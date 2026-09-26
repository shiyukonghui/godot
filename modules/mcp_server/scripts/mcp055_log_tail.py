import io
p = r"C:\Users\wyl\AppData\Local\Temp\mcp_server_build_local.log"
log = io.open(p, encoding="utf-8", errors="replace").read().split("\n")
starts = [i for i, l in enumerate(log) if "build_local START" in l]
tail = log[starts[-1]:]
errs = [l for l in tail if (" error C" in l or "error LNK" in l or "scons: ***" in l or "EXIT_CODE" in l)]
out = io.open(r"C:\Users\wyl\AppData\Local\Temp\mcp055_build_errors.txt", "w", encoding="utf-8")
out.write("section starts at line %d of %d\n" % (starts[-1], len(log)))
for l in errs:
    out.write(l + "\n")
out.close()
print("wrote", len(errs), "lines")
