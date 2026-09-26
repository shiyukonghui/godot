# =============================================================================
#  mcp068_rename_map_reverse_probe.ps1 -- TASK-068 (1): the reverse probe for
#  docs/scripts/check_rename_map.py's contract-size expectation.
#
#  Why this exists: G1/G5 of that script used to compare `len(ctools)` against
#  the *literal* 171 (and, in G5, against the equivalent `174 - 2 - 1`). The
#  contract has been 171 + `_meta.added_count` since TASK-052/053/063, so those
#  two lines exited 1 on a tree where nothing the script audits was wrong
#  (REPORT-067 section 4.3). TASK-068 replaces the comparison with the derived
#  `(map total) - 2 unregister - 1 merge + added_count` and keeps 171 as a
#  *checked literal* on the ported half.
#
#  What it proves, all on the real frozen input files and with the expressions
#  spelled exactly as the two versions of the script spell them:
#    * the OLD size expectation is FALSE on today's contract -> a gate loop that
#      reached it would exit non-zero (this is the stale expectation, measured,
#      not asserted by hand);
#    * the NEW derived expectation is TRUE -> exit 0;
#    * the literal `171` half is TRUE (so nothing was relaxed into "any size");
#    * and the new expression is NOT vacuous: fed the same expression with the
#      contract's own input mutated (one added tool removed from the meta list),
#      it is FALSE.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp068_rename_map_reverse_probe.ps1
#  Exit 0 when every old expression is false, every new one is true and the
#  mutated-input control is false; exit 1 otherwise.
#
#  Pure ASCII on purpose (Windows PowerShell 5.1 may read a .ps1 with the ANSI
#  code page when there is no BOM).
# =============================================================================

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$MapPath = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-rename-map.json'
$ContractPath = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'
$AddedManifest = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups-added.json'

$script:Failures = 0
$script:Rows = New-Object System.Collections.Generic.List[object]

function Read-JsonNoBom {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (ConvertFrom-Json ([IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding($false)))))
}

function Record-Probe {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Expression,
        [Parameter(Mandatory = $true)][bool]$Expected,
        [Parameter(Mandatory = $true)][string]$Why
    )
    $value = [bool](Invoke-Expression $Expression)
    $ok = ($value -eq $Expected)
    if (-not $ok) { $script:Failures = $script:Failures + 1 }
    $script:Rows.Add([pscustomobject]@{ Id = $Id; Value = $value; Expected = $Expected; Ok = $ok })
    Write-Host ("[{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $Id)
    Write-Host ("       source     : {0}" -f $Source)
    Write-Host ("       expression : {0}" -f $Expression)
    Write-Host ("       value      : {0} (expected {1})" -f $value, $Expected)
    Write-Host ("       why        : {0}" -f $Why)
}

# --- the inputs, read exactly the way the script reads them -------------------
$mapDoc = Read-JsonNoBom -Path $MapPath
$contract = Read-JsonNoBom -Path $ContractPath
$addedDoc = Read-JsonNoBom -Path $AddedManifest

$ctools = @($contract.result.tools)
$ctoolCount = $ctools.Count
$mapTools = @($mapDoc.tools)
$mapTotal = [int]$mapDoc.total

# The same disposition split the script computes (E-section + C-section).
$unregisterCount = @($mapTools | Where-Object { $_.disposition -eq 'unregister_until_implemented' }).Count
$mergeCount = @($mapTools | Where-Object { $_.disposition -eq 'merge_into' }).Count
# 174 entries - 2 unregister_until_implemented - 1 merge_into == 171 kept names;
# counted rather than restated, which is the TASK-068 change itself.
$portedCount = @($mapTools | Where-Object { ($_.disposition -ne 'unregister_until_implemented') -and ($_.disposition -ne 'merge_into') }).Count

$addedTools = @($contract._meta.added_tools)
$addedCount = [int]$contract._meta.added_count
$addedManifestNames = @()
foreach ($group in @($addedDoc.groups)) {
    foreach ($tool in @($group.tools)) { $addedManifestNames += [string]$tool }
}

# The same expression the fixed script evaluates, spelled as a boolean.
$newExpression = '($ctoolCount -eq (($mapTotal - $unregisterCount - $mergeCount) + $addedCount))'

Write-Host '============================================================='
Write-Host ' TASK-068: check_rename_map.py contract-size reverse probe'
Write-Host '============================================================='
Write-Host ("map           : total={0} entries={1} unregister={2} merge={3} -> ported={4}" -f $mapTotal, $mapTools.Count, $unregisterCount, $mergeCount, $portedCount)
Write-Host ("contract      : entries={0} _meta.count={1} added_count={2} added_tools={3}" -f $ctoolCount, $contract._meta.count, $addedCount, $addedTools.Count)
Write-Host ("added manifest: {0} name(s) [{1}]" -f $addedManifestNames.Count, ($addedManifestNames -join ', '))
Write-Host ''

# --- the stale expectations (what the script carried before TASK-068) --------
Record-Probe -Id 'old_G1_contract_count_is_171' `
    -Source 'docs/scripts/check_rename_map.py:240 (before TASK-068)' `
    -Expression '($ctoolCount -eq 171)' `
    -Expected $false `
    -Why 'the contract has been 171 + _meta.added_count since TASK-052/053/063; today it is 176, so the literal comparison is FALSE and that script exited 1 with 2 failing checks (REPORT-067 section 4.3)'
Record-Probe -Id 'old_G5_contract_count_is_map_total_minus_2_minus_1' `
    -Source 'docs/scripts/check_rename_map.py:250 (before TASK-068)' `
    -Expression '($ctoolCount -eq (174 - 2 - 1))' `
    -Expected $false `
    -Why 'the same stale expectation written as arithmetic: 174 - 2 - 1 is the ported half only, so it cannot equal a contract that also carries the added tools'

# --- the new expectations (what the script carries after TASK-068) -----------
Record-Probe -Id 'new_ported_half_is_still_171' `
    -Source 'docs/scripts/check_rename_map.py G1 (after TASK-068)' `
    -Expression '($portedCount -eq 171)' `
    -Expected $true `
    -Why 'the literal 171 is kept, as a checked literal, on the ported half (map total - 2 unregister - 1 merge), not compared against the whole contract'
Record-Probe -Id 'new_contract_count_is_derived' `
    -Source 'docs/scripts/check_rename_map.py G6 (after TASK-068)' `
    -Expression $newExpression `
    -Expected $true `
    -Why 'the derived size (map total - 2 unregister - 1 merge + _meta.added_count) is TRUE on the current contract, so the fixed script exits 0'
Record-Probe -Id 'new_added_count_matches_the_contract_list' `
    -Source 'docs/scripts/check_rename_map.py (after TASK-068, FATAL guard)' `
    -Expression '(($addedCount -eq $addedTools.Count) -and ($addedCount -gt 0))' `
    -Expected $true `
    -Why 'the derivation only means something if added_count is its own list length and non-zero; the script makes a mismatch a FATAL before any G check runs'

# --- not vacuous: the same new expression on a mutated contract --------------
# The mutation is the smallest one that changes the contract's size: drop one
# name from _meta.added_tools (and its count with it), exactly the drift the
# derivation is supposed to catch.
$mutatedAddedCount = $addedCount - 1
Record-Probe -Id 'new_contract_count_is_not_vacuous' `
    -Source 'the G6 expression fed _meta.added_count - 1 (same literal, same input file, one name removed)' `
    -Expression '($ctoolCount -eq (($mapTotal - $unregisterCount - $mergeCount) + $mutatedAddedCount))' `
    -Expected $false `
    -Why 'with one added tool no longer declared, the derived size no longer matches the real 176, so the expression is not a tautology'

# --- the three-way agreement the sixth manifest exists for -------------------
Record-Probe -Id 'new_sixth_manifest_is_the_contract_added_list' `
    -Source 'docs/tool-groups-added.json vs contract _meta.added_tools (TASK-052 GDR-28 point 3)' `
    -Expression '($addedManifestNames.Count -eq $addedTools.Count)' `
    -Expected $true `
    -Why 'the manifest that declares the added tools and the contract that carries them agree on the size; check_tool_groups.py --added proves the name-for-name half'

Write-Host ''
Write-Host ("probes={0} failures={1}" -f $script:Rows.Count, $script:Failures)
if ($script:Failures -gt 0) {
    Write-Host 'TASK-068 REVERSE PROBE FAILED'
    exit 1
}
Write-Host 'TASK-068 REVERSE PROBE PASS (both stale literals are false and the derived expression is true on the same input; the literal 171 half is still checked; the derivation is not vacuous)'
exit 0