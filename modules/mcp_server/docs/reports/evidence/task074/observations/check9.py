import io, os, json, collections
base = r'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074'
obs = os.path.join(base, 'observations')
out = io.open(os.path.join(obs, 'checks9.txt'), 'w', encoding='utf-8')

# max result bytes on the editor trace
recs = [json.loads(l) for l in io.open(os.path.join(obs, 'traces', 'trace-editor.jsonl'), encoding='utf-8') if l.strip()]
calls = [r for r in recs if r.get('method') == 'tools/call']
big = sorted(calls, key=lambda r: -(r.get('result_bytes') or 0))[:6]
out.write('=== largest editor tool responses ===\n')
for r in big:
    out.write('  seq=%-4s %-34s bytes=%s ok=%s\n' % (r.get('seq'), r.get('tool'), r.get('result_bytes'), r.get('ok')))
out.write('  capture lines total_bytes max: %s\n' % max((r.get('total_bytes') or 0) for r in recs if r.get('event') == 'capture'))
gd = [json.loads(l) for l in io.open(os.path.join(obs, 'traces', 'trace-game.jsonl'), encoding='utf-8') if l.strip()]
gb = sorted([r for r in gd if r.get('method') == 'tools/call'], key=lambda r: -(r.get('result_bytes') or 0))[:3]
out.write('=== largest game tool responses ===\n')
for r in gb:
    out.write('  seq=%-4s %-36s bytes=%s\n' % (r.get('seq'), r.get('tool'), r.get('result_bytes')))

# multi-frame samples (section 0.6 item 11 corroboration)
for f in ('samples-jump.json', 'samples-arc.json'):
    p = os.path.join(base, f)
    out.write('\n=== %s ===\n' % f)
    if not os.path.exists(p):
        out.write('(missing)\n')
        continue
    d = json.loads(io.open(p, encoding='utf-8').read())
    txt = d['result']['content'][0]['text'] if 'result' in d else json.dumps(d)
    o = json.loads(txt)
    out.write('keys=%s\n' % sorted(o.keys()))
    samples = o.get('samples') or []
    out.write('n_samples=%d\n' % len(samples))
    ys, xs = [], []
    for s in samples:
        vals = s.get('values') or {}
        pos = vals.get('position')
        if isinstance(pos, dict):
            xs.append(pos.get('x'))
            ys.append(pos.get('y'))
    out.write('distinct_x=%d distinct_y=%d  x=%s..%s  y=%s..%s\n' % (
        len(set(xs)), len(set(ys)), min(xs) if xs else None, max(xs) if xs else None,
        min(ys) if ys else None, max(ys) if ys else None))
    out.write('first 5 y=%s\n' % ys[:5])
    out.write('summary keys=%s\n' % sorted((o.get('summary') or {}).keys()))
    out.write('summary=%s\n' % json.dumps(o.get('summary'), ensure_ascii=False)[:600])
out.close()
print('ok')
