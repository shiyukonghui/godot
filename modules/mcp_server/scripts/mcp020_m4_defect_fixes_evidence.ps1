# =============================================================================
#  mcp020_m4_defect_fixes_evidence.ps1 -- TASK-020 gate 2 evidence
#
#  One script, run twice: `-Phase pre` against the unfixed binary (the RED
#  evidence: the M4 acceptance's D-1/D-2/D-3 reproductions) and `-Phase post`
#  against the fixed one (the GREEN evidence).  The two runs are the "before /
#  after" contrast the task book asks for; the evidence files of the two phases
#  live in separate directories so nothing can be mixed up.
#
#  Sections:
#    A  D-1: the *components* of a composite value.  The five spellings the M4
#       acceptance measured as `code=0` with `position.x` read back as `0.0`,
#       plus the second slot, Vector3 / Vector2i / Color, the accepted half, and
#       the batch paths (`editor_set_node_property_batch`, `editor_add_nodes_batch`).
#       Evidence form (the task book's hard requirement): **error code + the
#       scene file's sha256 unchanged + the old value still the old value**, read
#       back with a *different* tool.  A read-back-vs-request comparison alone
#       cannot tell "refused" from "the engine wrote its default".
#    B  D-2: `STRING -> FLOAT/INT`.  The six value classes
#       (integer/float/string/composite/array/dictionary/null) against a float
#       property, an int property and the composite `position`, on 9888 and 9889.
#    C  D-3: the two assertion entries' failure field sets, compared field by
#       field and reason text by reason text.
#    D  the two verifications the M4 acceptance could not finish:
#       `project_set_node_property_across_scenes` with a good + a broken file,
#       and `editor_analyze_screenshot_diff` against engine-encoded PNGs.
#    E  port discipline (9877 is the user's; 9888/9889 only).
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
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp020_m4_defect_fixes_evidence.ps1 -Phase post
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
$Scratch = Join-Path $env:TEMP ('mcp020-scratch-' + $Phase)
$LogRoot = Join-Path $env:TEMP ('mcp020-logs-' + $Phase)
$Evid = Join-Path $env:TEMP ('mcp020-evidence-' + $Phase)

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

function Get-Suggestion {
    param($Envelope)
    if ($null -eq $Envelope -or $null -eq $Envelope.error -or $null -eq $Envelope.error.data) { return '' }
    return [string]$Envelope.error.data.suggestion
}

function ConvertTo-CompactJson {
    param($Object)
    if ($null -eq $Object) { return '<null>' }
    return (ConvertTo-Json -InputObject $Object -Depth 20 -Compress)
}

# The sorted key names of a payload. D-3's question ("do the two entries carry
# the same failure fields?") is a set comparison; `ConvertTo-Json` key order is
# not part of any contract.
function Get-KeySet {
    param($Object)
    if ($null -eq $Object) { return @() }
    return @($Object.PSObject.Properties | ForEach-Object { [string]$_.Name } | Sort-Object)
}

function Remove-Keys {
    param($KeySet, [string[]]$Drop)
    return @($KeySet | Where-Object { $Drop -cnotcontains $_ })
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

# =============================================================================
# Scratch project
#
#   Main            Node2D, carries `main.gd`
#   Main/Ui         Control
#   Main/Ui/Title   Label   text = "Hello MCP"
#   Main/Actor      Node2D  position = (3, 4), rotation = 0.5, z_index = 0
#
#   cross/one.tscn  Node2D One
#   cross/two.tscn  Node2D Two
#   cross/broken.tscn  written after the import, truncated on purpose
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
    New-Item -ItemType Directory -Force -Path (Join-Path $Path 'scenes'), (Join-Path $Path 'cross') | Out-Null
    $project = @(
        'config_version=5',
        '',
        '[application]',
        'config/name="MCP020 defect-fix evidence"',
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
    Write-Utf8NoBom -Path (Join-Path $Path 'cross\one.tscn') -Text "[gd_scene format=3]`n`n[node name=`"One`" type=`"Node2D`"]`n"
    Write-Utf8NoBom -Path (Join-Path $Path 'cross\two.tscn') -Text "[gd_scene format=3]`n`n[node name=`"Two`" type=`"Node2D`"]`n"
}

# Put the edited scene back into the known state and make that state the **disk**
# state, then answer the file's sha256. Every D-1/D-2 case starts here: in the
# pre-fix phase a "refusal" case really does write, and a check must never inherit
# the previous case's bytes (that is also what makes the pre/post contrast honest
# case by case instead of only at the end).
function Reset-Baseline {
    param([string]$Tag)
    $null = Invoke-Tool -Id ($Tag + '_r0_pos') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = @{ x = 3; y = 4 } }
    $null = Invoke-Tool -Id ($Tag + '_r1_rot') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'rotation'; value = 0.5 }
    $null = Invoke-Tool -Id ($Tag + '_r2_zindex') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'z_index'; value = 0 }
    $null = Invoke-Tool -Id ($Tag + '_r3_modulate') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'modulate'; value = @{ r = 1; g = 1; b = 1; a = 1 } }
    $null = Invoke-Tool -Id ($Tag + '_r4_save') -Tool 'editor_save_scene' -Arguments @{}
    return (Get-FileSha $scenePath)
}

# =============================================================================
# Main
# =============================================================================

Write-Host '============================================================='
Write-Host (" TASK-020 gate 2 evidence -- phase {0}" -f $Phase)
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host "FATAL: engine binary not found: $Engine"; exit 2 }
Remove-Item -Recurse -Force $Scratch, $LogRoot, $Evid -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Scratch, $LogRoot, $Evid | Out-Null

$Project = Join-Path $Scratch 'proj'
$userPortPidBefore = Get-ListenerPid -Port $UserPort
Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPortPidBefore)
Add-Check 'port_user_9877_owner_before' ($userPortPidBefore -gt 0) ("port {0} owner pid={1} (must not change)" -f $UserPort, $userPortPidBefore)
Add-Check 'port_9888_free_before' ((Get-ListenerPid -Port $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port $EditorPort))
Add-Check 'port_9889_free_before' ((Get-ListenerPid -Port $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port $GamePort))

$versionText = (& $Engine --version)
$headSha = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
Write-Host ("engine --version: {0}; git HEAD: {1}" -f $versionText, $headSha)
Add-Check 'gate_version_matches_head' ($versionText.contains($headSha.Substring(0, 9))) ("engine='{0}' head='{1}'" -f $versionText, $headSha)

try {
    New-ScratchProject -Path $Project
    Write-Host 'importing the scratch project ...'
    $importAttempts = Import-Project -Path $Project -LogName 'import'
    Add-Check 'scratch_import_exit_code_is_zero' ($importAttempts -ge 1) ("imported with exit code 0 on attempt {0} (BOM-free .tscn/.gd/.godot)" -f $importAttempts)

    # A deliberately broken scene, written *after* the import so the import log
    # stays clean; the transaction reads the directory, not the import cache.
    Write-Utf8NoBom -Path (Join-Path $Project 'cross\broken.tscn') -Text "[gd_scene format=3]`n`n[node name=`"Broken`" type=`"Node2D`"`n"

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

    $scenePath = Join-Path $Project 'scenes\main.tscn'

    # The baseline the whole D-1/D-2 section is measured against: a known value
    # written through the tool itself, **saved to disk**, so "unchanged" is a
    # sha256 comparison and not a guess.
    $seed = Invoke-Tool -Id 'A2_seed_baseline' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = @{ x = 3; y = 4 } }
    $seed2 = Invoke-Tool -Id 'A3_seed_rotation' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'rotation'; value = 0.5 }
    $seed3 = Invoke-Tool -Id 'A4_seed_zindex' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'z_index'; value = 0 }
    $save = Invoke-Tool -Id 'A5_save_baseline' -Tool 'editor_save_scene' -Arguments @{}
    $shaBaseline = Get-FileSha $scenePath
    $basePos = Get-EditorNodeProperty -Id 'A6_read_baseline_position' -Path 'Actor' -Property 'position'
    $baseRot = Get-EditorNodeProperty -Id 'A7_read_baseline_rotation' -Path 'Actor' -Property 'rotation'
    Add-Check 'A2_baseline_seeded_and_saved' (($null -ne (Get-Payload $seed)) -and ($null -ne (Get-Payload $seed2)) -and ($null -ne (Get-Payload $seed3)) -and ($null -ne (Get-Payload $save)) -and ($null -ne $basePos) -and ([double]$basePos.x -eq 3) -and ([double]$basePos.y -eq 4) -and ([double]$baseRot -eq 0.5)) ("Actor.position=" + (ConvertTo-CompactJson $basePos) + " rotation=" + (ConvertTo-CompactJson $baseRot) + " scenes/main.tscn sha256=" + $shaBaseline)

    # =======================================================================
    # A. D-1: the components of a composite value
    # =======================================================================
    # The five spellings the M4 acceptance measured as a success reading back
    # 0.0, each in both component slots. The evidence form is the task book's:
    # error code + scene sha256 unchanged (after an explicit save) + the old
    # value still the old value via `editor_get_node_properties`.
    $badComponents = @(
        @{ label = 'string_abc'; value = 'abc' },
        @{ label = 'string_nan'; value = 'NaN' },
        @{ label = 'null'; value = $null },
        @{ label = 'object'; value = @{ z = 9 } },
        @{ label = 'array'; value = @(1, 2) }
    )
    foreach ($bad in $badComponents) {
        foreach ($slot in @('x', 'y')) {
            $caseTag = 'R1_' + $bad.label + '_' + $slot
            $shaCase = Reset-Baseline -Tag $caseTag
            $value = @{ x = 1; y = 1 }
            $value[$slot] = $bad.value
            $env = Invoke-Tool -Id ($caseTag + '_write') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = $value }
            $code = Get-ErrorCode $env
            $readBack = Get-EditorNodeProperty -Id ($caseTag + '_read') -Path 'Actor' -Property 'position'
            $rotBack = Get-EditorNodeProperty -Id ($caseTag + '_read2') -Path 'Actor' -Property 'rotation'
            $unchanged = ($null -ne $readBack) -and ([double]$readBack.x -eq 3) -and ([double]$readBack.y -eq 4) -and ([double]$rotBack -eq 0.5)
            $saveAfter = Invoke-Tool -Id ($caseTag + '_save') -Tool 'editor_save_scene' -Arguments @{}
            $shaAfter = Get-FileSha $scenePath
            $refused = ($code -eq -32602) -and ($null -eq $env.result) -and $unchanged -and ($shaAfter -eq $shaCase)
            Add-Check ('D1_component_' + $bad.label + '_' + $slot + '_refused_and_nothing_written') $refused ("code={0} result_is_null={1} position={2} rotation={3} sha_before={4} sha_after={5} message='{6}'" -f $code, ($null -eq $env.result), (ConvertTo-CompactJson $readBack), (ConvertTo-CompactJson $rotBack), $shaCase, $shaAfter, (Get-ErrorMessage $env))
        }
    }

    # The same rule on the other composite shapes: Vector3, Vector2i (no such
    # property on Node2D, so it is covered by the doctest) and Color, plus the
    # "extra keys" case that used to be silently ignored.
    $shaCase = Reset-Baseline -Tag 'R2_colour'
    $colour = Invoke-Tool -Id 'B4_colour_component' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'modulate'; value = @{ r = 'abc'; g = 0; b = 0 } }
    $colourRead = Get-EditorNodeProperty -Id 'B5_colour_read' -Path 'Actor' -Property 'modulate'
    $saveColour = Invoke-Tool -Id 'B5b_colour_save' -Tool 'editor_save_scene' -Arguments @{}
    $shaColour = Get-FileSha $scenePath
    Add-Check 'D1_colour_component_refused' (((Get-ErrorCode $colour) -eq -32602) -and ($null -eq $colour.result) -and ([double]$colourRead.r -eq 1) -and ([double]$colourRead.g -eq 1) -and ($shaColour -eq $shaCase)) ("code={0} modulate={1} sha_before={2} sha_after={3} message='{4}'" -f (Get-ErrorCode $colour), (ConvertTo-CompactJson $colourRead), $shaCase, $shaColour, (Get-ErrorMessage $colour))

    $shaCase = Reset-Baseline -Tag 'R3_extrakey'
    $extraKey = Invoke-Tool -Id 'B6_extra_key' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = @{ x = 5; y = 6; spare = 'ignored' } }
    $extraRead = Get-EditorNodeProperty -Id 'B7_extra_key_read' -Path 'Actor' -Property 'position'
    Add-Check 'D1_extra_key_ignored_like_the_engine_does' (((Get-ErrorCode $extraKey) -eq 0) -and ([double]$extraRead.x -eq 5) -and ([double]$extraRead.y -eq 6)) ("code={0} position={1} (an unknown member is not a component and is ignored, as before)" -f (Get-ErrorCode $extraKey), (ConvertTo-CompactJson $extraRead))

    # =======================================================================
    # B. D-1/D-2 through the two batch paths (all-or-nothing, pre-write refusal)
    # =======================================================================
    $shaCase = Reset-Baseline -Tag 'R4_batchpos'
    $batchPos = Invoke-Tool -Id 'C1_batch_component' -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Node2D'; property = 'position'; value = @{ x = 'abc'; y = 1 } }
    $actorAfterBatch = Get-EditorNodeProperty -Id 'C2_batch_read_actor' -Path 'Actor' -Property 'position'
    $mainAfterBatch = Get-EditorNodeProperty -Id 'C3_batch_read_main' -Path '.' -Property 'position'
    $saveBatch = Invoke-Tool -Id 'C4_batch_save' -Tool 'editor_save_scene' -Arguments @{}
    $shaBatch = Get-FileSha $scenePath
    Add-Check 'D1_set_property_batch_refused_before_any_write' (((Get-ErrorCode $batchPos) -eq -32602) -and ([double]$actorAfterBatch.x -eq 3) -and ([double]$mainAfterBatch.x -eq 0) -and ($shaBatch -eq $shaCase)) ("code={0} Actor.position={1} Main.position={2} sha_before={3} sha_after={4} message='{5}'" -f (Get-ErrorCode $batchPos), (ConvertTo-CompactJson $actorAfterBatch), (ConvertTo-CompactJson $mainAfterBatch), $shaCase, $shaBatch, (Get-ErrorMessage $batchPos))

    $shaCase = Reset-Baseline -Tag 'R5_addnodes'
    $addBatch = Invoke-Tool -Id 'C5_add_nodes_batch_component' -Tool 'editor_add_nodes_batch' -Arguments @{ nodes = @(@{ type = 'Node2D'; name = 'MCP020BadA'; properties = @{ position = @{ x = 'abc'; y = 1 } } }) }
    $nodesAfter = Invoke-Tool -Id 'C6_add_nodes_read' -Tool 'editor_find_nodes_by_type' -Arguments @{ type = 'Node2D' }
    $nodePayload = Get-Payload $nodesAfter
    $leaked = @(@($nodePayload.nodes) | Where-Object { [string]$_.path -eq 'MCP020BadA' })
    $saveAdd = Invoke-Tool -Id 'C7_add_nodes_save' -Tool 'editor_save_scene' -Arguments @{}
    $shaAdd = Get-FileSha $scenePath
    Add-Check 'D1_add_nodes_batch_component_refused_and_rolled_back' (((Get-ErrorCode $addBatch) -eq -32602) -and ([string]$addBatch.error.data.batch.status -eq 'rolled_back') -and ($leaked.Count -eq 0) -and ($shaAdd -eq $shaCase)) ("code={0} batch_status={1} MCP020BadA leaked={2} sha_before={3} sha_after={4}" -f (Get-ErrorCode $addBatch), [string]$addBatch.error.data.batch.status, $leaked.Count, $shaCase, $shaAdd)

    $shaCase = Reset-Baseline -Tag 'R6_batchrot'
    $batchRot = Invoke-Tool -Id 'C8_batch_rotation_string' -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Node2D'; property = 'rotation'; value = 'abc' }
    $rotAfterBatch = Get-EditorNodeProperty -Id 'C9_batch_read_rotation' -Path 'Actor' -Property 'rotation'
    $saveBatch2 = Invoke-Tool -Id 'C10_batch_save2' -Tool 'editor_save_scene' -Arguments @{}
    $shaBatch2 = Get-FileSha $scenePath
    Add-Check 'D2_set_property_batch_string_refused' (((Get-ErrorCode $batchRot) -eq -32602) -and ([double]$rotAfterBatch -eq 0.5) -and ($shaBatch2 -eq $shaCase)) ("code={0} Actor.rotation={1} sha_before={2} sha_after={3} message='{4}'" -f (Get-ErrorCode $batchRot), (ConvertTo-CompactJson $rotAfterBatch), $shaCase, $shaBatch2, (Get-ErrorMessage $batchRot))

    $shaCase = Reset-Baseline -Tag 'R7_addnodesrot'
    $addBatch2 = Invoke-Tool -Id 'C11_add_nodes_batch_string' -Tool 'editor_add_nodes_batch' -Arguments @{ nodes = @(@{ type = 'Node2D'; name = 'MCP020BadB'; properties = @{ rotation = 'abc' } }) }
    $nodesAfter2 = Invoke-Tool -Id 'C12_add_nodes_read2' -Tool 'editor_find_nodes_by_type' -Arguments @{ type = 'Node2D' }
    $nodePayload2 = Get-Payload $nodesAfter2
    $leaked2 = @(@($nodePayload2.nodes) | Where-Object { [string]$_.path -eq 'MCP020BadB' })
    Add-Check 'D2_add_nodes_batch_string_refused_and_rolled_back' (((Get-ErrorCode $addBatch2) -eq -32602) -and ([string]$addBatch2.error.data.batch.status -eq 'rolled_back') -and ($leaked2.Count -eq 0)) ("code={0} batch_status={1} MCP020BadB leaked={2} message='{3}'" -f (Get-ErrorCode $addBatch2), [string]$addBatch2.error.data.batch.status, $leaked2.Count, (Get-ErrorMessage $addBatch2))

    # =======================================================================
    # C. D-2: the six value classes on a float property, an int property and the
    #    composite property (9888), then the same on 9889.
    # =======================================================================
    $classes = @(
        @{ label = 'integer'; value = 3; expect = 'accept' },
        @{ label = 'float'; value = 1.25; expect = 'accept' },
        @{ label = 'string'; value = 'abc'; expect = 'refuse' },
        @{ label = 'composite'; value = @{ z = 9 }; expect = 'refuse' },
        @{ label = 'array'; value = @(1, 2); expect = 'refuse' },
        @{ label = 'null'; value = $null; expect = 'refuse' }
    )
    foreach ($class in $classes) {
        $caseTag = 'R8_' + $class.label
        $shaCase = Reset-Baseline -Tag $caseTag
        $env = Invoke-Tool -Id ('D1_rotation_' + $class.label) -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'rotation'; value = $class.value }
        $read = Get-EditorNodeProperty -Id ('D2_rotation_' + $class.label + '_read') -Path 'Actor' -Property 'rotation'
        $other = Get-EditorNodeProperty -Id ('D2_rotation_' + $class.label + '_read2') -Path 'Actor' -Property 'position'
        $saveCase = Invoke-Tool -Id ($caseTag + '_save') -Tool 'editor_save_scene' -Arguments @{}
        $shaCaseAfter = Get-FileSha $scenePath
        if ($class.expect -eq 'refuse') {
            $ok = ((Get-ErrorCode $env) -eq -32602) -and ([double]$read -eq 0.5) -and ([double]$other.x -eq 3) -and ($shaCaseAfter -eq $shaCase)
        } else {
            $ok = ((Get-ErrorCode $env) -eq 0) -and ($null -ne (Get-Payload $env))
        }
        Add-Check ('D2_rotation_' + $class.label + '_' + $class.expect) $ok ("code={0} rotation={1} position={2} sha_before={3} sha_after={4} message='{5}'" -f (Get-ErrorCode $env), (ConvertTo-CompactJson $read), (ConvertTo-CompactJson $other), $shaCase, $shaCaseAfter, (Get-ErrorMessage $env))
    }

    # The int property: a string that spells a whole number is accepted, a
    # garbage string and a fractional spelling are refused.
    $shaCase = Reset-Baseline -Tag 'R9_zgood'
    $intGood = Invoke-Tool -Id 'D5_zindex_string_good' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'z_index'; value = '7' }
    $intGoodRead = Get-EditorNodeProperty -Id 'D6_zindex_good_read' -Path 'Actor' -Property 'z_index'
    Add-Check 'D2_int_parseable_string_accepted' (((Get-ErrorCode $intGood) -eq 0) -and ([int]$intGoodRead -eq 7)) ("code={0} z_index={1}" -f (Get-ErrorCode $intGood), (ConvertTo-CompactJson $intGoodRead))

    $shaCase = Reset-Baseline -Tag 'R10_zbad'
    $intBad = Invoke-Tool -Id 'D7_zindex_string_bad' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'z_index'; value = 'abc' }
    $intBadRead = Get-EditorNodeProperty -Id 'D8_zindex_bad_read' -Path 'Actor' -Property 'z_index'
    $intOtherRead = Get-EditorNodeProperty -Id 'D8b_zindex_bad_read2' -Path 'Actor' -Property 'rotation'
    $saveInt = Invoke-Tool -Id 'D9_zindex_save' -Tool 'editor_save_scene' -Arguments @{}
    $shaInt = Get-FileSha $scenePath
    Add-Check 'D2_int_garbage_string_refused' (((Get-ErrorCode $intBad) -eq -32602) -and ([int]$intBadRead -eq 0) -and ([double]$intOtherRead -eq 0.5) -and ($shaInt -eq $shaCase)) ("code={0} z_index={1} rotation={2} sha_before={3} sha_after={4} message='{5}'" -f (Get-ErrorCode $intBad), (ConvertTo-CompactJson $intBadRead), (ConvertTo-CompactJson $intOtherRead), $shaCase, $shaInt, (Get-ErrorMessage $intBad))

    $intFrac = Invoke-Tool -Id 'D10_zindex_string_fraction' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'z_index'; value = '1.5' }
    Add-Check 'D2_int_fractional_string_refused' ((Get-ErrorCode $intFrac) -eq -32602) ("code={0} message='{1}'" -f (Get-ErrorCode $intFrac), (Get-ErrorMessage $intFrac))
    $intHuge = Invoke-Tool -Id 'D10b_zindex_string_huge' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'z_index'; value = '99999999999999999999' }
    Add-Check 'D2_int_out_of_range_string_refused' ((Get-ErrorCode $intHuge) -eq -32602) ("code={0} message='{1}'" -f (Get-ErrorCode $intHuge), (Get-ErrorMessage $intHuge))

    # The composite property takes only objects (and not the string grammar).
    foreach ($class in $classes) {
        if ($class.label -eq 'integer' -or $class.label -eq 'float') { continue }
        $caseTag = 'R11_' + $class.label
        $shaCase = Reset-Baseline -Tag $caseTag
        $env = Invoke-Tool -Id ('E1_position_' + $class.label) -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = $class.value }
        $read = Get-EditorNodeProperty -Id ('E2_position_' + $class.label + '_read') -Path 'Actor' -Property 'position'
        $saveCase = Invoke-Tool -Id ($caseTag + '_save') -Tool 'editor_save_scene' -Arguments @{}
        $shaCaseAfter = Get-FileSha $scenePath
        Add-Check ('D1_position_' + $class.label + '_refused') (((Get-ErrorCode $env) -eq -32602) -and ([double]$read.x -eq 3) -and ([double]$read.y -eq 4) -and ($shaCaseAfter -eq $shaCase)) ("code={0} position={1} sha_before={2} sha_after={3} message='{4}'" -f (Get-ErrorCode $env), (ConvertTo-CompactJson $read), $shaCase, $shaCaseAfter, (Get-ErrorMessage $env))
    }
    $posString = Invoke-Tool -Id 'E3_position_string_grammar' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = 'Vector2(1,1)' }
    Add-Check 'D1_position_string_grammar_still_refused' ((Get-ErrorCode $posString) -eq -32602) ("code={0} message='{1}'" -f (Get-ErrorCode $posString), (Get-ErrorMessage $posString))

    # The accepted half, through the same tool: a legal object, a legal number.
    $goodPos = Invoke-Tool -Id 'E4_position_good' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = @{ x = 5; y = 6 } }
    $goodPosRead = Get-EditorNodeProperty -Id 'E5_position_good_read' -Path 'Actor' -Property 'position'
    Add-Check 'D1_legal_object_still_writes' (((Get-ErrorCode $goodPos) -eq 0) -and ([double]$goodPosRead.x -eq 5) -and ([double]$goodPosRead.y -eq 6)) ("code={0} position={1}" -f (Get-ErrorCode $goodPos), (ConvertTo-CompactJson $goodPosRead))
    $nothing = Invoke-Tool -Id 'E6_restore_final' -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = @{ x = 3; y = 4 } }

    # ---- 9889: the same two defects, in the game process -------------------
    $gameBadComponent = Invoke-Tool -Id 'F1_game_component' -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'Actor'; property = 'position'; value = @{ x = 'abc'; y = 1 } } -Port $GamePort
    $gamePosRead = Get-GameNodeProperty -Id 'F2_game_position_read' -Path 'Actor' -Property 'position'
    Add-Check 'D1_game_set_node_property_component_refused' (((Get-ErrorCode $gameBadComponent) -eq -32602) -and ([double]$gamePosRead.x -eq 3) -and ([double]$gamePosRead.y -eq 4)) ("code={0} Actor.position={1} message='{2}'" -f (Get-ErrorCode $gameBadComponent), (ConvertTo-CompactJson $gamePosRead), (Get-ErrorMessage $gameBadComponent))
    $gameBadString = Invoke-Tool -Id 'F3_game_string' -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'Actor'; property = 'rotation'; value = 'abc' } -Port $GamePort
    $gameRotRead = Get-GameNodeProperty -Id 'F4_game_rotation_read' -Path 'Actor' -Property 'rotation'
    Add-Check 'D2_game_set_node_property_string_refused' (((Get-ErrorCode $gameBadString) -eq -32602) -and ([double]$gameRotRead -eq 0.5)) ("code={0} Actor.rotation={1} message='{2}'" -f (Get-ErrorCode $gameBadString), (ConvertTo-CompactJson $gameRotRead), (Get-ErrorMessage $gameBadString))
    $gameGoodString = Invoke-Tool -Id 'F5_game_int_string' -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'Actor'; property = 'z_index'; value = '9' } -Port $GamePort
    $gameZRead = Get-GameNodeProperty -Id 'F6_game_zindex_read' -Path 'Actor' -Property 'z_index'
    Add-Check 'D2_game_parseable_int_string_accepted' (((Get-ErrorCode $gameGoodString) -eq 0) -and ([int]$gameZRead -eq 9)) ("code={0} Actor.z_index={1}" -f (Get-ErrorCode $gameGoodString), (ConvertTo-CompactJson $gameZRead))

    # =======================================================================
    # G. D-3: the two assertion entries' failure field sets
    # =======================================================================
    $toolNodeFail = Invoke-Tool -Id 'G1_assert_node_tool_fail' -Tool 'running_game_assert_node_state' -Arguments @{ node_path = '.'; property = 'name'; expected = 'NotRoot'; operator = 'eq' } -Port $GamePort
    $toolNodePayload = Get-Payload $toolNodeFail
    Add-Check 'D3_node_tool_failure_carries_a_reason' (($null -ne $toolNodePayload) -and ($toolNodePayload.passed -eq $false) -and ($null -ne $toolNodePayload.reason) -and (([string]$toolNodePayload.actual) -eq 'Main') -and (([string]$toolNodePayload.expected) -eq 'NotRoot')) ("payload=" + (ConvertTo-CompactJson $toolNodePayload))

    $scenarioNode = Invoke-Tool -Id 'G2_assert_node_scenario_fail' -Tool 'running_game_run_test_scenario' -Arguments @{ steps = @(@{ type = 'assert'; node_path = '.'; property = 'name'; expected = 'NotRoot'; operator = 'eq' }) } -Port $GamePort -MaxTimeSec 120
    $scenarioNodePayload = Get-Payload $scenarioNode
    $scenarioNodeStep = @($scenarioNodePayload.results)[0]
    Add-Check 'D3_node_scenario_failure_carries_a_reason' (($null -ne $scenarioNodeStep) -and ($scenarioNodeStep.passed -eq $false) -and ($null -ne $scenarioNodeStep.reason)) ("step=" + (ConvertTo-CompactJson $scenarioNodeStep))

    $toolNodeKeys = Get-KeySet $toolNodePayload
    $scenarioNodeCore = Remove-Keys -KeySet (Get-KeySet $scenarioNodeStep) -Drop @('type', 'step')
    $nodeKeyDiff = @(Compare-Object -ReferenceObject $toolNodeKeys -DifferenceObject $scenarioNodeCore)
    $sameReason = ($null -ne $toolNodePayload.reason) -and ($null -ne $scenarioNodeStep.reason) -and ([string]$toolNodePayload.reason -ceq [string]$scenarioNodeStep.reason)
    Add-Check 'D3_node_entries_share_one_failure_field_set' (($nodeKeyDiff.Count -eq 0) -and $sameReason -and ($toolNodeKeys -ccontains 'reason')) ("tool keys=[{0}] scenario keys(minus type/step)=[{1}] key_diff_count={2} reason_equal={3} reason='{4}'" -f ($toolNodeKeys -join ','), ($scenarioNodeCore -join ','), $nodeKeyDiff.Count, $sameReason, [string]$toolNodePayload.reason)

    $toolTextFail = Invoke-Tool -Id 'G3_assert_text_tool_fail' -Tool 'running_game_assert_screen_text' -Arguments @{ text = 'NoSuchTextAnywhere'; partial = $true } -Port $GamePort
    $toolTextPayload = Get-Payload $toolTextFail
    Add-Check 'D3_text_tool_failure_carries_a_reason' (($null -ne $toolTextPayload) -and ($toolTextPayload.passed -eq $false) -and ($null -ne $toolTextPayload.reason)) ("payload=" + (ConvertTo-CompactJson $toolTextPayload))

    $scenarioText = Invoke-Tool -Id 'G4_assert_text_scenario_fail' -Tool 'running_game_run_test_scenario' -Arguments @{ steps = @(@{ type = 'assert'; text = 'NoSuchTextAnywhere'; partial = $true }) } -Port $GamePort -MaxTimeSec 120
    $scenarioTextPayload = Get-Payload $scenarioText
    $scenarioTextStep = @($scenarioTextPayload.results)[0]
    $toolTextKeys = Get-KeySet $toolTextPayload
    $scenarioTextCore = Remove-Keys -KeySet (Get-KeySet $scenarioTextStep) -Drop @('type', 'step')
    $textKeyDiff = @(Compare-Object -ReferenceObject $toolTextKeys -DifferenceObject $scenarioTextCore)
    $sameTextReason = ($null -ne $toolTextPayload.reason) -and ($null -ne $scenarioTextStep.reason) -and ([string]$toolTextPayload.reason -ceq [string]$scenarioTextStep.reason)
    Add-Check 'D3_text_entries_share_one_failure_field_set' (($textKeyDiff.Count -eq 0) -and $sameTextReason -and ($toolTextKeys -ccontains 'reason')) ("tool keys=[{0}] scenario keys(minus type/step)=[{1}] key_diff_count={2} reason_equal={3} reason='{4}'" -f ($toolTextKeys -join ','), ($scenarioTextCore -join ','), $textKeyDiff.Count, $sameTextReason, [string]$toolTextPayload.reason)

    # =======================================================================
    # H. the cross-scene all-or-nothing transaction with a good + a broken file
    # =======================================================================
    $onePath = Join-Path $Project 'cross\one.tscn'
    $twoPath = Join-Path $Project 'cross\two.tscn'
    $brokenPath = Join-Path $Project 'cross\broken.tscn'
    $oneBefore = Get-FileSha $onePath
    $twoBefore = Get-FileSha $twoPath

    $crossBroken = Invoke-Tool -Id 'H1_cross_scene_broken' -Tool 'project_set_node_property_across_scenes' -Arguments @{ type = 'Node2D'; property = 'z_index'; value = 5; path_filter = 'res://cross'; force = $true; dry_run = $false }
    $oneAfter = Get-FileSha $onePath
    $twoAfter = Get-FileSha $twoPath
    $crossErrors = @($crossBroken.error.data.scenes.errors)
    $crossLooked = (Get-ErrorCode $crossBroken) -ne 0
    Add-Check 'H1_cross_scene_broken_file_refuses_the_whole_call' ($crossLooked -and ($crossErrors.Count -ge 1) -and ((Get-Suggestion $crossBroken).Contains('Nothing was written')) -and ($oneAfter -eq $oneBefore) -and ($twoAfter -eq $twoBefore)) ("code={0} errors={1} suggestion='{2}' one.tscn sha before={3} after={4} two.tscn sha before={5} after={6}" -f (Get-ErrorCode $crossBroken), (ConvertTo-CompactJson $crossErrors), (Get-Suggestion $crossBroken), $oneBefore, $oneAfter, $twoBefore, $twoAfter)

    # The broken file is removed again: the *same* call over the same filter now
    # has to write both scenes.
    Remove-Item -Force $brokenPath -ErrorAction SilentlyContinue

    $crossDry = Invoke-Tool -Id 'H2_cross_scene_dry_run' -Tool 'project_set_node_property_across_scenes' -Arguments @{ type = 'Node2D'; property = 'z_index'; value = 5; path_filter = 'res://cross'; force = $true; dry_run = $true }
    $crossDryPayload = Get-Payload $crossDry
    $oneDry = Get-FileSha $onePath
    Add-Check 'H2_cross_scene_dry_run_writes_nothing' (($null -ne $crossDryPayload) -and ([int]$crossDryPayload.total_nodes -ge 1) -and ([int]$crossDryPayload.total_scenes -ge 1) -and ($oneDry -eq $oneBefore)) ("payload=" + (ConvertTo-CompactJson $crossDryPayload) + " one.tscn sha before={0} after={1}" -f $oneBefore, $oneDry)

    $crossGood = Invoke-Tool -Id 'H3_cross_scene_all_good' -Tool 'project_set_node_property_across_scenes' -Arguments @{ type = 'Node2D'; property = 'z_index'; value = 5; path_filter = 'res://cross'; force = $true; dry_run = $false }
    $crossGoodPayload = Get-Payload $crossGood
    $oneWritten = Get-FileSha $onePath
    $twoWritten = Get-FileSha $twoPath
    $oneText = ''
    try { $oneText = [string](Get-Payload (Invoke-Tool -Id 'H4_read_one_scene' -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://cross/one.tscn' })).content } catch { }
    Add-Check 'H3_cross_scene_both_good_files_written' (($null -ne $crossGoodPayload) -and ([int]$crossGoodPayload.total_scenes -eq 2) -and ($oneWritten -ne $oneBefore) -and ($twoWritten -ne $twoBefore) -and ($oneText.Contains('z_index = 5'))) ("payload=" + (ConvertTo-CompactJson $crossGoodPayload) + " one.tscn {0}->{1} two.tscn {2}->{3} read_back_has_z_index={4}" -f $oneBefore, $oneWritten, $twoBefore, $twoWritten, $oneText.Contains('z_index = 5'))

    # =======================================================================
    # I. editor_analyze_screenshot_diff against engine-encoded PNGs
    # =======================================================================
    $makePngs = @"
var a := Image.create(4, 4, false, Image.FORMAT_RGBA8)
a.fill(Color(0, 0, 0, 1))
a.save_png("res://diff_a.png")
var b := Image.create(4, 4, false, Image.FORMAT_RGBA8)
b.fill(Color(0, 0, 0, 1))
b.set_pixel(1, 1, Color(1, 0, 0, 1))
b.save_png("res://diff_b.png")
return [a.get_width(), a.get_height(), b.get_width(), b.get_height()]
"@
    $pngMake = Invoke-Tool -Id 'I1_make_pngs' -Tool 'editor_execute_gdscript' -Arguments @{ code = $makePngs }
    $pngMakePayload = Get-Payload $pngMake
    $pngA = Join-Path $Project 'diff_a.png'
    $pngB = Join-Path $Project 'diff_b.png'
    Add-Check 'I1_engine_encoded_both_pngs' (($null -ne $pngMakePayload) -and (Test-Path $pngA) -and (Test-Path $pngB)) ("result=" + (ConvertTo-CompactJson $pngMakePayload) + " a=" + (Get-FileSha $pngA) + " b=" + (Get-FileSha $pngB))

    $diffSame = Invoke-Tool -Id 'I2_diff_identical' -Tool 'editor_analyze_screenshot_diff' -Arguments @{ image_a = 'res://diff_a.png'; image_b = 'res://diff_a.png' }
    $diffSamePayload = Get-Payload $diffSame
    Add-Check 'I2_identical_pair_is_identical' (($null -ne $diffSamePayload) -and ($diffSamePayload.identical -eq $true) -and ([int]$diffSamePayload.changed_pixels -eq 0) -and ([int]$diffSamePayload.total_pixels -eq 16) -and ([double]$diffSamePayload.diff_percentage -eq 0) -and ([int]$diffSamePayload.width -eq 4) -and ([int]$diffSamePayload.height -eq 4)) ("payload=" + (ConvertTo-CompactJson $diffSamePayload))

    $diffDifferent = Invoke-Tool -Id 'I3_diff_changed' -Tool 'editor_analyze_screenshot_diff' -Arguments @{ image_a = 'res://diff_a.png'; image_b = 'res://diff_b.png' }
    $diffDifferentPayload = Get-Payload $diffDifferent
    Add-Check 'I3_one_changed_pixel_is_reported' (($null -ne $diffDifferentPayload) -and ($diffDifferentPayload.identical -eq $false) -and ([int]$diffDifferentPayload.changed_pixels -eq 1) -and ([double]$diffDifferentPayload.diff_percentage -eq 6.25) -and ([double]$diffDifferentPayload.threshold -eq 10) -and (-not [string]::IsNullOrEmpty([string]$diffDifferentPayload.diff_image_base64))) ("payload=" + (ConvertTo-CompactJson $diffDifferentPayload))

    $diffMasked = Invoke-Tool -Id 'I4_diff_threshold_255' -Tool 'editor_analyze_screenshot_diff' -Arguments @{ image_a = 'res://diff_a.png'; image_b = 'res://diff_b.png'; threshold = 255 }
    $diffMaskedPayload = Get-Payload $diffMasked
    Add-Check 'I4_threshold_255_masks_the_change' (($null -ne $diffMaskedPayload) -and ($diffMaskedPayload.identical -eq $true) -and ([int]$diffMaskedPayload.changed_pixels -eq 0)) ("payload=" + (ConvertTo-CompactJson $diffMaskedPayload))

    $diffZero = Invoke-Tool -Id 'I5_diff_threshold_0' -Tool 'editor_analyze_screenshot_diff' -Arguments @{ image_a = 'res://diff_a.png'; image_b = 'res://diff_b.png'; threshold = 0 }
    $diffZeroPayload = Get-Payload $diffZero
    Add-Check 'I5_threshold_0_keeps_the_change' (($null -ne $diffZeroPayload) -and ([int]$diffZeroPayload.changed_pixels -eq 1)) ("payload=" + (ConvertTo-CompactJson $diffZeroPayload))

    $diffHigh = Invoke-Tool -Id 'I6_diff_threshold_300' -Tool 'editor_analyze_screenshot_diff' -Arguments @{ image_a = 'res://diff_a.png'; image_b = 'res://diff_b.png'; threshold = 300 }
    $diffLow = Invoke-Tool -Id 'I7_diff_threshold_minus1' -Tool 'editor_analyze_screenshot_diff' -Arguments @{ image_a = 'res://diff_a.png'; image_b = 'res://diff_b.png'; threshold = -1 }
    Add-Check 'I6_threshold_out_of_range_is_32602' (((Get-ErrorCode $diffHigh) -eq -32602) -and ((Get-ErrorCode $diffLow) -eq -32602)) ("300 -> code={0} message='{1}'; -1 -> code={2} message='{3}'" -f (Get-ErrorCode $diffHigh), (Get-ErrorMessage $diffHigh), (Get-ErrorCode $diffLow), (Get-ErrorMessage $diffLow))

    $diffMissing = Invoke-Tool -Id 'I8_diff_missing_arg' -Tool 'editor_analyze_screenshot_diff' -Arguments @{ image_b = 'res://diff_b.png' }
    Add-Check 'I8_missing_image_a_is_32602' ((Get-ErrorCode $diffMissing) -eq -32602) ("code={0} message='{1}'" -f (Get-ErrorCode $diffMissing), (Get-ErrorMessage $diffMissing))

    # =======================================================================
    # J. the tools that share the same coercion helper but write a *resource* -
    #    the rest of the D-1/D-2 behaviour-change surface the task book asks to
    #    be measured. `project_create_resource` / `project_edit_resource` /
    #    `editor_add_resource_to_node_property` go through the one
    #    `coerce_to_property_type` directly (no component shaping step), so the
    #    defect here was visible as "an array element string became 0.0" and an
    #    enum-sized integer given a string.
    # =======================================================================
    $createBad = Invoke-Tool -Id 'J1_create_resource_bad_element' -Tool 'project_create_resource' -Arguments @{ path = 'res://probe_gradient.tres'; type = 'Gradient'; properties = @{ offsets = @('abc') } }
    $created = Test-Path (Join-Path $Project 'probe_gradient.tres')
    Add-Check 'J1_project_create_resource_refuses_a_bad_element' (((Get-ErrorCode $createBad) -eq -32602) -and (-not $created)) ("code={0} file_created={1} message='{2}'" -f (Get-ErrorCode $createBad), $created, (Get-ErrorMessage $createBad))

    $createGood = Invoke-Tool -Id 'J2_create_resource_good' -Tool 'project_create_resource' -Arguments @{ path = 'res://probe_gradient.tres'; type = 'Gradient'; properties = @{ offsets = @(0.0, 1.0) } }
    Add-Check 'J2_project_create_resource_legal_array_still_writes' ((Get-ErrorCode $createGood) -eq 0) ("code={0} payload={1}" -f (Get-ErrorCode $createGood), (ConvertTo-CompactJson (Get-Payload $createGood)))

    $probePath = Join-Path $Project 'probe_gradient.tres'
    $probeBefore = Get-FileSha $probePath
    $editBad = Invoke-Tool -Id 'J3_edit_resource_bad_element' -Tool 'project_edit_resource' -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ offsets = @('abc') } }
    $probeAfter = Get-FileSha $probePath
    Add-Check 'J3_project_edit_resource_refuses_a_bad_element' (((Get-ErrorCode $editBad) -eq -32602) -and ($probeAfter -eq $probeBefore)) ("code={0} sha_before={1} sha_after={2} message='{3}'" -f (Get-ErrorCode $editBad), $probeBefore, $probeAfter, (Get-ErrorMessage $editBad))

    $materialBefore = Get-EditorNodeProperty -Id 'J3b_material_before' -Path 'Actor' -Property 'material'
    $addResourceBad = Invoke-Tool -Id 'J4_add_resource_bad_value' -Tool 'editor_add_resource_to_node_property' -Arguments @{ node_path = 'Actor'; property = 'material'; resource_type = 'CanvasItemMaterial'; resource_properties = @{ light_mode = 'abc' } }
    $addResourceRead = Get-EditorNodeProperty -Id 'J5_add_resource_read' -Path 'Actor' -Property 'material'
    Add-Check 'J4_editor_add_resource_to_node_property_refuses_a_bad_value' (((Get-ErrorCode $addResourceBad) -eq -32602) -and ((ConvertTo-CompactJson $materialBefore) -ceq (ConvertTo-CompactJson $addResourceRead))) ("code={0} material before={1} after={2} message='{3}'" -f (Get-ErrorCode $addResourceBad), (ConvertTo-CompactJson $materialBefore), (ConvertTo-CompactJson $addResourceRead), (Get-ErrorMessage $addResourceBad))
    $addResourceGood = Invoke-Tool -Id 'J6_add_resource_good' -Tool 'editor_add_resource_to_node_property' -Arguments @{ node_path = 'Actor'; property = 'material'; resource_type = 'CanvasItemMaterial'; resource_properties = @{ light_mode = 2 } }
    Add-Check 'J6_editor_add_resource_to_node_property_legal_value_still_writes' ((Get-ErrorCode $addResourceGood) -eq 0) ("code={0} payload={1}" -f (Get-ErrorCode $addResourceGood), (ConvertTo-CompactJson (Get-Payload $addResourceGood)))

    $settingProject = Join-Path $Project 'project.godot'
    $settingBefore = Get-FileSha $settingProject
    $seedIntSetting = Invoke-Tool -Id 'J7_seed_int_setting' -Tool 'project_set_setting' -Arguments @{ key = 'mcp020/probe_int'; type = 'int'; value = 5 }
    $settingBad = Invoke-Tool -Id 'J8_setting_bad_string' -Tool 'project_set_setting' -Arguments @{ key = 'mcp020/probe_int'; value = 'abc' }
    $settingRead = Get-Payload (Invoke-Tool -Id 'J9_read_int_setting' -Tool 'project_get_settings' -Arguments @{ prefix = 'mcp020/' })
    $settingAfter = Get-FileSha $settingProject
    Add-Check 'J7_project_set_setting_refuses_a_bad_string' (((Get-ErrorCode $seedIntSetting) -eq 0) -and ((Get-ErrorCode $settingBad) -eq -32602) -and ((ConvertTo-CompactJson $settingRead).Contains('5'))) ("seed code={0}; value 'abc' into an int setting -> code={1} message='{2}'; project.godot sha before={3} after={4}" -f (Get-ErrorCode $seedIntSetting), (Get-ErrorCode $settingBad), (Get-ErrorMessage $settingBad), $settingBefore, $settingAfter)
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
