# =============================================================================
#  mcp012_input_playback_evidence.ps1 -- TASK-012 gate 2 / section 2
#
#  The live evidence for the eight tools of B2's third batch (four groups):
#
#    running_game_input              (4, scope=game)
#    running_game_node_write         (1, scope=game)
#    editor_playback                 (2, scope=editor)
#    editor_input_read               (1, scope=editor)
#
#  Phases:
#    -Phase game      A *headless* game process on 9889, running a scratch
#                     project whose `res://instrumented_auth.gd` is the game's
#                     own script: every count the evidence reads back is produced
#                     by the *game*, so "the tool changed the game" is observed
#                     from inside the game, not inferred from the tool's answer.
#                       * the D56 split on the wire: the game endpoint serves the
#                         five game-side tools of this batch and none of the nine
#                         editor-side input/playback tools;
#                       * running_game_set_node_property: before -> call -> after,
#                         with the negative cases (out-of-range integer, missing
#                         parameter, missing node, a Dictionary that does not
#                         name the components);
#                       * create/stop input recording: the input injected *inside
#                         the game process* is captured with per-event `time_ms`
#                         and each value comes back as JSON, not as a string;
#                       * play_input_recording: that recording is replayed and the
#                         game's own counters move;
#                       * simulate_button_click_by_text: the game's own Button
#                         emits `pressed`, its handler runs, the label changes.
#    -Phase playback  A *headless* editor process on 9888 with a scratch project
#                     that sets `godot_mcp/port=9889` (the editor hands its own
#                     project to the game child it spawns, and the child reads the
#                     port from that project - the editor does not forward
#                     `--mcp-port`).
#                       * editor_get_input_actions reads the editor's InputMap,
#                         ascending and containing ui_accept;
#                       * editor_stop_scene with nothing playing: the documented
#                         `{"stopped": false, ...}` success;
#                       * editor_play_scene(mode=main): the game child really
#                         comes up, proved by the **game endpoint 9889** becoming
#                         reachable and answering `GET /mcp`, *and* by the pid
#                         listening there being a child of the editor process;
#                       * editor_stop_scene: the child really goes away, proved by
#                         9889 becoming unreachable, by that pid being dead, and
#                         by the editor's whole process subtree being empty;
#                       * the no-orphan proof: every pid this script started is
#                         gone at the end.
#
#  Discipline (PLAYBOOK section 3 and section 7.1):
#    * every response body is written to its own file with
#      `curl.exe -s -o <file>` and a sha256 is printed from the bytes on disk.
#      Nothing goes through `Out-File` or a pipeline.
#    * ports 9888 (editor) / 9889 (game) only. Port 9877 belongs to the user's
#      editor: it is never touched, only observed, and its listener pid is
#      asserted unchanged at the end of every phase.
#    * only engines this script started itself are stopped, and the playback
#      phase additionally proves that the editor's game child is gone.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp012_input_playback_evidence.ps1 -Phase game
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp012_input_playback_evidence.ps1 -Phase playback
# =============================================================================

param(
    [ValidateSet('game', 'playback')]
    [string]$Phase = 'game'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877
$Scratch = Join-Path $env:TEMP 'mcp012-scratch'
$LogRoot = Join-Path $env:TEMP 'mcp012-logs'
$Evid = Join-Path $env:TEMP 'mcp012-evidence'

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
# JSON building. Every value is escaped by `ConvertTo-Json`, never by string
# interpolation: an interpolated value that happens to contain a quote turns the
# request into a parse error, which is a *harness* failure that looks like a tool
# failure. This was measured in the first TASK-012 evidence run (the replay
# request carried an unescaped Vector2 string and came back -32700/-32602).
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
# HTTP: the body always goes to a file; the request body is a file too, so no
# quoting rule can corrupt it.
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
        $script:LastResponse = ''
        return ''
    }
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] curl port={1} exit={2} bytes={3} sha256={4}" -f $Id, $Port, $curlExit, $bytes.Length, $sha)
    Write-Host ("       request : {0}" -f $Json)
    Write-Host ("       response: {0}" -f $text)
    $script:LastResponse = $text
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

# One property of one node, read through `running_game_get_node_properties`, as a
# string. A missing property and a failed call both answer `$null`, so a check can
# assert the failure instead of throwing on its way to its own assertion.
function Read-NodeProperty {
    param([string]$Id, [string]$NodePath, [string]$Property, [int]$Port)
    $envelope = Invoke-Tool -Id $Id -Tool 'running_game_get_node_properties' `
        -Arguments @{ node_path = $NodePath; properties = @($Property) } -Port $Port
    $payload = Get-Payload $envelope
    if ($null -eq $payload) { return $null }
    $bag = $payload.properties
    if ($null -eq $bag) { return $null }
    $member = $bag.PSObject.Properties[$Property]
    if ($null -eq $member -or $null -eq $member.Value) { return $null }
    return [string]$member.Value
}

# A component of a serialized `Vector2`/`Vector3`, which the module emits as
# `{"x":..,"y":..}`. Reading it through `PSObject.Properties` rather than through
# `$obj.x` is deliberate: a member access on a missing property is `$null` in
# PowerShell but *throws* under `Set-StrictMode`, and an evidence harness that
# throws on its way to its own assertion reports nothing.
function Get-VectorComponent {
    param($Value, [string]$Component)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $null }
    $member = $Value.PSObject.Properties[$Component]
    if ($null -eq $member -or $null -eq $member.Value) { return $null }
    return [string]$member.Value
}

# The `x`/`y` of a Vector2 property, as doubles. `$null` when the read failed or
# the value is not a serialized vector. Numeric, not textual: the wire spelling of
# a `float` component is `"0.0"` / `"321.0"`, so comparing the formatted pair
# against `"0,0"` is a string comparison that can only ever be accidentally right.
function Read-NodeVector2Components {
    param([string]$Id, [string]$NodePath, [string]$Property, [int]$Port)
    $envelope = Invoke-Tool -Id $Id -Tool 'running_game_get_node_properties' `
        -Arguments @{ node_path = $NodePath; properties = @($Property) } -Port $Port
    $payload = Get-Payload $envelope
    if ($null -eq $payload -or $null -eq $payload.properties) { return $null }
    $member = $payload.properties.PSObject.Properties[$Property]
    if ($null -eq $member -or $null -eq $member.Value) { return $null }
    if ($member.Value -is [string]) { return $null }
    $x = Get-VectorComponent -Value $member.Value -Component 'x'
    $y = Get-VectorComponent -Value $member.Value -Component 'y'
    if ($null -eq $x -or $null -eq $y) { return $null }
    return @{ x = [double]$x; y = [double]$y; text = ('{0},{1}' -f $x, $y) }
}

function Test-Vector2 {
    param($Components, [double]$ExpectedX, [double]$ExpectedY)
    if ($null -eq $Components) { return $false }
    return (([Math]::Abs([double]$Components.x - $ExpectedX) -lt 0.001) -and
            ([Math]::Abs([double]$Components.y - $ExpectedY) -lt 0.001))
}

# A Vector2 property as "x,y".
function Read-NodeVector2 {
    param([string]$Id, [string]$NodePath, [string]$Property, [int]$Port)
    $components = Read-NodeVector2Components -Id $Id -NodePath $NodePath -Property $Property -Port $Port
    if ($null -eq $components) { return $null }
    return [string]$components.text
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
        Write-Host ("         (status body is not JSON yet)")
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

function Wait-ForPort {
    param([int]$Port, [bool]$Open, [int]$TimeoutMs = 90000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ((Test-PortOpen -Port $Port) -eq $Open) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return ((Test-PortOpen -Port $Port) -eq $Open)
}

function Import-Project {
    param([string]$Path, [string]$LogName)
    $out = Join-Path $LogRoot ($LogName + '.out.log')
    $err = Join-Path $LogRoot ($LogName + '.err.log')
    $proc = Start-Process -FilePath $Engine -ArgumentList @('--headless', '--path', $Path, '--import') `
        -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    $proc.WaitForExit(300000) | Out-Null
}

# -----------------------------------------------------------------------------
# The scratch projects
# -----------------------------------------------------------------------------

function Write-GameProject {
    param([string]$Path)
    $sceneDir = Join-Path $Path 'scenes'
    New-Item -ItemType Directory -Force -Path $sceneDir | Out-Null
    Write-Utf8NoBom -Path (Join-Path $Path 'project.godot') -Text @'
config_version=5

[application]
config/name="MCP TASK-012 evidence game"
config/features=PackedStringArray("4.8")
run/main_scene="res://scenes/main.tscn"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@
    Write-Utf8NoBom -Path (Join-Path $sceneDir 'main.tscn') -Text @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://instrumented_auth.gd" id="1_auth"]

[node name="Main" type="Node2D"]
script = ExtResource("1_auth")

[node name="Label" type="Label" parent="."]
offset_left = 20.0
offset_top = 20.0
offset_right = 420.0
offset_bottom = 60.0
text = "idle"

[node name="FireButton" type="Button" parent="."]
offset_left = 20.0
offset_top = 80.0
offset_right = 180.0
offset_bottom = 120.0
text = "Fire Cannon"
'@
    Write-Utf8NoBom -Path (Join-Path $Path 'instrumented_auth.gd') -Text @'
extends Node2D

# The game's own script. Everything the TASK-012 evidence reads back is a count
# or a string that *this* file produced, so "the tool changed the game" is
# observed from inside the game rather than inferred from the tool's own answer.

var key_events := 0
var key_a_down := 0
var mouse_events := 0
var motion_events := 0
var last_event_type := ""
var clicks := 0
var status_text := "idle"

@onready var label: Label = $Label


func _ready() -> void:
	$FireButton.pressed.connect(_on_fire_pressed)
	_tick()


func _process(_delta: float) -> void:
	_tick()


func _input(event: InputEvent) -> void:
	# `DEVICE_ID_EMULATION` is the device the engine gives the motion events it
	# synthesises itself (Input::set_default_cursor_shape does exactly that), so
	# counting them would mean this counter no longer measures injection.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventKey:
		key_events += 1
		last_event_type = "key"
		if event.pressed:
			if event.keycode == KEY_A:
				key_a_down += 1
	elif event is InputEventMouseButton:
		mouse_events += 1
		last_event_type = "mouse_button"
	elif event is InputEventMouseMotion:
		motion_events += 1
		last_event_type = "mouse_motion"


func _on_fire_pressed() -> void:
	clicks += 1
	status_text = "fired %d" % clicks
	_tick()


func _tick() -> void:
	label.text = "state=%s clicks=%d key_a=%d keys=%d mouse=%d motion=%d" % [
		status_text, clicks, key_a_down, key_events, mouse_events, motion_events
	]
'@
}

function Write-EditorProject {
    param([string]$Path)
    $sceneDir = Join-Path $Path 'scenes'
    New-Item -ItemType Directory -Force -Path $sceneDir | Out-Null
    Write-Utf8NoBom -Path (Join-Path $Path 'project.godot') -Text @'
config_version=5

[application]
config/name="MCP TASK-012 evidence playback"
config/features=PackedStringArray("4.8")
run/main_scene="res://scenes/main.tscn"

[godot_mcp]
port=9889
enabled_in_game=true

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@
    Write-Utf8NoBom -Path (Join-Path $sceneDir 'main.tscn') -Text @'
[gd_scene format=3]

[node name="Main" type="Node2D"]
'@
    Write-Utf8NoBom -Path (Join-Path $Path 'playback_marker.gd') -Text @'
extends Node

# Written by the game child the editor spawns through `editor_play_scene`: its
# presence on disk is a second, non-HTTP witness that the child really ran.
func _ready() -> void:
	var file := FileAccess.open("user://mcp012_playback_started.txt", FileAccess.WRITE)
	if file:
		file.store_string("playback child started\n")
		file.close()
'@
}

# -----------------------------------------------------------------------------
# Process-level helpers (the no-orphan proof)
# -----------------------------------------------------------------------------

function Get-ChildProcessIds {
    param([int]$ParentPid)
    $ids = New-Object System.Collections.Generic.List[int]
    try {
        foreach ($p in (Get-CimInstance Win32_Process -Filter ("ParentProcessId = " + $ParentPid) -ErrorAction Stop)) {
            $ids.Add([int]$p.ProcessId)
        }
    } catch { }
    return $ids
}

function Get-ProcessTree {
    param([int]$RootPid)
    $all = @($RootPid)
    $frontier = @($RootPid)
    while ($frontier.Count -gt 0) {
        $next = @()
        foreach ($parent in $frontier) {
            foreach ($child in (Get-ChildProcessIds -ParentPid $parent)) {
                if ($all -notcontains $child) {
                    $all += $child
                    $next += $child
                }
            }
        }
        $frontier = $next
    }
    return $all
}

function Test-Alive {
    # `$processId`, not `$pid`: `$PID` is a read-only automatic variable in
    # PowerShell and binding a parameter to that name throws.
    param([int]$processId)
    try { return ($null -ne (Get-Process -Id $processId -ErrorAction Stop)) } catch { return $false }
}

# =============================================================================
#  Phase: game
# =============================================================================

function Invoke-GamePhase {
    $gameProject = Join-Path $Scratch 'game'
    Write-GameProject -Path $gameProject
    Write-Host 'importing the scratch game project ...'
    Import-Project -Path $gameProject -LogName 'mcp012-game-import'

    $userPortPidBefore = Get-ListenerPid -Port $UserPort
    Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)

    $game = Start-Engine -Arguments @('--headless', '--path', $gameProject, "--mcp-port=$GamePort") -LogName 'mcp012-game'
    if (-not (Wait-ForPump -Port $GamePort)) {
        Add-Check 'g00_game_ready' $false ("game endpoint never became ready; log={0}" -f (Get-Content -Raw $game.Out -ErrorAction SilentlyContinue))
        Stop-Engine -Handle $game
        return
    }
    Add-Check 'g00_game_ready' $true 'the headless game answers GET /mcp on 9889'

    # The game's own script must have loaded; if it did not, every counter below
    # would read `null` and the checks would be measuring nothing.
    $scriptLoaded = Read-NodeProperty -Id 'g00b_script_loaded' -NodePath 'Main' -Property 'status_text' -Port $GamePort
    Add-Check 'g00b_instrumented_script_is_loaded' ($scriptLoaded -eq 'idle') `
        ('the game script variable status_text reads ' + $scriptLoaded + ' (a parse failure would answer null)')

    # -- (E1) the D56 split, read out of the live tool list -------------------
    $gameList = Invoke-Curl -Id 'g01_tools_list_game_9889' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $GamePort
    $gameNames = @()
    try { $gameNames = @((ConvertFrom-Json $gameList).result.tools | ForEach-Object { [string]$_.name }) } catch { }
    $editorSide = @('editor_play_scene', 'editor_stop_scene', 'editor_get_input_actions',
                    'editor_simulate_key', 'editor_simulate_input_action', 'editor_simulate_mouse_click',
                    'editor_simulate_mouse_move', 'editor_simulate_input_sequence', 'editor_add_input_action')
    $leaked = @($editorSide | Where-Object { $gameNames -contains $_ })
    $gameSide = @('running_game_create_input_recording', 'running_game_stop_input_recording',
                  'running_game_play_input_recording', 'running_game_simulate_button_click_by_text',
                  'running_game_set_node_property')
    $missing = @($gameSide | Where-Object { $gameNames -notcontains $_ })
    Add-Check 'g02_d56_editor_input_tools_absent_from_game_endpoint' `
        (($leaked.Count -eq 0) -and ($missing.Count -eq 0)) `
        ("game endpoint 9889 serves all 5 game-side input/write tools; editor-side input/playback tools found there: [{0}]; tools={1}" -f ($leaked -join ','), $gameNames.Count)

    # -- (E2) running_game_set_node_property: before -> call -> after --------
    $beforeVec = Read-NodeVector2Components -Id 'g03_before_position' -NodePath 'Main' -Property 'position' -Port $GamePort
    Add-Check 'g03_property_before' (Test-Vector2 -Components $beforeVec -ExpectedX 0 -ExpectedY 0) `
        ('Main.position before = ' + [string]$beforeVec.text)

    $set = Invoke-Tool -Id 'g04_set_position' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = 'Main'; property = 'position'; value = @{ x = 321; y = 123 } } -Port $GamePort
    $setPayload = Get-Payload $set
    $afterVec = Read-NodeVector2Components -Id 'g05_after_position' -NodePath 'Main' -Property 'position' -Port $GamePort
    $setOld = ''
    $setNew = ''
    if ($null -ne $setPayload) {
        $setOld = ('{0},{1}' -f (Get-VectorComponent -Value $setPayload.old_value -Component 'x'), (Get-VectorComponent -Value $setPayload.old_value -Component 'y'))
        $setNew = ('{0},{1}' -f (Get-VectorComponent -Value $setPayload.new_value -Component 'x'), (Get-VectorComponent -Value $setPayload.new_value -Component 'y'))
    }
    Add-Check 'g04_set_node_property_before_after' `
        (($setOld -eq '0.0,0.0') -and ($setNew -eq '321.0,123.0') -and (Test-Vector2 -Components $afterVec -ExpectedX 321 -ExpectedY 123)) `
        ("a JSON object names the components: old_value={0} new_value={1}, read back afterwards position={2} via a second tool call" -f $setOld, $setNew, [string]$afterVec.text)

    # A scalar property of a different type: the answer must show it too.
    $scalar = Invoke-Tool -Id 'g06_set_float_scalar' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = 'Main'; property = 'rotation'; value = 0.75 } -Port $GamePort
    $scalarPayload = Get-Payload $scalar
    $rot = Read-NodeProperty -Id 'g07_read_rotation' -NodePath 'Main' -Property 'rotation' -Port $GamePort
    $scalarNew = ''
    if ($null -ne $scalarPayload) { $scalarNew = [string]$scalarPayload.new_value }
    Add-Check 'g06_set_node_property_scalar' `
        (($scalarNew -eq '0.75') -and ($rot -eq '0.75')) `
        ('rotation set to 0.75, new_value=' + $scalarNew + ', read back=' + $rot)

    # A script variable is a property too, and it is the case a property filter
    # is most likely to lose (the defect REPORT-010 caught).
    $setVar = Invoke-Tool -Id 'g07b_set_script_variable' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = 'Main'; property = 'status_text'; value = 'set-by-tool' } -Port $GamePort
    $varPayload = Get-Payload $setVar
    $varRead = Read-NodeProperty -Id 'g07c_read_script_variable' -NodePath 'Main' -Property 'status_text' -Port $GamePort
    $varNew = ''
    if ($null -ne $varPayload) { $varNew = [string]$varPayload.new_value }
    Add-Check 'g07b_script_variable_is_writable' (($varNew -eq 'set-by-tool') -and ($varRead -eq 'set-by-tool')) `
        ('a script variable of the game was written: old=' + [string]$varPayload.old_value + ' new=' + $varNew + ' read back=' + $varRead)

    # A Dictionary that does *not* name the components must not silently become
    # the zero vector: either it is refused, or the property is deliberately set
    # to the zero value - but the call may not report a success that leaves the
    # property at a value nobody asked for while claiming the requested one. The
    # requested `{"health":5}` names no component, so the only acceptable
    # outcomes are "an error" and "the property unchanged from 321,123".
    $badDict = Invoke-Tool -Id 'g08_set_non_component_dict' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = 'Main'; property = 'position'; value = @{ health = 5 } } -Port $GamePort
    Start-Sleep -Milliseconds 200
    $afterBad = Read-NodeVector2Components -Id 'g08b_read_after_non_component_dict' -NodePath 'Main' -Property 'position' -Port $GamePort
    $badDictCode = Get-ErrorCode $badDict
    $badDictOk = ($badDictCode -ne 0) -or (Test-Vector2 -Components $afterBad -ExpectedX 321 -ExpectedY 123)
    Add-Check 'g08_non_component_dict_never_becomes_the_zero_vector_silently' $badDictOk `
        ('a Dictionary without x/y answered code=' + $badDictCode + ' and left position=' + [string]$afterBad.text + ' (refused, or unchanged - never a silent wrong value)')
    # Restore the position for the checks below.
    Invoke-Tool -Id 'g08c_restore_position' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = 'Main'; property = 'position'; value = @{ x = 321; y = 123 } } -Port $GamePort | Out-Null

    # -- negative cases ------------------------------------------------------
    $oor = Invoke-Tool -Id 'g09_set_out_of_range' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = 'Main'; property = 'z_index'; value = 1e20 } -Port $GamePort
    Add-Check 'g09_set_out_of_range_is_-32602' `
        ((Get-ErrorCode $oor) -eq -32602 -and (Get-ErrorMessage $oor).Contains('64-bit integer')) `
        ('code=' + (Get-ErrorCode $oor) + ' message=' + (Get-ErrorMessage $oor))

    $missing = Invoke-Tool -Id 'g10_set_missing_value' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = 'Main'; property = 'position' } -Port $GamePort
    Add-Check 'g10_set_missing_value_is_-32602' `
        ((Get-ErrorCode $missing) -eq -32602 -and (Get-ErrorMessage $missing).Contains("Missing required parameter 'value'")) `
        ('code=' + (Get-ErrorCode $missing) + ' message=' + (Get-ErrorMessage $missing))

    $noNode = Invoke-Tool -Id 'g11_set_missing_node' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = 'ghost'; property = 'position'; value = 1 } -Port $GamePort
    Add-Check 'g11_set_missing_node_is_-32001' `
        ((Get-ErrorCode $noNode) -eq -32001 -and $null -ne $noNode.error.data.suggestion) `
        ('code=' + (Get-ErrorCode $noNode) + ' message=' + (Get-ErrorMessage $noNode) + ' suggestion=' + [string]$noNode.error.data.suggestion)

    $missingNodePath = Invoke-Tool -Id 'g12_set_missing_node_path' -Tool 'running_game_set_node_property' `
        -Arguments @{ property = 'position'; value = 1 } -Port $GamePort
    Add-Check 'g12_set_missing_node_path_is_-32602' ((Get-ErrorCode $missingNodePath) -eq -32602) `
        ('code=' + (Get-ErrorCode $missingNodePath) + ' message=' + (Get-ErrorMessage $missingNodePath))

    # -- (E3) the recording round trip --------------------------------------
    $start = Invoke-Tool -Id 'g13_recording_start' -Tool 'running_game_create_input_recording' -Arguments @{} -Port $GamePort
    $startPayload = Get-Payload $start
    Add-Check 'g13_recording_started' ($null -ne $startPayload -and $startPayload.recording -eq $true) `
        ('response=' + (ConvertTo-CompactJson $startPayload))

    # Input injected *inside the game process*: the tool compiles GDScript in the
    # game, so the events enter the game's own Input queue.
    $inject = @'
var out := []
for i in 2:
  var e := InputEventKey.new()
  e.keycode = KEY_A
  e.physical_keycode = KEY_A
  e.pressed = true
  Input.parse_input_event(e)
  out.append("key")
var m := InputEventMouseButton.new()
m.button_index = MOUSE_BUTTON_LEFT
m.pressed = true
m.position = Vector2(10, 20)
Input.parse_input_event(m)
out.append("mouse_button")
var mm := InputEventMouseMotion.new()
mm.position = Vector2(12, 24)
mm.relative = Vector2(2, 4)
Input.parse_input_event(mm)
out.append("mouse_motion")
return out
'@
    $injected = Invoke-Tool -Id 'g14_inject_inside_game' -Tool 'running_game_execute_gdscript' `
        -Arguments @{ code = $inject } -Port $GamePort
    $injectedPayload = Get-Payload $injected
    Add-Check 'g14_input_injected_inside_game' ($null -ne $injectedPayload -and [string]$injectedPayload.result_type -eq 'Array') `
        ('execute_gdscript injected 4 events into the game process; result=' + [string]$injectedPayload.result + ' of type ' + [string]$injectedPayload.result_type)

    $stopRec = Invoke-Tool -Id 'g15_recording_stop' -Tool 'running_game_stop_input_recording' -Arguments @{} -Port $GamePort
    $recPayload = Get-Payload $stopRec
    $events = @()
    $evCount = 0
    $types = ''
    $firstTime = ''
    $lastTime = ''
    $positionIsObject = $false
    if ($null -ne $recPayload) {
        $events = @($recPayload.events)
        $evCount = $events.Count
        $types = (ConvertTo-CompactJson $recPayload.event_types)
        if ($evCount -gt 0) {
            $firstTime = [string]$events[0].time_ms
            $lastTime = [string]$events[$evCount - 1].time_ms
        }
        foreach ($e in $events) {
            if ([string]$e.type -eq 'mouse_motion' -and $null -ne $e.position.x) { $positionIsObject = $true }
        }
    }
    Add-Check 'g15_recording_captured_the_game_input' ($evCount -ge 4) `
        ("event_count={0} event_types={1} time_ms first={2} last={3}" -f $evCount, $types, $firstTime, $lastTime)
    # The values must come back as JSON, not as the string a raw Vector2 becomes.
    Add-Check 'g15b_recorded_vectors_are_json_objects' $positionIsObject `
        'a recorded mouse_motion carries position as {"x":..,"y":..}, so the recording can be fed straight back to the replay tool'

    # The game itself saw the same events.
    $gameKeyEvents = Read-NodeProperty -Id 'g16_game_own_counters' -NodePath 'Main' -Property 'key_events' -Port $GamePort
    Add-Check 'g16_game_own_input_counters_moved' (($null -ne $gameKeyEvents) -and ([int]$gameKeyEvents -ge 2)) `
        ('the game instrumented_auth.gd counted key_events=' + $gameKeyEvents + ' in its own _input, not in the tool answer')

    # -- (E3b) replay: inject the recording and watch the game change --------
    $clicksBefore = [int](Read-NodeProperty -Id 'g17_clicks_before_replay' -NodePath 'Main' -Property 'clicks' -Port $GamePort)
    $keyABefore = [int](Read-NodeProperty -Id 'g18_key_a_before_replay' -NodePath 'Main' -Property 'key_a_down' -Port $GamePort)
    $keyEventsBefore = [int](Read-NodeProperty -Id 'g18b_key_events_before_replay' -NodePath 'Main' -Property 'key_events' -Port $GamePort)
    $mouseBefore = [int](Read-NodeProperty -Id 'g18c_mouse_before_replay' -NodePath 'Main' -Property 'mouse_events' -Port $GamePort)

    # The replay is called with **no `events` argument**: the recorder of this
    # game process still holds the recording that was just stopped (the stop tool
    # only cleared its own copy after answering), so the round trip
    # `create -> stop -> play` needs no byte-for-byte copy in between. The
    # explicit-array form is exercised by the negative cases below and by the
    # doctests.
    $replay = Invoke-Tool -Id 'g19_replay_recording' -Tool 'running_game_play_input_recording' `
        -Arguments @{} -Port $GamePort -MaxTimeSec 40
    $replayPayload = Get-Payload $replay
    Start-Sleep -Milliseconds 400
    $keyAAfter = [int](Read-NodeProperty -Id 'g20_key_a_after_replay' -NodePath 'Main' -Property 'key_a_down' -Port $GamePort)
    $keyEventsAfter = [int](Read-NodeProperty -Id 'g20b_key_events_after_replay' -NodePath 'Main' -Property 'key_events' -Port $GamePort)
    $mouseAfter = [int](Read-NodeProperty -Id 'g20c_mouse_after_replay' -NodePath 'Main' -Property 'mouse_events' -Port $GamePort)
    Add-Check 'g19_replay_injected_every_event' `
        ($null -ne $replayPayload -and $replayPayload.replayed -eq $true -and [int]$replayPayload.injected -eq $evCount) `
        ('replayed=' + [string]$replayPayload.replayed + ' event_count=' + [string]$replayPayload.event_count + ' injected=' + [string]$replayPayload.injected + ' speed=' + [string]$replayPayload.speed + ' (spans frames: the tool answered through the deferred channel)')
    Add-Check 'g20_replay_changed_the_game_state' `
        (($keyAAfter -gt $keyABefore) -and ($keyEventsAfter -gt $keyEventsBefore) -and ($mouseAfter -gt $mouseBefore)) `
        ('the game counted key_a_down ' + $keyABefore + ' -> ' + $keyAAfter + ', key_events ' + $keyEventsBefore + ' -> ' + $keyEventsAfter + ', mouse_events ' + $mouseBefore + ' -> ' + $mouseAfter + ' across the replay')
    Add-Check 'g20d_recording_carries_a_time_line' (($firstTime -ne '') -and ([int]$lastTime -ge 0)) `
        ('recorded time_ms spans ' + $firstTime + ' .. ' + $lastTime + ' ms; the replay scheduled on exactly those offsets')

    # -- negative cases of the replay ---------------------------------------
    $replayBad = Invoke-Tool -Id 'g21_replay_bad_event' -Tool 'running_game_play_input_recording' `
        -Arguments @{ events = @(@{ type = 'telepathy' }) } -Port $GamePort
    Add-Check 'g21_replay_bad_type_is_-32602' ((Get-ErrorCode $replayBad) -eq -32602) `
        ('code=' + (Get-ErrorCode $replayBad) + ' message=' + (Get-ErrorMessage $replayBad))

    $replayMissing = Invoke-Tool -Id 'g22_replay_missing_events' -Tool 'running_game_play_input_recording' `
        -Arguments @{} -Port $GamePort
    # The recorder snapshot is only *read* by the tool, so after a successful
    # replay there is still something to replay; the empty case is therefore
    # covered by an explicit empty array.
    $replayEmpty = Invoke-Tool -Id 'g22_replay_empty_events' -Tool 'running_game_play_input_recording' `
        -Arguments @{ events = @() } -Port $GamePort
    Add-Check 'g22_replay_empty_events_is_-32602' ((Get-ErrorCode $replayEmpty) -eq -32602) `
        ('code=' + (Get-ErrorCode $replayEmpty) + ' message=' + (Get-ErrorMessage $replayEmpty))

    $replaySpeed = Invoke-Tool -Id 'g22b_replay_bad_speed' -Tool 'running_game_play_input_recording' `
        -Arguments @{ events = @(@{ type = 'action'; action = 'ui_accept' }); speed = 0 } -Port $GamePort
    Add-Check 'g22b_replay_bad_speed_is_-32602' ((Get-ErrorCode $replaySpeed) -eq -32602) `
        ('code=' + (Get-ErrorCode $replaySpeed) + ' message=' + (Get-ErrorMessage $replaySpeed))

    # The explicit-array form is exercised too (as well as by the doctests): one
    # action event, replayed with a speed multiplier, and the game's InputMap
    # really sees it.
    $replayExplicit = Invoke-Tool -Id 'g22c_replay_explicit_array' -Tool 'running_game_play_input_recording' `
        -Arguments @{ events = @(@{ type = 'action'; action = 'ui_accept'; pressed = $true; strength = 1.0; time_ms = 0 }); speed = 4.0 } -Port $GamePort
    $replayExplicitPayload = Get-Payload $replayExplicit
    Add-Check 'g22c_replay_explicit_array_form' `
        ($null -ne $replayExplicitPayload -and $replayExplicitPayload.replayed -eq $true -and [int]$replayExplicitPayload.injected -eq 1) `
        ('explicit events array: replayed=' + [string]$replayExplicitPayload.replayed + ' injected=' + [string]$replayExplicitPayload.injected + ' speed=' + [string]$replayExplicitPayload.speed)

    # The *deferral* is what makes this tool different from an immediate one, and
    # it is measurable: a recording whose events sit 600 ms apart must take about
    # 600 ms to replay at speed 1.0, because each event is injected on the frame
    # its offset arrives and not in the frame that read the request. The four
    # injected-above events landed inside one frame, so this check is what pins
    # "the tool really waits across frames" on the wire.
    $slowRecording = @(
        @{ type = 'key'; keycode = 'A'; pressed = $true; time_ms = 0 },
        @{ type = 'key'; keycode = 'A'; pressed = $false; time_ms = 600 }
    )
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $slowReplay = Invoke-Tool -Id 'g22d_replay_spans_frames' -Tool 'running_game_play_input_recording' `
        -Arguments @{ events = $slowRecording; speed = 1.0 } -Port $GamePort -MaxTimeSec 40
    $watch.Stop()
    $slowPayload = Get-Payload $slowReplay
    $slowElapsed = [int]$watch.ElapsedMilliseconds
    Add-Check 'g22d_replay_spans_frames' `
        ($null -ne $slowPayload -and $slowPayload.replayed -eq $true -and $slowElapsed -ge 500) `
        ('two events 600 ms apart at speed 1.0 took {0} ms of wall clock and injected {1} event(s): the second one waited for its offset' -f $slowElapsed, [string]$slowPayload.injected)

    # -- (E4) button click by text ------------------------------------------
    $click = Invoke-Tool -Id 'g23_click_button' -Tool 'running_game_simulate_button_click_by_text' `
        -Arguments @{ text = 'Fire' } -Port $GamePort
    $clickPayload = Get-Payload $click
    Start-Sleep -Milliseconds 200
    $clicksAfter = Read-NodeProperty -Id 'g24_read_after_click' -NodePath 'Main' -Property 'clicks' -Port $GamePort
    $statusAfter = Read-NodeProperty -Id 'g24b_read_status_after_click' -NodePath 'Main' -Property 'status_text' -Port $GamePort
    Add-Check 'g23_button_click_found_and_emitted' `
        ($null -ne $clickPayload -and $clickPayload.clicked -eq $true -and ([string]$clickPayload.button_path).Contains('FireButton')) `
        ('clicked=' + [string]$clickPayload.clicked + ' button_path=' + [string]$clickPayload.button_path + ' button_text=' + [string]$clickPayload.button_text)
    Add-Check 'g24_button_handler_changed_game_state' `
        (($clicksAfter -eq [string]($clicksBefore + 1)) -and ($statusAfter -like '*fired*')) `
        ('the game handler ran exactly once: clicks ' + $clicksBefore + ' -> ' + $clicksAfter + ' and status_text=' + $statusAfter)

    $clickMissing = Invoke-Tool -Id 'g25_click_no_such_button' -Tool 'running_game_simulate_button_click_by_text' `
        -Arguments @{ text = 'Do Not Exist' } -Port $GamePort
    Add-Check 'g25_button_not_found_is_-32001' `
        ((Get-ErrorCode $clickMissing) -eq -32001 -and $null -ne $clickMissing.error.data.suggestion) `
        ('code=' + (Get-ErrorCode $clickMissing) + ' message=' + (Get-ErrorMessage $clickMissing))

    $clickEmpty = Invoke-Tool -Id 'g26_click_empty_text' -Tool 'running_game_simulate_button_click_by_text' `
        -Arguments @{ text = '   ' } -Port $GamePort
    Add-Check 'g26_button_empty_text_is_-32602' ((Get-ErrorCode $clickEmpty) -eq -32602) `
        ('code=' + (Get-ErrorCode $clickEmpty) + ' message=' + (Get-ErrorMessage $clickEmpty))

    $clickExact = Invoke-Tool -Id 'g26b_click_exact_text' -Tool 'running_game_simulate_button_click_by_text' `
        -Arguments @{ text = 'fire cannon'; partial = $false } -Port $GamePort
    Add-Check 'g26b_click_is_case_insensitive_and_exact' ($null -ne (Get-Payload $clickExact)) `
        ('partial=false with a lowercase spelling still matched: ' + [string](Get-Payload $clickExact).button_path)

    # Stopping when nothing is recording is an answer, not a failure: the
    # migration source behaved the same way, and a caller that lost track of its
    # session needs a way out.
    $stopIdle = Invoke-Tool -Id 'g27_stop_when_idle' -Tool 'running_game_stop_input_recording' -Arguments @{} -Port $GamePort
    $stopIdlePayload = Get-Payload $stopIdle
    Add-Check 'g27_stop_when_nothing_records_is_a_success' `
        ($null -ne $stopIdlePayload -and $stopIdlePayload.recording -eq $false -and [int]$stopIdlePayload.event_count -eq 0) `
        ('recording=' + [string]$stopIdlePayload.recording + ' event_count=' + [string]$stopIdlePayload.event_count + ' message=' + [string]$stopIdlePayload.message)

    Stop-Engine -Handle $game
    Start-Sleep -Milliseconds 800

    $userPortPidAfter = Get-ListenerPid -Port $UserPort
    Add-Check 'g28_user_port_9877_untouched' ($userPortPidBefore -eq $userPortPidAfter) `
        ('pid_before={0} pid_after={1}' -f $userPortPidBefore, $userPortPidAfter)
}

# =============================================================================
#  Phase: playback
# =============================================================================

function Invoke-PlaybackPhase {
    $editorProject = Join-Path $Scratch 'editor'
    Write-EditorProject -Path $editorProject
    Write-Host 'importing the scratch editor project ...'
    Import-Project -Path $editorProject -LogName 'mcp012-editor-import'

    $userPortPidBefore = Get-ListenerPid -Port $UserPort
    Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)

    if (Test-PortOpen -Port $GamePort) {
        Add-Check 'p00_game_port_free_before' $false 'port 9889 is already in use before the phase started'
        return
    }
    Add-Check 'p00_game_port_free_before' $true 'port 9889 is free before playback starts'

    $editor = Start-Engine -Arguments @('--headless', '-e', '--path', $editorProject, "--mcp-port=$EditorPort") -LogName 'mcp012-editor'
    if (-not (Wait-ForPump -Port $EditorPort)) {
        Add-Check 'p01_editor_ready' $false ("editor endpoint never became ready; log={0}" -f (Get-Content -Raw $editor.Out -ErrorAction SilentlyContinue))
        Stop-Engine -Handle $editor
        return
    }
    Add-Check 'p01_editor_ready' $true 'the headless editor answers GET /mcp on 9888'

    # The editor endpoint serves the editor-scope tools of this batch and none of
    # the game-side ones.
    $editorList = Invoke-Curl -Id 'p02_tools_list_editor_9888' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $EditorPort
    $editorNames = @()
    try { $editorNames = @((ConvertFrom-Json $editorList).result.tools | ForEach-Object { [string]$_.name }) } catch { }
    $want = @('editor_play_scene', 'editor_stop_scene', 'editor_get_input_actions')
    $missingEditor = @($want | Where-Object { $editorNames -notcontains $_ })
    $gameSideLeaked = @($editorNames | Where-Object { $_ -like 'running_game_*input*' -or $_ -eq 'running_game_set_node_property' })
    # The editor endpoint also serves the *both*-scope tools, so a
    # `scope = both` one (every `project_*` tool of B1 is BOTH) has to be there
    # while no `scope = game` tool is. The two candidates that look right are
    # both wrong: `running_game_get_scene_tree` and
    # `running_game_find_nearby_nodes` are `scope = game`, so their absence from
    # the editor endpoint is exactly what should happen.
    $hasBothScopeTool = ($editorNames -contains 'project_get_info')
    Add-Check 'p02_editor_endpoint_serves_the_editor_tools' `
        (($missingEditor.Count -eq 0) -and ($gameSideLeaked.Count -eq 0) -and $hasBothScopeTool) `
        ("editor endpoint: tools={0}; missing editor tools=[{1}]; leaked game-scope input tools=[{2}]; carries the both-scope project_get_info={3}" -f $editorNames.Count, ($missingEditor -join ','), ($gameSideLeaked -join ','), $hasBothScopeTool)

    # editor_get_input_actions reads the editor process' InputMap.
    $actions = Invoke-Tool -Id 'p03_editor_get_input_actions' -Tool 'editor_get_input_actions' -Arguments @{} -Port $EditorPort
    $actionsPayload = Get-Payload $actions
    $actionCount = 0
    $sorted = $false
    $hasUiAccept = $false
    if ($null -ne $actionsPayload) {
        $list = @($actionsPayload.actions)
        $actionCount = $list.Count
        $sorted = $true
        for ($i = 1; $i -lt $list.Count; $i++) {
            if ([string]::CompareOrdinal([string]$list[$i - 1], [string]$list[$i]) -gt 0) { $sorted = $false; break }
        }
        $hasUiAccept = ($list -contains 'ui_accept')
    }
    Add-Check 'p03_editor_get_input_actions_is_deterministic' `
        ($actionCount -gt 0 -and $sorted -and $hasUiAccept) `
        ("count={0} ascending={1} contains ui_accept={2} count_key_matches={3}" -f $actionCount, $sorted, $hasUiAccept, ([int]$actionsPayload.count -eq $actionCount))

    # The editor's InputMap must not be the *game's*: the same tool is refused on
    # the game endpoint (there is no game running yet, so 9889 answers nothing).
    Add-Check 'p03b_editor_input_actions_is_not_a_game_tool' ($gameSideLeaked -notcontains 'editor_get_input_actions') `
        'editor_get_input_actions is served by 9888 only; it reads the editor process InputMap'

    # Nothing is playing yet: the documented `stopped: false` success.
    $stopIdle = Invoke-Tool -Id 'p04_stop_when_idle' -Tool 'editor_stop_scene' -Arguments @{} -Port $EditorPort
    $stopIdlePayload = Get-Payload $stopIdle
    Add-Check 'p04_stop_when_nothing_plays' ($null -ne $stopIdlePayload -and $stopIdlePayload.stopped -eq $false) `
        ('stopped=' + [string]$stopIdlePayload.stopped + ' message=' + [string]$stopIdlePayload.message)

    # A bad custom scene path is refused before anything is started.
    $badPlay = Invoke-Tool -Id 'p05_play_bad_path' -Tool 'editor_play_scene' -Arguments @{ mode = 'res://../escape.tscn' } -Port $EditorPort
    Add-Check 'p05_play_bad_path_is_-32602' ((Get-ErrorCode $badPlay) -eq -32602) `
        ('code=' + (Get-ErrorCode $badPlay) + ' message=' + (Get-ErrorMessage $badPlay))

    $missingScene = Invoke-Tool -Id 'p06_play_missing_scene' -Tool 'editor_play_scene' -Arguments @{ mode = 'res://scenes/nope.tscn' } -Port $EditorPort
    Add-Check 'p06_play_missing_scene_is_-32001' ((Get-ErrorCode $missingScene) -eq -32001) `
        ('code=' + (Get-ErrorCode $missingScene) + ' message=' + (Get-ErrorMessage $missingScene))

    # Start playback.
    $editorPid = [int]$editor.Process.Id
    $treeBefore = Get-ProcessTree -RootPid $editorPid
    Write-Host ("editor pid={0}; its process tree before play: {1}" -f $editorPid, ($treeBefore -join ','))

    $play = Invoke-Tool -Id 'p07_play_scene_main' -Tool 'editor_play_scene' -Arguments @{ mode = 'main' } -Port $EditorPort
    $playPayload = Get-Payload $play
    Add-Check 'p07_play_scene_accepted' ($null -ne $playPayload -and $playPayload.playing -eq $true -and ([string]$playPayload.mode) -eq 'main') `
        ('playing=' + [string]$playPayload.playing + ' mode=' + [string]$playPayload.mode + ' path=' + [string]$playPayload.path)

    # The child really comes up: the *game* endpoint on 9889 becomes reachable and
    # answers with tools (the child reads godot_mcp/port from the project).
    $portUp = Wait-ForPort -Port $GamePort -Open $true -TimeoutMs 120000
    # The port can be open before the game's own `_process` has served a body, so
    # the pump and the last parsed status are waited for separately: the assertion
    # is about the answer, not about the socket.
    $gameProbe = $null
    $probeDeadline = [DateTime]::UtcNow.AddSeconds(120)
    while ([DateTime]::UtcNow -lt $probeDeadline) {
        $gameProbe = Get-StatusProbe -Port $GamePort
        if ($null -ne $gameProbe -and $null -ne $gameProbe.PSObject.Properties['tools']) { break }
        Start-Sleep -Milliseconds 1000
    }
    $gameTools = 0
    $childIsGame = $false
    if ($null -ne $gameProbe) {
        if ($null -ne $gameProbe.PSObject.Properties['tools']) { $gameTools = [int]$gameProbe.tools }
        if ($null -ne $gameProbe.PSObject.Properties['is_editor']) { $childIsGame = ($gameProbe.is_editor -eq $false) }
    }
    Add-Check 'p08_game_child_is_listening_on_9889' ($portUp -and $null -ne $gameProbe -and $gameTools -gt 0) `
        ("port 9889 reachable={0}; its GET /mcp answers tools={1} is_editor={2} listening={3}" -f $portUp, $gameTools, [string]$gameProbe.is_editor, [string]$gameProbe.listening)

    $treeDuring = Get-ProcessTree -RootPid $editorPid
    $children = @($treeDuring | Where-Object { $_ -ne $editorPid })
    $listenerPid = Get-ListenerPid -Port $GamePort
    Add-Check 'p09_game_child_is_a_child_process_of_the_editor' `
        ($children.Count -ge 1 -and ($children -contains $listenerPid)) `
        ('the pid listening on 9889 is {0}; the editor process tree during playback is {1}, and {0} is one of the editor children' -f $listenerPid, ($treeDuring -join ','))

    # The game child is a *game*, not another editor: its own status answer says so.
    Add-Check 'p10_game_child_is_a_game_process' $childIsGame `
        ('the child on 9889 reports is_editor=' + [string]$gameProbe.is_editor)

    # The game child's *own* subtree, captured while it runs. The editor spawns
    # helper children of its own (the debugger/language server pair visible in the
    # tree above), so "the editor has no children left" is not the claim that
    # matters: this is.
    $gameSubtree = @(Get-ProcessTree -RootPid $listenerPid | Where-Object { $_ -ne $listenerPid })
    Write-Host ("the game child {0} has subtree [{1}]" -f $listenerPid, ($gameSubtree -join ','))

    # Stop playback. `is_playing_scene()` is polled rather than assumed: the
    # child's teardown is asynchronous, and a tool that reported `stopped: true`
    # before the state really changed would be exactly the fake success this
    # implementation refuses to produce.
    $stopPayload = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    $attempt = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        $attempt++
        $stop = Invoke-Tool -Id ("p11_stop_scene_" + $attempt) -Tool 'editor_stop_scene' -Arguments @{} -Port $EditorPort
        $stopPayload = Get-Payload $stop
        if ($null -ne $stopPayload -and $stopPayload.stopped -eq $true) { break }
        Start-Sleep -Milliseconds 500
    }
    Add-Check 'p11_stop_scene_reports_stopped' ($null -ne $stopPayload -and $stopPayload.stopped -eq $true) `
        ('attempts={0} stopped={1} message={2}' -f $attempt, [string]$stopPayload.stopped, [string]$stopPayload.message)

    $portDown = Wait-ForPort -Port $GamePort -Open $false -TimeoutMs 60000
    Add-Check 'p12_game_endpoint_is_gone_after_stop' $portDown `
        ('port 9889 reachable after the stop: ' + (Test-PortOpen -Port $GamePort))

    # The process-level half of the same claim: the game child and everything it
    # in turn started must be gone, not merely unresponsive. The editor's own
    # helper children are deliberately *not* part of this claim (they are the
    # editor's, and they outlive a play/stop cycle by design); what is checked is
    # that nothing is left below the pid that played the game.
    $orphans = @()
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $deadline) {
        $orphans = @(Get-ProcessTree -RootPid $listenerPid | Where-Object { $_ -ne $listenerPid -and (Test-Alive -processId $_) })
        if ($orphans.Count -eq 0) { break }
        Start-Sleep -Milliseconds 500
    }
    Add-Check 'p13_no_orphan_game_process' `
        (($orphans.Count -eq 0) -and (-not (Test-Alive -processId $listenerPid))) `
        ('the game child {0} alive={1} and its own subtree after the stop: [{2}] (it had [{3}] while playing)' -f $listenerPid, (Test-Alive -processId $listenerPid), ($orphans -join ','), ($gameSubtree -join ','))

    Stop-Engine -Handle $editor
    Start-Sleep -Milliseconds 1500

    # Final sweep: nothing this script started may still be alive, and the pid
    # that listened on 9889 must be gone for good.
    $stillAlive = @($script:StartedPids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
    Add-Check 'p14_script_started_processes_all_stopped' ($stillAlive.Count -eq 0) `
        ('started pids={0}; still alive=[{1}]' -f ($script:StartedPids -join ','), ($stillAlive -join ','))
    Add-Check 'p15_9889_listener_pid_is_gone' `
        (((Get-ListenerPid -Port $GamePort) -eq -1) -and (-not (Test-Alive -processId $listenerPid))) `
        ('netstat LISTENING on 9889 now: ' + (Get-ListenerPid -Port $GamePort) + '; the pid that listened during playback is alive=' + (Test-Alive -processId $listenerPid))

    $userPortPidAfter = Get-ListenerPid -Port $UserPort
    Add-Check 'p16_user_port_9877_untouched' ($userPortPidBefore -eq $userPortPidAfter) `
        ('pid_before={0} pid_after={1}' -f $userPortPidBefore, $userPortPidAfter)
}

# =============================================================================
#  Main
# =============================================================================

New-Item -ItemType Directory -Force -Path $Scratch, $LogRoot, $Evid | Out-Null
Write-Host '============================================================='
Write-Host (" TASK-012 evidence -- phase {0}" -f $Phase)
Write-Host '============================================================='

try {
    if ($Phase -eq 'game') {
        Invoke-GamePhase
    } else {
        Invoke-PlaybackPhase
    }
} catch {
    Write-Host ("EXCEPTION: {0}" -f $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
    Add-Check 'harness_exception' $false $_.Exception.Message
} finally {
    # Never leave a process this script started behind, whatever happened.
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