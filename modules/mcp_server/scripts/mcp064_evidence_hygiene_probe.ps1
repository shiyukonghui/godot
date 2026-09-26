# =============================================================================
#  mcp064_evidence_hygiene_probe.ps1 -- TASK-064 section 2 counterexamples.
#
#  Two evidence-capture defects were measured in round 2 (BREAKOUT-FINDINGS.md
#  D-4 and D-9):
#
#    (i)  the evidence id `c2_b0_build` was reused four times and the writer used
#         a fixed `<id>.response.json` path, so later calls silently overwrote
#         the earlier files; 37 of the 200 comparable run-log lines no longer
#         matched what was on disk;
#    (ii) the `main.tscn.before_attach` / `after_attach` pair had the SAME
#         sha256, because the "before" file already contained the 18 script
#         assignments, so the read-back could not be attributed to the call.
#
#  The guards live in `mcp_evidence_guard.ps1` (TASK-064 section 2). This probe
#  is the counterexample driver the task asks for: each defect is MANUFACTURED on
#  purpose and the guard must refuse it, then the same scenario is run the right
#  way and must succeed. Every case is asserted twice - the guard has to throw
#  (for the negative cases) or not throw (for the positive ones) AND the
#  observable artefact set has to be what the case claims.
#
#  The negative cases never touch a pre-existing path: the "path already used by
#  the same process" case derives its path from its own payload, and the "path
#  already on disk with different content" case is deliberately caused by writing
#  a file with the same name and different bytes first. Nothing under the
#  repository is written; the scratch tree is `%TEMP%\mcp064-hygiene`.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp064_evidence_hygiene_probe.ps1
#  Exit 0 when every negative case was refused and every positive case landed;
#  exit 1 otherwise (with the failing case named).
#
#  Pure ASCII on purpose (Windows PowerShell 5.1 reads a .ps1 with the ANSI code
#  page unless it has a BOM).
# =============================================================================

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $PSScriptRoot 'mcp_evidence_guard.ps1')

$Root = Join-Path $env:TEMP 'mcp064-hygiene'
if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$script:Failures = 0
$script:Cases = New-Object System.Collections.Generic.List[object]

function Check {
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][bool]$Pass, [string]$Evidence = '')
    if (-not $Pass) { $script:Failures = $script:Failures + 1 }
    $script:Cases.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    Write-Host ("[{0}] {1}" -f $(if ($Pass) { 'PASS' } else { 'FAIL' }), $Id)
    if (-not [string]::IsNullOrWhiteSpace($Evidence)) { Write-Host ("       {0}" -f $Evidence) }
}

function Test-Throws {
    param([Parameter(Mandatory = $true)][scriptblock]$Body)
    try { $null = & $Body } catch { return $_.Exception.Message }
    return ''
}

Write-Host '============================================================='
Write-Host ' TASK-064: evidence hygiene counterexamples'
Write-Host (" scratch: {0}" -f $Root)
Write-Host '============================================================='

# -----------------------------------------------------------------------------
# Case 0 - the clean path: the same logical claim captured four times (the
# c2_b0_build id) must produce four DISTINCT files, one per payload.
# -----------------------------------------------------------------------------
$dirA = Join-Path $Root 'case0-clean'
$seqWrites = New-Object System.Collections.Generic.List[object]
foreach ($pay in @('{"build":"attempt 1","exit":1}', '{"build":"attempt 2","exit":0}', '{"build":"attempt 3","exit":0}', '{"build":"attempt 4","exit":0}')) {
    $seqWrites.Add((Write-McpEvidenceText -Directory $dirA -Leaf 'c2_b0_build' -Id 'reuse' -Text $pay))
}
$distinctPaths = @($seqWrites | ForEach-Object { $_.Path } | Sort-Object -Unique).Count
$distinctNames = @($seqWrites | ForEach-Object { $_.Name } | Sort-Object -Unique).Count
Check 'case0_four_reuses_of_one_id_produce_four_files' `
    (($seqWrites.Count -eq 4) -and ($distinctPaths -eq 4) -and ($distinctNames -eq 4) -and (@(Get-ChildItem -LiteralPath $dirA -File).Count -eq 4)) `
    ("id 'c2_b0_build' written 4 times -> {0} distinct path(s), {1} file(s) on disk: {2}" -f $distinctPaths, @(Get-ChildItem -LiteralPath $dirA -File).Count, (($seqWrites | ForEach-Object { $_.Name }) -join ', '))
Check 'case0_names_carry_seq_and_sha8' `
    ((@($seqWrites | Where-Object { $_.Name -notmatch '^c2_b0_build__reuse__\d{4}__[0-9a-f]{8}\.json$' }).Count) -eq 0) `
    ("naming convention <id>__<seq>__<sha8>.json: {0}" -f (($seqWrites | ForEach-Object { $_.Name }) -join ', '))
Check 'case0_name_digest_matches_content' `
    ((@($seqWrites | Where-Object { (Get-McpEvidenceSha8 -Path $_.Path) -cne $_.Sha8 }).Count) -eq 0) `
    'each file name carries the first eight hex digits of its own sha256'

# -----------------------------------------------------------------------------
# Case 1 (defect i) - the SAME id captured twice with the SAME payload is not an
# overwrite: one path, one content, so the write is accepted and flagged. What it
# must never do is silently replace different bytes (that is case 2).
# -----------------------------------------------------------------------------
$dirB = Join-Path $Root 'case1-same-content-same-run'
$samePayload = '{"build":"attempt 1","exit":1}'
$first = Write-McpEvidenceText -Directory $dirB -Leaf 'c2_b0_build_dup' -Text $samePayload
$err1 = Test-Throws { $null = Write-McpEvidenceText -Directory $dirB -Leaf 'c2_b0_build_dup' -Text $samePayload -Seq 1 }
Check 'case1_same_path_same_content_is_not_an_overwrite' `
    (($err1 -eq '')) `
    ("guard said: {0}" -f $(if ($err1 -eq '') { '<nothing - identical bytes, so one path one content holds>' } else { $err1 }))
$second = Write-McpEvidenceText -Directory $dirB -Leaf 'c2_b0_build_dup' -Text $samePayload -Seq 1
Check 'case1_identical_reuse_is_flagged_as_reproduced_bytes' `
    (($second.Path -ceq $first.Path) -and $second.SameContentSeen -and (@(Get-ChildItem -LiteralPath $dirB -File).Count -eq 1)) `
    ("one file on disk ({0}) and SameContentSeen={1}: the caller can report 'reproduced byte for byte' instead of rewriting history" -f $second.Name, $second.SameContentSeen)
Check 'case1_the_first_artefact_still_holds_its_bytes' `
    (((Get-McpEvidenceSha8 -Path $first.Path)) -ceq $first.Sha8) `
    ("first file untouched: {0} sha8={1}" -f $first.Name, (Get-McpEvidenceSha8 -Path $first.Path))

# -----------------------------------------------------------------------------
# Case 2 (defect i) - a path already used by this process, reached with
# DIFFERENT bytes, must be refused and must name both digests. The colliding
# path is manufactured by asking the guard to reuse an explicit path.
# -----------------------------------------------------------------------------
$dirC = Join-Path $Root 'case2-different-content-same-path'
$victim = Write-McpEvidenceText -Directory $dirC -Leaf 'c2_b0_build_overwrite' -Text '{"build":"attempt 1","exit":1}'
$err2 = Test-Throws {
    $null = Assert-McpEvidencePathUnused -Path $victim.Path -Bytes ((New-Object Text.UTF8Encoding($false)).GetBytes('{"build":"attempt 2","exit":0}'))
}
$err2NamesBoth = ($err2 -match 'first sha256=[0-9a-f]{64}') -and ($err2 -match 'now sha256=[0-9a-f]{64}')
Check 'case2_same_path_different_content_is_refused' `
    (($err2 -ne '') -and ($err2 -match 'DIFFERENT content')) `
    ("guard said: {0}" -f $(if ($err2 -eq '') { '<nothing - the overwrite was allowed>' } else { $err2 }))
Check 'case2_refusal_names_both_digests' $err2NamesBoth 'the message carries both the stored and the incoming sha256 (no silent overwrite)'
Check 'case2_the_victim_file_is_still_its_original_bytes' `
    (((Get-McpEvidenceSha8 -Path $victim.Path)) -ceq $victim.Sha8) `
    ("victim untouched: {0} sha8={1} (expected {2})" -f $victim.Name, (Get-McpEvidenceSha8 -Path $victim.Path), $victim.Sha8)

# -----------------------------------------------------------------------------
# Case 3 (defect i, the report-time half) - an evidence TREE that already
# contains the same name with two different contents must fail the audit.
# -----------------------------------------------------------------------------
$dirD = Join-Path $Root 'case3-tree-audit'
$subA = Join-Path $Root 'case3-run-a'
$subB = Join-Path $Root 'case3-run-b'
New-Item -ItemType Directory -Force -Path $dirD, $subA, $subB | Out-Null
[IO.File]::WriteAllBytes((Join-Path $subA 'c2_b0_build.response.json'), (New-Object Text.UTF8Encoding($false)).GetBytes('{"attempt":1}'))
[IO.File]::WriteAllBytes((Join-Path $subB 'c2_b0_build.response.json'), (New-Object Text.UTF8Encoding($false)).GetBytes('{"attempt":2}'))
$err3 = Test-Throws { Assert-McpEvidenceTreeUniqueness -Directory $Root }
Check 'case3_tree_with_same_name_different_content_is_refused' `
    (($err3 -ne '') -and ($err3 -match 'same-name files with DIFFERENT contents')) `
    ("audit said: {0}" -f $(if ($err3 -eq '') { '<nothing - the collision was accepted>' } else { ($err3 -split "`n")[0] }))

# ... and the same audit passes on a tree whose names are unique (case 0's).
$audit0 = Assert-McpEvidenceTreeUniqueness -Directory $dirA
Check 'case3_tree_with_unique_names_passes' `
    (($audit0.Collisions.Count -eq 0) -and ($audit0.Files -eq 4)) `
    ("case0 tree: {0} file(s), {1} collision(s), {2} duplicate name(s)" -f $audit0.Files, $audit0.Collisions.Count, $audit0.Duplicates.Count)

# -----------------------------------------------------------------------------
# Case 4 (defect ii) - a before/after pair that did not move is refused, and the
# refusal says why it cannot be used as evidence. This is the round-2
# main.tscn.before_attach / after_attach situation reproduced exactly: the
# "before" payload already contains what the step was supposed to add.
# -----------------------------------------------------------------------------
$dirE = Join-Path $Root 'case4-frozen-pair'
$sceneWithScript = "[node name=`"Brick`" type=`"Node2D`"]`nscript = ExtResource(`"1_t6lrv`")`n"
$err4 = Test-Throws {
    Write-McpEvidenceSnapshotPair -Directory $dirE -Leaf 'main.tscn' -Extension '.tscn' `
        -Before { $sceneWithScript } -After { $sceneWithScript }
}
Check 'case4_identical_pair_without_declaration_is_refused' `
    (($err4 -ne '') -and ($err4 -match 'SAME sha256')) `
    ("guard said: {0}" -f $(if ($err4 -eq '') { '<nothing - the frozen pair was accepted>' } else { ($err4 -split "`n")[0] }))

# -----------------------------------------------------------------------------
# Case 5 (defect ii, the correct run) - before first, the step between, after
# last: the pair must differ and must be attributable. This is what P4b needed.
# -----------------------------------------------------------------------------
$dirF = Join-Path $Root 'case5-ordered-pair'
$sceneBefore = "[node name=`"Brick`" type=`"Node2D`"]`n"
$sceneAfter = "[node name=`"Brick`" type=`"Node2D`"]`nscript = ExtResource(`"1_t6lrv`")`n"
$pair = Write-McpEvidenceSnapshotPair -Directory $dirF -Leaf 'main.tscn' -Extension '.tscn' `
    -Before { $sceneBefore } -Between { $null = 'the attach call happens here' } -After { $sceneAfter }
Check 'case5_ordered_pair_differs_and_is_attributable' `
    ((-not $pair.Identical) -and ($pair.BeforeSha256 -cne $pair.AfterSha256) -and (Test-Path -LiteralPath $pair.Before) -and (Test-Path -LiteralPath $pair.After)) `
    ("before={0} ({1}) -> after={2} ({3})" -f (Split-Path -Leaf $pair.Before), $pair.BeforeSha256.Substring(0, 8), (Split-Path -Leaf $pair.After), $pair.AfterSha256.Substring(0, 8))
Check 'case5_pair_names_carry_their_own_sha8' `
    (((Split-Path -Leaf $pair.Before) -match ([regex]::Escape($pair.BeforeSha256.Substring(0, 8)))) -and ((Split-Path -Leaf $pair.After) -match ([regex]::Escape($pair.AfterSha256.Substring(0, 8))))) `
    ("{0} / {1}" -f (Split-Path -Leaf $pair.Before), (Split-Path -Leaf $pair.After))

# -----------------------------------------------------------------------------
# Case 6 (defect ii, the honest exception) - a pair that really did not change is
# only usable when the expectation is DECLARED and explained. Without the reason
# it is refused; with it, it passes.
# -----------------------------------------------------------------------------
$dirG = Join-Path $Root 'case6-declared-identical'
$err6a = Test-Throws {
    Write-McpEvidenceSnapshotPair -Directory $dirG -Leaf 'idempotent.tscn' -Extension '.tscn' `
        -Before { 'same bytes' } -After { 'same bytes' } -ExpectedIdentical
}
Check 'case6_expected_identical_without_a_reason_is_refused' `
    (($err6a -ne '') -and ($err6a -match 'without -Reason')) `
    ("guard said: {0}" -f $(if ($err6a -eq '') { '<nothing>' } else { ($err6a -split "`n")[0] }))
$dirG2 = Join-Path $Root 'case6b-declared-identical-ok'
$pair6 = Write-McpEvidenceSnapshotPair -Directory $dirG2 -Leaf 'idempotent.tscn' -Extension '.tscn' `
    -Before { 'same bytes' } -After { 'same bytes' } -ExpectedIdentical -Reason 'idempotence: writing the same value twice must not touch the file'
Check 'case6_declared_identical_pair_passes_and_carries_the_reason' `
    ($pair6.Identical -and ($pair6.Reason -ne '')) `
    ("identical={0} reason='{1}'" -f $pair6.Identical, $pair6.Reason)
$err6b = Test-Throws {
    Write-McpEvidenceSnapshotPair -Directory (Join-Path $Root 'case6c-declared-identical-but-moved') -Leaf 'moved.tscn' -Extension '.tscn' `
        -Before { 'before bytes' } -After { 'after bytes' } -ExpectedIdentical -Reason 'this should not be identical'
}
Check 'case6_declared_identical_but_the_pair_moved_is_refused' `
    (($err6b -ne '') -and ($err6b -match 'declared -ExpectedIdentical but the two captures differ')) `
    ("guard said: {0}" -f $(if ($err6b -eq '') { '<nothing>' } else { ($err6b -split "`n")[0] }))

# -----------------------------------------------------------------------------
# Case 7 - a replay in a SEPARATE process that reproduces identical bytes is not
# a silent overwrite: it is accepted and flagged, so the caller can report it.
# -----------------------------------------------------------------------------
$dirH = Join-Path $Root 'case7-separate-process-replay'
$r1 = Write-McpEvidenceText -Directory $dirH -Leaf 'replay' -Text '{"same":true}'
$r2 = Write-McpEvidenceText -Directory $dirH -Leaf 'replay' -Text '{"same":true}'
Check 'case7_same_bytes_twice_receive_distinct_paths' `
    (($r1.Sha256 -ceq $r2.Sha256) -and ($r1.Path -cne $r2.Path) -and (@(Get-ChildItem -LiteralPath $dirH -File).Count -eq 2)) `
    ("{0} and {1} carry the same sha256 {2}; the sequence token is what makes a repeated capture land somewhere new" -f $r1.Name, $r2.Name, $r1.Sha256.Substring(0, 8))

# -----------------------------------------------------------------------------
# Case 8 - the D-4 headline, end to end: replay the OLD writer (fixed
# `<id>.response.json`) and show that the audit finds the collision, then replay
# the NEW writer on the same payload sequence and show it does not. This is the
# "37 of 200" defect, reduced to the shape that matters: four captures of one id.
# -----------------------------------------------------------------------------
function Write-McpEvidenceOldStyle {
    param([Parameter(Mandatory = $true)][string]$Directory, [Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$Text)
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { New-Item -ItemType Directory -Force -Path $Directory | Out-Null }
    $path = Join-Path $Directory ($Id + '.response.json')
    [IO.File]::WriteAllBytes($path, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
    return $path
}

$dirOld = Join-Path $Root 'case8-old-writer'
$oldPayloads = @('{"build":"attempt 1","exit":1}', '{"build":"attempt 2","exit":0}', '{"build":"attempt 3","exit":0}', '{"build":"attempt 4","exit":0}')
foreach ($pay in $oldPayloads) { $null = Write-McpEvidenceOldStyle -Directory $dirOld -Id 'c2_b0_build' -Text $pay }
$oldNames = @(Get-ChildItem -LiteralPath $dirOld -File | ForEach-Object { $_.Name })
$oldPayloadForName = '{"build":"attempt 1","exit":1}'
$oldHashOfFirstPayload = Get-McpEvidenceContentSha256 -Text $oldPayloadForName
$oldHashOnDisk = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dirOld 'c2_b0_build.response.json')).Hash.ToLower()
$oldErr = Test-Throws { Assert-McpEvidenceTreeUniqueness -Directory $dirOld }
Check 'case8_old_fixed_name_writer_loses_three_of_four_captures' `
    (($oldNames.Count -eq 1) -and ($oldHashOnDisk -cne $oldHashOfFirstPayload) -and ($oldErr -eq '')) `
    ("old writer wrote 4 payloads to 1 name ({0}); the file no longer holds payload 1 ({1} vs {2}); the tree audit sees NOTHING because the other three files are gone. This is exactly D-4 ('37 of 200 run-log lines no longer matched disk'): the defect is invisibility, not just overwriting." -f `
        ($oldNames -join ', '), $oldHashOnDisk.Substring(0, 8), $oldHashOfFirstPayload.Substring(0, 8))

$dirNew = Join-Path $Root 'case8-new-writer'
$newWritten = New-Object System.Collections.Generic.List[object]
foreach ($pay in $oldPayloads) { $newWritten.Add((Write-McpEvidenceText -Directory $dirNew -Leaf 'c2_b0_build' -Text $pay)) }
$newAudit = Assert-McpEvidenceTreeUniqueness -Directory $dirNew
$allFourRecoverable = $true
foreach ($pay in $oldPayloads) {
    $h = (Get-McpEvidenceContentSha256 -Text $pay).Substring(0, 8)
    $matches = @($newWritten | Where-Object { $_.Sha8 -ceq $h })
    if ($matches.Count -ne 1) { $allFourRecoverable = $false }
    $bytesOk = $false
    if ($matches.Count -eq 1 -and (Test-Path -LiteralPath $matches[0].Path)) {
        $onDisk = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($matches[0].Path))
        $bytesOk = ($onDisk -ceq $pay)
    }
    if (-not $bytesOk) { $allFourRecoverable = $false }
}
Check 'case8_new_writer_keeps_every_capture_and_the_audit_is_clean' `
    (($newWritten.Count -eq 4) -and ($newAudit.Collisions.Count -eq 0) -and $allFourRecoverable -and (@(Get-ChildItem -LiteralPath $dirNew -File).Count -eq 4)) `
    ("4 payloads -> 4 files, each named after its own digest and each holding its own payload byte for byte: {0}" -f (($newWritten | ForEach-Object { $_.Name }) -join ', '))

Write-Host ''
Write-Host ("cases={0} failures={1}" -f $script:Cases.Count, $script:Failures)
if ($script:Failures -gt 0) {
    Write-Host 'TASK-064 EVIDENCE HYGIENE PROBE FAILED'
    exit 1
}
Write-Host 'TASK-064 EVIDENCE HYGIENE PROBE PASS (every manufactured overwrite / frozen pair was refused; every correct capture landed)'

# Hand the scratch tree over as a self-describing artefact rather than leaving
# it nameless under %TEMP%: the audit below is the same function an evidence
# script is expected to call on its own output before publishing it.
$treeAudit = Assert-McpEvidenceTreeUniqueness -Directory (Join-Path $Root 'case0-clean')
$handover = [pscustomobject]@{
    task = 'TASK-064 section 2'
    scratch = $Root
    cases = $script:Cases.Count
    failures = $script:Failures
    clean_tree_files = $treeAudit.Files
    clean_tree_collisions = $treeAudit.Collisions.Count
    clean_tree_duplicate_names = $treeAudit.Duplicates.Count
    cases_detail = $script:Cases
}
[IO.File]::WriteAllBytes((Join-Path $Root 'mcp064-hygiene-cases.json'), (New-Object Text.UTF8Encoding($false)).GetBytes((ConvertTo-Json -InputObject $handover -Depth 8)))
Write-Host ("handover written: {0}" -f (Join-Path $Root 'mcp064-hygiene-cases.json'))
exit 0
