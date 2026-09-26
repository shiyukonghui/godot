# =============================================================================
#  mcp016_hoist_equivalence.ps1 -- TASK-016 section 1, acceptance criterion A2
#
#  The hoist of `MCPTools::edited_scene_root` / `MCPTools::find_node` into
#  tools/tool_helpers.* (U1) must be **behaviour preserving**: the same request
#  sequence must produce **byte-identical responses** before and after it. Reading
#  the two versions side by side is not the judgement; this script is.
#
#  What it does, in order:
#
#    PRE   = c26516becc (the commit TASK-016 started from; asserted to be an
#          ancestor of the current HEAD, so the comparison is against the tree
#          the hoist was made on and not against some unrelated revision).
#    AFTER = the current HEAD (the U1 commit) - recorded at start, restored at end.
#
#    1. builds a scratch project in %TEMP% (`.tscn` written with
#       [IO.File]::WriteAllBytes, i.e. **no BOM**) and checks the `--import` exit
#       code (the M3 acceptance finding);
#    2. `git checkout PRE`, rebuild with modules/mcp_server/scripts/build_local.cmd
#       (tests=yes, serial, output not suppressed), assert the `--version` hash
#       prefix equals `git rev-parse --short HEAD` (PLAYBOOK section 3 step 0 /
#       risk R-1), start the editor endpoint on 9888 and run the CASE sequence;
#       every response body is `curl.exe -s -o <file>` and its sha256 is printed;
#    3. the same for AFTER;
#   4. compares the two directories file by file: the diff count **must be 0**.
#
#  Ports: 9888 (editor) only, plus a read-only listener-pid check of the user's
#  9877 which is never touched. Scratch: %TEMP%.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp016_hoist_equivalence.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
# TASK-072 (D130): the anchor criterion lives in check_engine_anchor.ps1 only.
. (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$BuildScript = Join-Path $RepoRoot 'modules\mcp_server\scripts\build_local.cmd'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$EditorPort = 9888
$UserPort = 9877
$Scratch = Join-Path $env:TEMP 'mcp016-hoist-scratch'
$LogRoot = Join-Path $env:TEMP 'mcp016-hoist-logs'
$OutRoot = Join-Path $env:TEMP 'mcp016-hoist-equivalence'

$PreCommit = 'c26516becc'
$StartBranch = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
$StartHead = (& git -C $RepoRoot rev-parse HEAD).Trim()
$AfterCommit = $StartHead

$script:Results = New-Object System.Collections.Generic.List[object]
$script:EditorHandle = $null

function Add-Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Results.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1} :: {2}" -f $tag, $Id, $Evidence)
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path, [Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-ListenerPid {
    param([int]$Port)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

function Test-PortOpen {
    param([int]$Port, [int]$TimeoutMs = 1500)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        if (-not $task.Wait($TimeoutMs)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $out = Join-Path $LogRoot ($LogName + '.out.log')
    $err = Join-Path $LogRoot ($LogName + '.err.log')
    Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    Write-Host ("started pid={0} :: {1}" -f $proc.Id, ($Arguments -join ' '))
    return [pscustomobject]@{ Process = $proc; Out = $out; Err = $err }
}

function Stop-Engine {
    param($Handle)
    if ($null -eq $Handle) { return }
    try {
        if (-not $Handle.Process.HasExited) {
            Stop-Process -Id $Handle.Process.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 1200
        }
    } catch { }
}

function Import-Project {
    param([string]$Path, [string]$LogName)
    $out = Join-Path $LogRoot ($LogName + '.out.log')
    $err = Join-Path $LogRoot ($LogName + '.err.log')
    # `--mcp-port=0` keeps the import from *trying* to bind the editor default
    # 9877, which belongs to the user's running editor (MCPPort::should_listen is
    # false for a port <= 0). The import has no business opening an endpoint.
    #
    # The exit code is taken from `$LASTEXITCODE` of a directly invoked native
    # command, not from a `Start-Process` object (the object's `ExitCode` came
    # back empty under this PowerShell; measured in TASK-015).
    #
    # Up to three attempts: the very first run of this script lost an import to
    # `0xC0000005` (exit -1073741819) with `Parameter "singleton" is null.
    # At: EditorNode::is_cmdline_mode (editor\editor_node.cpp:6732)` on stderr,
    # while three immediately following fresh-directory imports of the same
    # project - and every later one - returned 0. That is an intermittent engine
    # crash, not a property of the project, so it is retried and the attempts are
    # reported instead of being hidden.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
            & $Engine --headless --mcp-port=0 --path $Path --import 1> $out 2> $err
            $code = $LASTEXITCODE
            Write-Host ("import {0}: attempt={1} exit={2} log={3}" -f $Path, $attempt, $code, $out)
            if ($code -eq 0) {
                return $attempt
            }
            Write-Host ("attempt {0} failed with {1}; stderr: {2}" -f $attempt, $code, ((Get-Content -Raw $err -ErrorAction SilentlyContinue) -replace "`r?`n", ' | '))
            Start-Sleep -Milliseconds 1500
        }
    } finally {
        $ErrorActionPreference = $previous
    }
    throw ("--import of {0} failed three times; last stderr: {1}" -f $Path, (Get-Content -Raw $err -ErrorAction SilentlyContinue))
}

# One build, serial, output not suppressed, exit code checked.
function Invoke-Build {
    param([string]$Label)
    Write-Host ("building ({0}) with {1} ..." -f $Label, $BuildScript)
    & cmd /c $BuildScript
    $code = $LASTEXITCODE
    Write-Host ("build {0}: exit={1}" -f $Label, $code)
    if ($code -ne 0) {
        $log = Join-Path $env:TEMP 'mcp_server_build_local.log'
        Write-Host ("build log tail: {0}" -f ((Get-Content $log -Tail 25 -ErrorAction SilentlyContinue) -join "`n"))
        throw ("the {0} build failed with exit code {1}" -f $Label, $code)
    }
}

# PLAYBOOK section 3 step 0 / risk R-1: a gate must never run on a stale binary.
#
# TASK-072 (D130): this is NOT an "anchor versus HEAD" check - the script checks
# PRE out, rebuilds, and the binary must be the one built FROM the revision it
# checked out (the comparison below is byte-for-byte, so a structural match
# would make it meaningless). The judgement is therefore still made by the single
# judge, with the checked-out revision as the comparison target, and only
# ANCHOR_EQUAL is accepted - which is the old substring test, made exact.
function Assert-VersionMatchesHead {
    param([string]$Label)
    $rev = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
    $version = (& $Engine --version).Trim()
    $verdict = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $version -HeadSha $rev
    Write-Host ("version[{0}] = {1}   (git rev-parse --short HEAD = {2})" -f $Label, $version, $rev)
    Write-Host ("anchor[{0}] = {1}" -f $Label, $verdict.Summary)
    if (($verdict.Verdict -cne 'ANCHOR_EQUAL') -or (-not $verdict.Ok)) {
        throw ("the {0} binary reports '{1}', which is not the revision '{2}' it was built from (anchor judge: {3})" -f $Label, $version, $rev, $verdict.Verdict)
    }
    return $version
}

function ConvertTo-CompactJson {
    param($Value)
    return (ConvertTo-Json -InputObject $Value -Depth 12 -Compress)
}

function Format-CallBody {
    param([string]$Tool, $Arguments, [int]$Id)
    $envelope = @{
        jsonrpc = '2.0'
        id      = $Id
        method  = 'tools/call'
        params  = @{ name = $Tool; arguments = $Arguments }
    }
    return (ConvertTo-CompactJson $envelope)
}

# POST one request with `curl.exe --data-binary @file` and land the response body
# on disk with `curl.exe -s -o`; nothing goes through a pipeline or Out-File
# (PLAYBOOK section 7.1).
function Send-Case {
    param([string]$OutDir, [string]$Name, [string]$Tool, $Arguments, [int]$Id)
    $bodyFile = Join-Path $OutDir ("{0}.request.json" -f $Name)
    $respFile = Join-Path $OutDir ("{0}.response.json" -f $Name)
    Write-Utf8NoBom -Path $bodyFile -Text (Format-CallBody -Tool $Tool -Arguments $Arguments -Id $Id)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time 60 -o $respFile -H 'Content-Type: application/json' `
        --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $EditorPort) | Out-Null
    $curlExit = $LASTEXITCODE
    if (-not (Test-Path $respFile)) {
        throw ("case {0}: curl exited {1} without a response file" -f $Name, $curlExit)
    }
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    if ($text.Length -gt 260) { $text = $text.Substring(0, 260) + '...' }
    Write-Host ("[{0}] {1} bytes={2} sha256={3}" -f $Name, $Tool, $bytes.Length, $sha)
    Write-Host ("       response: {0}" -f $text)
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw ("case {0}: empty response body" -f $Name)
    }
}

function Get-StatusProbe {
    param([int]$Port)
    $file = Join-Path $LogRoot ("status_{0}.response.json" -f $Port)
    if (Test-Path $file) { Remove-Item -Force $file }
    & $Curl -s --max-time 5 -o $file ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    if (-not (Test-Path $file)) { return $null }
    $bytes = [IO.File]::ReadAllBytes($file)
    if ($bytes.Length -eq 0) { return $null }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    try { return ConvertFrom-Json $text } catch { return $null }
}

function Wait-ForPump {
    param([int]$Port, [int]$TimeoutMs = 300000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $consecutive = 0
    $previous = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Get-StatusProbe -Port $Port
        if ($null -ne $probe) {
            $frames = [int]$probe.frame_count
            if ($null -ne $previous -and ($frames - $previous) -ge 20) { $consecutive++ } else { $consecutive = 0 }
            if ($consecutive -ge 3) { return $true }
            $previous = $frames
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# -----------------------------------------------------------------------------
# The CASE sequence.
#
# It is deliberately limited to tools that exist in **both** trees: the read
# helpers this batch adds (`editor_get_node_properties`, ...) are the subject of
# U2, which does not exist yet at the U1 commit, so using them would compare
# `-32601` against a real answer. Every branch of the two hoisted helpers is
# covered instead with tools that do exist on both sides:
#
#   * edited_scene_root     - every one of these tools calls it;
#   * find_node branch 1    - "." (steps 3, 12) and the bare root name (step 9);
#   * find_node branch 2    - "HoistA/Deep" (steps 4, 5, 8, 10), "./HoistA"
#                             (step 7), "HoistACopy" (step 17);
#   * find_node branch 3    - "Main/HoistA/Deep" (step 6);
#   * find_node branch 4    - "NoSuchNode" (steps 14, 16);
#   * the second call site (`find_node` inside `editor_set_node_selection` of
#     tools/editor_write_scene_editor.cpp) - steps 10, 12, 14, 17;
#   * the third call site of the hoisted root (`editor_get_selection`) - steps
#     2, 11, 13, 18, 20.
#
# The read-back tool is `editor_get_selection` and **not**
# `editor_get_scene_tree`: the latter answers `Node::get_path()`, an absolute
# path through the editor's own node tree (`/root/@EditorNode@<runtime id>/...`),
# so its bytes differ between two editor runs for reasons that have nothing to do
# with this refactor. Every path this sequence compares is a root-relative one
# (`get_path_to`), which is exactly the spelling both hoisted helpers produce.
# -----------------------------------------------------------------------------
function Invoke-CaseSequence {
    param([string]$OutDir, [string]$Label)
    Remove-Item -Recurse -Force $OutDir -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

    $script:EditorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Scratch, "--mcp-port=$EditorPort") -LogName ("editor-" + $Label)
    if (-not (Wait-ForPump -Port $EditorPort -TimeoutMs 300000)) { throw ("the {0} editor endpoint never became ready" -f $Label) }

    $cases = @(
        @{ name = '01_open_scene';                 tool = 'editor_open_scene';                  args = @{ path = 'res://scenes/main.tscn' } },
        @{ name = '02_selection_baseline';         tool = 'editor_get_selection';               args = @{} },
        @{ name = '03_add_node_root';              tool = 'editor_add_node';                    args = @{ type = 'Node2D'; parent_path = '.'; name = 'HoistA' } },
        @{ name = '04_add_node_relative';          tool = 'editor_add_node';                    args = @{ type = 'Node2D'; parent_path = 'HoistA'; name = 'Deep' } },
        @{ name = '05_write_relative';             tool = 'editor_set_node_property';           args = @{ path = 'HoistA/Deep'; property = 'position'; value = @{ x = 1; y = 2 } } },
        @{ name = '06_write_root_prefixed';        tool = 'editor_set_node_property';           args = @{ path = 'Main/HoistA/Deep'; property = 'position'; value = @{ x = 2; y = 3 } } },
        @{ name = '07_duplicate_dot_prefix';       tool = 'editor_duplicate_node';              args = @{ path = './HoistA'; new_name = 'HoistACopy' } },
        @{ name = '08_rename_nested';              tool = 'editor_rename_node';                 args = @{ path = 'HoistA/Deep'; name = 'Deep2' } },
        @{ name = '09_set_property_by_root_name';  tool = 'editor_set_node_property';           args = @{ path = 'Main'; property = 'position'; value = @{ x = 9; y = 9 } } },
        @{ name = '10_selection_nested_node';      tool = 'editor_set_node_selection';          args = @{ node_paths = @('HoistA/Deep2'); inspect = $false } },
        @{ name = '11_selection_read_nested';      tool = 'editor_get_selection';               args = @{} },
        @{ name = '12_selection_dot';              tool = 'editor_set_node_selection';          args = @{ node_paths = @('.'); inspect = $false } },
        @{ name = '13_selection_read_dot';         tool = 'editor_get_selection';               args = @{} },
        @{ name = '14_selection_missing_node';     tool = 'editor_set_node_selection';          args = @{ node_paths = @('NoSuchNode') } },
        @{ name = '15_reparent_to_dot';            tool = 'editor_reparent_node';               args = @{ path = 'HoistA/Deep2'; new_parent = '.' } },
        @{ name = '16_write_missing_node';         tool = 'editor_set_node_property';           args = @{ path = 'NoSuchNode'; property = 'position'; value = @{ x = 0; y = 0 } } },
        @{ name = '17_selection_copy';             tool = 'editor_set_node_selection';          args = @{ node_paths = @('HoistACopy'); inspect = $false } },
        @{ name = '18_selection_read_final';       tool = 'editor_get_selection';               args = @{} },
        @{ name = '19_delete_node';                tool = 'editor_delete_node';                 args = @{ path = 'HoistA' } },
        @{ name = '20_selection_read_after';       tool = 'editor_get_selection';               args = @{} }
    )

    $id = 100
    foreach ($case in $cases) {
        Send-Case -OutDir $OutDir -Name $case.name -Tool $case.tool -Arguments $case.args -Id $id
        $id++
        if ($case.name -eq '19_delete_node') { Start-Sleep -Milliseconds 1200 }
    }

    Stop-Engine -Handle $script:EditorHandle
    $script:EditorHandle = $null
    # The endpoint must have gone away, or the next phase would talk to the old
    # process (and the comparison would be meaningless).
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ((Test-PortOpen -Port $EditorPort) -and ([DateTime]::UtcNow -lt $deadline)) { Start-Sleep -Milliseconds 500 }
    if (Test-PortOpen -Port $EditorPort) { throw ("the {0} editor endpoint is still listening after the stop" -f $Label) }
}

# =============================================================================
# Main
# =============================================================================

Write-Host '============================================================='
Write-Host ' TASK-016 section 1 -- hoist equivalence (before/after, byte for byte)'
Write-Host '============================================================='
Write-Host ("PRE   = {0}" -f $PreCommit)
Write-Host ("AFTER = {0}  (branch {1})" -f $AfterCommit, $StartBranch)

if (-not (Test-Path $Engine)) { Write-Host "FATAL: engine binary not found: $Engine"; exit 2 }
New-Item -ItemType Directory -Force -Path $Scratch, $LogRoot, $OutRoot | Out-Null

$userPortPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)

$beforeDir = Join-Path $OutRoot 'before'
$afterDir = Join-Path $OutRoot 'after'

try {
    # (0) The comparison is only meaningful if PRE really is the tree the hoist
    #     was made on.
    & git -C $RepoRoot merge-base --is-ancestor $PreCommit $AfterCommit
    Add-Check 'pre_is_an_ancestor_of_after' ($LASTEXITCODE -eq 0) ("git merge-base --is-ancestor {0} {1} -> exit {2}" -f $PreCommit, $AfterCommit, $LASTEXITCODE)
    if ($LASTEXITCODE -ne 0) { throw 'PRE is not an ancestor of AFTER' }

    # `git checkout <commit>` refuses to overwrite tracked modifications, and a
    # dirty tree would silently compare the wrong thing. Untracked files (this
    # script, the scratch directories) are irrelevant and are ignored.
    $dirty = @(& git -C $RepoRoot status --porcelain | Where-Object { $_ -notmatch '^\?\?' })
    Add-Check 'working_tree_has_no_tracked_modifications' ($dirty.Count -eq 0) ("dirty entries: [" + ($dirty -join ' | ') + "]")
    if ($dirty.Count -ne 0) { throw 'the working tree has tracked modifications; commit or stash them first' }

    # (1) The scratch project: one scene whose root is named `Main`, so the
    #     "root-prefixed retry" branch of the migration source has a name to
    #     strip.
    $mainScene = @"
[gd_scene format=3]

[node name="Main" type="Node2D"]

[node name="Child" type="Node2D" parent="."]

[node name="World" type="Node" parent="."]
"@
    Remove-Item -Recurse -Force $Scratch -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $Scratch 'scenes') | Out-Null
    Write-Utf8NoBom -Path (Join-Path $Scratch 'project.godot') -Text (@(
        'config_version=5',
        '',
        '[application]',
        'config/name="MCP016 hoist equivalence"',
        'config/features=PackedStringArray("4.8")',
        '',
        '[rendering]',
        'renderer/rendering_method="gl_compatibility"',
        'renderer/rendering_method.mobile="gl_compatibility"',
        ''
    ) -join "`n")
    Write-Utf8NoBom -Path (Join-Path $Scratch 'scenes\main.tscn') -Text ($mainScene + "`n")
    $importAttempts = Import-Project -Path $Scratch -LogName 'import-equivalence'
    Add-Check 'scratch_import_exit_code' $true ("the scratch project imported with exit code 0 (attempt(s): {0})" -f $importAttempts)

    # (2) BEFORE: the tree as TASK-016 found it.
    Write-Host ''
    Write-Host '--- BEFORE (PRE) --------------------------------------------'
    & git -C $RepoRoot checkout --quiet $PreCommit
    if ($LASTEXITCODE -ne 0) { throw ("git checkout {0} failed" -f $PreCommit) }
    Invoke-Build -Label 'before'
    $beforeVersion = Assert-VersionMatchesHead -Label 'before'
    Invoke-CaseSequence -OutDir $beforeDir -Label 'before'
    Add-Check 'before_cases_completed' $true ("{0} response files" -f (@(Get-ChildItem $beforeDir -Filter '*.response.json')).Count)

    # (3) AFTER: the U1 commit.
    Write-Host ''
    Write-Host '--- AFTER (U1) ---------------------------------------------'
    & git -C $RepoRoot checkout --quiet $AfterCommit
    if ($LASTEXITCODE -ne 0) { throw ("git checkout {0} failed" -f $AfterCommit) }
    Invoke-Build -Label 'after'
    $afterVersion = Assert-VersionMatchesHead -Label 'after'
    Invoke-CaseSequence -OutDir $afterDir -Label 'after'
    Add-Check 'after_cases_completed' $true ("{0} response files" -f (@(Get-ChildItem $afterDir -Filter '*.response.json')).Count)

    # (4) The comparison.
    Write-Host ''
    Write-Host '--- COMPARISON ---------------------------------------------'
    $beforeFiles = @(Get-ChildItem $beforeDir -Filter '*.response.json' | Sort-Object Name)
    $afterNames = @(Get-ChildItem $afterDir -Filter '*.response.json' | ForEach-Object { $_.Name })
    Add-Check 'the_two_runs_produced_the_same_case_set' `
        ((@($beforeFiles | ForEach-Object { $_.Name }) -join ',') -eq ($afterNames -join ',')) `
        ("before={0} after={1}" -f $beforeFiles.Count, $afterNames.Count)

    $diffCount = 0
    Write-Host ("{0,-32} {1,-64} {2,-64}" -f 'case', 'before sha256', 'after sha256')
    foreach ($file in $beforeFiles) {
        $b = Join-Path $beforeDir $file.Name
        $a = Join-Path $afterDir $file.Name
        $bSha = (Get-FileHash -Algorithm SHA256 -Path $b).Hash.ToLower()
        if (-not (Test-Path $a)) {
            $diffCount++
            Write-Host ("{0,-32} {1,-64} {2}" -f $file.Name, $bSha, 'MISSING')
            continue
        }
        $aSha = (Get-FileHash -Algorithm SHA256 -Path $a).Hash.ToLower()
        $same = ($bSha -eq $aSha)
        if (-not $same) { $diffCount++ }
        Write-Host ("{0,-32} {1,-64} {2} {3}" -f $file.Name, $bSha, $aSha, $(if ($same) { '' } else { '<-- DIFFERS' }))
    }
    Add-Check 'before_and_after_responses_are_byte_identical' ($diffCount -eq 0) `
        ("{0} response file(s) compared, diff count = {1}" -f $beforeFiles.Count, $diffCount)
    Write-Host ''
    Write-Host ("before --version : {0}" -f $beforeVersion)
    Write-Host ("after  --version : {0}" -f $afterVersion)
} catch {
    Add-Check 'harness_exception' $false ($_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    Stop-Engine -Handle $script:EditorHandle

    # Always hand the repository back exactly as it was found.
    & git -C $RepoRoot checkout --quiet $StartBranch
    if ($LASTEXITCODE -ne 0) { Write-Host ("WARNING: could not check out {0} again" -f $StartBranch) }
    $restored = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
    Write-Host ("restored checkout: {0} (expected {1})" -f $restored, $StartBranch)

    $userPortPidAfter = Get-ListenerPid -Port $UserPort
    Add-Check 'guard_user_port_9877' ($userPortPidBefore -eq $userPortPidAfter) `
        ("pid_before={0} pid_after={1}" -f $userPortPidBefore, $userPortPidAfter)

    Write-Host ''
    Write-Host '========================== SUMMARY =========================='
    $passed = @($script:Results | Where-Object { $_.pass }).Count
    $total = $script:Results.Count
    foreach ($r in $script:Results) {
        $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
        Write-Host ("{0}  {1}" -f $tag, $r.id)
    }
    Write-Host ("{0}/{1} checks passed" -f $passed, $total)
    Write-Host ("evidence: {0}" -f $OutRoot)
    if ($passed -ne $total) { exit 1 }
    exit 0
}
