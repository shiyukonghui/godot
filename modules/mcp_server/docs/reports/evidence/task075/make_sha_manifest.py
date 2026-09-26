import hashlib, os, io

REPO = r"F:\RustProjects\godot-mcp-pro\code\godot"
PATHS = [
    "modules/mcp_server/tools/project_text_read.cpp",
    "modules/mcp_server/tools/project_text_read.h",
    "modules/mcp_server/tools/editor_set_node_script_batch.cpp",
    "modules/mcp_server/tools/editor_set_node_script_batch.h",
    "modules/mcp_server/tools/editor_script_write.cpp",
    "modules/mcp_server/tools/registration.cpp",
    "modules/mcp_server/tests/test_mcp_server.h",
    "modules/mcp_server/docs/tools_list.renamed.json",
    "modules/mcp_server/docs/tool-groups-added.json",
    "modules/mcp_server/scripts/gen_renamed_contract.py",
    "modules/mcp_server/scripts/analyze_mcp_trace.py",
    "modules/mcp_server/docs/reports/evidence/task074/observations/obs_digest.py",
    "modules/mcp_server/scripts/mcp075_live_evidence.ps1",
    "modules/mcp_server/scripts/mcp075_red_phase.ps1",
    "modules/mcp_server/scripts/mcp075_analysis_evidence.ps1",
    "modules/mcp_server/scripts/mcp075_d4_staleness.ps1",
    "modules/mcp_server/docs/reports/evidence/task075/live_before/evidence/d2_batch_incompatible.response.json",
    "modules/mcp_server/docs/reports/evidence/task075/live_before/evidence/d2_batch_compatible.response.json",
    "modules/mcp_server/docs/reports/evidence/task075/live_after/evidence/d2_batch_incompatible.response.json",
    "modules/mcp_server/docs/reports/evidence/task075/live_after/evidence/d2_batch_compatible.response.json",
    "modules/mcp_server/docs/reports/evidence/task075/live_after/evidence/editor_tools_list.response.json",
    "modules/mcp_server/docs/reports/evidence/task075/live_after/evidence/read_tool_roundtrip.response.json",
    "modules/mcp_server/docs/reports/evidence/task075/live_before/evidence/summary.txt",
    "modules/mcp_server/docs/reports/evidence/task075/live_after/evidence/summary.txt",
    "modules/mcp_server/docs/reports/evidence/task075/analysis/digest_before_task075.txt",
    "modules/mcp_server/docs/reports/evidence/task075/analysis/digest_after_task075.txt",
    "modules/mcp_server/docs/reports/evidence/task075/analysis/analyze_before_editor.txt",
    "modules/mcp_server/docs/reports/evidence/task075/analysis/analyze_after_editor.txt",
    "modules/mcp_server/docs/reports/evidence/task075/red_phase/red_test.txt",
    "modules/mcp_server/docs/reports/evidence/task075/red_phase/green_test.txt",
    "modules/mcp_server/docs/reports/evidence/task075/gate1_contract_subset.txt",
    "modules/mcp_server/docs/reports/evidence/task075/gate3_doctest_mcpserver.txt",
    "modules/mcp_server/docs/reports/evidence/task075/gate4_full_doctest.txt",
    "modules/mcp_server/docs/reports/evidence/task075/gate6_coverage_probes.txt",
    "modules/mcp_server/docs/reports/evidence/task075/gate6_narrowing.txt",
    "modules/mcp_server/docs/reports/evidence/task075/accept_m1_inventory_compare.json",
    "modules/mcp_server/docs/reports/evidence/task075/gate_engine_anchor.txt",
    "modules/mcp_server/docs/reports/evidence/task075/d4_staleness/evidence/summary.txt",
    "modules/mcp_server/docs/reports/evidence/task074/CALLS.jsonl",
    "modules/mcp_server/docs/reports/evidence/task074/aggregate/c_calls2.stdout.txt",
]

out = io.open(os.path.join(REPO, "modules/mcp_server/docs/reports/evidence/task075/sha256_manifest.txt"), "w", encoding="utf-8")
for path in PATHS:
    full = os.path.join(REPO, path.replace("/", os.sep))
    if os.path.exists(full):
        digest = hashlib.sha256(open(full, "rb").read()).hexdigest()
        line = "%s  %s" % (digest, path)
    else:
        line = "MISSING   %s" % path
    out.write(line + "\n")
    print(line)
out.close()
