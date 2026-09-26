# =============================================================================
#  mcp028_import_crash_probe.ps1 -- TASK-028 D-1, the `--import` investigation
#
#  The question: a brand-new project directory whose first `--import` exits with
#  `0xC0000005` (exit code -1073741819) while the second one exits 0. TASK-027
#  recorded one such run for a project **with** a `.tscn`; TASK-026's probe
#  project (no `.tscn`) imported first time. This script answers the four
#  candidate triggers the task book names, each as its own *fresh* directory:
#
#    1. the presence of a `.tscn`;
#    2. a UTF-8 **BOM** (in the `.tscn`, and in `project.godot`);
#    3. `--mcp-port` (absent / `=0` / `=9888`) - i.e. whether the module's HTTP
#       server is what is being started when the process dies;
#    4. the `.tscn`'s content (a bare node vs an `ext_resource` reference).
#
#  Every run is a fresh directory with no `.godot`, so "the first import" really
#  is the first one. For each variant the script also imports the *same* project a
#  second time, which is the "already initialised" control.
#
#  What it records per run: the exit code, whether the engine's own
#  `EditorNode::is_cmdline_mode` stderr line appeared, whether a `Parse Error`
#  appeared, and whether `.godot/` was produced (so a crash can be told from a
#  run that did nothing at all).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp028_import_crash_probe.ps1 -Repetitions 6
#
#  Port discipline: the variants that listen use 9888 (a test port). The user's
#  Godot 4.7.1-mono on 9877 is only *read* (its pid is recorded before and after)
#  and is never started, stopped or bound by this script.
# =============================================================================

param(
    [int]$Repetitions = 6,
    [string]$OutRoot = '',
    [int]$UserPort = 9877,
    [int]$TestPort = 9888
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp028-import-crash-probe' }
$Root = $OutRoot
$LogRoot = Join-Path $Root 'logs'
$ProjRoot = Join-Path $Root 'projects'

$script:Runs = New-Object System.Collections.Generic.List[object]

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

function Write-Utf8Bom {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($true)).GetBytes($Text))
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

$ProjectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp028_import_probe"'
    'run/main_scene="res://scenes/main.tscn"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"

$ScenePlain = @(
    '[gd_scene format=3]'
    ''
    '[node name="Main" type="Node2D"]'
) -join "`n"

$SceneExtResource = @(
    '[gd_scene load_steps=2 format=3]'
    ''
    '[ext_resource type="Script" path="res://probe.gd" id="1_probe"]'
    ''
    '[node name="Main" type="Node2D"]'
    'script = ExtResource("1_probe")'
) -join "`n"

# `-mcp-port` argument of each variant: $null means "do not pass the flag at all"
# (the editor then uses the module's default of 9877, which is *occupied* by the
# user's editor - the module must refuse to listen, and the process must survive
# that refusal).
$Variants = @(
    @{ id = 'tscn_nobom_port0'; scene = 'plain';  bom_scene = $false; bom_project = $false; port = 0 },
    @{ id = 'tscn_bom_port0'; scene = 'plain';  bom_scene = $true;  bom_project = $false; port = 0 },
    @{ id = 'tscn_bom_both_port0'; scene = 'plain'; bom_scene = $true; bom_project = $true; port = 0 },
    @{ id = 'notscn_nobom_port0'; scene = 'none'; bom_scene = $false; bom_project = $false; port = 0 },
    @{ id = 'tscn_nobom_noport'; scene = 'plain'; bom_scene = $false; bom_project = $false; port = $null },
    @{ id = 'tscn_nobom_port9888'; scene = 'plain'; bom_scene = $false; bom_project = $false; port = $TestPort },
    @{ id = 'tscn_extres_nobom_port0'; scene = 'extres'; bom_scene = $false; bom_project = $false; port = 0 }
)

function New-ProbeProject {
    param([string]$Path, $Variant)
    Remove-Item -Recurse -Force $Path -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    if ($Variant.bom_project) {
        Write-Utf8Bom -Path (Join-Path $Path 'project.godot') -Text ($ProjectGodot + "`n")
    } else {
        Write-Utf8NoBom -Path (Join-Path $Path 'project.godot') -Text ($ProjectGodot + "`n")
    }
    switch ($Variant.scene) {
        'plain'  { if ($Variant.bom_scene) { Write-Utf8Bom -Path (Join-Path $Path 'scenes\main.tscn') -Text ($ScenePlain + "`n") } else { Write-Utf8NoBom -Path (Join-Path $Path 'scenes\main.tscn') -Text ($ScenePlain + "`n") } }
        'extres' { if ($Variant.bom_scene) { Write-Utf8Bom -Path (Join-Path $Path 'scenes\main.tscn') -Text ($SceneExtResource + "`n") } else { Write-Utf8NoBom -Path (Join-Path $Path 'scenes\main.tscn') -Text ($SceneExtResource + "`n") }; Write-Utf8NoBom -Path (Join-Path $Path 'probe.gd') -Text "extends Node`n`n@export var probe := true`n" }
        'none'   { }
    }
}

# One `--import`, with the true exit code and the two stderr signatures the
# PLAYBOOK and the earlier reports name.
function Invoke-OneImport {
    param([string]$Project, $Port_, [string]$LogPath)
    $args = @('--headless')
    if ($null -ne $Port_) { $args += ("--mcp-port=" + $Port_) }
    $args += @('--path', $Project, '--import')
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Engine @args *> $LogPath
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    $text = Get-Content -Raw $LogPath -ErrorAction SilentlyContinue
    $record = [pscustomobject]@{
        exit_code            = $code
        godot_dir_present    = Test-Path (Join-Path $Project '.godot')
        singleton_is_null    = ($text -match 'is_cmdline_mode|Parameter "singleton" is null')
        parse_error          = ($text -match "Parse Error")
        log                  = $LogPath
    }
    return $record
}

# =============================================================================
#  Main
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $LogRoot, $ProjRoot | Out-Null

if (-not (Test-Path $Engine)) {
    Write-Host ("FATAL: engine binary not found: {0}" -f $Engine)
    exit 2
}

Write-Host '============================================================='
Write-Host ' TASK-028 D-1 -- first `--import` of a brand-new project'
Write-Host '============================================================='
Write-Host ("engine     : {0}" -f $Engine)
Write-Host ("engine hash: {0}" -f ((& $Engine --version) -join ''))
Write-Host ("head       : {0}" -f ((& git -C $RepoRoot rev-parse --short HEAD) -join ''))
Write-Host ("repetitions: {0}" -f $Repetitions)

$userPidBefore = Get-ListenerPid -Port_ $UserPort
Write-Host ("port {0} owner before: pid={1} (recorded, never touched)" -f $UserPort, $userPidBefore)
if ((Get-ListenerPid -Port_ $TestPort) -ne -1) {
    Write-Host ("FATAL: test port {0} is already in use" -f $TestPort)
    exit 2
}

foreach ($variant in $Variants) {
    for ($i = 1; $i -le $Repetitions; $i++) {
        $project = Join-Path $ProjRoot ("{0}-{1}" -f $variant.id, $i)
        New-ProbeProject -Path $project -Variant $variant
        $first = Invoke-OneImport -Project $project -Port_ $variant.port -LogPath (Join-Path $LogRoot ("{0}-{1}-first.log" -f $variant.id, $i))
        # The control: the same directory, now initialised.
        $second = Invoke-OneImport -Project $project -Port_ $variant.port -LogPath (Join-Path $LogRoot ("{0}-{1}-second.log" -f $variant.id, $i))

        foreach ($phase in @(@{ name = 'first'; rec = $first }, @{ name = 'second'; rec = $second })) {
            $script:Runs.Add([pscustomobject]@{
                    variant           = $variant.id
                    repetition        = $i
                    phase             = $phase.name
                    exit_code         = $phase.rec.exit_code
                    godot_dir_present = $phase.rec.godot_dir_present
                    singleton_is_null = $phase.rec.singleton_is_null
                    parse_error       = $phase.rec.parse_error
                    log               = $phase.rec.log
                })
            $tag = if ($phase.rec.exit_code -eq 0) { 'OK   ' } else { 'CRASH' }
            Write-Host ("[{0}] {1} #{2} {3} exit={4} .godot={5} singleton_err={6} parse_err={7}" -f `
                    $tag, $variant.id, $i, $phase.name, $phase.rec.exit_code, $phase.rec.godot_dir_present, $phase.rec.singleton_is_null, $phase.rec.parse_error)
        }
    }
}

$userPidAfter = Get-ListenerPid -Port_ $UserPort

Write-Host ''
Write-Host '--- summary (exit code <> 0 is the defect under investigation) ---'
$script:Runs | Group-Object variant, phase, exit_code | Sort-Object Name | ForEach-Object {
    Write-Host ("{0,-34} exit={1,-12} count={2}" -f $_.Name, ($_.Name -split ', ')[2], $_.Count)
}
$crashes = @($script:Runs | Where-Object { $_.exit_code -ne 0 })
Write-Host ("runs total         : {0}" -f $script:Runs.Count)
Write-Host ("runs non-zero exit : {0}" -f $crashes.Count)
Write-Host ("singleton_err runs : {0}" -f @($script:Runs | Where-Object { $_.singleton_is_null }).Count)
Write-Host ("parse_error runs   : {0}" -f @($script:Runs | Where-Object { $_.parse_error }).Count)
Write-Host ("port {0} owner after : pid={1} (before {2})" -f $UserPort, $userPidAfter, $userPidBefore)

$summary = [pscustomobject]@{
    engine            = $Engine
    engine_version    = ((& $Engine --version) -join '')
    head              = ((& git -C $RepoRoot rev-parse --short HEAD) -join '')
    repetitions       = $Repetitions
    user_port_pid     = $userPidBefore
    user_port_pid_now = $userPidAfter
    runs              = $script:Runs
}
[IO.File]::WriteAllBytes((Join-Path $Root 'summary.json'), (New-Object Text.UTF8Encoding($false)).GetBytes((ConvertTo-Json -InputObject $summary -Depth 6)))

Write-Host ("summary: {0}" -f (Join-Path $Root 'summary.json'))
if ($crashes.Count -gt 0) { exit 1 }
exit 0
