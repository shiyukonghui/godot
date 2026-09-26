# =============================================================================
#  mcp067_env.ps1 -- TASK-067 shared harness (pure ASCII).
#
#  Dot-source this file. It reuses the TASK-066 role-B harness
#  (`mcp066b_env.ps1`) for the pieces that have nothing to do with the task -
#  the one `tools/call` wrapper (request/response bytes through
#  `mcp_evidence_guard.ps1`, unique `<leaf>__<seq>__<sha8>` names, a hard refusal
#  to overwrite referenced evidence), the shared-file trace readers and the
#  port/process helpers that only ever touch PIDs this harness started - and
#  re-points every task-specific PATH at TASK-067's own scratch and evidence
#  trees. No shared script is modified.
#
#  DISCIPLINE (TASK-067): port 9877 is never occupied, killed or restarted; the
#  only ports used are 9888 (editor) and 9889 (game); nothing under
#  modules/mcp_server/tools|tests or the contract is written by this harness.
# =============================================================================

$McpRoot067 = 'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server'
. (Join-Path $McpRoot067 'scripts\mcp066b_env.ps1')

# --- TASK-067 paths (override what mcp066b_env.ps1 assigned) ----------------
$ScratchRoot = Join-Path $env:TEMP 'mcp067'
$IoRoot = Join-Path $ScratchRoot 'io'
$EvidenceRoot = Join-Path $McpRoot067 'docs\reports\evidence\task067'
$MixedProj = Join-Path $ScratchRoot 'proj-mixed'
$CommentProj = Join-Path $ScratchRoot 'proj-comments'
$BreakoutSrc = Join-Path $env:TEMP 'mcp-breakout-cs\proj'
$MonoExe = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe'
$PlainExe = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$EditorPort = 9888
$GamePort = 9889
$EditorTrace = Join-Path $ScratchRoot 'trace-editor.jsonl'
$EditorOutLog = Join-Path $ScratchRoot 'editor.out.log.txt'
$EditorErrLog = Join-Path $ScratchRoot 'editor.err.log.txt'
# `Globalize-ResPath` in the reused harness resolves `res://` against `$Proj`.
$Proj = $MixedProj

Ensure-Dir $ScratchRoot | Out-Null
Ensure-Dir $IoRoot | Out-Null
Ensure-Dir $EvidenceRoot | Out-Null

# ---------------------------------------------------------------------------
#  Project fixtures.
# ---------------------------------------------------------------------------

# The four hand written probe comments. They are deliberately spread so that
# three of them are NOT in the last section of the file: `[input]` is followed
# by `[physics]` and `[rendering]`, which is the shape a splice-based writer gets
# wrong (TASK-057 patch 2's header).
$ProbeComments = @(
    '; mcp067 comment 1 of 4 - before any section',
    '; mcp067 comment 2 of 4 - directly above [input]',
    '; mcp067 comment 3 of 4 - inside [input] after the action',
    '; mcp067 comment 4 of 4 - inside [rendering], the last section'
)

function New-CommentProjectText {
    return @"
; mcp067 comment 1 of 4 - before any section
config_version=5

[application]

config/name="Mcp067CommentProbe"
config/features=PackedStringArray("4.5", "Forward Plus", "C#")
run/main_scene="res://scenes/main.tscn"

; mcp067 comment 2 of 4 - directly above [input]
[input]

probe_action={
"deadzone": 0.5,
"events": []
}
; mcp067 comment 3 of 4 - inside [input] after the action

[physics]

common/physics_ticks_per_second=60

[rendering]
; mcp067 comment 4 of 4 - inside [rendering], the last section
renderer/rendering_method="forward_plus"
"@
}

# Rebuilds `$CommentProj` from scratch: project.godot with the four probe
# comments, one trivial scene, and a `.cs` + `.gd` pair so the same project also
# answers the script-listing question. Every file is written through the shared
# `Write-McpUtf8NoBom` (a BOM would change the sha comparison).
function Reset-CommentProject {
    if (Test-Path -LiteralPath $CommentProj) { Remove-Item -LiteralPath $CommentProj -Recurse -Force }
    Ensure-Dir (Join-Path $CommentProj 'scenes') | Out-Null
    Ensure-Dir (Join-Path $CommentProj 'scripts') | Out-Null
    Write-McpUtf8NoBom -Path (Join-Path $CommentProj 'project.godot') -Text (New-CommentProjectText)
    Write-McpUtf8NoBom -Path (Join-Path $CommentProj 'scenes\main.tscn') -Text "[gd_scene format=3]`n`n[node name=`"Main`" type=`"Node2D`"]`n"
    Write-McpUtf8NoBom -Path (Join-Path $CommentProj 'scripts\ProbeGd.gd') -Text "extends Node`n`nvar probe := true`n"
    Write-McpUtf8NoBom -Path (Join-Path $CommentProj 'scripts\ProbeCs.cs') -Text "// probe`npublic partial class ProbeCs : Node { }`n"
    return $CommentProj
}

# A byte-identical copy of A's TASK-066 C# fixture plus two GDScript files, so
# the script-listing answer must carry BOTH languages. The source fixture is
# never modified (the copy is what is started).
function Reset-MixedProject {
    if (Test-Path -LiteralPath $MixedProj) { Remove-Item -LiteralPath $MixedProj -Recurse -Force }
    # Copy the CONTENTS, not the directory: `Copy-Item <dir> -Destination
    # <existing dir> -Recurse` creates `<destination>\<source name>\...`, so the
    # project ends up one level down and its root has no `project.godot`.
    # Measured while writing this harness: the first run's editor answered with
    # `res://` of a directory that was not a project, which made `cs=0` look like
    # F-066-1 for the wrong reason. The root is asserted by the caller.
    New-Item -ItemType Directory -Force -Path $MixedProj | Out-Null
    foreach ($item in (Get-ChildItem -LiteralPath $BreakoutSrc -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $MixedProj -Recurse -Force
    }
    Write-McpUtf8NoBom -Path (Join-Path $MixedProj 'scripts\ProbeGd.gd') -Text "extends Node`n`nvar probe := true`n"
    Write-McpUtf8NoBom -Path (Join-Path $MixedProj 'scripts\ProbeGd2.gd') -Text "extends Node`n"
    return $MixedProj
}

# ---------------------------------------------------------------------------
#  `project.godot` snapshots: bytes -> evidence (unique name), plus the numbers
#  the comment question is actually about.
# ---------------------------------------------------------------------------
function Get-CommentLineCount([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return -1 }
    $text = [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding($false)))
    $count = 0
    foreach ($line in ($text -split "`n")) {
        if ($line.TrimStart().StartsWith(';')) { $count++ }
    }
    return $count
}

function Get-ProbeCommentSurvival([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $text = [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding($false)))
    return Get-ProbeCommentSurvivalInText -Text $text
}

# The same vector, computed from a snapshot's bytes instead of from the live file,
# so a check can be about the state at one point in the run rather than about
# "whatever the file looks like now".
function Get-ProbeCommentSurvivalInText([string]$Text) {
    $found = @()
    foreach ($comment in $ProbeComments) {
        $found += [bool]$Text.Contains($comment)
    }
    return $found
}

# Every comment line of a `project.godot` text, in file order. The engine's own
# writer emits seven header comment lines of its own, so "how many comment lines"
# is NOT "did the probe comments survive" - both are needed, separately.
function Get-CommentLinesFromText([string]$Text) {
    return @($Text -split "`n" | Where-Object { $_.TrimStart().StartsWith(';') })
}

# Every `path` of the files below a `project_get_filesystem_tree` node, found
# recursively (the answer nests `children`).
function Get-TreePaths($Node) {
    $out = @()
    if ($null -eq $Node) { return $out }
    if ($Node.path) { $out += [string]$Node.path }
    if ($Node.children) {
        foreach ($child in @($Node.children)) {
            $out += Get-TreePaths $child
        }
    }
    return $out
}

# Snapshot a file into the evidence tree under a unique, sha-bearing name and
# report the numbers. `-Leaf` must be unique per snapshot point.
function Save-ProjectSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Leaf,
        [Parameter(Mandatory = $true)][string]$Directory
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Exists = $false; Sha256 = ''; Bytes = 0; CommentLines = -1; EvidencePath = ''; Text = '' }
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $written = Write-McpEvidenceBytes -Directory $Directory -Leaf $Leaf -Bytes $bytes -Extension '.project.godot'
    return [pscustomobject]@{
        Exists       = $true
        Sha256       = $written.Sha256
        Bytes        = $bytes.Length
        CommentLines = Get-CommentLineCount -Path $Path
        EvidencePath = $written.Path
        Text         = [Text.Encoding]::UTF8.GetString($bytes)
    }
}

# ---------------------------------------------------------------------------
#  Engine processes. Windowed unless `-Headless` is passed, always with the MCP
#  port the harness owns, always with stdout/stderr redirected to files so the
#  real exit state is readable (never through a pipe).
# ---------------------------------------------------------------------------
function Start-McpEditor {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][int]$Port,
        [string[]]$ExtraArgs = @(),
        [switch]$Headless
    )
    $argv = New-Object System.Collections.ArrayList
    if ($Headless) { [void]$argv.Add('--headless') }
    [void]$argv.Add('--path')
    [void]$argv.Add($ProjectPath)
    [void]$argv.Add('-e')
    [void]$argv.Add(('--mcp-port={0}' -f $Port))
    [void]$argv.Add('--mcp-trace')
    [void]$argv.Add($EditorTrace)
    foreach ($extra in $ExtraArgs) { [void]$argv.Add($extra) }
    return Start-OwnProcess -Exe $Exe -EngineArgs ([string[]]$argv) -OutLog $EditorOutLog -ErrLog $EditorErrLog
}

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

# A derived JSON artefact (a summary table, a set computation) that has to be
# reproducible from the raw request/response bodies next to it. It goes through
# the same unique, sha-bearing writer as the bodies, so two runs cannot overwrite
# each other's evidence.
function Write-McpSummary {
    param(
        [Parameter(Mandatory = $true)][string]$RunDir,
        [Parameter(Mandatory = $true)][string]$Leaf,
        [Parameter(Mandatory = $true)]$Object
    )
    Ensure-Dir $RunDir | Out-Null
    $json = ($Object | ConvertTo-Json -Depth 40)
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($json)
    return Write-McpEvidenceBytes -Directory $RunDir -Leaf $Leaf -Bytes $bytes -Extension '.summary.json'
}