# =============================================================================
#  mcp073_gate3_double.ps1 -- TASK-073 A: gate 3's OPTIONAL precision=double
#  variant.
#
#  WHAT THIS IS
#  ------------
#  Gate 3 is the module doctest case set, `--headless --test --test-case=
#  "[MCPServer]*"`. It runs `bin\godot.windows.editor.x86_64.console.exe`, i.e.
#  `precision` at its default (`float`), so gate 3 IS a single-precision gate.
#  TASK-071 declared that in writing (REPORT-071 section B.4) and left
#  `precision=double` covered by NO gate. This script is that missing variant,
#  and it is OPT-IN: the gate battery `mcp059_gates.ps1` calls it ONLY when the
#  caller passes an explicit switch (`-PrecisionVariant double` / `-WithDouble`).
#  Without the switch nothing here runs, no build starts, and the default wall
#  clock of the battery is unchanged.
#
#  WHAT IT DOES, IN ORDER (every step is measured, none of it is assumed)
#  ---------------------------------------------------------------------
#    1. refuse to start while another scons is alive. D62: two concurrent scons
#       runs rewrite `modules/modules_tests.gen.h` and manufacture a batch of
#       compile errors that have nothing to do with the tree. The build of this
#       variant is therefore serial by construction, not by remembering. The
#       `-AllowConcurrentBuild` switch overrides the refusal and says so.
#    2. BUILD the double binary by reusing `scripts\mcp070_build_double.cmd`
#       (`tests=yes` is mandatory; the executable is
#       `bin\godot.windows.editor.double.x86_64[.console].exe` and it owns its
#       own PROGSUFFIX/OBJSUFFIX, so the plain and mono binaries are not
#       relinked). START/END/EXIT are read out of that script's own log.
#    3. judge the built binary's anchor with TASK-072's ONE criterion,
#       `scripts\check_engine_anchor.ps1`. ANCHOR_EQUAL and
#       ANCHOR_STRUCTURAL_EQUIVALENT pass; ANCHOR_STALE_COMPILED and
#       ANCHOR_NOT_ANCESTOR are RED. The whole verdict line is printed.
#    4. run the very same case set gate 3 runs, on the double binary, and require
#       it GREEN: 0 failed cases, 0 failed assertions, and at least -ExpectCases
#       cases (default 345; the check is `>=` so a later batch may ADD tests).
#    5. unless `-SkipSingleControl`, run the same case set on the ordinary binary
#       as well, so the pair (single, double) is measured in one run. The gate
#       battery passes `-SkipSingleControl` because it already runs that step.
#
#  NOTHING IS RELAXED FOR THE VARIANT: the case set is gate 3's own case set, the
#  binary is the double build of the same tree, and a red doctest, a stale
#  anchor, a missing binary or a failed build all exit non-zero.
#
#  USAGE
#  -----
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp073_gate3_double.ps1
#    ... -EvidenceDir <absolute dir>   # keep the artifacts there as well
#    ... -SkipBuild                    # re-judge the binary that is already on
#                                      # disk (does NOT satisfy the serial build
#                                      # requirement by itself)
#    ... -SkipSingleControl
#    ... -AllowConcurrentBuild
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$RepoRoot = '',
    [string]$LogRoot = '',
    [string]$EvidenceDir = '',
    [switch]$SkipBuild,
    [switch]$SkipSingleControl,
    [switch]$AllowConcurrentBuild,
    [int]$ExpectCases = 345
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
} else {
    $RepoRoot = (Resolve-Path $RepoRoot).Path
}
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = Join-Path $env:TEMP ('mcp073\gate3-double\' + $Stamp)
}
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$LogRoot = (Resolve-Path $LogRoot).Path
if ([string]::IsNullOrWhiteSpace($EvidenceDir)) {
    $EvidenceDir = $LogRoot
} else {
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
    $EvidenceDir = (Resolve-Path $EvidenceDir).Path
}

$DoubleExe = Join-Path $RepoRoot 'bin\godot.windows.editor.double.x86_64.console.exe'
$SingleExe = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$BuildCmd = Join-Path $RepoRoot 'modules\mcp_server\scripts\mcp070_build_double.cmd'
$CaseSet = '[MCPServer]*'

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

# The child's whole output goes to a file AND the file's tail is echoed, per the
# module rule that a build must not have its output suppressed.
function Invoke-Engine {
    param([string]$Engine, [string]$Tag, [string]$Case)
    $log = Join-Path $LogRoot ($Tag + '.doctest.txt')
    $arguments = @('--headless', '--test')
    if (-not [string]::IsNullOrWhiteSpace($Case)) { $arguments += ('--test-case=' + $Case) }
    $start = Get-Date
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $RepoRoot
    try {
        & $Engine @arguments *> $log
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
        $ErrorActionPreference = $old
    }
    $end = Get-Date
    $text = ''
    if (Test-Path -LiteralPath $log) {
        $text = [IO.File]::ReadAllText($log)
    }
    return [pscustomobject]@{
        exit     = $code
        log      = $log
        text     = $text
        seconds  = [math]::Round(($end - $start).TotalSeconds, 1)
    }
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
    }
}

Write-Host '============================================================='
Write-Host ' TASK-073 A: gate 3 optional variant, precision=double'
Write-Host (' repo       : ' + $RepoRoot)
Write-Host (' double exe : ' + $DoubleExe)
Write-Host (' single exe : ' + $SingleExe)
Write-Host (' case set   : ' + $CaseSet)
Write-Host (' logs       : ' + $LogRoot)
Write-Host (' evidence   : ' + $EvidenceDir)
Write-Host '============================================================='

$head = ((& git -C $RepoRoot rev-parse --short=9 HEAD) -join '').Trim()
Write-Host ('git HEAD        : ' + $head)

# ---------------------------------------------------------------------------
#  1. the serialization guard (D62)
# ---------------------------------------------------------------------------
$blockers = @()
if (-not $AllowConcurrentBuild) {
    $blockers = @(Get-Process -Name scons -ErrorAction SilentlyContinue)
}
if ($blockers.Count -gt 0) {
    Write-Host 'REFUSING TO BUILD: another scons process is alive (D62: concurrent'
    Write-Host 'scons runs rewrite modules/modules_tests.gen.h). Process ids:'
    $blockers | ForEach-Object { Write-Host ('  pid={0} name={1}' -f $_.Id, $_.ProcessName) }
    Write-Host 'Wait for it to finish, or pass -AllowConcurrentBuild to override on purpose.'
    exit 4
}
Check 'g3d_build_is_serial_no_other_scons_alive' $true `
    ('scons processes alive at start = {0} (the guard refuses a build otherwise; D62)' -f $blockers.Count)

# ---------------------------------------------------------------------------
#  2. the build, reusing the TASK-070 script
# ---------------------------------------------------------------------------
$singleShaBefore = Get-Sha256 $SingleExe
$doubleShaBefore = Get-Sha256 $DoubleExe
$buildStart = Get-Date
$buildSeconds = 0.0
$buildExit = -1
if ($SkipBuild) {
    Write-Host 'build: SKIPPED (-SkipBuild); the anchor judge below still decides the binary that is on disk.'
} else {
    $env:MCP_BUILD_LOG = Join-Path $LogRoot 'mcp070_build_double.log'
    Write-Host ('build: START {0}' -f $buildStart.ToString('s'))
    Push-Location $RepoRoot
    try {
        & cmd /c 'modules\mcp_server\scripts\mcp070_build_double.cmd'
        $buildExit = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $buildEnd = Get-Date
    $buildSeconds = [math]::Round(($buildEnd - $buildStart).TotalSeconds, 1)
    Write-Host ('build: END   {0}  exit={1}  seconds={2}' -f $buildEnd.ToString('s'), $buildExit, $buildSeconds)
    Write-Host ('build: log   {0}' -f $env:MCP_BUILD_LOG)
    if (Test-Path -LiteralPath $env:MCP_BUILD_LOG) {
        $tail = @(Get-Content -LiteralPath $env:MCP_BUILD_LOG -Tail 6)
        foreach ($line in $tail) { Write-Host ('  build-log | ' + $line) }
    }
}
$buildEvidence = if ($SkipBuild) {
    'build SKIPPED (-SkipBuild): the anchor judge below still decides the binary that is on disk, but this mode does NOT satisfy the serial-build requirement of the variant'
} else {
    ('build exit = {0}; seconds = {1}; the command is scripts\mcp070_build_double.cmd (tests=yes, precision=double; the plain and mono binaries inherit neither PROGSUFFIX nor OBJSUFFIX)' -f $buildExit, $buildSeconds)
}
Check 'g3d_build_double_exit_zero' (($SkipBuild) -or ($buildExit -eq 0)) $buildEvidence

$singleShaAfter = Get-Sha256 $SingleExe
$doubleShaAfter = Get-Sha256 $DoubleExe
Check 'g3d_build_left_the_single_precision_binary_byte_identical' ($singleShaBefore -eq $singleShaAfter) `
    ('single-precision binary sha256 before={0} after={1} (unchanged: the double build owns the .double suffix)' -f $singleShaBefore, $singleShaAfter)

# ---------------------------------------------------------------------------
#  3. the binary and its anchor (TASK-072's one criterion)
# ---------------------------------------------------------------------------
$doubleExists = Test-Path -LiteralPath $DoubleExe
$doubleVersion = ''
if ($doubleExists) {
    $doubleVersion = ((& $DoubleExe --version 2>$null) -join ' ').Trim()
}
$anchorDoubleVerdict = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $doubleVersion -HeadSha $head
Write-Host ('anchor (double): ' + $anchorDoubleVerdict.Summary)

Check 'g3d_double_binary_exists_and_is_named_double' ($doubleExists -and $doubleVersion.Contains('.double.')) `
    ("double binary: exists={0}; --version='{1}'; sha256={2} (was {3} before the build)" -f $doubleExists, $doubleVersion, $doubleShaAfter, $doubleShaBefore)
Check 'g3d_double_anchor_is_equal_or_structural_equivalent' ($anchorDoubleVerdict.Ok) `
    (('verdict={0} ok={1}; ANCHOR_EQUAL and ANCHOR_STRUCTURAL_EQUIVALENT pass, ANCHOR_STALE_COMPILED and ANCHOR_NOT_ANCESTOR are RED. ' -f $anchorDoubleVerdict.Verdict, $anchorDoubleVerdict.Ok) + $anchorDoubleVerdict.Summary)

# ---------------------------------------------------------------------------
#  4. the gate 3 case set on the double binary
# ---------------------------------------------------------------------------
$doubleRun = Invoke-Engine -Engine $DoubleExe -Tag 'gate3_double' -Case $CaseSet
$doubleTotals = Get-DoctestTotals -Text $doubleRun.text
Check 'g3d_double_doctest_exit_zero_and_no_failed_case' (($doubleRun.exit -eq 0) -and ($doubleTotals.casesFailed -eq 0) -and ($doubleTotals.cases -gt 0)) `
    ("double binary, case set '{0}': exit={1}; cases={2} passed={3} failed={4}; seconds={5}; log={6}" -f $CaseSet, $doubleRun.exit, $doubleTotals.cases, $doubleTotals.casesPassed, $doubleTotals.casesFailed, $doubleRun.seconds, $doubleRun.log)
Check 'g3d_double_doctest_no_failed_assertion' (($doubleTotals.assertionsFailed -eq 0) -and ($doubleTotals.assertions -gt 0)) `
    ('assertions: {0} | {1} passed | {2} failed (the count is written down, not compared against a frozen literal)' -f $doubleTotals.assertions, $doubleTotals.assertionsPassed, $doubleTotals.assertionsFailed)
Check 'g3d_double_doctest_case_count_not_below_the_baseline' ($doubleTotals.cases -ge $ExpectCases) `
    ('cases = {0}; baseline = {1}; the check is >= so a later batch may ADD cases, while a DROP fails here' -f $doubleTotals.cases, $ExpectCases)

# ---------------------------------------------------------------------------
#  5. the single-precision control of the same case set
# ---------------------------------------------------------------------------
$singleTotals = $null
$singleRun = $null
if ($SkipSingleControl) {
    Write-Host 'single control: SKIPPED (-SkipSingleControl; the gate battery runs that step itself).'
} else {
    $singleRun = Invoke-Engine -Engine $SingleExe -Tag 'gate3_single_control' -Case $CaseSet
    $singleTotals = Get-DoctestTotals -Text $singleRun.text
    Check 'g3d_single_control_is_green' (($singleRun.exit -eq 0) -and ($singleTotals.casesFailed -eq 0) -and ($singleTotals.assertionsFailed -eq 0) -and ($singleTotals.cases -gt 0)) `
        ("single binary, the same case set: exit={0}; cases={1}/{2}; assertions={3}/{4}; seconds={5}; log={6}" -f $singleRun.exit, $singleTotals.casesPassed, $singleTotals.cases, $singleTotals.assertionsPassed, $singleTotals.assertions, $singleRun.seconds, $singleRun.log)
}

# ---------------------------------------------------------------------------
#  the artifact
# ---------------------------------------------------------------------------
$verdict = if ($script:Failures -eq 0) { 'PASS' } else { 'FAIL' }
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('TASK-073 A -- gate 3 optional variant: precision=double')
$lines.Add('stamp           = ' + $Stamp)
$lines.Add('repo            = ' + $RepoRoot)
$lines.Add('git HEAD        = ' + $head)
$lines.Add('case set        = ' + $CaseSet)
$lines.Add('double binary   = ' + $DoubleExe)
$lines.Add('double --version= ' + $doubleVersion)
$lines.Add('double sha256   = ' + $doubleShaAfter + ' (before the build: ' + $doubleShaBefore + ')')
$lines.Add('single sha256   = ' + $singleShaAfter + ' (before the build: ' + $singleShaBefore + ')')
$lines.Add('anchor verdict  = ' + $anchorDoubleVerdict.Verdict + ' ok=' + $anchorDoubleVerdict.Ok)
$lines.Add('anchor detail   = ' + $anchorDoubleVerdict.Summary)
$lines.Add('build           = exit ' + $buildExit + ' seconds ' + $buildSeconds + ' skipped=' + $SkipBuild)
$lines.Add('double doctest  = exit ' + $doubleRun.exit + ' cases ' + $doubleTotals.cases + ' passed ' + $doubleTotals.casesPassed + ' failed ' + $doubleTotals.casesFailed + ' seconds ' + $doubleRun.seconds)
$lines.Add('double assert   = ' + $doubleTotals.assertions + ' passed ' + $doubleTotals.assertionsPassed + ' failed ' + $doubleTotals.assertionsFailed)
if ($null -ne $singleTotals) {
    $lines.Add('single doctest  = exit ' + $singleRun.exit + ' cases ' + $singleTotals.cases + ' passed ' + $singleTotals.casesPassed + ' failed ' + $singleTotals.casesFailed + ' seconds ' + $singleRun.seconds)
    $lines.Add('single assert   = ' + $singleTotals.assertions + ' passed ' + $singleTotals.assertionsPassed + ' failed ' + $singleTotals.assertionsFailed)
} else {
    $lines.Add('single doctest  = skipped (-SkipSingleControl)')
}
$lines.Add('logs            = ' + $LogRoot)
$lines.Add('evidence        = ' + $EvidenceDir)
$lines.Add('checks          = ' + $script:Rows.Count + ' failures ' + $script:Failures)
$lines.Add('verdict         = ' + $verdict)
$lines.Add('')
foreach ($row in $script:Rows) { $lines.Add($row) }
$summaryPath = Join-Path $EvidenceDir 'gate3_double_summary.txt'
[IO.File]::WriteAllLines($summaryPath, $lines.ToArray())

$resultLine = ('GATE3_DOUBLE_VARIANT RESULT={0} cases={1}/{2} assertions={3}/{4} anchor={5} build_seconds={6} doctest_seconds={7}' -f `
    $verdict, $doubleTotals.casesPassed, $doubleTotals.cases, $doubleTotals.assertionsPassed, $doubleTotals.assertions, `
    $anchorDoubleVerdict.Verdict, $buildSeconds, $doubleRun.seconds)

Write-Host ''
Write-Host '--- gate 3 double variant ---'
Write-Host ('  anchor verdict : ' + $anchorDoubleVerdict.Verdict + '  ok=' + $anchorDoubleVerdict.Ok)
Write-Host ('  build          : exit={0} seconds={1}' -f $buildExit, $buildSeconds)
Write-Host ('  double doctest : exit={0} cases={1}/{2} assertions={3}/{4} seconds={5}' -f $doubleRun.exit, $doubleTotals.casesPassed, $doubleTotals.cases, $doubleTotals.assertionsPassed, $doubleTotals.assertions, $doubleRun.seconds)
if ($null -ne $singleTotals) {
    Write-Host ('  single control : exit={0} cases={1}/{2} assertions={3}/{4} seconds={5}' -f $singleRun.exit, $singleTotals.casesPassed, $singleTotals.cases, $singleTotals.assertionsPassed, $singleTotals.assertions, $singleRun.seconds)
}
Write-Host ('  summary        : ' + $summaryPath)
Write-Host ('  checks         : {0} failures {1}' -f $script:Rows.Count, $script:Failures)
Write-Host $resultLine
if ($script:Failures -gt 0) {
    Write-Host ('GATE 3 DOUBLE VARIANT FAILED: {0}' -f $script:Failures)
    exit 1
}
Write-Host 'GATE 3 DOUBLE VARIANT PASS'
exit 0
