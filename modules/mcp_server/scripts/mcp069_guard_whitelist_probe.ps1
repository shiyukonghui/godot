# =============================================================================
#  mcp069_guard_whitelist_probe.ps1 -- TASK-069 section 1.3 (2)-(4).
#
#  Defect 1: `Restore-McpEvidence` (scripts\mcp_evidence_guard.ps1) put every path
#  that appeared *after* its snapshot back by DELETING it. Its rule was "delete
#  everything new", not "restore the artifacts this battery's steps declared",
#  so a report written while the battery ran was deleted with the battery's own
#  scratch output. (What the 15 step scripts really write is documented in the
#  guard's own header: tracked evidence under
#  modules/mcp_server/docs/reports/evidence/**, plus exactly one new file,
#  docs/reports/evidence/task051/red/e20_child_status.json.)
#
#  This probe exercises the fixed restore directly, on a scratch git repository
#  in %TEMP% (never inside the repository under test), with four paths at once so
#  the declaration has to DISCRIMINATE rather than "leave everything alone":
#
#    path                                   declared?  expected outcome
#    docs/reports/REPORT-planted.md         no         UNTOUCHED (still there, same bytes)
#    docs/reports/other.txt   (modified)    no         UNTOUCHED (still modified)
#    evidence/new_declared.json             yes        removed (RESTORED-NEW)
#    evidence/tracked.txt     (modified)    yes        reverted to HEAD (RESTORED)
#
#  And the default-deny half: the SAME scenario with no declaration at all must
#  leave all four exactly as they are -- an empty whitelist can never be mistaken
#  for "widen the directory".
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp069_guard_whitelist_probe.ps1
#
#  Pure ASCII on purpose.
# =============================================================================

param([string]$OutRoot = '')

$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)

if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp069\guard-probe' }
$script:Failures = 0
function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    if (-not $Pass) { $script:Failures = $script:Failures + 1 }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Get-Sha {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '<absent>' }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllBytes($Path, $utf8.GetBytes($Text))
}

Remove-Item -Recurse -Force $OutRoot -ErrorAction SilentlyContinue
$Repo = Join-Path $OutRoot 'repo'
New-Item -ItemType Directory -Force -Path $Repo | Out-Null

. (Join-Path $PSScriptRoot 'mcp_evidence_guard.ps1')

Write-Host '=================================================================='
Write-Host ' TASK-069: restore-whitelist probe (scratch repository)'
Write-Host '=================================================================='

# --- the scratch repository: two tracked files in two different directories ---
# git writes progress/warnings to stderr, and `$ErrorActionPreference = 'Stop'`
# turns a native stderr line into a terminating error, so every git call goes
# through this helper (exit code returned, output discarded).
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

$null = Invoke-Git @('-C', $Repo, 'init', '-q')
$null = Invoke-Git @('-C', $Repo, 'config', 'user.email', 'mcp069@example.invalid')
$null = Invoke-Git @('-C', $Repo, 'config', 'user.name', 'MCP069 probe')
$null = Invoke-Git @('-C', $Repo, 'config', 'commit.gpgsign', 'false')
$null = Invoke-Git @('-C', $Repo, 'config', 'core.autocrlf', 'false')
Write-Text -Path (Join-Path $Repo 'evidence\tracked.txt') -Text "tracked 1`n"
Write-Text -Path (Join-Path $Repo 'docs\reports\other.txt') -Text "tracked 2`n"
$null = Invoke-Git @('-C', $Repo, 'add', '-A')
$null = Invoke-Git @('-C', $Repo, 'commit', '-q', '-m', 'scratch base')
Check 'W01_scratch_repo_has_a_head' (((& git -C $Repo rev-parse --verify HEAD 2>$null | Out-String).Trim()).Length -eq 40) `
    ("HEAD={0}" -f ((& git -C $Repo rev-parse --short HEAD 2>$null) -join ''))

$TrackedEvidence = Join-Path $Repo 'evidence\tracked.txt'
$TrackedOther = Join-Path $Repo 'docs\reports\other.txt'
$PlantedReport = Join-Path $Repo 'docs\reports\REPORT-planted.md'
$NewDeclared = Join-Path $Repo 'evidence\new_declared.json'

$baseEvidence = Get-Sha $TrackedEvidence
$baseOther = Get-Sha $TrackedOther

# ---------------------------------------------------------------------------
#  Scenario A: one declared root ("evidence/"), everything else default-deny.
# ---------------------------------------------------------------------------
$before = Get-McpEvidenceState -RepoRoot $Repo
Write-Text -Path $PlantedReport -Text "a report written while the battery ran`n"
Write-Text -Path $NewDeclared -Text "{`"declared`": true}`n"
Write-Text -Path $TrackedEvidence -Text "MODIFIED by a step`n"
Write-Text -Path $TrackedOther -Text "MODIFIED by a human`n"

$plantedSha = Get-Sha $PlantedReport
$declaredSha = Get-Sha $NewDeclared

$manifest = Restore-McpEvidence -RepoRoot $Repo -Before $before -AllowedRoots @('evidence')
Write-Host '--- manifest (scenario A: -AllowedRoots evidence) ---'
$manifest | ForEach-Object { Write-Host ('    ' + $_) }
Write-Host ''

Check 'W10_the_planted_report_survives' ((Test-Path -LiteralPath $PlantedReport) -and ((Get-Sha $PlantedReport) -ceq $plantedSha)) `
    ("docs/reports/REPORT-planted.md exists with the same sha256 ({0}); it is not this battery's artifact" -f $plantedSha.Substring(0, 8))
Check 'W11_the_manifest_names_it_as_untouched' (@($manifest | Where-Object { $_ -like ('UNTOUCHED docs/reports/REPORT-planted.md*') }).Count -eq 1) `
    (@($manifest | Where-Object { $_ -like 'UNTOUCHED*' }) -join ' || ')
Check 'W12_a_tracked_file_modified_outside_the_declaration_is_untouched' ((Get-Sha $TrackedOther) -cne $baseOther) `
    ("docs/reports/other.txt is still the modified bytes (base {0} -> now {1}); the restore does not revert work outside its declaration" -f $baseOther.Substring(0, 8), (Get-Sha $TrackedOther).Substring(0, 8))
Check 'W13_the_declared_new_file_is_removed' (-not (Test-Path -LiteralPath $NewDeclared)) `
    ("evidence/new_declared.json (sha256 {0} before the restore) is gone and the manifest says so" -f $declaredSha.Substring(0, 8))
Check 'W14_the_declared_modified_file_is_back_to_head' ((Get-Sha $TrackedEvidence) -ceq $baseEvidence) `
    ("evidence/tracked.txt sha256 {0} again" -f $baseEvidence.Substring(0, 8))
Check 'W15_the_manifest_records_both_halves_of_the_restore' `
    ((@($manifest | Where-Object { $_ -like 'RESTORED evidence/tracked.txt*' }).Count -eq 1) -and (@($manifest | Where-Object { $_ -like 'RESTORED-NEW evidence/new_declared.json*' }).Count -eq 1)) `
    (($manifest | Where-Object { $_ -like 'RESTORED*' }) -join ' || ')
Check 'W16_the_summary_counts_the_untouched_paths' (@($manifest | Where-Object { $_ -like 'SUMMARY*' -and $_ -match 'untouched=2' }).Count -eq 1) `
    (($manifest | Where-Object { $_ -like 'SUMMARY*' }) -join ' | ')

# ---------------------------------------------------------------------------
#  Scenario B: default deny -- no declaration at all.
# ---------------------------------------------------------------------------
Remove-Item -Recurse -Force $OutRoot | Out-Null
New-Item -ItemType Directory -Force -Path $Repo | Out-Null
$null = Invoke-Git @('-C', $Repo, 'init', '-q')
$null = Invoke-Git @('-C', $Repo, 'config', 'user.email', 'mcp069@example.invalid')
$null = Invoke-Git @('-C', $Repo, 'config', 'user.name', 'MCP069 probe')
$null = Invoke-Git @('-C', $Repo, 'config', 'commit.gpgsign', 'false')
$null = Invoke-Git @('-C', $Repo, 'config', 'core.autocrlf', 'false')
Write-Text -Path (Join-Path $Repo 'evidence\tracked.txt') -Text "tracked 1`n"
Write-Text -Path (Join-Path $Repo 'docs\reports\other.txt') -Text "tracked 2`n"
$null = Invoke-Git @('-C', $Repo, 'add', '-A')
$null = Invoke-Git @('-C', $Repo, 'commit', '-q', '-m', 'scratch base')

$before2 = Get-McpEvidenceState -RepoRoot $Repo
Write-Text -Path $PlantedReport -Text "scenario B report`n"
Write-Text -Path $NewDeclared -Text "{`"declared`": true}`n"
Write-Text -Path $TrackedEvidence -Text "MODIFIED in scenario B`n"
$plantedSha2 = Get-Sha $PlantedReport
$declaredSha2 = Get-Sha $NewDeclared

$manifest2 = Restore-McpEvidence -RepoRoot $Repo -Before $before2
Write-Host '--- manifest (scenario B: no declaration at all -> default deny) ---'
$manifest2 | ForEach-Object { Write-Host ('    ' + $_) }
Write-Host ''

Check 'W20_default_deny_deletes_nothing' ((Test-Path -LiteralPath $NewDeclared) -and ((Get-Sha $NewDeclared) -ceq $declaredSha2)) `
    ("evidence/new_declared.json still exists (sha256 {0}) even though it is inside a directory a declaration COULD have named" -f $declaredSha2.Substring(0, 8))
Check 'W21_default_deny_leaves_the_planted_report_alone' ((Test-Path -LiteralPath $PlantedReport) -and ((Get-Sha $PlantedReport) -ceq $plantedSha2)) `
    ("docs/reports/REPORT-planted.md sha256 {0} unchanged" -f $plantedSha2.Substring(0, 8))
Check 'W22_default_deny_does_not_revert_tracked_files' ((Get-Sha $TrackedEvidence) -cne $baseEvidence) `
    ("evidence/tracked.txt is still the modified bytes ({0} -> {1})" -f $baseEvidence.Substring(0, 8), (Get-Sha $TrackedEvidence).Substring(0, 8))
Check 'W23_the_manifest_says_the_declaration_is_empty' (@($manifest2 | Where-Object { $_ -like 'SUMMARY*' -and $_ -match 'restored=0' -and $_ -match 'removed=0' -and $_ -match 'untouched=3' }).Count -eq 1) `
    (($manifest2 | Where-Object { $_ -like 'SUMMARY*' }) -join ' | ')

# The grammar itself: a declaration that would mean "every path" must be refused
# rather than honoured, and the matching must be a prefix rule rather than a
# substring rule (this is the difference between a whitelist and an ignore list).
$blanketRefused = $false
try { $null = Test-McpDeclaredPath -Path 'anything' -AllowedRoots @('./') } catch { $blanketRefused = $true }
Check 'W24_a_blanket_declaration_is_refused' $blanketRefused `
    'Test-McpDeclaredPath -AllowedRoots ./ throws instead of declaring every path in the repository'
Check 'W25_an_undeclared_path_is_not_declared' `
    ((Test-McpDeclaredPath -Path 'docs/reports/x.md' -AllowedRoots @('evidence')) -eq $false) `
    'docs/reports/x.md is outside the declared root evidence/ and is therefore NOT declared (default deny)'
Check 'W26_a_path_under_a_declared_root_is_declared' `
    ((Test-McpDeclaredPath -Path 'evidence/a/b.json' -AllowedRoots @('evidence')) -eq $true) `
    'evidence/a/b.json is under the declared root evidence/, so it IS declared'
Check 'W27_the_declaration_is_not_a_substring_match' `
    ((Test-McpDeclaredPath -Path 'not-evidence/a.json' -AllowedRoots @('evidence')) -eq $false) `
    'not-evidence/a.json merely contains the string "evidence" and must not be declared'
Check 'W28_a_declared_exact_path_is_declared' `
    ((Test-McpDeclaredPath -Path 'modules/mcp_server/docs/x.json' -AllowedPaths @('modules\mcp_server\docs\x.json')) -eq $true) `
    'the separator the caller uses does not matter: a backslash declaration matches the forward-slash path git prints'

Remove-Item -Recurse -Force $OutRoot -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("PROBE FAILURES: {0}" -f $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
Write-Host 'TASK-069 RESTORE-WHITELIST PROBE PASS (declared paths restored, undeclared paths untouched, default deny touches nothing)'
exit 0