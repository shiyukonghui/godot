# =============================================================================
#  mcp014_m3_evidence.ps1 -- TASK-014 (M3) gate 2 evidence
#
#  Two phases, because the two halves of TASK-014 run on two different engine
#  binaries:
#
#    -Phase gate2   the *non-mono* build (`module_mono_enabled=no`, the one that
#                   carries the doctests). It measures the four repaired items of
#                   TASK-014 section 1, on the wire:
#                     * D-1  `running_game_set_node_property` on a property the
#                            node does not have -> -32001 + data.suggestion, with
#                            a control read proving nothing was written, next to a
#                            real write that still works;
#                     * D-2  `editor_capture_screenshot` under `--headless` ->
#                            -32000 + data.suggestion (and a -32602 control that
#                            shows the argument half is unchanged);
#                     * D-3  the live `running_game_play_input_recording` entry
#                            (description + `inputSchema.required`) is *verbatim*
#                            the contract's, and the behaviour the new text
#                            documents - omitting `events` replays this process'
#                            most recent recording - really happens;
#                     * R-3  with `mcp_server/pending_timeout_ms=0` configured,
#                            a deferred tool that declares its own 600 s deadline
#                            is still capped at the framework's 30 s and answers
#                            -32000 with `data.timeout_ms = 30000`.
#
#    -Phase m3      the *mono* build. It measures the M3 assertions: the module
#                   still serves the same two tool sets (49 editor / 40 game),
#                   a real C# project builds with `dotnet build` and runs, the C#
#                   script's own state is read back through the MCP tools (the
#                   cross-language visibility TASK-014 section 3 is about), and a
#                   property written from the C++ module is visible to the C#
#                   code.
#
#  Discipline (PLAYBOOK section 3 and section 7.1), unchanged from TASK-012/013:
#    * every response body is written to its own file with `curl.exe -s -o`, and
#      a sha256 is printed from the bytes on disk; nothing goes through
#      `Out-File` or a pipeline;
#    * every request body is built with `ConvertTo-Json` and written as a file,
#      never interpolated into a command line;
#    * ports 9888 (editor) and 9889 (game) only. Port 9877 belongs to the user's
#      Godot 4.7.1-mono editor: it is never touched, only observed, and its
#      listener pid is asserted unchanged at the end of every phase;
#    * only engines this script started itself are stopped, and every pid it
#      started is swept in `finally`.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp014_m3_evidence.ps1 -Phase gate2
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp014_m3_evidence.ps1 -Phase m3 `
#        -Engine <repo>\bin\godot.windows.editor.x86_64.console.exe
# =============================================================================

param(
    [ValidateSet('gate2', 'm3')]
    [string]$Phase = 'gate2',
    # The engine to drive. Defaults to the in-tree editor binary; the `m3` phase
    # is meant to be pointed at the *mono* build.
    [string]$Engine = '',
    # `m3` only: skip `dotnet build` and reuse the project's existing assembly.
    [switch]$SkipDotnetBuild
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($Engine)) {
    $Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
}
$Engine = (Resolve-Path $Engine).Path
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877
$Scratch = Join-Path $env:TEMP 'mcp014-scratch'
$LogRoot = Join-Path $env:TEMP 'mcp014-logs'
$Evid = Join-Path $env:TEMP 'mcp014-evidence'

# TASK-028 D-1: the shared scratch-project writer + `--import` runner.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

$script:Results = New-Object System.Collections.Generic.List[object]
$script:StartedPids = New-Object System.Collections.Generic.List[int]

function Add-Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Results.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1} :: {2}" -f $tag, $Id, $Evidence)
}

# TASK-028 D-1: `Write-Utf8NoBom` / `Import-McpProject` now come from the shared
# guard (`scripts\mcp_import_guard.ps1`, dot-sourced next to the other variables
# of this script). The local copy this file used to carry is gone: a second
# definition is how the two would drift apart.
#
# TASK-048 section 2: TASK-028 renamed the helper to `Write-McpUtf8NoBom` but left
# one call site on the old name, so `Invoke-Curl` threw
# `Write-Utf8NoBom : The term ... is not recognized` on its very first request and
# `-Phase m3` aborted right after `m06` (recorded as MILESTONES-CLOSURE section
# 3.3). This batch fixes that one call site; nothing else about the phase changed.

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

# Sweeps every engine this script started, including any child the engine
# spawned itself (a game launched by `editor_play_scene`), by parent pid.
function Stop-AllStarted {
    foreach ($startedPid in $script:StartedPids) {
        Get-CimInstance Win32_Process -Filter ("ParentProcessId=$startedPid") -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-Process -Id $startedPid -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 800
}

# -----------------------------------------------------------------------------
# JSON building: every value is escaped by `ConvertTo-Json`, never by string
# interpolation.
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
    param([string]$Id, [string]$Json, [int]$Port, [int]$MaxTimeSec = 30, [string]$Method = 'tools/call')
    $bodyFile = Join-Path $Evid ("{0}.request.json" -f $Id)
    $respFile = Join-Path $Evid ("{0}.response.json" -f $Id)
    Write-McpUtf8NoBom -Path $bodyFile -Text $Json
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
    Write-Host ("[{0}] curl port={1} ({2}) exit={3} bytes={4} sha256={5}" -f $Id, $Port, $Method, $curlExit, $bytes.Length, $sha)
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

function Invoke-ToolsList {
    param([string]$Id, [int]$Port)
    $text = Invoke-Curl -Id $Id -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $Port -Method 'tools/list'
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

function Get-ErrorSuggestion {
    param($Envelope)
    if ($null -eq $Envelope -or $null -eq $Envelope.error -or $null -eq $Envelope.error.data) { return '' }
    return [string]$Envelope.error.data.suggestion
}

function Get-StatusProbe {
    param([int]$Port)
    $file = Join-Path $Evid ("status_{0}.response.json" -f $Port)
    if (Test-Path $file) { Remove-Item -Force $file }
    & $Curl -s --max-time 5 -o $file ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    if (-not (Test-Path $file)) { return $null }
    $bytes = [IO.File]::ReadAllBytes($file)
    if ($bytes.Length -eq 0) { return $null }
    try { return [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json } catch { return $null }
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
    # TASK-028 D-1: exit code checked, bounded retry, diagnosis on failure.
    # The old body ignored the exit code of `--import`.
    $result = Import-McpProject -Engine $Engine -Path $Path -LogDirectory $LogRoot -Name $LogName
    $script:LastImportAttempts = $result.attempts
    Write-Host ("import {0}: exit 0 on attempt {1}" -f $Path, $result.attempts)
    return $result.attempts
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
# Scratch projects
# -----------------------------------------------------------------------------

$GameScript = @'
extends Node2D

# The game's own state. Everything the evidence reads below is produced by this
# file (or, in the `m3` phase, by the C# script), never by a number a tool
# reported about itself.
var key_events := 0
var state_text := "gdscript-ready"
var label: Label


func _ready() -> void:
	label = get_node_or_null("Label")
	_tick()


func _process(_delta: float) -> void:
	_tick()


func _input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventKey:
		key_events += 1


func _tick() -> void:
	if label != null:
		label.text = "state=%s keys=%d" % [state_text, key_events]
'@

$GameScene = @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://instrumented.gd" id="1_auth"]

[node name="Main" type="Node2D"]
script = ExtResource("1_auth")

[node name="Label" type="Label" parent="."]
offset_left = 20.0
offset_top = 20.0
offset_right = 620.0
offset_bottom = 60.0
text = "idle"
'@

function Ensure-Project {
    param([string]$Path, [string]$Name, [bool]$WithMainScene, [string]$Script, [string]$Scene)
    Remove-Item -Recurse -Force $Path -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $lines = @('config_version=5', '', '[application]', ('config/name="' + $Name + '"'))
    if ($WithMainScene) { $lines += 'run/main_scene="res://scenes/main.tscn"' }
    $lines += 'config/features=PackedStringArray("4.8")'
    # TASK-014: the game process opts in through the project setting (the same
    # channel `check_contract_subset.ps1` uses), and the deferred ceiling is
    # configured to 0 on purpose - the R-3 check below measures that a
    # non-positive value cannot switch the fallback off.
    $lines += @('', '[godot_mcp]', 'enabled_in_game=true', '', '[mcp_server]', 'pending_timeout_ms=0')
    $lines += @('', '[rendering]', 'renderer/rendering_method="gl_compatibility"', 'renderer/rendering_method.mobile="gl_compatibility"')
    # TASK-028 D-1: no BOM anywhere (`Set-Content -Encoding UTF8` used to write one).
    Write-McpUtf8NoBom -Path (Join-Path $Path 'project.godot') -Text (($lines -join "`n") + "`n")
    if ($WithMainScene) {
        $sceneDir = Join-Path $Path 'scenes'
        New-Item -ItemType Directory -Force -Path $sceneDir | Out-Null
        Write-McpUtf8NoBom -Path (Join-Path $sceneDir 'main.tscn') -Text $Scene
        if ($Script -ne '') {
            Write-McpUtf8NoBom -Path (Join-Path $Path 'instrumented.gd') -Text $Script
        }
    }
}

# -----------------------------------------------------------------------------
# Phase gate2 -- the four repaired items, on the non-mono build
# -----------------------------------------------------------------------------

function Invoke-Gate2 {
    $editorProject = Join-Path $Scratch 'gate2-editor-proj'
    $gameProject = Join-Path $Scratch 'gate2-game-proj'
    Ensure-Project -Path $editorProject -Name 'mcp014-gate2-editor' -WithMainScene $true -Script $GameScript -Scene $GameScene
    Ensure-Project -Path $gameProject -Name 'mcp014-gate2-game' -WithMainScene $true -Script $GameScript -Scene $GameScene

    $userPidBefore = Get-ListenerPid -Port $UserPort
    Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPidBefore)

    # PLAYBOOK section 3: the gates have to be bound to a known build. The
    # version string is recorded in the evidence itself, so a later reader can
    # check it against the commit the report names - a gate result whose binary
    # is not named is not worth much.
    & $Engine --version *> (Join-Path $LogRoot 'gate2-engine-version.txt')
    $engineVersion = (Get-Content (Join-Path $LogRoot 'gate2-engine-version.txt') -Encoding UTF8 | Select-Object -First 1)
    Add-Check 'g00_engine_version_recorded' ($engineVersion -match 'custom_build') `
        ("engine --version = '{0}'" -f $engineVersion)

    Write-Host 'importing scratch projects ...'
    Import-Project -Path $editorProject -LogName 'gate2-editor-import'
    Import-Project -Path $gameProject -LogName 'gate2-game-import'

    $editorHandle = $null
    $gameHandle = $null
    try {
        $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $editorProject, "--mcp-port=$EditorPort") -LogName 'gate2-editor'
        $gameHandle = Start-Engine -Arguments @('--headless', '--path', $gameProject, "--mcp-port=$GamePort") -LogName 'gate2-game'

        $editorUp = Wait-ForPump -Port $EditorPort
        $gameUp = Wait-ForPump -Port $GamePort
        Add-Check 'g01_both_endpoints_up' ($editorUp -and $gameUp) `
            ("editor pump on {0} = {1}; game pump on {2} = {3}" -f $EditorPort, $editorUp, $GamePort, $gameUp)

        # -- D-2: the headless editor's screenshot tool ------------------------
        $shot = Invoke-Tool -Id 'g02_editor_capture_screenshot_headless' -Tool 'editor_capture_screenshot' -Arguments @{} -Port $EditorPort
        $shotCode = Get-ErrorCode $shot
        $shotSuggestion = Get-ErrorSuggestion $shot
        Add-Check 'g02_D2_headless_screenshot_is_32000_with_a_suggestion' `
            ($shotCode -eq -32000 -and $shotSuggestion.Length -gt 0) `
            ("editor_capture_screenshot under --headless -> code={0} (expected -32000), data.suggestion='{1}'" -f $shotCode, $shotSuggestion)

        # The argument half of the same tool is unchanged: a mistyped destination
        # is still -32602, and it is still reported *before* the capability guard.
        $shotBad = Invoke-Tool -Id 'g03_editor_capture_screenshot_bad_path' -Tool 'editor_capture_screenshot' `
            -Arguments @{ save_path = 'C:/outside/mcp014.png' } -Port $EditorPort
        Add-Check 'g03_D2_argument_half_unchanged' ((Get-ErrorCode $shotBad) -eq -32602) `
            ("a path outside res://+user:// is still -32602: code={0}, message='{1}'" -f (Get-ErrorCode $shotBad), (Get-ErrorMessage $shotBad))

        # -- gate 1's union, measured live in this run -------------------------
        $editorList = Invoke-ToolsList -Id 'g04_editor_tools_list' -Port $EditorPort
        $gameList = Invoke-ToolsList -Id 'g05_game_tools_list' -Port $GamePort
        $editorCount = if ($null -ne $editorList) { @($editorList.result.tools).Count } else { -1 }
        $gameCount = if ($null -ne $gameList) { @($gameList.result.tools).Count } else { -1 }
        Add-Check 'g06_tool_counts_49_and_40' ($editorCount -eq 49 -and $gameCount -eq 40) `
            ("tools/list = {0} on {1} (editor, expected 49) and {2} on {3} (game, expected 40)" -f $editorCount, $EditorPort, $gameCount, $GamePort)

        # -- D-3: the live entry vs the contract, key by key -------------------
        $contractPath = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'
        $contract = Get-Content $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $contractEntry = @($contract.result.tools) | Where-Object { $_.name -ceq 'running_game_play_input_recording' }
        $liveEntry = @($gameList.result.tools) | Where-Object { $_.name -ceq 'running_game_play_input_recording' }
        $descSame = ([string]$liveEntry[0].description -ceq [string]$contractEntry[0].description)
        $requiredLive = @($liveEntry[0].inputSchema.required)
        $requiredEmpty = ($requiredLive.Count -eq 0)
        $eventsStillDeclared = ($null -ne $liveEntry[0].inputSchema.properties.events)
        Add-Check 'g07_D3_live_schema_matches_the_contract' `
            ($descSame -and $requiredEmpty -and $eventsStillDeclared -and (@($liveEntry).Count -eq 1)) `
            ("description verbatim={0}; required={1} (empty={2}); properties.events still declared={3}" -f $descSame, (ConvertTo-CompactJson $requiredLive), $requiredEmpty, $eventsStillDeclared)

        # -- D-1: the write chain on the game endpoint -------------------------
        $tree = Invoke-Tool -Id 'g08_game_get_scene_tree' -Tool 'running_game_get_scene_tree' -Arguments @{ max_depth = 3 } -Port $GamePort
        $treePayload = Get-Payload $tree
        Add-Check 'g08_game_scene_tree_readable' ($null -ne $treePayload) `
            ("running_game_get_scene_tree answered a payload (root visible): {0}" -f (ConvertTo-CompactJson $treePayload).Substring(0, [Math]::Min(160, (ConvertTo-CompactJson $treePayload).Length)))

        $posBefore = Read-NodeProperty -Id 'g09_before_position' -NodePath 'Main' -Property 'position' -Port $GamePort
        $writeOk = Invoke-Tool -Id 'g10_set_position' -Tool 'running_game_set_node_property' `
            -Arguments @{ node_path = 'Main'; property = 'position'; value = @{ x = 321; y = 123 } } -Port $GamePort
        $writePayload = Get-Payload $writeOk
        $posAfter = Read-NodeProperty -Id 'g11_after_position' -NodePath 'Main' -Property 'position' -Port $GamePort
        # `running_game_execute_gdscript` compiles the body into a generated
        # method, so a multi-statement body needs real newlines. They come from a
        # single-quoted here-string: literal, no escaping, and the inner double
        # quotes of the GDScript reach the wire unchanged (a PowerShell
        # double-quoted string would need `\" to be spelled `"` and is a trap -
        # an earlier revision of this script did not parse because of it).
        #
        # The generated script `extends RefCounted` and its instance is a
        # RefCounted, *not* a Node: `get_node()` does not exist there (the first
        # run of this script measured exactly that - `Parameter 'code' does not
        # compile: Parse error`). The tree is reached through the `Engine`
        # singleton, which is the documented way for this tool.
        $readPosition = @'
var tree := Engine.get_main_loop() as SceneTree
var main := tree.current_scene
return "%.1f,%.1f" % [main.position.x, main.position.y]
'@
        $gdRead = Invoke-Tool -Id 'g12_gdscript_reads_position' -Tool 'running_game_execute_gdscript' `
            -Arguments @{ code = $readPosition } -Port $GamePort
        $gdPayload = Get-Payload $gdRead
        $gdValue = if ($null -ne $gdPayload) { [string]$gdPayload.result } else { '' }
        Add-Check 'g13_D1_real_write_still_works_and_two_tools_agree' `
            ($null -ne $writePayload -and $posAfter -match '321' -and $posAfter -match '123' -and $gdValue -eq '321.0,123.0') `
            ("position {0} -> write answer new_value={1}; independent read-back via running_game_get_node_properties = {2}; via running_game_execute_gdscript = '{3}'" -f $posBefore, (ConvertTo-CompactJson $writePayload.new_value), $posAfter, $gdValue)

        $bad = Invoke-Tool -Id 'g14_set_unknown_property' -Tool 'running_game_set_node_property' `
            -Arguments @{ node_path = 'Main'; property = 'mcp014_no_such_property'; value = 1 } -Port $GamePort
        $badCode = Get-ErrorCode $bad
        $badSuggestion = Get-ErrorSuggestion $bad
        $badMessage = Get-ErrorMessage $bad
        $noFakeSuccess = ($null -eq $bad.result)
        Add-Check 'g15_D1_unknown_property_is_32001' `
            ($badCode -eq -32001 -and $badSuggestion.Length -gt 0 -and $noFakeSuccess -and $badMessage.Contains('mcp014_no_such_property')) `
            ("code={0} (expected -32001), message='{1}', data.suggestion='{2}', no fake success result={3}" -f $badCode, $badMessage, $badSuggestion, $noFakeSuccess)

        $controlCode = @'
var tree := Engine.get_main_loop() as SceneTree
return tree.current_scene.get("mcp014_no_such_property") == null
'@
        $control = Invoke-Tool -Id 'g16_control_unknown_property_is_absent' -Tool 'running_game_execute_gdscript' `
            -Arguments @{ code = $controlCode } -Port $GamePort
        $controlPayload = Get-Payload $control
        $controlValue = if ($null -ne $controlPayload) { [string]$controlPayload.result } else { '' }
        Add-Check 'g17_control_nothing_was_written' ($controlValue -eq 'true') `
            ("the refused write changed nothing: the property is still absent (get(...) == null -> {0})" -f $controlValue)

        # -- D-3 behaviour: omitting `events` really replays the recording -----
        $recStart = Invoke-Tool -Id 'g18_start_recording' -Tool 'running_game_create_input_recording' -Arguments @{} -Port $GamePort
        Add-Check 'g18_recording_started' ($null -ne (Get-Payload $recStart)) `
            ("running_game_create_input_recording -> {0}" -f (ConvertTo-CompactJson (Get-Payload $recStart)))

        $inject = @'
var e := InputEventKey.new()
e.keycode = KEY_A
e.physical_keycode = KEY_A
e.pressed = true
Input.parse_input_event(e)
return "injected"
'@
        $injected = Invoke-Tool -Id 'g19_inject_inside_game' -Tool 'running_game_execute_gdscript' -Arguments @{ code = $inject } -Port $GamePort
        Start-Sleep -Milliseconds 700
        $recStop = Invoke-Tool -Id 'g20_stop_recording' -Tool 'running_game_stop_input_recording' -Arguments @{} -Port $GamePort
        $recStopPayload = Get-Payload $recStop
        $recCount = if ($null -ne $recStopPayload) { @($recStopPayload.events).Count } else { -1 }
        Add-Check 'g20_recording_collected_events' ($recCount -ge 1) `
            ("running_game_stop_input_recording -> events={0} (a recording exists for the no-`events` replay below)" -f $recCount)

        $playNoEvents = Invoke-Tool -Id 'g21_play_without_events' -Tool 'running_game_play_input_recording' -Arguments @{ speed = 8.0 } -Port $GamePort -MaxTimeSec 60
        $playPayload = Get-Payload $playNoEvents
        $playCode = Get-ErrorCode $playNoEvents
        Add-Check 'g22_D3_omitting_events_replays_the_recording' ($playCode -eq 0 -and $null -ne $playPayload) `
            ("`events` omitted: code={0} (0 = success), payload={1} - the behaviour the corrected contract now documents" -f $playCode, (ConvertTo-CompactJson $playPayload))

        # -- R-3: a non-positive configured ceiling cannot switch the net off --
        $gameLog = Join-Path $LogRoot 'gate2-game.out.log'
        $clampLine = ''
        if (Test-Path $gameLog) {
            $clampLines = @(Get-Content $gameLog -Encoding UTF8 | Where-Object { $_ -match 'pending_timeout_ms=' })
            if ($clampLines.Count -gt 0) { $clampLine = [string]$clampLines[0] }
        }
        Add-Check 'g23_R3_startup_log_reports_the_clamped_ceiling' ($clampLine -match 'pending_timeout_ms=30000') `
            ("configured `mcp_server/pending_timeout_ms=0` -> startup log: '{0}'" -f $clampLine)

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $ceiling = Invoke-Tool -Id 'g24_R3_deferred_ceiling' -Tool 'running_game_find_node_when_available' `
            -Arguments @{ node_path = 'Mcp014NeverAppears'; poll_frames = 5; timeout = 600 } -Port $GamePort -MaxTimeSec 90
        $watch.Stop()
        $ceilingCode = Get-ErrorCode $ceiling
        $ceilingTimeout = if ($null -ne $ceiling -and $null -ne $ceiling.error.data) { [int]$ceiling.error.data.timeout_ms } else { -1 }
        Add-Check 'g25_R3_ceiling_is_30s_not_600s' `
            ($ceilingCode -eq -32000 -and $ceilingTimeout -eq 30000) `
            ("the tool asked for 600 s; the configured ceiling was 0; the answer came after {0:N1} s with code={1} and data.timeout_ms={2} (expected 30000)" -f $watch.Elapsed.TotalSeconds, $ceilingCode, $ceilingTimeout)

        # -- hygiene -----------------------------------------------------------
        $userPidAfter = Get-ListenerPid -Port $UserPort
        Add-Check 'g26_guard_user_port_9877' ($userPidBefore -eq $userPidAfter -and $userPidBefore -gt 0) `
            ("pid_before={0} pid_after={1} (the user's Godot 4.7.1-mono editor was never touched)" -f $userPidBefore, $userPidAfter)
    } finally {
        Stop-Engine -Handle $gameHandle
        Stop-Engine -Handle $editorHandle
        Stop-AllStarted
    }

    foreach ($port in @($EditorPort, $GamePort)) {
        $open = Test-PortOpen -Port $port
        Add-Check ("g27_port_{0}_released" -f $port) (-not $open) ("listening after teardown = {0}" -f $open)
    }
}

# -----------------------------------------------------------------------------
# Phase m3 -- the mono build, a real C# project, and cross-language visibility
# -----------------------------------------------------------------------------

$CsharpScript = @'
using Godot;

// TASK-014 section 3: the smallest C# project that proves the language axis.
//
// Everything the evidence reads through the MCP tools is produced *here*: the
// tick counter only moves if `_Process` really ran, `CsharpReport()` is a C#
// method the C++ module's `running_game_execute_gdscript` calls through GDScript,
// and `CsharpState` is a property the C++ module writes.
//
// `[Export]` on the two fields is load-bearing and was measured: a *public
// field* of a C# script is an ordinary C# field, not a Godot property, so it
// never appears in `Object::get_property_list()` and `running_game_set_node_property`
// cannot reach it (the first run of this script answered `-32602` for an empty
// property name because the discovery found nothing). Only exported members are
// part of the object's property surface, which is exactly the surface every
// game-side node tool of this module works on.
public partial class Main : Node2D
{
    [Export] public int CsharpTicks = 0;
    [Export] public string CsharpState = "csharp-ready";

    private Label _label;

    public override void _Ready()
    {
        _label = GetNodeOrNull<Label>("Label");
        GD.Print("[MCP014-CS] Main._Ready ran; state=" + CsharpState);
        Tick();
    }

    public override void _Process(double delta)
    {
        CsharpTicks++;
        if (CsharpTicks % 120 == 0)
        {
            GD.Print("[MCP014-CS] ticks=" + CsharpTicks);
        }
        Tick();
    }

    // Called from the MCP module's `running_game_execute_gdscript`.
    public string CsharpReport()
    {
        return "csharp: ticks=" + CsharpTicks + " state=" + CsharpState;
    }

    private void Tick()
    {
        if (_label != null)
        {
            _label.Text = "cs_ticks=" + CsharpTicks + " state=" + CsharpState;
        }
    }
}
'@

$CsharpScene = @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://Main.cs" id="1_main"]

[node name="Main" type="Node2D"]
script = ExtResource("1_main")

[node name="Label" type="Label" parent="."]
offset_left = 20.0
offset_top = 20.0
offset_right = 720.0
offset_bottom = 60.0
text = "csharp-not-ready"
'@

function Get-GodotSdkVersion {
    $propsPath = Join-Path $RepoRoot 'modules\mono\SdkPackageVersions.props'
    if (-not (Test-Path $propsPath)) { return '' }
    $xml = [xml](Get-Content $propsPath -Raw -Encoding UTF8)
    $node = $xml.Project.PropertyGroup.PackageVersion_Godot_NET_Sdk
    if ($null -eq $node) { return [string]$xml.Project.PropertyGroup.PackageVersion_Godot_NET_Sdk }
    return [string]$node
}

function Ensure-CsharpProject {
    param([string]$Path)
    Remove-Item -Recurse -Force $Path -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Path 'scenes') | Out-Null

    $lines = @(
        'config_version=5', '', '[application]',
        'config/name="mcp014-csharp-proj"',
        'run/main_scene="res://scenes/main.tscn"',
        'config/features=PackedStringArray("4.8")',
        '', '[dotnet]', 'project/assembly_name="Mcp014Csharp"',
        '', '[godot_mcp]', 'enabled_in_game=true',
        '', '[mcp_server]', 'pending_timeout_ms=0',
        '', '[rendering]', 'renderer/rendering_method="gl_compatibility"',
        'renderer/rendering_method.mobile="gl_compatibility"'
    )
    Write-McpUtf8NoBom -Path (Join-Path $Path 'project.godot') -Text (($lines -join "`n") + "`n")
    Write-McpUtf8NoBom -Path (Join-Path $Path 'scenes\main.tscn') -Text $CsharpScene
    Write-McpUtf8NoBom -Path (Join-Path $Path 'Main.cs') -Text $CsharpScript

    # The only NuGet source is the one the Godot build itself produced
    # (`modules/mono/Directory.Build.targets` copies every packed nupkg into
    # `bin/GodotSharp/Tools/nupkgs/`). `<clear/>` keeps restore honest: if a
    # package is missing from that folder the build fails loudly instead of
    # silently reaching the network.
    $nupkgs = Join-Path $RepoRoot 'bin\GodotSharp\Tools\nupkgs'
    $nuget = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="godot-local" value="$nupkgs" />
  </packageSources>
</configuration>
"@
    Write-McpUtf8NoBom -Path (Join-Path $Path 'NuGet.config') -Text $nuget
}

function Invoke-M3 {
    $project = Join-Path $Scratch 'm3-csharp-proj'
    $editorProject = Join-Path $Scratch 'm3-editor-proj'
    Ensure-Project -Path $editorProject -Name 'mcp014-m3-editor' -WithMainScene $true -Script $GameScript -Scene $GameScene
    Ensure-CsharpProject -Path $project

    $sdkVersion = Get-GodotSdkVersion
    Add-Check 'm01_sdk_version_available' ($sdkVersion -ne '') `
        ("the Godot .NET SDK version of this build (modules/mono/SdkPackageVersions.props) = '{0}'" -f $sdkVersion)
    if ($sdkVersion -eq '') { return }

    $csproj = @"
<Project Sdk="Godot.NET.Sdk/$sdkVersion">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <EnableDynamicLoading>true</EnableDynamicLoading>
    <RootNamespace>Mcp014Csharp</RootNamespace>
    <AssemblyName>Mcp014Csharp</AssemblyName>
    <Nullable>disable</Nullable>
    <WarningLevel>4</WarningLevel>
  </PropertyGroup>
</Project>
"@
    Set-Content -Path (Join-Path $project 'Mcp014Csharp.csproj') -Value $csproj -Encoding UTF8

    $nupkgs = Join-Path $RepoRoot 'bin\GodotSharp\Tools\nupkgs'
    $nupkgList = @()
    if (Test-Path $nupkgs) { $nupkgList = @(Get-ChildItem $nupkgs -Filter *.nupkg | ForEach-Object { $_.Name }) }
    Add-Check 'm02_local_nupkg_source_populated' ($nupkgList.Count -ge 3) `
        ("the Godot build produced {0} local nupkgs in bin\GodotSharp\Tools\nupkgs: {1}" -f $nupkgList.Count, ($nupkgList -join ', '))

    $userPidBefore = Get-ListenerPid -Port $UserPort
    Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPidBefore)

    Import-Project -Path $editorProject -LogName 'm3-editor-import'
    Import-Project -Path $project -LogName 'm3-csharp-import'

    # -- the M3 gate's first half: `dotnet build` ------------------------------
    if (-not $SkipDotnetBuild) {
        $buildLog = Join-Path $LogRoot 'm3-dotnet-build.log'
        Push-Location $project
        try {
            & dotnet build -c Debug *> $buildLog
            $dotnetExit = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        Write-Host ("dotnet build exit={0}; full output follows" -f $dotnetExit)
        Get-Content $buildLog -Encoding UTF8 | ForEach-Object { Write-Host ("    dotnet| {0}" -f $_) }
        Add-Check 'm03_dotnet_build_succeeded' ($dotnetExit -eq 0) `
            ("dotnet build -c Debug exit code = {0} (log: {1})" -f $dotnetExit, $buildLog)
    } else {
        Write-Host 'dotnet build skipped (-SkipDotnetBuild)'
    }

    $assembly = Join-Path $project '.godot\mono\temp\bin\Debug\Mcp014Csharp.dll'
    $assemblyExists = Test-Path $assembly
    $assemblyBytes = if ($assemblyExists) { (Get-Item $assembly).Length } else { 0 }
    Add-Check 'm04_project_assembly_produced' $assemblyExists `
        ("the project assembly the engine loads: {0} ({1} bytes)" -f $assembly, $assemblyBytes)

    & $Engine --version *> (Join-Path $LogRoot 'm3-engine-version.txt')
    $monoVersion = (Get-Content (Join-Path $LogRoot 'm3-engine-version.txt') -Encoding UTF8 | Select-Object -First 1)
    Add-Check 'm05_engine_is_the_mono_build' ($monoVersion -ne '') ("engine --version = '{0}'" -f $monoVersion)

    $editorHandle = $null
    $gameHandle = $null
    try {
        $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $editorProject, "--mcp-port=$EditorPort") -LogName 'm3-editor'
        $gameHandle = Start-Engine -Arguments @('--headless', '--path', $project, "--mcp-port=$GamePort") -LogName 'm3-csharp-game'

        $editorUp = Wait-ForPump -Port $EditorPort
        $gameUp = Wait-ForPump -Port $GamePort
        Add-Check 'm06_both_endpoints_up_under_mono' ($editorUp -and $gameUp) `
            ("mono build: editor pump on {0} = {1}; game pump on {2} = {3}" -f $EditorPort, $editorUp, $GamePort, $gameUp)

        $editorList = Invoke-ToolsList -Id 'm07_editor_tools_list' -Port $EditorPort
        $gameList = Invoke-ToolsList -Id 'm08_game_tools_list' -Port $GamePort
        $editorCount = if ($null -ne $editorList) { @($editorList.result.tools).Count } else { -1 }
        $gameCount = if ($null -ne $gameList) { @($gameList.result.tools).Count } else { -1 }
        Add-Check 'm09_mono_tool_counts_49_and_40' ($editorCount -eq 49 -and $gameCount -eq 40) `
            ("under mono: tools/list = {0} on {1} (editor, expected 49) and {2} on {3} (game, expected 40)" -f $editorCount, $EditorPort, $gameCount, $GamePort)

        # -- the C# code really executed ---------------------------------------
        $gameLog = Join-Path $LogRoot 'm3-csharp-game.out.log'
        $readyLine = ''
        if (Test-Path $gameLog) {
            $readyLines = @(Get-Content $gameLog -Encoding UTF8 | Where-Object { $_ -match 'MCP014-CS' })
            if ($readyLines.Count -gt 0) { $readyLine = [string]$readyLines[0] }
        }
        Add-Check 'm10_csharp_ready_ran' ($readyLine -match 'MCP014-CS.*_Ready ran') `
            ("the C# script's own log line from _Ready: '{0}'" -f $readyLine)

        # -- the M3 gate's core: the C# script's state through the MCP tools ---
        $tree = Invoke-Tool -Id 'm11_game_get_scene_tree' -Tool 'running_game_get_scene_tree' -Arguments @{ max_depth = 3 } -Port $GamePort
        Add-Check 'm11_scene_tree_under_csharp_game' ($null -ne (Get-Payload $tree)) `
            ("running_game_get_scene_tree answered under the mono/C# game: {0}" -f (ConvertTo-CompactJson (Get-Payload $tree)).Substring(0, [Math]::Min(200, (ConvertTo-CompactJson (Get-Payload $tree)).Length)))

        # Discovery, not a hardcoded name: the Godot property name a C# member
        # gets is the engine's business, so the evidence asks the object.
        $discoverCode = @'
var names := []
var tree := Engine.get_main_loop() as SceneTree
for p in tree.current_scene.get_property_list():
    names.append(String(p.name))
return names
'@
        $discover = Invoke-Tool -Id 'm12_discover_csharp_properties' -Tool 'running_game_execute_gdscript' `
            -Arguments @{ code = $discoverCode } -Port $GamePort
        $namesPayload = Get-Payload $discover
        $names = @()
        if ($null -ne $namesPayload) { $names = @($namesPayload.result | ForEach-Object { [string]$_ }) }
        $tickName = ($names | Where-Object { ($_ -replace '_', '').ToLower() -eq 'csharpticks' } | Select-Object -First 1)
        $stateName = ($names | Where-Object { ($_ -replace '_', '').ToLower() -eq 'csharpstate' } | Select-Object -First 1)
        Add-Check 'm13_csharp_members_visible_in_the_property_list' ($null -ne $tickName -and $null -ne $stateName) `
            ("the C# script's own members appear in the Godot property list the C++ module reads: ticks='{0}', state='{1}' (of {2} properties)" -f $tickName, $stateName, $names.Count)

        # A C# method, called through the module's `running_game_execute_gdscript`.
        $reportCode = @'
var tree := Engine.get_main_loop() as SceneTree
return tree.current_scene.call("CsharpReport")
'@
        $report = Invoke-Tool -Id 'm14_call_csharp_method' -Tool 'running_game_execute_gdscript' `
            -Arguments @{ code = $reportCode } -Port $GamePort
        $reportPayload = Get-Payload $report
        $reportText = if ($null -ne $reportPayload) { [string]$reportPayload.result } else { '' }
        $reportTicks = -1
        if ($reportText -match 'ticks=(\d+)') { $reportTicks = [int]$Matches[1] }
        Add-Check 'm14_CsharpReport_reaches_the_mcp_wire' ($reportText -match '^csharp: ticks=\d+ state=csharp-ready$' -and $reportTicks -gt 0) `
            ("running_game_execute_gdscript -> C# CsharpReport() = '{0}' (ticks>0 proves _Process ran; the string was built in C#)" -f $reportText)

        # The same counter, read through the *property* tool (a second,
        # independent path: `running_game_get_node_properties` reads the C#
        # object's property from C++).
        $ticksViaProperty = if ($null -ne $tickName) { Read-NodeProperty -Id 'm15_read_csharp_ticks' -NodePath 'Main' -Property $tickName -Port $GamePort } else { $null }
        $ticksInt = -1
        if ($null -ne $ticksViaProperty -and $ticksViaProperty -match '(\d+)') { $ticksInt = [int]$Matches[1] }
        Start-Sleep -Milliseconds 900
        $ticksLater = if ($null -ne $tickName) { Read-NodeProperty -Id 'm16_read_csharp_ticks_again' -NodePath 'Main' -Property $tickName -Port $GamePort } else { $null }
        $ticksLaterInt = -1
        if ($null -ne $ticksLater -and $ticksLater -match '(\d+)') { $ticksLaterInt = [int]$Matches[1] }
        Add-Check 'm16_csharp_state_is_live_through_the_property_tool' ($ticksInt -ge 0 -and $ticksLaterInt -gt $ticksInt) `
            ("C# property '{0}' read by running_game_get_node_properties twice: {1} -> {2} (the C# code kept running between the two reads)" -f $tickName, $ticksInt, $ticksLaterInt)

        # -- the write half: C++ module -> C# object -> C# method --------------
        $write = Invoke-Tool -Id 'm17_write_csharp_property' -Tool 'running_game_set_node_property' `
            -Arguments @{ node_path = 'Main'; property = $stateName; value = 'written-from-mcp' } -Port $GamePort
        $writePayload = Get-Payload $write
        $after = Invoke-Tool -Id 'm18_call_csharp_method_after_write' -Tool 'running_game_execute_gdscript' `
            -Arguments @{ code = $reportCode } -Port $GamePort
        $afterPayload = Get-Payload $after
        $afterText = if ($null -ne $afterPayload) { [string]$afterPayload.result } else { '' }
        Add-Check 'm18_csharp_sees_the_value_written_by_the_cpp_module' ($afterText -match 'state=written-from-mcp') `
            ("after running_game_set_node_property('{0}' = 'written-from-mcp') (write answer {1}), the C# method reports '{2}'" -f $stateName, (ConvertTo-CompactJson $writePayload.new_value), $afterText)

        # -- mono must not have changed the two repaired items -----------------
        $shot = Invoke-Tool -Id 'm19_editor_capture_screenshot_headless_mono' -Tool 'editor_capture_screenshot' -Arguments @{} -Port $EditorPort
        Add-Check 'm19_D2_still_32000_under_mono' ((Get-ErrorCode $shot) -eq -32000 -and (Get-ErrorSuggestion $shot).Length -gt 0) `
            ("under mono, editor_capture_screenshot -> code={0}, suggestion='{1}'" -f (Get-ErrorCode $shot), (Get-ErrorSuggestion $shot))

        $bad = Invoke-Tool -Id 'm20_set_unknown_property_mono' -Tool 'running_game_set_node_property' `
            -Arguments @{ node_path = 'Main'; property = 'mcp014_no_such_property'; value = 1 } -Port $GamePort
        Add-Check 'm20_D1_still_32001_under_mono' ((Get-ErrorCode $bad) -eq -32001 -and (Get-ErrorSuggestion $bad).Length -gt 0) `
            ("under mono, an unknown property -> code={0}, suggestion='{1}'" -f (Get-ErrorCode $bad), (Get-ErrorSuggestion $bad))

        $clampLine = ''
        $gameLogPath = Join-Path $LogRoot 'm3-csharp-game.out.log'
        if (Test-Path $gameLogPath) {
            $clampLines = @(Get-Content $gameLogPath -Encoding UTF8 | Where-Object { $_ -match 'pending_timeout_ms=' })
            if ($clampLines.Count -gt 0) { $clampLine = [string]$clampLines[0] }
        }
        Add-Check 'm21_R3_startup_log_under_mono' ($clampLine -match 'pending_timeout_ms=30000') `
            ("configured 0 -> mono game startup log: '{0}'" -f $clampLine)

        $playEntry = @()
        if ($null -ne $gameList) { $playEntry = @(@($gameList.result.tools) | Where-Object { $_.name -ceq 'running_game_play_input_recording' }) }
        $playRequired = if ($playEntry.Count -eq 1) { ConvertTo-CompactJson @($playEntry[0].inputSchema.required) } else { '<entry missing>' }
        Add-Check 'm22_D3_live_schema_under_mono' ($playEntry.Count -eq 1 -and (@($playEntry[0].inputSchema.required)).Count -eq 0) `
            ("under mono, the live tools/list still carries the corrected schema: required={0}" -f $playRequired)

        $userPidAfter = Get-ListenerPid -Port $UserPort
        Add-Check 'm23_guard_user_port_9877' ($userPidBefore -eq $userPidAfter -and $userPidBefore -gt 0) `
            ("pid_before={0} pid_after={1} (the user's Godot 4.7.1-mono editor was never touched)" -f $userPidBefore, $userPidAfter)
    } finally {
        Stop-Engine -Handle $gameHandle
        Stop-Engine -Handle $editorHandle
        Stop-AllStarted
    }

    foreach ($port in @($EditorPort, $GamePort)) {
        $open = Test-PortOpen -Port $port
        Add-Check ("m24_port_{0}_released" -f $port) (-not $open) ("listening after teardown = {0}" -f $open)
    }
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

New-Item -ItemType Directory -Force -Path $Scratch, $LogRoot, $Evid | Out-Null

Write-Host '============================================================='
Write-Host (' TASK-014 evidence -- phase {0}' -f $Phase)
Write-Host '============================================================='
Write-Host ('engine : {0}' -f $Engine)
Write-Host ('scratch: {0}' -f $Scratch)
Write-Host ('logs   : {0}' -f $LogRoot)
Write-Host ('evidence: {0}' -f $Evid)
Write-Host ''

try {
    if ($Phase -eq 'gate2') { Invoke-Gate2 } else { Invoke-M3 }
} finally {
    Stop-AllStarted
}

Write-Host ''
Write-Host '========================== SUMMARY =========================='
$passed = 0
foreach ($r in $script:Results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    if ($r.pass) { $passed++ }
    Write-Host ("{0}  {1}" -f $tag, $r.id)
    Write-Host ("      {0}" -f $r.evidence)
}
Write-Host ('{0}/{1} checks passed' -f $passed, $script:Results.Count)
if ($passed -ne $script:Results.Count) { exit 1 }
exit 0
