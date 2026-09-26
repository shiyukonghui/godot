# =============================================================================
#  mcp011_deferred_evidence.ps1 -- TASK-011 gate 2 / section 1.8 + section 2
#
#  The live evidence for the deferred response channel (GDR-20) and for the four
#  tools TASK-011 ports.
#
#  Phases:
#    -Phase game     A *headless* game process on 9889.
#                     * the five state-machine classes on real requests:
#                       normal completion, timeout, disconnect cleanup,
#                       interleaved pendings on different connections, and
#                       "a pending never starves the ordinary requests";
#                     * cross-frame sampling really produces different samples
#                       (`moved_frames` strictly increasing over N frames);
#                     * the three evidence classes per tool (success /
#                       missing-or-mistyped parameter / bottom-layer failure);
#                     * the timeout really returns -32000 with `data.timeout_ms`
#                       and the service answers the very next request;
#                     * closing a connection during a pending drops the pending
#                       (observable pending count before/after) and never leaks.
#    -Phase capture  A *windowed* game process on 9889 (a real display server).
#                     The headless renderer has no texture storage at all
#                     (`RendererDummy::TextureStorage::texture_2d_get` returns
#                     null and logs `Parameter "t" is null`), so a real
#                     framebuffer is the only way to show frames that are
#                     provably different: distinct SceneTree frame numbers *and*
#                     distinct PNG digests, from a sprite that moves and changes
#                     colour every frame.
#
#  Discipline (PLAYBOOK section 3 and section 7.1):
#    * every response body is written to its own file - simple requests with
#      `curl.exe -s -o <file>`, the raw-socket cases (disconnect, interleaving,
#      starvation) with `[IO.File]::WriteAllBytes` - and a sha256 is printed from
#      the bytes on disk. Nothing goes through `Out-File` or a pipeline.
#    * ports 9888 (editor) / 9889 (game) only. Port 9877 belongs to the user's
#      editor: it is never touched, only observed, and its listener pid is
#      asserted unchanged at the end of every phase.
#    * only engines this script started itself are stopped.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp011_deferred_evidence.ps1 -Phase game
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp011_deferred_evidence.ps1 -Phase capture
# =============================================================================

param(
    [ValidateSet('game', 'capture')]
    [string]$Phase = 'game'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$GamePort = 9889
$UserPort = 9877
$Scratch = Join-Path $env:TEMP 'mcp011-deferred-scratch'
$LogRoot = Join-Path $env:TEMP 'mcp011-deferred-logs'
$Evid = Join-Path $env:TEMP 'mcp011-deferred-evidence'

$FrameTools = @(
    'running_game_get_node_property_samples',
    'running_game_find_node_when_available',
    'running_game_capture_frames',
    'running_game_capture_screenshot'
)

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

function Import-Project {
    param([string]$Path, [string]$LogName)
    $out = Join-Path $LogRoot ($LogName + '.out.log')
    $err = Join-Path $LogRoot ($LogName + '.err.log')
    $proc = Start-Process -FilePath $Engine -ArgumentList @('--headless', '--path', $Path, '--import') `
        -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    $proc.WaitForExit(300000) | Out-Null
}

# -----------------------------------------------------------------------------
# HTTP: curl for the simple requests, a raw socket for the ones that need
# connection control (closing during a pending, two pendings at once, timing a
# request while another one is pending).
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
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] curl port={1} exit={2} bytes={3} sha256={4}" -f $Id, $Port, $curlExit, $bytes.Length, $sha)
    Write-Host ("       request : {0}" -f $Json)
    Write-Host ("       response: {0}" -f $text)
    return $text
}

function Invoke-Status {
    param([string]$Id, [int]$Port)
    $respFile = Join-Path $Evid ("{0}.response.json" -f $Id)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s -o $respFile ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($respFile))
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    Write-Host ("[{0}] GET /mcp sha256={1}" -f $Id, $sha)
    Write-Host ("       status: {0}" -f $text)
    return $text
}

function Open-Conn {
    param([int]$Port, [int]$Timeout = 5000)
    $client = New-Object System.Net.Sockets.TcpClient
    $task = $client.ConnectAsync('127.0.0.1', $Port)
    if (-not $task.Wait($Timeout)) { throw "connect to 127.0.0.1:$Port timed out" }
    $client.NoDelay = $true
    return [pscustomobject]@{ Client = $client; Stream = $client.GetStream() }
}

function Send-Request {
    param($Conn, [string]$Json, [bool]$Close = $false)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Json)
    $connection = if ($Close) { 'close' } else { 'keep-alive' }
    $head = "POST /mcp HTTP/1.1`r`nHost: 127.0.0.1`r`nContent-Type: application/json`r`nConnection: $connection`r`nContent-Length: $($bytes.Length)`r`n`r`n"
    $Conn.Stream.Write([Text.Encoding]::UTF8.GetBytes($head), 0, $head.Length)
    $Conn.Stream.Write($bytes, 0, $bytes.Length)
    $Conn.Stream.Flush()
}

function Read-Message {
    param($Conn, [int]$Timeout = 30000, [string]$Id = '', [bool]$SaveBytes = $true)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($Timeout)
    $buffer = New-Object System.Collections.Generic.List[byte]
    $chunk = New-Object byte[] 65536
    while ([DateTime]::UtcNow -lt $deadline) {
        $data = $buffer.ToArray()
        $headerEnd = -1
        for ($i = 0; $i -le $data.Length - 4; $i++) {
            if ($data[$i] -eq 13 -and $data[$i + 1] -eq 10 -and $data[$i + 2] -eq 13 -and $data[$i + 3] -eq 10) {
                $headerEnd = $i
                break
            }
        }
        if ($headerEnd -ge 0) {
            $headerText = [Text.Encoding]::ASCII.GetString($data, 0, $headerEnd)
            $length = 0
            foreach ($line in ($headerText -split "`r`n")) {
                if ($line -match '^(?i)content-length:\s*(\d+)\s*$') { $length = [int]$Matches[1] }
            }
            if (($data.Length - ($headerEnd + 4)) -ge $length) {
                $body = [Text.Encoding]::UTF8.GetString($data, $headerEnd + 4, $length)
                if ($SaveBytes -and $Id -ne '') {
                    Write-Utf8NoBom -Path (Join-Path $Evid ("{0}.response.json" -f $Id)) -Text $body
                    $sha = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid ("{0}.response.json" -f $Id))).Hash.ToLower()
                    Write-Host ("[{0}] raw exit=0 bytes={1} sha256={2}" -f $Id, $length, $sha)
                    Write-Host ("       response: {0}" -f $body)
                }
                return [pscustomobject]@{
                    Status = [int]([regex]::Match($headerText, '^HTTP/1\.1\s+(\d+)').Groups[1].Value)
                    Header = $headerText
                    Body = $body
                }
            }
        }
        if ($Conn.Stream.DataAvailable) {
            $read = $Conn.Stream.Read($chunk, 0, $chunk.Length)
            if ($read -gt 0) {
                $part = New-Object byte[] $read
                [Array]::Copy($chunk, 0, $part, 0, $read)
                $buffer.AddRange($part)
            } else { Start-Sleep -Milliseconds 10 }
        } else { Start-Sleep -Milliseconds 10 }
    }
    throw "no complete HTTP response within $Timeout ms"
}

function Close-Conn {
    param($Conn)
    try { $Conn.Client.Close() } catch { }
}

function New-CallBody {
    param([int]$Id, [string]$Tool, $Arguments)
    $argsJson = $Arguments | ConvertTo-Json -Depth 8 -Compress
    return ('{"jsonrpc":"2.0","id":' + $Id + ',"method":"tools/call","params":{"name":"' + $Tool + '","arguments":' + $argsJson + '}}')
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
    try { return ($ResponseText | ConvertFrom-Json).error } catch { return $null }
}

function Add-ErrorCheck {
    param([string]$Id, [string]$ResponseText, [int]$Code, [string]$MessageFragment = '')
    $e = Get-ErrorObject $ResponseText
    if ($null -eq $e) {
        Add-Check $Id $false ("expected error {0}, got: {1}" -f $Code, $ResponseText)
        return $false
    }
    $ok = ($e.code -eq $Code)
    if ($MessageFragment -ne '') { $ok = $ok -and ([string]$e.message).Contains($MessageFragment) }
    Add-Check $Id $ok ("code={0} message='{1}' expected={2} contains='{3}'" -f $e.code, $e.message, $Code, $MessageFragment)
    return $ok
}

function Wait-ForFrames {
    param([int]$Port, [int]$TimeoutMs = 180000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $previous = $null
    $steady = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $text = Invoke-Status -Id 'pump-probe' -Port $Port
            $json = $text | ConvertFrom-Json
            $frames = [int]$json.frame_count
            if ($null -ne $previous -and ($frames - $previous) -ge 10) { $steady++ } else { $steady = 0 }
            if ($steady -ge 3) { return $true }
            $previous = $frames
        } catch { }
        Start-Sleep -Milliseconds 700
    }
    return $false
}

function Show-PortGuard {
    param([int]$Before)
    $after = Get-ListenerPid -Port $UserPort
    Add-Check 'guard_user_port_9877' (($Before -eq $after) -and ($Before -ne -1)) `
        ("port {0} pid_before={1} pid_after={2}" -f $UserPort, $Before, $after)
}

# =============================================================================
#  The scratch project: a Player that moves and repaints every frame (so both a
#  sampled property and the rendered pixels change across frames), and a
#  Latecomer that appears one second in (so a real "wait for a node" has
#  something to find).
# =============================================================================

function Initialize-Scratch {
    if (Test-Path $Scratch) { Remove-Item -Recurse -Force $Scratch }
    New-Item -ItemType Directory -Force -Path $Scratch | Out-Null

    $project = @(
        'config_version=5',
        '',
        '[application]',
        'config/name="MCP011 deferred evidence"',
        'run/main_scene="res://main.tscn"',
        'config/features=PackedStringArray("4.8")',
        '',
        '[rendering]',
        'renderer/rendering_method="gl_compatibility"',
        'renderer/rendering_method.mobile="gl_compatibility"'
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-Path $Scratch 'project.godot') -Text $project

    $scene = @(
        '[gd_scene load_steps=3 format=3]',
        '',
        '[ext_resource type="Script" path="res://main.gd" id="1"]',
        '[ext_resource type="Script" path="res://player.gd" id="2"]',
        '',
        '[node name="Main" type="Node"]',
        'script = ExtResource("1")',
        '',
        '[node name="Player" type="Node2D" parent="."]',
        'script = ExtResource("2")'
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-Path $Scratch 'main.tscn') -Text $scene

    $main = @(
        'extends Node',
        '',
        '# A node that only exists after one second, so that',
        '# `running_game_find_node_when_available` has something real to wait for.',
        'func _ready() -> void:',
        '	var timer := Timer.new()',
        '	timer.wait_time = 1.0',
        '	timer.one_shot = true',
        '	timer.autostart = true',
        '	timer.timeout.connect(_add_latecomer)',
        '	add_child(timer)',
        '',
        'func _add_latecomer() -> void:',
        '	var late := Node2D.new()',
        '	late.name = "Latecomer"',
        '	add_child(late)'
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-Path $Scratch 'main.gd') -Text $main

    $player = @(
        'extends Node2D',
        '',
        '# Strictly increasing: the observable that proves N samples came from N',
        '# different frames.',
        'var moved_frames := 0',
        '',
        'func _process(_delta: float) -> void:',
        '	moved_frames += 1',
        '	# Wraps, so the sprite stays inside the viewport however long the',
        '	# evidence run takes - while still changing position every frame.',
        '	position.x = fmod(position.x + 4.0, 600.0)',
        '	queue_redraw()',
        '',
        'func _draw() -> void:',
        '	# The colour changes every frame as well, so two rendered frames can',
        '	# never be pixel identical even if the position wrapped onto itself.',
        '	var hue := fmod(float(moved_frames) * 0.02, 1.0)',
        '	draw_circle(Vector2(60, 80), 50.0, Color.from_hsv(hue, 0.9, 1.0))'
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-Path $Scratch 'player.gd') -Text $player

    Write-Host ("scratch project: {0}" -f $Scratch)
    Import-Project -Path $Scratch -LogName 'import'
}

# =============================================================================
#  Phase game (headless): the state machine, the three evidence classes and the
#  cross-frame sampling proof.
# =============================================================================

function Invoke-GamePhase {
    param($Handle)

    $status = Invoke-Status -Id 'g00_baseline' -Port $GamePort
    $baseline = $status | ConvertFrom-Json
    Add-Check 'g00_pending_observable' `
        (($null -ne $baseline.pending) -and ($null -ne $baseline.pending_connections) -and ($baseline.pending -eq 0)) `
        ("status keys: pending={0} pending_connections={1} connections={2}" -f $baseline.pending, $baseline.pending_connections, $baseline.connections)

    # --- cross-frame sampling: N samples, N different frames ----------------
    $samplesResponse = Invoke-Curl -Id 'g01_samples_success' -Port $GamePort -Json (New-CallBody -Id 11 -Tool 'running_game_get_node_property_samples' -Arguments @{
            node_path = 'Player'; properties = @('moved_frames', 'position'); frame_count = 6; frame_interval = 1
        })
    $samples = Get-Payload $samplesResponse
    $counted = if ($null -ne $samples) { @($samples.samples).Count } else { 0 }
    $values = if ($counted -gt 0) { @($samples.samples | ForEach-Object { [int64]$_.moved_frames }) } else { @() }
    $increasing = $true
    for ($i = 1; $i -lt $values.Count; $i++) { if ($values[$i] -le $values[$i - 1]) { $increasing = $false } }
    Add-Check 'g01_samples_cross_frame_distinct' (($counted -eq 6) -and $increasing -and ($values.Count -eq 6)) `
        ("node_path={0} samples={1} moved_frames=[{2}] strictly_increasing={3}" -f $samples.node_path, $counted, ($values -join ','), $increasing)

    Add-ErrorCheck -Id 'g02_samples_missing_param' -ResponseText (Invoke-Curl -Id 'g02_samples_missing_param' -Port $GamePort -Json (New-CallBody -Id 12 -Tool 'running_game_get_node_property_samples' -Arguments @{ node_path = 'Player' })) -Code -32602 -MessageFragment 'properties'
    Add-ErrorCheck -Id 'g03_samples_bottom_layer' -ResponseText (Invoke-Curl -Id 'g03_samples_bottom_layer' -Port $GamePort -Json (New-CallBody -Id 13 -Tool 'running_game_get_node_property_samples' -Arguments @{ node_path = 'DoesNotExist'; properties = @('position') })) -Code -32001 -MessageFragment 'not found'

    # --- wait for a node that really appears --------------------------------
    $findResponse = Invoke-Curl -Id 'g04_find_success' -Port $GamePort -Json (New-CallBody -Id 14 -Tool 'running_game_find_node_when_available' -Arguments @{
            node_path = 'Latecomer'; poll_frames = 3; timeout = 8.0
        })
    $found = Get-Payload $findResponse
    Add-Check 'g04_find_success' (($null -ne $found) -and ($found.found -eq $true) -and ([string]$found.node_path -eq '/root/Main/Latecomer')) `
        ("found={0} node_path={1} type={2} name={3}" -f $found.found, $found.node_path, $found.type, $found.name)

    Add-ErrorCheck -Id 'g05_find_missing_param' -ResponseText (Invoke-Curl -Id 'g05_find_missing_param' -Port $GamePort -Json (New-CallBody -Id 15 -Tool 'running_game_find_node_when_available' -Arguments @{ poll_frames = 3 })) -Code -32602 -MessageFragment 'node_path'

    # --- the timeout class, timed ------------------------------------------
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $timeoutResponse = Invoke-Curl -Id 'g06_find_timeout' -Port $GamePort -Json (New-CallBody -Id 16 -Tool 'running_game_find_node_when_available' -Arguments @{
            node_path = 'NeverAppears'; poll_frames = 3; timeout = 2.0
        })
    $watch.Stop()
    $timeoutError = Get-ErrorObject $timeoutResponse
    $timeoutOk = ($null -ne $timeoutError) -and ($timeoutError.code -eq -32000) -and
        ($null -ne $timeoutError.data) -and ([int64]$timeoutError.data.timeout_ms -eq 2000) -and
        ([string]$timeoutError.data.suggestion).Length -gt 0 -and
        ($watch.ElapsedMilliseconds -ge 1800) -and ($watch.ElapsedMilliseconds -le 15000)
    Add-Check 'g06_find_timeout_is_-32000_with_timeout_ms' $timeoutOk `
        ("elapsed_ms={0} code={1} timeout_ms={2} suggestion='{3}'" -f $watch.ElapsedMilliseconds, $timeoutError.code, $timeoutError.data.timeout_ms, $timeoutError.data.suggestion)

    # The service must be perfectly usable right after a timeout expired.
    $afterTimeout = Invoke-Curl -Id 'g07_service_alive_after_timeout' -Port $GamePort -Json '{"jsonrpc":"2.0","id":17,"method":"ping"}'
    $afterJson = $afterTimeout | ConvertFrom-Json
    Add-Check 'g07_service_alive_after_timeout' (($null -ne $afterJson.result) -and ((Invoke-Status -Id 'g07_status' -Port $GamePort) | ConvertFrom-Json).pending -eq 0) `
        ("ping id={0} result_present={1}; pending back to 0" -f $afterJson.id, ($null -ne $afterJson.result))

    # --- disconnect while pending ------------------------------------------
    $conn = Open-Conn -Port $GamePort
    Send-Request -Conn $conn -Json (New-CallBody -Id 909 -Tool 'running_game_find_node_when_available' -Arguments @{ node_path = 'NeverAppears'; poll_frames = 3; timeout = 10.0 })
    Start-Sleep -Milliseconds 700
    $during = (Invoke-Status -Id 'g08_pending_during_disconnect' -Port $GamePort) | ConvertFrom-Json
    Close-Conn $conn
    Start-Sleep -Milliseconds 900
    $afterDrop = (Invoke-Status -Id 'g09_pending_after_disconnect' -Port $GamePort) | ConvertFrom-Json
    Add-Check 'g09_disconnect_releases_pending' (($during.pending -eq 1) -and ($afterDrop.pending -eq 0) -and ($afterDrop.pending_connections -eq 0)) `
        ("pending during={0} (connections={1}) -> after close={2} (pending_connections={3}, connections={4})" -f $during.pending, $during.connections, $afterDrop.pending, $afterDrop.pending_connections, $afterDrop.connections)

    $alive = Invoke-Curl -Id 'g10_service_alive_after_disconnect' -Port $GamePort -Json '{"jsonrpc":"2.0","id":18,"method":"ping"}'
    Add-Check 'g10_service_alive_after_disconnect' (($alive | ConvertFrom-Json).result -ne $null) ("after the pending connection died: {0}" -f $alive)

    # --- two pendings on two connections, no crossing -----------------------
    #
    # Both requests must still be *pending* when the count is read, so neither
    # may be answerable yet: A waits for a node that does not exist at all until
    # the injection below creates it, and B waits for one that never appears.
    # The injection is an ordinary immediate tool on a third connection, which is
    # the second half of the starvation proof: it answers while two deferred
    # requests are in flight.
    $connA = Open-Conn -Port $GamePort
    $connB = Open-Conn -Port $GamePort
    Send-Request -Conn $connA -Json (New-CallBody -Id 101 -Tool 'running_game_find_node_when_available' -Arguments @{ node_path = 'DeferredLatecomer'; poll_frames = 3; timeout = 8.0 })
    Send-Request -Conn $connB -Json (New-CallBody -Id 202 -Tool 'running_game_find_node_when_available' -Arguments @{ node_path = 'NeverAppears'; poll_frames = 3; timeout = 2.0 })
    Start-Sleep -Milliseconds 600
    $interleaved = (Invoke-Status -Id 'g11_pending_interleaved' -Port $GamePort) | ConvertFrom-Json

    $injectProbe = [Diagnostics.Stopwatch]::StartNew()
    # `Engine.get_main_loop()` and not `get_tree()`: the executed body is wrapped
    # in `extends RefCounted` by the tool, so the `Node::get_tree()` shortcut does
    # not exist there (the first attempt of this script failed with exactly that
    # parse error, see the report's errata).
    $injectResponse = Invoke-Curl -Id 'g11b_inject_node_while_two_pending' -Port $GamePort -Json (New-CallBody -Id 203 -Tool 'running_game_execute_gdscript' -Arguments @{
            code = "var scene := (Engine.get_main_loop() as SceneTree).current_scene`nvar node := Node2D.new()`nnode.name = ""DeferredLatecomer""`nscene.add_child(node)`nreturn ""added""`n"
        }) -MaxTimeSec 10
    $injectProbe.Stop()
    $injectPayload = Get-Payload $injectResponse
    Add-Check 'g11b_injection_answered_while_two_pending' `
        (($null -ne $injectPayload) -and ([string]$injectPayload.result -eq 'added') -and ($injectProbe.ElapsedMilliseconds -lt 1500) -and ($interleaved.pending -eq 2)) `
        ("pending at the probe={0} over {1} connection(s); the gdscript injection was answered in {2} ms with result='{3}'" -f `
            $interleaved.pending, $interleaved.pending_connections, $injectProbe.ElapsedMilliseconds, $injectPayload.result)

    $responseB = Read-Message -Conn $connB -Timeout 15000 -Id 'g12_interleaved_b'
    $responseA = Read-Message -Conn $connA -Timeout 15000 -Id 'g13_interleaved_a'
    Close-Conn $connA
    Close-Conn $connB
    $errorB = Get-ErrorObject $responseB.Body
    $payloadA = Get-Payload $responseA.Body
    $aJson = $responseA.Body | ConvertFrom-Json
    $bJson = $responseB.Body | ConvertFrom-Json
    $crossed = ([string]$responseA.Body).Contains('"id":202') -or ([string]$responseB.Body).Contains('"id":101')
    Add-Check 'g11_interleaved_pendings_do_not_cross' `
        (($interleaved.pending -eq 2) -and ($interleaved.pending_connections -eq 2) -and
        ($aJson.id -eq 101) -and ($payloadA.found -eq $true) -and ([string]$payloadA.node_path -eq '/root/Main/DeferredLatecomer') -and
        ($bJson.id -eq 202) -and ($errorB.code -eq -32000) -and ([int64]$errorB.data.timeout_ms -eq 2000) -and (-not $crossed)) `
        ("during={0} pendings over {1} connections; A id={2} found={3} node={4}; B id={5} code={6} timeout_ms={7}; crossed={8}" -f `
            $interleaved.pending, $interleaved.pending_connections, $aJson.id, $payloadA.found, $payloadA.node_path, $bJson.id, $errorB.code, $errorB.data.timeout_ms, $crossed)

    # --- a pending must not starve an ordinary request ----------------------
    $connLong = Open-Conn -Port $GamePort
    Send-Request -Conn $connLong -Json (New-CallBody -Id 303 -Tool 'running_game_find_node_when_available' -Arguments @{ node_path = 'NeverAppears'; poll_frames = 3; timeout = 10.0 })
    Start-Sleep -Milliseconds 700
    $pendingNow = ((Invoke-Status -Id 'g14_pending_during_starvation_probe' -Port $GamePort) | ConvertFrom-Json).pending
    $probe = [Diagnostics.Stopwatch]::StartNew()
    $pingWhilePending = Invoke-Curl -Id 'g15_ping_while_pending' -Port $GamePort -Json '{"jsonrpc":"2.0","id":19,"method":"ping"}' -MaxTimeSec 5
    $probe.Stop()
    $stillPending = ((Invoke-Status -Id 'g16_pending_after_starvation_probe' -Port $GamePort) | ConvertFrom-Json).pending
    Add-Check 'g15_pending_does_not_starve' `
        (($pendingNow -eq 1) -and (($pingWhilePending | ConvertFrom-Json).result -ne $null) -and ($probe.ElapsedMilliseconds -lt 1500) -and ($stillPending -eq 1)) `
        ("pending before probe={0}, ping answered in {1} ms, pending after probe={2}" -f $pendingNow, $probe.ElapsedMilliseconds, $stillPending)
    Close-Conn $connLong
    Start-Sleep -Milliseconds 900
    $finalPending = ((Invoke-Status -Id 'g17_pending_after_long_close' -Port $GamePort) | ConvertFrom-Json).pending
    Add-Check 'g17_long_pending_released_on_close' ($finalPending -eq 0) ("pending={0} after the long-waiting connection was closed" -f $finalPending)

    # --- the three evidence classes of the capture tools in a headless process
    Add-ErrorCheck -Id 'g18_capture_frames_no_framebuffer' -ResponseText (Invoke-Curl -Id 'g18_capture_frames_no_framebuffer' -Port $GamePort -Json (New-CallBody -Id 20 -Tool 'running_game_capture_frames' -Arguments @{ count = 2; frame_interval = 3 })) -Code -32000 -MessageFragment 'framebuffer'
    Add-ErrorCheck -Id 'g19_capture_screenshot_no_framebuffer' -ResponseText (Invoke-Curl -Id 'g19_capture_screenshot_no_framebuffer' -Port $GamePort -Json (New-CallBody -Id 21 -Tool 'running_game_capture_screenshot' -Arguments @{})) -Code -32000 -MessageFragment 'framebuffer'
    Add-ErrorCheck -Id 'g20_capture_frames_missing_param' -ResponseText (Invoke-Curl -Id 'g20_capture_frames_missing_param' -Port $GamePort -Json (New-CallBody -Id 22 -Tool 'running_game_capture_frames' -Arguments @{ count = 0 })) -Code -32602 -MessageFragment 'at least 1'
    Add-ErrorCheck -Id 'g21_capture_screenshot_bad_path' -ResponseText (Invoke-Curl -Id 'g21_capture_screenshot_bad_path' -Port $GamePort -Json (New-CallBody -Id 23 -Tool 'running_game_capture_screenshot' -Arguments @{ save_path = 'C:/outside/shot.png' })) -Code -32602 -MessageFragment "must start with 'res://' or 'user://'"

    # --- the four new tools are served by the game endpoint -----------------
    $list = Invoke-Curl -Id 'g22_tools_list' -Port $GamePort -Json '{"jsonrpc":"2.0","id":24,"method":"tools/list","params":{}}'
    $listed = @((($list | ConvertFrom-Json).result.tools) | ForEach-Object { [string]$_.name })
    $missing = @($FrameTools | Where-Object { $listed -notcontains $_ })
    Add-Check 'g22_game_endpoint_serves_the_four' ($missing.Count -eq 0) `
        ("tools={0} missing=[{1}]" -f $listed.Count, ($missing -join ','))
}

# =============================================================================
#  Phase capture (windowed): a real framebuffer, so frames can be shown to be
#  different from one another rather than merely numbered differently.
# =============================================================================

function Invoke-CapturePhase {
    param($Handle)

    $hello = Invoke-Status -Id 'c00_baseline' -Port $GamePort
    Write-Host ("windowed game status: {0}" -f $hello)

    $samplesResponse = Invoke-Curl -Id 'c01_samples_windowed' -Port $GamePort -Json (New-CallBody -Id 31 -Tool 'running_game_get_node_property_samples' -Arguments @{
            node_path = 'Player'; properties = @('moved_frames', 'position'); frame_count = 6; frame_interval = 2
        })
    $samples = Get-Payload $samplesResponse
    $values = @($samples.samples | ForEach-Object { [int64]$_.moved_frames })
    $positions = @($samples.samples | ForEach-Object { [double]$_.position.x })
    $increasing = $true
    for ($i = 1; $i -lt $values.Count; $i++) { if ($values[$i] -le $values[$i - 1]) { $increasing = $false } }
    Add-Check 'c01_samples_cross_frame_windowed' ((@($samples.samples).Count -eq 6) -and $increasing) `
        ("samples={0} moved_frames=[{1}] position.x=[{2}]" -f @($samples.samples).Count, ($values -join ','), ($positions -join ','))

    $framesResponse = Invoke-Curl -Id 'c02_capture_frames' -Port $GamePort -Json (New-CallBody -Id 32 -Tool 'running_game_capture_frames' -Arguments @{
            count = 3; frame_interval = 4; half_resolution = $false
        })
    $frames = Get-Payload $framesResponse
    $frameCount = @($frames.frames).Count
    $frameNumbers = @($frames.frames | ForEach-Object { [int64]$_.frame })
    $digests = @($frames.frames | ForEach-Object { [string]$_.sha256 })
    $distinctFrames = (@($frameNumbers | Sort-Object -Unique).Count -eq $frameCount) -and ($frameCount -eq 3)
    $distinctDigests = (@($digests | Sort-Object -Unique).Count -eq $frameCount)
    $allNonEmpty = (@($digests | Where-Object { $_.Length -eq 64 }).Count -eq $frameCount) -and
        (@($frames.frames | Where-Object { ([string]$_.image_base64).Length -gt 0 }).Count -eq $frameCount) -and
        (@($frames.frames | Where-Object { [int]$_.width -gt 0 }).Count -eq $frameCount)
    Add-Check 'c02_capture_frames_cross_frame_distinguishable' ($distinctFrames -and $distinctDigests -and $allNonEmpty) `
        ("frames={0} scene_frames=[{1}] distinct_digests={2} all_non_empty={3}" -f $frameCount, ($frameNumbers -join ','), $distinctDigests, $allNonEmpty)
    Add-Check 'c02b_capture_frames_png_digests' ($distinctDigests) ("sha256=[{0}]" -f ($digests -join ','))

    $shotResponse = Invoke-Curl -Id 'c03_capture_screenshot' -Port $GamePort -Json (New-CallBody -Id 33 -Tool 'running_game_capture_screenshot' -Arguments @{})
    $shot = Get-Payload $shotResponse
    Add-Check 'c03_capture_screenshot_base64' `
        (($null -ne $shot) -and ([string]$shot.format -eq 'png') -and ([int]$shot.width -gt 0) -and ([int]$shot.height -gt 0) -and ([string]$shot.image_base64).Length -gt 1000) `
        ("format={0} width={1} height={2} base64_bytes={3}" -f $shot.format, $shot.width, $shot.height, ([string]$shot.image_base64).Length)

    $savedResponse = Invoke-Curl -Id 'c04_capture_screenshot_save' -Port $GamePort -Json (New-CallBody -Id 34 -Tool 'running_game_capture_screenshot' -Arguments @{ save_path = 'res://mcp011_capture.png' })
    $saved = Get-Payload $savedResponse
    $pngPath = Join-Path $Scratch 'mcp011_capture.png'
    $pngExists = Test-Path $pngPath
    $pngBytes = if ($pngExists) { [IO.File]::ReadAllBytes($pngPath) } else { @() }
    $pngMagic = ($pngBytes.Length -ge 8) -and ($pngBytes[0] -eq 0x89) -and ($pngBytes[1] -eq 0x50) -and ($pngBytes[2] -eq 0x4E) -and ($pngBytes[3] -eq 0x47)
    $pngSha = if ($pngExists) { (Get-FileHash -Algorithm SHA256 -Path $pngPath).Hash.ToLower() } else { '' }
    Write-Host ("[c04] saved png sha256={0} bytes={1}" -f $pngSha, $pngBytes.Length)
    Add-Check 'c04_capture_screenshot_writes_a_real_png' `
        (($null -ne $saved) -and ([string]$saved.saved_path -eq 'res://mcp011_capture.png') -and $pngExists -and ($pngBytes.Length -gt 1000) -and $pngMagic) `
        ("saved_path={0} width={1} height={2} on_disk_bytes={3} png_magic={4} sha256={5}" -f $saved.saved_path, $saved.width, $saved.height, $pngBytes.Length, $pngMagic, $pngSha)

    Add-ErrorCheck -Id 'c05_capture_screenshot_bad_path' -ResponseText (Invoke-Curl -Id 'c05_capture_screenshot_bad_path' -Port $GamePort -Json (New-CallBody -Id 35 -Tool 'running_game_capture_screenshot' -Arguments @{ save_path = 'res://../escape.png' })) -Code -32602 -MessageFragment 'must not walk upwards'

    # The whole point of the phase: the *renderer really ran*, so the frames are
    # pixels and not a repeated placeholder.
    Add-Check 'c06_windowed_renderer_used' ($distinctDigests -and ($pngBytes.Length -gt 1000)) `
        ("three captures produced {0} distinct PNG digests and the saved file is {1} bytes" -f (@($digests | Sort-Object -Unique).Count), $pngBytes.Length)
}

# =============================================================================
#  Main
# =============================================================================

Write-Host '============================================================='
Write-Host (" TASK-011 deferred response channel -- evidence phase '{0}'" -f $Phase)
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host "FATAL: engine binary not found: $Engine"; exit 2 }
New-Item -ItemType Directory -Force -Path $LogRoot, $Evid | Out-Null
Write-Host ("engine sha256: {0}" -f (Get-FileHash -Algorithm SHA256 -Path $Engine).Hash.ToLower())

$userPortPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)

$handle = $null
try {
    Initialize-Scratch
    if ($Phase -eq 'game') {
        $handle = Start-Engine -Arguments @('--headless', '--path', $Scratch, "--mcp-port=$GamePort") -LogName 'game-headless'
    } else {
        # No --headless: the dummy renderer has no texture storage, so a real
        # display server is required for the capture half.
        $handle = Start-Engine -Arguments @('--path', $Scratch, "--mcp-port=$GamePort") -LogName 'game-windowed'
    }
    if (-not (Wait-ForFrames -Port $GamePort -TimeoutMs 180000)) {
        Write-Host 'FATAL: the game endpoint never pumped'
        Write-Host (Get-Content -Raw $handle.Out -ErrorAction SilentlyContinue)
        exit 2
    }
    if ($Phase -eq 'game') {
        Invoke-GamePhase -Handle $handle
    } else {
        Invoke-CapturePhase -Handle $handle
    }
} catch {
    Write-Host ("EXCEPTION: {0}" -f $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
    Add-Check 'phase_completed_without_exception' $false $_.Exception.Message
} finally {
    Stop-Engine -Handle $handle
    $logText = if ($null -ne $handle) { Get-Content -Raw $handle.Out -ErrorAction SilentlyContinue } else { '' }
    Add-Check 'engine_log_has_MCP_ready' ([string]$logText).Contains('[MCP] INFO: MCP server is ready') ("log contains the ready line: {0}" -f ([string]$logText).Contains('[MCP] INFO: MCP server is ready'))
    Show-PortGuard -Before $userPortPidBefore
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
