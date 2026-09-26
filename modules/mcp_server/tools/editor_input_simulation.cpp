/**************************************************************************/
/*  editor_input_simulation.cpp                                           */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/
#include "editor_input_simulation.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "../mcp_deferred.h"

#include "core/input/input.h"
#include "core/input/input_enums.h"
#include "core/input/input_event.h"
#include "core/input/input_map.h"
#include "core/math/math_funcs.h"
#include "core/object/object.h"
#include "core/os/keyboard.h"
#include "core/string/ustring.h"
#include "core/templates/list.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// Group `editor_input_simulation` (docs/tool-groups-b2.json): B2's last group,
// six tools, every one of them `channel = editor`, `scope = editor`,
// `mutating = true`:
//
//   editor_simulate_input_action     <- `simulate_action`     (input.rs:29/94)
//   editor_simulate_key              <- `simulate_key`        (input.rs:13/60)
//   editor_simulate_mouse_click      <- `simulate_mouse_click`(input.rs:20/73)
//   editor_simulate_mouse_move       <- `simulate_mouse_move` (input.rs:26/85)
//   editor_simulate_input_sequence   <- `simulate_sequence`   (input.rs:39/128)
//   editor_add_input_action          <- `set_input_action`    (input.rs:35/113)
//
// **What these tools are, and what they are not** (DESIGN-DETAIL section 19 /
// GDR-21, decided as D59 after TASK-012's two-sided wire evidence):
//
//   * they inject synthetic events into the **editor process'** own `Input`
//     queue (`Input::get_singleton()->parse_input_event()`) and write the
//     **editor process'** own `InputMap` singleton. That is exactly what the
//     rename map's `reason` for every one of them says, e.g. for
//     `editor_simulate_key`: "input.rs only parses the event into the editor
//     process' Input and never calls send_game_command, so it never reaches the
//     game process - hence the `editor_` channel";
//   * they therefore **cannot drive a running game**, which is the old
//     GDExtension architecture's E3 root cause. Driving a game is the job of the
//     `running_game_*` input tools, which are served by the *game* endpoint and
//     are absent from the editor endpoint (and vice versa). The boundary is not
//     a claim in a document: REPORT-013 measures it in one run - an event
//     injected here is counted by an `EditorPlugin` inside the editor process
//     and leaves the very same counters of a game running on the test port
//     untouched;
//   * `editor_add_input_action` writes the editor's `InputMap` **in memory
//     only**. It does not persist to `ProjectSettings` / `project.godot` - the
//     migration source did not either - and every answer says `persisted: false`
//     so a caller cannot mistake it for a project edit;
//   * every success answer carries `"target": "editor"`: the answer states which
//     process' input was touched, because that is the one thing a caller of a
//     "simulate" tool must not have to guess.
//
// **Guards.** The compile-time half is `MCP_EDITOR_TOOLS_ENABLED` (defined iff
// the engine was built with `TOOLS_ENABLED`); the runtime half is the tool's
// `scope = EDITOR`, which is what keeps the six out of a game process' table
// altogether (GDR-19 section 17.3) and therefore out of the game endpoint's
// `tools/list` (the end-to-end half, measured in REPORT-013). There is
// deliberately no `is_editor_process()` test inside the handlers as well: the
// registration already refuses the tool in a game process, and a second check
// would only be a second definition of the same rule. What *is* checked is the
// engine prerequisite - the `Input` / `InputMap` singleton of this process - so
// that a process without one answers `-32000` with a suggestion instead of
// dereferencing a null pointer.
//
// Migration source (semantic reference, read-only):
// `godot_mcp_gdext/src/commands/input.rs`. `addons/godot_mcp/commands/
// input_commands.gd` is the *other* migration source and disagrees with it in
// two ways that are recorded in REPORT-013 section 3: it wrote the events into
// `user://mcp_input_commands` for the **game** side to read (the file-IPC that
// GDR-21 removes), and its `simulate_mouse_click` auto-released the button. Both
// are deliberately not reproduced: the first is the architecture this module
// exists to replace, and the second would make one call inject two events while
// the contract's own `pressed` parameter exists precisely so the caller decides.
// ---------------------------------------------------------------------------

// The engine's own `MouseButton` range, used to refuse a button index that
// `mouse_button_to_mask()` would shift into undefined behaviour
// (`1 << (button - 1)`, core/input/input_enums.h:156). The migration source
// passed whatever integer it was given straight into the event.
static const int64_t MOUSE_BUTTON_MIN = (int64_t)MouseButton::LEFT; // 1
static const int64_t MOUSE_BUTTON_MAX = (int64_t)MouseButton::MB_XBUTTON2; // 9

// ---------------------------------------------------------------------------
// The runtime prerequisite: this process' `Input` / `InputMap` singleton.
//
// `Input` is created by `Main::setup2` in every engine process, so in a real
// editor these never fail. They exist so that the tools are *total*: the doctest
// binary's `[MCPServer]` cases run without those singletons, and a
// `--check-only` run would have neither, and a null dereference there is a crash
// rather than an answer.
// ---------------------------------------------------------------------------
static Input *_editor_input(MCPToolError &r_error) {
#ifndef MCP_EDITOR_TOOLS_ENABLED
	r_error = MCPToolError::not_implemented("input simulation in a game build (the editor input tools are not compiled in)",
			"Run this tool against the editor endpoint of an editor build");
	return nullptr;
#else
	Input *input = Input::get_singleton();
	if (input == nullptr) {
		r_error = MCPToolError::not_implemented("input simulation in this process (it has no Input singleton)",
				"Run this tool against a running Godot editor; a --test or --check-only process has no input queue");
		return nullptr;
	}
	return input;
#endif
}

static InputMap *_editor_input_map(MCPToolError &r_error) {
#ifndef MCP_EDITOR_TOOLS_ENABLED
	r_error = MCPToolError::not_implemented("input-map editing in a game build (the editor input tools are not compiled in)",
			"Run this tool against the editor endpoint of an editor build");
	return nullptr;
#else
	InputMap *map = InputMap::get_singleton();
	if (map == nullptr) {
		r_error = MCPToolError::not_implemented("input-map editing in this process (it has no InputMap singleton)",
				"Run this tool against a running Godot editor; a --test or --check-only process has no InputMap");
		return nullptr;
	}
	return map;
#endif
}

// ---------------------------------------------------------------------------
// Key resolution.
//
// The migration source calls `OS.find_keycode_from_string()` and injects
// whatever comes back - including `KEY_NONE` for a name the engine does not know,
// which produces a key event that no `_input` listener can tell from a stray.
// "A typo silently simulates nothing" is exactly the failure mode the module
// refuses, so an unknown name is a `-32602` here.
//
// Two spellings are accepted, because the two migration sources accepted one
// each: the engine's own key names ("A", "Space", "Escape", "F9", and the
// modifier form "Ctrl+A") via `find_keycode()`, and the GDScript constant
// spelling "KEY_A" that the addon's `_create_key_event` handled by stripping the
// prefix (it resolved it through `ClassDB`, which is not available to a C++
// module in the same way; the plain name is).
// ---------------------------------------------------------------------------
static bool _resolve_keycode(const String &p_text, Key &r_out, MCPToolError &r_error, const String &p_parameter) {
	String text = p_text.strip_edges();
	if (text.is_empty()) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must not be empty", p_parameter));
		return false;
	}
	Key code = find_keycode(text);
	if (code == Key::NONE && text.length() > 4 && text.substr(0, 4) == "KEY_") {
		code = find_keycode(text.substr(4));
	}
	if (code == Key::NONE) {
		r_error = MCPToolError::invalid_params(vformat(
	r_out = code;
	return true;
}

// One optional *number* out of the arguments. There is no `optional_float` in
// `tool_builder.h` (the module's other number-taking groups each carry the same
// four-line helper, TASK-008 section 2 / running_game_read_scene.cpp:110).
static bool _optional_number(const Dictionary &p_args, const String &p_key, double p_default, double &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = p_default;
		return true;
	}
	if (value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be a number, got %s", p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	r_out = (double)value;
	return true;
}

// ---------------------------------------------------------------------------
// Event construction. The four classes the contract describes, built in one
// place each so a flat tool and a sequence element cannot drift apart.
// ---------------------------------------------------------------------------

static Ref<InputEventKey> _make_key_event(Key p_keycode, bool p_pressed, bool p_shift, bool p_ctrl, bool p_alt) {
	Ref<InputEventKey> event;
	event.instantiate();
	event->set_keycode(p_keycode);
	// (0, 0). The migration source's game-side service sets both as well
	// (`mcp_input_service.gd:_create_mouse_button_event`).
	// MCP-NARROWING: G24-EDITOR-INPUT-EVENT-BUILD - the five `Vector2((real_t)…)`
	// casts and the `(real_t)` strength cast below are the narrowings the three
	// `_number_fits_event` gates at the call sites judge before these helpers run
	// (TASK-023 D-7: `_tool_simulate_mouse_click`,
	// `_tool_simulate_mouse_move`, `_tool_simulate_input_action`,
	// `_build_sequence_event`).
	event->set_position(Vector2((real_t)p_x, (real_t)p_y));
	event->set_global_position(Vector2((real_t)p_x, (real_t)p_y));
	return event;
}

static Ref<InputEventMouseMotion> _make_mouse_motion_event(double p_x, double p_y, double p_rel_x, double p_rel_y, int64_t p_button_mask) {
	Ref<InputEventMouseMotion> event;
	event.instantiate();
	event->set_position(Vector2((real_t)p_x, (real_t)p_y));
	event->set_global_position(Vector2((real_t)p_x, (real_t)p_y));
	event->set_relative(Vector2((real_t)p_rel_x, (real_t)p_rel_y));
	event->set_button_mask((BitField<MouseButtonMask>)(int64_t)p_button_mask);
	return event;
}

static Ref<InputEventAction> _make_action_event(const String &p_action, bool p_pressed, double p_strength) {
	Ref<InputEventAction> event;
	event.instantiate();
	event->set_action(p_action);
	event->set_pressed(p_pressed);
	// `set_strength()` clamps to [0, 1] (core/input/input_event.cpp:1627); the
	// answers below echo what the event really carries, never the raw request.
	event->set_strength((real_t)p_strength);
	return event;
}

// ---------------------------------------------------------------------------
//
// Observable contract (as implemented):
//   * `button` (int, default 1 = left) - one of the engine's `MouseButton`
//     values 1..9; anything else is `-32602`, and that refusal is a safety
//     property rather than a taste one: `Input::_parse_input_event_impl()`
//     computes `1 << (button - 1)` for the button mask, so an unvalidated
//     `button: 99` is undefined behaviour inside the engine;
//   * `pressed` (bool, default true), `x` / `y` (number, default 0);
//   * injects **one** `InputEventMouseButton`. The addon's `_simulate_mouse_click`
//     sent press+release ("auto_release", so UI buttons fire); that parameter is
//     not in the contract and both events are one `pressed: false` call away, so
//     the migration source that the mapping cites (input.rs) is followed;
//   * answers `{"simulated": "click", "target": "editor", "button", "pressed",
//     "position": {"x": .., "y": ..}}` (the position is read back off the event).
// ---------------------------------------------------------------------------
static Variant _tool_simulate_mouse_click(const Dictionary &p_args, MCPToolError &r_error) {
	int64_t button = 1;
	bool pressed = false;
	double x = 0.0;
	double y = 0.0;
	if (!optional_int(p_args, "button", 1, button, r_error) ||
			!optional_bool(p_args, "pressed", true, pressed, r_error) ||
			!optional_float(p_args, "x", 0.0, x, r_error) ||
			!optional_float(p_args, "y", 0.0, y, r_error)) {
		return Variant();
	}
	if (button < MOUSE_BUTTON_MIN || button > MOUSE_BUTTON_MAX) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'button' must be a MouseButton value between %d (left) and %d (xbutton2), got %d",
				(int)MOUSE_BUTTON_MIN, (int)MOUSE_BUTTON_MAX, (int)button));
		return Variant();
	}

	Input *input = _editor_input(r_error);
	if (input == nullptr) {
		return Variant();
	}
	const Ref<InputEventMouseButton> event = _make_mouse_button_event(button, pressed, x, y);
	input->parse_input_event(event);

	Dictionary result;
	result["simulated"] = "click";
	result["target"] = "editor";
	result["button"] = button;
	result["pressed"] = pressed;
	result["position"] = serialize_variant(event->get_position());
	return result;
}

// ---------------------------------------------------------------------------
// editor_simulate_mouse_move (old `simulate_mouse_move`, input.rs:26/85)
//
// Observable contract (as implemented):
//   * `x` / `y` (number, default 0);
//   * injects one `InputEventMouseMotion` with `position` = (x, y) and a
//     `relative` of zero - the migration source set nothing else, and the
//     contract's schema has no `relative` / `button_mask` (the *sequence* tool
//     does accept them per event, because the recorder emits them and a recorded
//     drag has to be replayable);
//   * answers `{"simulated": "mousemove", "target": "editor", "position": {...}}`.
// ---------------------------------------------------------------------------
static Variant _tool_simulate_mouse_move(const Dictionary &p_args, MCPToolError &r_error) {
	double x = 0.0;
	double y = 0.0;
	if (!optional_float(p_args, "x", 0.0, x, r_error) ||
			!optional_float(p_args, "y", 0.0, y, r_error)) {
		return Variant();
	}

	Input *input = _editor_input(r_error);
	if (input == nullptr) {
		return Variant();
	}
	const Ref<InputEventMouseMotion> event = _make_mouse_motion_event(x, y, 0.0, 0.0, 0);
	input->parse_input_event(event);

	Dictionary result;
	result["simulated"] = "mousemove";
	result["target"] = "editor";
	result["position"] = serialize_variant(event->get_position());
	return result;
}

// ---------------------------------------------------------------------------
// editor_simulate_input_action (old `simulate_action`, input.rs:29/94)
//
// Observable contract (as implemented):
//   * `action` (string, required, must not be blank) - the InputMap action name;
//   * `pressed` (bool, default true), `strength` (number, default 1.0). The
//     strength is **clamped by the engine** to [0, 1]; the answer echoes the
//     clamped value, so a caller that asked for 5 sees 1.0 and not its own
//     request. A non-finite strength is `-32602`.
//   * injects one `InputEventAction` into the editor process' `Input`. An action
//     that the editor's `InputMap` does not know is still injected (the event is
//     delivered to every `_input` listener) but it does **not** move `Input`'s
//     action state, so the answer says `"in_input_map": false` instead of
//     leaving the caller to guess why nothing happened. That is also the
//     documented way to see that this is the *editor's* map and not the game's:
//     `editor_add_input_action` + this tool + a game-scope read of the game's own
//     `InputMap` is the three-way comparison in REPORT-013;
//   * answers `{"simulated": "action", "target": "editor", "action", "pressed",
//     "strength", "in_input_map"}`.
// ---------------------------------------------------------------------------
static Variant _tool_simulate_input_action(const Dictionary &p_args, MCPToolError &r_error) {
	String action;
	if (!require_string(p_args, "action", action, r_error)) {
		return Variant();
	}
	const String trimmed = action.strip_edges();
	if (trimmed.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'action' must not be empty");
		return Variant();
	}
	bool pressed = false;
	double strength = 1.0;
	if (!optional_bool(p_args, "pressed", true, pressed, r_error) ||
			!optional_float(p_args, "strength", 1.0, strength, r_error)) {
		return Variant();
	}
	if (!Math::is_finite(strength)) {
		r_error = MCPToolError::invalid_params("Parameter 'strength' must be a finite number");
		return Variant();
	}

	Input *input = _editor_input(r_error);
	if (input == nullptr) {
		return Variant();
	}
	const Ref<InputEventAction> event = _make_action_event(trimmed, pressed, strength);
	input->parse_input_event(event);
	input->parse_input_event(event);

	bool in_map = false;
	if (InputMap *map = InputMap::get_singleton()) {
		in_map = map->has_action(trimmed);
	}

	Dictionary result;
	result["simulated"] = "action";
	result["target"] = "editor";
	result["action"] = trimmed;
	result["pressed"] = pressed;
	result["strength"] = (double)event->get_strength();
	result["in_input_map"] = in_map;
	return result;
}

// ---------------------------------------------------------------------------
// editor_add_input_action (old `set_input_action`, input.rs:35/113)
//
// Observable contract (as implemented):
//   * `action` (string, required, must not be blank) - created with
//     `InputMap::add_action()` when it does not exist yet (the migration source
//     did the same);
//   * `key` (string, optional) - when present, resolved with the same key rules
//     as `editor_simulate_key` and bound with `action_add_event()`;
//   * writes the **editor process' `InputMap` singleton** in memory, and then
//     (TASK-041 section 2, M-6) publishes the action's real state - `deadzone`
//     plus `events` - into the `[input]` section of `project.godot` through the
//     engine's own `save_custom()` (atomic sibling + rename) and reads it back
//     **from the disk**. That section is how the action reaches a running game:
//     `InputMap::load_from_project_settings()` rebuilds a process' map from it at
//     startup (core/input/input_map.cpp:325-358). The write is idempotent - a
//     second identical call leaves the same bytes;
//   * answers `{"action", "target": "editor", "created": <bool>, "key", ...,
//     "event_count": <events bound to the action now>, "action_state":
//     "created" | "pre_existing_modified" | "pre_existing_unchanged",
//     "persisted": <bool>, "persisted_reason": <string>, "project_entry":
//     "created" | "replaced" | "unchanged" | "none" | "unknown"}`.
//     `event_count` is read back from the map after the write. The engine's
//     `InputMap` refuses an identical event (`_find_event()`, input_map.cpp:205),
//     so calling the tool twice with the same key binds it once - the answer
//     reports the count read back from the map rather than the caller's intent,
//     which is how a caller sees the difference.
//     `action_state` and `project_entry` are TASK-042 section 3 (O-6): the
//     action's own state and the fate of the `[input]` entry on disk, so that an
//     action the process already knew (every engine built-in) cannot be read as
//     "nothing happened" just because `created` is false.
//     `persisted` is `true` only when the file on disk really parses back into
//     this action, and `persisted_reason` is empty exactly then. It is `false`,
//     with a reason, for a process without a `project.godot` (this tool never
//     creates one - the doctest process runs against the engine source tree), for
//     a name `ProjectSettings` cannot address as a single key (`/` or `.`), and
//     for a failed publish. No `inputSchema` change was needed: the publish is
//     what the tool was always for, and "persist or not" is not a caller choice
//     (decisions O-3); TASK-042 added no parameter either.
//   * no `InputMap` singleton (or a game build) -> `-32000` with a suggestion.
// ---------------------------------------------------------------------------
static Variant _tool_add_input_action(const Dictionary &p_args, MCPToolError &r_error) {
	String action;
	if (!require_string(p_args, "action", action, r_error)) {
		return Variant();
	}
	const String trimmed = action.strip_edges();
	if (trimmed.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'action' must not be empty");
		return Variant();
	}
	bool has_key = false;
	String key_text;
	Key keycode = Key::NONE;
	const Variant key_value = p_args.get("key", Variant());
	if (key_value.get_type() != Variant::NIL) {
		if (key_value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'key' must be a string, got %s", Variant::get_type_name(key_value.get_type())));
			return Variant();
		}
		key_text = (String)key_value;
		if (!_resolve_keycode(key_text, keycode, r_error, "key")) {
			return Variant();
		}
		has_key = true;
	}

	InputMap *map = _editor_input_map(r_error);
	if (map == nullptr) {
		return Variant();
	}

	const bool created = !map->has_action(trimmed);
	// TASK-042 section 3 (O-6): the count *before* this call, so the answer can
	// say whether an action that already existed was actually changed. `created`
	// alone answers a different question, and for every engine built-in
	// (`ui_accept`, ... - `InputMap::load_default()` in `main/main.cpp:2333`) it
	// is `false` even though the tool is about to write that action into the
	// project for the first time.
	int events_before = 0;
	if (!created) {
		if (const List<Ref<InputEvent>> *existing = map->action_get_events(trimmed)) {
			events_before = existing->size();
		}
	}
	if (created) {
		map->add_action(trimmed);
	}
	if (has_key) {
		const Ref<InputEventKey> event = _make_key_event(keycode, true, false, false, false);
		map->action_add_event(trimmed, event);
	}

	Dictionary result;
	result["action"] = trimmed;
	result["target"] = "editor";
	result["created"] = created;
	result["key"] = has_key ? keycode_get_string(keycode) : String();
	// `action_get_events()` returns `nullptr` for an action that does not exist;
	// the action exists at this point (either it did before or it was just
	// created), so the count is read back rather than assumed.
	int bound_events = 0;
	if (const List<Ref<InputEvent>> *bound = map->action_get_events(trimmed)) {
		bound_events = bound->size();
	}
	result["event_count"] = bound_events;
	// TASK-042 section 3 (O-6 honesty): `created: false` used to be readable as
	// "this call did nothing", and that reading was wrong in two different ways -
	// the action may have been changed here (a new key on a name that already
	// existed), or it may have been left alone while the tool mirrored it into
	// `project.godot`'s `[input]` section. So the answer states both facts
	// separately from `created`:
	//
	//   * `action_state` is about the **process InputMap**:
	//       "created"                 - the action did not exist here before;
	//       "pre_existing_modified"    - it existed and this call bound a new event;
	//       "pre_existing_unchanged"   - it existed and this call left it alone;
	//   * `project_entry` is about the **`[input]` entry on disk** and comes from
	//     `persist_input_action()` below ("none" = nothing was written).
	//
	// Neither replaces `persisted`, which stays the disk read-back verdict: an
	// entry that is not on disk after the call is `persisted: false` with a
	// reason, whatever the two fields above say.
	if (created) {
		result["action_state"] = "created";
	} else if (has_key && bound_events > events_before) {
		result["action_state"] = "pre_existing_modified";
	} else {
		result["action_state"] = "pre_existing_unchanged";
	}
	// TASK-041 section 2 (M-6). The editor process' `InputMap` and a running game's
	// are two different maps, and the only place they meet is
	// `project.godot`'s `[input]` section, which
	// `InputMap::load_from_project_settings()` reads at startup
	// (core/input/input_map.cpp:325-358). Writing the editor's map alone therefore
	// created an action that no game could ever see - the M-6 capability gap that
	// made a racing game unbootable-by-MCP. So the tool now also publishes the
	// action's real state (its `deadzone` and its `events`) through the engine's
	// own `save_custom()` and then **reads the file back off disk**.
	//
	// `persisted` is that read-back verdict - it is `true` only when the bytes that
	// are on disk now parse back into this action - and `persisted_reason` says why
	// when it is false: a process without a `project.godot` (this tool never
	// creates one), a name `ProjectSettings` cannot address as one key, or a failed
	// publish. A silent `false` was the one thing the old answer refused to give;
	// a silent `true` would be worse.
	String persist_reason;
	MCPTools::InputActionPublish publish = MCPTools::InputActionPublish::None;
	result["persisted"] = MCPTools::persist_input_action(map, trimmed, persist_reason, &publish);
	result["persisted_reason"] = persist_reason;
	result["project_entry"] = MCPTools::input_action_publish_name(publish);
	return result;
}

// ---------------------------------------------------------------------------
// editor_simulate_input_sequence (old `simulate_sequence`, input.rs:39/128)
//
// Observable contract (as implemented):
//   * `events` (array, required, must not be empty): one dictionary per event,
//     `type` selects the class. Both spelling families are accepted, because the
//     two migration sources used one each and the *recorder* of this module
//     emits the second: `key`; `mouse_click` / `mouse_button`; `mouse_move` /
//     `mouse_motion`; `action`. Any other `type` is `-32602` in the frame that
//     read the request (the migration source silently skipped it);
//   * per class: `key` needs `keycode` (same rules as `editor_simulate_key`) and
//     accepts `pressed` / `shift` / `ctrl` / `alt`; `mouse_click` /
//     `mouse_button` accept `button` (1..9) / `pressed` / `x` / `y` / `position`;
//     `mouse_move` / `mouse_motion` accept `x` / `y` / `position` / `relative` /
//     `relative_x` / `relative_y` / `button_mask`; `action` needs `action` and
//     accepts `pressed` / `strength`. Keys the class does not use are ignored,
//     which is what makes a `running_game_stop_input_recording` event feedable
//     here unchanged; `time_ms` is one of them - the pacing of this tool is
//     `frame_delay`, not a per-event offset - and the answer carries
	return true;
}

static bool _sequence_int(const Dictionary &p_event, const String &p_prefix, const String &p_key, int64_t p_default, int64_t &r_out, MCPToolError &r_error) {
	const Variant value = p_event.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = p_default;
		return true;
	}
	if (value.get_type() == Variant::INT) {
		r_out = (int64_t)value;
		return true;
	}
	if (value.get_type() == Variant::FLOAT) {
		const double number = (double)value;
		const int64_t truncated = (int64_t)number;
		if ((double)truncated == number) {
			r_out = truncated;
			return true;
		}
	}
	r_error = MCPToolError::invalid_params(vformat("Parameter '%s%s' must be an integer, got %s", p_prefix, p_key, Variant::get_type_name(value.get_type())));
	return false;
}

// A `{"x": .., "y": ..}` object, the shape `serialize_variant` produces for a
// `Vector2` and therefore the shape both a recorded event and this module's own
// answers carry. `-32602` when one of the components is missing or is not a
// number: a half-specified position is not a position.
static bool _sequence_vector2(const Dictionary &p_event, const String &p_prefix, const String &p_key, double p_default_x, double p_default_y, double &r_x, double &r_y, MCPToolError &r_error) {
	const Variant value = p_event.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_x = p_default_x;
		r_y = p_default_y;
		return true;
	}
	if (value.get_type() != Variant::DICTIONARY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s%s' must be an object with 'x' and 'y', got %s", p_prefix, p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	const Dictionary object = value;
	const Variant x = object.get("x", Variant());
	const Variant y = object.get("y", Variant());
	if ((x.get_type() != Variant::FLOAT && x.get_type() != Variant::INT) || (y.get_type() != Variant::FLOAT && y.get_type() != Variant::INT)) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s%s' must provide numeric 'x' and 'y' components", p_prefix, p_key));
		return false;
	}
	r_x = (double)x;
	r_y = (double)y;
	return true;
}

// One validated element of `events`, ready to inject.
static bool _build_sequence_event(const Dictionary &p_event, int p_index, bool &r_time_ms_ignored, Ref<InputEvent> &r_out, MCPToolError &r_error) {
	const String prefix = vformat("events[%d].", p_index);
	if (p_event.has("time_ms")) {
		r_time_ms_ignored = true;
	}

	String type;
	if (!_sequence_string(p_event, prefix, "type", true, String(), type, r_error)) {
		return false;
	}
	if (type.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%stype' must not be empty", prefix));
		return false;
	}
	EditorSequenceKind kind;
	if (!_sequence_kind_of(type.strip_edges(), kind)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%stype' is '%s'; the accepted types are 'key', 'mouse_click' (or 'mouse_button'), "
				"'mouse_move' (or 'mouse_motion') and 'action'",
				prefix, type));
		return false;
	}

	switch (kind) {
		case EditorSequenceKind::KEY: {
			String keycode_text;
			if (!_sequence_string(p_event, prefix, "keycode", true, String(), keycode_text, r_error)) {
				return false;
			}
			Key keycode = Key::NONE;
			if (!_resolve_keycode(keycode_text, keycode, r_error, prefix + "keycode")) {
				return false;
			}
			bool pressed = true;
			bool shift = false;
			bool ctrl = false;
			bool alt = false;
			if (!_sequence_bool(p_event, prefix, "pressed", true, pressed, r_error) ||
					!_sequence_bool(p_event, prefix, "shift", false, shift, r_error) ||
					!_sequence_bool(p_event, prefix, "ctrl", false, ctrl, r_error) ||
					!_sequence_bool(p_event, prefix, "alt", false, alt, r_error)) {
				return false;
			}
			r_out = _make_key_event(keycode, pressed, shift, ctrl, alt);
			return true;
		}
		case EditorSequenceKind::MOUSE_BUTTON: {
			int64_t button = 1;
			bool pressed = true;
			double x = 0.0;
			double y = 0.0;
			if (!_sequence_int(p_event, prefix, "button", 1, button, r_error) ||
					!_sequence_bool(p_event, prefix, "pressed", true, pressed, r_error) ||
					!_sequence_number(p_event, prefix, "x", 0.0, x, r_error) ||
					!_sequence_number(p_event, prefix, "y", 0.0, y, r_error) ||
					!_sequence_vector2(p_event, prefix, "position", x, y, x, y, r_error)) {
				return false;
			}
			if (button < MOUSE_BUTTON_MIN || button > MOUSE_BUTTON_MAX) {
				r_error = MCPToolError::invalid_params(vformat(
						"Parameter '%sbutton' must be a MouseButton value between %d (left) and %d (xbutton2), got %d",
						prefix, (int)MOUSE_BUTTON_MIN, (int)MOUSE_BUTTON_MAX, (int)button));
				return false;
			}
			// MCP-NARROWING: G24-EDITOR-SEQUENCE-CLICK - the `Vector2((real_t)…,
			// (real_t)…)` of `_make_mouse_button_event` narrows; this gate judges
			// it first (TASK-023 D-7).
			if (!_number_fits_event(Variant(x), prefix + "x", r_error) ||
					!_number_fits_event(Variant(y), prefix + "y", r_error)) {
				return false;
			}
			r_out = _make_mouse_button_event(button, pressed, x, y);
			return true;
		}
		case EditorSequenceKind::MOUSE_MOTION: {
			double x = 0.0;
			double y = 0.0;
			double rel_x = 0.0;
			double rel_y = 0.0;
			int64_t button_mask = 0;
			if (!_sequence_number(p_event, prefix, "x", 0.0, x, r_error) ||
					!_sequence_number(p_event, prefix, "y", 0.0, y, r_error) ||
					!_sequence_vector2(p_event, prefix, "position", x, y, x, y, r_error) ||
					!_sequence_vector2(p_event, prefix, "relative", 0.0, 0.0, rel_x, rel_y, r_error) ||
					!_sequence_number(p_event, prefix, "relative_x", rel_x, rel_x, r_error) ||
					!_sequence_number(p_event, prefix, "relative_y", rel_y, rel_y, r_error) ||
					!_sequence_int(p_event, prefix, "button_mask", 0, button_mask, r_error)) {
				return false;
			}
			// MCP-NARROWING: G24-EDITOR-SEQUENCE-MOVE - the three `Vector2` casts
			// of `_make_mouse_motion_event` narrow; this gate judges them first.
			if (!_number_fits_event(Variant(x), prefix + "x", r_error) ||
					!_number_fits_event(Variant(y), prefix + "y", r_error) ||
					!_number_fits_event(Variant(rel_x), prefix + "relative_x", r_error) ||
					!_number_fits_event(Variant(rel_y), prefix + "relative_y", r_error)) {
				return false;
			}
			r_out = _make_mouse_motion_event(x, y, rel_x, rel_y, button_mask);
			return true;
		}
		case EditorSequenceKind::ACTION: {
			String action;
			if (!_sequence_string(p_event, prefix, "action", true, String(), action, r_error)) {
				return false;
			}
			if (action.strip_edges().is_empty()) {
				r_error = MCPToolError::invalid_params(vformat("Parameter '%saction' must not be empty", prefix));
				return false;
			}
			bool pressed = true;
			double strength = 1.0;
			if (!_sequence_bool(p_event, prefix, "pressed", true, pressed, r_error) ||
					!_sequence_number(p_event, prefix, "strength", 1.0, strength, r_error)) {
				return false;
			}
			if (!Math::is_finite(strength)) {
				r_error = MCPToolError::invalid_params(vformat("Parameter '%sstrength' must be a finite number", prefix));
				return false;
			}
			// MCP-NARROWING: G24-EDITOR-SEQUENCE-ACTION - the `(real_t)` cast of
			// `_make_action_event` narrows; this gate judges it first.
			if (!_number_fits_event(Variant(strength), prefix + "strength", r_error)) {
				return false;
			}
			r_out = _make_action_event(action.strip_edges(), pressed, strength);
			return true;
		}
	}
	return false;
}

// The deferred half of `editor_simulate_input_sequence`: it owns the validated
// events and injects them one `frame_delay` frames apart. It holds no engine
// pointer and no clock: the frame counter and the millisecond clock both come
// from the framework (`MCPDeferred::Task::tick`), which is what makes the pacing
// reproducible and the class testable without a SceneTree.
class EditorSequenceTask : public MCPDeferred::Task {
public:
	EditorSequenceTask(const Vector<Ref<InputEvent>> &p_events, int p_frame_delay, bool p_time_ms_ignored) :
			events(p_events),
			frame_delay(p_frame_delay),
			time_ms_ignored(p_time_ms_ignored) {}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_now_ms;
		Input *input = Input::get_singleton();
		if (input == nullptr) {
			// The singleton cannot disappear while the engine runs; answering a
			// readable error instead of dereferencing null costs one branch.
			return MCPDeferred::TickResult::failed(MCPToolError::not_implemented(
					"input simulation in this process (it has no Input singleton)",
					"Run this tool against a running Godot editor"));
		}

		if (frame_delay <= 0) {
			// The migration source's `frame_delay <= 0` branch: the whole
			// sequence belongs to one frame.
			while (injected < events.size()) {
				input->parse_input_event(events[injected]);
				injected++;
			}
		} else if (last_frame < 0) {
			// The first frame the deferred channel advances this task: the
			// sequence starts here (not in the arrival frame, which the channel
			// never ticks - see the tool's contract comment).
			last_frame = p_frame;
			input->parse_input_event(events[injected]);
			injected++;
		} else if (p_frame - last_frame >= frame_delay) {
			last_frame = p_frame;
			input->parse_input_event(events[injected]);
			injected++;
		}

		if (injected < events.size()) {
			return MCPDeferred::TickResult::pending();
		}

		Dictionary result;
		result["simulated"] = "sequence";
		result["target"] = "editor";
		result["sent"] = true;
		result["event_count"] = events.size();
		result["frame_delay"] = frame_delay;
		result["time_ms_ignored"] = time_ms_ignored;
		return MCPDeferred::TickResult::done(result);
	}

	String describe() const override {
		return vformat("simulating %d editor input event(s) (%d frame(s) apart)", events.size(), frame_delay);
	}

private:
	Vector<Ref<InputEvent>> events;
	int frame_delay = 1;
	bool time_ms_ignored = false;
	int injected = 0;
	// Negative until the first tick; the frame an event was injected in after
	// that.
	int64_t last_frame = -1;
};

static MCPDeferred::Task *_tool_simulate_input_sequence(const Dictionary &p_args, MCPToolError &r_error) {
	const Variant events_value = p_args.get("events", Variant());
	if (events_value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter: events");
		return nullptr;
	}
	if (events_value.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'events' must be an array, got %s", Variant::get_type_name(events_value.get_type())));
		return nullptr;
	}
	const Array raw_events = events_value;
	if (raw_events.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'events' must not be empty");
		return nullptr;
	}
	int64_t frame_delay = 1;
	if (!optional_int(p_args, "frame_delay", 1, frame_delay, r_error)) {
		return nullptr;
	}

	// Everything is validated *before* a single event is built or a task is
	// handed over: a malformed sequence injects nothing (the same rule the
	// replay tool follows for its recordings).
	Vector<Ref<InputEvent>> events;
	bool time_ms_ignored = false;
	for (int i = 0; i < raw_events.size(); i++) {
		const Variant entry = raw_events[i];
		if (entry.get_type() != Variant::DICTIONARY) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'events[%d]' must be an object, got %s", i, Variant::get_type_name(entry.get_type())));
			return nullptr;
		}
		Ref<InputEvent> event;
		if (!_build_sequence_event((Dictionary)entry, i, time_ms_ignored, event, r_error)) {
			return nullptr;
		}
		events.push_back(event);
	}

	if (_editor_input(r_error) == nullptr) {
		return nullptr;
	}
	return memnew(EditorSequenceTask(events, (int)frame_delay, time_ms_ignored));
}

// ---------------------------------------------------------------------------
// Registration
//
// The declaration order follows docs/tool-groups-b2.json; channel, verb, scope
// and mutating come from docs/tool-rename-map.json and the description and
// `inputSchema` are a byte-exact copy of docs/tools_list.renamed.json, emitted
// by `scripts/gen_b2_game_schema.py` (re-running it reproduces this block).
// ---------------------------------------------------------------------------

void register_editor_input_simulation_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("editor_simulate_input_action", String::utf8("模拟 Input Action"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("action")] = v1;
		Dictionary v2;
		v2[String::utf8("default")] = true;
		v2[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("pressed")] = v2;
		Dictionary v3;
		v3[String::utf8("default")] = 1.0;
		v3[String::utf8("type")] = String::utf8("number");
		v0[String::utf8("strength")] = v3;
		schema[String::utf8("properties")] = v0;
		Array v4;
		v4.push_back(String::utf8("action"));
		schema[String::utf8("required")] = v4;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("editor").verb("simulate").scope(MCPToolScope::EDITOR).mutating(true).schema(schema).handler(_tool_simulate_input_action);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_simulate_key", String::utf8("模拟键盘按键"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("default")] = false;
		v1[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("alt")] = v1;
		Dictionary v2;
		v2[String::utf8("default")] = false;
		v2[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("ctrl")] = v2;
		Dictionary v3;
		v3[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("keycode")] = v3;
		Dictionary v4;
		v4[String::utf8("default")] = true;
		v4[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("pressed")] = v4;
		Dictionary v5;
		v5[String::utf8("default")] = false;
		Dictionary v2;
		v2[String::utf8("default")] = true;
		v2[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("pressed")] = v2;
		Dictionary v3;
		v3[String::utf8("default")] = 0;
		v3[String::utf8("type")] = String::utf8("number");
		v0[String::utf8("x")] = v3;
		Dictionary v4;
		v4[String::utf8("default")] = 0;
		v4[String::utf8("type")] = String::utf8("number");
		v0[String::utf8("y")] = v4;
		schema[String::utf8("properties")] = v0;
		Array v5;
		schema[String::utf8("required")] = v5;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("editor").verb("simulate").scope(MCPToolScope::EDITOR).mutating(true).schema(schema).handler(_tool_simulate_mouse_click);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_simulate_mouse_move", String::utf8("模拟鼠标移动"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("default")] = 0;
		v1[String::utf8("type")] = String::utf8("number");
		v0[String::utf8("x")] = v1;
		Dictionary v2;
		v2[String::utf8("default")] = 0;
		v2[String::utf8("type")] = String::utf8("number");
		v0[String::utf8("y")] = v2;
		schema[String::utf8("properties")] = v0;
		Array v3;
		schema[String::utf8("required")] = v3;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("editor").verb("simulate").scope(MCPToolScope::EDITOR).mutating(true).schema(schema).handler(_tool_simulate_mouse_move);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_simulate_input_sequence", String::utf8("模拟输入事件序列"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("事件数组, 每个事件包含 type 和对应参数");
		v1[String::utf8("type")] = String::utf8("array");
		v0[String::utf8("events")] = v1;
		Dictionary v2;
		v2[String::utf8("default")] = 1;
		v2[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("frame_delay")] = v2;
		schema[String::utf8("properties")] = v0;
		Array v3;
		v3.push_back(String::utf8("events"));
		schema[String::utf8("required")] = v3;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("editor").verb("simulate").scope(MCPToolScope::EDITOR).mutating(true).schema(schema).pending_handler(_tool_simulate_input_sequence);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_add_input_action", String::utf8("创建 Input Action When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them."));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("type")] = String::utf8("string");