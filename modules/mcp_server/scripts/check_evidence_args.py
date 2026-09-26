#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TASK-032 D4 impact census (read-only; stdlib only).

The registry refuses every argument name a tool's contract `inputSchema` does not
declare (TASK-032 D4), so two questions have to be answerable before and after
such a change, and they are the reason this script exists:

  1. **Does any tool read a top-level argument its own schema does not declare?**
     Such a tool would be refused when a caller uses the parameter the
     implementation actually wants. Part A answers it by extracting, per
     registered tool, the key literals its handler reads from `p_args` and
     comparing them with the schema of the same tool in
     `docs/tools_list.renamed.json`. (TASK-032's answer: none - the only literal
     that appears nowhere in the contract is `physical_keycode`, which is read
     from an `InputEvent` *dictionary*, not from the tool's arguments.)

  2. **Do the evidence scripts pass a name their tool does not declare?** Those
     are the scripts the new rule breaks, and they were relying on the old
     silent-ignore behaviour. Part B scans `scripts/*.ps1` for
     `-Tool '<name>' ... -Arguments @{ ... }` and compares the *top-level*
     hashtable keys with that tool's schema.

Usage (no arguments, no side effects):

    python scripts/check_evidence_args.py

Exit code is 0 whether or not candidates were found: this is a **census**, not a
gate. A CANDIDATE line means "a human has to look at this site" - two classes are
known to be benign and are reported as such:

  * a `$variable` used as a *key name* (`@{ $case.key = ... }`) is read as the
    literal last path segment by this scanner;
  * keys of a hashtable that is only *nested* inside a top-level value (a
    `steps = @(@{ type = ... })` member) are skipped by the depth tracking, but a
    computed-key case can still shift that tracking.

Part A deliberately reports a *registered* tool with no found registration block
as MISSING, so the census cannot silently cover nothing when a group is added.
"""

import io
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT = os.path.dirname(HERE)
TOOLS_DIR = os.path.join(MODULE_ROOT, "tools")
SCRIPTS_DIR = os.path.join(MODULE_ROOT, "scripts")
CONTRACT = os.path.join(MODULE_ROOT, "docs", "tools_list.renamed.json")
MANIFESTS = ["tool-groups.json", "tool-groups-b2.json", "tool-groups-b3.json",
             "tool-groups-b4.json", "tool-groups-b5.json", "tool-groups-added.json"]

READERS = ("require_string", "require_int", "optional_string", "optional_int",
           "optional_bool", "_optional_string_array", "_require_node_path",
           "require_node_path")
KEY_CALL = re.compile(r'(?:' + "|".join(READERS) + r')\(\s*p_args\s*,\s*"([^"]+)"')
ANY_KEY_CALL = re.compile(r'(?:' + "|".join(READERS) + r')\(\s*([A-Za-z_][\w.\[\]]*)\s*,\s*"([^"]+)"')
HANDLER = re.compile(r'\.(?:pending_handler|handler)\(\s*([A-Za-z_][\w]*)\s*\)')
BUILDER = re.compile(r'ToolBuilder\s+builder\(\s*"([^"]+)"')
FUNC = re.compile(r'^(?:static\s+)?(?:Variant|MCPDeferred::Task\s*\*)\s+([A-Za-z_][\w]*)\s*\(', re.M)
TOOL_ARG = re.compile(r"-Tool\s+'([a-z0-9_]+)'")
ARGS_LITERAL = re.compile(r"-Arguments\s*@\{")


def read_text(path):
    with io.open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def function_bodies(text):
    bodies = {}
    for match in FUNC.finditer(text):
        brace = text.find("{", match.end())
        if brace < 0:
            continue
        depth = 0
        i = brace
        while i < len(text):
            c = text[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        bodies[match.group(1)] = text[brace:i + 1]
    return bodies


def top_level_keys(text, brace_index):
    """Keys of the hashtable whose '{' sits at `brace_index` (depth 1 only)."""
    depth = 0
    i = brace_index
    while i < len(text):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = text[brace_index + 1:i]
    keys = []
    d = 0
    j = 0
    while j < len(body):
        c = body[j]
        if c in "{@":
            d += 1
            j += 1
            continue
        if c == "}":
            d -= 1
            j += 1
            continue
        if d == 0:
            m = re.match(r"\s*([A-Za-z_][\w]*)\s*=", body[j:])
            if m:
                keys.append(m.group(1))
                j += m.end()
                continue
            m = re.match(r"\s*(\$[A-Za-z_][\w]*)\s*=", body[j:])
            if m:
                keys.append(m.group(1))
                j += m.end()
                continue
        if c in "'\"":
            quote = c
            j += 1
            while j < len(body) and body[j] != quote:
                j += 1
        j += 1
    return keys


def contract_schemas():
    contract = json.load(io.open(CONTRACT, encoding="utf-8"))
    return {tool["name"]: set(tool["inputSchema"].get("properties", {}).keys())
            for tool in contract["result"]["tools"]}


def implemented_tools():
    names = set()
    for manifest in MANIFESTS:
        path = os.path.join(MODULE_ROOT, "docs", manifest)
        data = json.load(io.open(path, encoding="utf-8"))
        for group in data["groups"]:
            if group.get("implemented") is True:
                names.update(group["tools"])
    return names


def part_a(schemas):
    print("=" * 78)
    print("PART A - tool handlers vs their own contract schema")
    print("=" * 78)
    registered = {}
    for name in sorted(f for f in os.listdir(TOOLS_DIR) if f.endswith(".cpp")):
        text = read_text(os.path.join(TOOLS_DIR, name))
        bodies = function_bodies(text)
        starts = [m.start() for m in BUILDER.finditer(text)]
        for index, start in enumerate(starts):
            end = starts[index + 1] if index + 1 < len(starts) else len(text)
            block = text[start:end]
            tool = BUILDER.search(block).group(1)
            handler = HANDLER.search(block)
            if handler is None:
                continue
            registered[tool] = (name, handler.group(1),
                                set(KEY_CALL.findall(bodies.get(handler.group(1), ""))))

    implemented = implemented_tools()
    problems = 0
    for tool in sorted(schemas):
        if tool not in registered:
            if tool in implemented:
                print("MISSING     %-52s implemented but no registration block found" % tool)
                problems += 1
            continue
        source, handler, keys = registered[tool]
        extra = sorted(keys - schemas[tool])
        if extra:
            print("PROBLEM     %-52s %s:%s reads %s ; schema=%s"
                  % (tool, source, handler, extra, sorted(schemas[tool])))
            problems += 1
    print("contract tools            : %d" % len(schemas))
    print("manifest implemented=true : %d" % len(implemented))
    print("registration blocks found : %d" % len(registered))
    print("PROBLEM/MISSING lines     : %d" % problems)

    # The census of *every* key literal read anywhere, next to the receivers it is
    # read from: the one literal that no tool declares is expected to be an engine
    # property name read out of an event dictionary, not a tool argument.
    receivers = defaultdict(set)
    for name in sorted(f for f in os.listdir(TOOLS_DIR) if f.endswith(".cpp")):
        for receiver, key in ANY_KEY_CALL.findall(read_text(os.path.join(TOOLS_DIR, name))):
            receivers[receiver].add(key)
    all_keys = set()
    for keys in receivers.values():
        all_keys.update(keys)
    undeclared = sorted(all_keys - set().union(*schemas.values()))
    print("distinct key literals read anywhere: %d" % len(all_keys))
    for key in undeclared:
        owners = sorted(receiver for receiver, keys in receivers.items() if key in keys)
        print("UNDECLARED  %-28s read from receiver(s) %s" % (key, owners))
    return problems


def part_b(schemas):
    print("=" * 78)
    print("PART B - evidence scripts vs the schema of the tool they call")
    print("=" * 78)
    sites = 0
    candidates = []
    for script in sorted(f for f in os.listdir(SCRIPTS_DIR) if f.endswith(".ps1")):
        path = os.path.join(SCRIPTS_DIR, script)
        text = read_text(path)
        for match in TOOL_ARG.finditer(text):
            tool = match.group(1)
            args = ARGS_LITERAL.search(text, match.end())
            if args is None or args.start() - match.end() > 400:
                continue
            sites += 1
            if tool not in schemas:
                candidates.append((script, tool, ["<tool not in the contract>"]))
                continue
            keys = top_level_keys(text, args.end() - 1)
            extra = sorted(key for key in keys if not key.startswith("$") and key not in schemas[tool])
            if extra:
                candidates.append((script, tool, extra))
    print("-Tool/-Arguments literal call sites: %d" % sites)
    print("CANDIDATE sites                   : %d" % len(candidates))
    for script, tool, extra in candidates:
        print("CANDIDATE   %-46s %-44s %s" % (script, tool, extra))
    if not candidates:
        print("(no evidence script passes a name its tool does not declare)")
    return len(candidates)


def main():
    schemas = contract_schemas()
    problems = part_a(schemas)
    candidates = part_b(schemas)
    print("=" * 78)
    print("census: part A PROBLEM/MISSING=%d, part B CANDIDATE=%d "
          "(a CANDIDATE needs a human: computed key names are read literally here)"
          % (problems, candidates))
    return 0


if __name__ == "__main__":
    sys.exit(main())
