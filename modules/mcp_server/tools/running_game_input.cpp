/**************************************************************************/
/*  running_game_input.cpp                                                */
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
#include "running_game_input.h"

#include "input_recorder.h"
#include "tool_builder.h"
#include "tool_helpers.h"

#include "../mcp_deferred.h"

#include "core/input/input.h"
#include "core/input/input_event.h"
#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/os/keyboard.h"
#include "core/os/time.h"
#include "core/string/string_name.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/gui/button.h"
#include "scene/gui/control.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
// `SceneTree::get_root()` returns `RequiredResult<Window>`, so `Window` has to
// be a complete type here even though only its `Node` half is used.
#include "scene/main/window.h"
// `SceneTree::get_root()` returns `RequiredResult<Window>`, so `Window` has to
// be a complete type here even though only its `Node` half is used.
#include "scene/main/window.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// Group `running_game_input` (docs/tool-groups-b2.json): the four game-scope
// tools that *drive* or *observe* input in the **game process**.
//
// DECISIONS D56 - the split that this file exists to make unmistakable:
//
//   * these four tools run inside the *game* process (`scope = game`), so
//     `Input::get_singleton()->parse_input_event(...)` feeds the running game's
//     own input queue and the caller can observe the game's state change;
//   * the `editor_*` input family (`editor_simulate_input_action`,
//     `editor_simulate_key`, ... of `editor_input_simulation`, and the read-only
//     `editor_get_input_actions` of `editor_input_read`) acts on the **editor
//     process'** own `Input`/`InputMap`. That is the E3 root cause the mapping
//     calls out: injecting into the editor's queue cannot drive a game, because
//     the editor is not the game.
//
// The three recording/playback tools and their migration source:
//   * `running_game_create_input_recording` <- `start_recording`
//     (`mcp_runtime_agent.gd:292` / `mcp_game_inspector_service.gd:1482`);
//   * `running_game_stop_input_recording`   <- `stop_recording`;
//   * `running_game_play_input_recording`   <- `replay_recording`
//     (`mcp_game_inspector_service.gd:1503`);
//   * `running_game_simulate_button_click_by_text` <- `click_button_by_text`
//     (`mcp_game_inspector_service.gd:985`).
//
// Where the two migration sources disagree, this implementation follows the
// *newer* one (`mcp_game_inspector_service.gd`), because it is the one that
// actually reconstructs what it records; the divergences are listed in the
// report (REPORT-012 section 3) and repeated at the tool that has them.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// running_game_create_input_recording (old `start_recording`)
//
// Observable contract (as implemented):
//   * no parameters (the contract's `inputSchema` has an empty property set);
//   * starts a recording in the **game process**: a module-owned Node is added
//     to the tree root and asks for input, so every event the game receives from
//     this frame on is captured with its millisecond offset;
//   * answers `{"recording": true, "message": ...}`;
//   * already recording -> `-32000` with a suggestion (the previous recording is
//     left untouched rather than silently discarded);
//   * no SceneTree / no root window -> `-32000`: there is nothing to receive
//     input in this process.
// ---------------------------------------------------------------------------

// The recorder node of the active recording, held by id and never by pointer:
// the engine may free a node between two frames, and a stale `Node *` here would
// be a dangling dereference exactly like the one TASK-011 removed from the
// property sampler.
static ObjectID recorder_node_id;

static Variant _tool_create_input_recording(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	const uint64_t now_ms = Time::get_singleton()->get_ticks_msec();

	if (MCPInputRecording::is_recording()) {
		r_error = MCPToolError::tool_state(
				"An input recording is already running in this game process",
				"Call running_game_stop_input_recording to collect it before starting a new one (" +
						itos((int)MCPInputRecording::elapsed_ms(now_ms)) + " ms so far)");
		return Variant();
	}

	SceneTree *tree = SceneTree::get_singleton();
	if (tree == nullptr || tree->get_root() == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}

	Node *recorder = memnew(MCPInputRecorderNode);
	recorder->set_name("MCPInputRecorder");
	tree->get_root()->add_child(recorder);
	// `set_process_input(true)` is the whole hook: it puts the node into the
	// viewport's `_vp_input<id>` group, which is the group `Viewport::push_input`
	// calls `_input` on for every event.
	recorder->set_process_input(true);
	recorder_node_id = recorder->get_instance_id();

	MCPInputRecording::start(now_ms);

	Dictionary result;
	result["recording"] = true;
	result["message"] = "Recording started";
	return result;
}

// ---------------------------------------------------------------------------
// running_game_stop_input_recording (old `stop_recording`)
//
// Observable contract (as implemented):
//   * no parameters;
//   * stops the capture, removes the recorder node and answers
//     `{"recording": false, "events": [...], "event_count": N,
//       "duration_ms": <int>, "event_types": {"key": n, ...},
//       "truncated": <bool>, "dropped": <int>, "limits": {...}}`, where each
//     event is `{"type": ..., "time_ms": <offset>, ...}` in capture order;
//   * a recording that reached one of its length caps (D59 point 5) says so:
//     `truncated: true`, `dropped` = how many events were silently-lost-no-more,
//     and `limits` = the caps in force (`0` = no cap on that axis);
//   * an event class the replay tool cannot rebuild (a touch, a joypad event) is
//     *reported* under `event_types.other` instead of being dropped silently;
//   * nothing is recording -> `{"recording": false, "events": [], ...}` - a
//     success, because "there is nothing to collect" is an answer, not a
//     failure (the migration source behaved the same way). It is *also* what a
//     second stop of an already stopped session answers: the collected events
//     are only handed out by the stop that ended the session, and the recorder
//     keeps them for `running_game_play_input_recording` to replay;
//   * the recorder node having disappeared (it was the module's own node, so
//     only a scene teardown can do that) -> that is still a successful stop: the
//     state machine owns the events, the node only fed them.
// ---------------------------------------------------------------------------
static Variant _tool_stop_input_recording(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	(void)r_error;
	const uint64_t now_ms = Time::get_singleton()->get_ticks_msec();
	const bool was_recording = MCPInputRecording::is_recording();

	// Freeing through the deferred queue keeps this call inside the frame that
	// served it (the migration source's `queue_free()`).
	if (recorder_node_id.is_valid()) {
		if (Node *recorder = ObjectDB::get_instance<Node>(recorder_node_id)) {
			recorder->queue_free();
		}
		recorder_node_id = ObjectID();
	}

	if (was_recording) {
		MCPInputRecording::stop_events(now_ms);
	}

	Dictionary result;
	result["recording"] = false;
	if (was_recording) {
		// The session that was running is gathered and kept for the replay: the
		// snapshot is what makes `running_game_play_input_recording` usable with
		// no `events` argument right after this call.
		const Array events = MCPInputRecording::take_events();
		result["events"] = events;
		result["event_count"] = events.size();
		result["duration_ms"] = MCPInputRecording::elapsed_ms(now_ms);
		result["event_types"] = MCPInputRecording::event_type_counts();
		// D59 point 5 / DESIGN-DETAIL section 19.5: a recording that hit its
		// length cap says so, and says how many events were lost and what the
		// caps were, instead of answering a shorter recording that looks
		// complete. Both keys are unconditional, so a caller can always read
		// them without branching on this tool's version.
		const Dictionary truncation = MCPInputRecording::truncation_report();
		result["truncated"] = truncation["truncated"];
		result["dropped"] = truncation["dropped"];
		result["limits"] = truncation["limits"];
		result["message"] = (bool)truncation["truncated"] ? "Recording stopped (a length cap was reached; older events were dropped)" : "Recording stopped";
		return result;
	}

	// Nothing was running. A *second* stop must not hand out the previous
	// session's events again: the answer is an empty one, and the snapshot stays
	// available to the replay only.
	result["events"] = Array();
	result["event_count"] = 0;
	result["duration_ms"] = 0;
	result["event_types"] = MCPInputRecording::empty_type_counts();
	// A stop with nothing running ends no session, so there is no truncation to
	// report; the *caps* are still reported, because they are what the next
	// session will use.
	const Dictionary truncation = MCPInputRecording::truncation_report();
	result["truncated"] = false;
	result["dropped"] = 0;
	result["limits"] = truncation["limits"];
	result["message"] = "No recording was running";
	return result;
}

// ---------------------------------------------------------------------------
// running_game_play_input_recording (old `replay_recording`)
//
// Observable contract (as implemented):
//   * `events` (array, required) - each entry a dictionary with `type`
//     (`key` / `mouse_button` / `mouse_motion` / `action`) and optionally
//     `time_ms` (`time` is accepted as a fallback, in milliseconds too);
//   * `speed` (number, default 1.0): divides every offset, must be positive and
//     finite -> `-32602` otherwise;
//   * the replay **spans frames**: the events are injected through
//     `Input::parse_input_event()` as their adjusted deadlines arrive, so this
//     tool answers through the GDR-20 deferred channel (the first B2 batch that
//     did so for a *write* rather than for an observation);
//   * answers `{"replayed": true, "event_count": N, "injected": N, "speed": s}`;
//   * an event whose `type` is missing or not one of the four -> `-32602` in the
//     frame that read the request, *before* any frame is waited for, so a
//     malformed recording never half-replays;
//   * a `type` the recorder itself could only report (`other`) is refused the
//     same way rather than injected as nothing;
//   * the framework ceiling ends a replay that is still running with `-32000`,
//     `data.suggestion` and `data.timeout_ms`; the task's own deadline is
//     `max(time_ms)/speed + 2 s`, clamped by the framework.
//
// Deviation from `mcp_runtime_agent.gd` (deliberate, and the reason the two
// sources' schemas had to be reconciled): that version recorded `time` in
// *seconds* and its own replay read `"time"` as *milliseconds*, so its
// recordings replayed with every delay divided by 1000. `time_ms` is emitted
// here and read first; a `time` field is still accepted (milliseconds) for a
// caller that kept an old recording.
// ---------------------------------------------------------------------------

// One validated event, ready to inject.
struct ReplayEvent {
	String type;
	double offset_ms = 0.0;
	Ref<InputEvent> event;
};

// A finite, non-negative number out of a JSON value; `p_fallback` when the key
// is absent. Anything else is a `-32602`, not a silent zero.
static bool _event_number(const Dictionary &p_event, const String &p_key, double p_fallback, double &r_out, MCPToolError &r_error, int p_index) {
	const Variant value = p_event.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = p_fallback;
		return true;
	}
	if (value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'events[%d].%s' must be a number, got %s",
				p_index, p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	const double number = (double)value;
	if (!Math::is_finite(number)) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'events[%d].%s' must be finite", p_index, p_key));
		return false;
	}
	r_out = number < 0.0 ? 0.0 : number;
	return true;
}

// TASK-023 D-7 / GDR-24: the numbers of one replayed event reach
// `InputEventMouse*::set_position` / `set_relative` / `InputEventAction::set_strength`
// as `(real_t)`/`(float)` casts. The replay path never runs through
// `coerce_to_property_type`, so the module's one width judgement had no chance to
// see them: `events[0].relative = {"x": 1e300}` was injected as `inf` and a
// `strength` of `1e-300` as `0.0`, both next to a success. The slot is `FLOAT32`
// (not `REAL_T`) so the answer does not depend on the build's `real_t`.
static bool _event_number_fits(const Variant &p_value, const String &p_parameter_name, MCPToolError &r_error) {
	return value_fits_slot(p_value, ValueSlot::FLOAT32, p_parameter_name,
			"the 32-bit float slot this injected input event stores the number in", r_error);
}

static bool _event_bool(const Dictionary &p_event, const String &p_key, bool p_fallback, bool &r_out, MCPToolError &r_error, int p_index) {
	const Variant value = p_event.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = p_fallback;
		return true;
	}
	if (value.get_type() != Variant::BOOL) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'events[%d].%s' must be a boolean, got %s",
				p_index, p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	r_out = value;
	return true;
}

static bool _event_vector2(const Dictionary &p_event, const String &p_key, const Vector2 &p_fallback, Vector2 &r_out, MCPToolError &r_error, int p_index) {
	const Variant value = p_event.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = p_fallback;
		return true;
	}
	if (value.get_type() == Variant::VECTOR2) {
		r_out = value;
		return true;
	}
	if (value.get_type() == Variant::DICTIONARY) {
		const Dictionary components = value;
		double x = 0.0;
		double y = 0.0;
		if (!_event_number(components, "x", 0.0, x, r_error, p_index) || !_event_number(components, "y", 0.0, y, r_error, p_index)) {
			return false;
		}
		// MCP-NARROWING: G24-GAME-INPUT-VECTOR2 - the two `(real_t)` casts below
		// narrow; this is the TASK-023 gate that judges them first.
		if (!_event_number_fits(Variant(x), vformat("events[%d].%s.x", p_index, p_key), r_error) ||
				!_event_number_fits(Variant(y), vformat("events[%d].%s.y", p_index, p_key), r_error)) {
			return false;
		}
		// MCP-NARROWING: G24-GAME-INPUT-VECTOR2 - the cast below is the narrowing
		// the gate above judged.
		r_out = Vector2((real_t)x, (real_t)y);
		return true;
	}
	r_error = MCPToolError::invalid_params(vformat("Parameter 'events[%d].%s' must be a Vector2 or an object with x/y, got %s",
			p_index, p_key, Variant::get_type_name(value.get_type())));
	return false;
}

// Turns one validated event description into an engine event. `false` means the
// type is one the recorder can only *report*.
static bool _reconstruct_event(const Dictionary &p_event, const String &p_type, int p_index, Ref<InputEvent> &r_out, MCPToolError &r_error) {
	if (p_type == "key") {
		Ref<InputEventKey> key;
		key.instantiate();
		String keycode_string;
		if (!optional_string(p_event, "keycode", String(), keycode_string, r_error)) {
			return false;
		}
		String physical_string;
		if (!optional_string(p_event, "physical_keycode", String(), physical_string, r_error)) {
			return false;
		}
		// `find_keycode()` is the inverse of the `keycode_get_string()` the
		// recorder wrote (core/os/keyboard.h): the two share one table, which is
		// what makes the round trip exact rather than approximate.
		if (!keycode_string.is_empty()) {
			key->set_keycode(find_keycode(keycode_string));
		}
		if (!physical_string.is_empty()) {
			key->set_physical_keycode(find_keycode(physical_string));
		}
		bool pressed = true;
		if (!_event_bool(p_event, "pressed", true, pressed, r_error, p_index)) {
			return false;
		}
		bool value = false;
		if (!_event_bool(p_event, "shift", false, value, r_error, p_index)) {
			return false;
		}
		key->set_shift_pressed(value);
		if (!_event_bool(p_event, "ctrl", false, value, r_error, p_index)) {
			return false;
		}
		key->set_ctrl_pressed(value);
		if (!_event_bool(p_event, "alt", false, value, r_error, p_index)) {
			return false;
		}
		key->set_alt_pressed(value);
		if (!_event_bool(p_event, "meta", false, value, r_error, p_index)) {
			return false;
		}
		key->set_meta_pressed(value);
		if (!_event_bool(p_event, "echo", false, value, r_error, p_index)) {
			return false;
		}
		key->set_echo(value);
		key->set_pressed(pressed);
		r_out = key;
		return true;
	}

	if (p_type == "mouse_button") {
		Ref<InputEventMouseButton> button;
		button.instantiate();
		double index = 1.0;
		if (!_event_number(p_event, "button", 1.0, index, r_error, p_index)) {
			return false;
		}
		bool pressed = true;
		if (!_event_bool(p_event, "pressed", true, pressed, r_error, p_index)) {
			return false;
		}
		bool double_click = false;
		if (!_event_bool(p_event, "double_click", false, double_click, r_error, p_index)) {
			return false;
		}
		Vector2 position;
		// MCP-NARROWING: G24-GAME-INPUT-DEFAULT - the three `Vector2()` defaults
		// below are the zero vector and name no caller value; the numbers a caller
		// does send go through `_event_vector2`, which is gated (TASK-023 D-7).
		if (!_event_vector2(p_event, "position", Vector2(), position, r_error, p_index)) {
			return false;
		}
		Vector2 global;
		if (!_event_vector2(p_event, "global_position", position, global, r_error, p_index)) {
			return false;
		}
		button->set_button_index((MouseButton)(int)index);
		button->set_pressed(pressed);
		button->set_double_click(double_click);
		button->set_position(position);
		button->set_global_position(global);
		r_out = button;
		return true;
	}

	if (p_type == "mouse_motion") {
		Ref<InputEventMouseMotion> motion;
		motion.instantiate();
		Vector2 position;
		// MCP-NARROWING: G24-GAME-INPUT-DEFAULT - the three `Vector2()` defaults
		// below are the zero vector and name no caller value; the numbers a caller
		// does send go through `_event_vector2`, which is gated (TASK-023 D-7).
		if (!_event_vector2(p_event, "position", Vector2(), position, r_error, p_index)) {
			return false;
		}
		Vector2 global;
		if (!_event_vector2(p_event, "global_position", position, global, r_error, p_index)) {
			return false;
		}
		Vector2 relative;
		// MCP-NARROWING: G24-GAME-INPUT-DEFAULT - see the marker on the
		// `mouse_button` branch above: `Vector2()` is the zero-vector default.
		if (!_event_vector2(p_event, "relative", Vector2(), relative, r_error, p_index)) {
			return false;
		}
		double mask = 0.0;
		if (!_event_number(p_event, "button_mask", 0.0, mask, r_error, p_index)) {
			return false;
		}
		motion->set_position(position);
		motion->set_global_position(global);
		motion->set_relative(relative);
		motion->set_button_mask((BitField<MouseButtonMask>)(int64_t)mask);
		r_out = motion;
		return true;
	}

	if (p_type == "action") {
		Ref<InputEventAction> action;
		action.instantiate();
		String name;
		if (!optional_string(p_event, "action", String(), name, r_error)) {
			return false;
		}
		if (name.is_empty()) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'events[%d].action' is required for a 'action' event", p_index));
			return false;
		}
		bool pressed = true;
		if (!_event_bool(p_event, "pressed", true, pressed, r_error, p_index)) {
			return false;
		}
		double strength = 1.0;
		if (!_event_number(p_event, "strength", 1.0, strength, r_error, p_index)) {
			return false;
		}
		action->set_action(name);
		action->set_pressed(pressed);
		// MCP-NARROWING: G24-GAME-INPUT-ACTION-STRENGTH - the `(float)` cast below
		// narrows; this is the TASK-023 gate that judges it first.
		if (!_event_number_fits(Variant(strength), vformat("events[%d].strength", p_index), r_error)) {
			return false;
		}
		// MCP-NARROWING: G24-GAME-INPUT-ACTION-STRENGTH - the cast below is the
		// narrowing the gate above judged.
		action->set_strength((float)strength);
		r_out = action;
		return true;
	}

	r_error = MCPToolError::invalid_params(vformat(
			"Parameter 'events[%d].type' is '%s'; the replay can inject 'key', 'mouse_button', 'mouse_motion' or 'action'",
			p_index, p_type));
	return false;
}

// The deferred half: injects the events as their deadlines arrive. One `tick()`
// per frame, no sleeping, no nested loop - the whole frame clock is the
// framework's (GDR-20 point 3).
class InputReplayTask : public MCPDeferred::Task {
public:
	InputReplayTask(const Vector<ReplayEvent> &p_events, double p_speed, uint64_t p_start_ms, uint64_t p_timeout_ms) :
			events(p_events), speed(p_speed), start_ms(p_start_ms), timeout_ms(p_timeout_ms) {}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_frame;
		while (next < events.size()) {
			const double adjusted_ms = events[next].offset_ms / speed;
			if ((double)(p_now_ms - start_ms) + 0.5 < adjusted_ms) {
				// Not due yet. Deliberately not "inject it now to make
				// progress": the timeline *is* the contract.
				return MCPDeferred::TickResult::pending();
			}
			Input::get_singleton()->parse_input_event(events[next].event);
			injected++;
			next++;
		}

		Dictionary result;
		result["replayed"] = true;
		result["event_count"] = events.size();
		result["injected"] = injected;
		result["speed"] = speed;
		return MCPDeferred::TickResult::done(result);
	}

	uint64_t get_timeout_ms() const override {
		return timeout_ms;
	}

	String describe() const override {
		return vformat("replaying %d input event(s) at speed %s", events.size(), rtos(speed));
	}

private:
	Vector<ReplayEvent> events;
	double speed = 1.0;
	uint64_t start_ms = 0;
	uint64_t timeout_ms = 0;
	int next = 0;
	int injected = 0;
};

static MCPDeferred::Task *_tool_play_input_recording(const Dictionary &p_args, MCPToolError &r_error) {
	// `events` is `required` in the contract, but a caller very often wants to
	// replay *the recording it just stopped*. When the parameter is absent the
	// last recording of this game process is used instead, so the round trip
	// `create -> stop -> play` needs no byte-for-byte copy of the answer in
	// between; when it is present it is used verbatim. Only having neither is an
	// error, and the message says which two ways there are to supply events.
	Variant raw_events = p_args.get("events", Variant());
	if (raw_events.get_type() == Variant::NIL) {
		raw_events = MCPInputRecording::take_events();
	}
	if (raw_events.get_type() == Variant::ARRAY && ((Array)raw_events).is_empty()) {
		r_error = MCPToolError::invalid_params(
				"Parameter 'events' must not be empty: there is nothing to replay (pass the events, or call running_game_stop_input_recording in this game process first)");
		return nullptr;
	}
	if (!raw_events.is_array()) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'events' must be an array, got %s",
				Variant::get_type_name(raw_events.get_type())));
		return nullptr;
	}
	const Array events = raw_events;

	double speed = 1.0;
	{
		const Variant raw_speed = p_args.get("speed", Variant());
		if (raw_speed.get_type() != Variant::NIL) {
			if (raw_speed.get_type() != Variant::FLOAT && raw_speed.get_type() != Variant::INT) {
				r_error = MCPToolError::invalid_params(vformat("Parameter 'speed' must be a number, got %s",
						Variant::get_type_name(raw_speed.get_type())));
				return nullptr;
			}
			speed = (double)raw_speed;
		}
		if (!Math::is_finite(speed) || speed <= 0.0) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'speed' must be a positive finite number, got %s", (String)raw_speed));
			return nullptr;
		}
	}

	Vector<ReplayEvent> parsed;
	parsed.resize(events.size());
	double max_offset_ms = 0.0;
	for (int i = 0; i < events.size(); i++) {
		const Variant raw = events[i];
		if (raw.get_type() != Variant::DICTIONARY) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'events[%d]' must be an object, got %s",
					i, Variant::get_type_name(raw.get_type())));
			return nullptr;
		}
		const Dictionary entry = raw;
		String type;
		if (!require_string(entry, "type", type, r_error)) {
			return nullptr;
		}
		if (!MCPInputRecording::is_replayable_type(type)) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'events[%d].type' is '%s'; the replay can inject 'key', 'mouse_button', 'mouse_motion' or 'action'",
					i, type));
			return nullptr;
		}
		// `time_ms` first; `time` in milliseconds as the documented fallback for
		// a recording made by the older migration source.
		double offset_ms = 0.0;
		if (entry.has("time_ms")) {
			if (!_event_number(entry, "time_ms", 0.0, offset_ms, r_error, i)) {
				return nullptr;
			}
		} else if (!_event_number(entry, "time", 0.0, offset_ms, r_error, i)) {
			return nullptr;
		}

		Ref<InputEvent> event;
		if (!_reconstruct_event(entry, type, i, event, r_error)) {
			return nullptr;
		}
		parsed.write[i].type = type;
		parsed.write[i].offset_ms = offset_ms;
		parsed.write[i].event = event;
		max_offset_ms = MAX(max_offset_ms, offset_ms);
	}

	if (parsed.is_empty()) {
		// Unreachable: an empty array is refused above. Kept as a -32603 rather
		// than a silent success so that a future change to the guard above can
		// not turn "nothing to replay" into a deferred task that does nothing.
		r_error = MCPToolError::internal("the replay task was built with no events");
		return nullptr;
	}

	// The task's own deadline is the last event's adjusted offset plus a 2 s
	// settle window; the framework clamps it to its configured ceiling (30 s by
	// default), so a long recording is ended by the framework with `-32000` +
	// `data.timeout_ms` rather than hanging.
	const uint64_t timeout_ms = (uint64_t)(max_offset_ms / speed) + 2000;
	return memnew(InputReplayTask(parsed, speed, Time::get_singleton()->get_ticks_msec(), timeout_ms));
}

// ---------------------------------------------------------------------------
// running_game_simulate_button_click_by_text (old `click_button_by_text`)
//
// Observable contract (as implemented):
//   * `text` (string, required; blank -> `-32602`), `partial` (boolean, default
//     true);
//   * the *game's* current scene is searched depth first for a visible `Button`
//     whose text contains (partial) or equals (exact) the argument, both sides
//     lowercased and edge-stripped - the migration source's rule verbatim;
//   * the match's `pressed` signal is emitted, and the answer is
//     `{"clicked": true, "button_path": <absolute path>, "button_text": ...,
//       "position": {"x": .., "y": ..}}`;
//   * the button text and path are captured *before* the emission: a `pressed`
//     handler may change the scene, and reading the node afterwards would report
//     (or crash on) a freed node - a defect the newer migration source already
//     fixed with a comment of its own
//     (`mcp_game_inspector_service.gd:1006-1008`);
//   * no current scene -> `-32000`; no matching button -> `-32001` with a
//     suggestion;
//   * **immediate, not deferred**: emitting a signal is synchronous, and the
//     handler's own effect is observable in the same frame. The deferred channel
//     exists for tools whose *observable behaviour* is the passage of frames
//     (docs/tool-groups-b2.json), which is not this one.
// ---------------------------------------------------------------------------

static Button *_find_button_by_text(Node *p_node, const String &p_text, bool p_partial) {
	Button *button = Object::cast_to<Button>(p_node);
	// `Control::is_visible_in_tree()` rather than `Node::is_visible()`: a Button
	// under a hidden parent is not on screen, and the migration source's
	// `node.visible` check on a GDScript node is the local flag only.
	if (button != nullptr && button->is_visible_in_tree()) {
		const String button_text = button->get_text().to_lower().strip_edges();
		const String search_text = p_text.to_lower().strip_edges();
		if (p_partial ? button_text.contains(search_text) : button_text == search_text) {
			return button;
		}
	}
	const int child_count = p_node->get_child_count();
	for (int i = 0; i < child_count; i++) {
		Button *found = _find_button_by_text(p_node->get_child(i), p_text, p_partial);
		if (found != nullptr) {
			return found;
		}
	}
	return nullptr;
}

static Variant _tool_simulate_button_click_by_text(const Dictionary &p_args, MCPToolError &r_error) {
	String text;
	if (!require_string(p_args, "text", text, r_error)) {
		return Variant();
	}
	if (text.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'text' must not be empty");
		return Variant();
	}
	bool partial = true;
	if (!optional_bool(p_args, "partial", true, partial, r_error)) {
		return Variant();
	}

	Node *root = nullptr;
	SceneTree *tree = nullptr;
	if (!game_current_scene(root, tree, r_error)) {
		return Variant();
	}

	Button *button = _find_button_by_text(root, text, partial);
	if (button == nullptr) {
		r_error = MCPToolError::not_found(vformat("A visible Button whose text %s '%s'", partial ? "contains" : "equals", text),
				"Use running_game_find_ui_elements to list the game's Control nodes, or retry with partial=true");
		return Variant();
	}

	// Captured before the signal: the handler may free the button (a scene
	// transition) and `Control::get_global_rect()` on a freed node is a crash,
	// not a stale value.
	const String button_text = button->get_text();
	const String button_path = String(button->get_path());
	const Vector2 center = button->get_global_rect().get_center();

	button->emit_signal(SNAME("pressed"));

	Dictionary result;
	result["clicked"] = true;
	result["button_text"] = button_text;
	result["button_path"] = button_path;
	Dictionary position;
	position["x"] = center.x;
	position["y"] = center.y;
	result["position"] = position;
	return result;
}

// ---------------------------------------------------------------------------
// Registration
//
// The declaration order follows docs/tool-groups-b2.json; channel, verb, scope
// and mutating come from docs/tool-rename-map.json and the description and
// `inputSchema` are a byte-exact copy of docs/tools_list.renamed.json, emitted
// by `scripts/gen_b2_game_schema.py` (re-running it reproduces this block).
// ---------------------------------------------------------------------------

void register_running_game_input_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("running_game_create_input_recording", String::utf8("开始录制游戏中的输入事件（键盘、鼠标等）"));

		Dictionary schema;
		Dictionary v0;
		schema[String::utf8("properties")] = v0;
		Array v1;
		schema[String::utf8("required")] = v1;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("create").scope(MCPToolScope::GAME).mutating(true).schema(schema).handler(_tool_create_input_recording);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_stop_input_recording", String::utf8("停止录制并返回已录制的输入事件数据"));

		Dictionary schema;
		Dictionary v0;
		schema[String::utf8("properties")] = v0;
		Array v1;
		schema[String::utf8("required")] = v1;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("stop").scope(MCPToolScope::GAME).mutating(true).schema(schema).handler(_tool_stop_input_recording);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_play_input_recording", String::utf8("回放之前录制的输入事件序列 缺省 `events` 时，回放本游戏进程内最近一次 running_game_stop_input_recording 的录制；若本进程没有可用录制则返回 -32602。"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("要回放的事件数组");
		v1[String::utf8("type")] = String::utf8("array");
		v0[String::utf8("events")] = v1;
		Dictionary v2;
		v2[String::utf8("default")] = 1.0;
		v2[String::utf8("description")] = String::utf8("回放速度倍率");
		v2[String::utf8("type")] = String::utf8("number");
		v0[String::utf8("speed")] = v2;
		schema[String::utf8("properties")] = v0;
		Array v3;
		schema[String::utf8("required")] = v3;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("play").scope(MCPToolScope::GAME).mutating(true).schema(schema).pending_handler(_tool_play_input_recording);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_simulate_button_click_by_text", String::utf8("通过按钮文本点击运行中游戏的按钮"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("default")] = true;
		v1[String::utf8("description")] = String::utf8("是否使用部分匹配");
		v1[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("partial")] = v1;
		Dictionary v2;
		v2[String::utf8("description")] = String::utf8("按钮上显示的文本");
		v2[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("text")] = v2;
		schema[String::utf8("properties")] = v0;
		Array v3;
		v3.push_back(String::utf8("text"));
		schema[String::utf8("required")] = v3;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("simulate").scope(MCPToolScope::GAME).mutating(true).schema(schema).handler(_tool_simulate_button_click_by_text);
		builder.register_into(r_registry);
	}
	// END generated
}
