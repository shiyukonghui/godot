# =============================================================================
#  mcp047_m3_mono_check.ps1 -- TASK-047 section 3, the M3 row
#
#  M3 = "mono build + a C# project comes up". The batch's minimum set is:
#
#      rebuild the mono build (scons ... module_mono_enabled=yes)
#      + let one C# project start
#
#  Why this is not `mcp014_m3_evidence.ps1 -Phase m3`: that script aborts right
#  after its sixth check at this HEAD with
#
#      Write-Utf8NoBom : The term 'Write-Utf8NoBom' is not recognized ...
#      (mcp014_m3_evidence.ps1:183)
#
#  a leftover of the TASK-028 refactor (the local writer was replaced by
#  `mcp_import_guard.ps1`'s `Write-McpUtf8NoBom`, and line 183 kept the old
#  name). The same run did reach its first six checks and they are real evidence
#  (SDK version, local nupkgs, `dotnet build` exit 0, the project assembly, the
#  mono `--version`, and both endpoints up); this script continues from there and
#  proves the part the milestone is named after - that the C# code really runs.
#
#  It reuses the C# project that run built
#  (`%TEMP%\mcp014-scratch\m3-csharp-proj`, `.godot/mono/temp/bin/Debug/Mcp014Csharp.dll`)
#  so that nothing is recompiled here: the point is the *runtime*, not the build.
#
#  Port discipline: 9877 is never occupied (the shared `mcp_port_guard.ps1`
#  classification decides it); this script owns 9889 only.
#
#  Pure ASCII (the PowerShell 5.1 encoding rule this module follows).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp047_m3_mono_check.ps1 `
#        -Engine <repo>\bin\godot.windows.editor.x86_64.mono.console.exe
# =============================================================================

param(
    [string]$Engine = '',
    [string]$Project = '',
    [int]$GamePort = 9889,
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($Engine)) { $Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe' }
if ([string]::IsNullOrWhiteSpace($Project)) { $Project = Join-Path $env:TEMP 'mcp014-scratch\m3-csharp-proj' }
$Engine = (Resolve-Path $Engine).Path
$Project = (Resolve-Path $Project).Path
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$UserPort = 9877

$Root = Join-Path $env:TEMP 'mcp047-m3-mono'
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'

. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')
# TASK-072 (D130): the anchor criterion lives in check_engine_anchor.ps1 only.
. (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

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
    param([int]$Id, [string]$Tool, $Arguments)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Invoke-Json {
    param([string]$Id, [string]$Json, [int]$MaxTimeSec = 60)
    $bodyFile = Join-Path $Ev ("{0}.request.json" -f $Id)
    $respFile = Join-Path $Ev ("{0}.response.json" -f $Id)
    Write-Utf8NoBom -Path $bodyFile -Text $Json
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time $MaxTimeSec -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $GamePort) | Out-Null
    $curlExit = $LASTEXITCODE
    $text = ''
    if (Test-Path $respFile) { $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($respFile)) }
    Write-Host ("[{0}] curl_exit={1} bytes={2}" -f $Id, $curlExit, $text.Length)
    return $text
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments)
    return (Invoke-Json -Id $Id -Json (New-CallBody -Id 1 -Tool $Tool -Arguments $Arguments))
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

# The engine holds its stdout log for the whole run, so an observer has to ask
# for `ReadWrite` sharing (the same reason `mcp044` has this helper).
function Read-TextShared {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object IO.StreamReader($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Close() }
    } finally { $stream.Close() }
}

function Wait-ForEndpoint {
    param([int]$Port_, [int]$TimeoutMs)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Join-Path $Ev 'status.json'
        & $Curl -s --max-time 5 -o $probe ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (Test-Path $probe) {
            try {
                $parsed = ConvertFrom-Json ([IO.File]::ReadAllText($probe))
                if ($null -ne $parsed.frame_count) { return $true }
            } catch { }
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# =============================================================================
#  Main
# =============================================================================
Write-Host '============================================================='
Write-Host ' TASK-047 M3 row: a C# project comes up under the mono build'
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host ("FATAL: engine not found: {0}" -f $Engine); exit 2 }
if (-not (Test-Path $Project)) { Write-Host ("FATAL: C# project not found: {0}" -f $Project); exit 2 }
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

$versionText = ((& $Engine --version 2>$null) -join ' ').Trim()
$headSha = ((& git -C $RepoRoot rev-parse --short=9 HEAD) -join '').Trim()
Write-Host ("engine: {0}" -f $Engine)
Write-Host ("engine sha256: {0}" -f (Get-FileHash -Algorithm SHA256 -Path $Engine).Hash.ToLower())
Write-Host ("engine --version: {0}; git HEAD: {1}" -f $versionText, $headSha)

Check 'm3a_engine_is_the_mono_build' ($versionText.Contains('.mono.')) ("--version = '{0}'" -f $versionText)
# TASK-072 (D130): one judge decides the anchor; see check_engine_anchor.ps1.
$anchorVerdict = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $versionText -HeadSha $headSha
Check 'm3b_mono_engine_version_matches_head' ($anchorVerdict.Ok) `
    (("--version = '{0}' carries git HEAD short sha '{1}'" -f $versionText, $headSha) + ' | ' + $anchorVerdict.Summary)

$assembly = Join-Path $Project '.godot\mono\temp\bin\Debug\Mcp014Csharp.dll'
$assemblyOk = Test-Path $assembly
$assemblyBytes = if ($assemblyOk) { (Get-Item $assembly).Length } else { 0 }
$assemblySha = if ($assemblyOk) { (Get-FileHash -Algorithm SHA256 -Path $assembly).Hash.ToLower() } else { '<missing>' }
Check 'm3c_csharp_project_assembly_present' $assemblyOk `
    ("{0} ({1} bytes, sha256={2})" -f $assembly, $assemblyBytes, $assemblySha)

$userPidBefore = Get-ListenerPid -Port_ $UserPort
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("user editor on {0} before: pid={1}" -f $UserPort, $userPidBefore)
Check 'port_9889_free_before' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

# The expected game endpoint size is derived from the module's own two documents,
# not written down: the **contract** (171 entries - `tool-rename-map.json` carries
# 174 rows, three of which are not contract entries) minus every tool whose scope
# is `editor`.
$map = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $RepoRoot 'modules\mcp_server\docs\tool-rename-map.json'), (New-Object Text.UTF8Encoding($false))))
$scopeOf = @{}
foreach ($entry in @($map.tools)) { $scopeOf[[string]$entry.new_name] = [string]$entry.scope }
$contract = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'), (New-Object Text.UTF8Encoding($false))))
$contractNames = @($contract.result.tools | ForEach-Object { [string]$_.name })
$editorOnly = @($contractNames | Where-Object { $scopeOf[$_] -eq 'editor' })
$expectedGameTools = $contractNames.Count - $editorOnly.Count
Write-Host ("map rows={0}; contract entries={1}; scope=editor among the contract={2}; expected game endpoint = {3}" -f @($map.tools).Count, $contractNames.Count, $editorOnly.Count, $expectedGameTools)

$handle = $null
try {
    $arguments = @('--headless', '--path', $Project, ("--mcp-port={0}" -f $GamePort))
    $handle = Start-Process -FilePath $Engine -ArgumentList $arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot 'game.out.log') `
        -RedirectStandardError (Join-Path $LogRoot 'game.err.log') -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $arguments
    Write-Host ("started mono game pid={0} :: {1}" -f $handle.Id, ($arguments -join ' '))

    $ready = Wait-ForEndpoint -Port_ $GamePort -TimeoutMs $ReadyTimeoutMs
    Check 'm3d_mono_csharp_game_endpoint_ready' $ready ("mono game on {0} answered GET /mcp" -f $GamePort)

    $listText = Invoke-Json -Id 'm3_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
    $names = @()
    try { $names = @((ConvertFrom-Json $listText).result.tools | ForEach-Object { [string]$_.name }) } catch { }
    Check 'm3e_mono_game_serves_the_whole_game_endpoint' ($names.Count -eq $expectedGameTools) `
        ("tools/list under mono = {0} tool(s); expected {1} (the contract minus the scope=editor tools) - the module is the same one the non-mono build serves" -f $names.Count, $expectedGameTools)

    Start-Sleep -Seconds 2
    $logText = ''
    $logPath = Join-Path $LogRoot 'game.out.log'
    $logText = Read-TextShared -Path $logPath
    $readyLines = @()
    foreach ($line in ($logText -split "`n")) { if ($line -match 'MCP014-CS') { $readyLines += $line.Trim() } }
    Check 'm3f_csharp_script_ready_ran' (@($readyLines | Where-Object { $_ -match '_Ready ran' }).Count -ge 1) `
        ("the C# script's own stdout line: '{0}'" -f (@($readyLines)[0]))

    $discoverCode = @'
var names := []
var tree := Engine.get_main_loop() as SceneTree
for p in tree.current_scene.get_property_list():
    names.append(String(p.name))
return names
'@
    $discover = Invoke-Tool -Id 'm3g_discover' -Tool 'running_game_execute_gdscript' -Arguments @{ code = $discoverCode }
    $discoverPayload = Get-Payload $discover
    $propertyNames = @()
    if ($null -ne $discoverPayload) { $propertyNames = @($discoverPayload.result | ForEach-Object { [string]$_ }) }
    $ticksName = (@($propertyNames | Where-Object { ($_ -replace '_', '').ToLower() -eq 'csharpticks' }))[0]
    $stateName = (@($propertyNames | Where-Object { ($_ -replace '_', '').ToLower() -eq 'csharpstate' }))[0]
    Check 'm3g_csharp_members_are_visible_to_the_module' (($null -ne $ticksName) -and ($null -ne $stateName)) `
        ("the C# members appear in the Godot property list the C++ module reads: ticks='{0}' state='{1}' (of {2} properties)" -f $ticksName, $stateName, $propertyNames.Count)

    $reportCode = 'var tree := Engine.get_main_loop() as SceneTree' + "`n" + 'return tree.current_scene.call("CsharpReport")'
    $report = Invoke-Tool -Id 'm3h_report' -Tool 'running_game_execute_gdscript' -Arguments @{ code = $reportCode }
    $reportPayload = Get-Payload $report
    $reportText = if ($null -ne $reportPayload) { [string]$reportPayload.result } else { '' }
    $ticks = -1
    if ($reportText -match 'ticks=(\d+)') { $ticks = [int]$Matches[1] }
    Check 'm3h_csharp_method_reaches_the_wire' (($reportText -match '^csharp: ticks=\d+ state=csharp-ready$') -and ($ticks -gt 0)) `
        ("running_game_execute_gdscript -> C# CsharpReport() = '{0}' (ticks>0 proves the C# _Process ran inside the mono build)" -f $reportText)

    $write = Invoke-Tool -Id 'm3i_write' -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'Main'; property = $stateName; value = 'written-from-mcp' }
    $after = Invoke-Tool -Id 'm3j_report_after' -Tool 'running_game_execute_gdscript' -Arguments @{ code = $reportCode }
    $afterPayload = Get-Payload $after
    $afterText = if ($null -ne $afterPayload) { [string]$afterPayload.result } else { '' }
    Check 'm3i_cplusplus_write_is_seen_by_the_csharp_code' `
        (((Get-ErrorCode $write) -eq 0) -and ($afterText -match 'state=written-from-mcp')) `
        ("after running_game_set_node_property('{0}' = 'written-from-mcp') (error_code={1}), the C# method reports '{2}'" -f $stateName, (Get-ErrorCode $write), $afterText)
} finally {
    if ($null -ne $handle -and -not $handle.HasExited) {
        & taskkill /PID $handle.Id /T /F *> (Join-Path $LogRoot 'taskkill.log')
        Start-Sleep -Milliseconds 1200
    }
}

$portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence

$logFile = Join-Path $Ev 'evidence.log.txt'
$summary = @()
foreach ($entry in $script:Checks) {
    $entryTag = if ($entry.pass) { 'PASS' } else { 'FAIL' }
    $summary += ("[{0}] {1} :: {2}" -f $entryTag, $entry.id, $entry.evidence)
}
Write-Utf8NoBom -Path $logFile -Text (($summary -join "`r`n") + "`r`n")
$resultsFile = Join-Path $Ev 'results.json'
Write-Utf8NoBom -Path $resultsFile -Text (ConvertTo-Json -InputObject $script:Checks -Depth 6)

$passed = @($script:Checks | Where-Object { $_.pass }).Count
$total = $script:Checks.Count
Write-Host ''
Write-Host ("M3 mono/C# check: {0}/{1} checks passed; evidence in {2}" -f $passed, $total, $Ev)
Write-Host ("log sha256 = {0}" -f (Get-FileHash -Algorithm SHA256 -Path $logFile).Hash.ToLower())
if ($passed -ne $total) {
    foreach ($entry in $script:Checks) { if (-not $entry.pass) { Write-Host ("  FAILED {0} :: {1}" -f $entry.id, $entry.evidence) } }
    exit 1
}
exit 0
