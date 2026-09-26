# =============================================================================
#  mcp025_gate6_index_experiments.ps1 -- live evidence for TASK-025 item (1)
#
#  The narrowing-point guardrail (`docs/DESIGN-DETAIL.md` section 22 / GDR-24,
#  PLAYBOOK gate 6) is only useful if its failures mean something. Until
#  TASK-025 the script *claimed* - in its own docstring, in its `PINNED` comment
#  and in REPORT-023's deviation item 4 - that a pin is identified by
#  "(file, marker id, occurrence inside the file)" and that a drifted line is
#  only a note. The implementation did the opposite: `report()` looked the pin
#  up as `PINNED[file][point["line"]]`, a **line key**. Any unrelated edit above
#  a pinned point therefore answered `UNLISTED` (a false red), and every batch
#  had to re-pin by hand (TASK-024b renumbered `tools/tool_helpers.cpp`
#  851 -> 986 for exactly this reason).
#
#  TASK-025 made the lookup match the claim. This script demonstrates, on the
#  real tree, that the three failure conditions still work and that drift no
#  longer does:
#
#    E1  drift          - 20 comment lines inserted above a pinned point, no
#                         re-pinning: **exit 0**, with a `drifted` note;
#    E2  unannotated    - a bare `(real_t)` cast inserted: **exit 1**, named as
#                         a point with no `// MCP-NARROWING:` marker;
#    E3  stale entry    - a marker id renamed in the source: **exit 1**, named as
#                         a pinned marker with no matching point any more;
#    E4  baseline       - the tree restored: **exit 0**.
#
#  E0 is the pre-TASK-025 contrast, run in %TEMP% against a `git archive` copy of
#  **the commit TASK-025 started from** (`-PreTask025Commit`, default
#  `0b120996ff`) - never against `HEAD`, which after TASK-025's own commit holds
#  the replacement script. Nothing in the repository is mutated for it: the
#  identical drift that makes the old, line-keyed lookup answer `UNLISTED` is
#  only a `moved` note under the identity index (E1).
#
#  Every experiment that touches the real tree reverts with `git checkout --`
#  and asserts the file's sha256 is byte-identical to the pre-experiment one, so
#  a crash cannot leave the working tree dirty.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp025_gate6_index_experiments.ps1
# =============================================================================

param(
    [string]$RepoRoot = '',
    # The commit the pre-TASK-025 guardrail (and the `PINNED` list it was
    # written for) lives in. It is a *fixed* commit, not `HEAD`: TASK-025
    # commits the replacement script and the new `PINNED` list, so reading
    # "the old one" from HEAD after that commit would compare the new script
    # with itself. Defaults to the commit TASK-025 started from; the
    # `E0_pre_task025_script_is_really_the_old_one` check below refuses to run
    # otherwise.
    [string]$PreTask025Commit = '0b120996ff'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}
$Python = 'python'
$Script = Join-Path $RepoRoot 'modules\mcp_server\scripts\check_narrowing_points.py'
$RelTools = 'modules/mcp_server/tools'
$Root = Join-Path $env:TEMP 'task025-gate6'
$Logs = Join-Path $Root 'logs'
$Idx = Join-Path $Root 'index-contrast'

Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Logs, $Idx | Out-Null

$script:Checks = New-Object System.Collections.Generic.List[object]

function Note {
    param([string]$Text)
    Write-Host $Text
}

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Get-Sha {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '<missing>' }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}

function Write-LinesNoBom {
    param([string]$Path, [string[]]$Lines)
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes(($Lines -join "`n") + "`n"))
}

# `cmd /c` redirection keeps the bytes as python printed them (the guardrail's
# output is ASCII, and a PowerShell pipeline would re-encode it).
function Invoke-Gate6 {
    param([string]$Label, [string]$ScriptPath = $Script)
    $out = Join-Path $Logs ($Label + '.log')
    if (Test-Path $out) { Remove-Item -Force $out }
    & cmd /c "python `"$ScriptPath`" > `"$out`" 2>&1"
    $code = $LASTEXITCODE
    $text = Get-Content -Raw -Encoding UTF8 $out
    Note ("--- [{0}] python check_narrowing_points.py -> exit={1} log={2} sha256={3}" -f $Label, $code, $out, (Get-Sha $out))
    Note $text
    return [pscustomobject]@{ exit = $code; text = $text; log = $out }
}

# Insert `p_Insert` immediately before the first line containing `p_Anchor`.
function Insert-Before {
    param([string]$Path, [string]$Anchor, [string[]]$Insert)
    $lines = [IO.File]::ReadAllLines($Path)
    $index = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Contains($Anchor)) { $index = $i; break }
    }
    if ($index -lt 0) { throw ("anchor not found in {0}: {1}" -f $Path, $Anchor) }
    $before = @()
    if ($index -gt 0) { $before = $lines[0..($index - 1)] }
    $after = $lines[$index..($lines.Count - 1)]
    Write-LinesNoBom -Path $Path -Lines ($before + $Insert + $after)
}

function Rename-All {
    param([string]$Path, [string]$From, [string]$To)
    $text = [IO.File]::ReadAllText($Path)
    if (-not $text.Contains($From)) { throw ("text not found in {0}: {1}" -f $Path, $From) }
    $text = $text.Replace($From, $To)
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($text))
}

function Restore-File {
    param([string]$RelPath)
    & git -C $RepoRoot checkout -- $RelPath
    if ($LASTEXITCODE -ne 0) { throw ("git checkout -- {0} failed" -f $RelPath) }
    $full = Join-Path $RepoRoot ($RelPath -replace '/', '\')
    return (Get-Sha $full)
}

# -----------------------------------------------------------------------------
#  Run
# -----------------------------------------------------------------------------

Note '================================================================='
Note ' TASK-025 gate-6 evidence -- identity pin index + three experiments'
Note '================================================================='
Note ("repo        : {0}" -f $RepoRoot)
Note ("guardrail   : {0}" -f $Script)
Note ("guardrail sha256: {0}" -f (Get-Sha $Script))
$headSha = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
Note ("git HEAD    : {0}" -f $headSha)

$helpersRel = 'modules/mcp_server/tools/tool_helpers.cpp'
$scenarioRel = 'modules/mcp_server/tools/running_game_test_execution.cpp'
$helpersFull = Join-Path $RepoRoot ($helpersRel -replace '/', '\')
$scenarioFull = Join-Path $RepoRoot ($scenarioRel -replace '/', '\')
$helpersSha = Get-Sha $helpersFull
$scenarioSha = Get-Sha $scenarioFull
Note ("baseline sha256: tool_helpers.cpp={0}" -f $helpersSha)
Note ("baseline sha256: running_game_test_execution.cpp={0}" -f $scenarioSha)

$baseline = Invoke-Gate6 -Label 'E4a_baseline'
Check 'E4a_baseline_is_green' ($baseline.exit -eq 0) `
    ("python check_narrowing_points.py -> exit={0} (the tree as committed)" -f $baseline.exit)
Check 'E4a_baseline_scans_30_points' ((Get-Content -Raw (Join-Path $Logs 'E4a_baseline.log')) -match 'scanned\s+:\s+30 narrowing point') `
    ("the report counts 30 points / 30 pins (TASK-025 added the Rect2 component point)")

try {
    # =========================================================================
    #  E1 - drift: 20 comment lines above the `G24-THE-GATE` point
    # =========================================================================
    Note ''
    Note '--- E1: 20 comment lines above the pinned gate point (no re-pin) ---'
    $drift = @()
    for ($i = 1; $i -le 20; $i++) {
        $drift += ("// TASK-025 experiment E1 - unrelated line {0} of 20 (reverted after the run)" -f $i)
    }
    Insert-Before -Path $helpersFull -Anchor 'MCP-NARROWING: G24-THE-GATE' -Insert $drift
    $driftedSha = Get-Sha $helpersFull
    $e1 = Invoke-Gate6 -Label 'E1_drift'
    Check 'E1_drift_does_not_fail' ($e1.exit -eq 0) `
        ("exit={0}; the pin is by (file, marker id, occurrence), so moving the point is a refactor" -f $e1.exit)
    Check 'E1_drift_is_reported_as_a_note' ($e1.text -match 'note: \d+ pinned line number\(s\) drifted') `
        ("the report says the line number drifted and that this is not a failure")
    Check 'E1_drift_names_the_pinned_old_line' ($e1.text -match 'G24-THE-GATE\s+occurrence=\d+\s+pinned_line=986') `
        ("the drifted entry still resolves to the pin that documents line 986 - the very number TASK-024b had to hand-edit")
    Check 'E1_no_false_red' ($e1.text -notmatch 'FAIL:') `
        ("no FAIL line in the report (a line-keyed lookup answers UNLISTED here)")
    $helpersShaAfter1 = Restore-File -RelPath $helpersRel
    Check 'E1_reverted_byte_identical' ($helpersShaAfter1 -eq $helpersSha) `
        ("tool_helpers.cpp sha256 after revert = {0} (before the experiment: {1}; drifted: {2})" -f $helpersShaAfter1, $helpersSha, $driftedSha)

    # =========================================================================
    #  E2 - an unannotated narrowing point
    # =========================================================================
    Note ''
    Note '--- E2: a bare `(real_t)` cast (no marker, no pin) ---'
    Insert-Before -Path $scenarioFull -Anchor 'MCP-NARROWING: G24-GAME-SCENARIO-STRENGTH' -Insert @(
        '',
        '// TASK-025 experiment E2 - an unannotated narrowing point (reverted after the run)',
        'const real_t task025_experiment_unannotated = (real_t)1.0e300;'
    )
    $e2 = Invoke-Gate6 -Label 'E2_unannotated'
    Check 'E2_unannotated_is_red' ($e2.exit -eq 1) `
        ("exit={0} (the new `(real_t)` point carries no marker)" -f $e2.exit)
    Check 'E2_names_the_unannotated_point' (($e2.text -match 'carry no `// MCP-NARROWING:` marker') -and ($e2.text -match 'task025_experiment_unannotated')) `
        ("the report names the point and its text")
    $scenarioShaAfter2 = Restore-File -RelPath $scenarioRel
    Check 'E2_reverted_byte_identical' ($scenarioShaAfter2 -eq $scenarioSha) `
        ("running_game_test_execution.cpp sha256 after revert = {0}" -f $scenarioShaAfter2)

    # =========================================================================
    #  E3 - a stale pin (the marker id is renamed in the source)
    # =========================================================================
    Note ''
    Note '--- E3: the marker id renamed in the source, the pin left behind ---'
    Rename-All -Path $scenarioFull -From 'G24-GAME-SCENARIO-STRENGTH' -To 'G24-GAME-SCENARIO-RENAMED'
    $e3 = Invoke-Gate6 -Label 'E3_stale'
    Check 'E3_stale_is_red' ($e3.exit -eq 1) `
        ("exit={0}" -f $e3.exit)
    Check 'E3_names_the_stale_pin' ($e3.text -match 'have no matching narrowing point any more' -and $e3.text -match 'G24-GAME-SCENARIO-STRENGTH') `
        ("the report names the pinned marker with no point any more")
    Check 'E3_names_the_unknown_marker' ($e3.text -match 'marker=G24-GAME-SCENARIO-RENAMED') `
        ("and the renamed point, which has no pin")
    $scenarioShaAfter3 = Restore-File -RelPath $scenarioRel
    Check 'E3_reverted_byte_identical' ($scenarioShaAfter3 -eq $scenarioSha) `
        ("running_game_test_execution.cpp sha256 after revert = {0}" -f $scenarioShaAfter3)
} finally {
    # A crash must not leave the working tree dirty, whatever happened above.
    & git -C $RepoRoot checkout -- $helpersRel $scenarioRel | Out-Null
    $utf = Get-Sha $helpersFull
    $uts = Get-Sha $scenarioFull
    Note ("finally: reverted tool_helpers.cpp={0} running_game_test_execution.cpp={1}" -f $utf, $uts)
}

# =============================================================================
#  E4b - the tree restored: the guardrail is green again
# =============================================================================
Note ''
Note '--- E4b: after all experiments, the tree restored ---'
$final = Invoke-Gate6 -Label 'E4b_restored'
Check 'E4b_restored_is_green' ($final.exit -eq 0) ("exit={0}" -f $final.exit)
Check 'E4b_no_drift_notes' ($final.text -notmatch 'drifted') `
    ("no `moved` note: every pinned line number is the current one")
Check 'E4b_files_byte_identical' ((Get-Sha $helpersFull) -eq $helpersSha -and (Get-Sha $scenarioFull) -eq $scenarioSha) `
    ("tool_helpers.cpp={0}; running_game_test_execution.cpp={1}" -f (Get-Sha $helpersFull), (Get-Sha $scenarioFull))
Check 'E4b_worktree_clean_of_experiments' ((& git -C $RepoRoot status --porcelain -- $helpersRel $scenarioRel | Out-String).Trim() -eq '') `
    ("git status --porcelain for the two experiment files is empty")

# =============================================================================
#  E0 - the pre-TASK-025 lookup on a pristine HEAD copy (no repository mutation)
#
#  A `PINNED` list describes the source it was written against, so the contrast
#  is run the only fair way: each script against the tree its own list describes.
#  The pre-TASK-025 script runs here, in %TEMP%, on a `git archive` copy of
#  HEAD's `tools/**`; its drift result is then compared with the TASK-025
#  script's result for the *identical* drift (E1, on the real tree).
# =============================================================================
Note ''
Note '--- E0: the pre-TASK-025 line-keyed lookup on a pristine copy of its own tree ---'
Note ("    pre-TASK-025 commit: {0}" -f $PreTask025Commit)
$base = Join-Path $Idx 'head'
New-Item -ItemType Directory -Force -Path (Join-Path $base 'modules\mcp_server\scripts') | Out-Null
$zip = Join-Path $Idx 'head-tools.zip'
& git -C $RepoRoot archive --format=zip "--output=$zip" $PreTask025Commit $RelTools
if ($LASTEXITCODE -ne 0) { throw ("git archive of {0} failed" -f $PreTask025Commit) }
Expand-Archive -Path $zip -DestinationPath $base -Force
$oldScript = Join-Path $Idx 'head\modules\mcp_server\scripts\check_narrowing_points.py'
$showCommand = 'git -C "{0}" show {1}:modules/mcp_server/scripts/check_narrowing_points.py > "{2}"' -f $RepoRoot, $PreTask025Commit, $oldScript
& cmd /c $showCommand
if ($LASTEXITCODE -ne 0) { throw ("git show of the pre-TASK-025 script ({0}) failed" -f $PreTask025Commit) }
$oldText = [IO.File]::ReadAllText($oldScript)
$newText = [IO.File]::ReadAllText($Script)
# The discriminating line of the old lookup. If this is absent the "old" script
# is not the old script (which is exactly the mistake of reading it out of a
# commit that already contains the new one).
Check 'E0_pre_task025_script_is_really_the_old_one' `
    ($oldText.Contains('.get(point["line"])') -and (-not $newText.Contains('.get(point["line"])'))) `
    ("the copy from {0} looks its pin up by line (`.get(point[`"line`"])`); the TASK-025 script does not" -f $PreTask025Commit)
Note ("pre-TASK-025 guardrail sha256: {0}" -f (Get-Sha $oldScript))
Note ("TASK-025 guardrail sha256    : {0}" -f (Get-Sha $Script))

$oldBase = Invoke-Gate6 -Label 'E0a_old_baseline' -ScriptPath $oldScript
Check 'E0a_pre_task025_baseline_is_green' ($oldBase.exit -eq 0) `
    ("the pre-TASK-025 script on HEAD's own tools tree: exit={0} (so the drift below is the only difference)" -f $oldBase.exit)

$oldCopy = Join-Path $Idx 'head\modules\mcp_server\tools\tool_helpers.cpp'
Insert-Before -Path $oldCopy -Anchor 'MCP-NARROWING: G24-THE-GATE' -Insert $drift
$oldDrift = Invoke-Gate6 -Label 'E0b_old_drift' -ScriptPath $oldScript
Check 'E0b_pre_task025_index_false_reds_on_drift' `
    ($oldDrift.exit -eq 1 -and $oldDrift.text -match "are not pinned in this script's PINNED list" -and $oldDrift.text -match 'tool_helpers.cpp:1006') `
    ("pre-TASK-025 script, the identical 20-line drift: exit={0}; the point is reported at its new line 1006 as having no pin although nothing about it changed but its line number" -f $oldDrift.exit)
Check 'E0c_same_drift_only_notes_it_under_the_new_index' ($oldDrift.exit -eq 1 -and $e1.exit -eq 0 -and $e1.text -match 'drifted') `
    ("identical drift: pre-TASK-025 exit={0} (false red), TASK-025 exit={1} with a `moved` note (see E1/E4b for the real-tree run)" -f $oldDrift.exit, $e1.exit)

# =============================================================================
$logPath = Join-Path $Root 'gate6-experiments.log.txt'
$summary = @()
foreach ($entry in $script:Checks) {
    $tag = 'FAIL'
    if ($entry.pass) { $tag = 'PASS' }
    $summary += ("[{0}] {1} :: {2}" -f $tag, $entry.id, $entry.evidence)
}
[IO.File]::WriteAllBytes($logPath, (New-Object Text.UTF8Encoding($false)).GetBytes(($summary -join "`r`n") + "`r`n"))

$passed = @($script:Checks | Where-Object { $_.pass }).Count
$total = $script:Checks.Count
Write-Host ''
Write-Host '========================== SUMMARY =========================='
foreach ($c in $script:Checks) {
    $tag = 'FAIL'
    if ($c.pass) { $tag = 'PASS' }
    Write-Host ("{0}  {1}" -f $tag, $c.id)
}
Write-Host ("{0}/{1} checks passed; logs in {2} (log sha256={3})" -f $passed, $total, $Logs, (Get-Sha $logPath))
if ($passed -ne $total) { exit 1 }
exit 0