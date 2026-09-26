# =============================================================================
#  mcp040_defect_probes.ps1 -- TASK-040 red/green probes for D-1 / D-2 / D-3
#
#  D-1  editor_add_resource_to_node_property on a property the node does NOT
#       have, and on a property that exists but cannot hold the resource type
#  D-2  editor_connect_signal -> editor_save_scene -> restart -> is the
#       connection still there (disk + tools), and can it be disconnected
#  D-3  running_game_get_node_properties on a name the node does not have
#       (compared with the same endpoint's running_game_set_node_property)
#
#  Every response is produced by `curl.exe -s -o <file>` and its sha256 is
#  printed (PLAYBOOK section 7.1: a pipe must never carry a response body).
#  Port discipline: 9877 is only *observed*, never touched; 9888 / 9889 are used.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp040_defect_probes.ps1 -Label base
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp040_defect_probes.ps1 -Label fix
# =============================================================================

param(
    [int]$EditorPort = 9888,
    [int]$GamePort = 9889,
    [string]$Label = 'base'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$Root = Join-Path $env:TEMP ('mcp040-' + $Label)
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877
$utf8 = [Text.Encoding]::UTF8

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

function Get-ErrorSuggestion {
    param($Response)
    $envelope = Get-Envelope $Response
    if ($null -eq $envelope -or $null -eq $envelope.error -or $null -eq $envelope.error.data) { return '' }
    return [string]$envelope.error.data.suggestion
}

function Has-Property {
    param($Object_, [string]$Name)
    if ($null -eq $Object_) { return $false }
    foreach ($p in $Object_.PSObject.Properties) { if ([string]$p.Name -ceq $Name) { return $true } }
    return $false
}

function Get-PropertyValue {
    param($Object_, [string]$Name)
    if ($null -eq $Object_) { return $null }
    foreach ($p in $Object_.PSObject.Properties) { if ([string]$p.Name -ceq $Name) { return $p.Value } }
    return $null
}

function Get-NodePropertyValue {
    param($Payload, [string]$Name)
    if ($null -eq $Payload) { return $null }
    return Get-PropertyValue (Get-PropertyValue $Payload 'properties') $Name
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

# The connection line of a .tscn, or an empty string when there is none.
function Get-ConnectionBlock {
    param([string]$ScenePath)
    $text = [IO.File]::ReadAllText($ScenePath, $utf8)
    $lines = $text -split "`n"
    $hits = @()
    foreach ($line in $lines) { if ($line.TrimStart().StartsWith('[connection')) { $hits += $line.Trim() } }
    return @{ count = $hits.Count; lines = $hits; text = $text }
}

# =============================================================================
#  Scratch project
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, (Join-Path $Proj 'scenes') | Out-Null

$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp040"'
    'run/main_scene="res://scenes/main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text ($projectGodot + "`n")

# `Car` is a CharacterBody2D: `physics_material_override` exists on RigidBody2D /
# StaticBody2D only (rigid_body_2d.cpp:754, static_body_2d.cpp:235), never on
# CharacterBody2D. `Button` is a CanvasItem: it really has `material` (a
# CanvasItemMaterial/ShaderMaterial slot) and does NOT accept a `Gradient`.
$mainScene = @'
[gd_scene format=3]

[node name="Main" type="Node2D"]

[node name="Car" type="CharacterBody2D" parent="."]

[node name="Button" type="Button" parent="."]
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text $mainScene
$scenePath = Join-Path $Proj 'scenes\main.tscn'

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Check 'scratch_project_imported' ($import.exit_code -eq 0) ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

$userPidBefore = Get-ListenerPid -Port_ $UserPort
Note ("port {0} owner before: {1} (this run never binds it)" -f $UserPort, $userPidBefore)
$gamePortOwnerBefore = Get-ListenerPid -Port_ $GamePort
Note ("port {0} owner before: {1} - the leftover TASK-039 racing game; it is recorded, never killed, and this run's game child takes a tool-picked free port" -f $GamePort, $gamePortOwnerBefore)
Check 'port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))

$editorHandle = $null
$gameHandle = $null
$script:ownGamePort = 0
$script:racingPid = -1
try {
    # =========================================================================
    #  Editor #1: D-1 and the write half of D-2 / D-3
    # =========================================================================
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor1'
    Check 'editor1_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $open = Invoke-Tool -Id 'A00_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'A00_open_scene_ok' ((Get-ErrorCode $open) -eq 0) ("editor_open_scene code={0}" -f (Get-ErrorCode $open))

    # -------------------------------------------------------------------------
    #  D-1 -- the write side (red baseline: `ok` + nothing happened)
    # -------------------------------------------------------------------------
    $readMissing = Invoke-Tool -Id 'A01_read_physics_material_override' -Tool 'editor_get_node_properties' -Arguments @{
        path = 'Car'; properties = @('physics_material_override')
    }
    Check 'D1_reference_read_is_not_found' ((Get-ErrorCode $readMissing) -eq -32001) `
        ("editor_get_node_properties(Car.physics_material_override) code={0}" -f (Get-ErrorCode $readMissing))

    $addMissing = Invoke-Tool -Id 'A02_add_resource_on_missing_property' -Tool 'editor_add_resource_to_node_property' -Arguments @{
        node_path = 'Car'; property = 'physics_material_override'
        resource_type = 'PhysicsMaterial'; resource_properties = @{ friction = 0.1; bounce = 0.0 }
    }
    $addMissingCode = Get-ErrorCode $addMissing
    $addMissingPayload = Get-Payload $addMissing
    $addMissingHasOld = Has-Property $addMissingPayload 'old_value'
    Check 'D1_add_resource_on_missing_property_refused' ($addMissingCode -eq -32001) `
        ("code={0} (want -32001) message='{1}' suggestion='{2}'" -f $addMissingCode, (Get-ErrorMessage $addMissing), (Get-ErrorSuggestion $addMissing))
    Check 'D1_add_resource_refusal_names_the_property' ((Get-ErrorMessage $addMissing).Contains('physics_material_override')) `
        ("message='{0}'" -f (Get-ErrorMessage $addMissing))
    Check 'D1_add_resource_refusal_has_suggestion' ((Get-ErrorSuggestion $addMissing).Length -gt 0) `
        ("data.suggestion='{0}'" -f (Get-ErrorSuggestion $addMissing))
    Check 'D1_add_resource_success_shape_has_old_new' (($addMissingCode -eq -32001) -or ($addMissingHasOld -and (Has-Property $addMissingPayload 'new_value'))) `
        ("payload={0}" -f (Get-PayloadText $addMissing))

    $sceneAfterMissing = Get-ConnectionBlock -ScenePath $scenePath
    $missingSub = $sceneAfterMissing.text.Contains('PhysicsMaterial')
    Check 'D1_add_resource_on_missing_property_left_no_effect' (-not $missingSub) `
        ("the .tscn json has no PhysicsMaterial sub-resource: {0}" -f (-not $missingSub))

    # A property that exists but cannot hold this resource: Button.material with a
    # Gradient. The engine's own slot is a CanvasItemMaterial/ShaderMaterial.
    $addWrongType = Invoke-Tool -Id 'A03_add_resource_wrong_category' -Tool 'editor_add_resource_to_node_property' -Arguments @{
        node_path = 'Button'; property = 'material'; resource_type = 'Gradient'
    }
    $addWrongTypeCode = Get-ErrorCode $addWrongType
    Check 'D1_add_resource_wrong_category_refused' ($addWrongTypeCode -ne 0) `
        ("code={0} (want non-zero) message='{1}' suggestion='{2}'" -f $addWrongTypeCode, (Get-ErrorMessage $addWrongType), (Get-ErrorSuggestion $addWrongType))
    $buttonMaterialAfter = Invoke-Tool -Id 'A04_read_button_material' -Tool 'editor_get_node_properties' -Arguments @{
        path = 'Button'; properties = @('material')
    }
    $materialAfterWrongCategory = Get-NodePropertyValue (Get-Payload $buttonMaterialAfter) 'material'
    Check 'D1_wrong_category_left_the_slot_alone' (((Get-ErrorCode $addWrongType) -eq -32602) -and ($null -eq $materialAfterWrongCategory)) `
        ("the refusal is an argument-shape error (want -32602, got {0}); the slot is still empty: material={1}" -f (Get-ErrorCode $addWrongType), (ConvertTo-Json -Compress -InputObject $materialAfterWrongCategory))

    # The positive guard: the same tool on a property that really takes the
    # resource still writes, and the value really lands in the saved scene.
    $addGood = Invoke-Tool -Id 'A05_add_resource_good' -Tool 'editor_add_resource_to_node_property' -Arguments @{
        node_path = 'Button'; property = 'material'; resource_type = 'CanvasItemMaterial'
        resource_properties = @{ light_mode = 2 }
    }
    Check 'D1_add_resource_good_still_ok' ((Get-ErrorCode $addGood) -eq 0) `
        ("code={0} payload={1}" -f (Get-ErrorCode $addGood), (Get-PayloadText $addGood))
    $readGood = Invoke-Tool -Id 'A06_read_button_material_again' -Tool 'editor_get_node_properties' -Arguments @{
        path = 'Button'; properties = @('material')
    }
    $materialImage = Get-NodePropertyValue (Get-Payload $readGood) 'material'
    Check 'D1_good_write_is_readable_back' ($null -ne $materialImage) `
        ("editor_get_node_properties(Button.material) = {0}" -f (ConvertTo-Json -Compress -InputObject $materialImage -Depth 8))

    $saveGood = Invoke-Tool -Id 'A07_save_scene_with_material' -Tool 'editor_save_scene' -Arguments @{}
    Check 'D1_save_scene_ok' ((Get-ErrorCode $saveGood) -eq 0) ("editor_save_scene code={0}" -f (Get-ErrorCode $saveGood))
    $sceneText = [IO.File]::ReadAllText($scenePath, $utf8)
    Check 'D1_good_write_landed_in_the_scene_file' ($sceneText.Contains('CanvasItemMaterial')) `
        ("main.tscn contains a CanvasItemMaterial sub-resource: {0}" -f $sceneText.Contains('CanvasItemMaterial'))

    # -------------------------------------------------------------------------
    #  D-2 -- connect, save, look at the disk
    # -------------------------------------------------------------------------
    $connect = Invoke-Tool -Id 'A08_connect_signal' -Tool 'editor_connect_signal' -Arguments @{
        source_path = 'Button'; signal = 'pressed'; target_path = '.'; method = 'queue_free'
    }
    $connectCode = Get-ErrorCode $connect
    $connectPayload = Get-Payload $connect
    $hasPersisted = Has-Property $connectPayload 'persisted'
    $persistedValue = Get-PropertyValue $connectPayload 'persisted'
    Check 'D2_connect_signal_ok' ($connectCode -eq 0) ("code={0} payload={1}" -f $connectCode, (Get-PayloadText $connect))
    Check 'D2_connect_signal_reports_persisted' ($hasPersisted -and ($persistedValue -eq $true)) `
        ("payload has 'persisted': {0}; value={1}" -f $hasPersisted, $persistedValue)

    $listBefore = Invoke-Tool -Id 'A09_list_connections_before_save' -Tool 'editor_list_signal_connections' -Arguments @{ node_path = 'Button'; signal_name = 'pressed' }
    $listBeforeCount = Get-PropertyValue (Get-Payload $listBefore) 'count'
    Check 'D2_connection_is_live_in_memory' (($listBeforeCount -as [int]) -ge 1) ("count={0}" -f $listBeforeCount)

    $saveAfterConnect = Invoke-Tool -Id 'A10_save_scene_with_connection' -Tool 'editor_save_scene' -Arguments @{}
    Check 'D2_save_scene_ok' ((Get-ErrorCode $saveAfterConnect) -eq 0) ("editor_save_scene code={0}" -f (Get-ErrorCode $saveAfterConnect))
    $blocks = Get-ConnectionBlock -ScenePath $scenePath
    $sceneSha = (Get-FileHash -Algorithm SHA256 -Path $scenePath).Hash.ToLower()
    $sceneBytes = (Get-Item $scenePath).Length
    Note ("main.tscn after save: bytes={0} sha256={1} [connection] count={2}" -f $sceneBytes, $sceneSha, $blocks.count)
    foreach ($line in $blocks.lines) { Note ("  {0}" -f $line) }
    Check 'D2_connection_is_on_disk' ($blocks.count -ge 1 -and ($blocks.lines -join ' ').Contains('pressed')) `
        ("[connection] count={0} lines={1}" -f $blocks.count, ($blocks.lines -join ' | '))

    # -------------------------------------------------------------------------
    #  D-2 restart -- from disk, with no editor memory of the connection
    # -------------------------------------------------------------------------
    Stop-Engine -Handle $editorHandle
    $editorHandle = $null
    Start-Sleep -Seconds 2
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor2'
    Check 'editor2_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor restarted on {0}" -f $EditorPort)

    $openAgain = Invoke-Tool -Id 'B00_open_scene_again' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'B00_open_scene_again_ok' ((Get-ErrorCode $openAgain) -eq 0) ("editor_open_scene code={0}" -f (Get-ErrorCode $openAgain))

    $listAfterRestart = Invoke-Tool -Id 'B01_list_connections_after_restart' -Tool 'editor_list_signal_connections' -Arguments @{ node_path = 'Button'; signal_name = 'pressed' }
    $restartPayload = Get-Payload $listAfterRestart
    $restartCount = Get-PropertyValue $restartPayload 'count'
    $connectionsText = ConvertTo-Json -Compress -InputObject $restartPayload -Depth 12
    Check 'D2_connection_survives_a_restart' (($restartCount -as [int]) -ge 1 -and $connectionsText.Contains('queue_free')) `
        ("count={0} payload={1}" -f $restartCount, (Get-PayloadText $listAfterRestart))

    $analyze = Invoke-Tool -Id 'B02_analyze_signal_flow_after_restart' -Tool 'editor_analyze_signal_flow' -Arguments @{}
    $analyzeText = Get-PayloadText $analyze
    Check 'D2_analyze_signal_flow_sees_the_persistent_connection' ($analyzeText.Contains('queue_free')) `
        ("editor_analyze_signal_flow payload={0}" -f $analyzeText)

    # The persistent connection must be disconnectable again.
    $disconnect = Invoke-Tool -Id 'B03_disconnect_signal' -Tool 'editor_disconnect_signal' -Arguments @{
        source_path = 'Button'; signal = 'pressed'; target_path = '.'; method = 'queue_free'
    }
    $disconnectCode = Get-ErrorCode $disconnect
    Check 'D2_disconnect_of_a_persistent_connection_ok' ($disconnectCode -eq 0) `
        ("code={0} payload={1}" -f $disconnectCode, (Get-PayloadText $disconnect))
    $listAfterDisconnect = Invoke-Tool -Id 'B04_list_connections_after_disconnect' -Tool 'editor_list_signal_connections' -Arguments @{ node_path = 'Button'; signal_name = 'pressed' }
    $afterDisconnectText = Get-PayloadText $listAfterDisconnect
    Check 'D2_disconnect_really_removed_it' (-not $afterDisconnectText.Contains('queue_free')) `
        ("payload={0}" -f $afterDisconnectText)
    $saveAfterDisconnect = Invoke-Tool -Id 'B05_save_scene_after_disconnect' -Tool 'editor_save_scene' -Arguments @{}
    Check 'D2_save_after_disconnect_ok' ((Get-ErrorCode $saveAfterDisconnect) -eq 0) ("code={0}" -f (Get-ErrorCode $saveAfterDisconnect))
    $blocksAfterDisconnect = Get-ConnectionBlock -ScenePath $scenePath
    $sceneShaAfterDisconnect = (Get-FileHash -Algorithm SHA256 -Path $scenePath).Hash.ToLower()
    Note ("main.tscn after disconnect+save: bytes={0} sha256={1} [connection] count={2}" -f (Get-Item $scenePath).Length, $sceneShaAfterDisconnect, $blocksAfterDisconnect.count)
    Check 'D2_disconnected_connection_is_gone_from_disk' ($blocksAfterDisconnect.count -eq 0) `
        ("[connection] count={0}" -f $blocksAfterDisconnect.count)

    # -------------------------------------------------------------------------
    #  D-3 -- the game endpoint
    #
    #  `mcp_port` is deliberately NOT passed: 9889 was occupied when this task ran
    #  (a leftover TASK-039 racing game, `godot.windows.editor.x86_64.mono.exe
    #  --headless --path %TEMP%\mcp-racing-test --mcp-port=9889`, pid recorded
    #  below). That process is never killed here - it is the live downstream the
    #  racing regression is about - so the editor is asked to pick a free port for
    #  its own child and the answer's `mcp_port` is what the game probes use.
    # -------------------------------------------------------------------------
    $racingPid = Get-ListenerPid -Port_ $GamePort
    $script:racingPid = $racingPid
    Note ("port {0} owner before play_scene: {1} (leftover racing game; never killed)" -f $GamePort, $racingPid)

    $play = Invoke-Tool -Id 'C00_play_scene' -Tool 'editor_play_scene' -Arguments @{ mode = 'main' }
    $playCode = Get-ErrorCode $play
    $playPayload = Get-Payload $play
    $gamePortActual = $GamePort
    $reportedPort = Get-PropertyValue $playPayload 'mcp_port'
    if ($null -ne $reportedPort) { $gamePortActual = [int]$reportedPort }
    $script:ownGamePort = $gamePortActual
    Check 'C00_play_scene_ok' (($playCode -eq 0) -and ($null -ne $reportedPort)) `
        ("code={0} payload={1}" -f $playCode, (Get-PayloadText $play))
    Check 'game_endpoint_ready' (Wait-ForPump -Port_ $gamePortActual) ("game on {0} answered GET /mcp with +20 frames" -f $gamePortActual)
    Note ("game probes run against the module's own child on {0}" -f $gamePortActual)

    $gameReadMixed = Invoke-Tool -Id 'C01_game_read_missing_name' -Port_ $gamePortActual -Tool 'running_game_get_node_properties' -Arguments @{
        node_path = '/root/Main/Car'; properties = @('collision_layer', 'physics_material_override')
    }
    $gameReadMixedCode = Get-ErrorCode $gameReadMixed
    Note ("D-3 mixed read: code={0} text={1}" -f $gameReadMixedCode, (Get-PayloadText $gameReadMixed))
    Check 'D3_game_read_of_a_missing_name_refused' ($gameReadMixedCode -eq -32001) `
        ("code={0} (want -32001) message='{1}' suggestion='{2}'" -f $gameReadMixedCode, (Get-ErrorMessage $gameReadMixed), (Get-ErrorSuggestion $gameReadMixed))
    Check 'D3_refusal_names_the_property' ((Get-ErrorMessage $gameReadMixed).Contains('physics_material_override')) `
        ("message='{0}'" -f (Get-ErrorMessage $gameReadMixed))

    $gameReadGood = Invoke-Tool -Id 'C02_game_read_real_property' -Port_ $gamePortActual -Tool 'running_game_get_node_properties' -Arguments @{
        node_path = '/root/Main/Car'; properties = @('collision_layer')
    }
    $gameReadGoodPayload = Get-Payload $gameReadGood
    Check 'D3_game_read_of_a_real_property_still_ok' (((Get-ErrorCode $gameReadGood) -eq 0) -and ((Get-NodePropertyValue $gameReadGoodPayload 'collision_layer') -ne $null)) `
        ("code={0} payload={1}" -f (Get-ErrorCode $gameReadGood), (Get-PayloadText $gameReadGood))

    $gameReadAll = Invoke-Tool -Id 'C03_game_read_all_properties' -Port_ $gamePortActual -Tool 'running_game_get_node_properties' -Arguments @{
        node_path = '/root/Main/Car'
    }
    $allProps = Get-PropertyValue (Get-Payload $gameReadAll) 'properties'
    Check 'D3_unfiltered_read_still_answers_every_property' (((Get-ErrorCode $gameReadAll) -eq 0) -and ($null -ne $allProps)) `
        ("code={0} property_count={1}" -f (Get-ErrorCode $gameReadAll), (($allProps.PSObject.Properties | Measure-Object).Count))

    # Gate 2, the game-side tool's other two classes (success is C02 above).
    $gameMissParam = Invoke-Tool -Id 'E07_game_read_missing_param' -Port_ $gamePortActual -Tool 'running_game_get_node_properties' -Arguments @{}
    Check 'E07_game_read_missing_param_is_-32602' ((Get-ErrorCode $gameMissParam) -eq -32602) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $gameMissParam), (Get-ErrorMessage $gameMissParam))

    $gameMissNode = Invoke-Tool -Id 'E08_game_read_missing_node' -Port_ $gamePortActual -Tool 'running_game_get_node_properties' -Arguments @{ node_path = '/root/NoSuchNode' }
    Check 'E08_game_read_missing_node_is_-32001' ((Get-ErrorCode $gameMissNode) -eq -32001) `
        ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $gameMissNode), (Get-ErrorMessage $gameMissNode), (Get-ErrorSuggestion $gameMissNode))

    $gameSet = Invoke-Tool -Id 'C04_game_set_missing_name' -Port_ $gamePortActual -Tool 'running_game_set_node_property' -Arguments @{
        node_path = '/root/Main/Car'; property = 'physics_material_override'; value = 1.0
    }
    Check 'D3_write_side_still_refuses_the_same_name' ((Get-ErrorCode $gameSet) -eq -32001) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $gameSet), (Get-ErrorMessage $gameSet))

    $gameBatch = Invoke-Tool -Id 'C05_game_read_batch' -Port_ $gamePortActual -Tool 'running_game_get_node_properties_batch' -Arguments @{
        nodes = @(@{ node_path = '/root/Main/Car'; properties = @('collision_layer') }, @{ node_path = '/root/Main/Car'; properties = @('no_such_property_zzq') })
    }
    $batchPayload = Get-Payload $gameBatch
    $batchText = Get-PayloadText $gameBatch
    Note ("D-3 batch: code={0} payload={1}" -f (Get-ErrorCode $gameBatch), $batchText)
    # The batch keeps its per-item granularity: the good item still answers its
    # value, and the bad one answers an `error` entry that names the property
    # instead of a `{"no_such_property_zzq": null}` success image.
    $batchItems = @(Get-PropertyValue $batchPayload 'results')
    $firstItem = $null
    $secondItem = $null
    if ($batchItems.Count -ge 1) { $firstItem = $batchItems[0] }
    if ($batchItems.Count -ge 2) { $secondItem = $batchItems[1] }
    $firstItemOk = ($null -ne $firstItem) -and ((Get-NodePropertyValue $firstItem 'collision_layer') -ne $null)
    $secondItemOk = ($null -ne $secondItem) -and (Has-Property $secondItem 'error') -and (-not (Has-Property $secondItem 'properties')) -and `
        ([string](Get-PropertyValue $secondItem 'error')).Contains('no_such_property_zzq')
    Check 'D3_batch_names_the_missing_property_per_item' (((Get-ErrorCode $gameBatch) -eq 0) -and $firstItemOk -and $secondItemOk) `
        ("code={0} first_ok={1} second_ok={2} payload={3}" -f (Get-ErrorCode $gameBatch), $firstItemOk, $secondItemOk, $batchText)

    # -------------------------------------------------------------------------
    #  Gate 2 - the three evidence classes for every tool this task touched
    #  (editor side: success is A05 above; here the missing-argument and the
    #  underlying-failure classes).
    # -------------------------------------------------------------------------
    $missAdd = Invoke-Tool -Id 'E01_add_resource_missing_param' -Tool 'editor_add_resource_to_node_property' -Arguments @{ node_path = 'Button' }
    Check 'E01_add_resource_missing_param_is_-32602' ((Get-ErrorCode $missAdd) -eq -32602) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $missAdd), (Get-ErrorMessage $missAdd))

    $missConnect = Invoke-Tool -Id 'E02_connect_missing_param' -Tool 'editor_connect_signal' -Arguments @{ source_path = 'Button' }
    Check 'E02_connect_missing_param_is_-32602' ((Get-ErrorCode $missConnect) -eq -32602) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $missConnect), (Get-ErrorMessage $missConnect))

    $missDisconnect = Invoke-Tool -Id 'E03_disconnect_missing_param' -Tool 'editor_disconnect_signal' -Arguments @{ source_path = 'Button'; signal = 'pressed' }
    Check 'E03_disconnect_missing_param_is_-32602' ((Get-ErrorCode $missDisconnect) -eq -32602) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $missDisconnect), (Get-ErrorMessage $missDisconnect))

    $lowAdd = Invoke-Tool -Id 'E04_add_resource_missing_node' -Tool 'editor_add_resource_to_node_property' -Arguments @{
        node_path = 'NoSuchNode'; property = 'material'; resource_type = 'CanvasItemMaterial'
    }
    Check 'E04_add_resource_missing_node_is_-32001' ((Get-ErrorCode $lowAdd) -eq -32001) `
        ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $lowAdd), (Get-ErrorMessage $lowAdd), (Get-ErrorSuggestion $lowAdd))

    $lowConnect = Invoke-Tool -Id 'E05_connect_missing_signal' -Tool 'editor_connect_signal' -Arguments @{
        source_path = 'Button'; signal = 'no_such_signal_zzq'; target_path = '.'; method = 'queue_free'
    }
    Check 'E05_connect_missing_signal_is_-32001' ((Get-ErrorCode $lowConnect) -eq -32001) `
        ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $lowConnect), (Get-ErrorMessage $lowConnect), (Get-ErrorSuggestion $lowConnect))

    $lowDisconnect = Invoke-Tool -Id 'E06_disconnect_missing_connection' -Tool 'editor_disconnect_signal' -Arguments @{
        source_path = 'Button'; signal = 'pressed'; target_path = '.'; method = 'queue_free'
    }
    Check 'E06_disconnect_missing_connection_is_-32001' ((Get-ErrorCode $lowDisconnect) -eq -32001) `
        ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $lowDisconnect), (Get-ErrorMessage $lowDisconnect), (Get-ErrorSuggestion $lowDisconnect))

    $stop = Invoke-Tool -Id 'C06_stop_scene' -Tool 'editor_stop_scene' -Arguments @{}
    Note ("editor_stop_scene code={0}" -f (Get-ErrorCode $stop))
    Start-Sleep -Seconds 2
    Check 'racing_game_on_9889_untouched' ((Get-ListenerPid -Port_ $GamePort) -eq $racingPid) `
        ("port {0} owner after: {1} (before {2})" -f $GamePort, (Get-ListenerPid -Port_ $GamePort), $racingPid)
}
finally {
    Stop-Engine -Handle $editorHandle
    Stop-Engine -Handle $gameHandle
    # Only the game child this run started (its port was picked by the tool, so it
    # can never be 9877, and it is never the leftover racing game's).
    if ($script:ownGamePort -gt 0 -and $script:ownGamePort -ne $UserPort) {
        $ownPid = Get-ListenerPid -Port_ $script:ownGamePort
        if ($ownPid -gt 0 -and $ownPid -ne $script:racingPid) {
            Stop-Process -Id $ownPid -Force -ErrorAction SilentlyContinue
        }
    }
}

$userPidAfter = Get-ListenerPid -Port_ $UserPort
Check 'port_9877_owner_unchanged' ($userPidAfter -eq $userPidBefore) `
    ("port {0} owner before={1} after={2}" -f $UserPort, $userPidBefore, $userPidAfter)

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
Write-Host ("========== label={0} : {1} checks, {2} failed ==========" -f $Label, $script:Checks.Count, $failed.Count)
foreach ($f in $failed) { Write-Host ("FAIL {0}: {1}" -f $f.id, $f.evidence) }
Write-Host ("checks: {0}" -f $checksPath)
Write-Host ("evidence: {0}" -f $Ev)
if ($failed.Count -gt 0) { exit 1 }
exit 0
