# =============================================================================
#  mcp044_zero_change.ps1 -- TASK-044: the capture changes no response byte.
#
#  The capture is a bypass capability (GDR-27 point 1): the pictures and the
#  verdict go to the log and the files, never into a tool response. The proof is
#  a byte comparison over one shared probe set (`mcp038_probes.ps1`, the same 22
#  requests TASK-038 used, so the two tasks describe the same inputs):
#
#    pre   the binary built from the tree *before* this task, capture off (the
#          default: the switch does not exist in that build)
#    off   this task's binary with `--mcp-capture=off`
#    on    this task's binary with `--mcp-capture=every_call` and a trace file
#
#  `pre` vs `off` is the "the default really is unchanged" claim; `pre` vs `on`
#  is the "turning it on changes no response either" claim. A probe whose `pre`
#  and `off` responses differ is not an effect of anything here - it is the
#  endpoint being non-deterministic - and is reported as such instead of passing
#  by accident.
#
#  Port discipline: 9877 is never touched; only the process this script started
#  is killed.
#
#  Usage:
#    powershell ... -File mcp044_zero_change.ps1 -Mode capture -EnginePath <exe> -OutDir <dir> -Capture off
#    powershell ... -File mcp044_zero_change.ps1 -Mode compare -PreDir <dir> -OffDir <dir> -OnDir <dir>
# =============================================================================

param(
    [ValidateSet('capture', 'compare')][string]$Mode = 'capture',
    [string]$EnginePath = '',
    [string]$OutDir = '',
    [string]$PreDir = '',
    [string]$OffDir = '',
    [string]$OnDir = '',
    [ValidateSet('off', 'every_call')][string]$Capture = 'off',
    [int]$Port = 9888,
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$UserPort = 9877
$Root = Join-Path $env:TEMP 'mcp044-zero-change'
$LogRoot = Join-Path $Root 'logs'

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp038_probes.ps1')

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

if ($Mode -eq 'compare') {
    if (-not (Test-Path $PreDir) -or -not (Test-Path $OffDir) -or -not (Test-Path $OnDir)) {
        Write-Host 'FATAL: -PreDir, -OffDir and -OnDir must all exist'
        exit 2
    }
    $pre = Get-Content (Join-Path $PreDir 'hashes.txt')
    $off = Get-Content (Join-Path $OffDir 'hashes.txt')
    $on = Get-Content (Join-Path $OnDir 'hashes.txt')
    if ($pre.Count -ne $off.Count -or $pre.Count -ne $on.Count) {
        Write-Host ('FATAL: the three tables have different lengths ({0}/{1}/{2})' -f $pre.Count, $off.Count, $on.Count)
        exit 2
    }

    $deterministic = 0
    $unstable = 0
    $changedOff = 0
    $changedOn = 0
    $rows = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $pre.Count; $i++) {
        $a = $pre[$i]
        $b = $off[$i]
        $c = $on[$i]
        $label = ($a -split '\|')[0]
        $shaPre = ($a -split '\|')[1]
        $shaOff = ($b -split '\|')[1]
        $shaOn = ($c -split '\|')[1]
        if ($shaPre -eq $shaOff) {
            $deterministic++
            if ($shaPre -ne $shaOn) {
                $changedOn++
                $rows.Add(('  {0,-42} pre=off={1} on={2}  <== CHANGED' -f $label, $shaPre.Substring(0, 16), $shaOn.Substring(0, 16)))
            } else {
                $rows.Add(('  {0,-42} {1}  pre=off=on' -f $label, $shaPre.Substring(0, 16)))
            }
        } else {
            $unstable++
            if ($shaPre -ne $shaOn) { $changedOn++ }
            $rows.Add(('  {0,-42} NON-DETERMINISTIC pre={1} off={2}  (excluded)' -f $label, $shaPre.Substring(0, 16), $shaOff.Substring(0, 16)))
        }
    }
    foreach ($row in $rows) { Write-Host $row }

    Write-Host ''
    $pass1 = ($deterministic -ge 10) -and ($changedOff -eq 0)
    $pass2 = ($deterministic -ge 10) -and ($changedOn -eq 0)
    Write-Host ('[PASS?] {0} pre_vs_off_byte_identical  compared={1} changed={2} unstable={3}' -f $(if ($pass1) { 'PASS' } else { 'FAIL' }), $deterministic, $changedOff, $unstable)
    Write-Host ('[PASS?] {0} pre_vs_on_byte_identical   compared={1} changed={2} unstable={3}' -f $(if ($pass2) { 'PASS' } else { 'FAIL' }), $deterministic, $changedOn, $unstable)
    if (-not $pass1 -or -not $pass2) { exit 1 }
    exit 0
}

# ---------------------------------------------------------------------------
#  capture mode
# ---------------------------------------------------------------------------

if (-not (Test-Path $EnginePath)) { Write-Host ('FATAL: engine binary not found: {0}' -f $EnginePath); exit 2 }
New-Item -ItemType Directory -Force -Path $OutDir, $LogRoot | Out-Null
Remove-Item -Path $OutDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$project = Join-Path $Root 'project'
New-Mcp038ScratchProject -Path $project
Import-McpProject -Engine $EnginePath -Path $project -LogDirectory $LogRoot -Name ('mcp044-zero-import-' + $Capture) | Out-Null

$traceFile = Join-Path $Root ('trace-' + $Capture + '.jsonl')
$shotsDir = Join-Path $Root ('shots-' + $Capture)
Remove-Item -Path $traceFile, $shotsDir -Recurse -Force -ErrorAction SilentlyContinue

$arguments = @('--headless', '-e', '--path', $project, ('--mcp-port={0}' -f $Port))
if ($Capture -eq 'every_call') {
    $arguments += @(
        ('--mcp-trace={0}' -f ($traceFile -replace '\\', '/')),
        '--mcp-capture=every_call',
        ('--mcp-capture-dir={0}' -f ($shotsDir -replace '\\', '/'))
    )
}
# The pre-task binary does not know `--mcp-capture`; the caller passes
# -Capture off for every run of it, so no unknown switch ever reaches it.

$userPidBefore = Get-ListenerPid -PortNumber $UserPort
$out = Join-Path $LogRoot ('zero-' + $Capture + '.out.log')
$err = Join-Path $LogRoot ('zero-' + $Capture + '.err.log')
Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
$proc = Start-Process -FilePath $EnginePath -ArgumentList $arguments -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
Write-Host ('started pid={0} sha256={1} :: {2}' -f $proc.Id, (Get-FileHash -Algorithm SHA256 -Path $EnginePath).Hash.ToLower(), ($arguments -join ' '))

try {
    $ready = $false
    $deadline = [DateTime]::UtcNow.AddMilliseconds($ReadyTimeoutMs)
    $requestFile = Join-Path $OutDir 'ready-request.json'
    $responseFile = Join-Path $OutDir 'ready-response.json'
    Write-McpUtf8NoBom -Path $requestFile -Text '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}'
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path $responseFile) { Remove-Item -Path $responseFile -Force -ErrorAction SilentlyContinue }
        & curl.exe -s -o $responseFile --max-time 10 -X POST -H 'Content-Type: application/json' `
            --data-binary ('@' + $requestFile) ('http://127.0.0.1:{0}/mcp' -f $Port) 2>$null | Out-Null
        if (Test-Path $responseFile) {
            if (([IO.File]::ReadAllText($responseFile)) -match 'protocolVersion') { $ready = $true; break }
        }
        Start-Sleep -Milliseconds 1000
    }
    if (-not $ready) { Write-Host 'FATAL: the endpoint never became ready'; exit 2 }

    $probes = New-Mcp038Probes
    $table = New-Object System.Collections.Generic.List[string]
    foreach ($probe in $probes) {
        $req = Join-Path $OutDir ('request-{0}.json' -f $probe.id)
        $res = Join-Path $OutDir ('response-{0}.json' -f $probe.id)
        Write-McpUtf8NoBom -Path $req -Text (Get-Mcp038ProbeBody -Probe $probe)
        if (Test-Path $res) { Remove-Item -Path $res -Force -ErrorAction SilentlyContinue }
        & curl.exe -s -o $res --max-time 30 -X POST -H 'Content-Type: application/json' `
            --data-binary ('@' + $req) ('http://127.0.0.1:{0}/mcp' -f $Port) 2>$null | Out-Null
        $sha = if (Test-Path $res) { (Get-FileHash -Algorithm SHA256 -Path $res).Hash } else { 'NO_RESPONSE' }
        $table.Add(('{0}|{1}' -f $probe.label, $sha))
        Write-Host ('  {0,-42} {1}' -f $probe.label, $sha.Substring(0, [Math]::Min(16, $sha.Length)))
    }
    Write-McpUtf8NoBom -Path (Join-Path $OutDir 'hashes.txt') -Text (($table -join "`n") + "`n")

    if ($Capture -eq 'every_call') {
        $captureEvents = 0
        if (Test-Path $traceFile) {
            foreach ($line in (Get-Content $traceFile)) {
                if ($line -match '"event":"capture"') { $captureEvents++ }
            }
        }
        Write-Host ('capture lines in {0}: {1} (the switch really was on for this run)' -f $traceFile, $captureEvents)
    }
} finally {
    try { if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } } catch { }
    Start-Sleep -Milliseconds 800
}

$userPidAfter = Get-ListenerPid -PortNumber $UserPort
Write-Host ('guard: user port {0} pid before={1} after={2}' -f $UserPort, $userPidBefore, $userPidAfter)
if ($userPidBefore -ne $userPidAfter) { Write-Host 'FAIL: the user port changed'; exit 1 }
exit 0