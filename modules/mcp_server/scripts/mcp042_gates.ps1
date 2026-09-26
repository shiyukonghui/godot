# =============================================================================
#  mcp042_gates.ps1 -- TASK-042 gate battery, strictly serial (pure ASCII).
#
#  Every gate writes its own log under %TEMP%\mcp042\gates; the summary lists each
#  step's exit code. Two engines are never started at the same time (PLAYBOOK
#  section 3, R-1 / D62) and no scons is started here at all: the gates run
#  against the binary `scripts\build_local.cmd -Force` built, whose `--version`
#  self-report is compared with `git rev-parse --short=9 HEAD` below.
#
#  TASK-042's regressions are the six scripts whose 9877 precondition this batch
#  replaced (section 1) plus the two mcp040 scripts; their exit codes are in this
#  summary and their per-check attribution is in REPORT-042 section 7.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp042_gates.ps1
# =============================================================================

$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Scripts = Join-Path $RepoRoot 'modules\mcp_server\scripts'
$Logs = Join-Path $env:TEMP 'mcp042\gates'
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
    $line = ('STEP {0} EXIT {1} ({2:n0}s)' -f $Name, $rc, ((Get-Date) - $started).TotalSeconds)
    Add-Content -Path $Summary -Value $line -Encoding ASCII
    Write-Host $line
}

Add-Content -Path $Summary -Value 'TASK-042 gate battery' -Encoding ASCII
Add-Content -Path $Summary -Value ('binary --version: ' + (& $Engine --version)) -Encoding ASCII
Add-Content -Path $Summary -Value ('git HEAD: ' + (& git -C $RepoRoot rev-parse --short=9 HEAD)) -Encoding ASCII

Invoke-Step 'gate3_module_doctest' { & $Engine --headless --test '--test-case=[MCPServer]*' }
Invoke-Step 'gate4_full_doctest' { & $Engine --headless --test }
Invoke-Step 'gate1_contract_subset' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'check_contract_subset.ps1') -Group editor_input_simulation }
Invoke-Step 'gate6a_narrowing' { & python (Join-Path $Scripts 'check_narrowing_points.py') }
Invoke-Step 'gate6b_narrowing_coverage' { & python (Join-Path $Scripts 'check_narrowing_points.py') --coverage }
Invoke-Step 'gate6c_coverage_probes' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp031_gate6_coverage_probes.ps1') }
Invoke-Step 'gate5_accept_run1' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'accept_m1.ps1') }
Invoke-Step 'gate5_accept_run2' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'accept_m1.ps1') }
Invoke-Step 'gate2_rewrite_and_honesty_evidence' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp042_projectrewrite_and_honesty_evidence.ps1') }
Invoke-Step 'gate2b_port_guard_probes' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp042_port_guard_probes.ps1') }
Invoke-Step 'gate2c_task041_evidence' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp041_inputmap_persistence_evidence.ps1') }
Invoke-Step 'regress_mcp032' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp032_d3_d4_d6_evidence.ps1') }
Invoke-Step 'regress_mcp033' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp033_b5_animation_evidence.ps1') }
Invoke-Step 'regress_mcp034' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp034_b5_audio_particle_theme_evidence.ps1') }
Invoke-Step 'regress_mcp035' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp035_b5_tilemap_shader_physics_evidence.ps1') }
Invoke-Step 'regress_mcp036' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp036_b5_navigation_theme_export_android_evidence.ps1') }
Invoke-Step 'regress_probe037' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'probe037_d2_d1_r1r2.ps1') }
Invoke-Step 'regress_mcp040_probes' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp040_defect_probes.ps1') -Label task042 }
Invoke-Step 'regress_mcp040_racing' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp040_racing_regression.ps1') }

Add-Content -Path $Summary -Value ('tree dirty after the run: ' + ((& git -C $RepoRoot status --porcelain) -join ' | ')) -Encoding ASCII
Add-Content -Path $Summary -Value 'DONE' -Encoding ASCII
Write-Host ''
Write-Host '== summary =='
Get-Content $Summary | ForEach-Object { Write-Host $_ }

# --- TASK-069 gate: a battery whose steps are red must not exit 0 -----------
# Invoke-Step records every child's exit code in $Summary; this block is what
# makes THIS process's exit code agree with the record. Measured before
# TASK-069: `gate2_rewrite_and_honesty_evidence` ran
# mcp042_projectrewrite_and_honesty_evidence.ps1, which exited 1 with
# "30 checks, 3 failed", the summary line read `STEP ... EXIT 1` - and this
# driver still returned 0 (REPORT-068 section 5.4; TASK-069 section 2).
$failed = @(Select-String -Path $Summary -Pattern 'EXIT [1-9]')
if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host ("FAILED STEPS: {0}" -f $failed.Count)
    foreach ($entry in $failed) { Write-Host ('    ' + $entry.Line) }
    exit 1
}
Write-Host ("ALL STEPS EXIT 0 ({0} step line(s) in {1})" -f @(Select-String -Path $Summary -Pattern '^STEP ').Count, $Summary)
exit 0
