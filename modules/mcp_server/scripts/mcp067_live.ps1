# =============================================================================
#  mcp067_live.ps1 -- TASK-067 live evidence (pure ASCII).
#
#  Two questions, measured on a real windowed editor and a real MCP port:
#
#    (1) `project_list_scripts` on a GDScript + C# mixed project: are BOTH
#        languages listed, with one and the same field shape, and is the whole
#        set exactly "the script languages this build registered"?
#        (REPORT-066 F-066-1.)
#
#    (2) `project.godot` with four hand written probe comments, one of them in a
#        NON-last `[input]` section, started in a WINDOWED editor: do the comments
#        survive verbatim? (REPORT-066 F-066-2.) The pre/post phases are the two
#        halves of the red/green pair: `-Phase pre` is run against the binary that
#        still has the defect, `-Phase post` against the fixed one.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp067_live.ps1 `
#        -Phase pre  -Label mono-prefix -EditorExe bin\godot.windows.editor.x86_64.mono.console.exe
#
#  Discipline: 9877 is asserted untouched before and after; only 9888 is used;
#  only PIDs this script started are stopped; every request and response body is
#  written through `mcp_evidence_guard.ps1` (unique sha-bearing name, refusal to
#  overwrite referenced evidence).
# =============================================================================
param(
    [Parameter(Mandatory = $true)][ValidateSet('pre', 'post')][string]$Phase,
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string]$EditorExe
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mcp067_env.ps1')

if (-not [IO.Path]::IsPathRooted($EditorExe)) {
    $EditorExe = Join-Path $RepoRoot $EditorExe
}

$RunDir = Join-Path $EvidenceRoot ('run-' + $Label)
$CallDir = Join-Path $RunDir 'calls'
Ensure-Dir $CallDir | Out-Null
Ensure-Dir $IoRoot | Out-Null

Write-Host ('=== mcp067_live phase={0} label={1}' -f $Phase, $Label)
Write-Host ('    editor: {0}' -f $EditorExe)
Write-Host ('    run dir: {0}' -f $RunDir)

Assert-Port9877Untouched 'p0_port_9877_free_before'

# ---------------------------------------------------------------------------
#  Version anchor: the binary that produced this evidence says which revision it
#  is on its own, so the report never has to guess.
# ---------------------------------------------------------------------------
$versionText = Get-EngineVersion -Exe $EditorExe -LogPath (Join-Path $RunDir 'engine_version.txt')
Add-Check 'p0_engine_version_recorded' ([bool]$versionText) $versionText

$StartTime = (Get-Date).ToString('o')
Add-Heartbeat ('live start phase=' + $Phase + ' label=' + $Label)

# ---------------------------------------------------------------------------
#  (1) project_list_scripts on a GDScript + C# mixed project.
# ---------------------------------------------------------------------------
$mixedResult = $null
$mixedFsTree = $null
$editorPid = $null

Reset-MixedProject | Out-Null
$mixedProjectGodot = Join-Path $MixedProj 'project.godot'
$mixedGodotCs = @(Get-ChildItem -LiteralPath (Join-Path $MixedProj 'scripts') -Filter '*.cs' -File | ForEach-Object { $_.FullName })
$mixedGodotGd = @(Get-ChildItem -LiteralPath (Join-Path $MixedProj 'scripts') -Filter '*.gd' -File | ForEach-Object { $_.FullName })
$mixedCachedCs = @(Get-ChildItem -LiteralPath $MixedProj -Recurse -Filter '*.cs' -File | Where-Object { $_.FullName -notlike (Join-Path $MixedProj 'scripts\*') } | ForEach-Object { $_.FullName })
Add-Check 'p1_mixed_fixture_root_is_a_project' (Test-Path -LiteralPath $mixedProjectGodot) ('project.godot at ' + $MixedProj)
Add-Check 'p1_mixed_fixture_has_both_languages' (($mixedGodotCs.Count -ge 6) -and ($mixedGodotGd.Count -ge 2)) `
    ('res://scripts cs=' + $mixedGodotCs.Count + ' gd=' + $mixedGodotGd.Count + ' generated .cs elsewhere=' + $mixedCachedCs.Count)

Reset-McpCallSeq
$editor = Start-McpEditor -Exe $EditorExe -ProjectPath $MixedProj -Port $EditorPort
$editorPid = $editor.Id
Add-Heartbeat ('started mixed-project editor pid=' + $editorPid)
$portUp = Wait-Port -Port $EditorPort -TimeoutSec 180
Add-Check 'p1_editor_port_bound' $portUp ('port ' + $EditorPort + ' listening')
if ($portUp) {
    Start-Sleep -Seconds 3
    $mixedResult = Invoke-Tool -Port $EditorPort -Tool 'project_list_scripts' -Arguments ([ordered]@{}) -Directory $CallDir -Leaf ($Label + '_p1_list_scripts')
    $mixedFsTree = Invoke-Tool -Port $EditorPort -Tool 'project_get_filesystem_tree' -Arguments ([ordered]@{ path = 'res://scripts' }) -Directory $CallDir -Leaf ($Label + '_p1_fs_tree_scripts')
    # The independent cross-check that makes "cs=0" a DEFECT rather than a
    # capability gap: the very same process can READ the .cs file as a project
    # script, so the file is there, readable and under the walk's own root.
    $mixedReadCs = Invoke-Tool -Port $EditorPort -Tool 'project_read_script' -Arguments ([ordered]@{ path = 'res://scripts/Main.cs' }) -Directory $CallDir -Leaf ($Label + '_p1_read_main_cs')
}
Stop-OwnProcess -Process $editor -LogPath $EditorOutLog
Start-Sleep -Seconds 2
Add-Heartbeat ('stopped mixed-project editor pid=' + $editorPid)

if ($null -ne $mixedResult) {
    $body = Get-ToolBody $mixedResult
    Add-Check 'p1_call_is_not_an_error' ((Get-ErrorCode $mixedResult) -eq 0) ('code=' + (Get-ErrorCode $mixedResult) + ' message=' + (Get-ErrorMessage $mixedResult))
    if ($null -ne $body) {
        $scripts = @($body.scripts)
        $allStrings = $true
        foreach ($entry in $scripts) {
            if ($entry -isnot [string]) { $allStrings = $false }
        }
        $inScriptsDir = @($scripts | Where-Object { $_ -like 'res://scripts/*' })
        $csInScripts = @($inScriptsDir | Where-Object { $_ -like '*.cs' })
        $gdInScripts = @($inScriptsDir | Where-Object { $_ -like '*.gd' })
        $csAnywhere = @($scripts | Where-Object { $_ -like '*.cs' })
        $gdAnywhere = @($scripts | Where-Object { $_ -like '*.gd' })
        $gdshaderAnywhere = @($scripts | Where-Object { $_ -like '*.gdshader' })
        $godotCacheCs = @($scripts | Where-Object { $_ -like 'res://.godot/*' -and $_ -like '*.cs' })
$portUp2 = Wait-Port -Port $EditorPort -TimeoutSec 180
Add-Check 'p2_editor_port_bound' $portUp2 ('port ' + $EditorPort + ' listening')
$snapD = $null
$toolWrite = $null
$snapE = $null
$snapF = $null
if ($portUp2) {
    Start-Sleep -Seconds 3
    $snapD = Save-ProjectSnapshot -Path $commentProjectGodot -Leaf ($Label + '_p2_D_windowed_startup') -Directory $RunDir
    $mtimeAfterStartup = (Get-Item -LiteralPath $commentProjectGodot).LastWriteTimeUtc
    Add-Check 'p2_the_editor_really_wrote_the_file' ($mtimeAfterStartup -ne $mtimeBefore) `
        ('mtime before=' + $mtimeBefore.ToString('o') + ' after=' + $mtimeAfterStartup.ToString('o'))

    # The tool-write path is the OTHER half of the question and must not regress:
    # `editor_add_input_action` and `project_set_setting` publish one section each
    # (TASK-059). They run on the file the editor has already re-saved.
    $toolWrite = Invoke-Tool -Port $EditorPort -Tool 'editor_add_input_action' -Arguments ([ordered]@{ action = ('mcp067_probe_' + $Phase); key = 'F9' }) -Directory $CallDir -Leaf ($Label + '_p2_add_input_action')
    $toolWrite2 = Invoke-Tool -Port $EditorPort -Tool 'project_set_setting' -Arguments ([ordered]@{ key = 'physics/common/physics_ticks_per_second'; value = 61 }) -Directory $CallDir -Leaf ($Label + '_p2_set_setting')
    Start-Sleep -Seconds 2
    $snapF = Save-ProjectSnapshot -Path $commentProjectGodot -Leaf ($Label + '_p2_F_after_tool_writes') -Directory $RunDir
    Add-Check 'p2_tool_write_add_input_action_ok' ((Get-ErrorCode $toolWrite) -eq 0) ('code=' + (Get-ErrorCode $toolWrite) + ' msg=' + (Get-ErrorMessage $toolWrite))
    Add-Check 'p2_tool_write_set_setting_ok' ((Get-ErrorCode $toolWrite2) -eq 0) ('code=' + (Get-ErrorCode $toolWrite2) + ' msg=' + (Get-ErrorMessage $toolWrite2))
}
Stop-OwnProcess -Process $editor2 -LogPath $EditorOutLog
Start-Sleep -Seconds 2
$snapE = Save-ProjectSnapshot -Path $commentProjectGodot -Leaf ($Label + '_p2_E_after_windowed_session') -Directory $RunDir
Add-Heartbeat ('stopped comment-project editor pid=' + $editor2Pid)

# The B -> D comparison is the finding itself: same file, one windowed startup.
Add-Check 'p2_fixture_had_four_comments_before_startup' ($snapB.CommentLines -eq 4) ('B comments=' + $snapB.CommentLines)
if ($null -ne $snapD) {
    $survD = Get-ProbeCommentSurvivalInText -Text $snapD.Text
    if ($Phase -eq 'pre') {
        Add-Check 'p2_PRE_defect_reproduces_comments_lost' (($snapB.Sha256 -ne $snapD.Sha256) -and ($snapD.CommentLines -eq 0)) `
            ('B sha=' + $snapB.Sha256 + ' D sha=' + $snapD.Sha256 + ' D comments=' + $snapD.CommentLines + ' survival=' + (@($survD) -join ','))
    } else {
        Add-Check 'p2_POST_startup_kept_every_comment' ($snapD.CommentLines -eq 4) ('D comments=' + $snapD.CommentLines + ' sha=' + $snapD.Sha256)
        Add-Check 'p2_POST_startup_kept_every_comment_verbatim' ([bool](@($survD | Where-Object { $_ -eq $false }).Count -eq 0)) `
            ('D survival vector=' + (@($survD) -join ','))
        # The comment SEQUENCE, not just the count: a writer that moved a comment
        # into another section would keep the count and lose the meaning.
        $bComments = @([IO.File]::ReadAllText($snapB.EvidencePath, (New-Object Text.UTF8Encoding($false))) -split "`n" | Where-Object { $_.TrimStart().StartsWith(';') })
        $dComments = @([IO.File]::ReadAllText($snapD.EvidencePath, (New-Object Text.UTF8Encoding($false))) -split "`n" | Where-Object { $_.TrimStart().StartsWith(';') })
        $sameCommentSequence = (($bComments -join "`n") -eq ($dComments -join "`n"))
        Add-Check 'p2_POST_comment_lines_are_the_same_sequence' $sameCommentSequence ('B=' + $bComments.Count + ' D=' + $dComments.Count)
        # NOT an assertion that the bytes are identical: the call site's other job
        # is to persist the settings the editor holds (the feature list is
        # recomputed from the rendering API and from whether a `.csproj` exists),
        # so a settings line MAY legitimately change. The claim under test is that
        # nothing but a setting changes, so the diff is recorded instead of
        # asserted away.
        $bLines = @([IO.File]::ReadAllText($snapB.EvidencePath, (New-Object Text.UTF8Encoding($false))) -split "`n")
        $dLines = @([IO.File]::ReadAllText($snapD.EvidencePath, (New-Object Text.UTF8Encoding($false))) -split "`n")
        $onlyInD = @($dLines | Where-Object { $bLines -notcontains $_ })
        $onlyInB = @($bLines | Where-Object { $dLines -notcontains $_ })
        Write-McpSummary -RunDir $RunDir -Leaf ($Label + '_p2_B_vs_D_line_diff') -Object @{
            bytes_identical = ($snapB.Sha256 -eq $snapD.Sha256)
            b_sha256        = $snapB.Sha256
            d_sha256        = $snapD.Sha256
            only_in_d       = $onlyInD
            only_in_b       = $onlyInB
        }
        Add-Check 'p2_POST_settings_line_diff_recorded' $true ('only_in_D=' + $onlyInD.Count + ' only_in_B=' + $onlyInB.Count)
    }
}
if ($null -ne $snapF) {
    $fSurvives = Get-ProbeCommentSurvivalInText -Text $snapF.Text
    Add-Check 'p2_tool_writes_kept_every_comment_verbatim' ([bool](@($fSurvives | Where-Object { $_ -eq $false }).Count -eq 0)) `
        ('F survival vector=' + (@($fSurvives) -join ',') + ' comments=' + $snapF.CommentLines)
    $fText = $snapF.Text
    $hasProbeAction = $fText.Contains('mcp067_probe_' + $Phase)
    $hasTicks = $fText.Contains('common/physics_ticks_per_second=61')
    Add-Check 'p2_tool_writes_landed_in_the_file' ($hasProbeAction -and $hasTicks) ('probe_action=' + $hasProbeAction + ' ticks61=' + $hasTicks)
}

# `[input]` is not the last section: the comment that follows the action inside
# `[input]` must still be inside `[input]` afterwards, i.e. before `[physics]`.
if ($null -ne $snapE) {
    $commentThree = '; mcp067 comment 3 of 4 - inside [input] after the action'
    $commentFour = '; mcp067 comment 4 of 4 - inside [rendering], the last section'
        Add-Check 'p2_POST_tool_writes_kept_every_comment_verbatim' ([bool](@($fSurvives | Where-Object { $_ -eq $false }).Count -eq 0)) `
            ('F survival vector=' + (@($fSurvives) -join ',') + ' comments=' + $snapF.CommentLines)
    }
    $fText = $snapF.Text
    $hasProbeAction = $fText.Contains('mcp067_probe_' + $Phase)
    $hasTicks = $fText.Contains('common/physics_ticks_per_second=61')
    Add-Check 'p2_tool_writes_landed_in_the_file' ($hasProbeAction -and $hasTicks) ('probe_action=' + $hasProbeAction + ' ticks61=' + $hasTicks)
}

# `[input]` is not the last section: the comment that follows the action inside
# `[input]` must still be inside `[input]` afterwards, i.e. before `[physics]`.
# Asserted only where the comments are expected to exist; in the pre phase the
# four probe comments are gone and the positions are -1, which is the finding.
if (($null -ne $snapE) -and ($Phase -eq 'post')) {
    $commentThree = '; mcp067 comment 3 of 4 - inside [input] after the action'
    $commentFour = '; mcp067 comment 4 of 4 - inside [rendering], the last section'
    $i3 = $snapE.Text.IndexOf($commentThree)
    $iPhysics = $snapE.Text.IndexOf('[physics]')
    $i4 = $snapE.Text.IndexOf($commentFour)
    $iRendering = $snapE.Text.IndexOf('[rendering]')
    $inOrder = ($i3 -ge 0) -and ($i3 -lt $iPhysics) -and ($iPhysics -lt $iRendering) -and ($i4 -gt $iRendering)
    Add-Check 'p2_nonlast_input_comment_stays_in_its_section' $inOrder `
        ('c3=' + $i3 + ' [physics]=' + $iPhysics + ' [rendering]=' + $iRendering + ' c4=' + $i4)
}

$snapshotTable = @(
    [ordered]@{ point = 'A_hand_written'; sha256 = $snapA.Sha256; bytes = $snapA.Bytes; comments = $snapA.CommentLines; note = 'written by Reset-CommentProject' },
    [ordered]@{ point = 'B_after_import'; sha256 = $snapB.Sha256; bytes = $snapB.Bytes; comments = $snapB.CommentLines },
    [ordered]@{ point = 'D_windowed_startup'; sha256 = $(if ($snapD) { $snapD.Sha256 } else { '' }); bytes = $(if ($snapD) { $snapD.Bytes } else { 0 }); comments = $(if ($snapD) { $snapD.CommentLines } else { -1 }) },
    [ordered]@{ point = 'F_after_tool_writes'; sha256 = $(if ($snapF) { $snapF.Sha256 } else { '' }); bytes = $(if ($snapF) { $snapF.Bytes } else { 0 }); comments = $(if ($snapF) { $snapF.CommentLines } else { -1 }) },
    [ordered]@{ point = 'E_after_windowed_session'; sha256 = $snapE.Sha256; bytes = $snapE.Bytes; comments = $snapE.CommentLines }
)
Write-McpSummary -RunDir $RunDir -Leaf ($Label + '_p2_snapshots') -Object @{ snapshots = $snapshotTable; probe_comments = $ProbeComments }

Assert-Port9877Untouched 'p0_port_9877_free_after'

# ---------------------------------------------------------------------------
#  Machine readable total for this run.
# ---------------------------------------------------------------------------
$checks = @($script:Checks)
$failed = @($checks | Where-Object { -not $_.pass })
$summary = [ordered]@{
    task          = 'TASK-067'
    phase         = $Phase
    label         = $Label
    editor_exe    = $EditorExe
    engine_version = $versionText
    started       = $StartTime
    finished      = (Get-Date).ToString('o')
    checks_total  = $checks.Count
    checks_passed = @($checks | Where-Object { $_.pass }).Count
    checks_failed = $failed.Count
    checks        = $checks
}
Write-McpSummary -RunDir $RunDir -Leaf ($Label + '_run_summary') -Object $summary

Write-Host ('MCP067 LIVE phase={0} label={1} checks_total={2} checks_failed={3}' -f $Phase, $Label, $checks.Count, $failed.Count)
foreach ($f in $failed) { Write-Host ('  FAIL {0} :: {1}' -f $f.id, $f.detail) }
if ($failed.Count -gt 0) { exit 1 }
exit 0