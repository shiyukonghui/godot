#!/usr/bin/env python3
# =============================================================================
#  mcp053_contract_diff.py -- the structured diff of the TASK-053 contract
#  (173 -> 175 entries) against the revision before it.
#
#  `scripts/mcp052_contract_diff.py` pinned the 171 -> 173 transition of the
#  C tier's first batch, and every assertion in it is about *that* batch (its
#  expected counts, its expected added pair, its `added_entries_are_the_tail`).
#  Rather than weaken a proof of a finished batch, this is the same idea for this
#  batch's transition, and it is stricter in the one place TASK-053 is new: the
#  contract has a **schema override of a ported entry** for the first time in the
#  C tier, so "the ported entries did not move" cannot be a blanket assertion any
#  more. The one entry that is allowed to move is named, the shape of its move is
#  checked field by field, and every other ported entry has to be byte identical.
#
#  Usage:
#    python modules/mcp_server/scripts/mcp053_contract_diff.py <before.json> <after.json> <out.json>
#
#  `before.json` is the contract at the TASK-053 starting revision
#  (`git show <start>:modules/mcp_server/docs/tools_list.renamed.json`) and
#  `after.json` is the regenerated one. Exit code 0 means every check passed;
#  a non-zero exit prints the failing checks and writes them to `out.json`.
# =============================================================================
import json
import sys

THE_OVERRIDDEN_ENTRY = "running_game_get_node_property_samples"
# ... and the name the override tables are keyed by: an override is declared on
# the *map's* `old_name`, so `_meta.overrides` names the frozen 174-entry row
# (`monitor_properties`), never the renamed tool.
THE_OVERRIDDEN_OLD_NAME = "monitor_properties"
THE_NEW_MEMBER = "sample_stride"
# TASK-053's own contribution. This is the one literal the transition *is*: the
# names this batch appended to the `ADDED_TOOLS` table.
EXPECTED_ADDED = ["project_validate_scripts", "editor_set_node_script_batch"]
# TASK-064 D-8: the pair `(173, 175)` used to be pinned as literals. Both numbers
# are properties of the revision pair the caller passes in - `before.json` is the
# contract at the batch's starting revision and `after.json` is the one this
# batch produced - so a tree where a LATER batch legitimately appended another
# entry turned `after_is_175` red with nothing in this batch's own transition
# having changed (measured: TASK-063 appended
# `editor_set_node_property_updates`, making the after side 176). The
# expectation is now *derived*: the after side must be the before side grown by
# exactly the names below, which is a strictly stronger statement than "the
# after side is 175" because it holds for any before revision and still fails if
# the delta is not exactly the declared pair. The literal `171` half of the
# contract formula is asserted in `meta_count_moved_by_the_declared_delta`,
# where the two sides must agree with `171 + added_count` as well.
CONTRACT_PORTED_COUNT = 171


def load(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("Usage:\n  python mcp053_contract_diff.py <before.json> <after.json> <out.json>\n"
                         "Exit code 1 (and a non-empty \"problems\" list) when an assertion fails.\n")
        return 2

    before_path, after_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    before = load(before_path)
    after = load(after_path)

    checks = []

    def check(name, ok, evidence):
        checks.append({"id": name, "pass": bool(ok), "evidence": evidence})

    before_tools = before["result"]["tools"]
    after_tools = after["result"]["tools"]
    before_by_name = {tool["name"]: tool for tool in before_tools}
    after_by_name = {tool["name"]: tool for tool in after_tools}
    before_meta = before["_meta"]
    after_meta = after["_meta"]

    # Derived, not written down: the after side is the before side plus the
    # declared pair of this batch. `EXPECTED_BEFORE_COUNT`/`EXPECTED_AFTER_COUNT`
    # were the literals 173/175 until TASK-064 D-8.
    expected_before_count = len(before_tools)
    expected_after_count = expected_before_count + len(EXPECTED_ADDED)
    check("before_capture_is_the_batch_start", len(before_tools) == expected_before_count,
          "before entries = %d (read from the before capture; no literal - TASK-064 D-8)" % len(before_tools))
    check("after_is_before_plus_the_declared_pair", len(after_tools) == expected_after_count,
          "after entries = %d (expected %d = %d before + %d declared names; the literal 175 is gone - TASK-064 D-8)"
          % (len(after_tools), expected_after_count, expected_before_count, len(EXPECTED_ADDED)))

    removed = sorted(set(before_by_name) - set(after_by_name))
    check("no_entry_removed", not removed, "removed names = %s" % removed)

    # --- the two new entries -------------------------------------------------
    new_names = sorted(set(after_by_name) - set(before_by_name))
    check("difference_is_exactly_the_two_new_names", new_names == sorted(EXPECTED_ADDED),
          "new names = %s (expected %s)" % (new_names, sorted(EXPECTED_ADDED)))
    tail = [tool["name"] for tool in after_tools[len(after_tools) - 2:]]
    check("new_entries_are_the_tail_in_manifest_order", tail == EXPECTED_ADDED,
          "last 2 entries = %s (expected %s)" % (tail, EXPECTED_ADDED))
    for name in EXPECTED_ADDED:
        entry = after_by_name.get(name)
        if entry is None:
            check("new_entry_present_%s" % name, False, "absent from the after contract")
            continue
        check("new_entry_fields_%s" % name, sorted(entry.keys()) == ["description", "inputSchema", "name"],
              "fields = %s" % sorted(entry.keys()))
        check("new_entry_schema_is_an_object_%s" % name, entry["inputSchema"].get("type") == "object",
              "inputSchema.type = %r required = %r" % (entry["inputSchema"].get("type"), entry["inputSchema"].get("required")))
        check("new_entry_absent_before_%s" % name, name not in before_by_name,
              "%s is absent from the before contract: %s" % (name, name not in before_by_name))

    # --- the ported entries: exactly one may move, and only in one way --------
    moved = []
    for name in sorted(set(before_by_name) & set(after_by_name)):
        if json.dumps(before_by_name[name], sort_keys=True, ensure_ascii=False) != \
                json.dumps(after_by_name[name], sort_keys=True, ensure_ascii=False):
            moved.append(name)
    check("only_the_m5_entry_moved", moved == [THE_OVERRIDDEN_ENTRY],
          "ported entries that changed = %s (TASK-053 declares exactly %s)" % (moved, THE_OVERRIDDEN_ENTRY))

    old_entry = before_by_name.get(THE_OVERRIDDEN_ENTRY)
    new_entry = after_by_name.get(THE_OVERRIDDEN_ENTRY)
    if old_entry is None or new_entry is None:
        check("m5_entry_present_in_both", False, "the M-5 entry is missing from one side")
    else:
        check("m5_name_untouched", old_entry["name"] == new_entry["name"], "name = %s" % new_entry["name"])
        check("m5_description_untouched", old_entry["description"] == new_entry["description"],
              "description length %d -> %d" % (len(old_entry["description"]), len(new_entry["description"])))
        old_schema = old_entry["inputSchema"]
        new_schema = new_entry["inputSchema"]
        check("m5_schema_required_untouched", old_schema.get("required") == new_schema.get("required"),
              "required %s -> %s" % (old_schema.get("required"), new_schema.get("required")))
        check("m5_schema_object_members_untouched",
              {key: value for key, value in old_schema.items() if key != "properties"} ==
              {key: value for key, value in new_schema.items() if key != "properties"},
              "non-property members equal")
        old_props = old_schema.get("properties", {})
        new_props = new_schema.get("properties", {})
        added = sorted(set(new_props) - set(old_props))
        dropped = sorted(set(old_props) - set(new_props))
        check("m5_added_property_is_the_stride", added == [THE_NEW_MEMBER],
              "added properties = %s (expected [%s])" % (added, THE_NEW_MEMBER))
        check("m5_dropped_no_property", not dropped, "dropped properties = %s" % dropped)
        changed_props = sorted(name for name in set(old_props) & set(new_props)
                               if json.dumps(old_props[name], sort_keys=True, ensure_ascii=False) !=
                               json.dumps(new_props[name], sort_keys=True, ensure_ascii=False))
        check("m5_existing_properties_byte_identical", not changed_props,
              "properties that moved = %s" % changed_props)

    # --- _meta ---------------------------------------------------------------
    # TASK-064 D-8: was `meta_count_moved_to_175`, whose two literals 173/175
    # were the pre/post counts of this batch. The relation asserted is the same
    # one, expressed against the derived delta, plus the contract formula
    # `count == 171 ported + added_count` that `accept_m1.ps1` and
    # `check_tool_groups.py --completeness` both enforce.
    check("meta_count_moved_by_the_declared_delta",
          before_meta.get("count") == len(before_tools)
          and after_meta.get("count") == len(after_tools)
          and after_meta.get("count") == before_meta.get("count") + len(EXPECTED_ADDED)
          and before_meta.get("count") == CONTRACT_PORTED_COUNT + len(before_meta.get("added_tools", []))
          and after_meta.get("count") == CONTRACT_PORTED_COUNT + len(after_meta.get("added_tools", [])),
          "_meta.count %r -> %r; both sides equal %d ported + their own added_count (derived; the literals 173/175 are gone - TASK-064 D-8)"
          % (before_meta.get("count"), after_meta.get("count"), CONTRACT_PORTED_COUNT))
    check("meta_generator_version_moved", before_meta.get("generator_version") == "1.14.0" and after_meta.get("generator_version") == "1.15.0",
          "_meta.generator_version %r -> %r" % (before_meta.get("generator_version"), after_meta.get("generator_version")))
    check("meta_added_tools_grew_by_the_declared_pair",
          before_meta.get("added_tools") == ["project_build_csharp", "project_write_text_file"] and
          after_meta.get("added_tools") == ["project_build_csharp", "project_write_text_file"] + EXPECTED_ADDED,
          "_meta.added_tools = %s" % after_meta.get("added_tools"))
    check("meta_added_count_matches", after_meta.get("added_count") == len(after_meta.get("added_tools", [])),
          "_meta.added_count = %r, added_tools = %d" % (after_meta.get("added_count"), len(after_meta.get("added_tools", []))))
    for member in ("generated_from", "generated_from_sha256", "map_path", "map_sha256", "tool_count_in",
                   "order_normative", "excluded", "merged", "generated_by"):
        check("meta_unchanged_%s" % member, before_meta.get(member) == after_meta.get(member),
              "_meta.%s: %s" % (member, "equal" if before_meta.get(member) == after_meta.get(member) else "MOVED"))

    old_overrides = {(record["kind"], record["old_name"]) for record in before_meta.get("overrides", [])}
    new_overrides = {(record["kind"], record["old_name"]) for record in after_meta.get("overrides", [])}
    check("overrides_grew_by_the_m5_schema_record",
          new_overrides - old_overrides == {("inputSchema", THE_OVERRIDDEN_OLD_NAME)} and not (old_overrides - new_overrides),
          "new override records = %s; removed = %s (the M-5 schema override is declared on the map's old_name '%s')"
          % (sorted(new_overrides - old_overrides), sorted(old_overrides - new_overrides), THE_OVERRIDDEN_OLD_NAME))
    check("old_overrides_are_still_declared", old_overrides <= new_overrides,
          "%d before, %d after" % (len(old_overrides), len(new_overrides)))

    problems = [entry for entry in checks if not entry["pass"]]
    result = {"checks": checks, "problems": problems, "check_count": len(checks)}
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    for entry in checks:
        print("[%s] %s :: %s" % ("PASS" if entry["pass"] else "FAIL", entry["id"], entry["evidence"]))
    print("checks = %d, problems = %d; wrote %s" % (len(checks), len(problems), out_path))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
