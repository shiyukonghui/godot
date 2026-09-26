# TASK-074 section C -- item-by-item verification of A/B claims. READ-ONLY.
import json, hashlib, os, collections, re, base64

ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074"
SCRATCH = os.path.join(os.environ.get("TEMP", r"C:\Temp"), "mcp-platformer")
OUT = os.path.join(ROOT, "aggregate")
os.makedirs(OUT, exist_ok=True)
R = {}

def sha256f(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()

def sha256b(b):
    return hashlib.sha256(b).hexdigest()

def load_args(r):
    a = r.get("args")
    if isinstance(a, str):
        try:
            return json.loads(a)
        except Exception:
            return a
    return a

# ---------- V1: conns_user ----------
def show_resp(p):
    d = json.loads(open(p, "rb").read().decode("utf-8", "replace"))
    return d

for tag, p in [("scratch", os.path.join(SCRATCH, "conns_user.response.json")),
               ("raw_M6__012", os.path.join(ROOT, "raw", "M6__012_conns_user", "response.json")),
               ("raw_M7__006", os.path.join(ROOT, "raw", "M7__006_conns_user_after", "response.json"))]:
    if os.path.exists(p):
        b = open(p, "rb").read()
        try:
            d = json.loads(b.decode("utf-8", "replace"))
            txt = json.dumps(d)
            R.setdefault("conns_user", {})[tag] = {
                "bytes": len(b), "sha256": sha256b(b),
                "count": d.get("count") if isinstance(d, dict) else None,
                "keys": sorted(d.keys()) if isinstance(d, dict) else None,
                "raw_head": b[:400].decode("utf-8", "replace"),
            }
            # unwrap JSON-RPC envelope if present
            inner = d
            if isinstance(d, dict) and "result" in d and isinstance(d["result"], dict):
                inner = d["result"]
                R["conns_user"][tag]["inner_count"] = inner.get("count")
                R["conns_user"][tag]["inner_counts"] = inner.get("counts")
                R["conns_user"][tag]["inner_bytes"] = len(json.dumps(inner))
                conns = inner.get("connections") or []
                R["conns_user"][tag]["inner_n_connections"] = len(conns)
                R["conns_user"][tag]["connections"] = [
                    {k: c.get(k) for k in ("source_path", "signal", "target_path", "method", "flags")}
                    for c in conns]
        except Exception as e:
            R.setdefault("conns_user", {})[tag] = {"bytes": len(b), "sha256": sha256b(b), "parse_error": str(e)}

# ---------- V2: per-call list from CALLS.jsonl ----------
cj = os.path.join(ROOT, "CALLS.jsonl")
rows = [json.loads(l) for l in open(cj, encoding="utf-8-sig") if l.strip()]
R["calls_jsonl_lines"] = len(rows)
R["calls_jsonl_keys"] = sorted(rows[0].keys())
R["calls_jsonl_res_hist"] = dict(collections.Counter(str(r.get("result")) for r in rows))
R["calls_jsonl_port_hist"] = dict(collections.Counter(str(r.get("port")) for r in rows))
# find the connect_signal rows
cs = [r for r in rows if "connect_signal" in str(r.get("tool", ""))]
R["connect_signal_rows"] = cs

# ---------- V3: raw /M12__004 read main.tscn exists? ----------
raw = os.path.join(ROOT, "raw")
dirs = sorted(os.listdir(raw)) if os.path.exists(raw) else []
R["raw_dir_count"] = len(dirs)
R["raw_has_M12"] = [d for d in dirs if d.startswith("M12")]
R["raw_has_M4_028"] = [d for d in dirs if d.startswith("M4__028")]
R["raw_has_M13"] = [d for d in dirs if d.startswith("M13")]
R["raw_has_M10"] = [d for d in dirs if d.startswith("M10")]
R["raw_has_M11"] = [d for d in dirs if d.startswith("M11")]
R["raw_prefix_hist"] = dict(collections.Counter(d.split("__")[0] for d in dirs))

# coin script persistence in scratch
for f in ("coin-script-persistence.txt", "main-tscn-script-count.txt", "coin002-block.txt"):
    p = os.path.join(SCRATCH, f)
    if os.path.exists(p):
        R.setdefault("scratch_txt", {})[f] = open(p, encoding="utf-8", errors="replace").read()

# main.tscn on disk now
tscn = os.path.join(SCRATCH, "proj", "scenes", "main.tscn")
if os.path.exists(tscn):
    t = open(tscn, encoding="utf-8", errors="replace").read()
    R["main_tscn"] = {
        "bytes": len(t.encode("utf-8")), "sha256": sha256f(tscn),
        "script_ext_resource_occurrences": t.count("script = ExtResource"),
        "script_ext_unique_ids": dict(collections.Counter(re.findall(r'script = ExtResource\("([^"]+)"\)', t))),
        "coin_blocks_with_script": sorted(re.findall(r'\[node name="(Coin\d+)"[^\]]*\][\s\S]{0,400}?script = ExtResource', t)),
        "coin_blocks_total": len(re.findall(r'\[node name="Coin\d+"', t)),
        "has_anim": t.count('name="Anim"'),
    }
    R["main_tscn"]["coin_blocks_with_script_n"] = len(R["main_tscn"]["coin_blocks_with_script"])

# player.tscn (player + Anim)
pt = os.path.join(SCRATCH, "proj", "scenes", "player.tscn")
if os.path.exists(pt):
    t = open(pt, encoding="utf-8", errors="replace").read()
    R["player_tscn"] = {"bytes": len(t.encode("utf-8")), "sha256": sha256f(pt),
                        "nodes": re.findall(r'\[node name="([^"]+)" type="([^"]+)"', t)}

# ---------- V4: editor trace -> detailed call table ----------
edp = os.path.join(ROOT, "traces", "trace-editor.jsonl")
ed = [json.loads(l) for l in open(edp, encoding="utf-8") if l.strip()]
calls = [r for r in ed if r.get("event") != "capture" and "method" in r]
caps = {r["seq"]: r for r in ed if r.get("event") == "capture"}
# match raw dirs by tool+order
R["editor_tool_hist"] = dict(collections.Counter(r.get("tool") for r in calls if r.get("tool")).most_common())

# non-ok detail
R["editor_non_ok"] = [{"line": None, "seq": r["seq"], "tool": r.get("tool"), "code": r.get("error_code"),
                       "msg": r.get("error_message"), "duration_ms": r.get("duration_ms")}
                      for r in calls if r.get("ok") is not True and r.get("method") == "tools/call"]

# stamps line numbers
with open(edp, encoding="utf-8") as f:
    for i, l in enumerate(f, 1):
        try:
            rr = json.loads(l)
        except Exception:
            continue
        if rr.get("method") == "tools/call":
            for e in R["editor_non_ok"]:
                if e["seq"] == rr.get("seq"):
                    e["line"] = i
            for e in R["editor_non_ok"]:
                pass
# tools/list line
with open(edp, encoding="utf-8") as f:
    for i, l in enumerate(f, 1):
        rr = json.loads(l)
        if rr.get("method") == "tools/list":
            R["editor_tools_list_line"] = i
            R["editor_tools_list_seq"] = rr.get("seq")
            R["editor_tools_list_count"] = rr.get("tools")
            R["editor_tools_list_bytes"] = rr.get("result_bytes")

# dup open_scene by args
osc = collections.Counter()
osc_lines = collections.defaultdict(list)
for i, l in enumerate(open(edp, encoding="utf-8"), 1):
    rr = json.loads(l)
    if rr.get("tool") == "editor_open_scene":
        a = load_args(rr)
        key = json.dumps(a, sort_keys=True)
        osc[key] += 1
        osc_lines[key].append({"line": i, "seq": rr["seq"], "result_bytes": rr.get("result_bytes"),
                               "capture_changed": (caps.get(rr["seq"]) or {}).get("changed"),
                               "capture_px": (caps.get(rr["seq"]) or {}).get("changed_pixels")})
R["open_scene_dup_same_args"] = {k: {"n": v, "calls": osc_lines[k]} for k, v in osc.items() if v > 1}

# save_scene
R["save_scene"] = [{"line": i, "seq": rr["seq"], "args": load_args(rr), "ok": rr.get("ok")}
                   for i, l in enumerate(open(edp, encoding="utf-8"), 1)
                   for rr in [json.loads(l)] if rr.get("tool") == "editor_save_scene"]

# ---------- V5: analyze_mcp_trace.py args-type probe ----------
args_are_str = sum(1 for r in calls if isinstance(r.get("args"), str))
args_are_dict = sum(1 for r in calls if isinstance(r.get("args"), dict))
R["args_str_vs_dict"] = {"str": args_are_str, "dict": args_are_dict}

# ---------- V6: contract ----------
contracts = [r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\tools_list.renamed.json"]
for cp in contracts:
    if os.path.exists(cp):
        d = json.load(open(cp, encoding="utf-8"))
        tools = d["result"]["tools"] if "result" in d else d
        names = [t["name"] for t in tools]
        R["contract"] = {"bytes": os.path.getsize(cp), "sha256": sha256f(cp), "n": len(names)}
        R["contract_ns_hist"] = dict(collections.Counter(n.split("_")[0] for n in names))
        R["contract_has_read_text_file"] = [n for n in names if "text" in n]
        R["contract_read_tools"] = [n for n in names if "read" in n]
        R["contract_name_like"] = {q: [n for n in names if q in n] for q in
                                  ("property_update", "property_batch", "tileset", "keyframe", "instance",
                                   "script", "signal", "capture", "sample", "input", "text_file")}

json.dump(R, open(os.path.join(OUT, "c_verify.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
print(json.dumps({k: R[k] for k in ("conns_user", "editor_non_ok", "contract", "open_scene_dup_same_args",
                                    "args_str_vs_dict", "raw_dir_count") if k in R}, indent=1, ensure_ascii=False)[:6000])
