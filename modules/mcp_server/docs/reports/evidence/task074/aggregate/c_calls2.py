import json, os, collections, hashlib, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074"
rows = [json.loads(l) for l in open(os.path.join(ROOT, "CALLS.jsonl"), encoding="utf-8-sig") if l.strip()]

def code(r):
    res = str(r.get("result"))
    if res == "ok":
        return 0
    return int(res.split("code=")[1])

for port in ("9888", "9889"):
    sub = [r for r in rows if str(r.get("port")) == port]
    print("=" * 70)
    print("port", port, "calls", len(sub), "ok", sum(1 for r in sub if str(r.get("result")) == "ok"),
          "non-ok", sum(1 for r in sub if str(r.get("result")) != "ok"))
    print("  codes:", dict(collections.Counter(code(r) for r in sub if code(r) != 0)))
    print("  non-ok by tool:", dict(collections.Counter(r.get("tool") for r in sub if code(r) != 0)))
    if port == "9889":
        print("  tool hist:", dict(collections.Counter(r.get("tool") for r in sub)))
        print("  --- all game calls ---")
        for r in sub:
            print("   n=%-3s %-42s %-28s %s" % (r.get("n"), r.get("tool"), str(r.get("result"))[:28], str(r.get("note"))[:60]))
        print("  --- game non-ok detail ---")
        for r in sub:
            if code(r) != 0:
                print("   n=%-3s %-40s %s" % (r.get("n"), r.get("tool"), json.dumps(r.get("args"))[:150]))
                print("        resp:", os.path.basename(str(r.get("response_file") or "")), "sha", str(r.get("sha256"))[:16])
print()
print("=== game-side error codes in game traces (independent) ===")
for g in ("game", "game2", "game3", "game4"):
    p = os.path.join(ROOT, "traces", "trace-%s.jsonl" % g)
    ed = [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()]
    bad = [(r.get("seq"), r.get("tool"), r.get("error_code"), r.get("ok")) for r in ed if r.get("method") == "tools/call" and r.get("ok") is not True]
    tot = [r for r in ed if r.get("method") == "tools/call"]
    print(g, "tools/call:", len(tot), "non-ok:", len(bad), bad)
print()
p = os.path.join(ROOT, "editor-output-log.txt")
t = open(p, encoding="utf-8", errors="replace").read()
print("editor-output-log.txt content:")
print(t)