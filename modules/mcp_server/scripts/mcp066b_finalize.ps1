# =============================================================================
#  mcp066b_finalize.ps1 -- TASK-066 role B: collect the scratch products into the
#  repository evidence tree, audit uniqueness, write the manifest and the
#  closing discipline checks. Pure ASCII.
#
#  Reads: %TEMP%\mcp066b\** and the evidence tree under
#  docs\reports\evidence\task066b\ . Writes ONLY under that evidence tree.
# =============================================================================

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mcp066b_env.ps1')

$DirShots = Join-Path $EvidenceRoot 'shots'
$DirCaptured = Join-Path $EvidenceRoot 'captured-shots'
$DirLogs = Join-Path $EvidenceRoot 'process-logs'
$DirTraces = Join-Path $EvidenceRoot 'traces'

function Get-ListeningPorts2 {
    $rows = @(netstat -ano | Select-String -Pattern 'LISTENING')
    $ports = @()
    foreach ($row in $rows) {
        $line = [string]$row.Line
        if ($line -match ':(\d+)\s') { $ports += [int]$Matches[1] }
    }
    return @($ports | Sort-Object -Unique)
}

$results = New-Object System.Collections.ArrayList
function Add-Row([string]$Id, [bool]$Pass, [string]$Detail) {
    [void]$results.Add([pscustomobject]@{ id = $Id; pass = [bool]$Pass; detail = [string]$Detail })
    $tag = 'FAIL'
    if ($Pass) { $tag = 'PASS' }
    Write-Host ('[{0}] {1} :: {2}' -f $tag, $Id, $Detail)
}

# ---------------------------------------------------------------------------
#  1. every PNG the capture rows of this run produced, copied per session
# ---------------------------------------------------------------------------
$sessionShots = @(
    @{ name = 'editor-a'; dir = (Join-Path $Proj 'mcp066b_shots') },
    @{ name = 'editor-b'; dir = (Join-Path $Proj 'mcp066b_shots_b') },
    @{ name = 'editor-c'; dir = (Join-Path $Proj 'mcp066b_shots_c') },
    @{ name = 'editor-d'; dir = (Join-Path $Proj 'mcp066b_shots_d') },
    @{ name = 'game'; dir = (Join-Path $Proj 'mcp066b_game_shots') }
)
$copied = 0
$copiedBytes = 0
# The engine names its own captures 0001_before.png, 0002_after.png ... which
# repeat in every session. They are therefore re-emitted through
# mcp_evidence_guard.ps1's writer, so each collected file's name carries its
# session, its sequence and its own content digest
# (<session>__<original-stem>__<seq>__<sha8>.png) - the same rule the rest of
# this evidence tree follows. The directory is rebuilt from scratch each run
# because it is a derived copy of scratch.
if (Test-Path -LiteralPath $DirCaptured) { Remove-Item -LiteralPath $DirCaptured -Recurse -Force }
foreach ($s in $sessionShots) {
    if (Test-Path -LiteralPath $s.dir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $s.dir -File -Filter '*.png' | Sort-Object Name)) {
            $stem = [IO.Path]::GetFileNameWithoutExtension($f.Name)
            $written = Write-McpEvidenceBytes -Directory $DirCaptured -Leaf ($s.name + '__' + $stem) -Bytes ([IO.File]::ReadAllBytes($f.FullName)) -Extension '.png'
            $copied++
            $copiedBytes += $written.Bytes
        }
    }
}
Add-Row 'f1_captured_shots_collected' ($copied -gt 0) ('pngs=' + $copied + ' bytes=' + $copiedBytes + ' sessions=' + (@($sessionShots | Where-Object { Test-Path -LiteralPath $_.dir }).Count) + '/5')

# ---------------------------------------------------------------------------
#  2. process logs and traces from scratch
# ---------------------------------------------------------------------------
Ensure-Dir $DirLogs | Out-Null
foreach ($name in @('editor-a.out.log.txt', 'editor-a.err.log.txt', 'editor-b.out.log.txt', 'editor-b.err.log.txt', 'editor-c.out.log.txt', 'editor-c.err.log.txt', 'editor-d.out.log.txt', 'editor-d.err.log.txt', 'game.out.log.txt', 'game.err.log.txt')) {
    $src = Join-Path $DirLogs $name
    # logs were written straight into the evidence tree; nothing to copy
    if (-not (Test-Path -LiteralPath $src)) { Add-Heartbeat ('finalize: missing log ' + $name) }
}
$logCount = @(Get-ChildItem -LiteralPath $DirLogs -File).Count
Add-Row 'f2_process_logs_present' ($logCount -ge 8) ('files=' + $logCount)

# ---------------------------------------------------------------------------
#  3. uniqueness audit
# ---------------------------------------------------------------------------
$audit = Assert-McpEvidenceTreeUniqueness -Directory $EvidenceRoot
Add-Row 'f3_evidence_tree_has_no_name_collisions' (@($audit.Collisions).Count -eq 0) ('files=' + $audit.Files + ' collisions=' + @($audit.Collisions).Count + ' duplicate_names=' + @($audit.Duplicates).Count)

# ---------------------------------------------------------------------------
#  4. manifest
# ---------------------------------------------------------------------------
$manifestLines = New-Object System.Collections.ArrayList
foreach ($file in @(Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -File | Sort-Object FullName)) {
    if ($file.Name -eq 'evidence-manifest.txt') { continue }
    $rel = $file.FullName.Substring($EvidenceRoot.Length + 1)
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLower()
    [void]$manifestLines.Add(('{0}  {1}  {2}' -f $hash, $file.Length, $rel))
}
$manifestPath = Join-Path $EvidenceRoot 'evidence-manifest.txt'
[IO.File]::WriteAllText($manifestPath, (($manifestLines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
Add-Row 'f4_evidence_manifest_written' ($manifestLines.Count -gt 50) ('rows=' + $manifestLines.Count + ' manifest_sha256=' + (Get-Sha256OfFile $manifestPath))

# ---------------------------------------------------------------------------
#  5. closing discipline
# ---------------------------------------------------------------------------
$contractSha = Get-Sha256OfFile (Join-Path $McpRoot 'docs\tools_list.renamed.json')
Add-Row 'f5_contract_sha_unchanged' ($contractSha -eq 'd4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd') ('sha256=' + $contractSha)

$diffModules = @(& git -C $RepoRoot status --porcelain modules/mcp_server/tools modules/mcp_server/tests modules/mcp_server/docs/tools_list.renamed.json modules/mcp_server/docs/tool-rename-map.json modules/mcp_server/docs/tool-groups.json modules/mcp_server/docs/tool-groups-added.json)
Add-Row 'f6_module_implementation_and_contract_untouched' (@($diffModules | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) ('porcelain entries=' + @($diffModules).Count)

$ports = Get-ListeningPorts2
Add-Row 'f7_9877_untouched_and_9888_9889_released' ((-not ($ports -contains 9877)) -and (-not ($ports -contains 9888)) -and (-not ($ports -contains 9889))) ('listening=' + ($ports -join ','))

$watcherAlive = @(Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID })
Add-Heartbeat ('finalize: powershell processes other than this one=' + $watcherAlive.Count + ' (the watcher must have exited itself on the marker)')

$watchSummary = Join-Path $EvidenceRoot 'watch\watch-summary.json.txt'
$watchOk = $false
$watchDetail = 'missing'
if (Test-Path -LiteralPath $watchSummary) {
    $ws = Get-Content -LiteralPath $watchSummary -Raw | ConvertFrom-Json
    $watchOk = ([string]$ws.stop_reason -eq 'marker') -and [bool]$ws.activity_seen -and ([int]$ws.trace_lines -gt 0)
    $watchDetail = 'stop_reason=' + $ws.stop_reason + ' activity_seen=' + $ws.activity_seen + ' trace_lines=' + $ws.trace_lines + ' trace_files=' + $ws.trace_files
}
Add-Row 'f8_watch_stop_reason_is_marker' $watchOk $watchDetail

$final = [pscustomobject]@{
    script = 'mcp066b_finalize.ps1'
    evidence_root = $EvidenceRoot
    captured_pngs = $copied
    captured_bytes = $copiedBytes
    manifest_rows = $manifestLines.Count
    manifest_sha256 = (Get-Sha256OfFile $manifestPath)
    audit_files = $audit.Files
    audit_collisions = @($audit.Collisions).Count
    audit_duplicate_names = @($audit.Duplicates).Count
    contract_sha256 = $contractSha
    results = $results
    passed = @($results | Where-Object { $_.pass }).Count
    failed = @($results | Where-Object { -not $_.pass }).Count
}
$finalPath = Join-Path $EvidenceRoot 'finalize-summary.json'
[IO.File]::WriteAllText($finalPath, (($final | ConvertTo-Json -Depth 15).Replace("`r`n", "`n")), (New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host ('B066 FINALIZE passed=' + $final.passed + ' failed=' + $final.failed + ' summary=' + $finalPath)
