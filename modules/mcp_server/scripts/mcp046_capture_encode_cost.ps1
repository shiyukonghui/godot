# =============================================================================
#  mcp046_capture_encode_cost.ps1 -- TASK-046: the capture's *encoding* cost.
#
#  REPORT-045 split the `--mcp-capture=every_call` post-response cost with a
#  measurement: of the ~377 ms a back-to-back round trip spent, ~14 ms was the
#  pixel comparison and **~356 ms was two 2978x1793 PNG encodes** (177 ms each).
#  TASK-046 attacks that half with two levers that only touch the capture
#  bypass:
#
#    * the capture writes its diagnostic PNGs through the engine's `p_fast`
#      flag (`PNG_IMAGE_FLAG_FAST`: no row filters, compression level 3); the
#      two screenshot tools keep `Image::save_png()`;
#    * `--mcp-capture-scale=1|2|4` (default 1) resamples both frames *before*
#      anything is written or compared, so the two files and the
#      `changed_pixel_ratio` on the same capture line are always the same raster.
#
#  What this script produces, live, on one engine binary:
#
#    * the round-trip distributions (off / every_call back-to-back /
#      every_call 2.5 s apart) at `scale=1` and at `scale=2`;
#    * the two captured PNGs' bytes and sha256 at scale 1 - the *fast* bytes,
#      which is the only evidence of how much size the speed costs;
#    * the consistency proof: `editor_analyze_screenshot_diff` is fed the very
#      two PNG files of a capture, and its `changed_pixels` / `total_pixels`
#      must equal the numbers on that capture's own log line. At scale 2 this is
#      the assertion that catches "scaled the files but compared the full
#      frames" - the trap the task book forbids;
#    * `editor_analyze_screenshot_diff`'s payload sha256 at scale 1, which must
#      still be TASK-045's: the same pixels through the module's one comparison.
#
#  Run it once per binary and diff the `evidence\<label>\summary.txt` files:
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp046_capture_encode_cost.ps1 `
#        -Label pre -EnginePath C:\...\pre\godot.windows.editor.x86_64.console.exe
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp046_capture_encode_cost.ps1 -Label post
#
#  `-PngEncoding` says which encoding the capture is expected to have written:
#  `fast` (the default; TASK-046 and later) or `default` (a pre-TASK-046
#  binary). The measured sha256 is always printed, so the answer is never hidden
#  behind the expectation.
#
#  Port discipline: 9877 belongs to the user's own editor and is never touched
#  (its pid is read before and after and asserted equal); this script only ever
#  starts and kills its own process on 9888.
#
#  Evidence is written under %TEMP%\mcp046-evidence; every response body goes to
#  disk through `curl.exe -s -o <file>` (never through a PowerShell pipeline,
#  PLAYBOOK section 7.1) and every request body through `Write-McpUtf8NoBom`.
# =============================================================================

param(
    [string]$Label = 'post',
    [string]$EnginePath = '',
    [ValidateSet('fast', 'default')][string]$PngEncoding = 'fast',
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrEmpty($EnginePath)) {
    $EnginePath = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
}
if (-not (Test-Path $EnginePath)) { throw ('the engine binary "{0}" does not exist' -f $EnginePath) }
$Engine = (Resolve-Path $EnginePath).Path
$UserPort = 9877
$EditorPort = 9888
$Root = Join-Path $env:TEMP 'mcp046-evidence'
$Evid = Join-Path $Root ('evidence\' + $Label)
$LogRoot = Join-Path $Root ('logs\' + $Label)
$ProjectPath = Join-Path $Root 'project'

# The numbers TASK-044/045 measured for this exact project and scene, and the
# payload sha256 REPORT-045 published for the same pair. They are asserted, not
# merely printed: "the same pixels give the same answer" is the whole equivalence
# claim of this task.
$ExpectedChanged = 106800
$ExpectedTotal = 5339554
$ExpectedPayloadSha = '51c697771432ad17aac0b8a0c9d81f4e56e13033d631a660af47bf95b7476034'
# The captured PNGs' sha256, by encoding. `default` is TASK-044/045's pair; the
# `fast` pair is what this task's first evidence run measured (recorded here so
# a later run can prove the bytes are reproducible, not merely non-empty).
$ExpectedBeforePngDefault = '865c2f934c834d034fe2554503c41027ec57df1053f9ddef414098e887f3f36f'
$ExpectedAfterPngDefault = '87731a87b9d728ae2350f035b7b25dbeba46b326829596a155588291bbba3f2a'
$ExpectedBeforePngFast = 'c2d7a1bf20d8b909fd12797996e9f5d369b8a86e783fa0dea766590210624127'
$ExpectedAfterPngFast = '4516082843ecc2d2ff0d286a4b2b3fd1d63a51ce9d7b2497a14126cd9f2f47c0'

if ($PngEncoding -eq 'fast') {
    $ExpectedBeforePng = $ExpectedBeforePngFast
    $ExpectedAfterPng = $ExpectedAfterPngFast
} else {
    $ExpectedBeforePng = $ExpectedBeforePngDefault
    $ExpectedAfterPng = $ExpectedAfterPngDefault
}
$PngAnchorKnown = ($ExpectedBeforePng -notmatch '^__')

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

$script:Results = New-Object System.Collections.Generic.List[object]
$script:Notes = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Results.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ('[{0}] {1}' -f $tag, $Id)
    Write-Host ('       {0}' -f $Evidence)
}

function Add-Note {
    param([string]$Text)
    $script:Notes.Add($Text)
    Write-Host ('[NOTE] {0}' -f $Text)
}

function ConvertTo-McpPath {
    param([string]$Path)
    return ($Path -replace '\\', '/')
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

function Invoke-Mcp {
    param([string]$Id, [int]$PortNumber, [string]$Json, [string]$Directory, [int]$MaxTimeSec = 60)
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

function Get-PayloadText {
    # The tool's own answer, as the exact text of `content[0].text`. The response
    # envelope carries the request's `id`, which is exactly what makes two
    # byte-identical responses impossible to ask for; everything that is *the
    # tool's* answer is in this string.
    param([string]$ResponseText)
    $envelope = Get-Envelope $ResponseText
    if ($null -eq $envelope) { return '' }
    if ($null -eq $envelope.result) { return '' }
    $content = @($envelope.result.content)
    if ($content.Count -eq 0) { return '' }
    return [string]$content[0].text
}

function Get-Payload {
    param([string]$ResponseText)
    $text = Get-PayloadText -ResponseText $ResponseText
    if ([string]::IsNullOrEmpty($text)) { return $null }
    try { return (ConvertFrom-Json $text) } catch { return $null }
}

function Get-ErrorCode {
    param([string]$ResponseText)
    $envelope = Get-Envelope $ResponseText
    if ($null -eq $envelope) { return 0 }
    if ($null -eq $envelope.error) { return 0 }
    return [int]$envelope.error.code
}

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

function Wait-ForCaptureEvents {
    param([string]$Path, [int]$Expected, [int]$TimeoutMs = 180000)
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

function Format-Samples {
    # The raw samples, in request order: a min/median/max triple hides a polluted
    # run, and this host's load is demonstrably variable (TASK-046 saw one run
    # whose *off* baseline was 101 ms median against 19 ms in the next).
    param([double[]]$Values)
    return (($Values | ForEach-Object { '{0:N4}' -f $_ }) -join ' ')
}

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

function Get-StringSha256 {
    param([string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function Get-LocalPath {
    # `res://x/y.png` -> `<project>\x\y.png`, the way the capture wrote it.
    param([string]$McpPath)
    return (Join-Path $ProjectPath ($McpPath -replace '^res://', '' -replace '/', '\'))
}

function Initialize-Scratch {
    New-Item -ItemType Directory -Force -Path $Root, $Evid, $LogRoot | Out-Null
    New-McpScratchProject -Path $ProjectPath -Name 'mcp046-capture-encode' -WithMainScene $true -SceneType 'Node2D'
    # The same scene TASK-044/045 used: a Node2D with one ColorRect whose colour a
    # single tool call can change, which is what makes the two calls of the
    # existence experiment produce a real 106800-pixel difference.
    $scene = @(
        '[gd_scene format=3]',
        '',
        '[node name="Main" type="Node2D"]',
        '',
        '[node name="ColorRect" type="ColorRect" parent="."]',
        'offset_right = 600.0',
        'offset_bottom = 400.0',
        'color = Color(1, 0, 0, 1)'
    )
    Write-McpUtf8NoBom -Path (Join-Path $ProjectPath 'scenes\main.tscn') -Text (($scene -join "`n") + "`n")
}

# One full `every_call` run at one scale. Returns the distributions, the two
# events of the existence experiment and everything measured around them.
function Invoke-ScaleRun {
    param([int]$Scale, [string]$ShotsDir, [int]$IdBase)

    $result = [pscustomobject]@{
        Ready = $false
        BackToBack = @()
        Spaced = @()
        MutateEvents = @()
        Done = @()
        EventCount = 0
        StartupLine = ''
        PairBeforeSha = ''
        PairAfterSha = ''
        PairBeforeBytes = 0
        PairAfterBytes = 0
        DiffPayloadSha = ''
        ToolChangedPixels = -1
        ToolTotalPixels = -1
        ToolWidth = -1
        ToolHeight = -1
        LogChangedPixels = -1
        LogTotalPixels = -1
        LogRatio = -1.0
        LogScale = -1
        LogWidth = -1
        LogHeight = -1
        Swapped = $false
    }

    $dir = Join-Path $Evid ('scale' + $Scale)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $trace = Join-Path $Root ('trace-scale' + $Scale + '-' + $Label + '.jsonl')
    Remove-Item -Path $trace -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $ProjectPath ($ShotsDir -replace '^res://', '')) -Recurse -Force -ErrorAction SilentlyContinue

    $handle = Start-Engine -Arguments @(
        '-e', '--path', $ProjectPath, ('--mcp-port={0}' -f $EditorPort),
        ('--mcp-trace={0}' -f (ConvertTo-McpPath $trace)),
        '--mcp-capture=every_call', ('--mcp-capture-dir=' + $ShotsDir), '--mcp-capture-viewport=2d',
        ('--mcp-capture-scale=' + $Scale)
    ) -LogName ('editor-scale' + $Scale)
    try {
        $result.Ready = Wait-ForReady -PortNumber $EditorPort -TimeoutMs $ReadyTimeoutMs -Directory $dir
        if (-not $result.Ready) { return $result }

        $open = Invoke-Mcp -Id ('s{0}_open_scene' -f $Scale) -PortNumber $EditorPort -Directory $dir `
            -Json (New-CallBody -Id ($IdBase + 1) -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' })

        # The TASK-044 existence experiment, unchanged: the same call twice, both
        # reported as successes, one of which changes the picture.
        $mutate1 = Invoke-Mcp -Id ('s{0}_mutate_first' -f $Scale) -PortNumber $EditorPort -Directory $dir `
            -Json (New-CallBody -Id ($IdBase + 2) -Tool 'editor_set_node_property' -Arguments @{ path = 'ColorRect'; property = 'color'; value = '#00ff00' })
        $mutate2 = Invoke-Mcp -Id ('s{0}_mutate_again' -f $Scale) -PortNumber $EditorPort -Directory $dir `
            -Json (New-CallBody -Id ($IdBase + 3) -Tool 'editor_set_node_property' -Arguments @{ path = 'ColorRect'; property = 'color'; value = '#00ff00' })

        $backToBack = @()
        for ($i = 1; $i -le 5; $i++) {
            $r = Invoke-Mcp -Id ('s{0}_b2b_{1}' -f $Scale, $i) -PortNumber $EditorPort -Directory $dir `
                -Json (New-CallBody -Id ($IdBase + 10 + $i) -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
            $backToBack += $r.seconds
        }
        $spaced = @()
        for ($i = 1; $i -le 5; $i++) {
            Start-Sleep -Milliseconds 2500
            $r = Invoke-Mcp -Id ('s{0}_spaced_{1}' -f $Scale, $i) -PortNumber $EditorPort -Directory $dir `
                -Json (New-CallBody -Id ($IdBase + 30 + $i) -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
            $spaced += $r.seconds
        }
        $result.BackToBack = $backToBack
        $result.Spaced = $spaced

        $events = @(Wait-ForCaptureEvents -Path $trace -Expected 13)
        $traceLines = Get-TraceLines -Path $trace
        $done = @($events | Where-Object { [string]$_.status -eq 'done' })
        $result.EventCount = @($events).Count
        $result.Done = $done
        $result.StartupLine = (@(Select-String -Path $handle.Out -SimpleMatch '[MCP] capture enabled:' | ForEach-Object { $_.Line }) -join ' | ')

        $mutateEvents = New-Object System.Collections.Generic.List[object]
        foreach ($event in $done) {
            $callLine = Get-CallLineBySeq -TraceLines $traceLines -Seq ([int]$event.seq)
            if ($null -eq $callLine) { continue }
            if (([string]$callLine.args) -match '#00ff00') { $mutateEvents.Add($event) }
        }
        $result.MutateEvents = $mutateEvents

        if ($mutateEvents.Count -ge 1) {
            $first = $mutateEvents[0]
            $result.LogScale = [int]$first.scale
            $result.LogChangedPixels = [int]$first.changed_pixels
            $result.LogTotalPixels = [int]$first.total_pixels
            $result.LogRatio = [double]$first.changed_pixel_ratio
            $result.LogWidth = [int]$first.before.width
            $result.LogHeight = [int]$first.before.height

            $beforeLocal = Get-LocalPath ([string]$first.before.path)
            $afterLocal = Get-LocalPath ([string]$first.after.path)
            $result.PairBeforeSha = Get-FileSha256 -Path $beforeLocal
            $result.PairAfterSha = Get-FileSha256 -Path $afterLocal
            if (Test-Path $beforeLocal) { $result.PairBeforeBytes = (Get-Item $beforeLocal).Length }
            if (Test-Path $afterLocal) { $result.PairAfterBytes = (Get-Item $afterLocal).Length }
            Copy-Item -Path $beforeLocal -Destination (Join-Path $dir 'pair-before.png') -Force -ErrorAction SilentlyContinue
            Copy-Item -Path $afterLocal -Destination (Join-Path $dir 'pair-after.png') -Force -ErrorAction SilentlyContinue

            # **The consistency check.** The two files are handed to the tool an
            # observer has; every number it answers must be the line's own.
            $tool = Invoke-Mcp -Id ('s{0}_diff_pair' -f $Scale) -PortNumber $EditorPort -Directory $dir `
                -Json (New-CallBody -Id ($IdBase + 50) -Tool 'editor_analyze_screenshot_diff' -Arguments @{ image_a = [string]$first.before.path; image_b = [string]$first.after.path })
            $payloadText = Get-PayloadText -ResponseText $tool.text
            $result.DiffPayloadSha = Get-StringSha256 -Text $payloadText
            Write-McpUtf8NoBom -Path (Join-Path $dir 'diff-tool-payload.json') -Text $payloadText
            $payload = Get-Payload $tool.text
            if ($null -ne $payload) {
                $result.ToolChangedPixels = [int]$payload.changed_pixels
                $result.ToolTotalPixels = [int]$payload.total_pixels
                $result.ToolWidth = [int]$payload.width
                $result.ToolHeight = [int]$payload.height
            }
        }

        # The ratio itself must be the ratio of the file pair, exactly: the
        # `editor_analyze_screenshot_diff` payload is a second reading of the same
        # two rasters.
        if (($result.ToolTotalPixels -gt 0) -and ($result.LogTotalPixels -gt 0)) {
            $fileRatio = [double]$result.ToolChangedPixels / [double]$result.ToolTotalPixels
            $result.Swapped = ([Math]::Abs($fileRatio - $result.LogRatio) -lt 1e-12)
        }
    } finally {
        Stop-Engine -Handle $handle
        Wait-ForPortFree -PortNumber $EditorPort | Out-Null
    }
    return $result
}

# =============================================================================
#  Main
# =============================================================================

Write-Host '============================================================='
Write-Host (' TASK-046 capture-encode cost evidence -- label "{0}"' -f $Label)
Write-Host '============================================================='

New-Item -ItemType Directory -Force -Path $Evid, $LogRoot | Out-Null

$version = (& $Engine --version 2>$null) -join ''
$version = $version.Trim()
$engineSha = Get-FileSha256 -Path $Engine
Write-Host ('engine: {0}' -f $Engine)
Write-Host ('engine sha256: {0}' -f $engineSha)
Write-Host ('engine --version: {0}' -f $version)
Add-Note ('engine={0}' -f $Engine)
Add-Note ('engine_sha256={0}' -f $engineSha)
Add-Note ('engine_version={0}' -f $version)
Add-Note ('png_encoding_expected={0}' -f $PngEncoding)

$userPidBefore = Get-ListenerPid -PortNumber $UserPort
Write-Host ('user editor on {0} before run: pid={1}' -f $UserPort, $userPidBefore)

if ((Get-ListenerPid -PortNumber $EditorPort) -ge 0) {
    throw ('port {0} is already in use; refusing to disturb a foreign process' -f $EditorPort)
}

Initialize-Scratch
$import = Import-McpProject -Engine $Engine -Path $ProjectPath -LogDirectory $LogRoot -Name ('mcp046-import-' + $Label)
Add-Check 'project_imported' ($import.exit_code -eq 0) ('--import exit={0} attempts={1}' -f $import.exit_code, $import.attempts)

# ---- run 1: capture off, the baseline round trip.
$offLatency = @()
$offDir = Join-Path $Evid 'off'
New-Item -ItemType Directory -Force -Path $offDir | Out-Null
$offTrace = Join-Path $Root ('trace-off-' + $Label + '.jsonl')
Remove-Item -Path $offTrace -Force -ErrorAction SilentlyContinue
$offHandle = Start-Engine -Arguments @(
    '-e', '--path', $ProjectPath, ('--mcp-port={0}' -f $EditorPort),
    ('--mcp-trace={0}' -f (ConvertTo-McpPath $offTrace)), '--mcp-capture=off'
) -LogName 'editor-off'
try {
    $ready = Wait-ForReady -PortNumber $EditorPort -TimeoutMs $ReadyTimeoutMs -Directory $offDir
    Add-Check 'off_endpoint_ready' $ready ('editor on {0}' -f $EditorPort)
    if ($ready) {
        $openOff = Invoke-Mcp -Id 'off_open_scene' -PortNumber $EditorPort -Directory $offDir `
            -Json (New-CallBody -Id 1001 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' })
        Add-Check 'off_scene_opened' ((Get-ErrorCode $openOff.text) -eq 0) ('open_scene error_code={0}' -f (Get-ErrorCode $openOff.text))
        for ($i = 1; $i -le 5; $i++) {
            $r = Invoke-Mcp -Id ('off_lat_{0}' -f $i) -PortNumber $EditorPort -Directory $offDir `
                -Json (New-CallBody -Id (1100 + $i) -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
            $offLatency += $r.seconds
        }
    }
} finally {
    Stop-Engine -Handle $offHandle
    Wait-ForPortFree -PortNumber $EditorPort | Out-Null
}
Add-Check 'off_round_trip_distribution' ($offLatency.Count -eq 5) ('curl round trip -- off: {0}' -f (Format-Stats $offLatency))
Add-Note ('curl_round_trip_off={0}' -f (Format-Stats $offLatency))
Add-Note ('curl_round_trip_off_samples={0}' -f (Format-Samples $offLatency))

# ---- run 2 and 3: every_call at scale 1 and at scale 2.
$scale1 = Invoke-ScaleRun -Scale 1 -ShotsDir 'res://mcp046_shots_scale1' -IdBase 2000
$scale2 = Invoke-ScaleRun -Scale 2 -ShotsDir 'res://mcp046_shots_scale2' -IdBase 3000

# ---- scale 1: unchanged pixels, unchanged payload, only the PNG bytes move.
Add-Check 'scale1_endpoint_ready' $scale1.Ready ('editor on {0}' -f $EditorPort)
Add-Check 'scale1_startup_log_says_scale_1' ($scale1.StartupLine -match 'scale=1') ('startup log: {0}' -f $scale1.StartupLine)
Add-Check 'scale1_captured_every_call' ($scale1.Done.Count -ge 13) `
    ('capture events={0} done={1}' -f $scale1.EventCount, $scale1.Done.Count)
Add-Check 'scale1_line_carries_scale_1' ($scale1.LogScale -eq 1) ('scale field={0}' -f $scale1.LogScale)
Add-Check 'scale1_changed_true_with_the_task_044_numbers' `
    (($scale1.LogChangedPixels -eq $ExpectedChanged) -and ($scale1.LogTotalPixels -eq $ExpectedTotal)) `
    ('changed_pixels={0} total_pixels={1} ratio={2} (expected {3} / {4})' -f $scale1.LogChangedPixels, $scale1.LogTotalPixels, $scale1.LogRatio, $ExpectedChanged, $ExpectedTotal)
if ($scale1.MutateEvents.Count -ge 2) {
    $second = $scale1.MutateEvents[1]
    Add-Check 'scale1_no_op_success_is_changed_false' `
        ((-not [bool]$second.changed) -and ([int]$second.changed_pixels -eq 0)) `
        ('second "#00ff00" write: changed={0} changed_pixels={1}' -f $second.changed, $second.changed_pixels)
} else {
    Add-Check 'scale1_no_op_success_is_changed_false' $false ('second mutation event missing (events={0})' -f $scale1.MutateEvents.Count)
}
Add-Note ('scale1_pair_before_sha256={0} bytes={1}' -f $scale1.PairBeforeSha, $scale1.PairBeforeBytes)
Add-Note ('scale1_pair_after_sha256={0} bytes={1}' -f $scale1.PairAfterSha, $scale1.PairAfterBytes)
if ($PngAnchorKnown) {
    Add-Check ('scale1_the_two_captured_pngs_are_the_{0}_bytes' -f $PngEncoding) `
        (($scale1.PairBeforeSha -eq $ExpectedBeforePng) -and ($scale1.PairAfterSha -eq $ExpectedAfterPng)) `
        ('before={0} (expected {1}) / after={2} (expected {3})' -f $scale1.PairBeforeSha, $ExpectedBeforePng, $scale1.PairAfterSha, $ExpectedAfterPng)
} else {
    Add-Note ('scale1_png_anchor_not_set: this run measured before={0} after={1}' -f $scale1.PairBeforeSha, $scale1.PairAfterSha)
}
Add-Note ('scale1_diff_tool_payload_sha256={0}' -f $scale1.DiffPayloadSha)
Add-Check 'scale1_the_two_callers_still_answer_the_same_pixels' `
    (($scale1.ToolChangedPixels -eq $ExpectedChanged) -and ($scale1.ToolTotalPixels -eq $ExpectedTotal) -and ($scale1.DiffPayloadSha -eq $ExpectedPayloadSha)) `
    ('diff tool: changed_pixels={0} total_pixels={1} {2}x{3} payload_sha256={4} (expected {5})' -f $scale1.ToolChangedPixels, $scale1.ToolTotalPixels, $scale1.ToolWidth, $scale1.ToolHeight, $scale1.DiffPayloadSha, $ExpectedPayloadSha)
Add-Check 'scale1_the_line_agrees_with_the_files' `
    (($scale1.ToolChangedPixels -eq $scale1.LogChangedPixels) -and ($scale1.ToolTotalPixels -eq $scale1.LogTotalPixels) -and $scale1.Swapped) `
    ('line: {0}/{1} ratio={2} || files: {3}/{4} ratio={5}' -f $scale1.LogChangedPixels, $scale1.LogTotalPixels, $scale1.LogRatio, $scale1.ToolChangedPixels, $scale1.ToolTotalPixels, $(if ($scale1.ToolTotalPixels -gt 0) { [double]$scale1.ToolChangedPixels / [double]$scale1.ToolTotalPixels } else { 'n/a' }))
Add-Note ('curl_round_trip_every_call_scale1_back_to_back={0}' -f (Format-Stats $scale1.BackToBack))
Add-Note ('curl_round_trip_every_call_scale1_back_to_back_samples={0}' -f (Format-Samples $scale1.BackToBack))
Add-Note ('curl_round_trip_every_call_scale1_spaced={0}' -f (Format-Stats $scale1.Spaced))
Add-Check 'scale1_round_trip_distributions' (($scale1.BackToBack.Count -eq 5) -and ($scale1.Spaced.Count -eq 5)) `
    ('back_to_back={0} spaced={1}' -f (Format-Stats $scale1.BackToBack), (Format-Stats $scale1.Spaced))

# ---- scale 2: the files and the line describe the same halved raster.
Add-Check 'scale2_endpoint_ready' $scale2.Ready ('editor on {0}' -f $EditorPort)
Add-Check 'scale2_startup_log_says_scale_2' ($scale2.StartupLine -match 'scale=2') ('startup log: {0}' -f $scale2.StartupLine)
Add-Check 'scale2_captured_every_call' ($scale2.Done.Count -ge 13) `
    ('capture events={0} done={1}' -f $scale2.EventCount, $scale2.Done.Count)
Add-Check 'scale2_line_carries_scale_2' ($scale2.LogScale -eq 2) ('scale field={0}' -f $scale2.LogScale)
# The scale-2 raster is the scale-1 raster halved (integer division), and the
# capture line and the tool that read the two files agree on that size.
$halfWidth = [int][Math]::Floor([double]$scale1.LogWidth / 2.0)
$halfHeight = [int][Math]::Floor([double]$scale1.LogHeight / 2.0)
Add-Check 'scale2_the_files_are_the_halved_raster' `
    (($scale2.LogWidth -eq $halfWidth) -and ($scale2.LogHeight -eq $halfHeight) -and ($scale2.ToolWidth -eq $halfWidth) -and ($scale2.ToolHeight -eq $halfHeight) -and ($scale2.LogTotalPixels -eq ($halfWidth * $halfHeight))) `
    ('scale 1: {0}x{1} ({2} px) -> scale 2: {3}x{4} ({5} px); diff tool read {6}x{7}' -f $scale1.LogWidth, $scale1.LogHeight, $scale1.LogTotalPixels, $scale2.LogWidth, $scale2.LogHeight, $scale2.LogTotalPixels, $scale2.ToolWidth, $scale2.ToolHeight)
Add-Check 'scale2_the_line_agrees_with_the_files' `
    (($scale2.ToolChangedPixels -eq $scale2.LogChangedPixels) -and ($scale2.ToolTotalPixels -eq $scale2.LogTotalPixels) -and $scale2.Swapped) `
    ('line: {0}/{1} ratio={2} || files: {3}/{4} ratio={5}' -f $scale2.LogChangedPixels, $scale2.LogTotalPixels, $scale2.LogRatio, $scale2.ToolChangedPixels, $scale2.ToolTotalPixels, $(if ($scale2.ToolTotalPixels -gt 0) { [double]$scale2.ToolChangedPixels / [double]$scale2.ToolTotalPixels } else { 'n/a' }))
Add-Check 'scale2_the_change_is_still_detected' `
    ($scale2.LogChangedPixels -gt 0) ('changed_pixels={0} of {1}' -f $scale2.LogChangedPixels, $scale2.LogTotalPixels)
Add-Note ('scale2_pair_before_sha256={0} bytes={1}' -f $scale2.PairBeforeSha, $scale2.PairBeforeBytes)
Add-Note ('scale2_pair_after_sha256={0} bytes={1}' -f $scale2.PairAfterSha, $scale2.PairAfterBytes)
Add-Note ('curl_round_trip_every_call_scale2_back_to_back={0}' -f (Format-Stats $scale2.BackToBack))
Add-Note ('curl_round_trip_every_call_scale2_back_to_back_samples={0}' -f (Format-Samples $scale2.BackToBack))
Add-Note ('curl_round_trip_every_call_scale2_spaced={0}' -f (Format-Stats $scale2.Spaced))
Add-Check 'scale2_round_trip_distributions' (($scale2.BackToBack.Count -eq 5) -and ($scale2.Spaced.Count -eq 5)) `
    ('back_to_back={0} spaced={1}' -f (Format-Stats $scale2.BackToBack), (Format-Stats $scale2.Spaced))
Add-Note ('paid_back_to_back_ratio_scale2_over_scale1={0:N3}' -f `
    $(if ((Get-Median $scale1.BackToBack) -gt 0) { (Get-Median $scale2.BackToBack) / (Get-Median $scale1.BackToBack) } else { 0.0 }))

$userPidAfter = Get-ListenerPid -PortNumber $UserPort
Add-Check 'guard_user_port_9877' ($userPidBefore -eq $userPidAfter) ('pid_before={0} pid_after={1}' -f $userPidBefore, $userPidAfter)

# ---- summary.
$failed = @($script:Results | Where-Object { -not $_.pass })
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('TASK-046 capture-encode cost evidence')
$lines.Add(('label: {0}' -f $Label))
$lines.Add(('engine: {0}' -f $Engine))
$lines.Add(('engine sha256: {0}' -f $engineSha))
$lines.Add(('engine --version: {0}' -f $version))
$lines.Add('')
$lines.Add('notes:')
foreach ($note in $script:Notes) { $lines.Add(('  {0}' -f $note)) }
$lines.Add('')
$lines.Add('checks:')
foreach ($result in $script:Results) {
    $tag = if ($result.pass) { 'PASS' } else { 'FAIL' }
    $lines.Add(('  [{0}] {1}' -f $tag, $result.id))
    $lines.Add(('         {0}' -f $result.evidence))
}
$lines.Add('')
$lines.Add(('{0}/{1} checks passed' -f ($script:Results.Count - $failed.Count), $script:Results.Count))
Write-McpUtf8NoBom -Path (Join-Path $Evid 'summary.txt') -Text (($lines -join "`n") + "`n")

$summaryText = ($lines -join "`n")
Write-Host ''
Write-Host '========================== SUMMARY =========================='
Write-Host $summaryText
Write-Host ('summary written: {0}' -f (Join-Path $Evid 'summary.txt'))

if ($failed.Count -gt 0) { exit 1 }
exit 0
