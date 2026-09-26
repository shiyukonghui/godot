# =============================================================================
#  mcp054_gate_battery.ps1 -- TASK-054 gates 1, 3, 4, 5, 6 plus the contract
#  completeness checks, strictly serial (pure ASCII).
#
#  Every step writes its own log under %TEMP%\mcp054\gates and the summary lists
#  each step's exit code. No scons is started here: the gates run against the
#  binary `modules/mcp_server/scripts/build_local.cmd -Force` built, whose
#  `--version` self-report is compared with `git rev-parse --short=9 HEAD` here.
#  Two engines are never started at the same time (PLAYBOOK section 3, R-1/D62).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp054_gate_battery.ps1
# =============================================================================

$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Scripts = Join-Path $RepoRoot 'modules\mcp_server\scripts'
$DocScripts = Join-Path $RepoRoot 'modules\mcp_server\docs\scripts'
$Logs = Join-Path $env:TEMP 'mcp054\gates'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$Summary = Join-Path $Logs 'summary.txt'
Set-Content -Path $Summary -Value '' -Encoding ASCII
Set-Location $RepoRoot

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ("===== STEP {0} =====" -f $Name)
    $out = Join-Path $Logs ($Name + '.log')
    $started = Get-Date
    & $Body *> $out
    $rc = $LASTEXITCODE
    if ($null -eq $rc) { $rc = 0 }
    $line = ('STEP {0} EXIT {1} ({2:n0}s)' -f $Name, $rc, ((Get-Date) - $started).TotalSeconds)
    Add-Content -Path $Summary -Value $line -Encoding ASCII
    Write-Host $line
}

Add-Content -Path $Summary -Value 'TASK-054 gate battery' -Encoding ASCII
Add-Content -Path $Summary -Value ('plain binary --version: ' + (& $Engine --version)) -Encoding ASCII
Add-Content -Path $Summary -Value ('git HEAD: ' + (& git -C $RepoRoot rev-parse --short=9 HEAD)) -Encoding ASCII

Invoke-Step 'gate3_module_doctest' { & $Engine --headless --test '--test-case=[MCPServer]*' }
Invoke-Step 'gate4_full_doctest' { & $Engine --headless --test }
Invoke-Step 'gate1_contract_subset_default_group' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'check_contract_subset.ps1') }
Invoke-Step 'gate1_contract_subset_added_group' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'check_contract_subset.ps1') -Group project_validate_scripts }
Invoke-Step 'gate6a_narrowing' { & python (Join-Path $Scripts 'check_narrowing_points.py') }
Invoke-Step 'gate6b_narrowing_coverage' { & python (Join-Path $Scripts 'check_narrowing_points.py') --coverage }
Invoke-Step 'gate6c_coverage_probes' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp031_gate6_coverage_probes.ps1') }
Invoke-Step 'contract_completeness' { & python (Join-Path $DocScripts 'check_tool_groups.py') --check-completeness }
Invoke-Step 'contract_added_manifest' { & python (Join-Path $DocScripts 'check_tool_groups.py') --added }
Invoke-Step 'gate5_accept_run1' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'accept_m1.ps1') }
Invoke-Step 'gate5_accept_run2' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'accept_m1.ps1') }

Add-Content -Path $Summary -Value ('tree dirty after the run: ' + ((& git -C $RepoRoot status --porcelain) -join ' | ')) -Encoding ASCII
Add-Content -Path $Summary -Value 'DONE' -Encoding ASCII
Get-Content $Summary | ForEach-Object { Write-Host $_ }
$failed = @(Select-String -Path $Summary -Pattern 'EXIT [1-9]')
if ($failed.Count -gt 0) {
    Write-Host ("{0} step(s) failed; see {1}" -f $failed.Count, $Summary)
    exit 1
}
exit 0