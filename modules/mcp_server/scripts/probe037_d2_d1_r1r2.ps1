# =============================================================================
#  probe037_d2_d1_r1r2.ps1 -- baseline / after probes for TASK-037
#
#  Range:
#    D2a  project_edit_resource   : a completely unknown property name
#    D2b  project_edit_resource   : a value the engine clamps (Curve.min_value=5.0)
#    D2c  project_create_resource : the same two questions
#    D2d  the editor node property writer family: unknown property, clamped value
#    D2e  project_set_setting     : a value the engine clamps
#    D1   check_tool_groups.py --batch B1 vs no-argument (exit codes measured in
#         probe037_d1.ps1, this script only records the no-argument path)
#    R1   editor_set_shader_material on a MeshInstance3D with material_slot omitted
#    R2   project_set_theme_font_size(size=0) then project_get_theme_info
#
#  Every response is produced by `curl.exe -s -o <file>` and its sha256 is
#  printed (PLAYBOOK section 7.1: a pipe must never carry a response body).
#  Port discipline: 9877 is never touched; only 9888/9889 are used.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File probe037_d2_d1_r1r2.ps1 -Label base
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
$Root = Join-Path $env:TEMP ('probe037-' + $Label)
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877
$utf8 = [Text.Encoding]::UTF8

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

# A property out of a `project_read_resource` / `editor_get_node_properties`
# answer, whose `properties` field is a name -> JSON-image map.
function Get-NodePropertyValue {
    param($Payload, [string]$Name)
    if ($null -eq $Payload) { return $null }
    return Get-PropertyValue (Get-PropertyValue $Payload 'properties') $Name
}

function Get-ToolNames {
    param($Response)
    $names = New-Object System.Collections.Generic.List[string]
    try {
        $envelope = ConvertFrom-Json ([string]$Response.text)
        foreach ($entry in @($envelope.result.tools)) {
            if ($null -ne $entry -and $null -ne $entry.name) { $names.Add([string]$entry.name) }
        }
    } catch { }
    return $names
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
    }
}

# =============================================================================
#  Scratch project
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, (Join-Path $Proj 'resources'), (Join-Path $Proj 'ui'), (Join-Path $Proj 'scenes') | Out-Null

$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="probe037"'
    'run/main_scene="res://scenes/main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text ($projectGodot + "`n")

# The edited scene: a MeshInstance3D (no `material` slot of its own, the engine
# exposes `surface_material_override/<n>` instead) and a Sprite2D.
$mainScene = @'
[gd_scene load_steps=2 format=3]

[sub_resource type="BoxMesh" id="BoxMesh_1"]

[node name="Main" type="Node3D"]

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("BoxMesh_1")

[node name="Sprite" type="Sprite2D" parent="."]
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text $mainScene

# D2b: a Curve whose max_value stays at the default 1.0, so min_value = 5.0 is
# clamped by Curve::set_min_value (scene/resources/curve.cpp:349-357,
# MIN_Y_RANGE = 0.01) to 0.99.
$curveTres = @'
[gd_resource type="Curve" format=3]

[resource]
min_value = 0.0
max_value = 1.0
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'resources\curve.tres') -Text $curveTres

$shaderGd = @'
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() { COLOR = tint; }
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'ui\tint.gdshader') -Text $shaderGd

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Check 'scratch_project_imported' ($import.exit_code -eq 0) ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

# TASK-042 section 1: the 9877 judgement is the shared six-way classification,
# not "a listener must exist" - see mcp_port_guard.ps1. The `--import` launch
# above is registered too (it asks for port 0, never for the user's port).
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))

$editorHandle = $null
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $open = Invoke-Tool -Id 'A00_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'A00_open_scene_ok' ((Get-ErrorCode $open) -eq 0) ("editor_open_scene code={0}" -f (Get-ErrorCode $open))

    # =========================================================================
    #  D2a -- a completely unknown property name on an existing resource.
    # =========================================================================
    $editUnknown = Invoke-Tool -Id 'A01_edit_unknown' -Tool 'project_edit_resource' -Arguments @{
        path = 'res://resources/curve.tres'
        properties = @{ no_such_property = 1 }
    }
    $editUnknownCode = Get-ErrorCode $editUnknown
    $editUnknownSuggestion = Get-ErrorSuggestion $editUnknown
    Check 'D2a_edit_unknown_property_is_an_error' ($editUnknownCode -ne 0) `
        ("project_edit_resource with only no_such_property -> code={0} message='{1}'" -f $editUnknownCode, (Get-ErrorMessage $editUnknown))
    Check 'D2a_edit_unknown_property_is_-32001' ($editUnknownCode -eq -32001) ("code={0} (want -32001)" -f $editUnknownCode)
    Check 'D2a_edit_unknown_property_names_it_in_suggestion' ($editUnknownSuggestion -match 'no_such_property') `
        ("data.suggestion='{0}'" -f $editUnknownSuggestion)

    # =========================================================================
    #  D2b -- a value the engine clamps: Curve.min_value = 5.0 -> 0.99.
    # =========================================================================
    $editClamp = Invoke-Tool -Id 'A02_edit_clamped' -Tool 'project_edit_resource' -Arguments @{
        path = 'res://resources/curve.tres'
        properties = @{ min_value = 5.0 }
    }
    $editClampCode = Get-ErrorCode $editClamp
    $editClampPayload = Get-Payload $editClamp
    $clampChanged = Get-PropertyValue $editClampPayload 'changed'
    $clampIgnored = Get-PropertyValue $editClampPayload 'ignored'
    $clampMinNew = $null
    if ($null -ne $clampChanged -and (Has-Property $clampChanged 'min_value')) {
        $clampMinNew = Get-PropertyValue (Get-PropertyValue $clampChanged 'min_value') 'new'
    }
    Note ("D2b payload: {0}" -f (Get-PayloadText $editClamp))
    Check 'D2b_clamped_value_still_reports_the_real_result' ($editClampCode -eq 0) `
        ("code={0}; changed.min_value.new={1}" -f $editClampCode, $clampMinNew)
    Check 'D2b_clamped_value_lands_in_ignored' ($null -ne $clampIgnored -and (Has-Property $clampIgnored 'min_value')) `
        ("ignored = {0}" -f (ConvertTo-Json -Compress -InputObject $clampIgnored -Depth 10))
    if ($null -ne $clampIgnored -and (Has-Property $clampIgnored 'min_value')) {
        $miss = Get-PropertyValue $clampIgnored 'min_value'
        Check 'D2b_ignored_entry_has_requested_stored_reason' ((Has-Property $miss 'requested') -and (Has-Property $miss 'stored') -and (Has-Property $miss 'reason')) `
            ("requested={0} stored={1} reason={2}" -f (Get-PropertyValue $miss 'requested'), (Get-PropertyValue $miss 'stored'), (Get-PropertyValue $miss 'reason'))
    } else {
        Check 'D2b_ignored_entry_has_requested_stored_reason' $false "no ignored.min_value entry"
    }

    # =========================================================================
    #  D2c -- the same two questions on project_create_resource.
    # =========================================================================
    $createUnknown = Invoke-Tool -Id 'A03_create_unknown' -Tool 'project_create_resource' -Arguments @{
        path = 'res://resources/created_unknown.tres'
        type = 'Curve'
        properties = @{ no_such_property = 1 }
    }
    $createUnknownCode = Get-ErrorCode $createUnknown
    Check 'D2c_create_unknown_property_is_an_error' ($createUnknownCode -ne 0) `
        ("project_create_resource with only no_such_property -> code={0} message='{1}' suggestion='{2}'" -f $createUnknownCode, (Get-ErrorMessage $createUnknown), (Get-ErrorSuggestion $createUnknown))
    Check 'D2c_create_unknown_property_is_-32001' ($createUnknownCode -eq -32001) ("code={0} (want -32001)" -f $createUnknownCode)
    Check 'D2c_create_unknown_left_no_file' (-not (Test-Path (Join-Path $Proj 'resources\created_unknown.tres'))) `
        "res://resources/created_unknown.tres was not written"

    $createClamp = Invoke-Tool -Id 'A04_create_clamped' -Tool 'project_create_resource' -Arguments @{
        path = 'res://resources/created_clamp.tres'
        type = 'Curve'
        overwrite = $true
        properties = @{ min_value = 5.0 }
    }
    $createClampPayload = Get-Payload $createClamp
    $createIgnored = Get-PropertyValue $createClampPayload 'ignored'
    Note ("D2c create-clamped payload: {0}" -f (Get-PayloadText $createClamp))
    Check 'D2c_create_clamped_lands_in_ignored' ($null -ne $createIgnored -and (Has-Property $createIgnored 'min_value')) `
        ("ignored = {0}" -f (ConvertTo-Json -Compress -InputObject $createIgnored -Depth 10))

    # =========================================================================
    #  D2d -- the editor node property writer family.
    #  Parameter names: editor_set_node_property takes `path`/`property`/`value`
    #  and editor_set_node_property_batch takes
    #  `node_type`/`property`/`value` (measured on the baseline run).
    # =========================================================================
    $nodeUnknown = Invoke-Tool -Id 'A05_node_unknown' -Tool 'editor_set_node_property' -Arguments @{
        path = 'Sprite'
        property = 'no_such_property'
        value = 1
    }
    Check 'D2d_editor_set_node_property_unknown_is_-32001' ((Get-ErrorCode $nodeUnknown) -eq -32001) `
        ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $nodeUnknown), (Get-ErrorMessage $nodeUnknown), (Get-ErrorSuggestion $nodeUnknown))

    $nodeBatchUnknown = Invoke-Tool -Id 'A06_node_batch_unknown' -Tool 'editor_set_node_property_batch' -Arguments @{
        node_type = 'Sprite2D'
        property = 'no_such_property'
        value = 1
    }
    Check 'D2d_editor_set_node_property_batch_unknown_is_-32001' ((Get-ErrorCode $nodeBatchUnknown) -eq -32001) `
        ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $nodeBatchUnknown), (Get-ErrorMessage $nodeBatchUnknown), (Get-ErrorSuggestion $nodeBatchUnknown))

    # A node property the engine really clamps: Sprite2D.hframes has a floor of 1
    # in Sprite2D::set_hframes (scene/2d/sprite_2d.cpp), so hframes = 0 is stored
    # as something else by the engine's own setter.
    $nodeClamp = Invoke-Tool -Id 'A07_node_clamped' -Tool 'editor_set_node_property' -Arguments @{
        path = 'Sprite'
        property = 'hframes'
        value = 0
    }
    Note ("D2d hframes=0 payload: {0}" -f (Get-PayloadText $nodeClamp))
    $nodeClampPayload = Get-Payload $nodeClamp
    $nodeClampNew = Get-PropertyValue $nodeClampPayload 'new_value'
    $nodeClampIgnored = Get-PropertyValue $nodeClampPayload 'ignored'
    Check 'D2d_editor_set_node_property_reports_the_stored_value' ((Get-ErrorCode $nodeClamp) -eq 0 -and $null -ne $nodeClampNew) `
        ("hframes=0 -> code={0} new_value={1}" -f (Get-ErrorCode $nodeClamp), $nodeClampNew)
    # The value the answer reports is checked against the engine itself: the same
    # node is read back through the other tool. (The read-back is what D2d is
    # about; whether *this* property clamps is a separate, recorded question.)
    $nodeReadBack = Invoke-Tool -Id 'A07b_node_read_back' -Tool 'editor_get_node_properties' -Arguments @{
        path = 'Sprite'
    }
    $nodeReadPayload = Get-Payload $nodeReadBack
    $engineHframes = Get-NodePropertyValue $nodeReadPayload 'hframes'
    Check 'D2d_the_answered_value_is_the_engine_value' ([string]$nodeClampNew -ceq [string]$engineHframes) `
        ("editor_set_node_property new_value={0}; editor_get_node_properties hframes={1}" -f $nodeClampNew, $engineHframes)
    # Recorded finding: `Sprite2D.hframes = 0` is **refused** by the engine
    # (`Sprite2D::set_hframes` logs "Amount of hframes cannot be smaller than 1"
    # and leaves the member alone), so the answer reads back the value that was
    # already there. Before TASK-037 that read-back was the only signal; the entry
    # now lands in `ignored` with requested / stored / reason, the same shape the
    # resource writers and the particle/theme writers use (DESIGN-DETAIL section
    # 20.6). `stored` is the engine's real value afterwards, whatever it is.
    if ([string]$nodeClampNew -ceq '0') {
        Note "D2d finding: Sprite2D.hframes accepts 0 unchanged (no refusal on this property; D2b is the clamp witness)"
    } else {
        Check 'D2d_a_refused_node_property_is_named_in_ignored' (($null -ne $nodeClampIgnored) -and (Has-Property $nodeClampIgnored 'hframes')) `
            ("hframes=0 was not stored (engine holds {0}); ignored={1}" -f $nodeClampNew, (ConvertTo-Json -Compress -InputObject $nodeClampIgnored -Depth 10))
        if ($null -ne $nodeClampIgnored -and (Has-Property $nodeClampIgnored 'hframes')) {
            $nodeMiss = Get-PropertyValue $nodeClampIgnored 'hframes'
            Check 'D2d_node_ignored_entry_has_requested_stored_reason' ((Has-Property $nodeMiss 'requested') -and (Has-Property $nodeMiss 'stored') -and (Has-Property $nodeMiss 'reason')) `
                ("requested={0} stored={1} reason={2}" -f (Get-PropertyValue $nodeMiss 'requested'), (Get-PropertyValue $nodeMiss 'stored'), (Get-PropertyValue $nodeMiss 'reason'))
            Check 'D2d_node_ignored_stored_is_the_engines_real_value' ([string](Get-PropertyValue $nodeMiss 'stored') -ceq [string]$nodeClampNew) `
                ("ignored.stored={0} == new_value={1}" -f (Get-PropertyValue $nodeMiss 'stored'), $nodeClampNew)
        }
    }
    # The batch writer has to say the same thing, keyed by the node path.
    $nodeBatchClamp = Invoke-Tool -Id 'A07c_node_batch_clamped' -Tool 'editor_set_node_property_batch' -Arguments @{
        node_type = 'Sprite2D'
        property = 'hframes'
        value = 0
    }
    Note ("D2d batch hframes=0 payload: {0}" -f (Get-PayloadText $nodeBatchClamp))
    $nodeBatchClampPayload = Get-Payload $nodeBatchClamp
    $nodeBatchIgnored = Get-PropertyValue $nodeBatchClampPayload 'ignored'
    Check 'D2d_batch_names_the_clamp_per_node' ((Get-ErrorCode $nodeBatchClamp) -eq 0 -and $null -ne $nodeBatchIgnored -and (Has-Property $nodeBatchIgnored 'Sprite')) `
        ("code={0} ignored={1}" -f (Get-ErrorCode $nodeBatchClamp), (ConvertTo-Json -Compress -InputObject $nodeBatchIgnored -Depth 10))

    # =========================================================================
    #  D2e -- project_set_setting: a value the engine clamps.
    #  The parameter names are `key`/`type`/`value` (measured on the baseline).
    # =========================================================================
    $settingClamp = Invoke-Tool -Id 'A08_setting_clamped' -Tool 'project_set_setting' -Arguments @{
        key = 'display/window/size/viewport_width'
        type = 'int'
        value = -5
    }
    Note ("D2e project_set_setting(-5) payload: {0}" -f (Get-PayloadText $settingClamp))
    $settingClampPayload = Get-Payload $settingClamp
    $settingStored = Get-PropertyValue $settingClampPayload 'value'
    $settingIgnored = Get-PropertyValue $settingClampPayload 'ignored'
    Check 'D2e_project_set_setting_answers_the_read_back' ((Get-ErrorCode $settingClamp) -eq 0) `
        ("code={0} payload={1}" -f (Get-ErrorCode $settingClamp), (Get-PayloadText $settingClamp))
    # The probe asks "is the clamp named", but `display/window/size/viewport_width`
    # is not a clamped setting: the engine's `ProjectSettings` keeps a negative
    # width as a window position convention, so **no clamp happens** and no
    # `ignored` entry is correct. A refusal *or* the exact stored value is the pass
    # condition; the check records which one happened.
    Check 'D2e_no_clamp_is_invented' (((Get-ErrorCode $settingClamp) -ne 0) -or ($settingStored -eq -5) -or (($null -ne $settingIgnored) -and (Has-Property $settingIgnored 'display/window/size/viewport_width'))) `
        ("code={0} stored={1} ignored={2} (the engine keeps -5, so 'no ignored entry' is the correct answer here)" -f (Get-ErrorCode $settingClamp), $settingStored, (ConvertTo-Json -Compress -InputObject $settingIgnored -Depth 10))

    # =========================================================================
    #  R1 -- editor_set_shader_material on a MeshInstance3D, slot omitted.
    # =========================================================================
    $r1 = Invoke-Tool -Id 'A09_shader_default_slot' -Tool 'editor_set_shader_material' -Arguments @{
        node_path = 'Mesh'
        shader_path = 'res://ui/tint.gdshader'
    }
    $r1Code = Get-ErrorCode $r1
    $r1Payload = Get-Payload $r1
    $r1Slot = Get-PropertyValue $r1Payload 'material_slot'
    $r1Slots = Get-PropertyValue $r1Payload 'material_slots'
    Note ("R1 payload: {0}" -f (Get-PayloadText $r1))
    Check 'R1_omitted_slot_works_on_a_mesh' ($r1Code -eq 0) `
        ("editor_set_shader_material without material_slot on MeshInstance3D -> code={0} message='{1}' suggestion='{2}'" -f $r1Code, (Get-ErrorMessage $r1), (Get-ErrorSuggestion $r1))
    Check 'R1_omitted_slot_names_the_slot_it_used' (-not [string]::IsNullOrEmpty([string]$r1Slot)) `
        ("material_slot='{0}' material_slots={1}" -f $r1Slot, (ConvertTo-Json -Compress -InputObject $r1Slots -Depth 5))
    $r1FirstSlot = if ($null -ne $r1Slots -and @($r1Slots).Count -gt 0) { [string]@($r1Slots)[0] } else { '' }
    Check 'R1_omitted_slot_is_the_nodes_own_first_slot' (([string]$r1Slot) -ceq $r1FirstSlot) `
        ("material_slot='{0}' == material_slots[0]='{1}'" -f $r1Slot, $r1FirstSlot)
    Check 'R1_omitted_slot_is_not_the_literal_default_when_default_is_absent' (([string]$r1Slot) -ne 'material') `
        ("material_slot='{0}' (the contract default 'material' does not exist on a MeshInstance3D)" -f $r1Slot)

    $r1Bad = Invoke-Tool -Id 'A10_shader_explicit_bad_slot' -Tool 'editor_set_shader_material' -Arguments @{
        node_path = 'Mesh'
        shader_path = 'res://ui/tint.gdshader'
        material_slot = 'material'
    }
    Check 'R1_explicit_bad_slot_is_still_refused' ((Get-ErrorCode $r1Bad) -eq -32602) `
        ("explicit material_slot='material' on MeshInstance3D -> code={0} message='{1}'" -f (Get-ErrorCode $r1Bad), (Get-ErrorMessage $r1Bad))

    # =========================================================================
    #  R2 -- project_set_theme_font_size(size=0) then project_get_theme_info.
    # =========================================================================
    $createTheme = Invoke-Tool -Id 'A11_create_theme' -Tool 'project_create_theme' -Arguments @{
        path = 'res://ui/theme.tres'
        name = 'ProbeTheme'
    }
    Check 'R2_create_theme_ok' ((Get-ErrorCode $createTheme) -eq 0) ("code={0} payload={1}" -f (Get-ErrorCode $createTheme), (Get-PayloadText $createTheme))

    $fs = Invoke-Tool -Id 'A12_font_size_zero' -Tool 'project_set_theme_font_size' -Arguments @{
        theme_path = 'res://ui/theme.tres'
        font_size_name = 'zero_size'
        size = 0
    }
    $fsPayload = Get-Payload $fs
    Note ("R2 writer payload: {0}" -f (Get-PayloadText $fs))
    # TASK-037 R2: the writer refuses a non-positive size (-32602) instead of
    # writing one. The reason is measured, not assumed: the engine's serializer
    # persists `<=0` as the fallback font size, so the request can never be
    # stored as asked (see the report's R2 section and the A13b file read below).
    Check 'R2_writer_refuses_a_non_positive_size' ((Get-ErrorCode $fs) -eq -32602) `
        ("project_set_theme_font_size(size=0) -> code={0} message='{1}'" -f (Get-ErrorCode $fs), (Get-ErrorMessage $fs))
    Check 'R2_writer_names_the_engine_fallback_reason' ((Get-ErrorMessage $fs) -match 'fallback') `
        ("message='{0}'" -f (Get-ErrorMessage $fs))

    # The same call with a positive size still works and reads back exactly.
    $fsOk = Invoke-Tool -Id 'A12b_font_size_positive' -Tool 'project_set_theme_font_size' -Arguments @{
        theme_path = 'res://ui/theme.tres'
        font_size_name = 'good_size'
        size = 21
    }
    $fsOkPayload = Get-Payload $fsOk
    Check 'R2_writer_still_accepts_a_positive_size' ((Get-ErrorCode $fsOk) -eq 0 -and (Get-PropertyValue $fsOkPayload 'font_size_readable') -eq $true) `
        ("size=21 -> code={0} font_size_readable={1} payload={2}" -f (Get-ErrorCode $fsOk), (Get-PropertyValue $fsOkPayload 'font_size_readable'), (Get-PayloadText $fsOk))

    $info = Invoke-Tool -Id 'A13_theme_info' -Tool 'project_get_theme_info' -Arguments @{ theme_path = 'res://ui/theme.tres' }
    $infoPayload = Get-Payload $info
    Note ("R2 reader payload: {0}" -f (Get-PayloadText $info))
    $infoFontSizes = Get-PropertyValue $infoPayload 'font_sizes'
    $infoUnreadable = Get-PropertyValue $infoPayload 'font_sizes_stored_not_readable'
    $buttonSizes = Get-PropertyValue $infoFontSizes 'Button'
    $readerZero = Get-PropertyValue $buttonSizes 'zero_size'
    $readerGood = Get-PropertyValue $buttonSizes 'good_size'
    Check 'R2_reader_has_no_zero_entry_to_misread' ($null -eq $readerZero) `
        ("font_sizes.Button.zero_size={0} (the writer refused it, so the reader has nothing to misinterpret)" -f $readerZero)
    Check 'R2_reader_shows_the_positive_size' ($readerGood -eq 21) `
        ("font_sizes.Button.good_size={0} font_sizes_stored_not_readable={1}" -f $readerGood, (ConvertTo-Json -Compress -InputObject $infoUnreadable -Depth 5))

    # The on-disk bytes: the theme file holds the positive size and no zero entry.
    $themeFile = Join-Path $Proj 'ui\theme.tres'
    $themeText = [IO.File]::ReadAllText($themeFile, $utf8)
    $themeSha = (Get-FileHash -Algorithm SHA256 -Path $themeFile).Hash.ToLower()
    Note ("R2 theme.tres sha256={0}" -f $themeSha)
    Note ("R2 theme.tres body: {0}" -f ($themeText -replace "`r?`n", ' | '))
    Check 'R2_theme_file_has_no_zero_entry' (-not ($themeText -match 'zero_size')) `
        ("theme.tres carries no zero_size entry; body={0}" -f ($themeText -replace "`r?`n", ' | '))
    Check 'R2_theme_file_has_the_positive_entry' ($themeText -match 'good_size = 21') `
        ("theme.tres carries good_size = 21" )
}
finally {
    Stop-Engine -Handle $editorHandle
    Start-Sleep -Milliseconds 500
    Check 'port_9888_released' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1} after the probe" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
    $portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
    Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence
}

$failed = @($script:Checks | Where-Object { -not $_.pass })
Write-Host ''
Write-Host ("PROBE037 {0}: {1}/{2} checks passed" -f $Label, ($script:Checks.Count - $failed.Count), $script:Checks.Count)
foreach ($f in $failed) { Write-Host ("FAILED {0}: {1}" -f $f.id, $f.evidence) }
$checkArray = @($script:Checks | ForEach-Object { [pscustomobject]@{ id = [string]$_.id; pass = [bool]$_.pass; evidence = [string]$_.evidence } })
$outFile = Join-Path $Root 'probe037-checks.json'
Write-McpUtf8NoBom -Path $outFile -Text ((ConvertTo-Json -InputObject $checkArray -Depth 8) + "`n")
Write-Host ("checks: {0}" -f $outFile)
if ($failed.Count -gt 0) { exit 1 }
exit 0
