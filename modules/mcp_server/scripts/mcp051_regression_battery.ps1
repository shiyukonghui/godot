# =============================================================================
#  mcp051_regression_battery.ps1 -- TASK-051 regression runs, strictly serial
#  (pure ASCII).
#
#  One step at a time, one log per step, the exit code of every step recorded in
#  a summary. No step starts scons, and none of them overlaps with another: the
#  binary they run against is the one `scripts\build_local.cmd -Force` built,
#  whose `--version` is recorded below next to `git rev-parse --short=9 HEAD`.
#
#  The step list is the one TASK-051's brief names:
#
#    individual : the gate 6 coverage probes, the three TASK-010/019/027 evidence
#                 scripts, the TASK-050 evidence script (whose derived
#                 `data.suggestion` strings this batch legitimately changed), and
#                 the TASK-050 contract diff on its own pinned revision pair;
#    batteries  : TASK-041/042/043 gates (the batches whose contract and
#                 description machinery TASK-051 touches);
#    capture    : the TASK-044/045/046 capture phases.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp051_regression_battery.ps1 -Batch individual
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp051_regression_battery.ps1 -Batch batteries
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp051_regression_battery.ps1 -Batch capture
# =============================================================================

param(
    [ValidateSet('individual', 'batteries', 'capture')]
    [string]$Batch = 'individual'
)

$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Scripts = Join-Path $RepoRoot 'modules\mcp_server\scripts'
$Logs = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task051\green\regression'
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

Add-Content -Path $Summary -Value ('TASK-051 regression battery: ' + $Batch) -Encoding ASCII
Add-Content -Path $Summary -Value ('binary --version: ' + (& $Engine --version)) -Encoding ASCII
Add-Content -Path $Summary -Value ('git HEAD: ' + (& git -C $RepoRoot rev-parse HEAD)) -Encoding ASCII
Add-Content -Path $Summary -Value ('git HEAD short: ' + (& git -C $RepoRoot rev-parse --short=9 HEAD)) -Encoding ASCII

if ($Batch -eq 'individual') {
    Invoke-Step 'gate6c_coverage_probes' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp031_gate6_coverage_probes.ps1') }
    Invoke-Ps1 -Name 'regress_mcp010_b2_observation' -Script 'mcp010_b2_observation_evidence.ps1'
    Invoke-Ps1 -Name 'regress_mcp019_b4' -Script 'mcp019_b4_evidence.ps1'
    Invoke-Ps1 -Name 'regress_mcp027_object_shape_and_paths' -Script 'mcp027_object_shape_and_paths_evidence.ps1'
    Invoke-Ps1 -Name 'regress_mcp050_parameter_guidance' -Script 'mcp050_parameter_guidance_evidence.ps1' -Extra @('-Label', 'green')
    # TASK-050's own contract diff, on the revision pair it proved: the two
    # revisions are pinned by revision *and* sha256 inside that script, so this
    # step cannot be turned green by TASK-051's contract change (the pair is
    # TASK-050's, not the working tree's).
    Invoke-Step 'regress_mcp050_contract_diff' {
        $before = Join-Path $env:TEMP 'mcp051\task050_contract_before.json'
        $after = Join-Path $env:TEMP 'mcp051\task050_contract_after.json'
        New-Item -ItemType Directory -Force -Path (Split-Path $before) | Out-Null
        # The revision pair TASK-050 itself proved: `889466b85c` carries
        # generator_version 1.11.0 with 23 overrides, `b8b6553d90` (TASK-050's
        # implementation commit) carries 1.12.0 with 24. Pinning the revisions is
        # what keeps this step from being turned green by TASK-051's contract
        # change: the pair is TASK-050's, not the working tree's.
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $beforeText = ((& git -C $RepoRoot show '889466b85c:modules/mcp_server/docs/tools_list.renamed.json') -join "`n") + "`n"
        $afterText = ((& git -C $RepoRoot show 'b8b6553d90:modules/mcp_server/docs/tools_list.renamed.json') -join "`n") + "`n"
        [IO.File]::WriteAllText($before, $beforeText, $utf8)
        [IO.File]::WriteAllText($after, $afterText, $utf8)
        & python (Join-Path $Scripts 'mcp050_contract_diff.py') $before $after (Join-Path $env:TEMP 'mcp051\task050_contract_diff.json')
    }
} elseif ($Batch -eq 'batteries') {
    Invoke-Ps1 -Name 'regress_mcp041_gates' -Script 'mcp041_gates.ps1'
    Invoke-Ps1 -Name 'regress_mcp042_gates' -Script 'mcp042_gates.ps1'
    Invoke-Ps1 -Name 'regress_mcp043_gates' -Script 'mcp043_gates.ps1'
} else {
    Invoke-Ps1 -Name 'regress_mcp044_capture_editor' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'editor')
    Invoke-Ps1 -Name 'regress_mcp044_capture_headless' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'headless')
    Invoke-Ps1 -Name 'regress_mcp044_capture_game' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'game')
    Invoke-Ps1 -Name 'regress_mcp044_capture_diff_image' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'diff-image')
    Invoke-Ps1 -Name 'regress_mcp045_pixel_compare_cost' -Script 'mcp045_pixel_compare_cost.ps1' -Extra @('-Label', 'post')
    Invoke-Ps1 -Name 'regress_mcp046_capture_encode_cost' -Script 'mcp046_capture_encode_cost.ps1' -Extra @('-Label', 'post')
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
