# =============================================================================
#  mcp066b_env.ps1 -- TASK-066 role B shared harness (pure ASCII).
#
#  Dot-source this file. It provides the paths of the role-B run, one MCP
#  tools/call wrapper whose request and response bytes go through
#  mcp_evidence_guard.ps1 (unique names <leaf>__<seq>__<sha8>.{request,response}.json,
#  hard refusal to overwrite evidence), the trace readers used to correlate a
#  tools/call with its own capture line, and process/port helpers that only ever
#  touch PIDs this harness started.
#
#  DISCIPLINE (TASK-066 role B): port 9877 is never occupied, killed or
#  restarted; the only ports used are 9888 (editor) and 9889 (game); nothing
#  under modules/mcp_server/tools|tests or the contract is ever written.
# =============================================================================

$ErrorActionPreference = 'Stop'
$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

$RepoRoot = 'F:\RustProjects\godot-mcp-pro\code\godot'
$McpRoot = Join-Path $RepoRoot 'modules\mcp_server'
$ScriptRoot = Join-Path $McpRoot 'scripts'
$EvidenceRoot = Join-Path $McpRoot 'docs\reports\evidence\task066b'
$ScratchRoot = Join-Path $env:TEMP 'mcp066b'
$IoRoot = Join-Path $ScratchRoot 'io'
$ProjSrc = Join-Path $env:TEMP 'mcp-breakout-cs\proj'
$Proj = Join-Path $ScratchRoot 'proj-cs'
$EditorPort = 9888
$GamePort = 9889
$EditorTrace = Join-Path $ScratchRoot 'trace-editor.jsonl'
$GameTrace = Join-Path $ScratchRoot 'trace-game.jsonl'
$TraceGlob = Join-Path $ScratchRoot 'trace-*.jsonl'
$ProgressFile = Join-Path $ScratchRoot 'PROGRESS.md'
$MarkerFile = Join-Path $ScratchRoot 'B066-DONE.marker'
$WatchOutDir = Join-Path $ScratchRoot 'watch'
$MonoExe = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe'
$WatcherPath = Join-Path $ScriptRoot 'mcp_watch_run.ps1'
$ProgressTrace = $ProgressFile

. (Join-Path $ScriptRoot 'mcp_evidence_guard.ps1')
. (Join-Path $ScriptRoot 'mcp_import_guard.ps1')

$script:McpCallSeq = 0
$script:McpCallId = 0
$script:ToolOrdinals = @{}
$script:Checks = New-Object System.Collections.ArrayList

# First eight hex digits, or a readable marker when the string is not a digest
# (a missing capture line must not turn a detail string into an exception).
function Sha8([string]$Digest) {
    if ($null -ne $Digest -and $Digest.Length -ge 8) { return $Digest.Substring(0, 8) }
    return '<none>'
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
    return $Path
}

function To-Fwd([string]$Path) {
    return ($Path -replace '\\', '/')
}

function Add-Heartbeat([string]$Text) {
    $parent = Split-Path -Parent $ProgressFile
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $InvariantCulture)
    [System.IO.File]::AppendAllText($ProgressFile, ('[' + $stamp + '] ' + $Text + "`n"), (New-Object Text.UTF8Encoding($false)))
}

function Add-Check([string]$Id, [bool]$Pass, [string]$Detail) {
    [void]$script:Checks.Add([pscustomobject]@{ id = $Id; pass = [bool]$Pass; detail = [string]$Detail })
    $tag = 'FAIL'
    if ($Pass) { $tag = 'PASS' }
    Write-Host ('[{0}] {1} :: {2}' -f $tag, $Id, $Detail)
}

function Reset-McpCallSeq {
    $script:McpCallSeq = 0
    $script:McpCallId = 0
    $script:ToolOrdinals = @{}
}

# ---------------------------------------------------------------------------
#  One MCP tools/call.
# ---------------------------------------------------------------------------
function Invoke-Tool {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Tool,
        [Parameter(Mandatory = $true)]$Arguments,
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Leaf,
        [string]$Id = ''
    )
    $script:McpCallSeq++
    $script:McpCallId++
    $seq = [int]$script:McpCallSeq
    $callId = [int]$script:McpCallId
    # Ordinal of this tool within the current process: the trace is the only
    # place the server's own `seq` is visible, and pairing "my k-th call of tool
    # T" with "the k-th trace request of tool T" is what lets a capture line be
    # found without ever matching on text.
    if (-not $script:ToolOrdinals.ContainsKey($Tool)) { $script:ToolOrdinals[$Tool] = 0 }
    $script:ToolOrdinals[$Tool] = [int]$script:ToolOrdinals[$Tool] + 1
    $toolOrdinal = [int]$script:ToolOrdinals[$Tool]

    $envelope = [ordered]@{
        jsonrpc = '2.0'
        id      = $callId
        method  = 'tools/call'
        params  = [ordered]@{ name = $Tool; arguments = $Arguments }
    }
    $body = ($envelope | ConvertTo-Json -Depth 40 -Compress)
    $bodyBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($body)
    # The sha of the ARGUMENTS alone: the request envelope also carries the
    # JSON-RPC id, which changes on every call, so comparing whole request bodies
    # would call two byte-identical argument objects different (the same mistake
    # BREAKOUT-FINDINGS-R3 O-1 records for whole HTTP responses).
    $argumentsJson = ($Arguments | ConvertTo-Json -Depth 40 -Compress)
    $argumentsSha = Get-McpEvidenceContentSha256 -Text $argumentsJson

    Ensure-Dir $Directory | Out-Null
    $req = Write-McpEvidenceBytes -Directory $Directory -Leaf $Leaf -Bytes $bodyBytes -Extension '.request.json' -Seq $seq -Id $Id

    $tmpResp = Join-Path $IoRoot ('resp-' + $seq + '.json')
    $reqFile = $req.Path
    $null = & curl.exe -s -o $tmpResp --data-binary "@$reqFile" -H 'Content-Type: application/json' ("http://127.0.0.1:{0}/mcp" -f $Port)
    $curlExit = $LASTEXITCODE
    $respBytes = @()
    if (Test-Path -LiteralPath $tmpResp) { $respBytes = [IO.File]::ReadAllBytes($tmpResp) }
    if ($respBytes.Length -eq 0) { $respBytes = (New-Object Text.UTF8Encoding($false)).GetBytes('') }
    $resp = Write-McpEvidenceBytes -Directory $Directory -Leaf $Leaf -Bytes $respBytes -Extension '.response.json' -Seq $seq -Id $Id

    $text = [Text.Encoding]::UTF8.GetString($respBytes)
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json } catch { $parsed = $null }

    return [pscustomobject]@{
        Seq            = $seq
        CallId         = $callId
        ToolOrdinal    = $toolOrdinal
        Tool           = $Tool
        Port           = $Port
        RequestPath    = $req.Path
        RequestSha256  = $req.Sha256
        ArgumentsSha256 = $argumentsSha
        ArgumentsJson  = $argumentsJson
        ResponsePath   = $resp.Path
        ResponseSha256 = $resp.Sha256
        ResponseBytes  = $respBytes.Length
        CurlExit       = $curlExit
        Raw            = $text
        Json           = $parsed
    }
}

function Invoke-Raw {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Leaf
    )
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = 1; method = $Method }
    $body = ($envelope | ConvertTo-Json -Depth 10 -Compress)
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($body)
    Ensure-Dir $Directory | Out-Null
    $req = Write-McpEvidenceBytes -Directory $Directory -Leaf $Leaf -Bytes $bytes -Extension '.request.json'
    $tmpResp = Join-Path $IoRoot ('raw-' + [Guid]::NewGuid().ToString('N') + '.json')
    $reqFile = $req.Path
    $null = & curl.exe -s -o $tmpResp --data-binary "@$reqFile" -H 'Content-Type: application/json' ("http://127.0.0.1:{0}/mcp" -f $Port)
    $respBytes = @()
    if (Test-Path -LiteralPath $tmpResp) { $respBytes = [IO.File]::ReadAllBytes($tmpResp) }
    $resp = Write-McpEvidenceBytes -Directory $Directory -Leaf $Leaf -Bytes $respBytes -Extension '.response.json'
    $parsed = $null
    try { $parsed = ([Text.Encoding]::UTF8.GetString($respBytes)) | ConvertFrom-Json } catch { $parsed = $null }
    return [pscustomobject]@{ RequestPath = $req.Path; ResponsePath = $resp.Path; ResponseSha256 = $resp.Sha256; ResponseBytes = $respBytes.Length; Json = $parsed }
}

function Get-ToolBody($Call) {
    if ($null -eq $Call.Json) { return $null }
    if ($null -eq $Call.Json.result) { return $null }
    if ($null -eq $Call.Json.result.content) { return $null }
    $text = [string]$Call.Json.result.content[0].text
    if ([string]::IsNullOrEmpty($text)) { return $null }
    try { return ($text | ConvertFrom-Json) } catch { return $null }
}

function Get-ErrorCode($Call) {
    if ($null -eq $Call.Json) { return 'no_json' }
    if ($null -ne $Call.Json.error) { return [int]$Call.Json.error.code }
    return 0
}

function Get-ErrorMessage($Call) {
    if ($null -eq $Call.Json) { return 'no_json' }
    if ($null -ne $Call.Json.error) { return [string]$Call.Json.error.message }
    return ''
}

# ---------------------------------------------------------------------------
#  Trace readers. The trace request line carries its own `seq`; the capture line
#  repeats it, so a call is matched to its capture by seq, never by text.
# ---------------------------------------------------------------------------
function Get-TraceObjects([string]$Path) {
    $out = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    # The engine keeps the trace file open while it runs, so it must be opened
    # with FileShare.ReadWrite (the same reason mcp_watch_run.ps1 does it): plain
    # [IO.File]::ReadAllLines fails with "being used by another process".
    $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        try {
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $obj = $null
                try { $obj = $line | ConvertFrom-Json } catch { $obj = $null }
                if ($null -ne $obj) { [void]$out.Add($obj) }
            }
        } finally { $reader.Close() }
    } finally { $stream.Close(); $stream.Dispose() }
    return @($out)
}

function Get-ToolRequests($Lines) {
    return @($Lines | Where-Object { $_.method -eq 'tools/call' })
}

function Get-RequestOfTool($Lines, [string]$Tool, [int]$Ordinal = 1) {
    $reqs = @(Get-ToolRequests $Lines | Where-Object { $_.tool -eq $Tool })
    if ($reqs.Count -lt $Ordinal) { return $null }
    return $reqs[$Ordinal - 1]
}

function Get-CaptureBySeq($Lines, [int]$Seq) {
    foreach ($line in $Lines) {
        if ($line.event -eq 'capture' -and [int]$line.seq -eq $Seq) { return $line }
    }
    return $null
}

function Get-CapturesOfTool($Lines, [string]$Tool) {
    return @($Lines | Where-Object { $_.event -eq 'capture' -and $_.tool -eq $Tool })
}

# ---------------------------------------------------------------------------
#  Ports and processes. Nothing here kills a process it did not start.
# ---------------------------------------------------------------------------
function Get-ListeningPorts {
    $rows = @(netstat -ano | Select-String -Pattern 'LISTENING')
    $ports = @()
    foreach ($row in $rows) {
        $line = [string]$row.Line
        if ($line -match ':(\d+)\s') { $ports += [int]$Matches[1] }
    }
    return @($ports | Sort-Object -Unique)
}

function Wait-Port {
    param([int]$Port, [int]$TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ((Get-ListeningPorts) -contains $Port) { return $true }
        Start-Sleep -Milliseconds 750
    }
    return $false
}

function Start-OwnProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$EngineArgs,
        [Parameter(Mandatory = $true)][string]$OutLog,
        [Parameter(Mandatory = $true)][string]$ErrLog
    )
    Ensure-Dir (Split-Path -Parent $OutLog) | Out-Null
    $p = Start-Process -FilePath $Exe -ArgumentList $EngineArgs -PassThru -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog
    return $p
}

function Stop-OwnProcess {
    param($Process, [string]$LogPath)
    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            if ($LogPath) { Add-Heartbeat ('stopped own pid=' + $Process.Id + ' log=' + $LogPath) }
        }
    } catch {
        if ($LogPath) { Add-Heartbeat ('stop failed pid=' + $Process.Id + ' : ' + $_.Exception.Message) }
    }
}

function Wait-LogLine {
    param([string]$Path, [string]$Pattern, [int]$TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $text = Read-TextShared -Path $Path
        if (-not [string]::IsNullOrEmpty($text) -and ($text -match $Pattern)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

# A redirected stdout/stderr file and an open trace are BOTH held by a running
# engine, so every read of a live process file goes through one shared reader.
# `[IO.File]::ReadAllText` was measured to fail with "being used by another
# process" on a game process' redirected stdout while Get-Content succeeded on an
# editor one, so the retry is part of the helper, not of the call sites.
function Read-TextShared {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                try { return $reader.ReadToEnd() } finally { $reader.Close() }
            } finally { $stream.Close(); $stream.Dispose() }
        } catch {
            Start-Sleep -Milliseconds 400
        }
    }
    return ''
}

function First-LineMatching {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Pattern)
    $text = Read-TextShared -Path $Path
    foreach ($line in ($text -split "`n")) {
        if ($line -match $Pattern) { return $line.TrimEnd("`r") }
    }
    return ''
}

function Wait-FileExists {
    param([string]$Path, [int]$TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

# res:// or user:// -> an absolute OS path this harness can copy/snapshot.
function Globalize-ResPath([string]$ResPath) {
    if ($ResPath -like 'res://*') {
        return (Join-Path $Proj ($ResPath.Substring(6) -replace '/', '\'))
    }
    return $ResPath
}

function Get-Sha256OfFile([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}
