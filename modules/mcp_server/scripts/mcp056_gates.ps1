# =============================================================================
#  mcp056_gates.ps1 -- TASK-056 gate battery, strictly serial.
#
#  Runs, in order and without any concurrent scons:
#    gate 3  module doctests        --headless --test --test-case="[MCPServer]*"
#    gate 4  full engine regression --headless --test
#    gate 6  narrowing points       check_narrowing_points.py (+ --coverage, probes)
#    extra   contract completeness  check_tool_groups.py --check-completeness / --added
#    gate 1  live contract verbatim check_contract_subset.ps1 (default and -Group)
#
#  Logs: docs/reports/evidence/task056/gates/. The plain binary must have been
#  rebuilt for this working tree (`build_local.cmd -Force`) before this runs.
# =============================================================================

$ErrorActionPreference = 'Continue'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Ev = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task056\gates'
New-Item -ItemType Directory -Force -Path $Ev | Out-Null

$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Results = New-Object System.Collections.Generic.List[string]

function Invoke-Step {
    param([string]$Name, [string]$File, [string[]]$Arguments)
    $log = Join-Path $Ev ($Name + '.log')
    Write-Host ("=== {0} ===" -f $Name)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $File @Arguments *> $log
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    $tail = (Get-Content $log -Tail 4) -join ' | '
    Write-Host ("    exit={0} :: {1}" -f $code, $tail)
    $Results.Add(('{0}|{1}|{2}' -f $Name, $code, $tail))
    return $code
}

Push-Location $RepoRoot
try {
    Write-Host ("engine --version: " + ((& $Engine --version 2>$null) -join ' '))
    Write-Host ("git HEAD: " + ((& git rev-parse HEAD) -join ' '))

    $null = Invoke-Step 'gate3_doctest_mcpserver' $Engine @('--headless', '--test', '--test-case=[MCPServer]*')
    $null = Invoke-Step 'gate4_full_regression' $Engine @('--headless', '--test')
    $null = Invoke-Step 'gate6_narrowing' 'python' @('modules\mcp_server\scripts\check_narrowing_points.py')
    $null = Invoke-Step 'gate6_narrowing_coverage' 'python' @('modules\mcp_server\scripts\check_narrowing_points.py', '--coverage')
    $null = Invoke-Step 'gate6_coverage_probes' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\mcp031_gate6_coverage_probes.ps1')
    $null = Invoke-Step 'contract_completeness' 'python' @('modules\mcp_server\docs\scripts\check_tool_groups.py', '--check-completeness')
    $null = Invoke-Step 'contract_added' 'python' @('modules\mcp_server\docs\scripts\check_tool_groups.py', '--added')
    $null = Invoke-Step 'gate1_contract_default' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1')
    $null = Invoke-Step 'gate1_contract_validate_scripts' 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'modules\mcp_server\scripts\check_contract_subset.ps1', '-Group', 'project_validate_scripts')
} finally {
    Pop-Location
}

[IO.File]::WriteAllLines((Join-Path $Ev 'summary.txt'), $Results.ToArray())
Write-Host ''
Write-Host '--- summary ---'
$Results | ForEach-Object { Write-Host $_ }
$failed = @($Results | Where-Object { ($_ -split '\|')[1] -ne '0' })
if ($failed.Count -gt 0) { Write-Host ('FAILED STEPS: {0}' -f $failed.Count); exit 1 }
Write-Host 'ALL GATE STEPS EXIT 0'
exit 0