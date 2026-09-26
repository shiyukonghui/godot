$ErrorActionPreference = 'Stop'
$dst = 'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task041'
$tmp = $env:TEMP
New-Item -ItemType Directory -Force -Path ($dst + '\inputmap'), ($dst + '\logs') | Out-Null
Copy-Item ($tmp + '\mcp041-inputmap\evidence\*') ($dst + '\inputmap') -Force
Copy-Item ($tmp + '\mcp041-inputmap\checks.json') ($dst + '\inputmap') -Force
Copy-Item ($tmp + '\mcp041\red-inputmap.log') ($dst + '\logs\doctest-red-behaviour.log') -Force
Copy-Item ($tmp + '\mcp041\green-inputmap.log') ($dst + '\logs\doctest-green-inputmap.log') -Force
Copy-Item ($tmp + '\mcp041\green-task041.log') ($dst + '\logs\doctest-green-task041.log') -Force
Copy-Item ($tmp + '\mcp041\gates\summary.txt') ($dst + '\logs\gate-battery-summary.txt') -Force
$names = @('gate3_module_doctest', 'gate4_full_doctest', 'gate1_contract_subset', 'gate2_wire_evidence', 'gate6a_narrowing', 'gate6b_narrowing_coverage', 'gate6c_coverage_probes')
foreach ($n in $names) {
    Copy-Item ($tmp + '\mcp041\gates\' + $n + '.log') ($dst + '\logs\' + ($n -replace '_', '-') + '.log') -Force
}
$m = Get-ChildItem -Recurse -File $dst | Measure-Object -Property Length -Sum
Write-Host ('files=' + $m.Count + ' bytes=' + $m.Sum)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# TASK-041 evidence index (byte size + sha256)')
$lines.Add('')
foreach ($f in (Get-ChildItem -Recurse -File $dst | Sort-Object FullName)) {
    $rel = $f.FullName.Substring($dst.Length + 1).Replace('\', '/')
    $lines.Add(('| `{0}` | {1} | `{2}` |' -f $rel, $f.Length, (Get-FileHash -Algorithm SHA256 $f.FullName).Hash.ToLower()))
}
Set-Content -Path ($dst + '\INDEX.md') -Value $lines -Encoding UTF8
Write-Host ('index lines=' + $lines.Count)
