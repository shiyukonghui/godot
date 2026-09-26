#!/usr/bin/env python
"""TASK-069 section 2.3: the repository's exit-code propagation check.

WHY THIS EXISTS
---------------
`mcp042_gates.ps1` (and its siblings) walked a list of steps, recorded each
step's exit code in a summary, printed the summary -- and then returned 0 no
matter what the codes said. On the current tree that is not theoretical:
`mcp042_projectrewrite_and_honesty_evidence.ps1` exits **1** with
`30 checks, 3 failed` and `mcp043_description_evidence.ps1` exits **1** with
`16 checks, 5 failed`, while the drivers `mcp042_gates.ps1` / `mcp043_gates.ps1`
both exited **0** (REPORT-068 section 5.4 measured it; TASK-069 reproduced it).
A gate that says "exit 0" while one of its named steps printed FAIL is worse than
a missing gate, because the batch report quotes the 0.

The class is the exit-code sibling of the tautology check
(`scripts/check_tautologies.py`, TASK-059 D-2): "silently asserts nothing" and
"silently reports success" have the same shape, so this file has the same shape
as that one -- a **declared set of spellings**, each with an insertion probe,
plus a pinned list so a legitimate exception is a recorded decision instead of an
argument someone has to remember to repeat.

WHAT IS CHECKED
---------------
Every `.ps1` / `.py` file under the scan roots is read as text. A file that
carries one of the declared **aggregator shapes** below must also carry at least
one of that shape's declared **guard spellings**. A shape without a guard is a
file that can print a red verdict and still exit 0.

Exit 0 when every (file, shape) is discharged or pinned; exit 1 otherwise.

WHAT IS *NOT* CHECKED (state it, do not imply otherwise)
--------------------------------------------------------
* The check is **spelling-visible** only. A guard that is real but spelled
  outside the declared set is reported as a missing guard (that is the failure
  mode this check prefers: loud, cheap to fix by declaring the spelling). A
  guard that is spelled correctly but **unreachable** (inside a branch that never
  runs, after an early `exit`, in a function nobody calls) is NOT detected --
  that needs code review, exactly like gate 6's out-of-set narrowings.
* `sys.exit(main())` is declared for python because it is how several scripts
  really propagate; this checker does **not** follow `main()` to prove its return
  value is 0/1. The failure demonstration
  (`scripts/mcp069_exit_propagation_demo.ps1`) is the other leg: it manufactures
  a red step and requires the real guard text to exit non-zero.
* `.cmd` files are not scanned: batch has no aggregation of its own here.
* A pinned entry is a recorded decision, not a proof: the pin says "this shape is
  carried by a file that cannot report a red verdict" and the reason has to say
  why.

USAGE
-----
    python scripts/check_exit_propagation.py                # scan, exit 0/1
    python scripts/check_exit_propagation.py --coverage     # print the declared set
    python scripts/check_exit_propagation.py --probes       # insertion probes

Pure ASCII on purpose. The repository's own discipline (PLAYBOOK section 4) is
that a script is an argument, not a document.
"""

import argparse
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT = os.path.dirname(HERE)

# The scanner itself is excluded by name: it necessarily contains the pattern
# sources, and a self-hit would be a false positive that trains the reader to
# ignore the output.
SCAN_ROOTS = [
    os.path.join(MODULE_ROOT, "scripts"),
    os.path.join(MODULE_ROOT, "docs", "scripts"),
]
SCAN_SUFFIXES = (".ps1", ".py")
SELF_NAMES = ("check_exit_propagation.py",)

# ---------------------------------------------------------------------------
# The declared aggregator shapes. id -> (kind, compiled regex).
# ---------------------------------------------------------------------------
PS_SHAPES = [
    # The shared check printer: `$tag = if ($Pass) { 'PASS' } else { 'FAIL' }`
    # followed by `Write-Host ("[{0}] {1}" -f $tag, $Id)`. A file that tags every
    # check has a verdict to propagate.
    ("ps_check_printer", r"-f \$tag,"),
    # A step battery's summary line: the child's exit code is interpolated into a
    # line that is written to a summary file.
    ("ps_step_exit_line", r"EXIT \{1\}"),
]
PY_SHAPES = [
    # A python file that prints a FAIL verdict token.
    ("py_fail_verdict", r"['\"](FAIL|FAILED)['\"]|:\s*FAIL\b|FAIL\s*\("),
]

# ---------------------------------------------------------------------------
# The declared guard spellings. id -> (kind, compiled regex). A guard discharges
# the shapes it is listed for in SHAPE_GUARDS below.
# ---------------------------------------------------------------------------
PS_GUARDS = [
    # The step battery reads its own summary back and refuses to exit 0.
    ("ps_guard_summary_exit_nonzero", r"EXIT \[1-9\]"),
    ("ps_guard_failed_count", r"if\s*\(\s*\$failed(\.Count)?\s*-(gt|ne)\s*0\s*\)"),
    ("ps_guard_failed_scalar", r"if\s*\(\s*\$failed\s*-gt\s+0\s*\)"),
    ("ps_guard_script_failures", r"if\s*\(\s*\$script:Failures\s*-gt\s*0\s*\)"),
    ("ps_guard_failures_scalar", r"if\s*\(\s*\$failures\s*-gt\s*0\s*\)"),
    ("ps_guard_passed_total", r"if\s*\(\s*\$passed\s*-ne\s*\$total\s*\)"),
    ("ps_guard_passed_results", r"if\s*\(\s*\$passed\s*-ne\s*\$script:Results\.Count\s*\)"),
    ("ps_guard_verdict_pass", r"if\s*\(-not\s*\$verdict\.pass\s*\)"),
    ("ps_guard_crashes", r"if\s*\(\s*\$crashes\.Count\s*-gt\s*0\s*\)"),
    ("ps_guard_different", r"if\s*\(\s*\$different\s*-ne\s*0\s*\)"),
]
PY_GUARDS = [
    ("py_guard_return01", r"return 0 if .* else 1"),
    ("py_guard_failures_return1", r"if\s+FAILURES[\s\S]{0,200}?return\s+1"),
    ("py_guard_sys_exit1", r"sys\.exit\(1\)"),
    ("py_guard_sys_exit_fatal", r"sys\.exit\((['\"])FATAL"),
    ("py_guard_sys_exit_main", r"sys\.exit\(main\(\)\)"),
    # A module-level `assert` outside a function is a hard failure path (the
    # generator scripts in docs/scripts use this spelling).
    ("py_guard_module_assert", r"(?m)^assert\s"),
]

COMPILED_PS_SHAPES = [(sid, re.compile(src)) for sid, src in PS_SHAPES]
COMPILED_PY_SHAPES = [(sid, re.compile(src)) for sid, src in PY_SHAPES]
COMPILED_PS_GUARDS = [(gid, re.compile(src)) for gid, src in PS_GUARDS]
COMPILED_PY_GUARDS = [(gid, re.compile(src)) for gid, src in PY_GUARDS]

# Which guards discharge which shape. A shape with no entry can never be
# discharged and every hit must be pinned.
SHAPE_GUARDS = {
    "ps_check_printer": [
        "ps_guard_failed_count",
        "ps_guard_failed_scalar",
        "ps_guard_script_failures",
        "ps_guard_failures_scalar",
        "ps_guard_passed_total",
        "ps_guard_passed_results",
        "ps_guard_verdict_pass",
        "ps_guard_crashes",
        "ps_guard_different",
    ],
    "ps_step_exit_line": [
        "ps_guard_summary_exit_nonzero",
        "ps_guard_failed_count",
        "ps_guard_failed_scalar",
    ],
    "py_fail_verdict": [
        "py_guard_return01",
        "py_guard_failures_return1",
        "py_guard_sys_exit1",
        "py_guard_sys_exit_fatal",
        "py_guard_sys_exit_main",
        "py_guard_module_assert",
    ],
}

# ---------------------------------------------------------------------------
# The pinned list: (relative path, shape id) -> reason. A pinned pair is a
# recorded decision that this file carries the shape but cannot report a red
# verdict and still exit 0. Both directions are checked: a pair that is NOT here
# and is flagged is a failure, and a pair that is here but no longer flagged is a
# stale pin.
# ---------------------------------------------------------------------------
PINNED = {
    (os.path.join("scripts", "mcp066b_env.ps1"), "ps_check_printer"): (
        "TASK-069 census: a DOT-SOURCED library. It defines Add-Check (the shared "
        "printer with the PASS/FAIL tag) and is loaded by scripts/mcp066b_run.ps1, "
        "which owns the verdict and does exit non-zero on a failed check. The file "
        "has no top-level check of its own, so there is nothing for it to exit on."
    ),
    (os.path.join("scripts", "mcp066b_finalize.ps1"), "ps_check_printer"): (
        "TASK-069 census: a DOT-SOURCED library, same as mcp066b_env.ps1. It defines "
        "Add-Row (the PASS/FAIL printer) for scripts/mcp066b_run.ps1's final table; "
        "the verdict is the caller's."
    ),
}


def relative(path):
    return os.path.relpath(path, MODULE_ROOT).replace("/", os.sep)


def iter_files():
    for root in SCAN_ROOTS:
        if not os.path.isdir(root):
            continue
        for dirpath, _dirnames, filenames in os.walk(root):
            for name in sorted(filenames):
                if name in SELF_NAMES:
                    continue
                if not name.endswith(SCAN_SUFFIXES):
                    continue
                yield os.path.join(dirpath, name)


def classify_text(path, text):
    """(shapes present, guards present) for one file, as sorted id lists."""
    if path.lower().endswith(".py"):
        shapes = [sid for sid, regex in COMPILED_PY_SHAPES if regex.search(text)]
        guards = [gid for gid, regex in COMPILED_PY_GUARDS if regex.search(text)]
    else:
        shapes = [sid for sid, regex in COMPILED_PS_SHAPES if regex.search(text)]
        guards = [gid for gid, regex in COMPILED_PS_GUARDS if regex.search(text)]
    return shapes, guards


def undischarged(path, text):
    """The shape ids present in `text` that no declared guard of theirs covers."""
    shapes, guards = classify_text(path, text)
    out = []
    for sid in shapes:
        needed = SHAPE_GUARDS.get(sid, [])
        if not any(gid in guards for gid in needed):
            out.append(sid)
    return out


def scan():
    found = {}
    for path in iter_files():
        text = io.open(path, encoding="utf-8", errors="replace").read()
        for sid in undischarged(path, text):
            found.setdefault(relative(path), []).append(sid)
    return found


def print_coverage():
    print("DECLARED SPELLING SET (this is the whole guarantee)")
    print("  scanned file kinds : %s" % ", ".join(SCAN_SUFFIXES))
    print("  scanned roots      : %s" % ", ".join(relative(r) for r in SCAN_ROOTS))
    print("  powershell shapes  : %d" % len(PS_SHAPES))
    for sid, src in PS_SHAPES:
        print("    %-22s %s" % (sid, src))
    print("  python shapes      : %d" % len(PY_SHAPES))
    for sid, src in PY_SHAPES:
        print("    %-22s %s" % (sid, src))
    print("  powershell guards  : %d" % len(PS_GUARDS))
    for gid, src in PS_GUARDS:
        print("    %-32s %s" % (gid, src))
    print("  python guards      : %d" % len(PY_GUARDS))
    for gid, src in PY_GUARDS:
        print("    %-32s %s" % (gid, src))
    print("")
    print("  SHAPE -> GUARDS")
    for sid in sorted(SHAPE_GUARDS):
        print("    %-22s <- %s" % (sid, ", ".join(SHAPE_GUARDS[sid])))
    print("")
    print("  OUTSIDE the set, and therefore NOT guaranteed: a guard spelled some")
    print("  other way, a guard that is spelled right but unreachable, a red verdict")
    print("  that is printed without one of the declared shapes, and the return value")
    print("  of `main()` behind `sys.exit(main())`. The set is finite on purpose: it")
    print("  is the answer to the shapes that were actually found, checked by")
    print("  insertion probe, not a proof that no other shape exists (the same")
    print("  bounded guarantee gate 6 and check_tautologies.py state).")


# Each probe is (synthetic text, expected undischarged shape id or None).
PS_PROBES = [
    ("Invoke-Step 'x' { & cmd /c exit 3 }\n"
     "$line = ('STEP {0} EXIT {1}' -f $name, $rc)\n"
     "Add-Content -Path $Summary -Value $line -Encoding ASCII\n"
     "Get-Content $Summary | ForEach-Object { Write-Host $_ }\n",
     "ps_step_exit_line"),
    ("Invoke-Step 'x' { & cmd /c exit 3 }\n"
     "$line = ('STEP {0} EXIT {1}' -f $name, $rc)\n"
     "Add-Content -Path $Summary -Value $line -Encoding ASCII\n"
     "$failed = @(Select-String -Path $Summary -Pattern 'EXIT [1-9]')\n"
     "if ($failed.Count -gt 0) { exit 1 }\n",
     None),
    ("$tag = if ($Pass) { 'PASS' } else { 'FAIL' }\n"
     "Write-Host (\"[{0}] {1}\" -f $tag, $Id)\n",
     "ps_check_printer"),
    ("$tag = if ($Pass) { 'PASS' } else { 'FAIL' }\n"
     "Write-Host (\"[{0}] {1}\" -f $tag, $Id)\n"
     "$failed = @($script:Checks | Where-Object { -not $_.pass })\n"
     "if ($failed.Count -gt 0) { exit 1 }\n",
     None),
]
PY_PROBES = [
    ("print('RESULT: FAIL: %d check(s) failed' % f)\nsys.exit(0)\n", "py_fail_verdict"),
    ("print('RESULT: FAIL: %d check(s) failed' % f)\nprint('RESULT: %d checks, %d failed' % (n, f))\n"
     "return 0 if not failed else 1\n", None),
    ("print('RESULT: FAIL: %d check(s) failed' % f)\n"
     "if failed_count:\n    sys.exit(1)\nsys.exit(0)\n", None),
]
# Near misses: a step line that is not a step battery, and a FAIL word that is
# not a verdict (a comment, a variable name).
PS_MISSES = [
    ("Write-Host 'EXIT codes are printed by the caller'\n", None),
    ("$exitCode = 0\nWrite-Host ('child exit={0}' -f $exitCode)\n", None),
]
PY_MISSES = [
    ("# the FAIL branch is documented here only\nx = 'PASS'\n", None),
]


def run_probes():
    failures = 0
    checked = 0
    for text, expected in PS_PROBES + PS_MISSES:
        got = undischarged("probe.ps1", text)
        ok = (got == ([expected] if expected else []))
        checked += 1
        if not ok:
            failures += 1
        print("PROBE %-22s %s  expected=%s got=%s" % ("ps1", "PASS" if ok else "FAIL", expected, got))
    for text, expected in PY_PROBES + PY_MISSES:
        got = undischarged("probe.py", text)
        ok = (got == ([expected] if expected else []))
        checked += 1
        if not ok:
            failures += 1
        print("PROBE %-22s %s  expected=%s got=%s" % ("py", "PASS" if ok else "FAIL", expected, got))
    print("")
    print("PROBES: %d/%d" % (checked - failures, checked))
    return failures


def main():
    parser = argparse.ArgumentParser(description="The repository's exit-code propagation check (TASK-069).")
    parser.add_argument("--coverage", action="store_true", help="print the declared spelling set and what is outside it")
    parser.add_argument("--probes", action="store_true", help="run the insertion probes for every declared shape")
    args = parser.parse_args()

    if args.coverage:
        print_coverage()
        return 0

    if args.probes:
        return 1 if run_probes() > 0 else 0

    found = scan()
    print("DECLARED SHAPES    : %d powershell + %d python" % (len(PS_SHAPES), len(PY_SHAPES)))
    print("DECLARED GUARDS    : %d powershell + %d python" % (len(PS_GUARDS), len(PY_GUARDS)))
    print("PINNED             : %d (file, shape) pair(s)" % len(PINNED))
    print("")

    failures = 0
    seen = set()
    for path in sorted(found):
        for sid in sorted(found[path]):
            seen.add((path, sid))
            if (path, sid) not in PINNED:
                failures += 1
                print("UNDISCHARGED %s %s" % (path, sid))
                print("    the file carries this shape and no declared guard for it:")
                print("    a red step or check can be reported and the process still exits 0")

    for (path, sid), reason in sorted(PINNED.items()):
        if (path, sid) not in seen:
            failures += 1
            print("STALE PIN %s %s: pinned, but the file no longer carries the shape" % (path, sid))
        else:
            print("PINNED OK %s %s :: %s" % (path, sid, reason))

    for path in sorted(found):
        reconciled = [sid for sid in sorted(found[path]) if (path, sid) in PINNED]
        # Anything not in PINNED was already printed as UNDISCHARGED above; this
        # loop only names the reconciled ones, so a pinned file is never also
        # labelled as if it were guarded.
        if reconciled:
            print("PINNED (reconciled) %s %s" % (path, ", ".join(reconciled)))

    print("")
    if failures > 0:
        print("EXIT-CODE PROPAGATION CHECK FAILED: %d problem(s)" % failures)
        return 1
    print("EXIT-CODE PROPAGATION CHECK PASS (every aggregator shape is guarded or pinned; "
          "scanned %d file kind(s) under %d root(s))" % (len(SCAN_SUFFIXES), len(SCAN_ROOTS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())