# =============================================================================
#  mcp051_b_tier_evidence.ps1 -- TASK-051 gate 2 evidence (pure ASCII).
#
#  What it collects
#  ----------------
#  One row per real request, on the two test endpoints only (9888 editor /
#  9889 game; 9877 is never touched), plus one row per contract-relevant fact
#  read out of a real `tools/list`:
#
#    * C-3  editor_add_nodes_batch: the same-batch parent (default mode, new
#           mode), the forward reference, the duplicate name, the unknown
#           parent, and the tree the call left behind;
#    * O-9  editor_list_signal_connections: the default answer, scope=user,
#           scope=internal, scope=bogus, the preserved signal_name substring
#           filter, and the counts breakdown;
#    * O-4  editor_simulate_input_sequence: the live -32602 of a missing
#           events[0].type, next to the same call once the type is there;
#    * O-5  running_game_run_test_scenario: the pressed/strength call that has
#           always worked, and the declared members the schema report reads;
#    * M-3  editor_play_scene: headless launch (child endpoint reachable, the
#           child's own command line inspected for `--headless` and for exactly
#           one `--mcp-port`), the extra_args dedup, and the two refusals;
#    * the cross-tool chain the PLAYBOOK asks for in gate 2: open a scene, add
#           a parent and its child in ONE batch, read the tree back, and read
#           one node's properties back.
#
#  It asserts nothing on purpose: the same file produces the TASK-051 red run
#  (against the pre-change binary) and the green run (against the rebuilt one),
#  so the two summaries can be diffed row by row.
#
#  Discipline
#  ----------
#  * response bodies only ever land through `curl.exe -s -o` (never a
#    PowerShell pipeline, PLAYBOOK section 7.1), and both the request and the
#    response get a sha256;
#  * request bodies are written without a BOM (mcp_import_guard.ps1);
#  * the run is wrapped in the module's one port guard (mcp_port_guard.ps1),
#    which decides from the pids and command lines this script itself produced;
#  * only 9888 (editor) / 9889 (game) are used, one engine at a time, and the
#    game child M-3 starts is stopped through editor_stop_scene before the
#    editor goes away.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp051_b_tier_evidence.ps1 -Label red
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp051_b_tier_evidence.ps1 -Label green
# =============================================================================

param(
    [string]$Label = 'red',
    [int]$TimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$EvidenceRoot = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task051'
$Evid = Join-Path $EvidenceRoot $Label
$LogRoot = Join-Path $env:TEMP 'mcp051\logs'
$ScratchRoot = Join-Path $env:TEMP 'mcp051\scratch'
$EditorProject = Join-Path $ScratchRoot 'editor'
$GameProject = Join-Path $ScratchRoot 'game'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')

$script:StartedPids = New-Object System.Collections.Generic.List[int]
$script:Rows = New-Object System.Collections.Generic.List[object]
$script:Facts = New-Object System.Collections.Generic.List[object]
$script:RequestId = 5100

New-Item -ItemType Directory -Force -Path $Evid, $LogRoot, $ScratchRoot | Out-Null

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

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

function Get-FileSha {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '<absent>' }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}

function Get-TextSha {
    param([string]$Text)
    if ($null -eq $Text) { return '<null>' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Text)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLower()
}

# The same canonicalisation check_contract_subset.ps1 uses for `inputSchema`:
# object members sorted by name, recursively, so two spellings of one schema
# compare equal.
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
            Start-Sleep -Milliseconds 900
        }
    } catch { }
}

function Wait-ForPump {
    param([int]$Port, [int]$TimeoutMs = 240000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $previous = $null
    $consecutive = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        $body = & curl.exe -s -m 3 ("http://127.0.0.1:$Port/mcp") 2>$null
        if (-not [string]::IsNullOrWhiteSpace($body)) {
            $json = $null
            try { $json = ConvertFrom-Json $body } catch { $json = $null }
            if ($null -ne $json -and $null -ne $json.frame_count) {
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

function New-CallBody {
    param([string]$Tool, $Arguments)
    $script:RequestId++
    $body = [pscustomobject]@{
        id      = $script:RequestId
        jsonrpc = '2.0'
        method  = 'tools/call'
        params  = [pscustomobject]@{ arguments = $Arguments; name = $Tool }
    }
    return [pscustomobject]@{ Id = $script:RequestId; Json = (ConvertTo-Json $body -Compress -Depth 32) }
}

function Get-ResultText {
    param($Object)
    if ($null -eq $Object) { return '' }
    if ($null -eq $Object.result) { return '' }
    if ($null -eq $Object.result.content) { return '' }
    return [string]$Object.result.content[0].text
}

function Invoke-Probe {
    param(
        [string]$Id,
        [int]$Port,
        [string]$Tool,
        $Arguments,
        [string]$Note = ''
    )
    $call = New-CallBody -Tool $Tool -Arguments $Arguments
    $reqPath = Join-Path $Evid ($Id + '.request.json')
    $resPath = Join-Path $Evid ($Id + '.response.json')
    Write-McpUtf8NoBom -Path $reqPath -Text $call.Json
    $null = & curl.exe -s -o $resPath -H 'Content-Type: application/json' `
        --data-binary ('@' + $reqPath) ("http://127.0.0.1:$Port/mcp")

    $raw = ''
    if (Test-Path $resPath) { $raw = Get-Content -Raw -Encoding UTF8 $resPath }
    $obj = $null
    try { $obj = ConvertFrom-Json $raw } catch { $obj = $null }

    $code = '<no-envelope>'
    $message = ''
    $suggestion = '<none>'
    $dataKeys = ''
    $other = ''
    if ($null -ne $obj -and $null -ne $obj.error) {
        $code = [int]$obj.error.code
        $message = [string]$obj.error.message
        if ($null -ne $obj.error.data) {
            $suggestion = '<no-suggestion>'
            if ($null -ne $obj.error.data.suggestion) { $suggestion = [string]$obj.error.data.suggestion }
            $dataKeys = (@($obj.error.data.PSObject.Properties | ForEach-Object { $_.Name }) -join ',')
            if ($null -ne $obj.error.data.batch) { $other = 'batch_status=' + [string]$obj.error.data.batch.status }
        }
    } elseif ($null -ne $obj -and $null -ne $obj.result) {
        $code = 0
        $message = Get-ResultText $obj
        $suggestion = '<n/a-success>'
        # The success half of C-3/O-9/M-3 rides in the payload; the interesting
        # members are lifted into `extra` so a red/green diff can read them
        # without parsing the whole body again.
        try {
            $payload = ConvertFrom-Json $message
            $bits = @()
            if ($null -ne $payload.count) { $bits += ('count=' + [string]$payload.count) }
            if ($null -ne $payload.connections) { $bits += ('connections=' + [string]@($payload.connections).Count) }
            if ($null -ne $payload.counts) { $bits += ('counts=' + (Get-CanonicalJson $payload.counts)) }
            if ($null -ne $payload.scope) { $bits += ('scope=' + [string]$payload.scope) }
            if ($null -ne $payload.resolve_within_batch) { $bits += ('resolve_within_batch=' + [string]$payload.resolve_within_batch) }
            if ($null -ne $payload.created) { $bits += ('created=' + (Get-CanonicalJson $payload.created)) }
            if ($null -ne $payload.mcp_port) { $bits += ('mcp_port=' + [string]$payload.mcp_port) }
            if ($null -ne $payload.pid) { $bits += ('pid=' + [string]$payload.pid) }
            if ($null -ne $payload.headless) { $bits += ('headless=' + [string]$payload.headless) }
            if ($null -ne $payload.args_injected) { $bits += ('args_injected=' + (Get-CanonicalJson $payload.args_injected)) }
            if ($null -ne $payload.args_deduplicated) { $bits += ('args_deduplicated=' + (Get-CanonicalJson $payload.args_deduplicated)) }
            if ($null -ne $payload.playing) { $bits += ('playing=' + [string]$payload.playing) }
            if ($null -ne $payload.endpoint) { $bits += ('endpoint=' + [string]$payload.endpoint) }
            $other = ($bits -join ' | ')
        } catch { $other = '<payload-not-json>' }
    }

    $bytes = -1
    if (Test-Path $resPath) { $bytes = (Get-Item $resPath).Length }
    $row = [pscustomobject]@{
        id               = $Id
        port             = $Port
        tool             = $Tool
        note             = $Note
        code             = $code
        message          = $message
        suggestion       = $suggestion
        data_keys        = $dataKeys
        extra            = $other
        request_sha256   = (Get-FileSha $reqPath)
        response_sha256  = (Get-FileSha $resPath)
        response_bytes   = $bytes
    }
    $script:Rows.Add($row) | Out-Null
    Write-Host ("[{0}] port={1} tool={2} code={3}" -f $Id, $Port, $Tool, $code)
    Write-Host ("    extra      = {0}" -f $other)
    Write-Host ("    message    = {0}" -f $message)
    if (-not [string]::IsNullOrEmpty($Note)) { Write-Host ("    note       = {0}" -f $Note) }
    return $row
}

function Get-Suggestion {
    param($Row)
    if ($null -eq $Row) { return '' }
    if ([string]$Row.suggestion -eq '<none>' -or [string]$Row.suggestion -eq '<no-suggestion>' -or [string]$Row.suggestion -eq '<n/a-success>') { return '' }
    return [string]$Row.suggestion
}

# A real `tools/list`, captured to a file and reduced to the facts TASK-051 is
# about: which members each of the five tools declares, and the canonical
# schema digest. This is the wire half of the contract change (the gate 1
# assertion is the other half).
function Get-SchemaReport {
    param([int]$Port, [string]$Label2, [string[]]$Names)
    $reqPath = Join-Path $Evid ($Label2 + '-tools_list.request.json')
    $resPath = Join-Path $Evid ($Label2 + '-tools_list.response.json')
    Write-McpUtf8NoBom -Path $reqPath -Text '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
    $null = & curl.exe -s -o $resPath -H 'Content-Type: application/json' `
        --data-binary ('@' + $reqPath) ("http://127.0.0.1:$Port/mcp")
    $raw = Get-Content -Raw -Encoding UTF8 $resPath
    $obj = ConvertFrom-Json $raw
    $tools = @($obj.result.tools)
    foreach ($name in $Names) {
        $entry = @($tools | Where-Object { [string]$_.name -ceq $name })
        $has = $false
        $schemaSha = '<absent>'
        $props = ''
        $itemsProps = ''
        $stepProps = ''
        if ($entry.Count -eq 1) {
            $has = $true
            $schema = $entry[0].inputSchema
            $schemaSha = Get-TextSha (Get-CanonicalJson $schema)
            $props = (@($schema.properties.PSObject.Properties | ForEach-Object { $_.Name }) -join ',')
            if ($null -ne $schema.properties.events -and $null -ne $schema.properties.events.items) {
                $itemsProps = (@($schema.properties.events.items.properties.PSObject.Properties | ForEach-Object { $_.Name }) -join ',')
            }
            if ($null -ne $schema.properties.steps -and $null -ne $schema.properties.steps.items) {
                $stepProps = (@($schema.properties.steps.items.properties.PSObject.Properties | ForEach-Object { $_.Name }) -join ',')
            }
        }
        $fact = [pscustomobject]@{
            endpoint        = $Label2
            tool            = $name
            listed          = $has
            top_properties  = $props
            events_items    = $itemsProps
            steps_properties = $stepProps
            schema_canonical_sha256 = $schemaSha
            tools_list_bytes = (Get-Item $resPath).Length
        }
        $script:Facts.Add($fact) | Out-Null
        Write-Host ("[schema:{0}] {1} listed={2} props={3}" -f $Label2, $name, $has, $props)
        if (-not [string]::IsNullOrEmpty($itemsProps)) {
            Write-Host ("    events.items = {0}" -f $itemsProps)
        }
        if (-not [string]::IsNullOrEmpty($stepProps)) {
            Write-Host ("    steps.items  = {0}" -f $stepProps)
        }
    }
}

# The launched child's own command line: the only place the real `--headless`
# and the real number of `--mcp-port` occurrences can be counted (the tool's
# own answer is what we are checking, so it cannot be the evidence).
#
# The parameter is NOT named `$Pid`: that is a read-only automatic variable in
# PowerShell, and naming it that made the first green run abort here (measured:
# "Cannot overwrite variable Pid because it is read-only or constant", after
# which the game phase never ran).
function Get-ChildCommandLine {
    param([int]$ProcessId)
    $proc = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $ProcessId) -ErrorAction SilentlyContinue
    if ($null -eq $proc) { return '<no-such-process>' }
    return [string]$proc.CommandLine
}

function Get-OccurrenceCount {
    param([string]$Text, [string]$Token)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    return ([regex]::Matches($Text, [regex]::Escape($Token))).Count
}

function Add-ChildFact {
    param([string]$Id, [int]$ProcessId, [string]$Note)
    $cmdline = Get-ChildCommandLine -ProcessId $ProcessId
    $fact = [pscustomobject]@{
        id                       = $Id
        child_pid                = $ProcessId
        note                     = $Note
        command_line             = $cmdline
        mcp_port_occurrences     = Get-OccurrenceCount -Text $cmdline -Token '--mcp-port'
        headless_occurrences     = Get-OccurrenceCount -Text $cmdline -Token '--headless'
    }
    $script:Facts.Add($fact) | Out-Null
    Write-Host ("[child:{0}] pid={1} mcp_port_occurrences={2} headless_occurrences={3}" -f `
        $Id, $ProcessId, $fact.mcp_port_occurrences, $fact.headless_occurrences)
    Write-Host ("    cmdline = {0}" -f $cmdline)
    return $fact
}

# -----------------------------------------------------------------------------
# Scratch projects
# -----------------------------------------------------------------------------

function Initialize-ScratchProjects {
    # The editor project: a 5-node scene (the audit's O-9 shape: "a 5-node scene
    # answers 60 of 60 internal connections") and a main scene, so `mode: main`
    # really plays something. `New-McpScratchProject` writes no BOM.
    New-McpScratchProject -Path $EditorProject -Name 'MCP051 b tier editor' -WithMainScene $true
    $scene = @(
        '[gd_scene format=3]',
        '',
        '[node name="Main" type="Node2D"]',
        '',
        '[node name="Car" type="CharacterBody2D" parent="."]',
        '',
        '[node name="Button" type="Button" parent="."]',
        '',
        '[node name="Label" type="Label" parent="."]',
        '',
        '[node name="Timer" type="Timer" parent="."]',
        ''
    ) -join "`n"
    Write-McpUtf8NoBom -Path (Join-Path $EditorProject 'scenes/main.tscn') -Text $scene
    New-McpScratchProject -Path $GameProject -Name 'MCP051 b tier game' -WithMainScene $true
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

Write-Host '============================================================='
Write-Host (" TASK-051 evidence -- label '{0}'" -f $Label)
Write-Host '============================================================='

if (-not (Test-Path $Engine)) { Write-Host ("FATAL: engine binary not found: {0}" -f $Engine); exit 2 }

Get-ChildItem -Path $Evid -Filter '*.json' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$version = (& $Engine --version)
$head = (& git -C $RepoRoot rev-parse HEAD)
$headShort = (& git -C $RepoRoot rev-parse --short=9 HEAD)
Write-Host ("binary --version : {0}" -f $version)
Write-Host ("git HEAD         : {0}" -f $headShort)

$userPidBefore = Get-ListenerPid -Port $UserPort
$guard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("user editor on {0} before run: pid={1}" -f $UserPort, $userPidBefore)

Initialize-ScratchProjects
$importEditor = Import-McpProject -Engine $Engine -Path $EditorProject -LogDirectory $LogRoot -Name 'mcp051-import-editor'
Register-McpPortGuardCommandLine -Guard $guard -CommandLine $importEditor.command
$importGame = Import-McpProject -Engine $Engine -Path $GameProject -LogDirectory $LogRoot -Name 'mcp051-import-game'
Register-McpPortGuardCommandLine -Guard $guard -CommandLine $importGame.command
Write-Host ("import editor: exit 0 on attempt {0}; import game: exit 0 on attempt {1}" -f $importEditor.attempts, $importGame.attempts)

$editorHandle = $null
$gameHandle = $null

try {
    # -------------------------------------------------------------------------
    # Editor endpoint 9888
    # -------------------------------------------------------------------------
    $editorArgs = @('--headless', '-e', '--path', $EditorProject, ("--mcp-port=" + $EditorPort))
    Register-McpPortGuardProcess -Guard $guard -Arguments $editorArgs
    $editorHandle = Start-Engine -Arguments $editorArgs -LogName 'mcp051-editor'
    if (-not (Wait-ForPump -Port $EditorPort -TimeoutMs $TimeoutMs)) {
        Write-Host 'FATAL: the editor endpoint never became ready'
        Write-Host (Get-Content -Raw $editorHandle.Out -ErrorAction SilentlyContinue)
        exit 3
    }

    Get-SchemaReport -Port $EditorPort -Label2 'editor' -Names @(
        'editor_add_nodes_batch',
        'editor_list_signal_connections',
        'editor_simulate_input_sequence',
        'editor_play_scene'
    )

    # The precondition of every editor node probe, and the first link of the
    # cross-tool chain.
    Invoke-Probe -Id 'e01_open_scene' -Port $EditorPort -Tool 'editor_open_scene' `
        -Arguments @{ path = 'res://scenes/main.tscn' } -Note 'chain link 1: the edited scene the node tools act on'

    # --- O-9 (first, on the pristine 5-node scene) ---------------------------
    # These probes come before the C-3 ones on purpose: adding P1/C1 makes the
    # editor attach its own wiring to them, so the same request would answer 83
    # connections instead of 59 and the red/green rows would not be comparable.
    Invoke-Probe -Id 'e02_o9_default_scope' -Port $EditorPort -Tool 'editor_list_signal_connections' `
        -Arguments @{} -Note 'O-9 baseline: the default answer (scope=all) is the pre-TASK-051 answer'
    Invoke-Probe -Id 'e03_o9_scope_user' -Port $EditorPort -Tool 'editor_list_signal_connections' `
        -Arguments @{ scope = 'user' } -Note 'O-9: only the scene-side connections'
    Invoke-Probe -Id 'e04_o9_scope_internal' -Port $EditorPort -Tool 'editor_list_signal_connections' `
        -Arguments @{ scope = 'internal' } -Note 'O-9: only the editor/engine Class::method bindings'
    Invoke-Probe -Id 'e05_o9_scope_bogus' -Port $EditorPort -Tool 'editor_list_signal_connections' `
        -Arguments @{ scope = 'scene' } -Note 'O-9 refusal: the vocabulary is closed and names its values'
    Invoke-Probe -Id 'e06_o9_signal_name_filter' -Port $EditorPort -Tool 'editor_list_signal_connections' `
        -Arguments @{ signal_name = 'script_changed' } -Note 'O-9: the signal_name substring filter is deliberately unchanged (it does not remove the internal connections)'
    Invoke-Probe -Id 'e07_o9_scope_and_filter' -Port $EditorPort -Tool 'editor_list_signal_connections' `
        -Arguments @{ scope = 'user'; signal_name = 'script_changed' } -Note 'O-9: scope composes with the existing filters (script_changed is an editor-internal signal here)'

    # --- C-3 ----------------------------------------------------------------
    $batch_parents = @(
        @{ type = 'Node2D'; name = 'P1' },
        @{ type = 'Node2D'; name = 'C1'; parent_path = 'P1' }
    )
    Invoke-Probe -Id 'e08_c3_default_mode_refuses' -Port $EditorPort -Tool 'editor_add_nodes_batch' `
        -Arguments @{ nodes = $batch_parents } -Note 'C-3: default mode (no resolve_within_batch) keeps the pre-TASK-051 answer'
    Invoke-Probe -Id 'e09_c3_same_batch_parent' -Port $EditorPort -Tool 'editor_add_nodes_batch' `
        -Arguments @{ nodes = $batch_parents; resolve_within_batch = $true } -Note 'C-3 success: parent and child in ONE request'
    Invoke-Probe -Id 'e10_c3_chain_get_scene_tree' -Port $EditorPort -Tool 'editor_get_scene_tree' `
        -Arguments @{ max_depth = 3 } -Note 'chain link 2: the tree really contains P1 and P1/C1'
    Invoke-Probe -Id 'e11_c3_chain_get_properties' -Port $EditorPort -Tool 'editor_get_node_properties' `
        -Arguments @{ path = 'P1/C1'; properties = @('name') } -Note 'chain link 3: the child is reachable by the path the batch answered'
    Invoke-Probe -Id 'e12_c3_forward_reference' -Port $EditorPort -Tool 'editor_add_nodes_batch' `
        -Arguments @{ nodes = @(@{ type = 'Node2D'; name = 'C9'; parent_path = 'P9' }, @{ type = 'Node2D'; name = 'P9' }); resolve_within_batch = $true } `
        -Note 'C-3 refusal: the parent is created later in the same batch (a cycle has this shape)'
    Invoke-Probe -Id 'e13_c3_duplicate_name' -Port $EditorPort -Tool 'editor_add_nodes_batch' `
        -Arguments @{ nodes = @(@{ type = 'Node2D'; name = 'D1' }, @{ type = 'Node2D'; name = 'D1' }); resolve_within_batch = $true } `
        -Note 'C-3 refusal: two nodes of one batch would share a path'
    Invoke-Probe -Id 'e14_c3_unknown_parent' -Port $EditorPort -Tool 'editor_add_nodes_batch' `
        -Arguments @{ nodes = @(@{ type = 'Node2D'; name = 'C8'; parent_path = 'NoSuchParentXYZ' }); resolve_within_batch = $true } `
        -Note 'C-3 refusal: a parent nobody provides is still the plain -32001 not found'

    # --- O-4 ----------------------------------------------------------------
    Invoke-Probe -Id 'e15_o4_events_missing_type' -Port $EditorPort -Tool 'editor_simulate_input_sequence' `
        -Arguments @{ events = @(@{ keycode = 'W'; pressed = $true }) } -Note 'O-4: the -32602 that only the items schema can prevent'
    Invoke-Probe -Id 'e16_o4_events_with_type' -Port $EditorPort -Tool 'editor_simulate_input_sequence' `
        -Arguments @{ events = @(@{ type = 'key'; keycode = 'W'; pressed = $true }); frame_delay = 0 } `
        -Note 'O-4: the same call with the type the items enum declares'

    # --- M-3 ----------------------------------------------------------------
    # `headless` with the wrong type: refused in both phases (-32602), so the
    # row shows the argument going from "unknown to this tool" to "known and
    # type-checked" - and, unlike a launch probe, it cannot leave a child behind.
    Invoke-Probe -Id 'e17_m3_headless_type_error' -Port $EditorPort -Tool 'editor_play_scene' `
        -Arguments @{ mode = 'main'; headless = 'yes' } -Note 'M-3: the argument the pre-change contract did not have, refused in both phases'
    Invoke-Probe -Id 'e18_m3_port_in_extra_args' -Port $EditorPort -Tool 'editor_play_scene' `
        -Arguments @{ mode = 'main'; mcp_port = $GamePort; headless = $true; extra_args = @('--mcp-port=9889') } `
        -Note 'M-3 refusal: the port has exactly one source'
    Invoke-Probe -Id 'e19_m3_extra_args_type' -Port $EditorPort -Tool 'editor_play_scene' `
        -Arguments @{ mode = 'main'; extra_args = 7 } -Note 'M-3 refusal: extra_args must be an array of strings'

    # The launch itself. `headless` keeps the child off this desktop, and the
    # child's own command line is inspected right after the answer.
    $launch = Invoke-Probe -Id 'e20_m3_headless_launch' -Port $EditorPort -Tool 'editor_play_scene' `
        -Arguments @{ mode = 'main'; mcp_port = $GamePort; headless = $true; extra_args = @('--verbose') } `
        -Note 'M-3 success: headless child on 9889'
    if ([int]$launch.code -eq 0) {
        $payload = ConvertFrom-Json $launch.message
        if ($null -ne $payload.pid) {
            Add-ChildFact -Id 'e20_child_cmdline' -ProcessId ([int]$payload.pid) -Note 'M-3: headless once, --mcp-port once'
        }
        # "the game endpoint is reachable": the child's own /mcp answers.
        $statusPath = Join-Path $Evid 'e20_child_status.json'
        $null = & curl.exe -s -o $statusPath -m 20 ("http://127.0.0.1:$GamePort/mcp")
        $statusText = ''
        if (Test-Path $statusPath) { $statusText = Get-Content -Raw -Encoding UTF8 $statusPath }
        $statusObj = $null
        try { $statusObj = ConvertFrom-Json $statusText } catch { $statusObj = $null }
        $statusFact = [pscustomobject]@{
            id                  = 'e20_child_endpoint'
            port                = $GamePort
            note                = 'M-3: the game child really listens on the port the answer named'
            is_editor           = $statusObj.is_editor
            listening           = $statusObj.listening
            tools               = $statusObj.tools
            response_bytes      = (Get-Item $statusPath).Length
            response_sha256     = (Get-FileSha $statusPath)
        }
        $script:Facts.Add($statusFact) | Out-Null
        Write-Host ("[child-endpoint] is_editor={0} listening={1} tools={2}" -f `
            $statusFact.is_editor, $statusFact.listening, $statusFact.tools)
    }
    Invoke-Probe -Id 'e21_m3_stop_scene' -Port $EditorPort -Tool 'editor_stop_scene' `
        -Arguments @{} -Note 'M-3: the child is stopped before the next launch'

    # The dedup probe: `--headless` is requested twice, once by the flag and once
    # in extra_args, and the answer must say which entry was dropped.
    $launch2 = Invoke-Probe -Id 'e22_m3_headless_dedup' -Port $EditorPort -Tool 'editor_play_scene' `
        -Arguments @{ mode = 'main'; mcp_port = $GamePort; headless = $true; extra_args = @('--headless') } `
        -Note 'M-3 dedup: the duplicate --headless is dropped and reported'
    if ([int]$launch2.code -eq 0) {
        $payload2 = ConvertFrom-Json $launch2.message
        if ($null -ne $payload2.pid) {
            Add-ChildFact -Id 'e22_child_cmdline' -ProcessId ([int]$payload2.pid) -Note 'M-3: still exactly one --headless'
        }
    }
    Invoke-Probe -Id 'e23_m3_stop_scene' -Port $EditorPort -Tool 'editor_stop_scene' `
        -Arguments @{} -Note 'M-3: the second child is stopped too'

    Stop-Engine -Handle $editorHandle
    $editorHandle = $null

    # -------------------------------------------------------------------------
    # Game endpoint 9889
    # -------------------------------------------------------------------------
    $gameArgs = @('--headless', '--path', $GameProject, ("--mcp-port=" + $GamePort))
    Register-McpPortGuardProcess -Guard $guard -Arguments $gameArgs
    $gameHandle = Start-Engine -Arguments $gameArgs -LogName 'mcp051-game'
    if (-not (Wait-ForPump -Port $GamePort -TimeoutMs $TimeoutMs)) {
        Write-Host 'FATAL: the game endpoint never became ready'
        Write-Host (Get-Content -Raw $gameHandle.Out -ErrorAction SilentlyContinue)
        exit 3
    }

    Get-SchemaReport -Port $GamePort -Label2 'game' -Names @(
        'running_game_run_test_scenario'
    )

    Invoke-Probe -Id 'g01_o5_input_with_pressed' -Port $GamePort -Tool 'running_game_run_test_scenario' `
        -Arguments @{ steps = @(@{ type = 'input'; keycode = 'W'; pressed = $true; strength = 0.5 }) } `
        -Note 'O-5: pressed/strength have always been read; TASK-051 declares them'
    Invoke-Probe -Id 'g02_o5_input_release' -Port $GamePort -Tool 'running_game_run_test_scenario' `
        -Arguments @{ steps = @(@{ type = 'input'; keycode = 'W'; pressed = $false }) } `
        -Note 'O-5: the release step, the documented way to undo g01'

    Stop-Engine -Handle $gameHandle
    $gameHandle = $null
} catch {
    Write-Host ("EXCEPTION: {0}" -f $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    Stop-Engine -Handle $gameHandle
    Stop-Engine -Handle $editorHandle
}

$userPidAfter = Get-ListenerPid -Port $UserPort
$verdict = Complete-McpPortGuard -Guard $guard -PidAfter $userPidAfter

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

$summary = @{}
$summary['label'] = [string]$Label
$summary['engine_version'] = [string]$version
$summary['git_head'] = [string]$head
$summary['git_head_short'] = [string]$headShort
$summary['port_9877_pass'] = [bool]$verdict.pass
$summary['port_9877_classification'] = [string]$verdict.classification
$summary['port_9877_evidence'] = [string]$verdict.evidence
$summary['probes'] = $script:Rows.ToArray()
$summary['facts'] = $script:Facts.ToArray()
$summaryPath = Join-Path $Evid 'summary.json'
$summaryJson = ConvertTo-Json $summary -Depth 12
Write-McpUtf8NoBom -Path $summaryPath -Text $summaryJson

Write-Host ''
Write-Host '========================== SUMMARY =========================='
foreach ($row in $script:Rows) {
    Write-Host ("{0,-34} code={1,-12} {2}" -f $row.id, $row.code, $row.extra)
}
Write-Host ("probes          : {0}" -f $script:Rows.Count)
Write-Host ("facts           : {0}" -f $script:Facts.Count)
Write-Host ("port 9877 guard : pass={0} classification={1}" -f $verdict.pass, $verdict.classification)
Write-Host ("summary         : {0}" -f $summaryPath)
Write-Host ("summary sha256  : {0}" -f (Get-FileSha $summaryPath))

if (-not $verdict.pass) { exit 1 }
exit 0
