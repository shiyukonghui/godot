import io, json, os

ROOT = r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task075"


def body(path):
    doc = json.load(io.open(path, encoding="utf-8-sig"))
    if "result" in doc and doc["result"].get("content"):
        return doc["result"]["content"][0]["text"]
    return json.dumps(doc.get("error"), ensure_ascii=False)


TAGS = [
    "d2_batch_incompatible",
    "d2_batch_compatible",
    "d2_single_incompatible",
    "read_tool_before",
    "read_tool_roundtrip",
    "read_big_omitted",
    "read_big_included",
    "read_refuse_non_utf8",
    "d5_info_after_assign",
    "d5_set_cell",
    "game_good_marker",
    "game_bad_value",
]
for phase in ("live_before", "live_after"):
    for tag in TAGS:
        path = os.path.join(ROOT, phase, "evidence", tag + ".response.json")
        if os.path.exists(path):
            print("=== %s/%s" % (phase, tag))
            print(body(path)[:700])
            print("")
