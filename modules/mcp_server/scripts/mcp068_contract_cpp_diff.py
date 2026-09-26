#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TASK-068 helper: the contract description vs the C++ builder description.

Gate 1 (`scripts/check_contract_subset.ps1`) compares the *live* `tools/list` to
the contract, and the live description comes from the module's own C++ source
(the server has no access to `docs/`). For the tools whose contract text moves,
the two spellings have to be byte-identical, and this script is what proves it
before a build is spent on the question.

It reads the description from `ToolBuilder builder("<name>", String::utf8("<...>"))`
literally - the C++ string is NOT unescaped, so a `\"` in the source would be
reported as a mismatch (which is the point: the generator emits raw text, so an
escaped quote would already be a contract mismatch). A description is compared
only for the tools named in `CHECKED` (append-only, one line, UTF-8 source).

Usage:
    python scripts/mcp068_contract_cpp_diff.py
Exit 0 when every listed tool matches character for character.
"""

import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT = os.path.dirname(HERE)
DOCS = os.path.join(MODULE_ROOT, "docs")

CHECKED = {
    "project_list_scripts": os.path.join(MODULE_ROOT, "tools", "project_read_files.cpp"),
    "running_game_run_test_scenario": os.path.join(MODULE_ROOT, "tools", "running_game_test_execution.cpp"),
    # TASK-076 section A.1: the three descriptions that moved with v1.22.
    "editor_get_scene_tree": os.path.join(MODULE_ROOT, "tools", "editor_read_scene_inspector.cpp"),
    "editor_set_tilemap_cell": os.path.join(MODULE_ROOT, "tools", "editor_tilemap_write.cpp"),
    "editor_set_tilemap_cells_in_rect": os.path.join(MODULE_ROOT, "tools", "editor_tilemap_write.cpp"),
}

CONTRACT = os.path.join(DOCS, "tools_list.renamed.json")


def main():
    contract = json.loads(open(CONTRACT, "rb").read().decode("utf-8"))
    by_name = dict((tool["name"], tool) for tool in contract["result"]["tools"])
    failures = 0
    for name, path in sorted(CHECKED.items()):
        text = io.open(path, encoding="utf-8").read()
        # Two literal spellings are in use: a plain C++ string (the generated
        # game-schema blocks, `String::utf8("...")`) and the raw-string form the
        # hand-written B5 registrations use (`String::utf8(R"desc(...)desc")`,
        # TASK-076 section A.1). Both are checked; the C++ text is NOT unescaped
        # in the plain form, which is the point (a `\"` would be a mismatch).
        patterns = (
            re.compile(r'ToolBuilder builder\("%s", String::utf8\("([^"]*)"\)\);' % re.escape(name)),
            re.compile(r'ToolBuilder builder\("%s", String::utf8\(R"desc\((.*?)\)desc"\)\);' % re.escape(name), re.S),
        )
        match = None
        for pattern in patterns:
            match = pattern.search(text)
            if match:
                break
        if not match:
            print("FAIL %s: no ToolBuilder line found in %s" % (name, os.path.relpath(path, MODULE_ROOT)))
            failures += 1
            continue
        live = match.group(1)
        expected = by_name[name]["description"]
        same = (live == expected)
        print("%s %s" % ("MATCH" if same else "DIFF ", name))
        print("      source     : %s" % os.path.relpath(path, MODULE_ROOT).replace("\\", "/"))
        print("      cpp bytes  : %d" % len(live.encode("utf-8")))
        print("      contract   : %d bytes" % len(expected.encode("utf-8")))
        if not same:
            failures += 1
            first = 0
            while first < min(len(live), len(expected)) and live[first] == expected[first]:
                first += 1
            print("      first diff at char %d" % first)
            print("      cpp      : %r" % live[max(0, first - 20):first + 40])
            print("      contract : %r" % expected[max(0, first - 20):first + 40])
    print("")
    if failures:
        print("RESULT: FAIL (%d tool(s) differ)" % failures)
        return 1
    print("RESULT: PASS (every checked tool's C++ description is the contract's description verbatim)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
