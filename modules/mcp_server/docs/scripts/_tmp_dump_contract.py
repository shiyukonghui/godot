# -*- coding: utf-8 -*-
import json, io, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
c = json.load(io.open(os.path.join(DOCS,'tools_list.renamed.json'), encoding='utf-8'))
want = sys.argv[1:]
by = {t['name']: t for t in c['result']['tools']}
out = []
for n in want:
    t = by[n]
    out.append(json.dumps(t, ensure_ascii=False, indent=2))
io.open(os.path.join(HERE,'_tmp_contract.txt'),'w',encoding='utf-8').write('\n'.join(out))
print('ok', len(out))
