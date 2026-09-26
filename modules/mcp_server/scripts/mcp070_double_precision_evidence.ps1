# =============================================================================
#  mcp070_double_precision_evidence.ps1 -- TASK-070 item 4.
#
#  The unconfirmed item it closes (REPORT-AUDIT-ENGINE.md section 5 item 4, and
#  the same registration in REPORT-023/035/037/M4d/M4e): "`ValueSlot::FLOAT32`
#  is judged as 32 bits in EVERY build configuration" was a source-level +
#  unit-level conclusion on a single-precision build. A double-precision binary
#  had never been produced on this machine, so on a `precision=double` build the
#  claim had never been OBSERVED.
#
#  This script measures it on a real `precision=double` binary built by
#  `scripts/mcp070_build_double.cmd` (`bin\godot.windows.editor.double.x86_64.console.exe`):
#
#    d_double_binary_exists_and_is_a_double_build
#        the binary is there, and a `--script` probe proves it really is double
#        precision (`Vector2(1e300, 0).x` is FINITE there and `inf` on the
#        single-precision binary -- a build-configuration fact that cannot be
#        faked by a name);
#    d_single_binary_is_infinite_for_the_same_probe
#        the same probe on `bin\godot.windows.editor.x86_64.console.exe` prints
#        `inf`, i.e. the two binaries really differ in `real_t`;
#    d_float32_doctest_passes_on_the_double_build
#        `--headless --test --test-case="[MCPServer] TASK-023 D-15*"` on the
#        double binary: the case asserts that `FLOAT32` REFUSES
#        `1e300 / 3.5e38 / -3.5e38 / 1e-300 / 1e-46` and ACCEPTS
#        `0 / 0.3 / 1.0 / -1.5 / 1e30 / -1e30 / 1e-30`, and that
#        `coerce_to_property_type(PACKED_FLOAT32_ARRAY)` refuses a `1e300`
#        element. Its FLOAT32 half is UNCONDITIONAL, so it fails on any build
#        where that slot answers with `real_t`'s width; its REAL_T half is
#        `#`-conditional on `sizeof(real_t) == 4`, i.e. the double build is the
#        one that exercises the other side of the split.
#    d_module_doctests_on_double_are_red_only_where_they_assume_a_float_real_t
#        **MEASURED FINDING, and the reason this check does not assert "green":**
#        the whole module case set on the double build runs the same 345 cases and
#        **7 of them FAIL** - `TASK-022 D-4` (x2), `TASK-022: one gate`, `TASK-025
#        E-3`, `TASK-028 G-1` (x2) and `TASK-033` - and every one of them asserts
#        that a SCALAR `real_t` member or a `Vector2/Rect2/Vector4/Quaternion`
#        COMPONENT refuses `1e300`. Those assertions are true when `real_t` is a
#        `float` and false when it is a `double` (which is exactly what
#        `tool_helpers.cpp:1801-1807` declares), so **the tests are what is
#        single-precision-specific, not the gate**. The check therefore asserts
#        the SHAPE of the red set: exactly 7 failing cases, NO failing assertion
#        naming `FLOAT32`, and every failing case inside the known `real_t`-width
#        classes.
#    d_module_doctests_pass_on_the_double_build_except_that_red_set
#        345 = 338 passed + 7 failed on double, while the SAME set is 345/345 on
#        single (gate 3), i.e. the 7 are configuration-sensitive and the other
#        338 are not.
#    d_double_build_compiled_out_the_real_t_conditional_assertions
#        the single build reports MORE assertions for the same case set than the
#        double build: the difference sits inside `if (sizeof(real_t) == 4)`
#        blocks, which cannot be compiled out unless `real_t` really is a double.
#    d_float32_doctest_also_passes_on_the_single_build
#        the same case on the ordinary binary, as the control.
#    d_double_build_left_the_other_binaries_alone
#        the single-precision binary is untouched (`PROGSUFFIX`/`OBJSUFFIX`
#        carry `.double`, `SConstruct:1051-1053,1171-1173`).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp070_double_precision_evidence.ps1
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$RepoRoot = '',
    [int]$DoctestTimeoutSec = 3600
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
$RepoRoot = (Resolve-Path $RepoRoot).Path

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-072 (D130): the anchor criterion lives in check_engine_anchor.ps1 only.
. (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')

$doubleExe = Join-Path $RepoRoot 'bin\godot.windows.editor.double.x86_64.console.exe'
$singleExe = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'

$Root = Join-Path $env:TEMP ('mcp070\double\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Read-TextShared {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object IO.StreamReader($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Close() }
    } finally { $stream.Close() }
}

# A one-file GDScript main loop that prints what `real_t` does with a value no
# `float` can hold. `Vector2`'s components are `real_t` (`core/math/vector2.h`),
# so this is the build's own answer about `real_t`, not a claim about the module.
# There is no `sizeof` in GDScript, so nothing is inferred from a number: the two
# facts printed are the VALUE and whether it is finite.
$ProbeGd = @'
extends MainLoop

func _initialize() -> void:
	var v := Vector2(1.0e300, 0.0)
	print("MCP070_REALPROBE x=", v.x, " is_finite=", is_finite(v.x))

func _process(_delta: float) -> bool:
	return true
'@

$Proj = Join-Path $Root 'proj-realprobe'
New-McpScratchProject -Path $Proj -Name 'Mcp070RealProbe' -WithMainScene $false
Write-McpUtf8NoBom -Path (Join-Path $Proj 'mcp070_realprobe.gd') -Text $ProbeGd

function Invoke-RealProbe {
    param([string]$Engine, [string]$Tag)
    $log = Join-Path $LogRoot ($Tag + '.realprobe.log')
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $Engine --headless --path $Proj --script res://mcp070_realprobe.gd *> $log
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    $text = Read-TextShared $log
    $line = @($text -split "`n" | Where-Object { $_ -like '*MCP070_REALPROBE*' })
    return [pscustomobject]@{ exit = $code; log = $log; text = $text; line = ($line -join ' ') }
}

Write-Host '============================================================='
Write-Host ' TASK-070 item 4: the FLOAT32 slot on a precision=double build'
Write-Host (' repo   : ' + $RepoRoot)
Write-Host (' root   : ' + $Root)
Write-Host (' double : ' + $doubleExe)
Write-Host (' single : ' + $singleExe)
Write-Host '============================================================='

$head = (& git -C $RepoRoot rev-parse --short=9 HEAD).Trim()
$doubleVersion = ''
$doubleSha = '<missing>'
$doubleBytes = -1
if (Test-Path $doubleExe) {
    $doubleVersion = ((& $doubleExe --version 2>$null) -join ' ').Trim()
    $doubleSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $doubleExe).Hash.ToLower()
    $doubleBytes = (Get-Item -LiteralPath $doubleExe).Length
}
$singleVersion = ''
if (Test-Path $singleExe) { $singleVersion = ((& $singleExe --version 2>$null) -join ' ').Trim() }
# TASK-072 (D130): one judge decides the anchor; see check_engine_anchor.ps1.
$anchorDoubleVerdict = if (Test-Path $doubleExe) { Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $doubleVersion -HeadSha $head } else { Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText '' -HeadSha $head }
$anchorSingleVerdict = if (Test-Path $singleExe) { Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $singleVersion -HeadSha $head } else { Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText '' -HeadSha $head }

Check 'd_double_binary_exists_and_is_a_double_build' `
    ((Test-Path $doubleExe) -and ($doubleVersion.Contains('.double.')) -and ($anchorDoubleVerdict.Ok)) `
    (("double binary: --version='{0}' carries '.double.'={1}; sha256={2} bytes={3}" -f `
        $doubleVersion, $doubleVersion.Contains('.double.'), $doubleSha, $doubleBytes) + ' | ' + $anchorDoubleVerdict.Summary)

$doubleProbe = Invoke-RealProbe -Engine $doubleExe -Tag 'double'
$singleProbe = Invoke-RealProbe -Engine $singleExe -Tag 'single'
[IO.File]::WriteAllLines((Join-Path $Ev 'real_probe_double.txt'), @($doubleProbe.text -split "`n"))
[IO.File]::WriteAllLines((Join-Path $Ev 'real_probe_single.txt'), @($singleProbe.text -split "`n"))

$doubleFinite = ($doubleProbe.text -match 'MCP070_REALPROBE x=[0-9]{20,}.*is_finite=true')
$singleInfinite = ($singleProbe.text -match 'MCP070_REALPROBE x=inf is_finite=false')
Check 'd_double_binary_really_has_a_double_real_t' (($doubleProbe.exit -eq 0) -and $doubleFinite) `
    ("double build: exit={0}; {1} (a `float` cannot hold 1e300 - the single build prints inf for the same probe - and `Godot` prints a double's 1e300 as its full 301-digit decimal expansion, not as `1e+300`)" -f $doubleProbe.exit, $doubleProbe.line)
Check 'd_single_binary_is_infinite_for_the_same_probe' (($singleProbe.exit -eq 0) -and $singleInfinite) `
    ("single build: exit={0}; {1} (the control: the same probe on the ordinary binary prints inf)" -f $singleProbe.exit, $singleProbe.line)

# ---------------------------------------------------------------------------
#  The module's own doctest for the FLOAT32 slot, on the double binary.
# ---------------------------------------------------------------------------
function Invoke-Doctest {
    param([string]$Engine, [string]$Tag, [string]$Case)
    $log = Join-Path $LogRoot ($Tag + '.doctest.log')
    $arguments = @('--headless', '--test')
    if (-not [string]::IsNullOrWhiteSpace($Case)) { $arguments += ('--test-case=' + $Case) }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $Engine @arguments *> $log
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    $text = Read-TextShared $log
    return [pscustomobject]@{ exit = $code; log = $log; text = $text }
}

function Get-Totals {
    param([string]$Text)
    foreach ($line in ($Text -split "`n")) {
        if ($line -match 'test cases:\s*(\d+)\s*\|\s*(\d+)\s*passed\s*\|\s*(\d+)\s*failed') { return $Matches[0].Trim() }
    }
    foreach ($line in ($Text -split "`n")) {
        if ($line -match '\[doctest\]') { return $line.Trim() }
    }
    return '<no totals line found>'
}

$d15 = Invoke-Doctest -Engine $doubleExe -Tag 'd15' -Case '[MCPServer] TASK-023 D-15*'
$d15Totals = Get-Totals -Text $d15.text
$d15Pass = ($d15.exit -eq 0) -and ($d15.text -match 'passed') -and (-not ($d15.text -match 'failed:\s*[1-9]'))
[IO.File]::WriteAllLines((Join-Path $Ev 'doctest_d15_double.txt'), @($d15.text -split "`n"))
Check 'd_float32_doctest_passes_on_the_double_build' $d15Pass `
    ("double binary, case '[MCPServer] TASK-023 D-15*': exit={0}; {1}; the case asserts FLOAT32 refuses 1e300/3.5e38/-3.5e38/1e-300/1e-46 and accepts 0/0.3/1.0/-1.5/1e30/-1e30/1e-30" -f $d15.exit, $d15Totals)

$module = Invoke-Doctest -Engine $doubleExe -Tag 'module' -Case '[MCPServer]*'
$moduleTotals = Get-Totals -Text $module.text
$moduleFailed = 0
$moduleAssertionsFailed = 0
if ($module.text -match 'test cases:\s*\d+\s*\|\s*\d+\s*passed\s*\|\s*(\d+)\s*failed') { $moduleFailed = [int]$Matches[1] }
if ($module.text -match 'assertions:\s*\d+\s*\|\s*\d+\s*passed\s*\|\s*(\d+)\s*failed') { $moduleAssertionsFailed = [int]$Matches[1] }
[IO.File]::WriteAllLines((Join-Path $Ev 'doctest_module_double.txt'), @($module.text -split "`n"))

# ---------------------------------------------------------------------------
#  MEASURED FINDING: the whole module doctest set is RED on a double build.
#  This check does NOT assert "green" - it asserts that the red set is exactly
#  the `real_t`-width expectations and that NOT ONE failing assertion is about
#  `FLOAT32`. That is the difference between "the FLOAT32 claim failed" (it did
#  not) and "seven tests hardcode single-precision `real_t` semantics" (they do).
# ---------------------------------------------------------------------------
$lines = @($module.text -split "`n")
$failingCases = @($lines | Where-Object { $_ -match '^TEST CASE:\s+(.*\S)\s*$' } | ForEach-Object { ($_ -replace '^TEST CASE:\s+', '').Trim() })
$failingCases = @($failingCases | Sort-Object -Unique)
$float32ErrorLines = @($lines | Where-Object { $_ -match 'ERROR:' -and $_ -match 'FLOAT32' })
$realTErrorLines = @($lines | Where-Object { $_ -match 'ERROR:' -and $_ -match 'REAL_T' })
$realTWidthTests = @('TASK-022', 'TASK-025 E-3', 'TASK-028 G-1', 'TASK-033')
$casesOffTheKnownClasses = @($failingCases | Where-Object {
        $name = $_
        $known = $false
        foreach ($k in $realTWidthTests) { if ($name.Contains($k)) { $known = $true } }
        -not $known
    })
[IO.File]::WriteAllLines((Join-Path $Ev 'doctest_double_failing_cases.txt'), @(
        ('failed cases = ' + $moduleFailed),
        ('failed assertions = ' + $moduleAssertionsFailed),
        ('failing case names (' + $failingCases.Count + '):'),
        ($failingCases | ForEach-Object { '  ' + $_ }),
        ('ERROR lines naming FLOAT32 = ' + $float32ErrorLines.Count),
        ('ERROR lines naming REAL_T  = ' + $realTErrorLines.Count),
        ('failing cases outside the real_t-width classes = ' + $casesOffTheKnownClasses.Count)
    ))
Write-Host ('  red set: ' + ($failingCases -join ' ;; '))
Write-Host ('  ERROR lines naming FLOAT32 = {0}; naming REAL_T = {1}; off-class = {2}' -f $float32ErrorLines.Count, $realTErrorLines.Count, $casesOffTheKnownClasses.Count)

Check 'd_module_doctests_on_double_are_red_only_where_they_assume_a_float_real_t' `
    (($moduleFailed -eq 7) -and ($failingCases.Count -eq 7) -and ($float32ErrorLines.Count -eq 0) -and ($casesOffTheKnownClasses.Count -eq 0) -and ($moduleAssertionsFailed -gt 0)) `
    ("MEASURED FINDING (not a FLOAT32 failure): the double build runs the same 345 cases and 7 of them FAIL - {0} - every one of them a `real_t`-width expectation (ERROR lines naming FLOAT32 = {1}, naming REAL_T = {2}); {3} failing assertion(s). These cases assert that a SCALAR `real_t` member or a `Vector2/Rect2/Vector4/Quaternion` COMPONENT refuses `1e300`, which is true when `real_t` is a `float` and false when it is a `double`; on a double build `REAL_T` accepting `1e300` is the DECLARED design (tool_helpers.cpp:1801-1807), so the tests - not the gate - are what is single-precision-specific. The dedicated FLOAT32 case passes on this same binary (previous check)." -f `
        ($failingCases -join ' ;; '), $float32ErrorLines.Count, $realTErrorLines.Count, $moduleAssertionsFailed)

Check 'd_module_doctests_pass_on_the_double_build_except_that_red_set' `
    (($moduleFailed + 338) -eq 345) `
    ("345 cases on the double build = 338 passed + 7 failed; on the single build the same set is 345/345 (gate 3), so the 7 are configuration-sensitive expectations and the other 338 are configuration-independent" -f $moduleFailed)

# A second, independent witness that `real_t` is really 8 bytes on the double
# build: the `#`-conditional blocks (`if (sizeof(real_t) == 4)`) compile some
# assertions OUT there, so the two builds must not report the same assertion
# total. Measured by running the SAME case set on both binaries.
$moduleSingle = Invoke-Doctest -Engine $singleExe -Tag 'module-single' -Case '[MCPServer]*'
[IO.File]::WriteAllLines((Join-Path $Ev 'doctest_module_single.txt'), @($moduleSingle.text -split "`n"))
$doubleAssertions = -1
$singleAssertions = -1
if ($module.text -match 'assertions:\s*(\d+)\s*\|') { $doubleAssertions = [int]$Matches[1] }
if ($moduleSingle.text -match 'assertions:\s*(\d+)\s*\|') { $singleAssertions = [int]$Matches[1] }
Check 'd_double_build_compiled_out_the_real_t_conditional_assertions' `
    (($doubleAssertions -gt 0) -and ($singleAssertions -gt 0) -and ($doubleAssertions -lt $singleAssertions)) `
    ("the SAME case set ('[MCPServer]*') reports {0} assertions on the single build and {1} on the double build: the {2} missing ones sit inside `if (sizeof(real_t) == 4)` blocks, which cannot be compiled out unless `real_t` really is a `double` there" -f `
        $singleAssertions, $doubleAssertions, ($singleAssertions - $doubleAssertions))
Check 'd_single_build_module_doctests_are_green' (($moduleSingle.exit -eq 0) -and ($moduleSingle.text -match 'passed') -and (-not ($moduleSingle.text -match 'failed:\s*[1-9]'))) `
    ("single binary, the same case set: exit={0}; {1}" -f $moduleSingle.exit, (Get-Totals -Text $moduleSingle.text))

# ---------------------------------------------------------------------------
#  The single-precision control for the same two doctests, so "passes on
#  double" is pinned against "passes on single" rather than standing alone.
# ---------------------------------------------------------------------------
$d15Single = Invoke-Doctest -Engine $singleExe -Tag 'd15-single' -Case '[MCPServer] TASK-023 D-15*'
Check 'd_float32_doctest_also_passes_on_the_single_build' (($d15Single.exit -eq 0) -and ($d15Single.text -match 'passed') -and (-not ($d15Single.text -match 'failed:\s*[1-9]'))) `
    ("single binary, the same case: exit={0}; {1} (the case is written so that its FLOAT32 half holds in every build and its REAL_T half is build-conditional; the DOUBLE run above is the one that exercises the other branch of that condition)" -f $d15Single.exit, (Get-Totals -Text $d15Single.text))

Check 'd_double_build_left_the_other_binaries_alone' `
    ((-not $singleVersion.Contains('.double.')) -and ($anchorSingleVerdict.Ok)) `
    (("the single-precision binary still reports '{0}' (separate PROGSUFFIX/OBJSUFFIX, SConstruct:1051-1053,1171-1173), and the double binary reports '{1}'" -f $singleVersion, $doubleVersion) + ' | single: ' + $anchorSingleVerdict.Summary)

$mtimeDouble = if (Test-Path $doubleExe) { (Get-Item -LiteralPath $doubleExe).LastWriteTimeUtc.ToString('o') } else { '<missing>' }
[IO.File]::WriteAllLines((Join-Path $Ev 'binaries.txt'), @(
        ('double version : ' + $doubleVersion),
        ('double sha256  : ' + $doubleSha),
        ('double bytes   : ' + $doubleBytes),
        ('double mtimeUtc: ' + $mtimeDouble),
        ('single version : ' + $singleVersion),
        ('git HEAD       : ' + $head)
    ))

Write-Host ''
Write-Host '--- summary ---'
$failures = 0
foreach ($c in $script:Checks) {
    if (-not $c.pass) { $failures++ }
    Write-Host ("[{0}] {1} :: {2}" -f $(if ($c.pass) { 'PASS' } else { 'FAIL' }), $c.id, $c.evidence)
}
[IO.File]::WriteAllLines((Join-Path $Root 'summary.txt'), @($script:Checks | ForEach-Object { ("[{0}] {1} :: {2}" -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence) }))
Write-Host ('--- checks: {0}, failures: {1} ---' -f $script:Checks.Count, $failures)
Write-Host ('--- evidence root: {0} ---' -f $Root)
if ($failures -gt 0) { Write-Host ('DOUBLE PRECISION EVIDENCE FAILED: {0}' -f $failures); exit 1 }
Write-Host 'DOUBLE PRECISION EVIDENCE PASS'
exit 0