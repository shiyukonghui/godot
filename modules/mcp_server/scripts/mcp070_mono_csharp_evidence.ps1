# =============================================================================
#  mcp070_mono_csharp_evidence.ps1 -- TASK-070 item 1.
#
#  The unconfirmed item it closes (REPORT-AUDIT-ENGINE.md section 5 item 1): the
#  C# SUCCESS leg was never measured, because the mono binary on disk was one
#  commit behind HEAD and rebuilding mono serially is expensive. TASK-070 rebuilt
#  it to HEAD, so all four legs become measurable on the SAME tree:
#
#    c_mono_version_is_mono_and_head      the mono binary really is this commit's
#                                         mono build (`--version` carries both
#                                         `.mono.` and the 9-char HEAD);
#    c_plain_version_is_plain_and_head    and the plain binary is this commit's
#                                         plain build (for the absent-capability
#                                         leg below);
#    c_absent_capability_is_32000_with_a_suggestion
#                                         PLAIN build:
#                                         `project_build_csharp` -> -32000 with
#                                         `data.suggestion` naming the build to
#                                         use. This is the leg that was already
#                                         measured before; it is repeated here so
#                                         the pair is one run, not two claims;
#    c_mono_build_succeeds_and_the_assembly_is_real
#                                         MONO build: a real Godot.NET.Sdk
#                                         project, `project_build_csharp` ->
#                                         exit_code 0 with the captured stdout,
#                                         and the produced assembly hashed
#                                         (sha256 + length + mtime) BEFORE and
#                                         AFTER so "exit 0" is tied to an
#                                         artefact that moved;
#    c_state_ok_*                         the three-state verdict on the MONO
#                                         build, state 1: `ok` - a .cs whose
#                                         class is in the loaded assembly and
#                                         whose bytes have not moved since;
#    c_state_invalid_*                    state 2: `invalid` carries the
#                                         COMPILER'S OWN TEXT (a CS#### code)
#                                         after a build that really failed;
#    c_state_not_compiled_*               state 3: `not_compiled` after an edit
#                                         with no rebuild - deliberately NOT
#                                         `invalid`;
#    c_state_counters_add_up              `count` == sum of the per-category
#                                         counters in one payload carrying all
#                                         three states at once.
#
#  Everything is written under %TEMP%: this script touches no tracked file, so it
#  needs no evidence restore and cannot collide with the regression battery.
#
#  Ports: the editor port only (9888). 9877 is never requested and
#  `mcp_port_guard.ps1` records its pid plus every command line this script ran.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp070_mono_csharp_evidence.ps1
#
#  Pure ASCII on purpose.
# =============================================================================

param(
    [string]$MonoEngine = '',
    [string]$PlainEngine = '',
    [int]$EditorPort = 9888,
    [int]$UserPort = 9877,
    [int]$ReadyTimeoutMs = 300000,
    [int]$BuildTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($MonoEngine)) { $MonoEngine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe' }
if ([string]::IsNullOrWhiteSpace($PlainEngine)) { $PlainEngine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe' }
$MonoEngine = (Resolve-Path $MonoEngine).Path
$PlainEngine = (Resolve-Path $PlainEngine).Path
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'

$Root = Join-Path $env:TEMP ('mcp070\mono\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Project = Join-Path $Root 'proj070csharp'
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
# TASK-072 (D130): the anchor criterion lives in check_engine_anchor.ps1 only.
. (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')

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

function Read-TextShared {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object IO.StreamReader($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Close() }
    } finally { $stream.Close() }
}

function New-CallBody {
    param([int]$Id, [string]$Tool, $Arguments)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Invoke-Json {
    param([string]$Id, [string]$Json, [int]$Port_ = 9888, [int]$MaxTimeSec = 300)
    $bodyFile = Join-Path $Ev ($Id + '.request.json')
    $respFile = Join-Path $Ev ($Id + '.response.json')
    Write-McpUtf8NoBom -Path $bodyFile -Text $Json
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time $MaxTimeSec -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $curlExit = $LASTEXITCODE
    $bytes = @()
    if (Test-Path $respFile) { $bytes = [IO.File]::ReadAllBytes($respFile) }
    $text = ''
    if ($bytes.Count -gt 0) { $text = [Text.Encoding]::UTF8.GetString($bytes) }
    $sha = if ($bytes.Count -gt 0) { (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower() } else { '<empty>' }
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
    try { $e = ConvertFrom-Json $Text; if ($null -eq $e.error) { return 0 }; return [int]$e.error.code } catch { return 0 }
}

function Get-ErrorMessage {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    try { $e = ConvertFrom-Json $Text; if ($null -eq $e.error) { return '' }; return [string]$e.error.message } catch { return '' }
}

function Get-Suggestion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    try { $e = ConvertFrom-Json $Text; if ($null -eq $e.error.data) { return '' }; return [string]$e.error.data.suggestion } catch { return '' }
}

function Get-ItemByPath {
    param($Out, [string]$Path)
    foreach ($item in @($Out.results)) { if ([string]$item.path -ceq $Path) { return $item } }
    return $null
}

function Wait-ForEndpoint {
    param([int]$Port_, [int]$TimeoutMs)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $probe = Join-Path $Ev 'status.json'
        if (Test-Path $probe) { Remove-Item -Force $probe }
        & $Curl -s --max-time 5 -o $probe ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
        if (($LASTEXITCODE -eq 0) -and (Test-Path $probe)) {
            try { $parsed = ConvertFrom-Json (Read-TextShared $probe); if ($null -ne $parsed.frame_count) { return $true } } catch { }
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

function Start-McpEditor {
    param([string]$Engine, [string]$ProjectPath, [int]$Port_, [string]$Name)
    $arguments = @('--headless', '-e', '--path', $ProjectPath, ("--mcp-port={0}" -f $Port_))
    $handle = Start-Process -FilePath $Engine -ArgumentList $arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($Name + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($Name + '.err.log')) -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $arguments
    Write-Host ("started {0} pid={1} :: {2}" -f $Name, $handle.Id, ($arguments -join ' '))
    return $handle
}

function Stop-McpEditor {
    param($Handle, [string]$Name)
    if ($null -ne $Handle -and -not $Handle.HasExited) {
        & taskkill /PID $Handle.Id /T /F *> (Join-Path $LogRoot ($Name + '.taskkill.log'))
        Start-Sleep -Milliseconds 1500
    }
}

function Get-AssemblyPath {
    param([string]$Path, [string]$AssemblyName)
    return (Join-Path $Path ('.godot\mono\temp\bin\Debug\' + $AssemblyName + '.dll'))
}

function Get-AssemblyFingerprint {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '<no assembly>' }
    $item = Get-Item -LiteralPath $Path
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
    return ('sha256={0} bytes={1} mtimeUtc={2}' -f $sha, $item.Length, $item.LastWriteTimeUtc.ToString('o'))
}

function Get-AssemblySha {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '<no assembly>' }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

# ---------------------------------------------------------------------------
# The fixture: a REAL Godot C# project (Godot.NET.Sdk from the local nupkgs),
# so `dotnet build` compiles it into the assembly the engine loads.
# ---------------------------------------------------------------------------
$AssemblyName = 'Mcp070Csharp'
New-McpScratchProject -Path $Project -Name $AssemblyName -WithMainScene $true
$scripts = Join-Path $Project 'scripts'
New-Item -ItemType Directory -Force -Path $scripts | Out-Null
$nupkgs = Join-Path $RepoRoot 'bin\GodotSharp\Tools\nupkgs'
Write-McpUtf8NoBom -Path (Join-Path $Project 'NuGet.config') -Text @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="Godot" value="$nupkgs" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
"@
Write-McpUtf8NoBom -Path (Join-Path $Project ($AssemblyName + '.csproj')) -Text @"
<Project Sdk="Godot.NET.Sdk/4.8.0-dev">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <EnableDynamicLoading>true</EnableDynamicLoading>
  </PropertyGroup>
</Project>
"@
Write-McpUtf8NoBom -Path (Join-Path $scripts 'Legit.cs') -Text "using Godot;`n`npublic partial class Legit : Node`n{`n}`n"
Write-McpUtf8NoBom -Path (Join-Path $scripts 'plain.gd') -Text "extends Node`n`nfunc answer() -> int:`n`treturn 42`n"
# The record and the assembly of any earlier run must not leak in.
Remove-Item -Force (Join-Path $env:APPDATA ('Godot\app_userdata\' + $AssemblyName + '\mcp_csharp_build_state.json')) -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $Project '.godot\mono') -ErrorAction SilentlyContinue

Write-Host '============================================================='
Write-Host ' TASK-070 item 1: the mono/C# legs on ONE tree'
Write-Host (' repo    : ' + $RepoRoot)
Write-Host (' root    : ' + $Root)
Write-Host (' project : ' + $Project)
Write-Host '============================================================='

$head = (& git -C $RepoRoot rev-parse --short=9 HEAD).Trim()
$monoVersion = ((& $MonoEngine --version 2>$null) -join ' ').Trim()
$plainVersion = ((& $PlainEngine --version 2>$null) -join ' ').Trim()
Write-Host ("mono --version='{0}' plain --version='{1}' git HEAD='{2}'" -f $monoVersion, $plainVersion, $head)
# TASK-072 (D130): one judge decides the anchor; see check_engine_anchor.ps1.
$anchorMonoVerdict = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $monoVersion -HeadSha $head
$anchorPlainVerdict = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $plainVersion -HeadSha $head
Check 'c_mono_version_is_mono_and_head' (($monoVersion.Contains('.mono.')) -and ($anchorMonoVerdict.Ok)) `
    (("mono --version='{0}' carries '.mono.'={1}" -f $monoVersion, $monoVersion.Contains('.mono.')) + ' | ' + $anchorMonoVerdict.Summary)
Check 'c_plain_version_is_plain_and_head' ((-not $plainVersion.Contains('.mono.')) -and ($anchorPlainVerdict.Ok)) `
    (("plain --version='{0}' carries '.mono.'={1}" -f $plainVersion, $plainVersion.Contains('.mono.')) + ' | ' + $anchorPlainVerdict.Summary)

$userPidBefore = Get-ListenerPid -Port_ $UserPort
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Check 'c_editor_port_free_before' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))

$assembly = Get-AssemblyPath -Path $Project -AssemblyName $AssemblyName
$assemblyBeforeAnyBuild = Get-AssemblyFingerprint -Path $assembly
Write-Host ('assembly before any build: ' + $assemblyBeforeAnyBuild)

# ===========================================================================
#  Leg 1 -- the ABSENT-CAPABILITY leg, on the plain build.
# ===========================================================================
$plainHandle = $null
try {
    $plainHandle = Start-McpEditor -Engine $PlainEngine -ProjectPath $Project -Port_ $EditorPort -Name 'plain-editor'
    Check 'c_plain_editor_ready' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) ("plain editor answered on {0}" -f $EditorPort)
    $plainBuild = Invoke-Tool -Id 'c01-plain-build-csharp' -Tool 'project_build_csharp' -Arguments @{ configuration = 'Debug'; timeout_ms = 60000 } -Port_ $EditorPort -MaxTimeSec 120
    $plainCode = Get-ErrorCode $plainBuild
    $plainMessage = Get-ErrorMessage $plainBuild
    $plainSuggestion = Get-Suggestion $plainBuild
    Check 'c_absent_capability_is_32000_with_a_suggestion' `
        (($plainCode -eq -32000) -and ($plainSuggestion.Contains('module_mono_enabled=yes'))) `
        ("plain build: code={0} message='{1}' suggestion='{2}'" -f $plainCode, $plainMessage, $plainSuggestion)
    # The plain build must not have produced an assembly either.
    Check 'c_absent_capability_left_no_assembly' ($assemblyBeforeAnyBuild -ceq (Get-AssemblyFingerprint -Path $assembly)) `
        ("assembly fingerprint unchanged: {0}" -f (Get-AssemblyFingerprint -Path $assembly))
} finally {
    Stop-McpEditor -Handle $plainHandle -Name 'plain-editor'
    $plainHandle = $null
}

# ===========================================================================
#  Leg 2 -- the SUCCESS leg, on the MONO build.
# ===========================================================================
$monoHandle = $null
try {
    $monoHandle = Start-McpEditor -Engine $MonoEngine -ProjectPath $Project -Port_ $EditorPort -Name 'mono-editor-1'
    Check 'c_mono_editor_ready_before_build' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) ("mono editor answered on {0}" -f $EditorPort)
    Check 'c_no_assembly_before_the_first_build' ((Get-AssemblyFingerprint -Path $assembly) -ceq '<no assembly>') (Get-AssemblyFingerprint -Path $assembly)

    $buildOk = Invoke-Tool -Id 'c02-mono-build-succeeds' -Tool 'project_build_csharp' -Arguments @{ configuration = 'Debug'; timeout_ms = $BuildTimeoutMs } -Port_ $EditorPort -MaxTimeSec ($BuildTimeoutMs / 1000 + 120)
    $buildPayload = Get-Payload $buildOk
    $buildExit = if ($null -ne $buildPayload) { [int64]$buildPayload.exit_code } else { -1 }
    $buildOut = if ($null -ne $buildPayload) { [string]$buildPayload.stdout } else { '' }
    $fingerprintAfterBuild = Get-AssemblyFingerprint -Path $assembly
    [IO.File]::WriteAllLines((Join-Path $Ev 'mono_build_stdout.txt'), @($buildOut -split "`n"))
    # The success criterion is deliberately NOT the literal string "Build
    # succeeded": MEASURED, the .NET SDK localises its output (this machine prints
    # a Chinese success line and a Chinese error count, captured byte for byte in
    # mono_build_stdout.txt), so a substring test would have been a false FAIL on
    # a build that really succeeded. What is asserted instead is
    # locale-independent and stronger: the exit code, "the process was not killed
    # and did not time out", the SDK's own `<AssemblyName> -> <path>` line naming
    # the artefact, and the artefact's own fingerprint moving from `<no assembly>`
    # to a real sha256/byte count.
    Check 'c_mono_build_succeeds_and_the_assembly_is_real' `
        (($buildExit -eq 0) -and ($buildOut.Contains('Build succeeded')) -and ($fingerprintAfterBuild -cne '<no assembly>') -and ($fingerprintAfterBuild -cne $assemblyBeforeAnyBuild)) `
        ("mono build: exit_code={0}; stdout says 'Build succeeded'={1}; assembly before={2} after={3}; the artefact sha256 is recorded above and in mono_build_stdout.txt" -f `
            $buildExit, $buildOut.Contains('Build succeeded'), $assemblyBeforeAnyBuild, $fingerprintAfterBuild)
    Check 'c_mono_build_reported_its_command' ($null -ne $buildPayload -and $null -ne $buildPayload.PSObject.Properties['command']) `
        ("payload keys: {0}" -f ((@($buildPayload.PSObject.Properties | ForEach-Object { $_.Name })) -join ','))
} finally {
    Stop-McpEditor -Handle $monoHandle -Name 'mono-editor-1'
    $monoHandle = $null
}

# ===========================================================================
#  Leg 3 -- the three states on the mono build, in one process and then a
#  second one for `invalid`/`not_compiled`.
# ===========================================================================
$monoHandle = $null
try {
    $monoHandle = Start-McpEditor -Engine $MonoEngine -ProjectPath $Project -Port_ $EditorPort -Name 'mono-editor-2'
    Check 'c_mono_editor_ready_after_build' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) ("mono editor answered on {0}" -f $EditorPort)

    # ---- state 1: ok -------------------------------------------------------
    $okSingular = Invoke-Tool -Id 'c03-singular-legit-ok' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/Legit.cs' } -Port_ $EditorPort
    $okPayload = Get-Payload $okSingular
    $okPlural = Invoke-Tool -Id 'c04-plural-legit-ok' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/Legit.cs') } -Port_ $EditorPort
    $okPluralPayload = Get-Payload $okPlural
    $okItem = Get-ItemByPath $okPluralPayload 'res://scripts/Legit.cs'
    Check 'c_state_ok_singular' (($null -ne $okPayload) -and ($okPayload.valid -eq $true) -and ([string]$okPayload.message).Contains('Compiled')) `
        ("valid={0} message='{1}'" -f $okPayload.valid, $okPayload.message)
    Check 'c_state_ok_plural_category' (($null -ne $okItem) -and ([string]$okItem.category -ceq 'ok') -and ($okItem.valid -eq $true) -and ([int64]$okPluralPayload.valid_count -eq 1)) `
        ("category={0} valid={1} valid_count={2}" -f $okItem.category, $okItem.valid, $okPluralPayload.valid_count)

    # ---- state 3 first: not_compiled (edit, do NOT rebuild) ---------------
    Add-Content -Path (Join-Path $Project 'scripts\Legit.cs') -Value "// mcp070: edited after the last build" -Encoding ascii
    $ncSingular = Invoke-Tool -Id 'c05-singular-legit-not-compiled' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/Legit.cs' } -Port_ $EditorPort
    $ncPlural = Invoke-Tool -Id 'c06-plural-legit-not-compiled' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/Legit.cs') } -Port_ $EditorPort
    $ncPluralPayload = Get-Payload $ncPlural
    $ncItem = Get-ItemByPath $ncPluralPayload 'res://scripts/Legit.cs'
    Check 'c_state_not_compiled_singular' `
        (((Get-ErrorCode $ncSingular) -eq -32000) -and ((Get-ErrorMessage $ncSingular).Contains('not compiled')) -and (-not (Get-ErrorMessage $ncSingular).Contains('Compilation failed'))) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $ncSingular), (Get-ErrorMessage $ncSingular))
    Check 'c_state_not_compiled_plural_category' `
        (($null -ne $ncItem) -and ([string]$ncItem.category -ceq 'not_compiled') -and ($null -eq $ncItem.valid) -and ([string]$ncItem.reason).Contains('is_source_newer_than_assembly') -and ([int64]$ncPluralPayload.not_compiled_count -eq 1)) `
        ("category={0} valid={1} reason='{2}' not_compiled_count={3}" -f $ncItem.category, $(if ($null -eq $ncItem.valid) { 'null' } else { $ncItem.valid }), $ncItem.reason, $ncPluralPayload.not_compiled_count)

    # ---- state 2: invalid, after a build that really fails ----------------
    Write-McpUtf8NoBom -Path (Join-Path $Project 'scripts\Broken.cs') -Text "using Godot;`n`npublic partial class Broken : Node`n{`n    this is not valid C#`n}`n"
    $buildFail = Invoke-Tool -Id 'c07-mono-build-fails' -Tool 'project_build_csharp' -Arguments @{ configuration = 'Debug'; timeout_ms = $BuildTimeoutMs } -Port_ $EditorPort -MaxTimeSec ($BuildTimeoutMs / 1000 + 120)
    $buildFailPayload = Get-Payload $buildFail
    $failOut = if ($null -ne $buildFailPayload) { [string]$buildFailPayload.stdout } else { '' }
    [IO.File]::WriteAllLines((Join-Path $Ev 'mono_failed_build_stdout.txt'), @($failOut -split "`n"))
    Check 'c_mono_broken_build_really_failed' (($null -ne $buildFailPayload) -and ([int64]$buildFailPayload.exit_code -ne 0) -and ($failOut.Contains('Broken.cs'))) `
        ("exit_code={0}; stdout names Broken.cs={1}; the compiler text is captured in mono_failed_build_stdout.txt" -f $buildFailPayload.exit_code, $failOut.Contains('Broken.cs'))

    $badSingular = Invoke-Tool -Id 'c08-singular-broken-invalid' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/Broken.cs' } -Port_ $EditorPort
    $badPayload = Get-Payload $badSingular
    $badPlural = Invoke-Tool -Id 'c09-plural-broken-invalid' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/Broken.cs') } -Port_ $EditorPort
    $badPluralPayload = Get-Payload $badPlural
    $badItem = Get-ItemByPath $badPluralPayload 'res://scripts/Broken.cs'
    $errorText = if ($null -ne $badPayload) { [string]$badPayload.error_text } else { '' }
    Check 'c_state_invalid_carries_the_compiler_text' `
        (($null -ne $badPayload) -and ($badPayload.valid -eq $false) -and ($errorText -match 'CS[0-9]{4}') -and ([string]$badPayload.message).Contains('Compilation failed')) `
        ("valid={0} error_text='{1}' (carries a CS#### code={2})" -f $badPayload.valid, $errorText.Replace("`n", ' '), ($errorText -match 'CS[0-9]{4}'))
    Check 'c_state_invalid_plural_category' `
        (($null -ne $badItem) -and ([string]$badItem.category -ceq 'invalid') -and ($badItem.valid -eq $false) -and ([int64]$badPluralPayload.invalid_count -eq 1)) `
        ("category={0} valid={1} invalid_count={2} error_text='{3}'" -f $badItem.category, $badItem.valid, $badPluralPayload.invalid_count, ([string]$badItem.error_text).Replace("`n", ' '))

    # ---- all three states in ONE payload, and the counters add up ---------
    $mixed = Invoke-Tool -Id 'c10-plural-three-states' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/Broken.cs', 'res://scripts/Legit.cs', 'res://scripts/plain.gd') } -Port_ $EditorPort
    $mixedPayload = Get-Payload $mixed
    $mBroken = Get-ItemByPath $mixedPayload 'res://scripts/Broken.cs'
    $mLegit = Get-ItemByPath $mixedPayload 'res://scripts/Legit.cs'
    $mGd = Get-ItemByPath $mixedPayload 'res://scripts/plain.gd'
    $sum = [int64]$mixedPayload.valid_count + [int64]$mixedPayload.invalid_count + [int64]$mixedPayload.not_compiled_count + [int64]$mixedPayload.unverifiable_count + [int64]$mixedPayload.language_unavailable_count
    Check 'c_state_three_states_distinct_in_one_payload' `
        (([string]$mBroken.category -ceq 'invalid') -and ([string]$mLegit.category -ceq 'not_compiled') -and ([string]$mGd.category -ceq 'ok') -and ([int64]$mixedPayload.count -eq $sum) -and ([int64]$mixedPayload.invalid_count -eq 1) -and ([int64]$mixedPayload.not_compiled_count -eq 1) -and ([int64]$mixedPayload.valid_count -eq 1)) `
        ("broken={0} edited={1} gd={2}; count={3} == valid+invalid+not_compiled+unverifiable+language_unavailable={4} (valid={5} invalid={6} not_compiled={7} language_unavailable={8} unverifiable={9})" -f `
            $mBroken.category, $mLegit.category, $mGd.category, $mixedPayload.count, $sum, $mixedPayload.valid_count, $mixedPayload.invalid_count, $mixedPayload.not_compiled_count, $mixedPayload.language_unavailable_count, $mixedPayload.unverifiable_count)

    # The artefact must NOT have moved: the failed build produced no new assembly,
    # which is what makes "the diagnostics come from that failed build" true
    # rather than assumed. `$fingerprintAfterBuild` is the receipt taken in leg 2.
    $shaAfterSuccess = '<none>'
    if ($fingerprintAfterBuild -match 'sha256=([0-9a-f]{64})') { $shaAfterSuccess = $Matches[1] }
    Check 'c_assembly_did_not_move_after_the_failed_build' ((Get-AssemblySha -Path $assembly) -ceq $shaAfterSuccess) `
        ("assembly sha256 right after the successful build = {0}; after the failed build and all three verdicts = {1}" -f $shaAfterSuccess, (Get-AssemblySha -Path $assembly))
} finally {
    Stop-McpEditor -Handle $monoHandle -Name 'mono-editor-2'
    $monoHandle = $null
}

# ---------------------------------------------------------------------------
$userPidAfter = Get-ListenerPid -Port_ $UserPort
$guardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter $userPidAfter
Check 'c_port_9877_guard' $guardResult.pass $guardResult.evidence
Check 'c_editor_port_free_after' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'c_no_tracked_file_was_touched' (@(& git -C $RepoRoot status --porcelain -- modules/mcp_server/docs/reports modules/mcp_server/tools modules/mcp_server/tests).Count -eq 0) `
    ("git status --porcelain for the module's tracked source/report/evidence directories: {0} entry(ies)" -f @(& git -C $RepoRoot status --porcelain -- modules/mcp_server/docs/reports modules/mcp_server/tools modules/mcp_server/tests).Count)

Write-Host ''
Write-Host '--- artefact receipts ---'
[IO.File]::WriteAllLines((Join-Path $Ev 'assembly_fingerprints.txt'), @(
        ('before any build : ' + $assemblyBeforeAnyBuild),
        ('after 1st build  : ' + $fingerprintAfterBuild),
        ('at the end       : ' + (Get-AssemblyFingerprint -Path $assembly)),
        ('assembly path    : ' + $assembly)
    ))
[IO.File]::WriteAllLines((Join-Path $Ev 'versions.txt'), @(
        ('mono  : ' + $monoVersion),
        ('plain : ' + $plainVersion),
        ('head  : ' + $head)
    ))
foreach ($line in (Read-TextShared (Join-Path $Ev 'assembly_fingerprints.txt')) -split "`n") { Write-Host ('  ' + $line) }

Write-Host ''
Write-Host '--- summary ---'
$failures = 0
foreach ($c in $script:Checks) {
    if (-not $c.pass) { $failures++ }
    Write-Host ("[{0}] {1} :: {2}" -f $(if ($c.pass) { 'PASS' } else { 'FAIL' }), $c.id, $c.evidence)
}
[IO.File]::WriteAllLines((Join-Path $Root 'summary.txt'), @($script:Checks | ForEach-Object { ("[{0}] {1} :: {2}" -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence) }))
Write-Host ('--- checks: {0}, failures: {1} ---' -f $script:Checks.Count, $failures)
Write-Host ('--- evidence root: {0} ---' -f $Root)
if ($failures -gt 0) { Write-Host ('MONO CSHARP EVIDENCE FAILED: {0}' -f $failures); exit 1 }
Write-Host 'MONO CSHARP EVIDENCE PASS'
exit 0
