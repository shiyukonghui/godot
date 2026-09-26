# -*- coding: utf-8 -*-
"""One-shot repair: rebuild the generated span of the two TASK-010 group files.

The first revision of `gen_b2_game_schema.py` put the BEGIN/END markers inside
each tool's block but generated the whole group as one fragment, so running it a
second time spliced a fresh copy of every block next to the existing ones. The
generator is fixed (one marker pair per file); this script throws away everything
between the registration function's opening line and the file's end and writes
the (single) generated span back, followed by the function's closing brace.
"""
import importlib.util
import io

spec = importlib.util.spec_from_file_location("gen", "scripts/gen_b2_game_schema.py")
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

PAIRS = [
    ("running_game_observation", "tools/running_game_observation.cpp"),
    ("running_game_script_execution", "tools/running_game_script_execution.cpp"),
]

for group, path in PAIRS:
    text = io.open(path, encoding="utf-8").read()
    marker = "void register_%s_tools(MCPToolRegistry &r_registry) {" % group
    index = text.find(marker)
    if index < 0:
        raise SystemExit("FATAL: cannot find the registration function in %s" % path)
    head = text[: index + len(marker)] + "\n"
    fragment = gen.emit_group(group)
    updated = head + fragment + "}\n"
    io.open(path, "w", encoding="utf-8", newline="").write(updated)
    print("%s: %d -> %d bytes" % (path, len(text), len(updated)))
