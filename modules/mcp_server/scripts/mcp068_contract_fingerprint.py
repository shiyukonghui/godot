#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TASK-068 helper: print the contract fingerprints and the two moved descriptions.

Pure ASCII source; the output is UTF-8 and is meant to be redirected to a file
(`set PYTHONIOENCODING=utf-8` first, or read it with the file tool).

Usage:
    python scripts/mcp068_contract_fingerprint.py [--out PATH]
"""

import argparse
import hashlib
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT = os.path.dirname(HERE)
DOCS = os.path.join(MODULE_ROOT, "docs")

FILES = (
    os.path.join(DOCS, "tools_list.renamed.json"),
    os.path.join(DOCS, "tool-rename-map.json"),
    os.path.join(DOCS, "tool-groups.json"),
    os.path.join(DOCS, "tool-groups-b2.json"),
    os.path.join(DOCS, "tool-groups-b3.json"),
    os.path.join(DOCS, "tool-groups-b4.json"),
    os.path.join(DOCS, "tool-groups-b5.json"),
    os.path.join(DOCS, "tool-groups-added.json"),
    os.path.join(MODULE_ROOT, "scripts", "gen_renamed_contract.py"),
    os.path.join(DOCS, "scripts", "check_rename_map.py"),
)

MOVED = ("project_list_scripts", "running_game_run_test_scenario")


def main():
    parser = argparse.ArgumentParser(description="Contract fingerprints and the moved descriptions.")
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    lines = []
    for path in FILES:
        if not os.path.isfile(path):
            lines.append("MISSING %s" % path)
            continue
        raw = open(path, "rb").read()
        lines.append("SHA256 %-72s %s (%d bytes)"
                     % (os.path.basename(path), hashlib.sha256(raw).hexdigest(), len(raw)))

    contract_raw = open(FILES[0], "rb").read()
    contract = json.loads(contract_raw.decode("utf-8"))
    meta = contract["_meta"]
    tools = contract["result"]["tools"]
    lines.append("")
    lines.append("contract entries      = %d" % len(tools))
    lines.append("_meta.count           = %s" % meta.get("count"))
    lines.append("_meta.added_count     = %s" % meta.get("added_count"))
    lines.append("_meta.generator_ver   = %s" % meta.get("generator_version"))
    lines.append("_meta.overrides       = %d" % len(meta.get("overrides", [])))
    lines.append("_meta.order_normative = %s" % meta.get("order_normative"))
    added_manifest = json.loads(open(os.path.join(DOCS, "tool-groups-added.json"), "rb").read().decode("utf-8"))
    lines.append("added manifest genver = %s" % added_manifest.get("source", {}).get("generator_version"))

    by_name = dict((tool["name"], tool) for tool in tools)
    for name in MOVED:
        lines.append("")
        lines.append("=== %s.description ===" % name)
        lines.append(by_name[name]["description"])

    text = "\n".join(lines) + "\n"
    if args.out:
        with io.open(args.out, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())