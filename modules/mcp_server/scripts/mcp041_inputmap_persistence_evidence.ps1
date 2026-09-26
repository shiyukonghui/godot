# =============================================================================
#  mcp041_inputmap_persistence_evidence.ps1 -- TASK-041 section 2 (M-6)
#
#  The question this script answers end to end, in one run:
#
#    does `editor_add_input_action` really put an action where a *game* can see
#    it, and is the answer's `persisted` a measurement of the disk rather than a
#    promise?
#
#  The chain, all of it on the wire:
#
#    1. a scratch project with no `[input]` section at all (sha256 recorded);
#    2. editor #1 on 9888: `editor_get_input_actions` does not know the action,
#       `editor_add_input_action` creates it and answers `persisted: true`,
#       the project.godot on disk gains the `[input]` entry (read back by this
#       script from the file), a second identical call leaves the same bytes;
#    3. the honest negative: a name `ProjectSettings` cannot address as one key
#       answers `persisted: false` + a reason, is still created in the editor's
#       InputMap, and is **not** on disk;
#    4. the game half: `editor_play_scene` starts a real game process on 9889 and
#       `running_game_execute_gdscript` asks *that* process'
#       `InputMap.has_action(...)` - which is the only statement that matters;
#    5. a game process started **directly** on 9889 (the port TASK-041 section 1
#       released) reads the same file at its own startup and sees the action too;
#    6. a fresh editor process is asked the same question and must **not** see it,
#       because an editor process' `InputMap` is `load_default()` - the built-in
#       editor keys - and only a game loads the project's `[input]` section
#       (`main/main.cpp:2330-2336`). That check pins the engine fact that makes
#       `editor_get_input_actions` the wrong oracle for persistence, instead of
#       leaving a reader to assume the opposite.
#
#  Every response is produced by `curl.exe -s -o <file>` and its sha256 is
#  printed (PLAYBOOK section 7.1: a pipe must never carry a response body).
#  Port discipline: 9877 is only *observed*, never touched; 9888 / 9889 are used
#  and both must be free before the run (TASK-041 section 1 released the TASK-039
#  leftover on 9889; the run asserts it is empty instead of assuming it).
#  The scratch project lives in %TEMP% and every file is written without a BOM
#  through the shared `mcp_import_guard.ps1` helpers.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp041_inputmap_persistence_evidence.ps1
# =============================================================================

param(
    [int]$EditorPort = 9888,
    [int]$GamePort = 9889
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$Root = Join-Path $env:TEMP 'mcp041-inputmap'
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877
$utf8 = [Text.Encoding]::UTF8
$Action = 'mcp041_drive_forward'
$DottedAction = 'mcp041.dotted'

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Note { param([string]$Text) Write-Host ("NOTE   {0}" -f $Text) }

function Get-ListenerPid {
    param([int]$Port_)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port_ + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

function New-CallBody {
    param([string]$Tool, $Arguments, [int]$Id = 1)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Invoke-Raw {
    param([string]$Id, [string]$Body, [int]$Port_)
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-McpUtf8NoBom -Path $bodyFile -Text $Body
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl '-s' '--max-time' '120' '-o' $respFile '-H' 'Content-Type: application/json' '--data-binary' ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] port={1} bytes={2} sha256={3}" -f $Id, $Port_, $bytes.Length, $sha)
    Write-Host ("       {0}" -f $text)
    return @{ id = $Id; text = $text; sha256 = $sha; file = $respFile; bytes = $bytes.Length }
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 0)
    if ($Port_ -eq 0) { $Port_ = $EditorPort }
    return Invoke-Raw -Id $Id -Body (New-CallBody -Tool $Tool -Arguments $Arguments) -Port_ $Port_
}

function Get-Envelope {
    param($Response)
    try { return ConvertFrom-Json ([string]$Response.text) } catch { return $null }
}

function Get-PayloadText {
    param($Response)
    try {
        $envelope = Get-Envelope $Response
        if ($null -eq $envelope.result) { return '' }
        return [string]$envelope.result.content[0].text
    } catch { return '' }
}

function Get-Payload {
    param($Response)
    $text = Get-PayloadText $Response
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return ConvertFrom-Json $text } catch { return $null }
}

function Get-ErrorCode {
    param($Response)
    $envelope = Get-Envelope $Response
    if ($null -eq $envelope -or $null -eq $envelope.error) { return 0 }
    return [int]$envelope.error.code
}

function Get-ErrorMessage {
    param($Response)
    $envelope = Get-Envelope $Response
    if ($null -eq $envelope -or $null -eq $envelope.error) { return '' }
    return [string]$envelope.error.message
}

function Get-PropertyValue {
    param($Object_, [string]$Name)
    if ($null -eq $Object_) { return $null }
    foreach ($p in $Object_.PSObject.Properties) { if ([string]$p.Name -ceq $Name) { return $p.Value } }
    return $null
}

function Has-Property {
    param($Object_, [string]$Name)
    if ($null -eq $Object_) { return $false }
    foreach ($p in $Object_.PSObject.Properties) { if ([string]$p.Name -ceq $Name) { return $true } }
    return $false
}

# The `[input]` section of a project.godot, from its header to the next `[`
# header (or EOF). The *text* is used on purpose here - unlike "is this tool
# online", where PLAYBOOK section 7.4 forbids text matching, "is this byte
# pattern in the configuration file" is exactly the question, and the same file
# is also parsed structurally by the doctest with the engine's own `ConfigFile`.
function Get-InputSection {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    $text = [IO.File]::ReadAllText($Path, $utf8)
    $start = $text.IndexOf("[input]")
    if ($start -lt 0) { return '' }
    $rest = $text.Substring($start)
    $next = $rest.IndexOf("`n[", 1)
    if ($next -ge 0) { return $rest.Substring(0, $next) }
    return $rest
}

function Test-ActionInPayload {
    param($Payload, [string]$Name)
    if ($null -eq $Payload) { return $false }
    $actions = Get-PropertyValue $Payload 'actions'
    if ($null -eq $actions) { return $false }
    return ($actions -ccontains $Name)
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    return Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
}

function Wait-ForPump {
    param([int]$Port_, [int]$Iterations = 240)
    for ($i = 0; $i -lt $Iterations; $i++) {
        Start-Sleep -Milliseconds 1000
        $out = Join-Path $Ev ("status-{0}.json" -f $Port_)
        & $Curl '-s' '--max-time' '5' '-o' $out ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (Test-Path $out) {
            try {
                $probe = ConvertFrom-Json ([IO.File]::ReadAllText($out, $utf8))
                if ($null -ne $probe.frame_count -and [int]$probe.frame_count -ge 20) { return $true }
            } catch { }
        }
    }
    return $false
}

function Stop-Engine {
    param($Handle)
    if ($null -ne $Handle -and -not $Handle.HasExited) {
        Stop-Process -Id $Handle.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

# =============================================================================
#  Scratch project: no `[input]` section, one scene a game can run
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, (Join-Path $Proj 'scenes') | Out-Null

$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp041"'
    'run/main_scene="res://scenes/main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
$projectPath = Join-Path $Proj 'project.godot'
Write-McpUtf8NoBom -Path $projectPath -Text ($projectGodot + "`n")

$mainScene = @'
[gd_scene format=3]

[node name="Main" type="Node2D"]
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text $mainScene

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Check 'A01_scratch_project_imported' ($import.exit_code -eq 0) ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

$userPidBefore = Get-ListenerPid -Port_ $UserPort
Note ("port {0} owner before: {1} (observed only; this run never binds, kills or restarts it)" -f $UserPort, $userPidBefore)
Check 'A02_port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'A03_port_9889_free' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1} (TASK-041 section 1 released the TASK-039 leftover; the run starts from an empty port)" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

$beforeText = [IO.File]::ReadAllText($projectPath, $utf8)
$beforeSha = (Get-FileHash -Algorithm SHA256 -Path $projectPath).Hash.ToLower()
Check 'A04_project_godot_has_no_input_section_yet' ((-not $beforeText.Contains('[input]')) -and (-not $beforeText.Contains('InputEventKey'))) `
    ("sha256={0} bytes={1} has_[input]={2} has_InputEventKey={3}" -f $beforeSha, $beforeText.Length, $beforeText.Contains('[input]'), $beforeText.Contains('InputEventKey'))

$editorHandle = $null
$gameHandle = $null
$script:ownGamePort = 0
try {
    # =========================================================================
    #  Editor #1: the write, the disk read-back and the honest negative
    # =========================================================================
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor1'
    Check 'B01_editor1_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    # The action the editor process' map does not know yet. The list is parsed as
    # a set (PLAYBOOK section 7.4: never "the name appears somewhere in the text").
    $listBefore = Invoke-Tool -Id 'B02_list_before' -Tool 'editor_get_input_actions' -Arguments @{}
    $listBeforePayload = Get-Payload $listBefore
    Check 'B02_action_absent_before_the_call' (((Get-ErrorCode $listBefore) -eq 0) -and (-not (Test-ActionInPayload $listBeforePayload $Action))) `
        ("editor_get_input_actions count={0}; contains '{1}'={2}" -f (Get-PropertyValue $listBeforePayload 'count'), $Action, (Test-ActionInPayload $listBeforePayload $Action))

    $create = Invoke-Tool -Id 'B03_add_input_action' -Tool 'editor_add_input_action' -Arguments @{ action = $Action; key = 'W' }
    $createPayload = Get-Payload $create
    Check 'B03_editor_add_input_action_ok' ((Get-ErrorCode $create) -eq 0) ("code={0} payload={1}" -f (Get-ErrorCode $create), (Get-PayloadText $create))
    Check 'B04_persisted_is_true' ([bool](Get-PropertyValue $createPayload 'persisted') -eq $true) ("persisted={0}" -f (Get-PropertyValue $createPayload 'persisted'))
    Check 'B05_persisted_reason_is_empty_on_success' ((Has-Property $createPayload 'persisted_reason') -and ([string](Get-PropertyValue $createPayload 'persisted_reason') -eq '')) `
        ("persisted_reason='{0}'" -f (Get-PropertyValue $createPayload 'persisted_reason'))
    Check 'B06_created_and_event_count' (([bool](Get-PropertyValue $createPayload 'created') -eq $true) -and ([int](Get-PropertyValue $createPayload 'event_count') -eq 1) -and ([string](Get-PropertyValue $createPayload 'key') -eq 'W')) `
        ("created={0} event_count={1} key={2}" -f (Get-PropertyValue $createPayload 'created'), (Get-PropertyValue $createPayload 'event_count'), (Get-PropertyValue $createPayload 'key'))

    # The disk, read by this script - not by the tool that decided `persisted`.
    $afterCreateText = [IO.File]::ReadAllText($projectPath, $utf8)
    $afterCreateSha = (Get-FileHash -Algorithm SHA256 -Path $projectPath).Hash.ToLower()
    $inputSection = Get-InputSection $projectPath
    Check 'B07_project_godot_gained_the_input_section' ($inputSection.Contains(($Action + '='))) `
        ("sha256 {0} -> {1}; [input] section bytes={2}" -f $beforeSha.Substring(0, 16), $afterCreateSha.Substring(0, 16), $inputSection.Length)
    Check 'B08_disk_entry_has_the_engine_shape' ($inputSection.Contains('"deadzone"') -and $inputSection.Contains('"events"') -and $inputSection.Contains('Object(InputEventKey') -and $inputSection.Contains('"keycode"')) `
        ("[input] section: {0}" -f (($inputSection -replace "`r", ' ' -replace "`n", ' | ').Trim()))
    Check 'B09_project_godot_bytes_really_changed' ($afterCreateSha -ne $beforeSha) ("before={0} after={1}" -f $beforeSha, $afterCreateSha)

    # Idempotence: the same call again must not change the file.
    $again = Invoke-Tool -Id 'B10_add_again' -Tool 'editor_add_input_action' -Arguments @{ action = $Action; key = 'W' }
    $againPayload = Get-Payload $again
    $afterAgainSha = (Get-FileHash -Algorithm SHA256 -Path $projectPath).Hash.ToLower()
    Check 'B10_second_identical_call_is_idempotent' (([bool](Get-PropertyValue $againPayload 'persisted') -eq $true) -and ([bool](Get-PropertyValue $againPayload 'created') -eq $false) -and ([int](Get-PropertyValue $againPayload 'event_count') -eq 1) -and ($afterAgainSha -eq $afterCreateSha)) `
        ("persisted={0} created={1} event_count={2} sha256 unchanged={3}" -f (Get-PropertyValue $againPayload 'persisted'), (Get-PropertyValue $againPayload 'created'), (Get-PropertyValue $againPayload 'event_count'), ($afterAgainSha -eq $afterCreateSha))

    # A call without `key` still publishes the action (and its existing event).
    $noKey = Invoke-Tool -Id 'B11_add_without_key' -Tool 'editor_add_input_action' -Arguments @{ action = $Action }
    $noKeyPayload = Get-Payload $noKey
    $afterNoKeySha = (Get-FileHash -Algorithm SHA256 -Path $projectPath).Hash.ToLower()
    Check 'B11_keyless_call_keeps_it_persisted' (([bool](Get-PropertyValue $noKeyPayload 'persisted') -eq $true) -and ([int](Get-PropertyValue $noKeyPayload 'event_count') -eq 1) -and ($afterNoKeySha -eq $afterCreateSha)) `
        ("persisted={0} event_count={1} key='{2}' sha256 unchanged={3}" -f (Get-PropertyValue $noKeyPayload 'persisted'), (Get-PropertyValue $noKeyPayload 'event_count'), (Get-PropertyValue $noKeyPayload 'key'), ($afterNoKeySha -eq $afterCreateSha))

    # The honest negative: a name ProjectSettings cannot address as one key.
    $dotted = Invoke-Tool -Id 'B12_add_dotted_name' -Tool 'editor_add_input_action' -Arguments @{ action = $DottedAction; key = 'Q' }
    $dottedPayload = Get-Payload $dotted
    $dottedReason = [string](Get-PropertyValue $dottedPayload 'persisted_reason')
    Check 'B12_unaddressable_name_is_false_with_a_reason' (((Get-ErrorCode $dotted) -eq 0) -and ([bool](Get-PropertyValue $dottedPayload 'persisted') -eq $false) -and ($dottedReason.Length -gt 0)) `
        ("code={0} persisted={1} reason='{2}'" -f (Get-ErrorCode $dotted), (Get-PropertyValue $dottedPayload 'persisted'), $dottedReason)

    $listAfter = Invoke-Tool -Id 'B13_list_after' -Tool 'editor_get_input_actions' -Arguments @{}
    $listAfterPayload = Get-Payload $listAfter
    $dottedOnDisk = (Get-InputSection $projectPath).Contains($DottedAction)
    Check 'B14_rejected_name_is_still_in_this_process_map_only' ((Test-ActionInPayload $listAfterPayload $Action) -and (Test-ActionInPayload $listAfterPayload $DottedAction) -and (-not $dottedOnDisk)) `
        ("in-memory list: {0}={1} {2}={3}; on disk: {4}={5}" -f $Action, (Test-ActionInPayload $listAfterPayload $Action), $DottedAction, (Test-ActionInPayload $listAfterPayload $DottedAction), $DottedAction, $dottedOnDisk)

    # =========================================================================
    #  The game half: a real game process, asked about *its own* InputMap
    # =========================================================================
    $play = Invoke-Tool -Id 'C01_play_scene' -Tool 'editor_play_scene' -Arguments @{ mode = 'current' }
    $playPayload = Get-Payload $play
    $reportedPort = Get-PropertyValue $playPayload 'mcp_port'
    $gamePortActual = $GamePort
    if ($null -ne $reportedPort) { $gamePortActual = [int]$reportedPort }
    $script:ownGamePort = $gamePortActual
    Check 'C01_play_scene_started_a_game' (((Get-ErrorCode $play) -eq 0) -and ($null -ne $reportedPort)) ("code={0} mcp_port={1} payload={2}" -f (Get-ErrorCode $play), $reportedPort, (Get-PayloadText $play))
    Check 'C02_game_endpoint_ready' (Wait-ForPump -Port_ $gamePortActual) ("game on {0} ready" -f $gamePortActual)

    Start-Sleep -Seconds 3
    $hasCode = 'return InputMap.has_action("' + $Action + '")'
    $has = Invoke-Tool -Id 'C03_game_has_action' -Port_ $gamePortActual -Tool 'running_game_execute_gdscript' -Arguments @{ code = $hasCode }
    $hasPayload = Get-Payload $has
    Check 'C03_game_sees_the_action' (((Get-ErrorCode $has) -eq 0) -and ([bool](Get-PropertyValue $hasPayload 'result') -eq $true)) `
        ("game process InputMap.has_action('{0}') = {1} (payload {2})" -f $Action, (Get-PropertyValue $hasPayload 'result'), (Get-PayloadText $has))

    $countCode = 'return InputMap.action_get_events("' + $Action + '").size()'
    $count = Invoke-Tool -Id 'C04_game_action_event_count' -Port_ $gamePortActual -Tool 'running_game_execute_gdscript' -Arguments @{ code = $countCode }
    $countPayload = Get-Payload $count
    Check 'C04_game_sees_the_bound_key' (((Get-ErrorCode $count) -eq 0) -and ([int](Get-PropertyValue $countPayload 'result') -eq 1)) `
        ("game process InputMap.action_get_events('{0}').size() = {1}" -f $Action, (Get-PropertyValue $countPayload 'result'))

    $dottedCode = 'return InputMap.has_action("' + $DottedAction + '")'
    $dottedHas = Invoke-Tool -Id 'C05_game_does_not_have_the_rejected_name' -Port_ $gamePortActual -Tool 'running_game_execute_gdscript' -Arguments @{ code = $dottedCode }
    $dottedHasPayload = Get-Payload $dottedHas
    Check 'C05_game_does_not_see_the_rejected_name' (((Get-ErrorCode $dottedHas) -eq 0) -and ([bool](Get-PropertyValue $dottedHasPayload 'result') -eq $false)) `
        ("game process InputMap.has_action('{0}') = {1}" -f $DottedAction, (Get-PropertyValue $dottedHasPayload 'result'))

    $stop = Invoke-Tool -Id 'C06_stop_scene' -Tool 'editor_stop_scene' -Arguments @{}
    Note ("editor_stop_scene code={0}" -f (Get-ErrorCode $stop))
    Start-Sleep -Seconds 3
}
finally {
    Stop-Engine -Handle $editorHandle
    Stop-Engine -Handle $gameHandle
    if ($script:ownGamePort -gt 0 -and $script:ownGamePort -ne $UserPort) {
        $ownPid = Get-ListenerPid -Port_ $script:ownGamePort
        if ($ownPid -gt 0) { Stop-Process -Id $ownPid -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
    }
}

# =============================================================================
#  A game process of its own on 9889: it reads project.godot at its own startup
# =============================================================================
$gameHandle = $null
try {
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, "--mcp-port=$GamePort") -LogName 'game-direct'
    Check 'D01_direct_game_endpoint_ready' (Wait-ForPump -Port_ $GamePort) ("a game process started directly on {0} (the port TASK-041 released) answered +20 frames" -f $GamePort)

    $directHas = Invoke-Tool -Id 'D02_direct_game_has_action' -Port_ $GamePort -Tool 'running_game_execute_gdscript' -Arguments @{ code = $hasCode }
    $directHasPayload = Get-Payload $directHas
    Check 'D02_direct_game_sees_the_action_at_startup' (((Get-ErrorCode $directHas) -eq 0) -and ([bool](Get-PropertyValue $directHasPayload 'result') -eq $true)) `
        ("game process InputMap.has_action('{0}') = {1}" -f $Action, (Get-PropertyValue $directHasPayload 'result'))

    $directCount = Invoke-Tool -Id 'D03_direct_game_event_count' -Port_ $GamePort -Tool 'running_game_execute_gdscript' -Arguments @{ code = $countCode }
    $directCountPayload = Get-Payload $directCount
    Check 'D03_direct_game_sees_the_bound_key' ([int](Get-PropertyValue $directCountPayload 'result') -eq 1) `
        ("game process InputMap.action_get_events('{0}').size() = {1}" -f $Action, (Get-PropertyValue $directCountPayload 'result'))

    $directDotted = Invoke-Tool -Id 'D04_direct_game_rejected_name_absent' -Port_ $GamePort -Tool 'running_game_execute_gdscript' -Arguments @{ code = $dottedCode }
    $directDottedPayload = Get-Payload $directDotted
    Check 'D04_direct_game_does_not_see_the_rejected_name' ([bool](Get-PropertyValue $directDottedPayload 'result') -eq $false) `
        ("game process InputMap.has_action('{0}') = {1}" -f $DottedAction, (Get-PropertyValue $directDottedPayload 'result'))

    $finalText = [IO.File]::ReadAllText($projectPath, $utf8)
    $finalSha = (Get-FileHash -Algorithm SHA256 -Path $projectPath).Hash.ToLower()
    Check 'D05_no_game_start_rewrote_the_file' (($finalSha -eq $afterCreateSha) -and $finalText.Contains($Action)) `
        ("sha256={0} (the same as after the write)" -f $finalSha)
}
finally {
    Stop-Engine -Handle $gameHandle
}

# =============================================================================
#  A fresh *editor* process: the engine fact that makes the list a bad oracle
# =============================================================================
$editorHandle = $null
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor2'
    Check 'E01_editor2_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("a second editor process on {0} answered +20 frames" -f $EditorPort)

    $freshList = Invoke-Tool -Id 'E02_editor2_list' -Tool 'editor_get_input_actions' -Arguments @{}
    $freshPayload = Get-Payload $freshList
    Check 'E02_editor_process_never_loads_the_projects_input_section' (((Get-ErrorCode $freshList) -eq 0) -and (-not (Test-ActionInPayload $freshPayload $Action))) `
        ("editor_get_input_actions count={0}; contains '{1}'={2} - `main.cpp:2333` gives an editor `load_default()` (built-in editor keys) and only a game `load_from_project_settings()`, so this list can never be the persistence oracle" -f (Get-PropertyValue $freshPayload 'count'), $Action, (Test-ActionInPayload $freshPayload $Action))
    Check 'E03_editor_process_does_not_have_the_rejected_name' (-not (Test-ActionInPayload $freshPayload $DottedAction)) `
        ("contains '{0}'={1}" -f $DottedAction, (Test-ActionInPayload $freshPayload $DottedAction))
}
finally {
    Stop-Engine -Handle $editorHandle
}

Start-Sleep -Seconds 2
$userPidAfter = Get-ListenerPid -Port_ $UserPort
Check 'F01_port_9877_owner_unchanged' ($userPidAfter -eq $userPidBefore) ("port {0} owner before={1} after={2}" -f $UserPort, $userPidBefore, $userPidAfter)
Check 'F02_ports_released_after_the_run' (((Get-ListenerPid -Port_ $EditorPort) -eq -1) -and ((Get-ListenerPid -Port_ $GamePort) -eq -1)) `
    ("port {0} owner={1}; port {2} owner={3}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort), $GamePort, (Get-ListenerPid -Port_ $GamePort))

$checksPath = Join-Path $Root 'checks.json'
$checkLines = New-Object System.Collections.Generic.List[string]
foreach ($c in $script:Checks) {
    $id = ([string]$c.id).Replace('\', '\\').Replace('"', '\"')
    $evidenceText = ([string]$c.evidence).Replace('\', '\\').Replace('"', '\"').Replace("`r", ' ').Replace("`n", ' ')
    $boolText = if ($c.pass) { 'true' } else { 'false' }
    $checkLines.Add('{"id":"' + $id + '","pass":' + $boolText + ',"evidence":"' + $evidenceText + '"}')
}
Write-McpUtf8NoBom -Path $checksPath -Text (($checkLines -join "`n") + "`n")

$failed = @($script:Checks | Where-Object { -not $_.pass })
Write-Host ''
Write-Host ("========== {0} checks, {1} failed ==========" -f $script:Checks.Count, $failed.Count)
foreach ($f in $failed) { Write-Host ("FAIL {0}: {1}" -f $f.id, $f.evidence) }
Write-Host ("checks: {0}" -f $checksPath)
Write-Host ("evidence: {0}" -f $Ev)

if ($failed.Count -gt 0) { exit 1 }
exit 0
