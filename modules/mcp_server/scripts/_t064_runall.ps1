$ErrorActionPreference = 'Stop'
$out = Join-Path $env:TEMP 't064'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$repo = 'F:\RustProjects\godot-mcp-pro\code\godot'
Set-Location $repo

function Write-Tee {
    param([string]$Path, [scriptblock]$Body)
    & $Body *>&1 | Tee-Object -FilePath $Path
    return $LASTEXITCODE
}

Write-Host '### 1 reverse probe'
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp064_stale_expectation_reverse_probe.ps1 *>&1 | Tee-Object (Join-Path $out 'run_reverse_probe.txt') | Out-Null
Write-Host ("reverse probe exit = {0}" -f $LASTEXITCODE)

Write-Host '### 2 hygiene probe run 1'
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp064_evidence_hygiene_probe.ps1 *>&1 | Tee-Object (Join-Path $out 'run_hygiene_probe_1.txt') | Out-Null
Write-Host ("hygiene run1 exit = {0}" -f $LASTEXITCODE)

Write-Host '### 3 hygiene probe run 2'
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp064_evidence_hygiene_probe.ps1 *>&1 | Tee-Object (Join-Path $out 'run_hygiene_probe_2.txt') | Out-Null
Write-Host ("hygiene run2 exit = {0}" -f $LASTEXITCODE)

Write-Host '### 4 mcp053 contract diff on the real TASK-053 pair'
# The before side is the contract at the TASK-053 starting revision and the after
# side the one that batch produced. The redirect runs under cmd.exe on purpose:
# PowerShell 5.1's `>` re-encodes the stream and prepends a UTF-8 BOM, which
# `json.load` rejects (measured in this session).
$contractRel = 'modules/mcp_server/docs/tools_list.renamed.json'
cmd /c ("git -C `"{0}`" show c1f3385daf:{1} > `"{2}`"" -f $repo, $contractRel, (Join-Path $out 'c_before.json'))
cmd /c ("git -C `"{0}`" show 96c1693d3d:{1} > `"{2}`"" -f $repo, $contractRel, (Join-Path $out 'c_after.json'))
python modules\mcp_server\scripts\mcp053_contract_diff.py (Join-Path $out 'c_before.json') (Join-Path $out 'c_after.json') (Join-Path $out 'mcp053_diff_out.json') *>&1 | Tee-Object (Join-Path $out 'run_mcp053_diff.txt') | Out-Null
Write-Host ("mcp053 diff exit = {0}" -f $LASTEXITCODE)

Write-Host '### 5 mcp059 contract pre/post'
python modules\mcp_server\scripts\mcp059_contract_pre_post.py *>&1 | Tee-Object (Join-Path $out 'run_mcp059_prepost.txt') | Out-Null
Write-Host ("mcp059 prepost exit = {0}" -f $LASTEXITCODE)

Write-Host '### 6 git evidence'
& git diff --stat -- modules/mcp_server/tools tests *>&1 | Tee-Object (Join-Path $out 'git_diff_tools_tests.txt') | Out-Null
Write-Host ("tools/tests diff exit = {0}" -f $LASTEXITCODE)
& git status --porcelain *>&1 | Tee-Object (Join-Path $out 'git_status.txt') | Out-Null
& git diff --stat *>&1 | Tee-Object (Join-Path $out 'git_diff_stat.txt') | Out-Null

Write-Host '### 7 sha256 of the changed and added scripts'
$files = @(
    'modules/mcp_server/scripts/mcp_evidence_guard.ps1',
    'modules/mcp_server/scripts/mcp064_stale_expectation_reverse_probe.ps1',
    'modules/mcp_server/scripts/mcp064_evidence_hygiene_probe.ps1',
    'modules/mcp_server/scripts/mcp052_added_tools_evidence.ps1',
    'modules/mcp_server/scripts/mcp053_added_tools_evidence.ps1',
    'modules/mcp_server/scripts/mcp054_forensics_and_csharp_evidence.ps1',
    'modules/mcp_server/scripts/mcp053_contract_diff.py',
    'modules/mcp_server/scripts/mcp059_contract_pre_post.py'
)
$lines = foreach ($f in $files) {
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash.ToLower()
    ("{0}  {1}" -f $h, $f.Replace('\', '/'))
}
$lines | Tee-Object -FilePath (Join-Path $out 'sha256_changed.txt')

Write-Host '### 8 port guard (9877)'
$conn = Get-NetTCPConnection -LocalPort 9877 -State Listen -ErrorAction SilentlyContinue
if ($null -eq $conn) { Write-Host 'no listener on 9877 (nothing started or stopped by this task)' }
else { Write-Host ("9877 listener pid(s): {0}" -f (($conn | ForEach-Object { $_.OwningProcess }) -join ', ')) }
Write-Host 'DONE'
