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
out = []
for name in ['editor_get_navigation_info', 'editor_bake_navigation_mesh', 'editor_set_navigation_layers']:
    e = by[name]
    out.append('== ' + name)
    out.append(json.dumps(e['inputSchema'], ensure_ascii=False))
io.open(os.path.join('modules', 'mcp_server', 'docs', 'tasks', '_tmp_q036.out.txt'), 'w', encoding='utf-8').write(
    '\n'.join(out))
print(by['editor_get_navigation_info']['inputSchema'])
