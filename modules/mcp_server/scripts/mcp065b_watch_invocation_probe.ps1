# =============================================================================
#  mcp065b_watch_invocation_probe.ps1 -- TASK-065 section B, counterexample probe
#  for the two ways `scripts/mcp_watch_run.ps1` loses its whole observation when
#  a caller starts it the obvious way (`Start-Process ... -File <script>`).
#
#  Probe A: the array parameter bound twice, which is what a caller naturally
#           writes when the watcher has three sources to watch. Measured: a
#           non-zero exit (1) with "ParameterAlreadyBound" on stderr, no
#           watch.log header and no watch-summary.* -- i.e. no observation at
#           all, and the caller only learns it from stderr.
#           (The exit code is 1, not the script's own setup-error 2: the binding
#           error is raised by powershell.exe before mcp_watch_run.ps1 ever runs,
#           so the documented "2 = usage/setup error" contract does not cover
#           this way of losing the run.)
#  Probe B: the same three sources passed as ONE comma-separated string (the
#           workaround the first fix of this harness tried). Measured: exit 0 and
#           a summary, but `trace_path[0]` is the whole string and the watcher
#           resolves it as a single missing path -- `trace_files=1 missing=1`,
#           `trace_lines=0`, `activity_seen=0`, so the "observation" is worthless
#           while looking successful (stop_reason is still reported).
#
#  The probe does NOT modify mcp_watch_run.ps1. It writes everything under the
#  task065b evidence tree.
# =============================================================================

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'mcp065b_env.ps1')

$probeRoot = Ensure-Dir (Join-Path $EvidenceRoot 'probes')
$probeScratch = Ensure-Dir (Join-Path $env:TEMP 'mcp065b\watch-probe')
$watcherScript = Join-Path $ScriptRoot 'mcp_watch_run.ps1'
$results = New-Object System.Collections.Generic.List[object]

function Run-Probe {
    param([string]$Id, [string[]]$ExtraArgs, [string]$Note)
    $outDir = Ensure-Dir (Join-Path $probeScratch $Id)
    $marker = Join-Path $probeScratch ($Id + '.marker')
    [IO.File]::WriteAllText($marker, "probe`n", (New-Object Text.UTF8Encoding($false)))
    $outLog = Join-Path $probeRoot ($Id + '.stdout.txt')
    $errLog = Join-Path $probeRoot ($Id + '.stderr.txt')
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $watcherScript, '-Marker', $marker) + $ExtraArgs + @('-TimeoutSec', '2', '-StaleSec', '0', '-IntervalSec', '1', '-OutDir', $outDir)
    $p = Start-Process -FilePath 'powershell' -ArgumentList $args -PassThru -Wait -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $summary = Join-Path $outDir 'watch-summary.txt'
    $summaryText = ''
    if (Test-Path -LiteralPath $summary) { $summaryText = [IO.File]::ReadAllText($summary) }
    $watchLog = Join-Path $outDir 'watch.log'
    $header = ''
    if (Test-Path -LiteralPath $watchLog) {
        foreach ($line in [IO.File]::ReadAllLines($watchLog)) {
            if ($line -like '# trace_path*') { $header = $header + $line + ' | ' }
        }
    }
    $row = [ordered]@{
        id = $Id
        note = $Note
        command = ('powershell ' + ($args -join ' '))
        exit_code = $p.ExitCode
        stderr = ([IO.File]::ReadAllText($errLog)).Trim()
        watch_log_header = $header
        summary_present = (Test-Path -LiteralPath $summary)
        summary = $summaryText
        stdout_path = $outLog
        stderr_path = $errLog
    }
    $results.Add([pscustomobject]$row)
    Write-Host ('[' + $Id + '] exit=' + $p.ExitCode + ' summary=' + $row.summary_present)
    Write-Host ('  stderr: ' + $row.stderr)
    Write-Host ('  header: ' + $header)
    if ($summaryText) { foreach ($l in $summaryText.Split("`n")) { if ($l -like 'stop_reason=*' -or $l -like 'trace=*' -or $l -like 'activity_seen=*' -or $l -like 'trace_files=*' -or $l -like 'trace_lines=*') { Write-Host ('  ' + $l) } } }
}

Write-Host 'PROBE A: -TracePath bound twice through -File'
Run-Probe -Id 'A_duplicate_tracepath' -ExtraArgs @('-TracePath', 'a.jsonl', '-TracePath', 'b.jsonl') -Note 'the natural way to watch two traces; expect ParameterAlreadyBound and no summary'

Write-Host 'PROBE B: the three sources as one comma-separated string'
$oneString = ('a.jsonl,b.jsonl,c.md')
Run-Probe -Id 'B_comma_string' -ExtraArgs @('-TracePath', $oneString) -Note 'the first workaround; expect exit 0, one unresolved path, trace_files=1 missing=1'

$json = [ordered]@{
    script = 'mcp065b_watch_invocation_probe.ps1'
    watcher = $watcherScript
    probes = $results
}
$path = Join-Path $probeRoot 'watch-invocation-probe.json'
[IO.File]::WriteAllText($path, (($json | ConvertTo-Json -Depth 8)), (New-Object Text.UTF8Encoding($false)))
Write-Host ('WROTE ' + $path)

$expectA = ($results[0].exit_code -ne 0) -and ($results[0].summary_present -eq $false) -and
           ([string]::IsNullOrWhiteSpace([string]$results[0].watch_log_header)) -and
           ([string]$results[0].stderr -match 'TracePath|Parameter')
$expectB = ($results[1].exit_code -eq 0) -and ($results[1].summary_present -eq $true) -and ($results[1].watch_log_header -match ',') -and ($results[1].summary -match 'trace_files=1')
Write-Host ('PROBE A reproduced the observation loss: ' + $expectA)
Write-Host ('PROBE B reproduced the silent one-path watch: ' + $expectB)
if ($expectA -and $expectB) { Write-Host 'WATCH-INVOCATION PROBE: PASS (both failure modes reproduced)'; exit 0 }
Write-Host 'WATCH-INVOCATION PROBE: FAIL (a failure mode did not reproduce)'
exit 1