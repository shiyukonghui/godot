# =============================================================================
#  mcp030_live_open_scene_write_evidence.ps1 -- TASK-030 live evidence (D1, D5)
#
#  D1 (high). `project_set_node_property_across_scenes` used to load the *active
#  edited scene* into a detached `PackedScene` copy as well, edit that copy, skip
#  the disk write for it and answer
#  `code: 0` + `mode: "live_open_scene"` + "the active open scene was edited in
#  memory" while the live nodes were never touched: the next `editor_save_scene`
#  then persisted the OLD value.
#
#  The chain asserted below is exactly the one the task book demands, on the live
#  editor endpoint (9888), with every response body kept as a raw file + sha256:
#
#    (1) `editor_open_scene` on `res://scenes/good.tscn` and a read of its
#        `position` through `editor_get_node_properties` -> (1, 2);
#    (2) `project_set_node_property_across_scenes{force:true}` over a directory
#        holding the OPEN `good.tscn` and the CLOSED `side.tscn`;
#    (3) **another tool** reads `position` back -> (3, 4)      [red before TASK-030]
#    (4) the CLOSED scene is really on disk  -> `Vector2(3, 4)`
#    (5) the OPEN scene is NOT on disk yet   -> still `Vector2(1, 2)`
#    (6) `editor_save_scene` then persists the NEW value:
#        the file holds `Vector2(3, 4)`                        [red before TASK-030]
#
#  D5 (minor). A `path_filter` that matches no scene (here: a scene FILE instead
#  of a directory) used to answer `code: 0` with the "Applied: ..." message.
#  The assertions below pin the new wording (`No scene matched`) and prove the
#  call wrote nothing (both files' sha256 are unchanged).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp030_live_open_scene_write_evidence.ps1
# =============================================================================

param(
    [int]$EditorPort = 9888,
    [int]$GamePort = 9889,
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'task030-live-open-scene' }
$Root = $OutRoot
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877

# TASK-028 D-1: the shared scratch-project writer + `--import` runner (no BOM,
# checked exit code, bounded retry, diagnostics on every failure).
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
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
    param([string]$Tool, $Arguments)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 0)
    if ($Port_ -eq 0) { $Port_ = $EditorPort }
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-McpUtf8NoBom -Path $bodyFile -Text (New-CallBody -Tool $Tool -Arguments $Arguments)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time 120 -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] port={1} bytes={2} sha256={3}" -f $Id, $Port_, $bytes.Length, $sha)
    Write-Host ("       {0}" -f $text)
    return @{ text = $text; sha256 = $sha; file = $respFile; bytes = $bytes.Length }
}

function Get-Payload {
    param($Response)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.result) { return $null }
        return ConvertFrom-Json ([string]$envelope.result.content[0].text)
    } catch { return $null }
}

function Get-ErrorCode {
    param($Response)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return 0 }
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.error) { return 0 }
        return [int]$envelope.error.code
    } catch { return 0 }
}

function Get-ErrorMessage {
    param($Response)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.error) { return '' }
        return [string]$envelope.error.message
    } catch { return '' }
}

function ConvertTo-CompactJson {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    return (ConvertTo-Json -InputObject $Value -Depth 20 -Compress)
}

function Get-FileSha {
    param([string]$Path_)
    if (-not (Test-Path $Path_)) { return '<absent>' }
    return (Get-FileHash -Algorithm SHA256 -Path $Path_).Hash.ToLower()
}

function Read-TextFile {
    param([string]$Path_)
    if (-not (Test-Path $Path_)) { return '' }
    return [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($Path_))
}

# One scene's `scenes_affected` entry, or $null.
function Get-Affected {
    param($Payload, [string]$Scene)
    if ($null -eq $Payload) { return $null }
    foreach ($entry in @($Payload.scenes_affected)) {
        if ([string]$entry.scene -eq $Scene) { return $entry }
    }
    return $null
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    return Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
}

function Wait-ForPump {
    param([int]$Port_, [int]$Iterations = 180)
    for ($i = 0; $i -lt $Iterations; $i++) {
        Start-Sleep -Milliseconds 1000
        $out = Join-Path $Ev ("status-{0}.json" -f $Port_)
        & $Curl -s --max-time 5 -o $out ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (Test-Path $out) {
            try {
                $probe = ConvertFrom-Json (Get-Content -Raw $out)
                if ($null -ne $probe.frame_count -and [int]$probe.frame_count -ge 20) { return $true }
            } catch { }
        }
    }
    return $false
}

function Stop-Engine {
    param($Handle)
    if ($null -ne $Handle -and -not $Handle.HasExited) {
        Stop-Process -Id $Handle.Id -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Scratch project: one directory holding the scene the editor has OPEN and one
# scene it does not.
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Proj, (Join-Path $Proj 'scenes') | Out-Null

New-McpScratchProject -Path $Proj -Name 'mcp030_live_open_scene' -WithMainScene $false

$goodScene = @'
[gd_scene format=3]

[node name="Good" type="Node2D"]
position = Vector2(1, 2)
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\good.tscn') -Text $goodScene

$sideScene = @'
[gd_scene format=3]

[node name="Side" type="Node2D"]
position = Vector2(1, 2)
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\side.tscn') -Text $sideScene

$GoodAbs = Join-Path $Proj 'scenes\good.tscn'
$SideAbs = Join-Path $Proj 'scenes\side.tscn'

$userPidBefore = Get-ListenerPid -Port_ $UserPort
Check 'port_9877_owner_before' ($userPidBefore -gt 0) ("user Godot on {0}: pid={1} (never touched)" -f $UserPort, $userPidBefore)
Check 'port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'port_9889_free' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Check 'scratch_project_imported' ($import.exit_code -eq 0) `
    ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

$editorHandle = $null
$gameHandle = $null
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    # =========================================================================
    # D1 - the lost write on the active edited scene
    # =========================================================================
    $open = Invoke-Tool -Id 'D1_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/good.tscn' }
    Check 'D1_scene_opened' ((Get-ErrorCode $open) -eq 0) ("code={0} payload={1}" -f (Get-ErrorCode $open), (ConvertTo-CompactJson (Get-Payload $open)))

    $before = Invoke-Tool -Id 'D1_position_before' -Tool 'editor_get_node_properties' -Arguments @{ path = '.'; properties = @('position') }
    $beforePayload = Get-Payload $before
    Check 'D1_baseline_open_scene_is_1_2' (($null -ne $beforePayload) -and ([double]$beforePayload.properties.position.x -eq 1.0) -and ([double]$beforePayload.properties.position.y -eq 2.0)) `
        ("position=" + (ConvertTo-CompactJson $beforePayload.properties.position))

    $goodShaBefore = Get-FileSha $GoodAbs
    $sideShaBefore = Get-FileSha $SideAbs

    # (2) one call over the directory: `good.tscn` is OPEN (and active),
    #     `side.tscn` is CLOSED.
    $across = Invoke-Tool -Id 'D1_across_scenes_force' -Tool 'project_set_node_property_across_scenes' -Arguments @{
        type = 'Node2D'; property = 'position'; value = @{ x = 3.0; y = 4.0 }; path_filter = 'res://scenes'; force = $true
    }
    $acrossPayload = Get-Payload $across
    $goodEntry = Get-Affected $acrossPayload 'res://scenes/good.tscn'
    $sideEntry = Get-Affected $acrossPayload 'res://scenes/side.tscn'

    Check 'D1_mixed_call_code0_two_scenes' ((Get-ErrorCode $across) -eq 0 -and $null -ne $acrossPayload -and [int]$acrossPayload.total_scenes -eq 2 -and [int]$acrossPayload.total_nodes -eq 2) `
        ("code={0} total_scenes={1} total_nodes={2} scenes_affected={3}" -f (Get-ErrorCode $across), $acrossPayload.total_scenes, $acrossPayload.total_nodes, (ConvertTo-CompactJson $acrossPayload.scenes_affected))

    # The `mode` of every entry has to say, at a glance, whether that scene was
    # written and whether the new value is on disk.
    Check 'D1_open_scene_mode_says_written_not_persisted' `
        (($null -ne $goodEntry) -and ([string]$goodEntry.mode -eq 'live_open_scene_written') -and ($goodEntry.written -eq $true) -and ($goodEntry.persisted -eq $false) -and ([int]$goodEntry.count -eq 1)) `
        ("good entry=" + (ConvertTo-CompactJson $goodEntry))
    Check 'D1_closed_scene_mode_says_written_and_persisted' `
        (($null -ne $sideEntry) -and ([string]$sideEntry.mode -eq 'offline_saved') -and ($sideEntry.written -eq $true) -and ($sideEntry.persisted -eq $true) -and ([int]$sideEntry.count -eq 1)) `
        ("side entry=" + (ConvertTo-CompactJson $sideEntry))

    # The top-level message may no longer claim the open scene is on disk.
    Check 'D1_message_does_not_claim_open_scene_on_disk' `
        (($null -ne $acrossPayload) -and ([string]$acrossPayload.message).Contains('editor_save_scene') -and ([string]$acrossPayload.message).Contains('in memory') -and -not ([string]$acrossPayload.message).Contains('every closed scene was saved')) `
        ("message=" + [string]$acrossPayload.message)

    # (3) **another tool** reads the live scene back: this is the assertion the
    #     old build failed (it read the old value (1, 2)).
    $after = Invoke-Tool -Id 'D1_position_after_across' -Tool 'editor_get_node_properties' -Arguments @{ path = '.'; properties = @('position') }
    $afterPayload = Get-Payload $after
    Check 'D1_another_tool_reads_new_live_value' (($null -ne $afterPayload) -and ([double]$afterPayload.properties.position.x -eq 3.0) -and ([double]$afterPayload.properties.position.y -eq 4.0)) `
        ("position=" + (ConvertTo-CompactJson $afterPayload.properties.position))

    # (4) the CLOSED scene of the same call really landed on disk.
    $sideText = Read-TextFile $SideAbs
    Check 'D1_closed_scene_on_disk_has_new_value' ($sideText.Contains('Vector2(3, 4)')) `
        ("side.tscn sha before={0} after={1}; contains Vector2(3, 4)={2}" -f $sideShaBefore, (Get-FileSha $SideAbs), $sideText.Contains('Vector2(3, 4)'))

    # (5) the OPEN scene is honestly *not* on disk yet.
    $goodTextBeforeSave = Read-TextFile $GoodAbs
    Check 'D1_open_scene_file_not_written_yet' ($goodTextBeforeSave.Contains('Vector2(1, 2)') -and -not $goodTextBeforeSave.Contains('Vector2(3, 4)')) `
        ("good.tscn sha before={0} before save={1}; contains Vector2(1, 2)={2}" -f $goodShaBefore, (Get-FileSha $GoodAbs), $goodTextBeforeSave.Contains('Vector2(1, 2)'))

    # (6) the caller's save now persists the NEW value (before TASK-030 it
    #     persisted `Vector2(1, 2)`: the silent data loss of D1).
    $save = Invoke-Tool -Id 'D1_editor_save_scene' -Tool 'editor_save_scene' -Arguments @{}
    Check 'D1_editor_save_scene_code0' ((Get-ErrorCode $save) -eq 0 -and (Get-Payload $save).saved -eq $true) `
        ("code={0} payload={1}" -f (Get-ErrorCode $save), (ConvertTo-CompactJson (Get-Payload $save)))

    $goodTextAfterSave = Read-TextFile $GoodAbs
    Check 'D1_open_scene_file_has_new_value_after_save' ($goodTextAfterSave.Contains('Vector2(3, 4)') -and -not $goodTextAfterSave.Contains('Vector2(1, 2)')) `
        ("good.tscn sha after save={0}; contains Vector2(3, 4)={1} contains Vector2(1, 2)={2}" -f (Get-FileSha $GoodAbs), $goodTextAfterSave.Contains('Vector2(3, 4)'), $goodTextAfterSave.Contains('Vector2(1, 2)'))

    # =========================================================================
    # D5 - a `path_filter` that matches nothing may not say "Applied"
    # =========================================================================
    $goodShaPreD5 = Get-FileSha $GoodAbs
    $sideShaPreD5 = Get-FileSha $SideAbs
    $zero = Invoke-Tool -Id 'D5_zero_match' -Tool 'project_set_node_property_across_scenes' -Arguments @{
        type = 'Node2D'; property = 'position'; value = @{ x = 9.0; y = 9.0 }; path_filter = 'res://scenes/side.tscn'; force = $true
    }
    $zeroPayload = Get-Payload $zero
    Check 'D5_zero_match_reports_zero_scenes' ((Get-ErrorCode $zero) -eq 0 -and $null -ne $zeroPayload -and [int]$zeroPayload.total_scenes -eq 0 -and @($zeroPayload.scenes_affected).Count -eq 0 -and [int]$zeroPayload.total_nodes -eq 0) `
        ("code={0} total_scenes={1} scenes_affected={2} message={3}" -f (Get-ErrorCode $zero), $zeroPayload.total_scenes, (ConvertTo-CompactJson $zeroPayload.scenes_affected), [string]$zeroPayload.message)
    Check 'D5_zero_match_message_says_no_match' (($null -ne $zeroPayload) -and ([string]$zeroPayload.message).Contains('No scene matched') -and -not ([string]$zeroPayload.message).Contains('Applied')) `
        ("message=" + [string]$zeroPayload.message)
    Check 'D5_zero_match_wrote_nothing' ((Get-FileSha $GoodAbs) -eq $goodShaPreD5 -and (Get-FileSha $SideAbs) -eq $sideShaPreD5) `
        ("good sha {0} -> {1}; side sha {2} -> {3}" -f $goodShaPreD5, (Get-FileSha $GoodAbs), $sideShaPreD5, (Get-FileSha $SideAbs))

    # =========================================================================
    # Regression guard: an all-closed call still saves every file.
    # =========================================================================
    $closedOnly = Invoke-Tool -Id 'D1_closed_only_commit' -Tool 'project_set_node_property_across_scenes' -Arguments @{
        type = 'Node2D'; property = 'rotation'; value = 0.75; path_filter = 'res://scenes'; force = $true
    }
    $closedPayload = Get-Payload $closedOnly
    $goodRotEntry = Get-Affected $closedPayload 'res://scenes/good.tscn'
    $sideRotEntry = Get-Affected $closedPayload 'res://scenes/side.tscn'
    Check 'regression_closed_and_open_both_written' ((Get-ErrorCode $closedOnly) -eq 0 -and $null -ne $closedPayload -and [int]$closedPayload.total_scenes -eq 2 -and $null -ne $goodRotEntry -and $null -ne $sideRotEntry -and ($goodRotEntry.written -eq $true) -and ($sideRotEntry.written -eq $true)) `
        ("code={0} good={1} side={2}" -f (Get-ErrorCode $closedOnly), (ConvertTo-CompactJson $goodRotEntry), (ConvertTo-CompactJson $sideRotEntry))
    Check 'regression_closed_scene_rotation_on_disk' ((Read-TextFile $SideAbs).Contains('rotation = 0.75')) `
        ("side.tscn sha={0} contains rotation 0.75={1}" -f (Get-FileSha $SideAbs), (Read-TextFile $SideAbs).Contains('rotation = 0.75'))
} finally {
    Stop-Engine -Handle $editorHandle
    Stop-Engine -Handle $gameHandle
}

$userPidAfter = Get-ListenerPid -Port_ $UserPort
Check 'port_9877_owner_after' ($userPidAfter -eq $userPidBefore) ("pid before={0} after={1}" -f $userPidBefore, $userPidAfter)

$failed = @($script:Checks | Where-Object { -not $_.pass })
Write-Host ''
Write-Host '============================================================='
Write-Host (' TASK-030 evidence: {0} checks, {1} failed' -f $script:Checks.Count, $failed.Count)
Write-Host '============================================================='
foreach ($check in $script:Checks) {
    Write-Host ("[{0}] {1}" -f $(if ($check.pass) { 'PASS' } else { 'FAIL' }), $check.id)
}

$summary = [pscustomobject]@{
    engine       = (& $Engine --version) -join ''
    head         = (& git -C $RepoRoot rev-parse --short HEAD) -join ''
    checks       = $script:Checks
    failed_count = $failed.Count
}
Write-McpUtf8NoBom -Path (Join-Path $Root 'summary.json') -Text (ConvertTo-Json -InputObject $summary -Depth 8)
Write-Host ("summary: {0}" -f (Join-Path $Root 'summary.json'))
Write-Host ("evidence: {0}" -f $Ev)
if ($failed.Count -gt 0) { exit 1 }
exit 0
