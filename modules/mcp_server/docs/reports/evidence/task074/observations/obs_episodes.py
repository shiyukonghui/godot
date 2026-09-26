#!/usr/bin/env python
# TASK-074 section B observer -- episode dumps + noise quantification. ASCII only.
from __future__ import annotations
import collections, io, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
TRACES = os.path.join(HERE, 'traces')
CONTRACT = r'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\tools_list.renamed.json'
OUT = io.open(os.path.join(HERE, 'episodes.txt'), 'w', encoding='utf-8')

def w(*p):
    OUT.write(' '.join(str(x) for x in p) + '\n')

def load(name):
    recs = []
    for n, line in enumerate(io.open(os.path.join(TRACES, name), 'r', encoding='utf-8'), start=1):
        line = line.strip()
        if not line:
            continue
        r = json.loads(line)
        r['__line'] = n
        recs.append(r)
    return recs

recs = load('trace-editor.jsonl')
calls = {r['seq']: r for r in recs if r.get('method') == 'tools/call'}
caps = {r['seq']: r for r in recs if r.get('event') == 'capture'}

def show(seqs, title):
    w('=' * 100)
    w('EPISODE: %s' % title)
    w('=' * 100)
    for s in seqs:
        c = calls.get(s)
        if c:
            w('  seq=%-4s line=%-4s conn=%-4s tool=%-33s ok=%-5s code=%-7s dur=%sms' % (
                c['seq'], c['__line'], c['connection'], c['tool'], c['ok'], c['error_code'], c['duration_ms']))
            w('        args=%s' % c.get('args'))
            if not c.get('ok'):
                w('        ERROR=%s' % c.get('error_message'))
        cap = caps.get(s)
        if cap:
            w('        CAPTURE status=%s changed=%s px=%s ratio=%s before=%s after=%s reason=%s' % (
                cap.get('status'), cap.get('changed'), cap.get('changed_pixels'), cap.get('changed_pixel_ratio'),
                (cap.get('before') or {}).get('sha256', '')[:12], (cap.get('after') or {}).get('sha256', '')[:12],
                cap.get('reason')))
    w('')

show([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 22, 23, 24, 25], 'C# script creation (the -32602 dedicated-tool hint, then the -32001)')
show([26, 27, 28, 29, 30], "editor_get_node_properties on ['script'] (first pair)")
show([51, 52, 53, 54, 55, 91, 92, 97, 98, 99, 100], 'TileMapLayer: two tools, four different failures')
show([61, 62, 63, 72, 73, 78, 79, 80, 82, 83, 84, 85, 86, 88, 89, 90, 93, 102], 'particles / theme / batch-property naming')
show([124, 125, 126, 127, 128, 129, 130, 131, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148], 'batch + signal block')
show([149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160], 'save/load sha round trip (two -32601 on the reader name)')
show([165, 166, 168, 170, 171, 173, 174, 175, 176, 179, 180, 187, 188, 189, 193, 195, 196, 197, 198, 199], 'Coin002 script persistence + final pass')

# ------------------------------------------------------ capture noise -------
w('=' * 100)
w('CAPTURE NOISE QUANTIFICATION (changed=true)')
w('=' * 100)
tr = [r for r in recs if r.get('event') == 'capture' and r.get('changed') is True]
px = sorted((r.get('changed_pixels') or 0) for r in tr)
w('  changed=true captures: %d of %d' % (len(tr), sum(1 for r in recs if r.get('event') == 'capture')))
if px:
    import statistics
    w('  changed_pixels: min=%s p25=%s median=%s max=%s mean=%.1f' % (
        px[0], px[len(px) // 4], statistics.median(px), px[-1], statistics.mean(px)))
    for thr in (1, 4, 16, 64, 256, 1024):
        n = sum(1 for v in px if v <= thr)
        w('  <= %-5d px : %d (%.1f%%)' % (thr, n, 100.0 * n / len(px)))
w('  every changed=true capture with <= 4 pixels:')
for r in sorted(tr, key=lambda r: r.get('changed_pixels') or 0):
    if (r.get('changed_pixels') or 0) <= 4:
        c = calls.get(r['seq'], {})
        w('    seq=%-4s px=%-3s tool=%-34s ok=%-5s code=%-7s' % (
            r['seq'], r['changed_pixels'], r.get('tool'), c.get('ok'), c.get('error_code')))
w('')

w('=' * 100)
w('CAPTURE paired with a NON-OK call (no tool body ran) but changed=true')
w('=' * 100)
for r in sorted(tr, key=lambda r: r['seq']):
    c = calls.get(r['seq'])
    if c and not c.get('ok'):
        w('  seq=%-4s tool=%-34s code=%-7s px=%-6s ratio=%s' % (
            r['seq'], c.get('tool'), c.get('error_code'), r.get('changed_pixels'), r.get('changed_pixel_ratio')))
w('')

# ------------------------------------------------- contract cross-check -----
w('=' * 100)
w('CONTRACT CROSS-CHECK (tools_list.renamed.json)')
w('=' * 100)
doc = json.load(io.open(CONTRACT, encoding='utf-8'))
tools = doc['result']['tools']
names = [t['name'] for t in tools]
w('  contract tools=%d' % len(names))
for needle in ('read', 'text', 'tilemap', 'tileset', 'property', 'signal', 'script', 'animation_keyframe',
               'instance', 'save'):
    hit = sorted(n for n in names if needle in n)
    w('  name contains %-18s -> %d: %s' % (needle, len(hit), ', '.join(hit) if len(hit) <= 24 else ', '.join(hit[:24]) + ' ...'))
w('')
for probe in ('editor_set_node_properties_batch', 'editor_set_node_property_updates',
              'project_read_file', 'project_read_text_file', 'project_read_scene_file_content',
              'editor_get_node_properties', 'editor_set_tilemap_cell', 'editor_set_tilemap_cells_in_rect',
              'editor_set_animation_keyframe', 'editor_add_scene_instance', 'editor_save_scene',
              'editor_set_node_script_batch', 'editor_connect_signal', 'project_write_text_file'):
    t = next((x for x in tools if x['name'] == probe), None)
    if t is None:
        w('  ABSENT FROM CONTRACT: %s' % probe)
        continue
    w('  %s' % probe)
    w('     desc: %s' % t.get('description', '').replace('\n', ' ')[:400])
    w('     required: %s' % t.get('inputSchema', {}).get('required'))
    w('     params: %s' % sorted(t.get('inputSchema', {}).get('properties', {}).keys()))
w('')
OUT.close()
print('episodes written (%d bytes)' % os.path.getsize(os.path.join(HERE, 'episodes.txt')))
