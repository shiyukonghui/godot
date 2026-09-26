/**************************************************************************/
/*  running_game_assertion.h                                              */
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

#include "core/variant/variant.h"

// TASK-019 section 1, group `running_game_assertion` of
// `docs/tool-groups-b4.json`: the running game's two assertions and its one
// signal observation. All three are `scope = game`, `mutating = false`
// (docs/tool-rename-map.json).
//
// Two of them answer from the frame that read the request and are registered as
// ordinary handlers:
//
//   * `running_game_assert_node_state` - the migration source's comparison,
//     through the one shared `MCPTools::evaluate_assertion`;
//   * `running_game_assert_screen_text` - the migration source's assertion read
//     an `element["text"]` key that its own element collector never wrote
//     (`mcp_runtime_agent.gd:422-428`), so no text ever matched. This
//     implementation asks the engine for each visible Control's own text instead
//     (see `MCPTools::collect_visible_texts`).
//
// The third is a **listen window** (`duration_ms`, default 5000) and is therefore
// registered with `pending_handler()`: collecting emissions over a wall-clock
// window is exactly the family of behaviour GDR-20's deferred channel exists for
// (docs/tool-groups-b4.json's own note names it as a GDR-20 group).
//
// A note on where the assertion records go: these are game-scope tools and an
// assertion made through the game endpoint is recorded in the **game** process'
// accumulator, while `editor_get_test_report` reads the **editor's**. The two
// processes do not share memory, and the report says so (`source`); the
// editor-side assert steps of `running_game_run_test_scenario` and the two
// standalone assertions above are the ones a single-process caller can see
// together.
void register_running_game_assertion_tools(MCPToolRegistry &r_registry);

// ---------------------------------------------------------------------------
// TASK-020 section 4 (D-3) - the standalone entry's assertion verdicts.
//
// The M4 acceptance measured the two entries answering different field sets for
// the same failing assertion: these tools carried `actual`/`expected` (and
// `visible_elements[]`) but no `reason`, while the same assertion inside
// `running_game_run_test_scenario` carried the `reason` too. The two builders
// below are what this entry now merges into its answer, and the scenario runner
// merges the *same* shared field set
// (`MCPTools::node_state_assertion_fields` /
// `MCPTools::screen_text_assertion_fields`, `tools/tool_helpers.*`) into its
// per-step record - so the failure field set (and the reason text) of the two
// entries cannot drift apart.
//
// They are published for the doctest, which asserts exactly that equality by
// calling the two entries' builders; `REPORT-020` section 5 compares the two
// live answers of one failing assertion on the wire.
//
// `p_expected_raw` is the caller's expectation as it arrived; the builder echoes
// it normalized (`assertion_expectation_for`), which is how it was compared.
namespace MCPTools {

Dictionary node_state_tool_verdict(const String &p_resolved_node_path, const String &p_property,
		const String &p_operator, const Variant &p_expected_raw, const Variant &p_actual, bool p_passed);

Dictionary screen_text_tool_verdict(const String &p_text, bool p_partial, bool p_case_sensitive,
		const Array &p_visible_texts, const Array &p_visible_elements, bool p_found);

} // namespace MCPTools
