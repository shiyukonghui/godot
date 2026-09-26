# =============================================================================
#  mcp075_analysis_evidence.ps1 -- TASK-075's two analysis fixes, before/after.
#
#  Two scripts are in scope and neither needs an engine:
#
#   D9  `docs/reports/evidence/task074/observations/obs_digest.py` - the digest
#       whose non-ok counter is built from the EDITOR trace only, which is why the
#       round-5 game-side number could only be read by counting rows by eye.
#       TASK-075 adds a per-port count from `CALLS.jsonl` plus a `raw/**`
#       cross-check and a coverage statement.
#
#   D11 `scripts/analyze_mcp_trace.py` - its `probed_argument_names` signal is
#       structurally empty because the trace writes `args` as a JSON *string* and
#       the analyser tested `isinstance(args, dict)`. TASK-075 reads both
#       spellings, counts what it could not read, and adds `--self-test`.
#
#  Both are shown on the SAME inputs: the frozen round-5 trace and the frozen
#  per-call record of the same session. The pre-fix bytes come from the base
#  commit through `cmd /c` redirection (byte level), never through a pipeline.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp075_analysis_evidence.ps1 [-Base bf9518c2b3]
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
$Trace = Join-Path $ModuleRoot 'docs\reports\evidence\task074\traces\trace-editor.jsonl'
$DigestScript = Join-Path $ModuleRoot 'docs\reports\evidence\task074\observations\obs_digest.py'
$Analyzer = Join-Path $ModuleRoot 'scripts\analyze_mcp_trace.py'
$DigestDir = Join-Path $ModuleRoot 'docs\reports\evidence\task074\observations'

if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $OutRoot = Join-Path $ModuleRoot 'docs\reports\evidence\task075\analysis'
}
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$Temp = Join-Path $env:TEMP 'mcp075_analysis'
New-Item -ItemType Directory -Force -Path $Temp | Out-Null

$checks = New-Object System.Collections.Generic.List[object]
function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    Write-Host ("[{0}] {1} :: {2}" -f $(if ($Pass) { 'PASS' } else { 'FAIL' }), $Id, $Evidence)
}

function Get-BaseFile {
    param([string]$Relative, [string]$Destination)
    & cmd /c ('git -C "{0}" show {1}:{2} > "{3}"' -f $RepoRoot, $Base, $Relative, $Destination)
    if ($LASTEXITCODE -ne 0) { throw ('could not read {0} from {1}' -f $Relative, $Base) }
}

function Invoke-Python {
    param([string]$Script, [string[]]$Arguments, [string]$OutPath)
    if (Test-Path $OutPath) { Remove-Item -Force $OutPath }
    $line = ('python "{0}" {1} > "{2}" 2>&1' -f $Script, ($Arguments -join ' '), $OutPath)
    & cmd /c $line
    return $LASTEXITCODE
}

$prefixAnalyzer = Join-Path $Temp 'analyze_prefix.py'
$prefixDigest = Join-Path $Temp 'obs_digest_prefix.py'
Get-BaseFile -Relative 'modules/mcp_server/scripts/analyze_mcp_trace.py' -Destination $prefixAnalyzer

# The pre-fix digest reads `traces/` beside itself and writes `digest.txt` beside
# itself, so it gets a home of its own: the frozen scripts and the frozen traces,
# nothing else. Its output therefore lands in %TEMP%, and the artefact inside the
# evidence tree is never written by a replay.
$PrefixHome = Join-Path $Temp 'digest_prefix'
Remove-Item -Recurse -Force $PrefixHome -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $PrefixHome 'traces') | Out-Null
Get-BaseFile -Relative 'modules/mcp_server/docs/reports/evidence/task074/observations/obs_digest.py' -Destination (Join-Path $PrefixHome 'obs_digest.py')
$TraceDir = Join-Path $ModuleRoot 'docs\reports\evidence\task074\traces'
foreach ($name in @('trace-editor.jsonl', 'trace-game.jsonl', 'trace-game2.jsonl', 'trace-game3.jsonl', 'trace-game4.jsonl')) {
    Copy-Item -Force -Path (Join-Path $TraceDir $name) -Destination (Join-Path $PrefixHome ('traces\' + $name))
}
$prefixDigest = Join-Path $PrefixHome 'obs_digest.py'

# ---------------------------------------------------------------------------
#  D11: the trace analyser, before and after, on the same frozen trace
# ---------------------------------------------------------------------------
$beforeAnalyzer = Join-Path $OutRoot 'analyze_before_editor.txt'
$afterAnalyzer = Join-Path $OutRoot 'analyze_after_editor.txt'
$null = Invoke-Python -Script $prefixAnalyzer -Arguments @($Trace) -OutPath $beforeAnalyzer
$afterExit = Invoke-Python -Script $Analyzer -Arguments @($Trace) -OutPath $afterAnalyzer
$beforeText = [IO.File]::ReadAllText($beforeAnalyzer)
$afterText = [IO.File]::ReadAllText($afterAnalyzer)

$beforeProbedNone = $beforeText -match 'probed args\s+none'
$afterProbedLines = @([regex]::Matches($afterText, 'probed arg\s+\S+ \(failed x\d+'))
Check 'A001_before_the_signal_is_structurally_empty' $beforeProbedNone `
    ("pre-fix analyser on the frozen trace: 'probed args none' present={0}; sha256={1}" -f $beforeProbedNone, (Get-FileHash -Algorithm SHA256 -Path $beforeAnalyzer).Hash.ToLower())
Check 'A002_after_the_signal_is_found' (($afterExit -eq 0) -and ($afterProbedLines.Count -ge 1)) `
    ("fixed analyser exits {0} and reports {1} probed argument name(s): {2}" -f $afterExit, $afterProbedLines.Count, ($afterProbedLines | ForEach-Object { $_.Value }) -join ', ')

# The repository's own regression assertion, plus the probe that proves it can
# fail: the same file with `call_args` forced to return `None` must exit 1.
$selfTestOut = Join-Path $OutRoot 'analyze_self_test.txt'
$selfTestExit = Invoke-Python -Script $Analyzer -Arguments @('--self-test') -OutPath $selfTestOut
$selfTestText = [IO.File]::ReadAllText($selfTestOut)
Check 'A003_self_test_passes_on_the_fixed_tree' (($selfTestExit -eq 0) -and ($selfTestText -match 'SELF-TEST PASS')) `
    ("--self-test exit={0}; {1}" -f $selfTestExit, ($selfTestText -replace "`r?`n", ' '))

$mutated = Join-Path $Temp 'analyze_mutated.py'
$mutatedText = [IO.File]::ReadAllText($Analyzer).Replace("def call_args(record):`n", "def call_args(record):`n    return None  # TASK-075 probe: the D11 shape, restored`n")
[IO.File]::WriteAllText($mutated, $mutatedText, (New-Object Text.UTF8Encoding($false)))
$mutatedOut = Join-Path $OutRoot 'analyze_self_test_mutated_probe.txt'
$mutatedExit = Invoke-Python -Script $mutated -Arguments @('--self-test') -OutPath $mutatedOut
$mutatedTextOut = [IO.File]::ReadAllText($mutatedOut)
Check 'A004_the_self_test_really_asserts' (($mutatedExit -ne 0) -and ($mutatedTextOut -match 'SELF-TEST FAILED')) `
    ("the D11 mutation makes --self-test exit {0}: {1}" -f $mutatedExit, (($mutatedTextOut -split "`n" | Where-Object { $_ -match 'FAIL' }) -join ' | '))

# ---------------------------------------------------------------------------
#  D9: the round-5 digest, before and after, on the same frozen trace set
# ---------------------------------------------------------------------------
$beforeDigest = Join-Path $OutRoot 'digest_before_task075.txt'
$afterDigest = Join-Path $OutRoot 'digest_after_task075.txt'
# The pre-fix script has no output argument: it writes `digest.txt` next to
# itself. It therefore runs from the %TEMP% copy (so the frozen artefact beside
# the traces is never written by a replay), and the fixed one is given an
# explicit path. The frozen file's sha256 is compared before and after to prove
# neither run touched it.
$frozenDigest = Join-Path $DigestDir 'digest.txt'
$frozenShaBefore = if (Test-Path $frozenDigest) { (Get-FileHash -Algorithm SHA256 -Path $frozenDigest).Hash.ToLower() } else { '<absent>' }
$null = Invoke-Python -Script $prefixDigest -Arguments @() -OutPath (Join-Path $OutRoot 'digest_before_stdout.txt')
$prefixDigestPath = Join-Path $PrefixHome 'digest.txt'
if (-not (Test-Path $prefixDigestPath)) { throw 'the pre-fix digest did not write its digest.txt beside itself' }
Copy-Item -Force -Path $prefixDigestPath -Destination $beforeDigest
& cmd /c ('cd /d "{0}" && python "{1}" "{2}" > "{3}" 2>&1' -f $DigestDir, $DigestScript, $afterDigest, (Join-Path $OutRoot 'digest_after_stdout.txt'))
$afterDigestExit = $LASTEXITCODE
$afterDigestText = [IO.File]::ReadAllText($afterDigest)
$frozenShaAfter = if (Test-Path $frozenDigest) { (Get-FileHash -Algorithm SHA256 -Path $frozenDigest).Hash.ToLower() } else { '<absent>' }

# The pre-fix digest's own game-side rows, for the "2" half of 2 vs 14.
$prefixDigestText = [IO.File]::ReadAllText($beforeDigest)
$prefixGameNonOk = ([regex]::Matches($prefixDigestText, 'seq=\S+\s+\S+\s+ok=False')).Count
$prefixHasPortSection = $prefixDigestText -match 'NON-OK CALLS BY PORT'
$afterGameLine = ([regex]::Match($afterDigestText, 'game \(9889\) non-ok=(\d+)').Groups[1].Value)
$afterEditorLine = ([regex]::Match($afterDigestText, 'editor \(9888\) non-ok=(\d+)').Groups[1].Value)
$afterTotal = ([regex]::Match($afterDigestText, 'non-ok total=(\d+)').Groups[1].Value)
$afterOk = ([regex]::Match($afterDigestText, 'ok=(\d+)\s+non-ok total').Groups[1].Value)
$afterRows = ([regex]::Match($afterDigestText, 'rows=(\d+)').Groups[1].Value)
$afterTraceGame = ([regex]::Match($afterDigestText, 'game:\s+trace=(\d+)\s+CALLS\.jsonl=(\d+)').Groups[1].Value)
$afterTraceEditor = ([regex]::Match($afterDigestText, 'editor:\s+trace=(\d+)\s+CALLS\.jsonl=(\d+)').Groups[1].Value)
$afterCoverage = $afterDigestText -match 'COVERAGE: the traces carry'
$afterCrossCheck = $afterDigestText -match 'raw/\*\* non-ok = 30 ; MATCH'

Check 'D901_before_there_is_no_game_side_count' ((-not $prefixHasPortSection) -and ($prefixGameNonOk -eq 2)) `
    ("pre-fix digest: a per-port section present={0}; game-trace rows with ok=False (the only way to read a game-side number: counted by eye)={1}; sha256 of the frozen digest unchanged by the replay={2}" -f $prefixHasPortSection, $prefixGameNonOk, ($frozenShaBefore -ceq $frozenShaAfter))
Check 'D902_after_the_record_is_counted_per_port' (($afterDigestExit -eq 0) -and ($afterEditorLine -eq '28') -and ($afterGameLine -eq '2') -and ($afterTotal -eq '30') -and ($afterRows -eq '232') -and ($afterOk -eq '202')) `
    ("fixed digest exits {0}: rows={1}, ok={2}, non-ok total={3}, editor (9888)={4}, game (9889)={5}" -f $afterDigestExit, $afterRows, $afterOk, $afterTotal, $afterEditorLine, $afterGameLine)
Check 'D903_coverage_and_cross_check_are_stated' ($afterCoverage -and $afterCrossCheck) `
    ("coverage warning present={0}; CALLS.jsonl total 30 vs raw/** 30 MATCH present={1}; trace-visible editor/game={2}/{3}" -f $afterCoverage, $afterCrossCheck, $afterTraceEditor, $afterTraceGame)
# The round-5 findings' D9 says "the game side really has 14 non-ok calls". The
# frozen record says 2, its own recompute script says 2, and the 2 is exactly what
# the game traces carry. This check is the withdrawal, made on the same file.
Check 'D904_the_round5_fourteen_is_not_reproducible' (($afterGameLine -eq '2') -and ($afterTraceGame -eq '2')) `
    ("the authoritative per-port count for 9889 is {0} and the traces carry {1} of them; the round-5 findings' '14' has no supporting artefact (its own aggregate/c_calls2.stdout.txt line 6 prints 'port 9889 calls 34 ok 32 non-ok 2')" -f $afterGameLine, $afterTraceGame)

$failures = @($checks | Where-Object { -not $_.pass }).Count
$summary = Join-Path $OutRoot 'summary.txt'
[IO.File]::WriteAllLines($summary, @($checks | ForEach-Object { ("[{0}] {1} :: {2}" -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence) }))
Write-Host ''
Write-Host ('--- checks: {0}, failures: {1} ---' -f $checks.Count, $failures)
Write-Host ('--- evidence root: {0} ---' -f $OutRoot)
if ($failures -gt 0) { Write-Host ('MCP075 ANALYSIS EVIDENCE FAILED: {0}' -f $failures); exit 1 }
Write-Host 'MCP075 ANALYSIS EVIDENCE PASS (D9: per-port counting + raw/** cross-check, with the round-5 "14" withdrawn as unreproducible; D11: probed args found and self-tested)'
exit 0