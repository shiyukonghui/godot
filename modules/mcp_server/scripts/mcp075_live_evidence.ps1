# =============================================================================
#  mcp075_live_evidence.ps1 -- TASK-075 live evidence (D2 / new read tool / D4 / D5)
#
#  One script, two phases, so the "before" and the "after" are the SAME requests
#  against the SAME scratch project and can be compared line by line:
#
#    -Phase before   the binary as it is (the D2 defect is live)
#    -Phase after    the binary built from TASK-075's sources (fixed)
#
#  What it drives (editor 9888 / game 9889; the user's 9877 is guarded):
#
#   D2  a two-node batch with a script whose `extends` does not match the node's
#       root type (Node2D node + `extends Area2D` script), and a one-node batch
#       with a compatible script. Full response bodies land on disk (curl
#       `-s -o`), so the two can be compared verbatim. The scene is saved and the
#       saved text is read back with a tool; then the game process is started and
#       the engine's own stderr is counted for the mismatch message, and the one
#       script that really instantiated is read through a game-side property read.
#
#   D4  a main scene that instantiates a sub-scene at LOAD time (written by hand)
#       plus one instance created by `editor_add_scene_instance` at run time;
#       three tools are pointed at `.../Anim` on both.
#
#   D5  a TileMapLayer + `project_create_resource{type:TileSet}` + an attempt to
#       assign it + `editor_get_tilemap_info` + `editor_set_tilemap_cell`.
#
#   read  `project_read_text_file`: write -> read -> three-way sha256, the four
#         refusals, the `max_bytes` omission and the non-UTF-8 refusal.
#
#  Every response is written by curl.exe itself (PLAYBOOK section 7.1: never a
#  PowerShell pipeline). Ports and the user's editor are guarded.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp075_live_evidence.ps1 -Phase before
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp075_live_evidence.ps1 -Phase after
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [ValidateSet('before', 'after')][string]$Phase = 'after',
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

if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $env:TEMP ('mcp075\' + $Phase) }
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
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}
function Get-Sha {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '<absent>' }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}
function Get-ListenerPid {
    param([int]$Port_)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port_ + "\s")) { return [int](($line.Trim() -split '\s+')[-1]) }
    }
    return -1
}
function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $handle = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $Arguments
    return $handle
}
function Stop-Engine {
    param($Handle)
    if ($null -ne $Handle -and -not $Handle.HasExited) {
        Stop-Process -Id $Handle.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
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

# One JSON-RPC request. Returns file/bytes/sha/json plus the raw error fields.
function Invoke-Mcp {
    param([int]$Port_, [string]$Method, [hashtable]$Params, [string]$Tag)
    $bodyFile = Join-Path $Ev ($Tag + '.request.json')
    $respFile = Join-Path $Ev ($Tag + '.response.json')
    $payload = @{ jsonrpc = '2.0'; id = 1; method = $Method }
    if ($null -ne $Params) { $payload['params'] = $Params }
    Write-McpUtf8NoBom -Path $bodyFile -Text ($payload | ConvertTo-Json -Depth 12 -Compress)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl '-s' '--max-time' '90' '-o' $respFile '-H' 'Content-Type: application/json' '--data-binary' ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = Get-Sha $respFile
    $json = $null
    try { $json = ConvertFrom-Json ([IO.File]::ReadAllText($respFile, $utf8)) } catch { }
    $code = $null
    $message = ''
    $suggestion = ''
    if ($null -ne $json -and $null -ne $json.error) {
        $code = [int]$json.error.code
        $message = [string]$json.error.message
        if ($null -ne $json.error.data) { $suggestion = [string]$json.error.data.suggestion }
    }
    $text = ''
    if ($null -ne $json -and $null -ne $json.result -and $null -ne $json.result.content) {
        foreach ($part in @($json.result.content)) { if ($null -ne $part.text) { $text = [string]$part.text } }
    }
    $result = [pscustomobject]@{
        File = $respFile; Request = $bodyFile; Bytes = $bytes.Length; Sha256 = $sha
        Json = $json; Code = $code; Message = $message; Suggestion = $suggestion; Text = $text; Tag = $Tag
    }
    $short = if ($null -ne $code) { ('code={0} {1}' -f $code, $message) } else { $text }
    Write-Host ("  {0,-42} bytes={1,-6} sha={2} {3}" -f $Tag, $result.Bytes, $sha.Substring(0, 12), $short.Substring(0, [Math]::Min(150, $short.Length)))
    return $result
}
function Call-Tool {
    param([int]$Port_, [string]$Tool, [hashtable]$Arguments, [string]$Tag)
    return Invoke-Mcp -Port_ $Port_ -Method 'tools/call' -Params @{ name = $Tool; arguments = $Arguments } -Tag $Tag
}

$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)

# ---------------------------------------------------------------------------
#  The scratch project: written by hand so the sub-scene really exists at LOAD
#  time (D4's ground truth), with one incompatible and one compatible script.
# ---------------------------------------------------------------------------
New-McpScratchProject -Path $Proj -Name ('MCP075 live evidence ' + $Phase) -WithMainScene $false | Out-Null
$projectGodot = @(
    'config_version=5',
    '',
    '[application]',
    ('config/name="MCP075 live evidence ' + $Phase + '"'),
    'config/features=PackedStringArray("4.8")',
    'run/main_scene="res://scenes/main.tscn"',
    '',
    '[rendering]',
    'renderer/rendering_method="gl_compatibility"',
    'renderer/rendering_method.mobile="gl_compatibility"'
)
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text (($projectGodot -join "`n") + "`n")

# `coin.gd` extends Area2D: incompatible with the Node2D nodes of the main scene.
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scripts\coin.gd') -Text "extends Area2D`n`nvar value := 5`n"
# `ok.gd` extends Node2D: the compatible control (and a game-side readable marker).
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scripts\ok.gd') -Text "extends Node2D`n`nvar marker := 75`n"

$player = @(
    '[gd_scene format=3]',
    '',
    '[node name="Player" type="Node2D"]',
    '',
    '[node name="Anim" type="AnimationPlayer" parent="."]'
)
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\player.tscn') -Text (($player -join "`n") + "`n")

$main = @(
    '[gd_scene load_steps=2 format=3]',
    '',
    '[ext_resource type="PackedScene" path="res://scenes/player.tscn" id="1_player"]',
    '',
    '[node name="Main" type="Node2D"]',
    '',
    '[node name="Player" parent="." instance=ExtResource("1_player")]'
)
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text (($main -join "`n") + "`n")

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name ('import-' + $Phase) -Port 0
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'L001_import_ok' ($import.exit_code -eq 0) ("--import exit={0} after {1} attempt(s)" -f $import.exit_code, $import.attempts)

$editorHandle = $null
$gameHandle = $null
try {
    # -----------------------------------------------------------------------
    #  editor endpoint
    # -----------------------------------------------------------------------
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, ("--mcp-port=" + $EditorPort)) -LogName 'editor'
    Check 'L002_editor_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $listEd = Invoke-Mcp -Port_ $EditorPort -Method 'tools/list' -Params @{} -Tag 'editor_tools_list'
    $liveEd = @{}
    foreach ($tool in $listEd.Json.result.tools) { $liveEd[[string]$tool.name] = $true }
    $hasRead = $liveEd.ContainsKey('project_read_text_file')
    if ($Phase -eq 'before') {
        Check 'L003_read_tool_absent_before' (-not $hasRead) ("live editor tools/list carries {0} tool(s); project_read_text_file present={1}" -f $liveEd.Count, $hasRead)
    } else {
        Check 'L003_read_tool_present_after' $hasRead ("live editor tools/list carries {0} tool(s); project_read_text_file present={1}" -f $liveEd.Count, $hasRead)
    }

    $open = Call-Tool -Port_ $EditorPort -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Tag 'editor_open_main'
    Check 'L004_scene_opened' (($null -eq $open.Code) -and $open.Text.Contains('"opened":true')) ("open response: {0}" -f ($open.Text -replace "`n", ' '))

    # -----------------------------------------------------------------------
    #  D2: two nodes, one incompatible script; then the compatible control.
    # -----------------------------------------------------------------------
    $addBad = Call-Tool -Port_ $EditorPort -Tool 'editor_add_node' -Arguments @{ type = 'Node2D'; name = 'Bad'; parent_path = '.' } -Tag 'add_bad'
    $addBad2 = Call-Tool -Port_ $EditorPort -Tool 'editor_add_node' -Arguments @{ type = 'Node2D'; name = 'Bad2'; parent_path = '.' } -Tag 'add_bad2'
    $addBad3 = Call-Tool -Port_ $EditorPort -Tool 'editor_add_node' -Arguments @{ type = 'Node2D'; name = 'Bad3'; parent_path = '.' } -Tag 'add_bad3'
    $addGood = Call-Tool -Port_ $EditorPort -Tool 'editor_add_node' -Arguments @{ type = 'Node2D'; name = 'Good'; parent_path = '.' } -Tag 'add_good'

    $d2Bad = Call-Tool -Port_ $EditorPort -Tool 'editor_set_node_script_batch' -Arguments @{ node_paths = @('Bad', 'Bad2', 'Bad3', 'Good'); script_path = 'res://scripts/coin.gd' } -Tag 'd2_batch_incompatible'
    $d2BadText = $d2Bad.Text
    if ([string]::IsNullOrWhiteSpace($d2BadText)) { $d2BadText = $d2Bad.Message }
    $readableInBody = $d2BadText.Contains('readable')
    if ($Phase -eq 'before') {
        Check 'L010_d2_before_reports_attached_and_silent' `
            (($null -eq $d2Bad.Code) -and $d2BadText.Contains('attached') -and (-not $readableInBody)) `
            ("no error; body carries 'attached'={0}; body carries 'readable'={1}; sha={2}" -f $d2BadText.Contains('attached'), $readableInBody, $d2Bad.Sha256)
    } else {
        Check 'L010_d2_after_refuses_incompatible' `
            (($d2Bad.Code -eq -32000) -and (-not [string]::IsNullOrWhiteSpace($d2Bad.Suggestion)) -and ($d2BadText -notmatch '"attached":true')) `
            ("code={0}; message={1}; suggestion={2}; sha={3}" -f $d2Bad.Code, $d2Bad.Message, $d2Bad.Suggestion, $d2Bad.Sha256)
    }

    $d2Good = Call-Tool -Port_ $EditorPort -Tool 'editor_set_node_script_batch' -Arguments @{ node_paths = @('Good'); script_path = 'res://scripts/ok.gd' } -Tag 'd2_batch_compatible'
    $d2GoodText = $d2Good.Text
    $goodReadable = $d2GoodText.Contains('"readable":true')
    if ($Phase -eq 'before') {
        Check 'L011_d2_before_compatible_control' `
            (($null -eq $d2Good.Code) -and $d2GoodText.Contains('"attached":true')) `
            ("no error; body carries attached:true={0}; body carries readable:true={1}; sha={2}" -f $d2GoodText.Contains('"attached":true'), $goodReadable, $d2Good.Sha256)
    } else {
        Check 'L011_d2_after_compatible_control_is_readable' `
            (($null -eq $d2Good.Code) -and $d2GoodText.Contains('"attached":true') -and $goodReadable) `
            ("no error; attached:true={0}; readable:true={1}; sha={2}" -f $d2GoodText.Contains('"attached":true'), $goodReadable, $d2Good.Sha256)
    }

    # The singular tool shares the same silent path; same two cases.
    $singleBad = Call-Tool -Port_ $EditorPort -Tool 'editor_set_node_script' -Arguments @{ node_path = 'Bad'; script_path = 'res://scripts/coin.gd' } -Tag 'd2_single_incompatible'
    if ($Phase -eq 'before') {
        Check 'L012_d2_before_single_attached_true' (($null -eq $singleBad.Code) -and $singleBad.Text.Contains('"attached":true')) `
            ("no error; attached:true={0}; sha={1}" -f $singleBad.Text.Contains('"attached":true'), $singleBad.Sha256)
    } else {
        Check 'L012_d2_after_single_refuses' (($singleBad.Code -eq -32000) -and (-not [string]::IsNullOrWhiteSpace($singleBad.Suggestion))) `
            ("code={0}; message={1}; suggestion={2}" -f $singleBad.Code, $singleBad.Message, $singleBad.Suggestion)
    }

    # -----------------------------------------------------------------------
    #  D4: sub-scene internals, load-time instance vs editor-created instance
    # -----------------------------------------------------------------------
    $tree1 = Call-Tool -Port_ $EditorPort -Tool 'editor_get_scene_tree' -Arguments @{} -Tag 'd4_tree_after_open'
    $tree1Json = $null
    try { $tree1Json = ConvertFrom-Json $tree1.Text } catch { }
    $playerChildren = $null
    $animSeen = $false
    $player2Seen = $false
    if ($null -ne $tree1Json) {
        $world = $null
        foreach ($child in @($tree1Json.tree.children)) { if ([string]$child.name -ceq 'Player') { $world = $child } }
        if ($null -ne $world) { $playerChildren = @($world.children).Count }
        $animSeen = $tree1.Text.Contains('"Anim"')
    }
    Check 'L020_d4_tree_shows_load_time_instance_internals' `
        (($null -ne $playerChildren) -and ($playerChildren -ge 1) -and $animSeen) `
        ("editor_get_scene_tree: World/Player children={0}; 'Anim' anywhere in the tree={1}; sha={2}" -f $playerChildren, $animSeen, $tree1.Sha256)

    $propD4 = Call-Tool -Port_ $EditorPort -Tool 'editor_get_node_properties' -Arguments @{ path = 'Player/Anim'; properties = @('autoplay') } -Tag 'd4_get_anim_autoplay'
    $setD4 = Call-Tool -Port_ $EditorPort -Tool 'editor_set_node_property' -Arguments @{ path = 'Player/Anim'; property = 'autoplay'; value = 'run' } -Tag 'd4_set_anim_autoplay'
    $connD4 = Call-Tool -Port_ $EditorPort -Tool 'editor_connect_signal' -Arguments @{ source_path = 'Player/Anim'; signal = 'animation_finished'; target_path = '.'; method = '_on_animation_finished' } -Tag 'd4_connect_anim'
    Check 'L021_d4_three_tools_on_the_same_path' `
        (($null -eq $setD4.Code) -and ($null -eq $connD4.Code)) `
        ("get properties code={0}; set property code={1} body={2}; connect signal code={3} msg={4}" -f `
            $propD4.Code, $setD4.Code, ($setD4.Text -replace "`n", ' '), $connD4.Code, $connD4.Message)

    $inst2 = Call-Tool -Port_ $EditorPort -Tool 'editor_add_scene_instance' -Arguments @{ scene_path = 'res://scenes/player.tscn'; parent_path = '.'; name = 'Player2' } -Tag 'd4_add_instance_runtime'
    $tree2 = Call-Tool -Port_ $EditorPort -Tool 'editor_get_scene_tree' -Arguments @{} -Tag 'd4_tree_after_runtime_instance'
    $player2Children = $null
    try {
        $t2 = ConvertFrom-Json $tree2.Text
        foreach ($child in @($t2.tree.children)) { if ([string]$child.name -ceq 'Player2') { $player2Children = @($child.children).Count } }
    } catch { }
    $conn2 = Call-Tool -Port_ $EditorPort -Tool 'editor_connect_signal' -Arguments @{ source_path = 'Player2/Anim'; signal = 'animation_finished'; target_path = '.'; method = '_on_animation_finished' } -Tag 'd4_connect_player2_anim'
    Check 'L022_d4_runtime_instance_reproduced' `
        ($null -ne $player2Children) `
        ("editor_add_scene_instance returned code={0}; world/Player2 children={1} (a miss means the instance was not added); Player2/Anim connect code={2}" -f `
            $inst2.Code, $player2Children, $conn2.Code)

    # -----------------------------------------------------------------------
    #  D5: TileSet without an atlas source
    # -----------------------------------------------------------------------
    $addLayer = Call-Tool -Port_ $EditorPort -Tool 'editor_add_node' -Arguments @{ type = 'TileMapLayer'; name = 'Layer'; parent_path = '.' } -Tag 'd5_add_tilemaplayer'
    $mkTileSet = Call-Tool -Port_ $EditorPort -Tool 'project_create_resource' -Arguments @{ path = 'res://tiles/empty_tileset.tres'; type = 'TileSet' } -Tag 'd5_create_empty_tileset'
    $info0 = Call-Tool -Port_ $EditorPort -Tool 'editor_get_tilemap_info' -Arguments @{ node_path = 'Layer' } -Tag 'd5_info_before_assign'
    $attach = Call-Tool -Port_ $EditorPort -Tool 'editor_add_resource_to_node_property' -Arguments @{ node_path = 'Layer'; property = 'tile_set'; resource_type = 'TileSet'; resource_properties = @{ } } -Tag 'd5_attach_tileset'
    $setProp = Call-Tool -Port_ $EditorPort -Tool 'editor_set_node_property' -Arguments @{ path = 'Layer'; property = 'tile_set'; value = @{ type = 'TileSet'; path = 'res://tiles/empty_tileset.tres' } } -Tag 'd5_set_tileset_property'
    $info1 = Call-Tool -Port_ $EditorPort -Tool 'editor_get_tilemap_info' -Arguments @{ node_path = 'Layer' } -Tag 'd5_info_after_assign'
    $setCell = Call-Tool -Port_ $EditorPort -Tool 'editor_set_tilemap_cell' -Arguments @{ node_path = 'Layer'; x = 0; y = 0; source_id = 0; atlas_coords = @{ x = 0; y = 0 } } -Tag 'd5_set_cell'
    Check 'L030_d5_characterised' `
        ((($mkTileSet.Text -replace "`n", ' ').Contains('"properties_set":[]')) -and (($info1.Text -replace "`n", ' ').Contains('"has_tile_set":true')) -and ($setCell.Code -eq -32602)) `
        ("create_tileset code={0} props_set={1}; info_before has_tile_set={2}; attach code={3} msg={4}; set_property code={5} msg={6}; info_after has_tile_set={7}; set_cell code={8} msg={9}" -f `
            $mkTileSet.Code, (($mkTileSet.Text -replace "`n", ' ')), (($info0.Text -replace "`n", ' ')), $attach.Code, ($attach.Message -replace "`n", ' '), `
            $setProp.Code, ($setProp.Message -replace "`n", ' '), (($info1.Text -replace "`n", ' ')), $setCell.Code, ($setCell.Message -replace "`n", ' '))

    # -----------------------------------------------------------------------
    #  the write -> read chain and the new read tool's edge cases
    # -----------------------------------------------------------------------
    $slot = '{"slot":1,"coins":3}'
    $wrote = Call-Tool -Port_ $EditorPort -Tool 'project_write_text_file' -Arguments @{ path = 'res://save/slot1.json'; content = $slot; overwrite = $true } -Tag 'read_write_receipt'
    $onDisk = Join-Path $Proj 'save\slot1.json'
    $diskSha = if (Test-Path $onDisk) { Get-Sha $onDisk } else { '<absent>' }
    $receiptSha = ''
    try { $receiptSha = [string](ConvertFrom-Json $wrote.Text).sha256 } catch { }
    Check 'L040_write_receipt_sha_matches_disk' (($diskSha -ne '<absent>') -and ($receiptSha -ceq $diskSha)) `
        ("write receipt sha256={0}; disk sha256={1}; bytes={2}" -f $receiptSha, $diskSha, $(if (Test-Path $onDisk) { (Get-Item $onDisk).Length } else { -1 }))

    if ($Phase -eq 'before') {
        $beforeRead = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://save/slot1.json' } -Tag 'read_tool_before'
        Check 'L041_read_tool_before_is_method_not_found' ($beforeRead.Code -eq -32601) `
            ("code={0}; message={1}; sha={2}" -f $beforeRead.Code, $beforeRead.Message, $beforeRead.Sha256)
    } else {
        $read = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://save/slot1.json' } -Tag 'read_tool_roundtrip'
        $readJson = $null
        try { $readJson = ConvertFrom-Json $read.Text } catch { }
        $readSha = ''
        if ($null -ne $readJson) { $readSha = [string]$readJson.sha256 }
        Check 'L041_read_tool_three_way_sha' (($null -ne $readJson) -and ($readSha -ceq $receiptSha) -and ($readSha -ceq $diskSha)) `
            ("read sha256={0}; write receipt sha256={1}; disk sha256={2}; size={3}; text matches={4}" -f `
                $readSha, $receiptSha, $diskSha, $(if ($null -ne $readJson) { $readJson.size } else { -1 }), $(if ($null -ne $readJson) { ([string]$readJson.text -ceq $slot) } else { $false }))

        $outside = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'user://outside.txt' } -Tag 'read_refuse_outside_res'
        Check 'L042_read_refuses_outside_res' (($outside.Code -eq -32602) -and (-not [string]::IsNullOrWhiteSpace($outside.Suggestion))) `
            ("code={0}; message={1}; suggestion={2}" -f $outside.Code, $outside.Message, $outside.Suggestion)

        $upward = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://../secrets.txt' } -Tag 'read_refuse_dotdot'
        Check 'L043_read_refuses_dotdot' ($upward.Code -eq -32602) `
            ("code={0}; message={1}" -f $upward.Code, $upward.Message)

        $absolute = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'C:/Windows/win.ini' } -Tag 'read_refuse_absolute'
        Check 'L044_read_refuses_absolute' ($absolute.Code -eq -32602) `
            ("code={0}; message={1}" -f $absolute.Code, $absolute.Message)

        $directory = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://scenes' } -Tag 'read_refuse_directory'
        Check 'L045_read_refuses_directory' ($directory.Code -eq -32602) `
            ("code={0}; message={1}; suggestion={2}" -f $directory.Code, $directory.Message, $directory.Suggestion)

        $missing = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://save/no_such_file.json' } -Tag 'read_refuse_missing'
        Check 'L046_read_missing_is_32001_with_suggestion' (($missing.Code -eq -32001) -and (-not [string]::IsNullOrWhiteSpace($missing.Suggestion))) `
            ("code={0}; message={1}; suggestion={2}" -f $missing.Code, $missing.Message, $missing.Suggestion)

        $big = ('x' * 4096)
        $bigWrite = Call-Tool -Port_ $EditorPort -Tool 'project_write_text_file' -Arguments @{ path = 'res://save/big.txt'; content = $big; overwrite = $true } -Tag 'read_write_big'
        $omitted = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://save/big.txt'; max_bytes = 16 } -Tag 'read_big_omitted'
        $omittedJson = $null
        try { $omittedJson = ConvertFrom-Json $omitted.Text } catch { }
        $included = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://save/big.txt'; max_bytes = 8192 } -Tag 'read_big_included'
        $includedJson = $null
        try { $includedJson = ConvertFrom-Json $included.Text } catch { }
        Check 'L047_max_bytes_omits_then_includes' `
            (($null -ne $omittedJson) -and ([bool]$omittedJson.text_omitted) -and ($null -ne $omittedJson.reason) -and ($null -ne $includedJson) -and (-not [bool]$includedJson.text_omitted) -and ([string]$includedJson.text -ceq $big)) `
            ("max_bytes=16 -> text_omitted={0} reason={1} size={2} sha={3}; max_bytes=8192 -> text_omitted={4} text length={5}" -f `
                $(if ($null -ne $omittedJson) { $omittedJson.text_omitted } else { '<none>' }), $(if ($null -ne $omittedJson) { $omittedJson.reason } else { '' }), `
                $(if ($null -ne $omittedJson) { $omittedJson.size } else { -1 }), $(if ($null -ne $omittedJson) { $omittedJson.sha256 } else { '' }), `
                $(if ($null -ne $includedJson) { $includedJson.text_omitted } else { '<none>' }), $(if ($null -ne $includedJson) { ([string]$includedJson.text).Length } else { -1 }))

        $overLimit = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://save/big.txt'; max_bytes = 33554432 } -Tag 'read_refuse_over_limit'
        Check 'L048_max_bytes_upper_bound_refused' ($overLimit.Code -eq -32602) `
            ("code={0}; message={1}" -f $overLimit.Code, $overLimit.Message)

        # A file whose bytes are not valid UTF-8: 0xFF 0xFE is not a UTF-8 sequence.
        $binaryPath = Join-Path $Proj 'save\binary.bin'
        [IO.File]::WriteAllBytes($binaryPath, [byte[]](0x41, 0xFF, 0xFE, 0x42, 0x00, 0x43))
        $binaryRead = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://save/binary.bin' } -Tag 'read_refuse_non_utf8'
        Check 'L049_non_utf8_refused_with_suggestion' (($binaryRead.Code -eq -32000) -and (-not [string]::IsNullOrWhiteSpace($binaryRead.Suggestion))) `
            ("code={0}; message={1}; suggestion={2}" -f $binaryRead.Code, $binaryRead.Message, $binaryRead.Suggestion)
    }

    # -----------------------------------------------------------------------
    #  save the scene, read the saved text back with a tool
    # -----------------------------------------------------------------------
    $save = Call-Tool -Port_ $EditorPort -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Tag 'save_main'
    $sceneRead = Call-Tool -Port_ $EditorPort -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://scenes/main.tscn' } -Tag 'read_main_tscn'
    $sceneText = $sceneRead.Text
    $mainOnDisk = Join-Path $Proj 'scenes\main.tscn'
    Check 'L050_saved_scene_read_back' ((Test-Path $mainOnDisk) -and ($sceneText.Contains('Main'))) `
        ("editor_save_scene code={0}; disk bytes={1} sha256={2}; the read-back names Main={3}; carries scripts: coin.gd={4} ok.gd={5}" -f `
            $save.Code, (Get-Item $mainOnDisk).Length, (Get-Sha $mainOnDisk), $sceneText.Contains('Main'), $sceneText.Contains('coin.gd'), $sceneText.Contains('ok.gd'))
} finally {
    Stop-Engine $editorHandle
}

# ---------------------------------------------------------------------------
#  the game process: does the engine really drop the incompatible script?
# ---------------------------------------------------------------------------
$gameHandle = $null
try {
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, ("--mcp-port=" + $GamePort)) -LogName 'game'
    if (Wait-ForPump -Port_ $GamePort) {
        $gameGood = Call-Tool -Port_ $GamePort -Tool 'running_game_get_node_properties' -Arguments @{ node_path = 'Good'; properties = @('marker') } -Tag 'game_good_marker'
        $gameBad = Call-Tool -Port_ $GamePort -Tool 'running_game_get_node_properties' -Arguments @{ node_path = 'Bad'; properties = @('value') } -Tag 'game_bad_value'
        $goodMarker = $gameGood.Text
        Check 'L060_game_compatible_script_is_live' ($goodMarker.Contains('75')) `
            ("Good.marker read from the running game: {0}" -f ($goodMarker -replace "`n", ' '))
        Check 'L061_game_incompatible_script_is_absent' (($gameBad.Code -eq -32001) -or (($gameBad.Text -replace "`n", ' ').Contains('not found'))) `
            ("Bad.value read from the running game: code={0} {1}" -f $gameBad.Code, $gameBad.Message)
        Stop-Engine $gameHandle
    } else {
        Check 'L060_game_ready' $false ("game on {0} did not answer GET /mcp with +20 frames" -f $GamePort)
    }
} finally {
    Stop-Engine $gameHandle
}

# The engine's own message, counted in both logs: the editor is silent about the
# mismatch while the game drops the script and says so once per node.
$marker = "can't be assigned to an object of type"
$editorErr = Join-Path $LogRoot 'editor.err.log'
$gameErr = Join-Path $LogRoot 'game.err.log'
function Count-Marker {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return -1 }
    $text = [IO.File]::ReadAllText($Path)
    return ([regex]::Matches($text, [regex]::Escape($marker))).Count
}
$editorCount = Count-Marker $editorErr
$gameCount = Count-Marker $gameErr
if ($Phase -eq 'before') {
    Check 'L070_engine_message_only_in_the_game_log' (($editorCount -eq 0) -and ($gameCount -ge 1)) `
        ("editor.err.log occurrences of the engine mismatch message={0}; game.err.log occurrences={1} (one per Node2D the editor accepted an 'extends Area2D' script for)" -f $editorCount, $gameCount)
} else {
    Check 'L070_engine_message_absent_everywhere_after_the_fix' (($editorCount -eq 0) -and ($gameCount -eq 0)) `
        ("editor.err.log occurrences of the engine mismatch message={0}; game.err.log occurrences={1} (the refused attachment never reached the saved scene)" -f $editorCount, $gameCount)
}

# ---------------------------------------------------------------------------
#  the user's port and a clean finish
# ---------------------------------------------------------------------------
$portVerdict = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'L080_user_port_9877_untouched' ($portVerdict.pass) ("{0}: {1}" -f $portVerdict.classification, $portVerdict.evidence)

$failures = 0
Write-Host ''
Write-Host '--- summary ---'
foreach ($c in $script:Checks) {
    if (-not $c.pass) { $failures++ }
    Write-Host ("[{0}] {1} :: {2}" -f $(if ($c.pass) { 'PASS' } else { 'FAIL' }), $c.id, $c.evidence)
}
$summaryFile = Join-Path $Ev 'summary.txt'
[IO.File]::WriteAllLines($summaryFile, @($script:Checks | ForEach-Object { ("[{0}] {1} :: {2}" -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence) }))
Write-Host ('--- checks: {0}, failures: {1} ---' -f $script:Checks.Count, $failures)
Write-Host ('--- evidence root: {0} ---' -f $Ev)
if ($failures -gt 0) { Write-Host ('MCP075 LIVE EVIDENCE FAILED: {0}' -f $failures); exit 1 }
Write-Host ('MCP075 LIVE EVIDENCE PASS (phase ' + $Phase + ')')
exit 0