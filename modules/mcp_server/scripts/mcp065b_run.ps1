# =============================================================================
#  mcp065b_run.ps1 -- TASK-065 section B orchestrator (pure ASCII).
#
#  Criteria:
#    5) scope narrowing: editor_list_signal_connections called for real on 9888
#       with default / "user" / "internal" (>=3 calls each) plus signal_name
#       combinations, with the returned sets, counts and byte sizes compared and
#       the set differences computed from the raw responses.
#    6) windowed changed:false / changed:true with --mcp-capture=every_call,
#       viewport=2d, scale=2, and the same before/after PNG pair verified three
#       ways (capture line / editor_analyze_screenshot_diff / mcp065b_pixel_recompute.py).
#    game live chain on 9889: input injected by one tool, position read back by
#       another over many frames, brick count and score read back before/after.
#
#  Observation coverage is provided by scripts/mcp_watch_run.ps1 and the run only
#  ends after the marker is written, so stop_reason must be "marker".
#
#  Port discipline: 9888 / 9889 only. Port 9877 is never occupied, killed or
#  restarted; the harness only ever stops the PIDs it started itself.
# =============================================================================

param(
    [int]$WatcherTimeoutSec = 1800,
    [int]$WatcherStaleSec = 600,
    [int]$WatcherIntervalSec = 5
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mcp065b_env.ps1')
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

# A failure anywhere below must not leave a windowed editor, a game process or a
# watcher behind: the trap stops the PIDs this harness started itself, writes the
# marker so the watcher's stop_reason is still a machine-readable "marker" (the
# run's own pass/fail is a separate field of run-summary.json), and re-raises.
$script:EditorProc = $null
$script:GameProc = $null
trap {
    $message = $_.Exception.Message
    Write-Host ('TRAP ' + $message)
    Add-Heartbeat ('TRAP ' + $message)
    if ($null -ne $script:EditorProc) { Stop-OwnProcess -Process $script:EditorProc }
    if ($null -ne $script:GameProc) { Stop-OwnProcess -Process $script:GameProc }
    [IO.File]::WriteAllText($MarkerFile, ('aborted: ' + $message + "`n"), (New-Object Text.UTF8Encoding($false)))
    exit 1
}

$Root = $EvidenceRoot
$LogDir = Join-Path $Root 'process-logs'
$ShotDir = Join-Path $Root 'shots'
$Phase5Dir = Join-Path $Root 'phase5-scope'
$Phase6Dir = Join-Path $Root 'phase6-capture'
$GameDir = Join-Path $Root 'game-live-chain'

$script:Started = (Get-Date).ToString('o', $InvariantCulture)
$script:Checks = New-Object System.Collections.Generic.List[object]
$script:EditorCalls = New-Object System.Collections.Generic.List[object]
$script:GameCalls = New-Object System.Collections.Generic.List[object]
$script:Notes = New-Object System.Collections.Generic.List[string]

# The byte size of the `connections` array inside one response, measured on the
# response's own bytes (not on a PowerShell re-serialisation, which would be a
# different number for the same value).
function Get-ConnArrayBytes($Call) {
    if ($null -eq $Call.Json.result.content) { return 0 }
    $text = [string]$Call.Json.result.content[0].text
    $key = $text.IndexOf('"connections":')
    if ($key -lt 0) { return 0 }
    $from = $text.IndexOf('[', $key)
    if ($from -lt 0) { return 0 }
    $to = $text.IndexOf(']', $from)
    if ($to -lt 0) { return 0 }
    $span = $text.Substring($from, ($to - $from + 1))
    return (New-Object Text.UTF8Encoding($false)).GetBytes($span).Length
}

function Add-Check([string]$Id, [bool]$Pass, [string]$Evidence) {
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = 'FAIL'
    if ($Pass) { $tag = 'PASS' }
    Write-Host ('[' + $tag + '] ' + $Id + ' :: ' + $Evidence)
}

function Note([string]$Text) {
    $script:Notes.Add($Text)
    Write-Host ('NOTE ' + $Text)
}

function Do-Call {
    param([int]$Port, [string]$Tool, $Arguments, [string]$Directory, [string]$Leaf, [string]$Kind = 'editor')
    $c = Invoke-Tool -Port $Port -Tool $Tool -Arguments $Arguments -Directory $Directory -Leaf $Leaf
    if ($Kind -eq 'editor') { $script:EditorCalls.Add($c) } else { $script:GameCalls.Add($c) }
    Add-Heartbeat ($Kind + ' call seq=' + $c.Seq + ' ' + $Tool + ' bytes=' + $c.ResponseBytes)
    Write-Host ('  [seq ' + $c.Seq + '] ' + $Tool + ' -> ' + $c.ResponseBytes + ' B sha8=' + $c.ResponseSha256.Substring(0, 8))
    return $c
}

function Get-ConnKey($c) {
    return ([string]$c.source + '|' + [string]$c.signal + '|' + [string]$c.target + '|' + [string]$c.method)
}

function Get-ConnSet($body) {
    if ($null -eq $body) { return @() }
    $out = @()
    foreach ($c in @($body.connections)) {
        if ($null -eq $c) { continue }
        $out += (Get-ConnKey $c)
    }
    return @($out | Sort-Object -Unique)
}

# The trace file is held open by the engine while it is running, so it must be
# read with a share mode that tolerates the writer (the same FileShare a reader
# needs; [IO.File]::ReadAllLines asks for FileShare.Read and is refused).
function Read-TextShared([string]$Path) {
    $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
        $stream.Dispose()
    }
}

function Get-SetDiff($a, $b) {
    return @($a | Where-Object { $b -notcontains $_ })
}

function Get-JsonSize($value) {
    return (New-Object Text.UTF8Encoding($false)).GetBytes(($value | ConvertTo-Json -Depth 12 -Compress)).Length
}

function Get-ArgsSha($Arguments) {
    return (Get-McpEvidenceContentSha256 -Text (($Arguments | ConvertTo-Json -Depth 20 -Compress)))
}

# The sha256 of the TOOL RESULT body (result.content[0].text), i.e. without the
# JSON-RPC envelope. The whole HTTP response cannot be compared across calls
# because each one carries its own `id`; the body is the part the tool answers.
function Get-BodySha($Call) {
    if ($null -eq $Call.Json) { return '' }
    if ($null -eq $Call.Json.result) { return '' }
    if ($null -eq $Call.Json.result.content) { return '' }
    return (Get-McpEvidenceContentSha256 -Text ([string]$Call.Json.result.content[0].text))
}

function Get-CaptureLines([string]$TracePath) {
    $rows = @()
    if (-not (Test-Path -LiteralPath $TracePath)) { return $rows }
    $text = Read-TextShared $TracePath
    foreach ($line in $text.Split("`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '"event"\s*:\s*"capture"') { continue }
        try { $rows += ($line.TrimEnd("`r") | ConvertFrom-Json) } catch { }
    }
    return $rows
}

function Wait-CaptureLines([string]$TracePath, [int]$Expected, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $rows = @()
    while ((Get-Date) -lt $deadline) {
        $rows = Get-CaptureLines $TracePath
        if ($rows.Count -ge $Expected) { return $rows }
        Start-Sleep -Milliseconds 250
    }
    return $rows
}

# =========================================================== 0. probe the ports
Write-Host '=== 0. port preconditions ==='
$portsBefore = Get-ListeningPorts
Add-Check 'p0_port_9877_no_listener_before' ((@($portsBefore) -notcontains 9877)) ('listening=' + (@($portsBefore) -join ','))
Add-Check 'p0_port_9888_free_before' ((@($portsBefore) -notcontains 9888)) ('listening=' + (@($portsBefore) -join ','))
Add-Check 'p0_port_9889_free_before' ((@($portsBefore) -notcontains 9889)) ('listening=' + (@($portsBefore) -join ','))

Ensure-Dir $IoRoot | Out-Null
if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
foreach ($d in @($Root, $LogDir, $ShotDir, $Phase5Dir, $Phase6Dir, $GameDir, $WatchOutDir)) { Ensure-Dir $d | Out-Null }
Remove-Item -LiteralPath $MarkerFile -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $EditorTrace -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $GameTrace -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ProgressFile -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $EditorProject 'mcp065b_shots') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $GameProject '.godot\mcp065b_build_state.json') -ErrorAction SilentlyContinue

Add-Heartbeat 'mcp065b_run start'
Add-Heartbeat ('binary=' + $ConsoleExe)
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'bin') -Filter 'godot.windows.editor.x86_64*.exe' | Sort-Object Name)) {
    Add-Heartbeat ('bin ' + $f.Name + ' bytes=' + $f.Length + ' mtime=' + $f.LastWriteTime.ToString('s', $InvariantCulture))
}

# ================================================== 1. fixtures + project import
Write-Host '=== 1. fixtures + import ==='
& (Join-Path $ScriptRoot 'mcp065b_fixtures.ps1') -EditorProject $EditorProject -GameProject $GameProject | Out-Null
Add-Heartbeat 'fixtures written'

$editorImport = Import-McpProject -Engine $ConsoleExe -Path $EditorProject -LogDirectory $LogDir -Name 'import-editor' -Port 0
$gameImport = Import-McpProject -Engine $ConsoleExe -Path $GameProject -LogDirectory $LogDir -Name 'import-game' -Port 0
Add-Check 'p1_editor_project_imported' ($editorImport.exit_code -eq 0) ('exit=' + $editorImport.exit_code + ' attempts=' + $editorImport.attempts)
Add-Check 'p1_game_project_imported' ($gameImport.exit_code -eq 0) ('exit=' + $gameImport.exit_code + ' attempts=' + $gameImport.attempts)

# ====================================================== 2. start the watcher
Write-Host '=== 2. watcher ==='
$watchLog = Join-Path $LogDir 'watch-stdout.log.txt'
$watchErr = Join-Path $LogDir 'watch-stderr.log.txt'
$watcherScript = Join-Path $ScriptRoot 'mcp_watch_run.ps1'
# `-TracePath` is an array parameter. Two traps, both measured here:
#   * `-File` refuses a parameter bound more than once ("ParameterAlreadyBound",
#     exit 2, and the whole observation is lost);
#   * `-File` does not split a comma list either - `a,b,c` arrives as ONE string
#     and the watcher then watches a single nonexistent path.
# So the watcher is started through `-EncodedCommand` with a real PowerShell
# command line, where `-TracePath 'a','b','c'` is an array again (and no path ever
# needs command-line quoting).
$traceArg = (@(
        ("'" + $EditorTrace.Replace("'", "''") + "'"),
        ("'" + $GameTrace.Replace("'", "''") + "'"),
        ("'" + $ProgressFile.Replace("'", "''") + "'")
    ) -join ',')
$watchCommand = "& '" + $watcherScript.Replace("'", "''") + "'" +
    " -Marker '" + $MarkerFile.Replace("'", "''") + "'" +
    " -TracePath " + $traceArg +
    " -TimeoutSec " + $WatcherTimeoutSec +
    " -StaleSec " + $WatcherStaleSec +
    " -IntervalSec " + $WatcherIntervalSec +
    " -OutDir '" + $WatchOutDir.Replace("'", "''") + "'"
Add-Heartbeat ('watcher command: ' + $watchCommand)
$watchEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($watchCommand))
$watchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $watchEncoded)
$watcher = Start-Process -FilePath 'powershell' -ArgumentList $watchArgs -PassThru -RedirectStandardOutput $watchLog -RedirectStandardError $watchErr
Add-Heartbeat ('watcher started pid=' + $watcher.Id)
Write-Host ('watcher pid=' + $watcher.Id)
Start-Sleep -Seconds 4
Add-Check 'w2_watcher_still_alive_after_start' (-not $watcher.HasExited) ('pid=' + $watcher.Id + ' stderr=' + $watchErr)
$watchLogFile = Join-Path $WatchOutDir 'watch.log'
Add-Check 'w2_watcher_wrote_its_log' (Test-Path -LiteralPath $watchLogFile) ('path=' + $watchLogFile)
Add-Check 'w2_watcher_received_three_trace_paths' (Select-String -LiteralPath $watchLogFile -Pattern 'trace_path\[2\]' -Quiet) ('the watch.log header names all three sources (guard against the comma-list-as-one-string failure)')

# ====================================================== 3. windowed editor 9888
Write-Host '=== 3. windowed editor 9888 ==='
$editorOut = Join-Path $LogDir 'editor.out.log.txt'
$editorErr = Join-Path $LogDir 'editor.err.log.txt'
$editorArgs = @(
    '-e', '--path', $EditorProject,
    ('--mcp-port=' + $EditorPort),
    ('--mcp-trace=' + ($EditorTrace -replace '\\', '/')),
    '--mcp-capture=every_call',
    '--mcp-capture-dir=res://mcp065b_shots',
    '--mcp-capture-viewport=2d',
    '--mcp-capture-scale=2'
)
$editor = Start-OwnProcess -Exe $ConsoleExe -EngineArgs $editorArgs -OutLog $editorOut -ErrLog $editorErr
$script:EditorProc = $editor
Add-Heartbeat ('editor pid=' + $editor.Id)
$up = Wait-Port -Port $EditorPort -TimeoutSec 180
Add-Check 'p3_editor_listening_9888' $up ('pid=' + $editor.Id + ' port=' + $EditorPort)
if (-not $up) { throw 'editor endpoint never came up on 9888' }
$capLine = Wait-LogLine -Path $editorOut -Pattern 'capture enabled' -TimeoutSec 60
Add-Check 'p3_capture_enabled_line' $capLine ('log=' + $editorOut)
$readyLine = Wait-LogLine -Path $editorOut -Pattern 'MCP server is ready' -TimeoutSec 60
Add-Check 'p3_editor_ready_line' $readyLine ('log=' + $editorOut)
Start-Sleep -Seconds 3

$editorProjectCalls = 0
$editorCallsForCapture = New-Object System.Collections.Generic.List[object]

# --- 3a. contract view and scene opening (also the positive control that the
#         2D editor viewport really renders this scene: the changed:true capture
#         below cannot be produced by a blank or frozen viewport).
$editorProjectCalls++ ; $null = Do-Call $EditorPort 'editor_get_scene_tree' @{ max_depth = -1 } $Root 'p3_scene_tree_before' 'editor'
$open = Do-Call $EditorPort 'editor_open_scene' @{ path = 'res://scenes/main.tscn' } $Root 'p3_open_scene' 'editor'
$openBody = Get-ToolBody $open
Add-Check 'p3_scene_opened' ((Get-ToolError $open) -eq '' -and ((Get-ToolBody $open).opened -eq $true)) ([string]$open.Raw)
Start-Sleep -Seconds 2
$gd = Do-Call $EditorPort 'editor_execute_gdscript' @{ code = "EditorInterface.set_main_screen_editor(`"2D`")`nreturn `"ok`"" } $Root 'p3_main_screen_2d' 'editor'
Add-Check 'p3_main_screen_is_2d' ((Get-ToolError $gd) -eq '' -and ((Get-ToolBody $gd).result -eq 'ok')) ([string]$gd.Raw)
Start-Sleep -Seconds 2
$tree = Do-Call $EditorPort 'editor_get_scene_tree' @{ max_depth = -1 } $Root 'p3_scene_tree_after' 'editor'
$treeBody = Get-ToolBody $tree
$treeJson = ($treeBody | ConvertTo-Json -Depth 25 -Compress)
Add-Check 'p3_edited_scene_is_the_fixture' (([string]$treeBody.scene_path -eq 'res://scenes/main.tscn') -and ($treeJson -match '"Box"')) ('scene_path=' + $treeBody.scene_path + ' Box in tree: ' + ($treeJson -match '"Box"'))
Add-Check 'p3_scene_root_lives_in_the_2d_subviewport' (($treeJson -match 'EditorMainScreen') -and ($treeJson -match 'SubViewport')) ('the edited scene is parented under the editor 2D main screen SubViewport')

# ==================================================== 4. criterion 5: scope
Write-Host '=== 4. criterion 5: scope narrowing ==='
$scopeCalls = New-Object System.Collections.Generic.List[object]
# The parameter must NOT be called `$Args`: that is PowerShell's automatic
# argument array, and binding it that way silently sent `"arguments":[]` for
# every scope call in the first run of this harness.
function Scope-Call([string]$Leaf, $Arguments) {
    $c = Do-Call $EditorPort 'editor_list_signal_connections' $Arguments $Phase5Dir $Leaf 'editor'
    $scopeCalls.Add($c)
    return $c
}
$d1 = Scope-Call 'p5_default_1' @{}
$d2 = Scope-Call 'p5_default_2' @{}
$d3 = Scope-Call 'p5_default_3' @{}
$u1 = Scope-Call 'p5_user_1' @{ scope = 'user' }
$u2 = Scope-Call 'p5_user_2' @{ scope = 'user' }
$u3 = Scope-Call 'p5_user_3' @{ scope = 'user' }
$i1 = Scope-Call 'p5_internal_1' @{ scope = 'internal' }
$i2 = Scope-Call 'p5_internal_2' @{ scope = 'internal' }
$i3 = Scope-Call 'p5_internal_3' @{ scope = 'internal' }
$ut1 = Scope-Call 'p5_user_timeout_1' @{ scope = 'user'; signal_name = 'timeout' }
$ut2 = Scope-Call 'p5_user_timeout_2' @{ scope = 'user'; signal_name = 'timeout' }
$ut3 = Scope-Call 'p5_user_timeout_3' @{ scope = 'user'; signal_name = 'timeout' }
$it1 = Scope-Call 'p5_internal_timeout_1' @{ scope = 'internal'; signal_name = 'timeout' }
$it2 = Scope-Call 'p5_internal_timeout_2' @{ scope = 'internal'; signal_name = 'timeout' }
$it3 = Scope-Call 'p5_internal_timeout_3' @{ scope = 'internal'; signal_name = 'timeout' }
$dt1 = Scope-Call 'p5_default_timeout_1' @{ signal_name = 'timeout' }
$dt2 = Scope-Call 'p5_default_timeout_2' @{ signal_name = 'timeout' }
$dt3 = Scope-Call 'p5_default_timeout_3' @{ signal_name = 'timeout' }
$allExplicit = Scope-Call 'p5_all_explicit' @{ scope = 'all' }
$bogus = Scope-Call 'p5_bogus_scope' @{ scope = 'bogus' }

$dBody = Get-ToolBody $d1
$uBody = Get-ToolBody $u1
$iBody = Get-ToolBody $i1
$utBody = Get-ToolBody $ut1
$itBody = Get-ToolBody $it1
$dtBody = Get-ToolBody $dt1
$allBody = Get-ToolBody $allExplicit

$dSet = Get-ConnSet $dBody
$uSet = Get-ConnSet $uBody
$iSet = Get-ConnSet $iBody
$utSet = Get-ConnSet $utBody
$itSet = Get-ConnSet $itBody
$dtSet = Get-ConnSet $dtBody

Add-Check 'c5_default_call_answered' ($null -ne $dBody -and $dSet.Count -gt 0) ('count=' + $dSet.Count + ' bytes=' + $d1.ResponseBytes)
Add-Check 'c5_user_call_answered' ($null -ne $uBody) ('count=' + $uSet.Count + ' bytes=' + $u1.ResponseBytes)
Add-Check 'c5_internal_call_answered' ($null -ne $iBody) ('count=' + $iSet.Count + ' bytes=' + $i1.ResponseBytes)

$scopeEchoOk = $true
$expectedScopes = @(
    @($d1, 'all'), @($d2, 'all'), @($d3, 'all'),
    @($u1, 'user'), @($u2, 'user'), @($u3, 'user'),
    @($i1, 'internal'), @($i2, 'internal'), @($i3, 'internal'),
    @($ut1, 'user'), @($ut2, 'user'), @($ut3, 'user'),
    @($it1, 'internal'), @($it2, 'internal'), @($it3, 'internal'),
    @($dt1, 'all'), @($dt2, 'all'), @($dt3, 'all'),
    @($allExplicit, 'all')
)
foreach ($pair in $expectedScopes) {
    $body = Get-ToolBody $pair[0]
    if ($null -eq $body -or ([string]$body.scope) -ne [string]$pair[1]) { $scopeEchoOk = $false }
}
Add-Check 'c5_scope_field_echoes_the_request' $scopeEchoOk 'default -> all, user -> user, internal -> internal (20 calls)'

$userHasNoDoubleColon = $true
foreach ($c in @($uBody.connections)) { if (([string]$c.method).Contains('::')) { $userHasNoDoubleColon = $false } }
$internalAllDoubleColon = $true
foreach ($c in @($iBody.connections)) { if (-not ([string]$c.method).Contains('::')) { $internalAllDoubleColon = $false } }
Add-Check 'c5_user_contains_only_scene_side_methods' $userHasNoDoubleColon ('user methods: ' + ((@($uBody.connections) | ForEach-Object { [string]$_.method }) -join ','))
Add-Check 'c5_internal_contains_only_class_method_bindings' $internalAllDoubleColon ('internal methods all contain ::; count=' + (@($iBody.connections).Count))

$symDiff1 = Get-SetDiff $dSet $uSet
$disjoint = @()
foreach ($k in $uSet) { if ($iSet -contains $k) { $disjoint += $k } }
$recomposed = @($uSet + $iSet | Sort-Object -Unique)
$setRecomposes = (($recomposed.Count -eq $dSet.Count) -and ((Get-SetDiff $recomposed $dSet).Count -eq 0) -and ($symDiff1.Count -eq $iSet.Count))
Add-Check 'c5_user_and_internal_partition_the_default_set' $setRecomposes ('default=' + $dSet.Count + ' user=' + $uSet.Count + ' internal=' + $iSet.Count + ' disjoint=' + $disjoint.Count + ' default_minus_user=' + $symDiff1.Count)

$countsOk = $true
$countsEvidence = ''
foreach ($entry in @(
        @($d1, 'all'), @($d2, 'all'), @($d3, 'all'),
        @($u1, 'user'), @($u2, 'user'), @($u3, 'user'),
        @($i1, 'internal'), @($i2, 'internal'), @($i3, 'internal'),
        @($ut1, 'user'), @($ut2, 'user'), @($ut3, 'user'),
        @($it1, 'internal'), @($it2, 'internal'), @($it3, 'internal'),
        @($dt1, 'all'), @($dt2, 'all'), @($dt3, 'all'),
        @($allExplicit, 'all'))) {
    $b = Get-ToolBody $entry[0]
    $scope = [string]$entry[1]
    $returned = @($b.connections).Count
    $expected = 0
    if ($scope -eq 'all') { $expected = [int]$b.counts.all }
    if ($scope -eq 'user') { $expected = [int]$b.counts.user }
    if ($scope -eq 'internal') { $expected = [int]$b.counts.internal }
    $invariant = (([int]$b.counts.user + [int]$b.counts.internal) -eq [int]$b.counts.all) -and
                 ([int]$b.count -eq $returned) -and ($returned -eq $expected) -and ([string]$b.scope -eq $scope)
    if (-not $invariant) { $countsOk = $false }
    $countsEvidence = $countsEvidence + ('[' + $scope + ':' + $b.count + '/' + $returned + ' expected=' + $expected + ' counts=' + $b.counts.all + '-' + $b.counts.user + '-' + $b.counts.internal + ']')
}
Add-Check 'c5_count_and_counts_are_self_consistent' $countsOk $countsEvidence
$breakdownOk = ([int]$dBody.counts.all -eq $dSet.Count) -and ([int]$dBody.counts.user -eq $uSet.Count) -and ([int]$dBody.counts.internal -eq $iSet.Count) -and
               ([int]$dtBody.counts.all -eq $dtSet.Count) -and ([int]$dtBody.counts.user -eq $utSet.Count) -and ([int]$dtBody.counts.internal -eq $itSet.Count)
Add-Check 'c5_counts_match_the_independently_computed_sets' $breakdownOk ('unfiltered counts=' + $dBody.counts.all + '-' + $dBody.counts.user + '-' + $dBody.counts.internal + ' vs sets ' + $dSet.Count + '/' + $uSet.Count + '/' + $iSet.Count + '; signal_name=timeout counts=' + $dtBody.counts.all + '-' + $dtBody.counts.user + '-' + $dtBody.counts.internal + ' vs sets ' + $dtSet.Count + '/' + $utSet.Count + '/' + $itSet.Count)

$defaultBodyShas = @((Get-BodySha $d1), (Get-BodySha $d2), (Get-BodySha $d3))
$userBodyShas = @((Get-BodySha $u1), (Get-BodySha $u2), (Get-BodySha $u3))
$internalBodyShas = @((Get-BodySha $i1), (Get-BodySha $i2), (Get-BodySha $i3))
$deterministic = ((@($defaultBodyShas | Sort-Object -Unique).Count) -eq 1) -and ((@($userBodyShas | Sort-Object -Unique).Count) -eq 1) -and ((@($internalBodyShas | Sort-Object -Unique).Count) -eq 1)
Add-Check 'c5_three_calls_per_scope_have_identical_result_bodies' $deterministic ('default body sha8=' + ([string]$defaultBodyShas[0]).Substring(0, 8) + ' user body sha8=' + ([string]$userBodyShas[0]).Substring(0, 8) + ' internal body sha8=' + ([string]$internalBodyShas[0]).Substring(0, 8) + ' (the JSON-RPC envelope ids differ, the answer does not)')
Add-Check 'c5_explicit_all_equals_the_default' ((Get-BodySha $allExplicit) -eq (Get-BodySha $d1)) ('explicit all body sha8=' + (Get-BodySha $allExplicit).Substring(0, 8) + ' default body sha8=' + (Get-BodySha $d1).Substring(0, 8))

Add-Check 'c5_user_answer_differs_from_default' ((Get-BodySha $u1) -ne (Get-BodySha $d1)) ('user bytes=' + $u1.ResponseBytes + ' default bytes=' + $d1.ResponseBytes)
Add-Check 'c5_internal_answer_differs_from_default' ((Get-BodySha $i1) -ne (Get-BodySha $d1)) ('internal bytes=' + $i1.ResponseBytes + ' default bytes=' + $d1.ResponseBytes)

$dtUnion = @($utSet + $itSet | Sort-Object -Unique)
$comboOk = (($dtUnion.Count -eq $dtSet.Count) -and ((Get-SetDiff $dtUnion $dtSet).Count -eq 0) -and ((Get-SetDiff $dtSet $dtUnion).Count -eq 0))
$subsetOk = ((Get-SetDiff $utSet $uSet).Count -eq 0) -and ((Get-SetDiff $itSet $iSet).Count -eq 0) -and ((Get-SetDiff $dtSet $dSet).Count -eq 0)
Add-Check 'c5_signal_name_and_scope_compose' ($comboOk -and $subsetOk) ('signal_name=timeout: default=' + $dtSet.Count + ' user=' + $utSet.Count + ' internal=' + $itSet.Count + ' user+internal=default: ' + $comboOk + '; all three subsets of their scope: ' + $subsetOk)
Add-Check 'c5_signal_name_filter_keeps_the_whole_user_set' (($utSet.Count -eq $uSet.Count) -and ($uSet -contains 'Timer|timeout|.|_on_timer_timeout') -and ($uSet -contains 'Marker|timeout|.|_on_timer_two_timeout')) ('user=' + $uSet.Count + ' user+timeout=' + $utSet.Count + ' both fixture connections present: ' + (($uSet -contains 'Timer|timeout|.|_on_timer_timeout') -and ($uSet -contains 'Marker|timeout|.|_on_timer_two_timeout')))
Add-Check 'c5_signal_name_filter_drops_every_internal_connection' ($itSet.Count -eq 0) ('internal+timeout=' + $itSet.Count + ' while internal=' + $iSet.Count)

$bogusIsError = ($null -ne $bogus.Json.error) -and ([int]$bogus.Json.error.code -eq -32602)
$bogusNamesEnum = (([string]$bogus.Raw) -match 'all') -and (([string]$bogus.Raw) -match 'user') -and (([string]$bogus.Raw) -match 'internal')
Add-Check 'c5_unknown_scope_is_refused_with_the_enum' ($bogusIsError -and $bogusNamesEnum) ([string]$bogus.Raw)

$connBytesDefault = Get-ConnArrayBytes $d1
$connBytesUser = Get-ConnArrayBytes $u1
$connBytesInternal = Get-ConnArrayBytes $i1

$phase5 = [ordered]@{
    tool = 'editor_list_signal_connections'
    port = $EditorPort
    calls = @($scopeCalls | ForEach-Object { [ordered]@{ seq = $_.Seq; tool = $_.Tool; request = $_.RequestPath; request_sha256 = $_.RequestSha256; response = $_.ResponsePath; response_sha256 = $_.ResponseSha256; response_bytes = $_.ResponseBytes; scope = [string](Get-ToolBody $_).scope; count = (Get-ToolBody $_).count } })
    default_set = $dSet
    user_set = $uSet
    internal_set = $iSet
    user_set_minus_default = (Get-SetDiff $uSet $dSet)
    default_set_minus_user = (Get-SetDiff $dSet $uSet)
    default_set_minus_internal = (Get-SetDiff $dSet $iSet)
    user_internal_intersection = $disjoint
    sizes = [ordered]@{ default_count = $dSet.Count; user_count = $uSet.Count; internal_count = $iSet.Count; default_response_bytes = $d1.ResponseBytes; user_response_bytes = $u1.ResponseBytes; internal_response_bytes = $i1.ResponseBytes; default_connections_json_bytes = $connBytesDefault; user_connections_json_bytes = $connBytesUser; internal_connections_json_bytes = $connBytesInternal }
    signal_name_timeout = [ordered]@{ default_set = $dtSet; user_set = $utSet; internal_set = $itSet }
    scope_all_explicit_response_sha256 = $allExplicit.ResponseSha256
    default_response_sha256 = $d1.ResponseSha256
    user_response_sha256 = $u1.ResponseSha256
    internal_response_sha256 = $i1.ResponseSha256
    default_body_sha256 = (Get-BodySha $d1)
    user_body_sha256 = (Get-BodySha $u1)
    internal_body_sha256 = (Get-BodySha $i1)
    scope_all_explicit_body_sha256 = (Get-BodySha $allExplicit)
    bogus_scope_response = $bogus.Raw
}
[IO.File]::WriteAllText((Join-Path $Root 'phase5_scope.json'), ($phase5 | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))

# ============================================ 5. criterion 6: windowed capture
Write-Host '=== 5. criterion 6: windowed changed:false / changed:true ==='
$c6ReadA = Do-Call $EditorPort 'editor_get_scene_tree' @{ max_depth = -1 } $Phase6Dir 'p6_read_only_a' 'editor'
$i6ReadA = $script:EditorCalls.Count - 1
$readArgs = @{ max_depth = -1 }
$c6ReadB = Do-Call $EditorPort 'editor_get_scene_tree' $readArgs $Phase6Dir 'p6_read_only_b_replay' 'editor'
$i6ReadB = $script:EditorCalls.Count - 1
$moveArgs = @{ path = 'Box'; property = 'position'; value = @{ x = 200; y = 120 } }
$moveArgsSha = Get-ArgsSha $moveArgs
$c6MoveA = Do-Call $EditorPort 'editor_set_node_property' $moveArgs $Phase6Dir 'p6_real_change' 'editor'
$i6MoveA = $script:EditorCalls.Count - 1
Start-Sleep -Milliseconds 400
$c6Replay = Do-Call $EditorPort 'editor_set_node_property' $moveArgs $Phase6Dir 'p6_same_args_same_value_replay' 'editor'
$i6Replay = $script:EditorCalls.Count - 1

$moveBody = Get-ToolBody $c6MoveA
$replayBody = Get-ToolBody $c6Replay
Add-Check 'c6_real_change_reported_success' (((Get-ToolError $c6MoveA) -eq '') -and ([double]$moveBody.old_value.x -eq 40) -and ([double]$moveBody.new_value.x -eq 200)) ([string]$c6MoveA.Raw)
Add-Check 'c6_replay_sent_byte_identical_arguments' ($moveArgsSha -eq (Get-ArgsSha $moveArgs)) ('arguments sha256=' + $moveArgsSha.Substring(0, 16) + ' (one object used for both calls)')
Add-Check 'c6_read_only_replay_sent_byte_identical_arguments' ((Get-ArgsSha $readArgs) -eq (Get-ArgsSha @{ max_depth = -1 })) ('arguments sha256=' + (Get-ArgsSha $readArgs).Substring(0, 16))
Add-Check 'c6_replay_reported_success_with_the_same_value' (((Get-ToolError $c6Replay) -eq '') -and ([double]$replayBody.old_value.x -eq 200) -and ([double]$replayBody.new_value.x -eq 200) -and ([double]$replayBody.old_value.y -eq 120)) ([string]$c6Replay.Raw)

# --- the evidence guard's snapshot pair: main.tscn before -> between -> after,
#     with the two digests required to differ.
$sceneFile = Join-Path $EditorProject 'scenes\main.tscn'
$pair = Write-McpEvidenceSnapshotPair -Directory $Phase6Dir -Leaf 'p6_main_tscn' -Extension '.tscn' `
    -Before { [IO.File]::ReadAllBytes($sceneFile) } `
    -Between {
        $null = Do-Call $EditorPort 'editor_set_node_property' @{ path = 'Box'; property = 'position'; value = @{ x = 260; y = 150 } } $Phase6Dir 'p6_snapshot_between_change' 'editor'
        $null = Do-Call $EditorPort 'editor_save_scene' @{ path = 'res://scenes/main.tscn' } $Phase6Dir 'p6_snapshot_between_save' 'editor'
    } `
    -After { [IO.File]::ReadAllBytes($sceneFile) }
Add-Check 'c6_snapshot_pair_differs' (-not $pair.Identical) ('before sha8=' + $pair.BeforeSha256.Substring(0, 8) + ' after sha8=' + $pair.AfterSha256.Substring(0, 8) + ' (before -> change+save -> after)')

Start-Sleep -Milliseconds 800
$capsEarly = Wait-CaptureLines -TracePath $EditorTrace -Expected $script:EditorCalls.Count -TimeoutSec 10
Add-Check 'c6_every_editor_call_produced_one_capture_line_so_far' ($capsEarly.Count -eq $script:EditorCalls.Count) ('capture_lines=' + $capsEarly.Count + ' editor_tools_calls=' + $script:EditorCalls.Count)
$capReadA = $capsEarly[$i6ReadA]
$capReadB = $capsEarly[$i6ReadB]
$capMoveA = $capsEarly[$i6MoveA]
$capReplay = $capsEarly[$i6Replay]

Add-Check 'c6_capture_viewport_and_scale' (([string]$capMoveA.viewport -eq '2d') -and ([int]$capMoveA.scale -eq 2)) ('viewport=' + $capMoveA.viewport + ' scale=' + $capMoveA.scale + ' mode=' + $capMoveA.mode)
Add-Check 'c6_capture_status_done_not_unavailable' (([string]$capMoveA.status -eq 'done') -and ([string]$capReplay.status -eq 'done')) ('move status=' + $capMoveA.status + ' replay status=' + $capReplay.status + ' (headless would be unavailable)')
Add-Check 'c6_capture_waited_at_least_one_rendered_frame' (([int]$capMoveA.frames_waited -ge 1) -and ([int]$capReplay.frames_waited -ge 1)) ('frames_waited move=' + $capMoveA.frames_waited + ' replay=' + $capReplay.frames_waited)

Add-Check 'c6_real_change_is_changed_true' (($capMoveA.changed -eq $true) -and ([int]$capMoveA.changed_pixels -gt 0) -and ([double]$capMoveA.changed_pixel_ratio -gt 0)) ('changed=' + $capMoveA.changed + ' changed_pixels=' + $capMoveA.changed_pixels + ' total_pixels=' + $capMoveA.total_pixels + ' ratio=' + $capMoveA.changed_pixel_ratio)
Add-Check 'c6_same_args_same_value_replay_is_changed_false' (($capReplay.changed -eq $false) -and ([int]$capReplay.changed_pixels -eq 0) -and ([double]$capReplay.changed_pixel_ratio -eq 0.0)) ('changed=' + $capReplay.changed + ' changed_pixels=' + $capReplay.changed_pixels + ' ratio=' + $capReplay.changed_pixel_ratio + ' while the tool reported a successful write')
Add-Check 'c6_read_only_replays_are_changed_false' (($capReadA.changed -eq $false) -and ($capReadB.changed -eq $false)) ('read_a changed=' + $capReadA.changed + ' read_b changed=' + $capReadB.changed)

# --- route 2: the tool reads the same two PNGs the capture wrote.
$diffObj = Do-Call $EditorPort 'editor_analyze_screenshot_diff' @{ image_a = [string]$capMoveA.before.path; image_b = [string]$capMoveA.after.path } $Phase6Dir 'p6_tool_diff_real_change' 'editor'
$diffBody = Get-ToolBody $diffObj
$diffSame = Do-Call $EditorPort 'editor_analyze_screenshot_diff' @{ image_a = [string]$capReplay.before.path; image_b = [string]$capReplay.after.path } $Phase6Dir 'p6_tool_diff_idempotent_replay' 'editor'
$diffSameBody = Get-ToolBody $diffSame
Add-Check 'c6_tool_route_reproduces_the_capture_numbers' (($diffBody.changed_pixels -eq $capMoveA.changed_pixels) -and ($diffBody.total_pixels -eq $capMoveA.total_pixels)) ('tool=' + $diffBody.changed_pixels + '/' + $diffBody.total_pixels + ' capture=' + $capMoveA.changed_pixels + '/' + $capMoveA.total_pixels + ' identical=' + $diffBody.identical)
Add-Check 'c6_tool_route_agrees_on_the_idempotent_pair' (($diffSameBody.identical -eq $true) -and ([int]$diffSameBody.changed_pixels -eq 0)) ('identical=' + $diffSameBody.identical + ' changed_pixels=' + $diffSameBody.changed_pixels + ' total=' + $diffSameBody.total_pixels)

Start-Sleep -Milliseconds 800
$caps = Wait-CaptureLines -TracePath $EditorTrace -Expected $script:EditorCalls.Count -TimeoutSec 10
Add-Check 'c6_every_editor_call_produced_one_capture_line' ($caps.Count -eq $script:EditorCalls.Count) ('capture_lines=' + $caps.Count + ' editor_tools_calls=' + $script:EditorCalls.Count)
$capToolMismatch = @()
for ($k = 0; $k -lt $script:EditorCalls.Count -and $k -lt $caps.Count; $k++) {
    if ([string]$caps[$k].tool -ne [string]$script:EditorCalls[$k].Tool) {
        $capToolMismatch += ('' + $k + ':' + $caps[$k].tool + '!=' + $script:EditorCalls[$k].Tool)
    }
}
Add-Check 'c6_capture_lines_map_one_to_one_to_the_calls' ($capToolMismatch.Count -eq 0) ('mismatches=' + ($capToolMismatch -join ';') + ' (ordered capture table vs ordered call table)')

# --- copy the two pairs out of the project, verify the bytes, then route 3.
$shotHost = Join-Path $EditorProject 'mcp065b_shots'
$pairsForRecompute = @()
function Copy-Shot([string]$ResPath, [string]$Target) {
    $leaf = Split-Path -Leaf $ResPath
    $src = Join-Path $shotHost $leaf
    if (-not (Test-Path -LiteralPath $src)) { throw ('capture PNG missing: ' + $src) }
    [IO.File]::WriteAllBytes($Target, [IO.File]::ReadAllBytes($src))
    $h1 = (Get-FileHash -Algorithm SHA256 -LiteralPath $src).Hash.ToLower()
    $h2 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Target).Hash.ToLower()
    if ($h1 -ne $h2) { throw ('copied PNG differs: ' + $Target) }
    return $h1
}
foreach ($spec in @(
    @{ label = 'real_change'; cap = $capMoveA; log_cp = $capMoveA.changed_pixels; log_tp = $capMoveA.total_pixels; tool_cp = $diffBody.changed_pixels; tool_tp = $diffBody.total_pixels },
    @{ label = 'same_args_same_value_replay'; cap = $capReplay; log_cp = 0; log_tp = $capReplay.total_pixels; tool_cp = $diffSameBody.changed_pixels; tool_tp = $diffSameBody.total_pixels }
)) {
    $b = Copy-Shot ([string]$spec.cap.before.path) (Join-Path $ShotDir ('' + $spec.label + '.before.png'))
    $a = Copy-Shot ([string]$spec.cap.after.path) (Join-Path $ShotDir ('' + $spec.label + '.after.png'))
    $pairsForRecompute += [ordered]@{
        label = $spec.label
        before = (Join-Path $ShotDir ('' + $spec.label + '.before.png'))
        after = (Join-Path $ShotDir ('' + $spec.label + '.after.png'))
        before_sha256 = $b
        after_sha256 = $a
        threshold = 10
        log_changed_pixels = $spec.log_cp
        log_total_pixels = $spec.log_tp
        tool_changed_pixels = $spec.tool_cp
        tool_total_pixels = $spec.tool_tp
    }
}
$pairsFile = Join-Path $IoRoot 'pixel-pairs.json'
[IO.File]::WriteAllText($pairsFile, ($pairsForRecompute | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
$recomputeFile = Join-Path $Root 'pixel_recompute.json'
& python (Join-Path $ScriptRoot 'mcp065b_pixel_recompute.py') $pairsFile $recomputeFile | Write-Host
$recompute = ([IO.File]::ReadAllText($recomputeFile) | ConvertFrom-Json)
Add-Check 'c6_independent_recompute_agrees_with_capture_and_tool' ([bool]$recompute.all_three_routes_agree) ('pairs=' + @($recompute.pairs).Count + ' rule=max per-channel byte diff > 10')

$phase6 = [ordered]@{
    capture_argv = @('--mcp-capture=every_call', '--mcp-capture-dir=res://mcp065b_shots', '--mcp-capture-viewport=2d', '--mcp-capture-scale=2')
    headless = $false
    windowed = $true
    calls = @($script:EditorCalls | ForEach-Object { [ordered]@{ seq = $_.Seq; tool = $_.Tool; request = $_.RequestPath; request_sha256 = $_.RequestSha256; response = $_.ResponsePath; response_sha256 = $_.ResponseSha256; response_bytes = $_.ResponseBytes } })
    capture_lines = @($caps | ForEach-Object { [ordered]@{ seq = $_.seq; tool = $_.tool; status = $_.status; viewport = $_.viewport; scale = $_.scale; changed = $_.changed; changed_pixels = $_.changed_pixels; total_pixels = $_.total_pixels; changed_pixel_ratio = $_.changed_pixel_ratio; frames_waited = $_.frames_waited; before = $_.before.path; after = $_.after.path; before_sha256 = $_.before.sha256; after_sha256 = $_.after.sha256 } })
    real_change_capture = @($capMoveA | ForEach-Object { [ordered]@{ seq = $_.seq; changed = $_.changed; changed_pixels = $_.changed_pixels; total_pixels = $_.total_pixels; changed_pixel_ratio = $_.changed_pixel_ratio; before = $_.before.path; after = $_.after.path } })
    replay_capture = @($capReplay | ForEach-Object { [ordered]@{ seq = $_.seq; changed = $_.changed; changed_pixels = $_.changed_pixels; total_pixels = $_.total_pixels; changed_pixel_ratio = $_.changed_pixel_ratio; before = $_.before.path; after = $_.after.path } })
    replay_arguments_sha256 = $moveArgsSha
    real_change_response = @($c6MoveA | ForEach-Object { [ordered]@{ response = $_.ResponsePath; response_sha256 = $_.ResponseSha256; body = [string]$_.Raw } })
    replay_response = @($c6Replay | ForEach-Object { [ordered]@{ response = $_.ResponsePath; response_sha256 = $_.ResponseSha256; body = [string]$_.Raw } })
    tool_route_real_change = [ordered]@{ response = $diffObj.ResponsePath; response_sha256 = $diffObj.ResponseSha256; changed_pixels = $diffBody.changed_pixels; total_pixels = $diffBody.total_pixels; diff_percentage = $diffBody.diff_percentage; identical = $diffBody.identical; threshold = $diffBody.threshold }
    tool_route_replay = [ordered]@{ response = $diffSame.ResponsePath; response_sha256 = $diffSame.ResponseSha256; changed_pixels = $diffSameBody.changed_pixels; total_pixels = $diffSameBody.total_pixels; identical = $diffSameBody.identical }
    snapshot_pair = [ordered]@{ before = $pair.Before; after = $pair.After; before_sha256 = $pair.BeforeSha256; after_sha256 = $pair.AfterSha256; identical = $pair.Identical }
    pixel_recompute = $recompute
}
[IO.File]::WriteAllText((Join-Path $Root 'phase6_capture.json'), ($phase6 | ConvertTo-Json -Depth 14), (New-Object Text.UTF8Encoding($false)))

# =========================================================== 6. stop the editor
Write-Host '=== 6. stop editor ==='
Stop-OwnProcess -Process $editor -LogPath $editorOut
Start-Sleep -Seconds 4
Add-Check 'p6_port_9888_released' ((@(Get-ListeningPorts) -notcontains 9888)) ('listening=' + (@(Get-ListeningPorts) -join ','))

# ==================================================== 7. game live chain 9889
Write-Host '=== 7. game live chain 9889 ==='
$gameOut = Join-Path $LogDir 'game.out.log.txt'
$gameErr = Join-Path $LogDir 'game.err.log.txt'
$gameArgs = @('--headless', '--path', $GameProject, ('--mcp-port=' + $GamePort), ('--mcp-trace=' + ($GameTrace -replace '\\', '/')))
$game = Start-OwnProcess -Exe $ConsoleExe -EngineArgs $gameArgs -OutLog $gameOut -ErrLog $gameErr
$script:GameProc = $game
Add-Heartbeat ('game pid=' + $game.Id)
$gUp = Wait-Port -Port $GamePort -TimeoutSec 180
Add-Check 'g7_game_listening_9889' $gUp ('pid=' + $game.Id)
if (-not $gUp) { throw 'game endpoint never came up on 9889' }
$gRole = Wait-LogLine -Path $gameOut -Pattern 'role=game' -TimeoutSec 60
Add-Check 'g7_game_role_line' $gRole ('log=' + $gameOut)
Add-Check 'g7_game_endpoint_never_said_bind_failed' (-not (Wait-LogLine -Path $gameOut -Pattern 'bind failed' -TimeoutSec 1)) ('the round-2 D-7 silent-disable signature is absent')
Start-Sleep -Seconds 3

$gInfo = Do-Call $GamePort 'project_get_info' @{} $GameDir 'g7_game_project_info' 'game'
$gTreeBefore = Do-Call $GamePort 'running_game_get_scene_tree' @{ max_depth = -1 } $GameDir 'g7_scene_tree_before' 'game'
$gPaddleBefore = Do-Call $GamePort 'running_game_get_node_properties' @{ node_path = 'Paddle'; properties = @('position') } $GameDir 'g7_paddle_position_before' 'game'
$gBricksBefore = Do-Call $GamePort 'running_game_find_nodes_by_script' @{ script = 'res://scripts/brick.gd' } $GameDir 'g7_bricks_before' 'game'
$gScoreBefore = Do-Call $GamePort 'running_game_get_node_properties' @{ node_path = 'HUD/ScoreLabel'; properties = @('text') } $GameDir 'g7_score_text_before' 'game'

$gPress = Do-Call $GamePort 'running_game_run_test_scenario' @{ steps = @(@{ type = 'input'; action = 'paddle_right'; pressed = $true }) } $GameDir 'g7_inject_paddle_right' 'game'
$gSamples = Do-Call $GamePort 'running_game_get_node_property_samples' @{ node_path = 'Paddle'; properties = @('position'); frame_count = 24; frame_interval = 1 } $GameDir 'g7_paddle_position_samples' 'game'
$gPaddleAfter = Do-Call $GamePort 'running_game_get_node_properties' @{ node_path = 'Paddle'; properties = @('position', 'moves') } $GameDir 'g7_paddle_position_after' 'game'
$gRelease = Do-Call $GamePort 'running_game_run_test_scenario' @{ steps = @(@{ type = 'input'; action = 'paddle_right'; pressed = $false }, @{ type = 'assert'; node_path = 'Paddle'; property = 'moves'; operator = 'gt'; expected = 0 }) } $GameDir 'g7_release_and_assert_moves' 'game'

$gLaunch = Do-Call $GamePort 'running_game_run_test_scenario' @{ steps = @(@{ type = 'input'; action = 'launch'; pressed = $true }) } $GameDir 'g7_inject_launch' 'game'
$gBallSamples = Do-Call $GamePort 'running_game_get_node_property_samples' @{ node_path = 'Ball'; properties = @('position'); frame_count = 18; frame_interval = 1 } $GameDir 'g7_ball_position_samples' 'game'
$gHit = Do-Call $GamePort 'running_game_run_test_scenario' @{ steps = @(@{ type = 'wait'; seconds = 1.2 }, @{ type = 'input'; action = 'launch'; pressed = $false }, @{ type = 'assert'; node_path = 'Main'; property = 'score'; operator = 'gt'; expected = 0 }) } $GameDir 'g7_wait_and_assert_score' 'game'
$gBricksAfter = Do-Call $GamePort 'running_game_find_nodes_by_script' @{ script = 'res://scripts/brick.gd' } $GameDir 'g7_bricks_after' 'game'
$gScoreAfter = Do-Call $GamePort 'running_game_get_node_properties' @{ node_path = 'HUD/ScoreLabel'; properties = @('text') } $GameDir 'g7_score_text_after' 'game'
$gTreeAfter = Do-Call $GamePort 'running_game_get_scene_tree' @{ max_depth = -1 } $GameDir 'g7_scene_tree_after' 'game'

$bodyPaddleBefore = Get-ToolBody $gPaddleBefore
$bodyPaddleAfter = Get-ToolBody $gPaddleAfter
$bodySamples = Get-ToolBody $gSamples
$bodyBallSamples = Get-ToolBody $gBallSamples
$bodyBricksBefore = Get-ToolBody $gBricksBefore
$bodyBricksAfter = Get-ToolBody $gBricksAfter
$bodyScoreBefore = Get-ToolBody $gScoreBefore
$bodyScoreAfter = Get-ToolBody $gScoreAfter
$bodyHit = Get-ToolBody $gHit
$bodyRelease = Get-ToolBody $gRelease

$xBefore = [double]$bodyPaddleBefore.properties.position.x
$xAfter = [double]$bodyPaddleAfter.properties.position.x
$sampleXs = @()
foreach ($s in @($bodySamples.samples)) { $sampleXs += [double]$s.position.x }
$monotonic = $true
$distinct = @($sampleXs | Sort-Object -Unique).Count
for ($k = 1; $k -lt $sampleXs.Count; $k++) { if ($sampleXs[$k] -lt $sampleXs[$k - 1]) { $monotonic = $false } }
Add-Check 'g7_injected_input_moved_the_paddle' (($xAfter -gt ($xBefore + 1.0)) -and ([int]$bodyPaddleAfter.properties.moves -gt 0)) ('x ' + $xBefore + ' -> ' + $xAfter + ' moves=' + $bodyPaddleAfter.properties.moves)
Add-Check 'g7_another_tool_read_the_motion_over_many_frames' (($sampleXs.Count -ge 18) -and $monotonic -and ($distinct -ge 10) -and ($sampleXs[$sampleXs.Count - 1] -gt $sampleXs[0])) ('samples=' + $sampleXs.Count + ' distinct_x=' + $distinct + ' monotonic=' + $monotonic + ' first=' + $sampleXs[0] + ' last=' + $sampleXs[$sampleXs.Count - 1] + ' per_frame_delta=' + ([math]::Round(($sampleXs[$sampleXs.Count - 1] - $sampleXs[0]) / [double]$sampleXs.Count, 3)))
Add-Check 'g7_motion_is_not_a_teleport' (($sampleXs[$sampleXs.Count - 1] - $sampleXs[0]) -lt ($xAfter - $xBefore + 1.0) -and ($distinct -ge 10)) ('stepwise across ' + $sampleXs.Count + ' frames rather than a single jump')
Add-Check 'g7_release_assertion_passed_in_the_game' (($bodyRelease.all_passed -eq $true) -and ([int]$bodyRelease.failed -eq 0)) ('all_passed=' + $bodyRelease.all_passed + ' passed=' + $bodyRelease.passed + ' failed=' + $bodyRelease.failed + ' errors=' + $bodyRelease.errors)

$ballYs = @()
foreach ($s in @($bodyBallSamples.samples)) { $ballYs += [double]$s.position.y }
$ballMoving = $true
for ($k = 1; $k -lt $ballYs.Count; $k++) { if ($ballYs[$k] -gt $ballYs[$k - 1]) { $ballMoving = $false } }
Add-Check 'g7_ball_moved_over_many_frames_after_launch' (($ballYs.Count -ge 12) -and $ballMoving -and (($ballYs[0] - $ballYs[$ballYs.Count - 1]) -gt 1.0)) ('samples=' + $ballYs.Count + ' y ' + $ballYs[0] + ' -> ' + $ballYs[$ballYs.Count - 1] + ' strictly non-increasing=' + $ballMoving)

$brickBefore = [int]$bodyBricksBefore.count
$brickAfter = [int]$bodyBricksAfter.count
Add-Check 'g7_bricks_really_disappeared' (($brickAfter -lt $brickBefore) -and ($brickBefore -eq 3) -and ($brickAfter -eq 2)) ('find_nodes_by_script count ' + $brickBefore + ' -> ' + $brickAfter + '; survivors=' + ((@($bodyBricksAfter.nodes) | ForEach-Object { $_.name }) -join ','))
$treeBeforeJson = ((Get-ToolBody $gTreeBefore) | ConvertTo-Json -Depth 25 -Compress)
$treeAfterJson = ((Get-ToolBody $gTreeAfter) | ConvertTo-Json -Depth 25 -Compress)
$treeAfterHasBrick0 = $treeAfterJson -match '"Brick0"'
$treeBeforeHadBrick0 = $treeBeforeJson -match '"Brick0"'
Add-Check 'g7_removed_brick_is_gone_from_the_scene_tree' ($treeBeforeHadBrick0 -and (-not $treeAfterHasBrick0)) ('parsed scene tree before mentions Brick0: ' + $treeBeforeHadBrick0 + ', after: ' + $treeAfterHasBrick0 + ' (Brick1/Brick2 remain: ' + ($treeAfterJson -match '"Brick1"') + '/' + ($treeAfterJson -match '"Brick2"') + ')')

$scoreBeforeText = [string]$bodyScoreBefore.properties.text
$scoreAfterText = [string]$bodyScoreAfter.properties.text
Add-Check 'g7_score_really_changed' (($scoreBeforeText -eq 'Score: 0') -and ($scoreAfterText -eq 'Score: 10')) ('label text ' + $scoreBeforeText + ' -> ' + $scoreAfterText)
Add-Check 'g7_score_assertion_passed_in_the_game' (($bodyHit.all_passed -eq $true) -and ([int]$bodyHit.failed -eq 0)) ('all_passed=' + $bodyHit.all_passed + ' passed=' + $bodyHit.passed + ' failed=' + $bodyHit.failed + ' errors=' + $bodyHit.errors)

$phaseGame = [ordered]@{
    port = $GamePort
    headless = $true
    project = $GameProject
    calls = @($script:GameCalls | ForEach-Object { [ordered]@{ seq = $_.Seq; tool = $_.Tool; request = $_.RequestPath; request_sha256 = $_.RequestSha256; response = $_.ResponsePath; response_sha256 = $_.ResponseSha256; response_bytes = $_.ResponseBytes } })
    paddle_before = $bodyPaddleBefore
    paddle_samples = $bodySamples
    paddle_after = $bodyPaddleAfter
    release_assertion = $bodyRelease
    ball_samples = $bodyBallSamples
    bricks_before = $bodyBricksBefore
    bricks_after = $bodyBricksAfter
    scene_tree_after = ([string]$gTreeAfter.Raw)
    score_before = $scoreBeforeText
    score_after = $scoreAfterText
    score_assertion = $bodyHit
}
[IO.File]::WriteAllText((Join-Path $Root 'game_live_chain.json'), ($phaseGame | ConvertTo-Json -Depth 14), (New-Object Text.UTF8Encoding($false)))

Stop-OwnProcess -Process $game -LogPath $gameOut
Start-Sleep -Seconds 4
Add-Check 'g7_port_9889_released' ((@(Get-ListeningPorts) -notcontains 9889)) ('listening=' + (@(Get-ListeningPorts) -join ','))

# ==================================================== 8. close the observation
Write-Host '=== 8. close the watcher with the marker ==='
Add-Heartbeat 'mcp065b_run finished the three criteria; writing the marker'
[IO.File]::WriteAllText($MarkerFile, ('done ' + (Get-Date).ToString('o', $InvariantCulture) + "`n"), (New-Object Text.UTF8Encoding($false)))
$watchExited = $false
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    if ($watcher.HasExited) { $watchExited = $true; break }
    Start-Sleep -Seconds 2
}
Add-Check 'w8_watcher_exited_after_the_marker' $watchExited ('watcher pid=' + $watcher.Id + ' exited=' + $watcher.HasExited)
$summaryTxt = Join-Path $WatchOutDir 'watch-summary.txt'
$summaryJson = Join-Path $WatchOutDir 'watch-summary.json'
$stopReason = 'missing'
if (Test-Path -LiteralPath $summaryTxt) {
    foreach ($line in [IO.File]::ReadAllLines($summaryTxt)) {
        if ($line -like 'stop_reason=*') { $stopReason = $line.Substring('stop_reason='.Length).Trim() }
    }
}
Add-Check 'w8_stop_reason_is_marker' ($stopReason -eq 'marker') ('stop_reason=' + $stopReason + ' summary=' + $summaryTxt)
$watchSummary = $null
if (Test-Path -LiteralPath $summaryJson) { $watchSummary = ([IO.File]::ReadAllText($summaryJson) | ConvertFrom-Json) }
if ($null -ne $watchSummary) {
    $traceRows = @($watchSummary.traces)
    $missingRows = @($traceRows | Where-Object { [bool]$_.missing })
    Add-Check 'w8_watch_had_activity' ([bool]$watchSummary.activity_seen) ('activity_seen=' + $watchSummary.activity_seen + ' polls=' + $watchSummary.polls + ' elapsed_sec=' + $watchSummary.elapsed_sec)
    Add-Check 'w8_watch_saw_the_trace_lines' (([int]$watchSummary.trace_lines -gt 0) -and ([int]$watchSummary.last_seq -gt 0)) ('trace_lines=' + $watchSummary.trace_lines + ' last_seq=' + $watchSummary.last_seq)
    Add-Check 'w8_watch_covered_all_three_sources' (([int]$watchSummary.trace_files -eq 3) -and ($missingRows.Count -eq 0)) ('trace_files=' + $watchSummary.trace_files + ' missing=' + $missingRows.Count)
    Add-Check 'w8_watch_saw_the_development_finish' ([bool]$watchSummary.observation_stopped_before_development_ended -eq $false) ('observation_stopped_before_development_ended=' + $watchSummary.observation_stopped_before_development_ended)
}
Ensure-Dir (Join-Path $Root 'watch') | Out-Null
foreach ($f in @('watch.log', 'watch-summary.json', 'watch-summary.txt')) {
    $src = Join-Path $WatchOutDir $f
    if (Test-Path -LiteralPath $src) { [IO.File]::WriteAllBytes((Join-Path $Root ('watch\' + $f + '.txt')), [IO.File]::ReadAllBytes($src)) }
}

$portsAfter = Get-ListeningPorts
Add-Check 'p8_port_9877_no_listener_after' ((@($portsAfter) -notcontains 9877)) ('listening=' + (@($portsAfter) -join ','))
Add-Check 'p8_9888_9889_released' (((@($portsAfter) -notcontains 9888) -and (@($portsAfter) -notcontains 9889))) ('listening=' + (@($portsAfter) -join ','))

# ============================================================ 9. run summary
$passCount = @($script:Checks | Where-Object { $_.pass }).Count
$failCount = @($script:Checks | Where-Object { -not $_.pass }).Count
$runSummary = [ordered]@{
    script = 'mcp065b_run.ps1'
    task = 'TASK-065 section B'
    started = $script:Started
    finished = (Get-Date).ToString('o', $InvariantCulture)
    binary = $ConsoleExe
    editor_port = $EditorPort
    game_port = $GamePort
    checks = $script:Checks
    checks_passed = $passCount
    checks_failed = $failCount
    stop_reason = $stopReason
    watcher = $watchSummary
    notes = $script:Notes
    phase5_json = (Join-Path $Root 'phase5_scope.json')
    phase6_json = (Join-Path $Root 'phase6_capture.json')
    game_json = (Join-Path $Root 'game_live_chain.json')
    pixel_recompute_json = (Join-Path $Root 'pixel_recompute.json')
}
[IO.File]::WriteAllText((Join-Path $Root 'run-summary.json'), ($runSummary | ConvertTo-Json -Depth 14), (New-Object Text.UTF8Encoding($false)))

# evidence hygiene: no same-name file with two different contents anywhere.
$audit = Assert-McpEvidenceTreeUniqueness -Directory $Root
Write-Host ('evidence tree: files=' + $audit.Files + ' collisions=' + @($audit.Collisions).Count + ' duplicate_names=' + @($audit.Duplicates).Count)

Write-Host ('TASK-065B RESULT checks_passed=' + $passCount + ' checks_failed=' + $failCount + ' stop_reason=' + $stopReason)
if ($failCount -gt 0) {
    foreach ($c in @($script:Checks | Where-Object { -not $_.pass })) { Write-Host ('FAILED ' + $c.id + ' :: ' + $c.evidence) }
    exit 1
}
exit 0
