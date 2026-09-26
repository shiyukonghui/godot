import json, collections
P = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074\traces\trace-editor.jsonl"
ed = [json.loads(l) for l in open(P, encoding="utf-8") if l.strip()]
calls = [r for r in ed if r.get("event") != "capture" and "method" in r]
notool = [r for r in calls if not r.get("tool") and r.get("method") == "tools/call"]
print("calls", len(calls), "tools/call without tool key:", len(notool))
if notool:
    print("sample:", json.dumps({k: v for k, v in notool[0].items()}, indent=1)[:900])
print("dup seqs:", len([s for s, c in collections.Counter(r["seq"] for r in calls).items() if c > 1]))
print("distinct seqs:", len(set(r["seq"] for r in calls)))
print("tools/call with tool:", sum(1 for r in calls if r.get("method") == "tools/call" and r.get("tool")))
print("args type hist:", collections.Counter(type(r.get("args")).__name__ for r in calls))
# the open_scene 'null' key earlier -> rows where tool missing
print("seqs missing tool:", sorted(r["seq"] for r in notool))
