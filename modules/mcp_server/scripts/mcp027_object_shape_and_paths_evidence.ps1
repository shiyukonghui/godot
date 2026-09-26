# =============================================================================
#  mcp027_object_shape_and_paths_evidence.ps1 -- TASK-027 evidence
#
#  Two measured claims, both taken on the live endpoints (9888 editor / 9889
#  game) and both kept as raw response files with sha256 so an independent
#  verifier can re-check the bytes:
#
#   D-8 (GDR-25 section 23.5) - an Object-valued property is closed in both
#   directions:
#     * an unset reference reads `null` (never `{}`);
#     * `{}` is refused with -32602 (and it never clears anything);
#     * a `res://` string and the read-back `{"type","path"}` shape are both
#       accepted, and the value that is read back afterwards is structurally the
#       value that was read before;
#     * writing `null` reads back `null`;
#     * a load failure is -32001 + suggestion; a `type` that is not what the file
#       loads as, and a resource the *property* does not declare, are -32602 with
#       both names in the message; the property is left untouched;
#     * a whole resource property bag (which contains Object-valued properties:
#       `script`, `sky`, ...) round-trips, which is what the old `{}` shape made
#       impossible (REPORT-026 section 2.1).
#
#   E-2 + E-8 - node paths are relative to the edited scene root:
#     * `editor_get_scene_tree` answers `"."` / `"Actor"` / `"Actor/Sprite2D"`
#       and no `@EditorNode@` anywhere; the engine's own absolute path is kept in
#       a separate `absolute_path` field;
#     * two *separate* editor processes answer byte-identically (sha256 of the
#       whole response);
#     * refusals name the node the same way the successes do (no `@EditorNode@`);
#     * a >=4 step cross-tool chain fed only from previous responses (0 string
#       operations by the caller).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp027_object_shape_and_paths_evidence.ps1 -Phase green
# =============================================================================

param(
    [int]$EditorPort = 9888,
    [int]$GamePort = 9889,
    [string]$Phase = 'green',
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP ('task027-object-and-paths-' + $Phase) }
$Root = $OutRoot
$Ev = Join-Path $Root 'evidence'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877

# TASK-028 D-1: the shared scratch-project writer and `--import` runner.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-047 section 1: the shared 9877 classification (see mcp_port_guard.ps1).
. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

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
    param([string]$Tool, $Arguments)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 0)
    if ($Port_ -eq 0) { $Port_ = $EditorPort }
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-Utf8NoBom -Path $bodyFile -Text (New-CallBody -Tool $Tool -Arguments $Arguments)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time 120 -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $script:LastSha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $script:LastBytes = $bytes
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] bytes={1} sha256={2}" -f $Id, $bytes.Length, $script:LastSha)
    Write-Host ("       {0}" -f $text)
    return $text
}

function Get-ResponseFile {
    param([string]$Id)
    return (Join-Path $Ev ("$Id.response.json"))
}

function Get-Payload {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.result) { return $null }
        return ConvertFrom-Json ([string]$envelope.result.content[0].text)
    } catch { return $null }
}

function Get-ErrorCode {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return 0 }
        return [int]$envelope.error.code
    } catch { return 0 }
}

function Get-ErrorMessage {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return '' }
        return [string]$envelope.error.message
    } catch { return '' }
}

function Get-ErrorSuggestion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return '' }
        return [string]$envelope.error.data.suggestion
    } catch { return '' }
}

# A structural spelling of a JSON value with the keys sorted, so "the value I
# read is the value I wrote" is a comparison of values and not of key order.
function Get-Canonical {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $names = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $parts = @()
        foreach ($n in $names) { $parts += ('"' + $n + '":' + (Get-Canonical $Value.$n)) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $parts = @()
        foreach ($item in $Value) { $parts += (Get-Canonical $item) }
        return '[' + ($parts -join ',') + ']'
    }
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
        return ([Convert]::ToDouble($Value)).ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    }
    return ([string]$Value)
}

function Test-IsNullValue {
    param($Value)
    return ($null -eq $Value)
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $proc = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $Root ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $Root ($LogName + '.err.log')) -WindowStyle Hidden
    # TASK-047 section 1: record the pid *and* the arguments, so "did this script
    # ever ask for the user's port" is read off the real command line.
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $proc.Id -Arguments $Arguments
    return $proc
}

function Wait-ForPump {
    param([int]$Port_, [int]$TimeoutMs = 300000)
    $frames = $null
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 1000
        $statusFile = Join-Path $Ev ("status-$Port_.json")
        & $Curl -s --max-time 5 -o $statusFile ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (Test-Path $statusFile) {
            $bytes = [IO.File]::ReadAllBytes($statusFile)
            if ($bytes.Length -gt 0) {
                try {
                    $probe = ConvertFrom-Json ([Text.Encoding]::UTF8.GetString($bytes))
                    if ($null -ne $frames -and ([int]$probe.frame_count - $frames) -ge 20) { return $true }
                    $frames = [int]$probe.frame_count
                } catch { }
            }
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

# =============================================================================
# Scratch project
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $Proj, (Join-Path $Proj 'scenes') | Out-Null

$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp027_object_and_paths"'
    'run/main_scene="res://scenes/main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
Write-Utf8NoBom -Path (Join-Path $Proj 'project.godot') -Text ($projectGodot + "`n")

# The scene: Main (root) / Actor / Sprite2D - two nesting levels, so `"Actor"`
# and `"Actor/Sprite2D"` are both observable, and the editor's own UI path has
# something to be wrong about.
$scene = @(
    '[gd_scene format=3]'
    ''
    '[node name="Main" type="Node2D"]'
    ''
    '[node name="Actor" type="Node2D" parent="."]'
    ''
    '[node name="Sprite2D" type="Sprite2D" parent="Actor"]'
) -join "`n"
Write-Utf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text ($scene + "`n")

Write-Utf8NoBom -Path (Join-Path $Proj 'probe_material.tres') -Text ("[gd_resource type=`"CanvasItemMaterial`" format=3]`n`n[resource]`n")
Write-Utf8NoBom -Path (Join-Path $Proj 'probe_gradient.tres') -Text ("[gd_resource type=`"Gradient`" format=3]`n`n[resource]`noffsets = PackedFloat32Array(0, 1)`ncolors = PackedColorArray(1, 0, 0, 1, 0, 0, 1, 1)`n")
Write-Utf8NoBom -Path (Join-Path $Proj 'environment.tres') -Text ("[gd_resource type=`"Environment`" format=3]`n`n[resource]`n")
Write-Utf8NoBom -Path (Join-Path $Proj 'probe.gd') -Text ("extends Object`n`nvar probe := true`n")

$userPidBefore = Get-ListenerPid -Port_ $UserPort
# TASK-047 section 1: the 9877 judgement is the shared six-way classification,
# not "a listener must exist". The old `port_9877_owner_before` check asserted
# `($userPidBefore -gt 0)`, which is an *environment precondition* (the user
# running Godot) and fails forever when 9877 has no listener - a red that says
# nothing about this script and hides a real regression. The shared guard is
# strictly stronger: it also decides "did this script ever ask for 9877" from the
# real pids and command lines it started.
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("user editor on {0} before: pid={1} (never touched; judged by the shared guard)" -f $UserPort, $userPidBefore)
Check 'port_9888_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'port_9889_free' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))

# TASK-028 D-1: both imports now go through the shared guard, which checks the
# exit code, retries a bounded number of times and prints the command, the code
# and the log tail on every failure. The check below is kept (with its id) so the
# record of "the first import of a brand-new project directory is the fragile
# one" stays visible: the attempts are part of the evidence.
$import1 = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $Root -Name 'import1'
$import2 = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $Root -Name 'import2'
# TASK-047 section 1: `Import-McpProject` returns the exact command line it ran,
# so an `--import` process that asked for 9877 would be caught too.
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import1.command
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import2.command
Check 'scratch_project_import_second_run' ($import2.exit_code -eq 0) `
    ("first --import exit={0} after {1} attempt(s); second --import exit={2} after {3} attempt(s)" -f `
            $import1.exit_code, $import1.attempts, $import2.exit_code, $import2.attempts)

$editorHandle = $null
$editor2Handle = $null
$gameHandle = $null

try {
    # =========================================================================
    # Phase 1 - the editor endpoint (9888)
    # =========================================================================
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor1'
    Check 'editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $openText = Invoke-Tool -Id 'P1_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'P1_scene_opened' ((Get-ErrorCode $openText) -eq 0 -and $null -ne (Get-Payload $openText)) ("code={0} payload={1}" -f (Get-ErrorCode $openText), (ConvertTo-Json (Get-Payload $openText) -Compress -Depth 8))

    # --- E-2: the tree answers root-relative paths ---------------------------
    $treeText1 = Invoke-Tool -Id 'P2_tree_run1' -Tool 'editor_get_scene_tree' -Arguments @{}
    $tree1 = Get-Payload $treeText1
    $rootPath = ''
    $actorPath = ''
    $spritePath = ''
    $rootAbsolute = ''
    $actorAbsolute = ''
    if ($null -ne $tree1 -and $null -ne $tree1.tree) {
        $rootPath = [string]$tree1.tree.path
        $rootAbsolute = [string]$tree1.tree.absolute_path
        $actor = @($tree1.tree.children)[0]
        if ($null -ne $actor) {
            $actorPath = [string]$actor.path
            $actorAbsolute = [string]$actor.absolute_path
            $sprite = @($actor.children)[0]

    $badPathText = Invoke-Tool -Id 'P17_write_material_missing_resource' -Tool 'editor_set_node_property' `
        -Arguments @{ path = $spriteRelPath; property = 'material'; value = 'res://does_not_exist.tres' }
    Check 'D8_node_load_failure_is_-32001_with_a_suggestion' `
        (((Get-ErrorCode $badPathText) -eq -32001) -and (-not [string]::IsNullOrEmpty((Get-ErrorSuggestion $badPathText)))) `
        ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $badPathText), (Get-ErrorMessage $badPathText), (Get-ErrorSuggestion $badPathText))

    $afterRefusalsText = Invoke-Tool -Id 'P18_read_material_after_refusals' -Tool 'editor_get_node_properties' `
        -Arguments @{ path = $spriteRelPath; properties = @('material') }
    $afterRefusals = Get-Payload $afterRefusalsText
    Check 'D8_refusals_left_the_property_untouched' ($null -ne $afterRefusals -and (Test-IsNullValue $afterRefusals.properties.material)) `
        ("material after the three refusals = {0} (still the cleared value)" -f (ConvertTo-Json $afterRefusals.properties.material -Compress -Depth 8))

    # --- D-8 on the resource-property path ----------------------------------
    # A `Gradient` (7 stored properties, `script` among them) instead of the
    # `Environment`: the reader's 64-property limit would otherwise cut `script`
    # out of the re-read and the equality would be about the limit, not the shape.
    # `Environment` is still used below for the whole-bag check, where its
    # Object-valued `sky` is exactly the value that used to break the bag.
    $envReadText = Invoke-Tool -Id 'P19_read_resource' -Tool 'project_read_resource' -Arguments @{ path = 'res://probe_gradient.tres' }
    $envRead = Get-Payload $envReadText
    $envScriptUnset = ($null -ne $envRead -and ($null -ne $envRead.properties) -and (Test-IsNullValue $envRead.properties.script))
    Check 'D8_resource_unset_object_reads_null' $envScriptUnset `
        ("properties.script = {0}" -f (ConvertTo-Json $envRead.properties.script -Compress -Depth 8))

    $envEmptyText = Invoke-Tool -Id 'P20_edit_resource_script_empty' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ script = @{} } }
    Check 'D8_resource_empty_object_is_-32602' ((Get-ErrorCode $envEmptyText) -eq -32602) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $envEmptyText), (Get-ErrorMessage $envEmptyText))

    $envStringText = Invoke-Tool -Id 'P21_edit_resource_script_string' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ script = 'res://probe.gd' } }
    $envStringPayload = Get-Payload $envStringText
    $scriptShape = $null
    if ($null -ne $envStringPayload) { $scriptShape = $envStringPayload.changed.script.new }
    Check 'D8_resource_res_string_is_accepted' `
        (((Get-ErrorCode $envStringText) -eq 0) -and ($null -ne $scriptShape) -and ([string]$scriptShape.path -eq 'res://probe.gd') -and ([string]$scriptShape.type -eq 'GDScript')) `
        ("code={0} changed.script.new={1}" -f (Get-ErrorCode $envStringText), (ConvertTo-Json $scriptShape -Compress -Depth 8))

    $envBackText = Invoke-Tool -Id 'P22_edit_resource_script_readback' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ script = $scriptShape } }
    $envBackPayload = Get-Payload $envBackText
    Check 'D8_resource_read_shape_is_accepted' `
        (((Get-ErrorCode $envBackText) -eq 0) -and ((Get-Canonical $envBackPayload.changed.script.new) -ceq (Get-Canonical $scriptShape))) `
        ("code={0} changed.script.new={1}" -f (Get-ErrorCode $envBackText), (ConvertTo-Json $envBackPayload.changed.script.new -Compress -Depth 8))

    $envRead2Text = Invoke-Tool -Id 'P23_read_resource_again' -Tool 'project_read_resource' -Arguments @{ path = 'res://probe_gradient.tres' }
    $envRead2 = Get-Payload $envRead2Text
    Check 'D8_resource_reread_is_equal' `
        (($null -ne $envRead2) -and ($null -ne $envRead2.properties) -and ((Get-Canonical $envRead2.properties.script) -ceq (Get-Canonical $scriptShape))) `
        ("properties.script = {0}" -f (Get-Canonical $envRead2.properties.script))

    $envWrongTypeText = Invoke-Tool -Id 'P24_edit_resource_script_wrong_type' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ script = @{ type = 'CanvasItemMaterial'; path = 'res://probe_material.tres' } } }
    Check 'D8_resource_type_mismatch_is_-32602_with_both_names' `
        (((Get-ErrorCode $envWrongTypeText) -eq -32602) -and (Get-ErrorMessage $envWrongTypeText).Contains('CanvasItemMaterial') -and (Get-ErrorMessage $envWrongTypeText).Contains("declared for a 'Script'")) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $envWrongTypeText), (Get-ErrorMessage $envWrongTypeText))

    $envWrongType2Text = Invoke-Tool -Id 'P24b_payload_type_mismatch' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ script = @{ type = 'Node'; path = 'res://probe.gd' } } }
    Check 'D8_payload_type_mismatch_is_-32602_with_both_names' `
        (((Get-ErrorCode $envWrongType2Text) -eq -32602) -and (Get-ErrorMessage $envWrongType2Text).Contains("names type 'Node'") -and (Get-ErrorMessage $envWrongType2Text).Contains('GDScript')) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $envWrongType2Text), (Get-ErrorMessage $envWrongType2Text))

    $envBadPathText = Invoke-Tool -Id 'P25_edit_resource_script_missing' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ script = 'res://does_not_exist.gd' } }
    Check 'D8_resource_load_failure_is_-32001_with_a_suggestion' `
        (((Get-ErrorCode $envBadPathText) -eq -32001) -and (-not [string]::IsNullOrEmpty((Get-ErrorSuggestion $envBadPathText)))) `
        ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $envBadPathText), (Get-ErrorMessage $envBadPathText), (Get-ErrorSuggestion $envBadPathText))

    $envNullText = Invoke-Tool -Id 'P26_edit_resource_script_null' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ script = $null } }
    $envNullPayload = Get-Payload $envNullText
    Check 'D8_resource_null_write_reads_null' `
        (((Get-ErrorCode $envNullText) -eq 0) -and (Test-IsNullValue $envNullPayload.changed.script.new)) `
        ("code={0} changed.script.new={1}" -f (Get-ErrorCode $envNullText), (ConvertTo-Json $envNullPayload.changed.script.new -Compress -Depth 8))

    $envRead3Text = Invoke-Tool -Id 'P27_read_resource_after_null' -Tool 'project_read_resource' -Arguments @{ path = 'res://probe_gradient.tres' }
    $envRead3 = Get-Payload $envRead3Text
    Check 'D8_resource_null_reread_is_null' ($null -ne $envRead3 -and (Test-IsNullValue $envRead3.properties.script)) `
        ("properties.script = {0}" -f (ConvertTo-Json $envRead3.properties.script -Compress -Depth 8))

    # --- the whole property bag of a resource with Object properties ---------
    $envWholeReadText = Invoke-Tool -Id 'P28a_read_environment' -Tool 'project_read_resource' -Arguments @{ path = 'res://environment.tres' }
    $envWholeRead = Get-Payload $envWholeReadText
    $wholeText = Invoke-Tool -Id 'P28_edit_environment_whole_bag' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://environment.tres'; properties = $envWholeRead.properties }
    Check 'D8_whole_resource_bag_round_trips' ((Get-ErrorCode $wholeText) -eq 0) `
        ("code={0} message='{1}' (the bag contains Object-valued properties: `sky`, `script`; the old `{{}}` shape made this -32602)" -f (Get-ErrorCode $wholeText), (Get-ErrorMessage $wholeText))

    # --- E-2 cross-process reproducibility -----------------------------------
    Stop-Engine -Handle $editorHandle
    $editorHandle = $null
    Start-Sleep -Milliseconds 1500
    $editor2Handle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor2'
    Check 'editor_second_process_ready' (Wait-ForPump -Port_ $EditorPort) ("a fresh editor process on {0} is ready" -f $EditorPort)
    $open2Text = Invoke-Tool -Id 'P29_open_scene_second_process' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' }
    Check 'P29_scene_opened_in_the_second_process' ((Get-ErrorCode $open2Text) -eq 0) ("code={0}" -f (Get-ErrorCode $open2Text))
    $treeText2 = Invoke-Tool -Id 'P30_tree_run2' -Tool 'editor_get_scene_tree' -Arguments @{}
    $tree2 = Get-Payload $treeText2
    $tree2RootPath = ''
    $tree2ActorPath = ''
    $tree2SpritePath = ''
    if ($null -ne $tree2 -and $null -ne $tree2.tree) {
        $tree2RootPath = [string]$tree2.tree.path
        $a2 = @($tree2.tree.children)[0]
        if ($null -ne $a2) {
            $tree2ActorPath = [string]$a2.path
            $s2 = @($a2.children)[0]
            if ($null -ne $s2) { $tree2SpritePath = [string]$s2.path }
        }
    }
    Check 'E2_cli_two_process_paths_are_equal' `
        (($tree2RootPath -eq $rootPath) -and ($tree2ActorPath -eq $actorPath) -and ($tree2SpritePath -eq $spritePath)) `
        ("process 1: '{0}'/'{1}'/'{2}'  process 2: '{3}'/'{4}'/'{5}'" -f $rootPath, $actorPath, $spritePath, $tree2RootPath, $tree2ActorPath, $tree2SpritePath)
    Check 'E2_cross_process_responses_are_byte_identical' ($script:LastSha -eq $treeShaRun1) `
        ("process 2 sha256={0}; process 1 sha256={1}" -f $script:LastSha, $treeShaRun1)
    Check 'E2_run2_no_path_field_is_absolute' (-not $treeText2.Contains('\"path\":\"/')) `
        ('run 2 response has a path field whose value starts with / : ' + $treeText2.Contains('\"path\":\"/'))

    # =========================================================================
    # Phase 2 - the game endpoint (9889)
    # =========================================================================
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, "--mcp-port=$GamePort") -LogName 'game'
    Check 'game_endpoint_ready' (Wait-ForPump -Port_ $GamePort) ("game on {0} answered GET /mcp with +20 frames" -f $GamePort)

    $gameTreeText = Invoke-Tool -Id 'G0_game_scene_tree' -Tool 'running_game_get_scene_tree' -Arguments @{} -Port_ $GamePort
    $gameTree = Get-Payload $gameTreeText
    Check 'G0_game_scene_loaded' ($null -ne $gameTree -and $null -ne $gameTree.tree) `
        ("running_game_get_scene_tree = {0}" -f (ConvertTo-Json $gameTree -Compress -Depth 10))

    # Node paths on the game endpoint are resolved against the *current scene*
    # root (`resolve_game_node`), so the spelling here is `"Actor/Sprite2D"` - the
    # same relative form the editor answers with.
    $gamePath = 'Actor/Sprite2D'
    $gameReadUnsetText = Invoke-Tool -Id 'G1_game_read_material_unset' -Tool 'running_game_get_node_properties' `
        -Arguments @{ node_path = $gamePath; properties = @('material') } -Port_ $GamePort
    $gameReadUnset = Get-Payload $gameReadUnsetText
    Check 'D8_game_unset_reads_null' ($null -ne $gameReadUnset -and (Test-IsNullValue $gameReadUnset.properties.material)) `
        ("material = {0}" -f (ConvertTo-Json $gameReadUnset.properties.material -Compress -Depth 8))

    $gameStringText = Invoke-Tool -Id 'G2_game_write_material_string' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = $gamePath; property = 'material'; value = 'res://probe_material.tres' } -Port_ $GamePort
    Check 'D8_game_res_string_is_accepted' ((Get-ErrorCode $gameStringText) -eq 0) `
        ("code={0} new_value={1}" -f (Get-ErrorCode $gameStringText), (ConvertTo-Json (Get-Payload $gameStringText).new_value -Compress -Depth 8))

    $gameReadSetText = Invoke-Tool -Id 'G3_game_read_material_set' -Tool 'running_game_get_node_properties' `
        -Arguments @{ node_path = $gamePath; properties = @('material') } -Port_ $GamePort
    $gameMaterialShape = (Get-Payload $gameReadSetText).properties.material
    Check 'D8_game_set_reads_the_type_path_shape' `
        (($null -ne $gameMaterialShape) -and ([string]$gameMaterialShape.type -eq 'CanvasItemMaterial') -and ([string]$gameMaterialShape.path -eq 'res://probe_material.tres')) `
        ("material = {0}" -f (ConvertTo-Json $gameMaterialShape -Compress -Depth 8))

    $gameBackText = Invoke-Tool -Id 'G4_game_write_material_readback' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = $gamePath; property = 'material'; value = $gameMaterialShape } -Port_ $GamePort
    Check 'D8_game_read_shape_is_accepted' `
        (((Get-ErrorCode $gameBackText) -eq 0) -and ((Get-Canonical (Get-Payload $gameBackText).new_value) -ceq (Get-Canonical $gameMaterialShape))) `
        ("code={0} new_value={1}" -f (Get-ErrorCode $gameBackText), (ConvertTo-Json (Get-Payload $gameBackText).new_value -Compress -Depth 8))

    $gameEmptyText = Invoke-Tool -Id 'G5_game_write_material_empty' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = $gamePath; property = 'material'; value = @{} } -Port_ $GamePort
    Check 'D8_game_empty_object_is_-32602' ((Get-ErrorCode $gameEmptyText) -eq -32602) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $gameEmptyText), (Get-ErrorMessage $gameEmptyText))

    $gameClearText = Invoke-Tool -Id 'G6_game_write_material_null' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = $gamePath; property = 'material'; value = $null } -Port_ $GamePort
    Check 'D8_game_null_write_reads_null' `
        (((Get-ErrorCode $gameClearText) -eq 0) -and (Test-IsNullValue (Get-Payload $gameClearText).new_value)) `
        ("code={0} new_value={1}" -f (Get-ErrorCode $gameClearText), (ConvertTo-Json (Get-Payload $gameClearText).new_value -Compress -Depth 8))

    $gameReadClearedText = Invoke-Tool -Id 'G7_game_read_material_cleared' -Tool 'running_game_get_node_properties' `
        -Arguments @{ node_path = $gamePath; properties = @('material') } -Port_ $GamePort
    $gameReadCleared = Get-Payload $gameReadClearedText
    Check 'D8_game_cleared_reread_is_null' ($null -ne $gameReadCleared -and (Test-IsNullValue $gameReadCleared.properties.material)) `
        ("material = {0}" -f (ConvertTo-Json $gameReadCleared.properties.material -Compress -Depth 8))

    $gameErrText = Invoke-Tool -Id 'G8_game_missing_property_message' -Tool 'running_game_set_node_property' `
        -Arguments @{ node_path = $gamePath; property = 'no_such_property_xyz'; value = 1 } -Port_ $GamePort
    $gameErrMessage = Get-ErrorMessage $gameErrText
    # The game side keeps the engine's own tree path on purpose (E-2 is the
    # editor's spelling); what is asserted here is that it is a *tree* path and
    # never the editor's UI layout.
    Check 'G8_game_refusal_is_not_an_editor_path' `
        (((Get-ErrorCode $gameErrText) -eq -32001) -and ($gameErrMessage -match "on node '/root/Main/Actor/Sprite2D'") -and (-not $gameErrMessage.Contains('@EditorNode@'))) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $gameErrText), $gameErrMessage)

    $gameEnvEmptyText = Invoke-Tool -Id 'G9_game_resource_empty_object' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ script = @{} } } -Port_ $GamePort
    Check 'D8_game_resource_empty_object_is_-32602' ((Get-ErrorCode $gameEnvEmptyText) -eq -32602) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $gameEnvEmptyText), (Get-ErrorMessage $gameEnvEmptyText))

    $gameEnvStringText = Invoke-Tool -Id 'G10_game_resource_res_string' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ script = 'res://probe.gd' } } -Port_ $GamePort
    Check 'D8_game_resource_res_string_is_accepted' ((Get-ErrorCode $gameEnvStringText) -eq 0) `
        ("code={0} changed.script.new={1}" -f (Get-ErrorCode $gameEnvStringText), (ConvertTo-Json (Get-Payload $gameEnvStringText).changed.script.new -Compress -Depth 8))

    $gameEnvNullText = Invoke-Tool -Id 'G11_game_resource_null' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://probe_gradient.tres'; properties = @{ script = $null } } -Port_ $GamePort
    Check 'D8_game_resource_null_write_reads_null' `
        (((Get-ErrorCode $gameEnvNullText) -eq 0) -and (Test-IsNullValue (Get-Payload $gameEnvNullText).changed.script.new)) `
        ("code={0} changed.script.new={1}" -f (Get-ErrorCode $gameEnvNullText), (ConvertTo-Json (Get-Payload $gameEnvNullText).changed.script.new -Compress -Depth 8))
} finally {
    Stop-Engine -Handle $gameHandle
    Stop-Engine -Handle $editorHandle
    Stop-Engine -Handle $editor2Handle
    Start-Sleep -Milliseconds 1500
    $userPidAfter = Get-ListenerPid -Port_ $UserPort
    $portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter $userPidAfter
    Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence
    Check 'port_9888_free_after' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
    Check 'port_9889_free_after' ((Get-ListenerPid -Port_ $GamePort) -eq -1) ("port {0} owner={1}" -f $GamePort, (Get-ListenerPid -Port_ $GamePort))
}

# The chain's own "string operations by the caller = 0" claim, checked
# mechanically over this script's chain region (the `D8_chain_*` checks and the
# `P9..P14` calls between them): no Split/Replace/Substring/Trim/regex/cast may
# appear there, and every argument is a variable taken from a previous response.
$chainStart = (Select-String -Path $PSCommandPath -Pattern "D8 on the node path" | Select-Object -First 1).LineNumber
$chainEnd = (Select-String -Path $PSCommandPath -Pattern "D8 refusals on the node path" | Select-Object -First 1).LineNumber
$chainText = ''
if ($chainStart -and $chainEnd -and $chainEnd -gt $chainStart) {
    $chainText = (Get-Content $PSCommandPath)[($chainStart - 1)..($chainEnd - 2)] -join "`n"
}
$forbidden = @('.Split(', '.Replace(', '.Substring(', '.Trim(', '-match ', '-replace ', '[double]', '[int]', '[regex]')
$foundForbidden = @()
foreach ($token in $forbidden) { if ($chainText.Contains($token)) { $foundForbidden += $token } }
Check 'E2_zero_string_surgery_chain' ($foundForbidden.Count -eq 0 -and $chainText.Length -gt 0) `
    ("forbidden tokens in the chain region (path/value arguments are variables taken from the previous response; the only conversions present are ConvertTo-Json in the evidence text, never in an argument): {0}" -f (($foundForbidden -join ', ') + $(if ($foundForbidden.Count -eq 0) { '<none>' } else { '' })))

$logPath = Join-Path $Ev 'evidence.log.txt'
$summary = @()
foreach ($entry in $script:Checks) {
    $entryTag = if ($entry.pass) { 'PASS' } else { 'FAIL' }
    $summary += ("[{0}] {1} :: {2}" -f $entryTag, $entry.id, $entry.evidence)
}
Write-Utf8NoBom -Path $logPath -Text (($summary -join "`r`n") + "`r`n")

$resultsFile = Join-Path $Ev 'results.json'
Write-Utf8NoBom -Path $resultsFile -Text (ConvertTo-Json -InputObject $script:Checks -Depth 6)

$passed = @($script:Checks | Where-Object { $_.pass }).Count
$total = $script:Checks.Count
Write-Host ''
Write-Host ("phase {0}: {1}/{2} checks passed; evidence in {3}" -f $Phase, $passed, $total, $Ev)
Write-Host ("log sha256 = {0}" -f (Get-FileHash -Algorithm SHA256 -Path $logPath).Hash.ToLower())
if ($passed -ne $total) { exit 1 }
exit 0