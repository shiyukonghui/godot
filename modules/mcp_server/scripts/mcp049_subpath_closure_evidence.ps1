# =============================================================================
#  mcp049_subpath_closure_evidence.ps1 -- TASK-049 evidence
#
#  The defect (mcp027 `D8_whole_resource_bag_round_trips`): the *read* side
#  answers property names the *write* side refused with
#
#    -32602 "Property name 'glow_levels/1' is not a settable property name"
#
#  `glow_levels/1` is the engine's own spelling (`Environment` registers seven
#  of them with `ADD_PROPERTYI`, `scene/resources/environment.cpp:1464-1470`),
#  and `Object::set()` reaches its setter through the object's own property
#  table (`Object::set_native`, `core/object/object.cpp:349-393`). The module's
#  own extra identifier gate was the defect (GDR-25 section 23.4).
#
#  What this script measures, on the live endpoints (9888 editor / 9889 game):
#
#    A. the shape the read side really answers (the key list, with the
#       `/`-shaped names in it) and the minimal single-key reproduction;
#    B. the three-layer equivalence of section 23.4 for the whole bag the reader
#       answered: (1) the write takes it as it is, (2) `changed` reports the
#       read-back value and no key is `ignored`, (3) a second read answers the
#       same bag - key by key, not as one summary;
#    C. the file truth: a fresh *game* process (9889, no editor-side resource
#       cache) reads the same `.tres` and answers the written value, and the
#       saved file itself spells the sub-path name;
#    D. the same family on the other two read/write pairs that can produce it:
#       a node property name (`HingeJoint3D.angular_limit/upper` through
#       `editor_get_node_properties` / `editor_set_node_property`) and a
#       `ProjectSettings` key (`application/config/name` through
#       `project_get_settings` / `project_set_setting`);
#    E. the refusals that must NOT have been weakened: a name that is neither an
#       identifier nor an engine property name stays -32602, an unknown
#       identifier stays -32001, and an empty name stays -32602;
#    F. the engine-wide census of `get_property_list()` names that are not valid
#       ASCII identifiers (via `editor_execute_gdscript` + `ClassDB`), split into
#       real properties and inspector labels, with the shape breakdown.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp049_subpath_closure_evidence.ps1
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
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'task049-subpath-closure' }
$Root = $OutRoot
$Ev = Join-Path $Root 'evidence'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
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
    param([string]$Tool, $Arguments)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 40 -Compress)
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 0)
    if ($Port_ -eq 0) { $Port_ = $EditorPort }
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-McpUtf8NoBom -Path $bodyFile -Text (New-CallBody -Tool $Tool -Arguments $Arguments)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time 180 -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $script:LastSha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] bytes={1} sha256={2}" -f $Id, $bytes.Length, $script:LastSha)
    Write-Host ("       {0}" -f $text)
    return $text
}

function Get-Payload {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.result) { return $null }
        return ConvertFrom-Json ([string]$envelope.result.content[0].text)
    } catch { return $null }
}

function Get-ErrorCode {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return 0 }
        return [int]$envelope.error.code
    } catch { return 0 }
}

function Get-ErrorMessage {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return '' }
        return [string]$envelope.error.message
    } catch { return '' }
}

function Get-ErrorSuggestion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return '' }
        return [string]$envelope.error.data.suggestion
    } catch { return '' }
}

# A structural spelling of a JSON value with the keys sorted, so "the value I
# read is the value I wrote" compares values, not key order.
function Get-Canonical {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $names = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $parts = @()
        foreach ($n in $names) { $parts += ('"' + $n + '":' + (Get-Canonical $Value.$n)) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $parts = @()
        foreach ($item in $Value) { $parts += (Get-Canonical $item) }
        return '[' + ($parts -join ',') + ']'
    }
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
        return ([Convert]::ToDouble($Value)).ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    }
    return ([string]$Value)
}

function Get-KeyList {
    param($Bag)
    if ($null -eq $Bag) { return @() }
    return @($Bag.PSObject.Properties | ForEach-Object { $_.Name })
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $proc = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $Root ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $Root ($LogName + '.err.log')) -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $proc.Id -Arguments $Arguments
    return $proc
}

function Wait-ForPump {
    param([int]$Port_, [int]$TimeoutMs = 300000)
    $frames = $null
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 1000
        $statusFile = Join-Path $Ev ("status-$Port_.json")
        & $Curl -s --max-time 5 -o $statusFile ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (Test-Path $statusFile) {
            $bytes = [IO.File]::ReadAllBytes($statusFile)
            if ($bytes.Length -gt 0) {
                try {
                    $probe = ConvertFrom-Json ([Text.Encoding]::UTF8.GetString($bytes))
                    if ($null -ne $frames -and ([int]$probe.frame_count - $frames) -ge 20) { return $true }
                    $frames = [int]$probe.frame_count
                } catch { }
            }
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

# level 1 of section 23.4: write the bag exactly as the reader answered it.
function Invoke-BagWrite {
    param([string]$Id, [string]$Tool, [string]$Path, $Bag)
    return (Invoke-Tool -Id $Id -Tool $Tool -Arguments @{ path = $Path; properties = $Bag })
}

# =============================================================================
# Scratch project
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $Proj, (Join-Path $Proj 'scenes'), (Join-Path $Proj 'shaders') | Out-Null

New-McpScratchProject -Path $Proj -Name 'task049_subpath_closure' -WithMainScene $false
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text @'
config_version=5

[application]
config/name="task049_subpath_closure"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.8")

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@

# A node whose property table holds `/`-shaped names (the engine's own spelling:
# `HingeJoint3D` registers `angular_limit/upper` and `params/bias`).
$scene = @(
    '[gd_scene format=3]'
    ''
    '[node name="Main" type="Node3D"]'
    ''
    '[node name="Joint" type="HingeJoint3D" parent="."]'
) -join "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text ($scene + "`n")

Write-McpUtf8NoBom -Path (Join-Path $Proj 'environment.tres') -Text ("[gd_resource type=`"Environment`" format=3]`n`n[resource]`n")
Write-McpUtf8NoBom -Path (Join-Path $Proj 'shaders\probe.gdshader') -Text ("shader_type canvas_item;`n`nuniform vec3 albedo = vec3(1.0);`nuniform float uv1_scale = 1.0;`n")
Write-McpUtf8NoBom -Path (Join-Path $Proj 'shader_material.tres') -Text ("[gd_resource type=`"ShaderMaterial`" load_steps=2 format=3]`n`n[ext_resource type=`"Shader`" path=`"res://shaders/probe.gdshader`" id=`"1_sh`"]`n`n[resource]`nshader = ExtResource(`"1_sh`")`nshader_parameter/albedo = Vector3(1, 0, 0)`nshader_parameter/uv1_scale = 2.5`n")
# The same material with both uniforms left unset: the *value* half of the same
# pair has its own boundary (finding F-1): the engine falls back to
# `RenderingServer::shader_get_parameter_default()` (material.cpp:342-347), which
# a headless process answers as `null`, and `null` is refused for a non-Object
# property instead of being written as the type's default.
Write-McpUtf8NoBom -Path (Join-Path $Proj 'shader_material_unset.tres') -Text ("[gd_resource type=`"ShaderMaterial`" load_steps=2 format=3]`n`n[ext_resource type=`"Shader`" path=`"res://shaders/probe.gdshader`" id=`"1_sh`"]`n`n[resource]`nshader = ExtResource(`"1_sh`")`n")

$userPidBefore = Get-ListenerPid -Port_ $UserPort
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("user editor on {0} before: pid={1} (never touched; judged by the shared guard)" -f $UserPort, $userPidBefore)
Check 'port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'port_9889_free' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

$import1 = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $Root -Name 'import1' -NoPort
$import2 = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $Root -Name 'import2' -NoPort
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import1.command
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import2.command
Check 'scratch_project_import_second_run' ($import2.exit_code -eq 0) `
    ("first --import exit={0} after {1} attempt(s); second --import exit={2} after {3} attempt(s)" -f `
            $import1.exit_code, $import1.attempts, $import2.exit_code, $import2.attempts)

$editorHandle = $null
$gameHandle = $null

try {
    # =========================================================================
    # A. the shape the read side answers, and the minimal reproduction
    # =========================================================================
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $envReadText = Invoke-Tool -Id 'A1_read_environment' -Tool 'project_read_resource' -Arguments @{ path = 'res://environment.tres' }
    $envRead = Get-Payload $envReadText
    $envBag = $envRead.properties
    $envKeys = Get-KeyList -Bag $envBag
    $envSlashKeys = @($envKeys | Where-Object { $_.Contains('/') })
    $envSlashKeysSorted = @($envSlashKeys | Sort-Object)
    $expectedGlow = @(1..7 | ForEach-Object { "glow_levels/$_" })
    Check 'A_read_side_answers_sub_path_names' `
        (($envSlashKeysSorted -join ',') -eq (($expectedGlow | Sort-Object) -join ',')) `
        ("the reader answered {0} keys ({1} stored total, truncated={2} dropped={3}); the '/' names are: {4}" -f `
                $envKeys.Count, $envRead.total_properties, $envRead.truncated, $envRead.dropped, ($envSlashKeysSorted -join ', '))
    Check 'A_read_side_does_not_roll_the_sub_paths_up' (-not ($envKeys -contains 'glow_levels')) `
        ("'glow_levels' is not a key of the answer: {0}" -f (-not ($envKeys -contains 'glow_levels')))

    $singleText = Invoke-Tool -Id 'A2_write_one_sub_path' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://environment.tres'; properties = @{ 'glow_levels/1' = 1.5 } }
    $singleCode = Get-ErrorCode $singleText
    $singlePayload = Get-Payload $singleText
    $singleStored = $null
    if ($null -ne $singlePayload) { $singleStored = $singlePayload.changed.'glow_levels/1'.new }
    Check 'A_minimal_repro_is_taken' (($singleCode -eq 0) -and ($null -ne $singleStored) -and ([double]$singleStored -eq 1.5)) `
        ("code={0} changed['glow_levels/1'].new={1} message='{2}'" -f $singleCode, (Get-Canonical $singleStored), (Get-ErrorMessage $singleText))

    $envReadOneText = Invoke-Tool -Id 'A3_read_one_sub_path' -Tool 'project_read_resource' -Arguments @{ path = 'res://environment.tres' }
    $envReadOne = Get-Payload $envReadOneText
    Check 'A_write_read_back_is_1_5' ([double]$envReadOne.properties.'glow_levels/1' -eq 1.5) `
        ("properties['glow_levels/1'] = {0}" -f $envReadOne.properties.'glow_levels/1')

    # =========================================================================
    # B. the three-layer equivalence for the whole bag the reader answered
    # =========================================================================
    $envBagText = Invoke-BagWrite -Id 'B1_write_whole_bag_as_read' -Tool 'project_edit_resource' -Path 'res://environment.tres' -Bag $envBag
    $envBagCode = Get-ErrorCode $envBagText
    $envBagPayload = Get-Payload $envBagText
    Check 'B1_whole_bag_is_taken_as_read' ($envBagCode -eq 0) `
        ("code={0} message='{1}' (bag keys: {2})" -f $envBagCode, (Get-ErrorMessage $envBagText), $envKeys.Count)

    $level2Mismatch = @()
    $ignoredKeys = @()
    if ($null -ne $envBagPayload) {
        foreach ($key in $envKeys) {
            $entry = $envBagPayload.changed.$key
            if ($null -eq $entry) { $level2Mismatch += ($key + '=missing'); continue }
            if ((Get-Canonical $entry.new) -cne (Get-Canonical $envBag.$key)) { $level2Mismatch += ($key + '=' + (Get-Canonical $entry.new)) }
        }
        $ignoredKeys = Get-KeyList -Bag $envBagPayload.ignored
    } else {
        $level2Mismatch += 'no payload'
    }
    Check 'B2_level2_changed_is_the_read_back_truth' ($level2Mismatch.Count -eq 0) `
        ("keys whose changed[].new is not the value that was read: {0}" -f (($level2Mismatch -join '; ') + $(if ($level2Mismatch.Count -eq 0) { '<none>' } else { '' })))
    Check 'B2_no_key_was_ignored' ($ignoredKeys.Count -eq 0) `
        ("ignored keys: {0}" -f (($ignoredKeys -join ', ') + $(if ($ignoredKeys.Count -eq 0) { '<none>' } else { '' })))
    Check 'B2_sub_path_keys_are_reported_as_set' `
        ((@($envBagPayload.properties_set) -contains 'glow_levels/1') -and (@($envBagPayload.properties_set) -contains 'glow_levels/7')) `
        ("properties_set contains: {0}" -f ((@($envBagPayload.properties_set) | Where-Object { $_.Contains('/') }) -join ', '))

    $envAgainText = Invoke-Tool -Id 'B3_reread_whole_bag' -Tool 'project_read_resource' -Arguments @{ path = 'res://environment.tres' }
    $envAgain = Get-Payload $envAgainText
    $level3Mismatch = @()
    foreach ($key in $envKeys) {
        if ((Get-Canonical $envAgain.properties.$key) -cne (Get-Canonical $envBag.$key)) {
            $level3Mismatch += ($key + ': ' + (Get-Canonical $envBag.$key) + ' -> ' + (Get-Canonical $envAgain.properties.$key))
        }
    }
    Check 'B3_level3_reread_equals_what_was_read' ($level3Mismatch.Count -eq 0) `
        ("keys whose re-read differs from the first read (of {0}): {1}" -f $envKeys.Count, (($level3Mismatch -join '; ') + $(if ($level3Mismatch.Count -eq 0) { '<none>' } else { '' })))

    $shaderReadText = Invoke-Tool -Id 'B4_read_shader_material' -Tool 'project_read_resource' -Arguments @{ path = 'res://shader_material.tres' }
    $shaderRead = Get-Payload $shaderReadText
    $shaderBag = $shaderRead.properties
    $shaderKeys = Get-KeyList -Bag $shaderBag
    $shaderSlash = @($shaderKeys | Where-Object { $_.Contains('/') } | Sort-Object)
    Check 'B4_read_side_answers_shader_parameter_names' (($shaderSlash -join ',') -eq 'shader_parameter/albedo,shader_parameter/uv1_scale') `
        ("ShaderMaterial keys: {0}" -f ($shaderKeys -join ', '))

    $shaderWriteText = Invoke-BagWrite -Id 'B5_write_shader_bag_as_read' -Tool 'project_edit_resource' -Path 'res://shader_material.tres' -Bag $shaderBag
    $shaderWritePayload = Get-Payload $shaderWriteText
    $shaderMismatch = @()
    if ($null -ne $shaderWritePayload) {
        foreach ($key in $shaderKeys) {
            $entry = $shaderWritePayload.changed.$key
            if ($null -eq $entry) { $shaderMismatch += ($key + '=missing'); continue }
            if ((Get-Canonical $entry.new) -cne (Get-Canonical $shaderBag.$key)) { $shaderMismatch += $key }
        }
    } else {
        $shaderMismatch += 'no payload'
    }
    $shaderAgainText = Invoke-Tool -Id 'B6_reread_shader_bag' -Tool 'project_read_resource' -Arguments @{ path = 'res://shader_material.tres' }
    $shaderAgain = Get-Payload $shaderAgainText
    foreach ($key in $shaderKeys) {
        if ((Get-Canonical $shaderAgain.properties.$key) -cne (Get-Canonical $shaderBag.$key)) { $shaderMismatch += ('reread:' + $key) }
    }
    Check 'B6_shader_bag_round_trips' ((Get-ErrorCode $shaderWriteText) -eq 0 -and $shaderMismatch.Count -eq 0) `
        ("code={0} mismatching keys: {1}" -f (Get-ErrorCode $shaderWriteText), (($shaderMismatch -join ', ') + $(if ($shaderMismatch.Count -eq 0) { '<none>' } else { '' })))

    # F-1 (registered, not fixed by this task): the *value* half of the same pair.
    # An unset uniform is answered `null` by the reader (the headless
    # RenderingServer has no default to give, material.cpp:342-347) and `null` is
    # refused for a non-Object property by the one value gate - the rule that
    # stops "a default was written silently". Both halves are honest, and the
    # file must be untouched by the refusal.
    $unsetPath = Join-Path $Proj 'shader_material_unset.tres'
    $unsetBefore = (Get-FileHash -Algorithm SHA256 -Path $unsetPath).Hash.ToLower()
    $unsetReadText = Invoke-Tool -Id 'B7_read_unset_shader_material' -Tool 'project_read_resource' -Arguments @{ path = 'res://shader_material_unset.tres' }
    $unsetRead = Get-Payload $unsetReadText
    $unsetNulls = ((Get-Canonical $unsetRead.properties.'shader_parameter/albedo') -ceq 'null') -and ((Get-Canonical $unsetRead.properties.'shader_parameter/uv1_scale') -ceq 'null')
    Check 'B7_unset_uniform_reads_null' $unsetNulls `
        ("shader_parameter/albedo = {0}; shader_parameter/uv1_scale = {1}" -f (Get-Canonical $unsetRead.properties.'shader_parameter/albedo'), (Get-Canonical $unsetRead.properties.'shader_parameter/uv1_scale'))
    $unsetWriteText = Invoke-BagWrite -Id 'B8_write_the_null_bag' -Tool 'project_edit_resource' -Path 'res://shader_material_unset.tres' -Bag $unsetRead.properties
    $unsetAfter = (Get-FileHash -Algorithm SHA256 -Path $unsetPath).Hash.ToLower()
    Check 'B8_null_for_a_non_object_property_is_refused_and_writes_nothing' `
        (((Get-ErrorCode $unsetWriteText) -eq -32602) -and ($unsetBefore -ceq $unsetAfter)) `
        ("code={0} message='{1}'; file sha256 before={2} after={3}" -f (Get-ErrorCode $unsetWriteText), (Get-ErrorMessage $unsetWriteText), $unsetBefore.Substring(0, 12), $unsetAfter.Substring(0, 12))

    # =========================================================================
    # D. the same family on the node and the ProjectSettings pairs
    # =========================================================================
    $openText = Invoke-Tool -Id 'D1_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'D1_scene_opened' ((Get-ErrorCode $openText) -eq 0) ("code={0}" -f (Get-ErrorCode $openText))

    $nodeReadText = Invoke-Tool -Id 'D2_read_joint_properties' -Tool 'editor_get_node_properties' `
        -Arguments @{ path = 'Joint'; properties = @('angular_limit/upper', 'params/bias') }
    $nodeRead = Get-Payload $nodeReadText
    $nodeSubPathOk = ($null -ne $nodeRead) -and ($null -ne $nodeRead.properties.'angular_limit/upper') -and ($null -ne $nodeRead.properties.'params/bias')
    Check 'D2_node_read_answers_sub_path_names' $nodeSubPathOk `
        ("angular_limit/upper = {0}; params/bias = {1} (code={2})" -f (Get-Canonical $nodeRead.properties.'angular_limit/upper'), (Get-Canonical $nodeRead.properties.'params/bias'), (Get-ErrorCode $nodeReadText))

    $nodeWriteText = Invoke-Tool -Id 'D3_write_joint_sub_path' -Tool 'editor_set_node_property' `
        -Arguments @{ path = 'Joint'; property = 'angular_limit/upper'; value = 42.5 }
    $nodeWritePayload = Get-Payload $nodeWriteText
    $nodeBackText = Invoke-Tool -Id 'D4_reread_joint_sub_path' -Tool 'editor_get_node_properties' `
        -Arguments @{ path = 'Joint'; properties = @('angular_limit/upper') }
    $nodeBack = Get-Payload $nodeBackText
    Check 'D3_node_write_and_reread_close' `
        (((Get-ErrorCode $nodeWriteText) -eq 0) -and ([double]$nodeBack.properties.'angular_limit/upper' -eq 42.5) -and ((Get-Canonical $nodeWritePayload.new_value) -ceq '42.5')) `
        ("code={0} new_value={1} re-read={2}" -f (Get-ErrorCode $nodeWriteText), (Get-Canonical $nodeWritePayload.new_value), (Get-Canonical $nodeBack.properties.'angular_limit/upper'))

    $settingsText = Invoke-Tool -Id 'D5_read_settings' -Tool 'project_get_settings' -Arguments @{ prefix = 'application/' }
    $settings = Get-Payload $settingsText
    $settingsKeys = Get-KeyList -Bag $settings.settings
    $slashSetting = @($settingsKeys | Where-Object { $_.Contains('/') } | Sort-Object)
    Check 'D5_settings_read_answers_slash_keys' (($slashSetting.Count -ge 3) -and ($slashSetting -contains 'application/config/name')) `
        ("application/* keys ({0}): {1}" -f $settingsKeys.Count, ($settingsKeys -join ', '))
    $nameKey = 'application/config/name'
    $setText = Invoke-Tool -Id 'D6_write_setting_key' -Tool 'project_set_setting' `
        -Arguments @{ key = $nameKey; value = 'task049_subpath_closure' }
    $setBackText = Invoke-Tool -Id 'D7_reread_setting_key' -Tool 'project_get_settings' -Arguments @{ prefix = $nameKey }
    $setBack = Get-Payload $setBackText
    Check 'D6_settings_key_round_trips' `
        (((Get-ErrorCode $setText) -eq 0) -and ([string]$setBack.settings.$nameKey -eq 'task049_subpath_closure')) `
        ("code={0} re-read={1}" -f (Get-ErrorCode $setText), $setBack.settings.$nameKey)

    # =========================================================================
    # E. the refusals that must not have been weakened
    # =========================================================================
    $spaceText = Invoke-Tool -Id 'E1_space_name' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://environment.tres'; properties = @{ 'not a property' = 1 } }
    Check 'E1_non_identifier_non_property_is_-32602' ((Get-ErrorCode $spaceText) -eq -32602) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $spaceText), (Get-ErrorMessage $spaceText))

    $emptyText = Invoke-Tool -Id 'E2_empty_name' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://environment.tres'; properties = @{ '' = 1 } }
    Check 'E2_empty_name_is_-32602' ((Get-ErrorCode $emptyText) -eq -32602) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $emptyText), (Get-ErrorMessage $emptyText))

    $unknownText = Invoke-Tool -Id 'E3_unknown_identifier' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://environment.tres'; properties = @{ no_such_property_xyz = 1 } }
    Check 'E3_unknown_identifier_is_-32001_with_a_suggestion' `
        (((Get-ErrorCode $unknownText) -eq -32001) -and (-not [string]::IsNullOrEmpty((Get-ErrorSuggestion $unknownText)))) `
        ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $unknownText), (Get-ErrorMessage $unknownText), (Get-ErrorSuggestion $unknownText))

    $colonText = Invoke-Tool -Id 'E4_colon_path_on_a_resource' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://environment.tres'; properties = @{ 'glow_levels:1' = 1 } }
    Check 'E4_colon_path_on_a_resource_stays_-32602' ((Get-ErrorCode $colonText) -eq -32602) `
        ("code={0} message='{1}' (the node writers take ':' paths; a resource bag takes the engine's own names)" -f (Get-ErrorCode $colonText), (Get-ErrorMessage $colonText))

    # =========================================================================
    # F. the engine-wide census of non-identifier property names
    # =========================================================================
    $censusCode = @'
var real = []
var labels = []
for c in ClassDB.get_class_list():
    for p in ClassDB.class_get_property_list(c, true):
        var n = String(p.name)
        if n.is_valid_identifier():
            continue
        if (p.usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_CATEGORY)) != 0:
            labels.append(c + "|" + n)
        else:
            real.append(c + "|" + n + "|" + str(p.type))
var slash = 0
var dot = 0
var colon = 0
var bracket = 0
var empty = 0
var space = 0
var other = 0
for entry in real:
    var n = entry.get_slice("|", 1)
    if n.is_empty():
        empty += 1
    elif n.contains("/"):
        slash += 1
    elif n.contains("."):
        dot += 1
    elif n.contains(":"):
        colon += 1
    elif n.contains("["):
        bracket += 1
    elif n.contains(" "):
        space += 1
    else:
        other += 1
return {"real": real, "labels": labels, "shapes": {"slash": slash, "dot": dot, "colon": colon, "bracket": bracket, "empty": empty, "space": space, "other": other}}
'@
    $censusText = Invoke-Tool -Id 'F1_census_non_identifier_names' -Tool 'editor_execute_gdscript' -Arguments @{ code = $censusCode }
    $census = Get-Payload $censusText
    $censusReal = @()
    $censusLabels = @()
    if ($null -ne $census) { $censusReal = @($census.result.real); $censusLabels = @($census.result.labels) }
    $envGlow = @($censusReal | Where-Object { $_ -like 'Environment|glow_levels/*' })
    Check 'F1_census_reaches_the_glow_levels' ($envGlow.Count -eq 7) `
        ("non-identifier *property* names: {0}; inspector labels: {1}; Environment glow_levels entries: {2}" -f $censusReal.Count, $censusLabels.Count, $envGlow.Count)
    Check 'F2_census_shape_breakdown' ($censusReal.Count -gt 200) `
        ("shapes (real properties only): slash={0} dot={1} colon={2} bracket={3} empty={4} space={5} other={6}" -f `
                $census.result.shapes.slash, $census.result.shapes.dot, $census.result.shapes.colon, $census.result.shapes.bracket, `
                $census.result.shapes.empty, $census.result.shapes.space, $census.result.shapes.other)
    $censusSample = @($censusReal | Sort-Object | Select-Object -First 12)
    Write-Host ("census sample: {0}" -f ($censusSample -join ', '))
    $labelSample = @($censusLabels | Sort-Object -Unique | Select-Object -First 8)
    Write-Host ("label sample: {0}" -f ($labelSample -join ', '))

    # =========================================================================
    # C. the file truth, read by a fresh game process (9889)
    # =========================================================================
    $finalWriteText = Invoke-Tool -Id 'C0_write_the_value_to_check' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://environment.tres'; properties = @{ 'glow_levels/1' = 1.5 } }
    Check 'C0_the_value_is_written' ((Get-ErrorCode $finalWriteText) -eq 0) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $finalWriteText), (Get-ErrorMessage $finalWriteText))

    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, "--mcp-port=$GamePort") -LogName 'game'
    Check 'C0b_game_endpoint_ready' (Wait-ForPump -Port_ $GamePort) ("game on {0} answered GET /mcp with +20 frames" -f $GamePort)

    $gameReadText = Invoke-Tool -Id 'C1_game_reads_the_same_file' -Tool 'project_read_resource' -Arguments @{ path = 'res://environment.tres' } -Port_ $GamePort
    $gameRead = Get-Payload $gameReadText
    Check 'C1_fresh_process_reads_the_written_value' ($null -ne $gameRead -and ([double]$gameRead.properties.'glow_levels/1' -eq 1.5)) `
        ("a second process (game, port {0}) reads properties['glow_levels/1'] = {1}" -f $GamePort, $gameRead.properties.'glow_levels/1')

    $savedFile = Join-Path $Proj 'environment.tres'
    $savedText = [IO.File]::ReadAllText($savedFile)
    $savedLines = @($savedText -split "`n" | Where-Object { $_.Contains('glow_levels') } | Sort-Object)
    Check 'C2_saved_file_spells_the_sub_path_name' (($savedLines.Count -ge 1) -and ($savedText.Contains('glow_levels/1'))) `
        ("the saved .tres spells {0} 'glow_levels/...' line(s): {1}" -f $savedLines.Count, ($savedLines -join ' / '))
} finally {
    Stop-Engine -Handle $gameHandle
    Stop-Engine -Handle $editorHandle
    Start-Sleep -Milliseconds 1500
    $userPidAfter = Get-ListenerPid -Port_ $UserPort
    $portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter $userPidAfter
    Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence
    Check 'port_9888_free_after' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
    Check 'port_9889_free_after' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))
}

$logPath = Join-Path $Ev 'evidence.log.txt'
$summary = @()
foreach ($entry in $script:Checks) {
    $entryTag = if ($entry.pass) { 'PASS' } else { 'FAIL' }
    $summary += ("[{0}] {1} :: {2}" -f $entryTag, $entry.id, $entry.evidence)
}
Write-McpUtf8NoBom -Path $logPath -Text (($summary -join "`r`n") + "`r`n")
Write-McpUtf8NoBom -Path (Join-Path $Ev 'results.json') -Text (ConvertTo-Json -InputObject $script:Checks -Depth 6)

$passed = @($script:Checks | Where-Object { $_.pass }).Count
$total = $script:Checks.Count
Write-Host ''
Write-Host ("{0}/{1} checks passed; evidence in {2}" -f $passed, $total, $Ev)
Write-Host ("log sha256 = {0}" -f (Get-FileHash -Algorithm SHA256 -Path $logPath).Hash.ToLower())
if ($passed -ne $total) { exit 1 }
exit 0
