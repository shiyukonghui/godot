import io
import re

log = io.open(r"C:\Users\wyl\AppData\Local\Temp\mcp055\diag_build.log", encoding="utf-8", errors="replace").read()
hits = [m for m in re.finditer(r"/analyzer:[^ \r\n]+", log)]
print("analyzer refs:", len(hits))
for m in hits[:5]:
    print("  ", m.group()[-140:])
print("Godot.SourceGenerators mentioned:", log.count("Godot.SourceGenerators"))
idx = log.find("BuildResponseFile")
if idx > 0:
    chunk = log[idx:idx + 6000]
    print("response file has analyzer:", "/analyzer" in chunk)
    for m in re.finditer(r"/analyzer:[^ \r\n]+", chunk):
        print("   rsp:", m.group()[-140:])
