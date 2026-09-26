import json, io, sys

path = sys.argv[1]
out = sys.argv[2]
wanted = set(sys.argv[3:])
d = json.load(io.open(path, encoding="utf-8"))
sel = [t for t in d["tools"] if t.get("new_name") in wanted or t.get("old_name") in wanted]
with io.open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write(json.dumps(sel, ensure_ascii=False, indent=1))
print("wrote", len(sel))
