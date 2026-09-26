# =============================================================================
#  mcp054_regression_battery.ps1 -- TASK-054 regression runs, strictly serial.
#
#  The scripts every earlier batch left behind are re-run against this tree. The
#  point of the run is *attribution*: TASK-054 changes one tool's wire behaviour
#  (C# is `unverifiable` instead of `ok`), adds a line to the trace file, and
#  regenerates the contract (`_meta.generator_version` 1.15.0 -> 1.16.0, two
#  description fields), so any step that fails has to be explained rather than
#  excused.
#
#  Every step's stdout/stderr is kept under
#  docs/reports/evidence/task054/regression/ and a summary lists each exit code.
#  Two engines are never started at the same time (PLAYBOOK section 3, R-1/D62)
#  and no scons is started here at all.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp054_regression_battery.ps1
# =============================================================================

param(
    [string]$Only = ''
)

$ErrorActionPreference = 'Continue'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Scripts = $PSScriptRoot
$Logs = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task054\regression'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$Summary = Join-Path $Logs 'summary.txt'
Set-Content -Path $Summary -Value '' -Encoding ASCII
Set-Location $RepoRoot

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    if ($Only -ne '' -and $Name -ne $Only) { return }
    Write-Host ("===== STEP {0} =====" -f $Name)
    $out = Join-Path $Logs ($Name + '.log')
    $started = Get-Date
    & $Body *> $out
    $rc = $LASTEXITCODE
    if ($null -eq $rc) { $rc = 0 }
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

Add-Content -Path $Summary -Value 'TASK-054 regression battery' -Encoding ASCII
Add-Content -Path $Summary -Value ('plain binary --version: ' + (& $Engine --version)) -Encoding ASCII
Add-Content -Path $Summary -Value ('mono binary --version: ' + (& (Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe') --version)) -Encoding ASCII
Add-Content -Path $Summary -Value ('git HEAD: ' + (& git -C $RepoRoot rev-parse --short=9 HEAD)) -Encoding ASCII

# The TASK-041 / TASK-042 / TASK-043 gate batteries: each one re-runs gates
# 3/4/1/6/5 and its own batch's evidence scripts.
Invoke-Ps1 -Name 'task041_gates' -Script 'mcp041_gates.ps1'
Invoke-Ps1 -Name 'task042_gates' -Script 'mcp042_gates.ps1'
Invoke-Ps1 -Name 'task043_gates' -Script 'mcp043_gates.ps1'

# TASK-053's battery is the transport for the TASK-010 / 019 / 027 / 044 / 045 /
# 046 / 050 / 051 / 052 scripts (it has one batch per previous task).
Invoke-Ps1 -Name 'task053_individual' -Script 'mcp053_regression_battery.ps1' -Extra @('-Batch', 'individual')
Invoke-Ps1 -Name 'task053_capture' -Script 'mcp053_regression_battery.ps1' -Extra @('-Batch', 'capture')
Invoke-Ps1 -Name 'task053_task051' -Script 'mcp053_regression_battery.ps1' -Extra @('-Batch', 'task051')
Invoke-Ps1 -Name 'task053_added' -Script 'mcp053_regression_battery.ps1' -Extra @('-Batch', 'added')

# TASK-053's own live evidence (its mono phase C pins the C# answer this task
# changed; it was updated to the fixed truth and is re-run here).
Invoke-Ps1 -Name 'task053_evidence' -Script 'mcp053_added_tools_evidence.ps1'

# TASK-038's trace evidence (it counts the lines of a trace file, which this
# task's generation marker moved from 10 to 11; it was updated and re-run here).
Invoke-Ps1 -Name 'task038_trace_evidence' -Script 'mcp038_trace_evidence.ps1'

Add-Content -Path $Summary -Value ('tree dirty after the run: ' + ((& git -C $RepoRoot status --porcelain) -join ' | ')) -Encoding ASCII
Add-Content -Path $Summary -Value 'DONE' -Encoding ASCII
Get-Content $Summary | ForEach-Object { Write-Host $_ }
$failed = @(Select-String -Path $Summary -Pattern 'EXIT [1-9]')
if ($failed.Count -gt 0) {
    Write-Host ("{0} step(s) failed; see {1}" -f $failed.Count, $Summary)
    exit 1
}
exit 0
