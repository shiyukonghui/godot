# =============================================================================
#  mcp043_gates.ps1 -- TASK-043 gate battery, strictly serial (pure ASCII).
#
#  Every step writes its own log under %TEMP%\mcp043\gates; the summary lists each
#  step's exit code. Two engines are never started at the same time (PLAYBOOK
#  section 3, R-1 / D62) and no scons is started here: the gates run against the
#  binary `scripts\build_local.cmd -Force` built, whose `--version` self-report is
#  recorded next to `git rev-parse --short=9 HEAD` (they have to be equal).
#
#  TASK-043 changes descriptions only, so its own gate-2 evidence is
#  `mcp043_description_evidence.ps1` (the live tools/list) plus
#  `mcp043_reload_plugin_rewrite_probe.ps1` (the one added tool of the survey),
#  and the behaviour regressions are the TASK-042/TASK-041 evidence chains plus
#  the six scripts whose 9877 precondition TASK-042 replaced.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp043_gates.ps1
# =============================================================================

$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Scripts = Join-Path $RepoRoot 'modules\mcp_server\scripts'
$Logs = Join-Path $env:TEMP 'mcp043\gates'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$Summary = Join-Path $Logs 'summary.txt'
Set-Content -Path $Summary -Value '' -Encoding ASCII
Set-Location $RepoRoot

# The pre-TASK-043 contract, pinned by revision *and* by sha256: TASK-043's brief
# commit is `806d5396b`, and the renamed contract it was written against is
# `c844ec8a...`. The byte-exact copy this produces is the left-hand side of the
# structured contract diff below; the sha check is what keeps that snapshot from
# silently becoming some other revision.
#
# TASK-050 section 4: the *right-hand* side is pinned the same way now. It used
# to be the live `docs/tools_list.renamed.json`, which made this step a snapshot
# of TASK-043's result that any later legitimate contract change would turn red -
# and TASK-050 really does change the contract (one appended description, N-2).
# The assertion itself is untouched (`scripts/mcp043_contract_diff.py` is not
# modified at all); what changed is that both sides are now the revision pair
# TASK-043 actually proved, so this step keeps testing TASK-043 rather than "no
# later task has touched the contract" - a property that is not this battery's
# subject and that TASK-050's own `scripts/mcp050_contract_diff.py` asserts.
$PreChangeContractRev = '806d5396b'
$PreChangeContractSha = 'c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256'
$BeforeContract = Join-Path $env:TEMP 'mcp043\tools_list.before.json'
$PostChangeContractRev = '47b5008bac'
$PostChangeContractSha = '443f1df2e9a3c5b0a2ad1c4ce532a4cfb6f33d22d0401a02448a0ca0bede914f'
$AfterContract = Join-Path $env:TEMP 'mcp043\tools_list.after.json'

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

function Invoke-SnapshotStep {
    param([string]$Name, [string]$Rev, [string]$RelPath, [string]$ExpectedSha, [string]$Destination)
    Invoke-Step $Name {
        $parent = Split-Path -Parent $Destination
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        # cmd redirection, not a PowerShell pipeline: the bytes `git show` emits
        # reach the file unchanged (the TASK-042 lesson about piped evidence).
        & cmd /c ('git -C "{0}" show {1}:{2} > "{3}"' -f $RepoRoot, $Rev, $RelPath, $Destination)
        $sha = '<absent>'
        if (Test-Path $Destination) { $sha = (Get-FileHash -Algorithm SHA256 -Path $Destination).Hash.ToLower() }
        Write-Host ("{0}:{1} -> {2} sha256={3} (expected {4})" -f $Rev, $RelPath, $Destination, $sha, $ExpectedSha)
        if ($sha -ceq $ExpectedSha) { $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 }
    }
}

Add-Content -Path $Summary -Value 'TASK-043 gate battery' -Encoding ASCII
Add-Content -Path $Summary -Value ('binary --version: ' + (& $Engine --version)) -Encoding ASCII
Add-Content -Path $Summary -Value ('git HEAD: ' + (& git -C $RepoRoot rev-parse --short=9 HEAD)) -Encoding ASCII

Invoke-SnapshotStep -Name 'gate2f_snapshot_before_contract' -Rev $PreChangeContractRev `
    -RelPath 'modules/mcp_server/docs/tools_list.renamed.json' -ExpectedSha $PreChangeContractSha -Destination $BeforeContract
Invoke-SnapshotStep -Name 'gate2f_snapshot_after_contract' -Rev $PostChangeContractRev `
    -RelPath 'modules/mcp_server/docs/tools_list.renamed.json' -ExpectedSha $PostChangeContractSha -Destination $AfterContract

Invoke-Step 'gate3_module_doctest' { & $Engine --headless --test '--test-case=[MCPServer]*' }
Invoke-Step 'gate4_full_doctest' { & $Engine --headless --test }
# Gate 1 is "per-group verbatim": it compares the *group's* tools verbatim
# (name / description / inputSchema) on both endpoints and asserts the union for
# the rest. TASK-043 changed descriptions in four different groups, so it is run
# once per owning group, which is what makes "verbatim, the changed tools
# included" true rather than assumed.
Invoke-Step 'gate1a_contract_group_editor_write_scene_editor' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'check_contract_subset.ps1') -Group editor_write_scene_editor }
Invoke-Step 'gate1b_contract_group_project_setting_write' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'check_contract_subset.ps1') -Group project_setting_write }
Invoke-Step 'gate1c_contract_group_project_autoload_write' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'check_contract_subset.ps1') -Group project_autoload_write }
Invoke-Step 'gate1d_contract_group_editor_input_simulation' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'check_contract_subset.ps1') -Group editor_input_simulation }
Invoke-Step 'gate6a_narrowing' { & python (Join-Path $Scripts 'check_narrowing_points.py') }
Invoke-Step 'gate6b_narrowing_coverage' { & python (Join-Path $Scripts 'check_narrowing_points.py') --coverage }
Invoke-Step 'gate6c_coverage_probes' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp031_gate6_coverage_probes.ps1') }
Invoke-Step 'gate5_accept_run1' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'accept_m1.ps1') }
Invoke-Step 'gate5_accept_run2' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'accept_m1.ps1') }
Invoke-Step 'gate2a_description_evidence' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp043_description_evidence.ps1') }
Invoke-Step 'gate2b_reload_plugin_probe' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp043_reload_plugin_rewrite_probe.ps1') }
Invoke-Step 'gate2c_probe037_d2d1r1r2' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'probe037_d2_d1_r1r2.ps1') }
Invoke-Step 'gate2d_rewrite_evidence' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp042_projectrewrite_and_honesty_evidence.ps1') }
Invoke-Step 'gate2e_task041_evidence' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp041_inputmap_persistence_evidence.ps1') }
Invoke-Step 'gate2f_port_guard_probes' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp042_port_guard_probes.ps1') }
Invoke-Step 'gate2g_contract_diff' { & python (Join-Path $Scripts 'mcp043_contract_diff.py') $BeforeContract $AfterContract (Join-Path $env:TEMP 'mcp043\contract-diff.json') }
Invoke-Step 'gate2h_registration_literals' { & python (Join-Path $Scripts 'mcp043_registration_literals.py') }
Invoke-Step 'gate2i_group_lookup' { & python (Join-Path $Scripts 'mcp043_group_lookup.py') }
Invoke-Step 'regress_mcp032' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp032_d3_d4_d6_evidence.ps1') }
Invoke-Step 'regress_mcp033' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp033_b5_animation_evidence.ps1') }
Invoke-Step 'regress_mcp034' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp034_b5_audio_particle_theme_evidence.ps1') }
Invoke-Step 'regress_mcp035' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp035_b5_tilemap_shader_physics_evidence.ps1') }
Invoke-Step 'regress_mcp036' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp036_b5_navigation_theme_export_android_evidence.ps1') }
Invoke-Step 'regress_mcp040_probes' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp040_defect_probes.ps1') -Label task043 }
Invoke-Step 'regress_mcp040_racing' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp040_racing_regression.ps1') }

Add-Content -Path $Summary -Value ('tree dirty after the run: ' + ((& git -C $RepoRoot status --porcelain) -join ' | ')) -Encoding ASCII
Add-Content -Path $Summary -Value 'DONE' -Encoding ASCII
Write-Host ''
Write-Host '== summary =='
Get-Content $Summary | ForEach-Object { Write-Host $_ }

# --- TASK-069 gate: a battery whose steps are red must not exit 0 -----------
# Invoke-Step records every child's exit code in $Summary; this block is what
# makes THIS process's exit code agree with the record. Measured before
# TASK-069: `gate2a_description_evidence` ran mcp043_description_evidence.ps1,
# which exited 1 with "16 checks, 5 failed", and `gate2d_rewrite_evidence` ran
# mcp042_projectrewrite_and_honesty_evidence.ps1, which exited 1 with
# "30 checks, 3 failed" - the summary named both, and this driver still returned
# 0 (REPORT-068 section 5.4; TASK-069 section 2). The `$global:LASTEXITCODE = 1`
# that Invoke-SnapshotStep sets is NOT a substitute: it is overwritten by the
# next child and nothing ever reads it.
$failed = @(Select-String -Path $Summary -Pattern 'EXIT [1-9]')
if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host ("FAILED STEPS: {0}" -f $failed.Count)
    foreach ($entry in $failed) { Write-Host ('    ' + $entry.Line) }
    exit 1
}
Write-Host ("ALL STEPS EXIT 0 ({0} step line(s) in {1})" -f @(Select-String -Path $Summary -Pattern '^STEP ').Count, $Summary)
exit 0