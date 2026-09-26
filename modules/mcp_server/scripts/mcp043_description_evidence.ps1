# =============================================================================
#  mcp043_description_evidence.ps1 -- TASK-043 section 1.5 (live verification)
#
#  The contract is generated, but the text a client really reads comes from the
#  C++ registration literal, so "the contract says it" is not evidence that the
#  live `tools/list` says it. This script fetches `tools/list` from a real editor
#  process on 9888 (`curl.exe -s -o <file>`, never a pipeline, PLAYBOOK section
#  7.1), hashes the raw bytes, and pins, for each of the five tools TASK-043
#  appended a sentence to:
#
#    * the live description is byte-equal to the contract entry; and
#    * it satisfies the relation the DECLARED override mode implies - TASK-069
#      section 2.2 replaced the old pinned form ("ends with the appended
#      sentence", false for all five since TASK-059 D-4 switched them to
#      `replace`) with: `append` -> the description must end with the declared
#      sentence; `replace` -> the description must BE the declared text. The
#      declaration is read from `DESCRIPTION_OVERRIDES` in
#      scripts/gen_renamed_contract.py through scripts/mcp069_override_dump.py,
#      and the contract's own `_meta.overrides` mode must agree with it.
#
#  Port discipline: 9877 is only classified through mcp_port_guard.ps1; the
#  editor uses 9888. ASCII only.
# =============================================================================

param(
    [int]$EditorPort = 9888,
    [int]$UserPort = 9877,
    [string]$OutRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp043-live' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$ModuleRoot = Join-Path $RepoRoot 'modules\mcp_server'
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$Contract = Join-Path $ModuleRoot 'docs\tools_list.renamed.json'
$Root = $OutRoot
$Proj = Join-Path $Root 'proj'
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$utf8 = [Text.Encoding]::UTF8

# The sentence TASK-043 appended to those five descriptions. TASK-069 section 2.2
# keeps it here as a CHECKED LITERAL, not as an expectation: TASK-059 D-4 switched
# the five descriptions from `append` to `replace` (the sentence names a fact
# TASK-057 patch 2 disproved), so a replace-mode description must NOT carry it any
# more. The expected relation for each tool is DERIVED from the declaration below.
$Sentence = "When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them."

$Affected = @(
    'project_set_setting',
    'project_add_autoload',
    'project_remove_autoload',
    'editor_add_input_action',
    'editor_reload_plugin'
)

# TASK-069 section 2.2: the old_name each affected description is declared under
# in `DESCRIPTION_OVERRIDES` (the generator's table, keyed by old_name). Without
# this map the script could only pin text; with it the expected relation is read
# out of the declaration.
$AffectedOldName = @{
    'project_set_setting'     = 'set_project_setting'
    'project_add_autoload'    = 'add_autoload'
    'project_remove_autoload' = 'remove_autoload'
    'editor_add_input_action' = 'set_input_action'
    'editor_reload_plugin'    = 'reload_plugin'
}

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Get-Sha {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '<absent>' }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}

function Get-ListenerPid {
    param([int]$Port_)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port_ + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $handle = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $Arguments
    return $handle
}

function Wait-ForPump {
    param([int]$Port_, [int]$Iterations = 240)
    for ($i = 0; $i -lt $Iterations; $i++) {
        Start-Sleep -Milliseconds 1000
        $out = Join-Path $Ev ("status-{0}.json" -f $Port_)
        & $Curl '-s' '--max-time' '5' '-o' $out ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (Test-Path $out) {
            try {
                $probe = ConvertFrom-Json ([IO.File]::ReadAllText($out, $utf8))
                if ($null -ne $probe.frame_count -and [int]$probe.frame_count -ge 20) { return $true }
            } catch { }
        }
    }
    return $false
}

function Stop-Engine {
    param($Handle)
    if ($null -ne $Handle -and -not $Handle.HasExited) {
        Stop-Process -Id $Handle.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null
New-McpScratchProject -Path $Proj -Name 'MCP043 description evidence' -WithMainScene $true | Out-Null

$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'L01_import_ok' ($import.exit_code -eq 0) ("--import exit={0} after {1} attempt(s)" -f $import.exit_code, $import.attempts)

$editorHandle = $null
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'L02_editor_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    # The list request goes to disk through curl itself; the response body is
    # never piped through PowerShell (that once collapsed every non-ASCII byte).
    $bodyFile = Join-Path $Ev 'tools_list.request.json'
    Write-McpUtf8NoBom -Path $bodyFile -Text '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
    $listFile = Join-Path $Ev 'tools_list.response.json'
    if (Test-Path $listFile) { Remove-Item -Force $listFile }
    & $Curl '-s' '--max-time' '60' '-o' $listFile '-H' 'Content-Type: application/json' '--data-binary' ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $EditorPort) | Out-Null
    $listBytes = [IO.File]::ReadAllBytes($listFile)
    $listSha = Get-Sha $listFile
    Write-Host ("[L10] tools/list bytes={0} sha256={1}" -f $listBytes.Length, $listSha)
    Check 'L10_tools_list_fetched' ($listBytes.Length -gt 0) ("bytes={0} sha256={1}" -f $listBytes.Length, $listSha)

    $list = ConvertFrom-Json ([IO.File]::ReadAllText($listFile, $utf8))
    $live = @{}
    foreach ($tool in $list.result.tools) { $live[[string]$tool.name] = [string]$tool.description }
    Check 'L11_tool_count' ($live.Count -gt 0) ("live editor tools/list carries {0} tools" -f $live.Count)

    $contract = ConvertFrom-Json ([IO.File]::ReadAllText($Contract, $utf8))
    $expected = @{}
    foreach ($tool in $contract.result.tools) { $expected[[string]$tool.name] = [string]$tool.description }

    # TASK-069 section 2.2: the declared override table, read from its single
    # source (DESCRIPTION_OVERRIDES in scripts/gen_renamed_contract.py) through
    # scripts/mcp069_override_dump.py. This is what replaces the pinned sentence:
    # the relation each description has to satisfy depends on the mode the
    # declaration carries, not on a copy of the text in this script.
    $overrideDumpPath = Join-Path $Ev 'description_overrides.json'
    & python (Join-Path $PSScriptRoot 'mcp069_override_dump.py') --out $overrideDumpPath --kind description | Out-Null
    $dumpCode = $LASTEXITCODE
    $declared = $null
    if (($dumpCode -eq 0) -and (Test-Path $overrideDumpPath)) {
        $declared = ConvertFrom-Json ([IO.File]::ReadAllText($overrideDumpPath, $utf8))
    }
    Check 'L21a_the_declared_override_table_was_read' (($dumpCode -eq 0) -and ($null -ne $declared)) `
        ("mcp069_override_dump.py exit={0}; generator_version={1} count={2} path={3}" -f $dumpCode, $(if ($null -ne $declared) { $declared.generator_version } else { '<none>' }), $(if ($null -ne $declared) { $declared.count } else { 0 }), $overrideDumpPath)

    # The mode the contract itself records for the same override. The generator
    # table and the contract it generated are two independent declarations, and
    # the check below requires them to agree before it uses either.
    $contractModeByOldName = @{}
    foreach ($override in $contract._meta.overrides) {
        if ([string]$override.kind -ceq 'description') { $contractModeByOldName[[string]$override.old_name] = [string]$override.mode }
    }

    foreach ($name in $Affected) {
        if (-not $live.ContainsKey($name)) {
            Check ("L20_{0}_present" -f $name) $false ("tool '{0}' is not in the live tools/list" -f $name)
            continue
        }
        $shown = $live[$name]
        $is_equal = ($shown -ceq $expected[$name])
        Check ("L20_{0}_live_equals_contract" -f $name) $is_equal `
            ("live description == contract entry: {0}; lengths live={1} contract={2}" -f $is_equal, $shown.Length, $expected[$name].Length)

        $oldName = [string]$AffectedOldName[$name]
        $declaredRecord = $null
        if ($null -ne $declared) { $declaredRecord = $declared.overrides.$oldName }
        if ($null -eq $declaredRecord) {
            Check ("L21_{0}_matches_the_declared_override" -f $name) $false `
                ("the declaration could not be read, or it carries no description override for old_name '{0}' (dump exit={1})" -f $oldName, $dumpCode)
            continue
        }
        $mode = [string]$declaredRecord.mode
        $value = [string]$declaredRecord.value
        $contractMode = [string]$contractModeByOldName[$oldName]
        $modesAgree = ($contractMode -ceq $mode)
        $sentenceGone = (-not $shown.Contains($Sentence))
        if ($mode -ceq 'append') {
            $relation = ($shown.EndsWith($value)) -and ($shown.Length -gt $value.Length)
            $relationText = ("declared mode=append: live ENDS WITH the declared sentence ({0} char(s)); live length {1} > {2}" -f $value.Length, $shown.Length, $value.Length)
        } elseif ($mode -ceq 'replace') {
            $relation = ($shown -ceq $value)
            $relationText = ("declared mode=replace: live description IS the declared text byte for byte ({0} char(s))" -f $value.Length)
        } else {
            $relation = $false
            $relationText = ("declared mode '{0}' is outside the enum" -f $mode)
        }
        Check ("L21_{0}_matches_the_declared_{1}_override" -f $name, $mode) `
            ($relation -and $modesAgree -and (($mode -cne 'replace') -or $sentenceGone)) `
            ("{0}; generator mode == contract _meta.overrides mode: {1} (contract says '{2}'); the disproven TASK-043 sentence is absent from the wire: {3}" -f $relationText, $modesAgree, $contractMode, $sentenceGone)
    }

    # The other 166 tools must not have moved: a hash over every live description
    # that is NOT one of the five, compared with the same hash over the contract.
    $othersLive = @()
    $othersContract = @()
    foreach ($name in ($live.Keys | Sort-Object)) {
        if ($Affected -contains $name) { continue }
        if (-not $expected.ContainsKey($name)) { continue }
        $othersLive += ($name + '=' + $live[$name])
        $othersContract += ($name + '=' + $expected[$name])
    }
    $joined = ($othersLive -join "`n")
    $sha = [BitConverter]::ToString((New-Object Security.Cryptography.SHA256Managed).ComputeHash($utf8.GetBytes($joined))).Replace('-', '').ToLower()
    $joinedExpected = ($othersContract -join "`n")
    $shaExpected = [BitConverter]::ToString((New-Object Security.Cryptography.SHA256Managed).ComputeHash($utf8.GetBytes($joinedExpected))).Replace('-', '').ToLower()
    Check 'L30_no_other_tool_description_moved' (($sha -ceq $shaExpected) -and ($othersLive.Count -gt 100)) `
        ("{0} untouched live descriptions sha256={1}; same set from the contract sha256={2}" -f $othersLive.Count, $sha, $shaExpected)
} finally {
    Stop-Engine -Handle $editorHandle
}

$guard = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'Z01_port_9877_guard' ([bool]$guard.pass) ([string]$guard.evidence)

$failed = @($script:Checks | Where-Object { -not $_.pass })
$summary = [pscustomobject]@{
    script     = 'mcp043_description_evidence.ps1'
    list_sha256 = $listSha
    affected   = $Affected
    checks     = $script:Checks
    failed     = $failed.Count
}
$summaryPath = Join-Path $Ev 'mcp043-description-checks.json'
[IO.File]::WriteAllBytes($summaryPath, (New-Object Text.UTF8Encoding($false)).GetBytes(($summary | ConvertTo-Json -Depth 10)))
Write-Host ("RESULT {0} checks, {1} failed; checks json sha256={2}; tools/list sha256={3}" -f $script:Checks.Count, $failed.Count, (Get-Sha $summaryPath), $listSha)
if ($failed.Count -gt 0) { exit 1 }
exit 0
