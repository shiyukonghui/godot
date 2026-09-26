# TASK-074 section C -- aggregator's own recomputation from raw traces. READ-ONLY.
# ASCII only. Outputs JSON/text to the same directory.
import json, hashlib, os, sys, collections, re

ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074"
OUT = os.path.join(ROOT, "aggregate")
os.makedirs(OUT, exist_ok=True)
SCRATCH = os.path.join(os.environ.get("TEMP", r"C:\Temp"), "mcp-platformer")

def sha(b):
    return hashlib.sha256(b).hexdigest()

def load_jsonl(p):
    rows = []
    with open(p, "rb") as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append((i, json.loads(line)))
            except Exception as e:
                rows.append((i, {"__parse_error__": str(e)}))
    return rows

report = {}

# ---------- 1. trace inventory ----------
traces = {
    "editor": os.path.join(ROOT, "traces", "trace-editor.jsonl"),
    "game": os.path.join(ROOT, "traces", "trace-game.jsonl"),
    "game2": os.path.join(ROOT, "traces", "trace-game2.jsonl"),
    "game3": os.path.join(ROOT, "traces", "trace-game3.jsonl"),
    "game4": os.path.join(ROOT, "traces", "trace-game4.jsonl"),
}
inv = {}
for k, p in traces.items():
    b = open(p, "rb").read()
    rows = load_jsonl(p)
    kinds = collections.Counter()
    for ln, r in rows:
        if "__parse_error__" in r:
            kinds["__parse_error__"] += 1
        elif r.get("event") == "trace_opened":
            kinds["trace_opened"] += 1
        elif r.get("event") == "capture":
            kinds["capture"] += 1
        else:
            kinds["call"] += 1
    inv[k] = {
        "path": p, "bytes": len(b), "sha256": sha(b),
        "lines": sum(1 for _ in open(p, "rb")),
        "kinds": dict(kinds),
        "sha256_matches_scratch": None,
    }
    sp = os.path.join(SCRATCH, os.path.basename(p))
    if os.path.exists(sp):
        inv[k]["sha256_matches_scratch"] = (sha(open(sp, "rb").read()) == inv[k]["sha256"])
report["trace_inventory"] = inv
report["trace_sizes_equal_observations"] = {}
obs_tr = os.path.join(ROOT, "observations", "traces")
for k in traces:
    a = inv[k]["sha256"]
    op = os.path.join(obs_tr, os.path.basename(traces[k]))
    report["trace_sizes_equal_observations"][k] = (sha(open(op, "rb").read()) == a) if os.path.exists(op) else None

# ---------- 2. editor calls: details ----------
ed = load_jsonl(traces["editor"])
calls = []      # request rows
caps = {}       # seq -> capture row
opened = []
for ln, r in ed:
    if r.get("event") == "trace_opened":
        opened.append((ln, r))
    elif r.get("event") == "capture":
        caps[r.get("seq")] = (ln, r)
    elif "__parse_error__" in r:
        pass
    else:
        calls.append((ln, r))

report["editor_trace_opened"] = [(ln, {k: v for k, v in r.items() if k in ("event", "pid", "port", "version", "product", "role", "engine")}) for ln, r in opened]

args_types = collections.Counter()
for ln, r in calls:
    a = r.get("args", None)
    args_types[type(a).__name__] += 1
report["editor_args_python_types"] = dict(args_types)

def errcode(r):
    return r.get("error_code")

def ok_of(r):
    return r.get("ok") is True

tool_counts = collections.Counter()
nok = []
big = []
method_counts = collections.Counter()
for ln, r in calls:
    tool = r.get("tool") or r.get("method")
    method_counts[r.get("method")] += 1
    tool_counts[tool] += 1
    if not ok_of(r):
        nok.append((ln, r.get("seq"), tool, errcode(r), (r.get("error_message") or "")[:220]))
    rb = r.get("result_bytes")
    if isinstance(rb, int):
        big.append((rb, ln, r.get("seq"), tool))
big.sort(reverse=True)
report["editor_calls"] = len(calls)
report["editor_method_counts"] = dict(method_counts)
report["editor_non_ok_count"] = len(nok)
report["editor_non_ok_by_code"] = dict(collections.Counter(str(x[3]) for x in nok))
report["editor_non_ok_rows"] = nok
report["editor_top_result_bytes"] = big[:8]
report["editor_result_bytes_sum"] = sum(b[0] for b in big)

# tools/list
for ln, r in calls:
    if r.get("method") == "tools/list":
        report["editor_tools_list"] = {"line": ln, "seq": r.get("seq"), "result_bytes": r.get("result_bytes"),
                                       "tools": r.get("tools")}
report["editor_trace_key_sample"] = {k: v for k, v in calls[0][1].items() if k not in ("args",)}

# ---------- 3. game calls ----------
gsum = {}
for k in ("game", "game2", "game3", "game4"):
    rows = load_jsonl(traces[k])
    cc = [(ln, r) for ln, r in rows if r.get("event") not in ("capture", "trace_opened") and "__parse_error__" not in r]
    gg = [(ln, r) for ln, r in rows if r.get("event") == "capture"]
    nk = [(ln, r.get("seq"), r.get("tool"), errcode(r)) for ln, r in cc if not ok_of(r)]
    tl = [(ln, r) for ln, r in cc if r.get("method") == "tools/list"]
    gsum[k] = {"calls": len(cc), "captures": len(gg), "non_ok": nk,
               "tools_list": [{"line": ln, "result_bytes": r.get("result_bytes"),
                               "tools": r.get("tools")} for ln, r in tl],
               "tool_histogram": dict(collections.Counter(r.get("tool") for ln, r in cc if r.get("tool")))}
report["game"] = gsum

report["TOTAL_calls"] = len(calls) + sum(v["calls"] for v in gsum.values())
report["TOTAL_non_ok"] = len(nok) + sum(len(v["non_ok"]) for v in gsum.values())

# ---------- 4. captures ----------
ch = []
for seq, (ln, r) in caps.items():
    b = r.get("before") or {}
    a = r.get("after") or {}
    ch.append((seq, ln, r.get("changed"), r.get("changed_pixels"), r.get("status"),
               bool(b.get("sha256") != a.get("sha256"))))
ch.sort()
changed_true = [c for c in ch if c[2] is True]
pxs = sorted(c[3] for c in changed_true if isinstance(c[3], int))
def pct(p):
    if not pxs:
        return None
    i = int(round((len(pxs) - 1) * p))
    return pxs[i]
report["capture"] = {
    "total": len(ch), "changed_true": len(changed_true),
    "status_counts": dict(collections.Counter(c[4] for c in ch)),
    "px_min": pxs[0] if pxs else None, "px_max": pxs[-1] if pxs else None,
    "px_p25": pct(.25), "px_median": pct(.5), "px_p75": pct(.75),
    "le4": sum(1 for x in pxs if x <= 4), "le16": sum(1 for x in pxs if x <= 16),
    "le64": sum(1 for x in pxs if x <= 64),
    "seqs_with_capture": len(ch),
    "sha_changed": sum(1 for c in ch if c[5]),
    "unavailable_rows": [{"seq": c[0], "tool": (caps[c[0]][1].get("tool"))} for c in ch if c[4] == "unavailable"],
}

# non-ok seqs whose capture claims changed
nok_seq = set(x[1] for x in nok)
report["capture_nonok_changed"] = [
    {"seq": s, "px": p, "changed": c, "tool": caps[s][1].get("tool")} for s, ln, c, p, st, sh in ch if s in nok_seq
]
# -32601 seqs
m32601 = set(x[1] for x in nok if x[3] == -32601)
report["capture_32601_changed"] = [{"seq": s, "px": p} for s, ln, c, p, st, sh in ch if s in m32601]
report["nonok_32601"] = [(x[0], x[1], x[2], x[4]) for x in nok if x[3] == -32601]

# ---------- 5. tool name histogram / bigrams ----------
seqsorted = sorted(calls, key=lambda t: t[1].get("seq", 0))
seqs = [(r.get("seq"), r.get("tool")) for ln, r in seqsorted]
report["editor_tool_histogram"] = dict(collections.Counter(t for _, t in seqs).most_common())
bg = collections.Counter()
for i in range(len(seqs) - 1):
    bg[(seqs[i][1], seqs[i + 1][1])] += 1
report["editor_bigrams_top"] = [{"pair": "%s -> %s" % k, "n": v} for k, v in bg.most_common(15)]
report["editor_bigrams_repeat_same_tool"] = [{"tool": k[0], "n": v} for k, v in bg.most_common() if k[0] == k[1]]

# open_scene duplicates
os_args = []
for ln, r in seqsorted:
    if r.get("tool") == "editor_open_scene":
        a = r.get("args")
        if isinstance(a, str):
            try: a = json.loads(a)
            except Exception: pass
        os_args.append((r.get("seq"), ln, a, r.get("result_bytes")))
report["editor_open_scene_calls"] = [{"seq": s, "line": ln, "args": a, "result_bytes": rb} for s, ln, a, rb in os_args]

# save_scene calls
ss = []
for ln, r in seqsorted:
    if r.get("tool") == "editor_save_scene":
        a = r.get("args")
        if isinstance(a, str):
            try: a = json.loads(a)
            except Exception: pass
        ss.append((r.get("seq"), ln, a, r.get("result_bytes")))
report["editor_save_scene_calls"] = [{"seq": s, "line": ln, "args": a, "result_bytes": rb} for s, ln, a, rb in ss]

with open(os.path.join(OUT, "c_recompute.json"), "w", encoding="utf-8") as f:
    json.dump(report, f, indent=1, ensure_ascii=False)
print(json.dumps({
    "trace_inventory": report["trace_inventory"],
    "editor_calls": report["editor_calls"],
    "editor_non_ok_count": report["editor_non_ok_count"],
    "editor_non_ok_by_code": report["editor_non_ok_by_code"],
    "editor_args_python_types": report["editor_args_python_types"],
    "game": {k: {"calls": v["calls"], "captures": v["captures"], "non_ok": v["non_ok"], "tools_list": v["tools_list"]} for k, v in report["game"].items()},
    "TOTAL_calls": report["TOTAL_calls"],
    "TOTAL_non_ok": report["TOTAL_non_ok"],
    "capture": report["capture"],
}, indent=1, ensure_ascii=False))
