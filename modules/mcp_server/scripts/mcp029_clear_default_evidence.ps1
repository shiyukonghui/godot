# =============================================================================
#  mcp029_clear_default_evidence.ps1 -- TASK-029 live evidence
#
#  TASK-028 G-3 made `editor_get_test_report`'s `clear` an explicit opt-in (an
#  omitted `clear` is a pure read; only `clear: true` deletes), but the registered
#  `inputSchema` still declared `"default": true` - the contract said the
#  opposite of what the tool did. TASK-029 fixes that declaration through
#  `scripts/gen_renamed_contract.py`'s `SCHEMA_OVERRIDES` / `DESCRIPTION_OVERRIDES`.
#
#  The claims below are all taken on the live endpoints, and every response body
#  is kept as a raw file with its sha256 so an independent verifier can re-check
#  the bytes:
#
#    * the **online `tools/list`** on 9888 really carries
#      `inputSchema.properties.clear.default == false` (parsed from the wire, not
#      read out of the repo file) and a description that names the *shared*
#      bridge file;
#    * an omitted `clear` (and an explicit `clear: false`) is a **pure read**:
#      the whole report comes back, `cleared` is `[]`, and the bridge file is
#      still there;
#    * **two clients read one after the other and the two response bodies are
#      byte-identical** (`sha256(A) == sha256(B)`) - the non-destructive half,
#      measured as bytes rather than as a field-by-field comparison;
#    * only an explicit `clear: true` deletes (and says which halves of the
#      report it really emptied), after which the next read is **honestly empty**
#      (`total: 0`, `no_results: true`, `pass_rate: "N/A"` - no fabricated total).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp029_clear_default_evidence.ps1
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
$Contract = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'task029-clear-default' }
$Root = $OutRoot
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877

# --- encoding facts this script depends on -----------------------------------
#
# The contract and every response body are UTF-8, and **this file carries no
# non-ASCII byte** on purpose: Windows PowerShell 5.1 reads a BOM-less `.ps1` in
# the ANSI code page (measured here: `gb2312`), so a Chinese literal written into
# this script would be silently mangled and the two description checks below would
# compare garbage. The two strings that have to be Chinese are therefore built
# from code points, and the *old* wording is read out of the frozen fixture with an
# explicit UTF-8 decoder instead of `Get-Content`.
$utf8 = [Text.Encoding]::UTF8
$sharedWord = -join ([char]0x5171, [char]0x4EAB) # the word "shared"
$OldFixture = 'F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json'
$oldDescription = ''
$oldClearDescription = ''
if (Test-Path $OldFixture) {
    try {
        $oldJson = ConvertFrom-Json ([IO.File]::ReadAllText($OldFixture, $utf8))
        foreach ($candidate in @($oldJson.result.tools)) {
            if ([string]$candidate.name -eq 'get_test_report') {
                $oldDescription = [string]$candidate.description
                $oldClearDescription = [string]$candidate.inputSchema.properties.clear.description
                break
            }
        }
    } catch { }
}

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
    param([string]$Tool, $Arguments, [int]$Id = 1)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function New-ListBody {
    param([int]$Id = 1)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/list'; params = [ordered]@{} }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

# One raw JSON-RPC request kept as a file (`curl.exe -s -o <file>`): the response
# body is never carried through a pipeline (PLAYBOOK section 7.1).
function Invoke-Raw {
    param([string]$Id, [string]$Body, [int]$Port_)
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-McpUtf8NoBom -Path $bodyFile -Text $Body
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time 120 -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] port={1} bytes={2} sha256={3}" -f $Id, $Port_, $bytes.Length, $sha)
    return @{ text = $text; sha256 = $sha; file = $respFile; bytes = $bytes.Length }
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 0)
    if ($Port_ -eq 0) { $Port_ = $EditorPort }
    $resp = Invoke-Raw -Id $Id -Body (New-CallBody -Tool $Tool -Arguments $Arguments) -Port_ $Port_
    Write-Host ("       {0}" -f $resp.text)
    return $resp
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

function ConvertTo-CompactJson {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    return (ConvertTo-Json -InputObject $Value -Depth 20 -Compress)
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
                $probe = ConvertFrom-Json ([IO.File]::ReadAllText($out, $utf8))
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
# Scratch project (minimal: the two assertion writers only need a node and a
# property that can pass/fail, so the TASK-028 G-1 fixture is not repeated here)
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Proj, (Join-Path $Proj 'scenes') | Out-Null

$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp029_clear_default"'
    'run/main_scene="res://scenes/main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text ($projectGodot + "`n")

$scene = @'
[gd_scene format=3]

[node name="Main" type="Node2D"]

[node name="Actor" type="Node2D" parent="."]
position = Vector2(1, 2)
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text $scene

$userDir = Join-Path $env:APPDATA 'Godot\app_userdata\mcp029_clear_default'
$bridgeAbs = Join-Path $userDir 'mcp_test_report.json'

$userPidBefore = Get-ListenerPid -Port_ $UserPort
Check 'port_9877_owner_before' ($userPidBefore -gt 0) ("user Godot on {0}: pid={1} (never touched)" -f $UserPort, $userPidBefore)
Check 'port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'port_9889_free' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))
# The append-only half of the description override is checked against the *old*
# wording; if the frozen fixture cannot be read, that check must fail loudly
# instead of comparing against an empty prefix.
Check 'old_fixture_readable' (($oldDescription.Length -gt 0) -and ($oldClearDescription.Length -gt 0)) `
    ("{0}: old description = {1} | old clear.description = {2}" -f $OldFixture, $oldDescription, $oldClearDescription)

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Check 'scratch_project_imported' ($import.exit_code -eq 0) `
    ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

$editorHandle = $null
$gameHandle = $null
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    # =========================================================================
    # 1. The declaration, read off the wire (`tools/list` on 9888)
    # =========================================================================
    $list = Invoke-Raw -Id 'tools_list_editor' -Body (New-ListBody) -Port_ $EditorPort
    $listEntry = $null
    $listCount = 0
    try {
        $listEnvelope = ConvertFrom-Json $list.text
        $listTools = @($listEnvelope.result.tools)
        $listCount = $listTools.Count
        foreach ($candidate in $listTools) {
            if ([string]$candidate.name -eq 'editor_get_test_report') { $listEntry = $candidate; break }
        }
    } catch { }

    $wireDefault = $null
    $wireClearDescription = ''
    $wireDescription = ''
    if ($null -ne $listEntry) {
        $wireDefault = $listEntry.inputSchema.properties.clear.default
        $wireClearDescription = [string]$listEntry.inputSchema.properties.clear.description
        $wireDescription = [string]$listEntry.description
    }
    Check 'tools_list_has_the_tool' ($null -ne $listEntry) ("tools/list on {0}: {1} tools, entry found={2}" -f $EditorPort, $listCount, ($null -ne $listEntry))

    # The whole point of TASK-029: this is parsed from the response body, not read
    # from `docs/tools_list.renamed.json`.
    Check 'wire_clear_default_is_false' `
        (($null -ne $listEntry) -and ($wireDefault -is [bool]) -and ($wireDefault -eq $false)) `
        ("live inputSchema.properties.clear.default = {0} (type {1})" -f (ConvertTo-CompactJson $wireDefault), $(if ($null -eq $wireDefault) { '<null>' } else { $wireDefault.GetType().Name }))

    Check 'wire_clear_description_kept' (($null -ne $listEntry) -and ($wireClearDescription -eq $oldClearDescription)) `
        ("live clear.description = {0} (== the frozen old contract's clear.description: {1})" -f $wireClearDescription, ($wireClearDescription -eq $oldClearDescription))

    # The destructive half has to be readable without the module's source. The
    # word "shared" is built from code points on purpose - see $sharedWord above.
    Check 'wire_description_names_shared_file' `
        (($null -ne $listEntry) -and ($wireDescription.StartsWith($oldDescription + ' ')) -and $wireDescription.Contains($sharedWord) -and $wireDescription.Contains('user://mcp_test_report.json') -and $wireDescription.Contains('clear:true') -and $wireDescription.Contains('clear:false')) `
        ("live description = {0}" -f $wireDescription)

    # And the on-disk contract agrees with the wire (this is what gate 1 compares
    # verbatim; here it is pinned for the one field the task is about).
    $contractEntry = $null
    try {
        $contractJson = ConvertFrom-Json ([IO.File]::ReadAllText($Contract, $utf8))
        foreach ($candidate in @($contractJson.result.tools)) {
            if ([string]$candidate.name -eq 'editor_get_test_report') { $contractEntry = $candidate; break }
        }
    } catch { }
    $contractDefault = if ($null -ne $contractEntry) { $contractEntry.inputSchema.properties.clear.default } else { $null }
    Check 'contract_file_agrees_with_wire' `
        (($null -ne $contractEntry) -and ($contractDefault -eq $false) -and ([string]$contractEntry.description -eq $wireDescription) -and ([string]$contractEntry.inputSchema.properties.clear.description -eq $wireClearDescription)) `
        ("contract clear.default = {0}; live description == contract description = {1}" -f (ConvertTo-CompactJson $contractDefault), ($null -ne $contractEntry -and [string]$contractEntry.description -eq $wireDescription))

    # =========================================================================
    # 2. The behaviour the declaration now describes
    # =========================================================================
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, "--mcp-port=$GamePort") -LogName 'game'
    Check 'game_endpoint_ready' (Wait-ForPump -Port_ $GamePort) ("game on {0} answered GET /mcp with +20 frames" -f $GamePort)

    if (Test-Path $bridgeAbs) { Remove-Item -Force $bridgeAbs }

    $gamePass = Invoke-Tool -Id 'G3_game_assert_a' -Tool 'running_game_assert_node_state' -Arguments @{ node_path = 'Actor'; property = 'position'; operator = 'eq'; expected = @{ x = 1; y = 2 } } -Port_ $GamePort
    $gameFail = Invoke-Tool -Id 'G3_game_assert_b' -Tool 'running_game_assert_node_state' -Arguments @{ node_path = 'Actor'; property = 'rotation'; operator = 'eq'; expected = 123.0 } -Port_ $GamePort
    Check 'game_assertions_recorded' (((Get-Payload $gamePass).passed -eq $true) -and ((Get-Payload $gameFail).passed -eq $false) -and (Test-Path $bridgeAbs)) `
        ("pass={0} fail={1} bridge={2}" -f (Get-Payload $gamePass).passed, (Get-Payload $gameFail).passed, (Test-Path $bridgeAbs))

    # --- (1) omitted `clear`: a pure read, twice, byte-identical --------------
    # Both requests carry the same JSON-RPC `id` on purpose: the comparison is
    # between two *response bodies*, so anything that legitimately differs (a
    # request id) would mask a report that changed.
    $readerA = Invoke-Tool -Id 'G3_reader_a_plain' -Tool 'editor_get_test_report' -Arguments @{}
    $readerAPayload = Get-Payload $readerA
    $fileAfterA = Test-Path $bridgeAbs
    Check 'plain_read_default_is_a_pure_read' `
        (([int]$readerAPayload.total -eq 2) -and ([int]$readerAPayload.passed -eq 1) -and ([int]$readerAPayload.failed -eq 1) -and (@($readerAPayload.cleared).Count -eq 0) -and $fileAfterA -and ($readerAPayload.report_file_present -eq $true)) `
        ("A: total={0} passed={1} failed={2} source={3} cleared={4} report_file_present={5} file on disk={6}" -f `
                $readerAPayload.total, $readerAPayload.passed, $readerAPayload.failed, $readerAPayload.source, `
                (ConvertTo-CompactJson $readerAPayload.cleared), $readerAPayload.report_file_present, $fileAfterA)

    $readerB = Invoke-Tool -Id 'G3_reader_b_plain' -Tool 'editor_get_test_report' -Arguments @{}
    $readerBPayload = Get-Payload $readerB
    $fileAfterB = Test-Path $bridgeAbs
    Check 'second_client_still_sees_the_whole_report' `
        (([int]$readerBPayload.total -eq 2) -and (@($readerBPayload.cleared).Count -eq 0) -and $fileAfterB) `
        ("B: total={0} passed={1} failed={2} source={3} cleared={4} | file after A={5} after B={6}" -f `
                $readerBPayload.total, $readerBPayload.passed, $readerBPayload.failed, $readerBPayload.source, `
                (ConvertTo-CompactJson $readerBPayload.cleared), $fileAfterA, $fileAfterB)

    Check 'two_plain_reads_are_byte_identical' ($readerA.sha256 -eq $readerB.sha256) `
        ("sha256(A)={0} sha256(B)={1} bytes A={2} B={3}" -f $readerA.sha256, $readerB.sha256, $readerA.bytes, $readerB.bytes)

    # --- (2) an *explicit* `clear: false` is the same pure read ---------------
    $explicitFalse = Invoke-Tool -Id 'G3_reader_c_explicit_false' -Tool 'editor_get_test_report' -Arguments @{ clear = $false }
    $explicitFalsePayload = Get-Payload $explicitFalse
    Check 'explicit_false_is_also_a_pure_read' `
        (([int]$explicitFalsePayload.total -eq 2) -and (@($explicitFalsePayload.cleared).Count -eq 0) -and (Test-Path $bridgeAbs)) `
        ("total={0} cleared={1} file still there={2}" -f $explicitFalsePayload.total, (ConvertTo-CompactJson $explicitFalsePayload.cleared), (Test-Path $bridgeAbs))

    # --- (3) only `clear: true` deletes, and it names what it emptied --------
    $explicit = Invoke-Tool -Id 'G3_explicit_clear_true' -Tool 'editor_get_test_report' -Arguments @{ clear = $true }
    $explicitPayload = Get-Payload $explicit
    Check 'explicit_true_clears_and_says_so' `
        (([int]$explicitPayload.total -eq 2) -and ($explicitPayload.cleared -contains 'editor_process') -and ($explicitPayload.cleared -contains 'game_process_file') -and ((Test-Path $bridgeAbs) -eq $false)) `
        ("total={0} cleared={1} file left={2}" -f $explicitPayload.total, (ConvertTo-CompactJson $explicitPayload.cleared), (Test-Path $bridgeAbs))

    # --- (4) the next read is honestly empty, never a fabricated total -------
    $afterClear = Invoke-Tool -Id 'G3_after_clear_plain' -Tool 'editor_get_test_report' -Arguments @{}
    $afterClearPayload = Get-Payload $afterClear
    Check 'empty_is_honest' `
        (([int]$afterClearPayload.total -eq 0) -and ($afterClearPayload.no_results -eq $true) -and ([string]$afterClearPayload.pass_rate -eq 'N/A') -and ($afterClearPayload.all_passed -eq $false) -and ($afterClearPayload.report_file_present -eq $false) -and (@($afterClearPayload.details).Count -eq 0)) `
        ("total={0} no_results={1} pass_rate={2} all_passed={3} report_file_present={4} reason={5} source={6}" -f `
                $afterClearPayload.total, $afterClearPayload.no_results, $afterClearPayload.pass_rate, $afterClearPayload.all_passed, `
                $afterClearPayload.report_file_present, $afterClearPayload.report_unavailable_reason, $afterClearPayload.source)
} finally {
    Stop-Engine -Handle $editorHandle
    Stop-Engine -Handle $gameHandle
}

$userPidAfter = Get-ListenerPid -Port_ $UserPort
Check 'port_9877_owner_after' ($userPidAfter -eq $userPidBefore) ("pid before={0} after={1}" -f $userPidBefore, $userPidAfter)

$failed = @($script:Checks | Where-Object { -not $_.pass })
Write-Host ''
Write-Host '============================================================='
Write-Host (' TASK-029 evidence: {0} checks, {1} failed' -f $script:Checks.Count, $failed.Count)
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
