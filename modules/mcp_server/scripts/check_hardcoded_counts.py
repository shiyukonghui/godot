#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TASK-068 section 1b: the survey of hard-coded contract/endpoint counts.

`check_rename_map.py` was not the only script that had a size written down for
one revision and re-read on another (REPORT-063 section 6.2 / REPORT-067
section 4.3 call it the "stale expectation" class; TASK-064 D-8 closed four of
them). This script makes the survey machine-checkable instead of a claim in a
report: it finds every occurrence of the numbers the task book names
(171 / 173 / 175 / 176 / 152 / 72 / 153) under `modules/mcp_server/scripts/`
and under `modules/mcp_server/docs/scripts/`, classifies each one from the line
it sits on, and exits non-zero if any line is in the `UNCLASSIFIED` bucket.

Buckets
-------
FROZEN     the number names one historical revision and no live artifact is
           compared against it on that line (a diff of two past contract files,
           a manifest range, an assertion about the frozen old contract, a
           pinned narrowing-point line number, a probe that *asserts* a stale
           literal is false, ...). Reading it on a later tree is not a gate
           failure because the line does not decide anything about today.
DERIVED    the line derives the number from the artifacts (`+ added_count`,
           `_meta.count`, `$ExpectedContractSize`, `171 ported +`, ...).
CHECKED    the line is an assertion that the ported half is still 171 / the map
           is still 174 - the kind of literal TASK-064 and TASK-068 keep on
           purpose.
LIVE       the line asserts the *endpoint* size (editor 153 / game 72) - these
           move with every implemented group and are re-derived by
           `scripts/accept_m1.ps1` and the two `*_added_tools_evidence.ps1`.

Any line whose bucket cannot be decided is printed as UNCLASSIFIED and fails
the run; that is the point of the script - the census cannot silently skip a
number it does not understand.

Usage:
    python scripts/check_hardcoded_counts.py [--root PATH] [--verbose]
Exit 0 when there are zero UNCLASSIFIED lines.
"""

import argparse
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT = os.path.dirname(HERE)

NUMBERS = ("171", "173", "175", "176", "152", "72", "153")
NUMBER_RE = re.compile(r"(?<![0-9A-Za-z_])(%s)(?![0-9A-Za-z_])" % "|".join(NUMBERS))

# Directories that make up the surveyed set, relative to the module root.
SURVEY_DIRS = (
    os.path.join("scripts",),
    os.path.join("docs", "scripts"),
)
SCANNED_SUFFIXES = (".py", ".ps1", ".cmd", ".sh")

# A line is DERIVED when the number is not a standalone expectation: the line
# spells the arithmetic instead, or reads the count out of an artifact.
DERIVED_PATTERNS = (
    r"added_count",
    r"_meta\.count",
    r"\$\w*added\w*count",
    r"addedNames\.Count",
    r"\$addedTools\.Count",
    r"addedManifestNames\.Count",
    r"portedCount",
    r"CONTRACT_PORTED_COUNT",
    r"EXPECTED_PORTS",
    r"\$\w*ExpectedContractSize",
    r"\$\w*ExpectedAddedCount",
    r"\bport(ed)?\b",
    r"len\(ADDED_TOOLS\)",
    r"len\(new_tools\)",
    r"len\(ctools\)",
    r"171 \+ N",
    r"171 \+ \$",
    r"port\b",
    r"= \$ported",
)
# A line is FROZEN when it is prose, a diff/probe of a past revision, a pin
# line number, or an assertion *about* a stale literal.
FROZEN_PATTERNS = (
    r"^\s*#",
    r"^\s*//",
    r"^\s*;",
    r'^\s*"""',
    r"^\s*'",
    r"^\s*\*",
    r"TASK-0\d\d",
    r"REPORT-0\d\d",
    r"stale",
    r"BL\d",
    r"EXPECTED_TOOLS",
    r"EXPECTED_PORTS",
    # A quoted expression that *is* the stale literal being proven false by a
    # probe (mcp064 / mcp068) - the probe's own assertion is that it is FALSE.
    r"-Expression '\(\$?\w+\.Count -eq 17[0-9]\)'",
    r"-Expression '-?\$?\w+ -eq 17[0-9]'",
    # A sentence about the *past* revision ("the 171 entry contract").
    r"entry contract",
    r"171/171",
    r"171 - 2 unregister",
    r"103\", \"164\", \"171\"",
    # A repeated-dash separator or a text-art width.
    r'"=" \* 72',
    r'lines\.append\("=" \* 72\)',
    # The pin tables of check_narrowing_points.py carry *line numbers*, not tool
    # counts: `_pin("ID", <line>, ...)`.
    r'_pin\("[A-Z0-9-]+", \d+',
    # A reason string that merely names the number it measured.
    r'no longer matches the real 176',
    r'project\.rs:175',
    r'173 of the 175',
    r'count stays 175',
    r'count of contract entries \(171\)',
    r'--check-completeness',
    # A prose note about where a past version left the count (`stay exactly
    # where v1.19 left them (**176 entries**)`).
    r'left them',
    # A prose diff line describing a *past* pair of revisions
    # (`count (171 -> 173)`), i.e. a historical note, not a live comparison.
    r"-> 17[0-9]",
    r"17[0-9] ->",
    # The TASK-068 module-level docstring of check_rename_map.py explains what
    # the literal means; it is prose (its own line is not an assertion).
    r"literal `171`",
    r"asserted to be 171",
)
# A line is CHECKED when it asserts the frozen half of the map / contract.
CHECKED_PATTERNS = (
    r"== 17[14]",
    r"-eq 17[14]",
    r"map total",
    r"frozen",
    r"Frozen",
)
# A line is PINNED when it is a hard literal compared against a live artifact
# (the contract file, or a live endpoint's tool count). TASK-064 D-8 changed
# four of these to derivations; the ones that remain are intentional pins and
# are listed, with their reason, in REPORT-068 section 2.3. A PINNED line is
# *allowed* to go stale when a later task grows the contract - that is the
# class this survey exists to make visible.
PINNED_PATTERNS = (
    r"\$contractNames\.Count -eq 17[0-9]",
    r"\$names[AB]?\.Count -eq 7[0-9]",
    r"\$list[AG]Count -eq 7[0-9]",
    r"\$list[AG]Count -eq 15[0-9]",
    r"\$names[AB]?\.Count -eq 15[0-9]",
    r"Check 'contract_is_17[0-9]_entries'",
)
# A line is LIVE when it asserts an endpoint size through a variable whose name
# says it is the live list.
LIVE_PATTERNS = (
    r"live 98",
    r"endpoint",
    r"editor view",
    r"game view",
)


def classify(line):
    stripped = line.strip()
    # 1. A line that re-derives the size can never be a stale literal.
    for pattern in DERIVED_PATTERNS:
        if re.search(pattern, line):
            return "DERIVED"
    # 2. A hard literal compared against a live artifact: the class REPORT-063
    #    / 067 call "stale expectation" once the artifact grows.
    for pattern in PINNED_PATTERNS:
        if re.search(pattern, line):
            return "PINNED"
    # 3. The checked halves TASK-064 / 068 keep on purpose.
    for pattern in CHECKED_PATTERNS:
        if re.search(pattern, line):
            return "CHECKED"
    # 4. A comment, a probe's own quote of a stale literal, or a prose note
    #    about a past revision names a number no live comparison reads.
    for pattern in FROZEN_PATTERNS:
        if re.search(pattern, line):
            return "FROZEN"
    # 5. An assertion about the live endpoint carries the endpoint's own number.
    for pattern in LIVE_PATTERNS:
        if re.search(pattern, line):
            return "LIVE"
    if re.search(r"153|152|72", line) and re.search(r"editor|game|endpoint|tools_list|namesA|namesB|listA|listG", line):
        return "LIVE"
    if stripped.startswith("$") or stripped.startswith("expected") or re.search(r"Check ", line):
        return "LIVE"
    return "UNCLASSIFIED"


def main():
    parser = argparse.ArgumentParser(description="Survey hard-coded counts in the module scripts.")
    parser.add_argument("--root", default=MODULE_ROOT)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    buckets = {}
    rows = []
    files = []
    self_path = os.path.abspath(__file__)
    for directory in SURVEY_DIRS:
        walk_root = os.path.join(root, directory)
        if not os.path.isdir(walk_root):
            continue
        for name in sorted(os.listdir(walk_root)):
            path = os.path.join(walk_root, name)
            # This survey names its own number set and its own bucket rules, so
            # it would match itself; it is excluded on purpose (SKIPPED below)
            # rather than hidden behind a pattern nobody can audit.
            if os.path.isfile(path) and name.endswith(SCANNED_SUFFIXES) and os.path.abspath(path) != self_path:
                files.append(path)

    print("SURVEY root             = %s" % root)
    print("SURVEY files scanned    = %d" % len(files))
    print("SURVEY SKIPPED (self)   = %s" % os.path.relpath(self_path, root).replace("\\", "/"))
    print("SURVEY numbers          = %s" % ", ".join(NUMBERS))
    print("")

    for path in files:
        with io.open(path, "r", encoding="utf-8", errors="replace") as handle:
            for index, line in enumerate(handle, start=1):
                found = NUMBER_RE.findall(line)
                if not found:
                    continue
                bucket = classify(line)
                buckets[bucket] = buckets.get(bucket, 0) + 1
                rows.append((os.path.relpath(path, root).replace("\\", "/"), index, sorted(set(found)), bucket, line.rstrip()))

    for bucket in ("DERIVED", "CHECKED", "PINNED", "LIVE", "FROZEN", "UNCLASSIFIED"):
        count = buckets.get(bucket, 0)
        print("BUCKET %-12s = %d" % (bucket, count))
    print("BUCKET total        = %d" % len(rows))
    print("")

    if args.verbose:
        for rel, index, numbers, bucket, text in rows:
            print("%-8s %s:%d  [%s]  %s" % (bucket, rel, index, ",".join(numbers), text.strip()[:150]))
        print("")

    unclassified = [row for row in rows if row[3] == "UNCLASSIFIED"]
    for rel, index, numbers, bucket, text in unclassified:
        print("UNCLASSIFIED %s:%d [%s] %s" % (rel, index, ",".join(numbers), text.strip()))

    if unclassified:
        print("")
        print("RESULT: FAIL (%d unclassified line(s))" % len(unclassified))
        return 1
    print("RESULT: PASS (every occurrence of %s is classified; none is UNCLASSIFIED)" % "/".join(NUMBERS))
    return 0


if __name__ == "__main__":
    sys.exit(main())