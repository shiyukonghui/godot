# =============================================================================
#  mcp040_racing_regression.ps1 -- the TASK-039 racing project as a real
#  downstream, replayed after the TASK-040 D-2 fix.
#
#  Part A (the required regression): the racing project's own scene is opened,
#  `HUD/StartButton.pressed -> Main.OnStartPressed` and
#  `Checkpoints/CP1.body_entered -> LapTimer.OnCheckpointBodyEntered` are made
#  **with the tools**, the scene is saved, the editor is restarted, and the
#  connection is read back with the tools and from the `.tscn` on disk.
#
#  Part B (the counterfactual "would the car have started timing?"): a GDScript
#  scene with a `Timer.timeout -> Flag.mark` connection made the same way is
#  played *after* the restart, and `Flag.fired` is read through the running game
#  endpoint. That is what "the connection is really live at runtime after a
#  reload" means, on an engine build that can load the script (this local build
#  has `module_mono_enabled=no`, so the racing project's C# scripts cannot load -
#  which is exactly why the racing project is exercised as a *copy*).
#
#  Nothing under %TEMP%\mcp-racing-test is modified: the project is copied to
#  %TEMP%\mcp040-racing-<Label>\proj first, and the copy's scene sha256 is
#  checked against the RACING-FINDINGS anchor before anything happens.
#
#  Port discipline: 9877 is only observed; 9888 is the editor; the game child
#  port is chosen by `editor_play_scene` (9889 is held by the leftover TASK-039
#  racing game and is never touched).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp040_racing_regression.ps1 -Label fix
# =============================================================================

param(
    [int]$EditorPort = 9888,
    [int]$GamePort = 9889,
    [string]$Label = 'fix'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$SrcProject = Join-Path $env:TEMP 'mcp-racing-test'
$Root = Join-Path $env:TEMP ('mcp040-racing-' + $Label)
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877
$RacingSceneSha = '5892209c13782d417d8ef32f794bf94b7aaebcde00f40b1e75345ea8a49b7c3c'
$utf8 = [Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Note { param([string]$Text) Write-Host ("NOTE   {0}" -f $Text) }

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

function Invoke-Raw {
    param([string]$Id, [string]$Body, [int]$Port_)
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-McpUtf8NoBom -Path $bodyFile -Text $Body
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl '-s' '--max-time' '120' '-o' $respFile '-H' 'Content-Type: application/json' '--data-binary' ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] port={1} bytes={2} sha256={3}" -f $Id, $Port_, $bytes.Length, $sha)
    Write-Host ("       {0}" -f $text)
    return @{ id = $Id; text = $text; sha256 = $sha; file = $respFile; bytes = $bytes.Length }
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 0)
    if ($Port_ -eq 0) { $Port_ = $EditorPort }
    return Invoke-Raw -Id $Id -Body (New-CallBody -Tool $Tool -Arguments $Arguments) -Port_ $Port_
}

function Get-Envelope {
    param($Response)
    try { return ConvertFrom-Json ([string]$Response.text) } catch { return $null }
}

function Get-PayloadText {
    param($Response)
    try {
        $envelope = Get-Envelope $Response
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
    $envelope = Get-Envelope $Response
    if ($null -eq $envelope -or $null -eq $envelope.error) { return 0 }
    return [int]$envelope.error.code
}

function Get-ErrorMessage {
    param($Response)
    $envelope = Get-Envelope $Response
    if ($null -eq $envelope -or $null -eq $envelope.error) { return '' }
    return [string]$envelope.error.message
}

function Get-PropertyValue {
    param($Object_, [string]$Name)
    if ($null -eq $Object_) { return $null }
    foreach ($p in $Object_.PSObject.Properties) { if ([string]$p.Name -ceq $Name) { return $p.Value } }
    return $null
}

function Get-NodePropertyValue {
    param($Payload, [string]$Name)
    if ($null -eq $Payload) { return $null }
    return Get-PropertyValue (Get-PropertyValue $Payload 'properties') $Name
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    return Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
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

function Stop-Engine {
    param($Handle)
    if ($null -ne $Handle -and -not $Handle.HasExited) {
        Stop-Process -Id $Handle.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Get-SceneFacts {
    param([string]$ScenePath)
    $text = [IO.File]::ReadAllText($ScenePath, $utf8)
    $lines = $text -split "`n"
    $connections = @()
    $scripts = 0
    foreach ($line in $lines) {
        if ($line.TrimStart().StartsWith('[connection')) { $connections += $line.Trim() }
        if ($line.TrimStart().StartsWith('[ext_resource') -and $line.Contains('type="Script"')) { $scripts++ }
    }
    return @{
        text = $text
        connection_count = $connections.Count
        connections = $connections
        script_resources = $scripts
        bytes = (Get-Item $ScenePath).Length
        sha256 = (Get-FileHash -Algorithm SHA256 -Path $ScenePath).Hash.ToLower()
    }
}

# =============================================================================
#  The racing project copy
# =============================================================================
Check 'racing_project_source_exists' (Test-Path (Join-Path $SrcProject 'scenes\main.tscn')) ("source: {0}" -f $SrcProject)
$srcScene = Join-Path $SrcProject 'scenes\main.tscn'
$srcSha = (Get-FileHash -Algorithm SHA256 -Path $srcScene).Hash.ToLower()
Check 'racing_scene_matches_the_findings_anchor' ($srcSha -ceq $RacingSceneSha) `
    ("scenes/main.tscn sha256={0} (RACING-FINDINGS anchor {1})" -f $srcSha, $RacingSceneSha)

Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null
Copy-Item -Recurse -Force $SrcProject $Proj
Remove-Item -Recurse -Force (Join-Path $Proj '.godot') -ErrorAction SilentlyContinue

$projFile = Join-Path $Proj 'project.godot'
$projText = [IO.File]::ReadAllText($projFile, $utf8)
# The trace file setting is not needed here and would write into the original
# project's directory; drop it so the copy is self-contained.
$projText = $projText -replace '(?m)^trace_file=.*\r?\n', ''
Write-McpUtf8NoBom -Path $projFile -Text $projText

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Check 'racing_copy_imported' ($import.exit_code -eq 0) ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

$userPidBefore = Get-ListenerPid -Port_ $UserPort
$racingGamePid = Get-ListenerPid -Port_ $GamePort
Note ("port {0} owner before: {1}; port {2} owner (leftover racing game): {3}" -f $UserPort, $userPidBefore, $GamePort, $racingGamePid)
Check 'editor_port_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))

$racingScene = Join-Path $Proj 'scenes\main.tscn'
$timerScenePath = Join-Path $Proj 'scenes\timer.tscn'

$editorHandle = $null
$script:ownGamePort = 0
$script:racingPid = $racingGamePid
try {
    # =========================================================================
    #  Phase 0 - the project exactly as TASK-039 left it: a C# project.
    #
    #  This local build is `module_mono_enabled=no` (the mandated
    #  `scripts/build_local.cmd` passes it), so the C# scripts cannot load and
    #  the editor refuses the scene. That is recorded here as the reason the
    #  regression below runs on an adaptation, and it is *not* a module result:
    #  the tool's own answer names the cause ("the file exists but the editor
    #  could not open it as a scene; check its dependencies (missing scripts,
    #  resources or ext_resource paths)").
    # =========================================================================
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor0-csharp'
    Check 'P00_editor0_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} ready" -f $EditorPort)
    $openAsIs = Invoke-Tool -Id 'P00_open_racing_scene_as_is' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    $asIsCode = Get-ErrorCode $openAsIs
    Check 'P00_mono_less_build_cannot_open_the_csharp_scene' ($asIsCode -eq -32001) `
        ("editor_open_scene(main.tscn) code={0} message='{1}' (the local build has module_mono_enabled=no, so scripts/*.cs cannot load)" -f $asIsCode, (Get-ErrorMessage $openAsIs))
    Stop-Engine -Handle $editorHandle
    $editorHandle = $null
    Start-Sleep -Seconds 2

    # =========================================================================
    #  Phase 1 - the mono-less adaptation, documented.
    #
    #  The scene keeps its 28 real nodes, its node names, its properties and its
    #  `ext_resource` ids; only the six `Script` ext_resources are re-pointed
    #  from `res://scripts/X.cs` to equivalent `res://scripts/X.gd` stand-ins, so
    #  the scene the tools address is the racing scene and the connection
    #  targets are the ones TASK-039 used (`HUD/StartButton` -> `Main
    #  .OnStartPressed`, `Checkpoints/CP1.body_entered` ->
    #  `LapTimer.OnCheckpointBodyEntered`). The stand-ins deliberately do NOT
    #  self-connect the button: the real `Main.cs` does (`_Ready`), and leaving
    #  that compensation out is what makes the reload evidence unambiguous - a
    #  connection seen after the reload can only have come from the `.tscn`.
    # =========================================================================
    $stubs = @{}
    $stubs['Main'] = @'
extends Node2D

var ready_count := 0
var recorded_spawn := Vector2.ZERO

func _ready() -> void:
	ready_count += 1
	var car := get_node_or_null("Car")
	if car != null:
		recorded_spawn = car.position

func OnStartPressed() -> void:
	var lap_timer := get_node_or_null("LapTimer")
	if lap_timer != null:
		lap_timer.set("Timing", true)
'@
    $stubs['Car'] = @'
extends CharacterBody2D

signal SpeedChanged
signal BodyCrossed

@export var Acceleration := 620.0
@export var Drag := 240.0
@export var MaxSpeed := 320.0
@export var TurnRateDeg := 160.0
'@
    $stubs['Checkpoint'] = @'
extends Area2D

signal BodyCrossed
signal CheckpointPassed(index: int)

@export var IsFinish := false
@export var Index := 0
'@
    $stubs['ChaseCamera'] = @'
extends Camera2D

@export var TargetPath := NodePath()
'@
    $stubs['LapTimer'] = @'
extends Node

signal LapCompleted(lap: int, time: float)
signal CheckpointPassed(index: int, t: float)

var LapCount := 1
var CheckpointsHit := 0
var LastCheckpointIndex := -1
var CurrentLapTime := 0.0
var BestLap := -1.0
var TotalTime := 0.0
var Timing := false
var checkpoint_events := 0
var body_entered_probe_count := 0
var lap_completed_count := 0

func _process(delta: float) -> void:
	if Timing:
		CurrentLapTime += delta
		TotalTime += delta

func OnCheckpointBodyEntered(_body: Node2D) -> void:
	body_entered_probe_count += 1

func OnCheckpointIndex(_index: int) -> void:
	checkpoint_events += 1
'@
    $stubs['Hud'] = @'
extends CanvasLayer

func OnSpeedChanged(_speed: float) -> void:
	pass

func OnLapEvent(_a = null, _b = null) -> void:
	pass
'@
    foreach ($name in $stubs.Keys) {
        Write-McpUtf8NoBom -Path (Join-Path $Proj ("scripts\{0}.gd" -f $name)) -Text ($stubs[$name] + "`n")
    }

    $sceneText = [IO.File]::ReadAllText($racingScene, $utf8)
    $scriptPattern = '\[ext_resource type="Script"[^\]]*?path="res://scripts/([A-Za-z0-9_]+)\.cs" id="([^"]+)"\]'
    $sceneAdapted = [regex]::Replace($sceneText, $scriptPattern, '[ext_resource type="Script" path="res://scripts/$1.gd" id="$2"]')
    Write-McpUtf8NoBom -Path $racingScene -Text $sceneAdapted
    Check 'P01_the_only_change_is_the_six_script_ext_resources' ((([regex]::Matches($sceneAdapted, '\[ext_resource type="Script"')).Count -eq 6) -and (-not $sceneAdapted.Contains('.cs'))) `
        ("Script ext_resource count in the adapted scene = {0}; no .cs reference left" -f ([regex]::Matches($sceneAdapted, '\[ext_resource type="Script"')).Count)

    # Part B's GDScript scene: a `Timer` whose `timeout` is wired to a GDScript
    # method through the tools. `fired` is a script variable, so the running game's
    # property read answers it (PROPERTY_USAGE_SCRIPT_VARIABLE).
    $flagScript = @'
extends Node

var fired := 0

func mark() -> void:
	fired += 1
'@
    Write-McpUtf8NoBom -Path (Join-Path $Proj 'scripts\Flag.gd') -Text ($flagScript + "`n")

    $timerScene = @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/Flag.gd" id="1_flag"]

[node name="Main" type="Node2D"]

[node name="Timer" type="Timer" parent="."]
wait_time = 0.2
autostart = true

[node name="Flag" type="Node" parent="."]
script = ExtResource("1_flag")
'@
    Write-McpUtf8NoBom -Path $timerScenePath -Text ($timerScene + "`n")

    Remove-Item -Recurse -Force (Join-Path $Proj '.godot') -ErrorAction SilentlyContinue
    $import2 = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import-adapted'
    Check 'P02_adapted_copy_imported' ($import2.exit_code -eq 0) ("--import exit={0} after {1} attempt(s); log={2}" -f $import2.exit_code, $import2.attempts, $import2.log)

    $before = Get-SceneFacts -ScenePath $racingScene
    $scriptResourcesBefore = $before.script_resources
    Note ("racing main.tscn before: bytes={0} sha256={1} [connection] count={2} Script ext_resources={3}" -f $before.bytes, $before.sha256, $before.connection_count, $scriptResourcesBefore)

    # =========================================================================
    #  Part A - the tool calls TASK-039 really made, on the adapted scene
    # =========================================================================
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor1'
    Check 'editor1_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} ready" -f $EditorPort)

    $open = Invoke-Tool -Id 'R00_open_racing_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'R00_open_racing_scene_ok' ((Get-ErrorCode $open) -eq 0) ("code={0}" -f (Get-ErrorCode $open))

    # Keep the scene's own content in step with what the tools write (the editor
    # marks it dirty only on a real change, so saving is required to publish).
    $save0 = Invoke-Tool -Id 'R01_save_before' -Tool 'editor_save_scene' -Arguments @{}
    Check 'R01_save_before_ok' ((Get-ErrorCode $save0) -eq 0) ("code={0}" -f (Get-ErrorCode $save0))

    # ---- Part A: the two connections the developer made in TASK-039 --------
    $connectButton = Invoke-Tool -Id 'R02_connect_start_button' -Tool 'editor_connect_signal' -Arguments @{
        source_path = 'HUD/StartButton'; signal = 'pressed'; target_path = '.'; method = 'OnStartPressed'
    }
    $connectButtonPayload = Get-Payload $connectButton
    Check 'R02_connect_start_button_ok' ((Get-ErrorCode $connectButton) -eq 0) ("code={0} payload={1}" -f (Get-ErrorCode $connectButton), (Get-PayloadText $connectButton))
    Check 'R02_connect_reports_persisted_true' ((Get-PropertyValue $connectButtonPayload 'persisted') -eq $true) `
        ("payload={0}" -f (Get-PayloadText $connectButton))

    $connectBody = Invoke-Tool -Id 'R03_connect_checkpoint_body' -Tool 'editor_connect_signal' -Arguments @{
        source_path = 'Checkpoints/CP1'; signal = 'body_entered'; target_path = 'LapTimer'; method = 'OnCheckpointBodyEntered'
    }
    Check 'R03_connect_checkpoint_body_ok' ((Get-ErrorCode $connectBody) -eq 0) ("code={0} payload={1}" -f (Get-ErrorCode $connectBody), (Get-PayloadText $connectBody))

    $save1 = Invoke-Tool -Id 'R04_save_after_connect' -Tool 'editor_save_scene' -Arguments @{}
    Check 'R04_save_after_connect_ok' ((Get-ErrorCode $save1) -eq 0) ("code={0}" -f (Get-ErrorCode $save1))

    $afterSave = Get-SceneFacts -ScenePath $racingScene
    Note ("racing main.tscn after save: bytes={0} sha256={1} [connection] count={2} Script ext_resources={3}" -f $afterSave.bytes, $afterSave.sha256, $afterSave.connection_count, $afterSave.script_resources)
    foreach ($line in $afterSave.connections) { Note ("  {0}" -f $line) }
    Check 'A_connection_landed_in_the_racing_scene' (($afterSave.connection_count -ge 2) -and (($afterSave.connections -join ' ').Contains('OnStartPressed'))) `
        ("[connection] count={0} lines={1}" -f $afterSave.connection_count, ($afterSave.connections -join ' | '))
    Check 'A_checkpoint_connection_landed_too' (($afterSave.connections -join ' ').Contains('OnCheckpointBodyEntered')) `
        ("lines={0}" -f ($afterSave.connections -join ' | '))
    Check 'A_script_ext_resources_untouched_by_the_round_trip' ($afterSave.script_resources -eq $scriptResourcesBefore) `
        ("before={0} after={1} (the mono build loads the C# scripts; this local build does not)" -f $scriptResourcesBefore, $afterSave.script_resources)

    # ---- restart: the connection must come back from the file -------------
    Stop-Engine -Handle $editorHandle
    $editorHandle = $null
    Start-Sleep -Seconds 2
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor2'
    Check 'editor2_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor restarted on {0}" -f $EditorPort)

    $open2 = Invoke-Tool -Id 'R05_open_racing_scene_again' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'R05_open_again_ok' ((Get-ErrorCode $open2) -eq 0) ("code={0}" -f (Get-ErrorCode $open2))

    $listButton = Invoke-Tool -Id 'R06_list_start_button' -Tool 'editor_list_signal_connections' -Arguments @{ node_path = 'HUD/StartButton'; signal_name = 'pressed' }
    $listButtonText = Get-PayloadText $listButton
    Check 'A_start_button_connection_survives_the_reload' ($listButtonText.Contains('OnStartPressed')) `
        ("editor_list_signal_connections = {0}" -f $listButtonText)

    $listBody = Invoke-Tool -Id 'R07_list_checkpoint_body' -Tool 'editor_list_signal_connections' -Arguments @{ node_path = 'Checkpoints/CP1'; signal_name = 'body_entered' }
    $listBodyText = Get-PayloadText $listBody
    Check 'A_checkpoint_connection_survives_the_reload' ($listBodyText.Contains('OnCheckpointBodyEntered')) `
        ("editor_list_signal_connections = {0}" -f $listBodyText)

    $analyze = Invoke-Tool -Id 'R08_analyze_signal_flow' -Tool 'editor_analyze_signal_flow' -Arguments @{}
    $analyzeText = Get-PayloadText $analyze
    Check 'A_analyze_signal_flow_sees_the_reloaded_connections' ($analyzeText.Contains('OnStartPressed')) `
        ("editor_analyze_signal_flow = {0}" -f $analyzeText)

    $readFile = Invoke-Tool -Id 'R09_read_scene_file' -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://scenes/main.tscn' }
    $readFilePayload = Get-Payload $readFile
    # The payload is `{"content": <file text>, "path", "size"}`, so the *content*
    # member is the file itself (the envelope's outer escaping is gone here).
    $readFileContent = [string](Get-PropertyValue $readFilePayload 'content')
    $onDiskLine = '[connection signal="pressed" from="HUD/StartButton" to="." method="OnStartPressed"]'
    Check 'A_scene_file_on_disk_names_the_connection' ($readFileContent.Contains($onDiskLine)) `
        ("project_read_scene_file_content returned size={0} and its content contains the exact connection line: {1}" -f (Get-PropertyValue $readFilePayload 'size'), $readFileContent.Contains($onDiskLine))

    # ---- Part B: the connection really fires at runtime after a reload ----
    $openTimer = Invoke-Tool -Id 'R10_open_timer_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/timer.tscn' }
    Check 'R10_open_timer_scene_ok' ((Get-ErrorCode $openTimer) -eq 0) ("code={0}" -f (Get-ErrorCode $openTimer))

    $connectTimer = Invoke-Tool -Id 'R11_connect_timer' -Tool 'editor_connect_signal' -Arguments @{
        source_path = 'Timer'; signal = 'timeout'; target_path = 'Flag'; method = 'mark'
    }
    Check 'R11_connect_timer_ok' ((Get-ErrorCode $connectTimer) -eq 0) ("code={0} payload={1}" -f (Get-ErrorCode $connectTimer), (Get-PayloadText $connectTimer))
    $saveTimer = Invoke-Tool -Id 'R12_save_timer_scene' -Tool 'editor_save_scene' -Arguments @{}
    Check 'R12_save_timer_scene_ok' ((Get-ErrorCode $saveTimer) -eq 0) ("code={0}" -f (Get-ErrorCode $saveTimer))
    $timerFacts = Get-SceneFacts -ScenePath $timerScenePath
    Note ("timer.tscn after save: bytes={0} sha256={1} [connection] count={2}" -f $timerFacts.bytes, $timerFacts.sha256, $timerFacts.connection_count)
    foreach ($line in $timerFacts.connections) { Note ("  {0}" -f $line) }
    Check 'B_timer_connection_landed_on_disk' ($timerFacts.connection_count -ge 1) ("[connection] count={0}" -f $timerFacts.connection_count)

    # A fresh editor, so the connection can only come from the file.
    Stop-Engine -Handle $editorHandle
    $editorHandle = $null
    Start-Sleep -Seconds 2
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor3'
    Check 'editor3_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor restarted a second time on {0}" -f $EditorPort)
    $openTimer2 = Invoke-Tool -Id 'R13_open_timer_again' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/timer.tscn' }
    Check 'R13_open_timer_again_ok' ((Get-ErrorCode $openTimer2) -eq 0) ("code={0}" -f (Get-ErrorCode $openTimer2))

    $play = Invoke-Tool -Id 'R14_play_current_scene' -Tool 'editor_play_scene' -Arguments @{ mode = 'current' }
    $playPayload = Get-Payload $play
    $reportedPort = Get-PropertyValue $playPayload 'mcp_port'
    $gamePortActual = $GamePort
    if ($null -ne $reportedPort) { $gamePortActual = [int]$reportedPort }
    $script:ownGamePort = $gamePortActual
    Check 'R14_play_current_scene_ok' (((Get-ErrorCode $play) -eq 0) -and ($null -ne $reportedPort)) ("code={0} payload={1}" -f (Get-ErrorCode $play), (Get-PayloadText $play))
    Check 'B_game_endpoint_ready' (Wait-ForPump -Port_ $gamePortActual) ("game on {0} ready" -f $gamePortActual)

    Start-Sleep -Seconds 3
    $readFlag = Invoke-Tool -Id 'R15_read_flag_fired' -Port_ $gamePortActual -Tool 'running_game_get_node_properties' -Arguments @{
        node_path = '/root/Main/Flag'; properties = @('fired')
    }
    $fired = Get-NodePropertyValue (Get-Payload $readFlag) 'fired'
    Check 'B_persistent_connection_really_fired_in_the_running_game' ((Get-ErrorCode $readFlag) -eq 0 -and $null -ne $fired -and ([double]$fired) -ge 1) `
        ("running_game_get_node_properties(/root/Main/Flag.fired) = {0} (payload {1})" -f $fired, (Get-PayloadText $readFlag))

    $stop = Invoke-Tool -Id 'R16_stop_scene' -Tool 'editor_stop_scene' -Arguments @{}
    Note ("editor_stop_scene code={0}" -f (Get-ErrorCode $stop))
    Start-Sleep -Seconds 2
    Check 'racing_game_on_9889_untouched' ((Get-ListenerPid -Port_ $GamePort) -eq $racingGamePid) `
        ("port {0} owner after: {1} (before {2})" -f $GamePort, (Get-ListenerPid -Port_ $GamePort), $racingGamePid)
}
finally {
    Stop-Engine -Handle $editorHandle
    if ($script:ownGamePort -gt 0 -and $script:ownGamePort -ne $UserPort) {
        $ownPid = Get-ListenerPid -Port_ $script:ownGamePort
        if ($ownPid -gt 0 -and $ownPid -ne $script:racingPid) {
            Stop-Process -Id $ownPid -Force -ErrorAction SilentlyContinue
        }
    }
}

$userPidAfter = Get-ListenerPid -Port_ $UserPort
Check 'port_9877_owner_unchanged' ($userPidAfter -eq $userPidBefore) `
    ("port {0} owner before={1} after={2}" -f $UserPort, $userPidBefore, $userPidAfter)

$checksPath = Join-Path $Root 'checks.json'
$checkLines = New-Object System.Collections.Generic.List[string]
foreach ($c in $script:Checks) {
    $id = ([string]$c.id).Replace('\', '\\').Replace('"', '\"')
    $evidenceText = ([string]$c.evidence).Replace('\', '\\').Replace('"', '\"').Replace("`r", ' ').Replace("`n", ' ')
    $boolText = if ($c.pass) { 'true' } else { 'false' }
    $checkLines.Add('{"id":"' + $id + '","pass":' + $boolText + ',"evidence":"' + $evidenceText + '"}')
}
Write-McpUtf8NoBom -Path $checksPath -Text (($checkLines -join "`n") + "`n")

$failed = @($script:Checks | Where-Object { -not $_.pass })
Write-Host ''
Write-Host ("========== racing regression label={0} : {1} checks, {2} failed ==========" -f $Label, $script:Checks.Count, $failed.Count)
foreach ($f in $failed) { Write-Host ("FAIL {0}: {1}" -f $f.id, $f.evidence) }
Write-Host ("checks: {0}" -f $checksPath)
Write-Host ("evidence: {0}" -f $Ev)
if ($failed.Count -gt 0) { exit 1 }
exit 0
