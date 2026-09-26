# =============================================================================
#  mcp008_editor_write_evidence.ps1 -- TASK-008 gate 2
#
#  Two jobs:
#    * the red -> green evidence for `editor_remove_output_log`, the group's
#      `fix_implementation_first` tool: the same three requests are sent to the
#      migration-faithful build (`-Phase redclear`) and to the fixed build
#      (`-Phase main`), same scratch project, same port, and the two response
#      bodies are compared;
#    * the three evidence classes (success / missing-parameter / bottom-layer
#      failure) plus the editor-state chains of the ten tools of
#      `editor_write_scene_editor`, on a real editor process (`-Phase main`,
#      `-Phase noplugin`).
#
#  Discipline (PLAYBOOK section 3 and section 7.1):
#    * every response body is written to a file with `curl.exe -s -o <file>`
#      (never through Out-File / a pipeline) and its sha256 is computed from the
#      bytes on disk;
#    * the scratch project is a *fresh copy* under %TEMP%; nothing is written
#      inside the repository or any user project;
#    * the engine is started on port 9888 only (9877 belongs to the user's editor
#      and is never touched), and a positive pid-same guard is printed;
#    * the file system before/after state is a sorted `path|size|sha256` list.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp008_editor_write_evidence.ps1
#    powershell ... -File mcp008_editor_write_evidence.ps1 -Phase redclear
#    powershell ... -File mcp008_editor_write_evidence.ps1 -Phase noplugin
# =============================================================================

param(
    [ValidateSet('main', 'redclear', 'noplugin', 'gamecall', 'gui')]
    [string]$Phase = 'main',
    [int]$Port = 9888,
    [switch]$KeepScratch
)

$ErrorActionPreference = 'Stop'

$RepoRoot = 'F:\RustProjects\godot-mcp-pro\code\godot'
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Scratch = Join-Path $env:TEMP 'mcp008-editor-write-scratch'
$LogRoot = Join-Path $env:TEMP 'mcp008-editor-write-logs'
$Evid = Join-Path $env:TEMP 'mcp008-editor-write-evidence'

Write-Host ("=== TASK-008 gate 2 evidence driver (phase={0}) ===" -f $Phase)

# -----------------------------------------------------------------------------
# fresh scratch project
# -----------------------------------------------------------------------------
if (Test-Path $Scratch) { Remove-Item -Recurse -Force $Scratch }
New-Item -ItemType Directory -Force -Path $Scratch, $LogRoot, $Evid | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Scratch 'scenes'), (Join-Path $Scratch 'addons\mcpreload') | Out-Null

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

# The addon is the object `editor_reload_plugin` reloads. The project file only
# enables it in the `main` and `redclear` phases; `noplugin` leaves the list out
# on purpose, which is the bottom-layer failure of that tool.
$projectLines = @(
    'config_version=5',
    '',
    '[application]',
    'config/name="MCP008 editor write scratch"',
    'config/features=PackedStringArray("4.8")',
    'run/main_scene="res://scenes/main.tscn"',
    '',
    '[rendering]',
    'renderer/rendering_method="gl_compatibility"',
    'renderer/rendering_method.mobile="gl_compatibility"'
)
if ($Phase -ne 'noplugin') {
    $projectLines += @(
        '',
        '[editor_plugins]',
        'enabled=PackedStringArray("res://addons/mcpreload/plugin.cfg")'
    )
}
# File logging makes `user://logs/godot.log` exist, which is what
# `editor_get_output_log` reads. It is a *different* object from the Output
# panel, and the `editor_remove_output_log` evidence below uses exactly that
# difference: clearing the panel must not truncate this file.
$projectLines += @(
    '',
    '[debug]',
    'file_logging/enable_file_logging=true'
)
Write-Utf8NoBom (Join-Path $Scratch 'project.godot') (($projectLines -join "`n") + "`n")

Write-Utf8NoBom (Join-Path $Scratch 'addons\mcpreload\plugin.cfg') (@(
    '[plugin]',
    'name="mcpreload"',
    'description="TASK-008 scratch addon: the object editor_reload_plugin reloads"',
    'author="mcp-server"',
    'version="1.0"',
    'script="plugin.gd"'
) -join "`n") + "`n"

Write-Utf8NoBom (Join-Path $Scratch 'addons\mcpreload\plugin.gd') (@(
    '@tool',
    'extends EditorPlugin',
    '',
    'func _enter_tree() -> void:',
    '	print("MCP008_PLUGIN_ENTER")',
    '',
    'func _exit_tree() -> void:',
    '	print("MCP008_PLUGIN_EXIT")'
) -join "`n") + "`n"

Write-Utf8NoBom (Join-Path $Scratch 'scenes\main.tscn') (@(
    '[gd_scene format=3]',
    '',
    '[node name="Main" type="Node3D"]',
    '',
    '[node name="Marker" type="MeshInstance3D" parent="."]',
    '',
    '[node name="Group" type="Node3D" parent="."]',
    '',
    '[node name="Nested" type="Node3D" parent="Group"]'
) -join "`n") + "`n"

Write-Utf8NoBom (Join-Path $Scratch 'scenes\second.tscn') (@(
    '[gd_scene format=3]',
    '',
    '[node name="Second" type="Node2D"]'
) -join "`n") + "`n"

Write-Utf8NoBom (Join-Path $Scratch 'scenes\locked.tscn') (@(
    '[gd_scene format=3]',
    '',
    '[node name="Locked" type="Node2D"]'
) -join "`n") + "`n"

# A scene whose only dependency cannot be loaded: opening it makes the editor
# write resource errors into the Output panel, which is the pre-condition of the
# `editor_remove_output_log` evidence.
Write-Utf8NoBom (Join-Path $Scratch 'scenes\broken.tscn') (@(
    '[gd_scene load_steps=2 format=3]',
    '',
    '[ext_resource type="Script" path="res://scenes/does_not_exist.gd" id="1_missing"]',
    '',
    '[node name="Broken" type="Node2D"]',
    'script = ExtResource("1_missing")'
) -join "`n") + "`n"

Write-Host ("scratch project: {0}" -f $Scratch)

# -----------------------------------------------------------------------------
# helpers
# -----------------------------------------------------------------------------
function Get-FileSnapshot {
    param([string]$Root)
    $rows = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -Path $Root -Recurse -File -Force | ForEach-Object {
        $hash = (Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash.ToLower()
        $rel = $_.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
        $rows.Add(('{0}|{1}|{2}' -f $rel, $_.Length, $hash))
    }
    return ($rows | Sort-Object)
}

function Write-Snapshot {
    param([string]$Path, [string]$Root)
    $snapshot = Get-FileSnapshot -Root $Root
    [IO.File]::WriteAllLines($Path, $snapshot, (New-Object Text.UTF8Encoding($false)))
    return $snapshot
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [string]$Label)
    $payload = @{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = @{ name = $Tool; arguments = $Arguments } } | ConvertTo-Json -Depth 8 -Compress
    $body = Join-Path $Evid ("{0}.request.json" -f $Label)
    $resp = Join-Path $Evid ("{0}.response.json" -f $Label)
    [IO.File]::WriteAllText($body, $payload, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path $resp) { Remove-Item -Force $resp }
    & curl.exe -s -o $resp -H 'Content-Type: application/json' --data-binary ('@' + $body) ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    $exit = $LASTEXITCODE
    $bytes = [IO.File]::ReadAllBytes($resp)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $resp).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] curl_exit={1} bytes={2} sha256={3}" -f $Label, $exit, $bytes.Length, $sha)
    Write-Host ("        request : {0}" -f $payload)
    Write-Host ("        response: {0}" -f $text)
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

function Assert-Payload {
    param([string]$ResponseText, [string]$Label)
    $p = Get-Payload $ResponseText
    if ($null -eq $p) {
        throw ("{0}: expected a result payload, got an error: {1}" -f $Label, ((Get-ErrorObject $ResponseText).message))
    }
    return $p
}

function Assert-Error {
    param([string]$ResponseText, [string]$Label, [int]$Code)
    $e = Get-ErrorObject $ResponseText
    if ($null -eq $e) {
        throw ("{0}: expected an error with code {1}, got a result" -f $Label, $Code)
    }
    if ($e.code -ne $Code) {
        throw ("{0}: expected code {1}, got {2} ({3})" -f $Label, $Code, $e.code, $e.message)
    }
    return $e
}

# -----------------------------------------------------------------------------
# the 9877 guard and the scratch editor
# -----------------------------------------------------------------------------
$pidBefore = -1
$lines = & netstat -ano -p TCP 2>$null
foreach ($line in $lines) {
    if ($line -match 'LISTENING' -and $line -match '[:\]]9877\s') { $pidBefore = [int](($line.Trim() -split '\s+')[-1]) }
}
Write-Host ("user editor on 9877 before: pid={0}" -f $pidBefore)

$out = Join-Path $LogRoot ("scratch-editor-{0}.out.log" -f $Phase)
$err = Join-Path $LogRoot ("scratch-editor-{0}.err.log" -f $Phase)
Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
# `gamecall` is the other process: a *game* build of the same project on 9889.
# Every one of the ten tools is scoped `editor`, so the game endpoint must not
# even carry them - and calling one must be `-32601` with no execution.
# `editor_get_output_log` reads `user://logs/godot.log`, and that file is a
# *different* object from the Output panel. In an **editor** process the project
# setting `debug/file_logging/enable_file_logging` is deliberately ignored
# (main.cpp:2300-2301 only enables it when `!editor`), so the file is created
# through the explicit `--log-file` override pointed at exactly that path.
$userDir = Join-Path $env:APPDATA 'Godot\app_userdata\MCP008 editor write scratch'
New-Item -ItemType Directory -Force -Path (Join-Path $userDir 'logs') | Out-Null
$userLogFile = Join-Path $userDir 'logs\godot.log'
# A stale log from an earlier run must not be able to stand in for this run's.
Remove-Item -Force $userLogFile -ErrorAction SilentlyContinue

$engineArgs = if ($Phase -eq 'gamecall') {
    @('--headless', '--path', $Scratch, "--mcp-port=$Port")
} elseif ($Phase -eq 'gui') {
    # `editor_capture_screenshot` needs a *rendered* viewport: under `--headless`
    # Godot uses the dummy rendering driver and `ViewportTexture::get_image()`
    # yields an empty image, which the `main` phase records as the tool's honest
    # failure. The success class therefore runs a real (short-lived) editor
    # window on the same port, moved aside and sized small.
    @('-e', '--path', $Scratch, 'res://scenes/main.tscn', "--mcp-port=$Port", '--resolution', '512x384', '--position', '80,80')
} else {
    # `Start-Process -ArgumentList <array>` joins with spaces and does not quote,
    # so the one argument that contains spaces (the user-data log path) is quoted
    # by hand.
    @('--headless', '-e', '--path', $Scratch, 'res://scenes/main.tscn', "--mcp-port=$Port", '--log-file', ('"{0}"' -f $userLogFile))
}
$proc = Start-Process -FilePath $Engine -ArgumentList $engineArgs -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
Write-Host ("scratch editor pid={0}" -f $proc.Id)

$result = @{ phase = $Phase; checks = (New-Object System.Collections.Generic.List[object]) }
function Add-Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:result.checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1} :: {2}" -f $tag, $Id, $Evidence)
}

try {
    $deadline = [DateTime]::UtcNow.AddSeconds(240)
    $ready = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $task = $client.ConnectAsync('127.0.0.1', $Port)
            if ($task.Wait(800)) { $client.Close(); $ready = $true; break }
            $client.Close()
        } catch { }
        Start-Sleep -Milliseconds 800
    }
    if (-not $ready) { throw "the scratch editor never listened on $Port; log: $(Get-Content -Raw $out)" }
    Start-Sleep -Seconds 6
    Write-Host 'scratch editor is listening'

    $before = Write-Snapshot -Path (Join-Path $Evid ("fs.before.{0}.txt" -f $Phase)) -Root $Scratch

    # -------------------------------------------------------------------------
    # PHASE gui -- the success class of editor_capture_screenshot
    # -------------------------------------------------------------------------
    if ($Phase -eq 'gui') {
        $t = Invoke-Tool -Id 700 -Tool 'editor_capture_screenshot' -Arguments @{} -Label 'success-capture-base64'
        $e = Get-ErrorObject $t
        if ($null -ne $e) {
            Add-Check 'success_capture_base64' $false ("code={0} message='{1}'" -f $e.code, $e.message)
        } else {
            $p = Assert-Payload $t 'success-capture-base64'
            $b64 = "$($p.image_base64)"
            Add-Check 'success_capture_base64' (($p.width -gt 0) -and ($p.height -gt 0) -and ($b64.Length -gt 1000)) ("width={0} height={1} base64_chars={2}" -f $p.width, $p.height, $b64.Length)
            # A base64 PNG has a PNG signature; decode the first bytes and check
            # them, so "it returned a string" is not mistaken for "it returned an
            # image".
            $decoded = [Convert]::FromBase64String($b64.Substring(0, 64))
            $signature = ($decoded[0..7] -join ',')
            Add-Check 'success_capture_base64_is_png' ($signature -eq '137,80,78,71,13,10,26,10') ("first 8 decoded bytes = {0} (PNG signature = 137,80,78,71,13,10,26,10)" -f $signature)
        }

        $t = Invoke-Tool -Id 701 -Tool 'editor_capture_screenshot' -Arguments @{ save_path = 'res://screenshots/editor.png' } -Label 'success-capture-save'
        $e = Get-ErrorObject $t
        $shot = Join-Path $Scratch 'screenshots\editor.png'
        if ($null -ne $e) {
            Add-Check 'success_capture_save' $false ("code={0} message='{1}'" -f $e.code, $e.message)
        } else {
            $p = Assert-Payload $t 'success-capture-save'
            $pngExists = Test-Path $shot
            $pngSha = if ($pngExists) { (Get-FileHash -Algorithm SHA256 -Path $shot).Hash.ToLower() } else { 'absent' }
            $pngBytes = if ($pngExists) { (Get-Item $shot).Length } else { 0 }
            $safe = $pngExists -and ($pngSha -ne 'absent')
            Add-Check 'success_capture_save' (($p.saved_path -eq 'res://screenshots/editor.png') -and $safe) ("saved_path={0} file_on_disk={1} sha256={2} bytes={3}" -f $p.saved_path, $pngExists, $pngSha, $pngBytes)
        }

        # The scratch name must not survive: the PNG is published atomically.
        $leftovers = @(Get-ChildItem -Path $Scratch -Recurse -File -Force | Where-Object { $_.Name.Contains('.mcp-tmp') })
        Add-Check 'gui_no_scratch_file_left_behind' ($leftovers.Count -eq 0) ("files matching .mcp-tmp in the project: {0}" -f $leftovers.Count)

        # The failing writer must not damage an existing PNG either.
        $t = Invoke-Tool -Id 702 -Tool 'editor_capture_screenshot' -Arguments @{ save_path = 'res://screenshots/editor.png'; } -Label 'gui-capture-overwrite'
        $shaBefore = if (Test-Path $shot) { (Get-FileHash -Algorithm SHA256 -Path $shot).Hash.ToLower() } else { 'absent' }
        Add-Check 'gui_capture_overwrite_is_still_a_png' (Test-Path $shot) ("second write: sha256={0}" -f $shaBefore)
    }

    # -------------------------------------------------------------------------
    # PHASE gamecall -- a game process must refuse every tool of this group
    # -------------------------------------------------------------------------
    if ($Phase -eq 'gamecall') {
        $groupTools = @(
            'editor_open_scene', 'editor_save_scene', 'editor_reload_plugin',
            'editor_rescan_project_filesystem', 'editor_set_node_selection',
            'editor_remove_node_selection', 'editor_add_resource_to_node_property',
            'editor_set_viewport_3d_camera', 'editor_capture_screenshot',
            'editor_remove_output_log'
        )
        $payload = @{ jsonrpc = '2.0'; id = 951; method = 'tools/list'; params = @{} } | ConvertTo-Json -Depth 8 -Compress
        $body = Join-Path $Evid 'gamecall-tools-list.request.json'
        $resp = Join-Path $Evid 'gamecall-tools-list.response.json'
        [IO.File]::WriteAllText($body, $payload, (New-Object Text.UTF8Encoding($false)))
        & curl.exe -s -o $resp -H 'Content-Type: application/json' --data-binary ('@' + $body) ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
        $listText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($resp))
        # The *positive* half of the scope guard: this really is the game endpoint
        # (23 both-scope tools), so the ten absences below are the guard working
        # and not a broken process.
        $listed = @((($listText | ConvertFrom-Json).result.tools) | ForEach-Object { $_.name })
        Add-Check 'gamecall_endpoint_serves_23_tools' ($listed.Count -eq 23) ("tools/list on {0} returned {1} tool(s)" -f $Port, $listed.Count)
        $leaked = @($groupTools | Where-Object { $listed -contains $_ })
        $leakedText = if ($leaked.Count -eq 0) { 'none' } else { $leaked -join ',' }
        Add-Check 'gamecall_group_is_absent_from_tools_list' ($leaked.Count -eq 0) ("leaked editor tools: {0}" -f $leakedText)

        foreach ($tool in $groupTools) {
            $t = Invoke-Tool -Id ("96{0}" -f $groupTools.IndexOf($tool)) -Tool $tool -Arguments @{} -Label ("gamecall-{0}" -f $tool)
            $e = Assert-Error $t ("gamecall-{0}" -f $tool) -32601
            $refused = ($t.Contains('"code":-32601')) -and (-not $t.Contains('"result"'))
            Add-Check ("gamecall_refuses_$tool") $refused ("code={0} message='{1}'" -f $e.code, $e.message)
        }
    }

    # -------------------------------------------------------------------------
    # PHASE noplugin -- the honest bottom-layer failure of editor_reload_plugin
    # -------------------------------------------------------------------------
    if ($Phase -eq 'noplugin') {
        $t = Invoke-Tool -Id 900 -Tool 'editor_reload_plugin' -Arguments @{} -Label 'bottom-reload-plugin-without-addon'
        $e = Assert-Error $t 'bottom-reload-plugin-without-addon' -32000
        Add-Check 'noplugin_reload_plugin_is_honest' (($e.data.suggestion.Length -gt 0)) ("code={0} message='{1}' suggestion='{2}'" -f $e.code, $e.message, $e.data.suggestion)
    }

    # -------------------------------------------------------------------------
    # PHASE redclear -- prime the Output panel and clear it once
    # -------------------------------------------------------------------------
    if ($Phase -eq 'redclear') {
        $t = Invoke-Tool -Id 800 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/broken.tscn' } -Label 'redclear-prime-panel'
        Write-Host ("        priming response: {0}" -f $t.Substring(0, [Math]::Min(220, $t.Length)))
        $t = Invoke-Tool -Id 801 -Tool 'editor_remove_output_log' -Arguments @{} -Label 'redclear-clear-output-log'
        Write-Host ("        RED clear response: {0}" -f $t)
        $p = Get-Payload $t
        if ($null -ne $p) {
            $wasEmpty = if ($null -eq $p.log_was_empty) { 'not-measured' } else { "$($p.log_was_empty)" }
            $isEmpty = if ($null -eq $p.log_is_empty) { 'not-measured' } else { "$($p.log_is_empty)" }
            $lie = ($p.cleared -eq $true) -and ($p.log_is_empty -ne $true) -and ($p.log_was_empty -ne $true)
            Add-Check 'redclear_reports_cleared_without_clearing' $lie ("cleared={0} log_was_empty={1} log_is_empty={2}" -f $p.cleared, $wasEmpty, $isEmpty)
        } else {
            Add-Check 'redclear_reports_cleared_without_clearing' $false ("unexpected error: {0}" -f $t)
        }
    }

    # -------------------------------------------------------------------------
    # PHASE main -- the full gate-2 sequence
    # -------------------------------------------------------------------------
    if ($Phase -eq 'main') {
        Write-Host ''
        Write-Host '========== state chain: editor_open_scene =========='
        $t = Invoke-Tool -Id 1 -Tool 'editor_get_scene_tree' -Arguments @{} -Label 'state-01-scene-before-open'
        $p = Assert-Payload $t 'state-01'
        $sceneBefore = $p.scene_path
        Add-Check 'state_scene_before_open' ($sceneBefore -eq 'res://scenes/main.tscn') ("editor_get_scene_tree.scene_path={0}" -f $sceneBefore)

        $t = Invoke-Tool -Id 2 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/second.tscn' } -Label 'success-open-scene'
        $p = Assert-Payload $t 'success-open-scene'
        Add-Check 'success_open_scene' (($p.path -eq 'res://scenes/second.tscn') -and ($p.opened -eq $true)) ("path={0} opened={1}" -f $p.path, $p.opened)

        $t = Invoke-Tool -Id 3 -Tool 'editor_get_scene_tree' -Arguments @{} -Label 'state-02-scene-after-open'
        $p = Assert-Payload $t 'state-02'
        Add-Check 'state_scene_after_open' ($p.scene_path -eq 'res://scenes/second.tscn') ("editor_get_scene_tree.scene_path={0}" -f $p.scene_path)

        $t = Invoke-Tool -Id 4 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Label 'success-open-scene-main'
        $p = Assert-Payload $t 'success-open-scene-main'
        Add-Check 'success_open_scene_main' ($p.path -eq 'res://scenes/main.tscn') ("path={0} opened={1}" -f $p.path, $p.opened)

        $t = Invoke-Tool -Id 5 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/never_written.tscn' } -Label 'bottom-open-missing-scene'
        $e = Assert-Error $t 'bottom-open-missing-scene' -32001
        Add-Check 'bottom_open_missing_scene' ($e.data.suggestion.Length -gt 0) ("code={0} message='{1}' suggestion='{2}'" -f $e.code, $e.message, $e.data.suggestion)

        $t = Invoke-Tool -Id 6 -Tool 'editor_open_scene' -Arguments @{} -Label 'missing-param-open-scene'
        $e = Assert-Error $t 'missing-param-open-scene' -32602
        Add-Check 'missing_param_open_scene' ($e.message -eq 'Missing required parameter: path') ("code={0} message='{1}'" -f $e.code, $e.message)

        Write-Host ''
        Write-Host '========== state chain: selection =========='
        $t = Invoke-Tool -Id 10 -Tool 'editor_get_selection' -Arguments @{} -Label 'state-03-selection-before'
        $p = Assert-Payload $t 'state-03'
        Add-Check 'state_selection_before' ($p.count -eq 0) ("editor_get_selection.count={0}" -f $p.count)

        $t = Invoke-Tool -Id 11 -Tool 'editor_set_node_selection' -Arguments @{ node_path = 'Marker' } -Label 'success-select-node'
        $p = Assert-Payload $t 'success-select-node'
        Add-Check 'success_select_node' (($p.count -eq 1) -and ($p.selected[0].path -eq 'Marker') -and ($p.mode -eq 'replace')) ("mode={0} count={1} selected[0].path={2}" -f $p.mode, $p.count, $p.selected[0].path)

        $t = Invoke-Tool -Id 12 -Tool 'editor_get_selection' -Arguments @{} -Label 'state-04-selection-after-select'
        $p = Assert-Payload $t 'state-04'
        Add-Check 'state_selection_after_select' (($p.count -eq 1) -and ($p.nodes[0].path -eq 'Marker')) ("editor_get_selection.count={0} nodes[0].path={1}" -f $p.count, $p.nodes[0].path)

        $t = Invoke-Tool -Id 13 -Tool 'editor_set_node_selection' -Arguments @{ node_paths = @('Marker', 'Group/Nested'); mode = 'add'; inspect = $false; focus = $false } -Label 'success-select-add-many'
        $p = Assert-Payload $t 'success-select-add-many'
        Add-Check 'success_select_add_many' ($p.count -eq 2) ("mode={0} count={1}" -f $p.mode, $p.count)

        $t = Invoke-Tool -Id 14 -Tool 'editor_set_node_selection' -Arguments @{ node_paths = @('Marker'); mode = 'remove' } -Label 'success-select-remove'
        $p = Assert-Payload $t 'success-select-remove'
        Add-Check 'success_select_remove' (($p.count -eq 1) -and ($p.selected[0].path -eq 'Group/Nested')) ("mode={0} count={1} selected[0].path={2}" -f $p.mode, $p.count, $p.selected[0].path)

        $t = Invoke-Tool -Id 15 -Tool 'editor_remove_node_selection' -Arguments @{} -Label 'success-clear-selection'
        $p = Assert-Payload $t 'success-clear-selection'
        Add-Check 'success_clear_selection' (($p.cleared -eq 1) -and ($p.count -eq 0)) ("cleared={0} count={1}" -f $p.cleared, $p.count)

        $t = Invoke-Tool -Id 16 -Tool 'editor_get_selection' -Arguments @{} -Label 'state-05-selection-after-clear'
        $p = Assert-Payload $t 'state-05'
        Add-Check 'state_selection_after_clear' ($p.count -eq 0) ("editor_get_selection.count={0}" -f $p.count)

        $t = Invoke-Tool -Id 17 -Tool 'editor_set_node_selection' -Arguments @{ node_path = 'NoSuchNode' } -Label 'bottom-select-missing-node'
        $e = Assert-Error $t 'bottom-select-missing-node' -32001
        Add-Check 'bottom_select_missing_node' ($e.data.suggestion.Length -gt 0) ("code={0} message='{1}'" -f $e.code, $e.message)

        $t = Invoke-Tool -Id 18 -Tool 'editor_set_node_selection' -Arguments @{ node_path = '.'; mode = 'toggle' } -Label 'mistyped-param-set-node-selection'
        $e = Assert-Error $t 'mistyped-param-set-node-selection' -32602
        Add-Check 'mistyped_param_set_node_selection' ($e.message -eq 'mode must be one of: replace, add, remove') ("code={0} message='{1}'" -f $e.code, $e.message)

        Write-Host ''
        Write-Host '========== editor_add_resource_to_node_property =========='
        $t = Invoke-Tool -Id 20 -Tool 'editor_add_resource_to_node_property' -Arguments @{
            node_path = 'Marker'; property = 'material_override'; resource_type = 'StandardMaterial3D'
            resource_properties = @{ albedo_color = '#ff0000'; metallic = 0.5 }
        } -Label 'success-add-resource'
        $p = Assert-Payload $t 'success-add-resource'
        Add-Check 'success_add_resource' (($p.node_path -eq 'Marker') -and ($p.property -eq 'material_override') -and ($p.resource_type -eq 'StandardMaterial3D')) ("node_path={0} property={1} resource_type={2}" -f $p.node_path, $p.property, $p.resource_type)

        $t = Invoke-Tool -Id 21 -Tool 'editor_add_resource_to_node_property' -Arguments @{ node_path = 'Marker'; property = 'material_override'; resource_type = 'McpNoSuchClass' } -Label 'bottom-add-resource-unknown-class'
        $e = Assert-Error $t 'bottom-add-resource-unknown-class' -32602
        Add-Check 'bottom_add_resource_unknown_class' ($e.message.Length -gt 0) ("code={0} message='{1}'" -f $e.code, $e.message)

        $t = Invoke-Tool -Id 22 -Tool 'editor_add_resource_to_node_property' -Arguments @{ node_path = 'NoSuchNode'; property = 'material_override'; resource_type = 'StandardMaterial3D' } -Label 'bottom-add-resource-missing-node'
        $e = Assert-Error $t 'bottom-add-resource-missing-node' -32001
        Add-Check 'bottom_add_resource_missing_node' ($e.data.suggestion.Length -gt 0) ("code={0} message='{1}'" -f $e.code, $e.message)

        $t = Invoke-Tool -Id 23 -Tool 'editor_add_resource_to_node_property' -Arguments @{ node_path = '.'; property = 'x' } -Label 'mistyped-param-add-resource'
        $e = Assert-Error $t 'mistyped-param-add-resource' -32602
        Add-Check 'mistyped_param_add_resource' ($e.message -eq 'Missing required parameter: resource_type') ("code={0} message='{1}'" -f $e.code, $e.message)

        Write-Host ''
        Write-Host '========== editor_save_scene (atomic publish) =========='
        $t = Invoke-Tool -Id 30 -Tool 'editor_save_scene' -Arguments @{} -Label 'success-save-scene-in-place'
        $p = Assert-Payload $t 'success-save-scene-in-place'
        Add-Check 'success_save_scene_in_place' (($p.path -eq 'res://scenes/main.tscn') -and ($p.saved -eq $true)) ("path={0} saved={1}" -f $p.path, $p.saved)

        # The sub-resource added above must now be *on disk*: that is the
        # independent half of the add-resource evidence.
        $mainText = [IO.File]::ReadAllText((Join-Path $Scratch 'scenes\main.tscn'))
        $hasSub = $mainText.Contains('sub_resource type="StandardMaterial3D"')
        Add-Check 'add_resource_landed_in_saved_scene' $hasSub ('main.tscn contains the StandardMaterial3D sub-resource: {0}' -f $hasSub)

        $t = Invoke-Tool -Id 31 -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/out/copy.tscn' } -Label 'success-save-scene-as'
        $p = Assert-Payload $t 'success-save-scene-as'
        $copyExists = Test-Path (Join-Path $Scratch 'scenes\out\copy.tscn')
        Add-Check 'success_save_scene_as' (($p.path -eq 'res://scenes/out/copy.tscn') -and ($p.saved -eq $true) -and $copyExists) ("path={0} saved={1} file_on_disk={2}" -f $p.path, $p.saved, $copyExists)

        $t = Invoke-Tool -Id 32 -Tool 'editor_save_scene' -Arguments @{ path = 17 } -Label 'mistyped-param-save-scene'
        $e = Assert-Error $t 'mistyped-param-save-scene' -32602
        Add-Check 'mistyped_param_save_scene' ($e.message.Contains("must be a string")) ("code={0} message='{1}'" -f $e.code, $e.message)

        $t = Invoke-Tool -Id 33 -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/bad.txt' } -Label 'bottom-save-unrecognized-extension'
        $e = Assert-Error $t 'bottom-save-unrecognized-extension' -32603
        Add-Check 'bottom_save_unrecognized_extension' (($e.message.Contains('Failed to save scene')) -and (-not (Test-Path (Join-Path $Scratch 'scenes\bad.txt')))) ("code={0} message='{1}' bad.txt_exists={2}" -f $e.code, $e.message, (Test-Path (Join-Path $Scratch 'scenes\bad.txt')))

        Write-Host ''
        Write-Host '========== editor_rescan_project_filesystem / editor_reload_plugin =========='
        $t = Invoke-Tool -Id 40 -Tool 'editor_rescan_project_filesystem' -Arguments @{} -Label 'success-rescan-filesystem'
        $p = Assert-Payload $t 'success-rescan-filesystem'
        Add-Check 'success_rescan_filesystem' ($p.reloaded -eq $true) ("reloaded={0} message='{1}'" -f $p.reloaded, $p.message)

        $t = Invoke-Tool -Id 41 -Tool 'editor_reload_plugin' -Arguments @{} -Label 'success-reload-plugin'
        $p = Assert-Payload $t 'success-reload-plugin'
        Add-Check 'success_reload_plugin' (($p.reloading -eq $true) -and ($p.plugins.Count -ge 1)) ("reloading={0} plugins={1}" -f $p.reloading, ($p.plugins -join ','))

        Write-Host ''
        Write-Host '========== state chain: 3D viewport camera =========='
        $t = Invoke-Tool -Id 50 -Tool 'editor_get_viewport_3d_camera' -Arguments @{} -Label 'state-06-camera-before'
        $p = Assert-Payload $t 'state-06'
        $fovBefore = $p.fov
        $posBefore = "$($p.position.x),$($p.position.y),$($p.position.z)"
        Add-Check 'state_camera_before' ($null -ne $fovBefore) ("editor_get_viewport_3d_camera.fov={0} position=({1})" -f $fovBefore, $posBefore)

        $t = Invoke-Tool -Id 51 -Tool 'editor_set_viewport_3d_camera' -Arguments @{ position = @{ x = 1; y = 2; z = 3 }; fov = 42 } -Label 'success-set-camera'
        $p = Assert-Payload $t 'success-set-camera'
        Add-Check 'success_set_camera' (($p.fov -eq 42) -and ($p.position.x -eq 1) -and ($p.position.y -eq 2) -and ($p.position.z -eq 3)) ("position=({0},{1},{2}) fov={3}" -f $p.position.x, $p.position.y, $p.position.z, $p.fov)

        $t = Invoke-Tool -Id 52 -Tool 'editor_get_viewport_3d_camera' -Arguments @{} -Label 'state-07-camera-after'
        $p = Assert-Payload $t 'state-07'
        # The position survives: the editor's viewport *reads* the camera transform.
        Add-Check 'state_camera_after_position' ((($p.position.x - 1.0) -lt 0.001) -and (($p.position.y - 2.0) -lt 0.001) -and (($p.position.z - 3.0) -lt 0.001)) ("editor_get_viewport_3d_camera.position=({0},{1},{2})" -f $p.position.x, $p.position.y, $p.position.z)
        # The fov does not, and that is a measured property of the editor rather
        # than of this tool: `Node3DEditorViewport::_update_camera()` recomputes
        # the camera projection from its own state every update
        # (node_3d_editor_viewport.cpp:3053-3061
        # `camera->set_perspective(get_fov(), ...)`) and there is no public setter
        # for that state from a module. The migration source had the same shape
        # (`cam.fov = ...` then an immediate read-back), so the tool's own
        # response is the durable observable of the fov: it reports the value it
        # set, read back from the real camera. Recorded, not hidden.
        Add-Check 'state_camera_after_fov_reasserted_by_editor' ($p.fov -ne 42) ("fov after the editor's own viewport update = {0} (not 42); the tool's own response reported 42 - measured editor behaviour, see REPORT-008 section 8" -f $p.fov)

        $t = Invoke-Tool -Id 53 -Tool 'editor_set_viewport_3d_camera' -Arguments @{ fov = 'wide' } -Label 'mistyped-param-set-camera'
        $e = Assert-Error $t 'mistyped-param-set-camera' -32602
        Add-Check 'mistyped_param_set_camera' ($e.message.Contains("Parameter 'fov' must be a number")) ("code={0} message='{1}'" -f $e.code, $e.message)

        Write-Host ''
        Write-Host '========== editor_capture_screenshot (honest refusal under --headless) =========='
        # Under `--headless` the rendering driver is the dummy one, so
        # `ViewportTexture::get_image()` yields an empty image. The tool must say
        # so; what it must *not* do is answer with a fabricated image or, worse,
        # with `saved_path` for a file that was never written (the migration
        # source swallowed the failure and removed `image_base64`, which produced
        # exactly that fake success). The success class runs in `-Phase gui`.
        $t = Invoke-Tool -Id 60 -Tool 'editor_capture_screenshot' -Arguments @{} -Label 'headless-capture-base64-refused'
        $e = Assert-Error $t 'headless-capture-base64-refused' -32603
        Add-Check 'headless_capture_base64_is_an_honest_error' ((-not $t.Contains('image_base64')) -and (-not $t.Contains('"result"'))) ("code={0} message='{1}' no result envelope={2}" -f $e.code, $e.message, (-not $t.Contains('"result"')))

        $shotAbs = Join-Path $Scratch 'screenshots\editor.png'
        $t = Invoke-Tool -Id 61 -Tool 'editor_capture_screenshot' -Arguments @{ save_path = 'res://screenshots/editor.png' } -Label 'headless-capture-save-refused'
        $e = Assert-Error $t 'headless-capture-save-refused' -32603
        Add-Check 'headless_capture_save_is_an_honest_error' ((-not $t.Contains('saved_path')) -and (-not (Test-Path $shotAbs))) ("code={0} message='{1}' file_created={2}" -f $e.code, $e.message, (Test-Path $shotAbs))

        $t = Invoke-Tool -Id 62 -Tool 'editor_capture_screenshot' -Arguments @{ save_path = 'C:/outside/shot.png' } -Label 'mistyped-param-capture-screenshot'
        $e = Assert-Error $t 'mistyped-param-capture-screenshot' -32602
        Add-Check 'mistyped_param_capture_screenshot' ($e.message.Contains("must start with 'res://' or 'user://'")) ("code={0} message='{1}'" -f $e.code, $e.message)

        Write-Host ''
        Write-Host '========== counter-example: a failing save must not damage the file =========='
        $locked = Join-Path $Scratch 'scenes\locked.tscn'
        $t = Invoke-Tool -Id 70 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/locked.tscn' } -Label 'success-open-scene-locked'
        $p = Assert-Payload $t 'success-open-scene-locked'
        $lockedShaBefore = (Get-FileHash -Algorithm SHA256 -Path $locked).Hash.ToLower()
        Set-ItemProperty -Path $locked -Name IsReadOnly -Value $true
        Write-Host ("locked.tscn is now read-only; sha256 before={0}" -f $lockedShaBefore)

        $t = Invoke-Tool -Id 71 -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/locked.tscn' } -Label 'counter-example-save-readonly-destination'
        $e = Assert-Error $t 'counter-example-save-readonly-destination' -32603
        $lockedShaAfter = (Get-FileHash -Algorithm SHA256 -Path $locked).Hash.ToLower()
        Add-Check 'counter_example_save_readonly' (($lockedShaBefore -eq $lockedShaAfter) -and ($null -ne $e)) ("code={0} sha256_before={1} sha256_after={2} unchanged={3}" -f $e.code, $lockedShaBefore, $lockedShaAfter, ($lockedShaBefore -eq $lockedShaAfter))
        Set-ItemProperty -Path $locked -Name IsReadOnly -Value $false

        Write-Host ''
        Write-Host '========== editor_remove_output_log (red -> green) =========='
        # The Output panel is an `EditorLog` widget; `editor_get_output_log` reads
        # the engine log file. They are different objects, and the evidence below
        # keeps them apart: the panel is measured in-band by the tool, and the log
        # file is read from disk by this script *after* the editor has exited
        # (while the editor runs, the engine holds the log open, which is why the
        # read tool answers `cannot open the log file` here - recorded as an
        # observation).
        $t = Invoke-Tool -Id 79 -Tool 'editor_get_output_log' -Arguments @{ max_lines = 500 } -Label 'observation-log-file-while-editor-holds-it'
        Write-Host ("        observation: {0}" -f $t)

        # Even the *failure* of opening a scene makes the editor report into the
        # panel: that is what the panel's own content measures below.
        $t = Invoke-Tool -Id 80 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/broken.tscn' } -Label 'bottom-open-unloadable-scene'
        $e = Assert-Error $t 'bottom-open-unloadable-scene' -32001
        Add-Check 'bottom_open_unloadable_scene' ($e.data.suggestion.Length -gt 0) ("code={0} message='{1}'" -f $e.code, $e.message)

        $t = Invoke-Tool -Id 81 -Tool 'editor_remove_output_log' -Arguments @{} -Label 'success-clear-output-log'
        $p = Assert-Payload $t 'success-clear-output-log'
        Add-Check 'success_clear_output_log' (($p.cleared -eq $true) -and ($p.log_was_empty -eq $false) -and ($p.log_is_empty -eq $true)) ("cleared={0} log_was_empty={1} log_is_empty={2}" -f $p.cleared, $p.log_was_empty, $p.log_is_empty)

        # The second call can only report `log_was_empty = true` if the first one
        # really emptied the panel.
        $t = Invoke-Tool -Id 82 -Tool 'editor_remove_output_log' -Arguments @{} -Label 'success-clear-output-log-again'
        $p = Assert-Payload $t 'success-clear-output-log-again'
        Add-Check 'success_clear_output_log_idempotent' (($p.cleared -eq $true) -and ($p.log_was_empty -eq $true) -and ($p.log_is_empty -eq $true)) ("cleared={0} log_was_empty={1} log_is_empty={2}" -f $p.cleared, $p.log_was_empty, $p.log_is_empty)
    }

    Start-Sleep -Seconds 2
}
finally {
    if ($null -ne $proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    $after = Write-Snapshot -Path (Join-Path $Evid ("fs.after.{0}.txt" -f $Phase)) -Root $Scratch

    $pidAfter = -1
    $lines = & netstat -ano -p TCP 2>$null
    foreach ($line in $lines) {
        if ($line -match 'LISTENING' -and $line -match '[:\]]9877\s') { $pidAfter = [int](($line.Trim() -split '\s+')[-1]) }
    }
    Write-Host ("user editor on 9877 after: pid={0}" -f $pidAfter)
    Add-Check 'guard_user_port_9877' ($pidBefore -eq $pidAfter -and $pidBefore -ne -1) ("pid_before={0} pid_after={1} same={2}" -f $pidBefore, $pidAfter, ($pidBefore -eq $pidAfter))

    $listening = (& netstat -ano -p TCP 2>$null | Where-Object { $_ -match 'LISTENING' -and $_ -match (":[0-9]*\b") -and $_ -match "[:]$Port\s" })
    Add-Check 'own_port_released' ((-not $listening) -or ($listening.Count -eq 0)) ("listeners on {0} after shutdown: {1}" -f $Port, ($listening -join ' ; '))

    # The *external* half of the panel-vs-file evidence: the engine log file is
    # read from disk by this script after the editor has exited. The panel was
    # emptied during the run (measured in-band), and the file still holds the
    # marker the scratch addon printed at startup - so the tool did not "clear the
    # output" by truncating the engine log.
    if ($Phase -eq 'main') {
        if (Test-Path $userLogFile) {
            $logText = [IO.File]::ReadAllText($userLogFile)
            $markerCount = ([regex]::Matches($logText, 'MCP008_PLUGIN')).Count
            $logSha = (Get-FileHash -Algorithm SHA256 -Path $userLogFile).Hash.ToLower()
            Add-Check 'log_file_is_not_the_panel' ($markerCount -ge 1) ("after the panel was cleared the engine log still holds {0} marker line(s): bytes={1} sha256={2} marker_lines={3}" -f $markerCount, (Get-Item $userLogFile).Length, $logSha, $markerCount)
        } else {
            Add-Check 'log_file_is_not_the_panel' $false ("the engine log file was never created: {0}" -f $userLogFile)
        }
    }

    if (-not $KeepScratch) {
        # leave the scratch tree in place for inspection; it lives in %TEMP%
    }
}

$passed = ($result.checks | Where-Object { $_.pass }).Count
$total = $result.checks.Count
Write-Host ''
Write-Host ("=== phase {0}: {1}/{2} checks passed ===" -f $Phase, $passed, $total)
foreach ($c in $result.checks) {
    if (-not $c.pass) { Write-Host ("  FAILED {0} :: {1}" -f $c.id, $c.evidence) }
}
Write-Host ("evidence directory: {0}" -f $Evid)
if ($passed -ne $total) { exit 1 }
exit 0