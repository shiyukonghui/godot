#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TASK-068 helper: bump `source.generator_version` in docs/tool-groups-added.json.

The three-way assertion `check_tool_groups.py --generator-version` makes is
`GENERATOR_VERSION` (scripts/gen_renamed_contract.py) ==
`_meta.generator_version` (docs/tools_list.renamed.json) ==
`source.generator_version` (docs/tool-groups-added.json), plus a mention of the
same string inside `source.entries`. This script performs the third leg as a
**byte-level** edit: the old version string is replaced everywhere it appears in
that one file, the file's BOM (if any) and its line endings are preserved, and
the byte count before/after is printed so the edit is auditable.

Usage:
    python scripts/mcp068_bump_added_manifest.py --from 1.19.0 --to 1.20.0 [--note TEXT]
"""

import argparse
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT = os.path.dirname(HERE)
MANIFEST = os.path.join(MODULE_ROOT, "docs", "tool-groups-added.json")

DEFAULT_NOTE = (
    " v1.20 (TASK-068) is a description-only version: it appends the .godot generated-script "
    "sentence to project_list_scripts and the seconds/waited_seconds sentence to "
    "running_game_run_test_scenario, and it does not touch ADDED_TOOLS, so this manifest's tool "
    "list is unchanged while the shared version string moves with the generator."
)


def main():
    parser = argparse.ArgumentParser(description="Bump the added manifest's generator version.")
    parser.add_argument("--from", dest="old", required=True)
    parser.add_argument("--to", dest="new", required=True)
    parser.add_argument("--note", default=DEFAULT_NOTE)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    raw = open(MANIFEST, "rb").read()
    before_sha = hashlib.sha256(raw).hexdigest()
    bom = raw.startswith(b"\xef\xbb\xbf")
    body = raw[3:] if bom else raw
    text = body.decode("utf-8")
    occurrences = text.count('"%s"' % args.old)
    if occurrences > 1:
        sys.exit("FATAL: expected at most one quoted %r in %s, found %d"
                 % (args.old, MANIFEST, occurrences))
    entries_tail = "so this field moves with it and the three-way generator-version assertion stays exact)"
    if entries_tail not in text:
        sys.exit("FATAL: the expected `source.entries` tail is not in %s: %r" % (MANIFEST, entries_tail))
    # `source.entries` is free text and `check_tool_groups.py --generator-version`
    # asserts that the *new* version appears in it. The sentence spells the old
    # one as `v<old>` ("generator v1.19.0"), which is the number a reader sees
    # first, so it moves too - leaving it behind keeps the file telling two
    # stories, and the assertion catches exactly that (measured: the first run of
    # this script moved the quoted field only, and `--added` failed with
    # "source.entries does not even mention 1.20.0").
    old_spelled = "v" + args.old
    new_spelled = "v" + args.new
    spelled = text.count(old_spelled)
    text = text.replace(old_spelled, new_spelled)
    # "v1.19 appends editor_set_node_property_updates ..." is the same version
    # named in the short form, after the `v` was already replaced it reads
    # `v1.20 appends ...`, which is correct only if 1.20 really is the version
    # that appended it. It is not (1.19 did), so the short form moves separately.
    short_old = args.old.split(".")[0] + "." + args.old.split(".")[1]
    short_new = args.new.split(".")[0] + "." + args.new.split(".")[1]
    short_fixed = text.replace("v" + short_old + " appends", "v" + short_old + " appended")
    text = short_fixed
    text = text.replace(entries_tail, entries_tail[:-1] + "." + args.note + ")", 1)
    if occurrences == 1:
        text = text.replace('"%s"' % args.old, '"%s"' % args.new, 1)
    if args.new not in text:
        sys.exit("FATAL: %s still does not mention %s after the edit" % (MANIFEST, args.new))

    print("MANIFEST            %s" % MANIFEST)
    print("BOM                 %s" % ("yes" if bom else "no"))
    print("bytes before        %d sha256=%s" % (len(raw), before_sha))
    print("quoted occurrences  %d of %r" % (occurrences, args.old))
    print("spelled occurrences %d of %r" % (spelled, old_spelled))
    if args.dry_run:
        print("DRY RUN: nothing written")
        return 0
    out = (b"\xef\xbb\xbf" if bom else b"") + text.encode("utf-8")
    with open(MANIFEST, "wb") as handle:
        handle.write(out)
    after = open(MANIFEST, "rb").read()
    print("bytes after         %d sha256=%s" % (len(after), hashlib.sha256(after).hexdigest()))
    print("WROTE               %s" % MANIFEST)
    return 0


if __name__ == "__main__":
    sys.exit(main())
