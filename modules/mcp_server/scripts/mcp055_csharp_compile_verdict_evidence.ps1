# =============================================================================
#  mcp055_csharp_compile_verdict_evidence.ps1 -- TASK-055 (D112)
#
#  The live evidence of the C# compile verdict, captured on one binary per run:
#
#    * the plain (module_mono_enabled=no) build: a '.cs' file is still refused
#      with -32000 and classified 'language_unavailable' (the TASK-050 answer, unchanged);
#    * the mono build: a real C# project (Godot.NET.Sdk) is built through
#      project_build_csharp and the two validate tools are asked before, after a
#      successful build, after a failed build, and after editing a file without
#      rebuilding -- so 'compiled' / 'not compiled' / 'failed to compile' are all
#      observable and distinct;
#    * a full tools/list and the TASK-038 probe battery, stored as response bytes
#      so a pre-patch and a post-patch binary can be compared label by label
#      (mcp055_pre_post_compare.py).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass `
#        -File mcp055_csharp_compile_verdict_evidence.ps1 -Label pre -MonoEngine <pre mono exe> -PlainEngine <pre plain exe>
#    ... -Label post -MonoEngine bin\godot.windows.editor.x86_64.mono.console.exe -PlainEngine bin\godot.windows.editor.x86_64.console.exe
#
#  Ports: the editor port is 9888, 9877 is never touched (netstat guard), and
#  every process this script starts is stopped by this script.
# =============================================================================

param(
    [ValidateSet('pre', 'post')][string]$Label = 'post',
    [string]$MonoEngine = '',
    [string]$PlainEngine = '',
    [int]$EditorPort = 9888,
    [int]$ReadyTimeoutMs = 300000
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($MonoEngine)) { $MonoEngine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe' }
if ([string]::IsNullOrWhiteSpace($PlainEngine)) { $PlainEngine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe' }
$MonoEngine = (Resolve-Path $MonoEngine).Path
$PlainEngine = (Resolve-Path $PlainEngine).Path

$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$UserPort = 9877
$Root = Join-Path $env:TEMP ('mcp055-' + $Label)
$Ev = Join-Path $RepoRoot ('modules\mcp_server\docs\reports\evidence\task055\' + $Label)
$LogRoot = Join-Path $Root 'logs'
$Project = Join-Path $Root 'proj055'

. (Join-Path $PSScriptRoot 'mcp_port_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
. (Join-Path $PSScriptRoot 'mcp038_probes.ps1')

New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null

$script:Checks = New-Object System.Collections.Generic.List[object]
$script:Hashes = New-Object System.Collections.Generic.List[string]
# Probes whose response bytes cannot be compared across runs (they carry a
# duration, a build's stdout, or a process id). Their *content* is checked
# instead, and mcp055_pre_post_compare.py reads this file to know what to skip.
$script:Unhashable = New-Object System.Collections.Generic.List[string]

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
    param([string]$Id, [string]$Json, [int]$Port_ = 9888, [int]$MaxTimeSec = 300, [bool]$Hashable = $true)
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
    if ($bytes.Count -gt 0) {
        $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    } else {
        $sha = '<empty>'
    }
    Write-Host ("[{0}] port={1} curl_exit={2} bytes={3} sha256={4}" -f $Id, $Port_, $curlExit, $bytes.Count, $sha)
    if ($Hashable) {
        $script:Hashes.Add(($Id + '|' + $sha))
    } else {
        $script:Unhashable.Add($Id)
    }
    return $text
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 9888, [int]$MaxTimeSec = 300, [bool]$Hashable = $true)
    return (Invoke-Json -Id $Id -Json (New-CallBody -Id 1 -Tool $Tool -Arguments $Arguments) -Port_ $Port_ -MaxTimeSec $MaxTimeSec -Hashable $Hashable)
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

function Wait-ForEndpoint {
    param([int]$Port_, [int]$TimeoutMs)
    # The probe file is removed before every attempt and curl has to exit 0: a
    # refused connection never rewrites the output file (TASK-054's measured
    # probe defect), so a stale body must not be able to answer "ready".
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

function Get-ItemByPath {
    param($Out, [string]$Path)
    foreach ($item in @($Out.results)) { if ([string]$item.path -ceq $Path) { return $item } }
    return $null
}

function Get-ToolEntry {
    param([string]$ListText, [string]$ToolName)
    try {
        $envelope = ConvertFrom-Json $ListText
        foreach ($entry in @($envelope.result.tools)) {
            if ([string]$entry.name -ceq $ToolName) { return $entry }
        }
    } catch { }
    return $null
}

# ---------------------------------------------------------------------------
# The fixture: a real Godot C# project (Godot.NET.Sdk), so `dotnet build` can
# actually compile it into the assembly the engine loads.
# ---------------------------------------------------------------------------
function New-Mcp055Project {
    param([string]$Path)
    Remove-Item -Recurse -Force $Path -ErrorAction SilentlyContinue
    New-McpScratchProject -Path $Path -Name 'Mcp055Probe' -WithMainScene $true
    $scripts = Join-Path $Path 'scripts'
    New-Item -ItemType Directory -Force -Path $scripts | Out-Null
    $nupkgs = Join-Path $RepoRoot 'bin\GodotSharp\Tools\nupkgs'
    Write-McpUtf8NoBom -Path (Join-Path $Path 'NuGet.config') -Text @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="Godot" value="$nupkgs" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
"@
    Write-McpUtf8NoBom -Path (Join-Path $Path 'Mcp055Probe.csproj') -Text @"
<Project Sdk="Godot.NET.Sdk/4.8.0-dev">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <EnableDynamicLoading>true</EnableDynamicLoading>
  </PropertyGroup>
</Project>
"@
    Write-McpUtf8NoBom -Path (Join-Path $scripts 'Legit.cs') -Text "using Godot;`n`npublic partial class Legit : Node`n{`n}`n"
    Write-McpUtf8NoBom -Path (Join-Path $scripts 'plain.gd') -Text "extends Node`n`nfunc answer() -> int:`n`treturn 42`n"
}

function New-BrokenScript {
    param([string]$Path)
    Write-McpUtf8NoBom -Path (Join-Path $Path 'scripts\Broken.cs') -Text "using Godot;`n`npublic partial class Broken : Node`n{`n    this is not valid C#`n}`n"
}

# The record and the assembly of a previous run must not leak into this one.
function Clear-Mcp055State {
    param([string]$Path)
    $userDir = Join-Path $env:APPDATA ('Godot\app_userdata\Mcp055Probe')
    Remove-Item -Force (Join-Path $userDir 'mcp_csharp_build_state.json') -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path $Path '.godot\mono') -ErrorAction SilentlyContinue
}

# The engine's own view, read straight from the process: which assembly is
# loaded and when it was written. Used to prove the fixture is real.
function Get-AssemblyInfo {
    param([string]$Path)
    $dll = Join-Path $Path '.godot\mono\temp\bin\Debug\Mcp055Probe.dll'
    if (-not (Test-Path $dll)) { return '<no assembly>' }
    $item = Get-Item $dll
    return ('{0} bytes, {1}' -f $item.Length, $item.LastWriteTimeUtc.ToString('o'))
}

# ---------------------------------------------------------------------------
$userPidBefore = Get-ListenerPid -Port $UserPort
$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore
Write-Host ("label={0} mono={1} plain={2}" -f $Label, $MonoEngine, $PlainEngine)

New-Mcp055Project -Path $Project
Clear-Mcp055State -Path $Project
$monoVersion = ((& $MonoEngine --version 2>$null) -join ' ').Trim()
$plainVersion = ((& $PlainEngine --version 2>$null) -join ' ').Trim()
$headSha = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
Write-Host ("mono --version='{0}' plain --version='{1}' git HEAD='{2}'" -f $monoVersion, $plainVersion, $headSha)
Check 'mono_engine_is_the_mono_build' ($monoVersion.Contains('.mono.')) ("mono --version='{0}'" -f $monoVersion)
Check 'plain_engine_is_not_the_mono_build' (-not $plainVersion.Contains('.mono.')) ("plain --version='{0}'" -f $plainVersion)

# ===========================================================================
# Phase A -- the plain build: the the TASK-050 answer must not move.
# ===========================================================================
$plainHandle = $null
try {
    $plainHandle = Start-McpEngine -Engine $PlainEngine -ProjectPath $Project -Port_ $EditorPort -Name 'plain-editor' -Editor
    Check 'plain_editor_ready' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) ("plain editor answered on {0}" -f $EditorPort)

    $probes = New-Mcp038Probes
    foreach ($probe in $probes) {
        $null = Invoke-Json -Id ('plain-{0:d2}-{1}' -f $probe.id, ($probe.label -replace '[^A-Za-z0-9]+', '_')) `
            -Json (Get-Mcp038ProbeBody -Probe $probe) -Port_ $EditorPort
    }

    $plainCs = Invoke-Tool -Id 'plain-90-singular-cs' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/Legit.cs' } -Port_ $EditorPort
    Check 'plain_singular_cs_is_32000_language_unavailable' `
        (((Get-ErrorCode $plainCs) -eq -32000) -and ((Get-Suggestion $plainCs).Contains('module_mono_enabled=yes')) -and ((Get-ErrorMessage $plainCs).Contains('not parsed or compiled'))) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $plainCs), (Get-ErrorMessage $plainCs))

    $plainPlural = Invoke-Tool -Id 'plain-91-plural-cs' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/Legit.cs', 'res://scripts/plain.gd') } -Port_ $EditorPort
    $plainPluralPayload = Get-Payload $plainPlural
    $plainPluralCs = Get-ItemByPath $plainPluralPayload 'res://scripts/Legit.cs'
    Check 'plain_plural_cs_is_language_unavailable' `
        (($null -ne $plainPluralCs) -and ([string]$plainPluralCs.category -ceq 'language_unavailable') -and ($null -eq $plainPluralCs.valid) -and ([string]$plainPluralCs.reason).Contains('get_language_for_extension')) `
        ("category={0} valid={1} reason='{2}'" -f $plainPluralCs.category, $(if ($null -eq $plainPluralCs.valid) { 'null' } else { $plainPluralCs.valid }), $plainPluralCs.reason)
    $hasNotCompiledCounter = ($null -ne $plainPluralPayload) -and ($null -ne $plainPluralPayload.PSObject.Properties['not_compiled_count'])
    if ($Label -eq 'post') {
        Check 'plain_plural_has_the_not_compiled_counter' $hasNotCompiledCounter `
            ("not_compiled_count={0}" -f $plainPluralPayload.not_compiled_count)
    } else {
        Check 'pre_plain_plural_has_no_not_compiled_counter' (-not $hasNotCompiledCounter) `
            ("not_compiled_count present={0}" -f $hasNotCompiledCounter)
    }
} finally {
    Stop-McpEngine -Handle $plainHandle -Name 'plain-editor'
    $plainHandle = $null
}

# ===========================================================================
# Phase B -- the mono build: build a real C# project and read the verdicts.
# ===========================================================================
$monoHandle = $null
try {
    # B1: no assembly has ever been built for this project yet.
    Clear-Mcp055State -Path $Project
    $monoHandle = Start-McpEngine -Engine $MonoEngine -ProjectPath $Project -Port_ $EditorPort -Name 'mono-editor-1' -Editor -ExtraArgs @('--verbose')
    Check 'mono_editor_ready_before_build' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) ("mono editor answered on {0}" -f $EditorPort)
    Check 'no_assembly_before_the_first_build' ((Get-AssemblyInfo -Path $Project) -ceq '<no assembly>') (Get-AssemblyInfo -Path $Project)

    $beforeSingular = Invoke-Tool -Id 'mono-01-singular-legit-before-build' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/Legit.cs' } -Port_ $EditorPort
    $beforePlural = Invoke-Tool -Id 'mono-02-plural-legit-before-build' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/Legit.cs') } -Port_ $EditorPort
    $beforePluralPayload = Get-Payload $beforePlural
    $beforeItem = Get-ItemByPath $beforePluralPayload 'res://scripts/Legit.cs'

    if ($Label -eq 'post') {
        Check 'mono_not_compiled_before_any_build' `
            (((Get-ErrorCode $beforeSingular) -eq -32000) -and ((Get-ErrorMessage $beforeSingular).Contains('not compiled'))) `
            ("code={0} message='{1}'" -f (Get-ErrorCode $beforeSingular), (Get-ErrorMessage $beforeSingular))
        Check 'mono_not_compiled_category_before_any_build' `
            (($null -ne $beforeItem) -and ([string]$beforeItem.category -ceq 'not_compiled') -and ($null -eq $beforeItem.valid) -and ([string]$beforeItem.reason).Contains('is_source_newer_than_assembly')) `
            ("category={0} valid={1} reason='{2}'" -f $beforeItem.category, $beforeItem.valid, $beforeItem.reason)
        Check 'mono_plural_counts_the_new_category' `
            (([int64]$beforePluralPayload.not_compiled_count -eq 1) -and ([int64]$beforePluralPayload.unverifiable_count -eq 0) -and ([int64]$beforePluralPayload.count -eq 1)) `
            ("not_compiled_count={0} unverifiable_count={1} count={2}" -f $beforePluralPayload.not_compiled_count, $beforePluralPayload.unverifiable_count, $beforePluralPayload.count)
    } else {
        Check 'pre_mono_unverifiable_before_any_build' `
            (((Get-ErrorCode $beforeSingular) -eq -32000) -and ((Get-ErrorMessage $beforeSingular).Contains('no compile verdict'))) `
            ("code={0} message='{1}'" -f (Get-ErrorCode $beforeSingular), (Get-ErrorMessage $beforeSingular))
        Check 'pre_mono_plural_unverifiable' (($null -ne $beforeItem) -and ([string]$beforeItem.category -ceq 'unverifiable')) `
            ("category={0}" -f $beforeItem.category)
    }

    # B2: build the project through the MCP tool; the response carries the exit
    # code and the captured output, and the tool records the diagnostics.
    $buildOk = Invoke-Tool -Id 'mono-03-build-succeeds' -Tool 'project_build_csharp' -Arguments @{ configuration = 'Debug'; timeout_ms = 300000 } -Port_ $EditorPort -MaxTimeSec 360 -Hashable $false
    $buildOkPayload = Get-Payload $buildOk
    Check 'mono_build_succeeded' (($null -ne $buildOkPayload) -and ([int64]$buildOkPayload.exit_code -eq 0)) `
        ("exit_code={0} stdout_tail='{1}'" -f $buildOkPayload.exit_code, (@($buildOkPayload.stdout -split "`n") | Select-Object -Last 1))
    Check 'mono_assembly_exists_after_the_build' ((Get-AssemblyInfo -Path $Project) -cne '<no assembly>') (Get-AssemblyInfo -Path $Project)
} finally {
    Stop-McpEngine -Handle $monoHandle -Name 'mono-editor-1'
    $monoHandle = $null
}

# B3: a second editor start loads the assembly that now exists, and then a
# broken file is added and the build is run again so it fails.
try {
    $monoHandle = Start-McpEngine -Engine $MonoEngine -ProjectPath $Project -Port_ $EditorPort -Name 'mono-editor-2' -Editor -ExtraArgs @('--verbose')
    Check 'mono_editor_ready_after_build' (Wait-ForEndpoint -Port_ $EditorPort -TimeoutMs $ReadyTimeoutMs) ("mono editor answered on {0}" -f $EditorPort)

    $okSingular = Invoke-Tool -Id 'mono-04-singular-legit-after-build' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/Legit.cs' } -Port_ $EditorPort
    $okPlural = Invoke-Tool -Id 'mono-05-plural-legit-after-build' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/Legit.cs') } -Port_ $EditorPort
    $okPayload = Get-Payload $okSingular
    $okPluralPayload = Get-Payload $okPlural
    $okItem = Get-ItemByPath $okPluralPayload 'res://scripts/Legit.cs'

    if ($Label -eq 'post') {
        Check 'mono_legit_cs_compiles' (($null -ne $okPayload) -and ($okPayload.valid -eq $true) -and ([string]$okPayload.message).Contains('Compiled')) `
            ("valid={0} message='{1}'" -f $okPayload.valid, $okPayload.message)
        Check 'mono_plural_legit_cs_is_ok' (($null -ne $okItem) -and ([string]$okItem.category -ceq 'ok') -and ($okItem.valid -eq $true) -and ([int64]$okPluralPayload.valid_count -eq 1)) `
            ("category={0} valid={1} valid_count={2}" -f $okItem.category, $okItem.valid, $okPluralPayload.valid_count)
    } else {
        Check 'pre_mono_legit_cs_refused' ((Get-ErrorCode $okSingular) -eq -32000) ("code={0}" -f (Get-ErrorCode $okSingular))
        Check 'pre_mono_plural_legit_cs_unverifiable' (($null -ne $okItem) -and ([string]$okItem.category -ceq 'unverifiable')) ("category={0}" -f $okItem.category)
    }

    # A file with a syntax error joins the project, and the build now fails.
    New-BrokenScript -Path $Project
    $buildFail = Invoke-Tool -Id 'mono-06-build-fails' -Tool 'project_build_csharp' -Arguments @{ configuration = 'Debug'; timeout_ms = 300000 } -Port_ $EditorPort -MaxTimeSec 360 -Hashable $false
    $buildFailPayload = Get-Payload $buildFail
    Check 'mono_broken_build_failed' (($null -ne $buildFailPayload) -and ([int64]$buildFailPayload.exit_code -ne 0) -and ([string]$buildFailPayload.stdout).Contains('Broken.cs')) `
        ("exit_code={0}" -f $buildFailPayload.exit_code)

    $failSingular = Invoke-Tool -Id 'mono-07-singular-broken-after-failed-build' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/Broken.cs' } -Port_ $EditorPort
    $failPlural = Invoke-Tool -Id 'mono-08-plural-broken-after-failed-build' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/Broken.cs') } -Port_ $EditorPort
    $failPayload = Get-Payload $failSingular
    $failPluralPayload = Get-Payload $failPlural
    $failItem = Get-ItemByPath $failPluralPayload 'res://scripts/Broken.cs'

    if ($Label -eq 'post') {
        Check 'mono_broken_cs_fails_with_the_compiler_text' `
            (($null -ne $failPayload) -and ($failPayload.valid -eq $false) -and ([string]$failPayload.error_text).Contains('CS') -and ([string]$failPayload.message).Contains('Compilation failed')) `
            ("valid={0} error_text='{1}'" -f $failPayload.valid, $failPayload.error_text)
        Check 'mono_plural_broken_cs_is_invalid' (($null -ne $failItem) -and ([string]$failItem.category -ceq 'invalid') -and ($failItem.valid -eq $false) -and ([int64]$failPluralPayload.invalid_count -eq 1)) `
            ("category={0} valid={1} invalid_count={2} error_text='{3}'" -f $failItem.category, $failItem.valid, $failPluralPayload.invalid_count, $failItem.error_text)
    } else {
        Check 'pre_mono_broken_cs_refused' ((Get-ErrorCode $failSingular) -eq -32000) ("code={0}" -f (Get-ErrorCode $failSingular))
        Check 'pre_mono_plural_broken_cs_unverifiable' (($null -ne $failItem) -and ([string]$failItem.category -ceq 'unverifiable')) ("category={0}" -f $failItem.category)
    }

    # The source of a file that is NOT broken was not recompiled by that failed
    # build either -- but its class is still in the loaded assembly and its bytes
    # did not move, so it is still "compiled". That is the honest asymmetry.
    $legitAfterFail = Invoke-Tool -Id 'mono-09-singular-legit-after-failed-build' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/Legit.cs' } -Port_ $EditorPort
    if ($Label -eq 'post') {
        $legitAfterFailPayload = Get-Payload $legitAfterFail
        Check 'mono_legit_cs_stays_compiled_after_another_files_failure' (($null -ne $legitAfterFailPayload) -and ($legitAfterFailPayload.valid -eq $true)) `
            ("valid={0}" -f $legitAfterFailPayload.valid)
    } else {
        Check 'pre_mono_legit_still_refused_after_failure' ((Get-ErrorCode $legitAfterFail) -eq -32000) ("code={0}" -f (Get-ErrorCode $legitAfterFail))
    }

    # "changed but not compiled" vs "failed to compile", in ONE payload: the
    # broken file keeps its recorded rejection while the edited file has no
    # recorded diagnostic and is only "not compiled".
    Add-Content -Path (Join-Path $Project 'scripts\Legit.cs') -Value "// edited after the last build" -Encoding ascii
    $mixed = Invoke-Tool -Id 'mono-10-plural-mixed-after-edit' -Tool 'project_validate_scripts' -Arguments @{ paths = @('res://scripts/Broken.cs', 'res://scripts/Legit.cs') } -Port_ $EditorPort
    $mixedPayload = Get-Payload $mixed
    $brokenItem = Get-ItemByPath $mixedPayload 'res://scripts/Broken.cs'
    $editedItem = Get-ItemByPath $mixedPayload 'res://scripts/Legit.cs'
    if ($Label -eq 'post') {
        Check 'mono_edited_file_is_not_compiled_while_the_broken_one_is_invalid' `
            (($null -ne $brokenItem) -and ($null -ne $editedItem) -and ([string]$brokenItem.category -ceq 'invalid') -and ([string]$editedItem.category -ceq 'not_compiled') -and ([int64]$mixedPayload.invalid_count -eq 1) -and ([int64]$mixedPayload.not_compiled_count -eq 1)) `
            ("broken={0} edited={1} invalid_count={2} not_compiled_count={3}" -f $brokenItem.category, $editedItem.category, $mixedPayload.invalid_count, $mixedPayload.not_compiled_count)
        Check 'mono_edited_file_reason_names_the_engine_accessor' (([string]$editedItem.reason).Contains('is_source_newer_than_assembly')) ([string]$editedItem.reason)
    } else {
        Check 'pre_mono_mixed_is_two_unverifiable' `
            (($null -ne $brokenItem) -and ($null -ne $editedItem) -and ([string]$brokenItem.category -ceq 'unverifiable') -and ([string]$editedItem.category -ceq 'unverifiable')) `
            ("broken={0} edited={1}" -f $brokenItem.category, $editedItem.category)
    }

    $editedSingular = Invoke-Tool -Id 'mono-11-singular-edited-after-build' -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/Legit.cs' } -Port_ $EditorPort
    if ($Label -eq 'post') {
        Check 'mono_edited_singular_is_not_compiled_not_invalid' `
            (((Get-ErrorCode $editedSingular) -eq -32000) -and ((Get-ErrorMessage $editedSingular).Contains('not compiled')) -and (-not (Get-ErrorMessage $editedSingular).Contains('Compilation failed'))) `
            ("code={0} message='{1}'" -f (Get-ErrorCode $editedSingular), (Get-ErrorMessage $editedSingular))
    } else {
        Check 'pre_mono_edited_singular_refused' ((Get-ErrorCode $editedSingular) -eq -32000) ("code={0}" -f (Get-ErrorCode $editedSingular))
    }

    # A tool that has nothing to do with C# must answer byte for byte the same,
    # and the full tools/list is captured so the contract can be compared too.
    $null = Invoke-Tool -Id 'mono-12-unrelated-tool' -Tool 'project_get_info' -Arguments @{} -Port_ $EditorPort
    $null = Invoke-Json -Id 'mono-13-tools-list' -Json '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' -Port_ $EditorPort
} finally {
    Stop-McpEngine -Handle $monoHandle -Name 'mono-editor-2'
    $monoHandle = $null
}

# ---------------------------------------------------------------------------
$userPidAfter = Get-ListenerPid -Port $UserPort
$guardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter $userPidAfter
Check 'port_9877_guard' $guardResult.pass $guardResult.evidence
Check 'user_editor_9877_untouched' ($userPidAfter -eq $userPidBefore) ("pid before={0} after={1}" -f $userPidBefore, $userPidAfter)

[IO.File]::WriteAllLines((Join-Path $Ev 'hashes.txt'), $script:Hashes.ToArray())
[IO.File]::WriteAllLines((Join-Path $Ev 'unhashable.txt'), $script:Unhashable.ToArray())
$failed = @($script:Checks | Where-Object { -not $_.pass })
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add(('label={0} mono={1} plain={2} git_head={3}' -f $Label, $monoVersion, $plainVersion, $headSha))
$summary.Add(('checks={0} passed={1} failed={2}' -f $script:Checks.Count, ($script:Checks.Count - $failed.Count), $failed.Count))
foreach ($check in $script:Checks) {
    $summary.Add(('[{0}] {1} :: {2}' -f $(if ($check.pass) { 'PASS' } else { 'FAIL' }), $check.id, $check.evidence))
}
[IO.File]::WriteAllLines((Join-Path $Ev 'summary.txt'), $summary.ToArray())

Write-Host ''
Write-Host ('{0}: {1}/{2} checks passed' -f $Label, ($script:Checks.Count - $failed.Count), $script:Checks.Count)
foreach ($check in $failed) { Write-Host ('  FAILED {0} :: {1}' -f $check.id, $check.evidence) }
if ($failed.Count -gt 0) { exit 1 }
exit 0