import io, json

raw = json.load(io.open(r'modules\mcp_server\docs\tools_list.renamed.json', encoding='utf-8'))


def find_tools(o):
    if isinstance(o, dict):
        if 'tools' in o and isinstance(o['tools'], list):
            return o['tools']
        for v in o.values():
            r = find_tools(v)
            if r:
                return r
    return None


tools = {t['name']: t for t in find_tools(raw)}
for name in ['editor_simulate_key', 'editor_set_shader_material', 'project_create_shader']:
    e = tools[name]
    print('==', name)
    print(json.dumps(e['inputSchema'], ensure_ascii=False))
