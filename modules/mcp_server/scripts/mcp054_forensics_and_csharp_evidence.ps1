# =============================================================================
#  mcp054_forensics_and_csharp_evidence.ps1 -- TASK-054, the live evidence.
#
#  Three blocks, all on real engine processes and real wire requests:
#
#    * the C# honesty fix (D-053-3): the same scratch project's `legit.cs` and
#      `broken.cs` are validated by both tools on a Mono build (9888). With
#      `-Label red` the script asserts the *defect* the task was filed for
#      (`valid:true` for a file with a syntax error); with `-Label green` it
#      asserts the fixed answer (no verdict: the singular tool refuses with
#      -32000, the plural tool classifies `unverifiable`). A plain (non-Mono)
#      build is checked in both runs, where `.cs` must keep answering
#      `language_unavailable` / -32000 (TASK-050, unchanged).
#
#    * the trace generation marker (O-12): the same engine is started three
#      times against one `--mcp-trace` file. `red` expects three `seq == 1`
#      lines and no marker at all; `green` expects one `trace_opened` line per
#      run (pid / role / --mcp-port / --version), no `seq` on it, and the first
#      request of every generation still at `seq == 1`.
#
#    * the analyzer fixes (O-11): the old script (from git HEAD) and the new one
#      are run over the same files and their JSON is compared - the character
#      split unigram, the pseudo-friction excluded by the "no other tool in
#      between" rule, the per-generation segmentation, and the diagnostic
#      bypass (`tools/list`, `event:"capture"`) excluded from the large-response
#      verdict.
#
#  Port discipline: the user's editor on 9877 is never started, killed or
#  restarted - only observed, before and after - and only 9888 / 9889 are used.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp054_forensics_and_csharp_evidence.ps1 -Label green
# =============================================================================

param(
    [ValidateSet('red', 'green')]
    [string]$Label = 'green',
    [string]$MonoEngine = '',
    [string]$PlainEngine = '',
    [int]$EditorPort = 9888,
    [int]$GamePort = 9889,
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($MonoEngine)) { $MonoEngine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe' }
if ([string]::IsNullOrWhiteSpace($PlainEngine)) { $PlainEngine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe' }
$MonoEngine = (Resolve-Path $MonoEngine).Path
$PlainEngine = (Resolve-Path $PlainEngine).Path
$ContractPath = Join-Path $RepoRoot 'modules\mcp_server\docs\tools_list.renamed.json'
$AddedManifest = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups-added.json'
$OldAnalyzer = Join-Path $env:TEMP 'task054\analyze_old.py'
$NewAnalyzer = Join-Path $RepoRoot 'modules\mcp_server\scripts\analyze_mcp_trace.py'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$UserPort = 9877

$Root = Join-Path $env:TEMP ('mcp054-' + $Label)
$Ev = Join-Path $RepoRoot ('modules\mcp_server\docs\reports\evidence\task054\' + $Label)
$LogRoot = Join-Path $Root 'logs'
$Project = Join-Path $Root 'proj054'

. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
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

function New-CallBody {
    param([int]$Id, [string]$Tool, $Arguments)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Read-TextShared {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object IO.StreamReader($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Close() }
    } finally { $stream.Close() }
}

function Invoke-Json {
    param([string]$Id, [string]$Json, [int]$Port_ = 9888, [int]$MaxTimeSec = 300)
    $bodyFile = Join-Path $Ev ("{0}.request.json" -f $Id)
    $respFile = Join-Path $Ev ("{0}.response.json" -f $Id)
    Write-McpUtf8NoBom -Path $bodyFile -Text $Json
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time $MaxTimeSec -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $curlExit = $LASTEXITCODE
    $bytes = @()
    if (Test-Path $respFile) { $bytes = [IO.File]::ReadAllBytes($respFile) }
    $text = ''
    if ($bytes.Count -gt 0) { $text = [Text.Encoding]::UTF8.GetString($bytes) }
    if ($bytes.Count -gt 0) {
        $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    } else {
        $sha = '<empty>'
    }
    Write-Host ("[{0}] port={1} curl_exit={2} bytes={3} sha256={4}" -f $Id, $Port_, $curlExit, $bytes.Count, $sha)
    return $text
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 9888, [int]$MaxTimeSec = 300)
    return (Invoke-Json -Id $Id -Json (New-CallBody -Id 1 -Tool $Tool -Arguments $Arguments) -Port_ $Port_ -MaxTimeSec $MaxTimeSec)
}

function Get-Payload {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.result) { return $null }
        return ConvertFrom-Json ([string]$envelope.result.content[0].text)
    } catch { return $null }
}

function Get-ErrorCode {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return 0 }
        return [int]$envelope.error.code
    } catch { return 0 }
}

function Get-ErrorMessage {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return '' }
        return [string]$envelope.error.message
    } catch { return '' }
}

function Get-Suggestion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return '' }
        if ($null -eq $envelope.error.data) { return '' }
        return [string]$envelope.error.data.suggestion
    } catch { return '' }
}

function Wait-ForEndpoint {
    param([int]$Port_, [int]$TimeoutMs)
    # TASK-054: measured on the TASK-052/053 batteries and fixed here - when the
    # probe file is left over from the previous phase, a *failed* `curl.exe -o`
    # does not rewrite it (curl never opens the output file on a refused
    # connection), so parsing the stale body made this function answer "ready"
    # while the process was still loading. The probe file is therefore removed
    # before every attempt and `curl` has to exit 0 for the body to count.
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Join-Path $Ev 'status.json'
        if (Test-Path $probe) { Remove-Item -Force $probe }
        & $Curl -s --max-time 5 -o $probe ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (($LASTEXITCODE -eq 0) -and (Test-Path $probe)) {
            try {
                $parsed = ConvertFrom-Json (Read-TextShared $probe)
                if ($null -ne $parsed.frame_count) { return $true }
            } catch { }
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

function Start-McpEngine {
    param([string]$Engine, [string]$ProjectPath, [int]$Port_, [string]$Name, [switch]$Editor, [string[]]$ExtraArgs = @())
    $arguments = @('--headless')
    if ($Editor) { $arguments += '-e' }
    $arguments += @('--path', $ProjectPath, ("--mcp-port={0}" -f $Port_))
    $arguments += $ExtraArgs
    $handle = Start-Process -FilePath $Engine -ArgumentList $arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($Name + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($Name + '.err.log')) -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $arguments
    Write-Host ("started {0} pid={1} :: {2}" -f $Name, $handle.Id, ($arguments -join ' '))
    return $handle
}

function Stop-McpEngine {
    param($Handle, [string]$Name)
    if ($null -ne $Handle -and -not $Handle.HasExited) {
        & taskkill /PID $Handle.Id /T /F *> (Join-Path $LogRoot ($Name + '.taskkill.log'))
        Start-Sleep -Milliseconds 1200
    }
}

function Get-ToolEntry {
    param($ListText, [string]$ToolName)
    try {
        $envelope = ConvertFrom-Json $ListText
        foreach ($entry in @($envelope.result.tools)) {
            if ([string]$entry.name -ceq $ToolName) { return $entry }
        }
    } catch { }
    return $null
}

function Get-ItemByPath {
    param($Out, [string]$Path)
    foreach ($item in @($Out.results)) { if ([string]$item.path -ceq $Path) { return $item } }
    return $null
}

function Get-TraceLines {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $text = Read-TextShared $Path
    return @($text -split "`n" | Where-Object { $_.Trim().Length -gt 0 })
}

function Get-JsonLines {
    param([string]$Path)
    $out = @()
    foreach ($line in (Get-TraceLines $Path)) {
        try { $out += (ConvertFrom-Json $line) } catch { }
    }
    return $out
}

function Get-TextSha {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLower()
    } finally { $sha.Dispose() }
}

function Run-Analyzer {
    param([string]$Script, [string]$Trace, [string]$JsonOut, [int]$MaxResultBytes = 0)
    $extra = @()
    if ($MaxResultBytes -gt 0) { $extra = @('--max-result-bytes', [string]$MaxResultBytes) }
    $null = & python $Script $Trace --quiet --json $JsonOut @extra 2>&1
    if (-not (Test-Path $JsonOut)) { return $null }
    return (ConvertFrom-Json (Read-TextShared $JsonOut))
}

# =============================================================================
#  Main
# =============================================================================
Write-Host '============================================================='
Write-Host (' TASK-054 live evidence -- label={0}' -f $Label)
Write-Host '============================================================='

foreach ($pair in @(@('plain', $PlainEngine), @('mono', $MonoEngine))) {
    if (-not (Test-Path $pair[1])) { Write-Host ("FATAL: {0} engine not found: {1}" -f $pair[0], $pair[1]); exit 2 }
}
Remove-Item -Recurse -Force $Ev -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

$headSha = ((& git -C $RepoRoot rev-parse --short=9 HEAD) -join '').Trim()
$plainVersion = ((& $PlainEngine --version 2>$null) -join ' ').Trim()
$monoVersion = ((& $MonoEngine --version 2>$null) -join ' ').Trim()
Write-Host ("plain --version='{0}' mono --version='{1}' git HEAD='{2}'" -f $plainVersion, $monoVersion, $headSha)
Check 'mono_engine_is_the_mono_build' ($monoVersion.Contains('.mono.')) ("mono --version='{0}'" -f $monoVersion)

# --- the contract -----------------------------------------------------------
$contract = ConvertFrom-Json (Read-TextShared $ContractPath)
$contractNames = @($contract.result.tools | ForEach-Object { [string]$_.name })
# TASK-064 D-8: this used to pin the literal `175` (and, below, the literal
# `4` of `_meta.added_count`). Both numbers are a function of a contract that is
# allowed to grow - the contract is `171 ported + _meta.added_count` - so the
# expectation is derived from the contract's own `_meta` and cross-checked
# against the recounting of `docs/tool-groups-added.json`. TASK-063's
# `editor_set_node_property_updates` (175 -> 176, added_count 4 -> 5) turned the
# two pinned literals red with nothing else changed. The literal 171 half stays
# a checked literal on purpose: it is the ported-entry count GDR-17 fixes.
$portedCount = 171
$addedManifestDoc = ConvertFrom-Json (Read-TextShared $AddedManifest)
$addedManifestNames = @()
foreach ($group in @($addedManifestDoc.groups)) { foreach ($tool in @($group.tools)) { $addedManifestNames += [string]$tool } }
Check 'contract_is_ported_plus_added_entries' `
    (($contractNames.Count -eq ($portedCount + @($contract._meta.added_tools).Count)) -and ([int]$contract._meta.count -eq $contractNames.Count)) `
    ("_meta.count={0} contract entries={1} = {2} ported + {3} added (derived; the pinned 175 is gone - TASK-064 D-8)" -f $contract._meta.count, $contractNames.Count, $portedCount, @($contract._meta.added_tools).Count)
if ($Label -eq 'green') {
    # TASK-059 D-8: this branch used to pin the literal `1.17.0`, so it went red
    # on the very next legitimate generator bump (v1.17.0 -> v1.18.0 in TASK-059)
    # although nothing about the tool list had changed. The value is now read from
    # the source of truth, `GENERATOR_VERSION` in `gen_renamed_contract.py`.
    $generatorPy = Join-Path $RepoRoot 'modules\mcp_server\scripts\gen_renamed_contract.py'
    $generatorVersion = ''
    if (Test-Path $generatorPy) {
        $versionMatch = [regex]::Match((Read-TextShared $generatorPy), 'GENERATOR_VERSION\s*=\s*"([^"]+)"')
        if ($versionMatch.Success) { $generatorVersion = $versionMatch.Groups[1].Value }
    }
    Check 'contract_generator_version_matches_the_generator' ((([string]$contract._meta.generator_version) -ceq $generatorVersion) -and ($generatorVersion -ne '')) `
        ("_meta.generator_version={0} GENERATOR_VERSION={1} (read from gen_renamed_contract.py; the pinned literal is gone - TASK-059 D-8)" -f $contract._meta.generator_version, $generatorVersion)
} else {
    Check 'contract_generator_version_is_the_pre_change_1_15_0' ([string]$contract._meta.generator_version -ceq '1.15.0') `
        ("_meta.generator_version={0}" -f $contract._meta.generator_version)
}
Check 'contract_meta_added_tools_is_the_manifest' `
    (((@($contract._meta.added_tools) -join ",") -ceq ($addedManifestNames -join ",")) -and ([int]$contract._meta.added_count -eq $addedManifestNames.Count)) `
    ("_meta.added_count={0} _meta.added_tools=[{1}] manifest=[{2}] (derived from docs/tool-groups-added.json; the pinned count 4 is gone - TASK-064 D-8)" -f $contract._meta.added_count, (@($contract._meta.added_tools) -join ', '), ($addedManifestNames -join ', '))
$contractEntry = @{}
foreach ($entry in @($contract.result.tools)) { $contractEntry[[string]$entry.name] = $entry }

# --- the scratch project ----------------------------------------------------
$userPidBefore = Get-ListenerPid -Port_ $UserPort
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("user editor on {0} before: pid={1}" -f $UserPort, $userPidBefore)
Check 'test_ports_free_before' (((Get-ListenerPid -Port_ $EditorPort) -eq -1) -and ((Get-ListenerPid -Port_ $GamePort) -eq -1)) `
    ("port {0} owner={1}; port {2} owner={3}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort), $GamePort, (Get-ListenerPid -Port_ $GamePort))

New-McpScratchProject -Path $Project -Name 'MCP054' -WithMainScene $true
$scripts = Join-Path $Project 'scripts'
New-Item -ItemType Directory -Force -Path $scripts | Out-Null
Write-McpUtf8NoBom -Path (Join-Path $scripts 'valid.gd') -Text "extends Node`n`nfunc answer() -> int:`n`treturn 42`n"
Write-McpUtf8NoBom -Path (Join-Path $scripts 'broken.gd') -Text "extends Node`n`nfunc broken( -> void:`n`tpass`n"
Write-McpUtf8NoBom -Path (Join-Path $scripts 'legit.cs') -Text "using Godot;`n`npublic partial class Legit : Node`n{`n}`n"
Write-McpUtf8NoBom -Path (Join-Path $scripts 'broken.cs') -Text "using Godot;`n`npublic partial class Broken : Node`n{`n    this is not valid C#`n}`n"

$import = Import-McpProject -Engine $PlainEngine -Path $Project -LogDirectory $LogRoot -Name 'import-base'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine ([string]$import.command)
Check 'scratch_project_imported' ($import.exit_code -eq 0) `
    ("import exit={0} attempts={1}" -f $import.exit_code, $import.attempts)

$plainHandle = $null
$monoHandle = $null
try {
    # =======================================================================
    #  Phase A: the plain (non-Mono) editor on 9888. `.cs` has no backend here,
    #  and that answer must not have moved (TASK-050 N-2).
    # =======================================================================
    $plainHandle = Start-McpEngine -Engine $PlainEngine -ProjectPath $Project -Port_ $EditorPort -Name 'plain-editor' -Editor
    Check 'phase_a_editor_ready' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) ("plain editor answered GET /mcp on {0}" -f $EditorPort)

    $listA = Invoke-Json -Id 'a01_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port_ $EditorPort
    foreach ($name in @('project_validate_script', 'project_validate_scripts')) {
        $live = Get-ToolEntry $listA $name
        $want = $contractEntry[$name]
        $same = ($null -ne $live) -and ([string]$live.description -ceq [string]$want.description)
        Check ("a02_{0}_description_verbatim_on_9888" -f $name) $same `
            ("live sha256={0} contract sha256={1}" -f (Get-TextSha ([string]$live.description)), (Get-TextSha ([string]$want.description)))
    }

    $resp = Invoke-Tool -Id 'a03_plain_singular_legit_cs' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/legit.cs' } -Port_ $EditorPort
    Check 'a03_plain_build_refuses_the_cs_file' `
        (((Get-ErrorCode $resp) -eq -32000) -and ((Get-Suggestion $resp).Contains('module_mono_enabled=yes'))) `
        ("code={0} suggestion='{1}'" -f (Get-ErrorCode $resp), (Get-Suggestion $resp))

    $resp = Invoke-Tool -Id 'a04_plain_singular_broken_cs' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/broken.cs' } -Port_ $EditorPort
    Check 'a04_plain_broken_cs_is_the_same_refusal_not_a_compile_failure' `
        (((Get-ErrorCode $resp) -eq -32000) -and (-not (Get-ErrorMessage $resp).Contains('Compilation failed')) -and (-not (Get-ErrorMessage $resp).Contains('ERR_PARSE_ERROR'))) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp))

    $resp = Invoke-Tool -Id 'a05_plain_plural_mixed' -Tool 'project_validate_scripts' `
        -Arguments @{ paths = @('res://scripts/valid.gd', 'res://scripts/broken.gd', 'res://scripts/legit.cs', 'res://scripts/broken.cs') } -Port_ $EditorPort
    $payload = Get-Payload $resp
    Check 'a05_plain_plural_classifies_the_three_known_categories' `
        (($null -ne $payload) -and ($payload.valid_count -eq 1) -and ($payload.invalid_count -eq 1) -and ($payload.unavailable_count -eq 2) -and ($payload.count -eq 4)) `
        ("valid={0} invalid={1} unavailable={2} count={3}" -f $payload.valid_count, $payload.invalid_count, $payload.unavailable_count, $payload.count)
    $hasFourth = ($null -ne $payload) -and ($null -ne $payload.PSObject.Properties['unverifiable_count'])
    if ($Label -eq 'green') {
        Check 'a05b_green_the_fourth_counter_exists_and_is_zero_in_a_plain_build' ($hasFourth -and ($payload.unverifiable_count -eq 0)) `
            ("unverifiable_count present={0} value={1}" -f $hasFourth, $payload.unverifiable_count)
    } else {
        Check 'a05b_red_the_fourth_counter_does_not_exist_yet' (-not $hasFourth) ("unverifiable_count present={0}" -f $hasFourth)
    }
    $csItem = Get-ItemByPath $payload 'res://scripts/legit.cs'
    Check 'a06_plain_plural_cs_is_language_unavailable' `
        (($null -ne $csItem) -and ([string]$csItem.category -ceq 'language_unavailable') -and (([string]$csItem.suggestion).Contains('module_mono_enabled=yes'))) `
        ("category={0} valid={1}" -f $csItem.category, $csItem.valid)
    $gdOk = Get-ItemByPath $payload 'res://scripts/valid.gd'
    $gdBad = Get-ItemByPath $payload 'res://scripts/broken.gd'
    Check 'a07_the_gd_halves_are_unchanged' `
        (($null -ne $gdOk) -and ([string]$gdOk.category -ceq 'ok') -and ($gdOk.valid -eq $true) -and ($null -ne $gdBad) -and ([string]$gdBad.category -ceq 'invalid') -and ($gdBad.valid -eq $false)) `
        ("valid.gd={0}/{1} broken.gd={2}/{3}" -f $gdOk.category, $gdOk.valid, $gdBad.category, $gdBad.valid)

    $resp = Invoke-Tool -Id 'a08_singular_missing_param' -Tool 'project_validate_script' -Arguments @{ } -Port_ $EditorPort
    Check 'a08_singular_missing_param_is_32602' ((Get-ErrorCode $resp) -eq -32602) ("code={0} message='{1}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp))
    $resp = Invoke-Tool -Id 'a09_singular_missing_file' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/does_not_exist.gd' } -Port_ $EditorPort
    Check 'a09_singular_missing_file_is_32001' ((Get-ErrorCode $resp) -eq -32001) ("code={0} message='{1}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp))
    $resp = Invoke-Tool -Id 'a10_plural_empty_paths' -Tool 'project_validate_scripts' -Arguments @{ paths = @() } -Port_ $EditorPort
    Check 'a10_plural_empty_paths_is_32602' ((Get-ErrorCode $resp) -eq -32602) ("code={0}" -f (Get-ErrorCode $resp))

    Stop-McpEngine -Handle $plainHandle -Name 'plain-editor'
    $plainHandle = $null

    # =======================================================================
    #  Phase M: the Mono editor on 9888 - the block D-053-3 is about.
    # =======================================================================
    $monoHandle = Start-McpEngine -Engine $MonoEngine -ProjectPath $Project -Port_ $EditorPort -Name 'mono-editor' -Editor
    Check 'phase_m_mono_editor_ready' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) ("mono editor answered GET /mcp on {0}" -f $EditorPort)

    $respSingularLegit = Invoke-Tool -Id 'm01_mono_singular_legit_cs' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/legit.cs' } -Port_ $EditorPort
    $respSingularBroken = Invoke-Tool -Id 'm02_mono_singular_broken_cs' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/broken.cs' } -Port_ $EditorPort
    $respPluralBroken = Invoke-Tool -Id 'm03_mono_plural_broken_cs' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/broken.cs') } -Port_ $EditorPort
    $respPluralLegit = Invoke-Tool -Id 'm04_mono_plural_legit_cs' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/legit.cs') } -Port_ $EditorPort
    $respMonoGd = Invoke-Tool -Id 'm05_mono_singular_valid_gd' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/valid.gd' } -Port_ $EditorPort
    $respMonoGdBroken = Invoke-Tool -Id 'm06_mono_singular_broken_gd' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/broken.gd' } -Port_ $EditorPort

    $payloadBroken = Get-Payload $respPluralBroken
    $payloadLegit = Get-Payload $respPluralLegit
    $brokenItem = Get-ItemByPath $payloadBroken 'res://scripts/broken.cs'
    $legitItem = Get-ItemByPath $payloadLegit 'res://scripts/legit.cs'

    if ($Label -eq 'red') {
        # The defect as filed: a `.cs` with a syntax error is answered "compiles
        # successfully" because `CSharpScript::reload()` always returns OK.
        $pb = Get-Payload $respSingularBroken
        Check 'm01_red_broken_cs_is_reported_valid_by_the_singular_tool' `
            (($null -ne $pb) -and ($pb.valid -eq $true)) ("singular broken.cs: valid={0} message='{1}'" -f $pb.valid, $pb.message)
        $pl = Get-Payload $respSingularLegit
        Check 'm02_red_legit_cs_is_also_valid' (($null -ne $pl) -and ($pl.valid -eq $true)) ("singular legit.cs: valid={0}" -f $pl.valid)
        Check 'm03_red_plural_broken_cs_is_category_ok' `
            (($null -ne $brokenItem) -and ([string]$brokenItem.category -ceq 'ok') -and ($brokenItem.valid -eq $true)) `
            ("category={0} valid={1} message='{2}'" -f $brokenItem.category, $brokenItem.valid, $brokenItem.message)
        Check 'm04_red_plural_counters_report_a_valid_file' `
            (($null -ne $payloadBroken) -and ($payloadBroken.valid_count -eq 1) -and ($payloadBroken.invalid_count -eq 0)) `
            ("valid_count={0} invalid_count={1} unavailable_count={2}" -f $payloadBroken.valid_count, $payloadBroken.invalid_count, $payloadBroken.unavailable_count)
    } else {
        # The fixed answer (TASK-055, D112): this scratch project has no
        # `.csproj` and has never been built, so the honest verdict for a `.cs`
        # file is `not_compiled` - never `ok`, and never `invalid`, because the
        # engine has no C# compiler and "nothing built it" must not be published
        # as "it does not compile". The engine basis is now the TASK-055 accessor
        # `CSharpScript::is_source_newer_than_assembly()` plus the public
        # `Script::is_script_valid()`; the language that really compiles keeps
        # its verdict.
        Check 'm01_green_singular_broken_cs_is_a_32000_refusal' `
            (((Get-ErrorCode $respSingularBroken) -eq -32000) -and ((Get-ErrorMessage $respSingularBroken).Contains('not compiled')) -and (-not (Get-ErrorMessage $respSingularBroken).Contains('Compilation failed'))) `
            ("code={0} message='{1}'" -f (Get-ErrorCode $respSingularBroken), (Get-ErrorMessage $respSingularBroken))
        Check 'm02_green_singular_refusal_names_the_engine_basis' `
            (((Get-Suggestion $respSingularBroken).Contains('is_source_newer_than_assembly')) -and ((Get-Suggestion $respSingularBroken).Contains('is_script_valid')) -and ((Get-Suggestion $respSingularBroken).Contains('project_build_csharp'))) `
            ("suggestion='{0}'" -f (Get-Suggestion $respSingularBroken))
        Check 'm03_green_singular_legit_cs_gets_the_same_refusal' `
            ((Get-ErrorCode $respSingularLegit) -eq -32000) ("code={0} message='{1}'" -f (Get-ErrorCode $respSingularLegit), (Get-ErrorMessage $respSingularLegit))

        $hasReason = ($null -ne $brokenItem) -and ($null -ne $brokenItem.PSObject.Properties['reason']) -and ([string]$brokenItem.reason).Contains('is_source_newer_than_assembly')
        Check 'm04_green_plural_broken_cs_is_not_compiled_with_the_engine_reason' `
            (($null -ne $brokenItem) -and ([string]$brokenItem.category -ceq 'not_compiled') -and $hasReason) `
            ("category={0} valid={1} reason_has_engine_accessor={2} reason='{3}'" -f $brokenItem.category, $brokenItem.valid, $hasReason, $brokenItem.reason)
        Check 'm05_green_plural_publishes_no_valid_for_the_cs_file' `
            (($null -ne $brokenItem) -and ($null -eq $brokenItem.valid)) `
            ("valid={0} (null means no verdict was made)" -f $(if ($null -eq $brokenItem.valid) { 'null' } else { $brokenItem.valid }))
        Check 'm06_green_plural_counts_it_as_not_compiled_not_valid_or_invalid' `
            (($null -ne $payloadBroken) -and ($payloadBroken.valid_count -eq 0) -and ($payloadBroken.invalid_count -eq 0) -and ($payloadBroken.unavailable_count -eq 0) -and ($payloadBroken.unverifiable_count -eq 0) -and ($payloadBroken.not_compiled_count -eq 1) -and ($payloadBroken.count -eq 1)) `
            ("valid={0} invalid={1} unavailable={2} unverifiable={3} not_compiled={4} count={5}" -f $payloadBroken.valid_count, $payloadBroken.invalid_count, $payloadBroken.unavailable_count, $payloadBroken.unverifiable_count, $payloadBroken.not_compiled_count, $payloadBroken.count)
        Check 'm07_green_the_two_tools_publish_the_same_sentences' `
            (((Get-ErrorMessage $respSingularBroken) -ceq [string]$brokenItem.message) -and ((Get-Suggestion $respSingularBroken) -ceq [string]$brokenItem.suggestion)) `
            ("message_equal={0} suggestion_equal={1}" -f ((Get-ErrorMessage $respSingularBroken) -ceq [string]$brokenItem.message), ((Get-Suggestion $respSingularBroken) -ceq [string]$brokenItem.suggestion))
        Check 'm08_green_legit_cs_gets_the_same_not_compiled_shape_as_broken_cs' `
            (($null -ne $legitItem) -and ([string]$legitItem.category -ceq 'not_compiled') -and ($null -eq $legitItem.valid)) `
            ("legit.cs category={0} valid={1}" -f $legitItem.category, $(if ($null -eq $legitItem.valid) { 'null' } else { $legitItem.valid }))

        $gdPayload = Get-Payload $respMonoGd
        Check 'm09_green_a_language_that_compiles_still_gets_a_real_verdict' `
            (($null -ne $gdPayload) -and ($gdPayload.valid -eq $true)) ("valid.gd valid={0}" -f $gdPayload.valid)
        $gdB = Get-Payload $respMonoGdBroken
        Check 'm10_green_a_gd_compile_error_is_still_invalid' `
            (($null -ne $gdB) -and ($gdB.valid -eq $false) -and ($gdB.error_text -ne $null)) ("broken.gd valid={0} error_text={1}" -f $gdB.valid, $gdB.error_text)
    }

    Stop-McpEngine -Handle $monoHandle -Name 'mono-editor'
    $monoHandle = $null

    # =======================================================================
    #  Phase T: three runs against one --mcp-trace file (O-12).
    #
    #  Every run issues: a failing tool call, a succeeding call of the same tool
    #  (a real friction episode in runs 1 and 3), and - in run 2 - a *different*
    #  tool call between the failure and the success (the pseudo-friction case
    #  O-11 is about).
    # =======================================================================
    $trace = Join-Path $Root 'trace-generations.jsonl'
    if (Test-Path $trace) { Remove-Item -Force $trace }

    $runPlans = @(
        @(@{ id = 't1_a_fail'; tool = 'project_validate_script'; args = @{ path = 'res://scripts/nope_zzq.gd' } },
          @{ id = 't1_b_ok';   tool = 'project_validate_script'; args = @{ path = 'res://scripts/valid.gd' } },
          @{ id = 't1_c_other'; tool = 'project_get_info'; args = @{ } }),
        @(@{ id = 't2_a_other'; tool = 'project_get_info'; args = @{ } },
          @{ id = 't2_b_fail';  tool = 'project_validate_script'; args = @{ path = 'res://scripts/nope_zzq.gd' } },
          @{ id = 't2_c_other'; tool = 'project_get_info'; args = @{ } },
          @{ id = 't2_d_ok';    tool = 'project_validate_script'; args = @{ path = 'res://scripts/valid.gd' } }),
        @(@{ id = 't3_a_fail'; tool = 'project_validate_script'; args = @{ path = 'res://scripts/nope_zzq.gd' } },
          @{ id = 't3_b_ok';   tool = 'project_validate_script'; args = @{ path = 'res://scripts/valid.gd' } })
    )

    $runPids = @()
    for ($run = 0; $run -lt $runPlans.Count; $run++) {
        $name = ('trace-run-{0}' -f ($run + 1))
        $handle = Start-McpEngine -Engine $MonoEngine -ProjectPath $Project -Port_ $EditorPort -Name $name -Editor -ExtraArgs @(('--mcp-trace=' + $trace))
        $runPids += $handle.Id
        $ready = Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs
        Check (('t{0}_generation_run_ready' -f ($run + 1))) $ready ("run {0} answered GET /mcp (pid={1})" -f ($run + 1), $handle.Id)
        foreach ($step in $runPlans[$run]) {
            $null = Invoke-Tool -Id $step.id -Tool $step.tool -Arguments $step.args -Port_ $EditorPort
        }
        Stop-McpEngine -Handle $handle -Name $name
        Start-Sleep -Milliseconds 500
    }

    $lines = Get-TraceLines $trace
    $parsed = Get-JsonLines $trace
    $markers = @($parsed | Where-Object { $null -ne $_.PSObject.Properties['event'] -and [string]$_.event -ceq 'trace_opened' })
    $requests = @($parsed | Where-Object { $null -ne $_.PSObject.Properties['method'] })
    $seqOnes = @($requests | Where-Object { $_.seq -eq 1 })
    Write-Host ("trace: {0} line(s), {1} trace_opened marker(s), {2} request(s), {3} seq==1" -f $lines.Count, $markers.Count, $requests.Count, $seqOnes.Count)
    $traceSha = if (Test-Path $trace) { (Get-FileHash -Algorithm SHA256 -Path $trace).Hash.ToLower() } else { '<missing>' }
    Check 't_trace_file_written' ($lines.Count -gt 0) ("lines={0} sha256={1}" -f $lines.Count, $traceSha)

    if ($Label -eq 'red') {
        Check 't_red_three_runs_share_one_file_with_three_seq_one' ($seqOnes.Count -eq 3) ("seq==1 count={0}" -f $seqOnes.Count)
        Check 't_red_no_generation_marker_exists' ($markers.Count -eq 0) ("trace_opened count={0}" -f $markers.Count)
    } else {
        Check 't_green_one_generation_marker_per_run' ($markers.Count -eq 3) ("trace_opened count={0}" -f $markers.Count)
        Check 't_green_markers_carry_pid_role_port_and_version' `
            ((@($markers | Where-Object { $_.pid -gt 0 }).Count -eq 3) -and (@($markers | Where-Object { [string]$_.role -ceq 'editor' }).Count -eq 3) -and (@($markers | Where-Object { $_.mcp_port -eq $EditorPort }).Count -eq 3) -and (@($markers | Where-Object { ([string]$_.version).Contains('mono.custom_build') }).Count -eq 3)) `
            ("pids={0}; roles={1}; ports={2}; versions={3}" -f (@($markers | ForEach-Object { $_.pid }) -join ','), (@($markers | ForEach-Object { $_.role }) -join ','), (@($markers | ForEach-Object { $_.mcp_port }) -join ','), (@($markers | ForEach-Object { $_.version }) -join ','))
        Check 't_green_the_marker_holds_no_request_seq' (@($markers | Where-Object { $null -ne $_.PSObject.Properties['seq'] }).Count -eq 0) `
            ("markers with a seq field: {0}" -f (@($markers | Where-Object { $null -ne $_.PSObject.Properties['seq'] }).Count))
        Check 't_green_every_generation_still_starts_at_seq_one' ($seqOnes.Count -eq 3) ("seq==1 count={0}" -f $seqOnes.Count)
        Check 't_green_the_file_has_twelve_lines' ($lines.Count -eq 12) ("{0} request line(s) + {1} marker(s) = {2}" -f $requests.Count, $markers.Count, $lines.Count)
    }

    # =======================================================================
    #  Phase X: the analyzer, old versus new, on the same inputs.
    # =======================================================================
    $auditTrace = Join-Path $env:TEMP 'audit-racing-backlog\ev-editor\trace-game.jsonl'
    $editorTrace = Join-Path $env:TEMP 'mcp-racing-test\trace-editor.jsonl'

    # (1) the segmentation, on the file phase T just wrote
    $oldGen = Run-Analyzer -Script $OldAnalyzer -Trace $trace -JsonOut (Join-Path $Ev 'x01_old_generations.json')
    $newGen = Run-Analyzer -Script $NewAnalyzer -Trace $trace -JsonOut (Join-Path $Ev 'x02_new_generations.json')
    $oldGenCount = if ($null -eq $oldGen) { -1 } else { @($oldGen.generations).Count }
    $newGenCount = if ($null -eq $newGen) { -1 } else { @($newGen.generations).Count }
    if ($Label -eq 'green') {
        Check 'x01_new_analyzer_segments_the_trace_by_generation' ($newGenCount -eq 3) ("generations old={0} new={1}" -f $oldGenCount, $newGenCount)
        $opened = @($newGen.generations | ForEach-Object { $_.opened } | Where-Object { $null -ne $_ })
        Check 'x02_each_segment_carries_its_marker' ($opened.Count -eq 3) ("segments with an opened marker: {0}" -f $opened.Count)
    } else {
        # Red: there is no marker to segment on, so both analysers see one
        # generation - the whole point of O-12.
        Check 'x01_red_without_a_marker_there_is_nothing_to_segment' (($newGenCount -eq 1) -and ($oldGenCount -eq 1)) ("generations old={0} new={1}" -f $oldGenCount, $newGenCount)
        $opened = @($newGen.generations | ForEach-Object { $_.opened } | Where-Object { $null -ne $_ })
        Check 'x02_red_no_segment_has_a_marker' ($opened.Count -eq 0) ("segments with an opened marker: {0}" -f $opened.Count)
    }

    # (2) friction: the pseudo pair (run 2, a different tool in between) has to
    # disappear while the two real episodes stay. The run-2 pair is the one whose
    # success is `seq 4` of its own generation.
    $oldFric = @($oldGen.friction.fail_then_success)
    $newFric = @($newGen.friction.fail_then_success)
    $oldPseudo = @($oldFric | Where-Object { $_.succeeded_seq -eq 4 }).Count
    $newPseudo = @($newFric | Where-Object { $_.succeeded_seq -eq 4 }).Count
    Check 'x03_the_pseudo_friction_of_run_two_is_gone' (($oldPseudo -eq 1) -and ($newPseudo -eq 0)) `
        ("pairs with the run-2 shape: old={0} new={1}; old pairs={2} new pairs={3}" -f $oldPseudo, $newPseudo, $oldFric.Count, $newFric.Count)
    if ($Label -eq 'green') {
        Check 'x04_the_two_real_episodes_are_kept' (($oldFric.Count -eq 3) -and ($newFric.Count -eq 2)) `
            ("pairs old={0} new={1}" -f $oldFric.Count, $newFric.Count)
    } else {
        # Red: with no marker the file's connections are each used once, so a
        # session-keyed pair can never form and the fixed analyser reports
        # nothing rather than gluing three runs together (O-12's consequence).
        Check 'x04_red_the_unsegmented_file_yields_no_pair_from_the_fixed_analyzer' (($oldFric.Count -eq 3) -and ($newFric.Count -eq 0)) `
            ("pairs old={0} new={1}" -f $oldFric.Count, $newFric.Count)
    }

    # (3) the unigram defect, on a file with real tool names
    $uniBad = 0
    foreach ($item in @($oldGen.mergeable.unigrams)) { if ($item.sequence.Count -gt 1) { $uniBad++ } }
    $uniGood = 0
    foreach ($item in @($newGen.mergeable.unigrams)) { if ($item.sequence.Count -eq 1) { $uniGood++ } }
    Check 'x05_a_unigram_is_a_name_not_an_array_of_characters' (($uniBad -gt 0) -and ($uniGood -gt 0)) `
        ("old unigrams split into characters={0}; new one-element names={1}" -f $uniBad, $uniGood)

    # (4) the diagnostic bypass excluded from the large-response verdict
    $synth = Join-Path $Root 'synthetic-bypass.jsonl'
    $synthLines = @(
        '{"event":"trace_opened","pid":1,"role":"editor","mcp_port":9888,"version":"x","ts_ms":1,"uptime_ms":1,"started_ts_ms":0,"listen":true}',
        '{"id":1,"seq":1,"ts_ms":2,"connection":2,"method":"tools/list","ok":true,"error_code":0,"error_message":"","duration_ms":1,"result_bytes":2000000,"tools":175}',
        '{"id":2,"seq":2,"ts_ms":3,"connection":3,"method":"tools/call","tool":"editor_get_scene_tree","ok":true,"error_code":0,"error_message":"","duration_ms":1,"result_bytes":2000000,"args":"{}","args_bytes":2,"args_truncated":false}',
        '{"event":"capture","seq":2,"tool":"editor_get_scene_tree","status":"done","total_bytes":2000000}'
    )
    Write-McpUtf8NoBom -Path $synth -Text (($synthLines -join "`n") + "`n")
    $oldSynth = Run-Analyzer -Script $OldAnalyzer -Trace $synth -JsonOut (Join-Path $Ev 'x06_old_bypass.json')
    $newSynth = Run-Analyzer -Script $NewAnalyzer -Trace $synth -JsonOut (Join-Path $Ev 'x07_new_bypass.json')
    Check 'x06_old_analyzer_flags_the_bypass_lines_as_large_responses' (@($oldSynth.anomalies.large_responses).Count -eq 2) `
        ("old large_responses={0}" -f (@($oldSynth.anomalies.large_responses | ForEach-Object { $_.method }) -join ','))
    Check 'x07_new_analyzer_flags_only_the_real_call_and_declares_the_exclusions' `
        ((@($newSynth.anomalies.large_responses).Count -eq 1) -and ($newSynth.anomalies.large_responses_excluded -eq 1) -and ([string]$newSynth.anomalies.large_responses[0].tool -ceq 'editor_get_scene_tree')) `
        ("new large_responses={0} excluded={1}" -f (@($newSynth.anomalies.large_responses | ForEach-Object { $_.tool }) -join ','), $newSynth.anomalies.large_responses_excluded)

    # (5) the same contrast on the traces the audit used, when they are present
    if (Test-Path $editorTrace) {
        $oldE = Run-Analyzer -Script $OldAnalyzer -Trace $editorTrace -JsonOut (Join-Path $Ev 'x08_old_editor_trace.json')
        $newE = Run-Analyzer -Script $NewAnalyzer -Trace $editorTrace -JsonOut (Join-Path $Ev 'x09_new_editor_trace.json')
        $oldPairs = @($oldE.friction.fail_then_success)
        $newPairs = @($newE.friction.fail_then_success)
        $oldBigrams = @($oldE.mergeable.bigrams).Count
        $newBigrams = @($newE.mergeable.bigrams).Count
        Check 'x08_on_the_audit_editor_trace_the_one_pseudo_pair_goes_and_the_real_ones_stay' `
            (($oldPairs.Count -eq 13) -and ($newPairs.Count -eq 12)) ("pairs old={0} new={1}" -f $oldPairs.Count, $newPairs.Count)
        Check 'x09_the_same_trace_now_yields_bigrams_instead_of_an_empty_list' `
            (($oldBigrams -eq 0) -and ($newBigrams -gt 0)) ("bigrams old={0} new={1}" -f $oldBigrams, $newBigrams)
    }
    if (Test-Path $auditTrace) {
        $oldA = Run-Analyzer -Script $OldAnalyzer -Trace $auditTrace -JsonOut (Join-Path $Ev 'x10_old_audit_trace.json')
        $newA = Run-Analyzer -Script $NewAnalyzer -Trace $auditTrace -JsonOut (Join-Path $Ev 'x11_new_audit_trace.json')
        Check 'x10_the_audit_game_trace_keeps_its_unmarked_generations_at_one' (@($newA.generations).Count -eq 1) `
            ("new generations={0}" -f @($newA.generations).Count)
        Check 'x11_the_audit_game_trace_no_longer_mixes_three_runs_into_one_friction_list' `
            (@($oldA.friction.fail_then_success).Count -eq 3) ("pairs old={0} new={1}" -f @($oldA.friction.fail_then_success).Count, @($newA.friction.fail_then_success).Count)
        Check 'x12_the_unigram_repair_is_visible_on_the_audit_trace_too' `
            ((@($oldA.mergeable.unigrams)[0].sequence.Count -gt 1) -and (@($newA.mergeable.unigrams)[0].sequence.Count -eq 1)) `
            ("old first unigram elements={0} new={1}" -f @($oldA.mergeable.unigrams)[0].sequence.Count, @($newA.mergeable.unigrams)[0].sequence.Count)
    }

    # =======================================================================
    #  The user's editor must be untouched.
    # =======================================================================
    $userPidAfter = Get-ListenerPid -Port_ $UserPort
    $portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter $userPidAfter
    Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence
    Check 'user_editor_9877_untouched' ($userPidAfter -eq $userPidBefore) ("pid before={0} after={1}" -f $userPidBefore, $userPidAfter)
    Check 'test_ports_free_after' (((Get-ListenerPid -Port_ $EditorPort) -eq -1) -and ((Get-ListenerPid -Port_ $GamePort) -eq -1)) `
        ("port {0} owner={1}; port {2} owner={3}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort), $GamePort, (Get-ListenerPid -Port_ $GamePort))

    $passed = @($script:Checks | Where-Object { $_.pass }).Count
    $total = $script:Checks.Count
    $summary = [pscustomobject]@{
        label         = $Label
        git_head      = $headSha
        plain_version = $plainVersion
        mono_version  = $monoVersion
        checks_passed = $passed
        checks_total  = $total
        trace_sha256  = $traceSha
        checks        = $script:Checks
    }
    Write-McpUtf8NoBom -Path (Join-Path $Ev 'results.json') -Text (ConvertTo-Json -InputObject $summary -Depth 8)
    $log = @()
    foreach ($entry in $script:Checks) {
        $tag = if ($entry.pass) { 'PASS' } else { 'FAIL' }
        $log += ("[{0}] {1} :: {2}" -f $tag, $entry.id, $entry.evidence)
    }
    $log += ''
    $log += ("label={0} git_head={1} plain={2} mono={3} trace_sha256={4}" -f $Label, $headSha, $plainVersion, $monoVersion, $traceSha)
    Write-McpUtf8NoBom -Path (Join-Path $Ev 'evidence.log.txt') -Text (($log -join "`r`n") + "`r`n")
    Write-Host ("[{0}] {1}/{2} checks passed" -f $Label, $passed, $total)
    if ($passed -ne $total) {
        foreach ($entry in $script:Checks) { if (-not $entry.pass) { Write-Host ("  FAILED {0} :: {1}" -f $entry.id, $entry.evidence) } }
        exit 1
    }
    exit 0
} finally {
    if ($null -ne $plainHandle) { Stop-McpEngine -Handle $plainHandle -Name 'plain-editor' }
    if ($null -ne $monoHandle) { Stop-McpEngine -Handle $monoHandle -Name 'mono-editor' }
}
