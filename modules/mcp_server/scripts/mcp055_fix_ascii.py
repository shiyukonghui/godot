import io
import re

p = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\scripts\mcp055_csharp_compile_verdict_evidence.ps1"
s = io.open(p, encoding="utf-8").read()
n = s.count("(int64)")
s = s.replace("(int64)", "[int64]")
bad = [(i, s[i]) for i, ch in enumerate(s) if ord(ch) > 127]
for i, ch in bad:
    print("non-ascii at", i, repr(s[max(0, i - 60):i + 30]))
# The one Chinese word that slipped in, spelled out in English.
s = s.replace("TASK-050口径", "the TASK-050 answer")
bad = [(i, s[i]) for i, ch in enumerate(s) if ord(ch) > 127]
print("remaining non-ascii:", len(bad))
assert not bad
io.open(p, "w", encoding="ascii", newline="").write(s)
print("replaced (int64) ->", n)
