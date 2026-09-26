/**************************************************************************/
/*  running_game_test_execution.h                                         */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/
#pragma once

#include "../tool_registry.h"

// TASK-019 section 1, group `running_game_test_execution` of
// `docs/tool-groups-b4.json`: the two scenario drivers, and the only
// `mutating = true` group of B4 (they *drive* the running game).
//
// Both are inherently multi-frame and are registered with `pending_handler()`
// (GDR-20):
//
//   * `running_game_run_test_scenario` walks the caller's `steps` array - input
//     presses, waits and assertions - one step at a time, and a `wait` step is
//     the whole point of the tool. Running the array inside the frame that read
//     the request would collapse every wait to zero, which is the counterexample
//     GDR-20 was written from. The answer is the **structured conclusion** the
//     batch exists for: per-step results plus `all_passed` / `passed` / `failed`
//     / `errors` / `duration_ms`;
//   * `running_game_run_stress_test` repeats one action `count` times across
//     frames and reports what it observed (`completed`, `crashed`,
//     `iterations`, `events_sent`, timings). It has no assertion to fail by
//     construction - its verdict *is* "the game survived" - so the batch's
//     deliberate-failure demonstration lives in `run_test_scenario`, whose
//     `assert` steps can fail and are counted.
//
// The migration source put the scenario in the **editor** and talked to the game
// over a `user://` request/response file IPC, sleeping on the editor's main
// thread while it waited (`test.rs:71-147`: `std::thread::sleep` in a
// `while` loop). None of that survives inside the game process: there is no IPC
// left, and `sleep` on the main thread is forbidden (GDR-20 point 3), so the
// drivers became deferred tasks in the game process. The observable consequence
// is recorded in the report: the *editor* no longer coordinates the scenario, so
// `scene_path` - which named the scene the editor should play before the steps
// ran - has no meaning here and is **refused** rather than ignored.
//
// Both are `scope = game`, served by the game endpoint (9889) and refused with
// `-32601` by the editor endpoint.
void register_running_game_test_execution_tools(MCPToolRegistry &r_registry);
// `-32601` by the editor endpoint.
void register_running_game_test_execution_tools(MCPToolRegistry &r_registry);

// ---------------------------------------------------------------------------
// TASK-020 section 4 (D-3) - one `assert` step's verdict.
//
// The M4 acceptance measured the same failing assertion answering two different
// shapes depending on the entry: the standalone tools had no `reason`, while this
// runner's per-step record had one. The two builders below are this entry's half
// of the fix: the per-step verdict is the **shared** assertion field set
// (`MCPTools::node_state_assertion_fields` /
// `MCPTools::screen_text_assertion_fields`, `tools/tool_helpers.*`) - the same
// object the standalone tools merge into their answer - and the runner adds only
// its own `type`/`step` envelope on top. `REPORT-020` section 5 compares the two
// live answers of one failing assertion, and the doctest asserts the two field
// sets are equal.
//
// `p_step_node_path` is the path the step asked for (`node_path`, echoed as the
// caller wrote it); `p_resolved_node_path` is the node the runner really found.
// ---------------------------------------------------------------------------
namespace MCPTools {

Dictionary node_state_step_verdict(const String &p_step_node_path, const String &p_resolved_node_path,
		const String &p_property, const String &p_operator, const Variant &p_expected_raw,
		const Variant &p_actual, bool p_passed);

Dictionary screen_text_step_verdict(const String &p_text, bool p_partial, bool p_case_sensitive,
		const Array &p_visible_texts, const Array &p_visible_elements, bool p_found);

// ---------------------------------------------------------------------------
// TASK-092 (item B3): the scenario driver's core, separated from the tool's
// statement about its environment.
//
// The state machine (`TestScenarioTask`) was only reachable through
// `running_game_run_test_scenario`, and that tool refuses with `-32000` in any
// process without a `SceneTree` - which every doctest is. That is why TASK-090
// had to declare "`in_input_map` has no doctest" and pin the field with one live
// trace instead. Exporting the core is the same move TASK-090 made for the
// GDScript executor ("the core with the mount point passed in"), and it keeps the
// two things apart on purpose:
//
//   * **what the request means** (the step validation, the deadline estimate, the
//     task itself) - this function, testable with no engine state at all;
//   * **whether this process can serve it** - the `SceneTree` requirement, which
//     stays a property of the *tool*: `running_game_run_test_scenario` passes
//     `p_require_scene_tree = true`, an in-process caller that already knows what
//     it is doing passes `false`.
//
// `p_now_ms` is the caller's clock (`OS::get_ticks_msec()` in the tool), so a
// doctest never depends on wall time. Ownership of the returned task transfers to
// the caller, exactly like `pending_handler` does.
// ---------------------------------------------------------------------------
MCPDeferred::Task *create_test_scenario_task(const Dictionary &p_args, uint64_t p_now_ms,
		bool p_require_scene_tree, MCPToolError &r_error);

} // namespace MCPTools