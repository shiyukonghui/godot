# =============================================================================
#  mcp057_gates.ps1 -- TASK-057 gate battery (strictly serial, no scons).
#
#  Runs, in order:
#    gate 3   module doctests        --headless --test --test-case="[MCPServer]*"
#    gate 4   full engine regression --headless --test
#    gate 6   narrowing points       check_narrowing_points.py (+ --coverage, probes)
#    extra    contract completeness  check_tool_groups.py --check-completeness
#    extra    added manifest         check_tool_groups.py --added
#    extra    R-B2 version assertion check_tool_groups.py --generator-version
#    extra    R-B2 failure demo      mcp057_rb2_failure_demo.ps1
#    gate 1   contract verbatim      check_contract_subset.ps1 (default + 3 groups)
#    extra    patch 2 live evidence  mcp057_settings_publish_evidence.ps1
#
#  Gate 5 (`accept_m1.ps1` twice, PASS lists compared) and the 15 step regression
#  battery live in `mcp056_regression_battery.ps1`, which TASK-057 section 3
#  changed so that it writes its own logs to %TEMP% and restores the tracked
#  evidence it overwrote; running it here as well would double the wall clock
#  without adding a different check.
#
#  Logs: %TEMP%\mcp057\gates\<stamp>\ . The plain binary must have been rebuilt
#  for this working tree and must report the git HEAD in `--version`; this script
#  prints both at the top and fails at the end if any step is non-zero.
#
#  Pure ASCII on purpose.
# =============================================================================

param([string]$LogRoot = '')

$ErrorActionPreference = 'Continue'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = Join-Path $env:TEMP ('mcp057\gates\' + $Stamp)
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
    $null = Invoke-Step 'contract_completeness' 'python' @('modules\mcp_server\docs\scripts\check_tool_groups.py', '--check-completeness')
    $null = Invoke-Step 'contract_added' 'python' @('modules\mcp_server\docs\scripts\check_tool_groups.py', '--added')
    $null = Invoke-Step 'contract_generator_version' 'python' @('modules\mcp_server\docs\scripts\check_tool_groups.py', '--generator-version')
    $null = Invoke-Step 'rb2_failure_demo' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\mcp057_rb2_failure_demo.ps1')
    $null = Invoke-Step 'gate1_contract_default' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1')
    $null = Invoke-Step 'gate1_contract_read_template' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1', '-Group', 'project_read_template')
    $null = Invoke-Step 'gate1_contract_validate_scripts' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1', '-Group', 'project_validate_scripts')
    $null = Invoke-Step 'gate1_contract_csharp_build' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1', '-Group', 'project_csharp_build')
    $null = Invoke-Step 'gate1_contract_editor_set_node_script_batch' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1', '-Group', 'editor_set_node_script_batch')
    $null = Invoke-Step 'patch2_settings_publish_evidence' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\mcp057_settings_publish_evidence.ps1')
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