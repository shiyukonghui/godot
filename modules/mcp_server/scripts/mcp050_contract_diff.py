"""TASK-050 contract diff (pure ASCII source).

Compares two `tools_list.renamed.json` revisions and asserts the *shape* of the
change TASK-050 is allowed to make:

  * exactly one tool changed, `project_validate_script`, and only in
    `description`;
  * the new description is `old + " " + <the appended N-2 sentence>`, i.e.
    append-only: not one character of the original wording may be dropped;
  * the appended text really states the rule N-2 is about (the language this
    build does not contain, the `-32000` refusal, `data.suggestion`, and what
    `valid` means);
  * `_meta` changed only in `generator_version` (1.11.0 -> 1.12.0) and
    `overrides` (23 -> 24), and the one new record is a description append for
    `validate_script`;
  * `map_sha256` did not move (the rename map was not touched).

TASK-043's own diff (`mcp043_contract_diff.py`) is untouched and now compares the
revision pair TASK-043 really proved; this script is the one that pins *this*
batch's contract change. No assertion in either file is relaxed.

Usage:
    python scripts/mcp050_contract_diff.py <before.json> <after.json> <out.json>

Exit code 1 (and a non-empty "problems" list) when the assertion fails.
"""
import io
import json
import os
import sys

AFFECTED = ["project_validate_script"]

# The original wording of `project_validate_script`, verbatim: the append-only
# guard is only meaningful against the exact text that has to survive.
ORIGINAL = u"\u9a8c\u8bc1\u811a\u672c\u8bed\u6cd5"  # "validate script syntax"

BEFORE_VERSION = "1.11.0"
AFTER_VERSION = "1.12.0"

# The facts the appended sentence must carry. They are the N-2 rule itself, so a
# later edit that quietly drops one of them fails here instead of passing as "a
# description moved".
REQUIRED_FRAGMENTS = [
    "valid",
    "module_mono_enabled=no",
    "-32000",
    "data.suggestion",
    "--test",
]


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
    appended = None
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
            old_description = old[key]
            new_description = new[key]
            if not isinstance(old_description, str) or not isinstance(new_description, str):
                problems.append("%s: description is not a string" % name)
                continue
            if name in AFFECTED and old_description != ORIGINAL:
                problems.append("%s: the original description is not the pinned text: %r"
                                % (name, old_description))
            if not new_description.startswith(old_description + " "):
                problems.append("%s: the description is not append-only (original wording lost)" % name)
                continue
            appended = new_description[len(old_description) + 1:]
            for fragment in REQUIRED_FRAGMENTS:
                if fragment not in appended:
                    problems.append("%s: the appended sentence does not mention %r" % (name, fragment))

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

    records_before = meta_before.get("overrides", [])
    records_after = meta_after.get("overrides", [])
    if len(records_after) - len(records_before) != len(AFFECTED):
        problems.append("override records: %d -> %d (expected +%d)"
                        % (len(records_before), len(records_after), len(AFFECTED)))
    fresh = [record for record in records_after
             if record not in records_before]
    if len(fresh) != len(AFFECTED):
        problems.append("%d new override record(s), expected %d" % (len(fresh), len(AFFECTED)))
    for record in fresh:
        if record.get("kind") != "description" or record.get("mode") != "append":
            problems.append("the new override record is not a description append: %s" % record)
        if record.get("old_name") not in ("validate_script",):
            problems.append("the new override record names %r" % record.get("old_name"))
    # The generator's own bookkeeping has to be self-consistent: exactly the 24
    # declared overrides fired, each once.
    fired = sorted((record.get("kind"), record.get("old_name")) for record in records_after)
    if len(set(fired)) != len(fired):
        problems.append("an override fired twice: %s" % fired)

    result = {
        "before": os.path.abspath(sys.argv[1]),
        "after": os.path.abspath(sys.argv[2]),
        "changed_tools": sorted(changed),
        "changed_fields": ["description"],
        "appended_description": appended,
        "meta_diff": meta_diff,
        "overrides_before": len(records_before),
        "overrides_after": len(records_after),
        "required_fragments": REQUIRED_FRAGMENTS,
        "problems": problems,
    }
    with io.open(sys.argv[3], "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

    sys.stdout.write("changed tools = %s\n" % ", ".join(sorted(changed)))
    sys.stdout.write("meta keys moved = %s\n" % ", ".join(sorted(meta_diff)))
    sys.stdout.write("overrides %d -> %d\n" % (len(records_before), len(records_after)))
    if appended is not None:
        sys.stdout.write("appended description bytes = %d\n" % len(appended.encode("utf-8")))
    sys.stdout.write("problems = %d\n" % len(problems))
    for problem in problems:
        sys.stdout.write("  PROBLEM %s\n" % problem)
    if problems:
        sys.exit(1)


if __name__ == "__main__":
    main()