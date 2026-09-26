# -*- coding: utf-8 -*-
import json, io, os, sys
DOCS = sys.argv[1]
c = json.load(io.open(os.path.join(DOCS,'tools_list.renamed.json'), encoding='utf-8'))
m = json.load(io.open(os.path.join(DOCS,'tool-rename-map.json'), encoding='utf-8'))
by = {t['name']: t for t in c['result']['tools']}
bynew = {t['new_name']: t for t in m['tools']}
names = ["editor_add_node","editor_delete_node","editor_duplicate_node","editor_rename_node",
         "editor_reparent_node","editor_set_node_property","editor_set_node_groups",
         "editor_connect_signal","editor_disconnect_signal","editor_set_auto_dismiss_dialogs"]
handlers = {
 "editor_add_node":"_tool_add_node","editor_delete_node":"_tool_delete_node",
 "editor_duplicate_node":"_tool_duplicate_node","editor_rename_node":"_tool_rename_node",
 "editor_reparent_node":"_tool_reparent_node","editor_set_node_property":"_tool_set_node_property",
 "editor_set_node_groups":"_tool_set_node_groups","editor_connect_signal":"_tool_connect_signal",
 "editor_disconnect_signal":"_tool_disconnect_signal",
 "editor_set_auto_dismiss_dialogs":"_tool_set_auto_dismiss_dialogs"}
out = []
for n in names:
    t = by[n]; e = bynew[n]
    schema = json.dumps(t['inputSchema'], ensure_ascii=False, sort_keys=True, separators=(',',':'))
    desc = t['description']
    assert ')schema"' not in schema and ')desc"' not in desc, n
    out.append('\t{\n'
      '\t\tToolBuilder builder("%s", String::utf8(R"desc(%s)desc"));\n'
      '\t\tbuilder.channel("%s").verb("%s").scope(MCPToolScope::%s).mutating(%s);\n'
      '\t\tbuilder.schema(_schema_from_json(R"schema(%s)schema"));\n'
      '\t\tbuilder.handler(%s).register_into(r_registry);\n'
      '\t}\n' % (n, desc, e['channel'], e['verb'],
                 'EDITOR' if e['scope']=='editor' else ('GAME' if e['scope']=='game' else 'BOTH'),
                 'true' if e['mutating'] else 'false', schema, handlers[n]))
io.open(os.path.join(DOCS,'scripts','_tmp_reg_snippet.txt'),'w',encoding='utf-8').write('\n'.join(out))
print('ok')
