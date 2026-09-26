# =============================================================================
#  mcp042_projectrewrite_and_honesty_evidence.ps1 -- TASK-042 sections 2 and 3
#
#  Section 2: what does `editor_add_input_action` really do to a real, hand
#  commented `project.godot`? The specimen is a **byte copy** of this fork's own
#  `modules/gdscript/tests/scripts/project.godot` - a real project file that is
#  shipped in the tree, carries four hand-written comments (one of which asks
#  that the editor not save changes into it) and a `[input]` section with a
#  multi-line value. It is copied into a scratch directory, so the file in the
#  tree is never touched.
#
#  Measured: the byte difference, what is lost (comments, formatting), what
#  survives, and whether the rewrite is at least idempotent. Then the *feasible
#  alternative* is measured too: a text-level splice of only the new `[input]`
#  entry, verified by a game process that loads the file through
#  `InputMap::load_from_project_settings()` at its own startup.
#
#  TASK-069 section 2.1 rewrote the three "what is lost" expectations
#  (A22/A23/A26b, and the stale NAME of A21) because TASK-057 patch 2 / TASK-059
#  D-4 moved this tool onto `ProjectSettings::save_custom_section()`, which
#  replaces only the target section's text. They are derived from the specimen's
#  own bytes now (see the block before A22); the old pinned forms are recorded in
#  docs/reports/REPORT-069-gate-integrity.md and machine-checked by
#  scripts/mcp069_stale_expectation_reverse_probe.ps1.
#
#  Section 3 (O-6 honesty): the same run pins the tool's new `action_state` and
#  `project_entry` fields on the wire, and the honest negative (a name
#  ProjectSettings cannot address as a key).
#
#  Port discipline: 9877 is only *observed*, and only through the shared
#  classification in mcp_port_guard.ps1; the editor uses 9888, the game 9889.
#  ASCII only.
# =============================================================================

param(
    [int]$EditorPort = 9888,
    [int]$GamePort = 9889,
    [int]$UserPort = 9877,
    [string]$OutRoot = '',
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($OutRoot)) { $OutRoot = Join-Path $env:TEMP 'mcp042-rewrite' }
if ([string]::IsNullOrEmpty($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }

$Engine = Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe'
$Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$Specimen = Join-Path $RepoRoot 'modules\gdscript\tests\scripts\project.godot'
$Root = $OutRoot
$Proj = Join-Path $Root 'proj'
$Ev = Join-Path $Root 'evidence'
$LogRoot = Join-Path $Root 'logs'
$ProjectFile = Join-Path $Proj 'project.godot'
$utf8 = [Text.Encoding]::UTF8
$NewAction = 'mcp042_mirrored_action'
$ExistingAction = 'test_input_action'

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

function Get-PayloadText {
    param($Response)
    try {
        $envelope = Get-Envelope $Response
        if ($null -eq $envelope.result) { return '' }
        return [string]$envelope.result.content[0].text
    } catch { return '' }
}

function Get-Payload {
    param($Response)
    $text = Get-PayloadText $Response
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return ConvertFrom-Json $text } catch { return $null }
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

function Get-InputSection {
    param([string]$Text)
    $start = $Text.IndexOf("[input]")
    if ($start -lt 0) { return '' }
    $rest = $Text.Substring($start)
    $next = $rest.IndexOf("`n[", 1)
    if ($next -ge 0) { return $rest.Substring(0, $next) }
    return $rest
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
#  Scratch project: a byte copy of the real, commented specimen
# =============================================================================
Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Ev, $LogRoot, $Proj, (Join-Path $Proj 'scenes') | Out-Null
Copy-Item -Path $Specimen -Destination $ProjectFile -Force
# A scene a game process can be pointed at **on its command line**
# (`main.cpp:2033-2036`: an unrecognised argument goes into `main_args`, so the
# "no main scene defined" abort at `main.cpp:2317` is skipped and
# `main.cpp:4088-4104` loads this scene). Doing it this way keeps `project.godot`
# free of any harness-only line, which is what makes the byte claims below clean.
$scene = '[gd_scene format=3]' + "`n`n" + '[node name="Main" type="Node"]' + "`n"
Write-McpUtf8NoBom -Path (Join-Path $Proj 'scenes\main.tscn') -Text $scene

$originalBytes = [IO.File]::ReadAllBytes($ProjectFile)
$originalText = [IO.File]::ReadAllText($ProjectFile, $utf8)
$originalSha = Get-Sha $ProjectFile

$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore (Get-ListenerPid -Port_ $UserPort)

Check 'A01_specimen_copied_byte_for_byte' ((Get-Sha $Specimen) -eq $originalSha) `
    ("modules/gdscript/tests/scripts/project.godot sha256={0}; the scratch copy has the same sha256 and {1} bytes (the tree's file is never touched)" -f $originalSha, $originalBytes.Length)
Check 'A02_ports_free' (((Get-ListenerPid -Port_ $EditorPort) -eq -1) -and ((Get-ListenerPid -Port_ $GamePort) -eq -1)) `
    ("editor {0} owner={1}; game {2} owner={3}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort), $GamePort, (Get-ListenerPid -Port_ $GamePort))

$import = Import-McpProject -Engine $Engine -Path $Proj -LogDirectory $LogRoot -Name 'import'
Register-McpPortGuardCommandLine -Guard $script:McpPortGuard -CommandLine $import.command
Check 'A03_import_ok' ($import.exit_code -eq 0) ("--import exit={0} after {1} attempt(s)" -f $import.exit_code, $import.attempts)

$originalCommentLines = @($originalText -split "`r?`n" | Where-Object { $_.StartsWith(';') })
Check 'A04_the_specimen_really_is_commented' ($originalCommentLines.Count -eq 4) `
    ("{0} hand-written comment line(s) in the specimen: {1}" -f $originalCommentLines.Count, ($originalCommentLines -join ' | '))

# =============================================================================
#  Section 2, part 1: the full rewrite, measured
# =============================================================================
$editorHandle = $null
$afterText = ''
$afterSha = ''
try {
    $editorHandle = Start-Engine -Arguments @('--headless', '-e', '--path', $Proj, "--mcp-port=$EditorPort") -LogName 'editor'
    Check 'A10_editor_ready' (Wait-ForPump -Port_ $EditorPort) ("editor on {0} answered GET /mcp with +20 frames" -f $EditorPort)
    Check 'A11_editor_did_not_touch_the_file_on_startup' ((Get-Sha $ProjectFile) -eq $originalSha) `
        ("sha256 before={0} after the editor came up={1}" -f $originalSha, (Get-Sha $ProjectFile))

    $add = Invoke-Tool -Id 'A20_add_action' -Tool 'editor_add_input_action' -Arguments @{ action = $NewAction; key = 'J' }
    $addPayload = Get-Payload $add

    $afterText = [IO.File]::ReadAllText($ProjectFile, $utf8)
    $afterBytes = [IO.File]::ReadAllBytes($ProjectFile)
    $afterSha = Get-Sha $ProjectFile

    # --- section 3, on the wire: the honest pair ---------------------------
    Check 'A20_response_distinguishes_created_from_existing' `
        (((Get-ErrorCode $add) -eq 0) -and ([bool](Get-PropertyValue $addPayload 'created') -eq $true) -and ([string](Get-PropertyValue $addPayload 'action_state') -ceq 'created') -and ([string](Get-PropertyValue $addPayload 'project_entry') -ceq 'created') -and ([bool](Get-PropertyValue $addPayload 'persisted') -eq $true)) `
        ("created={0} action_state={1} project_entry={2} persisted={3}" -f (Get-PropertyValue $addPayload 'created'), (Get-PropertyValue $addPayload 'action_state'), (Get-PropertyValue $addPayload 'project_entry'), (Get-PropertyValue $addPayload 'persisted'))

    # TASK-069 section 2.1: the check kept its predicate (`the file on disk
    # changed`) and lost its stale NAME. It used to be called
    # `A21_whole_file_was_rewritten`, which TASK-057 patch 2 / TASK-059 D-4 made
    # false while the predicate kept passing - a name that contradicts A22/A23 in
    # the same log is the same defect class as the three expectations below.
    Check 'A21_the_file_on_disk_changed_after_the_call' (($afterSha -ne $originalSha)) `
        ("sha256 {0} -> {1}; bytes {2} -> {3}" -f $originalSha, $afterSha, $originalBytes.Length, $afterBytes.Length)

    # --- what is lost (TASK-069 section 2.1: DERIVED, not pinned) ------------
    #
    # TASK-057 patch 2 / TASK-059 D-4 moved `editor_add_input_action`'s
    # persistence onto `ProjectSettings::save_custom_section()`, which replaces
    # only the target section's text and copies every other byte of the file
    # through (the contract description for the tool says exactly this, so this
    # is the declared behaviour being measured). TASK-042's A22/A23/A26b pinned
    # the OLD whole-file writer: "all four comments are gone", "the engine writes
    # its own header", "the only lost lines are the 4 comments". All three are
    # false by construction now, and none of them is relaxed here - the boundary
    # is COMPUTED from the specimen text instead:
    #
    #   * everything before the first `[input]` header is the prologue; the
    #     section writer must copy it through byte for byte;
    #   * only the target section may be re-emitted, so nothing OUTSIDE it may
    #     disappear;
    #   * the engine's fixed header must not appear, because the prologue (which
    #     carries the original first line) is still the head of the file.
    $inputHeaderIndex = $originalText.IndexOf('[input]')
    $originalPrologue = if ($inputHeaderIndex -ge 0) { $originalText.Substring(0, $inputHeaderIndex) } else { '' }
    $originalSectionText = if ($inputHeaderIndex -ge 0) { $originalText.Substring($inputHeaderIndex) } else { '' }
    $prologuePreserved = ($originalPrologue.Length -gt 0) -and $afterText.StartsWith($originalPrologue)
    $engineHeaderWritten = $afterText.Contains('; Engine configuration file.')

    $lostComments = @()
    $keptComments = @()
    foreach ($comment in $originalCommentLines) {
        if ($afterText.Contains($comment)) { $keptComments += $comment } else { $lostComments += $comment }
    }
    Check 'A22_the_section_writer_keeps_every_hand_written_comment' `
        (($lostComments.Count -eq 0) -and ($keptComments.Count -eq $originalCommentLines.Count) -and $prologuePreserved) `
        ("comments kept {0}/{1} (lost {2}); the {3} char(s) before '[input]' (the boundary computed from the specimen) are a byte-exact prefix of the result: {4}" -f $keptComments.Count, $originalCommentLines.Count, $lostComments.Count, $originalPrologue.Length, $prologuePreserved)
    Check 'A23_the_engine_header_is_not_written_because_only_the_input_section_moved' `
        ((-not $engineHeaderWritten) -and (($afterText -split "`r?`n")[0] -ceq ($originalText -split "`r?`n")[0])) `
        ("engine header written: {0}; the file still starts with the specimen's own first line '{1}' (a whole-file rewrite would put '; Engine configuration file.' there and this check would fail)" -f $engineHeaderWritten, (($afterText -split "`r?`n")[0]))

    # --- what survives ------------------------------------------------------
    $inputSection = Get-InputSection $afterText
    Check 'A24_preexisting_action_and_engine_setting_survive' (($afterText.Contains($ExistingAction + '=')) -and ($afterText.Contains('settings/gdscript/always_track_call_stacks=true')) -and ($afterText.Contains('config/name="GDScript Integration Test Suite"'))) `
        ("test_input_action={0} always_track_call_stacks={1} config/name={2}" -f $afterText.Contains($ExistingAction + '='), $afterText.Contains('settings/gdscript/always_track_call_stacks=true'), $afterText.Contains('config/name="GDScript Integration Test Suite"'))
    Check 'A25_new_action_lands_in_the_input_section' (($inputSection.Contains($NewAction + '=')) -and ($inputSection.Contains('InputEventKey'))) `
        ("[input] section now: {0}" -f ($inputSection -replace "`r?`n", ' | '))

    # --- formatting: the hand-written value block ---------------------------
    # The first version of this check assumed the engine collapses a value onto
    # one line. It does not: `VariantWriter::write_to_string(value, vstr, true)`
    # (`project_settings.cpp:1204`) writes a Dictionary as `{`, one member per
    # line and `}`, exactly the shape the specimen's author had typed by hand.
    # So the honest measurement is "the pre-existing value block survived
    # verbatim", and the exact loss is counted instead of guessed.
    $valueStart = $originalText.IndexOf($ExistingAction + '={')
    $valueEnd = $originalText.IndexOf('}', $valueStart)
    $originalValueBlock = ''
    if (($valueStart -ge 0) -and ($valueEnd -gt $valueStart)) {
        $originalValueBlock = $originalText.Substring($valueStart, $valueEnd - $valueStart + 1)
    }
    Check 'A26_the_preexisting_value_block_survives_verbatim' (($originalValueBlock.Length -gt 0) -and ($afterText.Contains($originalValueBlock))) `
        ("the specimen's 'test_input_action' block ({0} chars, multi-line) is byte-identical in the rewritten file: {1}" -f $originalValueBlock.Length, ($originalValueBlock -replace "`r?`n", ' | '))

    # What was lost, counted rather than described and PARTITIONED by the
    # derived boundary: the target section is the only place the engine may
    # re-emit text, so the derived claim is "no original non-blank line OUTSIDE
    # `[input]` is missing". TASK-069 replaced the pinned "missing == 4 comments"
    # with this, which is strictly stronger in the direction that matters (a loss
    # anywhere outside the replaced section fails it).
    $missingOutsideInputSection = @($originalPrologue -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $afterText.Contains($_) })
    $missingInsideInputSection = @($originalSectionText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $afterText.Contains($_) })
    Check 'A26b_nothing_outside_the_target_section_is_lost' ($missingOutsideInputSection.Count -eq 0) `
        ("{0} original line(s) outside '[input]' are no longer present; inside the replaced section {1} line(s) differ: {2}" -f $missingOutsideInputSection.Count, $missingInsideInputSection.Count, (($missingOutsideInputSection | ForEach-Object { "'" + $_ + "'" }) -join ' '))

    # --- is the rewrite at least idempotent? --------------------------------
    $again = Invoke-Tool -Id 'A27_add_again' -Tool 'editor_add_input_action' -Arguments @{ action = $NewAction; key = 'J' }
    $againPayload = Get-Payload $again
    $againSha = Get-Sha $ProjectFile
    Check 'A27_second_identical_call_is_byte_identical' (($againSha -eq $afterSha) -and ([string](Get-PropertyValue $againPayload 'project_entry') -ceq 'unchanged') -and ([string](Get-PropertyValue $againPayload 'action_state') -ceq 'pre_existing_unchanged')) `
        ("sha256 unchanged={0}; action_state={1} project_entry={2} persisted={3}" -f ($againSha -eq $afterSha), (Get-PropertyValue $againPayload 'action_state'), (Get-PropertyValue $againPayload 'project_entry'), (Get-PropertyValue $againPayload 'persisted'))

    # --- section 3 (O-6): the case the decision is about, on the wire --------
    # `ui_accept` is an engine built-in: the editor process' InputMap gets it from
    # `InputMap::load_default()` (`main/main.cpp:2333`), so `created` is false -
    # and yet the tool mirrors the editor's default binding into the project's
    # `[input]` for the first time. `action_state` + `project_entry` are what make
    # "nothing new" and "an existing action was mirrored" read differently.
    $builtin = Invoke-Tool -Id 'A29_add_builtin_ui_accept' -Tool 'editor_add_input_action' -Arguments @{ action = 'ui_accept' }
    $builtinPayload = Get-Payload $builtin
    Check 'A29_a_builtin_name_is_created_false_but_project_entry_created' `
        (((Get-ErrorCode $builtin) -eq 0) -and ([bool](Get-PropertyValue $builtinPayload 'created') -eq $false) -and ([string](Get-PropertyValue $builtinPayload 'action_state') -ceq 'pre_existing_unchanged') -and ([string](Get-PropertyValue $builtinPayload 'project_entry') -ceq 'created') -and ([bool](Get-PropertyValue $builtinPayload 'persisted') -eq $true)) `
        ("action=ui_accept created={0} action_state={1} project_entry={2} persisted={3} event_count={4}" -f (Get-PropertyValue $builtinPayload 'created'), (Get-PropertyValue $builtinPayload 'action_state'), (Get-PropertyValue $builtinPayload 'project_entry'), (Get-PropertyValue $builtinPayload 'persisted'), (Get-PropertyValue $builtinPayload 'event_count'))
    $builtinText = [IO.File]::ReadAllText($ProjectFile, $utf8)
    Check 'A29b_the_builtin_really_landed_in_the_file' (($builtinText.Contains('ui_accept=')) -and ([int](Get-PropertyValue $builtinPayload 'event_count') -gt 0)) `
        ("the file now has 'ui_accept=': {0}, with {1} event(s) taken from the editor's own default binding" -f $builtinText.Contains('ui_accept='), (Get-PropertyValue $builtinPayload 'event_count'))
} finally {
    Stop-Engine -Handle $editorHandle
}

Start-Sleep -Seconds 2
$afterExitText = [IO.File]::ReadAllText($ProjectFile, $utf8)
Check 'A28_action_survives_the_editor_exit' ($afterExitText.Contains($NewAction + '=')) `
    ("after the editor exited, the file still carries '{0}'; sha256 {1} -> {2} (measured, not judged: an editor-side rewrite on exit would show here)" -f $NewAction, $afterSha, (Get-Sha $ProjectFile))
$afterExitSha = Get-Sha $ProjectFile

# =============================================================================
#  Section 2, part 2: can the rewrite be avoided? A pure splice of one entry.
#
#  The engine has no partial-publish API: `ProjectSettings::save_custom()`
#  (`core/config/project_settings.cpp:1234-1341`) always ends in
#  `_save_settings_text()` (`:1162-1210`), which writes the fixed header and then
#  every stored setting; `ConfigFile::save()` is whole-file too
#  (`core/io/config_file.cpp:191-211`). So the spike below does what a C++
#  implementation would have to do by hand: take the **engine's own** value text
#  for one `input/<action>` entry (the line the engine just wrote) and splice it
#  into the original bytes, changing nothing else.
# =============================================================================
$newStart = $afterExitText.IndexOf($NewAction + '={')
$newEnd = -1
$valueBlock = ''
if ($newStart -ge 0) { $newEnd = $afterExitText.IndexOf("`n}", $newStart) }
if (($newStart -ge 0) -and ($newEnd -gt $newStart)) {
    $valueBlock = $afterExitText.Substring($newStart, $newEnd - $newStart + 2)
}
Check 'B01_the_engine_serialized_one_complete_entry' (($valueBlock.Length -gt 0) -and $valueBlock.Contains('deadzone') -and $valueBlock.Contains('keycode": 74')) `
    ("the engine's own serialization of the entry is {0} chars over {1} line(s): {2}" -f $valueBlock.Length, (@($valueBlock -split "`r?`n").Count), ($valueBlock -replace "`r?`n", ' | '))
# The insertion point must be inside the `[input]` section: in this specimen
# `[input]` is the last section, so appending at EOF is inside it.
$inputIsLast = ($originalText.IndexOf('[input]') -ge 0) -and (-not (Get-InputSection $originalText).Contains("`n["))
Check 'B01b_the_specimens_input_section_is_the_last_one' $inputIsLast `
    ("'[input]' present={0}; no section header follows it={1} (so appending at EOF lands inside [input])" -f ($originalText.IndexOf('[input]') -ge 0), (-not (Get-InputSection $originalText).Contains("`n[")))

$separator = ''
if (-not $originalText.EndsWith("`n")) { $separator = "`n" }
$surgical = $originalText + $separator + $valueBlock + "`n"
$surgicalSha = ''
if ($valueBlock.Length -gt 0) {
    $appended = $separator + $valueBlock + "`n"
    Check 'B02_the_splice_changes_nothing_but_the_added_entry' (($surgical.StartsWith($originalText)) -and ($surgical.Substring($originalText.Length) -eq $appended)) `
        ("the original {0} bytes are an exact prefix of the spliced file; the only difference is the appended entry ({1} chars; a newline had to be inserted={2})" -f $originalBytes.Length, $appended.Length, ($separator.Length -gt 0))
    $surgicalBytes = $utf8.GetBytes($surgical)
    [IO.File]::WriteAllBytes($ProjectFile, $surgicalBytes)
    $hasher = [Security.Cryptography.SHA256]::Create()
    $expectedSurgicalSha = ([BitConverter]::ToString($hasher.ComputeHash($surgicalBytes)) -replace '-', '').ToLower()
    $surgicalSha = Get-Sha $ProjectFile
    Check 'B03_the_spliced_file_is_the_one_we_meant_to_write' ($surgicalSha -eq $expectedSurgicalSha) `
        ("sha256 of the spliced project.godot = {0} (equals the hash of the bytes we built)" -f $surgicalSha)
}

$gameHandle = $null
try {
    if ($valueBlock.Length -gt 0) {
        $gameHandle = Start-Engine -Arguments @('--headless', '--path', $Proj, 'res://scenes/main.tscn', "--mcp-port=$GamePort") -LogName 'game-surgical'
        Check 'B10_game_endpoint_ready' (Wait-ForPump -Port_ $GamePort) `
            ("a game process started directly on {0} with a scene on its command line answered +20 frames" -f $GamePort)

        Start-Sleep -Seconds 3
        $hasCode = 'return InputMap.has_action("' + $NewAction + '")'
        $has = Invoke-Tool -Id 'B11_game_has_spliced_action' -Port_ $GamePort -Tool 'running_game_execute_gdscript' -Arguments @{ code = $hasCode }
        $hasPayload = Get-Payload $has
        Check 'B11_a_game_reads_the_spliced_entry' (((Get-ErrorCode $has) -eq 0) -and ([bool](Get-PropertyValue $hasPayload 'result') -eq $true)) `
            ("game process InputMap.has_action('{0}') = {1} - `load_from_project_settings()` (main.cpp:2335) rebuilt the map from the file" -f $NewAction, (Get-PropertyValue $hasPayload 'result'))

        $countCode = 'return InputMap.action_get_events("' + $NewAction + '").size()'
        $count = Invoke-Tool -Id 'B12_game_spliced_event_count' -Port_ $GamePort -Tool 'running_game_execute_gdscript' -Arguments @{ code = $countCode }
        $countPayload = Get-Payload $count
        Check 'B12_the_spliced_entry_carries_its_event' (((Get-ErrorCode $count) -eq 0) -and ([int](Get-PropertyValue $countPayload 'result') -eq 1)) `
            ("game process InputMap.action_get_events('{0}').size() = {1}" -f $NewAction, (Get-PropertyValue $countPayload 'result'))

        $oldCode = 'return InputMap.has_action("' + $ExistingAction + '")'
        $old = Invoke-Tool -Id 'B13_game_preexisting_action' -Port_ $GamePort -Tool 'running_game_execute_gdscript' -Arguments @{ code = $oldCode }
        $oldPayload = Get-Payload $old
        Check 'B13_the_preexisting_action_survives_too' (((Get-ErrorCode $old) -eq 0) -and ([bool](Get-PropertyValue $oldPayload 'result') -eq $true)) `
            ("game process InputMap.has_action('{0}') = {1}" -f $ExistingAction, (Get-PropertyValue $oldPayload 'result'))
    }
} finally {
    Stop-Engine -Handle $gameHandle
}

Start-Sleep -Seconds 2
if ($valueBlock.Length -gt 0) {
    Check 'B14_the_game_did_not_rewrite_the_file' ((Get-Sha $ProjectFile) -eq $surgicalSha) `
        ("sha256 before={0} after the game ran={1} - a game start reads the file, it does not publish it" -f $surgicalSha, (Get-Sha $ProjectFile))
    $finalText = [IO.File]::ReadAllText($ProjectFile, $utf8)
    $commentsStillThere = 0
    foreach ($comment in $originalCommentLines) { if ($finalText.Contains($comment)) { $commentsStillThere++ } }
    Check 'B15_comments_and_formatting_survive_the_splice' (($commentsStillThere -eq $originalCommentLines.Count) -and $finalText.Contains($originalValueBlock) -and ($finalText -eq $surgical)) `
        ("hand-written comments still present: {0}/{1}; the hand-formatted value block still verbatim: {2}; the file is still exactly the spliced text: {3}" -f $commentsStillThere, $originalCommentLines.Count, $finalText.Contains($originalValueBlock), ($finalText -eq $surgical))
}

# =============================================================================
#  9877 and the report
# =============================================================================
$portGuardResult = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter (Get-ListenerPid -Port_ $UserPort)
Check 'Z01_port_9877_guard' $portGuardResult.pass $portGuardResult.evidence
Check 'Z02_ports_released' (((Get-ListenerPid -Port_ $EditorPort) -eq -1) -and ((Get-ListenerPid -Port_ $GamePort) -eq -1)) `
    ("editor {0} owner={1}; game {2} owner={3}" -f $EditorPort, (Get-ListenerPid -Port_ $EditorPort), $GamePort, (Get-ListenerPid -Port_ $GamePort))

# A line-by-line "what survived" listing, for the report.
$diffLines = New-Object System.Collections.Generic.List[string]
$diffLines.Add("# project.godot rewrite diff (TASK-042 section 2)")
$diffLines.Add("")
$diffLines.Add("specimen           : " + $Specimen)
$diffLines.Add("scratch project    : " + $ProjectFile)
$diffLines.Add("sha256 before      : " + $originalSha + " (" + $originalBytes.Length + " bytes)")
$diffLines.Add("sha256 after (one added action): " + $afterSha + " (" + $afterBytes.Length + " bytes)")
$diffLines.Add("")
$diffLines.Add("## every original line, verbatim-present in the rewritten file?")
$index = 0
foreach ($line in ($originalText -split "`r?`n")) {
    $index++
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $present = $afterText.Contains($line)
    $tag = if ($present) { 'KEPT ' } else { 'LOST ' }
    $diffLines.Add(("{0} {1,3}: {2}" -f $tag, $index, $line))
}
$diffLines.Add("")
$diffLines.Add("## the rewritten file, verbatim")
$diffLines.Add($afterText)
Write-McpUtf8NoBom -Path (Join-Path $Root 'project-godot-rewrite-diff.txt') -Text (($diffLines -join "`r`n") + "`r`n")

$failed = @($script:Checks | Where-Object { -not $_.pass })
Write-Host ''
Write-Host ('TASK-042 rewrite + honesty evidence: {0} checks, {1} failed' -f $script:Checks.Count, $failed.Count)
$summary = [pscustomobject]@{
    engine          = (& $Engine --version) -join ''
    head            = (& git -C $RepoRoot rev-parse --short HEAD) -join ''
    specimen        = $Specimen
    specimen_sha256 = (Get-Sha $Specimen)
    original_sha256 = $originalSha
    rewritten_sha256 = $afterSha
    checks          = $script:Checks
    failed_count    = $failed.Count
   }
Write-McpUtf8NoBom -Path (Join-Path $Root 'mcp042-rewrite-summary.json') -Text ((ConvertTo-Json -InputObject $summary -Depth 8) + "`n")
Write-Host ("summary: {0}" -f (Join-Path $Root 'mcp042-rewrite-summary.json'))
Write-Host ("diff   : {0}" -f (Join-Path $Root 'project-godot-rewrite-diff.txt'))
if ($failed.Count -gt 0) { exit 1 }
exit 0
