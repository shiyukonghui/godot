"""TASK-043 contract diff (pure ASCII source).

Compares two `tools_list.renamed.json` revisions and asserts the *shape* of the
change TASK-043 is allowed to make:

  * exactly the five affected tools changed, and only in `description`;
  * every changed description is `old + " " + <the shared sentence>`;
  * no `inputSchema`, `name` or any other field moved;
  * `_meta` changed only in `generator_version` and `overrides`.

Usage:
    python scripts/mcp043_contract_diff.py <before.json> <after.json> <out.json>

Exit code 1 (and a non-empty "problems" list) when the assertion fails.
"""
import io
import json
import os
import sys

AFFECTED = [
    "editor_add_input_action",
    "editor_reload_plugin",
    "project_add_autoload",
    "project_remove_autoload",
    "project_set_setting",
]

SENTENCE = (
    "When this call saves, it rewrites the entire project.godot with the engine's own "
    "whole-file writer (the engine has no partial-publish API), so every hand-written "
    "comment in that file is lost: the remaining settings are re-emitted verbatim and a "
    "repeated identical call changes no bytes (idempotent), and because the comments "
    "cannot be kept, back the file up yourself before calling if you need them."
)


def load(path):
    with io.open(path, encoding="utf-8") as handle:
        return json.load(handle)


def by_name(contract):
    return dict((tool["name"], tool) for tool in contract["result"]["tools"])


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    before = load(sys.argv[1])
    after = load(sys.argv[2])
    problems = []

    names_before = sorted(by_name(before))
    names_after = sorted(by_name(after))
    if names_before != names_after:
        problems.append("the set of tool names changed: %s -> %s" % (names_before, names_after))

    tools_before = by_name(before)
    tools_after = by_name(after)

    changed = []
    for name in names_after:
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
            if key != "description":
                problems.append("%s: field %s changed (only description may)" % (name, key))
                continue
            if new[key] != old[key] + " " + SENTENCE:
                problems.append("%s: description is not old + ' ' + the shared sentence" % name)

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
    if meta_after.get("generator_version") != "1.11.0":
        problems.append("generator_version is %r" % meta_after.get("generator_version"))
    if meta_before.get("map_sha256") != meta_after.get("map_sha256"):
        problems.append("map_sha256 moved although the rename map was not touched")
    old_meta_overrides = len(meta_before.get("overrides", []))
    new_meta_overrides = len(meta_after.get("overrides", []))
    if new_meta_overrides - old_meta_overrides != len(AFFECTED):
        problems.append("override records: %d -> %d (expected +%d)" % (
            old_meta_overrides, new_meta_overrides, len(AFFECTED)))
    fired = sorted(record["old_name"] for record in meta_after.get("overrides", [])
                   if record["mode"] == "append"
                   and record["old_name"] in ("set_project_setting", "add_autoload", "remove_autoload",
                                              "set_input_action", "reload_plugin"))
    expected_fired = ["add_autoload", "reload_plugin", "remove_autoload", "set_input_action", "set_project_setting"]
    if fired != expected_fired:
        problems.append("the five new append records did not all fire: %s" % fired)

    result = {
        "before": os.path.abspath(sys.argv[1]),
        "after": os.path.abspath(sys.argv[2]),
        "changed_tools": sorted(changed),
        "changed_fields": ["description"],
        "meta_diff": meta_diff,
        "overrides_before": old_meta_overrides,
        "overrides_after": new_meta_overrides,
        "shared_sentence": SENTENCE,
        "problems": problems,
    }
    with io.open(sys.argv[3], "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

    sys.stdout.write("changed tools = %s\n" % ", ".join(sorted(changed)))
    sys.stdout.write("meta keys moved = %s\n" % ", ".join(sorted(meta_diff)))
    sys.stdout.write("overrides %d -> %d\n" % (old_meta_overrides, new_meta_overrides))
    sys.stdout.write("problems = %d\n" % len(problems))
    for problem in problems:
        sys.stdout.write("  PROBLEM %s\n" % problem)
    if problems:
        sys.exit(1)


if __name__ == "__main__":
    main()