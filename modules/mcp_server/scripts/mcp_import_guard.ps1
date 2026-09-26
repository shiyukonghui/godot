# =============================================================================
#  mcp_import_guard.ps1 -- TASK-028 D-1: the one hardened scratch-project helper
#
#  Dot-source this file and call the two functions:
#
#      . "$PSScriptRoot\mcp_import_guard.ps1"
#      Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text $lines
#      $import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
#
#  It exists because the discipline is now three rules that every script creating
#  a scratch project and running `--import` needs, and that used to be
#  re-implemented - or forgotten - once per script:
#
#    1. a scratch project's text files are written **without a BOM**
#       (`Write-McpUtf8NoBom`). `Set-Content -Encoding UTF8` on Windows
#       PowerShell 5.1 prepends a BOM; two gate scripts and `mcp014` did exactly
#       that until TASK-028.
#    2. `--import`'s **exit code is checked**. A non-zero exit is a failure of the
#       gate, never something to ignore: the editor may have left a half-imported
#       project behind, and every later check then measures the wrong thing.
#    3. a failure is **retried a bounded number of times**, and every attempt
#       prints the command line, the project path, the exit code, the log path and
#       the log's tail - so a diagnosis never requires editing the script.
#
#  Why (2) and (3) are not optional: a brand-new project directory's first
#  `--import` was observed to die with `0xC0000005` (exit code -1073741819) four
#  times in this project's history (M3, mcp016, mcp026, mcp027). TASK-028's
#  controlled probe could not reproduce it in 84 first imports (see
#  scripts/mcp028_import_crash_probe.ps1 and REPORT-028), so the *frequency* is
#  unknown - which is exactly why a gate must neither ignore the exit code nor
#  fail on a single one.
# =============================================================================

function Write-McpUtf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Text = ''
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

# Writes a whole scratch project: `project.godot`, optionally a one-node
# `scenes/main.tscn`, every file without a BOM. This is the shape every evidence
# script of this module builds; it lives here so the *next* script does not make
# a sixteenth copy of the same five lines.
function New-McpScratchProject {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [bool]$WithMainScene = $true,
        [string]$SceneType = 'Node',
        [string[]]$ExtraProjectLines = @()
    )
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $lines = @(
        'config_version=5',
        '',
        '[application]',
        ('config/name="' + $Name + '"'),
        'config/features=PackedStringArray("4.8")'
    )
    if ($WithMainScene) { $lines += 'run/main_scene="res://scenes/main.tscn"' }
    $lines += $ExtraProjectLines
    $lines += @(
        '',
        '[rendering]',
        'renderer/rendering_method="gl_compatibility"',
        'renderer/rendering_method.mobile="gl_compatibility"'
    )
    Write-McpUtf8NoBom -Path (Join-Path $Path 'project.godot') -Text (($lines -join "`n") + "`n")
    if ($WithMainScene) {
        $sceneDir = Join-Path $Path 'scenes'
        New-Item -ItemType Directory -Force -Path $sceneDir | Out-Null
        $scene = @('[gd_scene format=3]', '', ('[node name="Main" type="' + $SceneType + '"]'))
        Write-McpUtf8NoBom -Path (Join-Path $sceneDir 'main.tscn') -Text (($scene -join "`n") + "`n")
    }
}

# Runs `--import` on a scratch project, checks the exit code, retries a bounded
# number of times and prints everything a diagnosis needs. Returns a hashtable
# `{ exit_code, attempts, log, command }`; throws when every attempt failed.
function Import-McpProject {
    param(
        [Parameter(Mandatory = $true)][string]$Engine,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$LogDirectory = $env:TEMP,
        [string]$Name = 'import',
        [int]$Attempts = 3,
        [int]$Port = 0,
        [switch]$NoPort,
        [int]$RetryDelayMs = 1500
    )
    if (-not (Test-Path $LogDirectory)) { New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null }
    # A missing engine is a *diagnosable* failure, not a native-command exception:
    # `& $Engine` with a path that does not exist throws a `CommandNotFoundException`
    # before `$LASTEXITCODE` is ever set, which bypasses every diagnostic below
    # (measured while writing this helper's own demonstration).
    if (-not (Test-Path $Engine)) {
        throw ('--import of "{0}" cannot run: the engine binary "{1}" does not exist (log directory {2})' -f `
                $Path, $Engine, $LogDirectory)
    }
    $arguments = @('--headless')
    if (-not $NoPort) { $arguments += ('--mcp-port=' + $Port) }
    $arguments += @('--path', $Path, '--import')
    $command = ('{0} {1}' -f $Engine, ($arguments -join ' '))

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $code = $null
    $log = $null
    try {
        for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
            $log = Join-Path $LogDirectory ('{0}.attempt{1}.log' -f $Name, $attempt)
            Remove-Item -Path $log -ErrorAction SilentlyContinue
            & $Engine @arguments *> $log
            $code = $LASTEXITCODE
            Write-Host ('import[{0}] attempt {1}/{2} exit={3} project={4} log={5}' -f $Name, $attempt, $Attempts, $code, $Path, $log)
            if ($code -eq 0) {
                return @{ exit_code = 0; attempts = $attempt; log = $log; command = $command }
            }
            # The diagnosis, on every failed attempt: the exact command, the code,
            # where the log is, and its tail. A reader must not have to re-run the
            # script to learn what happened.
            Write-Host ('  DIAGNOSTIC: {0}' -f $command)
            # `-1073741819` is `0xC0000005` in two's complement. The mask is
            # written as the decimal `4294967295` on purpose: PowerShell parses
            # the literal `0xFFFFFFFF` as the **Int32** `-1`, and `-1073741819
            # -band -1` stays negative, so `[uint32]` would throw.
            $unsigned = [uint32]([int64]$code -band 4294967295)
            Write-Host ('  DIAGNOSTIC: exit code {0} (0x{1:X8}), project {2}' -f $code, $unsigned, $Path)
            Write-Host ('  DIAGNOSTIC: log {0}, tail:' -f $log)
            foreach ($line in (Get-Content $log -Tail 12 -ErrorAction SilentlyContinue)) {
                Write-Host ('    import| {0}' -f $line)
            }
            if ($attempt -lt $Attempts) { Start-Sleep -Milliseconds $RetryDelayMs }
        }
    } finally {
        $ErrorActionPreference = $previous
    }
    throw ('--import of "{0}" failed {1} time(s); last exit code {2} (0x{3:X8}); see {4}' -f `
            $Path, $Attempts, $code, [uint32]([int64]$code -band 4294967295), $log)
}