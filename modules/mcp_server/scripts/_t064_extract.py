import subprocess, os, sys
REPO = r"F:\RustProjects\godot-mcp-pro\code\godot"
T = os.path.join(os.environ["TEMP"], "t064")
os.makedirs(T, exist_ok=True)
PAIR = [("c_before.json", "c1f3385daf"), ("c_after.json", "96c1693d3d")]
for name, rev in PAIR:
    out = subprocess.run(["git", "-C", REPO, "show", "%s:modules/mcp_server/docs/tools_list.renamed.json" % rev],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if out.returncode != 0:
        sys.exit("git show failed: " + out.stderr.decode("utf-8", "replace"))
    path = os.path.join(T, name)
    open(path, "wb").write(out.stdout)
    print("%s <- %s : %d bytes" % (name, rev, len(out.stdout)))
