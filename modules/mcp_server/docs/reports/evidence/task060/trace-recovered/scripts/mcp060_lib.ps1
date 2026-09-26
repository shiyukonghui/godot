# =============================================================================
#  mcp060_lib.ps1 -- TASK-060 section B helper library (pure ASCII)
#
#  Shared by mcp060_bootstrap.ps1 / mcp060_scene.ps1 / mcp060_csharp.ps1, so the
#  request/response plumbing (curl --data-binary, byte-exact response files,
#  sha256, trace indexing) exists once.
#
#  Discipline honoured here:
#    * responses land on disk with `curl.exe -s -o <file>` and are hashed --
#      never piped through Out-File (that corrupted an evidence file once);
#    * project text files are written without a BOM;
#    * JSON that is a request body never travels as a command-line argument.
# =============================================================================

$ErrorActionPreference = 'Stop'

$script:RepoRoot = 'F:\RustProjects\godot-mcp-pro\code\godot'
$script:TmpRoot  = Join-Path $env:TEMP 'mcp-breakout'
# A caller that dot-sources this library may have already chosen the project to
# operate on (mcp060_start_editor.ps1 takes -ProjectPath); the library must not
# stomp on that choice.
if ([string]::IsNullOrWhiteSpace($script:Proj) -or -not (Test-Path $script:Proj)) {
    $script:Proj = Join-Path $script:TmpRoot 'proj'
}
$script:EvRoot   = Join-Path $script:RepoRoot 'docs\reports\evidence\task060'
$script:Curl     = Join-Path $env:SystemRoot 'System32\curl.exe'
$script:Engine   = Join-Path $script:RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe'
$script:EditorPort = 9888
$script:GamePort   = 9889

New-Item -ItemType Directory -Force -Path $script:TmpRoot, $script:EvRoot | Out-Null

function Write-Ascii {
    param([Parameter(Mandatory = $true)][string]$Path, [AllowEmptyString()][string]$Text = '')
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { return '<missing>' }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}

# A numbered step in the dev log. `$Note` is appended to the run log; the rich
# per-step record lives in the JSONL decision log.
function Log-Step {
    param([string]$Tag, [string]$Detail)
    $line = ('{0} | {1} | {2}' -f (Get-Date -Format 'HH:mm:ss.fff'), $Tag, $Detail)
    Write-Host $line
    Add-Content -Path (Join-Path $script:TmpRoot 'run.log') -Value $line -Encoding ASCII
    $global:Mcp060CallCount = $global:Mcp060CallCount + 1
}

# A tool call whose request and response are both written to disk byte for byte
# under <EvidenceDir>\<Id>.request.json / .response.json, plus a sha256 file.
# Serialising a request body is the one place this library has bitten me twice:
#   1. the request body is a JavaScriptEncoder-shaped envelope with a nested
#      dictionary, and ConvertTo-Json annotates a dictionary instance the first
#      time it sees it (`Count`), so the SAME instance must never be serialised
#      twice;
#   2. nesting an OrderedDictionary inside an OrderedDictionary inside an ARRAY
#      inside an OrderedDictionary made ConvertTo-Json -Depth 40 never return on
#      PowerShell 5.1 (measured: the script hung with no request file written).
# `New-JsonArgs` therefore builds the envelope from plain hashtables, one fresh
# instance per call, and Invoke-McpTool writes the body out before touching the
# network so a later hang is always attributable.
function New-JsonArgs {
    param([Parameter(Mandatory = $true)][string]$Tool, [Parameter(Mandatory = $true)]$Arguments)
    $t = [string]$Tool
    $a = $Arguments
    return @{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = @{ name = $t; arguments = $a } }
}

function Invoke-McpTool {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Tool,
        [Parameter(Mandatory = $true)]$Arguments,
        [int]$Port = 9888,
        [string]$EvidenceDir = '',
        [int]$MaxTimeSec = 60,
        [switch]$NoLog
    )
    if ([string]::IsNullOrEmpty($EvidenceDir)) { $EvidenceDir = Join-Path $script:TmpRoot 'raw' }
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
    $reqFile = Join-Path $EvidenceDir ($Id + '.request.json')
    $respFile = Join-Path $EvidenceDir ($Id + '.response.json')
    $envelope = New-JsonArgs -Tool $Tool -Arguments $Arguments
    $body = ConvertTo-Json -InputObject $envelope -Depth 40 -Compress
    Write-Ascii -Path $reqFile -Text $body
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $script:Curl -s --max-time $MaxTimeSec -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $reqFile) ('http://127.0.0.1:{0}/mcp' -f $Port) | Out-Null
    $curlExit = $LASTEXITCODE
    $sw.Stop()
    # A transport failure must never be readable as an answer with error_code 0:
    # curl exit 7 means the endpoint was not there, and an empty body is not an
    # OK verdict. Measured once (editor had died): two calls "succeeded" with
    # bytes=0 / err=0 before the mistake was noticed.
    if ($curlExit -ne 0 -or -not (Test-Path $respFile) -or ([IO.File]::ReadAllBytes($respFile)).Length -eq 0) {
        throw ('transport failure for tool "{0}" (id {1}): curl exit {2}, response bytes {3} - the endpoint on port {4} is not answering' -f `
            $Tool, $Id, $curlExit, $(if (Test-Path $respFile) { ([IO.File]::ReadAllBytes($respFile)).Length } else { '<no file>' }), $Port)
    }
    $bytes = 0; $text = ''; $sha = '<empty>'
    if (Test-Path $respFile) {
        $bytes = ([IO.File]::ReadAllBytes($respFile)).Length
        $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($respFile))
        $sha = Get-Sha256 $respFile
    }
    Write-Ascii -Path ($respFile + '.sha256') -Text ("{0}  {1}`n" -f $sha, (Split-Path -Leaf $respFile))
    if (-not $NoLog) {
        $code = Get-McpErrorCode $text
        Log-Step $Tool ("port=$Port id=$Id bytes=$bytes sha256=$sha curl_exit=$curlExit ms=$($sw.ElapsedMilliseconds) err=$code")
    }
    return [pscustomobject]@{
        Id = $Id; Tool = $Tool; Port = $Port; Text = $text; Bytes = $bytes
        Sha256 = $sha; CurlExit = $curlExit; ElapsedMs = $sw.ElapsedMilliseconds
        EvidencePath = $respFile
        ErrorCode = (Get-McpErrorCode $text)
        ErrorMessage = (Get-McpErrorMessage $text)
        Payload = (Get-McpPayload $text)
    }
}

function Get-McpPayload {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        $env = ConvertFrom-Json $Text
        if ($null -eq $env.result) { return $null }
        $t = [string]$env.result.content[0].text
        if ([string]::IsNullOrWhiteSpace($t)) { return $null }
        return ConvertFrom-Json $t
    } catch { return $null }
}

function Get-McpErrorCode {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    try { $env = ConvertFrom-Json $Text; if ($null -eq $env.error) { return 0 }; return [int]$env.error.code } catch { return 0 }
}

function Get-McpErrorMessage {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    try { $env = ConvertFrom-Json $Text; if ($null -eq $env.error) { return '' }; return [string]$env.error.message } catch { return '' }
}

function Invoke-McpJson {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        $Params,
        [int]$Port = 9888,
        [string]$EvidenceDir = ''
    )
    if ([string]::IsNullOrEmpty($EvidenceDir)) { $EvidenceDir = Join-Path $script:TmpRoot 'raw' }
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params }
    $body = ConvertTo-Json -InputObject $envelope -Depth 40 -Compress
    $reqFile = Join-Path $EvidenceDir (($Method -replace '[^A-Za-z0-9]', '_') + '.request.json')
    $respFile = Join-Path $EvidenceDir (($Method -replace '[^A-Za-z0-9]', '_') + '.response.json')
    Write-Ascii -Path $reqFile -Text $body
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $script:Curl -s --max-time 120 -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $reqFile) ('http://127.0.0.1:{0}/mcp' -f $Port) | Out-Null
    $text = ''
    if (Test-Path $respFile) { $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($respFile)) }
    return [pscustomobject]@{ Text = $text; Sha256 = (Get-Sha256 $respFile); EvidencePath = $respFile }
}

function Wait-McpEndpoint {
    param([int]$Port, [int]$TimeoutMs = 240000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $probe = Join-Path $script:TmpRoot ('probe-{0}.json' -f $Port)
    while ([DateTime]::UtcNow -lt $deadline) {