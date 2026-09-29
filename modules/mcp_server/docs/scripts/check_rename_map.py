#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent self-check for docs/tool-rename-map.json (v1.1) + the generated contract.

Written for TASK-001 section 3.1 / 3.2 / 3.3. It does NOT reuse the v1.0
`check.py` conclusions: every predicate below is evaluated here from the raw
bytes of the two data files, and every failure is a hard non-zero exit.

Checks
------
A. shape          : total == len(tools) == 174
B. coverage       : old_name set == the frozen old contract's tool names (both
                    directions empty)
C. uniqueness     : new_name of every non-merge_into entry is globally unique
D. lint           : new_name matches ^(editor|running_game|project|os)_[a-z0-9_]+$
                    (channel prefix stripped longest-first), verb in the closed
                    set, declared channel/verb == parsed, no `update_`
E. disposition    : value in the enum; merge_into carries a merge_target that
                    points at an existing old_name; no `merge_into:<old_name>`
                    inline form survives
F. counts         : disposition rename 164 / fix 7 / merge 1 / unregister 2;
                    channel editor 103 / project 45 / running_game 24 / os 2;
                    mutating true == 103
G. contract       : docs/tools_list.renamed.json has all names unique, the 2
                    unregister + 1 merge source names are absent, the two
                    de-merged tools are present under two distinct names, and its
                    size is **derived** as
                        (map total) - 2 unregister - 1 merge + added_count
                    with the 171 ported half still asserted as a literal

The TASK-068 G-section change
-----------------------------
Until TASK-068 G1/G5 pinned the literal `171`, which was the ported entry count
of the v1.1 rename map. The contract has been `171 + N` since TASK-052/053/063
(`_meta.added_count`, `docs/tool-groups-added.json`), so `len(ctools) == 171`
and `len(ctools) == 174 - 2 - 1` had gone red on a tree where **nothing this
script audits** was wrong: it was REPORT-067 section 4.3's "stale expectation"
class (a size written down for one revision and then re-read on another). What
the script has to say is that the ported *half* is still 171, that the added
count is what the contract declares **and** what the sixth manifest lists, and
that no name leaked or vanished - none of which needs the literal `171` to be
the thing compared against `len(ctools)`.

So the literal stays, as a **checked** literal, and the size comparison is a
derivation:

  * `ported = 174 - 2 - 1` (map total - unregister - merge) equals the number of
    `new_name`s of the entries that are neither unregistered nor merged, and is
    asserted to be 171;
  * `added = _meta.added_count` must equal `len(_meta.added_tools)` and be
    non-negative, and each added name must be in the contract;
  * `len(ctools) == ported + added` is what the two G checks now assert.

Nothing is weakened: a deleted ported entry makes `ported` fall (B2/C1 fail), a
contract that stops carrying an added tool makes the derivation fail, and a
contract whose meta disagrees with its own list is a FATAL before any G check
runs. Every one of those predicates is still a hard non-zero exit.

Usage:  python check_rename_map.py [--old-contract PATH] [--map PATH] [--contract PATH]
Standard library only (Python 3.9).
"""

import argparse
import collections
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
MODULE_ROOT = os.path.dirname(DOCS)

DEFAULT_MAP = os.path.join(DOCS, "tool-rename-map.json")
DEFAULT_CONTRACT = os.path.join(DOCS, "tools_list.renamed.json")

# TASK-152: the old-contract baseline is an ENGINE-REPOSITORY artifact.
#
# Until TASK-152 this name was bound to the hof-rs working file
# `F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json`, so the gate's verdict
# depended on a file outside the repository it audits. hof-rs re-captured that
# fixture in its own DR-42 contract migration (hof-rs commit db2eed7, 174 -> 177
# tools), which turned B0/B1/B2 red on a tree where nothing this script audits
# had changed - the cross-repository coupling of D225. The baseline now lives
# inside the repository as a frozen byte-for-byte copy.
#
# Provenance (recorded where the constant is, per TASK-152 section 2A):
#   path  : docs/rename-baseline-tools-list.json   (this directory)
#   bytes : 48749     tools: 174     eol: none (the file carries no newline)
#   sha256: 8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54
#   source: hof-rs `tests/fixtures/mcp/tools_list.json` at the state immediately
#           before its DR-42 re-capture (hof-rs commit db2eed7^, git blob
#           543b49b2583bf06c3aba2a320649a31eda272e3e)
#   taken : 2026-09-29, with
#           `git -C F:\moonbit-hof-rs cat-file blob \
#                543b49b2583bf06c3aba2a320649a31eda272e3e`
#           (a pure read of the hof-rs object store; nothing on the hof-rs side
#            was written), then written verbatim into this repository.
# The three values are identical to the ones this script has always frozen, so
# the strictness of B0/B1/B2 is unchanged; only the location of the bytes moved.
DEFAULT_OLD_CONTRACT = os.path.join(DOCS, "rename-baseline-tools-list.json")

OLD_CONTRACT_SHA256 = "8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54"
OLD_CONTRACT_TOOL_COUNT = 174

# GDR-16 L1: longest prefix first (`running_game_` carries its own underscore).
CHANNELS = ("running_game", "project", "editor", "os")
L1_PATTERN = re.compile(r"^(editor|running_game|project|os)_[a-z0-9_]+$")

DISPOSITION_ENUM = (
    "rename",
    "keep",
    "merge_into",
    "unregister_until_implemented",
    "fix_implementation_first",
)

EXPECTED_DISPOSITION = {
    "rename": 164,
    "fix_implementation_first": 7,
    "merge_into": 1,
    "unregister_until_implemented": 2,
}
EXPECTED_CHANNEL = {"editor": 103, "project": 45, "running_game": 24, "os": 2}

FAILURES = []


def check(label, ok, detail=""):
    status = "PASS" if ok else "FAIL"
    print("[%s] %-58s %s" % (status, label, detail))
    if not ok:
        FAILURES.append(label)
    return ok


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_tool_name(name):
    """Isomorphic to MCPToolRegistry::parse_tool_name (tool_registry.cpp:62-87)."""
    for channel in CHANNELS:
        prefix = channel + "_"
        if not name.startswith(prefix):
            continue
        rest = name[len(prefix):]
        if not rest:
            return None
        if not all((("a" <= c <= "z") or ("0" <= c <= "9") or c == "_") for c in rest):
            return None
        return channel, rest.split("_", 1)[0]
    return None


def main():
    parser = argparse.ArgumentParser(description="Self-check the v1.1 rename map.")
    parser.add_argument("--map", default=DEFAULT_MAP)
    parser.add_argument("--contract", default=DEFAULT_CONTRACT)
    parser.add_argument("--old-contract", default=DEFAULT_OLD_CONTRACT)
    args = parser.parse_args()

    map_path = os.path.abspath(args.map)
    contract_path = os.path.abspath(args.contract)
    old_path = os.path.abspath(args.old_contract)

    raw = open(map_path, "rb").read()
    rename_map = json.loads(raw.decode("utf-8"))
    tools = rename_map["tools"]
    print("MAP      %s" % map_path)
    print("MAP      bytes=%d sha256=%s" % (len(raw), hashlib.sha256(raw).hexdigest()))
    print("MAP      convention_version=%s" % rename_map.get("convention_version"))
    print("")

    # --- A. shape -----------------------------------------------------------
    check("A1 total == 174", rename_map.get("total") == 174, "total=%s" % rename_map.get("total"))
    check("A2 len(tools) == 174", len(tools) == 174, "len=%d" % len(tools))

    # --- B. coverage vs the frozen old contract -----------------------------
    old_sha = sha256_file(old_path)
    check("B0 old contract sha256 frozen", old_sha == OLD_CONTRACT_SHA256, old_sha)
    old_contract = json.load(open(old_path, "r", encoding="utf-8"))
    old_names = [t["name"] for t in old_contract["result"]["tools"]]
    entry_names = [t["old_name"] for t in tools]
    only_old = sorted(set(old_names) - set(entry_names))
    only_map = sorted(set(entry_names) - set(old_names))
    check("B1 old contract tools == 174", len(old_names) == OLD_CONTRACT_TOOL_COUNT,
          "len=%d" % len(old_names))
    check("B2 bidirectional diff empty", not only_old and not only_map,
          "contract-only=%s map-only=%s" % (only_old, only_map))
    check("B3 old_name unique", len(set(entry_names)) == 174,
          "distinct=%d" % len(set(entry_names)))

    by_old = {t["old_name"]: t for t in tools}
    closed_set = set(rename_map["convention"]["verb_closed_set"])

    # --- E. disposition -----------------------------------------------------
    bad_enum = sorted({t["disposition"] for t in tools} - set(DISPOSITION_ENUM))
    check("E1 disposition values inside the enum", not bad_enum, "outside=%s" % bad_enum)
    inline_merge = [t["old_name"] for t in tools if t.get("disposition", "").startswith("merge_into:")]
    check("E2 no inline 'merge_into:<old_name>' form", not inline_merge, "leftover=%s" % inline_merge)
    merges = [t for t in tools if t["disposition"] == "merge_into"]
    target_ok = all("merge_target" in t and t["merge_target"] in by_old for t in merges)
    check("E3 every merge_into has a resolvable merge_target", target_ok,
          "targets=%s" % [t.get("merge_target") for t in merges])
    stray = [t["old_name"] for t in tools
             if t["disposition"] != "merge_into" and "merge_target" in t]
    check("E4 merge_target only on merge_into entries", not stray, "stray=%s" % stray)

    # --- C. uniqueness ------------------------------------------------------
    excluded = [t["old_name"] for t in tools
                if t["disposition"] == "unregister_until_implemented"]
    merged = [t["old_name"] for t in merges]
    dropped = set(excluded) | set(merged)
    kept_names = [t["new_name"] for t in tools if t["old_name"] not in dropped]
    dupes = sorted(n for n, c in collections.Counter(kept_names).items() if c > 1)
    check("C1 non-merged new_name globally unique", not dupes, "duplicates=%s" % dupes)
    # TASK-068: the ported half of the contract, derived from the map's own
    # disposition split rather than written down. `dropped` is exactly the 2
    # unregister + 1 merge set the G section used to subtract as literals, so
    # `len(kept_names)` IS `174 - 2 - 1` - computed from the data instead of
    # restated, which is the whole point of the TASK-068 change. It is asserted
    # to be 171 below (G1), so the literal is a *checked* literal: a map edit
    # that moved the ported count still fails.
    ported_count = len(kept_names)
    all_new = collections.Counter(t["new_name"] for t in tools)
    check("C2 only merge pairs share a new_name",
          sorted(n for n, c in all_new.items() if c > 1) == ["editor_get_performance_monitors"],
          "shared=%s" % sorted(n for n, c in all_new.items() if c > 1))

    # --- D. lint (longest-prefix strip) -------------------------------------
    lint_fail = []
    for t in tools:
        name = t["new_name"]
        if "update_" in name:
            lint_fail.append((name, "L4 banned update_"))
            continue
        if not L1_PATTERN.match(name):
            lint_fail.append((name, "L1 pattern"))
            continue
        parsed = parse_tool_name(name)
        if parsed is None:
            lint_fail.append((name, "L1 parse"))
            continue
        channel, verb = parsed
        if verb not in closed_set:
            lint_fail.append((name, "L2 verb %r outside closed set" % verb))
        if verb != t["verb"]:
            lint_fail.append((name, "L3 verb %r != declared %r" % (verb, t["verb"])))
        if channel != t["channel"]:
            lint_fail.append((name, "L3 channel %r != declared %r" % (channel, t["channel"])))
    check("D1 L1..L4 over all 174 new_name", not lint_fail, "violations=%s" % lint_fail[:4])
    naive = [t["new_name"] for t in tools
             if t["new_name"].startswith("running_game_") and t["new_name"].split("_")[1] != t["verb"]]
    check("D2 naive split('_')[1] demonstrably fails", len(naive) > 0,
          "%d/%d running_game_* misparsed, e.g. %s" % (
              len(naive), sum(1 for t in tools if t["channel"] == "running_game"),
              naive[0] if naive else "-"))
    check("D3 closed set has 37 verbs", len(closed_set) == 37 and len(rename_map["convention"]["verb_closed_set"]) == 37,
          "distinct=%d listed=%d" % (len(closed_set), len(rename_map["convention"]["verb_closed_set"])))

    # --- F. counts ----------------------------------------------------------
    disp = collections.Counter(t["disposition"] for t in tools)
    check("F1 disposition counts 164/7/1/2", dict(disp) == EXPECTED_DISPOSITION, dict(disp))
    channel = collections.Counter(t["channel"] for t in tools)
    check("F2 channel counts 103/45/24/2", {k: channel[k] for k in EXPECTED_CHANNEL} == EXPECTED_CHANNEL,
          dict(channel))
    mut = collections.Counter(bool(t["mutating"]) for t in tools)
    check("F3 mutating true == 103", mut[True] == 103, "true=%d false=%d" % (mut[True], mut[False]))
    check("F4 sum(channel) == 174", sum(channel.values()) == 174, "sum=%d" % sum(channel.values()))
    evaluate = [t["old_name"] for t in tools if t["verb"] == "evaluate"]
    notes = rename_map["convention"].get("verb_notes", {})
    check("F5 'evaluate' kept and annotated unused_in_v1",
          not evaluate and notes.get("evaluate", "").startswith("unused_in_v1"),
          "usage=%d note=%r" % (len(evaluate), notes.get("evaluate", "")))

    # convention completeness (D-4 / D-5 / GDR-18)
    conv = rename_map["convention"]
    need = ["disposition_enum", "scope_enum", "merge_target_semantics",
            "conditional_write_clause", "mutating_semantics"]
    check("F6 convention carries the D-4/D-5 clauses",
          all(k in conv for k in need), "missing=%s" % [k for k in need if k not in conv])
    check("F7 convention.disposition_enum == the enum in force",
          conv.get("disposition_enum") == list(DISPOSITION_ENUM), conv.get("disposition_enum"))
    check("F8 mutating_semantics states 103 and the policy.rs predicate warning",
          "103" in conv.get("mutating_semantics", "") and "MUTATING_EXACT" in conv.get("mutating_semantics", ""),
          "len=%d" % len(conv.get("mutating_semantics", "")))
    shots = [by_old["get_editor_screenshot"], by_old["get_game_screenshot"]]
    check("F9 both screenshot tools: mutating=true + conditional-write reason (GDR-18)",
          all(t["mutating"] is True and "条件写" in t["reason"] for t in shots),
          [(t["new_name"], t["mutating"]) for t in shots])

    # --- G. the generated contract ------------------------------------------
    craw = open(contract_path, "rb").read()
    contract = json.loads(craw.decode("utf-8"))
    ctools = contract["result"]["tools"]
    cnames = [t["name"] for t in ctools]
    print("")
    print("CONTRACT %s" % contract_path)
    print("CONTRACT bytes=%d sha256=%s" % (len(craw), hashlib.sha256(craw).hexdigest()))

    # TASK-068: the added half, read from the contract's own `_meta` (the same
    # authority `scripts/check_tool_groups.py --added` uses). `added_count` is
    # redundant with the list's length *on purpose* (gen_renamed_contract.py
    # says so), so a contract whose meta lies about its own list is a FATAL here
    # rather than a silently larger derivation.
    meta = contract.get("_meta", {})
    added_tools = meta.get("added_tools", [])
    if meta.get("added_count") != len(added_tools):
        sys.exit("FATAL: contract _meta.added_count %r != len(added_tools) %d"
                 % (meta.get("added_count"), len(added_tools)))
    if len(set(added_tools)) != len(added_tools):
        sys.exit("FATAL: contract _meta.added_tools has duplicates: %s" % sorted(added_tools))
    added_count = len(added_tools)
    expected_contract_count = ported_count + added_count
    print("DERIVE  ported (map total %s - 2 unregister - 1 merge) = %d"
          % (rename_map.get("total"), ported_count))
    print("DERIVE  added (_meta.added_count)                    = %d %s"
          % (added_count, sorted(added_tools)))
    print("DERIVE  expected contract size = %d + %d = %d"
          % (ported_count, added_count, expected_contract_count))
    print("")

    check("G1 ported half is still 171", ported_count == 171, "ported=%d" % ported_count)
    check("G2 contract names unique", len(set(cnames)) == len(cnames),
          "distinct=%d" % len(set(cnames)))
    check("G3 no unregistered/merged-source name leaks into the contract",
          not (set(cnames) & dropped), "leaked=%s" % sorted(set(cnames) & dropped))
    de_merged = ["project_find_files_referencing_symbol", "project_search_file_contents",
                 "editor_list_signal_connections", "editor_analyze_signal_flow"]
    check("G4 both de-merged pairs present under 4 distinct names",
          all(n in cnames for n in de_merged), "present=%s" % [n for n in de_merged if n in cnames])
    check("G5 every _meta.added_tool is in the contract",
          not (set(added_tools) - set(cnames)), "absent=%s" % sorted(set(added_tools) - set(cnames)))
    check("G6 contract count == map total - 2 unregister - 1 merge + _meta.added_count",
          len(ctools) == expected_contract_count,
          "%d == %d - 2 - 1 + %d = %d"
          % (len(ctools), rename_map.get("total"), added_count, expected_contract_count))

    print("")
    if FAILURES:
        print("RESULT: FAIL (%d failing checks): %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("RESULT: PASS (all checks green)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
