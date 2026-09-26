# =============================================================================
#  mcp070_guard_blindspot_probe.ps1 -- TASK-070 item 5, SECOND EDITION
#  (re-run under TASK-071 section A).
#
#  THE FIRST EDITION (TASK-070, anchor 3cbaacd6b) MEASURED A BOUNDARY. Its two
#  scenarios and their result are recorded in
#  `docs/reports/REPORT-070-audit-unconfirmed-closure.md` section 5, table:
#
#      control (visible) : a NEW untracked file in a tracked directory
#                          -> manifest `UNTOUCHED <path>` (the guard saw it)
#      BLIND SPOT A      : an untracked FILE that existed BEFORE the snapshot
#                          and was deleted by something else afterwards
#                          -> 0 manifest lines mentioned it; the battery's
#                             declared-leftover count was 0, i.e. a real
#                             deletion was reported as `tracked_evidence_restored`
#      BLIND SPOT B      : a rewrite + a creation INSIDE an already-untracked
#                          directory (one `-unormal` entry before and after)
#                          -> 0 manifest lines mentioned either file
#
#  TASK-071 section A replaced the directory-level untracked set with a
#  FILE-level inventory (`git status --porcelain -uall`) and added the three
#  manifest classes MISSING-UNTRACKED / APPEARED-UNTRACKED / CHANGED-UNTRACKED.
#  This second edition replays the SAME two scenarios and asserts the opposite
#  of the first edition's finding: the three paths must now be NAMED.
#
#  What it does NOT claim: naming a MISSING or a CHANGED untracked path is not
#  restoring it. git holds no bytes of either, so the probe asserts both halves:
#  the path is NAMED in the manifest, AND it is still gone / still rewritten
#  afterwards. Detection is the deliverable; restoration is not possible here.
#
#  The guard under test is the SHIPPED one (`mcp_evidence_guard.ps1`, dot
#  sourced line by line below); this probe deliberately defines no local copy of
#  the inventory functions any more, so it cannot measure itself.
#
#  The repository is left exactly as it was: every planted path is removed and
#  the probe asserts `git status --porcelain -uall` before == after, byte for
#  byte (sha256 of the full output).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp070_guard_blindspot_probe.ps1
#
#  Pure ASCII on purpose.
# =============================================================================

param([string]$RepoRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
$RepoRoot = (Resolve-Path $RepoRoot).Path

. (Join-Path $PSScriptRoot 'mcp_evidence_guard.ps1')

$Root = Join-Path $env:TEMP ('mcp070\guard\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Ev = Join-Path $Root 'evidence'
New-Item -ItemType Directory -Force -Path $Ev | Out-Null

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Write-Bytes {
    param([string]$Rel, [string]$Text)
    $full = Join-Path $RepoRoot $Rel
    $parent = Split-Path -Parent $full
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($full, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

function Remove-Rel {
    param([string]$Rel)
    $full = Join-Path $RepoRoot $Rel
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-PorcelainAll {
    return @(& git -C $RepoRoot status --porcelain -uall 2>$null)
}

function Get-PorcelainSha {
    param([string[]]$Lines)
    return (Get-McpEvidenceContentSha256 -Text (($Lines -join "`n") + "`n"))
}

# ---------------------------------------------------------------------------
#  The planted paths. All of them are untracked and none of them is in the
#  battery's declaration (`task050` / `task051` / `task053` + the one
#  `e20_child_status.json`).
# ---------------------------------------------------------------------------
$DeclaredRoots = @(
    'modules/mcp_server/docs/reports/evidence/task050',
    'modules/mcp_server/docs/reports/evidence/task051',
    'modules/mcp_server/docs/reports/evidence/task053'
)
$DeclaredPaths = @('modules/mcp_server/docs/reports/evidence/task051/red/e20_child_status.json')

$EvDir = 'modules/mcp_server/docs/reports/evidence'
$VictimA = ($EvDir + '/mcp070-blindspot-victim-a.txt')          # pre-existing untracked FILE
$CarrierKeep = ($EvDir + '/task070/carrier/keep.txt')           # inside an untracked DIRECTORY
$CarrierVictim = ($EvDir + '/task070/carrier/victim.txt')       # inside an untracked DIRECTORY
$CarrierNew = ($EvDir + '/task070/carrier/new-after-snapshot.txt')
$VisiblePlant = ($EvDir + '/mcp070-blindspot-visible-plant.txt')

# A rewrite that keeps the same LENGTH, so only the identity string can see it.
$CarrierVictimNew = "mcp070 blind spot B: REWRITTEN after the snapshot, same length......`n"

$PorcelainBeforeProbe = Get-PorcelainAll
$PorcelainBeforeProbeSha = Get-PorcelainSha -Lines $PorcelainBeforeProbe
[IO.File]::WriteAllLines((Join-Path $Ev 'porcelain_before_probe.txt'), [string[]]$PorcelainBeforeProbe)

Write-Host '============================================================='
Write-Host ' TASK-070 item 5 (TASK-071 section A second edition):'
Write-Host ' what the evidence guard can now SEE'
Write-Host (' repo : ' + $RepoRoot)
Write-Host (' root : ' + $Root)
Write-Host '============================================================='

$cleanupNeeded = $false
try {
    # -----------------------------------------------------------------------
    #  1. Plant everything that must exist BEFORE the snapshot.
    # -----------------------------------------------------------------------
    Write-Bytes -Rel $VictimA -Text "mcp070 blind spot A: this file existed before the snapshot.`n"
    Write-Bytes -Rel $CarrierKeep -Text "mcp070 blind spot B carrier: pre-snapshot.`n"
    Write-Bytes -Rel $CarrierVictim -Text "mcp070 blind spot B: original content, to be rewritten.`n"
    $cleanupNeeded = $true

    $shot = Get-McpEvidenceState -RepoRoot $RepoRoot
    $beforeHasVictimA = @($shot.Untracked) -contains $VictimA
    $carrierEntries = @($shot.Untracked | Where-Object { $_ -like ($EvDir + '/task070/*') })
    Write-Host ('snapshot: untracked FILE entries={0}; victim A listed as its own file={1}; carrier files={2}' -f `
            @($shot.Untracked).Count, $beforeHasVictimA, ($carrierEntries.Count))
    [IO.File]::WriteAllLines((Join-Path $Ev 'snapshot_before_untracked.txt'), [string[]]@($shot.Untracked))
    Check 'g_planted_paths_are_in_the_before_snapshot' `
        ($beforeHasVictimA -and ($carrierEntries.Count -ge 2) -and (@($shot.UntrackedInventory.Keys).Count -ge 3)) `
        ("victim A is its own untracked entry={0}; the carrier DIRECTORY is no longer one entry, it contributes {1} file entries; the file-level inventory holds {2} paths" -f `
            $beforeHasVictimA, $carrierEntries.Count, @($shot.UntrackedInventory.Keys).Count)

    # The identity string of every planted file is a length + mtime pair, which is
    # what makes a deletion and a rewrite distinguishable at all.
    $inventoryShowsIdentity = ($shot.UntrackedInventory.ContainsKey($VictimA)) -and `
        ($shot.UntrackedInventory[$VictimA] -match '^[0-9]+:[0-9]+$') -and `
        ($shot.UntrackedInventory.ContainsKey($CarrierVictim))
    Check 'g_inventory_sees_the_planted_files_with_an_identity_string' $inventoryShowsIdentity `
        ("victim A present={0} identity='{1}'; carrier victim present={2}" -f `
            $shot.UntrackedInventory.ContainsKey($VictimA), $shot.UntrackedInventory[$VictimA], $shot.UntrackedInventory.ContainsKey($CarrierVictim))

    # -----------------------------------------------------------------------
    #  2. The "other place": delete/rewrite/create WITHOUT going through the
    #     guard, then run the shipped restore over the battery's declaration.
    # -----------------------------------------------------------------------
    Remove-Rel -Rel $VictimA
    Write-Bytes -Rel $CarrierVictim -Text $CarrierVictimNew
    Write-Bytes -Rel $CarrierNew -Text "mcp070 blind spot B: created after the snapshot.`n"
    Write-Bytes -Rel $VisiblePlant -Text "mcp070 control: this one the guard can see.`n"

    $manifest = Restore-McpEvidence -RepoRoot $RepoRoot -Before $shot -AllowedPaths $DeclaredPaths -AllowedRoots $DeclaredRoots
    [IO.File]::WriteAllLines((Join-Path $Ev 'restore_manifest.txt'), [string[]]$manifest)
    Write-Host ''
    Write-Host '--- shipped restore manifest (relevant lines) ---'
    foreach ($line in $manifest) {
        if ($line -like ('*' + 'mcp070' + '*') -or $line -like 'SUMMARY*') { Write-Host ('    ' + $line) }
    }
    $manifestMentionsVictimA = @($manifest | Where-Object { $_ -like ('*' + $VictimA + '*') })
    $manifestMentionsVisible = @($manifest | Where-Object { $_ -like ('*' + $VisiblePlant + '*') })
    $manifestMentionsCarrierNew = @($manifest | Where-Object { $_ -like ('*' + $CarrierNew + '*') })
    $manifestMentionsCarrierVictim = @($manifest | Where-Object { $_ -like ('*' + $CarrierVictim + '*') })
    $summaryLine = @($manifest | Where-Object { $_ -like 'SUMMARY*' })

    Check 'g_guard_names_a_new_untracked_file' ($manifestMentionsVisible.Count -ge 1) `
        ("the file created after the snapshot: {0} manifest line(s) name it" -f $manifestMentionsVisible.Count)

    # ---- blind spot A: WAS 0 lines in the first edition, must be named now ---
    $victimNamed = @($manifestMentionsVictimA | Where-Object { $_ -like 'MISSING-UNTRACKED *' -or $_ -like 'UNTOUCHED-MISSING-UNTRACKED *' })
    $victimClaimedRestored = @($manifestMentionsVictimA | Where-Object { $_ -like 'RESTORED*' })
    Check 'g_blindspot_a_a_deleted_untracked_file_is_now_named' `
        (($victimNamed.Count -ge 1) -and ($victimClaimedRestored.Count -eq 0)) `
        ("first edition: 0 manifest lines named it. Now: {0} line(s) name it ({1}); lines claiming it was restored: {2}; SUMMARY = {3}" -f `
            $manifestMentionsVictimA.Count, ($manifestMentionsVictimA -join ' ;; '), $victimClaimedRestored.Count, ($summaryLine -join ' '))
    Check 'g_blindspot_a_is_detected_but_NOT_restored' (-not (Test-Path (Join-Path $RepoRoot $VictimA))) `
        ("the deleted file {0} is still gone after the restore: git holds no bytes of an untracked file, so naming it is the whole deliverable (detection is not restoration)" -f $VictimA)

    # ---- blind spot B: WAS 0 lines, must be named now -----------------------
    $carrierNewNamed = @($manifestMentionsCarrierNew | Where-Object { $_ -like 'APPEARED-UNTRACKED *' -or $_ -like 'UNTOUCHED *' -or $_ -like 'RESTORED-NEW*' })
    $carrierVictimNamed = @($manifestMentionsCarrierVictim | Where-Object { $_ -like 'CHANGED-UNTRACKED *' -or $_ -like 'UNTOUCHED-CHANGED-UNTRACKED *' })
    Check 'g_blindspot_b_side_effects_inside_an_untracked_directory_are_now_named' `
        (($carrierNewNamed.Count -ge 1) -and ($carrierVictimNamed.Count -ge 1)) `
        ("first edition: 0 manifest lines named either file. Now: the created file is named by {0} line(s) ({1}); the rewritten file by {2} line(s) ({3})" -f `
            $carrierNewNamed.Count, ($carrierNewNamed -join ' ;; '), $carrierVictimNamed.Count, ($carrierVictimNamed -join ' ;; '))
    $carrierBytes = @()
    if (Test-Path (Join-Path $RepoRoot $CarrierVictim)) {
        $carrierBytes = [IO.File]::ReadAllBytes((Join-Path $RepoRoot $CarrierVictim))
    }
    $carrierText = (New-Object Text.UTF8Encoding($false)).GetString($carrierBytes)
    Check 'g_blindspot_b_is_detected_but_NOT_restored' ($carrierText -ceq $CarrierVictimNew) `
        ("the rewritten file still holds the post-snapshot bytes ({0} byte(s)): the old untracked bytes are gone and CHANGED-UNTRACKED says so instead of implying a restore" -f $carrierBytes.Length)

    # ---- what the battery's OWN verdict machinery now says ------------------
    # The battery (mcp056_regression_battery.ps1) recomputes this diff from its
    # two snapshots, so the same arithmetic is reproduced here: with the planted
    # paths DECLARED, the verdict can no longer read 0.
    $afterState = Get-McpEvidenceState -RepoRoot $RepoRoot
    $inventoryDiff = Compare-McpUntrackedInventory -Before $shot.UntrackedInventory -After $afterState.UntrackedInventory
    $newModified = @($afterState.Modified | Where-Object { @($shot.Modified) -notcontains $_ })
    $newUntracked = @($afterState.Untracked | Where-Object { @($shot.Untracked) -notcontains $_ })
    $leftoverCandidates = @(@($newModified) + @($newUntracked) + @($inventoryDiff.Missing) + @($inventoryDiff.Changed) | Sort-Object -Unique)
    $undeclaredLeftover = @($leftoverCandidates | Where-Object {
            -not (Test-McpDeclaredPath -Path $_ -AllowedPaths $DeclaredPaths -AllowedRoots $DeclaredRoots)
        })
    $declaredLeftoverWithDeclaration = @($leftoverCandidates | Where-Object {
            Test-McpDeclaredPath -Path $_ -AllowedPaths @() -AllowedRoots @($EvDir)
        })
    Check 'g_battery_verdict_now_counts_a_missing_untracked_file' `
        (($inventoryDiff.Missing -contains $VictimA) -and ($declaredLeftoverWithDeclaration.Count -ge 1) -and ($declaredLeftoverWithDeclaration -contains $VictimA)) `
        ("first edition: the declared-leftover count was 0 and the verdict printed 'evidence restored'. Now: MISSING holds victim A={0}, and with the planted root declared the declared-leftover count is {1} - so a real silent deletion fails the verdict instead of passing it" -f `
            ($inventoryDiff.Missing -contains $VictimA), $declaredLeftoverWithDeclaration.Count)

    # ---- cost, measured on this repository ---------------------------------
    $t0 = Get-Date
    $afterPlain = Get-McpUntrackedInventory -RepoRoot $RepoRoot
    $plainMs = ((Get-Date) - $t0).TotalMilliseconds
    $t1 = Get-Date
    $afterHashed = Get-McpUntrackedInventory -RepoRoot $RepoRoot -HashUntracked
    $hashedMs = ((Get-Date) - $t1).TotalMilliseconds
    $inventoryReport = New-Object System.Collections.Generic.List[string]
    $inventoryReport.Add(('untracked files in the inventory: {0}' -f $afterPlain.Count))
    $inventoryReport.Add(('default mode (path + length + mtime): {0:n0} ms' -f $plainMs))
    $inventoryReport.Add(('hash mode  (path + length + mtime + sha256): {0:n0} ms' -f $hashedMs))
    $inventoryReport.Add(('MISSING  = {0}' -f ($inventoryDiff.Missing -join ', ')))
    $inventoryReport.Add(('APPEARED = {0}' -f ($inventoryDiff.Appeared -join ', ')))
    $inventoryReport.Add(('CHANGED  = {0}' -f ($inventoryDiff.Changed -join ', ')))
    $inventoryReport.Add(('undeclared leftovers under the BATTERY declaration = {0}' -f $undeclaredLeftover.Count))
    [IO.File]::WriteAllLines((Join-Path $Ev 'inventory_report.txt'), $inventoryReport.ToArray())
    foreach ($line in $inventoryReport) { Write-Host ('  inventory| ' + $line) }
    Check 'g_inventory_is_cheap_enough_to_run_per_guard_call' ($plainMs -lt 30000) `
        ("the default file-level inventory of {0} untracked files costs {1:n0} ms (git status -uall + one Get-Item per file, no file content read); the hashed variant costs {2:n0} ms" -f `
            $afterPlain.Count, $plainMs, $hashedMs)
} finally {
    if ($cleanupNeeded) {
        Remove-Rel -Rel $VictimA
        Remove-Rel -Rel $VisiblePlant
        Remove-Rel -Rel ($EvDir + '/task070')
    }
}

# ---------------------------------------------------------------------------
#  The repository must be exactly where it started, BYTE FOR BYTE.
# ---------------------------------------------------------------------------
$PorcelainAfterProbe = Get-PorcelainAll
$PorcelainAfterProbeSha = Get-PorcelainSha -Lines $PorcelainAfterProbe
[IO.File]::WriteAllLines((Join-Path $Ev 'porcelain_after_probe.txt'), [string[]]$PorcelainAfterProbe)
$diffPorcelain = @(Compare-Object $PorcelainBeforeProbe $PorcelainAfterProbe)
Check 'g_repository_left_exactly_as_it_started' (($diffPorcelain.Count -eq 0) -and ($PorcelainBeforeProbeSha -ceq $PorcelainAfterProbeSha)) `
    ("git status --porcelain -uall before={0} line(s) sha256={1}, after={2} line(s) sha256={3}, differing={4}" -f `
        $PorcelainBeforeProbe.Count, $PorcelainBeforeProbeSha.Substring(0, 12), $PorcelainAfterProbe.Count, $PorcelainAfterProbeSha.Substring(0, 12), $diffPorcelain.Count)

Write-Host ''
Write-Host '--- summary ---'
$failures = 0
foreach ($c in $script:Checks) {
    if (-not $c.pass) { $failures++ }
    Write-Host ("[{0}] {1} :: {2}" -f $(if ($c.pass) { 'PASS' } else { 'FAIL' }), $c.id, $c.evidence)
}
[IO.File]::WriteAllLines((Join-Path $Root 'summary.txt'), @($script:Checks | ForEach-Object { ("[{0}] {1} :: {2}" -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence) }))
Write-Host ('--- checks: {0}, failures: {1} ---' -f $script:Checks.Count, $failures)
Write-Host ('--- evidence root: {0} ---' -f $Root)
if ($failures -gt 0) { Write-Host ('GUARD BLIND-SPOT PROBE FAILED: {0}' -f $failures); exit 1 }
Write-Host 'GUARD BLIND-SPOT PROBE PASS (the two TASK-070 blind spots are now NAMED; naming is detection, not restoration)'
exit 0
