# =============================================================================
#  mcp038_baseline_compare.ps1 -- TASK-038: the trace-off response bytes are the
#  bytes the pre-task binary produced.
#
#  The zero-change evidence of `mcp038_zero_change.ps1` compares three runs of
#  the *new* binary (off / off / on). This script adds the missing half: the same
#  probe set is captured once from a binary built from the tree *before* TASK-038
#  (`git checkout HEAD -- <module>` with the two new files removed) and once from
#  the TASK-038 binary, and every response is compared by sha256.
#
#  Two modes:
#
#    capture   start `<EnginePath>` on 9888 with the trace OFF, send every probe,
#              store each response body and a `hashes.txt` in `<OutDir>`
#    compare   compare the `hashes.txt` of `<OutDir>` (pre) and `<OtherDir>`
#              (post) label by label
#
#  Port discipline: 9877 is never touched, and only the process this script
#  started is killed.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp038_baseline_compare.ps1 `
#        -Mode capture -EnginePath <bin\godot...console.exe> -OutDir <dir>
#    powershell ... -Mode compare -OutDir <pre-dir> -OtherDir <post-dir>
# =============================================================================

param(
    [ValidateSet('capture', 'compare')][string]$Mode = 'capture',
    [string]$EnginePath = '',
    [string]$OutDir = '',
    [string]$OtherDir = '',
    [int]$Port = 9888,
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$ScratchRoot = Join-Path $env:TEMP 'mcp038-baseline'
$LogRoot = Join-Path $env:TEMP 'mcp038-baseline-logs'
$UserPort = 9877

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

function Invoke-Probe {
    param([string]$Directory, $Probe)
    $requestFile = Join-Path $Directory ('request-{0}.json' -f $Probe.id)
    $responseFile = Join-Path $Directory ('response-{0}.json' -f $Probe.id)
    Write-McpUtf8NoBom -Path $requestFile -Text (Get-Mcp038ProbeBody -Probe $Probe)
    if (Test-Path $responseFile) { Remove-Item $responseFile -ErrorAction SilentlyContinue }
    & curl.exe -s -o $responseFile -X POST -H 'Content-Type: application/json' `
        --data-binary ("@" + $requestFile) ("http://127.0.0.1:{0}/mcp" -f $Port) 2>$null | Out-Null
    if (-not (Test-Path $responseFile)) { return 'NO_RESPONSE' }
    return (Get-FileHash -Algorithm SHA256 -Path $responseFile).Hash
}

if ($Mode -eq 'compare') {
    if (-not (Test-Path $OutDir) -or -not (Test-Path $OtherDir)) { Write-Host 'FATAL: both directories are required'; exit 2 }
    $pre = @{}
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $OutDir 'hashes.txt'))) {
        if ($line -match '^([^|]+)\|(.+)$') { $pre[$Matches[1]] = $Matches[2] }
    }
    $post = @{}
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $OtherDir 'hashes.txt'))) {
        if ($line -match '^([^|]+)\|(.+)$') { $post[$Matches[1]] = $Matches[2] }
    }
    if ($pre.Count -eq 0 -or $post.Count -eq 0) { Write-Host 'FATAL: an empty hashes.txt'; exit 2 }

    Write-Host '============================================================='
    Write-Host ' TASK-038 pre-task vs post-task response bytes'
    Write-Host '============================================================='
    Write-Host ('pre  : {0}' -f $OutDir)
    Write-Host ('post : {0}' -f $OtherDir)
    Write-Host ''
    $same = 0
    $different = 0
    foreach ($label in ($pre.Keys | Sort-Object)) {
        $a = $pre[$label]
        $b = if ($post.ContainsKey($label)) { $post[$label] } else { 'MISSING' }
        if ($a -eq $b) {
            $same++
            Write-Host ('  [SAME] {0,-40} {1}' -f $label, $a.Substring(0, 16))
        } else {
            $different++
            Write-Host ('  [DIFF] {0,-40} pre={1} post={2}' -f $label, $a.Substring(0, 16), $b.Substring(0, 16))
        }
    }
    Write-Host ''
    Write-Host ('{0} identical, {1} different, {2} probes' -f $same, $different, $pre.Count)
    if ($different -ne 0) { exit 1 }
    exit 0
}

if ($EnginePath -eq '' -or $OutDir -eq '') { Write-Host 'FATAL: -EnginePath and -OutDir are required in capture mode'; exit 2 }
if (-not (Test-Path $EnginePath)) { Write-Host ('FATAL: engine binary not found: {0}' -f $EnginePath); exit 2 }
New-Item -ItemType Directory -Force -Path $OutDir, $ScratchRoot, $LogRoot | Out-Null

$ProjectPath = Join-Path $ScratchRoot 'project'
New-Mcp038ScratchProject -Path $ProjectPath
Write-Host ('importing scratch project {0} with {1} ...' -f $ProjectPath, (Split-Path -Leaf $EnginePath))
# `--mcp-port=0` (the helper's default) and NOT `-NoPort`: an editor process with
# no port argument falls back to the default 9877 and tries to bind the port the
# user's own editor owns. Omitting the port is not the same as asking for "no
# port"; the import must stay off every port.
Import-McpProject -Engine $EnginePath -Path $ProjectPath -LogDirectory $LogRoot -Name ('baseline-import-' + (Split-Path -Leaf $OutDir)) | Out-Null

$userPidBefore = Get-ListenerPid -Port $UserPort
$out = Join-Path $LogRoot ('baseline-' + (Split-Path -Leaf $OutDir) + '.out.log')
$err = Join-Path $LogRoot ('baseline-' + (Split-Path -Leaf $OutDir) + '.err.log')
Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
$proc = Start-Process -FilePath $EnginePath -ArgumentList @('--headless', '-e', '--path', $ProjectPath, ("--mcp-port={0}" -f $Port)) `
    -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden

$probes = New-Mcp038Probes
$ready = $false
$deadline = [DateTime]::UtcNow.AddMilliseconds($ReadyTimeoutMs)
while ([DateTime]::UtcNow -lt $deadline) {
    $probe = [pscustomobject]@{ id = 900; label = 'ready'; method = 'initialize'; name = ''; args = $null }
    $null = Invoke-Probe -Directory $OutDir -Probe $probe
    $text = ''
    $readyFile = Join-Path $OutDir 'response-900.json'
    if (Test-Path $readyFile) { $text = [IO.File]::ReadAllText($readyFile) }
    if ($text -match 'protocolVersion') { $ready = $true; break }
    Start-Sleep -Milliseconds 1000
}
if (-not $ready) {
    try { if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force } } catch { }
    Write-Host ('FATAL: the editor never became ready; log={0}' -f $out)
    exit 2
}

$lines = New-Object System.Collections.Generic.List[string]
foreach ($probe in $probes) {
    $hash = Invoke-Probe -Directory $OutDir -Probe $probe
    $lines.Add(('{0}|{1}' -f $probe.label, $hash))
    Write-Host ('  {0,-40} {1}' -f $probe.label, $hash)
}

try { if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 1200 } } catch { }
[IO.File]::WriteAllLines((Join-Path $OutDir 'hashes.txt'), $lines.ToArray())
$userPidAfter = Get-ListenerPid -Port $UserPort
Write-Host ('captured {0} probes into {1}; user editor 9877 pid {2} -> {3}' -f $probes.Count, $OutDir, $userPidBefore, $userPidAfter)
if ($userPidBefore -ne $userPidAfter) { Write-Host 'FATAL: the user editor on 9877 changed pid'; exit 2 }
exit 0