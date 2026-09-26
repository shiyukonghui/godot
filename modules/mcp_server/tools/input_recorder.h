/**************************************************************************/
/*  input_recorder.h                                                      */
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

#include "core/input/input_event.h"
#include "core/object/ref_counted.h"
#include "core/string/ustring.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "scene/main/node.h"

// ---------------------------------------------------------------------------
// Input recording state machine (TASK-012, group `running_game_input`).
//
// `running_game_create_input_recording` and `running_game_stop_input_recording`
// are two calls that necessarily sit on *different frames*: whatever happens
// between them is the recording. The migration source captured it with a
// GDScript autoload's `_input()` (`addons/godot_mcp_rs/mcp_runtime_agent.gd:264`
// and `addons/godot_mcp/mcp_game_inspector_service.gd:1531`) - an object that is
// alive for the whole session. The module has no autoload to borrow, so it
// supplies its own smallest equivalent: a Node that is added to the tree root,
// asks for input (`set_process_input(true)`, which is exactly what registers it
// in the viewport's `_vp_input<id>` group, scene/main/node.cpp:1267) and is
// removed again when the recording stops.
//
// This header holds the **state machine only**, deliberately free of the
// engine's SceneTree, of GDVIRTUAL and of the wire format. Two reasons:
//
//   * `Main::test_entrypoint()` runs `test_main()` *before* the module
//     initialization levels (main/main.cpp:921-943 vs. :787), so a doctest
//     process has no `ClassDB` registration for the Node and cannot `memnew`
//     one. The state machine can therefore be exercised by itself, with
//     synthetic events, and the Node wrapper stays too thin to be worth a class
//     the tests must instantiate;
//   * `stop` is the only place that turns events into JSON, and having it in
//     one method is what keeps `running_game_stop_input_recording`'s answer
//     shape and `running_game_play_input_recording`'s accepted shape from
//     drifting apart.
//
// Event shape (the round trip is the point - see the report's D56 section):
//   { "type": "key"|"mouse_button"|"mouse_motion"|"action", "time_ms": <int>, ... }
// `time_ms` is milliseconds since `start()`, matching
// `mcp_game_inspector_service.gd:1535`. The migration source's older
// `mcp_runtime_agent.gd` emitted `time` as *seconds* under a `"time"` key while
// its own replay read `"time"` as milliseconds - a recording that replays
// instantly. `running_game_play_input_recording` therefore reads `time_ms`
// first and falls back to `time` (milliseconds), so a recording made by either
// spelling replays with the right delays; only `time_ms` is ever emitted.
// ---------------------------------------------------------------------------

// The recorder's counting/coercion helpers are shared with the replay tool, so
// the two live next to each other rather than one per file.
namespace MCPInputRecording {

// ---------------------------------------------------------------------------
// Length caps (D59 point 5 / DESIGN-DETAIL section 19.5).
//
// Before TASK-013 a recording had no upper bound at all: `capture()` pushed one
// `Ref<InputEvent>` per event for as long as the session stayed open, so a
// forgotten `stop_input_recording` grew the game process' heap without limit.
// A cap is therefore enforced on **both** axes - event count and total duration
// - and reaching one of them stops the collection and is *reported*.
//
// Where the caps come from, in decreasing precedence (read by `start()`, so a
// change applies to the next session and never mid-session):
//
//   1. `godot_mcp/recording_max_events` / `godot_mcp/recording_max_duration_ms`
//      in `ProjectSettings`, when the key is present and holds a number. The
//      dotted aliases (`godot_mcp.recording_max_events`) are accepted too, like
//      the module's other settings. A value `<= 0` means "no cap on that axis";
//   2. `set_limits()`, i.e. the programmatic configuration (what a doctest uses);
//   3. the compiled defaults below.
//
// The defaults are deliberately far above anything a scripted test session
// produces and far below a threat to the process: 100000 events is a couple of
// tens of MB of `InputEvent` objects (a human-driven session records thousands),
// and 10 minutes is longer than a scripted scenario while still bounding a
// forgotten recording. Both are "long enough to be invisible, short enough to
// matter".
//
// A setting that is present but not a number is ignored (the module's other
// settings reader behaves the same way); it is never a reason to fail a tool.
// ---------------------------------------------------------------------------
const int64_t DEFAULT_MAX_EVENTS = 100000;
const int64_t DEFAULT_MAX_DURATION_MS = 600000; // 10 minutes

// Configures the caps used by the *next* `start()`. `0` (or a negative value)
// means "no cap on that axis". They are also what `reset()` restores.
void set_limits(int64_t p_max_events, int64_t p_max_duration_ms);

// The caps in force for the current/last session, as
// `{"max_events": <int>, "max_duration_ms": <int>}` with `0` for "no cap".
Dictionary limits();

// True when at least one event was dropped because a cap was reached. "At least
// one event really was lost" is the definition on purpose: a session whose clock
// passed the duration cap but which never received another event has not
// truncated anything and does not claim it.
bool was_truncated();

// How many events were dropped by the caps (0 when nothing was).
int64_t dropped_event_count();

// The truncation half of the stop answer, in one place so its shape cannot
// drift: `{"truncated": <bool>, "dropped": <int>, "limits": {...}}`.
Dictionary truncation_report();

// "A recording is in progress" as seen by the create/stop tools.
bool is_recording();

// Starts a fresh recording, discarding whatever the previous one collected, and
// resolves the length caps of the new session (see the cap block above).
// `p_now_ms` is the clock the timestamps are relative to; the caller passes the
// engine's monotonic millisecond clock (`Time::get_ticks_msec()`) so that this
// file needs no clock of its own.
void start(uint64_t p_now_ms);

// One captured event. `p_now_ms` is the same clock as in `start()`. Once a cap
// is reached the event (and every later one) is dropped and counted, never kept.
void capture(const Ref<InputEvent> &p_event, uint64_t p_now_ms);

// Ends the recording. The collected events stay available through
// `take_events()` until the next `start()` (so the stop tool can encode them and
// `running_game_play_input_recording` can replay them with no argument).
void stop_events(uint64_t p_now_ms);

// The events of the last *stopped* recording, encoded (one dictionary per event,
// in capture order, each with its `time_ms` offset). Empty before the first
// stop and after `start()`/`reset()`.
Array take_events();

// `{"key": 0, "mouse_button": 0, "mouse_motion": 0, "action": 0, "other": 0}` -
// the answer's `event_types` shape for a stop that collected nothing. A helper
// so the zero case is not a second, handwritten copy of the key set.
Dictionary empty_type_counts();

// `{"key": n, "mouse_button": n, "mouse_motion": n, "action": n, "other": n}`:
// what the last recording contains, per event class. `other` entries can be
// reported but never replayed.
Dictionary event_type_counts();

// Milliseconds between `start()` and `p_now_ms`, or between `start()` and
// `stop_events()` once the recording ended (0 when nothing was ever recorded).
int64_t elapsed_ms(uint64_t p_now_ms);

// True for the four event classes `running_game_play_input_recording` can
// reconstruct. The replay tool validates with this *before* it starts waiting,
// so an un-replayable recording is refused in one frame instead of half way
// through.
bool is_replayable_type(const String &p_type);

// Discards the recording entirely and restores the compiled caps (see above).
// Used by the module teardown path and by the doctests' own reset; not reachable
// through any tool.
void reset();

} // namespace MCPInputRecording

// The tree-attached half: an input sink. It is intentionally trivial - all it
// does is forward one event into the state machine above - so that the module
// owns one obvious place where game input is observed.
//
// It overrides `Node::input()` and **not** the `_input` GDVIRTUAL. That choice
// is the whole reason this class needs no `ClassDB` registration at all:
//
//   * `Node::_call_input()` (scene/main/node.cpp:3606-3614) first tries the
//     `_input` GDVIRTUAL and then, unconditionally, calls the plain C++ virtual
//     `Node::input(event)`. The GDVIRTUAL machinery (core/object/gdvirtual.gen.h)
//     resolves *only* through a `ScriptInstance` or a GDExtension instance, so a
//     subclass written in C++ inside the engine can never be reached by it -
//     but the plain virtual is reached by ordinary C++ dispatch;
//   * `set_process_input(true)` is what puts the node into the viewport's
//     `_vp_input<id>` group, i.e. what makes `_call_input` reach it at all
//     (scene/main/node.cpp:1267), and that works for any Node.
//
// Avoiding the registration also keeps the doctest process able to test the
// state machine: `Main::test_entrypoint()` runs `test_main()` *before* the
// module initialization levels (main/main.cpp:921-943 vs. :787), so a class
// registered in `register_types.cpp` does not exist yet while the tests run.
class MCPInputRecorderNode : public Node {
	GDCLASS(MCPInputRecorderNode, Node);

protected:
	static void _bind_methods() {}

public:
	MCPInputRecorderNode() {}

	void input(const Ref<InputEvent> &p_event) override;
};
