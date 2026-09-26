# =============================================================================
#  mcp069_exit_propagation_demo.ps1 -- TASK-069 section 2.4 (2).
#
#  Defect 2 is "a gate battery that prints a red step and still exits 0". The
#  reproduction on the real scripts is in the report (the TASK-069 pre-fix
#  battery run: `mcp042_gates | 0` while its own step
#  `gate2_rewrite_and_honesty_evidence` recorded `EXIT 1` / three FAIL checks).
#  This file is the *failure demonstration* half of the fix, in the shape
#  TASK-057 R-B2 and TASK-059 D-2 established for their own checks: manufacture
#  the condition the fix claims to detect and require the real guard text to
#  answer non-zero.
#
#  What it does, and why each step is written this way:
#
#   1. Reads the REAL driver `scripts\mcp043_gates.ps1` (or -Source <path>) and
#      extracts, verbatim and byte for byte:
#        * the `Invoke-Step` function (from `function Invoke-Step {` to the
#          column-0 `}` that closes it), and
#        * the TASK-069 guard block (from its marker comment to end of file).
#      "Same input" is an assertion here, not a claim: the extracted guard text
#      must be a suffix of the real file, and its sha256 is printed. TASK-068
#      measured that a "before/after comparison" whose two sides are not the
#      same input is a trap, so the identity of the text is checked.
#
#   2. Writes three throwaway drivers under %TEMP% (never inside the repository,
#      so nothing can be left behind):
#        * UNGUARDED: green step + red step, no guard, exactly the pre-TASK-069
#          shape -> the child summary carries `EXIT 3` and the process must exit 0
#          (this is the defect, reproduced);
#        * GUARDED-RED: the same two steps + the real guard block -> exit 1;
#        * GUARDED-GREEN: the red step made green + the real guard block -> exit 0
#          (the fail -> restore -> zero leg: the guard is not a constant).
#
#   3. Prints every exit code, every summary, and the sha256 of both extracted
#      texts. Exit 0 only when the three legs are 0 / 1 / 0.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp069_exit_propagation_demo.ps1
#    powershell ... -Source <path to a gate driver>
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$Source = '',
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Scripts = Join-Path $RepoRoot 'modules\mcp_server\scripts'
if ([string]::IsNullOrWhiteSpace($Source)) { $Source = Join-Path $Scripts 'mcp043_gates.ps1' }
if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp069\exit-prop-demo' }

$script:Failures = 0
function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    if (-not $Pass) { $script:Failures = $script:Failures + 1 }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Get-Sha256Text {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($Text)))).Replace('-', '').ToLower() }
    finally { $sha.Dispose() }
}

function Get-FunctionText {
    <#
      The text from the line `function <Name> {` through the first line that is
      exactly `}` (the repository writes its PowerShell functions that way, and
      the demo asserts it found a non-empty block rather than trusting it).
    #>
    param([string]$Text, [string]$Name)
    $start = $Text.IndexOf("function $Name {")
    if ($start -lt 0) { return '' }
    $lines = $Text.Substring($start) -split "`n"
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $out.Add($line)
        if ($out.Count -gt 1 -and $line.TrimEnd("`r") -ceq '}') { break }
    }
    return (($out -join "`n") + "`n")
}

function Invoke-DemoDriver {
    param([string]$Path, [string]$LogPath)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $Path *> $LogPath
    return $LASTEXITCODE
}

Write-Host '=================================================================='
Write-Host ' TASK-069: exit-code propagation failure demonstration'
Write-Host '=================================================================='
Write-Host ("source : {0}" -f $Source)
Write-Host ''

Remove-Item -Recurse -Force $OutRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$sourceText = [IO.File]::ReadAllText($Source, $utf8)

$invokeStep = Get-FunctionText -Text $sourceText -Name 'Invoke-Step'
Check 'D01_the_real_invoke_step_function_was_extracted' ($invokeStep.Length -gt 0) `
    ("{0} char(s) from the definition of 'function Invoke-Step' in {1}; sha256={2}" -f $invokeStep.Length, (Split-Path -Leaf $Source), (Get-Sha256Text $invokeStep))
Check 'D02_the_extracted_invoke_step_is_a_slice_of_the_real_file' `
    (($invokeStep.Length -gt 0) -and ($sourceText.Contains($invokeStep))) `
    'the extracted function is byte-identical to the text in the real driver (no re-typing)'

$Marker = '# --- TASK-069 gate: a battery whose steps are red must not exit 0'
$markerIndex = $sourceText.IndexOf($Marker)
Check 'D03_the_real_guard_block_exists' ($markerIndex -ge 0) `
    ("marker '{0}' at char {1} of {2}" -f $Marker, $markerIndex, (Split-Path -Leaf $Source))
if ($markerIndex -lt 0) {
    Write-Host ("DEMO FAILURES: {0}" -f $script:Failures)
    exit 1
}
$guardBlock = $sourceText.Substring($markerIndex)
Check 'D04_the_guard_block_is_a_verbatim_suffix_of_the_real_file' `
    ($sourceText.Substring($sourceText.Length - $guardBlock.Length) -ceq $guardBlock) `
    ("{0} char(s); sha256={1} (the demo runs THIS text, not a paraphrase)" -f $guardBlock.Length, (Get-Sha256Text $guardBlock))
Check 'D05_the_guard_block_carries_a_nonzero_exit' ($guardBlock -match 'exit\s+1') `
    "the extracted block contains an `exit 1` (the demo would otherwise be testing nothing)"

# ---------------------------------------------------------------------------
#  The three drivers.
# ---------------------------------------------------------------------------
$logs = Join-Path $OutRoot 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null

function New-DemoDriver {
    param([string]$Path, [string]$Summary, [bool]$Guarded, [bool]$RedStep)
    $redLine = if ($RedStep) { "Invoke-Step 'red_step' { & cmd /c exit 3 }" } else { "Invoke-Step 'red_step' { & cmd /c exit 0 }" }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('$ErrorActionPreference = ''Continue''')
    $lines.Add(('$Logs = ' + "'" + $logs + "'"))
    $lines.Add(('$Summary = ' + "'" + $Summary + "'"))
    $lines.Add('Set-Content -Path $Summary -Value '''' -Encoding ASCII')
    foreach ($line in ($invokeStep -split "`n")) { $lines.Add($line.TrimEnd("`r")) }
    $lines.Add("Invoke-Step 'green_step' { & cmd /c exit 0 }")
    $lines.Add($redLine)
    if ($Guarded) {
        foreach ($line in ($guardBlock -split "`n")) { $lines.Add($line.TrimEnd("`r")) }
    } else {
        $lines.Add('Write-Host ''== summary ==''')
        $lines.Add('Get-Content $Summary | ForEach-Object { Write-Host $_ }')
    }
    [IO.File]::WriteAllBytes($Path, $utf8.GetBytes(($lines -join "`r`n")))
    return ($lines.Count)
}

$unguarded = Join-Path $OutRoot 'demo_unguarded.ps1'
$guardedRed = Join-Path $OutRoot 'demo_guarded_red.ps1'
$guardedGreen = Join-Path $OutRoot 'demo_guarded_green.ps1'

$null = New-DemoDriver -Path $unguarded -Summary (Join-Path $OutRoot 'summary_unguarded.txt') -Guarded $false -RedStep $true
$null = New-DemoDriver -Path $guardedRed -Summary (Join-Path $OutRoot 'summary_guarded_red.txt') -Guarded $true -RedStep $true
$null = New-DemoDriver -Path $guardedGreen -Summary (Join-Path $OutRoot 'summary_guarded_green.txt') -Guarded $true -RedStep $false

$codeUnguarded = Invoke-DemoDriver -Path $unguarded -LogPath (Join-Path $logs 'unguarded.log')
$codeGuardedRed = Invoke-DemoDriver -Path $guardedRed -LogPath (Join-Path $logs 'guarded_red.log')
$codeGuardedGreen = Invoke-DemoDriver -Path $guardedGreen -LogPath (Join-Path $logs 'guarded_green.log')

$sumUnguarded = Get-Content (Join-Path $OutRoot 'summary_unguarded.txt')
$sumGuardedRed = Get-Content (Join-Path $OutRoot 'summary_guarded_red.txt')
$sumGuardedGreen = Get-Content (Join-Path $OutRoot 'summary_guarded_green.txt')

Write-Host ''
Write-Host '--- summary lines (the child the driver has to react to) ---'
Write-Host ('unguarded      : ' + ($sumUnguarded -join ' | '))
Write-Host ('guarded_red    : ' + ($sumGuardedRed -join ' | '))
Write-Host ('guarded_green  : ' + ($sumGuardedGreen -join ' | '))
Write-Host '--- exit codes ---'
Write-Host ('unguarded      : {0}' -f $codeUnguarded)
Write-Host ('guarded_red    : {0}' -f $codeGuardedRed)
Write-Host ('guarded_green  : {0}' -f $codeGuardedGreen)
Write-Host ''

Check 'D10_the_unguarded_battery_really_swallows_a_red_step' `
    (($codeUnguarded -eq 0) -and (@($sumUnguarded | Where-Object { $_ -match 'EXIT 3' }).Count -ge 1)) `
    ("exit={0} while its own summary carries a failing step: {1} -- this is the pre-TASK-069 shape reproduced" -f $codeUnguarded, (@($sumUnguarded | Where-Object { $_ -match 'EXIT 3' }) -join ' | '))
Check 'D11_the_real_guard_turns_a_red_step_into_a_nonzero_exit' `
    (($codeGuardedRed -ne 0) -and (@($sumGuardedRed | Where-Object { $_ -match 'EXIT 3' }).Count -ge 1)) `
    ("exit={0} on the same input (the guard block is the only difference between this driver and demo_unguarded.ps1)" -f $codeGuardedRed)
Check 'D12_the_same_guard_exits_zero_when_nothing_is_red' `
    (($codeGuardedGreen -eq 0) -and (@($sumGuardedGreen | Where-Object { $_ -match 'EXIT [1-9]' }).Count -eq 0)) `
    ("exit={0} once the red step is green (the guard is not a constant: fail -> restore -> zero)" -f $codeGuardedGreen)
Check 'D13_the_two_guarded_drivers_differ_only_in_the_step' `
    ((& {
        param([string]$Text)
        $t = $Text -replace 'exit 3', 'exit 0'
        $t = $t -replace 'summary_guarded_red\.txt', 'SUMMARY_PATH'
        $t = $t -replace 'summary_guarded_green\.txt', 'SUMMARY_PATH'
        return $t
    } (Get-Content $guardedRed -Raw)) -ceq (& {
        param([string]$Text)
        $t = $Text -replace 'exit 3', 'exit 0'
        $t = $t -replace 'summary_guarded_red\.txt', 'SUMMARY_PATH'
        $t = $t -replace 'summary_guarded_green\.txt', 'SUMMARY_PATH'
        return $t
    } (Get-Content $guardedGreen -Raw))) `
    'the green leg is the red leg with exactly one substitution (plus its own summary file name), so the exit-code difference is attributable to the step and not to the guard text'
Check 'D14_no_demo_file_was_written_inside_the_repository' `
    ((-not $unguarded.StartsWith($RepoRoot)) -and (-not $guardedRed.StartsWith($RepoRoot)) -and (-not $guardedGreen.StartsWith($RepoRoot))) `
    ("the three drivers live under {0}; the repository is untouched by this demo" -f $OutRoot)

Write-Host ''
Write-Host ("DEMO FAILURES: {0}" -f $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
Write-Host 'TASK-069 EXIT-PROPAGATION FAILURE DEMO PASS (unguarded=0 with a red step, guarded-red non-zero, guarded-green=0)'
exit 0