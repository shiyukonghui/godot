# =============================================================================
#  mcp038_zero_change.ps1 -- TASK-038: the trace changes nothing.
#
#  The call trace is a *bypass* capability, not a behaviour change, so the proof
#  is a byte comparison: the very same requests are sent to the very same kind of
#  endpoint three times and every response body must be identical.
#
#    run A  editor on 9888, trace OFF
#    run B  editor on 9888, trace OFF      <- the control: what A != B is not
#                                             an effect of the trace, it is the
#                                             endpoint being non-deterministic,
#                                             and such a probe is excluded (and
#                                             reported) instead of passing by
#                                             accident
#    run C  editor on 9888, trace ON       <- must equal A on every probe A == B
#
#  Every response is captured with `curl.exe -s -o <file>` (never through a pipe:
#  a PowerShell pipeline mangles non-ASCII bytes, PLAYBOOK section 7.1) and
#  compared by sha256.
#
#  Port discipline: the user's own editor owns 9877 and is never touched; this
#  script only kills the processes it started and asserts the 9877 pid at the end.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp038_zero_change.ps1
# =============================================================================

param(
    [int]$Port = 9888,
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$UserPort = 9877
$ScratchRoot = Join-Path $env:TEMP 'mcp038-zero-change'
$LogRoot = Join-Path $env:TEMP 'mcp038-zero-change-logs'
$TraceFile = Join-Path $env:TEMP 'mcp038-zero-change-trace.jsonl'

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp038_probes.ps1')

$script:StartedPids = New-Object System.Collections.Generic.List[int]
$script:Results = New-Object System.Collections.Generic.List[object]

function Record-Result {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Results.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
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

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $out = Join-Path $LogRoot ($LogName + '.out.log')
    $err = Join-Path $LogRoot ($LogName + '.err.log')
    Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    $script:StartedPids.Add($proc.Id)
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

# The probes are shared with `mcp038_baseline_compare.ps1` (one definition, so
# the two evidence scripts can never drift apart).
function Wait-ForReady {
    param([string]$Directory, [int]$TimeoutMs)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $requestFile = Join-Path $Directory 'ready-request.json'
    $responseFile = Join-Path $Directory 'ready-response.json'
    $body = '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}'
    Write-McpUtf8NoBom -Path $requestFile -Text $body
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path $responseFile) { Remove-Item $responseFile -ErrorAction SilentlyContinue }
        & curl.exe -s -o $responseFile -X POST -H 'Content-Type: application/json' `
            --data-binary ("@" + $requestFile) ("http://127.0.0.1:{0}/mcp" -f $Port) 2>$null | Out-Null
        if (Test-Path $responseFile) {
            $text = [IO.File]::ReadAllText($responseFile)
            if ($text -match 'protocolVersion') { return $true }
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# Runs every probe once against a freshly started editor and returns a table of
# `label -> sha256 of the response body`.
function Invoke-Run {
    param([string]$Label, [bool]$TraceEnabled)
    $dir = Join-Path $ScratchRoot $Label
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $arguments = @('--headless', '-e', '--path', $ProjectPath, ("--mcp-port={0}" -f $Port))
    if ($TraceEnabled) { $arguments += ("--mcp-trace={0}" -f $TraceFile) }
    $handle = Start-Engine -Arguments $arguments -LogName ('zero-change-' + $Label)
    $hashes = [ordered]@{}
    if (-not (Wait-ForReady -Directory $dir -TimeoutMs $ReadyTimeoutMs)) {
        Stop-Engine -Handle $handle
        return @{ ok = $false; hashes = $hashes; log = $handle.Out }
    }

    foreach ($probe in $probes) {
        $requestFile = Join-Path $dir ('request-{0}.json' -f $probe.id)
        $responseFile = Join-Path $dir ('response-{0}.json' -f $probe.id)
        Write-McpUtf8NoBom -Path $requestFile -Text (Get-Mcp038ProbeBody -Probe $probe)
        if (Test-Path $responseFile) { Remove-Item $responseFile -ErrorAction SilentlyContinue }
        & curl.exe -s -o $responseFile -X POST -H 'Content-Type: application/json' `
            --data-binary ("@" + $requestFile) ("http://127.0.0.1:{0}/mcp" -f $Port) 2>$null | Out-Null
        if (-not (Test-Path $responseFile)) {
            $hashes[$probe.label] = 'NO_RESPONSE'
            continue
        }
        $hashes[$probe.label] = (Get-FileHash -Algorithm SHA256 -Path $responseFile).Hash
    }

    Stop-Engine -Handle $handle
    return @{ ok = $true; hashes = $hashes; log = $handle.Out }
}

# =============================================================================
#  Main
# =============================================================================

Write-Host '============================================================='
Write-Host ' TASK-038 zero behaviour change -- three runs, byte compare'
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host ("FATAL: engine binary not found: {0}" -f $Engine); exit 2 }

$probes = New-Mcp038Probes
New-Item -ItemType Directory -Force -Path $ScratchRoot, $LogRoot | Out-Null
$ProjectPath = Join-Path $ScratchRoot 'project'
# The very same scratch project the two other TASK-038 evidence scripts use, so
# the three sha256 tables of this task describe the same inputs.
New-Mcp038ScratchProject -Path $ProjectPath
Remove-Item -Path $TraceFile -ErrorAction SilentlyContinue

Write-Host ('importing scratch project {0} ...' -f $ProjectPath)
# `--mcp-port=0` (the helper's default) and NOT `-NoPort`: an editor process with
# no port argument falls back to the default 9877 and tries to bind the port the
# user's own editor owns. Omitting the port is not the same as asking for "no
# port"; the import must stay off every port.
Import-McpProject -Engine $Engine -Path $ProjectPath -LogDirectory $LogRoot -Name 'zero-change-import' | Out-Null

$userPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ('user editor on {0} before run: pid={1}' -f $UserPort, $userPidBefore)
Write-Host ('probes: {0}' -f $probes.Count)
Write-Host ''

$runA = Invoke-Run -Label 'off-a' -TraceEnabled $false
if (-not $runA.ok) { Write-Host 'FATAL: run A (trace off) never became ready'; exit 2 }
$runB = Invoke-Run -Label 'off-b' -TraceEnabled $false
if (-not $runB.ok) { Write-Host 'FATAL: run B (trace off control) never became ready'; exit 2 }
$runC = Invoke-Run -Label 'on' -TraceEnabled $true
if (-not $runC.ok) { Write-Host 'FATAL: run C (trace on) never became ready'; exit 2 }

# The trace file of run C has to exist: the switch really was on for that run.
Record-Result 'trace_file_written_when_on' (Test-Path $TraceFile) `
    ('file={0} exists={1}' -f $TraceFile, (Test-Path $TraceFile))

$deterministic = 0
$changed = 0
$unstable = 0
$rows = New-Object System.Collections.Generic.List[string]
foreach ($probe in $probes) {
    $label = $probe.label
    $a = [string]$runA.hashes[$label]
    $b = [string]$runB.hashes[$label]
    $c = [string]$runC.hashes[$label]
    if ($a -eq $b) {
        $deterministic++
        if ($a -eq $c) {
            $rows.Add(('  {0,-40} {1}  off=on' -f $label, $a.Substring(0, 16)))
        } else {
            $changed++
            $rows.Add(('  {0,-40} {1}  off={2} on={3}  <== CHANGED' -f $label, $a.Substring(0, 16), $a.Substring(0, 16), $c.Substring(0, 16)))
        }
    } else {
        $unstable++
        $rows.Add(('  {0,-40} NON-DETERMINISTIC off-a={1} off-b={2}  (excluded)' -f $label, $a.Substring(0, 16), $b.Substring(0, 16)))
    }
}
Write-Host ''
Write-Host 'probe response sha256 (first 16 hex digits):'
foreach ($row in $rows) { Write-Host $row }
Write-Host ''

Record-Result 'deterministic_control_run' ($unstable -le 4) `
    ('stable={0} unstable={1} (a probe that differs between two identical trace-off runs is the endpoint, not the trace)' -f $deterministic, $unstable)
Record-Result 'trace_does_not_change_any_stable_probe' ($changed -eq 0 -and $deterministic -ge 10) `
    ('compared={0} changed={1} (need >= 10 stable probes and zero differences)' -f $deterministic, $changed)

# The full `tools/list` is the contract itself: it has to be one of the stable
# probes, and its byte identity across the three runs is the zero-change claim
# for the whole tool surface at once. The exact *set* is gate 1's assertion
# (`check_contract_subset.ps1` against the implemented union), so this check only
# insists that the list is a real, non-empty tool list of the editor endpoint.
$listResponse = Join-Path (Join-Path $ScratchRoot 'off-a') 'response-2.json'
$listTools = -1
if (Test-Path $listResponse) {
    $parsed = ConvertFrom-Json ([IO.File]::ReadAllText($listResponse))
    if ($null -ne $parsed.result) { $listTools = @($parsed.result.tools).Count }
}
Record-Result 'tools_list_is_stable_and_complete' `
    ($listTools -gt 100 -and $runA.hashes['tools/list'] -eq $runB.hashes['tools/list'] -and $runA.hashes['tools/list'] -eq $runC.hashes['tools/list']) `
    ('editor tools={0} sha_off_a={1} sha_off_b={2} sha_on={3}' -f $listTools, ([string]$runA.hashes['tools/list']).Substring(0, 16), ([string]$runB.hashes['tools/list']).Substring(0, 16), ([string]$runC.hashes['tools/list']).Substring(0, 16))

# The two endpoints of the module still say "off" and "on" in their logs, which
# is how a reader of a log knows whether a trace file is to be expected.
Record-Result 'startup_log_says_off_for_runs_ab' `
    ((Select-String -Path $runA.log -Pattern '\[MCP\] trace=off' -Quiet) -and (Select-String -Path $runB.log -Pattern '\[MCP\] trace=off' -Quiet)) `
    ('run_a={0} run_b={1}' -f (Select-String -Path $runA.log -Pattern '\[MCP\] trace=off' -Quiet), (Select-String -Path $runB.log -Pattern '\[MCP\] trace=off' -Quiet))
Record-Result 'startup_log_says_on_for_run_c' `
    (Select-String -Path $runC.log -Pattern '\[MCP\] trace enabled: file=' -Quiet) `
    ('run_c_log={0}' -f $runC.log)

$userPidAfter = Get-ListenerPid -Port $UserPort
Record-Result 'guard_user_port_9877' ($userPidBefore -eq $userPidAfter) `
    ('pid_before={0} pid_after={1}' -f $userPidBefore, $userPidAfter)

Write-Host ''
Write-Host '========================== SUMMARY =========================='
$passed = @($script:Results | Where-Object { $_.pass }).Count
$total = $script:Results.Count
foreach ($r in $script:Results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ('{0}  {1}' -f $tag, $r.id)
}
Write-Host ('{0}/{1} checks passed; probes={2} stable={3} changed={4} unstable={5}' -f $passed, $total, $probes.Count, $deterministic, $changed, $unstable)
if ($passed -ne $total) { exit 1 }
exit 0