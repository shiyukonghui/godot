# =============================================================================
#  mcp050_parameter_guidance_evidence.ps1 -- TASK-050 gate 2 evidence (pure ASCII).
#
#  What it collects
#  ----------------
#  One row per real request, on the two test endpoints only:
#
#    * O-1: a *missing required* parameter, on the immediate entry (editor tool
#      on 9888) and on the deferred entry (editor_simulate_input_sequence, which
#      is a pending_handler tool), plus the same parameter "present but empty";
#    * N-7: a mistyped parameter, a nested path (`events[0].type`), an enum
#      parameter, an over-long array, a handler's own semantic refusal, and the
#      already-suggested unknown-argument refusal (the TASK-032 behaviour, which
#      must not move);
#    * N-2: `project_validate_script` on a legitimate `.cs` file in this
#      (module_mono_enabled=no) build, next to the `.gd` positive/negative
#      controls and the underlying `-32001` of the same tool;
#    * the cross-tool chain the PLAYBOOK asks for in gate 2: create a script with
#      project_create_script, validate it, read it back, and read back the file
#      the *honest refusal* left untouched.
#
#  It asserts nothing on purpose: the same file produces the TASK-050 red run
#  (against the pre-change binary) and the green run (against the rebuilt one),
#  so the two summaries can be diffed row by row.
#
#  Discipline
#  ----------
#  * response bodies only ever land through `curl.exe -s -o` (never a
#    PowerShell pipeline, PLAYBOOK section 7.1), and both the request and the
#    response get a sha256;
#  * request bodies are written without a BOM (mcp_import_guard.ps1);
#  * 9877 is never bound, never touched: the run is wrapped in the module's one
#    port guard (mcp_port_guard.ps1), which decides from the pids and command
#    lines this script itself produced;
#  * only 9888 (editor) / 9889 (game) are used, one engine at a time.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp050_parameter_guidance_evidence.ps1 -Label red
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp050_parameter_guidance_evidence.ps1 -Label green
# =============================================================================

param(
    [string]$Label = 'red',
    [int]$TimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$EvidenceRoot = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task050'
$Evid = Join-Path $EvidenceRoot $Label
$LogRoot = Join-Path $env:TEMP 'mcp050\logs'
$ScratchRoot = Join-Path $env:TEMP 'mcp050\scratch'
$EditorProject = Join-Path $ScratchRoot 'editor'
$GameProject = Join-Path $ScratchRoot 'game'
$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')

$script:StartedPids = New-Object System.Collections.Generic.List[int]
$script:Rows = New-Object System.Collections.Generic.List[object]
$script:RequestId = 5000

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

# The endpoint is ready when `GET /mcp` answers with a frame counter that keeps
# moving (the same rule check_contract_subset.ps1 uses for its own socket client).
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
        $message = [string]$obj.result.content[0].text
        $suggestion = '<n/a-success>'
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
    Write-Host ("    message    = {0}" -f $message)
    Write-Host ("    suggestion = {0}" -f $suggestion)
    if (-not [string]::IsNullOrEmpty($Note)) { Write-Host ("    note       = {0}" -f $Note) }
    return $row
}

function Get-Suggestion {
    param($Row)
    if ($null -eq $Row) { return '' }
    if ([string]$Row.suggestion -eq '<none>' -or [string]$Row.suggestion -eq '<no-suggestion>' -or [string]$Row.suggestion -eq '<n/a-success>') { return '' }
    return [string]$Row.suggestion
}

# -----------------------------------------------------------------------------
# Scratch projects
# -----------------------------------------------------------------------------

function Initialize-ScratchProjects {
    # The shared writer (mcp_import_guard.ps1), then the two script files the
    # probes need: the `.gd` controls and the `.cs` of the N-2 question. The `.cs`
    # probe file is *not* written here - the chain writes it through
    # project_create_script, so the file the tool validates is a tool-written one.
    New-McpScratchProject -Path $EditorProject -Name 'MCP050 parameter guidance' -WithMainScene $false
    New-McpScratchProject -Path $GameProject -Name 'MCP050 parameter guidance game' -WithMainScene $true
    New-Item -ItemType Directory -Force -Path (Join-Path $EditorProject 'scripts') | Out-Null
    Write-McpUtf8NoBom -Path (Join-Path $EditorProject 'scripts/legit.gd') -Text ("extends Node" + "`n")
    Write-McpUtf8NoBom -Path (Join-Path $EditorProject 'scripts/broken.gd') -Text "func broken(`n"
    # A scene the editor can open: the batch tool's own -32602 (which already
    # carries `data.suggestion` + `data.batch`) is only reachable with a scene
    # open, and that refusal is the one TASK-050 must not clobber.
    New-Item -ItemType Directory -Force -Path (Join-Path $EditorProject 'scenes') | Out-Null
    Write-McpUtf8NoBom -Path (Join-Path $EditorProject 'scenes/probe.tscn') `
        -Text ("[gd_scene format=3]`n`n[node name=`"Probe`" type=`"Node2D`"]`n")
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

Write-Host '============================================================='
Write-Host (" TASK-050 evidence -- label '{0}'" -f $Label)
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
$importEditor = Import-McpProject -Engine $Engine -Path $EditorProject -LogDirectory $LogRoot -Name 'mcp050-import-editor'
Register-McpPortGuardCommandLine -Guard $guard -CommandLine $importEditor.command
$importGame = Import-McpProject -Engine $Engine -Path $GameProject -LogDirectory $LogRoot -Name 'mcp050-import-game'
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
    $editorHandle = Start-Engine -Arguments $editorArgs -LogName 'mcp050-editor'
    if (-not (Wait-ForPump -Port $EditorPort -TimeoutMs $TimeoutMs)) {
        Write-Host 'FATAL: the editor endpoint never became ready'
        Write-Host (Get-Content -Raw $editorHandle.Out -ErrorAction SilentlyContinue)
        exit 3
    }

    # The cross-tool chain, part 1: write the two files with the write half of
    # the same family. `.cs` is accepted by project_create_script (only `.csproj`
    # is refused), which is what makes the N-2 file reachable from the tool face.
    $csSource = "using Godot;`n`npublic partial class Legit : Node`n{`n    public override void _Ready()`n    {`n    }`n}`n"
    Invoke-Probe -Id 'e01_chain_create_cs' -Port $EditorPort -Tool 'project_create_script' `
        -Arguments @{ path = 'res://scripts/legit.cs'; content = $csSource } -Note 'cross-tool chain: the .cs file the N-2 probe validates'
    Invoke-Probe -Id 'e02_chain_read_cs' -Port $EditorPort -Tool 'project_read_script' `
        -Arguments @{ path = 'res://scripts/legit.cs' } -Note 'chain: the file is on disk and readable (bytes match the request)'

    # N-2: the honest answer for a language this build does not contain.
    Invoke-Probe -Id 'e03_n2_validate_cs' -Port $EditorPort -Tool 'project_validate_script' `
        -Arguments @{ path = 'res://scripts/legit.cs' } -Note 'N-2: a legitimate .cs in a module_mono_enabled=no build'

    # N-2 controls: the same tool on the language it does contain.
    Invoke-Probe -Id 'e04_validate_gd_valid' -Port $EditorPort -Tool 'project_validate_script' `
        -Arguments @{ path = 'res://scripts/legit.gd' } -Note 'success path of the same tool (valid gd)'
    Invoke-Probe -Id 'e05_validate_gd_broken' -Port $EditorPort -Tool 'project_validate_script' `
        -Arguments @{ path = 'res://scripts/broken.gd' } -Note 'refused compilation is still a successful call with valid=false'

    # O-1 / gate 2 "missing" and "underlying failure" on one tool.
    Invoke-Probe -Id 'e06_validate_missing_param' -Port $EditorPort -Tool 'project_validate_script' `
        -Arguments @{} -Note 'O-1: contract-required path omitted'
    Invoke-Probe -Id 'e07_validate_missing_file' -Port $EditorPort -Tool 'project_validate_script' `
        -Arguments @{ path = 'res://scripts/does_not_exist.gd' } -Note 'underlying failure (-32001 + suggestion), unchanged'

    # O-1: the same shape on the immediate entry of a multi-parameter tool.
    Invoke-Probe -Id 'e08_missing_required_immediate' -Port $EditorPort -Tool 'editor_set_node_property' `
        -Arguments @{ property = 'visible'; value = $true } -Note 'O-1 immediate entry: path omitted'
    Invoke-Probe -Id 'e09_missing_required_two' -Port $EditorPort -Tool 'editor_rename_node' `
        -Arguments @{} -Note 'O-1 immediate entry: two required parameters omitted'

    # O-1: the deferred entry (pending_handler validates before a task exists).
    Invoke-Probe -Id 'e10_missing_required_deferred' -Port $EditorPort -Tool 'editor_simulate_input_sequence' `
        -Arguments @{} -Note 'O-1 deferred entry: events omitted'
    Invoke-Probe -Id 'e11_empty_required_deferred' -Port $EditorPort -Tool 'editor_simulate_input_sequence' `
        -Arguments @{ events = @() } -Note 'O-1 deferred entry: events present but empty'

    # N-7: nested path, unknown value, type error, unknown name (must not move).
    Invoke-Probe -Id 'e12_nested_missing_type' -Port $EditorPort -Tool 'editor_simulate_input_sequence' `
        -Arguments @{ events = @(@{ keycode = 'W'; pressed = $true }) } -Note 'N-7: missing events[0].type (the array has no item shape in the contract)'
    Invoke-Probe -Id 'e13_nested_type_error' -Port $EditorPort -Tool 'editor_simulate_input_sequence' `
        -Arguments @{ events = @(@{ type = 'key'; keycode = 17 }) } -Note 'N-7: nested type error names events[0].keycode'
    Invoke-Probe -Id 'e14_type_error_top' -Port $EditorPort -Tool 'project_get_settings' `
        -Arguments @{ prefix = $true } -Note 'N-7: mistyped optional parameter'
    Invoke-Probe -Id 'e15_unknown_parameter' -Port $EditorPort -Tool 'project_get_settings' `
        -Arguments @{ prefix = 'application'; filter = 'application' } -Note 'TASK-032 behaviour, must stay byte-identical: unknown parameter'
    Invoke-Probe -Id 'e16_empty_required_value' -Port $EditorPort -Tool 'editor_execute_gdscript' `
        -Arguments @{ code = '' } -Note 'N-7: a contract-required parameter present but empty, refused by the handler'
    Invoke-Probe -Id 'e17_open_scene' -Port $EditorPort -Tool 'editor_open_scene' `
        -Arguments @{ path = 'res://scenes/probe.tscn' } -Note 'precondition of e17b: the batch refusal needs an open scene'
    Invoke-Probe -Id 'e17b_batch_own_suggestion' -Port $EditorPort -Tool 'editor_add_nodes_batch' `
        -Arguments @{ nodes = @(@{ type = 'NoSuchMcpNodeClass' }) } -Note 'N-7: an existing -32602 that already carries data.suggestion + data.batch, must not be clobbered'
    Invoke-Probe -Id 'e18_enum_value' -Port $EditorPort -Tool 'editor_set_node_selection' `
        -Arguments @{ node_path = '.'; mode = 'toggle' } -Note 'N-7: an enum refused by the handler names its accepted values'
    Invoke-Probe -Id 'e19_unknown_tool' -Port $EditorPort -Tool 'project_no_such_tool' `
        -Arguments @{} -Note 'N-7: -32602 for a name that is not a tool (in-process branch; the transport answers -32601 for it)'

    # Cross-tool chain, last link: what the honest refusal left behind.
    Invoke-Probe -Id 'e20_chain_read_cs_after' -Port $EditorPort -Tool 'project_read_script' `
        -Arguments @{ path = 'res://scripts/legit.cs' } -Note 'chain: the .cs file still has exactly the bytes that were written'

    Stop-Engine -Handle $editorHandle
    $editorHandle = $null

    # -------------------------------------------------------------------------
    # Game endpoint 9889
    # -------------------------------------------------------------------------
    $gameArgs = @('--headless', '--path', $GameProject, ("--mcp-port=" + $GamePort))
    Register-McpPortGuardProcess -Guard $guard -Arguments $gameArgs
    $gameHandle = Start-Engine -Arguments $gameArgs -LogName 'mcp050-game'
    if (-not (Wait-ForPump -Port $GamePort -TimeoutMs $TimeoutMs)) {
        Write-Host 'FATAL: the game endpoint never became ready'
        Write-Host (Get-Content -Raw $gameHandle.Out -ErrorAction SilentlyContinue)
        exit 3
    }

    Invoke-Probe -Id 'g01_missing_required_immediate' -Port $GamePort -Tool 'running_game_get_autoload_node' `
        -Arguments @{} -Note 'O-1 game-side immediate entry: name omitted'
    Invoke-Probe -Id 'g02_missing_required_deferred' -Port $GamePort -Tool 'running_game_run_test_scenario' `
        -Arguments @{} -Note 'O-1 game-side deferred entry: steps omitted'
    Invoke-Probe -Id 'g03_empty_required_deferred' -Port $GamePort -Tool 'running_game_run_test_scenario' `
        -Arguments @{ steps = @() } -Note 'O-1 game-side deferred entry: steps present but empty'
    Invoke-Probe -Id 'g04_nested_enum_error' -Port $GamePort -Tool 'running_game_run_test_scenario' `
        -Arguments @{ steps = @(@{ type = 'bogus' }) } -Note 'N-7: steps[0].type is resolvable in the contract and must list its enum'
    Invoke-Probe -Id 'g05_nested_missing_type' -Port $GamePort -Tool 'running_game_run_test_scenario' `
        -Arguments @{ steps = @(@{ seconds = 0.1 }) } -Note 'N-7: steps[0] without type'
    Invoke-Probe -Id 'g06_nested_type_mismatch' -Port $GamePort -Tool 'running_game_run_test_scenario' `
        -Arguments @{ steps = @(@{ type = 17 }) } -Note 'N-7: the step parser spells this path mid-sentence (steps[0].type)'
    Invoke-Probe -Id 'g07_bare_array_nested' -Port $GamePort -Tool 'running_game_play_input_recording' `
        -Arguments @{ events = @(@{ type = 'walker' }) } -Note 'N-7: events has no item shape in the contract, so the reason must be stated'
    Invoke-Probe -Id 'g08_game_type_error' -Port $GamePort -Tool 'running_game_get_node_properties' `
        -Arguments @{ node_path = 17 } -Note 'N-7: game-side type error'

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

# Built member by member: on Windows PowerShell 5.1 both `[pscustomobject]@{...}`
# and `$table['k'] = @($genericListOfPSObjects)` throw
# `Argument types do not match` (measured while writing this script, and
# reproduced in isolation), so the rows are handed over with `.ToArray()`.
$summary = @{}
$summary['label'] = [string]$Label
$summary['engine_version'] = [string]$version
$summary['git_head'] = [string]$head
$summary['git_head_short'] = [string]$headShort
$summary['port_9877_pass'] = [bool]$verdict.pass
$summary['port_9877_classification'] = [string]$verdict.classification
$summary['port_9877_evidence'] = [string]$verdict.evidence
$summary['probes'] = $script:Rows.ToArray()
$summaryPath = Join-Path $Evid 'summary.json'
$summaryJson = ConvertTo-Json $summary -Depth 12
Write-McpUtf8NoBom -Path $summaryPath -Text $summaryJson

Write-Host ''
Write-Host '========================== SUMMARY =========================='
foreach ($row in $script:Rows) {
    Write-Host ("{0,-34} code={1,-12} suggestion={2}" -f $row.id, $row.code, (Get-Suggestion $row))
}
Write-Host ("probes          : {0}" -f $script:Rows.Count)
Write-Host ("port 9877 guard : pass={0} classification={1}" -f $verdict.pass, $verdict.classification)
Write-Host ("summary         : {0}" -f $summaryPath)
Write-Host ("summary sha256  : {0}" -f (Get-FileSha $summaryPath))

if (-not $verdict.pass) { exit 1 }
exit 0
