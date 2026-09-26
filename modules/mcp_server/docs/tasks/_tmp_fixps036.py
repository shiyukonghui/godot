import io

p = r'modules\mcp_server\scripts\mcp031_gate6_coverage_probes.ps1'
b = io.open(p, 'rb').read()
print('first bytes', b[:4], 'len', len(b))
print('has BOM', b[:3] == b'\xef\xbb\xbf')
t = b.decode('utf-8-sig')
t = t.replace('\\$baselineJson', '$baselineJson').replace('\\$finalJson', '$finalJson')
if not t.endswith('\n'):
    t += '\n'
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
i = t.find('B1_baseline_scanned')
print(repr(t[i:i + 160]))
i = t.find('B1b_restored_scanned')
print(repr(t[i:i + 130]))
