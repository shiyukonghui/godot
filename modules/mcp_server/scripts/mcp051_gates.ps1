# =============================================================================
#  mcp051_gates.ps1 -- TASK-051's gates 3, 4, 5, 6 plus the contract checks, all
#  strictly serial (pure ASCII).
#
#  Every step writes its own log under
#  `docs/reports/evidence/task051/green/` and its exit code to `summary.txt`.
#  Nothing here starts scons: the binary is the one
#  `scripts\build_local.cmd -Force` built, whose `--version` is recorded below
#  next to `git rev-parse --short=9 HEAD` (the gate must be run against a binary
#  that matches HEAD).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp051_gates.ps1
# =============================================================================

$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Scripts = Join-Path $RepoRoot 'modules\mcp_server\scripts'
$Module = Join-Path $RepoRoot 'modules\mcp_server'
$Logs = Join-Path $Module 'docs\reports\evidence\task051\green'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$Summary = Join-Path $Logs 'summary-gates.txt'
Set-Content -Path $Summary -Value '' -Encoding ASCII
Set-Location $RepoRoot

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ("===== STEP {0} =====" -f $Name)
    $out = Join-Path $Logs ($Name + '.log')
    $started = Get-Date
    & $Body *> $out
    $rc = $LASTEXITCODE
    $line = ('STEP {0} EXIT {1} ({2:n0}s)' -f $Name, $rc, ((Get-Date) - $started).TotalSeconds)
    Add-Content -Path $Summary -Value $line -Encoding ASCII
    Write-Host $line
}

Add-Content -Path $Summary -Value 'TASK-051 gates' -Encoding ASCII
Add-Content -Path $Summary -Value ('binary --version: ' + (& $Engine --version)) -Encoding ASCII
Add-Content -Path $Summary -Value ('git HEAD: ' + (& git -C $RepoRoot rev-parse HEAD)) -Encoding ASCII
Add-Content -Path $Summary -Value ('git HEAD short: ' + (& git -C $RepoRoot rev-parse --short=9 HEAD)) -Encoding ASCII

# --- the contract's own static gates ---------------------------------------
Invoke-Step 'contract_check_rename_map' { & python (Join-Path $Module 'docs\scripts\check_rename_map.py') }
Invoke-Step 'contract_check_tool_groups' { & python (Join-Path $Module 'docs\scripts\check_tool_groups.py') }
Invoke-Step 'contract_structured_diff' {
    $before = Join-Path $env:TEMP 'mcp051\contract_before.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $before) | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $text = ((& git -C $RepoRoot show 'HEAD:modules/mcp_server/docs/tools_list.renamed.json') -join "`n") + "`n"
    [IO.File]::WriteAllText($before, $text, $utf8)
    & python (Join-Path $Scripts 'mcp051_contract_diff.py') $before (Join-Path $Module 'docs\tools_list.renamed.json') (Join-Path $Logs 'contract-diff.json')
}

# --- gate 3: the module's own doctests --------------------------------------
Invoke-Step 'gate3_module_doctests' { & $Engine --headless --test '--test-case=[MCPServer]*' }

# --- gate 4: the whole engine test suite ------------------------------------
Invoke-Step 'gate4_full_engine_tests' { & $Engine --headless --test }

# --- gate 6: the narrowing points, all three legs ---------------------------
Invoke-Step 'gate6a_narrowing_points' { & python (Join-Path $Scripts 'check_narrowing_points.py') }
Invoke-Step 'gate6b_narrowing_coverage' { & python (Join-Path $Scripts 'check_narrowing_points.py') --coverage }
Invoke-Step 'gate6c_gate6_coverage_probes' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp031_gate6_coverage_probes.ps1') }

# --- gate 5: the batch acceptance, twice ------------------------------------
Invoke-Step 'gate5a_accept_m1_run1' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'accept_m1.ps1') }
Invoke-Step 'gate5b_accept_m1_run2' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'accept_m1.ps1') }

Add-Content -Path $Summary -Value ('tree dirty after the run: ' + ((& git -C $RepoRoot status --porcelain) -join ' | ')) -Encoding ASCII
Add-Content -Path $Summary -Value 'DONE' -Encoding ASCII
Write-Host ''
Get-Content $Summary | ForEach-Object { Write-Host $_ }

# TASK-069 section 2.3 (census): Invoke-Step recorded every child's exit code in
# $Summary and this file never read it back, so a red step was reported and the
# process still exited 0. Same guard as the TASK-042/043 drivers.
$failed = @(Select-String -Path $Summary -Pattern 'EXIT [1-9]')
if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host ("FAILED STEPS: {0}" -f $failed.Count)
    foreach ($entry in $failed) { Write-Host ('    ' + $entry.Line) }
    exit 1
}
exit 0
