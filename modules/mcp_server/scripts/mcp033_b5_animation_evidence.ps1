# =============================================================================
#  mcp033_b5_animation_evidence.ps1 -- TASK-033 (B5 batch 1) live evidence
#
#  Two things are proven here, on the real endpoints:
#
#  (A) the three small closures of M4e
#      * D-M4e-2: `running_game_get_node_properties` without a filter now answers
#        the same property set as `editor_get_node_properties` for the same node
#        (measured across the two endpoints, key for key, case sensitive);
#      * D-M4e-3: `project_set_node_property_across_scenes` names the reason
#        nothing was written: a matched directory whose scenes hold no node of the
#        requested type says so, and the "name a directory" sentence appears only
#        when `path_filter` really names a file;
#      * D-M4e-1 is the gate-6 scanner, whose evidence is
#        `scripts/mcp031_gate6_coverage_probes.ps1` (101/101) plus the coverage
#        text checked below.
#
#  (B) gate 2 of the batch: success / missing argument (-32602) / underlying
#      failure (-32001) for each of the 14 animation tools, one cross-tool
#      end-to-end chain with **zero string surgery** (every identifier a step
#      answers is fed into the next step verbatim), and the process-scope proof
#      that all 14 editor-scope tools are absent from the game endpoint (a
#      `tools/call` there is -32601 and never executes).
#
#  Discipline: response bodies go through `curl.exe -s -o <file>` and their
#  sha256 is computed from the bytes on disk; request bodies are built with
#  `ConvertTo-Json` and sent with `--data-binary @file`; ports 9888/9889 only, and
#  the user's own editor on 9877 is asserted to keep the same pid. This file is
#  deliberately pure ASCII.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp033_b5_animation_evidence.ps1
# =============================================================================

param(
    [int]$EditorPort = 9888,
    [int]$GamePort = 9889,
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$Contract = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'task033-b5-animation' }
$Root = $OutRoot
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877
$utf8 = [Text.Encoding]::UTF8

# TASK-028 D-1: the shared scratch-project writer + `--import` runner.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-042 section 1: the shared 9877 classification (see mcp_port_guard.ps1).
. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

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

function New-ListBody {
    param([int]$Id = 1)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/list'; params = [ordered]@{} }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Invoke-Raw {
    param([string]$Id, [string]$Body, [int]$Port_)
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-McpUtf8NoBom -Path $bodyFile -Text $Body
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time 120 -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] port={1} bytes={2} sha256={3}" -f $Id, $Port_, $bytes.Length, $sha)
    return @{ text = $text; sha256 = $sha; file = $respFile; bytes = $bytes.Length }
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 0)
    if ($Port_ -eq 0) { $Port_ = $EditorPort }
    $resp = Invoke-Raw -Id $Id -Body (New-CallBody -Tool $Tool -Arguments $Arguments) -Port_ $Port_
    Write-Host ("       {0}" -f $resp.text)
    return $resp
}

function Get-PayloadText {
    param($Response)
    if ($null -eq $Response) { return '' }
    try {
        $envelope = ConvertFrom-Json ([string]$Response.text)
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
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return 0 }
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.error) { return 0 }
        return [int]$envelope.error.code
    } catch { return 0 }
}

function Get-ErrorMessage {
    param($Response)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.error) { return '' }
        return [string]$envelope.error.message
    } catch { return '' }
}

function Get-ErrorSuggestion {
    param($Response)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.error -or $null -eq $envelope.error.data) { return '' }
        return [string]$envelope.error.data.suggestion
    } catch { return '' }
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $handle = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
    # TASK-042 section 1: record the pid *and* the arguments, so "did this script
    # ever ask for the user's port" is read off the real command line.
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $Arguments
    return $handle
}

function Wait-ForPump {
    param([int]$Port_, [int]$Iterations = 240)
    for ($i = 0; $i -lt $Iterations; $i++) {
        Start-Sleep -Milliseconds 1000
        $out = Join-Path $Ev ("status-{0}.json" -f $Port_)
        & $Curl -s --max-time 5 -o $out ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
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
    }
}

function Get-PropertyKeys {
    param($Payload)
    if ($null -eq $Payload -or $null -eq $Payload.properties) { return @() }
    $names = @()
    foreach ($p in $Payload.properties.PSObject.Properties) { $names += [string]$p.Name }
    return $names
}

# `@($x.Count)` is not a null test in PowerShell: `@($null)` is an array with one
# element, so it counts as 1. Every "is there an entry at [0]" guard below checks
# `$null -ne` first for that reason.
function Get-First {
    param($Collection)
    if ($null -eq $Collection) { return $null }
    $items = @($Collection)
    if ($items.Count -ge 1) { return $items[0] }
    return $null
}

# =============================================================================
# The 14 tools of the batch, with the argument sets gate 2 needs.
#
# `missing` is the set that omits every required member (the -32602 case);
# `fail`    is a complete set whose `node_path` names nothing (the -32001 case).
# The success half is the live chain below - one call per tool, in order.
# =============================================================================
$tools = @(
    @{ name = 'editor_create_animation'; missing = @{}; fail = @{ node_path = 'NoSuchNode'; name = 'idle' } },
    @{ name = 'editor_add_animation_track'; missing = @{}; fail = @{ node_path = 'NoSuchNode'; animation = 'idle'; track_path = '.:position' } },
    @{ name = 'editor_set_animation_keyframe'; missing = @{}; fail = @{ node_path = 'NoSuchNode'; animation = 'idle'; track_index = 0; time = 0.5; value = 1.0 } },
    @{ name = 'editor_remove_animation'; missing = @{}; fail = @{ node_path = 'NoSuchNode'; name = 'idle' } },
    @{ name = 'editor_create_animation_tree'; missing = @{}; fail = @{ node_path = 'NoSuchNode' } },
    @{ name = 'editor_add_state_machine_state'; missing = @{}; fail = @{ node_path = 'NoSuchNode'; state_name = 'Idle' } },
    @{ name = 'editor_add_state_machine_transition'; missing = @{}; fail = @{ node_path = 'NoSuchNode'; from_state = 'Idle'; to_state = 'Walk' } },
    @{ name = 'editor_remove_state_machine_state'; missing = @{}; fail = @{ node_path = 'NoSuchNode'; state_name = 'Idle' } },
    @{ name = 'editor_remove_state_machine_transition'; missing = @{}; fail = @{ node_path = 'NoSuchNode'; from_state = 'Idle'; to_state = 'Walk' } },
    @{ name = 'editor_set_blend_tree_node'; missing = @{}; fail = @{ node_path = 'NoSuchNode'; blend_tree_state = 'Move'; bt_node_name = 'Walk'; bt_node_type = 'Animation' } },
    @{ name = 'editor_set_animation_tree_parameter'; missing = @{}; fail = @{ node_path = 'NoSuchNode'; parameter = 'parameters/Idle/backward'; value = $true } },
    @{ name = 'editor_get_animation_info'; missing = @{}; fail = @{ node_path = 'NoSuchNode'; animation = 'idle' } },
    @{ name = 'editor_get_animation_tree_structure'; missing = @{}; fail = @{ node_path = 'NoSuchNode' } },
    @{ name = 'editor_list_animations'; missing = @{}; fail = @{ node_path = 'NoSuchNode' } }
)

# =============================================================================
# Scratch project
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Proj, (Join-Path $Proj 'scenes'), (Join-Path $Proj 'scenes\empty') | Out-Null

$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp033_b5_animation"'
    'run/main_scene="res://scenes/main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text ($projectGodot + "`n")

$scene = @'
[gd_scene format=3]

[node name="Main" type="Node2D"]

[node name="Actor" type="Node2D" parent="."]
position = Vector2(1, 2)

[node name="Player" type="AnimationPlayer" parent="."]
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text $scene

# A scene that holds no `Node3D` at all: the D-M4e-3 witness.
$emptyScene = @'
[gd_scene format=3]

[node name="Only" type="Node"]
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\empty\only.tscn') -Text $emptyScene

# =============================================================================
# (A1) D-M4e-1: the gate-6 scanner's declared coverage (script level)
# =============================================================================
$narrowScript = Join-Path $PSScriptRoot 'check_narrowing_points.py'
$covLog = Join-Path $LogRoot 'gate6_coverage.log'
& cmd /c "python `"$narrowScript`" --coverage > `"$covLog`" 2>&1"
$covExit = $LASTEXITCODE
$covText = Get-Content -Raw -Encoding UTF8 $covLog
Check 'm4e1_coverage_exits_0' ($covExit -eq 0) ("check_narrowing_points.py --coverage -> exit={0} log={1}" -f $covExit, $covLog)
foreach ($spelling in @('lit_real_t_alias', 'lit_float_range', 'dbl_cast_into_float')) {
    Check ("m4e1_declares_" + $spelling) ($covText.Contains($spelling)) ("--coverage lists the declared spelling '{0}'" -f $spelling)
}
Check 'm4e1_declares_alias_boundary' ($covText -match 'alias of real_t/float declared in') `
    ("--coverage names the boundary it does not cover (a typedef alias declared in another file)")

# TASK-042 section 1: the 9877 judgement is the shared six-way classification,
# not "a listener must exist" - see mcp_port_guard.ps1.
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)
Check 'port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'port_9889_free' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'scratch_project_imported' ($import.exit_code -eq 0) `
    ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

$editorHandle = $null
$gameHandle = $null
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $open = Invoke-Tool -Id 'B0_00_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'scene_opened' ($null -ne (Get-Payload $open)) ("editor_open_scene -> " + (Get-PayloadText $open))

    # -------------------------------------------------------------------------
    # (B) the live chain: 0 string operations between the steps.
    #
    # Each step feeds an identifier the previous answer produced - a track index,
    # a key value object, a node path, a state name, a parameter name - straight
    # into the next call, with the PowerShell object the JSON parser built. No
    # step ever edits, splits, joins or re-spells a string.
    # -------------------------------------------------------------------------
    $created = Invoke-Tool -Id 'C01_create_animation' -Tool 'editor_create_animation' -Arguments @{ node_path = 'Player'; name = 'idle'; length = 2.0 }
    $createdPayload = Get-Payload $created
    Check 'chain_01_create_animation_ok' (($null -ne $createdPayload) -and ($createdPayload.created -eq $true) -and ([double]$createdPayload.length -eq 2.0) -and ([int]$createdPayload.track_count -eq 0)) `
        ("editor_create_animation -> " + (Get-PayloadText $created))

    $track = Invoke-Tool -Id 'C02_add_animation_track' -Tool 'editor_add_animation_track' -Arguments @{ node_path = 'Player'; animation = 'idle'; track_path = '.:position'; track_type = 'position_3d' }
    $trackPayload = Get-Payload $track
    $trackIndex = if ($null -ne $trackPayload) { $trackPayload.track_index } else { -1 }
    Check 'chain_02_add_track_ok' (($null -ne $trackPayload) -and ([int]$trackIndex -eq 0) -and ($trackPayload.track_type -eq 'position_3d')) `
        ("editor_add_animation_track -> track_index={0} type={1}" -f $trackIndex, $trackPayload.track_type)

    $key = Invoke-Tool -Id 'C03_set_keyframe' -Tool 'editor_set_animation_keyframe' -Arguments @{ node_path = 'Player'; animation = 'idle'; track_index = $trackIndex; time = 0.5; value = @{ x = 1.0; y = 2.0; z = 3.0 } }
    $keyPayload = Get-Payload $key
    $keyValue = if ($null -ne $keyPayload) { $keyPayload.value } else { $null }
    Check 'chain_03_set_keyframe_ok' (($null -ne $keyPayload) -and ([int]$keyPayload.key_index -eq 0) -and ([double]$keyPayload.value.x -eq 1.0) -and ([double]$keyPayload.value.y -eq 2.0) -and ([double]$keyPayload.value.z -eq 3.0)) `
        ("editor_set_animation_keyframe -> " + (Get-PayloadText $key))

    # The *returned* value object is fed straight back in, at another time.
    $key2 = Invoke-Tool -Id 'C04_set_keyframe_feed_back' -Tool 'editor_set_animation_keyframe' -Arguments @{ node_path = 'Player'; animation = 'idle'; track_index = $trackIndex; time = 1.0; value = $keyValue }
    $key2Payload = Get-Payload $key2
    Check 'chain_04_key_value_fed_back' (($null -ne $key2Payload) -and ([int]$key2Payload.key_index -eq 1) -and ([int]$key2Payload.key_count -eq 2) -and ([double]$key2Payload.value.z -eq 3.0)) `
        ("the value C03 answered was fed back verbatim -> " + (Get-PayloadText $key2))

    $info = Invoke-Tool -Id 'C05_get_animation_info' -Tool 'editor_get_animation_info' -Arguments @{ node_path = 'Player'; animation = 'idle' }
    $infoPayload = Get-Payload $info
    $trackEntry = $null
    $readKeyValue = $null
    if ($null -ne $infoPayload) { $trackEntry = Get-First $infoPayload.tracks }
    if ($null -ne $trackEntry) { $readKeyValue = (Get-First $trackEntry.keys).value }
    Check 'chain_05_animation_info_reads_back' (($null -ne $trackEntry) -and ([int]$trackEntry.index -eq [int]$trackIndex) -and ($trackEntry.type -eq 'position_3d') -and ([int]$trackEntry.key_count -eq 2) -and ([double]$trackEntry.keys[0].time -eq 0.5) -and ([double]$readKeyValue.z -eq 3.0)) `
        ("editor_get_animation_info -> index={0} type={1} keys={2}" -f $trackEntry.index, $trackEntry.type, $trackEntry.key_count)

    $listed = Invoke-Tool -Id 'C06_list_animations' -Tool 'editor_list_animations' -Arguments @{ node_path = 'Player' }
    $listedPayload = Get-Payload $listed
    Check 'chain_06_list_animations' (($null -ne $listedPayload) -and ([int]$listedPayload.count -eq 1) -and (@($listedPayload.animations) -contains 'idle') -and (@($listedPayload.libraries).Count -ge 1)) `
        ("editor_list_animations -> " + (Get-PayloadText $listed))

    $tree = Invoke-Tool -Id 'C07_create_animation_tree' -Tool 'editor_create_animation_tree' -Arguments @{ node_path = '.'; animation_player_path = 'Player'; name = 'Tree' }
    $treePayload = Get-Payload $tree
    $treePath = if ($null -ne $treePayload) { [string]$treePayload.node_path } else { '' }
    Check 'chain_07_create_animation_tree' (($null -ne $treePayload) -and ($treePath -eq 'Tree') -and ($treePayload.animation_player -eq 'Player') -and ($treePayload.animation_player_source -eq 'animation_player_path') -and ($treePayload.tree_root -eq 'AnimationNodeStateMachine')) `
        ("editor_create_animation_tree -> " + (Get-PayloadText $tree))

    # `node_path` from the answer is fed back; the state names are fed on.
    $stateIdle = Invoke-Tool -Id 'C08_add_state_idle' -Tool 'editor_add_state_machine_state' -Arguments @{ node_path = $treePath; state_name = 'Idle'; state_type = 'animation'; position_x = 10; position_y = 20 }
    $stateIdlePayload = Get-Payload $stateIdle
    Check 'chain_08_add_state_idle' (($null -ne $stateIdlePayload) -and ($stateIdlePayload.state_type -eq 'animation') -and ([double]$stateIdlePayload.position.x -eq 10.0) -and ([int]$stateIdlePayload.state_count -eq 3)) `
        ("editor_add_state_machine_state(Idle) -> " + (Get-PayloadText $stateIdle))

    $stateWalk = Invoke-Tool -Id 'C09_add_state_walk' -Tool 'editor_add_state_machine_state' -Arguments @{ node_path = $treePath; state_name = 'Walk'; state_type = 'animation' }
    $stateWalkPayload = Get-Payload $stateWalk
    Check 'chain_09_add_state_walk' (($null -ne $stateWalkPayload) -and ([int]$stateWalkPayload.state_count -eq 4)) `
        ("editor_add_state_machine_state(Walk) -> " + (Get-PayloadText $stateWalk))

    $transition = Invoke-Tool -Id 'C10_add_transition' -Tool 'editor_add_state_machine_transition' -Arguments @{ node_path = $treePath; from_state = 'Idle'; to_state = 'Walk'; switch_mode = 'at_end'; advance_mode = 'auto' }
    $transitionPayload = Get-Payload $transition
    Check 'chain_10_add_transition' (($null -ne $transitionPayload) -and ($transitionPayload.switch_mode -eq 'at_end') -and ($transitionPayload.advance_mode -eq 'auto') -and ([int]$transitionPayload.transition_count -eq 1)) `
        ("editor_add_state_machine_transition -> " + (Get-PayloadText $transition))

    $structure = Invoke-Tool -Id 'C11_tree_structure' -Tool 'editor_get_animation_tree_structure' -Arguments @{ node_path = $treePath }
    $structurePayload = Get-Payload $structure
    $machine = if ($null -ne $structurePayload) { $structurePayload.state_machine } else { $null }
    $names = @()
    if ($null -ne $machine -and $null -ne $machine.state_names) { $names = @($machine.state_names) }
    $transitionEntry = $null
    if ($null -ne $machine) { $transitionEntry = Get-First $machine.transitions }
    $parameters = @()
    if ($null -ne $structurePayload -and $null -ne $structurePayload.parameters) { $parameters = @($structurePayload.parameters) }
    $parameterNames = @()
    foreach ($entry in $parameters) { $parameterNames += [string]$entry.name }
    Check 'chain_11_structure_reads_back' (($null -ne $machine) -and ($names -contains 'Idle') -and ($names -contains 'Walk') -and ($null -ne $transitionEntry) -and ($transitionEntry.switch_mode -eq 'at_end')) `
        ("editor_get_animation_tree_structure -> states=[{0}] transitions={1}" -f ($names -join ','), @($machine.transitions).Count)
    Check 'chain_11_structure_lists_parameters' ($parameterNames -contains 'parameters/Idle/backward') `
        ("the parameter list is feedable: [{0}]" -f (($parameterNames | Select-Object -First 6) -join ', '))

    # The parameter *name* the read answered is fed straight into the write.
    $parameterName = 'parameters/Idle/backward'
    $paramWrite = Invoke-Tool -Id 'C12_set_tree_parameter' -Tool 'editor_set_animation_tree_parameter' -Arguments @{ node_path = $treePath; parameter = $parameterName; value = $true }
    $paramPayload = Get-Payload $paramWrite
    $storedParameter = if ($null -ne $paramPayload) { [string]$paramPayload.parameter } else { '' }
    Check 'chain_12_set_parameter' (($null -ne $paramPayload) -and ($paramPayload.value -eq $true) -and ($paramPayload.changed.new -eq $true) -and ($storedParameter -eq $parameterName)) `
        ("editor_set_animation_tree_parameter -> " + (Get-PayloadText $paramWrite))

    # ... and the *canonical name the tool answered* is fed back in.
    $paramWrite2 = Invoke-Tool -Id 'C13_set_parameter_feed_back' -Tool 'editor_set_animation_tree_parameter' -Arguments @{ node_path = $treePath; parameter = $storedParameter; value = $false }
    $paramPayload2 = Get-Payload $paramWrite2
    Check 'chain_13_parameter_fed_back' (($null -ne $paramPayload2) -and ($paramPayload2.value -eq $false) -and ($paramPayload2.changed.old -eq $true) -and ($paramPayload2.changed.new -eq $false)) `
        ("the name C12 answered was fed back verbatim -> " + (Get-PayloadText $paramWrite2))

    $blendState = Invoke-Tool -Id 'C14_add_blend_state' -Tool 'editor_add_state_machine_state' -Arguments @{ node_path = $treePath; state_name = 'Move'; state_type = 'blend_tree' }
    $blendStatePayload = Get-Payload $blendState
    Check 'chain_14_add_blend_state' (($null -ne $blendStatePayload) -and ($blendStatePayload.state_type -eq 'blend_tree')) `
        ("editor_add_state_machine_state(Move, blend_tree) -> " + (Get-PayloadText $blendState))

    $btNode = Invoke-Tool -Id 'C15_set_blend_tree_node' -Tool 'editor_set_blend_tree_node' -Arguments @{ node_path = $treePath; blend_tree_state = 'Move'; bt_node_name = 'Walk'; bt_node_type = 'Animation'; position_x = 5; position_y = 6 }
    $btPayload = Get-Payload $btNode
    $btNodes = if ($null -ne $btPayload) { @($btPayload.nodes) } else { @() }
    Check 'chain_15_set_blend_tree_node' (($null -ne $btPayload) -and ($btPayload.class -eq 'AnimationNodeAnimation') -and ($btNodes -contains 'Walk') -and ([double]$btPayload.position.x -eq 5.0)) `
        ("editor_set_blend_tree_node -> " + (Get-PayloadText $btNode))

    $structure2 = Invoke-Tool -Id 'C16_tree_structure_after_blend' -Tool 'editor_get_animation_tree_structure' -Arguments @{ node_path = $treePath }
    $structure2Payload = Get-Payload $structure2
    $blendTrees = @()
    if ($null -ne $structure2Payload -and $null -ne $structure2Payload.state_machine -and $null -ne $structure2Payload.state_machine.blend_trees) { $blendTrees = @($structure2Payload.state_machine.blend_trees) }
    $blendNames = @()
    $blendTree = Get-First $blendTrees
    if ($null -ne $blendTree -and $null -ne $blendTree.nodes) { foreach ($node in @($blendTree.nodes)) { $blendNames += [string]$node.name } }
    Check 'chain_16_structure_sees_blend_tree' (($blendTrees.Count -eq 1) -and ($blendNames -contains 'Walk')) `
        ("editor_get_animation_tree_structure -> blend tree nodes=[{0}]" -f ($blendNames -join ','))

    # --- the destroying half, with real counts ------------------------------
    $removeTransition = Invoke-Tool -Id 'C17_remove_transition' -Tool 'editor_remove_state_machine_transition' -Arguments @{ node_path = $treePath; from_state = 'Idle'; to_state = 'Walk' }
    $removeTransitionPayload = Get-Payload $removeTransition
    Check 'chain_17_remove_transition' (($null -ne $removeTransitionPayload) -and ([int]$removeTransitionPayload.removed -eq 1) -and ([int]$removeTransitionPayload.transition_count -eq 0)) `
        ("editor_remove_state_machine_transition -> " + (Get-PayloadText $removeTransition))

    $removeState = Invoke-Tool -Id 'C18_remove_state' -Tool 'editor_remove_state_machine_state' -Arguments @{ node_path = $treePath; state_name = 'Move' }
    $removeStatePayload = Get-Payload $removeState
    Check 'chain_18_remove_state' (($null -ne $removeStatePayload) -and ([int]$removeStatePayload.removed -eq 1) -and ([int]$removeStatePayload.state_count -eq 4)) `
        ("editor_remove_state_machine_state -> " + (Get-PayloadText $removeState))

    $removeAnimation = Invoke-Tool -Id 'C19_remove_animation' -Tool 'editor_remove_animation' -Arguments @{ node_path = 'Player'; name = 'idle' }
    $removeAnimationPayload = Get-Payload $removeAnimation
    Check 'chain_19_remove_animation' (($null -ne $removeAnimationPayload) -and ([int]$removeAnimationPayload.removed -eq 1) -and ([int]$removeAnimationPayload.animation_count -eq 0)) `
        ("editor_remove_animation -> " + (Get-PayloadText $removeAnimation))

    $gone = Invoke-Tool -Id 'C20_animation_is_really_gone' -Tool 'editor_get_animation_info' -Arguments @{ node_path = 'Player'; animation = 'idle' }
    Check 'chain_20_removed_animation_is_gone' ((Get-ErrorCode $gone) -eq -32001) `
        ("after the removal editor_get_animation_info answers -32001 (code={0})" -f (Get-ErrorCode $gone))
    $removeAgain = Invoke-Tool -Id 'C21_remove_absent_state' -Tool 'editor_remove_state_machine_state' -Arguments @{ node_path = $treePath; state_name = 'Move' }
    Check 'chain_21_removing_absent_state_is_refused' ((Get-ErrorCode $removeAgain) -eq -32001) `
        ("removing an absent state answers -32001 (code={0}) with a suggestion naming the states" -f (Get-ErrorCode $removeAgain))

    # -------------------------------------------------------------------------
    # (B) gate 2, classes 2 and 3: -32602 and -32001 for every tool
    # -------------------------------------------------------------------------
    foreach ($entry in $tools) {
        $missing = Invoke-Tool -Id ("M_" + $entry.name) -Tool $entry.name -Arguments $entry.missing
        Check ("missing_arg_" + $entry.name) ((Get-ErrorCode $missing) -eq -32602) `
            ("{0} without its required members -> -32602 '{1}'" -f $entry.name, (Get-ErrorMessage $missing))
        $failed = Invoke-Tool -Id ("F_" + $entry.name) -Tool $entry.name -Arguments $entry.fail
        $failedCode = Get-ErrorCode $failed
        $failedSuggestion = Get-ErrorSuggestion $failed
        Check ("underlying_failure_" + $entry.name) (($failedCode -eq -32001) -and (-not [string]::IsNullOrEmpty($failedSuggestion))) `
            ("{0} with node_path='NoSuchNode' -> code={1} suggestion='{2}'" -f $entry.name, $failedCode, $failedSuggestion)
    }

    # -------------------------------------------------------------------------
    # (A3) D-M4e-3: the wording of `project_set_node_property_across_scenes`
    # -------------------------------------------------------------------------
    $zeroNodes = Invoke-Tool -Id 'X01_zero_nodes' -Tool 'project_set_node_property_across_scenes' -Arguments @{ path_filter = 'res://scenes/empty'; type = 'Node3D'; property = 'position'; value = @{ x = 1.0; y = 2.0; z = 3.0 } }
    $zeroPayload = Get-Payload $zeroNodes
    $zeroMessage = if ($null -ne $zeroPayload) { [string]$zeroPayload.message } else { '' }
    Check 'm4e3_zero_node_wording' (($null -ne $zeroPayload) -and ([int]$zeroPayload.total_scenes -eq 0) -and $zeroMessage.Contains("None of them contains a node of type 'Node3D'") -and (-not $zeroMessage.Contains('No scene matched'))) `
        ("a matched directory with no Node3D -> '{0}'" -f $zeroMessage)

    $singleFile = Invoke-Tool -Id 'X02_single_file_filter' -Tool 'project_set_node_property_across_scenes' -Arguments @{ path_filter = 'res://scenes/empty/only.tscn'; type = 'Node3D'; property = 'position'; value = @{ x = 1.0; y = 2.0; z = 3.0 } }
    $singlePayload = Get-Payload $singleFile
    $singleMessage = if ($null -ne $singlePayload) { [string]$singlePayload.message } else { '' }
    Check 'm4e3_single_file_wording' (($null -ne $singlePayload) -and ([int]$singlePayload.total_scenes -eq 0) -and $singleMessage.Contains('is a file') -and $singleMessage.Contains('No scene matched')) `
        ("a single .tscn filter -> '{0}'" -f $singleMessage)
    Check 'm4e3_old_sentence_is_gone' ($singleMessage.Contains('not a single scene file') -eq $false) `
        ("the old sentence ('not a single scene file') is no longer emitted: {0}" -f (-not $singleMessage.Contains('not a single scene file')))

    # -------------------------------------------------------------------------
    # (A2) D-M4e-2: the two same-family readers answer the same property set
    # -------------------------------------------------------------------------
    $editorProps = Invoke-Tool -Id 'X03_editor_properties' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor' }
    $editorKeys = Get-PropertyKeys (Get-Payload $editorProps)
    Check 'm4e2_editor_reads_the_full_set' ($editorKeys.Count -ge 40) `
        ("editor_get_node_properties(Actor) -> {0} properties" -f $editorKeys.Count)

    # --- the game endpoint: the same node, the same question ---------------
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, "--mcp-port=$GamePort") -LogName 'game'
    Check 'game_endpoint_ready' (Wait-ForPump -Port_ $GamePort) ("game on {0} answered GET /mcp with +20 frames" -f $GamePort)

    $gameProps = Invoke-Tool -Id 'X04_game_properties' -Tool 'running_game_get_node_properties' -Arguments @{ node_path = 'Actor' } -Port_ $GamePort
    $gameKeys = Get-PropertyKeys (Get-Payload $gameProps)
    Check 'm4e2_game_reads_the_full_set' ($gameKeys.Count -ge 40) `
        ("running_game_get_node_properties(Actor) -> {0} properties" -f $gameKeys.Count)
    $difference = @(Compare-Object -ReferenceObject $editorKeys -DifferenceObject $gameKeys -CaseSensitive)
    # PowerShell 5.1 has no `if` *expression*, so the difference text is built
    # before the format string rather than inside it.
    $differenceText = ''
    if ($difference.Count -gt 0) { $differenceText = ': ' + (($difference | ForEach-Object { $_.InputObject }) -join ', ') }
    Check 'm4e2_same_set_on_both_endpoints' ($difference.Count -eq 0) `
        ("case-sensitive Compare-Object over {0} editor keys and {1} game keys -> {2} difference(s){3}" -f $editorKeys.Count, $gameKeys.Count, $difference.Count, $differenceText)
    Check 'm4e2_wide_set_includes_the_former_gaps' (($editorKeys -contains 'transform') -and ($gameKeys -contains 'transform') -and ($gameKeys -contains 'global_position') -and ($gameKeys -contains 'owner')) `
        ("the keys the filtered reader used to omit (`transform`, `global_position`, `owner`) are answered on both endpoints")

    # -------------------------------------------------------------------------
    # (B) process scope: the 14 tools are absent from 9889
    # -------------------------------------------------------------------------
    $gameList = Invoke-Raw -Id 'X05_game_tools_list' -Body (New-ListBody) -Port_ $GamePort
    $gameNames = @()
    try {
        $gameEnvelope = ConvertFrom-Json ([string]$gameList.text)
        $gameNames = @($gameEnvelope.result.tools | ForEach-Object { [string]$_.name })
    } catch { }
    Check 'scope_game_list_parsed' ($gameNames.Count -ge 50) ("the game endpoint lists {0} tools" -f $gameNames.Count)
    $leaked = @($tools | Where-Object { $gameNames -contains $_.name } | ForEach-Object { $_.name })
    Check 'scope_no_editor_tool_on_the_game_endpoint' ($leaked.Count -eq 0) `
        ("of the 14 editor-scope animation tools, {0} appear on 9889: [{1}]" -f $leaked.Count, ($leaked -join ', '))
    $refused = Invoke-Raw -Id 'X06_game_call_animation' -Body (New-CallBody -Tool 'editor_create_animation' -Arguments @{ node_path = '.'; name = 'nope' }) -Port_ $GamePort
    Check 'scope_game_call_is_method_not_found' (((Get-ErrorCode $refused) -eq -32601) -and ((Get-ErrorMessage $refused) -like '*editor_create_animation*')) `
        ("tools/call on 9889 -> code={0} message='{1}'" -f (Get-ErrorCode $refused), (Get-ErrorMessage $refused))
} finally {
    Stop-Engine -Handle $gameHandle
    Stop-Engine -Handle $editorHandle
}

Start-Sleep -Milliseconds 1500
$portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence
Check 'port_9888_released' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'port_9889_released' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

# -----------------------------------------------------------------------------
$logPath = Join-Path $Root 'summary.json'
$summary = @()
foreach ($entry in $script:Checks) {
    $tag = 'FAIL'
    if ($entry.pass) { $tag = 'PASS' }
    $summary += ("[{0}] {1} :: {2}" -f $tag, $entry.id, $entry.evidence)
}
Write-McpUtf8NoBom -Path $logPath -Text (($summary -join "`r`n") + "`r`n")

$passed = @($script:Checks | Where-Object { $_.pass }).Count
$total = $script:Checks.Count
Write-Host ''
Write-Host '========================== SUMMARY =========================='
foreach ($entry in $script:Checks) {
    $tag = 'FAIL'
    if ($entry.pass) { $tag = 'PASS' }
    Write-Host ("{0}  {1}" -f $tag, $entry.id)
}
Write-Host ("{0}/{1} checks passed; evidence in {2} (summary sha256={3})" -f $passed, $total, $Ev, (Get-FileHash -Algorithm SHA256 -Path $logPath).Hash.ToLower())
if ($passed -ne $total) { exit 1 }
exit 0
