import io, json, os, hashlib
C = r'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\tools_list.renamed.json'
out = io.open('checks7.txt', 'w', encoding='utf-8')
tools = {t['name']: t for t in json.load(io.open(C, encoding='utf-8'))['result']['tools']}
for n in ('editor_set_node_property', 'editor_set_node_property_batch', 'editor_set_node_property_updates',
          'editor_set_node_script', 'editor_set_node_script_batch', 'project_create_resource',
          'editor_add_nodes_batch', 'editor_add_animation_track', 'editor_set_animation_keyframe',
          'editor_set_tilemap_cell', 'editor_set_tilemap_cells_in_rect', 'project_search_file_contents',
          'project_read_scene_file_content', 'editor_execute_gdscript'):
    t = tools.get(n)
    out.write('=' * 90 + '\n%s\n' % n)
    if t is None:
        out.write('  ABSENT FROM CONTRACT\n')
        continue
    out.write('  desc: %s\n' % t.get('description', '').replace('\n', ' ')[:700])
    s = t.get('inputSchema', {})
    out.write('  required: %s\n' % s.get('required'))
    out.write('  params: %s\n' % sorted((s.get('properties') or {}).keys()))
out.write('\n' + '=' * 90 + '\nEVIDENCE SHA256 (this session)\n')
for d in ('.', 'traces', 'watch'):
    p = d if d != '.' else '.'
    for f in sorted(os.listdir(p)):
        fp = os.path.join(p, f)
        if os.path.isfile(fp) and not f.endswith('.py'):
            b = open(fp, 'rb').read()
            out.write('  %-46s %8d  %s\n' % (f, len(b), hashlib.sha256(b).hexdigest()))
out.close()
print('ok')
