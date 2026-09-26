# =============================================================================
#  mcp047_graceful_exit_flush.ps1 -- TASK-047 section 2
#
#  The question REPORT-AUDIT-CAPTURE left `unconfirmed` (section 9.2 item 4):
#
#      "the last call (`editor_analyze_screenshot_diff`, seq=18) has no capture
#       line: my script read the trace right after its response, and a capture
#       line is appended one frame later by design; the process was killed
#       immediately afterwards (`Engine::stop()` drops the in-flight entries).
#       This is not a defect but the observation boundary of *last call + kill
#       right away*; I did not verify with a graceful exit whether the pending
#       entry is flushed before the process goes away."
#
#  This script answers exactly that, with a graceful exit and not a kill:
#
#    * a headless game process on 9889 started with `--mcp-trace=<file>` and
#      `--mcp-capture=every_call`;
#    * call A: a captured read, *waited for*. This is the positive control that
#      a capture line really is appended (one rendered frame after the call) and
#      that the trace file is readable while the process owns it;
#    * call B: `running_game_execute_gdscript` whose body calls
#      `Engine.get_main_loop().quit(0)`. The quit is requested *inside* the tool
#      handler of this very call, i.e. in the same frame the call was armed in,
#      so the frame `tick()` needs (`finish_frame + 1`) never happens. That makes
#      the in-flight boundary deterministic instead of hoped for, and it is a
#      graceful exit: the SceneTree finishes its frame, `Main::iteration()`
#      returns and the process exits with code 0 - no `Stop-Process`, no kill.
#
#  The verdict is written down as it comes out, whichever way it comes out. The
#  only thing this script does *not* do is claim a fact its own trace does not
#  show.
#
#  Port discipline: 9877 belongs to the user and is never occupied - the shared
#  `mcp_port_guard.ps1` classification decides that from the pids and command
#  lines this script started. This script only ever owns 9889.
#
#  Pure ASCII (the PowerShell 5.1 encoding rule this module follows).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp047_graceful_exit_flush.ps1
# =============================================================================

param(
    [int]$GamePort = 9889,
    [int]$ReadyTimeoutMs = 300000,
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$UserPort = 9877

if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp047-graceful-exit' }
$Root = $OutRoot
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$TraceFile = Join-Path $Root 'trace-graceful.jsonl'

# TASK-028 D-1: the shared scratch-project writer and `--import` runner.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-047 section 1: the shared 9877 classification (see mcp_port_guard.ps1).
. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Get-ListenerPid {
    param([int]$Port_)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port_ + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

# The recorder keeps its handle for the whole run, so an observer has to ask for
# `ReadWrite` sharing - `[IO.File]::ReadAllLines` asks for `Read` only and fails
# with a sharing violation on the very file this evidence is about.
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

function Get-CallLines {
    param($TraceLines)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($line in $TraceLines) {
        if (($line.PSObject.Properties.Name -contains 'method') -and ([string]$line.method -eq 'tools/call')) { $out.Add($line) }
    }
    return $out
}

function Get-CaptureEvents {
    param($TraceLines)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($line in $TraceLines) {
        if (($line.PSObject.Properties.Name -contains 'event') -and ([string]$line.event -eq 'capture')) { $out.Add($line) }
    }
    return $out
}

function Add-PathSlash {
    param([string]$Path)
    return ($Path -replace '\\', '/')
}

function New-CallBody {
    param([int]$Id, [string]$Tool, $Arguments)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 0, [int]$MaxTimeSec = 60)
    if ($Port_ -eq 0) { $Port_ = $GamePort }
    $bodyFile = Join-Path $Ev ("{0}.request.json" -f $Id)
    $respFile = Join-Path $Ev ("{0}.response.json" -f $Id)
    Write-Utf8NoBom -Path $bodyFile -Text (New-CallBody -Id 1 -Tool $Tool -Arguments $Arguments)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time $MaxTimeSec -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $curlExit = $LASTEXITCODE
    $text = ''
    if (Test-Path $respFile) { $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($respFile)) }
    Write-Host ("[{0}] curl_exit={1} response={2}" -f $Id, $curlExit, $text)
    return $text
}

function Get-ErrorCode {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return 0 }
        return [int]$envelope.error.code
    } catch { return 0 }
}

function Wait-ForCaptureEvents {
    param([string]$Path, [int]$Expected, [int]$TimeoutMs = 60000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $events = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        $events = @(Get-CaptureEvents -TraceLines (Get-TraceLines -Path $Path))
        if ($events.Count -ge $Expected) { return $events }
        Start-Sleep -Milliseconds 400
    }
    return $events
}

# The engine is started through a generated `cmd.exe` wrapper rather than with
# `Start-Process -RedirectStandardOutput <file>`. Measured on this machine
# (PowerShell 5.1): a process started that way reports `ExitCode` as `$null`
# even after `WaitForExit(ms)` + `Refresh()` + `WaitForExit()`, so "the process
# exited with 0" - the one fact that separates a graceful exit from a kill -
# would not be readable. A wrapper batch file redirects and then writes the
# *expanded at execution time* `%ERRORLEVEL%` to a file, which is.
function Start-EngineViaCmd {
    param(
        [string[]]$Arguments,
        [string]$WrapperPath,
        [string]$OutLog,
        [string]$ErrLog,
        [string]$ExitFile
    )
    $quoted = @($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
    $lines = @(
        '@echo off',
        ('cd /d "' + $RepoRoot + '"'),
        ('"' + $Engine + '" ' + ($quoted -join ' ') + ' > "' + $OutLog + '" 2> "' + $ErrLog + '"'),
        ('echo %ERRORLEVEL% > "' + $ExitFile + '"')
    )
    Write-Utf8NoBom -Path $WrapperPath -Text (($lines -join "`r`n") + "`r`n")
    return (Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $WrapperPath) -PassThru -WindowStyle Hidden)
}

function Wait-ForEndpoint {
    param([int]$Port_, [int]$TimeoutMs)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Join-Path $Ev 'status.json'
        & $Curl -s --max-time 5 -o $probe ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (Test-Path $probe) {
            try {
                $parsed = ConvertFrom-Json ([IO.File]::ReadAllText($probe))
                if ($null -ne $parsed.frame_count) { return $true }
            } catch { }
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# =============================================================================
#  Main
# =============================================================================
Write-Host '============================================================='
Write-Host ' TASK-047 section 2: does a graceful exit flush the in-flight entry?'
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host ("FATAL: engine binary not found: {0}" -f $Engine); exit 2 }
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Proj | Out-Null

Write-Host ("engine: {0}" -f $Engine)
Write-Host ("engine sha256: {0}" -f (Get-FileHash -Algorithm SHA256 -Path $Engine).Hash.ToLower())
Write-Host ("engine --version: {0}" -f ((& $Engine --version 2>$null) -join ' '))

$userPidBefore = Get-ListenerPid -Port_ $UserPort
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("user editor on {0} before: pid={1}" -f $UserPort, $userPidBefore)
Check 'port_9889_free_before' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

New-McpScratchProject -Path $Proj -Name 'mcp047-graceful-exit' -WithMainScene $true -SceneType 'Node2D'
$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'scratch_project_imported' ($import.exit_code -eq 0) `
    ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

$handle = $null
$exitCode = $null
$exited = $false
$quitCallLine = $null
$quitText = ''
$engineOut = Join-Path $LogRoot 'game.out.log'
$engineErr = Join-Path $LogRoot 'game.err.log'
$exitFile = Join-Path $LogRoot 'game.exitcode.txt'
$wrapper = Join-Path $LogRoot 'run-engine.cmd'
try {
    $arguments = @(
        '--headless', '--path', $Proj, ("--mcp-port={0}" -f $GamePort),
        ('--mcp-trace={0}' -f (Add-PathSlash $TraceFile)), '--mcp-capture=every_call'
    )
    $handle = Start-EngineViaCmd -Arguments $arguments -WrapperPath $wrapper -OutLog $engineOut -ErrLog $engineErr -ExitFile $exitFile
    # The pid recorded here is the wrapper's; the engine command line is recorded
    # verbatim as well, so "did this script ever ask for 9877" is answered from
    # the arguments that really reached the engine.
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $arguments
    Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine ("cmd /c {0} :: {1}" -f $wrapper, (($Engine, ($arguments -join ' ')) -join ' '))
    Write-Host ("started wrapper pid={0} :: {1}" -f $handle.Id, (($Engine, ($arguments -join ' ')) -join ' '))

    Check 'game_endpoint_ready' (Wait-ForEndpoint -Port_ $GamePort -TimeoutMs $ReadyTimeoutMs) `
        ("game on {0} answered GET /mcp" -f $GamePort)

    # ---- call A: the positive control ------------------------------------
    $textA = Invoke-Tool -Id 'A_captured_read' -Tool 'running_game_get_scene_tree' -Arguments @{ max_depth = 2 }
    $codeA = Get-ErrorCode $textA
    Check 'control_call_a_answered' ((Get-ErrorCode $textA) -eq 0) ("running_game_get_scene_tree error_code={0}" -f $codeA)

    $eventsA = @(Wait-ForCaptureEvents -Path $TraceFile -Expected 1)
    Check 'control_capture_line_landed_while_alive' (@($eventsA).Count -ge 1) `
        ("capture events after call A = {0} (a capture line is appended one rendered frame after its response; the process was alive to run that frame)" -f @($eventsA).Count)

    # ---- call B: the graceful exit, requested from inside its own handler --
    $quitCode = 'Engine.get_main_loop().quit(0)' + "`n" + 'return "quit-requested"'
    $quitText = Invoke-Tool -Id 'B_quit_call' -Tool 'running_game_execute_gdscript' -Arguments @{ code = $quitCode }
    Write-Host ("quit call error_code={0}" -f (Get-ErrorCode $quitText))

    $exited = $handle.WaitForExit(120000)
    if ($exited) {
        # The wrapper's own line runs after the engine is gone, so this file is
        # the engine's real exit code, read from disk rather than from the
        # PowerShell process object (which reports it as null when the output was
        # redirected - see Start-EngineViaCmd).
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while (-not (Test-Path $exitFile) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
        if (Test-Path $exitFile) {
            $raw = ([IO.File]::ReadAllText($exitFile)).Trim()
            if ($raw -match '^-?[0-9]+$') { $exitCode = [int]$raw }
        }
    }
} finally {
    if ($null -ne $handle -and -not $handle.HasExited) {
        & taskkill /PID $handle.Id /T /F *> (Join-Path $LogRoot 'taskkill.log')
        Start-Sleep -Milliseconds 1000
    }
}

Check 'process_exited_on_its_own_gracefully' ($exited -and ($exitCode -eq 0)) `
    ("the engine's exit code (written by the cmd wrapper after the engine returned) = {0}; the wrapper was never killed, so a non-zero or absent code would mean the quit path did not finish (the logs are {1} / {2})" -f $(if ($null -eq $exitCode) { 'n/a' } else { $exitCode }), $engineOut, $engineErr)

# =============================================================================
#  Read the file the dead process left behind
# =============================================================================
$traceBytes = if (Test-Path $TraceFile) { [IO.File]::ReadAllBytes($TraceFile) } else { @() }
$traceSha = if (Test-Path $TraceFile) { (Get-FileHash -Algorithm SHA256 -Path $TraceFile).Hash.ToLower() } else { '<missing>' }
$traceText = [Text.Encoding]::UTF8.GetString($traceBytes)
$traceLines = @(Get-TraceLines -Path $TraceFile)
$callLines = @(Get-CallLines -TraceLines $traceLines)
$captureEvents = @(Get-CaptureEvents -TraceLines $traceLines)

Check 'trace_file_non_empty_and_ends_with_a_newline' `
    (($traceBytes.Length -gt 0) -and ($traceText.EndsWith("`n"))) `
    ("bytes={0} sha256={1} ends_with_LF={2} (a torn tail would show up as a last line that does not parse, checked next)" -f $traceBytes.Length, $traceSha, $traceText.EndsWith("`n"))

$lastLine = if ($traceLines.Count -ge 1) { $traceLines[$traceLines.Count - 1] } else { $null }
Check 'every_line_including_the_last_parses_as_json' ($null -ne $lastLine) `
    ("parsed trace lines={0}; the last one is {1}" -f $traceLines.Count, $(if ($null -eq $lastLine) { '<none>' } else { 'method=' + [string]$lastLine.method + ' tool=' + [string]$lastLine.tool }))

foreach ($line in $callLines) {
    if ([string]$line.tool -eq 'running_game_execute_gdscript') { $quitCallLine = $line }
}

Check 'the_quit_call_line_is_on_disk' ($null -ne $quitCallLine) `
    ("tools/call lines={0}; the last request before the shutdown (running_game_execute_gdscript) has a line: {1}" -f $callLines.Count, $(if ($null -eq $quitCallLine) { 'NO' } else { 'yes, seq=' + [string]$quitCallLine.seq + ' capture.status=' + [string]$quitCallLine.capture.status }))

$quitSeq = -1
if ($null -ne $quitCallLine) { $quitSeq = [int]$quitCallLine.seq }
$quitCaptureEvents = @($captureEvents | Where-Object { [int]$_.seq -eq $quitSeq -and $quitSeq -ge 0 })

Check 'the_in_flight_capture_line_was_not_written' (($quitSeq -ge 0) -and ($quitCaptureEvents.Count -eq 0)) `
    ("quit call seq={0}; capture event lines carrying that seq={1} (the call line announced capture.status={2}, so the entry was armed and in flight when the process went away)" -f $quitSeq, $quitCaptureEvents.Count, $(if ($null -eq $quitCallLine) { 'n/a' } else { [string]$quitCallLine.capture.status }))

$announced = @($callLines | Where-Object { $_.PSObject.Properties.Name -contains 'capture' })
$dangling = New-Object System.Collections.Generic.List[int]
foreach ($line in $announced) {
    $seq = [int]$line.seq
    if (@($captureEvents | Where-Object { [int]$_.seq -eq $seq }).Count -eq 0) { $dangling.Add($seq) }
}
Check 'the_only_dangling_entry_is_the_in_flight_one' ($dangling.Count -le 1) `
    ("call lines announcing a capture={0}, capture event lines={1}, seqs announced but never written=[{2}] (counted from the file, not assumed)" -f $announced.Count, $captureEvents.Count, (@($dangling) -join ','))

$portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence

# =============================================================================
#  Summary
# =============================================================================
Write-Host ''
Write-Host '=============== the raw trace the dead process left ==============='
foreach ($line in ($traceText -split "`n")) {
    if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Host $line }
}
Write-Host '==================================================================='

$logPath = Join-Path $Ev 'evidence.log.txt'
$summary = @()
foreach ($entry in $script:Checks) {
    $entryTag = if ($entry.pass) { 'PASS' } else { 'FAIL' }
    $summary += ("[{0}] {1} :: {2}" -f $entryTag, $entry.id, $entry.evidence)
}
Write-Utf8NoBom -Path $logPath -Text (($summary -join "`r`n") + "`r`n")
$resultsFile = Join-Path $Ev 'results.json'
Write-Utf8NoBom -Path $resultsFile -Text (ConvertTo-Json -InputObject $script:Checks -Depth 6)

$passed = @($script:Checks | Where-Object { $_.pass }).Count
$total = $script:Checks.Count
Write-Host ''
Write-Host ("graceful exit flush: {0}/{1} checks passed; evidence in {2}" -f $passed, $total, $Ev)
Write-Host ("log sha256 = {0}" -f (Get-FileHash -Algorithm SHA256 -Path $logPath).Hash.ToLower())
if ($passed -ne $total) {
    foreach ($entry in $script:Checks) { if (-not $entry.pass) { Write-Host ("  FAILED {0} :: {1}" -f $entry.id, $entry.evidence) } }
    exit 1
}
exit 0
