import io, json

PATH = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074\traces\trace-editor.jsonl"
kinds = {}
truncated = 0
for line in io.open(PATH, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    record = json.loads(line)
    if record.get("method") != "tools/call":
        continue
    args = record.get("args")
    kinds[type(args).__name__] = kinds.get(type(args).__name__, 0) + 1
    if record.get("args_truncated"):
        truncated += 1
print("tools/call arg kinds:", kinds)
print("args_truncated true:", truncated)
