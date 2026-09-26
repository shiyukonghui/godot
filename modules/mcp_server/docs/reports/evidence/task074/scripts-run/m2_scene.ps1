# m2_scene.ps1 -- TASK-074 section A milestone M2: main scene assembly with
# instanced sub-scenes, animation, tilemap, UI/theme, audio (pure ASCII).
$ErrorActionPreference = 'Stop'
. 'C:\Users\wyl\AppData\Local\Temp\mcp-platformer\mcplib.ps1'
$MS = 'M2'
Append-Progress 'M2 begin: main scene assembly (instances/animation/UI/audio)'

$r = Invoke-Mcp -Port 9888 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Tag 'open_main' -Milestone $MS
Write-Host ('open_main -> ' + $r.Ok + ' ' + $r.Text)

# ------------------------------------------------------------------ the C# orchestrator
$cs_main = @'
using Godot;

// TASK-074 section A: Main is C#; it consumes the GDScript coin/enemy scenes and
// drives the GDScript-authored AnimationPlayer.
public partial class Main : Node2D
{
    [Signal] public delegate void GameOverEventHandler();

    public int Score = 0;
    public int Lives = 3;
    public bool Paused = false;

    private Label _scoreLabel;
    private Label _livesLabel;
    private Node2D _player;
    private AnimationPlayer _anim;

    public override void _Ready()
    {
        _scoreLabel = GetNodeOrNull<Label>("HUD/ScoreLabel");
        _livesLabel = GetNodeOrNull<Label>("HUD/LivesLabel");
        _player = GetNodeOrNull<Node2D>("World/Player");
        _anim = GetNodeOrNull<AnimationPlayer>("World/Player/Anim");
        if (_anim != null && _anim.HasAnimation("run"))
        {
            _anim.Play("run");
        }
        GD.Print("[main-cs] ready score=" + Score + " lives=" + Lives);
        RefreshHud();
    }

    public void AddScore(int amount)
    {
        Score += amount;
        RefreshHud();
        GD.Print("[main-cs] score=" + Score);
    }

    public void AddLife(int amount)
    {
        Lives += amount;
        RefreshHud();
    }

    public void OnCoinCollected(int value)
    {
        AddScore(value);
    }

    public void OnPlayerDied()
    {
        Lives -= 1;
        RefreshHud();
        GD.Print("[main-cs] lives=" + Lives);
        if (Lives <= 0)
        {
            EmitSignal(SignalName.GameOver);
        }
    }

    public void SetPaused(bool value)
    {
        Paused = value;
    }

    private void RefreshHud()
    {
        if (_scoreLabel != null) { _scoreLabel.Text = "SCORE " + Score; }
        if (_livesLabel != null) { _livesLabel.Text = "LIVES " + Lives; }
    }
}
'@
$r = Invoke-Mcp -Port 9888 -Tool 'project_create_script' -Arguments @{ path = 'res://scripts/main.gd'; content = $cs_main } -Tag 'create_main_script_wrong_ext' -Milestone $MS -Note 'deliberately probing: .gd path, C# body -> expect an engine verdict, not a silent accept'
Write-Host ('create_main_as_gd -> ' + $r.Ok + ' code=' + $r.Code + ' ' + $r.Text)
$r = Invoke-Mcp -Port 9888 -Tool 'project_create_script' -Arguments @{ path = 'res://scripts/Main.cs'; content = $cs_main } -Tag 'create_main_cs' -Milestone $MS
Write-Host ('create_main_cs -> ' + $r.Ok + ' code=' + $r.Code + ' ' + $r.Text)

# ------------------------------------------------------------------ World / Ground / instanced sub-scenes
$r = Invoke-Mcp -Port 9888 -Tool 'editor_add_node' -Arguments @{ type = 'Node2D'; name = 'World'; parent_path = '.' } -Tag 'add_world' -Milestone $MS
Write-Host ('add_world -> ' + $r.Ok + ' ' + $r.Text)
$r = Invoke-Mcp -Port 9888 -Tool 'editor_add_node' -Arguments @{ type = 'StaticBody2D'; name = 'Ground'; parent_path = 'World' } -Tag 'add_ground' -Milestone $MS
Write-Host ('add_ground -> ' + $r.Ok + ' ' + $r.Text)

# instance player + 3 enemies + 2 coins: six editor_add_scene_instance calls
$r = Invoke-Mcp -Port 9888 -Tool 'editor_add_scene_instance' -Arguments @{ scene_path = 'res://scenes/player.tscn'; parent_path = 'World'; name = 'Player' } -Tag 'inst_player' -Milestone $MS
Write-Host ('inst_player -> ' + $r.Ok + ' code=' + $r.Code + ' ' + $r.Text)
for ($i = 1; $i -le 3; $i++) {
    $r = Invoke-Mcp -Port 9888 -Tool 'editor_add_scene_instance' -Arguments @{ scene_path = 'res://scenes/enemy.tscn'; parent_path = 'World'; name = ('Enemy{0}' -f $i) } -Tag ('inst_enemy{0}' -f $i) -Milestone $MS
    Write-Host ('inst_enemy{0} -> {1} code={2} {3}' -f $i, $r.Ok, $r.Code, $r.Text)
}
for ($i = 1; $i -le 2; $i++) {
    $r = Invoke-Mcp -Port 9888 -Tool 'editor_add_scene_instance' -Arguments @{ scene_path = 'res://scenes/coin.tscn'; parent_path = 'World'; name = ('Coin{0}' -f $i) } -Tag ('inst_coin{0}' -f $i) -Milestone $MS
    Write-Host ('inst_coin{0} -> {1} code={2} {3}' -f $i, $r.Ok, $r.Code, $r.Text)
}

# per-instance overrides on the main scene's instances (one call, many nodes)
$r = Invoke-Mcp -Port 9888 -Tool 'editor_set_node_property_updates' -Arguments @{ updates = @(
    @{ path = 'World/Player'; property = 'position'; value = @{ x = -300; y = 0 } },
    @{ path = 'World/Enemy1'; property = 'position'; value = @{ x = 150; y = 0 } },
    @{ path = 'World/Enemy2'; property = 'position'; value = @{ x = 450; y = 0 } },
    @{ path = 'World/Enemy3'; property = 'position'; value = @{ x = 750; y = 0 } },
    @{ path = 'World/Coin1'; property = 'position'; value = @{ x = 60; y = -80 } },
    @{ path = 'World/Coin2'; property = 'position'; value = @{ x = 220; y = -120 } }
) } -Tag 'inst_overrides' -Milestone $MS
Write-Host ('inst_overrides -> ' + $r.Ok + ' code=' + $r.Code + ' ' + $r.Text)

$r = Invoke-Mcp -Port 9888 -Tool 'editor_set_node_script' -Arguments @{ node_path = '.'; script_path = 'res://scripts/Main.cs' } -Tag 'attach_main_cs' -Milestone $MS
Write-Host ('attach_main_cs -> ' + $r.Ok + ' code=' + $r.Code + ' ' + $r.Text)

$r = Invoke-Mcp -Port 9888 -Tool 'editor_get_scene_tree' -Arguments @{} -Tag 'tree_after_assembly' -Milestone $MS
Write-Host ('tree -> ' + $r.Text)

$r = Invoke-Mcp -Port 9888 -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Tag 'save_main' -Milestone $MS
Write-Host ('save_main -> ' + $r.Ok + ' ' + $r.Text)
Append-Progress ('M2 done; calls={0}' -f $script:McpCallCount)
Write-Host ("M2 calls={0}" -f $script:McpCallCount)