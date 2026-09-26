# Rewrite the five C++ registration literals whose description the TASK-059 D-4
# contract change rewrote, so the wire text is the contract text byte for byte.
#
# TASK-055 wrote the same kind of script for the two C# validate tools; this is
# the TASK-059 analogue for the five `project.godot` side-effect descriptions.
# Gate 1 (`check_contract_subset.ps1`) compares the live `tools/list` with
# `docs/tools_list.renamed.json` verbatim, so a literal left behind is a gate
# failure - and a silent one if the sync were done by hand.
#
# Pure ASCII on purpose: this file is an argument, not a document, and the
# contract text it copies is UTF-8.
import io
import json

ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server"
contract = json.load(io.open(ROOT + r"\docs\tools_list.renamed.json", encoding="utf-8"))
descs = {t["name"]: t["description"] for t in contract["result"]["tools"]}

# (file, tool name). All five are the TASK-059 D-4 entries.
TARGETS = [
    (r"\tools\project_setting_write.cpp", "project_set_setting"),
    (r"\tools\project_autoload_write.cpp", "project_add_autoload"),
    (r"\tools\project_autoload_write.cpp", "project_remove_autoload"),
    (r"\tools\editor_input_simulation.cpp", "editor_add_input_action"),
    (r"\tools\editor_write_scene_editor.cpp", "editor_reload_plugin"),
]

changed = 0
for relative, name in TARGETS:
    path = ROOT + relative
    text = io.open(path, encoding="utf-8").read()
    anchor = 'ToolBuilder builder("%s",' % name
    start = text.index(anchor)
    raw = text.find('String::utf8(R"desc(', start)
    if raw >= 0:
        open_end = raw + len('String::utf8(R"desc(')
        close = text.index(')desc"', open_end)
    else:
        plain = text.index('String::utf8("', start)
        open_end = plain + len('String::utf8("')
        close = text.index('"));', open_end)
    old = text[open_end:close]
    new = descs[name]
    # A raw string literal cannot carry these, and neither can the plain form the
    # input-action literal uses; the contract text is built to avoid them.
    assert '"' not in new, name
    assert "\\" not in new, name
    assert ")desc" not in new, name
    if old == new:
        print("%s (%s): already identical (%d chars)" % (relative, name, len(old)))
        continue
    text = text[:open_end] + new + text[close:]
    io.open(path, "w", encoding="utf-8", newline="").write(text)
    changed += 1
    print("%s (%s): literal replaced (%d -> %d chars)" % (relative, name, len(old), len(new)))

print("mcp059_sync_literals: %d literal(s) rewritten, %d target(s)" % (changed, len(TARGETS)))
