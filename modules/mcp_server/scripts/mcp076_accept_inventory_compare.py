#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TASK-076 A.3 evidence: the two `accept_m1.ps1` inventories are identical.

Gate 5 is "accept_m1.ps1 twice, and the two PASS lists are identical". The
second half is what decides whether the batch is repeatable, and it is the half
that a reader cannot see in either log alone. This helper extracts the
`tool_names=` line from two captured runs, hashes it, and writes the comparison
to a JSON file next to the logs.

Usage:
    python scripts/mcp076_accept_inventory_compare.py --run1 <log> --run2 <log> [--out <json>]
Exit 0 when both runs carry the line and the two are byte-identical.
"""
import argparse
import hashlib
import io
import json
import re
import sys

LINE_RE = re.compile(r"^(.*\btool_names=.*)$", re.M)


def extract(path):
    text = io.open(path, encoding="utf-8", errors="replace").read()
    matches = LINE_RE.findall(text)
    if not matches:
        return None
    # The last match is the summary line; earlier ones are per-case echoes.
    line = matches[-1].strip()
    marker = "tool_names="
    names = line.split(marker, 1)[1]
    return line, names


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run1", required=True)
    parser.add_argument("--run2", required=True)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    first = extract(args.run1)
    second = extract(args.run2)
    failures = 0
    report = {}
    if first is None or second is None:
        failures += 1
        report["error"] = "one of the runs carries no tool_names= line"
        print("FAIL: %s" % report["error"])
    else:
        line1, names1 = first
        line2, names2 = second
        shared = names1 == names2
        report = {
            "run1": args.run1,
            "run2": args.run2,
            "run1_line_sha256": hashlib.sha256(line1.encode("utf-8")).hexdigest(),
            "run2_line_sha256": hashlib.sha256(line2.encode("utf-8")).hexdigest(),
            "run1_names_sha256": hashlib.sha256(names1.encode("utf-8")).hexdigest(),
            "run2_names_sha256": hashlib.sha256(names2.encode("utf-8")).hexdigest(),
            "run1_name_count": len(names1.split(",")),
            "run2_name_count": len(names2.split(",")),
            "byte_identical": shared,
            "verdict": "PASS" if shared else "FAIL",
        }
        if not shared:
            failures += 1
        print("run1 tool_names line sha256 = %s (%d names)" % (report["run1_line_sha256"], report["run1_name_count"]))
        print("run2 tool_names line sha256 = %s (%d names)" % (report["run2_line_sha256"], report["run2_name_count"]))
        print("run1 names sha256           = %s" % report["run1_names_sha256"])
        print("run2 names sha256           = %s" % report["run2_names_sha256"])
        print("byte identical              = %s" % shared)
        print("")
        print("RESULT: %s" % ("PASS (the two accept_m1 inventories are byte-identical)" if shared
                               else "FAIL (the two accept_m1 inventories differ)"))
    if args.out:
        with io.open(args.out, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        print("wrote %s" % args.out)
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
