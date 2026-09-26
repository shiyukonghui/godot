# =============================================================================
#  mcp051_gate1_groups.ps1 -- gate 1 for the five groups TASK-051 changed
#  (pure ASCII).
#
#  `check_contract_subset.ps1` compares the *group's* tools name/description/
#  inputSchema verbatim on both endpoints, and asserts in the same run that the
#  live tool set is exactly the implemented union. TASK-051 changed the
#  `inputSchema` of five tools that live in five different groups, so the gate
#  has to be run once per group - each run re-proves the union as well.
#
#  Strictly serial (one engine pair at a time); each run's log and exit code are
#  recorded in a summary.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp051_gate1_groups.ps1
# =============================================================================

$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Scripts = Join-Path $RepoRoot 'modules\mcp_server\scripts'
$Logs = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task051\green\gate1'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$Summary = Join-Path $Logs 'summary.txt'
Set-Content -Path $Summary -Value '' -Encoding ASCII
Set-Location $RepoRoot

$groups = @(
    'editor_node_batch_write',
    'editor_node_read',
    'editor_input_simulation',
    'editor_playback',
    'running_game_test_execution'
)

Add-Content -Path $Summary -Value 'TASK-051 gate 1, one run per affected group' -Encoding ASCII
Add-Content -Path $Summary -Value ('git HEAD: ' + (& git -C $RepoRoot rev-parse --short=9 HEAD)) -Encoding ASCII

foreach ($group in $groups) {
    Write-Host ("===== GATE1 {0} =====" -f $group)
    $log = Join-Path $Logs ($group + '.log')
    $started = Get-Date
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scripts 'check_contract_subset.ps1') -Group $group *> $log
    $rc = $LASTEXITCODE
    $verdict = (Select-String -Path $log -Pattern '(\d+)/(\d+) checks passed' | Select-Object -Last 1).Line
    $line = ('GATE1 {0} EXIT {1} ({2:n0}s) {3}' -f $group, $rc, ((Get-Date) - $started).TotalSeconds, $verdict)
    Add-Content -Path $Summary -Value $line -Encoding ASCII
    Write-Host $line
}

Add-Content -Path $Summary -Value 'DONE' -Encoding ASCII
Write-Host ''
Get-Content $Summary | ForEach-Object { Write-Host $_ }

# TASK-069 section 2.3 (census): this loop records each group's exit code in
# $Summary with the "GATE1 <group> EXIT <n>" format and never read it back.
$failed = @(Select-String -Path $Summary -Pattern 'EXIT [1-9]')
if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host ("FAILED GROUPS: {0}" -f $failed.Count)
    foreach ($entry in $failed) { Write-Host ('    ' + $entry.Line) }
    exit 1
}
exit 0
