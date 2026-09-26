# -*- coding: utf-8 -*-
import json, io, os, collections
HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
def L(n): return json.load(io.open(os.path.join(DOCS,n), encoding='utf-8'))
m = L('tool-rename-map.json'); c = L('tools_list.renamed.json')
g1 = L('tool-groups.json'); g2 = L('tool-groups-b2.json')
contract = [t['name'] for t in c['result']['tools']]
by_new = {t['new_name']: t for t in m['tools']}
impl = set()
for g in g1['groups']:
    if g.get('implemented'): impl |= set(g['tools'])
for g in g2['groups']:
    if g.get('implemented'): impl |= set(g['tools'])
print('impl not in contract:', sorted(impl - set(contract)))
remaining = [n for n in contract if n not in impl]
print('remaining', len(remaining))
out = []
for n in remaining:
    e = by_new[n]
    out.append((e['channel'], e['scope'], str(e['mutating']), e['verb'], e['old_name'], n, e['disposition']))
out.sort()
with io.open(os.path.join(HERE,'_tmp_remaining.tsv'),'w',encoding='utf-8') as f:
    f.write('channel\tscope\tmutating\tverb\told_name\tnew_name\tdisposition\n')
    for r in out: f.write('\t'.join(r)+'\n')
print('wrote tsv')
# dispositions among remaining
print(collections.Counter(r[6] for r in out))
print(collections.Counter((r[0],r[1],r[2]) for r in out))
fixfirst = [r for r in out if r[6]=='fix_implementation_first']
print('FIX FIRST remaining:', len(fixfirst))
for r in fixfirst: print('  ', r[5], '<=', r[4])
