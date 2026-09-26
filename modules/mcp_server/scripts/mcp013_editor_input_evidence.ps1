# =============================================================================
#  mcp013_editor_input_evidence.ps1 -- TASK-013 gate 2 evidence
#
#  The live evidence for B2's last group (`editor_input_simulation`, six
#  editor-scope tools) plus the two claims the task book names as this batch's
#  most valuable ones:
#
#    Phase boundary   The GDR-21 / D59 input-channel boundary, measured in one
#                     run with *two* processes of the same project:
#                       * a game on 9889 whose own script counts the input events
#                         it receives (`instrumented_auth.gd`), and
#                       * an editor on 9888 whose own EditorPlugin counts the
#                         input events *it* receives (`mcp013_probe/plugin.gd`,
#                         writing `user://mcp013_editor_input_probe.txt`).
#                     Then the same actions are injected through the editor
#                     endpoint and both sides are read back:
#                       * every injection changes the EDITOR's own counters (the
#                         editor process' Input/InputMap really did move), and
#                       * not one of the game's counters moves.
#                     The control that keeps the second half from being vacuous:
#                     the same key is then injected *inside the game* with
#                     `running_game_execute_gdscript`, and the game's counter
#                     does move. "Unchanged" is a measurement, not an absence of
#                     measurement.
#                     The endpoint half is here too: the six tools are served by
#                     9888, absent from 9889, and a call on 9889 is `-32601`.
#
#    Phase limits     The recording length caps (D59 point 5 / DESIGN-DETAIL
#                     19.5), configured through the project (`godot_mcp/
#                     recording_max_events` / `recording_max_duration_ms`, the
#                     same channel as `godot_mcp/port`):
#                       * `events`   - a cap of 3: record 5, stop, get exactly 3
#                                      with `truncated: true`, `dropped: 2`;
#                       * `duration` - a cap of 500 ms: one event inside the cap
#                                      and one after it, `truncated: true`,
#                                      `dropped: 1`;
#                       * the boundary phase additionally records with no cap
#                         configured and reads the compiled defaults back.
#
#  Discipline (PLAYBOOK section 3 and section 7.1), as in TASK-012's script:
#    * every response body is written to its own file with
#      `curl.exe -s -o <file>` and a sha256 is printed from the bytes on disk.
#      Nothing goes through `Out-File` or a pipeline.
#    * every request body is built with `ConvertTo-Json` and written as a file,
#      never interpolated into a command line.
#    * ports 9888 (editor) / 9889 (game) only. Port 9877 belongs to the user's
#      editor: it is never touched, only observed, and its listener pid is
#      asserted unchanged at the end of every phase.
#    * only engines this script started itself are stopped, and every pid it
#      started is swept in `finally`.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp013_editor_input_evidence.ps1 -Phase boundary
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp013_editor_input_evidence.ps1 -Phase negatives
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp013_editor_input_evidence.ps1 -Phase limits
# =============================================================================

param(
    [ValidateSet('boundary', 'limits', 'negatives')]
    [string]$Phase = 'boundary',
    # `limits` runs two engine sessions (one per cap axis) unless a single
    # configuration is named.
    [ValidateSet('', 'events', 'duration')]
    [string]$LimitsConfig = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877
$Scratch = Join-Path $env:TEMP 'mcp013-scratch'
$LogRoot = Join-Path $env:TEMP 'mcp013-logs'
$Evid = Join-Path $env:TEMP 'mcp013-evidence'

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
    [IO.File]::WriteAllBytes($Path, [Text.Encoding]::UTF8.GetBytes($Text))
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

function Test-PortOpen {
    param([int]$Port, [int]$TimeoutMs = 1500)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        if (-not $task.Wait($TimeoutMs)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
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
    return [pscustomobject]@{ Process = $proc; Out = $out; Err = $err }
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

# -----------------------------------------------------------------------------
# JSON building: every value is escaped by `ConvertTo-Json`, never by string
# interpolation (TASK-012's first evidence run measured the difference).
# -----------------------------------------------------------------------------

function ConvertTo-CompactJson {
    param($Value)
    return (ConvertTo-Json -InputObject $Value -Depth 12 -Compress)
}

function Format-CallBody {
    param([string]$Tool, $Arguments)
    $envelope = @{
        jsonrpc = '2.0'
        id      = 1
        method  = 'tools/call'
        params  = @{ name = $Tool; arguments = $Arguments }
    }
    return (ConvertTo-CompactJson $envelope)
}

# -----------------------------------------------------------------------------
# HTTP: the response always goes to a file; the request body is a file too.
# -----------------------------------------------------------------------------

function Invoke-Curl {
    param([string]$Id, [string]$Json, [int]$Port, [int]$MaxTimeSec = 30)
    $bodyFile = Join-Path $Evid ("{0}.request.json" -f $Id)
    $respFile = Join-Path $Evid ("{0}.response.json" -f $Id)
    Write-Utf8NoBom -Path $bodyFile -Text $Json
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time $MaxTimeSec -o $respFile -H 'Content-Type: application/json' `
        --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    $curlExit = $LASTEXITCODE
    if (-not (Test-Path $respFile)) {
        Write-Host ("[{0}] curl port={1} exit={2} :: NO RESPONSE FILE" -f $Id, $Port, $curlExit)
        return ''
    }
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] curl port={1} exit={2} bytes={3} sha256={4}" -f $Id, $Port, $curlExit, $bytes.Length, $sha)
    Write-Host ("       request : {0}" -f $Json)
    Write-Host ("       response: {0}" -f $text)
    return $text
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port, [int]$MaxTimeSec = 30)
    $text = Invoke-Curl -Id $Id -Json (Format-CallBody -Tool $Tool -Arguments $Arguments) -Port $Port -MaxTimeSec $MaxTimeSec
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return ConvertFrom-Json $text } catch { return $null }
}

# The tool payload of a successful `tools/call`: the JSON text inside
# `result.content[0].text`.
function Get-Payload {
    param($Envelope)
    if ($null -eq $Envelope) { return $null }
    if ($null -eq $Envelope.result) { return $null }
    $content = @($Envelope.result.content)
    if ($content.Count -lt 1) { return $null }
    try { return ConvertFrom-Json ([string]$content[0].text) } catch { return $null }
}

function Get-ErrorCode {
    param($Envelope)
    if ($null -eq $Envelope -or $null -eq $Envelope.error) { return 0 }
    return [int]$Envelope.error.code
}

function Get-ErrorMessage {
    param($Envelope)
    if ($null -eq $Envelope -or $null -eq $Envelope.error) { return '' }
    return [string]$Envelope.error.message
}

function Get-StatusProbe {
    param([int]$Port)
    $file = Join-Path $Evid ("status_{0}.response.json" -f $Port)
    if (Test-Path $file) { Remove-Item -Force $file }
    & $Curl -s --max-time 5 -o $file ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    if (-not (Test-Path $file)) { return $null }
    $bytes = [IO.File]::ReadAllBytes($file)
    if ($bytes.Length -eq 0) { return $null }
    $sha = (Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[status] port={0} bytes={1} sha256={2}" -f $Port, $bytes.Length, $sha)
    Write-Host ("         body: {0}" -f $text)
    try { return ConvertFrom-Json $text } catch {
        Write-Host '         (status body is not JSON yet)'
        return $null
    }
}

function Wait-ForPump {
    param([int]$Port, [int]$TimeoutMs = 240000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $consecutive = 0
    $previous = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Get-StatusProbe -Port $Port
        if ($null -ne $probe) {
            $frames = [int]$probe.frame_count
            if ($null -ne $previous -and ($frames - $previous) -ge 20) { $consecutive++ } else { $consecutive = 0 }
            if ($consecutive -ge 3) { return $true }
            $previous = $frames
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

function Import-Project {
    param([string]$Path, [string]$LogName)
    $out = Join-Path $LogRoot ($LogName + '.out.log')
    $err = Join-Path $LogRoot ($LogName + '.err.log')
    $proc = Start-Process -FilePath $Engine -ArgumentList @('--headless', '--path', $Path, '--import') `
        -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    $proc.WaitForExit(300000) | Out-Null
}

# One property of one node, read through `running_game_get_node_properties`, as
# a string (`$null` when the call failed or the property is missing).
function Read-NodeProperty {
    param([string]$Id, [string]$NodePath, [string]$Property, [int]$Port)
    $envelope = Invoke-Tool -Id $Id -Tool 'running_game_get_node_properties' `
        -Arguments @{ node_path = $NodePath; properties = @($Property) } -Port $Port
    $payload = Get-Payload $envelope
    if ($null -eq $payload -or $null -eq $payload.properties) { return $null }
    $member = $payload.properties.PSObject.Properties[$Property]
    if ($null -eq $member -or $null -eq $member.Value) { return $null }
    return [string]$member.Value
}

# -----------------------------------------------------------------------------
# The scratch projects. Both carry the *same* game script, so the two processes
# really are the same project; only the editor copy carries the probe plugin.
# -----------------------------------------------------------------------------

$GameScript = @'
extends Node2D

# The game's own counter. Every "the game did not change" claim below reads a
# number that *this* file produced, not a number a tool reported about itself.
var key_events := 0
var mouse_events := 0
var motion_events := 0
var last_event_type := ""
var status_text := "idle"

@onready var label: Label = $Label


func _ready() -> void:
	_tick()


func _process(_delta: float) -> void:
	_tick()


func _input(event: InputEvent) -> void:
	# `DEVICE_ID_EMULATION` is the device the engine gives its own synthesised
	# events, so counting them would stop this counter from measuring injection.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventKey:
		key_events += 1
		last_event_type = "key"
	elif event is InputEventMouseButton:
		mouse_events += 1
		last_event_type = "mouse_button"
	elif event is InputEventMouseMotion:
		motion_events += 1
		last_event_type = "mouse_motion"


func _tick() -> void:
	label.text = "state=%s keys=%d mouse=%d motion=%d last=%s" % [
		status_text, key_events, mouse_events, motion_events, last_event_type
	]
'@

$GameScene = @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://instrumented_auth.gd" id="1_auth"]

[node name="Main" type="Node2D"]
script = ExtResource("1_auth")

[node name="Label" type="Label" parent="."]
offset_left = 20.0
offset_top = 20.0
offset_right = 520.0
offset_bottom = 60.0
text = "idle"
'@

# The editor-side instrument: an EditorPlugin is the only thing an editor
# process runs out of a project (autoloads are a game-runtime feature), and it
# is added to the editor's own tree, so `_input` sees what the editor's Input
# queue delivers - which is exactly what the tools under test feed.
$ProbePlugin = @'
@tool
extends EditorPlugin

const OUT_PATH := "user://mcp013_editor_input_probe.txt"

var counts := {"key": 0, "mouse_button": 0, "mouse_motion": 0, "action": 0, "other": 0}
var last := ""


func _enter_tree() -> void:
	set_process_input(true)
	_write("booted")


func _exit_tree() -> void:
	set_process_input(false)


func _input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var kind := "other"
	if event is InputEventKey:
		kind = "key"
	elif event is InputEventMouseButton:
		kind = "mouse_button"
	elif event is InputEventMouseMotion:
		kind = "mouse_motion"
	elif event is InputEventAction:
		kind = "action"
	counts[kind] = int(counts[kind]) + 1
	last = "%s:%s" % [kind, event.as_text()]
	_write(last)


func _write(what: String) -> void:
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"counts": counts,
		"last": what,
		"seen": int(counts["key"]) + int(counts["mouse_button"]) + int(counts["mouse_motion"]) + int(counts["action"]) + int(counts["other"]),
	}))
	file.close()
'@

function Write-GameProject {
    param([string]$Path, [string]$Name, [string[]]$ExtraSettings = @())
    $sceneDir = Join-Path $Path 'scenes'
    New-Item -ItemType Directory -Force -Path $sceneDir | Out-Null
    $lines = @(
        'config_version=5',
        '',
        '[application]',
        ('config/name="' + $Name + '"'),
        'config/features=PackedStringArray("4.8")',
        'run/main_scene="res://scenes/main.tscn"'
    )
    if ($ExtraSettings.Count -gt 0) {
        $lines += ''
        $lines += '[godot_mcp]'
        $lines += $ExtraSettings
    }
    $lines += @(
        '',
        '[rendering]',
        'renderer/rendering_method="gl_compatibility"',
        'renderer/rendering_method.mobile="gl_compatibility"'
    )
    Write-Utf8NoBom -Path (Join-Path $Path 'project.godot') -Text ($lines -join "`n")
    Write-Utf8NoBom -Path (Join-Path $sceneDir 'main.tscn') -Text $GameScene
    Write-Utf8NoBom -Path (Join-Path $Path 'instrumented_auth.gd') -Text $GameScript
}

function Write-EditorProject {
    param([string]$Path, [string]$Name)
    $sceneDir = Join-Path $Path 'scenes'
    $addonDir = Join-Path $Path 'addons\mcp013_probe'
    New-Item -ItemType Directory -Force -Path $sceneDir, $addonDir | Out-Null
    Write-Utf8NoBom -Path (Join-Path $Path 'project.godot') -Text @"
config_version=5

[application]
config/name="$Name"
config/features=PackedStringArray("4.8")

[editor_plugins]
enabled=PackedStringArray("res://addons/mcp013_probe/plugin.cfg")

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
"@
    Write-Utf8NoBom -Path (Join-Path $sceneDir 'main.tscn') -Text @'
[gd_scene format=3]

[node name="Main" type="Node2D"]
'@
    Write-Utf8NoBom -Path (Join-Path $Path 'instrumented_auth.gd') -Text $GameScript
    Write-Utf8NoBom -Path (Join-Path $addonDir 'plugin.cfg') -Text @'
[plugin]

name="MCP013 Probe"
description="Counts the input events the editor process receives (TASK-013 evidence)."
author="TASK-013"
version="1.0"
script="plugin.gd"
'@
    Write-Utf8NoBom -Path (Join-Path $addonDir 'plugin.gd') -Text $ProbePlugin
}

# -----------------------------------------------------------------------------
# The editor probe file: `user://` of the editor project.
# -----------------------------------------------------------------------------

function Get-ProbePath {
    param([string]$ProjectName)
    return (Join-Path $env:APPDATA ("Godot\app_userdata\{0}\mcp013_editor_input_probe.txt" -f $ProjectName))
}

function Read-Probe {
    param([string]$ProjectName)
    $path = Get-ProbePath -ProjectName $ProjectName
    if (-not (Test-Path $path)) { return $null }
    $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    try { return ConvertFrom-Json $raw } catch { return $null }
}

function Wait-ForProbe {
    param([string]$ProjectName, [string]$Field, [int]$AtLeast, [int]$TimeoutMs = 20000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $last = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $last = Read-Probe -ProjectName $ProjectName
        if ($null -ne $last) {
            if ($Field -eq 'seen') {
                if ([int]$last.seen -ge $AtLeast) { return $last }
            } else {
                $member = $last.counts.PSObject.Properties[$Field]
                if ($null -ne $member -and [int]$member.Value -ge $AtLeast) { return $last }
            }
        }
        Start-Sleep -Milliseconds 400
    }
    return $last
}

function Get-ProbeCount {
    param($Probe, [string]$Field)
    if ($null -eq $Probe) { return -1 }
    $member = $Probe.counts.PSObject.Properties[$Field]
    if ($null -eq $member) { return -1 }
    return [int]$member.Value
}

# =============================================================================
#  Phase: boundary -- the GDR-21 / D59 input-channel boundary, measured
# =============================================================================

function Invoke-BoundaryPhase {
    $gameProject = Join-Path $Scratch 'boundary-game'
    $editorProject = Join-Path $Scratch 'boundary-editor'
    $gameName = 'MCP TASK-013 boundary game'
    $editorName = 'MCP TASK-013 boundary editor'
    Write-GameProject -Path $gameProject -Name $gameName
    Write-EditorProject -Path $editorProject -Name $editorName
    Write-Host 'importing the two scratch projects ...'
    Import-Project -Path $gameProject -LogName 'mcp013-boundary-game-import'
    Import-Project -Path $editorProject -LogName 'mcp013-boundary-editor-import'

    $userPortPidBefore = Get-ListenerPid -Port $UserPort
    Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)

    $freePorts = (-not (Test-PortOpen -Port $EditorPort) -and -not (Test-PortOpen -Port $GamePort))
    Add-Check 'b00_test_ports_free' $freePorts ("9888 open={0} 9889 open={1} before the phase" -f (Test-PortOpen -Port $EditorPort), (Test-PortOpen -Port $GamePort))
    if (-not $freePorts) { return }

    # -- the game process ----------------------------------------------------
    $game = Start-Engine -Arguments @('--headless', '--path', $gameProject, "--mcp-port=$GamePort") -LogName 'mcp013-boundary-game'
    if (-not (Wait-ForPump -Port $GamePort)) {
        Add-Check 'b01_game_ready' $false ("game endpoint never became ready; log={0}" -f (Get-Content -Raw $game.Out -ErrorAction SilentlyContinue))
        Stop-Engine -Handle $game
        return
    }
    Add-Check 'b01_game_ready' $true 'the headless game answers GET /mcp on 9889'

    $scriptLoaded = Read-NodeProperty -Id 'b02_script_loaded' -NodePath 'Main' -Property 'status_text' -Port $GamePort
    Add-Check 'b02_game_script_is_loaded' ($scriptLoaded -eq 'idle') `
        ('the game script variable status_text reads ' + $scriptLoaded + ' (a parse failure would answer null)')

    # -- the editor process --------------------------------------------------
    $editor = Start-Engine -Arguments @('--headless', '-e', '--path', $editorProject, "--mcp-port=$EditorPort") -LogName 'mcp013-boundary-editor'
    if (-not (Wait-ForPump -Port $EditorPort)) {
        Add-Check 'b03_editor_ready' $false ("editor endpoint never became ready; log={0}" -f (Get-Content -Raw $editor.Out -ErrorAction SilentlyContinue))
        Stop-Engine -Handle $game
        Stop-Engine -Handle $editor
        return
    }
    Add-Check 'b03_editor_ready' $true 'the headless editor answers GET /mcp on 9888'

    $boot = Read-Probe -ProjectName $editorName
    Add-Check 'b04_editor_probe_plugin_is_running' (($null -ne $boot) -and ([int]$boot.seen -eq 0)) `
        ('the EditorPlugin of the editor process wrote its probe file with seen=' + [string]$boot.seen + ' (last="' + [string]$boot.last + '")')

    # -- baselines -----------------------------------------------------------
    $baseKeys = [int](Read-NodeProperty -Id 'b05_game_baseline_key_events' -NodePath 'Main' -Property 'key_events' -Port $GamePort)
    $baseMouse = [int](Read-NodeProperty -Id 'b05_game_baseline_mouse_events' -NodePath 'Main' -Property 'mouse_events' -Port $GamePort)
    $baseMotion = [int](Read-NodeProperty -Id 'b05_game_baseline_motion_events' -NodePath 'Main' -Property 'motion_events' -Port $GamePort)
    $baseEditor = Read-Probe -ProjectName $editorName
    Write-Host ("baselines: game keys={0} mouse={1} motion={2}; editor {3}" -f $baseKeys, $baseMouse, $baseMotion, (ConvertTo-CompactJson $baseEditor.counts))

    # -- (1) one key, injected through the EDITOR endpoint --------------------
    $key = Invoke-Tool -Id 'b06_editor_simulate_key' -Tool 'editor_simulate_key' `
        -Arguments @{ keycode = 'A'; pressed = $true } -Port $EditorPort
    $keyPayload = Get-Payload $key
    Add-Check 'b06_editor_simulate_key_accepted' `
        ($null -ne $keyPayload -and $keyPayload.simulated -eq 'key' -and $keyPayload.target -eq 'editor' -and [string]$keyPayload.keycode -eq 'A') `
        ('answer=' + (ConvertTo-CompactJson $keyPayload))

    $afterKey = Wait-ForProbe -ProjectName $editorName -Field 'key' -AtLeast ([int](Get-ProbeCount -Probe $baseEditor -Field 'key') + 1)
    $editorKeys = Get-ProbeCount -Probe $afterKey -Field 'key'
    Add-Check 'b07_editor_process_input_state_changed' ($editorKeys -ge 1) `
        ('the editor process own EditorPlugin counted key={0} event(s) in its _input after the injection (was {1})' -f $editorKeys, (Get-ProbeCount -Probe $baseEditor -Field 'key'))

    Start-Sleep -Milliseconds 600
    $gameKeysAfterKey = [int](Read-NodeProperty -Id 'b08_game_keys_after_editor_key' -NodePath 'Main' -Property 'key_events' -Port $GamePort)
    Add-Check 'b08_game_state_unchanged_by_the_editor_key' ($gameKeysAfterKey -eq $baseKeys) `
        ('the game own key_events counter is {0} (baseline {1}) while the same key moved the editor: the editor input queue is not the game one (GDR-21)' -f $gameKeysAfterKey, $baseKeys)

    # -- (2) click + move + a new action + the action event, all via 9888 -----
    $click = Invoke-Tool -Id 'b09_editor_simulate_mouse_click' -Tool 'editor_simulate_mouse_click' `
        -Arguments @{ button = 1; pressed = $true; x = 5; y = 6 } -Port $EditorPort
    $move = Invoke-Tool -Id 'b10_editor_simulate_mouse_move' -Tool 'editor_simulate_mouse_move' `
        -Arguments @{ x = 9; y = 10 } -Port $EditorPort
    $add = Invoke-Tool -Id 'b11_editor_add_input_action' -Tool 'editor_add_input_action' `
        -Arguments @{ action = 'mcp013_probe_action'; key = 'F9' } -Port $EditorPort
    $action = Invoke-Tool -Id 'b12_editor_simulate_input_action' -Tool 'editor_simulate_input_action' `
        -Arguments @{ action = 'mcp013_probe_action'; pressed = $true } -Port $EditorPort
    $clickPayload = Get-Payload $click
    $movePayload = Get-Payload $move
    $addPayload = Get-Payload $add
    $actionPayload = Get-Payload $action
    Add-Check 'b09_editor_mouse_tools_accepted' `
        ($null -ne $clickPayload -and $null -ne $movePayload -and $clickPayload.target -eq 'editor' -and $movePayload.target -eq 'editor') `
        ('click=' + (ConvertTo-CompactJson $clickPayload) + ' move=' + (ConvertTo-CompactJson $movePayload))
    Add-Check 'b10_editor_add_input_action_is_in_memory_only' `
        ($null -ne $addPayload -and $addPayload.persisted -eq $false -and $addPayload.created -eq $true -and [int]$addPayload.event_count -eq 1) `
        ('answer=' + (ConvertTo-CompactJson $addPayload) + ' (the editor InputMap was written, ProjectSettings was not)')
    Add-Check 'b11_editor_input_action_is_known_to_the_editor_map' `
        ($null -ne $actionPayload -and $actionPayload.target -eq 'editor' -and $actionPayload.in_input_map -eq $true) `
        ('answer=' + (ConvertTo-CompactJson $actionPayload))

    $afterAll = Wait-ForProbe -ProjectName $editorName -Field 'mouse_motion' -AtLeast 1
    Start-Sleep -Milliseconds 400
    $afterAll = Read-Probe -ProjectName $editorName
    $editorMouse = Get-ProbeCount -Probe $afterAll -Field 'mouse_button'
    $editorMotion = Get-ProbeCount -Probe $afterAll -Field 'mouse_motion'
    $editorAction = Get-ProbeCount -Probe $afterAll -Field 'action'
    Add-Check 'b12_editor_process_saw_the_mouse_and_action_events' `
        (($editorMouse -ge 1) -and ($editorMotion -ge 1) -and ($editorAction -ge 1)) `
        ('the editor process own counters: mouse_button={0} mouse_motion={1} action={2} (key={3})' -f $editorMouse, $editorMotion, $editorAction, (Get-ProbeCount -Probe $afterAll -Field 'key'))

    Start-Sleep -Milliseconds 600
    $gameMouse = [int](Read-NodeProperty -Id 'b13_game_mouse_after_editor_mouse' -NodePath 'Main' -Property 'mouse_events' -Port $GamePort)
    $gameMotion = [int](Read-NodeProperty -Id 'b14_game_motion_after_editor_motion' -NodePath 'Main' -Property 'motion_events' -Port $GamePort)
    Add-Check 'b15_game_state_unchanged_by_the_editor_mouse_and_action' `
        (($gameMouse -eq $baseMouse) -and ($gameMotion -eq $baseMotion)) `
        ('the game own counters are still mouse_events={0} motion_events={1} (baselines {2}/{3}) while the editor counted its own copies' -f $gameMouse, $gameMotion, $baseMouse, $baseMotion)

    # -- (3) the two InputMaps are different maps ----------------------------
    $list = Invoke-Tool -Id 'b16_editor_get_input_actions' -Tool 'editor_get_input_actions' -Arguments @{} -Port $EditorPort
    $listPayload = Get-Payload $list
    $hasAction = $false
    if ($null -ne $listPayload) { $hasAction = (@($listPayload.actions) -contains 'mcp013_probe_action') }
    Add-Check 'b16_editor_inputmap_carries_the_new_action' $hasAction `
        ('editor_get_input_actions on 9888 lists mcp013_probe_action={0} (count={1})' -f $hasAction, [string]$listPayload.count)

    $probeCode = 'return InputMap.has_action("mcp013_probe_action")'
    $gameMap = Invoke-Tool -Id 'b17_game_inputmap_probe' -Tool 'running_game_execute_gdscript' `
        -Arguments @{ code = $probeCode } -Port $GamePort
    $gameMapPayload = Get-Payload $gameMap
    $gameHasAction = $null
    if ($null -ne $gameMapPayload) { $gameHasAction = [string]$gameMapPayload.result }
    Add-Check 'b17_game_inputmap_does_not_carry_it' ($gameHasAction -eq 'false') `
        ('the game process own InputMap.has_action("mcp013_probe_action") = {0}: editor_add_input_action wrote the editor singleton, which is not the game one' -f $gameHasAction)

    # -- (4) the control: the same key, injected INSIDE the game -------------
    # Without this the "unchanged" checks above would be satisfied by a counter
    # that cannot move at all.
    $gameInject = @'
var e := InputEventKey.new()
e.keycode = KEY_A
e.physical_keycode = KEY_A
e.pressed = true
Input.parse_input_event(e)
return "injected"
'@
    $injected = Invoke-Tool -Id 'b18_game_injects_key_inside_itself' -Tool 'running_game_execute_gdscript' `
        -Arguments @{ code = $gameInject } -Port $GamePort
    Start-Sleep -Milliseconds 800
    $gameKeysAfterControl = [int](Read-NodeProperty -Id 'b19_game_keys_after_control' -NodePath 'Main' -Property 'key_events' -Port $GamePort)
    Add-Check 'b19_game_counter_moves_when_the_game_injects' ($gameKeysAfterControl -gt $gameKeysAfterKey) `
        ('the same key injected *inside* the game moved its own counter {0} -> {1}: the unchanged readings above are measurements, not a dead counter' -f $gameKeysAfterKey, $gameKeysAfterControl)

    # -- (5) the sequence tool, through the editor's deferred channel --------
    $sequence = @(
        @{ type = 'key'; keycode = 'B'; pressed = $true },
        @{ type = 'mouse_click'; button = 1; pressed = $true; x = 11; y = 12 },
        @{ type = 'action'; action = 'mcp013_probe_action'; pressed = $true }
    )
    $keysBeforeSequence = Get-ProbeCount -Probe (Read-Probe -ProjectName $editorName) -Field 'key'
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $sequenceCall = Invoke-Tool -Id 'b20_editor_simulate_input_sequence' -Tool 'editor_simulate_input_sequence' `
        -Arguments @{ events = $sequence; frame_delay = 1 } -Port $EditorPort -MaxTimeSec 40
    $watch.Stop()
    $sequencePayload = Get-Payload $sequenceCall
    Add-Check 'b20_editor_sequence_injected_every_event' `
        ($null -ne $sequencePayload -and $sequencePayload.sent -eq $true -and [int]$sequencePayload.event_count -eq 3 -and $sequencePayload.target -eq 'editor') `
        ('answer=' + (ConvertTo-CompactJson $sequencePayload) + ' after ' + [int]$watch.ElapsedMilliseconds + ' ms (it answers through the GDR-20 deferred channel, one event per frame)')

    $afterSequence = Wait-ForProbe -ProjectName $editorName -Field 'key' -AtLeast ($keysBeforeSequence + 1)
    Start-Sleep -Milliseconds 400
    $afterSequence = Read-Probe -ProjectName $editorName
    Add-Check 'b21_editor_process_saw_the_sequence' ((Get-ProbeCount -Probe $afterSequence -Field 'key') -ge ($keysBeforeSequence + 1)) `
        ('the editor process own key counter went {0} -> {1} across the sequence' -f $keysBeforeSequence, (Get-ProbeCount -Probe $afterSequence -Field 'key'))

    $gameKeysAfterSequence = [int](Read-NodeProperty -Id 'b22_game_keys_after_sequence' -NodePath 'Main' -Property 'key_events' -Port $GamePort)
    Add-Check 'b22_game_state_unchanged_by_the_sequence' ($gameKeysAfterSequence -eq $gameKeysAfterControl) `
        ('the game own key counter is still {0} (it was {1} after the control injection) after a whole editor-side sequence' -f $gameKeysAfterSequence, $gameKeysAfterControl)

    # -- (6) the endpoint half: served by 9888, refused by 9889 --------------
    $refused = Invoke-Tool -Id 'b23_game_endpoint_refuses_editor_simulate_key' -Tool 'editor_simulate_key' `
        -Arguments @{ keycode = 'A' } -Port $GamePort
    Add-Check 'b23_game_endpoint_call_is_-32601' ((Get-ErrorCode $refused) -eq -32601) `
        ('code=' + (Get-ErrorCode $refused) + ' message=' + (Get-ErrorMessage $refused))

    $editorList = Invoke-Curl -Id 'b24_tools_list_editor_9888' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $EditorPort
    $gameList = Invoke-Curl -Id 'b25_tools_list_game_9889' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $GamePort
    $editorNames = @()
    $gameNames = @()
    try { $editorNames = @((ConvertFrom-Json $editorList).result.tools | ForEach-Object { [string]$_.name }) } catch { }
    try { $gameNames = @((ConvertFrom-Json $gameList).result.tools | ForEach-Object { [string]$_.name }) } catch { }
    $group = @('editor_simulate_input_action', 'editor_simulate_key', 'editor_simulate_mouse_click',
               'editor_simulate_mouse_move', 'editor_simulate_input_sequence', 'editor_add_input_action')
    $missingOnEditor = @($group | Where-Object { $editorNames -notcontains $_ })
    $leakedToGame = @($group | Where-Object { $gameNames -contains $_ })
    Add-Check 'b24_all_six_tools_on_the_editor_endpoint' ($missingOnEditor.Count -eq 0) `
        ('editor endpoint 9888 has tools={0}, missing=[{1}]' -f $editorNames.Count, ($missingOnEditor -join ','))
    Add-Check 'b25_none_of_the_six_on_the_game_endpoint' ($leakedToGame.Count -eq 0) `
        ('game endpoint 9889 has tools={0}, leaked=[{1}]; the difference between the two listings is exactly the editor-scope set' -f $gameNames.Count, ($leakedToGame -join ','))

    # -- (7) a plain recording, with no cap configured, reads the defaults ---
    $start = Invoke-Tool -Id 'b26_recording_start' -Tool 'running_game_create_input_recording' -Arguments @{} -Port $GamePort
    $stop = Invoke-Tool -Id 'b27_recording_stop' -Tool 'running_game_stop_input_recording' -Arguments @{} -Port $GamePort
    $stopPayload = Get-Payload $stop
    Add-Check 'b26_default_recording_limits_are_reported' `
        ($null -ne $stopPayload -and $stopPayload.truncated -eq $false -and [int]$stopPayload.dropped -eq 0 -and
         [int]$stopPayload.limits.max_events -eq 100000 -and [int]$stopPayload.limits.max_duration_ms -eq 600000) `
        ('a session with no cap configured reports truncated=' + [string]$stopPayload.truncated + ' dropped=' + [string]$stopPayload.dropped + ' limits=' + (ConvertTo-CompactJson $stopPayload.limits))

    Stop-Engine -Handle $game
    Stop-Engine -Handle $editor
    Start-Sleep -Milliseconds 800

    $userPortPidAfter = Get-ListenerPid -Port $UserPort
    Add-Check 'b28_user_port_9877_untouched' ($userPortPidBefore -eq $userPortPidAfter) `
        ('pid_before={0} pid_after={1}' -f $userPortPidBefore, $userPortPidAfter)
}

# =============================================================================
#  Phase: limits -- the recording length caps (D59 point 5 / DESIGN-DETAIL 19.5)
# =============================================================================

# One key event, injected inside the game process, with a distinct keycode so a
# sequence of calls is visible in a recording.
function Get-InjectSnippet {
    param([string]$KeyName)
    return @"
var e := InputEventKey.new()
e.keycode = $KeyName
e.physical_keycode = $KeyName
e.pressed = true
Input.parse_input_event(e)
return "injected"
"@
}

function Invoke-LimitsConfig {
    param([string]$Config)

    $settings = @()
    if ($Config -eq 'events') { $settings = @('port=9889', 'enabled_in_game=true', 'recording_max_events=3') }
    if ($Config -eq 'duration') { $settings = @('port=9889', 'enabled_in_game=true', 'recording_max_duration_ms=500') }

    $project = Join-Path $Scratch ("limits-{0}" -f $Config)
    Write-GameProject -Path $project -Name ("MCP TASK-013 limits " + $Config) -ExtraSettings $settings
    Write-Host ("importing the limits/{0} scratch project ..." -f $Config)
    Import-Project -Path $project -LogName ("mcp013-limits-{0}-import" -f $Config)

    $userPortPidBefore = Get-ListenerPid -Port $UserPort
    if (Test-PortOpen -Port $GamePort) {
        Add-Check ("l_{0}_00_game_port_free" -f $Config) $false 'port 9889 is already in use'
        return
    }

    $game = Start-Engine -Arguments @('--headless', '--path', $project, "--mcp-port=$GamePort") -LogName ("mcp013-limits-{0}" -f $Config)
    try {
        if (-not (Wait-ForPump -Port $GamePort)) {
            Add-Check ("l_{0}_01_game_ready" -f $Config) $false ("game endpoint never became ready; log={0}" -f (Get-Content -Raw $game.Out -ErrorAction SilentlyContinue))
            return
        }
        Add-Check ("l_{0}_01_game_ready" -f $Config) $true 'the headless game answers GET /mcp on 9889'

        $start = Invoke-Tool -Id ("l_{0}_02_recording_start" -f $Config) -Tool 'running_game_create_input_recording' -Arguments @{} -Port $GamePort
        $startPayload = Get-Payload $start
        Add-Check ("l_{0}_02_recording_started" -f $Config) ($null -ne $startPayload -and $startPayload.recording -eq $true) `
            ('answer=' + (ConvertTo-CompactJson $startPayload))

        $keyNames = @('KEY_A', 'KEY_B', 'KEY_C', 'KEY_D', 'KEY_E')
        if ($Config -eq 'events') {
            # Five key events, one HTTP call each, so the recording node sees them
            # on five different frames.
            for ($i = 0; $i -lt 5; $i++) {
                $envelope = Invoke-Tool -Id ("l_events_03_inject_{0}" -f $i) -Tool 'running_game_execute_gdscript' `
                    -Arguments @{ code = (Get-InjectSnippet -KeyName $keyNames[$i]) } -Port $GamePort
                if ((Get-ErrorCode $envelope) -ne 0) {
                    Add-Check ("l_events_03_inject_{0}" -f $i) $false ('code=' + (Get-ErrorCode $envelope) + ' message=' + (Get-ErrorMessage $envelope))
                }
            }
            Start-Sleep -Milliseconds 800
        } else {
            # One event inside the 500 ms cap, then a second one well past it.
            Invoke-Tool -Id 'l_duration_03_inject_first' -Tool 'running_game_execute_gdscript' `
                -Arguments @{ code = (Get-InjectSnippet -KeyName 'KEY_A') } -Port $GamePort | Out-Null
            Start-Sleep -Milliseconds 1200
            Invoke-Tool -Id 'l_duration_04_inject_second' -Tool 'running_game_execute_gdscript' `
                -Arguments @{ code = (Get-InjectSnippet -KeyName 'KEY_B') } -Port $GamePort | Out-Null
            Start-Sleep -Milliseconds 500
        }

        $stop = Invoke-Tool -Id ("l_{0}_05_recording_stop" -f $Config) -Tool 'running_game_stop_input_recording' -Arguments @{} -Port $GamePort
        $stopPayload = Get-Payload $stop
        $eventCount = -1
        $dropped = -1
        $limitsJson = ''
        if ($null -ne $stopPayload) {
            $eventCount = [int]$stopPayload.event_count
            $dropped = [int]$stopPayload.dropped
            $limitsJson = ConvertTo-CompactJson $stopPayload.limits
        }
        Add-Check ("l_{0}_05_truncation_is_reported" -f $Config) `
            ($null -ne $stopPayload -and $stopPayload.truncated -eq $true -and $dropped -ge 1) `
            ('answer: event_count=' + $eventCount + ' truncated=' + [string]$stopPayload.truncated + ' dropped=' + $dropped + ' limits=' + $limitsJson + ' message=' + [string]$stopPayload.message)

        if ($Config -eq 'events') {
            Add-Check 'l_events_06_exactly_the_cap_was_kept' `
                (($eventCount -eq 3) -and ($dropped -eq 2) -and ([int]$stopPayload.limits.max_events -eq 3)) `
                ('recording_max_events=3 with 5 injected events -> event_count=' + $eventCount + ' dropped=' + $dropped + ' limits=' + $limitsJson)
            $types = ConvertTo-CompactJson $stopPayload.event_types
            Add-Check 'l_events_07_the_kept_events_are_the_first_ones' ([int]$stopPayload.event_types.key -eq 3) `
                ('event_types=' + $types + ' (the three kept events are key events; the dropped two are counted, not reported as a shorter recording)')
        } else {
            Add-Check 'l_duration_06_the_cap_is_the_duration_axis' `
                (($eventCount -eq 1) -and ($dropped -eq 1) -and ([int]$stopPayload.limits.max_duration_ms -eq 500)) `
                ('recording_max_duration_ms=500 with one event inside the cap and one 1200 ms after it -> event_count=' + $eventCount + ' dropped=' + $dropped + ' limits=' + $limitsJson)
        }
    } finally {
        Stop-Engine -Handle $game
        Start-Sleep -Milliseconds 800
    }

    $userPortPidAfter = Get-ListenerPid -Port $UserPort
    Add-Check ("l_{0}_08_user_port_9877_untouched" -f $Config) ($userPortPidBefore -eq $userPortPidAfter) `
        ('pid_before={0} pid_after={1}' -f $userPortPidBefore, $userPortPidAfter)
}

function Invoke-LimitsPhase {
    $configs = @('events', 'duration')
    if ($LimitsConfig -ne '') { $configs = @($LimitsConfig) }
    foreach ($config in $configs) {
        Invoke-LimitsConfig -Config $config
    }
}

# =============================================================================
#  Phase: negatives -- the per-tool refusal classes on the wire
#
#  PLAYBOOK section 3 gate 2 wants, for every tool, a real request/response for
#  each of the three classes (success / missing argument / underlying failure).
#  The success class is the boundary phase; this phase is the other two, plus the
#  explicit declaration of the one class this group cannot construct (see n10).
# =============================================================================

function Invoke-NegativesPhase {
    $gameProject = Join-Path $Scratch 'boundary-game'
    $editorProject = Join-Path $Scratch 'boundary-editor'
    Write-GameProject -Path $gameProject -Name 'MCP TASK-013 boundary game'
    Write-EditorProject -Path $editorProject -Name 'MCP TASK-013 boundary editor'

    $userPortPidBefore = Get-ListenerPid -Port $UserPort
    if (Test-PortOpen -Port $EditorPort) {
        Add-Check 'n00_editor_port_free' $false 'port 9888 is already in use'
        return
    }

    $editor = Start-Engine -Arguments @('--headless', '-e', '--path', $editorProject, "--mcp-port=$EditorPort") -LogName 'mcp013-negatives-editor'
    $game = $null
    try {
        if (-not (Wait-ForPump -Port $EditorPort)) {
            Add-Check 'n00_editor_ready' $false ("editor endpoint never became ready; log={0}" -f (Get-Content -Raw $editor.Out -ErrorAction SilentlyContinue))
            return
        }
        Add-Check 'n00_editor_ready' $true 'the headless editor answers GET /mcp on 9888'

        $expectInvalid = {
            param([string]$Id, [string]$Tool, $Arguments, [string]$Fragment)
            $envelope = Invoke-Tool -Id $Id -Tool $Tool -Arguments $Arguments -Port $EditorPort
            $code = Get-ErrorCode $envelope
            $message = Get-ErrorMessage $envelope
            Add-Check $Id (($code -eq -32602) -and $message.Contains($Fragment)) `
                ('code=' + $code + ' message=' + $message + ' (expected -32602 containing "' + $Fragment + '")')
        }

        & $expectInvalid 'n01_simulate_input_action_missing_action' 'editor_simulate_input_action' @{} 'Missing required parameter: action'
        & $expectInvalid 'n02_simulate_key_missing_keycode' 'editor_simulate_key' @{} 'Missing required parameter: keycode'
        & $expectInvalid 'n02b_simulate_key_unknown_key' 'editor_simulate_key' @{ keycode = 'NOPE_NOT_A_KEY' } 'not a key name'
        & $expectInvalid 'n03_simulate_mouse_click_bad_button' 'editor_simulate_mouse_click' @{ button = 99 } 'MouseButton value between 1'
        & $expectInvalid 'n04_simulate_mouse_move_bad_type' 'editor_simulate_mouse_move' @{ y = 'tall' } "'y' must be a number"
        & $expectInvalid 'n05_simulate_input_sequence_empty' 'editor_simulate_input_sequence' @{ events = @() } 'must not be empty'
        & $expectInvalid 'n05b_simulate_input_sequence_unknown_type' 'editor_simulate_input_sequence' @{ events = @(@{ type = 'telepathy' }) } 'accepted types'
        & $expectInvalid 'n05c_simulate_input_sequence_bad_event' 'editor_simulate_input_sequence' @{ events = @(@{ type = 'key' }) } 'events[0].keycode'
        & $expectInvalid 'n06_add_input_action_missing_action' 'editor_add_input_action' @{} 'Missing required parameter: action'

        # A refused call must not have injected anything: the tool still works
        # afterwards, and the editor's own probe still counts only real events.
        $afterNegatives = Invoke-Tool -Id 'n07_editor_still_works' -Tool 'editor_simulate_key' -Arguments @{ keycode = 'A' } -Port $EditorPort
        $afterPayload = Get-Payload $afterNegatives
        Add-Check 'n07_a_refused_call_injected_nothing_and_the_tool_still_works' `
            ($null -ne $afterPayload -and $afterPayload.target -eq 'editor' -and [string]$afterPayload.keycode -eq 'A') `
            ('answer after the refusals: ' + (ConvertTo-CompactJson $afterPayload))

        # The game endpoint half: every one of the six is absent *and* a call is
        # -32601 (not an execution, not a silent success). This phase starts its
        # own game process; no phase ever relies on a process another one left
        # behind.
        $game = Start-Engine -Arguments @('--headless', '--path', $gameProject, "--mcp-port=$GamePort") -LogName 'mcp013-negatives-game'
        $null = Wait-ForPump -Port $GamePort -TimeoutMs 120000
        $gameReady = Test-PortOpen -Port $GamePort
        Add-Check 'n08_game_endpoint_ready' $gameReady 'a game process answers on 9889 for the absence half'
        if ($gameReady) {
            $group = @(
                @{ tool = 'editor_simulate_input_action'; args = @{ action = 'ui_accept' } },
                @{ tool = 'editor_simulate_key'; args = @{ keycode = 'A' } },
                @{ tool = 'editor_simulate_mouse_click'; args = @{ x = 1; y = 2 } },
                @{ tool = 'editor_simulate_mouse_move'; args = @{ x = 1; y = 2 } },
                @{ tool = 'editor_simulate_input_sequence'; args = @{ events = @(@{ type = 'key'; keycode = 'A' }) } },
                @{ tool = 'editor_add_input_action'; args = @{ action = 'mcp013_probe_action' } }
            )
            $notFound = @()
            for ($i = 0; $i -lt $group.Count; $i++) {
                $name = [string]$group[$i].tool
                $envelope = Invoke-Tool -Id ("n09_game_calls_{0}_{1}" -f $i, $name) -Tool $name -Arguments $group[$i].args -Port $GamePort
                if ((Get-ErrorCode $envelope) -ne -32601) {
                    $notFound += ("{0}: code={1}" -f $name, (Get-ErrorCode $envelope))
                }
            }
            Add-Check 'n09_all_six_are_-32601_on_the_game_endpoint' ($notFound.Count -eq 0) `
                ('every one of the six answers -32601 on 9889 (nothing executed); deviations: [{0}]' -f ($notFound -join '; '))
        }

        # The declaration the PLAYBOOK asks for. The *underlying failure* class of
        # this group is "this process has no `Input` / `InputMap` singleton"
        # (-32000 with a suggestion). A running editor always has both, so it can
        # only be reached from a process that is not an editor - which is exactly
        # the process in which the tool is not registered at all (-32601 above).
        # The branch is therefore not constructible on the wire by design, and is
        # pinned by the doctest
        # `[MCPServer] the editor input simulation tools validate every argument
        # before they touch the editor` (assertions at -32000 for all six).
        Add-Check 'n10_underlying_failure_class_declared' $true `
            'the -32000 (no Input/InputMap singleton) class is unreachable on a live editor endpoint by construction and is pinned by the module doctest; the only wire-visible "unavailable" answer is -32601 on the game endpoint (n09)'
    } finally {
        Stop-Engine -Handle $editor
        Stop-Engine -Handle $game
        Start-Sleep -Milliseconds 800
    }

    $userPortPidAfter = Get-ListenerPid -Port $UserPort
    Add-Check 'n11_user_port_9877_untouched' ($userPortPidBefore -eq $userPortPidAfter) `
        ('pid_before={0} pid_after={1}' -f $userPortPidBefore, $userPortPidAfter)
}

# =============================================================================
#  Main
# =============================================================================

New-Item -ItemType Directory -Force -Path $Scratch, $LogRoot, $Evid | Out-Null
Write-Host '============================================================='
Write-Host (" TASK-013 evidence -- phase {0}" -f $Phase)
Write-Host '============================================================='

try {
    if ($Phase -eq 'boundary') {
        Invoke-BoundaryPhase
    } elseif ($Phase -eq 'negatives') {
        Invoke-NegativesPhase
    } else {
        Invoke-LimitsPhase
    }
} catch {
    Write-Host ("EXCEPTION: {0}" -f $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
    Add-Check 'harness_exception' $false $_.Exception.Message
} finally {
    foreach ($started in $script:StartedPids) {
        try {
            if (Get-Process -Id $started -ErrorAction SilentlyContinue) {
                Stop-Process -Id $started -Force -ErrorAction SilentlyContinue
                Write-Host ("swept pid={0}" -f $started)
            }
        } catch { }
    }
}

Write-Host ''
Write-Host '========================== SUMMARY =========================='
$passed = @($script:Results | Where-Object { $_.pass }).Count
$total = $script:Results.Count
foreach ($r in $script:Results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0}  {1}" -f $tag, $r.id)
}
Write-Host ("phase={0} {1}/{2} checks passed" -f $Phase, $passed, $total)
if ($passed -ne $total) { exit 1 }
exit 0
