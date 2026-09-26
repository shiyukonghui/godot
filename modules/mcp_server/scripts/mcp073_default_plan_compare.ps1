# =============================================================================
#  mcp073_default_plan_compare.ps1 -- TASK-073 A, evidence item 1: the DEFAULT
#  gate plan of `mcp059_gates.ps1` is unchanged, machine-checked.
#
#  The claim TASK-073 A has to make is "without the switch, gate 3 and the whole
#  battery are exactly what they were". Reading the diff is not a check, so this
#  script derives the default plan from the SOURCE of two revisions and compares
#  them:
#
#    * the plan is the ordered list of `Invoke-Step '<name>'` calls in
#      `scripts/mcp059_gates.ps1`, minus every line tagged
#      `MCP073-ONLY-IN-DOUBLE-MODE` (the one conditional step TASK-073 A adds);
#    * the baseline plan comes from `<BaselineRevision>:<path>` (`git show`), so
#      the baseline is the file as committed at that revision, not a copy;
#    * the two lists must be EQUAL, element for element, in order;
#    * and as the positive half of the check, the DOUBLE-MODE plan (the same
#      extraction WITHOUT dropping the tagged line) must be the default plan plus
#      exactly one extra step, named `gate3_double_variant`, whose line is the
#      only place in the file that names `mcp073_gate3_double.ps1`.
#
#  So "default unchanged" and "the switch adds exactly one step" are both
#  assertions about the file, re-runnable at any later revision, instead of two
#  sentences in a report.
#
#  USAGE
#  -----
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp073_default_plan_compare.ps1 `
#        -BaselineRevision 8ffb92b4b -EvidenceDir <absolute dir>
#
#  `-CurrentFile <path>` is a test seam for the insertion probe only
#  (`mcp073_plan_compare_probe.ps1`); the default is the working-tree copy of
#  `-GateScript`.
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$RepoRoot = '',
    [string]$BaselineRevision = '',
    [string]$GateScript = 'modules/mcp_server/scripts/mcp059_gates.ps1',
    # `-CurrentFile` is a TEST SEAM: it lets the insertion probe
    # (`mcp073_plan_compare_probe.ps1`) hand this script a modified COPY as the
    # "current" side, so the check can be forced to go red without touching the
    # real driver. Default: the working-tree copy of `-GateScript`.
    [string]$CurrentFile = '',
    [string]$EvidenceDir = ''
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
} else {
    $RepoRoot = (Resolve-Path $RepoRoot).Path
}
if ([string]::IsNullOrWhiteSpace($BaselineRevision)) {
    Write-Host 'mcp073_default_plan_compare: -BaselineRevision is required (the revision BEFORE the TASK-073 change).'
    exit 3
}
if ([string]::IsNullOrWhiteSpace($EvidenceDir)) {
    $EvidenceDir = Join-Path $env:TEMP ('mcp073\plan-compare\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$EvidenceDir = (Resolve-Path $EvidenceDir).Path

$TaggedMarker = 'MCP073-ONLY-IN-DOUBLE-MODE'
$VariantScriptName = 'mcp073_gate3_double.ps1'

$script:Failures = 0
$script:Rows = New-Object System.Collections.Generic.List[string]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    if (-not $Pass) { $script:Failures++ }
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
    $script:Rows.Add(("[{0}] {1} :: {2}" -f $tag, $Id, $Evidence))
}

function Get-GitText {
    param([string[]]$GitArgs)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = @(& git -C $RepoRoot @GitArgs 2>$null)
        $code = [int]$LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    return [pscustomobject]@{ code = $code; text = ($out -join "`n") }
}

# The ordered `Invoke-Step '<name>'` calls of one source text, with the trimmed
# source line of each one. A line carrying the TASK-073 tag is a step that only
# the double variant runs.
function Get-StepPlan {
    param([string]$Text)
    $all = New-Object System.Collections.Generic.List[string]
    $allLines = New-Object System.Collections.Generic.List[string]
    $conditional = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($Text -split "`n")) {
        $m = [regex]::Match($line, "Invoke-Step\s+'([^']+)'")
        if (-not $m.Success) { continue }
        $name = $m.Groups[1].Value
        $all.Add($name)
        $allLines.Add($line.Trim())
        if ($line.Contains($TaggedMarker)) { $conditional.Add($name) }
    }
    $default = New-Object System.Collections.Generic.List[string]
    $defaultLines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $all.Count; $i++) {
        if (-not $conditional.Contains($all[$i])) {
            $default.Add($all[$i])
            $defaultLines.Add($allLines[$i])
        }
    }
    return [pscustomobject]@{
        all          = @($all)
        conditional  = @($conditional)
        default      = @($default)
        defaultLines = @($defaultLines)
        doubleMode   = @($all)
    }
}

$head = (Get-GitText @('rev-parse', '--short=9', 'HEAD')).text.Trim()
$repoGatePath = Join-Path $RepoRoot ($GateScript -replace '/', '\')
if ([string]::IsNullOrWhiteSpace($CurrentFile)) {
    $currentPath = $repoGatePath
} else {
    $currentPath = (Resolve-Path -LiteralPath $CurrentFile).Path
}
$currentText = [IO.File]::ReadAllText($currentPath)
$baselineBlobText = (Get-GitText @('show', ($BaselineRevision + ':' + $GateScript))).text

$current = Get-StepPlan -Text $currentText
$baseline = Get-StepPlan -Text $baselineBlobText

Write-Host '============================================================='
Write-Host ' TASK-073 A: the default gate plan is unchanged'
Write-Host (' repo     : ' + $RepoRoot)
Write-Host (' file     : ' + $currentPath)
Write-Host (' baseline : ' + $BaselineRevision + ':' + $GateScript)
Write-Host (' HEAD     : ' + $head)
Write-Host (' evidence : ' + $EvidenceDir)
Write-Host '============================================================='
Write-Host ('baseline default steps ({0}): {1}' -f $baseline.default.Count, ($baseline.default -join ', '))
Write-Host ('current  default steps ({0}): {1}' -f $current.default.Count, ($current.default -join ', '))
Write-Host ('current  double-mode steps ({0}): {1}' -f $current.doubleMode.Count, ($current.doubleMode -join ', '))

Check 'g3p_baseline_read_from_git_is_a_gate_script' (($baselineBlobText.Length -gt 0) -and ($baseline.default.Count -gt 0)) `
    ('git show {0}:{1} returned {2} byte(s) and {3} step(s)' -f $BaselineRevision, $GateScript, $baselineBlobText.Length, $baseline.default.Count)

$sameCount = ($baseline.default.Count -eq $current.default.Count)
$sameOrder = $true
if ($sameCount) {
    for ($i = 0; $i -lt $baseline.default.Count; $i++) {
        if ($baseline.default[$i] -ne $current.default[$i]) { $sameOrder = $false }
    }
}
Check 'g3p_default_default_plan_is_identical_in_order_and_content' ($sameCount -and $sameOrder) `
    ('baseline {0} step(s) vs current {1} step(s); same order and content = {2} (with neither -PrecisionVariant nor -WithDouble, this is the whole step list)' -f $baseline.default.Count, $current.default.Count, $sameOrder)

# The stronger half: the step LINES, arguments included, not just the names. A
# reordering, a dropped argument or a changed engine flag would fail here even
# when the names still line up.
$sameLineCount = ($baseline.defaultLines.Count -eq $current.defaultLines.Count)
$differentLines = New-Object System.Collections.Generic.List[string]
if ($sameLineCount) {
    for ($i = 0; $i -lt $baseline.defaultLines.Count; $i++) {
        if ($baseline.defaultLines[$i] -cne $current.defaultLines[$i]) {
            $differentLines.Add(('step {0} {1}: baseline [{2}] current [{3}]' -f $i, $current.default[$i], $baseline.defaultLines[$i], $current.defaultLines[$i]))
        }
    }
} else {
    $differentLines.Add('step counts differ')
}
Check 'g3p_default_step_lines_are_identical_arguments_included' (($sameLineCount) -and ($differentLines.Count -eq 0)) `
    ('{0} DEFAULT step line(s) compared verbatim (trimmed), differing = {1}{2}' -f $current.defaultLines.Count, $differentLines.Count, $(if ($differentLines.Count -gt 0) { ' :: ' + ($differentLines -join ' ;; ') } else { '' }))

Check 'g3p_baseline_carries_no_double_only_step' ($baseline.conditional.Count -eq 0) `
    ('tagged double-only steps in the baseline = {0} (the baseline really is the pre-TASK-073 file)' -f $baseline.conditional.Count)

$extra = @($current.doubleMode | Where-Object { $current.default -notcontains $_ })
Check 'g3p_double_mode_adds_exactly_one_step_named_gate3_double_variant' (($current.conditional.Count -eq 1) -and ($extra.Count -eq 1) -and ($current.conditional[0] -eq 'gate3_double_variant')) `
    ('tagged steps = {0}; extra step(s) in double mode = {1} (must be exactly one, named gate3_double_variant)' -f $current.conditional.Count, $extra.Count)

$variantMentions = @([regex]::Matches($currentText, [regex]::Escape($VariantScriptName))).Count
$taggedStepLines = @($currentText -split "`n" | Where-Object { $_.Contains($TaggedMarker) -and ($_ -match "Invoke-Step\s+'") })
$invokeLinesWithVariant = @($currentText -split "`n" | Where-Object { ($_ -match "Invoke-Step\s+'") -and $_.Contains($VariantScriptName) })
Check 'g3p_the_variant_script_is_invoked_only_by_the_tagged_step' (($taggedStepLines.Count -eq 1) -and ($invokeLinesWithVariant.Count -eq 1) -and $taggedStepLines[0].Contains($VariantScriptName)) `
    ('Invoke-Step lines carrying the tag = {0}; Invoke-Step lines naming {1} = {2}; the tagged step is the one that invokes it = {3} (total mentions of the name anywhere in the file, comments included: {4})' -f $taggedStepLines.Count, $VariantScriptName, $invokeLinesWithVariant.Count, $taggedStepLines[0].Contains($VariantScriptName), $variantMentions)

$planPath = Join-Path $EvidenceDir 'gate3_default_plan_compare.txt'
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('TASK-073 A -- default vs double-mode step plan of mcp059_gates.ps1')
$lines.Add('repo             = ' + $RepoRoot)
$lines.Add('file             = ' + $currentPath)
$lines.Add('git HEAD         = ' + $head)
$lines.Add('baseline revision= ' + $BaselineRevision)
$lines.Add('baseline blob    = ' + (Get-GitText @('rev-parse', ($BaselineRevision + ':' + $GateScript))).text.Trim())
$lines.Add('')
$lines.Add('BASELINE default plan (' + $baseline.default.Count + ' steps):')
$lines.Add(($baseline.default | ForEach-Object { '  ' + $_ }))
$lines.Add('')
$lines.Add('CURRENT default plan (' + $current.default.Count + ' steps):')
$lines.Add(($current.default | ForEach-Object { '  ' + $_ }))
$lines.Add('')
$lines.Add('CURRENT double-mode plan (' + $current.doubleMode.Count + ' steps):')
$lines.Add(($current.doubleMode | ForEach-Object { '  ' + $_ }))
$lines.Add('')
$lines.Add('CURRENT default step lines, arguments included (' + $current.defaultLines.Count + '):')
$lines.Add(($current.defaultLines | ForEach-Object { '  ' + $_ }))
$lines.Add('')
$lines.Add('BASELINE default step lines, arguments included (' + $baseline.defaultLines.Count + '):')
$lines.Add(($baseline.defaultLines | ForEach-Object { '  ' + $_ }))
$lines.Add('')
$lines.Add('tagged (double-only) steps = ' + $current.conditional.Count + ' (' + ($current.conditional -join ', ') + ')')
$lines.Add('default plan identical in order and content = ' + ($sameCount -and $sameOrder))
$lines.Add('checks = ' + $script:Rows.Count + ' failures ' + $script:Failures)
$lines.Add('')
foreach ($row in $script:Rows) { $lines.Add($row) }
[IO.File]::WriteAllLines($planPath, $lines.ToArray())

Write-Host ('  plan artifact: ' + $planPath)
Write-Host ('  checks       : {0} failures {1}' -f $script:Rows.Count, $script:Failures)
Write-Host ('DEFAULT_PLAN_COMPARE RESULT={0} baseline_steps={1} default_steps={2} double_steps={3}' -f $(if ($script:Failures -eq 0) { 'PASS' } else { 'FAIL' }), $baseline.default.Count, $current.default.Count, $current.doubleMode.Count)
if ($script:Failures -gt 0) {
    Write-Host ('DEFAULT PLAN COMPARE FAILED: {0}' -f $script:Failures)
    exit 1
}
Write-Host 'DEFAULT PLAN COMPARE PASS'
exit 0
