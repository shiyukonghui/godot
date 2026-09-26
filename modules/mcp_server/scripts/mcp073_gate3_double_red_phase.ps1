# =============================================================================
#  mcp073_gate3_double_red_phase.ps1 -- TASK-073 A, evidence item 3: the RED
#  phase of the double-precision gate variant, constructed on purpose.
#
#  WHY THIS EXISTS
#  ---------------
#  F-1 (TASK-071 B) made seven module doctest cases build-configuration
#  independent: they used to assert, unconditionally, that a scalar `real_t`
#  member or a `Vector2/Rect2/Vector4/Quaternion` component REFUSES `1e300`.
#  That is true when `real_t` is a `float` and false when it is a `double`, so on
#  a `precision=double` build those seven cases failed. TASK-071 measured the red
#  phase (345 cases = 338 passed + 7 failed; 23961 assertions = 23862 passed +
#  99 failed) on a binary built from the pre-F-1 test file at revision
#  `4512d14c7e`, and then fixed the tests.
#
#  A gate variant whose red phase has never been observed is not a gate. This
#  script re-creates exactly that state, on demand, without leaving anything
#  behind:
#
#    1. it refuses to start unless `modules/mcp_server/tests/test_mcp_server.h`
#       is byte-for-byte the committed HEAD version (so it cannot destroy work);
#    2. it writes the PRE-F-1 blob of that one file (`git show <rev>:<path>`
#       captured as RAW BYTES) over the working copy and verifies the working
#       copy now hashes to that blob (`git hash-object` == `git rev-parse`);
#    3. it builds the double binary and runs the gate 3 case set: the run MUST be
#       RED, with the known shape (7 failing cases, no failing assertion naming
#       FLOAT32, no failing case outside the `real_t`-width classes) and the same
#       totals the TASK-071 evidence recorded. The raw engine output is kept
#       verbatim;
#    4. it restores the file from git, verifies the sha256 is the one it started
#       with, rebuilds the double binary and runs the same case set: now it MUST
#       be GREEN (345/345, 0 failed assertions) with the totals the TASK-071
#       green evidence recorded;
#    5. `finally` restores the file if anything above threw, and the final state
#       (sha256, `git status --porcelain` for that path, HEAD) is asserted.
#
#  `4512d14c7e` is the only revision whose test file has to be replayed: the diff
#  `4512d14c7e..HEAD` contains exactly ONE compile input, this test file, so
#  restoring it alone reproduces the pre-F-1 binary.
#
#  USAGE
#  -----
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp073_gate3_double_red_phase.ps1
#    ... -EvidenceDir <absolute dir>   # keep the red/green artifacts there
#    ... -PreFixRevision <sha>         # default 4512d14c7e
#    ... -AllowConcurrentBuild
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$RepoRoot = '',
    [string]$LogRoot = '',
    [string]$EvidenceDir = '',
    [string]$PreFixRevision = '4512d14c7e',
    [int]$ExpectRedCases = 7,
    [switch]$AllowConcurrentBuild
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
} else {
    $RepoRoot = (Resolve-Path $RepoRoot).Path
}
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = Join-Path $env:TEMP ('mcp073\gate3-double-red\' + $Stamp)
}
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$LogRoot = (Resolve-Path $LogRoot).Path
if ([string]::IsNullOrWhiteSpace($EvidenceDir)) {
    $EvidenceDir = $LogRoot
} else {
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
    $EvidenceDir = (Resolve-Path $EvidenceDir).Path
}

$RelPath = 'modules/mcp_server/tests/test_mcp_server.h'
$TestPath = Join-Path $RepoRoot ($RelPath -replace '/', '\')
$DoubleExe = Join-Path $RepoRoot 'bin\godot.windows.editor.double.x86_64.console.exe'
$CaseSet = '[MCPServer]*'
$HistoricalRed = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task071\doctest_module_double_RED.txt'
$HistoricalGreen = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task071\doctest_module_double_GREEN.txt'

. (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')

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

function Get-Sha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '<missing>' }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
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
    return [pscustomobject]@{ code = $code; text = (($out -join "`n").Trim()) }
}

# The blob's RAW bytes, not a re-encoded string: `git show` is captured through
# the child process's standard output stream, so line endings and any byte the
# file happens to contain survive the round trip.
function Get-GitBlobBytes {
    param([string]$Revision, [string]$Rel)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = ('-C "{0}" show {1}:{2}' -f $RepoRoot, $Revision, $Rel)
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $ms = New-Object System.IO.MemoryStream
    $proc.StandardOutput.BaseStream.CopyTo($ms)
    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) {
        throw ('git show {0}:{1} failed (exit {2}): {3}' -f $Revision, $Rel, $proc.ExitCode, $err.Trim())
    }
    return $ms.ToArray()
}

function Restore-TestFile {
    $call = Get-GitText @('checkout', 'HEAD', '--', $RelPath)
    return ($call.code -eq 0)
}

function Test-TestFileClean {
    $call = Get-GitText @('status', '--porcelain', '--', $RelPath)
    return [string]::IsNullOrWhiteSpace($call.text)
}

function Invoke-Engine {
    param([string]$Engine, [string]$Tag)
    $log = Join-Path $LogRoot ($Tag + '.doctest.txt')
    $start = Get-Date
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $RepoRoot
    try {
        & $Engine '--headless' '--test' ('--test-case=' + $CaseSet) *> $log
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
        $ErrorActionPreference = $old
    }
    $end = Get-Date
    $text = ''
    if (Test-Path -LiteralPath $log) { $text = [IO.File]::ReadAllText($log) }
    return [pscustomobject]@{ exit = $code; log = $log; text = $text; seconds = [math]::Round(($end - $start).TotalSeconds, 1) }
}

function Get-DoctestTotals {
    param([string]$Text)
    $cases = -1; $casesPassed = -1; $casesFailed = -1
    $assertions = -1; $assertionsPassed = -1; $assertionsFailed = -1
    if ($Text -match 'test cases:\s*(\d+)\s*\|\s*(\d+)\s*passed\s*\|\s*(\d+)\s*failed') {
        $cases = [int]$Matches[1]; $casesPassed = [int]$Matches[2]; $casesFailed = [int]$Matches[3]
    }
    if ($Text -match 'assertions:\s*(\d+)\s*\|\s*(\d+)\s*passed\s*\|\s*(\d+)\s*failed') {
        $assertions = [int]$Matches[1]; $assertionsPassed = [int]$Matches[2]; $assertionsFailed = [int]$Matches[3]
    }
    return [pscustomobject]@{
        cases = $cases; casesPassed = $casesPassed; casesFailed = $casesFailed
        assertions = $assertions; assertionsPassed = $assertionsPassed; assertionsFailed = $assertionsFailed
        totalsText = ((@($Text -split "`n") | Where-Object { $_ -match '\[doctest\] (test cases|assertions):' }) -join ' ;; ')
    }
}

function Invoke-Build {
    $env:MCP_BUILD_LOG = Join-Path $LogRoot 'mcp070_build_double.log'
    $start = Get-Date
    Push-Location $RepoRoot
    try {
        & cmd /c 'modules\mcp_server\scripts\mcp070_build_double.cmd'
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $end = Get-Date
    return [pscustomobject]@{ exit = $code; seconds = [math]::Round(($end - $start).TotalSeconds, 1); log = $env:MCP_BUILD_LOG }
}

Write-Host '============================================================='
Write-Host ' TASK-073 A: gate 3 double variant -- the RED phase, constructed'
Write-Host (' repo        : ' + $RepoRoot)
Write-Host (' file        : ' + $TestPath)
Write-Host (' pre-F-1 rev : ' + $PreFixRevision)
Write-Host (' logs        : ' + $LogRoot)
Write-Host (' evidence    : ' + $EvidenceDir)
Write-Host '============================================================='

$head = (Get-GitText @('rev-parse', '--short=9', 'HEAD')).text
$headFull = (Get-GitText @('rev-parse', 'HEAD')).text
Write-Host ('git HEAD        : ' + $head)

$shaBefore = Get-Sha256 $TestPath
$headBlob = (Get-GitText @('rev-parse', ('HEAD:' + $RelPath))).text
$preBlob = (Get-GitText @('rev-parse', ($PreFixRevision + ':' + $RelPath))).text
$fileCleanAtStart = Test-TestFileClean

Check 'g3r_test_file_is_the_committed_head_version_at_start' $fileCleanAtStart `
    ('git status --porcelain for {0} is empty = {1}; sha256={2}; HEAD blob={3}. The script refuses to run otherwise, so it can never overwrite uncommitted work in this file.' -f $RelPath, $fileCleanAtStart, $shaBefore, $headBlob)
if (-not $fileCleanAtStart) {
    Write-Host 'REFUSING: the test file has uncommitted changes; commit or revert them first.'
    exit 2
}
Check 'g3r_the_pre_f1_blob_is_a_different_blob' (($preBlob.Length -gt 0) -and ($preBlob -ne $headBlob)) `
    ('pre-F-1 blob={0}; HEAD blob={1} (the two differ, so replaying the old file really does recreate the pre-F-1 state)' -f $preBlob, $headBlob)

$blockers = @()
if (-not $AllowConcurrentBuild) { $blockers = @(Get-Process -Name scons -ErrorAction SilentlyContinue) }
if ($blockers.Count -gt 0) {
    Write-Host ('REFUSING TO BUILD: {0} scons process(es) alive (D62).' -f $blockers.Count)
    exit 4
}
Check 'g3r_build_is_serial_no_other_scons_alive' $true `
    ('scons processes alive at start = {0}; every build below is therefore serial with respect to other builds (D62)' -f $blockers.Count)

$script:Restored = $false
$redRun = $null
$redTotals = $null
$greenRun = $null
$greenTotals = $null
$redBuild = $null
$greenBuild = $null
$script:Errors = @()
$code = 0

try {
    # --- 1. write the pre-F-1 file ------------------------------------------
    $bytes = Get-GitBlobBytes -Revision $PreFixRevision -Rel $RelPath
    [IO.File]::WriteAllBytes($TestPath, $bytes)
    $writtenBlob = (Get-GitText @('hash-object', $TestPath)).text
    Check 'g3r_working_file_now_hashes_to_the_pre_f1_blob' ($writtenBlob -eq $preBlob) `
        ('git hash-object({0}) = {1}; git rev-parse({2}:{3}) = {4}; bytes written = {5}' -f $RelPath, $writtenBlob, $PreFixRevision, $RelPath, $preBlob, $bytes.Length)

    # --- 2. build and run: the run MUST be red ------------------------------
    $redBuild = Invoke-Build
    Write-Host ('red build : exit={0} seconds={1} log={2}' -f $redBuild.exit, $redBuild.seconds, $redBuild.log)
    $redRun = Invoke-Engine -Engine $DoubleExe -Tag 'gate3_double_RED'
    $redTotals = Get-DoctestTotals -Text $redRun.text
    $redRaw = Join-Path $EvidenceDir 'gate3_double_red_phase_RED.txt'
    [IO.File]::WriteAllBytes($redRaw, [IO.File]::ReadAllBytes($redRun.log))
    Write-Host ('red run   : exit={0} case-set totals: {1}' -f $redRun.exit, $redTotals.totalsText)

    $redLines = @($redRun.text -split "`n")
    $failingCases = @($redLines | Where-Object { $_ -match '^TEST CASE:\s+(.*\S)\s*$' } | ForEach-Object { ($_ -replace '^TEST CASE:\s+', '').Trim() } | Sort-Object -Unique)
    $float32ErrorLines = @($redLines | Where-Object { $_ -match 'ERROR:' -and $_ -match 'FLOAT32' })
    $realTErrorLines = @($redLines | Where-Object { $_ -match 'ERROR:' -and $_ -match 'REAL_T' })
    $knownClasses = @('TASK-022', 'TASK-025 E-3', 'TASK-028 G-1', 'TASK-033')
    $offClass = @($failingCases | Where-Object {
            $name = $_
            $known = $false
            foreach ($k in $knownClasses) { if ($name.Contains($k)) { $known = $true } }
            -not $known
        })
    $failingCaseList = Join-Path $EvidenceDir 'gate3_double_red_phase_failing_cases.txt'
    [IO.File]::WriteAllLines($failingCaseList, @(
            ('pre-F-1 revision = ' + $PreFixRevision),
            ('file = ' + $RelPath),
            ('file blob = ' + $preBlob),
            ('cases failed = ' + $redTotals.casesFailed),
            ('assertions failed = ' + $redTotals.assertionsFailed),
            ('failing case names (' + $failingCases.Count + '):'),
            ($failingCases | ForEach-Object { '  ' + $_ }),
            ('ERROR lines naming FLOAT32 = ' + $float32ErrorLines.Count),
            ('ERROR lines naming REAL_T = ' + $realTErrorLines.Count),
            ('failing cases outside the real_t-width classes = ' + $offClass.Count)
        ))

    Check 'g3r_red_run_really_is_red' (($redTotals.casesFailed -gt 0) -and ($redTotals.assertionsFailed -gt 0)) `
        ('the pre-F-1 test file on the double binary: {0}; cases failed={1} assertions failed={2} (a green run here would mean the demonstration proves nothing)' -f $redTotals.totalsText, $redTotals.casesFailed, $redTotals.assertionsFailed)
    Check 'g3r_red_run_has_exactly_the_known_f1_case_set' (($redTotals.casesFailed -eq $ExpectRedCases) -and ($failingCases.Count -eq $ExpectRedCases)) `
        ('cases failed={0}; distinct failing case names={1}; expected={2}; the names are in {3}' -f $redTotals.casesFailed, $failingCases.Count, $ExpectRedCases, $failingCaseList)
    Check 'g3r_no_red_assertion_names_float32_and_none_is_off_class' (($float32ErrorLines.Count -eq 0) -and ($offClass.Count -eq 0)) `
        ('ERROR lines naming FLOAT32 = {0} (must be 0: the FLOAT32 slot is unconditional, D-15); naming REAL_T = {1}; failing cases outside the real_t-width classes = {2} (must be 0)' -f $float32ErrorLines.Count, $realTErrorLines.Count, $offClass.Count)

    # the recorded TASK-071 evidence is the oracle, read from the repo
    $histRedText = ''
    if (Test-Path -LiteralPath $HistoricalRed) { $histRedText = [IO.File]::ReadAllText($HistoricalRed) }
    $histRed = Get-DoctestTotals -Text $histRedText
    Check 'g3r_red_totals_match_the_recorded_pre_f1_evidence' (($histRed.cases -eq $redTotals.cases) -and ($histRed.casesFailed -eq $redTotals.casesFailed) -and ($histRed.assertions -eq $redTotals.assertions) -and ($histRed.assertionsFailed -eq $redTotals.assertionsFailed)) `
        ('replayed: cases={0} failed={1} assertions={2} failed={3} || recorded in {4}: cases={5} failed={6} assertions={7} failed={8}' -f $redTotals.cases, $redTotals.casesFailed, $redTotals.assertions, $redTotals.assertionsFailed, $HistoricalRed, $histRed.cases, $histRed.casesFailed, $histRed.assertions, $histRed.assertionsFailed)

    # --- 3. restore the file and verify -------------------------------------
    $restoreOk = Restore-TestFile
    $script:Restored = $true
    $shaRestored = Get-Sha256 $TestPath
    $restoredBlob = (Get-GitText @('hash-object', $TestPath)).text
    Check 'g3r_test_file_restored_byte_identical' (($restoreOk) -and ($shaRestored -eq $shaBefore) -and ($restoredBlob -eq $headBlob) -and (Test-TestFileClean)) `
        ('git checkout HEAD restored the file: sha256={0} (started {1}); git hash-object={2} (= HEAD blob {3}); git status --porcelain empty={4}' -f $shaRestored, $shaBefore, $restoredBlob, $headBlob, (Test-TestFileClean))

    # --- 4. rebuild and run: now it MUST be green ---------------------------
    $greenBuild = Invoke-Build
    Write-Host ('green build: exit={0} seconds={1} log={2}' -f $greenBuild.exit, $greenBuild.seconds, $greenBuild.log)
    $greenRun = Invoke-Engine -Engine $DoubleExe -Tag 'gate3_double_GREEN'
    $greenTotals = Get-DoctestTotals -Text $greenRun.text
    Write-Host ('green run : exit={0} case-set totals: {1}' -f $greenRun.exit, $greenTotals.totalsText)
    Check 'g3r_green_run_is_green' (($greenRun.exit -eq 0) -and ($greenTotals.casesFailed -eq 0) -and ($greenTotals.assertionsFailed -eq 0) -and ($greenTotals.cases -gt 0)) `
        ('after restoring the file: {0}; exit={1}; cases passed={2}/{3}; assertions passed={4}/{5}' -f $greenTotals.totalsText, $greenRun.exit, $greenTotals.casesPassed, $greenTotals.cases, $greenTotals.assertionsPassed, $greenTotals.assertions)

    $histGreenText = ''
    if (Test-Path -LiteralPath $HistoricalGreen) { $histGreenText = [IO.File]::ReadAllText($HistoricalGreen) }
    $histGreen = Get-DoctestTotals -Text $histGreenText
    Check 'g3r_green_totals_match_the_recorded_green_evidence' (($histGreen.cases -eq $greenTotals.cases) -and ($histGreen.assertions -eq $greenTotals.assertions)) `
        ('rebuilt: cases={0} assertions={1} || recorded in {2}: cases={3} assertions={4}' -f $greenTotals.cases, $greenTotals.assertions, $HistoricalGreen, $histGreen.cases, $histGreen.assertions)

    # --- 5. the anchor of the green binary ----------------------------------
    $greenVersion = ((& $DoubleExe --version 2>$null) -join ' ').Trim()
    $anchorVerdict = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $greenVersion -HeadSha $head
    Check 'g3r_green_binary_anchor_passes' ($anchorVerdict.Ok) `
        (('--version=''{0}''; verdict={1} ok={2}; ' -f $greenVersion, $anchorVerdict.Verdict, $anchorVerdict.Ok) + $anchorVerdict.Summary)

    if ($script:Failures -gt 0) { $code = 1 } else { $code = 0 }
} catch {
    $script:Errors += $_.Exception.Message
    Write-Host ('EXCEPTION: ' + $_.Exception.Message)
    $code = 1
} finally {
    if (-not $script:Restored) {
        Write-Host 'finally: restoring the test file.'
        $ok = Restore-TestFile
        Write-Host ('finally: restore ok = ' + $ok)
    }
}

# ---------------------------------------------------------------------------
#  final state, always checked outside the finally above
# ---------------------------------------------------------------------------
$shaFinal = Get-Sha256 $TestPath
$finalBlob = (Get-GitText @('hash-object', $TestPath)).text
$finalClean = Test-TestFileClean
Check 'g3r_final_state_is_untouched' (($shaFinal -eq $shaBefore) -and ($finalBlob -eq $headBlob) -and $finalClean) `
    ('file sha256={0} (started {1}); blob={2} (= HEAD {3}); porcelain empty={4}; HEAD={5}' -f $shaFinal, $shaBefore, $finalBlob, $headBlob, $finalClean, $headFull)

if ($script:Failures -gt 0) { $code = 1 }

$redText = if ($null -ne $redTotals) { ('cases={0} passed={1} failed={2}; assertions={3} passed={4} failed={5}' -f $redTotals.cases, $redTotals.casesPassed, $redTotals.casesFailed, $redTotals.assertions, $redTotals.assertionsPassed, $redTotals.assertionsFailed) } else { '<not measured>' }
$greenText = if ($null -ne $greenTotals) { ('cases={0} passed={1} failed={2}; assertions={3} passed={4} failed={5}' -f $greenTotals.cases, $greenTotals.casesPassed, $greenTotals.casesFailed, $greenTotals.assertions, $greenTotals.assertionsPassed, $greenTotals.assertionsFailed) } else { '<not measured>' }
$verdict = if ($code -eq 0) { 'PASS' } else { 'FAIL' }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('TASK-073 A -- gate 3 double variant: the pre-F-1 RED phase, replayed')
$lines.Add('stamp            = ' + $Stamp)
$lines.Add('repo             = ' + $RepoRoot)
$lines.Add('git HEAD         = ' + $head)
$lines.Add('file             = ' + $TestPath)
$lines.Add('file sha256      = ' + $shaBefore + ' (final ' + $shaFinal + ')')
$lines.Add('pre-F-1 revision = ' + $PreFixRevision + ' (blob ' + $preBlob + ')')
$lines.Add('HEAD blob        = ' + $headBlob)
$lines.Add('red build        = exit ' + $(if ($null -ne $redBuild) { $redBuild.exit } else { '<none>' }) + ' seconds ' + $(if ($null -ne $redBuild) { $redBuild.seconds } else { '<none>' }))
$lines.Add('red run          = ' + $redText)
$lines.Add('red raw output   = ' + (Join-Path $EvidenceDir 'gate3_double_red_phase_RED.txt'))
$lines.Add('green build      = exit ' + $(if ($null -ne $greenBuild) { $greenBuild.exit } else { '<none>' }) + ' seconds ' + $(if ($null -ne $greenBuild) { $greenBuild.seconds } else { '<none>' }))
$lines.Add('green run        = ' + $greenText)
$lines.Add('checks           = ' + $script:Rows.Count + ' failures ' + $script:Failures)
$lines.Add('exceptions       = ' + $(if ($script:Errors.Count -gt 0) { ($script:Errors -join ' | ') } else { '<none>' }))
$lines.Add('verdict          = ' + $verdict)
$lines.Add('')
foreach ($row in $script:Rows) { $lines.Add($row) }
$summaryPath = Join-Path $EvidenceDir 'gate3_double_red_phase_summary.txt'
[IO.File]::WriteAllLines($summaryPath, $lines.ToArray())

Write-Host ''
Write-Host '--- gate 3 double variant red phase ---'
Write-Host ('  red run   : ' + $redText)
Write-Host ('  green run : ' + $greenText)
Write-Host ('  raw red   : ' + (Join-Path $EvidenceDir 'gate3_double_red_phase_RED.txt'))
Write-Host ('  summary   : ' + $summaryPath)
Write-Host ('  checks    : {0} failures {1}' -f $script:Rows.Count, $script:Failures)
Write-Host ('GATE3_DOUBLE_RED_PHASE RESULT={0} red_cases_failed={1} red_assertions_failed={2} green_cases={3} green_failed={4}' -f $verdict, `
        $(if ($null -ne $redTotals) { $redTotals.casesFailed } else { -1 }), `
        $(if ($null -ne $redTotals) { $redTotals.assertionsFailed } else { -1 }), `
        $(if ($null -ne $greenTotals) { $greenTotals.cases } else { -1 }), `
        $(if ($null -ne $greenTotals) { $greenTotals.casesFailed } else { -1 }))
if ($script:Failures -gt 0) {
    Write-Host ('GATE 3 DOUBLE RED PHASE FAILED: {0}' -f $script:Failures)
    exit 1
}
Write-Host 'GATE 3 DOUBLE RED PHASE PASS'
exit 0
