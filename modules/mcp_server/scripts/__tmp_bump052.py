import io

p = r'modules/mcp_server/tests/test_mcp_server.h'
s = io.open(p, encoding='utf-8').read()
pairs = [
    ('get_tool_count() == 69)', 'get_tool_count() == 71)'),
    ('get_visible_tool_count(false) == 69)', 'get_visible_tool_count(false) == 71)'),
    ('get_visible_tool_count(true) == 46)', 'get_visible_tool_count(true) == 48)'),
    ('build_tools_list(true).size() == 46)', 'build_tools_list(true).size() == 48)'),
    ('get_tool_count() == 171)', 'get_tool_count() == 173)'),
    ('get_visible_tool_count(true) == 148)', 'get_visible_tool_count(true) == 150)'),
    ('game_list.size() == 69)', 'game_list.size() == 71)'),
    ('game_listing.size() == 69)', 'game_listing.size() == 71)'),
    ('editor_list.size() == 148)', 'editor_list.size() == 150)'),
    ('"tools", 0) == 171)', '"tools", 0) == 173)'),
]
for a, b in pairs:
    n = s.count(a)
    s = s.replace(a, b)
    print('%-50s -> %-50s x%d' % (a, b, n))
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('written')
