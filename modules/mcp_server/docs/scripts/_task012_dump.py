import json
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
p = 'modules/mcp_server/docs/tools_list.renamed.json'
c = json.load(open(p, encoding='utf-8'))
tools = c['result']['tools']
idx = {t['name']: t for t in tools}
for n in sys.argv[1:]:
    t = idx.get(n)
    print('=== ', n, 'FOUND' if t else 'MISSING')
    if t:
        print(json.dumps(t, ensure_ascii=False, indent=1))
