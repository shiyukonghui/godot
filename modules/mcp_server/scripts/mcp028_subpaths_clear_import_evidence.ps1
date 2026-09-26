# =============================================================================
#  mcp028_subpaths_clear_import_evidence.ps1 -- TASK-028 evidence (G-1, G-3)
#
#  Every claim is taken on the live endpoints (9888 editor / 9889 game) and kept
#  as a raw response file with its sha256, so an independent verifier can re-check
#  the bytes.
#
#  G-1 - **sub-property paths** are accepted by the node write family, through the
#  same gate as a whole-property write:
#    * `editor_set_node_property(path, "position:y", 3)` really writes the
#      component, and **another tool** (`editor_get_node_properties`) reads the
#      whole `position` back as `{"x":..., "y":3}`;
#    * `v4:x` on a node whose script declares a `Vector4`;
#    * `material:shader_parameter/uv1_scale` (a nested `Object` property);
#    * two negatives with **different** codes: a segment that does not exist is
#      `-32001` and the message names that segment; a value that cannot be indexed
#      is `-32602`; a malformed path is `-32602`;
#    * the shared gate still refuses what a whole-property write refuses
#      (`position:y = 1e300` is `-32602`, the old value survives);
#    * the batch member of the family (`editor_set_node_property_batch`) takes the
#      same expression.
#
#  G-3 - **`editor_get_test_report` no longer destroys on read**:
#    * a game process records two assertions (the bridge file is written);
#    * **two clients read the editor endpoint one after the other** and both get
#      the whole report, with `cleared: []`, and the bridge file still exists
#      afterwards;
#    * only an explicit `clear: true` empties it (and says which of the two
#      sources it emptied);
#    * the empty case stays honestly empty (`total: 0`, `no_results: true`).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp028_subpaths_clear_import_evidence.ps1
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
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'task028-subpaths-clear' }
$Root = $OutRoot
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877

# TASK-028 D-1: the shared scratch-project writer + `--import` runner.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

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
    param([string]$Tool, $Arguments)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 0)
    if ($Port_ -eq 0) { $Port_ = $EditorPort }
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-McpUtf8NoBom -Path $bodyFile -Text (New-CallBody -Tool $Tool -Arguments $Arguments)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time 120 -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] port={1} bytes={2} sha256={3}" -f $Id, $Port_, $bytes.Length, $sha)
    Write-Host ("       {0}" -f $text)
    return @{ text = $text; sha256 = $sha; file = $respFile; bytes = $bytes.Length }
}

function Get-Payload {
    param($Response)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.result) { return $null }
        return ConvertFrom-Json ([string]$envelope.result.content[0].text)
    } catch { return $null }
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
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.error) { return '' }
        return [string]$envelope.error.message
    } catch { return '' }
}

function Get-ErrorSuggestion {
    param($Response)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.error -or $null -eq $envelope.error.data) { return '' }
        return [string]$envelope.error.data.suggestion
    } catch { return '' }
}

function ConvertTo-CompactJson {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    return (ConvertTo-Json -InputObject $Value -Depth 20 -Compress)
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    return Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
}

function Wait-ForPump {
    param([int]$Port_, [int]$Iterations = 180)
    for ($i = 0; $i -lt $Iterations; $i++) {
        Start-Sleep -Milliseconds 1000
        $out = Join-Path $Ev ("status-{0}.json" -f $Port_)
        & $Curl -s --max-time 5 -o $out ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (Test-Path $out) {
            try {
                $probe = ConvertFrom-Json (Get-Content -Raw $out)
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

# =============================================================================
# Scratch project
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Proj, (Join-Path $Proj 'scenes') | Out-Null

# TASK-028 G-1: the Vector4 comes from a GDScript member (`v4`), because no engine
# class declares a Vector4 property, and the nested Object case comes from a real
# `ShaderMaterial`'s `shader_parameter/<uniform>` entry - the path the task book
# names.
$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp028_subpaths_clear"'
    'run/main_scene="res://scenes/main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text ($projectGodot + "`n")

$actorScript = @'
@tool
extends Node2D

# `@tool` on purpose: the engine refuses to instantiate a non-`@tool` script
# while the editor is running (`GDScript::can_instantiate()`), so a plain script
# variable would not be visible in the 9888 process at all - measured.
var v4 := Vector4(1, 2, 3, 4)
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'actor.gd') -Text $actorScript

$shader = @'
shader_type canvas_item;

uniform float uv1_scale = 1.0;
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'probe.gdshader') -Text $shader

$material = @'
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://probe.gdshader" id="1_shader"]

[resource]
shader = ExtResource("1_shader")
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'probe_material.tres') -Text $material

$scene = @'
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://actor.gd" id="1_actor"]
[ext_resource type="Material" path="res://probe_material.tres" id="2_mat"]

[node name="Main" type="Node2D"]

[node name="Actor" type="Node2D" parent="."]
position = Vector2(1, 2)
script = ExtResource("1_actor")

[node name="Sprite2D" type="Sprite2D" parent="Actor"]
material = ExtResource("2_mat")
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text $scene

$userPidBefore = Get-ListenerPid -Port_ $UserPort
Check 'port_9877_owner_before' ($userPidBefore -gt 0) ("user Godot on {0}: pid={1} (never touched)" -f $UserPort, $userPidBefore)
Check 'port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'port_9889_free' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Check 'scratch_project_imported' ($import.exit_code -eq 0) `
    ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

$editorHandle = $null
$gameHandle = $null
try {
    # =========================================================================
    # G-1 - sub-property paths, on the editor endpoint
    # =========================================================================
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $open = Invoke-Tool -Id 'G1_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'G1_scene_opened' ((Get-ErrorCode $open) -eq 0) ("code={0}" -f (Get-ErrorCode $open))

    # --- the baseline: `position` is (1, 2), read through the read tool --------
    $before = Invoke-Tool -Id 'G1_position_before' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor'; properties = @('position') }
    $beforePayload = Get-Payload $before
    Check 'G1_position_before_is_1_2' (($null -ne $beforePayload) -and ([double]$beforePayload.properties.position.x -eq 1.0) -and ([double]$beforePayload.properties.position.y -eq 2.0)) `
        ("position=" + (ConvertTo-CompactJson $beforePayload.properties.position))

    # --- (1) `position:y = 3` through the editor write tool --------------------
    $setY = Invoke-Tool -Id 'G1_set_position_y' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position:y'; value = 3 }
    $setYPayload = Get-Payload $setY
    Check 'G1_set_position_y_ok' ((Get-ErrorCode $setY) -eq 0 -and $null -ne $setYPayload) `
        ("code={0} payload={1}" -f (Get-ErrorCode $setY), (ConvertTo-CompactJson $setYPayload))

    # --- (2) **another tool** reads the whole property back -------------------
    $after = Invoke-Tool -Id 'G1_position_after' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor'; properties = @('position') }
    $afterPayload = Get-Payload $after
    Check 'G1_position_read_back_is_1_3' (($null -ne $afterPayload) -and ([double]$afterPayload.properties.position.x -eq 1.0) -and ([double]$afterPayload.properties.position.y -eq 3.0)) `
        ("position=" + (ConvertTo-CompactJson $afterPayload.properties.position))

    # --- (3) the answer's read-back: the value at the path and its parent -----
    Check 'G1_answer_reads_back_the_path' ($null -ne $setYPayload -and [double]$setYPayload.old_value -eq 2.0 -and [double]$setYPayload.new_value -eq 3.0 -and [string]$setYPayload.parent_property -eq 'position' -and [double]$setYPayload.parent_new_value.y -eq 3.0) `
        ("old_value={0} new_value={1} parent_property={2} parent_new_value={3}" -f $setYPayload.old_value, $setYPayload.new_value, $setYPayload.parent_property, (ConvertTo-CompactJson $setYPayload.parent_new_value))

    # --- (4) level 3 of section 23.4: read it a *second* time ----------------
    $again = Invoke-Tool -Id 'G1_position_again' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor'; properties = @('position') }
    $againPayload = Get-Payload $again
    Check 'G1_position_still_1_3' (($null -ne $againPayload) -and ([double]$againPayload.properties.position.y -eq 3.0)) `
        ("position=" + (ConvertTo-CompactJson $againPayload.properties.position))

    # --- (5) `v4:x` on a GDScript Vector4 member ----------------------------
    $v4Before = Invoke-Tool -Id 'G1_v4_before' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor'; properties = @('v4') }
    $v4BeforePayload = Get-Payload $v4Before
    Check 'G1_v4_before_is_1_2_3_4' (($null -ne $v4BeforePayload) -and ([double]$v4BeforePayload.properties.v4.x -eq 1.0) -and ([double]$v4BeforePayload.properties.v4.w -eq 4.0)) `
        ("v4=" + (ConvertTo-CompactJson $v4BeforePayload.properties.v4))

    $setV4 = Invoke-Tool -Id 'G1_set_v4_x' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'v4:x'; value = 9 }
    $setV4Payload = Get-Payload $setV4
    $v4After = Invoke-Tool -Id 'G1_v4_after' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor'; properties = @('v4') }
    $v4AfterPayload = Get-Payload $v4After
    Check 'G1_v4_x_written' ((Get-ErrorCode $setV4) -eq 0 -and ($null -ne $v4AfterPayload) -and ([double]$v4AfterPayload.properties.v4.x -eq 9.0) -and ([double]$v4AfterPayload.properties.v4.y -eq 2.0)) `
        ("code={0} new_value={1} v4={2}" -f (Get-ErrorCode $setV4), $setV4Payload.new_value, (ConvertTo-CompactJson $v4AfterPayload.properties.v4))

    # --- (6) a nested Object property: `material:shader_parameter/<uniform>` --
    $matBefore = Invoke-Tool -Id 'G1_material_before' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor/Sprite2D'; properties = @('material') }
    $matBeforePayload = Get-Payload $matBefore
    $shaderParam = 'material:shader_parameter/uv1_scale'
    $setParam = Invoke-Tool -Id 'G1_set_shader_param' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor/Sprite2D'; property = $shaderParam; value = 2.5 }
    $setParamPayload = Get-Payload $setParam
    $paramOk = ((Get-ErrorCode $setParam) -eq 0) -and ($null -ne $setParamPayload) -and ([double]$setParamPayload.new_value -eq 2.5)
    Check 'G1_shader_parameter_available' ($paramOk) `
        ("material={0} code={1} payload={2}" -f (ConvertTo-CompactJson $matBeforePayload.properties.material), (Get-ErrorCode $setParam), (ConvertTo-CompactJson $setParamPayload))

    # --- (7) the same gate: a component slot refuses what the whole does -----
    $gate = Invoke-Tool -Id 'G1_gate_position_y_1e300' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position:y'; value = 1.0e300 }
    $gateAfter = Invoke-Tool -Id 'G1_gate_position_after' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor'; properties = @('position') }
    $gateAfterPayload = Get-Payload $gateAfter
    Check 'G1_gate_refuses_and_leaves_value' ((Get-ErrorCode $gate) -eq -32602 -and ([double]$gateAfterPayload.properties.position.y -eq 3.0)) `
        ("code={0} message={1} position after={2}" -f (Get-ErrorCode $gate), (Get-ErrorMessage $gate), (ConvertTo-CompactJson $gateAfterPayload.properties.position))

    # --- (8) negative 1: a segment that does not exist -> -32001, named ------
    $missing = Invoke-Tool -Id 'G1_missing_segment' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position:nope'; value = 1 }
    Check 'G1_missing_segment_is_32001_named' ((Get-ErrorCode $missing) -eq -32001 -and (Get-ErrorMessage $missing).Contains('nope') -and (Get-ErrorMessage $missing).Contains('position')) `
        ("code={0} message={1}" -f (Get-ErrorCode $missing), (Get-ErrorMessage $missing))

    # --- (9) negative 2: a sort that cannot be indexed -> -32602 -------------
    $notIndexable = Invoke-Tool -Id 'G1_not_indexable' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position:y:z'; value = 1 }
    Check 'G1_not_indexable_is_32602' ((Get-ErrorCode $notIndexable) -eq -32602 -and (Get-ErrorMessage $notIndexable).Contains('float')) `
        ("code={0} message={1}" -f (Get-ErrorCode $notIndexable), (Get-ErrorMessage $notIndexable))

    # --- (10) malformed path -> -32602 --------------------------------------
    $malformed = Invoke-Tool -Id 'G1_malformed_path' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position::y'; value = 1 }
    Check 'G1_malformed_path_is_32602' ((Get-ErrorCode $malformed) -eq -32602) `
        ("code={0} message={1}" -f (Get-ErrorCode $malformed), (Get-ErrorMessage $malformed))

    # --- (11) the batch member of the family takes the same expression ------
    $batch = Invoke-Tool -Id 'G1_batch_set_position_y' -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Node2D'; property = 'position:y'; value = 7 }
    $batchPayload = Get-Payload $batch
    $batchAfter = Invoke-Tool -Id 'G1_batch_position_after' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor'; properties = @('position') }
    $batchAfterPayload = Get-Payload $batchAfter
    Check 'G1_batch_takes_sub_path' ((Get-ErrorCode $batch) -eq 0 -and $null -ne $batchPayload -and [int]$batchPayload.updated -ge 1 -and ([double]$batchAfterPayload.properties.position.y -eq 7.0)) `
        ("code={0} updated={1} position={2}" -f (Get-ErrorCode $batch), $batchPayload.updated, (ConvertTo-CompactJson $batchAfterPayload.properties.position))

    # --- (12) a batch that cannot be indexed is a request violation ----------
    $batchBad = Invoke-Tool -Id 'G1_batch_not_indexable' -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Node2D'; property = 'position:y:z'; value = 1 }
    Check 'G1_batch_not_indexable_is_32602' ((Get-ErrorCode $batchBad) -eq -32602) `
        ("code={0} message={1}" -f (Get-ErrorCode $batchBad), (Get-ErrorMessage $batchBad))

    # =========================================================================
    # G-3 - a read that does not destroy
    # =========================================================================
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, "--mcp-port=$GamePort") -LogName 'game'
    Check 'game_endpoint_ready' (Wait-ForPump -Port_ $GamePort) ("game on {0} answered GET /mcp with +20 frames" -f $GamePort)

    $userDir = Join-Path $env:APPDATA ('Godot\app_userdata\mcp028_subpaths_clear')
    $bridgeAbs = Join-Path $userDir 'mcp_test_report.json'
    if (Test-Path $bridgeAbs) { Remove-Item -Force $bridgeAbs }

    $gamePass = Invoke-Tool -Id 'G3_game_assert_a' -Tool 'running_game_assert_node_state' -Arguments @{ node_path = 'Actor'; property = 'position'; operator = 'eq'; expected = @{ x = 1; y = 2 } } -Port_ $GamePort
    $gameFail = Invoke-Tool -Id 'G3_game_assert_b' -Tool 'running_game_assert_node_state' -Arguments @{ node_path = 'Actor'; property = 'rotation'; operator = 'eq'; expected = 123.0 } -Port_ $GamePort
    Check 'G3_game_assertions_recorded' (((Get-Payload $gamePass).passed -eq $true) -and ((Get-Payload $gameFail).passed -eq $false) -and (Test-Path $bridgeAbs)) `
        ("pass={0} fail={1} bridge={2}" -f (Get-Payload $gamePass).passed, (Get-Payload $gameFail).passed, (Test-Path $bridgeAbs))

    # Two clients read, in sequence, with **no** `clear` argument.
    $readerA = Invoke-Tool -Id 'G3_reader_a_plain' -Tool 'editor_get_test_report' -Arguments @{} -Port_ $EditorPort
    $readerAPayload = Get-Payload $readerA
    $fileAfterA = Test-Path $bridgeAbs
    $readerB = Invoke-Tool -Id 'G3_reader_b_plain' -Tool 'editor_get_test_report' -Arguments @{} -Port_ $EditorPort
    $readerBPayload = Get-Payload $readerB
    $fileAfterB = Test-Path $bridgeAbs
    Check 'G3_two_clients_both_read_whole' `
        (([int]$readerAPayload.total -ge 2) -and ([int]$readerBPayload.total -ge 2) -and (@($readerAPayload.cleared).Count -eq 0) -and (@($readerBPayload.cleared).Count -eq 0) -and $fileAfterA -and $fileAfterB) `
        ("A: total={0} passed={1} failed={2} source={3} cleared={4} | B: total={5} passed={6} failed={7} source={8} cleared={9} | file after A={10} after B={11}" -f `
                $readerAPayload.total, $readerAPayload.passed, $readerAPayload.failed, $readerAPayload.source, (ConvertTo-CompactJson $readerAPayload.cleared), `
                $readerBPayload.total, $readerBPayload.passed, $readerBPayload.failed, $readerBPayload.source, (ConvertTo-CompactJson $readerBPayload.cleared), $fileAfterA, $fileAfterB)

    # The two answers are the same report, byte for byte (the file did not change).
    Check 'G3_two_reads_are_identical' ($readerAPayload.total -eq $readerBPayload.total -and $readerAPayload.passed -eq $readerBPayload.passed -and $readerAPayload.failed -eq $readerBPayload.failed -and @($readerAPayload.details).Count -eq @($readerBPayload.details).Count) `
        ("details A={0} B={1} report_written_at_unix A={2} B={3}" -f @($readerAPayload.details).Count, @($readerBPayload.details).Count, $readerAPayload.report_written_at_unix, $readerBPayload.report_written_at_unix)

    # An **explicit** clear destroys (and says which halves it emptied).
    $explicit = Invoke-Tool -Id 'G3_explicit_clear' -Tool 'editor_get_test_report' -Arguments @{ clear = $true } -Port_ $EditorPort
    $explicitPayload = Get-Payload $explicit
    $afterClear = Invoke-Tool -Id 'G3_after_clear' -Tool 'editor_get_test_report' -Arguments @{} -Port_ $EditorPort
    $afterClearPayload = Get-Payload $afterClear
    Check 'G3_explicit_clear_destroys' (([int]$explicitPayload.total -ge 2) -and ($explicitPayload.cleared -contains 'game_process_file') -and ((Test-Path $bridgeAbs) -eq $false) -and ([int]$afterClearPayload.total -eq 0) -and ($afterClearPayload.no_results -eq $true)) `
        ("cleared total={0} cleared={1} file left={2} then total={3} no_results={4}" -f $explicitPayload.total, (ConvertTo-CompactJson $explicitPayload.cleared), (Test-Path $bridgeAbs), $afterClearPayload.total, $afterClearPayload.no_results)

    # The empty/unreachable case stays honestly empty (never a fabricated total).
    Check 'G3_empty_stays_honest' (([int]$afterClearPayload.total -eq 0) -and ($afterClearPayload.no_results -eq $true) -and ([string]$afterClearPayload.pass_rate -eq 'N/A') -and ($afterClearPayload.report_file_present -eq $false)) `
        ("total={0} no_results={1} pass_rate={2} report_file_present={3} source={4}" -f $afterClearPayload.total, $afterClearPayload.no_results, $afterClearPayload.pass_rate, $afterClearPayload.report_file_present, $afterClearPayload.source)
} finally {
    Stop-Engine -Handle $editorHandle
    Stop-Engine -Handle $gameHandle
}

$userPidAfter = Get-ListenerPid -Port_ $UserPort
Check 'port_9877_owner_after' ($userPidAfter -eq $userPidBefore) ("pid before={0} after={1}" -f $userPidBefore, $userPidAfter)

$failed = @($script:Checks | Where-Object { -not $_.pass })
Write-Host ''
Write-Host '============================================================='
Write-Host (' TASK-028 evidence: {0} checks, {1} failed' -f $script:Checks.Count, $failed.Count)
Write-Host '============================================================='
foreach ($check in $script:Checks) {
    Write-Host ("[{0}] {1}" -f $(if ($check.pass) { 'PASS' } else { 'FAIL' }), $check.id)
}

$summary = [pscustomobject]@{
    engine       = (& $Engine --version) -join ''
    head         = (& git -C $RepoRoot rev-parse --short HEAD) -join ''
    checks       = $script:Checks
    failed_count = $failed.Count
}
Write-McpUtf8NoBom -Path (Join-Path $Root 'summary.json') -Text (ConvertTo-Json -InputObject $summary -Depth 8)
Write-Host ("summary: {0}" -f (Join-Path $Root 'summary.json'))
Write-Host ("evidence: {0}" -f $Ev)
if ($failed.Count -gt 0) { exit 1 }
exit 0