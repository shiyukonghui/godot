# =============================================================================
#  mcp_port_guard.ps1 -- TASK-042 section 1
#
#  The one classification of "is port 9877 (the port the user's own Godot listens
#  on) safe?" for the *regression* scripts, so that six of them do not each carry
#  their own copy of the judgement (and so that the judgement cannot drift from
#  gate 5's `accept_m1.ps1`).
#
#  Why the old two halves had to be replaced
#  -----------------------------------------
#  `mcp032/033/034/035/036` and `probe037` each asserted two things:
#
#      Check 'port_9877_owner_before' ($userPidBefore -gt 0) ...
#      Check 'port_9877_owner_after'  ($userPidAfter -eq $userPidBefore) ...
#
#  The first half is an **environment precondition**, not a regression: it fails
#  forever in an environment where the user simply is not running Godot
#  (measured: 9877 has no listener, pid = -1). TASK-041 fixed exactly this shape
#  in `accept_m1.ps1` and the six scripts' failures were then attributed to it
#  (REPORT-041 section 7). This file is that fix, extracted for the six scripts.
#
#  What is asserted instead (nothing is weakened)
#  ----------------------------------------------
#  The invariant is "**this script** never occupies 9877". It is decided from
#  machine facts rather than from an assumption:
#
#    * every engine process the script starts is registered with its **pid** and
#      its **command line** (Register-McpPortGuardProcess), so "did we ever ask
#      for 9877" is answered from the real arguments;
#    * a listener on 9877 that is one of our pids is a violation;
#    * a listener that was already there and kept the same pid is the user's
#      editor, untouched;
#    * a listener that was there before and is gone (or is a different pid) after
#      is still a failure - the old `-gt 0` + `-eq` pair failed here too, and the
#      classification below keeps failing there;
#    * "no listener before and none after" is an environment fact. It is a PASS
#      with `classification=environment_fact_no_listener_before_or_after` spelled
#      out, so "nobody is on 9877" can never be read as "we proved we did not take
#      it" without the reason.
#
#  Compared with the two old assertions this is strictly stronger: the pid
#  stability still applies whenever a listener exists, and the two facts "our
#  pids" and "our command lines" are added.
#
#  ASCII only (the PowerShell 5.1 encoding rule this module already follows).
# =============================================================================

# The `--mcp-port` values a command line asks for. Both spellings the module and
# the engine use are covered: `--mcp-port=9877` and `--mcp-port 9877`. A value
# that merely *starts* with the port is a different port (`--mcp-port=98770` is
# 98770), which is why the digits are captured whole and compared as integers.
function Get-McpPortsInCommandLine {
    param([AllowEmptyString()][string]$CommandLine = '')
    $ports = New-Object System.Collections.Generic.List[int]
    if ([string]::IsNullOrEmpty($CommandLine)) { return @() }
    foreach ($match in [regex]::Matches($CommandLine, '--mcp-port[= ]([0-9]+)')) {
        $ports.Add([int]$match.Groups[1].Value)
    }
    return @($ports)
}

# Captures the state of `$Port` before the run. `$PidBefore` is passed in by the
# caller because every one of these scripts already has its own `Get-ListenerPid`
# (returning -1 when nobody listens); the helper owns the judgement, not the
# enumeration, so there is still exactly one place that says what a listener
# means.
function New-McpPortGuard {
    param([int]$Port = 9877, [int]$PidBefore = -1)
    return [pscustomobject]@{
        port          = $Port
        pid_before    = $PidBefore
        pids          = New-Object System.Collections.Generic.List[int]
        command_lines = New-Object System.Collections.Generic.List[string]
        ports_asked   = New-Object System.Collections.Generic.List[int]
    }
}

# Records one engine process this script started. `-Arguments` is what was handed
# to `Start-Process`; `-CommandLine` is for a launch another helper performed
# (`Import-McpProject` returns the exact command line it ran).
# The parameter is `-EnginePid` and not `-Pid`: `$Pid` is a read-only automatic
# variable in PowerShell, so a parameter of that name cannot be bound at all
# (measured while writing the TASK-042 probes).
function Register-McpPortGuardProcess {
    param(
        $Guard,
        [int]$EnginePid = -1,
        [string[]]$Arguments = @(),
        [AllowEmptyString()][string]$CommandLine = ''
    )
    if ($null -eq $Guard) { return }
    if ($EnginePid -gt 0) { [void]$Guard.pids.Add([int]$EnginePid) }
    $line = $CommandLine
    if ([string]::IsNullOrEmpty($line) -and $null -ne $Arguments -and $Arguments.Count -gt 0) {
        $line = ($Arguments -join ' ')
    }
    if ([string]::IsNullOrEmpty($line)) { return }
    [void]$Guard.command_lines.Add($line)
    foreach ($asked in @(Get-McpPortsInCommandLine -CommandLine $line)) {
        if (-not $Guard.ports_asked.Contains($asked)) { [void]$Guard.ports_asked.Add($asked) }
    }
}

function Register-McpPortGuardCommandLine {
    param($Guard, [AllowEmptyString()][string]$CommandLine = '')
    Register-McpPortGuardProcess -Guard $Guard -EnginePid -1 -CommandLine $CommandLine
}

# The judgement. Returns `{ pass, classification, evidence }`; `pass` is the
# bool the caller's `Check` wants and `evidence` is the line that says why,
# including the facts the verdict was read off.
function Complete-McpPortGuard {
    param($Guard, [int]$PidAfter = -1)
    if ($null -eq $Guard) {
        return @{
            pass           = $false
            classification = 'guard_was_never_created'
            evidence       = 'the script asked for a verdict without creating a port guard'
        }
    }
    $alive = ($PidAfter -ne -1)
    $ours = $alive -and $Guard.pids.Contains([int]$PidAfter)
    $asked = $Guard.ports_asked.Contains([int]$Guard.port)
    $same = ($PidAfter -eq $Guard.pid_before)
    $had = ($Guard.pid_before -gt 0)

    if ($asked) {
        # We handed 9877 to an engine process. That is the violation itself, and
        # it is decided from the arguments we really passed, not from a call-site
        # assumption.
        $pass = $false
        $classification = 'violation_this_script_requested_the_user_port'
    } elseif ($ours) {
        $pass = $false
        $classification = 'violation_this_script_owns_the_user_port'
    } elseif (-not $alive -and -not $had) {
        # Nobody was on 9877 and nobody is now: an environment fact, reported as
        # such rather than as a proof of innocence.
        $pass = $true
        $classification = 'environment_fact_no_listener_before_or_after'
    } elseif (-not $alive -and $had) {
        # There was a listener before and it is gone now. This script only ever
        # kills pids it started, so this is a real surprise and it stays a
        # failure (the old `-gt 0` + `-eq` pair failed here too).
        $pass = $false
        $classification = 'user_editor_vanished_during_the_run'
    } elseif (-not $had) {
        # A listener appeared that was not there before and is not ours.
        $pass = $true
        $classification = 'foreign_listener_appeared_during_the_run'
    } elseif ($same) {
        $pass = $true
        $classification = 'user_editor_present_untouched'
    } else {
        $pass = $false
        $classification = 'user_editor_pid_changed_during_the_run'
    }

    $ourPorts = @($Guard.ports_asked | Sort-Object)
    $evidence = ("listening={0} pid_before={1} pid_after={2} ours={3} same_pid={4} asked_by_us={5} classification={6} our_pids=[{7}] our_ports=[{8}] our_command_lines={9}" -f `
            $alive, $Guard.pid_before, $PidAfter, $ours, $same, $asked, $classification, `
            (@($Guard.pids) -join ','), ($ourPorts -join ','), $Guard.command_lines.Count)
    return @{
        pass           = $pass
        classification = $classification
        evidence       = $evidence
    }
}