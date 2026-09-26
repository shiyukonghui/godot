import io, os, re

path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'tool-groups-b5.json')
with io.open(path, encoding='utf-8') as f:
    text = f.read()

targets = [
    'editor_navigation_write',
    'project_theme_write',
    'project_theme_read',
    'project_export_read',
    'project_android_read',
    'os_android_read',
    'os_android_write',
    'running_game_navigation_write',
]

changed = 0
for name in targets:
    pattern = re.compile(
        r'("name": "' + re.escape(name) + r'",\s*\n(?:\s*"[a-z_]+": [^\n]*\n)*?\s*"implemented": )false')
    text, n = pattern.subn(r'\1true', text, count=1)
    changed += n
    if n != 1:
        print('WARN: %s -> %d replacement(s)' % (name, n))

with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(text)
print('flipped', changed)
