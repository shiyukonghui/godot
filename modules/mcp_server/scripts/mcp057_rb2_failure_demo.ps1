# =============================================================================
#  mcp057_rb2_failure_demo.ps1 -- TASK-057 section 2 (R-B2) failure demo.
#
#  The task book does not accept "the assertion exists": it asks for a
#  demonstration that the assertion *fails* when one of the three generator
#  versions drifts. This script edits exactly one of the three places, runs the
#  checker, requires a non-zero exit code, restores the file byte for byte and
#  requires exit 0 again.
#
#  All three directions are demonstrated, because the drift that really happened
#  twice was the manifest-vs-generator one and a future drift could be any of
#  the three:
#
#    A. database  docs/tool-groups-added.json  source.generator_version
#    B. generator scripts/gen_renamed_contract.py  GENERATOR_VERSION
#    C. contract  docs/tools_list.renamed.json  _meta.generator_version
#
#  Every edit goes through [IO.File]::WriteAllBytes with the original bytes held
#  in memory and in %TEMP%, and the restore is verified by sha256 - the working
#  tree must be back to the exact bytes it started with, not merely "parseable".
#
#  Pure ASCII on purpose (Windows PowerShell 5.1 reads a .ps1 with the ANSI code
#  page unless it has a BOM, and a non-ASCII character would be mangled).
#
#  Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp057_rb2_failure_demo.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$DocScripts = Join-Path $RepoRoot 'modules\mcp_server\docs\scripts\check_tool_groups.py'
$AddedJson = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups-added.json'
$GenPy = Join-Path $RepoRoot 'modules\mcp_server\scripts\gen_renamed_contract.py'
$ContractJson = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogRoot = Join-Path $env:TEMP ('mcp057\rb2-demo\' + $Stamp)
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$Log = Join-Path $LogRoot 'demo.log'

$script:Failed = 0

function Say([string]$Text) {
    Write-Host $Text
    Add-Content -Path $Log -Value $Text -Encoding UTF8
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Get-Bytes([string]$Path) {
    return [IO.File]::ReadAllBytes($Path)
}

function Set-Bytes([string]$Path, [byte[]]$Bytes) {
    [IO.File]::WriteAllBytes($Path, $Bytes)
}

# The three "places", each one a byte-exact replacement inside one file.
#
# TASK-059 D-8: the version used to be HARDCODED here as `1.17.0`, which made
# this demonstration fail on the very next version bump - it reported "the
# literal to drift was not found" for all three places and exited 1, i.e. the
# failure demo for the version-consistency assertion was itself the thing that
# broke when the version was made consistent. It is now read from the source of
# truth (`gen_renamed_contract.py`'s GENERATOR_VERSION) at run time, so a bump
# cannot silently disable it. That is the same class of defect as D-2: a check
# that stops checking without saying so.
$GenText = [Text.Encoding]::UTF8.GetString((Get-Bytes $GenPy))
$versionMatch = [regex]::Match($GenText, 'GENERATOR_VERSION\s*=\s*"([^"]+)"')
if (-not $versionMatch.Success) {
    Say ('FATAL: could not read GENERATOR_VERSION out of ' + $GenPy)
    exit 2
}
$CurrentVersion = $versionMatch.Groups[1].Value
$DriftedVersion = '9.9.9'
if ($CurrentVersion -eq $DriftedVersion) {
    Say ('FATAL: the drift target (' + $DriftedVersion + ') equals the current version; pick another')
    exit 2
}
Say ('drift: ' + $CurrentVersion + ' -> ' + $DriftedVersion + ' (read from gen_renamed_contract.py, not hardcoded)')

$Places = @(
    @{
        id = 'A_added_manifest'
        path = $AddedJson
        from = '"generator_version": "' + $CurrentVersion + '"'
        to = '"generator_version": "' + $DriftedVersion + '"'
        note = 'docs/tool-groups-added.json source.generator_version'
    },
    @{
        id = 'B_generator_constant'
        path = $GenPy
        from = 'GENERATOR_VERSION = "' + $CurrentVersion + '"'
        to = 'GENERATOR_VERSION = "' + $DriftedVersion + '"'
        note = 'scripts/gen_renamed_contract.py GENERATOR_VERSION'
    },
    @{
        id = 'C_contract_meta'
        path = $ContractJson
        from = '"generator_version": "' + $CurrentVersion + '"'
        to = '"generator_version": "' + $DriftedVersion + '"'
        note = 'docs/tools_list.renamed.json _meta.generator_version'
    }
)

function Invoke-Checker([string]$Which, [string]$OutFile) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $cmdArgs = @($DocScripts)
        if ($Which -eq '--added') { $cmdArgs += '--added' } else { $cmdArgs += '--generator-version' }
        $output = & python @cmdArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    [IO.File]::WriteAllLines($OutFile, @($output | ForEach-Object { [string]$_ }))
    return $code
}

Say '============================================================='
Say ' TASK-057 R-B2 failure demo: one version drifts -> exit != 0'
Say (' repo      : ' + $RepoRoot)
Say (' git HEAD  : ' + ((& git -C $RepoRoot rev-parse HEAD) -join ''))
Say (' log       : ' + $Log)
Say '============================================================='

# Baseline: with a clean tree the assertion must be green on both entry points.
$baselineHashes = @{}
foreach ($p in @($AddedJson, $GenPy, $ContractJson)) {
    $baselineHashes[$p] = Get-Sha256 $p
}
$code = Invoke-Checker '--generator-version' (Join-Path $LogRoot 'baseline_generator_version.log')
Say ('BASELINE --generator-version exit=' + $code)
if ($code -ne 0) { Say 'FAIL baseline --generator-version must be exit 0'; $script:Failed++ }
$code = Invoke-Checker '--added' (Join-Path $LogRoot 'baseline_added.log')
Say ('BASELINE --added              exit=' + $code)
if ($code -ne 0) { Say 'FAIL baseline --added must be exit 0'; $script:Failed++ }

foreach ($place in $Places) {
    $path = $place.path
    $original = Get-Bytes $path
    $backup = Join-Path $LogRoot (($place.id) + '.original.bin')
    Set-Bytes $backup $original
    $before = Get-Sha256 $path

    $text = [Text.Encoding]::UTF8.GetString($original)
    if (-not $text.Contains($place.from)) {
        Say ('FAIL ' + $place.id + ': the literal to drift was not found in ' + $path)
        Say ('     looked for: ' + $place.from)
        $script:Failed++
        continue
    }
    $mutated = $text.Replace($place.from, $place.to)
    Set-Bytes $path ([Text.Encoding]::UTF8.GetBytes($mutated))
    $drifted = Get-Sha256 $path

    Say ''
    Say ('--- ' + $place.id + ' : ' + $place.note + ' ---')
    Say ('     before sha256 = ' + $before)
    Say ('     drifted sha256= ' + $drifted + '  (' + $CurrentVersion + ' -> ' + $DriftedVersion + ' in one file only)')

    $gvCode = Invoke-Checker '--generator-version' (Join-Path $LogRoot ($place.id + '_generator_version.log'))
    $addedCode = Invoke-Checker '--added' (Join-Path $LogRoot ($place.id + '_added.log'))
    Say ('     --generator-version exit=' + $gvCode + '   --added exit=' + $addedCode)
    $fatalLine = (Get-Content (Join-Path $LogRoot ($place.id + '_generator_version.log')) |
                  Where-Object { $_ -match 'FATAL' } | Select-Object -First 1)
    Say ('     checker says: ' + $fatalLine)

    if ($gvCode -eq 0) { Say ('FAIL ' + $place.id + ': --generator-version returned 0 on a drift'); $script:Failed++ }
    if ($addedCode -eq 0) { Say ('FAIL ' + $place.id + ': --added returned 0 on a drift'); $script:Failed++ }

    # Byte-exact restore.
    $restoredBytes = Get-Bytes $backup
    Set-Bytes $path $restoredBytes
    $after = Get-Sha256 $path
    Say ('     restored sha256= ' + $after)
    if ($after -ne $before) {
        Say ('FAIL ' + $place.id + ': restore is not byte identical'); $script:Failed++
    } else {
        Say '     restore: byte identical PASS'
    }
    $gvCode = Invoke-Checker '--generator-version' (Join-Path $LogRoot ($place.id + '_restored_generator_version.log'))
    Say ('     after restore --generator-version exit=' + $gvCode)
    if ($gvCode -ne 0) { Say ('FAIL ' + $place.id + ': checker still red after restore'); $script:Failed++ }
}

# Final: every file back to its starting bytes and the tree has no new tracked
# modification (the three files are the only ones this script ever touched).
Say ''
Say '--- final state ---'
foreach ($p in @($AddedJson, $GenPy, $ContractJson)) {
    $now = Get-Sha256 $p
    $ok = ($now -eq $baselineHashes[$p])
    Say (('{0} {1} {2}' -f $(if ($ok) { 'SAME' } else { 'DIFF' }), $now, (Split-Path $p -Leaf)))
    if (-not $ok) { $script:Failed++ }
}
$status = (& git -C $RepoRoot status --porcelain) -join ' | '
Say ('git status --porcelain (whole tree): ' + $status)

if ($script:Failed -gt 0) {
    Say ('R-B2 FAILURE DEMO: FAILED checks = ' + $script:Failed)
    exit 1
}
Say 'R-B2 FAILURE DEMO: PASS (three drifts detected, three byte-exact restores, baseline green)'
exit 0
