# TASK-074 section C -- sha256 of raw evidence for all 11 criteria + defect repros. READ-ONLY.
import json, hashlib, os, re, collections, subprocess, sys

ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074"
SCRATCH = os.path.join(os.environ.get("TEMP", r"C:\Temp"), "mcp-platformer")
OUT = os.path.join(ROOT, "aggregate")
os.makedirs(OUT, exist_ok=True)

def sh(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()

def stat(p):
    if not os.path.exists(p):
        return {"MISSING": p}
    b = open(p, "rb").read()
    try:
        rp = os.path.relpath(p, ROOT)
    except ValueError:
        rp = p
    return {"path": rp, "bytes": len(b), "sha256": hashlib.sha256(b).hexdigest()}

R = {}

# all raw response files, indexed by dir name
raw = os.path.join(ROOT, "raw")
idx = {}
for d in sorted(os.listdir(raw)):
    rp = os.path.join(raw, d, "response.json")
    qp = os.path.join(raw, d, "request.json")
    e = {}
    if os.path.exists(rp):
        e["response"] = stat(rp)
    if os.path.exists(qp):
        e["request"] = stat(qp)
    idx[d] = e
R["raw_index_n"] = len(idx)

def body(p):
    """unwrap JSON-RPC envelope -> inner tool body text"""
    if not os.path.exists(p):
        return None
    try:
        d = json.loads(open(p, "rb").read().decode("utf-8", "replace"))
    except Exception:
        return None
    if isinstance(d, dict) and "result" in d and isinstance(d["result"], dict):
        c = d["result"].get("content")
        if isinstance(c, list) and c and isinstance(c[0], dict) and "text" in c[0]:
            t = c[0]["text"]
            try:
                return json.loads(t)
            except Exception:
                return t
        return d["result"]
    return d

# ---------- criteria evidence table ----------
crit = {
    "C1_scenes_instances": ["M1__001_create_main", "M1__009_create_enemy", "M1__015_create_coin",
                            "M1b__001_create_player_cs", "M2__006_inst_player", "M2__007_inst_enemy1",
                            "M2__008_inst_enemy2", "M2__009_inst_enemy3", "M2__010_inst_coin1",
                            "M2__011_inst_coin2", "M2__012_inst_overrides"],
    "C2_tilemap": ["M3__004_add_tilemaplayer", "M3__005_tilemap_info", "M3__007_tilemap_cell",
                   "M3__008_set_tilemap_cell", "M3__009_set_tilemap_rect", "M3__010_tilemap_info_after",
                   "M3b__013_create_tileset", "M3b__014_set_tileset_dict", "M3b__015_attach_tileset",
                   "M3b__016_set_cell_with_source0", "M3b__017_tilemap_info_final"],
    "C3_animation": ["M4__028_anim_autoplay"],
    "C4_ui_theme": ["M3b__003_ui_batch_fixed", "M3b__010_override_score_theme", "M3b__011_theme_info",
                    "M3b__012_scorelabel_props"],
    "C5_audio": ["M3__012_add_audio", "M3__013_audio_info"],
    "C6_particles_parallax": ["M3b__004_add_particles_fixed", "M3b__005_particle_preset",
                              "M3b__006_particle_gradient", "M3b__008_parallax_mirror",
                              "M3b__009_parallax_scale"],
    "C7_csharp_gdscript": ["M7__001_build_csharp", "M7__002_validate_after_build", "M7__003_validate_main_cs",
                           "M1__012_write_enemy_gd", "M1__013_attach_enemy_gd", "M1__018_write_coin_gd"],
    "C8_save_load": ["M6__016_write_save_json", "M6__017_read_save_json", "M6__018_read_text_save"],
    "C9_batch": ["M5__004_batch100_coins", "M5__005_updates12", "M5__006_readback_coin000",
                 "M5__007_readback_coin011", "M5__008_scene_complexity"],
    "C10_signals": ["M6__007_conn1_pause_setpaused", "M6__008_conn2_coin_score",
                    "M6__009_conn3_anim_finished", "M6__010_conn4_coin2_score",
                    "M6__011_conn5_button_down", "M6__012_conns_user", "M6__013_conns_all",
                    "M7__005_conn6_coin002", "M7__006_conns_user_after"],
    "C11_runtime": ["M8__003_inject_multi_step", "M8__004_samples_position", "M8__006_screen_text_score",
                    "M8__008_test_scenario_move", "M10__004_inject_walk_jump", "M10__005_samples_jump",
                    "M10__008_inject_jump_only", "M10__009_samples_arc", "M11__007_inject_walk_to_coin",
                    "M11__008_score_samples", "M11__009_score_after", "M11__010_signal_emissions",
                    "M13__008_walk_to_coin", "M13__009_score_after_walk", "M13__010_player_pos_after"],
    "D1_batch30": ["M6__002_attach_coin_script_batch30", "M11__002_attach_coin002", "M11__003_save_after_attach",
                   "M12__004_read_main_tscn"],
    "D2_type_mismatch": ["M13__002_coin002_body", "M13__003_coin002_script", "M13__004_coin002_selfconnect",
                         "M13__006_coin002_props", "M11__005_coin002_props"],
    "D4_instance_child_path": ["M4__028_anim_autoplay", "M3__030_tree_after_assembly", "M3b__002_tree_before",
                               "M3b__020_tree_after", "M2__014_tree_after_assembly"],
}
ev = {}
for k, ds in crit.items():
    ev[k] = {}
    for d in ds:
        if d in idx:
            ev[k][d] = idx[d]
        else:
            ev[k][d] = {"MISSING": d}
R["criteria_evidence"] = ev

# ---------- specific body checks ----------
sel = {}
sel["batch30_body_keys"] = None
p = os.path.join(raw, "M6__002_attach_coin_script_batch30", "response.json")
b = body(p)
if isinstance(b, dict):
    sel["batch30_body_keys"] = sorted(b.keys())
    sel["batch30_status"] = b.get("status")
    sel["batch30_attached"] = b.get("attached")
    sel["batch30_count"] = b.get("count")
    sel["batch30_has_readable_field"] = any("readable" in json.dumps(b) for _ in [0])
    sel["batch30_text_has_word_readable"] = "readable" in json.dumps(b)
    nodes = b.get("nodes") or b.get("results") or b.get("updated") or []
    if nodes:
        sel["batch30_node_keys"] = sorted(nodes[0].keys())
        sel["batch30_n_nodes"] = len(nodes)
sel["batch30_file"] = stat(p)
sel["batch30_scratch_file"] = stat(os.path.join(SCRATCH, "attach_coin_batch30.response.json"))

for tag, d, key in [("write_save_json", "M6__016_write_save_json", "C8"),
                    ("read_save_json", "M6__017_read_save_json", "C8"),
                    ("read_text_save", "M6__018_read_text_save", "C8"),
                    ("batch100", "M5__004_batch100_coins", "C9"),
                    ("updates12", "M5__005_updates12", "C9"),
                    ("conns_user_M6", "M6__012_conns_user", "C10"),
                    ("conns_user_M7", "M7__006_conns_user_after", "C10"),
                    ("conn3_anim_finished", "M6__009_conn3_anim_finished", "D4"),
                    ("anim_autoplay", "M4__028_anim_autoplay", "D4"),
                    ("coin002_props_M13", "M13__006_coin002_props", "D2"),
                    ("coin002_signals", "M6__004_coin000_signals", "C10"),
                    ("player_props_initial", "M8__002_player_props_initial", "C7"),
                    ("build_csharp", "M7__001_build_csharp", "C7"),
                    ("samples_jump", "M10__005_samples_jump", "C11"),
                    ("samples_arc", "M10__009_samples_arc", "C11"),
                    ("inject_walk_jump", "M10__004_inject_walk_jump", "C11"),
                    ("score_samples", "M11__008_score_samples", "C11"),
                    ("signal_emissions", "M11__010_signal_emissions", "C11"),
                    ("contact_probe", "M5__006_readback_coin000", "C9")]:
    dd = body(os.path.join(raw, d, "response.json"))
    sel[tag] = {"file": stat(os.path.join(raw, d, "response.json")),
                "request": stat(os.path.join(raw, d, "request.json")),
                "body": dd if not isinstance(dd, (str, type(None))) or isinstance(dd, str) else str(dd)[:400]}
R["selected_bodies"] = sel

# scratch save file re-hash
sp = os.path.join(SCRATCH, "proj", "save", "slot1.json")
if os.path.exists(sp):
    R["save_slot1_disk"] = {"bytes": os.path.getsize(sp), "sha256": sh(sp),
                            "content": open(sp, encoding="utf-8", errors="replace").read()[:400]}

json.dump(R, open(os.path.join(OUT, "c_evidence.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)

# ---------- printable digest ----------
print("RAW dirs:", R["raw_index_n"])
print()
for k, v in ev.items():
    miss = [d for d, e in v.items() if "MISSING" in e]
    hashed = {d: (e.get("response") or {}).get("sha256", "")[:12] for d, e in v.items()}
    print("%-24s n=%d missing=%s" % (k, len(v), miss))
    for d, h in hashed.items():
        print("      %-46s %s" % (d, h))
print()
print("batch30 keys:", sel.get("batch30_body_keys"))
print("batch30 status/attached/count:", sel.get("batch30_status"), sel.get("batch30_attached"), sel.get("batch30_count"))
print("batch30 text has 'readable':", sel.get("batch30_text_has_word_readable"))
print("batch30 filename bytes(evidence):", sel["batch30_file"].get("bytes"), sel["batch30_file"].get("sha256", "")[:16])
print("batch30 filename bytes(scratch) :", sel["batch30_scratch_file"].get("bytes"), sel["batch30_scratch_file"].get("sha256", "")[:16])
print("save_slot1_disk:", R.get("save_slot1_disk"))
