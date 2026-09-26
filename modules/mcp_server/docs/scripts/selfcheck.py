# -*- coding: utf-8 -*-
"""Read-only self-check of the rendered docs/TOOL-NAMING.md (v1.1).

Complements gen_table.py: that script proves the document matches the map by
construction; this one inspects the artifact on disk the way a reviewer would
(shapes, counts, required statements, leftover placeholders, embedded evidence).

Usage:  python modules/mcp_server/docs/scripts/selfcheck.py
Standard library only (Python 3.9).
"""

import hashlib
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
P = os.path.join(DOCS, "TOOL-NAMING.md")
MAP = os.path.join(DOCS, "tool-rename-map.json")

BT = "`"
s = io.open(P, encoding="utf-8").read()
b = io.open(P, "rb").read()
map_b = io.open(MAP, "rb").read()

rows = [l for l in s.splitlines() if l.startswith("| " + BT) and l.count(BT + " |") >= 7]
print("BYTES      %d" % len(b))
print("SHA256     %s" % hashlib.sha256(b).hexdigest())
print("LINES      %d" % (s.count("\n") + 1))
print("MAP_BYTES  %d" % len(map_b))
print("MAP_SHA256 %s" % hashlib.sha256(map_b).hexdigest())
print("TOOLROWS   %d  (assert == 174: %s)" % (len(rows), "PASS" if len(rows) == 174 else "FAIL"))
hdr = "| old_name | channel | verb | object | new_name | mutating | scope | disposition | reason |"
print("HEADERS    %d (expect 4)" % s.count(hdr))
print("CH2_COUNTS 2.1=%s 2.2=%s 2.3=%s 2.4=%s" % tuple(
    re.findall(r"### 2\.\d[^\n]*（(\d+) 条）", s)))
print("PLACEHOLDERS_LEFT %d" % s.count("@@"))
print("MERGE_GROUPS_SECTION %s" % (
    "OK" if "**1 个新名对应 2 个旧名**" in s else "MISSING"))
print("HEADER_FINGERPRINT %s" % (
    "OK" if ("`%d` 字节" % len(map_b)) in s and hashlib.sha256(map_b).hexdigest() in s else "MISSING"))
must = [
    # v1.1 data changes
    "project_find_files_referencing_symbol", "editor_list_signal_connections",
    "project_search_file_contents", "editor_analyze_signal_flow",
    "merge_target", "merge_into", "disposition_enum", "scope_enum",
    "平铺改嵌套", "条件写", "GDR-17", "GDR-18", "D45", "unused_in_v1",
    "103", "164", "171",
    # pre-existing normative content that must survive the re-render
    "find_signal_connections", "signal_name", "addons/", "扩展名白名单",
    "export.rs:117", "TODO", "请自行实现", "mcp_runtime_agent.gd:554",
    "tilemap_set_cell", "tilemap_fill_rect", "必须先写红测试", "数据破坏",
    "TESTER_ALLOW_PREFIXES", "TESTER_ALLOW_EXACT", "MUTATING_PREFIXES", "MUTATING_EXACT",
    "fail-closed", "禁止用「给 allow 表加通道前缀」过桥",
    "is_mutating(old", "JSON 是唯一事实源", "注册期 lint", "运行期不变式测试",
    "godot_mcp_gdext", "registry.insert", "ToolDefinition::new", "tools_list.json",
    "8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54",
    "tool_registry.cpp", "src\\runtime\\policy.rs", "src\\adapter\\godot.rs", "src\\adapter\\mod.rs",
    "src\\prompts", "Phase 0", "最长前缀", "split('_')[1]",
    "GDR-13", "GDR-12", "D41", "D38", "D34",
]
missing = []
for k in must:
    c = s.count(k)
    if not c:
        missing.append(k)
    print("REQUIRE  %-72s %d %s" % (k, c, "" if c else "  <-- MISSING"))
print("SECTION7_EVIDENCE %s" % (
    "EMBEDDED" if "ASSERT  rows == 174 : PASS" in s
    and "CONSISTENCY  result: PASS" in s
    and "DETERMINISM  render run#1 == render run#2 byte-identical" in s else "MISSING"))
print("SELFCHECK  result: %s" % ("PASS" if not missing and len(rows) == 174 else "FAIL (%s)" % missing))

# TASK-069 section 2.3 (census): this read-only self-check printed its verdict
# and then exited 0 either way, so a failure was invisible to any caller. It has
# no `main()` and no aggregate object to thread through, so the verdict is
# computed once into `ok` and turned into the process exit code.
ok = (not missing and len(rows) == 174)
if not ok:
    sys.exit(1)
sys.exit(0)
