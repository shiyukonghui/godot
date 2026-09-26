#!/usr/bin/env python
"""D-2 (TASK-059): the repository's tautology check.

WHY THIS EXISTS
---------------
`mcp057_settings_publish_evidence.ps1` carried, at its final check, a predicate
of the shape "<a real condition> disjoined with the constant `$true`". A
disjunction against a constant true is a constant true, so `Check` (which
increments its failure counter only when the predicate is false) could never
fail there: the check announced that it verified there was no leftover scratch
engine process and verified nothing at all. That is worse than a missing check,
because the summary line still reads PASS.

It was found by reading, not by any machine check. The same class had already
appeared four times as "silently writes the wrong value" and was answered with a
machine check (gate 6, GDR-24); this file is the same answer for "silently
asserts nothing". The guarantee is deliberately the SAME SHAPE and the SAME
BOUNDED SIZE as gate 6: a **declared set of spellings**, each with an insertion
probe, plus a pinned-list so a legitimate quoted mention can be recorded instead
of re-argued.

WHAT IS CHECKED
---------------
Every file under the scan roots (below) is read as text and matched against the
declared pattern list. A hit is any occurrence of a constant-only boolean
expression: a PowerShell `-or`/`-and` against a literal `$true`/`$false`, a
literal-only `if ($false)` / `if ($true)`, a literal-only equality such as
`$true -eq $true`, and the Python spellings `or True`, `and False`, `if True:`,
`if False:` and `assert True`.

Exit 0 when every hit is accounted for; exit 1 otherwise.

WHAT IS *NOT* CHECKED (state it, do not imply otherwise)
--------------------------------------------------------
* The check is **spelling-visible** only. A tautology the scanner cannot see -
  `$x = $true; if ($x)`, a property that is always true, a predicate built by
  string concatenation, a lambda that ignores its argument - is outside it.
  Those need code review, exactly like gate 6's out-of-set narrowings.
* `.cmd` files are not scanned: batch has no boolean expression of this shape,
  and `if /i "%~1"=="-Force"` is a comparison against an argument, not a
  constant.
* A pinned hit is a recorded decision, not a proof: the pin says "this spelling
  is quoted on purpose here", and the reason has to say why.
* This is one leg. The other two are the failure demonstration
  (`mcp059_d2_failure_demo.ps1`, which manufactures the condition the check
  claims to detect and requires the evidence script to exit non-zero) and plain
  reading.

USAGE
-----
    python scripts/check_tautologies.py                  # scan, exit 0/1
    python scripts/check_tautologies.py --coverage       # print the declared set
    python scripts/check_tautologies.py --probes         # insertion probes

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

# Roots scanned, relative to the module root. The scanner itself is excluded by
# name: it necessarily contains the pattern sources, and a self-hit would be a
# false positive that trains the reader to ignore the output.
SCAN_ROOTS = [
    os.path.join(MODULE_ROOT, "scripts"),
    os.path.join(MODULE_ROOT, "docs", "scripts"),
]
SCAN_SUFFIXES = (".ps1", ".py")
SELF_NAMES = ("check_tautologies.py",)

# ---------------------------------------------------------------------------
# The declared spelling set. Every entry is (id, compiled regex). Each spelling
# is matched case-insensitively and without regard to the surrounding
# whitespace. `--probes` inserts each of these into a synthetic sample and
# requires a hit, so "declared" cannot silently mean "not implemented".
# ---------------------------------------------------------------------------
POWERSHELL_PATTERNS = [
    ("ps_or_true", r"-\s*or\s+\$true\b"),
    ("ps_or_true_quoted", r"-\s*or\s+['\"]true['\"]"),
    ("ps_and_false", r"-\s*and\s+\$false\b"),
    ("ps_and_false_quoted", r"-\s*and\s+['\"]false['\"]"),
    ("ps_if_false", r"\bif\s*\(\s*\$false\s*\)"),
    ("ps_if_true", r"\bif\s*\(\s*\$true\s*\)"),
    ("ps_true_eq_true", r"\$true\s*-eq\s*\$true\b"),
    ("ps_false_eq_false", r"\$false\s*-eq\s*\$false\b"),
    ("ps_true_ne_false", r"\$true\s*-ne\s*\$false\b"),
]
PYTHON_PATTERNS = [
    ("py_or_true", r"\bor\s+True\b"),
    ("py_and_false", r"\band\s+False\b"),
    ("py_if_true", r"^[ \t]*if\s+True\s*:"),
    ("py_if_false", r"^[ \t]*if\s+False\s*:"),
    ("py_assert_true", r"\bassert\s+True\b"),
]

COMPILED = {
    "ps1": [(pid, re.compile(src, re.IGNORECASE)) for pid, src in POWERSHELL_PATTERNS],
    "py": [(pid, re.compile(src, re.IGNORECASE)) for pid, src in PYTHON_PATTERNS],
}

# ---------------------------------------------------------------------------
# The pinned list: (relative path, pattern id) -> (expected hit count, reason).
# A pinned spelling is a recorded decision. A path/pattern pair that is NOT here
# and has hits is a failure; so is a pair whose count no longer matches, in both
# directions (a disappeared quotation is a stale pin).
# ---------------------------------------------------------------------------
PINNED = {
    (
        os.path.join("scripts", "mcp057_settings_publish_evidence.ps1"),
        "ps_or_true",
    ): (
        1,
        "TASK-059 D-2: the two comment lines that record the defect quote the old "
        "predicate verbatim, so the fix stays auditable in the file a reader opens. "
        "The executable predicate on the check itself is a real assertion (process "
        "sweep AND both test ports free) and the failure demonstration "
        "(mcp059_d2_failure_demo.ps1) forces it to exit non-zero.",
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


def scan_text(path, text):
    """Every declared-spelling hit in `text`, as (pattern id, line number, line)."""
    kind = "py" if path.lower().endswith(".py") else "ps1"
    hits = []
    lines = text.split("\n")
    for number, line in enumerate(lines, start=1):
        for pid, regex in COMPILED[kind]:
            if regex.search(line):
                hits.append((pid, number, line.strip()))
    return hits


def scan():
    """All hits, as {relative path: {pattern id: [(line no, line)]}}."""
    found = {}
    for path in iter_files():
        text = io.open(path, encoding="utf-8", errors="replace").read()
        hits = scan_text(path, text)
        if not hits:
            continue
        per_file = found.setdefault(relative(path), {})
        for pid, number, line in hits:
            per_file.setdefault(pid, []).append((number, line))
    return found


def print_coverage():
    print("DECLARED SPELLING SET (this is the whole guarantee)")
    print("  scanned file kinds : %s" % ", ".join(SCAN_SUFFIXES))
    print("  scanned roots      : %s" % ", ".join(relative(r) for r in SCAN_ROOTS))
    print("  powershell patterns: %d" % len(POWERSHELL_PATTERNS))
    for pid, src in POWERSHELL_PATTERNS:
        print("    %-22s %s" % (pid, src))
    print("  python patterns    : %d" % len(PYTHON_PATTERNS))
    for pid, src in PYTHON_PATTERNS:
        print("    %-22s %s" % (pid, src))
    print("")
    print("  OUTSIDE the set, and therefore NOT guaranteed: a tautology whose")
    print("  truth is not spelled as a constant in the expression (a variable")
    print("  assigned $true, an always-true property, a predicate assembled from")
    print("  strings), every .cmd file, and every file outside the roots above.")
    print("  The set is finite on purpose: it is the answer to the shapes that")
    print("  were actually found, checked by insertion probe, not a proof that no")
    print("  other shape exists (the same bounded guarantee gate 6 states).")


# Each probe is (spelling as it would be written, expected pattern id).
PROBES = [
    ("Check 'x' ($a.Count -eq 0 -or $true) ('e')", "ps_or_true"),
    ("Check 'x' ($a -or 'true') ('e')", "ps_or_true_quoted"),
    ("Check 'x' ($a -and $false) ('e')", "ps_and_false"),
    ("Check 'x' ($a -and \"false\") ('e')", "ps_and_false_quoted"),
    ("if ($false) { exit 1 }", "ps_if_false"),
    ("if ($true) { exit 1 }", "ps_if_true"),
    ("Check 'x' ($true -eq $true) ('e')", "ps_true_eq_true"),
    ("Check 'x' ($false -eq $false) ('e')", "ps_false_eq_false"),
    ("Check 'x' ($true -ne $false) ('e')", "ps_true_ne_false"),
]
PY_PROBES = [
    ("if a or True:\n", "py_or_true"),
    ("if a and False:\n", "py_and_false"),
    ("if True:\n", "py_if_true"),
    ("if False:\n", "py_if_false"),
    ("assert True\n", "py_assert_true"),
]
# A near miss for every probe: the same operator against a real variable. The
# scanner must NOT match these, or the set would be noise.
MISSES = [
    "Check 'x' ($a.Count -eq 0 -or $aDrained) ('e')",
    "Check 'x' ($gameProbe.is_editor -eq $false) ('e')",
    "if ($item) { exit 1 }",
    "Check 'x' (($swept.Count -eq 0) -and ($portsBusy.Count -eq 0)) ('e')",
]


def run_probes():
    failures = 0
    for spelling, expected in PROBES:
        hits = [pid for pid, _n, _l in scan_text("probe.ps1", spelling)]
        ok = expected in hits
        if not ok:
            failures += 1
        print("PROBE %-22s %s  (%s)" % (expected, "PASS" if ok else "FAIL", spelling.strip()))
    for spelling, expected in PY_PROBES:
        hits = [pid for pid, _n, _l in scan_text("probe.py", spelling)]
        ok = expected in hits
        if not ok:
            failures += 1
        print("PROBE %-22s %s  (%s)" % (expected, "PASS" if ok else "FAIL", spelling.strip()))
    for miss in MISSES:
        hits = scan_text("probe.ps1", miss)
        ok = len(hits) == 0
        if not ok:
            failures += 1
        print("MISS  %-22s %s  (%s)" % ("(not a tautology)", "PASS" if ok else "FAIL", miss.strip()))
    total = len(PROBES) + len(PY_PROBES) + len(MISSES)
    print("")
    print("PROBES: %d/%d (%d declared spelling(s) + %d near miss(es))"
          % (total - failures, total, len(PROBES) + len(PY_PROBES), len(MISSES)))
    return failures


def main():
    parser = argparse.ArgumentParser(description="The repository's tautology check (TASK-059 D-2).")
    parser.add_argument("--coverage", action="store_true", help="print the declared spelling set and what is outside it")
    parser.add_argument("--probes", action="store_true", help="run the insertion probes for every declared spelling")
    args = parser.parse_args()

    if args.coverage:
        print_coverage()
        return 0

    if args.probes:
        return 1 if run_probes() > 0 else 0

    found = scan()
    print("DECLARED SPELLINGS : %d powershell + %d python"
          % (len(POWERSHELL_PATTERNS), len(PYTHON_PATTERNS)))
    print("PINNED             : %d (file, pattern) pair(s)" % len(PINNED))
    print("")

    failures = 0
    seen = set()
    for path in sorted(found):
        for pid in sorted(found[path]):
            entries = found[path][pid]
            seen.add((path, pid))
            pinned = PINNED.get((path, pid))
            if pinned is None:
                failures += 1
                print("UNPINNED %s %s (%d hit(s))" % (path, pid, len(entries)))
                for number, line in entries:
                    print("    line %d: %s" % (number, line))
            elif pinned[0] != len(entries):
                failures += 1
                print("PIN COUNT %s %s: pinned %d, found %d" % (path, pid, pinned[0], len(entries)))

    for (path, pid), (count, _reason) in sorted(PINNED.items()):
        if (path, pid) not in seen:
            failures += 1
            print("STALE PIN %s %s: pinned %d hit(s), found none" % (path, pid, count))

    for (path, pid), (count, reason) in sorted(PINNED.items()):
        if (path, pid) in seen and PINNED[(path, pid)][0] == len(found[path][pid]):
            print("PINNED OK %s %s (%d) :: %s" % (path, pid, count, reason))
            print("          at line %d: %s" % (found[path][pid][0][0], found[path][pid][0][1]))

    print("")
    if failures > 0:
        print("TAUTOLOGY CHECK FAILED: %d problem(s)" % failures)
        return 1
    print("TAUTOLOGY CHECK PASS (every hit is pinned; scanned=%d file kind(s) under %d root(s))"
          % (len(SCAN_SUFFIXES), len(SCAN_ROOTS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())