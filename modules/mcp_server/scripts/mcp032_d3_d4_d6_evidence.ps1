# =============================================================================
#  mcp032_d3_d4_d6_evidence.ps1 -- TASK-032 live evidence (M4d D3, D4, D6)
#
#  D3 (medium, the highest-priority item). `editor_get_node_properties` without a
#  `properties` filter used to enumerate the *inspector's own* label entries
#  (PROPERTY_USAGE_GROUP / SUBGROUP / CATEGORY) as if they were properties: 12
#  fake `null` properties for a `Node2D`, one of them - the CanvasItem group
#  "Material" - differing from the real property `material` only by case. A
#  case-insensitive JSON parser refuses such a package outright, and PowerShell
#  5.1 is one of them:
#      Cannot convert the JSON string because a dictionary that was converted
#      from the string contains the duplicated keys 'Material' and 'material'.
#  This script proves three things, on the live endpoint:
#    (a) the *ground truth*: through `editor_execute_gdscript` the engine itself
#        is asked which entries of the node's property table carry one of those
#        three usage bits (the labels) and which do not (the values);
#    (b) the response now carries the value set and not one label, and the
#        label/value sets reconstructed together have exactly one
#        case-insensitive collision while the answered set has none;
#    (c) the direct judgment criterion: `ConvertFrom-Json` (a case-insensitive
#        parser) parses both the whole envelope and its `content[0].text`
#        payload - with a *positive control* next to it, a hand-built JSON text
#        with `Material` and `material` that the very same parser refuses, so
#        "it parsed" cannot be an artifact of a parser that never throws.
#
#  D4 (minor). `project_get_settings` documents `prefix`; a caller who spelled it
#  `filter` used to get `code: 0` plus the unfiltered 981-setting list. The
#  registry now refuses every argument name the tool's schema does not declare.
#  Proven on the wire: the correct spelling still works, the wrong one is
#  `-32602` naming `filter` with a `data.suggestion` listing the accepted names,
#  and a tool that declares no parameter says so instead of listing nothing.
#
#  D6 (minor). `running_game_get_scene_tree` returns `path = "/root/Main/Actor"`
#  (SceneTree absolute) while the family's `node_path` description said
#  "relative to the scene root". The contract now says both, and both spellings
#  are measured to work: the same node is read as `Actor` and as
#  `/root/Main/Actor`, answering the same payload.
#
#  Discipline: response bodies go through `curl.exe -s -o <file>` and their
#  sha256 is computed from the bytes on disk; request bodies are built with
#  `ConvertTo-Json` and sent with `--data-binary @file`; ports 9888/9889 only.
#  TASK-154: the decision maker's own editor port is REFUSED at launch (a requested
#  test port outside {9888, 9889} exits 4 before any process starts) and the port is
#  no longer enumerated, probed or asserted on by this script. This file is
#  deliberately pure ASCII (the Chinese fragments it needs are read out of the
#  contract / the frozen baseline with an explicit UTF-8 decoder, never written as
#  literals into a BOM-less .ps1 that Windows PowerShell 5.1 reads as ANSI).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp032_d3_d4_d6_evidence.ps1
# =============================================================================

param(
    [int]$EditorPort = 9888,
    [int]$GamePort = 9889,
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$Contract = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'

# TASK-154: the pre-override wording is read from the ENGINE-REPOSITORY baseline,
# not from the hof-rs working file.
#
# Until TASK-154 this was the absolute path
# `F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json` - a file outside the
# repository this script belongs to, and one that hof-rs commit `db2eed7` has since
# re-captured to the 177-tool four-channel shape (measured on this machine: that
# file now has 177 entries and carries neither `get_test_report` nor
# `get_game_node_properties`, so the old spelling could only ever produce an empty
# prefix). The bytes this script needs are the ones frozen inside this repository as
# `docs/rename-baseline-tools-list.json` (48749 B, 174 entries, sha256
# `8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54`, no newline):
# the same artifact `docs/scripts/check_rename_map.py` (TASK-152) and
# `scripts/gen_renamed_contract.py` (TASK-153) already read, so the entry this
# script compares against now comes from ONE baseline inside one git history.
#
# Equivalence evidence (TASK-154, static - the hof-rs file on this machine is the
# post-`db2eed7` capture): `get_game_node_properties.description` and the whole
# `inputSchema` of that entry are BYTE-IDENTICAL in the engine baseline and in
# `git -C F:\moonbit-hof-rs show db2eed7^:tests/fixtures/mcp/tools_list.json` (a
# read-only object-store read of the state this script always intended). The path
# constant is the only thing that changes, so what the script evidences is
# unchanged.
$ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Docs = Join-Path $ModuleRoot 'docs'
$OldFixture = Join-Path $Docs 'rename-baseline-tools-list.json'
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'task032-d3-d4-d6' }
$Root = $OutRoot
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
# TASK-154: there is no `$UserPort` here any more. The constant it held - the
# decision maker's editor port - is refused by the launch guard below and is never
# enumerated, probed or asserted on by this script.
$utf8 = [Text.Encoding]::UTF8

# TASK-028 D-1: the shared scratch-project writer + `--import` runner.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

# =============================================================================
#  TASK-154 section 2.2: the user's editor port is REFUSED, not parameterised.
#
#  The decision-maker's own Godot editor listens on 9877 on this machine, and this
#  script used to carry that number and even assert its pid stayed the same across
#  the run. Nothing here may occupy it, probe it, or admit it as a reachable value.
#
#  The form chosen is the *explicit refusal guard*: a requested test port outside
#  {9888, 9889} is a hard stop, and so is any occurrence of the user editor's port
#  literal in `$PSScriptRoot` (where every launcher this script can use is
#  assembled), so there is no path on which that port is used *silently*.
#  Parameterising it instead would leave a spelling - `-EditorPort <user port>` -
#  that reaches the user's editor.
#
#  The old TASK-042 `mcp_port_guard.ps1` classification is therefore no longer
#  dot-sourced here: its whole subject was the state of that port. What it really
#  guaranteed - "this script's engines are only ever launched with the test ports"
#  - is now decided earlier and more strongly, from the argument values themselves.
# =============================================================================
$TestPorts = @(9888, 9889)
foreach ($requestedPort in @($EditorPort, $GamePort)) {
    if (@($TestPorts) -notcontains $requestedPort) {
        Write-Host ('TASK-154 PORT GUARD: port {0} is refused. This script uses the test ports only: {1}.' -f $requestedPort, (($TestPorts | Sort-Object) -join '/'))
        Write-Host '  (The decision maker''s own editor port on this machine is never to be occupied or probed.)'
        exit 4
    }
}
$portLiteralPattern = [regex]::Escape('9877')
if (-not [string]::IsNullOrEmpty([string]$PSScriptRoot) -and [regex]::IsMatch([string]$PSScriptRoot, $portLiteralPattern)) {
    Write-Host ('TASK-154 PORT GUARD: the user editor port literal appears in the launch context "{0}"; refusing to run.' -f $PSScriptRoot)
    exit 4
}

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Get-ListenerPid {
    param([int]$Port_)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port_ + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

function New-CallBody {
    param([string]$Tool, $Arguments, [int]$Id = 1)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function New-ListBody {
    param([int]$Id = 1)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/list'; params = [ordered]@{} }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Invoke-Raw {
    param([string]$Id, [string]$Body, [int]$Port_)
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-McpUtf8NoBom -Path $bodyFile -Text $Body
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time 120 -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] port={1} bytes={2} sha256={3}" -f $Id, $Port_, $bytes.Length, $sha)
    return @{ text = $text; sha256 = $sha; file = $respFile; bytes = $bytes.Length }
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 0)
    if ($Port_ -eq 0) { $Port_ = $EditorPort }
    $resp = Invoke-Raw -Id $Id -Body (New-CallBody -Tool $Tool -Arguments $Arguments) -Port_ $Port_
    Write-Host ("       {0}" -f $resp.text)
    return $resp
}

# The *inner* payload text of a successful `tools/call` (never parsed through a
# pipeline: it is the string the envelope carries).
function Get-PayloadText {
    param($Response)
    if ($null -eq $Response) { return '' }
    try {
        $envelope = ConvertFrom-Json ([string]$Response.text)
        if ($null -eq $envelope.result) { return '' }
        return [string]$envelope.result.content[0].text
    } catch { return '' }
}

function Get-Payload {
    param($Response)
    $text = Get-PayloadText $Response
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return ConvertFrom-Json $text } catch { return $null }
}

function Get-ErrorCode {
    param($Response)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return 0 }
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.error) { return 0 }
        return [int]$envelope.error.code
    } catch { return 0 }
}

function Get-ErrorMessage {
    param($Response)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.error) { return '' }
        return [string]$envelope.error.message
    } catch { return '' }
}

function Get-ErrorSuggestion {
    param($Response)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $text
        if ($null -eq $envelope.error -or $null -eq $envelope.error.data) { return '' }
        return [string]$envelope.error.data.suggestion
    } catch { return '' }
}

function ConvertTo-CompactJson {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    return (ConvertTo-Json -InputObject $Value -Depth 20 -Compress)
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    # TASK-154: the engine process is started with exactly the arguments given, and
    # every argument list in this file is built from $EditorPort / $GamePort, which
    # the launch guard above has already pinned to the test ports. The old TASK-042
    # `Register-McpPortGuardProcess` bookkeeping is gone with `mcp_port_guard.ps1`.
    return Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
}

function Wait-ForPump {
    param([int]$Port_, [int]$Iterations = 240)
    for ($i = 0; $i -lt $Iterations; $i++) {
        Start-Sleep -Milliseconds 1000
        $out = Join-Path $Ev ("status-{0}.json" -f $Port_)
        & $Curl -s --max-time 5 -o $out ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (Test-Path $out) {
            try {
                $probe = ConvertFrom-Json ([IO.File]::ReadAllText($out, $utf8))
                if ($null -ne $probe.frame_count -and [int]$probe.frame_count -ge 20) { return $true }
            } catch { }
        }
    }
    return $false
}

function Stop-Engine {
    param($Handle)
    if ($null -ne $Handle -and -not $Handle.HasExited) {
        Stop-Process -Id $Handle.Id -Force -ErrorAction SilentlyContinue
    }
}

# The three usage bits the engine's own consumers test for a label
# (core/object/property_info.h: GROUP = 1 << 6, CATEGORY = 1 << 7, SUBGROUP = 1 << 8).
$LabelMask = 64 + 128 + 256

# =============================================================================
# Scratch project: a Node2D that carries both a label and the property it groups
# (CanvasItem declares ADD_GROUP("Material", "") next to the real `material`).
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Proj, (Join-Path $Proj 'scenes') | Out-Null

$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp032_d3_d4_d6"'
    'run/main_scene="res://scenes/main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text ($projectGodot + "`n")

$scene = @'
[gd_scene format=3]

[node name="Main" type="Node2D"]

[node name="Actor" type="Node2D" parent="."]
position = Vector2(1, 2)
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text $scene

# The ground-truth code: never mind what the tool answers, ask the engine which
# table entries are labels and which are values for the very same node.
$labelProbe = @'
var root = Engine.get_main_loop().get_edited_scene_root()
var node = root.get_node("Actor")
var labels = []
var values = []
for p in node.get_property_list():
    var usage = int(p.usage)
    if (usage & 64) != 0 or (usage & 128) != 0 or (usage & 256) != 0:
        labels.append(String(p.name))
    elif not String(p.name).begins_with("_") and String(p.name) != "script":
        values.append(String(p.name))
return {"labels": labels, "values": values}
'@

# -----------------------------------------------------------------------------
# D3: the direct judgment criterion. `ConvertFrom-Json` is a case-insensitive
# parser; the positive control proves it really refuses a case-conflicting pair,
# so a successful parse of the real answer is evidence and not luck.
# -----------------------------------------------------------------------------
$controlThrew = $false
$controlMessage = ''
try {
    $null = ('{"Material":null,"material":null}' | ConvertFrom-Json)
} catch {
    $controlThrew = $true
    $controlMessage = $_.Exception.Message
}
Check 'd3_parser_positive_control' $controlThrew `
    ("hand-built {'Material','material'} JSON: ConvertFrom-Json threw = {0}; message='{1}'" -f $controlThrew, $controlMessage)
Check 'd3_parser_control_names_the_pair' ($controlThrew -and $controlMessage.Contains('Material') -and $controlMessage.Contains('material')) `
    ("the refusal names both keys: Material={0} material={1}" -f $controlMessage.Contains('Material'), $controlMessage.Contains('material'))

# TASK-154: the old six-way 9877 classification (`New-McpPortGuard` /
# `Complete-McpPortGuard` from `mcp_port_guard.ps1`) stood here. It is replaced by
# the launch-time refusal guard plus these two checks: "this script only ever asked
# the engine for the test ports" is now a fact about the argument values (checked
# before any process starts), and "the test ports are released again" is a fact
# about what this script itself did.
$userPortLiteralPattern = [regex]::Escape('9877')
Check 'test_ports_only' (($TestPorts.Count -eq 2) -and (@($TestPorts) -contains $EditorPort) -and (@($TestPorts) -contains $GamePort) -and (-not [regex]::IsMatch([string]$PSScriptRoot, $userPortLiteralPattern))) `
    ("editor={0} game={1}; allowed test ports = [{2}]; the user editor port is refused at launch and is never taught to this script" -f $EditorPort, $GamePort, (($TestPorts | Sort-Object) -join ', '))
Check 'port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'port_9889_free' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Check 'scratch_project_imported' ($import.exit_code -eq 0) `
    ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

$editorHandle = $null
$gameHandle = $null
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $open = Invoke-Tool -Id 'D3_00_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'd3_scene_opened' ($null -ne (Get-Payload $open)) ("editor_open_scene -> " + (Get-PayloadText $open))

    # --- (a) the engine's own classification -------------------------------
    $probe = Invoke-Tool -Id 'D3_01_engine_usage_probe' -Tool 'editor_execute_gdscript' -Arguments @{ code = $labelProbe }
    $probePayload = Get-Payload $probe
    $probeResult = if ($null -ne $probePayload) { $probePayload.result } else { $null }
    $labels = if ($null -ne $probeResult) { @($probeResult.labels) } else { @() }
    $values = if ($null -ne $probeResult) { @($probeResult.values) } else { @() }
    Check 'd3_probe_ran' (($null -ne $probeResult) -and ($labels.Count -ge 1) -and ($values.Count -ge 1)) `
        ("engine probe: labels={0} values={1} labels=[{2}]" -f $labels.Count, $values.Count, ($labels -join ', '))
    Check 'd3_probe_has_the_colliding_label' ($labels -contains 'Material') `
        ("PROPERTY_USAGE_GROUP entry 'Material' present in the raw table: {0}" -f ($labels -contains 'Material'))

    # --- (b) the answer, and the before/after comparison --------------------
    $props = Invoke-Tool -Id 'D3_02_list_properties' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor' }
    $propsText = Get-PayloadText $props
    $propsPayload = Get-Payload $props
    $properties = if ($null -ne $propsPayload) { $propsPayload.properties } else { $null }
    $answered = if ($null -ne $properties) { @($properties.PSObject.Properties | ForEach-Object { $_.Name }) } else { @() }

    # "before" = what the old, unfiltered enumerator answered: the labels *and*
    # the values, in engine order (the labels are exactly the entries that used to
    # come back as fake nulls). Two of the thirteen labels collide with a real
    # property under a case-insensitive comparison - `Material` with `material`
    # and `Transform` with `transform`; PowerShell names the first pair it meets.
    #
    # Every string comparison below is explicitly *case sensitive*
    # (`-ccontains` / `-ceq` / `Compare-Object -CaseSensitive`): PowerShell's
    # default `-contains` compares case-insensitively, which is exactly the
    # confusion this defect is about - the first run of this script reported
    # `Material` "present" in an answer that only carries `material`.
    $before = @($labels + $values)
    $beforeLower = @($before | ForEach-Object { $_.ToLower() })
    $beforeDuplicates = @($beforeLower | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    $answeredLower = @($answered | ForEach-Object { $_.ToLower() })
    $answeredDuplicates = @($answeredLower | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })

    Check 'd3_before_had_the_case_collisions' ($beforeDuplicates -ccontains 'material' -and $beforeDuplicates -ccontains 'transform') `
        ("reconstructed pre-fix key set: {0} keys, case-insensitive duplicates=[{1}] (Material/material and Transform/transform; the old set was not parsable by a case-insensitive client)" -f $before.Count, ($beforeDuplicates -join ', '))
    Check 'd3_after_has_no_case_collision' ($answeredDuplicates.Count -eq 0) `
        ("answered key set: {0} keys, case-insensitive duplicates=[{1}]" -f $answered.Count, ($answeredDuplicates -join ', '))

    $leaked = @($labels | Where-Object { $answered -ccontains $_ })
    Check 'd3_no_label_is_answered_as_a_property' ($leaked.Count -eq 0) `
        ("{0} label(s) in the engine table, {1} of them present in the answer (case sensitive): [{2}]" -f $labels.Count, $leaked.Count, ($leaked -join ', '))
    Check 'd3_the_real_property_survives' (($answered -ccontains 'material') -and (($answered -ccontains 'Material') -eq $false)) `
        ("answer contains 'material'={0} and 'Material'={1} (case sensitive)" -f ($answered -ccontains 'material'), ($answered -ccontains 'Material'))

    $valueSetDiff = @(Compare-Object -CaseSensitive -ReferenceObject (@($values | Sort-Object -Unique)) -DifferenceObject (@($answered | Sort-Object -Unique)))
    Check 'd3_answer_is_exactly_the_value_set' ($valueSetDiff.Count -eq 0 -and $answered.Count -eq $values.Count) `
        ("engine values={0} answered={1} diff=[{2}]" -f $values.Count, $answered.Count, (($valueSetDiff | ForEach-Object { $_.InputObject }) -join ', '))

    # --- (c) the direct judgment criterion, on the real answer --------------
    $envelopeParsed = $false
    $envelopeDetail = ''
    try {
        $envelope = ConvertFrom-Json ([string]$props.text)
        $envelopeParsed = $null -ne $envelope.result
        $envelopeDetail = 'envelope parsed, result present'
    } catch {
        $envelopeDetail = 'envelope refused: ' + $_.Exception.Message
    }
    Check 'd3_whole_envelope_parses' $envelopeParsed ("WIRE JSON-RPC envelope: {0}; sha256={1}" -f $envelopeDetail, $props.sha256)

    $payloadParsed = $false
    $payloadDetail = ''
    try {
        $inner = ConvertFrom-Json $propsText
        $payloadParsed = $null -ne $inner.properties
        $payloadDetail = ('content[0].text parsed, property count=' + @($inner.properties.PSObject.Properties).Count)
    } catch {
        $payloadDetail = 'content[0].text refused: ' + $_.Exception.Message
    }
    Check 'd3_inner_payload_parses' $payloadParsed ("WIRE content[0].text: {0}" -f $payloadDetail)

    # --- (d) the named path: a label is refused, the property is answered ---
    $labelByName = Invoke-Tool -Id 'D3_03_named_label' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor'; properties = @('Material') }
    Check 'd3_named_label_is_32001' ((Get-ErrorCode $labelByName) -eq -32001) `
        ("properties=['Material'] -> code={0} message='{1}'" -f (Get-ErrorCode $labelByName), (Get-ErrorMessage $labelByName))
    Check 'd3_named_label_message_names_it' ((Get-ErrorMessage $labelByName).Contains('Material')) `
        ("message names the label: '{0}'" -f (Get-ErrorMessage $labelByName))

    $realByName = Invoke-Tool -Id 'D3_04_named_property' -Tool 'editor_get_node_properties' -Arguments @{ path = 'Actor'; properties = @('material') }
    $realByNamePayload = Get-Payload $realByName
    # Windows PowerShell 5.1 unrolls a *statement's* output: an `if` whose branch
    # emits a one-element array yields a scalar (on which `.Count` is 1 and
    # `[0]` is the first *character*). The `@(...)` wrapper below is what keeps
    # `$realKeys[0]` the key name rather than 'm'.
    $realKeys = @(if ($null -ne $realByNamePayload) { @($realByNamePayload.properties.PSObject.Properties | ForEach-Object { $_.Name }) })
    $realCode = Get-ErrorCode $realByName
    $realCountOk = ($realKeys.Count -eq 1)
    $realNameOk = ($realKeys.Count -eq 1) -and ([string]$realKeys[0] -ceq 'material')
    Check 'd3_named_property_is_answered' (($realCode -eq 0) -and $realCountOk -and $realNameOk) `
        ("properties=['material'] -> code={0} (==0: {1}) keys=[{2}] count_ok={3} exact_spelling_ok={4}" -f $realCode, ($realCode -eq 0), ($realKeys -join ', '), $realCountOk, $realNameOk)

    # --- D4: the unknown-parameter gate ------------------------------------
    $good = Invoke-Tool -Id 'D4_00_documented_spelling' -Tool 'project_get_settings' -Arguments @{ prefix = 'application/config/name' }
    $goodPayload = Get-Payload $good
    Check 'd4_documented_spelling_still_works' ((Get-ErrorCode $good) -eq 0 -and $null -ne $goodPayload -and [int]$goodPayload.count -ge 1) `
        ("{prefix:'application/config/name'} -> code={0} count={1}" -f (Get-ErrorCode $good), $(if ($null -ne $goodPayload) { $goodPayload.count } else { '<none>' }))

    $bad = Invoke-Tool -Id 'D4_01_measured_defect_filter' -Tool 'project_get_settings' -Arguments @{ filter = 'application/config/name' }
    $badPayload = Get-Payload $bad
    Check 'd4_unknown_name_is_32602' ((Get-ErrorCode $bad) -eq -32602) `
        ("{filter:...} -> code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $bad), (Get-ErrorMessage $bad), (Get-ErrorSuggestion $bad))
    Check 'd4_message_names_the_unknown_parameter' (((Get-ErrorMessage $bad).Contains('filter')) -and ((Get-ErrorMessage $bad).Contains('project_get_settings'))) `
        ("message = '{0}'" -f (Get-ErrorMessage $bad))
    Check 'd4_suggestion_lists_the_accepted_names' (((Get-ErrorSuggestion $bad).Contains('prefix')) -and ((Get-ErrorSuggestion $bad).Contains('include_default'))) `
        ("suggestion = '{0}'" -f (Get-ErrorSuggestion $bad))
    Check 'd4_no_settings_payload_came_back' ($null -eq $badPayload) `
        ("payload is null (the old behaviour was 981 settings): {0}" -f ($null -eq $badPayload))

    $mixed = Invoke-Tool -Id 'D4_02_correct_plus_wrong' -Tool 'project_get_settings' -Arguments @{ prefix = 'application/config/'; filter = 'application/config/' }
    Check 'd4_mixed_call_is_refused_too' ((Get-ErrorCode $mixed) -eq -32602 -and (Get-ErrorMessage $mixed).Contains('filter')) `
        ("{prefix, filter} -> code={0} message='{1}'" -f (Get-ErrorCode $mixed), (Get-ErrorMessage $mixed))

    $noParams = Invoke-Tool -Id 'D4_03_tool_without_parameters' -Tool 'project_get_info' -Arguments @{ bogus = 1 }
    Check 'd4_no_parameter_tool_says_so' ((Get-ErrorCode $noParams) -eq -32602 -and ((Get-ErrorSuggestion $noParams) -eq 'project_get_info accepts no parameters')) `
        ("project_get_info {bogus:1} -> code={0} suggestion='{1}'" -f (Get-ErrorCode $noParams), (Get-ErrorSuggestion $noParams))

    $declaredOptional = Invoke-Tool -Id 'D4_04_declared_optional_parameter' -Tool 'project_get_settings' -Arguments @{ include_default = $true }
    Check 'd4_declared_parameter_is_not_the_gate_business' ((Get-ErrorCode $declaredOptional) -eq 0) `
        ("{include_default:true} is declared, so it is answered: code={0} message='{1}' (a *declared* parameter a tool cannot honour stays the handler's business - pinned by the doctest for running_game_run_test_scenario.scene_path)" -f (Get-ErrorCode $declaredOptional), (Get-ErrorMessage $declaredOptional))

    # --- D6: the game-side path shape and the two accepted spellings --------
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, "--mcp-port=$GamePort") -LogName 'game'
    Check 'game_endpoint_ready' (Wait-ForPump -Port_ $GamePort) ("game on {0} answered GET /mcp with +20 frames" -f $GamePort)

    $tree = Invoke-Tool -Id 'D6_00_scene_tree' -Tool 'running_game_get_scene_tree' -Arguments @{ max_depth = -1 } -Port_ $GamePort
    $treePayload = Get-Payload $tree
    $actorPath = ''
    if ($null -ne $treePayload -and $null -ne $treePayload.tree) {
        $children = @($treePayload.tree.children)
        foreach ($child in $children) {
            if ([string]$child.name -eq 'Actor') { $actorPath = [string]$child.path; break }
        }
    }
    Check 'd6_scene_tree_returns_the_absolute_path' ($actorPath -eq '/root/Main/Actor') `
        ("running_game_get_scene_tree path of Actor = '{0}' (SceneTree absolute, from /root)" -f $actorPath)

    # The cross-tool chain: the *answer* of the tree tool (`path` of Actor) is fed
    # straight back into the property tool, and the relative spelling is measured
    # next to it. This is the end-to-end form of the D6 claim ("one tool's answer
    # can be fed into the next").
    $chainedPath = if ([string]::IsNullOrEmpty($actorPath)) { '/root/Main/Actor' } else { $actorPath }
    $byRelative = Invoke-Tool -Id 'D6_01_relative_node_path' -Tool 'running_game_get_node_properties' -Arguments @{ node_path = 'Actor'; properties = @('position') } -Port_ $GamePort
    $byAbsolute = Invoke-Tool -Id 'D6_02_absolute_node_path' -Tool 'running_game_get_node_properties' -Arguments @{ node_path = $chainedPath; properties = @('position') } -Port_ $GamePort
    $relPayload = Get-Payload $byRelative
    $absPayload = Get-Payload $byAbsolute
    Check 'd6_tree_answer_is_fed_back_verbatim' ((Get-ErrorCode $byAbsolute) -eq 0 -and $null -ne $absPayload) `
        ("running_game_get_scene_tree answered path='{0}'; that exact string was used as node_path -> code={1} payload={2}" -f $chainedPath, (Get-ErrorCode $byAbsolute), (Get-PayloadText $byAbsolute))
    Check 'd6_relative_spelling_accepted' ((Get-ErrorCode $byRelative) -eq 0 -and $null -ne $relPayload) `
        ("node_path='Actor' -> code={0} payload={1}" -f (Get-ErrorCode $byRelative), (Get-PayloadText $byRelative))
    Check 'd6_absolute_spelling_accepted' ((Get-ErrorCode $byAbsolute) -eq 0 -and $null -ne $absPayload) `
        ("node_path='{0}' -> code={1} payload={2}" -f $chainedPath, (Get-ErrorCode $byAbsolute), (Get-PayloadText $byAbsolute))
    Check 'd6_both_spellings_answer_the_same_node' (($null -ne $relPayload) -and ($null -ne $absPayload) -and ([string]$relPayload.node_path -eq '/root/Main/Actor') -and ([string]$absPayload.node_path -eq [string]$relPayload.node_path) -and ((ConvertTo-CompactJson $relPayload.properties) -eq (ConvertTo-CompactJson $absPayload.properties))) `
        ("relative node_path='{0}' absolute node_path='{1}' properties equal={2}" -f $relPayload.node_path, $absPayload.node_path, ((ConvertTo-CompactJson $relPayload.properties) -eq (ConvertTo-CompactJson $absPayload.properties)))

    # The live description has to carry the shape (D6 is a *declaration* fix), and
    # it has to stay append-only against the pre-override wording, which is read
    # out of the frozen fixture with an explicit UTF-8 decoder (this .ps1 is pure
    # ASCII on purpose).
    $oldDescription = ''
    if (Test-Path $OldFixture) {
        try {
            $oldJson = ConvertFrom-Json ([IO.File]::ReadAllText($OldFixture, $utf8))
            foreach ($candidate in @($oldJson.result.tools)) {
                if ([string]$candidate.name -eq 'get_game_node_properties') { $oldDescription = [string]$candidate.description; break }
            }
        } catch { }
    }
    Check 'd6_old_wording_readable' ($oldDescription.Length -gt 0) ("frozen fixture get_game_node_properties.description = '{0}'" -f $oldDescription)

    $gameList = Invoke-Raw -Id 'D6_03_tools_list' -Body (New-ListBody) -Port_ $GamePort
    $liveDescription = ''
    $liveSchemaNodePath = ''
    try {
        $listEnvelope = ConvertFrom-Json $gameList.text
        foreach ($candidate in @($listEnvelope.result.tools)) {
            if ([string]$candidate.name -eq 'running_game_get_node_properties') {
                $liveDescription = [string]$candidate.description
                $liveSchemaNodePath = [string]$candidate.inputSchema.properties.node_path.description
                break
            }
        }
    } catch { }
    Check 'd6_live_description_keeps_the_old_wording' (($oldDescription.Length -gt 0) -and $liveDescription.StartsWith($oldDescription + ' ')) `
        ("live description starts with the pre-override wording + space: {0}" -f (($oldDescription.Length -gt 0) -and $liveDescription.StartsWith($oldDescription + ' ')))
    Check 'd6_live_description_declares_the_shape' ($liveDescription.Contains('/root/Main/Actor') -and $liveDescription.Contains('SceneTree') -and $liveDescription.Contains('/root')) `
        ("live description = '{0}'" -f $liveDescription)
    $contractDescription = ''
    try {
        $contractJson = ConvertFrom-Json ([IO.File]::ReadAllText($Contract, $utf8))
        foreach ($candidate in @($contractJson.result.tools)) {
            if ([string]$candidate.name -eq 'running_game_get_node_properties') { $contractDescription = [string]$candidate.description; break }
        }
    } catch { }
    Check 'd6_contract_agrees_with_the_wire' (($contractDescription.Length -gt 0) -and ($contractDescription -eq $liveDescription)) `
        ("contract description == live description = {0}" -f ($contractDescription -eq $liveDescription))
} finally {
    Stop-Engine -Handle $editorHandle
    Stop-Engine -Handle $gameHandle
}

# TASK-154: the old `port_9877_guard` verdict stood here (it classified the state
# of the user editor's port). It is replaced by "both test ports are released
# again" - a fact this script is responsible for, unlike a port it never touches.
Check 'test_ports_released' (((Get-ListenerPid -Port_ $EditorPort) -eq -1) -and ((Get-ListenerPid -Port_ $GamePort) -eq -1)) `
    ("editor {0} owner={1}; game {2} owner={3}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort), $GamePort, (Get-ListenerPid -Port_ $GamePort))

$failed = @($script:Checks | Where-Object { -not $_.pass })
Write-Host ''
Write-Host '============================================================='
Write-Host (' TASK-032 evidence: {0} checks, {1} failed' -f $script:Checks.Count, $failed.Count)
Write-Host '============================================================='
foreach ($check in $script:Checks) {
    Write-Host ("[{0}] {1}" -f $(if ($check.pass) { 'PASS' } else { 'FAIL' }), $check.id)
}

$summary = [pscustomobject]@{
    engine       = (& $Engine --version) -join ''
    head         = (& git -C $RepoRoot rev-parse --short HEAD) -join ''
    checks       = $script:Checks
    failed_count = $failed.Count
}
Write-McpUtf8NoBom -Path (Join-Path $Root 'summary.json') -Text (ConvertTo-Json -InputObject $summary -Depth 8)
Write-Host ("summary: {0}" -f (Join-Path $Root 'summary.json'))
Write-Host ("evidence: {0}" -f $Ev)
if ($failed.Count -gt 0) { exit 1 }
exit 0
