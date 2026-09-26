# Rewrite the two C++ registration literals from the generated contract, so the
# wire text is the contract text byte for byte (TASK-055).
import io, json, sys

ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server"
contract = json.load(io.open(ROOT + r"\docs\tools_list.renamed.json", encoding="utf-8"))
descs = {t["name"]: t["description"] for t in contract["result"]["tools"]}

targets = [
    (ROOT + r"\tools\project_read_files.cpp", "project_validate_script"),
    (ROOT + r"\tools\project_validate_scripts.cpp", "project_validate_scripts"),
]

for path, name in targets:
    text = io.open(path, encoding="utf-8").read()
    anchor = 'ToolBuilder builder("%s",' % name
    start = text.index(anchor)
    raw = text.find('String::utf8(R"desc(', start)
    if raw >= 0:
        open_end = raw + len('String::utf8(R"desc(')
        close = text.index(')desc"', open_end)
        close_end = close
    else:
        plain = text.index('String::utf8("', start)
        open_end = plain + len('String::utf8("')
        close = text.index('"));', open_end)
        close_end = close
    old = text[open_end:close]
    new = descs[name]
    assert '"' not in new and '\\' not in new, name
    if old == new:
        print("%s: already identical" % name)
        continue
    text = text[:open_end] + new + text[close_end:]
    io.open(path, "w", encoding="utf-8", newline="").write(text)
    print("%s: literal replaced (%d -> %d chars)" % (name, len(old), len(new)))
