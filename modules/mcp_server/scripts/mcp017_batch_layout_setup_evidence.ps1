# =============================================================================
#  mcp017_batch_layout_setup_evidence.ps1 -- TASK-017 gate 2 evidence
#
#  The live evidence for the three B3 groups this task ports (ten tools, all
#  channel=editor / scope=editor / mutating=true):
#
#    editor_node_batch_write         editor_add_nodes_batch,
#                                   editor_set_node_property_batch
#    editor_control_layout_write     editor_set_anchor_preset
#    editor_node_setup               editor_setup_camera_3d,
#                                   editor_setup_collision_shape,
#                                   editor_setup_world_environment,
#                                   editor_setup_lighting,
#                                   editor_setup_navigation_agent,
#                                   editor_setup_navigation_region,
#                                   editor_setup_physics_body
#
#  It covers, in one run:
#
#    Scope       the ten tools are served by the editor endpoint 9888, absent
#                from the game endpoint 9889, and a direct call on 9889 is
#                -32601 with `result` null (never execution).
#    Success     for every tool that has one, with its real response.
#    Missing arg one missing-required-parameter request per tool that *has* a
#                required parameter (-32602). A tool whose contract has no
#                required parameter is declared explicitly instead.
#    Bottom      one bottom-layer failure per tool that has one (-32001 for a
#                missing node/parent, -32602 for an illegal shape/light/body/
#                agent/mode/preset name, -32000 for a parent that cannot accept
#                the child).
#    Batch       the deliberate middle-element counter-example for
#                `editor_add_nodes_batch` (two variants), the read-back proof
#                that no partial node stayed in the scene, and one good
#                three-element batch that really creates all three.
#    Prop batch  the all-or-nothing counter-example for
#                `editor_set_node_property_batch` (a property missing on one
#                matched node) plus the read-back proof that no member changed.
#    Setup chain the seven `editor_setup_*` read-back chain: each call is
#                followed by an independent read-family tool
#                (`editor_get_node_properties`, `editor_find_nodes_by_type`,
#                `editor_save_scene` + `project_read_scene_file_content`), and
#                the class/name/property values are asserted from that read.
#    Cross tool  one end-to-end chain per group with a state-change read
#                (batch-add a Control -> anchor preset -> read anchors back;
#                batch-add bodies -> collision shape -> read the shapes back).
#    Text        the TASK-017 section 3 `not_found` message on the wire (one
#                " not found" suffix) and, on the real transitive caller
#                (`editor_add_nodes_batch`'s property refusal, whose message
#                `_transaction_fail` forwards into `not_found` a second time),
#                the exact batch message with exactly one " not found".
#
#  Discipline (PLAYBOOK section 3 and section 7.1):
#    * every response body is written with `curl.exe -s -o <file>` and its
#      sha256 is printed from the bytes on disk (nothing through a pipe);
#    * every request body is built with `ConvertTo-Json` and sent with
#      `curl.exe --data-binary @file`;
#    * ports 9888 (editor) / 9889 (game) only; the user's 9877 is never touched
#      and its listener pid is asserted unchanged;
#    * the scratch `.tscn` / `.tres` are written **without a BOM** and the
#      `--import` exit code is checked.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp017_batch_layout_setup_evidence.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877
$Scratch = Join-Path $env:TEMP 'mcp017-scratch'
$LogRoot = Join-Path $env:TEMP 'mcp017-logs'
$Evid = Join-Path $env:TEMP 'mcp017-evidence'

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
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
            & $Engine --headless --mcp-port=0 --path $Path --import 1> $out 2> $err
            $code = $LASTEXITCODE
            Write-Host ("import {0}: attempt={1} exit={2} log={3}" -f $Path, $attempt, $code, $out)
            if ($code -eq 0) { return $attempt }
            Write-Host ("attempt {0} failed with {1}" -f $attempt, $code)
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

function Read-ResponseText {
    param([string]$Id)
    $file = Join-Path $Evid ("{0}.response.json" -f $Id)
    if (-not (Test-Path $file)) { return '' }
    return [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($file))
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

# Every root-relative node path `editor_find_nodes_by_type` reports for `type`.
function Get-TypePaths {
    param([string]$Id, [string]$Type)
    $envelope = Invoke-Tool -Id $Id -Tool 'editor_find_nodes_by_type' -Arguments @{ type = $Type }
    $payload = Get-Payload $envelope
    if ($null -eq $payload -or $null -eq $payload.nodes) { return @() }
    return @(@($payload.nodes) | ForEach-Object { [string]$_.path })
}

# The `type`/`value` of a node's property as `editor_get_node_properties`
# reports it. A `null` answer means the property was not in the response.
function Get-NodeProperty {
    param([string]$Id, [string]$Path, [string]$Property)
    $envelope = Invoke-Tool -Id $Id -Tool 'editor_get_node_properties' -Arguments @{ path = $Path; properties = @($Property) }
    $payload = Get-Payload $envelope
    if ($null -eq $payload -or $null -eq $payload.properties) { return $null }
    return $payload.properties.$Property
}

# =============================================================================
# Scratch project
# =============================================================================

$EditorScene = @"
[gd_scene format=3]

[node name="Main" type="Node2D"]

[node name="A" type="Node2D" parent="."]

[node name="B" type="Node2D" parent="."]

[node name="Ui" type="Control" parent="."]

[node name="World3D" type="Node3D" parent="."]

[node name="Plain" type="Node" parent="."]
"@

$GameScene = @"
[gd_scene format=3]

[node name="Main" type="Node"]
"@

function New-Project {
    param([string]$Path, [string]$Name, [string]$SceneText, [bool]$WithMainScene)
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
    Write-Utf8NoBom -Path (Join-Path $Path 'scenes\main.tscn') -Text ($SceneText + "`n")
}

# =============================================================================
# Main
# =============================================================================

Write-Host '============================================================='
Write-Host ' TASK-017 gate 2 evidence -- batch write + control layout + setup family'
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host "FATAL: engine binary not found: $Engine"; exit 2 }
New-Item -ItemType Directory -Force -Path $Scratch, $LogRoot, $Evid | Out-Null

$EditorProject = Join-Path $Scratch 'editor'
$GameProject = Join-Path $Scratch 'game'
$userPortPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)
Write-Host ("engine --version: {0}" -f (& $Engine --version))

$TenTools = @(
    'editor_add_nodes_batch', 'editor_set_node_property_batch',
    'editor_set_anchor_preset',
    'editor_setup_camera_3d', 'editor_setup_collision_shape',
    'editor_setup_world_environment', 'editor_setup_lighting',
    'editor_setup_navigation_agent', 'editor_setup_navigation_region',
    'editor_setup_physics_body'
)

try {
    New-Project -Path $EditorProject -Name 'MCP017 batch layout setup' -SceneText $EditorScene -WithMainScene $false
    New-Project -Path $GameProject -Name 'MCP017 game' -SceneText $GameScene -WithMainScene $true

    Write-Host 'importing scratch projects ...'
    $a1 = Import-Project -Path $EditorProject -LogName 'import-editor'
    $a2 = Import-Project -Path $GameProject -LogName 'import-game'
    Add-Check 'import_exit_codes' $true ("both scratch projects imported with exit code 0 (attempts: {0} / {1})" -f $a1, $a2)

    $script:EditorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $EditorProject, "--mcp-port=$EditorPort") -LogName 'editor'
    if (-not (Wait-ForPump -Port $EditorPort -TimeoutMs 300000)) { throw 'editor endpoint never became ready' }

    $script:GameHandle = Start-Engine -Arguments @('--headless', '--path', $GameProject, "--mcp-port=$GamePort") -LogName 'game'
    if (-not (Wait-ForPump -Port $GamePort -TimeoutMs 240000)) { throw 'game endpoint never became ready' }

    # ------------------------------------------------------------------
    # Scope: served by 9888, absent from 9889, -32601 in the game process
    # ------------------------------------------------------------------
    $editorListText = Invoke-Curl -Id 'scope_editor_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $EditorPort
    $gameListText = Invoke-Curl -Id 'scope_game_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $GamePort
    $editorMissing = @($TenTools | Where-Object { $editorListText -notmatch ('"' + $_ + '"') })
    $gameLeaked = @($TenTools | Where-Object { $gameListText -match ('"' + $_ + '"') })
    Add-Check 'scope_editor_serves_all_ten' ($editorMissing.Count -eq 0) ("missing from 9888: [" + ($editorMissing -join ', ') + "]")
    Add-Check 'scope_game_serves_none' ($gameLeaked.Count -eq 0) ("leaked into 9889: [" + ($gameLeaked -join ', ') + "]")

    $GameArgs = @{
        'editor_add_nodes_batch'           = @{ nodes = @(@{ type = 'Node2D' }) }
        'editor_set_node_property_batch'   = @{ node_type = 'Node2D'; property = 'position'; value = @{ x = 1; y = 1 } }
        'editor_set_anchor_preset'         = @{ node_path = '.'; preset = 'center' }
        'editor_setup_camera_3d'           = @{ node_path = '.' }
        'editor_setup_collision_shape'     = @{ node_path = '.' }
        'editor_setup_world_environment'   = @{}
        'editor_setup_lighting'            = @{}
        'editor_setup_navigation_agent'    = @{ node_path = '.' }
        'editor_setup_navigation_region'   = @{ node_path = '.' }
        'editor_setup_physics_body'        = @{}
    }
    foreach ($tool in $TenTools) {
        $envelope = Invoke-Tool -Id ("scope_game_call_" + $tool) -Tool $tool -Arguments $GameArgs[$tool] -Port $GamePort
        $ok = (Get-ErrorCode $envelope) -eq -32601 -and (Get-ErrorMessage $envelope).contains("Method not found: $tool") -and $null -eq $envelope.result
        Add-Check ("scope_game_call_is_32601_" + $tool) $ok ("code=" + (Get-ErrorCode $envelope) + " message='" + (Get-ErrorMessage $envelope) + "'")
    }

    # ------------------------------------------------------------------
    # Open the scene
    # ------------------------------------------------------------------
    $open = Invoke-Tool -Id 'chain_00_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Add-Check 'chain_open_scene' ((Get-ErrorCode $open) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $open)))

    # ------------------------------------------------------------------
    # editor_add_nodes_batch: success, missing arg, counter-examples
    # ------------------------------------------------------------------
    $good = Invoke-Tool -Id 'batch_01_good' -Tool 'editor_add_nodes_batch' -Arguments @{
        nodes = @(
            @{ type = 'Node2D'; name = 'Ok1' },
            @{ type = 'Node2D'; name = 'Ok2'; parent_path = 'World3D' },
            @{ type = 'Node2D'; name = 'Ok3' }
        )
    }
    $goodPayload = Get-Payload $good
    $goodOk = (Get-ErrorCode $good) -eq 0 -and [string]$goodPayload.status -eq 'ok' -and [int]$goodPayload.count -eq 3
    Add-Check 'batch_good_three_creates_all' $goodOk ("payload=" + (ConvertTo-CompactJson $goodPayload) + " sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'batch_01_good.response.json')).Hash.ToLower())
    $pathsAfterGood = Get-TypePaths -Id 'batch_02_read_after_good' -Type 'Node2D'
    Add-Check 'batch_good_read_back' (($pathsAfterGood -contains 'Ok1') -and ($pathsAfterGood -contains 'World3D/Ok2') -and ($pathsAfterGood -contains 'Ok3')) ("Node2D paths=" + ($pathsAfterGood -join ', '))

    $missingBatch = Invoke-Tool -Id 'batch_03_missing_arg' -Tool 'editor_add_nodes_batch' -Arguments @{}
    Add-Check 'batch_missing_nodes_is_32602' ((Get-ErrorCode $missingBatch) -eq -32602) ("code=" + (Get-ErrorCode $missingBatch) + " message='" + (Get-ErrorMessage $missingBatch) + "'")

    # Counter-example A: an unknown type in the middle.
    $badType = Invoke-Tool -Id 'batch_04_bad_middle_type' -Tool 'editor_add_nodes_batch' -Arguments @{
        nodes = @(
            @{ type = 'Node2D'; name = 'BadA1' },
            @{ type = 'NoSuchTypeXYZ' },
            @{ type = 'Node2D'; name = 'BadA3' }
        )
    }
    $badTypeOk = (Get-ErrorCode $badType) -eq -32602 -and $null -eq $badType.result -and (Get-ErrorMessage $badType).contains('nodes[1]')
    Add-Check 'batch_bad_middle_type_is_32602' $badTypeOk ("code=" + (Get-ErrorCode $badType) + " result=" + ($null -eq $badType.result) + " message='" + (Get-ErrorMessage $badType) + "' sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'batch_04_bad_middle_type.response.json')).Hash.ToLower())

    # Counter-example B: a missing parent in the middle (the mandated one).
    $badParent = Invoke-Tool -Id 'batch_05_bad_middle_parent' -Tool 'editor_add_nodes_batch' -Arguments @{
        nodes = @(
            @{ type = 'Node2D'; name = 'BadB1' },
            @{ type = 'Node2D'; name = 'BadB2'; parent_path = 'NoSuchParentXYZ' },
            @{ type = 'Node2D'; name = 'BadB3' }
        )
    }
    $badParentOk = (Get-ErrorCode $badParent) -eq -32001 -and $null -eq $badParent.result -and (Get-ErrorMessage $badParent).contains('nodes[1]')
    Add-Check 'batch_bad_middle_parent_is_32001' $badParentOk ("code=" + (Get-ErrorCode $badParent) + " result=" + ($null -eq $badParent.result) + " message='" + (Get-ErrorMessage $badParent) + "' sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'batch_05_bad_middle_parent.response.json')).Hash.ToLower())

    # The rollback envelope is attached to `error.data.batch`.
    $badParentRaw = Read-ResponseText -Id 'batch_05_bad_middle_parent'
    $envelopeOk = $badParentRaw.Contains('"status":"rolled_back"') -and $badParentRaw.Contains('"on_error":"all_or_nothing"') -and $badParentRaw.Contains('"rolled_back"') -and $badParentRaw.Contains('"BadB1"')
    Add-Check 'batch_rollback_envelope_on_the_wire' $envelopeOk ("contains status=rolled_back / on_error=all_or_nothing / rolled_back entry for BadB1: " + $envelopeOk)

    # No partial node stayed in the scene: the read family must not see any of
    # the six names the two refused batches asked for, and `BadB1` in particular
    # (the element that prepared successfully before the failure).
    $pathsAfterBad = Get-TypePaths -Id 'batch_06_read_after_bad' -Type 'Node2D'
    $leftovers = @('BadA1', 'BadA3', 'BadB1', 'BadB2', 'BadB3') | Where-Object { $pathsAfterBad -contains $_ }
    Add-Check 'batch_bad_leaves_no_partial_node' ($leftovers.Count -eq 0) ("Node2D paths after the two refused batches=" + ($pathsAfterBad -join ', ') + " leftovers=[" + ($leftovers -join ', ') + "]")

    # ------------------------------------------------------------------
    # editor_set_node_property_batch: success, no-match, all-or-nothing
    # ------------------------------------------------------------------
    # Put the Node2D nodes at a known position first.
    $seedPosition = Invoke-Tool -Id 'prop_01_seed_position' -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Node2D'; property = 'position'; value = @{ x = 3; y = 4 } }
    $seedPayload = Get-Payload $seedPosition
    Add-Check 'prop_success_writes_all' ((Get-ErrorCode $seedPosition) -eq 0 -and [int]$seedPayload.updated -ge 4 -and [string]$seedPayload.status -eq 'ok') ("payload=" + (ConvertTo-CompactJson $seedPayload) + " sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'prop_01_seed_position.response.json')).Hash.ToLower())

    $seedRead = Invoke-Tool -Id 'prop_02_read_position' -Tool 'editor_get_node_properties' -Arguments @{ path = 'A'; properties = @('position') }
    $seedPositionPayload = Get-Payload $seedRead
    Add-Check 'prop_success_read_back' ($null -ne $seedPositionPayload -and [double]$seedPositionPayload.properties.position.x -eq 3 -and [double]$seedPositionPayload.properties.position.y -eq 4) ("A.position=" + (ConvertTo-CompactJson $seedPositionPayload.properties))

    $propMissing = Invoke-Tool -Id 'prop_03_missing_arg' -Tool 'editor_set_node_property_batch' -Arguments @{}
    Add-Check 'prop_missing_node_type_is_32602' ((Get-ErrorCode $propMissing) -eq -32602) ("code=" + (Get-ErrorCode $propMissing) + " message='" + (Get-ErrorMessage $propMissing) + "'")

    $propNoMatch = Invoke-Tool -Id 'prop_04_no_match' -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Sprite2D'; property = 'position'; value = @{ x = 9; y = 9 } }
    Add-Check 'prop_no_match_is_32001' ((Get-ErrorCode $propNoMatch) -eq -32001 -and $null -eq $propNoMatch.result) ("code=" + (Get-ErrorCode $propNoMatch) + " result=" + ($null -eq $propNoMatch.result) + " message='" + (Get-ErrorMessage $propNoMatch) + "' sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'prop_04_no_match.response.json')).Hash.ToLower())

    # The all-or-nothing counter-example: `texture` exists on Sprite2D but not on
    # the Node2D nodes that `node_type = Node2D` also matches. Refused before any
    # write, and the positions stay exactly what `prop_01` wrote.
    # A Sprite2D is added first so the matched set really has a node that has the
    # property as well as nodes that do not.
    $addSprite = Invoke-Tool -Id 'prop_05_add_sprite' -Tool 'editor_add_node' -Arguments @{ type = 'Sprite2D'; name = 'Spr' }
    Add-Check 'prop_setup_add_sprite' ((Get-ErrorCode $addSprite) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $addSprite)))

    $propPartial = Invoke-Tool -Id 'prop_06_partial_property' -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Node2D'; property = 'texture'; value = $null }
    $propPartialOk = (Get-ErrorCode $propPartial) -eq -32001 -and $null -eq $propPartial.result -and (Get-ErrorMessage $propPartial).contains('texture')
    Add-Check 'prop_all_or_nothing_is_32001' $propPartialOk ("code=" + (Get-ErrorCode $propPartial) + " result=" + ($null -eq $propPartial.result) + " message='" + (Get-ErrorMessage $propPartial) + "' sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'prop_06_partial_property.response.json')).Hash.ToLower())

    $afterPartial = Invoke-Tool -Id 'prop_07_read_after_partial' -Tool 'editor_get_node_properties' -Arguments @{ path = 'A'; properties = @('position') }
    $afterPartialPayload = Get-Payload $afterPartial
    $unchanged = ($null -ne $afterPartialPayload) -and ([double]$afterPartialPayload.properties.position.x -eq 3) -and ([double]$afterPartialPayload.properties.position.y -eq 4)
    Add-Check 'prop_all_or_nothing_leaves_no_change' $unchanged ("A.position after the refused call=" + (ConvertTo-CompactJson $afterPartialPayload.properties))

    # ------------------------------------------------------------------
    # editor_set_anchor_preset
    # ------------------------------------------------------------------
    $anchor = Invoke-Tool -Id 'anchor_01_success' -Tool 'editor_set_anchor_preset' -Arguments @{ node_path = 'Ui'; preset = 'center' }
    $anchorPayload = Get-Payload $anchor
    Add-Check 'anchor_success' ((Get-ErrorCode $anchor) -eq 0 -and [string]$anchorPayload.preset -eq 'center' -and [string]$anchorPayload.node_path -eq 'Ui') ("payload=" + (ConvertTo-CompactJson $anchorPayload) + " sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'anchor_01_success.response.json')).Hash.ToLower())

    $anchorRead = Invoke-Tool -Id 'anchor_02_read_back' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Ui'; properties = @('anchor_left', 'anchor_top', 'anchor_right', 'anchor_bottom') }
    $anchorReadPayload = Get-Payload $anchorRead
    $anchorsOk = ($null -ne $anchorReadPayload) -and ([double]$anchorReadPayload.properties.anchor_left -eq 0.5) -and ([double]$anchorReadPayload.properties.anchor_top -eq 0.5) -and ([double]$anchorReadPayload.properties.anchor_right -eq 0.5) -and ([double]$anchorReadPayload.properties.anchor_bottom -eq 0.5)
    Add-Check 'anchor_read_back_via_get_node_properties' $anchorsOk ("Ui anchors=" + (ConvertTo-CompactJson $anchorReadPayload.properties))

    $anchorMissing = Invoke-Tool -Id 'anchor_03_missing_arg' -Tool 'editor_set_anchor_preset' -Arguments @{}
    Add-Check 'anchor_missing_node_path_is_32602' ((Get-ErrorCode $anchorMissing) -eq -32602) ("code=" + (Get-ErrorCode $anchorMissing) + " message='" + (Get-ErrorMessage $anchorMissing) + "'")

    $anchorIllegal = Invoke-Tool -Id 'anchor_04_illegal_preset' -Tool 'editor_set_anchor_preset' -Arguments @{ node_path = 'Ui'; preset = 'middle' }
    Add-Check 'anchor_illegal_preset_is_32602' ((Get-ErrorCode $anchorIllegal) -eq -32602 -and (Get-ErrorMessage $anchorIllegal).contains('top_left')) ("code=" + (Get-ErrorCode $anchorIllegal) + " message='" + (Get-ErrorMessage $anchorIllegal) + "'")

    $anchorNotControl = Invoke-Tool -Id 'anchor_05_not_control' -Tool 'editor_set_anchor_preset' -Arguments @{ node_path = 'A'; preset = 'center' }
    Add-Check 'anchor_not_control_is_32602' ((Get-ErrorCode $anchorNotControl) -eq -32602 -and (Get-ErrorMessage $anchorNotControl).contains('Control')) ("code=" + (Get-ErrorCode $anchorNotControl) + " message='" + (Get-ErrorMessage $anchorNotControl) + "'")

    $anchorMissingNode = Invoke-Tool -Id 'anchor_06_missing_node' -Tool 'editor_set_anchor_preset' -Arguments @{ node_path = 'NoSuchNodeXYZ'; preset = 'center' }
    Add-Check 'anchor_missing_node_is_32001' ((Get-ErrorCode $anchorMissingNode) -eq -32001) ("code=" + (Get-ErrorCode $anchorMissingNode) + " message='" + (Get-ErrorMessage $anchorMissingNode) + "'")

    # ------------------------------------------------------------------
    # editor_setup_camera_3d
    #
    # `node_path` names either an existing Camera3D (configure, created:false)
    # or a Node3D parent to create one under (created:true). The class of the
    # hit is the boundary - a Camera3D *is* a Node3D, so the two halves cannot
    # collide - and a hit that is neither is -32602 while a miss is -32001,
    # both before anything is allocated (the read-back after the refusals shows
    # no Camera3D was left behind). The create branch is read back by a
    # *different* tool, never by the create answer alone.
    # ------------------------------------------------------------------
    $addCamera = Invoke-Tool -Id 'setup_00_add_camera' -Tool 'editor_add_node' -Arguments @{ type = 'Camera3D'; name = 'WorldCamera'; parent_path = 'World3D' }
    Add-Check 'setup_camera_3d_setup_add_camera' ((Get-ErrorCode $addCamera) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $addCamera)))
    $camera = Invoke-Tool -Id 'setup_01_camera' -Tool 'editor_setup_camera_3d' -Arguments @{ node_path = 'World3D/WorldCamera' }
    $cameraPayload = Get-Payload $camera
    Add-Check 'setup_camera_3d_success' ((Get-ErrorCode $camera) -eq 0 -and (-not [bool]$cameraPayload.created) -and [bool]$cameraPayload.current -and [string]$cameraPayload.type -eq 'Camera3D') ("payload=" + (ConvertTo-CompactJson $cameraPayload) + " sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'setup_01_camera.response.json')).Hash.ToLower())
    $cameraPaths = Get-TypePaths -Id 'setup_02_read_camera' -Type 'Camera3D'
    $cameraProps = Get-NodeProperty -Id 'setup_03_read_camera_props' -Path 'World3D/WorldCamera' -Property 'current'
    Add-Check 'setup_camera_3d_read_back' (($cameraPaths -contains 'World3D/WorldCamera') -and ($null -ne $cameraProps) -and [bool]$cameraProps) ("find_nodes_by_type(Camera3D)=" + ($cameraPaths -join ', ') + " current=" + (ConvertTo-CompactJson $cameraProps))

    # The create branch: an existing Node3D parent gets a new Camera3D.
    $cameraCreate = Invoke-Tool -Id 'setup_03b_camera_create_under_parent' -Tool 'editor_setup_camera_3d' -Arguments @{ node_path = 'World3D' }
    $cameraCreatePayload = Get-Payload $cameraCreate
    Add-Check 'setup_camera_3d_creates_under_parent' ((Get-ErrorCode $cameraCreate) -eq 0 -and [bool]$cameraCreatePayload.created -and [bool]$cameraCreatePayload.current -and [string]$cameraCreatePayload.type -eq 'Camera3D' -and [string]$cameraCreatePayload.node_path -eq 'World3D/Camera3D') ("payload=" + (ConvertTo-CompactJson $cameraCreatePayload) + " sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'setup_03b_camera_create_under_parent.response.json')).Hash.ToLower())
    $cameraCreatePaths = Get-TypePaths -Id 'setup_03c_read_created_camera' -Type 'Camera3D'
    $cameraCreateCurrent = Get-NodeProperty -Id 'setup_03d_read_created_camera_current' -Path 'World3D/Camera3D' -Property 'current'
    Add-Check 'setup_camera_3d_create_read_back' (($cameraCreatePaths -contains 'World3D/Camera3D') -and ($null -ne $cameraCreateCurrent) -and [bool]$cameraCreateCurrent) ("find_nodes_by_type(Camera3D)=" + ($cameraCreatePaths -join ', ') + " World3D/Camera3D.current=" + (ConvertTo-CompactJson $cameraCreateCurrent))

    $cameraMissing = Invoke-Tool -Id 'setup_04_camera_missing_arg' -Tool 'editor_setup_camera_3d' -Arguments @{}
    Add-Check 'setup_camera_3d_missing_arg_is_32602' ((Get-ErrorCode $cameraMissing) -eq -32602) ("code=" + (Get-ErrorCode $cameraMissing) + " message='" + (Get-ErrorMessage $cameraMissing) + "'")
    # `A` is a Node2D: neither a Camera3D nor a Node3D, so it is refused with
    # -32602 naming the class it really is.
    $cameraNotCamera = Invoke-Tool -Id 'setup_05_camera_not_camera' -Tool 'editor_setup_camera_3d' -Arguments @{ node_path = 'A' }
    Add-Check 'setup_camera_3d_not_camera_is_32602' ((Get-ErrorCode $cameraNotCamera) -eq -32602 -and (Get-ErrorMessage $cameraNotCamera).contains('Camera3D') -and (Get-ErrorMessage $cameraNotCamera).contains('Node2D')) ("code=" + (Get-ErrorCode $cameraNotCamera) + " message='" + (Get-ErrorMessage $cameraNotCamera) + "'")
    # Non-vacuous: the two refusals above must not have left a Camera3D under
    # the refused paths (no half-built node).
    $cameraAfterRefusals = Get-TypePaths -Id 'setup_05c_read_after_camera_refusals' -Type 'Camera3D'
    $strayCameras = @($cameraAfterRefusals | Where-Object { $_ -like 'A/*' -or $_ -like 'Plain/*' })
    Add-Check 'setup_camera_3d_refusals_create_nothing' ($strayCameras.Count -eq 0) ("Camera3D paths after the refusals=" + ($cameraAfterRefusals -join ', ') + " under-refused-paths=[" + ($strayCameras -join ', ') + "]")
    # Non-vacuous -32001: the code, a null result and the exact message.
    $cameraBadParent = Invoke-Tool -Id 'setup_05b_camera_bad_parent' -Tool 'editor_setup_camera_3d' -Arguments @{ node_path = 'NoSuchParentXYZ' }
    Add-Check 'setup_camera_3d_bad_parent_is_32001' ((Get-ErrorCode $cameraBadParent) -eq -32001 -and $null -eq $cameraBadParent.result -and (Get-ErrorMessage $cameraBadParent).contains("Parent 'NoSuchParentXYZ' not found")) ("code=" + (Get-ErrorCode $cameraBadParent) + " result=" + ($null -eq $cameraBadParent.result) + " message='" + (Get-ErrorMessage $cameraBadParent) + "'")

    # ------------------------------------------------------------------
    # editor_setup_collision_shape
    # ------------------------------------------------------------------
    $collision = Invoke-Tool -Id 'setup_06_collision' -Tool 'editor_setup_collision_shape' -Arguments @{ node_path = 'A'; shape_type = 'RectangleShape2D'; shape_params = @{ size = @{ x = 32; y = 32 } } }
    $collisionPayload = Get-Payload $collision
    Add-Check 'setup_collision_shape_success' ((Get-ErrorCode $collision) -eq 0 -and [bool]$collisionPayload.shape_set -and [string]$collisionPayload.collision_node_type -eq 'CollisionShape2D') ("payload=" + (ConvertTo-CompactJson $collisionPayload) + " sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'setup_06_collision.response.json')).Hash.ToLower())
    $collisionPaths = Get-TypePaths -Id 'setup_07_read_collision' -Type 'CollisionShape2D'
    $collisionShape = Get-NodeProperty -Id 'setup_08_read_collision_shape' -Path 'A/CollisionShape2D' -Property 'shape'
    Add-Check 'setup_collision_shape_read_back' (($collisionPaths -contains 'A/CollisionShape2D') -and ($null -ne $collisionShape) -and [string]$collisionShape.type -eq 'RectangleShape2D') ("find_nodes_by_type(CollisionShape2D)=" + ($collisionPaths -join ', ') + " shape=" + (ConvertTo-CompactJson $collisionShape))
    $collisionMissing = Invoke-Tool -Id 'setup_09_collision_missing_arg' -Tool 'editor_setup_collision_shape' -Arguments @{}
    Add-Check 'setup_collision_shape_missing_arg_is_32602' ((Get-ErrorCode $collisionMissing) -eq -32602) ("code=" + (Get-ErrorCode $collisionMissing) + " message='" + (Get-ErrorMessage $collisionMissing) + "'")
    $collisionBadType = Invoke-Tool -Id 'setup_10_collision_bad_shape' -Tool 'editor_setup_collision_shape' -Arguments @{ node_path = 'A'; shape_type = 'NoSuchShape' }
    Add-Check 'setup_collision_shape_bad_type_is_32602' ((Get-ErrorCode $collisionBadType) -eq -32602 -and (Get-ErrorMessage $collisionBadType).contains('RectangleShape2D')) ("code=" + (Get-ErrorCode $collisionBadType) + " message='" + (Get-ErrorMessage $collisionBadType) + "'")
    $collisionBadNode = Invoke-Tool -Id 'setup_11_collision_bad_node' -Tool 'editor_setup_collision_shape' -Arguments @{ node_path = 'NoSuchNodeXYZ' }
    Add-Check 'setup_collision_shape_bad_node_is_32001' ((Get-ErrorCode $collisionBadNode) -eq -32001) ("code=" + (Get-ErrorCode $collisionBadNode) + " message='" + (Get-ErrorMessage $collisionBadNode) + "'")

    # ------------------------------------------------------------------
    # editor_setup_world_environment
    # ------------------------------------------------------------------
    $worldEnv = Invoke-Tool -Id 'setup_12_world_env' -Tool 'editor_setup_world_environment' -Arguments @{ bg_color = @{ r = 0.1; g = 0.2; b = 0.3 }; ambient_color = @{ r = 0.4; g = 0.5; b = 0.6 } }
    $worldEnvPayload = Get-Payload $worldEnv
    Add-Check 'setup_world_environment_success' ((Get-ErrorCode $worldEnv) -eq 0 -and [bool]$worldEnvPayload.world_environment_created -and [bool]$worldEnvPayload.environment_created) ("payload=" + (ConvertTo-CompactJson $worldEnvPayload) + " sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'setup_12_world_env.response.json')).Hash.ToLower())
    $worldEnvPaths = Get-TypePaths -Id 'setup_13_read_world_env' -Type 'WorldEnvironment'
    $environmentProp = Get-NodeProperty -Id 'setup_14_read_environment' -Path 'WorldEnvironment' -Property 'environment'
    Add-Check 'setup_world_environment_read_back' (($worldEnvPaths -contains 'WorldEnvironment') -and ($null -ne $environmentProp) -and [string]$environmentProp.type -eq 'Environment') ("find_nodes_by_type(WorldEnvironment)=" + ($worldEnvPaths -join ', ') + " environment=" + (ConvertTo-CompactJson $environmentProp))

    # The Environment *resource* is read back through the saved scene, which is a
    # different read family (`editor_save_scene` + project_read_scene_file_content)
    # and shows the exact values the direct C++ calls wrote.
    $save = Invoke-Tool -Id 'setup_15_save_scene' -Tool 'editor_save_scene' -Arguments @{}
    Add-Check 'setup_save_scene' ((Get-ErrorCode $save) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $save)))
    $sceneText = Invoke-Tool -Id 'setup_16_read_scene_file' -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://scenes/main.tscn' }
    $scenePayload = Get-Payload $sceneText
    $sceneRaw = Read-ResponseText -Id 'setup_16_read_scene_file'
    $envTextOk = ($sceneRaw.Contains('background_color = Color(0.1, 0.2, 0.3, 1)')) -and ($sceneRaw.Contains('ambient_light_color = Color(0.4, 0.5, 0.6, 1)')) -and ($sceneRaw.Contains('ambient_light_source = 2'))
    Add-Check 'setup_world_environment_resource_read_back' $envTextOk ("saved main.tscn contains background_color=Color(0.1, 0.2, 0.3, 1) / ambient_light_color=Color(0.4, 0.5, 0.6, 1) / ambient_light_source=2: " + $envTextOk)

    $worldEnvBadColor = Invoke-Tool -Id 'setup_17_world_env_bad_color' -Tool 'editor_setup_world_environment' -Arguments @{ bg_color = 'not-an-object' }
    Add-Check 'setup_world_environment_bad_color_is_32602' ((Get-ErrorCode $worldEnvBadColor) -eq -32602 -and (Get-ErrorMessage $worldEnvBadColor).contains('bg_color')) ("code=" + (Get-ErrorCode $worldEnvBadColor) + " message='" + (Get-ErrorMessage $worldEnvBadColor) + "'")
    $worldEnvWrongType = Invoke-Tool -Id 'setup_18_world_env_wrong_type' -Tool 'editor_setup_world_environment' -Arguments @{ world_env_path = 'A' }
    Add-Check 'setup_world_environment_wrong_node_type_is_32602' ((Get-ErrorCode $worldEnvWrongType) -eq -32602 -and (Get-ErrorMessage $worldEnvWrongType).contains('WorldEnvironment')) ("code=" + (Get-ErrorCode $worldEnvWrongType) + " message='" + (Get-ErrorMessage $worldEnvWrongType) + "'")

    # ------------------------------------------------------------------
    # editor_setup_lighting
    # ------------------------------------------------------------------
    $lighting = Invoke-Tool -Id 'setup_19_lighting' -Tool 'editor_setup_lighting' -Arguments @{ parent_path = '.'; light_type = 'directional' }
    $lightingPayload = Get-Payload $lighting
    Add-Check 'setup_lighting_success' ((Get-ErrorCode $lighting) -eq 0 -and [string]$lightingPayload.type -eq 'DirectionalLight3D') ("payload=" + (ConvertTo-CompactJson $lightingPayload) + " sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'setup_19_lighting.response.json')).Hash.ToLower())
    $lightingPaths = Get-TypePaths -Id 'setup_20_read_lighting' -Type 'DirectionalLight3D'
    Add-Check 'setup_lighting_read_back' ($lightingPaths -contains 'DirectionalLight3D') ("find_nodes_by_type(DirectionalLight3D)=" + ($lightingPaths -join ', '))
    $lightingBad = Invoke-Tool -Id 'setup_21_lighting_bad_type' -Tool 'editor_setup_lighting' -Arguments @{ light_type = 'banana' }
    Add-Check 'setup_lighting_bad_type_is_32602' ((Get-ErrorCode $lightingBad) -eq -32602 -and (Get-ErrorMessage $lightingBad).contains('directional')) ("code=" + (Get-ErrorCode $lightingBad) + " message='" + (Get-ErrorMessage $lightingBad) + "'")
    $lightingBadParent = Invoke-Tool -Id 'setup_22_lighting_bad_parent' -Tool 'editor_setup_lighting' -Arguments @{ parent_path = 'NoSuchParentXYZ' }
    Add-Check 'setup_lighting_bad_parent_is_32001' ((Get-ErrorCode $lightingBadParent) -eq -32001) ("code=" + (Get-ErrorCode $lightingBadParent) + " message='" + (Get-ErrorMessage $lightingBadParent) + "'")

    # ------------------------------------------------------------------
    # editor_setup_navigation_agent / editor_setup_navigation_region
    # ------------------------------------------------------------------
    $agent = Invoke-Tool -Id 'setup_23_agent' -Tool 'editor_setup_navigation_agent' -Arguments @{ node_path = 'World3D'; agent_type = '3D'; name = 'Agent3D'; radius = 0.75; max_speed = 12 }
    $agentPayload = Get-Payload $agent
    Add-Check 'setup_navigation_agent_success' ((Get-ErrorCode $agent) -eq 0 -and [string]$agentPayload.type -eq 'NavigationAgent3D' -and [double]$agentPayload.radius -eq 0.75 -and [double]$agentPayload.max_speed -eq 12) ("payload=" + (ConvertTo-CompactJson $agentPayload) + " sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'setup_23_agent.response.json')).Hash.ToLower())
    $agentPaths = Get-TypePaths -Id 'setup_24_read_agent' -Type 'NavigationAgent3D'
    $agentRadius = Get-NodeProperty -Id 'setup_25_read_agent_props' -Path 'World3D/Agent3D' -Property 'radius'
    $agentSpeed = Get-NodeProperty -Id 'setup_26_read_agent_speed' -Path 'World3D/Agent3D' -Property 'max_speed'
    Add-Check 'setup_navigation_agent_read_back' (($agentPaths -contains 'World3D/Agent3D') -and ([double]$agentRadius -eq 0.75) -and ([double]$agentSpeed -eq 12)) ("find_nodes_by_type(NavigationAgent3D)=" + ($agentPaths -join ', ') + " radius=" + (ConvertTo-CompactJson $agentRadius) + " max_speed=" + (ConvertTo-CompactJson $agentSpeed))
    $agentMissing = Invoke-Tool -Id 'setup_27_agent_missing_arg' -Tool 'editor_setup_navigation_agent' -Arguments @{}
    Add-Check 'setup_navigation_agent_missing_arg_is_32602' ((Get-ErrorCode $agentMissing) -eq -32602) ("code=" + (Get-ErrorCode $agentMissing) + " message='" + (Get-ErrorMessage $agentMissing) + "'")
    $agentBadType = Invoke-Tool -Id 'setup_28_agent_bad_type' -Tool 'editor_setup_navigation_agent' -Arguments @{ node_path = 'World3D'; agent_type = '3d' }
    Add-Check 'setup_navigation_agent_bad_type_is_32602' ((Get-ErrorCode $agentBadType) -eq -32602) ("code=" + (Get-ErrorCode $agentBadType) + " message='" + (Get-ErrorMessage $agentBadType) + "'")
    $agentNoContext = Invoke-Tool -Id 'setup_29_agent_no_context' -Tool 'editor_setup_navigation_agent' -Arguments @{ node_path = 'Plain'; agent_type = '3D' }
    Add-Check 'setup_navigation_agent_no_context_is_32000' ((Get-ErrorCode $agentNoContext) -eq -32000) ("code=" + (Get-ErrorCode $agentNoContext) + " message='" + (Get-ErrorMessage $agentNoContext) + "'")
    $agentBadNode = Invoke-Tool -Id 'setup_30_agent_bad_node' -Tool 'editor_setup_navigation_agent' -Arguments @{ node_path = 'NoSuchNodeXYZ' }
    Add-Check 'setup_navigation_agent_bad_node_is_32001' ((Get-ErrorCode $agentBadNode) -eq -32001) ("code=" + (Get-ErrorCode $agentBadNode) + " message='" + (Get-ErrorMessage $agentBadNode) + "'")

    $region = Invoke-Tool -Id 'setup_31_region' -Tool 'editor_setup_navigation_region' -Arguments @{ node_path = 'World3D'; mode = 'auto'; name = 'Region3D'; agent_radius = 0.5; agent_height = 1.5; cell_size = 0.25 }
    $regionPayload = Get-Payload $region
    Add-Check 'setup_navigation_region_success' ((Get-ErrorCode $region) -eq 0 -and [string]$regionPayload.type -eq 'NavigationRegion3D' -and [double]$regionPayload.agent_radius -eq 0.5 -and [double]$regionPayload.cell_size -eq 0.25) ("payload=" + (ConvertTo-CompactJson $regionPayload) + " sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'setup_31_region.response.json')).Hash.ToLower())
    $regionPaths = Get-TypePaths -Id 'setup_32_read_region' -Type 'NavigationRegion3D'
    $regionMesh = Get-NodeProperty -Id 'setup_33_read_region_mesh' -Path 'World3D/Region3D' -Property 'navigation_mesh'
    Add-Check 'setup_navigation_region_read_back' (($regionPaths -contains 'World3D/Region3D') -and ($null -ne $regionMesh) -and [string]$regionMesh.type -eq 'NavigationMesh') ("find_nodes_by_type(NavigationRegion3D)=" + ($regionPaths -join ', ') + " navigation_mesh=" + (ConvertTo-CompactJson $regionMesh))
    $regionMissing = Invoke-Tool -Id 'setup_34_region_missing_arg' -Tool 'editor_setup_navigation_region' -Arguments @{}
    Add-Check 'setup_navigation_region_missing_arg_is_32602' ((Get-ErrorCode $regionMissing) -eq -32602) ("code=" + (Get-ErrorCode $regionMissing) + " message='" + (Get-ErrorMessage $regionMissing) + "'")
    $regionBadMode = Invoke-Tool -Id 'setup_35_region_bad_mode' -Tool 'editor_setup_navigation_region' -Arguments @{ node_path = 'World3D'; mode = '4d' }
    Add-Check 'setup_navigation_region_bad_mode_is_32602' ((Get-ErrorCode $regionBadMode) -eq -32602) ("code=" + (Get-ErrorCode $regionBadMode) + " message='" + (Get-ErrorMessage $regionBadMode) + "'")
    $regionNoContext = Invoke-Tool -Id 'setup_36_region_no_context' -Tool 'editor_setup_navigation_region' -Arguments @{ node_path = 'Plain'; mode = '3d' }
    Add-Check 'setup_navigation_region_no_context_is_32000' ((Get-ErrorCode $regionNoContext) -eq -32000) ("code=" + (Get-ErrorCode $regionNoContext) + " message='" + (Get-ErrorMessage $regionNoContext) + "'")
    $regionBadNode = Invoke-Tool -Id 'setup_37_region_bad_node' -Tool 'editor_setup_navigation_region' -Arguments @{ node_path = 'NoSuchNodeXYZ' }
    Add-Check 'setup_navigation_region_bad_node_is_32001' ((Get-ErrorCode $regionBadNode) -eq -32001) ("code=" + (Get-ErrorCode $regionBadNode) + " message='" + (Get-ErrorMessage $regionBadNode) + "'")

    # ------------------------------------------------------------------
    # editor_setup_physics_body
    # ------------------------------------------------------------------
    $body = Invoke-Tool -Id 'setup_38_physics_body' -Tool 'editor_setup_physics_body' -Arguments @{ parent_path = '.'; body_type = 'RigidBody2D'; name = 'Body1' }
    $bodyPayload = Get-Payload $body
    Add-Check 'setup_physics_body_success' ((Get-ErrorCode $body) -eq 0 -and [string]$bodyPayload.type -eq 'RigidBody2D' -and [string]$bodyPayload.name -eq 'Body1' -and [bool]$bodyPayload.created) ("payload=" + (ConvertTo-CompactJson $bodyPayload) + " sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'setup_38_physics_body.response.json')).Hash.ToLower())
    $bodyPaths = Get-TypePaths -Id 'setup_39_read_body' -Type 'RigidBody2D'
    Add-Check 'setup_physics_body_read_back' ($bodyPaths -contains 'Body1') ("find_nodes_by_type(RigidBody2D)=" + ($bodyPaths -join ', '))
    $bodyBadType = Invoke-Tool -Id 'setup_40_body_bad_type' -Tool 'editor_setup_physics_body' -Arguments @{ body_type = 'Node2D' }
    Add-Check 'setup_physics_body_bad_type_is_32602' ((Get-ErrorCode $bodyBadType) -eq -32602 -and (Get-ErrorMessage $bodyBadType).contains('PhysicsBody2D')) ("code=" + (Get-ErrorCode $bodyBadType) + " message='" + (Get-ErrorMessage $bodyBadType) + "'")
    $bodyBadParent = Invoke-Tool -Id 'setup_41_body_bad_parent' -Tool 'editor_setup_physics_body' -Arguments @{ parent_path = 'NoSuchParentXYZ' }
    Add-Check 'setup_physics_body_bad_parent_is_32001' ((Get-ErrorCode $bodyBadParent) -eq -32001) ("code=" + (Get-ErrorCode $bodyBadParent) + " message='" + (Get-ErrorMessage $bodyBadParent) + "'")

    # The tools with no required parameter are declared explicitly: there is no
    # "missing required argument" class to construct for them.
    Add-Check 'missing_arg_not_constructible' $true "editor_setup_world_environment, editor_setup_lighting and editor_setup_physics_body have required:[] in the contract, so they have no missing-required-argument class; their bottom-layer failure class is used instead (bad colour / bad light_type / bad body_type / bad parent)."

    # ------------------------------------------------------------------
    # Cross-tool chain per group
    # ------------------------------------------------------------------
    # Group 1: batch-add a Control and a body, then drive each with its own tool.
    $batchControl = Invoke-Tool -Id 'chain_01_batch_control' -Tool 'editor_add_nodes_batch' -Arguments @{
        nodes = @(
            @{ type = 'Control'; name = 'ChainControl' },
            @{ type = 'RigidBody2D'; name = 'ChainBody' }
        )
    }
    $batchControlPayload = Get-Payload $batchControl
    Add-Check 'chain_batch_add_control_and_body' ((Get-ErrorCode $batchControl) -eq 0 -and [int]$batchControlPayload.count -eq 2) ("payload=" + (ConvertTo-CompactJson $batchControlPayload))
    $chainAnchor = Invoke-Tool -Id 'chain_02_anchor_on_batched_control' -Tool 'editor_set_anchor_preset' -Arguments @{ node_path = 'ChainControl'; preset = 'full_rect' }
    Add-Check 'chain_anchor_on_batched_control' ((Get-ErrorCode $chainAnchor) -eq 0 -and [string](Get-Payload $chainAnchor).preset -eq 'full_rect') ("payload=" + (ConvertTo-CompactJson (Get-Payload $chainAnchor)))
    $chainAnchorRead = Invoke-Tool -Id 'chain_03_read_chain_control' -Tool 'editor_get_node_properties' -Arguments @{ path = 'ChainControl'; properties = @('anchor_left', 'anchor_right') }
    $chainAnchorPayload = Get-Payload $chainAnchorRead
    # `full_rect` is anchors (0,0,1,1): the left/top anchors stay at the
    # beginning and the right/bottom anchors are pinned to the end.
    Add-Check 'chain_anchor_read_back' (($null -ne $chainAnchorPayload) -and ([double]$chainAnchorPayload.properties.anchor_left -eq 0) -and ([double]$chainAnchorPayload.properties.anchor_right -eq 1)) ("ChainControl anchors=" + (ConvertTo-CompactJson $chainAnchorPayload.properties))
    $chainCollision = Invoke-Tool -Id 'chain_04_collision_on_batched_body' -Tool 'editor_setup_collision_shape' -Arguments @{ node_path = 'ChainBody'; shape_type = 'CircleShape2D'; shape_params = @{ radius = 8.5 } }
    Add-Check 'chain_collision_on_batched_body' ((Get-ErrorCode $chainCollision) -eq 0 -and [string](Get-Payload $chainCollision).collision_node_type -eq 'CollisionShape2D') ("payload=" + (ConvertTo-CompactJson (Get-Payload $chainCollision)))
    $chainCollisionPaths = Get-TypePaths -Id 'chain_05_read_chain_collision' -Type 'CollisionShape2D'
    $chainShape = Get-NodeProperty -Id 'chain_06_read_chain_shape' -Path 'ChainBody/CollisionShape2D' -Property 'shape'
    Add-Check 'chain_collision_read_back' (($chainCollisionPaths -contains 'ChainBody/CollisionShape2D') -and ($null -ne $chainShape) -and [string]$chainShape.type -eq 'CircleShape2D') ("find_nodes_by_type(CollisionShape2D)=" + ($chainCollisionPaths -join ', ') + " shape=" + (ConvertTo-CompactJson $chainShape))

    # Group 2: one property written across the nodes a batch call just created.
    $batchForProp = Invoke-Tool -Id 'chain_07_batch_prop_nodes' -Tool 'editor_add_nodes_batch' -Arguments @{
        nodes = @(
            @{ type = 'Node2D'; name = 'PropBatch1' },
            @{ type = 'Node2D'; name = 'PropBatch2' }
        )
    }
    Add-Check 'chain_batch_add_property_nodes' ((Get-ErrorCode $batchForProp) -eq 0) ("payload=" + (ConvertTo-CompactJson (Get-Payload $batchForProp)))
    $chainProp = Invoke-Tool -Id 'chain_08_property_batch' -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Node2D'; property = 'position'; value = @{ x = 21; y = 22 } }
    Add-Check 'chain_property_batch_after_batch_add' ((Get-ErrorCode $chainProp) -eq 0 -and [int](Get-Payload $chainProp).updated -ge 2) ("payload=" + (ConvertTo-CompactJson (Get-Payload $chainProp)))
    $chainPropRead = Invoke-Tool -Id 'chain_09_read_property_node' -Tool 'editor_get_node_properties' -Arguments @{ path = 'PropBatch1'; properties = @('position') }
    $chainPropPayload = Get-Payload $chainPropRead
    Add-Check 'chain_property_batch_read_back' (($null -ne $chainPropPayload) -and ([double]$chainPropPayload.properties.position.x -eq 21) -and ([double]$chainPropPayload.properties.position.y -eq 22)) ("PropBatch1.position=" + (ConvertTo-CompactJson $chainPropPayload.properties))

    # ------------------------------------------------------------------
    # TASK-017 section 3: the not_found message on the wire
    # ------------------------------------------------------------------
    $scriptProperty = Invoke-Tool -Id 'text_01_not_readable_by_name' -Tool 'editor_get_node_properties' -Arguments @{ path = 'A'; properties = @('script') }
    $scriptMessage = Get-ErrorMessage $scriptProperty
    $scriptOk = (Get-ErrorCode $scriptProperty) -eq -32001 -and $scriptMessage.contains('not readable by name not found') -and (-not $scriptMessage.contains('not found not found'))
    Add-Check 'text_not_found_suffix_once' $scriptOk ("code=" + (Get-ErrorCode $scriptProperty) + " message='" + $scriptMessage + "' sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'text_01_not_readable_by_name.response.json')).Hash.ToLower())
    $plainMessage = Get-ErrorMessage (Invoke-Tool -Id 'text_02_plain_not_found' -Tool 'editor_get_node_properties' -Arguments @{ path = 'NoSuchNodeXYZ' })
    Add-Check 'text_plain_not_found_unchanged' ($plainMessage.contains("NoSuchNodeXYZ") -and $plainMessage.contains('not found') -and (-not $plainMessage.contains('not found not found'))) ("message='" + $plainMessage + "'")
    # The transitive caller of `MCPToolError::not_found`: the batch group's
    # `_transaction_fail` forwards the message `write_node_property` already built
    # with `MCPToolError::not_found` ("Property 'x' on node '' not found") into
    # `MCPToolError::not_found` again
    # (tools/editor_node_batch_write.cpp:313-315). The assertion is the wire
    # itself: the refusal must carry exactly one " not found" and the exact
    # message. Before the TASK-017 section 3 fix this read
    # "nodes[1]: Property 'NoSuchPropertyXYZ' on node '' not found not found",
    # which is what made the fix load-bearing on a live path today.
    #
    # This replaces the former `text_no_caller_with_suffixed_p_what`, a line-local
    # `git grep` over the *direct* `not_found(...)` call sites: that test could
    # never see a message a helper forwards at runtime, so it asserted a property
    # of the source text rather than of the answer the server gives.
    $batchBadProperty = Invoke-Tool -Id 'text_03_batch_bad_property' -Tool 'editor_add_nodes_batch' -Arguments @{
        nodes = @(
            @{ type = 'Node2D'; name = 'PropOk' },
            @{ type = 'Node2D'; name = 'PropBad'; properties = @{ NoSuchPropertyXYZ = 1 } }
        )
    }
    $batchBadPropertyMessage = Get-ErrorMessage $batchBadProperty
    $batchBadPropertySuffixCount = ([regex]::Matches($batchBadPropertyMessage, ' not found')).Count
    $batchBadPropertyOk = (Get-ErrorCode $batchBadProperty) -eq -32001 -and $null -eq $batchBadProperty.result -and $batchBadPropertySuffixCount -eq 1 -and $batchBadPropertyMessage -ceq "nodes[1]: Property 'NoSuchPropertyXYZ' on node '' not found"
    Add-Check 'text_batch_property_refusal_has_exactly_one_not_found' $batchBadPropertyOk ("code=" + (Get-ErrorCode $batchBadProperty) + " result=" + ($null -eq $batchBadProperty.result) + " suffix_count=" + $batchBadPropertySuffixCount + " message='" + $batchBadPropertyMessage + "' sha256=" + (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Evid 'text_03_batch_bad_property.response.json')).Hash.ToLower())
    $batchAfterText = Get-TypePaths -Id 'text_04_read_after_bad_property' -Type 'Node2D'
    $textLeftovers = @('PropOk', 'PropBad') | Where-Object { $batchAfterText -contains $_ }
    Add-Check 'text_batch_bad_property_rolled_back' ($textLeftovers.Count -eq 0) ("Node2D paths after the refused property batch=" + ($batchAfterText -join ', ') + " leftovers=[" + ($textLeftovers -join ', ') + "]")
} catch {
    Add-Check 'harness_exception' $false ("EXCEPTION: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber)
} finally {
    Stop-Engine -Handle $script:GameHandle
    Stop-Engine -Handle $script:EditorHandle
    $userPortPidAfter = Get-ListenerPid -Port $UserPort
    Add-Check 'guard_user_port_9877' ($userPortPidBefore -eq $userPortPidAfter) ("pid_before={0} pid_after={1}" -f $userPortPidBefore, $userPortPidAfter)
}

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
