import json, os, sys, collections, hashlib
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074"
SCRATCH = os.path.join(os.environ.get("TEMP", r"C:\Temp"), "mcp-platformer")
rows = [json.loads(l) for l in open(os.path.join(ROOT, "CALLS.jsonl"), encoding="utf-8-sig") if l.strip()]

print("=== §A D6: identical editor_open_scene args -> distinct response sha256 ===")
for tool, argmatch in (("editor_open_scene", "main.tscn"), ("editor_open_scene", "player.tscn"),
                       ("editor_open_scene", "enemy.tscn"), ("editor_open_scene", "coin.tscn")):
    sub = [r for r in rows if r.get("tool") == tool and argmatch in json.dumps(r.get("args"))]
    shas = collections.Counter(str(r.get("sha256"))[:16] for r in sub)
    print(" %-20s %-12s n=%d distinct_sha=%d %s" % (tool, argmatch, len(sub), len(shas), dict(shas)))

print()
print("=== §A: same-tool repeated calls with identical args+sha (stable) vs not ===")
same = [r for r in rows if r.get("tool") == "editor_save_scene" and "main.tscn" in json.dumps(r.get("args"))]
print(" editor_save_scene main.tscn n=%d distinct_sha=%d" % (len(same), len(set(str(r.get('sha256')) for r in same))))
same2 = [r for r in rows if r.get("tool") == "editor_get_scene_tree"]
print(" editor_get_scene_tree n=%d distinct_sha=%d bytes=%s" % (len(same2), len(set(str(r.get('sha256')) for r in same2)),
                                                                sorted(set(r.get('bytes') for r in same2))))

print()
print("=== game.err.log (scratch) for D2 ===")
for cand in ("logs", "."):
    d = os.path.join(SCRATCH, cand)
    if not os.path.isdir(d):
        continue
    for f in sorted(os.listdir(d)):
        if "err" in f.lower() or "log" in f.lower():
            p = os.path.join(d, f)
            if os.path.isfile(p):
                t = open(p, encoding="utf-8", errors="replace").read()
                print(" %-50s bytes=%d Area2D=%d Node2D=%d" % (p, len(t), t.count("Area2D"), t.count("Node2D")))
print()
print("=== all files under scratch/logs ===")
ld = os.path.join(SCRATCH, "logs")
if os.path.isdir(ld):
    for f in sorted(os.listdir(ld)):
        p = os.path.join(ld, f)
        print("  %-40s %d" % (f, os.path.getsize(p) if os.path.isfile(p) else -1))
# search whole scratch for the Area2D message
import re
hits = 0
for dp, dn, fn in os.walk(SCRATCH):
    if "shots" in dp:
        continue
    for f in fn:
        if f.endswith((".log", ".txt", ".err")):
            p = os.path.join(dp, f)
            try:
                t = open(p, encoding="utf-8", errors="replace").read()
            except Exception:
                continue
            if "can't be assigned to an object of type" in t:
                n = t.count("can't be assigned to an object of type")
                print("  D2 MESSAGE FOUND:", p, "count", n)
                hits += 1
print("files containing D2 message:", hits)

print()
print("=== §B A1 pixel histogram recomputed ===")
p = os.path.join(ROOT, "traces", "trace-editor.jsonl")
ed = [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()]
caps = [r for r in ed if r.get("event") == "capture"]
ch = [c for c in caps if c.get("changed")]
px = sorted(c.get("changed_pixels", 0) for c in ch)
print("changed_true=%d min=%d p25=%s median=%s p75=%s max=%d le4=%d(%.1f%%) le16=%d(%.1f%%) le64=%d"
      % (len(ch), px[0], px[len(px)//4], px[len(px)//2], px[3*len(px)//4], px[-1],
         sum(1 for x in px if x <= 4), 100.0*sum(1 for x in px if x <= 4)/len(px),
         sum(1 for x in px if x <= 16), 100.0*sum(1 for x in px if x <= 16)/len(px),
         sum(1 for x in px if x <= 64)))
nokseq = set()
for r in ed:
    if r.get("method") == "tools/call" and r.get("ok") is not True:
        nokseq.add(r.get("seq"))
badc = [(c.get("seq"), c.get("changed_pixels")) for c in caps if c.get("seq") in nokseq and c.get("changed")]
print("non-ok calls whose capture says changed:", len(badc), badc)
e32601 = set(r.get("seq") for r in ed if r.get("method") == "tools/call" and r.get("error_code") == -32601)
print("-32601 seqs:", sorted(e32601), "changed:", [(c.get("seq"), c.get("changed_pixels")) for c in caps if c.get("seq") in e32601])
print("capture status:", dict(collections.Counter(c.get("status") for c in caps)))
print("unavailable:", [(c.get("seq"), c.get("tool")) for c in caps if c.get("status") == "unavailable"])
