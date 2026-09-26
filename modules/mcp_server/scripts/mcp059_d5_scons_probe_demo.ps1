# =============================================================================
#  mcp059_d5_scons_probe_demo.ps1 -- TASK-059 D-5 evidence.
#
#  `mcp057_build_mono.cmd` (and, in the same two lines, `build_local.cmd`) used
#  to call `D:\Anaconda\Scripts\scons.exe` by absolute path. That works on
#  exactly one machine and fails elsewhere with a native "not recognized as an
#  internal or external command" that names nothing. TASK-059 replaced both with
#  the same three-candidate probe (%SCONS% -> `scons` on PATH -> the known
#  absolute path) plus a readable error, and this file demonstrates all of it:
#
#    d5_build_local_resolves                  --probe-only resolves and exits 0
#    d5_build_mono_resolves                   --probe-only resolves and exits 0
#    d5_resolution_names_its_source           the printed line says WHICH
#                                             candidate won, so a wrong
#                                             interpreter is visible rather
#                                             than silent
#    d5_scrap_the_path                       with %SCONS% pointing at nothing and
#                                             the known path disabled and `scons`
#                                             off PATH, the probe fails with the
#                                             readable message and exit code 3
#                                             (this is the case that used to be
#                                             an inscrutable native error)
#    d5_no_hardcoded_invocation_left          neither .cmd still *runs* the
#                                             absolute path: `D:\Anaconda\...`
#                                             survives only as the documented
#                                             third candidate
#
#  Nothing is built here: every invocation is `--probe-only`.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp059_d5_scons_probe_demo.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$BuildLocal = Join-Path $PSScriptRoot 'build_local.cmd'
$BuildMono = Join-Path $PSScriptRoot 'mcp057_build_mono.cmd'
$OutRoot = Join-Path $env:TEMP ('mcp059\d5-probe\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$script:Failures = 0

function Check([string]$Id, [bool]$Ok, [string]$EvidenceText) {
    $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
    if (-not $Ok) { $script:Failures++ }
    Write-Host ("[{0}] {1} :: {2}" -f $tag, $Id, $EvidenceText)
}

function Invoke-Probe([string]$Script, [string]$Label, [hashtable]$Environment) {
    $log = Join-Path $OutRoot ($Label + '.txt')
    if ($null -eq $Environment) {
        & cmd /c ("`"{0}`" --probe-only > `"{1}`" 2>&1" -f $Script, $log)
        $code = $LASTEXITCODE
    } else {
        # A tiny wrapper .cmd rather than one long `cmd /c` string: the `set`
        # lines and the `&&` chain survived PowerShell's argument marshalling
        # badly (measured: the whole thing came back as a native "filename,
        # directory name, or volume label syntax is incorrect"), and a file is
        # also what a reader can inspect afterwards.
        $wrapper = Join-Path $OutRoot ($Label + '.wrapper.cmd')
        $lines = @('@echo off')
        foreach ($key in $Environment.Keys) { $lines += ('set "{0}={1}"' -f $key, $Environment[$key]) }
        $lines += ('call "{0}" --probe-only' -f $Script)
        $lines += 'exit /b %ERRORLEVEL%'
        [IO.File]::WriteAllLines($wrapper, $lines)
        & cmd /c ("`"{0}`" > `"{1}`" 2>&1" -f $wrapper, $log)
        $code = $LASTEXITCODE
    }
    $text = ''
    if (Test-Path $log) { $text = [IO.File]::ReadAllText($log) }
    $resolved = ''
    foreach ($candidate in ($text -split "`r?`n")) {
        if ($candidate.TrimStart().StartsWith('scons:')) { $resolved = $candidate.Trim(); break }
    }
    $fatal = ''
    foreach ($candidate in ($text -split "`r?`n")) {
        if ($candidate.StartsWith('FATAL: no scons')) { $fatal = $candidate.Trim(); break }
    }
    return @{ code = $code; text = $text; resolved = $resolved; fatal = $fatal; log = $log }
}

Write-Host '============================================================='
Write-Host ' TASK-059 D-5: the scons probe in both build scripts'
Write-Host (' repo : ' + $RepoRoot)
Write-Host (' out  : ' + $OutRoot)
Write-Host '============================================================='

$envString = ''
foreach ($key in @('SCONS', 'PATH')) {
    $value = [Environment]::GetEnvironmentVariable($key)
    $envString += ('{0}={1}; ' -f $key, $value)
}
Write-Host ('environment before the demo: ' + $envString)

$local = Invoke-Probe $BuildLocal 'build_local' $null
Check 'd5_build_local_resolves' ($local.code -eq 0 -and $local.resolved.Length -gt 0) ("exit={0}; {1}" -f $local.code, $local.resolved)

$mono = Invoke-Probe $BuildMono 'build_mono' $null
Check 'd5_build_mono_resolves' ($mono.code -eq 0 -and $mono.resolved.Length -gt 0) ("exit={0}; {1}" -f $mono.code, $mono.resolved)

Check 'd5_resolution_names_its_source' (($local.resolved.Contains('(from')) -and ($mono.resolved.Contains('(from'))) `
    ("build_local: {0} || build_mono: {1}" -f $local.resolved, $mono.resolved)

# Explicit override wins, and a *bad* override falls through with the source
# printed -- which is how a typo becomes visible instead of silent.
$override = Invoke-Probe $BuildLocal 'build_local_override' @{ SCONS = 'C:\definitely\not\here\scons.exe' }
Check 'd5_bad_override_falls_through_visibly' ($override.code -eq 0 -and (-not $override.resolved.Contains('definitely'))) `
    ("exit={0}; SCONS pointed at a nonexistent path, the probe resolved {1}" -f $override.code, $override.resolved)

# The genuinely blocked case: no %SCONS%, no `scons` on PATH, known path disabled.
$blocked = Invoke-Probe $BuildLocal 'build_local_blocked' @{
    SCONS = 'Z:\nope\scons.exe'
    SCONS_NO_KNOWN_PATH = '1'
    PATH = (Join-Path $env:SystemRoot 'System32')
}
Check 'd5_scrap_the_path_reports_readably' ($blocked.code -eq 3 -and $blocked.fatal.Length -gt 0) `
    ("exit={0}; first line: {1}" -f $blocked.code, $blocked.fatal)
Check 'd5_error_names_all_three_candidates' ($blocked.text.Contains('the SCONS environment variable') -and $blocked.text.Contains('scons` on PATH') -and $blocked.text.Contains('D:\Anaconda\Scripts\scons.exe')) `
    'the message lists the three sources it tried and the two ways to fix it'
Check 'd5_error_suggests_the_probe' ($blocked.text.Contains('--probe-only')) 'the message tells the reader how to inspect the probe without building'

# `probe-only` must really not build: the run must be fast and must not touch
# the object tree. A cheap, honest proxy: the log says so, and no build log line
# was appended.
$before = ''
$after = ''
$buildLog = Join-Path $env:TEMP 'mcp_server_build_local.log'
if (Test-Path $buildLog) { $before = (Get-FileHash -Algorithm SHA256 -Path $buildLog).Hash }
$null = Invoke-Probe $BuildLocal 'build_local_probe_again' $null
if (Test-Path $buildLog) { $after = (Get-FileHash -Algorithm SHA256 -Path $buildLog).Hash }
Check 'd5_probe_only_does_not_build' (($before -eq $after) -and $local.text.Contains('probe-only')) `
    ("build log sha before={0} after={1}; the probe prints probe-only and exits" -f $before, $after)

# The absolute path survives only as the third candidate; no invocation of it
# without %SCONS_BIN% remains.
$monoText = [IO.File]::ReadAllText($BuildMono)
$localText = [IO.File]::ReadAllText($BuildLocal)
$hardcodedMono = $monoText.Contains('D:\Anaconda\Scripts\scons.exe platform=windows')
$hardcodedLocal = $localText.Contains('D:\Anaconda\Scripts\scons.exe platform=windows')
Check 'd5_no_hardcoded_invocation_left' ((-not $hardcodedMono) -and (-not $hardcodedLocal)) `
    ("mcp057_build_mono.cmd invokes the absolute path directly: {0}; build_local.cmd: {1}" -f $hardcodedMono, $hardcodedLocal)

Write-Host ''
Write-Host '--- summary ---'
Write-Host ('--- demo failures: {0} ---' -f $script:Failures)
Write-Host ('--- output root: {0} ---' -f $OutRoot)
if ($script:Failures -gt 0) { Write-Host ('D5 SCONS PROBE DEMO FAILED: {0}' -f $script:Failures); exit 1 }
Write-Host 'D5 SCONS PROBE DEMO PASS'
exit 0
