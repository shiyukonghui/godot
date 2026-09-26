"""TASK-052 contract diff (pure ASCII source).

Compares two `tools_list.renamed.json` revisions and asserts the *shape* of the
change TASK-052 is allowed to make, which is the first change of its kind: the
generator stops being a pure rename + override of the frozen 174 entry map and
*appends* entries the decision maker authored (`DESIGN-DETAIL.md` section 26 /
GDR-28).

What this script pins, and nothing else:

  * the 171 ported entries are **byte-identical** before and after: same name
    set, and for every name the whole entry (name + description + inputSchema)
    is deep-equal. An override that moved a character of a ported entry fails
    here as loudly as a removed tool;
  * the name set grew by **exactly two** names, they are `_meta.added_tools`
    (in that order) and they are the **tail** of `result.tools`, so "the append
    happens after the rename + override pass" (GDR-28 point 1) is checked and
    not just claimed;
  * each added entry carries exactly the three contract fields
    (`description`, `inputSchema`, `name`) - no `_meta`-ish extra member and no
    old-contract leftover - and a non-empty description and object schema;
  * `_meta` moved only in the four fields this batch is allowed to touch:
    `count` (171 -> 173), `generator_version` (1.13.0 -> 1.14.0),
    `added_count` (absent -> 2) and `added_tools` (absent -> the two names).
    `map_sha256`, `generated_from_sha256`, `overrides`, `excluded`, `merged`,
    `tool_count_in`, `order_normative`, `generated_by`, `generated_from` and
    `map_path` are unchanged - the map is not edited to expand the contract, and
    the 28 existing override records do not move.

The wording of the two added entries is *not* duplicated here: it is the
contract file's own content, and gate 1 compares it verbatim against the live
`tools/list` on both endpoints (`scripts/check_contract_subset.ps1 -Group
project_csharp_build|project_text_write`). This script is about the *shape* of
the diff.

Usage:
    python scripts/mcp052_contract_diff.py <before.json> <after.json> <out.json>

Exit code 1 (and a non-empty "problems" list) when an assertion fails.
"""
import io
import json
import os
import sys

ADDED = ["project_build_csharp", "project_write_text_file"]
EXPECTED_PORTS = 171
EXPECTED_AFTER = EXPECTED_PORTS + len(ADDED)
BEFORE_VERSION = "1.13.0"
AFTER_VERSION = "1.14.0"

# Every `_meta` member the two revisions must agree on, byte for byte.
UNCHANGED_META = [
    "generated_from",
    "generated_from_sha256",
    "map_path",
    "map_sha256",
    "tool_count_in",
    "order_normative",
    "excluded",
    "merged",
    "generated_by",
    "overrides",
]

CONTRACT_FIELDS = ["description", "inputSchema", "name"]


def load(path):
    with io.open(path, encoding="utf-8") as handle:
        return json.load(handle)


def by_name(contract):
    return dict((tool["name"], tool) for tool in contract["result"]["tools"])


def main():
    if len(sys.argv) != 4:
        sys.stderr.write(
            "Usage:\n    python scripts/mcp052_contract_diff.py <before.json> <after.json> <out.json>\n"
            "Exit code 1 (and a non-empty \"problems\" list) when an assertion fails.\n")
        return 1

    before_path, after_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    before = load(before_path)
    after = load(after_path)
    before_tools = before["result"]["tools"]
    after_tools = after["result"]["tools"]
    before_by = by_name(before)
    after_by = by_name(after)

    problems = []
    rows = []

    def check(cid, ok, evidence):
        rows.append({"id": cid, "pass": bool(ok), "evidence": evidence})
        if not ok:
            problems.append("%s: %s" % (cid, evidence))

    # (1) the two revisions are the sizes this batch declares.
    check("before_is_171", len(before_tools) == EXPECTED_PORTS,
          "before entries = %d (expected %d)" % (len(before_tools), EXPECTED_PORTS))
    check("after_is_173", len(after_tools) == EXPECTED_AFTER,
          "after entries = %d (expected %d = %d ported + %d added)"
          % (len(after_tools), EXPECTED_AFTER, EXPECTED_PORTS, len(ADDED)))

    # (2) the name sets differ by exactly the two added names.
    before_names = set(before_by)
    after_names = set(after_by)
    removed = sorted(before_names - after_names)
    added = sorted(after_names - before_names)
    check("no_ported_tool_removed", removed == [], "removed names = %s" % removed)
    check("difference_is_exactly_the_added_names", added == sorted(ADDED),
          "added names = %s (expected %s)" % (added, sorted(ADDED)))

    # (3) every ported entry is deep-equal.
    moved = []
    for name in sorted(before_names & after_names):
        if before_by[name] != after_by[name]:
            moved.append(name)
    check("ported_entries_are_byte_identical", moved == [],
          "ported entries that changed = %s (of %d compared)" % (moved, len(before_names & after_names)))
    check("ported_entry_count", len(before_names & after_names) == EXPECTED_PORTS,
          "ported entries present in both = %d" % len(before_names & after_names))

    # (4) the added names are `_meta.added_tools`, in order, and the tail of the
    # list - i.e. the append really happens after the rename + override pass.
    meta = after.get("_meta", {})
    meta_added = meta.get("added_tools", [])
    check("meta_added_tools_is_the_declared_pair", meta_added == ADDED,
          "_meta.added_tools = %s (expected %s)" % (meta_added, ADDED))
    check("meta_added_count_matches", meta.get("added_count") == len(ADDED),
          "_meta.added_count = %r (expected %d)" % (meta.get("added_count"), len(ADDED)))
    tail = [tool["name"] for tool in after_tools[-len(ADDED):]]
    check("added_entries_are_the_tail", tail == ADDED,
          "last %d entries = %s (expected %s)" % (len(ADDED), tail, ADDED))

    # (5) the added entries are contract entries and nothing else.
    for name in ADDED:
        entry = after_by.get(name)
        if entry is None:
            check("added_entry_" + name, False, "absent from the contract")
            continue
        check("added_entry_fields_" + name, sorted(entry.keys()) == CONTRACT_FIELDS,
              "fields = %s (expected %s)" % (sorted(entry.keys()), CONTRACT_FIELDS))
        check("added_entry_description_" + name,
              isinstance(entry.get("description"), str) and entry["description"].strip() != "",
              "description length = %s" % (len(entry.get("description", "")) if isinstance(entry.get("description"), str) else "n/a"))
        check("added_entry_schema_" + name,
              isinstance(entry.get("inputSchema"), dict) and entry["inputSchema"].get("type") == "object",
              "inputSchema type = %r" % (entry.get("inputSchema", {}).get("type") if isinstance(entry.get("inputSchema"), dict) else None))
        check("added_entry_has_no_old_name_" + name, "old_name" not in entry,
              "an added entry must not carry an old-contract field")
        check("added_entry_is_absent_before_" + name, name not in before_by,
              "the before revision already had %s" % name)

    # (6) `_meta` moved only in the fields this batch declares.
    before_meta = before.get("_meta", {})
    check("meta_count_moved", before_meta.get("count") == EXPECTED_PORTS and meta.get("count") == EXPECTED_AFTER,
          "_meta.count = %r -> %r" % (before_meta.get("count"), meta.get("count")))
    check("meta_generator_version_moved",
          before_meta.get("generator_version") == BEFORE_VERSION and meta.get("generator_version") == AFTER_VERSION,
          "_meta.generator_version = %r -> %r" % (before_meta.get("generator_version"), meta.get("generator_version")))
    check("meta_added_fields_are_new",
          "added_tools" not in before_meta and "added_count" not in before_meta,
          "the before revision already carried %s"
          % sorted([k for k in ("added_tools", "added_count") if k in before_meta]))
    for key in UNCHANGED_META:
        check("meta_unchanged_" + key, before_meta.get(key) == meta.get(key),
              "_meta.%s: %s" % (key, "equal" if before_meta.get(key) == meta.get(key) else "MOVED"))
    unexpected = sorted(set(meta) - set(before_meta) - {"added_tools", "added_count"})
    check("meta_has_no_unexpected_new_member", unexpected == [],
          "new _meta members = %s (expected none beyond added_tools/added_count)" % unexpected)
    dropped = sorted(set(before_meta) - set(meta))
    check("meta_has_no_dropped_member", dropped == [], "dropped _meta members = %s" % dropped)

    payload = {
        "before": os.path.abspath(before_path),
        "after": os.path.abspath(after_path),
        "checks": rows,
        "problems": problems,
        "added_tools": meta_added,
    }
    directory = os.path.dirname(os.path.abspath(out_path))
    if directory and not os.path.isdir(directory):
        os.makedirs(directory)
    with io.open(out_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

    for row in rows:
        print("[%s] %s :: %s" % ("PASS" if row["pass"] else "FAIL", row["id"], row["evidence"]))
    print("checks = %d, problems = %d; wrote %s" % (len(rows), len(problems), out_path))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
