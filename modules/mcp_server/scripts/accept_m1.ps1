# =============================================================================
#  accept_m1.ps1 -- independent acceptance run for M1 of modules/mcp_server
#
#  Covers every row of DESIGN-DETAIL.md §9 (14 rows), plus hardening cases that
#  are not part of §9 (connection reaping, `Expect: 100-continue`, 431 for an
#  oversized header, 400 for a bare LF header terminator, and the verbose
#  warning for a non-UTF-8 body), plus a guard that the user's own editor on
#  port 9877 is left untouched.
#
#  TASK-004 §3.1 adds `case20_tools_list_cross_process_restart`: the *same*
#  build served by two *independent* engine processes (the editor is stopped and
#  started again on the same port/project) must answer `tools/list` with
#  byte-identical response bodies. The pre-existing determinism cases only
#  compare calls made to one running process (§17.4), so a build whose listing
#  order depended on, say, a hash seed used at startup would have slipped
#  through.
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
#  `modules/mcp_server/scripts/gen_renamed_contract.py`. The v1.2 generator is
#  still a name-only rewrite plus **7 append-only description discriminators**
#  (R-1/R-2/R-3, TASK-002 section 2.1); inputSchema is carried over character for
#  character everywhere and every description is still compared verbatim, so the
#  strictness of the gate is unchanged. The old fixture stays on the provenance
#  chain as `_meta.generated_from` and `_meta.overrides` lists the 7 reasons.
#
#  Gate scope (R-4): the verbatim comparison covers the tools listed in
#  `$ToolNames` (the implemented ones), never the whole 171 entry contract. The
#  SUMMARY prints "implemented tools N / contract 171" and marks the deviation
#  explicitly, so a per-batch green can never be read as a full-contract green.
#
#  TASK-006 §2 adds the process dimension: `$ToolNames` is the *editor*
#  endpoint's union, `$GameToolNames` is the same union minus the tools whose
#  `scope` is `editor` (docs/tool-rename-map.json is the authority for scope).
#  `case12_game_process_endpoint` compares the game `tools/list` against
#  `$GameToolNames`, asserts that no editor-scope tool leaked into it, and calls
#  one of them to prove the refusal is -32601 rather than execution.
#
#  TASK-010 §1/§4 - B2 opened with the game-side observation group plus the E3
#  lever `running_game_execute_gdscript`. Those tools are all `scope = game`, so
#  they are absent from the editor endpoint's listing and present on the game
#  endpoint's; the derived expectations (`$EditorToolNames` / `$GameToolNames` /
#  the two only-lists) follow from the rename map, so every comparison case keeps
#  working unchanged and no assertion is weakened.
#
#  TASK-018 §2 removed the hand-maintained literal this paragraph used to point
#  at: `$ToolNames` is derived from the group manifests (see the block where it
#  is built), so a new batch no longer edits this file at all. The per-batch
#  manifests are `docs/tool-groups.json` and its `-b2`/`-b3`/`-b4`/`-b5` sisters;
#  this script still does not *decode* them beyond the tools of the groups marked
#  `implemented: true`, and the rename map remains the authority for `scope`.
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
# Windows PowerShell 5.1 prepends one), and `--import`'s exit code is checked
# with a bounded retry and a diagnosis printed on every failure. This acceptance
# gate used to do neither.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-018 section 2: `$ToolNames` is **derived from the manifests** instead of
# being a hand-maintained literal.
#
# Until TASK-018 this was a literal array that every batch had to append to by
# hand (TASK-014/015/016/017 each did, and each recorded it as a declared
# deviation), which is exactly the kind of list that drifts: a tool can be
# implemented and registered while this file still does not know about it, and
# the equality gate then silently keeps testing the previous batch's set.
#
# The single source of truth is now the per-batch group manifests
# (`docs/tool-groups.json`, `-b2`, `-b3`, `-b4`, `-b5`): the expected set is the
# union of the `tools` of every group marked `implemented: true`, in manifest
# order, de-duplicated. Every assertion below keeps its exact form and strength -
# `$EditorToolNames` / `$GameToolNames` / `$EditorOnlyToolNames` /
# `$GameOnlyToolNames` are still derived from `$ToolNames` through the rename
# map, `case3` and `case12` still compare every name/description/inputSchema
# verbatim, and `gate_scope_declared` still checks the implemented count against
# the 171 entry contract. Nothing is weakened; adding a batch now needs no edit
# to this file at all.
#
# A missing manifest is fatal on purpose: skipping one would silently shrink the
# expected set, which is the failure mode this derivation exists to prevent.
$ManifestFileNames = @(
    'tool-groups.json',
    'tool-groups-b2.json',
    'tool-groups-b3.json',
    'tool-groups-b4.json',
    'tool-groups-b5.json',
    'tool-groups-added.json'
)
$ToolNames = @()
foreach ($manifestFileName in $ManifestFileNames) {
    $manifestPath = Join-Path $RepoRoot ('modules\mcp_server\docs\' + $manifestFileName)
    if (-not (Test-Path $manifestPath)) { throw ("group manifest not found: {0}" -f $manifestPath) }
    $manifestJson = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $manifestPath)
    foreach ($manifestGroup in @($manifestJson.groups)) {
        if ($manifestGroup.implemented -ne $true) { continue }
        foreach ($manifestTool in @($manifestGroup.tools)) {
            if ($ToolNames -notcontains $manifestTool) { $ToolNames += [string]$manifestTool }
        }
    }
}
if ($ToolNames.Count -eq 0) { throw 'no implemented tool found in any group manifest' }
Write-Host ("derived tool union : {0} tool(s) from groups marked implemented in {1}" -f `
    $ToolNames.Count, ($ManifestFileNames -join ', '))
# TASK-006 §2: `$ToolNames` is the union of every implemented tool. The *editor*
# endpoint serves that union minus every tool whose `scope` is `game`, and the
# game endpoint serves it minus every tool whose `scope` is `editor`
# (docs/tool-rename-map.json is the authority for scope). TASK-009 added the
# first `scope = game` tool, so the editor-side expectation needs its own
# derived list; before that "every implemented tool" and "the editor endpoint"
# happened to be the same set.
$RenameMap = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-rename-map.json'
$Script:MapJson = $null
$Script:AddedScopeOf = $null
function Get-ToolScope {
    param([string]$Name)
    if ($null -eq $Script:MapJson) {
        if (-not (Test-Path $RenameMap)) { throw "rename map not found: $RenameMap" }
        $Script:MapJson = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $RenameMap)
    }
    foreach ($entry in @($Script:MapJson.tools)) {
        if ([string]$entry.new_name -ceq $Name) { return [string]$entry.scope }
    }
    # TASK-052: an added tool has no rename-map row; its group in
    # docs/tool-groups-added.json declares the scope instead (the same source
    # check_contract_subset.ps1 reads, so gate 1 and this gate cannot disagree).
    if ($null -eq $Script:AddedScopeOf) {
        $Script:AddedScopeOf = @{}
        $addedManifest = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups-added.json'
        if (Test-Path $addedManifest) {
            $addedDoc = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $addedManifest)
            foreach ($addedGroup in @($addedDoc.groups)) {
                foreach ($addedTool in @($addedGroup.tools)) {
                    $Script:AddedScopeOf[[string]$addedTool] = [string]$addedGroup.scope
                }
            }
        }
    }
    if ($Script:AddedScopeOf.ContainsKey($Name)) { return [string]$Script:AddedScopeOf[$Name] }
    return ''
}
$EditorOnlyToolNames = @($ToolNames | Where-Object { (Get-ToolScope $_) -eq 'editor' })
$GameOnlyToolNames = @($ToolNames | Where-Object { (Get-ToolScope $_) -eq 'game' })
$GameToolNames = @($ToolNames | Where-Object { (Get-ToolScope $_) -ne 'editor' })
# What the editor endpoint (9888) serves: the union minus the game-only tools.
$EditorToolNames = @($ToolNames | Where-Object { (Get-ToolScope $_) -ne 'game' })
# R-4 (audit REPORT-AUDIT-001 rename-map v1.1): the verbatim equality gate covers
# the tools that are *implemented*, not the whole contract. Anything less than the
# full contract is a batch gate, not a full-contract gate, and the SUMMARY says so
# explicitly. Registering an unimplemented tool to make the count look complete is
# forbidden (GDR-7).
#
# TASK-052 section 0 (GDR-28 point 2): this used to be the literal 171. The
# contract is `171 + N` now, so the size is derived from the contract's own
# `_meta`: `count` is `len(result.tools)` and `added_count` is how many of those
# the generator's ADDED_TOOLS table authored. The 171 half stays a checked
# literal on purpose - if the contract ever silently lost a ported entry, the two
# numbers would still agree and this guard is what catches it.
if (-not (Test-Path $RenamedContract)) { throw ("renamed contract not found: {0}" -f $RenamedContract) }
$ContractDocForSize = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $RenamedContract)
$ExpectedAddedCount = [int]$ContractDocForSize._meta.added_count
$ExpectedContractSize = [int]@($ContractDocForSize.result.tools).Count
if ($ExpectedContractSize -ne (171 + $ExpectedAddedCount)) {
    throw ("contract size {0} is not 171 + added_count {1}" -f $ExpectedContractSize, $ExpectedAddedCount)
}
Write-Host ("contract size      : {0} = 171 ported + {1} added (GDR-28)" -f `
    $ExpectedContractSize, $ExpectedAddedCount)

$script:StartedPids = New-Object System.Collections.Generic.List[int]
# TASK-041 section 1.3: the *arguments* of every engine this script started, keyed
# by pid. The 9877 guard below proves two things about the user port - that no
# process this script started owns it, and that none of them was even asked for it
# - and the second one needs the real command lines, not an inference.
$script:StartedArguments = @{}
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

    # ------------------------------------------------------------------
    # TASK-069 case: the repository's exit-code propagation check.
    #
    # Defect 2 of TASK-069 was a gate battery that recorded `STEP x EXIT 1` and
    # then exited 0, so the red step was unreadable to every caller (the batch
    # report quoted the 0). The drivers are fixed; what keeps the class from
    # coming back is `scripts/check_exit_propagation.py`, and it is run HERE - in
    # the one acceptance gate every batch runs twice - so it cannot silently
    # disappear. Two invocations, both of which are the check's own contract:
    # the scan (every aggregator shape under scripts/** and docs/scripts/** is
    # guarded or pinned with a reason) and the insertion probes (every declared
    # guard spelling really discharges its shape).
    # ------------------------------------------------------------------
    Invoke-Case 'case0_repo_exit_code_propagation' {
        $checker = Join-Path $RepoRoot 'modules\mcp_server\scripts\check_exit_propagation.py'
        $evidenceDir = Join-Path $env:TEMP 'mcp069'
        if (-not (Test-Path $evidenceDir)) { New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null }
        $scanLog = Join-Path $evidenceDir 'accept_m1_exit_propagation_scan.txt'
        $probeLog = Join-Path $evidenceDir 'accept_m1_exit_propagation_probes.txt'
        & python $checker *> $scanLog
        $scanCode = $LASTEXITCODE
        & python $checker --probes *> $probeLog
        $probeCode = $LASTEXITCODE
        $scanTail = ((Get-Content $scanLog -Tail 1) -join ' ')
        $probeTail = ((Get-Content $probeLog -Tail 1) -join ' ')
        return @{
            pass = (($scanCode -eq 0) -and ($probeCode -eq 0))
            evidence = ("scan exit={0} ('{1}') / --probes exit={2} ('{3}'); logs: {4} , {5}" -f $scanCode, $scanTail, $probeCode, $probeTail, $scanLog, $probeLog)
        }
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
              ($firstJson.tools -eq $EditorToolNames.Count) -and ($null -ne $secondJson) -and
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
        $interimCount = ([regex]::Matches($interim.Header + $final.Header, '100 Continue')).Count
        $ok = $interimSeen -and ($interimCount -eq 1) -and ($final.Status -eq 200) -and ($final.Body -match '"id":1600')
        return @{
            pass = $ok
            evidence = ("interim='{0}' after {1} ms; interim_sent_times={2}; final_status={3} final_body={4}" -f `
                ($interim.Header -replace "`r`n", '\r\n'), $clock.ElapsedMilliseconds, $interimCount, $final.Status, $final.Body)
        }
    }

    Stop-Engine -Handle $script:editorHandle
    $script:editorHandle = $null

    # ------------------------------------------------------------------
    # Game side
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
        $first = Invoke-Mcp -Port $EditorPort -Body $body
        $firstBytes = [Text.Encoding]::UTF8.GetBytes($first.Body)

        Stop-Engine -Handle $script:editorHandle
        $script:editorHandle = $null
        $script:editorHandle = Start-Engine -Arguments @('--headless', '--verbose', '-e', '--path', $EditorProject, "--mcp-port=$EditorPort") -LogName 'editor-restart'
        $secondPid = $script:editorHandle.Process.Id
        if (-not (Wait-ForTcp -Port $EditorPort -TimeoutMs 180000)) {
            return @{ pass = $false; evidence = ("the restarted editor (pid={0}) never came up; log={1}" -f $secondPid, (Get-McpLogLines -Path $script:editorHandle.Out)) }
        }
        if (-not (Wait-ForStablePump -Port $EditorPort -TimeoutMs 180000)) {
            return @{ pass = $false; evidence = 'the restarted editor never pumped steadily' }
        }

        $second = Invoke-Mcp -Port $EditorPort -Body $body
        $secondBytes = [Text.Encoding]::UTF8.GetBytes($second.Body)

        $identical = ($firstBytes.Length -eq $secondBytes.Length)
        if ($identical) {
            for ($i = 0; $i -lt $firstBytes.Length; $i++) {
                if ($firstBytes[$i] -ne $secondBytes[$i]) { $identical = $false; break }
            }
        }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $firstHash = (($sha.ComputeHash($firstBytes) | ForEach-Object { $_.ToString('x2') }) -join '')
        $secondHash = (($sha.ComputeHash($secondBytes) | ForEach-Object { $_.ToString('x2') }) -join '')
        $firstJson = ConvertFrom-JsonSafe -Text $first.Body
        $secondJson = ConvertFrom-JsonSafe -Text $second.Body
        $toolCount = if ($null -ne $firstJson -and $null -ne $firstJson.result) { @($firstJson.result.tools).Count } else { -1 }

        $ok = $identical -and ($firstPid -ne $secondPid) -and ($first.Status -eq 200) -and ($second.Status -eq 200) -and ($toolCount -eq $ToolNames.Count)
        return @{
            pass = $ok
            evidence = ("pid_first={0} pid_second={1} tools={2} bytes={3}/{4} byte_identical={5} sha256_first={6} sha256_second={7}" -f `
                $firstPid, $secondPid, $toolCount, $firstBytes.Length, $secondBytes.Length, $identical, $firstHash, $secondHash)
        }
    }

    Stop-Engine -Handle $script:editorHandle
    $script:editorHandle = $null
    # `tools/list` bodies to be byte-identical, hash included.
    Invoke-Case 'case20_tools_list_cross_process_restart' {
        $body = '{"jsonrpc":"2.0","id":77,"method":"tools/list","params":{}}'
        $firstPid = $script:editorHandle.Process.Id
        $first = Invoke-Mcp -Port $EditorPort -Body $body
        $firstBytes = [Text.Encoding]::UTF8.GetBytes($first.Body)

        Stop-Engine -Handle $script:editorHandle
        $script:editorHandle = $null
        $script:editorHandle = Start-Engine -Arguments @('--headless', '--verbose', '-e', '--path', $EditorProject, "--mcp-port=$EditorPort") -LogName 'editor-restart'
        $secondPid = $script:editorHandle.Process.Id
        if (-not (Wait-ForTcp -Port $EditorPort -TimeoutMs 180000)) {
            return @{ pass = $false; evidence = ("the restarted editor (pid={0}) never came up; log={1}" -f $secondPid, (Get-McpLogLines -Path $script:editorHandle.Out)) }
        }
        if (-not (Wait-ForStablePump -Port $EditorPort -TimeoutMs 180000)) {
            return @{ pass = $false; evidence = 'the restarted editor never pumped steadily' }
        }

        $second = Invoke-Mcp -Port $EditorPort -Body $body
        $secondBytes = [Text.Encoding]::UTF8.GetBytes($second.Body)

        $identical = ($firstBytes.Length -eq $secondBytes.Length)
        if ($identical) {
            for ($i = 0; $i -lt $firstBytes.Length; $i++) {
                if ($firstBytes[$i] -ne $secondBytes[$i]) { $identical = $false; break }
            }
        }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $firstHash = (($sha.ComputeHash($firstBytes) | ForEach-Object { $_.ToString('x2') }) -join '')
        $secondHash = (($sha.ComputeHash($secondBytes) | ForEach-Object { $_.ToString('x2') }) -join '')
        $firstJson = ConvertFrom-JsonSafe -Text $first.Body
        $secondJson = ConvertFrom-JsonSafe -Text $second.Body
        $toolCount = if ($null -ne $firstJson -and $null -ne $firstJson.result) { @($firstJson.result.tools).Count } else { -1 }

        $ok = $identical -and ($firstPid -ne $secondPid) -and ($first.Status -eq 200) -and ($second.Status -eq 200) -and ($toolCount -eq $ToolNames.Count)
        return @{
            pass = $ok
            evidence = ("pid_first={0} pid_second={1} tools={2} bytes={3}/{4} byte_identical={5} sha256_first={6} sha256_second={7}" -f `
                $firstPid, $secondPid, $toolCount, $firstBytes.Length, $secondBytes.Length, $identical, $firstHash, $secondHash)
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
        $comparison = Compare-ToolListToFixture -ActualTools @($gameListJson.result.tools) -Names $GameToolNames
        # TASK-006 §2: no editor-scope tool may be visible on the game endpoint,
        # and asking for one by name must be refused with -32601 rather than run.
        $gameToolNames = @($gameListJson.result.tools | ForEach-Object { [string]$_.name })
        $leaked = @($gameToolNames | Where-Object { $EditorOnlyToolNames -contains $_ })
        $refusal = Invoke-Mcp -Port $GamePort -Body '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"editor_get_errors","arguments":{}}}'
        $refusalJson = ConvertFrom-JsonSafe -Text $refusal.Body
        $refused = ($null -ne $refusalJson) -and ($refusalJson.error.code -eq -32601)
        $ok = $comparison.ok -and ($gameProbeJson.is_editor -eq $false) -and ($gameInit.Body -match 'godot-mcp-rs') -and
              ($leaked.Count -eq 0) -and $refused -and ($gameToolNames.Count -eq $GameToolNames.Count)
        return @{
            pass = $ok
            evidence = ("tools={0} editor_scope_leaked={1} editor_tool_call={2} status={3} is_editor={4} initialize={5}; {6}" -f `
                $gameList.Body, ($leaked -join ','), $refusal.Body, $gameProbe.Status, $gameProbeJson.is_editor, $gameInit.Body, $comparison.notes)
        }
        }
        $gameList = Invoke-Mcp -Port $GamePort -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
        $gameListJson = ConvertFrom-JsonSafe -Text $gameList.Body
        $gameProbe = Invoke-StatusProbe -Port $GamePort
        $gameProbeJson = ConvertFrom-JsonSafe -Text $gameProbe.Body
        $gameInit = Invoke-Mcp -Port $GamePort -Body '{"jsonrpc":"2.0","id":3,"method":"initialize"}'

        if ($null -eq $gameListJson -or $null -eq $gameListJson.result) {
            return @{ pass = $false; evidence = ("no tools/list result: {0}" -f $gameList.Body) }
        }
        $comparison = Compare-ToolListToFixture -ActualTools @($gameListJson.result.tools) -Names $GameToolNames
        # TASK-006 §2: no editor-scope tool may be visible on the game endpoint,
        # and asking for one by name must be refused with -32601 rather than run.
        $gameToolNames = @($gameListJson.result.tools | ForEach-Object { [string]$_.name })
        $leaked = @($gameToolNames | Where-Object { $EditorOnlyToolNames -contains $_ })
        $refusal = Invoke-Mcp -Port $GamePort -Body '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"editor_get_errors","arguments":{}}}'
        $refusalJson = ConvertFrom-JsonSafe -Text $refusal.Body
        $refused = ($null -ne $refusalJson) -and ($refusalJson.error.code -eq -32601)
        $ok = $comparison.ok -and ($gameProbeJson.is_editor -eq $false) -and ($gameInit.Body -match 'godot-mcp-rs') -and
              ($leaked.Count -eq 0) -and $refused -and ($gameToolNames.Count -eq $GameToolNames.Count)
        return @{
            pass = $ok
            evidence = ("tools={0} editor_scope_leaked={1} editor_tool_call={2} status={3} is_editor={4} initialize={5}; {6}" -f `
                $gameList.Body, ($leaked -join ','), $refusal.Body, $gameProbe.Status, $gameProbeJson.is_editor, $gameInit.Body, $comparison.notes)
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

# R-4: state plainly which gate this run is, so that "all cases passed" can
# never be misread as "the whole 171 entry contract is live". The verbatim
# equality gate covers exactly the implemented tools listed in $ToolNames.
$contractSize = 0
if (Test-Path $RenamedContract) {
    $contractJson = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $RenamedContract)
    $contractSize = @($contractJson.result.tools).Count
}
$implementedCount = $ToolNames.Count
Write-Host ("implemented tools      : {0} / contract {1}" -f $implementedCount, $contractSize)
Write-Host ("process split          : editor endpoint {0} tool(s), game endpoint {1} tool(s), editor-only {2}, game-only {3}" -f `
    $EditorToolNames.Count, $GameToolNames.Count, $EditorOnlyToolNames.Count, $GameOnlyToolNames.Count)
Write-Host ("equality gate coverage : {0} tool(s) compared verbatim on the editor endpoint" -f $EditorToolNames.Count)
# D-3 (TASK-003 section 1.2): `-f` binds tighter than `+`, so a multi fragment
# message has to be concatenated *inside* its own parentheses before the format
# operator runs. Without the inner pair only the last fragment was formatted and
# the SUMMARY printed a literal `{0} of {1}` instead of the two counts.
Write-Host (("known_deviation        : per-batch gate, NOT a full-contract gate ({0} of {1} contract entries " +
            "are implemented and compared verbatim); unimplemented tools are deliberately absent from " +
            "tools/list (GDR-7)") -f $implementedCount, $contractSize)
$contractGateOk = ($contractSize -eq $ExpectedContractSize) -and ($implementedCount -le $contractSize)
Record-Result 'gate_scope_declared' $contractGateOk `
    ("implemented={0} contract={1} expected_contract={2} tool_names={3}" -f `
        $implementedCount, $contractSize, $ExpectedContractSize, ($ToolNames -join ','))

$passed = @($script:Results | Where-Object { $_.pass }).Count
$total = $script:Results.Count
foreach ($r in $script:Results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0}  {1}" -f $tag, $r.id)
}
Write-Host ("{0}/{1} cases passed" -f $passed, $total)
Write-Host ("implemented tools = {0} (editor endpoint) / {1} (game endpoint); contract = {2}; known_deviation = per-batch verbatim gate only" -f `
    $EditorToolNames.Count, $GameToolNames.Count, $contractSize)
if ($passed -ne $total) { exit 1 }
exit 0
        $userPortPass = $true
        $userPortClass = 'user_editor_present_untouched'
    } else {
        # A listener that was there before and is a different pid now: this script
        # never kills anything but its own pids, so this is a real surprise and it
        # stays a failure (the old assertion failed here too).
        $userPortPass = $false
        $userPortClass = 'user_editor_pid_changed_during_the_run'
    }
    Record-Result 'guard_user_port_9877' $userPortPass ("listening={0} pid_before={1} pid_after={2} ours={3} same_pid={4} asked_by_us={5} classification={6}" -f `
        $userPortAlive, $userPortPidBefore, $userPortPidAfter, $userPortOurs, $userPortSame, $userPortAsked, $userPortClass)
}

Write-Host ''
Write-Host '========================== SUMMARY =========================='

# R-4: state plainly which gate this run is, so that "all cases passed" can
# never be misread as "the whole 171 entry contract is live". The verbatim
# equality gate covers exactly the implemented tools listed in $ToolNames.
$contractSize = 0
if (Test-Path $RenamedContract) {
    $contractJson = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $RenamedContract)
    $contractSize = @($contractJson.result.tools).Count
}
$implementedCount = $ToolNames.Count
Write-Host ("implemented tools      : {0} / contract {1}" -f $implementedCount, $contractSize)
Write-Host ("process split          : editor endpoint {0} tool(s), game endpoint {1} tool(s), editor-only {2}, game-only {3}" -f `
    $EditorToolNames.Count, $GameToolNames.Count, $EditorOnlyToolNames.Count, $GameOnlyToolNames.Count)
Write-Host ("equality gate coverage : {0} tool(s) compared verbatim on the editor endpoint" -f $EditorToolNames.Count)
# D-3 (TASK-003 section 1.2): `-f` binds tighter than `+`, so a multi fragment
# message has to be concatenated *inside* its own parentheses before the format
# operator runs. Without the inner pair only the last fragment was formatted and
# the SUMMARY printed a literal `{0} of {1}` instead of the two counts.
Write-Host (("known_deviation        : per-batch gate, NOT a full-contract gate ({0} of {1} contract entries " +
            "are implemented and compared verbatim); unimplemented tools are deliberately absent from " +
            "tools/list (GDR-7)") -f $implementedCount, $contractSize)
$contractGateOk = ($contractSize -eq $ExpectedContractSize) -and ($implementedCount -le $contractSize)
Record-Result 'gate_scope_declared' $contractGateOk `
    ("implemented={0} contract={1} expected_contract={2} tool_names={3}" -f `
        $implementedCount, $contractSize, $ExpectedContractSize, ($ToolNames -join ','))

$passed = @($script:Results | Where-Object { $_.pass }).Count
$total = $script:Results.Count
foreach ($r in $script:Results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0}  {1}" -f $tag, $r.id)
}
Write-Host ("{0}/{1} cases passed" -f $passed, $total)
Write-Host ("implemented tools = {0} (editor endpoint) / {1} (game endpoint); contract = {2}; known_deviation = per-batch verbatim gate only" -f `
    $EditorToolNames.Count, $GameToolNames.Count, $contractSize)
if ($passed -ne $total) { exit 1 }
exit 0
    } elseif ($userPortPidBefore -le 0) {
        $userPortPass = $true
        $userPortClass = 'foreign_listener_appeared_during_the_run'
    } elseif ($userPortSame) {
        $userPortPass = $true
        $userPortClass = 'user_editor_present_untouched'
    } else {
        # A listener that was there before and is a different pid now: this script
        # never kills anything but its own pids, so this is a real surprise and it
        # stays a failure (the old assertion failed here too).
        $userPortPass = $false
        $userPortClass = 'user_editor_pid_changed_during_the_run'
    }
    Record-Result 'guard_user_port_9877' $userPortPass ("listening={0} pid_before={1} pid_after={2} ours={3} same_pid={4} asked_by_us={5} classification={6}" -f `
        $userPortAlive, $userPortPidBefore, $userPortPidAfter, $userPortOurs, $userPortSame, $userPortAsked, $userPortClass)
}

Write-Host ''
Write-Host '========================== SUMMARY =========================='

# R-4: state plainly which gate this run is, so that "all cases passed" can
# never be misread as "the whole 171 entry contract is live". The verbatim
# equality gate covers exactly the implemented tools listed in $ToolNames.
$contractSize = 0
if (Test-Path $RenamedContract) {
    $contractJson = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $RenamedContract)
    $contractSize = @($contractJson.result.tools).Count
}
$implementedCount = $ToolNames.Count
Write-Host ("implemented tools      : {0} / contract {1}" -f $implementedCount, $contractSize)
Write-Host ("process split          : editor endpoint {0} tool(s), game endpoint {1} tool(s), editor-only {2}, game-only {3}" -f `
    $EditorToolNames.Count, $GameToolNames.Count, $EditorOnlyToolNames.Count, $GameOnlyToolNames.Count)
Write-Host ("equality gate coverage : {0} tool(s) compared verbatim on the editor endpoint" -f $EditorToolNames.Count)
# D-3 (TASK-003 section 1.2): `-f` binds tighter than `+`, so a multi fragment
# message has to be concatenated *inside* its own parentheses before the format
# operator runs. Without the inner pair only the last fragment was formatted and
# the SUMMARY printed a literal `{0} of {1}` instead of the two counts.
Write-Host (("known_deviation        : per-batch gate, NOT a full-contract gate ({0} of {1} contract entries " +
            "are implemented and compared verbatim); unimplemented tools are deliberately absent from " +
            "tools/list (GDR-7)") -f $implementedCount, $contractSize)
$contractGateOk = ($contractSize -eq $ExpectedContractSize) -and ($implementedCount -le $contractSize)
Record-Result 'gate_scope_declared' $contractGateOk `
    ("implemented={0} contract={1} expected_contract={2} tool_names={3}" -f `
        $implementedCount, $contractSize, $ExpectedContractSize, ($ToolNames -join ','))

$passed = @($script:Results | Where-Object { $_.pass }).Count
$total = $script:Results.Count
foreach ($r in $script:Results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0}  {1}" -f $tag, $r.id)
}
Write-Host ("{0}/{1} cases passed" -f $passed, $total)
Write-Host ("implemented tools = {0} (editor endpoint) / {1} (game endpoint); contract = {2}; known_deviation = per-batch verbatim gate only" -f `
    $EditorToolNames.Count, $GameToolNames.Count, $contractSize)
if ($passed -ne $total) { exit 1 }
exit 0