# =============================================================================
#  mcp071_gate2_live_evidence.ps1 -- TASK-071 gate 2 (live three-class evidence).
#
#  TASK-071 changes no tool, no contract entry and no generator, so this gate's
#  subject is not "a new group's tools" but the live endpoints: the module still
#  serves the SAME 176 contract entries (153 editor / 72 game / 176 union) and
#  still answers the three classes of request a tool must distinguish:
#
#    * SUCCESS          - a well-formed call returns a result;
#    * MISSING PARAM    - `-32602`;
#    * UNDERLYING FAIL  - `-32001` with `data.suggestion`.
#
#  It also walks one CROSS-TOOL chain (create -> read -> validate), because that
#  is the evidence class that has caught real defects the doctests could not.
#
#  Every response body lands on disk through `curl.exe -s -o <file>` (never a
#  PowerShell pipeline: PLAYBOOK section 7.1) and its sha256 is printed from the
#  bytes on disk.
#
#  Ports: 9888 (editor) / 9889 (game). The user's editor on 9877 is never
#  requested and never touched; `mcp_port_guard.ps1` asserts that.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp071_gate2_live_evidence.ps1
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$OutRoot = '',
    [string]$EnginePath = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$ModuleRoot = Join-Path $RepoRoot 'modules\mcp_server'
$Contract = Join-Path $ModuleRoot 'docs\tools_list.renamed.json'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$utf8 = [Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($EnginePath)) {
    $EnginePath = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
}
$Engine = (Resolve-Path $EnginePath).Path

$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877

if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp071\gate2' }
Remove-Item -Recurse -Force $OutRoot -ErrorAction SilentlyContinue
$Proj = Join-Path $OutRoot 'proj'
$Ev = Join-Path $OutRoot 'evidence'
$LogRoot = Join-Path $OutRoot 'logs'
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_evidence_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]
function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}
function Get-Sha {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '<absent>' }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}
function Get-ListenerPid {
    param([int]$Port_)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port_ + "\s")) { return [int](($line.Trim() -split '\s+')[-1]) }
    }
    return -1
}
function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $handle = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $Arguments
    return $handle
}
function Stop-Engine {
    param($Handle)
    if ($null -ne $Handle -and -not $Handle.HasExited) {
        Stop-Process -Id $Handle.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}
function Wait-ForPump {
    param([int]$Port_, [int]$Iterations = 240)
    for ($i = 0; $i -lt $Iterations; $i++) {
        Start-Sleep -Milliseconds 1000
        $out = Join-Path $Ev ("status-{0}.json" -f $Port_)
        & $Curl '-s' '--max-time' '5' '-o' $out ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (Test-Path $out) {
            try {
                $probe = ConvertFrom-Json ([IO.File]::ReadAllText($out, $utf8))
                if ($null -ne $probe.frame_count -and [int]$probe.frame_count -ge 20) { return $true }
            } catch { }
        }
    }
    return $false
}

# One JSON-RPC request: the body is a file (no BOM), the response is written by
# curl itself, and the bytes on disk are the evidence.
function Invoke-Mcp {
    param([int]$Port_, [string]$Id, [string]$Method, [hashtable]$Params, [string]$Tag)
    $bodyFile = Join-Path $Ev ($Tag + '.request.json')
    $respFile = Join-Path $Ev ($Tag + '.response.json')
    $payload = @{ jsonrpc = '2.0'; id = 1; method = $Method }
    if ($null -ne $Params) { $payload['params'] = $Params }
    Write-McpUtf8NoBom -Path $bodyFile -Text ($payload | ConvertTo-Json -Depth 12 -Compress)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl '-s' '--max-time' '90' '-o' $respFile '-H' 'Content-Type: application/json' '--data-binary' ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = Get-Sha $respFile
    $json = $null
    try { $json = ConvertFrom-Json ([IO.File]::ReadAllText($respFile, $utf8)) } catch { }
    return [pscustomobject]@{ File = $respFile; Bytes = $bytes.Length; Sha256 = $sha; Json = $json; Tag = $Tag }
}

function Get-ToolResultText {
    param($Json)
    if ($null -eq $Json) { return '' }
    if ($null -eq $Json.result) { return '' }
    if ($null -eq $Json.result.content) { return '' }
    foreach ($part in @($Json.result.content)) {
        if ($null -ne $part.text) { return [string]$part.text }
    }
    return ''
}

New-McpScratchProject -Path $Proj -Name 'MCP071 gate 2 live evidence' -WithMainScene $true | Out-Null
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)

$porcelainBefore = @(& git -C $RepoRoot status --porcelain -uall 2>$null)
$porcelainBeforeSha = Get-McpEvidenceContentSha256 -Text (($porcelainBefore -join "`n") + "`n")

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'G201_import_ok' ($import.exit_code -eq 0) ("--import exit={0} after {1} attempt(s)" -f $import.exit_code, $import.attempts)

$contractDoc = ConvertFrom-Json ([IO.File]::ReadAllText($Contract, $utf8))
$contractNames = @{}
foreach ($tool in $contractDoc.result.tools) { $contractNames[[string]$tool.name] = $true }
Write-Host ("contract entries: {0}" -f $contractNames.Count)

$editorHandle = $null
$gameHandle = $null
try {
    # -----------------------------------------------------------------------
    #  editor endpoint (9888)
    # -----------------------------------------------------------------------
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'G202_editor_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $listEd = Invoke-Mcp -Port_ $EditorPort -Id 'list' -Method 'tools/list' -Params @{} -Tag 'editor_tools_list'
    Check 'G203_editor_tools_list_fetched' ($listEd.Bytes -gt 0) ("bytes={0} sha256={1}" -f $listEd.Bytes, $listEd.Sha256)
    $liveEd = @{}
    foreach ($tool in $listEd.Json.result.tools) { $liveEd[[string]$tool.name] = $true }
    Check 'G204_editor_live_count_is_153' ($liveEd.Count -eq 153) ("live editor tools/list carries {0} tool(s) (TASK-070: 153)" -f $liveEd.Count)

    # -----------------------------------------------------------------------
    #  game endpoint (9889)
    # -----------------------------------------------------------------------
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, "--mcp-port=$GamePort") -LogName 'game'
    Check 'G205_game_ready' (Wait-ForPump -Port_ $GamePort) ("game on {0} answered GET /mcp with +20 frames" -f $GamePort)

    $listGame = Invoke-Mcp -Port_ $GamePort -Id 'list' -Method 'tools/list' -Params @{} -Tag 'game_tools_list'
    Check 'G206_game_tools_list_fetched' ($listGame.Bytes -gt 0) ("bytes={0} sha256={1}" -f $listGame.Bytes, $listGame.Sha256)
    $liveGame = @{}
    foreach ($tool in $listGame.Json.result.tools) { $liveGame[[string]$tool.name] = $true }
    Check 'G207_game_live_count_is_72' ($liveGame.Count -eq 72) ("live game tools/list carries {0} tool(s) (TASK-070: 72)" -f $liveGame.Count)

    # The declared contract is the UNION of the two endpoints' live lists - the
    # assertion that no entry was dropped and no unlisted tool appeared.
    $union = @{}
    foreach ($n in $liveEd.Keys) { $union[$n] = $true }
    foreach ($n in $liveGame.Keys) { $union[$n] = $true }
    $missingFromLive = @($contractNames.Keys | Where-Object { -not $union.ContainsKey($_) })
    $extraInLive = @($union.Keys | Where-Object { -not $contractNames.ContainsKey($_) })
    # TASK-076 section A.2: the size is DERIVED from the artifact this assertion
    # is about - the contract file read a few lines above - instead of being
    # written down. It used to be the literal 176, which went stale the moment
    # TASK-075 moved the contract to 177: that is the "stale expectation" class
    # TASK-064/068 closed elsewhere, and the survey
    # (scripts/check_hardcoded_counts.py) reported this line as UNCLASSIFIED
    # precisely because a bare literal there decides the gate. The assertion is
    # NOT relaxed: the derived count is still checked, and the two set
    # comparisons below it (missing from live / not in the contract) are the
    # name-for-name half. scripts/mcp076_gate2_union_count_reverse_probe.ps1
    # proves the derivation is non-vacuous on a mutated union.
    Check 'G208_live_union_equals_the_contract_entries' `
        (($union.Count -eq $contractNames.Count) -and ($missingFromLive.Count -eq 0) -and ($extraInLive.Count -eq 0)) `
        ("union={0}; contract={1}; missing from live={2}; not in the contract={3}" -f $union.Count, $contractNames.Count, $missingFromLive.Count, $extraInLive.Count)

    # -----------------------------------------------------------------------
    #  the three classes on the editor endpoint
    # -----------------------------------------------------------------------
    $ok = Invoke-Mcp -Port_ $EditorPort -Id 'ok' -Method 'tools/call' -Params @{ name = 'project_get_info'; arguments = @{} } -Tag 'class_success_project_get_info'
    $okText = Get-ToolResultText -Json $ok.Json
    Check 'G210_success_class' (($null -ne $ok.Json.result) -and (-not $ok.Json.result.isError) -and (-not [string]::IsNullOrWhiteSpace($okText))) `
        ("bytes={0} sha256={1}; non-empty result content: {2}" -f $ok.Bytes, $ok.Sha256, $okText.Substring(0, [Math]::Min(160, $okText.Length)))

    $missing = Invoke-Mcp -Port_ $EditorPort -Id 'missing' -Method 'tools/call' -Params @{ name = 'project_read_script'; arguments = @{} } -Tag 'class_missing_param_project_read_script'
    $missingCode = $null
    if ($null -ne $missing.Json.error) { $missingCode = [int]$missing.Json.error.code }
    Check 'G211_missing_param_class_is_32602' ($missingCode -eq -32602) `
        ("bytes={0} sha256={1}; error.code={2}; message={3}" -f $missing.Bytes, $missing.Sha256, $missingCode, $(if ($null -ne $missing.Json.error) { [string]$missing.Json.error.message } else { '<none>' }))

    $under = Invoke-Mcp -Port_ $EditorPort -Id 'under' -Method 'tools/call' -Params @{ name = 'project_read_script'; arguments = @{ path = 'res://mcp071_does_not_exist.gd' } } -Tag 'class_underlying_failure_project_read_script'
    $underCode = $null
    $underSuggestion = $null
    if ($null -ne $under.Json.error) {
        $underCode = [int]$under.Json.error.code
        if ($null -ne $under.Json.error.data) { $underSuggestion = [string]$under.Json.error.data.suggestion }
    }
    Check 'G212_underlying_failure_class_is_32001_with_suggestion' (($underCode -eq -32001) -and (-not [string]::IsNullOrWhiteSpace($underSuggestion))) `
        ("bytes={0} sha256={1}; error.code={2}; data.suggestion={3}" -f $under.Bytes, $under.Sha256, $underCode, $underSuggestion)

    # -----------------------------------------------------------------------
    #  one cross-tool chain: create -> read -> validate
    # -----------------------------------------------------------------------
    $chainPath = 'res://mcp071_chain_tool.gd'
    $chainSource = "extends Node`n`nfunc mcp071_marker() -> int:`n`treturn 71`n"
    $created = Invoke-Mcp -Port_ $EditorPort -Id 'chain1' -Method 'tools/call' -Params @{ name = 'project_create_script'; arguments = @{ path = $chainPath; content = $chainSource } } -Tag 'chain1_create_script'
    $createdText = Get-ToolResultText -Json $created.Json
    $read = Invoke-Mcp -Port_ $EditorPort -Id 'chain2' -Method 'tools/call' -Params @{ name = 'project_read_script'; arguments = @{ path = $chainPath } } -Tag 'chain2_read_script'
    $readText = Get-ToolResultText -Json $read.Json
    $validated = Invoke-Mcp -Port_ $EditorPort -Id 'chain3' -Method 'tools/call' -Params @{ name = 'project_validate_script'; arguments = @{ path = $chainPath } } -Tag 'chain3_validate_script'
    $validatedText = Get-ToolResultText -Json $validated.Json
    $onDisk = Join-Path $Proj 'mcp071_chain_tool.gd'
    Check 'G220_cross_tool_chain_create_read_validate' `
        ((Test-Path $onDisk) -and ($readText.Contains('mcp071_marker')) -and ($validatedText.Contains('valid'))) `
        ("create sha256={0}; read sha256={1} carries the marker={2}; validate sha256={3} carries 'valid'={4}; bytes on disk={5}" -f `
            $created.Sha256, $read.Sha256, $readText.Contains('mcp071_marker'), $validated.Sha256, $validatedText.Contains('valid'), (Get-Item $onDisk).Length)
} finally {
    Stop-Engine $gameHandle
    Stop-Engine $editorHandle
}

# ---------------------------------------------------------------------------
#  the user's port and the repository are untouched
# ---------------------------------------------------------------------------
$portVerdict = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'G230_user_port_9877_untouched' ($portVerdict.pass) `
    ("{0}: {1}" -f $portVerdict.classification, $portVerdict.evidence)

$porcelainAfter = @(& git -C $RepoRoot status --porcelain -uall 2>$null)
$porcelainAfterSha = Get-McpEvidenceContentSha256 -Text (($porcelainAfter -join "`n") + "`n")
$porcelainDiff = @(Compare-Object $porcelainBefore $porcelainAfter)
Check 'G231_repository_porcelain_byte_identical' (($porcelainDiff.Count -eq 0) -and ($porcelainBeforeSha -ceq $porcelainAfterSha)) `
    ("git status --porcelain -uall before={0} line(s) sha256={1} after={2} line(s) sha256={3} differing={4}" -f `
        $porcelainBefore.Count, $porcelainBeforeSha.Substring(0, 12), $porcelainAfter.Count, $porcelainAfterSha.Substring(0, 12), $porcelainDiff.Count)

$failures = 0
Write-Host ''
Write-Host '--- summary ---'
foreach ($c in $script:Checks) {
    if (-not $c.pass) { $failures++ }
    Write-Host ("[{0}] {1} :: {2}" -f $(if ($c.pass) { 'PASS' } else { 'FAIL' }), $c.id, $c.evidence)
}
$summaryFile = Join-Path $Ev 'summary.txt'
[IO.File]::WriteAllLines($summaryFile, @($script:Checks | ForEach-Object { ("[{0}] {1} :: {2}" -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence) }))
Write-Host ('--- checks: {0}, failures: {1} ---' -f $script:Checks.Count, $failures)
Write-Host ('--- evidence root: {0} ---' -f $Ev)
if ($failures -gt 0) { Write-Host ('GATE 2 LIVE EVIDENCE FAILED: {0}' -f $failures); exit 1 }
Write-Host ('GATE 2 LIVE EVIDENCE PASS ({0} contract entries live, three request classes distinguished, one cross-tool chain closed)' -f $contractNames.Count)
exit 0
