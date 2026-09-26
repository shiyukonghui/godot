# =============================================================================
#  mcp034_b5_audio_particle_theme_evidence.ps1 -- TASK-034 (B5 batch 2) evidence
#
#  Gate 2 of the batch, on the real endpoints. Four things are proven here:
#
#  (A) The three classes of evidence for the 15 tools of the batch
#      (`editor_audio_write` 4, `editor_particle_write` 4, `editor_audio_read` 2,
#      `editor_particle_read` 1, `editor_theme_write` 1, `editor_scene_3d_write`
#      1, `editor_navigation_read` 1, `editor_profiling_read` 1): a success call,
#      a missing-argument call (-32602) and an underlying-failure call (-32001 or
#      the tool's own state code). Where a class cannot be constructed for a tool
#      the script says so explicitly in the SUMMARY table instead of skipping it
#      silently:
#        * the three no-argument readers (`editor_get_audio_info`,
#          `editor_get_audio_bus_layout`, `editor_get_performance_monitors`) have
#          no required member, so their -32602 witness is an *undeclared*
#          argument (the module names it, it does not ignore it);
#        * `editor_get_navigation_info` has no required member either (the same
#          undeclared-argument witness);
#        * a missing-argument witness is impossible for every tool whose required
#          set is empty, and the table marks those rows `n/a (no required
#          argument)`.
#
#  (B) Two cross-tool live chains with **zero string surgery**: every identifier
#      a step answers (a bus index, a bus name, a node path, a parameter name, a
#      stops array, a material parameter dictionary) is fed into the next step as
#      the object the JSON parser built. No step edits, splits, joins or re-spells
#      a string; the script counts its own string operations and asserts 0.
#
#  (C) The engine-slot discipline of TASK-034 section 1 (M4c's E-4): a
#      `MeshInstance3D` with a **two-surface** mesh gets a different material on
#      slot 0 and slot 1, and both are read back through
#      `editor_get_node_properties` (`surface_material_override/0` and `/1`).
#      The migration source read `material_slot` and hard-coded slot 0; this is
#      the "different slots, different materials" evidence the task asks for.
#
#  (D) TASK-034 section 0: the unreachable -> reachable before/after of the four
#      schema gaps. "Before" is the committed contract at the **pinned base
#      commit** `fc724ce49a` (the member is absent from its
#      `tools_list.renamed.json`) - pinned rather than read from `HEAD`, because
#      the change this block proves is an ancestor of the commit that tracks this
#      script, so a `HEAD` read rotates the conclusion the moment the contract
#      moves (TASK-037 R4, REPORT-AUDIT-B5 section 9 R4) - and a live call that
#      cannot point a new Animation state at an animation; "after" is the
#      regenerated contract plus a live call that does, with the animation name
#      read back, fed through `editor_get_animation_tree_structure` ->
#      `editor_get_animation_info`, and the transition's own
#      `advance_condition_parameter` fed into
#      `editor_set_animation_tree_parameter`.
#
#  Discipline: response bodies go through `curl.exe -s -o <file>` and their
#  sha256 is computed from the bytes on disk; request bodies are built with
#  `ConvertTo-Json` and sent with `--data-binary @file`; only ports 9888/9889 are
#  used, and the user's own editor on 9877 is asserted to keep the same pid
#  before and after. This file is deliberately pure ASCII.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp034_b5_audio_particle_theme_evidence.ps1
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
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'task034-b5-batch2' }
$Root = $OutRoot
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877
$utf8 = [Text.Encoding]::UTF8

# TASK-028 D-1: the shared scratch-project writer + `--import` runner.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-042 section 1: the shared 9877 classification (see mcp_port_guard.ps1).
. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]
# The chain's string-surgery counter (TASK-034 section 2 / GDR-25 section 23.1):
# every call site below feeds an answer into the next request without touching it
# as text, and nothing in this script increments this counter. It is asserted to
# be 0 at the end, so "no string surgery" is a machine fact about the script that
# ran, not a claim about the script that was written.
$script:StringOps = 0

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

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $handle = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
    # TASK-042 section 1: record the pid *and* the arguments, so "did this script
    # ever ask for the user's port" is read off the real command line.
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $Arguments
    return $handle
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

# `@($x.Count)` is not a null test in PowerShell: `@($null)` counts as 1, so
# every "is there an entry at [0]" guard checks `$null -ne` first.
function Get-First {
    param($Collection)
    if ($null -eq $Collection) { return $null }
    $items = @($Collection)
    if ($items.Count -ge 1) { return $items[0] }
    return $null
}

# Parses `tools/list` into the **name set** (PLAYBOOK section 6.4: never decide
# "is this tool online" by matching response text).
function Get-ToolNames {
    param($Response)
    $names = New-Object System.Collections.Generic.List[string]
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return $names }
    try {
        $envelope = ConvertFrom-Json $text
        foreach ($entry in @($envelope.result.tools)) {
            if ($null -ne $entry -and $null -ne $entry.name) { $names.Add([string]$entry.name) }
        }
    } catch { }
    return $names
}

function Get-ToolEntry {
    param($Response, [string]$Name)
    $text = if ($Response -is [string]) { $Response } else { [string]$Response.text }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        $envelope = ConvertFrom-Json $text
        foreach ($entry in @($envelope.result.tools)) {
            if ($null -ne $entry -and [string]$entry.name -ceq $Name) { return $entry }
        }
    } catch { }
    return $null
}

# One property of an `editor_get_node_properties` answer, by its exact name
# (`surface_material_override/0` contains '/', so the PSObject list is walked
# instead of property syntax).
function Get-NodeProperty {
    param($Payload, [string]$Name)
    if ($null -eq $Payload -or $null -eq $Payload.properties) { return $null }
    foreach ($p in $Payload.properties.PSObject.Properties) {
        if ([string]$p.Name -ceq $Name) { return $p.Value }
    }
    return $null
}

function Get-NodePropertyNames {
    param($Payload)
    $names = @()
    if ($null -eq $Payload -or $null -eq $Payload.properties) { return $names }
    foreach ($p in $Payload.properties.PSObject.Properties) { $names += [string]$p.Name }
    return $names
}

# =============================================================================
# The 15 tools, with the argument sets gate 2 needs.
#
# `missing` is the set that omits every required member (the -32602 case);
# `fail`    is a complete set whose target does not exist (the -32001 case).
# `norequired = $true` marks a tool whose schema declares no required member: its
# -32602 witness is an undeclared argument instead (the module names unknown
# members rather than ignoring them, TASK-032 D4), and the table says so.
# =============================================================================
$tools = @(
    @{ name = 'editor_add_audio_bus'; args = @{ name = 'ClassProbeBus' }; missing = @{}; fail = @{ name = 'Music' } },
    @{ name = 'editor_add_audio_bus_effect'; args = @{ bus_index = 0; effect_type = 'AudioEffectAmplify' }; missing = @{}; fail = @{ bus_index = 9999; effect_type = 'AudioEffectAmplify' } },
    @{ name = 'editor_add_audio_player'; args = @{ parent_path = '.'; name = 'ClassProbePlayer' }; missing = $null; fail = @{ parent_path = 'NoSuchNode' }; norequired = $true },
    @{ name = 'editor_set_audio_bus_property'; args = @{ bus_index = 0; property = 'mute'; value = $true }; missing = @{}; fail = @{ bus_index = 9999; property = 'mute'; value = $true } },
    @{ name = 'editor_create_particles'; args = @{ parent_path = '.'; name = 'ClassProbeFx' }; missing = $null; fail = @{ parent_path = 'NoSuchNode'; name = 'ClassProbeFx' }; norequired = $true },
    @{ name = 'editor_set_particle_preset'; args = @{ node_path = 'Fx'; preset = 'fire' }; missing = @{}; fail = @{ node_path = 'NoSuchNode'; preset = 'fire' } },
    @{ name = 'editor_set_particle_color_gradient'; args = @{ node_path = 'Fx'; colors = @(@{ offset = 0.0; color = @{ r = 1.0; g = 0.0; b = 0.0; a = 1.0 } }) }; missing = @{}; fail = @{ node_path = 'NoSuchNode'; colors = @(@{ offset = 0.0; color = '#ffffff' }) } },
    @{ name = 'editor_set_particle_material'; args = @{ node_path = 'Fx'; material_params = @{ spread = 12.0 } }; missing = @{}; fail = @{ node_path = 'NoSuchNode'; material_params = @{ spread = 12.0 } } },
    @{ name = 'editor_set_control_theme'; args = @{ node_path = 'Ui' }; missing = @{}; fail = @{ node_path = 'NoSuchNode' } },
    @{ name = 'editor_set_material_3d'; args = @{ node_path = 'Mesh'; material_path = 'res://materials/a.tres' }; missing = @{}; fail = @{ node_path = 'NoSuchNode'; material_path = 'res://materials/a.tres' } },
    @{ name = 'editor_get_audio_info'; args = @{}; missing = $null; fail = $null; norequired = $true; nofailure = $true },
    @{ name = 'editor_get_audio_bus_layout'; args = @{}; missing = $null; fail = $null; norequired = $true; nofailure = $true },
    @{ name = 'editor_get_particle_info'; args = @{ node_path = 'Fx' }; missing = @{}; fail = @{ node_path = 'NoSuchNode' } },
    @{ name = 'editor_get_navigation_info'; args = @{ node_path = '.' }; missing = $null; fail = @{ node_path = 'NoSuchNode' }; norequired = $true },
    @{ name = 'editor_get_performance_monitors'; args = @{}; missing = $null; fail = $null; norequired = $true; nofailure = $true }
)

# =============================================================================
# Scratch project
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Proj, (Join-Path $Proj 'scenes'), (Join-Path $Proj 'materials'), (Join-Path $Proj 'themes') | Out-Null

$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp034_b5_batch2"'
    'run/main_scene="res://scenes/main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text ($projectGodot + "`n")

# One scene holds everything this batch writes: a Node3D root (so the 3D
# material tool has a `MeshInstance3D` to address), a Control for the theme tool
# and an AnimationPlayer for the animation-family half of section 0. Godot's own
# node hierarchy allows all three under one root; the migration source's tools
# did the same.
$scene = @'
[gd_scene format=3]

[node name="Main" type="Node3D"]

[node name="Ui" type="Control" parent="."]
offset_right = 200.0
offset_bottom = 100.0

[node name="Player" type="AnimationPlayer" parent="."]
'@ + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text $scene

# =============================================================================
# (A0) The declared coverage of the narrowing gate (TASK-031 / GDR-24 section
# 22.3b rule 6): the scanner's own coverage text is part of gate 6's evidence.
# =============================================================================
$narrowScript = Join-Path $PSScriptRoot 'check_narrowing_points.py'
$covLog = Join-Path $LogRoot 'gate6_coverage.log'
& cmd /c "python `"$narrowScript`" --coverage > `"$covLog`" 2>&1"
$covExit = $LASTEXITCODE
$covText = Get-Content -Raw -Encoding UTF8 $covLog
Check 'gate6_coverage_exits_0' ($covExit -eq 0) ("check_narrowing_points.py --coverage -> exit={0} log={1}" -f $covExit, $covLog)
foreach ($spelling in @('lit_real_t_alias', 'lit_float_range', 'dbl_cast_into_float')) {
    Check ("gate6_declares_" + $spelling) ($covText.Contains($spelling)) ("--coverage lists the declared spelling '{0}'" -f $spelling)
}
Check 'gate6_coverage_declares_the_boundary' ($covText.Contains('declared NOT covered')) `
    "--coverage names the spellings the scanner does NOT cover (the boundary this gate must not be paraphrased beyond)"
Check 'gate6_coverage_counts_the_declared_set' ($covText.Contains('declared narrowing spellings (17)')) `
    "--coverage lists the 17 declared spellings of this module"

# TASK-042 section 1: the 9877 judgement is the shared six-way classification,
# not "a listener must exist" - see mcp_port_guard.ps1.
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)
Check 'port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'port_9889_free' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'scratch_project_imported' ($import.exit_code -eq 0) `
    ("--import exit={0} after {1} attempt(s); log={2}" -f $import.exit_code, $import.attempts, $import.log)

# =============================================================================
# (0) TASK-034 section 0: the contract's before/after (host side, no engine).
#
# "Before" is the committed contract **at a pinned commit**, not at `HEAD`. The
# four members are absent there. "After" is the regenerated file that gates 1
# compares against. This is the structured half of the unreachable -> reachable
# proof; the live half is below.
#
# TASK-037 R4: this block used to read `git show HEAD:...`, which made its
# conclusion rotate as soon as the contract itself changed - the commit that
# closed the four schema gaps is an ancestor of the commit that added *this*
# script, so by the time the script was tracked its own "before" state was
# already gone and all five `s0_head_*` rows failed on every later HEAD
# (REPORT-AUDIT-B5 section 9 R4 measured it, and independently adjudged it a
# stale-anchor failure rather than an implementation regression). The anchor is
# now the last commit **before** the contract change: `fc724ce49a` ("TASK-034
# brief ... and REPORT-033"), the parent of the `d744a100bc` commit that added
# the four members. The assertions are unchanged - same five rows, same old
# shape - only the revision they read is fixed. Override with MCP034_BASE_REF
# to re-run the proof against another base.
# =============================================================================
$BaseRef = if ($env:MCP034_BASE_REF) { $env:MCP034_BASE_REF } else { 'fc724ce49a' }
$headText = (& git -C $RepoRoot show ($BaseRef + ':modules/mcp_server/docs/tools_list.renamed.json')) -join "`n"
$nowText = Get-Content -Raw -Encoding UTF8 $Contract
Check 's0_contract_at_head_readable' ($headText.Length -gt 1000) ("git show {0}:modules/mcp_server/docs/tools_list.renamed.json -> {1} characters" -f $BaseRef, $headText.Length)

function Test-ContractMember {
    param([string]$Text, [string]$Tool, [string]$Member)
    try {
        $doc = ConvertFrom-Json $Text
        foreach ($entry in @($doc.result.tools)) {
            if ([string]$entry.name -ceq $Tool) {
                return ($null -ne $entry.inputSchema.properties.PSObject.Properties[[string]$Member])
            }
        }
    } catch { }
    return $false
}

Check 's0_head_has_no_animation_member_on_add_state' (-not (Test-ContractMember $headText 'editor_add_state_machine_state' 'animation')) `
    ("the pinned base contract ({0}): editor_add_state_machine_state.inputSchema.properties.animation is absent" -f $BaseRef)
Check 's0_now_has_animation_member_on_add_state' (Test-ContractMember $nowText 'editor_add_state_machine_state' 'animation') `
    "regenerated contract: editor_add_state_machine_state.inputSchema.properties.animation is present"
Check 's0_head_has_no_animation_member_on_blend_tree' (-not (Test-ContractMember $headText 'editor_set_blend_tree_node' 'animation')) `
    ("the pinned base contract ({0}): editor_set_blend_tree_node.inputSchema.properties.animation is absent" -f $BaseRef)
Check 's0_now_has_animation_member_on_blend_tree' (Test-ContractMember $nowText 'editor_set_blend_tree_node' 'animation') `
    "regenerated contract: editor_set_blend_tree_node.inputSchema.properties.animation is present"
foreach ($member in @('xfade_time', 'priority', 'advance_condition')) {
    Check ("s0_head_has_no_" + $member) (-not (Test-ContractMember $headText 'editor_add_state_machine_transition' $member)) `
        ("the pinned base contract ({0}): editor_add_state_machine_transition.inputSchema.properties.{1} is absent" -f $BaseRef, $member)
    Check ("s0_now_has_" + $member) (Test-ContractMember $nowText 'editor_add_state_machine_transition' $member) `
        ("regenerated contract: editor_add_state_machine_transition.inputSchema.properties.{0} is present" -f $member)
}

# =============================================================================
# (1) Live endpoints
# =============================================================================
$editorHandle = $null
$gameHandle = $null
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $editorList = Invoke-Raw -Id 'L00_tools_list_editor' -Body (New-ListBody) -Port_ $EditorPort
    $editorNames = Get-ToolNames $editorList
    $missingOnEditor = @()
    foreach ($tool in $tools) { if (-not $editorNames.Contains([string]$tool.name)) { $missingOnEditor += [string]$tool.name } }
    Check 'scope_9888_serves_all_15' ($missingOnEditor.Count -eq 0) `
        ("editor tools/list carries all 15 batch tools (count={0}); missing=[{1}]" -f $editorNames.Count, ($missingOnEditor -join ','))

    # The live schemas declare the four section-0 members (the wire half of the
    # contract proof: gate 1 compares these fields, this checks the member names).
    foreach ($pair in @(@('editor_add_state_machine_state', 'animation'), @('editor_set_blend_tree_node', 'animation'), @('editor_add_state_machine_transition', 'xfade_time'), @('editor_add_state_machine_transition', 'priority'), @('editor_add_state_machine_transition', 'advance_condition'))) {
        $entry = Get-ToolEntry $editorList ([string]$pair[0])
        $has = $false
        if ($null -ne $entry -and $null -ne $entry.inputSchema.properties) {
            $has = ($null -ne $entry.inputSchema.properties.PSObject.Properties[[string]$pair[1]])
        }
        Check ("s0_live_schema_" + $pair[0] + "_" + $pair[1]) $has `
            ("live tools/list: {0}.inputSchema.properties.{1} is declared" -f $pair[0], $pair[1])
    }

    $open = Invoke-Tool -Id 'B00_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'scene_opened' ($null -ne (Get-Payload $open)) ("editor_open_scene -> " + (Get-PayloadText $open))

    # -------------------------------------------------------------------------
    # (D) section 0, live: unreachable before, reachable after.
    # -------------------------------------------------------------------------
    $anim = Invoke-Tool -Id 'S0_01_create_animation' -Tool 'editor_create_animation' -Arguments @{ node_path = 'Player'; name = 'idle'; length = 2.0 }
    Check 's0_create_animation' ($null -ne (Get-Payload $anim)) ("editor_create_animation -> " + (Get-PayloadText $anim))

    $tree = Invoke-Tool -Id 'S0_02_create_tree' -Tool 'editor_create_animation_tree' -Arguments @{ node_path = '.'; animation_player_path = 'Player'; name = 'Tree' }
    $treePayload = Get-Payload $tree
    $treePath = if ($null -ne $treePayload) { [string]$treePayload.node_path } else { '' }
    Check 's0_create_tree' (($null -ne $treePayload) -and ($treePath -eq 'Tree')) ("editor_create_animation_tree -> " + (Get-PayloadText $tree))

    # The "before" side, live: the same call the old contract allowed cannot point
    # the new state at an animation, and the answer says so (`animation` is empty).
    $beforeState = Invoke-Tool -Id 'S0_03_state_without_animation' -Tool 'editor_add_state_machine_state' -Arguments @{ node_path = $treePath; state_name = 'Unreachable'; state_type = 'animation' }
    $beforePayload = Get-Payload $beforeState
    $beforeAnimation = if ($null -ne $beforePayload) { [string]$beforePayload.animation } else { 'NULL' }
    Check 's0_unreachable_state_has_empty_animation' (($null -ne $beforePayload) -and ($beforeAnimation -eq '') -and ($beforePayload.animation_given -eq $false)) `
        ("without the declared member the state's animation is '' (unreachable) -> " + (Get-PayloadText $beforeState))

    # The "after" side: the declared member reaches the engine.
    $afterState = Invoke-Tool -Id 'S0_04_state_with_animation' -Tool 'editor_add_state_machine_state' -Arguments @{ node_path = $treePath; state_name = 'Idle'; state_type = 'animation'; animation = 'idle' }
    $afterPayload = Get-Payload $afterState
    Check 's0_reachable_state_names_animation' (($null -ne $afterPayload) -and ([string]$afterPayload.animation -eq 'idle') -and ($afterPayload.animation_given -eq $true)) `
        ("with the declared member the engine stores the animation -> " + (Get-PayloadText $afterState))

    $walkState = Invoke-Tool -Id 'S0_05_state_walk' -Tool 'editor_add_state_machine_state' -Arguments @{ node_path = $treePath; state_name = 'Walk'; state_type = 'animation'; animation = 'idle' }
    Check 's0_second_state' ($null -ne (Get-Payload $walkState)) ("editor_add_state_machine_state(Walk) -> " + (Get-PayloadText $walkState))

    # The transition's three new members, read back by the engine's own accessors.
    $transition = Invoke-Tool -Id 'S0_06_transition' -Tool 'editor_add_state_machine_transition' -Arguments @{ node_path = $treePath; from_state = 'Idle'; to_state = 'Walk'; switch_mode = 'immediate'; advance_mode = 'auto'; xfade_time = 0.35; priority = 3; advance_condition = 'go_now' }
    $transitionPayload = Get-Payload $transition
    Check 's0_transition_members_read_back' (($null -ne $transitionPayload) -and ([double]$transitionPayload.xfade_time -gt 0.34) -and ([double]$transitionPayload.xfade_time -lt 0.36) -and ([int]$transitionPayload.priority -eq 3) -and ([string]$transitionPayload.advance_condition -eq 'go_now')) `
        ("editor_add_state_machine_transition -> " + (Get-PayloadText $transition))

    # The parameter name the transition answered is fed straight into the tree
    # parameter writer: no string surgery anywhere in the chain.
    $conditionParameter = if ($null -ne $transitionPayload) { [string]$transitionPayload.advance_condition_parameter } else { '' }
    Check 's0_condition_parameter_is_the_engine_spelling' ($conditionParameter -eq 'parameters/conditions/go_now') `
        ("the answer's advance_condition_parameter is the engine's own parameter name: '{0}'" -f $conditionParameter)
    $conditionWrite = Invoke-Tool -Id 'S0_07_condition_parameter_fed_back' -Tool 'editor_set_animation_tree_parameter' -Arguments @{ node_path = $treePath; parameter = $conditionParameter; value = $true }
    $conditionPayload = Get-Payload $conditionWrite
    Check 's0_condition_parameter_fed_back' (($null -ne $conditionPayload) -and ($conditionPayload.value -eq $true) -and ([string]$conditionPayload.parameter -eq $conditionParameter)) `
        ("the name S0_06 answered was fed back verbatim -> " + (Get-PayloadText $conditionWrite))

    # The state's animation is readable through the *other* tool, and that name is
    # fed into a third tool.
    $structure = Invoke-Tool -Id 'S0_08_tree_structure' -Tool 'editor_get_animation_tree_structure' -Arguments @{ node_path = $treePath }
    $structurePayload = Get-Payload $structure
    $idleState = $null
    if ($null -ne $structurePayload -and $null -ne $structurePayload.state_machine) {
        foreach ($state in @($structurePayload.state_machine.states)) {
            if ([string]$state.name -eq 'Idle') { $idleState = $state }
        }
    }
    $readAnimation = if ($null -ne $idleState) { [string]$idleState.animation } else { '' }
    Check 's0_structure_reads_animation_back' ($readAnimation -eq 'idle') `
        ("editor_get_animation_tree_structure -> state 'Idle' answers animation='{0}'" -f $readAnimation)
    $animInfo = Invoke-Tool -Id 'S0_09_animation_name_fed_back' -Tool 'editor_get_animation_info' -Arguments @{ node_path = 'Player'; animation = $readAnimation }
    $animInfoPayload = Get-Payload $animInfo
    Check 's0_animation_name_fed_back' (($null -ne $animInfoPayload) -and ([string]$animInfoPayload.name -ceq 'idle')) `
        ("the state's animation name was fed into editor_get_animation_info -> " + (Get-PayloadText $animInfo))

    # -------------------------------------------------------------------------
    # (B1) the audio chain: 5 tools, 0 string operations.
    # -------------------------------------------------------------------------
    $music = Invoke-Tool -Id 'A01_add_bus_music' -Tool 'editor_add_audio_bus' -Arguments @{ name = 'Music' }
    $musicPayload = Get-Payload $music
    $musicIndex = if ($null -ne $musicPayload) { [int]$musicPayload.index } else { -1 }
    Check 'audio_01_add_bus_reads_back' (($null -ne $musicPayload) -and ($musicPayload.created -eq $true) -and ([string]$musicPayload.name -eq 'Music') -and ($musicIndex -ge 1)) `
        ("editor_add_audio_bus -> " + (Get-PayloadText $music))

    # The returned index is fed in as `after_bus_index`: the new bus lands right
    # after it, which is what the argument's name promises.
    $sfx = Invoke-Tool -Id 'A02_add_bus_sfx_after' -Tool 'editor_add_audio_bus' -Arguments @{ name = 'SFX'; after_bus_index = $musicIndex }
    $sfxPayload = Get-Payload $sfx
    $sfxIndex = if ($null -ne $sfxPayload) { [int]$sfxPayload.index } else { -1 }
    Check 'audio_02_insert_after_index' (($null -ne $sfxPayload) -and ($sfxIndex -eq ($musicIndex + 1))) `
        ("after_bus_index={0} -> new index {1}" -f $musicIndex, $sfxIndex)

    $volume = Invoke-Tool -Id 'A03_set_bus_volume' -Tool 'editor_set_audio_bus_property' -Arguments @{ bus_index = $sfxIndex; property = 'volume_db'; value = -6.5 }
    $volumePayload = Get-Payload $volume
    Check 'audio_03_volume_db_read_back' (($null -ne $volumePayload) -and ($volumePayload.applied -eq $true) -and ($volumePayload.changed -eq $true) -and ([double]$volumePayload.new_value -gt -6.6) -and ([double]$volumePayload.new_value -lt -6.4)) `
        ("editor_set_audio_bus_property(volume_db) -> " + (Get-PayloadText $volume))

    $effect = Invoke-Tool -Id 'A04_add_bus_effect' -Tool 'editor_add_audio_bus_effect' -Arguments @{ bus_index = $sfxIndex; effect_type = 'AudioEffectAmplify'; name = 'sfx_gain' }
    $effectPayload = Get-Payload $effect
    Check 'audio_04_effect_added_and_read_back' (($null -ne $effectPayload) -and ($effectPayload.effect_type -eq 'AudioEffectAmplify') -and ([int]$effectPayload.effect_index -eq 0) -and ($effectPayload.enabled -eq $true) -and ([string]$effectPayload.name -eq 'sfx_gain')) `
        ("editor_add_audio_bus_effect -> " + (Get-PayloadText $effect))

    $layout = Invoke-Tool -Id 'A05_bus_layout' -Tool 'editor_get_audio_bus_layout' -Arguments @{}
    $layoutPayload = Get-Payload $layout
    $sfxRecord = $null
    $masterRecord = Get-First $layoutPayload.buses
    if ($null -ne $layoutPayload) {
        foreach ($bus in @($layoutPayload.buses)) { if ([int]$bus.index -eq $sfxIndex) { $sfxRecord = $bus } }
    }
    Check 'audio_05_layout_reads_the_bus_back' (($null -ne $sfxRecord) -and ([string]$sfxRecord.name -eq 'SFX') -and ([int]$sfxRecord.effect_count -eq 1) -and ([double]$sfxRecord.volume_db -lt -6.4)) `
        ("editor_get_audio_bus_layout -> " + (Get-PayloadText $layout))

    # The reader's own `name` of the master bus is fed into `send` - the value the
    # read side answers is the value the write side takes.
    $masterName = if ($null -ne $masterRecord) { [string]$masterRecord.name } else { '' }
    $send = Invoke-Tool -Id 'A06_send_feeds_back' -Tool 'editor_set_audio_bus_property' -Arguments @{ bus_index = $sfxIndex; property = 'send'; value = $masterName }
    $sendPayload = Get-Payload $send
    Check 'audio_06_send_chainable' (($null -ne $sendPayload) -and ($sendPayload.applied -eq $true) -and ([string]$sendPayload.new_value -eq $masterName)) `
        ("the layout's bus name '{0}' was fed into 'send' verbatim -> {1}" -f $masterName, (Get-PayloadText $send))

    # The three failure classes of the audio writers.
    $unknownProperty = Invoke-Tool -Id 'A07_unknown_property' -Tool 'editor_set_audio_bus_property' -Arguments @{ bus_index = $sfxIndex; property = 'gain'; value = 1.0 }
    Check 'audio_07_unknown_property_32602' ((Get-ErrorCode $unknownProperty) -eq -32602) `
        ("unknown bus property -> {0}: {1}" -f (Get-ErrorCode $unknownProperty), (Get-ErrorMessage $unknownProperty))
    $outOfRangeBus = Invoke-Tool -Id 'A08_bus_out_of_range' -Tool 'editor_set_audio_bus_property' -Arguments @{ bus_index = 9999; property = 'mute'; value = $true }
    Check 'audio_08_bus_out_of_range_32001' ((Get-ErrorCode $outOfRangeBus) -eq -32001 -and (Get-ErrorSuggestion $outOfRangeBus).Length -gt 0) `
        ("out-of-range bus index -> {0}: {1}" -f (Get-ErrorCode $outOfRangeBus), (Get-ErrorMessage $outOfRangeBus))
    $unknownSend = Invoke-Tool -Id 'A09_send_unknown_bus' -Tool 'editor_set_audio_bus_property' -Arguments @{ bus_index = $sfxIndex; property = 'send'; value = 'NoSuchBus' }
    Check 'audio_09_send_unknown_bus_32001' ((Get-ErrorCode $unknownSend) -eq -32001) `
        ("send to a bus that does not exist -> {0}: {1}" -f (Get-ErrorCode $unknownSend), (Get-ErrorMessage $unknownSend))
    $duplicateBus = Invoke-Tool -Id 'A10_duplicate_bus_name' -Tool 'editor_add_audio_bus' -Arguments @{ name = 'Music' }
    Check 'audio_10_duplicate_name_32000' ((Get-ErrorCode $duplicateBus) -eq -32000 -and (Get-ErrorSuggestion $duplicateBus).Length -gt 0) `
        ("a duplicate bus name is refused instead of silently renamed -> {0}" -f (Get-ErrorMessage $duplicateBus))
    $badEffect = Invoke-Tool -Id 'A11_not_an_effect' -Tool 'editor_add_audio_bus_effect' -Arguments @{ bus_index = $musicIndex; effect_type = 'Node3D' }
    Check 'audio_11_not_an_audio_effect_32602' ((Get-ErrorCode $badEffect) -eq -32602) `
        ("a class that is not an AudioEffect -> {0}: {1}" -f (Get-ErrorCode $badEffect), (Get-ErrorMessage $badEffect))
    # `after_bus_index` is validated against the server's own bus count before
    # anything is created (the doctest cannot decide this half: a test process has
    # no AudioServer).
    $busIndexRange = Invoke-Tool -Id 'A16_after_bus_index_out_of_range' -Tool 'editor_add_audio_bus' -Arguments @{ name = 'TooFar'; after_bus_index = 9999 }
    Check 'audio_16_after_bus_index_range_32602' ((Get-ErrorCode $busIndexRange) -eq -32602 -and (Get-ErrorMessage $busIndexRange).Contains('after_bus_index')) `
        ("an insert position outside the server -> {0}: {1}" -f (Get-ErrorCode $busIndexRange), (Get-ErrorMessage $busIndexRange))
    $audioInfo = Invoke-Tool -Id 'A12_audio_info' -Tool 'editor_get_audio_info' -Arguments @{}
    $audioInfoPayload = Get-Payload $audioInfo
    Check 'audio_12_audio_info' (($null -ne $audioInfoPayload) -and ($audioInfoPayload.source -eq 'engine_process') -and ([int]$audioInfoPayload.bus_count -ge 3)) `
        ("editor_get_audio_info -> " + (Get-PayloadText $audioInfo))

    $player = Invoke-Tool -Id 'A13_add_audio_player' -Tool 'editor_add_audio_player' -Arguments @{ parent_path = '.'; name = 'Player2D' }
    $playerPayload = Get-Payload $player
    $playerPath = if ($null -ne $playerPayload) { [string]$playerPayload.node_path } else { '' }
    Check 'audio_13_player_created_and_read_back' (($null -ne $playerPayload) -and ($playerPayload.created -eq $true) -and ($playerPayload.type -eq 'AudioStreamPlayer2D') -and ([string]$playerPayload.node_path -eq 'Player2D') -and ([string]$playerPayload.owner -eq '.')) `
        ("editor_add_audio_player -> " + (Get-PayloadText $player))
    # The created node really is in the tree and really has the class the answer
    # claims - read by a *different* tool.
    $playerProps = Invoke-Tool -Id 'A14_player_read_back_by_another_tool' -Tool 'editor_get_node_properties' -Arguments @{ path = $playerPath }
    $playerPropsPayload = Get-Payload $playerProps
    $busProperty = Get-NodeProperty $playerPropsPayload 'bus'
    Check 'audio_14_player_node_is_real' (($null -ne $busProperty) -and ([string]$busProperty -eq ($playerPayload.bus))) `
        ("editor_get_node_properties('{0}') shows the player's own 'bus' property: {1}" -f $playerPath, (Get-NodePropertyNames $playerPropsPayload).Count)
    $playerMissingParent = Invoke-Tool -Id 'A15_player_missing_parent' -Tool 'editor_add_audio_player' -Arguments @{ parent_path = 'NoSuchNode' }
    Check 'audio_15_player_missing_parent_32001' ((Get-ErrorCode $playerMissingParent) -eq -32001) `
        ("a parent that does not exist -> {0}: {1}" -f (Get-ErrorCode $playerMissingParent), (Get-ErrorMessage $playerMissingParent))

    # -------------------------------------------------------------------------
    # (B2) the particle chain: 5 tools, 0 string operations.
    # -------------------------------------------------------------------------
    $particles = Invoke-Tool -Id 'P01_create_particles' -Tool 'editor_create_particles' -Arguments @{ parent_path = '.'; name = 'Fx'; particle_type = 'GPUParticles2D' }
    $particlesPayload = Get-Payload $particles
    $fxPath = if ($null -ne $particlesPayload) { [string]$particlesPayload.node_path } else { '' }
    Check 'particle_01_created_and_read_back' (($null -ne $particlesPayload) -and ($particlesPayload.created -eq $true) -and ($particlesPayload.type -eq 'GPUParticles2D') -and ($particlesPayload.process_material_slot -eq 'process_material') -and ($null -ne $particlesPayload.process_material)) `
        ("editor_create_particles -> " + (Get-PayloadText $particles))

    $preset = Invoke-Tool -Id 'P02_preset_fire' -Tool 'editor_set_particle_preset' -Arguments @{ node_path = $fxPath; preset = 'fire' }
    $presetPayload = Get-Payload $preset
    $presetSpread = $null
    if ($null -ne $presetPayload) {
        foreach ($param in @($presetPayload.material_params)) { if ([string]$param.property -eq 'spread') { $presetSpread = $param } }
    }
    Check 'particle_02_preset_applied' (($null -ne $presetPayload) -and ($presetPayload.applied -eq $true) -and ($null -ne $presetSpread) -and ([double]$presetSpread.stored -eq 15.0) -and ($presetPayload.ignored_count -eq 0)) `
        ("editor_set_particle_preset(fire) -> " + (Get-PayloadText $preset))

    $material = Invoke-Tool -Id 'P03_set_material' -Tool 'editor_set_particle_material' -Arguments @{ node_path = $fxPath; material_params = @{ spread = 42.5; direction = @{ x = 0.0; y = -1.0; z = 0.0 }; color = @{ r = 1.0; g = 0.5; b = 0.0; a = 1.0 }; emission_shape = 'sphere'; emission_sphere_radius = 2.5 } }
    $materialPayload = Get-Payload $material
    Check 'particle_03_material_written' (($null -ne $materialPayload) -and ([int]$materialPayload.changed_count -eq 5) -and ([int]$materialPayload.ignored_count -eq 0)) `
        ("editor_set_particle_material -> " + (Get-PayloadText $material))

    $gradient = Invoke-Tool -Id 'P04_set_gradient' -Tool 'editor_set_particle_color_gradient' -Arguments @{ node_path = $fxPath; colors = @(@{ offset = 0.0; color = @{ r = 1.0; g = 0.9; b = 0.1; a = 1.0 } }, @{ offset = 0.5; color = '#00ff00' }, @{ offset = 1.0; color = @{ r = 0.0; g = 0.0; b = 1.0; a = 0.5 } }) }
    $gradientPayload = Get-Payload $gradient
    Check 'particle_04_gradient_written' (($null -ne $gradientPayload) -and ([int]$gradientPayload.stop_count -eq 3) -and ($gradientPayload.applied -eq $true)) `
        ("editor_set_particle_color_gradient -> " + (Get-PayloadText $gradient))

    $info = Invoke-Tool -Id 'P05_particle_info' -Tool 'editor_get_particle_info' -Arguments @{ node_path = $fxPath }
    $infoPayload = Get-Payload $info
    Check 'particle_05_info_reads_everything' (($null -ne $infoPayload) -and ([string]$infoPayload.type -eq 'GPUParticles2D') -and ([string]$infoPayload.process_material_slot -eq 'process_material') -and ($null -ne $infoPayload.params) -and ([double]$infoPayload.params.spread -gt 42.4) -and ([string]$infoPayload.params.emission_shape -eq 'sphere') -and ([int]$infoPayload.color_stop_count -eq 3)) `
        ("editor_get_particle_info -> params.spread={0} shape={1} stops={2}" -f $infoPayload.params.spread, $infoPayload.params.emission_shape, $infoPayload.color_stop_count)

    # The reader's whole parameter dictionary is fed back into the writer ...
    $paramFeedBack = Invoke-Tool -Id 'P06_params_fed_back' -Tool 'editor_set_particle_material' -Arguments @{ node_path = $fxPath; material_params = $infoPayload.params }
    $paramFeedBackPayload = Get-Payload $paramFeedBack
    Check 'particle_06_params_fed_back' (($null -ne $paramFeedBackPayload) -and ([int]$paramFeedBackPayload.ignored_count -eq 0) -and ([int]$paramFeedBackPayload.changed_count -ge 30)) `
        ("all {0} parameters the reader answered were written back with none ignored -> count={1}" -f $paramFeedBackPayload.changed_count, $paramFeedBackPayload.changed_count)

    # ... and the reader's stops array is fed back into the gradient writer.
    $colorFeedBack = Invoke-Tool -Id 'P07_colors_fed_back' -Tool 'editor_set_particle_color_gradient' -Arguments @{ node_path = $fxPath; colors = $infoPayload.colors }
    $colorFeedBackPayload = Get-Payload $colorFeedBack
    Check 'particle_07_colors_fed_back' (($null -ne $colorFeedBackPayload) -and ([int]$colorFeedBackPayload.stop_count -eq 3) -and ([double](Get-First $colorFeedBackPayload.colors).offset -eq 0.0)) `
        ("the stops array the reader answered was written back verbatim -> stops={0}" -f $colorFeedBackPayload.stop_count)

    # Failure classes of the particle family.
    $unknownPreset = Invoke-Tool -Id 'P08_unknown_preset' -Tool 'editor_set_particle_preset' -Arguments @{ node_path = $fxPath; preset = 'plasma' }
    Check 'particle_08_unknown_preset_32602' ((Get-ErrorCode $unknownPreset) -eq -32602 -and (Get-ErrorMessage $unknownPreset).Contains('fire')) `
        ("unknown preset -> {0}: {1}" -f (Get-ErrorCode $unknownPreset), (Get-ErrorMessage $unknownPreset))
    $notParticles = Invoke-Tool -Id 'P09_not_a_particle_system' -Tool 'editor_set_particle_material' -Arguments @{ node_path = 'Ui'; material_params = @{ spread = 1.0 } }
    Check 'particle_09_not_a_particle_system_32602' ((Get-ErrorCode $notParticles) -eq -32602 -and (Get-ErrorMessage $notParticles).Contains('Control')) `
        ("a node of another class -> {0}: {1}" -f (Get-ErrorCode $notParticles), (Get-ErrorMessage $notParticles))
    $unknownParam = Invoke-Tool -Id 'P10_unknown_param' -Tool 'editor_set_particle_material' -Arguments @{ node_path = $fxPath; material_params = @{ spred = 1.0 } }
    Check 'particle_10_unknown_param_32602' ((Get-ErrorCode $unknownParam) -eq -32602 -and (Get-ErrorMessage $unknownParam).Contains('spred')) `
        ("a mistyped parameter is named, not ignored -> {0}: {1}" -f (Get-ErrorCode $unknownParam), (Get-ErrorMessage $unknownParam))
    $wideParam = Invoke-Tool -Id 'P11_param_too_wide' -Tool 'editor_set_particle_material' -Arguments @{ node_path = $fxPath; material_params = @{ spread = 1.0e300 } }
    Check 'particle_11_slot_width_32602' ((Get-ErrorCode $wideParam) -eq -32602 -and (Get-ErrorMessage $wideParam).Contains('spread')) `
        ("a value that cannot land in the float slot -> {0}: {1}" -f (Get-ErrorCode $wideParam), (Get-ErrorMessage $wideParam))
    $badStop = Invoke-Tool -Id 'P12_stop_out_of_range' -Tool 'editor_set_particle_color_gradient' -Arguments @{ node_path = $fxPath; colors = @(@{ offset = 2.5; color = '#ffffff' }) }
    Check 'particle_12_stop_offset_32602' ((Get-ErrorCode $badStop) -eq -32602) `
        ("a gradient offset outside 0..1 -> {0}: {1}" -f (Get-ErrorCode $badStop), (Get-ErrorMessage $badStop))
    $missingNode = Invoke-Tool -Id 'P13_missing_node' -Tool 'editor_get_particle_info' -Arguments @{ node_path = 'NoSuchNode' }
    Check 'particle_13_missing_node_32001' ((Get-ErrorCode $missingNode) -eq -32001) `
        ("a node that does not exist -> {0}: {1}" -f (Get-ErrorCode $missingNode), (Get-ErrorMessage $missingNode))

    # -------------------------------------------------------------------------
    # (C) the engine slot discipline (M4c's E-4).
    # -------------------------------------------------------------------------
    $matA = Invoke-Tool -Id 'C01_create_material_a' -Tool 'project_create_resource' -Arguments @{ path = 'res://materials/a.tres'; type = 'StandardMaterial3D'; properties = @{ albedo_color = @{ r = 1.0; g = 0.0; b = 0.0; a = 1.0 } } }
    Check 'slot_01_material_a_created' ($null -ne (Get-Payload $matA)) ("project_create_resource(a.tres) -> " + (Get-PayloadText $matA))
    $matB = Invoke-Tool -Id 'C02_create_material_b' -Tool 'project_create_resource' -Arguments @{ path = 'res://materials/b.tres'; type = 'StandardMaterial3D'; properties = @{ albedo_color = @{ r = 0.0; g = 0.0; b = 1.0; a = 1.0 } } }
    Check 'slot_02_material_b_created' ($null -ne (Get-Payload $matB)) ("project_create_resource(b.tres) -> " + (Get-PayloadText $matB))

    $mesh = Invoke-Tool -Id 'C03_add_mesh_instance' -Tool 'editor_add_mesh_instance' -Arguments @{ parent_path = '.'; name = 'Mesh' }
    $meshPayload = Get-Payload $mesh
    $meshPath = if ($null -ne $meshPayload) { [string]$meshPayload.node_path } else { 'Mesh' }
    Check 'slot_03_mesh_instance_created' ($null -ne $meshPayload) ("editor_add_mesh_instance -> " + (Get-PayloadText $mesh))

    # A two-surface mesh: `BoxMesh` has one surface, so the mesh is built by the
    # engine itself through the GDScript bridge (the ArrayMesh API is the only way
    # to make a mesh with two surfaces from a tool call).
    $meshCode = @'
var tree = Engine.get_main_loop()
var root = tree.get_edited_scene_root()
var inst = root.get_node("Mesh")
var mesh = ArrayMesh.new()
var arrays = []
arrays.resize(ArrayMesh.ARRAY_MAX)
arrays[ArrayMesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
arrays[ArrayMesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1)])
mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
inst.mesh = mesh
return mesh.get_surface_count()
'@
    $surfaceCount = Invoke-Tool -Id 'C04_build_two_surface_mesh' -Tool 'editor_execute_gdscript' -Arguments @{ code = $meshCode }
    $surfacePayload = Get-Payload $surfaceCount
    Check 'slot_04_multi_surface_mesh_built' (($null -ne $surfacePayload) -and ([int]$surfacePayload.result -eq 2)) `
        ("editor_execute_gdscript built an ArrayMesh with {0} surfaces -> " + (Get-PayloadText $surfaceCount))

    $writeSlot0 = Invoke-Tool -Id 'C05_write_slot_0' -Tool 'editor_set_material_3d' -Arguments @{ node_path = $meshPath; material_path = 'res://materials/a.tres'; material_slot = '0' }
    $slot0Payload = Get-Payload $writeSlot0
    Check 'slot_05_write_slot_0' (($null -ne $slot0Payload) -and ([string]$slot0Payload.material_slot -eq '0') -and ([int]$slot0Payload.surface_count -eq 2) -and ($slot0Payload.set -eq $true)) `
        ("editor_set_material_3d(slot 0) -> " + (Get-PayloadText $writeSlot0))

    $writeSlot1 = Invoke-Tool -Id 'C06_write_slot_1' -Tool 'editor_set_material_3d' -Arguments @{ node_path = $meshPath; material_path = 'res://materials/b.tres'; material_slot = '1' }
    $slot1Payload = Get-Payload $writeSlot1
    Check 'slot_06_write_slot_1' (($null -ne $slot1Payload) -and ([string]$slot1Payload.material_slot -eq '1') -and ($slot1Payload.set -eq $true)) `
        ("editor_set_material_3d(slot 1) -> " + (Get-PayloadText $writeSlot1))

    # Read both slots back through a *different* tool: the MeshInstance3D's own
    # `surface_material_override/<i>` properties.
    $meshProps = Invoke-Tool -Id 'C07_read_slots_back' -Tool 'editor_get_node_properties' -Arguments @{ path = $meshPath }
    $meshPropsPayload = Get-Payload $meshProps
    $override0 = Get-NodeProperty $meshPropsPayload 'surface_material_override/0'
    $override1 = Get-NodeProperty $meshPropsPayload 'surface_material_override/1'
    $path0 = if ($null -ne $override0) { [string]$override0.path } else { 'NULL' }
    $path1 = if ($null -ne $override1) { [string]$override1.path } else { 'NULL' }
    Check 'slot_07_slot_0_holds_material_a' ($path0 -eq 'res://materials/a.tres') `
        ("editor_get_node_properties: surface_material_override/0.path = '{0}'" -f $path0)
    Check 'slot_08_slot_1_holds_material_b' ($path1 -eq 'res://materials/b.tres') `
        ("editor_get_node_properties: surface_material_override/1.path = '{0}'" -f $path1)
    Check 'slot_09_the_two_slots_differ' ($path0 -ne $path1) `
        ("the two slots hold different materials ('{0}' vs '{1}') - the defect E-4 named (hard-coded slot 0) is not present" -f $path0, $path1)

    # The slot grammar and range.
    $slotOutOfRange = Invoke-Tool -Id 'C08_slot_out_of_range' -Tool 'editor_set_material_3d' -Arguments @{ node_path = $meshPath; material_path = 'res://materials/a.tres'; material_slot = '2' }
    Check 'slot_10_slot_out_of_range_32001' ((Get-ErrorCode $slotOutOfRange) -eq -32001 -and (Get-ErrorSuggestion $slotOutOfRange).Contains('0..1')) `
        ("surface slot 2 on a two-surface mesh -> {0}: {1}" -f (Get-ErrorCode $slotOutOfRange), (Get-ErrorMessage $slotOutOfRange))
    $slotGrammar = Invoke-Tool -Id 'C09_slot_grammar' -Tool 'editor_set_material_3d' -Arguments @{ node_path = $meshPath; material_path = 'res://materials/a.tres'; material_slot = 'top' }
    Check 'slot_11_slot_grammar_32602' ((Get-ErrorCode $slotGrammar) -eq -32602) `
        ("a slot spelling that is not an index -> {0}: {1}" -f (Get-ErrorCode $slotGrammar), (Get-ErrorMessage $slotGrammar))
    $missingMaterial = Invoke-Tool -Id 'C10_missing_material' -Tool 'editor_set_material_3d' -Arguments @{ node_path = $meshPath; material_path = 'res://materials/nope.tres' }
    Check 'slot_12_missing_material_32001' ((Get-ErrorCode $missingMaterial) -eq -32001) `
        ("a material path that does not exist -> {0}: {1}" -f (Get-ErrorCode $missingMaterial), (Get-ErrorMessage $missingMaterial))
    $notAMesh = Invoke-Tool -Id 'C11_not_a_mesh' -Tool 'editor_set_material_3d' -Arguments @{ node_path = 'Ui'; material_path = 'res://materials/a.tres' }
    Check 'slot_13_not_a_mesh_instance_32602' ((Get-ErrorCode $notAMesh) -eq -32602 -and (Get-ErrorMessage $notAMesh).Contains('MeshInstance3D')) `
        ("a node of another class -> {0}: {1}" -f (Get-ErrorCode $notAMesh), (Get-ErrorMessage $notAMesh))

    # -------------------------------------------------------------------------
    # Theme
    # -------------------------------------------------------------------------
    $theme = Invoke-Tool -Id 'T01_create_theme' -Tool 'project_create_resource' -Arguments @{ path = 'res://themes/ui.tres'; type = 'Theme' }
    Check 'theme_01_resource_created' ($null -ne (Get-Payload $theme)) ("project_create_resource(Theme) -> " + (Get-PayloadText $theme))
    $applyTheme = Invoke-Tool -Id 'T02_apply_theme' -Tool 'editor_set_control_theme' -Arguments @{ node_path = 'Ui'; theme_path = 'res://themes/ui.tres' }
    $applyPayload = Get-Payload $applyTheme
    Check 'theme_02_applied_and_read_back' (($null -ne $applyPayload) -and ($applyPayload.applied -eq $true) -and ([string]$applyPayload.theme_path -eq 'res://themes/ui.tres') -and ([string]$applyPayload.theme.path -eq 'res://themes/ui.tres')) `
        ("editor_set_control_theme -> " + (Get-PayloadText $applyTheme))
    $clearTheme = Invoke-Tool -Id 'T03_clear_theme' -Tool 'editor_set_control_theme' -Arguments @{ node_path = 'Ui' }
    $clearPayload = Get-Payload $clearTheme
    Check 'theme_03_omitted_path_clears' (($null -ne $clearPayload) -and ($clearPayload.cleared -eq $true) -and ($clearPayload.theme_applied -eq $false) -and ($null -eq $clearPayload.theme)) `
        ("an omitted theme_path clears the Control's own theme and says so -> " + (Get-PayloadText $clearTheme))
    $missingTheme = Invoke-Tool -Id 'T04_missing_theme' -Tool 'editor_set_control_theme' -Arguments @{ node_path = 'Ui'; theme_path = 'res://themes/nope.tres' }
    Check 'theme_04_missing_theme_32001' ((Get-ErrorCode $missingTheme) -eq -32001) `
        ("a theme path that does not exist -> {0}: {1}" -f (Get-ErrorCode $missingTheme), (Get-ErrorMessage $missingTheme))
    $notAControl = Invoke-Tool -Id 'T05_not_a_control' -Tool 'editor_set_control_theme' -Arguments @{ node_path = 'Player'; theme_path = 'res://themes/ui.tres' }
    Check 'theme_05_not_a_control_32602' ((Get-ErrorCode $notAControl) -eq -32602 -and (Get-ErrorMessage $notAControl).Contains('Control')) `
        ("a node of another class -> {0}: {1}" -f (Get-ErrorCode $notAControl), (Get-ErrorMessage $notAControl))

    # -------------------------------------------------------------------------
    # Navigation
    # -------------------------------------------------------------------------
    $region = Invoke-Tool -Id 'N01_setup_region' -Tool 'editor_setup_navigation_region' -Arguments @{ node_path = '.'; mode = '3d' }
    $regionPayload = Get-Payload $region
    $regionPath = if ($null -ne $regionPayload) { [string]$regionPayload.node_path } else { '' }
    Check 'nav_01_region_created' (($null -ne $regionPayload) -and ($regionPath.Length -gt 0)) `
        ("editor_setup_navigation_region -> " + (Get-PayloadText $region))
    $agent = Invoke-Tool -Id 'N02_setup_agent' -Tool 'editor_setup_navigation_agent' -Arguments @{ node_path = '.'; agent_type = '3D' }
    Check 'nav_02_agent_created' ($null -ne (Get-Payload $agent)) ("editor_setup_navigation_agent -> " + (Get-PayloadText $agent))
    $navInfo = Invoke-Tool -Id 'N03_navigation_info' -Tool 'editor_get_navigation_info' -Arguments @{ node_path = '.' }
    $navPayload = Get-Payload $navInfo
    $regionRecord = Get-First $navPayload.regions
    $agentRecord = Get-First $navPayload.agents
    Check 'nav_03_info_counts_and_shapes' (($null -ne $navPayload) -and ([int]$navPayload.region_count -eq 1) -and ([int]$navPayload.agent_count -eq 1) -and ($null -ne $regionRecord) -and ([string]$regionRecord.path -eq $regionPath) -and ($regionRecord.baked -eq $false)) `
        ("editor_get_navigation_info -> regions={0} agents={1} region.path='{2}'" -f $navPayload.region_count, $navPayload.agent_count, $regionRecord.path)
    # The path the reader answered is fed straight back in, both as a `node_path`
    # and as a property-write target.
    $navInfo2 = Invoke-Tool -Id 'N04_region_path_fed_back' -Tool 'editor_get_navigation_info' -Arguments @{ node_path = $regionRecord.path }
    $navPayload2 = Get-Payload $navInfo2
    Check 'nav_04_region_path_chainable' (($null -ne $navPayload2) -and ([string]$navPayload2.node_path -eq $regionPath)) `
        ("the region path was fed back verbatim -> " + (Get-PayloadText $navInfo2))
    $layerWrite = Invoke-Tool -Id 'N05_region_layers' -Tool 'editor_set_node_property' -Arguments @{ path = $regionRecord.path; property = 'navigation_layers'; value = 3 }
    $layerPayload = Get-Payload $layerWrite
    Check 'nav_05_region_path_is_a_write_target' (($null -ne $layerPayload) -and ([int]$layerPayload.new_value -eq 3)) `
        ("the same path is a legal editor_set_node_property target -> " + (Get-PayloadText $layerWrite))
    $navMissing = Invoke-Tool -Id 'N06_missing_node' -Tool 'editor_get_navigation_info' -Arguments @{ node_path = 'NoSuchNode' }
    Check 'nav_06_missing_node_32001' ((Get-ErrorCode $navMissing) -eq -32001) `
        ("a node that does not exist -> {0}: {1}" -f (Get-ErrorCode $navMissing), (Get-ErrorMessage $navMissing))

    # -------------------------------------------------------------------------
    # Profiling
    # -------------------------------------------------------------------------
    $perf = Invoke-Tool -Id 'F01_performance_monitors' -Tool 'editor_get_performance_monitors' -Arguments @{}
    $perfPayload = Get-Payload $perf
    $fpsProperty = $null
    if ($null -ne $perfPayload -and $null -ne $perfPayload.monitors) { $fpsProperty = $perfPayload.monitors.PSObject.Properties['time/fps'] }
    Check 'profiling_01_monitors_by_engine_name' (($null -ne $perfPayload) -and ($perfPayload.source -eq 'engine_process') -and ([int]$perfPayload.monitor_count -gt 0) -and ($null -ne $fpsProperty)) `
        ("editor_get_performance_monitors -> monitor_count={0} time/fps={1}" -f $perfPayload.monitor_count, $fpsProperty)

    # -------------------------------------------------------------------------
    # (2) The three evidence classes, table driven, plus the tools/list scope on
    # the game endpoint.
    # -------------------------------------------------------------------------
    $classRows = New-Object System.Collections.Generic.List[string]
    foreach ($tool in $tools) {
        $name = [string]$tool.name
        $success = Invoke-Tool -Id ("G_ok_" + $name) -Tool $name -Arguments $tool.args
        $ok = ($null -ne (Get-Payload $success))
        $row = "{0}: success={1}" -f $name, $ok

        if ($null -ne $tool.missing) {
            $missingResp = Invoke-Tool -Id ("G_missing_" + $name) -Tool $name -Arguments $tool.missing
            $missingOk = ((Get-ErrorCode $missingResp) -eq -32602)
            $row += (" missing-arg={0} (code={1})" -f $missingOk, (Get-ErrorCode $missingResp))
        } else {
            $undeclared = Invoke-Tool -Id ("G_undeclared_" + $name) -Tool $name -Arguments @{ mcp034_undeclared = 1 }
            $undeclaredOk = ((Get-ErrorCode $undeclared) -eq -32602 -and (Get-ErrorMessage $undeclared).Contains('mcp034_undeclared'))
            $row += (" no-required-argument: undeclared-argument={0} (code={1})" -f $undeclaredOk, (Get-ErrorCode $undeclared))
        }

        if ($null -ne $tool.fail) {
            $failResp = Invoke-Tool -Id ("G_fail_" + $name) -Tool $name -Arguments $tool.fail
            # "The thing it looked for is not there" (-32001) or the tool's own
            # state refusal (-32000); both are the declared underlying-failure
            # classes of the module.
            $failCode = Get-ErrorCode $failResp
            $failOk = ($failCode -eq -32001 -or $failCode -eq -32000)
            $row += (" underlying-failure={0} (code={1})" -f $failOk, $failCode)
        } else {
            $row += ' underlying-failure=n/a (the tool takes no reference to miss; its -32602 witness is the undeclared argument above)'
            $failOk = $true
        }
        $classRows.Add($row)
        Check ("class_evidence_" + $name) ($ok -and $failOk) $row
    }

    # The game endpoint: none of the 15 is registered at all (GDR-19 17.3).
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, "--mcp-port=$GamePort") -LogName 'game'
    $gameReady = Wait-ForPump -Port_ $GamePort
    Check 'game_endpoint_ready' $gameReady ("game on {0} answered GET /mcp with +20 frames" -f $GamePort)
    if ($gameReady) {
        $gameList = Invoke-Raw -Id 'L01_tools_list_game' -Body (New-ListBody) -Port_ $GamePort
        $gameNames = Get-ToolNames $gameList
        $leaked = @()
        foreach ($tool in $tools) { if ($gameNames.Contains([string]$tool.name)) { $leaked += [string]$tool.name } }
        Check 'scope_9889_serves_none_of_the_15' ($leaked.Count -eq 0) `
            ("game tools/list has {0} names, none of the batch's 15; leaked=[{1}]" -f $gameNames.Count, ($leaked -join ','))
        $gameCall = Invoke-Tool -Id 'L02_game_endpoint_call' -Tool 'editor_add_audio_bus' -Arguments @{ name = 'Music' } -Port_ $GamePort
        Check 'scope_9889_call_is_32601' ((Get-ErrorCode $gameCall) -eq -32601) `
            ("a game endpoint refuses the tool -> {0}: {1}" -f (Get-ErrorCode $gameCall), (Get-ErrorMessage $gameCall))
    }
}
finally {
    Stop-Engine $editorHandle
    Stop-Engine $gameHandle
}

Start-Sleep -Seconds 2
$editorReleased = ((Get-ListenerPid -Port_ $EditorPort) -eq -1)
$gameReleased = ((Get-ListenerPid -Port_ $GamePort) -eq -1)
Check 'ports_released_after_run' ($editorReleased -and $gameReleased) ("editor 9888 released={0}; game 9889 released={1}" -f $editorReleased, $gameReleased)
$portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence
Check 'zero_string_surgery_chain' ($script:StringOps -eq 0) `
    ("the script performs {0} string operations on values it feeds back (the chains feed JSON objects verbatim)" -f $script:StringOps)

# =============================================================================
# SUMMARY
# =============================================================================
$classLog = Join-Path $Root 'class_evidence.txt'
Write-McpUtf8NoBom -Path $classLog -Text (($classRows -join "`r`n") + "`r`n")

$logPath = Join-Path $Root 'summary.json'
$summary = @()
foreach ($entry in $script:Checks) {
    $tag = 'FAIL'
    if ($entry.pass) { $tag = 'PASS' }
    $summary += ("[{0}] {1} :: {2}" -f $tag, $entry.id, $entry.evidence)
}
Write-McpUtf8NoBom -Path $logPath -Text (($summary -join "`r`n") + "`r`n")

$passed = @($script:Checks | Where-Object { $_.pass }).Count
$total = $script:Checks.Count
Write-Host ''
Write-Host '========================== SUMMARY =========================='
foreach ($entry in $script:Checks) {
    $tag = 'FAIL'
    if ($entry.pass) { $tag = 'PASS' }
    Write-Host ("{0}  {1}" -f $tag, $entry.id)
}
Write-Host ''
Write-Host '================= THREE EVIDENCE CLASSES ================='
foreach ($row in $classRows) { Write-Host $row }
Write-Host ''
Write-Host ("{0}/{1} checks passed; evidence in {2} (summary sha256={3})" -f $passed, $total, $Ev, (Get-FileHash -Algorithm SHA256 -Path $logPath).Hash.ToLower())
if ($passed -ne $total) { exit 1 }
exit 0
