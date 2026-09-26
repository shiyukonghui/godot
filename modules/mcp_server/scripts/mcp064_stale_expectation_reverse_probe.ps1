# =============================================================================
#  mcp064_stale_expectation_reverse_probe.ps1 -- TASK-064 (1) exit-code before
#  and after, for the four evidence scripts that pinned a contract size.
#
#  Why this exists: the four scripts named by REPORT-063 section 6.2 -
#  mcp052_added_tools_evidence.ps1, mcp053_added_tools_evidence.ps1,
#  mcp054_forensics_and_csharp_evidence.ps1 and mcp059_contract_pre_post.py -
#  each start a plain *and* a mono engine and assert `engines_match_head`, and
#  the mono binary in this worktree is anchored at cd7224274 while HEAD is
#  c589eae24. A full end-to-end rerun is therefore red for a reason that has
#  nothing to do with this task (REPORT-063 section 6.2 measured the same wall).
#  Everything this task changed is decided from three tracked JSON files and
#  happens *before* any engine starts, so the exit codes can be measured exactly
#  by evaluating the same expressions on the same inputs in one process.
#
#  What it proves, per literal:
#    * the OLD expression (verbatim from the script before this task) is FALSE
#      on today's contract => a gate loop that reached it would exit non-zero;
#    * the NEW expression (verbatim from the script after this task) is TRUE
#      => exit 0.
#  Both are evaluated with Invoke-Expression on the real files. Nothing is
#  relaxed: the new expressions are the ones the scripts now carry.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp064_stale_expectation_reverse_probe.ps1
#  Exit 0 when every old expression is false, every new one is true and the
#  manifest cross-check agrees; exit 1 otherwise.
#
#  Pure ASCII on purpose (Windows PowerShell 5.1 may read a .ps1 with the ANSI
#  code page when there is no BOM).
# =============================================================================

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$ContractPath = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'
$MapPath = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-rename-map.json'
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

# --- the three tracked inputs, read exactly as the four scripts read them ----
$contract = Read-JsonNoBom -Path $ContractPath
$contractNames = @($contract.result.tools | ForEach-Object { [string]$_.name })
$addedNames = @($contract._meta.added_tools | ForEach-Object { [string]$_ })

$mapDoc = Read-JsonNoBom -Path $MapPath
$scopeOf = @{}
foreach ($entry in @($mapDoc.tools)) { $scopeOf[[string]$entry.new_name] = [string]$entry.scope }
$addedDoc = Read-JsonNoBom -Path $AddedManifest
$addedManifestNames = @()
foreach ($group in @($addedDoc.groups)) {
    foreach ($tool in @($group.tools)) { $addedManifestNames += [string]$tool; $scopeOf[[string]$tool] = [string]$group.scope }
}
$editorExpectedCount = @($contractNames | Where-Object { $scopeOf[$_] -ne 'game' }).Count
$gameExpectedCount = @($contractNames | Where-Object { $scopeOf[$_] -ne 'editor' }).Count
$portedCount = 171

Write-Host '============================================================='
Write-Host ' TASK-064: stale-expectation reverse probe (old vs new)'
Write-Host '============================================================='
Write-Host ("contract       : {0} entries, _meta.count={1}, added_count={2}" -f $contractNames.Count, $contract._meta.count, $contract._meta.added_count)
Write-Host ("added manifest : {0} name(s) [{1}]" -f $addedManifestNames.Count, ($addedManifestNames -join ', '))
Write-Host ("derived views  : editor={0} game={1} (171 ported + {2} added)" -f $editorExpectedCount, $gameExpectedCount, $addedNames.Count)
Write-Host ''

# --- mcp052_added_tools_evidence.ps1 -----------------------------------------
Record-Probe -Id 'mcp052_old_endpoint_expectations' `
    -Source 'mcp052_added_tools_evidence.ps1:315 (before TASK-064)' `
    -Expression '(($editorExpectedCount -eq 152) -and ($gameExpectedCount -eq 72))' `
    -Expected $false `
    -Why 'REPORT-063 section 6.2: editor view 152 -> 153 after TASK-063 appended one editor-scope tool; the literal pair is stale'
Record-Probe -Id 'mcp052_new_endpoint_expectations' `
    -Source 'mcp052_added_tools_evidence.ps1 (after TASK-064)' `
    -Expression '(($contractNames.Count -eq ($portedCount + $addedNames.Count)) -and ($addedNames.Count -eq [int]$contract._meta.added_count))' `
    -Expected $true `
    -Why 'the contract is 171 ported + added_count and both halves are read from the contract itself; the live counts are separately asserted against the two derived views'

# --- mcp053_added_tools_evidence.ps1 -----------------------------------------
Record-Probe -Id 'mcp053_old_contract_is_175' `
    -Source 'mcp053_added_tools_evidence.ps1:325 (before TASK-064)' `
    -Expression '($contractNames.Count -eq 175)' `
    -Expected $false `
    -Why 'the contract has been 176 since TASK-063 appended editor_set_node_property_updates'
Record-Probe -Id 'mcp053_old_added_tools_is_the_four_some' `
    -Source 'mcp053_added_tools_evidence.ps1:327 (before TASK-064)' `
    -Expression '(($addedNames.Count -eq 4) -and ($addedNames[2] -ceq ''project_validate_scripts'') -and ($addedNames[3] -ceq ''editor_set_node_script_batch''))' `
    -Expected $false `
    -Why 'the added list grew to five names in append order, so the pinned length 4 is stale while positions 2 and 3 still hold'
Record-Probe -Id 'mcp053_old_endpoint_expectations' `
    -Source 'mcp053_added_tools_evidence.ps1:362 (before TASK-064)' `
    -Expression '(($editorExpectedCount -eq 152) -and ($gameExpectedCount -eq 72))' `
    -Expected $false `
    -Why 'same stale pair as mcp052: the editor view is 153'
Record-Probe -Id 'mcp053_new_contract_is_ported_plus_added' `
    -Source 'mcp053_added_tools_evidence.ps1 (after TASK-064)' `
    -Expression '(($contractNames.Count -eq ($portedCount + $addedNames.Count)) -and ($addedNames.Count -eq [int]$contract._meta.added_count) -and ([int]$contract._meta.count -eq $contractNames.Count))' `
    -Expected $true `
    -Why 'the source of the expectation is now the contract formula 171 + added_count, cross-checked against _meta.count'
Record-Probe -Id 'mcp053_new_added_tools_is_the_manifest' `
    -Source 'mcp053_added_tools_evidence.ps1 (after TASK-064)' `
    -Expression '(($addedNames.Count -eq [int]$contract._meta.added_count) -and (($addedNames -join ",") -ceq ($addedManifestNames -join ",")) -and ($addedNames[2] -ceq ''project_validate_scripts'') -and ($addedNames[3] -ceq ''editor_set_node_script_batch''))' `
    -Expected $true `
    -Why 'read sixth manifest + contract: docs/tool-groups-added.json is the declared inventory and _meta.added_tools must equal it in order'
Record-Probe -Id 'mcp053_new_endpoint_expectations' `
    -Source 'mcp053_added_tools_evidence.ps1 (after TASK-064)' `
    -Expression '(($contractNames.Count -eq ($portedCount + $addedNames.Count)) -and ($addedNames.Count -eq [int]$contract._meta.added_count))' `
    -Expected $true `
    -Why 'same derivation as mcp052; the live 9888/9889 counts are asserted against editor/gameExpectedCount elsewhere in the script'

# --- mcp054_forensics_and_csharp_evidence.ps1 --------------------------------
Record-Probe -Id 'mcp054_old_contract_is_175' `
    -Source 'mcp054_forensics_and_csharp_evidence.ps1:288 (before TASK-064)' `
    -Expression '($contractNames.Count -eq 175)' `
    -Expected $false `
    -Why 'same stale literal'
Record-Probe -Id 'mcp054_old_added_count_is_4' `
    -Source 'mcp054_forensics_and_csharp_evidence.ps1:307 (before TASK-064)' `
    -Expression '($contract._meta.added_count -eq 4)' `
    -Expected $false `
    -Why 'added_count is 5 since TASK-063'
Record-Probe -Id 'mcp054_new_contract_is_ported_plus_added' `
    -Source 'mcp054_forensics_and_csharp_evidence.ps1 (after TASK-064)' `
    -Expression '(($contractNames.Count -eq ($portedCount + @($contract._meta.added_tools).Count)) -and ([int]$contract._meta.count -eq $contractNames.Count))' `
    -Expected $true `
    -Why 'the expectation is the contract formula, not a frozen number'
Record-Probe -Id 'mcp054_new_added_tools_is_the_manifest' `
    -Source 'mcp054_forensics_and_csharp_evidence.ps1 (after TASK-064)' `
    -Expression '(((@($contract._meta.added_tools) -join ",") -ceq ($addedManifestNames -join ",")) -and ([int]$contract._meta.added_count -eq $addedManifestNames.Count))' `
    -Expected $true `
    -Why 'the manifest is read and the contract must match it name for name in order'

# --- the invariant the three scripts now share -------------------------------
Record-Probe -Id 'shared_contract_formula_holds' `
    -Source 'accept_m1.ps1:207 + check_tool_groups.py --completeness' `
    -Expression '(($contractNames.Count -eq ($portedCount + $addedNames.Count)) -and ($addedManifestNames.Count -eq $addedNames.Count) -and (($addedManifestNames -join ",") -ceq ($addedNames -join ",")))' `
    -Expected $true `
    -Why 'three-way agreement: contract size = 171 + added_count, and the sixth manifest names exactly the contract added list'

Write-Host ''
Write-Host ("probes={0} failures={1}" -f $script:Rows.Count, $script:Failures)
if ($script:Failures -gt 0) {
    Write-Host 'TASK-064 REVERSE PROBE FAILED'
    exit 1
}
Write-Host 'TASK-064 REVERSE PROBE PASS (every stale literal is false on the current contract; every derived expression is true)'
exit 0