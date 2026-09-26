# =============================================================================
#  mcp007_write_evidence.ps1 -- TASK-007 gate 2 (three evidence classes for the
#  four write tools of project_write_resource_scene) on a %TEMP% scratch project.
#
#  Discipline:
#    * every response body is written to a file with `curl.exe -s -o <file>`
#      (never through Out-File / a pipeline), and its sha256 is computed from the
#      bytes on disk;
#    * the scratch project is a *fresh copy* under %TEMP%; nothing is written
#      inside the repository or any user project;
#    * the engine is started on port 9888 only (9877 belongs to the user's
#      editor and is never touched);
#    * the file system before/after state is a sorted `path|size|sha256` list.
# =============================================================================

$ErrorActionPreference = 'Stop'

$RepoRoot = 'F:\RustProjects\godot-mcp-pro\code\godot'
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Scratch = Join-Path $env:TEMP 'mcp007-write-scratch'
$LogRoot = Join-Path $env:TEMP 'mcp007-write-logs'
$Evid = Join-Path $env:TEMP 'mcp007-write-evidence'
$Port = 9888

Write-Host '=== TASK-007 gate 2 evidence driver ==='

# -----------------------------------------------------------------------------
# fresh scratch project
# -----------------------------------------------------------------------------
if (Test-Path $Scratch) { Remove-Item -Recurse -Force $Scratch }
New-Item -ItemType Directory -Force -Path $Scratch, $LogRoot, $Evid | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Scratch 'resources'), (Join-Path $Scratch 'scenes') | Out-Null

$projectGodot = @(
    'config_version=5',
    '',
    '[application]',
    'config/name="MCP007 write scratch"',
    'config/features=PackedStringArray("4.8")',
    '',
    '[rendering]',
    'renderer/rendering_method="gl_compatibility"',
    'renderer/rendering_method.mobile="gl_compatibility"'
) -join "`n"
[IO.File]::WriteAllText((Join-Path $Scratch 'project.godot'), $projectGodot + "`n", (New-Object Text.UTF8Encoding($false)))

$editable = @(
    '[gd_resource type="Resource" format=3]',
    '',
    '[resource]',
    'resource_name = "original"'
) -join "`n"
[IO.File]::WriteAllText((Join-Path $Scratch 'resources\editable.tres'), $editable + "`n", (New-Object Text.UTF8Encoding($false)))

$corrupt = "[gd_resource type=`"Resource`" format=3]`n`n[resource`nresource_name = `"unterminated`n"
[IO.File]::WriteAllText((Join-Path $Scratch 'resources\corrupt.tres'), $corrupt, (New-Object Text.UTF8Encoding($false)))

$doomed = @(
    '[gd_scene format=3]',
    '',
    '[node name="Doomed" type="Node2D"]'
) -join "`n"
[IO.File]::WriteAllText((Join-Path $Scratch 'scenes\doomed.tscn'), $doomed + "`n", (New-Object Text.UTF8Encoding($false)))
# NOTE: no `doomed.tscn.import` is created here on purpose. The editor rescan that
# runs while the scratch editor is up re-creates it for a `.tscn` it knows about
# (observed: the sidecar reappears after `project_delete_scene_file` removed it),
# so its absence is not a stable observable of the *tool*. What the tool is
# asserted on is the scene file itself, which the editor does not resurrect.

Write-Host ("scratch project: {0}" -f $Scratch)

# -----------------------------------------------------------------------------
# helpers
# -----------------------------------------------------------------------------
function Get-FileSnapshot {
    param([string]$Root)
    $rows = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -Path $Root -Recurse -File -Force | ForEach-Object {
        $hash = (Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash.ToLower()
        $rel = $_.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
        $rows.Add(('{0}|{1}|{2}' -f $rel, $_.Length, $hash))
    }
    return ($rows | Sort-Object)
}

function Write-Snapshot {
    param([string]$Path, [string]$Root)
    $snapshot = Get-FileSnapshot -Root $Root
    [IO.File]::WriteAllLines($Path, $snapshot, (New-Object Text.UTF8Encoding($false)))
    return $snapshot
}

function Invoke-Tool {
    param([string]$Id, [string]$Tool, [hashtable]$Arguments, [string]$Label)
    $payload = @{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = @{ name = $Tool; arguments = $Arguments } } | ConvertTo-Json -Depth 8 -Compress
    $body = Join-Path $Evid ("{0}.request.json" -f $Label)
    $resp = Join-Path $Evid ("{0}.response.json" -f $Label)
    [IO.File]::WriteAllText($body, $payload, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path $resp) { Remove-Item -Force $resp }
    & curl.exe -s -o $resp -H 'Content-Type: application/json' --data-binary ('@' + $body) ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    $exit = $LASTEXITCODE
    $bytes = [IO.File]::ReadAllBytes($resp)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $resp).Hash.ToLower()
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    Write-Host ("[{0}] curl_exit={1} bytes={2} sha256={3}" -f $Label, $exit, $bytes.Length, $sha)
    Write-Host ("        request : {0}" -f $payload)
    Write-Host ("        response: {0}" -f $text)
    return $text
}

function Get-Payload {
    param([string]$ResponseText)
    $json = $ResponseText | ConvertFrom-Json
    if ($null -ne $json.result -and $null -ne $json.result.content) {
        return ($json.result.content[0].text | ConvertFrom-Json)
    }
    return $null
}

function Get-ErrorObject {
    param([string]$ResponseText)
    return ($ResponseText | ConvertFrom-Json).error
}

# Re-read a published file through `project_read_resource` (a *different* tool of
# the module), so "the file is a real resource again" is observed on the wire and
# not only by hashing bytes.
function ResourceLoaderProbe {
    param([string]$Path)
    $payload = @{ jsonrpc = '2.0'; id = 'probe'; method = 'tools/call'; params = @{ name = 'project_read_resource'; arguments = @{ path = $Path } } } | ConvertTo-Json -Depth 8 -Compress
    $body = Join-Path $Evid ('probe.request.json')
    $resp = Join-Path $Evid ('probe.response.json')
    [IO.File]::WriteAllText($body, $payload, (New-Object Text.UTF8Encoding($false)))
    & curl.exe -s -o $resp -H 'Content-Type: application/json' --data-binary ('@' + $body) ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($resp))
    $json = $text | ConvertFrom-Json
    if ($null -eq $json.result) { return ("ERROR " + $json.error.message) }
    $inner = $json.result.content[0].text | ConvertFrom-Json
    $hash = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Scratch ($Path -replace '^res://', '').Replace('/', '\'))).Hash.ToLower()
    return ("type={0} path={1} sha256={2}" -f $inner.type, $inner.path, $hash)
}

# -----------------------------------------------------------------------------
# start the scratch editor on 9888
# -----------------------------------------------------------------------------
$pidBefore = -1
$lines = & netstat -ano -p TCP 2>$null
foreach ($line in $lines) {
    if ($line -match 'LISTENING' -and $line -match '[:\]]9877\s') { $pidBefore = [int](($line.Trim() -split '\s+')[-1]) }
}
Write-Host ("user editor on 9877 before: pid={0}" -f $pidBefore)

$out = Join-Path $LogRoot 'scratch-editor.out.log'
$err = Join-Path $LogRoot 'scratch-editor.err.log'
Remove-Item -Path $out, $err -ErrorAction SilentlyContinue
$proc = Start-Process -FilePath $Engine -ArgumentList @('--headless', '-e', '--path', $Scratch, "--mcp-port=$Port") -PassThru -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
Write-Host ("scratch editor pid={0}" -f $proc.Id)

try {
    $deadline = [DateTime]::UtcNow.AddSeconds(180)
    $ready = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $task = $client.ConnectAsync('127.0.0.1', $Port)
            if ($task.Wait(800)) { $client.Close(); $ready = $true; break }
            $client.Close()
        } catch { }
        Start-Sleep -Milliseconds 800
    }
    if (-not $ready) { throw "the scratch editor never listened on $Port; log: $(Get-Content -Raw $out)" }
    # Let the editor's main loop settle so the first request is not answered by a
    # half-initialised process.
    Start-Sleep -Seconds 5
    Write-Host 'scratch editor is listening'

    Write-Host ''
    Write-Host '========== phase 0: before state =========='
    $before = Write-Snapshot -Path (Join-Path $Evid 'fs.before.txt') -Root $Scratch
    $before | ForEach-Object { Write-Host ("  {0}" -f $_) }

    Write-Host ''
    Write-Host '========== phase 1: success path =========='

    $t = Invoke-Tool -Id 101 -Tool 'project_create_resource' -Arguments @{
        path = 'res://generated/created.tres'; type = 'Resource'
        properties = @{ resource_name = 'mcp_created' }
    } -Label 'success-provider-create-resource'
    $p = Get-Payload $t
    Write-Host ("        parsed: path={0} type={1} properties_set={2}" -f $p.path, $p.type, ($p.properties_set -join ','))

    $t = Invoke-Tool -Id 102 -Tool 'project_create_scene_file' -Arguments @{
        path = 'res://generated/created.tscn'; root_type = 'Node3D'; root_name = 'ScratchRoot'
    } -Label 'success-provider-create-scene'
    $p = Get-Payload $t
    Write-Host ("        parsed: path={0} root_type={1} root_name={2} created={3}" -f $p.path, $p.root_type, $p.root_name, $p.created)

    $t = Invoke-Tool -Id 103 -Tool 'project_edit_resource' -Arguments @{
        path = 'res://resources/editable.tres'; properties = @{ resource_name = 'edited'; mcp_no_such_property = 1 }
    } -Label 'success-provider-edit-resource'
    $p = Get-Payload $t
    $entry = $p.changed.resource_name
    Write-Host ("        parsed: path={0} type={1} changed.resource_name.old={2} new={3} unknown_skipped={4}" -f $p.path, $p.type, $entry.old, $entry.new, (-not $p.changed.PSObject.Properties['mcp_no_such_property']))

    $t = Invoke-Tool -Id 104 -Tool 'project_delete_scene_file' -Arguments @{ path = 'res://scenes/doomed.tscn' } -Label 'success-provider-delete-scene'
    $p = Get-Payload $t
    Write-Host ("        parsed: path={0} deleted={1}" -f $p.path, $p.deleted)

    # `overwrite = true` is the explicit opt-in of project_create_resource: it is
    # the one path that replaces an existing file on purpose.
    $t = Invoke-Tool -Id 105 -Tool 'project_create_resource' -Arguments @{
        path = 'res://resources/editable.tres'; type = 'Resource'; overwrite = $true
        properties = @{ resource_name = 'overwritten' }
    } -Label 'success-provider-create-resource-overwrite'
    $p = Get-Payload $t
    Write-Host ("        parsed: path={0} type={1} properties_set={2}" -f $p.path, $p.type, ($p.properties_set -join ','))

    Write-Host ''
    Write-Host '========== phase 2: missing / mistyped parameter (-32602) =========='

    $t = Invoke-Tool -Id 201 -Tool 'project_create_resource' -Arguments @{ path = 'res://generated/no-type.tres' } -Label 'missing-param-create-resource'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1}" -f $e.code, $e.message)

    $t = Invoke-Tool -Id 202 -Tool 'project_edit_resource' -Arguments @{ path = 'res://resources/editable.tres' } -Label 'missing-param-edit-resource'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1}" -f $e.code, $e.message)

    $t = Invoke-Tool -Id 203 -Tool 'project_delete_scene_file' -Arguments @{ path = 'res://../escape.tscn' } -Label 'mistyped-param-delete-path-outside-project'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1}" -f $e.code, $e.message)

    $t = Invoke-Tool -Id 204 -Tool 'project_create_scene_file' -Arguments @{ path = 'res://generated/bad-root.tscn'; root_type = 'McpNoSuchNodeClass' } -Label 'mistyped-param-create-scene-bad-root'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1}" -f $e.code, $e.message)

    Write-Host ''
    Write-Host '========== phase 3: bottom-layer failure (-32000 / -32001) =========='

    $t = Invoke-Tool -Id 301 -Tool 'project_delete_scene_file' -Arguments @{ path = 'res://scenes/never-existed.tscn' } -Label 'bottom-delete-missing-file'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1} suggestion={2}" -f $e.code, $e.message, $e.data.suggestion)

    $t = Invoke-Tool -Id 302 -Tool 'project_edit_resource' -Arguments @{ path = 'res://resources/never-written.tres'; properties = @{ resource_name = 'x' } } -Label 'bottom-edit-missing-resource'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1} suggestion={2}" -f $e.code, $e.message, $e.data.suggestion)

    $t = Invoke-Tool -Id 303 -Tool 'project_create_resource' -Arguments @{ path = 'res://resources/editable.tres'; type = 'Resource' } -Label 'bottom-create-existing-without-overwrite'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1} suggestion={2}" -f $e.code, $e.message, $e.data.suggestion)

    $t = Invoke-Tool -Id 304 -Tool 'project_create_scene_file' -Arguments @{ path = 'res://generated/created.tscn' } -Label 'bottom-create-scene-existing'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1} suggestion={2}" -f $e.code, $e.message, $e.data.suggestion)

    Write-Host ''
    Write-Host '========== phase 4: failed call must not damage an existing file =========='

    $t = Invoke-Tool -Id 401 -Tool 'project_edit_resource' -Arguments @{ path = 'res://resources/corrupt.tres'; properties = @{ resource_name = 'hijacked' } } -Label 'counter-example-edit-corrupt-file'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1} suggestion={2}" -f $e.code, $e.message, $e.data.suggestion)

    $t = Invoke-Tool -Id 402 -Tool 'project_create_resource' -Arguments @{ path = 'res://resources/corrupt.tres'; type = 'Resource' } -Label 'counter-example-create-over-corrupt-without-overwrite'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1} suggestion={2}" -f $e.code, $e.message, $e.data.suggestion)

    $t = Invoke-Tool -Id 403 -Tool 'project_create_resource' -Arguments @{ path = 'res://resources/corrupt.tres'; type = 'McpNoSuchResourceClass'; overwrite = $true } -Label 'counter-example-create-over-corrupt-bad-class'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1} suggestion={2}" -f $e.code, $e.message, $e.data.suggestion)

    $t = Invoke-Tool -Id 404 -Tool 'project_create_scene_file' -Arguments @{ path = 'res://resources/corrupt.tres' } -Label 'counter-example-create-scene-over-corrupt'
    $e = Get-ErrorObject $t
    Write-Host ("        parsed: code={0} message={1} suggestion={2}" -f $e.code, $e.message, $e.data.suggestion)

    Write-Host ''
    Write-Host '========== phase 5: after state + the two refusals re-checked =========='
    Start-Sleep -Seconds 2
    $after = Write-Snapshot -Path (Join-Path $Evid 'fs.after.txt') -Root $Scratch
    $after | ForEach-Object { Write-Host ("  {0}" -f $_) }

    Write-Host ''
    Write-Host '--- diff (before -> after) ---'
    $added = @($after | Where-Object { $before -notcontains $_ })
    $removed = @($before | Where-Object { $after -notcontains $_ })
    Write-Host 'ADDED:'
    $added | ForEach-Object { Write-Host ("  + {0}" -f $_) }
    Write-Host 'REMOVED:'
    $removed | ForEach-Object { Write-Host ("  - {0}" -f $_) }

    # The damaged file must be byte-identical, and no temporary artefact may
    # survive anywhere in the project.
    $corruptHash = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $Scratch 'resources\corrupt.tres')).Hash.ToLower()
    $corruptBefore = ($before | Where-Object { $_ -like 'resources/corrupt.tres|*' })
    $corruptAfter = ($after | Where-Object { $_ -like 'resources/corrupt.tres|*' })
    Write-Host ''
    Write-Host ("corrupt.tres before: {0}" -f $corruptBefore)
    Write-Host ("corrupt.tres after : {0}" -f $corruptAfter)
    Write-Host ("corrupt.tres unchanged: {0}" -f ($corruptBefore -eq $corruptAfter))

    $temps = @($after | Where-Object { $_ -notmatch '^\.godot/' -and $_ -match 'mcp-tmp|\.tmp|~' })
    Write-Host ("temporary / partial artefacts left behind in the project (outside .godot/): {0}" -f $temps.Count)
    $temps | ForEach-Object { Write-Host ("  ! {0}" -f $_) }
    # `.godot/` is the editor's own cache directory; it is reported separately so
    # the number above cannot hide an artefact inside it.
    $editor_cache = @($after | Where-Object { $_ -match '^\.godot/' -and $_ -match 'mcp-tmp' })
    Write-Host ("editor-cache entries naming a scratch path (editor side effect, not a project file): {0}" -f $editor_cache.Count)
    $editor_cache | ForEach-Object { Write-Host ("  . {0}" -f $_) }

    # The published files must be real, loadable resources again.
    $created = ResourceLoaderProbe -Path 'res://generated/created.tres'
    $scene = ResourceLoaderProbe -Path 'res://generated/created.tscn'
    $edited = ResourceLoaderProbe -Path 'res://resources/editable.tres'
    Write-Host ''
    Write-Host ("generated/created.tres loads as: {0}" -f $created)
    Write-Host ("generated/created.tscn loads as: {0}" -f $scene)
    Write-Host ("resources/editable.tres loads as: {0}" -f $edited)
} finally {
    try { if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force } } catch { }
    Start-Sleep -Milliseconds 800
    $pidAfter = -1
    $lines = & netstat -ano -p TCP 2>$null
    foreach ($line in $lines) {
        if ($line -match 'LISTENING' -and $line -match '[:\]]9877\s') { $pidAfter = [int](($line.Trim() -split '\s+')[-1]) }
    }
    Write-Host ''
    Write-Host ("guard: user editor on 9877 before pid={0} after pid={1} same={2}" -f $pidBefore, $pidAfter, ($pidBefore -eq $pidAfter))
}

Write-Host ''
Write-Host ("evidence directory: {0}" -f $Evid)
