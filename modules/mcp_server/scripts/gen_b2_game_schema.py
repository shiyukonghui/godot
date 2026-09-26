# -*- coding: utf-8 -*-
"""Emit the registration fragment of the TASK-010 group files.

`description` and `inputSchema` are the *sole authority* of
`docs/tools_list.renamed.json` and must be copied byte for byte: hand-typing
Chinese JSON text is how a contract gate fails for a reason nobody can see. The
B1 generator (`gen_running_game_schema.py`) could only emit flat string/number
properties; the B2 game-side tools carry `default`, `items` and one nested object
schema (`running_game_get_node_properties_batch`), so this generator walks the
whole schema recursively.

Two facts it never invents, both read from the rename map:

  * `channel`, `verb`, `scope` and `mutating` come from
    `docs/tool-rename-map.json`, so a declaration can not disagree with the
    authority (that is the same cross-check the B2 manifest is validated
    against by `docs/scripts/check_tool_groups.py --batch B2`);
  * the handler name is `_tool_<name without the channel prefix>`, which is the
    convention of the two group files.

Usage:
    python modules/mcp_server/scripts/gen_b2_game_schema.py --group running_game_observation
    python modules/mcp_server/scripts/gen_b2_game_schema.py --group running_game_script_execution --in-place tools/running_game_script_execution.cpp

`--in-place` rewrites the first `// BEGIN generated` .. `// END generated` span
of the file with the generated text, so the checked-in block is reproducible and
diffable instead of trusted. The output is always written as UTF-8 bytes.

Standard library only (Python 3.9).
"""

import argparse
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(MODULE))
CONTRACT = os.path.join(MODULE, "docs", "tools_list.renamed.json")
RENAME_MAP = os.path.join(MODULE, "docs", "tool-rename-map.json")

# The group -> tool list mapping is the authority of docs/tool-groups-b2.json
# (validated by docs/scripts/check_tool_groups.py --batch B2). It is repeated
# here only so that the generator knows *which* contract entries to emit; the
# declarations themselves still come from the rename map.
GROUPS = {
    "running_game_observation": [
        "running_game_get_scene_tree",
        "running_game_get_node_properties",
        "running_game_get_node_properties_batch",
        "running_game_get_autoload_node",
        "running_game_find_nodes_by_script",
        "running_game_find_ui_elements",
    ],
    "running_game_script_execution": [
        "running_game_execute_gdscript",
    ],
    # TASK-011 section 2: the frame-clock group and the single-shot capture
    # group. Both are game-scope; the first three tools are registered with
    # `pending_handler()`, the fourth with `handler()` - the handler *name* is
    # what the generator emits either way, so the generator needs no knowledge of
    # which half a tool belongs to.
    "running_game_frame_observation": [
        "running_game_get_node_property_samples",
        "running_game_find_node_when_available",
        "running_game_capture_frames",
    ],
    "running_game_capture": [
        "running_game_capture_screenshot",
    ],
    # TASK-012 section 1: B2's third batch. Four groups, eight tools, two
    # processes - the game-side input family and the one game-scope property
    # write, then the editor's play/stop pair and its InputMap read. The groups
    # are listed in docs/tool-groups-b2.json order; the generator's only
    # interest in them is *which* contract entries to emit.
    "running_game_input": [
        "running_game_create_input_recording",
        "running_game_stop_input_recording",
        "running_game_play_input_recording",
        "running_game_simulate_button_click_by_text",
    ],
    "running_game_node_write": [
        "running_game_set_node_property",
    ],
    "editor_playback": [
        "editor_play_scene",
        "editor_stop_scene",
    ],
    "editor_input_read": [
        "editor_get_input_actions",
    ],
    # TASK-013 section 1: B2's last group, six editor-scope input simulation
    # tools. Every one of them is `scope = editor`, so this group changes the
    # editor endpoint's count and leaves the game endpoint's alone.
    "editor_input_simulation": [
        "editor_simulate_input_action",
        "editor_simulate_key",
        "editor_simulate_mouse_click",
        "editor_simulate_mouse_move",
        "editor_simulate_input_sequence",
        "editor_add_input_action",
    ],
    # TASK-019 section 1: the three groups of docs/tool-groups-b4.json, in that
    # manifest's order. The B4 batch is the test/assertion family: the editor's
    # two test-artefact readers, the running game's three assertions/observations,
    # and the two scenario drivers. `editor_get_test_report` was the batch's
    # `fix_implementation_first` entry; the *name* is what this generator ever
    # needs, so nothing here depends on which half of that fix landed first.
    "editor_testing_read": [
        "editor_get_test_report",
        "editor_analyze_screenshot_diff",
    ],
    "running_game_assertion": [
        "running_game_assert_node_state",
        "running_game_assert_screen_text",
        "running_game_capture_signal_emissions",
    ],
    "running_game_test_execution": [
        "running_game_run_test_scenario",
        "running_game_run_stress_test",
    ],
}

SCOPE_CPP = {"editor": "MCPToolScope::EDITOR", "game": "MCPToolScope::GAME", "both": "MCPToolScope::BOTH"}

# TASK-019: the one tool of B4 whose handler name is not `_tool_<name without the
# channel prefix>`. `editor_get_test_report`'s implementation is about the report
# *format*, and it lives next to its sibling reader; the name below is what
# `tools/editor_testing_read.cpp` defines. (Empty is the normal case: the
# convention holds for the other 170 tools.)
HANDLER_OVERRIDES = {
    "editor_get_test_report": "_tool_get_test_report",
}

# TASK-011 / GDR-20: these tools answer across frames, so they are registered
# with the *deferred* half of the builder (`pending_handler`, which takes the
# same function-pointer shape and returns a `MCPDeferred::Task *`). The list is
# repeated here for the same reason the group lists are: the generator has to
# know which registration call to emit, and the tool itself cannot be asked
# before it exists. `ToolBuilder::build()` refuses a tool that declares both
# halves, so a wrong entry here is a loud failure, not a silent one.
DEFERRED = {
    "running_game_get_node_property_samples",
    "running_game_find_node_when_available",
    "running_game_capture_frames",
    # TASK-012 section 2.1: replayed events sit on a time line
    # (`time_ms` per event, divided by `speed`), so a replay is inherently
    # multi-frame - injecting the whole recording inside the frame that read the
    # request would collapse every delay to zero. The other three tools of that
    # group are immediate: the recording accumulates between two calls that
    # already sit on different frames, and a synthetic button press is a
    # synchronous signal emission.
    "running_game_play_input_recording",
    # TASK-013 section 1: a sequence of synthetic events is *paced*: one event
    # every `frame_delay` frames, which is the migration source's own semantics
    # (`mcp_input_service.gd:61-65`) and therefore inherently multi-frame. The
    # other five tools of that group inject exactly one event each and answer in
    # the frame that read the request.
    "editor_simulate_input_sequence",
    # TASK-019 section 1: of B4's seven tools exactly three span frames. Both
    # scenario drivers do by construction (a scenario is input steps, waits and
    # assertions in sequence, and a stress test is `count` repeats of an action -
    # doing either inside one frame would collapse every wait to zero), and
    # `running_game_capture_signal_emissions` does because its whole parameter set
    # is a **listen window** (`duration_ms`, default 5000). The other four answer
    # from the current frame: a node property, the visible text of the current
    # scene, the accumulated test report, and a CPU-side pixel diff of two files
    # that are already on disk. `running_game_run_stress_test` reports the
    # *observed* outcome (completed / crashed), not a fabricated verdict; the
    # deliberate failure of TASK-019 section 1.3 is a `run_test_scenario` whose
    # assertion cannot hold.
    "running_game_capture_signal_emissions",
    "running_game_run_test_scenario",
    "running_game_run_stress_test",
}


def cpp(text):
    """The body of a C++ double-quoted literal for exactly these characters."""
    out = []
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        else:
            out.append(ch)
    return "".join(out)


def literal(value):
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return 'String::utf8("%s")' % cpp(value)
    if value is None:
        return "Variant()"
    raise SystemExit("FATAL: cannot express %r as a Variant literal" % (value,))


def emit(value, lines, indent, counter, name=None):
    """Emit `value` (a JSON object or array) into a fresh variable, return its name."""
    if name is None:
        name = "v%d" % counter[0]
        counter[0] += 1
    if isinstance(value, dict):
        lines.append("%sDictionary %s;" % (indent, name))
        for key in value:
            child = value[key]
            if isinstance(child, (dict, list)):
                sub = emit(child, lines, indent, counter)
                lines.append('%s%s[String::utf8("%s")] = %s;' % (indent, name, cpp(key), sub))
            else:
                lines.append('%s%s[String::utf8("%s")] = %s;' % (indent, name, cpp(key), literal(child)))
        return name
    if isinstance(value, list):
        lines.append("%sArray %s;" % (indent, name))
        for item in value:
            if isinstance(item, (dict, list)):
                sub = emit(item, lines, indent, counter)
                lines.append("%s%s.push_back(%s);" % (indent, name, sub))
            else:
                lines.append("%s%s.push_back(%s);" % (indent, name, literal(item)))
        return name
    raise SystemExit("FATAL: the top level of a schema must be an object or an array")


def emit_group(group):
    """The whole generated span of one group file.

    The span starts with the `// BEGIN generated` line and ends with the
    `// END generated` line, both indented by one tab, so that `--in-place` can
    replace exactly the lines between them (and nothing else) and a second run is
    a no-op. An earlier revision put the markers *inside* each tool's block,
    which made the second run splice a fresh copy of every block next to the
    existing ones (measured: the observation file grew from 30806 to 45155
    bytes); the markers are therefore per *file*, not per tool."""
    contract = json.load(io.open(CONTRACT, encoding="utf-8"))
    rename_map = json.load(io.open(RENAME_MAP, encoding="utf-8"))
    by_name = dict((t["name"], t) for t in contract["result"]["tools"])
    by_new = dict((t["new_name"], t) for t in rename_map["tools"])

    lines = []
    lines.append("\t// BEGIN generated")
    lines.append("\t// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;")
    lines.append("\t//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator")
    lines.append("\t//  --in-place reproduces this span byte for byte.)")
    for tool in GROUPS[group]:
        if tool not in by_name:
            raise SystemExit("FATAL: %s is not in the contract" % tool)
        if tool not in by_new:
            raise SystemExit("FATAL: %s is not in the rename map" % tool)
        entry = by_name[tool]
        meta = by_new[tool]
        # The B4 groups (TASK-019) are the first where a tool's own name and its
        # handler's name differ: `editor_get_test_report` lives in
        # `tools/editor_testing_read.cpp`, so the channel-derived `_tool_...`
        # spelling would be `_tool_get_test_report`. That is the name the file
        # defines, and the explicit map below is what makes it so. Everything
        # else keeps the convention.
        handler = HANDLER_OVERRIDES.get(tool, "_tool_" + tool[len(meta["channel"]) + 1:])
        registration = "pending_handler" if tool in DEFERRED else "handler"

        lines.append("\t{")
        lines.append("\t\tToolBuilder builder(\"%s\", String::utf8(\"%s\"));" % (cpp(tool), cpp(entry["description"])))
        lines.append("")
        counter = [0]
        emit(entry["inputSchema"], lines, "\t\t", counter, name="schema")
        lines.append("")
        lines.append("\t\tbuilder.channel(\"%s\").verb(\"%s\").scope(%s).mutating(%s).schema(schema).%s(%s);"
                     % (cpp(meta["channel"]), cpp(meta["verb"]), SCOPE_CPP[meta["scope"]],
                        "true" if meta["mutating"] else "false", registration, handler))
        lines.append("\t\tbuilder.register_into(r_registry);")
        lines.append("\t}")
    lines.append("\t// END generated")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--group", required=True, choices=sorted(GROUPS))
    parser.add_argument("--in-place", default="")
    args = parser.parse_args()

    fragment = emit_group(args.group)
    if not args.in_place:
        sys.stdout.buffer.write(fragment.encode("utf-8"))
        return

    path = args.in_place
    if not os.path.isabs(path):
        path = os.path.join(MODULE, path)
    text = io.open(path, encoding="utf-8").read()
    begin = text.find("// BEGIN generated")
    # The *last* END marker: the generated span is one contiguous region holding
    # every tool of the group, so the replacement covers all of it and a second
    # run changes nothing.
    end = text.rfind("// END generated")
    if begin < 0 or end < 0 or end < begin:
        raise SystemExit("FATAL: no generated span in %s" % path)
    end += len("// END generated")
    # Both markers sit alone on their line; the replacement starts at the first
    # marker's line and ends at (and includes) the last marker's line.
    line_start = text.rfind("\n", 0, begin) + 1
    line_end = text.find("\n", end)
    if line_end < 0:
        line_end = len(text)
    else:
        line_end += 1
    updated = text[:line_start] + fragment + text[line_end:]
    if updated == text:
        print("the generated span of %s is already up to date (%d bytes)" % (path, len(text)))
        return
    io.open(path, "w", encoding="utf-8", newline="").write(updated)
    print("rewrote the generated span of %s (%d bytes -> %d bytes)" % (path, len(text), len(updated)))


if __name__ == "__main__":
    main()