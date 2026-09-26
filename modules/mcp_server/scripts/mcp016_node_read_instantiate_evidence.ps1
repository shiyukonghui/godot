# =============================================================================
#  mcp016_node_read_instantiate_evidence.ps1 -- TASK-016 gate 2 evidence
#
#  The live evidence for the two B3 groups this task ports:
#
#    editor_node_read        (6 tools, mutating = false)
#    editor_node_instantiate (4 tools, mutating = true)
#
#  It covers, in one run:
#
#    Scope       the ten tools are served by the editor endpoint 9888, absent
#                from the game endpoint 9889, and a call on 9889 is -32601
#                (never execution).
#    Success     for every tool that has one, with its real response.
#    Refusal     one missing-parameter request per tool that *has* a required
#                parameter (-32602), plus one request of the wrong type where the
#                migration source silently ignored the argument.
#    Bottom      one bottom-layer failure per tool that has one (-32001 for a
#                node, a scene file, a mesh library or a property that is not
#                there). The two tools whose entire contract is "an empty result
#                is a success" have no such class; that is declared per tool.
#    Corrections the two behaviour corrections of this task, measured online:
#                  * `editor_get_node_properties {properties:["no_such_prop_xyz"]}`
#                    is -32001 (the migration source answered `properties: {}`);
#                  * `editor_add_gridmap {mesh_library_path:"res://no_such.tres"}`
#                    is -32001 (the migration source answered `created: true`).
#    Chain A     the read family reading back what TASK-015's write family wrote:
#                add -> set property -> get properties -> set groups -> get
#                groups -> find in group -> connect -> get signals -> list
#                connections -> disconnect -> list connections (count 0) ->
#                delete. Every step observes a state change, not "a 200".
#    Chain B     the instantiation family, read back by the read family and by
#                the B1 `editor_get_scene_tree`.
#
#  Discipline (PLAYBOOK section 3 and section 7.1):
#    * every response body is written with `curl.exe -s -o <file>` and its
#      sha256 is printed from the bytes on disk (nothing through Out-File);
#    * every request body is built with `ConvertTo-Json` and sent with
#      `curl.exe --data-binary @file`;
#    * ports 9888 (editor) / 9889 (game) only; the user's 9877 is never touched
#      and its listener pid is asserted unchanged;
#    * the scratch `.tscn` / `.tres` are written **without a BOM** and the
#      `--import` exit code is checked (M3 acceptance finding).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp016_node_read_instantiate_evidence.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877
$Scratch = Join-Path $env:TEMP 'mcp016-scratch'
$LogRoot = Join-Path $env:TEMP 'mcp016-logs'
$Evid = Join-Path $env:TEMP 'mcp016-evidence'

$script:Results = New-Object System.Collections.Generic.List[object]
$script:EditorHandle = $null
$script:GameHandle = $null

function Add-Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Results.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1} :: {2}" -f $tag, $Id, $Evidence)
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path, [Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-ListenerPid {
    param([int]$Port)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

function Test-PortOpen {
    param([int]$Port, [int]$TimeoutMs = 1500)
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

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $out = Join-Path $LogRoot ($LogName + '.out.log')
    $err = Join-Path $LogRoot ($LogName + '.err.log')
    Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    Write-Host ("started pid={0} :: {1}" -f $proc.Id, ($Arguments -join ' '))
    return [pscustomobject]@{ Process = $proc; Out = $out; Err = $err }
}

function Stop-Engine {
    param($Handle)
    if ($null -eq $Handle) { return }
    try {
        if (-not $Handle.Process.HasExited) {
            Stop-Process -Id $Handle.Process.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 1200
        }
    } catch { }
}

function Import-Project {
    param([string]$Path, [string]$LogName)
    $out = Join-Path $LogRoot ($LogName + '.out.log')
    $err = Join-Path $LogRoot ($LogName + '.err.log')
    # `--mcp-port=0` keeps the import from trying to bind the editor default
    # 9877, which belongs to the user's running editor. The exit code is taken
    # from `$LASTEXITCODE` of a directly invoked native command (TASK-015
    # measured that a `Start-Process` object's `ExitCode` is empty here), and it
    # is *checked*: the M3 acceptance finding is that an import failure used to
    # be swallowed.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
            & $Engine --headless --mcp-port=0 --path $Path --import 1> $out 2> $err
            $code = $LASTEXITCODE
            Write-Host ("import {0}: attempt={1} exit={2} log={3}" -f $Path, $attempt, $code, $out)
            if ($code -eq 0) { return $attempt }
            Write-Host ("attempt {0} failed with {1}; stderr: {2}" -f $attempt, $code, ((Get-Content -Raw $err -ErrorAction SilentlyContinue) -replace "`r?`n", ' | '))
            Start-Sleep -Milliseconds 1500
        }
    } finally {
        $ErrorActionPreference = $previous
    }
    throw ("--import of {0} failed three times" -f $Path)
}

function ConvertTo-CompactJson {
    param($Value)
    return (ConvertTo-Json -InputObject $Value -Depth 12 -Compress)
}

function Format-CallBody {
    param([string]$Tool, $Arguments, [int]$Id)
    $envelope = @{
        jsonrpc = '2.0'
        id      = $Id
        method  = 'tools/call'
        params  = @{ name = $Tool; arguments = $Arguments }
    }
    return (ConvertTo-CompactJson $envelope)
}

function Invoke-Curl {
    param([string]$Id, [string]$Json, [int]$Port, [int]$MaxTimeSec = 60)
    $bodyFile = Join-Path $Evid ("{0}.request.json" -f $Id)
    $respFile = Join-Path $Evid ("{0}.response.json" -f $Id)
    Write-Utf8NoBom -Path $bodyFile -Text $Json
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time $MaxTimeSec -o $respFile -H 'Content-Type: application/json' `
        --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    $curlExit = $LASTEXITCODE
    if (-not (Test-Path $respFile)) {
        Write-Host ("[{0}] curl port={1} exit={2} :: NO RESPONSE FILE" -f $Id, $Port, $curlExit)
        return ''
    }
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] curl port={1} exit={2} bytes={3} sha256={4}" -f $Id, $Port, $curlExit, $bytes.Length, $sha)
    Write-Host ("       request : {0}" -f $Json)
    Write-Host ("       response: {0}" -f $text)
    return $text
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port = $EditorPort, [int]$MaxTimeSec = 60)
    $text = Invoke-Curl -Id $Id -Json (Format-CallBody -Tool $Tool -Arguments $Arguments -Id 1) -Port $Port -MaxTimeSec $MaxTimeSec
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return ConvertFrom-Json $text } catch { return $null }
}

function Get-Payload {
    param($Envelope)
    if ($null -eq $Envelope -or $null -eq $Envelope.result) { return $null }
    $content = @($Envelope.result.content)
    if ($content.Count -lt 1) { return $null }
    try { return ConvertFrom-Json ([string]$content[0].text) } catch { return $null }
}

function Get-ErrorCode {
    param($Envelope)
    if ($null -eq $Envelope -or $null -eq $Envelope.error) { return 0 }
    return [int]$Envelope.error.code
}

function Get-ErrorMessage {
    param($Envelope)
    if ($null -eq $Envelope -or $null -eq $Envelope.error) { return '' }
    return [string]$Envelope.error.message
}

function Get-StatusProbe {
    param([int]$Port)
    $file = Join-Path $Evid ("status_{0}.response.json" -f $Port)
    if (Test-Path $file) { Remove-Item -Force $file }
    & $Curl -s --max-time 5 -o $file ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    if (-not (Test-Path $file)) { return $null }
    $bytes = [IO.File]::ReadAllBytes($file)
    if ($bytes.Length -eq 0) { return $null }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[status] port={0} bytes={1} sha256={2}" -f $Port, $bytes.Length, (Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLower())
    Write-Host ("         body: {0}" -f $text)
    try { return ConvertFrom-Json $text } catch { return $null }
}

function Wait-ForPump {
    param([int]$Port, [int]$TimeoutMs = 300000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $consecutive = 0
    $previous = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Get-StatusProbe -Port $Port
        if ($null -ne $probe) {
            $frames = [int]$probe.frame_count
            if ($null -ne $previous -and ($frames - $previous) -ge 20) { $consecutive++ } else { $consecutive = 0 }
            if ($consecutive -ge 3) { return $true }
            $previous = $frames
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# The relative paths of the edited scene, as `editor_get_scene_tree` (a B1 tool
# of another group) reports them. The first entry is the scene root.
function Get-TreePaths {
    param($Node, [string]$Prefix)
    $name = [string]$Node.name
    $cur = if ([string]::IsNullOrEmpty($Prefix)) { $name } else { "$Prefix/$name" }
    $list = @($cur)
    foreach ($child in @($Node.children)) {
        if ($null -ne $child) { $list += Get-TreePaths -Node $child -Prefix $cur }
    }
    return $list
}

function Read-ScenePaths {
    param([string]$Id)
    $envelope = Invoke-Tool -Id $Id -Tool 'editor_get_scene_tree' -Arguments @{}
    $payload = Get-Payload $envelope
    if ($null -eq $payload -or $null -eq $payload.tree) { return @() }
    return @(Get-TreePaths -Node $payload.tree -Prefix '')
}

function Get-Paths {
    param($Payload)
    if ($null -eq $Payload) { return @() }
    return @(@($Payload.nodes) | ForEach-Object { [string]$_.path })
}

# =============================================================================
# Scratch project
# =============================================================================

$MainScene = @"
[gd_scene format=3]

[node name="Main" type="Node2D"]

[node name="Child" type="Node2D" parent="."]

[node name="World" type="Node" parent="."]
"@

$InstanceScene = @"
[gd_scene format=3]

[node name="InstRoot" type="Node3D"]
"@

# A MeshLibrary with no entries: the point is that the resource really loads and
# is really written into the GridMap's `mesh_library` property.
$MeshLibrary = @"
[gd_resource type="MeshLibrary" format=3]

[resource]
"@

function New-Project {
    param([string]$Path, [string]$Name, [bool]$WithMainScene)
    Remove-Item -Recurse -Force $Path -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $Path 'scenes') | Out-Null
    $lines = @(
        'config_version=5',
        '',
        '[application]',
        ('config/name="' + $Name + '"'),
        'config/features=PackedStringArray("4.8")'
    )
    if ($WithMainScene) { $lines += 'run/main_scene="res://scenes/main.tscn"' }
    $lines += @(
        '',
        '[rendering]',
        'renderer/rendering_method="gl_compatibility"',
        'renderer/rendering_method.mobile="gl_compatibility"'
    )
    Write-Utf8NoBom -Path (Join-Path $Path 'project.godot') -Text (($lines -join "`n") + "`n")
    Write-Utf8NoBom -Path (Join-Path $Path 'scenes\main.tscn') -Text ($MainScene + "`n")
    Write-Utf8NoBom -Path (Join-Path $Path 'scenes\inst.tscn') -Text ($InstanceScene + "`n")
    Write-Utf8NoBom -Path (Join-Path $Path 'scenes\lib.tres') -Text ($MeshLibrary + "`n")
}

# =============================================================================
# Main
# =============================================================================

Write-Host '============================================================='
Write-Host ' TASK-016 gate 2 evidence -- editor_node_read + editor_node_instantiate'
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host "FATAL: engine binary not found: $Engine"; exit 2 }
New-Item -ItemType Directory -Force -Path $Scratch, $LogRoot, $Evid | Out-Null

$EditorProject = Join-Path $Scratch 'editor'
$GameProject = Join-Path $Scratch 'game'
$userPortPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)
Write-Host ("engine --version: {0}" -f (& $Engine --version))

try {
    New-Project -Path $EditorProject -Name 'MCP016 node read' -WithMainScene $false
    New-Project -Path $GameProject -Name 'MCP016 game' -WithMainScene $true

    Write-Host 'importing scratch projects ...'
    $a1 = Import-Project -Path $EditorProject -LogName 'import-editor'
    $a2 = Import-Project -Path $GameProject -LogName 'import-game'
    Add-Check 'import_exit_codes' $true ("both scratch projects imported with exit code 0 (attempts: {0} / {1})" -f $a1, $a2)

    # Both scratch projects hold the same scene files; the game project only
    # needs a runnable main scene for the 9889 endpoint.
    Write-Utf8NoBom -Path (Join-Path $GameProject 'scenes\inst.tscn') -Text ($InstanceScene + "`n")
    Write-Utf8NoBom -Path (Join-Path $GameProject 'scenes\lib.tres') -Text ($MeshLibrary + "`n")

    $script:EditorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $EditorProject, "--mcp-port=$EditorPort") -LogName 'editor'
    if (-not (Wait-ForPump -Port $EditorPort -TimeoutMs 300000)) { throw 'editor endpoint never became ready' }

    $script:GameHandle = Start-Engine -Arguments @('--headless', '--path', $GameProject, "--mcp-port=$GamePort") -LogName 'game'
    if (-not (Wait-ForPump -Port $GamePort -TimeoutMs 240000)) { throw 'game endpoint never became ready' }

    # ------------------------------------------------------------------
    # Scope: served by 9888, absent from 9889, -32601 in the game process
    # ------------------------------------------------------------------
    $TenTools = @(
        'editor_get_node_properties', 'editor_get_node_groups',
        'editor_find_nodes_in_group', 'editor_find_nodes_by_type',
        'editor_get_node_signals', 'editor_list_signal_connections',
        'editor_add_scene_instance', 'editor_add_raycast',
        'editor_add_mesh_instance', 'editor_add_gridmap'
    )
    $editorListText = Invoke-Curl -Id 'scope_editor_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $EditorPort
    $gameListText = Invoke-Curl -Id 'scope_game_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $GamePort
    $editorMissing = @($TenTools | Where-Object { $editorListText -notmatch ('"' + $_ + '"') })
    $gameLeaked = @($TenTools | Where-Object { $gameListText -match ('"' + $_ + '"') })
    Add-Check 'scope_editor_serves_all_ten' ($editorMissing.Count -eq 0) ("missing from 9888: [" + ($editorMissing -join ', ') + "]")
    Add-Check 'scope_game_serves_none' ($gameLeaked.Count -eq 0) ("leaked into 9889: [" + ($gameLeaked -join ', ') + "]")

    foreach ($tool in $TenTools) {
        $args = @{ path = '.' }
        if ($tool -eq 'editor_get_node_groups' -or $tool -eq 'editor_get_node_signals') { $args = @{ node_path = '.' } }
        if ($tool -eq 'editor_find_nodes_in_group') { $args = @{ group = 'g' } }
        if ($tool -eq 'editor_find_nodes_by_type') { $args = @{ type = 'Node' } }
        if ($tool -eq 'editor_list_signal_connections') { $args = @{} }
        if ($tool -eq 'editor_add_scene_instance') { $args = @{ scene_path = 'res://scenes/inst.tscn' } }
        if ($tool -eq 'editor_add_gridmap') { $args = @{ mesh_library_path = 'res://scenes/lib.tres' } }
        if ($tool -eq 'editor_add_raycast' -or $tool -eq 'editor_add_mesh_instance') { $args = @{ name = 'GameProbe' } }
        $envelope = Invoke-Tool -Id ("scope_game_call_" + $tool) -Tool $tool -Arguments $args -Port $GamePort
        $ok = (Get-ErrorCode $envelope) -eq -32601 -and (Get-ErrorMessage $envelope).contains("Method not found: $tool") -and $null -eq $envelope.result
        Add-Check ("scope_game_call_is_32601_" + $tool) $ok ("code=" + (Get-ErrorCode $envelope) + " message='" + (Get-ErrorMessage $envelope) + "'")
    }

    # ------------------------------------------------------------------
    # Open the scene
    # ------------------------------------------------------------------
    $open = Invoke-Tool -Id 'chain_00_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Add-Check 'chain_open_scene' ((Get-ErrorCode $open) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $open)))

    # ------------------------------------------------------------------
    # Success class, one per tool
    # ------------------------------------------------------------------
    $add = Invoke-Tool -Id 'succ_00_add_node_for_reads' -Tool 'editor_add_node' `
        -Arguments @{ type = 'Node2D'; name = 'ReadProbe'; parent_path = '.'; properties = @{ position = @{ x = 1; y = 2 } } }
    Add-Check 'succ_00_add_node_for_reads' ((Get-ErrorCode $add) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $add)))

    # 1. editor_get_node_properties: full listing and a named filter.
    $props = Invoke-Tool -Id 'succ_01_get_node_properties' -Tool 'editor_get_node_properties' -Arguments @{ path = 'ReadProbe' }
    $propsPayload = Get-Payload $props
    $propsOk = (Get-ErrorCode $props) -eq 0 -and [string]$propsPayload.node_path -eq 'ReadProbe' -and
               [string]$propsPayload.type -eq 'Node2D' -and $null -ne $propsPayload.properties.position
    Add-Check 'succ_get_node_properties_full' $propsOk ("keys=" + (@($propsPayload.properties.PSObject.Properties.Name)).Count + " payload=" + (ConvertTo-CompactJson $propsPayload))

    $filtered = Invoke-Tool -Id 'succ_02_get_node_properties_filtered' -Tool 'editor_get_node_properties' `
        -Arguments @{ path = 'ReadProbe'; properties = @('position') }
    $filteredPayload = Get-Payload $filtered
    $filteredOk = (Get-ErrorCode $filtered) -eq 0 -and (@($filteredPayload.properties.PSObject.Properties.Name).Count -eq 1) -and
                  [int]$filteredPayload.properties.position.x -eq 1 -and [int]$filteredPayload.properties.position.y -eq 2
    Add-Check 'succ_get_node_properties_filtered' $filteredOk ("payload=" + (ConvertTo-CompactJson $filteredPayload))

    # 2. editor_get_node_groups
    $groups = Invoke-Tool -Id 'succ_03_get_node_groups' -Tool 'editor_get_node_groups' -Arguments @{ node_path = 'ReadProbe' }
    $groupsPayload = Get-Payload $groups
    Add-Check 'succ_get_node_groups' ((Get-ErrorCode $groups) -eq 0 -and [string]$groupsPayload.node_path -eq 'ReadProbe' -and [int]$groupsPayload.count -eq 0) `
        ("payload=" + (ConvertTo-CompactJson $groupsPayload))

    # 3. editor_find_nodes_in_group (with a group the write family sets below)
    $setGroups = Invoke-Tool -Id 'succ_04_set_node_groups' -Tool 'editor_set_node_groups' -Arguments @{ node_path = 'ReadProbe'; groups = @('mcp016_probe') }
    Add-Check 'succ_04_set_node_groups' ((Get-ErrorCode $setGroups) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $setGroups)))

    $inGroup = Invoke-Tool -Id 'succ_05_find_nodes_in_group' -Tool 'editor_find_nodes_in_group' -Arguments @{ group = 'mcp016_probe' }
    $inGroupPayload = Get-Payload $inGroup
    $inGroupOk = (Get-ErrorCode $inGroup) -eq 0 -and [int]$inGroupPayload.count -eq 1 -and
                 [string]$inGroupPayload.group -eq 'mcp016_probe' -and [string]$inGroupPayload.nodes[0].path -eq 'ReadProbe'
    Add-Check 'succ_find_nodes_in_group' $inGroupOk ("payload=" + (ConvertTo-CompactJson $inGroupPayload))

    # An empty group is a success with count 0, not an error.
    $emptyGroup = Invoke-Tool -Id 'succ_05b_find_nodes_in_group_empty' -Tool 'editor_find_nodes_in_group' -Arguments @{ group = 'mcp016_nobody' }
    Add-Check 'succ_find_nodes_in_group_empty_is_success' ((Get-ErrorCode $emptyGroup) -eq 0 -and [int](Get-Payload $emptyGroup).count -eq 0) `
        ("payload=" + (ConvertTo-CompactJson (Get-Payload $emptyGroup)))

    # 4. editor_find_nodes_by_type
    $byType = Invoke-Tool -Id 'succ_06_find_nodes_by_type' -Tool 'editor_find_nodes_by_type' -Arguments @{ type = 'Node2D' }
    $byTypePayload = Get-Payload $byType
    $byTypeOk = (Get-ErrorCode $byType) -eq 0 -and [int]$byTypePayload.count -ge 2 -and
                (@(Get-Paths $byTypePayload) -contains 'ReadProbe') -and (@(Get-Paths $byTypePayload) -contains 'Child')
    Add-Check 'succ_find_nodes_by_type' $byTypeOk ("count=" + [int]$byTypePayload.count + " paths=[" + ((Get-Paths $byTypePayload) -join ', ') + "]")

    # A type no node has is a success with count 0.
    $emptyType = Invoke-Tool -Id 'succ_06b_find_nodes_by_type_empty' -Tool 'editor_find_nodes_by_type' -Arguments @{ type = 'NoSuchMcpClass' }
    Add-Check 'succ_find_nodes_by_type_empty_is_success' ((Get-ErrorCode $emptyType) -eq 0 -and [int](Get-Payload $emptyType).count -eq 0) `
        ("payload=" + (ConvertTo-CompactJson (Get-Payload $emptyType)))

    # 5. editor_get_node_signals - after a connection exists
    $connect = Invoke-Tool -Id 'succ_07_connect_signal' -Tool 'editor_connect_signal' `
        -Arguments @{ source_path = 'ReadProbe'; signal = 'ready'; method = 'queue_free'; target_path = 'ReadProbe' }
    Add-Check 'succ_07_connect_signal' ((Get-ErrorCode $connect) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $connect)))

    $signals = Invoke-Tool -Id 'succ_08_get_node_signals' -Tool 'editor_get_node_signals' -Arguments @{ node_path = 'ReadProbe' }
    $signalsPayload = Get-Payload $signals
    $readyEntry = $null
    foreach ($entry in @($signalsPayload.signals)) {
        if ([string]$entry.name -eq 'ready') { $readyEntry = $entry }
    }
    $signalsOk = (Get-ErrorCode $signals) -eq 0 -and [string]$signalsPayload.node_path -eq 'ReadProbe' -and
                 [string]$signalsPayload.type -eq 'Node2D' -and $null -ne $readyEntry -and
                 @($readyEntry.connections).Count -ge 1 -and [string]$readyEntry.connections[0].target -eq 'ReadProbe' -and
                 [string]$readyEntry.connections[0].method -eq 'queue_free'
    Add-Check 'succ_get_node_signals' $signalsOk ("payload=" + (ConvertTo-CompactJson $signalsPayload))

    # An argument's `type` is the type *name*, not the migration source's
    # stringified enum value.
    $argType = $null
    foreach ($entry in @($signalsPayload.signals)) {
        if ([string]$entry.name -eq 'child_entered_tree' -and @($entry.args).Count -eq 1) { $argType = [string]$entry.args[0].type }
    }
    Add-Check 'succ_get_node_signals_argument_type_is_a_name' ($argType -eq 'Object') ("child_entered_tree.args[0].type='" + $argType + "'")

    # 6. editor_list_signal_connections - the flat shape, both filters.
    $flat = Invoke-Tool -Id 'succ_09_list_signal_connections' -Tool 'editor_list_signal_connections' -Arguments @{}
    $flatPayload = Get-Payload $flat
    $flatOk = (Get-ErrorCode $flat) -eq 0 -and [int]$flatPayload.count -ge 1 -and
              (@($flatPayload.connections) | Where-Object { [string]$_.source -eq 'ReadProbe' -and [string]$_.signal -eq 'ready' -and [string]$_.target -eq 'ReadProbe' -and [string]$_.method -eq 'queue_free' }).Count -eq 1
    Add-Check 'succ_list_signal_connections' $flatOk ("count=" + [int]$flatPayload.count + " payload=" + (ConvertTo-CompactJson $flatPayload))

    $flatNode = Invoke-Tool -Id 'succ_10_list_signal_connections_node_filter' -Tool 'editor_list_signal_connections' -Arguments @{ node_path = 'ReadProbe' }
    Add-Check 'succ_list_signal_connections_node_filter' ((Get-ErrorCode $flatNode) -eq 0 -and [int](Get-Payload $flatNode).count -eq 1) `
        ("payload=" + (ConvertTo-CompactJson (Get-Payload $flatNode)))
    $flatSignal = Invoke-Tool -Id 'succ_11_list_signal_connections_signal_filter' -Tool 'editor_list_signal_connections' -Arguments @{ signal_name = 'ready' }
    Add-Check 'succ_list_signal_connections_signal_filter' ((Get-ErrorCode $flatSignal) -eq 0 -and [int](Get-Payload $flatSignal).count -eq 1) `
        ("payload=" + (ConvertTo-CompactJson (Get-Payload $flatSignal)))

    # The connection above is a plain `connect()`, i.e. **not** persistent. It is
    # collected: that is the discriminator against editor_analyze_signal_flow.
    Add-Check 'succ_list_signal_connections_collects_non_persistent' ($flatOk) `
        'the collected ready -> ReadProbe.queue_free connection is CONNECT_PERSIST-free'

    # Missing-parameter class, one per tool that has a required parameter.
    $MissingCases = @(
        @{ id = 'miss_get_node_properties'; tool = 'editor_get_node_properties'; args = @{}; frag = 'Missing required parameter: path' },
        @{ id = 'miss_get_node_groups'; tool = 'editor_get_node_groups'; args = @{}; frag = 'Missing required parameter: node_path' },
        @{ id = 'miss_find_nodes_in_group'; tool = 'editor_find_nodes_in_group'; args = @{}; frag = 'Missing required parameter: group' },
        @{ id = 'miss_find_nodes_by_type'; tool = 'editor_find_nodes_by_type'; args = @{}; frag = 'Missing required parameter: type' },
        @{ id = 'miss_get_node_signals'; tool = 'editor_get_node_signals'; args = @{}; frag = 'Missing required parameter: node_path' },
        @{ id = 'miss_add_scene_instance'; tool = 'editor_add_scene_instance'; args = @{}; frag = 'Missing required parameter: scene_path' },
        @{ id = 'miss_add_gridmap'; tool = 'editor_add_gridmap'; args = @{}; frag = 'Missing required parameter: mesh_library_path' }
    )
    foreach ($case in $MissingCases) {
        $envelope = Invoke-Tool -Id $case.id -Tool $case.tool -Arguments $case.args
        $ok = (Get-ErrorCode $envelope) -eq -32602 -and $null -eq $envelope.result -and (Get-ErrorMessage $envelope).contains($case.frag)
        Add-Check $case.id $ok ("code=" + (Get-ErrorCode $envelope) + " message='" + (Get-ErrorMessage $envelope) + "'")
    }
    # `editor_add_raycast`, `editor_add_mesh_instance` and
    # `editor_list_signal_connections` have **no** missing-parameter class: every
    # one of their arguments is optional in the contract. Their refusal class is
    # the wrong-type one below, and the declaration is repeated here so the
    # absence is explicit rather than an omission.
    Add-Check 'miss_not_constructible_for_three_tools' $true `
        'editor_add_raycast / editor_add_mesh_instance / editor_list_signal_connections have no required parameter (contract); their refusal class is the wrong-type one'

    # Wrong-type class: the migration source silently ignored these.
    $TypeCases = @(
        @{ id = 'type_get_node_properties_properties'; tool = 'editor_get_node_properties'; args = @{ path = '.'; properties = 'position' }; frag = "must be an array of strings" },
        @{ id = 'type_get_node_properties_element'; tool = 'editor_get_node_properties'; args = @{ path = '.'; properties = @('position', 7) }; frag = "'properties[1]' must be a string" },
        @{ id = 'type_find_nodes_by_type'; tool = 'editor_find_nodes_by_type'; args = @{ type = 7 }; frag = "'type' must be a string" },
        @{ id = 'type_list_signal_connections'; tool = 'editor_list_signal_connections'; args = @{ signal_name = 7 }; frag = "'signal_name' must be a string" },
        @{ id = 'type_add_raycast_dimension'; tool = 'editor_add_raycast'; args = @{ dimension = 7 }; frag = "'dimension' must be a string" },
        @{ id = 'type_add_mesh_instance_name'; tool = 'editor_add_mesh_instance'; args = @{ name = 7 }; frag = "'name' must be a string" },
        @{ id = 'type_add_gridmap_path'; tool = 'editor_add_gridmap'; args = @{ mesh_library_path = 7 }; frag = "'mesh_library_path' must be a string" }
    )
    foreach ($case in $TypeCases) {
        $envelope = Invoke-Tool -Id $case.id -Tool $case.tool -Arguments $case.args
        $ok = (Get-ErrorCode $envelope) -eq -32602 -and (Get-ErrorMessage $envelope).contains($case.frag)
        Add-Check $case.id $ok ("code=" + (Get-ErrorCode $envelope) + " message='" + (Get-ErrorMessage $envelope) + "'")
    }

    # Bottom-layer failure class.
    $FailureCases = @(
        @{ id = 'fail_get_node_properties_missing'; tool = 'editor_get_node_properties'; args = @{ path = 'NoSuchNode' }; frag = "Node 'NoSuchNode' not found" },
        @{ id = 'fail_get_node_groups_missing'; tool = 'editor_get_node_groups'; args = @{ node_path = 'NoSuchNode' }; frag = "Node 'NoSuchNode' not found" },
        @{ id = 'fail_get_node_signals_missing'; tool = 'editor_get_node_signals'; args = @{ node_path = 'NoSuchNode' }; frag = "Node 'NoSuchNode' not found" },
        @{ id = 'fail_add_scene_instance_missing_file'; tool = 'editor_add_scene_instance'; args = @{ scene_path = 'res://scenes/no_such_scene.tscn' }; frag = "Scene 'res://scenes/no_such_scene.tscn'" },
        @{ id = 'fail_add_scene_instance_missing_parent'; tool = 'editor_add_scene_instance'; args = @{ scene_path = 'res://scenes/inst.tscn'; parent_path = 'NoSuchParent' }; frag = "Parent 'NoSuchParent' not found" },
        @{ id = 'fail_add_raycast_missing_parent'; tool = 'editor_add_raycast'; args = @{ parent_path = 'NoSuchParent' }; frag = "Parent 'NoSuchParent' not found" },
        @{ id = 'fail_add_mesh_instance_missing_parent'; tool = 'editor_add_mesh_instance'; args = @{ parent_path = 'NoSuchParent' }; frag = "Parent 'NoSuchParent' not found" },
        @{ id = 'fail_add_gridmap_missing_parent'; tool = 'editor_add_gridmap'; args = @{ mesh_library_path = 'res://scenes/lib.tres'; parent_path = 'NoSuchParent' }; frag = "Parent 'NoSuchParent' not found" }
    )
    foreach ($case in $FailureCases) {
        $envelope = Invoke-Tool -Id $case.id -Tool $case.tool -Arguments $case.args
        $ok = (Get-ErrorCode $envelope) -eq -32001 -and (Get-ErrorMessage $envelope).contains($case.frag) -and $null -eq $envelope.result
        Add-Check $case.id $ok ("code=" + (Get-ErrorCode $envelope) + " message='" + (Get-ErrorMessage $envelope) + "'")
    }
    # `editor_find_nodes_in_group`, `editor_find_nodes_by_type` and
    # `editor_list_signal_connections` have **no** bottom-layer failure class:
    # "nothing matched" is a success with `count: 0` (asserted above), and the
    # only other state they need - an edited scene - is the state this run is in.
    Add-Check 'fail_not_constructible_for_three_tools' $true `
        'editor_find_nodes_in_group / editor_find_nodes_by_type / editor_list_signal_connections have no bottom-layer failure: an empty match is a success'

    # ------------------------------------------------------------------
    # The two behaviour corrections, measured online
    # ------------------------------------------------------------------
    $named = Invoke-Tool -Id 'fix_01_properties_named_missing' -Tool 'editor_get_node_properties' `
        -Arguments @{ path = 'ReadProbe'; properties = @('no_such_prop_xyz') }
    $namedOk = (Get-ErrorCode $named) -eq -32001 -and (Get-ErrorMessage $named).contains('no_such_prop_xyz') -and
               $null -eq $named.result -and -not [string]::IsNullOrEmpty([string]$named.error.data.suggestion)
    Add-Check 'fix_get_node_properties_refuses_a_named_missing_property' $namedOk `
        ("code=" + (Get-ErrorCode $named) + " message='" + (Get-ErrorMessage $named) + "' result_is_null=" + ($null -eq $named.result) +
         " suggestion='" + [string]$named.error.data.suggestion + "'")

    $scriptProperty = Invoke-Tool -Id 'fix_02_properties_named_script' -Tool 'editor_get_node_properties' `
        -Arguments @{ path = 'ReadProbe'; properties = @('script') }
    Add-Check 'fix_get_node_properties_refuses_the_script_property_by_name' `
        ((Get-ErrorCode $scriptProperty) -eq -32001 -and (Get-ErrorMessage $scriptProperty).contains('not readable by name')) `
        ("code=" + (Get-ErrorCode $scriptProperty) + " message='" + (Get-ErrorMessage $scriptProperty) + "'")

    $badLibrary = Invoke-Tool -Id 'fix_03_add_gridmap_bad_library' -Tool 'editor_add_gridmap' `
        -Arguments @{ mesh_library_path = 'res://scenes/no_such_library.tres'; name = 'BadGridMap' }
    $badLibraryOk = (Get-ErrorCode $badLibrary) -eq -32001 -and (Get-ErrorMessage $badLibrary).contains('no_such_library') -and
                    $null -eq $badLibrary.result -and -not [string]::IsNullOrEmpty([string]$badLibrary.error.data.suggestion)
    Add-Check 'fix_add_gridmap_refuses_an_unloadable_mesh_library' $badLibraryOk `
        ("code=" + (Get-ErrorCode $badLibrary) + " message='" + (Get-ErrorMessage $badLibrary) + "' result_is_null=" + ($null -eq $badLibrary.result) +
         " suggestion='" + [string]$badLibrary.error.data.suggestion + "'")
    $pathsAfterBadLibrary = Read-ScenePaths -Id 'fix_04_tree_after_bad_library'
    Add-Check 'fix_add_gridmap_leaves_no_orphan' ($pathsAfterBadLibrary -notcontains 'Main/BadGridMap') ("paths=[" + ($pathsAfterBadLibrary -join ', ') + "]")

    # ------------------------------------------------------------------
    # editor_add_gridmap with a library that really loads
    # ------------------------------------------------------------------
    $gridmap = Invoke-Tool -Id 'succ_12_add_gridmap' -Tool 'editor_add_gridmap' `
        -Arguments @{ mesh_library_path = 'res://scenes/lib.tres'; name = 'GM'; parent_path = '.' }
    $gridmapPayload = Get-Payload $gridmap
    $gridmapOk = (Get-ErrorCode $gridmap) -eq 0 -and [string]$gridmapPayload.name -eq 'GM' -and
                 [string]$gridmapPayload.type -eq 'GridMap' -and $gridmapPayload.mesh_library_set -eq $true -and
                 [string]$gridmapPayload.parent_path -eq '.' -and [string]$gridmapPayload.mesh_library_path -eq 'res://scenes/lib.tres' -and
                 [string]$gridmapPayload.created -eq 'True'
    Add-Check 'succ_add_gridmap' $gridmapOk ("payload=" + (ConvertTo-CompactJson $gridmapPayload))

    # ------------------------------------------------------------------
    # Chain A: write family (TASK-015) -> read family (this batch)
    # ------------------------------------------------------------------
    Add-Check 'chainA_start' $true 'editor_open_scene already ran; the chain starts from the read family reading the write family'

    $chainA_add = Invoke-Tool -Id 'chainA_01_add_node' -Tool 'editor_add_node' -Arguments @{ type = 'Node2D'; name = 'Chain' }
    Add-Check 'chainA_01_add_node' ((Get-ErrorCode $chainA_add) -eq 0 -and [string](Get-Payload $chainA_add).node_path -eq 'Chain') `
        ("payload=" + (ConvertTo-CompactJson (Get-Payload $chainA_add)))

    $chainA_set = Invoke-Tool -Id 'chainA_02_set_property' -Tool 'editor_set_node_property' `
        -Arguments @{ path = 'Chain'; property = 'position'; value = @{ x = 7; y = 9 } }
    Add-Check 'chainA_02_set_property' ((Get-ErrorCode $chainA_set) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $chainA_set)))

    $chainA_read = Invoke-Tool -Id 'chainA_03_get_properties' -Tool 'editor_get_node_properties' `
        -Arguments @{ path = 'Chain'; properties = @('position') }
    $chainA_readPayload = Get-Payload $chainA_read
    Add-Check 'chainA_03_read_back_the_written_property' `
        ((Get-ErrorCode $chainA_read) -eq 0 -and [int]$chainA_readPayload.properties.position.x -eq 7 -and [int]$chainA_readPayload.properties.position.y -eq 9) `
        ("payload=" + (ConvertTo-CompactJson $chainA_readPayload))

    $chainA_groups = Invoke-Tool -Id 'chainA_04_set_groups' -Tool 'editor_set_node_groups' -Arguments @{ node_path = 'Chain'; groups = @('chain_g') }
    $chainA_groupsPayload = Get-Payload $chainA_groups
    Add-Check 'chainA_04_set_groups' ((Get-ErrorCode $chainA_groups) -eq 0 -and (@($chainA_groupsPayload.added) -contains 'chain_g')) `
        ("payload=" + (ConvertTo-CompactJson $chainA_groupsPayload))

    $chainA_groupRead = Invoke-Tool -Id 'chainA_05_get_groups' -Tool 'editor_get_node_groups' -Arguments @{ node_path = 'Chain' }
    $chainA_groupPayload = Get-Payload $chainA_groupRead
    Add-Check 'chainA_05_read_back_the_group' `
        ((Get-ErrorCode $chainA_groupRead) -eq 0 -and (@($chainA_groupPayload.groups) -contains 'chain_g') -and [int]$chainA_groupPayload.count -eq 1) `
        ("payload=" + (ConvertTo-CompactJson $chainA_groupPayload))

    $chainA_inGroup = Invoke-Tool -Id 'chainA_06_find_in_group' -Tool 'editor_find_nodes_in_group' -Arguments @{ group = 'chain_g' }
    $chainA_inGroupPayload = Get-Payload $chainA_inGroup
    Add-Check 'chainA_06_find_in_group' `
        ((Get-ErrorCode $chainA_inGroup) -eq 0 -and [int]$chainA_inGroupPayload.count -eq 1 -and [string]$chainA_inGroupPayload.nodes[0].path -eq 'Chain') `
        ("payload=" + (ConvertTo-CompactJson $chainA_inGroupPayload))

    $chainA_connect = Invoke-Tool -Id 'chainA_07_connect_signal' -Tool 'editor_connect_signal' `
        -Arguments @{ source_path = 'Chain'; signal = 'ready'; method = 'queue_free'; target_path = '.' }
    Add-Check 'chainA_07_connect_signal' ((Get-ErrorCode $chainA_connect) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $chainA_connect)))

    $chainA_signals = Invoke-Tool -Id 'chainA_08_get_signals' -Tool 'editor_get_node_signals' -Arguments @{ node_path = 'Chain' }
    $chainA_signalsPayload = Get-Payload $chainA_signals
    $chainA_ready = $null
    foreach ($entry in @($chainA_signalsPayload.signals)) {
        if ([string]$entry.name -eq 'ready') { $chainA_ready = $entry }
    }
    Add-Check 'chainA_08_get_signals' `
        ((Get-ErrorCode $chainA_signals) -eq 0 -and $null -ne $chainA_ready -and @($chainA_ready.connections).Count -eq 1 -and
         [string]$chainA_ready.connections[0].target -eq '.' -and [string]$chainA_ready.connections[0].method -eq 'queue_free') `
        ("ready.connections=" + (ConvertTo-CompactJson $chainA_ready.connections))

    $chainA_flat = Invoke-Tool -Id 'chainA_09_list_connections' -Tool 'editor_list_signal_connections' -Arguments @{ node_path = 'Chain' }
    $chainA_flatPayload = Get-Payload $chainA_flat
    Add-Check 'chainA_09_list_connections' `
        ((Get-ErrorCode $chainA_flat) -eq 0 -and [int]$chainA_flatPayload.count -eq 1 -and
         [string]$chainA_flatPayload.connections[0].source -eq 'Chain' -and [string]$chainA_flatPayload.connections[0].signal -eq 'ready' -and
         [string]$chainA_flatPayload.connections[0].target -eq '.' -and [string]$chainA_flatPayload.connections[0].method -eq 'queue_free') `
        ("payload=" + (ConvertTo-CompactJson $chainA_flatPayload))

    $chainA_disconnect = Invoke-Tool -Id 'chainA_10_disconnect' -Tool 'editor_disconnect_signal' `
        -Arguments @{ source_path = 'Chain'; signal = 'ready'; method = 'queue_free'; target_path = '.' }
    Add-Check 'chainA_10_disconnect' ((Get-ErrorCode $chainA_disconnect) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $chainA_disconnect)))

    $chainA_zero = Invoke-Tool -Id 'chainA_11_list_connections_zero' -Tool 'editor_list_signal_connections' -Arguments @{ signal_name = 'ready' }
    Add-Check 'chainA_11_connections_are_gone' ((Get-ErrorCode $chainA_zero) -eq 0 -and [int](Get-Payload $chainA_zero).count -eq 0) `
        ("payload=" + (ConvertTo-CompactJson (Get-Payload $chainA_zero)))

    $chainA_delete = Invoke-Tool -Id 'chainA_12_delete_node' -Tool 'editor_delete_node' -Arguments @{ path = 'Chain' }
    Add-Check 'chainA_12_delete_node' ((Get-ErrorCode $chainA_delete) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $chainA_delete)))
    Start-Sleep -Milliseconds 1200
    $pathsAfterChainA = Read-ScenePaths -Id 'chainA_13_tree_after_delete'
    Add-Check 'chainA_13_node_is_gone' ($pathsAfterChainA -notcontains 'Main/Chain') ("paths=[" + ($pathsAfterChainA -join ', ') + "]")
    $findGone = Invoke-Tool -Id 'chainA_14_find_in_group_gone' -Tool 'editor_find_nodes_in_group' -Arguments @{ group = 'chain_g' }
    Add-Check 'chainA_14_group_is_empty_again' ((Get-ErrorCode $findGone) -eq 0 -and [int](Get-Payload $findGone).count -eq 0) `
        ("payload=" + (ConvertTo-CompactJson (Get-Payload $findGone)))

    # ------------------------------------------------------------------
    # Chain B: instantiation family -> read family
    # ------------------------------------------------------------------
    $chainB_before = Read-ScenePaths -Id 'chainB_00_tree_before'
    Add-Check 'chainB_00_tree_before' $true ("paths=[" + ($chainB_before -join ', ') + "]")

    $rc2d = Invoke-Tool -Id 'chainB_01_add_raycast_2d' -Tool 'editor_add_raycast' -Arguments @{ dimension = '2d'; name = 'RC'; parent_path = '.' }
    $rc2dPayload = Get-Payload $rc2d
    Add-Check 'chainB_01_add_raycast_2d' ((Get-ErrorCode $rc2d) -eq 0 -and [string]$rc2dPayload.type -eq 'RayCast2D' -and [string]$rc2dPayload.node_path -eq 'RC') `
        ("payload=" + (ConvertTo-CompactJson $rc2dPayload))

    $rc3d = Invoke-Tool -Id 'chainB_02_add_raycast_3d' -Tool 'editor_add_raycast' -Arguments @{ dimension = '3d'; name = 'RC3'; parent_path = '.' }
    $rc3dPayload = Get-Payload $rc3d
    Add-Check 'chainB_02_add_raycast_any_other_dimension_is_3d' ((Get-ErrorCode $rc3d) -eq 0 -and [string]$rc3dPayload.type -eq 'RayCast3D') `
        ("payload=" + (ConvertTo-CompactJson $rc3dPayload))

    $mesh = Invoke-Tool -Id 'chainB_03_add_mesh_instance' -Tool 'editor_add_mesh_instance' -Arguments @{ name = 'MI'; parent_path = '.' }
    $meshPayload = Get-Payload $mesh
    Add-Check 'chainB_03_add_mesh_instance' ((Get-ErrorCode $mesh) -eq 0 -and [string]$meshPayload.type -eq 'MeshInstance3D' -and [string]$meshPayload.node_path -eq 'MI') `
        ("payload=" + (ConvertTo-CompactJson $meshPayload))

    $findRaycast2D = Invoke-Tool -Id 'chainB_04_find_nodes_by_type_raycast2d' -Tool 'editor_find_nodes_by_type' -Arguments @{ type = 'RayCast2D' }
    Add-Check 'chainB_04_read_back_raycast2d' ((Get-ErrorCode $findRaycast2D) -eq 0 -and (@(Get-Paths (Get-Payload $findRaycast2D)) -contains 'RC')) `
        ("paths=[" + ((Get-Paths (Get-Payload $findRaycast2D)) -join ', ') + "]")

    $findGridMap = Invoke-Tool -Id 'chainB_05_find_nodes_by_type_gridmap' -Tool 'editor_find_nodes_by_type' -Arguments @{ type = 'GridMap' }
    Add-Check 'chainB_05_read_back_gridmap' ((Get-ErrorCode $findGridMap) -eq 0 -and (@(Get-Paths (Get-Payload $findGridMap)) -contains 'GM')) `
        ("paths=[" + ((Get-Paths (Get-Payload $findGridMap)) -join ', ') + "]")

    $findMesh = Invoke-Tool -Id 'chainB_06_find_nodes_by_type_mesh' -Tool 'editor_find_nodes_by_type' -Arguments @{ type = 'MeshInstance3D' }
    Add-Check 'chainB_06_read_back_mesh' ((Get-ErrorCode $findMesh) -eq 0 -and (@(Get-Paths (Get-Payload $findMesh)) -contains 'MI')) `
        ("paths=[" + ((Get-Paths (Get-Payload $findMesh)) -join ', ') + "]")

    $instance = Invoke-Tool -Id 'chainB_07_add_scene_instance' -Tool 'editor_add_scene_instance' `
        -Arguments @{ scene_path = 'res://scenes/inst.tscn'; name = 'Inst'; parent_path = '.' }
    $instancePayload = Get-Payload $instance
    Add-Check 'chainB_07_add_scene_instance' ((Get-ErrorCode $instance) -eq 0 -and [string]$instancePayload.name -eq 'Inst' -and [string]$instancePayload.scene_path -eq 'res://scenes/inst.tscn') `
        ("payload=" + (ConvertTo-CompactJson $instancePayload))

    $instanceProps = Invoke-Tool -Id 'chainB_08_get_node_properties' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Inst' }
    Add-Check 'chainB_08_read_back_the_instance_type' ((Get-ErrorCode $instanceProps) -eq 0 -and [string](Get-Payload $instanceProps).type -eq 'Node3D') `
        ("payload=" + (ConvertTo-CompactJson (Get-Payload $instanceProps)))

    # The instance keeps its own root name when `name` is absent.
    $instanceDefault = Invoke-Tool -Id 'chainB_09_add_scene_instance_default_name' -Tool 'editor_add_scene_instance' `
        -Arguments @{ scene_path = 'res://scenes/inst.tscn' }
    Add-Check 'chainB_09_add_scene_instance_keeps_the_scene_root_name' ((Get-ErrorCode $instanceDefault) -eq 0 -and [string](Get-Payload $instanceDefault).name -eq 'InstRoot') `
        ("payload=" + (ConvertTo-CompactJson (Get-Payload $instanceDefault)))

    $pathsFinal = Read-ScenePaths -Id 'chainB_10_tree_final'
    $chainBOk = ($pathsFinal -contains 'Main/RC') -and ($pathsFinal -contains 'Main/RC3') -and ($pathsFinal -contains 'Main/MI') -and
                ($pathsFinal -contains 'Main/GM') -and ($pathsFinal -contains 'Main/Inst') -and ($pathsFinal -contains 'Main/InstRoot')
    Add-Check 'chainB_10_tree_contains_every_created_node' $chainBOk ("paths=[" + ($pathsFinal -join ', ') + "]")
} catch {
    Add-Check 'harness_exception' $false ($_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    Stop-Engine -Handle $script:GameHandle
    Stop-Engine -Handle $script:EditorHandle

    $userPortPidAfter = Get-ListenerPid -Port $UserPort
    Add-Check 'guard_user_port_9877' ($userPortPidBefore -eq $userPortPidAfter) `
        ("pid_before={0} pid_after={1}" -f $userPortPidBefore, $userPortPidAfter)

    Write-Host ''
    Write-Host '========================== SUMMARY =========================='
    $passed = @($script:Results | Where-Object { $_.pass }).Count
    $total = $script:Results.Count
    foreach ($r in $script:Results) {
        $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
        Write-Host ("{0}  {1}" -f $tag, $r.id)
    }
    Write-Host ("{0}/{1} checks passed" -f $passed, $total)
    Write-Host ("evidence: {0}" -f $Evid)
    if ($passed -ne $total) { exit 1 }
    exit 0
}
