# =============================================================================
#  mcp053_regression_battery.ps1 -- TASK-053 regression runs, strictly serial.
#
#  The scripts of the previous batches are re-run against this tree and their
#  stdout/stderr is kept, one file per step, under
#  docs/reports/evidence/task053/regression/. The point of the run is
#  *attribution*: the contract moved 173 -> 175 and one ported entry's schema
#  moved, so any step that fails has to be explained rather than excused.
#
#  The driver is modeled on scripts/mcp051_regression_battery.ps1 - same step
#  list, same `individual`/`batteries`/`capture` split - with one deliberate
#  difference: it writes its logs into this batch's own evidence directory, so it
#  does not overwrite the evidence of the batch whose scripts it runs. (A few of
#  those scripts write their own evidence under their own task directory; the
#  step list and the report say which ones did, and those files are restored
#  afterwards so the only durable record of this run is this directory.)
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp053_regression_battery.ps1 -Batch individual
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp053_regression_battery.ps1 -Batch batteries
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp053_regression_battery.ps1 -Batch capture
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp053_regression_battery.ps1 -Batch added
# =============================================================================

param(
    [string]$Batch = 'individual'
)

$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$MonoEngine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe'
$Scripts = $PSScriptRoot
$Logs = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task053\regression'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$Summary = Join-Path $Logs ('summary-' + $Batch + '.txt')
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
    # A step that "passed" in no time at all is the failure mode this driver has
    # to refuse: an empty `$Scripts` made every `powershell -File <garbage>` exit
    # 0 without running anything (measured while writing this script). A step
    # whose log is empty is therefore a failure, whatever its exit code says.
    $logBytes = 0
    if (Test-Path $out) { $logBytes = (Get-Item $out).Length }
    if ($logBytes -eq 0) { $rc = 97 }
    $line = ('STEP {0} EXIT {1} ({2:n0}s, log={3} bytes)' -f $Name, $rc, ((Get-Date) - $started).TotalSeconds, $logBytes)
    Add-Content -Path $Summary -Value $line -Encoding ASCII
    Write-Host $line
}

function Invoke-Ps1 {
    param([string]$Name, [string]$Script, [string[]]$Extra = @())
    Invoke-Step $Name { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts $Script) @Extra }
}

Add-Content -Path $Summary -Value ('TASK-053 regression battery: ' + $Batch) -Encoding ASCII
Add-Content -Path $Summary -Value ('plain binary --version: ' + (& $Engine --version)) -Encoding ASCII
if (Test-Path $MonoEngine) {
    Add-Content -Path $Summary -Value ('mono binary --version: ' + (& $MonoEngine --version)) -Encoding ASCII
}
Add-Content -Path $Summary -Value ('git HEAD: ' + (& git -C $RepoRoot rev-parse HEAD)) -Encoding ASCII

if ($Batch -eq 'individual') {
    Invoke-Step 'gate6c_coverage_probes' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'mcp031_gate6_coverage_probes.ps1') }
    Invoke-Ps1 -Name 'regress_mcp010_b2_observation' -Script 'mcp010_b2_observation_evidence.ps1'
    Invoke-Ps1 -Name 'regress_mcp019_b4' -Script 'mcp019_b4_evidence.ps1'
    Invoke-Ps1 -Name 'regress_mcp027_object_shape_and_paths' -Script 'mcp027_object_shape_and_paths_evidence.ps1'
    Invoke-Ps1 -Name 'regress_mcp050_parameter_guidance' -Script 'mcp050_parameter_guidance_evidence.ps1' -Extra @('-Label', 'green')
    Invoke-Step 'regress_mcp050_contract_diff' {
        $before = Join-Path $env:TEMP 'mcp053\task050_contract_before.json'
        $after = Join-Path $env:TEMP 'mcp053\task050_contract_after.json'
        New-Item -ItemType Directory -Force -Path (Split-Path $before) | Out-Null
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $beforeText = ((& git -C $RepoRoot show '889466b85c:modules/mcp_server/docs/tools_list.renamed.json') -join "`n") + "`n"
        $afterText = ((& git -C $RepoRoot show 'b8b6553d90:modules/mcp_server/docs/tools_list.renamed.json') -join "`n") + "`n"
        [IO.File]::WriteAllText($before, $beforeText, $utf8)
        [IO.File]::WriteAllText($after, $afterText, $utf8)
        & python (Join-Path $Scripts 'mcp050_contract_diff.py') $before $after (Join-Path $env:TEMP 'mcp053\task050_contract_diff.json')
    }
} elseif ($Batch -eq 'batteries') {
    Invoke-Ps1 -Name 'regress_mcp041_gates' -Script 'mcp041_gates.ps1'
    Invoke-Ps1 -Name 'regress_mcp042_gates' -Script 'mcp042_gates.ps1'
    Invoke-Ps1 -Name 'regress_mcp043_gates' -Script 'mcp043_gates.ps1'
} elseif ($Batch -eq 'capture') {
    Invoke-Ps1 -Name 'regress_mcp044_capture_editor' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'editor')
    Invoke-Ps1 -Name 'regress_mcp044_capture_headless' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'headless')
    Invoke-Ps1 -Name 'regress_mcp044_capture_game' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'game')
    Invoke-Ps1 -Name 'regress_mcp044_capture_diff_image' -Script 'mcp044_capture_evidence.ps1' -Extra @('-Phase', 'diff-image')
    Invoke-Ps1 -Name 'regress_mcp045_pixel_compare_cost' -Script 'mcp045_pixel_compare_cost.ps1' -Extra @('-Label', 'post')
    Invoke-Ps1 -Name 'regress_mcp046_capture_encode_cost' -Script 'mcp046_capture_encode_cost.ps1' -Extra @('-Label', 'post')
} elseif ($Batch -eq 'task051') {
    # TASK-051's own gate battery (`mcp051_gates.ps1`) is **not** reusable as a
    # whole: its `contract_structured_diff` step pins TASK-051's revision pair by
    # content (171 entries, generator 1.12.0 -> 1.13.0, overrides 24 -> 28),
    # which no later tree satisfies - running it here would report eight
    # `PROBLEM` lines about TASK-051's own change set, not about this batch. Its
    # remaining steps (gate 3/4/5 x2/6) are covered by this tree's own gate runs
    # and by the `batteries` batch, which re-runs them inside `mcp041_gates.ps1`.
    # What is re-run here are TASK-051's four reusable scripts.
    Invoke-Ps1 -Name 'regress_mcp051_gate1_groups' -Script 'mcp051_gate1_groups.ps1'
    Invoke-Ps1 -Name 'regress_mcp051_b_tier_evidence' -Script 'mcp051_b_tier_evidence.ps1'
    Invoke-Step 'regress_mcp051_wire_verbatim_check' {
        & python (Join-Path $Scripts 'mcp051_wire_verbatim_check.py') 2>&1
    }
    Invoke-Step 'regress_mcp051_final_sweep' {
        & python (Join-Path $Scripts 'mcp051_final_sweep.py') 2>&1
    }
    Invoke-Step 'not_a_regression_mcp051_contract_diff_pins_task051' {
        # The proof of inapplicability, kept as a step (exit 0 on purpose: this
        # step *documents* that TASK-051's diff tool cannot run here, it is not a
        # gate). Its eight PROBLEM lines are the evidence.
        $before = Join-Path $env:TEMP 'mcp053\mcp051_head_contract.json'
        New-Item -ItemType Directory -Force -Path (Split-Path $before) | Out-Null
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $text = ((& git -C $RepoRoot show 'HEAD:modules/mcp_server/docs/tools_list.renamed.json') -join "`n") + "`n"
        [IO.File]::WriteAllText($before, $text, $utf8)
        Write-Host 'mcp051_contract_diff.py is pinned to TASK-051''s own revision pair (171 entries, generator 1.12.0 -> 1.13.0, overrides 24 -> 28). Its output on this tree follows; every line is about TASK-051''s change set, not about this batch:'
        & python (Join-Path $Scripts 'mcp051_contract_diff.py') $before (Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json') (Join-Path $env:TEMP 'mcp053\mcp051_contract_diff.json') 2>&1
        Write-Host 'the four reusable TASK-051 scripts above are the regression; this step is the attribution for the fifth'
        $global:LASTEXITCODE = 0
        return
    }
} elseif ($Batch -eq 'added') {
    # TASK-052's own evidence script: the mono build is what phases B/C/D need.
    Invoke-Ps1 -Name 'regress_mcp052_added_tools' -Script 'mcp052_added_tools_evidence.ps1'
} else {
    Write-Host ("unknown batch '{0}'" -f $Batch)
    exit 2
}

Get-Content $Summary | ForEach-Object { Write-Host $_ }
$failed = @(Select-String -Path $Summary -Pattern 'EXIT [1-9]')
if ($failed.Count -gt 0) {
    Write-Host ("{0} step(s) failed; see {1}" -f $failed.Count, $Summary)
    exit 1
}
exit 0