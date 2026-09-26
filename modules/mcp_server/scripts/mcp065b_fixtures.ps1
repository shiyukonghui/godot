# =============================================================================
#  mcp065b_fixtures.ps1 -- TASK-065 section B scratch fixtures (pure ASCII).
#
#  Two throw-away projects under %TEMP%\mcp065b, both written UTF-8 WITHOUT a
#  BOM and with LF line endings (scripts/mcp_import_guard.ps1 Write-McpUtf8NoBom):
#
#   proj-editor  a 2D scene with a REAL persistent scene-level signal connection
#                (Timer.timeout -> Main._on_timer_timeout and
#                 Marker.timeout -> Main._on_timer_two_timeout, both methods
#                 spelled without "::", i.e. the user half of
#                 editor_list_signal_connections' `scope`), plus a large
#                 ColorRect that the 2D editor viewport really draws so a pixel
#                 change is possible.
#
#   proj-game    a genuinely playable mini-breakout in GDScript (no C#): a
#                paddle driven by InputMap actions, a ball that moves every
#                physics frame and removes the brick it reaches, a score label
#                the brick writes through its parent. Nothing here is a mock:
#                every value the game-side tools read back is produced by the
#                engine's own scene tree and physics loop.
#
#  The actions carry an EMPTY event list on purpose. The module injects
#  InputEventAction, and InputMap::event_get_action_status matches an
#  InputEventAction by NAME alone (core/input/input_map.cpp:294-315), so the
#  action only has to exist for Input.is_action_pressed to answer.
# =============================================================================

param(
    [string]$EditorProject = (Join-Path $env:TEMP 'mcp065b\proj-editor'),
    [string]$GameProject = (Join-Path $env:TEMP 'mcp065b\proj-game')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

# --------------------------------------------------------------------- editor -
New-Item -ItemType Directory -Force -Path (Join-Path $EditorProject 'scenes') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $EditorProject 'scripts') | Out-Null

$editorProjectGodot = @'
config_version=5

[application]

config/name="mcp065b-editor"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.8")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.05, 0.05, 0.08, 1)
'@

$editorMainGd = @'
extends Node2D


func _on_timer_timeout() -> void:
    pass


func _on_timer_two_timeout() -> void:
    pass
'@

$editorScene = @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]

[node name="Main" type="Node2D"]
script = ExtResource("1_main")

[node name="Timer" type="Timer" parent="."]
one_shot = false
autostart = false

[node name="Marker" type="Timer" parent="."]
one_shot = true
autostart = false

[node name="Box" type="ColorRect" parent="."]
offset_left = 40.0
offset_top = 40.0
offset_right = 360.0
offset_bottom = 240.0
color = Color(0.92549, 0.282353, 0.603922, 1)

[connection signal="timeout" from="Timer" to="." method="_on_timer_timeout"]
[connection signal="timeout" from="Marker" to="." method="_on_timer_two_timeout"]
'@

Write-McpUtf8NoBom -Path (Join-Path $EditorProject 'project.godot') -Text $editorProjectGodot
Write-McpUtf8NoBom -Path (Join-Path $EditorProject 'scripts\main.gd') -Text $editorMainGd
Write-McpUtf8NoBom -Path (Join-Path $EditorProject 'scenes\main.tscn') -Text $editorScene

# ----------------------------------------------------------------------- game -
New-Item -ItemType Directory -Force -Path (Join-Path $GameProject 'scenes') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $GameProject 'scripts') | Out-Null

$gameProjectGodot = @'
config_version=5

[application]

config/name="mcp065b-game"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.8")

[input]

paddle_left={
"deadzone": 0.5,
"events": []
}
paddle_right={
"deadzone": 0.5,
"events": []
}
launch={
"deadzone": 0.5,
"events": []
}

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.05, 0.05, 0.08, 1)
'@

$gameScene = @'
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]
[ext_resource type="Script" path="res://scripts/paddle.gd" id="2_paddle"]
[ext_resource type="Script" path="res://scripts/ball.gd" id="3_ball"]
[ext_resource type="Script" path="res://scripts/brick.gd" id="4_brick"]

[node name="Main" type="Node2D"]
script = ExtResource("1_main")

[node name="Paddle" type="Node2D" parent="."]
position = Vector2(300, 560)
script = ExtResource("2_paddle")

[node name="Ball" type="Node2D" parent="."]
position = Vector2(300, 320)
script = ExtResource("3_ball")

[node name="Bricks" type="Node2D" parent="."]

[node name="Brick0" type="Node2D" parent="Bricks"]
position = Vector2(300, 160)
script = ExtResource("4_brick")

[node name="Brick1" type="Node2D" parent="Bricks"]
position = Vector2(200, 160)
script = ExtResource("4_brick")

[node name="Brick2" type="Node2D" parent="Bricks"]
position = Vector2(400, 160)
script = ExtResource("4_brick")

[node name="HUD" type="CanvasLayer" parent="."]

[node name="ScoreLabel" type="Label" parent="HUD"]
offset_left = 40.0
offset_top = 20.0
offset_right = 440.0
offset_bottom = 60.0
text = "Score: 0"
'@

$gameMainGd = @'
extends Node2D

var score: int = 0
var bricks_hit: int = 0
var launched: bool = false


func add_score(points: int) -> void:
    score += points
    bricks_hit += 1
    var label := get_node_or_null("HUD/ScoreLabel")
    if label != null:
        label.text = "Score: " + str(score)


func _physics_process(_delta: float) -> void:
    if not launched and Input.is_action_pressed("launch"):
        launched = true
        var ball := get_node_or_null("Ball")
        if ball != null:
            ball.call("launch")
'@

$gamePaddleGd = @'
extends Node2D

const SPEED := 420.0

var moves: int = 0


func _physics_process(delta: float) -> void:
    var dir := 0.0
    if Input.is_action_pressed("paddle_right"):
        dir += 1.0
    if Input.is_action_pressed("paddle_left"):
        dir -= 1.0
    if dir != 0.0:
        moves += 1
        position.x = clampf(position.x + dir * SPEED * delta, 40.0, 560.0)
'@

$gameBallGd = @'
extends Node2D

const SPEED := 240.0

var live: bool = false
var bounces: int = 0


func launch() -> void:
    live = true


func _physics_process(delta: float) -> void:
    if not live:
        return
    position.y -= SPEED * delta
    var bricks := get_parent().get_node_or_null("Bricks")
    if bricks == null:
        return
    for brick in bricks.get_children():
        if absf(brick.position.x - position.x) < 40.0 and absf(brick.position.y - position.y) < 24.0:
            hit_brick(brick)
            return


func hit_brick(brick: Node) -> void:
    bounces += 1
    live = false
    var main := get_parent()
    if main != null and main.has_method("add_score"):
        main.call("add_score", 10)
    brick.queue_free()
'@

$gameBrickGd = @'
extends Node2D

const POINTS := 10

var was_hit: bool = false
'@

Write-McpUtf8NoBom -Path (Join-Path $GameProject 'project.godot') -Text $gameProjectGodot
Write-McpUtf8NoBom -Path (Join-Path $GameProject 'scenes\main.tscn') -Text $gameScene
Write-McpUtf8NoBom -Path (Join-Path $GameProject 'scripts\main.gd') -Text $gameMainGd
Write-McpUtf8NoBom -Path (Join-Path $GameProject 'scripts\paddle.gd') -Text $gamePaddleGd
Write-McpUtf8NoBom -Path (Join-Path $GameProject 'scripts\ball.gd') -Text $gameBallGd
Write-McpUtf8NoBom -Path (Join-Path $GameProject 'scripts\brick.gd') -Text $gameBrickGd

Write-Host ('FIXTURES written: editor=' + $EditorProject + ' game=' + $GameProject)

# A machine-readable manifest of what the fixtures claim, for the report.
$files = @()
foreach ($root in @($EditorProject, $GameProject)) {
    foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName)) {
        if ($f.FullName -like '*\.godot\*') { continue }
        $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLower()
        $files += [pscustomobject]@{ path = $f.FullName; bytes = $f.Length; sha256 = $h }
    }
}
$files | ConvertTo-Json -Depth 4 | ForEach-Object { Write-Host $_ }
exit 0