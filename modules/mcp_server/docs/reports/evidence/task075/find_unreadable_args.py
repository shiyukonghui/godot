import io, json

PATH = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074\traces\trace-editor.jsonl"
bad = []
total = 0
for line in io.open(PATH, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    record = json.loads(line)
    if record.get("method") != "tools/call":
        continue
    total += 1
    args = record.get("args")
    ok = False
    if isinstance(args, dict):
        ok = True
    elif isinstance(args, str):
        try:
            ok = isinstance(json.loads(args), dict)
        except ValueError:
            ok = False
    if not ok:
        bad.append((record.get("seq"), record.get("tool"), repr(args)[:120], record.get("ok"), record.get("error_code")))
print("tools/call rows:", total)
print("unreadable:", len(bad))
for row in bad:
    print(row)
