# =============================================================================
#  mcp071_guard_inventory_probe.ps1 -- TASK-071 section A.
#
#  REPORT-070 section 5 measured two blind spots of the evidence guard and left
#  a runnable prototype (`Get-McpUntrackedInventory` /
#  `Compare-McpUntrackedInventory`, a KEPT read-only probe copy in
#  mcp070_guard_blindspot_probe.ps1's first edition). TASK-071 section A adopts
#  the prototype into the SHIPPED guard:
#
#    * `Get-McpEvidenceState` now reads `git status --porcelain -uall` and
#      returns a FILE-level `UntrackedInventory` (`path -> '<length>:<mtime
#      ticks>'`, plus `:sha256` under `-HashUntracked`) instead of a
#      directory-level `Untracked` list;
#    * `Restore-McpEvidence` reports the three difference classes
#      MISSING-UNTRACKED / APPEARED-UNTRACKED / CHANGED-UNTRACKED;
#    * the battery's verdict counts MISSING/CHANGED as declared leftovers, so a
#      silently deleted pre-existing untracked file can no longer be reported as
#      `tracked_evidence_restored`.
#
#  This probe is the evidence for that change. It does NOT re-measure the blind
#  spots (mcp070_guard_blindspot_probe.ps1, second edition, replays the exact
#  TASK-070 scenarios); it pins the SEMANTICS of the new inventory on a scratch
#  repository where mtime and byte length can be controlled exactly:
#
#    1. file-level, not directory-level (one `-unormal` entry vs N `-uall` files)
#    2. MISSING-UNTRACKED + CHANGED-UNTRACKED are NAMED but NOT restored
#       (declared and undeclared, which is what separates the two prefixes)
#    3. APPEARED-UNTRACKED is NAMED and IS restored by deletion (declared), and
#       an emptied declared directory is pruned
#    4. `-HashUntracked` catches an equal-length rewrite inside the same mtime
#       tick, which the default mode cannot see - the reason the switch exists
#    5. cost, measured on this repository (the one with ~4k graphify cache files)
#    6. `git status --porcelain -uall` is byte-identical before and after a
#       snapshot + restore cycle (the probe leaves no trace; sha256 compared)
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp071_guard_inventory_probe.ps1
#    powershell ... -File scripts\mcp071_guard_inventory_probe.ps1 -RepoRoot <path>
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$RepoRoot = '',
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)

if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
$RepoRoot = (Resolve-Path $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp071\guard-inventory' }
if (Test-Path -LiteralPath $OutRoot) { Remove-Item -Recurse -Force $OutRoot -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

. (Join-Path $PSScriptRoot 'mcp_evidence_guard.ps1')

$script:Failures = 0
function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    if (-not $Pass) { $script:Failures = $script:Failures + 1 }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllBytes($Path, $utf8.GetBytes($Text))
}

function Get-Sha {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '<absent>' }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

function Get-PorcelainSha {
    param([string]$Repo, [string[]]$Lines)
    return (Get-McpEvidenceContentSha256 -Text (($Lines -join "`n") + "`n"))
}

# `$ErrorActionPreference = 'Stop'` turns a native stderr line into a
# terminating error, so every scratch-repo git call goes through this helper.
function Invoke-Git {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git @Arguments 2>&1 | Out-Null
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
}

Write-Host '=================================================================='
Write-Host ' TASK-071 section A: the file-level evidence-guard inventory'
Write-Host (' repo : ' + $RepoRoot)
Write-Host (' root : ' + $OutRoot)
Write-Host '=================================================================='

# ===========================================================================
#  1. A scratch repository, where length and mtime can be set exactly.
# ===========================================================================
$Repo = Join-Path $OutRoot 'repo'
New-Item -ItemType Directory -Force -Path $Repo | Out-Null
$null = Invoke-Git @('-C', $Repo, 'init', '-q')
$null = Invoke-Git @('-C', $Repo, 'config', 'user.email', 'mcp071@example.invalid')
$null = Invoke-Git @('-C', $Repo, 'config', 'user.name', 'MCP071 probe')
$null = Invoke-Git @('-C', $Repo, 'config', 'commit.gpgsign', 'false')
$null = Invoke-Git @('-C', $Repo, 'config', 'core.autocrlf', 'false')
Write-Text -Path (Join-Path $Repo 'evidence\tracked.txt') -Text "tracked 1`n"
Write-Text -Path (Join-Path $Repo 'docs\other.txt') -Text "tracked 2`n"
$null = Invoke-Git @('-C', $Repo, 'add', '-A')
$null = Invoke-Git @('-C', $Repo, 'commit', '-q', '-m', 'scratch base')
Check 'W01_scratch_repo_has_a_head' (((& git -C $Repo rev-parse --verify HEAD 2>$null | Out-String).Trim()).Length -eq 40) `
    ("HEAD={0}" -f ((& git -C $Repo rev-parse --short HEAD 2>$null) -join ''))

# --- the planted paths of the declared scenario ------------------------------
$GoneDeclared = 'evidence/gone.txt'
$GoneUndeclared = 'docs/gone.txt'
$ChangedLen = 'evidence/changed-length.txt'
$ChangedSameLen = 'evidence/changed-same-length-same-tick.bin'
$AppearedFile = 'evidence/appeared.txt'
$AppearedInNewDir = 'evidence/newdir/inside.txt'

Write-Text -Path (Join-Path $Repo 'evidence\gone.txt') -Text "this file exists BEFORE the snapshot.`n"
Write-Text -Path (Join-Path $Repo 'docs\gone.txt') -Text "undeclared victim, exists before the snapshot.`n"
Write-Text -Path (Join-Path $Repo 'evidence\changed-length.txt') -Text "original, to be rewritten LONGER.`n"
$a = 'A' * 40
Write-Text -Path (Join-Path $Repo 'evidence\changed-same-length-same-tick.bin') -Text ($a + "`n")
$SamelenTicks = (Get-Item -LiteralPath (Join-Path $Repo 'evidence\changed-same-length-same-tick.bin')).LastWriteTimeUtc
Write-Text -Path (Join-Path $Repo 'evidence\tree\leaf.txt') -Text "kept, so evidence/tree must not be pruned.`n"
Write-Text -Path (Join-Path $Repo 'evidence\tree\leaf2.txt') -Text "same directory, so -unormal collapses all three into one entry.`n"
Write-Text -Path (Join-Path $Repo 'evidence\tree\leaf3.txt') -Text "same directory, same point.`n"

$beforeShot = Get-McpEvidenceState -RepoRoot $Repo
Check 'W02_untracked_is_file_level_not_directory_level' `
    ((@($beforeShot.Untracked) -contains 'evidence/tree/leaf.txt') -and (@($beforeShot.Untracked) -notcontains 'evidence/tree/')) `
    ("the untracked set holds the FILE evidence/tree/leaf.txt={0} and NOT the directory entry evidence/tree/={1}; inventory entries={2}" -f `
        (@($beforeShot.Untracked) -contains 'evidence/tree/leaf.txt'), (@($beforeShot.Untracked) -notcontains 'evidence/tree/'), @($beforeShot.UntrackedInventory.Keys).Count)

$unormalEntries = @(& git -C $Repo status --porcelain -unormal | Where-Object { $_ -like '??*' })
$uallEntries = @(& git -C $Repo status --porcelain -uall | Where-Object { $_ -like '??*' })
Check 'W03_uall_expands_a_wholly_untracked_directory' (($unormalEntries.Count -lt $uallEntries.Count) -and ($uallEntries.Count -ge 6)) `
    ("git status --porcelain -unormal reports {0} untracked entr(y|ies) while -uall reports {1}: the directory collapse is exactly what used to hide activity inside it" -f `
        $unormalEntries.Count, $uallEntries.Count)

# --- "another place" happens: nothing goes through the guard -----------------
Remove-Item -LiteralPath (Join-Path $Repo 'evidence\gone.txt') -Force
Remove-Item -LiteralPath (Join-Path $Repo 'docs\gone.txt') -Force
Write-Text -Path (Join-Path $Repo 'evidence\changed-length.txt') -Text "REWRITTEN after the snapshot, a longer body.`n"
$b = 'B' * 40
Write-Text -Path (Join-Path $Repo 'evidence\changed-same-length-same-tick.bin') -Text ($b + "`n")
[IO.File]::SetLastWriteTimeUtc((Join-Path $Repo 'evidence\changed-same-length-same-tick.bin'), $SamelenTicks)
Write-Text -Path (Join-Path $Repo 'evidence\appeared.txt') -Text "created after the snapshot.`n"
Write-Text -Path (Join-Path $Repo 'evidence\newdir\inside.txt') -Text "created after the snapshot, in a new directory.`n"

# ===========================================================================
#  2. The default mode: length + mtime. Declared restore over evidence/.
# ===========================================================================
$manifest = Restore-McpEvidence -RepoRoot $Repo -Before $beforeShot -AllowedRoots @('evidence')
[IO.File]::WriteAllLines((Join-Path $OutRoot 'manifest_default.txt'), [string[]]$manifest)
Write-Host '--- manifest (default mode, -AllowedRoots evidence) ---'
$manifest | ForEach-Object { Write-Host ('    ' + $_) }
Write-Host ''

Check 'W10_a_deleted_declared_untracked_file_is_NAMED_missing' `
    (@($manifest | Where-Object { $_ -ceq ('MISSING-UNTRACKED ' + $GoneDeclared) }).Count -eq 1) `
    (($manifest | Where-Object { $_ -like 'MISSING-UNTRACKED *' }) -join ' ;; ')
Check 'W11_a_deleted_declared_untracked_file_is_NOT_restored' (-not (Test-Path -LiteralPath (Join-Path $Repo 'evidence\gone.txt'))) `
    ("evidence/gone.txt is still absent after the restore: git holds no bytes of an untracked file, so the manifest NAMES the loss - it does not undo it")
Check 'W12_a_rewritten_declared_untracked_file_is_NAMED_changed' `
    (@($manifest | Where-Object { $_ -ceq ('CHANGED-UNTRACKED ' + $ChangedLen) }).Count -eq 1) `
    (($manifest | Where-Object { $_ -like 'CHANGED-UNTRACKED *' }) -join ' ;; ')
Check 'W13_a_rewritten_declared_untracked_file_is_NOT_restored' `
    (((Get-Sha (Join-Path $Repo 'evidence\changed-length.txt')) -cne '<absent>') -and ((([IO.File]::ReadAllText((Join-Path $Repo 'evidence\changed-length.txt'))) -like '*REWRITTEN*'))) `
    'evidence/changed-length.txt still holds the post-snapshot bytes: the class detects, it does not restore'
Check 'W14_an_appeared_declared_untracked_file_is_NAMED_and_IS_removed' `
    ((@($manifest | Where-Object { $_ -ceq ('APPEARED-UNTRACKED ' + $AppearedFile) }).Count -eq 1) -and `
        (@($manifest | Where-Object { $_ -ceq ('RESTORED-NEW ' + $AppearedFile) }).Count -eq 1) -and `
        (-not (Test-Path -LiteralPath (Join-Path $Repo 'evidence\appeared.txt')))) `
    ("APPEARED-UNTRACKED is a DETECTION line and RESTORED-NEW is the ACTION; evidence/appeared.txt is gone={0}" -f (-not (Test-Path -LiteralPath (Join-Path $Repo 'evidence\appeared.txt'))))
Check 'W15_an_emptied_declared_directory_is_pruned' `
    ((-not (Test-Path -LiteralPath (Join-Path $Repo 'evidence\newdir'))) -and (@($manifest | Where-Object { $_ -eq 'PRUNED-EMPTY-DIR evidence/newdir' }).Count -eq 1)) `
    ("evidence/newdir (created during the run, emptied by the file-level deletion) is pruned: {0}" -f (($manifest | Where-Object { $_ -like 'PRUNED-EMPTY-DIR*' }) -join ' ;; '))
Check 'W16_a_declared_directory_that_is_not_empty_survives' (Test-Path -LiteralPath (Join-Path $Repo 'evidence\tree\leaf.txt')) `
    'evidence/tree still holds its pre-snapshot untracked file, so the prune rule (empty AND declared) leaves it alone'
Check 'W17_the_class_the_default_mode_cannot_see' `
    (-not (@($manifest | Where-Object { $_ -like ('*' + $ChangedSameLen + '*') }).Count -ge 1)) `
    ("default mode (length + mtime ticks, which the probe reset to the original value) reports {0}: an equal-length rewrite inside the same tick is INVISIBLE to it - this is the measured limit of the cheap mode, and why -HashUntracked exists" -f `
        (@($manifest | Where-Object { $_ -like ('*' + $ChangedSameLen + '*') }) -join ' ;; '))

Check 'W18_summary_counts_the_new_classes' `
    (@($manifest | Where-Object { $_ -like 'SUMMARY*' -and $_ -match 'missing-untracked=1' -and $_ -match 'changed-untracked=1' -and $_ -match 'appeared-untracked=2' -and $_ -match 'untouched=1' -and $_ -match 'pruned-dirs=1' -and $_ -match 'inventory-hashed=false' }).Count -eq 1) `
    (($manifest | Where-Object { $_ -like 'SUMMARY*' }) -join ' | ')

# ===========================================================================
#  3. The hashed mode catches what the default one cannot.
# ===========================================================================
$beforeHash = Get-McpEvidenceState -RepoRoot $Repo -HashUntracked
Write-Text -Path (Join-Path $Repo 'evidence\changed-same-length-same-tick.bin') -Text ($a + "`n")
[IO.File]::SetLastWriteTimeUtc((Join-Path $Repo 'evidence\changed-same-length-same-tick.bin'), $SamelenTicks)
$manifestHash = Restore-McpEvidence -RepoRoot $Repo -Before $beforeHash -AllowedRoots @('evidence') -HashUntracked
[IO.File]::WriteAllLines((Join-Path $OutRoot 'manifest_hashed.txt'), [string[]]$manifestHash)
Check 'W20_hash_mode_catches_the_equal_length_same_tick_rewrite' `
    (@($manifestHash | Where-Object { $_ -ceq ('CHANGED-UNTRACKED ' + $ChangedSameLen) }).Count -eq 1) `
    ("with -HashUntracked the same rewrite is named: {0}" -f (($manifestHash | Where-Object { $_ -like 'CHANGED-UNTRACKED *' }) -join ' ;; '))
Check 'W21_hash_mode_identity_string_carries_the_digest' `
    ((@($beforeHash.UntrackedInventory[$ChangedSameLen]) -match '^[0-9]+:[0-9]+:[0-9a-f]{64}$') -and ($beforeHash.UntrackedInventoryHashed -eq $true)) `
    ("identity = '{0}' (length:mtime:sha256) and inventory-hashed={1}" -f $beforeHash.UntrackedInventory[$ChangedSameLen], $beforeHash.UntrackedInventoryHashed)

# ===========================================================================
#  4. Declared vs undeclared: the same loss with the default-deny answer.
# ===========================================================================
Write-Text -Path (Join-Path $Repo 'docs\gone.txt') -Text "undeclared victim, exists before the snapshot.`n"
$beforeDeny = Get-McpEvidenceState -RepoRoot $Repo
Remove-Item -LiteralPath (Join-Path $Repo 'docs\gone.txt') -Force
$manifestDeny = Restore-McpEvidence -RepoRoot $Repo -Before $beforeDeny
Check 'W30_an_undeclared_loss_is_named_as_untouched_and_not_counted_as_a_leftover' `
    ((@($manifestDeny | Where-Object { $_ -ceq ('UNTOUCHED-MISSING-UNTRACKED ' + $GoneUndeclared) }).Count -eq 1) -and `
        (@($manifestDeny | Where-Object { $_ -like 'MISSING-UNTRACKED *' }).Count -eq 0) -and `
        (@($manifestDeny | Where-Object { $_ -like 'SUMMARY*' -and $_ -match 'missing-untracked=0' }).Count -eq 1)) `
    ("the undeclared loss is reported as UNTOUCHED-MISSING-UNTRACKED (named, never touched) while the DECLARED counter stays 0: {0}" -f `
        (($manifestDeny | Where-Object { $_ -like 'UNTOUCHED-MISSING-UNTRACKED *' }) -join ' ;; '))

# ===========================================================================
#  5. Real repository: cost, and the no-trace guarantee.
# ===========================================================================
$RealBefore = @(& git -C $RepoRoot status --porcelain -uall 2>$null)
$RealBeforeSha = Get-PorcelainSha -Repo $RepoRoot -Lines $RealBefore

$t0 = Get-Date
$realPlain = Get-McpUntrackedInventory -RepoRoot $RepoRoot
$plainMs = ((Get-Date) - $t0).TotalMilliseconds
$t1 = Get-Date
$realHashed = Get-McpUntrackedInventory -RepoRoot $RepoRoot -HashUntracked
$hashedMs = ((Get-Date) - $t1).TotalMilliseconds
$t2 = Get-Date
$realState = Get-McpEvidenceState -RepoRoot $RepoRoot
$snapshotMs = ((Get-Date) - $t2).TotalMilliseconds
$t3 = Get-Date
$realStateHashed = Get-McpEvidenceState -RepoRoot $RepoRoot -HashUntracked
$snapshotHashedMs = ((Get-Date) - $t3).TotalMilliseconds

Check 'W40_the_real_repository_inventory_is_measurable_and_cheap' (($realPlain.Count -gt 0) -and ($plainMs -lt 30000)) `
    ("{0} untracked files: inventory {1:n0} ms (default) vs {2:n0} ms (hashed); a full guard snapshot {3:n0} ms (default) vs {4:n0} ms (hashed) - one git call per snapshot, one Get-Item per untracked file, no file content read in the default mode" -f `
        $realPlain.Count, $plainMs, $hashedMs, $snapshotMs, $snapshotHashedMs)
Check 'W41_the_real_snapshot_is_file_level' `
    ((@($realState.Untracked).Count -eq @($realState.UntrackedInventory.Keys).Count) -and (@($realState.Untracked).Count -gt 0)) `
    ("the real repository's untracked set and its inventory have the same size ({0}), so no directory entry is masquerading as a file" -f @($realState.Untracked).Count)

$CostReport = New-Object System.Collections.Generic.List[string]
$CostReport.Add(('scratch repo untracked files: {0}' -f @($beforeShot.Untracked).Count))
$CostReport.Add(('real repo untracked files: {0}' -f $realPlain.Count))
$CostReport.Add(('real repo inventory, default (path+length+mtime): {0:n0} ms' -f $plainMs))
$CostReport.Add(('real repo inventory, -HashUntracked (adds sha256 per file): {0:n0} ms' -f $hashedMs))
$CostReport.Add(('real repo full guard snapshot Get-McpEvidenceState, default: {0:n0} ms' -f $snapshotMs))
$CostReport.Add(('real repo full guard snapshot Get-McpEvidenceState, hashed: {0:n0} ms' -f $snapshotHashedMs))
$CostReport.Add(('default mode catches: deletion, appearance, and any rewrite that changes length or mtime ticks'))
$CostReport.Add(('default mode misses: an equal-length rewrite inside the same mtime tick (measured: W17)'))
$CostReport.Add(('-HashUntracked catches: that case too (measured: W20)'))
$CostReport.Add(('neither mode can RESTORE a missing or a changed untracked file - detection only'))
[IO.File]::WriteAllLines((Join-Path $OutRoot 'cost.txt'), $CostReport.ToArray())
foreach ($line in $CostReport) { Write-Host ('  cost| ' + $line) }

# The scratch repository must end where it started too, and the real repository
# must be untouched BYTE FOR BYTE by everything above.
Remove-Item -Recurse -Force $OutRoot -ErrorAction SilentlyContinue
$RealAfter = @(& git -C $RepoRoot status --porcelain -uall 2>$null)
$RealAfterSha = Get-PorcelainSha -Repo $RepoRoot -Lines $RealAfter
$RealDiff = @(Compare-Object $RealBefore $RealAfter)
Check 'W50_the_real_repository_porcelain_is_byte_identical' (($RealDiff.Count -eq 0) -and ($RealBeforeSha -ceq $RealAfterSha)) `
    ("git status --porcelain -uall before={0} line(s) sha256={1} after={2} line(s) sha256={3} differing={4}" -f `
        $RealBefore.Count, $RealBeforeSha.Substring(0, 12), $RealAfter.Count, $RealAfterSha.Substring(0, 12), $RealDiff.Count)

Write-Host ''
Write-Host ("PROBE FAILURES: {0}" -f $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
Write-Host 'TASK-071 FILE-LEVEL INVENTORY PROBE PASS (MISSING/APPEARED/CHANGED are named; only APPEARED is restorable; -HashUntracked buys the same-tick case; the repository is untouched)'
exit 0
