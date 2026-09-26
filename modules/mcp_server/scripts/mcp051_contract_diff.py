"""TASK-051 contract diff (pure ASCII source).

Compares two `tools_list.renamed.json` revisions and asserts the *shape* of the
change TASK-051 is allowed to make:

  * the tool name set is unchanged (171 before and after - the batch adds no
    tool and removes none);
  * exactly the five tools named in AFFECTED moved, and each of them **only in
    `inputSchema`** (`description` may not move at all in this batch);
  * every change is a **pure addition**: flattening both schemas into
    `path -> value` leaves every old member present with the identical value, and
    every new member sits under an allowed prefix for that tool. A re-typed, a
    removed or a rewritten member fails here as loudly as a new one;
  * `_meta` moved only in `generator_version` (1.12.0 -> 1.13.0) and `overrides`
    (24 -> 28), `map_sha256` and `generated_from_sha256` are unchanged, and the
    override records are exactly the five `inputSchema` replacements this batch
    declares (one pre-existing description record of `play_scene` is unchanged).

TASK-050's own diff (`mcp050_contract_diff.py`) and TASK-043's
(`mcp043_contract_diff.py`) are untouched; this script pins *this* batch's
contract change. No assertion anywhere is relaxed.

Usage:
    python scripts/mcp051_contract_diff.py <before.json> <after.json> <out.json>

Exit code 1 (and a non-empty "problems" list) when an assertion fails.
"""
import io
import json
import os
import sys

# tool name -> the only prefixes a *new* member of its schema may live under.
AFFECTED = {
    "editor_add_nodes_batch": ["/properties/resolve_within_batch"],
    "editor_list_signal_connections": ["/properties/scope"],
    "editor_simulate_input_sequence": ["/properties/events/items"],
    "running_game_run_test_scenario": [
        "/properties/steps/items/properties/pressed",
        "/properties/steps/items/properties/strength",
    ],
    "editor_play_scene": [
        "/properties/headless",
        "/properties/extra_args",
    ],
}

# The override *record* each affected tool must carry after the change (the
# rename-map old_name, not the tool name), and the mode it must declare.
EXPECTED_SCHEMA_RECORDS = {
    "batch_add_nodes": "replace",
    "find_signal_connections": "replace",
    "simulate_sequence": "replace",
    "run_test_scenario": "replace",
    "play_scene": "replace",
}

BEFORE_VERSION = "1.12.0"
AFTER_VERSION = "1.13.0"
BEFORE_OVERRIDES = 24
AFTER_OVERRIDES = 28
EXPECTED_TOOLS = 171


def load(path):
    with io.open(path, encoding="utf-8") as handle:
        return json.load(handle)


def by_name(contract):
    return dict((tool["name"], tool) for tool in contract["result"]["tools"])


def flatten(value, path=""):
    """`path -> leaf` for every member of a JSON value, lists included."""
    out = {}
    if isinstance(value, dict):
        for key in value:
            out.update(flatten(value[key], path + "/" + key))
    elif isinstance(value, list):
        if not value:
            out[path] = []
        else:
            for index, item in enumerate(value):
                out.update(flatten(item, "%s[%d]" % (path, index)))
    else:
        out[path] = value
    return out


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    before = load(sys.argv[1])
    after = load(sys.argv[2])
    problems = []

    names_before = sorted(by_name(before))
    names_after = sorted(by_name(after))
    if names_before != names_after:
        problems.append("the set of tool names changed")
    if len(names_after) != EXPECTED_TOOLS:
        problems.append("tool count is %d, expected %d" % (len(names_after), EXPECTED_TOOLS))

    tools_before = by_name(before)
    tools_after = by_name(after)
    changed = []
    for name in names_after:
        if name not in tools_before:
            continue
        old = tools_before[name]
        new = tools_after[name]
        if old == new:
            continue
        changed.append(name)
        if sorted(old) != sorted(new):
            problems.append("%s: the key set moved: %s -> %s" % (name, sorted(old), sorted(new)))
            continue
        for key in sorted(old):
            if old[key] == new[key]:
                continue
            if key != "inputSchema":
                problems.append("%s: field %s changed (only inputSchema may)" % (name, key))
                continue
            old_flat = flatten(old[key])
            new_flat = flatten(new[key])
            for path, value in sorted(old_flat.items()):
                if path not in new_flat:
                    problems.append("%s: member %s disappeared" % (name, path))
                elif new_flat[path] != value:
                    problems.append("%s: member %s changed: %r -> %r"
                                    % (name, path, value, new_flat[path]))
            added = sorted(path for path in new_flat if path not in old_flat)
            if not added:
                problems.append("%s: inputSchema moved but no member was added" % name)
            allowed = AFFECTED.get(name, [])
            for path in added:
                if not any(path.startswith(prefix) for prefix in allowed):
                    problems.append("%s: unexpected new member %s (allowed: %s)"
                                    % (name, path, allowed))

    if sorted(changed) != sorted(AFFECTED):
        problems.append("changed tools = %s, expected exactly %s" % (sorted(changed), sorted(AFFECTED)))

    meta_before = before.get("_meta", {})
    meta_after = after.get("_meta", {})
    meta_diff = {}
    for key in sorted(set(meta_before) | set(meta_after)):
        if meta_before.get(key) != meta_after.get(key):
            meta_diff[key] = {"before": meta_before.get(key), "after": meta_after.get(key)}
    if sorted(meta_diff) != ["generator_version", "overrides"]:
        problems.append("_meta moved in %s, expected only generator_version + overrides" % sorted(meta_diff))
    if meta_before.get("generator_version") != BEFORE_VERSION:
        problems.append("generator_version before is %r, expected %r"
                        % (meta_before.get("generator_version"), BEFORE_VERSION))
    if meta_after.get("generator_version") != AFTER_VERSION:
        problems.append("generator_version after is %r, expected %r"
                        % (meta_after.get("generator_version"), AFTER_VERSION))
    if meta_before.get("map_sha256") != meta_after.get("map_sha256"):
        problems.append("map_sha256 moved although the rename map was not touched")
    if meta_before.get("generated_from_sha256") != meta_after.get("generated_from_sha256"):
        problems.append("generated_from_sha256 moved although the frozen old contract did not")

    records_before = meta_before.get("overrides", [])
    records_after = meta_after.get("overrides", [])
    if len(records_before) != BEFORE_OVERRIDES:
        problems.append("overrides before = %d, expected %d" % (len(records_before), BEFORE_OVERRIDES))
    if len(records_after) != AFTER_OVERRIDES:
        problems.append("overrides after = %d, expected %d" % (len(records_after), AFTER_OVERRIDES))
    fired = sorted((record.get("kind"), record.get("old_name")) for record in records_after)
    if len(set(fired)) != len(fired):
        problems.append("an override fired twice: %s" % fired)

    for record in records_after:
        if record.get("kind") != "inputSchema" or record.get("old_name") not in EXPECTED_SCHEMA_RECORDS:
            continue
        old_name = record.get("old_name")
        if record.get("mode") != EXPECTED_SCHEMA_RECORDS[old_name]:
            problems.append("inputSchema override of %r has mode %r" % (old_name, record.get("mode")))
        if not str(record.get("reason", "")).strip():
            problems.append("inputSchema override of %r carries no reason" % old_name)

    # Only the five declared records may differ between the two revisions; every
    # other record (the 24 of the previous batches, including `play_scene`'s
    # description entry) has to be byte-identical. The *reasons* of the five are
    # compared too, because a rewritten reason is how a replaced member would
    # silently leave the audit trail.
    changed_records = [record for record in records_after if record not in records_before]
    changed_records += [record for record in records_before if record not in records_after]
    changed_old_names = sorted(set(record.get("old_name") for record in changed_records))
    if changed_old_names != sorted(EXPECTED_SCHEMA_RECORDS):
        problems.append("override records moved for %s, expected exactly %s"
                        % (changed_old_names, sorted(EXPECTED_SCHEMA_RECORDS)))
    for record in changed_records:
        if record.get("kind") != "inputSchema":
            problems.append("a %r override record of %r moved"
                            % (record.get("kind"), record.get("old_name")))

    # No description record may have moved at all in this batch.
    desc_before = dict((record.get("old_name"), record) for record in records_before
                       if record.get("kind") == "description")
    desc_after = dict((record.get("old_name"), record) for record in records_after
                      if record.get("kind") == "description")
    if desc_before != desc_after:
        moved = sorted(set(desc_before) ^ set(desc_after)) + \
            sorted(name for name in set(desc_before) & set(desc_after)
                   if desc_before[name] != desc_after[name])
        problems.append("description override record(s) moved: %s" % moved)

    result = {
        "before": os.path.abspath(sys.argv[1]),
        "after": os.path.abspath(sys.argv[2]),
        "changed_tools": sorted(changed),
        "changed_fields": ["inputSchema"],
        "added_members": dict((name, sorted(path for path in flatten(tools_after[name]["inputSchema"])
                                            if path not in flatten(tools_before[name]["inputSchema"])))
                              for name in sorted(AFFECTED)),
        "meta_diff": meta_diff,
        "overrides_before": len(records_before),
        "overrides_after": len(records_after),
        "problems": problems,
    }
    with io.open(sys.argv[3], "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

    sys.stdout.write("changed tools = %s\n" % ", ".join(sorted(changed)))
    for name in sorted(AFFECTED):
        added = result["added_members"][name]
        sys.stdout.write("  %s: +%d member(s)\n" % (name, len(added)))
    sys.stdout.write("meta keys moved = %s\n" % ", ".join(sorted(meta_diff)))
    sys.stdout.write("overrides %d -> %d\n" % (len(records_before), len(records_after)))
    sys.stdout.write("problems = %d\n" % len(problems))
    for problem in problems:
        sys.stdout.write("  PROBLEM %s\n" % problem)
    if problems:
        sys.exit(1)


if __name__ == "__main__":
    main()