import io, os, json
base = r'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074\raw'
out = io.open('checks3.txt', 'w', encoding='utf-8')
t = open(os.path.join(base, 'M6__002_attach_coin_script_batch30', 'response.json'), 'rb').read().decode('utf-8')
obj = json.loads(t)
txt = obj['result']['content'][0]['text']
out.write('=== batch30 response: full text len=%d ===\n' % len(txt))
out.write('contains readable   : %s\n' % ('readable' in txt))
out.write('contains unreadable : %s\n' % ('unreadable' in txt))
d = json.loads(txt)
out.write('top-level keys : %s\n' % sorted(d.keys()))
out.write('per-node keys  : %s\n' % sorted(d['attached'][0].keys()))
out.write('attached true=%d false=%d\n' % (sum(1 for a in d['attached'] if a['attached']),
                                           sum(1 for a in d['attached'] if not a['attached'])))
out.write('tail 700 chars : %s\n' % txt[-700:])
out.close()
print('ok')
