# =============================================================================
#  accept_m1.ps1 -- independent acceptance run for M1 of modules/mcp_server
#
#  Covers every row of DESIGN-DETAIL.md §9 (14 rows), plus hardening cases that
#  are not part of §9 (connection reaping, `Expect: 100-continue`, 431 for an
#  oversized header, 400 for a bare LF header terminator, and the verbose
#  warning for a non-UTF-8 body), plus a guard that the user's own editor on
#  port 9877 is left untouched.
#
#  Port discipline (see ACCEPTANCE.md "environment facts"):
#    * the editor owned by the user listens on 9877 and must never be touched;
#    * this script therefore uses 9888 (editor side) / 9889 (game side) only;
#    * the default-port logic (9877) is covered by unit tests, never by binding.
#
#  The script only ever kills the PIDs it started itself.
#
#  Reference contract: the equality gate compares against
#  `modules/mcp_server/docs/tools_list.renamed.json`. That file is generated
#  mechanically from the old hof-rs fixture
#  `F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json` by
#  `modules/mcp_server/scripts/gen_renamed_contract.py` (name-only rewrite:
#  description / inputSchema are carried over character for character, so the
#  strictness of the gate is unchanged). The old fixture stays on the
#  provenance chain as `_meta.generated_from`.
#
#  Known engine facts this script works around (documented, not hidden):
#    * `SocketServer::MAX_PENDING_CONNECTIONS` is 8, so more than 8 connections
#      that are simultaneously pending while a frame is busy get reset by
#      Windows. The concurrency case therefore uses 8 parallel connections with
#      pipelined requests (100 requests in flight at once), and waits for the
#      editor's main loop to pump steadily before starting.
#    * the captured snapshot in hof-rs is the authoritative fixture and is
#      compared *verbatim*: name, description and inputSchema must match
#      character for character (case included).  An earlier revision of this
#      script also accepted the Latin-1 recovery of a description double
#      encoded by a PowerShell round trip; that fallback made the gate unable
#      to reject a server emitting mojibake, and it also silently covered the
#      nested descriptions inside `inputSchema`.  The fixture has since been
#      re-captured as clean UTF-8 (GDR-13), so both the fallback and the
#      double encoding are gone.
#    * "the connection is closed after 413" is proven *positively*: a read
#      timeout is not evidence of closure - the same idiom reports "closed" on a
#      keep-alive connection that is demonstrably alive (GDR-12.1).  The check
#      therefore requires a zero length read (FIN), a reset, a failed write, or
#      a probe request that is never answered.
#
#  Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File accept_m1.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$RenamedContract = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877
$ScratchRoot = Join-Path $env:TEMP 'godot-mcp-m1-scratch'
$LogRoot = Join-Path $env:TEMP 'godot-mcp-m1-logs'
$ToolNames = @('project_get_info', 'project_get_settings')

$script:StartedPids = New-Object System.Collections.Generic.List[int]
$script:Results = New-Object System.Collections.Generic.List[object]

# -----------------------------------------------------------------------------
# Reporting helpers
# -----------------------------------------------------------------------------

function Record-Result {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Results.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Invoke-Case {
    param([string]$Id, [scriptblock]$Body)
    try {
        $result = & $Body
        Record-Result -Id $Id -Pass ([bool]$result.pass) -Evidence ([string]$result.evidence)
    } catch {
        Record-Result -Id $Id -Pass $false -Evidence ("exception: " + $_.Exception.Message)
    }
}

# -----------------------------------------------------------------------------
# Small utilities
# -----------------------------------------------------------------------------

function Get-CanonicalJson {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string]) { return (ConvertTo-Json $Value -Compress) }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $parts = @()
        foreach ($p in ($Value.PSObject.Properties | Sort-Object Name)) {
            $parts += ('"' + $p.Name + '":' + (Get-CanonicalJson $p.Value))
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = @()
        foreach ($item in $Value) { $parts += (Get-CanonicalJson $item) }
        return '[' + ($parts -join ',') + ']'
    }
    return (ConvertTo-Json $Value -Compress)
}

# Compares a `tools/list` payload against the authoritative snapshot. Every
# field is compared verbatim (case sensitive): name, description and
# inputSchema. There is deliberately no tolerance for a Latin-1 recovery of a
# description - that fallback used to make this gate unable to reject a server
# that emits mojibake (GDR-13).
function Compare-ToolListToFixture {
    param($ActualTools)
    if (-not (Test-Path $RenamedContract)) {
        Write-Host ("FATAL: renamed contract not found: {0}" -f $RenamedContract)
        Write-Host '        regenerate it with modules\mcp_server\scripts\gen_renamed_contract.py'
        exit 2
    }
    $fixtureJson = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $RenamedContract)
    $fixtureTools = @($fixtureJson.result.tools | Where-Object { $ToolNames -ccontains $_.name })
    $ok = ($ActualTools.Count -eq 2) -and ($fixtureTools.Count -eq 2)
    $notes = @()
    foreach ($name in $ToolNames) {
        $actual = @($ActualTools | Where-Object { $_.name -ceq $name })
        $expected = @($fixtureTools | Where-Object { $_.name -ceq $name })
        if ($actual.Count -ne 1 -or $expected.Count -ne 1) {
            $ok = $false
            $notes += ("{0}: count actual={1} fixture={2}" -f $name, $actual.Count, $expected.Count)
            continue
        }
        $nameEqual = ([string]$actual[0].name -ceq [string]$expected[0].name)
        if (-not $nameEqual) { $ok = $false; $notes += ("{0}: name differs ('{1}' vs '{2}')" -f $name, $actual[0].name, $expected[0].name) }

        $schemaEqual = (Get-CanonicalJson $actual[0].inputSchema) -ceq (Get-CanonicalJson $expected[0].inputSchema)
        if (-not $schemaEqual) { $ok = $false; $notes += ("{0}: inputSchema differs" -f $name) }

        $descriptionEqual = ([string]$actual[0].description -ceq [string]$expected[0].description)
        if (-not $descriptionEqual) { $ok = $false; $notes += ("{0}: description differs" -f $name) }

        $notes += ("{0}: name_verbatim={1} inputSchema_verbatim={2} description_verbatim={3} fixture_description='{4}' actual_description='{5}'" -f `
            $name, $nameEqual, $schemaEqual, $descriptionEqual, $expected[0].description, $actual[0].description)
    }
    return @{ ok = $ok; notes = ($notes -join ' | ') }
}

function Test-Listener {
    param([int]$Port)
    $lines = & netstat -ano -p TCP 2>$null
    foreach ($line in $lines) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port + "\s")) { return $true }
    }
    return $false
}

function Get-ListenerPid {
    param([int]$Port)
    $lines = & netstat -ano -p TCP 2>$null
    foreach ($line in $lines) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port + "\s")) {
            $fields = ($line.Trim() -split '\s+')
            return [int]$fields[-1]
        }
    }
    return -1
}

function Test-TcpConnect {
    param([int]$Port, [int]$TimeoutMs = 800)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        if (-not $task.Wait($TimeoutMs)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Wait-ForTcp {
    param([int]$Port, [int]$TimeoutMs = 120000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-TcpConnect -Port $Port -TimeoutMs 500) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Wait-ForLogLine {
    param([string]$Path, [string]$Pattern, [int]$TimeoutMs = 90000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path $Path) {
            $text = Get-Content -Raw -Path $Path -ErrorAction SilentlyContinue
            if ($text -and $text -match $Pattern) { return $true }
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Get-LogText {
    param([string]$Path)
    if (Test-Path $Path) { return (Get-Content -Raw -Path $Path -ErrorAction SilentlyContinue) }
    return ''
}

function Get-McpLogLines {
    param([string]$Path)
    return (((Get-LogText -Path $Path) -split "`n" | Where-Object { $_ -match '\[MCP\]' }) -join ' | ')
}

# -----------------------------------------------------------------------------
# Raw HTTP client (the server speaks a hand rolled HTTP/1.1 subset)
# -----------------------------------------------------------------------------

function New-Reader {
    param($Stream)
    return [pscustomobject]@{
        Stream = $Stream
        Buffer = (New-Object System.Collections.Generic.List[byte])
    }
}

function Find-HeaderEnd {
    param([byte[]]$Bytes)
    for ($i = 0; $i -le $Bytes.Length - 4; $i++) {
        if ($Bytes[$i] -eq 13 -and $Bytes[$i + 1] -eq 10 -and $Bytes[$i + 2] -eq 13 -and $Bytes[$i + 3] -eq 10) {
            return $i
        }
    }
    return -1
}

function Read-Message {
    param($Reader, [int]$TimeoutMs = 10000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $buf = New-Object byte[] 16384
    while ([DateTime]::UtcNow -lt $deadline) {
        $data = $Reader.Buffer.ToArray()
        $he = Find-HeaderEnd -Bytes $data
        if ($he -ge 0) {
            $headerText = [Text.Encoding]::ASCII.GetString($data, 0, $he)
            $cl = 0
            foreach ($line in ($headerText -split "`r`n")) {
                if ($line -match '^(?i)content-length:\s*(\d+)\s*$') { $cl = [int]$Matches[1] }
            }
            if (($data.Length - ($he + 4)) -ge $cl) {
                $body = [Text.Encoding]::UTF8.GetString($data, $he + 4, $cl)
                $status = 0
                if ($headerText -match '^HTTP/1\.1\s+(\d+)') { $status = [int]$Matches[1] }
                $Reader.Buffer.RemoveRange(0, $he + 4 + $cl)
                return [pscustomobject]@{ Complete = $true; Status = $status; Header = $headerText; Body = $body }
            }
        }
        if ($Reader.Stream.DataAvailable) {
            $n = $Reader.Stream.Read($buf, 0, $buf.Length)
            if ($n -gt 0) {
                $chunk = New-Object byte[] $n
                [Array]::Copy($buf, 0, $chunk, 0, $n)
                $Reader.Buffer.AddRange($chunk)
            } else {
                Start-Sleep -Milliseconds 15
            }
        } else {
            Start-Sleep -Milliseconds 15
        }
    }
    return [pscustomobject]@{ Complete = $false; Status = 0; Header = ''; Body = '' }
}

# PowerShell wraps a failed NetworkStream.Read twice (MethodInvocationException
# -> IOException -> SocketException), so the socket error code has to be dug out
# of the inner exception chain.
function Get-SocketErrorCode {
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    $depth = 0
    while ($null -ne $ex -and $depth -lt 8) {
        if ($ex.GetType().FullName -eq 'System.Net.Sockets.SocketException') { return [string]$ex.SocketErrorCode }
        $ex = $ex.InnerException
        $depth++
    }
    return ''
}

# Positive proof that the peer closed the connection (GDR-12.1 / D-1).
#
# A read timeout alone is NOT proof of closure: on a keep-alive connection that
# is demonstrably alive, "read one byte and call the timeout closed" reports
# closed=True (measured: it returns after the timeout and the same socket then
# serves another request in ~20 ms). One of these positive outcomes is required
# instead:
#   * FIN   - a zero length read, i.e. the peer sent FIN;
#   * RESET - a socket error other than a timeout (e.g. connection reset);
#   * WRITE_FAILED - the probe request could not even be written;
#   * NO_RESPONSE - the probe was written and never answered within the timeout
#     (a live server answers `ping` in milliseconds).
# `kind` is returned so the evidence string states which proof fired.
function Test-PeerClosed {
    param($Conn, [string]$ProbeBody, [string]$ProbeId, [int]$TimeoutMs = 3000, [int]$FinWaitMs = 300)

    # Step 1: has the peer already closed? A graceful close is a zero length
    # read; a timeout here only means "no FIN yet", not "closed".
    $data = New-Object System.Collections.Generic.List[byte]
    $buf = New-Object byte[] 8192
    try {
        $Conn.Stream.ReadTimeout = $FinWaitMs
        $n = $Conn.Stream.Read($buf, 0, $buf.Length)
        if ($n -eq 0) {
            return [pscustomobject]@{ closed = $true; kind = 'FIN'; detail = ("zero-length read (peer FIN) within {0} ms of the last response" -f $FinWaitMs) }
        }
        $chunk = New-Object byte[] $n
        [Array]::Copy($buf, 0, $chunk, 0, $n)
        $data.AddRange($chunk)
    } catch {
        $code = Get-SocketErrorCode -ErrorRecord $_
        if ($code -ne 'TimedOut') {
            return [pscustomobject]@{ closed = $true; kind = 'RESET'; detail = ("socket error {0}: {1}" -f $code, $_.Exception.Message) }
        }
    }

    # Step 2: the probe. A live server answers `ping` in milliseconds.
    try {
        Send-McpRequest -Conn $Conn -Body $ProbeBody
    } catch {
        return [pscustomobject]@{ closed = $true; kind = 'WRITE_FAILED'; detail = ("write to the socket failed: {0}" -f $_.Exception.Message) }
    }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $Conn.Stream.ReadTimeout = $TimeoutMs
        while ($true) {
            $n = $Conn.Stream.Read($buf, 0, $buf.Length)
            if ($n -eq 0) {
                $clock.Stop()
                return [pscustomobject]@{ closed = $true; kind = 'FIN'; detail = ("zero-length read (peer FIN) {0} ms after the probe" -f $clock.ElapsedMilliseconds) }
            }
            $chunk = New-Object byte[] $n
            [Array]::Copy($buf, 0, $chunk, 0, $n)
            $data.AddRange($chunk)
            $text = [Text.Encoding]::UTF8.GetString($data.ToArray())
            if ($text -match [regex]::Escape(('"' + $ProbeId + '"'))) {
                $clock.Stop()
                return [pscustomobject]@{ closed = $false; kind = 'ANSWERED'; detail = ("probe answered after {0} ms: {1}" -f $clock.ElapsedMilliseconds, (($text -replace "`r`n", ' ').Trim())) }
            }
        }
    } catch {
        $clock.Stop()
        $code = Get-SocketErrorCode -ErrorRecord $_
        if ($code -eq 'TimedOut') {
            return [pscustomobject]@{ closed = $true; kind = 'NO_RESPONSE'; detail = ("probe written, no response within {0} ms (read timed out)" -f $TimeoutMs) }
        }
        return [pscustomobject]@{ closed = $true; kind = 'RESET'; detail = ("socket error {0}: {1}" -f $code, $_.Exception.Message) }
    }
}

function Open-Connection {
    param([int]$Port, [int]$TimeoutMs = 5000)
    $client = New-Object System.Net.Sockets.TcpClient
    $task = $client.ConnectAsync('127.0.0.1', $Port)
    if (-not $task.Wait($TimeoutMs)) { throw "connect to 127.0.0.1:$Port timed out" }
    $client.NoDelay = $true
    return [pscustomobject]@{ Client = $client; Stream = $client.GetStream() }
}

function Send-Bytes {
    param($Conn, [byte[]]$Bytes)
    $Conn.Stream.Write($Bytes, 0, $Bytes.Length)
    $Conn.Stream.Flush()
}

function Send-Text {
    param($Conn, [string]$Text)
    Send-Bytes -Conn $Conn -Bytes ([Text.Encoding]::UTF8.GetBytes($Text))
}

function Send-McpRequest {
    param($Conn, [string]$Body)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $head = "POST /mcp HTTP/1.1`r`nHost: 127.0.0.1`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`n`r`n"
    Send-Text -Conn $Conn -Text $head
    Send-Bytes -Conn $Conn -Bytes $bytes
}

function Invoke-Mcp {
    param([int]$Port, [string]$Body, [int]$TimeoutMs = 15000)
    $Conn = Open-Connection -Port $Port
    try {
        Send-McpRequest -Conn $Conn -Body $Body
        return Read-Message -Reader (New-Reader -Stream $Conn.Stream) -TimeoutMs $TimeoutMs
    } finally {
        $Conn.Client.Close()
    }
}

function Invoke-StatusProbe {
    param([int]$Port)
    try {
        $Conn = Open-Connection -Port $Port -TimeoutMs 3000
        try {
            Send-Text -Conn $Conn -Text ("GET /mcp HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n")
            return (Read-Message -Reader (New-Reader -Stream $Conn.Stream) -TimeoutMs 8000)
        } finally { $Conn.Client.Close() }
    } catch {
        return [pscustomobject]@{ Complete = $false; Status = 0; Header = ''; Body = '' }
    }
}

function ConvertFrom-JsonSafe {
    param([string]$Text)
    try { return ($Text | ConvertFrom-Json) } catch { return $null }
}

# The editor spends a while on its first filesystem scan and layout load. If a
# frame takes long, connections pending beyond the listen backlog are reset by
# the OS, so every case waits until the pump runs steadily first.
function Wait-ForStablePump {
    param([int]$Port, [int]$TimeoutMs = 180000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $consecutive = 0
    $previous = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Invoke-StatusProbe -Port $Port
        $json = ConvertFrom-JsonSafe -Text $probe.Body
        if ($null -ne $json) {
            $frames = [int]$json.frame_count
            if ($null -ne $previous -and ($frames - $previous) -ge 20) { $consecutive++ } else { $consecutive = 0 }
            if ($consecutive -ge 3) { return $true }
            $previous = $frames
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# -----------------------------------------------------------------------------
# Engine process management
# -----------------------------------------------------------------------------

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $out = Join-Path $LogRoot ($LogName + '.out.log')
    $err = Join-Path $LogRoot ($LogName + '.err.log')
    Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    $script:StartedPids.Add($proc.Id)
    return [pscustomobject]@{ Process = $proc; Out = $out; Err = $err }
}

function Stop-Engine {
    param($Handle)
    if ($null -eq $Handle) { return }
    try {
        if (-not $Handle.Process.HasExited) {
            Stop-Process -Id $Handle.Process.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 800
        }
    } catch { }
}

function Ensure-ScratchProject {
    param([string]$Path, [string]$Name, [bool]$WithMainScene)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $lines = @(
        'config_version=5',
        '',
        '[application]',
        ('config/name="' + $Name + '"'),
        'config/features=PackedStringArray("4.8")'
    )
    if ($WithMainScene) {
        $lines += 'run/main_scene="res://scenes/main.tscn"'
    }
    $lines += @(
        '',
        '[rendering]',
        'renderer/rendering_method="gl_compatibility"',
        'renderer/rendering_method.mobile="gl_compatibility"'
    )
    Set-Content -Path (Join-Path $Path 'project.godot') -Value ($lines -join "`n") -Encoding UTF8

    if ($WithMainScene) {
        $sceneDir = Join-Path $Path 'scenes'
        New-Item -ItemType Directory -Force -Path $sceneDir | Out-Null
        Set-Content -Path (Join-Path $sceneDir 'main.tscn') -Encoding UTF8 -Value @(
            '[gd_scene format=3]',
            '',
            '[node name="Main" type="Node"]'
        )
    }
}

function Import-Project {
    param([string]$Path, [string]$LogName)
    $handle = Start-Engine -Arguments @('--headless', '--path', $Path, '--import') -LogName $LogName
    $handle.Process.WaitForExit(180000) | Out-Null
    Stop-Engine -Handle $handle
}

# =============================================================================
#  Main
# =============================================================================

Write-Host '============================================================='
Write-Host ' M1 acceptance -- modules/mcp_server'
Write-Host '============================================================='

if (-not (Test-Path $Engine)) {
    Write-Host "FATAL: engine binary not found: $Engine"
    exit 2
}

New-Item -ItemType Directory -Force -Path $ScratchRoot, $LogRoot | Out-Null
$EditorProject = Join-Path $ScratchRoot 'editor'
$GameProject = Join-Path $ScratchRoot 'game'

$userPortPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)

$script:editorHandle = $null
$script:gameHandle = $null
$script:gameNoPortHandle = $null
$script:occupiedHandle = $null
$script:blocker = $null

try {
    # ------------------------------------------------------------------
    # Setup
    # ------------------------------------------------------------------
    Ensure-ScratchProject -Path $EditorProject -Name 'M1 Editor Scratch' -WithMainScene $false
    Ensure-ScratchProject -Path $GameProject -Name 'M1 Game Scratch' -WithMainScene $true

    Write-Host 'importing scratch projects ...'
    Import-Project -Path $EditorProject -LogName 'import-editor'
    Import-Project -Path $GameProject -LogName 'import-game'

    $script:editorHandle = Start-Engine -Arguments @('--headless', '--verbose', '-e', '--path', $EditorProject, "--mcp-port=$EditorPort") -LogName 'editor'
    if (-not (Wait-ForTcp -Port $EditorPort -TimeoutMs 180000)) {
        Write-Host 'FATAL: editor endpoint never came up'
        Write-Host (Get-LogText -Path $script:editorHandle.Out)
        Write-Host (Get-LogText -Path $script:editorHandle.Err)
        throw 'editor endpoint not reachable'
    }
    Write-Host 'waiting for a steadily pumping main loop ...'
    if (-not (Wait-ForStablePump -Port $EditorPort -TimeoutMs 180000)) {
        Write-Host 'WARNING: the pump never looked steady, running the cases anyway'
    }

    # --- case 1: GET /mcp --------------------------------------------------
    Invoke-Case 'case1_GET_mcp_200' {
        $first = Invoke-StatusProbe -Port $EditorPort
        $firstJson = ConvertFrom-JsonSafe -Text $first.Body
        Start-Sleep -Milliseconds 1500
        $second = Invoke-StatusProbe -Port $EditorPort
        $secondJson = ConvertFrom-JsonSafe -Text $second.Body
        $ok = ($first.Status -eq 200) -and ($null -ne $firstJson) -and
              ($firstJson.port -eq $EditorPort) -and ($firstJson.is_editor -eq $true) -and
              ($firstJson.tools -eq 2) -and ($null -ne $secondJson) -and
              ($secondJson.frame_count -gt $firstJson.frame_count)
        return @{
            pass = $ok
            evidence = ("status={0} body={1}; pump frame_count {2} -> {3}" -f $first.Status, $first.Body, $firstJson.frame_count, $secondJson.frame_count)
        }
    }

    # --- case 2: initialize ------------------------------------------------
    Invoke-Case 'case2_initialize' {
        $init = Invoke-Mcp -Port $EditorPort -Body '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
        $json = ConvertFrom-JsonSafe -Text $init.Body
        $ok = ($init.Status -eq 200) -and ($null -ne $json) -and
              ($json.result.protocolVersion -eq '2025-03-26') -and ($json.result.serverInfo.name -eq 'godot-mcp-rs')
        return @{ pass = $ok; evidence = ("status={0} body={1}" -f $init.Status, $init.Body) }
    }

    # --- case 3: tools/list vs the authoritative fixture --------------------
    Invoke-Case 'case3_tools_list_fixture' {
        $list = Invoke-Mcp -Port $EditorPort -Body '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
        $listJson = ConvertFrom-JsonSafe -Text $list.Body
        if ($null -eq $listJson -or $null -eq $listJson.result) {
            return @{ pass = $false; evidence = ("no result: {0}" -f $list.Body) }
        }
        if ((Test-Path $RenamedContract) -eq $false) {
            return @{ pass = $false; evidence = ("renamed contract missing: {0}" -f $RenamedContract) }
        }
        $actualTools = @($listJson.result.tools)
        $comparison = Compare-ToolListToFixture -ActualTools $actualTools
        return @{
            pass = $comparison.ok
            evidence = ("tools={0}; {1}" -f $actualTools.Count, $comparison.notes)
        }
    }

    # --- case 4: tools/call project_get_info success ------------------------
    Invoke-Case 'case4_tools_call_project_info' {
        $call = Invoke-Mcp -Port $EditorPort -Body '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"project_get_info","arguments":{}}}'
        $json = ConvertFrom-JsonSafe -Text $call.Body
        $payload = $null
        $ok = $false
        if ($null -ne $json -and $null -ne $json.result) {
            $payload = ConvertFrom-JsonSafe -Text ([string]$json.result.content[0].text)
            $ok = ($json.result.content[0].type -eq 'text') -and ($null -ne $payload) -and
                  ($payload.project_name -eq 'M1 Editor Scratch') -and ($null -ne $payload.editor_screen_size)
        }
        return @{ pass = $ok; evidence = ("status={0} body={1}" -f $call.Status, $call.Body) }
    }

    # --- case 5: tools/call missing / mistyped params -> -32602 -------------
    Invoke-Case 'case5_tools_call_invalid_params' {
        $missingName = Invoke-Mcp -Port $EditorPort -Body '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{}}'
        $missingJson = ConvertFrom-JsonSafe -Text $missingName.Body
        $badArgs = Invoke-Mcp -Port $EditorPort -Body '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"project_get_info","arguments":"not-an-object"}}'
        $badArgsJson = ConvertFrom-JsonSafe -Text $badArgs.Body
        $ok = ($null -ne $missingJson) -and ($null -ne $badArgsJson) -and
              ($missingJson.error.code -eq -32602) -and ($badArgsJson.error.code -eq -32602)
        return @{ pass = $ok; evidence = ("missing-name={0} bad-arguments={1}" -f $missingName.Body, $badArgs.Body) }
    }

    # --- case 6: unknown method -> -32601 ----------------------------------
    Invoke-Case 'case6_unknown_method' {
        $unknown = Invoke-Mcp -Port $EditorPort -Body '{"jsonrpc":"2.0","id":7,"method":"bogus/method","params":{}}'
        $json = ConvertFrom-JsonSafe -Text $unknown.Body
        $ok = ($null -ne $json) -and ($json.error.code -eq -32601) -and ($json.error.message -eq 'Method not found: bogus/method')
        return @{ pass = $ok; evidence = ("body={0}" -f $unknown.Body) }
    }

    # --- case 7: invalid JSON -> -32700 with null id -----------------------
    Invoke-Case 'case7_parse_error' {
        $bad = Invoke-Mcp -Port $EditorPort -Body '{not json at all'
        $json = ConvertFrom-JsonSafe -Text $bad.Body
        $id = $null
        if ($null -ne $json) { $id = $json.PSObject.Properties['id'].Value }
        $ok = ($null -ne $json) -and ($json.error.code -eq -32700) -and ($null -eq $id)
        return @{ pass = $ok; evidence = ("status={0} body={1}" -f $bad.Status, $bad.Body) }
    }

    # --- case 8: 100 concurrent requests, ids must not be crossed -----------
    # 8 parallel connections (the engine's listen backlog), 100 pipelined
    # requests in flight at the same time, ids interleaved across connections so
    # that any arrival-ordered sharing would be visible immediately.
    Invoke-Case 'case8_concurrent_100' {
        $connectionCount = 8
        $total = 100
        $perConnection = @()
        $remaining = $total
        for ($c = 0; $c -lt $connectionCount; $c++) {
            $take = [Math]::Ceiling($remaining / ($connectionCount - $c))
            $perConnection += [int]$take
            $remaining -= $take
        }
        $conns = @()
        $expectedIds = @()
        $sent = 0
        $received = 0
        $mismatches = @()
        try {
            for ($c = 0; $c -lt $connectionCount; $c++) {
                $conns += (Open-Connection -Port $EditorPort)
            }
            for ($c = 0; $c -lt $connectionCount; $c++) {
                $ids = @()
                for ($j = 0; $j -lt $perConnection[$c]; $j++) {
                    $ids += ($c + 1 + $j * $connectionCount)
                }
                $expectedIds += , $ids
            }
            # Everything is put on the wire before a single response is read.
            for ($c = 0; $c -lt $connectionCount; $c++) {
                foreach ($id in $expectedIds[$c]) {
                    Send-McpRequest -Conn $conns[$c] -Body ('{"jsonrpc":"2.0","id":' + $id + ',"method":"ping"}')
                    $sent++
                }
            }
            for ($c = 0; $c -lt $connectionCount; $c++) {
                $reader = New-Reader -Stream $conns[$c].Stream
                for ($j = 0; $j -lt $perConnection[$c]; $j++) {
                    $msg = Read-Message -Reader $reader -TimeoutMs 30000
                    if (-not $msg.Complete) { $mismatches += ("conn{0}: missing response #{1}" -f $c, $j); break }
                    $json = ConvertFrom-JsonSafe -Text $msg.Body
                    $got = $null
                    if ($null -ne $json) { $got = $json.id }
                    if ($got -ne $expectedIds[$c][$j]) {
                        $mismatches += ("conn{0}: expected id {1} got {2}" -f $c, $expectedIds[$c][$j], $got)
                    }
                    $received++
                }
            }
        } finally {
            foreach ($c in $conns) { $c.Client.Close() }
        }
        $uniqueIds = ($expectedIds | ForEach-Object { $_ } | Sort-Object -Unique).Count
        $ok = ($mismatches.Count -eq 0) -and ($received -eq $total) -and ($sent -eq $total) -and ($uniqueIds -eq $total)
        return @{
            pass = $ok
            evidence = ("connections={0} sent={1} received={2} unique_ids={3} mismatches={4}" -f $connectionCount, $sent, $received, $uniqueIds, ($mismatches -join '; '))
        }
    }

    # --- case 9: keep-alive, two requests on one connection -----------------
    Invoke-Case 'case9_keep_alive_two_requests' {
        $Conn = Open-Connection -Port $EditorPort
        try {
            $reader = New-Reader -Stream $Conn.Stream
            Send-McpRequest -Conn $Conn -Body '{"jsonrpc":"2.0","id":"ka-1","method":"ping"}'
            $r1 = Read-Message -Reader $reader
            Send-McpRequest -Conn $Conn -Body '{"jsonrpc":"2.0","id":"ka-2","method":"ping"}'
            $r2 = Read-Message -Reader $reader
        } finally { $Conn.Client.Close() }
        $j1 = ConvertFrom-JsonSafe -Text $r1.Body
        $j2 = ConvertFrom-JsonSafe -Text $r2.Body
        $ok = ($r1.Status -eq 200) -and ($r2.Status -eq 200) -and ($j1.id -eq 'ka-1') -and ($j2.id -eq 'ka-2')
        return @{ pass = $ok; evidence = ("first={0} second={1}" -f $r1.Body, $r2.Body) }
    }

    # --- case 10: half packet ----------------------------------------------
    Invoke-Case 'case10_half_packet' {
        $Conn = Open-Connection -Port $EditorPort
        try {
            $reader = New-Reader -Stream $Conn.Stream
            $body = '{"jsonrpc":"2.0","id":"half","method":"ping"}'
            $bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
            $head = "POST /mcp HTTP/1.1`r`nHost: 127.0.0.1`r`nContent-Length: $($bodyBytes.Length)`r`n`r`n"
            $whole = [Text.Encoding]::UTF8.GetBytes($head + $body)
            $split = [int]($whole.Length / 2)
            Send-Bytes -Conn $Conn -Bytes $whole[0..($split - 1)]
            Start-Sleep -Milliseconds 400
            Send-Bytes -Conn $Conn -Bytes $whole[$split..($whole.Length - 1)]
            $half = Read-Message -Reader $reader
        } finally { $Conn.Client.Close() }
        $json = ConvertFrom-JsonSafe -Text $half.Body
        $ok = ($half.Status -eq 200) -and ($null -ne $json) -and ($json.id -eq 'half')
        return @{ pass = $ok; evidence = ("status={0} body={1}" -f $half.Status, $half.Body) }
    }

    # --- case 11: body over max_body_bytes -> 413 + closed ------------------
    # The closure is proven positively (GDR-12.1): a probe request is written on
    # the same socket and must not be answered, or the peer is already gone
    # (FIN / reset / failed write). A read timeout on its own is explicitly not
    # accepted - that idiom is also true on a live connection.
    Invoke-Case 'case11_body_too_large' {
        $Conn = Open-Connection -Port $EditorPort
        try {
            Send-Text -Conn $Conn -Text ("POST /mcp HTTP/1.1`r`nHost: 127.0.0.1`r`nContent-Length: 9000000`r`n`r`n")
            $tooBig = Read-Message -Reader (New-Reader -Stream $Conn.Stream) -TimeoutMs 10000
            $probe = Test-PeerClosed -Conn $Conn -ProbeBody '{"jsonrpc":"2.0","id":"after-413","method":"ping"}' -ProbeId 'after-413'
        } finally { $Conn.Client.Close() }
        $ok = ($tooBig.Status -eq 413) -and $probe.closed -and ($probe.kind -ne 'ANSWERED')
        return @{
            pass = $ok
            evidence = ("status={0} closed_after={1} proof={2} ({3}) body={4}" -f $tooBig.Status, $probe.closed, $probe.kind, $probe.detail, $tooBig.Body)
        }
    }

    # --- case 15 (hardening regression): dead peers are reaped --------------
    # A connection table that never notices a peer going away starves the 16
    # connection budget: 16 short lived clients would be enough to make the
    # endpoint refuse everything afterwards. The status body exposes the live
    # table size (`connections`), and a fresh request proves the budget is back.
    Invoke-Case 'case15_connection_reaping' {
        $held = @()
        $capEnforced = $false
        try {
            for ($c = 0; $c -lt 16; $c++) { $held += (Open-Connection -Port $EditorPort) }
            Start-Sleep -Milliseconds 800

            # The 17th connection is closed by the server before it can be used,
            # so either the request cannot be written or it is never answered.
            $over = Open-Connection -Port $EditorPort
            $overResp = $null
            try {
                Send-McpRequest -Conn $over -Body '{"jsonrpc":"2.0","id":1700,"method":"ping"}'
                $overResp = Read-Message -Reader (New-Reader -Stream $over.Stream) -TimeoutMs 5000
            } catch {
                $overResp = $null
            }
            $capEnforced = ($null -eq $overResp) -or (-not ($overResp.Body -match '"id":1700'))
            $over.Client.Close()
        } finally {
            foreach ($c in $held) { $c.Client.Close() }
        }
        Start-Sleep -Milliseconds 800

        $statusAfter = Invoke-StatusProbe -Port $EditorPort
        $statusJson = ConvertFrom-JsonSafe -Text $statusAfter.Body
        $live = -1
        if ($null -ne $statusJson -and $null -ne $statusJson.PSObject.Properties['connections']) {
            $live = [int]$statusJson.connections
        }

        $fresh = Open-Connection -Port $EditorPort
        try {
            Send-McpRequest -Conn $fresh -Body '{"jsonrpc":"2.0","id":999,"method":"ping"}'
            $clock = [Diagnostics.Stopwatch]::StartNew()
            $freshResp = Read-Message -Reader (New-Reader -Stream $fresh.Stream) -TimeoutMs 8000
            $clock.Stop()
        } finally { $fresh.Client.Close() }
        $freshOk = $null -ne $freshResp -and ($freshResp.Body -match '"id":999')

        # 16 entries that are gone must no longer be counted; the status probe's
        # own connection is still in the table and is the only tolerated entry.
        $ok = $capEnforced -and $freshOk -and ($live -ge 0) -and ($live -le 2)
        return @{
            pass = $ok
            evidence = ("cap_enforced_on_17th={0} live_connections_after_close={1} fresh_request_served={2} latency_ms={3}" -f `
                $capEnforced, $live, $freshOk, $clock.ElapsedMilliseconds)
        }
    }

    # --- case 16 (hardening regression): Expect: 100-continue ----------------
    Invoke-Case 'case16_expect_100_continue' {
        $Conn = Open-Connection -Port $EditorPort
        try {
            $reader = New-Reader -Stream $Conn.Stream
            # A body over the 1 KiB threshold is where curl starts to wait for
            # the interim response.
            $body = '{"jsonrpc":"2.0","id":1600,"method":"ping","params":{"pad":"' + ('x' * 2000) + '"}}'
            $bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
            $head = "POST /mcp HTTP/1.1`r`nHost: 127.0.0.1`r`nExpect: 100-continue`r`nContent-Type: application/json`r`nContent-Length: $($bodyBytes.Length)`r`n`r`n"
            Send-Text -Conn $Conn -Text $head

            # The body is withheld: the server has to answer before it is sent.
            $clock = [Diagnostics.Stopwatch]::StartNew()
            $interim = Read-Message -Reader $reader -TimeoutMs 8000
            $clock.Stop()
            $interimSeen = ($interim.Status -eq 100) -and ($interim.Header -match '^HTTP/1\.1 100 Continue')

            Send-Bytes -Conn $Conn -Bytes $bodyBytes
            $final = Read-Message -Reader $reader -TimeoutMs 15000
        } finally { $Conn.Client.Close() }

        $interimCount = ([regex]::Matches($interim.Header + $final.Header, '100 Continue')).Count
        $ok = $interimSeen -and ($interimCount -eq 1) -and ($final.Status -eq 200) -and ($final.Body -match '"id":1600')
        return @{
            pass = $ok
            evidence = ("interim='{0}' after {1} ms; interim_sent_times={2}; final_status={3} final_body={4}" -f `
                ($interim.Header -replace "`r`n", '\r\n'), $clock.ElapsedMilliseconds, $interimCount, $final.Status, $final.Body)
        }
    }

    # --- case 17 (GDR-12.2): header block over 8 KiB -> 431 ----------------
    Invoke-Case 'case17_header_too_large_431' {
        $Conn = Open-Connection -Port $EditorPort
        try {
            $pad = ''
            for ($i = 0; $i -lt 400; $i++) { $pad += "X-Pad: 0123456789012345678901234567890123456789`r`n" }
            Send-Text -Conn $Conn -Text ("POST /mcp HTTP/1.1`r`nHost: 127.0.0.1`r`n" + $pad + "Content-Length: 2`r`n`r`n{}")
            $resp = Read-Message -Reader (New-Reader -Stream $Conn.Stream) -TimeoutMs 10000
            $reason = ''
            if ($resp.Header -match '^HTTP/1\.1\s+(\d+)\s+([^\r\n]+)') { $reason = $Matches[2] }
            $probe = Test-PeerClosed -Conn $Conn -ProbeBody '{"jsonrpc":"2.0","id":"after-431","method":"ping"}' -ProbeId 'after-431'
        } finally { $Conn.Client.Close() }
        $ok = ($resp.Status -eq 431) -and ($reason -eq 'Request Header Fields Too Large') -and $probe.closed
        return @{
            pass = $ok
            evidence = ("status={0} reason='{1}' closed_after={2} proof={3} ({4}) body={5}" -f $resp.Status, $reason, $probe.closed, $probe.kind, $probe.detail, $resp.Body)
        }
    }

    # --- case 18 (GDR-12.3): bare LF header terminator -> 400, not a stall --
    # Before the fix this request produced no answer at all until the 30 s idle
    # reaper closed the connection, so the latency is part of the assertion.
    Invoke-Case 'case18_bare_lf_terminator_400' {
        $Conn = Open-Connection -Port $EditorPort
        try {
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Send-Text -Conn $Conn -Text "POST /mcp HTTP/1.1`nHost: 127.0.0.1`nContent-Length: 2`n`n{}"
            $resp = Read-Message -Reader (New-Reader -Stream $Conn.Stream) -TimeoutMs 10000
            $clock.Stop()
            $probe = Test-PeerClosed -Conn $Conn -ProbeBody '{"jsonrpc":"2.0","id":"after-lf","method":"ping"}' -ProbeId 'after-lf'
        } finally { $Conn.Client.Close() }
        $ok = ($resp.Status -eq 400) -and ($clock.ElapsedMilliseconds -lt 5000) -and $probe.closed
        return @{
            pass = $ok
            evidence = ("status={0} answered_after={1} ms closed_after={2} proof={3} ({4}) body={5}" -f $resp.Status, $clock.ElapsedMilliseconds, $probe.closed, $probe.kind, $probe.detail, $resp.Body)
        }
    }

    # --- case 19 (GDR-12.4): non-UTF-8 body stays accepted but warns --------
    Invoke-Case 'case19_invalid_utf8_body_warns' {
        $Conn = Open-Connection -Port $EditorPort
        try {
            # A payload that is valid JSON once the offending byte is replaced:
            # it must still be served (loose acceptance), with the id echoed.
            $head = '{"jsonrpc":"2.0","id":"utf8","method":"ping","params":{"pad":"'
            $tail = '"}}'
            $bytes = [Text.Encoding]::UTF8.GetBytes($head + '*' + $tail)
            for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -eq 0x2A) { $bytes[$i] = 0xFF } }
            Send-Text -Conn $Conn -Text ("POST /mcp HTTP/1.1`r`nHost: 127.0.0.1`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`n`r`n")
            Send-Bytes -Conn $Conn -Bytes $bytes
            $resp = Read-Message -Reader (New-Reader -Stream $Conn.Stream) -TimeoutMs 10000
            $json = ConvertFrom-JsonSafe -Text $resp.Body
            $accepted = ($resp.Status -eq 200) -and ($null -ne $json) -and ($json.id -eq 'utf8')

            # The substitution is reported on the verbose channel, with the
            # original byte length of the body.
            $warnSeen = Wait-ForLogLine -Path $script:editorHandle.Out -Pattern '\[MCP\] request body is not valid UTF-8 \(\d+ bytes\)' -TimeoutMs 8000
            $warnLine = ''
            if ($warnSeen) {
                $warnLines = @((Get-LogText -Path $script:editorHandle.Out) -split "`n" | Where-Object { $_ -match 'not valid UTF-8' })
                if ($warnLines.Count -gt 0) { $warnLine = ([string]$warnLines[-1]).Trim() }
            }

            # A body that stays invalid JSON after the replacement is still a
            # -32700 (GDR-6), i.e. the loose path does not swallow JSON errors.
            $badBytes = [byte[]]@(0x7B, 0xFF, 0x7D)
            Send-Text -Conn $Conn -Text ("POST /mcp HTTP/1.1`r`nHost: 127.0.0.1`r`nContent-Type: application/json`r`nContent-Length: $($badBytes.Length)`r`n`r`n")
            Send-Bytes -Conn $Conn -Bytes $badBytes
            $resp2 = Read-Message -Reader (New-Reader -Stream $Conn.Stream) -TimeoutMs 10000
            $json2 = ConvertFrom-JsonSafe -Text $resp2.Body
            $parseError = ($null -ne $json2) -and ($json2.error.code -eq -32700)
        } finally { $Conn.Client.Close() }
        $ok = $accepted -and $warnSeen -and $parseError
        return @{
            pass = $ok
            evidence = ("bytes={0} status={1} id_echoed={2} verbose_warning={3} warning_line='{4}' invalid_json_body_status={5} parse_error={6} second_body={7}" -f `
                $bytes.Length, $resp.Status, $accepted, $warnSeen, $warnLine, $resp2.Status, $parseError, $resp2.Body)
        }
    }

    Stop-Engine -Handle $script:editorHandle
    $script:editorHandle = $null

    # ------------------------------------------------------------------
    # Game side
    # ------------------------------------------------------------------
    Invoke-Case 'case12_game_process_endpoint' {
        $script:gameHandle = Start-Engine -Arguments @('--headless', '--path', $GameProject, "--mcp-port=$GamePort") -LogName 'game'
        if (-not (Wait-ForTcp -Port $GamePort -TimeoutMs 180000)) {
            return @{ pass = $false; evidence = ("game endpoint on {0} never came up; log={1}" -f $GamePort, (Get-McpLogLines -Path $script:gameHandle.Out)) }
        }
        if (-not (Wait-ForStablePump -Port $GamePort -TimeoutMs 120000)) {
            return @{ pass = $false; evidence = 'game pump never became steady' }
        }
        $gameList = Invoke-Mcp -Port $GamePort -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
        $gameListJson = ConvertFrom-JsonSafe -Text $gameList.Body
        $gameProbe = Invoke-StatusProbe -Port $GamePort
        $gameProbeJson = ConvertFrom-JsonSafe -Text $gameProbe.Body
        $gameInit = Invoke-Mcp -Port $GamePort -Body '{"jsonrpc":"2.0","id":3,"method":"initialize"}'

        if ($null -eq $gameListJson -or $null -eq $gameListJson.result) {
            return @{ pass = $false; evidence = ("no tools/list result: {0}" -f $gameList.Body) }
        }
        $comparison = Compare-ToolListToFixture -ActualTools @($gameListJson.result.tools)
        $ok = $comparison.ok -and ($gameProbeJson.is_editor -eq $false) -and ($gameInit.Body -match 'godot-mcp-rs')
        return @{
            pass = $ok
            evidence = ("tools/list={0} status={1} is_editor={2} initialize={3}; {4}" -f $gameList.Body, $gameProbe.Status, $gameProbeJson.is_editor, $gameInit.Body, $comparison.notes)
        }
    }
    Stop-Engine -Handle $script:gameHandle
    $script:gameHandle = $null

    # --- case 13: game process without --mcp-port must not listen -----------
    Invoke-Case 'case13_game_without_port' {
        $script:gameNoPortHandle = Start-Engine -Arguments @('--headless', '--path', $GameProject) -LogName 'game-noport'
        $sawRoleLine = Wait-ForLogLine -Path $script:gameNoPortHandle.Out -Pattern '\[MCP\] role=game' -TimeoutMs 180000
        Start-Sleep -Milliseconds 1500
        $listening = Test-TcpConnect -Port $GamePort -TimeoutMs 1500
        $alive = -not $script:gameNoPortHandle.Process.HasExited
        $ok = $sawRoleLine -and (-not $listening) -and $alive
        return @{
            pass = $ok
            evidence = ("role_line={0} listening_on_{1}={2} alive={3} mcp_lines={4}" -f $sawRoleLine, $GamePort, $listening, $alive, (Get-McpLogLines -Path $script:gameNoPortHandle.Out))
        }
    }
    Stop-Engine -Handle $script:gameNoPortHandle
    $script:gameNoPortHandle = $null

    # --- case 14: port already in use -> no crash, WARNING, port 0 ---------
    Invoke-Case 'case14_port_occupied' {
        $script:blocker = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Parse('127.0.0.1'), $EditorPort)
        $script:blocker.Start()
        $blocked = Test-TcpConnect -Port $EditorPort -TimeoutMs 1000
        $script:occupiedHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $EditorProject, "--mcp-port=$EditorPort") -LogName 'editor-occupied'
        $bindFailed = Wait-ForLogLine -Path $script:occupiedHandle.Out -Pattern '\[MCP\] bind failed' -TimeoutMs 180000
        if (-not $bindFailed) { $bindFailed = Wait-ForLogLine -Path $script:occupiedHandle.Err -Pattern 'bind failed' -TimeoutMs 1000 }
        $portZero = Wait-ForLogLine -Path $script:occupiedHandle.Out -Pattern 'get_port\(\)=0' -TimeoutMs 5000
        Start-Sleep -Milliseconds 1500
        $alive = -not $script:occupiedHandle.Process.HasExited
        $ok = $blocked -and $bindFailed -and $portZero -and $alive
        return @{
            pass = $ok
            evidence = ("blocker_listening={0} bind_failed_warning={1} get_port_zero={2} engine_alive={3} mcp_lines={4}" -f $blocked, $bindFailed, $portZero, $alive, (Get-McpLogLines -Path $script:occupiedHandle.Out))
        }
    }
    Stop-Engine -Handle $script:occupiedHandle
    $script:occupiedHandle = $null
    if ($null -ne $script:blocker) { $script:blocker.Stop(); $script:blocker = $null }
} catch {
    Write-Host ("EXCEPTION: {0}" -f $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    Stop-Engine -Handle $script:occupiedHandle
    Stop-Engine -Handle $script:gameNoPortHandle
    Stop-Engine -Handle $script:gameHandle
    Stop-Engine -Handle $script:editorHandle
    if ($null -ne $script:blocker) { try { $script:blocker.Stop() } catch { } }

    # Only the PIDs started by this script are gone; 9877 must be untouched.
    $userPortPidAfter = Get-ListenerPid -Port $UserPort
    $userPortAlive = Test-Listener -Port $UserPort
    $userPortSame = ($userPortPidBefore -eq $userPortPidAfter)
    Record-Result 'guard_user_port_9877' ($userPortAlive -and $userPortSame) ("listening={0} pid_before={1} pid_after={2}" -f $userPortAlive, $userPortPidBefore, $userPortPidAfter)
}

Write-Host ''
Write-Host '========================== SUMMARY =========================='
$passed = @($script:Results | Where-Object { $_.pass }).Count
$total = $script:Results.Count
foreach ($r in $script:Results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0}  {1}" -f $tag, $r.id)
}
Write-Host ("{0}/{1} cases passed" -f $passed, $total)
if ($passed -ne $total) { exit 1 }
exit 0
