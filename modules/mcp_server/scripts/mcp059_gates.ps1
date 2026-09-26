# =============================================================================
#  mcp059_gates.ps1 -- TASK-059 gate battery (strictly serial, no scons).
#
#  The TASK-057 battery (`mcp057_gates.ps1`) is the module's gate runner and is
#  not modified by this batch, so this one runs the SAME gate steps plus the
#  TASK-059-specific ones. Running both would only double the wall clock; the
#  step list below is the union, and the names say which batch introduced each.
#
#    gate 1   contract verbatim      check_contract_subset.ps1 (default + 5 groups)
#    gate 3   module doctests        --headless --test --test-case="[MCPServer]*"
#    gate 4   full engine regression --headless --test
#    gate 6   narrowing points       check_narrowing_points.py (plain + --coverage
#                                    + mcp031_gate6_coverage_probes.ps1)
#    extra    contract completeness  check_tool_groups.py --check-completeness
#    extra    added manifest         check_tool_groups.py --added
#    extra    generator version      check_tool_groups.py --generator-version
#    extra    R-B2 failure demo      mcp057_rb2_failure_demo.ps1
#    extra    patch 2 live evidence  mcp057_settings_publish_evidence.ps1 (D-1/D-2 fixed)
#    T-059    tautology scan         check_tautologies.py
#    T-059    tautology probes       check_tautologies.py --probes
#    T-059    tautology coverage     check_tautologies.py --coverage
#    T-059    contract pre/post      mcp059_contract_pre_post.py
#    T-059    tool-path evidence     mcp059_section_switch_evidence.ps1
#    T-059    D-5 scons probe demo   mcp059_d5_scons_probe_demo.ps1
#    T-059    D-2 failure demo       mcp059_d2_failure_demo.ps1 (3 evidence runs)
#
#  Gate 5 (`accept_m1.ps1` twice, PASS lists compared) lives in
#  `mcp056_regression_battery.ps1` with the 15 step regression, exactly as the
#  TASK-057 battery documents; it is not repeated here.
#
#  Logs: %TEMP%\mcp059\gates\<stamp>\ . The plain binary must have been rebuilt
#  for this working tree and must report the git HEAD in `--version`; this script
#  prints both at the top and fails at the end if any step is non-zero.
#
#  TASK-073 A -- gate 3's OPTIONAL precision=double variant
#  -------------------------------------------------------
#  Gate 3 (`gate3_doctest_mcpserver`, the step above) is a SINGLE-PRECISION gate:
#  it runs bin\godot.windows.editor.x86_64.console.exe, i.e. `precision` at its
#  default. TASK-071 declared that in writing (REPORT-071 section B.4) and left
#  `precision=double` covered by no gate at all. That gap now has an executable
#  answer and it is OPT-IN, in both directions:
#
#    * DEFAULT (`mcp059_gates.ps1`) -- the step list is exactly the TASK-059 list,
#      step for step. No build is started, no double binary is touched and the
#      wall clock does not grow. The one conditional Invoke-Step below is tagged
#      `MCP073-ONLY-IN-DOUBLE-MODE` so a reader (or a script) can extract the
#      default plan from this file and see that for themselves.
#    * OPT-IN (`-PrecisionVariant double`, or the equivalent `-WithDouble`) --
#      ONE extra step runs last: scripts\mcp073_gate3_double.ps1, which builds the
#      double binary serially (reusing scripts\mcp070_build_double.cmd, guarded
#      against a concurrent scons), judges its anchor with TASK-072's one
#      criterion (scripts\check_engine_anchor.ps1; ANCHOR_EQUAL or
#      ANCHOR_STRUCTURAL_EQUIVALENT pass, ANCHOR_STALE_COMPILED is RED) and runs
#      this very gate 3 case set on it, requiring it green.
#
#  The two switches contradicting each other (`-WithDouble -PrecisionVariant
#  single`) is a usage error (exit 3) rather than a silent winner.
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$LogRoot = '',
    [ValidateSet('single', 'double')][string]$PrecisionVariant = 'single',
    [switch]$WithDouble
)

$ErrorActionPreference = 'Continue'

# TASK-073 A: the variant selection. `-PrecisionVariant` defaults to 'single', so
# "explicitly single" is told apart from "not passed" through $PSBoundParameters.
$variantPassedExplicitly = $PSBoundParameters.ContainsKey('PrecisionVariant')
if ($WithDouble -and $variantPassedExplicitly -and ($PrecisionVariant -ne 'double')) {
    Write-Host 'mcp059_gates: -WithDouble and -PrecisionVariant single contradict each other; pass one of them.'
    exit 3
}
if ($WithDouble) { $PrecisionVariant = 'double' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = Join-Path $env:TEMP ('mcp059\gates\' + $Stamp)
}
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$LogRoot = (Resolve-Path $LogRoot).Path

$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Results = New-Object System.Collections.Generic.List[string]

function Invoke-Step {
    param([string]$Name, [string]$File, [string[]]$Arguments)
    $log = Join-Path $LogRoot ($Name + '.log')
    Write-Host ("=== {0} ===" -f $Name)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $File @Arguments *> $log
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    $tail = (Get-Content $log -Tail 3) -join ' | '
    Write-Host ("    exit={0} :: {1}" -f $code, $tail)
    $Results.Add(('{0}|{1}|{2}' -f $Name, $code, $tail))
    return $code
}

Push-Location $RepoRoot
try {
    # TASK-072 (D130): the anchor criterion lives in check_engine_anchor.ps1 only.
    . (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')
    $version = ((& $Engine --version 2>$null) -join '').Trim()
    $head = ((& git rev-parse --short=9 HEAD) -join '').Trim()
    $anchorVerdict = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $version -HeadSha $head
    Write-Host ("engine --version: {0}" -f $version)
    Write-Host ("git HEAD short : {0}" -f $head)
    Write-Host ('version_matches_head: ' + $anchorVerdict.Ok + ' verdict=' + $anchorVerdict.Verdict)
    Write-Host ('anchor: ' + $anchorVerdict.Summary)

    $null = Invoke-Step 'gate3_doctest_mcpserver' $Engine @('--headless', '--test', '--test-case=[MCPServer]*')
    $null = Invoke-Step 'gate4_full_regression' $Engine @('--headless', '--test')
    $null = Invoke-Step 'gate6_narrowing' 'python' @('modules\mcp_server\scripts\check_narrowing_points.py')
    $null = Invoke-Step 'gate6_narrowing_coverage' 'python' @('modules\mcp_server\scripts\check_narrowing_points.py', '--coverage')
    $null = Invoke-Step 'gate6_coverage_probes' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\mcp031_gate6_coverage_probes.ps1')
    $null = Invoke-Step 't059_tautology_scan' 'python' @('modules\mcp_server\scripts\check_tautologies.py')
    $null = Invoke-Step 't059_tautology_probes' 'python' @('modules\mcp_server\scripts\check_tautologies.py', '--probes')
    $null = Invoke-Step 't059_tautology_coverage' 'python' @('modules\mcp_server\scripts\check_tautologies.py', '--coverage')
    $null = Invoke-Step 'contract_completeness' 'python' @('modules\mcp_server\docs\scripts\check_tool_groups.py', '--check-completeness')
    $null = Invoke-Step 'contract_added' 'python' @('modules\mcp_server\docs\scripts\check_tool_groups.py', '--added')
    $null = Invoke-Step 'contract_generator_version' 'python' @('modules\mcp_server\docs\scripts\check_tool_groups.py', '--generator-version')
    $null = Invoke-Step 't059_contract_pre_post' 'python' @('modules\mcp_server\scripts\mcp059_contract_pre_post.py')
    $null = Invoke-Step 'rb2_failure_demo' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\mcp057_rb2_failure_demo.ps1')
    $null = Invoke-Step 't059_d5_scons_probe_demo' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\mcp059_d5_scons_probe_demo.ps1')
    $null = Invoke-Step 'gate1_contract_default' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1')
    $null = Invoke-Step 'gate1_contract_read_template' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1', '-Group', 'project_read_template')
    $null = Invoke-Step 'gate1_contract_validate_scripts' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1', '-Group', 'project_validate_scripts')
    $null = Invoke-Step 'gate1_contract_csharp_build' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1', '-Group', 'project_csharp_build')
    $null = Invoke-Step 'gate1_contract_editor_set_node_script_batch' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1', '-Group', 'editor_set_node_script_batch')
    $null = Invoke-Step 't059_section_switch_evidence' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\mcp059_section_switch_evidence.ps1')
    $null = Invoke-Step 'patch2_settings_publish_evidence' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\mcp057_settings_publish_evidence.ps1')
    $null = Invoke-Step 't059_d2_failure_demo' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\mcp059_d2_failure_demo.ps1')

    # TASK-073 A: gate 3's optional precision=double variant. Only reached with an
    # explicit switch; the step is last on purpose so the default list above is
    # untouched in order and in content.
    if ($PrecisionVariant -eq 'double') {
        Write-Host 'precision variant: double (gate 3 default is single; this step builds and runs the .double binary)'
        $null = Invoke-Step 'gate3_double_variant' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\mcp073_gate3_double.ps1', '-SkipSingleControl', '-EvidenceDir', (Join-Path $LogRoot 'gate3_double')) # MCP073-ONLY-IN-DOUBLE-MODE
    }
} finally {
    Pop-Location
}

[IO.File]::WriteAllLines((Join-Path $LogRoot 'summary.txt'), $Results.ToArray())
Write-Host ''
Write-Host '--- summary ---'
$Results | ForEach-Object { Write-Host $_ }
Write-Host ('--- logs: {0} ---' -f $LogRoot)
$failed = @($Results | Where-Object { ($_ -split '\|')[1] -ne '0' })
if ($failed.Count -gt 0) { Write-Host ('FAILED STEPS: {0}' -f $failed.Count); exit 1 }
Write-Host 'ALL GATE STEPS EXIT 0'
exit 0