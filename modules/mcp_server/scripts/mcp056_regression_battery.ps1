# =============================================================================
#  mcp056_regression_battery.ps1 -- TASK-056: the regression battery that
#  TASK-055 declared unrun (REPORT-055 section 8.1 D-1), plus the two acceptance
#  runs whose PASS lists have to agree.
#
#  Every step is a separate `powershell -File` child, strictly serial (each one
#  binds 9888 / 9889), with its full output in <evidence dir>/<name>.log and its
#  exit code in summary.txt. The scripts are run exactly as they are; a failure
#  is reported, never patched away here.
#
#  ---------------------------------------------------------------------------
#  TASK-057 section 3 (R-B3) changes two things, and only two:
#
#  1. THE EVIDENCE DIRECTORY DEFAULTS TO %TEMP%. The 15 step scripts write their
#     own evidence into *tracked* files under
#     docs/reports/evidence/task0xx/** - that is their declared contract and the
#     battery does not touch it - so the battery's own aggregate logs must not
#     be written there too, or the restore below would delete the very logs this
#     run produced. `-EvidenceDir` still accepts the historical path for anyone
#     who wants it (and then the restore leaves it alone only if it was dirty
#     before the run, which is what the guard reports).
#
#  2. THE WORKING TREE IS RESTORED AND THE RESTORE IS PRINTED. The battery
#     snapshots the tree with scripts/mcp_evidence_guard.ps1 before the first
#     step, and afterwards puts every DECLARED tracked file back to its HEAD
#     bytes and deletes every DECLARED path that did not exist before the run
#     (one of the steps creates docs/reports/evidence/task051/red/
#     e20_child_status.json). The manifest is printed and saved next to the
#     logs, and the battery fails if a declared artifact is not back where it
#     started - so "the evidence is still history" is an assertion, not a
#     discipline someone has to remember.
#
#     TASK-069 section 1 narrows that assertion to the declaration: the restore
#     used to delete EVERY path that appeared during the run, which is not a
#     restore but a sweep (it deleted the report TASK-068's engineer wrote while
#     the battery ran, and REPORT-069 reproduced it). A path the battery did not
#     declare - a report, a scratch file - is now reported as UNTOUCHED and left
#     exactly as it is; the verdict only speaks about the declared set.
#  ---------------------------------------------------------------------------
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp056_regression_battery.ps1
#    powershell ... -File scripts\mcp056_regression_battery.ps1 -EvidenceDir <path>
#    powershell ... -File scripts\mcp056_regression_battery.ps1 -NoRestore
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$EvidenceDir = '',
    [switch]$NoRestore
)

$ErrorActionPreference = 'Continue'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $PSScriptRoot 'mcp_evidence_guard.ps1')

# ---------------------------------------------------------------------------
# TASK-069 section 1: THE BATTERY RESTORES ONLY WHAT ITS STEPS DECLARE.
#
# The declaration below is the empirical set of artifacts the 15 step scripts
# touch, read off the pre-TASK-069 restore manifest of this very battery (57
# `RESTORED` tracked paths and exactly 1 `REMOVED` new path, every one of them
# under one of these three roots):
#
#     modules/mcp_server/docs/reports/evidence/task050
#     modules/mcp_server/docs/reports/evidence/task051
#     modules/mcp_server/docs/reports/evidence/task053
#
# `mcp050_parameter_guidance_evidence.ps1` owns task050,
# `mcp051_b_tier_evidence.ps1` owns task051,
# `mcp053_added_tools_evidence.ps1` (and the shared one-path writer it uses) owns
# task053, and `docs/reports/evidence/task051/red/e20_child_status.json` is the
# ONE file no batch ever committed and a step creates.
#
# It is a path whitelist with DEFAULT DENY. Everything outside it - including a
# report written while this battery runs - is reported as UNTOUCHED and left
# exactly as it is (TASK-069 defect 1: the previous version deleted it). If a
# step's declared evidence root ever moves, ADD IT HERE: the battery will then
# report the untouched path loudly instead of silently owning it.
# ---------------------------------------------------------------------------
$DeclaredRoots = @(
    'modules/mcp_server/docs/reports/evidence/task050',
    'modules/mcp_server/docs/reports/evidence/task051',
    'modules/mcp_server/docs/reports/evidence/task053'
)
$DeclaredPaths = @(
    'modules/mcp_server/docs/reports/evidence/task051/red/e20_child_status.json'
)

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($EvidenceDir)) {
    $Ev = Join-Path $env:TEMP ('mcp_server_regression\' + $Stamp)
} else {
    $Ev = $EvidenceDir
}
New-Item -ItemType Directory -Force -Path $Ev | Out-Null
$Ev = (Resolve-Path $Ev).Path

$Steps = @(
    @{ name = 'accept_m1_run1'; script = 'accept_m1.ps1' },
    @{ name = 'accept_m1_run2'; script = 'accept_m1.ps1' },
    @{ name = 'mcp041_gates'; script = 'mcp041_gates.ps1' },
    @{ name = 'mcp042_gates'; script = 'mcp042_gates.ps1' },
    @{ name = 'mcp043_gates'; script = 'mcp043_gates.ps1' },
    @{ name = 'mcp010_b2_observation_evidence'; script = 'mcp010_b2_observation_evidence.ps1' },
    @{ name = 'mcp019_b4_evidence'; script = 'mcp019_b4_evidence.ps1' },
    @{ name = 'mcp027_object_shape_and_paths_evidence'; script = 'mcp027_object_shape_and_paths_evidence.ps1' },
    @{ name = 'mcp044_capture_evidence'; script = 'mcp044_capture_evidence.ps1' },
    @{ name = 'mcp045_pixel_compare_cost'; script = 'mcp045_pixel_compare_cost.ps1' },
    @{ name = 'mcp046_capture_encode_cost'; script = 'mcp046_capture_encode_cost.ps1' },
    @{ name = 'mcp050_parameter_guidance_evidence'; script = 'mcp050_parameter_guidance_evidence.ps1' },
    @{ name = 'mcp051_b_tier_evidence'; script = 'mcp051_b_tier_evidence.ps1' },
    @{ name = 'mcp052_added_tools_evidence'; script = 'mcp052_added_tools_evidence.ps1' },
    @{ name = 'mcp053_added_tools_evidence'; script = 'mcp053_added_tools_evidence.ps1' }
)

function Get-TreeView {
    param([string]$Tag)
    # `-unormal` keeps a wholly untracked directory as one line; without it a
    # `status.showUntrackedFiles=all` config would put fifteen thousand lines of
    # build cache into the evidence file.
    $short = @(& git -C $RepoRoot status --short -unormal)
    $stat = @(& git -C $RepoRoot diff --stat)
    [IO.File]::WriteAllLines((Join-Path $Ev ('git_status_short_' + $Tag + '.txt')), [string[]]$short)
    [IO.File]::WriteAllLines((Join-Path $Ev ('git_diff_stat_' + $Tag + '.txt')), [string[]]$stat)
    return @{ Short = $short; Stat = $stat }
}

# R-B3: the state of the tree before anything of this battery runs.
$beforeState = Get-McpEvidenceState -RepoRoot $RepoRoot
$beforeView = Get-TreeView -Tag 'before'
Write-Host '--- git status --short (before) ---'
$beforeView.Short | ForEach-Object { Write-Host ('    ' + $_) }
Write-Host ('--- git diff --stat (before): {0} line(s) ---' -f $beforeView.Stat.Count)
$beforeView.Stat | ForEach-Object { Write-Host ('    ' + $_) }

$Results = New-Object System.Collections.Generic.List[string]
Push-Location $RepoRoot
try {
    Write-Host ("git HEAD: " + ((& git rev-parse HEAD) -join ' '))
    foreach ($step in $Steps) {
        $name = $step.name
        $path = Join-Path $RepoRoot ('modules\mcp_server\scripts\' + $step.script)
        $log = Join-Path $Ev ($name + '.log')
        Write-Host ("=== {0} ===" -f $name)
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $path *> $log
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $old
        }
        $tail = (Get-Content $log -Tail 3) -join ' | '
        Write-Host ("    exit={0} :: {1}" -f $code, $tail)
        $Results.Add(('{0}|{1}|{2}' -f $name, $code, $tail))
    }
} finally {
    Pop-Location
}

# The two acceptance runs must agree check for check, not just "both green".
$run1 = @(Get-Content (Join-Path $Ev 'accept_m1_run1.log') | Where-Object { $_ -match '^\[(PASS|FAIL)\]' })
$run2 = @(Get-Content (Join-Path $Ev 'accept_m1_run2.log') | Where-Object { $_ -match '^\[(PASS|FAIL)\]' })
$diff = @(Compare-Object $run1 $run2)
$compare = New-Object System.Collections.Generic.List[string]
$compare.Add(('accept_m1_run1 checks={0} accept_m1_run2 checks={1} differing_lines={2}' -f $run1.Count, $run2.Count, $diff.Count))
foreach ($line in $diff) { $compare.Add(('{0} {1}' -f $line.SideIndicator, $line.InputObject)) }
[IO.File]::WriteAllLines((Join-Path $Ev 'accept_m1_pass_list_compare.txt'), $compare.ToArray())

$Results.Add(('accept_m1_pass_lists_agree|{0}|{1}' -f $(if ($diff.Count -eq 0) { 0 } else { 1 }), $compare[0]))

$failed = @($Results | Where-Object { ($_ -split '\|')[1] -ne '0' })

# ---------------------------------------------------------------------------
# R-B3: put the tracked evidence back and prove the tree is where it started.
# TASK-069 section 1: only the paths declared at the top of this file are
# restored; anything else the run changed is reported and left alone.
# ---------------------------------------------------------------------------
$restoreFailed = 0
if ($NoRestore) {
    Write-Host ''
    Write-Host '-NoRestore: the working tree is left as the steps wrote it (TASK-057 R-B3).'
} else {
    $manifest = Restore-McpEvidence -RepoRoot $RepoRoot -Before $beforeState `
        -AllowedPaths $DeclaredPaths -AllowedRoots $DeclaredRoots
    Write-Host ''
    Write-Host '--- R-B3 restore manifest (TASK-057 section 3; TASK-069 declaration) ---'
    Write-Host ('    declared roots : ' + ($DeclaredRoots -join ' | '))
    Write-Host ('    declared paths : ' + ($DeclaredPaths -join ' | '))
    $manifest | ForEach-Object { Write-Host ('    ' + $_) }
    [IO.File]::WriteAllLines((Join-Path $Ev 'restore_manifest.txt'), [string[]]$manifest)
    $restoreFailed = @($manifest | Where-Object { $_ -like 'RESTORE-FAILED*' }).Count
}

$afterState = Get-McpEvidenceState -RepoRoot $RepoRoot
$afterView = Get-TreeView -Tag 'after'
Write-Host '--- git status --short (after) ---'
$afterView.Short | ForEach-Object { Write-Host ('    ' + $_) }
Write-Host ('--- git diff --stat (after): {0} line(s) ---' -f $afterView.Stat.Count)
$afterView.Stat | ForEach-Object { Write-Host ('    ' + $_) }

$newModified = @($afterState.Modified | Where-Object { @($beforeState.Modified) -notcontains $_ })
$newUntracked = @($afterState.Untracked | Where-Object { @($beforeState.Untracked) -notcontains $_ })

# TASK-071 section A: the file-level untracked diff, recomputed from the two
# snapshots so the verdict holds with -NoRestore too (where there is no
# manifest). `Missing` is the class the old directory-level snapshot could not
# see AT ALL: a file that was there before the run and was deleted by something
# that did not go through the guard. It is DETECTED, never restored (git holds
# no bytes), so it is a DECLARED LEFTOVER and the verdict below can no longer
# print "tracked_evidence_restored" next to a real deletion.
$inventoryDiff = Compare-McpUntrackedInventory -Before $beforeState.UntrackedInventory -After $afterState.UntrackedInventory
$missingUntracked = @($inventoryDiff.Missing)
$changedUntracked = @($inventoryDiff.Changed)
$appearedUntracked = @($inventoryDiff.Appeared)

# TASK-069: the verdict is scoped to the declaration. A path this battery
# declared must be back where it started; a path it did not declare is somebody
# else's and is reported, never a failure and never restored.
$leftoverCandidates = @(@($newModified) + @($newUntracked) + @($missingUntracked) + @($changedUntracked) | Sort-Object -Unique)
$declaredLeftover = @($leftoverCandidates | Where-Object {
    Test-McpDeclaredPath -Path $_ -AllowedPaths $DeclaredPaths -AllowedRoots $DeclaredRoots
})
$undeclaredLeftover = @($leftoverCandidates | Where-Object {
    -not (Test-McpDeclaredPath -Path $_ -AllowedPaths $DeclaredPaths -AllowedRoots $DeclaredRoots)
})
$treeClean = (($declaredLeftover.Count -eq 0) -and ($restoreFailed -eq 0))

if ($undeclaredLeftover.Count -gt 0) {
    Write-Host ''
    Write-Host '--- paths this battery did NOT declare (left exactly as they are, TASK-069) ---'
    $undeclaredLeftover | ForEach-Object { Write-Host ('    UNTOUCHED ' + $_) }
}

$restoreVerdict = if ($treeClean) { 0 } else { 1 }
$restoreFormat = 'tracked_evidence_restored|{0}|declared leftovers={1} (every declared artifact is back); undeclared paths left alone={2}; restore failures={3}; git diff --stat after={4} line(s); file-level untracked detection: appeared={5} missing={6} changed={7} (missing/changed are DETECTED, never restored; a declared one fails this verdict - TASK-071 A)'
$restoreLine = $restoreFormat -f $restoreVerdict, $declaredLeftover.Count, $undeclaredLeftover.Count, $restoreFailed, $afterView.Stat.Count, $appearedUntracked.Count, $missingUntracked.Count, $changedUntracked.Count
$Results.Add($restoreLine)

[IO.File]::WriteAllLines((Join-Path $Ev 'summary.txt'), $Results.ToArray())

Write-Host ''
Write-Host '--- summary ---'
$Results | ForEach-Object { Write-Host $_ }
Write-Host ('--- evidence directory: {0} ---' -f $Ev)

$failed = @($Results | Where-Object { ($_ -split '\|')[1] -ne '0' })
if ($failed.Count -gt 0) { Write-Host ('FAILED STEPS: {0}' -f $failed.Count); exit 1 }
Write-Host 'ALL REGRESSION STEPS EXIT 0'
exit 0