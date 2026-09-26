# =============================================================================
#  mcp068_env.ps1 -- TASK-068 shared harness (pure ASCII).
#
#  Dot-source this file. It reuses TASK-067's harness (`mcp067_env.ps1`) for the
#  pieces that have nothing to do with this task - the one `tools/call` wrapper
#  (request/response bytes through `mcp_evidence_guard.ps1`, unique
#  `<leaf>__<seq>__<sha8>` names, a refusal to overwrite referenced evidence),
#  the shared-file trace readers, the import guard and the port/process helpers
#  that only ever touch PIDs this harness started - and re-points every
#  task-specific path at TASK-068's own scratch and evidence trees.
#  No shared script is modified.
#
#  DISCIPLINE (TASK-068): port 9877 is never occupied, killed or restarted; the
#  only ports used are 9888 (editor) and 9889 (game); the contract, the generator
#  and the manifests are read by this harness, never written.
# =============================================================================

$McpRoot068 = 'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server'
. (Join-Path $McpRoot068 'scripts\mcp067_env.ps1')

# --- TASK-068 paths (override what mcp067_env.ps1 assigned) -----------------
$ScratchRoot = Join-Path $env:TEMP 'mcp068'
$IoRoot = Join-Path $ScratchRoot 'io'
$EvidenceRoot = Join-Path $McpRoot068 'docs\reports\evidence\task068'
$MonoProj = Join-Path $ScratchRoot 'proj-mono'
$BreakoutSrc = Join-Path $env:TEMP 'mcp-breakout-cs\proj'
$BreakoutDll = Join-Path $BreakoutSrc '.godot\mono\temp\bin\Debug\McpBreakoutCs.dll'
$MonoExe = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe'
$PlainExe = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$EditorPort = 9888
$GamePort = 9889
$EditorTrace = Join-Path $ScratchRoot 'trace-editor.jsonl'
$GameTrace = Join-Path $ScratchRoot 'trace-game.jsonl'
$EditorOutLog = Join-Path $ScratchRoot 'editor.out.log.txt'
$EditorErrLog = Join-Path $ScratchRoot 'editor.err.log.txt'
$GameOutLog = Join-Path $ScratchRoot 'game.out.log.txt'
$GameErrLog = Join-Path $ScratchRoot 'game.err.log.txt'
$Proj = $MonoProj

Ensure-Dir $ScratchRoot | Out-Null
Ensure-Dir $IoRoot | Out-Null
Ensure-Dir $EvidenceRoot | Out-Null

# ---------------------------------------------------------------------------
#  The fixture: a byte-identical copy of the TASK-066 C# breakout project plus
#  two GDScript files, so `project_list_scripts` has to answer across languages
#  and the engine's own generated `.cs` files under `res://.godot/mono/temp/obj`
#  are present on disk. The source fixture is never modified.
# ---------------------------------------------------------------------------
function Reset-MonoProject {
    if (Test-Path -LiteralPath $MonoProj) { Remove-Item -LiteralPath $MonoProj -Recurse -Force }
    # Copy the CONTENTS, not the directory (TASK-067's first-run bug: `Copy-Item
    # <dir> -Destination <existing dir> -Recurse` nests the source one level
    # down, so `res://` is not the project root).
    New-Item -ItemType Directory -Force -Path $MonoProj | Out-Null
    foreach ($item in (Get-ChildItem -LiteralPath $BreakoutSrc -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $MonoProj -Recurse -Force
    }
    Write-McpUtf8NoBom -Path (Join-Path $MonoProj 'scripts\ProbeGd.gd') -Text "extends Node`n`nvar probe := true`n"
    Write-McpUtf8NoBom -Path (Join-Path $MonoProj 'scripts\ProbeGd2.gd') -Text "extends Node`n"
    return $MonoProj
}

# Every path in the answer that lives under the engine's own project cache.
function Get-GodotCacheScripts($Scripts) {
    return @($Scripts | Where-Object { $_ -like 'res://.godot/*' })
}

# ---------------------------------------------------------------------------
#  Engine processes. The editor runs WINDOWED (`-e`) like TASK-067's harness; the
#  game runs from the same binary without `-e`, which is what makes a real game
#  process answer on 9889. stdout/stderr always go to files (never through a
#  pipe), so the real exit state is readable.
# ---------------------------------------------------------------------------
function Start-McpGame {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][int]$Port,
        [string[]]$ExtraArgs = @()
    )
    $argv = New-Object System.Collections.ArrayList
    [void]$argv.Add('--path')
    [void]$argv.Add($ProjectPath)
    [void]$argv.Add(('--mcp-port={0}' -f $Port))
    [void]$argv.Add('--mcp-trace')
    [void]$argv.Add($GameTrace)
    foreach ($extra in $ExtraArgs) { [void]$argv.Add($extra) }
    return Start-OwnProcess -Exe $Exe -EngineArgs ([string[]]$argv) -OutLog $GameOutLog -ErrLog $GameErrLog
}

# The engine's own import guard, with the bounded retry and the diagnostics the
# PLAYBOOK requires. `-NoPort` on purpose: an `--import` run must not take a port.
function Import-Project {
    param(
        [Parameter(Mandatory = $true)][string]$Engine,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return (Import-McpProject -Engine $Engine -Path $Path -LogDirectory $ScratchRoot -Name $Name -NoPort)
}

# The engine binary's self-reported version, written into the evidence tree.
function Get-EngineVersion([string]$Exe, [string]$LogPath) {
    $out = & $Exe --version 2>&1
    $text = [string]($out -join "`n")
    [IO.File]::WriteAllText($LogPath, $text + "`n", (New-Object Text.UTF8Encoding($false)))
    return $text.Trim()
}

function Assert-Port9877Untouched([string]$CheckId) {
    $listening = Get-ListeningPorts
    Add-Check $CheckId (-not ($listening -contains 9877)) ('listening ports: ' + (@($listening) -join ','))
}
