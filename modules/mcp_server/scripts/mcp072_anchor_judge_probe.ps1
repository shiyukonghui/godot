# =============================================================================
#  mcp072_anchor_judge_probe.ps1 -- TASK-072: does the ONE anchor judge decide
#  the four verdicts correctly, and is it neither vacuous nor weakened?
#
#  Part A builds a throw-away git repository under %TEMP% with a known commit
#  graph and asserts the whole decision table on it:
#
#    A1  anchor == HEAD                                -> ANCHOR_EQUAL            PASS
#    A2  ancestor, diff is docs only                    -> ..._STRUCTURAL_EQUIVALENT PASS
#    A3  ancestor, diff touches *.cpp                   -> ..._STALE_COMPILED       FAIL
#    A4  ancestor, diff touches modules/*/config.py     -> ..._STALE_COMPILED       FAIL
#    A5  ancestor, diff touches an unclassified suffix  -> ..._STALE_COMPILED       FAIL
#    A6  ancestor, diff touches only .gitignore         -> ..._STRUCTURAL_EQUIVALENT PASS
#    A7  a commit on a side branch (not in HEAD)        -> ANCHOR_NOT_ANCESTOR      FAIL
#    A8  an anchor that does not resolve at all         -> ANCHOR_NOT_ANCESTOR      FAIL
#    A9  a --version line without a hex token           -> ANCHOR_NOT_ANCESTOR      FAIL
#
#  Part B asserts the classifier itself on a literal table, including the two
#  closures that would otherwise be holes: `SCsub`/`SConstruct`/`SConscript`
#  (extension-less build inputs) and `modules/*/config.py` (a SCons build input
#  even though `.py` is on the safe whitelist).
#
#  Part C records the real verdict of the two real binaries in this worktree and
#  asserts that the reported anchor is really parsed out of `--version`. It does
#  NOT assert which verdict is "right" -- that is what the counter-example probe
#  and the gate runs are for; this part only pins that the judge is not vacuous.
#
#  Usage:
#    powershell -NoProfile -ExecutionPolicy Bypass -File mcp072_anchor_judge_probe.ps1
#  Exit 0 when every check passes, 1 otherwise.
#
#  Pure ASCII on purpose (Windows PowerShell 5.1 may read a .ps1 with the ANSI
#  code page when there is no BOM).
# =============================================================================

param(
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
}
. (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')

$script:Checks = 0
$script:Failures = 0

function Check {
    param([string]$Id, [bool]$Pass, [string]$Evidence)
    $script:Checks = $script:Checks + 1
    if (-not $Pass) { $script:Failures = $script:Failures + 1 }
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1}" -f $tag, $Id)
    Write-Host ("       {0}" -f $Evidence)
}

function Write-ProbeFile {
    param([string]$Root, [string]$Relative, [string]$Text)
    $full = Join-Path $Root $Relative
    $parent = Split-Path -Parent $full
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllBytes($full, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

# Native git with stderr swallowed and without the PS 5.1 NativeCommandError
# stop: `core.autocrlf` is forced off so the throw-away repository never emits
# the LF/CRLF warning that would otherwise become a terminating error.
function Invoke-ProbeGit {
    param([string]$Root, [string[]]$GitArgs)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = @()
    $code = 0
    try {
        $out = @(& git -C $Root -c core.autocrlf=false -c core.safecrlf=false @GitArgs 2>$null)
        $code = [int]$LASTEXITCODE
    } catch {
        $code = -1
        $out = @()
    } finally {
        $ErrorActionPreference = $old
    }
    return [pscustomobject]@{ ExitCode = $code; Lines = @($out) }
}

Write-Host '============================================================='
Write-Host ' TASK-072: the anchor judge probe (decision table + classifier)'
Write-Host '============================================================='
Write-Host ("repo under test : {0}" -f $RepoRoot)
Write-Host ''

# =============================================================================
#  Part A -- the decision table on a throw-away repository
# =============================================================================
$synth = Join-Path $env:TEMP 'mcp072\anchor-synthetic'
if (Test-Path $synth) { Remove-Item -Recurse -Force $synth }
New-Item -ItemType Directory -Force -Path $synth | Out-Null

$init = Invoke-ProbeGit -Root $synth -GitArgs @('init', '-q')
if ($init.ExitCode -ne 0) { throw 'git init failed for the synthetic repository' }

function New-SyntheticCommit {
    param([string]$Message)
    $null = Invoke-ProbeGit -Root $synth -GitArgs @('-c', 'user.name=mcp072', '-c', 'user.email=mcp072@example.invalid', 'add', '-A')
    $commit = Invoke-ProbeGit -Root $synth -GitArgs @('-c', 'user.name=mcp072', '-c', 'user.email=mcp072@example.invalid', 'commit', '--no-verify', '-q', '-m', $Message)
    if ($commit.ExitCode -ne 0) { throw ('synthetic commit failed: ' + $Message + ' :: ' + ($commit.Lines -join ' ')) }
    $rev = Invoke-ProbeGit -Root $synth -GitArgs @('rev-parse', 'HEAD')
    return (([string]$rev.Lines[0]) -join '').Trim()
}

Write-ProbeFile -Root $synth -Relative 'core/engine.cpp' -Text "int engine() { return 1; }`n"
Write-ProbeFile -Root $synth -Relative 'docs/README.md' -Text "# one`n"
Write-ProbeFile -Root $synth -Relative 'modules/mcp_server/config.py' -Text "value = 1`n"
Write-ProbeFile -Root $synth -Relative '.gitignore' -Text "bin/`n"
$h1 = New-SyntheticCommit -Message 'c1: the starting tree'

Write-ProbeFile -Root $synth -Relative 'docs/README.md' -Text "# two`n"
$h2 = New-SyntheticCommit -Message 'c2: docs only'

Write-ProbeFile -Root $synth -Relative 'core/engine.cpp' -Text "int engine() { return 2; }`n"
$h3 = New-SyntheticCommit -Message 'c3: a compile input'

Write-ProbeFile -Root $synth -Relative 'modules/mcp_server/config.py' -Text "value = 2`n"
$h4 = New-SyntheticCommit -Message 'c4: config.py, a SCons build input'

Write-ProbeFile -Root $synth -Relative 'notes/thing.xyz' -Text "unclassified`n"
$h5 = New-SyntheticCommit -Message 'c5: an unclassified suffix'

Write-ProbeFile -Root $synth -Relative '.gitignore' -Text "bin/`ndist/`n"
$h6 = New-SyntheticCommit -Message 'c6: a dotfile only'

$null = Invoke-ProbeGit -Root $synth -GitArgs @('checkout', '-q', '-b', 'side', $h1)
Write-ProbeFile -Root $synth -Relative 'docs/side.md' -Text "# side`n"
$side = New-SyntheticCommit -Message 'side: a branch HEAD does not contain'
$null = Invoke-ProbeGit -Root $synth -GitArgs @('checkout', '-q', $h6)

Write-Host ("synthetic graph : h1={0} h2={1} h3={2} h4={3} h5={4} h6={5} side={6}" -f `
    $h1.Substring(0, 8), $h2.Substring(0, 8), $h3.Substring(0, 8), $h4.Substring(0, 8), $h5.Substring(0, 8), $h6.Substring(0, 8), $side.Substring(0, 8))
Write-Host ''

function Check-Verdict {
    param(
        [string]$Id,
        [string]$Anchor,
        [string]$Head,
        [string]$ExpectVerdict,
        [bool]$ExpectOk,
        [string[]]$ExpectRed = @(),
        [string[]]$ExpectSafe = @()
    )
    $v = Get-McpEngineAnchorVerdict -RepoRoot $synth -Anchor $Anchor -HeadSha $Head
    $redPaths = @($v.RedFiles | ForEach-Object { $_.Path })
    $safePaths = @($v.SafeFiles)
    $ok = ($v.Verdict -ceq $ExpectVerdict) -and ($v.Ok -eq $ExpectOk)
    foreach ($p in $ExpectRed) { if (-not ($redPaths -contains $p)) { $ok = $false } }
    foreach ($p in $ExpectSafe) { if (-not ($safePaths -contains $p)) { $ok = $false } }
    if ($ExpectRed.Count -gt 0 -and $redPaths.Count -ne $ExpectRed.Count) { $ok = $false }
    if ($ExpectSafe.Count -gt 0 -and $ExpectVerdict -ceq 'ANCHOR_STRUCTURAL_EQUIVALENT' -and $safePaths.Count -ne $ExpectSafe.Count) { $ok = $false }
    Check -Id $Id -Pass $ok -Evidence ("expect={0} ok={1} red=[{2}] safe=[{3}] :: {4}" -f `
        $ExpectVerdict, $ExpectOk, ($redPaths -join ' '), ($safePaths -join ' '), $v.Summary)
}

Check-Verdict -Id 'A1_anchor_equals_head_is_ANCHOR_EQUAL' `
    -Anchor $h2 -Head $h2 -ExpectVerdict 'ANCHOR_EQUAL' -ExpectOk $true
Check-Verdict -Id 'A2_docs_only_diff_is_STRUCTURAL_EQUIVALENT' `
    -Anchor $h1 -Head $h2 -ExpectVerdict 'ANCHOR_STRUCTURAL_EQUIVALENT' -ExpectOk $true -ExpectSafe @('docs/README.md')
Check-Verdict -Id 'A3_cpp_in_the_diff_is_STALE_COMPILED' `
    -Anchor $h2 -Head $h3 -ExpectVerdict 'ANCHOR_STALE_COMPILED' -ExpectOk $false -ExpectRed @('core/engine.cpp')
Check-Verdict -Id 'A4_config_py_in_the_diff_is_STALE_COMPILED' `
    -Anchor $h3 -Head $h4 -ExpectVerdict 'ANCHOR_STALE_COMPILED' -ExpectOk $false -ExpectRed @('modules/mcp_server/config.py')
Check-Verdict -Id 'A5_unclassified_suffix_is_STALE_COMPILED' `
    -Anchor $h4 -Head $h5 -ExpectVerdict 'ANCHOR_STALE_COMPILED' -ExpectOk $false -ExpectRed @('notes/thing.xyz')
Check-Verdict -Id 'A6_gitignore_only_diff_is_STRUCTURAL_EQUIVALENT' `
    -Anchor $h5 -Head $h6 -ExpectVerdict 'ANCHOR_STRUCTURAL_EQUIVALENT' -ExpectOk $true -ExpectSafe @('.gitignore')
Check-Verdict -Id 'A7_side_branch_anchor_is_NOT_ANCESTOR' `
    -Anchor $side -Head $h6 -ExpectVerdict 'ANCHOR_NOT_ANCESTOR' -ExpectOk $false
Check-Verdict -Id 'A8_unresolvable_anchor_is_NOT_ANCESTOR' `
    -Anchor 'deadbeefc' -Head $h6 -ExpectVerdict 'ANCHOR_NOT_ANCESTOR' -ExpectOk $false

$unparsable = Get-McpEngineAnchorVerdict -RepoRoot $synth -VersionText '4.8.dev' -HeadSha $h6
Check -Id 'A9_version_without_hex_token_is_NOT_ANCESTOR' `
    -Pass ((($unparsable.Verdict -ceq 'ANCHOR_NOT_ANCESTOR') -and (-not $unparsable.Ok)) -and ($unparsable.Anchor -eq '')) `
    -Evidence ("verdict={0} ok={1} anchor='{2}' :: {3}" -f $unparsable.Verdict, $unparsable.Ok, $unparsable.Anchor, $unparsable.Summary)

# The full --version line of a real build, against the synthetic repository: the
# token has to be pulled out of the string and then fail as a non-ancestor.
$fromVersionText = Get-McpEngineAnchorVerdict -RepoRoot $synth -VersionText '4.8.dev.mono.custom_build.1111111' -HeadSha $h6
Check -Id 'A10_anchor_is_extracted_from_the_version_line' `
    -Pass ((($fromVersionText.Anchor -ceq '1111111') -and ($fromVersionText.Verdict -ceq 'ANCHOR_NOT_ANCESTOR'))) `
    -Evidence ("anchor='{0}' verdict={1}" -f $fromVersionText.Anchor, $fromVersionText.Verdict)

Write-Host ''

# =============================================================================
#  Part B -- the classifier on a literal table
# =============================================================================
$classTable = @(
    @{ path = 'core/engine.cpp';                    kind = 'COMPILE_INPUT' },
    @{ path = 'core/typedefs.h';                    kind = 'COMPILE_INPUT' },
    @{ path = 'scene/node.hpp';                     kind = 'COMPILE_INPUT' },
    @{ path = 'core/a.c';                           kind = 'COMPILE_INPUT' },
    @{ path = 'csharp/Thing.cs';                    kind = 'COMPILE_INPUT' },
    @{ path = 'scenes/main.tscn';                   kind = 'COMPILE_INPUT' },
    @{ path = 'res/x.tres';                         kind = 'COMPILE_INPUT' },
    @{ path = 'scripts/g.gd';                       kind = 'COMPILE_INPUT' },
    @{ path = 'project.godot';                      kind = 'COMPILE_INPUT' },
    @{ path = 'x.build';                            kind = 'COMPILE_INPUT' },
    @{ path = 'SConstruct';                         kind = 'COMPILE_INPUT' },
    @{ path = 'SConscript';                         kind = 'COMPILE_INPUT' },
    @{ path = 'modules/mcp_server/SCsub';           kind = 'COMPILE_INPUT' },
    @{ path = 'modules/mcp_server/config.py';       kind = 'COMPILE_INPUT' },
    @{ path = 'Makefile';                           kind = 'COMPILE_INPUT' },
    @{ path = 'docs/report.md';                     kind = 'SAFE' },
    @{ path = 'docs/x.json';                        kind = 'SAFE' },
    @{ path = 'docs/x.txt';                         kind = 'SAFE' },
    @{ path = 'scripts/x.ps1';                      kind = 'SAFE' },
    @{ path = 'scripts/x.py';                       kind = 'SAFE' },
    @{ path = 'scripts/x.cmd';                      kind = 'SAFE' },
    @{ path = 'scripts/x.sh';                       kind = 'SAFE' },
    @{ path = '.gitignore';                         kind = 'SAFE' },
    @{ path = '.gitattributes';                     kind = 'SAFE' },
    @{ path = 'notes/thing.xyz';                    kind = 'UNCLASSIFIED' },
    @{ path = 'a/b/cccccccc.hpp';                   kind = 'COMPILE_INPUT' }
)
$classBad = @()
foreach ($row in $classTable) {
    $got = Get-McpAnchorFileKind -RelativePath $row.path
    if ($got -cne $row.kind) { $classBad += ('{0}: expected {1} got {2}' -f $row.path, $row.kind, $got) }
}
Check -Id 'B1_classifier_matches_the_declared_table' -Pass ($classBad.Count -eq 0) `
    -Evidence ("rows={0} mismatches={1} {2}" -f $classTable.Count, $classBad.Count, ($classBad -join '; '))

Write-Host ''

# =============================================================================
#  Part C -- the real binaries (recorded, and pinned as non-vacuous)
# =============================================================================
$headShort = (([string]((Invoke-ProbeGit -Root $RepoRoot -GitArgs @('rev-parse', '--short=9', 'HEAD')).Lines[0])) -join '').Trim()
Write-Host ("real HEAD short : {0}" -f $headShort)
$realVerdicts = @()
foreach ($pair in @(
        @{ name = 'plain'; exe = (Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.console.exe') },
        @{ name = 'mono'; exe = (Join-Path $RepoRoot 'bin\godot.windows.editor.x86_64.mono.console.exe') })) {
    if (-not (Test-Path $pair.exe)) {
        Check -Id ('C_anchor_' + $pair.name + '_binary_present') -Pass $false -Evidence ('missing: ' + $pair.exe)
        continue
    }
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $pair.exe).Hash.ToLower()
    $versionText = ((& $pair.exe --version 2>$null) -join ' ').Trim()
    $v = Get-McpEngineAnchorVerdict -RepoRoot $RepoRoot -VersionText $versionText -HeadSha $headShort
    $realVerdicts += ('{0} --version=''{1}'' sha256={2} {3}' -f $pair.name, $versionText, $sha256, $v.Summary)
    $known = @('ANCHOR_EQUAL', 'ANCHOR_STRUCTURAL_EQUIVALENT', 'ANCHOR_STALE_COMPILED', 'ANCHOR_NOT_ANCESTOR')
    Check -Id ('C_anchor_' + $pair.name + '_is_a_parsed_real_verdict') `
        -Pass (($known -contains $v.Verdict) -and ($v.Anchor -ne '')) `
        -Evidence ($v.Summary)
}
Write-Host ''
Write-Host '--- the real verdicts, verbatim (recording, not a pass/fail claim) ---'
foreach ($line in $realVerdicts) { Write-Host $line }

Write-Host ''
Write-Host ("checks={0} failures={1}" -f $script:Checks, $script:Failures)
if ($script:Failures -gt 0) {
    Write-Host 'TASK-072 ANCHOR JUDGE PROBE FAILED'
    exit 1
}
Write-Host 'TASK-072 ANCHOR JUDGE PROBE PASS (the decision table, the classifier and the real anchors all agree)'
exit 0
