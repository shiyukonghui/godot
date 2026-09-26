import io, os, re, sys

MODULE = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
HEADER = os.path.join(MODULE, 'tests', 'test_mcp_server.h')

with io.open(HEADER, encoding='utf-8') as f:
    text = f.read()
lines = text.split('\n')

builds = {}
listbuilds = {}

build_re = re.compile(r'build_(all_tools|editor_process)_registry\((\w+)\)')
list_re = re.compile(r'(\w+)\s*=\s*(\w+)\.build_tools_list\((\w+)\)')
check_re = re.compile(r'CHECK\((\w+)\.(get_tool_count|get_visible_tool_count|build_tools_list)\(([^()]*)\)\s*==\s*(\d+)\)')
size_re = re.compile(r'CHECK\((\w+)_list\.size\(\)\s*==\s*(\d+)\)')
list_size_direct_re = re.compile(r'CHECK\((\w+)\.build_tools_list\(([^()]*)\)\.size\(\)\s*==\s*(\d+)\)')
# old -> new by (table, mode)
NEW = {
    ('all', 'count'): (57, 69),
    ('all', 'visible_true'): (35, 46),
    ('all', 'visible_false'): (57, 69),
    ('all', 'list_true'): (35, 46),
    ('all', 'list_false'): (57, 69),
    ('editor', 'count'): (157, 171),
    ('editor', 'visible_true'): (135, 148),
    ('editor', 'visible_false'): (57, 46),
    ('editor', 'list_true'): (135, 148),
    ('editor', 'list_false'): (57, 46),
}

changes = []
unresolved = []


def apply(index, key, old, new, label):
    line = lines[index]
    if ('== %d)' % old) not in line:
        unresolved.append('%d: %s expected old %d not found in: %s' % (index + 1, label, old, line.strip()))
        return
    lines[index] = line.replace('== %d)' % old, '== %d)' % new, 1)
    changes.append('%d: %s  %d -> %d' % (index + 1, label, old, new))


for i, line in enumerate(lines):
    m = build_re.search(line)
    if m:
        builds[m.group(2)] = 'all' if m.group(1) == 'all_tools' else 'editor'
    m = list_re.search(line)
    if m:
        listbuilds[m.group(1)] = (m.group(2), m.group(3))
    m = check_re.search(line)
    if m:
        var, accessor, arg, old = m.group(1), m.group(2), m.group(3), int(m.group(4))
        table = builds.get(var)
        if table is None:
            unresolved.append('%d: unknown table for %s: %s' % (i + 1, var, line.strip()))
            continue
        if accessor == 'get_tool_count':
            key = 'count'
        elif accessor == 'get_visible_tool_count':
            key = 'visible_true' if arg.strip() == 'true' else 'visible_false'
        else:
            key = 'list_true' if arg.strip() == 'true' else 'list_false'
        old_expected, new = NEW[(table, key)]
        if old != old_expected:
            unresolved.append('%d: %s.%s(%s) old=%d expected %d' % (i + 1, var, accessor, arg, old, old_expected))
            continue
        apply(i, (table, key), old, new, '%s.%s(%s)' % (var, accessor, arg))
        continue
    m = list_size_direct_re.search(line)
    if m:
        var, mode, old = m.group(1), m.group(2), int(m.group(3))
        table = builds.get(var)
        if table is None:
            unresolved.append('%d: unknown table for %s (direct size): %s' % (i + 1, var, line.strip()))
            continue
        key = 'list_true' if mode.strip() == 'true' else 'list_false'
        old_expected, new = NEW[(table, key)]
        if old != old_expected:
            unresolved.append('%d: %s.build_tools_list(%s).size() old=%d expected %d' % (i + 1, var, mode, old, old_expected))
            continue
        apply(i, (table, key), old, new, '%s.build_tools_list(%s).size()' % (var, mode))
        continue
    m = size_re.search(line)
    if m:
        listvar, old = m.group(1) + '_list', int(m.group(2))
        info = listbuilds.get(listvar)
        if info is None:
            unresolved.append('%d: unknown list build for %s: %s' % (i + 1, listvar, line.strip()))
            continue
        reg, mode = info
        table = builds.get(reg)
        if table is None:
            unresolved.append('%d: unknown table for list %s (registry %s)' % (i + 1, listvar, reg))
            continue
        key = 'list_true' if mode.strip() == 'true' else 'list_false'
        old_expected, new = NEW[(table, key)]
        if old != old_expected:
            unresolved.append('%d: %s.size() old=%d expected %d' % (i + 1, listvar, old, old_expected))
            continue
        apply(i, (table, key), old, new, '%s.size()' % listvar)

if '--apply' in sys.argv:
    with io.open(HEADER, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))

print('changes: %d' % len(changes))
for c in changes:
    print('  ' + c)
print('unresolved: %d' % len(unresolved))
for u in unresolved:
    print('  ' + u)
