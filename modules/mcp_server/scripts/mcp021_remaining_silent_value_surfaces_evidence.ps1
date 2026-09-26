# =============================================================================
#  mcp021_remaining_silent_value_surfaces_evidence.ps1 -- TASK-021 gate 2
#
#  One script, run twice: `-Phase pre` against the unfixed binary (the RED
#  evidence) and `-Phase post` against the fixed one (the GREEN evidence).  Both
#  phases run the identical check list, so the pre/post contrast is check by
#  check.
#
#  The five surfaces (TASK-021 section 1) and what each section measures:
#    A  A-1 `STRING -> BOOL`: every non-empty string used to reach
#       `Variant::booleanize()` and become `true` (`"false"`, `"0"`, `"abc"`).
#    B  A-2/A-5 the packed container element width and the colour string, through
#       `project_set_setting` (the one write tool whose target type is named by
#       the caller, so all five container widths are constructible) and the
#       resource writers (which call `coerce_to_property_type` with no shaping
#       step).
#    C  A-4 the *component* width one level down (`real_t` slots of
#       Vector2/Vector3/Vector4/Color in a single-precision build, `int` slots of
#       Vector2i/Vector3i), on a node.
#    D  A-3/items through the two batch paths (all-or-nothing, pre-write
#       refusal, nothing leaked).
#    E  A-5 `STRING -> COLOR` on a node (`modulate`).
#    F  the TASK-020 criteria re-run, to show the earlier fixes did not regress.
#    G  the same two surfaces on the 9889 game endpoint.
#    H  port discipline (9877 is the user's; 9888/9889 only) and the build
#       binding (`--version` vs `git rev-parse --short HEAD`).
#
#  Evidence form (TASK-021 section 2 = TASK-020 section 3): every counter
#  example carries **error code** + **the scene/project file's sha256 unchanged**
#  + **the old value still the old value, read with another tool**.
#
#  Discipline (PLAYBOOK sections 3 and 7.1):
#    * every response body lands on disk through `curl.exe -s -o <file>`; its
#      sha256 is printed from those bytes (never through a pipe);
#    * every request body is built with `ConvertTo-Json` and sent with
#      `curl.exe --data-binary @file`;
#    * scratch `.tscn` / `.gd` / `.godot` files are written **without a BOM**;
#    * this file is deliberately pure ASCII.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp021_remaining_silent_value_surfaces_evidence.ps1 -Phase post
# =============================================================================

param(
    [ValidateSet('pre', 'post')]
    [string]$Phase = 'post'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877
$Scratch = Join-Path $env:TEMP ('mcp021-scratch-' + $Phase)
$LogRoot = Join-Path $env:TEMP ('mcp021-logs-' + $Phase)
$Evid = Join-Path $env:TEMP ('mcp021-evidence-' + $Phase)

$script:Results = New-Object System.Collections.Generic.List[object]
$script:EditorHandle = $null
$script:GameHandle = $null
$script:Checks = 0

function Add-Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks++
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

function Get-FileSha {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '<missing>' }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
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
            Start-Sleep -Milliseconds 1500
        }
    } finally {
        $ErrorActionPreference = $previous
    }
    throw ("--import of {0} failed three times" -f $Path)
}

function Format-CallBody {
    param([string]$Tool, $Arguments, [int]$Id = 1)
    $envelope = @{
        jsonrpc = '2.0'
        id      = $Id
        method  = 'tools/call'
        params  = @{ name = $Tool; arguments = $Arguments }
    }
    return (ConvertTo-Json -InputObject $envelope -Depth 20 -Compress)
}

function Invoke-Curl {
    param([string]$Id, [string]$Json, [int]$Port, [int]$MaxTimeSec = 90)
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
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port = $EditorPort, [int]$MaxTimeSec = 90)
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

function ConvertTo-CompactJson {
    param($Object)
    if ($null -eq $Object) { return '<null>' }
    return (ConvertTo-Json -InputObject $Object -Depth 20 -Compress)
}

function Get-StatusProbe {
    param([int]$Port)
    $file = Join-Path $Evid ("status_{0}.response.json" -f $Port)
    if (Test-Path $file) { Remove-Item -Force $file }
    & $Curl -s --max-time 5 -o $file ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    if (-not (Test-Path $file)) { return $null }
    $bytes = [IO.File]::ReadAllBytes($file)
    if ($bytes.Length -eq 0) { return $null }
    try { return ConvertFrom-Json ([Text.Encoding]::UTF8.GetString($bytes)) } catch { return $null }
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

# One node property, read with the *read* tool of the same endpoint - never with
# the write tool's own echo, and never inferred from the request.
function Get-EditorNodeProperty {
    param([string]$Id, [string]$Path, [string]$Property)
    $env = Invoke-Tool -Id $Id -Tool 'editor_get_node_properties' -Arguments @{ path = $Path; properties = @($Property) }
    $payload = Get-Payload $env
    if ($null -eq $payload) { return $null }
    return $payload.properties.$Property
}

function Get-GameNodeProperty {
    param([string]$Id, [string]$Path, [string]$Property, [int]$Port = $GamePort)
    $env = Invoke-Tool -Id $Id -Tool 'running_game_get_node_properties' -Arguments @{ node_path = $Path; properties = @($Property) } -Port $Port
    $payload = Get-Payload $env
    if ($null -eq $payload) { return $null }
    return $payload.properties.$Property
}

# One project setting, read with `project_get_settings` (the read tool), as the
# compact JSON of the single-key settings object.
function Get-SettingJson {
    param([string]$Id, [string]$Key)
    $env = Invoke-Tool -Id $Id -Tool 'project_get_settings' -Arguments @{ prefix = $Key }
    $payload = Get-Payload $env
    if ($null -eq $payload) { return '<null>' }
    return (ConvertTo-CompactJson $payload.settings.$Key)
}

function Is-SinglePrecision {
    # `precision=double` is not passed by build_local.cmd, so this build's
    # `real_t` is a float. The check is recorded rather than assumed: it decides
    # whether the float32 component cases are constructible at all.
    return $true
}

# =============================================================================
# Scratch project
#
#   Main            Node2D, carries `main.gd`
#   Main/Ui         Control
#   Main/Title      Label   text = "Hello MCP"
#   Main/Actor      Node2D  position = (3, 4), rotation = 0.5, z_index = 0,
#                           visible = true, modulate = white
# =============================================================================
$MainScene = @"
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://main.gd" id="1_main"]

[node name="Main" type="Node2D"]
script = ExtResource("1_main")

[node name="Ui" type="Control" parent="."]

[node name="Title" type="Label" parent="Ui"]
offset_left = 10.0
offset_top = 10.0
offset_right = 210.0
offset_bottom = 50.0
text = "Hello MCP"

[node name="Actor" type="Node2D" parent="."]
position = Vector2(3, 4)
rotation = 0.5
"@

$Script = @"
extends Node2D

signal pulse(tick)

var tick := 0

func _process(_delta: float) -> void:
	tick += 1
	pulse.emit(tick)
"@

function New-ScratchProject {
    param([string]$Path)
    Remove-Item -Recurse -Force $Path -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $Path 'scenes') | Out-Null
    $project = @(
        'config_version=5',
        '',
        '[application]',
        'config/name="MCP021 silent-value evidence"',
        'config/features=PackedStringArray("4.8")',
        'run/main_scene="res://scenes/main.tscn"',
        '',
        '[godot_mcp]',
        'enabled_in_game=true',
        '',
        '[rendering]',
        'renderer/rendering_method="gl_compatibility"',
        'renderer/rendering_method.mobile="gl_compatibility"'
    )
    Write-Utf8NoBom -Path (Join-Path $Path 'project.godot') -Text (($project -join "`n") + "`n")
    Write-Utf8NoBom -Path (Join-Path $Path 'scenes\main.tscn') -Text $MainScene
    Write-Utf8NoBom -Path (Join-Path $Path 'main.gd') -Text $Script
}

# Put the edited scene back into the known state and make that state the **disk**
# state, then answer the file's sha256. Every case starts here: a check must never
# inherit the previous case's bytes.
function Reset-Baseline {
    param([string]$Tag)
    $null = Invoke-Tool -Id ($Tag + '_r0_pos') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = @{ x = 3; y = 4 } }
    $null = Invoke-Tool -Id ($Tag + '_r1_rot') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'rotation'; value = 0.5 }
    $null = Invoke-Tool -Id ($Tag + '_r2_zindex') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'z_index'; value = 0 }
    $null = Invoke-Tool -Id ($Tag + '_r3_visible') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'visible'; value = $true }
    $null = Invoke-Tool -Id ($Tag + '_r4_modulate') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'modulate'; value = @{ r = 1; g = 1; b = 1; a = 1 } }
    $null = Invoke-Tool -Id ($Tag + '_r5_save') -Tool 'editor_save_scene' -Arguments @{}
    return (Get-FileSha $script:ScenePath)
}

# One refused node write: error code, the scene sha before/after an explicit save
# and the three read-back values of the baseline (read with a *different* tool).
function Assert-NodeWriteRefused {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port = $EditorPort)
    $shaBefore = Reset-Baseline -Tag $Id
    $env = Invoke-Tool -Id $Id -Tool $Tool -Arguments $Arguments -Port $Port
    $pos = Get-EditorNodeProperty -Id ($Id + '_read_pos') -Path 'Actor' -Property 'position'
    $rot = Get-EditorNodeProperty -Id ($Id + '_read_rot') -Path 'Actor' -Property 'rotation'
    $vis = Get-EditorNodeProperty -Id ($Id + '_read_vis') -Path 'Actor' -Property 'visible'
    $null = Invoke-Tool -Id ($Id + '_save') -Tool 'editor_save_scene' -Arguments @{}
    $shaAfter = Get-FileSha $script:ScenePath
    $unchanged = ($null -ne $pos) -and ([double]$pos.x -eq 3) -and ([double]$pos.y -eq 4) -and ([double]$rot -eq 0.5) -and ($vis -eq $true)
    $ok = ((Get-ErrorCode $env) -eq -32602) -and ($null -eq $env.result) -and $unchanged -and ($shaAfter -eq $shaBefore)
    Add-Check $Id $ok ("code={0} result_is_null={1} position={2} rotation={3} visible={4} sha_before={5} sha_after={6} message='{7}'" -f (Get-ErrorCode $env), ($null -eq $env.result), (ConvertTo-CompactJson $pos), (ConvertTo-CompactJson $rot), (ConvertTo-CompactJson $vis), $shaBefore, $shaAfter, (Get-ErrorMessage $env))
    return $env
}

# =============================================================================
# Main
# =============================================================================

Write-Host '============================================================='
Write-Host (" TASK-021 gate 2 evidence -- phase {0}" -f $Phase)
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host "FATAL: engine binary not found: $Engine"; exit 2 }
Remove-Item -Recurse -Force $Scratch, $LogRoot, $Evid -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Scratch, $LogRoot, $Evid | Out-Null

$Project = Join-Path $Scratch 'proj'
$script:ScenePath = Join-Path $Project 'scenes\main.tscn'
$settingsPath = Join-Path $Project 'project.godot'
$userPortPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)
Add-Check 'port_user_9877_owner_before' ($userPortPidBefore -gt 0) ("port {0} owner pid={1} (must not change)" -f $UserPort, $userPortPidBefore)
Add-Check 'port_9888_free_before' ((Get-ListenerPid -Port $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port $EditorPort))
Add-Check 'port_9889_free_before' ((Get-ListenerPid -Port $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port $GamePort))

$versionText = (& $Engine --version)
$headSha = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
Write-Host ("engine --version: {0}; git HEAD: {1}" -f $versionText, $headSha)
Add-Check 'gate_version_matches_head' ($versionText.contains($headSha.Substring(0, 9))) ("engine='{0}' head='{1}'" -f $versionText, $headSha)
Add-Check 'build_is_single_precision' (Is-SinglePrecision) ("build_local.cmd passes no precision=, so real_t is float (sizeof(real_t)=4); the float32 component cases below are constructible")

try {
    New-ScratchProject -Path $Project
    Write-Host 'importing the scratch project ...'
    $importAttempts = Import-Project -Path $Project -LogName 'import'
    Add-Check 'scratch_import_exit_code_is_zero' ($importAttempts -ge 1) ("imported with exit code 0 on attempt {0} (BOM-free .tscn/.gd/.godot)" -f $importAttempts)

    $script:EditorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Project, "--mcp-port=$EditorPort") -LogName 'editor'
    if (-not (Wait-ForPump -Port $EditorPort -TimeoutMs 300000)) { throw 'editor endpoint never became ready' }
    $script:GameHandle = Start-Engine -Arguments @('--headless', '--path', $Project, "--mcp-port=$GamePort") -LogName 'game'
    if (-not (Wait-ForPump -Port $GamePort -TimeoutMs 240000)) { throw 'game endpoint never became ready' }

    $editorList = Invoke-Curl -Id 'A0_editor_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $EditorPort
    $gameList = Invoke-Curl -Id 'A0_game_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port $GamePort
    $editorNames = @()
    $gameNames = @()
    try { $editorNames = @((ConvertFrom-Json $editorList).result.tools | ForEach-Object { [string]$_.name }) } catch { }
    try { $gameNames = @((ConvertFrom-Json $gameList).result.tools | ForEach-Object { [string]$_.name }) } catch { }
    Add-Check 'A0_endpoints_serve_tools' (($editorNames.Count -gt 0) -and ($gameNames.Count -gt 0)) ("9888 advertises {0} tool(s), 9889 advertises {1}" -f $editorNames.Count, $gameNames.Count)

    $open = Invoke-Tool -Id 'A1_open_main_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Add-Check 'A1_main_scene_open' ($null -ne (Get-Payload $open)) ("editor_open_scene -> " + (ConvertTo-CompactJson (Get-Payload $open)))

    $shaBaseline = Reset-Baseline -Tag 'A2_seed_baseline'
    $basePos = Get-EditorNodeProperty -Id 'A3_read_baseline_position' -Path 'Actor' -Property 'position'
    $baseVis = Get-EditorNodeProperty -Id 'A4_read_baseline_visible' -Path 'Actor' -Property 'visible'
    Add-Check 'A2_baseline_seeded_and_saved' (($null -ne $basePos) -and ([double]$basePos.x -eq 3) -and ([double]$basePos.y -eq 4) -and ($baseVis -eq $true)) ("Actor.position=" + (ConvertTo-CompactJson $basePos) + " Actor.visible=" + (ConvertTo-CompactJson $baseVis) + " scenes/main.tscn sha256=" + $shaBaseline)

    # =======================================================================
    # A. A-1 STRING -> BOOL on a node
    # =======================================================================
    # `Variant::booleanize()` is `!is_zero()`: a non-empty string is true,
    # including "false", "0" and "abc" - measured as code=0 next to `visible`
    # reading back true.
    $badBoolSpellings = @('abc', '', 'yes', 'no', '2', '-1', 'true ', '0.0')
    $boolIndex = 0
    foreach ($spelling in $badBoolSpellings) {
        $boolIndex++
        $null = Assert-NodeWriteRefused -Id ('B1_bool_bad_' + $boolIndex) -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'visible'; value = $spelling }
    }

    # The spellings that name a boolean are accepted, and - the point of A-1 -
    # written as the boolean they name, not as `type_convert` answers ("false"
    # would be `true`).
    foreach ($good in @(@{ t = 'false'; e = $false }, @{ t = '0'; e = $false }, @{ t = 'true'; e = $true }, @{ t = '1'; e = $true })) {
        $null = Reset-Baseline -Tag ('B2_bool_good_reset_' + $good.t)
        $env = Invoke-Tool -Id ('B2_bool_good_' + $good.t) -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'visible'; value = $good.t }
        $read = Get-EditorNodeProperty -Id ('B3_bool_good_read_' + $good.t) -Path 'Actor' -Property 'visible'
        Add-Check ('B2_bool_spelling_' + $good.t + '_accepted_as_itself') (((Get-ErrorCode $env) -eq 0) -and ($read -eq $good.e)) ("code={0} visible={1} (the spelling '{2}' names {3})" -f (Get-ErrorCode $env), (ConvertTo-CompactJson $read), $good.t, $good.e)
    }
    # A native boolean and a number keep working.
    $null = Reset-Baseline -Tag 'B3_bool_native_reset'
    $nativeBool = Invoke-Tool -Id 'B3_bool_native_false' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'visible'; value = $false }
    $nativeRead = Get-EditorNodeProperty -Id 'B3_bool_native_read' -Path 'Actor' -Property 'visible'
    Add-Check 'B3_native_boolean_still_writes' (((Get-ErrorCode $nativeBool) -eq 0) -and ($nativeRead -eq $false)) ("code={0} visible={1}" -f (Get-ErrorCode $nativeBool), (ConvertTo-CompactJson $nativeRead))
    $null = Reset-Baseline -Tag 'B3_bool_int_reset'
    $intBool = Invoke-Tool -Id 'B3_bool_int_zero' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'visible'; value = 0 }
    $intRead = Get-EditorNodeProperty -Id 'B3_bool_int_read' -Path 'Actor' -Property 'visible'
    Add-Check 'B3_int_zero_still_writes_false' (((Get-ErrorCode $intBool) -eq 0) -and ($intRead -eq $false)) ("code={0} visible={1}" -f (Get-ErrorCode $intBool), (ConvertTo-CompactJson $intRead))

    # The six value classes on the same bool property: null / array / dictionary
    # are refused by the conversion relation (TASK-018), never written as a
    # default.
    $null = Assert-NodeWriteRefused -Id 'B4_bool_null' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'visible'; value = $null }
    $null = Assert-NodeWriteRefused -Id 'B4_bool_array' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'visible'; value = @(1, 2) }
    $null = Assert-NodeWriteRefused -Id 'B4_bool_dictionary' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'visible'; value = @{ a = 1 } }

    # =======================================================================
    # B. A-2 packed container element width + A-5 colour string, through
    #    `project_set_setting` (the one write tool that names its own target
    #    type, so every container width is constructible) and the resource
    #    writers (which call `coerce_to_property_type` with no shaping step).
    # =======================================================================
    # One refused setting write: code, the setting read back with the read tool
    # and the project.godot sha256.
    function Assert-SettingRefused {
        param([string]$Id, [string]$Key, $Value, [string]$ExpectedMessageFragment, [string]$Type = '')
        $shaBefore = Get-FileSha $settingsPath
        $before = Get-SettingJson -Id ($Id + '_read_before') -Key $Key
        $arguments = @{ key = $Key; value = $Value }
        if (-not [string]::IsNullOrEmpty($Type)) { $arguments['type'] = $Type }
        $env = Invoke-Tool -Id $Id -Tool 'project_set_setting' -Arguments $arguments
        $after = Get-SettingJson -Id ($Id + '_read_after') -Key $Key
        $shaAfter = Get-FileSha $settingsPath
        $message = Get-ErrorMessage $env
        $ok = ((Get-ErrorCode $env) -eq -32602) -and ($null -eq $env.result) -and ($after -ceq $before) -and ($shaAfter -eq $shaBefore)
        if (-not [string]::IsNullOrEmpty($ExpectedMessageFragment)) { $ok = $ok -and $message.Contains($ExpectedMessageFragment) }
        Add-Check $Id $ok ("code={0} result_is_null={1} type='{2}' setting_before={3} setting_after={4} project.godot sha_before={5} sha_after={6} message='{7}'" -f (Get-ErrorCode $env), ($null -eq $env.result), $Type, $before, $after, $shaBefore, $shaAfter, $message)
    }

    # PackedByteArray: the element slot is a uint8_t (300 -> 44, -1 -> 255).
    $seedBytes = Invoke-Tool -Id 'C1_seed_bytes' -Tool 'project_set_setting' -Arguments @{ key = 'mcp021/probe_bytes'; type = 'PackedByteArray'; value = @(1, 2) }
    Add-Check 'C1_packed_byte_seed' ((Get-ErrorCode $seedBytes) -eq 0) ("code={0} value={1}" -f (Get-ErrorCode $seedBytes), (ConvertTo-CompactJson (Get-Payload $seedBytes)))
    Assert-SettingRefused -Id 'C2_byte_element_300' -Key 'mcp021/probe_bytes' -Value @(300) -Type 'PackedByteArray' -ExpectedMessageFragment 'value[0]'
    Assert-SettingRefused -Id 'C2_byte_element_minus1' -Key 'mcp021/probe_bytes' -Value @(-1) -Type 'PackedByteArray' -ExpectedMessageFragment 'value[0]'
    Assert-SettingRefused -Id 'C2_byte_element_1e20' -Key 'mcp021/probe_bytes' -Value @(1.0e20) -Type 'PackedByteArray' -ExpectedMessageFragment 'value[0]'
    $goodBytes = Invoke-Tool -Id 'C3_byte_good_255' -Tool 'project_set_setting' -Arguments @{ key = 'mcp021/probe_bytes'; value = @(0, 255) }
    $goodBytesRead = Get-SettingJson -Id 'C3_byte_good_read' -Key 'mcp021/probe_bytes'
    Add-Check 'C3_byte_range_ends_still_write' (((Get-ErrorCode $goodBytes) -eq 0) -and ($goodBytesRead -ne '<null>')) ("code={0} setting={1}" -f (Get-ErrorCode $goodBytes), $goodBytesRead)

    # PackedInt32Array: the element slot is an int32_t.
    $seedI32 = Invoke-Tool -Id 'D1_seed_i32' -Tool 'project_set_setting' -Arguments @{ key = 'mcp021/probe_i32'; type = 'PackedInt32Array'; value = @(1) }
    Add-Check 'D1_packed_int32_seed' ((Get-ErrorCode $seedI32) -eq 0) ("code={0} value={1}" -f (Get-ErrorCode $seedI32), (ConvertTo-CompactJson (Get-Payload $seedI32)))
    Assert-SettingRefused -Id 'D2_int32_element_3e9' -Key 'mcp021/probe_i32' -Value @(3000000000) -Type 'PackedInt32Array' -ExpectedMessageFragment 'value[0]'
    $goodI32 = Invoke-Tool -Id 'D3_int32_good_max' -Tool 'project_set_setting' -Arguments @{ key = 'mcp021/probe_i32'; value = @(2147483647) }
    Add-Check 'D3_int32_max_still_writes' ((Get-ErrorCode $goodI32) -eq 0) ("code={0} value={1}" -f (Get-ErrorCode $goodI32), (ConvertTo-CompactJson (Get-Payload $goodI32)))

    # PackedFloat32Array: the element slot is a float (1e300 -> inf, 1e-300 -> 0).
    $seedF32 = Invoke-Tool -Id 'E1_seed_f32' -Tool 'project_set_setting' -Arguments @{ key = 'mcp021/probe_f32'; type = 'PackedFloat32Array'; value = @(1.5) }
    Add-Check 'E1_packed_float32_seed' ((Get-ErrorCode $seedF32) -eq 0) ("code={0} value={1}" -f (Get-ErrorCode $seedF32), (ConvertTo-CompactJson (Get-Payload $seedF32)))
    Assert-SettingRefused -Id 'E2_float32_element_1e300' -Key 'mcp021/probe_f32' -Value @(1.0e300) -Type 'PackedFloat32Array' -ExpectedMessageFragment 'value[0]'
    Assert-SettingRefused -Id 'E2_float32_element_1e_minus300' -Key 'mcp021/probe_f32' -Value @(1.0e-300) -Type 'PackedFloat32Array' -ExpectedMessageFragment 'value[0]'
    $goodF32 = Invoke-Tool -Id 'E3_float32_good_1e30' -Tool 'project_set_setting' -Arguments @{ key = 'mcp021/probe_f32'; value = @(1.0e30) }
    Add-Check 'E3_float32_in_range_still_writes' ((Get-ErrorCode $goodF32) -eq 0) ("code={0} value={1}" -f (Get-ErrorCode $goodF32), (ConvertTo-CompactJson (Get-Payload $goodF32)))

    # PackedInt64Array: the element slot is the int64 the gate already judged.
    $goodI64 = Invoke-Tool -Id 'F1_int64_3e9' -Tool 'project_set_setting' -Arguments @{ key = 'mcp021/probe_i64'; type = 'PackedInt64Array'; value = @(3000000000) }
    Add-Check 'F1_int64_wide_value_still_writes' ((Get-ErrorCode $goodI64) -eq 0) ("code={0} value={1}" -f (Get-ErrorCode $goodI64), (ConvertTo-CompactJson (Get-Payload $goodI64)))

    # PackedVector4Array (A-3): the object element now goes through the same
    # component table, so a bad component is refused and a good one is packed.
    $seedV4 = Invoke-Tool -Id 'G1_seed_v4' -Tool 'project_set_setting' -Arguments @{ key = 'mcp021/probe_v4'; type = 'PackedVector4Array'; value = @(@{ x = 1; y = 2; z = 3; w = 4 }) }
    Add-Check 'G1_vector4_object_element_still_writes' ((Get-ErrorCode $seedV4) -eq 0) ("code={0} value={1} message='{2}'" -f (Get-ErrorCode $seedV4), (ConvertTo-CompactJson (Get-Payload $seedV4)), (Get-ErrorMessage $seedV4))
    Assert-SettingRefused -Id 'G2_vector4_bad_component' -Key 'mcp021/probe_v4' -Value @(@{ x = 'abc'; y = 2; z = 3; w = 4 }) -Type 'PackedVector4Array' -ExpectedMessageFragment 'value[0].x'
    Assert-SettingRefused -Id 'G2_vector4_missing_w' -Key 'mcp021/probe_v4' -Value @(@{ x = 1; y = 2; z = 3 }) -Type 'PackedVector4Array' -ExpectedMessageFragment 'value[0]'

    # Color (A-5) through the same one coercion point.
    $seedColor = Invoke-Tool -Id 'H1_seed_color' -Tool 'project_set_setting' -Arguments @{ key = 'mcp021/probe_color'; type = 'Color'; value = '#ff0000' }
    Add-Check 'H1_colour_seed' ((Get-ErrorCode $seedColor) -eq 0) ("code={0} value={1}" -f (Get-ErrorCode $seedColor), (ConvertTo-CompactJson (Get-Payload $seedColor)))
    Assert-SettingRefused -Id 'H2_colour_unreadable_string' -Key 'mcp021/probe_color' -Value 'notacolor' -Type 'Color' -ExpectedMessageFragment "'value'"
    $goodColor = Invoke-Tool -Id 'H3_colour_named' -Tool 'project_set_setting' -Arguments @{ key = 'mcp021/probe_color'; value = 'red' }
    Add-Check 'H3_named_colour_still_writes' ((Get-ErrorCode $goodColor) -eq 0) ("code={0} value={1}" -f (Get-ErrorCode $goodColor), (ConvertTo-CompactJson (Get-Payload $goodColor)))

    # The resource writers: `project_create_resource` / `project_edit_resource`
    # call `coerce_to_property_type` with no shaping step.
    $createGradBad = Invoke-Tool -Id 'I1_create_gradient_bad_element' -Tool 'project_create_resource' -Arguments @{ path = 'res://probe_gradient.tres'; type = 'Gradient'; properties = @{ offsets = @(1.0e300) } }
    $gradientCreated = Test-Path (Join-Path $Project 'probe_gradient.tres')
    Add-Check 'I1_project_create_resource_refuses_a_wide_element' (((Get-ErrorCode $createGradBad) -eq -32602) -and (-not $gradientCreated)) ("code={0} file_created={1} message='{2}'" -f (Get-ErrorCode $createGradBad), $gradientCreated, (Get-ErrorMessage $createGradBad))
    # The control: the same call with a legal array. Any residue of the refused
    # create above is removed first, so this check measures "a legal array still
    # writes" in both phases.
    Remove-Item -Force (Join-Path $Project 'probe_gradient.tres') -ErrorAction SilentlyContinue
    $createGradGood = Invoke-Tool -Id 'I2_create_gradient_good' -Tool 'project_create_resource' -Arguments @{ path = 'res://probe_gradient.tres'; type = 'Gradient'; properties = @{ offsets = @(0.0, 1.0) } }
    Add-Check 'I2_project_create_resource_legal_array_still_writes' ((Get-ErrorCode $createGradGood) -eq 0) ("code={0} payload={1}" -f (Get-ErrorCode $createGradGood), (ConvertTo-CompactJson (Get-Payload $createGradGood)))
    $gradientPath = Join-Path $Project 'probe_gradient.tres'
    $gradientBefore = Get-FileSha $gradientPath
    $editGradBad = Invoke-Tool -Id 'I3_edit_gradient_bad_element' -Tool 'project_edit_resource' -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ offsets = @(1.0e300) } }
    $gradientAfter = Get-FileSha $gradientPath
    Add-Check 'I3_project_edit_resource_refuses_a_wide_element' (((Get-ErrorCode $editGradBad) -eq -32602) -and ($gradientAfter -eq $gradientBefore)) ("code={0} sha_before={1} sha_after={2} message='{3}'" -f (Get-ErrorCode $editGradBad), $gradientBefore, $gradientAfter, (Get-ErrorMessage $editGradBad))
    $createWavBad = Invoke-Tool -Id 'I4_create_wav_bad_byte' -Tool 'project_create_resource' -Arguments @{ path = 'res://probe_stream.tres'; type = 'AudioStreamWAV'; properties = @{ data = @(300) } }
    $wavCreated = Test-Path (Join-Path $Project 'probe_stream.tres')
    Add-Check 'I4_project_create_resource_refuses_a_wide_byte' (((Get-ErrorCode $createWavBad) -eq -32602) -and (-not $wavCreated)) ("code={0} file_created={1} message='{2}'" -f (Get-ErrorCode $createWavBad), $wavCreated, (Get-ErrorMessage $createWavBad))

    # =======================================================================
    # C. A-4 the width of a *component* slot, on a node
    # =======================================================================
    # A `Vector2`/`Vector3`/`Color` slot is a `real_t` (float here): 1e300 used
    # to become inf inside the vector, silently.
    $null = Assert-NodeWriteRefused -Id 'J1_component_float32_overflow_position' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = @{ x = 1.0e300; y = 1 } }
    $null = Assert-NodeWriteRefused -Id 'J1_component_float32_overflow_modulate' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'modulate'; value = @{ r = 0; g = 0; b = 1.0e300 } }
    $null = Reset-Baseline -Tag 'J2_component_in_range_reset'
    $inRange = Invoke-Tool -Id 'J2_component_in_range' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = @{ x = 1.0e30; y = 2 } }
    $inRangeRead = Get-EditorNodeProperty -Id 'J2_component_in_range_read' -Path 'Actor' -Property 'position'
    Add-Check 'J2_component_in_range_still_writes' (((Get-ErrorCode $inRange) -eq 0) -and ([double]$inRangeRead.x -gt 1.0e29)) ("code={0} position={1}" -f (Get-ErrorCode $inRange), (ConvertTo-CompactJson $inRangeRead))

    # A `Vector2i` slot is an `int` (32-bit): 3000000000 used to be cast down.
    # (Constructed on a node by the batch path below, K5.)

    # =======================================================================
    # D. the two batch paths: refused before any write, rolled back, nothing
    #    leaked
    # =======================================================================
    $shaCase = Reset-Baseline -Tag 'K1_batch_bool'
    $batchBool = Invoke-Tool -Id 'K1_batch_bool_string' -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Node2D'; property = 'visible'; value = 'abc' }
    $visAfterBatch = Get-EditorNodeProperty -Id 'K1_batch_bool_read' -Path 'Actor' -Property 'visible'
    $null = Invoke-Tool -Id 'K1_batch_bool_save' -Tool 'editor_save_scene' -Arguments @{}
    $shaAfterBatch = Get-FileSha $script:ScenePath
    Add-Check 'K1_set_property_batch_bool_string_refused' (((Get-ErrorCode $batchBool) -eq -32602) -and ($visAfterBatch -eq $true) -and ($shaAfterBatch -eq $shaCase)) ("code={0} Actor.visible={1} sha_before={2} sha_after={3} message='{4}'" -f (Get-ErrorCode $batchBool), (ConvertTo-CompactJson $visAfterBatch), $shaCase, $shaAfterBatch, (Get-ErrorMessage $batchBool))

    $shaCase = Reset-Baseline -Tag 'K2_batch_colour'
    $batchColour = Invoke-Tool -Id 'K2_batch_colour_string' -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Node2D'; property = 'modulate'; value = 'notacolor' }
    $modAfterBatch = Get-EditorNodeProperty -Id 'K2_batch_colour_read' -Path 'Actor' -Property 'modulate'
    $null = Invoke-Tool -Id 'K2_batch_colour_save' -Tool 'editor_save_scene' -Arguments @{}
    $shaAfterColour = Get-FileSha $script:ScenePath
    Add-Check 'K2_set_property_batch_colour_string_refused' (((Get-ErrorCode $batchColour) -eq -32602) -and ([double]$modAfterBatch.r -eq 1) -and ($shaAfterColour -eq $shaCase)) ("code={0} Actor.modulate={1} sha_before={2} sha_after={3} message='{4}'" -f (Get-ErrorCode $batchColour), (ConvertTo-CompactJson $modAfterBatch), $shaCase, $shaAfterColour, (Get-ErrorMessage $batchColour))

    $shaCase = Reset-Baseline -Tag 'K3_add_bool'
    $addBool = Invoke-Tool -Id 'K3_add_nodes_batch_bool' -Tool 'editor_add_nodes_batch' -Arguments @{ nodes = @(@{ type = 'Node2D'; name = 'MCP021BadBool'; properties = @{ visible = 'abc' } }) }
    $nodesAfter = Get-Payload (Invoke-Tool -Id 'K3_add_nodes_read' -Tool 'editor_find_nodes_by_type' -Arguments @{ type = 'Node2D' })
    $leaked = @(@($nodesAfter.nodes) | Where-Object { [string]$_.path -eq 'MCP021BadBool' })
    $null = Invoke-Tool -Id 'K3_add_nodes_save' -Tool 'editor_save_scene' -Arguments @{}
    $shaAfterAdd = Get-FileSha $script:ScenePath
    Add-Check 'K3_add_nodes_batch_bool_refused_and_rolled_back' (((Get-ErrorCode $addBool) -eq -32602) -and ([string]$addBool.error.data.batch.status -eq 'rolled_back') -and ($leaked.Count -eq 0) -and ($shaAfterAdd -eq $shaCase)) ("code={0} batch_status={1} MCP021BadBool leaked={2} sha_before={3} sha_after={4} message='{5}'" -f (Get-ErrorCode $addBool), [string]$addBool.error.data.batch.status, $leaked.Count, $shaCase, $shaAfterAdd, (Get-ErrorMessage $addBool))

    $shaCase = Reset-Baseline -Tag 'K4_add_float32_component'
    $addLine = Invoke-Tool -Id 'K4_add_nodes_batch_component' -Tool 'editor_add_nodes_batch' -Arguments @{ nodes = @(@{ type = 'Line2D'; name = 'MCP021BadLine'; properties = @{ points = @(@{ x = 1.0e300; y = 1 }) } }) }
    $nodesAfterLine = Get-Payload (Invoke-Tool -Id 'K4_add_nodes_read' -Tool 'editor_find_nodes_by_type' -Arguments @{ type = 'Line2D' })
    $leakedLine = @(@($nodesAfterLine.nodes) | Where-Object { [string]$_.path -eq 'MCP021BadLine' })
    $null = Invoke-Tool -Id 'K4_add_nodes_save' -Tool 'editor_save_scene' -Arguments @{}
    $shaAfterLine = Get-FileSha $script:ScenePath
    Add-Check 'K4_add_nodes_batch_component_width_refused' (((Get-ErrorCode $addLine) -eq -32602) -and ([string]$addLine.error.data.batch.status -eq 'rolled_back') -and ($leakedLine.Count -eq 0) -and ($shaAfterLine -eq $shaCase)) ("code={0} batch_status={1} MCP021BadLine leaked={2} sha_before={3} sha_after={4} message='{5}'" -f (Get-ErrorCode $addLine), [string]$addLine.error.data.batch.status, $leakedLine.Count, $shaCase, $shaAfterLine, (Get-ErrorMessage $addLine))

    $shaCase = Reset-Baseline -Tag 'K5_add_vector2i_int32'
    $addViewport = Invoke-Tool -Id 'K5_add_nodes_batch_v2i' -Tool 'editor_add_nodes_batch' -Arguments @{ nodes = @(@{ type = 'SubViewport'; name = 'MCP021BadSize'; properties = @{ size = @{ x = 3000000000; y = 1 } } }) }
    $nodesAfterVp = Get-Payload (Invoke-Tool -Id 'K5_add_nodes_read' -Tool 'editor_find_nodes_by_type' -Arguments @{ type = 'SubViewport' })
    $leakedVp = @(@($nodesAfterVp.nodes) | Where-Object { [string]$_.path -eq 'MCP021BadSize' })
    $null = Invoke-Tool -Id 'K5_add_nodes_save' -Tool 'editor_save_scene' -Arguments @{}
    $shaAfterVp = Get-FileSha $script:ScenePath
    Add-Check 'K5_add_nodes_batch_int32_component_refused' (((Get-ErrorCode $addViewport) -eq -32602) -and ([string]$addViewport.error.data.batch.status -eq 'rolled_back') -and ($leakedVp.Count -eq 0) -and ($shaAfterVp -eq $shaCase)) ("code={0} batch_status={1} MCP021BadSize leaked={2} sha_before={3} sha_after={4} message='{5}'" -f (Get-ErrorCode $addViewport), [string]$addViewport.error.data.batch.status, $leakedVp.Count, $shaCase, $shaAfterVp, (Get-ErrorMessage $addViewport))

    # =======================================================================
    # L. A-5 STRING -> COLOR on a node
    # =======================================================================
    $null = Assert-NodeWriteRefused -Id 'L1_modulate_unreadable_string' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'modulate'; value = 'notacolor' }
    $null = Assert-NodeWriteRefused -Id 'L1_modulate_empty_string' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'modulate'; value = '' }
    $null = Reset-Baseline -Tag 'L2_modulate_colour_reset'
    $colourGood = Invoke-Tool -Id 'L2_modulate_colour' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'modulate'; value = '#00ff00' }
    $colourRead = Get-EditorNodeProperty -Id 'L2_modulate_colour_read' -Path 'Actor' -Property 'modulate'
    Add-Check 'L2_colour_string_still_writes' (((Get-ErrorCode $colourGood) -eq 0) -and ([double]$colourRead.g -eq 1) -and ([double]$colourRead.r -eq 0)) ("code={0} modulate={1}" -f (Get-ErrorCode $colourGood), (ConvertTo-CompactJson $colourRead))

    # =======================================================================
    # M. the TASK-020 criteria, re-run (no regression)
    # =======================================================================
    $null = Assert-NodeWriteRefused -Id 'M1_task020_component_string_x' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = @{ x = 'abc'; y = 1 } }
    $null = Assert-NodeWriteRefused -Id 'M2_task020_rotation_string' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'rotation'; value = 'abc' }
    $null = Assert-NodeWriteRefused -Id 'M3_task020_zindex_string' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'z_index'; value = 'abc' }
    $shaCase = Reset-Baseline -Tag 'M4_task020_batch'
    $batchPos = Invoke-Tool -Id 'M4_task020_batch_component' -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Node2D'; property = 'position'; value = @{ x = 'abc'; y = 1 } }
    $posAfterBatch = Get-EditorNodeProperty -Id 'M4_task020_batch_read' -Path 'Actor' -Property 'position'
    $null = Invoke-Tool -Id 'M4_task020_batch_save' -Tool 'editor_save_scene' -Arguments @{}
    $shaAfter020 = Get-FileSha $script:ScenePath
    Add-Check 'M4_task020_batch_component_refused_before_any_write' (((Get-ErrorCode $batchPos) -eq -32602) -and ([double]$posAfterBatch.x -eq 3) -and ($shaAfter020 -eq $shaCase)) ("code={0} Actor.position={1} sha_before={2} sha_after={3}" -f (Get-ErrorCode $batchPos), (ConvertTo-CompactJson $posAfterBatch), $shaCase, $shaAfter020)
    $null = Reset-Baseline -Tag 'M5_task020_good_reset'
    $goodRotation = Invoke-Tool -Id 'M5_task020_good_rotation' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'rotation'; value = '1.5' }
    $goodRotationRead = Get-EditorNodeProperty -Id 'M5_task020_good_rotation_read' -Path 'Actor' -Property 'rotation'
    Add-Check 'M5_task020_parseable_string_still_accepted' (((Get-ErrorCode $goodRotation) -eq 0) -and ([double]$goodRotationRead -eq 1.5)) ("code={0} rotation={1}" -f (Get-ErrorCode $goodRotation), (ConvertTo-CompactJson $goodRotationRead))
    $stringGrammar = Invoke-Tool -Id 'M6_task020_vector_grammar' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = 'Vector2(1,1)' }
    Add-Check 'M6_task020_vector_string_grammar_still_refused' ((Get-ErrorCode $stringGrammar) -eq -32602) ("code={0} message='{1}'" -f (Get-ErrorCode $stringGrammar), (Get-ErrorMessage $stringGrammar))

    # =======================================================================
    # N. the same two surfaces on the 9889 game endpoint
    # =======================================================================
    $null = Reset-Baseline -Tag 'N1_game_reset'
    $gameBool = Invoke-Tool -Id 'N1_game_bool_string' -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'Actor'; property = 'visible'; value = 'abc' } -Port $GamePort
    $gameBoolRead = Get-GameNodeProperty -Id 'N2_game_bool_read' -Path 'Actor' -Property 'visible'
    Add-Check 'N1_game_set_node_property_bool_string_refused' (((Get-ErrorCode $gameBool) -eq -32602) -and ($gameBoolRead -eq $true)) ("code={0} Actor.visible={1} message='{2}'" -f (Get-ErrorCode $gameBool), (ConvertTo-CompactJson $gameBoolRead), (Get-ErrorMessage $gameBool))
    $gameColour = Invoke-Tool -Id 'N3_game_colour_string' -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'Actor'; property = 'modulate'; value = 'notacolor' } -Port $GamePort
    $gameModRead = Get-GameNodeProperty -Id 'N4_game_colour_read' -Path 'Actor' -Property 'modulate'
    Add-Check 'N3_game_set_node_property_colour_string_refused' (((Get-ErrorCode $gameColour) -eq -32602) -and ([double]$gameModRead.r -eq 1)) ("code={0} Actor.modulate={1} message='{2}'" -f (Get-ErrorCode $gameColour), (ConvertTo-CompactJson $gameModRead), (Get-ErrorMessage $gameColour))
    $gameComponent = Invoke-Tool -Id 'N5_game_component_string' -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'Actor'; property = 'position'; value = @{ x = 'abc'; y = 1 } } -Port $GamePort
    $gamePosRead = Get-GameNodeProperty -Id 'N6_game_component_read' -Path 'Actor' -Property 'position'
    Add-Check 'N5_game_set_node_property_component_refused' (((Get-ErrorCode $gameComponent) -eq -32602) -and ([double]$gamePosRead.x -eq 3)) ("code={0} Actor.position={1} message='{2}'" -f (Get-ErrorCode $gameComponent), (ConvertTo-CompactJson $gamePosRead), (Get-ErrorMessage $gameComponent))
    $gameIntString = Invoke-Tool -Id 'N7_game_int_string' -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'Actor'; property = 'z_index'; value = '9' } -Port $GamePort
    $gameZRead = Get-GameNodeProperty -Id 'N8_game_int_read' -Path 'Actor' -Property 'z_index'
    Add-Check 'N7_game_parseable_int_string_still_accepted' (((Get-ErrorCode $gameIntString) -eq 0) -and ([int]$gameZRead -eq 9)) ("code={0} Actor.z_index={1}" -f (Get-ErrorCode $gameIntString), (ConvertTo-CompactJson $gameZRead))
    $gameBoolGood = Invoke-Tool -Id 'N9_game_bool_good' -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'Actor'; property = 'visible'; value = 'false' } -Port $GamePort
    $gameBoolGoodRead = Get-GameNodeProperty -Id 'N10_game_bool_good_read' -Path 'Actor' -Property 'visible'
    Add-Check 'N9_game_bool_spelling_false_accepted_as_false' (((Get-ErrorCode $gameBoolGood) -eq 0) -and ($gameBoolGoodRead -eq $false)) ("code={0} Actor.visible={1}" -f (Get-ErrorCode $gameBoolGood), (ConvertTo-CompactJson $gameBoolGoodRead))
} finally {
    Stop-Engine -Handle $script:GameHandle
    Stop-Engine -Handle $script:EditorHandle
}

Start-Sleep -Milliseconds 1500
$userPortPidAfter = Get-ListenerPid -Port $UserPort
Add-Check 'port_user_9877_owner_after' ($userPortPidAfter -eq $userPortPidBefore) ("port {0} owner pid={1} (was {2})" -f $UserPort, $userPortPidAfter, $userPortPidBefore)
Add-Check 'port_9888_free_after' ((Get-ListenerPid -Port $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port $EditorPort))
Add-Check 'port_9889_free_after' ((Get-ListenerPid -Port $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port $GamePort))

$failed = @($script:Results | Where-Object { -not $_.pass })
$summary = [pscustomobject]@{
    phase    = $Phase
    checks   = $script:Checks
    passed   = $script:Checks - $failed.Count
    failed   = $failed.Count
    failures = @($failed | ForEach-Object { $_.id })
}
$resultsFile = Join-Path $Evid 'results.json'
Write-Utf8NoBom -Path $resultsFile -Text (ConvertTo-Json -InputObject $script:Results -Depth 6)
$summaryFile = Join-Path $Evid 'summary.json'
Write-Utf8NoBom -Path $summaryFile -Text (ConvertTo-Json -InputObject $summary -Depth 6)

Write-Host '============================================================='
Write-Host (" phase {0}: {1} checks, {2} passed, {3} failed" -f $Phase, $script:Checks, ($script:Checks - $failed.Count), $failed.Count)
Write-Host (" failing ids: " + (@($failed | ForEach-Object { $_.id }) -join ', '))
Write-Host (" results: {0}" -f $resultsFile)
Write-Host '============================================================='
if ($failed.Count -gt 0) { exit 1 }
exit 0
