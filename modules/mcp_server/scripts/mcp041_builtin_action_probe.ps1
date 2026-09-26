# =============================================================================
#  mcp041_builtin_action_probe.ps1 -- TASK-041 section 2: the ui_* boundary.
#
#  `editor_add_input_action` publishes whatever action it just wrote in the
#  editor's InputMap. For a name the editor's map already has - every built-in
#  `ui_*` action, added by `InputMap::load_default()` (`main/main.cpp:2333`) -
#  `created` is false, but the action is *still* in the map, so the publish path
#  writes an `input/ui_accept` entry into the project. This probe measures that
#  instead of guessing: it records the `[input]` section before and after, and
#  reports how many events the new entry carries.
#
#  Port discipline: 9877 is only observed; 9888 is used; the scratch project is
#  `%TEMP%\mcp041-inputmap\proj` (created by the evidence script - run that one
#  first, or this probe creates the project itself if it is missing).
# =============================================================================

param(
    [int]$EditorPort = 9888
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$Root = Join-Path $env:TEMP 'mcp041-inputmap'
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877
$utf8 = [Text.Encoding]::UTF8
$Action = 'ui_accept'

. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks.Add([pscustomobject]@{ id = $Id; pass = $Pass; evidence = $Evidence })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Note { param([string]$Text) Write-Host ("NOTE   {0}" -f $Text) }

function Get-ListenerPid {
    param([int]$Port_)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port_ + "\s")) {
            return [int](($line.Trim() -split '\s+')[-1])
        }
    }
    return -1
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    $body = ConvertTo-Json -InputObject $envelope -Depth 30 -Compress
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-McpUtf8NoBom -Path $bodyFile -Text $body
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl '-s' '--max-time' '120' '-o' $respFile '-H' 'Content-Type: application/json' '--data-binary' ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $EditorPort) | Out-Null
    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($respFile))
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    Write-Host ("[{0}] bytes={1} sha256={2}" -f $Id, $text.Length, $sha)
    Write-Host ("       {0}" -f $text)
    return $text
}

function Get-InputSection {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    $text = [IO.File]::ReadAllText($Path, $utf8)
    $start = $text.IndexOf("[input]")
    if ($start -lt 0) { return '' }
    $rest = $text.Substring($start)
    $next = $rest.IndexOf("`n[", 1)
    if ($next -ge 0) { return $rest.Substring(0, $next) }
    return $rest
}

function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    return Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
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

New-Item -ItemType Directory -Force -Path $Ev, $LogRoot | Out-Null
if (-not (Test-Path (Join-Path $Proj 'project.godot'))) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Proj 'scenes') | Out-Null
    $lines = @('config_version=5', '', '[application]', 'config/name="mcp041"', 'config/features=PackedStringArray("4.8")')
    Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text (($lines -join "`n") + "`n")
    $import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
    Check 'Z0_scratch_project_imported' ($import.exit_code -eq 0) ("--import exit={0}" -f $import.exit_code)
}

$projectPath = Join-Path $Proj 'project.godot'
$userPidBefore = Get-ListenerPid -Port_ $UserPort
Note ("port {0} owner before: {1} (observed only)" -f $UserPort, $userPidBefore)
$beforeSection = Get-InputSection $projectPath
$beforeSha = (Get-FileHash -Algorithm SHA256 -Path $projectPath).Hash.ToLower()
Check 'Z1_editor_port_free' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))
Check 'Z2_probe_action_absent_before' (-not $beforeSection.Contains($Action)) ("[input] section mentions '{0}': {1} (sha256={2})" -f $Action, $beforeSection.Contains($Action), $beforeSha)

$editorHandle = $null
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor-ui-accept'
    Check 'Z3_editor_endpoint_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} ready" -f $EditorPort)

    $text = Invoke-Tool -Id 'Z4_add_builtin_ui_accept' -Tool 'editor_add_input_action' -Arguments @{ action = $Action }
    $payload = $null
    try { $payload = (ConvertFrom-Json $text).result.content[0].text | ConvertFrom-Json } catch { }
    $created = $null
    $persisted = $null
    $events = $null
    if ($null -ne $payload) {
        foreach ($p in $payload.PSObject.Properties) {
            if ($p.Name -ceq 'created') { $created = $p.Value }
            if ($p.Name -ceq 'persisted') { $persisted = $p.Value }
            if ($p.Name -ceq 'event_count') { $events = $p.Value }
        }
    }
    Check 'Z5_builtin_action_is_not_created_but_is_persisted' (($created -eq $false) -and ($persisted -eq $true)) `
        ("created={0} persisted={1} event_count={2} (a built-in action already exists in the editor's map, so it is not created - but it is published)" -f $created, $persisted, $events)

    $afterSection = Get-InputSection $projectPath
    $afterSha = (Get-FileHash -Algorithm SHA256 -Path $projectPath).Hash.ToLower()
    $hasEntry = $afterSection.Contains(($Action + '='))
    Check 'Z6_builtin_entry_lands_in_project_godot' $hasEntry `
        ("sha256 {0} -> {1}; [input] has '{2}=': {3}" -f $beforeSha.Substring(0, 16), $afterSha.Substring(0, 16), $Action, $hasEntry)
    Check 'Z7_builtin_entry_carries_the_editors_events' ($afterSection.Contains('Object(InputEventKey')) `
        ("[input] section bytes={0}" -f $afterSection.Length)
    Note ("[input] events for '{0}': {1}" -f $Action, ([regex]::Matches($afterSection, 'Object\(InputEventKey').Count))
}
finally {
    Stop-Engine -Handle $editorHandle
}

Start-Sleep -Seconds 2
$userPidAfter = Get-ListenerPid -Port_ $UserPort
Check 'Z8_port_9877_owner_unchanged' ($userPidAfter -eq $userPidBefore) ("port {0} owner before={1} after={2}" -f $UserPort, $userPidBefore, $userPidAfter)
Check 'Z9_editor_port_released' ((Get-ListenerPid -Port_ $EditorPort) -eq -1) ("port {0} owner={1}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort))

$failed = @($script:Checks | Where-Object { -not $_.pass })
Write-Host ''
Write-Host ("========== ui_accept probe: {0} checks, {1} failed ==========" -f $script:Checks.Count, $failed.Count)
foreach ($f in $failed) { Write-Host ("FAIL {0}: {1}" -f $f.id, $f.evidence) }
if ($failed.Count -gt 0) { exit 1 }
exit 0
