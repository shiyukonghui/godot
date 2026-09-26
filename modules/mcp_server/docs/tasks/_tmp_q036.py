import io, json, os

docs = r'modules\mcp_server\docs'
raw = json.load(io.open(os.path.join(docs, 'tools_list.renamed.json'), encoding='utf-8'))

def find_tools(o):
    if isinstance(o, dict):
        if 'tools' in o and isinstance(o['tools'], list):
            return o['tools']
        for v in o.values():
            r = find_tools(v)
            if r:
                return r
    return None

contract = find_tools(raw)
by = {t['name']: t for t in contract}
for name in ['editor_open_scene', 'editor_save_scene', 'editor_execute_gdscript', 'editor_get_node_properties',
             'editor_set_node_property', 'editor_get_scene_tree', 'running_game_get_scene_tree',
             'running_game_get_node_properties', 'editor_setup_navigation_region']:
    entry = by.get(name)
    if entry is None:
        print(name, 'MISSING')
        continue
    print('=' * 70)
    print(name, '|', entry['description'])
    print(json.dumps(entry['inputSchema'], ensure_ascii=False))
