$root = 'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server'
$files = @(
    'tools\running_game_node_write.cpp',
    'tools\running_game_node_write.h',
    'tools\editor_node_batch_write.cpp',
    'tools\project_cross_scene_write.cpp',
    'tools\editor_testing_read.cpp',
    'tests\test_mcp_server.h',
    'scripts\mcp_import_guard.ps1',
    'scripts\mcp028_import_crash_probe.ps1',
    'scripts\mcp028_subpaths_clear_import_evidence.ps1',
    'scripts\accept_m1.ps1',
    'scripts\check_contract_subset.ps1',
    'docs\tasks\PLAYBOOK-group-port.md'
)
foreach ($f in $files) {
    $p = Join-Path $root $f
    $h = (Get-FileHash -Algorithm SHA256 -Path $p).Hash.ToLower()
    Write-Output ("{0}  {1}" -f $h, $f)
}
