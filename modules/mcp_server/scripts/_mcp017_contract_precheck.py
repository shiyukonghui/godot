import json, re, sys, io

repo = r"F:\RustProjects\godot-mcp-pro\code\godot"
contract_path = repo + r"\modules\mcp_server\docs\tools_list.renamed.json"
with io.open(contract_path, encoding="utf-8") as f:
    contract = json.load(f)
by_name = {t["name"]: t for t in contract["result"]["tools"]}

files = [
    r"\modules\mcp_server\tools\editor_node_batch_write.cpp",
    r"\modules\mcp_server\tools\editor_control_layout_write.cpp",
    r"\modules\mcp_server\tools\editor_node_setup.cpp",
]

def canonical(o):
    return json.dumps(o, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

# Parse: ToolBuilder builder("<name>", String::utf8(R"desc(<desc>)desc")); ... _schema_from_json(R"schema(<json>)schema")
pat = re.compile(
    r'ToolBuilder builder\("([^"]+)",\s*String::utf8\(R"desc\((.*?)\)desc"\)\);(.*?)builder\.schema\(_schema_from_json\(R"schema\((.*?)\)schema"\)\)',
    re.S)

new = {}
for rel in files:
    with io.open(repo + rel, encoding="utf-8") as f:
        text = f.read()
    for m in pat.finditer(text):
        name, desc, mid, schema = m.group(1), m.group(2), m.group(3), m.group(4)
        new[name] = (desc, schema, rel)

ok = True
for name, (desc, schema_s, rel) in new.items():
    entry = by_name.get(name)
    if entry is None:
        print("MISSING IN CONTRACT:", name); ok = False; continue
    try:
        schema = json.loads(schema_s)
    except Exception as e:
        print("BAD JSON SCHEMA", name, e); ok = False; continue
    d_ok = desc == entry["description"]
    s_ok = canonical(schema) == canonical(entry["inputSchema"])
    print("%-36s desc=%s schema=%s" % (name, d_ok, s_ok))
    if not d_ok:
        print("   expected desc:", repr(entry["description"]))
        print("   actual   desc:", repr(desc))
    if not s_ok:
        print("   expected schema:", canonical(entry["inputSchema"]))
        print("   actual   schema:", canonical(schema))
    if not (d_ok and s_ok):
        ok = False

print("total parsed:", len(new))
sys.exit(0 if ok else 1)
