# =============================================================================
#  mcp038_probes.ps1 -- the probe set shared by the TASK-038 evidence scripts.
#
#  A probe is one complete JSON-RPC request. The bodies are built with
#  `ConvertTo-Json` (a hand written body on a Windows command line loses its
#  quotes and becomes a -32700, PLAYBOOK section 3), so every run sends byte
#  identical requests and the responses can be compared by sha256.
#
#  The set covers: the two method envelopes (`initialize`, `ping`), the full
#  `tools/list`, successful tool calls, a missing resource (-32001), a missing
#  argument (-32602), an undeclared argument (-32602), an unknown tool (-32601)
#  and an unknown method (-32601).
# =============================================================================

function New-Mcp038Probes {
    $probes = New-Object System.Collections.Generic.List[object]

    $probes.Add([pscustomobject]@{ id = 1; label = 'initialize'; method = 'initialize'; name = ''; args = $null })
    $probes.Add([pscustomobject]@{ id = 2; label = 'tools/list'; method = 'tools/list'; name = ''; args = $null })
    $probes.Add([pscustomobject]@{ id = 3; label = 'ping'; method = 'ping'; name = ''; args = $null })
    $probes.Add([pscustomobject]@{ id = 4; label = 'project_get_info'; method = 'tools/call'; name = 'project_get_info'; args = @{} })
    $probes.Add([pscustomobject]@{ id = 5; label = 'project_get_settings'; method = 'tools/call'; name = 'project_get_settings'; args = @{} })
    $probes.Add([pscustomobject]@{ id = 6; label = 'project_get_statistics'; method = 'tools/call'; name = 'project_get_statistics'; args = @{} })
    $probes.Add([pscustomobject]@{ id = 7; label = 'project_list_scripts'; method = 'tools/call'; name = 'project_list_scripts'; args = @{} })
    $probes.Add([pscustomobject]@{ id = 8; label = 'project_get_filesystem_tree'; method = 'tools/call'; name = 'project_get_filesystem_tree'; args = @{} })
    $probes.Add([pscustomobject]@{ id = 9; label = 'project_read_script ok'; method = 'tools/call'; name = 'project_read_script'; args = @{ path = 'res://scripts/hello.gd' } })
    $probes.Add([pscustomobject]@{ id = 10; label = 'project_read_script missing'; method = 'tools/call'; name = 'project_read_script'; args = @{ path = 'res://no_such_script_038.gd' } })
    $probes.Add([pscustomobject]@{ id = 11; label = 'project_read_script no args'; method = 'tools/call'; name = 'project_read_script'; args = @{} })
    $probes.Add([pscustomobject]@{ id = 12; label = 'project_get_info unknown argument'; method = 'tools/call'; name = 'project_get_info'; args = @{ bogus_argument = 1 } })
    $probes.Add([pscustomobject]@{ id = 13; label = 'project_validate_script'; method = 'tools/call'; name = 'project_validate_script'; args = @{ path = 'res://scripts/hello.gd' } })
    $probes.Add([pscustomobject]@{ id = 14; label = 'project_get_scene_dependencies'; method = 'tools/call'; name = 'project_get_scene_dependencies'; args = @{ path = 'res://scenes/main.tscn' } })
    $probes.Add([pscustomobject]@{ id = 15; label = 'project_analyze_scene_complexity'; method = 'tools/call'; name = 'project_analyze_scene_complexity'; args = @{ path = 'res://scenes/main.tscn' } })
    $probes.Add([pscustomobject]@{ id = 16; label = 'project_read_scene_file_content'; method = 'tools/call'; name = 'project_read_scene_file_content'; args = @{ path = 'res://scenes/main.tscn' } })
    $probes.Add([pscustomobject]@{ id = 17; label = 'project_find_unused_resources'; method = 'tools/call'; name = 'project_find_unused_resources'; args = @{} })
    $probes.Add([pscustomobject]@{ id = 18; label = 'project_detect_circular_dependencies'; method = 'tools/call'; name = 'project_detect_circular_dependencies'; args = @{} })
    $probes.Add([pscustomobject]@{ id = 19; label = 'project_search_file_names'; method = 'tools/call'; name = 'project_search_file_names'; args = @{ pattern = 'main' } })
    $probes.Add([pscustomobject]@{ id = 20; label = 'project_search_file_contents'; method = 'tools/call'; name = 'project_search_file_contents'; args = @{ pattern = 'hello' } })
    $probes.Add([pscustomobject]@{ id = 21; label = 'unknown tool'; method = 'tools/call'; name = 'project_get_no_such_tool_038'; args = @{} })
    $probes.Add([pscustomobject]@{ id = 22; label = 'unknown method'; method = 'no_such_method_038'; name = ''; args = $null })

    return $probes
}

# The request body of one probe, as a JSON string.
function Get-Mcp038ProbeBody {
    param($Probe)
    if ($Probe.method -eq 'tools/call') {
        $request = @{
            jsonrpc = '2.0'
            id = $Probe.id
            method = 'tools/call'
            params = @{ name = $Probe.name; arguments = $Probe.args }
        }
    } else {
        $request = @{ jsonrpc = '2.0'; id = $Probe.id; method = $Probe.method; params = @{} }
    }
    return ($request | ConvertTo-Json -Depth 10 -Compress)
}

# The `project.godot` + one script + one scene every TASK-038 evidence run uses.
function New-Mcp038ScratchProject {
    param([string]$Path)
    New-McpScratchProject -Path $Path -Name 'MCP 038 evidence' -WithMainScene $true
    Write-McpUtf8NoBom -Path (Join-Path $Path 'scripts\hello.gd') -Text ("extends Node`n`nconst MARKER := `"TASK038`"`n")
}