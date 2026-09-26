/**************************************************************************/
/*  mcp_capture.cpp                                                       */
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

#include "mcp_capture.h"

// `MCPTools::compare_screenshot_pixels` (the one pixel comparison of the module,
// hoisted by this task), `MCPTools::game_framebuffer_available` (the one headless
// test) and the `MCP_EDITOR_TOOLS_ENABLED` guard. The capture path deliberately
// does not grow copies of any of the three.
#include "tools/tool_helpers.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/os/os.h"
#include "scene/gui/control.h"
#include "scene/main/scene_tree.h"
#include "scene/main/viewport.h"
#include "scene/main/window.h"

#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/editor_interface.h"
#endif

namespace MCPCapture {

static const char *const CMDLINE_CAPTURE_PREFIX = "--mcp-capture=";
static const char *const CMDLINE_CAPTURE_FLAG = "--mcp-capture";
static const char *const CMDLINE_DIR_PREFIX = "--mcp-capture-dir=";
static const char *const CMDLINE_DIR_FLAG = "--mcp-capture-dir";
static const char *const CMDLINE_VIEWPORT_PREFIX = "--mcp-capture-viewport=";
static const char *const CMDLINE_VIEWPORT_FLAG = "--mcp-capture-viewport";
static const char *const CMDLINE_SCALE_PREFIX = "--mcp-capture-scale=";
static const char *const CMDLINE_SCALE_FLAG = "--mcp-capture-scale";
static const char *const CMDLINE_DIFF_IMAGE_PREFIX = "--mcp-capture-diff-image=";
static const char *const CMDLINE_DIFF_IMAGE_FLAG = "--mcp-capture-diff-image";

// The threshold `editor_analyze_screenshot_diff` documents as its default. The
// capture compares with it so that "changed" means the same thing whether a
// caller asked the tool or read the capture line.
static const int DEFAULT_DIFF_THRESHOLD = 10;

const char *mode_name(Mode p_mode) {
	switch (p_mode) {
		case Mode::ON_ERROR:
			return "on_error";
		case Mode::EVERY_CALL:
			return "every_call";
		case Mode::OFF:
		default:
			return "off";
	}
}

bool mode_from_name(const String &p_name, Mode &r_mode) {
	if (p_name == "off") {
		r_mode = Mode::OFF;
		return true;
	}
	if (p_name == "on_error") {
		r_mode = Mode::ON_ERROR;
		return true;
	}
	if (p_name == "every_call") {
		r_mode = Mode::EVERY_CALL;
		return true;
	}
	return false;
}

bool viewport_is_valid(const String &p_viewport) {
	return p_viewport == "editor" || p_viewport == "2d" || p_viewport == "3d";
}

bool scale_from_name(const String &p_name, int &r_scale) {
	// A closed list, not any positive integer: the point of the switch is a
	// *cheaper* capture, and 1 / 2 / 4 are the factors whose rasters an observer
	// can reason about (and the ones `running_game_capture_frames`'
	// `half_resolution` precedent fixes the spelling of). Anything else is
	// reported and leaves the default - the viewport switch's rule, not the mode
	// switch's: a wrong scale must not silently turn the capture off.
	if (p_name == "1") {
		r_scale = 1;
		return true;
	}
	if (p_name == "2") {
		r_scale = 2;
		return true;
	}
	if (p_name == "4") {
		r_scale = 4;
		return true;
	}
	return false;
}

// `String::path_join` is not usable for a `user://` base: `get_base_dir()` of
// `user://x.jsonl` is `user:/` (the rfind of `/` lands on the second slash), so
// joining there would produce `user:/shots` - a *relative OS path* as far as
// every engine accessor is concerned, not a user-data directory.
static String _join_dir(const String &p_base, const String &p_child) {
	if (p_base.is_empty()) {
		return p_child;
	}
	if (p_base.ends_with("/")) {
		return p_base + p_child;
	}
	return p_base + "/" + p_child;
}

String default_dir_for_trace(const String &p_trace_path) {
	if (p_trace_path.is_empty()) {
		return "shots";
	}
	if (p_trace_path.begins_with("res://") || p_trace_path.begins_with("user://")) {
		const bool res = p_trace_path.begins_with("res://");
		const String scheme = res ? String("res://") : String("user://");
		const String rest = p_trace_path.substr(scheme.length());
		const String base = rest.get_base_dir();
		return base.is_empty() ? (scheme + "shots") : (scheme + _join_dir(base, "shots"));
	}
	const String base = p_trace_path.get_base_dir();
	return base.is_empty() ? String("shots") : _join_dir(base, "shots");
}

// Reads the last spelling of one switch. Both forms the module's other switches
// accept are understood (`--x=value` and `--x value`), and a value that starts
// with `--` is the next engine switch rather than a value, exactly like
// `MCPTrace::parse` reads it.
static bool _last_switch_value(const Vector<String> &p_args, const String &p_prefix, const String &p_flag, String &r_value) {
	bool found = false;
	const int arg_count = p_args.size();
	for (int i = 0; i < arg_count; i++) {
		const String &arg = p_args[i];
		if (arg.begins_with(p_prefix)) {
			const String value = arg.substr(p_prefix.length());
			if (!value.is_empty()) {
				r_value = value;
				found = true;
			}
		} else if (arg == p_flag) {
			if (i + 1 < arg_count) {
				const String value = p_args[i + 1];
				if (!value.is_empty() && !value.begins_with("--")) {
					r_value = value;
					found = true;
				}
				i++;
			}
		}
	}
	return found;
}

Config parse(const Vector<String> &p_cmdline_args, bool p_has_setting, const String &p_setting_value, const String &p_trace_path) {
	Config config;
	// The directory is resolved even when the switch is off: it is what the
	// startup line would name, and the default must not depend on whether the
	// command line remembered to name one.
	config.dir = default_dir_for_trace(p_trace_path);

	// The project setting is the fallback; the command line wins over it, the
	// same priority the port and the trace use.
	if (p_has_setting) {
		const String setting_value = p_setting_value.strip_edges();
		Mode setting_mode = Mode::OFF;
		if (mode_from_name(setting_value, setting_mode)) {
			if (setting_mode != Mode::OFF) {
				config.mode = setting_mode;
				config.from_project_setting = true;
			}
		} else if (!setting_value.is_empty()) {
			config.warning = vformat("godot_mcp/capture = '%s' is not one of off / on_error / every_call; it is ignored", setting_value);
		}
	}

	String mode_value;
	if (_last_switch_value(p_cmdline_args, CMDLINE_CAPTURE_PREFIX, CMDLINE_CAPTURE_FLAG, mode_value)) {
		Mode mode = Mode::OFF;
		if (mode_from_name(mode_value, mode)) {
			config.mode = mode;
			config.explicit_cmdline = true;
			config.from_project_setting = false;
		} else {
			config.warning = vformat("--mcp-capture=%s is not one of off / on_error / every_call; capture stays off", mode_value);
			config.mode = Mode::OFF;
			config.explicit_cmdline = true;
			config.from_project_setting = false;
		}
	}

	String dir_value;
	if (_last_switch_value(p_cmdline_args, CMDLINE_DIR_PREFIX, CMDLINE_DIR_FLAG, dir_value)) {
		config.dir = dir_value;
	}

	String viewport_value;
	if (_last_switch_value(p_cmdline_args, CMDLINE_VIEWPORT_PREFIX, CMDLINE_VIEWPORT_FLAG, viewport_value)) {
		if (viewport_is_valid(viewport_value)) {
			config.viewport = viewport_value;
		} else {
			config.warning = vformat("--mcp-capture-viewport=%s is not one of editor / 2d / 3d; using '%s'", viewport_value, config.viewport);
		}
	}

	String scale_value;
	if (_last_switch_value(p_cmdline_args, CMDLINE_SCALE_PREFIX, CMDLINE_SCALE_FLAG, scale_value)) {
		int scale = 1;
		if (scale_from_name(scale_value, scale)) {
			config.scale = scale;
		} else {
			config.warning = vformat("--mcp-capture-scale=%s is not one of 1 / 2 / 4; using 1 (no scaling)", scale_value);
		}
	}

	String diff_value;
	if (_last_switch_value(p_cmdline_args, CMDLINE_DIFF_IMAGE_PREFIX, CMDLINE_DIFF_IMAGE_FLAG, diff_value)) {
		// "on" is the only spelling that turns it on; every other value - "off"
		// included - leaves it off, which is the documented default and the safe
		// direction for a switch whose wrong value writes more files.
		config.diff_image = diff_value == "on";
	}

	return config;
}

bool framebuffer_available() {
	// One definition (GDR-25): the same test `editor_capture_screenshot` and
	// `running_game_capture_screenshot` make.
	return MCPTools::game_framebuffer_available();
}

Ref<Image> snapshot(const String &p_viewport, bool p_is_editor, String &r_reason) {
	if (!framebuffer_available()) {
		// The `--headless` display server is behind a dummy renderer with no
		// texture storage: asking for the image would only log an engine error
		// and answer null (REPORT-011 section 2). Never a silent skip and never a
		// blank picture - the caller writes this reason into the log.
		r_reason = String::utf8("headless display server 没有纹理存储");
		return Ref<Image>();
	}

	Viewport *viewport = nullptr;
	if (!p_is_editor) {
		// The game side is the game window, whatever the viewport setting says
		// (`editor` / `2d` / `3d` are editor-tool viewports and do not exist
		// outside the editor).
		SceneTree *tree = SceneTree::get_singleton();
		viewport = tree != nullptr ? tree->get_root() : nullptr;
	} else {
#ifdef MCP_EDITOR_TOOLS_ENABLED
		EditorInterface *editor = EditorInterface::get_singleton();
		if (editor != nullptr) {
			if (p_viewport == "2d") {
				viewport = editor->get_editor_viewport_2d();
			} else if (p_viewport == "3d") {
				viewport = editor->get_editor_viewport_3d(0);
			} else {
				// The whole editor window - the viewport of the base control the
				// editor UI lives in, which is what `editor_capture_screenshot`
				// already reads.
				Control *base_control = editor->get_base_control();
				viewport = base_control != nullptr ? base_control->get_viewport() : nullptr;
			}
		}
#endif
	}

	if (viewport == nullptr) {
		r_reason = vformat("the '%s' viewport is not available in this process", p_viewport);
		return Ref<Image>();
	}
	Ref<ViewportTexture> texture = viewport->get_texture();
	Ref<Image> image = texture.is_valid() ? texture->get_image() : Ref<Image>();
	if (image.is_null() || image->is_empty()) {
		r_reason = vformat("the '%s' viewport has no readable image data yet", p_viewport);
		return Ref<Image>();
	}
	return image;
}

static Ref<Image> _production_snapshot(void *p_userdata, const String &p_viewport, bool p_is_editor, String &r_reason) {
	(void)p_userdata;
	return snapshot(p_viewport, p_is_editor, r_reason);
}

Dictionary image_fields(const Ref<Image> &p_image, const String &p_path, int64_t p_bytes) {
	Dictionary fields;
	fields["path"] = p_path;
	fields["sha256"] = FileAccess::get_sha256(p_path);
	fields["bytes"] = p_bytes;
	fields["width"] = p_image->get_width();
	fields["height"] = p_image->get_height();
	return fields;
}

bool payload_calls_tool(const String &p_body, String &r_tool) {
	JSON json;
	if (json.parse(p_body) != OK) {
		return false;
	}
	const Variant data = json.get_data();
	if (data.get_type() != Variant::DICTIONARY) {
		return false;
	}
	const Dictionary request = data;
	if (String(request.get("method", String())) != "tools/call") {
		return false;
	}
	const Variant params = request.get("params", Variant());
	if (params.get_type() != Variant::DICTIONARY) {
		return false;
	}
	const Variant name = ((Dictionary)params).get("name", Variant());
	if (name.get_type() != Variant::STRING) {
		return false;
	}
	const String tool = name;
	if (tool.is_empty()) {
		return false;
	}
	r_tool = tool;
	return true;
}

static int64_t _wall_clock_ms() {
	const OS *os = OS::get_singleton();
	if (os == nullptr) {
		return 0;
	}
	return (int64_t)(os->get_unix_time() * 1000.0);
}

Engine::~Engine() {
	stop();
}

bool Engine::start(const Config &p_config, MCPTrace::Recorder *p_recorder, bool p_is_editor) {
	config = p_config;
	recorder = p_recorder;
	is_editor = p_is_editor;
	dir = config.dir;
	// A capture line is a line in the trace file, so the file is not optional.
	const String trace_path = p_recorder != nullptr ? p_recorder->get_path() : String();
	if (dir.is_empty()) {
		dir = default_dir_for_trace(trace_path);
	}
	// Editor-side viewports are a choice; a game process has exactly one window.
	viewport_name = p_is_editor ? config.viewport : String("game");

	if (p_recorder == nullptr || !p_recorder->is_active()) {
		WARN_PRINT("[MCP] capture was requested but no call trace is open; capture stays off (add --mcp-trace=<path>)");
		return false;
	}
	if (!viewport_is_valid(config.viewport)) {
		WARN_PRINT(vformat("[MCP] capture viewport '%s' is not one of editor / 2d / 3d; capture stays off", config.viewport));
		return false;
	}

	const Error err = DirAccess::make_dir_recursive_absolute(dir);
	if (err != OK) {
		WARN_PRINT(vformat("[MCP] capture directory '%s' could not be created (error %d); capture stays off", dir, (int)err));
		return false;
	}

	active = true;
	snapshot_func = &_production_snapshot;
	// The startup line is the one place the two things the user has to know are
	// visible: which mode is on, and where the (never deleted, never capped)
	// pictures are going. `scale` is appended (TASK-046) rather than inserted:
	// the line's existing shape is what the live evidence scripts match on.
	print_line(vformat("[MCP] capture enabled: mode=%s viewport=%s dir=%s diff_image=%s scale=%d",
			mode_name(config.mode), viewport_name, dir, config.diff_image ? "true" : "false", config.scale));
	print_line(vformat("[MCP] capture keeps every PNG it writes (no size limit, nothing is ever deleted); the trace line carries total_bytes and a single WARN is printed above %d bytes",
			(int64_t)warn_total_bytes));
	return true;
}

void Engine::stop() {
	active = false;
	// The in-flight entries hold `Image` refs; there is nowhere left to report
	// them to, so they are dropped rather than written.
	for (int i = 0; i < pending.size(); i++) {
		pending.ptrw()[i] = Pending();
	}
	live_count = 0;
	snapshot_func = nullptr;
	snapshot_userdata = nullptr;
}

void Engine::set_snapshot_provider_for_tests(SnapshotFunc p_func, void *p_userdata) {
	snapshot_func = p_func;
	snapshot_userdata = p_userdata;
}

void Engine::set_warn_total_bytes_for_tests(int64_t p_bytes) {
	warn_total_bytes = p_bytes;
}

int Engine::_free_slot() {
	for (int i = 0; i < pending.size(); i++) {
		if (!pending[i].active) {
			return i;
		}
	}
	pending.push_back(Pending());
	return pending.size() - 1;
}

int Engine::arm(const String &p_tool) {
	if (!active) {
		return -1;
	}
	const int index = _free_slot();
	Pending &entry = pending.ptrw()[index];
	entry = Pending();
	entry.active = true;
	entry.tool = p_tool;
	entry.armed_frame = frame;

	// The **only** work done while the request is being answered: one framebuffer
	// image copy. Everything else waits for `tick()`.
	String reason;
	SnapshotFunc func = snapshot_func != nullptr ? snapshot_func : &_production_snapshot;
	entry.before = func(snapshot_userdata, viewport_name, is_editor, reason);
	if (entry.before.is_null()) {
		// Not silence and not a blank picture: the log owes a verdict, and the
		// call line says `unavailable` before the capture line repeats it.
		entry.unavailable = true;
		entry.reason = reason.is_empty() ? String("the configured viewport could not be read") : reason;
	}
	live_count++;
	return index;
}

int Engine::arm_unavailable(const String &p_tool, const String &p_reason) {
	if (!active) {
		return -1;
	}
	const int index = _free_slot();
	Pending &entry = pending.ptrw()[index];
	entry = Pending();
	entry.active = true;
	entry.tool = p_tool;
	entry.armed_frame = frame;
	entry.unavailable = true;
	entry.reason = p_reason;
	live_count++;
	return index;
}

// TASK-092 (item B2): release an armed slot with no verdict. See the header: the
// only caller is the transport's connection-drop path, where there is no response
// left to describe.
void Engine::discard(int p_token) {
	if (p_token < 0 || p_token >= pending.size()) {
		return;
	}
	if (!pending[p_token].active) {
		return;
	}
	pending.ptrw()[p_token] = Pending();
	live_count--;
}

bool Engine::finish(int p_token, bool p_ok, int p_seq) {
	if (p_token < 0 || p_token >= pending.size()) {
		return false;
	}
	Pending &entry = pending.ptrw()[p_token];
	if (!entry.active) {
		return false;
	}
	if (config.mode == Mode::ON_ERROR && p_ok) {
		// `on_error` asks for the picture of a call that failed, and this call
		// did not: the image is dropped here, and the call line carries no
		// `capture` member at all. The rule runs before the `unavailable`
		// verdict, so a successful call in `on_error` mode produces nothing -
		// neither a picture nor a log line - whatever the process can see.
		entry = Pending();
		live_count--;
		return false;
	}
	entry.finish_frame = frame;
	entry.seq = p_seq;
	return true;
}

String Engine::call_line_status(int p_token) const {
	if (p_token < 0 || p_token >= pending.size() || !pending[p_token].active) {
		return String();
	}
	return pending[p_token].unavailable ? String("unavailable") : String("pending");
}

String Engine::call_line_reason(int p_token) const {
	if (p_token < 0 || p_token >= pending.size() || !pending[p_token].active) {
		return String();
	}
	return pending[p_token].reason;
}

bool Engine::_write_png(const String &p_path, const Ref<Image> &p_image, int64_t &r_bytes, String &r_reason) {
	// Not through Godot's "backup save": in an editor process that branch writes
	// `<path><ticks>.tmp` and renames on close, so a process that is killed -
	// which is what every test harness does - would leave no picture at all. The
	// trace recorder made the same call for the same reason (TASK-038), and the
	// option is restored immediately: this runs on the main thread and the call
	// below does not re-enter any other file writer.
	//
	// TASK-046: these are diagnostic pictures, so they are written with the
	// driver's fast encoding (`PNG_IMAGE_FLAG_FAST`: no row filters, compression
	// level 3 - `drivers/png/png_driver_common.cpp:142-144`,
	// `thirdparty/libpng/pngwrite.c:2172-2184`). It trades bytes for the ~177 ms
	// per 2978x1793 frame REPORT-045 measured. The two *screenshot tools* keep
	// `Image::save_png()`: `write_screenshot_png(..., false)` is that same call,
	// and only this capture passes `true`.
	const bool previous_backup_save = FileAccess::is_backup_save_enabled();
	FileAccess::set_backup_save(false);
	const Error err = MCPTools::write_screenshot_png(p_path, p_image, true);
	FileAccess::set_backup_save(previous_backup_save);

	if (err != OK) {
		r_reason = vformat("could not write '%s' (error %d)", p_path, (int)err);
		return false;
	}
	r_bytes = FileAccess::get_size(p_path);
	if (r_bytes <= 0) {
		r_reason = vformat("'%s' was written empty", p_path);
		return false;
	}
	return true;
}

// `--mcp-capture-scale`, applied to one frame. Returns the very same `Ref` for
// scale 1 - no copy, no resample, so the default capture is byte for byte the
// one TASK-044/045 measured.
//
// For scale > 1 the frame is **copied first** and the copy is resampled. The
// snapshot provider is injectable and a doctest's provider may hand out the same
// `Ref<Image>` for both frames (`Task044::FakeViewport` does, and so does a real
// viewport that did not repaint), so resizing in place could halve an image
// twice. `Image::duplicate()` copies the `Vector<uint8_t>` handle, not the
// pixels, and `Image::resize()` builds a new raster and assigns it
// (`core/io/image.cpp:1654`), so the copy is cheap and the source is never
// written through.
//
// `INTERPOLATE_BILINEAR`, measured rather than assumed (TASK-046): this lever
// exists to make a capture *cheaper*, and `half_resolution`'s
// `INTERPOLATE_LANCZOS` (`tools/tool_helpers.cpp:2655`) does not do that at this
// size - it costs 79.5 ms per 2978x1793 frame against the 19.2 ms of bilinear
// (in-process A/B, `[MCP046-TIMING]` in the doctest), i.e. *more* than the
// 2 x 35 ms of fast encoding that scale 2 saves. A switch whose value makes the
// capture slower than its own default would be a trap. At exactly 2x, Godot's
// bilinear downscale is a proper box filter - the source coordinate of
// destination pixel `x` is `(x + 0.5) * 2 - 0.5`, i.e. the 2x2 block average
// (`core/io/image.cpp:1005-1049`, `_scale_bilinear`) - so nothing is aliased
// there. At 4x it
// samples 2 of every 4 source pixels per axis and does undersample; that is the
// declared price of a *diagnostic* raster, and it is recorded in REPORT-046
// rather than hidden. LANCZOS remains the one-word change if fidelity is ever
// preferred over cost (the numbers are in the same report).
//
// `MAX(1, ..)`: a divisor larger than a dimension would ask for a zero-width
// image, which `Image::resize()` refuses (`core/io/image.cpp:1289-1290`) while
// leaving the image untouched - the guard keeps a tiny frame well defined
// instead.
static Ref<Image> _scaled_frame(const Ref<Image> &p_image, int p_scale) {
	if (p_scale <= 1 || p_image.is_null()) {
		return p_image;
	}
	Ref<Image> scaled = p_image->duplicate();
	scaled->resize(MAX(1, scaled->get_width() / p_scale), MAX(1, scaled->get_height() / p_scale), Image::INTERPOLATE_BILINEAR);
	return scaled;
}

static String _shot_path(const String &p_dir, int p_seq, const char *p_kind) {
	return _join_dir(p_dir, vformat("%04d_%s.png", p_seq, p_kind));
}

void Engine::_complete(int p_index) {
	// Copied out first: the slot is released even when everything below fails,
	// and a failure here must not leave an entry that is retried every frame.
	const Pending entry = pending[p_index];
	pending.ptrw()[p_index] = Pending();
	live_count--;

	const String before_path = _shot_path(dir, entry.seq, "before");
	const String after_path = _shot_path(dir, entry.seq, "after");

	Dictionary before;
	Dictionary after;
	Dictionary diff;
	Dictionary fields;
	fields["event"] = "capture";
	fields["seq"] = entry.seq;
	fields["ts_ms"] = _wall_clock_ms();
	fields["tool"] = entry.tool;
	fields["mode"] = mode_name(config.mode);
	fields["viewport"] = viewport_name;
	// Recorded on every line, in every status: it is the one fact an observer
	// needs to reconcile `changed_pixel_ratio` with the two pictures, and a line
	// that omits it would be the trap this field exists to close.
	fields["scale"] = config.scale;
	fields["frames_waited"] = frame - entry.armed_frame;

	String status;
	String reason;
	bool changed_reported = false;
	bool changed = false;
	double ratio = 0.0;

	if (entry.unavailable) {
		status = "unavailable";
		reason = entry.reason;
	} else {
		SnapshotFunc func = snapshot_func != nullptr ? snapshot_func : &_production_snapshot;
		String after_reason;
		const Ref<Image> after_image = func(snapshot_userdata, viewport_name, is_editor, after_reason);
		if (after_image.is_null()) {
			status = "failed";
			reason = after_reason.is_empty() ? String("the after frame could not be read") : after_reason;
		} else {
			// TASK-046: the scale is applied **here** - after the response, before
			// the first write and before the comparison - so the two files and the
			// `changed_pixel_ratio` of this very line describe the same raster at
			// the same size. Doing it in `arm()` would put a whole-frame resample
			// on the response path, which GDR-27 point 4 forbids; doing it only on
			// the way to disk would make the line's numbers disagree with the
			// pictures (`editor_analyze_screenshot_diff` over the two files is the
			// second opinion that must agree).
			const Ref<Image> before_image = _scaled_frame(entry.before, config.scale);
			const Ref<Image> after_frame = _scaled_frame(after_image, config.scale);
			int64_t before_bytes = 0;
			int64_t after_bytes = 0;
			String write_reason;
			if (!_write_png(before_path, before_image, before_bytes, write_reason)) {
				status = "failed";
				reason = write_reason;
			} else if (!_write_png(after_path, after_frame, after_bytes, write_reason)) {
				status = "failed";
				reason = write_reason;
			} else {
				total_bytes += before_bytes + after_bytes;
				before = image_fields(before_image, before_path, before_bytes);
				after = image_fields(after_frame, after_path, after_bytes);

				// The comparison is the whole point of the feature, and it is the
				// module's one implementation (GDR-25): the same loop
				// `editor_analyze_screenshot_diff` runs, with the same default
				// threshold, so `changed` means here what it means there.
				MCPTools::ScreenshotDiff comparison;
				MCPToolError comparison_error;
				if (MCPTools::compare_screenshot_pixels(before_image, after_frame, DEFAULT_DIFF_THRESHOLD,
							config.diff_image, "before", "after", comparison, comparison_error)) {
					changed = !comparison.identical;
					ratio = comparison.total_pixels > 0 ? (double)comparison.changed_pixels / (double)comparison.total_pixels : 0.0;
					changed_reported = true;
					fields["changed_pixels"] = comparison.changed_pixels;
					fields["total_pixels"] = comparison.total_pixels;
					if (config.diff_image && comparison.diff_image.is_valid()) {
						const String diff_path = _shot_path(dir, entry.seq, "diff");
						int64_t diff_bytes = 0;
						String diff_reason;
						if (_write_png(diff_path, comparison.diff_image, diff_bytes, diff_reason)) {
							total_bytes += diff_bytes;
							diff["path"] = diff_path;
							diff["bytes"] = diff_bytes;
							diff["sha256"] = FileAccess::get_sha256(diff_path);
						} else {
							// The verdict stands; only the human-readable picture is
							// missing, and the reason says so.
							reason = diff_reason;
						}
					}
				} else {
					// The window changed size between the two frames. The pixels
					// really are different, but a per-pixel ratio is not defined
					// across two geometries, so the ratio is reported as null -
					// never invented as 0 or 1.
					changed = true;
					reason = comparison_error.message;
				}
				status = "done";
			}
		}
	}

	fields["status"] = status;
	fields["before"] = before.is_empty() ? Variant() : (Variant)before;
	fields["after"] = after.is_empty() ? Variant() : (Variant)after;
	fields["changed"] = changed_reported ? Variant(changed) : Variant();
	fields["changed_pixel_ratio"] = changed_reported ? Variant(ratio) : Variant();
	fields["diff"] = diff;
	fields["total_bytes"] = total_bytes;
	if (!reason.is_empty()) {
		fields["reason"] = reason;
	}

	// The no-limit promise is only honest when it is visible. Nothing is ever
	// deleted; the threshold is a one-time warning and nothing else.
	if (total_bytes > warn_total_bytes && !warned_over_threshold) {
		warned_over_threshold = true;
		WARN_PRINT(vformat("[MCP] capture directory '%s' passed %d bytes (%d bytes of PNGs); nothing is deleted - remove old shots yourself",
				dir, (int64_t)warn_total_bytes, total_bytes));
	}

	if (recorder != nullptr) {
		recorder->record_event_line(fields);
	}
}

void Engine::tick(int64_t p_frame) {
	if (!active) {
		return;
	}
	frame = p_frame;

	if (recorder == nullptr || !recorder->is_active()) {
		// The trace died (a write failure disables it). A capture that cannot be
		// reported is not worth the disk, so the in-flight entries are dropped
		// and no further files are produced.
		for (int i = 0; i < pending.size(); i++) {
			pending.ptrw()[i] = Pending();
		}
		live_count = 0;
		return;
	}

	for (int i = 0; i < pending.size(); i++) {
		if (!pending[i].active || pending[i].finish_frame < 0) {
			continue;
		}
		// At least one whole rendered frame after the one the response was
		// produced in: the call's effect is on screen, and `frames_waited` in the
		// line is what proves it.
		if (p_frame < pending[i].finish_frame + 1) {
			continue;
		}
		_complete(i);
	}
}

} // namespace MCPCapture