# =============================================================================
#  mcp073_plan_compare_probe.ps1 -- TASK-073 A: the insertion probe for
#  `mcp073_default_plan_compare.ps1`.
#
#  WHY: a check that has never been observed to go red is not a check (the module
#  has been burned by exactly that shape, TASK-059 D-2 / TASK-069). The plan
#  comparison asserts "the default step plan did not change"; this probe makes
#  that assertion fail on purpose, in three steps, and then proves it did not
#  touch the real driver:
#
#    P1  the untouched driver against its own baseline        -> PASS, 5/5
#    P2  the same driver with ONE synthetic `Invoke-Step 'mcp073_probe_extra_step'`
#        inserted, handed to the checker through its `-CurrentFile` test seam
#                                                             -> FAIL on
#        `g3p_default_default_plan_is_identical_in_order_and_content`
#    P3  the same synthetic driver with the tagged double step REMOVED
#                                                             -> FAIL on
#        `g3p_double_mode_adds_exactly_one_step_named_gate3_double_variant`
#    P4  the real driver file on disk is byte-identical before and after
#
#  The synthetic copies live in `%TEMP%`; nothing in the repository is written.
#
#  USAGE
#  -----
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp073_plan_compare_probe.ps1 `
#        -RepoRoot <abs repo> -BaselineRevision 8ffb92b4b -EvidenceDir <absolute dir>
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$RepoRoot = '',
    [string]$BaselineRevision = '',
    [string]$GateScript = 'modules/mcp_server/scripts/mcp059_gates.ps1',
    [string]$EvidenceDir = ''
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
} else {
    $RepoRoot = (Resolve-Path $RepoRoot).Path
}
if ([string]::IsNullOrWhiteSpace($BaselineRevision)) {
    Write-Host 'mcp073_plan_compare_probe: -BaselineRevision is required.'
    exit 3
}
$Root = Join-Path $env:TEMP ('mcp073\plan-probe\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $Root | Out-Null
$Root = (Resolve-Path $Root).Path
if ([string]::IsNullOrWhiteSpace($EvidenceDir)) { $EvidenceDir = $Root }
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$EvidenceDir = (Resolve-Path $EvidenceDir).Path

$Checker = Join-Path $PSScriptRoot 'mcp073_default_plan_compare.ps1'
$Driver = Join-Path $RepoRoot ($GateScript -replace '/', '\')
$Marker = 'MCP073-ONLY-IN-DOUBLE-MODE'

$script:Failures = 0
$script:Rows = New-Object System.Collections.Generic.List[string]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    if (-not $Pass) { $script:Failures++ }
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
    $script:Rows.Add(("[{0}] {1} :: {2}" -f $tag, $Id, $Evidence))
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Invoke-Checker {
    param([string]$CurrentFile, [string]$Tag)
    $log = Join-Path $Root ($Tag + '.log')
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Checker,
        '-RepoRoot', $RepoRoot,
        '-BaselineRevision', $BaselineRevision,
        '-GateScript', $GateScript,
        '-EvidenceDir', $Root)
    if (-not [string]::IsNullOrWhiteSpace($CurrentFile)) { $arguments += @('-CurrentFile', $CurrentFile) }
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & powershell @arguments *> $log
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    $text = [IO.File]::ReadAllText($log)
    return [pscustomobject]@{ exit = $code; log = $log; text = $text }
}

Write-Host '============================================================='
Write-Host ' TASK-073 A: the plan-comparison insertion probe'
Write-Host (' repo     : ' + $RepoRoot)
Write-Host (' driver   : ' + $Driver)
Write-Host (' checker  : ' + $Checker)
Write-Host (' probe dir: ' + $Root)
Write-Host '============================================================='

$driverShaBefore = Get-Sha256 $Driver
$driverText = [IO.File]::ReadAllText($Driver)

# --- P1: the untouched driver, through the real path ------------------------
$p1 = Invoke-Checker -CurrentFile '' -Tag 'p1_untouched'
$p1Ok = ($p1.exit -eq 0) -and ($p1.text -match 'DEFAULT PLAN COMPARE PASS')
Check 'p1_untouched_driver_passes_the_plan_comparison' $p1Ok `
    ('exit={0}; the driver on disk passes every check (this is the green side of the probe)' -f $p1.exit)

# --- P2: one extra step inserted into a COPY --------------------------------
$copyExtra = Join-Path $Root 'driver_with_extra_step.ps1'
$extraText = $driverText -replace "(?m)^(.*Invoke-Step 't059_d2_failure_demo'.*)$", "`$1`r`n    `$null = Invoke-Step 'mcp073_probe_extra_step' 'cmd' @('/c', 'exit 0')"
[IO.File]::WriteAllText($copyExtra, $extraText)
$hasExtra = $extraText.Contains("mcp073_probe_extra_step")
$p2 = Invoke-Checker -CurrentFile $copyExtra -Tag 'p2_extra_step'
$p2Ok = ($p2.exit -ne 0) -and ($p2.text -match 'g3p_default_default_plan_is_identical_in_order_and_content') -and ($p2.text -match '\[FAIL\]')
Check 'p2_one_inserted_step_makes_the_comparison_go_red' ($hasExtra -and $p2Ok) `
    ('synthetic copy carries the extra step = {0}; checker exit={1} (must be non-zero); it names the failing check = {2}' -f $hasExtra, $p2.exit, ($p2.text -match 'g3p_default_default_plan_is_identical_in_order_and_content'))

# --- P3: the tagged double step removed from a COPY -------------------------
$copyNoDouble = Join-Path $Root 'driver_without_double_step.ps1'
$kept = @($driverText -split "`n" | Where-Object { -not $_.Contains($Marker) })
[IO.File]::WriteAllLines($copyNoDouble, $kept)
$p3 = Invoke-Checker -CurrentFile $copyNoDouble -Tag 'p3_no_double_step'
$p3Ok = ($p3.exit -ne 0) -and ($p3.text -match 'g3p_double_mode_adds_exactly_one_step_named_gate3_double_variant') -and ($p3.text -match '\[FAIL\]')
Check 'p3_dropping_the_tagged_step_makes_the_comparison_go_red' $p3Ok `
    ('checker exit={0} (must be non-zero); it names the double-mode check = {1}' -f $p3.exit, ($p3.text -match 'g3p_double_mode_adds_exactly_one_step_named_gate3_double_variant'))

# --- P4: the real driver was never written ---------------------------------
$driverShaAfter = Get-Sha256 $Driver
Check 'p4_the_real_driver_is_byte_identical_after_the_probe' ($driverShaBefore -eq $driverShaAfter) `
    ('sha256 before={0} after={1} (the probe only ever reads it; the synthetic copies are in {2})' -f $driverShaBefore, $driverShaAfter, $Root)

$probeText = Join-Path $EvidenceDir 'gate3_plan_compare_probe.txt'
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('TASK-073 A -- insertion probe for the default-plan comparison')
$lines.Add('repo              = ' + $RepoRoot)
$lines.Add('baseline revision = ' + $BaselineRevision)
$lines.Add('driver            = ' + $Driver)
$lines.Add('driver sha256     = ' + $driverShaBefore)
$lines.Add('probe dir         = ' + $Root)
$lines.Add('')
$lines.Add('--- P1 untouched driver (green side), exit ' + $p1.exit + ' ---')
$lines.Add($p1.text)
$lines.Add('--- P2 one inserted step into a COPY, exit ' + $p2.exit + ' (RED on purpose) ---')
$lines.Add($p2.text)
$lines.Add('--- P3 tagged double step removed from a COPY, exit ' + $p3.exit + ' (RED on purpose) ---')
$lines.Add($p3.text)
$lines.Add('')
$lines.Add('checks = ' + $script:Rows.Count + ' failures ' + $script:Failures)
$lines.Add('')
foreach ($row in $script:Rows) { $lines.Add($row) }
[IO.File]::WriteAllLines($probeText, $lines.ToArray())

Write-Host ''
Write-Host ('  probe transcript: ' + $probeText)
Write-Host ('  checks          : {0} failures {1}' -f $script:Rows.Count, $script:Failures)
Write-Host ('PLAN_COMPARE_PROBE RESULT={0} p1_exit={1} p2_exit={2} p3_exit={3}' -f $(if ($script:Failures -eq 0) { 'PASS' } else { 'FAIL' }), $p1.exit, $p2.exit, $p3.exit)
if ($script:Failures -gt 0) {
    Write-Host ('PLAN COMPARE PROBE FAILED: {0}' -f $script:Failures)
    exit 1
}
Write-Host 'PLAN COMPARE PROBE PASS'
exit 0
