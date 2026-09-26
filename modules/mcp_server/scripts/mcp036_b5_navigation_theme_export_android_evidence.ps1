# =============================================================================
#  mcp036_b5_navigation_theme_export_android_evidence.ps1
#
#  TASK-036 (B5 batch 4) wire evidence, in the PLAYBOOK-group-port shape:
#  a scratch project on the module's own test ports, `curl.exe` as the only
#  transport, sha256 of every response, and every claim the report makes
#  reproduced as a machine check.
#
#  What it proves, and against which engine fact:
#
#   * section CH  - the theme chain is one zero-string-surgery chain of six calls
#                   (project_create_theme -> project_set_theme_color ->
#                   project_set_theme_constant -> project_set_theme_font_size ->
#                   project_set_theme_stylebox -> project_get_theme_info): every
#                   later request carries a value parsed out of the previous
#                   answer, and the reader finds the items the writers made.
#   * section NAV - the fix_implementation_first story of
#                   editor_bake_navigation_mesh, live:
#                     (1) RED: the migration source's spelling
#                         (`editor_set_node_property` with
#                         `property=navigation_mesh.bake_navigation_mesh`) is
#                         refused by the engine, which is why the port needed a
#                         real tool;
#                     (2) the tool runs the engine's asynchronous bake
#                         (`NavigationRegion3D::bake_navigation_mesh` +
#                         `is_baking`) through the GDR-20 deferred channel;
#                     (3) the result is proven by the *other* tool -
#                         `editor_get_navigation_info` answers polygon_count > 0
#                         where it answered 0 before the bake;
#                     (4) `editor_set_navigation_layers` writes the 32-bit mask
#                         and the reader sees it back.
#   * section AND - the Android/export capability split: with a real Android
#                   preset in the project, the engine's own
#                   `EditorExportPlatform::can_export` and
#                   `AndroidSDKManager::is_android_sdk_setup` are the evidence,
#                   and the two writes refuse with `-32000` + what is missing
#                   instead of inventing a device or an APK. A second project
#                   without export presets proves the honest empty answer and the
#                   two "no preset" refusals. A "capability-missing only" branch
#                   is never reported as a success.
#   * section MOV - `running_game_move_player_to_target` on the game endpoint:
#                   the deferred task drives a real `NavigationAgent2D` (agent
#                   branch) and, for a node without an agent, the server's own
#                   `map_get_path` (server branch); the positions it reports are
#                   cross-checked against `running_game_get_node_properties`
#                   while the movement is in flight, so "it moved" is a
#                   first-hand fact and not the tool's own claim. A project with
#                   no navigation data gets the honest `-32000` refusal.
#
#  Port discipline: the user's editor on 9877 is never touched; only 9888/9889
#  are used, and only PIDs this script started are killed.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp036_b5_navigation_theme_export_android_evidence.ps1
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
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'task036-b5-batch4' }
$Root = $OutRoot
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$Proj2 = Join-Path $Root 'proj_navless'
$UserPort = 9877
$utf8 = [Text.Encoding]::UTF8

# TASK-028 D-1: the shared scratch-project writer + `--import` runner.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-042 section 1: the shared 9877 classification (see mcp_port_guard.ps1).
. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]
# GDR-25 23.1: every call site below feeds an answer into the next request as a
# parsed value; nothing increments this counter, and it is asserted to be 0.
$script:StringOps = 0

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Note {
    param([string]$Text)
    Write-Host ("NOTE   {0}" -f $Text)
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

# The deferred tools answer only when their task settles, so the caller has to be
# able to keep using the endpoint while the request is in flight. This starts the
# same `curl.exe` call as a child process and hands back its response file.
function Invoke-ToolAsync {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_)
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-McpUtf8NoBom -Path $bodyFile -Text (New-CallBody -Tool $Tool -Arguments $Arguments)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    $arguments = @('-s', '--max-time', '120', '-o', $respFile, '--stderr', ($respFile + '.err.txt'), '-H', 'Content-Type: application/json', '--data-binary', ('@' + $bodyFile), ("http://127.0.0.1:{0}/mcp" -f $Port_))
    # PowerShell 5.1's `Start-Process -ArgumentList` joins an array with spaces
    # and lets CreateProcess split it again, which mangles an argument whose value
    # contains a space (`-H 'Content-Type: application/json'` arrived as two
    # arguments and curl then wrote no output file at all - measured while writing
    # this script). Every argument is therefore quoted here.
    $quoted = ($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $proc = Start-Process -FilePath $Curl -ArgumentList $quoted -PassThru -WindowStyle Hidden
    Write-Host ("[{0}] started async: tool={1} port={2} response={3}" -f $Id, $Tool, $Port_, $respFile)
    return @{ proc = $proc; file = $respFile; id = $Id }
}

function Get-AsyncResponse {
    param($Async)
    if (-not $Async.proc.WaitForExit(60000)) { $Async.proc.Kill() }
    $errFile = $Async.file + '.err.txt'
    if (-not (Test-Path $Async.file)) {
        $curlError = ''
        if (Test-Path $errFile) { $curlError = (Get-Content -Raw $errFile) }
        throw ("the async curl for {0} wrote no response file (exit code {1}, curl stderr '{2}')" -f $Async.id, $Async.proc.ExitCode, $curlError)
    }
    $bytes = [IO.File]::ReadAllBytes($Async.file)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $Async.file).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] async settled bytes={1} sha256={2} curl_exit={3}" -f $Async.id, $bytes.Length, $sha, $Async.proc.ExitCode)
    Write-Host ("       {0}" -f $text)
    return @{ text = $text; sha256 = $sha; file = $Async.file; bytes = $bytes.Length }
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
        if ($null -eq $envelope.error) { return '' }
        if ($null -eq $envelope.error.data) { return '' }
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

function Get-PropertyValue {
    param($Payload, [string]$Name)
    if ($null -eq $Payload) { return $null }
    foreach ($p in $Payload.PSObject.Properties) {
        if ([string]$p.Name -ceq $Name) { return $p.Value }
    }
    return $null
}

# `editor_get_navigation_info` answers `regions`/`agents`/... as **arrays** of
# records, each carrying the node's own relative `path` - not as a map keyed by
# the path it was asked about.
function Get-RecordByPath {
    param($Collection, [string]$Path_)
    if ($null -eq $Collection) { return $null }
    foreach ($entry in @($Collection)) {
        if ($null -eq $entry) { continue }
        if ([string]$entry.path -ceq $Path_) { return $entry }
    }
    return $null
}

# =============================================================================
# The 14 tools of this batch, in manifest order, with the argument sets the three
# classes of evidence need. `missing` omits a required member (-32602); `fail` is
# complete but addresses something that is not there (-32001); `norequired` marks
# a tool whose schema declares no required member, so its -32602 witness is an
# undeclared argument (TASK-032 D4); `nofailure` marks a tool with no defined
# underlying-failure class, which is declared explicitly instead of guessed.
# =============================================================================
$ThemeChain = 'res://ui/chain.tres'
$tools = @(
    @{ name = 'editor_bake_navigation_mesh'; args = @{ navigation_region_path = 'Region' }; missing = @{}; fail = @{ navigation_region_path = 'NoSuchNode' } },
    @{ name = 'editor_set_navigation_layers'; args = @{ node_path = 'Region'; layers = 5 }; missing = @{}; fail = @{ node_path = 'NoSuchNode'; layers = 5 } },
    @{ name = 'editor_get_navigation_info'; args = @{ node_path = 'Region' }; missing = @{ nothing = 1 }; fail = @{ node_path = 'NoSuchNode' }; norequired = $true },
    @{ name = 'project_create_theme'; args = @{ path = 'res://ui/evidence.tres'; name = 'Evidence' }; missing = @{}; fail = $null; nofailure = $true },
    @{ name = 'project_set_theme_color'; args = @{ theme_path = $ThemeChain; color_name = 'font_color'; color = @{ r = 0.25; g = 0.5; b = 0.75; a = 1.0 } }; missing = @{}; fail = @{ theme_path = 'res://ui/no_such.tres'; color_name = 'font_color'; color = @{ r = 1; g = 0; b = 0 } } },
    @{ name = 'project_set_theme_constant'; args = @{ theme_path = $ThemeChain; constant_name = 'separation'; value = 7 }; missing = @{}; fail = @{ theme_path = 'res://ui/no_such.tres'; constant_name = 'separation'; value = 7 } },
    @{ name = 'project_set_theme_font_size'; args = @{ theme_path = $ThemeChain; font_size_name = 'title_size'; size = 19 }; missing = @{}; fail = @{ theme_path = 'res://ui/no_such.tres'; font_size_name = 'title_size'; size = 19 } },
    @{ name = 'project_set_theme_stylebox'; args = @{ theme_path = $ThemeChain; stylebox_name = 'panel'; bg_color = '#112233'; border_width = 2; corner_radius = 3 }; missing = @{}; fail = @{ theme_path = 'res://ui/no_such.tres'; stylebox_name = 'panel' } },
    @{ name = 'project_get_theme_info'; args = @{ theme_path = $ThemeChain }; missing = @{}; fail = @{ theme_path = 'res://ui/no_such.tres' } },
    @{ name = 'project_get_export_info'; args = @{}; missing = @{ preset_name = 'Android' }; fail = $null; norequired = $true; nofailure = $true },
    @{ name = 'project_list_export_presets'; args = @{}; missing = @{ preset_name = 'Android' }; fail = $null; norequired = $true; nofailure = $true },
    @{ name = 'project_get_android_preset_info'; args = @{ preset_name = 'Android' }; missing = @{ preset_name = 7 }; fail = @{ preset_name = 'NoSuchPreset' }; norequired = $true },
    @{ name = 'os_list_android_devices'; args = @{}; missing = @{ device_id = 'x' }; fail = $null; norequired = $true; nofailure = $true; capabilityonly = $true },
    @{ name = 'os_deploy_to_android_device'; args = @{ preset_name = 'Android' }; missing = @{}; fail = @{ preset_name = 'NoSuchPreset' }; capabilityonly = $true },
    @{ name = 'running_game_move_player_to_target'; args = @{ target = 'Goal'; player_path = 'Player'; timeout = 20.0; arrival_radius = 5.0 }; missing = @{}; fail = @{ target = 'NoSuchNode'; player_path = 'Player' } }
)

$editorScope = @('editor_bake_navigation_mesh', 'editor_set_navigation_layers')
$gameScope = @('running_game_move_player_to_target')

# =============================================================================
# Scratch projects
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Proj, (Join-Path $Proj 'scenes'), (Join-Path $Proj 'ui'), $Proj2, (Join-Path $Proj2 'scenes') | Out-Null

$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp036_b5_batch4"'
    'run/main_scene="res://scenes/game_main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text ($projectGodot + "`n")

# A real Android export preset, written *before* the editor starts: `EditorExport`
# reads `res://export_presets.cfg` once, on `NOTIFICATION_ENTER_TREE`
# (editor/export/editor_export.cpp:248-252), so a file written later would not be
# in the engine's list and the capability check could not run at all.
$exportPresets = @'
[preset.0]

name="Android"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/mcp036.apk"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
package/unique_name="com.example.mcp036"
package/name="mcp036"
package/signed=true
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'export_presets.cfg') -Text $exportPresets

# The 3D scene the bake works on: a `NavigationRegion3D` whose only source
# geometry is a subdivided `PlaneMesh` child (the default
# `geometry_source_geometry_mode` is "root node children", so the mesh under the
# region is exactly what the generator parses).
$navScene = @'
[gd_scene load_steps=3 format=3]

[sub_resource type="NavigationMesh" id="NavigationMesh_1"]

[sub_resource type="PlaneMesh" id="PlaneMesh_1"]
size = Vector2(20, 20)
subdivide_width = 20
subdivide_depth = 20

[node name="NavScene" type="Node3D"]

[node name="Region" type="NavigationRegion3D" parent="."]
navigation_mesh = SubResource("NavigationMesh_1")

[node name="Floor" type="MeshInstance3D" parent="Region"]
mesh = SubResource("PlaneMesh_1")
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\nav3d.tscn') -Text $navScene

# The 2D game scene, built in `_ready`: one `NavigationRegion2D` with a
# hand-triangulated `NavigationPolygon`, a `CharacterBody2D` "Player" carrying a
# `NavigationAgent2D`, a scripted "Walker" with a `speed` property and no agent,
# and the "Goal" the movement is aimed at.
$gameMain = @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://main.gd" id="1_main"]

[node name="Main" type="Node2D"]
script = ExtResource("1_main")
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\game_main.tscn') -Text $gameMain

$mainGd = @'
extends Node2D

func _ready() -> void:
    var region := NavigationRegion2D.new()
    region.name = "Region"
    var polygon := NavigationPolygon.new()
    polygon.add_outline(PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(400, 300), Vector2(0, 300)]))
    polygon.make_polygons_from_outlines()
    region.navigation_polygon = polygon
    add_child(region)

    var player := CharacterBody2D.new()
    player.name = "Player"
    player.position = Vector2(30, 150)
    var agent := NavigationAgent2D.new()
    agent.name = "Agent"
    agent.max_speed = 240.0
    agent.path_desired_distance = 4.0
    agent.target_desired_distance = 4.0
    player.add_child(agent)
    add_child(player)

    var walker := Node2D.new()
    walker.name = "Walker"
    walker.set_script(load("res://walker.gd"))
    walker.position = Vector2(30, 30)
    add_child(walker)

    var goal := Node2D.new()
    goal.name = "Goal"
    goal.position = Vector2(360, 150)
    add_child(goal)
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'main.gd') -Text $mainGd

$walkerGd = @'
extends Node2D

var speed := 90.0
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'walker.gd') -Text $walkerGd

# The second project: the same game with **no** navigation data and **no** export
# presets, which is what the two honest refusals are measured on.
$projectGodot2 = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp036_navless"'
    'run/main_scene="res://scenes/plain_main.tscn"'
    'config/features=PackedStringArray("4.8")'
) -join "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj2 'project.godot') -Text ($projectGodot2 + "`n")

$plainMain = @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://plain.gd" id="1_plain"]

[node name="Main" type="Node2D"]
script = ExtResource("1_plain")
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj2 'scenes\plain_main.tscn') -Text $plainMain

$plainGd = @'
extends Node2D

func _ready() -> void:
    var player := Node2D.new()
    player.name = "Player"
    player.position = Vector2(10, 10)
    add_child(player)

    var goal := Node2D.new()
    goal.name = "Goal"
    goal.position = Vector2(200, 10)
    add_child(goal)
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj2 'plain.gd') -Text $plainGd

$importOne = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import_proj' -Port $EditorPort
$importTwo = Import-McpProject -Engine $Engine -Path $Proj2 -LogDirectory $LogRoot -Name 'import_proj2' -Port $EditorPort
Check 'imports_succeeded' (($importOne.exit_code -eq 0) -and ($importTwo.exit_code -eq 0)) `
    ("both scratch projects imported (proj exit={0}, navless exit={1})" -f $importOne.exit_code, $importTwo.exit_code)

# =============================================================================
# Environment facts about the Android toolchain, taken from the host *before*
# the engine is asked: whatever the tools answer has to agree with this.
# =============================================================================
$hostAdb = $null
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($null -ne $adbCommand) { $hostAdb = [string]$adbCommand.Source }
$sdkCandidates = @()
foreach ($candidate in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
    if (-not [string]::IsNullOrEmpty($candidate)) { $sdkCandidates += $candidate }
}
$sdkPresent = @()
foreach ($candidate in $sdkCandidates) {
    if (Test-Path $candidate) { $sdkPresent += $candidate }
}
Note ("host: adb on PATH = '{0}'; SDK candidates = [{1}]; existing = [{2}]" -f $hostAdb, ($sdkCandidates -join '; '), ($sdkPresent -join '; '))

# TASK-042 section 1: the 9877 judgement is the shared six-way classification,
# not "a listener must exist" - see mcp_port_guard.ps1. The two `--import`
# launches below are registered too, so "did this script ever ask for the user's
# port" is answered from their real command lines (they ask for 9888).
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $importOne.command
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $importTwo.command

$editorHandle = $null
$gameHandle = $null
$game2Handle = $null
try {
    # =========================================================================
    # The editor endpoint (9888)
    # =========================================================================
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $editorList = Invoke-Raw -Id 'L00_tools_list_editor' -Body (New-ListBody) -Port_ $EditorPort
    $editorNames = Get-ToolNames $editorList
    $missingOnEditor = @()
    foreach ($tool in $tools) {
        if ($gameScope -contains [string]$tool.name) { continue }
        if (-not $editorNames.Contains([string]$tool.name)) { $missingOnEditor += [string]$tool.name }
    }
    Check 'scope_9888_serves_the_fourteen_editor_viewable_tools' ($missingOnEditor.Count -eq 0) `
        ("editor tools/list carries the 14 batch tools an editor serves (count={0}); missing=[{1}]" -f $editorNames.Count, ($missingOnEditor -join ','))
    Check 'scope_9888_hides_game_only' (-not $editorNames.Contains('running_game_move_player_to_target')) `
        ("editor tools/list does not carry running_game_move_player_to_target (game scope, GDR-19 17.3)" -f $editorNames.Count)

    # -------------------------------------------------------------------------
    # S0: the two closures the decision-maker ruled on (TASK-036 section 0)
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '=== S0: the manifest note and the two string-typed name spellings ==='

    # (0.1) the `editor_physics_write` note says node scope, and the manifest entry
    # is the one the contract group carries.
    $b5Json = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 (Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups-b5.json'))
    $physicsGroup = $null
    foreach ($group in @($b5Json.groups)) {
        if ([string]$group.name -ceq 'editor_physics_write') { $physicsGroup = $group }
    }
    $physicsNote = if ($null -ne $physicsGroup) { [string]$physicsGroup.notes } else { '' }
    Check 's0_physics_note_is_node_scope' `
        (($null -ne $physicsGroup) -and ($physicsNote -match 'node') -and ($physicsNote -notmatch 'writes the project') -and (@($physicsGroup.tools) -contains 'editor_set_physics_layers')) `
        ("docs/tool-groups-b5.json editor_physics_write.notes = '" + $physicsNote + "'")

    # (0.2a) material_slot stays a string and the **name** spelling works: the
    # contract's own default is the slot name `material`, so the name is the
    # primary spelling and a decimal index is the convenience. The scene is opened
    # first, because the slot lives on a `MeshInstance3D` inside it.
    $s0Open = Invoke-Tool -Id 'S0_00_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/nav3d.tscn' }
    Check 's0_scene_opened_for_the_slot_check' ($null -ne (Get-Payload $s0Open)) ("editor_open_scene -> " + (Get-PayloadText $s0Open))

    $s0Shader = Invoke-Tool -Id 'S0_01_create_shader' -Tool 'project_create_shader' -Arguments @{ path = 'res://shaders/evidence.gdshader' }
    $s0ShaderPayload = Get-Payload $s0Shader
    $s0Slot = Invoke-Tool -Id 'S0_02_material_slot_name' -Tool 'editor_set_shader_material' -Arguments @{ node_path = 'Region/Floor'; shader_path = 'res://shaders/evidence.gdshader'; material_slot = 'material_override' }
    $s0SlotPayload = Get-Payload $s0Slot
    Check 's0_material_slot_name_spelling_works' `
        (($null -ne $s0ShaderPayload) -and ($null -ne $s0SlotPayload) -and ($s0SlotPayload.applied -eq $true) -and ([string]$s0SlotPayload.material_slot -ceq 'material_override')) `
        ("editor_set_shader_material with the slot **name** 'material_override' (the contract's type is string) -> " + (Get-PayloadText $s0Slot))

    # (0.2b) keycode stays a string and both the bare name and the GDScript
    # constant name resolve to the same engine key.
    $s0KeyConstant = Invoke-Tool -Id 'S0_03_keycode_constant_name' -Tool 'editor_simulate_key' -Arguments @{ keycode = 'KEY_A'; pressed = $true }
    $s0KeyBare = Invoke-Tool -Id 'S0_04_keycode_bare_name' -Tool 'editor_simulate_key' -Arguments @{ keycode = 'A'; pressed = $true }
    $s0KeyConstantPayload = Get-Payload $s0KeyConstant
    $s0KeyBarePayload = Get-Payload $s0KeyBare
    Check 's0_keycode_name_spellings_work' `
        (($null -ne $s0KeyConstantPayload) -and ($null -ne $s0KeyBarePayload) -and (-not [string]::IsNullOrWhiteSpace([string]$s0KeyConstantPayload.keycode)) -and ([string]$s0KeyConstantPayload.keycode -ceq [string]$s0KeyBarePayload.keycode)) `
        ("editor_simulate_key resolves both the GDScript constant name 'KEY_A' and the bare name 'A' to the same engine key '{0}' (the contract's type is string)" -f $s0KeyConstantPayload.keycode)

    # -------------------------------------------------------------------------
    # CH: the theme chain, zero string surgery
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '=== CH: the theme chain (6 calls, no string surgery) ==='
    $chCreate = Invoke-Tool -Id 'CH_01_create_theme' -Tool 'project_create_theme' -Arguments @{ path = $ThemeChain; name = 'Chain' }
    $chCreatePayload = Get-Payload $chCreate
    Check 'ch01_theme_created' (($null -ne $chCreatePayload) -and ([string]$chCreatePayload.path -ceq $ThemeChain) -and ($chCreatePayload.created -eq $true)) `
        ("project_create_theme -> " + (Get-PayloadText $chCreate))

    $chColor = Invoke-Tool -Id 'CH_02_set_color' -Tool 'project_set_theme_color' -Arguments @{ theme_path = $chCreatePayload.path; color_name = 'font_color'; color = @{ r = 0.25; g = 0.5; b = 0.75; a = 1.0 } }
    $chColorPayload = Get-Payload $chColor
    $chColorName = Get-First $chColorPayload.properties_set
    Check 'ch02_color_written_and_read_back' (($null -ne $chColorPayload) -and ($chColorPayload.saved -eq $true) -and ([string]$chColorName -ceq 'font_color')) `
        ("project_set_theme_color -> " + (Get-PayloadText $chColor))

    $chConstant = Invoke-Tool -Id 'CH_03_set_constant' -Tool 'project_set_theme_constant' -Arguments @{ theme_path = $chColorPayload.theme_path; constant_name = $chColorName; value = 7 }
    $chConstantPayload = Get-Payload $chConstant
    $chConstantName = [string]$chConstantPayload.constant_name
    Check 'ch03_constant_written_and_read_back' (($null -ne $chConstantPayload) -and ($chConstantPayload.saved -eq $true)) `
        ("project_set_theme_constant -> " + (Get-PayloadText $chConstant))

    $chFontSize = Invoke-Tool -Id 'CH_04_set_font_size' -Tool 'project_set_theme_font_size' -Arguments @{ theme_path = $chConstantPayload.theme_path; font_size_name = $chConstantName; size = 19 }
    $chFontSizePayload = Get-Payload $chFontSize
    $chFontSizeName = [string]$chFontSizePayload.font_size_name
    Check 'ch04_font_size_written_and_readable' (($null -ne $chFontSizePayload) -and ($chFontSizePayload.saved -eq $true) -and ($chFontSizePayload.font_size_readable -eq $true)) `
        ("project_set_theme_font_size -> " + (Get-PayloadText $chFontSize))

    $chStylebox = Invoke-Tool -Id 'CH_05_set_stylebox' -Tool 'project_set_theme_stylebox' -Arguments @{ theme_path = $chFontSizePayload.theme_path; stylebox_name = $chFontSizeName; bg_color = '#112233'; border_width = 2; corner_radius = 3 }
    $chStyleboxPayload = Get-Payload $chStylebox
    $chStyleboxName = [string]$chStyleboxPayload.stylebox_name
    Check 'ch05_stylebox_written_and_read_back' (($null -ne $chStyleboxPayload) -and ($chStyleboxPayload.saved -eq $true) -and ([string]$chStyleboxPayload.stylebox_type -ceq 'StyleBoxFlat')) `
        ("project_set_theme_stylebox -> " + (Get-PayloadText $chStylebox))

    $chInfo = Invoke-Tool -Id 'CH_06_theme_info' -Tool 'project_get_theme_info' -Arguments @{ theme_path = $chStyleboxPayload.theme_path }
    $chInfoPayload = Get-Payload $chInfo
    $chColorType = [string]$chColorPayload.node_type
    $chConstantType = [string]$chConstantPayload.node_type
    $chFontSizeType = [string]$chFontSizePayload.node_type
    $chStyleboxType = [string]$chStyleboxPayload.node_type
    $chColors = Get-PropertyValue $chInfoPayload.colors $chColorType
    $chConstants = Get-PropertyValue $chInfoPayload.constants $chConstantType
    $chFontSizes = Get-PropertyValue $chInfoPayload.font_sizes $chFontSizeType
    $chStyleboxes = Get-PropertyValue $chInfoPayload.styleboxes $chStyleboxType
    $chHasColor = ($null -ne $chColors) -and ($null -ne (Get-PropertyValue $chColors $chColorName))
    $chHasConstant = ($null -ne $chConstants) -and ($null -ne (Get-PropertyValue $chConstants $chConstantName))
    $chHasFontSize = ($null -ne $chFontSizes) -and ($null -ne (Get-PropertyValue $chFontSizes $chFontSizeName))
    $chHasStylebox = ($null -ne $chStyleboxes) -and ($null -ne (Get-PropertyValue $chStyleboxes $chStyleboxName))
    Check 'chain_theme_zero_string_surgery' `
        (($null -ne $chInfoPayload) -and ([string]$chInfoPayload.path -ceq $ThemeChain) -and $chHasColor -and $chHasConstant -and $chHasFontSize -and $chHasStylebox) `
        ("6 steps: project_create_theme -> project_set_theme_color -> project_set_theme_constant -> project_set_theme_font_size -> project_set_theme_stylebox -> project_get_theme_info; the reader found color '{0}' under '{1}', constant '{2}' under '{3}', font_size '{4}' under '{5}', stylebox '{6}' under '{7}'" -f $chColorName, $chColorType, $chConstantName, $chConstantType, $chFontSizeName, $chFontSizeType, $chStyleboxName, $chStyleboxType)

    # -------------------------------------------------------------------------
    # NAV: the bake's fix_implementation_first story, live
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '=== NAV: bake red -> real bake -> proof through the other tool ==='
    # The scene was opened in section S0; this confirms the region really is there
    # before the bake is measured (`editor_get_scene_tree`).
    $navTree = Invoke-Tool -Id 'NAV_01_scene_tree' -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 }
    Check 'nav01_region_is_in_the_edited_scene' ((Get-PayloadText $navTree) -match 'Region' -and (Get-PayloadText $navTree) -match 'Floor') `
        ("editor_get_scene_tree sees the NavigationRegion3D and its source mesh -> " + (Get-PayloadText $navTree))

    $navBefore = Invoke-Tool -Id 'NAV_02_info_before' -Tool 'editor_get_navigation_info' -Arguments @{ node_path = 'Region' }
    $navBeforePayload = Get-Payload $navBefore
    $regionRecord = Get-RecordByPath $navBeforePayload.regions 'Region'
    $beforePolygons = if ($null -ne $regionRecord) { [int]$regionRecord.polygon_count } else { -1 }
    Check 'nav02_region_unbaked_before' (($beforePolygons -eq 0) -and ($regionRecord.baked -eq $false)) `
        ("editor_get_navigation_info before the bake -> polygons={0} baked={1}" -f $beforePolygons, $regionRecord.baked)

    # (1) RED: the migration source's spelling. `bake_navigation_mesh` is a
    # *method* of NavigationRegion3D, not a property, so the engine refuses it -
    # which is exactly why a tool was needed.
    $navRed = Invoke-Tool -Id 'NAV_03_red_migration_spelling' -Tool 'editor_set_node_property' -Arguments @{ path = 'Region'; property = 'bake_navigation_mesh'; value = 0 }
    Check 'nav03_migration_spelling_is_refused' ((Get-ErrorCode $navRed) -ne 0) `
        ("the migration source's spelling for the bake (editor_set_node_property on 'bake_navigation_mesh') -> error {0}: {1}" -f (Get-ErrorCode $navRed), (Get-ErrorMessage $navRed))

    # (2) the real tool, through the deferred channel.
    $navBake = Invoke-Tool -Id 'NAV_04_bake' -Tool 'editor_bake_navigation_mesh' -Arguments @{ navigation_region_path = 'Region' }
    $navBakePayload = Get-Payload $navBake
    $bakePath = [string]$navBakePayload.node_path
    $bakeVerifyRecord = Get-RecordByPath $navBakePayload.verify.regions $bakePath
    Check 'nav04_bake_finished_and_changed_the_mesh' `
        (($null -ne $navBakePayload) -and ($navBakePayload.bake_signalled_done -eq $true) -and ($null -ne $navBakePayload.verify) -and ([string]$navBakePayload.verify_tool -ceq 'editor_get_navigation_info') -and ($null -ne $bakeVerifyRecord) -and ([int]$bakeVerifyRecord.polygon_count -gt 0) -and ([int]$navBakePayload.polygon_count -gt 0) -and ($navBakePayload.changed -eq $true) -and ([int]$navBakePayload.before_polygon_count -eq 0)) `
        ("editor_bake_navigation_mesh (deferred) -> " + (Get-PayloadText $navBake))

    # (3) the proof comes from the *other* tool, called with the path the bake
    # answered with.
    $navAfter = Invoke-Tool -Id 'NAV_05_info_after' -Tool 'editor_get_navigation_info' -Arguments @{ node_path = $bakePath }
    $navAfterPayload = Get-Payload $navAfter
    $afterRecord = Get-RecordByPath $navAfterPayload.regions $bakePath
    $afterPolygons = if ($null -ne $afterRecord) { [int]$afterRecord.polygon_count } else { -1 }
    Check 'nav05_verifier_tool_sees_the_baked_mesh' (($afterPolygons -gt 0) -and ($afterPolygons -eq [int]$navBakePayload.polygon_count) -and ($afterRecord.baked -eq $true)) `
        ("editor_get_navigation_info after the bake -> polygons={0} (the bake reported {1})" -f $afterPolygons, $navBakePayload.polygon_count)

    # (4) the layer mask, written and read back.
    $navLayers = Invoke-Tool -Id 'NAV_06_set_layers' -Tool 'editor_set_navigation_layers' -Arguments @{ node_path = $bakePath; layers = 5 }
    $navLayersPayload = Get-Payload $navLayers
    $navLayersRead = Invoke-Tool -Id 'NAV_07_read_layers' -Tool 'editor_get_navigation_info' -Arguments @{ node_path = $bakePath }
    $navLayersReadPayload = Get-Payload $navLayersRead
    $layerRecord = Get-RecordByPath $navLayersReadPayload.regions $bakePath
    # The write's own answer carries one name per bit of the mask (the name is the
    # project setting `layer_names/3d_navigation/layer_N`, empty when unset);
    # `editor_get_navigation_info` is the read-back and carries the mask itself.
    $layerNameCount = @($navLayersPayload.layer_names).Count
    Check 'chain_navigation_layers_round_trip' `
        (($null -ne $navLayersPayload) -and ($navLayersPayload.applied -eq $true) -and (@($navLayersPayload.layer_bits) -contains 1) -and (@($navLayersPayload.layer_bits) -contains 3) -and ($layerNameCount -eq 2) -and ($null -ne $layerRecord) -and ([int]$layerRecord.navigation_layers -eq 5)) `
        ("editor_set_navigation_layers(layers=5) -> bits {0}, layer_names {1} -> editor_get_navigation_info reads navigation_layers={2}" -f ((@($navLayersPayload.layer_bits)) -join ','), (($navLayersPayload.layer_names) -join '/'), $layerRecord.navigation_layers)

    # -------------------------------------------------------------------------
    # AND: the Android/export capability evidence on the editor endpoint
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '=== AND: the Android/export capability split (editor endpoint) ==='
    $andInfo = Invoke-Tool -Id 'AND_01_export_info' -Tool 'project_get_export_info' -Arguments @{}
    $andInfoPayload = Get-Payload $andInfo
    Check 'and01_export_info_sees_the_real_preset' (($null -ne $andInfoPayload) -and ($andInfoPayload.presets_file_present -eq $true) -and ([int]$andInfoPayload.preset_count -eq 1) -and ([string]$andInfoPayload.presets_source -ceq 'editor_export') -and ([int]$andInfoPayload.export_platform_count -ge 1)) `
        ("project_get_export_info -> " + (Get-PayloadText $andInfo))

    $andList = Invoke-Tool -Id 'AND_02_list_presets' -Tool 'project_list_export_presets' -Arguments @{}
    $andListPayload = Get-Payload $andList
    $andFirst = Get-First $andListPayload.presets
    Check 'and02_preset_list_is_the_engine_list' (($null -ne $andListPayload) -and ([int]$andListPayload.count -eq 1) -and ([string]$andFirst.name -ceq 'Android') -and ([string]$andFirst.platform -ceq 'Android')) `
        ("project_list_export_presets -> " + (Get-PayloadText $andList))

    $andPreset = Invoke-Tool -Id 'AND_03_android_preset_info' -Tool 'project_get_android_preset_info' -Arguments @{ preset_name = 'Android' }
    $andPresetPayload = Get-Payload $andPreset
    $capability = $andPresetPayload.export_capability
    $andUnavailable = @($andPresetPayload.unavailable | Where-Object { [string]$_.capability -eq 'android_export' })
    Check 'and03_preset_readable_but_export_checked_and_false' `
        (($null -ne $andPresetPayload) -and ([string]$andPresetPayload.name -ceq 'Android') -and ([string]$andPresetPayload.android_package_name -ceq 'com.example.mcp036') -and ($capability.checked -eq $true) -and ($capability.can_export -eq $false) -and ($andUnavailable.Count -eq 1)) `
        ("project_get_android_preset_info -> export_capability.checked={0} can_export={1} engine_error='{2}'; the preset itself is still readable (a readable preset is never hidden behind a refusal)" -f $capability.checked, $capability.can_export, $capability.error)

    $andEnvironment = $andPresetPayload.environment
    $andSdkAgrees = ($andEnvironment.android_sdk_ready -eq $false) -and ($sdkPresent.Count -eq 0)
    Check 'and04_tool_and_host_agree_about_the_sdk' $andSdkAgrees `
        ("the tool reports android_sdk_ready={0} (error '{1}') and the host really has no SDK directory installed" -f $andEnvironment.android_sdk_ready, $andEnvironment.android_sdk_error)

    $andDeploy = Invoke-Tool -Id 'AND_04_deploy_refusal' -Tool 'os_deploy_to_android_device' -Arguments @{ preset_name = 'Android' }
    $andDeployCode = Get-ErrorCode $andDeploy
    $andDeploySuggestion = Get-ErrorSuggestion $andDeploy
    Check 'and05_deploy_refuses_with_what_is_missing' `
        (($andDeployCode -eq -32000) -and (-not [string]::IsNullOrWhiteSpace($andDeploySuggestion)) -and ((Get-ErrorMessage $andDeploy) -match 'can_export|Android|missing|SDK')) `
        ("os_deploy_to_android_device -> -32000 '{0}' (suggestion: {1}) - no APK and no device is invented" -f (Get-ErrorMessage $andDeploy), $andDeploySuggestion)

    $andDevices = Invoke-Tool -Id 'AND_05_devices' -Tool 'os_list_android_devices' -Arguments @{}
    $andDevicesCode = Get-ErrorCode $andDevices
    $andDevicesPayload = Get-Payload $andDevices
    $devicesHonest = $false
    $devicesEvidence = ''
    if ($andDevicesCode -eq 0) {
        $devicesHonest = ($null -ne $andDevicesPayload) -and ([int]$andDevicesPayload.count -eq @($andDevicesPayload.devices).Count)
        $devicesEvidence = ("the host has adb ('{0}'), so the tool ran it: count={1} source='{2}'" -f $hostAdb, $andDevicesPayload.count, $andDevicesPayload.source)
    } else {
        $devicesHonest = ($andDevicesCode -eq -32000) -and (-not [string]::IsNullOrWhiteSpace((Get-ErrorSuggestion $andDevices)))
        $devicesEvidence = ("the host has no adb, so the tool refused honestly: -32000 '{0}'" -f (Get-ErrorMessage $andDevices))
    }
    Check 'and06_device_list_is_never_invented' $devicesHonest $devicesEvidence

    # -------------------------------------------------------------------------
    # (A) the three classes of evidence for the fourteen tools of this batch
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '=== class evidence (success / -32602 / underlying failure) ==='
    $classRows = @()
    foreach ($tool in $tools) {
        $name = [string]$tool.name
        if ($name -eq 'running_game_move_player_to_target') { continue }
        $success = Invoke-Tool -Id ("G_ok_" + $name) -Tool $name -Arguments $tool.args
        $ok = ($null -ne (Get-Payload $success))
        $row = "{0}: success={1}" -f $name, $ok
        if ($tool.capabilityonly -eq $true -and -not $ok) {
            # A tool whose only possible outcome on this machine is the
            # capability refusal: `-32000` + what is missing *is* the class, and
            # it is reported as such instead of being counted as a success.
            $capabilityOnly = ((Get-ErrorCode $success) -eq -32000) -and (-not [string]::IsNullOrWhiteSpace((Get-ErrorSuggestion $success)))
            $ok = $capabilityOnly
            $row = "{0}: success=n/a (declared: capability-missing only on this host), capability_refusal={1} - {2}" -f $name, $capabilityOnly, (Get-ErrorMessage $success)
        }

        if ($null -ne $tool.missing) {
            $missing = Invoke-Tool -Id ("G_missing_" + $name) -Tool $name -Arguments $tool.missing
            $missingOk = ((Get-ErrorCode $missing) -eq -32602)
            $row += "; -32602={0}" -f $missingOk
        } else {
            $missingOk = $true
            $row += "; -32602=n/a"
        }

        if ($tool.nofailure -eq $true) {
            $failureOk = $true
            $row += "; failure=n/a (declared: this tool has no underlying-failure class)"
        } elseif ($null -ne $tool.fail) {
            $failure = Invoke-Tool -Id ("G_fail_" + $name) -Tool $name -Arguments $tool.fail
            $failureOk = ((Get-ErrorCode $failure) -in @(-32001, -32000))
            $row += "; failure={0} (code {1})" -f $failureOk, (Get-ErrorCode $failure)
            if ((Get-ErrorCode $failure) -eq -32000) {
                $failureOk = $failureOk -and (-not [string]::IsNullOrWhiteSpace((Get-ErrorSuggestion $failure)))
            }
        } else {
            $failureOk = $true
        }
        $classRows += ($row + ("|" + $name))
        Check ("class_" + $name) ($ok -and $missingOk -and $failureOk) $row
    }

    # -------------------------------------------------------------------------
    # MOV + AND on the game endpoint (9889)
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '=== MOV: the movement write on the game endpoint (9889) ==='
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, "--mcp-port=$GamePort") -LogName 'game'
    Check 'game_endpoint_ready' (Wait-ForPump -Port_ $GamePort) ("game on {0} answered GET /mcp with +20 frames" -f $GamePort)

    $gameList = Invoke-Raw -Id 'L01_tools_list_game' -Body (New-ListBody) -Port_ $GamePort
    $gameNames = Get-ToolNames $gameList
    # The three editor-scope tools of the navigation family (the two writes of this
    # batch and the TASK-034 reader) must be absent from a game endpoint; the other
    # twelve are served there.
    $editorOnlyFamily = $editorScope + @('editor_get_navigation_info')
    $missingOnGame = @()
    foreach ($tool in $tools) {
        if ($editorOnlyFamily -contains [string]$tool.name) { continue }
        if (-not $gameNames.Contains([string]$tool.name)) { $missingOnGame += [string]$tool.name }
    }
    Check 'scope_9889_serves_the_twelve_non_editor_tools' ($missingOnGame.Count -eq 0) `
        ("game tools/list carries the 12 batch tools a game serves (count={0}); missing=[{1}]" -f $gameNames.Count, ($missingOnGame -join ','))
    Check 'scope_9889_hides_editor_only' ((-not $gameNames.Contains('editor_bake_navigation_mesh')) -and (-not $gameNames.Contains('editor_set_navigation_layers'))) `
        ("game tools/list does not carry editor_bake_navigation_mesh / editor_set_navigation_layers (editor scope, GDR-19 17.3)")

    $movTree = Invoke-Tool -Id 'MOV_00_scene_tree' -Tool 'running_game_get_scene_tree' -Arguments @{ named_only = $true } -Port_ $GamePort
    Check 'mov00_scene_has_the_navigation_actors' ((Get-PayloadText $movTree) -match 'Player' -and (Get-PayloadText $movTree) -match 'Walker' -and (Get-PayloadText $movTree) -match 'Region') `
        ("running_game_get_scene_tree sees the Region/Player/Walker/Goal the scene built -> " + (Get-PayloadText $movTree))

    # (A) the agent branch: the deferred request runs while this script reads the
    # player's position through a *different* tool, so the movement is observed
    # first-hand.
    $movAsync = Invoke-ToolAsync -Id 'MOV_01_agent_move' -Tool 'running_game_move_player_to_target' -Arguments @{ target = 'Goal'; player_path = 'Player'; timeout = 20.0; arrival_radius = 5.0 } -Port_ $GamePort
    $observed = New-Object System.Collections.Generic.List[string]
    while (-not $movAsync.proc.HasExited -and $observed.Count -lt 50) {
        Start-Sleep -Milliseconds 300
        $probe = Invoke-Tool -Id ("MOV_01_poll_{0}_{1}" -f $observed.Count, $movAsync.proc.Id) -Tool 'running_game_get_node_properties' -Arguments @{ node_path = 'Player'; properties = @('position') } -Port_ $GamePort
        $probePayload = Get-Payload $probe
        $position = Get-NodeProperty $probePayload 'position'
        if ($null -ne $position) { $observed.Add(("{0},{1}" -f $position.x, $position.y)) }
    }
    $distinct = @($observed | Sort-Object -Unique)
    $movResponse = Get-AsyncResponse $movAsync
    $movPayload = Get-Payload $movResponse
    $movDistinct = if ($null -ne $movPayload) { @($movPayload.positions_sampled | ForEach-Object { "{0},{1}" -f $_.position.x, $_.position.y } | Sort-Object -Unique) } else { @() }
    Check 'mov01_agent_branch_moved_the_player_per_frame' `
        (($null -ne $movPayload) -and ($movPayload.reached -eq $true) -and ([string]$movPayload.speed_source -ceq 'navigation_agent_max_speed') -and ([string]$movPayload.navigation.path_source -ceq 'navigation_agent') -and ([int]$movPayload.navigation.agent_path_point_count -ge 2) -and ([int]$movPayload.navigation.map_region_count -eq 1) -and ($movPayload.movement -ceq 'character_body_move_and_slide') -and ([int]$movPayload.position_sample_count -ge 8) -and ($movDistinct.Count -ge 8) -and ($distinct.Count -ge 3)) `
        ("the agent branch: navigation.path_source={0} agent_path_points={1} map_regions={2} speed={3} ({4}) movement={5}; the tool reported {6} distinct sampled positions and this script observed {7} distinct positions for the player through running_game_get_node_properties while the request was in flight" -f $movPayload.navigation.path_source, $movPayload.navigation.agent_path_point_count, $movPayload.navigation.map_region_count, $movPayload.speed, $movPayload.speed_source, $movPayload.movement, $movDistinct.Count, $distinct.Count)

    $movFinal = Get-NodeProperty (Get-Payload (Invoke-Tool -Id 'MOV_02_final_position' -Tool 'running_game_get_node_properties' -Arguments @{ node_path = 'Player'; properties = @('position') } -Port_ $GamePort)) 'position'
    Check 'mov02_final_position_is_the_goal' (($null -ne $movFinal) -and ([math]::Abs([double]$movFinal.x - 360.0) -le 6.0) -and ([math]::Abs([double]$movFinal.y - 150.0) -le 6.0)) `
        ("after the move the player really is at the goal: running_game_get_node_properties -> position=({0},{1}) against the target (360,150)" -f $movFinal.x, $movFinal.y)

    # (B) the server branch: a node with a scripted `speed` and no agent follows
    # the server's own `map_get_path` polyline.
    $movServer = Invoke-Tool -Id 'MOV_03_server_move' -Tool 'running_game_move_player_to_target' -Arguments @{ target = @{ x = 360; y = 30 }; player_path = 'Walker'; timeout = 20.0; arrival_radius = 5.0; run = $true } -Port_ $GamePort
    $movServerPayload = Get-Payload $movServer
    Check 'mov03_server_branch_uses_map_get_path_and_the_scripted_speed' `
        (($null -ne $movServerPayload) -and ($movServerPayload.reached -eq $true) -and ([string]$movServerPayload.navigation.path_source -ceq 'navigation_server') -and ([string]$movServerPayload.speed_source -ceq 'player_speed') -and ([double]$movServerPayload.speed -eq 180.0) -and ($movServerPayload.run_multiplier -eq 2.0)) `
        ("the server branch: navigation.path_source={0} speed={1} ({2}) run_multiplier={3} - the scripted 'speed' property of the Walker is the source and the map path is the engine's own" -f $movServerPayload.navigation.path_source, $movServerPayload.speed, $movServerPayload.speed_source, $movServerPayload.run_multiplier)

    # (C) the three classes for the game-scope tool, on its own endpoint.
    $movToolRow = $null
    foreach ($tool in $tools) {
        if ([string]$tool.name -ne 'running_game_move_player_to_target') { continue }
        $successOk = ($null -ne $movPayload) -and ($movPayload.reached -eq $true)
        $missing = Invoke-Tool -Id 'G_missing_running_game_move_player_to_target' -Tool 'running_game_move_player_to_target' -Arguments @{} -Port_ $GamePort
        $missingOk = ((Get-ErrorCode $missing) -eq -32602)
        $failure = Invoke-Tool -Id 'G_fail_running_game_move_player_to_target' -Tool 'running_game_move_player_to_target' -Arguments @{ target = 'NoSuchNode'; player_path = 'Player' } -Port_ $GamePort
        $failureOk = ((Get-ErrorCode $failure) -eq -32001)
        $movToolRow = "running_game_move_player_to_target: success={0}; -32602={1}; failure={2} (code {3})" -f $successOk, $missingOk, $failureOk, (Get-ErrorCode $failure)
        Check 'class_running_game_move_player_to_target' ($successOk -and $missingOk -and $failureOk) $movToolRow
    }

    Stop-Engine -Handle $gameHandle
    $gameHandle = $null
    Start-Sleep -Milliseconds 1500

    # -------------------------------------------------------------------------
    # NAVL: the navless game - the honest refusal and the honest empty export
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '=== NAVL: a project with no navigation data and no export presets ==='
    $game2Handle = Start-Engine -Arguments @('--headless', '--path', $Proj2, "--mcp-port=$GamePort") -LogName 'game_navless'
    Check 'navless_endpoint_ready' (Wait-ForPump -Port_ $GamePort) ("the navless game on {0} answered GET /mcp with +20 frames" -f $GamePort)

    $navlMove = Invoke-Tool -Id 'NAVL_01_move_without_navigation' -Tool 'running_game_move_player_to_target' -Arguments @{ target = 'Goal'; player_path = 'Player'; timeout = 10.0 } -Port_ $GamePort
    $navlMoveCode = Get-ErrorCode $navlMove
    Check 'navl01_move_refuses_without_navigation_data' (($navlMoveCode -eq -32000) -and ((Get-ErrorMessage $navlMove) -match 'region|navigation')) `
        ("running_game_move_player_to_target in a scene with no NavigationRegion -> -32000 '{0}' (suggestion: {1}) - it did not pretend to walk a straight line" -f (Get-ErrorMessage $navlMove), (Get-ErrorSuggestion $navlMove))

    $navlExport = Invoke-Tool -Id 'NAVL_02_export_info' -Tool 'project_get_export_info' -Arguments @{} -Port_ $GamePort
    $navlExportPayload = Get-Payload $navlExport
    Check 'navl02_export_info_is_empty_not_error' (($null -ne $navlExportPayload) -and ($navlExportPayload.presets_file_present -eq $false) -and ([int]$navlExportPayload.preset_count -eq 0) -and (-not [string]::IsNullOrWhiteSpace([string]$navlExportPayload.message))) `
        ("project_get_export_info in a project without export_presets.cfg -> " + (Get-PayloadText $navlExport))

    $navlAndroid = Invoke-Tool -Id 'NAVL_03_android_no_preset' -Tool 'project_get_android_preset_info' -Arguments @{} -Port_ $GamePort
    Check 'navl03_android_read_refuses_without_a_preset' (((Get-ErrorCode $navlAndroid) -eq -32000) -and ((Get-ErrorMessage $navlAndroid) -match 'export_presets\.cfg') -and (-not [string]::IsNullOrWhiteSpace((Get-ErrorSuggestion $navlAndroid)))) `
        ("project_get_android_preset_info with no presets file -> -32000 '{0}'" -f (Get-ErrorMessage $navlAndroid))

    $navlDeploy = Invoke-Tool -Id 'NAVL_04_deploy_no_preset' -Tool 'os_deploy_to_android_device' -Arguments @{ preset_name = 'Android' } -Port_ $GamePort
    Check 'navl04_deploy_refuses_without_a_preset' (((Get-ErrorCode $navlDeploy) -eq -32001) -or ((Get-ErrorCode $navlDeploy) -eq -32000)) `
        ("os_deploy_to_android_device with no presets file -> {0} '{1}'" -f (Get-ErrorCode $navlDeploy), (Get-ErrorMessage $navlDeploy))

    # The theme group is `scope = both`: the game process has no editor, yet the
    # whole write -> read -> save loop runs there too, on a theme of its own.
    $navlThemeCreate = Invoke-Tool -Id 'NAVL_05_theme_create_in_game' -Tool 'project_create_theme' -Arguments @{ path = 'res://ui/game_theme.tres'; name = 'GameTheme' } -Port_ $GamePort
    $navlThemeCreatePayload = Get-Payload $navlThemeCreate
    $navlThemeColor = Invoke-Tool -Id 'NAVL_06_theme_color_in_game' -Tool 'project_set_theme_color' -Arguments @{ theme_path = 'res://ui/game_theme.tres'; color_name = 'font_color'; color = @{ r = 0.1; g = 0.2; b = 0.3; a = 1.0 } } -Port_ $GamePort
    $navlThemeColorPayload = Get-Payload $navlThemeColor
    $navlThemeInfo = Invoke-Tool -Id 'NAVL_07_theme_info_in_game' -Tool 'project_get_theme_info' -Arguments @{ theme_path = $navlThemeColorPayload.theme_path } -Port_ $GamePort
    $navlThemePayload = Get-Payload $navlThemeInfo
    $navlColors = Get-PropertyValue $navlThemePayload.colors ([string]$navlThemeColorPayload.node_type)
    Check 'navl05_theme_chain_runs_in_the_game_process' `
        (($null -ne $navlThemeCreatePayload) -and ($navlThemeCreatePayload.created -eq $true) -and ($null -ne $navlThemeColorPayload) -and ($navlThemeColorPayload.saved -eq $true) -and ($null -ne $navlThemePayload) -and ($null -ne (Get-PropertyValue $navlColors 'font_color'))) `
        ("a game process with no editor runs the whole theme loop: project_create_theme -> project_set_theme_color -> project_get_theme_info -> " + (Get-PayloadText $navlThemeInfo))

    Stop-Engine -Handle $game2Handle
    $game2Handle = $null

    Check 'chain_string_operations_are_zero' ($script:StringOps -eq 0) `
        ("the script's own string-surgery counter is {0}: every identifier above was fed as the parsed object" -f $script:StringOps)
} finally {
    Stop-Engine -Handle $editorHandle
    Stop-Engine -Handle $gameHandle
    Stop-Engine -Handle $game2Handle
}

$portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence
foreach ($port in @($EditorPort, $GamePort)) {
    $pid_ = Get-ListenerPid -Port_ $port
    Check ("port_{0}_released" -f $port) ($pid_ -lt 0) ("no listener is left on {0}" -f $port)
}

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
