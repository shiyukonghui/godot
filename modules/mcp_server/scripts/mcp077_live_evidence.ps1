# =============================================================================
#  mcp077_live_evidence.ps1 -- TASK-077 D-B1 / D-B2 live evidence
#
#  One script, two phases, the same scratch project and the same requests, so the
#  "before" and the "after" rows can be compared line by line:
#
#    -Phase before   the binary as it is (the D-B1 fence hole and the D-B2
#                    `readable: true` lie are live)
#    -Phase after    the binary built from TASK-077's sources
#
#  D-B1 (blocking): a junction, a directory symlink and a file symlink are placed
#  INSIDE the project and point OUTSIDE it. Every read tool is pointed at them:
#
#    F22  project_read_text_file{res://link/secret.txt}       (junction)
#    F24  project_read_text_file{res://sym_secret.txt}        (file symlink)
#    F25  project_read_text_file{res://dlink/secret.txt}      (dir symlink)
#    G04  the same as F22 on the GAME endpoint (9889)
#    plus project_read_script / project_read_scene_file_content on the link, and
#    project_get_filesystem_tree{path:"res://link"} and {path:"res://"}.
#
#  The decisive comparison is the sha256 INSIDE the answer against the hash the
#  operating system computes for the outside file (they are equal before the fix).
#
#  The two controls that must survive the fix:
#    1. a plain project file is still readable, byte for byte;
#    2. `res://plain/../plain/secret_inside.txt` - a `..` that folds back inside
#       the project - must be REFUSED before the fix (the blanket rule) and must
#       SUCCEED after it (no over-refusal).
#
#  D-B2 (high): broken.gd (`func broken(:`) is offered to the batch and to the
#  singular tool; the scene is saved, read back with a tool and then loaded by the
#  GAME process, whose stderr is searched for the engine's own
#  `GDScript::reload (res://scripts/broken.gd` parse error.
#
#  Every response body is written by curl.exe itself (`-s -o`), never through a
#  PowerShell pipeline (PLAYBOOK section 7.1). The user's port 9877 is guarded and
#  never requested; the module's 9888 / 9889 are used. Pure ASCII on purpose.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp077_live_evidence.ps1 -Phase before
#    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp077_live_evidence.ps1 -Phase after
# =============================================================================

param(
    [ValidateSet('before', 'after')][string]$Phase = 'after',
    [string]$OutRoot = '',
    [string]$EnginePath = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$utf8 = [Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($EnginePath)) {
    $EnginePath = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
}
$Engine = (Resolve-Path $EnginePath).Path

$EditorPort = 9888
$GamePort = 9889
$UserPort = 9877

if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $env:TEMP ('mcp077\' + $Phase) }
Remove-Item -Recurse -Force $OutRoot -ErrorAction SilentlyContinue
$Proj = Join-Path $OutRoot 'proj'
$Outside = Join-Path $OutRoot 'outside'
$Ev = Join-Path $OutRoot 'evidence'
$LogRoot = Join-Path $OutRoot 'logs'
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Outside | Out-Null

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
function Get-Sha {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '<absent>' }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}
function Get-ListenerPid {
    param([int]$Port_)
    foreach ($line in (& netstat -ano -p TCP 2>$null)) {
        if ($line -match 'LISTENING' -and $line -match ("[:\]]" + $Port_ + "\s")) { return [int](($line.Trim() -split '\s+')[-1]) }
    }
    return -1
}
function Start-Engine {
    param([string[]]$Arguments, [string]$LogName)
    $handle = Start-Process -FilePath $Engine -ArgumentList $Arguments -PassThru `
        -RedirectStandardOutput (Join-Path $LogRoot ($LogName + '.out.log')) `
        -RedirectStandardError (Join-Path $LogRoot ($LogName + '.err.log')) -WindowStyle Hidden
    Register-McpPortGuardProcess -Guard $script:McpPortGuard -EnginePid $handle.Id -Arguments $Arguments
    return $handle
}
function Stop-Engine {
    param($Handle)
    if ($null -ne $Handle -and -not $Handle.HasExited) {
        Stop-Process -Id $Handle.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
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

# One JSON-RPC request. Returns the file/bytes/sha plus the raw error fields and
# the `content[0].text` payload of a successful tools/call.
function Invoke-Mcp {
    param([int]$Port_, [string]$Method, [hashtable]$Params, [string]$Tag)
    $bodyFile = Join-Path $Ev ($Tag + '.request.json')
    $respFile = Join-Path $Ev ($Tag + '.response.json')
    $payload = @{ jsonrpc = '2.0'; id = 1; method = $Method }
    if ($null -ne $Params) { $payload['params'] = $Params }
    Write-McpUtf8NoBom -Path $bodyFile -Text ($payload | ConvertTo-Json -Depth 12 -Compress)
    if (Test-Path $respFile) { Remove-Item -Force $respFile }
    & $Curl '-s' '--max-time' '90' '-o' $respFile '-H' 'Content-Type: application/json' '--data-binary' ('@' + $bodyFile) ("http://127.0.0.1:{0}/mcp" -f $Port_) | Out-Null
    $bytes = [IO.File]::ReadAllBytes($respFile)
    $sha = Get-Sha $respFile
    $json = $null
    try { $json = ConvertFrom-Json ([IO.File]::ReadAllText($respFile, $utf8)) } catch { }
    $code = $null
    $message = ''
    $suggestion = ''
    if ($null -ne $json -and $null -ne $json.error) {
        $code = [int]$json.error.code
        $message = [string]$json.error.message
        if ($null -ne $json.error.data) { $suggestion = [string]$json.error.data.suggestion }
    }
    $text = ''
    if ($null -ne $json -and $null -ne $json.result -and $null -ne $json.result.content) {
        foreach ($part in @($json.result.content)) { if ($null -ne $part.text) { $text = [string]$part.text } }
    }
    $payloadObject = $null
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        try { $payloadObject = ConvertFrom-Json $text } catch { }
    }
    $result = [pscustomobject]@{
        File = $respFile; Request = $bodyFile; Bytes = $bytes.Length; Sha256 = $sha
        Json = $json; Code = $code; Message = $message; Suggestion = $suggestion; Text = $text
        Payload = $payloadObject; Tag = $Tag
    }
    $short = if ($null -ne $code) { ('code={0} {1}' -f $code, $message) } else { $text }
    Write-Host ("  {0,-44} bytes={1,-6} sha={2} {3}" -f $Tag, $result.Bytes, $sha.Substring(0, 12), $short.Substring(0, [Math]::Min(150, $short.Length)))
    return $result
}
function Call-Tool {
    param([int]$Port_, [string]$Tool, [hashtable]$Arguments, [string]$Tag)
    return Invoke-Mcp -Port_ $Port_ -Method 'tools/call' -Params @{ name = $Tool; arguments = $Arguments } -Tag $Tag
}

$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)

# ---------------------------------------------------------------------------
#  The scratch project, and the three link objects that leave it
# ---------------------------------------------------------------------------
New-McpScratchProject -Path $Proj -Name ('MCP077 live evidence ' + $Phase) -WithMainScene $false | Out-Null
$projectGodot = @(
    'config_version=5',
    '',
    '[application]',
    ('config/name="MCP077 live evidence ' + $Phase + '"'),
    'config/features=PackedStringArray("4.8")',
    'run/main_scene="res://scenes/main.tscn"',
    '',
    '[rendering]',
    'renderer/rendering_method="gl_compatibility"',
    'renderer/rendering_method.mobile="gl_compatibility"'
)
Write-McpUtf8NoBom -Path (Join-Path $Proj 'project.godot') -Text (($projectGodot -join "`n") + "`n")

$secretToken = 'OUTSIDE_SECRET_TASK077_4c1f8a'
$insideToken = 'INSIDE_PROJECT_TASK077_PLAIN'
[IO.File]::WriteAllBytes((Join-Path $Outside 'secret.txt'), $utf8.GetBytes($secretToken + "`r`n"))
Write-McpUtf8NoBom -Path (Join-Path $Proj 'plain\secret_inside.txt') -Text ($insideToken + "`n")

Write-McpUtf8NoBom -Path (Join-Path $Proj 'scripts\good.gd') -Text "extends Node2D`n`nvar marker := 77`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scripts\broken.gd') -Text "extends Node2D`nfunc broken(:`n"
$main = @(
    '[gd_scene format=3]',
    '',
    '[node name="Main" type="Node2D"]'
)
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text (($main -join "`n") + "`n")

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name ('import-' + $Phase) -Port 0
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'L001_import_ok' ($import.exit_code -eq 0) ("--import exit={0} after {1} attempt(s)" -f $import.exit_code, $import.attempts)

# The links are created AFTER the import, so the editor's first scan never walks
# them (the project is imported once, cleanly); they are exactly what the audit
# placed by hand. Junctions need `mklink /J`, a directory symlink `mklink /D`,
# a file symlink `mklink`.
$linkLog = New-Object System.Collections.Generic.List[string]
function New-Link {
    param([string]$Arguments, [string]$Id)
    $line = ('cmd /c mklink {0}' -f $Arguments)
    $output = & cmd /c ('mklink {0}' -f $Arguments) 2>&1
    $code = $LASTEXITCODE
    $linkLog.Add(('[{0}] exit={1} :: {2}' -f $Id, $code, ($output -join ' | ')))
    Write-Host ('  mklink {0} (exit {1}): {2}' -f $Arguments, $code, ($output -join ' | '))
    return $code
}
$rcJunction = New-Link -Arguments ('/J "{0}" "{1}"' -f (Join-Path $Proj 'link'), $Outside) -Id 'junction'
$rcDirLink = New-Link -Arguments ('/D "{0}" "{1}"' -f (Join-Path $Proj 'dlink'), $Outside) -Id 'dir_symlink'
$rcFileLink = New-Link -Arguments ('"{0}" "{1}"' -f (Join-Path $Proj 'sym_secret.txt'), (Join-Path $Outside 'secret.txt')) -Id 'file_symlink'
[IO.File]::WriteAllLines((Join-Path $Ev 'link_creation.txt'), $linkLog)
Check 'L002_three_links_created' (($rcJunction -eq 0) -and ($rcDirLink -eq 0) -and ($rcFileLink -eq 0)) `
    ("junction exit={0}; dir symlink exit={1}; file symlink exit={2}; see {3}" -f $rcJunction, $rcDirLink, $rcFileLink, (Join-Path $Ev 'link_creation.txt'))

$secretSha = Get-Sha (Join-Path $Outside 'secret.txt')
$insideSha = Get-Sha (Join-Path $Proj 'plain\secret_inside.txt')
Write-Host ('  OS sha256 of the outside secret: {0}' -f $secretSha)
Write-Host ('  OS sha256 of the inside control: {0}' -f $insideSha)

# ---------------------------------------------------------------------------
#  editor endpoint
# ---------------------------------------------------------------------------
$editorHandle = $null
$gameHandle = $null
$brokenInSceneBeforeGame = $false
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, ("--mcp-port=" + $EditorPort)) -LogName 'editor'
    Check 'L003_editor_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)

    $listEd = Invoke-Mcp -Port_ $EditorPort -Method 'tools/list' -Params @{} -Tag 'editor_tools_list'
    $liveNames = @()
    foreach ($tool in $listEd.Json.result.tools) { $liveNames += [string]$tool.name }
    Check 'L004_read_tools_present' (($liveNames -contains 'project_read_text_file') -and ($liveNames -contains 'project_read_script') -and ($liveNames -contains 'project_get_filesystem_tree')) `
        ("live editor tools/list carries {0} tool(s); the three fenced readers present={1}" -f $liveNames.Count, `
            (($liveNames -contains 'project_read_text_file') -and ($liveNames -contains 'project_read_script') -and ($liveNames -contains 'project_get_filesystem_tree')))

    # -----------------------------------------------------------------------
    #  D-B1: the three link shapes, on the byte-answering tool
    # -----------------------------------------------------------------------
    $probes = @(
        @{ Tag = 'F22_junction_dir'; Path = 'res://link/secret.txt' },
        @{ Tag = 'F24_file_symlink'; Path = 'res://sym_secret.txt' },
        @{ Tag = 'F25_dir_symlink'; Path = 'res://dlink/secret.txt' }
    )
    foreach ($probe in $probes) {
        $r = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = $probe.Path } -Tag $probe.Tag
        $payloadSha = ''
        if ($null -ne $r.Payload) { $payloadSha = [string]$r.Payload.sha256 }
        if ($Phase -eq 'before') {
            Check ('L010_{0}_before_reads_outside' -f $probe.Tag) (($null -ne $r.Payload) -and ($payloadSha -ceq $secretSha)) `
                ("path={0} -> answer sha256={1} == OS sha256 of the outside file {2}; response body sha={3}" -f $probe.Path, $payloadSha, $secretSha, $r.Sha256)
        } else {
            Check ('L010_{0}_after_refused' -f $probe.Tag) (($r.Code -eq -32602) -and (-not [string]::IsNullOrWhiteSpace($r.Suggestion)) -and ($r.Text -notmatch [regex]::Escape($secretToken))) `
                ("path={0} -> code={1} message={2} suggestion={3}; the outside token is absent from the response={4}" -f `
                    $probe.Path, $r.Code, $r.Message, $r.Suggestion, ($r.Text -notmatch [regex]::Escape($secretToken)))
        }
    }

    # The same three shapes through the other two fenced readers.
    $scriptLink = Call-Tool -Port_ $EditorPort -Tool 'project_read_script' -Arguments @{ path = 'res://sym_secret.txt' } -Tag 'F24b_read_script_file_symlink'
    $scriptTree = Call-Tool -Port_ $EditorPort -Tool 'project_read_script' -Arguments @{ path = 'res://link/secret.txt' } -Tag 'F22b_read_script_junction'
    $sceneLink = Call-Tool -Port_ $EditorPort -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://dlink/secret.txt' } -Tag 'F25b_read_scene_content_dir_symlink'
    if ($Phase -eq 'before') {
        Check 'L011_read_script_before_pierces' (($null -ne $scriptLink.Payload) -and ((([string]$scriptLink.Payload.content).Contains($secretToken)) -or (([string]$scriptTree.Payload.content).Contains($secretToken)))) `
            ("project_read_script(res://sym_secret.txt) content carries the outside token={0}; junction variant={1}; project_read_scene_file_content(res://dlink/secret.txt) token={2}" -f `
                ((($null -ne $scriptLink.Payload) -and ([string]$scriptLink.Payload.content).Contains($secretToken))), `
                ((($null -ne $scriptTree.Payload) -and ([string]$scriptTree.Payload.content).Contains($secretToken))), `
                ((($null -ne $sceneLink.Payload) -and ([string]$sceneLink.Payload.content).Contains($secretToken))))
    } else {
        Check 'L011_three_read_tools_same_verdict' (($scriptLink.Code -eq -32602) -and ($scriptTree.Code -eq -32602) -and ($sceneLink.Code -eq -32602)) `
            ("project_read_script(sym) code={0}; project_read_script(junction) code={1}; project_read_scene_file_content(dlink) code={2} (all three must be the same refusal)" -f `
                $scriptLink.Code, $scriptTree.Code, $sceneLink.Code)
    }

    # The tree: a directory argument that IS the link, and the whole project.
    $treeLink = Call-Tool -Port_ $EditorPort -Tool 'project_get_filesystem_tree' -Arguments @{ path = 'res://link' } -Tag 'F30_tree_link_root'
    $treeRoot = Call-Tool -Port_ $EditorPort -Tool 'project_get_filesystem_tree' -Arguments @{ path = 'res://' } -Tag 'F31_tree_project_root'
    if ($Phase -eq 'before') {
        $treeLinkLeaks = $treeLink.Text.Contains('res://link/secret.txt')
        $treeRootLeaks = $treeRoot.Text.Contains('link/secret.txt') -or $treeRoot.Text.Contains('dlink/secret.txt') -or $treeRoot.Text.Contains('sym_secret.txt')
        Check 'L012_tree_before_lists_outside' ($treeLinkLeaks -and $treeRootLeaks) `
            ("project_get_filesystem_tree{res://link} names res://link/secret.txt={0}; the project-root tree names an entry under the links={1}" -f $treeLinkLeaks, $treeRootLeaks)
    } else {
        $treeRootMarks = $treeRoot.Text.Contains('"outside_project":true')
        $treeRootLeaks = $treeRoot.Text.Contains('link/secret.txt') -or $treeRoot.Text.Contains('dlink/secret.txt')
        $treeRootListsEntry = $treeRoot.Text.Contains('res://sym_secret.txt')
        Check 'L012_tree_marks_the_links_and_does_not_descend' (($treeLink.Code -eq -32602) -and $treeRootMarks -and (-not $treeRootLeaks)) `
            ("project_get_filesystem_tree{res://link} code={0}; the project-root tree marks the link entries 'outside_project'={1}; it descends into them (outside files listed)={2}; the file-symlink entry is still named={3}" -f `
                $treeLink.Code, $treeRootMarks, $treeRootLeaks, $treeRootListsEntry)
    }

    # Controls: the inside file, and a `..` that folds back inside the project.
    $inside = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://plain/secret_inside.txt' } -Tag 'C01_inside_control'
    $insideShaOk = ($null -ne $inside.Payload) -and ([string]$inside.Payload.sha256 -ceq $insideSha) -and (([string]$inside.Payload.text).Contains($insideToken))
    Check 'L013_plain_project_file_still_readable' $insideShaOk `
        ("project_read_text_file{res://plain/secret_inside.txt} code={0} sha256={1} == OS sha256 {2}" -f $inside.Code, $(if ($null -ne $inside.Payload) { $inside.Payload.sha256 } else { '<none>' }), $insideSha)

    $dotdot = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://plain/../plain/secret_inside.txt' } -Tag 'C02_dotdot_legal'
    if ($Phase -eq 'before') {
        Check 'L014_legal_dotdot_refused_before' ($dotdot.Code -eq -32602) `
            ("a '..' that folds back inside the project is refused by the blanket rule: code={0} message={1}" -f $dotdot.Code, $dotdot.Message)
    } else {
        $dotdotOk = ($null -ne $dotdot.Payload) -and ([string]$dotdot.Payload.sha256 -ceq $insideSha) -and ([string]$dotdot.Payload.path -ceq 'res://plain/secret_inside.txt')
        Check 'L014_legal_dotdot_succeeds_after' $dotdotOk `
            ("code={0}; echoed path={1}; sha256={2} (the refusal must not over-refuse a '..' that stays inside)" -f $dotdot.Code, $(if ($null -ne $dotdot.Payload) { $dotdot.Payload.path } else { '<none>' }), $(if ($null -ne $dotdot.Payload) { $dotdot.Payload.sha256 } else { '<none>' }))
    }

    $escape = Call-Tool -Port_ $EditorPort -Tool 'project_read_text_file' -Arguments @{ path = 'res://../outside_secret_probe.txt' } -Tag 'C03_dotdot_escape'
    Check 'L015_escaping_dotdot_still_refused' ($escape.Code -eq -32602) `
        ("res://../outside_secret_probe.txt -> code={0} message={1}" -f $escape.Code, $escape.Message)

    # -----------------------------------------------------------------------
    #  D-B2: a script that does not compile
    # -----------------------------------------------------------------------
    $validateBroken = Call-Tool -Port_ $EditorPort -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/broken.gd' } -Tag 'D201_validate_broken'
    $validateGood = Call-Tool -Port_ $EditorPort -Tool 'project_validate_script' -Arguments @{ path = 'res://scripts/good.gd' } -Tag 'D202_validate_good'
    $brokenValid = $false
    if ($null -ne $validateBroken.Payload) { $brokenValid = [bool]$validateBroken.Payload.valid }
    $goodValid = $false
    if ($null -ne $validateGood.Payload) { $goodValid = [bool]$validateGood.Payload.valid }
    Check 'L020_the_same_process_already_knows' ((-not $brokenValid) -and $goodValid) `
        ("project_validate_script{broken.gd} valid={0} error_text={1}; {good.gd} valid={2}" -f $brokenValid, $(if ($null -ne $validateBroken.Payload) { $validateBroken.Payload.error_text } else { '<none>' }), $goodValid)

    $scenePath = Join-Path $Proj 'scenes\main.tscn'
    $sceneShaBefore = Get-Sha $scenePath

    $addBad = Call-Tool -Port_ $EditorPort -Tool 'editor_add_node' -Arguments @{ type = 'Node2D'; name = 'Bad'; parent_path = '.' } -Tag 'D210_add_bad_node'
    $addGood = Call-Tool -Port_ $EditorPort -Tool 'editor_add_node' -Arguments @{ type = 'Node2D'; name = 'Good'; parent_path = '.' } -Tag 'D211_add_good_node'
    $attachGood = Call-Tool -Port_ $EditorPort -Tool 'editor_set_node_script_batch' -Arguments @{ node_paths = @('Good'); script_path = 'res://scripts/good.gd' } -Tag 'D212_batch_good'
    $attachBrokenBatch = Call-Tool -Port_ $EditorPort -Tool 'editor_set_node_script_batch' -Arguments @{ node_paths = @('Bad'); script_path = 'res://scripts/broken.gd' } -Tag 'D213_batch_broken'
    $attachBrokenSingle = Call-Tool -Port_ $EditorPort -Tool 'editor_set_node_script' -Arguments @{ node_path = 'Bad'; script_path = 'res://scripts/broken.gd' } -Tag 'D214_single_broken'

    $goodAttached = $attachGood.Text.Contains('"attached":true') -and $attachGood.Text.Contains('"readable":true')
    Check 'L021_compatible_script_is_readable' (($null -eq $attachGood.Code) -and $goodAttached) `
        ("editor_set_node_script_batch{Good, good.gd}: code={0} body carries attached:true and readable:true={1}" -f $attachGood.Code, $goodAttached)

    if ($Phase -eq 'before') {
        $batchLies = ($null -eq $attachBrokenBatch.Code) -and $attachBrokenBatch.Text.Contains('"attached":true') -and $attachBrokenBatch.Text.Contains('"readable":true')
        $singleLies = ($null -eq $attachBrokenSingle.Code) -and $attachBrokenSingle.Text.Contains('"attached":true')
        Check 'L022_before_uncompilable_script_reported_attached' ($batchLies -and $singleLies) `
            ("batch{broken.gd}: no error={0} attached:true={1} readable:true={2} sha={3}; singular{broken.gd}: no error={4} attached:true={5} sha={6}" -f `
                ($null -eq $attachBrokenBatch.Code), $attachBrokenBatch.Text.Contains('"attached":true'), $attachBrokenBatch.Text.Contains('"readable":true'), $attachBrokenBatch.Sha256, `
                ($null -eq $attachBrokenSingle.Code), $attachBrokenSingle.Text.Contains('"attached":true'), $attachBrokenSingle.Sha256)
    } else {
        $batchRefuses = ($attachBrokenBatch.Code -eq -32000) -and (-not [string]::IsNullOrWhiteSpace($attachBrokenBatch.Suggestion)) -and `
            $attachBrokenBatch.Text.Contains('"readable":false') -and (-not $attachBrokenBatch.Text.Contains('"attached":true'))
        $singleRefuses = ($attachBrokenSingle.Code -eq -32000) -and (-not [string]::IsNullOrWhiteSpace($attachBrokenSingle.Suggestion))
        Check 'L022_after_uncompilable_script_refused_and_rolled_back' ($batchRefuses -and $singleRefuses) `
            ("batch{broken.gd}: code={0} batch.status/readable:false present={1} attached:true absent={2} message={3}; singular: code={4} message={5}" -f `
                $attachBrokenBatch.Code, $attachBrokenBatch.Text.Contains('"readable":false'), (-not $attachBrokenBatch.Text.Contains('"attached":true')), $attachBrokenBatch.Message, $attachBrokenSingle.Code, $attachBrokenSingle.Message)
    }

    # Save, then read the saved text back with a tool: did broken.gd reach the file?
    $save = Call-Tool -Port_ $EditorPort -Tool 'editor_save_scene' -Arguments @{ path = 'res://scenes/main.tscn' } -Tag 'D220_save_scene'
    $savedRead = Call-Tool -Port_ $EditorPort -Tool 'project_read_scene_file_content' -Arguments @{ path = 'res://scenes/main.tscn' } -Tag 'D221_read_saved_scene'
    $savedText = [string]$savedRead.Payload.content
    $brokenInSavedScene = $savedText.Contains('broken.gd')
    $goodInSavedScene = $savedText.Contains('good.gd')
    [IO.File]::WriteAllText((Join-Path $Ev 'saved_scene.txt'), $savedText, (New-Object Text.UTF8Encoding($false)))
    if ($Phase -eq 'before') {
        Check 'L023_before_broken_script_reaches_the_saved_scene' ($brokenInSavedScene -and $goodInSavedScene) `
            ("saved main.tscn names broken.gd={0} good.gd={1}; disk sha before={2} after={3}" -f $brokenInSavedScene, $goodInSavedScene, $sceneShaBefore, (Get-Sha $scenePath))
    } else {
        $rollbackVerdict = $attachBrokenBatch.Text.Contains('"rolled_back":true') -or $attachBrokenBatch.Code -eq -32000
        Check 'L023_after_broken_script_is_not_in_the_scene' ((-not $brokenInSavedScene) -and $goodInSavedScene -and $rollbackVerdict) `
            ("saved main.tscn names broken.gd={0} (must be false) good.gd={1}; the batch refusal was all-or-nothing={2}" -f $brokenInSavedScene, $goodInSavedScene, $rollbackVerdict)
    }
    $brokenInSceneBeforeGame = $brokenInSavedScene
} finally {
    Stop-Engine $editorHandle
}

# ---------------------------------------------------------------------------
#  game endpoint: the engine loads the saved scene and drops what it cannot load
# ---------------------------------------------------------------------------
try {
    $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, ("--mcp-port=" + $GamePort)) -LogName 'game'
    if (Wait-ForPump -Port_ $GamePort) {
        $gameTree = Call-Tool -Port_ $GamePort -Tool 'running_game_get_scene_tree' -Arguments @{} -Tag 'G01_game_scene_tree'
        $nodeHasScript = $null
        $nodeSeen = $false
        try {
            foreach ($child in @($gameTree.Payload.tree.children)) {
                if ([string]$child.name -ceq 'Bad') {
                    $nodeSeen = $true
                    $nodeHasScript = (@($child.PSObject.Properties.Name) -contains 'script')
                }
            }
        } catch { }
        if ($Phase -eq 'before') {
            Check 'L030_before_game_dropped_the_script' ($nodeSeen -and ($nodeHasScript -eq $false) -and $brokenInSceneBeforeGame) `
                ("the game's Bad node carries a script={0} (the .tscn names broken.gd={1}), so the editor's 'readable:true' was a claim the engine contradicts" -f $nodeHasScript, $brokenInSceneBeforeGame)
        } else {
            $goodNodeHasScript = $false
            try {
                foreach ($child in @($gameTree.Payload.tree.children)) {
                    if ([string]$child.name -ceq 'Good') { $goodNodeHasScript = (@($child.PSObject.Properties.Name) -contains 'script') }
                }
            } catch { }
            Check 'L030_after_game_keeps_the_compatible_script_only' (($goodNodeHasScript -eq $true) -and ($nodeHasScript -eq $false) -and (-not $brokenInSceneBeforeGame)) `
                ("the game's Good node carries a script={0}; Bad carries one={1}; the saved scene named broken.gd={2}" -f $goodNodeHasScript, $nodeHasScript, $brokenInSceneBeforeGame)
        }

        # The GAME-side fence: the same junction probe as F22, on 9889.
        $gameLink = Call-Tool -Port_ $GamePort -Tool 'project_read_text_file' -Arguments @{ path = 'res://link/secret.txt' } -Tag 'G04_junction_game_endpoint'
        if ($Phase -eq 'before') {
            $gamePayloadSha = ''
            if ($null -ne $gameLink.Payload) { $gamePayloadSha = [string]$gameLink.Payload.sha256 }
            Check 'L031_before_game_endpoint_pierces' ($gamePayloadSha -ceq $secretSha) `
                ("game 9889 project_read_text_file{res://link/secret.txt} sha256={0} == OS sha256 {1}; response sha={2} (byte-identical to F22's)" -f $gamePayloadSha, $secretSha, $gameLink.Sha256)
        } else {
            Check 'L031_after_game_endpoint_refuses' (($gameLink.Code -eq -32602) -and (-not $gameLink.Text.Contains($secretToken))) `
                ("game 9889 project_read_text_file{res://link/secret.txt} code={0} message={1}; outside token present={2}" -f $gameLink.Code, $gameLink.Message, $gameLink.Text.Contains($secretToken))
        }
        Stop-Engine $gameHandle
    } else {
        Check 'L029_game_ready' $false ("game on {0} did not answer GET /mcp with +20 frames" -f $GamePort)
    }
} finally {
    Stop-Engine $gameHandle
}

# The engine's own parse-error line for a script it drops while loading the scene.
$gameErr = Join-Path $LogRoot 'game.err.log'
$loadMessageCount = -1
if (Test-Path $gameErr) {
    $errText = [IO.File]::ReadAllText($gameErr)
    $loadMessageCount = ([regex]::Matches($errText, [regex]::Escape('GDScript::reload (res://scripts/broken.gd'))).Count
}
if ($Phase -eq 'before') {
    Check 'L040_before_the_engine_reports_the_dropped_script' ($loadMessageCount -ge 1) `
        ("game.err.log occurrences of 'GDScript::reload (res://scripts/broken.gd': {0} (the engine drops the attachment the tools called 'readable')" -f $loadMessageCount)
} else {
    Check 'L040_after_the_engine_never_sees_the_broken_script' ($loadMessageCount -eq 0) `
        ("game.err.log occurrences of 'GDScript::reload (res://scripts/broken.gd': {0} (the refused attachment never reached the saved scene)" -f $loadMessageCount)
}

$portVerdict = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'L050_user_port_9877_untouched' ($portVerdict.pass) ("{0}: {1}" -f $portVerdict.classification, $portVerdict.evidence)

$failures = 0
Write-Host ''
Write-Host '--- summary ---'
foreach ($c in $script:Checks) {
    if (-not $c.pass) { $failures++ }
    Write-Host ("[{0}] {1} :: {2}" -f $(if ($c.pass) { 'PASS' } else { 'FAIL' }), $c.id, $c.evidence)
}
$summaryFile = Join-Path $Ev 'summary.txt'
[IO.File]::WriteAllLines($summaryFile, @($script:Checks | ForEach-Object { ("[{0}] {1} :: {2}" -f $(if ($_.pass) { 'PASS' } else { 'FAIL' }), $_.id, $_.evidence) }))
Write-Host ('--- checks: {0}, failures: {1} ---' -f $script:Checks.Count, $failures)
Write-Host ('--- evidence root: {0} ---' -f $Ev)
if ($failures -gt 0) { Write-Host ('MCP077 LIVE EVIDENCE FAILED (phase {0}): {1}' -f $Phase, $failures); exit 1 }
Write-Host ('MCP077 LIVE EVIDENCE PASS (phase ' + $Phase + ')')
exit 0
