# =============================================================================
#  mcp052_added_tools_evidence.ps1 -- TASK-052 section 1 and 2, the live evidence
#  of the two *added* tools (`project_build_csharp`, `project_write_text_file`)
#  and of the closed loop they make possible.
#
#  It answers gate 2 of the PLAYBOOK for the two added entries:
#
#    * three classes of evidence per tool: success / missing parameter /
#      underlying failure (a refusal, in the sense of the module: -32602 with a
#      suggestion, or -32000/-32001 with one);
#    * one cross-tool end-to-end chain: a minimal C# project is built **from
#      nothing with the tools only** - `project_set_setting` writes the project
#      name, `project_write_text_file` writes the `.csproj` and the
#      `NuGet.config`, `project_create_script` writes the `.cs`, and
#      `project_build_csharp` compiles it - with the response and its sha256
#      printed at every step;
#    * the honest refusal of an engine without C# support (the plain build),
#      the non-zero exit code of a broken build, and the real kill of a build
#      that outruns `timeout_ms`.
#
#  Phases (each phase owns its engine process and its scratch project):
#
#    A  the plain (non-mono) editor on 9888, project `proj-refuse`:
#       the added entries verbatim on the wire, every refusal of
#       `project_write_text_file`, the "no delete path" property, the argument
#       rules of `project_build_csharp` and its capability refusal;
#    B  the mono editor on 9888, project `proj-loop` (still empty):
#       `-32001` for "there is no .csproj to build";
#    C  the mono editor on 9888, project `proj-loop`:
#       the closed loop, the broken build, the timeout + kill;
#    D  the mono *game* process on 9889: the two added tools are served by the
#       game endpoint too (`scope = both`).
#
#  Port discipline: the user's editor on 9877 is never started, killed or
#  restarted; only the two test ports 9888 / 9889 are used, and the port guard
#  records the 9877 pid before and after.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp052_added_tools_evidence.ps1
# =============================================================================

param(
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
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$UserPort = 9877

$Root = Join-Path $env:TEMP 'mcp052'
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$RefuseProject = Join-Path $Root 'proj-refuse'
$LoopProject = Join-Path $Root 'proj-loop'

. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-072: the anchor criterion is not re-implemented here. All anchor checks in
# this module call the one judge (see check_engine_anchor.ps1 for the criterion).
. (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]
$script:StepHashes = New-Object System.Collections.Generic.List[object]

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
    $script:StepHashes.Add([pscustomobject]@{ id = $Id; bytes = $bytes.Count; sha256 = $sha })
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

function Get-ErrorMessage {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return '' }
        return [string]$envelope.error.message
    } catch { return '' }
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

function Wait-ForEndpoint {
    param([int]$Port_, [int]$TimeoutMs)
    # TASK-054: the probe file is removed before every attempt and `curl` has to
    # exit 0. A *failed* `curl.exe -o` does not rewrite the file (curl never
    # opens the output on a refused connection), so the version of this function
    # that parsed whatever was there answered "ready" from the previous phase's
    # body while the mono editor was still loading - measured as
    # `curl_exit=7 bytes=0` on the first request of phase B.
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Join-Path $Ev 'status.json'
        if (Test-Path $probe) { Remove-Item -Force $probe }
        & $Curl -s --max-time 5 -o $probe ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (($LASTEXITCODE -eq 0) -and (Test-Path $probe)) {
            try {
                $parsed = ConvertFrom-Json ([IO.File]::ReadAllText($probe))
                if ($null -ne $parsed.frame_count) { return $true }
            } catch { }
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

function Start-McpEngine {
    param([string]$Engine, [string]$Project, [int]$Port_, [string]$Name, [switch]$Editor)
    $arguments = @('--headless')
    if ($Editor) { $arguments += '-e' }
    $arguments += @('--path', $Project, ("--mcp-port={0}" -f $Port_))
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

function Get-ToolNames {
    param($ListText)
    $names = @()
    try {
        $envelope = ConvertFrom-Json $ListText
        $names = @($envelope.result.tools | ForEach-Object { [string]$_.name })
    } catch { }
    return $names
}

function Get-DiskSha {
    param([string]$Path)
    if (Test-Path $Path) { return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower() }
    return '<missing>'
}

function Show-Step {
    param([string]$Label, [string]$Text)
    $short = $Text
    if ($short.Length -gt 700) { $short = $short.Substring(0, 700) + '...' }
    Write-Host ("--- {0} ---" -f $Label)
    Write-Host $short
}

# =============================================================================
#  Main
# =============================================================================
Write-Host '============================================================='
Write-Host ' TASK-052: the two added tools (project_build_csharp /'
Write-Host '           project_write_text_file) and the closed C# loop'
Write-Host '============================================================='

foreach ($pair in @(@('plain', $PlainEngine), @('mono', $MonoEngine))) {
    if (-not (Test-Path $pair[1])) { Write-Host ("FATAL: {0} engine not found: {1}" -f $pair[0], $pair[1]); exit 2 }
}
if (-not (Test-Path $ContractPath)) { Write-Host ("FATAL: contract not found: {0}" -f $ContractPath); exit 2 }

Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

$headSha = ((& git -C $RepoRoot rev-parse --short=9 HEAD) -join '').Trim()
$plainVersion = ((& $PlainEngine --version 2>$null) -join ' ').Trim()
$monoVersion = ((& $MonoEngine --version 2>$null) -join ' ').Trim()
# TASK-072 (D130): an anchor is NOT "the binary prints HEAD". That criterion was
# red on every docs-only commit, and TASK-071 was marked FAILED STEPS: 2 by it
# with no regression behind it. The judge below accepts a *structural* match (the
# anchor is an ancestor of HEAD and the whole diff is non-compiling) and still
# fails closed on a stale binary. The check id is kept for continuity; the
# evidence line now carries the reported anchor, HEAD, the criterion and the
# complete diff list, so nothing is hidden behind the verdict name.
$plainAnchor = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $plainVersion -HeadSha $headSha
$monoAnchor = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $monoVersion -HeadSha $headSha
Check 'engines_match_head' (($plainAnchor.Ok) -and ($monoAnchor.Ok)) `
    (("plain --version='{0}' | {1}" -f $plainVersion, $plainAnchor.Summary) + ' || ' + `
     ("mono --version='{0}' | {1}" -f $monoVersion, $monoAnchor.Summary))
Check 'mono_engine_is_the_mono_build' ($monoVersion.Contains('.mono.')) ("mono --version='{0}'" -f $monoVersion)
Write-Host ("plain engine sha256 = {0}" -f (Get-DiskSha $PlainEngine))
Write-Host ("mono  engine sha256 = {0}" -f (Get-DiskSha $MonoEngine))

# The contract's own two added entries, read from the generator's artifact.
$contract = ConvertFrom-Json ([IO.File]::ReadAllText($ContractPath, (New-Object Text.UTF8Encoding($false))))
$contractNames = @($contract.result.tools | ForEach-Object { [string]$_.name })
$addedNames = @($contract._meta.added_tools | ForEach-Object { [string]$_ })
# TASK-064 D-8: this check used to pin the literal four-some `[..., ..., ..., ...]`
# of TASK-053. TASK-063 then appended `editor_set_node_property_updates`
# (contract 175 -> 176) - a legitimate growth of the *same* list this script
# reads - and the pinned literal went red although nothing about TASK-052's
# subject (the first two entries, still positions 0 and 1) had changed. The
# expectation is now derived from the manifest `docs/tool-groups-added.json`,
# whose tool union is the contract's own `_meta.added_tools` in append order
# (`check_tool_groups.py --added` states the equivalence in both directions), so
# a name that is appended, removed or reordered still fails while a legitimate
# append does not. The literal 171 half below stays a checked literal on purpose
# - it is the ported-entry count GDR-17 fixes, and a contract that silently lost
# a ported entry would still satisfy "count == len(result.tools)".
$addedManifestDoc = ConvertFrom-Json ([IO.File]::ReadAllText($AddedManifest, (New-Object Text.UTF8Encoding($false))))
$addedManifestNames = @()
foreach ($group in @($addedManifestDoc.groups)) { foreach ($tool in @($group.tools)) { $addedManifestNames += [string]$tool } }
$portedCount = 171
Check 'contract_meta_added_tools' `
    (($addedNames.Count -eq [int]$contract._meta.added_count) -and `
     (($addedNames -join ",") -ceq (($addedManifestNames -join ","))) -and `
     ($addedNames[0] -ceq 'project_build_csharp') -and ($addedNames[1] -ceq 'project_write_text_file')) `
    ("_meta.added_count={0} _meta.added_tools=[{1}] manifest=[{2}] (derived from docs/tool-groups-added.json; the pinned four-some of TASK-053 is gone - TASK-064 D-8) contract entries={3}" -f `
        $contract._meta.added_count, ($addedNames -join ', '), ($addedManifestNames -join ', '), $contractNames.Count)

$contractBuild = $null
$contractWrite = $null
foreach ($entry in @($contract.result.tools)) {
    if ([string]$entry.name -ceq 'project_build_csharp') { $contractBuild = $entry }
    if ([string]$entry.name -ceq 'project_write_text_file') { $contractWrite = $entry }
}
Check 'contract_has_both_added_entries' (($null -ne $contractBuild) -and ($null -ne $contractWrite)) `
    ("project_build_csharp={0} project_write_text_file={1}" -f ($null -ne $contractBuild), ($null -ne $contractWrite))

# What each endpoint is supposed to serve, derived and not written down: the
# contract minus the tools of the other process. `docs/tool-rename-map.json` is
# the authority for a *ported* tool's scope and the added manifest declares its
# own members' scope (GDR-28 point 3), so the two sources are merged here exactly
# the way `scripts/check_contract_subset.ps1` merges them.
$scopeOf = @{}
$mapDoc = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $RepoRoot 'modules\mcp_server\docs\tool-rename-map.json'), (New-Object Text.UTF8Encoding($false))))
foreach ($entry in @($mapDoc.tools)) { $scopeOf[[string]$entry.new_name] = [string]$entry.scope }
$addedDoc = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $RepoRoot 'modules\mcp_server\docs\tool-groups-added.json'), (New-Object Text.UTF8Encoding($false))))
foreach ($group in @($addedDoc.groups)) { foreach ($tool in @($group.tools)) { $scopeOf[[string]$tool] = [string]$group.scope } }
$editorExpectedCount = @($contractNames | Where-Object { $scopeOf[$_] -ne 'game' }).Count
$gameExpectedCount = @($contractNames | Where-Object { $scopeOf[$_] -ne 'editor' }).Count
# TASK-064 D-8: this check used to pin the pair (152, 72). Those two numbers are
# a function of the contract, which grows: TASK-063 appended one editor-scope
# tool, so the editor view became 153 and the pinned 152 went red on a tree where
# every tool this script is about was still there. The expectation is now
# *derived* from the two declared sources - the contract's entries and the scope
# declarations of `docs/tool-rename-map.json` plus `docs/tool-groups-added.json`
# - exactly the merge `accept_m1.ps1` and `check_contract_subset.ps1` perform;
# the contract's `171 + added_count` half is asserted on the same line, and the
# live counts are separately required to equal these derived values
# (`a2_editor_live_count_is_the_contract_view` / `d2_game_live_count_...` below),
# which is what gives this check its teeth.
Check 'endpoint_expectations_derived' `
    (($contractNames.Count -eq ($portedCount + $addedNames.Count)) -and ($addedNames.Count -eq [int]$contract._meta.added_count)) `
    ("editor expects {0} tool(s), game expects {1} tool(s) from the {2} entry contract = {3} ported + {4} added (the scope of every entry resolved from docs/tool-rename-map.json and docs/tool-groups-added.json - the same merge accept_m1.ps1 and check_contract_subset.ps1 perform; the pinned pair 152/72 is gone - TASK-064 D-8). The live endpoints are separately required to equal these two derived numbers." -f $editorExpectedCount, $gameExpectedCount, $contractNames.Count, $portedCount, $addedNames.Count)

# The scratch projects. Both are written without a BOM; `proj-loop` starts empty
# on purpose (no .csproj), which is what phase B measures.
#
# The port guard is armed *before* the imports so that the `--import` command
# lines are recorded too: the guard's second half is "no process this script
# started was even asked for the user's port", which needs every command line.
$userPidBefore = Get-ListenerPid -Port_ $UserPort
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("user editor on {0} before: pid={1}" -f $UserPort, $userPidBefore)
Check 'test_ports_free_before' (((Get-ListenerPid -Port_ $EditorPort) -eq -1) -and ((Get-ListenerPid -Port_ $GamePort) -eq -1)) `
    ("port {0} owner={1}; port {2} owner={3}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort), $GamePort, (Get-ListenerPid -Port_ $GamePort))

New-McpScratchProject -Path $RefuseProject -Name 'MCP052 refuse' -WithMainScene $true
New-McpScratchProject -Path $LoopProject -Name 'MCP052 loop' -WithMainScene $true
$importRefuse = Import-McpProject -Engine $PlainEngine -Path $RefuseProject -LogDirectory $LogRoot -Name 'import-refuse'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine ([string]$importRefuse.command)
$importLoop = Import-McpProject -Engine $MonoEngine -Path $LoopProject -LogDirectory $LogRoot -Name 'import-loop'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine ([string]$importLoop.command)
Check 'scratch_projects_imported' (($importRefuse.exit_code -eq 0) -and ($importLoop.exit_code -eq 0)) `
    ("proj-refuse exit={0} attempts={1}; proj-loop exit={2} attempts={3}" -f $importRefuse.exit_code, $importRefuse.attempts, $importLoop.exit_code, $importLoop.attempts)

$plainHandle = $null
$monoHandle = $null
$gameHandle = $null
try {
    # -------------------------------------------------------------------------
    #  Phase A: the plain (non-mono) editor - refusals, arguments, capability.
    # -------------------------------------------------------------------------
    $plainHandle = Start-McpEngine -Engine $PlainEngine -Project $RefuseProject -Port_ $EditorPort -Name 'plain-editor' -Editor
    $ready = Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs
    Check 'phase_a_plain_editor_ready' $ready ("plain editor answered GET /mcp on {0}" -f $EditorPort)

    $listA = Invoke-Json -Id 'a1_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port_ $EditorPort
    $namesA = Get-ToolNames $listA
    Check 'a2_editor_serves_both_added_tools' (($namesA -contains 'project_build_csharp') -and ($namesA -contains 'project_write_text_file')) `
        ("live tools/list = {0} tool(s); added present={1}" -f $namesA.Count, ((@($namesA | Where-Object { $addedNames -contains $_ })) -join ', '))
    Check 'a3_editor_live_count_is_the_contract_view' ($namesA.Count -eq $editorExpectedCount) `
        ("live={0} derived editor view={1} (contract {2})" -f $namesA.Count, $editorExpectedCount, $contractNames.Count)
    foreach ($entry in @($contractBuild, $contractWrite)) {
        $live = Get-ToolEntry $listA ([string]$entry.name)
        $same = ($null -ne $live) -and ([string]$live.description -ceq [string]$entry.description)
        $schemaSame = $false
        if ($null -ne $live) {
            $liveSchema = ConvertTo-Json -InputObject $live.inputSchema -Depth 30 -Compress
            $wantSchema = ConvertTo-Json -InputObject $entry.inputSchema -Depth 30 -Compress
            $schemaSame = ($liveSchema -ceq $wantSchema)
        }
        Check ("a4_{0}_verbatim_on_the_editor" -f [string]$entry.name) ($same -and $schemaSame) `
            ("description={0} inputSchema={1}" -f $same, $schemaSame)
    }

    # --- project_write_text_file: the four dedicated families + project.godot --
    $refusals = @(
        @{ id = 'a5_project_godot'; path = 'res://project.godot'; want = 'project_set_setting' },
        @{ id = 'a6_tscn'; path = 'res://scene.tscn'; want = 'project_create_scene_file' },
        @{ id = 'a7_tres'; path = 'res://thing.tres'; want = 'project_create_resource' },
        @{ id = 'a8_gd'; path = 'res://script.gd'; want = 'project_create_script' },
        @{ id = 'a9_cs'; path = 'res://Script.cs'; want = 'project_create_script' },
        @{ id = 'a10_outside_res'; path = 'user://outside.cfg'; want = 'res://' },
        @{ id = 'a11_dotdot'; path = 'res://../escape.cfg'; want = '..' }
    )
    foreach ($case in $refusals) {
        $resp = Invoke-Tool -Id $case.id -Tool 'project_write_text_file' -Arguments @{ path = $case.path; content = 'x' } -Port_ $EditorPort
        $code = Get-ErrorCode $resp
        $suggestion = Get-Suggestion $resp
        $named = ($suggestion.Contains([string]$case.want)) -or ((Get-ErrorMessage $resp).Contains([string]$case.want))
        Check ($case.id + '_refused_with_a_named_tool') (($code -eq -32602) -and $named) `
            ("path='{0}' code={1} suggestion='{2}'" -f $case.path, $code, $suggestion)
    }
    # --- the two required members --------------------------------------------
    $resp = Invoke-Tool -Id 'a12_missing_path' -Tool 'project_write_text_file' -Arguments @{ content = 'x' } -Port_ $EditorPort
    Check 'a12_missing_path_is_32602' ((Get-ErrorCode $resp) -eq -32602) ("code={0} message='{1}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp))
    $resp = Invoke-Tool -Id 'a13_missing_content' -Tool 'project_write_text_file' -Arguments @{ path = 'res://ok.cfg' } -Port_ $EditorPort
    Check 'a13_missing_content_is_32602' ((Get-ErrorCode $resp) -eq -32602) ("code={0} message='{1}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp))

    # --- the success class: write, read back, hash ---------------------------
    $csproj = @(
        '<Project Sdk="Microsoft.NET.Sdk">',
        '  <PropertyGroup>',
        '    <TargetFramework>net8.0</TargetFramework>',
        '    <AssemblyName>Mcp052Loop</AssemblyName>',
        '    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>',
        '    <Nullable>disable</Nullable>',
        '  </PropertyGroup>',
        '  <ItemGroup>',
        '    <Compile Include="Mcp052Loop.cs" />',
        '  </ItemGroup>',
        '</Project>'
    ) -join "`n"
    $csproj += "`n"
    $nuget = @(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<configuration>',
        '  <packageSources>',
        '    <clear />',
        '  </packageSources>',
        '</configuration>'
    ) -join "`n"
    $nuget += "`n"

    $resp = Invoke-Tool -Id 'a14_write_csproj' -Tool 'project_write_text_file' -Arguments @{ path = 'res://Mcp052Loop.csproj'; content = $csproj } -Port_ $EditorPort
    $payload = Get-Payload $resp
    $disk = Join-Path $RefuseProject 'Mcp052Loop.csproj'
    $diskSha = Get-DiskSha $disk
    $ok = ($null -ne $payload) -and ([string]$payload.path -ceq 'res://Mcp052Loop.csproj') -and ($payload.created -eq $true) -and ([string]$payload.sha256 -ceq $diskSha)
    Check 'a14_write_success_matches_the_file_on_disk' $ok `
        ("path={0} bytes={1} created={2} sha256_answered={3} sha256_on_disk={4}" -f $payload.path, $payload.bytes, $payload.created, $payload.sha256, $diskSha)
    Show-Step 'a14 response' $resp

    $resp = Invoke-Tool -Id 'a15_write_nuget' -Tool 'project_write_text_file' -Arguments @{ path = 'res://NuGet.config'; content = $nuget } -Port_ $EditorPort
    $payload = Get-Payload $resp
    $diskNuget = Join-Path $RefuseProject 'NuGet.config'
    Check 'a15_second_write_is_honest_too' (($null -ne $payload) -and ([string]$payload.sha256 -ceq (Get-DiskSha $diskNuget))) `
        ("path={0} bytes={1} sha256={2}" -f $payload.path, $payload.bytes, $payload.sha256)

    # --- overwrite:false on an occupied destination --------------------------
    # TASK-053 section 1 re-judged the code: the destination exists (`-32001` is
    # "the thing you looked for is absent") and `overwrite: false` is a declared
    # parameter with a legal value (`-32602`), so the refusal is the state's,
    # which is `-32000`. The bytes-unchanged half of this check is unchanged.
    $beforeSha = Get-DiskSha $disk
    $resp = Invoke-Tool -Id 'a16_overwrite_false' -Tool 'project_write_text_file' -Arguments @{ path = 'res://Mcp052Loop.csproj'; content = 'replacement' } -Port_ $EditorPort
    $afterSha = Get-DiskSha $disk
    Check 'a16_occupied_destination_is_refused_and_bytes_unchanged' `
        (((Get-ErrorCode $resp) -eq -32000) -and ((Get-Suggestion $resp).Contains('overwrite": true')) -and ($beforeSha -ceq $afterSha)) `
        ("code={0} suggestion='{1}' sha_before={2} sha_after={3}" -f (Get-ErrorCode $resp), (Get-Suggestion $resp), $beforeSha, $afterSha)

    # --- the "no delete path" property --------------------------------------
    $resp = Invoke-Tool -Id 'a17_delete_argument' -Tool 'project_write_text_file' -Arguments @{ path = 'res://x.cfg'; content = 'x'; remove = $true } -Port_ $EditorPort
    Check 'a17_delete_shaped_argument_is_refused' (((Get-ErrorCode $resp) -eq -32602) -and ((Get-ErrorMessage $resp).Contains('Unknown parameter'))) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp))
    $writeEntry = Get-ToolEntry $listA 'project_write_text_file'
    $props = @()
    if ($null -ne $writeEntry) { $props = @($writeEntry.inputSchema.properties.PSObject.Properties | ForEach-Object { $_.Name }) }
    $propsSorted = @($props | Sort-Object)
    Check 'a18_schema_has_exactly_three_members' (($propsSorted.Count -eq 3) -and ($propsSorted[0] -ceq 'content') -and ($propsSorted[1] -ceq 'overwrite') -and ($propsSorted[2] -ceq 'path')) `
        ("properties = [{0}]" -f ($propsSorted -join ', '))

    # --- project_build_csharp: arguments, then capability --------------------
    $argCases = @(
        @{ id = 'a19_bad_configuration'; args = @{ configuration = 'Fast' }; want = 'Debug' },
        @{ id = 'a20_bad_timeout'; args = @{ timeout_ms = 500 }; want = '1000' },
        @{ id = 'a21_bad_extra_args'; args = @{ extra_args = 7 }; want = 'array of strings' },
        @{ id = 'a22_bad_rescan'; args = @{ rescan = 'yes' }; want = 'boolean' }
    )
    foreach ($case in $argCases) {
        $resp = Invoke-Tool -Id $case.id -Tool 'project_build_csharp' -Arguments $case.args -Port_ $EditorPort
        Check ($case.id + '_is_32602') (((Get-ErrorCode $resp) -eq -32602) -and ((Get-ErrorMessage $resp).Contains([string]$case.want))) `
            ("code={0} message='{1}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp))
    }
    $resp = Invoke-Tool -Id 'a23_capability_refusal' -Tool 'project_build_csharp' -Arguments @{} -Port_ $EditorPort
    $code = Get-ErrorCode $resp
    $suggestion = Get-Suggestion $resp
    Check 'a23_plain_engine_refuses_without_csharp_support' (($code -eq -32000) -and ($suggestion.Contains('C#')) -and ($suggestion.Length -gt 0)) `
        ("code={0} message='{1}' suggestion='{2}'" -f $code, (Get-ErrorMessage $resp), $suggestion)
    Show-Step 'a23 response' $resp
    Stop-McpEngine -Handle $plainHandle -Name 'plain-editor'
    $plainHandle = $null

    # -------------------------------------------------------------------------
    #  Phase B: the mono editor, empty project - the concrete refusal.
    # -------------------------------------------------------------------------
    $monoHandle = Start-McpEngine -Engine $MonoEngine -Project $LoopProject -Port_ $EditorPort -Name 'mono-editor' -Editor
    $ready = Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs
    Check 'phase_b_mono_editor_ready' $ready ("mono editor answered GET /mcp on {0}" -f $EditorPort)
    $resp = Invoke-Tool -Id 'b1_no_csproj' -Tool 'project_build_csharp' -Arguments @{} -Port_ $EditorPort
    Check 'b1_no_csproj_is_32001_with_a_suggestion' (((Get-ErrorCode $resp) -eq -32001) -and ((Get-Suggestion $resp).Contains('project_write_text_file'))) `
        ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp), (Get-Suggestion $resp))

    # -------------------------------------------------------------------------
    #  Phase C: the closed loop, from nothing, with the tools only.
    # -------------------------------------------------------------------------
    $resp = Invoke-Tool -Id 'c1_project_set_setting' -Tool 'project_set_setting' -Arguments @{ key = 'application/config/name'; value = 'Mcp052ClosedLoop' } -Port_ $EditorPort
    $payload = Get-Payload $resp
    Check 'c1_project_name_written_by_project_set_setting' (($null -ne $payload) -and ([string]$payload.value -ceq 'Mcp052ClosedLoop') -and ($payload.saved -eq $true)) `
        ("key={0} value={1} saved={2}" -f $payload.key, $payload.value, $payload.saved)
    Show-Step 'c1 response (project_set_setting)' $resp

    $resp = Invoke-Tool -Id 'c2_write_csproj' -Tool 'project_write_text_file' -Arguments @{ path = 'res://Mcp052Loop.csproj'; content = $csproj } -Port_ $EditorPort
    $payload = Get-Payload $resp
    $loopCsproj = Join-Path $LoopProject 'Mcp052Loop.csproj'
    Check 'c2_csproj_written_by_project_write_text_file' (($null -ne $payload) -and ($payload.created -eq $true) -and ([string]$payload.sha256 -ceq (Get-DiskSha $loopCsproj))) `
        ("path={0} bytes={1} created={2} sha256={3}" -f $payload.path, $payload.bytes, $payload.created, $payload.sha256)
    Show-Step 'c2 response (project_write_text_file / .csproj)' $resp

    $resp = Invoke-Tool -Id 'c3_write_nuget' -Tool 'project_write_text_file' -Arguments @{ path = 'res://NuGet.config'; content = $nuget } -Port_ $EditorPort
    $payload = Get-Payload $resp
    Check 'c3_nuget_config_written' (($null -ne $payload) -and ([string]$payload.sha256 -ceq (Get-DiskSha (Join-Path $LoopProject 'NuGet.config')))) `
        ("path={0} bytes={1} sha256={2}" -f $payload.path, $payload.bytes, $payload.sha256)
    Show-Step 'c3 response (project_write_text_file / NuGet.config)' $resp

    $csCode = @(
        'namespace Mcp052Loop {',
        '    public static class Greeter {',
        '        public static string Hello() { return "mcp052-closed-loop"; }',
        '    }',
        '}'
    ) -join "`n"
    $csCode += "`n"
    $resp = Invoke-Tool -Id 'c4_create_cs' -Tool 'project_create_script' -Arguments @{ path = 'res://Mcp052Loop.cs'; content = $csCode; template = 'Node' } -Port_ $EditorPort
    $payload = Get-Payload $resp
    Check 'c4_cs_written_by_project_create_script' (($null -ne $payload) -and (Test-Path (Join-Path $LoopProject 'Mcp052Loop.cs'))) `
        ("path={0} bytes={1}" -f $payload.path, $payload.bytes)
    Show-Step 'c4 response (project_create_script / .cs)' $resp

    $resp = Invoke-Tool -Id 'c5_build_success' -Tool 'project_build_csharp' -Arguments @{ configuration = 'Debug' } -Port_ $EditorPort -MaxTimeSec 600
    $payload = Get-Payload $resp
    $dll = Join-Path $LoopProject 'bin\Debug\net8.0\Mcp052Loop.dll'
    $dllOk = Test-Path $dll
    $dllSha = Get-DiskSha $dll
    $ok = ($null -ne $payload) -and ([int]$payload.exit_code -eq 0) -and ([bool]$payload.timed_out -eq $false) -and `
        ([string]$payload.command.Contains('build')) -and ([string]$payload.command.Contains('dotnet')) -and `
        ($payload.project_files -contains 'res://Mcp052Loop.csproj') -and ($payload.duration_ms -gt 0) -and $dllOk
    Check 'c5_closed_loop_build_succeeded' $ok `
        ("exit_code={0} timed_out={1} duration_ms={2} command='{3}' project_files=[{4}] dll={5} ({6} bytes, sha256={7})" -f `
            $payload.exit_code, $payload.timed_out, $payload.duration_ms, $payload.command, ($payload.project_files -join ', '), $dllOk, (Get-Item $dll -ErrorAction SilentlyContinue).Length, $dllSha)
    Show-Step 'c5 response (project_build_csharp success)' $resp
    Check 'c5b_stdout_carries_the_sdk_output' (($null -ne $payload) -and ([string]$payload.stdout.Length -gt 0) -and (-not [bool]$payload.stdout_truncated)) `
        ("stdout = {0} byte(s); stderr = {1} byte(s); stdout_truncated={2}" -f ([string]$payload.stdout).Length, ([string]$payload.stderr).Length, $payload.stdout_truncated)

    # --- the failure class: a broken .cs must be a non-zero exit code --------
    $broken = @(
        'namespace Mcp052Loop {',
        '    public static class Greeter {',
        '        this is not valid C#',
        '    }',
        '}'
    ) -join "`n"
    $broken += "`n"
    $resp = Invoke-Tool -Id 'c6_write_broken_cs' -Tool 'project_create_script' -Arguments @{ path = 'res://Mcp052Loop.cs'; content = $broken; template = 'Node' } -Port_ $EditorPort
    Check 'c6_broken_cs_written' ((Get-ErrorCode $resp) -eq 0) ("code={0}" -f (Get-ErrorCode $resp))
    $resp = Invoke-Tool -Id 'c7_build_failure' -Tool 'project_build_csharp' -Arguments @{ configuration = 'Debug' } -Port_ $EditorPort -MaxTimeSec 600
    $payload = Get-Payload $resp
    $combined = ([string]$payload.stdout) + ([string]$payload.stderr)
    $ok = ($null -ne $payload) -and ([int]$payload.exit_code -ne 0) -and (-not [bool]$payload.timed_out) -and ($combined.Length -gt 0)
    Check 'c7_broken_build_is_a_nonzero_exit_code' $ok `
        ("exit_code={0} timed_out={1} stdout_bytes={2} stderr_bytes={3} mentions_error={4}" -f `
            $payload.exit_code, $payload.timed_out, ([string]$payload.stdout).Length, ([string]$payload.stderr).Length, ($combined -match 'error'))
    Show-Step 'c7 response (project_build_csharp failure)' $resp

    # --- the timeout class: the child is really killed -----------------------
    $slow = @(
        '<Project Sdk="Microsoft.NET.Sdk">',
        '  <PropertyGroup>',
        '    <TargetFramework>net8.0</TargetFramework>',
        '    <AssemblyName>Mcp052Loop</AssemblyName>',
        '    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>',
        '  </PropertyGroup>',
        '  <Target Name="Mcp052Slow" BeforeTargets="CoreCompile">',
        '    <Exec Command="ping -n 12 127.0.0.1 &gt; nul" />',
        '  </Target>',
        '  <ItemGroup>',
        '    <Compile Include="Mcp052Loop.cs" />',
        '  </ItemGroup>',
        '</Project>'
    ) -join "`n"
    $slow += "`n"
    $goodCs = $csCode
    $resp = Invoke-Tool -Id 'c8_write_good_cs_again' -Tool 'project_create_script' -Arguments @{ path = 'res://Mcp052Loop.cs'; content = $goodCs; template = 'Node' } -Port_ $EditorPort
    Check 'c8_cs_restored' ((Get-ErrorCode $resp) -eq 0) ("code={0}" -f (Get-ErrorCode $resp))
    $resp = Invoke-Tool -Id 'c9_write_slow_csproj' -Tool 'project_write_text_file' -Arguments @{ path = 'res://Mcp052Loop.csproj'; content = $slow; overwrite = $true } -Port_ $EditorPort
    Check 'c9_slow_csproj_written' ((Get-ErrorCode $resp) -eq 0) ("code={0}" -f (Get-ErrorCode $resp))

    # The slow target only runs when MSBuild really compiles, so the previous
    # build's outputs are removed: an up-to-date project would answer instantly
    # and the timeout path would never be entered (that would be a test that
    # cannot fail, not a passing one).
    Remove-Item -Recurse -Force (Join-Path $LoopProject 'bin'), (Join-Path $LoopProject 'obj') -ErrorAction SilentlyContinue
    Write-Host ("removed the previous build outputs of {0} to force a full build" -f $LoopProject)

    $dotnetBefore = @(Get-Process dotnet -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    $resp = Invoke-Tool -Id 'c10_build_times_out' -Tool 'project_build_csharp' -Arguments @{ timeout_ms = 2000; extra_args = @('/nodeReuse:false') } -Port_ $EditorPort -MaxTimeSec 300
    $payload = Get-Payload $resp
    $ok = ($null -ne $payload) -and ([bool]$payload.timed_out -eq $true) -and ([int]$payload.exit_code -eq -1) -and `
        ([bool]$payload.killed -eq $true) -and ([int]$payload.duration_ms -lt 30000) -and ([int]$payload.effective_timeout_ms -eq 2000)
    Check 'c10_timeout_reports_timed_out_and_a_kill' $ok `
        ("timed_out={0} exit_code={1} killed={2} duration_ms={3} timeout_ms={4} effective_timeout_ms={5}" -f `
            $payload.timed_out, $payload.exit_code, $payload.killed, $payload.duration_ms, $payload.timeout_ms, $payload.effective_timeout_ms)
    Show-Step 'c10 response (project_build_csharp timeout)' $resp

    $newDotnet = @()
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        Start-Sleep -Milliseconds 500
        $dotnetAfter = @(Get-Process dotnet -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
        $newDotnet = @($dotnetAfter | Where-Object { $dotnetBefore -notcontains $_ })
        if ($newDotnet.Count -eq 0) { break }
    }
    Check 'c11_the_build_child_really_died' ($newDotnet.Count -eq 0) `
        ("dotnet pids before=[{0}] after=[{1}] new=[{2}]" -f ($dotnetBefore -join ','), (@(Get-Process dotnet -ErrorAction SilentlyContinue | ForEach-Object { $_.Id }) -join ','), ($newDotnet -join ','))

    # --- write then read back with *another* tool: no string surgery ---------
    # The reader is `project_search_file_contents`, whose text-extension whitelist
    # is `gd/tscn/tres/cfg/godot/gdshader/md/txt/json/yaml/yml/xml/csv/ini`
    # (project_read_template.cpp:332-334), so the witness is a `.cfg` file written
    # by the tool under test - not a `.csproj`, which that reader deliberately does
    # not scan.
    $marker = 'mcp052-readback-marker'
    $resp = Invoke-Tool -Id 'c12_write_cfg' -Tool 'project_write_text_file' -Arguments @{ path = 'res://mcp052-readback.cfg'; content = ("key=" + $marker + "`n") } -Port_ $EditorPort
    $payload = Get-Payload $resp
    $cfgPath = Join-Path $LoopProject 'mcp052-readback.cfg'
    Check 'c12_cfg_written_for_the_readback' (($null -ne $payload) -and ([string]$payload.sha256 -ceq (Get-DiskSha $cfgPath))) `
        ("path={0} bytes={1} sha256={2}" -f $payload.path, $payload.bytes, $payload.sha256)
    $resp = Invoke-Tool -Id 'c13_read_back_with_a_search' -Tool 'project_search_file_contents' -Arguments @{ pattern = $marker; path = 'res://'; file_pattern = '*.cfg' } -Port_ $EditorPort
    $payload = Get-Payload $resp
    $hits = 0
    if ($null -ne $payload) { $hits = @($payload.matches).Count }
    Check 'c13_another_tool_reads_what_the_writer_wrote' ($hits -gt 0) `
        ("project_search_file_contents(pattern='{0}', file_pattern='*.cfg') = {1} hit(s); query='{2}'" -f $marker, $hits, $payload.query)
    Show-Step 'c13 response (read-back through another tool)' $resp
    Stop-McpEngine -Handle $monoHandle -Name 'mono-editor'
    $monoHandle = $null

    # -------------------------------------------------------------------------
    #  Phase D: the game endpoint serves the two added tools as well.
    # -------------------------------------------------------------------------
    $gameHandle = Start-McpEngine -Engine $MonoEngine -Project $LoopProject -Port_ $GamePort -Name 'mono-game'
    $ready = Wait-ForEndpoint -Port_ $GamePort -TimeoutMs $ReadyTimeoutMs
    Check 'phase_d_game_endpoint_ready' $ready ("mono game answered GET /mcp on {0}" -f $GamePort)
    $listD = Invoke-Json -Id 'd1_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port_ $GamePort
    $namesD = Get-ToolNames $listD
    Check 'd2_game_serves_both_added_tools' (($namesD -contains 'project_build_csharp') -and ($namesD -contains 'project_write_text_file')) `
        ("live game tools/list = {0} tool(s); added present={1}" -f $namesD.Count, ((@($namesD | Where-Object { $addedNames -contains $_ })) -join ', '))
    Check 'd2b_game_live_count_is_the_contract_view' ($namesD.Count -eq $gameExpectedCount) `
        ("live game={0} derived game view={1} (contract {2})" -f $namesD.Count, $gameExpectedCount, $contractNames.Count)
    foreach ($entry in @($contractBuild, $contractWrite)) {
        $live = Get-ToolEntry $listD ([string]$entry.name)
        $same = ($null -ne $live) -and ([string]$live.description -ceq [string]$entry.description)
        $schemaSame = $false
        if ($null -ne $live) {
            $liveSchema = ConvertTo-Json -InputObject $live.inputSchema -Depth 30 -Compress
            $wantSchema = ConvertTo-Json -InputObject $entry.inputSchema -Depth 30 -Compress
            $schemaSame = ($liveSchema -ceq $wantSchema)
        }
        Check ("d3_{0}_verbatim_on_the_game" -f [string]$entry.name) ($same -and $schemaSame) `
            ("description={0} inputSchema={1}" -f $same, $schemaSame)
    }
} finally {
    Stop-McpEngine -Handle $gameHandle -Name 'mono-game'
    Stop-McpEngine -Handle $monoHandle -Name 'mono-editor'
    Stop-McpEngine -Handle $plainHandle -Name 'plain-editor'
}

$portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence

$logFile = Join-Path $Ev 'evidence.log.txt'
$summary = @()
foreach ($entry in $script:Checks) {
    $entryTag = if ($entry.pass) { 'PASS' } else { 'FAIL' }
    $summary += ("[{0}] {1} :: {2}" -f $entryTag, $entry.id, $entry.evidence)
}
$summary += ''
$summary += '--- response files (bytes / sha256) ---'
foreach ($step in $script:StepHashes) {
    $summary += ("{0} :: {1} bytes :: {2}" -f $step.id, $step.bytes, $step.sha256)
}
Write-McpUtf8NoBom -Path $logFile -Text (($summary -join "`r`n") + "`r`n")
$resultsFile = Join-Path $Ev 'results.json'
Write-McpUtf8NoBom -Path $resultsFile -Text (ConvertTo-Json -InputObject @{ checks = $script:Checks; responses = $script:StepHashes } -Depth 6)

$passed = @($script:Checks | Where-Object { $_.pass }).Count
$total = $script:Checks.Count
Write-Host ''
Write-Host ("TASK-052 added tools evidence: {0}/{1} checks passed; evidence in {2}" -f $passed, $total, $Ev)
Write-Host ("log sha256 = {0}" -f (Get-FileHash -Algorithm SHA256 -Path $logFile).Hash.ToLower())
if ($passed -ne $total) {
    foreach ($entry in $script:Checks) { if (-not $entry.pass) { Write-Host ("  FAILED {0} :: {1}" -f $entry.id, $entry.evidence) } }
    exit 1
}
exit 0
