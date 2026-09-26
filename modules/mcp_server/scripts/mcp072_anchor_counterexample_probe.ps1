# =============================================================================
#  mcp072_anchor_counterexample_probe.ps1 -- TASK-072 section 2.3
#
#  The capability-preserving counter-examples. A judge that only ever says
#  "PASS" is worthless, so this probe builds the four situations on the REAL
#  repository with temporary commits and asserts what the judge must say:
#
#    1. change an .md only, do not rebuild   -> ANCHOR_STRUCTURAL_EQUIVALENT (PASS)
#    2. change a .cpp,  do not rebuild       -> ANCHOR_STALE_COMPILED       (FAIL)
#    3. an anchor that is not in HEAD's
#       history (a commit that survived a
#       `git reset --hard`, plus a forged
#       sha)                                 -> ANCHOR_NOT_ANCESTOR         (FAIL)
#    4. the binaries rebuilt onto HEAD       -> ANCHOR_EQUAL                (PASS)
#
#  Safety: the probe refuses to run unless `git status --porcelain -uno` is
#  empty, it commits with `--no-verify`, and a `finally` block always puts HEAD
#  and the working tree back with `git reset --hard <the HEAD it started on>`.
#  The two files it touches are hashed before and after, and the hash and the
#  porcelain status are asserted unchanged at the end.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp072_anchor_counterexample_probe.ps1
#  Exit 0 when every scenario behaves as required, 1 otherwise, 2 when the
#  repository is too dirty to run, 3 when the repository could not be restored.
#
#  Pure ASCII on purpose (Windows PowerShell 5.1 may read a .ps1 with the ANSI
#  code page when there is no BOM).
# =============================================================================

param(
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
}
. (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')

$script:Checks = 0
$script:Failures = 0

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks = $script:Checks + 1
    if (-not $Pass) { $script:Failures = $script:Failures + 1 }
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Invoke-ProbeGit {
    param([string[]]$GitArgs, [switch]$AllowFailure)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = @()
    $code = 0
    try {
        $out = @(& git -C $RepoRoot -c core.autocrlf=false -c core.safecrlf=false @GitArgs 2>$null)
        $code = [int]$LASTEXITCODE
    } catch {
        $code = -1
        $out = @()
    } finally {
        $ErrorActionPreference = $old
    }
    if (-not $AllowFailure -and $code -ne 0) {
        throw ('git {0} failed with exit {1}: {2}' -f ($GitArgs -join ' '), $code, ($out -join ' '))
    }
    return [pscustomobject]@{ ExitCode = $code; Lines = @($out) }
}

function Get-ProbeSha256 {
    param([string]$Relative)
    $full = Join-Path $RepoRoot $Relative
    if (-not (Test-Path $full)) { return '<missing>' }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToLower()
}

function Get-ProbePorcelain {
    $out = Invoke-ProbeGit -GitArgs @('status', '--porcelain', '--untracked-files=no')
    return (($out.Lines) -join "`n")
}

$docsFile = 'modules/mcp_server/docs/tasks/PLAYBOOK-group-port.md'
$cppFile = 'modules/mcp_server/tools/registration.cpp'
$plainExe = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$monoExe = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe'

Write-Host '============================================================='
Write-Host ' TASK-072: the anchor counter-examples on the real repository'
Write-Host '============================================================='
Write-Host ("repo            : {0}" -f $RepoRoot)

$startedUtc = (Get-Date).ToUniversalTime()
Write-Host ("START           : {0}" -f $startedUtc.ToString('yyyy-MM-dd HH:mm:ss'))

$head0 = (([string]((Invoke-ProbeGit -GitArgs @('rev-parse', 'HEAD')).Lines[0])) -join '').Trim()
$head0Short = (([string]((Invoke-ProbeGit -GitArgs @('rev-parse', '--short=9', 'HEAD')).Lines[0])) -join '').Trim()
$porcelain0 = Get-ProbePorcelain
$docsSha0 = Get-ProbeSha256 -Relative $docsFile
$cppSha0 = Get-ProbeSha256 -Relative $cppFile

Write-Host ("HEAD            : {0} ({1})" -f $head0Short, $head0)
Write-Host ("docs file       : {0} sha256={1}" -f $docsFile, $docsSha0)
Write-Host ("cpp file        : {0} sha256={1}" -f $cppFile, $cppSha0)
Write-Host ("porcelain -uno  : {0}" -f $(if ($porcelain0.Trim().Length -eq 0) { '<clean>' } else { $porcelain0 }))
Write-Host ''

if ($porcelain0.Trim().Length -ne 0) {
    Write-Host 'FATAL: the tracked working tree is not clean; this probe makes temporary commits and refuses to run.'
    exit 2
}
if (-not (Test-Path $plainExe)) { Write-Host ('FATAL: missing ' + $plainExe); exit 2 }
if (-not (Test-Path $monoExe)) { Write-Host ('FATAL: missing ' + $monoExe); exit 2 }

# -----------------------------------------------------------------------------
#  Scenario 4 first (the state the two binaries are in right now)
# -----------------------------------------------------------------------------
foreach ($pair in @(@{ name = 'plain'; exe = $plainExe }, @{ name = 'mono'; exe = $monoExe })) {
    $versionText = ((& $pair.exe --version 2>$null) -join ' ').Trim()
    $v = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $versionText -HeadSha $head0Short
    Check -Id ('S4_' + $pair.name + '_rebuilt_onto_HEAD_is_ANCHOR_EQUAL') `
        -Pass (($v.Verdict -ceq 'ANCHOR_EQUAL') -and ($v.Ok -eq $true)) `
        -Evidence ("--version='{0}' :: {1}" -f $versionText, $v.Summary)
}
Write-Host ''

$restored = $false
$restoreNotes = @()
$tempDocsCommit = ''
$tempCppCommit = ''
try {
    # -------------------------------------------------------------------------
    #  Scenario 1 -- an .md-only change, no rebuild
    # -------------------------------------------------------------------------
    Write-Host '--- scenario 1: an .md-only commit, no rebuild --------------------'
    Add-Content -LiteralPath (Join-Path $RepoRoot $docsFile) -Value '' -Encoding ASCII
    Add-Content -LiteralPath (Join-Path $RepoRoot $docsFile) -Value '<!-- TASK-072 counterexample probe: this line exists only inside a temporary commit -->' -Encoding ASCII
    $null = Invoke-ProbeGit -GitArgs @('add', '--', $docsFile)
    $null = Invoke-ProbeGit -GitArgs @('commit', '--no-verify', '-q', '-m', 'TASK-072 probe: docs only (temporary, removed by the probe)')
    $tempDocsCommit = (([string]((Invoke-ProbeGit -GitArgs @('rev-parse', 'HEAD')).Lines[0])) -join '').Trim()
    Write-Host ("temporary commit: {0}" -f $tempDocsCommit.Substring(0, 9))
    $v1 = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText ((& $plainExe --version 2>$null) -join ' ').Trim() -HeadSha $tempDocsCommit
    $v1m = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText ((& $monoExe --version 2>$null) -join ' ').Trim() -HeadSha $tempDocsCommit
    Check -Id 'S1_docs_only_commit_keeps_the_plain_anchor_STRUCTURAL_EQUIVALENT' `
        -Pass (($v1.Verdict -ceq 'ANCHOR_STRUCTURAL_EQUIVALENT') -and ($v1.Ok -eq $true) -and (@($v1.SafeFiles) -contains $docsFile) -and ($v1.RedCount -eq 0)) `
        -Evidence $v1.Summary
    Check -Id 'S1_docs_only_commit_keeps_the_mono_anchor_STRUCTURAL_EQUIVALENT' `
        -Pass (($v1m.Verdict -ceq 'ANCHOR_STRUCTURAL_EQUIVALENT') -and ($v1m.Ok -eq $true) -and (@($v1m.SafeFiles) -contains $docsFile) -and ($v1m.RedCount -eq 0)) `
        -Evidence $v1m.Summary
    Write-Host ''

    # -------------------------------------------------------------------------
    #  Scenario 2 -- a .cpp change, no rebuild
    # -------------------------------------------------------------------------
    Write-Host '--- scenario 2: a .cpp commit, no rebuild ------------------------'
    $null = Invoke-ProbeGit -GitArgs @('reset', '--hard', $head0)
    Add-Content -LiteralPath (Join-Path $RepoRoot $cppFile) -Value '' -Encoding ASCII
    Add-Content -LiteralPath (Join-Path $RepoRoot $cppFile) -Value '// TASK-072 counterexample probe: this line exists only inside a temporary commit' -Encoding ASCII
    $null = Invoke-ProbeGit -GitArgs @('add', '--', $cppFile)
    $null = Invoke-ProbeGit -GitArgs @('commit', '--no-verify', '-q', '-m', 'TASK-072 probe: a compile input (temporary, removed by the probe)')
    $tempCppCommit = (([string]((Invoke-ProbeGit -GitArgs @('rev-parse', 'HEAD')).Lines[0])) -join '').Trim()
    Write-Host ("temporary commit: {0}" -f $tempCppCommit.Substring(0, 9))
    $v2 = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText ((& $plainExe --version 2>$null) -join ' ').Trim() -HeadSha $tempCppCommit
    $v2m = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText ((& $monoExe --version 2>$null) -join ' ').Trim() -HeadSha $tempCppCommit
    $v2reds = @($v2.RedFiles | ForEach-Object { $_.Path })
    Check -Id 'S2_cpp_commit_makes_the_plain_anchor_STALE_COMPILED' `
        -Pass (($v2.Verdict -ceq 'ANCHOR_STALE_COMPILED') -and ($v2.Ok -eq $false) -and ($v2reds -contains $cppFile)) `
        -Evidence $v2.Summary
    Check -Id 'S2_cpp_commit_makes_the_mono_anchor_STALE_COMPILED' `
        -Pass (($v2m.Verdict -ceq 'ANCHOR_STALE_COMPILED') -and ($v2m.Ok -eq $false)) `
        -Evidence $v2m.Summary
    Write-Host ''

    # -------------------------------------------------------------------------
    #  Scenario 3 -- an anchor outside HEAD's history
    # -------------------------------------------------------------------------
    Write-Host '--- scenario 3: an anchor that is not an ancestor ----------------'
    $null = Invoke-ProbeGit -GitArgs @('reset', '--hard', $head0)
    # $tempCppCommit still resolves in the object database (it is only
    # unreachable), so this is a real commit that HEAD no longer contains -
    # exactly the branch-switch / rebase shape the criterion must reject.
    $v3 = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -Anchor $tempCppCommit -HeadSha $head0
    Check -Id 'S3_a_real_commit_outside_HEAD_history_is_ANCHOR_NOT_ANCESTOR' `
        -Pass (($v3.Verdict -ceq 'ANCHOR_NOT_ANCESTOR') -and ($v3.Ok -eq $false) -and ($v3.Ancestor -eq $false)) `
        -Evidence $v3.Summary
    $v3b = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText '4.8.dev.custom_build.deadbeefc' -HeadSha $head0
    Check -Id 'S3_a_forged_anchor_in_the_version_line_is_ANCHOR_NOT_ANCESTOR' `
        -Pass (($v3b.Verdict -ceq 'ANCHOR_NOT_ANCESTOR') -and ($v3b.Ok -eq $false) -and ($v3b.Anchor -ceq 'deadbeefc')) `
        -Evidence $v3b.Summary
    Write-Host ''

    # -------------------------------------------------------------------------
    #  Scenario 1b -- the same docs-only situation judged by the CLI entry point
    #  (proves the command mode and the library mode agree)
    # -------------------------------------------------------------------------
    Write-Host '--- scenario 1b: the command-line entry point of the same judge ----'
    $null = Invoke-ProbeGit -GitArgs @('reset', '--hard', $head0)
    Add-Content -LiteralPath (Join-Path $RepoRoot $docsFile) -Value '<!-- TASK-072 counterexample probe: CLI run -->' -Encoding ASCII
    $null = Invoke-ProbeGit -GitArgs @('add', '--', $docsFile)
    $null = Invoke-ProbeGit -GitArgs @('commit', '--no-verify', '-q', '-m', 'TASK-072 probe: docs only, CLI (temporary, removed by the probe)')
    $tempDocsCommit2 = (([string]((Invoke-ProbeGit -GitArgs @('rev-parse', 'HEAD')).Lines[0])) -join '').Trim()
    $cliOut = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_engine_anchor.ps1') -VersionText ((& $plainExe --version 2>$null) -join ' ').Trim() -HeadSha $tempDocsCommit2 2>$null)
    $cliCode = [int]$LASTEXITCODE
    $cliText = ($cliOut -join "`n")
    Check -Id 'S1b_cli_and_library_modes_agree_on_STRUCTURAL_EQUIVALENT' `
        -Pass (($cliCode -eq 0) -and ($cliText -match 'ANCHOR_JUDGE VERDICT=ANCHOR_STRUCTURAL_EQUIVALENT') -and ($cliText -match 'ANCHOR_JUDGE RESULT PASS')) `
        -Evidence ("exit={0}" -f $cliCode)
    Write-Host '--- the CLI output, verbatim ---'
    foreach ($line in $cliOut) { Write-Host $line }
} finally {
    Write-Host ''
    Write-Host '--- restoring the repository --------------------------------------'
    $reset = Invoke-ProbeGit -GitArgs @('reset', '--hard', $head0) -AllowFailure
    $restoreNotes += ('reset --hard {0}: exit {1}' -f $head0Short, $reset.ExitCode)
    $porcelainAfterReset = Get-ProbePorcelain
    $docsShaAfter = Get-ProbeSha256 -Relative $docsFile
    $cppShaAfter = Get-ProbeSha256 -Relative $cppFile
    $headAfter = (([string]((Invoke-ProbeGit -GitArgs @('rev-parse', 'HEAD')).Lines[0])) -join '').Trim()
    $restored = (($reset.ExitCode -eq 0) -and ($headAfter -ceq $head0) -and ($porcelainAfterReset.Trim().Length -eq 0) -and `
        ($docsShaAfter -ceq $docsSha0) -and ($cppShaAfter -ceq $cppSha0))
    foreach ($n in $restoreNotes) { Write-Host ('  ' + $n) }
    Write-Host ("  HEAD now        : {0}" -f $headAfter)
    Write-Host ("  porcelain -uno  : {0}" -f $(if ($porcelainAfterReset.Trim().Length -eq 0) { '<clean>' } else { $porcelainAfterReset }))
    Write-Host ("  docs sha256     : {0} (was {1})" -f $docsShaAfter, $docsSha0)
    Write-Host ("  cpp  sha256     : {0} (was {1})" -f $cppShaAfter, $cppSha0)
}

Check -Id 'S0_the_probe_put_the_repository_back' -Pass $restored `
    -Evidence ('HEAD={0} porcelain_clean={1} docs_sha_unchanged={2} cpp_sha_unchanged={3}' -f `
        $head0Short, ($porcelainAfterReset.Trim().Length -eq 0), ($docsShaAfter -ceq $docsSha0), ($cppShaAfter -ceq $cppSha0))

$endedUtc = (Get-Date).ToUniversalTime()
Write-Host ''
Write-Host ("END             : {0}" -f $endedUtc.ToString('yyyy-MM-dd HH:mm:ss'))
Write-Host ("elapsed         : {0:N1} s" -f (($endedUtc - $startedUtc).TotalSeconds))
Write-Host ("checks={0} failures={1}" -f $script:Checks, $script:Failures)
if (-not $restored) {
    Write-Host 'TASK-072 COUNTEREXAMPLE PROBE COULD NOT RESTORE THE REPOSITORY'
    exit 3
}
if ($script:Failures -gt 0) {
    Write-Host 'TASK-072 COUNTEREXAMPLE PROBE FAILED'
    exit 1
}
Write-Host 'TASK-072 COUNTEREXAMPLE PROBE PASS (docs-only passes, a compile input fails, a foreign anchor fails, the rebuilt binaries are equal)'
exit 0
