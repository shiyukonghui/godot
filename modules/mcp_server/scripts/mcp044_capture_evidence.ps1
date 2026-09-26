# =============================================================================
#  mcp044_capture_evidence.ps1 -- TASK-044: the before/after capture (GDR-27).
#
#  One script per phase, because each phase needs a *different kind of process*:
#
#    -Phase editor    windowed editor on 9888 (a real display server, so the
#                     framebuffer exists): the three switch positions, the
#                     existence experiment (changed:true / changed:false), the
#                     three viewports, the monotone byte counter and the
#                     response-latency comparison.
#    -Phase headless  a `--headless` editor on 9888: the `unavailable` verdict
#                     (a line, never a blank picture) and the proof that the
#                     tool call itself is unaffected.
#    -Phase game      a windowed game on 9889: the game endpoint's own chain.
#
#  Port discipline: 9877 belongs to the user's running editor and is never
#  touched (its pid is read before and after and asserted equal); this script
#  only ever starts and kills its own processes on 9888 / 9889.
#
#  Evidence is written under %TEMP%\mcp044-evidence\evidence; every response body
#  is written with `curl.exe -s -o <file>` (never through a PowerShell pipeline,
#  PLAYBOOK section 7.1) and every request body with `ConvertTo-Json` and
#  `Write-McpUtf8NoBom`.
#
#  Paths handed to the engine use forward slashes: the module derives the default
#  capture directory from the trace file with `String::get_base_dir()`, which
#  only knows `/`, so a backslash path would silently fall back to a relative
#  `shots`.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp044_capture_evidence.ps1 -Phase editor
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp044_capture_evidence.ps1 -Phase headless
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp044_capture_evidence.ps1 -Phase game
# =============================================================================

param(
    [ValidateSet('editor', 'headless', 'game', 'diff-image')]
    [string]$Phase = 'editor',
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$UserPort = 9877
$EditorPort = 9888
$GamePort = 9889
$Root = Join-Path $env:TEMP 'mcp044-evidence'
$Evid = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$ProjectPath = Join-Path $Root 'project'

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

$script:Results = New-Object System.Collections.Generic.List[object]

function ConvertTo-McpPath {
    param([string]$Path)
    return ($Path -replace '\\', '/')
}

function Add-Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Results.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ('[{0}] {1}' -f $tag, $Id)
    Write-Host ('       {0}' -f $Evidence)
}

function Get-ListenerPid {
    param([int]$PortNumber)
    $lines = & netstat -ano -p TCP 2>$null
    foreach ($line in $lines) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $PortNumber + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

function Wait-ForPortFree {
    param([int]$PortNumber, [int]$TimeoutMs = 30000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ((Get-ListenerPid -PortNumber $PortNumber) -lt 0) { return $true }
        Start-Sleep -Milliseconds 500
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
    Write-Host ('started pid={0} :: {1}' -f $proc.Id, ($Arguments -join ' '))
    return [pscustomobject]@{ Process = $proc; Out = $out; Err = $err; Name = $LogName }
}

function Stop-Engine {
    param($Handle)
    if ($null -eq $Handle) { return }
    try {
        if (-not $Handle.Process.HasExited) {
            Stop-Process -Id $Handle.Process.Id -Force -ErrorAction SilentlyContinue
        }
    } catch { }
    Start-Sleep -Milliseconds 800
}

function Wait-ForReady {
    param([int]$PortNumber, [int]$TimeoutMs, [string]$Directory)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $requestFile = Join-Path $Directory 'ready-request.json'
    $responseFile = Join-Path $Directory 'ready-response.json'
    Write-McpUtf8NoBom -Path $requestFile -Text '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}'
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path $responseFile) { Remove-Item -Path $responseFile -Force -ErrorAction SilentlyContinue }
        & curl.exe -s -o $responseFile --max-time 10 -X POST -H 'Content-Type: application/json' `
            --data-binary ('@' + $requestFile) ('http://127.0.0.1:{0}/mcp' -f $PortNumber) 2>$null | Out-Null
        if (Test-Path $responseFile) {
            $text = [IO.File]::ReadAllText($responseFile)
            if ($text -match 'protocolVersion') { return $true }
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

function New-CallBody {
    param([int]$Id, [string]$Tool, $Arguments)
    $params = @{ name = $Tool; arguments = $Arguments }
    return (@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = $params } | ConvertTo-Json -Depth 10 -Compress)
}

# One request. The response body lands on disk (never in a pipeline) and the wall
# time around `curl.exe` is the latency the zero-latency check compares.
function Invoke-Mcp {
    param([string]$Id, [int]$PortNumber, [string]$Json, [string]$Directory, [int]$MaxTimeSec = 40)
    $requestFile = Join-Path $Directory ('req-{0}.json' -f $Id)
    $responseFile = Join-Path $Directory ('res-{0}.json' -f $Id)
    Write-McpUtf8NoBom -Path $requestFile -Text $Json
    if (Test-Path $responseFile) { Remove-Item -Path $responseFile -Force -ErrorAction SilentlyContinue }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & curl.exe -s -o $responseFile --max-time $MaxTimeSec -X POST -H 'Content-Type: application/json' `
        --data-binary ('@' + $requestFile) ('http://127.0.0.1:{0}/mcp' -f $PortNumber) 2>$null | Out-Null
    $sw.Stop()
    $text = if (Test-Path $responseFile) { [IO.File]::ReadAllText($responseFile) } else { '' }
    return [pscustomobject]@{ id = $Id; seconds = $sw.Elapsed.TotalSeconds; text = $text; file = $responseFile }
}

function Get-Envelope {
    param([string]$ResponseText)
    if ([string]::IsNullOrEmpty($ResponseText)) { return $null }
    try { return (ConvertFrom-Json $ResponseText) } catch { return $null }
}

# The tool's answer, parsed out of the `content[0].text` envelope (GDR-6).
function Get-Payload {
    param([string]$ResponseText)
    $envelope = Get-Envelope $ResponseText
    if ($null -eq $envelope) { return $null }
    if ($null -eq $envelope.result) { return $null }
    $content = @($envelope.result.content)
    if ($content.Count -eq 0) { return $null }
    try { return (ConvertFrom-Json ([string]$content[0].text)) } catch { return $null }
}

function Get-ErrorCode {
    param([string]$ResponseText)
    $envelope = Get-Envelope $ResponseText
    if ($null -eq $envelope) { return 0 }
    if ($null -eq $envelope.error) { return 0 }
    return [int]$envelope.error.code
}

# Reads a text file that another process is still holding open. The trace
# recorder keeps its handle for the whole run (that is the point of it), and
# `[IO.File]::ReadAllLines` asks for `FileShare.Read` only - so it fails with a
# sharing violation on the very file this evidence is about. `ReadWrite` sharing
# is what an observer of a live log needs.
function Read-TextShared {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object IO.StreamReader($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Close() }
    } finally { $stream.Close() }
}

function Get-TraceLines {
    param([string]$Path)
    $out = New-Object System.Collections.Generic.List[object]
    $text = Read-TextShared -Path $Path
    if ([string]::IsNullOrEmpty($text)) { return $out }
    foreach ($line in ($text -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $out.Add((ConvertFrom-Json $line)) } catch { }
    }
    return $out
}

function Get-CaptureEvents {
    param($TraceLines)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($line in $TraceLines) {
        if (($line.PSObject.Properties.Name -contains 'event') -and ([string]$line.event -eq 'capture')) {
            $out.Add($line)
        }
    }
    return $out
}

function Get-CallLineBySeq {
    param($TraceLines, [int]$Seq)
    foreach ($line in $TraceLines) {
        if (($line.PSObject.Properties.Name -contains 'seq') -and ([int]$line.seq -eq $Seq) -and
            ($line.PSObject.Properties.Name -contains 'method') -and ([string]$line.method -eq 'tools/call')) {
            return $line
        }
    }
    return $null
}

function Get-ShortHash {
    param([string]$Hash)
    if ([string]::IsNullOrEmpty($Hash)) { return '' }
    return $Hash.Substring(0, [Math]::Min(16, $Hash.Length))
}

# The capture line of a call is appended one *rendered frame* after the response,
# so it is not on disk yet when `curl.exe` returns. Reading the trace immediately
# is the one way to make this evidence flaky in the wrong direction (a pass would
# still be a real pass, but a missing line would look like a defect); every read
# below therefore polls until the expected number of capture lines is there.
function Wait-ForCaptureEvents {
    param([string]$Path, [int]$Expected, [int]$TimeoutMs = 60000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $events = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        $events = @(Get-CaptureEvents -TraceLines (Get-TraceLines -Path $Path))
        if ($events.Count -ge $Expected) { return $events }
        Start-Sleep -Milliseconds 500
    }
    return $events
}

function Format-Stats {
    param([double[]]$Values)
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return 'n=0' }
    $mid = [int][Math]::Floor($sorted.Count / 2)
    $median = if ($sorted.Count % 2 -eq 1) { $sorted[$mid] } else { ($sorted[$mid - 1] + $sorted[$mid]) / 2.0 }
    return ('n={0} min={1:N4}s median={2:N4}s max={3:N4}s' -f $sorted.Count, $sorted[0], $median, $sorted[$sorted.Count - 1])
}

function Get-Median {
    param([double[]]$Values)
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return 0.0 }
    $mid = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) { return $sorted[$mid] }
    return ($sorted[$mid - 1] + $sorted[$mid]) / 2.0
}

function Initialize-Scratch {
    New-Item -ItemType Directory -Force -Path $Root, $Evid, $LogRoot | Out-Null
    # A rerun must start from an empty project: the "no file was deleted" and
    # "count the PNGs" checks would otherwise count an earlier run's pictures.
    foreach ($name in @('mcp044_shots', 'mcp044_shots_2d', 'mcp044_shots_3d', 'mcp044_shots_editor', 'mcp044_shots_on_error', 'mcp044_shots_game', 'mcp044_shots_diff_image')) {
        Remove-Item -Path (Join-Path $ProjectPath $name) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path (Join-Path $Root 'shots') -Recurse -Force -ErrorAction SilentlyContinue
    New-McpScratchProject -Path $ProjectPath -Name 'mcp044-capture' -WithMainScene $true -SceneType 'Node2D'
    # The shared helper writes a bare one-node scene; this phase needs something
    # the 2D/3D editor viewports and the running game all show, and something
    # whose colour a single tool call can change.
    $scene = @(
        '[gd_scene format=3]',
        '',
        '[node name="Main" type="Node2D"]',
        '',
        '[node name="ColorRect" type="ColorRect" parent="."]',
        'offset_right = 600.0',
        'offset_bottom = 400.0',
        'color = Color(1, 0, 0, 1)',
        '',
        '[node name="Marker3D" type="Node3D" parent="."]'
    )
    Write-McpUtf8NoBom -Path (Join-Path $ProjectPath 'scenes\main.tscn') -Text (($scene -join "`n") + "`n")
}

# Starts one editor, waits for its endpoint and hands the handle back. The caller
# owns the handle and stops it: the body of every run below talks to the engine.
function Start-EditorRun {
    param([string]$Label, [string[]]$ExtraArguments, [string]$TraceFile)
    $dir = Join-Path $Evid $Label
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Remove-Item -Path $TraceFile -Force -ErrorAction SilentlyContinue
    $arguments = @('-e', '--path', $ProjectPath, ('--mcp-port={0}' -f $EditorPort), ('--mcp-trace={0}' -f (ConvertTo-McpPath $TraceFile)))
    $arguments += $ExtraArguments
    $handle = Start-Engine -Arguments $arguments -LogName ('editor-' + $Label)
    $ready = Wait-ForReady -PortNumber $EditorPort -TimeoutMs $ReadyTimeoutMs -Directory $dir
    Add-Check ('{0}_endpoint_ready' -f $Label) $ready ('editor on {0}, log {1}' -f $EditorPort, $handle.Out)
    return [pscustomobject]@{ Dir = $dir; Handle = $handle; Trace = $TraceFile; Ready = $ready }
}

# =============================================================================
#  Editor phase (windowed: the framebuffer really exists)
# =============================================================================

function Test-CaptureDisabled {
    param($Run)
    $trace = Get-TraceLines -Path $Run.Trace
    $events = Get-CaptureEvents -TraceLines $trace
    $anyCaptureMember = $false
    foreach ($line in $trace) {
        if ($line.PSObject.Properties.Name -contains 'capture') { $anyCaptureMember = $true }
    }
    Add-Check 'switch_off_writes_no_capture_line' (($events.Count -eq 0) -and (-not $anyCaptureMember)) `
        ('trace lines={0} capture events={1} call lines carrying a capture member={2} (file={3})' -f $trace.Count, $events.Count, $anyCaptureMember, $Run.Trace)
    $shots = @(Get-ChildItem -Path $ProjectPath -Recurse -Filter '*.png' -ErrorAction SilentlyContinue)
    Add-Check 'switch_off_writes_no_png' ($shots.Count -eq 0) ('png files under the project: {0}' -f $shots.Count)
    Add-Check 'switch_off_startup_log_says_off' `
        ((Select-String -Path $Run.Handle.Out -Pattern '\[MCP\] capture=off' -Quiet) -eq $true) `
        ('log={0}' -f $Run.Handle.Out)
}

function Test-ThreeViewports {
    # `editor` / `2d` / `3d` are three process-level settings, so each one is its
    # own run. Each must produce a picture with a real size, and the three must
    # not be the same bytes (which is what "all three answered the same blank
    # frame" would look like).
    $hashes = @{}
    $sizes = @{}
    $index = 0
    foreach ($viewport in @('2d', '3d', 'editor')) {
        $label = ('viewport-' + $viewport)
        $trace = Join-Path $Root ('trace-{0}.jsonl' -f $label)
        $shotsDir = ('res://mcp044_shots_' + $viewport)
        $run = Start-EditorRun -Label $label -ExtraArguments @(
            '--mcp-capture=every_call', ('--mcp-capture-dir=' + $shotsDir), ('--mcp-capture-viewport=' + $viewport)
        ) -TraceFile $trace
        try {
            if (-not $run.Ready) { continue }
            $index++
            # A scene has to be open before the editor viewports have a real
            # geometry to show (without one the 2D editor view is a 2x2
            # placeholder and a "reasonable size" check would be meaningless).
            Invoke-Mcp -Id ('v_open_{0}' -f $viewport) -PortNumber $EditorPort -Directory $run.Dir `
                -Json (New-CallBody -Id (1090 + $index) -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }) | Out-Null
            Start-Sleep -Milliseconds 1500
            $call = Invoke-Mcp -Id ('v_{0}' -f $viewport) -PortNumber $EditorPort -Directory $run.Dir `
                -Json (New-CallBody -Id (1100 + $index) -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
            $payload = Get-Payload $call.text
            $ok = ($null -ne $payload) -and ($null -ne $payload.tree) -and ($null -ne $payload.scene_path)
            Add-Check ('viewport_{0}_call_ok' -f $viewport) $ok ('answer scene_path={0} root_name={1}' -f $payload.scene_path, $payload.tree.name)

            $events = @(Wait-ForCaptureEvents -Path $trace -Expected 2)
            $done = @($events | Where-Object { [string]$_.status -eq 'done' })
            if ($done.Count -lt 2) {
                Add-Check ('viewport_{0}_capture_done' -f $viewport) $false ('capture events={0} done={1} (expected the open_scene call and the read)' -f @($events).Count, $done.Count)
                continue
            }
            Add-Check ('viewport_{0}_capture_done' -f $viewport) $true ('capture events={0} done={1}' -f @($events).Count, $done.Count)
            $event = $done[$done.Count - 1]

            $beforePath = [string]$event.before.path
            $localBefore = Join-Path $ProjectPath ($beforePath -replace '^res://', '' -replace '/', '\')
            $exists = Test-Path $localBefore
            $bytes = if ($exists) { (Get-Item $localBefore).Length } else { 0 }
            $sha = if ($exists) { (Get-FileHash -Algorithm SHA256 -Path $localBefore).Hash } else { '' }
            $width = [int]$event.before.width
            $height = [int]$event.before.height
            $afterSha = [string]$event.after.sha256
            Add-Check ('viewport_{0}_picture_is_real' -f $viewport) `
                ($exists -and $bytes -gt 1024 -and $width -ge 100 -and $height -ge 100 -and $afterSha.Length -eq 64) `
                ('path={0} bytes={1} {2}x{3} sha256={4} after_sha256={5}' -f $beforePath, $bytes, $width, $height, (Get-ShortHash $sha), (Get-ShortHash $afterSha))
            $hashes[$viewport] = $sha
            $sizes[$viewport] = ('{0}x{1}' -f $width, $height)
        } finally {
            Stop-Engine -Handle $run.Handle
            Wait-ForPortFree -PortNumber $EditorPort | Out-Null
        }
    }
    $distinct = @($hashes.Values | Where-Object { -not [string]::IsNullOrEmpty($_) } | Sort-Object -Unique).Count
    Add-Check 'three_viewports_are_not_the_same_frame' ($distinct -ge 2) `
        ('distinct sha256={0} sizes: 2d={1} 3d={2} editor={3}' -f $distinct, $sizes['2d'], $sizes['3d'], $sizes['editor'])
}

function Invoke-EditorPhase {
    Write-Host '=== editor phase: off / every_call / on_error / viewports / latency ==='

    # ---- run 1: capture off (the default). This is also the latency baseline.
    $offTrace = Join-Path $Root 'trace-off.jsonl'
    $offRun = Start-EditorRun -Label 'off' -ExtraArguments @('--mcp-capture=off') -TraceFile $offTrace
    $offLatency = @()
    if ($offRun.Ready) {
        for ($i = 1; $i -le 5; $i++) {
            $r = Invoke-Mcp -Id ('off_lat_{0}' -f $i) -PortNumber $EditorPort -Directory $offRun.Dir `
                -Json (New-CallBody -Id (2100 + $i) -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
            $offLatency += $r.seconds
        }
        Test-CaptureDisabled -Run $offRun
    }
    Stop-Engine -Handle $offRun.Handle
    Wait-ForPortFree -PortNumber $EditorPort | Out-Null

    # ---- run 2: every_call, viewport 2d. The existence experiment lives here.
    $trace = Join-Path $Root 'trace-every-call-2d.jsonl'
    $run = Start-EditorRun -Label 'every-call-2d' -ExtraArguments @(
        '--mcp-capture=every_call', '--mcp-capture-dir=res://mcp044_shots', '--mcp-capture-viewport=2d'
    ) -TraceFile $trace
    $onLatency = @()
    $onLatencySpaced = @()
    $dir = $run.Dir
    try {
        if ($run.Ready) {
            Add-Check 'every_call_startup_log_names_dir_and_mode' `
                (((Select-String -Path $run.Handle.Out -SimpleMatch '[MCP] capture enabled: mode=every_call viewport=2d dir=res://mcp044_shots diff_image=false' -Quiet) -eq $true) -and
                 ((Select-String -Path $run.Handle.Out -SimpleMatch 'nothing is ever deleted' -Quiet) -eq $true)) `
                ('log={0}' -f $run.Handle.Out)

            $open = Invoke-Mcp -Id 'open_scene' -PortNumber $EditorPort -Directory $dir `
                -Json (New-CallBody -Id 2201 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' })
            Add-Check 'editor_scene_opened' ((Get-ErrorCode $open.text) -eq 0) ('open_scene error_code={0}' -f (Get-ErrorCode $open.text))

            $read = Invoke-Mcp -Id 'read_tree' -PortNumber $EditorPort -Directory $dir `
                -Json (New-CallBody -Id 2202 -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
            Add-Check 'editor_read_call_ok' ((Get-ErrorCode $read.text) -eq 0) ('get_scene_tree error_code={0}' -f (Get-ErrorCode $read.text))

            # **The existence experiment**: the same call twice. The first changes
            # the picture, the second reports exactly the same success and does
            # not.
            $mutateJson = New-CallBody -Id 2203 -Tool 'editor_set_node_property' -Arguments @{ path = 'ColorRect'; property = 'color'; value = '#00ff00' }
            $mutateAgainJson = New-CallBody -Id 2204 -Tool 'editor_set_node_property' -Arguments @{ path = 'ColorRect'; property = 'color'; value = '#00ff00' }
            $mutate1 = Invoke-Mcp -Id 'mutate_first' -PortNumber $EditorPort -Directory $dir -Json $mutateJson
            $mutate2 = Invoke-Mcp -Id 'mutate_again' -PortNumber $EditorPort -Directory $dir -Json $mutateAgainJson
            Add-Check 'editor_mutations_reported_success' `
                (((Get-ErrorCode $mutate1.text) -eq 0) -and ((Get-ErrorCode $mutate2.text) -eq 0)) `
                ('first error_code={0}, second error_code={1} (both must be a reported success)' -f (Get-ErrorCode $mutate1.text), (Get-ErrorCode $mutate2.text))

            $failed = Invoke-Mcp -Id 'mutate_missing_property' -PortNumber $EditorPort -Directory $dir `
                -Json (New-CallBody -Id 2205 -Tool 'editor_set_node_property' -Arguments @{ path = 'ColorRect'; property = 'no_such_property_xyz'; value = 1 })
            Add-Check 'editor_failing_call_is_refused' ((Get-ErrorCode $failed.text) -eq -32001) `
                ('error_code={0}' -f (Get-ErrorCode $failed.text))

            for ($i = 1; $i -le 5; $i++) {
                $r = Invoke-Mcp -Id ('on_lat_{0}' -f $i) -PortNumber $EditorPort -Directory $dir `
                    -Json (New-CallBody -Id (2300 + $i) -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
                $onLatency += $r.seconds
            }
            # The same probe again, but with an idle gap before each one. The
            # capture's post-response work (two PNG encodes and a 5.3M pixel
            # comparison) keeps the main thread busy *after* the answer, so a
            # request that arrives while it is busy waits for the next frame -
            # which a client-observed round trip sees, and the server-side
            # `duration_ms` of the call does not.
            for ($i = 1; $i -le 5; $i++) {
                Start-Sleep -Milliseconds 2500
                $r = Invoke-Mcp -Id ('on_lat_spaced_{0}' -f $i) -PortNumber $EditorPort -Directory $dir `
                    -Json (New-CallBody -Id (2320 + $i) -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
                $onLatencySpaced += $r.seconds
            }

            $events = @(Wait-ForCaptureEvents -Path $trace -Expected 15)
            $traceLines = Get-TraceLines -Path $trace
            $done = @($events | Where-Object { [string]$_.status -eq 'done' })
            Add-Check 'every_call_captures_every_call' ($done.Count -eq 15) `
                ('tools/call requests=15 capture events={0} done={1} (the line of the last call arrives one rendered frame after its response; this read polls for it)' -f $events.Count, $done.Count)

            # Which capture belongs to which call: the `seq` joins them, and the
            # call line's recorded arguments say what the call was.
            $mutateEvents = New-Object System.Collections.Generic.List[object]
            $failedEvent = $null
            foreach ($event in $done) {
                $callLine = Get-CallLineBySeq -TraceLines $traceLines -Seq ([int]$event.seq)
                if ($null -eq $callLine) { continue }
                $args = [string]$callLine.args
                if ($args -match 'no_such_property_xyz') { $failedEvent = $event }
                elseif ($args -match '#00ff00') { $mutateEvents.Add($event) }
            }
            $mutate1Event = if ($mutateEvents.Count -ge 1) { $mutateEvents[0] } else { $null }
            $mutate2Event = if ($mutateEvents.Count -ge 2) { $mutateEvents[1] } else { $null }

            Add-Check 'existence_proof_a_real_change_is_changed_true' `
                (($null -ne $mutate1Event) -and ([bool]$mutate1Event.changed) -and ([double]$mutate1Event.changed_pixel_ratio -gt 0)) `
                ('first "#00ff00" write: seq={0} changed={1} ratio={2} changed_pixels={3} of {4}' -f $mutate1Event.seq, $mutate1Event.changed, $mutate1Event.changed_pixel_ratio, $mutate1Event.changed_pixels, $mutate1Event.total_pixels)
            Add-Check 'existence_proof_a_no_op_success_is_changed_false' `
                (($null -ne $mutate2Event) -and (-not [bool]$mutate2Event.changed) -and ([double]$mutate2Event.changed_pixel_ratio -eq 0)) `
                ('second "#00ff00" write (identical arguments, still an error_code=0 success): seq={0} changed={1} ratio={2} changed_pixels={3}' -f $mutate2Event.seq, $mutate2Event.changed, $mutate2Event.changed_pixel_ratio, $mutate2Event.changed_pixels)
            Add-Check 'existence_proof_the_failing_call_is_also_measured' `
                (($null -ne $failedEvent) -and (-not [bool]$failedEvent.changed)) `
                ('the -32001 call: seq={0} changed={1} ratio={2} (a capture is taken whether the call succeeded or not)' -f $failedEvent.seq, $failedEvent.changed, $failedEvent.changed_pixel_ratio)

            # The capture line carries the same `seq` as the call line it belongs
            # to, and that call line already says a capture is coming.
            $joinOk = $true
            $joinEvidence = ''
            foreach ($event in $done) {
                $callLine = Get-CallLineBySeq -TraceLines $traceLines -Seq ([int]$event.seq)
                if ($null -eq $callLine) {
                    $joinOk = $false
                    $joinEvidence += ('seq={0}:NO_CALL_LINE ' -f $event.seq)
                    continue
                }
                if (-not ($callLine.PSObject.Properties.Name -contains 'capture')) {
                    $joinOk = $false
                    $joinEvidence += ('seq={0}:NO_CAPTURE_MEMBER ' -f $event.seq)
                } elseif ([string]$callLine.capture.status -ne 'pending') {
                    $joinOk = $false
                    $joinEvidence += ('seq={0}:status={1} ' -f $event.seq, $callLine.capture.status)
                }
            }
            Add-Check 'capture_line_shares_the_call_seq_and_the_call_line_announces_it' $joinOk `
                ('{0}capture lines checked={1}' -f $joinEvidence, $done.Count)

            # `frames_waited` is the self-certification of the one-rendered-frame
            # rule.
            $framesOk = $true
            $framesEvidence = ''
            foreach ($event in $done) {
                if ([int64]$event.frames_waited -lt 1) { $framesOk = $false }
                $framesEvidence += ('seq={0}:{1} ' -f $event.seq, $event.frames_waited)
            }
            Add-Check 'after_frame_waited_at_least_one_rendered_frame' $framesOk $framesEvidence

            # `total_bytes` is cumulative and strictly increasing, and nothing is
            # ever deleted.
            $monotone = $true
            $previous = -1
            foreach ($event in $done) {
                $now = [int64]$event.total_bytes
                if ($now -le $previous) { $monotone = $false }
                $previous = $now
            }
            Add-Check 'total_bytes_is_monotone' ($monotone -and $previous -gt 0) `
                ('last total_bytes={0} over {1} captures' -f $previous, $done.Count)

            $shotsDirLocal = Join-Path $ProjectPath 'mcp044_shots'
            $pngs = @(Get-ChildItem -Path $shotsDirLocal -Filter '*.png' -ErrorAction SilentlyContinue)
            Add-Check 'no_capture_file_was_deleted' ($pngs.Count -eq (2 * $done.Count)) `
                ('expected {0} PNGs (2 per done capture), found {1} in {2}' -f (2 * $done.Count), $pngs.Count, $shotsDirLocal)

            # The module's own diff tool reads the two PNGs the capture wrote,
            # which proves they are a real pair of a real geometry.
            if ($null -ne $mutate1Event) {
                $diffCall = Invoke-Mcp -Id 'diff_of_the_change' -PortNumber $EditorPort -Directory $dir `
                    -Json (New-CallBody -Id 2206 -Tool 'editor_analyze_screenshot_diff' -Arguments @{
                        image_a = [string]$mutate1Event.before.path
                        image_b = [string]$mutate1Event.after.path
                    })
                $diffPayload = Get-Payload $diffCall.text
                $diffOk = ($null -ne $diffPayload) -and ([int]$diffPayload.changed_pixels -gt 0) -and `
                    ([int]$diffPayload.total_pixels -eq ([int]$mutate1Event.before.width * [int]$mutate1Event.before.height))
                Add-Check 'diff_tool_agrees_with_the_capture_verdict' $diffOk `
                    ('identical={0} changed_pixels={1} total_pixels={2} ({3}x{4})' -f $diffPayload.identical, $diffPayload.changed_pixels, $diffPayload.total_pixels, $mutate1Event.before.width, $mutate1Event.before.height)
            }
        }
    } finally {
        Stop-Engine -Handle $run.Handle
        Wait-ForPortFree -PortNumber $EditorPort | Out-Null
    }

    # ---- run 3: on_error. Only the failing call is captured.
    $oeTrace = Join-Path $Root 'trace-on-error.jsonl'
    $oeRun = Start-EditorRun -Label 'on-error' -ExtraArguments @(
        '--mcp-capture=on_error', '--mcp-capture-dir=res://mcp044_shots_on_error', '--mcp-capture-viewport=2d'
    ) -TraceFile $oeTrace
    try {
        if ($oeRun.Ready) {
            # The scene has to be open first, or `editor_get_scene_tree` answers
            # its own `-32000` and stops being the *successful* call this
            # experiment needs. The opening call is a capture too: the counts
            # below are of the two calls this check is about.
            Invoke-Mcp -Id 'oe_open' -PortNumber $EditorPort -Directory $oeRun.Dir `
                -Json (New-CallBody -Id 2400 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }) | Out-Null
            Start-Sleep -Milliseconds 1500
            $ok = Invoke-Mcp -Id 'oe_ok' -PortNumber $EditorPort -Directory $oeRun.Dir `
                -Json (New-CallBody -Id 2401 -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
            $bad = Invoke-Mcp -Id 'oe_bad' -PortNumber $EditorPort -Directory $oeRun.Dir `
                -Json (New-CallBody -Id 2402 -Tool 'editor_set_node_property' -Arguments @{ path = 'ColorRect'; property = 'no_such_property_xyz'; value = 1 })
            Add-Check 'on_error_successful_call_really_succeeded' ((Get-ErrorCode $ok.text) -eq 0) `
                ('editor_get_scene_tree error_code={0} (it has to be a success for "only failures are captured" to mean anything)' -f (Get-ErrorCode $ok.text))
            Add-Check 'on_error_failing_call_really_failed' ((Get-ErrorCode $bad.text) -eq -32001) `
                ('editor_set_node_property error_code={0}' -f (Get-ErrorCode $bad.text))

            # `@(...)` matters: PowerShell unrolls a one-element array on return,
            # so a single capture line would arrive as a bare object with no
            # `.Count` at all.
            $events = @(Wait-ForCaptureEvents -Path $oeTrace -Expected 1)
            $traceLines = Get-TraceLines -Path $oeTrace
            $callCount = 0
            $withCaptureMember = 0
            $successCallHasCapture = $false
            foreach ($line in $traceLines) {
                if (($line.PSObject.Properties.Name -contains 'method') -and ([string]$line.method -eq 'tools/call')) {
                    $callCount++
                    if ($line.PSObject.Properties.Name -contains 'capture') {
                        $withCaptureMember++
                        if ([string]$line.tool -eq 'editor_get_scene_tree' -and [int]$line.id -eq 2401) { $successCallHasCapture = $true }
                    }
                }
            }
            Add-Check 'on_error_captures_only_the_failed_call' (($events.Count -eq 1) -and ($callCount -eq 3) -and ($withCaptureMember -eq 1) -and (-not $successCallHasCapture)) `
                ('tools/call lines={0} (open_scene + the successful read + the failing write), call lines carrying a capture member={1}, the successful read carries one={2}, capture events={3}' -f $callCount, $withCaptureMember, $successCallHasCapture, $events.Count)
            if ($events.Count -ge 1) {
                Add-Check 'on_error_event_is_a_real_pair' (([string]$events[0].status -eq 'done') -and ([int]$events[0].seq -eq 4)) `
                    ('the only capture line: status={0} seq={1} changed={2} before={3}' -f $events[0].status, $events[0].seq, $events[0].changed, $events[0].before.path)
            }
        }
    } finally {
        Stop-Engine -Handle $oeRun.Handle
        Wait-ForPortFree -PortNumber $EditorPort | Out-Null
    }

    Test-ThreeViewports

    # ---- latency: the same probes, off vs every_call.
    #
    # Two different clocks have to be told apart, and the acceptance criterion
    # ("no systematic increase in the response") is about the first one:
    #
    #   * the *server side* `duration_ms` of the call (request parsed -> response
    #     produced). This is the only place the capture adds work before the
    #     answer, and that work is exactly one framebuffer image copy.
    #   * the *client observed* round trip of the next request, which also waits
    #     while the previous call's post-response work (two PNG encodes and a
    #     2978x1793 pixel comparison) keeps the main thread busy.
    $offDurations = @()
    foreach ($line in (Get-TraceLines -Path $offTrace)) {
        if (($line.PSObject.Properties.Name -contains 'method') -and ([string]$line.method -eq 'tools/call') -and ([string]$line.tool -eq 'editor_get_scene_tree')) {
            $offDurations += [double]$line.duration_ms
        }
    }
    $onDurations = @()
    if ($null -ne $run -and $run.Ready -and (Test-Path $trace)) {
        foreach ($line in (Get-TraceLines -Path $trace)) {
            if (($line.PSObject.Properties.Name -contains 'method') -and ([string]$line.method -eq 'tools/call') -and ([string]$line.tool -eq 'editor_get_scene_tree')) {
                $onDurations += [double]$line.duration_ms
            }
        }
    }
    $offMedian = Get-Median $offDurations
    $onMedian = Get-Median $onDurations
    Add-Check 'zero_latency_the_response_path_adds_only_the_one_copy' `
        (($offDurations.Count -ge 5) -and ($onDurations.Count -ge 5) -and (($onMedian - $offMedian) -le 50.0)) `
        ('server side `duration_ms` of the same editor_get_scene_tree call -- off: {0} || every_call: {1} || delta_median={2:N1} ms (the single framebuffer copy, taken before the tool runs)' -f (Format-Stats $offDurations), (Format-Stats $onDurations), ($onMedian - $offMedian))
    Add-Check 'zero_latency_client_round_trip' `
        (($offLatency.Count -eq 5) -and ($onLatency.Count -eq 5) -and ($onLatencySpaced.Count -eq 5)) `
        ('curl round trip -- off: {0} || every_call (back to back): {1} || every_call (2.5 s apart): {2} || the back-to-back figure includes waiting for the previous call''s post-response work, which is what the spaced figure removes' -f (Format-Stats $offLatency), (Format-Stats $onLatency), (Format-Stats $onLatencySpaced))
}

# =============================================================================
#  Headless phase: unavailable, never silent, never a blank picture
# =============================================================================

function Invoke-HeadlessPhase {
    Write-Host '=== headless phase: unavailable verdict, tool calls unaffected ==='
    $dir = Join-Path $Evid 'headless'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $trace = Join-Path $Root 'trace-headless.jsonl'
    $traceDir = Split-Path -Parent $trace
    Remove-Item -Path $trace -Force -ErrorAction SilentlyContinue
    # No `--mcp-capture-dir`: the default has to be the trace file's `shots/`
    # sibling, which is what the startup line is checked against.
    $defaultShots = Join-Path $traceDir 'shots'
    Remove-Item -Path $defaultShots -Recurse -Force -ErrorAction SilentlyContinue

    $handle = Start-Engine -Arguments @(
        '--headless', '-e', '--path', $ProjectPath, ('--mcp-port={0}' -f $EditorPort),
        ('--mcp-trace={0}' -f (ConvertTo-McpPath $trace)), '--mcp-capture=every_call'
    ) -LogName 'editor-headless-capture'
    try {
        $ready = Wait-ForReady -PortNumber $EditorPort -TimeoutMs $ReadyTimeoutMs -Directory $dir
        Add-Check 'headless_endpoint_ready' $ready ('editor on {0}' -f $EditorPort)
        if (-not $ready) { return }

        $expectedDir = ConvertTo-McpPath $defaultShots
        Add-Check 'headless_startup_log_names_the_default_dir' `
            ((Select-String -Path $handle.Out -SimpleMatch ('[MCP] capture enabled: mode=every_call viewport=editor dir=' + $expectedDir) -Quiet) -eq $true) `
            ('expected dir={0} in {1}' -f $expectedDir, $handle.Out)

        $read = Invoke-Mcp -Id 'hl_read' -PortNumber $EditorPort -Directory $dir `
            -Json (New-CallBody -Id 3101 -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
        $bad = Invoke-Mcp -Id 'hl_bad' -PortNumber $EditorPort -Directory $dir `
            -Json (New-CallBody -Id 3102 -Tool 'editor_set_node_property' -Arguments @{ path = 'ColorRect'; property = 'no_such_property_xyz'; value = 1 })
        # A tool call that *needs* the framebuffer answers its own -32000, exactly
        # as it did before this task: capture never rewrites a response.
        $shot = Invoke-Mcp -Id 'hl_capture_screenshot' -PortNumber $EditorPort -Directory $dir `
            -Json (New-CallBody -Id 3103 -Tool 'editor_capture_screenshot' -Arguments @{})
        Add-Check 'headless_tool_calls_still_answer' `
            (((Get-ErrorCode $read.text) -eq 0) -and ((Get-ErrorCode $bad.text) -eq -32001)) `
            ('get_scene_tree error_code={0}, set_node_property error_code={1}' -f (Get-ErrorCode $read.text), (Get-ErrorCode $bad.text))
        Add-Check 'headless_capture_tool_still_refuses_with_32000' ((Get-ErrorCode $shot.text) -eq -32000) `
            ('editor_capture_screenshot error_code={0}' -f (Get-ErrorCode $shot.text))

        $expectedReason = 'headless display server ' + [char]0x6CA1 + [char]0x6709 + [char]0x7EB9 + [char]0x7406 + [char]0x5B58 + [char]0x50A8
        # TASK-046: every other phase of this script waits for its capture lines
        # (lines 363 / 470 / 595 / 770 / 826); this one read the trace the instant
        # the third response came back, and a capture line is appended one
        # *frame* later by design (GDR-27 point 4). On a fast machine that reads
        # only 2 of the 3 - measured while re-running this phase for TASK-046:
        # `capture events=2 statuses=[unavailable,unavailable]` with both checks
        # red, while the same trace already carried **all three** `unavailable`
        # lines with the exact expected reason. Waiting asserts what the check
        # always meant to assert; it cannot make a wrong trace pass.
        $events = @(Wait-ForCaptureEvents -Path $trace -Expected 3)
        $allUnavailable = ($events.Count -eq 3)
        $reasonOk = ($events.Count -eq 3)
        foreach ($event in $events) {
            if ([string]$event.status -ne 'unavailable') { $allUnavailable = $false }
            if ([string]$event.reason -ne $expectedReason) { $reasonOk = $false }
            if ($null -ne $event.before) { $reasonOk = $false }
            if ($null -ne $event.after) { $reasonOk = $false }
        }
        Add-Check 'headless_says_unavailable_for_every_call' $allUnavailable `
            ('capture events={0} statuses=[{1}]' -f $events.Count, (($events | ForEach-Object { [string]$_.status }) -join ','))
        $reasonEvidence = if ($events.Count -ge 1) { [string]$events[0].reason } else { '(no event)' }
        Add-Check 'headless_carries_the_reason_and_no_picture_reference' $reasonOk `
            ('reason="{0}" before={1} after={2}' -f $reasonEvidence, $(if ($events.Count -ge 1) { $events[0].before } else { 'n/a' }), $(if ($events.Count -ge 1) { $events[0].after } else { 'n/a' }))
        # The configured directory itself is created at startup (GDR-27: "create
        # the directory if it is missing"), so the check is what it holds: a
        # headless process must not leave a picture in it - not a blank one, not
        # an empty one.
        $shotFiles = @(Get-ChildItem -Path $defaultShots -Recurse -File -ErrorAction SilentlyContinue)
        Add-Check 'headless_writes_no_blank_picture' ($shotFiles.Count -eq 0) `
            ('files under {0}: {1} (the directory exists from the startup `make_dir_recursive`, and stays empty)' -f $defaultShots, $shotFiles.Count)
    } finally {
        Stop-Engine -Handle $handle
        Wait-ForPortFree -PortNumber $EditorPort | Out-Null
    }
}

# =============================================================================
#  Game phase: the second endpoint
# =============================================================================

function Invoke-GamePhase {
    Write-Host '=== game phase: windowed game on 9889 ==='
    $dir = Join-Path $Evid 'game'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $trace = Join-Path $Root 'trace-game.jsonl'
    Remove-Item -Path $trace -Force -ErrorAction SilentlyContinue

    $handle = Start-Engine -Arguments @(
        '--path', $ProjectPath, ('--mcp-port={0}' -f $GamePort),
        ('--mcp-trace={0}' -f (ConvertTo-McpPath $trace)), '--mcp-capture=every_call',
        '--mcp-capture-dir=res://mcp044_shots_game', '--mcp-capture-viewport=3d'
    ) -LogName 'game-windowed-capture'
    try {
        $ready = Wait-ForReady -PortNumber $GamePort -TimeoutMs $ReadyTimeoutMs -Directory $dir
        Add-Check 'game_endpoint_ready' $ready ('game on {0} (a windowed process, so the framebuffer exists)' -f $GamePort)
        if (-not $ready) { return }

        Add-Check 'game_viewport_name_is_game' `
            ((Select-String -Path $handle.Out -SimpleMatch '[MCP] capture enabled: mode=every_call viewport=game dir=res://mcp044_shots_game' -Quiet) -eq $true) `
            ('log={0} (a game process has one window; the editor viewport setting does not apply)' -f $handle.Out)

        $read = Invoke-Mcp -Id 'game_read' -PortNumber $GamePort -Directory $dir `
            -Json (New-CallBody -Id 4101 -Tool 'running_game_get_scene_tree' -Arguments @{ max_depth = 2 })
        Add-Check 'game_read_call_ok' ((Get-ErrorCode $read.text) -eq 0) ('error_code={0}' -f (Get-ErrorCode $read.text))

        # The chain: a read (no change), then a colour change, then the same
        # change again (reported as a success, and the screen does not move).
        $mutateJson = New-CallBody -Id 4102 -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'ColorRect'; property = 'color'; value = '#0000ff' }
        $mutateAgainJson = New-CallBody -Id 4103 -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'ColorRect'; property = 'color'; value = '#0000ff' }
        $m1 = Invoke-Mcp -Id 'game_mutate_first' -PortNumber $GamePort -Directory $dir -Json $mutateJson
        $m2 = Invoke-Mcp -Id 'game_mutate_again' -PortNumber $GamePort -Directory $dir -Json $mutateAgainJson
        Add-Check 'game_mutations_reported_success' `
            (((Get-ErrorCode $m1.text) -eq 0) -and ((Get-ErrorCode $m2.text) -eq 0)) `
            ('first error_code={0}, second error_code={1}' -f (Get-ErrorCode $m1.text), (Get-ErrorCode $m2.text))

        $events = @(Wait-ForCaptureEvents -Path $trace -Expected 3)
        $traceLines = Get-TraceLines -Path $trace
        $done = @($events | Where-Object { [string]$_.status -eq 'done' })
        Add-Check 'game_capture_produced_a_verdict_per_call' ($done.Count -eq 3) `
            ('tools/call=3 (read + two identical writes) capture events={0} done={1}' -f $events.Count, $done.Count)

        $mutateEvents = New-Object System.Collections.Generic.List[object]
        foreach ($event in $done) {
            $callLine = Get-CallLineBySeq -TraceLines $traceLines -Seq ([int]$event.seq)
            if ($null -eq $callLine) { continue }
            if ([string]$callLine.args -match '#0000ff') { $mutateEvents.Add($event) }
        }
        $first = if ($mutateEvents.Count -ge 1) { $mutateEvents[0] } else { $null }
        $second = if ($mutateEvents.Count -ge 2) { $mutateEvents[1] } else { $null }
        Add-Check 'game_change_detected' (($null -ne $first) -and ([bool]$first.changed) -and ([double]$first.changed_pixel_ratio -gt 0)) `
            ('first write: seq={0} changed={1} ratio={2} changed_pixels={3} of {4}' -f $first.seq, $first.changed, $first.changed_pixel_ratio, $first.changed_pixels, $first.total_pixels)
        Add-Check 'game_no_op_detected' (($null -ne $second) -and (-not [bool]$second.changed)) `
            ('second identical write (still an error_code=0 success): seq={0} changed={1} ratio={2}' -f $second.seq, $second.changed, $second.changed_pixel_ratio)

        $gameShots = Join-Path $ProjectPath 'mcp044_shots_game'
        $pngs = @(Get-ChildItem -Path $gameShots -Filter '*.png' -ErrorAction SilentlyContinue)
        Add-Check 'game_pngs_written' ($pngs.Count -eq (2 * $done.Count)) `
            ('expected {0} PNGs, found {1} in {2}' -f (2 * $done.Count), $pngs.Count, $gameShots)
    } finally {
        Stop-Engine -Handle $handle
        Wait-ForPortFree -PortNumber $GamePort | Out-Null
    }
}

# =============================================================================
#  Diff-image phase: `--mcp-capture-diff-image=on` (off by default)
# =============================================================================

function Invoke-DiffImagePhase {
    Write-Host '=== diff-image phase: the difference picture is opt-in ==='
    $dir = Join-Path $Evid 'diff-image'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $trace = Join-Path $Root 'trace-diff-image.jsonl'
    $shotsDir = 'res://mcp044_shots_diff_image'
    Remove-Item -Path (Join-Path $ProjectPath 'mcp044_shots_diff_image') -Recurse -Force -ErrorAction SilentlyContinue

    $run = Start-EditorRun -Label 'diff-image' -ExtraArguments @(
        '--mcp-capture=every_call', ('--mcp-capture-dir=' + $shotsDir), '--mcp-capture-viewport=2d', '--mcp-capture-diff-image=on'
    ) -TraceFile $trace
    try {
        if (-not $run.Ready) { return }
        Add-Check 'diff_image_startup_log_says_true' `
            ((Select-String -Path $run.Handle.Out -SimpleMatch '[MCP] capture enabled: mode=every_call viewport=2d dir=res://mcp044_shots_diff_image diff_image=true' -Quiet) -eq $true) `
            ('log={0}' -f $run.Handle.Out)

        Invoke-Mcp -Id 'di_open' -PortNumber $EditorPort -Directory $run.Dir `
            -Json (New-CallBody -Id 5100 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }) | Out-Null
        Start-Sleep -Milliseconds 1500
        Invoke-Mcp -Id 'di_mutate' -PortNumber $EditorPort -Directory $run.Dir `
            -Json (New-CallBody -Id 5101 -Tool 'editor_set_node_property' -Arguments @{ path = 'ColorRect'; property = 'color'; value = '#ffff00' }) | Out-Null

        $events = @(Wait-ForCaptureEvents -Path $trace -Expected 2)
        $mutateEvent = $null
        foreach ($event in $events) {
            $callLine = Get-CallLineBySeq -TraceLines (Get-TraceLines -Path $trace) -Seq ([int]$event.seq)
            if ($null -ne $callLine -and ([string]$callLine.args -match '#ffff00')) { $mutateEvent = $event }
        }
        $ok = ($null -ne $mutateEvent) -and ([bool]$mutateEvent.changed)
        $diffPath = ''
        $diffBytes = 0
        if ($ok) {
            $diffPath = [string]$mutateEvent.diff.path
            $local = Join-Path $ProjectPath ($diffPath -replace '^res://', '' -replace '/', '\')
            if (Test-Path $local) { $diffBytes = (Get-Item $local).Length }
        }
        Add-Check 'diff_image_written_when_asked_for' ($ok -and $diffBytes -gt 1024 -and ([string]$mutateEvent.diff.sha256).Length -eq 64) `
            ('changed={0} ratio={1} diff.path={2} diff.bytes={3} on_disk={4}' -f $mutateEvent.changed, $mutateEvent.changed_pixel_ratio, $diffPath, $mutateEvent.diff.bytes, $diffBytes)

        # The other two pictures of the same capture are still there, and the
        # difference picture is a third file - not a replacement.
        $beforeLocal = Join-Path $ProjectPath (([string]$mutateEvent.before.path) -replace '^res://', '' -replace '/', '\')
        $afterLocal = Join-Path $ProjectPath (([string]$mutateEvent.after.path) -replace '^res://', '' -replace '/', '\')
        Add-Check 'diff_image_is_an_extra_file' ((Test-Path $beforeLocal) -and (Test-Path $afterLocal)) `
            ('before={0} after={1} diff={2}' -f (Test-Path $beforeLocal), (Test-Path $afterLocal), $diffPath)
    } finally {
        Stop-Engine -Handle $run.Handle
        Wait-ForPortFree -PortNumber $EditorPort | Out-Null
    }
}

# =============================================================================
#  Main
# =============================================================================
Write-Host '============================================================='
Write-Host (' TASK-044 capture evidence -- phase {0}' -f $Phase)
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host ('FATAL: engine binary not found: {0}' -f $Engine); exit 2 }
New-Item -ItemType Directory -Force -Path $Root, $Evid, $LogRoot | Out-Null
Write-Host ('engine: {0}' -f $Engine)
Write-Host ('engine sha256: {0}' -f (Get-FileHash -Algorithm SHA256 -Path $Engine).Hash.ToLower())
Write-Host ('engine --version: {0}' -f ((& $Engine --version 2>$null) -join ' '))

$userPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ('user editor on {0} before run: pid={1}' -f $UserPort, $userPidBefore)

try {
    Initialize-Scratch
    Import-McpProject -Engine $Engine -Path $ProjectPath -LogDirectory $LogRoot -Name ('mcp044-import-' + $Phase) | Out-Null
    if ($Phase -eq 'editor') { Invoke-EditorPhase }
    elseif ($Phase -eq 'headless') { Invoke-HeadlessPhase }
    elseif ($Phase -eq 'diff-image') { Invoke-DiffImagePhase }
    else { Invoke-GamePhase }
} catch {
    Write-Host ('EXCEPTION: {0}' -f $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
    Add-Check 'phase_completed_without_exception' $false $_.Exception.Message
}

$userPidAfter = Get-ListenerPid -Port $UserPort
Add-Check 'guard_user_port_9877' ($userPidBefore -eq $userPidAfter) `
    ('pid_before={0} pid_after={1}' -f $userPidBefore, $userPidAfter)

Write-Host ''
Write-Host '========================== SUMMARY =========================='
$passed = @($script:Results | Where-Object { $_.pass }).Count
$total = $script:Results.Count
foreach ($r in $script:Results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ('{0}  {1}' -f $tag, $r.id)
}
Write-Host ('{0}/{1} checks passed (phase {2}); evidence in {3}' -f $passed, $total, $Phase, $Evid)
$summaryPath = Join-Path $Evid ('summary-{0}.txt' -f $Phase)
$summary = ($script:Results | ForEach-Object { '{0}|{1}|{2}' -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence }) -join "`n"
Write-McpUtf8NoBom -Path $summaryPath -Text ($summary + "`n")
Write-Host ('summary written: {0}' -f $summaryPath)
if ($passed -ne $total) { exit 1 }
exit 0