# =============================================================================
#  check_engine_anchor.ps1 -- TASK-072: the ONE anchor criterion of this module.
#
#  Why this file exists (decision D130, REPORT-071 section "gate 5"):
#  the module's evidence scripts used to assert "the engine's --version string
#  contains `git rev-parse --short=9 HEAD`". That is red on *every* commit that
#  moves HEAD, including commits that touch only docs and scripts -- the exact
#  false red TASK-071 hit (`FAILED STEPS: 2`, no regression at all). A gate that
#  goes red for a reason which is not a defect destroys trust in the gate, so the
#  criterion has to be mechanised instead of remembered.
#
#  The criterion (A = the anchor the binary self-reports, H = HEAD):
#
#    ANCHOR_EQUAL                  A and H resolve to the same commit.       PASS
#    ANCHOR_STRUCTURAL_EQUIVALENT  A is an ancestor of H AND
#                                  `git diff --name-only A..H` contains no
#                                  compile input. The safe diff is printed in
#                                  full, with its count.                     PASS
#    ANCHOR_STALE_COMPILED         A is an ancestor of H but the diff DOES
#                                  contain a compile input: the binary was
#                                  built before a change that can change what
#                                  it does. The offending files are printed. FAIL
#    ANCHOR_NOT_ANCESTOR           A does not resolve at all, or A is not in
#                                  H's history (branch switch, rebase, forged
#                                  anchor).                                 FAIL
#
#  Fail closed: a file is SAFE only when it matches the declared non-compiling
#  whitelist below. Every recognised compile input is RED, and everything the
#  classifier does not recognise is RED as well (`UNCLASSIFIED`). `config.py` is
#  carved out of the `.py` whitelist on purpose: `modules/*/config.py` is a SCons
#  build input, so whitelisting it would be a hole in the closure.
#
#  ANCHOR_STRUCTURAL_EQUIVALENT is NOT "equal to HEAD" and must never be written
#  down as such. Every verdict carries the binary's self-reported anchor, HEAD,
#  the criterion and the whole diff, so a later reader can judge for themselves
#  (TASK-072 section 2). The word "equivalent" only ever means "the diff between
#  the two commits cannot change the compiled behaviour".
#
#  Usage as a library (this is what the evidence scripts do):
#
#    . (Join-Path $PSScriptRoot 'check_engine_anchor.ps1')
#    $v = Get-McpEngineAnchorVerdict -VersionText $versionText -HeadSha $head9
#    if (-not $v.Ok) { ... }             # $v.Summary is the evidence line
#
#  Usage as a command (this is what the counter-example probes do):
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File check_engine_anchor.ps1 `
#        -VersionText '4.8.dev.custom_build.3cbaacd6b'
#    powershell ... -Anchor deadbeefc -RepoRoot <scratch repo> [-Json]
#
#  exit 0 = PASS (EQUAL / STRUCTURAL_EQUIVALENT), 1 = FAIL (STALE_COMPILED /
#  NOT_ANCESTOR), 3 = usage error.
#
#  Pure ASCII on purpose (Windows PowerShell 5.1 may read a .ps1 with the ANSI
#  code page when there is no BOM).
# =============================================================================

# -----------------------------------------------------------------------------
#  NO `param(...)` BLOCK ON PURPOSE, and no assignments outside functions before
#  the dot-source guard below.
#
#  This file is dot-sourced as a library by the evidence scripts. A parameter
#  block in a dot-sourced script binds its parameters *into the caller's scope*,
#  so dot-sourcing it with no arguments would assign '' to the caller's own
#  $RepoRoot / $VersionText / $Anchor / $HeadSha and silently break the caller
#  (measured: mcp052's $RepoRoot was wiped by the first version of this file).
#  The command line is therefore parsed from $args in command mode, and nothing
#  in this file touches the caller's variables.
# -----------------------------------------------------------------------------

# --- the declared classification (TASK-072 section 2.1) ----------------------
# A file is RED when it is a compile input. The list is the task's explicit one
# plus the neighbouring shapes that are obviously compiled as well; unlisted
# extensions are NOT safe (they fall into UNCLASSIFIED, which is red).
$script:MCP072CompileExtensions = @(
    '.cpp', '.cxx', '.cc', '.c', '.h', '.hpp', '.hh', '.hxx', '.inl', '.inc',
    '.cs', '.tscn', '.tres', '.gd', '.godot', '.build', '.csproj', '.sln',
    '.vcxproj', '.asm', '.s', '.m', '.mm', '.rc', '.def', '.java', '.kt',
    '.swift', '.rs', '.go'
)
# Extension-less build inputs. `config.py` is here on purpose (see the header).
$script:MCP072CompileNames = @(
    'sconstruct', 'sconscript', 'scsub', 'config.py', 'makefile', 'gnumakefile'
)
# The declared non-compiling whitelist. Only these are SAFE.
$script:MCP072SafeExtensions = @(
    '.md', '.json', '.txt', '.ps1', '.py', '.cmd', '.sh', '.bat', '.psm1',
    '.psd1', '.yml', '.yaml', '.toml', '.cfg', '.ini', '.csv', '.rst', '.adoc',
    '.html', '.css', '.svg', '.png', '.jpg', '.jpeg', '.webp', '.gif', '.log'
)
$script:MCP072SafeNames = @(
    '.gitignore', '.gitattributes', '.gitmodules', '.editorconfig',
    'license', 'copying', 'authors', 'notice'
)

$script:MCP072Criterion = 'A is an ancestor of H (A == H counts) and git diff --name-only A..H contains no compile input (safe = declared non-compiling whitelist, everything else red)'

# =============================================================================
#  Library: the judge
# =============================================================================

function Get-McpAnchorJudgeRepoRoot {
    param([string]$RepoRoot = '')
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        return (Resolve-Path -LiteralPath $RepoRoot).Path
    }
    # $PSScriptRoot is the directory of *this* file even when it is dot-sourced,
    # so the default works from any caller context.
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
}

# Pull the trailing hex token out of a `--version` line, e.g.
#   '4.8.dev.mono.custom_build.3cbaacd6b' -> '3cbaacd6b'
# Returns '' when there is no such token (the caller then fails closed).
function Get-McpAnchorFromVersionText {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $t = ([string]$Text).Trim()
    if ($t -match '([0-9a-fA-F]{7,40})\s*$') { return $Matches[1].ToLowerInvariant() }
    return ''
}

# SAFE / COMPILE_INPUT / UNCLASSIFIED. Unclassified is red at the call site.
function Get-McpAnchorFileKind {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $name = ([IO.Path]::GetFileName($RelativePath)).ToLowerInvariant()
    if ($script:MCP072CompileNames -contains $name) { return 'COMPILE_INPUT' }
    if ($script:MCP072SafeNames -contains $name) { return 'SAFE' }
    $ext = ([IO.Path]::GetExtension($name)).ToLowerInvariant()
    if ($script:MCP072CompileExtensions -contains $ext) { return 'COMPILE_INPUT' }
    if ($script:MCP072SafeExtensions -contains $ext) { return 'SAFE' }
    return 'UNCLASSIFIED'
}

function Invoke-McpAnchorGit {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string[]]$GitArgs
    )
    # $ErrorActionPreference is lowered locally: with 'Stop' a native command that
    # writes anything to stderr turns into a terminating NativeCommandError in
    # Windows PowerShell 5.1, and an anchor check must not die on a git warning.
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = @()
    $code = 0
    try {
        $out = @(& git -C $RepoRoot @GitArgs 2>$null)
        $code = [int]$LASTEXITCODE
    } catch {
        $code = -1
        $out = @()
    } finally {
        $ErrorActionPreference = $old
    }
    return [pscustomobject]@{ ExitCode = $code; Lines = @($out) }
}

# `git merge-base --is-ancestor A B` -> 0 when A is an ancestor of B (A == B
# included), 1 when it is not. Returns the raw exit code; -1 means the call
# itself could not be made.
function Invoke-McpAnchorGitMergeBase {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Ancestor,
        [Parameter(Mandatory = $true)][string]$Descendant
    )
    $call = Invoke-McpAnchorGit -RepoRoot $RepoRoot -GitArgs @('merge-base', '--is-ancestor', $Ancestor, $Descendant)
    return [int]$call.ExitCode
}

function Format-McpAnchorSummary {
    param([Parameter(Mandatory = $true)]$Verdict)
    $anchorShown = $Verdict.Anchor
    if ([string]::IsNullOrWhiteSpace($anchorShown)) { $anchorShown = '<none>' }
    $diffParts = @()
    foreach ($f in @($Verdict.SafeFiles)) { $diffParts += ('S:' + $f) }
    foreach ($f in @($Verdict.RedFiles)) { $diffParts += ('R:' + $f.Path + '(' + $f.Kind + ')') }
    $diffText = if ($diffParts.Count -gt 0) { $diffParts -join ' ' } else { '<empty>' }
    $parts = @(
        ('anchor={0}' -f $anchorShown),
        ('anchor_reported={0}' -f $(if ([string]::IsNullOrWhiteSpace($Verdict.AnchorReported)) { '<none>' } else { $Verdict.AnchorReported })),
        ('head={0}' -f $(if ([string]::IsNullOrWhiteSpace($Verdict.Head)) { '<unresolved>' } else { $Verdict.Head })),
        ('verdict={0}' -f $Verdict.Verdict),
        ('ancestor={0}' -f $(if ($Verdict.Ancestor) { 'yes' } else { 'no' })),
        ('diff_count={0}' -f $Verdict.DiffCount),
        ('safe_count={0}' -f $Verdict.SafeCount),
        ('red_count={0}' -f $Verdict.RedCount),
        ('criterion="{0}"' -f $Verdict.Criterion),
        ('reason="{0}"' -f $Verdict.Reason),
        ('diff=[{0}]' -f $diffText)
    )
    return ($parts -join ' ')
}

function Get-McpEngineAnchorVerdict {
    <#
      The single anchor criterion of this module. Returns an object with:
        Ok              bool   - the gate answer (PASS/FAIL)
        Verdict         string - ANCHOR_EQUAL / ANCHOR_STRUCTURAL_EQUIVALENT /
                                 ANCHOR_STALE_COMPILED / ANCHOR_NOT_ANCESTOR
        Anchor          string - the resolved anchor prefix the binary reported
        AnchorReported  string - the raw token extracted from --version
        Head            string - the resolved HEAD (short)
        Ancestor        bool
        Criterion       string
        DiffCount       int    - files in `git diff --name-only A..H`
        SafeFiles       [string[]]
        RedFiles        [object[]] - @{ Path; Kind }
        UnclassifiedFiles [string[]]
        Reason          string
        Summary         string - one line carrying anchor + HEAD + criterion + diff
    #>
    param(
        [string]$VersionText = '',
        [string]$Anchor = '',
        [string]$HeadSha = '',
        [string]$RepoRoot = ''
    )

    $result = New-Object psobject -Property ([ordered]@{
        Ok                = $false
        Verdict           = 'ANCHOR_NOT_ANCESTOR'
        Anchor            = ''
        AnchorReported    = ''
        Head              = ''
        Ancestor          = $false
        Criterion         = $script:MCP072Criterion
        DiffCount         = 0
        SafeCount         = 0
        RedCount          = 0
        SafeFiles         = @()
        RedFiles          = @()
        UnclassifiedFiles = @()
        Reason            = ''
        RepoRoot          = ''
        Summary           = ''
    })

    try {
        $result.RepoRoot = Get-McpAnchorJudgeRepoRoot -RepoRoot $RepoRoot
    } catch {
        $result.Reason = ('repository root not resolvable: {0}' -f $_.Exception.Message)
        $result.Summary = Format-McpAnchorSummary -Verdict $result
        return $result
    }

    # --- 1. resolve HEAD (recorded in every verdict, present or not) ---------
    if (-not [string]::IsNullOrWhiteSpace($HeadSha)) {
        $result.Head = ([string]$HeadSha).Trim().ToLowerInvariant()
    } else {
        $headRev = Invoke-McpAnchorGit -RepoRoot $result.RepoRoot -GitArgs @('rev-parse', '--short=9', 'HEAD')
        if (($headRev.ExitCode -ne 0) -or ($headRev.Lines.Count -eq 0)) {
            $result.Reason = 'git rev-parse --short=9 HEAD failed'
            $result.Summary = Format-McpAnchorSummary -Verdict $result
            return $result
        }
        $result.Head = ([string]$headRev.Lines[0]).Trim().ToLowerInvariant()
    }

    # --- 2. the anchor the binary reported ----------------------------------
    $anchorText = $Anchor
    if ([string]::IsNullOrWhiteSpace($anchorText)) {
        $anchorText = Get-McpAnchorFromVersionText -Text $VersionText
    }
    $result.AnchorReported = ([string]$anchorText).Trim()
    if ([string]::IsNullOrWhiteSpace($anchorText)) {
        $result.Reason = ('the reported version carries no hex anchor token: "{0}"' -f (([string]$VersionText).Trim()))
        $result.Summary = Format-McpAnchorSummary -Verdict $result
        return $result
    }
    $result.Anchor = ([string]$anchorText).Trim().ToLowerInvariant()

    # --- 3. resolve both to commits (fail closed when A does not resolve) ----
    $anchorRev = Invoke-McpAnchorGit -RepoRoot $result.RepoRoot -GitArgs @('rev-parse', '--verify', '--quiet', ($result.Anchor + '^{commit}'))
    $headRev2 = Invoke-McpAnchorGit -RepoRoot $result.RepoRoot -GitArgs @('rev-parse', '--verify', '--quiet', ($result.Head + '^{commit}'))
    if (($anchorRev.ExitCode -ne 0) -or ($anchorRev.Lines.Count -eq 0)) {
        $result.Reason = ('the reported anchor ''{0}'' does not resolve to a commit in this repository' -f $result.Anchor)
        $result.Summary = Format-McpAnchorSummary -Verdict $result
        return $result
    }
    if (($headRev2.ExitCode -ne 0) -or ($headRev2.Lines.Count -eq 0)) {
        $result.Reason = ('HEAD ''{0}'' does not resolve to a commit in this repository' -f $result.Head)
        $result.Summary = Format-McpAnchorSummary -Verdict $result
        return $result
    }
    $anchorFull = ([string]$anchorRev.Lines[0]).Trim().ToLowerInvariant()
    $headFull = ([string]$headRev2.Lines[0]).Trim().ToLowerInvariant()

    # --- 4. the three-way decision ------------------------------------------
    if ($anchorFull -ceq $headFull) {
        $result.Verdict = 'ANCHOR_EQUAL'
        $result.Ok = $true
        $result.Ancestor = $true
        $result.Reason = 'the binary self-reports the very commit HEAD points at; the diff is empty by construction'
        $result.Summary = Format-McpAnchorSummary -Verdict $result
        return $result
    }

    $mergeBase = Invoke-McpAnchorGitMergeBase -RepoRoot $result.RepoRoot -Ancestor $anchorFull -Descendant $headFull
    $isAncestor = ($mergeBase -eq 0)
    $result.Ancestor = $isAncestor
    if (-not $isAncestor) {
        $result.Verdict = 'ANCHOR_NOT_ANCESTOR'
        $result.Ok = $false
        $result.Reason = ('{0} is not an ancestor of {1}: the binary is anchored on a history HEAD does not contain' -f $result.Anchor, $result.Head)
        $result.Summary = Format-McpAnchorSummary -Verdict $result
        return $result
    }

    $diff = Invoke-McpAnchorGit -RepoRoot $result.RepoRoot -GitArgs @('diff', '--name-only', '--no-renames', ($anchorFull + '..' + $headFull))
    if ($diff.ExitCode -ne 0) {
        $result.Verdict = 'ANCHOR_STALE_COMPILED'
        $result.Ok = $false
        $result.Reason = ('git diff --name-only {0}..{1} failed (exit {2}); the closure cannot be proven' -f $result.Anchor, $result.Head, $diff.ExitCode)
        $result.Summary = Format-McpAnchorSummary -Verdict $result
        return $result
    }

    $safe = New-Object System.Collections.Generic.List[string]
    $red = New-Object System.Collections.Generic.List[object]
    $unclassified = New-Object System.Collections.Generic.List[string]
    foreach ($raw in @($diff.Lines)) {
        $path = ([string]$raw).Trim().Trim('"')
        if ($path.Length -eq 0) { continue }
        $kind = Get-McpAnchorFileKind -RelativePath $path
        if ($kind -eq 'SAFE') {
            $safe.Add($path) | Out-Null
        } else {
            $red.Add((New-Object psobject -Property ([ordered]@{ Path = $path; Kind = $kind }))) | Out-Null
            if ($kind -eq 'UNCLASSIFIED') { $unclassified.Add($path) | Out-Null }
        }
    }
    $result.SafeFiles = @($safe.ToArray())
    $result.RedFiles = @($red.ToArray())
    $result.UnclassifiedFiles = @($unclassified.ToArray())
    $result.DiffCount = $result.SafeFiles.Count + $result.RedFiles.Count
    $result.SafeCount = $result.SafeFiles.Count
    $result.RedCount = $result.RedFiles.Count

    if ($result.RedCount -gt 0) {
        $result.Verdict = 'ANCHOR_STALE_COMPILED'
        $result.Ok = $false
        $result.Reason = ('{0} is an ancestor of {1} but the diff contains {2} file(s) that can change the compiled binary: {3}' -f `
            $result.Anchor, $result.Head, $result.RedCount, (($result.RedFiles | ForEach-Object { $_.Kind + ':' + $_.Path }) -join ', '))
    } else {
        $result.Verdict = 'ANCHOR_STRUCTURAL_EQUIVALENT'
        $result.Ok = $true
        $result.Reason = ('{0} is an ancestor of {1} and all {2} file(s) in the diff are non-compiling; the binary is NOT equal to HEAD, it is structurally equivalent to it' -f `
            $result.Anchor, $result.Head, $result.DiffCount)
    }
    $result.Summary = Format-McpAnchorSummary -Verdict $result
    return $result
}

# =============================================================================
#  Library mode: when this file is dot-sourced only the definitions above are
#  made and nothing else runs (see the note at the top of the file).
# =============================================================================
if ($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference = 'Stop'

# =============================================================================
#  Command mode: parse $args (there is no param block on purpose)
# =============================================================================
$cliRepoRoot = ''
$cliVersionText = ''
$cliAnchor = ''
$cliHeadSha = ''
$cliJson = $false
$cliBad = @()
$i = 0
while ($i -lt $args.Count) {
    $a = [string]$args[$i]
    switch ($a) {
        '-RepoRoot'    { $i++; $cliRepoRoot = [string]$args[$i] }
        '-VersionText' { $i++; $cliVersionText = [string]$args[$i] }
        '-Anchor'      { $i++; $cliAnchor = [string]$args[$i] }
        '-HeadSha'     { $i++; $cliHeadSha = [string]$args[$i] }
        '-Json'        { $cliJson = $true }
        default        { $cliBad += $a }
    }
    $i++
}
if ($cliBad.Count -gt 0) {
    Write-Host ('check_engine_anchor: unknown argument(s): {0}' -f ($cliBad -join ' '))
    exit 3
}
if ([string]::IsNullOrWhiteSpace($cliAnchor) -and [string]::IsNullOrWhiteSpace($cliVersionText)) {
    Write-Host 'check_engine_anchor: nothing to judge.'
    Write-Host '  usage: check_engine_anchor.ps1 -VersionText <engine --version output> [-RepoRoot <path>] [-HeadSha <sha>]'
    Write-Host '         check_engine_anchor.ps1 -Anchor <sha-or-prefix>       [-RepoRoot <path>] [-HeadSha <sha>] [-Json]'
    exit 3
}

$verdict = Get-McpEngineAnchorVerdict -VersionText $cliVersionText -Anchor $cliAnchor -HeadSha $cliHeadSha -RepoRoot $cliRepoRoot

if ($cliJson) {
    $payload = [ordered]@{
        verdict           = $verdict.Verdict
        ok                = $verdict.Ok
        anchor            = $verdict.Anchor
        anchor_reported   = $verdict.AnchorReported
        head              = $verdict.Head
        ancestor          = $verdict.Ancestor
        criterion         = $verdict.Criterion
        diff_count        = $verdict.DiffCount
        safe_count        = $verdict.SafeCount
        red_count         = $verdict.RedCount
        safe_files        = @($verdict.SafeFiles)
        red_files         = @($verdict.RedFiles | ForEach-Object { [ordered]@{ path = $_.Path; kind = $_.Kind } })
        unclassified_files = @($verdict.UnclassifiedFiles)
        reason            = $verdict.Reason
        repo_root         = $verdict.RepoRoot
    }
    Write-Output (ConvertTo-Json -InputObject $payload -Depth 8 -Compress)
} else {
    Write-Host ('ANCHOR_JUDGE VERDICT={0}' -f $verdict.Verdict)
    Write-Host ('ANCHOR_JUDGE ANCHOR={0} ANCHOR_REPORTED={1} HEAD={2}' -f $verdict.Anchor, $verdict.AnchorReported, $(if ([string]::IsNullOrWhiteSpace($verdict.Head)) { '<unresolved>' } else { $verdict.Head }))
    Write-Host ('ANCHOR_JUDGE ANCESTOR={0}' -f $(if ($verdict.Ancestor) { 'yes' } else { 'no' }))
    Write-Host ('ANCHOR_JUDGE CRITERION={0}' -f $verdict.Criterion)
    Write-Host ('ANCHOR_JUDGE DIFF_COUNT={0} SAFE_COUNT={1} RED_COUNT={2}' -f $verdict.DiffCount, $verdict.SafeCount, $verdict.RedCount)
    foreach ($f in @($verdict.SafeFiles)) { Write-Host ('ANCHOR_JUDGE SAFE {0}' -f $f) }
    foreach ($f in @($verdict.RedFiles)) { Write-Host ('ANCHOR_JUDGE RED {0} {1}' -f $f.Kind, $f.Path) }
    Write-Host ('ANCHOR_JUDGE REASON={0}' -f $verdict.Reason)
    Write-Host ('ANCHOR_JUDGE SUMMARY {0}' -f $verdict.Summary)
    Write-Host ('ANCHOR_JUDGE RESULT {0}' -f $(if ($verdict.Ok) { 'PASS' } else { 'FAIL' }))
}

if ($verdict.Ok) { exit 0 }
exit 1