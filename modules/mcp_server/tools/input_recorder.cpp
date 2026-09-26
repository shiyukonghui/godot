/**************************************************************************/
/*  input_recorder.cpp                                                    */
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
#include "input_recorder.h"

#include "tool_helpers.h"

#include "core/config/project_settings.h"
#include "core/input/input_event.h"
#include "core/os/keyboard.h"
#include "core/os/time.h"
#include "core/variant/dictionary.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// The state machine (see input_recorder.h for why it is separate from the Node).
// ---------------------------------------------------------------------------

namespace {
// One recording at a time: the create/stop pair is two calls against one shared
// session, so the state is process-global. It holds no engine pointer, so
// leaking it across a test is impossible.
bool recording = false;
uint64_t record_start_ms = 0;
// The events in capture order. Kept as `Ref<InputEvent>` rather than as already
// serialised dictionaries: serialising in `stop_events()` is what lets the one
// encoder below stay the single definition of the recording format.
Vector<Ref<InputEvent>> recorded_events;
Vector<uint64_t> recorded_offsets_ms;
// The encoded result of the last recording and how long it lasted, both frozen
// by `stop_events()` and kept until the next `start()`.
Array last_events;
int64_t last_duration_ms = 0;

// The length caps (D59 point 5). `configured_*` is what `set_limits()` writes
// and what `reset()` restores; `session_*` is the pair `start()` resolved for
// the running/last session (project settings win, see the header).
int64_t configured_max_events = MCPInputRecording::DEFAULT_MAX_EVENTS;
int64_t configured_max_duration_ms = MCPInputRecording::DEFAULT_MAX_DURATION_MS;
int64_t session_max_events = MCPInputRecording::DEFAULT_MAX_EVENTS;
int64_t session_max_duration_ms = MCPInputRecording::DEFAULT_MAX_DURATION_MS;
// Set the first time an event has to be dropped because of a cap; after that
// collection stays off for the rest of the session and every further event is
// counted as dropped (so the answer's `dropped` is the real loss, not a guess).
bool session_truncated = false;
int64_t session_dropped = 0;

// One number out of `ProjectSettings`, or `p_fallback` when the key is absent or
// is not a number. Both the section style name and the dotted alias are accepted
// (`mcp_server.cpp`'s `_get_int_setting` does the same for its own settings).
int64_t _project_setting_int(const String &p_name, int64_t p_fallback) {
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr) {
		return p_fallback;
	}
	Vector<String> names;
	names.push_back(p_name);
	const String alias = p_name.replace("/", ".");
	if (alias != p_name) {
		names.push_back(alias);
	}
	for (int i = 0; i < names.size(); i++) {
		if (!settings->has_setting(names[i])) {
			continue;
		}
		const Variant value = settings->get_setting(names[i]);
		if (value.get_type() == Variant::INT || value.get_type() == Variant::FLOAT) {
			const int64_t number = (int64_t)value;
			// `<= 0` is an explicit "no cap", not a cap of zero events.
			return number > 0 ? number : 0;
		}
	}
	return p_fallback;
}
} // namespace

namespace MCPInputRecording {

void set_limits(int64_t p_max_events, int64_t p_max_duration_ms) {
	configured_max_events = p_max_events > 0 ? p_max_events : 0;
	configured_max_duration_ms = p_max_duration_ms > 0 ? p_max_duration_ms : 0;
}

Dictionary limits() {
	Dictionary result;
	result["max_events"] = session_max_events;
	result["max_duration_ms"] = session_max_duration_ms;
	return result;
}

bool was_truncated() {
	return session_truncated;
}

int64_t dropped_event_count() {
	return session_dropped;
}

Dictionary truncation_report() {
	Dictionary result;
	result["truncated"] = session_truncated;
	result["dropped"] = session_dropped;
	result["limits"] = limits();
	return result;
}

bool is_recording() {
	return recording;
}

void start(uint64_t p_now_ms) {
	recording = true;
	record_start_ms = p_now_ms;
	last_duration_ms = 0;
	last_events.clear();
	recorded_events.clear();
	recorded_offsets_ms.clear();
	session_truncated = false;
	session_dropped = 0;
	// Resolve the caps for this session: the project's numbers win over the
	// programmatic configuration, which wins over the compiled defaults.
	session_max_events = _project_setting_int("godot_mcp/recording_max_events", configured_max_events);
	session_max_duration_ms = _project_setting_int("godot_mcp/recording_max_duration_ms", configured_max_duration_ms);
}

void capture(const Ref<InputEvent> &p_event, uint64_t p_now_ms) {
	if (!recording || p_event.is_null()) {
		return;
	}
	// A cap was already reached: the session stays open (so its events can still
	// be collected by `running_game_stop_input_recording`) but nothing more is
	// kept, and the loss is counted rather than hidden.
	if (session_truncated) {
		session_dropped++;
		return;
	}
	const int64_t offset_ms = (int64_t)(p_now_ms - record_start_ms);
	if (session_max_events > 0 && (int64_t)recorded_events.size() >= session_max_events) {
		session_truncated = true;
		session_dropped = 1;
		return;
	}
	// An event exactly at the duration cap is still kept; the cap drops what
	// comes after it.
	if (session_max_duration_ms > 0 && offset_ms > session_max_duration_ms) {
		session_truncated = true;
		session_dropped = 1;
		return;
	}
	recorded_events.push_back(p_event);
	recorded_offsets_ms.push_back((uint64_t)offset_ms);
}

// ---------------------------------------------------------------------------
// The one encoder. `time_ms` leads every entry because it is what the replay
// tool schedules on; the rest is the migration source's key set
// (`mcp_game_inspector_service.gd:1538-1566`).
//
// Every value goes through the module's single `serialize_variant`, exactly like
// the property readers: a raw `Vector2` put into a Dictionary *survives*
// `JSON::stringify` as the **string** `"(10.0, 20.0)"`, so the recording that
// came back over the wire carried `"position":"(10.0, 20.0)"` instead of
// `{"x":10,"y":20}` and the replay tool refused it with
// `'events[2].position' must be a Vector2 or an object with x/y, got String`
// (measured in the TASK-012 evidence run). Serialising here is what makes the
// answer both readable and re-feedable.
// ---------------------------------------------------------------------------

static bool _encode_event(const Ref<InputEvent> &p_event, int64_t p_offset_ms, Dictionary &r_out) {
	Dictionary data;
	data["time_ms"] = p_offset_ms;

	if (const InputEventKey *key = Object::cast_to<InputEventKey>(p_event.ptr())) {
		data["type"] = "key";
		// `keycode` is a *Key* enum value; the human-readable spelling is what
		// survives a round trip through JSON, and `find_keycode()` (inverse of
		// `keycode_get_string()`, core/os/keyboard.h) parses the exact same
		// table back. A key that carries no keycode but a physical one (a
		// layout-independent binding) is spelled under `physical_keycode` so the
		// event is still reconstructible.
		const Key keycode = (Key)key->get_keycode();
		const Key physical = (Key)key->get_physical_keycode();
		data["keycode"] = keycode != Key::NONE ? keycode_get_string(keycode) : String();
		data["physical_keycode"] = physical != Key::NONE ? keycode_get_string(physical) : String();
		data["pressed"] = key->is_pressed();
		data["echo"] = key->is_echo();
		data["shift"] = key->is_shift_pressed();
		data["ctrl"] = key->is_ctrl_pressed();
		data["alt"] = key->is_alt_pressed();
		data["meta"] = key->is_meta_pressed();
		r_out = data;
		return true;
	}

	if (const InputEventMouseButton *button = Object::cast_to<InputEventMouseButton>(p_event.ptr())) {
		data["type"] = "mouse_button";
		data["button"] = (int64_t)button->get_button_index();
		data["pressed"] = button->is_pressed();
		data["double_click"] = button->is_double_click();
		data["position"] = serialize_variant(button->get_position());
		data["global_position"] = serialize_variant(button->get_global_position());
		r_out = data;
		return true;
	}

	if (const InputEventMouseMotion *motion = Object::cast_to<InputEventMouseMotion>(p_event.ptr())) {
		data["type"] = "mouse_motion";
		data["position"] = serialize_variant(motion->get_position());
		data["global_position"] = serialize_variant(motion->get_global_position());
		data["relative"] = serialize_variant(motion->get_relative());
		data["button_mask"] = (int64_t)(int)motion->get_button_mask();
		r_out = data;
		return true;
	}

	if (const InputEventAction *action = Object::cast_to<InputEventAction>(p_event.ptr())) {
		data["type"] = "action";
		data["action"] = action->get_action();
		data["pressed"] = action->is_pressed();
		data["strength"] = action->get_strength();
		r_out = data;
		return true;
	}

	// Anything else (a screen touch, a joypad event, a midi event) is *named*
	// rather than silently dropped: the migration source put it under
	// `"type": "other"` with `as_text()`, and a caller that cannot replay it
	// should still be able to see that it happened. It never reconstructs.
	data["type"] = "other";
	data["class"] = p_event->get_class();
	data["as_text"] = p_event->as_text();
	r_out = data;
	return true;
}

void stop_events(uint64_t p_now_ms) {
	recording = false;
	// The duration is frozen here rather than recomputed by the caller: once
	// `recording` is false the clock no longer has a meaning for this session.
	last_duration_ms = (int64_t)(p_now_ms - record_start_ms);
	last_events.clear();
	for (int i = 0; i < recorded_events.size(); i++) {
		Dictionary encoded;
		if (_encode_event(recorded_events[i], (int64_t)recorded_offsets_ms[i], encoded)) {
			last_events.push_back(encoded);
		}
	}
	// Kept until the next `start()`/`reset()` so that `take_events()` (and
	// therefore the stop answer and the replay tool) can be handed the recording
	// that was just stopped.
}

Array take_events() {
	return last_events;
}

Dictionary empty_type_counts() {
	Dictionary counts;
	counts["key"] = 0;
	counts["mouse_button"] = 0;
	counts["mouse_motion"] = 0;
	counts["action"] = 0;
	counts["other"] = 0;
	return counts;
}

Dictionary event_type_counts() {
	Dictionary counts = empty_type_counts();
	for (int i = 0; i < last_events.size(); i++) {
		const Variant entry = last_events[i];
		if (entry.get_type() != Variant::DICTIONARY) {
			continue;
		}
		const String type = ((Dictionary)entry).get("type", String());
		if (counts.has(type)) {
			counts[type] = (int64_t)counts[type] + 1;
		} else {
			counts["other"] = (int64_t)counts["other"] + 1;
		}
	}
	return counts;
}

int64_t elapsed_ms(uint64_t p_now_ms) {
	if (!recording) {
		return last_duration_ms;
	}
	return (int64_t)(p_now_ms - record_start_ms);
}

bool is_replayable_type(const String &p_type) {
	return p_type == "key" || p_type == "mouse_button" || p_type == "mouse_motion" || p_type == "action";
}

void reset() {
	recording = false;
	record_start_ms = 0;
	last_duration_ms = 0;
	recorded_events.clear();
	recorded_offsets_ms.clear();
	last_events.clear();
	session_truncated = false;
	session_dropped = 0;
	// `reset()` is the "as if the process had just started" state, so the
	// programmatic configuration goes back to the compiled defaults as well.
	configured_max_events = DEFAULT_MAX_EVENTS;
	configured_max_duration_ms = DEFAULT_MAX_DURATION_MS;
	session_max_events = DEFAULT_MAX_EVENTS;
	session_max_duration_ms = DEFAULT_MAX_DURATION_MS;
}

} // namespace MCPInputRecording

// ---------------------------------------------------------------------------
// The tree-attached sink. `Node::input()` is the plain C++ virtual that
// `Node::_call_input()` reaches after the `_input` GDVIRTUAL; see the header for
// why that is the hook this module uses.
// ---------------------------------------------------------------------------

void MCPInputRecorderNode::input(const Ref<InputEvent> &p_event) {
	// `get_device() == DEVICE_ID_INTERNAL` events are engine-generated echoes
	// (an action synthesised from a key, for instance). Recording them would
	// double every keystroke on replay, and `Node::_call_input` skips the
	// `_input` GDVIRTUAL for exactly that device - the same rule is applied here
	// so a recording made by this node matches one a GDScript agent would make.
	if (p_event.is_null() || p_event->get_device() == InputEvent::DEVICE_ID_INTERNAL) {
		return;
	}
	MCPInputRecording::capture(p_event, Time::get_singleton()->get_ticks_msec());
}
