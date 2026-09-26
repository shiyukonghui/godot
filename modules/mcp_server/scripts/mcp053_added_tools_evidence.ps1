# =============================================================================
#  mcp053_added_tools_evidence.ps1 -- TASK-053 section 1 and 2, the live evidence
#  of the error-code re-judgement, the two added tools and M-5's sampling stride.
#
#  It answers gate 2 of the PLAYBOOK for this batch:
#
#    * the three classes of evidence per tool (success / missing-or-mistyped
#      parameter / underlying failure), each a real request and a real response
#      written with `curl.exe -o` and hashed;
#    * one cross-tool end-to-end chain per added tool:
#        - `project_validate_scripts`: the same four files answered one-by-one by
#          the *singular* `project_validate_script` (which refuses the C# file
#          with -32000) and in one call by the plural tool (which classifies it
#          `language_unavailable`), plus the whole project's bytes before/after;
#        - `editor_set_node_script_batch`: attach -> `editor_save_scene` ->
#          `project_read_scene_file_content` (an *independent* reader of the
#          bytes on disk); then `keep_existing` (nothing moves),
#          `keep_existing:false` (the replacement names what it replaced), a
#          refusal (rolled back, named) and the abstract-script refusal whose
#          read-back is the only thing that catches it;
#    * M-5: the default call compared **byte for byte** (sha256) with the
#      pre-change baseline captured by `mcp053_m5_baseline_capture.ps1` on the
#      engine of the previous revision, and the same call at stride 10 with its
#      point count and byte count next to it.
#
#  Phases (each phase owns its engine process; the scratch project is one):
#
#    A  the plain (non-mono) editor on 9888: the contract entries, the
#       re-judged refusal, both added tools, the cross-tool chains;
#    B  the plain *game* process on 9889: what a game endpoint serves, the M-5
#       default/stride comparison, and the plural validate tool's
#       capability answer for a `.cs` file in a build without C#;
#    C  the mono editor on 9888: the same `.cs` file now gets a *real* verdict
#       (`ok` / `invalid`), which is what makes
#       `language_unavailable` a statement about the build and not a blanket
#       refusal.
#
#  Port discipline: the user's editor on 9877 is never started, killed or
#  restarted - only observed, before and after - and only the two test ports
#  9888 / 9889 are used.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp053_added_tools_evidence.ps1
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
$MapPath = Join-Path $RepoRoot 'modules\mcp_server\docs\tool-rename-map.json'
$BaselinePath = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task053\m5-baseline\baseline.json'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$UserPort = 9877

$Root = Join-Path $env:TEMP 'mcp053'
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Project = Join-Path $Root 'proj053'

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

function Get-ErrorDataField {
    param([string]$Text, [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        $envelope = ConvertFrom-Json $Text
        if ($null -eq $envelope.error) { return $null }
        if ($null -eq $envelope.error.data) { return $null }
        return $envelope.error.data.$Field
    } catch { return $null }
}

function Wait-ForEndpoint {
    param([int]$Port_, [int]$TimeoutMs)
    # TASK-054: the probe file is removed before every attempt and `curl` has to
    # exit 0. A *failed* `curl.exe -o` does not rewrite the file (curl never
    # opens the output on a refused connection), so the old version parsed the
    # previous phase's body and answered "ready" while the mono editor was still
    # loading - measured as `curl_exit=7 bytes=0` on phase C's first request.
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
Write-Host ' TASK-053: error-code re-judgement, the two added tools and'
Write-Host '           M-5 sample_stride'
Write-Host '============================================================='

foreach ($pair in @(@('plain', $PlainEngine), @('mono', $MonoEngine))) {
    if (-not (Test-Path $pair[1])) { Write-Host ("FATAL: {0} engine not found: {1}" -f $pair[0], $pair[1]); exit 2 }
}
foreach ($file in @($ContractPath, $AddedManifest, $MapPath, $BaselinePath)) {
    if (-not (Test-Path $file)) { Write-Host ("FATAL: required file not found: {0}" -f $file); exit 2 }
}

Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

$headSha = ((& git -C $RepoRoot rev-parse --short=9 HEAD) -join '').Trim()
$plainVersion = ((& $PlainEngine --version 2>$null) -join ' ').Trim()
$monoVersion = ((& $MonoEngine --version 2>$null) -join ' ').Trim()
# TASK-072 (D130): same single judge as mcp052 - an anchor is not "the binary
# prints HEAD". Structural equivalence (ancestor + non-compiling diff) passes;
# a diff that contains a compile input still fails. The evidence line keeps the
# reported anchor, HEAD, the criterion and the full diff list.
$plainAnchor = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $plainVersion -HeadSha $headSha
$monoAnchor = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $monoVersion -HeadSha $headSha
Check 'engines_match_head' (($plainAnchor.Ok) -and ($monoAnchor.Ok)) `
    (("plain --version='{0}' | {1}" -f $plainVersion, $plainAnchor.Summary) + ' || ' + `
     ("mono --version='{0}' | {1}" -f $monoVersion, $monoAnchor.Summary))
Check 'mono_engine_is_the_mono_build' ($monoVersion.Contains('.mono.')) ("mono --version='{0}'" -f $monoVersion)

# --- the contract's own numbers, derived and not written down ---------------
$contract = ConvertFrom-Json (Read-TextShared $ContractPath)
$contractNames = @($contract.result.tools | ForEach-Object { [string]$_.name })
$addedNames = @($contract._meta.added_tools | ForEach-Object { [string]$_ })
# TASK-064 D-8: this check used to pin the literal `175`. The contract is
# `171 ported + _meta.added_count` (the formula `accept_m1.ps1` and
# `check_tool_groups.py --completeness` both assert), so the expectation is now
# derived from the contract's own `_meta` instead of a number that has to be
# hand-edited every time a legitimate entry is appended (TASK-063 appended
# `editor_set_node_property_updates`: 175 -> 176, and the pinned 175 went red
# although every tool this script is about was still there). The literal 171
# half stays a checked literal on purpose: it is the ported-entry count GDR-17
# fixes, so a contract that silently lost a ported entry (and therefore still
# satisfied `count == len(result.tools)`) is still caught here.
$portedCount = 171
Check 'contract_is_ported_plus_added_entries' `
    (($contractNames.Count -eq ($portedCount + $addedNames.Count)) -and ($addedNames.Count -eq [int]$contract._meta.added_count) -and ([int]$contract._meta.count -eq $contractNames.Count)) `
    ("_meta.count={0} contract entries={1} = {2} ported + {3} added (derived; the pinned 175 is gone - TASK-064 D-8)" -f $contract._meta.count, $contractNames.Count, $portedCount, $addedNames.Count)
# TASK-064 D-8: the same de-pinning for the added list itself. This check used
# to require exactly the four names of TASK-052+TASK-053; TASK-063's legitimate
# fifth append (`editor_set_node_property_updates`, manifest order last) turned
# it red. The expectation is now the manifest `docs/tool-groups-added.json`, and
# the two names this task is about are still required at positions 2 and 3.
$addedManifestDoc = ConvertFrom-Json (Read-TextShared $AddedManifest)
$addedManifestNames = @()
foreach ($group in @($addedManifestDoc.groups)) { foreach ($tool in @($group.tools)) { $addedManifestNames += [string]$tool } }
Check 'contract_meta_added_tools_is_the_manifest' `
    (($addedNames.Count -eq [int]$contract._meta.added_count) -and `
     (($addedNames -join ",") -ceq ($addedManifestNames -join ",")) -and `
    # validate calls, instead of making this a race (TASK-055 hit it once).
    Start-Sleep -Milliseconds 1500
    $treeShaBefore = Get-ProjectTreeSha $Project
    $pathsArgs = @{ paths = @('res://scripts/valid.gd', 'res://scripts/broken.gd', 'res://scripts/legit.cs', 'res://shader.gdshader') }
    & {
        $resp = Invoke-Tool -Id 'a10_validate_scripts_mixed' -Tool 'project_validate_scripts' -Arguments $pathsArgs -Port_ $EditorPort
        $payload = Get-Payload $resp
        $validItem = Get-ItemByPath $payload 'res://scripts/valid.gd'
        $brokenItem = Get-ItemByPath $payload 'res://scripts/broken.gd'
        $csItem = Get-ItemByPath $payload 'res://scripts/legit.cs'
        $shaderItem = Get-ItemByPath $payload 'res://shader.gdshader'
        $countersOk = ($payload.count -eq 4) -and ($payload.valid_count -eq 1) -and ($payload.invalid_count -eq 1) -and ($payload.unavailable_count -eq 2) `
            -and ($payload.returned -eq 4) -and ($payload.errors_only -eq $false) -and ($payload.truncated -eq $false) -and ($payload.dropped -eq 0)
        $itemsOk = ($null -ne $validItem) -and ($validItem.category -ceq 'ok') -and ($validItem.valid -eq $true) `
            -and ($null -ne $brokenItem) -and ($brokenItem.category -ceq 'invalid') -and ($brokenItem.valid -eq $false) -and ([string]$brokenItem.error_text).StartsWith('ERR_') `
            -and ($null -ne $csItem) -and ($csItem.category -ceq 'language_unavailable') -and ($csItem.valid -eq $false) -and ([string]$csItem.message).Contains('not parsed or compiled') `
            -and ($null -ne $shaderItem) -and ($shaderItem.category -ceq 'language_unavailable')
        Check 'a10_validate_scripts_classifies_three_categories' ($countersOk -and $itemsOk) `
            ("count={0} valid={1} invalid={2} unavailable={3}; valid.gd={4} broken.gd={5}/{6} legit.cs={7} shader.gdshader={8}" -f `
                $payload.count, $payload.valid_count, $payload.invalid_count, $payload.unavailable_count, `
                $validItem.category, $brokenItem.category, $brokenItem.error_text, $csItem.category, $shaderItem.category)
        Show-Step 'a10 response (mixed batch)' $resp
        Check 'a10b_the_ok_item_is_a_verdict_not_a_guess' (([string]$validItem.language -ceq 'gd') -and ([string]$validItem.message).Contains('compiles')) `
            ("language={0} message='{1}'" -f $validItem.language, $validItem.message)
    }
    & {
        $resp = Invoke-Tool -Id 'a11_validate_scripts_errors_only' -Tool 'project_validate_scripts' `
            -Arguments @{ paths = $pathsArgs.paths; include_errors_only = $true } -Port_ $EditorPort
        $payload = Get-Payload $resp
        Check 'a11_errors_only_filters_the_list_not_the_counters' `
            (($payload.errors_only -eq $true) -and ($payload.returned -eq 3) -and ($payload.count -eq 4) -and ($payload.valid_count -eq 1) -and ($payload.unavailable_count -eq 2)) `
            ("errors_only={0} returned={1} count={2} valid={3} invalid={4} unavailable={5}" -f `
                $payload.errors_only, $payload.returned, $payload.count, $payload.valid_count, $payload.invalid_count, $payload.unavailable_count)
    }
    & {
        $resp = Invoke-Tool -Id 'a12_validate_scripts_scan' -Tool 'project_validate_scripts' -Arguments @{} -Port_ $EditorPort
        $payload = Get-Payload $resp
        $scanned = @($payload.results | ForEach-Object { [string]$_.path })
        $counterSum = ([int]$payload.valid_count + [int]$payload.invalid_count + [int]$payload.unavailable_count)
        $onlyScripts = (@($scanned | Where-Object { -not ($_.EndsWith('.gd') -or $_.EndsWith('.cs')) }).Count -eq 0)
        Check 'a12_scan_counts_every_script_of_the_project' `
            (($payload.count -eq $counterSum) -and ($payload.count -ge 6) -and $onlyScripts -and ($payload.limits.max_scripts -eq 64) -and ($payload.returned -eq $payload.count)) `
            ("count={0} valid+invalid+unavailable={1} max_scripts={2} returned={3} truncated={4} dropped={5} paths=[{6}]" -f `
                $payload.count, $counterSum, $payload.limits.max_scripts, $payload.returned, $payload.truncated, $payload.dropped, ($scanned -join ', '))
        Show-Step 'a12 response (no paths = scan)' $resp
    & {
        $singular = Invoke-Tool -Id 'a18_singular_validate_cs' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/legit.cs' } -Port_ $EditorPort
        $plural = Invoke-Tool -Id 'a19_plural_validate_cs' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/legit.cs') } -Port_ $EditorPort
        $pluralPayload = Get-Payload $plural
        $pluralItem = Get-ItemByPath $pluralPayload 'res://scripts/legit.cs'
        $sameMessage = ($null -ne $pluralItem) -and (([string]$pluralItem.message) -ceq (Get-ErrorMessage $singular))
        Check 'a18_the_two_validate_tools_agree_on_the_cs_file' `
            (((Get-ErrorCode $singular) -eq -32000) -and ($pluralPayload.unavailable_count -eq 1) -and ($pluralItem.valid -eq $false) -and $sameMessage) `
            ("singular code={0} message='{1}'; plural category={2} valid={3} same_message={4}" -f `
                (Get-ErrorCode $singular), (Get-ErrorMessage $singular), $pluralItem.category, $pluralItem.valid, $sameMessage)
        Check 'a19_no_valid_false_is_ever_published_for_the_cs_file' (($null -ne $pluralItem) -and ($pluralItem.category -ceq 'language_unavailable') -and (-not ($pluralItem.PSObject.Properties.Name -contains 'error_text'))) `
            ("category={0} suggestion='{1}'" -f $pluralItem.category, $pluralItem.suggestion)
    }
    Check 'a20_the_validate_tools_wrote_nothing' ((Get-ProjectTreeSha $Project) -ceq $treeShaBefore) `
        ("project tree sha256 before={0} after={1}" -f $treeShaBefore, (Get-ProjectTreeSha $Project))

    # --- editor_set_node_script_batch ----------------------------------------
    & {
        $resp = Invoke-Tool -Id 'a21_open_scene' -Tool 'editor_open_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort
        Check 'a21_scene_opened' ((Get-ErrorCode $resp) -eq 0) ("code={0} payload={1}" -f (Get-ErrorCode $resp), (Get-Payload $resp).opened)
    }
    & {
        $resp = Invoke-Tool -Id 'a22_add_nodes' -Tool 'editor_add_nodes_batch' `
            -Arguments @{ nodes = @(@{ type = 'Node2D'; name = 'Mcp053A' }, @{ type = 'Node2D'; name = 'Mcp053B' }) } -Port_ $EditorPort
        $payload = Get-Payload $resp
        Check 'a22_two_nodes_added_to_the_edited_scene' (($null -ne $payload) -and ($payload.count -eq 2) -and ($payload.status -ceq 'ok')) `
            ("status={0} count={1}" -f $payload.status, $payload.count)
    }
    & {
        $resp = Invoke-Tool -Id 'a23_batch_attach' -Tool 'editor_set_node_script_batch' `
            -Arguments @{ script_path = 'res://scripts/valid.gd'; node_paths = @('Mcp053A', 'Mcp053B') } -Port_ $EditorPort
        $payload = Get-Payload $resp
        $attachedOk = ($null -ne $payload) -and ($payload.status -ceq 'ok') -and ($payload.count -eq 2) -and ($payload.keep_existing -eq $false) `
            -and (@($payload.attached).Count -eq 2) -and (@($payload.skipped).Count -eq 0) -and (@($payload.errors).Count -eq 0) `
            -and (@($payload.attached | Where-Object { $_.attached -ne $true }).Count -eq 0) `
            -and ((@($payload.attached | Where-Object { [string]$_.script_path -cne 'res://scripts/valid.gd' }).Count -eq 0))
        Check 'a23_batch_attach_reports_every_node_read_back' $attachedOk `
            ("status={0} count={1} attached=[{2}] skipped={3} previous=[{4}]" -f $payload.status, $payload.count, `
                (($payload.attached | ForEach-Object { ("{0}:{1}:{2}" -f $_.node_path, $_.attached, $_.script_path) }) -join ' '), `
                @($payload.skipped).Count, (($payload.attached | ForEach-Object { $_.previous_script_path }) -join ','))
        Show-Step 'a23 response (batch attach)' $resp
    }
    # The independent read-back: save the scene and read the bytes on disk with a
    # different tool. The script resource must appear once and be referenced
    # twice.
    & {
        $saveResp = Invoke-Tool -Id 'a24_save_scene' -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort
        Check 'a24_scene_saved' (((Get-ErrorCode $saveResp) -eq 0) -and ((Get-Payload $saveResp).saved -eq $true)) `
            ("saved={0} path={1}" -f (Get-Payload $saveResp).saved, (Get-Payload $saveResp).path)
        $readResp = Invoke-Tool -Id 'a25_read_scene_file' -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort
        $sceneText = (Get-Payload $readResp).content
        $extResourceRefs = ([regex]::Matches($sceneText, 'script = ExtResource\(')).Count
        $scriptPathHits = ([regex]::Matches([string]$sceneText, [regex]::Escape('res://scripts/valid.gd'))).Count
        Check 'a25_the_saved_scene_really_carries_the_script_twice' (($extResourceRefs -eq 2) -and ($scriptPathHits -ge 1)) `
            ("'script = ExtResource(' x{0}; 'res://scripts/valid.gd' x{1} (the file is read with project_read_scene_file_content, not with the writer)" -f $extResourceRefs, $scriptPathHits)
    }
    # keep_existing: nothing is replaced, and nothing moves on disk.
    $sceneShaBefore = Get-TextSha (Get-Payload (Invoke-Tool -Id 'a26_scene_before' -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort)).content
    & {
        $resp = Invoke-Tool -Id 'a27_keep_existing_skip' -Tool 'editor_set_node_script_batch' `
            -Arguments @{ script_path = 'res://scripts/other.gd'; node_paths = @('Mcp053A', 'Mcp053B'); keep_existing = $true } -Port_ $EditorPort
        $payload = Get-Payload $resp
        $skipOk = ($payload.status -ceq 'ok') -and ($payload.count -eq 0) -and (@($payload.attached).Count -eq 0) -and (@($payload.skipped).Count -eq 2) `
            -and (@($payload.skipped | Where-Object { -not ([string]$_.reason).Contains('keep_existing') }).Count -eq 0) `
            -and (@($payload.skipped | Where-Object { [string]$_.previous_script_path -cne 'res://scripts/valid.gd' }).Count -eq 0)
        Check 'a27_keep_existing_skips_and_names_the_kept_script' $skipOk `
            ("count={0} attached={1} skipped=[{2}]" -f $payload.count, @($payload.attached).Count, `
                (($payload.skipped | ForEach-Object { ("{0}:{1}" -f $_.node_path, $_.previous_script_path) }) -join ' '))
        Show-Step 'a27 response (keep_existing)' $resp
        $saveResp = Invoke-Tool -Id 'a28_save_after_skip' -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort
        $after = Get-Payload (Invoke-Tool -Id 'a29_scene_after_skip' -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort)
        Check 'a28_keep_existing_did_not_touch_the_scene' ((Get-TextSha $after.content) -ceq $sceneShaBefore) `
            ("scene text sha256 before={0} after={1} (saved again in between)" -f $sceneShaBefore, (Get-TextSha $after.content))
    }
    # keep_existing:false replaces, and says what it replaced.
    & {
        $resp = Invoke-Tool -Id 'a30_replace_existing' -Tool 'editor_set_node_script_batch' `
            -Arguments @{ script_path = 'res://scripts/other.gd'; node_paths = @('Mcp053A', 'Mcp053B') } -Port_ $EditorPort
        $payload = Get-Payload $resp
        $replaceOk = ($payload.count -eq 2) -and (@($payload.attached | Where-Object { [string]$_.previous_script_path -cne 'res://scripts/valid.gd' }).Count -eq 0) `
            -and (@($payload.attached | Where-Object { [string]$_.script_path -cne 'res://scripts/other.gd' }).Count -eq 0)
        Check 'a30_default_overwrites_and_names_the_previous_script' $replaceOk `
            ("attached=[{0}]" -f (($payload.attached | ForEach-Object { ("{0}:{1}->{2}" -f $_.node_path, $_.previous_script_path, $_.script_path) }) -join ' '))
        $saveResp = Invoke-Tool -Id 'a31_save_after_replace' -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort
        $readResp = Invoke-Tool -Id 'a32_read_after_replace' -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort
        $sceneText = [string](Get-Payload $readResp).content
        Check 'a32_the_file_on_disk_carries_the_new_script' `
            ((([regex]::Matches($sceneText, [regex]::Escape('res://scripts/other.gd'))).Count -ge 1) -and (([regex]::Matches($sceneText, [regex]::Escape('res://scripts/valid.gd'))).Count -eq 0)) `
            ("other.gd x{0}; valid.gd x{1}" -f ([regex]::Matches($sceneText, [regex]::Escape('res://scripts/other.gd'))).Count, ([regex]::Matches($sceneText, [regex]::Escape('res://scripts/valid.gd'))).Count)
    }
    # A refusal: a node that is not there, all-or-nothing.
    & {
        $resp = Invoke-Tool -Id 'a33_missing_node' -Tool 'editor_set_node_script_batch' `
            -Arguments @{ script_path = 'res://scripts/valid.gd'; node_paths = @('Mcp053A', 'Nope') } -Port_ $EditorPort
        $batch = Get-ErrorDataField $resp 'batch'
        Check 'a33_missing_node_rolls_back_and_names_it' `
            (((Get-ErrorCode $resp) -eq -32001) -and ($batch.status -ceq 'rolled_back') -and ($batch.rolled_back -eq $true) -and ($batch.on_error -ceq 'all_or_nothing') -and `
             ($batch.count -eq 0) -and (@($batch.attached).Count -eq 0) -and (@($batch.errors).Count -eq 1) -and ([string]$batch.errors[0].node_path -ceq 'Nope') -and ([int]$batch.errors[0].index -eq 1)) `
            ("code={0} status={1} rolled_back={2} on_error={3} errors=[{4}] reverted={5}" -f (Get-ErrorCode $resp), $batch.status, $batch.rolled_back, $batch.on_error, `
                (($batch.errors | ForEach-Object { ("{0}:{1}" -f $_.index, $_.node_path) }) -join ' '), @($batch.reverted).Count)
        Show-Step 'a33 response (rolled-back refusal)' $resp
        $saveResp = Invoke-Tool -Id 'a34_save_after_refusal' -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort
        $readResp = Invoke-Tool -Id 'a35_read_after_refusal' -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort
        $sceneText = [string](Get-Payload $readResp).content
        Check 'a35_the_refusal_left_the_scene_alone' `
            ((([regex]::Matches($sceneText, [regex]::Escape('res://scripts/other.gd'))).Count -ge 1) -and (([regex]::Matches($sceneText, [regex]::Escape('res://scripts/valid.gd'))).Count -eq 0)) `
            ("after the refused batch the file still carries other.gd (x{0}) and no valid.gd (x{1})" -f ([regex]::Matches($sceneText, [regex]::Escape('res://scripts/other.gd'))).Count, ([regex]::Matches($sceneText, [regex]::Escape('res://scripts/valid.gd'))).Count)
    }
    # A refusal the *read-back* is what catches: an abstract script.
    & {
        $resp = Invoke-Tool -Id 'a36_abstract_script' -Tool 'editor_set_node_script_batch' `
            -Arguments @{ script_path = 'res://scripts/abstract.gd'; node_paths = @('Mcp053A', 'Mcp053B') } -Port_ $EditorPort
        $batch = Get-ErrorDataField $resp 'batch'
        Check 'a36_abstract_script_is_refused_by_the_read_back' `
            (((Get-ErrorCode $resp) -eq -32000) -and ($batch.status -ceq 'rolled_back') -and ($batch.rolled_back -eq $true) -and (@($batch.attached).Count -eq 0) -and (@($batch.errors).Count -eq 1) -and ([int]$batch.errors[0].index -eq 0)) `
            ("code={0} message='{1}' batch.errors=[{2}] reverted={3}" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp), `
                (($batch.errors | ForEach-Object { ("{0}:{1}" -f $_.index, $_.reason) }) -join ' '), @($batch.reverted).Count)
        Show-Step 'a36 response (abstract script)' $resp
        $saveResp = Invoke-Tool -Id 'a37_save_after_abstract' -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort
        $readResp = Invoke-Tool -Id 'a38_read_after_abstract' -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://scenes/main.tscn' } -Port_ $EditorPort
        $sceneText = [string](Get-Payload $readResp).content
        Check 'a38_nothing_was_attached' (([regex]::Matches($sceneText, [regex]::Escape('abstract.gd'))).Count -eq 0) `
            ("'abstract.gd' occurrences in the saved scene = {0}" -f ([regex]::Matches($sceneText, [regex]::Escape('abstract.gd'))).Count)
    }
    # The argument surface.
    $argCases = @(
        @{ id = 'a39_missing_script_path'; args = @{ node_paths = @('Mcp053A') }; code = -32602; want = 'script_path' },
        @{ id = 'a40_empty_node_paths'; args = @{ script_path = 'res://scripts/valid.gd'; node_paths = @() }; code = -32602; want = 'at least one node' },
        @{ id = 'a41_wrong_node_paths_type'; args = @{ script_path = 'res://scripts/valid.gd'; node_paths = 'Mcp053A' }; code = -32602; want = 'array of strings' },
        @{ id = 'a42_bad_keep_existing'; args = @{ script_path = 'res://scripts/valid.gd'; node_paths = @('Mcp053A'); keep_existing = 'yes' }; code = -32602; want = 'boolean' },
        @{ id = 'a43_relative_script_path'; args = @{ script_path = 'user://x.gd'; node_paths = @('Mcp053A') }; code = -32602; want = '' },
        @{ id = 'a44_unknown_param'; args = @{ script_path = 'res://scripts/valid.gd'; node_paths = @('Mcp053A'); nope = 1 }; code = -32602; want = 'Unknown parameter' },
        @{ id = 'a45_missing_script_file'; args = @{ script_path = 'res://scripts/no_such.gd'; node_paths = @('Mcp053A') }; code = -32001; want = 'no_such.gd' }
    )
    foreach ($case in $argCases) {
        $resp = Invoke-Tool -Id $case.id -Tool 'editor_set_node_script_batch' -Arguments $case.args -Port_ $EditorPort
        $ok = (Get-ErrorCode $resp) -eq $case.code
        if ([string]$case.want -ne '') { $ok = $ok -and (((Get-ErrorMessage $resp).Contains($case.want)) -or ((Get-Suggestion $resp).Contains($case.want))) }
        Check ($case.id + '_refused') $ok ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp), (Get-Suggestion $resp))
    }

    Stop-McpEngine -Handle $plainHandle -Name 'plain-editor'
    $plainHandle = $null

    # -------------------------------------------------------------------------
    #  Phase B: the plain game process on 9889.
    # -------------------------------------------------------------------------
    $gameHandle = Start-McpEngine -Engine $PlainEngine -ProjectPath $Project -Port_ $GamePort -Name 'plain-game'
    Check 'phase_b_game_ready' (Wait-ForEndpoint -Port_ $GamePort -TimeoutMs $ReadyTimeoutMs) ("plain game answered GET /mcp on {0}" -f $GamePort)

    $listB = Invoke-Json -Id 'b01_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port_ $GamePort
    $namesB = Get-ToolNames $listB
    Check 'b02_game_live_count_is_the_contract_view' ($namesB.Count -eq $gameExpectedCount) `
        ("live 9889 = {0} tool(s), derived game view = {1} (contract {2} entries)" -f $namesB.Count, $gameExpectedCount, $contractNames.Count)
    Check 'b03_the_scope_split_is_visible_on_the_wire' `
        (($namesB.Contains('project_validate_scripts')) -and (-not $namesB.Contains('editor_set_node_script_batch')) -and ($namesB.Contains('running_game_get_node_property_samples'))) `
        ("9889 serves project_validate_scripts={0} editor_set_node_script_batch={1} running_game_get_node_property_samples={2}" -f `
            $namesB.Contains('project_validate_scripts'), $namesB.Contains('editor_set_node_script_batch'), $namesB.Contains('running_game_get_node_property_samples'))
    & {
        $live = Get-ToolEntry $listB 'running_game_get_node_property_samples'
        $want = $contractEntry['running_game_get_node_property_samples']
        $schemaSame = ((ConvertTo-Json -InputObject $live.inputSchema -Depth 30 -Compress) -ceq (ConvertTo-Json -InputObject $want.inputSchema -Depth 30 -Compress))
        $hasStride = @($live.inputSchema.properties.PSObject.Properties.Name) -contains 'sample_stride'
        Check 'b04_the_m5_schema_is_the_contract_entry_verbatim' ($schemaSame -and $hasStride) `
            ("description identical={0}; inputSchema identical={1}; sample_stride member={2}" -f ([string]$live.description -ceq [string]$want.description), $schemaSame, $hasStride)
    }
    & {
        $resp = Invoke-Tool -Id 'b05_editor_tool_on_game' -Tool 'editor_set_node_script_batch' `
            -Arguments @{ script_path = 'res://scripts/valid.gd'; node_paths = @('A') } -Port_ $GamePort
        Check 'b05_the_editor_tool_is_32601_on_9889' ((Get-ErrorCode $resp) -eq -32601) `
            ("code={0} message='{1}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp))
    }
    # The `.cs` answer is a statement about the *build*: the same file, the same
    # tool, a plain build -> unavailable; phase C repeats it on the mono build.
    & {
        $resp = Invoke-Tool -Id 'b06_validate_cs_in_a_plain_build' -Tool 'project_validate_scripts' `
            -Arguments @{ paths = @('res://scripts/legit.cs') } -Port_ $GamePort
        $payload = Get-Payload $resp
        $item = Get-ItemByPath $payload 'res://scripts/legit.cs'
        Check 'b06_plain_game_build_says_language_unavailable' `
            (($payload.unavailable_count -eq 1) -and ($item.category -ceq 'language_unavailable') -and ([string]$item.suggestion).Contains('module_mono_enabled=yes')) `
            ("category={0} valid={1} suggestion='{2}'" -f $item.category, $item.valid, $item.suggestion)
    }
    # M-5: the default response is byte-identical to the pre-change capture.
    & {
        $arguments = [ordered]@{ node_path = '/root/Main'; properties = @('name'); frame_count = 5; frame_interval = 1 }
        $resp = Invoke-Tool -Id 'b07_m5_default_matches_the_pre_change_baseline' -Tool 'running_game_get_node_property_samples' -Arguments $arguments -Port_ $GamePort
        $payload = Get-Payload $resp
        $sha = $script:StepHashes[$script:StepHashes.Count - 1].sha256
        $sameBytes = ($sha -ceq [string]$baseline.response_sha256)
        $sameShape = ($payload.frame_count -eq 5) -and (@($payload.samples).Count -eq 5) `
            -and (-not ($payload.PSObject.Properties.Name -contains 'sample_stride')) `
            -and (-not ($payload.PSObject.Properties.Name -contains 'observed_count'))
        Check 'b07_default_response_is_byte_identical_to_the_pre_change_capture' ($sameBytes -and $sameShape) `
            ("response sha256 {0} == baseline {1}; frame_count={2} samples={3} extra keys absent={4} bytes={5} vs baseline bytes={6}" -f `
                $sha, $baseline.response_sha256, $payload.frame_count, @($payload.samples).Count, $sameShape, $script:StepHashes[$script:StepHashes.Count - 1].bytes, $baseline.response_bytes)
        Show-Step 'b07 response (default)' $resp
    }
    # ... and the same series with one explicit stride next to it.
    $full = $null
    & {
        $arguments = [ordered]@{ node_path = '/root/Main'; properties = @('name'); frame_count = 180; frame_interval = 1 }
        $resp = Invoke-Tool -Id 'b08_m5_180_no_stride' -Tool 'running_game_get_node_property_samples' -Arguments $arguments -Port_ $GamePort -MaxTimeSec 120
        $full = Get-Payload $resp
        $step = $script:StepHashes[$script:StepHashes.Count - 1]
        Check 'b08_180_observations_are_180_returned_points' (($full.frame_count -eq 180) -and (@($full.samples).Count -eq 180)) `
            ("frame_count={0} samples={1} bytes={2} sha256={3} (no stride member: the default path)" -f $full.frame_count, @($full.samples).Count, $step.bytes, $step.sha256)
    }
    & {
        $arguments = [ordered]@{ node_path = '/root/Main'; properties = @('name'); frame_count = 180; frame_interval = 1; sample_stride = 10 }
        $resp = Invoke-Tool -Id 'b09_m5_180_stride_10' -Tool 'running_game_get_node_property_samples' -Arguments $arguments -Port_ $GamePort -MaxTimeSec 120
        $payload = Get-Payload $resp
        $step = $script:StepHashes[$script:StepHashes.Count - 1]
        $fullStep = $script:StepHashes[$script:StepHashes.Count - 2]
        $points = @($payload.samples).Count
        $frames = @($payload.samples | ForEach-Object { [int]$_.frame })
        $strideOk = ($points -eq 18) -and ($payload.frame_count -eq 18) -and ($payload.observed_count -eq 180) -and ($payload.sample_stride -eq 10) `
            -and ($frames[0] -eq 0) -and ($frames[1] -eq 10) -and ($frames[17] -eq 170) -and ($step.bytes -lt $fullStep.bytes)
        Check 'b09_stride_10_returns_18_of_180_observations' $strideOk `
            ("frame_count={0} observed_count={1} sample_stride={2} frames=[{3} ... {4}] bytes={5} vs {6} without a stride ({7}% smaller)" -f `
                $payload.frame_count, $payload.observed_count, $payload.sample_stride, $frames[0], $frames[$points - 1], $step.bytes, $fullStep.bytes, `
                [int](100 - [math]::Round(100.0 * $step.bytes / $fullStep.bytes)))
        Show-Step 'b09 response (stride 10)' $resp
    }
    & {
        $resp = Invoke-Tool -Id 'b10_stride_zero' -Tool 'running_game_get_node_property_samples' `
            -Arguments @{ node_path = '/root/Main'; properties = @('name'); sample_stride = 0 } -Port_ $GamePort
        Check 'b10_stride_zero_is_32602' (((Get-ErrorCode $resp) -eq -32602) -and ((Get-ErrorMessage $resp).Contains('at least 1'))) `
            ("code={0} message='{1}' suggestion='{2}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp), (Get-Suggestion $resp))
    }
    & {
        $resp = Invoke-Tool -Id 'b11_stride_wrong_type' -Tool 'running_game_get_node_property_samples' `
            -Arguments @{ node_path = '/root/Main'; properties = @('name'); sample_stride = 'every' } -Port_ $GamePort
        Check 'b11_stride_wrong_type_is_32602' (((Get-ErrorCode $resp) -eq -32602) -and ((Get-ErrorMessage $resp).Contains('integer'))) `
            ("code={0} message='{1}'" -f (Get-ErrorCode $resp), (Get-ErrorMessage $resp))
    }
    Stop-McpEngine -Handle $gameHandle -Name 'plain-game'
    $gameHandle = $null

    # -------------------------------------------------------------------------
    #  Phase C: the mono editor on 9888 - the `.cs` file, after TASK-055.
    #
    #  TASK-053 measured here that a syntax-error `.cs` was reported `ok` /
    #  `valid: true` (the `CSharpScript::reload()` limitation recorded as
    #  D-053-3). TASK-054 stopped the lie (no verdict: `unverifiable` + -32000)
    #  and TASK-055 (D112) replaced that with a **real verdict**: the engine now
    #  exposes `CSharpScript::is_source_newer_than_assembly()` next to the public
    #  `Script::is_script_valid()`, and the project-level half comes from the
    #  diagnostics `project_build_csharp` records.
    #
    #  This project has **no `.csproj` and no build**, so the honest answer for
    #  both files is `not_compiled` (nothing compiled this source), never
    #  `invalid`: the engine has no C# compiler, so "nothing built it" must not
    #  be published as "it does not compile". The probe ids and response files
    #  keep their names so the before/after history stays traceable.
    # -------------------------------------------------------------------------
    $monoHandle = Start-McpEngine -Engine $MonoEngine -ProjectPath $Project -Port_ $EditorPort -Name 'mono-editor' -Editor
    Check 'phase_c_mono_editor_ready' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) ("mono editor answered GET /mcp on {0}" -f $EditorPort)
    & {
        $listC = Invoke-Json -Id 'c01_tools_list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port_ $EditorPort
        Check 'c01_mono_editor_serves_the_same_contract_view' ((Get-ToolNames $listC).Count -eq $editorExpectedCount) `
            ("live mono 9888 = {0} tool(s), derived editor view = {1}" -f (Get-ToolNames $listC).Count, $editorExpectedCount)
    }
    & {
        $resp = Invoke-Tool -Id 'c02_mono_valid_cs' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/legit.cs') } -Port_ $EditorPort
        $payload = Get-Payload $resp
        $item = Get-ItemByPath $payload 'res://scripts/legit.cs'
        Check 'c02_task055_an_unbuilt_cs_file_is_not_compiled_not_invalid' `
            (($payload.valid_count -eq 0) -and ($payload.invalid_count -eq 0) -and ($payload.not_compiled_count -eq 1) -and ($item.category -ceq 'not_compiled') -and ($null -eq $item.valid)) `
            ("valid_count={0} invalid_count={1} not_compiled_count={2} category={3} valid={4} message='{5}'" -f $payload.valid_count, $payload.invalid_count, $payload.not_compiled_count, $item.category, $item.valid, $item.message)
    Stop-McpEngine -Handle $gameHandle -Name 'plain-game'
    Stop-McpEngine -Handle $plainHandle -Name 'plain-editor'
}

$portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence
Check 'test_ports_released_after_run' (((Get-ListenerPid -Port_ $EditorPort) -eq -1) -and ((Get-ListenerPid -Port_ $GamePort) -eq -1)) `
    ("9888 owner={0}; 9889 owner={1}" -f (Get-ListenerPid -Port_ $EditorPort), (Get-ListenerPid -Port_ $GamePort))

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

# The durable half of the evidence: the request/response bodies of every step
# (small enough to commit, and the only place the *exact* wire bytes of this run
# exist), the ordered check list and the log. The bulk of a run lives in
# `%TEMP%`; this directory is what a later reader gets.
$RepoEvidence = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task053'
$RepoWire = Join-Path $RepoEvidence 'wire'
New-Item -ItemType Directory -Force -Path $RepoWire | Out-Null
Copy-Item -Path (Join-Path $Ev '*.json') -Destination $RepoWire -Force
Write-McpUtf8NoBom -Path (Join-Path $RepoEvidence 'evidence.log.txt') -Text (($summary -join "`r`n") + "`r`n")
Write-McpUtf8NoBom -Path (Join-Path $RepoEvidence 'results.json') -Text (ConvertTo-Json -InputObject @{ checks = $script:Checks; responses = $script:StepHashes } -Depth 6)

$passed = @($script:Checks | Where-Object { $_.pass }).Count
$total = $script:Checks.Count
Write-Host ''
Write-Host ("TASK-053 evidence: {0}/{1} checks passed; evidence in {2}" -f $passed, $total, $Ev)
Write-Host ("log sha256 = {0}" -f (Get-FileHash -Algorithm SHA256 -Path $logFile).Hash.ToLower())
if ($passed -ne $total) {
    foreach ($entry in $script:Checks) { if (-not $entry.pass) { Write-Host ("  FAILED {0} :: {1}" -f $entry.id, $entry.evidence) } }
    exit 1
}
exit 0