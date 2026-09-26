# =============================================================================
#  mcp057_settings_publish_evidence.ps1 -- TASK-057 section 4 (engine patch 2)
#  live evidence for `ProjectSettings::save_custom_section()`.
#
#  What it proves, all of it on real files and with an outside-the-process byte
#  comparison:
#
#    * the value really lands in the NAMED section even when that section is not
#      the last one - the R1 failure of the text-splice approach is read back by
#      the engine's own InputMap (`has_action`), which is the reader that
#      resolves `input/<action>`, and a control run proves the reader can say no;
#    * every byte outside the target section survives: the hand written header
#      comments, the blank lines, the key order and the following section are
#      compared against an expectation built independently in PowerShell;
#    * a second identical call leaves the file byte identical (idempotence);
#    * a UTF-8 BOM survives (measured, because `FileAccess::get_as_text()` drops
#      it and `store_string()` never writes one);
#    * CRLF line endings survive, on a CRLF fixture, byte for byte;
#    * `--import` and a game run (`--headless --quit`) do not change the file;
#    * four concurrent writers leave a parseable file that contains exactly one
#      of the four complete results - never a torn or half-merged file;
#    * the existing whole-file writer is untouched: `save_custom()` on the same
#      fixture still rewrites the file and still drops the hand written
#      comments, which is the DECLARED behaviour this patch deliberately does
#      not change.
#
#  Everything lives in %TEMP%; the repository is never written to. Pure ASCII.
#
#  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp057_settings_publish_evidence.ps1
# =============================================================================

$ErrorActionPreference = 'Continue'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-072 (D130): the anchor criterion lives in check_engine_anchor.ps1 only.
. (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')

$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$ProbeSource = Join-Path $PSScriptRoot 'mcp057_section_probe.gd'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$ScratchPrefix = Join-Path $env:TEMP 'mcp057'
$Root = Join-Path $env:TEMP ('mcp057\settings-publish\' + $Stamp)
$LogRoot = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$script:Checks = New-Object System.Collections.Generic.List[string]
$script:Failures = 0

function Check([string]$Id, [bool]$Ok, [string]$Evidence) {
    $verdict = if ($Ok) { 'PASS' } else { 'FAIL' }
    if (-not $Ok) { $script:Failures++ }
    $line = ('[{0}] {1} :: {2}' -f $verdict, $Id, $Evidence)
    $script:Checks.Add($line)
    Write-Host $line
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Get-Bytes([string]$Path) {
    return [IO.File]::ReadAllBytes($Path)
}

function Set-Bytes([string]$Path, [byte[]]$Bytes) {
    [IO.File]::WriteAllBytes($Path, $Bytes)
}

function Get-Text([string]$Path) {
    return [Text.Encoding]::UTF8.GetString((Get-Bytes $Path))
}

function Run-Engine([string[]]$Arguments, [string]$LogName, [int]$TimeoutSeconds = 150) {
    # A Godot that fails to load the `--script` main loop does NOT exit: it falls
    # back to the default main loop and runs the project forever. That was
    # measured the hard way (a stale probe wedged this script until the process
    # was killed by hand), so every engine invocation is bounded here, and a
    # timeout also sweeps the processes of this task's scratch tree - matched by
    # their command line, never by name, so the user's own editor can never be
    # hit.
    $log = Join-Path $LogRoot ($LogName + '.log')
    $job = Start-Job -ScriptBlock {
        param($EnginePath, $ArgList)
        $out = & $EnginePath @ArgList 2>&1
        [PSCustomObject]@{ code = $LASTEXITCODE; text = ($out -join "`n") }
    } -ArgumentList $Engine, $Arguments
    $completed = Wait-Job $job -Timeout $TimeoutSeconds
    $killed = @()
    if ($completed) {
        $received = Receive-Job $job
        $code = $received.code
        $text = $received.text
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        $killed = Stop-ScratchEngineProcesses
        $code = -1
        $text = ('MCP057_PROBE timeout after {0}s; killed scratch-process ids: {1}' -f $TimeoutSeconds, ($killed -join ','))
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    $lines = @($text -split "`n")
    [IO.File]::WriteAllLines($log, $lines)
    return @{ code = $code; killed = $killed; log = $log; text = $text }
}

# Kills every Godot process whose command line mentions this task's scratch root.
# The user's own editor is started elsewhere and is therefore never matched.
function Stop-ScratchEngineProcesses {
    $killed = @()
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "name like '%godot%'")) {
        if ($p.CommandLine -and $p.CommandLine.Contains($ScratchPrefix)) {
            try {
                Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
                $killed += $p.ProcessId
            } catch { }
        }
    }
    return $killed
}

function Get-ProbeLine([string]$Text, [string]$Prefix) {
    foreach ($line in ($Text -split "`n")) {
        if ($line.Contains('MCP057_PROBE ' + $Prefix)) { return $line.Trim() }
    }
    return ''
}

# D-2 (TASK-059): is a TCP port free? Asked by BINDING it, not by parsing
# `netstat` text: the state word `netstat` prints is localized on this machine's
# locale, so a text match would be a check that silently stops working when the
# console language changes. A Godot that failed to load the probe main loop keeps
# running its scratch project forever and keeps its listener, so this is the
# second leg of "nothing of this run survived".
function Test-TestPortFree([int]$Port) {
    $listener = $null
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($null -ne $listener) { $listener.Stop() }
    }
}

function Get-BusyTestPorts([int[]]$Ports) {
    $busy = @()
    foreach ($port in $Ports) {
        if (-not (Test-TestPortFree $port)) { $busy += $port }
    }
    return $busy
}

# ---------------------------------------------------------------------------
# Fixtures. The same hand written file in three flavours; `[input]` is
# DELIBERATELY NOT the last section in all of them.
# ---------------------------------------------------------------------------
$LfBody = @'
; HAND WRITTEN HEADER -- must survive byte for byte
; second comment line
[application]

config/name="mcp057-fixture"
config/features=PackedStringArray("4.8")
run/main_scene="res://scenes/main.tscn"

; input is deliberately NOT the last section
[input]

mcp057_existing={
"deadzone": 0.5,
"events": []
}

[rendering]

renderer/rendering_method="gl_compatibility"
'@
$LfText = $LfBody + "`n"

# The serialization oracle, taken from the fixture's own bytes: an input action
# is written by the engine as a MULTI-LINE dictionary
# (`variant_parser.cpp:2187-2201`), so the block that has to appear under a new
# name is the existing block with the name swapped. Building the expectation this
# way keeps it independent of the writer under test while still matching the
# engine's real format - a hand-written single-line dictionary would not.
$blockStart = $LfText.IndexOf('mcp057_existing=')
$blockEnd = $LfText.IndexOf("}`n", $blockStart) + 1
$existingBlock = $LfText.Substring($blockStart, $blockEnd - $blockStart)
$fireBlock = 'mcp057_fire=' + $existingBlock.Substring($existingBlock.IndexOf('=') + 1)

function New-SectionProject([string]$Name, [string]$Text, [bool]$WithBom) {
    $dir = Join-Path $Root $Name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
    if ($WithBom) {
        $payload = New-Object System.Collections.Generic.List[byte]
        $payload.Add(0xEF); $payload.Add(0xBB); $payload.Add(0xBF)
        foreach ($b in $bytes) { $payload.Add($b) }
        [IO.File]::WriteAllBytes((Join-Path $dir 'project.godot'), $payload.ToArray())
    } else {
        [IO.File]::WriteAllBytes((Join-Path $dir 'project.godot'), $bytes)
    }
    Copy-Item -Path $ProbeSource -Destination (Join-Path $dir 'mcp057_section_probe.gd') -Force
    # A main scene is needed for the "run the game" leg: an editor build whose
    # project declares no main scene opens the PROJECT MANAGER instead, and that
    # loop never quits (measured - `--headless --path X --quit` wedged).
    $sceneDir = Join-Path $dir 'scenes'
    New-Item -ItemType Directory -Force -Path $sceneDir | Out-Null
    $scene = @('[gd_scene format=3]', '', '[node name="Main" type="Node"]')
    Write-McpUtf8NoBom -Path (Join-Path $sceneDir 'main.tscn') -Text (($scene -join "`n") + "`n")
    return $dir
}

Write-Host '============================================================='
Write-Host ' TASK-057 engine patch 2: section-granular project.godot publish'
Write-Host (' repo   : ' + $RepoRoot)
Write-Host (' root   : ' + $Root)
Write-Host '============================================================='

# --- 0. the engine has to be the one the gates are anchored on ---------------
$version = ((& $Engine --version) -join '').Trim()
$head = ((& git -C $RepoRoot rev-parse --short=9 HEAD) -join '').Trim()
# TASK-072 (D130): one judge decides the anchor; see check_engine_anchor.ps1.
$anchorVerdict = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $version -HeadSha $head
Check 'p2_engine_version_matches_head' ($anchorVerdict.Ok) `
    (("--version='{0}' git HEAD='{1}'" -f $version, $head) + ' | ' + $anchorVerdict.Summary)

$gdProject = New-SectionProject 'lf' $LfText $false
$bomProject = New-SectionProject 'bom' $LfText $true
$crlfProject = New-SectionProject 'crlf' ($LfText.Replace("`n", "`r`n")) $false
$customProject = New-SectionProject 'save_custom' $LfText $false

$gdPath = Join-Path $gdProject 'project.godot'
$bomPath = Join-Path $bomProject 'project.godot'
$crlfPath = Join-Path $crlfProject 'project.godot'

# --- 1. negative control: the reader can say "no" ---------------------------
$control = Run-Engine @('--headless', '--path', $gdProject, '--script', 'res://mcp057_section_probe.gd', '--', 'has_action', 'mcp057_fire') 'control_has_action'
$hasActionBefore = (Get-ProbeLine $control.text 'mode=has_action').Contains('has_action=false')
Check 'p2_has_action_control_false_before_publish' ($control.code -eq 0 -and $hasActionBefore) ("exit={0} :: {1}" -f $control.code, (Get-ProbeLine $control.text 'mode=has_action'))

# --- 1b. the RED state: the naive in-caller splice fails silently ------------
# The rejected approach this patch exists to replace: append the new key to the
# end of the file. `[input]` is not the last section, so the engine's reader
# attributes the key to `[rendering]` - the file still parses, `ConfigFile`
# loads it without complaint, and only a reader that resolves
# `input/<action>` (the InputMap a game process builds) can see that nothing
# happened. This is exactly the R1 failure TASK-042 measured.
$spliceProject = New-SectionProject 'naive_splice' ($LfText + $fireBlock + "`n") $false
$spliceReader = Run-Engine @('--headless', '--path', $spliceProject, '--script', 'res://mcp057_section_probe.gd', '--', 'has_action', 'mcp057_fire') 'splice_has_action'
$spliceLoad = Run-Engine @('--headless', '--path', $spliceProject, '--script', 'res://mcp057_section_probe.gd', '--', 'publish', 'res://project.godot', 'rendering', 'rendering/renderer/rendering_method', '"gl_compatibility"') 'splice_parses'
$spliceStillParses = (Get-ProbeLine $spliceLoad.text 'load=').Contains('load=0')
$spliceHasAction = (Get-ProbeLine $spliceReader.text 'mode=has_action').Contains('has_action=true')
Check 'p2_RED_naive_splice_is_silent_and_wrong' ((-not $spliceHasAction) -and $spliceStillParses) ("has_action={0} (expected false) file_still_parses={1} -- the failure is silent" -f $spliceHasAction, $spliceStillParses)
$spliceText = Get-Text (Join-Path $spliceProject 'project.godot')
Check 'p2_RED_naive_splice_put_the_key_in_rendering' ($spliceText.EndsWith($fireBlock + "`n")) 'the key sits after the [rendering] header, which is why the InputMap cannot see it'

# --- 2. the publish, then the engine's own InputMap reads it back -----------
$before = Get-Sha256 $gdPath
$publish = Run-Engine @('--headless', '--path', $gdProject, '--script', 'res://mcp057_section_probe.gd', '--',
    'input_action', 'res://project.godot', 'mcp057_fire') 'publish_input_action'
$publishOk = (Get-ProbeLine $publish.text 'mode=input_action').Contains('err=0')
Check 'p2_publish_returns_ok' ($publish.code -eq 0 -and $publishOk) (Get-ProbeLine $publish.text 'mode=input_action')
Check 'p2_probe_keys_read_back' ((Get-ProbeLine $publish.text 'keys=') -like '*mcp057_fire*') (Get-ProbeLine $publish.text 'keys=')
Check 'p2_probe_key_present' ((Get-ProbeLine $publish.text 'key=mcp057_fire') -like '*present=true*') (Get-ProbeLine $publish.text 'key=mcp057_fire')

$after = Get-Sha256 $gdPath
Check 'p2_file_changed_by_publish' ($after -ne $before) ("before={0} after={1}" -f $before, $after)

$hasActionRun = Run-Engine @('--headless', '--path', $gdProject, '--script', 'res://mcp057_section_probe.gd', '--', 'has_action', 'mcp057_fire') 'after_has_action'
$hasActionAfter = (Get-ProbeLine $hasActionRun.text 'mode=has_action').Contains('has_action=true')
Check 'p2_has_action_true_after_publish_R1_reversed' ($hasActionRun.code -eq 0 -and $hasActionAfter) (Get-ProbeLine $hasActionRun.text 'mode=has_action')

# --- 3. byte-exact expectation, built independently -------------------------
$expectedLf = $LfText.Replace($existingBlock + "`n", $existingBlock + "`n" + $fireBlock + "`n")
$actualLfBytes = Get-Bytes $gdPath
$expectedLfBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($expectedLf)
$identical = ($actualLfBytes.Length -eq $expectedLfBytes.Length)
if ($identical) {
    for ($i = 0; $i -lt $actualLfBytes.Length; $i++) {
        if ($actualLfBytes[$i] -ne $expectedLfBytes[$i]) { $identical = $false; break }
    }
}
Check 'p2_bytes_exact_lf' $identical ("actual={0}B sha={1} expected={2}B" -f $actualLfBytes.Length, (Get-Sha256 $gdPath), $expectedLfBytes.Length)
[IO.File]::WriteAllBytes((Join-Path $LogRoot 'lf_expected.godot'), $expectedLfBytes)
[IO.File]::WriteAllBytes((Join-Path $LogRoot 'lf_actual.godot'), $actualLfBytes)

# --- 4. idempotence ---------------------------------------------------------
$publish2 = Run-Engine @('--headless', '--path', $gdProject, '--script', 'res://mcp057_section_probe.gd', '--',
    'input_action', 'res://project.godot', 'mcp057_fire') 'publish_input_action_again'
Check 'p2_idempotent_second_call' ((Get-Sha256 $gdPath) -eq $after) ("sha after first={0} sha after second={1}" -f $after, (Get-Sha256 $gdPath))

# --- 5. a scalar into a section that does not exist yet ---------------------
$create = Run-Engine @('--headless', '--path', $gdProject, '--script', 'res://mcp057_section_probe.gd', '--',
    'publish', 'res://project.godot', 'mcp057_new_section', 'mcp057_new_section/score', '1.5') 'publish_new_section'
$afterCreate = Get-Text $gdPath
Check 'p2_new_section_appended_at_end' ($create.code -eq 0 -and $afterCreate.EndsWith("[mcp057_new_section]`n`nscore=1.5`n") -and $afterCreate.StartsWith($expectedLf)) ("ends_with_block={0} starts_with_previous={1}" -f $afterCreate.EndsWith("[mcp057_new_section]`n`nscore=1.5`n"), $afterCreate.StartsWith($expectedLf))

# --- 6. BOM ------------------------------------------------------------------
$bomBefore = Get-Bytes $bomPath
$bomRun = Run-Engine @('--headless', '--path', $bomProject, '--script', 'res://mcp057_section_probe.gd', '--',
    'publish', 'res://project.godot', 'input', 'input/mcp057_bom_fire', '1.5') 'publish_bom'
$bomAfter = Get-Bytes $bomPath
$bomKept = ($bomBefore[0] -eq 0xEF -and $bomBefore[1] -eq 0xBB -and $bomBefore[2] -eq 0xBF -and
           $bomAfter[0] -eq 0xEF -and $bomAfter[1] -eq 0xBB -and $bomAfter[2] -eq 0xBF)
$bomBodyKept = ((Get-Text $bomPath).StartsWith("; HAND WRITTEN HEADER"))
Check 'p2_bom_preserved' ($bomRun.code -eq 0 -and $bomKept -and $bomBodyKept) ("before[0..2]={0:X2} {1:X2} {2:X2} after[0..2]={3:X2} {4:X2} {5:X2}" -f $bomBefore[0], $bomBefore[1], $bomBefore[2], $bomAfter[0], $bomAfter[1], $bomAfter[2])

# --- 7. CRLF -----------------------------------------------------------------
$crlfRun = Run-Engine @('--headless', '--path', $crlfProject, '--script', 'res://mcp057_section_probe.gd', '--',
    'publish', 'res://project.godot', 'input', 'input/mcp057_crlf_fire', '1.5') 'publish_crlf'
$crlfBytes = Get-Bytes $crlfPath
$crlfText = Get-Text $crlfPath
$noBareLf = (-not ($crlfText -replace "`r`n", '').Contains("`n"))
$crlfInserted = $crlfText.Contains($existingBlock.Replace("`n", "`r`n") + "`r`n" + 'mcp057_crlf_fire=1.5' + "`r`n")
Check 'p2_crlf_preserved_and_new_line_is_crlf' ($crlfRun.code -eq 0 -and $noBareLf -and $crlfInserted) ("no_bare_lf={0} inserted_with_crlf={1}" -f $noBareLf, $crlfInserted)

# --- 8. --import does not change the file -----------------------------------
$importBefore = Get-Sha256 $gdPath
$import = Import-McpProject -Engine $Engine -Path $gdProject -LogDirectory $LogRoot -Name 'import' -NoPort
$importAfter = Get-Sha256 $gdPath
Check 'p2_import_leaves_file_unchanged' ($import.exit_code -eq 0 -and $importAfter -eq $importBefore) ("import exit={0} attempts={1} sha {2} -> {3}" -f $import.exit_code, $import.attempts, $importBefore, $importAfter)

# --- 9. a game run does not change the file ---------------------------------
$runBefore = Get-Sha256 $gdPath
$gameRun = Run-Engine @('--headless', '--path', $gdProject, '--quit-after', '2') 'game_run'
$runAfter = Get-Sha256 $gdPath
Check 'p2_game_run_leaves_file_unchanged' ($gameRun.code -eq 0 -and $runAfter -eq $runBefore) ("run exit={0} sha {1} -> {2}" -f $gameRun.code, $runBefore, $runAfter)

# --- 10. concurrency: four writers, one complete result ---------------------
$concProject = New-SectionProject 'concurrent' $LfText $false
$concPath = Join-Path $concProject 'project.godot'
$keys = @('mcp057_c1', 'mcp057_c2', 'mcp057_c3', 'mcp057_c4')
$jobs = @()
foreach ($k in $keys) {
    $jobs += Start-Job -ScriptBlock {
        param($EnginePath, $ProjPath, $Key)
        $out = & $EnginePath --headless --path $ProjPath --script res://mcp057_section_probe.gd -- publish res://project.godot input ('input/' + $Key) '1.5' 2>&1
        return @{ key = $Key; code = $LASTEXITCODE; text = ($out -join "`n") }
    } -ArgumentList $Engine, $concProject, $k
}
$jobResults = @()
$null = $jobs | Wait-Job -Timeout 300
$jobResults = @($jobs | Receive-Job)
$stillRunning = @($jobs | Where-Object { $_.State -eq 'Running' }).Count
$jobs | Stop-Job -ErrorAction SilentlyContinue
$jobs | Remove-Job -Force
$jobCodesOk = (@($jobResults | Where-Object { $_.code -ne 0 }).Count -eq 0) -and ($stillRunning -eq 0)
$jobSummary = (($jobResults | ForEach-Object { '{0}={1}' -f $_.key, $_.code }) -join ' ')
# D-1 (TASK-059): this `Check` used to be called TWICE under one id - once here
# and once after the survivor count was computed - so `summary.txt` carried the
# same id on two lines and `checks:` counted a duplicate. The call that carried
# the stronger evidence (the survivor counts) is the one kept, below; this id is
# gone and its own honest result is folded into the survivor line's evidence
# string. The survivor assertion itself was NOT dropped.
$concActual = Get-Text $concPath
$concReader = Run-Engine @('--headless', '--path', $concProject, '--script', 'res://mcp057_section_probe.gd', '--', 'has_action', 'mcp057_c1') 'concurrent_readback'

# What is asserted about the race is what the writer really guarantees: the file
# is never TORN and nothing outside the target section moves. It does NOT
# guarantee "no lost update" - the publish is a read-modify-rename with no
# inter-process lock, so a different interleaving can leave fewer than four
# survivors (last writer wins). This run kept all four because the four
# processes ended up serialized in practice; the check below therefore accepts
# one to four WHOLE results and rejects anything partial.
$survivors = @($keys | Where-Object { $concActual.Contains($_ + '=1.5') })
$duplicated = @($keys | Where-Object { ([regex]::Matches($concActual, [regex]::Escape($_ + '=1.5'))).Count -gt 1 })
Check 'p2_concurrency_four_writers_all_exit_zero' $jobCodesOk ("{0}; still running after the wait: {1}; survivors={2}/4 ({3})" -f $jobSummary, $stillRunning, $survivors.Count, ($survivors -join ','))
$invariantPrefix = $LfText.Substring(0, $LfText.IndexOf('[input]'))
$invariantSuffix = $LfText.Substring($LfText.IndexOf("`n`n[rendering]"))
$invariantKept = ($concActual.StartsWith($invariantPrefix)) -and ($concActual.EndsWith($invariantSuffix))
Check 'p2_concurrency_bytes_outside_the_section_untouched' $invariantKept 'the prefix before [input] and everything from [rendering] on are byte identical to the fixture'

$bodyStart = $invariantPrefix.Length
$bodyEnd = $concActual.IndexOf($invariantSuffix)
$bodyLines = @()
if ($bodyEnd -gt $bodyStart) {
    $bodyLines = @(($concActual.Substring($bodyStart, $bodyEnd - $bodyStart)).Split("`n") | Where-Object { $_.Trim() -ne '' })
}
$allowed = @('[input]', 'mcp057_existing={', '"deadzone": 0.5,', '"events": []', '}') + ($keys | ForEach-Object { $_ + '=1.5' })
$unexpected = @($bodyLines | Where-Object { $allowed -notcontains $_ })
Check 'p2_concurrency_every_line_is_a_whole_result' (($unexpected.Count -eq 0) -and ($duplicated.Count -eq 0) -and ($survivors.Count -ge 1)) ("survivors={0} duplicated={1} unexpected line(s)={2}" -f $survivors.Count, $duplicated.Count, (($unexpected | Select-Object -First 3) -join ' / '))
Check 'p2_concurrency_readable_after_the_race' (-not [string]::IsNullOrWhiteSpace((Get-ProbeLine $concReader.text 'mode=has_action'))) (Get-ProbeLine $concReader.text 'mode=has_action')
Check 'p2_concurrency_no_scratch_file_left' ((-not (Test-Path ($concPath + '.section_tmp'))) -and (-not (Test-Path ($concPath + '.section_bak')))) 'no .section_tmp / .section_bak next to the destination'

# --- 11. the existing whole-file writer is untouched ------------------------
$customPath = Join-Path $customProject 'project.godot'
$customRun = Run-Engine @('--headless', '--path', $customProject, '--script', 'res://mcp057_section_probe.gd', '--', 'save_custom', 'res://project.godot') 'save_custom'
$customText = Get-Text $customPath
$commentsGone = (-not $customText.Contains('HAND WRITTEN HEADER')) -and (-not $customText.Contains('deliberately NOT the last section'))
$headerWritten = $customText.StartsWith('; Engine configuration file.')
Check 'p2_save_custom_still_rewrites_the_whole_file' ($customRun.code -eq 0 -and $commentsGone -and $headerWritten) ("header_written={0} hand_comments_gone={1} (declared behaviour, deliberately unchanged)" -f $headerWritten, $commentsGone)

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Nothing of this run may survive as a process: a Godot that could not load the
# probe main loop would otherwise keep running the scratch project forever.
#
# D-2 (TASK-059): this check used to end its predicate with a disjunction against
# the constant `$true`: the predicate was `($swept.Count -eq 0 -or $true)`. A
# disjunction against a constant true is a constant true, so `Check` - which
# increments `$script:Failures` only when its predicate is false - could never
# fail here: the line announced that it verified there was no leftover process
# and verified nothing. The predicate now really inspects the sweep result, and a
# second leg asks the two test ports are free, because a scratch Godot that
# wedged keeps its listener as well as its process. The failure demonstration
# `mcp059_d2_failure_demo.ps1` manufactures exactly the condition this line
# claims to detect and requires this script to exit 1; a true assertion that has
# never been shown to fail is only marginally better than a tautology.
# (The sentence above quotes the old spelling verbatim, so the fix is auditable
# in the file a reader opens. `scripts/check_tautologies.py` pins exactly one
# occurrence of it in this file - this one - and the pin is what makes the
# quotation a recorded decision rather than a new defect.)
$swept = Stop-ScratchEngineProcesses
$busyPorts = @(Get-BusyTestPorts @(9888, 9889))
Check 'p2_no_scratch_engine_process_left' (($swept.Count -eq 0) -and ($busyPorts.Count -eq 0)) ("swept at the end: {0} process id(s) {1}; test ports 9888/9889 still bound: {2}; the 9877 user editor is never matched because it does not name this scratch root" -f $swept.Count, ($swept -join ','), ($busyPorts -join ','))

Write-Host ''
Write-Host '--- summary ---'
$script:Checks | ForEach-Object { Write-Host $_ }
$summaryPath = Join-Path $Root 'summary.txt'
[IO.File]::WriteAllLines($summaryPath, $script:Checks.ToArray())
Write-Host ('--- checks: {0}, failures: {1} ---' -f $script:Checks.Count, $script:Failures)
Write-Host ('--- evidence root: {0} ---' -f $Root)
if ($script:Failures -gt 0) { Write-Host ('SETTINGS-PUBLISH EVIDENCE FAILED: {0}' -f $script:Failures); exit 1 }
Write-Host 'SETTINGS-PUBLISH EVIDENCE PASS'
exit 0
