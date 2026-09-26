import io, os, json, hashlib
base = r'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074'
obs = os.path.join(base, 'observations')
out = io.open(os.path.join(obs, 'checks10.txt'), 'w', encoding='utf-8')

def content_of(p):
    j = json.loads(open(p, encoding='utf-8').read())
    if 'result' in j:
        return j['result']['content'][0]['text']
    return json.dumps(j, ensure_ascii=False)

top = content_of(os.path.join(base, 'tree-main.json'))
out.write('tree-main.json inner-text sha256=%s len=%d\n' % (hashlib.sha256(top.encode()).hexdigest(), len(top)))
for d in ('M2__014_tree_after_assembly', 'M3__030_tree_full', 'M3b__002_tree_before', 'M3b__020_tree_after',
          'M10__003_tree_with_shapes', 'M8__001_game_scene_tree'):
    t = content_of(os.path.join(base, 'raw', d, 'response.json'))
    out.write('%-28s inner-text sha256=%s len=%-6d identical_to_tree_main=%s\n' % (
        d, hashlib.sha256(t.encode()).hexdigest(), len(t), t == top))

# save_scene vs the scene open at that moment
recs = [json.loads(l) for l in io.open(os.path.join(obs, 'traces', 'trace-editor.jsonl'), encoding='utf-8') if l.strip()]
calls = sorted([r for r in recs if r.get('method') == 'tools/call'], key=lambda r: r['seq'])
open_scene = None
out.write('\n=== save_scene path vs last opened scene ===\n')
same = 0
tot = 0
for r in calls:
    if r.get('tool') == 'editor_open_scene':
        open_scene = json.loads(r['args']).get('path')
    elif r.get('tool') == 'editor_save_scene':
        p = json.loads(r['args']).get('path')
        tot += 1
        eq = '[path]' in r['args'] or p == open_scene
        same += 1 if eq else 0
        out.write('  seq=%-4s save=%-28s last_open=%-28s match=%s\n' % (r.get('seq'), p, open_scene, eq))
out.write('  save_scene calls=%d match_last_open=%d\n' % (tot, same))
out.close()
print('ok')
