# =============================================================================
#  mcp024a_e10_play_scene_evidence.ps1 -- live evidence for TASK-024a (E-10)
#
#  Proves, on the wire and against real processes, that `editor_play_scene`
#  injects `--mcp-port=<port>` into the game child it starts through
#  `EditorRunBar::play_*(..., p_play_args)`:
#
#    1. the *child's command line* really carries the argument (read from
#       Win32_Process, not inferred);
#    2. the game is immediately observable over MCP **from that port** - the
#       script connects to it and runs a game-side tool, so "start the game,
#       watch it" is a closed loop;
#    3. the port is the caller's `mcp_port` when given, and an automatically
#       probed free port otherwise (never the editor's own port);
#    4. an occupied port, or the editor's own port, is refused honestly - no
#       child is started and no success is reported;
#    5. all three `mode` values (`main` / `current` / a scene path) still work;
#    6. `editor_stop_scene` really kills the child (no orphan game process).
#
#  Discipline (PLAYBOOK sections 3 and 7): request bodies are built with
#  `ConvertTo-Json` and posted with `curl.exe --data-binary @file`; response
#  bodies are written by `curl.exe -s -o <file>` (never through a pipe or
#  `Out-File`), and every body gets a sha256. The user's editor on port 9877 is
#  never touched: only its listener pid is *read* (netstat) as a before/after
#  guard.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp024a_e10_play_scene_evidence.ps1
# =============================================================================

param(
    [int]$EditorPort = 9888,
    [int]$ExplicitGamePort = 19890,
    [int]$CurrentGamePort = 19892,
    [int]$CustomGamePort = 19893,
    [int]$HeldPort = 19891
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Root = Join-Path $env:TEMP 'task024a-e10'
$Ev = Join-Path $Root 'evidence'
$Project = Join-Path $Root 'proj'
$UserPort = 9877

# TASK-028 D-1: the shared scratch-project writer and `--import` runner.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $Project | Out-Null

$script:Checks = New-Object System.Collections.Generic.List[object]
$script:Log = New-Object System.Collections.Generic.List[string]
$script:EditorProcess = $null
$script:HeldListener = $null

function Note {
    param([string]$Text)
    $script:Log.Add($Text)
    Write-Host $Text
}

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
    $script:Log.Add(("[{0}] {1} :: {2}" -f $tag, $Id, $Evidence))
}

# -----------------------------------------------------------------------------
# HTTP against the MCP endpoint (hand-rolled HTTP/1.1 subset)
# -----------------------------------------------------------------------------

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

function New-ToolCallBody {
    param([string]$Tool, [hashtable]$Arguments)
    $obj = [ordered]@{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json $obj -Depth 12 -Compress)
}

function Invoke-Mcp {
    param([int]$Port, [string]$Body, [string]$Tag)
    $bodyPath = Join-Path $Ev ($Tag + '.request.json')
    $respPath = Join-Path $Ev ($Tag + '.response.json')
    Write-Utf8NoBom -Path $bodyPath -Text $Body
    & curl.exe -s -o $respPath --max-time 90 -H 'Content-Type: application/json' --data-binary "@$bodyPath" "http://127.0.0.1:$Port/mcp"
    $rc = $LASTEXITCODE
    $text = [IO.File]::ReadAllText($respPath)
    $json = $null
    try { $json = ConvertFrom-Json $text } catch { $json = $null }
    return [pscustomobject]@{
        rc = $rc; request = $bodyPath; response = $respPath
        sha256 = (Get-FileHash $respPath -Algorithm SHA256).Hash
        text = $text; json = $json
    }
}

function Get-StatusProbe {
    param([int]$Port)
    $respPath = Join-Path $Ev ('status.' + $Port + '.' + [Guid]::NewGuid().ToString('N').Substring(0, 6) + '.json')
    & curl.exe -s -o $respPath --max-time 10 "http://127.0.0.1:$Port/mcp"
    if ($LASTEXITCODE -ne 0) { return $null }
    $text = [IO.File]::ReadAllText($respPath)
    try { return ConvertFrom-Json $text } catch { return $null }
}

function Wait-ForPump {
    param([int]$Port, [int]$TimeoutSec = 240)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $previous = $null
    $consecutive = 0
    while ((Get-Date) -lt $deadline) {
        $probe = Get-StatusProbe -Port $Port
        if ($null -ne $probe) {
            $frames = [int]$probe.frame_count
            if ($null -ne $previous -and ($frames - $previous) -ge 20) { $consecutive++ } else { $consecutive = 0 }
            if ($consecutive -ge 2) { return $true }
            $previous = $frames
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

function Wait-ForPort {
    param([int]$Port, [int]$TimeoutSec = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $task = $client.ConnectAsync('127.0.0.1', $Port)
            if ($task.Wait(1000) -and $client.Connected) { $client.Close(); return $true }
        } catch { }
        $client.Close()
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Get-ListenerPid {
    param([int]$Port)
    $lines = & netstat -ano -p TCP 2>$null
    foreach ($line in $lines) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

function Get-ChildCmdline {
    param([int]$ProcessId)
    $p = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $ProcessId) -ErrorAction SilentlyContinue
    if ($null -eq $p) { return '' }
    return [string]$p.CommandLine
}

function Test-ProcessAlive {
    param([int]$ProcessId)
    return ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue))
}

# -----------------------------------------------------------------------------
# Scratch project: deliberately WITHOUT `godot_mcp/port`
#
# That absence is half the evidence: before E-10 the only way to give the child a
# port was to set that project setting. Here the port can only come from the
# injected command line argument.
# -----------------------------------------------------------------------------

function New-ScratchProject {
    New-Item -ItemType Directory -Force -Path (Join-Path $Project 'scenes') | Out-Null
    $projectGodot = @(
        'config_version=5'
        ''
        '[application]'
        'config/name="MCP E-10 evidence"'
        'config/features=PackedStringArray("4.8")'
        'run/main_scene="res://scenes/main.tscn"'
        ''
        '[rendering]'
        'renderer/rendering_method="gl_compatibility"'
        'renderer/rendering_method.mobile="gl_compatibility"'
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-Path $Project 'project.godot') -Text ($projectGodot + "`n")
    $main = @(
        '[gd_scene format=3]'
        ''
        '[node name="Main" type="Node2D"]'
        ''
        '[node name="Marker" type="Node2D" parent="."]'
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-Path $Project 'scenes\main.tscn') -Text ($main + "`n")
    $other = @(
        '[gd_scene format=3]'
        ''
        '[node name="Other" type="Node2D"]'
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-Path $Project 'scenes\other.tscn') -Text ($other + "`n")
}

function Start-Editor {
    $out = Join-Path $Root 'editor.out.log'
    $err = Join-Path $Root 'editor.err.log'
    $args = @('--headless', '-e', '--path', $Project, ("--mcp-port=" + $EditorPort))
    $script:EditorProcess = Start-Process -FilePath $Engine -ArgumentList $args -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    return $script:EditorProcess
}

# =============================================================================
#  Run
# =============================================================================

Note '============================================================='
Note ' TASK-024a E-10 live evidence -- editor_play_scene --mcp-port injection'
Note '============================================================='
Note ("engine      : {0}" -f $Engine)
Note ("version     : {0}" -f (& $Engine --version))
Note ("editor port : {0} (this script owns it)" -f $EditorPort)

$userPidBefore = Get-ListenerPid -Port $UserPort
Note ("user editor on {0} before run: pid={1} (read-only guard)" -f $UserPort, $userPidBefore)

New-ScratchProject
Note ("scratch project: {0} (no godot_mcp/port setting on purpose)" -f $Project)
# The import is a *one-shot* process, so its exit code is the thing that proves
# the project really imported (PLAYBOOK section 3: an unchecked `--import` can
# exit with 0xC0000005 and still leave the rest of the run looking green).
#
# It is run through `cmd /c` for two reasons: `Start-Process -PassThru` does not
# hand back a readable `ExitCode` for a redirected child in this PowerShell
# (measured: the property is empty in every form), and `cmd /c` preserves the
# child's exit code in `$LASTEXITCODE`. `--mcp-port=0` is passed so that an
# engine run that is not meant to serve MCP does not even try to bind the
# module's default editor port (9877), which belongs to the user's editor.
# It is run through the shared guard now (TASK-028 D-1): the guard keeps the
# checked exit code this comment is about, and adds the bounded retry plus a
# printed diagnosis, so a single transient `0xC0000005` no longer fails the whole
# evidence run. `--mcp-port=0` is passed so that an engine run that is not meant
# to serve MCP does not even try to bind the module's default editor port (9877),
# which belongs to the user's editor.
$import = Import-McpProject -Engine $Engine -Path $Project -LogDirectory $Root -Name 'import'
Check 'scratch_import_exit_code' ($import.exit_code -eq 0) `
    ("--import --mcp-port=0 exit code = {0} after {1} attempt(s) (log: {2})" -f $import.exit_code, $import.attempts, $import.log)

Start-Editor | Out-Null
Note ("editor pid  : {0}" -f $script:EditorProcess.Id)
Check 'editor_endpoint_ready' (Wait-ForPump -Port $EditorPort) ("editor on {0} answered GET /mcp twice with +20 frames" -f $EditorPort)

try {
    # -------------------------------------------------------------------------
    # 0. the contract the client sees
    # -------------------------------------------------------------------------
    $list = Invoke-Mcp -Port $EditorPort -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Tag 'tools_list.editor'
    $playSchema = $null
    foreach ($tool in @($list.json.result.tools)) {
        if ([string]$tool.name -eq 'editor_play_scene') { $playSchema = $tool.inputSchema }
    }
    $portProp = $null
    if ($null -ne $playSchema) { $portProp = $playSchema.properties.mcp_port }
    Check 'schema_advertises_mcp_port' ($null -ne $portProp -and [string]$portProp.type -eq 'integer') `
        ("editor_play_scene.inputSchema.properties.mcp_port = {0} (description='{1}')" -f (ConvertTo-Json $portProp -Compress), $portProp.description)

    # -------------------------------------------------------------------------
    # 1. E-10: an explicit mcp_port, the child's real command line, and a
    #    game-side tool called on that port
    # -------------------------------------------------------------------------
    Note ''
    Note '--- (1) explicit mcp_port -------------------------------------------'
    $play1 = Invoke-Mcp -Port $EditorPort -Tag 'play_scene.explicit.request' `
        -Body (New-ToolCallBody -Tool 'editor_play_scene' -Arguments @{ mode = 'main'; mcp_port = $ExplicitGamePort })
    $r1 = $play1.json.result.content[0].text | ConvertFrom-Json
    Note ("response: {0}" -f (ConvertTo-Json $r1 -Compress))
    Check 'explicit_response_fields' `
        ($r1.playing -eq $true -and [int]$r1.mcp_port -eq $ExplicitGamePort -and [string]$r1.mcp_port_source -eq 'argument' `
        -and [string]$r1.endpoint -eq ("http://127.0.0.1:{0}/mcp" -f $ExplicitGamePort) -and [int]$r1.pid -gt 0) `
        ("playing={0} mcp_port={1} mcp_port_source={2} endpoint={3} pid={4}" -f $r1.playing, $r1.mcp_port, $r1.mcp_port_source, $r1.endpoint, $r1.pid)

    $cmd1 = Get-ChildCmdline -ProcessId ([int]$r1.pid)
    Note ("child cmdline: {0}" -f $cmd1)
    Check 'child_cmdline_contains_mcp_port' ($cmd1 -match ("--mcp-port=" + $ExplicitGamePort)) `
        ("pid {0} command line contains --mcp-port={1}" -f $r1.pid, $ExplicitGamePort)
    Check 'child_cmdline_is_the_reported_pid' (Test-ProcessAlive -ProcessId ([int]$r1.pid)) `
        ("pid {0} from the tool response is a live process" -f $r1.pid)

    $up1 = Wait-ForPort -Port $ExplicitGamePort
    Check 'explicit_port_listening' $up1 ("TCP 127.0.0.1:{0} accepted a connection after the game started" -f $ExplicitGamePort)

    $tree1 = Invoke-Mcp -Port $ExplicitGamePort -Tag 'running_game_get_scene_tree.explicit' `
        -Body (New-ToolCallBody -Tool 'running_game_get_scene_tree' -Arguments @{})
    $treePayload = $null
    if ($null -ne $tree1.json -and $null -ne $tree1.json.result) { $treePayload = $tree1.json.result.content[0].text | ConvertFrom-Json }
    Check 'game_side_tool_on_injected_port' ($null -ne $treePayload) `
        ("running_game_get_scene_tree on {0} answered: {1}" -f $ExplicitGamePort, (ConvertTo-Json $treePayload -Compress -Depth 6))

    $stop1 = Invoke-Mcp -Port $EditorPort -Tag 'stop_scene.after_explicit' `
        -Body (New-ToolCallBody -Tool 'editor_stop_scene' -Arguments @{})
    $s1 = $stop1.json.result.content[0].text | ConvertFrom-Json
    Start-Sleep -Milliseconds 1500
    Check 'stop_scene_kills_child' ($s1.stopped -eq $true -and -not (Test-ProcessAlive -ProcessId ([int]$r1.pid))) `
        ("stopped={0} message='{1}'; pid {2} alive after stop = {3}" -f $s1.stopped, $s1.message, $r1.pid, (Test-ProcessAlive -ProcessId ([int]$r1.pid)))

    # -------------------------------------------------------------------------
    # 2. the automatic port: not the editor's, and really usable
    # -------------------------------------------------------------------------
    Note ''
    Note '--- (2) automatic port ---------------------------------------------'
    $play2 = Invoke-Mcp -Port $EditorPort -Tag 'play_scene.auto.request' `
        -Body (New-ToolCallBody -Tool 'editor_play_scene' -Arguments @{ mode = 'main' })
    $r2 = $play2.json.result.content[0].text | ConvertFrom-Json
    $autoPort = [int]$r2.mcp_port
    Note ("response: {0}" -f (ConvertTo-Json $r2 -Compress))
    Check 'auto_port_source_and_range' ([string]$r2.mcp_port_source -eq 'auto_free_port' -and $autoPort -ge 1 -and $autoPort -le 65535) `
        ("mcp_port={0} mcp_port_source={1}" -f $autoPort, $r2.mcp_port_source)
    Check 'auto_port_differs_from_editor_port' ($autoPort -ne $EditorPort) `
        ("auto mcp_port={0} != editor port {1}" -f $autoPort, $EditorPort)

    $cmd2 = Get-ChildCmdline -ProcessId ([int]$r2.pid)
    Check 'auto_child_cmdline_contains_mcp_port' ($cmd2 -match ("--mcp-port=" + $autoPort)) `
        ("pid {0} command line contains --mcp-port={1}: {2}" -f $r2.pid, $autoPort, $cmd2)

    Check 'auto_port_listening' (Wait-ForPort -Port $autoPort) ("TCP 127.0.0.1:{0} accepted a connection" -f $autoPort)
    $tree2 = Invoke-Mcp -Port $autoPort -Tag 'running_game_get_scene_tree.auto' `
        -Body (New-ToolCallBody -Tool 'running_game_get_scene_tree' -Arguments @{})
    Check 'auto_game_side_tool' ($null -ne $tree2.json.result) `
        ("running_game_get_scene_tree on the auto port answered a result (sha256={0})" -f $tree2.sha256)

    $stop2 = Invoke-Mcp -Port $EditorPort -Tag 'stop_scene.after_auto' -Body (New-ToolCallBody -Tool 'editor_stop_scene' -Arguments @{})
    $s2 = $stop2.json.result.content[0].text | ConvertFrom-Json
    Start-Sleep -Milliseconds 1200
    Check 'auto_stop_scene_kills_child' ($s2.stopped -eq $true -and -not (Test-ProcessAlive -ProcessId ([int]$r2.pid))) `
        ("stopped={0}; pid {1} alive after stop = {2}" -f $s2.stopped, $r2.pid, (Test-ProcessAlive -ProcessId ([int]$r2.pid)))

    # -------------------------------------------------------------------------
    # 3. an occupied port is refused, not handed to the child
    # -------------------------------------------------------------------------
    Note ''
    Note '--- (3) occupied port / the editor own port ------------------------'
    $script:HeldListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Parse('127.0.0.1')), $HeldPort
    $script:HeldListener.Start()
    Check 'held_port_really_occupied' ((Get-ListenerPid -Port $HeldPort) -eq $PID) `
        ("this script (pid {0}) holds 127.0.0.1:{1}" -f $PID, $HeldPort)

    $pidBeforeBusy = 0
    $play3 = Invoke-Mcp -Port $EditorPort -Tag 'play_scene.busy_port.request' `
        -Body (New-ToolCallBody -Tool 'editor_play_scene' -Arguments @{ mode = 'main'; mcp_port = $HeldPort })
    $e3 = $play3.json.error
    Note ("error: {0}" -f (ConvertTo-Json $e3 -Compress -Depth 6))
    Check 'busy_port_is_refused' ($null -ne $e3 -and [int]$e3.code -eq -32000 -and ([string]$e3.message).Contains([string]$HeldPort) `
        -and $null -ne $e3.data.suggestion) `
        ("code={0} message='{1}' suggestion='{2}'" -f $e3.code, $e3.message, $e3.data.suggestion)

    $ownPort = Invoke-Mcp -Port $EditorPort -Tag 'play_scene.editor_port.request' `
        -Body (New-ToolCallBody -Tool 'editor_play_scene' -Arguments @{ mode = 'main'; mcp_port = $EditorPort })
    $e4 = $ownPort.json.error
    Check 'editor_own_port_is_refused' ($null -ne $e4 -and [int]$e4.code -eq -32000 -and ([string]$e4.message).Contains('editor')) `
        ("code={0} message='{1}' suggestion='{2}'" -f $e4.code, $e4.message, $e4.data.suggestion)

    $afterRefusal = Invoke-Mcp -Port $EditorPort -Tag 'stop_scene.after_refusals' -Body (New-ToolCallBody -Tool 'editor_stop_scene' -Arguments @{})
    $s5 = $afterRefusal.json.result.content[0].text | ConvertFrom-Json
    Check 'no_game_started_by_refused_calls' ($s5.stopped -eq $false) `
        ("editor_stop_scene after the two refusals: stopped={0} message='{1}'" -f $s5.stopped, $s5.message)

    # -------------------------------------------------------------------------
    # 4. argument classes (gate 2): bad type / out of range / missing arg /
    #    underlying failure
    # -------------------------------------------------------------------------
    Note ''
    Note '--- (4) argument and failure classes -------------------------------'
    $badType = Invoke-Mcp -Port $EditorPort -Tag 'play_scene.bad_type.request' `
        -Body '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"editor_play_scene","arguments":{"mcp_port":"19890"}}}'
    Check 'wrong_type_is_-32602' ([int]$badType.json.error.code -eq -32602 -and ([string]$badType.json.error.message).Contains('must be an integer')) `
        ("code={0} message='{1}'" -f $badType.json.error.code, $badType.json.error.message)

    foreach ($rangeCase in @(@{ port = 0; label = 'zero' }, @{ port = 99999; label = 'too_big' }, @{ port = -1; label = 'negative' })) {
        $resp = Invoke-Mcp -Port $EditorPort -Tag ('play_scene.range_' + $rangeCase.label + '.request') `
            -Body (New-ToolCallBody -Tool 'editor_play_scene' -Arguments @{ mcp_port = $rangeCase.port })
        Check ('out_of_range_' + $rangeCase.label + '_is_-32602') `
            ([int]$resp.json.error.code -eq -32602 -and ([string]$resp.json.error.message).Contains('between 1 and 65535')) `
            ("mcp_port={0} -> code={1} message='{2}'" -f $rangeCase.port, $resp.json.error.code, $resp.json.error.message)
    }

    $missingScene = Invoke-Mcp -Port $EditorPort -Tag 'play_scene.missing_scene.request' `
        -Body (New-ToolCallBody -Tool 'editor_play_scene' -Arguments @{ mode = 'res://scenes/nope.tscn'; mcp_port = $ExplicitGamePort })
    Check 'missing_scene_is_-32001' ([int]$missingScene.json.error.code -eq -32001 -and $null -ne $missingScene.json.error.data.suggestion) `
        ("code={0} message='{1}' suggestion='{2}'" -f $missingScene.json.error.code, $missingScene.json.error.message, $missingScene.json.error.data.suggestion)

    $outsidePath = Invoke-Mcp -Port $EditorPort -Tag 'play_scene.outside_path.request' `
        -Body (New-ToolCallBody -Tool 'editor_play_scene' -Arguments @{ mode = 'C:/outside/scene.tscn' })
    Check 'outside_path_is_-32602' ([int]$outsidePath.json.error.code -eq -32602) `
        ("mode=C:/outside/scene.tscn -> code={0} message='{1}'" -f $outsidePath.json.error.code, $outsidePath.json.error.message)

    # -------------------------------------------------------------------------
    # 5. the three modes still work (regression)
    # -------------------------------------------------------------------------
    Note ''
    Note '--- (5) mode regression: main / current / path ---------------------'
    $playMain = Invoke-Mcp -Port $EditorPort -Tag 'play_scene.mode_main.request' `
        -Body (New-ToolCallBody -Tool 'editor_play_scene' -Arguments @{ mode = 'main'; mcp_port = $ExplicitGamePort })
    $rMain = $playMain.json.result.content[0].text | ConvertFrom-Json
    $cmdMain = Get-ChildCmdline -ProcessId ([int]$rMain.pid)
    Check 'mode_main_ok' ($rMain.playing -eq $true -and [string]$rMain.mode -eq 'main' -and -not ($rMain.PSObject.Properties.Name -contains 'path') `
        -and $cmdMain -match ('--mcp-port=' + $ExplicitGamePort) -and (Wait-ForPort -Port $ExplicitGamePort)) `
        ("playing={0} mode={1} port={2} pid={3}; cmdline='{4}'" -f $rMain.playing, $rMain.mode, $rMain.mcp_port, $rMain.pid, $cmdMain)
    Invoke-Mcp -Port $EditorPort -Tag 'stop_scene.after_mode_main' -Body (New-ToolCallBody -Tool 'editor_stop_scene' -Arguments @{}) | Out-Null
    Start-Sleep -Milliseconds 1200

    $openOther = Invoke-Mcp -Port $EditorPort -Tag 'editor_open_scene.other' `
        -Body (New-ToolCallBody -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/other.tscn' })
    Note ("editor_open_scene: {0}" -f (ConvertTo-Json $openOther.json.result.content[0].text -Compress))

    $playCurrent = Invoke-Mcp -Port $EditorPort -Tag 'play_scene.mode_current.request' `
        -Body (New-ToolCallBody -Tool 'editor_play_scene' -Arguments @{ mode = 'current'; mcp_port = $CurrentGamePort })
    $rCurrent = $playCurrent.json.result.content[0].text | ConvertFrom-Json
    $cmdCurrent = Get-ChildCmdline -ProcessId ([int]$rCurrent.pid)
    Check 'mode_current_ok' ($rCurrent.playing -eq $true -and [string]$rCurrent.mode -eq 'current' `
        -and $cmdCurrent -match ('--mcp-port=' + $CurrentGamePort) -and (Wait-ForPort -Port $CurrentGamePort)) `
        ("playing={0} mode={1} port={2} pid={3}; cmdline='{4}'" -f $rCurrent.playing, $rCurrent.mode, $rCurrent.mcp_port, $rCurrent.pid, $cmdCurrent)
    Invoke-Mcp -Port $EditorPort -Tag 'stop_scene.after_mode_current' -Body (New-ToolCallBody -Tool 'editor_stop_scene' -Arguments @{}) | Out-Null
    Start-Sleep -Milliseconds 1200

    $playCustom = Invoke-Mcp -Port $EditorPort -Tag 'play_scene.mode_path.request' `
        -Body (New-ToolCallBody -Tool 'editor_play_scene' -Arguments @{ mode = 'res://scenes/other.tscn'; mcp_port = $CustomGamePort })
    $rCustom = $playCustom.json.result.content[0].text | ConvertFrom-Json
    $cmdCustom = Get-ChildCmdline -ProcessId ([int]$rCustom.pid)
    Check 'mode_path_ok' ($rCustom.playing -eq $true -and [string]$rCustom.mode -eq 'res://scenes/other.tscn' -and [string]$rCustom.path -eq 'res://scenes/other.tscn' `
        -and $cmdCustom -match ('--mcp-port=' + $CustomGamePort) -and $cmdCustom -match '--scene' -and (Wait-ForPort -Port $CustomGamePort)) `
        ("playing={0} mode={1} path={2} pid={3}; cmdline='{4}'" -f $rCustom.playing, $rCustom.mode, $rCustom.path, $rCustom.pid, $cmdCustom)

    # -------------------------------------------------------------------------
    # 6. a cross-tool chain with zero string surgery (PLAYBOOK gate 2)
    # -------------------------------------------------------------------------
    Note ''
    Note '--- (6) cross-tool chain on the immediately observable game --------'
    $chainTree = Invoke-Mcp -Port $CustomGamePort -Tag 'chain.scene_tree' -Body (New-ToolCallBody -Tool 'running_game_get_scene_tree' -Arguments @{})
    $chainPayload = $chainTree.json.result.content[0].text | ConvertFrom-Json
    $rootPath = $null
    if ($null -ne $chainPayload.tree) { $rootPath = [string]$chainPayload.tree.path }
    if ([string]::IsNullOrEmpty($rootPath)) { $rootPath = [string]$chainPayload.tree.name }
    $chainProps = Invoke-Mcp -Port $CustomGamePort -Tag 'chain.node_properties' `
        -Body (New-ToolCallBody -Tool 'running_game_get_node_properties' -Arguments @{ node_path = $rootPath })
    $chainPropsPayload = $chainProps.json.result.content[0].text | ConvertFrom-Json
    Check 'zero_string_surgery_chain' ($null -ne $chainPayload -and $null -ne $chainPropsPayload -and $null -eq $chainProps.json.error) `
        ("step1 running_game_get_scene_tree -> step2 running_game_get_node_properties(node_path='{0}') answered type='{1}' (string operations by the caller: 0)" -f $rootPath, $chainPropsPayload.type)

    Invoke-Mcp -Port $EditorPort -Tag 'stop_scene.after_chain' -Body (New-ToolCallBody -Tool 'editor_stop_scene' -Arguments @{}) | Out-Null
    Start-Sleep -Milliseconds 1500
    Check 'no_orphan_after_chain' (-not (Test-ProcessAlive -ProcessId ([int]$rCustom.pid))) `
        ("pid {0} gone after editor_stop_scene" -f $rCustom.pid)
} finally {
    if ($null -ne $script:HeldListener) { try { $script:HeldListener.Stop() } catch { } }
    if ($null -ne $script:EditorProcess -and -not $script:EditorProcess.HasExited) {
        Stop-Process -Id $script:EditorProcess.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 1000
    }
    $userPidAfter = Get-ListenerPid -Port $UserPort
    Check 'guard_user_port_9877' ($userPidBefore -eq $userPidAfter) ("pid_before={0} pid_after={1}" -f $userPidBefore, $userPidAfter)
}

$logPath = Join-Path $Ev 'evidence.log.txt'
Write-Utf8NoBom -Path $logPath -Text (($script:Log -join "`r`n") + "`r`n")

$passed = @($script:Checks | Where-Object { $_.pass }).Count
$total = $script:Checks.Count
Write-Host ''
Write-Host '========================== SUMMARY =========================='
foreach ($c in $script:Checks) {
    $tag = if ($c.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0}  {1}" -f $tag, $c.id)
}
Write-Host ("{0}/{1} checks passed; evidence in {2}" -f $passed, $total, $Ev)
if ($passed -ne $total) { exit 1 }
exit 0
