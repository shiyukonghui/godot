import json, subprocess, io, sys, os
REPO = r"F:\RustProjects\godot-mcp-pro\code\godot"
CONTRACT = "modules/mcp_server/docs/tools_list.renamed.json"

def show(rev, path):
    out = subprocess.run(["git", "-C", REPO, "show", "%s:%s" % (rev, path)], stdout=subprocess.PIPE)
    return out.stdout

def load_bytes(b):
    if b[:3] == b"\xef\xbb\xbf":
        b = b[3:]
    return json.loads(b.decode("utf-8"))

after = json.loads(io.open(os.path.join(REPO, CONTRACT), "r", encoding="utf-8").read())
a_names = [t["name"] for t in after["result"]["tools"]]
print("HEAD contract:", len(a_names), after["_meta"]["added_count"], after["_meta"]["added_tools"])

for rev in ("213b1791258aa476e6b271e57733a689ad8f3ff9", "c1f3385daf"):
    b = show(rev, CONTRACT)
    if not b:
        print(rev, "MISSING")
        continue
    d = load_bytes(b)
    names = [t["name"] for t in d["result"]["tools"]]
    print("---", rev, len(names), "added=", d["_meta"].get("added_count"), d["_meta"].get("added_tools"))
    print("   added vs HEAD:", sorted(set(a_names) - set(names)))
    print("   removed vs HEAD:", sorted(set(names) - set(a_names)))
    if names == a_names:
        print("   name list identical to HEAD")
    else:
        diff = [(i, x, y) for i, (x, y) in enumerate(zip(names, a_names)) if x != y]
        print("   first position diffs:", diff[:5])
        print("   prefix equal len:", len(names) == len(a_names))

# TASK-053 start revision: find the commit
