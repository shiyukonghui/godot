# =============================================================================
#  mcp026_object_shape_probe.ps1 -- the OBJECT read-back gap (TASK-026 section 2.1)
#
#  E-9 is the first tool that reads an OBJECT-valued property back. This probe
#  measures the two directions of that round trip on a real `.tres`, so the gap
#  reported in `docs/reports/REPORT-026-e9-e6-g4.md` is a measured fact and not
#  an inference:
#
#    1. `project_read_resource` answers a null Object reference as `{}` (an empty
#       object) - `MCPTools::serialize_variant`'s OBJECT branch returns an empty
#       Dictionary for a null pointer;
#    2. feeding that `{}` back to `project_edit_resource` is **-32602**
#       (`Variant::can_convert(DICTIONARY, OBJECT)` is false, so `{}` can never be
#       a legal value for an Object property: a provable dead shape);
#    3. feeding the whole `properties` bag back is refused for the same reason;
#    4. writing JSON `null` instead is accepted (`code=0`) - but the answer still
#       reads `{}`, so the round trip is not structurally equal either;
#    5. controls: a scalar stored property and a component-shaped one both write
#       back with `code=0` (the component control is also the live proof of the
#       resource writers' TASK-026 shaping fix).
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp026_object_shape_probe.ps1
# =============================================================================

param(
    [int]$Port = 9888
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$Root = Join-Path $env:TEMP 'task026-object-shape'
$Ev = Join-Path $Root 'evidence'
$Proj = Join-Path $Root 'proj'
$UserPort = 9877

# TASK-028 D-1: the shared scratch-project writer and `--import` runner.
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

$script:Checks = New-Object System.Collections.Generic.List[object]

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

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

function Call-Tool {
    param([string]$Id, [string]$Tool, $Arguments)
    $envelope = [ordered]@{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = [ordered]@{ name = $Tool; arguments = $Arguments } }
    $bodyFile = Join-Path $Ev ("$Id.request.json")
    $respFile = Join-Path $Ev ("$Id.response.json")
    Write-Utf8NoBom -Path $bodyFile -Text (ConvertTo-Json -InputObject $envelope -Depth 20 -Compress)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl -s --max-time 60 -o $respFile -H 'Content-Type: application/json' --data-binary ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $respFile).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] bytes={1} sha256={2}" -f $Id, $bytes.Length, $sha)
    Write-Host ("       {0}" -f $text)
    return $text
}

function Parse-Payload {
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

# -----------------------------------------------------------------------------
# Scratch project: an `Environment` stores `sky` (an OBJECT reference, unset in a
# fresh resource) next to scalars, colours and vectors.
# -----------------------------------------------------------------------------
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $Proj | Out-Null

$projectGodot = @(
    'config_version=5'
    ''
    '[application]'
    'config/name="mcp026_object_shape"'
    'config/features=PackedStringArray("4.8")'
    ''
    '[rendering]'
    'renderer/rendering_method="gl_compatibility"'
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
Write-Utf8NoBom -Path (Join-Path $Proj 'project.godot') -Text ($projectGodot + "`n")
Write-Utf8NoBom -Path (Join-Path $Proj 'environment.tres') -Text ("[gd_resource type=`"Environment`" format=3]`n`n[resource]`n")

$userPidBefore = Get-ListenerPid -Port_ $UserPort
Check 'port_9888_free' ((Get-ListenerPid -Port_ $Port) -eq -1) ("port {0} owner={1}" -f $Port, (Get-ListenerPid -Port_ $Port))

$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
# TASK-028 D-1: the shared checked+retried `--import` runner.
$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $Root -Name 'import'
$ErrorActionPreference = $previous
Check 'scratch_project_imported' ($import.exit_code -eq 0) `
    ("--import exit={0} after {1} attempt(s) (log: {2})" -f $import.exit_code, $import.attempts, $import.log)

$proc = Start-Process -FilePath $Engine -ArgumentList @('--headless', '-e', '--path', $Proj, "--mcp-port=$Port") `
    -PassThru -RedirectStandardOutput (Join-Path $Root 'editor.out.log') -RedirectStandardError (Join-Path $Root 'editor.err.log') -WindowStyle Hidden

try {
    $ready = $false
    $frames = $null
    for ($i = 0; $i -lt 180; $i++) {
        Start-Sleep -Milliseconds 1000
        $statusFile = Join-Path $Ev 'status.json'
        & $Curl -s --max-time 5 -o $statusFile ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
        if (Test-Path $statusFile) {
            $bytes = [IO.File]::ReadAllBytes($statusFile)
            if ($bytes.Length -gt 0) {
                try {
                    $probe = ConvertFrom-Json ([Text.Encoding]::UTF8.GetString($bytes))
                    if ($null -ne $frames -and ([int]$probe.frame_count - $frames) -ge 20) { $ready = $true; break }
                    $frames = [int]$probe.frame_count
                } catch { }
            }
        }
    }
    Check 'editor_endpoint_ready' $ready ("editor on {0} answered GET /mcp with +20 frames" -f $Port)

    $readText = Call-Tool -Id 'read_environment' -Tool 'project_read_resource' -Arguments @{ path = 'res://environment.tres' }
    $payload = Parse-Payload $readText
    # The predicate is taken from the response text, not from a re-parsed object:
    # an empty JSON object round-trips through `ConvertFrom-Json` into a
    # `PSCustomObject` with no properties, and PowerShell cannot tell "no
    # properties" from "a null property collection" without a fragile test.
    $skyIsEmptyObject = $readText.Contains('\"sky\":{}')
    Check 'read_answers_a_null_object_reference_as_an_empty_object' $skyIsEmptyObject `
        ("response contains '`"sky`":{{}}' : {0} - serialize_variant's OBJECT branch returns an empty Dictionary for a null pointer" -f $skyIsEmptyObject)

    $writeEmptyText = Call-Tool -Id 'write_sky_empty_object' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://environment.tres'; properties = @{ sky = @{} } }
    Check 'feeding_the_read_value_back_is_refused_-32602' ((Get-ErrorCode $writeEmptyText) -eq -32602) `
        ("code={0} message='{1}'" -f (Get-ErrorCode $writeEmptyText), (Get-ErrorMessage $writeEmptyText))

    $writeNullText = Call-Tool -Id 'write_sky_null' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://environment.tres'; properties = @{ sky = $null } }
    # `null` in, `{}` out: accepted, but the answer is not the value that was
    # sent, so there is no equal round trip in this direction either
    # (`JSON::stringify` sorts the keys, so `new` precedes `old`).
    Check 'json_null_is_accepted_but_reads_back_as_an_empty_object' `
        (((Get-ErrorCode $writeNullText) -eq 0) -and $writeNullText.Contains('\"sky\":{\"new\":{},\"old\":{}}')) `
        ("code={0}; response contains '`"sky`":{{`"new`":{{}},`"old`":{{}}}}' = {1}" -f `
            (Get-ErrorCode $writeNullText), $writeNullText.Contains('\"sky\":{\"new\":{},\"old\":{}}'))

    $writeScalarText = Call-Tool -Id 'write_background_mode' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://environment.tres'; properties = @{ background_mode = 0 } }
    Check 'control_scalar_stored_property_writes_back' ((Get-ErrorCode $writeScalarText) -eq 0) `
        ("code={0} .changed.background_mode.new = {1}" -f (Get-ErrorCode $writeScalarText), ((Parse-Payload $writeScalarText).changed.background_mode.new))

    $writeColorText = Call-Tool -Id 'write_background_color' -Tool 'project_edit_resource' `
        -Arguments @{ path = 'res://environment.tres'; properties = @{ background_color = @{ r = 0.1; g = 0.2; b = 0.3; a = 1.0 } } }
    $colorPayload = Parse-Payload $writeColorText
    $colorNew = $null
    if ($null -ne $colorPayload) { $colorNew = $colorPayload.changed.background_color.new }
    Check 'control_component_shaped_property_writes_back' `
        (((Get-ErrorCode $writeColorText) -eq 0) -and ($null -ne $colorNew) -and ([double]$colorNew.r -gt 0.09) -and ([double]$colorNew.r -lt 0.11)) `
        ("code={0} .changed.background_color.new = {1} (the TASK-026 shaping fix on the resource write path)" -f `
            (Get-ErrorCode $writeColorText), (ConvertTo-Json $colorNew -Compress))

    if ($null -ne $payload) {
        $wholeText = Call-Tool -Id 'write_whole_bag' -Tool 'project_edit_resource' `
            -Arguments @{ path = 'res://environment.tres'; properties = $payload.properties }
        Check 'the_whole_read_bag_is_refused_for_the_same_reason' ((Get-ErrorCode $wholeText) -eq -32602) `
            ("code={0} message='{1}'" -f (Get-ErrorCode $wholeText), (Get-ErrorMessage $wholeText))
    }
} finally {
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 1500
    $userPidAfter = Get-ListenerPid -Port_ $UserPort
    Check 'guard_user_port_9877' ($userPidBefore -eq $userPidAfter -and $userPidBefore -gt 0) ("pid_before={0} pid_after={1}" -f $userPidBefore, $userPidAfter)
    Check 'test_port_released' ((Get-ListenerPid -Port_ $Port) -eq -1) ("port {0} owner={1}" -f $Port, (Get-ListenerPid -Port_ $Port))
}

$logPath = Join-Path $Ev 'probe.log.txt'
$summary = @()
foreach ($entry in $script:Checks) {
    $entryTag = 'FAIL'
    if ($entry.pass) { $entryTag = 'PASS' }
    $summary += ("[{0}] {1} :: {2}" -f $entryTag, $entry.id, $entry.evidence)
}
Write-Utf8NoBom -Path $logPath -Text (($summary -join "`r`n") + "`r`n")

$passed = @($script:Checks | Where-Object { $_.pass }).Count
$total = $script:Checks.Count
Write-Host ''
Write-Host ("{0}/{1} checks passed; evidence in {2} (log sha256={3})" -f $passed, $total, $Ev, (Get-FileHash -Algorithm SHA256 -Path $logPath).Hash.ToLower())
if ($passed -ne $total) { exit 1 }
exit 0
