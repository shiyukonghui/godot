#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TASK-076 A.1 evidence: the contract moved by DESCRIPTIONS ONLY.

Compares the committed contract (`git show HEAD:...`) with the regenerated one
and asserts, key by key:
  * the entry count is unchanged (177);
  * the tool NAME order is unchanged;
  * every `inputSchema` is byte-identical;
  * every `description` is byte-identical except the three declared by v1.22;
  * `_meta` differs only in `generator_version` and `overrides`.

Usage:
    python scripts/mcp076_descriptions_only.py [--rev HEAD:modules/mcp_server/docs/tools_list.renamed.json]
Exit 0 when every claim holds; 1 otherwise. Output is UTF-8 (redirect to a file).
"""
import argparse
import hashlib
import io
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT = os.path.dirname(HERE)
CONTRACT_REL = "modules/mcp_server/docs/tools_list.renamed.json"
CONTRACT = os.path.join(MODULE_ROOT, "docs", "tools_list.renamed.json")
EXPECTED_MOVED = ("editor_get_scene_tree", "editor_set_tilemap_cell", "editor_set_tilemap_cells_in_rect")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rev", default="HEAD:" + CONTRACT_REL)
    args = parser.parse_args()

    repo_root = os.path.abspath(os.path.join(MODULE_ROOT, "..", ".."))
    old_raw = subprocess.check_output(["git", "-C", repo_root, "show", args.rev])
    old = json.loads(old_raw.decode("utf-8"))
    new_raw = open(CONTRACT, "rb").read()
    new = json.loads(new_raw.decode("utf-8"))

    failures = 0

    def check(ok, text):
        nonlocal failures
        if not ok:
            failures += 1
        print("[%s] %s" % ("PASS" if ok else "FAIL", text))

    print("old contract (git %s) sha256 = %s" % (args.rev, hashlib.sha256(old_raw).hexdigest()))
    print("new contract (worktree) sha256 = %s" % hashlib.sha256(new_raw).hexdigest())
    print("")

    old_tools = old["result"]["tools"]
    new_tools = new["result"]["tools"]
    check(len(old_tools) == 177 and len(new_tools) == 177,
          "entry count unchanged: old=%d new=%d (177)" % (len(old_tools), len(new_tools)))

    old_names = [t["name"] for t in old_tools]
    new_names = [t["name"] for t in new_tools]
    check(old_names == new_names, "tool name order unchanged (%d names)" % len(new_names))
    check(len(set(new_names)) == len(new_names), "tool names still unique")

    schema_diffs = [n["name"] for o, n in zip(old_tools, new_tools) if json.dumps(o["inputSchema"], sort_keys=True) != json.dumps(n["inputSchema"], sort_keys=True)]
    check(not schema_diffs, "every inputSchema byte-identical (differences: %s)" % (schema_diffs or "none"))

    desc_diffs = [n["name"] for o, n in zip(old_tools, new_tools) if o["description"] != n["description"]]
    check(sorted(desc_diffs) == sorted(EXPECTED_MOVED),
          "exactly the declared descriptions moved: %s" % (desc_diffs or "none"))
    for o, n in zip(old_tools, new_tools):
        if n["name"] in EXPECTED_MOVED:
            check(n["description"].startswith(o["description"] + " "),
                  "%s: append-only (original wording is the verbatim prefix)" % n["name"])
            print("      old bytes=%d new bytes=%d" % (len(o["description"].encode("utf-8")),
                                                       len(n["description"].encode("utf-8"))))

    old_meta = dict(old["_meta"])
    new_meta = dict(new["_meta"])
    check(old_meta.get("count") == new_meta.get("count") == 177, "_meta.count unchanged (177)")
    check(old_meta.get("added_count") == new_meta.get("added_count") == 6, "_meta.added_count unchanged (6)")
    check(old_meta.get("added_tools") == new_meta.get("added_tools"), "_meta.added_tools unchanged")
    check(old_meta.get("order_normative") == new_meta.get("order_normative") is False, "_meta.order_normative unchanged")
    check(old_meta.get("map_sha256") == new_meta.get("map_sha256"), "map_sha256 unchanged (the map was not touched)")
    buckets = {}
    for m in (old_meta, new_meta):
        for key, value in m.items():
            buckets.setdefault(key, []).append(json.dumps(value, sort_keys=True, ensure_ascii=False))
    moved = sorted(k for k, v in buckets.items() if len(v) == 2 and v[0] != v[1])
    check(moved == ["generator_version", "overrides"],
          "_meta differences limited to generator_version + overrides: %s" % moved)
    check(old_meta["generator_version"] == "1.21.0" and new_meta["generator_version"] == "1.22.0",
          "generator_version 1.21.0 -> 1.22.0")
    check(len(old_meta["overrides"]) == 33 and len(new_meta["overrides"]) == 36,
          "overrides 33 -> 36 (three description/append records)")

    old_pairs = set((r["kind"], r["old_name"], r["mode"]) for r in old_meta["overrides"])
    new_pairs = set((r["kind"], r["old_name"], r["mode"]) for r in new_meta["overrides"])
    added_pairs = sorted(new_pairs - old_pairs)
    check(added_pairs == [("description", "get_scene_tree", "append"),
                          ("description", "tilemap_fill_rect", "append"),
                          ("description", "tilemap_set_cell", "append")],
          "the only new override records: %s" % (added_pairs,))
    check(not (old_pairs - new_pairs), "no pre-existing override record was removed or changed")

    print("")
    print("RESULT: %s" % ("PASS (the contract moved by descriptions only)" if not failures
                          else "FAIL (%d claim(s) failed)" % failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
