# =============================================================================
#  mcp076_gate2_union_count_reverse_probe.ps1 -- TASK-076 section A.2.
#
#  The stale expectation this task repaired is the same class TASK-064 and
#  TASK-068 repaired: a gate that pinned a *revision* instead of reading the
#  artifact. `scripts/mcp071_gate2_live_evidence.ps1` G208 compared the live
#  union of the two endpoints against the *literal* 176, and the sixth
#  `Write-Host` line repeated the same number. TASK-075 moved the contract to
#  177, so both lines were stale - and a bare literal there is exactly what
#  `scripts/check_hardcoded_counts.py` reported as UNCLASSIFIED (it cannot tell
#  whether a number decides anything, so it refuses to classify it silently).
#
#  They were not deleted and not relaxed: each one is replaced by a DERIVED
#  expression (the union is compared against `$contractNames.Count`, the count
#  read out of the contract file the assertion is about). This file is the
#  machine evidence for the claims a reader would otherwise take on trust:
#
#    1. the OLD literal is FALSE on today's contract -> a loop that reached it
#       would exit non-zero; the staleness is measured, not asserted by hand;
#    2. the NEW derived expression is TRUE on the same input -> the fix is not a
#       deletion;
#    3. the NEW expression is FALSE on a mutated input (one extra name added to
#       the union) -> it is not a tautology, the same non-vacuity probe TASK-068
#       used for its derived contract size;
#    4. the repaired script really carries the derived spelling, evaluated on the
#       real file rather than on a paraphrase;
#    5. the SURVEY still flags a bare literal and accepts the derived spelling,
#       run against two throwaway roots built here - so the survey's exit 0 on
#       the real tree is not "the checker went blind", it is "the number is
#       derived now".
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp076_gate2_union_count_reverse_probe.ps1
#  Exit 0 when every old expression is false, every new one is true, the mutated
#  control is false, and the survey probes behave; exit 1 otherwise.
#
#  Pure ASCII on purpose (Windows PowerShell 5.1 may read a .ps1 with the ANSI
#  code page when there is no BOM).
# =============================================================================

param([string]$OutRoot = '')

$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$ModuleRoot = Join-Path $RepoRoot 'modules\mcp_server'
$Scripts = Join-Path $ModuleRoot 'scripts'
$ContractPath = Join-Path $ModuleRoot 'docs\tools_list.renamed.json'
$Gate2Path = Join-Path $Scripts 'mcp071_gate2_live_evidence.ps1'
$SurveyPath = Join-Path $Scripts 'check_hardcoded_counts.py'
if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp076\union-count-probe' }
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$script:Failures = 0
$script:Rows = New-Object System.Collections.Generic.List[object]

function Read-JsonNoBom {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (ConvertFrom-Json ([IO.File]::ReadAllText($Path, $utf8)))
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

# The inputs, read exactly the way mcp071 reads them. mcp071 asserts that the
# union of the two endpoints' live lists IS the contract's entry set, so the
# contract file stands in for the live union here; the two are kept as separate
# variables so the size comparison is a real comparison, never `x -eq x`.
$contract = Read-JsonNoBom -Path $ContractPath
$contractNames = @{}
foreach ($tool in $contract.result.tools) { $contractNames[[string]$tool.name] = $true }
$contractCount = $contractNames.Count

$unionNames = @{}
foreach ($name in $contractNames.Keys) { $unionNames[$name] = $true }
$unionCount = $unionNames.Count

# The mutation that isolates the size term: the same construction plus one name
# the contract does not carry (the drift the derivation must catch).
$mutatedNames = @{}
foreach ($name in $unionNames.Keys) { $mutatedNames[$name] = $true }
$mutatedNames['mcp076_not_a_real_tool'] = $true
$mutatedCount = $mutatedNames.Count

# The repaired G208 line, read out of the real file (same-input discipline).
$gateText = [IO.File]::ReadAllText($Gate2Path, $utf8)
$carriesDerived = $gateText.Contains('$union.Count -eq $contractNames.Count')
$noLiteralComparison = -not $gateText.Contains('-eq 176')
$passLineDerived = $gateText.Contains('-f $contractNames.Count)')

# The survey probes: a throwaway root with a bare literal must be flagged
# (exit 1), the same line with the derived spelling must pass (exit 0). The
# literal line is deliberately NOT of the `Check ...` shape, because the survey
# classifies a `Check` line as LIVE (a line that names a check is a check
# printer); the two mcp071 lines the survey refused to classify were exactly
# this shape - a bare continuation line and a Write-Host line.
#
# The root has to live on the same drive as the module: `--root` calls
# `os.path.relpath(self_path, root)` to print its own SKIPPED line, and that
# raises on a cross-drive pair (measured: a %TEMP% root makes the survey exit 1
# with a traceback for EVERY input, which would make this probe unfalsifiable).
$probeRoot = Join-Path ([IO.Path]::GetPathRoot($RepoRoot)) '_mcp076_survey_probe'
$surveyOk = $true
Write-Host '============================================================='
Write-Host ' TASK-076: mcp071 G208 union-count reverse probe'
Write-Host '============================================================='
Write-Host ("contract      : entries={0} _meta.count={1}" -f $contractCount, $contract._meta.count)
Write-Host ("union stand-in: {0} name(s) (the contract set G208 asserts against)" -f $unionCount)
Write-Host ("mutated union : {0} name(s) (one extra key, not in the contract)" -f $mutatedCount)
Write-Host ''
Write-Host '--- survey probes (throwaway roots) ---'
foreach ($case in @(
        @{ name = 'stale'; line = '($u.Count -eq 176)'; expected = 1 },
        @{ name = 'derived'; line = '($u.Count -eq $contractNames.Count)'; expected = 0 }
    )) {
    $root = Join-Path $probeRoot ('survey-' + $case.name)
    $dir = Join-Path $root 'scripts'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'probe_survey.ps1'), ($case.line + "`n"), $utf8)
    & python $SurveyPath --root $root | Out-Null
    $code = $LASTEXITCODE
    if ($code -ne $case.expected) { $surveyOk = $false }
    Write-Host ("[survey:{0}] exit={1} (expected {2}) line={3}" -f $case.name, $code, $case.expected, $case.line)
}
Remove-Item -Recurse -Force $probeRoot -ErrorAction SilentlyContinue
& python $SurveyPath | Out-Null
$realCode = $LASTEXITCODE
Write-Host ''
Write-Host '--- probes ---'

# --- the stale expectation (what G208 carried before TASK-076) ---------------
Record-Probe -Id 'old_G208_union_count_is_176' `
    -Source 'scripts/mcp071_gate2_live_evidence.ps1 G208 (before TASK-076)' `
    -Expression '$unionCount -eq 176' `
    -Expected $false `
    -Why 'TASK-075 moved the contract from 176 to 177 (one added tool, project_read_text_file), so the literal comparison is FALSE and that gate went red for a reason that is not a defect'

# --- the new expectations (what G208 carries after TASK-076) -----------------
Record-Probe -Id 'new_G208_union_count_is_derived' `
    -Source 'scripts/mcp071_gate2_live_evidence.ps1 G208 (after TASK-076)' `
    -Expression '($unionCount -eq $contractCount)' `
    -Expected $true `
    -Why 'the size is read out of the contract file the assertion is about ($contractNames.Count), so the comparison cannot go stale when the contract grows'

Record-Probe -Id 'new_G208_size_term_separates_the_mutated_union' `
    -Source 'the G208 size term fed a union with one extra name' `
    -Expression '($mutatedCount -eq $contractCount)' `
    -Expected $false `
    -Why 'the derived size still separates a union that carries one name the contract does not have, so the comparison is not a tautology'

Record-Probe -Id 'new_G208_still_has_the_missing_and_extra_half' `
    -Source 'scripts/mcp071_gate2_live_evidence.ps1 G208 (after TASK-076)' `
    -Expression '((@($contractNames.Keys | Where-Object { -not $mutatedNames.ContainsKey($_) }).Count -eq 0) -and (@($mutatedNames.Keys | Where-Object { -not $contractNames.ContainsKey($_) }).Count -eq 1))' `
    -Expected $true `
    -Why 'the mutated union is missing nothing and has exactly one name the contract does not carry, which is the shape the second and third conjunct of G208 report'

Record-Probe -Id 'script_carries_the_derived_comparison' `
    -Source 'scripts/mcp071_gate2_live_evidence.ps1 (after TASK-076)' `
    -Expression '($carriesDerived)' `
    -Expected $true `
    -Why 'the fixed line is read out of the real file, not a paraphrase of it'
Record-Probe -Id 'script_no_longer_compares_against_the_literal' `
    -Source 'scripts/mcp071_gate2_live_evidence.ps1 (after TASK-076)' `
    -Expression '($noLiteralComparison)' `
    -Expected $true `
    -Why 'the bare literal comparison is gone; the number survives only in the provenance comment explaining the repair'
Record-Probe -Id 'script_passing_line_is_derived_too' `
    -Source 'scripts/mcp071_gate2_live_evidence.ps1 (after TASK-076)' `
    -Expression '($passLineDerived)' `
    -Expected $true `
    -Why 'the PASS summary line interpolates the same derived count instead of repeating the number'

Record-Probe -Id 'survey_flags_the_bare_literal_and_accepts_the_derived_spelling' `
    -Source 'scripts/check_hardcoded_counts.py --root <throwaway roots>' `
    -Expression '($surveyOk)' `
    -Expected $true `
    -Why 'the survey exits 1 on a bare literal and 0 on the derived spelling, so its exit 0 on the real tree means the number is derived - not that the checker stopped looking'
Record-Probe -Id 'survey_exits_0_on_the_real_tree' `
    -Source 'scripts/check_hardcoded_counts.py' `
    -Expression '($realCode -eq 0)' `
    -Expected $true `
    -Why 'every occurrence of the surveyed numbers is classified; zero UNCLASSIFIED'

Write-Host ''
Write-Host ("probes={0} failures={1}" -f $script:Rows.Count, $script:Failures)
if ($script:Failures -gt 0) {
    Write-Host 'TASK-076 UNION-COUNT REVERSE PROBE FAILED'
    exit 1
}
Write-Host 'TASK-076 UNION-COUNT REVERSE PROBE PASS (the old literal is false on today contract; the derived size is true and false on a mutated union; the script carries the derivation; the survey still flags a bare literal)'
exit 0
