# -*- coding: utf-8 -*-
"""Verify docs/tool-groups.json against the frozen B1 list and the contract.

TASK-002 section 2.3.1 makes `docs/tool-groups.json` the *only* input of the
follow-up parallel porting batches, so it has to be exact. This checker is the
executable form of that requirement:

  1. the B1 old-name list is re-derived from `docs/DESIGN-DETAIL.md` section 10
     (the two B1 paragraphs) and from `docs/tool-rename-map.json`;
  2. `get_editor_performance` is dropped (GDR-17 lossless merge, already
     registered elsewhere), leaving exactly 41 tools;
  3. every one of the 41 appears in the manifest **exactly once** (no missing,
     no duplicate, no foreign name);
  4. every group is one `channel` + one `mutating` value and its declared value
     matches the rename map for every member;
  5. group sizes respect the <=10 cap of section 2.3.1;
  6. no tool name is accidentally taken from the 130 non-B1 contract entries.

Usage:  python modules/mcp_server/docs/scripts/check_tool_groups.py
Standard library only (Python 3.9).
"""

import collections
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)

DETAIL_MD = os.path.join(DOCS, "DESIGN-DETAIL.md")
MAP_JSON = os.path.join(DOCS, "tool-rename-map.json")
CONTRACT_JSON = os.path.join(DOCS, "tools_list.renamed.json")
GROUPS_JSON = os.path.join(DOCS, "tool-groups.json")

EXPECTED_B1_OLD = 42
EXPECTED_PORTED = 41
EXPECTED_GROUPS = 7
MAX_GROUP_SIZE = 10


def ev(line):
    print(line)


def read_b1_old_names():
    """Re-derive the B1 old-name list from DESIGN-DETAIL.md section 10.

    The section declares `**B1 ... — 42 个**：` followed by backticked names."""
    text = io.open(DETAIL_MD, encoding="utf-8").read()
    match = re.search(r"\*\*B1[^*]*?(\d+)\s*个\*\*：(.*?)\n\n", text, re.S)
    if not match:
        sys.exit("FATAL: cannot locate the B1 paragraph in DESIGN-DETAIL.md")
    declared = int(match.group(1))
    names = re.findall(r"`([a-z0-9_]+)`", match.group(2))
    if declared != EXPECTED_B1_OLD:
        sys.exit("FATAL: DESIGN-DETAIL.md declares %d B1 tools, expected %d" % (declared, EXPECTED_B1_OLD))
    if len(names) != EXPECTED_B1_OLD:
        sys.exit("FATAL: parsed %d B1 names, expected %d" % (len(names), EXPECTED_B1_OLD))
    ev("SOURCE  DESIGN-DETAIL.md section 10: B1 declares %d old tools, parsed %d/%d"
       % (declared, len(names), EXPECTED_B1_OLD))
    return names


def main():
    raw = open(GROUPS_JSON, "rb").read()
    groups_doc = json.loads(raw.decode("utf-8"))
    rename_map = json.loads(open(MAP_JSON, "rb").read().decode("utf-8"))
    contract = json.loads(open(CONTRACT_JSON, "rb").read().decode("utf-8"))

    by_old = dict((t["old_name"], t) for t in rename_map["tools"])
    contract_names = [t["name"] for t in contract["result"]["tools"]]

    old_names = read_b1_old_names()
    missing_from_map = [n for n in old_names if n not in by_old]
    if missing_from_map:
        sys.exit("FATAL: B1 old names missing from the rename map: %s" % missing_from_map)

    excluded = [n for n in old_names if by_old[n]["disposition"] == "merge_into"]
    ported = [by_old[n]["new_name"] for n in old_names if n not in excluded]
    if len(ported) != EXPECTED_PORTED:
        sys.exit("FATAL: expected %d ported B1 tools, got %d" % (EXPECTED_PORTED, len(ported)))
    ev("DERIVE  excluded (merge_into) = %s" % ", ".join(excluded))
    ev("DERIVE  B1 tools to port = %d - %d = %d" % (EXPECTED_B1_OLD, len(excluded), len(ported)))

    groups = groups_doc["groups"]
    if len(groups) != EXPECTED_GROUPS:
        sys.exit("FATAL: expected %d groups, got %d" % (EXPECTED_GROUPS, len(groups)))

    seen = collections.Counter()
    for group in groups:
        name = group["name"]
        tools = group["tools"]
        if not tools:
            sys.exit("FATAL: group %s is empty" % name)
        if len(tools) > MAX_GROUP_SIZE:
            sys.exit("FATAL: group %s has %d tools (> %d)" % (name, len(tools), MAX_GROUP_SIZE))
        if group["channel"] not in ("editor", "running_game", "project", "os"):
            sys.exit("FATAL: group %s has an illegal channel %r" % (name, group["channel"]))
        if not isinstance(group["mutating"], bool):
            sys.exit("FATAL: group %s must declare a boolean mutating" % name)
        for tool in tools:
            seen[tool] += 1
            entry = [t for t in rename_map["tools"] if t["new_name"] == tool]
            if not entry:
                sys.exit("FATAL: group %s lists unknown tool %s" % (name, tool))
            if entry[0]["channel"] != group["channel"]:
                sys.exit("FATAL: %s is %s but group %s declares channel %s"
                         % (tool, entry[0]["channel"], name, group["channel"]))
            if bool(entry[0]["mutating"]) != group["mutating"]:
                sys.exit("FATAL: %s mutating=%s but group %s declares %s"
                         % (tool, entry[0]["mutating"], name, group["mutating"]))
        ev("GROUP   %-28s channel=%-12s mutating=%-5s implemented=%-5s tools=%d"
           % (name, group["channel"], group["mutating"], group["implemented"], len(tools)))

    duplicates = sorted(n for n, c in seen.items() if c > 1)
    if duplicates:
        sys.exit("FATAL: tool(s) listed more than once: %s" % duplicates)
    foreign = sorted(set(seen) - set(ported))
    if foreign:
        sys.exit("FATAL: tool(s) that are not B1 tools: %s" % foreign)
    absent = sorted(set(ported) - set(seen))
    if absent:
        sys.exit("FATAL: B1 tool(s) missing from the manifest: %s" % absent)

    not_in_contract = [n for n in seen if n not in contract_names]
    if not_in_contract:
        sys.exit("FATAL: manifest name(s) absent from the contract: %s" % not_in_contract)

    ev("ASSERT  distinct tools in manifest = %d" % len(seen))
    ev("ASSERT  B1 tools to port        = %d" % len(ported))
    ev("ASSERT  every B1 tool appears exactly once: PASS (duplicates=0, missing=0, foreign=0)")
    ev("ASSERT  every name exists in the 171 entry contract: PASS")
    ev("ASSERT  every group is one channel + one mutating value: PASS")
    ev("ASSERT  41 == %d - %d: PASS" % (EXPECTED_B1_OLD, len(excluded)))
    print("BYTES %d" % len(raw))
    print("SHA256 " + __import__("hashlib").sha256(raw).hexdigest())
    print("TOOL-GROUPS CHECK PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
