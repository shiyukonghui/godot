import io, re

p = r'modules\mcp_server\scripts\mcp031_gate6_coverage_probes.ps1'
b = io.open(p, 'rb').read()
print('has BOM before', b[:3] == b'\xef\xbb\xbf')
t = b.decode('utf-8-sig')
t = t.replace("_scanned_69\\'", "_scanned_69'")
t = t.replace('\\$baselineJson', '$baselineJson').replace('\\$finalJson', '$finalJson')
# Any remaining backslash immediately before a single quote in a Check line is an
# artifact of the earlier replacement.
t = re.sub(r"\\(?=')", "", t)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
b2 = io.open(p, 'rb').read()
print('has BOM after', b2[:3] == b'\xef\xbb\xbf')
for m in re.finditer(r'.*(_scanned_69|scanned -eq 69).*', t):
    print(repr(m.group(0)))
print('non-ascii bytes:', any(c > 127 for c in b2))
print('trailing newline:', b2.endswith(b'\n'))
