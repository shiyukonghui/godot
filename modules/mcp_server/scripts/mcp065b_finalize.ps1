# =============================================================================
#  mcp065b_finalize.ps1 -- TASK-065 section B: pull the out-of-repo scratch
#  artefacts in, then publish a manifest and the numbers the report cites.
#
#  Nothing here changes the implementation, the contract or the harness: it only
#  copies %TEMP% scratch files to absolute paths under docs\reports\evidence\
#  task065b and hashes what is there. Re-runnable: identical bytes are reported
#  as SAME, different bytes are refused with both digests named.
# =============================================================================

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mcp065b_env.ps1')

$Root = $EvidenceRoot
$traceDir = Ensure-Dir (Join-Path $Root 'traces')

$copies = @(
    @{ src = $EditorTrace; dst = (Join-Path $traceDir 'trace-editor.jsonl') },
    @{ src = $GameTrace; dst = (Join-Path $traceDir 'trace-game.jsonl') },
    @{ src = $ProgressFile; dst = (Join-Path $traceDir 'PROGRESS.md.txt') },
    @{ src = (Join-Path $env:TEMP 'mcp065b\run-console.log'); dst = (Join-Path $Root 'process-logs\run-console.log.txt') },
    @{ src = (Join-Path $WatchOutDir 'watch.log'); dst = (Join-Path $Root 'watch\watch.log.txt') },
    @{ src = (Join-Path $WatchOutDir 'watch-summary.json'); dst = (Join-Path $Root 'watch\watch-summary.json.txt') },
    @{ src = (Join-Path $WatchOutDir 'watch-summary.txt'); dst = (Join-Path $Root 'watch\watch-summary.txt') }
)

foreach ($pair in $copies) {
    if (-not (Test-Path -LiteralPath $pair.src)) {
        Write-Host ('MISSING ' + $pair.src)
        continue
    }
    $bytes = [IO.File]::ReadAllBytes($pair.src)
    $newHash = (Get-McpEvidenceContentSha256 -Bytes $bytes)
    $note = 'COPIED'
    if (Test-Path -LiteralPath $pair.dst) {
        $oldHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $pair.dst).Hash.ToLower()
        if ($oldHash -eq $newHash) {
            $note = 'SAME'
        } else {
            throw ('refusing to overwrite a different artefact: {0} on disk={1} scratch={2}' -f $pair.dst, $oldHash, $newHash)
        }
    }
    if ($note -eq 'COPIED') {
        [IO.File]::WriteAllBytes($pair.dst, $bytes)
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $pair.dst).Hash.ToLower() -ne $newHash) {
            throw ('copy did not reproduce the bytes: ' + $pair.dst)
        }
    }
    Write-Host ('{0} {1} sha256={2}' -f $note, $pair.dst, $newHash)
}

# ---------------------------------------------------------------- manifest ----
# The manifest does NOT list itself: a file cannot carry its own digest, and a
# row that described the previous run's manifest would be a permanently stale
# hash inside an otherwise reproducible list.
$manifestTxt = Join-Path $Root 'evidence-manifest.txt'
$rows = @()
foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName)) {
    if ($f.FullName -eq $manifestTxt) { continue }
    $rows += ('{0}  {1}  {2}' -f (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLower(), $f.Length, ($f.FullName.Substring($Root.Length + 1)))
}
[IO.File]::WriteAllText($manifestTxt, (($rows -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
$manifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestTxt).Hash.ToLower()
Write-Host ('MANIFEST rows=' + $rows.Count + ' (excluding the manifest itself) sha256=' + $manifestHash)

$audit = Assert-McpEvidenceTreeUniqueness -Directory $Root
Write-Host ('UNIQUENESS files=' + $audit.Files + ' collisions=' + @($audit.Collisions).Count + ' duplicate_names=' + @($audit.Duplicates).Count)

# ------------------------------------------------------- cited numbers ----
$summary = ([IO.File]::ReadAllText((Join-Path $Root 'run-summary.json')) | ConvertFrom-Json)
$p5 = ([IO.File]::ReadAllText((Join-Path $Root 'phase5_scope.json')) | ConvertFrom-Json)
$p6 = ([IO.File]::ReadAllText((Join-Path $Root 'phase6_capture.json')) | ConvertFrom-Json)
$gp = ([IO.File]::ReadAllText((Join-Path $Root 'game_live_chain.json')) | ConvertFrom-Json)

Write-Host '--- run ---'
Write-Host ('checks_passed=' + $summary.checks_passed + ' checks_failed=' + $summary.checks_failed + ' stop_reason=' + $summary.stop_reason)
Write-Host '--- criterion 5 ---'
Write-Host ('sizes: default=' + $p5.sizes.default_count + '/' + $p5.sizes.default_response_bytes + 'B user=' + $p5.sizes.user_count + '/' + $p5.sizes.user_response_bytes + 'B internal=' + $p5.sizes.internal_count + '/' + $p5.sizes.internal_response_bytes + 'B')
Write-Host ('connections array bytes: default=' + $p5.sizes.default_connections_json_bytes + ' user=' + $p5.sizes.user_connections_json_bytes + ' internal=' + $p5.sizes.internal_connections_json_bytes)
Write-Host ('body sha256 default=' + $p5.default_body_sha256)
Write-Host ('body sha256 user=' + $p5.user_body_sha256)
Write-Host ('body sha256 internal=' + $p5.internal_body_sha256)
Write-Host ('body sha256 scope=all explicit=' + $p5.scope_all_explicit_body_sha256)
Write-Host ('default_minus_user=' + @($p5.default_set_minus_user).Count + ' default_minus_internal=' + @($p5.default_set_minus_internal).Count + ' user_minus_default=' + @($p5.user_set_minus_default).Count)
Write-Host ('user set: ' + (($p5.user_set) -join ' ; '))
Write-Host '--- criterion 6 ---'
Write-Host ('real change: changed=' + $p6.real_change_capture.changed + ' pixels=' + $p6.real_change_capture.changed_pixels + '/' + $p6.real_change_capture.total_pixels + ' ratio=' + $p6.real_change_capture.changed_pixel_ratio + ' before=' + $p6.real_change_capture.before + ' after=' + $p6.real_change_capture.after)
Write-Host ('replay: changed=' + $p6.replay_capture.changed + ' pixels=' + $p6.replay_capture.changed_pixels + ' ratio=' + $p6.replay_capture.changed_pixel_ratio + ' before=' + $p6.replay_capture.before + ' after=' + $p6.replay_capture.after)
Write-Host ('tool route real: ' + $p6.tool_route_real_change.changed_pixels + '/' + $p6.tool_route_real_change.total_pixels + ' identical=' + $p6.tool_route_real_change.identical + ' response_sha256=' + $p6.tool_route_real_change.response_sha256)
Write-Host ('tool route replay: ' + $p6.tool_route_replay.changed_pixels + '/' + $p6.tool_route_replay.total_pixels + ' identical=' + $p6.tool_route_replay.identical + ' response_sha256=' + $p6.tool_route_replay.response_sha256)
Write-Host ('snapshot pair: before=' + $p6.snapshot_pair.before_sha256.Substring(0, 16) + ' after=' + $p6.snapshot_pair.after_sha256.Substring(0, 16))
Write-Host ('three routes agree=' + $p6.pixel_recompute.all_three_routes_agree)
Write-Host '--- game ---'
Write-Host ('paddle x ' + $gp.paddle_before.properties.position.x + ' -> ' + $gp.paddle_after.properties.position.x + ' moves=' + $gp.paddle_after.properties.moves + ' samples=' + @($gp.paddle_samples.samples).Count)
Write-Host ('bricks ' + $gp.bricks_before.count + ' -> ' + $gp.bricks_after.count + ' score [' + $gp.score_before + '] -> [' + $gp.score_after + ']')
Write-Host ('ball y first/last ' + $gp.ball_samples.samples[0].position.y + ' -> ' + $gp.ball_samples.samples[-1].position.y + ' samples=' + @($gp.ball_samples.samples).Count)
Write-Host '--- anchors ---'
foreach ($p in @(
        'modules/mcp_server/tools', 'modules/mcp_server/tests',
        'modules/mcp_server/docs/tools_list.renamed.json', 'modules/mcp_server/docs/tool-rename-map.json',
        'modules/mcp_server/docs/tool-groups.json', 'modules/mcp_server/docs/tool-groups-added.json')) {
    $out = @(& git -C $RepoRoot diff --stat -- $p)
    Write-Host ('git diff --stat -- ' + $p + ' -> ' + @($out).Count + ' line(s)')
}
Write-Host ('contract sha256=' + (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $McpRoot 'docs\tools_list.renamed.json')).Hash.ToLower())
Write-Host ('HEAD=' + (@(& git -C $RepoRoot rev-parse HEAD)))
Write-Host 'git status --short:'
foreach ($line in @(& git -C $RepoRoot status --short)) { Write-Host ('  ' + $line) }
exit 0
