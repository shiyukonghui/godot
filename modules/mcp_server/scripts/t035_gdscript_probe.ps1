param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$Proj = Join-Path $env:TEMP 'task035-b5-batch3\proj'
$Out = Join-Path $env:TEMP 'task035-probe'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$port = 9888
$handle = Start-Process -FilePath $Engine -ArgumentList @('--headless', '-e', '--path', $Proj, "--mcp-port=$port") -PassThru -RedirectStandardOutput (Join-Path $Out 'editor.out.log') -RedirectStandardError (Join-Path $Out 'editor.err.log') -WindowStyle Hidden
try {
    $ready = $false
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Milliseconds 1000
        $status = Join-Path $Out 'status.json'
        & $Curl -s --max-time 5 -o $status ("http://127.0.0.1:{0}/mcp" -f $port) | Out-Null
        if (Test-Path $status) {
            try { $p = ConvertFrom-Json ([IO.File]::ReadAllText($status, [Text.Encoding]::UTF8)); if ($null -ne $p.frame_count -and [int]$p.frame_count -ge 20) { $ready = $true; break } } catch { }
        }
    }
    Write-Host "ready=$ready"
    & $Curl -s --max-time 60 -o (Join-Path $Out 'open.json') -H 'Content-Type: application/json' --data-binary ('@' + (Join-Path $Out 'open.json')) ("http://127.0.0.1:{0}/mcp" -f $port) | Out-Null

    $cases = @(
        @{ id = 'v1'; code = "return 1 + 1" },
        @{ id = 'v2'; code = "var x = 1`nreturn x" },
        @{ id = 'v3'; code = "return Mesh.ARRAY_MAX" },
        @{ id = 'v4'; code = "var arrays = []`narrays.resize(Mesh.ARRAY_MAX)`narrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])`narrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])`nvar mesh = ArrayMesh.new()`nmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)`nreturn mesh.get_surface_count()`n" },
        @{ id = 'v5'; code = "var mesh = ArrayMesh.new()`nvar arrays = []`narrays.resize(Mesh.ARRAY_MAX)`narrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])`narrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])`nmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)`nreturn mesh.get_surface_count()`n" },
        @{ id = 'v6'; code = "var node = get_edited_scene_root().get_node('Mesh')`nreturn node.name`n" },
        @{ id = 'v7'; code = "var node = get_edited_scene_root().get_node(`"Mesh`")`nreturn node.name`n" }
    )
    foreach ($case in $cases) {
        $envelope = [ordered]@{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = [ordered]@{ name = 'editor_execute_gdscript'; arguments = @{ code = $case.code } } }
        $body = ConvertTo-Json -InputObject $envelope -Depth 30 -Compress
        $bf = Join-Path $Out ($case.id + '.request.json')
        Write-McpUtf8NoBom -Path $bf -Text $body
        $rf = Join-Path $Out ($case.id + '.response.json')
        & $Curl -s --max-time 60 -o $rf -H 'Content-Type: application/json' --data-binary ('@' + $bf) ("http://127.0.0.1:{0}/mcp" -f $port) | Out-Null
        Write-Host ("=== {0}: {1}" -f $case.id, ([IO.File]::ReadAllText($rf, [Text.Encoding]::UTF8)))
    }
} finally {
    if (-not $handle.HasExited) { Stop-Process -Id $handle.Id -Force -ErrorAction SilentlyContinue }
}
