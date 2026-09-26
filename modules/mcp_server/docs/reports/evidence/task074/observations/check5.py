import io, os, json
base = r'F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074'
out = io.open('checks5.txt', 'w', encoding='utf-8')

# 1) full args of the script-creation calls
for r in (json.loads(l) for l in io.open(os.path.join(base, 'observations', 'traces', 'trace-editor.jsonl'), encoding='utf-8') if l.strip()):
    if r.get('method') != 'tools/call':
        continue
    if r.get('seq') in (32, 33, 46, 47, 22, 147, 13, 19):
        a = json.loads(r['args'])
        a2 = dict(a)
        if 'content' in a2:
            c = a2['content']
            a2['content'] = '<%d bytes, first line: %r>' % (len(c), c.split('\n')[0][:70])
        out.write('seq=%-4s %-24s ok=%s code=%s\n   %s\n' % (r['seq'], r['tool'], r['ok'], r['error_code'],
                                                             json.dumps(a2, ensure_ascii=False)))

# 2) validation / error-reporting responses
def cat(d, files=('request.json', 'response.json'), limit=2600):
    p = os.path.join(base, 'raw', d)
    out.write('\n' + '=' * 80 + '\n%s\n' % d)
    if not os.path.isdir(p):
        out.write('(missing)\n')
        return
    for f in files:
        fp = os.path.join(p, f)
        if not os.path.exists(fp):
            continue
        t = open(fp, 'rb').read().decode('utf-8')
        try:
            j = json.loads(t)
            if 'result' in j and 'content' in j['result']:
                txt = j['result']['content'][0]['text']
                try:
                    j = json.loads(txt)
                except ValueError:
                    j = txt
            t = json.dumps(j, ensure_ascii=False, indent=1)
        except ValueError:
            pass
        out.write('-- %s\n%s\n' % (f, t[:limit]))

for d in ('M3__001_validate_bogus_gd', 'M3__002_validate_all', 'M2__002_create_main_script_wrong_ext',
          'M2__003_create_main_cs', 'M12__002_editor_errors', 'M11__001_open_main'):
    cat(d)
out.close()
print('ok')
