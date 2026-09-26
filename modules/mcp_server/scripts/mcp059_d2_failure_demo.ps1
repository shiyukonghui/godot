# =============================================================================
#  mcp059_d2_failure_demo.ps1 -- TASK-059 D-2: make the fixed assertion FAIL.
#
#  Why this file exists (the rule it enforces):
#  `mcp057_settings_publish_evidence.ps1` used to end with a predicate that was a
#  constant `$true`, so its final check could never fail. TASK-059 replaced it
#  with a real assertion, but "a check that has never been shown to fail" is only
#  marginally better than a tautology -- a new assertion can be wrong in the
#  other direction (always false, or reading the wrong variable) and no amount of
#  green runs would say so.
#
#  So this script manufactures EXACTLY the condition that check claims to detect,
#  runs the real evidence script unmodified, and requires it to exit non-zero.
#  Then it cleans up and re-runs the same script to show it goes green again.
#  Three states, three verdicts:
#
#    1. BASELINE   : no leftover       -> evidence script exit 0, check PASS
#    2. MANUFACTURED: one leftover     -> evidence script exit 1, check FAIL
#    3. RESTORED   : leftover gone     -> evidence script exit 0, check PASS
#
#  The manufactured leftover is a copy of `cmd.exe` whose FILE NAME contains
#  "godot" and whose command line contains the evidence script's scratch prefix
#  (`%TEMP%\mcp057`), which is exactly how `Stop-ScratchEngineProcesses` selects
#  its targets (process name like '%godot%' AND command line naming the scratch
#  root). It is a real, independent process the sweep really has to kill -- not a
#  stub that fakes the count. It is NOT the user's editor: 9877 is never touched,
#  never started, never killed.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp059_d2_failure_demo.ps1
# =============================================================================

param(
    [int]$TimeoutSeconds = 1800,
    [switch]$SkipBaseline
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Evidence = Join-Path $PSScriptRoot 'mcp057_settings_publish_evidence.ps1'
$ScratchPrefix = Join-Path $env:TEMP 'mcp057'
$FakeExe = Join-Path $ScratchPrefix 'mcp059_fake_godot.exe'
$OutRoot = Join-Path $env:TEMP ('mcp059\d2-demo\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$script:Failures = 0

function Say([string]$Text) {
    Write-Host $Text
}

function Check([string]$Id, [bool]$Ok, [string]$EvidenceText) {
    $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
    if (-not $Ok) { $script:Failures++ }
    Write-Host ("[{0}] {1} :: {2}" -f $tag, $Id, $EvidenceText)
}

function Get-Leftover {
    # The same selector `Stop-ScratchEngineProcesses` uses, without stopping
    # anything: this script inspects and only the evidence script kills.
    $found = @()
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "name like '%godot%'")) {
        if ($p.CommandLine -and $p.CommandLine.Contains($ScratchPrefix)) {
            $found += [pscustomobject]@{ pid = $p.ProcessId; name = $p.Name }
        }
    }
    return $found
}

function Invoke-Evidence([string]$Label) {
    $log = Join-Path $OutRoot ($Label + '.console.txt')
    $summaryLog = Join-Path $OutRoot ($Label + '.summary.txt')
    Say ("--- running the evidence script ({0}) ---" -f $Label)
    # `cmd /c` so the exit code survives; output is teed to a file, never piped
    # through something that would swallow the code.
    & cmd /c ("powershell -NoProfile -ExecutionPolicy Bypass -File `"{0}`" > `"{1}`" 2>&1" -f $Evidence, $log)
    $code = $LASTEXITCODE
    $text = ''
    if (Test-Path $log) { $text = [IO.File]::ReadAllText($log) }
    [IO.File]::WriteAllText($summaryLog, ($text + "`nEXIT_CODE=" + $code + "`n"))
    $line = ''
    foreach ($candidate in ($text -split "`n")) {
        if ($candidate.Contains('p2_no_scratch_engine_process_left')) { $line = $candidate.Trim(); break }
    }
    Say ("    exit code = {0}" -f $code)
    Say ("    check line = {0}" -f $line)
    return @{ code = $code; text = $text; line = $line; log = $log }
}

function Start-FakeLeftover {
    if (-not (Test-Path $ScratchPrefix)) { New-Item -ItemType Directory -Force -Path $ScratchPrefix | Out-Null }
    Copy-Item -Path (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination $FakeExe -Force
    # A long, harmless command line that NAMES the scratch prefix, so the very
    # selector the evidence script uses has to match it.
    $arguments = @('/c', ('echo {0} & ping -n 600 127.0.0.1 > nul' -f $ScratchPrefix))
    $handle = Start-Process -FilePath $FakeExe -ArgumentList $arguments -PassThru -WindowStyle Hidden
    return $handle
}

Write-Host '============================================================='
Write-Host ' TASK-059 D-2: failure demonstration for the fixed assertion'
Write-Host (' evidence script : ' + $Evidence)
Write-Host (' scratch prefix  : ' + $ScratchPrefix)
Write-Host (' output          : ' + $OutRoot)
Write-Host '============================================================='

# ---------------------------------------------------------------------------
# 0. State the selector is real before anything is manufactured.
# ---------------------------------------------------------------------------
$before = @(Get-Leftover)
Check 'd2_no_leftover_before_the_demo' ($before.Count -eq 0) ("processes matching the sweep selector: {0}" -f (($before | ForEach-Object { $_.pid }) -join ','))

$baseline = $null
if (-not $SkipBaseline) {
    # -----------------------------------------------------------------------
    # 1. BASELINE: the fixed assertion is green on a clean machine.
    # -----------------------------------------------------------------------
    $baseline = Invoke-Evidence 'baseline'
    Check 'd2_baseline_evidence_exits_zero' ($baseline.code -eq 0) ("baseline exit code = {0}" -f $baseline.code)
    Check 'd2_baseline_check_passes' ($baseline.line.Contains('[PASS]') -and ($baseline.code -eq 0)) ("{0}" -f $baseline.line)
} else {
    Say '--- baseline run skipped by -SkipBaseline ---'
}

# ---------------------------------------------------------------------------
# 2. MANUFACTURED: one real leftover whose command line names the scratch root.
# ---------------------------------------------------------------------------
$fake = $null
try {
    $fake = Start-FakeLeftover
    Start-Sleep -Milliseconds 1500
    $during = @(Get-Leftover)
    $ourPid = @($during | Where-Object { $_.pid -eq $fake.Id })
    Check 'd2_leftover_is_visible_to_the_selector' ($ourPid.Count -eq 1) `
        ("manufactured pid={0} name={1}; selector found {2} process(es): {3}" -f $fake.Id, $fake.ProcessName, $during.Count, (($during | ForEach-Object { '{0}:{1}' -f $_.pid, $_.name }) -join ','))

    $manufactured = Invoke-Evidence 'manufactured'
    Check 'd2_manufactured_evidence_exits_nonzero' ($manufactured.code -ne 0) `
        ("WITH a leftover present the evidence script exits {0} (the old tautology could only ever exit 0 here)" -f $manufactured.code)
    Check 'd2_manufactured_check_reports_fail' ($manufactured.line.Contains('[FAIL]')) ("{0}" -f $manufactured.line)
} finally {
    if ($null -ne $fake -and -not $fake.HasExited) {
        # The evidence script's own sweep should already have killed it; this is
        # the belt-and-braces path so the demo cannot leave anything running.
        Start-Sleep -Milliseconds 500
        if (-not $fake.HasExited) { & taskkill /PID $fake.Id /T /F *> (Join-Path $OutRoot 'fake.taskkill.log') }
    }
    if (Test-Path $FakeExe) { Remove-Item -Force $FakeExe }
    # Any straggler matching the selector (e.g. a `ping` child) is stopped here.
    foreach ($p in @(Get-Leftover)) {
        & taskkill /PID $p.pid /T /F *> (Join-Path $OutRoot ('cleanup-' + $p.pid + '.log'))
    }
    Start-Sleep -Milliseconds 1000
}

# ---------------------------------------------------------------------------
# 3. RESTORED: the machine is clean again and the same script is green again.
#    This is the "clean up -> restore" half: the demonstration must not leave
#    the environment in the failing state it created.
# ---------------------------------------------------------------------------
$left = @(Get-Leftover)
Check 'd2_no_leftover_after_the_cleanup' ($left.Count -eq 0) ("processes matching the sweep selector: {0}" -f (($left | ForEach-Object { $_.pid }) -join ','))
Check 'd2_fake_binary_removed' (-not (Test-Path $FakeExe)) ("{0} removed" -f $FakeExe)

$restored = Invoke-Evidence 'restored'
Check 'd2_restored_evidence_exits_zero' ($restored.code -eq 0) ("restored exit code = {0}" -f $restored.code)
Check 'd2_restored_check_passes' ($restored.line.Contains('[PASS]')) ("{0}" -f $restored.line)

Write-Host ''
Write-Host '--- summary ---'
Write-Host ('--- exit codes: baseline={0} manufactured={1} restored={2} ---' -f `
    $(if ($null -ne $baseline) { $baseline.code } else { 'skipped' }), $manufactured.code, $restored.code)
Write-Host ('--- demo failures: {0} ---' -f $script:Failures)
Write-Host ('--- output root: {0} ---' -f $OutRoot)
if ($script:Failures -gt 0) { Write-Host ('D2 FAILURE DEMO INCONCLUSIVE: {0}' -f $script:Failures); exit 1 }
Write-Host 'D2 FAILURE DEMO PASS (a leftover makes the fixed check fail, a clean machine makes it pass)'
exit 0
