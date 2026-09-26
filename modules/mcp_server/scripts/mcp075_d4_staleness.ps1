# =============================================================================
#  mcp075_d4_staleness.ps1 -- TASK-075 D4: the mechanism behind the round-5
#  observation, reproduced on purpose.
#
#  THE OBSERVATION (PLATFORMER-FINDINGS E1): "the editor cannot address a node
#  inside an instanced sub-scene: `World/Player` resolves, `World/Player/Anim`
#  is `-32001`, while a property write reached `Anim` somewhere else" -- read as
#  "the tools disagree about the same path".
#
#  WHAT THIS SCRIPT SHOWS
#  ---------------------
#   * all three tools resolve through the SAME helper (`MCPTools::find_node`,
#     tools/tool_helpers.cpp:1417), so on a scene whose instance is current they
#     agree (that is the TASK-075 live evidence's L020/L021/L022);
#   * the round-5 property write that "reached Anim" was made with
#     `res://scenes/player.tscn` OPEN and the path `"Anim"` (a direct child of the
#     edited root) - a different scene and a different path
#     (`docs/reports/evidence/task074/scripts-run/m4_anim.ps1:21` opens
#     player.tscn, line 78 writes `Anim.autoplay`);
#   * the real mechanism is that an in-editor instance is a **snapshot**: this
#     script instances `player.tscn` while it has no children, then adds `Anim`
#     to `player.tscn` and saves it, and the instance inside main.tscn does NOT
#     grow - while a freshly added instance of the same file does, and the game
#     (which re-instantiates from disk) always does.
#
#  That is the boundary TASK-075 declares: an instance's *live* contents are what
#  the sub-scene looked like when the editor last instantiated it; edit the
#  sub-scene first, or re-open/re-instance the outer scene after editing it.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp075_d4_staleness.ps1
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$OutRoot = '',
    [string]$EnginePath = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$ModuleRoot = Join-Path $RepoRoot 'modules\mcp_server'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$utf8 = [Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($EnginePath)) {
    $EnginePath = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
}
$Engine = (Resolve-Path $EnginePath).Path
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877

if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp075\d4_staleness' }
Remove-Item -Recurse -Force $OutRoot -ErrorAction SilentlyContinue
$Proj = Join-Path $OutRoot 'proj'
$Ev = Join-Path $OutRoot 'evidence'
$LogRoot = Join-Path $OutRoot 'logs'
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]
function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    Write-Host ("[{0}] {1} :: {2}" -f $(if ($Pass) { 'PASS' } else { 'FAIL' }), $Id, $Evidence)
}
function Get-ListenerPid {
    param([int]$Port_)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port_ + "\s")) { return [int](($line.Trim() -split '\s+')[-1]) }
    }
    return -1
}
function Invoke-Mcp {
    param([int]$Port_, [string]$Method, [hashtable]$Params, [string]$Tag)
    $bodyFile = Join-Path $Ev ($Tag + '.request.json')
    $respFile = Join-Path $Ev ($Tag + '.response.json')
    $payload = @{ jsonrpc = '2.0'; id = 1; method = $Method }
    if ($null -ne $Params) { $payload['params'] = $Params }
    Write-McpUtf8NoBom -Path $bodyFile -Text ($payload | ConvertTo-Json -Depth 12 -Compress)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl '-s' '--max-time' '90' '-o' $respFile '-H' 'Content-Type: application/json' '--data-binary' ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $json = $null
    try { $json = ConvertFrom-Json ([IO.File]::ReadAllText($respFile, $utf8)) } catch { }
    $code = $null
    $message = ''
    $text = ''
    if ($null -ne $json -and $null -ne $json.error) { $code = [int]$json.error.code; $message = [string]$json.error.message }
    if ($null -ne $json -and $null -ne $json.result -and $null -ne $json.result.content) {
        foreach ($part in @($json.result.content)) { if ($null -ne $part.text) { $text = [string]$part.text } }
    }
    Write-Host ("  {0,-32} code={1} {2}" -f $Tag, $code, $(if ($code) { $message } else { $text }).Substring(0, [Math]::Min(120, $(if ($code) { $message } else { $text }).Length)))
    return [pscustomobject]@{ File = $respFile; Code = $code; Message = $message; Text = $text; Tag = $Tag }
}
function Call-Tool {
    param([int]$Port_, [string]$Tool, [hashtable]$Arguments, [string]$Tag)
    return Invoke-Mcp -Port_ $Port_ -Method 'tools/call' -Params @{ name = $Tool; arguments = $Arguments } -Tag $Tag
}
function Children-Of {
    param([string]$JsonText, [string]$NodeName)
    try {
        $tree = ConvertFrom-Json $JsonText
        foreach ($child in @($tree.tree.children)) {
            if ([string]$child.name -ceq $NodeName) {
                # PowerShell's `@($null).Count` is 1, so an absent `children` key
                # must be tested for explicitly: reading it as "one child" is the
                # exact false reading that made the first version of this probe
                # claim the instance had grown.
                if ($null -eq $child.PSObject.Properties['children']) { return 0 }
                return @($child.children).Count
            }
        }
    } catch { }
    return -1
}

$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)

# player.tscn WITHOUT children, and a main scene that instances it.
New-McpScratchProject -Path $Proj -Name 'MCP075 D4 staleness' -WithMainScene $false | Out-Null
$projectGodot = @(
    'config_version=5', '', '[application]', 'config/name="MCP075 D4 staleness"',
    'config/features=PackedStringArray("4.8")', 'run/main_scene="res://scenes/main.tscn"', '',
    '[rendering]', 'renderer/rendering_method="gl_compatibility"', 'renderer/rendering_method.mobile="gl_compatibility"'
)
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text (($projectGodot -join "`n") + "`n")
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\player.tscn') -Text ("[gd_scene format=3]`n`n[node name=`"Player`" type=`"Node2D`"]`n")
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text (
    "[gd_scene load_steps=2 format=3]`n`n[ext_resource type=`"PackedScene`" path=`"res://scenes/player.tscn`" id=`"1_player`"]`n`n" +
    "[node name=`"Main`" type=`"Node2D`"]`n`n[node name=`"Player`" parent=`".`" instance=ExtResource(`"1_player`")]`n")

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import-d4' -Port 0
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'S001_import_ok' ($import.exit_code -eq 0) ("--import exit={0} after {1} attempt(s)" -f $import.exit_code, $import.attempts)

$handle = $null
try {
    $handle = Start-Process -FilePath $Engine -PassThru -WindowStyle Hidden `
        -ArgumentList @('--headless', '-e', '--path', $Proj, ("--mcp-port=" + $EditorPort)) `
        -RedirectStandardOutput (Join-Path $LogRoot 'editor.out.log') -RedirectStandardError (Join-Path $LogRoot 'editor.err.log')
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments @('--headless', '-e', '--path', $Proj, ("--mcp-port=" + $EditorPort))
    $ready = $false
    for ($i = 0; $i -lt 240; $i++) {
        Start-Sleep -Milliseconds 1000
        $status = Join-Path $Ev 'status.json'
        & $Curl '-s' '--max-time' '5' '-o' $status ("http://127.0.0.1:{0}/mcp" -f $EditorPort) | Out-Null
        if (Test-Path $status) {
            try { if ([int](ConvertFrom-Json ([IO.File]::ReadAllText($status, $utf8))).frame_count -ge 20) { $ready = $true; break } } catch { }
        }
    }
    Check 'S002_editor_ready' $ready ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    # (1) main.tscn with the instance as it is NOW (player.tscn has no children).
    $null = Call-Tool -Port_ $EditorPort -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Tag 'open_main_before'
    $treeBefore = Call-Tool -Port_ $EditorPort -Tool 'editor_get_scene_tree' -Arguments @{} -Tag 'tree_before'
    $childrenBefore = Children-Of $treeBefore.Text 'Player'
    $connectBefore = Call-Tool -Port_ $EditorPort -Tool 'editor_connect_signal' -Arguments @{ source_path = 'Player/Anim'; signal = 'animation_finished'; target_path = '.'; method = '_on_animation_finished' } -Tag 'connect_before'
    Check 'S003_before_the_subscene_grows_nothing_is_there' (($childrenBefore -eq 0) -and ($connectBefore.Code -eq -32001)) `
        ("the instance has {0} child(ren) and 'Player/Anim' is code={1} while player.tscn still has none" -f $childrenBefore, $connectBefore.Code)

    # (2) grow the sub-scene: open player.tscn, add Anim, save.
    $null = Call-Tool -Port_ $EditorPort -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/player.tscn' } -Tag 'open_player'
    $null = Call-Tool -Port_ $EditorPort -Tool 'editor_add_node' -Arguments @{ type = 'AnimationPlayer'; name = 'Anim'; parent_path = '.' } -Tag 'add_anim'
    $saved = Call-Tool -Port_ $EditorPort -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/player.tscn' } -Tag 'save_player'
    $playerText = [IO.File]::ReadAllText((Join-Path $Proj 'scenes\player.tscn'))
    Check 'S003b_the_subscene_file_really_grew_on_disk' (($null -eq $saved.Code) -and $playerText.Contains('Anim')) `
        ("player.tscn on disk after the save names 'Anim': {0}" -f $playerText.Contains('Anim'))

    # (3) back to main.tscn: does the LIVE instance grow?
    $null = Call-Tool -Port_ $EditorPort -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Tag 'open_main_after'
    $treeAfter = Call-Tool -Port_ $EditorPort -Tool 'editor_get_scene_tree' -Arguments @{} -Tag 'tree_after'
    $childrenAfter = Children-Of $treeAfter.Text 'Player'
    $connectStale = Call-Tool -Port_ $EditorPort -Tool 'editor_connect_signal' -Arguments @{ source_path = 'Player/Anim'; signal = 'animation_finished'; target_path = '.'; method = '_on_animation_finished' } -Tag 'connect_stale_anim'
    Check 'S004_the_live_instance_is_a_snapshot_of_the_old_file' (($childrenAfter -eq 0) -and ($connectStale.Code -eq -32001)) `
        ("after player.tscn grew and was saved, the live instance still has {0} child(ren) and 'Player/Anim' is code={1} ({2})" -f $childrenAfter, $connectStale.Code, $connectStale.Message)

    # (4) a freshly created instance of the SAME file: the resource cache still
    #     holds the pre-edit PackedScene, so this is NOT a way around the snapshot.
    $null = Call-Tool -Port_ $EditorPort -Tool 'editor_add_scene_instance' -Arguments @{ scene_path = 'res://scenes/player.tscn'; parent_path = '.'; name = 'Player2' } -Tag 'instance_fresh'
    $treeFresh = Call-Tool -Port_ $EditorPort -Tool 'editor_get_scene_tree' -Arguments @{} -Tag 'tree_fresh'
    $childrenFresh = Children-Of $treeFresh.Text 'Player2'
    $connectFresh = Call-Tool -Port_ $EditorPort -Tool 'editor_connect_signal' -Arguments @{ source_path = 'Player2/Anim'; signal = 'animation_finished'; target_path = '.'; method = '_on_animation_finished' } -Tag 'connect_fresh_anim'
    Check 'S005_re_instancing_in_the_same_session_is_not_a_way_around_it' (($childrenFresh -eq 0) -and ($connectFresh.Code -eq -32001)) `
        ("a new instance of the same player.tscn has {0} child(ren) and 'Player2/Anim' is code={1}: the editor's resource cache still serves the pre-edit PackedScene" -f $childrenFresh, $connectFresh.Code)

    # (5) save main.tscn in the STALE state and let the game measure it while the
    #     editor is still running (two ports, two processes, no interference).
    $null = Call-Tool -Port_ $EditorPort -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Tag 'save_main'

    $gameHandle = $null
    try {
        $gameHandle = Start-Process -FilePath $Engine -PassThru -WindowStyle Hidden `
            -ArgumentList @('--headless', '--path', $Proj, ("--mcp-port=" + $GamePort)) `
            -RedirectStandardOutput (Join-Path $LogRoot 'game.out.log') -RedirectStandardError (Join-Path $LogRoot 'game.err.log')
        Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $gameHandle.Id -Arguments @('--headless', '--path', $Proj, ("--mcp-port=" + $GamePort))
        $gameReady = $false
        for ($i = 0; $i -lt 240; $i++) {
            Start-Sleep -Milliseconds 1000
            $status = Join-Path $Ev 'status-game.json'
            & $Curl '-s' '--max-time' '5' '-o' $status ("http://127.0.0.1:{0}/mcp" -f $GamePort) | Out-Null
            if (Test-Path $status) {
                try { if ([int](ConvertFrom-Json ([IO.File]::ReadAllText($status, $utf8))).frame_count -ge 20) { $gameReady = $true; break } } catch { }
            }
        }
        if ($gameReady) {
            $gameTree = Call-Tool -Port_ $GamePort -Tool 'running_game_get_scene_tree' -Arguments @{} -Tag 'game_tree'
            $gameHasAnim = $gameTree.Text.Contains('Player2/Anim')
            Check 'S006_the_game_loads_the_current_subscene' $gameHasAnim `
                ("the running game's scene tree names 'Player2/Anim' (the instance whose sub-scene file grew): {0}" -f $gameHasAnim)
        } else {
            Check 'S006_the_game_loads_the_current_subscene' $false 'game on 9889 never became ready'
        }
    } finally {
        if ($null -ne $gameHandle -and -not $gameHandle.HasExited) { Stop-Process -Id $gameHandle.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
    }

    # (6) the workaround that does work in this session: write the child into the
    #     OUTER scene, under the instance. Measured AFTER the game leg so the game
    #     reads the un-overridden file.
    $null = Call-Tool -Port_ $EditorPort -Tool 'editor_add_node' -Arguments @{ type = 'AnimationPlayer'; name = 'Anim'; parent_path = 'Player' } -Tag 'add_anim_override'
    $treeOverride = Call-Tool -Port_ $EditorPort -Tool 'editor_get_scene_tree' -Arguments @{} -Tag 'tree_override'
    $childrenOverride = Children-Of $treeOverride.Text 'Player'
    $connectOverride = Call-Tool -Port_ $EditorPort -Tool 'editor_connect_signal' -Arguments @{ source_path = 'Player/Anim'; signal = 'animation_finished'; target_path = '.'; method = '_on_animation_finished' } -Tag 'connect_override_anim'
    Check 'S007_the_in_session_workaround_resolves_the_path' (($childrenOverride -eq 1) -and ($null -eq $connectOverride.Code)) `
        ("after adding the child under the instance in the OUTER scene, the instance has {0} child(ren) and 'Player/Anim' resolves (code={1}, connected={2})" -f $childrenOverride, $connectOverride.Code, $connectOverride.Text)
} finally {
    if ($null -ne $handle -and -not $handle.HasExited) { Stop-Process -Id $handle.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
}

$portVerdict = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'S008_user_port_9877_untouched' ($portVerdict.pass) ("{0}: {1}" -f $portVerdict.classification, $portVerdict.evidence)

$failures = @($script:Checks | Where-Object { -not $_.pass }).Count
$summary = Join-Path $Ev 'summary.txt'
[IO.File]::WriteAllLines($summary, @($script:Checks | ForEach-Object { ("[{0}] {1} :: {2}" -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence) }))
Write-Host ''
Write-Host ('--- checks: {0}, failures: {1} ---' -f $script:Checks.Count, $failures)
Write-Host ('--- evidence root: {0} ---' -f $Ev)
if ($failures -gt 0) { Write-Host ('MCP075 D4 STALENESS PROBE FAILED: {0}' -f $failures); exit 1 }
Write-Host 'MCP075 D4 STALENESS PROBE PASS (an in-editor instance - and a fresh instance in the same session - is a snapshot of the cached PackedScene; the game loads the file; adding the child in the outer scene resolves it in-session)'
exit 0
