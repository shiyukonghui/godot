# -*- coding: utf-8 -*-
"""Emit the registration fragment of tools/running_game_read_scene.cpp.

`description` and `inputSchema` are the *sole authority* of
`docs/tools_list.renamed.json` and must be copied byte for byte; hand-typing
Chinese JSON text is how a contract gate fails for a reason nobody can see.
This script prints the C++ `ToolBuilder` fragment for
`running_game_find_nearby_nodes` so the block in the .cpp file can be
regenerated (and diffed) instead of trusted.

Usage:
    python modules/mcp_server/scripts/gen_running_game_schema.py

Standard library only (Python 3.9). The output is a fragment for the block
between `// BEGIN generated` and `// END generated` of
tools/running_game_read_scene.cpp.
"""

import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
CONTRACT = os.path.join(REPO, "modules", "mcp_server", "docs", "tools_list.renamed.json")
TOOL = "running_game_find_nearby_nodes"


def cpp(text):
    """The body of a C++ double-quoted literal for exactly these characters."""
    out = []
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        else:
            out.append(ch)
    return "".join(out)


def main():
    doc = json.load(io.open(CONTRACT, encoding="utf-8"))
    entries = [t for t in doc["result"]["tools"] if t["name"] == TOOL]
    if len(entries) != 1:
        raise SystemExit("FATAL: expected exactly one contract entry for %s, got %d" % (TOOL, len(entries)))
    entry = entries[0]
    schema = entry["inputSchema"]

    lines = []
    lines.append("\t\t// BEGIN generated")
    lines.append("\t\t// (scripts/gen_running_game_schema.py: contract entry copied byte for byte)")
    lines.append("\t\tToolBuilder builder(\"%s\", String::utf8(\"%s\"));" % (TOOL, cpp(entry["description"])))
    lines.append("")
    lines.append("\t\tDictionary properties;")
    for key in schema["properties"]:
        prop = schema["properties"][key]
        lines.append("\t\t{")
        lines.append("\t\t\tDictionary property;")
        lines.append("\t\t\tproperty[\"type\"] = \"%s\";" % cpp(prop["type"]))
        if "description" in prop:
            lines.append("\t\t\tproperty[\"description\"] = String::utf8(\"%s\");" % cpp(prop["description"]))
        if "additionalProperties" in prop:
            lines.append("\t\t\tproperty[\"additionalProperties\"] = %s;"
                         % ("true" if prop["additionalProperties"] else "false"))
        lines.append("\t\t\tproperties[\"%s\"] = property;" % cpp(key))
        lines.append("\t\t}")
    lines.append("")
    lines.append("\t\tArray required;")
    for name in schema["required"]:
        lines.append("\t\trequired.push_back(\"%s\");" % cpp(name))
    lines.append("")
    lines.append("\t\tDictionary schema;")
    lines.append("\t\tschema[\"type\"] = \"%s\";" % cpp(schema["type"]))
    lines.append("\t\tschema[\"properties\"] = properties;")
    lines.append("\t\tschema[\"required\"] = required;")
    lines.append("")
    lines.append("\t\tbuilder.channel(\"running_game\").verb(\"find\").scope(MCPToolScope::GAME).mutating(false).schema(schema).handler(_tool_find_nearby_nodes);")
    lines.append("\t\tbuilder.register_into(r_registry);")
    lines.append("\t\t// END generated")
    # Written as UTF-8 bytes on purpose: the fragment carries Chinese text and
    # the console code page of the caller has nothing to do with the file it is
    # redirected into (a cp936 stdout would silently mangle every description).
    sys.stdout.buffer.write(("\n".join(lines) + "\n").encode("utf-8"))


if __name__ == "__main__":
    main()