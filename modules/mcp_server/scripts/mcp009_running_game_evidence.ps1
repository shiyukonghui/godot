# =============================================================================
#  mcp009_running_game_evidence.ps1 -- TASK-009 gate 2
#
#  The evidence for the single `scope = game` tool of B1,
#  `running_game_find_nearby_nodes`, and the first end-to-end proof of the
#  "game-only must be absent from the editor endpoint" direction.
#
#  Phases:
#    -Phase game    a real game engine on 9889 against a scratch project whose
#                   main scene has one node of every interesting shape (a 2D
#                   root, two grouped Node2Ds, an out-of-radius Node2D, a
#                   Sprite2D and a Node3D child under it). Records the success
#                   class, both filters, `max_results` (including 0), the
#                   inclusive distance boundary, the missing/mistyped-parameter
#                   refusals and the bottom-layer failure (a second, live game
#                   project whose current scene has been cleared, so
#                   `SceneTree::get_current_scene()` is null).
#    -Phase scope   the *editor* engine on 9888: the tool must be absent from
#                   `tools/list` and calling it must be -32601 with no
#                   execution; then the *game* engine on 9889 as the
#                   counter-direction (the tool present, an editor-only tool
#                   absent and refused). Both full name lists are printed
#                   side by side.
#    -Phase count   `docs/scripts/check_tool_groups.py` plus a machine-checked
#                   per-group count: the `implemented = true` groups sum to 41
#                   distinct tools and `running_game_read_scene` contributes 1.
#
#  Discipline (PLAYBOOK section 3 and section 7.1):
#    * every response body goes to its own file with `curl.exe -s -o <file>`
#      (never through Out-File or a pipeline) and its sha256 is computed from
#      the bytes on disk;
#    * the scratch projects are fresh copies under %TEMP%; nothing is written
#      inside the repository or any user project;
#    * ports 9888 (editor) / 9889 (game) only. Port 9877 belongs to the user's
#      editor: it is never touched, only observed, and its listener pid is
#      asserted unchanged by every phase;
#    * only engines this script started itself are stopped.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp009_running_game_evidence.ps1 -Phase game
#    powershell ... -Phase scope
#    powershell ... -Phase count
# =============================================================================

param(
    [ValidateSet('game', 'scope', 'count')]
    [string]$Phase = 'game',
    [switch]$KeepScratch
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877
$Scratch = Join-Path $env:TEMP 'mcp009-running-game-scratch'
$NoSceneScratch = Join-Path $env:TEMP 'mcp009-running-game-noscene'
$LogRoot = Join-Path $env:TEMP 'mcp009-running-game-logs'
$Evid = Join-Path $env:TEMP 'mcp009-running-game-evidence'

$ToolName = 'running_game_find_nearby_nodes'
$EditorOnlyProbe = 'editor_get_errors'

$script:Results = New-Object System.Collections.Generic.List[object]
$script:StartedPids = New-Object System.Collections.Generic.List[int]

function Add-Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Results.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1} :: {2}" -f $tag, $Id, $Evidence)
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Get-ListenerPid {
    param([int]$Port)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

function Wait-ForTcp {
    param([int]$Port, [int]$TimeoutMs = 240000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $task = $client.ConnectAsync('127.0.0.1', $Port)
            if ($task.Wait(700) -and $client.Connected) { return $true }
        } catch { } finally { $client.Close() }
        Start-Sleep -Milliseconds 600
    }
    return $false
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $out = Join-Path $LogRoot ($LogName + '.out.log')
    $err = Join-Path $LogRoot ($LogName + '.err.log')
    Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    $script:StartedPids.Add($proc.Id)
    Write-Host ("started pid={0} :: {1}" -f $proc.Id, ($Arguments -join ' '))
    return [pscustomobject]@{ Process = $proc; Out = $out }
}

function Stop-Engine {
    param($Handle)
    if ($null -eq $Handle) { return }
    try {
        if (-not $Handle.Process.HasExited) {
            Stop-Process -Id $Handle.Process.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 1200
        }
    } catch { }
}

function Import-Project {
    param([string]$Path, [string]$LogName)
    $out = Join-Path $LogRoot ($LogName + '.out.log')
    $err = Join-Path $LogRoot ($LogName + '.err.log')
    $proc = Start-Process -FilePath $Engine -ArgumentList @('--headless', '--path', $Path, '--import') `
        -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    $proc.WaitForExit(300000) | Out-Null
}

# One JSON-RPC request: body to a file, `curl.exe --data-binary @file`, response
# to its own file with `-o` (never through a pipe).
function Invoke-Mcp {
    param([string]$Id, [string]$Json, [int]$Port)
    $bodyFile = Join-Path $Evid ("{0}.request.json" -f $Id)
    $respFile = Join-Path $Evid ("{0}.response.json" -f $Id)
    [IO.File]::WriteAllBytes($bodyFile, [Text.Encoding]::UTF8.GetBytes($Json))
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) `
        ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    $curlExit = $LASTEXITCODE
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] port={1} curl_exit={2} bytes={3} sha256={4}" -f $Id, $Port, $curlExit, $bytes.Length, $sha)
    Write-Host ("       request : {0}" -f $Json)
    Write-Host ("       response: {0}" -f $text)
    return $text
}

function Get-Payload {
    param([string]$ResponseText)
    $json = $ResponseText | ConvertFrom-Json
    if ($null -ne $json.result -and $null -ne $json.result.content) {
        return ($json.result.content[0].text | ConvertFrom-Json)
    }
    return $null
}

function Get-ErrorObject {
    param([string]$ResponseText)
    return ($ResponseText | ConvertFrom-Json).error
}

function Get-Lists {
    param([string]$ResponseText)
    $json = $ResponseText | ConvertFrom-Json
    if ($null -eq $json.result) { return $null }
    return @($json.result.tools | ForEach-Object { [string]$_.name })
}

# The scene under test. Order matters: it is the pre-order the tool walks, and
# that order is what breaks distance ties.
#   Main     Node2D    (0,0)          the root, included by the reference walk
#   Center   Node2D    (0,0)   group markers
#   Near     Node2D    (10,0)  group markers
#   Far      Node2D    (90,0)         exactly on the radius-90 boundary
#   TooFar   Node2D    (250,0)        outside every radius tested here
#   Sprite   Sprite2D  (0,0)
#   Child3D  Node3D    (5,0,0)  under Sprite: a Vector3-only position, so the
#                               Vector2 reader falls back to (0,0)
function Get-SceneText {
    return (@(
            '[gd_scene format=3]',
            '',
            '[node name="Main" type="Node2D"]',
            '',
            '[node name="Center" type="Node2D" parent="." groups=["markers"]]',
            'position = Vector2(0, 0)',
            '',
            '[node name="Near" type="Node2D" parent="." groups=["markers"]]',
            'position = Vector2(10, 0)',
            '',
            '[node name="Far" type="Node2D" parent="."]',
            'position = Vector2(90, 0)',
            '',
            '[node name="TooFar" type="Node2D" parent="."]',
            'position = Vector2(250, 0)',
            '',
            '[node name="Sprite" type="Sprite2D" parent="."]',
            'position = Vector2(0, 0)',
            '',
            '[node name="Child3D" type="Node3D" parent="Sprite"]',
            'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5, 0, 0)'
        ) -join "`n") + "`n"
}

function Get-ProjectText {
    param([string]$Name, [bool]$WithMainScene)
    $lines = @(
        'config_version=5',
        '',
        '[application]',
        ('config/name="' + $Name + '"'),
        'config/features=PackedStringArray("4.8")'
    )
    if ($WithMainScene) { $lines += 'run/main_scene="res://scenes/main.tscn"' }
    $lines += @(
        '',
        '[rendering]',
        'renderer/rendering_method="gl_compatibility"',
        'renderer/rendering_method.mobile="gl_compatibility"'
    )
    return (($lines -join "`n") + "`n")
}

# The bottom-layer case: a *running* game whose `SceneTree::get_current_scene()`
# is null. The obvious construction - a project with `run/main_scene` absent -
# does not work: Godot starts, the MCP server binds, and then `Main::start()`
# aborts the process (measured: 9889 accepts one connection and the engine is
# gone), so no request can ever be answered. This project therefore runs a real
# main scene whose root script clears `current_scene` in `_ready()`: the scene
# loop keeps running, the endpoint stays up, and the tool sees exactly the null
# current scene it must refuse.
function Get-ClearedSceneProjectText {
    return ((@(
                'config_version=5',
                '',
                '[application]',
                'config/name="MCP009 current scene cleared"',
                'config/features=PackedStringArray("4.8")',
                'run/main_scene="res://scenes/main.tscn"',
                '',
                '[rendering]',
                'renderer/rendering_method="gl_compatibility"',
                'renderer/rendering_method.mobile="gl_compatibility"'
            ) -join "`n") + "`n")
}

function Get-ClearedSceneText {
    return ((@(
                '[gd_scene load_steps=2 format=3]',
                '',
                '[ext_resource type="Script" path="res://scenes/clear_current_scene.gd" id="1_clear"]',
                '',
                '[node name="Main" type="Node2D"]',
                'script = ExtResource("1_clear")'
            ) -join "`n") + "`n")
}

function Get-ClearedSceneScriptText {
    return ((@(
                'extends Node2D',
                '',
                'func _ready() -> void:',
                '	print("MCP009_CURRENT_SCENE_CLEARED")',
                '	get_tree().current_scene = null'
            ) -join "`n") + "`n")
}

function Initialize-Scratch {
    if (Test-Path $Scratch) { Remove-Item -Recurse -Force $Scratch }
    if (Test-Path $NoSceneScratch) { Remove-Item -Recurse -Force $NoSceneScratch }
    New-Item -ItemType Directory -Force -Path $Scratch, (Join-Path $Scratch 'scenes'), `
        (Join-Path $NoSceneScratch 'scenes'), $LogRoot, $Evid | Out-Null
    Write-Utf8NoBom (Join-Path $Scratch 'project.godot') (Get-ProjectText -Name 'MCP009 running game scratch' -WithMainScene $true)
    Write-Utf8NoBom (Join-Path $Scratch 'scenes\main.tscn') (Get-SceneText)
    Write-Utf8NoBom (Join-Path $NoSceneScratch 'project.godot') (Get-ClearedSceneProjectText)
    Write-Utf8NoBom (Join-Path $NoSceneScratch 'scenes\main.tscn') (Get-ClearedSceneText)
    Write-Utf8NoBom (Join-Path $NoSceneScratch 'scenes\clear_current_scene.gd') (Get-ClearedSceneScriptText)
    Write-Host ("scratch (with main scene)  : {0}" -f $Scratch)
    Write-Host ("scratch (scene cleared)    : {0}" -f $NoSceneScratch)
}

function Assert-Nodes {
    param([string]$ResponseText, [string]$Label, [string[]]$ExpectedNames, [string[]]$ExpectedPaths, [double[]]$ExpectedDistances)
    $payload = Get-Payload $ResponseText
    if ($null -eq $payload) {
        Add-Check $Label $false ("expected a result, got: {0}" -f $ResponseText)
        return
    }
    $nodes = @($payload.nodes)
    $actualNames = @($nodes | ForEach-Object { [string]$_.name })
    $actualPaths = @($nodes | ForEach-Object { [string]$_.path })
    $actualDistances = @($nodes | ForEach-Object { [double]$_.distance })
    $sameNames = (($actualNames -join '|') -ceq ($ExpectedNames -join '|'))
    $samePaths = (($actualPaths -join '|') -ceq ($ExpectedPaths -join '|'))
    $sameDistances = $true
    if ($actualDistances.Count -ne $ExpectedDistances.Count) {
        $sameDistances = $false
    } else {
        for ($i = 0; $i -lt $ExpectedDistances.Count; $i++) {
            if ([Math]::Abs($actualDistances[$i] - $ExpectedDistances[$i]) -gt 0.0001) { $sameDistances = $false }
        }
    }
    $countOk = ([int]$payload.count -eq $nodes.Count) -and ($nodes.Count -eq $ExpectedNames.Count)
    $ascending = $true
    for ($i = 1; $i -lt $actualDistances.Count; $i++) {
        if ($actualDistances[$i] -lt $actualDistances[$i - 1]) { $ascending = $false }
    }
    $ok = $sameNames -and $samePaths -and $sameDistances -and $countOk -and $ascending
    Add-Check $Label $ok ("count={0} nodes={1} names=[{2}] paths=[{3}] distances=[{4}] ascending={5} expected_names=[{6}]" -f `
            $payload.count, $nodes.Count, ($actualNames -join ','), ($actualPaths -join ','), (($actualDistances | ForEach-Object { $_.ToString('0.###') }) -join ','), `
        $ascending, ($ExpectedNames -join ','))
}

function Assert-Error {
    param([string]$ResponseText, [string]$Label, [int]$Code, [string]$MessageFragment)
    $e = Get-ErrorObject $ResponseText
    if ($null -eq $e) {
        Add-Check $Label $false ("expected the error {0}, got a result: {1}" -f $Code, $ResponseText)
        return
    }
    $ok = ($e.code -eq $Code)
    if ($MessageFragment -ne '') { $ok = $ok -and ([string]$e.message).Contains($MessageFragment) }
    Add-Check $Label $ok ("code={0} message='{1}' expected_code={2} message_contains='{3}'" -f $e.code, $e.message, $Code, $MessageFragment)
}

function Show-PortGuard {
    param([int]$Before, [string]$Label)
    $after = Get-ListenerPid -Port $UserPort
    Add-Check $Label (($Before -eq $after) -and ($Before -ne -1)) ("port {0} pid_before={1} pid_after={2}" -f $UserPort, $Before, $after)
}

# =============================================================================
#  Main
# =============================================================================

Write-Host ("=== TASK-009 gate 2 evidence (phase={0}) ===" -f $Phase)

if (Test-Path $Engine) {
    $engineSha = (Get-FileHash -Algorithm SHA256 -Path $Engine).Hash
    Write-Host ("engine: {0}" -f $Engine)
    Write-Host ("engine sha256: {0}" -f $engineSha)
} else {
    Write-Host ("FATAL: engine not found: {0}" -f $Engine)
    exit 2
}

$userPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ("user editor on {0} before: pid={1}" -f $UserPort, $userPidBefore)

# -----------------------------------------------------------------------------
# -Phase game
# -----------------------------------------------------------------------------
if ($Phase -eq 'game') {
    Initialize-Scratch
    Write-Host 'importing the scratch projects ...'
    Import-Project -Path $Scratch -LogName 'import-game-scratch'
    Import-Project -Path $NoSceneScratch -LogName 'import-noscene'

    $gameHandle = $null
    $noSceneHandle = $null
    try {
        $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Scratch, ("--mcp-port={0}" -f $GamePort)) -LogName 'game-scratch'
        if (-not (Wait-ForTcp -Port $GamePort)) { throw "the game endpoint on $GamePort never came up; log=$(Get-Content -Raw $gameHandle.Out -ErrorAction SilentlyContinue)" }
        Start-Sleep -Seconds 8
        Write-Host 'the game endpoint is listening'

        # --- 1. success -----------------------------------------------------
        # Recomputed from the real tree: the root `Main` (0,0), `Center` (0,0),
        # `Sprite` (0,0), `Child3D` (the Vector3 fallback, (0,0)), `Near` (10,0)
        # and `Far` (90,0) are all within radius 100, so count is 6 - `TooFar`
        # (250,0) is the only node outside. The ties at distance 0 come out in
        # pre-order because the sort key is (distance, pre-order index).
        $t = Invoke-Mcp -Id 'game01_success_radius100' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0,"y":0},"radius":100}}}')
        Assert-Nodes $t 'game_success_radius100' `
            @('Main', 'Center', 'Sprite', 'Child3D', 'Near', 'Far') `
            @('/root/Main', '/root/Main/Center', '/root/Main/Sprite', '/root/Main/Sprite/Child3D', '/root/Main/Near', '/root/Main/Far') `
            @(0.0, 0.0, 0.0, 0.0, 10.0, 90.0)

        $p = Get-Payload $t
        if ($null -ne $p) {
            $root = @($p.nodes | Where-Object { [string]$_.name -ceq 'Main' })
            $rootOk = ($root.Count -eq 1) -and ([string]$root[0].path -ceq '/root/Main') -and ([string]$root[0].type -ceq 'Node2D')
            Add-Check 'game_success_root_included' $rootOk ("Main -> path={0} type={1}" -f $(if ($root.Count -eq 1) { $root[0].path } else { 'absent' }), $(if ($root.Count -eq 1) { $root[0].type } else { 'absent' }))
            $tooFar = @($p.nodes | Where-Object { [string]$_.name -ceq 'TooFar' })
            Add-Check 'game_success_out_of_radius_excluded' ($tooFar.Count -eq 0) ("TooFar (250,0) present in the nodes list: {0}" -f $tooFar.Count)
        }

        # --- 2. filters -----------------------------------------------------
        $t = Invoke-Mcp -Id 'game02_group_filter_markers' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0,"y":0},"radius":100,"group_filter":"markers"}}}')
        Assert-Nodes $t 'game_group_filter_markers' @('Center', 'Near') @('/root/Main/Center', '/root/Main/Near') @(0.0, 10.0)

        $t = Invoke-Mcp -Id 'game03_type_filter_node3d' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0,"y":0},"radius":100,"type_filter":"Node3D"}}}')
        Assert-Nodes $t 'game_type_filter_node3d' @('Child3D') @('/root/Main/Sprite/Child3D') @(0.0)
        # The same request is also the "a failing filter does not prune the
        # subtree" proof: `Child3D` sits under `Sprite`, which is not a Node3D,
        # so the walk had to descend through a non-matching parent to find it.
        Add-Check 'game_filter_does_not_prune_subtree' (((Get-Payload $t) | ForEach-Object { $_.count }) -eq 1) 'Child3D was found below a non-matching Sprite2D parent, so the type filter skipped Sprite without pruning its children'

        $t = Invoke-Mcp -Id 'game04_type_filter_node2d' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0,"y":0},"radius":100,"type_filter":"Node2D"}}}')
        Assert-Nodes $t 'game_type_filter_node2d' @('Main', 'Center', 'Sprite', 'Near', 'Far') `
            @('/root/Main', '/root/Main/Center', '/root/Main/Sprite', '/root/Main/Near', '/root/Main/Far') @(0.0, 0.0, 0.0, 10.0, 90.0)

        # --- 3. max_results -------------------------------------------------
        $t = Invoke-Mcp -Id 'game05_max_results_2' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0,"y":0},"radius":1000,"max_results":2}}}')
        Assert-Nodes $t 'game_max_results_2_keeps_nearest' @('Main', 'Center') @('/root/Main', '/root/Main/Center') @(0.0, 0.0)

        $t = Invoke-Mcp -Id 'game06_max_results_0' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0,"y":0},"radius":1000,"max_results":0}}}')
        Assert-Nodes $t 'game_max_results_0_is_an_empty_result' @() @() @()
        $e = Get-ErrorObject $t
        Add-Check 'game_max_results_0_is_not_an_error' ($null -eq $e) ("error object: {0}" -f $(if ($null -eq $e) { 'none' } else { "code=$($e.code)" }))

        $t = Invoke-Mcp -Id 'game07_max_results_negative' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0,"y":0},"radius":1000,"max_results":-3}}}')
        Assert-Nodes $t 'game_max_results_negative_is_an_empty_result' @() @() @()

        # --- 4. the inclusive boundary --------------------------------------
        $t = Invoke-Mcp -Id 'game08_radius_90_includes_far' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0,"y":0},"radius":90}}}')
        Assert-Nodes $t 'game_boundary_radius_90_includes_far' @('Main', 'Center', 'Sprite', 'Child3D', 'Near', 'Far') `
            @('/root/Main', '/root/Main/Center', '/root/Main/Sprite', '/root/Main/Sprite/Child3D', '/root/Main/Near', '/root/Main/Far') @(0.0, 0.0, 0.0, 0.0, 10.0, 90.0)

        $t = Invoke-Mcp -Id 'game09_radius_89_9_excludes_far' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0,"y":0},"radius":89.9}}}')
        Assert-Nodes $t 'game_boundary_radius_89_9_excludes_far' @('Main', 'Center', 'Sprite', 'Child3D', 'Near') `
            @('/root/Main', '/root/Main/Center', '/root/Main/Sprite', '/root/Main/Sprite/Child3D', '/root/Main/Near') @(0.0, 0.0, 0.0, 0.0, 10.0)

        # --- 5. the parameter contract --------------------------------------
        $t = Invoke-Mcp -Id 'game10_missing_position' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{}}}')
        Assert-Error $t 'game_missing_position_is_-32602' -32602 'Missing required parameter: position'
        Add-Check 'game_missing_position_has_no_result' ((-not $t.Contains('"result"')) -and $t.Contains('"code":-32602')) 'the refusal carries no result envelope'

        $t = Invoke-Mcp -Id 'game11_scalar_position' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":5}}}')
        Assert-Error $t 'game_scalar_position_is_-32602' -32602 "Parameter 'position' must be an object, got float"

        $t = Invoke-Mcp -Id 'game12_mistyped_radius' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0},"radius":"big"}}}')
        Assert-Error $t 'game_mistyped_radius_is_-32602' -32602 "Parameter 'radius' must be a number, got String"

        $t = Invoke-Mcp -Id 'game13_mistyped_position_component' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":"a"}}}}')
        Assert-Error $t 'game_mistyped_position_component_is_-32602' -32602 "Parameter 'position.x' must be a number, got String"

        $t = Invoke-Mcp -Id 'game14_mistyped_max_results' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0},"max_results":"many"}}}')
        Assert-Error $t 'game_mistyped_max_results_is_-32602' -32602 "Parameter 'max_results' must be an integer, got String"

        $t = Invoke-Mcp -Id 'game15_mistyped_group_filter' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0},"group_filter":7}}}')
        Assert-Error $t 'game_mistyped_group_filter_is_-32602' -32602 "Parameter 'group_filter' must be a string, got float"

        Stop-Engine -Handle $gameHandle
        $gameHandle = $null

        # --- 6. bottom-layer failure: no current scene -----------------------
        # A live game whose current scene has been cleared (see
        # `Get-ClearedSceneProjectText`): the tool must refuse with -32000 and a
        # `data.suggestion`, never dereference the null scene.
        $noSceneHandle = Start-Engine -Arguments @('--headless', '--path', $NoSceneScratch, ("--mcp-port={0}" -f $GamePort)) -LogName 'game-noscene'
        if (-not (Wait-ForTcp -Port $GamePort)) { throw "the cleared-scene game endpoint on $GamePort never came up; log=$(Get-Content -Raw $noSceneHandle.Out -ErrorAction SilentlyContinue)" }
        Start-Sleep -Seconds 6
        Add-Check 'game_cleared_scene_endpoint_is_really_a_running_game' (-not $noSceneHandle.Process.HasExited) ("engine pid={0} still running, so the -32000 below is the tool's null-scene refusal and not a dead endpoint" -f $noSceneHandle.Process.Id)
        $t = Invoke-Mcp -Id 'game16_no_current_scene' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0,"y":0}}}}')
        Assert-Error $t 'game_no_current_scene_is_-32000' -32000 ''
        $e = Get-ErrorObject $t
        if ($null -ne $e) {
            $hasSuggestion = ($null -ne $e.data) -and ($null -ne $e.data.suggestion) -and ([string]$e.data.suggestion).Length -gt 0
            Add-Check 'game_no_current_scene_has_suggestion' $hasSuggestion ("code={0} message='{1}' suggestion='{2}' with_cleared_current_scene=true" -f $e.code, $e.message, $e.data.suggestion)
            Add-Check 'game_no_current_scene_has_no_result' (-not $t.Contains('"result"')) 'the refusal carries no result envelope and no nodes list'
        } else {
            Add-Check 'game_no_current_scene_has_suggestion' $false 'no error object at all'
        }
        Stop-Engine -Handle $noSceneHandle
        $noSceneHandle = $null
    } finally {
        Stop-Engine -Handle $gameHandle
        Stop-Engine -Handle $noSceneHandle
        Show-PortGuard -Before $userPidBefore -Label 'guard_user_port_9877'
    }
}

# -----------------------------------------------------------------------------
# -Phase scope
# -----------------------------------------------------------------------------
if ($Phase -eq 'scope') {
    Initialize-Scratch
    Write-Host 'importing the scratch project ...'
    Import-Project -Path $Scratch -LogName 'import-scope'

    $editorHandle = $null
    $gameHandle = $null
    $editorNames = @()
    $gameNames = @()
    try {
        # --- editor endpoint (9888) -----------------------------------------
        $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Scratch, ("--mcp-port={0}" -f $EditorPort)) -LogName 'editor-scope'
        if (-not (Wait-ForTcp -Port $EditorPort)) { throw "the editor endpoint on $EditorPort never came up; log=$(Get-Content -Raw $editorHandle.Out -ErrorAction SilentlyContinue)" }
        Start-Sleep -Seconds 8

        $list = Invoke-Mcp -Id 'scope01_editor_tools_list' -Port $EditorPort -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
        $editorNames = Get-Lists $list
        $present = @($editorNames | Where-Object { $_ -ceq $ToolName })
        Add-Check 'scope_game_only_tool_absent_from_editor_list' ($present.Count -eq 0) ("{0}: occurrences on the editor endpoint (9888) = {1}; editor endpoint serves {2} tool(s)" -f $ToolName, $present.Count, $editorNames.Count)
        Add-Check 'scope_editor_endpoint_tool_count' ($editorNames.Count -eq 40) ("tools/list on 9888 returned {0} tool(s) (41 registered in an editor process minus the 1 game-only tool)" -f $editorNames.Count)

        $t = Invoke-Mcp -Id 'scope02_editor_calls_game_tool' -Port $EditorPort -Json ('{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"' + $ToolName + '","arguments":{"position":{"x":0,"y":0}}}}')
        Assert-Error $t 'scope_editor_refuses_game_tool_with_-32601' -32601 ("Method not found: " + $ToolName)
        Add-Check 'scope_editor_refusal_did_not_execute' ((-not $t.Contains('"result"')) -and (-not $t.Contains('"nodes"'))) 'the refusal contains neither a result envelope nor a nodes list'

        Stop-Engine -Handle $editorHandle
        $editorHandle = $null

        # --- game endpoint (9889), the counter-direction ---------------------
        $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Scratch, ("--mcp-port={0}" -f $GamePort)) -LogName 'game-scope'
        if (-not (Wait-ForTcp -Port $GamePort)) { throw "the game endpoint on $GamePort never came up; log=$(Get-Content -Raw $gameHandle.Out -ErrorAction SilentlyContinue)" }
        Start-Sleep -Seconds 8

        $list = Invoke-Mcp -Id 'scope03_game_tools_list' -Port $GamePort -Json '{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}'
        $gameNames = Get-Lists $list
        $present = @($gameNames | Where-Object { $_ -ceq $ToolName })
        Add-Check 'scope_game_only_tool_present_on_game_list' ($present.Count -eq 1) ("{0}: occurrences on the game endpoint (9889) = {1}; game endpoint serves {2} tool(s)" -f $ToolName, $present.Count, $gameNames.Count)
        $leaked = @($gameNames | Where-Object { $_ -ceq $EditorOnlyProbe })
        Add-Check 'scope_editor_only_tool_absent_from_game_list' ($leaked.Count -eq 0) ("{0}: occurrences on the game endpoint = {1}" -f $EditorOnlyProbe, $leaked.Count)
        Add-Check 'scope_game_endpoint_tool_count' ($gameNames.Count -eq 24) ("tools/list on 9889 returned {0} tool(s) (23 both-scope tools plus the 1 game-only tool)" -f $gameNames.Count)

        $t = Invoke-Mcp -Id 'scope04_game_calls_editor_tool' -Port $GamePort -Json ('{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"' + $EditorOnlyProbe + '","arguments":{}}}')
        Assert-Error $t 'scope_game_refuses_editor_tool_with_-32601' -32601 ("Method not found: " + $EditorOnlyProbe)

        Stop-Engine -Handle $gameHandle
        $gameHandle = $null
    } finally {
        Stop-Engine -Handle $editorHandle
        Stop-Engine -Handle $gameHandle

        Write-Host ''
        Write-Host '================= the two endpoints side by side ================='
        Write-Host ("editor 9888 ({0} tools): {1}" -f $editorNames.Count, ($editorNames -join ' > '))
        Write-Host ("game   9889 ({0} tools): {1}" -f $gameNames.Count, ($gameNames -join ' > '))
        $editorOnly = @($editorNames | Where-Object { $gameNames -notcontains $_ })
        $gameOnly = @($gameNames | Where-Object { $editorNames -notcontains $_ })
        Write-Host ("editor-only tools (present on 9888, absent on 9889): {0}" -f (($editorOnly) -join ', '))
        Write-Host ("game-only tools   (present on 9889, absent on 9888): {0}" -f (($gameOnly) -join ', '))
        Add-Check 'scope_the_editor_game_split_is_exactly_the_scopes' `
            ((($editorOnly.Count) -eq 17) -and (($gameOnly.Count) -eq 1) -and ($gameOnly[0] -ceq $ToolName)) `
            ("editor-only={0} [{1}] game-only={2} [{3}]" -f $editorOnly.Count, ($editorOnly -join ','), $gameOnly.Count, ($gameOnly -join ','))

        Show-PortGuard -Before $userPidBefore -Label 'guard_user_port_9877'
    }
}

# -----------------------------------------------------------------------------
# -Phase count
# -----------------------------------------------------------------------------
if ($Phase -eq 'count') {
    $groupsJson = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups.json'
    $checker = Join-Path $RepoRoot 'modules\mcp_server\docs\scripts\check_tool_groups.py'
    $doc = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $groupsJson)

    Write-Host ''
    Write-Host '========== docs/scripts/check_tool_groups.py =========='
    & python $checker
    $checkerExit = $LASTEXITCODE
    Write-Host ("check_tool_groups.py exit code: {0}" -f $checkerExit)
    Add-Check 'count_check_tool_groups_exit_zero' ($checkerExit -eq 0) ("python modules/mcp_server/docs/scripts/check_tool_groups.py exit={0}" -f $checkerExit)

    Write-Host ''
    Write-Host '========== machine-checked per-group tool count =========='
    $implemented = @($doc.groups | Where-Object { $_.implemented -eq $true })
    $all = New-Object System.Collections.Generic.List[string]
    foreach ($group in $doc.groups) {
        $mark = if ($group.implemented -eq $true) { 'implemented' } else { 'NOT-implemented' }
        Write-Host ("{0,-30} {1,-12} {2,-8} tools={3}" -f $group.name, $group.channel, $mark, @($group.tools).Count)
        if ($group.implemented -eq $true) {
            foreach ($tool in @($group.tools)) { $all.Add([string]$tool) }
        }
    }
    $distinct = @($all | Sort-Object -Unique)
    $duplicates = @($all | Group-Object | Where-Object { $_.Count -gt 1 })
    Add-Check 'count_b1_closure_41_distinct' (($distinct.Count -eq 41) -and ($duplicates.Count -eq 0)) `
        ("implemented=true groups = {0}; distinct tools = {1}; duplicated = {2}; B1 closure = {1}/41" -f $implemented.Count, $distinct.Count, $duplicates.Count)
    $rgr = @($doc.groups | Where-Object { $_.name -ceq 'running_game_read_scene' })
    $rgrOk = ($rgr.Count -eq 1) -and ($rgr[0].implemented -eq $true) -and (@($rgr[0].tools).Count -eq 1) -and ([string]$rgr[0].tools[0] -ceq $ToolName)
    Add-Check 'count_running_game_read_scene_contributes_one' $rgrOk `
        ("group running_game_read_scene: implemented={0} tools={1} [{2}]" -f $rgr[0].implemented, @($rgr[0].tools).Count, (@($rgr[0].tools) -join ','))
}

$passed = @($script:Results | Where-Object { $_.pass }).Count
$total = $script:Results.Count
Write-Host ''
Write-Host ("=== phase {0}: {1}/{2} checks passed ===" -f $Phase, $passed, $total)
foreach ($r in $script:Results) {
    if (-not $r.pass) { Write-Host ("  FAILED {0} :: {1}" -f $r.id, $r.evidence) }
}
Write-Host ("evidence directory: {0}" -f $Evid)
if ($passed -ne $total) { exit 1 }
exit 0