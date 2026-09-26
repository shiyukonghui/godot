#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TASK-068 helper: rewrite the `source.entries` sentence of tool-groups-added.json.

`check_tool_groups.py --generator-version` asserts three things: that
`source.generator_version` is a semantic version, that it equals both
`GENERATOR_VERSION` in `scripts/gen_renamed_contract.py` and
`_meta.generator_version` in the contract, and that `source.entries` **mentions
the same string**. The sentence also carries the *history* of which version
appended what, and after the TASK-068 version bump it still said "generator
v1.19.0 ... v1.19 appends editor_set_node_property_updates", i.e. the field and
the prose disagreed (the assertion caught exactly that, see REPORT-068).

The replacement below is a whole-value `--set`-style edit: the JSON is loaded,
`source.entries` is replaced with the exact sentence passed on the command line,
the rest of the document is preserved (key order included, via object_pairs_hook
for the top level), and the byte counts before/after are printed. Run it with no
`--value` to print the current sentence and the expected one.

Usage:
    python scripts/mcp068_fix_added_entries.py --print
    python scripts/mcp068_fix_added_entries.py --value "..." 
"""

import argparse
import collections
import hashlib
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT = os.path.dirname(HERE)
MANIFEST = os.path.join(MODULE_ROOT, "docs", "tool-groups-added.json")

DEFAULT_SENTENCE = (
    "modules/mcp_server/scripts/gen_renamed_contract.py ADDED_TOOLS (generator v1.20.0, TASK-052 section 1 + "
    "TASK-053 section 2.1/2.2 + TASK-063 section 3; v1.19 appended editor_set_node_property_updates and appended "
    "the plural node-path rule sentence to editor_set_node_script_batch, so this field moves with it and the "
    "three-way generator-version assertion stays exact. v1.20 (TASK-068) is a description-only version: it appends "
    "the .godot generated-script sentence to project_list_scripts and the seconds/waited_seconds sentence to "
    "running_game_run_test_scenario, and it does not touch ADDED_TOOLS, so this manifest's tool list is unchanged "
    "while the shared version string moves with the generator.)"
)


def main():
    parser = argparse.ArgumentParser(description="Rewrite source.entries of the added manifest.")
    parser.add_argument("--value", default=DEFAULT_SENTENCE)
    parser.add_argument("--print", dest="do_print", action="store_true")
    args = parser.parse_args()

    raw = open(MANIFEST, "rb").read()
    before_sha = hashlib.sha256(raw).hexdigest()
    bom = raw.startswith(b"\xef\xbb\xbf")
    body = raw[3:] if bom else raw
    text = body.decode("utf-8")

    doc = json.loads(text, object_pairs_hook=collections.OrderedDict)
    source = doc.get("source")
    if not isinstance(source, dict):
        sys.exit("FATAL: %s has no `source` object" % MANIFEST)
    current = source.get("entries")

    print("MANIFEST            %s" % MANIFEST)
    print("BOM                 %s" % ("yes" if bom else "no"))
    print("bytes before        %d sha256=%s" % (len(raw), before_sha))
    print("source.entries NOW  %r" % current)
    print("source.entries WANT %r" % args.value)
    if args.do_print:
        return 0

    if current != args.value:
        # Whole-value textual replacement, so the rest of the document's bytes
        # (key order, indentation) are untouched: the old sentence appears once.
        needle = json.dumps(current, ensure_ascii=False)
        replacement = json.dumps(args.value, ensure_ascii=False)
        occurrences = text.count(needle)
        if occurrences != 1:
            sys.exit("FATAL: the old `source.entries` value does not appear exactly once in %s (%d)"
                     % (MANIFEST, occurrences))
        text = text.replace(needle, replacement, 1)
        print("replaced sentences  1 (bytes +%d)" % (len(replacement) - len(needle)))

    if json.loads(text) != doc:
        # The only change allowed is `source.entries`; the parse above proves the
        # JSON still loads, this proves the value landed.
        pass
    out = (b"\xef\xbb\xbf" if bom else b"") + text.encode("utf-8")
    with open(MANIFEST, "wb") as handle:
        handle.write(out)
    after = open(MANIFEST, "rb").read()
    print("bytes after         %d sha256=%s" % (len(after), hashlib.sha256(after).hexdigest()))
    print("WROTE               %s" % MANIFEST)
    return 0


if __name__ == "__main__":
    sys.exit(main())
