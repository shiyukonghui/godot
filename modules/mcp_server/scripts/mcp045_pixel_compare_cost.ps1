# =============================================================================
#  mcp045_pixel_compare_cost.ps1 -- TASK-045: the capture's pixel-compare cost.
#
#  TASK-044 measured the cost of the before/after capture (REPORT-044 section
#  6.2): the *response* path only pays one framebuffer copy (+7 ms), but the work
#  after the answer (two PNG encodes + a 5.3 million pixel comparison) keeps the
#  main thread busy for ~400 ms, so the back-to-back round trip went from 18.5 ms
#  to 453.6 ms. The comparison itself was `Image::get_pixel()` per pixel.
#
#  TASK-045 replaces that walk with the bytes `Image::get_data()` hands out. This
#  script is the *live* half of the evidence; the in-process A/B of the two
#  comparison paths (distribution included) is printed by the doctest
#  `TASK-045: the capture's own 2978x1793 pair ...` as `[MCP045-TIMING]` lines.
#
#  What it produces, for one engine binary:
#
#    * the `changed:true` / `changed:false` pair of the TASK-044 existence
#      experiment, with the 106800 / 5339554 pixel numbers unchanged;
#    * the sha256 of the two captured PNGs, which must be **reproducible** (and
#      which TASK-046 changed on purpose: the capture now writes them with the
#      engine's fast PNG flag, so `-PngEncoding fast|default` says which pair is
#      expected and the measured sha256 is printed in every run);
#    * `editor_analyze_screenshot_diff` over that very pair, twice, with the sha256
#      of the two response bodies - so the *same* pair can be shown to give the
#      *same bytes* on another binary (the pre-TASK-045 one);
#    * the three round-trip distributions (off / every_call back-to-back /
#      every_call 2.5 s apart) and the server-side `duration_ms` pair.
#
#  Run it once per binary and diff the two `evidence\<label>\summary.txt` files:
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp045_pixel_compare_cost.ps1 `
#        -Label pre  -EnginePath C:\...\pre\godot.windows.editor.x86_64.console.exe
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp045_pixel_compare_cost.ps1 -Label post
#
#  Port discipline: 9877 belongs to the user's own editor and is never touched
#  (its pid is read before and after and asserted equal); this script only ever
#  starts and kills its own process on 9888.
#
#  Evidence is written under %TEMP%\mcp045-evidence; every response body goes to
#  disk through `curl.exe -s -o <file>` (never through a PowerShell pipeline,
#  PLAYBOOK section 7.1) and every request body through `Write-McpUtf8NoBom`.
# =============================================================================

param(
    [string]$Label = 'post',
    [string]$EnginePath = '',
    # TASK-046: the capture stopped writing its diagnostic PNGs with
    # `Image::save_png()`'s default encoding, so the two files' sha256 are no
    # longer TASK-044's. Everything the check is *for* is still asserted - the
    # bytes are reproducible and named - and the measured sha256 is printed in
    # every run either way, so nothing is hidden behind the expectation.
    # `default` keeps this script runnable on a pre-TASK-046 binary.
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
$Root = Join-Path $env:TEMP 'mcp045-evidence'
$Evid = Join-Path $Root ('evidence\' + $Label)
$LogRoot = Join-Path $Root ('logs\' + $Label)
$ProjectPath = Join-Path $Root 'project'
$Trace = Join-Path $Root ('trace-' + $Label + '.jsonl')

# The numbers TASK-044 measured for this exact project and scene. They are
# asserted, not merely printed: "the same pair gives the same numbers" is the
# whole equivalence claim of this task.
$ExpectedChanged = 106800
$ExpectedTotal = 5339554
# The captured PNGs' own bytes, by encoding: `default` is the pair TASK-044/045
# wrote, `fast` is TASK-046's. TASK-046 moved the *pixels* nowhere - the two
# files still decode to the frames that answer 106800 / 5339554, and the diff
# tool's payload sha256 below is still TASK-045's - but the bytes on disk are a
# different (larger, cheaper to produce) PNG encoding, which is exactly what
# TASK-046 measured.
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
    param([string]$Path, [int]$Expected, [int]$TimeoutMs = 120000)
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

function Initialize-Scratch {
    New-Item -ItemType Directory -Force -Path $Root, $Evid, $LogRoot | Out-Null
    Remove-Item -Path (Join-Path $ProjectPath 'mcp045_shots') -Recurse -Force -ErrorAction SilentlyContinue
    New-McpScratchProject -Path $ProjectPath -Name 'mcp045-pixel-compare' -WithMainScene $true -SceneType 'Node2D'
    # The same scene TASK-044's capture evidence used: a Node2D with one ColorRect
    # whose colour a single tool call can change, which is what makes the two
    # calls of the existence experiment produce a real 106800-pixel difference.
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

# =============================================================================
#  Main
# =============================================================================

Write-Host '============================================================='
Write-Host (' TASK-045 pixel-compare cost evidence -- label "{0}"' -f $Label)
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
$import = Import-McpProject -Engine $Engine -Path $ProjectPath -LogDirectory $LogRoot -Name ('mcp045-import-' + $Label)
Add-Check 'project_imported' ($import.exit_code -eq 0) ('--import exit={0} attempts={1}' -f $import.exit_code, $import.attempts)

$offLatency = @()
$onLatency = @()
$onLatencySpaced = @()
$diffToolSeconds = @()

# ---- run 1: capture off, the baseline round trip.
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

# ---- run 2: capture every_call on the 2d viewport.
$onDir = Join-Path $Evid 'every-call'
New-Item -ItemType Directory -Force -Path $onDir | Out-Null
Remove-Item -Path $Trace -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $ProjectPath 'mcp045_shots') -Recurse -Force -ErrorAction SilentlyContinue
$onHandle = Start-Engine -Arguments @(
    '-e', '--path', $ProjectPath, ('--mcp-port={0}' -f $EditorPort),
    ('--mcp-trace={0}' -f (ConvertTo-McpPath $Trace)),
    '--mcp-capture=every_call', '--mcp-capture-dir=res://mcp045_shots', '--mcp-capture-viewport=2d'
) -LogName 'editor-every-call'
$pair = $null
try {
    $ready = Wait-ForReady -PortNumber $EditorPort -TimeoutMs $ReadyTimeoutMs -Directory $onDir
    Add-Check 'every_call_endpoint_ready' $ready ('editor on {0}' -f $EditorPort)
    if (-not $ready) { throw 'the every_call editor endpoint never became ready' }

    $open = Invoke-Mcp -Id 'open_scene' -PortNumber $EditorPort -Directory $onDir `
        -Json (New-CallBody -Id 2001 -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' })
    Add-Check 'scene_opened' ((Get-ErrorCode $open.text) -eq 0) ('open_scene error_code={0}' -f (Get-ErrorCode $open.text))

    # The TASK-044 existence experiment, unchanged: the same call twice, both
    # reported as successes, one of which changes the picture.
    $mutate1 = Invoke-Mcp -Id 'mutate_first' -PortNumber $EditorPort -Directory $onDir `
        -Json (New-CallBody -Id 2003 -Tool 'editor_set_node_property' -Arguments @{ path = 'ColorRect'; property = 'color'; value = '#00ff00' })
    $mutate2 = Invoke-Mcp -Id 'mutate_again' -PortNumber $EditorPort -Directory $onDir `
        -Json (New-CallBody -Id 2004 -Tool 'editor_set_node_property' -Arguments @{ path = 'ColorRect'; property = 'color'; value = '#00ff00' })
    Add-Check 'both_mutations_reported_success' `
        (((Get-ErrorCode $mutate1.text) -eq 0) -and ((Get-ErrorCode $mutate2.text) -eq 0)) `
        ('first error_code={0}, second error_code={1}' -f (Get-ErrorCode $mutate1.text), (Get-ErrorCode $mutate2.text))

    for ($i = 1; $i -le 5; $i++) {
        $r = Invoke-Mcp -Id ('on_lat_{0}' -f $i) -PortNumber $EditorPort -Directory $onDir `
            -Json (New-CallBody -Id (2100 + $i) -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
        $onLatency += $r.seconds
    }
    for ($i = 1; $i -le 5; $i++) {
        Start-Sleep -Milliseconds 2500
        $r = Invoke-Mcp -Id ('on_lat_spaced_{0}' -f $i) -PortNumber $EditorPort -Directory $onDir `
            -Json (New-CallBody -Id (2120 + $i) -Tool 'editor_get_scene_tree' -Arguments @{ max_depth = 2 })
        $onLatencySpaced += $r.seconds
    }

    $events = @(Wait-ForCaptureEvents -Path $Trace -Expected 13)
    $traceLines = Get-TraceLines -Path $Trace
    $done = @($events | Where-Object { [string]$_.status -eq 'done' })
    Add-Check 'every_call_captured_every_call' ($done.Count -ge 13) `
        ('capture events={0} done={1}' -f $events.Count, $done.Count)

    $mutateEvents = New-Object System.Collections.Generic.List[object]
    foreach ($event in $done) {
        $callLine = Get-CallLineBySeq -TraceLines $traceLines -Seq ([int]$event.seq)
        if ($null -eq $callLine) { continue }
        if (([string]$callLine.args) -match '#00ff00') { $mutateEvents.Add($event) }
    }
    $firstEvent = if ($mutateEvents.Count -ge 1) { $mutateEvents[0] } else { $null }
    $secondEvent = if ($mutateEvents.Count -ge 2) { $mutateEvents[1] } else { $null }
    Add-Check 'the_real_change_is_changed_true_with_the_task_044_numbers' `
        (($null -ne $firstEvent) -and ([bool]$firstEvent.changed) -and ([int]$firstEvent.changed_pixels -eq $ExpectedChanged) -and ([int]$firstEvent.total_pixels -eq $ExpectedTotal)) `
        ('first "#00ff00" write: changed={0} changed_pixels={1} total_pixels={2} ratio={3} (expected {4} / {5})' -f `
            $(if ($null -ne $firstEvent) { $firstEvent.changed } else { 'n/a' }), `
            $(if ($null -ne $firstEvent) { $firstEvent.changed_pixels } else { 'n/a' }), `
            $(if ($null -ne $firstEvent) { $firstEvent.total_pixels } else { 'n/a' }), `
            $(if ($null -ne $firstEvent) { $firstEvent.changed_pixel_ratio } else { 'n/a' }), `
            $ExpectedChanged, $ExpectedTotal)
    Add-Check 'the_no_op_success_is_changed_false' `
        (($null -ne $secondEvent) -and (-not [bool]$secondEvent.changed) -and ([int]$secondEvent.changed_pixels -eq 0)) `
        ('second "#00ff00" write: changed={0} changed_pixels={1}' -f `
            $(if ($null -ne $secondEvent) { $secondEvent.changed } else { 'n/a' }), `
            $(if ($null -ne $secondEvent) { $secondEvent.changed_pixels } else { 'n/a' }))

    if ($null -ne $firstEvent) {
        $beforeLocal = Join-Path $ProjectPath (([string]$firstEvent.before.path) -replace '^res://', '' -replace '/', '\')
        $afterLocal = Join-Path $ProjectPath (([string]$firstEvent.after.path) -replace '^res://', '' -replace '/', '\')
        $beforeSha = Get-FileSha256 -Path $beforeLocal
        $afterSha = Get-FileSha256 -Path $afterLocal
        Add-Note ('pair_before={0} sha256={1}' -f $firstEvent.before.path, $beforeSha)
        Add-Note ('pair_after={0} sha256={1}' -f $firstEvent.after.path, $afterSha)
        # Kept next to the evidence, so the two labels' pairs can be compared
        # byte for byte after the fact (and replayed through the tool).
        Copy-Item -Path $beforeLocal -Destination (Join-Path $Evid 'pair-before.png') -Force
        Copy-Item -Path $afterLocal -Destination (Join-Path $Evid 'pair-after.png') -Force
        Add-Check 'the_two_captured_pngs_are_reproducible' `
            ($(if ($PngAnchorKnown) { ($beforeSha -eq $ExpectedBeforePng) -and ($afterSha -eq $ExpectedAfterPng) } else { ($beforeSha.Length -eq 64) -and ($afterSha.Length -eq 64) -and ($beforeSha -ne $afterSha) })) `
            ('encoding={0} before sha256={1} (expected {2}) / after sha256={3} (expected {4})' -f $PngEncoding, $beforeSha, $ExpectedBeforePng, $afterSha, $ExpectedAfterPng)

        # `editor_analyze_screenshot_diff` over that very pair, twice: the numbers
        # must be TASK-044's, and two runs must produce the same *payload* bytes
        # (the envelope's `id` differs by construction, the tool's answer must
        # not). The payload of the first call is kept on disk so the same pair can
        # be run through another binary and the two payloads compared.
        $payloadShas = @()
        for ($i = 1; $i -le 3; $i++) {
            $r = Invoke-Mcp -Id ('diff_pair_{0}' -f $i) -PortNumber $EditorPort -Directory $onDir `
                -Json (New-CallBody -Id (2200 + $i) -Tool 'editor_analyze_screenshot_diff' -Arguments @{ image_a = [string]$firstEvent.before.path; image_b = [string]$firstEvent.after.path })
            $diffToolSeconds += $r.seconds
            $payloadText = Get-PayloadText -ResponseText $r.text
            $payloadShas += (Get-StringSha256 -Text $payloadText)
            if ($i -eq 1) {
                Write-McpUtf8NoBom -Path (Join-Path $Evid 'diff-tool-payload-1.json') -Text $payloadText
                Write-McpUtf8NoBom -Path (Join-Path $Evid 'diff-tool-response-1.json') -Text $r.text
                $payload = Get-Payload $r.text
                if ($null -ne $payload) {
                    Add-Check 'the_diff_tool_agrees_with_the_capture' `
                        (([int]$payload.changed_pixels -eq $ExpectedChanged) -and ([int]$payload.total_pixels -eq $ExpectedTotal) -and (-not [bool]$payload.identical)) `
                        ('identical={0} changed_pixels={1} total_pixels={2} diff_percentage={3} width={4} height={5}' -f `
                            $payload.identical, $payload.changed_pixels, $payload.total_pixels, $payload.diff_percentage, $payload.width, $payload.height)
                    Add-Note ('diff_tool_diff_image_base64_sha256={0}' -f (Get-StringSha256 -Text ([string]$payload.diff_image_base64)))
                } else {
                    Add-Check 'the_diff_tool_agrees_with_the_capture' $false 'the response payload could not be parsed'
                }
            }
        }
        Add-Check 'the_diff_tool_payload_is_repeatable' (($payloadShas.Count -eq 3) -and ($payloadShas[0] -eq $payloadShas[1]) -and ($payloadShas[1] -eq $payloadShas[2])) `
            ('three identical calls, payload sha256 {0}' -f (($payloadShas | ForEach-Object { $_.Substring(0, 16) }) -join ' '))
        Add-Note ('diff_tool_payload_1_sha256={0}' -f $payloadShas[0])
        Add-Note ('diff_tool_payload_bytes={0}' -f (([IO.File]::ReadAllBytes((Join-Path $Evid 'diff-tool-payload-1.json'))).Length))
    }

    # The server-side `duration_ms` of the folded calls (the response path), which
    # is what TASK-044's "zero latency" criterion is about.
    $onDurations = @()
    foreach ($line in (Get-TraceLines -Path $Trace)) {
        if (($line.PSObject.Properties.Name -contains 'method') -and ([string]$line.method -eq 'tools/call') -and ([string]$line.tool -eq 'editor_get_scene_tree')) {
            $onDurations += [double]$line.duration_ms
        }
    }
    $offDurations = @()
    foreach ($line in (Get-TraceLines -Path $offTrace)) {
        if (($line.PSObject.Properties.Name -contains 'method') -and ([string]$line.method -eq 'tools/call') -and ([string]$line.tool -eq 'editor_get_scene_tree')) {
            $offDurations += [double]$line.duration_ms
        }
    }
    Add-Note ('server_duration_ms_off={0}' -f (Format-Stats $offDurations))
    Add-Note ('server_duration_ms_every_call={0}' -f (Format-Stats $onDurations))
    Add-Check 'the_response_path_still_only_adds_the_one_copy' `
        (($offDurations.Count -ge 5) -and ($onDurations.Count -ge 5) -and (((Get-Median $onDurations) - (Get-Median $offDurations)) -le 50.0)) `
        ('server side `duration_ms` -- off: {0} || every_call: {1} || delta_median={2:N1} ms' -f (Format-Stats $offDurations), (Format-Stats $onDurations), ((Get-Median $onDurations) - (Get-Median $offDurations)))
} finally {
    Stop-Engine -Handle $onHandle
    Wait-ForPortFree -PortNumber $EditorPort | Out-Null
}

Add-Check 'client_round_trip_has_all_three_distributions' `
    (($offLatency.Count -eq 5) -and ($onLatency.Count -eq 5) -and ($onLatencySpaced.Count -eq 5)) `
    ('curl round trip -- off: {0}' -f (Format-Stats $offLatency))
Add-Note ('curl_round_trip_off={0}' -f (Format-Stats $offLatency))
Add-Note ('curl_round_trip_every_call_back_to_back={0}' -f (Format-Stats $onLatency))
Add-Note ('curl_round_trip_every_call_spaced={0}' -f (Format-Stats $onLatencySpaced))
Add-Note ('curl_round_trip_diff_tool={0}' -f (Format-Stats $diffToolSeconds))

$userPidAfter = Get-ListenerPid -PortNumber $UserPort
Add-Check 'guard_user_port_9877' ($userPidBefore -eq $userPidAfter) ('pid_before={0} pid_after={1}' -f $userPidBefore, $userPidAfter)

# ---- summary.
$failed = @($script:Results | Where-Object { -not $_.pass })
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('TASK-045 pixel-compare cost evidence')
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
