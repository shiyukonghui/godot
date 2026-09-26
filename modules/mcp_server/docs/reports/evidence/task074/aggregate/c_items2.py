import json, os, re, hashlib, collections
SCRATCH = os.path.join(os.environ.get("TEMP", r"C:\Temp"), "mcp-platformer")
ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074"

print("repo ports-final.txt:", repr(open(os.path.join(ROOT, "ports-final.txt"), encoding="utf-8-sig").read()))
print("scratch ports-final.txt:", repr(open(os.path.join(SCRATCH, "ports-final.txt"), encoding="utf-8-sig").read()))
print("same bytes:", open(os.path.join(ROOT, "ports-final.txt"), "rb").read() == open(os.path.join(SCRATCH, "ports-final.txt"), "rb").read())

def jload(p):
    return json.loads(open(p, "rb").read().decode("utf-8-sig", "replace"))

def walk(n, path=""):
    if isinstance(n, dict):
        yield path, n
        for c in (n.get("children") or []):
            yield from walk(c, path + "/" + str(c.get("name")))

for gp in ("game-scene-tree.json", "game-scene-tree2.json"):
    p = os.path.join(SCRATCH, gp)
    d = jload(p)
    tree = d.get("tree") or d
    nodes = list(walk(tree))
    flds = collections.Counter()
    for _, n in nodes:
        for k in n:
            flds[k] += 1
    print()
    print("===", gp, "bytes", os.path.getsize(p), "sha", hashlib.sha256(open(p, "rb").read()).hexdigest()[:16], "nodes", len(nodes))
    print("   field hist:", dict(flds))
    withscript = [(pth, n.get("script")) for pth, n in nodes if n.get("script")]
    print("   nodes with script:", len(withscript), withscript[:10])
    coin = [(pth, n.get("script")) for pth, n in nodes if re.search(r"Coin\d+$", pth)]
    print("   Coin nodes:", len(coin), "scriptless:", sum(1 for _, s in coin if not s))
    print("   Player subtree:", [pth for pth, _ in nodes if "Player" in pth])
    print("   key nodes:", [(pth, n.get("script")) for pth, n in nodes if re.search(r"/(Main|Player|Enemy\d|Coin1|Coin2)$", pth)])

print()
print("=== editor-side tree dumps: is 'Anim' anywhere / World/Player children? ===")
for d in ("M2__014_tree_after_assembly", "M3b__002_tree_before", "M3b__020_tree_after"):
    p = os.path.join(ROOT, "raw", d, "response.json")
    dd = json.loads(open(p, "rb").read().decode("utf-8", "replace"))
    b = json.loads(dd["result"]["content"][0]["text"])
    txt = json.dumps(b)
    tree = b.get("tree") if isinstance(b, dict) and "tree" in b else b
    nodes = list(walk(tree))
    pl = [(pth, len(n.get("children") or []), n.get("type")) for pth, n in nodes if n.get("name") == "Player"]
    print(d, "| bytes", os.path.getsize(p), "| sha", hashlib.sha256(open(p, "rb").read()).hexdigest()[:16])
    print("   nodes:", len(nodes), "| 'Anim' count:", txt.count("Anim"), "| Player entries:", pl)
    print("   top keys:", sorted(b.keys()) if isinstance(b, dict) else type(b))
    print("   has absolute_path:", '"absolute_path"' in txt, "| sample:", re.findall(r'"absolute_path"\s*:\s*"([^"]{0,150})"', txt)[:1])
