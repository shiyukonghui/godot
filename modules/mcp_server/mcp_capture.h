/**************************************************************************/
/*  mcp_capture.h                                                         */
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

#include "mcp_trace.h"

#include "core/io/image.h"
#include "core/templates/vector.h"
#include "core/string/ustring.h"

// ---------------------------------------------------------------------------
// Optional before/after capture of a tool call (TASK-044, GDR-27).
//
// The module's core proposition is the family of calls that answer `ok` while
// nothing happened (the D-1/D-2 family). A read-back of the caller's own
// arguments cannot settle that; a picture taken around the call can, and two
// pictures can settle it mechanically: the call changed the screen, or it did
// not.
//
// Two hard constraints shape the design, and both come from the trace this is an
// extension of:
//
//   1. **Off by default, and a bystander.** No switch means no engine object at
//      all (`MCPServer::capture_engine` stays null), so the request path is the
//      one it was before this file existed. A failed write only warns; a tool
//      call never learns that capture was configured.
//
//   2. **Zero latency in the response.** The *only* work done while the request
//      is being answered is one framebuffer image copy; the optional
//      `--mcp-capture-scale` resample (TASK-046), encoding, decoding, hashing,
//      writing and the pixel comparison all happen after the response has been
//      produced, on a later frame. The "after" picture is therefore taken at
//      least one *rendered* frame after the call, which is what makes
//      `changed` mean "the call's effect is on screen".
//
// The state machine is deliberately free of the SceneTree and of sockets: the
// snapshot is behind a function pointer, so the doctest binary - which has no
// display server and no SceneTree - drives the whole thing (files, JSON, the
// pixel comparison, the once-only threshold warning) on images it built itself.
// ---------------------------------------------------------------------------

namespace MCPCapture {

// The three settings of the switch. `OFF` is the default and the absence of the
// whole feature.
enum class Mode {
	OFF,
	ON_ERROR,
	EVERY_CALL,
};

// "off" / "on_error" / "every_call", the spelling of the command line and of the
// `capture` member of a log line.
const char *mode_name(Mode p_mode);

// Parses that spelling. False for anything else (the caller reports it).
bool mode_from_name(const String &p_name, Mode &r_mode);

// "editor" / "2d" / "3d".
bool viewport_is_valid(const String &p_viewport);

// `--mcp-capture-scale`: "1" / "2" / "4" - the integer divisor applied to both
// frames before anything is compared or written (TASK-046). False for anything
// else (the caller reports it and keeps the default).
bool scale_from_name(const String &p_name, int &r_scale);

struct Config {
	Mode mode = Mode::OFF;
	// The directory the PNGs land in. Empty means `default_dir_for_trace()`
	// (the trace file's own `shots/` sibling).
	String dir;
	String viewport = "editor";
	// `--mcp-capture-diff-image=on`: also write the difference picture. Off by
	// default - the verdict of a capture is the two numbers, and the picture is
	// only there for a human who is looking at it.
	bool diff_image = false;
	// `--mcp-capture-scale=1|2|4`: divide both frames by this before anything is
	// written or compared (TASK-046). 1 - the default - is "no scaling at all":
	// no image is copied and no resample happens, so the frames, the verdict and
	// the two log numbers are the ones TASK-044/045 measured. Any other value is
	// applied **once, to both frames and only in `Engine::_complete`** (after the
	// response, before the first write), so the pictures on disk and
	// `changed_pixel_ratio` of the same line are always the same raster -
	// `editor_analyze_screenshot_diff` over those two files answers exactly the
	// line's numbers. The `running_game_capture_frames` `half_resolution` switch
	// is the precedent for the feature; its `INTERPOLATE_LANCZOS` is deliberately
	// **not** the interpolation here - `_scaled_frame` in the .cpp measured
	// bilinear at 19.2 ms against lanczos' 79.5 ms on the capture's own
	// 2978x1793 frame, and a "cheaper capture" switch that costs more than the
	// default would be a trap.
	int scale = 1;
	bool explicit_cmdline = false;
	bool from_project_setting = false;
	// A spelling the switch does not know ("--mcp-capture=sometimes") or a
	// companion without a value. `parse()` cannot print it (it is called from the
	// startup path, which is where the other startup lines are printed), so it
	// reports the sentence and `MCPServer` WARNs with it. Empty when everything
	// that was given was understood.
	String warning;
};

// Priority, the same chain the trace and the port use (GDR-4 / GDR-26 point 1):
// `--mcp-capture=<mode>` (or `--mcp-capture <mode>`, last one wins) >
// `ProjectSettings: godot_mcp/capture` > off. The companions
// (`--mcp-capture-dir=<OS path>`, `--mcp-capture-viewport=<name>`,
// `--mcp-capture-scale=1|2|4`, `--mcp-capture-diff-image=on`) only refine
// an enabled switch; an unknown mode spelling is reported by the *caller*
// (`MCPServer`), which is the only place that can print a warning, so `parse()`
// leaves `mode` as `OFF` for it.
//
// `p_trace_path` is the resolved trace file: a capture line is a line in that
// file, so capture is meaningless without one and `MCPServer` refuses it (with
// a warning) when no trace file was named.
Config parse(const Vector<String> &p_cmdline_args,
		bool p_has_setting, const String &p_setting_value,
		const String &p_trace_path);

// `<base dir of the trace file>/shots`, or `shots` when the trace has no
// directory part. Handles both OS paths and `res://` / `user://`.
String default_dir_for_trace(const String &p_trace_path);

// True when this process has a display server that can hand out a framebuffer.
// It is `MCPTools::game_framebuffer_available()` - one definition, shared with
// the two screenshot tools (GDR-25) - re-exported so the capture path does not
// grow a second copy of the headless test.
bool framebuffer_available();

// One picture of the configured viewport, or a null Ref plus `r_reason` when
// this process cannot produce one (no framebuffer, no such viewport, no frame
// drawn yet). `p_is_editor` selects the editor accessors; a game process reads
// its own window whatever the viewport setting says.
Ref<Image> snapshot(const String &p_viewport, bool p_is_editor, String &r_reason);

// `{"path","sha256","bytes","width","height"}` - the reference one log line
// holds for one stored picture. `p_bytes` is the size on disk.
Dictionary image_fields(const Ref<Image> &p_image, const String &p_path, int64_t p_bytes);

// Does this payload call a tool? Fills `r_tool` with `params.name` when it does
// (and it is a non-empty string). A capture is only ever taken around a
// `tools/call`; `initialize` / `tools/list` have no effect to observe.
bool payload_calls_tool(const String &p_body, String &r_tool);

// The one snapshot entry point, injectable. Production uses `snapshot()`;
// the doctest binary substitutes its own.
typedef Ref<Image> (*SnapshotFunc)(void *p_userdata, const String &p_viewport, bool p_is_editor, String &r_reason);

// The visibility threshold of the "no size limit" promise: nothing is ever
// deleted, but a capture directory that passed 1 GB is WARNed about once.
const int64_t WARN_TOTAL_BYTES = 1024LL * 1024LL * 1024LL;

// One in-flight capture per armed tool call, completed one frame later.
class Engine {
public:
	Engine() = default;
	~Engine();

	Engine(const Engine &) = delete;
	Engine &operator=(const Engine &) = delete;

	// Resolves the directory (creating it), prints the startup line and stores
	// the recorder. Answers false - after one warning - when the directory
	// cannot be used; the caller then drops the engine entirely.
	bool start(const Config &p_config, MCPTrace::Recorder *p_recorder, bool p_is_editor);
	void stop();

	bool is_active() const { return active; }
	const Config &get_config() const { return config; }
	const String &get_viewport_name() const { return viewport_name; }
	const String &get_dir() const { return dir; }
	int64_t get_total_bytes() const { return total_bytes; }
	int get_pending_count() const { return live_count; }
	bool is_warned_over_threshold() const { return warned_over_threshold; }

	void set_snapshot_provider_for_tests(SnapshotFunc p_func, void *p_userdata);
	void set_warn_total_bytes_for_tests(int64_t p_bytes);

	// The frame clock, handed in once per frame *before* the transport poll.
	void begin_frame(int64_t p_frame) { frame = p_frame; }
	int64_t get_frame() const { return frame; }

	// Arms one capture. Answers a token, or -1 when nothing was armed (the mode
	// is off or the engine is stopped). A process without a framebuffer still
	// arms: it owes the log an `unavailable` verdict rather than silence, and
	// that verdict is what the caller puts on the call line.
	int arm(const String &p_tool);

	// The same, for a call the capture path knows it cannot take a picture
	// around at all (a request answered across frames: its call line is written
	// from the deferred completion, which is far too late to decide whether a
	// picture should have been dropped). No snapshot is taken; the log still
	// gets its `unavailable` verdict and its reason.
	int arm_unavailable(const String &p_tool, const String &p_reason);

	// Called once the outcome of the call is known, before the call line is
	// written. `p_seq` is the line number that call line will carry (the
	// recorder's next request line). Answers false when the capture was
	// **dropped** (mode `on_error` and the call succeeded), in which case the
	// caller must not put a `capture` member on the call line at all.
	bool finish(int p_token, bool p_ok, int p_seq);

	// The `capture` member of the call line, valid for a token `finish()`
	// accepted. `status` is `pending` (a capture line will follow) or
	// `unavailable` (it cannot be taken; `reason` says why).
	String call_line_status(int p_token) const;
	String call_line_reason(int p_token) const;

	// Completes every capture whose call was answered at least one frame ago.
	// Called once per frame *after* the transport poll, so the encoding, the
	// files, the pixel comparison and the appended line all happen strictly
	// after the response.
	void tick(int64_t p_frame);

private:
	struct Pending {
		bool active = false;
		String tool;
		int64_t armed_frame = 0;
		// The frame the response was produced in; -1 while the call is still in
		// flight (a deferred request never reaches a capture, but the field is
		// kept honest for the state machine itself).
		int64_t finish_frame = -1;
		int seq = 0;
		Ref<Image> before;
		bool unavailable = false;
		String reason;
	};

	int _free_slot();
	void _complete(int p_index);
	bool _write_png(const String &p_path, const Ref<Image> &p_image, int64_t &r_bytes, String &r_reason);

	Config config;
	MCPTrace::Recorder *recorder = nullptr;
	bool is_editor = false;
	bool active = false;
	String dir;
	String viewport_name;
	int64_t frame = 0;
	int64_t total_bytes = 0;
	int64_t warn_total_bytes = WARN_TOTAL_BYTES;
	bool warned_over_threshold = false;
	int live_count = 0;
	Vector<Pending> pending;
	SnapshotFunc snapshot_func = nullptr;
	void *snapshot_userdata = nullptr;
};

} // namespace MCPCapture
