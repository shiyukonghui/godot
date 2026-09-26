# =============================================================================
#  check_contract_subset.ps1 -- per-group verbatim contract gate
#                         (TASK-002 section 2.4.1)
#
#  Input: a group name from `docs/tool-groups.json` (default:
#  project_read_template) or an explicit comma separated tool name set.
#
#  It starts the engine itself and asserts that the live `tools/list` equals the
#  group's subset of `docs/tools_list.renamed.json` **verbatim**: name,
#  description and inputSchema, with no extra and no missing entry. Both
#  endpoints are exercised by default:
#
#    9888  editor process (`-e --headless --path <scratch editor project>`)
#    9889  game process   (`--headless --path <scratch game project>`)
#
#  TASK-004 §4 changed the "no extra tool" half: as soon as a *second* group is
#  implemented the live list legitimately carries the tools of the other
#  implemented groups, so the total count and the "extra" set are now checked
#  against the union of every group marked `implemented: true` in
#  `docs/tool-groups.json` instead of against this one group. The invariant is
#  unchanged in strength, in fact tightened to state it precisely: the live list
#  must be exactly the set of implemented tools - a tool that is registered
#  while its group is still marked unimplemented, or that is absent from the
#  manifest altogether, is still a FAIL (GDR-7). The group's own seven tools are
#  additionally compared verbatim against the contract, as before.
#
#  TASK-006 §2 - the first `scope = editor` group - adds the process *dimension*
#  to that union. The union is no longer one set: a tool whose `scope` is
#  `editor` (docs/tool-rename-map.json, the authority for scope) is served by the
#  editor endpoint and must be *absent* from the game endpoint, while every other
#  implemented tool is served by both. The game endpoint is therefore checked
#  against the union minus the editor-scope tools, and additionally against an
#  explicit "these editor-only tools must not appear here" list - which is the
#  end-to-end proof that the GDR-19 17.3 guard holds on the wire, not just in the
#  registry.
#
#  Port discipline (ACCEPTANCE.md "environment facts"): the editor owned by the
#  user listens on 9877 and is never touched; the script only kills the PIDs it
#  started itself, and it records a positive 9877 pid-same guard at the end.
#
#  TASK-009 section 2 completes the dimension in the *other* direction. The
#  first `scope = game` tool exists now, so the editor endpoint is checked
#  against the implemented union **minus the game-only tools** (not simply the
#  whole union) and against an explicit "these game-only tools must not appear
#  here" list. Before that change the editor expectation happened to be the
#  whole union because no game-only tool existed.
#
#  TASK-010 §4 - B2 opens. The batch manifest is a *sister* file
#  (`docs/tool-groups-b2.json`), because the B1 file is frozen. The script reads
#  the union of both manifests for the group lookup and for the implemented
#  union; every existing assertion keeps its exact form and strength, so a tool
#  registered while its group is unimplemented, or one missing from the live
#  list, still fails. The B2 half of the batch is `scope = game`, so its tools
#  must be absent from 9888 (asserted by the `HiddenToolNames` list) and present
#  on 9889 (asserted by the count and by the verbatim comparison).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File check_contract_subset.ps1
#    powershell ... -File check_contract_subset.ps1 -Group project_read_template
#    powershell ... -File check_contract_subset.ps1 -Tools project_get_info,project_get_settings
#    powershell ... -File check_contract_subset.ps1 -SkipGame
# =============================================================================

param(
    [string]$Group = 'project_read_template',
    [string]$Tools = '',
    [switch]$SkipEditor,
    [switch]$SkipGame,
    [int]$TimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$RenamedContract = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'
$GroupsJson = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups.json'
# TASK-010: the B2 batch has its own manifest (docs/tool-groups-b2.json) so that
# the frozen B1 file is not edited. A group name is looked up in the union of the
# two manifests, and the implemented union is the union of both. Nothing else
# changes: an unimplemented tool that is registered anyway, or an implemented one
# that is missing, still fails exactly as before.
#
# TASK-015 adds the three B3/B4/B5 manifests (docs/tool-groups-b3.json,
# -b4.json, -b5.json). They are read the same way - a group name is looked up in
# the union of all five files and the implemented union is the union of all
# `implemented: true` groups of all five - so the assertion keeps its exact
# strength: the live list must still be exactly the implemented set for the
# process, no more and no less. The four sister files only widen where a group
# can be found; the B1 file is still read first and is still frozen.
$GroupsJsonB2 = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups-b2.json'
$GroupsJsonB3 = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups-b3.json'
$GroupsJsonB4 = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups-b4.json'
$GroupsJsonB5 = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups-b5.json'
# TASK-052 (GDR-28 point 3): the added tools live in their own manifest
# (`docs/tool-groups-added.json`), which is read exactly like the five batch
# manifests: a group name is looked up in the union of all six files, and the
# implemented union is the union of every `implemented: true` group of all six.
# The gate's strength is unchanged - the live list must still be exactly the
# implemented set for the process - and the added entries are compared verbatim
# by the same code (`$Expected` comes from the contract). The one thing the
# added manifest has to supply itself is the `scope` of its members, because
# `docs/tool-rename-map.json` (the authority for a *ported* tool's scope) has no
# row for a name that was not ported; see `$scopeOf` below.
$GroupsJsonAdded = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups-added.json'
$RenameMap = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-rename-map.json'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877
$ScratchRoot = Join-Path $env:TEMP 'godot-mcp-subset-scratch'
$LogRoot = Join-Path $env:TEMP 'godot-mcp-subset-logs'

# TASK-028 D-1: the one hardened scratch-project writer + `--import` runner. Two
# rules of the PLAYBOOK's section 3 are implemented there and used below: a
# scratch file is never written with a BOM (`Set-Content -Encoding UTF8` on
# Windows PowerShell 5.1 prepends one), and `--import`'s exit code is checked
# with a bounded retry and a diagnosis printed on every failure. This gate used
# to do neither.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

$script:StartedPids = New-Object System.Collections.Generic.List[int]
$script:Results = New-Object System.Collections.Generic.List[object]

# -----------------------------------------------------------------------------
# Reporting
# -----------------------------------------------------------------------------

function Record-Result {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Results.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

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

# -----------------------------------------------------------------------------
# HTTP client (the server speaks a hand rolled HTTP/1.1 subset)
# -----------------------------------------------------------------------------

function Open-Connection {
    param([int]$Port, [int]$Timeout = 5000)
    $client = New-Object System.Net.Sockets.TcpClient
    $task = $client.ConnectAsync('127.0.0.1', $Port)
    if (-not $task.Wait($Timeout)) { throw "connect to 127.0.0.1:$Port timed out" }
    $client.NoDelay = $true
    return [pscustomobject]@{ Client = $client; Stream = $client.GetStream() }
}

function Read-Message {
    param($Conn, [int]$Timeout = 20000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($Timeout)
    $buffer = New-Object System.Collections.Generic.List[byte]
    $chunk = New-Object byte[] 16384
    while ([DateTime]::UtcNow -lt $deadline) {
        $data = $buffer.ToArray()
        $headerEnd = -1
        for ($i = 0; $i -le $data.Length - 4; $i++) {
            if ($data[$i] -eq 13 -and $data[$i + 1] -eq 10 -and $data[$i + 2] -eq 13 -and $data[$i + 3] -eq 10) {
                $headerEnd = $i
                break
            }
        }
        if ($headerEnd -ge 0) {
            $headerText = [Text.Encoding]::ASCII.GetString($data, 0, $headerEnd)
            $length = 0
            foreach ($line in ($headerText -split "`r`n")) {
                if ($line -match '^(?i)content-length:\s*(\d+)\s*$') { $length = [int]$Matches[1] }
            }
            if (($data.Length - ($headerEnd + 4)) -ge $length) {
                return [pscustomobject]@{
                    Status = [int]([regex]::Match($headerText, '^HTTP/1\.1\s+(\d+)').Groups[1].Value)
                    Header = $headerText
                    Body = [Text.Encoding]::UTF8.GetString($data, $headerEnd + 4, $length)
                }
            }
        }
        if ($Conn.Stream.DataAvailable) {
            $read = $Conn.Stream.Read($chunk, 0, $chunk.Length)
            if ($read -gt 0) {
                $part = New-Object byte[] $read
                [Array]::Copy($chunk, 0, $part, 0, $read)
                $buffer.AddRange($part)
            } else { Start-Sleep -Milliseconds 15 }
        } else { Start-Sleep -Milliseconds 15 }
    }
    throw "no complete HTTP response within $Timeout ms"
}

function Invoke-Mcp {
    param([int]$Port, [string]$Body)
    $conn = Open-Connection -Port $Port
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
        $head = "POST /mcp HTTP/1.1`r`nHost: 127.0.0.1`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`n`r`n"
        $conn.Stream.Write([Text.Encoding]::UTF8.GetBytes($head), 0, $head.Length)
        $conn.Stream.Write($bytes, 0, $bytes.Length)
        $conn.Stream.Flush()
        return (Read-Message -Conn $conn)
    } finally { $conn.Client.Close() }
}

function Get-StatusProbe {
    param([int]$Port)
    try {
        $conn = Open-Connection -Port $Port -Timeout 3000
        try {
            $head = "GET /mcp HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n"
            $conn.Stream.Write([Text.Encoding]::UTF8.GetBytes($head), 0, $head.Length)
            $conn.Stream.Flush()
            return (Read-Message -Conn $conn -Timeout 8000)
        } finally { $conn.Client.Close() }
    } catch { return $null }
}

function Wait-ForPump {
    param([int]$Port, [int]$TimeoutMs = 240000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $consecutive = 0
    $previous = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Get-StatusProbe -Port $Port
        if ($null -ne $probe) {
            try { $json = ConvertFrom-Json $probe.Body } catch { $json = $null }
            if ($null -ne $json) {
                $frames = [int]$json.frame_count
                if ($null -ne $previous -and ($frames - $previous) -ge 20) { $consecutive++ } else { $consecutive = 0 }
                if ($consecutive -ge 3) { return $true }
                $previous = $frames
            }
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

function Get-ListenerPid {
    param([int]$Port)
    $lines = & netstat -ano -p TCP 2>$null
    foreach ($line in $lines) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
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
    $lines = @('config_version=5', '', '[application]', ('config/name="' + $Name + '"'), 'config/features=PackedStringArray("4.8")')
    if ($WithMainScene) { $lines += 'run/main_scene="res://scenes/main.tscn"' }
    $lines += @('', '[rendering]', 'renderer/rendering_method="gl_compatibility"', 'renderer/rendering_method.mobile="gl_compatibility"')
    # TASK-028 D-1: no BOM (the old `Set-Content -Encoding UTF8` wrote one).
    Write-McpUtf8NoBom -Path (Join-Path $Path 'project.godot') -Text (($lines -join "`n") + "`n")
    if ($WithMainScene) {
        $sceneDir = Join-Path $Path 'scenes'
        New-Item -ItemType Directory -Force -Path $sceneDir | Out-Null
        Write-McpUtf8NoBom -Path (Join-Path $sceneDir 'main.tscn') -Text ("[gd_scene format=3]`n`n[node name=`"Main`" type=`"Node`"]`n")
    }
}

function Import-Project {
    param([string]$Path, [string]$LogName)
    # TASK-028 D-1: the exit code is checked, a failure is retried a bounded
    # number of times, and every failure prints the command, the code, the log
    # path and the log's tail. The old body started the process, waited and
    # ignored the result, so a half-imported project silently became the input of
    # every later assertion of this gate.
    $result = Import-McpProject -Engine $Engine -Path $Path -LogDirectory $LogRoot -Name $LogName
    $script:LastImportAttempts = $result.attempts
    Write-Host ("import {0}: exit 0 on attempt {1}" -f $Path, $result.attempts)
    return $result.attempts
}

# -----------------------------------------------------------------------------
# Gate
# -----------------------------------------------------------------------------

function Test-Endpoint {
    param([int]$Port, [string]$Label, [string[]]$ToolNames, $Expected, [string[]]$ExpectedTools, [string[]]$HiddenToolNames = @())
    $list = Invoke-Mcp -Port $Port -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
    try { $json = ConvertFrom-Json $list.Body } catch { $json = $null }
    if ($null -eq $json -or $null -eq $json.result) {
        return @{ pass = $false; evidence = ("no tools/list result on {0} ({1}): {2}" -f $Port, $Label, $list.Body) }
    }
    $actual = @($json.result.tools)
    $actualNames = @($actual | ForEach-Object { [string]$_.name })
    $notes = @()
    $ok = $true
    # TASK-006 §2: the expected live list is the implemented union *filtered by
    # this process* - editor-scope tools are served by the editor endpoint only.
    if ($actual.Count -ne $ExpectedTools.Count) {
        $ok = $false
        $notes += ("tool count actual={0} expected_for_{1}={2}" -f $actual.Count, $Label, $ExpectedTools.Count)
    }
    # The selected group's tools that this endpoint is supposed to serve are
    # compared verbatim (name / description / inputSchema).
    foreach ($name in $ToolNames) {
        if ($ExpectedTools -notcontains $name) { continue }
        $a = @($actual | Where-Object { $_.name -ceq $name })
        $e = @($Expected | Where-Object { $_.name -ceq $name })
        if ($a.Count -ne 1 -or $e.Count -ne 1) {
            $ok = $false
            $notes += ("{0}: actual={1} expected={2}" -f $name, $a.Count, $e.Count)
            continue
        }
        $nameSame = ([string]$a[0].name -ceq [string]$e[0].name)
        $descSame = ([string]$a[0].description -ceq [string]$e[0].description)
        $schemaSame = (Get-CanonicalJson $a[0].inputSchema) -ceq (Get-CanonicalJson $e[0].inputSchema)
        if (-not ($nameSame -and $descSame -and $schemaSame)) { $ok = $false }
        $notes += ("{0}: name={1} description={2} inputSchema={3}" -f $name, $nameSame, $descSame, $schemaSame)
        if (-not $descSame) {
            $notes += ("    expected_description='{0}'" -f $e[0].description)
            $notes += ("    actual_description='{0}'" -f $a[0].description)
        }
    }
    # ... and the tools this endpoint is *not* supposed to serve must really be
    # absent. This is the end-to-end half of GDR-19 section 17.3.
    foreach ($name in $ToolNames) {
        if ($ExpectedTools -contains $name) { continue }
        if ($actualNames -contains $name) {
            $ok = $false
            $notes += ("{0}: MUST be hidden on the {1} endpoint but the live list contains it" -f $name, $Label)
        } else {
            $notes += ("{0}: correctly absent on the {1} endpoint" -f $name, $Label)
        }
    }
    # Every tool that is hidden on this endpoint for a *scope* reason.
    foreach ($name in $HiddenToolNames) {
        if ($actualNames -contains $name) {
            $ok = $false
            $notes += ("{0}: scope-hidden tool leaked into the {1} endpoint" -f $name, $Label)
        }
    }
    $extra = @($actualNames | Where-Object { $ExpectedTools -notcontains $_ })
    if ($extra.Count -gt 0) {
        $ok = $false
        $notes += ("unexpected extra tool(s) (not part of any implemented group for this process): {0}" -f ($extra -join ', '))
    }
    $missing = @($ExpectedTools | Where-Object { $actualNames -notcontains $_ })
    if ($missing.Count -gt 0) {
        $ok = $false
        $notes += ("implemented tool(s) missing from the live list: {0}" -f ($missing -join ', '))
    }
    return @{
        pass = $ok
        evidence = ("{0} port={1} tools={2} order={3} | {4}" -f $Label, $Port, $actual.Count,
            ($actualNames -join ' > '), ($notes -join ' | '))
    }
}

# =============================================================================
#  Main
# =============================================================================

Write-Host '============================================================='
Write-Host ' contract subset gate -- modules/mcp_server'
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host "FATAL: engine binary not found: $Engine"; exit 2 }
if (-not (Test-Path $RenamedContract)) { Write-Host "FATAL: renamed contract not found: $RenamedContract"; exit 2 }

$contractJson = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $RenamedContract)
$contractTools = @($contractJson.result.tools)

if ($Tools -ne '') {
    $toolNames = @($Tools -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    $groupLabel = '<explicit tool set>'
    # An explicit set states the exact expected live list.
    $implementedTools = $toolNames
} else {
    if (-not (Test-Path $GroupsJson)) { Write-Host "FATAL: group manifest not found: $GroupsJson"; exit 2 }
    # TASK-010: the B1 manifest is the primary one; the B2 manifest is merged in
    # as a second group list when it exists. `$allGroups` is the only thing the
    # rest of the script reads, so the lookup, the "is this group implemented"
    # warning and the implemented union below all see both batches.
    $manifestDocs = @(ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $GroupsJson))
    # TASK-015: the three new manifests are appended the same way the B2 one is.
    # A missing file is skipped, so the two older gates keep running against
    # exactly the manifests they know.
    foreach ($extraManifest in @($GroupsJsonB2, $GroupsJsonB3, $GroupsJsonB4, $GroupsJsonB5, $GroupsJsonAdded)) {
        if (Test-Path $extraManifest) {
            $manifestDocs += @(ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $extraManifest))
        }
    }
    $allGroups = @($manifestDocs | ForEach-Object { $_.groups })
    # NOTE: the local must NOT be called `$group` - PowerShell variable names are
    # case insensitive, so assigning an array to `$group` would hit the
    # `[string]$Group` type constraint of the parameter and coerce the matched
    # objects into one string.
    $selectedGroup = @($allGroups | Where-Object { $_.name -ceq $Group })
    if ($selectedGroup.Count -ne 1) {
        Write-Host ("FATAL: group '{0}' not found (or ambiguous) in {1}" -f $Group, $GroupsJson)
        Write-Host ("       known groups: {0}" -f ((@($allGroups | ForEach-Object { $_.name })) -join ', '))
        exit 2
    }
    $toolNames = @($selectedGroup[0].tools)
    $groupLabel = $selectedGroup[0].name
    # TASK-004 §4: the live list must be exactly the union of the tools of every
    # group the manifest marks as implemented.
    $implementedTools = @($allGroups | Where-Object { $_.implemented -eq $true } | ForEach-Object { $_.tools })
    if ($selectedGroup[0].implemented -ne $true) {
        Write-Host ("WARNING: group '{0}' is not marked implemented in its manifest; it cannot appear in the live list" -f $Group)
    }
}

Write-Host ("group       : {0}" -f $groupLabel)
Write-Host ("tools       : {0}" -f ($toolNames -join ', '))
Write-Host ("implemented : {0} tool(s) across the groups marked implemented: {1}" -f $implementedTools.Count, ($implementedTools -join ', '))
Write-Host ("contract    : {0} entries" -f $contractTools.Count)

# -----------------------------------------------------------------------------
# TASK-006 §2: the process dimension.
#
# `docs/tool-rename-map.json` is the authority for a tool's `scope`
# ("editor" / "game" / "both"), so the per-endpoint expectation is derived from
# it rather than from the channel prefix or from a hand-maintained list.
# -----------------------------------------------------------------------------
if (-not (Test-Path $RenameMap)) { Write-Host "FATAL: rename map not found: $RenameMap"; exit 2 }
$mapJson = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $RenameMap)
$scopeOf = @{}
foreach ($entry in @($mapJson.tools)) {
    $scopeOf[[string]$entry.new_name] = [string]$entry.scope
}
# TASK-052: an added tool has no rename-map row, so its group declares the scope
# instead. The declaration is the same one `check_tool_groups.py --added` reads,
# and it is checked end to end right here: a wrong scope makes the expected set
# of one of the two endpoints wrong, so the count and the "extra/missing" lists
# below fail. A name that is in neither source keeps the empty scope, which the
# derivations below read as "both" - the honest default is `both` only because
# the added manifest is required to exist here (`--added` fails otherwise).
if (Test-Path $GroupsJsonAdded) {
    $addedDoc = ConvertFrom-Json (Get-Content -Raw -Encoding UTF8 $GroupsJsonAdded)
    foreach ($addedGroup in @($addedDoc.groups)) {
        foreach ($addedTool in @($addedGroup.tools)) {
            $scopeOf[[string]$addedTool] = [string]$addedGroup.scope
        }
    }
}
$editorOnlyTools = @($implementedTools | Where-Object { $scopeOf[$_] -eq 'editor' })
$gameTools = @($implementedTools | Where-Object { $scopeOf[$_] -ne 'editor' })
$gameOnlyTools = @($implementedTools | Where-Object { $scopeOf[$_] -eq 'game' })
# TASK-009 section 2: the editor endpoint serves the implemented union minus the
# game-only tools. Until the first `scope = game` tool existed the two sets were
# the same, so this distinction was invisible.
$editorTools = @($implementedTools | Where-Object { $scopeOf[$_] -ne 'game' })

Write-Host ("scope       : editor-only={0} game-only={1} both/shared={2}" -f `
    $editorOnlyTools.Count, $gameOnlyTools.Count, ($gameTools.Count - $gameOnlyTools.Count))
Write-Host ("editor set  : {0} tool(s)" -f $editorTools.Count)
Write-Host ("game set    : {0} tool(s)" -f $gameTools.Count)
Write-Host ''

$expected = @($contractTools | Where-Object { $toolNames -ccontains $_.name })
if ($expected.Count -ne $toolNames.Count) {
    Write-Host ("FATAL: only {0}/{1} of the requested tools exist in the contract" -f $expected.Count, $toolNames.Count)
    exit 2
}
Write-Host ''

New-Item -ItemType Directory -Force -Path $ScratchRoot, $LogRoot | Out-Null
$EditorProject = Join-Path $ScratchRoot 'editor'
$GameProject = Join-Path $ScratchRoot 'game'
$userPortPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)

$script:editorHandle = $null
$script:gameHandle = $null

try {
    Ensure-ScratchProject -Path $EditorProject -Name 'MCP subset editor' -WithMainScene $false
    Ensure-ScratchProject -Path $GameProject -Name 'MCP subset game' -WithMainScene $true
    Write-Host 'importing scratch projects ...'
    Import-Project -Path $EditorProject -LogName 'subset-import-editor'
    Import-Project -Path $GameProject -LogName 'subset-import-game'

    if (-not $SkipEditor) {
        $script:editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $EditorProject, "--mcp-port=$EditorPort") -LogName 'subset-editor'
        if (-not (Wait-ForPump -Port $EditorPort -TimeoutMs $TimeoutMs)) {
            Record-Result 'editor_9888' $false ("editor endpoint never became ready; log={0}" -f (Get-Content -Raw $script:editorHandle.Out -ErrorAction SilentlyContinue))
        } else {
            $result = Test-Endpoint -Port $EditorPort -Label 'editor' -ToolNames $toolNames -Expected $expected -ExpectedTools $editorTools -HiddenToolNames $gameOnlyTools
            Record-Result 'editor_9888_contract_subset' ([bool]$result.pass) ([string]$result.evidence)
        }
        Stop-Engine -Handle $script:editorHandle
        $script:editorHandle = $null
    }

    if (-not $SkipGame) {
        $script:gameHandle = Start-Engine -Arguments @('--headless', '--path', $GameProject, "--mcp-port=$GamePort") -LogName 'subset-game'
        if (-not (Wait-ForPump -Port $GamePort -TimeoutMs $TimeoutMs)) {
            Record-Result 'game_9889' $false ("game endpoint never became ready; log={0}" -f (Get-Content -Raw $script:gameHandle.Out -ErrorAction SilentlyContinue))
        } else {
            $result = Test-Endpoint -Port $GamePort -Label 'game' -ToolNames $toolNames -Expected $expected -ExpectedTools $gameTools -HiddenToolNames $editorOnlyTools
            Record-Result 'game_9889_contract_subset' ([bool]$result.pass) ([string]$result.evidence)
        }
        Stop-Engine -Handle $script:gameHandle
        $script:gameHandle = $null
    }
} catch {
    Write-Host ("EXCEPTION: {0}" -f $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    Stop-Engine -Handle $script:gameHandle
    Stop-Engine -Handle $script:editorHandle

    $userPortPidAfter = Get-ListenerPid -Port $UserPort
    $userPortSame = ($userPortPidBefore -eq $userPortPidAfter)
    Record-Result 'guard_user_port_9877' $userPortSame ("pid_before={0} pid_after={1}" -f $userPortPidBefore, $userPortPidAfter)
}

Write-Host ''
Write-Host '========================== SUMMARY =========================='
$passed = @($script:Results | Where-Object { $_.pass }).Count
$total = $script:Results.Count
foreach ($r in $script:Results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0}  {1}" -f $tag, $r.id)
}
Write-Host ("group={0} tools={1} contract={2}" -f $groupLabel, $toolNames.Count, $contractTools.Count)
Write-Host ("implemented_union={0} tools (editor endpoint) / {1} tools (game endpoint)" -f $editorTools.Count, $gameTools.Count)
Write-Host ("{0}/{1} checks passed" -f $passed, $total)
if ($passed -ne $total) { exit 1 }
exit 0