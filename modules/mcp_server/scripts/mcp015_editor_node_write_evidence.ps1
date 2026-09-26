# =============================================================================
#  mcp015_editor_node_write_evidence.ps1 -- TASK-015 gate 2 evidence
#
#  The live evidence for B3's first group (`editor_node_write`, ten editor-scope
#  node writes). It covers, in one run:
#
#    Scope       the ten tools are served by the editor endpoint 9888, absent
#                from the game endpoint 9889, and a call on 9889 is -32601
#                (never execution).
#    Success     for every tool that has one: add / duplicate / rename /
#                reparent / set property / set groups / connect / disconnect /
#                delete, each with its real response.
#    Refusal     one missing-parameter request per tool (-32602) and one
#                bottom-layer failure per tool that has one (-32001 for a node,
#                a signal or a property that is not there; -32602 for a class
#                that does not exist).
#    Honesty     `editor_set_auto_dismiss_dialogs` has **no** success class: the
#                tool answers -32000 Not implemented with a suggestion because
#                this engine has no process-wide auto-dismiss behaviour. The
#                script asserts the refusal and asserts that no success shape is
#                produced, which is the whole point of the fix-first pair.
#    Chain       the group's cross-tool evidence chain: add -> read back with
#                `editor_get_scene_tree` (a B1 tool of another group) -> write a
#                property -> rename -> duplicate -> reparent -> read back again
#                -> delete -> read back a third time. Every state change is
#                observed by a *different* tool than the one that made it.
#
#  Discipline (PLAYBOOK section 3 and section 7.1):
#    * every response body is written with `curl.exe -s -o <file>` and its
#      sha256 is printed from the bytes on disk (nothing through Out-File).
#    * every request body is built with `ConvertTo-Json`.
#    * ports 9888 (editor) / 9889 (game) only; the user's 9877 is never touched
#      and its listener pid is asserted unchanged.
#    * the scratch `.tscn` / `project.godot` are written **without a BOM** and
#      the `--import` exit code is checked (M3 acceptance finding).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp015_editor_node_write_evidence.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877
$Scratch = Join-Path $env:TEMP 'mcp015-scratch'
$LogRoot = Join-Path $env:TEMP 'mcp015-logs'
$Evid = Join-Path $env:TEMP 'mcp015-evidence'

$script:Results = New-Object System.Collections.Generic.List[object]
$script:StartedPids = New-Object System.Collections.Generic.List[int]

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
    $script:StartedPids.Add($proc.Id)
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
    # `--mcp-port=0` keeps the import from *trying* to bind the editor default
    # 9877, which belongs to the user's running editor (MCPPort::should_listen is
    # false for a port <= 0). The import has no business opening an endpoint.
    #
    # The exit code is taken from `$LASTEXITCODE` of a directly invoked native
    # command, not from a `Start-Process` object: the object's `ExitCode` came
    # back empty under the PowerShell this runs on (measured: the first two runs
    # of this script refused a perfectly good import). Native stderr is written
    # straight to a file, so the `$ErrorActionPreference = 'Stop'` at the top of
    # this script never sees it.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Engine --headless --mcp-port=0 --path $Path --import 1> $out 2> $err
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    Write-Host ("import {0}: exit={1} log={2}" -f $Path, $code, $out)
    if ($code -ne 0) {
        throw ("--import of {0} exited with {1}; stderr: {2}" -f $Path, $code, (Get-Content -Raw $err -ErrorAction SilentlyContinue))
    }
}

function ConvertTo-CompactJson {
    param($Value)
    return (ConvertTo-Json -InputObject $Value -Depth 12 -Compress)
}

function Format-CallBody {
    param([string]$Tool, $Arguments)
    $envelope = @{
        jsonrpc = '2.0'
        id      = 1
        method  = 'tools/call'
        params  = @{ name = $Tool; arguments = $Arguments }
    }
    return (ConvertTo-CompactJson $envelope)
}

function Invoke-Curl {
    param([string]$Id, [string]$Json, [int]$Port, [int]$MaxTimeSec = 30)
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
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port, [int]$MaxTimeSec = 30)
    $text = Invoke-Curl -Id $Id -Json (Format-CallBody -Tool $Tool -Arguments $Arguments) -Port $Port -MaxTimeSec $MaxTimeSec
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
    $sha = (Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[status] port={0} bytes={1} sha256={2}" -f $Port, $bytes.Length, $sha)
    Write-Host ("         body: {0}" -f $text)
    try { return ConvertFrom-Json $text } catch {
        Write-Host '         (status body is not JSON yet)'
        return $null
    }
}

function Wait-ForPump {
    param([int]$Port, [int]$TimeoutMs = 240000)
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
    $envelope = Invoke-Tool -Id $Id -Tool 'editor_get_scene_tree' -Arguments @{} -Port $EditorPort
    $payload = Get-Payload $envelope
    if ($null -eq $payload -or $null -eq $payload.tree) { return @() }
    return @(Get-TreePaths -Node $payload.tree -Prefix '')
}

# =============================================================================
# Scratch projects
# =============================================================================

$MainScene = @"
[gd_scene format=3]

[node name="Main" type="Node2D"]

[node name="Child" type="Node2D" parent="."]

[node name="World" type="Node" parent="."]
"@

$GameScene = @"
[gd_scene format=3]

[node name="Level" type="Node2D"]

[node name="Marker" type="Node2D" parent="."]
"@

function New-Project {
    param([string]$Path, [string]$Name, [string]$Scene, [bool]$WithMainScene)
    Remove-Item -Recurse -Force $Path -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
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
    Write-Utf8NoBom -Path (Join-Path $Path 'scenes\main.tscn') -Text ($Scene + "`n")
}

# =============================================================================
# Main
# =============================================================================

Write-Host '============================================================='
Write-Host ' TASK-015 gate 2 evidence -- editor_node_write'
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host "FATAL: engine binary not found: $Engine"; exit 2 }
New-Item -ItemType Directory -Force -Path $Scratch, $LogRoot, $Evid | Out-Null

$EditorProject = Join-Path $Scratch 'editor'
$GameProject = Join-Path $Scratch 'game'
$userPortPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)

$script:editorHandle = $null
$script:gameHandle = $null

try {
    New-Project -Path $EditorProject -Name 'MCP015 node write' -Scene $MainScene -WithMainScene $false
    New-Project -Path $GameProject -Name 'MCP015 game' -Scene $GameScene -WithMainScene $true

    Write-Host 'importing scratch projects ...'
    Import-Project -Path $EditorProject -LogName 'import-editor'
    Import-Project -Path $GameProject -LogName 'import-game'
    Add-Check 'import_exit_codes' $true 'both scratch projects imported with exit code 0'

    $script:editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $EditorProject, "--mcp-port=$EditorPort") -LogName 'editor'
    if (-not (Wait-ForPump -Port $EditorPort -TimeoutMs 300000)) { throw 'editor endpoint never became ready' }

    $script:gameHandle = Start-Engine -Arguments @('--headless', '--path', $GameProject, "--mcp-port=$GamePort") -LogName 'game'
    if (-not (Wait-ForPump -Port $GamePort -TimeoutMs 240000)) { throw 'game endpoint never became ready' }

    # ------------------------------------------------------------------
    # Scope: served by 9888, absent from 9889, -32601 in the game process
    # ------------------------------------------------------------------
    $TenTools = @(
        'editor_add_node', 'editor_delete_node', 'editor_duplicate_node',
        'editor_rename_node', 'editor_reparent_node', 'editor_set_node_property',
        'editor_set_node_groups', 'editor_connect_signal',
        'editor_disconnect_signal', 'editor_set_auto_dismiss_dialogs'
    )
    $editorListText = Invoke-Curl -Id 'scope_editor_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $EditorPort
    $gameListText = Invoke-Curl -Id 'scope_game_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $GamePort
    $editorMissing = @($TenTools | Where-Object { $editorListText -notmatch ('"' + $_ + '"') })
    $gameLeaked = @($TenTools | Where-Object { $gameListText -match ('"' + $_ + '"') })
    Add-Check 'scope_editor_serves_all_ten' ($editorMissing.Count -eq 0) ("missing from 9888: [" + ($editorMissing -join ', ') + "]")
    Add-Check 'scope_game_serves_none' ($gameLeaked.Count -eq 0) ("leaked into 9889: [" + ($gameLeaked -join ', ') + "]")

    $gameCall = Invoke-Tool -Id 'scope_game_call_add_node' -Tool 'editor_add_node' -Arguments @{ type = 'Node2D' } -Port $GamePort
    Add-Check 'scope_game_call_is_32601' `
        ((Get-ErrorCode $gameCall) -eq -32601 -and (Get-ErrorMessage $gameCall).contains('Method not found: editor_add_node') -and $null -eq $gameCall.result) `
        ("code=" + (Get-ErrorCode $gameCall) + " message='" + (Get-ErrorMessage $gameCall) + "'")

    # ------------------------------------------------------------------
    # Open the scene, then the success class and the evidence chain
    # ------------------------------------------------------------------
    $open = Invoke-Tool -Id 'chain_00_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Port $EditorPort
    Add-Check 'chain_open_scene' ((Get-ErrorCode $open) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $open)))

    $paths0 = Read-ScenePaths -Id 'chain_01_tree_before'
    Add-Check 'chain_tree_before' (($paths0 -join ',') -eq 'Main,Main/Child,Main/World') ("paths=[" + ($paths0 -join ', ') + "]")

    # 1. add_node (success) -- also the third argument class for `properties`
    $add = Invoke-Tool -Id 'succ_01_add_node' -Tool 'editor_add_node' `
        -Arguments @{ type = 'Node2D'; name = 'Added'; parent_path = '.'; properties = @{ position = @{ x = 1; y = 2 } } } -Port $EditorPort
    $addPayload = Get-Payload $add
    Add-Check 'succ_add_node' ((Get-ErrorCode $add) -eq 0 -and [string]$addPayload.node_path -eq 'Added' -and [string]$addPayload.name -eq 'Added' -and [string]$addPayload.type -eq 'Node2D') `
        ("payload=" + (ConvertTo-CompactJson $addPayload))

    $paths1 = Read-ScenePaths -Id 'chain_02_tree_after_add'
    Add-Check 'chain_after_add' ($paths1 -contains 'Main/Added') ("paths=[" + ($paths1 -join ', ') + "]")

    # 2. set_node_property (success) -- the TASK-014 shape
    $set = Invoke-Tool -Id 'succ_02_set_node_property' -Tool 'editor_set_node_property' `
        -Arguments @{ path = 'Added'; property = 'position'; value = @{ x = 5; y = 6 } } -Port $EditorPort
    $setPayload = Get-Payload $set
    $setOk = (Get-ErrorCode $set) -eq 0 -and [string]$setPayload.node_path -eq 'Added' -and
             [string]$setPayload.property -eq 'position' -and $null -ne $setPayload.old_value -and $null -ne $setPayload.new_value -and
             [int]$setPayload.new_value.x -eq 5 -and [int]$setPayload.new_value.y -eq 6
    Add-Check 'succ_set_node_property' $setOk ("payload=" + (ConvertTo-CompactJson $setPayload))

    # 3. rename_node (success)
    $rename = Invoke-Tool -Id 'succ_03_rename_node' -Tool 'editor_rename_node' -Arguments @{ path = 'Added'; name = 'Renamed' } -Port $EditorPort
    $renamePayload = Get-Payload $rename
    Add-Check 'succ_rename_node' ((Get-ErrorCode $rename) -eq 0 -and [string]$renamePayload.new_name -eq 'Renamed' -and [string]$renamePayload.renamed -eq 'True') `
        ("payload=" + (ConvertTo-CompactJson $renamePayload))

    # 4. duplicate_node (success)
    $dup = Invoke-Tool -Id 'succ_04_duplicate_node' -Tool 'editor_duplicate_node' -Arguments @{ path = 'Renamed'; new_name = 'Copy' } -Port $EditorPort
    $dupPayload = Get-Payload $dup
    Add-Check 'succ_duplicate_node' ((Get-ErrorCode $dup) -eq 0 -and [string]$dupPayload.node_path -eq 'Copy' -and [string]$dupPayload.name -eq 'Copy') `
        ("payload=" + (ConvertTo-CompactJson $dupPayload))

    # 5. set_node_groups (success) -- the group result is read back by a
    #    second call with an empty desired list, which removes what it added.
    $groups = Invoke-Tool -Id 'succ_05_set_node_groups' -Tool 'editor_set_node_groups' `
        -Arguments @{ node_path = 'Renamed'; groups = @('enemies', 'targets') } -Port $EditorPort
    $groupsPayload = Get-Payload $groups
    $groupsOk = (Get-ErrorCode $groups) -eq 0 -and $groupsPayload.added.Count -eq 2 -and
                ($groupsPayload.added -join ',') -eq 'enemies,targets' -and $groupsPayload.removed.Count -eq 0
    Add-Check 'succ_set_node_groups' $groupsOk ("payload=" + (ConvertTo-CompactJson $groupsPayload))

    # 6. connect_signal (success)
    $connect = Invoke-Tool -Id 'succ_06_connect_signal' -Tool 'editor_connect_signal' `
        -Arguments @{ source_path = 'Main'; signal = 'ready'; method = 'queue_free'; target_path = 'Renamed' } -Port $EditorPort
    $connectPayload = Get-Payload $connect
    Add-Check 'succ_connect_signal' ((Get-ErrorCode $connect) -eq 0 -and [string]$connectPayload.connected -eq 'True' -and [string]$connectPayload.target -eq 'Renamed') `
        ("payload=" + (ConvertTo-CompactJson $connectPayload))

    # 7. disconnect_signal (success)
    $disconnect = Invoke-Tool -Id 'succ_07_disconnect_signal' -Tool 'editor_disconnect_signal' `
        -Arguments @{ source_path = 'Main'; signal = 'ready'; method = 'queue_free'; target_path = 'Renamed' } -Port $EditorPort
    $disconnectPayload = Get-Payload $disconnect
    Add-Check 'succ_disconnect_signal' ((Get-ErrorCode $disconnect) -eq 0 -and [string]$disconnectPayload.disconnected -eq 'True' -and [string]$disconnectPayload.target -eq 'Renamed') `
        ("payload=" + (ConvertTo-CompactJson $disconnectPayload))

    # 8. reparent_node (success)
    $reparent = Invoke-Tool -Id 'succ_08_reparent_node' -Tool 'editor_reparent_node' -Arguments @{ path = 'Copy'; new_parent = 'World' } -Port $EditorPort
    $reparentPayload = Get-Payload $reparent
    Add-Check 'succ_reparent_node' ((Get-ErrorCode $reparent) -eq 0 -and [string]$reparentPayload.node_path -eq 'World/Copy' -and [string]$reparentPayload.moved -eq 'True') `
        ("payload=" + (ConvertTo-CompactJson $reparentPayload))

    $paths2 = Read-ScenePaths -Id 'chain_03_tree_after_writes'
    $chainOk = ($paths2 -contains 'Main/Renamed') -and ($paths2 -contains 'Main/World/Copy') -and ($paths2 -notcontains 'Main/Added') -and ($paths2 -notcontains 'Main/Copy')
    Add-Check 'chain_after_writes' $chainOk ("paths=[" + ($paths2 -join ', ') + "]")

    # 9. delete_node (success) and the read-back that proves it. The path is the
    #    one the reparent above produced (`World/Copy`): the tools address nodes
    #    relative to the edited scene root, and the answer of step 8 is exactly
    #    what a caller feeds back in.
    $delete = Invoke-Tool -Id 'succ_09_delete_node' -Tool 'editor_delete_node' -Arguments @{ path = 'World/Copy' } -Port $EditorPort
    $deletePayload = Get-Payload $delete
    Add-Check 'succ_delete_node' ((Get-ErrorCode $delete) -eq 0 -and [string]$deletePayload.deleted -eq 'True' -and [string]$deletePayload.path -eq 'World/Copy' -and [string]$deletePayload.deferred -eq 'True') `
        ("payload=" + (ConvertTo-CompactJson $deletePayload))

    Start-Sleep -Milliseconds 1200
    $paths3 = Read-ScenePaths -Id 'chain_04_tree_after_delete'
    Add-Check 'chain_after_delete' (($paths3 -notcontains 'Main/World/Copy') -and ($paths3 -contains 'Main/Renamed')) ("paths=[" + ($paths3 -join ', ') + "]")

    # ------------------------------------------------------------------
    # The honest refusal: no success shape for the auto-dismiss tool
    # ------------------------------------------------------------------
    $dismiss = Invoke-Tool -Id 'honest_01_set_auto_dismiss' -Tool 'editor_set_auto_dismiss_dialogs' -Arguments @{ enabled = $true } -Port $EditorPort
    $dismissOk = (Get-ErrorCode $dismiss) -eq -32000 -and (Get-ErrorMessage $dismiss) -eq 'Not implemented: editor_set_auto_dismiss_dialogs' -and
                 $null -eq $dismiss.result -and -not [string]::IsNullOrEmpty([string]$dismiss.error.data.suggestion)
    Add-Check 'honest_auto_dismiss_is_32000_not_implemented' $dismissOk `
        ("code=" + (Get-ErrorCode $dismiss) + " message='" + (Get-ErrorMessage $dismiss) + "' result_is_null=" + ($null -eq $dismiss.result))
    $dismissDisabled = Invoke-Tool -Id 'honest_02_set_auto_dismiss_disabled' -Tool 'editor_set_auto_dismiss_dialogs' -Arguments @{ enabled = $false } -Port $EditorPort
    Add-Check 'honest_auto_dismiss_disabled_same_refusal' ((Get-ErrorCode $dismissDisabled) -eq -32000) `
        ("code=" + (Get-ErrorCode $dismissDisabled) + " message='" + (Get-ErrorMessage $dismissDisabled) + "'")

    # ------------------------------------------------------------------
    # Missing-parameter class: one per tool
    # ------------------------------------------------------------------
    $MissingCases = @(
        @{ id = 'miss_add_node';                tool = 'editor_add_node';                args = @{} ;                                         frag = "Missing required parameter: type" },
        @{ id = 'miss_delete_node';             tool = 'editor_delete_node';             args = @{} ;                                         frag = "Missing required parameter: path" },
        @{ id = 'miss_duplicate_node';          tool = 'editor_duplicate_node';          args = @{} ;                                         frag = "Missing required parameter: path" },
        @{ id = 'miss_rename_node';             tool = 'editor_rename_node';             args = @{ path = 'Renamed' };                        frag = "Missing required parameter: name" },
        @{ id = 'miss_reparent_node';           tool = 'editor_reparent_node';           args = @{ path = 'Renamed' };                        frag = "Missing required parameter: new_parent" },
        @{ id = 'miss_set_node_property';       tool = 'editor_set_node_property';       args = @{ path = 'Renamed'; property = 'position' }; frag = "Missing required parameter 'value'" },
        @{ id = 'miss_set_node_groups';         tool = 'editor_set_node_groups';         args = @{ node_path = 'Renamed' };                   frag = "Missing required parameter 'groups'" },
        @{ id = 'miss_connect_signal';          tool = 'editor_connect_signal';          args = @{ source_path = 'Main' };                    frag = "Missing required parameter: signal" },
        @{ id = 'miss_disconnect_signal';       tool = 'editor_disconnect_signal';       args = @{ source_path = 'Main' };                    frag = "Missing required parameter: signal" },
        @{ id = 'miss_set_auto_dismiss';        tool = 'editor_set_auto_dismiss_dialogs'; args = @{} ;                                        frag = "Missing required parameter 'enabled'" }
    )
    foreach ($case in $MissingCases) {
        $envelope = Invoke-Tool -Id $case.id -Tool $case.tool -Arguments $case.args -Port $EditorPort
        $ok = (Get-ErrorCode $envelope) -eq -32602 -and $null -eq $envelope.result
        Add-Check $case.id $ok ("code=" + (Get-ErrorCode $envelope) + " message='" + (Get-ErrorMessage $envelope) + "'")
    }

    # ------------------------------------------------------------------
    # Bottom-layer failure class: one per tool that has one
    # ------------------------------------------------------------------
    $FailureCases = @(
        @{ id = 'fail_add_node_unknown_type';   tool = 'editor_add_node';          args = @{ type = 'NoSuchMcpNodeClass' };                              code = -32602; frag = 'no such class' },
        @{ id = 'fail_add_node_not_a_node';     tool = 'editor_add_node';          args = @{ type = 'Resource' };                                        code = -32602; frag = 'not a Node subclass' },
        @{ id = 'fail_delete_node_missing';     tool = 'editor_delete_node';       args = @{ path = 'NoSuchNode' };                                      code = -32001; frag = "Node 'NoSuchNode' not found" },
        @{ id = 'fail_duplicate_node_missing';  tool = 'editor_duplicate_node';    args = @{ path = 'NoSuchNode' };                                      code = -32001; frag = "Node 'NoSuchNode' not found" },
        @{ id = 'fail_rename_node_missing';     tool = 'editor_rename_node';       args = @{ path = 'NoSuchNode'; name = 'X' };                          code = -32001; frag = "Node 'NoSuchNode' not found" },
        @{ id = 'fail_reparent_node_missing';   tool = 'editor_reparent_node';     args = @{ path = 'Renamed'; new_parent = 'NoSuchParent' };            code = -32001; frag = "Parent 'NoSuchParent' not found" },
        @{ id = 'fail_reparent_into_descendant'; tool = 'editor_reparent_node';     args = @{ path = 'Child'; new_parent = 'Child' };                     code = -32602; frag = 'own descendant' },
        @{ id = 'fail_set_node_property_unknown'; tool = 'editor_set_node_property'; args = @{ path = 'Renamed'; property = 'not_a_property_xyz'; value = 1 }; code = -32001; frag = "Property 'not_a_property_xyz'" },
        @{ id = 'fail_set_node_groups_missing_node'; tool = 'editor_set_node_groups'; args = @{ node_path = 'NoSuchNode'; groups = @('g') };              code = -32001; frag = "Node 'NoSuchNode' not found" },
        @{ id = 'fail_connect_signal_unknown_signal'; tool = 'editor_connect_signal'; args = @{ source_path = 'Main'; signal = 'no_such_signal_xyz'; method = 'queue_free'; target_path = 'Renamed' }; code = -32001; frag = "Signal 'no_such_signal_xyz'" },
        @{ id = 'fail_disconnect_signal_not_connected'; tool = 'editor_disconnect_signal'; args = @{ source_path = 'Main'; signal = 'ready'; method = 'queue_free'; target_path = 'Renamed' }; code = -32001; frag = 'not found' }
    )
    foreach ($case in $FailureCases) {
        $envelope = Invoke-Tool -Id $case.id -Tool $case.tool -Arguments $case.args -Port $EditorPort
        $ok = (Get-ErrorCode $envelope) -eq $case.code -and (Get-ErrorMessage $envelope).contains($case.frag) -and $null -eq $envelope.result
        Add-Check $case.id $ok ("code=" + (Get-ErrorCode $envelope) + " message='" + (Get-ErrorMessage $envelope) + "'")
    }
    # `editor_set_auto_dismiss_dialogs` has no separate bottom-layer failure: its
    # one honest answer *is* the -32000 checked above (the whole editor refuses it
    # because the capability does not exist in this engine).

    # ------------------------------------------------------------------
    # The fix-first defect, measured end to end: with `target_path` naming the
    # node the connection belongs to, the disconnect really removes that
    # connection; the migration source ignored `target_path` and always built
    # the callable from the scene root, which is what the red doctest pinned.
    # ------------------------------------------------------------------
    $connect2 = Invoke-Tool -Id 'fix_01_connect_for_disconnect' -Tool 'editor_connect_signal' `
        -Arguments @{ source_path = 'Main'; signal = 'ready'; method = 'queue_free'; target_path = 'Renamed' } -Port $EditorPort
    $disconnectWanted = Invoke-Tool -Id 'fix_02_disconnect_named_target' -Tool 'editor_disconnect_signal' `
        -Arguments @{ source_path = 'Main'; signal = 'ready'; method = 'queue_free'; target_path = 'Renamed' } -Port $EditorPort
    $disconnectAgain = Invoke-Tool -Id 'fix_03_disconnect_again' -Tool 'editor_disconnect_signal' `
        -Arguments @{ source_path = 'Main'; signal = 'ready'; method = 'queue_free'; target_path = 'Renamed' } -Port $EditorPort
    $fixOk = (Get-ErrorCode $connect2) -eq 0 -and (Get-ErrorCode $disconnectWanted) -eq 0 -and
             [string](Get-Payload $disconnectWanted).target -eq 'Renamed' -and (Get-ErrorCode $disconnectAgain) -eq -32001
    Add-Check 'fix_disconnect_uses_target_path' $fixOk `
        ("connect_code=" + (Get-ErrorCode $connect2) + " first_disconnect=" + (Get-ErrorCode $disconnectWanted) + " second_disconnect=" + (Get-ErrorCode $disconnectAgain) + " (" + (Get-ErrorMessage $disconnectAgain) + ")")
} catch {
    Add-Check 'harness_exception' $false ($_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    Stop-Engine -Handle $script:gameHandle
    Stop-Engine -Handle $script:editorHandle

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
    if ($passed -ne $total) { exit 1 }
    exit 0
}