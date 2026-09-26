# =============================================================================
#  mcp042_port_guard_probes.ps1 -- TASK-042 section 1
#
#  Proves that the shared port guard (`mcp_port_guard.ps1`) is not a tautology:
#  every one of its classifications is reachable, the three violation classes
#  really FAIL, and the six regression scripts no longer contain the old
#  "a listener must exist on 9877" precondition.
#
#  Run:  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp042_port_guard_probes.ps1
#
#  ASCII only.
# =============================================================================

param(
    [string]$RepoRoot = '',
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')

if ([string]::IsNullOrEmpty($OutDir)) { $OutDir = Join-Path $env:TEMP 'mcp042-port-guard' }
if ([string]::IsNullOrEmpty($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

# --- the command-line parser ------------------------------------------------
$parsedEquals = @(Get-McpPortsInCommandLine -CommandLine '--headless -e --path C:\p --mcp-port=9877')
Check 'parser_equals_form' (($parsedEquals.Count -eq 1) -and ($parsedEquals[0] -eq 9877)) `
    ("'--mcp-port=9877' -> [{0}]" -f ($parsedEquals -join ','))
$parsedSpace = @(Get-McpPortsInCommandLine -CommandLine '--mcp-port 9877 --path C:\p')
Check 'parser_space_form' (($parsedSpace.Count -eq 1) -and ($parsedSpace[0] -eq 9877)) `
    ("'--mcp-port 9877' -> [{0}]" -f ($parsedSpace -join ','))
$parsedOther = @(Get-McpPortsInCommandLine -CommandLine '--mcp-port=9888 --mcp-port=9889')
Check 'parser_other_ports' (($parsedOther.Count -eq 2) -and ($parsedOther[0] -eq 9888) -and ($parsedOther[1] -eq 9889)) `
    ("'--mcp-port=9888 --mcp-port=9889' -> [{0}]" -f ($parsedOther -join ','))
$parsedPrefix = @(Get-McpPortsInCommandLine -CommandLine '--mcp-port=98770')
Check 'parser_does_not_confuse_98770_with_9877' (($parsedPrefix.Count -eq 1) -and ($parsedPrefix[0] -eq 98770)) `
    ("'--mcp-port=98770' -> [{0}] (a prefix match would be the classic false negative)" -f ($parsedPrefix -join ','))
$parsedNone = @(Get-McpPortsInCommandLine -CommandLine '--headless --path C:\p --import')
Check 'parser_no_port' ($parsedNone.Count -eq 0) ("no --mcp-port -> [{0}]" -f ($parsedNone -join ','))

# --- the six classifications ------------------------------------------------
# (1) environment fact: nobody before, nobody after.
$g = New-McpPortGuard -Port 9877 -PidBefore -1
Register-McpPortGuardProcess -Guard $g -EnginePid 11111 -Arguments @('--headless', '-e', '--path', 'C:\p', '--mcp-port=9888')
$r = Complete-McpPortGuard -Guard $g -PidAfter -1
Check 'class_environment_fact_passes' (($r.pass) -and ($r.classification -eq 'environment_fact_no_listener_before_or_after')) `
    $r.evidence

# (2) the user's editor was there and is untouched.
$g = New-McpPortGuard -Port 9877 -PidBefore 4242
Register-McpPortGuardProcess -Guard $g -EnginePid 11111 -Arguments @('--mcp-port=9888')
$r = Complete-McpPortGuard -Guard $g -PidAfter 4242
Check 'class_user_editor_untouched_passes' (($r.pass) -and ($r.classification -eq 'user_editor_present_untouched')) `
    $r.evidence

# (3) a foreign listener appeared during the run (not ours).
$g = New-McpPortGuard -Port 9877 -PidBefore -1
Register-McpPortGuardProcess -Guard $g -EnginePid 11111 -Arguments @('--mcp-port=9888')
$r = Complete-McpPortGuard -Guard $g -PidAfter 4242
Check 'class_foreign_listener_passes' (($r.pass) -and ($r.classification -eq 'foreign_listener_appeared_during_the_run')) `
    $r.evidence

# (4) VIOLATION: we asked an engine process for 9877.
$g = New-McpPortGuard -Port 9877 -PidBefore -1
Register-McpPortGuardProcess -Guard $g -EnginePid 11111 -Arguments @('--headless', '--mcp-port=9877')
$r = Complete-McpPortGuard -Guard $g -PidAfter -1
Check 'violation_requested_port_fails' ((-not $r.pass) -and ($r.classification -eq 'violation_this_script_requested_the_user_port')) `
    $r.evidence

# (5) VIOLATION: the listener now on 9877 is one of our pids.
$g = New-McpPortGuard -Port 9877 -PidBefore -1
Register-McpPortGuardProcess -Guard $g -EnginePid 11111 -Arguments @('--mcp-port=9888')
$r = Complete-McpPortGuard -Guard $g -PidAfter 11111
Check 'violation_our_pid_owns_port_fails' ((-not $r.pass) -and ($r.classification -eq 'violation_this_script_owns_the_user_port')) `
    $r.evidence

# (6) VIOLATION: the user's editor was there before and is gone after. This is
# the case gate 5's six-way form used to let through as an "environment fact";
# it is a failure here (and in gate 5 after TASK-042), so the alignment cannot
# be read as a relaxation of the old `-gt 0` + `-eq` pair.
$g = New-McpPortGuard -Port 9877 -PidBefore 4242
Register-McpPortGuardProcess -Guard $g -EnginePid 11111 -Arguments @('--mcp-port=9888')
$r = Complete-McpPortGuard -Guard $g -PidAfter -1
Check 'violation_user_editor_vanished_fails' ((-not $r.pass) -and ($r.classification -eq 'user_editor_vanished_during_the_run')) `
    $r.evidence

# (7) VIOLATION: a different pid owns 9877 now.
$g = New-McpPortGuard -Port 9877 -PidBefore 4242
Register-McpPortGuardProcess -Guard $g -EnginePid 11111 -Arguments @('--mcp-port=9888')
$r = Complete-McpPortGuard -Guard $g -PidAfter 4243
Check 'violation_user_editor_pid_changed_fails' ((-not $r.pass) -and ($r.classification -eq 'user_editor_pid_changed_during_the_run')) `
    $r.evidence

# (8) the port is a parameter, not a constant: a script that only ever used
# 9877 would pass probe (4) by accident if the check were hard-coded.
$g = New-McpPortGuard -Port 9877 -PidBefore -1
Register-McpPortGuardCommandLine -Guard $g -CommandLine 'C:\godot.exe --headless --path C:\p --mcp-port=9889'
$r = Complete-McpPortGuard -Guard $g -PidAfter -1
Check 'other_ports_are_not_reported_as_the_user_port' (($r.pass) -and ($r.classification -eq 'environment_fact_no_listener_before_or_after')) `
    $r.evidence

# (9) "we asked for 9877" is read from the command line, including a launch that
# was performed by another helper (`Import-McpProject` hands back its command).
$g = New-McpPortGuard -Port 9877 -PidBefore -1
Register-McpPortGuardCommandLine -Guard $g -CommandLine 'C:\godot.exe --headless --mcp-port=9877 --path C:\p --import'
$r = Complete-McpPortGuard -Guard $g -PidAfter -1
Check 'import_command_line_is_covered' ((-not $r.pass) -and ($r.classification -eq 'violation_this_script_requested_the_user_port')) `
    $r.evidence

# --- the six regression scripts carry no "a listener must exist" assertion ---
$scripts = @(
    'mcp032_d3_d4_d6_evidence.ps1',
    'mcp033_b5_animation_evidence.ps1',
    'mcp034_b5_audio_particle_theme_evidence.ps1',
    'mcp035_b5_tilemap_shader_physics_evidence.ps1',
    'mcp036_b5_navigation_theme_export_android_evidence.ps1',
    'probe037_d2_d1_r1r2.ps1'
)
foreach ($name in $scripts) {
    $path = Join-Path $PSScriptRoot $name
    $text = [IO.File]::ReadAllText($path)
    $oldBefore = $text.Contains("port_9877_owner_before' (`$userPidBefore -gt 0)") -or $text.Contains("port_9877_guard_before' (`$guardBefore -gt 0)")
    $hasGuard = $text.Contains('New-McpPortGuard') -and $text.Contains('Complete-McpPortGuard')
    $hasDotSource = $text.Contains('mcp_port_guard.ps1')
    Check ("aligned_{0}" -f $name) ((-not $oldBefore) -and $hasGuard -and $hasDotSource) `
        ("old 'must exist' before-assertion present={0}; dot-sources the guard={1}; uses New/Complete={2}" -f $oldBefore, $hasDotSource, $hasGuard)
}

# --- gate 5 and the guard share the classification set ----------------------
# The gate script has its own inline copy (TASK-041); adding the "vanished"
# class to it keeps the two in step, and this probe fails if that drifts.
$gatePath = Join-Path $PSScriptRoot 'accept_m1.ps1'
$gateText = [IO.File]::ReadAllText($gatePath)
Check 'gate5_knows_the_vanished_classification' ($gateText.Contains('user_editor_vanished_during_the_run')) `
    'accept_m1.ps1 carries the same classification for "a listener was there before and is gone after"'

$failed = @($script:Checks | Where-Object { -not $_.pass })
Write-Host ''
Write-Host ('TASK-042 port guard probes: {0} checks, {1} failed' -f $script:Checks.Count, $failed.Count)
$summary = [pscustomobject]@{
    engine       = ''
    head         = (& git -C $RepoRoot rev-parse --short HEAD) -join ''
    checks       = $script:Checks
    failed_count = $failed.Count
}
[IO.File]::WriteAllBytes((Join-Path $OutDir 'mcp042-port-guard-checks.json'), (New-Object Text.UTF8Encoding($false)).GetBytes((ConvertTo-Json -InputObject $summary -Depth 8)))
Write-Host ("checks: {0}" -f (Join-Path $OutDir 'mcp042-port-guard-checks.json'))
if ($failed.Count -gt 0) { exit 1 }
exit 0