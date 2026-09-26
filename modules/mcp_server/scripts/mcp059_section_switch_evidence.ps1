# =============================================================================
#  mcp059_section_switch_evidence.ps1 -- TASK-059 D-4, the LIVE evidence of the
#  behaviour switch: the tools that now publish section by section must keep
#  every hand written comment in `project.godot`, and the tools that did not
#  switch must be seen doing what their descriptions now say.
#
#  Why a separate script from `mcp057_settings_publish_evidence.ps1`: that one
#  exercises the ENGINE API directly (`ProjectSettings.save_custom_section` from
#  a GDScript probe). This one exercises the **tools**, over MCP on port 9888,
#  against a real scratch project -- which is the only thing that proves the
#  switch reached the call sites rather than just existing in the engine.
#
#  The fixture is one annotated `project.godot` with FOUR hand written comment
#  lines and `[input]` deliberately NOT the last section (the R1 shape), written
#  without a BOM:
#
#      ; mcp059 comment 1 of 4 ...      <- before `config_version`, where the
#      ; mcp059 comment 2 of 4 ...         whole-file writer writes its own header
#      config_version=5
#      [application] ...
#      ; mcp059 comment 3 of 4          <- inside a section
#      [input] ...                      <- NOT last
#      ; mcp059 comment 4 of 4 ...
#      [rendering] ...
#
#  What is claimed, and how it is checked:
#
#    p3_set_setting_keeps_every_comment     4/4 comments survive a tool call,
#                                           and the file does not start with the
#                                           engine's own header any more;
#    p3_set_setting_only_the_target_section_moved
#                                           a line-level diff of before/after
#                                           must be confined to the span of the
#                                           target section (byte prefix and byte
#                                           suffix outside it identical);
#    p3_set_setting_key_landed_in_its_section the new key is inside `[application]`
#                                           and NOT after `[input]`;
#    p3_set_setting_is_idempotent            the same call twice -> same sha256;
#    p3_input_action_keeps_every_comment     `editor_add_input_action` keeps 4/4;
#    p3_input_action_visible_to_the_engine   a separate `--headless --script` run
#                                           of the project answers
#                                           `InputMap.has_action == true`, i.e.
#                                           the key really landed in `[input]`
#                                           even though that section is not last;
#    p3_add_autoload_keeps_every_comment     `project_add_autoload` keeps 4/4;
#    p3_fallback_bare_key_rewrites_the_whole_file
#                                           a key with no `/` cannot be published
#                                           by section: the DECLARED fall-back
#                                           runs and the comments ARE lost;
#    p3_fallback_remove_autoload_rewrites_the_whole_file
#                                           `project_remove_autoload` stays on the
#                                           whole-file writer (a section publish
#                                           cannot delete a key) and the comments
#                                           ARE lost -- asserted, not glossed over;
#    p3_import_leaves_the_file_unchanged     a section publish is not undone or
#                                           rewritten by `--import`;
#    p3_game_run_leaves_the_file_unchanged   nor by running the project;
#    p3_engine_version_matches_head          the binary under test is the tree's;
#    p3_tools_are_still_the_175              the live `tools/list` count, and the
#                                           five rewritten descriptions findable
#                                           on the wire (a description change is
#                                           the only wire change this batch is
#                                           allowed to make).
#
#  Port discipline: only 9888 (editor) is started. The user's editor on 9877 is
#  never started, killed or restarted, and `mcp_port_guard.ps1` records its pid
#  before and after plus every command line this script ran.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp059_section_switch_evidence.ps1
# =============================================================================

param(
    [string]$Engine = '',
    [int]$EditorPort = 9888,
    [int]$UserPort = 9877,
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($Engine)) { $Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe' }
$Engine = (Resolve-Path $Engine).Path
$ContractPath = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$ProbeSource = Join-Path $PSScriptRoot 'mcp057_section_probe.gd'

$Root = Join-Path $env:TEMP ('mcp059\switch\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Project = Join-Path $Root 'proj-switch'
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Project | Out-Null

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

function New-CallBody {
    param([int]$Id, [string]$Tool, $Arguments)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Invoke-Json {
    param([string]$Id, [string]$Json, [int]$Port_ = 9888, [int]$MaxTimeSec = 300)
    $bodyFile = Join-Path $Ev ("{0}.request.json" -f $Id)
    $respFile = Join-Path $Ev ("{0}.response.json" -f $Id)
    Write-McpUtf8NoBom -Path $bodyFile -Text $Json
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time $MaxTimeSec -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $curlExit = $LASTEXITCODE
    $bytes = @()
    if (Test-Path $respFile) { $bytes = [IO.File]::ReadAllBytes($respFile) }
    $text = ''
    if ($bytes.Count -gt 0) { $text = [Text.Encoding]::UTF8.GetString($bytes) }
    $sha = if ($bytes.Count -gt 0) { (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower() } else { '<empty>' }
    Write-Host ("[{0}] port={1} curl_exit={2} bytes={3} sha256={4}" -f $Id, $Port_, $curlExit, $bytes.Count, $sha)
    [IO.File]::WriteAllText((Join-Path $Ev ("{0}.sha256" -f $Id)), ($sha + "`n"))
    return $text
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 9888)
    return (Invoke-Json -Id $Id -Json (New-CallBody -Id 1 -Tool $Tool -Arguments $Arguments) -Port_ $Port_)
}

function Get-Payload {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.result) { return $null }
        return ConvertFrom-Json ([string]$envelope.result.content[0].text)
    } catch { return $null }
}

function Get-ErrorCode {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return 0 }
        return [int]$envelope.error.code
    } catch { return 0 }
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

function Get-CommentCount {
    param([string]$Text)
    # A whole-line comment: the first non-blank character is ';'. A COUNT, not a
    # substring test, so "4/4 kept" cannot be satisfied by an unrelated comment.
    $count = 0
    foreach ($line in ($Text -split "`n")) {
        if ($line.TrimStart().StartsWith(';')) { $count++ }
    }
    return $count
}

function HandWrittenCommentsGone {
    param([string]$Text)
    # "The fixture's four comments are gone" is NOT "the comment count is 0": the
    # engine's whole-file writer emits its own fixed header, which is 7 comment
    # lines (`_save_settings_text()`, core/config/project_settings.cpp:1170-1182).
    # Measured the hard way: an earlier version of this script asserted
    # `count -lt 4` and failed on a file that HAD been rewritten, because 7 is
    # not less than 4.
    return (-not $Text.Contains('mcp059 comment 1 of 4')) -and (-not $Text.Contains('mcp059 comment 4 of 4'))
}

function Get-DiffSpan {
    param([string]$Before, [string]$After)
    # The first and last line index at which the two texts differ. Used to prove
    # the edit is confined to the target section's span.
    $b = @($Before -split "`n")
    $a = @($After -split "`n")
    $first = -1
    $last = -1
    $max = [Math]::Max($b.Count, $a.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $bl = if ($i -lt $b.Count) { $b[$i] } else { '<absent>' }
        $al = if ($i -lt $a.Count) { $a[$i] } else { '<absent>' }
        if ($bl -ne $al) { if ($first -lt 0) { $first = $i }; $last = $i }
    }
    return @{ first = $first; last = $last; before = $b; after = $a }
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
                $parsed = ConvertFrom-Json ([IO.File]::ReadAllText($probe))
                if ($null -ne $parsed.frame_count) { return $true }
            } catch { }
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# ---------------------------------------------------------------------------
# The fixture. Written byte-wise through the shared helper, so the file has no
# BOM and the four comments are exactly where they are claimed to be.
# ---------------------------------------------------------------------------
$FixtureLines = @(
    '; mcp059 comment 1 of 4: hand written header',
    '; mcp059 comment 2 of 4',
    'config_version=5',
    '',
    '[application]',
    '',
    'config/name="MCP059 switch"',
    'config/features=PackedStringArray("4.8")',
    'run/main_scene="res://scenes/main.tscn"',
    '',
    '; mcp059 comment 3 of 4',
    '[input]',
    '',
    'jump={',
    '"deadzone": 0.5,',
    '"events": []',
    '}',
    '',
    '; mcp059 comment 4 of 4: [input] is deliberately NOT the last section',
    '[rendering]',
    '',
    'renderer/rendering_method="gl_compatibility"'
)
Write-McpUtf8NoBom -Path (Join-Path $Project 'project.godot') -Text (($FixtureLines -join "`n") + "`n")
New-Item -ItemType Directory -Force -Path (Join-Path $Project 'scenes') | Out-Null
Write-McpUtf8NoBom -Path (Join-Path $Project 'scenes\main.tscn') -Text "[gd_scene format=3]`n`n[node name=`"Main`" type=`"Node`"]`n"
Copy-Item -Path $ProbeSource -Destination (Join-Path $Project 'mcp059_probe.gd') -Force

$ProjectFile = Join-Path $Project 'project.godot'

Write-Host '============================================================='
Write-Host ' TASK-059 D-4: the section-granular publish, through the TOOLS'
Write-Host (' repo    : ' + $RepoRoot)
Write-Host (' root    : ' + $Root)
Write-Host (' project : ' + $Project)
Write-Host '============================================================='

$version = ((& $Engine --version) -join '').Trim()
$head = ((& git -C $RepoRoot rev-parse --short=9 HEAD) -join '').Trim()
# TASK-072 (D130): one judge decides the anchor; see check_engine_anchor.ps1.
$anchorVerdict = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $version -HeadSha $head
Check 'p3_engine_version_matches_head' ($anchorVerdict.Ok) `
    (("--version='{0}' git HEAD='{1}'" -f $version, $head) + ' | ' + $anchorVerdict.Summary)

$userPidBefore = Get-ListenerPid -Port_ $UserPort
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("user editor on {0} before: pid={1}" -f $UserPort, $userPidBefore)
Check 'p3_editor_port_free_before' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))

$import = Import-McpProject -Engine $Engine -Path $Project -LogDirectory $LogRoot -Name 'import-switch'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine ([string]$import.command)
$fixtureText = Read-TextShared $ProjectFile
Check 'p3_fixture_survives_import' (($import.exit_code -eq 0) -and ((Get-CommentCount $fixtureText) -eq 4)) `
    ("import exit={0} attempts={1}; comments={2}/4" -f $import.exit_code, $import.attempts, (Get-CommentCount $fixtureText))

$handle = $null
try {
    $arguments = @('--headless', '-e', '--path', $Project, ("--mcp-port={0}" -f $EditorPort))
    $handle = Start-Process -FilePath $Engine -ArgumentList $arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot 'editor.out.log') `
        -RedirectStandardError (Join-Path $LogRoot 'editor.err.log') -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $arguments
    Write-Host ("started editor pid={0} :: {1}" -f $handle.Id, ($arguments -join ' '))

    $ready = Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs
    Check 'p3_editor_endpoint_ready' $ready ("port {0} answered within {1} ms" -f $EditorPort, $ReadyTimeoutMs)

    # --- the live tools/list: the same set of names, and the rewritten text ----
    # The live list is the union of the IMPLEMENTED groups (152 tools on the
    # editor endpoint at this task's HEAD), not the 175 entry contract, so the
    # assertion is "a subset of the contract, containing all five rewritten
    # tools, and stable" rather than a pinned count that the next batch would
    # have to update.
    $listText = Invoke-Json -Id 'p3_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port_ $EditorPort
    # The SAME id, so byte equality is a statement about the tool list and not
    # about the echoed request id (measured: two calls with ids 1 and 2 are
    # 59194 bytes each and differ only there).
    $listText2 = Invoke-Json -Id 'p3_tools_list_again' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port_ $EditorPort
    $listNames = @()
    $listByName = @{}
    try {
        $listEnvelope = ConvertFrom-Json $listText
        foreach ($entry in @($listEnvelope.result.tools)) {
            $listNames += [string]$entry.name
            $listByName[[string]$entry.name] = $entry
        }
    } catch { }
    Check 'p3_live_tools_list_is_deterministic' ($listText -ceq $listText2) ("two tools/list calls on one process byte-identical: {0}; live count={1}" -f ($listText -ceq $listText2), $listNames.Count)

    $contract = ConvertFrom-Json ([IO.File]::ReadAllText($ContractPath))
    $contractNames = @{}
    $contractDesc = @{}
    foreach ($t in @($contract.result.tools)) {
        $contractNames[[string]$t.name] = $true
        $contractDesc[[string]$t.name] = [string]$t.description
    }
    $foreign = @($listNames | Where-Object { -not $contractNames.ContainsKey($_) })
    $five = @('project_set_setting', 'editor_add_input_action', 'project_add_autoload', 'project_remove_autoload', 'editor_reload_plugin')
    $missingFive = @($five | Where-Object { -not $listByName.ContainsKey($_) })
    Check 'p3_live_tools_are_a_subset_of_the_contract' (($foreign.Count -eq 0) -and ($missingFive.Count -eq 0)) `
        ("foreign name(s)={0}; the five rewritten tools present, missing={1}" -f ($foreign -join ','), ($missingFive -join ','))

    $descMismatch = @()
    foreach ($name in $five) {
        if ($listByName.ContainsKey($name)) {
            if ([string]$listByName[$name].description -cne [string]$contractDesc[$name]) { $descMismatch += $name }
        }
    }
    $setDesc = ''
    if ($listByName.ContainsKey('project_set_setting')) { $setDesc = [string]$listByName['project_set_setting'].description }
    $removeDesc = ''
    if ($listByName.ContainsKey('project_remove_autoload')) { $removeDesc = [string]$listByName['project_remove_autoload'].description }
    $switchedOk = ($setDesc.Contains('section by section')) -and ($setDesc.Contains('behaviour improvement')) -and (-not $setDesc.Contains('no partial-publish'))
    $keptOk = ($removeDesc.Contains('never deletes a key')) -and (-not $removeDesc.Contains('no partial-publish'))
    Check 'p3_rewritten_descriptions_are_on_the_wire' (($descMismatch.Count -eq 0) -and $switchedOk -and $keptOk) `
        ("five descriptions verbatim == contract: {0}; the switched one states the section write + the fall-backs + the improvement: {1}; the kept one says why it could not switch: {2}" -f ($descMismatch.Count -eq 0), $switchedOk, $keptOk)

    # -------------------------------------------------------------------------
    #  1. project_set_setting: a NEW key in an existing MIDDLE section
    # -------------------------------------------------------------------------
    Write-McpUtf8NoBom -Path $ProjectFile -Text (($FixtureLines -join "`n") + "`n")
    $before = Get-DiskSha $ProjectFile
    $beforeText = Read-TextShared $ProjectFile
    $setResp = Invoke-Tool -Id 'p3_set_setting_1' -Tool 'project_set_setting' -Arguments @{ key = 'application/mcp059_marker'; value = 42 } -Port_ $EditorPort
    $setPayload = Get-Payload $setResp
    $setOk = ($null -ne $setPayload) -and ([string]$setPayload.key -ceq 'application/mcp059_marker')
    Check 'p3_set_setting_succeeded' $setOk ("error_code={0}; payload={1}" -f (Get-ErrorCode $setResp), ($setResp -replace "`n", ' '))

    $afterText = Read-TextShared $ProjectFile
    $after = Get-DiskSha $ProjectFile
    $commentsAfter = Get-CommentCount $afterText
    Check 'p3_set_setting_keeps_every_comment' ($commentsAfter -eq 4) ("comments before={0}/4 after={1}/4; the whole-file writer would have left 7 of its own" -f (Get-CommentCount $beforeText), $commentsAfter)
    Check 'p3_set_setting_did_not_write_the_engine_header' (-not $afterText.StartsWith('; Engine configuration file.')) 'the file does not begin with the engine whole-file header'
    Check 'p3_set_setting_changed_the_file' ($after -ne $before) ("sha before={0} after={1}" -f $before, $after)

    # The new key is inside the target section's span and NOT after `[input]`.
    $appHeader = $afterText.IndexOf('[application]')
    $inputHeader = $afterText.IndexOf('[input]')
    $markerAt = $afterText.IndexOf('mcp059_marker=42')
    Check 'p3_set_setting_key_landed_in_its_section' (($markerAt -gt $appHeader) -and ($markerAt -lt $inputHeader)) `
        ("[application] at {0}, mcp059_marker=42 at {1}, [input] at {2} -- appended at the end would have been past {2}" -f $appHeader, $markerAt, $inputHeader)

    # The diff is confined to the target section: the byte prefix before
    # `[application]` and the byte suffix from `[input]` on are identical.
    $prefixOk = $afterText.StartsWith($beforeText.Substring(0, $beforeText.IndexOf('[application]')))
    $suffixOk = $afterText.EndsWith($beforeText.Substring($beforeText.IndexOf('[input]')))
    $span = Get-DiffSpan -Before $beforeText -After $afterText
    Check 'p3_set_setting_only_the_target_section_moved' ($prefixOk -and $suffixOk) `
        ("prefix before [application] identical={0}; suffix from [input] on identical={1}; first differing line index={2}, last={3}" -f $prefixOk, $suffixOk, $span.first, $span.last)

    # Idempotence: the same call again leaves the file byte identical.
    $setResp2 = Invoke-Tool -Id 'p3_set_setting_2' -Tool 'project_set_setting' -Arguments @{ key = 'application/mcp059_marker'; value = 42 } -Port_ $EditorPort
    $after2 = Get-DiskSha $ProjectFile
    Check 'p3_set_setting_is_idempotent' ($after2 -eq $after) ("sha after 1st={0} after 2nd={1}" -f $after, $after2)

    # -------------------------------------------------------------------------
    #  2. editor_add_input_action: the [input] section is NOT last
    # -------------------------------------------------------------------------
    Write-McpUtf8NoBom -Path $ProjectFile -Text (($FixtureLines -join "`n") + "`n")
    $actionResp = Invoke-Tool -Id 'p3_add_input_action' -Tool 'editor_add_input_action' -Arguments @{ action = 'mcp059_switch'; key = 'F7' } -Port_ $EditorPort
    $actionPayload = Get-Payload $actionResp
    Check 'p3_add_input_action_succeeded' (($null -ne $actionPayload) -and ([string]$actionPayload.persisted -eq 'True')) `
        ("error_code={0}; payload={1}" -f (Get-ErrorCode $actionResp), ($actionResp -replace "`n", ' '))
    $afterActionText = Read-TextShared $ProjectFile
    Check 'p3_input_action_keeps_every_comment' ((Get-CommentCount $afterActionText) -eq 4) `
        ("comments={0}/4; the mirror block is in [input], which is not the last section" -f (Get-CommentCount $afterActionText))
    $actionAt = $afterActionText.IndexOf('mcp059_switch=')
    $inputAt = $afterActionText.IndexOf('[input]')
    $renderAt = $afterActionText.IndexOf('[rendering]')
    Check 'p3_input_action_landed_inside_input_not_after_it' (($actionAt -gt $inputAt) -and ($actionAt -lt $renderAt)) `
        ("[input] at {0}, mcp059_switch= at {1}, [rendering] at {2}" -f $inputAt, $actionAt, $renderAt)

    # -------------------------------------------------------------------------
    #  3. project_add_autoload: a brand new [autoload] section
    # -------------------------------------------------------------------------
    Write-McpUtf8NoBom -Path $ProjectFile -Text (($FixtureLines -join "`n") + "`n")
    Write-McpUtf8NoBom -Path (Join-Path $Project 'scripts\mcp059_autoload.gd') -Text "extends Node`n"
    $addResp = Invoke-Tool -Id 'p3_add_autoload' -Tool 'project_add_autoload' -Arguments @{ name = 'Mcp059Autoload'; path = 'res://scripts/mcp059_autoload.gd' } -Port_ $EditorPort
    $addPayload = Get-Payload $addResp
    Check 'p3_add_autoload_succeeded' (($null -ne $addPayload) -and ([string]$addPayload.added -eq 'True')) `
        ("error_code={0}; payload={1}" -f (Get-ErrorCode $addResp), ($addResp -replace "`n", ' '))
    $afterAddText = Read-TextShared $ProjectFile
    Check 'p3_add_autoload_keeps_every_comment' ((Get-CommentCount $afterAddText) -eq 4) ("comments={0}/4 after a brand new section was created at the end of the file" -f (Get-CommentCount $afterAddText))

    # -------------------------------------------------------------------------
    #  4. the DECLARED fall-backs, each on its OWN fresh fixture, asserted as
    #     the honest cost they are (this is what makes them declared, not hidden)
    # -------------------------------------------------------------------------

    # 4a. project_remove_autoload: a removal cannot be a section publish, so the
    #     whole file is rewritten and the comments really are lost.
    Write-McpUtf8NoBom -Path $ProjectFile -Text (($FixtureLines -join "`n") + "`n")
    $null = Invoke-Tool -Id 'p3_remove_autoload_setup' -Tool 'project_add_autoload' -Arguments @{ name = 'Mcp059Gone'; path = 'res://scripts/mcp059_autoload.gd' } -Port_ $EditorPort
    $beforeRemoveText = Read-TextShared $ProjectFile
    Check 'p3_remove_autoload_setup_kept_the_comments' (((Get-CommentCount $beforeRemoveText) -eq 4)) `
        ("adding the autoload that is about to be removed kept {0}/4 comments" -f (Get-CommentCount $beforeRemoveText))
    $removeResp = Invoke-Tool -Id 'p3_remove_autoload' -Tool 'project_remove_autoload' -Arguments @{ name = 'Mcp059Gone' } -Port_ $EditorPort
    $removePayload = Get-Payload $removeResp
    $afterRemoveText = Read-TextShared $ProjectFile
    Check 'p3_remove_autoload_succeeded' (($null -ne $removePayload) -and ([string]$removePayload.removed -eq 'True')) `
        ("error_code={0}; payload={1}" -f (Get-ErrorCode $removeResp), ($removeResp -replace "`n", ' '))
    Check 'p3_fallback_remove_autoload_rewrites_the_whole_file' ((HandWrittenCommentsGone $afterRemoveText) -and $afterRemoveText.StartsWith('; Engine configuration file.')) `
        ("the section writer cannot delete a key, so this tool keeps the whole-file writer: the 4 hand written comments are gone (file now carries {0} comment line(s), the engine's own), engine header written={1} -- declared, not hidden" -f (Get-CommentCount $afterRemoveText), $afterRemoveText.StartsWith('; Engine configuration file.'))

    # 4b. a key that names no section: `_save_settings_text()` writes it into the
    #     header-less global block, which has no section name to publish into.
    Write-McpUtf8NoBom -Path $ProjectFile -Text (($FixtureLines -join "`n") + "`n")
    $bareResp = Invoke-Tool -Id 'p3_fallback_bare_key' -Tool 'project_set_setting' -Arguments @{ key = 'mcp059_bare'; value = 7 } -Port_ $EditorPort
    $afterBareText = Read-TextShared $ProjectFile
    $bareComments = Get-CommentCount $afterBareText
    Check 'p3_fallback_bare_key_rewrites_the_whole_file' ((HandWrittenCommentsGone $afterBareText) -and $afterBareText.StartsWith('; Engine configuration file.')) `
        ("a key with no '/' names no section, so the whole-file writer runs: the 4 hand written comments are gone (file now carries {0} comment line(s), the engine's own), engine header written={1} -- declared, not hidden" -f $bareComments, $afterBareText.StartsWith('; Engine configuration file.'))
    Check 'p3_fallback_bare_key_still_saved_the_value' ($afterBareText.Contains('mcp059_bare=7')) 'the fall-back still produced the requested end state'
    Check 'p3_fallback_bare_key_error_free' ((Get-ErrorCode $bareResp) -eq 0) ("error_code={0} (a declared fall-back is a success, not an error)" -f (Get-ErrorCode $bareResp))

    # -------------------------------------------------------------------------
    #  6. put the fixture back, do a section publish, then import + run the game
    # -------------------------------------------------------------------------
    Write-McpUtf8NoBom -Path $ProjectFile -Text (($FixtureLines -join "`n") + "`n")
    $rePublish = Invoke-Tool -Id 'p3_republish_for_import' -Tool 'project_set_setting' -Arguments @{ key = 'application/mcp059_marker'; value = 42 } -Port_ $EditorPort
    $beforeImport = Get-DiskSha $ProjectFile
    $import2 = Import-McpProject -Engine $Engine -Path $Project -LogDirectory $LogRoot -Name 'import-after-publish'
    Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine ([string]$import2.command)
    $afterImport = Get-DiskSha $ProjectFile
    Check 'p3_import_leaves_the_file_unchanged' (($import2.exit_code -eq 0) -and ($afterImport -eq $beforeImport) -and ((Get-CommentCount (Read-TextShared $ProjectFile)) -eq 4)) `
        ("import exit={0} attempts={1} sha {2} -> {3}; comments={4}/4" -f $import2.exit_code, $import2.attempts, $beforeImport, $afterImport, (Get-CommentCount (Read-TextShared $ProjectFile)))

    $gameFile = Join-Path $LogRoot 'game_run.txt'
    $previousGamePreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $Engine --headless --path $Project --quit-after 2 *> $gameFile
    $gameExit = $LASTEXITCODE
    $ErrorActionPreference = $previousGamePreference
    $afterGame = Get-DiskSha $ProjectFile
    Check 'p3_game_run_leaves_the_file_unchanged' (($gameExit -eq 0) -and ($afterGame -eq $beforeImport)) `
        ("game run exit={0} sha {1} -> {2}; log={3}" -f $gameExit, $beforeImport, $afterGame, $gameFile)

    # -------------------------------------------------------------------------
    #  7. the engine's own InputMap: run the project and ASK it
    # -------------------------------------------------------------------------
    Write-McpUtf8NoBom -Path $ProjectFile -Text (($FixtureLines -join "`n") + "`n")
    $action2 = Invoke-Tool -Id 'p3_input_action_for_probe' -Tool 'editor_add_input_action' -Arguments @{ action = 'mcp059_probe_action'; key = 'F8' } -Port_ $EditorPort
    $probeOut = Join-Path $LogRoot 'has_action.txt'
    # A `--script` main loop with no SceneTree makes the MCP bootstrap write
    # `ERROR: [MCP] SceneTree never became available` to stderr. Under
    # `$ErrorActionPreference = 'Stop'` PowerShell 5.1 turns any native stderr
    # line into a terminating NativeCommandError, which killed this script after
    # the probe but before the summary (measured: the run stopped at this line
    # with no `p3_input_action_visible_to_the_engine` result at all). The
    # preference is therefore relaxed for exactly this call, the way
    # `mcp_import_guard.ps1` does it, and the exit code is checked by hand.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $Engine --headless --path $Project --script res://mcp059_probe.gd -- has_action mcp059_probe_action *> $probeOut
    $probeExit = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    $probeText = Read-TextShared $probeOut
    $hasAction = $probeText.Contains('has_action=true')
    Check 'p3_input_action_visible_to_the_engine' (($probeExit -eq 0) -and $hasAction) `
        ("separate --headless --script run: InputMap.has_action(mcp059_probe_action)={0}; and the hand written comments are still there={1}/4" -f $hasAction, (Get-CommentCount (Read-TextShared $ProjectFile)))
}
finally {
    if ($null -ne $handle -and -not $handle.HasExited) {
        & taskkill /PID $handle.Id /T /F *> (Join-Path $LogRoot 'editor.taskkill.log')
        Start-Sleep -Milliseconds 1500
    }
}

$portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'p3_port_9877_guard' $portGuardResult.pass $portGuardResult.evidence
Check 'p3_editor_port_free_after' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))

Write-Host ''
Write-Host '--- summary ---'
$failures = 0
foreach ($c in $script:Checks) {
    if (-not $c.pass) { $failures++ }
    Write-Host ("[{0}] {1} :: {2}" -f $(if ($c.pass) { 'PASS' } else { 'FAIL' }), $c.id, $c.evidence)
}
$summaryPath = Join-Path $Root 'summary.txt'
[IO.File]::WriteAllLines($summaryPath, @($script:Checks | ForEach-Object { ("[{0}] {1} :: {2}" -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence) }))
Write-Host ('--- checks: {0}, failures: {1} ---' -f $script:Checks.Count, $failures)
Write-Host ('--- evidence root: {0} ---' -f $Root)
if ($failures -gt 0) { Write-Host ('SECTION-SWITCH EVIDENCE FAILED: {0}' -f $failures); exit 1 }
Write-Host 'SECTION-SWITCH EVIDENCE PASS'
exit 0
