# =============================================================================
#  mcp075_red_phase.ps1 -- TASK-075's red phase, replayed for the record.
#
#  WHY A REPLAY
#  ------------
#  The fix and its tests are committed together, so "this test was ever red" is
#  not visible in the history. The claim this script makes is stronger than the
#  claim a single recorded run can make, and it is the claim the repository's
#  discipline asks for (`scripts/mcp073_gate3_double_red_phase.ps1` set the
#  pattern): the PRE-FIX bytes of the implementation are written back over the
#  fixed ones, the SAME test binary is rebuilt from the SAME new test file, and
#  the two TASK-075 cases must FAIL; then the fixed bytes are restored (verified
#  against `HEAD` byte for byte), rebuilt, and the cases must PASS.
#
#  Files reverted for the red run (all four exist at the base commit):
#    modules/mcp_server/tools/editor_set_node_script_batch.h
#    modules/mcp_server/tools/editor_set_node_script_batch.cpp
#    modules/mcp_server/tools/editor_script_write.cpp
#    modules/mcp_server/tools/registration.cpp
#
#  Everything else stays as it is - including the new `tools/project_text_read.*`
#  and the new test file - so the red run compiles and the failures are real
#  test failures, not compile errors.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp075_red_phase.ps1 [-Base bf9518c2b3]
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$Base = 'bf9518c2b3',
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$ModuleRoot = Join-Path $RepoRoot 'modules\mcp_server'
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$BuildLog = Join-Path $env:TEMP 'mcp075_red_phase_build.log'

if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $OutRoot = Join-Path $ModuleRoot 'docs\reports\evidence\task075\red_phase'
}
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$reverted = @(
    'modules/mcp_server/tools/editor_set_node_script_batch.h',
    'modules/mcp_server/tools/editor_set_node_script_batch.cpp',
    'modules/mcp_server/tools/editor_script_write.cpp',
    'modules/mcp_server/tools/registration.cpp'
)

$checks = New-Object System.Collections.Generic.List[object]
function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    Write-Host ("[{0}] {1} :: {2}" -f $(if ($Pass) { 'PASS' } else { 'FAIL' }), $Id, $Evidence)
}
function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}

function Invoke-Build {
    param([string]$LogPath)
    if (Test-Path $LogPath) { Remove-Item -Force $LogPath }
    $env:MCP_BUILD_LOG = $LogPath
    $out = & (Join-Path $PSScriptRoot 'build_local.cmd') '-Force' 2>&1
    $code = $LASTEXITCODE
    $out | Write-Host
    return $code
}

function Invoke-Task075Cases {
    param([string]$OutPath)
    if (Test-Path $OutPath) { Remove-Item -Force $OutPath }
    # `cmd /c` redirection is byte level, so the doctest's own bytes are what is
    # recorded (PLAYBOOK section 7.1: never carry an artefact through a PowerShell
    # pipeline).
    & cmd /c ('"{0}" --headless --test --test-case=*TASK-075* > "{1}" 2>&1' -f $Engine, $OutPath)
    $code = $LASTEXITCODE
    $text = [IO.File]::ReadAllText($OutPath)
    return [pscustomobject]@{ Exit = $code; Text = $text }
}

Write-Host ('red phase: base commit = {0}; current HEAD = {1}' -f $Base, (& git -C $RepoRoot rev-parse --short HEAD))

# The fixed bytes, kept aside so the restore is a byte copy and not a git guess.
$backup = Join-Path $env:TEMP ('mcp075_red_phase_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $backup | Out-Null
foreach ($relative in $reverted) {
    $destination = Join-Path $backup ($relative -replace '/', '_')
    Copy-Item -Force -Path (Join-Path $RepoRoot $relative) -Destination $destination
}
$fixedBefore = @{}
foreach ($relative in $reverted) { $fixedBefore[$relative] = Get-Sha256 (Join-Path $RepoRoot $relative) }

try {
    # -----------------------------------------------------------------------
    #  1. the pre-fix bytes
    # -----------------------------------------------------------------------
    $refused = @()
    foreach ($relative in $reverted) {
        # `cmd /c` redirection, so the pre-fix bytes are written back byte for
        # byte: `git show` through a PowerShell pipeline would re-encode the three
        # files that carry non-ASCII text (the repo has been bitten by exactly
        # that; PLAYBOOK section 7.1).
        $target = Join-Path $RepoRoot ($relative -replace '/', '\')
        & cmd /c ('git -C "{0}" show {1}:{2} > "{3}"' -f $RepoRoot, $Base, $relative, $target)
        if ($LASTEXITCODE -ne 0) { $refused += $relative }
    }
    Check 'R001_base_files_written' ($refused.Count -eq 0) ("reverted {0} file(s) to {1}; missing at base: {2}" -f $reverted.Count, $Base, $(if ($refused.Count) { $refused -join ',' } else { '(none)' }))

    $redBuild = Invoke-Build -LogPath (Join-Path $OutRoot 'red_build.log')
    Check 'R002_red_build_ok' ($redBuild -eq 0) ("pre-fix build exit={0}; log={1}" -f $redBuild, (Join-Path $OutRoot 'red_build.log'))
    if ($redBuild -ne 0) { throw 'the pre-fix build failed; the red run cannot be judged' }

    $red = Invoke-Task075Cases -OutPath (Join-Path $OutRoot 'red_test.txt')
    $redFailed = ($red.Text -match 'Status: FAILURE')
    $redTail = ($red.Text -split "`n" | Where-Object { $_ -match 'test cases:|assertions:|Status:' }) -join ' | '
    Check 'R003_the_two_cases_fail_before_the_fix' (($red.Exit -ne 0) -and $redFailed) ("exit={0}; {1}" -f $red.Exit, $redTail)
    Check 'R004_red_run_reports_the_D2_and_read_tool_failures' `
        (($red.Text -match 'readable') -and ($red.Text -match 'project_read_text_file')) `
        ("the red output names the missing `readable` field and the missing read tool: readable={0}, tool={1}" -f ($red.Text -match 'readable'), ($red.Text -match 'project_read_text_file'))

    # -----------------------------------------------------------------------
    #  2. the fixed bytes back, byte for byte
    # -----------------------------------------------------------------------
    foreach ($relative in $reverted) {
        $source = Join-Path $backup ($relative -replace '/', '_')
        Copy-Item -Force -Path $source -Destination (Join-Path $RepoRoot $relative)
    }
    $restored = $true
    foreach ($relative in $reverted) {
        if ((Get-Sha256 (Join-Path $RepoRoot $relative)) -ne $fixedBefore[$relative]) { $restored = $false }
    }
    Check 'R005_fixed_bytes_restored_byte_identical' $restored ("every reverted file is back to its pre-replay sha256 ({0} file(s))" -f $reverted.Count)

    $greenBuild = Invoke-Build -LogPath (Join-Path $OutRoot 'green_build.log')
    Check 'R006_green_build_ok' ($greenBuild -eq 0) ("fixed build exit={0}" -f $greenBuild)
    if ($greenBuild -ne 0) { throw 'the fixed build failed' }

    $green = Invoke-Task075Cases -OutPath (Join-Path $OutRoot 'green_test.txt')
    $greenTail = ($green.Text -split "`n" | Where-Object { $_ -match 'test cases:|assertions:|Status:' }) -join ' | '
    Check 'R007_the_same_cases_pass_after_the_fix' (($green.Exit -eq 0) -and ($green.Text -match 'Status: SUCCESS')) ("exit={0}; {1}" -f $green.Exit, $greenTail)
} finally {
    # A failed run must not leave the pre-fix bytes behind: put the fixed ones
    # back unconditionally and verify.
    foreach ($relative in $reverted) {
        $source = Join-Path $backup ($relative -replace '/', '_')
        if (Test-Path $source) { Copy-Item -Force -Path $source -Destination (Join-Path $RepoRoot $relative) }
    }
}

$failures = @($checks | Where-Object { -not $_.pass }).Count
$summary = Join-Path $OutRoot 'summary.txt'
[IO.File]::WriteAllLines($summary, @($checks | ForEach-Object { ("[{0}] {1} :: {2}" -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence) }))
Write-Host ''
Write-Host ('--- checks: {0}, failures: {1} ---' -f $checks.Count, $failures)
Write-Host ('--- evidence root: {0} ---' -f $OutRoot)
if ($failures -gt 0) { Write-Host ('TASK-075 RED PHASE REPLAY FAILED: {0}' -f $failures); exit 1 }
Write-Host 'TASK-075 RED PHASE REPLAY PASS (pre-fix bytes must fail, fixed bytes must pass, both on the same test file)'
exit 0
