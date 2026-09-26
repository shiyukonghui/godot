# =============================================================================
#  mcp038_trace_evidence.ps1 -- TASK-038: a real trace sample with real friction.
#
#  Produces the two things the report needs from a *live* endpoint:
#
#   1. "off by default": an editor started without `--mcp-trace` writes no file
#      at all, and says `[MCP] trace=off` in its log;
#   2. a real sample: an editor started with `--mcp-trace=<path>` records every
#      `initialize` / `tools/list` / `tools/call` in order, and the sample
#      deliberately contains friction the observer is supposed to find:
#        * `project_read_script` with a path that does not exist (-32001),
#          then the same tool with the path that does (the "had to find the
#          right shape" signal),
#        * a tool name that does not exist (-32601, a missing-tool clue),
#        * an undeclared argument (-32602),
#        * `project_get_info` called twice with the same arguments.
#
#  The analyzer (`scripts/analyze_mcp_trace.py`) is then run on the sample and
#  its output is checked for those signals, because a trace that cannot show the
#  friction is not evidence of anything.
#
#  Evidence capture is `curl.exe -s -o <file>` plus sha256, bodies are built with
#  `ConvertTo-Json`, and 9877 is never touched.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp038_trace_evidence.ps1
# =============================================================================

param(
    [int]$Port = 9888,
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Analyzer = Join-Path $PSScriptRoot 'analyze_mcp_trace.py'
$UserPort = 9877
$ScratchRoot = Join-Path $env:TEMP 'mcp038-trace-evidence'
$LogRoot = Join-Path $env:TEMP 'mcp038-trace-evidence-logs'
$TraceFile = Join-Path $env:TEMP 'mcp038-trace-sample.jsonl'
$AnalysisJson = Join-Path $env:TEMP 'mcp038-trace-analysis.json'

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

# One `tools/call`, captured with curl into a file. Returns the response text.
function Invoke-ToolCall {
    param([string]$Directory, [int]$Id, [string]$Tool, $Arguments)
    $requestFile = Join-Path $Directory ('request-{0}.json' -f $Id)
    $responseFile = Join-Path $Directory ('response-{0}.json' -f $Id)
    $request = @{
        jsonrpc = '2.0'
        id = $Id
        method = 'tools/call'
        params = @{ name = $Tool; arguments = $Arguments }
    }
    Write-McpUtf8NoBom -Path $requestFile -Text (($request | ConvertTo-Json -Depth 10 -Compress))
    if (Test-Path $responseFile) { Remove-Item $responseFile -ErrorAction SilentlyContinue }
    & curl.exe -s -o $responseFile -X POST -H 'Content-Type: application/json' `
        --data-binary ("@" + $requestFile) ("http://127.0.0.1:{0}/mcp" -f $Port) 2>$null | Out-Null
    if (-not (Test-Path $responseFile)) { return '' }
    return [IO.File]::ReadAllText($responseFile)
}

function Invoke-Raw {
    param([string]$Directory, [int]$Id, [string]$Method)
    $requestFile = Join-Path $Directory ('request-{0}.json' -f $Id)
    $responseFile = Join-Path $Directory ('response-{0}.json' -f $Id)
    $request = @{ jsonrpc = '2.0'; id = $Id; method = $Method; params = @{} }
    Write-McpUtf8NoBom -Path $requestFile -Text (($request | ConvertTo-Json -Depth 10 -Compress))
    if (Test-Path $responseFile) { Remove-Item $responseFile -ErrorAction SilentlyContinue }
    & curl.exe -s -o $responseFile -X POST -H 'Content-Type: application/json' `
        --data-binary ("@" + $requestFile) ("http://127.0.0.1:{0}/mcp" -f $Port) 2>$null | Out-Null
    if (-not (Test-Path $responseFile)) { return '' }
    return [IO.File]::ReadAllText($responseFile)
}

function Wait-ForReady {
    param([string]$Directory, [int]$TimeoutMs)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $text = Invoke-Raw -Directory $Directory -Id 900 -Method 'initialize'
        if ($text -match 'protocolVersion') { return $true }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# =============================================================================
#  Main
# =============================================================================

Write-Host '============================================================='
Write-Host ' TASK-038 real trace sample'
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host ("FATAL: engine binary not found: {0}" -f $Engine); exit 2 }
if (-not (Test-Path $Analyzer)) { Write-Host ("FATAL: analyzer not found: {0}" -f $Analyzer); exit 2 }

New-Item -ItemType Directory -Force -Path $ScratchRoot, $LogRoot | Out-Null
$ProjectPath = Join-Path $ScratchRoot 'project'
# The very same scratch project the two other TASK-038 evidence scripts use.
New-Mcp038ScratchProject -Path $ProjectPath
Write-Host ('importing scratch project {0} ...' -f $ProjectPath)
# `--mcp-port=0` (the helper's default) and NOT `-NoPort`: an editor process with
# no port argument falls back to the default 9877 and tries to bind the port the
# user's own editor owns (measured: the import log carried
# `role=editor configured_port=9877 source=default` and `bind failed on
# 127.0.0.1:9877`). Omitting the port is not the same as asking for "no port".
Import-McpProject -Engine $Engine -Path $ProjectPath -LogDirectory $LogRoot -Name 'trace-evidence-import' | Out-Null

$userPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ('user editor on {0} before run: pid={1}' -f $UserPort, $userPidBefore)

# -----------------------------------------------------------------------------
# Part A: the default. No switch, no file.
# -----------------------------------------------------------------------------
Remove-Item -Path $TraceFile -ErrorAction SilentlyContinue
$offDir = Join-Path $ScratchRoot 'off'
New-Item -ItemType Directory -Force -Path $offDir | Out-Null
$offHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $ProjectPath, ("--mcp-port={0}" -f $Port)) -LogName 'trace-off'
$readyOff = Wait-ForReady -Directory $offDir -TimeoutMs $ReadyTimeoutMs
if (-not $readyOff) {
    Stop-Engine -Handle $offHandle
    Write-Host 'FATAL: the trace-off editor never became ready'
    exit 2
}
$null = Invoke-Raw -Directory $offDir -Id 1 -Method 'initialize'
$null = Invoke-Raw -Directory $offDir -Id 2 -Method 'tools/list'
$null = Invoke-ToolCall -Directory $offDir -Id 3 -Tool 'project_get_info' -Arguments @{}
Stop-Engine -Handle $offHandle

Record-Result 'default_off_writes_no_file' (-not (Test-Path $TraceFile)) `
    ('trace path {0} exists={1} after 3 requests' -f $TraceFile, (Test-Path $TraceFile))
Record-Result 'default_off_is_announced_in_the_log' (Select-String -Path $offHandle.Out -Pattern '\[MCP\] trace=off' -Quiet) `
    ('log={0}' -f $offHandle.Out)

# -----------------------------------------------------------------------------
# Part B: the switch on. Nine real calls, with deliberate friction.
# -----------------------------------------------------------------------------
Remove-Item -Path $TraceFile -ErrorAction SilentlyContinue
$onDir = Join-Path $ScratchRoot 'on'
New-Item -ItemType Directory -Force -Path $onDir | Out-Null
$onHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $ProjectPath, ("--mcp-port={0}" -f $Port), ("--mcp-trace={0}" -f $TraceFile)) -LogName 'trace-on'
$readyOn = Wait-ForReady -Directory $onDir -TimeoutMs $ReadyTimeoutMs
if (-not $readyOn) {
    Stop-Engine -Handle $onHandle
    Write-Host 'FATAL: the traced editor never became ready'
    exit 2
}

# The readiness probe above is itself request id 900; it is part of the sample.
$script:calls = New-Object System.Collections.Generic.List[object]
$script:calls.Add([pscustomobject]@{ step = 'initialize'; text = (Invoke-Raw -Directory $onDir -Id 1 -Method 'initialize') })
$script:calls.Add([pscustomobject]@{ step = 'tools/list'; text = (Invoke-Raw -Directory $onDir -Id 2 -Method 'tools/list') })
$script:calls.Add([pscustomobject]@{ step = 'project_get_info ok'; text = (Invoke-ToolCall -Directory $onDir -Id 3 -Tool 'project_get_info' -Arguments @{}) })
$script:calls.Add([pscustomobject]@{ step = 'project_read_script MISSING (deliberate failure)'; text = (Invoke-ToolCall -Directory $onDir -Id 4 -Tool 'project_read_script' -Arguments @{ path = 'res://no_such_script_038.gd' }) })
$script:calls.Add([pscustomobject]@{ step = 'project_read_script ok (the recovery)'; text = (Invoke-ToolCall -Directory $onDir -Id 5 -Tool 'project_read_script' -Arguments @{ path = 'res://scripts/hello.gd' }) })
$script:calls.Add([pscustomobject]@{ step = 'project_get_no_such_tool (deliberate -32601)'; text = (Invoke-ToolCall -Directory $onDir -Id 6 -Tool 'project_get_no_such_tool_038' -Arguments @{}) })
$script:calls.Add([pscustomobject]@{ step = 'project_get_info unknown argument (deliberate -32602)'; text = (Invoke-ToolCall -Directory $onDir -Id 7 -Tool 'project_get_info' -Arguments @{ bogus_argument = 1 }) })
$script:calls.Add([pscustomobject]@{ step = 'project_get_statistics ok'; text = (Invoke-ToolCall -Directory $onDir -Id 8 -Tool 'project_get_statistics' -Arguments @{}) })
$script:calls.Add([pscustomobject]@{ step = 'project_get_info ok again (same arguments)'; text = (Invoke-ToolCall -Directory $onDir -Id 9 -Tool 'project_get_info' -Arguments @{}) })
Stop-Engine -Handle $onHandle

# The nine responses, so the reader can see the trace line next to the answer.
foreach ($call in $script:calls) {
    $tag = 'ok'
    if ($call.text -match '"code":(-?\d+)') { $tag = ('error ' + $Matches[1]) }
    Write-Host ('  {0,-52} -> {1}' -f $call.step, $tag)
}
Write-Host ''

Record-Result 'trace_file_created_when_on' (Test-Path $TraceFile) ('file={0}' -f $TraceFile)
Record-Result 'trace_announced_in_the_log' (Select-String -Path $onHandle.Out -Pattern '\[MCP\] trace enabled: file=' -Quiet) `
    ((Select-String -Path $onHandle.Out -Pattern '\[MCP\] trace enabled: file=' | Select-Object -First 1).Line)

$lines = @()
if (Test-Path $TraceFile) { $lines = @([IO.File]::ReadAllLines($TraceFile) | Where-Object { $_.Trim() -ne '' }) }
# The readiness probe (id 900) plus the nine calls, plus TASK-054's generation
# marker: every process that opens the trace file writes exactly one
# `{"event":"trace_opened",...}` line first, and it is an *event* line, so it
# takes no request `seq`. Before TASK-054 this was 10 requests and 10 lines.
Record-Result 'one_line_per_request' ($lines.Count -eq 11) `
    ('lines={0} expected=11 (1 trace_opened marker + 1 readiness initialize + 9 calls)' -f $lines.Count)

$parsedAll = $true
$seqs = @()
$markers = 0
$markerSeqFree = $true
foreach ($line in $lines) {
    try {
        $value = ConvertFrom-Json $line
        if ($null -ne $value.PSObject.Properties['event'] -and [string]$value.event -ceq 'trace_opened') {
            $markers++
            if ($null -ne $value.PSObject.Properties['seq']) { $markerSeqFree = $false }
            continue
        }
        $seqs += [int]$value.seq
    } catch { $parsedAll = $false }
}
Record-Result 'task054_generation_marker_is_written_once_and_takes_no_seq' (($markers -eq 1) -and $markerSeqFree) `
    ('trace_opened lines={0} marker_has_no_seq={1}' -f $markers, $markerSeqFree)
$seqMonotonic = $true
for ($i = 1; $i -lt $seqs.Count; $i++) { if ($seqs[$i] -le $seqs[$i - 1]) { $seqMonotonic = $false } }
# The `-gt 0` is not decoration: an empty file would otherwise satisfy "every
# line parses and the seqs increase" vacuously.
Record-Result 'every_request_line_is_json_with_an_increasing_seq' ($parsedAll -and $seqMonotonic -and $seqs.Count -eq ($lines.Count - $markers) -and $lines.Count -gt 0) `
    ('parsed={0} lines={1} request_lines={2} seqs={3}' -f $parsedAll, $lines.Count, $seqs.Count, ($seqs -join ','))

# -----------------------------------------------------------------------------
# Part C: the analyzer has to find the friction that was really provoked.
# -----------------------------------------------------------------------------
Write-Host 'running analyze_mcp_trace.py ...'
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$analysis = & python $Analyzer $TraceFile --json $AnalysisJson 2>&1 | Out-String
$analyzerExit = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
Write-Host ''
Write-Host $analysis
Write-Host ''

Record-Result 'analyzer_exit_code_is_zero' ($analyzerExit -eq 0) ('exit={0}' -f $analyzerExit)
Record-Result 'analyzer_reports_the_fail_then_success' ($analysis -match 'fail->success' -and $analysis -match 'project_read_script') `
    ('mentions fail->success and project_read_script')
Record-Result 'analyzer_reports_the_missing_tool' ($analysis -match '-32601' -and $analysis -match 'project_get_no_such_tool_038') `
    ('mentions the -32601 clue')
Record-Result 'analyzer_reports_the_error_distribution' ($analysis -match 'error codes' -and $analysis -match '"-32001"|"-32602"') `
    ('error code distribution present')
Record-Result 'analyzer_writes_its_json' (Test-Path $AnalysisJson) ('json={0}' -f $AnalysisJson)

$userPidAfter = Get-ListenerPid -Port $UserPort
Record-Result 'guard_user_port_9877' ($userPidBefore -eq $userPidAfter) `
    ('pid_before={0} pid_after={1}' -f $userPidBefore, $userPidAfter)

Write-Host '========================== TRACE SAMPLE =========================='
foreach ($line in $lines) { Write-Host $line }
Write-Host '================================================================='

Write-Host ''
Write-Host '========================== SUMMARY =========================='
$passed = @($script:Results | Where-Object { $_.pass }).Count
$total = $script:Results.Count
foreach ($r in $script:Results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ('{0}  {1}' -f $tag, $r.id)
}
Write-Host ('{0}/{1} checks passed; trace lines={2}' -f $passed, $total, $lines.Count)
if ($passed -ne $total) { exit 1 }
exit 0
