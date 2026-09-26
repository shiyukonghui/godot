import json, os, sys, hashlib, re
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074"
SCRATCH = os.path.join(os.environ.get("TEMP", r"C:\Temp"), "mcp-platformer")

A = os.path.join(ROOT, "raw", "M6__002_attach_coin_script_batch30", "response.json")
B = os.path.join(SCRATCH, "attach_coin_batch30.response.json")
for p in (A, B):
    b = open(p, "rb").read()
    print(p)
    print("  bytes", len(b), "sha", hashlib.sha256(b).hexdigest())
    print("  BOM", b[:3] == b"\xef\xbb\xbf")
print()
ja = json.loads(open(A, "rb").read().decode("utf-8", "replace"))
jb = json.loads(open(B, "rb").read().decode("utf-8-sig", "replace"))
print("A keys", sorted(ja.keys()), "| B keys", sorted(jb.keys()))
ta = ja["result"]["content"][0]["text"]
print("A text bytes", len(ta.encode()), "sha", hashlib.sha256(ta.encode()).hexdigest()[:16])
if "result" in jb:
    tb = jb["result"]["content"][0]["text"]
else:
    tb = json.dumps(jb)
print("B text bytes", len(tb.encode()), "sha", hashlib.sha256(tb.encode()).hexdigest()[:16])
print("texts equal:", ta == tb)
print("B text tail:", repr(tb[-180:]))
print("A text tail:", repr(ta[-180:]))
da = json.loads(ta)
db = json.loads(tb)
print()
print("body equal:", da == db)
print("A top keys", sorted(da.keys()), "B top keys", sorted(db.keys()))
for k in sorted(da.keys()):
    va, vb = da[k], db.get(k, "<MISSING>")
    if isinstance(va, list) and isinstance(vb, list):
        print("  %-20s list len A=%d B=%d entries_equal=%s" % (k, len(va), len(vb), va == vb))
    else:
        print("  %-20s equal=%s" % (k, va == vb))
if "nodes" in da:
    print("  node[0] A:", json.dumps(da["nodes"][0], sort_keys=True))
    print("  node[0] B:", json.dumps(db["nodes"][0], sort_keys=True))
for k in da:
    if isinstance(da[k], list):
        for i, (x, y) in enumerate(zip(da[k], db.get(k) or [])):
            if x != y:
                print("  FIRST DIFF %s[%d]:\n    A=%s\n    B=%s" % (k, i, json.dumps(x, sort_keys=True), json.dumps(y, sort_keys=True)))
                break
print()
print("||| A text len", len(ta), "chars; where do they first differ?")
for i, (c1, c2) in enumerate(zip(ta, tb)):
    if c1 != c2:
        print("  first char diff at", i, repr(ta[i - 40:i + 80]), "|", repr(tb[i - 40:i + 80]))
        break
else:
    print("  common prefix identical; len diff", len(ta) - len(tb))
