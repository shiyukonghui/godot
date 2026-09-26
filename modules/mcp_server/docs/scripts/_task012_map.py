import json
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
p = 'modules/mcp_server/docs/tool-rename-map.json'
c = json.load(open(p, encoding='utf-8'))
for entry in c['tools']:
    if entry.get('new_name') in sys.argv[1:]:
        print(json.dumps(entry, ensure_ascii=False, indent=1))
