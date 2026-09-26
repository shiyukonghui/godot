"""Dump the declared description/inputSchema override table of the generator.

TASK-069 section 2.2. The five descriptions that TASK-043 appended a sentence to
were switched to `mode: "replace"` by TASK-059 D-4, so a gate script that pins
"the description ends with the TASK-043 sentence" is testing a behaviour that no
longer exists (and that the contract's own `_meta.overrides` says no longer
exists). The expectation has to be DERIVED from the declaration instead of
copied into the script.

The declaration lives in exactly one place: `DESCRIPTION_OVERRIDES` in
`scripts/gen_renamed_contract.py` (the same table the contract is generated
from). This helper imports it and writes, for every description override:

    {"old_name": {"mode": ..., "value": ..., "reason": ...}}

as UTF-8 without BOM. The caller (a pure-ASCII .ps1) reads that file with an
explicit UTF-8 decoder, so the Chinese text never travels through a console code
page.

Usage:
    python scripts/mcp069_override_dump.py --out <file> [--kind description]

Exit 0 when the table was dumped; exit 1 on any import/validation failure.
"""

import argparse
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

MODES = ("append", "replace")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--kind", default="description", choices=("description", "inputSchema"))
    args = parser.parse_args()

    import gen_renamed_contract as gen

    table = gen.DESCRIPTION_OVERRIDES if args.kind == "description" else gen.SCHEMA_OVERRIDES

    out = {}
    for old_name, record in table.items():
        mode = str(record.get("mode", "append"))
        value = record.get("value")
        if mode not in MODES:
            sys.exit("FATAL: %s override of %s has mode %r outside %s"
                     % (args.kind, old_name, mode, list(MODES)))
        if not isinstance(value, str):
            sys.exit("FATAL: %s override of %s carries no string value" % (args.kind, old_name))
        reason = record.get("reason")
        if not isinstance(reason, str) or not reason.strip():
            sys.exit("FATAL: %s override of %s carries no reason" % (args.kind, old_name))
        out[old_name] = {"mode": mode, "value": value, "reason": reason}

    payload = json.dumps({
        "generator_version": gen.GENERATOR_VERSION,
        "kind": args.kind,
        "count": len(out),
        "overrides": out,
    }, ensure_ascii=False, indent=2, sort_keys=True)

    with io.open(args.out, "w", encoding="utf-8", newline="") as handle:
        handle.write(payload)

    print("mcp069_override_dump: generator_version=%s kind=%s count=%d -> %s"
          % (gen.GENERATOR_VERSION, args.kind, len(out), args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
