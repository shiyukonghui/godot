# -*- coding: utf-8 -*-
"""Count the implemented tool union of B1 + B2, split by scope, for TASK-012."""
import json
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
mod = 'modules/mcp_server/docs/'
b1 = json.load(open(mod + 'tool-groups.json', encoding='utf-8'))
b2 = json.load(open(mod + 'tool-groups-b2.json', encoding='utf-8'))
rm = json.load(open(mod + 'tool-rename-map.json', encoding='utf-8'))
scope = {t['new_name']: t['scope'] for t in rm['tools']}

impl = []
for doc in (b1, b2):
    for g in doc['groups']:
        if g['implemented'] is True:
            impl.extend(g['tools'])
print('implemented union:', len(impl), 'unique:', len(set(impl)))
by = {'editor': [], 'game': [], 'both': []}
for n in impl:
    by[scope[n]].append(n)
for k in ('editor', 'game', 'both'):
    print(' %-7s %d' % (k, len(by[k])))
editor = [n for n in impl if scope[n] != 'game']
game = [n for n in impl if scope[n] != 'editor']
print('editor endpoint serves:', len(editor))
print('game endpoint serves  :', len(game))
print('game registry (game+both):', len(by['game']) + len(by['both']))
print('editor registry (all     ):', len(impl))
