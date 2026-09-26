$ErrorActionPreference = 'Stop'

# TASK-028 D-1: replace every remaining bespoke `Import-Project` implementation
# with the one shared, hardened runner (`mcp_import_guard.ps1`).
$files = @(
    'mcp015_editor_node_write_evidence.ps1',
    'mcp016_node_read_instantiate_evidence.ps1',
    'mcp017_batch_layout_setup_evidence.ps1',
    'mcp018_b3_closure_evidence.ps1',
    'mcp019_b4_evidence.ps1',
    'mcp020_m4_defect_fixes_evidence.ps1',
    'mcp021_remaining_silent_value_surfaces_evidence.ps1',
    'mcp022_unified_narrowing_gate_evidence.ps1',
    'mcp023_narrowing_guardrail_evidence.ps1',
    'mcp024b_ergonomics_batch2_evidence.ps1',
    'mcp025_e3_writeside_evidence.ps1',
    'mcp026_e9_e6_evidence.ps1'
)

foreach ($f in $files) {
    $path = Join-Path $PSScriptRoot $f
    $lines = [IO.File]::ReadAllLines($path)
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq 'function Import-Project {') { $start = $i; break }
    }
    if ($start -lt 0) { Write-Host ('MISS function: ' + $f); continue }
    $end = -1
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq '}') { $end = $i; break }
    }
    if ($end -lt 0) { Write-Host ('MISS end brace: ' + $f); continue }

    $oldBody = ($lines[$start..$end] -join "`n")
    $hasPathParam = ($oldBody -match 'param\(\[string\]\$Path')
    $usesProject = ($oldBody -match '\$Project')

    if ($hasPathParam) {
        $newBody = @(
            'function Import-Project {',
            '    param([string]$Path, [string]$LogName)',
            '    # TASK-028 D-1: the shared, hardened `--import` runner',
            '    # (`scripts\mcp_import_guard.ps1`): exit code checked, bounded retry,',
            '    # and every failure prints the command, the exit code, the project path',
            '    # and the log tail. The bespoke loop this replaces did the first two and',
            '    # only this file knew how to report the third.',
            '    $result = Import-McpProject -Engine $Engine -Path $Path -LogDirectory $LogRoot -Name $LogName',
            '    $script:LastImportAttempts = $result.attempts',
            '    Write-Host (''import {0}: exit 0 on attempt {1}'' -f $Path, $result.attempts)',
            '    return $result.attempts',
            '}'
        )
    } elseif ($usesProject) {
        $newBody = @(
            'function Import-Project {',
            '    # TASK-028 D-1: the shared, hardened `--import` runner',
            '    # (`scripts\mcp_import_guard.ps1`): exit code checked, bounded retry,',
            '    # and every failure prints the command, the exit code, the project path',
            '    # and the log tail.',
            '    $result = Import-McpProject -Engine $Engine -Path $Project -LogDirectory $LogRoot -Name ''import''',
            '    $script:LastImportAttempts = $result.attempts',
            '    Write-Host (''import {0}: exit 0 on attempt {1}'' -f $Project, $result.attempts)',
            '    return $result.attempts',
            '}'
        )
    } else {
        Write-Host ('UNRECOGNISED shape: ' + $f)
        continue
    }

    $before = @()
    if ($start -gt 0) { $before = $lines[0..($start - 1)] }
    $after = @()
    if ($end -lt ($lines.Count - 1)) { $after = $lines[($end + 1)..($lines.Count - 1)] }
    $out = @($before + $newBody + $after)

    # The dot-source of the shared guard, right after this script's `$LogRoot` line
    # (all twelve define one).
    $anchor = -1
    for ($i = 0; $i -lt $out.Count; $i++) {
        if ($out[$i] -match '^\$LogRoot = ') { $anchor = $i; break }
    }
    if ($anchor -lt 0) { Write-Host ('MISS LogRoot anchor: ' + $f); continue }
    $insert = @(
        '',
        '# TASK-028 D-1: the shared scratch-project writer and `--import` runner.',
        ". (Join-Path `$PSScriptRoot 'mcp_import_guard.ps1')"
    )
    $tail = @()
    if ($anchor -lt ($out.Count - 1)) { $tail = $out[($anchor + 1)..($out.Count - 1)] }
    $final = @($out[0..$anchor] + $insert + $tail)

    $text = (($final -join "`r`n") + "`r`n")
    # Syntax check before writing.
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        Write-Host ('SYNTAX ERROR, not written: ' + $f)
        $errors | Select-Object -First 3 | ForEach-Object { Write-Host ('  ' + $_.Message) }
        continue
    }
    [IO.File]::WriteAllBytes($path, (New-Object Text.UTF8Encoding($false)).GetBytes($text))
    Write-Host ('patched: ' + $f)
}
