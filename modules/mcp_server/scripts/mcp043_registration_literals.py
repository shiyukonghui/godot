"""TASK-043 registration-literal check (pure ASCII source).

The live `description` of a tool is the C++ literal in its registration block,
not the contract file, so a contract override that is not reflected in that
literal would make gates 1 fail (live tools/list != contract). This script pins
the two sides against each other for the five tools TASK-043 touches, reading
the literal out of the source in both spellings the module uses:

  * hand-written groups:  ToolBuilder builder("name", String::utf8(R"desc(TEXT)desc"))
  * generated spans:      ToolBuilder builder("name", String::utf8("TEXT"))

Exit code 1 when a literal is missing or differs from the contract.
"""
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.dirname(HERE)

CASES = [
    ("project_set_setting", "tools/project_setting_write.cpp"),
    ("project_add_autoload", "tools/project_autoload_write.cpp"),
    ("project_remove_autoload", "tools/project_autoload_write.cpp"),
    ("editor_add_input_action", "tools/editor_input_simulation.cpp"),
    ("editor_reload_plugin", "tools/editor_write_scene_editor.cpp"),
]


def literal_of(text, name):
    """Returns (literal, line, spelling) or (None, -1, '')."""
    raw = re.compile(
        re.escape('ToolBuilder builder("%s", String::utf8(R"desc(' % name) + "(.*?)" + re.escape(')desc"));'),
        re.DOTALL)
    match = raw.search(text)
    if match is not None:
        return match.group(1), text.count("\n", 0, match.start()) + 1, "raw-string"
    plain = re.compile(
        re.escape('ToolBuilder builder("%s", String::utf8("' % name) + '((?:[^"\\\\]|\\\\.)*)"',
        re.DOTALL)
    match = plain.search(text)
    if match is not None:
        return match.group(1), text.count("\n", 0, match.start()) + 1, "escaped-string"
    return None, -1, ""


def main():
    with io.open(os.path.join(MODULE, "docs", "tools_list.renamed.json"), encoding="utf-8") as handle:
        contract = json.load(handle)
    tools = dict((tool["name"], tool) for tool in contract["result"]["tools"])

    sources = {}
    rows = []
    failures = 0
    for name, relative in CASES:
        if relative not in sources:
            with io.open(os.path.join(MODULE, relative), encoding="utf-8") as handle:
                sources[relative] = handle.read()
        expected = tools[name]["description"]
        literal, line, spelling = literal_of(sources[relative], name)
        ok = literal is not None and literal == expected
        if not ok:
            failures += 1
        rows.append({
            "tool": name,
            "file": relative,
            "line": line,
            "spelling": spelling,
            "literal_equals_contract": ok,
            "literal_length": -1 if literal is None else len(literal),
            "contract_length": len(expected),
        })
        print("%-28s %-38s line=%-5d %-16s %s" % (
            name, relative, line, spelling, "EQUAL" if ok else "DIFFERS"))

    output = os.path.join(os.environ.get("TEMP", "."), "mcp043", "registration-literals.json")
    os.makedirs(os.path.dirname(output), exist_ok=True)
    with io.open(output, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps({"cases": rows, "failures": failures,
                                 "contract_sha256_path": "docs/tools_list.renamed.json"},
                                ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    print("failures = %d; wrote %s" % (failures, output))
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()