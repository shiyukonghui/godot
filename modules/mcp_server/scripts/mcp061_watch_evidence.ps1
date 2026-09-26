# =============================================================================
#  mcp061_watch_evidence.ps1 -- TASK-061 evidence generator (pure ASCII).
#
#  Runs the four constructs REPORT-061 must show, with the real watcher and a
#  real blocking call each time:
#
#    S1 marker    : a helper process writes the marker after 10 s
#                   -> expect stop_reason=marker,  exit 0
#    S2 timeout   : no marker, no activity, budget 12 s, stale disabled
#                   -> expect stop_reason=timeout, exit 0
#    S3 stale     : a few trace lines exist, then nothing is appended,
#                   -StaleSec 10 -> expect stop_reason=stale, exit 0
#    S4 counterexample: "development still in progress" (a helper keeps
#                   appending trace lines every 3 s), marker absent, budget
#                   elapsed -> the watcher must SAY stop_reason=timeout
#                   instead of ending silently
#    S5 old-protocol contrast: the round-2 watchdog (watch.ps1, TASK-060
#                   evidence) is run against the SAME "in progress" state; it
#                   ends on its budget with no machine-readable reason at all.
#                   The copy differs from the original in TWO constant strings
#                   only ($scratch and $log, redirected to scratch); the diff
#                   is printed below and filed.
#
#  Time is compressed for S2/S4/S5 (budget in seconds instead of the protocol's
#  4500/1500 s). The semantics under test - "marker absent, budget elapsed" - is
#  unchanged; REPORT-061 states the compression explicitly.
#
#  Nothing is killed, no port is probed, port 9877 is never touched. All
#  scratch lives under %TEMP%\task061 (the round-2 %TEMP%\mcp-breakout is NOT
#  touched); evidence is copied into
#  modules/mcp_server/docs/reports/evidence/task061/.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp061_watch_evidence.ps1
#  Exit code 0 = every scenario produced its expected stop reason.
# =============================================================================

$ErrorActionPreference = 'Stop'
$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Scripts = Join-Path $RepoRoot 'modules\mcp_server\scripts'
$Watcher = Join-Path $Scripts 'mcp_watch_run.ps1'
$Evidence = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task061'
$Base = Join-Path $env:TEMP 'task061'
$PwshExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$OldWatch = Join-Path $RepoRoot 'docs\reports\evidence\task060\c-obs\watch.ps1'

function New-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-Lines([string]$Path, [string[]]$Lines) {
    # LF-only: the repository stores text as LF (.gitattributes `* text=auto
    # eol=lf`), so LF here keeps every published evidence sha256 equal to the
    # sha256 of the committed blob (a CRLF worktree would not verify from a
    # fresh clone).
    [System.IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), $Utf8NoBom)
}

function Add-JsonLine([string]$Path, [int]$Number) {
    $line = '{"id":' + $Number + ',"seq":' + $Number + ',"ts_ms":0,"connection":1,"method":"tools/call","ok":true,"tool":"demo_tool"}'
    [System.IO.File]::AppendAllText($Path, $line + "`n", $Utf8NoBom)
}

function Invoke-Watcher([string[]]$ArgList, [string]$OutDir) {
    New-Dir $OutDir
    $stdoutPath = Join-Path $OutDir 'stdout.txt'
    $savedEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $all = & $PwshExe -NoProfile -ExecutionPolicy Bypass -File $Watcher @ArgList 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $savedEap
    Write-Lines $stdoutPath ([string[]]@($all | ForEach-Object { [string]$_ }))
    $last = ''
    foreach ($row in @($all)) {
        if (([string]$row).StartsWith('WATCH_STOP ')) { $last = [string]$row }
    }
    return @{ code = $code; stdout = $stdoutPath; last = $last }
}

function Get-Reason([string]$StopLine) {
    $m = [regex]::Match($StopLine, 'stop_reason=([a-z]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Copy-Evidence([string]$FromDir, [string]$ToName) {
    $to = Join-Path $Evidence $ToName
    New-Dir $to
    if (Test-Path -LiteralPath $FromDir) {
        Get-ChildItem -Path $FromDir -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $to -Force }
    }
}

# --------------------------------------------------------------- prepare -----
Remove-Item -LiteralPath $Base -Recurse -Force -ErrorAction SilentlyContinue
New-Dir $Base
New-Dir $Evidence

# Helpers the scenarios start as separate processes (never killed, only waited).
$HelperMarker = Join-Path $Base 'helper-marker.ps1'
Write-Lines $HelperMarker @(
    'param([string]$Marker,[int]$DelaySec)',
    'Start-Sleep -Seconds $DelaySec',
    'New-Item -ItemType File -Force -Path $Marker | Out-Null'
)
$HelperAppend = Join-Path $Base 'helper-append.ps1'
Write-Lines $HelperAppend @(
    'param([string]$Trace,[int]$Count,[int]$EverySec,[int]$StartSeq)',
    '$enc = New-Object System.Text.UTF8Encoding($false)',
    'for ($i = 1; $i -le $Count; $i++) {',
    '    $n = $StartSeq + $i',
    '    $line = ''{"id":'' + $n + '',"seq":'' + $n + '',"ts_ms":0,"connection":1,"method":"tools/call","ok":true,"tool":"demo_tool"}''',
    '    [System.IO.File]::AppendAllText($Trace, $line + "`n", $enc)',
    '    Start-Sleep -Seconds $EverySec',
    '}'
)

$results = New-Object System.Collections.ArrayList
$route = New-Object System.Collections.ArrayList

# ------------------------------------------------------------------- S1 ------
$s1 = Join-Path $Base 's1-marker'
New-Dir $s1
$s1Trace = Join-Path $s1 'trace-editor.jsonl'
$s1Marker = Join-Path $s1 'DEV-DONE.marker'
Add-JsonLine $s1Trace 1
Add-JsonLine $s1Trace 2
Add-JsonLine $s1Trace 3
$s1Writer = Start-Process -FilePath $PwshExe -PassThru -WindowStyle Hidden `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $HelperMarker, '-Marker', $s1Marker, '-DelaySec', '10')
$s1Run = Invoke-Watcher @('-Marker', $s1Marker, '-TracePath', $s1Trace, '-TimeoutSec', '120', '-StaleSec', '0', '-IntervalSec', '2', '-OutDir', (Join-Path $s1 'watch')) (Join-Path $s1 'watch')
$s1Writer.WaitForExit()
$s1Reason = Get-Reason $s1Run.last
$s1Ok = (($s1Reason -eq 'marker') -and ($s1Run.code -eq 0))
[void]$results.Add('S1_marker expected=marker actual=' + $s1Reason + ' exit=' + $s1Run.code + ' ' + $(if ($s1Ok) { 'PASS' } else { 'FAIL' }))
[void]$route.Add('S1 t+' + ((Get-Date).ToString('HH:mm:ss', $InvariantCulture)) + ' reason=' + $s1Reason)
Copy-Evidence (Join-Path $s1 'watch') 's1-marker'
Copy-Item -LiteralPath $s1Trace -Destination (Join-Path $Evidence 's1-marker') -Force

# ------------------------------------------------------------------- S2 ------
$s2 = Join-Path $Base 's2-timeout'
New-Dir $s2
$s2Trace = Join-Path $s2 'trace-editor.jsonl'
$s2Marker = Join-Path $s2 'DEV-DONE.marker'
Add-JsonLine $s2Trace 1
Add-JsonLine $s2Trace 2
$s2Run = Invoke-Watcher @('-Marker', $s2Marker, '-TracePath', $s2Trace, '-TimeoutSec', '12', '-StaleSec', '600', '-IntervalSec', '2', '-OutDir', (Join-Path $s2 'watch')) (Join-Path $s2 'watch')
$s2Reason = Get-Reason $s2Run.last
$s2Ok = (($s2Reason -eq 'timeout') -and ($s2Run.code -eq 0))
[void]$results.Add('S2_timeout expected=timeout actual=' + $s2Reason + ' exit=' + $s2Run.code + ' ' + $(if ($s2Ok) { 'PASS' } else { 'FAIL' }))
[void]$route.Add('S2 t+' + ((Get-Date).ToString('HH:mm:ss', $InvariantCulture)) + ' reason=' + $s2Reason)
Copy-Evidence (Join-Path $s2 'watch') 's2-timeout'

# ------------------------------------------------------------------- S3 ------
$s3 = Join-Path $Base 's3-stale'
New-Dir $s3
$s3Trace = Join-Path $s3 'trace-editor.jsonl'
$s3Marker = Join-Path $s3 'DEV-DONE.marker'
for ($i = 1; $i -le 5; $i++) { Add-JsonLine $s3Trace $i }
$s3Run = Invoke-Watcher @('-Marker', $s3Marker, '-TracePath', $s3Trace, '-TimeoutSec', '300', '-StaleSec', '10', '-IntervalSec', '2', '-OutDir', (Join-Path $s3 'watch')) (Join-Path $s3 'watch')
$s3Reason = Get-Reason $s3Run.last
$s3Ok = (($s3Reason -eq 'stale') -and ($s3Run.code -eq 0))
[void]$results.Add('S3_stale expected=stale actual=' + $s3Reason + ' exit=' + $s3Run.code + ' ' + $(if ($s3Ok) { 'PASS' } else { 'FAIL' }))
[void]$route.Add('S3 t+' + ((Get-Date).ToString('HH:mm:ss', $InvariantCulture)) + ' reason=' + $s3Reason)
Copy-Evidence (Join-Path $s3 'watch') 's3-stale'

# ------------------------------------------------------------------- S4 ------
# Counterexample: development is STILL RUNNING (trace grows every 3 s), the
# marker is absent and the budget elapses. The old protocol ended here without
# saying anything; the new watcher must name the reason.
$s4 = Join-Path $Base 's4-in-progress'
New-Dir $s4
$s4Trace = Join-Path $s4 'trace-editor.jsonl'
$s4Marker = Join-Path $s4 'DEV-DONE.marker'
Add-JsonLine $s4Trace 1
$s4Writer = Start-Process -FilePath $PwshExe -PassThru -WindowStyle Hidden `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $HelperAppend, '-Trace', $s4Trace, '-Count', '10', '-EverySec', '3', '-StartSeq', '1')
$s4Run = Invoke-Watcher @('-Marker', $s4Marker, '-TracePath', $s4Trace, '-TimeoutSec', '20', '-StaleSec', '6000', '-IntervalSec', '2', '-OutDir', (Join-Path $s4 'watch')) (Join-Path $s4 'watch')
$s4Reason = Get-Reason $s4Run.last
# The development is allowed to finish (it must NOT be killed); we only wait.
$s4Writer.WaitForExit()
$s4Ok = (($s4Reason -eq 'timeout') -and ($s4Run.code -eq 0))
[void]$results.Add('S4_counterexample expected=timeout actual=' + $s4Reason + ' exit=' + $s4Run.code + ' ' + $(if ($s4Ok) { 'PASS' } else { 'FAIL' }))
[void]$route.Add('S4 t+' + ((Get-Date).ToString('HH:mm:ss', $InvariantCulture)) + ' reason=' + $s4Reason)
Copy-Evidence (Join-Path $s4 'watch') 's4-counterexample'
Copy-Item -LiteralPath $s4Trace -Destination (Join-Path $Evidence 's4-counterexample') -Force

# ------------------------------------------------------------------- S5 ------
# Old-protocol contrast. The round-2 watchdog is copied with exactly TWO
# constant strings replaced (its scratch dir and its log path); nothing else.
function Invoke-Scenario5 {
    $s5 = Join-Path $Base 's5-old-protocol'
    New-Dir $s5
    $s5Trace = Join-Path $s5 'trace-editor.jsonl'
    $s5Marker = Join-Path $s5 'DEV-DONE.marker'
    Add-JsonLine $s5Trace 1
    $s5Old = Join-Path $s5 'watch-old.ps1'
    $oldText = [System.IO.File]::ReadAllText($OldWatch)
    $newText = $oldText.Replace("Join-Path `$env:TEMP 'mcp-breakout'", "'" + $s5 + "'")
    $newText = $newText.Replace("'F:\RustProjects\godot-mcp-pro\code\godot\docs\reports\evidence\task060\c-obs\watch.log'", "'" + (Join-Path $s5 'watch.log') + "'")
    [System.IO.File]::WriteAllText($s5Old, $newText, $Utf8NoBom)
    $oldDiff = New-Object System.Collections.ArrayList
    $oldLines = $oldText.Split("`n")
    $newLines = $newText.Split("`n")
    for ($i = 0; $i -lt [Math]::Min($oldLines.Length, $newLines.Length); $i++) {
        if ($oldLines[$i] -ne $newLines[$i]) {
            [void]$oldDiff.Add('line ' + ($i + 1) + ' OLD: ' + $oldLines[$i].TrimEnd("`r"))
            [void]$oldDiff.Add('line ' + ($i + 1) + ' NEW: ' + $newLines[$i].TrimEnd("`r"))
        }
    }
    $diffLines = New-Object System.Collections.ArrayList
    [void]$diffLines.Add('original : ' + $OldWatch)
    [void]$diffLines.Add('copy     : ' + $s5Old)
    [void]$diffLines.Add('original_sha256 : ' + (Get-FileHash -LiteralPath $OldWatch -Algorithm SHA256).Hash.ToLower())
    [void]$diffLines.Add('copy_sha256     : ' + (Get-FileHash -LiteralPath $s5Old -Algorithm SHA256).Hash.ToLower())
    [void]$diffLines.Add('changed_lines   : ' + [int]($oldDiff.Count / 2))
    foreach ($d in @($oldDiff)) { [void]$diffLines.Add($d) }
    Write-Lines (Join-Path $s5 'transformation-diff.txt') ([string[]]$diffLines.ToArray())

    $s5Writer = Start-Process -FilePath $PwshExe -PassThru -WindowStyle Hidden `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $HelperAppend, '-Trace', $s5Trace, '-Count', '10', '-EverySec', '3', '-StartSeq', '1')
    $savedEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $s5All = & $PwshExe -NoProfile -ExecutionPolicy Bypass -File $s5Old -BudgetSeconds 20 -IntervalSeconds 4 2>&1
    $s5Code = $LASTEXITCODE
    $ErrorActionPreference = $savedEap
    Write-Lines (Join-Path $s5 'stdout.txt') ([string[]]@($s5All | ForEach-Object { [string]$_ }))
    $s5Writer.WaitForExit()
    $s5Log = Join-Path $s5 'watch.log'
    $s5LogText = [System.IO.File]::ReadAllText($s5Log)
    $s5LogLast = ([string[]]($s5LogText.TrimEnd().Split("`n")))[-1].TrimEnd("`r")
    $s5StdoutText = (([string[]]@($s5All | ForEach-Object { [string]$_ })) -join "`n")
    $s5HasReason = (($s5StdoutText + "`n" + $s5LogText) -match 'stop_reason')
    # The round-2 watchdog writes CRLF (Set-Content / Add-Content). The
    # repository stores text as LF, so the copy is normalized to LF here - EOL
    # only, not one character of content - so that every published evidence
    # sha256 equals the sha256 of its committed blob.
    $s5LogText = $s5LogText.Replace("`r`n", "`n")
    [System.IO.File]::WriteAllText($s5Log, $s5LogText, $Utf8NoBom)
    $s5Ok = ((-not $s5HasReason) -and ($s5LogLast -match 'BUDGET_REACHED'))
    [void]$results.Add('S5_old_protocol silent_end=' + $(if (-not $s5HasReason) { 'yes' } else { 'no' }) + ' last_log_line=' + $s5LogLast + ' exit=' + $s5Code + ' ' + $(if ($s5Ok) { 'PASS' } else { 'FAIL' }))
    [void]$route.Add('S5 t+' + ((Get-Date).ToString('HH:mm:ss', $InvariantCulture)) + ' old_watchdog last=' + $s5LogLast)
    Copy-Evidence $s5 's5-old-protocol'
}

if (Test-Path -LiteralPath $OldWatch -PathType Leaf) {
    Invoke-Scenario5
} else {
    [void]$results.Add('S5_old_protocol SKIPPED missing_source=' + $OldWatch + ' FAIL')
}

Write-Lines (Join-Path $Evidence 'scenario-results.txt') ([string[]]$results.ToArray())
Write-Lines (Join-Path $Evidence 'route.txt') ([string[]]$route.ToArray())
Write-Lines (Join-Path $Base 'scenario-results.txt') ([string[]]$results.ToArray())

foreach ($line in @($results)) { Write-Host $line }

$failed = 0
foreach ($line in @($results)) { if ($line -match ' FAIL$') { $failed++ } }
if ($failed -gt 0) { Write-Host ('EVIDENCE_FAIL failed=' + $failed); exit 1 }
Write-Host 'EVIDENCE_OK scenarios=5'
exit 0
