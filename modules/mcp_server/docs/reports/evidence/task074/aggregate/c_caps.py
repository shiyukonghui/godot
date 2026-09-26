import json, os, sys, collections, hashlib
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074"

def inner(p):
    d = json.loads(open(p, "rb").read().decode("utf-8", "replace"))
    return json.loads(d["result"]["content"][0]["text"])

for d in ("M3__004_add_tilemaplayer", "M3__005_tilemap_info", "M3__007_tilemap_cell", "M3__008_set_tilemap_cell",
          "M3__010_tilemap_info_after", "M3b__013_create_tileset", "M3b__015_attach_tileset",
          "M3b__016_set_cell_with_source0", "M3b__017_tilemap_info_final", "M3__012_add_audio",
          "M3__013_audio_info", "M3b__011_theme_info", "M3b__012_scorelabel_props",
          "M3b__003_ui_batch_fixed", "M3b__005_particle_preset", "M3b__008_parallax_mirror",
          "M2__012_inst_overrides", "M5__008_scene_complexity", "M4__028_anim_autoplay",
          "M7__003_validate_main_cs", "M7__002_validate_after_build"):
    p = os.path.join(ROOT, "raw", d, "response.json")
    if not os.path.exists(p):
        print(d, "MISSING"); continue
    try:
        b = inner(p)
    except Exception as e:
        b = {"__err__": str(e)}
    txt = json.dumps(b, ensure_ascii=False)
    print("=== %-38s bytes=%-6d sha=%s" % (d, os.path.getsize(p), hashlib.sha256(open(p,'rb').read()).hexdigest()[:16]))
    print("   ", txt[:700])
