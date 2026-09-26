import json, os, re, hashlib, collections
ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074"
SCRATCH = os.path.join(os.environ.get("TEMP", r"C:\Temp"), "mcp-platformer")

def inner(p):
    d = json.loads(open(p, "rb").read().decode("utf-8", "replace"))
    return json.loads(d["result"]["content"][0]["text"])

print("=== animation keyframe calls (editor trace) ===")
P = os.path.join(ROOT, "traces", "trace-editor.jsonl")
ed = [json.loads(l) for l in open(P, encoding="utf-8") if l.strip()]
kf = []
for r in ed:
    t = r.get("tool") or ""
    if "animation" in t and r.get("method") == "tools/call":
        a = r.get("args")
        a = json.loads(a) if isinstance(a, str) else a
        kf.append({"seq": r["seq"], "tool": t, "ok": r.get("ok"), "args": a})
print("n animation calls:", len(kf))
print(collections.Counter(x["tool"] for x in kf))
for x in kf:
    if x["tool"] in ("editor_create_animation", "editor_add_animation_track"):
        print("  ", x["seq"], x["tool"], json.dumps(x["args"])[:200])
kfonly = [x for x in kf if x["tool"] == "editor_set_animation_keyframe"]
print("keyframe calls:", len(kfonly), "all ok:", all(x["ok"] for x in kfonly))
print("by animation:", collections.Counter(x["args"].get("animation") for x in kfonly))
print("by track:", collections.Counter((x["args"].get("animation"), x["args"].get("track_index") or x["args"].get("track")) for x in kfonly))
print("distinct times:", len(set(str(x["args"].get("time")) for x in kfonly)))
for x in kfonly[:6]:
    print("   seq", x["seq"], json.dumps(x["args"], sort_keys=True))

print()
print("=== game scene tree: script field coverage ===")
for gp in ("game-scene-tree.json", "game-scene-tree2.json"):
    p = os.path.join(SCRATCH, gp)
    if not os.path.exists(p):
        print(gp, "MISSING"); continue
    d = inner(p)
    def walk(n, path=""):
        yield path, n
        for c in (n.get("children") or []):
            yield from walk(c, path + "/" + str(c.get("name")))
    nodes = list(walk(d)) if isinstance(d, dict) else []
    # generic: find any list of nodes
    txt = json.dumps(d)
    print(gp, "bytes", os.path.getsize(p), "sha", hashlib.sha256(open(p,'rb').read()).hexdigest()[:16],
          "| has 'script' field any:", '"script"' in txt, "| nodes", len(nodes))
    flds = collections.Counter()
    for pth, n in nodes:
        if isinstance(n, dict):
            for k in n:
                flds[k] += 1
    print("   field hist:", dict(flds))
    withscript = [pth for pth, n in nodes if isinstance(n, dict) and n.get("script")]
    print("   nodes with non-empty script:", len(withscript), withscript[:8])
    coins = [pth for pth, n in nodes if pth.endswith(tuple("Coin%03d" % i for i in range(30)))]
    print("   coin paths sample:", coins[:3], "n=", len(coins))
    anyscript = [p for p in coins if True]
    print("   Coin nodes present but scriptless:", sum(1 for pth, n in nodes if isinstance(n, dict) and re.search(r"Coin\d+$", pth) and not n.get("script")))
    print("   Player/Enemy/Coin1/Coin2 script entries:",
          [(pth, n.get("script")) for pth, n in nodes if isinstance(n, dict) and re.search(r"/(Player|Enemy\d|Coin\d)$", pth) and n.get("script")][:6])

print()
print("=== tree dumps: does World/Player have children / Anim? ===")
for d in ("M2__014_tree_after_assembly", "M3b__002_tree_before", "M3b__020_tree_after"):
    p = os.path.join(ROOT, "raw", d, "response.json")
    if not os.path.exists(p):
        print(d, "MISSING"); continue
    try:
        b = inner(p)
    except Exception as e:
        print(d, "ERR", e); continue
    txt = json.dumps(b)
    print(d, "| 'Anim' occurrences:", txt.count("Anim"), "| has World/Player node:",
          '"World/Player"' in txt, "| bytes", os.path.getsize(p),
          "| sha", hashlib.sha256(open(p, "rb").read()).hexdigest()[:16])
    # try to find the Player node and its children count
    def find(n, path=""):
        if isinstance(n, dict):
            nm = n.get("name")
            np_ = n.get("path") or path
            if nm == "Player" and (n.get("type") or "") == "CharacterBody2D":
                yield {k: (len(n[k]) if k == "children" else n[k]) for k in n if k != "children"} | {"n_children": len(n.get("children") or [])}
            for c in (n.get("children") or []):
                yield from find(c, np_ + "/" + str(c.get("name")))
        elif isinstance(n, list):
            for c in n:
                yield from find(c, path)
    res = list(find(b))
    print("   Player nodes:", res)

print()
print("=== node counts ===")
for gp in ("game-scene-tree.json", "game-scene-tree2.json"):
    p = os.path.join(SCRATCH, gp)
    if not os.path.exists(p): continue
    d = inner(p)

    def cnt(n):
        if isinstance(n, dict):
            return 1 + sum(cnt(c) for c in (n.get("children") or []))
        if isinstance(n, list):
            return sum(cnt(c) for c in n)
        return 0
    print(gp, "total nodes:", cnt(d))
for d in ("M2__014_tree_after_assembly", "M3b__020_tree_after"):
    p = os.path.join(ROOT, "raw", d, "response.json")
    if not os.path.exists(p): continue
    b = inner(p)

    def cnt2(n):
        if isinstance(n, dict):
            return 1 + sum(cnt2(c) for c in (n.get("children") or []))
        if isinstance(n, list):
            return sum(cnt2(c) for c in n)
        return 0
    print(d, "nodes:", cnt2(b))
    t = json.dumps(b)
    print("   absolute_path sample:", re.findall(r'"absolute_path":"([^"]{0,120})"', t)[:2])
