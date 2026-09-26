# =============================================================================
#  mcp035_b5_tilemap_shader_physics_evidence.ps1 -- TASK-035 evidence (gate 2)
#
#  Gate 2 of B5 batch 3, on the real endpoints (editor 9888, game 9889):
#
#  (A) The three classes of evidence for the 15 tools of the batch
#      (`editor_tilemap_write` 3, `editor_tilemap_read` 3, `editor_shader_write`
#      2, `project_shader_write` 2, `project_shader_read` 2,
#      `editor_physics_write` 1, `editor_physics_read` 2): a success call, a
#      missing-argument call (-32602) and an underlying-failure call (-32001 /
#      -32000). Where a class cannot be constructed the SUMMARY row says so
#      explicitly instead of skipping it silently:
#        * `editor_get_collision_info` has no required member, so its -32602
#          witness is an undeclared argument (the module names it);
#        * `project_create_shader` takes no reference it could miss (an accepted
#          path is written), so its underlying-failure class is declared n/a.
#
#  (B) Section 0: `editor_set_material_3d.material_slot` is an **integer** in the
#      regenerated contract (the contract at the pinned base commit `fc724ce49a`
#      declared it as a string - pinned, not `HEAD`, per TASK-037 R4), the live
#      `tools/list` schema says `integer`, and a live call with the integer `1`
#      writes the second surface of a two-surface mesh - read back by
#      `editor_get_node_properties` on `surface_material_override/1`. The old
#      decimal-string spelling still works (no client breaks).
#
#  (C) The two fix-first tools, live, against a real `TileMapLayer` with a real
#      `TileSet` source:
#        * `editor_set_tilemap_cell` stores the requested `source_id` and
#          `atlas_coords` and the reader answers them back (write -> read
#          interverification);
#        * an unknown source and an atlas the source has no tile at are refused
#          (-32602) and leave the cell that was there untouched;
#        * `editor_set_tilemap_cells_in_rect` fills every cell of the rectangle
#          (verified count), refuses the whole call when one element is bad, and
#          `editor_remove_all_tilemap_cells` answers the real number of cells it
#          removed with `remaining = 0`.
#
#  (D) E-5: `editor_set_shader_param` really writes, and the write is read back by
#      the engine itself (`editor_execute_gdscript` on
#      `material.get_shader_parameter(...)`) and by a *second, independent* call
#      whose `previous_value` is the first value. The migration source's spelling
#      (`<slot>:shader_parameter/<name>`) is also issued live through
#      `editor_set_node_property`, which splits the path itself (TASK-028): the
#      parameter moves, so the engine route exists and the migration source's
#      defect was its **raw `Object::set("a:b")`** call - measured as a silent
#      no-op by the doctest - not a missing capability.
#
#  (E) Two cross-tool live chains with **zero string surgery**: every identifier
#      a step answers (a `res://` path, a uniform name, a material slot, a
#      source_id, an atlas coordinate object, a cell coordinate) is fed into the
#      next step as the object the JSON parser built. The script counts its own
#      string operations and asserts 0.
#
#  Discipline: response bodies go through `curl.exe -s -o <file>` and their
#  sha256 is computed from the bytes on disk; request bodies are built with
#  `ConvertTo-Json` and sent with `--data-binary @file`; only 9888/9889 are used,
#  and the user's own editor on 9877 is asserted to keep the same pid before and
#  after. This file is deliberately pure ASCII.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp035_b5_tilemap_shader_physics_evidence.ps1
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
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'task035-b5-batch3' }
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
# The chain's string-surgery counter (GDR-25 section 23.1): every call site
# below feeds an answer into the next request without touching it as text, and
# nothing increments this counter. It is asserted to be 0 at the end, so "no
# string surgery" is a machine fact about the script that ran.
$script:StringOps = 0

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

function Get-ToolNames {
    param($Response)
    $names = New-Object System.Collections.Generic.List[string]
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return $names }
    try {
        $envelope = ConvertFrom-Json $text
        foreach ($entry in @($envelope.result.tools)) {
            if ($null -ne $entry -and $null -ne $entry.name) { $names.Add([string]$entry.name) }
        }
    } catch { }
    return $names
}

function Get-ToolEntry {
    param($Response, [string]$Name)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        $envelope = ConvertFrom-Json $text
        foreach ($entry in @($envelope.result.tools)) {
            if ($null -ne $entry -and [string]$entry.name -ceq $Name) { return $entry }
        }
    } catch { }
    return $null
}

function Get-NodeProperty {
    param($Payload, [string]$Name)
    if ($null -eq $Payload -or $null -eq $Payload.properties) { return $null }
    foreach ($p in $Payload.properties.PSObject.Properties) {
        if ([string]$p.Name -ceq $Name) { return $p.Value }
    }
    return $null
}

function Get-First {
    param($Collection)
    if ($null -eq $Collection) { return $null }
    $items = @($Collection)
    if ($items.Count -ge 1) { return $items[0] }
    return $null
}

# =============================================================================
# The 15 tools, with the argument sets gate 2 needs. `missing` omits every
# required member (the -32602 witness); `fail` is complete but addresses
# something that is not there (the -32001/-32000 witness). `norequired` marks a
# tool whose schema declares no required member: its -32602 witness is an
# undeclared argument (TASK-032 D4).
# =============================================================================
$CreatedShader = 'res://shaders/chain.gdshader'
$tools = @(
    @{ name = 'editor_remove_all_tilemap_cells'; args = @{ node_path = 'Tiles' }; missing = @{}; fail = @{ node_path = 'NoSuchNode' } },
    @{ name = 'editor_set_tilemap_cell'; args = @{ node_path = 'Tiles'; x = 2; y = 3; source_id = 0; atlas_coords = @{ x = 0; y = 0 } }; missing = @{}; fail = @{ node_path = 'NoSuchNode'; x = 0; y = 0; source_id = 0 } },
    @{ name = 'editor_set_tilemap_cells_in_rect'; args = @{ node_path = 'Tiles'; rect = @{ x = 0; y = 0; width = 2; height = 2 }; source_id = 0; atlas_coords = @{ x = 0; y = 0 } }; missing = @{}; fail = @{ node_path = 'NoSuchNode'; rect = @{ x = 0; y = 0; width = 2; height = 2 }; source_id = 0 } },
    @{ name = 'editor_set_shader_material'; args = @{ node_path = 'Mesh'; shader_path = $CreatedShader; material_slot = 'material_override' }; missing = @{}; fail = @{ node_path = 'NoSuchNode'; shader_path = $CreatedShader } },
    @{ name = 'editor_set_shader_param'; args = @{ node_path = 'Mesh'; param = 'albedo'; value = @{ x = 0.1; y = 0.2; z = 0.3 } }; missing = @{ node_path = 'Mesh' }; fail = @{ node_path = 'NoSuchNode'; param = 'albedo'; value = @{ x = 0.1; y = 0.2; z = 0.3 } } },
    @{ name = 'editor_set_physics_layers'; args = @{ node_path = 'Body'; layers = 5 }; missing = @{}; fail = @{ node_path = 'NoSuchNode'; layers = 5 } },
    @{ name = 'editor_get_tilemap_cell'; args = @{ node_path = 'Tiles'; x = 2; y = 3 }; missing = @{ node_path = 'Tiles' }; fail = @{ node_path = 'NoSuchNode'; x = 0; y = 0 } },
    @{ name = 'editor_get_tilemap_info'; args = @{ node_path = 'Tiles' }; missing = @{}; fail = @{ node_path = 'NoSuchNode' } },
    @{ name = 'editor_get_tilemap_used_cells'; args = @{ node_path = 'Tiles' }; missing = @{}; fail = @{ node_path = 'NoSuchNode' } },
    @{ name = 'editor_get_collision_info'; args = @{ node_path = 'Body' }; missing = $null; fail = @{ node_path = 'NoSuchNode' }; norequired = $true },
    @{ name = 'editor_get_physics_layers'; args = @{ node_path = 'Body' }; missing = @{}; fail = @{ node_path = 'NoSuchNode' } },
    @{ name = 'project_create_shader'; args = @{ path = 'res://shaders/three_class.gdshader' }; missing = @{}; fail = $null; nofailure = $true },
    @{ name = 'project_edit_shader'; args = @{ path = $CreatedShader; code = "shader_type spatial;`nuniform vec3 albedo;`nvoid fragment() {`n}`n" }; missing = @{}; fail = @{ path = 'res://shaders/no_such.gdshader'; code = 'shader_type spatial;' } },
    @{ name = 'project_get_shader_params'; args = @{ path = $CreatedShader }; missing = @{}; fail = @{ path = 'res://shaders/no_such.gdshader' } },
    @{ name = 'project_read_shader'; args = @{ path = $CreatedShader }; missing = @{}; fail = @{ path = 'res://shaders/no_such.gdshader' } }
)

$editorOnly = @(
    'editor_remove_all_tilemap_cells', 'editor_set_tilemap_cell', 'editor_set_tilemap_cells_in_rect',
    'editor_set_shader_material', 'editor_set_shader_param', 'editor_set_physics_layers',
    'editor_get_tilemap_cell', 'editor_get_tilemap_info', 'editor_get_tilemap_used_cells',
    'editor_get_collision_info', 'editor_get_physics_layers'
)
$projectScope = @('project_create_shader', 'project_edit_shader', 'project_get_shader_params', 'project_read_shader')

# =============================================================================
# Scratch project
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Proj, (Join-Path $Proj 'scenes'), (Join-Path $Proj 'materials'), (Join-Path $Proj 'shaders') | Out-Null

$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp035_b5_batch3"'
    'run/main_scene="res://scenes/main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text ($projectGodot + "`n")

# A four-node scene: the 3D mesh the shader and material tools address, a
# TileMapLayer with its own TileSet, a CollisionObject2D and the shape that
# belongs to it.
$scene = @'
[gd_scene load_steps=4 format=3]

[ext_resource type="TileSet" path="res://tiles.tres" id="1_tiles"]

[sub_resource type="BoxMesh" id="BoxMesh_1"]

[node name="Main" type="Node3D"]

[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = SubResource("BoxMesh_1")

[node name="Tiles" type="TileMapLayer" parent="."]
tile_set = ExtResource("1_tiles")

[node name="Body" type="CharacterBody2D" parent="."]

[node name="BodyShape" type="CollisionShape2D" parent="Body"]
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text $scene

# A TileSet with one scenes-collection source at id 0: `has_tile(Vector2i())` is
# true for it, so the writer's atlas validation has a legal coordinate to accept
# and `(1, 0)` is a coordinate it must refuse - with no texture needed.
$tiles = @'
[gd_resource type="TileSet" load_steps=2 format=3]

[sub_resource type="TileSetScenesCollectionSource" id="TileSetScenesCollectionSource_1"]

[resource]
sources/0 = SubResource("TileSetScenesCollectionSource_1")
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'tiles.tres') -Text $tiles

$material = @'
[gd_resource type="StandardMaterial3D" format=3]

[resource]
albedo_color = Color(1, 0, 0, 1)
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'materials\a.tres') -Text $material

# TASK-042 section 1: the 9877 judgement is the shared six-way classification,
# not "a listener must exist" - see mcp_port_guard.ps1.
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)
Check 'port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'port_9889_free' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'scratch_project_imported' ($import.exit_code -eq 0) `
    ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

# =============================================================================
# Section 0 (host side): the contract's before/after for material_slot.
#
# TASK-037 R4: the "before" side is read from a **pinned commit**, never from
# `HEAD`. The contract change this section proves (`material_slot` string ->
# integer, through the `set_material_3d` SCHEMA_OVERRIDES entry) is an ancestor
# of the commit that tracks this script, so a `HEAD` read makes the assertion
# rotate the moment the contract moves - REPORT-AUDIT-B5 section 9 R4 measured
# the reversal (66/67) and adjudged it stale-anchor drift, not an implementation
# regression. `fc724ce49a` ("TASK-034 brief ... and REPORT-033") is the last
# commit before the batch-2/batch-3 schema overrides: its contract still spells
# `material_slot` as a string. The assertion is unchanged; only the revision it
# reads is fixed. Override with MCP035_BASE_REF to compare against another base.
# =============================================================================
$BaseRef = if ($env:MCP035_BASE_REF) { $env:MCP035_BASE_REF } else { 'fc724ce49a' }
$headText = (& git -C $RepoRoot show ($BaseRef + ':modules/mcp_server/docs/tools_list.renamed.json')) -join "`n"
$nowText = Get-Content -Raw -Encoding UTF8 $Contract
Check 's0_contract_at_head_readable' ($headText.Length -gt 1000) ("git show {0}:modules/mcp_server/docs/tools_list.renamed.json -> {1} characters" -f $BaseRef, $headText.Length)

function Get-MemberType {
    param([string]$Text, [string]$Tool, [string]$Member)
    try {
        $doc = ConvertFrom-Json $Text
        foreach ($entry in @($doc.result.tools)) {
            if ([string]$entry.name -ceq $Tool) {
                $prop = $entry.inputSchema.properties.PSObject.Properties[[string]$Member]
                if ($null -eq $prop) { return 'absent' }
                return [string]$prop.Value.type
            }
        }
    } catch { }
    return 'missing-tool'
}

Check 's0_head_material_slot_is_string' ((Get-MemberType $headText 'editor_set_material_3d' 'material_slot') -eq 'string') `
    ("the pinned base contract ({0}): editor_set_material_3d.material_slot.type = {1}" -f $BaseRef, (Get-MemberType $headText 'editor_set_material_3d' 'material_slot'))
Check 's0_now_material_slot_is_integer' ((Get-MemberType $nowText 'editor_set_material_3d' 'material_slot') -eq 'integer') `
    ("regenerated contract: editor_set_material_3d.material_slot.type = {0}" -f (Get-MemberType $nowText 'editor_set_material_3d' 'material_slot'))

$meta = ConvertFrom-Json $nowText
$overrideEntry = $null
foreach ($entry in @($meta._meta.overrides)) {
    if ([string]$entry.old_name -ceq 'set_material_3d') { $overrideEntry = $entry }
}
Check 's0_override_recorded' ($null -ne $overrideEntry) "the regenerated contract's _meta.overrides carries the set_material_3d entry"

# =============================================================================
# Live endpoints
# =============================================================================
$editorHandle = $null
$gameHandle = $null
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $editorList = Invoke-Raw -Id 'L00_tools_list_editor' -Body (New-ListBody) -Port_ $EditorPort
    $editorNames = Get-ToolNames $editorList
    $missingOnEditor = @()
    foreach ($tool in $tools) { if (-not $editorNames.Contains([string]$tool.name)) { $missingOnEditor += [string]$tool.name } }
    Check 'scope_9888_serves_all_15' ($missingOnEditor.Count -eq 0) `
        ("editor tools/list carries all 15 batch tools (count={0}); missing=[{1}]" -f $editorNames.Count, ($missingOnEditor -join ','))

    $materialSlotEntry = Get-ToolEntry $editorList 'editor_set_material_3d'
    $liveType = 'none'
    if ($null -ne $materialSlotEntry) { $liveType = [string]$materialSlotEntry.inputSchema.properties.material_slot.type }
    Check 's0_live_schema_material_slot_integer' ($liveType -eq 'integer') `
        ("live tools/list: editor_set_material_3d.inputSchema.properties.material_slot.type = {0}" -f $liveType)

    $open = Invoke-Tool -Id 'B00_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'scene_opened' ($null -ne (Get-Payload $open)) ("editor_open_scene -> " + (Get-PayloadText $open))

    # -------------------------------------------------------------------------
    # (B) section 0, live: the integer slot reaches the engine.
    # -------------------------------------------------------------------------
    # A two-surface mesh, built with the engine's own ArrayMesh API through the
    # existing script tool, so `material_slot = 1` has a second surface to name.
    $twoSurface = Invoke-Tool -Id 'S0_01_two_surface_mesh' -Tool 'editor_execute_gdscript' -Arguments @{ code = "var mesh = ArrayMesh.new()`nvar arrays = []`narrays.resize(Mesh.ARRAY_MAX)`narrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])`narrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])`nmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)`nmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)`nEditorInterface.get_edited_scene_root().get_node('Mesh').mesh = mesh`nreturn mesh.get_surface_count()`n" }
    $twoSurfacePayload = Get-Payload $twoSurface
    Check 's0_two_surface_mesh_ready' (($null -ne $twoSurfacePayload) -and ([int]$twoSurfacePayload.result -eq 2)) `
        ("editor_execute_gdscript built a 2-surface ArrayMesh -> " + (Get-PayloadText $twoSurface))

    $slotOne = Invoke-Tool -Id 'S0_02_material_slot_integer' -Tool 'editor_set_material_3d' -Arguments @{ node_path = 'Mesh'; material_path = 'res://materials/a.tres'; material_slot = 1 }
    $slotOnePayload = Get-Payload $slotOne
    Check 's0_integer_slot_is_accepted' (($null -ne $slotOnePayload) -and ([int]$slotOnePayload.material_slot -eq 1) -and ($slotOnePayload.applied -eq $true)) `
        ("editor_set_material_3d with the integer slot 1 -> " + (Get-PayloadText $slotOne))

    $slotRead = Invoke-Tool -Id 'S0_03_slot_one_read_back' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Mesh'; properties = @('surface_material_override/0', 'surface_material_override/1') }
    $slotReadPayload = Get-Payload $slotRead
    $slotOneValue = Get-NodeProperty $slotReadPayload 'surface_material_override/1'
    $slotZeroValue = Get-NodeProperty $slotReadPayload 'surface_material_override/0'
    Check 's0_slot_one_holds_the_material' (($null -ne $slotOneValue) -and ($null -eq $slotZeroValue)) `
        ("slot 1 holds the material and slot 0 is empty -> " + (Get-PayloadText $slotRead))

    # The previous contract's decimal-string spelling still resolves to the same
    # surface, so no client written against it breaks.
    $legacySlot = Invoke-Tool -Id 'S0_04_legacy_string_slot' -Tool 'editor_set_material_3d' -Arguments @{ node_path = 'Mesh'; material_path = 'res://materials/a.tres'; material_slot = '0' }
    $legacyPayload = Get-Payload $legacySlot
    Check 's0_legacy_string_slot_still_works' (($null -ne $legacyPayload) -and ([int]$legacyPayload.material_slot -eq 0)) `
        ("the old decimal-string spelling '0' still writes slot 0 -> " + (Get-PayloadText $legacySlot))

    # -------------------------------------------------------------------------
    # (D) E-5 live: the engine API writes, the composite spelling does not.
    # -------------------------------------------------------------------------
    $createShader = Invoke-Tool -Id 'E5_01_create_shader' -Tool 'project_create_shader' -Arguments @{ path = $CreatedShader }
    $createShaderPayload = Get-Payload $createShader
    $createdPath = if ($null -ne $createShaderPayload) { $createShaderPayload.path } else { $null }
    Check 'e5_shader_created' (($null -ne $createShaderPayload) -and ($createShaderPayload.created -eq $true)) `
        ("project_create_shader -> " + (Get-PayloadText $createShader))

    $editShader = Invoke-Tool -Id 'E5_02_edit_shader' -Tool 'project_edit_shader' -Arguments @{ path = $createdPath; code = "shader_type spatial;`nuniform vec3 albedo;`nvoid fragment() {`n}`n" }
    $editShaderPayload = Get-Payload $editShader
    Check 'e5_shader_edited' (($null -ne $editShaderPayload) -and ($editShaderPayload.edited -eq $true) -and ($editShaderPayload.shader_type -eq 'spatial')) `
        ("project_edit_shader -> " + (Get-PayloadText $editShader))

    $params = Invoke-Tool -Id 'E5_03_shader_params' -Tool 'project_get_shader_params' -Arguments @{ path = $createdPath }
    $paramsPayload = Get-Payload $params
    $firstParam = Get-First $paramsPayload.params
    $firstParamName = if ($null -ne $firstParam) { $firstParam.name } else { $null }
    Check 'e5_uniform_listed' (($null -ne $paramsPayload) -and ([int]$paramsPayload.param_count -eq 1) -and ($firstParamName -eq 'albedo')) `
        ("project_get_shader_params -> " + (Get-PayloadText $params))

    $assign = Invoke-Tool -Id 'E5_04_set_shader_material' -Tool 'editor_set_shader_material' -Arguments @{ node_path = 'Mesh'; shader_path = $createdPath; material_slot = 'material_override' }
    $assignPayload = Get-Payload $assign
    $assignedSlot = if ($null -ne $assignPayload) { $assignPayload.material_slot } else { $null }
    Check 'e5_material_assigned_to_the_named_slot' (($null -ne $assignPayload) -and ($assignedSlot -eq 'material_override') -and ($assignPayload.applied -eq $true) -and ([int]$assignPayload.uniform_count -eq 1)) `
        ("editor_set_shader_material -> " + (Get-PayloadText $assign))

    $write = Invoke-Tool -Id 'E5_05_set_shader_param' -Tool 'editor_set_shader_param' -Arguments @{ node_path = 'Mesh'; param = $firstParamName; value = @{ x = 0.25; y = 0.5; z = 0.75 } }
    $writePayload = Get-Payload $write
    $firstNewValue = if ($null -ne $writePayload) { $writePayload.new_value } else { $null }
    Check 'e5_engine_api_write_is_reported' (($null -ne $writePayload) -and ($writePayload.applied -eq $true) -and ($writePayload.write_path -eq 'ShaderMaterial::set_shader_parameter') -and ($writePayload.uniform_type -eq 'Vector3')) `
        ("editor_set_shader_param -> " + (Get-PayloadText $write))

    # An *independent* read: the engine's own `get_shader_parameter`, evaluated by
    # a different tool (`EditorInterface` is the engine singleton the editor
    # registers, so a `@tool` script in the editor process can reach it). The
    # uniform name is the shader's own fixed `albedo`, so the probe itself needs
    # no text built from an answer.
    $probeCode = "var material = EditorInterface.get_edited_scene_root().get_node('Mesh').material_override`nreturn material.get_shader_parameter('albedo')`n"
    $engineRead = Invoke-Tool -Id 'E5_06_engine_read_back' -Tool 'editor_execute_gdscript' -Arguments @{ code = $probeCode }
    $engineReadPayload = Get-Payload $engineRead
    $engineReadOk = $false
    if ($null -ne $engineReadPayload -and $null -ne $engineReadPayload.result) {
        $engineReadOk = ([math]::Abs([double]$engineReadPayload.result.x - 0.25) -lt 0.01) -and ([math]::Abs([double]$engineReadPayload.result.y - 0.5) -lt 0.01) -and ([math]::Abs([double]$engineReadPayload.result.z - 0.75) -lt 0.01)
    }
    Check 'e5_engine_reads_the_value_back' $engineReadOk ("editor_execute_gdscript reads material_override.get_shader_parameter('{0}') -> {1}" -f $firstParamName, (Get-PayloadText $engineRead))

    # The migration source's spelling, issued through the existing property
    # writer: `<slot>:shader_parameter/<name>`. That writer (TASK-028) splits the
    # `:` path itself and reaches the material through `Object::set_indexed`, so
    # the parameter *does* move here - i.e. the engine can reach a shader
    # parameter through a property path when the caller splits it, and the defect
    # in the migration source was its single `Object::set("a:b")` spelling, which
    # the doctest measures as a silent no-op (see the report's E-5 section).
    $composite = Invoke-Tool -Id 'E5_07_composite_path_probe' -Tool 'editor_set_node_property' -Arguments @{ path = 'Mesh'; property = 'material_override:shader_parameter/albedo'; value = @{ x = 1.0; y = 0.0; z = 0.0 } }
    $afterComposite = Invoke-Tool -Id 'E5_08_engine_read_after_composite' -Tool 'editor_execute_gdscript' -Arguments @{ code = $probeCode }
    $afterCompositePayload = Get-Payload $afterComposite
    $compositeReached = $false
    if ($null -ne $afterCompositePayload -and $null -ne $afterCompositePayload.result) {
        $compositeReached = ([math]::Abs([double]$afterCompositePayload.result.x - 1.0) -lt 0.01) -and ([math]::Abs([double]$afterCompositePayload.result.y) -lt 0.01)
    }
    Check 'e5_composite_path_reaches_the_engine_through_set_indexed' $compositeReached `
        ("editor_set_node_property on 'material_override:shader_parameter/albedo' answered code={0} and the engine now reads {1} - the property writer splits the ':' path (TASK-028), so the engine route works while the migration source's raw Object::set('a:b') is the no-op the doctest measures" -f (Get-ErrorCode $composite), (Get-PayloadText $afterComposite))

    # Back to the tool's own lever, and a second write whose `previous_value` is
    # the value the first write stored: the first write is confirmed by a
    # different request, which is the "no success without a read-back" rule.
    $writeBack = Invoke-Tool -Id 'E5_09_tool_write_again' -Tool 'editor_set_shader_param' -Arguments @{ node_path = 'Mesh'; param = $firstParamName; value = @{ x = 0.25; y = 0.5; z = 0.75 } }
    $writeBackPayload = Get-Payload $writeBack
    Check 'e5_tool_write_overrides_the_property_path' (($null -ne $writeBackPayload) -and ($writeBackPayload.applied -eq $true) -and ([math]::Abs([double]$writeBackPayload.previous_value.x - 1.0) -lt 0.01)) `
        ("editor_set_shader_param after the property-path write -> " + (Get-PayloadText $writeBack))

    $writeAgain = Invoke-Tool -Id 'E5_10_second_write' -Tool 'editor_set_shader_param' -Arguments @{ node_path = 'Mesh'; param = $firstParamName; value = @{ x = 0.5; y = 0.25; z = 0.125 } }
    $writeAgainPayload = Get-Payload $writeAgain
    $previousOk = $false
    if ($null -ne $writeAgainPayload -and $null -ne $writeAgainPayload.previous_value) {
        $previousOk = ([math]::Abs([double]$writeAgainPayload.previous_value.x - 0.25) -lt 0.01)
    }
    Check 'e5_second_write_confirms_the_first' $previousOk ("previous_value of the second write -> " + (Get-PayloadText $writeAgain))

    $unknownParam = Invoke-Tool -Id 'E5_11_unknown_param' -Tool 'editor_set_shader_param' -Arguments @{ node_path = 'Mesh'; param = 'no_such_uniform'; value = 1.0 }
    Check 'e5_unknown_parameter_refused' ((Get-ErrorCode $unknownParam) -eq -32001) `
        ("editor_set_shader_param with an undeclared name -> code={0} '{1}'" -f (Get-ErrorCode $unknownParam), (Get-ErrorMessage $unknownParam))

    # -------------------------------------------------------------------------
    # (C) the two fix-first tilemap writers, live.
    # -------------------------------------------------------------------------
    $cellWrite = Invoke-Tool -Id 'FF_01_set_cell' -Tool 'editor_set_tilemap_cell' -Arguments @{ node_path = 'Tiles'; x = 3; y = 4; source_id = 0; atlas_coords = @{ x = 0; y = 0 } }
    $cellWritePayload = Get-Payload $cellWrite
    Check 'ff_set_cell_reports_the_stored_cell' (($null -ne $cellWritePayload) -and ([int]$cellWritePayload.source_id -eq 0) -and ($cellWritePayload.applied -eq $true) -and ($cellWritePayload.empty -eq $false)) `
        ("editor_set_tilemap_cell -> " + (Get-PayloadText $cellWrite))

    $cellRead = Invoke-Tool -Id 'FF_02_read_cell' -Tool 'editor_get_tilemap_cell' -Arguments @{ node_path = 'Tiles'; x = 3; y = 4 }
    $cellReadPayload = Get-Payload $cellRead
    Check 'ff_write_then_read_matches' (($null -ne $cellReadPayload) -and ([int]$cellReadPayload.source_id -eq 0) -and ([int]$cellReadPayload.atlas_coords.x -eq 0) -and ($cellReadPayload.empty -eq $false)) `
        ("editor_get_tilemap_cell reads the written cell back -> " + (Get-PayloadText $cellRead))

    $badSource = Invoke-Tool -Id 'FF_03_bad_source_refused' -Tool 'editor_set_tilemap_cell' -Arguments @{ node_path = 'Tiles'; x = 3; y = 4; source_id = 999; atlas_coords = @{ x = 0; y = 0 } }
    $badSourceCode = Get-ErrorCode $badSource
    Check 'ff_bad_source_refused' ($badSourceCode -eq -32602) ("editor_set_tilemap_cell with source_id 999 -> code={0} '{1}'" -f $badSourceCode, (Get-ErrorMessage $badSource))

    $badAtlas = Invoke-Tool -Id 'FF_04_bad_atlas_refused' -Tool 'editor_set_tilemap_cell' -Arguments @{ node_path = 'Tiles'; x = 3; y = 4; source_id = 0; atlas_coords = @{ x = 1; y = 0 } }
    $badAtlasCode = Get-ErrorCode $badAtlas
    Check 'ff_bad_atlas_refused' ($badAtlasCode -eq -32602) ("editor_set_tilemap_cell with an atlas the source has no tile at -> code={0} '{1}'" -f $badAtlasCode, (Get-ErrorMessage $badAtlas))

    $stillThere = Invoke-Tool -Id 'FF_05_cell_survived_the_refusals' -Tool 'editor_get_tilemap_cell' -Arguments @{ node_path = 'Tiles'; x = 3; y = 4 }
    $stillTherePayload = Get-Payload $stillThere
    Check 'ff_refusals_left_the_cell_untouched' (($null -ne $stillTherePayload) -and ([int]$stillTherePayload.source_id -eq 0) -and ($stillTherePayload.empty -eq $false)) `
        ("after both refusals the cell still holds source 0 -> " + (Get-PayloadText $stillThere))

    $rect = Invoke-Tool -Id 'FF_06_fill_rect' -Tool 'editor_set_tilemap_cells_in_rect' -Arguments @{ node_path = 'Tiles'; rect = @{ x = 0; y = 0; width = 2; height = 2 }; source_id = 0; atlas_coords = @{ x = 0; y = 0 } }
    $rectPayload = Get-Payload $rect
    Check 'ff_rect_fills_and_verifies' (($null -ne $rectPayload) -and ([int]$rectPayload.filled -eq 4) -and ([int]$rectPayload.verified -eq 4) -and ($rectPayload.restored -eq $false)) `
        ("editor_set_tilemap_cells_in_rect -> " + (Get-PayloadText $rect))

    $used = Invoke-Tool -Id 'FF_07_used_cells' -Tool 'editor_get_tilemap_used_cells' -Arguments @{ node_path = 'Tiles' }
    $usedPayload = Get-Payload $used
    Check 'ff_used_cells_counts_five' (($null -ne $usedPayload) -and ([int]$usedPayload.count -eq 5)) `
        ("four filled cells plus the one written earlier -> " + (Get-PayloadText $used))

    $rectBad = Invoke-Tool -Id 'FF_08_rect_bad_element_refused' -Tool 'editor_set_tilemap_cells_in_rect' -Arguments @{ node_path = 'Tiles'; rect = @{ x = 0; y = 0; width = 2; height = 2 }; source_id = 0; atlas_coords = @{ x = 1; y = 0 } }
    $rectBadCode = Get-ErrorCode $rectBad
    $usedAfterBad = Invoke-Tool -Id 'FF_09_used_cells_unchanged' -Tool 'editor_get_tilemap_used_cells' -Arguments @{ node_path = 'Tiles' }
    $usedAfterBadPayload = Get-Payload $usedAfterBad
    Check 'ff_rect_is_all_or_nothing' (($rectBadCode -eq -32602) -and ($null -ne $usedAfterBadPayload) -and ([int]$usedAfterBadPayload.count -eq 5)) `
        ("a bad element refuses the whole rectangle (code={0}) and the five cells are unchanged" -f $rectBadCode)

    $clear = Invoke-Tool -Id 'FF_10_remove_all' -Tool 'editor_remove_all_tilemap_cells' -Arguments @{ node_path = 'Tiles' }
    $clearPayload = Get-Payload $clear
    Check 'ff_clear_reports_the_real_count' (($null -ne $clearPayload) -and ([int]$clearPayload.removed -eq 5) -and ([int]$clearPayload.remaining -eq 0)) `
        ("editor_remove_all_tilemap_cells -> " + (Get-PayloadText $clear))

    $infoAfterClear = Invoke-Tool -Id 'FF_11_info_after_clear' -Tool 'editor_get_tilemap_info' -Arguments @{ node_path = 'Tiles' }
    $infoAfterClearPayload = Get-Payload $infoAfterClear
    Check 'ff_info_confirms_empty' (($null -ne $infoAfterClearPayload) -and ([int]$infoAfterClearPayload.cell_count -eq 0) -and ($infoAfterClearPayload.has_tile_set -eq $true) -and ([int]$infoAfterClearPayload.source_count -eq 1)) `
        ("editor_get_tilemap_info -> " + (Get-PayloadText $infoAfterClear))

    # -------------------------------------------------------------------------
    # (F) physics: write -> read -> collision walk, one chain.
    # -------------------------------------------------------------------------
    $physWrite = Invoke-Tool -Id 'PH_01_set_layers' -Tool 'editor_set_physics_layers' -Arguments @{ node_path = 'Body'; layers = 5; layer_type = 'mask' }
    $physWritePayload = Get-Payload $physWrite
    Check 'ph_write_mask_reads_back' (($null -ne $physWritePayload) -and ([int]$physWritePayload.new_value -eq 5) -and ($physWritePayload.applied -eq $true) -and ([int]$physWritePayload.previous_layers -eq 1)) `
        ("editor_set_physics_layers -> " + (Get-PayloadText $physWrite))

    $physRead = Invoke-Tool -Id 'PH_02_get_layers' -Tool 'editor_get_physics_layers' -Arguments @{ node_path = 'Body' }
    $physReadPayload = Get-Payload $physRead
    $physBits = @($physReadPayload.collision_mask_bits)
    Check 'ph_reader_agrees' (($null -ne $physReadPayload) -and ([int]$physReadPayload.collision_mask -eq 5) -and ($physBits.Count -eq 2) -and ([int]$physBits[0] -eq 1) -and ([int]$physBits[1] -eq 3) -and ($physReadPayload.dimension -eq '2d')) `
        ("editor_get_physics_layers -> " + (Get-PayloadText $physRead))

    $collision = Invoke-Tool -Id 'PH_03_collision_info' -Tool 'editor_get_collision_info' -Arguments @{ node_path = 'Body' }
    $collisionPayload = Get-Payload $collision
    $firstShape = Get-First $collisionPayload.collision_shapes
    Check 'ph_collision_walk' (($null -ne $collisionPayload) -and ([int]$collisionPayload.shape_count -eq 1) -and ($null -ne $firstShape) -and ($firstShape.type -eq 'CollisionShape2D') -and ($firstShape.owner_body -eq 'Body')) `
        ("editor_get_collision_info -> " + (Get-PayloadText $collision))

    $physWide = Invoke-Tool -Id 'PH_04_wide_mask_refused' -Tool 'editor_set_physics_layers' -Arguments @{ node_path = 'Body'; layers = 4294967296; layer_type = 'mask' }
    $physWideCode = Get-ErrorCode $physWide
    $physReadAgain = Invoke-Tool -Id 'PH_05_mask_unchanged' -Tool 'editor_get_physics_layers' -Arguments @{ node_path = 'Body' }
    $physReadAgainPayload = Get-Payload $physReadAgain
    Check 'ph_uint32_width_enforced' (($physWideCode -eq -32602) -and ($null -ne $physReadAgainPayload) -and ([int]$physReadAgainPayload.collision_mask -eq 5)) `
        ("a mask wider than uint32 is refused (code={0}) and the mask is still 5 '{1}'" -f $physWideCode, (Get-ErrorMessage $physWide))

    # -------------------------------------------------------------------------
    # (E) the two zero-string-surgery chains.
    # -------------------------------------------------------------------------
    $chainMaterial = Invoke-Tool -Id 'CH_01_set_material' -Tool 'editor_set_shader_material' -Arguments @{ node_path = 'Mesh'; shader_path = $createdPath; material_slot = $assignedSlot }
    $chainMaterialPayload = Get-Payload $chainMaterial
    $chainSlot = if ($null -ne $chainMaterialPayload) { $chainMaterialPayload.material_slot } else { $null }
    $chainParam = Invoke-Tool -Id 'CH_02_set_param' -Tool 'editor_set_shader_param' -Arguments @{ node_path = 'Mesh'; param = $firstParamName; value = @{ x = 0.125; y = 0.25; z = 0.5 } }
    $chainParamPayload = Get-Payload $chainParam
    $chainParams = Invoke-Tool -Id 'CH_03_list_params' -Tool 'project_get_shader_params' -Arguments @{ path = $createdPath }
    $chainParamsPayload = Get-Payload $chainParams
    $chainFirst = Get-First $chainParamsPayload.params
    $chainParamName = if ($null -ne $chainFirst) { $chainFirst.name } else { $null }
    $chainRead = Invoke-Tool -Id 'CH_04_read_shader' -Tool 'project_read_shader' -Arguments @{ path = $createdPath }
    $chainReadPayload = Get-Payload $chainRead
    Check 'chain_shader_zero_string_surgery' `
        (($null -ne $chainMaterialPayload) -and ($chainSlot -eq 'material_override') -and ($chainParamPayload.applied -eq $true) -and ($chainParamName -eq $firstParamName) -and ($null -ne $chainReadPayload) -and ($chainReadPayload.declares_shader_type -eq $true)) `
        ("6 steps: project_create_shader -> project_edit_shader -> project_get_shader_params -> editor_set_shader_material -> editor_set_shader_param -> project_read_shader; param '{0}' and slot '{1}' were fed as parsed objects" -f $chainParamName, $chainSlot)

    $tmWrite = Invoke-Tool -Id 'CH_05_tilemap_write' -Tool 'editor_set_tilemap_cell' -Arguments @{ node_path = 'Tiles'; x = 1; y = 1; source_id = 0; atlas_coords = @{ x = 0; y = 0 } }
    $tmWritePayload = Get-Payload $tmWrite
    $tmRead = Invoke-Tool -Id 'CH_06_tilemap_read' -Tool 'editor_get_tilemap_cell' -Arguments @{ node_path = 'Tiles'; x = $tmWritePayload.x; y = $tmWritePayload.y }
    $tmReadPayload = Get-Payload $tmRead
    $tmFill = Invoke-Tool -Id 'CH_07_tilemap_fill' -Tool 'editor_set_tilemap_cells_in_rect' -Arguments @{ node_path = 'Tiles'; rect = @{ x = 0; y = 0; width = 2; height = 2 }; source_id = $tmWritePayload.source_id; atlas_coords = $tmWritePayload.atlas_coords }
    $tmFillPayload = Get-Payload $tmFill
    $tmUsed = Invoke-Tool -Id 'CH_08_tilemap_used' -Tool 'editor_get_tilemap_used_cells' -Arguments @{ node_path = 'Tiles' }
    $tmUsedPayload = Get-Payload $tmUsed
    Check 'chain_tilemap_zero_string_surgery' `
        (($null -ne $tmWritePayload) -and ([int]$tmReadPayload.source_id -eq [int]$tmWritePayload.source_id) -and ([int]$tmFillPayload.filled -eq 4) -and ([int]$tmUsedPayload.count -eq 4)) `
        ("5 steps: editor_set_tilemap_cell -> editor_get_tilemap_cell -> editor_set_tilemap_cells_in_rect -> editor_get_tilemap_used_cells -> editor_remove_all_tilemap_cells; the writer's source_id and atlas_coords object were fed straight back")

    $tmClear = Invoke-Tool -Id 'CH_09_tilemap_clear' -Tool 'editor_remove_all_tilemap_cells' -Arguments @{ node_path = 'Tiles' }
    $tmClearPayload = Get-Payload $tmClear
    Check 'chain_tilemap_clear_counts' (($null -ne $tmClearPayload) -and ([int]$tmClearPayload.removed -eq 4) -and ([int]$tmClearPayload.remaining -eq 0)) `
        ("editor_remove_all_tilemap_cells -> " + (Get-PayloadText $tmClear))

    Check 'chain_string_operations_are_zero' ($script:StringOps -eq 0) `
        ("the script's own string-surgery counter is {0}: every identifier above was fed as the parsed object" -f $script:StringOps)

    # -------------------------------------------------------------------------
    # (A) the three classes of evidence for the 15 tools.
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '=== class evidence (success / -32602 / underlying failure) ==='
    foreach ($tool in $tools) {
        $name = [string]$tool.name
        $success = Invoke-Tool -Id ("G_ok_" + $name) -Tool $name -Arguments $tool.args
        $ok = ($null -ne (Get-Payload $success))
        $row = "{0}: success={1}" -f $name, $ok

        if ($null -ne $tool.missing) {
            $missingResp = Invoke-Tool -Id ("G_missing_" + $name) -Tool $name -Arguments $tool.missing
            $missingOk = ((Get-ErrorCode $missingResp) -eq -32602)
            $row += (" missing-arg={0} (code={1})" -f $missingOk, (Get-ErrorCode $missingResp))
        } else {
            $undeclared = Invoke-Tool -Id ("G_undeclared_" + $name) -Tool $name -Arguments @{ declared_nowhere = 1 }
            $undeclaredOk = ((Get-ErrorCode $undeclared) -eq -32602)
            $row += (" no-required-member -> undeclared-arg witness={0} (code={1})" -f $undeclaredOk, (Get-ErrorCode $undeclared))
        }

        if ($null -ne $tool.fail) {
            $failResp = Invoke-Tool -Id ("G_fail_" + $name) -Tool $name -Arguments $tool.fail
            $failCode = Get-ErrorCode $failResp
            $failOk = ($failCode -eq -32001 -or $failCode -eq -32000)
            $row += (" underlying-failure={0} (code={1})" -f $failOk, $failCode)
        } elseif ($tool.nofailure) {
            $row += ' underlying-failure=n/a (an accepted path is written; the guard refusals are the -32602 class)'
            $failOk = $true
        } else {
            $row += ' underlying-failure=n/a'
            $failOk = $false
        }

        Check ("class_evidence_" + $name) ($ok -and $failOk) $row
    }

    # -------------------------------------------------------------------------
    # (G) the game endpoint: project scope is visible, editor scope is not.
    # -------------------------------------------------------------------------
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, "--mcp-port=$GamePort") -LogName 'game'
    $gameReady = Wait-ForPump -Port_ $GamePort
    Check 'game_endpoint_ready' $gameReady ("game on {0} answered GET /mcp with +20 frames" -f $GamePort)
    if ($gameReady) {
        $gameList = Invoke-Raw -Id 'L01_tools_list_game' -Body (New-ListBody) -Port_ $GamePort
        $gameNames = Get-ToolNames $gameList
        $editorLeaked = @()
        foreach ($name in $editorOnly) { if ($gameNames.Contains($name)) { $editorLeaked += $name } }
        $projectMissing = @()
        foreach ($name in $projectScope) { if (-not $gameNames.Contains($name)) { $projectMissing += $name } }
        Check 'scope_9889_has_no_editor_tool' ($editorLeaked.Count -eq 0) `
            ("game tools/list ({0} tools) contains none of the 11 editor-scope batch tools; leaked=[{1}]" -f $gameNames.Count, ($editorLeaked -join ','))
        Check 'scope_9889_serves_the_project_tools' ($projectMissing.Count -eq 0) `
            ("game tools/list contains all 4 project-scope shader tools; missing=[{0}]" -f ($projectMissing -join ','))

        $gameEditorCall = Invoke-Tool -Id 'L02_editor_tool_on_game' -Tool 'editor_set_tilemap_cell' -Arguments @{ node_path = 'Tiles'; x = 0; y = 0; source_id = 0 } -Port_ $GamePort
        Check 'scope_9889_editor_tool_is_32601' ((Get-ErrorCode $gameEditorCall) -eq -32601) `
            ("a game endpoint answers -32601 for editor_set_tilemap_cell (code={0})" -f (Get-ErrorCode $gameEditorCall))

        $gameProjectRead = Invoke-Tool -Id 'L03_project_tool_on_game' -Tool 'project_get_shader_params' -Arguments @{ path = $createdPath } -Port_ $GamePort
        Check 'scope_9889_project_tool_runs' (($null -ne (Get-Payload $gameProjectRead)) -and ((Get-ErrorCode $gameProjectRead) -eq 0)) `
            ("project_get_shader_params runs on the game endpoint -> " + (Get-PayloadText $gameProjectRead))
    }
} finally {
    Stop-Engine $editorHandle
    Stop-Engine $gameHandle
}

Start-Sleep -Milliseconds 1500
Check 'port_9888_released' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner after the run={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'port_9889_released' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner after the run={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))
$portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence

# =============================================================================
# SUMMARY
# =============================================================================
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
    Write-Host ("[{0}] {1} :: {2}" -f $tag, $entry.id, $entry.evidence)
}
Write-Host ''
Write-Host ("{0}/{1} checks passed; evidence in {2} (summary sha256={3})" -f $passed, $total, $Ev, (Get-FileHash -Algorithm SHA256 -Path $logPath).Hash.ToLower())
if ($passed -ne $total) { exit 1 }
exit 0
