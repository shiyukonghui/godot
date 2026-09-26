# =============================================================================
#  mcp065b_env.ps1 -- TASK-065 section B shared harness (pure ASCII).
#
#  Dot-source this file. It provides:
#    * the absolute paths of the scratch root, the evidence root and the IO area;
#    * Invoke-Tool: one MCP tools/call over curl.exe, with the request and the
#      response bytes stored through mcp_evidence_guard.ps1 (unique name ->
#      <leaf>__<seq>__<sha8>.request.json / .response.json, and a hard refusal
#      to overwrite evidence that already holds different bytes);
#    * heartbeat / progress lines for scripts/mcp_watch_run.ps1;
#    * process start/stop helpers that only ever touch PIDs this harness
#      started, plus a port-free check that never kills anything.
#
#  DISCIPLINE (TASK-065 section B): port 9877 is never occupied, killed or
#  restarted; the only ports used are 9888 (editor) and 9889 (game).
# =============================================================================

$ErrorActionPreference = 'Stop'
$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

$RepoRoot = 'F:\RustProjects\godot-mcp-pro\code\godot'
$McpRoot = Join-Path $RepoRoot 'modules\mcp_server'
$ScriptRoot = Join-Path $McpRoot 'scripts'
$EvidenceRoot = Join-Path $McpRoot 'docs\reports\evidence\task065b'
$ScratchRoot = Join-Path $env:TEMP 'mcp065b'
$IoRoot = Join-Path $ScratchRoot 'io'
$EditorProject = Join-Path $ScratchRoot 'proj-editor'
$GameProject = Join-Path $ScratchRoot 'proj-game'
$EditorPort = 9888
$GamePort = 9889
$EditorTrace = Join-Path $ScratchRoot 'trace-editor.jsonl'
$GameTrace = Join-Path $ScratchRoot 'trace-game.jsonl'
$ProgressFile = Join-Path $ScratchRoot 'PROGRESS.md'
$MarkerFile = Join-Path $ScratchRoot 'DONE.marker'
$WatchOutDir = Join-Path $ScratchRoot 'watch'
$ConsoleExe = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'

. (Join-Path $ScriptRoot 'mcp_evidence_guard.ps1')

$script:McpCallSeq = 0
$script:McpCallId = 0

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
    return $Path
}

function Add-Heartbeat([string]$Text) {
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $InvariantCulture)
    [System.IO.File]::AppendAllText($ProgressFile, ('[' + $stamp + '] ' + $Text + "`n"), (New-Object Text.UTF8Encoding($false)))
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
    # NOT `$id`: `$Id` is the (string-typed) parameter below, and PowerShell
    # variable names are case insensitive, so assigning to `$id` would coerce the
    # JSON-RPC id to a string and the request would carry "5" instead of 5.
    $callId = [int]$script:McpCallId

    $envelope = [ordered]@{
        jsonrpc = '2.0'
        id      = $callId
        method  = 'tools/call'
        params  = [ordered]@{ name = $Tool; arguments = $Arguments }
    }
    $body = ($envelope | ConvertTo-Json -Depth 40 -Compress)
    $bodyBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($body)

    Ensure-Dir $Directory | Out-Null
    $req = Write-McpEvidenceBytes -Directory $Directory -Leaf $Leaf -Bytes $bodyBytes -Extension '.request.json' -Seq $seq -Id $Id

    $tmpResp = Join-Path $IoRoot ('resp-' + $seq + '.json')
    $reqFile = $req.Path
    $curlOut = & curl.exe -s -o $tmpResp --data-binary "@$reqFile" -H 'Content-Type: application/json' ("http://127.0.0.1:{0}/mcp" -f $Port)
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
        Id             = $callId
        Tool           = $Tool
        Port           = $Port
        RequestPath    = $req.Path
        RequestSha256  = $req.Sha256
        ResponsePath   = $resp.Path
        ResponseSha256 = $resp.Sha256
        ResponseBytes  = $respBytes.Length
        CurlExit       = $curlExit
        Raw            = $text
        Json           = $parsed
    }
}

# The tool result body of a successful content_result: result.content[0].text
# parsed as JSON. Returns $null when the envelope is an error or has no text.
function Get-ToolBody($Call) {
    if ($null -eq $Call.Json) { return $null }
    if ($null -eq $Call.Json.result) { return $null }
    if ($null -eq $Call.Json.result.content) { return $null }
    $text = [string]$Call.Json.result.content[0].text
    if ([string]::IsNullOrEmpty($text)) { return $null }
    try { return ($text | ConvertFrom-Json) } catch { return $null }
}

function Get-ToolError($Call) {
    if ($null -eq $Call.Json) { return 'no_json' }
    if ($null -ne $Call.Json.error) { return ('rpc_error ' + $Call.Json.error.code + ' ' + $Call.Json.error.message) }
    if ($null -ne $Call.Json.result -and $null -ne $Call.Json.result.isError -and $Call.Json.result.isError) {
        return ('tool_error ' + $Call.Raw)
    }
    return ''
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
            if ($LogPath) {
                Add-Heartbeat ('stopped own pid=' + $Process.Id + ' log=' + $LogPath)
            }
        }
    } catch {
        if ($LogPath) { Add-Heartbeat ('stop failed pid=' + $Process.Id + ' : ' + $_.Exception.Message) }
    }
}

function Wait-LogLine {
    param([string]$Path, [string]$Pattern, [int]$TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $Path) {
            $hit = Select-String -LiteralPath $Path -Pattern $Pattern -Quiet -ErrorAction SilentlyContinue
            if ($hit) { return $true }
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}