import io, os, json, collections
base = r'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074'
out = io.open('checks8.txt', 'w', encoding='utf-8')

p = os.path.join(base, 'raw', 'M12__004_read_main_tscn', 'response.json')
j = json.loads(open(p, encoding='utf-8').read())
txt = j['result']['content'][0]['text']
content = json.loads(txt)['content']
out.write('M12__004 read_main_tscn (seq 193): content bytes=%d\n' % len(content.encode('utf-8')))
out.write('sha256(content utf8)=%s\n' % __import__('hashlib').sha256(content.encode('utf-8')).hexdigest())

lines = content.split('\n')
coin_ext = collections.Counter()
for ln in lines:
    if ln.startswith('[node name="CoinField'):
        pass
    if ln.startswith('script = ExtResource'):
        coin_ext[ln.strip()] += 1
out.write('script = ExtResource lines: %s\n' % dict(coin_ext))

# count CoinField children that carry a script line
cur = None
nodes = []
for i, ln in enumerate(lines):
    if ln.startswith('[node name='):
        cur = {'decl': ln, 'line': i, 'script': None, 'children': 0}
        nodes.append(cur)
    elif cur is not None:
        if ln.startswith('script = '):
            cur['script'] = ln.strip()
out.write('total nodes=%d\n' % len(nodes))
coinfield = [n for n in nodes if 'parent="World/CoinField"' in n['decl']]
out.write('CoinField children=%d, of which with a script line=%d\n' % (
    len(coinfield), sum(1 for n in coinfield if n['script'])))
out.write('first 6: %s\n' % [n['decl'][:70] + ' | ' + str(n['script']) for n in coinfield[:6]])
roots = [n for n in nodes if 'parent=' not in n['decl']]
out.write('root nodes=%s\n' % [n['decl'][:90] for n in roots])
withscript = [(n['decl'][:80], n['script']) for n in nodes if n['script']]
out.write('nodes with a script line=%d\n' % len(withscript))
for d, s in withscript[:40]:
    out.write('   %-80s %s\n' % (d, s))

# the dev's own count file
cf = os.path.join(base, 'main-tscn-script-count.txt')
out.write('\nmain-tscn-script-count.txt: %s\n' % open(cf).read().strip())
out.close()
print('ok')
