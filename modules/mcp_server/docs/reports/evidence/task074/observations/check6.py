import io, os, json
base = r'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074\raw'
out = io.open('checks6.txt', 'w', encoding='utf-8')
for d in sorted(os.listdir(base)):
    if 'tree' not in d:
        continue
    p = os.path.join(base, d)
    req = os.path.join(p, 'request.json')
    res = os.path.join(p, 'response.json')
    args = ''
    if os.path.exists(req):
        j = json.loads(open(req, encoding='utf-8').read())
        args = json.dumps(j.get('params', {}).get('arguments', {}), ensure_ascii=False)
        tool = j.get('params', {}).get('name')
    else:
        tool = '?'
    txt = open(res, encoding='utf-8').read() if os.path.exists(res) else ''
    body = txt
    try:
        j = json.loads(txt)
        if 'result' in j:
            body = j['result']['content'][0]['text']
    except ValueError:
        pass
    flat = set()
    def walk(n):
        flat.add(n.get('path'))
        for c in (n.get('children') or []):
            walk(c)
    try:
        walk(json.loads(body)['tree'])
    except Exception:
        pass
    out.write('%-28s tool=%-26s args=%s\n' % (d, tool, args))
    out.write('   nodes=%-4d has_Anim=%-5s has_HudRoot=%-5s has_ScoreLabel=%-5s\n' % (
        len(flat), 'Anim' in body, 'HudRoot' in body, 'ScoreLabel' in body))
    out.write('   paths_with_Anim=%s paths_with_HudRoot=%s\n' % (
        sorted(x for x in flat if x and 'Anim' in x), sorted(x for x in flat if x and 'HudRoot' in x)))
out.close()
print('ok')
