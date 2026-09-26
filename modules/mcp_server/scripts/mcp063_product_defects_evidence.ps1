# =============================================================================
#  mcp063_product_defects_evidence.ps1 -- TASK-063, the live evidence of the
#  second round's four product defects.
#
#  It answers gate 2 of the PLAYBOOK for this batch, one phase per defect:
#
#    A  (a) D-7, the silent disabled endpoint. Phase A starts a *game* process
#       whose requested port is already held, three ways:
#         A1  reproduction: a real listener the script starts itself holds 9889,
#             the game is told --mcp-port=9889, and its stderr/stdout are read to
#             show the ERROR line naming the requested port, the diagnosed reason
#             and the disabled endpoint - plus the endpoint_disabled trace event
#             when --mcp-trace is on;
#         A2  the same game process on a free port really binds, and its
#             tools/list answers the game endpoint's tool count - the "the E-10
#             injection really binds" half;
#         A3  the conflict is *not* silent and is *not* a fake success: the
#             disabled process serves nothing (curl fails) and its recorded state
#             is what the log says it is.
#    B  (b) D-5/O-2/O-3, the path parameter surface. On the editor endpoint:
#         B1  `/root/Main/Ball` -> -32001 whose data.suggestion names the
#             parameter, the basis and the accepted spelling;
#         B2  the right spelling (`Main/Ball`) -> success, and the read-back is
#             the value that was written;
#         B3  `node_path` on the singular tool -> -32602 whose data.suggestion
#             names 'path'; the singular spelling on the plural tool -> the
#             suggestion names 'node_paths';
#         B4  the live `tools/list` descriptions carry the rule sentence on all
#             three tools, verbatim against the contract - and the parameter
#             names did NOT move (contract count unchanged for them).
#    C  (c) D-6/M-1, the new tool. On the editor endpoint:
#         C1  four nodes, four different values in ONE call, one of them
#             out-of-range -> three land with per-entry old/new/changed, one is
#             refused with its own code;
#         C2  the read-back with a *different* tool
#             (editor_get_node_properties) proves the three landed and the
#             fourth did not;
#         C3  stop_on_error:true is all-or-nothing: the take-back puts the first
#             entry back and the answer says so;
#         C4  the type-scoped sibling still writes one value everywhere - the
#             two scopes side by side;
#         C5  the out-of-range refusal is the SAME gate the single-node writer
#             uses (`editor_set_node_property` refuses the same value for the
#             same property), which is the "not a back door" proof.
#    D  (d) D-10, the parse error line. On the editor endpoint:
#         D1  `editor_execute_gdscript{code:"var x = )"}` -> -32602 naming line 1
#             of `code`, with data.parse_error carrying the line and stating that
#             the column is not available;
#         D2  the same error on the caller's second line is named as line 2;
#         D3  a different tool's parse error (a real `.gd` file with a syntax
#             error, validated by project_validate_script) is unaffected, and a
#             valid body still runs - the boundary of what moved.
#
#  Port discipline: the user's editor on 9877 is never started, killed or
#  restarted - only observed, before and after; only 9888/9889 (and one
#  ephemeral port the script probes for the "free port" half) are used.
#
#  Every response body is written with `curl.exe -s -o <file>` and hashed; no
#  response body ever travels through a pipe (PLAYBOOK section 7.1).
#
#  ASCII only.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp063_product_defects_evidence.ps1
# =============================================================================

param(
    [string]$PlainEngine = '',
    [int]$EditorPort = 9888,
    [int]$GamePort = 9889,
    [int]$ReadyTimeoutMs = 300000,
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($PlainEngine)) { $PlainEngine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe' }
$PlainEngine = (Resolve-Path $PlainEngine).Path
$ContractPath = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$UserPort = 9877

if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp063' }
$Ev = Join-Path $OutRoot 'evidence'
$LogRoot = Join-Path $OutRoot 'logs'
$Project = Join-Path $OutRoot 'proj063'

. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-072 (D130): the anchor criterion lives in check_engine_anchor.ps1 only.
. (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]
$script:StepHashes = New-Object System.Collections.Generic.List[object]

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

function Read-TextShared {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object IO.StreamReader($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Close() }
    } finally { $stream.Close() }
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
    if ($bytes.Count -gt 0) {
        $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    } else {
        $sha = '<empty>'
    }
    Write-Host ("[{0}] port={1} curl_exit={2} bytes={3} sha256={4}" -f $Id, $Port_, $curlExit, $bytes.Count, $sha)
    $script:StepHashes.Add([pscustomobject]@{ id = $Id; bytes = $bytes.Count; sha256 = $sha })
    return $text
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 9888, [int]$MaxTimeSec = 300)
    return (Invoke-Json -Id $Id -Json (New-CallBody -Id 1 -Tool $Tool -Arguments $Arguments) -Port_ $Port_ -MaxTimeSec $MaxTimeSec)
}

function Get-Payload {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.result) { return $null }
        if ($envelope.result.PSObject.Properties.Name -contains 'isError' -and $envelope.result.isError) { return $null }
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

function Get-ErrorMessage {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return '' }
        return [string]$envelope.error.message
    } catch { return '' }
}

function Get-ErrorData {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return $null }
        return $envelope.error.data
    } catch { return $null }
}

function Get-Suggestion {
    param([string]$Text)
    $data = Get-ErrorData $Text
    if ($null -eq $data) { return '' }
    return [string]$data.suggestion
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

function Start-McpEngine {
    param([string]$Engine, [string]$ProjectPath, [int]$Port_, [string]$Name, [switch]$Editor, [switch]$WithTrace, [string[]]$Extra = @())
    $arguments = @('--headless')
    if ($Editor) { $arguments += '-e' }
    $arguments += @('--path', $ProjectPath)
    if ($Port_ -gt 0) { $arguments += ("--mcp-port={0}" -f $Port_) }
    if ($WithTrace) { $arguments += ("--mcp-trace={0}" -f (Join-Path $LogRoot ($Name + '.trace.jsonl'))) }
    if ($Extra.Count -gt 0) { $arguments += $Extra }
    $handle = Start-Process -FilePath $Engine -ArgumentList $arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($Name + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($Name + '.err.log')) -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $arguments
    Write-Host ("started {0} pid={1} :: {2}" -f $Name, $handle.Id, ($arguments -join ' '))
    return $handle
}

function Stop-McpEngine {
    param($Handle, [string]$Name)
    if ($null -ne $Handle -and -not $Handle.HasExited) {
        & taskkill /PID $Handle.Id /T /F *> (Join-Path $LogRoot ($Name + '.taskkill.log'))
        Start-Sleep -Milliseconds 1200
    }
}

# Waits for a process that is expected to stay alive (a game whose bind failed
# keeps running - the requirement is explicit that the failure must not take the
# engine down).
function Wait-ForLogText {
    param([string]$Path, [string]$Needle, [int]$TimeoutMs)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $text = Read-TextShared $Path
        if ($text.Contains($Needle)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Get-ToolEntry {
    param($ListText, [string]$ToolName)
    try {
        $envelope = ConvertFrom-Json $ListText
        foreach ($entry in @($envelope.result.tools)) {
            if ([string]$entry.name -ceq $ToolName) { return $entry }
        }
    } catch { }
    return $null
}

function Get-ToolNames {
    param($ListText)
    $names = @()
    try {
        $envelope = ConvertFrom-Json $ListText
        $names = @($envelope.result.tools | ForEach-Object { [string]$_.name })
    } catch { }
    return $names
}

function Get-TextSha {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLower()
    } finally { $sha.Dispose() }
}

function Show-Step {
    param([string]$Label, [string]$Text)
    $short = $Text
    if ($short.Length -gt 800) { $short = $short.Substring(0, 800) + '...' }
    Write-Host ("--- {0} ---" -f $Label)
    Write-Host $short
}

function Select-PortEntry {
    param($Out, [string]$NodePath)
    foreach ($item in @($Out.results)) { if ([string]$item.path -ceq $NodePath) { return $item } }
    return $null
}

function Start-PortHolder {
    param([int]$Port_)
    # A real listener on 127.0.0.1:Port_, started by this script, so the
    # "occupied" scenario is reproducible without a second Godot process. The
    # helper is a one-line .NET TcpListener server; it is stopped by
    # `Stop-PortHolder`.
    $log = Join-Path $LogRoot ("port-holder-{0}.log" -f $Port_)
    $code = 'using System;using System.Net;using System.Net.Sockets;using System.Threading;' +
            'public class H{public static void Main(){var l=new TcpListener(IPAddress.Parse("127.0.0.1"),' + $Port_ + ');' +
            'l.Start();Console.WriteLine("holding");while(true){Thread.Sleep(1000);}}}'
    $cs = Join-Path $OutRoot 'port-holder.cs'
    Write-McpUtf8NoBom -Path $cs -Text $code
    $exe = Join-Path $OutRoot 'port-holder.exe'
    $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (Test-Path $csc) {
        & $csc /nologo /out:$exe $cs *> (Join-Path $LogRoot 'port-holder-csc.log')
    }
    if (Test-Path $exe) {
        $handle = Start-Process -FilePath $exe -PassThru -RedirectStandardOutput $log -WindowStyle Hidden
    } else {
        # Fall back to PowerShell's own TcpListener, which needs no compiler.
        $script:PortHolderPowerShell = Start-Job -ScriptBlock {
            param($p)
            $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse('127.0.0.1'), $p)
            $listener.Start()
            while ($true) { Start-Sleep -Seconds 1 }
        } -ArgumentList $Port_
        $handle = $script:PortHolderPowerShell
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ((Get-ListenerPid -Port_ $Port_) -gt 0) { return $handle }
        Start-Sleep -Milliseconds 300
    }
    return $handle
}

function Stop-PortHolder {
    param($Handle)
    if ($null -eq $Handle) { return }
    if ($Handle -is [System.Management.Automation.Job]) {
        Stop-Job -Job $Handle -ErrorAction SilentlyContinue
        Remove-Job -Job $Handle -Force -ErrorAction SilentlyContinue
    } elseif (-not $Handle.HasExited) {
        & taskkill /PID $Handle.Id /T /F *> (Join-Path $LogRoot 'port-holder-taskkill.log')
    }
    Start-Sleep -Milliseconds 800
}

# =============================================================================
#  Main
# =============================================================================
Write-Host '============================================================='
Write-Host ' TASK-063: the second round four product defects (live evidence)'
Write-Host '============================================================='

if (-not (Test-Path $PlainEngine)) { Write-Host ("FATAL: engine not found: {0}" -f $PlainEngine); exit 2 }
if (-not (Test-Path $ContractPath)) { Write-Host ("FATAL: contract not found: {0}" -f $ContractPath); exit 2 }

Remove-Item -Recurse -Force $OutRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

$headSha = ((& git -C $RepoRoot rev-parse --short=9 HEAD) -join '').Trim()
$version = ((& $PlainEngine --version 2>$null) -join ' ').Trim()
# TASK-072 (D130): one judge decides the anchor; see check_engine_anchor.ps1.
$anchorVerdict = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $version -HeadSha $headSha
Check 'engine_matches_head' ($anchorVerdict.Ok) `
    (("engine --version='{0}' git rev-parse --short=9 HEAD='{1}'" -f $version, $headSha) + ' | ' + $anchorVerdict.Summary)

$contract = ConvertFrom-Json (Read-TextShared $ContractPath)
$contractNames = @($contract.result.tools | ForEach-Object { [string]$_.name })
$addedNames = @($contract._meta.added_tools | ForEach-Object { [string]$_ })
Check 'contract_is_176_entries' ($contractNames.Count -eq 176) `
    ("_meta.count={0} contract entries={1}" -f $contract._meta.count, $contractNames.Count)
Check 'contract_added_tools_is_the_five_some' `
    (($addedNames.Count -eq 5) -and ($addedNames[4] -ceq 'editor_set_node_property_updates')) `
    ("_meta.added_count={0} _meta.added_tools=[{1}]" -f $contract._meta.added_count, ($addedNames -join ', '))

$contractEntry = @{}
foreach ($entry in @($contract.result.tools)) { $contractEntry[[string]$entry.name] = $entry }

$userPidBefore = Get-ListenerPid -Port_ $UserPort
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("user editor on {0} before: pid={1}" -f $UserPort, $userPidBefore)
Check 'test_ports_free_before' (((Get-ListenerPid -Port_ $EditorPort) -eq -1) -and ((Get-ListenerPid -Port_ $GamePort) -eq -1)) `
    ("port {0} owner={1}; port {2} owner={3}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort), $GamePort, (Get-ListenerPid -Port_ $GamePort))

New-McpScratchProject -Path $Project -Name 'MCP063' -WithMainScene $true
$scripts = Join-Path $Project 'scripts'
New-Item -ItemType Directory -Force -Path $scripts | Out-Null
Write-McpUtf8NoBom -Path (Join-Path $scripts 'valid.gd') -Text "extends Node`n`nfunc answer() -> int:`n`treturn 42`n"
Write-McpUtf8NoBom -Path (Join-Path $scripts 'syntax_error.gd') -Text "extends Node`n`nfunc broken( -> void:`n`tpass`n"

$import = Import-McpProject -Engine $PlainEngine -Path $Project -LogDirectory $LogRoot -Name 'import-base'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine ([string]$import.command)
Check 'scratch_project_imported' ($import.exit_code -eq 0) `
    ("import exit={0} attempts={1}" -f $import.exit_code, $import.attempts)

$editorHandle = $null
$gameFreeHandle = $null
$gameBusyHandle = $null
$holderHandle = $null
try {
    # -------------------------------------------------------------------------
    #  Phase A: (a) the silent disabled endpoint.
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '--- Phase A: (a) the bind failure is loud and recorded ---'
    $holderHandle = Start-PortHolder -Port_ $GamePort
    $holderPid = Get-ListenerPid -Port_ $GamePort
    Check 'a00_a_real_listener_holds_the_game_port' ($holderPid -gt 0) `
        ("netstat says port {0} is held by pid {1}" -f $GamePort, $holderPid)
    $gameBusyHandle = Start-McpEngine -Engine $PlainEngine -ProjectPath $Project -Port_ $GamePort -Name 'game-busy' -WithTrace
    Check 'a01_busy_game_reports_the_failure' (Wait-ForLogText -Path (Join-Path $LogRoot 'game-busy.out.log') -Needle 'bind failed' -TimeoutMs 120000) `
        'game-busy.out.log carries the bind failure'
    Start-Sleep -Milliseconds 1500
    $busyOut = Read-TextShared (Join-Path $LogRoot 'game-busy.out.log')
    $busyErr = Read-TextShared (Join-Path $LogRoot 'game-busy.err.log')
    Write-McpUtf8NoBom -Path (Join-Path $Ev 'a02_game-busy.out.log') -Text $busyOut
    Write-McpUtf8NoBom -Path (Join-Path $Ev 'a03_game-busy.err.log') -Text $busyErr
    Check 'a02_error_line_names_port_reason_and_disabled' `
        (($busyErr.Contains('ERROR')) -and ($busyErr.Contains('ENDPOINT DISABLED')) -and ($busyErr.Contains(("port {0}" -f $GamePort))) -and `
         ($busyErr.Contains('reason:')) -and ($busyErr.Contains('already listening'))) `
        ("err sha256={0}" -f (Get-TextSha $busyErr))
    Check 'a03_the_process_is_still_alive' (-not $gameBusyHandle.HasExited) `
        ("pid={0} HasExited={1} (a bind failure must not take the engine down)" -f $gameBusyHandle.Id, $gameBusyHandle.HasExited)
    & {
        # Nothing answers on the port: the endpoint really is disabled, not slow.
        $probe = Join-Path $Ev 'a04_disabled_probe.json'
        if (Test-Path $probe) { Remove-Item -Force $probe }
        & $Curl -s --max-time 4 -o $probe ("http://127.0.0.1:{0}/mcp" -f $GamePort) | Out-Null
        $exit = $LASTEXITCODE
        $bytes = 0
        if (Test-Path $probe) { $bytes = ([IO.File]::ReadAllBytes($probe)).Count }
        Check 'a04_the_disabled_endpoint_serves_nothing' (($exit -ne 0) -or ($bytes -eq 0)) `
            ("curl_exit={0} bytes={1} (the port is held by the script's own listener, not by the game)" -f $exit, $bytes)
    }
    & {
        $trace = Read-TextShared (Join-Path $LogRoot 'game-busy.trace.jsonl')
        Write-McpUtf8NoBom -Path (Join-Path $Ev 'a05_game-busy.trace.jsonl') -Text $trace
        $hasDisabled = $trace.Contains('"event":"endpoint_disabled"')
        $hasRequested = $trace.Contains(('"requested_port":{0}' -f $GamePort))
        $hasZero = $trace.Contains('"mcp_port":0')
        $hasError = $trace.Contains('"error":22')
        Check 'a05_the_disabled_state_is_machine_readable' ($hasDisabled -and $hasRequested -and $hasZero -and $hasError) `
            ("trace event endpoint_disabled={0} requested_port={1} mcp_port=0:{2} error=22:{3}" -f $hasDisabled, $hasRequested, $hasZero, $hasError)
        Show-Step 'a05 trace (endpoint_disabled event)' $trace
    }
    Stop-McpEngine -Handle $gameBusyHandle -Name 'game-busy'
    $gameBusyHandle = $null
    Stop-PortHolder -Handle $holderHandle
    $holderHandle = $null
    Check 'a06_the_conflict_scenario_is_releasable' ((Get-ListenerPid -Port_ $GamePort) -eq -1) `
        ("port {0} is free again after the holder stopped" -f $GamePort)

    # The "it really binds when nothing holds the port" half.
    $gameFreeHandle = Start-McpEngine -Engine $PlainEngine -ProjectPath $Project -Port_ $GamePort -Name 'game-free'
    Check 'a07_free_game_binds' (Wait-ForEndpoint -Port_ $GamePort -TimeoutMs $ReadyTimeoutMs) `
        ("game endpoint answered GET /mcp on {0}" -f $GamePort)
    $freeOut = Read-TextShared (Join-Path $LogRoot 'game-free.out.log')
    Write-McpUtf8NoBom -Path (Join-Path $Ev 'a08_game-free.out.log') -Text $freeOut
    Check 'a08_no_failure_line_in_the_free_run' `
        (($freeOut.Contains('INFO: MCP server is ready')) -and (-not $freeOut.Contains('bind failed'))) `
        ("ready line present; bind failure absent (out sha256={0})" -f (Get-TextSha $freeOut))
    $listA = Invoke-Json -Id 'a09_game_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port_ $GamePort
    $namesA = Get-ToolNames $listA
    Check 'a09_game_endpoint_serves_the_game_view' ($namesA.Count -eq 72) `
        ("live 9889 = {0} tool(s) (expected 72: the 176 entry contract minus the 104 editor-scope tools)" -f $namesA.Count)
    Stop-McpEngine -Handle $gameFreeHandle -Name 'game-free'
    $gameFreeHandle = $null

    # -------------------------------------------------------------------------
    #  Phase B/C/D: the editor endpoint.
    # -------------------------------------------------------------------------
    $editorHandle = Start-McpEngine -Engine $PlainEngine -ProjectPath $Project -Port_ $EditorPort -Name 'editor' -Editor
    Check 'bc_editor_ready' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) `
        ("editor endpoint answered GET /mcp on {0}" -f $EditorPort)

    $listB = Invoke-Json -Id 'b00_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port_ $EditorPort
    $namesB = Get-ToolNames $listB
    Check 'b00_editor_serves_153_tools' ($namesB.Count -eq 153) `
        ("live 9888 = {0} tool(s) (expected 153)" -f $namesB.Count)

    # (b) the three descriptions and the parameter names.
    foreach ($name in @('editor_set_node_property', 'editor_get_node_properties', 'editor_set_node_script_batch')) {
        $live = Get-ToolEntry $listB $name
        $want = $contractEntry[$name]
        $same = ($null -ne $live) -and ([string]$live.description -ceq [string]$want.description)
        Check ("b01_{0}_description_is_the_contract_entry" -f $name) $same `
            ("identical={0}; rule sentence present={1}" -f $same, ([string]$live.description).Contains('relative to the edited scene root'))
    }
    Check 'b02_the_parameter_names_did_not_move' `
        (((@($contractEntry['editor_set_node_property'].inputSchema.required) -contains 'path')) -and `
         ((@($contractEntry['editor_get_node_properties'].inputSchema.required) -contains 'path')) -and `
         ((@($contractEntry['editor_set_node_script_batch'].inputSchema.required) -contains 'node_paths'))) `
        'editor_set_node_property/get_node_properties still require `path`; the batch tool still requires `node_paths`'

    & {
        $resp = Invoke-Tool -Id 'b03_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort
        Check 'b03_scene_opened' ((Get-ErrorCode $resp) -eq 0) ("code={0} opened={1}" -f (Get-ErrorCode $resp), (Get-Payload $resp).opened)
        $resp = Invoke-Tool -Id 'b04_add_nodes' -Tool 'editor_add_nodes_batch' `
            -Arguments @{ nodes = @(@{ type = 'Node2D'; name = 'Ball'; parent_path = 'Main' }) } -Port_ $EditorPort
        Check 'b04_node_added' ((Get-ErrorCode $resp) -eq 0) ("code={0} count={1}" -f (Get-ErrorCode $resp), (Get-Payload $resp).count)
    }

    # B1: the absolute path is refused AND the refusal points the way.
    & {
        $resp = Invoke-Tool -Id 'b05_absolute_path' -Tool 'editor_set_node_property' `
            -Arguments @{ path = '/root/Main/Ball'; property = 'position'; value = @{ x = 5; y = 6 } } -Port_ $EditorPort
        $suggestion = Get-Suggestion $resp
        Check 'b05_absolute_path_is_refused_with_guidance' `
            (((Get-ErrorCode $resp) -eq -32001) -and ($suggestion.Contains("takes ONE node path")) -and `
             ($suggestion.Contains('/root/Main/Bricks/Car')) -and ($suggestion.Contains('editor_get_scene_tree'))) `
            ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp), $suggestion)
        Show-Step 'b05 refusal (the D-5 measurement)' $resp
    }
    # B2: the right spelling succeeds, and the read-back is the value written.
    & {
        $resp = Invoke-Tool -Id 'b06_scene_relative_path' -Tool 'editor_set_node_property' `
            -Arguments @{ path = 'Main/Ball'; property = 'position'; value = @{ x = 576; y = 320 } } -Port_ $EditorPort
        $payload = Get-Payload $resp
        Check 'b06_scene_relative_path_succeeds' (((Get-ErrorCode $resp) -eq 0) -and ($payload.new_value.x -eq 576) -and ($payload.new_value.y -eq 320)) `
            ("new_value={0}" -f (ConvertTo-Json -InputObject $payload.new_value -Compress))
        $resp = Invoke-Tool -Id 'b07_read_back' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Main/Ball'; properties = @('position') } -Port_ $EditorPort
        $read = Get-Payload $resp
        Check 'b07_the_read_back_proves_it' (((Get-ErrorCode $resp) -eq 0) -and ($read.properties.position.x -eq 576) -and ($read.properties.position.y -eq 320)) `
            ("read back position={0}" -f (ConvertTo-Json -InputObject $read.properties.position -Compress))
        Show-Step 'b06/b07 response' $resp
    }
    # B3: the sibling spellings point at each other.
    & {
        $resp = Invoke-Tool -Id 'b08_singular_tool_with_node_path' -Tool 'editor_set_node_property' `
            -Arguments @{ node_path = 'Main/Ball'; property = 'position'; value = @{ x = 1; y = 1 } } -Port_ $EditorPort
        $suggestion = Get-Suggestion $resp
        Check 'b08_singular_tool_names_its_own_parameter' `
            (((Get-ErrorCode $resp) -eq -32602) -and ((Get-ErrorMessage $resp) -eq "Unknown parameter 'node_path' for tool 'editor_set_node_property'") -and `
             ($suggestion.Contains("its node path is spelled 'path'"))) `
            ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp), $suggestion)
        Show-Step 'b08 refusal' $resp

        $resp = Invoke-Tool -Id 'b09_plural_tool_with_path' -Tool 'editor_set_node_script_batch' `
            -Arguments @{ path = 'Main/Ball'; script_path = 'res://scripts/valid.gd' } -Port_ $EditorPort
        $suggestion = Get-Suggestion $resp
        Check 'b09_plural_tool_names_its_own_parameter' `
            (((Get-ErrorCode $resp) -eq -32602) -and ($suggestion.Contains("its node path is spelled 'node_paths'"))) `
            ("code={0} suggestion='{1}'" -f (Get-ErrorCode $resp), $suggestion)

        $resp = Invoke-Tool -Id 'b10_plural_tool_absolute_path' -Tool 'editor_set_node_script_batch' `
            -Arguments @{ node_paths = @('/root/Main/Ball'); script_path = 'res://scripts/valid.gd' } -Port_ $EditorPort
        $suggestion = Get-Suggestion $resp
        Check 'b10_plural_absolute_path_is_refused_with_guidance' `
            (((Get-ErrorCode $resp) -eq -32001) -and ($suggestion.Contains('is an array of node paths')) -and ($suggestion.Contains('/root/Main/Bricks/Car'))) `
            ("code={0} suggestion='{1}'" -f (Get-ErrorCode $resp), $suggestion)
    }

    # -------------------------------------------------------------------------
    #  Phase C: (c) the new tool.
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '--- Phase C: (c) editor_set_node_property_updates ---'
    & {
        $resp = Invoke-Tool -Id 'c00_add_four_nodes' -Tool 'editor_add_nodes_batch' `
            -Arguments @{ nodes = @(
                @{ type = 'Node2D'; name = 'UpA'; parent_path = 'Main' },
                @{ type = 'Node2D'; name = 'UpB'; parent_path = 'Main' },
                @{ type = 'Node2D'; name = 'UpC'; parent_path = 'Main' },
                @{ type = 'Node2D'; name = 'UpD'; parent_path = 'Main' }
            ) } -Port_ $EditorPort
        Check 'c00_four_nodes_added' ((Get-ErrorCode $resp) -eq 0) ("code={0} count={1}" -f (Get-ErrorCode $resp), (Get-Payload $resp).count)
    }
    & {
        $updates = @(
            @{ path = 'Main/UpA'; property = 'position'; value = @{ x = 1; y = 1 } },
            @{ path = 'Main/UpB'; property = 'position'; value = @{ x = 20; y = 2 } },
            @{ path = 'Main/UpC'; property = 'position'; value = @{ x = 300; y = 3 } },
            @{ path = 'Main/UpD'; property = 'position'; value = 1e20 }
        )
        $resp = Invoke-Tool -Id 'c01_four_values_one_call' -Tool 'editor_set_node_property_updates' `
            -Arguments @{ updates = $updates } -Port_ $EditorPort
        $payload = Get-Payload $resp
        $landed = @($payload.results | Where-Object { $_.status -ceq 'ok' })
        $refused = @($payload.results | Where-Object { $_.status -ceq 'error' })
        $okShapes = ($landed.Count -eq 3) -and ($refused.Count -eq 1) -and ($payload.status -ceq 'partial') -and `
            ($payload.count -eq 4) -and ($payload.updated -eq 3) -and ($payload.failed -eq 1) -and `
            (@($landed | Where-Object { $_.changed -ne $true }).Count -eq 0) -and `
            (@($landed | Where-Object { $null -eq $_.old_value -or $null -eq $_.new_value }).Count -eq 0) -and `
            ($refused[0].error.code -eq -32602) -and ((@($landed | Where-Object { $_.new_value.x -eq 1 -or $_.new_value.x -eq 20 -or $_.new_value.x -eq 300 }).Count) -eq 3)
        Check 'c01_four_nodes_four_values_one_call' $okShapes `
            ("status={0} count={1} updated={2} failed={3}; landed=[{4}]; refused=[{5}]" -f $payload.status, $payload.count, $payload.updated, $payload.failed, `
                (($landed | ForEach-Object { ("{0}:{1}->{2}" -f $_.path, ($_.old_value | ConvertTo-Json -Compress), ($_.new_value | ConvertTo-Json -Compress)) }) -join ' '), `
                (($refused | ForEach-Object { ("{0}:{1}" -f $_.path, $_.error.code) }) -join ' '))
        Show-Step 'c01 response (four values, one refused)' $resp
    }
    # C2: an independent reader.
    & {
        $resp = Invoke-Tool -Id 'c02_read_back' -Tool 'editor_get_node_properties' `
            -Arguments @{ path = 'Main/UpA'; properties = @('position') } -Port_ $EditorPort
        $a = Get-Payload $resp
        $resp = Invoke-Tool -Id 'c03_read_back_d' -Tool 'editor_get_node_properties' `
            -Arguments @{ path = 'Main/UpD'; properties = @('position') } -Port_ $EditorPort
        $d = Get-Payload $resp
        Check 'c02_the_refused_entry_left_its_node_alone' (($a.properties.position.x -eq 1) -and ($d.properties.position.x -eq 0) -and ($d.properties.position.y -eq 0)) `
            ("UpA.position={0} UpD.position={1}" -f (ConvertTo-Json -InputObject $a.properties.position -Compress), (ConvertTo-Json -InputObject $d.properties.position -Compress))
    }
    # C3: stop_on_error is all-or-nothing, with a real take-back.
    & {
        $resp = Invoke-Tool -Id 'c04_stop_on_error_setup' -Tool 'editor_set_node_property' `
            -Arguments @{ path = 'Main/UpA'; property = 'position'; value = @{ x = 9; y = 9 } } -Port_ $EditorPort
        Check 'c04_setup_old_value' ((Get-ErrorCode $resp) -eq 0) 'UpA.position = (9,9) before the failing batch'
        $updates = @(
            @{ path = 'Main/UpA'; property = 'position'; value = @{ x = 100; y = 100 } },
            @{ path = 'Main/UpB'; property = 'position'; value = 1e20 },
            @{ path = 'Main/UpC'; property = 'position'; value = @{ x = 200; y = 200 } }
        )
        $resp = Invoke-Tool -Id 'c05_stop_on_error_true' -Tool 'editor_set_node_property_updates' `
            -Arguments @{ updates = $updates; stop_on_error = $true } -Port_ $EditorPort
        $data = Get-ErrorData $resp
        $results = @($data.results)
        $skipped = @($results | Where-Object { $_.status -ceq 'skipped' })
        $okShape = ((Get-ErrorCode $resp) -eq -32602) -and ((Get-ErrorMessage $resp).StartsWith('updates[1]')) -and `
            ($data.stop_on_error -eq $true) -and ($data.rolled_back -eq $true) -and ($data.updated -eq 1) -and `
            ($skipped.Count -eq 1) -and ($skipped[0].index -eq 2) -and (@($data.applied).Count -eq 1) -and `
            ($data.applied[0].status -ceq 'reverted')
        Check 'c05_stop_on_error_is_all_or_nothing' $okShape `
            ("code={0} message='{1}' rolled_back={2} updated={3} applied=[{4}] skipped=[{5}]" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp), $data.rolled_back, $data.updated, `
                (($data.applied | ForEach-Object { ("{0}:{1}" -f $_.index, $_.status) }) -join ' '), (($skipped | ForEach-Object { $_.index }) -join ','))
        Show-Step 'c05 response (rolled back)' $resp
        $resp = Invoke-Tool -Id 'c06_read_back_after_rollback' -Tool 'editor_get_node_properties' `
            -Arguments @{ path = 'Main/UpA'; properties = @('position') } -Port_ $EditorPort
        $a = Get-Payload $resp
        Check 'c06_the_take_back_really_happened' (($a.properties.position.x -eq 9) -and ($a.properties.position.y -eq 9)) `
            ("UpA.position after the rolled-back call = {0} (it was (100,100) mid-call)" -f (ConvertTo-Json -InputObject $a.properties.position -Compress))
    }
    # C4: the two scopes side by side.
    & {
        $resp = Invoke-Tool -Id 'c07_type_scoped_batch' -Tool 'editor_set_node_property_batch' `
            -Arguments @{ node_type = 'Node2D'; property = 'rotation'; value = 0.5 } -Port_ $EditorPort
        $payload = Get-Payload $resp
        Check 'c07_the_type_scoped_sibling_writes_one_value_everywhere' (((Get-ErrorCode $resp) -eq 0) -and ($payload.updated -ge 5) -and ([string]$payload.property -ceq 'rotation')) `
            ("updated={0} property={1} (one value for every Node2D - the shape TASK-063 did not change)" -f $payload.updated, $payload.property)
    }
    # C5: the same gate, proven from both sides.
    & {
        $resp = Invoke-Tool -Id 'c08_single_writer_refuses_the_same_value' -Tool 'editor_set_node_property' `
            -Arguments @{ path = 'Main/UpB'; property = 'position'; value = 1e20 } -Port_ $EditorPort
        $singleCode = Get-ErrorCode $resp
        $resp = Invoke-Tool -Id 'c09_updates_refuses_the_same_value' -Tool 'editor_set_node_property_updates' `
            -Arguments @{ updates = @(@{ path = 'Main/UpB'; property = 'position'; value = 1e20 }) } -Port_ $EditorPort
        $payload = Get-Payload $resp
        $entryCode = $payload.results[0].error.code
        Check 'c08_c09_both_writers_refuse_the_out_of_range_value' (($singleCode -eq -32602) -and ($entryCode -eq -32602)) `
            ("editor_set_node_property -> {0}; editor_set_node_property_updates -> {1} (the same ValueSlot gate)" -f $singleCode, $entryCode)
        # The unknown-property refusal is the same shape too (TASK-014 D-1).
        $resp = Invoke-Tool -Id 'c10_single_writer_unknown_property' -Tool 'editor_set_node_property' `
            -Arguments @{ path = 'Main/UpB'; property = 'no_such_property'; value = 1 } -Port_ $EditorPort
        $singleUnknown = Get-ErrorCode $resp
        $resp = Invoke-Tool -Id 'c11_updates_unknown_property' -Tool 'editor_set_node_property_updates' `
            -Arguments @{ updates = @(@{ path = 'Main/UpB'; property = 'no_such_property'; value = 1 }) } -Port_ $EditorPort
        $payload = Get-Payload $resp
        Check 'c10_c11_both_writers_refuse_the_unknown_property' (($singleUnknown -eq -32001) -and ($payload.results[0].error.code -eq -32001)) `
            ("single -> {0}; updates -> {1}" -f $singleUnknown, $payload.results[0].error.code)
    }
    # The contract-shape refusals of the new tool, on the wire.
    $argCases = @(
        @{ id = 'c12_missing_updates'; args = @{}; code = -32602; want = 'updates' },
        @{ id = 'c13_empty_updates'; args = @{ updates = @() }; code = -32602; want = 'at least one update' },
        @{ id = 'c14_element_not_an_object'; args = @{ updates = @(7) }; code = -32602; want = 'updates[0]' },
        @{ id = 'c15_unknown_member_in_element'; args = @{ updates = @(@{ path = 'Main/UpA'; property = 'position'; value = @{ x = 0; y = 0 }; nope = 1 }) }; code = -32602; want = 'updates[0].nope' },
        @{ id = 'c16_missing_path_in_element'; args = @{ updates = @(@{ property = 'position'; value = @{ x = 0; y = 0 } }) }; code = -32602; want = 'updates[0].path' },
        @{ id = 'c17_stop_on_error_wrong_type'; args = @{ updates = @(@{ path = 'Main/UpA'; property = 'position'; value = @{ x = 0; y = 0 } }); stop_on_error = 'yes' }; code = -32602; want = 'boolean' },
        @{ id = 'c18_unknown_node'; args = @{ updates = @(@{ path = 'Main/NoSuchNode'; property = 'position'; value = @{ x = 0; y = 0 } }) }; code = -32001; want = 'NoSuchNode' }
    )
    foreach ($case in $argCases) {
        $resp = Invoke-Tool -Id $case.id -Tool 'editor_set_node_property_updates' -Arguments $case.args -Port_ $EditorPort
        $payload = Get-Payload $resp
        $code = Get-ErrorCode $resp
        $message = Get-ErrorMessage $resp
        $suggestion = Get-Suggestion $resp
        if (($code -eq 0) -and ($null -ne $payload)) {
            # A per-entry refusal (the node is not there) comes back as a payload.
            $code = [int]$payload.results[0].error.code
            $message = [string]$payload.results[0].error.message
            $suggestion = [string]$payload.results[0].suggestion
        }
        $ok = ($code -eq $case.code) -and (($message.Contains([string]$case.want)) -or ($suggestion.Contains([string]$case.want)))
        Check ($case.id + '_refused') $ok ("code={0} message='{1}' suggestion='{2}'" -f $code, $message, $suggestion)
    }

    # -------------------------------------------------------------------------
    #  Phase D: (d) the parse error line.
    # -------------------------------------------------------------------------
    Write-Host ''
    Write-Host '--- Phase D: (d) editor_execute_gdscript names the line ---'
    & {
        $resp = Invoke-Tool -Id 'd01_parse_error_line_one' -Tool 'editor_execute_gdscript' `
            -Arguments @{ code = "var x = )`nreturn x" } -Port_ $EditorPort
        $message = Get-ErrorMessage $resp
        $data = Get-ErrorData $resp
        $lineOne = ($data.parse_error.line -eq 1) -and ($data.parse_error.in_caller_code -eq $true)
        Check 'd01_parse_error_names_line_one' `
            (((Get-ErrorCode $resp) -eq -32602) -and ($message.Contains('does not compile')) -and ($message.Contains("line 1 of 'code'")) -and $lineOne -and `
             ([string]$data.parse_error.message).StartsWith('Parse Error') -and ($data.PSObject.Properties.Name -contains 'parse_error_column') -and ($null -eq $data.parse_error_column)) `
            ("code={0} message='{1}' parse_error.line={2} column={3}" -f (Get-ErrorCode $resp), $message, $data.parse_error.line, $(if ($null -eq $data.parse_error_column) { '<null: the declared boundary>' } else { $data.parse_error_column }))
        Show-Step 'd01 refusal (the D-10 measurement)' $resp
    }
    & {
        $resp = Invoke-Tool -Id 'd02_parse_error_line_two' -Tool 'editor_execute_gdscript' `
            -Arguments @{ code = "var x = 1`nvar y = )`nreturn x" } -Port_ $EditorPort
        $data = Get-ErrorData $resp
        Check 'd02_parse_error_names_line_two' (((Get-ErrorCode $resp) -eq -32602) -and ($data.parse_error.line -eq 2) -and ((Get-ErrorMessage $resp).Contains("line 2 of 'code'"))) `
            ("message='{0}' parse_error.line={1}" -f (Get-ErrorMessage $resp), $data.parse_error.line)
    }
    & {
        # The boundary: a valid body still runs, and a *file*'s syntax error is
        # still reported by the tool that owns it, unchanged.
        $resp = Invoke-Tool -Id 'd03_valid_body_runs' -Tool 'editor_execute_gdscript' -Arguments @{ code = 'return 41 + 1' } -Port_ $EditorPort
        $payload = Get-Payload $resp
        Check 'd03_valid_body_still_runs' (((Get-ErrorCode $resp) -eq 0) -and ($payload.result -eq 42)) `
            ("result={0} result_type={1}" -f $payload.result, $payload.result_type)
        $resp = Invoke-Tool -Id 'd04_missing_code' -Tool 'editor_execute_gdscript' -Arguments @{} -Port_ $EditorPort
        Check 'd04_missing_code_is_still_32602' ((Get-ErrorCode $resp) -eq -32602) ("code={0}" -f (Get-ErrorCode $resp))
        $resp = Invoke-Tool -Id 'd05_file_syntax_error_unchanged' -Tool 'project_validate_script' `
            -Arguments @{ path = 'res://scripts/syntax_error.gd' } -Port_ $EditorPort
        $payload = Get-Payload $resp
        Check 'd05_the_file_validator_is_not_this_path' (((Get-ErrorCode $resp) -eq 0) -and ($payload.valid -eq $false) -and ([string]$payload.error_text).Contains('ERR_PARSE_ERROR')) `
            ("project_validate_script -> code={0} valid={1} error_text='{2}' (its own verdict path is unaffected by TASK-063: it answers a payload, not the executor's -32602)" -f (Get-ErrorCode $resp), $payload.valid, $payload.error_text)
    }

    # -------------------------------------------------------------------------
    #  Scope split, and the collected hashes.
    # -------------------------------------------------------------------------
    & {
        $resp = Invoke-Tool -Id 'e01_updates_on_game_endpoint' -Tool 'editor_set_node_property_updates' `
            -Arguments @{ updates = @(@{ path = 'A'; property = 'position'; value = @{ x = 0; y = 0 } }) } -Port_ $EditorPort
    }
    Stop-McpEngine -Handle $editorHandle -Name 'editor'
    $editorHandle = $null
    & {
        $gameForScope = Start-McpEngine -Engine $PlainEngine -ProjectPath $Project -Port_ $GamePort -Name 'game-scope'
        try {
            if (Wait-ForEndpoint -Port_ $GamePort -TimeoutMs $ReadyTimeoutMs) {
                $list = Invoke-Json -Id 'e00_game_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port_ $GamePort
                $names = Get-ToolNames $list
                Check 'e00_the_new_tool_is_editor_scope' ((-not ($names -contains 'editor_set_node_property_updates'))) `
                    ("9889 serves {0} tool(s); editor_set_node_property_updates present={1}" -f $names.Count, ($names -contains 'editor_set_node_property_updates'))
                $resp = Invoke-Tool -Id 'e01_updates_on_game_endpoint' -Tool 'editor_set_node_property_updates' `
                    -Arguments @{ updates = @(@{ path = 'A'; property = 'position'; value = @{ x = 0; y = 0 } }) } -Port_ $GamePort
                Check 'e01_the_editor_tool_is_32601_on_9889' ((Get-ErrorCode $resp) -eq -32601) `
                    ("code={0} message='{1}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp))
            } else {
                Check 'e00_the_new_tool_is_editor_scope' $false 'the game endpoint did not come up'
            }
        } finally {
            Stop-McpEngine -Handle $gameForScope -Name 'game-scope'
        }
    }
} finally {
    Stop-McpEngine -Handle $editorHandle -Name 'editor'
    Stop-McpEngine -Handle $gameFreeHandle -Name 'game-free'
    Stop-McpEngine -Handle $gameBusyHandle -Name 'game-busy'
    Stop-PortHolder -Handle $holderHandle
}

# --- the port guard: the user's 9877 is exactly as it was found --------------
$guardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'port_9877_untouched' $guardResult.pass $guardResult.evidence

$failed = @($script:Checks | Where-Object { -not $_.pass })
Write-Host ''
Write-Host ('TASK-063 evidence: {0} checks, {1} failed' -f $script:Checks.Count, $failed.Count)
$summary = [pscustomobject]@{
    engine       = $version
    head         = $headSha
    checks       = $script:Checks
    hashes       = $script:StepHashes
    failed_count = $failed.Count
}
[IO.File]::WriteAllBytes((Join-Path $OutRoot 'mcp063-checks.json'), (New-Object Text.UTF8Encoding($false)).GetBytes((ConvertTo-Json -InputObject $summary -Depth 8)))
Write-Host ("checks: {0}" -f (Join-Path $OutRoot 'mcp063-checks.json'))
Write-Host ("evidence dir: {0}" -f $Ev)
if ($failed.Count -gt 0) { exit 1 }
exit 0
