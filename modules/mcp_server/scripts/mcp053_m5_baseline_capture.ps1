# =============================================================================
#  mcp053_m5_baseline_capture.ps1 -- TASK-053 section 2.3 (M-5), the *pre-change*
#  half of the "the default response is byte-identical" proof.
#
#  It must run against the engine binary of the revision **before** the M-5
#  change (the tree at the TASK-053 starting commit), because what it captures is
#  the response of `running_game_get_node_property_samples` with no explicit
#  stride argument - the bytes the new `sample_stride` parameter must leave
#  untouched when it is omitted.
#
#  The call is deliberately deterministic: one static property (`name`) of the
#  main scene's root node, sampled five times one frame apart. Every value of the
#  answer is a constant of the scene, so two runs of the same call on the same
#  engine produce the same bytes, and the captured sha256 is a meaningful fixed
#  point for the post-change comparison.
#
#  It writes, under docs/reports/evidence/task053/m5-baseline/:
#    * default.response.json  the raw response of run 1 (--data-binary + curl -o);
#    * default.request.json   the exact request body;
#    * default.run2/run3.response.json  the repeat runs (byte-identity proof);
#    * baseline.json          the engine version/sha256, the request, the byte
#                             count and the sha256 of the captured response.
#
#  Port discipline: the user's editor on 9877 is only *observed*; only 9888/9889
#  are used, and 9889 is the port this script owns and releases.
#
#  Usage (ASCII only, like every .ps1 of this module):
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp053_m5_baseline_capture.ps1
# =============================================================================

param(
    [string]$Engine = '',
    [int]$GamePort = 9889,
    [int]$EditorPort = 9888,
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($Engine)) { $Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe' }
$Engine = (Resolve-Path $Engine).Path
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$UserPort = 9877

$OutDir = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task053\m5-baseline'
$Root = Join-Path $env:TEMP 'mcp053-m5-baseline'
$LogRoot = Join-Path $Root 'logs'
$Project = Join-Path $Root 'proj'

. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

function Get-ListenerPid {
    param([int]$Port_)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port_ + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

function Get-DiskSha {
    param([string]$Path)
    if (Test-Path $Path) { return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower() }
    return '<missing>'
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

function Wait-ForEndpoint {
    param([int]$Port_, [int]$TimeoutMs)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Join-Path $OutDir 'status-probe.json'
        & $Curl -s --max-time 5 -o $probe ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (Test-Path $probe) {
            try {
                $parsed = ConvertFrom-Json (Read-TextShared $probe)
                if ($null -ne $parsed.frame_count) { return $true }
            } catch { }
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

function Invoke-Raw {
    param([string]$Id, [string]$Json, [int]$Port_)
    $bodyFile = Join-Path $OutDir ("{0}.request.json" -f $Id)
    $respFile = Join-Path $OutDir ("{0}.response.json" -f $Id)
    Write-McpUtf8NoBom -Path $bodyFile -Text $Json
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time 120 -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $curlExit = $LASTEXITCODE
    $bytes = 0
    if (Test-Path $respFile) { $bytes = ([IO.File]::ReadAllBytes($respFile)).Count }
    Write-Host ("[{0}] port={1} curl_exit={2} bytes={3} sha256={4}" -f $Id, $Port_, $curlExit, $bytes, (Get-DiskSha $respFile))
    return $respFile
}

Write-Host '============================================================='
Write-Host ' TASK-053 M-5: capture the pre-change default sample response'
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host ('FATAL: engine not found: {0}' -f $Engine); exit 2 }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
if (-not (Test-Path $LogRoot)) { New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null }

$headSha = ((& git -C $RepoRoot rev-parse --short=9 HEAD) -join '').Trim()
$version = ((& $Engine --version 2>$null) -join ' ').Trim()
Write-Host ("engine --version = '{0}'  git HEAD = {1}  engine sha256 = {2}" -f $version, $headSha, (Get-DiskSha $Engine))

$userPidBefore = Get-ListenerPid -Port_ $UserPort
$guard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("user editor on {0} before: pid={1}" -f $UserPort, $userPidBefore)

if ((Get-ListenerPid -Port_ $GamePort) -ne -1) {
    Write-Host ("FATAL: port {0} is already in use (owner {1}); this script owns it" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))
    exit 2
}

Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-McpScratchProject -Path $Project -Name 'MCP053 M5 baseline' -WithMainScene $true
$import = Import-McpProject -Engine $Engine -Path $Project -LogDirectory $LogRoot -Name 'import-m5-baseline'
Register-McpPortGuardCommandLine -Guard $guard -CommandLine ([string]$import.command)
Write-Host ("import exit={0} attempts={1}" -f $import.exit_code, $import.attempts)

$handle = $null
try {
    $arguments = @('--headless', '--path', $Project, ("--mcp-port={0}" -f $GamePort))
    $handle = Start-Process -FilePath $Engine -ArgumentList $arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot 'game.out.log') `
        -RedirectStandardError (Join-Path $LogRoot 'game.err.log') -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $guard -EnginePid $handle.Id -Arguments $arguments
    Write-Host ("started game pid={0} :: {1}" -f $handle.Id, ($arguments -join ' '))

    $ready = Wait-ForEndpoint -Port_ $GamePort -TimeoutMs $ReadyTimeoutMs
    Write-Host ("game endpoint ready = {0}" -f $ready)
    if (-not $ready) { exit 3 }

    # The one deterministic call. No `sample_stride` member: this is the default
    # path whose bytes the new parameter must not move.
    $args = [ordered]@{ node_path = '/root/Main'; properties = @('name'); frame_count = 5; frame_interval = 1 }
    $body = ConvertTo-Json -InputObject ([ordered]@{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = [ordered]@{ name = 'running_game_get_node_property_samples'; arguments = $args } }) -Depth 20 -Compress
    Write-Host ("request = {0}" -f $body)

    $run1 = Invoke-Raw -Id 'default' -Json $body -Port_ $GamePort
    $run2 = Invoke-Raw -Id 'default.run2' -Json $body -Port_ $GamePort
    $run3 = Invoke-Raw -Id 'default.run3' -Json $body -Port_ $GamePort

    $sha1 = Get-DiskSha $run1
    $sha2 = Get-DiskSha $run2
    $sha3 = Get-DiskSha $run3
    $bytes = ([IO.File]::ReadAllBytes($run1)).Count
    $same = ($sha1 -ceq $sha2) -and ($sha1 -ceq $sha3)
    Write-Host ("three runs identical = {0} (sha256 {1})" -f $same, $sha1)
    Write-Host ("captured response: {0}" -f (Read-TextShared $run1))

    $record = [ordered]@{
        task = 'TASK-053'
        section = '2.3 M-5'
        role = 'pre-change baseline of the default running_game_get_node_property_samples response'
        engine = $Engine
        engine_version = $version
        engine_sha256 = (Get-DiskSha $Engine)
        git_head_at_capture = $headSha
        port = $GamePort
        project = $Project
        request_body = $body
        response_file = 'default.response.json'
        response_bytes = $bytes
        response_sha256 = $sha1
        repeat_runs_identical = $same
        repeat_run_sha256 = @($sha2, $sha3)
    }
    Write-McpUtf8NoBom -Path (Join-Path $OutDir 'baseline.json') -Text ((ConvertTo-Json -InputObject $record -Depth 8) + "`n")

    if (-not $same) { Write-Host 'FATAL: the baseline call is not deterministic; it cannot be a fixed point'; exit 4 }
} finally {
    if ($null -ne $handle -and -not $handle.HasExited) {
        & taskkill /PID $handle.Id /T /F *> (Join-Path $LogRoot 'game.taskkill.log')
        Start-Sleep -Milliseconds 1200
    }
}

$portGuardResult = Complete-McpPortGuard -Guard $guard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Write-Host ('port 9877 guard pass = {0} :: {1}' -f $portGuardResult.pass, $portGuardResult.evidence)
if (-not $portGuardResult.pass) { exit 5 }

Write-Host ("baseline written to {0}" -f $OutDir)
exit 0
