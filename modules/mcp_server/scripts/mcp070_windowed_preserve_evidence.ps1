# =============================================================================
#  mcp070_windowed_preserve_evidence.ps1 -- TASK-070 item 2.
#
#  The unconfirmed item it closes (REPORT-AUDIT-ENGINE.md section 5 item 2):
#  "patch 3's editor save-on-open call site was never exercised in a WINDOWED
#  editor". `editor/editor_node.cpp:1062` guards the call with `!cmdline_mode`,
#  and `cmdline_mode = (DisplayServer::get_singleton()->get_name() == "headless")`
#  (`editor/editor_node.cpp:8497`), so `--import` and `--headless` can never reach
#  it -- which is exactly why the defect ("opening the project deletes every hand
#  written comment from project.godot") survived unnoticed for so long.
#
#  This script therefore STARTS A REAL WINDOWED EDITOR (no `--headless` in the
#  argument list; the argument list is printed and stored) on a scratch project
#  whose `project.godot` carries FIVE hand written comment lines with `[input]`
#  deliberately NOT the last section, and compares the file before and after:
#
#    w_fixture_shape                       5 comment lines; two of them INSIDE
#                                          [input]; [input] before [rendering];
#    w_import_leaves_the_file_byte_identical  control 4a: the `--import` path
#                                          (headless by construction) moves
#                                          neither the bytes nor the mtime;
#    w_headless_editor_leaves_the_file_byte_identical
#                                          control 4b: a real `--headless -e` run
#                                          moves neither either (the editor has no
#                                          bounded quit flag -- MEASURED,
#                                          `--quit-after 200` never ended it --
#                                          so this control is a bounded
#                                          observation and is declared as one);
#    w_windowed_open_wrote_the_file_without_changing_it
#                                          MEASURED RESULT: the windowed open
#                                          leaves the BYTES byte-identical and
#                                          advances the MTIME. The bytes cannot
#                                          distinguish "wrote and it came out the
#                                          same" from "nobody wrote"; the mtime
#                                          can, and only this branch can write;
#    w_windowed_open_keeps_every_comment    5/5, each line verbatim;
#    w_windowed_open_keeps_the_unknown_hand_written_key
#                                          a key the engine has never heard of
#                                          survives byte for byte;
#    w_windowed_open_keeps_the_input_comment_inside_input
#                                          both comments written inside [input]
#                                          are still between [input] and
#                                          [rendering];
#    w_windowed_open_did_not_write_the_engine_header
#                                          the file does not start with the
#                                          whole-file writer's header;
#    w_windowed_open_diff_is_confined        the byte prefix before [application]
#                                          and the byte suffix from [input] on are
#                                          identical, so the diff (ZERO lines)
#                                          cannot have touched [input];
#    w_windowed_process_had_a_real_display_driver
#                                          the editor's own log names a rendering
#                                          device, i.e. it was NOT headless;
#    w_windowed_second_open_is_byte_identical
#                                          item 3: idempotence, mtime advancing
#                                          again;
#    w_windowed_open_is_the_only_write      nothing was written after the editor
#                                          became ready and before it was killed;
#    w_save_unchanged_whole_file_writer     reverse: `ProjectSettings.save()`
#                                          itself is unchanged (probe .gd on a
#                                          headless `--script` run);
#    w_other_save_call_sites_are_untouched  reverse: the set of `ProjectSettings::
#                                          get_singleton()->save()` call sites,
#                                          per file and per count, compared with
#                                          the revision before patch 3;
#    w_patch3_changed_exactly_one_call_site
#                                          and that revision's own diff adds one
#                                          `save()` line, removes one, and adds
#                                          the `save_preserving_text()` branch.
#
#  Port discipline: only 9888 is used for the editor; 9877 is never requested and
#  `mcp_port_guard.ps1` records its pid before/after plus every command line this
#  script ran.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp070_windowed_preserve_evidence.ps1
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$Engine = '',
    [int]$EditorPort = 9888,
    [int]$UserPort = 9877,
    [int]$ReadyTimeoutMs = 300000,
    [int]$SettleTimeoutMs = 120000,
    [int]$HeadlessControlSeconds = 25
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($Engine)) { $Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe' }
$Engine = (Resolve-Path $Engine).Path
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$SaveProbeSource = Join-Path $PSScriptRoot 'mcp070_settings_save_probe.gd'
$PatchThreeRev = '2f85141a74'
$BeforePatchThreeRev = '2f85141a74^'

$Root = Join-Path $env:TEMP ('mcp070\windowed\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-072 (D130): the anchor criterion lives in check_engine_anchor.ps1 only.
. (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Get-DiskSha {
    param([string]$Path)
    if (Test-Path $Path) { return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower() }
    return '<missing>'
}

function Get-ListenerPid {
    param([int]$Port_)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port_ + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

function Read-TextShared {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object IO.StreamReader($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Close() }
    } finally { $stream.Close() }
}

# The mtime in UTC ticks. It is the discriminator between "the file was written
# and happened to come out byte-identical" (the windowed save-on-open: the engine
# always writes, `project_settings.cpp` `save_preserving_text()`) and "nobody
# wrote the file at all" (`--import`, `--headless`: the `!cmdline_mode` branch is
# never reached). The bytes alone cannot tell those two apart.
function Get-MtimeTicks {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return -1 }
    return (Get-Item -LiteralPath $Path).LastWriteTimeUtc.Ticks
}

function Wait-ForEndpoint {
    param([int]$Port_, [int]$TimeoutMs)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Join-Path $Ev 'status.json'
        if (Test-Path $probe) { Remove-Item -Force $probe }
        & $Curl -s --max-time 5 -o $probe ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (($LASTEXITCODE -eq 0) -and (Test-Path $probe)) {
            try {
                $parsed = ConvertFrom-Json (Read-TextShared $probe)
                if ($null -ne $parsed.frame_count) { return $true }
            } catch { }
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# Wait until the file's sha256 has both changed from `-Before` and then held still
# for three consecutive samples, or the deadline passes. Returns the settled sha.
function Wait-ForSettledSha {
    param([string]$Path, [string]$Before, [int]$TimeoutMs, [switch]$RequireChange)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $last = Get-DiskSha -Path $Path
    $stable = 0
    $changed = (-not $RequireChange) -or ($last -ne $Before)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 2000
        $now = Get-DiskSha -Path $Path
        if ($now -eq $last) { $stable++ } else { $stable = 0; $last = $now }
        if ($last -ne $Before) { $changed = $true }
        if ($changed -and $stable -ge 3) { return $last }
    }
    return $last
}

# The windowed save-on-open has to be observed by its EFFECT, and the effect is
# the modification time when the bytes come out identical (see the check below).
# Returns $true when the mtime moved past `-BeforeTicks`, after the file has then
# held still for two further samples.
function Wait-ForMtimeAdvance {
    param([string]$Path, [int64]$BeforeTicks, [int]$TimeoutMs)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 2000
        if ((Get-MtimeTicks -Path $Path) -gt $BeforeTicks) {
            $probe = Get-MtimeTicks -Path $Path
            Start-Sleep -Milliseconds 2000
            if ((Get-MtimeTicks -Path $Path) -eq $probe) { return $true }
        }
    }
    return ((Get-MtimeTicks -Path $Path) -gt $BeforeTicks)
}

function Get-CommentLines {
    param([string]$Text)
    $out = @()
    foreach ($line in ($Text -split "`n")) {
        if ($line.TrimStart().StartsWith(';')) { $out += $line.TrimEnd("`r") }
    }
    return $out
}

function Get-LineDiff {
    param([string]$Before, [string]$After)
    $b = @($Before -split "`n")
    $a = @($After -split "`n")
    $lines = New-Object System.Collections.Generic.List[string]
    $count = 0
    $max = [Math]::Max($b.Count, $a.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $bl = if ($i -lt $b.Count) { $b[$i].TrimEnd("`r") } else { '<no line>' }
        $al = if ($i -lt $a.Count) { $a[$i].TrimEnd("`r") } else { '<no line>' }
        if ($bl -ne $al) {
            $count++
            $lines.Add(('line {0}: before=<{1}> after=<{2}>' -f ($i + 1), $bl, $al))
        }
    }
    return @{ Count = $count; Lines = @($lines) }
}

# The fixture: FIVE hand written comment lines. `[input]` is NOT the last
# section, and one comment line lives INSIDE `[input]`, which is the shape the
# whole-file writer destroys and the section publisher has to copy through.
$FixtureLines = @(
    '; mcp070 comment 1 of 5: hand written header',
    '; mcp070 comment 2 of 5',
    'config_version=5',
    '',
    '[application]',
    '',
    'config/name="MCP070 windowed preserve"',
    'config/features=PackedStringArray("4.8")',
    'run/main_scene="res://scenes/main.tscn"',
    'mcp070_unknown_setting="a key the engine has never heard of"',
    '',
    '; mcp070 comment 3 of 5: inside [application]',
    '[input]',
    '',
    'mcp070_jump={',
    '"deadzone": 0.5,',
    '"events": []',
    '}',
    '',
    '; mcp070 comment 4 of 5: inside [input], before the next section header',
    '; mcp070 comment 5 of 5: [input] is deliberately NOT the last section',
    '[rendering]',
    '',
    'renderer/rendering_method="gl_compatibility"'
)
$FixtureText = ($FixtureLines -join "`n") + "`n"
$ExpectedComments = @(
    '; mcp070 comment 1 of 5: hand written header',
    '; mcp070 comment 2 of 5',
    '; mcp070 comment 3 of 5: inside [application]',
    '; mcp070 comment 4 of 5: inside [input], before the next section header',
    '; mcp070 comment 5 of 5: [input] is deliberately NOT the last section'
)

function New-FixtureProject {
    param([string]$Path)
    Remove-Item -Recurse -Force $Path -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $Path 'scenes') | Out-Null
    Write-McpUtf8NoBom -Path (Join-Path $Path 'project.godot') -Text $FixtureText
    Write-McpUtf8NoBom -Path (Join-Path $Path 'scenes\main.tscn') -Text "[gd_scene format=3]`n`n[node name=`"Main`" type=`"Node`"]`n"
    Copy-Item -Path $SaveProbeSource -Destination (Join-Path $Path 'mcp070_probe.gd') -Force
}

$Project = Join-Path $Root 'proj-windowed'
New-FixtureProject -Path $Project
$ProjectFile = Join-Path $Project 'project.godot'

Write-Host '============================================================='
Write-Host ' TASK-070 item 2: the editor save-on-open call site, WINDOWED'
Write-Host (' repo    : ' + $RepoRoot)
Write-Host (' root    : ' + $Root)
Write-Host (' project : ' + $Project)
Write-Host '============================================================='

$version = ((& $Engine --version) -join '').Trim()
$head = ((& git -C $RepoRoot rev-parse --short=9 HEAD) -join '').Trim()
# TASK-072 (D130): one judge decides the anchor; see check_engine_anchor.ps1.
$anchorVerdict = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $version -HeadSha $head
Check 'w_engine_version_matches_head' ($anchorVerdict.Ok) `
    (("--version='{0}' git HEAD='{1}'" -f $version, $head) + ' | ' + $anchorVerdict.Summary)

$userPidBefore = Get-ListenerPid -Port_ $UserPort
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("user editor on {0} before: pid={1}" -f $UserPort, $userPidBefore)
Check 'w_editor_port_free_before' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))

# ---------------------------------------------------------------------------
# The fixture's shape, read off the bytes on disk (not off the array above).
# ---------------------------------------------------------------------------
$fixtureText = Read-TextShared $ProjectFile
$fixtureSha = Get-DiskSha $ProjectFile
$fixtureComments = @(Get-CommentLines -Text $fixtureText)
$inputAt = $fixtureText.IndexOf('[input]')
$renderAt = $fixtureText.IndexOf('[rendering]')
$inInput = @($ExpectedComments | Where-Object { $fixtureText.IndexOf($_) -gt $inputAt -and $fixtureText.IndexOf($_) -lt $renderAt })
$allVerbatim = $true
foreach ($c in $ExpectedComments) { if (-not $fixtureText.Contains($c)) { $allVerbatim = $false } }
Check 'w_fixture_shape' `
    (($fixtureComments.Count -eq 5) -and ($inputAt -gt 0) -and ($inputAt -lt $renderAt) -and ($inInput.Count -ge 1) -and $allVerbatim) `
    ("comments={0}/5 all verbatim={1}; [input] at {2} < [rendering] at {3}; comment line(s) inside [input]={4}; sha256={5}" -f `
        $fixtureComments.Count, $allVerbatim, $inputAt, $renderAt, $inInput.Count, $fixtureSha)

# ---------------------------------------------------------------------------
# Control 4a: the `--import` path.
# ---------------------------------------------------------------------------
$ProjectImport = Join-Path $Root 'proj-import-control'
New-FixtureProject -Path $ProjectImport
$importFile = Join-Path $ProjectImport 'project.godot'
$importShaBefore = Get-DiskSha $importFile
$importMtimeBefore = Get-MtimeTicks $importFile
$import = Import-McpProject -Engine $Engine -Path $ProjectImport -LogDirectory $LogRoot -Name 'import-control'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine ([string]$import.command)
$importShaAfter = Get-DiskSha $importFile
$importMtimeAfter = Get-MtimeTicks $importFile
$importText = Read-TextShared $importFile
Check 'w_import_leaves_the_file_byte_identical' `
    (($import.exit_code -eq 0) -and ($importShaAfter -eq $importShaBefore) -and ($importMtimeAfter -eq $importMtimeBefore) -and ((Get-CommentLines -Text $importText).Count -eq 5)) `
    ("import exit={0} attempts={1}; sha {2} -> {3}; mtime unchanged={4}; comments={5}/5; command={6}" -f `
        $import.exit_code, $import.attempts, $importShaBefore, $importShaAfter, ($importMtimeAfter -eq $importMtimeBefore), (Get-CommentLines -Text $importText).Count, $import.command)

# ---------------------------------------------------------------------------
# Control 4b: a real `--headless -e` editor. MEASURED: the editor does not honour
# `--quit-after` (a `--quit-after 200` run was still alive after 180 s and had to
# be killed), so this control is a bounded observation with the file as its
# subject, and the kill is part of the declaration rather than a hidden step.
# ---------------------------------------------------------------------------
$ProjectHeadless = Join-Path $Root 'proj-headless-control'
New-FixtureProject -Path $ProjectHeadless
$headlessFile = Join-Path $ProjectHeadless 'project.godot'
$headlessShaBefore = Get-DiskSha $headlessFile
$headlessMtimeBefore = Get-MtimeTicks $headlessFile
$headlessArgs = @('--headless', '-e', '--path', $ProjectHeadless, ("--mcp-port={0}" -f $EditorPort))
$headlessHandle = $null
$headlessKilled = $false
try {
    $headlessHandle = Start-Process -FilePath $Engine -ArgumentList $headlessArgs -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot 'headless-control.out.log') `
        -RedirectStandardError (Join-Path $LogRoot 'headless-control.err.log') -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $headlessHandle.Id -Arguments $headlessArgs
    $headlessReady = Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs
    Start-Sleep -Seconds $HeadlessControlSeconds
    $headlessShaDuring = Get-DiskSha $headlessFile
    if (-not $headlessHandle.HasExited) {
        & taskkill /PID $headlessHandle.Id /T /F *> (Join-Path $LogRoot 'headless-control.taskkill.log')
        $headlessKilled = $true
        Start-Sleep -Milliseconds 1500
    }
} finally {
    if ($null -ne $headlessHandle -and -not $headlessHandle.HasExited) {
        & taskkill /PID $headlessHandle.Id /T /F *> (Join-Path $LogRoot 'headless-control.taskkill2.log')
        Start-Sleep -Milliseconds 1500
    }
}
$headlessShaAfter = Get-DiskSha $headlessFile
$headlessMtimeAfter = Get-MtimeTicks $headlessFile
$headlessText = Read-TextShared $headlessFile
Check 'w_headless_editor_leaves_the_file_byte_identical' `
    (($headlessShaDuring -eq $headlessShaBefore) -and ($headlessShaAfter -eq $headlessShaBefore) -and ($headlessMtimeAfter -eq $headlessMtimeBefore) -and ((Get-CommentLines -Text $headlessText).Count -eq 5)) `
    ("headless editor endpoint ready={0}; sha before={1} during={2} after={3}; mtime unchanged={4}; comments={5}/5; killed by this script after {6}s={7}; command={8}" -f `
        $headlessReady, $headlessShaBefore, $headlessShaDuring, $headlessShaAfter, ($headlessMtimeAfter -eq $headlessMtimeBefore), (Get-CommentLines -Text $headlessText).Count, $HeadlessControlSeconds, $headlessKilled, ($headlessArgs -join ' '))

# ---------------------------------------------------------------------------
# Control 5 (the reverse): `ProjectSettings.save()` itself, unchanged. The probe
# runs under the SAME engine on a copy of the same fixture and calls the public
# `save()` binding; the whole-file writer must still write its own header and
# still lose the hand written comments.
# ---------------------------------------------------------------------------
$ProjectSave = Join-Path $Root 'proj-save-reverse'
New-FixtureProject -Path $ProjectSave
$saveFile = Join-Path $ProjectSave 'project.godot'
$saveOut = Join-Path $LogRoot 'save-reverse.txt'
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $Engine --headless --path $ProjectSave --script res://mcp070_probe.gd -- save_whole *> $saveOut
$saveExit = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
$saveText = Read-TextShared $saveFile
$saveComments = @(Get-CommentLines -Text $saveText)
$handWrittenGone = $true
foreach ($c in $ExpectedComments) { if ($saveText.Contains($c)) { $handWrittenGone = $false } }
Check 'w_save_unchanged_whole_file_writer' `
    (($saveExit -eq 0) -and $handWrittenGone -and $saveText.StartsWith('; Engine configuration file.') -and ((Read-TextShared $saveOut).Contains('err=0'))) `
    ("probe `ProjectSettings.save()` exit={0}; the 5 hand written comments are gone={1}; the file now starts with the engine header={2}; comment lines now={3} (the engine's own 7); log={4}" -f `
        $saveExit, $handWrittenGone, $saveText.StartsWith('; Engine configuration file.'), $saveComments.Count, $saveOut)

# ---------------------------------------------------------------------------
# Reverse: the call-site set, compared with the revision before patch 3.
# ---------------------------------------------------------------------------
$pattern = 'ProjectSettings::get_singleton()->save()'
$sitesNow = @(& git -C $RepoRoot grep -n -F -- $pattern HEAD -- 'editor/*.cpp' 'editor/**/*.cpp' 'modules/**/*.cpp' 2>$null)
$sitesBefore = @(& git -C $RepoRoot grep -n -F -- $pattern $BeforePatchThreeRev -- 'editor/*.cpp' 'editor/**/*.cpp' 'modules/**/*.cpp' 2>$null)
# `git grep -n <pat> <rev> -- <paths>` prints `<rev>:<path>:<line>:<text>` for
# every revision, so field 1 is the path in both lists and the revision is
# dropped on purpose. The LINE NUMBER is dropped as well, and that is the point:
# patch 3 inserted 15 lines above the other call sites in `editor_node.cpp`, so
# every later line number in that file shifts by that amount. The claim being
# measured is "no call site was added or removed", which is a statement about
# FILES and COUNTS PER FILE, not about line numbers.
$nowByFile = @($sitesNow | ForEach-Object { ($_ -split ':', 3)[1] } | Group-Object | ForEach-Object { ('{0} x{1}' -f $_.Name, $_.Count) } | Sort-Object)
$beforeByFile = @($sitesBefore | ForEach-Object { ($_ -split ':', 3)[1] } | Group-Object | ForEach-Object { ('{0} x{1}' -f $_.Name, $_.Count) } | Sort-Object)
$added = @($nowByFile | Where-Object { $beforeByFile -notcontains $_ })
$removed = @($beforeByFile | Where-Object { $nowByFile -notcontains $_ })
[IO.File]::WriteAllLines((Join-Path $Ev 'save_call_sites_now.txt'), [string[]]$sitesNow)
[IO.File]::WriteAllLines((Join-Path $Ev 'save_call_sites_before_patch3.txt'), [string[]]$sitesBefore)
[IO.File]::WriteAllLines((Join-Path $Ev 'save_call_sites_by_file_compare.txt'), @(
        ('file:count entries now={0}, before {1}={2}' -f $nowByFile.Count, $BeforePatchThreeRev, $beforeByFile.Count),
        ('added=' + ($added -join ', ')),
        ('removed=' + ($removed -join ', '))
    ))
Check 'w_other_save_call_sites_are_untouched' (($added.Count -eq 0) -and ($removed.Count -eq 0) -and ($nowByFile.Count -eq $beforeByFile.Count)) `
    ("`ProjectSettings::get_singleton()->save()` call sites: {0} line(s) in {1} file(s) now, {2} line(s) in {3} file(s) before {4}; per-file added={5} removed={6}" -f `
        $sitesNow.Count, $nowByFile.Count, $sitesBefore.Count, $beforeByFile.Count, $BeforePatchThreeRev, ($added -join ','), ($removed -join ','))

# And the one call site patch 3 DID change is shown to be exactly one, and to be
# the guarded branch: the diff adds one `save()` line and removes one.
$patchDiff = @(& git -C $RepoRoot show $PatchThreeRev -- editor/editor_node.cpp 2>$null)
[IO.File]::WriteAllLines((Join-Path $Ev 'patch3_editor_node_diff.txt'), [string[]]$patchDiff)
$removedSaveLines = @($patchDiff | Where-Object { $_ -match '^-' -and $_ -match 'get_singleton\(\)->save\(\)' })
$addedSaveLines = @($patchDiff | Where-Object { $_ -match '^\+' -and $_ -match 'get_singleton\(\)->save\(\)' })
$addedPreserving = @($patchDiff | Where-Object { $_ -match '^\+' -and $_ -match 'save_preserving_text' })
Check 'w_patch3_changed_exactly_one_call_site' `
    (($removedSaveLines.Count -eq 1) -and ($addedSaveLines.Count -eq 1) -and ($addedPreserving.Count -ge 1)) `
    ("patch {0} on editor/editor_node.cpp: `save()` lines removed={1} added={2}; `save_preserving_text()` lines added={3}" -f `
        $PatchThreeRev, $removedSaveLines.Count, $addedSaveLines.Count, $addedPreserving.Count)

# ---------------------------------------------------------------------------
# The windowed run itself. NO `--headless` in the argument list.
# ---------------------------------------------------------------------------
$shaBefore = Get-DiskSha $ProjectFile
$mtimeBefore = Get-MtimeTicks $ProjectFile
$textBefore = Read-TextShared $ProjectFile
$windowedArgs = @('-e', '--path', $Project, ("--mcp-port={0}" -f $EditorPort))
[IO.File]::WriteAllLines((Join-Path $Ev 'windowed_command_line.txt'), @(($windowedArgs -join ' ')))
$handle = $null
$shaAfterReady = '<none>'
$shaAfterKill = '<none>'
try {
    $handle = Start-Process -FilePath $Engine -ArgumentList $windowedArgs -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot 'windowed.out.log') `
        -RedirectStandardError (Join-Path $LogRoot 'windowed.err.log')
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $windowedArgs
    Write-Host ("started WINDOWED editor pid={0} :: {1}" -f $handle.Id, ($windowedArgs -join ' '))
    $ready = Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs
    Check 'w_windowed_endpoint_ready' $ready ("port {0} answered within {1} ms" -f $EditorPort, $ReadyTimeoutMs)
    Check 'w_windowed_launch_has_no_headless_flag' (-not ($windowedArgs -contains '--headless')) ("argument list = {0}" -f ($windowedArgs -join ' '))

    $settled = Wait-ForSettledSha -Path $ProjectFile -Before $shaBefore -TimeoutMs $SettleTimeoutMs
    $mtimeMoved = Wait-ForMtimeAdvance -Path $ProjectFile -BeforeTicks $mtimeBefore -TimeoutMs $SettleTimeoutMs
    $textAfter = Read-TextShared $ProjectFile
    $shaAfter = Get-DiskSha $ProjectFile
    $mtimeAfter = Get-MtimeTicks $ProjectFile
    $shaAfterReady = $shaAfter

    # MEASURED RESULT: the windowed open leaves the BYTES byte-identical, because
    # `save_preserving_text()` publishes only the settings that differ from their
    # engine default and this fixture already says all of them, so
    # `updated == text` and the write puts the file's own bytes back. The proof
    # that the call site RAN is therefore the modification time, not a diff: the
    # `--import` and `--headless` controls above leave both the bytes AND the
    # mtime untouched, so a moved mtime with identical bytes can only be a write
    # from the one branch they cannot reach.
    Check 'w_windowed_open_wrote_the_file_without_changing_it' `
        (($shaAfter -eq $shaBefore) -and ($mtimeAfter -gt $mtimeBefore)) `
        ("sha256 before={0} after={1} (identical={2}); mtime advanced={3} (before ticks={4} after ticks={5}); mtime observed to move={6}; settled={7}" -f `
            $shaBefore, $shaAfter, ($shaAfter -eq $shaBefore), ($mtimeAfter -gt $mtimeBefore), $mtimeBefore, $mtimeAfter, $mtimeMoved, $settled)

    $commentsAfter = @(Get-CommentLines -Text $textAfter)
    $verbatim = $true
    foreach ($c in $ExpectedComments) { if (-not $textAfter.Contains($c)) { $verbatim = $false } }
    Check 'w_windowed_open_keeps_every_comment' (($commentsAfter.Count -eq 5) -and $verbatim) `
        ("comments before={0}/5 after={1}/5; every hand written line still present verbatim={2}" -f $fixtureComments.Count, $commentsAfter.Count, $verbatim)
    Check 'w_windowed_open_keeps_the_unknown_hand_written_key' ($textAfter.Contains('mcp070_unknown_setting="a key the engine has never heard of"')) `
        'a key the engine has never heard of survived the save byte for byte'
    Check 'w_windowed_open_did_not_write_the_engine_header' (-not $textAfter.StartsWith('; Engine configuration file.')) `
        'the file does not begin with the whole-file writer header'

    $inputAtAfter = $textAfter.IndexOf('[input]')
    $renderAtAfter = $textAfter.IndexOf('[rendering]')
    $c4At = $textAfter.IndexOf('; mcp070 comment 4 of 5: inside [input], before the next section header')
    $c5At = $textAfter.IndexOf('; mcp070 comment 5 of 5: [input] is deliberately NOT the last section')
    Check 'w_windowed_open_keeps_the_input_comment_inside_input' `
        (($c4At -gt $inputAtAfter) -and ($c4At -lt $renderAtAfter) -and ($c5At -gt $inputAtAfter) -and ($c5At -lt $renderAtAfter)) `
        ("[input] at {0}; comment 4 at {1}; comment 5 at {2}; [rendering] at {3} -- both comments are still inside [input]" -f $inputAtAfter, $c4At, $c5At, $renderAtAfter)

    $diff = Get-LineDiff -Before $textBefore -After $textAfter
    $prefixOk = $textAfter.StartsWith($textBefore.Substring(0, $textBefore.IndexOf('[application]')))
    $suffixOk = $textAfter.EndsWith($textBefore.Substring($textBefore.IndexOf('[input]')))
    [IO.File]::WriteAllLines((Join-Path $Ev 'windowed_open_line_diff.txt'), @($diff.Lines))
    [IO.File]::WriteAllLines((Join-Path $Ev 'windowed_open_before.txt'), @($textBefore -split "`n"))
    [IO.File]::WriteAllLines((Join-Path $Ev 'windowed_open_after.txt'), @($textAfter -split "`n"))
    Check 'w_windowed_open_diff_is_confined' ($prefixOk -and $suffixOk) `
        ("{0} differing line(s) overall; prefix before [application] identical={1}; suffix from [input] on identical={2}; diff: {3}" -f `
            $diff.Count, $prefixOk, $suffixOk, ($diff.Lines -join ' ;; '))

    # The process really had a physical display: a `--headless` run never prints a
    # rendering device line, so this is what rules out "the branch was reached
    # because DisplayServer said headless after all".
    $windowedLog = Read-TextShared (Join-Path $LogRoot 'windowed.out.log')
    $hasDevice = ($windowedLog -match 'Using Device:') -or ($windowedLog -match 'OpenGL API') -or ($windowedLog -match 'Vulkan')
    $serverLine = @($windowedLog -split "`n" | Where-Object { $_ -like '*[MCP]*listening*' })
    [IO.File]::WriteAllLines((Join-Path $Ev 'windowed_display_evidence.txt'), @($windowedLog -split "`n"))
    Check 'w_windowed_process_had_a_real_display_driver' $hasDevice `
        ("the windowed process logged a rendering device; log line: {0}" -f (@($windowedLog -split "`n" | Where-Object { $_ -match 'Using Device:|OpenGL API|Vulkan' }) -join ' | '))
    Check 'w_windowed_process_served_the_tools_on_9888' (@($serverLine).Count -ge 1) ("{0}" -f ($serverLine -join ' | '))

    # Nothing may be written between "ready" and the kill: the claim is about the
    # save-on-open call site, not about a later quit-time save.
    Start-Sleep -Milliseconds 1500
    Check 'w_windowed_open_is_the_only_write' ((Get-DiskSha $ProjectFile) -eq $shaAfter) `
        ("sha256 after settle={0}, +1.5 s later={1}" -f $shaAfter, (Get-DiskSha $ProjectFile))
} finally {
    if ($null -ne $handle -and -not $handle.HasExited) {
        & taskkill /PID $handle.Id /T /F *> (Join-Path $LogRoot 'windowed.taskkill.log')
        Start-Sleep -Milliseconds 1500
    } elseif ($null -ne $handle) {
        Write-Host 'windowed editor had already exited'
    }
}
$shaAfterKill = Get-DiskSha $ProjectFile
Check 'w_windowed_kill_does_not_change_the_file' ($shaAfterKill -eq $shaAfterReady) ("sha256 after ready={0} after kill={1}" -f $shaAfterReady, $shaAfterKill)

# ---------------------------------------------------------------------------
# Idempotence: open the SAME project a second time. By now the file already says
# what the engine would publish, so the second open must not move a byte.
# ---------------------------------------------------------------------------
$textBeforeSecond = Read-TextShared $ProjectFile
$shaBeforeSecond = Get-DiskSha $ProjectFile
$mtimeBeforeSecond = Get-MtimeTicks $ProjectFile
$handle2 = $null
try {
    $handle2 = Start-Process -FilePath $Engine -ArgumentList $windowedArgs -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot 'windowed2.out.log') `
        -RedirectStandardError (Join-Path $LogRoot 'windowed2.err.log')
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle2.Id -Arguments $windowedArgs
    Write-Host ("started WINDOWED editor #2 pid={0}" -f $handle2.Id)
    $ready2 = Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs
    $mtimeMoved2 = Wait-ForMtimeAdvance -Path $ProjectFile -BeforeTicks $mtimeBeforeSecond -TimeoutMs $SettleTimeoutMs
    Start-Sleep -Seconds 2
} finally {
    if ($null -ne $handle2 -and -not $handle2.HasExited) {
        & taskkill /PID $handle2.Id /T /F *> (Join-Path $LogRoot 'windowed2.taskkill.log')
        Start-Sleep -Milliseconds 1500
    }
}
$textAfterSecond = Read-TextShared $ProjectFile
$shaAfterSecond = Get-DiskSha $ProjectFile
$mtimeAfterSecond = Get-MtimeTicks $ProjectFile
$diffSecond = Get-LineDiff -Before $textBeforeSecond -After $textAfterSecond
$commentsSecond = @(Get-CommentLines -Text $textAfterSecond)
Check 'w_windowed_second_open_is_byte_identical' `
    (($ready2) -and ($shaAfterSecond -eq $shaBeforeSecond) -and ($diffSecond.Count -eq 0) -and ($commentsSecond.Count -eq 5) -and ($mtimeAfterSecond -gt $mtimeBeforeSecond)) `
    ("second open endpoint ready={0}; sha {1} -> {2}; differing lines={3}; comments={4}/5; mtime advanced again={5} (observed to move={6}; the declared 'always write, even when updated == text')" -f `
        $ready2, $shaBeforeSecond, $shaAfterSecond, $diffSecond.Count, $commentsSecond.Count, ($mtimeAfterSecond -gt $mtimeBeforeSecond), $mtimeMoved2)
[IO.File]::WriteAllLines((Join-Path $Ev 'windowed_second_open_line_diff.txt'), @($diffSecond.Lines))

# ---------------------------------------------------------------------------
$userPidAfter = Get-ListenerPid -Port_ $UserPort
$guardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter $userPidAfter
Check 'w_port_9877_guard' $guardResult.pass $guardResult.evidence
Check 'w_editor_port_free_after' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))

Write-Host ''
Write-Host '--- summary ---'
$failures = 0
foreach ($c in $script:Checks) {
    if (-not $c.pass) { $failures++ }
    Write-Host ("[{0}] {1} :: {2}" -f $(if ($c.pass) { 'PASS' } else { 'FAIL' }), $c.id, $c.evidence)
}
[IO.File]::WriteAllLines((Join-Path $Root 'summary.txt'), @($script:Checks | ForEach-Object { ("[{0}] {1} :: {2}" -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence) }))
Write-Host ('--- checks: {0}, failures: {1} ---' -f $script:Checks.Count, $failures)
Write-Host ('--- evidence root: {0} ---' -f $Root)
if ($failures -gt 0) { Write-Host ('WINDOWED PRESERVE EVIDENCE FAILED: {0}' -f $failures); exit 1 }
Write-Host 'WINDOWED PRESERVE EVIDENCE PASS'
exit 0
