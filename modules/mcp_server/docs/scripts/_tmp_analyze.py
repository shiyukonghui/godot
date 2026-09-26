# -*- coding: utf-8 -*-
import json, io, os, collections
HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
m = json.load(io.open(os.path.join(DOCS,'tool-rename-map.json'), encoding='utf-8'))
c = json.load(io.open(os.path.join(DOCS,'tools_list.renamed.json'), encoding='utf-8'))
g1 = json.load(io.open(os.path.join(DOCS,'tool-groups.json'), encoding='utf-8'))
g2 = json.load(io.open(os.path.join(DOCS,'tool-groups-b2.json'), encoding='utf-8'))
contract = [t['name'] for t in c['result']['tools']]
by_new = {t['new_name']: t for t in m['tools']}
impl = set()
for g in g1['groups']:
    if g.get('implemented'): impl |= set(g['tools'])
for g in g2['groups']:
    if g.get('implemented'): impl |= set(g['tools'])
print('contract', len(contract), 'unique', len(set(contract)))
print('map entries', len(m['tools']))
print('implemented', len(impl))
disp = collections.Counter(t['disposition'] for t in m['tools'])
print('dispositions', dict(disp))
unreg = [t['new_name'] for t in m['tools'] if t['disposition'] != 'rename' and t['new_name'] not in contract]
print('NOT in contract:', [(t['old_name'], t['new_name'], t['disposition']) for t in m['tools'] if t['new_name'] not in contract])
remaining = [n for n in contract if n not in impl]
print('remaining in contract not implemented:', len(remaining))
# also map-level
print('map names not in contract:', [t['new_name'] for t in m['tools'] if t['new_name'] not in contract])
