# =============================================================================
#  mcp043_reload_plugin_rewrite_probe.ps1 -- TASK-043, survey evidence
#
#  The survey for TASK-043 is read out of the source, not guessed. Four tools
#  reach the engine's whole-file writer directly:
#
#      project_set_setting / project_add_autoload / project_remove_autoload
#          -> MCPTools::publish_project_settings()
#      editor_add_input_action
#          -> MCPTools::persist_input_action() -> persist_input_action_to()
#
#  The fifth one is *indirect*, and that is exactly why it needs a measurement
#  instead of a source reading: `editor_reload_plugin` calls
#  `EditorNode::set_addon_plugin_enabled(name, false, false)` and then
#  `(name, true, false)` - with `p_config_changed = false`, which looks like
#  "do not touch the project file". But both branches end in
#  `EditorNode::_update_addon_config()` (`editor_node.cpp:4524-4531`), which is
#  **not** gated on `p_config_changed` and calls
#  `project_settings_editor->queue_save()` unconditionally (`:4530`). That arms
#  a one-shot 1.5 s `Timer` (`project_settings_editor.cpp:870-874`) whose timeout
#  runs `ProjectSettings::save()` (`:102-106`) - the engine's own whole-file
#  `save_custom()` path.
#
#  So the claim to measure is: a reload with one addon enabled rewrites the whole
#  `project.godot` and loses its hand-written comments. The control is the first
#  check: an editor that merely starts with that addon enabled must NOT rewrite
#  the file (otherwise the attribution below would be wrong).
#
#  Port discipline: 9877 is only classified through mcp_port_guard.ps1; the
#  editor uses 9888, the game 9889. ASCII only.
# =============================================================================

param(
    [int]$EditorPort = 9888,
    [int]$GamePort = 9889,
    [int]$UserPort = 9877,
    [string]$OutRoot = '',
    [int]$SettleSeconds = 5
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp043-reload' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$Root = $OutRoot
$Proj = Join-Path $Root 'proj'
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$ProjectFile = Join-Path $Proj 'project.godot'
$utf8 = [Text.Encoding]::UTF8
$AddonName = 'res://addons/mcp043probe/plugin.cfg'

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

function Note { param([string]$Text) Write-Host ("NOTE   {0}" -f $Text) }

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

function New-CallBody {
    param([string]$Tool, $Arguments, [int]$Id = 1)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    return (ConvertTo-Json -InputObject $envelope -Depth 30 -Compress)
}

function Invoke-Raw {
    param([string]$Id, [string]$Body, [int]$Port_)
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-McpUtf8NoBom -Path $bodyFile -Text $Body
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl '-s' '--max-time' '120' '-o' $respFile '-H' 'Content-Type: application/json' '--data-binary' ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] port={1} bytes={2} sha256={3}" -f $Id, $Port_, $bytes.Length, $sha)
    Write-Host ("       {0}" -f $text)
    return @{ id = $Id; text = $text; sha256 = $sha; file = $respFile; bytes = $bytes.Length }
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, $Arguments, [int]$Port_ = 0)
    if ($Port_ -eq 0) { $Port_ = $EditorPort }
    return Invoke-Raw -Id $Id -Body (New-CallBody -Tool $Tool -Arguments $Arguments) -Port_ $Port_
}

function Get-Envelope {
    param($Response)
    try { return ConvertFrom-Json ([string]$Response.text) } catch { return $null }
}

function Get-Payload {
    param($Response)
    try {
        $envelope = Get-Envelope $Response
        if ($null -eq $envelope.result) { return $null }
        return ConvertFrom-Json ([string]$envelope.result.content[0].text)
    } catch { return $null }
}

function Get-ErrorCode {
    param($Response)
    $envelope = Get-Envelope $Response
    if ($null -eq $envelope -or $null -eq $envelope.error) { return 0 }
    return [int]$envelope.error.code
}

function Get-PropertyValue {
    param($Object_, [string]$Name)
    if ($null -eq $Object_) { return $null }
    foreach ($p in $Object_.PSObject.Properties) { if ([string]$p.Name -ceq $Name) { return $p.Value } }
    return $null
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

# =============================================================================
#  Scratch project: hand-written comments plus one enabled addon
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Proj, (Join-Path $Proj 'scenes'), (Join-Path $Proj 'addons\mcp043probe') | Out-Null

$comments = @(
    '; hand-written comment one: keep me',
    '; hand-written comment two: these are not engine settings',
    '; hand-written comment three: the engine has nowhere to store them'
)
$projectLines = @()
$projectLines += $comments
$projectLines += @(
    'config_version=5',
    '',
    '[application]',
    '',
    'config/name="MCP043 reload probe"',
    'config/features=PackedStringArray("4.8")',
    'run/main_scene="res://scenes/main.tscn"',
    '',
    '[editor_plugins]',
    '',
    ('enabled=PackedStringArray("' + $AddonName + '")'),
    '',
    '[rendering]',
    '',
    'renderer/rendering_method="gl_compatibility"',
    'renderer/rendering_method.mobile="gl_compatibility"'
)
Write-McpUtf8NoBom -Path $ProjectFile -Text (($projectLines -join "`n") + "`n")
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text (@('[gd_scene format=3]', '', '[node name="Main" type="Node"]') -join "`n")
Write-McpUtf8NoBom -Path (Join-Path $Proj 'addons\mcp043probe\plugin.cfg') -Text (@(
        '[plugin]', '', 'name="MCP043 reload probe"', 'description="The object editor_reload_plugin reloads"',
        'author="mcp043"', 'version="1.0"', 'script="plugin.gd"') -join "`n")
Write-McpUtf8NoBom -Path (Join-Path $Proj 'addons\mcp043probe\plugin.gd') -Text (@(
        '@tool', 'extends EditorPlugin') -join "`n")

$originalBytes = [IO.File]::ReadAllBytes($ProjectFile)
$originalText = [IO.File]::ReadAllText($ProjectFile, $utf8)
$originalSha = Get-Sha $ProjectFile
$originalCommentLines = @($originalText -split "`r?`n" | Where-Object { $_.StartsWith(';') })

$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)

Check 'P01_project_has_hand_written_comments' ($originalCommentLines.Count -eq 3) `
    ("{0} comment line(s); sha256={1}; bytes={2}" -f $originalCommentLines.Count, $originalSha, $originalBytes.Length)
Check 'P02_ports_free' (((Get-ListenerPid -Port_ $EditorPort) -eq -1) -and ((Get-ListenerPid -Port_ $GamePort) -eq -1)) `
    ("editor {0} owner={1}; game {2} owner={3}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort), $GamePort, (Get-ListenerPid -Port_ $GamePort))

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'P03_import_ok' ($import.exit_code -eq 0) ("--import exit={0} after {1} attempt(s)" -f $import.exit_code, $import.attempts)
$afterImportSha = Get-Sha $ProjectFile
Check 'P04_import_left_the_file_alone' ($afterImportSha -eq $originalSha) `
    ("sha256 before={0} after --import={1}" -f $originalSha, $afterImportSha)

$editorHandle = $null
$afterSha = ''
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'P10_editor_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    # The control: with the addon enabled the editor boots, loads plugins and
    # still may not touch the file - otherwise the rewrite measured below could
    # not be attributed to the tool call.
    Start-Sleep -Seconds 3
    $afterStartupSha = Get-Sha $ProjectFile
    Check 'P11_editor_startup_did_not_rewrite_the_file' ($afterStartupSha -eq $originalSha) `
        ("sha256 before={0} after the editor came up with the addon enabled={1}" -f $originalSha, $afterStartupSha)

    $reload = Invoke-Tool -Id 'P20_reload_plugin' -Tool 'editor_reload_plugin' -Arguments @{ }
    $reloadPayload = Get-Payload $reload
    Check 'P20_reload_reported_success' (((Get-ErrorCode $reload) -eq 0) -and ([bool](Get-PropertyValue $reloadPayload 'reloading') -eq $true)) `
        ("code={0} reloading={1} plugins={2}" -f (Get-ErrorCode $reload), (Get-PropertyValue $reloadPayload 'reloading'), (Get-PropertyValue $reloadPayload 'plugins'))

    # `ProjectSettingsEditor`'s timer is one-shot with a 1.5 s wait time, so the
    # save lands shortly *after* the tool returns - and the tool itself is not
    # allowed to claim it happened. Wait it out and measure the bytes.
    Start-Sleep -Seconds $SettleSeconds
    $afterSha = Get-Sha $ProjectFile
    $afterText = [IO.File]::ReadAllText($ProjectFile, $utf8)
    $afterBytes = [IO.File]::ReadAllBytes($ProjectFile)

    Check 'P21_whole_file_was_rewritten' ($afterSha -ne $originalSha) `
        ("sha256 {0} -> {1}; bytes {2} -> {3}" -f $originalSha, $afterSha, $originalBytes.Length, $afterBytes.Length)

    $lost = @()
    $kept = @()
    foreach ($comment in $originalCommentLines) {
        if ($afterText.Contains($comment)) { $kept += $comment } else { $lost += $comment }
    }
    Check 'P22_every_hand_written_comment_is_gone' (($lost.Count -eq $originalCommentLines.Count) -and ($kept.Count -eq 0)) `
        ("comments lost {0}/{1}; kept {2}; first lost line: '{3}'" -f $lost.Count, $originalCommentLines.Count, $kept.Count, $(if ($lost.Count -gt 0) { $lost[0] } else { '<none>' }))
    Check 'P23_the_engine_writes_its_own_header_instead' ($afterText.Contains('; Engine configuration file.')) `
        ("first line of the rewritten file: {0}" -f (($afterText -split "`r?`n")[0]))
    Check 'P24_other_settings_survive_verbatim' (($afterText.Contains('config/name="MCP043 reload probe"')) -and ($afterText.Contains('enabled=PackedStringArray("' + $AddonName + '")'))) `
        ("config/name kept={0}; editor_plugins/enabled kept={1}" -f $afterText.Contains('config/name="MCP043 reload probe"'), $afterText.Contains('enabled=PackedStringArray("' + $AddonName + '")'))

    $again = Invoke-Tool -Id 'P25_reload_again' -Tool 'editor_reload_plugin' -Arguments @{ }
    Start-Sleep -Seconds $SettleSeconds
    $againSha = Get-Sha $ProjectFile
    Check 'P25_second_reload_is_byte_identical' ($againSha -eq $afterSha) `
        ("sha256 after the second reload={0} (first={1})" -f $againSha, $afterSha)
    Check 'P25b_second_reload_still_succeeded' ((Get-ErrorCode $again) -eq 0) `
        ("code={0} payload={1}" -f (Get-ErrorCode $again), ([string]($again.text)))
} finally {
    Stop-Engine -Handle $editorHandle
}

# =============================================================================
#  Port guard (9877 is never requested: the editor is started with 9888)
# =============================================================================
$guard = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'Z01_port_9877_guard' ([bool]$guard.pass) ([string]$guard.evidence)

# =============================================================================
#  Result
# =============================================================================
$failed = @($script:Checks | Where-Object { -not $_.pass })
$summary = [pscustomobject]@{
    script    = 'mcp043_reload_plugin_rewrite_probe.ps1'
    original_sha256 = $originalSha
    rewritten_sha256 = $afterSha
    addon     = $AddonName
    checks    = $script:Checks
    failed    = $failed.Count
}
$summaryPath = Join-Path $Ev 'mcp043-reload-probe-checks.json'
[IO.File]::WriteAllBytes($summaryPath, (New-Object Text.UTF8Encoding($false)).GetBytes(($summary | ConvertTo-Json -Depth 10)))
Write-Host ("RESULT {0} checks, {1} failed; checks json sha256={2}" -f $script:Checks.Count, $failed.Count, (Get-Sha $summaryPath))
if ($failed.Count -gt 0) { exit 1 }
exit 0
