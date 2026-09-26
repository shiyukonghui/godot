# =============================================================================
#  mcp056_evidence.ps1 -- TASK-056: the live evidence of D1 and D3.
#
#  D1 (blocking, REPORT-AUDIT-ADDED): `project_validate_scripts` published
#  `"valid": false` for a `category=language_unavailable` item (the `.cs` file of
#  a build without the C# backend). It must publish `valid: null` plus `reason`,
#  exactly like `unverifiable` / `not_compiled`, and the singular tool must keep
#  refusing (no claim) with -32000.
#
#  D3 (cosmetic): the `command` field of `project_build_csharp` spelled the
#  executable `C:\Program Files\dotnet\/dotnet.exe` (two separators at the
#  junction). It must be one separator, with the same resolved file and the same
#  exit_code.
#
#  Phases:
#    plain -- a non-mono editor on 9888 answers the TASK-055 request
#             `plain-91-plural-cs` byte for byte (except the intended change),
#             so mcp056_pre_post_compare.py can diff it against the tracked
#             pre-fix record of docs/reports/evidence/task055/post/;
#    mono  -- a mono editor on 9888 builds a real C# project through
#             project_build_csharp and captures the `command` field.
#
#  Ports: 9888 only. 9877 is never bound, killed or restarted (netstat guard
#  before and after). Every process this script starts is stopped by it.
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp056_evidence.ps1
# =============================================================================

param(
    [ValidateSet('both', 'plain', 'mono')][string]$Phase = 'both',
    [string]$MonoEngine = '',
    [string]$PlainEngine = '',
    [int]$EditorPort = 9888,
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($MonoEngine)) { $MonoEngine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe' }
if ([string]::IsNullOrWhiteSpace($PlainEngine)) { $PlainEngine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe' }

$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$UserPort = 9877
$Root = Join-Path $env:TEMP 'mcp056'
$Ev = Join-Path $RepoRoot 'modules\mcp_server\docs\reports\evidence\task056'
$LogRoot = Join-Path $Root 'logs'
$Project = Join-Path $Root 'proj056'

. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Get-ListenerPid {
    param([int]$Port)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port + "\s")) {
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

# One request, its response stored byte for byte under <Id>.response.json.
function Invoke-Json {
    param([string]$Id, [string]$Json, [int]$Port_ = 9888, [int]$MaxTimeSec = 300)
    $bodyFile = Join-Path $Ev ($Id + '.request.json')
    $respFile = Join-Path $Ev ($Id + '.response.json')
    Write-McpUtf8NoBom -Path $bodyFile -Text ($Json + "`n")
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time $MaxTimeSec -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $curlExit = $LASTEXITCODE
    $bytes = @()
    if (Test-Path $respFile) { $bytes = [IO.File]::ReadAllBytes($respFile) }
    $text = ''
    if ($bytes.Count -gt 0) { $text = [Text.Encoding]::UTF8.GetString($bytes) }
    $sha = '<empty>'
    if ($bytes.Count -gt 0) { $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower() }
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
        if ($null -eq $envelope.error.data) { return '' }
        return [string]$envelope.error.data.suggestion
    } catch { return '' }
}

function Get-ItemByPath {
    param($Out, [string]$Path)
    foreach ($item in @($Out.results)) { if ([string]$item.path -ceq $Path) { return $item } }
    return $null
}

# The wire spelling of a JSON null in this server's own writer.
function Get-ValidJson {
    param($Item)
    if ($null -eq $Item) { return '<no item>' }
    return ($Item | ConvertTo-Json -Depth 3 -Compress)
}

function Wait-ForEndpoint {
    param([int]$Port_, [int]$TimeoutMs)
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
    param([string]$Engine, [string]$ProjectPath, [int]$Port_, [string]$Name, [switch]$Editor)
    $arguments = @('--headless')
    if ($Editor) { $arguments += '-e' }
    $arguments += @('--path', $ProjectPath, ("--mcp-port={0}" -f $Port_))
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

# ---------------------------------------------------------------------------
# The fixture. The plain phase replays the TASK-055 request verbatim, so the
# two scripts keep the names it used; the mono phase needs a real Godot.NET.Sdk
# project that `dotnet build` can compile.
# ---------------------------------------------------------------------------
function New-Mcp056Project {
    param([string]$Path)
    Remove-Item -Recurse -Force $Path -ErrorAction SilentlyContinue
    New-McpScratchProject -Path $Path -Name 'Mcp056Probe' -WithMainScene $true
    $scripts = Join-Path $Path 'scripts'
    New-Item -ItemType Directory -Force -Path $scripts | Out-Null
    $nupkgs = Join-Path $RepoRoot 'bin\GodotSharp\Tools\nupkgs'
    $nuget = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="Godot" value="$nupkgs" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
"@
    Write-McpUtf8NoBom -Path (Join-Path $Path 'NuGet.config') -Text $nuget
    $csproj = @"
<Project Sdk="Godot.NET.Sdk/4.8.0-dev">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <EnableDynamicLoading>true</EnableDynamicLoading>
  </PropertyGroup>
</Project>
"@
    Write-McpUtf8NoBom -Path (Join-Path $Path 'Mcp056Probe.csproj') -Text $csproj
    # File name and class name must agree case for case, or the SDK emits no
    # [ScriptPath] and the engine has no class for the path (TASK-055 section 8.2-1).
    Write-McpUtf8NoBom -Path (Join-Path $scripts 'Legit.cs') -Text "using Godot;`n`npublic partial class Legit : Node`n{`n}`n"
    Write-McpUtf8NoBom -Path (Join-Path $scripts 'plain.gd') -Text "extends Node`n`nfunc answer() -> int:`n`treturn 42`n"
}

function Clear-Mcp056State {
    param([string]$Path)
    $userDir = Join-Path $env:APPDATA 'Godot\app_userdata\Mcp056Probe'
    Remove-Item -Force (Join-Path $userDir 'mcp_csharp_build_state.json') -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path $Path '.godot\mono') -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
$userPidBefore = Get-ListenerPid -Port $UserPort
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
$plainVersion = ((& $PlainEngine --version 2>$null) -join ' ').Trim()
$monoVersion = '<not built>'
if (Test-Path $MonoEngine) { $monoVersion = ((& $MonoEngine --version 2>$null) -join ' ').Trim() }
$headSha = (& git -C $RepoRoot rev-parse HEAD).Trim()
Write-Host ("phase={0} git HEAD={1}" -f $Phase, $headSha)
Write-Host ("plain='{0}' mono='{1}'" -f $plainVersion, $monoVersion)

New-Mcp056Project -Path $Project
Clear-Mcp056State -Path $Project
Import-McpProject -Engine $PlainEngine -Path $Project -LogDirectory $LogRoot -Name 'import056' | Out-Null

# ===========================================================================
# Phase P -- D1 on the plain build (no C# backend, so `.cs` is
# `language_unavailable`; this is the exact TASK-055 probe).
# ===========================================================================
if ($Phase -ne 'mono') {
    $plainHandle = $null
    try {
        $plainHandle = Start-McpEngine -Engine $PlainEngine -ProjectPath $Project -Port_ $EditorPort -Name 'plain-editor' -Editor
        Check 'plain_editor_ready' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) ("plain editor answered on {0}" -f $EditorPort)

        $pluralArgs = @{ paths = @('res://scripts/Legit.cs', 'res://scripts/plain.gd') }
        $plural = Invoke-Json -Id 'plain-91-plural-cs' -Json (New-CallBody -Id 1 -Tool 'project_validate_scripts' -Arguments $pluralArgs) -Port_ $EditorPort
        $payload = Get-Payload $plural
        $csItem = Get-ItemByPath $payload 'res://scripts/Legit.cs'
        $gdItem = Get-ItemByPath $payload 'res://scripts/plain.gd'

        Check 'plural_cs_item_is_language_unavailable' `
            (($null -ne $csItem) -and ([string]$csItem.category -ceq 'language_unavailable') -and ([string]$csItem.language -ceq 'cs')) `
            ("category={0} language={1}" -f $csItem.category, $csItem.language)
        # The key has to be THERE and null: a missing key and a null key both read
        # as `false` in PowerShell, which is how the defect hid from a bool test.
        Check 'plural_cs_item_publishes_valid_as_json_null' `
            (($null -ne $csItem) -and ($csItem.PSObject.Properties.Name -contains 'valid') -and ($null -eq $csItem.valid)) `
            ("has_valid_key={0} valid={1}" -f ($csItem.PSObject.Properties.Name -contains 'valid'), $(if ($null -eq $csItem.valid) { 'null' } else { [string]$csItem.valid }))
        # The payload is a JSON string inside the envelope, so its quoting is
        # escaped on the wire: `\"valid\":null`.
        Check 'plural_cs_wire_text_carries_a_null_valid' `
            ($plural.Contains('\"valid\":null') -and (-not $plural.Contains('\"valid\":false,\"path\":\"res://scripts/Legit.cs\"'))) `
            ("contains_valid_null={0} contains_valid_false_for_the_item={1}" -f $plural.Contains('\"valid\":null'), $plural.Contains('\"valid\":false,\"path\":\"res://scripts/Legit.cs\"'))
        Check 'plural_cs_item_publishes_a_reason' `
            (($null -ne $csItem) -and ($csItem.PSObject.Properties.Name -contains 'reason') -and ([string]$csItem.reason).Contains('get_language_for_extension') -and ([string]$csItem.reason).Contains('ScriptServer::are_languages_initialized()')) `
            ("reason='{0}'" -f $csItem.reason)
        Check 'plural_cs_item_keeps_its_message_and_suggestion' `
            (([string]$csItem.message).Contains('not parsed or compiled') -and ([string]$csItem.suggestion).Contains('module_mono_enabled=yes')) `
            ("message='{0}' suggestion='{1}'" -f $csItem.message, $csItem.suggestion)
        Check 'plural_counters_still_add_up' `
            (([int64]$payload.count -eq 2) -and ([int64]$payload.valid_count -eq 1) -and ([int64]$payload.invalid_count -eq 0) -and ([int64]$payload.unavailable_count -eq 1) -and ([int64]$payload.unverifiable_count -eq 0) -and ([int64]$payload.not_compiled_count -eq 0) -and ([int64]$payload.count -eq ([int64]$payload.valid_count + [int64]$payload.invalid_count + [int64]$payload.unavailable_count + [int64]$payload.unverifiable_count + [int64]$payload.not_compiled_count))) `
            ("count={0} valid={1} invalid={2} unavailable={3} unverifiable={4} not_compiled={5}" -f $payload.count, $payload.valid_count, $payload.invalid_count, $payload.unavailable_count, $payload.unverifiable_count, $payload.not_compiled_count)
        Check 'plural_gd_item_is_still_a_real_verdict' `
            (($null -ne $gdItem) -and ([string]$gdItem.category -ceq 'ok') -and ($gdItem.valid -eq $true)) `
            ("category={0} valid={1}" -f $gdItem.category, $gdItem.valid)

        # The same request twice: the response is deterministic (and nothing the
        # first call did leaked into the second).
        $repeat = Invoke-Json -Id 'plain-91b-plural-cs-repeat' -Json (New-CallBody -Id 1 -Tool 'project_validate_scripts' -Arguments $pluralArgs) -Port_ $EditorPort
        $firstSha = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Ev 'plain-91-plural-cs.response.json')).Hash.ToLower()
        $repeatSha = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Ev 'plain-91b-plural-cs-repeat.response.json')).Hash.ToLower()
        Check 'the_same_request_answers_the_same_bytes' ($firstSha -ceq $repeatSha) ("first={0} repeat={1}" -f $firstSha, $repeatSha)

        # The singular tool answers the same file: it has no `valid` to publish,
        # so it refuses with -32000 and the same suggestion. The two tools must
        # agree on "no claim".
        $singular = Invoke-Tool -Id 'plain-90-singular-cs' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/Legit.cs' } -Port_ $EditorPort
        Check 'singular_tool_refuses_without_publishing_a_valid' `
            (((Get-ErrorCode $singular) -eq -32000) -and ((Get-ErrorMessage $singular).Contains('not parsed or compiled')) -and ((Get-Suggestion $singular).Contains('module_mono_enabled=yes')) -and (-not $singular.Contains('"valid"'))) `
            ("code={0} message='{1}'" -f (Get-ErrorCode $singular), (Get-ErrorMessage $singular))
        Check 'the_two_tools_agree_on_the_suggestion' `
            (($null -ne $csItem) -and (([string]$csItem.suggestion) -ceq (Get-Suggestion $singular))) `
            ("plural suggestion == singular suggestion: {0}" -f (($null -ne $csItem) -and (([string]$csItem.suggestion) -ceq (Get-Suggestion $singular))))
    } finally {
        Stop-McpEngine -Handle $plainHandle -Name 'plain-editor'
        $plainHandle = $null
    }
}

# ===========================================================================
# Phase M -- D3 on the mono build: a real `dotnet build` through the tool.
# ===========================================================================
if ($Phase -ne 'plain') {
    if (-not (Test-Path $MonoEngine)) {
        Check 'mono_engine_present' $false ("missing: {0}" -f $MonoEngine)
    } elseif (-not $monoVersion.Contains('.mono.')) {
        Check 'mono_engine_is_the_mono_build' $false ("--version='{0}'" -f $monoVersion)
    } else {
        $monoHandle = $null
        try {
            Clear-Mcp056State -Path $Project
            $monoHandle = Start-McpEngine -Engine $MonoEngine -ProjectPath $Project -Port_ $EditorPort -Name 'mono-editor' -Editor
            Check 'mono_editor_ready' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) ("mono editor answered on {0}" -f $EditorPort)

            $build = Invoke-Tool -Id 'mono-build-csharp' -Tool 'project_build_csharp' -Arguments @{ configuration = 'Debug'; timeout_ms = 300000 } -Port_ $EditorPort -MaxTimeSec 360
            $buildPayload = Get-Payload $build
            Check 'mono_build_succeeded' (($null -ne $buildPayload) -and ([int64]$buildPayload.exit_code -eq 0)) `
                ("exit_code={0}" -f $buildPayload.exit_code)
            Check 'mono_build_rescanned_or_reported' (($null -ne $buildPayload) -and ($null -ne $buildPayload.rescanned)) `
                ("rescanned={0} project_files=[{1}]" -f $buildPayload.rescanned, (@($buildPayload.project_files) -join ', '))

            $command = [string]$buildPayload.command
            $expectedExe = ''
            if ($null -ne (Get-Command dotnet -ErrorAction SilentlyContinue)) { $expectedExe = [string](Get-Command dotnet).Source }
            Check 'the_resolved_dotnet_path_itself_is_single_separator' `
                (($expectedExe.Length -gt 0) -and (-not ($expectedExe.Contains('/'))) -and (-not ($expectedExe.Contains('\/')))) `
                ("PATH dotnet = '{0}'" -f $expectedExe)
            Check 'build_command_has_no_mixed_separator' ((-not ($command -match '\\/')) -and (-not ($command -match '/\\'))) ("command='{0}'" -f $command)
            Check 'build_command_starts_with_the_native_dotnet_path' `
                (($expectedExe.Length -gt 0) -and ($command.StartsWith($expectedExe + ' '))) `
                ("command='{0}' expected_prefix='{1}'" -f $command, $expectedExe)
            Check 'build_command_reports_the_same_executable_as_commands_array' `
                ((@($buildPayload.commands).Count -eq 1) -and ([string]@($buildPayload.commands)[0] -ceq $command)) `
                ("commands=[{0}]" -f (@($buildPayload.commands) -join ' | '))
            $exeOnDisk = $false
            if ($expectedExe.Length -gt 0) { $exeOnDisk = (Test-Path $expectedExe) }
            Check 'the_reported_executable_really_exists' $exeOnDisk ("Test-Path '{0}' = {1}" -f $expectedExe, $exeOnDisk)
            Check 'the_built_assembly_exists' (Test-Path (Join-Path $Project '.godot\mono\temp\bin\Debug\Mcp056Probe.dll')) `
                ("assembly = {0}" -f (Join-Path $Project '.godot\mono\temp\bin\Debug\Mcp056Probe.dll'))
        } finally {
            Stop-McpEngine -Handle $monoHandle -Name 'mono-editor'
            $monoHandle = $null
        }
    }
}

# ---------------------------------------------------------------------------
$userPidAfter = Get-ListenerPid -Port $UserPort
$guardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter $userPidAfter
Check 'port_9877_guard' $guardResult.pass $guardResult.evidence
Check 'user_editor_9877_untouched' ($userPidAfter -eq $userPidBefore) ("pid before={0} after={1}" -f $userPidBefore, $userPidAfter)

$failed = @($script:Checks | Where-Object { -not $_.pass })
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add(('phase={0} git_head={1} plain={2} mono={3}' -f $Phase, $headSha, $plainVersion, $monoVersion))
$summary.Add(('checks={0} passed={1} failed={2}' -f $script:Checks.Count, ($script:Checks.Count - $failed.Count), $failed.Count))
foreach ($check in $script:Checks) {
    $summary.Add(('[{0}] {1} :: {2}' -f $(if ($check.pass) { 'PASS' } else { 'FAIL' }), $check.id, $check.evidence))
}
[IO.File]::WriteAllLines((Join-Path $Ev 'summary.txt'), $summary.ToArray())
# Per phase, because the two phases are separate runs over one evidence dir and
# the last one used to overwrite the other's summary (TASK-056 recorded that).
[IO.File]::WriteAllLines((Join-Path $Ev ('summary-' + $Phase + '.txt')), $summary.ToArray())

Write-Host ''
Write-Host ('{0}: {1}/{2} checks passed' -f $Phase, ($script:Checks.Count - $failed.Count), $script:Checks.Count)
foreach ($check in $failed) { Write-Host ('  FAILED {0} :: {1}' -f $check.id, $check.evidence) }
if ($failed.Count -gt 0) { exit 1 }
exit 0
