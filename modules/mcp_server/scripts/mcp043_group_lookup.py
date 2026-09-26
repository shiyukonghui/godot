"""TASK-043 helper: which group manifest owns each affected tool (pure ASCII)."""
import glob
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.dirname(HERE)
WANT = [
    "project_set_setting",
    "project_add_autoload",
    "project_remove_autoload",
    "editor_add_input_action",
    "editor_reload_plugin",
]

rows = []
for path in sorted(glob.glob(os.path.join(MODULE, "docs", "tool-groups*.json"))):
    with io.open(path, encoding="utf-8") as handle:
        manifest = json.load(handle)
    groups = manifest.get("groups")
    if not groups:
        continue
    for group in groups:
        for name in WANT:
            if name in group.get("tools", []):
                rows.append((os.path.basename(path), group["name"], group.get("implemented"), name))

output = os.path.join(os.environ.get("TEMP", "."), "mcp043", "groups.txt")
os.makedirs(os.path.dirname(output), exist_ok=True)
lines = ["%s | %s | implemented=%s | %s" % row for row in rows]
with io.open(output, "w", encoding="utf-8", newline="\n") as handle:
    handle.write("\n".join(lines) + "\n")
sys.stdout.write("\n".join(lines) + "\n")
sys.stdout.write("rows=%d\n" % len(rows))
