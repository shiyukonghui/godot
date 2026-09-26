# =============================================================================
#  mcp_evidence_guard.ps1 -- TASK-057 section 3 (R-B3).
#
#  The 15 step regression battery rewrites the *tracked* evidence files of the
#  batches it re-runs (13 of the 15 steps do; ONE of them, the B-tier evidence,
#  additionally CREATES a file that no batch ever committed:
#  docs/reports/evidence/task051/red/e20_child_status.json). Rewriting a tracked
#  file is not a cosmetic issue here: those files are the historical record a
#  report cites, so re-running a battery silently replaces the evidence with
#  today's run and the citation becomes unverifiable. The audit that found this
#  (R-B3) had to run `git checkout -- .` by hand afterwards.
#
#  This helper turns that hand step into a machine step - option 2 of the task
#  book ("restore automatically and print the restore manifest"). Option 1
#  ("write to %TEMP% only") was NOT taken for the step scripts because their
#  output paths are part of each task's own declared evidence contract: 13
#  scripts x several files each would have to be re-pointed, each one changing a
#  frozen report's cited path. A snapshot/restore works for any step, including
#  steps added later, without touching a single writer.
#
#  The battery's OWN aggregate logs *are* redirected to %TEMP% (a battery that
#  immediately restores its own output would write nothing); everything the
#  steps write is restored.
#
#  What is restored (TASK-069 section 1: declared artifacts ONLY):
#    * tracked files that were clean before the run and are modified after it
#      -> `git checkout -- <path>`;
#    * paths that did not exist before the run and do after it
#      -> deleted (files and directories).
#    BOTH halves are gated on the caller's declaration (`-AllowedPaths` /
#    `-AllowedRoots`), and the default is DENY: a path the caller did not declare
#    is reported as `UNTOUCHED` and left exactly as it is.
#  What is NOT restored (and is printed loudly):
#    * tracked files that were ALREADY modified before the run. They are not
#      this battery's doing, and restoring them would throw away work that is
#      not the battery's to throw away.
#    * **TASK-071 section A - detected but not restorable**: an untracked file
#      that was there BEFORE the snapshot and is gone after it
#      (`MISSING-UNTRACKED`), and one that is still there with a different
#      length / mtime / (with `-HashUntracked`) content (`CHANGED-UNTRACKED`).
#      git holds no bytes for either, so there is nothing to put back; the guard
#      now NAMES them instead of reporting silence as success. The untracked set
#      is a FILE-level inventory (`git status --porcelain -uall`), which is what
#      makes a deletion and an activity inside an untracked directory visible at
#      all (measured invisible in TASK-070 section 5).
#
#  WHY THE DECLARATION EXISTS (TASK-069, measured): the first version of this
#  helper deleted **every** path that appeared after its snapshot. That is not a
#  restore, it is a sweep that also owns files no step of the battery created:
#  the TASK-069 reproduction planted an untracked report while the battery ran and
#  the manifest read
#      REMOVED modules/mcp_server/docs/reports/REPORT-069-planted-untracked-during-PRE.md
#  next to the one path a step really creates, and the battery then reported
#  `newly untracked=0`. The declaration is a path whitelist, not an ignore list:
#  everything outside it is default-denied, and `Test-McpDeclaredPath` refuses a
#  declaration that normalises to the empty string (which would mean "everything").
#
#  Every function takes the repository root explicitly and never assumes a
#  current directory, so the caller can snapshot across a `Push-Location`.
#
#  Pure ASCII on purpose (Windows PowerShell 5.1 reads a .ps1 with the ANSI code
#  page unless it has a BOM).
# =============================================================================

function Get-McpUntrackedInventory {
    <#
      .SYNOPSIS
        Every untracked FILE of the work tree, as `path -> identity string`.
      .DESCRIPTION
        TASK-071 section A. The snapshot used to read
        `git status --porcelain -unormal`, which reports a wholly untracked
        directory as ONE entry ending in '/'. That is enough to delete a
        directory that appeared during a run, and it is blind to two things
        measured in TASK-070 section 5:

          * a file that was THERE before the snapshot and was deleted by
            something that did not go through the guard (the entry never
            appeared in any "new" set, so nothing ever looked at it);
          * any activity INSIDE an already-untracked directory (the directory is
            one entry both before and after, so creating or rewriting a file in
            there changes neither set).

        This function asks git for the FILE level instead (`-uall`) and pairs
        every untracked file with an identity string:

          * default        : '<length>:<LastWriteTimeUtc.Ticks>'
          * -HashUntracked : '<length>:<LastWriteTimeUtc.Ticks>:<sha256>'

        The default reads metadata only (one `Get-Item` per file, no file
        content), which is what keeps it affordable on every guard call
        (measured: TASK-071 report section A.3). The hashed variant also says
        whether the bytes really changed instead of inferring it from length and
        mtime, at the cost of reading every untracked file.

        A path that is a DIRECTORY is recorded as 'dir:<ticks>'. `-uall` never
        reports one, but a `status.showUntrackedFiles` override in a config file
        could, and silently dropping it would reintroduce a blind spot.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string[]]$Lines = $null,
        [switch]$HashUntracked
    )

    if ($null -eq $Lines) { $Lines = @(& git -C $RepoRoot status --porcelain -uall) }

    $inventory = @{}
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Length -lt 4) { continue }
        if ($line.Substring(0, 2) -ne '??') { continue }
        $rel = $line.Substring(3).Trim('"')
        $full = Join-Path $RepoRoot $rel
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $item = Get-Item -LiteralPath $full
            $value = ('{0}:{1}' -f $item.Length, $item.LastWriteTimeUtc.Ticks)
            if ($HashUntracked) {
                # A file another process is holding open cannot be read. It is
                # recorded as unreadable instead of aborting the whole guard: an
                # inventory that dies on one locked file (a log being written, a
                # probe's own tee target) is worse than one that says what it
                # could not do. Two snapshots that both find it unreadable are
                # equal, which is the conservative answer.
                $digest = 'unreadable'
                try {
                    $digest = (Get-FileHash -Algorithm SHA256 -LiteralPath $full -ErrorAction Stop).Hash.ToLower()
                } catch {
                    $digest = 'unreadable'
                }
                $value = $value + ':' + $digest
            }
        } elseif (Test-Path -LiteralPath $full -PathType Container) {
            $item = Get-Item -LiteralPath $full
            $value = ('dir:{0}' -f $item.LastWriteTimeUtc.Ticks)
        } else {
            # Neither a file nor a directory: the entry names something git saw
            # and the filesystem does not. Recorded rather than dropped.
            $value = 'absent'
        }
        $inventory[$rel] = $value
    }
    return $inventory
}

function Compare-McpUntrackedInventory {
    <#
      .SYNOPSIS
        The three file-level differences of TASK-071 section A.
      .DESCRIPTION
        `-Before` / `-After` are the hashtables `Get-McpUntrackedInventory`
        returns. The result has exactly three sets:

          Missing  - present before, gone after. **DETECTABLE, NOT RESTORABLE**:
                     git holds no bytes of an untracked file, so there is
                     nothing to put back. The value of the class is that the
                     silence is replaced by a named line, which is what stops a
                     real deletion from being reported as "evidence restored".
          Appeared - absent before, present after. The class the old
                     directory-level snapshot could only see OUTSIDE an
                     untracked directory. These ARE restorable, by deletion.
          Changed  - present in both, identity string differs: length, mtime,
                     and (with `-HashUntracked`) content. Also DETECTABLE, NOT
                     RESTORABLE - the guard never kept the old bytes.

        All three are sorted string arrays so two runs can be compared and the
        manifest can be read line by line.
    #>
    param($Before, $After)

    $beforeFiles = @{}
    if ($null -ne $Before) { $beforeFiles = $Before }
    $afterFiles = @{}
    if ($null -ne $After) { $afterFiles = $After }

    $missing = New-Object System.Collections.Generic.List[string]
    $changed = New-Object System.Collections.Generic.List[string]
    $appeared = New-Object System.Collections.Generic.List[string]

    foreach ($key in @($beforeFiles.Keys)) {
        $name = [string]$key
        if (-not $afterFiles.ContainsKey($key)) { $missing.Add($name); continue }
        if ([string]$afterFiles[$key] -cne [string]$beforeFiles[$key]) { $changed.Add($name) }
    }
    foreach ($key in @($afterFiles.Keys)) {
        if (-not $beforeFiles.ContainsKey($key)) { $appeared.Add([string]$key) }
    }

    return [pscustomobject]@{
        Missing  = @($missing | Sort-Object -Unique)
        Appeared = @($appeared | Sort-Object -Unique)
        Changed  = @($changed | Sort-Object -Unique)
    }
}

function Get-McpEvidenceState {
    <#
      .SYNOPSIS
        A snapshot of the working tree as two sets of repository relative paths,
        plus a FILE-level inventory of the untracked ones.
      .DESCRIPTION
        `Modified`  holds every tracked path whose content differs from HEAD.
        `Untracked` holds every path git does not track, at the FILE level
                    (`git status --porcelain -uall`, TASK-071 section A); a
                    wholly untracked directory no longer collapses its contents
                    into one entry.
        `UntrackedInventory` is `path -> '<length>:<mtime ticks>[:sha256]'` for
                    every one of those files, the map the three difference
                    classes of `Compare-McpUntrackedInventory` are computed from.

        Both path sets are sorted strings, so two snapshots can be compared with
        Compare-Object or with plain set arithmetic.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [switch]$HashUntracked
    )

    # `-uall` is written out on purpose: the repository does not currently
    # override `status.showUntrackedFiles`, but a config file that set it to
    # `normal` would collapse whole untracked directories back into one entry and
    # silently shrink this snapshot to the directory level again.
    $lines = @(& git -C $RepoRoot status --porcelain -uall)
    $modified = New-Object System.Collections.Generic.List[string]
    $untracked = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        # Porcelain v1 columns: XY<space>path, and 'R' rows read 'XY old -> new'.
        $code = $line.Substring(0, 2)
        $rest = $line.Substring(3)
        if ($rest.Contains(' -> ')) { $rest = $rest.Split(' -> ')[-1] }
        $rest = $rest.Trim('"')
        if ($code -eq '??') {
            $untracked.Add($rest)
        } else {
            $modified.Add($rest)
        }
    }

    return @{
        Modified  = @($modified | Sort-Object -Unique)
        Untracked = @($untracked | Sort-Object -Unique)
        UntrackedInventory = Get-McpUntrackedInventory -RepoRoot $RepoRoot -Lines $lines -HashUntracked:$HashUntracked
        UntrackedInventoryHashed = [bool]$HashUntracked
    }
}

function Test-McpDeclaredPath {
    <#
      .SYNOPSIS
        Is this repository-relative path one of the artifacts the caller declared?
      .DESCRIPTION
        TASK-069 section 1. The restore below is a *restore of declared
        artifacts*, not a "delete everything that appeared" sweep; this is the
        one function that decides, and the caller declares with two lists:

          * `-AllowedPaths` : exact repository-relative paths;
          * `-AllowedRoots` : directory prefixes (a path is declared when it IS
            the root or lives under it).

        Both are matched after normalising separators to '/' and trimming a
        leading './' and trailing '/', so a caller cannot be defeated by the
        separator git happens to print.

        DEFAULT IS DENY. An entry that normalises to the empty string - '', '.',
        './', '/' - would mean "every path in the repository" and is REFUSED with
        a throw instead of being silently skipped: a blanket is exactly the
        mistake this function exists to prevent (TASK-069 task book section 1.4:
        "no ignore list, a path whitelist with default deny").
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$AllowedPaths = @(),
        [string[]]$AllowedRoots = @()
    )

    function ConvertTo-McpDeclaredForm {
        # Separators to '/', one leading './' removed, trailing '/' removed. A
        # leading '.' is deliberately NOT trimmed in general: '.godot/x' is a
        # real path in this repository and stripping the dot would rename it.
        param([string]$Value)
        $v = ($Value -replace '\\', '/').Trim()
        while ($v.StartsWith('./')) { $v = $v.Substring(2) }
        $v = $v.TrimEnd('/')
        if ($v -eq '.') { return '' }
        if ($v -eq '/') { return '' }
        return $v
    }

    $normalized = ConvertTo-McpDeclaredForm -Value $Path
    if ($normalized.Length -eq 0) { return $false }

    foreach ($entry in @($AllowedPaths)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $want = ConvertTo-McpDeclaredForm -Value $entry
        if ($want.Length -eq 0) {
            throw ("Test-McpDeclaredPath: declared path '{0}' normalises to the empty string, which would declare every path in the repository. Refusing (TASK-069)." -f $entry)
        }
        if ($normalized -ceq $want) { return $true }
    }

    foreach ($entry in @($AllowedRoots)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $root = ConvertTo-McpDeclaredForm -Value $entry
        if ($root.Length -eq 0) {
            throw ("Test-McpDeclaredPath: declared root '{0}' normalises to the empty string, which would declare every path in the repository. Refusing (TASK-069)." -f $entry)
        }
        if ($normalized -ceq $root) { return $true }
        if ($normalized.StartsWith($root + '/')) { return $true }
    }

    return $false
}

function Restore-McpEvidence {
    <#
      .SYNOPSIS
        Undo what a battery did to its DECLARED artifacts, and DETECT what it did
        to every other untracked file (TASK-071 section A).
      .DESCRIPTION
        `$Before` is the state captured by Get-McpEvidenceState before the run.
        Returns a list of manifest lines, so the caller can both print them and
        persist them next to its own logs.

        The restore uses git itself for the tracked half (so "restored" means
        "byte identical to HEAD" by construction, not "rewritten by this
        helper") and plain deletion for the appeared-untracked half.

        **Only paths declared through `-AllowedPaths` / `-AllowedRoots` are
        touched (TASK-069 section 1).** Anything else that became modified or
        appeared during the run is reported as `UNTOUCHED` and left exactly as it
        is, because a restore that owns every new path also owns the evidence
        someone wrote while the battery ran -- which is the defect measured in
        REPORT-068 section 5.4 and reproduced in TASK-069: the battery deleted
        `docs/reports/REPORT-069-planted-untracked-during-PRE.md`, a file no step
        of it ever created, and then reported `newly untracked=0`.

        With both lists empty nothing at all is touched, so "default deny" is
        the behaviour a caller who forgets to declare gets.

        **TASK-071 section A: detection is not restoration.** The three
        file-level classes of the untracked inventory are reported whether or not
        the path is declared, because their whole purpose is that a step which
        bypassed the guard is no longer invisible:

          MISSING-UNTRACKED <p>          DECLARED, was there before the snapshot,
                                         is gone now. NOT restorable (git holds
                                         no bytes of an untracked file) - the
                                         line exists so a real deletion can never
                                         be reported as evidence restored.
          CHANGED-UNTRACKED <p>          DECLARED, present but length / mtime /
                                         (with -HashUntracked) content differ.
                                         NOT restorable, same reason.
          APPEARED-UNTRACKED <p>         absent before, present after. IS
                                         restorable, by deletion.
          UNTOUCHED-MISSING-UNTRACKED    the same three classes for a path the
          UNTOUCHED-CHANGED-UNTRACKED    caller did NOT declare: reported, never
          UNTOUCHED (an appeared path)   touched.

        The manifest vocabulary:
          RESTORED <p>          tracked, was declared, is back to HEAD
          RESTORED-NEW <p>      untracked file, was declared, was deleted
          RESTORED-NEW-DIR <p>  untracked directory, was declared, was deleted
          APPEARED-UNTRACKED <p>  file-level detection: this path appeared
          UNTOUCHED <p>         untracked, undeclared: left alone
          UNTOUCHED-MODIFIED <p> tracked, undeclared: left modified
          KEPT-DIRTY-BEFORE-THE-RUN <p>  already dirty before the run
          RESTORE-FAILED <p>    declared, but still modified / still present
          MISSING-UNTRACKED <p>  declared, gone, NOT restorable
          CHANGED-UNTRACKED <p>  declared, changed, NOT restorable
          PRUNED-EMPTY-DIR <p>  a declared directory emptied by the deletions
          SUMMARY restored=... removed=... kept-dirty-before=... untouched=...
                  missing-untracked=... changed-untracked=... appeared-untracked=...
                  pruned-dirs=... inventory-hashed=...
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Before,
        [string[]]$AllowedPaths = @(),
        [string[]]$AllowedRoots = @(),
        [switch]$HashUntracked
    )

    $after = Get-McpEvidenceState -RepoRoot $RepoRoot -HashUntracked:$HashUntracked
    $manifest = New-Object System.Collections.Generic.List[string]

    $beforeModified = @($Before.Modified)
    $beforeUntracked = @($Before.Untracked)

    $newlyModified = @($after.Modified | Where-Object { $beforeModified -notcontains $_ })
    $stillDirty = @($after.Modified | Where-Object { $beforeModified -contains $_ })
    $newUntracked = @($after.Untracked | Where-Object { $beforeUntracked -notcontains $_ })
    $untouchedCount = 0

    # TASK-071 section A: the file-level diff. `$inventoryDiff` is what makes a
    # DELETION visible at all; `$newUntracked` above only ever names paths that
    # APPEARED.
    $beforeInventory = $Before.UntrackedInventory
    $hasInventory = ($null -ne $beforeInventory)
    if (-not $hasInventory) { $beforeInventory = @{} }
    # The identity strings of the two modes are not comparable: the hashed one
    # carries a fourth field, so comparing a hashed before-snapshot with a plain
    # after-snapshot would name EVERY file as CHANGED. Refuse instead of
    # producing a manifest full of false alarms.
    if ($hasInventory -and ($Before -is [hashtable]) -and $Before.ContainsKey('UntrackedInventoryHashed')) {
        $beforeHashed = [bool]$Before.UntrackedInventoryHashed
        if ($beforeHashed -ne [bool]$HashUntracked) {
            throw ('Restore-McpEvidence: -HashUntracked={0} but the before-snapshot was taken with HashUntracked={1}; take the snapshot with the same option or every untracked path would be reported as CHANGED.' -f ([bool]$HashUntracked), $beforeHashed)
        }
    }
    $inventoryDiff = Compare-McpUntrackedInventory -Before $beforeInventory -After $after.UntrackedInventory

    $missingDeclared = 0
    $changedDeclared = 0
    $appearedDetected = 0

    if ($hasInventory) {
        foreach ($path in $inventoryDiff.Missing) {
            if (Test-McpDeclaredPath -Path $path -AllowedPaths $AllowedPaths -AllowedRoots $AllowedRoots) {
                $missingDeclared++
                $manifest.Add('MISSING-UNTRACKED ' + $path)
            } else {
                $untouchedCount++
                $manifest.Add('UNTOUCHED-MISSING-UNTRACKED ' + $path)
            }
        }
        foreach ($path in $inventoryDiff.Changed) {
            if (Test-McpDeclaredPath -Path $path -AllowedPaths $AllowedPaths -AllowedRoots $AllowedRoots) {
                $changedDeclared++
                $manifest.Add('CHANGED-UNTRACKED ' + $path)
            } else {
                $untouchedCount++
                $manifest.Add('UNTOUCHED-CHANGED-UNTRACKED ' + $path)
            }
        }
    }

    $restoredCount = 0
    foreach ($path in $newlyModified) {
        if (-not (Test-McpDeclaredPath -Path $path -AllowedPaths $AllowedPaths -AllowedRoots $AllowedRoots)) {
            $untouchedCount++
            $manifest.Add('UNTOUCHED-MODIFIED ' + $path)
            continue
        }
        & git -C $RepoRoot checkout -- $path 2>&1 | Out-Null
        $restoredCount++
        $manifest.Add('RESTORED ' + $path)
    }
    if ($restoredCount -gt 0) {
        # `checkout` prints nothing; re-reading the status is the proof it took.
        $check = Get-McpEvidenceState -RepoRoot $RepoRoot
        foreach ($path in $newlyModified) {
            if (($check.Modified -contains $path) -and (Test-McpDeclaredPath -Path $path -AllowedPaths $AllowedPaths -AllowedRoots $AllowedRoots)) {
                $manifest.Add('RESTORE-FAILED ' + $path)
            }
        }
    }

    # The appeared half: the file level, plus any entry the inventory did not
    # cover (a directory under a `status.showUntrackedFiles` override), so the
    # old delete-everything-that-appeared coverage is not lost.
    $appearedPaths = @(@($inventoryDiff.Appeared) + @($newUntracked) | Sort-Object -Unique)
    $removedCount = 0
    $removedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($path in $appearedPaths) {
        $appearedDetected++
        $manifest.Add('APPEARED-UNTRACKED ' + $path)
        if (-not (Test-McpDeclaredPath -Path $path -AllowedPaths $AllowedPaths -AllowedRoots $AllowedRoots)) {
            $untouchedCount++
            $manifest.Add('UNTOUCHED ' + $path)
            continue
        }
        $full = Join-Path $RepoRoot $path
        $isDir = $path.EndsWith('/') -or (Test-Path -PathType Container $full)
        if ($isDir) {
            Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $full) {
                $manifest.Add('RESTORE-FAILED ' + $path)
            } else {
                $removedCount++
                $removedPaths.Add($path)
                $manifest.Add('RESTORED-NEW-DIR ' + $path)
            }
        } else {
            Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $full) {
                $manifest.Add('RESTORE-FAILED ' + $path)
            } else {
                $removedCount++
                $removedPaths.Add($path)
                $manifest.Add('RESTORED-NEW ' + $path)
            }
        }
    }

    # A file-level deletion cannot take the directory with it, so a declared
    # directory that only ever held the removed files would survive as an empty
    # one. Prune it - but ONLY while it is empty AND declared, so the
    # default-deny rule of TASK-069 is not weakened by a recursion.
    $prunedCount = 0
    foreach ($path in $removedPaths) {
        # `Split-Path -Parent` answers with the platform separator; every path in
        # a manifest is repository-relative with '/', so normalise.
        $dir = ((Split-Path -Parent $path) -replace '\\', '/')
        while (-not [string]::IsNullOrWhiteSpace($dir) -and $dir -ne '.' -and $dir -ne '/' -and $dir -ne '') {
            if (-not (Test-McpDeclaredPath -Path $dir -AllowedPaths $AllowedPaths -AllowedRoots $AllowedRoots)) { break }
            $fullDir = Join-Path $RepoRoot $dir
            if (-not (Test-Path -LiteralPath $fullDir -PathType Container)) { break }
            if (@(Get-ChildItem -LiteralPath $fullDir -Force -ErrorAction SilentlyContinue).Count -gt 0) { break }
            Remove-Item -LiteralPath $fullDir -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $fullDir) { break }
            $prunedCount++
            $manifest.Add('PRUNED-EMPTY-DIR ' + $dir)
            $dir = ((Split-Path -Parent $dir) -replace '\\', '/')
        }
    }

    foreach ($path in $stillDirty) {
        $manifest.Add('KEPT-DIRTY-BEFORE-THE-RUN ' + $path)
    }

    $summaryFormat = 'SUMMARY restored={0} removed={1} kept-dirty-before={2} untouched={3} missing-untracked={4} changed-untracked={5} appeared-untracked={6} pruned-dirs={7} inventory-hashed={8} (declared paths only are touched; MISSING/CHANGED are DETECTED, never restored)'
    $manifest.Add(($summaryFormat -f $restoredCount, $removedCount, $stillDirty.Count, $untouchedCount, `
                $missingDeclared, $changedDeclared, $appearedDetected, $prunedCount, ([bool]$HashUntracked).ToString().ToLower()))
    return $manifest
}

# =============================================================================
#  TASK-064 section 2 -- two evidence-capture defects measured in round 2.
#
#  Defect (i), D-4 of BREAKOUT-FINDINGS.md: the run log of the round-2 breakout
#  reused the same evidence id four times (`c2_b0_build` at 06:27:35, 06:28:15,
#  06:30:54 and 06:52:44) while the writer used `<directory>\<id>.response.json`
#  as a fixed path, so each call overwrote the previous file. 200 run-log lines
#  could be compared with what was on disk and 37 of them did not match; the
#  response a report cited for the first build existed nowhere. A reused id is
#  normal (a retried call keeps its logical name); a reused *path* is the
#  defect. The rule enforced here:
#
#    * the file name of a captured artefact always carries the run sequence and
#      the first eight hex digits of the artefact's own sha256
#      (`<id>__<seq>__<sha8>.json`), so a different payload can never land on an
#      already-written name by construction;
#    * a path that has already been written by this process is a hard error, and
#      the error names both digests when they differ (no silent overwrite);
#    * a path that already exists on disk from an EARLIER process is a hard error
#      too unless it is byte-identical to what is being written, which is what
#      makes a re-run of the same script report "this is the same evidence"
#      instead of quietly replacing historical bytes.
#
#  Defect (ii), D-9/P4b of BREAKOUT-FINDINGS.md: the round-2 `before_attach` and
#  `after_attach` snapshots of `main.tscn` had the SAME sha256
#  (`a423d468...`), because the before snapshot was taken after the 18 script
#  assignments had already happened - so the "the script really landed" claim
#  could not be attributed to the call under test. The rule enforced here: a
#  before/after pair is captured by `Write-McpEvidenceSnapshotPair`, which
#  writes the before snapshot FIRST, writes the after snapshot SECOND and then
#  requires their sha256 to differ - unless the caller explicitly passes
#  `-ExpectedIdentical` and says why (a genuine "nothing changed" control, e.g.
#  an idempotence check, which the round-2 plan wanted and could not get).
#
#  Both rules are one function call wide, so a future evidence script cannot
#  "forget" them without the call site visibly not being a capture.
#
#  Pure ASCII on purpose (Windows PowerShell 5.1 reads a .ps1 with the ANSI code
#  page unless it has a BOM).
# =============================================================================

function Get-McpEvidenceContentSha256 {
    <#
      .SYNOPSIS
        The sha256 of some bytes, as lowercase hex - the digest the evidence file
        name carries.
      .DESCRIPTION
        `-Text` takes a string (hashed as UTF-8) and `-Bytes` takes a byte
        array. The two are separate parameters rather than one polymorphic one,
        because PowerShell 5.1 would happily coerce a byte array to a string.
    #>
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Text')][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true, ParameterSetName = 'Bytes')][byte[]]$Bytes
    )
    if ($PSCmdlet.ParameterSetName -eq 'Bytes') { $payload = $Bytes }
    else { $payload = (New-Object Text.UTF8Encoding($false)).GetBytes($Text) }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLower() }
    finally { $sha.Dispose() }
}

function New-McpEvidencePath {
    <#
      .SYNOPSIS
        `<Directory>\<Leaf>__<seq>__<sha8><Extension>` - the unique evidence
        name of TASK-064 section 2 (i).
      .DESCRIPTION
        `-Leaf` is the logical claim name (e.g. `c2_b0_build`, `main.tscn`),
        `-Seq` the run sequence of that claim and `-ContentSha256` the digest of
        the payload. `-Extension` defaults to `.json`; pass `.request.json` or
        `.response.json` for the tool-call pair, or `.tscn` for a scene copy.
        `-Id` is an optional readable id embedded between the leaf and the
        sequence when the claim is shared by several calls.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Leaf,
        [Parameter(Mandatory = $true)][int]$Seq,
        [Parameter(Mandatory = $true)][string]$ContentSha256,
        [string]$Extension = '.json',
        [string]$Id = ''
    )
    if ($ContentSha256 -notmatch '^[0-9a-f]{64}$') {
        throw ("New-McpEvidencePath: ContentSha256 must be 64 lowercase hex digits, got '{0}'" -f $ContentSha256)
    }
    $safe = ($Leaf -replace '[^A-Za-z0-9._-]', '_')
    $middle = if ([string]::IsNullOrWhiteSpace($Id)) { '' } else { '__' + ($Id -replace '[^A-Za-z0-9._-]', '_') }
    $name = ('{0}{1}__{2:d4}__{3}{4}' -f $safe, $middle, $Seq, $ContentSha256.Substring(0, 8), $Extension)
    return (Join-Path $Directory $name)
}

function Get-McpEvidenceSha8 {
    <#
      .SYNOPSIS
        The first eight hex digits of the sha256 of the bytes at `-Path`.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw ("Get-McpEvidenceSha8: no such file: {0}" -f $Path) }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower().Substring(0, 8)
}

function Assert-McpEvidencePathUnused {
    <#
      .SYNOPSIS
        Hard error when the same path is about to receive DIFFERENT content -
        within this process or from an earlier run (TASK-064 section 2 (i)).
      .DESCRIPTION
        The invariant is one sentence: **one evidence path, one content**. A path
        that is asked to hold different bytes than it already holds - in this
        run's registry or on disk from an earlier run - is refused with both
        digests named. A path asked to hold exactly the bytes it already holds is
        not an overwrite at all; it is accepted and reported via
        `-SameContentSeen` so the caller can say "this evidence was reproduced
        byte for byte" instead of quietly rewriting history.

        Do not confuse the two halves of the round-2 defect: a REUSED ID is
        normal (a retried call keeps its logical name) and is allowed; a reused
        ID that lands on the same PATH with different bytes is the defect, and
        the naming convention of `New-McpEvidencePath` plus this refusal is what
        makes it impossible.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )
    if (-not $script:McpEvidenceWrittenPaths) { $script:McpEvidenceWrittenPaths = @{} }
    $newHash = Get-McpEvidenceContentSha256 -Bytes $Bytes
    $seen = $null
    if ($script:McpEvidenceWrittenPaths.ContainsKey($Path)) { $seen = [string]$script:McpEvidenceWrittenPaths[$Path] }
    if ($null -ne $seen -and $seen -cne $newHash) {
        throw ('evidence path already holds DIFFERENT content in this run: {0} first sha256={1}, now sha256={2}. This is the c2_b0_build overwrite defect; chain a sequence token instead.' -f $Path, $seen, $newHash)
    }
    $sameContent = ($null -ne $seen)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $existing = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
        if ($existing -cne $newHash) {
            throw ('evidence path already exists with DIFFERENT content: {0} on disk sha256={1}, about to write sha256={2}. Refusing to overwrite evidence that is already cited.' -f $Path, $existing, $newHash)
        }
        $sameContent = $true
    }
    # Deliberately no side effect here: the path enters the "already written"
    # registry only when the bytes are really written (`Write-McpEvidenceBytes`).
    # A guard call that throws (an assert-only caller, or a capture that fails
    # before writing) must not make the same path unusable for the retry.
    return [pscustomobject]@{ Path = $Path; Sha256 = $newHash; Sha8 = $newHash.Substring(0, 8); SameContentSeen = $sameContent }
}

function Write-McpEvidenceBytes {
    <#
      .SYNOPSIS
        Write one evidence artefact under the TASK-064 (i) rules and return what
        was written (path, sha256, sha8, sequence).
      .DESCRIPTION
        The sequence is per `-Leaf` unless the caller passes `-Seq` explicitly
        (use the latter when the sequence has to agree with something else, such
        as a tool call's own sequence in the trace). `-Id` is embedded in the
        name when several distinct claims share a leaf.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Leaf,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [string]$Extension = '.json',
        [string]$Id = '',
        [int]$Seq = -1
    )
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    }
    if ($Seq -lt 0) {
        if (-not $script:McpEvidenceSeq) { $script:McpEvidenceSeq = @{} }
        $key = $Leaf + '|' + $Id
        if (-not $script:McpEvidenceSeq.ContainsKey($key)) { $script:McpEvidenceSeq[$key] = 0 }
        $Seq = [int]$script:McpEvidenceSeq[$key] + 1
        $script:McpEvidenceSeq[$key] = $Seq
    }
    $hash = Get-McpEvidenceContentSha256 -Bytes $Bytes
    $path = New-McpEvidencePath -Directory $Directory -Leaf $Leaf -Seq $Seq -ContentSha256 $hash -Extension $Extension -Id $Id
    $check = Assert-McpEvidencePathUnused -Path $path -Bytes $Bytes
    [IO.File]::WriteAllBytes($path, $Bytes)
    # Registered only now, so the guard's "same path twice" answer is about paths
    # that really hold bytes (TASK-064 section 2 (i)).
    if (-not $script:McpEvidenceWrittenPaths) { $script:McpEvidenceWrittenPaths = @{} }
    $script:McpEvidenceWrittenPaths[$path] = $hash
    $inName = Get-McpEvidenceSha8 -Path $path
    if ($inName -cne $hash.Substring(0, 8)) {
        throw ('evidence name does not carry the content digest: {0} carries {1}, content is {2}' -f $path, $inName, $hash.Substring(0, 8))
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower() -cne $hash) {
        throw ('evidence file on disk does not hash to what was written: {0}' -f $path)
    }
    return [pscustomobject]@{
        Path = $path; Name = (Split-Path -Leaf $path); Sha256 = $hash; Sha8 = $hash.Substring(0, 8)
        Bytes = $Bytes.Length; Seq = $Seq; SameContentSeen = [bool]$check.SameContentSeen
    }
}

function Write-McpEvidenceText {
    <#
      .SYNOPSIS
        `Write-McpEvidenceBytes` for a string (UTF-8, no BOM).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Leaf,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [string]$Extension = '.json',
        [string]$Id = '',
        [int]$Seq = -1
    )
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
    return (Write-McpEvidenceBytes -Directory $Directory -Leaf $Leaf -Bytes $bytes -Extension $Extension -Id $Id -Seq $Seq)
}

function Write-McpEvidenceSnapshotPair {
    <#
      .SYNOPSIS
        Capture a before/after pair in order and assert the pair really moved
        (TASK-064 section 2 (ii)).
      .DESCRIPTION
        `-Before` is invoked FIRST and `-After` LAST, with `-Between` (a
        scriptblock, optional) run between the two captures - so the ordering of
        the three steps is a property of this function and not of the caller's
        indentation. Each capture scriptblock must return something
        `Write-McpEvidenceBytes` can write:

          a string, a byte array, or a FileInfo (whose bytes are read).

        After both files are on disk the two sha256 digests are compared. They
        must DIFFER. Pass `-ExpectedIdentical -Reason '<why no change is the
        point>'` for a genuine control where equality is the expected outcome
        (an idempotence check, or "a refused write really changed nothing"); the
        digest equality is then asserted instead, and the reason is echoed.

        This is the assertion the round-2 `main.tscn.before_attach` /
        `after_attach` pair did not have: those two files had the same sha256
        (`a423d468...`) because the before snapshot already contained the 18
        `script = ExtResource(...)` lines, so P4b could not attribute the read
        back to the call under test (BREAKOUT-FINDINGS.md D-9/P4b).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Leaf,
        [Parameter(Mandatory = $true)][scriptblock]$Before,
        [Parameter(Mandatory = $true)][scriptblock]$After,
        [scriptblock]$Between = $null,
        [string]$Extension = '.txt',
        [switch]$ExpectedIdentical,
        [string]$Reason = ''
    )
    function ConvertTo-McpEvidenceBytes {
        param($Value)
        if ($null -eq $Value) { throw 'snapshot scriptblock returned $null; use @() or an empty string for an empty capture' }
        if ($Value -is [byte[]]) { return $Value }
        if ($Value -is [string]) { return (New-Object Text.UTF8Encoding($false)).GetBytes($Value) }
        if ($Value -is [IO.FileInfo]) { return [IO.File]::ReadAllBytes($Value.FullName) }
        if ($Value -is [System.Array]) { return [byte[]]$Value }
        throw ('snapshot scriptblock returned an unsupported type: {0}' -f $Value.GetType().FullName)
    }

    $beforeBytes = ConvertTo-McpEvidenceBytes (& $Before)
    $beforeWritten = Write-McpEvidenceBytes -Directory $Directory -Leaf ($Leaf + '.before') -Bytes $beforeBytes -Extension $Extension
    if ($null -ne $Between) { $null = & $Between }
    $afterBytes = ConvertTo-McpEvidenceBytes (& $After)
    $afterWritten = Write-McpEvidenceBytes -Directory $Directory -Leaf ($Leaf + '.after') -Bytes $afterBytes -Extension $Extension

    $identical = ($beforeWritten.Sha256 -ceq $afterWritten.Sha256)
    if ($ExpectedIdentical) {
        if (-not $identical) {
            throw ('snapshot pair declared -ExpectedIdentical but the two captures differ: before={0} ({1}) after={2} ({3})' -f `
                $beforeWritten.Name, $beforeWritten.Sha256.Substring(0, 8), $afterWritten.Name, $afterWritten.Sha256.Substring(0, 8))
        }
        if ([string]::IsNullOrWhiteSpace($Reason)) {
            throw 'snapshot pair declared -ExpectedIdentical without -Reason; an identical pair is only evidence when the expectation is stated'
        }
    } elseif ($identical) {
        throw ('snapshot pair has the SAME sha256 ({0}) for before={1} and after={2}: the before capture already contains whatever the step under test was supposed to change, so the pair cannot attribute anything. Re-order the capture (before first) or declare -ExpectedIdentical -Reason <why equality is the point>.' -f `
            $beforeWritten.Sha256, $beforeWritten.Name, $afterWritten.Name)
    }
    return [pscustomobject]@{
        Before = $beforeWritten.Path; After = $afterWritten.Path
        BeforeSha256 = $beforeWritten.Sha256; AfterSha256 = $afterWritten.Sha256
        Identical = $identical; ExpectedIdentical = [bool]$ExpectedIdentical; Reason = $Reason
    }
}

function Assert-McpEvidenceTreeUniqueness {
    <#
      .SYNOPSIS
        Audit an existing evidence directory: same file name with two different
        contents is a hard error (TASK-064 section 2 (i), the report-time half).
      .DESCRIPTION
        The writer-side guard above prevents new collisions; this is the reader
        that proves a tree handed over as evidence has none. Two files that
        share a name can only coexist in different subdirectories, so the audit
        keys on the leaf name and reports:

          * `Collisions` - same leaf name, different sha256 (the D-4 defect);
          * `Duplicates` - same leaf name AND same sha256 (harmless, but a
            reused name is still a smell and is reported).

        `-FailOnDuplicates` turns the harmless half into an error as well, for a
        strict capture tree.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [switch]$FailOnDuplicates
    )
    $byName = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -Recurse -File | Sort-Object FullName)) {
        $leaf = [string]$file.Name
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLower()
        if (-not $byName.ContainsKey($leaf)) { $byName[$leaf] = New-Object System.Collections.Generic.List[object] }
        # `@(...)` around a List[object] makes PowerShell try to coerce the list
        # itself to the list's element type; measured as `ArgumentException:
        # Argument types do not match` on this exact line. Enumerate instead.
        $byName[$leaf].Add([pscustomobject]@{ Path = [string]$file.FullName; Sha256 = $hash })
    }
    $collisions = @()
    $duplicates = @()
    foreach ($leaf in @($byName.Keys | Sort-Object)) {
        $leaf = [string]$leaf
        $entries = @()
        foreach ($entry in $byName[$leaf]) { $entries += $entry }
        if ($entries.Count -lt 2) { continue }
        $hashes = @($entries | ForEach-Object { [string]$_.Sha256 } | Sort-Object -Unique)
        $record = [pscustomobject]@{
            Name = $leaf; Count = $entries.Count; DistinctContent = $hashes.Count
            Paths = @($entries | ForEach-Object { [string]$_.Path })
            Sha256 = @($hashes)
        }
        if ($hashes.Count -gt 1) { $collisions += $record } else { $duplicates += $record }
    }
    if ($collisions.Count -gt 0) {
        $detail = (@($collisions | ForEach-Object { ('  ' + [string]$_.Name + ' x' + [string]$_.Count + ' with ' + [string]$_.DistinctContent + ' distinct contents') }) -join "`n")
        $message = 'evidence tree has same-name files with DIFFERENT contents:' + "`n" + $detail + "`n" + [string]$Directory
        throw $message
    }
    if ($FailOnDuplicates -and $duplicates.Count -gt 0) {
        $detail = (@($duplicates | ForEach-Object { ('  ' + [string]$_.Name + ' x' + [string]$_.Count + ' (identical bytes)') }) -join "`n")
        $message = 'evidence tree reuses names for identical content and -FailOnDuplicates was given:' + "`n" + $detail + "`n" + [string]$Directory
        throw $message
    }
    return [pscustomobject]@{
        Files = [int](@(Get-ChildItem -LiteralPath $Directory -Recurse -File)).Count
        Collisions = $collisions; Duplicates = $duplicates
    }
}

