# =============================================================================
#  mcp050_regression_battery.ps1 -- TASK-050 regression runs, strictly serial
#  (pure ASCII).
#
#  One step at a time, one log per step, the exit code of every step recorded in
#  a summary. The batteries never overlap with each other and none of them starts
#  scons: the binary they run against is the one `scripts\build_local.cmd -Force`
#  built, whose `--version` is recorded below next to `git rev-parse --short=9
#  HEAD`.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp050_regression_battery.ps1 -Batch individual
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp050_regression_battery.ps1 -Batch batteries
# =============================================================================

param(
    [ValidateSet('individual', 'capture', 'batteries')]
    [string]$Batch = 'individual'
)

$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Scripts = Join-Path $RepoRoot 'modules\mcp_server\scripts'
$Logs = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task050\green\regression'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$Summary = Join-Path $Logs ('summary-' + $Batch + '.txt')
Set-Content -Path $Summary -Value '' -Encoding ASCII
Set-Location $RepoRoot

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ("===== STEP {0} =====" -f $Name)
    $out = Join-Path $Logs ($Name + '.log')
    $started = Get-Date
    & $Body *> $out
    $rc = $LASTEXITCODE
    $line = ('STEP {0} EXIT {1} ({2:n0}s)' -f $Name, $rc, ((Get-Date) - $started).TotalSeconds)
    Add-Content -Path $Summary -Value $line -Encoding ASCII
    Write-Host $line
}

function Invoke-Ps1 {
    param([string]$Name, [string]$Script, [string[]]$Extra = @())
    Invoke-Step $Name { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts $Script) @Extra }
}

Add-Content -Path $Summary -Value ('TASK-050 regression battery: ' + $Batch) -Encoding ASCII
Add-Content -Path $Summary -Value ('binary --version: ' + (& $Engine --version)) -Encoding ASCII
Add-Content -Path $Summary -Value ('git HEAD: ' + (& git -C $RepoRoot rev-parse HEAD)) -Encoding ASCII
Add-Content -Path $Summary -Value ('git HEAD short: ' + (& git -C $RepoRoot rev-parse --short=9 HEAD)) -Encoding ASCII

if ($Batch -eq 'individual') {
    Invoke-Step 'gate6c_coverage_probes' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp031_gate6_coverage_probes.ps1') }
    Invoke-Ps1 -Name 'regress_mcp010_b2_observation' -Script 'mcp010_b2_observation_evidence.ps1'
    Invoke-Ps1 -Name 'regress_mcp019_b4' -Script 'mcp019_b4_evidence.ps1'
    Invoke-Ps1 -Name 'regress_mcp027_object_shape_and_paths' -Script 'mcp027_object_shape_and_paths_evidence.ps1'
} elseif ($Batch -eq 'capture') {
    # The invocation list MILESTONES-CLOSURE section 4 and REPORT-048 section 7
    # use for these three: the four phases TASK-044/045/046 really ran, with the
    # labels their reports record. `mcp044_zero_change.ps1` is deliberately NOT
    # in the list: its `pre` leg needs the binary built *before* TASK-044, which
    # cannot be rebuilt from this revision, so it is attributed in the report
    # instead of being run against a stand-in.
    Invoke-Ps1 -Name 'regress_mcp044_capture_editor' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'editor')
    Invoke-Ps1 -Name 'regress_mcp044_capture_headless' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'headless')
    Invoke-Ps1 -Name 'regress_mcp044_capture_game' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'game')
    Invoke-Ps1 -Name 'regress_mcp044_capture_diff_image' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'diff-image')
    Invoke-Ps1 -Name 'regress_mcp045_pixel_compare_cost' -Script 'mcp045_pixel_compare_cost.ps1' -Extra @('-Label', 'post')
    Invoke-Ps1 -Name 'regress_mcp046_capture_encode_cost' -Script 'mcp046_capture_encode_cost.ps1' -Extra @('-Label', 'post')
} else {
    Invoke-Ps1 -Name 'regress_mcp041_gates' -Script 'mcp041_gates.ps1'
    Invoke-Ps1 -Name 'regress_mcp042_gates' -Script 'mcp042_gates.ps1'
    Invoke-Ps1 -Name 'regress_mcp043_gates' -Script 'mcp043_gates.ps1'
}

Add-Content -Path $Summary -Value ('tree dirty after the run: ' + ((& git -C $RepoRoot status --porcelain) -join ' | ')) -Encoding ASCII
Add-Content -Path $Summary -Value 'DONE' -Encoding ASCII
Write-Host ''
Write-Host '== summary =='
Get-Content $Summary | ForEach-Object { Write-Host $_ }

# TASK-069 section 2.3 (census): Invoke-Step recorded every child's exit code in
# $Summary and this file never read it back, so a red step was reported and the
# process still exited 0. Same guard as the TASK-042/043 drivers.
$failed = @(Select-String -Path $Summary -Pattern 'EXIT [1-9]')
if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host ("FAILED STEPS: {0}" -f $failed.Count)
    foreach ($entry in $failed) { Write-Host ('    ' + $entry.Line) }
    exit 1
}
exit 0
