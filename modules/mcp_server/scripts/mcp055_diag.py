import io
p = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\tools\project_read_files.cpp"
lines = io.open(p, encoding="utf-8").read().split("\n")
s = lines[912]
q = 0
for idx, ch in enumerate(s):
    if ch == '"':
        q += 1
        print("quote", q, "at", idx, repr(s[max(0, idx - 50):idx + 50]))
log = io.open(r"C:\Users\wyl\AppData\Local\Temp\mcp_server_build_local.log", encoding="utf-8", errors="replace").read().split("\n")
starts = [i for i, l in enumerate(log) if "build_local START" in l]
print("sections:", starts, "lines:", len(log))
tail = log[starts[-1]:] if starts else log
errs = [l for l in tail if " error C" in l or "error LNK" in l]
print("errors in last section:", len(errs))
for l in errs[:20]:
    print("  ", l[:160])
