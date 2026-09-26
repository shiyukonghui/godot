/**************************************************************************/
/*  running_game_test_execution.cpp                                       */
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
#include "running_game_test_execution.h"

#include "../mcp_deferred.h"
#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/input/input.h"
#include "core/input/input_event.h"
#include "core/input/input_map.h"
#include "core/os/os.h"
#include "core/string/ustring.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// Shared pieces of the two drivers
//
// The migration source lives on the **editor** side and talks to the game over a
// `user://` request/response file IPC, waiting with `std::thread::sleep` in a
// `while` loop (`godot_mcp_gdext/src/commands/test.rs:71-147`). Inside the game
// process none of that is available or legal: there is no IPC to talk to, and
// GDR-20 point 3 forbids sleeping on the main thread. Both tools are therefore
// `MCPDeferred::Task`s that advance one step per frame.
//
// The two consequences a caller can observe:
//
//   1. `scene_path` - which named the scene the *editor* should play before the
//      steps ran - has no meaning inside the game that is already running. It is
//      **refused** (`-32602`) rather than silently ignored, because a caller that
//      asked for a scene and got a scenario against some other scene must not
//      read that as success;
//   2. the injected events go into **this process'** `Input`, which is exactly
//      what GDR-21 requires: `editor_simulate_*` drives the editor's `Input` and
//      can never drive the running game.
// ---------------------------------------------------------------------------

// One input event of the contract's `input` step (`action` and/or `keycode`).
// `pressed`/`strength` are the migration source's own two names, plus the
// `frame_delay` it used to pace a sequence.
struct ScenarioEvent {
	enum Kind {
		ACTION,
		KEY,
	};
	Kind kind = ACTION;
	StringName name;
	String keycode_name;
	bool pressed = true;
	double strength = 1.0;
};

// Resolves a key name the way the rest of the module does
// (`find_keycode`, plus "KEY_" tolerated), or `-32602` naming the caller's own
// argument. `p_parameter_name` is `keycode` for both drivers.
static bool _resolve_scenario_keycode(const String &p_key, Key &r_out, MCPToolError &r_error, const String &p_parameter_name) {
	String text = p_key.strip_edges();
	if (text.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter '" + p_parameter_name + "' must not be empty");
		return false;
	}
	// `find_keycode` wants the engine's own spelling and is case sensitive
	// (`keycode_get_string` answers "A", "Escape", ...).
	Key keycode = find_keycode(text);
	if (keycode == Key::NONE && !text.begins_with("KEY_")) {
		keycode = find_keycode("KEY_" + text);
	}
	if (keycode == Key::NONE) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' is not a key name this engine knows: '%s' (try e.g. \"Space\", \"A\", \"Escape\")",
				p_parameter_name, p_key));
		return false;
	}
	r_out = keycode;
	return true;
}

static Ref<InputEventAction> _make_scenario_action(const StringName &p_action, bool p_pressed, double p_strength) {
	Ref<InputEventAction> event;
	event.instantiate();
	event->set_action(p_action);
	event->set_pressed(p_pressed);
	// `set_strength()` clamps to [0, 1]; the answer echoes what the event really
	// carries rather than the caller's raw request.
	//
	// MCP-NARROWING: G24-GAME-SCENARIO-STRENGTH - the `(real_t)` cast below
	// narrows; `_build_scenario_events` judges every `steps[i].strength` with
	// `value_fits_slot(FLOAT32)` in the whole-scenario validation pass that runs
	// **before any step is injected**, so this helper cannot see an unfit value
	// (TASK-023 D-7).
	event->set_strength((real_t)p_strength);
	return event;
}

static Ref<InputEventKey> _make_scenario_key(Key p_keycode, bool p_pressed) {
	Ref<InputEventKey> event;
	event.instantiate();
	event->set_keycode(p_keycode);
	event->set_pressed(p_pressed);
	return event;
}

// The `input` *step* of a scenario: an action with `action`, or a key press with
// `keycode`. Both may be present; both are injected (the migration source's
// `if/else if` chose one or the other, and picking a winner between two explicit
// arguments would silently drop one of them).
static bool _build_scenario_events(const Dictionary &p_step, int p_index, Vector<ScenarioEvent> &r_out, MCPToolError &r_error) {
	const String prefix = vformat("Parameter 'steps[%d]'", p_index);
	bool pressed = true;
	if (!optional_bool(p_step, "pressed", true, pressed, r_error)) {
		return false;
	}
	double strength = 1.0;
	if (!optional_float(p_step, "strength", 1.0, strength, r_error)) {
		return false;
	}
	const Variant action_value = p_step.get("action", Variant());
	const Variant keycode_value = p_step.get("keycode", Variant());
	if (action_value.get_type() == Variant::NIL && keycode_value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params(prefix + " is an 'input' step but carries neither 'action' nor 'keycode'");
		return false;
	}
	if (action_value.get_type() != Variant::NIL) {
		if (action_value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(prefix + ".action must be a string, got " + Variant::get_type_name(action_value.get_type()));
			return false;
		}
		const String action = (String)action_value;
		if (action.strip_edges().is_empty()) {
			r_error = MCPToolError::invalid_params(prefix + ".action must not be empty");
			return false;
		}
		// MCP-NARROWING: G24-GAME-SCENARIO-STRENGTH - `_make_scenario_action`
		// casts the strength to `real_t`; this is the TASK-023 gate that judges it
		// first, and it runs in the whole-scenario validation pass, so a bad step 7
		// of 10 still injects nothing. The engine clamps to [0, 1] *after* the
		// cast, so a value the slot cannot hold would be clamped from `inf`/`0`.
		// `prefix` already spells `Parameter 'steps[i]'`, hence the bare
		// `steps[i].strength` parameter name (the message would otherwise read
		// `Parameter 'Parameter 'steps[1]'.strength'`).
		if (!value_fits_slot(Variant(strength), ValueSlot::FLOAT32, vformat("steps[%d].strength", p_index),
					"the 32-bit float slot the injected action event stores the strength in", r_error)) {
			return false;
		}
		ScenarioEvent event;
		event.kind = ScenarioEvent::ACTION;
		event.name = action;
		event.pressed = pressed;
		event.strength = strength;
		r_out.push_back(event);
	}
	if (keycode_value.get_type() != Variant::NIL) {
		if (keycode_value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(prefix + ".keycode must be a string, got " + Variant::get_type_name(keycode_value.get_type()));
			return false;
		}
		Key keycode = Key::NONE;
		if (!_resolve_scenario_keycode(keycode_value, keycode, r_error, prefix + ".keycode")) {
			return false;
		}
		ScenarioEvent event;
		event.kind = ScenarioEvent::KEY;
		event.keycode_name = keycode_get_string(keycode);
		event.pressed = pressed;
		r_out.push_back(event);
	}
	return true;
}

// Injects one built event into this process' `Input`.
static void _inject_scenario_event(const ScenarioEvent &p_event) {
	Input *input = Input::get_singleton();
	if (input == nullptr) {
		return;
	}
	if (p_event.kind == ScenarioEvent::ACTION) {
		input->parse_input_event(_make_scenario_action(p_event.name, p_event.pressed, p_event.strength));
	} else {
		input->parse_input_event(_make_scenario_key(find_keycode(p_event.keycode_name), p_event.pressed));
	}
}

// ---------------------------------------------------------------------------
// running_game_run_test_scenario (old `run_test_scenario`)
//
// Observable contract (as implemented):
//   * `steps` (array, required, not empty, at most 1000 entries) - each element
//     an object whose `type` is `input`, `wait` or `assert` (the contract's own
//     enum, and the three the migration source implements). The array is
//     validated **completely before any step runs**: a malformed step 7 of 10
//     injects nothing rather than half a scenario;
//   * `scene_path` is refused with `-32602` (see the block above);
//   * an `input` step injects `action` and/or `keycode` with `pressed`
//     (default true) and `strength` (default 1.0);
//   * a `wait` step with `seconds` (a finite number >= 0) waits that long on the
//     frame clock; a `wait` step with `node_path` polls `resolve_game_node` until
//     the node exists or `timeout` (default 5.0) seconds have passed, and answers
//     `found: false` without failing the scenario when it never appears (a wait
//     that is still waiting has no verdict of its own - the assertion that
//     follows is what decides);
//   * an `assert` step with `text` runs the screen-text assertion of
//     `running_game_assert_screen_text` (same `partial`/`case_sensitive` rules,
//     same `source: "control_tree"` search space); an `assert` step with
//     `node_path` + `property` runs the node-state assertion with `expected` and
//     `operator` (default `eq`). An assert step carries exactly one verdict and
//     counts once; an assert step with neither form is an **error**, not a pass;
//   * the structured conclusion is
//     `{"scene_path": <refused|absent>, "total_steps", "completed_steps",
//     "passed", "failed", "errors", "all_passed", "duration_ms", "results"}`,
//     where every entry of `results` is `{"step", "type", ...}` and carries its
//     own `passed` when it is an assertion. `all_passed` is `failed == 0 &&
//     errors == 0 && passed > 0` - a scenario that asserted nothing is **not**
//     "all passed" (that guard is the whole difference between this tool and a
//     tool that always says yes);
//   * each assertion verdict is also recorded in the process' accumulator
//     (`MCPTools::record_test_result`), so an editor-side caller that drives a
//     scenario in this process and then asks `editor_get_test_report` sees the
//     same assertions in the aggregate;
//   * the framework deadline is the scenario's own estimate
//     (`Task::get_timeout_ms`: the sum of the declared waits plus a per-step
//     margin) clamped to the framework ceiling; a scenario that outruns it is
//     `-32000` with `data.timeout_ms`, never a silent truncation.
// ---------------------------------------------------------------------------

// A `wait` step's two forms, resolved up front so the tick has no parsing left.
struct ScenarioStep {
	String type;
	// input
	Vector<ScenarioEvent> events;
	// wait (seconds) / wait (node)
	bool wait_by_time = false;
	double wait_seconds = 0.0;
	String wait_node_path;
	double wait_timeout_seconds = 5.0;
	// assert (text) / assert (node + property)
	bool assert_text = false;
	String assert_text_value;
	bool assert_partial = true;
	bool assert_case_sensitive = true;
	String assert_node_path;
	String assert_property;
	Variant assert_expected;
	String assert_operator = "eq";
};

static bool _step_has_key(const Dictionary &p_step, const String &p_key) {
	return p_step.get(p_key, Variant()).get_type() != Variant::NIL;
}

static bool _parse_scenario_steps(const Array &p_steps, Vector<ScenarioStep> &r_out, MCPToolError &r_error) {
	if (p_steps.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'steps' must not be empty");
		return false;
	}
	if (p_steps.size() > 1000) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'steps' has %d entries; at most 1000 are accepted", p_steps.size()));
		return false;
	}
	for (int i = 0; i < p_steps.size(); i++) {
		const String prefix = vformat("Parameter 'steps[%d]'", i);
		const Variant raw = p_steps[i];
		if (raw.get_type() != Variant::DICTIONARY) {
			r_error = MCPToolError::invalid_params(prefix + " must be an object, got " + Variant::get_type_name(raw.get_type()));
			return false;
		}
		const Dictionary step = raw;
		if (!_step_has_key(step, "type")) {
			r_error = MCPToolError::invalid_params(prefix + " is missing 'type'");
			return false;
		}
		const Variant type_value = step.get("type", Variant());
		if (type_value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(prefix + ".type must be a string, got " + Variant::get_type_name(type_value.get_type()));
			return false;
		}

		ScenarioStep parsed;
		parsed.type = type_value;
		if (parsed.type == "input") {
			if (!_build_scenario_events(step, i, parsed.events, r_error)) {
				return false;
			}
		} else if (parsed.type == "wait") {
			if (_step_has_key(step, "seconds")) {
				if (!optional_float(step, "seconds", 0.0, parsed.wait_seconds, r_error)) {
					return false;
				}
				if (!Math::is_finite(parsed.wait_seconds) || parsed.wait_seconds < 0.0) {
					r_error = MCPToolError::invalid_params(prefix + ".seconds must be a finite number >= 0");
					return false;
				}
				parsed.wait_by_time = true;
			} else if (_step_has_key(step, "node_path")) {
				if (!require_string(step, "node_path", parsed.wait_node_path, r_error)) {
					return false;
				}
				if (!optional_float(step, "timeout", 5.0, parsed.wait_timeout_seconds, r_error)) {
					return false;
				}
				if (!Math::is_finite(parsed.wait_timeout_seconds) || parsed.wait_timeout_seconds <= 0.0) {
					r_error = MCPToolError::invalid_params(prefix + ".timeout must be a finite number > 0");
					return false;
				}
			} else {
				r_error = MCPToolError::invalid_params(prefix + " is a 'wait' step but carries neither 'seconds' nor 'node_path'");
				return false;
			}
		} else if (parsed.type == "assert") {
			if (_step_has_key(step, "text")) {
				if (!require_string(step, "text", parsed.assert_text_value, r_error)) {
					return false;
				}
				if (parsed.assert_text_value.strip_edges().is_empty()) {
					r_error = MCPToolError::invalid_params(prefix + ".text must not be empty");
					return false;
				}
				if (!optional_bool(step, "partial", true, parsed.assert_partial, r_error) ||
						!optional_bool(step, "case_sensitive", true, parsed.assert_case_sensitive, r_error)) {
					return false;
				}
				parsed.assert_text = true;
			} else if (_step_has_key(step, "node_path") && _step_has_key(step, "property")) {
				if (!require_string(step, "node_path", parsed.assert_node_path, r_error) ||
						!require_string(step, "property", parsed.assert_property, r_error)) {
					return false;
				}
				if (!step.has("expected")) {
					r_error = MCPToolError::invalid_params(prefix + " is a node assertion and is missing 'expected'");
					return false;
				}
				parsed.assert_expected = step.get("expected", Variant());
				if (!optional_string(step, "operator", "eq", parsed.assert_operator, r_error)) {
					return false;
				}
				if (!is_valid_assert_operator(parsed.assert_operator)) {
					bool ignored = false;
					evaluate_assertion(parsed.assert_operator, Variant(), Variant(), ignored, r_error);
					return false;
				}
			} else {
				r_error = MCPToolError::invalid_params(prefix + " is an 'assert' step but carries neither 'text' nor 'node_path' + 'property'");
				return false;
			}
		} else {
			r_error = MCPToolError::invalid_params(vformat(
					"%s.type is '%s'; a scenario step is 'input', 'wait' or 'assert'", prefix, parsed.type));
			return false;
		}
		r_out.push_back(parsed);
	}
	return true;
}

// TASK-020 section 4 (D-3): the two verdict builders of this entry. Each one is
// the shared assertion field set (`tools/tool_helpers.*`) - the same object the
// standalone `running_game_assert_*` tools answer with - plus nothing: the
// runner's own `type`/`step` envelope is added by `TestScenarioTask::tick()`,
// which is step metadata and not an assertion field. See the header.
//
// Declared in `MCPTools` like their declarations (`running_game_test_execution.h`)
// because this file carries `using namespace MCPTools;`: a global-scope definition
// of a name the namespace already declares would be an ambiguous overload.
namespace MCPTools {

Dictionary node_state_step_verdict(const String &p_step_node_path, const String &p_resolved_node_path,
		const String &p_property, const String &p_operator, const Variant &p_expected_raw,
		const Variant &p_actual, bool p_passed) {
	return node_state_assertion_fields(p_step_node_path, p_resolved_node_path, p_property, p_operator,
			p_expected_raw, p_actual, p_passed);
}

Dictionary screen_text_step_verdict(const String &p_text, bool p_partial, bool p_case_sensitive,
		const Array &p_visible_texts, const Array &p_visible_elements, bool p_found) {
	return screen_text_assertion_fields(p_text, p_partial, p_case_sensitive, p_visible_texts, p_visible_elements, p_found);
}

} // namespace MCPTools

class TestScenarioTask : public MCPDeferred::Task {
public:
	TestScenarioTask(const Vector<ScenarioStep> &p_steps, uint64_t p_start_ms, uint64_t p_timeout_ms) :
			steps(p_steps), start_ms(p_start_ms), timeout_ms(p_timeout_ms) {}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_frame;
		if (next >= steps.size()) {
					entry["found"] = true;
					entry["node_path"] = String(found->get_path());
					wait_deadline_ms = -1;
				}
			}
		} else {
		entry["type"] = step.type;

		if (step.type == "input") {
			for (int i = 0; i < step.events.size(); i++) {
				_inject_scenario_event(step.events[i]);
			}
			entry["injected"] = step.events.size();
		} else if (step.type == "wait") {
			if (step.wait_by_time) {
				if (wait_deadline_ms < 0) {
					wait_deadline_ms = (int64_t)p_now_ms + (int64_t)(step.wait_seconds * 1000.0 + 0.5);
				}
				if ((int64_t)p_now_ms < wait_deadline_ms) {
					return MCPDeferred::TickResult::pending();
				}
				entry["waited_seconds"] = step.wait_seconds;
				wait_deadline_ms = -1;
			} else {
				Node *root = nullptr;
				SceneTree *tree = nullptr;
				MCPToolError ignored;
				const bool have_scene = game_current_scene(root, tree, ignored);
				Node *found = nullptr;
				if (have_scene) {
					found = resolve_game_node(tree, root, step.wait_node_path);
				}
				if (found == nullptr) {
					if (wait_deadline_ms < 0) {
						wait_deadline_ms = (int64_t)p_now_ms + (int64_t)(step.wait_timeout_seconds * 1000.0 + 0.5);
					}
					if ((int64_t)p_now_ms < wait_deadline_ms) {
						return MCPDeferred::TickResult::pending();
					}
					entry["found"] = false;
					entry["waited_seconds"] = step.wait_timeout_seconds;
					wait_deadline_ms = -1;
				} else {
					entry["found"] = true;
					entry["node_path"] = String(found->get_path());
					wait_deadline_ms = -1;
				}
			}
		} else {
			// assert
			if (step.assert_text) {
				const Dictionary verdict = _run_text_assertion(step);
				entry.merge(verdict, true);
			} else {
				const Dictionary verdict = _run_node_assertion(step);
				entry.merge(verdict, true);
		}
		const Array elements = collect_visible_texts(root);
		const String search_text = p_step.assert_case_sensitive ? p_step.assert_text_value : p_step.assert_text_value.to_lower();
		bool found = false;
		Array visible_texts;
		for (int i = 0; i < elements.size(); i++) {
			const Dictionary element = elements[i];
			const String element_text = element.get("text", String());
			visible_texts.push_back(p_step.assert_case_sensitive ? element_text : element_text.to_lower());
			const String compare_text = p_step.assert_case_sensitive ? element_text : element_text.to_lower();
			const bool hit = p_step.assert_partial ? compare_text.contains(search_text) : compare_text == search_text;
			if (hit && !found) {
				found = true;
				verdict["matched_element"] = element;
			}
		}
		verdict["passed"] = found;
		verdict["visible_texts"] = visible_texts;
		if (!found) {
			verdict["reason"] = vformat("screen text %s '%s' was not found in the %d visible text(s) of the control tree",
					p_step.assert_partial ? "containing" : "equal to", p_step.assert_text_value, visible_texts.size());
		}
		return verdict;
	}

	Dictionary _run_node_assertion(const ScenarioStep &p_step) const {
		Dictionary verdict;
		verdict["node_path"] = p_step.assert_node_path;
		verdict["property"] = p_step.assert_property;
		verdict["operator"] = p_step.assert_operator;

		Node *root = nullptr;
		SceneTree *tree = nullptr;
		MCPToolError ignored;
		if (!game_current_scene(root, tree, ignored)) {
			verdict["passed"] = false;
			verdict["expected"] = serialize_variant(p_step.assert_expected);
			verdict["error"] = "No current scene";
			return verdict;
		}
		Node *node = resolve_game_node(tree, root, p_step.assert_node_path);
		if (node == nullptr || !object_has_property(node, p_step.assert_property)) {
			verdict["passed"] = false;
			verdict["expected"] = serialize_variant(p_step.assert_expected);
			verdict["reason"] = node == nullptr
					? vformat("node '%s' does not exist in the running scene", p_step.assert_node_path)
					: vformat("node '%s' does not have the property '%s'", String(node->get_path()), p_step.assert_property);
			return verdict;
		}
		const Variant actual = node->get(p_step.assert_property);
		// The expectation as it is really compared (see
		// `MCPTools::assertion_expectation_for`): a `{"x":3,"y":4}` object against
		// a vector property is compared as the vector, and echoed as the vector.
		const Variant expected = assertion_expectation_for(actual, p_step.assert_expected);
		verdict["actual"] = serialize_variant(actual);
		verdict["expected"] = serialize_variant(expected);
		verdict["resolved_node_path"] = String(node->get_path());

		bool passed = false;
		MCPToolError error;
		if (!evaluate_assertion(p_step.assert_operator, actual, p_step.assert_expected, passed, error)) {
			verdict["passed"] = false;
			verdict["reason"] = error.message;
			return verdict;
		}
		verdict["passed"] = passed;
		if (!passed) {
			verdict["reason"] = vformat("expected %s %s %s, found %s",
					p_step.assert_property, p_step.assert_operator,
					assertion_text_of(expected), assertion_text_of(actual));
		}
		return verdict;
	}

	Dictionary build_result(uint64_t p_now_ms) const {
		Dictionary result;
		result["total_steps"] = steps.size();
		result["completed_steps"] = results.size();
		result["passed"] = pass_count;
		result["failed"] = fail_count;
		result["errors"] = error_count;
		// `passed > 0` on purpose: a scenario whose steps were all input and wait
		// asserted nothing, and "nothing was asserted" must not be reported as
		// "everything passed".
		result["all_passed"] = fail_count == 0 && error_count == 0 && pass_count > 0;
			return verdict;
		}
		Node *node = resolve_game_node(tree, root, p_step.assert_node_path);
		if (node == nullptr || !object_has_property(node, p_step.assert_property)) {
			verdict["passed"] = false;
			verdict["expected"] = serialize_variant(p_step.assert_expected);
			verdict["reason"] = node == nullptr
					? vformat("node '%s' does not exist in the running scene", p_step.assert_node_path)
					: vformat("node '%s' does not have the property '%s'", String(node->get_path()), p_step.assert_property);
			return verdict;
		}
		const Variant actual = node->get(p_step.assert_property);

		bool passed = false;
		MCPToolError error;
		if (!evaluate_assertion(p_step.assert_operator, actual, p_step.assert_expected, passed, error)) {
			verdict["passed"] = false;
			verdict["expected"] = serialize_variant(p_step.assert_expected);
			verdict["reason"] = error.message;
			return verdict;
		}
		// TASK-020 section 4 (D-3): the compared verdict - the expectation echoed
		// as it was really compared, the actual value, the status and the failure
		// `reason` - is the shared assertion field set, the very object
		// `running_game_assert_node_state` answers with.
		return node_state_step_verdict(p_step.assert_node_path, String(node->get_path()), p_step.assert_property,
				p_step.assert_operator, p_step.assert_expected, actual, passed);
	}

	Dictionary build_result(uint64_t p_now_ms) const {
		Dictionary result;
		result["total_steps"] = steps.size();
		result["completed_steps"] = results.size();
		result["passed"] = pass_count;
		result["failed"] = fail_count;
		result["errors"] = error_count;
		// `passed > 0` on purpose: a scenario whose steps were all input and wait
		// asserted nothing, and "nothing was asserted" must not be reported as
		// "everything passed".
		result["all_passed"] = fail_count == 0 && error_count == 0 && pass_count > 0;
		result["duration_ms"] = (int64_t)(p_now_ms - start_ms);
		result["results"] = results;
		return result;
	}

	Vector<ScenarioStep> steps;
	Array results;
	uint64_t start_ms = 0;
	uint64_t timeout_ms = 0;
	int next = 0;
	int pass_count = 0;
	int fail_count = 0;
	int error_count = 0;
	// < 0 means "no deadline armed"; armed once the first tick of a wait step runs.
	int64_t wait_deadline_ms = -1;
};

static MCPDeferred::Task *_tool_run_test_scenario(const Dictionary &p_args, MCPToolError &r_error) {
	const Variant steps_value = p_args.get("steps", Variant());
	if (steps_value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter: steps");
		return nullptr;
	}
	if (steps_value.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params("Parameter 'steps' must be an array, got " + Variant::get_type_name(steps_value.get_type()));
		return nullptr;
	}
	// `scene_path` belongs to the editor-side migration source (it played a scene
	// before running the steps). Inside the already-running game it cannot mean
	// anything, and silently ignoring it would let a caller believe the scenario
	// ran against the scene it named.
	const Variant scene_path_value = p_args.get("scene_path", Variant());
	if (scene_path_value.get_type() != Variant::NIL) {
		if (scene_path_value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params("Parameter 'scene_path' must be a string, got " + Variant::get_type_name(scene_path_value.get_type()));
			return nullptr;
		}
		const String requested = (String)scene_path_value;
		if (!requested.strip_edges().is_empty()) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'scene_path' ('%s') is not supported by the game-scope runner: the migration source used it to make the *editor* "
					"play a scene before the steps ran, and this tool runs inside the game process that is already running. "
					"Use editor_play_scene (editor endpoint) first, then run the scenario against the running game",
					requested));
			return nullptr;
		}
	}

	Vector<ScenarioStep> steps;
	if (!_parse_scenario_steps((Array)steps_value, steps, r_error)) {
		return nullptr;
	}

	SceneTree *tree = SceneTree::get_singleton();
	if (tree == nullptr) {
			return MCPDeferred::TickResult::done(build_result(p_now_ms, true));
		}

	// The clock comes from `OS`, not from `Time`: the `Time` singleton is null in
	// a `--test` process (see the note in `tools/running_game_assertion.cpp`).
		const uint64_t iteration_start = (uint64_t)OS::get_singleton()->get_ticks_msec();
		const StringName action = actions[iterations % actions.size()];
		input->parse_input_event(_make_scenario_action(action, true, 1.0));
		input->parse_input_event(_make_scenario_action(action, false, 0.0));
		events_sent += 2;
		total_iteration_ms += (int64_t)((uint64_t)OS::get_singleton()->get_ticks_msec() - iteration_start);
		iterations++;

		if (iterations >= count) {
			return MCPDeferred::TickResult::done(build_result(p_now_ms, true));
//     answered at all (`completed: true, crashed: false` is therefore the only
//     reachable answer, and `game_still_running` reports what was observed at the
//     last iteration rather than an assumption);
//   * **there is no assertion in this tool**, which is why it has no `passed`
//     field: a "pass/fail" verdict here would be fabricated. The batch's
//     deliberate-failure demonstration therefore lives in
//     `running_game_run_test_scenario`, whose `assert` steps really can fail; the
//     report carries that scenario's fail evidence;
//   * no `Input` singleton -> `-32000` with a suggestion; no `SceneTree` ->
//     `-32000`.
//
// `crashed` is reported as false because the alternative - a boolean that cannot
// become true in this architecture - is exactly the kind of always-one-value
// field the batch's `fix_implementation_first` work exists to remove. The
// observed facts (`iterations_completed`, `game_still_running`, the elapsed time)
// are what a caller can act on.
// ---------------------------------------------------------------------------
class StressTestTask : public MCPDeferred::Task {
public:
	StressTestTask(const Vector<String> &p_actions, int p_count, uint64_t p_start_ms, uint64_t p_timeout_ms) :
			actions(p_actions), count(p_count), start_ms(p_start_ms), timeout_ms(p_timeout_ms) {}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_frame;
		Input *input = Input::get_singleton();
		if (input == nullptr) {
			return MCPDeferred::TickResult::failed(MCPToolError::not_implemented(
					"input injection in this process (it has no Input singleton)",
					"Run this tool against a running game process"));
		}
		if (iterations >= count) {
			return MCPDeferred::TickResult::done(build_result(p_now_ms, true));
		}

		// The clock comes from `OS`, not from `Time`: the `Time` singleton is
		// null in a `--test` process (see the note in
		// `tools/running_game_assertion.cpp`).
		const uint64_t iteration_start = (uint64_t)OS::get_singleton()->get_ticks_msec();
		const StringName action = actions[iterations % actions.size()];
		input->parse_input_event(_make_scenario_action(action, true, 1.0));
		input->parse_input_event(_make_scenario_action(action, false, 0.0));
		events_sent += 2;
		total_iteration_ms += (int64_t)((uint64_t)OS::get_singleton()->get_ticks_msec() - iteration_start);
		iterations++;

		if (iterations >= count) {
			return MCPDeferred::TickResult::done(build_result(p_now_ms, true));
		}
		return MCPDeferred::TickResult::pending();
	}

	uint64_t get_timeout_ms() const override {
		return timeout_ms;
	}

	String describe() const override {
		return vformat("running %d stress iteration(s)", count);
	}

private:
	Dictionary build_result(uint64_t p_now_ms, bool p_completed) const {
		Dictionary result;
		result["completed"] = p_completed;
		result["crashed"] = false;
		result["iterations"] = count;
		result["iterations_completed"] = iterations;
		result["events_sent"] = events_sent;
		result["elapsed_ms"] = (int64_t)(p_now_ms - start_ms);
		result["average_iteration_ms"] = iterations > 0 ? (double)total_iteration_ms / (double)iterations : 0.0;
		result["game_still_running"] = SceneTree::get_singleton() != nullptr && Input::get_singleton() != nullptr;
		Array action_names;
		for (int i = 0; i < actions.size(); i++) {
			action_names.push_back(String(actions[i]));
		}
		result["actions"] = action_names;
		return result;
	}

	Vector<String> actions;
	int count = 0;
	uint64_t start_ms = 0;
	uint64_t timeout_ms = 0;
	int iterations = 0;
	int64_t events_sent = 0;
	int64_t total_iteration_ms = 0;
};

static MCPDeferred::Task *_tool_run_stress_test(const Dictionary &p_args, MCPToolError &r_error) {
	int64_t count = 10;
	if (!optional_int(p_args, "count", 10, count, r_error)) {
		return nullptr;
	}
	if (count < 1) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'count' must be at least 1, got %d: a stress test of zero iterations is not a test", (int)count));
		return nullptr;
	}
	if (count > 100000) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'count' must be at most 100000, got %d", (int)count));
		return nullptr;
	}

	Vector<String> actions;
	const Variant action_value = p_args.get("action", Variant());
	if (action_value.get_type() != Variant::NIL) {
		if (action_value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params("Parameter 'action' must be a string, got " + Variant::get_type_name(action_value.get_type()));
			return nullptr;
		}
		const String action = (String)action_value;
		if (action.strip_edges().is_empty()) {
			r_error = MCPToolError::invalid_params("Parameter 'action' must not be empty (omit it to rotate over the engine's ui_* actions)");
			return nullptr;
		}
		actions.push_back(action);
	} else {
		// The migration source's rotation, verbatim.
		actions.push_back("ui_up");
		actions.push_back("ui_down");
		actions.push_back("ui_left");
		actions.push_back("ui_right");
		actions.push_back("ui_accept");
	}

	if (Input::get_singleton() == nullptr) {
		r_error = MCPToolError::not_implemented(
				"input injection in this process (it has no Input singleton)",
				"Run this tool against a running game process");
		return nullptr;
	}
	if (SceneTree::get_singleton() == nullptr) {
		r_error = MCPToolError::no_scene();
		return nullptr;
	}

	// One frame per iteration plus a margin for the whole run.
	const uint64_t estimated_ms = (uint64_t)count * 16u + 2000u;
	return memnew(StressTestTask(actions, (int)count, (uint64_t)OS::get_singleton()->get_ticks_msec(), estimated_ms));
}

// ---------------------------------------------------------------------------
// Registration
//
// Order follows docs/tool-groups-b4.json. Every declaration comes from
// docs/tool-rename-map.json (`channel = running_game`, `scope = game`,
// `mutating = true`) and the description and `inputSchema` are a byte-exact copy
// of the entries of docs/tools_list.renamed.json, emitted from that file by
// `scripts/gen_b2_game_schema.py --in-place` and not retyped; re-running the
// generator reproduces this block byte for byte.
// ---------------------------------------------------------------------------

void register_running_game_test_execution_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("running_game_run_test_scenario", String::utf8("运行测试场景并执行一系列测试步骤 wait 步骤的入参名是 seconds（steps[i].seconds，契约 schema 里唯一的等待时长成员），结果里每个 wait 条目的回显字段叫 waited_seconds（真正等到的秒数，如 {\"step\":1,\"type\":\"wait\",\"waited_seconds\":1.5}）；两者在**不同的对象**里，waited_seconds 不是入参（把它写进请求的 step 不生效，seconds 才是入参），入参名与结果字段名都未改动、既有调用不受影响。"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("场景路径，可选 'main', 'current' 或 res:// 路径");
		v1[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("scene_path")] = v1;
		Dictionary v2;
		v2[String::utf8("description")] = String::utf8("测试步骤数组，每个步骤包含 type(input/wait/assert) 和相关参数");
		Dictionary v3;
		Dictionary v4;
		Dictionary v5;
		v5[String::utf8("description")] = String::utf8("操作名称（input 类型使用）");
		v5[String::utf8("type")] = String::utf8("string");
		v4[String::utf8("action")] = v5;
		Dictionary v6;
		v6[String::utf8("description")] = String::utf8("期望值（assert 类型使用）");
		v4[String::utf8("expected")] = v6;
		Dictionary v7;
		v7[String::utf8("description")] = String::utf8("按键代码（input 类型使用）");
		v7[String::utf8("type")] = String::utf8("string");
		v4[String::utf8("keycode")] = v7;
		Dictionary v8;
		v8[String::utf8("description")] = String::utf8("节点路径（wait/assert 类型使用）");
		v8[String::utf8("type")] = String::utf8("string");
		v4[String::utf8("node_path")] = v8;
		Dictionary v9;
		v9[String::utf8("default")] = String::utf8("eq");
		v9[String::utf8("description")] = String::utf8("比较操作符: eq/neq/gt/lt/gte/lte/contains/type_is");
		v9[String::utf8("type")] = String::utf8("string");
		v4[String::utf8("operator")] = v9;
		Dictionary v10;
		v10[String::utf8("default")] = true;
		v10[String::utf8("description")] = String::utf8("input 步骤：注入的事件是按下(true，默认)还是松开(false)");
		v10[String::utf8("type")] = String::utf8("boolean");
		v4[String::utf8("pressed")] = v10;
		Dictionary v11;
		v11[String::utf8("description")] = String::utf8("属性名（assert 类型使用）");
		v11[String::utf8("type")] = String::utf8("string");
		v4[String::utf8("property")] = v11;
		Dictionary v12;
		v12[String::utf8("description")] = String::utf8("等待秒数（wait 类型使用）");
		v12[String::utf8("type")] = String::utf8("number");
		v4[String::utf8("seconds")] = v12;
		Dictionary v13;
		v13[String::utf8("default")] = 1.0;
		v13[String::utf8("description")] = String::utf8("input 步骤作用于 action 时的强度（默认 1.0；引擎会夹到 0..1）");
		v13[String::utf8("type")] = String::utf8("number");
		v4[String::utf8("strength")] = v13;
		Dictionary v14;
		v14[String::utf8("description")] = String::utf8("期望文本（assert 类型使用）");
		v4[String::utf8("type")] = v13;
		v3[String::utf8("properties")] = v4;
		Array v15;
		v15.push_back(String::utf8("type"));
		v3[String::utf8("required")] = v15;
		v3[String::utf8("type")] = String::utf8("object");
		v2[String::utf8("items")] = v3;
		v2[String::utf8("type")] = String::utf8("array");
		v0[String::utf8("steps")] = v2;
		schema[String::utf8("properties")] = v0;
		Array v16;
		v16.push_back(String::utf8("steps"));
		schema[String::utf8("required")] = v16;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("run").scope(MCPToolScope::GAME).mutating(true).schema(schema).pending_handler(_tool_run_test_scenario);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_run_stress_test", String::utf8("运行压力测试，重复执行指定操作 count 次"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("要执行的操作（可选，默认使用方向键）");
		v1[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("action")] = v1;
		Dictionary v2;
		v2[String::utf8("default")] = 10;
		v2[String::utf8("description")] = String::utf8("重复次数");
		v2[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("count")] = v2;
		schema[String::utf8("properties")] = v0;
		Array v3;
		schema[String::utf8("required")] = v3;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("run").scope(MCPToolScope::GAME).mutating(true).schema(schema).pending_handler(_tool_run_stress_test);
		builder.register_into(r_registry);
	}
	// END generated
}
