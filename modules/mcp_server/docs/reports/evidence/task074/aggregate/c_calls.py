import json, os, collections, hashlib
ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074"
CJ = os.path.join(ROOT, "CALLS.jsonl")
rows = [json.loads(l) for l in open(CJ, encoding="utf-8-sig") if l.strip()]
print("CALLS.jsonl rows:", len(rows))
print("keys:", sorted(rows[0].keys()))
print("ports:", dict(collections.Counter(str(r.get("port")) for r in rows)))
print("result hist:", dict(collections.Counter(str(r.get("result")) for r in rows)))
print("tools hist (top):", collections.Counter(r.get("tool") for r in rows).most_common(12))
b = open(CJ, "rb").read()
print("CALLS.jsonl bytes:", len(b), "sha256:", hashlib.sha256(b).hexdigest()[:16], "BOM:", b[:3] == b"\xef\xbb\xbf")

# crypto tools the dev used? any hand-made hashing in scripts?
import re
sg = os.path.join(ROOT, "scripts-run")
tot = 0
for f in sorted(os.listdir(sg)):
    t = open(os.path.join(sg, f), encoding="utf-8", errors="replace").read()
    n = len(re.findall(r"SHA256|Get-FileHash|sha256", t))
    tot += n
    if n:
        print("  %-24s mentions sha256/Get-FileHash: %d" % (f, n))
print("total sha mentions in scripts-run:", tot)

# score samples / emissions
def inner(p):
    d = json.loads(open(p, "rb").read().decode("utf-8", "replace"))
    return json.loads(d["result"]["content"][0]["text"])
for d in ("M11__008_score_samples", "M11__010_signal_emissions", "M11__009_score_after", "M13__009_score_after_walk",
          "M13__011_hud_score1", "M13__007_score_before", "M11__006_score_before"):
    p = os.path.join(ROOT, "raw", d, "response.json")
    if os.path.exists(p):
        print(d, "->", json.dumps(inner(p), ensure_ascii=False)[:400])

# editor output log
p = os.path.join(ROOT, "editor-output-log.txt")
if os.path.exists(p):
    t = open(p, encoding="utf-8", errors="replace").read()
    print()
    print("editor-output-log.txt:", len(t), "bytes; 'Anim' hits:", t.count("Anim"), "'Area2D' hits:", t.count("Area2D"), "'script' hits:", t.lower().count("script"))
    print(t[:1200])
