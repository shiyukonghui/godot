# =============================================================================
#  mcp_watch_run.ps1 -- TASK-061 deterministic watcher (pure ASCII).
#
#  WHY THIS EXISTS (protocol repair, not an incident fix)
#  ------------------------------------------------------
#  In the round-2 breakout test (TASK-060) the observer finished while the
#  development was still running. Three design defects, all fixed here:
#    1. budget shorter than the work    -> a 25 min budget for a job that is
#                                          almost always longer ends by itself;
#    2. the stop condition was an agent's judgement, with no machine-checkable
#       stop reason;
#    3. the WAITING was done by agent-run sleep loops instead of a
#       deterministic process.
#  This script is defect 3's repair: it BLOCKS, it polls, it records, and it
#  can only end for one of three reasons, each of which is printed and filed.
#
#  STOP REASONS (all exit 0, so the caller must read the reason, not the code)
#  --------------------------------------------------------------------------
#    marker  : the completion marker exists            -> development finished
#    timeout : -TimeoutSec elapsed and no marker       -> forced stop
#    stale   : no new line for -StaleSec while active  -> development stuck
#
#  ACTIVITY MEASUREMENT
#  --------------------
#  One line is one newline-terminated record. Nothing localized is ever parsed:
#  the watcher counts lines and reads the `seq` field of each line with a plain
#  regex. `seq` is the server trace's own correlation key (mcp_trace.cpp:295 for
#  request lines, mcp_capture.cpp:609 for capture lines); files that have no
#  `seq` (e.g. the developer's PROGRESS.md heartbeat) still count by line, and
#  their last_seq simply stays 0. A trace path may be a literal path or a
#  wildcard pattern; a literal path that does not exist yet is reported as
#  MISSING and picked up as soon as it appears.
#
#  STALE POLICY (deliberate - see REPORT-061 section 3)
#  ----------------------------------------------------
#  `stale` is only eligible AFTER the first line has been observed. Before any
#  activity exists there is nothing to be stale relative to, so only `timeout`
#  can fire; otherwise a slow-starting developer would be mislabelled "stuck"
#  and the observer would exit early again - the exact defect being repaired.
#  Every log line prints `stale_ok` so the caller can see the eligibility.
#
#  WHEN TWO REASONS BECOME TRUE ON THE SAME POLL the order is
#  marker > timeout > stale. The budget is the outer bound, so it wins.
#
#  DISCIPLINE
#  ----------
#  No netstat, no localized output, no process is ever killed, port 9877 is
#  never touched (PLAYBOOK section 3). Read-only with respect to every input
#  file: the only writes are inside -OutDir.
#
#  USAGE
#  -----
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp_watch_run.ps1 `
#      -Marker  "%TEMP%\mcp-breakout\DEV-DONE.marker" `
#      -TracePath "%TEMP%\mcp-breakout\trace-editor.jsonl" `
#      -TracePath "%TEMP%\mcp-breakout\trace-game.jsonl" `
#      -TracePath "%TEMP%\mcp-breakout\PROGRESS.md" `
#      -TimeoutSec 4500 -StaleSec 300 -IntervalSec 30 `
#      -OutDir "%TEMP%\mcp-breakout\watch"
#
#  OUTPUTS (inside -OutDir)
#  ------------------------
#    watch.log           header + one status line per poll + STOP/DECISION lines
#    watch-summary.json  machine-readable summary of the whole run
#    watch-summary.txt   the same summary as key=value lines
#  Final stdout line (single line, machine readable):
#    WATCH_STOP stop_reason=... elapsed_sec=... polls=... last_seq=...
#               trace_lines=... trace_files=... stale_age_sec=...
#               watch_log=... summary=...
#
#  EXIT CODES: 0 for each of the three stop reasons; 2 for a usage/setup error
#  (a setup error is not a stop reason and must not be read as one).
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Marker,
    [Parameter(Mandatory = $true)][string[]]$TracePath,
    [Parameter(Mandatory = $true)][int]$TimeoutSec,
    [int]$StaleSec = 0,
    [int]$IntervalSec = 30,
    [Parameter(Mandatory = $true)][string]$OutDir
)

$ErrorActionPreference = 'Stop'
$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ReadChunkMax = 8388608

function Get-Stamp([datetime]$When) {
    return $When.ToString('yyyy-MM-dd HH:mm:ss', $InvariantCulture)
}

function Get-BoolInt([bool]$Value) {
    if ($Value) { return '1' }
    return '0'
}

function Add-LogLine([string]$Path, [string]$Line) {
    # UTF-8 without BOM, LF-only: evidence must survive a non-ASCII path or
    # message, and the repository stores text as LF (.gitattributes
    # `* text=auto eol=lf`), so LF on disk keeps the published sha256 of every
    # evidence file equal to the sha256 of its committed blob.
    [System.IO.File]::AppendAllText($Path, $Line + "`n", $Utf8NoBom)
}

function Resolve-TraceFiles([string[]]$Patterns) {
    $found = New-Object System.Collections.ArrayList
    foreach ($pattern in $Patterns) {
        if ($pattern -match '[*?]') {
            $hits = @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue)
            foreach ($hit in $hits) {
                if (-not $found.Contains($hit.FullName)) { [void]$found.Add($hit.FullName) }
            }
        } else {
            if (-not $found.Contains($pattern)) { [void]$found.Add($pattern) }
        }
    }
    return $found
}

$script:TraceStates = New-Object System.Collections.ArrayList

function Get-TraceState([string]$FullPath) {
    foreach ($state in $script:TraceStates) {
        if ($state.Full -eq $FullPath) { return $state }
    }
    $fresh = @{
        Full = $FullPath
        Lines = 0
        LastSeq = 0
        Offset = [int64]0
        Carry = ''
        NewLines = 0
        Missing = $true
        Error = ''
        Truncated = $false
    }
    [void]$script:TraceStates.Add($fresh)
    return $fresh
}

function Update-TraceState($State) {
    # Mutates the hashtable in place (hashtables are reference objects, so no
    # [ref] parameter is needed and none is used).
    $State.NewLines = 0
    $State.Missing = $true
    $State.Error = ''
    $path = [string]$State.Full

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $State.Missing = $false

    try {
        $stream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    } catch {
        $State.Error = 'open_failed'
        return
    }

    try {
        $length = [int64]$stream.Length
        if ($length -lt [int64]$State.Offset) {
            # The file was truncated or recreated: the counters must describe
            # the file that is actually there now, so start over.
            $State.Offset = [int64]0
            $State.Lines = 0
            $State.LastSeq = 0
            $State.Carry = ''
            $State.Truncated = $true
        }
        $remaining = $length - [int64]$State.Offset
        if ($remaining -le 0) { return }

        # The stream is opened fresh on every poll, so its position is 0: it
        # MUST be moved to the saved offset, otherwise the reader re-reads the
        # head of the file and reports the first line's `seq` forever (this was
        # a real defect, caught by the progressive-append scenario of
        # mcp061_watch_evidence.ps1 before TASK-061 was reported).
        [void]$stream.Seek([int64]$State.Offset, [System.IO.SeekOrigin]::Begin)

        $want = [int]$remaining
        if ($want -gt $ReadChunkMax) { $want = $ReadChunkMax }
        $buffer = New-Object byte[] $want
        $read = $stream.Read($buffer, 0, $want)
        if ($read -le 0) { return }
        $State.Offset = [int64]$State.Offset + [int64]$read

        $text = [string]$State.Carry + [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        $parts = $text.Split("`n")
        $complete = $parts.Length - 1
        if ($text.EndsWith("`n")) {
            $State.Carry = ''
        } else {
            $State.Carry = [string]$parts[$parts.Length - 1]
        }

        for ($i = 0; $i -lt $complete; $i++) {
            $line = ([string]$parts[$i]).TrimEnd("`r")
            $State.Lines = [int]$State.Lines + 1
            $State.NewLines = [int]$State.NewLines + 1
            # First `seq` token in the line wins: the server writes it as the
            # second field of a request line (`{"id":..,"seq":N,..}`) and as the
            # second field of a capture line (`{"event":"capture","seq":N,..}`),
            # both before any echoed argument text.
            $match = [regex]::Match($line, '"seq"\s*:\s*([0-9]+)')
            if ($match.Success) {
                $State.LastSeq = [int64]$match.Groups[1].Value
            }
        }
    } finally {
        $stream.Close()
        $stream.Dispose()
    }
}

# ------------------------------------------------------------------ setup ----
if ($TimeoutSec -lt 1) {
    Write-Host ('WATCH_ERROR error=timeout_sec_must_be_positive value=' + $TimeoutSec)
    exit 2
}
if ($IntervalSec -lt 1) { $IntervalSec = 1 }
if ($StaleSec -lt 0) { $StaleSec = 0 }
if ([string]::IsNullOrEmpty($OutDir)) {
    Write-Host 'WATCH_ERROR error=out_dir_required'
    exit 2
}
try {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
} catch {
    Write-Host ('WATCH_ERROR error=out_dir_not_creatable path=' + $OutDir)
    exit 2
}

$LogPath = Join-Path $OutDir 'watch.log'
$SummaryJson = Join-Path $OutDir 'watch-summary.json'
$SummaryTxt = Join-Path $OutDir 'watch-summary.txt'
$Started = Get-Date

Add-LogLine $LogPath ('# mcp_watch_run (TASK-061) start=' + $Started.ToString('o', $InvariantCulture))
Add-LogLine $LogPath ('# marker=' + $Marker)
Add-LogLine $LogPath ('# timeout_sec=' + $TimeoutSec + ' stale_sec=' + $StaleSec + ' interval_sec=' + $IntervalSec)
for ($i = 0; $i -lt $TracePath.Length; $i++) {
    Add-LogLine $LogPath ('# trace_path[' + $i + ']=' + $TracePath[$i])
}
Add-LogLine $LogPath ('# stale_sec=0 disables the stale reason; stale needs activity first (see header)')

# ------------------------------------------------------------------- loop ----
$polls = 0
$reason = ''
$markerSeen = $false
$activitySeen = $false
$lastActivity = $Started
$totalLines = 0
$lastSeq = [int64]0
$stopped = $Started
$elapsed = 0
$staleAge = 0
$staleEligible = $false
$tickNew = 0

while ($reason -eq '') {
    $now = Get-Date
    $elapsed = [int]($now - $Started).TotalSeconds
    $polls++

    $markerSeen = Test-Path -LiteralPath $Marker -PathType Leaf

    $files = Resolve-TraceFiles $TracePath
    $tickNew = 0
    $totalLines = 0
    $lastSeq = [int64]0
    $descriptions = New-Object System.Collections.ArrayList

    foreach ($file in $files) {
        $state = Get-TraceState ([string]$file)
        Update-TraceState $state
        $tickNew += [int]$state.NewLines
        $totalLines += [int]$state.Lines
        if ([int64]$state.LastSeq -gt $lastSeq) { $lastSeq = [int64]$state.LastSeq }

        $note = ''
        if ($state.Missing) { $note = ' MISSING' }
        if ($state.Error -ne '') { $note = $note + ' ERR=' + $state.Error }
        if ($state.Truncated) { $note = $note + ' TRUNCATED' }
        $leaf = Split-Path -Path ([string]$state.Full) -Leaf
        [void]$descriptions.Add('[' + $leaf + ' l=' + $state.Lines + ' s=' + $state.LastSeq + ' n=' + $state.NewLines + $note + ']')
    }

    if ($tickNew -gt 0) {
        $activitySeen = $true
        $lastActivity = $now
    }
    $staleAge = [int]($now - $lastActivity).TotalSeconds
    $staleEligible = (($StaleSec -gt 0) -and $activitySeen)

    if ($markerSeen) {
        $reason = 'marker'
    } elseif ($elapsed -ge $TimeoutSec) {
        $reason = 'timeout'
    } elseif ($staleEligible -and ($staleAge -ge $StaleSec)) {
        $reason = 'stale'
    }

    $statusLine = 't+' + $elapsed + 's ' + (Get-Stamp $now) +
        ' polls=' + $polls +
        ' marker=' + (Get-BoolInt $markerSeen) +
        ' files=' + $files.Count +
        ' lines=' + $totalLines +
        ' seq=' + $lastSeq +
        ' new=' + $tickNew +
        ' stale_age=' + $staleAge +
        ' stale_ok=' + (Get-BoolInt $staleEligible) +
        ' activity_seen=' + (Get-BoolInt $activitySeen) +
        ' ' + ($descriptions -join ' ')
    Add-LogLine $LogPath $statusLine
    Write-Host $statusLine

    if ($reason -eq '') {
        Start-Sleep -Seconds $IntervalSec
    }
}

$stopped = Get-Date
$elapsed = [int]($stopped - $Started).TotalSeconds
Add-LogLine $LogPath ('DECISION stop_reason=' + $reason + ' elapsed_sec=' + $elapsed + ' polls=' + $polls)
if ($reason -ne 'marker') {
    Add-LogLine $LogPath ('DECISION observation_stopped_before_development_ended=1 stop_reason=' + $reason)
}

# ---------------------------------------------------------------- summary ----
$traceRows = New-Object System.Collections.ArrayList
foreach ($state in $script:TraceStates) {
    $row = @{
        path = [string]$state.Full
        lines = [int]$state.Lines
        last_seq = [int64]$state.LastSeq
        last_new_lines = [int]$state.NewLines
        missing = [bool]$state.Missing
        error = [string]$state.Error
    }
    [void]$traceRows.Add($row)
}

$summary = @{
    script = 'mcp_watch_run.ps1'
    task = 'TASK-061'
    stop_reason = $reason
    exit_code = 0
    elapsed_sec = $elapsed
    polls = $polls
    started = $Started.ToString('o', $InvariantCulture)
    stopped = $stopped.ToString('o', $InvariantCulture)
    marker = $Marker
    marker_seen = $markerSeen
    timeout_sec = $TimeoutSec
    stale_sec = $StaleSec
    interval_sec = $IntervalSec
    activity_seen = $activitySeen
    stale_age_sec = $staleAge
    last_seq = $lastSeq
    trace_lines = $totalLines
    trace_files = $traceRows.Count
    observation_stopped_before_development_ended = [bool]($reason -ne 'marker')
    watch_log = $LogPath
    traces = $traceRows
}
# ConvertTo-Json emits CRLF; the repository stores text as LF, so the line
# endings are normalized here (content untouched) to keep the published sha256
# of this file equal to the sha256 of its committed blob.
$jsonText = ($summary | ConvertTo-Json -Depth 4).Replace("`r`n", "`n")
[System.IO.File]::WriteAllText($SummaryJson, $jsonText, $Utf8NoBom)

$txt = New-Object System.Collections.ArrayList
[void]$txt.Add('stop_reason=' + $reason)
[void]$txt.Add('exit_code=0')
[void]$txt.Add('elapsed_sec=' + $elapsed)
[void]$txt.Add('polls=' + $polls)
[void]$txt.Add('last_seq=' + $lastSeq)
[void]$txt.Add('trace_lines=' + $totalLines)
[void]$txt.Add('trace_files=' + $traceRows.Count)
[void]$txt.Add('marker=' + $Marker)
[void]$txt.Add('marker_seen=' + (Get-BoolInt $markerSeen))
[void]$txt.Add('timeout_sec=' + $TimeoutSec)
[void]$txt.Add('stale_sec=' + $StaleSec)
[void]$txt.Add('interval_sec=' + $IntervalSec)
[void]$txt.Add('activity_seen=' + (Get-BoolInt $activitySeen))
[void]$txt.Add('stale_age_sec=' + $staleAge)
[void]$txt.Add('observation_stopped_before_development_ended=' + (Get-BoolInt ($reason -ne 'marker')))
[void]$txt.Add('watch_log=' + $LogPath)
foreach ($row in $traceRows) {
    [void]$txt.Add('trace=' + $row.path + ' lines=' + $row.lines + ' last_seq=' + $row.last_seq + ' missing=' + (Get-BoolInt ([bool]$row.missing)))
}
[System.IO.File]::WriteAllText($SummaryTxt, (($txt -join "`n") + "`n"), $Utf8NoBom)

$stopLine = 'WATCH_STOP stop_reason=' + $reason +
    ' elapsed_sec=' + $elapsed +
    ' polls=' + $polls +
    ' last_seq=' + $lastSeq +
    ' trace_lines=' + $totalLines +
    ' trace_files=' + $traceRows.Count +
    ' stale_age_sec=' + $staleAge +
    ' watch_log=' + $LogPath +
    ' summary=' + $SummaryTxt
Add-LogLine $LogPath $stopLine
Write-Host $stopLine
exit 0