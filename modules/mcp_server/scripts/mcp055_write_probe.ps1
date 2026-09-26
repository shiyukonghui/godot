# Focused probe: does `project_validate_scripts` write anything into the project
# tree in a plain (non-mono) build? Runs one editor, hashes the tree, calls the
# two validate tools on a `.cs` file, hashes again, prints the file-level diff.
param(
    [int]$Port = 9888,
    [int]$ReadyTimeoutMs = 240000
)
$ErrorActionPreference = 'Continue'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$Root = Join-Path $env:TEMP 'mcp055-write-probe'
. (Join-Path $PSScriptRoot 'mcp_import_guard.ps1')

Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Root | Out-Null
$Project = Join-Path $Root 'proj'
New-McpScratchProject -Path $Project -Name 'Mcp055WriteProbe' -WithMainScene $true
New-Item -ItemType Directory -Force -Path (Join-Path $Project 'scripts') | Out-Null
Write-McpUtf8NoBom -Path (Join-Path $Project 'scripts\Legit.cs') -Text "using Godot;`n`npublic partial class Legit : Node`n{`n}`n"

function Get-Tree {
    param([string]$Path)
    $parts = @()
    foreach ($file in @(Get-ChildItem -Path $Path -Recurse -File | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($Path.Length).Replace('\', '/')
        $parts += ($relative + ':' + (Get-FileHash -Algorithm SHA256 -Path $file.FullName).Hash.ToLower())
    }
    return $parts
}

$handle = Start-Process -FilePath $Engine -PassThru -WindowStyle Hidden `
    -ArgumentList @('--headless', '-e', '--path', $Project, ("--mcp-port={0}" -f $Port)) `
    -RedirectStandardOutput (Join-Path $Root 'editor.out.log') -RedirectStandardError (Join-Path $Root 'editor.err.log')

$deadline = [DateTime]::UtcNow.AddMilliseconds($ReadyTimeoutMs)
$ready = $false
while ([DateTime]::UtcNow -lt $deadline) {
    $probe = Join-Path $Root 'status.json'
    if (Test-Path $probe) { Remove-Item -Force $probe }
    & $Curl -s --max-time 5 -o $probe ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
    if (($LASTEXITCODE -eq 0) -and (Test-Path $probe)) { $ready = $true; break }
    Start-Sleep -Milliseconds 1000
}
Write-Host ("editor ready={0}" -f $ready)

$before = Get-Tree -Path $Project
$body = Join-Path $Root 'call.json'
Write-McpUtf8NoBom -Path $body -Text '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_validate_scripts","arguments":{"paths":["res://scripts/Legit.cs"]}}}'
$resp = Join-Path $Root 'call.response.json'
& $Curl -s --max-time 60 -o $resp -H 'Content-Type: application/json' --data-binary ('@' + $body) ("http://127.0.0.1:{0}/mcp" -f $Port) | Out-Null
Write-Host ("validate_scripts: " + (Get-Content $resp -Raw))
Start-Sleep -Milliseconds 500
$after = Get-Tree -Path $Project

$diff = Compare-Object $before $after
if ($null -eq $diff) {
    Write-Host ("VERDICT: no project file changed ({0} files hashed)" -f $before.Count)
} else {
    Write-Host "VERDICT: the project tree DID change:"
    $diff | ForEach-Object { Write-Host ("  {0} {1}" -f $_.SideIndicator, $_.InputObject) }
}
if (-not $handle.HasExited) { & taskkill /PID $handle.Id /T /F *> $null }
