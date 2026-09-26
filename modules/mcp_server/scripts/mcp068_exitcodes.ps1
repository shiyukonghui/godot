# =============================================================================
#  mcp068_exitcodes.ps1 -- TASK-068 (1): the exit codes of the rename-map scripts,
#  captured as evidence.
#
#  TASK-068 changed `docs/scripts/check_rename_map.py` (the contract-size
#  expectation is now derived) and added `scripts/mcp068_rename_map_reverse_probe.ps1`.
#  A report that says "before: 1, after: 0" has to be reproducible, and the
#  unrepaired "before" no longer exists in the worktree, so this script measures
#  **both versions of the same expression on the same input** in one process:
#
#    * `check_rename_map.py` as the worktree has it now       -> must exit 0;
#    * the same script with its two G comparisons restored to the pre-TASK-068
#      literals (edited in a TEMP copy, never in the repository) -> must be
#      non-zero and must fail exactly on those two checks;
#    * `mcp068_rename_map_reverse_probe.ps1`                  -> must exit 0.
#
#  The temporary copy is what makes the "before" number real instead of
#  remembered: the only difference between the two runs is the two lines under
#  test.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp068_exitcodes.ps1
#  Exit 0 when the three expectations hold.
# =============================================================================

$ErrorActionPreference = 'Stop'
$script:Failures = 0

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
    return $Path
}

function Add-Check([string]$Id, [bool]$Pass, [string]$Detail) {
    $tag = 'FAIL'
    if ($Pass) { $tag = 'PASS' }
    Write-Host ('[{0}] {1} :: {2}' -f $tag, $Id, $Detail)
    if (-not $Pass) { $script:Failures = $script:Failures + 1 }
}

# `& python script` sets $LASTEXITCODE; stdout+stderr go to a file so the exit
# code is the only thing this function reads from the process. The redirect is
# done by `cmd /c` rather than by PowerShell's `2>&1`: the "before" run is
# *supposed* to print a FATAL traceback, and PowerShell 5.1 turns a native
# process' stderr into a terminating `NativeCommandError` under
# `$ErrorActionPreference = 'Stop'` even when the exit code is what matters.
function Invoke-Python {
    param([string]$ScriptPath, [string]$LogPath, [string]$WorkingDirectory)
    if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
    $line = ('cd /d "{2}" && python "{0}" > "{1}" 2>&1' -f $ScriptPath, $LogPath, $WorkingDirectory)
    & cmd.exe /c $line | Out-Null
    return $LASTEXITCODE
}

$McpRoot = 'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server'
$ScriptDir = Join-Path $McpRoot 'docs\scripts'
$Scratch = Join-Path $env:TEMP 'mcp068'
Ensure-Dir $Scratch | Out-Null

Write-Host '============================================================='
Write-Host ' TASK-068: check_rename_map.py exit codes (before / after)'
Write-Host '============================================================='

$current = Join-Path $ScriptDir 'check_rename_map.py'
$afterLog = Join-Path $Scratch 'rename_map_after.txt'
$afterCode = Invoke-Python -ScriptPath $current -LogPath $afterLog -WorkingDirectory $ScriptDir
Add-Check 'current_script_exits_0' ($afterCode -eq 0) ('exit=' + $afterCode + ' log=' + $afterLog)

# --- the pre-TASK-068 script, rebuilt in a TEMP copy -------------------------
# The copy lives in `docs/scripts/` while it runs (and only while it runs): the
# script resolves `docs/*.json` from `os.path.dirname(os.path.abspath(__file__))`,
# so a copy anywhere else cannot see them and the "before" run would fail for a
# reason that is not under test (measured on the first version of this harness:
# `FileNotFoundError: ...\AppData\Local\Temp\tool-rename-map.json`). The file is
# deleted in the `finally` below, so the repository is left exactly as it was.
$beforeScript = Join-Path $ScriptDir 'check_rename_map_BEFORE_TASK068.py'
$text = [IO.File]::ReadAllText($current, (New-Object Text.UTF8Encoding($false)))
$nl = [string][char]10
$newG1 = 'check("G1 ported half is still 171", ported_count == 171, "ported=%d" % ported_count)'
$oldG1 = 'check("G1 contract tool count == 171", len(ctools) == 171, "len=%d" % len(ctools))'
# The whole G6 call, exactly as the current file spells it (five lines), against
# the whole pre-TASK-068 G5 call (two lines). Replacing only the first line and
# the expectation leaves the `check(` wrapper behind, which makes the call a
# *nested* expression - it then still prints nothing and the failing-check count
# is one instead of two (measured on the first version of this harness).
$newG6 = 'check("G6 contract count == map total - 2 unregister - 1 merge + _meta.added_count",' + $nl +
         '          len(ctools) == expected_contract_count,' + $nl +
         '          "%d == %d - 2 - 1 + %d = %d"' + $nl +
         '          % (len(ctools), rename_map.get("total"), added_count, expected_contract_count))'
$oldG6 = 'check("G5 contract count == map total - 2 unregister - 1 merge",' + $nl +
         '          len(ctools) == 174 - 2 - 1, "%d == 171" % len(ctools))'
if (-not $text.Contains($newG1)) { throw 'the new G1 line is not in the current script (TASK-068 text moved?)' }
if (-not $text.Contains($newG6)) { throw 'the new G6 block is not in the current script (TASK-068 text moved?)' }
$before = $text.Replace($newG1, $oldG1).Replace($newG6, $oldG6)
$beforeLog = Join-Path $Scratch 'rename_map_before.txt'
$beforeCode = -999
try {
    [IO.File]::WriteAllText($beforeScript, $before, (New-Object Text.UTF8Encoding($false)))
    $beforeCode = Invoke-Python -ScriptPath $beforeScript -LogPath $beforeLog -WorkingDirectory $ScriptDir
} finally {
    if (Test-Path -LiteralPath $beforeScript) { Remove-Item -LiteralPath $beforeScript -Force }
}
Add-Check 'pre_task068_script_exits_nonzero' ($beforeCode -ne 0) ('exit=' + $beforeCode + ' log=' + $beforeLog + ' copy was ' + $beforeScript + ' (deleted)')
Add-Check 'pre_task068_copy_is_deleted_from_the_tree' (-not (Test-Path -LiteralPath $beforeScript)) $beforeScript

# Only the `check()` output lines are "failing checks": `[FAIL] <label>` with the
# label column the script's own format uses. A traceback can contain the word
# FAIL inside a path, and counting *it* would be measuring the harness instead of
# the script (the first version of this file did exactly that).
function Get-FailedChecks([string]$LogPath) {
    $pattern = '^\[FAIL\]\s'
    $out = @()
    foreach ($line in ([IO.File]::ReadAllLines($LogPath))) {
        if ($line -match $pattern) { $out += $line.Trim() }
    }
    return $out
}

$failedLines = Get-FailedChecks $beforeLog
Add-Check 'pre_task068_script_fails_exactly_on_the_two_size_checks' ($failedLines.Count -eq 2) ('failing checks=' + $failedLines.Count + ' [' + ($failedLines -join ' | ') + ']')
$afterFailed = Get-FailedChecks $afterLog
Add-Check 'current_script_has_no_failing_check' ($afterFailed.Count -eq 0) ('failing checks=' + $afterFailed.Count)

# --- the reverse probe -------------------------------------------------------
$probe = Join-Path $McpRoot 'scripts\mcp068_rename_map_reverse_probe.ps1'
$probeLog = Join-Path $Scratch 'rename_map_reverse_probe.txt'
if (Test-Path -LiteralPath $probeLog) { Remove-Item -LiteralPath $probeLog -Force }
& cmd.exe /c ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" > "{1}" 2>&1' -f $probe, $probeLog) | Out-Null
$probeCode = $LASTEXITCODE
Add-Check 'reverse_probe_exits_0' ($probeCode -eq 0) ('exit=' + $probeCode + ' log=' + $probeLog)

Write-Host ''
Write-Host ('BEFORE (pre-TASK-068 expressions, same input) = exit {0}' -f $beforeCode)
Write-Host ('AFTER  (current script)                       = exit {0}' -f $afterCode)
Write-Host ('PROBE  (old false / new true, same input)     = exit {0}' -f $probeCode)
if ($script:Failures -gt 0) {
    Write-Host ('TASK-068 EXIT-CODE EVIDENCE FAILED ({0})' -f $script:Failures)
    exit 1
}
Write-Host 'TASK-068 EXIT-CODE EVIDENCE PASS'
exit 0
