import json, io, os
base = os.path.dirname(os.path.abspath(__file__))
docs = os.path.dirname(base)  # docs/
contract = json.load(io.open(os.path.join(docs, 'tools_list.renamed.json'), encoding='utf-8'))
mapping = json.load(io.open(os.path.join(docs, 'tool-rename-map.json'), encoding='utf-8'))

tools = [
 "editor_bake_navigation_mesh","editor_set_navigation_layers","editor_get_navigation_info",
 "running_game_move_player_to_target",
 "project_create_theme","project_set_theme_color","project_set_theme_constant",
 "project_set_theme_font_size","project_set_theme_stylebox","project_get_theme_info",
 "project_get_export_info","project_list_export_presets","project_get_android_preset_info",
 "os_list_android_devices","os_deploy_to_android_device",
]

def find_tools(o):
    if isinstance(o, dict):
        if 'tools' in o and isinstance(o['tools'], list):
            return o['tools']
        for v in o.values():
            r = find_tools(v)
            if r: return r
    return None
cl = find_tools(contract)
by = {t['name']: t for t in cl}

out = {}
out['contract'] = {t: by.get(t) for t in tools}

mt = mapping['tools']
out['map_type'] = str(type(mt))
if isinstance(mt, list):
    mb = {e.get('new_name'): e for e in mt}
elif isinstance(mt, dict):
    mb = mt
else:
    mb = {}
out['map'] = {t: mb.get(t) for t in tools}
out['map_keys_sample'] = list(mb.keys())[:5]

with io.open(os.path.join(base, '_tmp_dump036.json'), 'w', encoding='utf-8') as f:
    f.write(json.dumps(out, ensure_ascii=False, indent=1))
print('written')
