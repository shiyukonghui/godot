# ===========================================================================
#  mcp022_unified_narrowing_gate_evidence.ps1
#
#  TASK-022 wire evidence:
#    * D-4  - the unified "slot width" gate: the counterexample matrix across the
#             five write paths, each case with the **four evidence forms** the
#             task book demands (error code / finite echo / clean file bytes /
#             an independent reader still seeing the old value);
#    * D-5  - `project_create_resource`'s read-back shape;
#    * D-6  - the cross-process test report (game writes `user://`, editor reads);
#    * the TASK-020 / TASK-021 regression faces (five component spellings, string
#             spellings, batch transaction) re-run to prove nothing regressed.
#
#  The harness (endpoint launcher, `curl.exe -s -o` evidence collector, sha256,
#  ConvertTo-Json request bodies, the scratch project) is the one
#  `mcp021_remaining_silent_value_surfaces_evidence.ps1` established: response
#  bodies always land in a file (never through a pipe), so the sha256 and the byte
#  count are the artefact's, not the console's.
#
#  Port discipline: 9877 belongs to the user's own Godot and is never touched;
#  this script only uses 9888 (editor) / 9889 (game). Nothing here pushes.
# ===========================================================================
param(
    [string]$Tag = 'task022'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877
$Scratch = Join-Path $env:TEMP ('mcp022-scratch-' + $Tag)
$LogRoot = Join-Path $env:TEMP ('mcp022-logs-' + $Tag)
$Evid = Join-Path $env:TEMP ('mcp022-evidence-' + $Tag)
$ResultFile = Join-Path $env:TEMP ('mcp022-results-' + $Tag + '.json')

$script:Results = New-Object System.Collections.Generic.List[object]
$script:EditorHandle = $null
$script:GameHandle = $null
$script:Checks = 0

foreach ($dir in @($LogRoot, $Evid)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
}

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

function Get-FileText {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '<missing>' }
    return [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($Path))
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
    return (ConvertTo-Json -InputObject $envelope -Depth 32 -Compress)
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

function Get-ErrorData {
    param($Envelope)
    if ($null -eq $Envelope -or $null -eq $Envelope.error) { return $null }
    return $Envelope.error.data
}

function ConvertTo-CompactJson {
    param($Object)
    if ($null -eq $Object) { return '<null>' }
    return (ConvertTo-Json -InputObject $Object -Depth 32 -Compress)
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

# ---------------------------------------------------------------------------
# The four evidence forms, as four independent functions.
#
# `Get-EditorNodeProperty` / `Get-GameNodeProperty` are the module's own read
# tools; `Get-EditorGdscript` / `Get-GameGdscript` are the *other* read channel
# (GDScript evaluation), which is the one the M4b audit used to see `inf` - a
# module read of a non-finite float answers `null` and therefore cannot witness
# the defect on its own (that is exactly why form 4 alone was never enough).
# ---------------------------------------------------------------------------
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

function Get-EditorGdscript {
    param([string]$Id, [string]$Code)
    $env = Invoke-Tool -Id $Id -Tool 'editor_execute_gdscript' -Arguments @{ code = $Code }
    $payload = Get-Payload $env
    if ($null -eq $payload) { return '<no-payload>' }
    return [string]$payload.result
}

function Get-GameGdscript {
    param([string]$Id, [string]$Code)
    $env = Invoke-Tool -Id $Id -Tool 'running_game_execute_gdscript' -Arguments @{ code = $Code } -Port $GamePort
    $payload = Get-Payload $env
    if ($null -eq $payload) { return '<no-payload>' }
    return [string]$payload.result
}

# `str()` of a float spells `inf`/`nan` explicitly, which is the only spelling a
# JSON answer would otherwise lose.
$EditorReadActorRotation = @'
var tree = Engine.get_main_loop()
var root = tree.get_edited_scene_root()
return str(root.get_node("Actor").rotation)
'@

$GameReadActorRotation = @'
var tree = Engine.get_main_loop()
var root = tree.current_scene
return str(root.get_node("Actor").rotation)
'@

# Form 2 of the evidence shape, read precisely.
#
# "The response's echo value must be finite" cannot mean "the word `inf` may not
# appear anywhere": the refusal message is *required* to state the value the
# engine's own copy would have written, and for an overflow that value is `inf`
# (the task book asks for it). What must not happen - and what the pre-TASK-022
# binary did - is a **success payload** whose `new_value` carries `1e99999`/`null`.
#
# So the test is: a refusal has **no** `result` payload at all, and its
# `error.data` carries no value-echo key. The engine-would-write spelling is then
# *recorded* next to it as evidence that the message is a diagnostic and not an
# echo.
function Test-NoValueEcho {
    param($Envelope)
    if ($null -eq $Envelope) { return $false }
    if ($null -ne $Envelope.result) { return $false }
    if ($null -eq $Envelope.error) { return $false }
    $data = $Envelope.error.data
    if ($null -ne $data) {
        foreach ($key in @('new_value', 'old_value', 'stored')) {
            if ($null -ne $data.$key) { return $false }
        }
    }
    return $true
}

# Does the refusal *name* the value the engine would have written? Recorded, not
# asserted on its own: an overflow message must say `inf`, an underflow one `0`.
function Get-EngineWouldWriteSpelling {
    param([string]$Text)
    if ($Text.Contains('inf')) { return 'inf (named in the refusal message)' }
    if ($Text.Contains('would write 0')) { return '0 (named in the refusal message)' }
    return '<not named>'
}

# Form 3: the bytes on disk must not spell a non-finite value either.
function Test-FileHasNoNonFinite {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $text = Get-FileText $Path
    if ($text.Contains('1e99999')) { return $false }
    if ([regex]::IsMatch($text, '(?i)(?<![a-z])(inf|nan)(?![a-z0-9])')) { return $false }
    return $true
}

# The same question asked of a *value* rather than of the bytes: is it a finite
# number? `$null` and the spellings of a non-finite value are all "no".
function Test-FiniteValue {
    param($Value)
    if ($null -eq $Value) { return $false }
    $double = 0.0
    if (-not [double]::TryParse(([string]$Value), [ref]$double)) { return $false }
    if ([double]::IsNaN($double) -or [double]::IsInfinity($double)) { return $false }
    return $true
}

# =============================================================================
# Scratch project:  Main/Actor is a Node2D whose rotation is the scalar member
# under test; `xscenes/good.tscn` carries two Node2Ds for the cross-scene path.
# =============================================================================
$MainScene = @"
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://main.gd" id="1_main"]

[node name="Main" type="Node2D"]
script = ExtResource("1_main")

[node name="Actor" type="Node2D" parent="."]
position = Vector2(3, 4)
rotation = 0.5
"@

$XScene = @"
[gd_scene format=3]

[node name="XRoot" type="Node2D"]

[node name="X1" type="Node2D" parent="."]
rotation = 0.5

[node name="X2" type="Node2D" parent="."]
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
    New-Item -ItemType Directory -Force -Path (Join-Path $Path 'xscenes') | Out-Null
    $project = @(
        'config_version=5',
        '',
        '[application]',
        'config/name="MCP022 narrowing-gate evidence"',
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
    Write-Utf8NoBom -Path (Join-Path $Path 'xscenes\good.tscn') -Text $XScene
    Write-Utf8NoBom -Path (Join-Path $Path 'main.gd') -Text $Script
}

$Script:MainScenePath = $null
$Script:XScenePath = $null

# Put the edited scene back into the known state **and** make that state the disk
# state, so every case starts from the same bytes.
function Reset-Baseline {
    param([string]$Tag)
    $null = Invoke-Tool -Id ($Tag + '_b0_pos') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = @{ x = 3; y = 4 } }
    $null = Invoke-Tool -Id ($Tag + '_b1_rot') -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'rotation'; value = 0.5 }
    $null = Invoke-Tool -Id ($Tag + '_b2_save') -Tool 'editor_save_scene' -Arguments @{}
    $null = Invoke-Tool -Id ($Tag + '_b3_save') -Tool 'editor_save_scene' -Arguments @{}
    return (Get-FileSha $Script:MainScenePath)
}

# ---------------------------------------------------------------------------
# The D-4 counterexample matrix for `editor_set_node_property` (path 1).
#
# `values` are the two controls and the six counterexamples the M4b audit
# measured. Every counterexample gets all four evidence forms; the controls prove
# the gate is a refusal of the unfittable and not of large numbers as such.
# ---------------------------------------------------------------------------
$CounterExamples = @(
    [pscustomobject]@{ name = '1e300'; value = 1.0e300; refused = $true },
    [pscustomobject]@{ name = '3.5e38'; value = 3.5e38; refused = $true },
    [pscustomobject]@{ name = 'neg_3.5e38'; value = -3.5e38; refused = $true },
    [pscustomobject]@{ name = 'string_1e300'; value = '1e300'; refused = $true },
    [pscustomobject]@{ name = '1e-300'; value = 1.0e-300; refused = $true },
    [pscustomobject]@{ name = '1e-46'; value = 1.0e-46; refused = $true },
    [pscustomobject]@{ name = '1e30_control'; value = 1.0e30; refused = $false },
    [pscustomobject]@{ name = '1e-30_control'; value = 1.0e-30; refused = $false }
)

function Test-Path1Scalar {
    $results = @()
    foreach ($case in $CounterExamples) {
        $tag = 'P1_' + $case.name
        $before = Reset-Baseline -Tag $tag
        $env = Invoke-Tool -Id $tag -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'rotation'; value = $case.value }
        $code = Get-ErrorCode $env
        $payload = Get-Payload $env
        $respFile = Join-Path $Evid ($tag + '.response.json')
        $respText = Get-FileText $respFile
        $saveEnv = Invoke-Tool -Id ($tag + '_save') -Tool 'editor_save_scene' -Arguments @{}
        $after = Get-FileSha $Script:MainScenePath
        $propsRead = Get-EditorNodeProperty -Id ($tag + '_read_props') -Path 'Actor' -Property 'rotation'
        $gdRead = Get-EditorGdscript -Id ($tag + '_read_gd') -Code $EditorReadActorRotation

        $formEcho = Test-NoValueEcho $env
        $formFile = Test-FileHasNoNonFinite -Path $Script:MainScenePath
        $formRead = (Test-FiniteValue $propsRead) -and ($gdRead -eq '0.5')
        if ($case.refused) {
            $formCode = ($code -eq -32602)
            $newValue = ''
            if ($null -ne $payload) { $newValue = ConvertTo-CompactJson $payload.new_value }
            Add-Check ($tag + '_code') $formCode ("code=" + $code + " new_value_echo=" + $newValue + " message=" + (Get-ErrorMessage $env))
            Add-Check ($tag + '_no_value_echo') $formEcho ("no result payload / no value echo in error.data; message names the engine's value: " + (Get-EngineWouldWriteSpelling -Text $respText))
            Add-Check ($tag + '_file_clean') $formFile ("scenes/main.tscn sha256 " + $before + " -> " + $after + "; no inf/nan in bytes")
            Add-Check ($tag + '_read_old') $formRead ("editor_get_node_properties rotation=" + (ConvertTo-CompactJson $propsRead) + " ; editor_execute_gdscript str(rotation)=" + $gdRead)
        } else {
            $formCode = ($code -eq 0) -and (Test-FiniteValue $payload.new_value)
            Add-Check ($tag + '_code') $formCode ("code=" + $code + " new_value=" + (ConvertTo-CompactJson $payload.new_value) + " (finite control)")
            Add-Check ($tag + '_echo_finite') (($null -ne $env.result) -and (Test-FiniteValue $payload.new_value) -and (-not $respText.Contains('1e99999'))) ("success payload with a finite new_value=" + (ConvertTo-CompactJson $payload.new_value))
            Add-Check ($tag + '_file_clean') $formFile ("scene file clean after save; sha256 " + $after)
            $formRead = ($gdRead -ne '0.5') -and ($gdRead -ne 'inf') -and ($gdRead -ne 'nan')
            Add-Check ($tag + '_read_new') $formRead ("the written value is finite and readable: gd=" + $gdRead + " props=" + (ConvertTo-CompactJson $propsRead))
        }
        $results += [pscustomobject]@{ case = $case.name; code = $code; before = $before; after = $after; props = (ConvertTo-CompactJson $propsRead); gd = $gdRead }
    }
    return $results
}

function Test-Path2Batch {
    $results = @()
    foreach ($case in @(
            [pscustomobject]@{ name = '1e300'; value = 1.0e300 },
            [pscustomobject]@{ name = '1e-300'; value = 1.0e-300 })) {
        $tag = 'P2_' + $case.name
        $before = Reset-Baseline -Tag $tag
        $env = Invoke-Tool -Id $tag -Tool 'editor_set_node_property_batch' -Arguments @{ node_type = 'Node2D'; property = 'rotation'; value = $case.value }
        $code = Get-ErrorCode $env
        $respText = Get-FileText (Join-Path $Evid ($tag + '.response.json'))
        $null = Invoke-Tool -Id ($tag + '_save') -Tool 'editor_save_scene' -Arguments @{}
        $after = Get-FileSha $Script:MainScenePath
        $propsRead = Get-EditorNodeProperty -Id ($tag + '_read_props') -Path 'Actor' -Property 'rotation'
        $gdRead = Get-EditorGdscript -Id ($tag + '_read_gd') -Code $EditorReadActorRotation
        Add-Check ($tag + '_code') ($code -eq -32602) ("code=" + $code + " message=" + (Get-ErrorMessage $env))
        Add-Check ($tag + '_no_value_echo') (Test-NoValueEcho $env) ("no result payload / no value echo; message names: " + (Get-EngineWouldWriteSpelling -Text $respText))
        Add-Check ($tag + '_file_clean') ((Test-FileHasNoNonFinite -Path $Script:MainScenePath) -and ($before -eq $after)) ("sha256 " + $before + " -> " + $after + "; no inf/nan in bytes")
        Add-Check ($tag + '_read_old') ((Test-FiniteValue $propsRead) -and ($gdRead -eq '0.5')) ("rotation=" + (ConvertTo-CompactJson $propsRead) + " gd=" + $gdRead)
        $results += [pscustomobject]@{ case = $case.name; code = $code; before = $before; after = $after; props = (ConvertTo-CompactJson $propsRead); gd = $gdRead }
    }
    return $results
}

function Test-Path3AddNodes {
    $results = @()
    foreach ($case in @(
            [pscustomobject]@{ name = '1e300'; value = 1.0e300 },
            [pscustomobject]@{ name = 'string_1e300'; value = '1e300' })) {
        $tag = 'P3_' + $case.name
        $before = Reset-Baseline -Tag $tag
        $nodes = @(@{ type = 'Node2D'; name = 'D4Node'; parent_path = '.'; properties = @{ rotation = $case.value } })
        $env = Invoke-Tool -Id $tag -Tool 'editor_add_nodes_batch' -Arguments @{ nodes = $nodes }
        $code = Get-ErrorCode $env
        $respText = Get-FileText (Join-Path $Evid ($tag + '.response.json'))
        $treeEnv = Invoke-Tool -Id ($tag + '_tree') -Tool 'editor_get_scene_tree' -Arguments @{}
        $treeText = ConvertTo-CompactJson (Get-Payload $treeEnv)
        $attached = $treeText.Contains('D4Node')
        $after = Get-FileSha $Script:MainScenePath
        $null = Invoke-Tool -Id ($tag + '_save') -Tool 'editor_save_scene' -Arguments @{}
        $afterSave = Get-FileSha $Script:MainScenePath
        $gdRead = Get-EditorGdscript -Id ($tag + '_read_gd') -Code $EditorReadActorRotation
        Add-Check ($tag + '_code') ($code -eq -32602) ("code=" + $code + " message=" + (Get-ErrorMessage $env))
        Add-Check ($tag + '_no_value_echo') (Test-NoValueEcho $env) ("no result payload / no value echo; message names: " + (Get-EngineWouldWriteSpelling -Text $respText))
        Add-Check ($tag + '_file_clean') ((Test-FileHasNoNonFinite -Path $Script:MainScenePath) -and ($before -eq $afterSave)) ("sha256 " + $before + " -> " + $afterSave + "; no inf/nan in bytes")
        Add-Check ($tag + '_nothing_attached') (-not $attached) ("scene tree contains D4Node = " + $attached + " ; sha before save=" + $after)
        Add-Check ($tag + '_read_old') ((Test-FiniteValue (Get-EditorNodeProperty -Id ($tag + '_read_props') -Path 'Actor' -Property 'rotation')) -and ($gdRead -eq '0.5')) ("Actor.rotation gd=" + $gdRead)
        $results += [pscustomobject]@{ case = $case.name; code = $code; attached = $attached; before = $before; after = $afterSave; gd = $gdRead }
    }
    return $results
}

function Test-Path4Game {
    $results = @()
    foreach ($case in @(
            [pscustomobject]@{ name = '1e300'; value = 1.0e300 },
            [pscustomobject]@{ name = '1e-46'; value = 1.0e-46 })) {
        $tag = 'P4_' + $case.name
        # The game side has no save-scene tool (it is the editor's), so the game
        # case is measured by its own state + the GDScript channel; the file form
        # is covered by path 1/2/3 and path 5 (which really writes to disk).
        $seed = Invoke-Tool -Id ($tag + '_seed') -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'Actor'; property = 'rotation'; value = 0.5 } -Port $GamePort
        $env = Invoke-Tool -Id $tag -Tool 'running_game_set_node_property' -Arguments @{ node_path = 'Actor'; property = 'rotation'; value = $case.value } -Port $GamePort
        $code = Get-ErrorCode $env
        $respText = Get-FileText (Join-Path $Evid ($tag + '.response.json'))
        $propsRead = Get-GameNodeProperty -Id ($tag + '_read_props') -Path 'Actor' -Property 'rotation'
        $gdRead = Get-GameGdscript -Id ($tag + '_read_gd') -Code $GameReadActorRotation
        Add-Check ($tag + '_seed_ok') ((Get-ErrorCode $seed) -eq 0) ("seed rotation=0.5 code=" + (Get-ErrorCode $seed))
        Add-Check ($tag + '_code') ($code -eq -32602) ("code=" + $code + " message=" + (Get-ErrorMessage $env))
        Add-Check ($tag + '_no_value_echo') (Test-NoValueEcho $env) ("no result payload / no value echo; message names: " + (Get-EngineWouldWriteSpelling -Text $respText))
        Add-Check ($tag + '_read_old') ((Test-FiniteValue $propsRead) -and ($gdRead -eq '0.5')) ("running_game_get_node_properties rotation=" + (ConvertTo-CompactJson $propsRead) + " ; running_game_execute_gdscript str(rotation)=" + $gdRead)
        $results += [pscustomobject]@{ case = $case.name; code = $code; props = (ConvertTo-CompactJson $propsRead); gd = $gdRead }
    }
    return $results
}

function Test-Path5AcrossScenes {
    $results = @()
    foreach ($case in @(
            [pscustomobject]@{ name = '1e300'; value = 1.0e300 },
            Add-Check ($tag + '_refused') (($code -eq -32602) -and (-not (Test-Path $file))) ("code=" + $code + " message=" + (Get-ErrorMessage $env) + " file exists=" + (Test-Path $file))
        } else {
            $set = @($payload.properties_set)
            $changed = $payload.changed
            $ignored = $payload.ignored
            if ($case.name -eq 'min_5_clamped') {
                Add-Check ($tag + '_readback') (($set -notcontains 'min_value') -and ($null -ne $changed.min_value) -and ($null -ne $ignored.min_value)) ("properties_set=" + (ConvertTo-CompactJson $set) + " changed.min_value=" + (ConvertTo-CompactJson $changed.min_value) + " ignored.min_value=" + (ConvertTo-CompactJson $ignored.min_value))
                Add-Check ($tag + '_file_truthful') (Test-FileHasNoNonFinite -Path $file) ("file=" + $file + " sha256=" + $fileSha)
            } else {
                Add-Check ($tag + '_readback') (($set -contains 'min_value') -and ($set -contains 'max_value') -and ($null -ne $changed.min_value) -and (@($ignored.PSObject.Properties).Count -eq 0)) ("properties_set=" + (ConvertTo-CompactJson $set) + " changed=" + (ConvertTo-CompactJson $changed) + " ignored=" + (ConvertTo-CompactJson $ignored))
                Add-Check ($tag + '_file_truthful') (Test-FileHasNoNonFinite -Path $file) ("file=" + $file + " sha256=" + $fileSha)
            }
        }
        $results += [pscustomobject]@{ case = $case.name; code = $code; properties_set = (ConvertTo-CompactJson $payload.properties_set); changed = (ConvertTo-CompactJson $payload.changed); ignored = (ConvertTo-CompactJson $payload.ignored); sha = $fileSha }
    }
    # The sibling entry's shape, for the "same standard" comparison.
    $env = Invoke-Tool -Id 'D5_edit_compare' -Tool 'project_edit_resource' -Arguments @{ path = 'res://d5_ok.tres'; properties = @{ min_value = 0.5 } }
    $payload = Get-Payload $env
    Add-Check 'D5_edit_readback_shape' (($null -ne $payload.changed.min_value) -and ($null -ne $payload.changed.min_value.old) -and ($null -ne $payload.changed.min_value.new)) ("project_edit_resource changed=" + (ConvertTo-CompactJson $payload.changed))
    return $results
}

function Test-D6CrossProcess {
    $bridge = Join-Path $Project 'mcp_test_report.json'
    # The game writes `user://mcp_test_report.json`; resolve it through the editor
    # process so the path compared here is the one the engine really used.
    $userDir = Get-EditorGdscript -Id 'D6_userdir' -Code 'return OS.get_user_data_dir()'
    $bridgeAbs = Join-Path $userDir 'mcp_test_report.json'
    Write-Host ("bridge file = {0}" -f $bridgeAbs)

    # (1) Two assertions in the **game** process: one pass, one fail.
    $pass = Invoke-Tool -Id 'D6_game_pass' -Tool 'running_game_assert_node_state' -Arguments @{ node_path = 'Actor'; property = 'position'; operator = 'eq'; expected = @{ x = 3; y = 4 } } -Port $GamePort
    $passPayload = Get-Payload $pass
    $fail = Invoke-Tool -Id 'D6_game_fail' -Tool 'running_game_assert_node_state' -Arguments @{ node_path = 'Actor'; property = 'rotation'; operator = 'eq'; expected = 123.0 } -Port $GamePort
    $failPayload = Get-Payload $fail
    Add-Check 'D6_game_assertions_ran' (($passPayload.passed -eq $true) -and ($failPayload.passed -eq $false)) ("pass=" + (ConvertTo-CompactJson $passPayload.passed) + " fail=" + (ConvertTo-CompactJson $failPayload.passed) + " fail.reason=" + $failPayload.reason)
    Add-Check 'D6_bridge_file_written' (Test-Path $bridgeAbs) ("user://mcp_test_report.json exists=" + (Test-Path $bridgeAbs) + " sha256=" + (Get-FileSha $bridgeAbs) + " bytes=" + (Get-Item $bridgeAbs -ErrorAction SilentlyContinue).Length)

    # (2) The editor endpoint reads it (the cross-endpoint call is the whole
    # point: `running_game_*` is not registered on 9888).
    $report = Invoke-Tool -Id 'D6_editor_read' -Tool 'editor_get_test_report' -Arguments @{ clear = $false }
    $reportPayload = Get-Payload $report
    $reportText = ConvertTo-CompactJson $reportPayload
    Add-Check 'D6_editor_sees_game_report' (([int]$reportPayload.total -ge 2) -and ([int]$reportPayload.failed -ge 1) -and ((@($reportPayload.details)).Count -ge 2) -and ($reportPayload.source -eq 'game_process_file')) ("total=" + $reportPayload.total + " passed=" + $reportPayload.passed + " failed=" + $reportPayload.failed + " source=" + $reportPayload.source + " report_path=" + $reportPayload.report_path + " written_at_unix=" + $reportPayload.report_written_at_unix)

    # (3) `clear` (the default) empties the bridge as well, so the next call is
    # honestly empty instead of replaying a stale report.
    $cleared = Invoke-Tool -Id 'D6_editor_clear' -Tool 'editor_get_test_report' -Arguments @{}
    $clearedPayload = Get-Payload $cleared
    $empty = Invoke-Tool -Id 'D6_editor_empty' -Tool 'editor_get_test_report' -Arguments @{}
    $emptyPayload = Get-Payload $empty
    Add-Check 'D6_clear_is_cross_process' (([int]$clearedPayload.total -ge 2) -and (Test-Path $bridgeAbs) -eq $false -and ([int]$emptyPayload.total -eq 0) -and ($emptyPayload.no_results -eq $true) -and ($emptyPayload.report_file_present -eq $false)) ("first total=" + $clearedPayload.total + " cleared=" + (ConvertTo-CompactJson $clearedPayload.cleared) + " file left=" + (Test-Path $bridgeAbs) + " second total=" + $emptyPayload.total + " no_results=" + $emptyPayload.no_results + " report_file_present=" + $emptyPayload.report_file_present)

    return $reportText
}

function Test-Regression {
    # TASK-020/021 faces re-run: five component spellings, string spellings and
    # the batch transaction must still be refused the same way.
    $before = Reset-Baseline -Tag 'REG'
    $componentValues = @(
        @{ x = 'NaN'; y = 1 }, @{ x = 'abc'; y = 1 }, @{ x = $null; y = 1 },
        @{ x = @{ z = 9 }; y = 1 }, @{ x = @(1, 2); y = 1 }
    )
    $componentOk = $true
    for ($i = 0; $i -lt $componentValues.Count; $i++) {
        $env = Invoke-Tool -Id ('REG_comp_' + $i) -Tool 'editor_set_node_property' -Arguments @{ path = 'Actor'; property = 'position'; value = $componentValues[$i] }
        if ((Get-ErrorCode $env) -ne -32602) { $componentOk = $false }
    }
    $posRead = Get-EditorNodeProperty -Id 'REG_comp_read' -Path 'Actor' -Property 'position'
    $reg = Test-Regression

    Write-Host '=== port discipline (after) ==='
    $pid9877b = Get-ListenerPid -Port $UserPort
    Add-Check 'P0_user_port_untouched_after' ($pid9877b -eq $pid9877) ("9877 owner before=" + $pid9877 + " after=" + $pid9877b)

    $summary = [pscustomobject]@{
        version    = $version
        head       = $head
        checks     = $script:Checks
        failed     = @($script:Results | Where-Object { -not $_.pass }).Count
        path1      = $path1
        path2      = $path2
        path3      = $path3
        path4      = $path4
        path5      = $path5
        d5         = $d5
        d6         = $d6
        regression = $reg
        results    = $script:Results
    }
    [IO.File]::WriteAllText($ResultFile, (ConvertTo-Json -InputObject $summary -Depth 32))
    Write-Host ("results -> {0}" -f $ResultFile)
    Write-Host ("checks={0} failed={1}" -f $script:Checks, @($script:Results | Where-Object { -not $_.pass }).Count)
} finally {
    Stop-Engine -Handle $script:GameHandle
    Stop-Engine -Handle $script:EditorHandle
    Start-Sleep -Milliseconds 1500
    Write-Host '=== port discipline (settled) ==='
    Write-Host ("9888 owner = " + (Get-ListenerPid -Port $EditorPort))
    Write-Host ("9889 owner = " + (Get-ListenerPid -Port $GamePort))
    Write-Host ("9877 owner = " + (Get-ListenerPid -Port $UserPort))
}

# TASK-069 section 2.3 (census): this evidence script wrote its `failed` count
# into the summary JSON and printed it, then fell off the end of the file - which
# PowerShell reports as exit 0, so a red check was unreadable to any caller.
# `$script:Results` is the shared check list filled by Add-Check.
$failed = @($script:Results | Where-Object { -not $_.pass })
if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host ("EVIDENCE FAILED: {0} check(s)" -f $failed.Count)
    foreach ($entry in $failed) { Write-Host ('    ' + $entry.id + ': ' + $entry.evidence) }
    exit 1
}
exit 0