# =============================================================================
#  mcp069_stale_expectation_reverse_probe.ps1 -- TASK-069 section 2.4 (3).
#
#  The stale expectations this task repaired are the same class TASK-064 and
#  TASK-068 repaired: an assertion that pinned a *behaviour* which a later task
#  deliberately changed, so the gate went red for a reason that is not a defect -
#  and stayed red in silence because its driver returned 0. They were not deleted
#  and not relaxed: each one was replaced by a DERIVED expectation, and this file
#  is the machine evidence for the three claims a reader would otherwise have to
#  take on trust:
#
#    1. the OLD expression is FALSE on today's behaviour (a loop that reached it
#       would exit non-zero)      -> the staleness is real, not a guess;
#    2. the NEW expression is TRUE on the same input -> the fix is not a
#       deletion;
#    3. the NEW expression is FALSE on a mutated input -> it is not a tautology
#       (the same non-vacuity probe TASK-068 used for its derived contract size).
#
#  Section A -- the three `mcp042_projectrewrite_and_honesty_evidence.ps1`
#  expectations. TASK-057 patch 2 / TASK-059 D-4 moved `editor_add_input_action`
#  onto `ProjectSettings::save_custom_section()`, which replaces only the target
#  section's text; TASK-042's A22/A23/A26b pinned the whole-file rewrite. Three
#  texts are built from the real specimen
#  (modules/gdscript/tests/scripts/project.godot):
#    * SECTION-LIKE    : the specimen's bytes up to `[input]`, then the same
#                        section with one entry appended (the new writer);
#    * WHOLE-FILE-LIKE : the engine's fixed header plus the specimen with its
#                        comment lines removed (the old writer);
#    * PROLOGUE-MUTATED: SECTION-LIKE with one prologue line renamed, i.e. a
#                        writer that dropped a line outside the target section.
#
#  Section B -- the five `mcp043_description_evidence.ps1` L21 expectations.
#  TASK-059 D-4 rewrote five descriptions from `mode=append` to `mode=replace`,
#  so "the live description ends with the sentence TASK-043 appended" is false by
#  construction. The new expression is DERIVED from the declaration
#  (`DESCRIPTION_OVERRIDES` in scripts/gen_renamed_contract.py, the table the
#  contract is generated from) through scripts/mcp069_override_dump.py:
#  append -> the description must END with the declared sentence; replace -> the
#  description must BE the declared text, byte for byte.
#
#  Section C -- the static half of defect 2: the three gate drivers carry the
#  TASK-069 guard block, and the new repository check answers exit 0.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp069_stale_expectation_reverse_probe.ps1
#  Exit 0 when every old expression is false, every new one is true, every
#  mutated-input control is false, and the static probes hold; exit 1 otherwise.
#
#  Pure ASCII on purpose.
# =============================================================================

param([string]$OutRoot = '')

$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$ModuleRoot = Join-Path $RepoRoot 'modules\mcp_server'
$Scripts = Join-Path $ModuleRoot 'scripts'
$Specimen = Join-Path $RepoRoot 'modules\gdscript\tests\scripts\project.godot'
$ContractPath = Join-Path $ModuleRoot 'docs\tools_list.renamed.json'
$RewriteEvidence = Join-Path $Scripts 'mcp042_projectrewrite_and_honesty_evidence.ps1'
if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp069\stale-probe' }
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$script:Failures = 0
$script:Rows = New-Object System.Collections.Generic.List[object]

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

function Read-JsonNoBom {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (ConvertFrom-Json ([IO.File]::ReadAllText($Path, $utf8)))
}

Write-Host '============================================================='
Write-Host ' TASK-069: stale-expectation reverse probe (old vs new vs mutated)'
Write-Host '============================================================='
Write-Host ''

# =============================================================================
#  Section A: A22 / A23 / A26b
# =============================================================================
$originalText = [IO.File]::ReadAllText($Specimen, $utf8)
$inputIndex = $originalText.IndexOf('[input]')
$originalPrologue = if ($inputIndex -ge 0) { $originalText.Substring(0, $inputIndex) } else { '' }
$originalSectionText = if ($inputIndex -ge 0) { $originalText.Substring($inputIndex) } else { '' }
$originalLines = @($originalText -split "`r?`n")
$originalCommentLines = @($originalLines | Where-Object { $_.StartsWith(';') })
$headerLine = '; Engine configuration file.'
$probeEntry = "mcp069_probe_action={`r`n`"deadzone`": 0.2,`r`n`"events`": []`r`n}`r`n"

$sectionLikeText = $originalPrologue + $originalSectionText + $probeEntry
$wholeFileLikeText = $headerLine + "`r`n" + (($originalLines | Where-Object { -not $_.StartsWith(';') }) -join "`r`n")
$prologueMutatedText = $sectionLikeText.Replace('config_version=5', 'config_version_renamed=5')

Write-Host ("specimen         : {0} ({1} char(s), {2} comment line(s), [input] at {3})" -f $Specimen, $originalText.Length, $originalCommentLines.Count, $inputIndex)
Write-Host ("prologue         : {0} char(s) before '[input]' - the DERIVED boundary A22/A23/A26b use now" -f $originalPrologue.Length)
Write-Host ("section-like     : {0} char(s) (comments kept, no engine header)" -f $sectionLikeText.Length)
Write-Host ("whole-file-like  : {0} char(s) (engine header, comments gone)" -f $wholeFileLikeText.Length)
Write-Host ("prologue-mutated : {0} char(s) (one prologue line renamed)" -f $prologueMutatedText.Length)
Write-Host ''

function Test-A22-Old {
    param([string]$AfterText)
    $lost = @($originalCommentLines | Where-Object { -not $AfterText.Contains($_) })
    $kept = @($originalCommentLines | Where-Object { $AfterText.Contains($_) })
    return (($lost.Count -eq $originalCommentLines.Count) -and ($kept.Count -eq 0))
}
function Test-A23-Old {
    param([string]$AfterText)
    return $AfterText.Contains($headerLine)
}
function Test-A26b-Old {
    param([string]$AfterText)
    $missing = @($originalLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $AfterText.Contains($_) })
    return ($missing.Count -eq $originalCommentLines.Count)
}
function Test-A22 {
    param([string]$AfterText)
    $lost = @($originalCommentLines | Where-Object { -not $AfterText.Contains($_) })
    $kept = @($originalCommentLines | Where-Object { $AfterText.Contains($_) })
    $prologuePreserved = ($originalPrologue.Length -gt 0) -and $AfterText.StartsWith($originalPrologue)
    return (($lost.Count -eq 0) -and ($kept.Count -eq $originalCommentLines.Count) -and $prologuePreserved)
}
function Test-A23 {
    param([string]$AfterText)
    $firstLine = ($AfterText -split "`r?`n")[0]
    return ((-not $AfterText.Contains($headerLine)) -and ($firstLine -ceq $originalLines[0]))
}
function Test-A26b {
    param([string]$AfterText)
    $outsideText = if ($inputIndex -ge 0) { $originalText.Substring(0, $inputIndex) } else { $originalText }
    $missingOutside = @($outsideText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $AfterText.Contains($_) })
    return ($missingOutside.Count -eq 0)
}

$rewriteScriptText = [IO.File]::ReadAllText($RewriteEvidence, $utf8)

Write-Host '--- A: the OLD expressions are false on the new behaviour (stale) ---'
Record-Probe -Id 'A22_old_every_comment_is_gone_is_false_on_a_section_write' `
    -Source 'mcp042_projectrewrite_and_honesty_evidence.ps1 (A22, before TASK-069)' `
    -Expression '(Test-A22-Old -AfterText $sectionLikeText)' -Expected $false `
    -Why 'TASK-057 patch 2 / TASK-059 D-4: the section writer preserves the prologue, so 0/4 comments are lost and the TASK-042 expectation ("all four gone") is stale'
Record-Probe -Id 'A23_old_engine_header_is_written_is_false_on_a_section_write' `
    -Source 'mcp042_projectrewrite_and_honesty_evidence.ps1 (A23, before TASK-069)' `
    -Expression '(Test-A23-Old -AfterText $sectionLikeText)' -Expected $false `
    -Why 'the section writer copies every byte outside [input] through, so the engine header is never written'
Record-Probe -Id 'A26b_old_only_the_comments_are_lost_is_false_on_a_section_write' `
    -Source 'mcp042_projectrewrite_and_honesty_evidence.ps1 (A26b, before TASK-069)' `
    -Expression '(Test-A26b-Old -AfterText $sectionLikeText)' -Expected $false `
    -Why 'nothing at all is lost any more, so "missing == 4 comment lines" no longer holds'

Write-Host ''
Write-Host '--- A: the NEW derived expressions are true on a section write ---'
Record-Probe -Id 'A22_new_comments_and_the_prologue_are_preserved' `
    -Source 'mcp042_projectrewrite_and_honesty_evidence.ps1 (A22, after TASK-069)' `
    -Expression '(Test-A22 -AfterText $sectionLikeText)' -Expected $true `
    -Why 'the boundary is DERIVED from the specimen (the bytes before [input]); no comment count and no engine expectation is written down'
Record-Probe -Id 'A23_new_the_engine_header_is_absent_and_the_first_line_survives' `
    -Source 'mcp042_projectrewrite_and_honesty_evidence.ps1 (A23, after TASK-069)' `
    -Expression '(Test-A23 -AfterText $sectionLikeText)' -Expected $true `
    -Why 'derived from the same boundary: a whole-file rewrite puts the engine header on line 1 and fails this'
Record-Probe -Id 'A26b_new_nothing_outside_the_target_section_is_lost' `
    -Source 'mcp042_projectrewrite_and_honesty_evidence.ps1 (A26b, after TASK-069)' `
    -Expression '(Test-A26b -AfterText $sectionLikeText)' -Expected $true `
    -Why 'the target section boundary is computed from the original text, so the claim names the ONLY place a line may disappear'

Write-Host ''
Write-Host '--- A: non-vacuity (new expressions on the old writer / a dropped prologue line) ---'
Record-Probe -Id 'A22_new_is_false_on_a_whole_file_rewrite' `
    -Source 'mutated input: engine header + comments stripped (the old writer)' `
    -Expression '(Test-A22 -AfterText $wholeFileLikeText)' -Expected $false `
    -Why 'the old writer loses the prologue and all four comments; the new predicate must say so instead of being constantly true'
Record-Probe -Id 'A23_new_is_false_on_a_whole_file_rewrite' `
    -Source 'mutated input: engine header + comments stripped (the old writer)' `
    -Expression '(Test-A23 -AfterText $wholeFileLikeText)' -Expected $false `
    -Why 'the engine header IS written in that case, so the derived predicate is not a tautology'
Record-Probe -Id 'A26b_new_is_false_when_one_prologue_line_is_gone' `
    -Source 'mutated input: one prologue line renamed outside the target section' `
    -Expression '(Test-A26b -AfterText $prologueMutatedText)' -Expected $false `
    -Why 'a line outside [input] disappeared, which is exactly what the derived predicate forbids (the old whole-file writer kept those lines, so this is the mutation that isolates the claim)'

Write-Host ''
Record-Probe -Id 'A_fix_is_the_one_the_script_carries_prologue' `
    -Source 'mcp042_projectrewrite_and_honesty_evidence.ps1' `
    -Expression '$rewriteScriptText.Contains("`$prologuePreserved")' -Expected $true `
    -Why 'the probe evaluates the same derivation the repaired script carries (same-input discipline), not a paraphrase'
Record-Probe -Id 'A_fix_is_the_one_the_script_carries_missing_outside' `
    -Source 'mcp042_projectrewrite_and_honesty_evidence.ps1' `
    -Expression '$rewriteScriptText.Contains("`$missingOutsideInputSection")' -Expected $true `
    -Why 'A26b now counts the missing lines OUTSIDE the target section only'

# =============================================================================
#  Section B: the five L21 expectations
# =============================================================================
Write-Host ''
$Sentence = "When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them."

$dumpPath = Join-Path $OutRoot 'description_overrides.json'
& python (Join-Path $Scripts 'mcp069_override_dump.py') --out $dumpPath --kind description | Out-Null
if ($LASTEXITCODE -ne 0) { throw ('mcp069_override_dump.py exited {0}' -f $LASTEXITCODE) }
$dump = Read-JsonNoBom -Path $dumpPath
$contract = Read-JsonNoBom -Path $ContractPath
$live = @{}
foreach ($tool in $contract.result.tools) { $live[[string]$tool.name] = [string]$tool.description }
$contractModeByOldName = @{}
foreach ($override in $contract._meta.overrides) {
    if ([string]$override.kind -ceq 'description') { $contractModeByOldName[[string]$override.old_name] = [string]$override.mode }
}

$Affected = @(
    @{ new = 'project_set_setting'; old = 'set_project_setting' },
    @{ new = 'project_add_autoload'; old = 'add_autoload' },
    @{ new = 'project_remove_autoload'; old = 'remove_autoload' },
    @{ new = 'editor_add_input_action'; old = 'set_input_action' },
    @{ new = 'editor_reload_plugin'; old = 'reload_plugin' }
)

Write-Host ("override dump    : generator_version={0} count={1}" -f $dump.generator_version, $dump.count)
Write-Host '--- B: the two independent declarations of each mode agree ---'
foreach ($item in $Affected) {
    $declaredMode = [string]$dump.overrides.($item.old).mode
    $contractMode = [string]$contractModeByOldName[$item.old]
    Record-Probe -Id ('B_declared_mode_agrees_for_{0}' -f $item.old) `
        -Source 'scripts/gen_renamed_contract.py DESCRIPTION_OVERRIDES vs docs/tools_list.renamed.json _meta.overrides' `
        -Expression ('("{0}" -ceq "{1}")' -f $declaredMode, $contractMode) -Expected $true `
        -Why ('the generator table and the contract it generated say the same mode ({0}); the derived expectation is not reading one source alone' -f $declaredMode)
}

Write-Host ''
Write-Host '--- B: the OLD L21 expression is false for all five (stale) ---'
foreach ($item in $Affected) {
    $name = [string]$item.new
    Record-Probe -Id ('L21_old_{0}_ends_with_the_appended_sentence' -f $name) `
        -Source 'mcp043_description_evidence.ps1 (L21, before TASK-069)' `
        -Expression ('([string]$live["{0}"]).EndsWith($Sentence)' -f $name) -Expected $false `
        -Why 'TASK-059 D-4 switched this description to mode=replace; the sentence TASK-043 appended is gone from the wire'
}

Write-Host ''
Write-Host '--- B: the NEW derived expression is true, and false on a mutated input ---'
foreach ($item in $Affected) {
    $name = [string]$item.new
    $old = [string]$item.old
    $declaredMode = [string]$dump.overrides.$old.mode
    $declaredValue = [string]$dump.overrides.$old.value
    if ($declaredMode -ceq 'append') {
        $newExpr = ('(([string]$live["{0}"]).EndsWith([string]$dump.overrides."{1}".value) -and (([string]$live["{0}"]).Length -gt ([string]$dump.overrides."{1}".value).Length))' -f $name, $old)
        $mutExpr = ('(([string]$live["{0}"]).Substring(0, [Math]::Max(0, ([string]$live["{0}"]).Length - 1)).EndsWith([string]$dump.overrides."{1}".value))' -f $name, $old)
        $why = 'declared mode=append: the wording the override appends must still be the tail (derived from the declaration, not copied into the script)'
    } else {
        $newExpr = ('(([string]$live["{0}"]) -ceq ([string]$dump.overrides."{1}".value))' -f $name, $old)
        $mutExpr = ('(([string]$live["{0}"] + " ") -ceq ([string]$dump.overrides."{1}".value))' -f $name, $old)
        $why = 'declared mode=replace: the live description must BE the declared text byte for byte, which is strictly stronger than "ends with a sentence"'
    }
    Record-Probe -Id ('L21_new_{0}_matches_the_declared_{1}_override' -f $name, $declaredMode) `
        -Source 'mcp043_description_evidence.ps1 (L21, after TASK-069)' `
        -Expression $newExpr -Expected $true -Why $why
    Record-Probe -Id ('L21_new_{0}_is_false_on_a_mutated_input' -f $name) `
        -Source 'mutated input: one byte added to the declared text' `
        -Expression $mutExpr -Expected $false `
        -Why 'the derived expression is not a tautology: a one-byte change to the wire description makes it false'
    Record-Probe -Id ('L21_new_{0}_does_not_carry_the_disproven_sentence' -f $name) `
        -Source 'mcp043_description_evidence.ps1 (L21, after TASK-069)' `
        -Expression ('(-not ([string]$live["{0}"]).Contains($Sentence))' -f $name) -Expected ($declaredMode -ceq 'replace') `
        -Why 'the TASK-043 sentence names a fact TASK-057 patch 2 disproved; for a replace-mode entry it must not be on the wire any more'
}

# =============================================================================
#  Section C: the static half of defect 2
# =============================================================================
Write-Host ''
$marker = '# --- TASK-069 gate: a battery whose steps are red must not exit 0'
foreach ($gate in @('mcp041_gates.ps1', 'mcp042_gates.ps1', 'mcp043_gates.ps1')) {
    $gatePath = Join-Path $Scripts $gate
    Record-Probe -Id ('C_guard_block_present_in_{0}' -f $gate) `
        -Source $gate `
        -Expression ('(([IO.File]::ReadAllText("{0}")) -match [regex]::Escape("{1}"))' -f $gatePath, $marker) `
        -Expected $true `
        -Why 'the driver carries the TASK-069 guard block that reads its own summary back'
    Record-Probe -Id ('C_guard_uses_the_summary_pattern_in_{0}' -f $gate) `
        -Source $gate `
        -Expression ('(([IO.File]::ReadAllText("{0}")) -match [regex]::Escape("EXIT [1-9]"))' -f $gatePath) `
        -Expected $true `
        -Why 'and refuses to exit 0 when any recorded step code is non-zero'
}

$checker = Join-Path $Scripts 'check_exit_propagation.py'
& python $checker | Out-Null
$checkerCode = $LASTEXITCODE
Record-Probe -Id 'C_the_repository_check_exits_0' `
    -Source 'scripts/check_exit_propagation.py' -Expression '($checkerCode -eq 0)' -Expected $true `
    -Why 'every aggregator shape under scripts/** and docs/scripts/** is guarded or pinned with a reason'
& python $checker --probes | Out-Null
$probeCode = $LASTEXITCODE
Record-Probe -Id 'C_the_repository_check_insertion_probes_pass' `
    -Source 'scripts/check_exit_propagation.py --probes' -Expression '($probeCode -eq 0)' -Expected $true `
    -Why 'an inserted red-reporting shape is flagged, and every declared guard spelling discharges one'

Write-Host ''
Write-Host ("probes={0} failures={1}" -f $script:Rows.Count, $script:Failures)
if ($script:Failures -gt 0) {
    Write-Host 'TASK-069 REVERSE PROBE FAILED'
    exit 1
}
Write-Host 'TASK-069 REVERSE PROBE PASS (every stale expectation is false on today input; every derived replacement is true, and false on a mutated input)'
exit 0