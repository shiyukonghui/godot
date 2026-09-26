"""TASK-043 survey helper (pure ASCII source).

Prints, for the tools TASK-043 has to consider, the rename-map `old_name` and
the current `description` of the renamed contract entry. The output is written
to a file (UTF-8, no BOM) so the console code page cannot mangle it.
"""
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.dirname(HERE)

WANT = [
    "project_set_setting",
    "project_add_autoload",
    "project_remove_autoload",
    "editor_add_input_action",
    "editor_reload_plugin",
]


def main():
    with io.open(os.path.join(MODULE, "docs", "tool-rename-map.json"), encoding="utf-8") as handle:
        rename_map = json.load(handle)
    with io.open(os.path.join(MODULE, "docs", "tools_list.renamed.json"), encoding="utf-8") as handle:
        contract = json.load(handle)

    entries = {entry["new_name"]: entry for entry in rename_map["tools"]}
    tools = {tool["name"]: tool for tool in contract["result"]["tools"]}

    lines = []
    for name in WANT:
        entry = entries.get(name)
        tool = tools.get(name)
        lines.append("=" * 72)
        lines.append("new_name: %s" % name)
        if entry is None:
            lines.append("  NOT IN RENAME MAP")
            continue
        lines.append("  old_name: %s" % entry["old_name"])
        lines.append("  channel=%s verb=%s scope=%s mutating=%s" % (
            entry["channel"], entry["verb"], entry["scope"], entry["mutating"]))
        if tool is None:
            lines.append("  NOT IN CONTRACT")
            continue
        lines.append("  description: %s" % tool["description"])
        lines.append("  inputSchema: %s" % json.dumps(tool["inputSchema"], ensure_ascii=False))

    output = os.path.join(
        os.environ.get("TEMP", "."), "mcp043", "survey.txt")
    os.makedirs(os.path.dirname(output), exist_ok=True)
    with io.open(output, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    sys.stdout.write("wrote %s (%d samples)\n" % (output, len(WANT)))


if __name__ == "__main__":
    main()
