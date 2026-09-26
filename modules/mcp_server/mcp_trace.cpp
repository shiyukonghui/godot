/**************************************************************************/
/*  mcp_trace.cpp                                                         */
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

#include "mcp_trace.h"

#include "core/io/json.h"
#include "core/os/os.h"
#include "core/version.h"

namespace MCPTrace {

static const char *const CMDLINE_PREFIX = "--mcp-trace=";
static const char *const CMDLINE_FLAG = "--mcp-trace";

Config parse(const Vector<String> &p_cmdline_args, bool p_has_setting, const String &p_setting_path) {
	Config config;

	// The same two forms the port switch accepts (GDR-4): `--mcp-trace=PATH` and
	// `--mcp-trace PATH`. The last one on the command line wins, exactly like the
	// port, so a wrapper script can override a default it passed earlier.
	String explicit_path;
	bool has_explicit = false;
	const int arg_count = p_cmdline_args.size();
	for (int i = 0; i < arg_count; i++) {
		const String &arg = p_cmdline_args[i];
		if (arg.begins_with(CMDLINE_PREFIX)) {
			const String value = arg.substr(String(CMDLINE_PREFIX).length());
			if (!value.is_empty()) {
				explicit_path = value;
				has_explicit = true;
			}
		} else if (arg == CMDLINE_FLAG) {
			if (i + 1 < arg_count) {
				const String value = p_cmdline_args[i + 1];
				if (!value.is_empty() && !value.begins_with("--")) {
					explicit_path = value;
					has_explicit = true;
				}
				i++;
			}
		}
	}

	// The project setting is the fallback, and an empty setting is "no path" -
	// there is no such thing as a trace file without a name.
	if (p_has_setting && !p_setting_path.is_empty()) {
		config.enabled = true;
		config.path = p_setting_path;
		config.from_project_setting = true;
	}

	if (has_explicit) {
		config.enabled = true;
		config.path = explicit_path;
		config.explicit_cmdline = true;
	}

	return config;
}

// UTF-8 safe truncation: the cut is moved back to the start of the character
// that straddles the limit, so the recorded prefix is always decodable text and
// never a lone replacement character.
static String _truncate_utf8(const String &p_text, int p_max_bytes, bool &r_truncated) {
	const CharString utf8 = p_text.utf8();
	if (p_max_bytes <= 0 || utf8.length() <= p_max_bytes) {
		r_truncated = false;
		return p_text;
	}
	r_truncated = true;
	int cut = p_max_bytes;
	const char *const data = utf8.get_data();
	while (cut > 0 && ((uint8_t)data[cut] & 0xC0) == 0x80) {
		cut--;
	}
	if (cut <= 0) {
		return String();
	}
	return String::utf8(data, cut);
}

static int64_t _wall_clock_ms() {
	const OS *os = OS::get_singleton();
	if (os == nullptr) {
		return 0;
	}
	return (int64_t)(os->get_unix_time() * 1000.0);
}

Dictionary build_trace_opened_fields(bool p_is_editor, int p_port, bool p_listen) {
	OS *os = OS::get_singleton();
	const int64_t now_ms = _wall_clock_ms();
	const int64_t uptime_ms = os != nullptr ? (int64_t)os->get_ticks_msec() : (int64_t)0;

	Dictionary fields;
	fields["event"] = "trace_opened";
	fields["pid"] = os != nullptr ? (int64_t)os->get_process_id() : (int64_t)0;
	fields["ts_ms"] = now_ms;
	// Two halves of "when did this process start": how long it has been up, and
	// the wall clock instant that implies. `ts_ms` is the moment the marker was
	// written (the same unit every request line uses).
	fields["uptime_ms"] = uptime_ms;
	fields["started_ts_ms"] = now_ms - uptime_ms;
	fields["mcp_port"] = p_port;
	fields["listen"] = p_listen;

	// The exact string `--version` prints, so the marker names the binary that
	// wrote the file (main/main.cpp:319-325).
	String hash = String(GODOT_VERSION_HASH);
	if (!hash.is_empty()) {
		hash = "." + hash.left(9);
	}
	fields["version"] = String(GODOT_VERSION_FULL_BUILD) + hash;
	fields["role"] = p_is_editor ? "editor" : "game";
	return fields;
}

// TASK-063 (a): the "no endpoint" event line. See the declaration: it exists
// because the generation marker is written before the bind is attempted, so
// `listen: false` there cannot say *why* - and a process whose endpoint never
// came up has no other machine-readable channel.
Dictionary build_endpoint_disabled_fields(bool p_is_editor, int p_requested_port, int p_error,
		const String &p_reason) {
	OS *os = OS::get_singleton();
	const int64_t now_ms = _wall_clock_ms();

	Dictionary fields;
	fields["event"] = "endpoint_disabled";
	fields["pid"] = os != nullptr ? (int64_t)os->get_process_id() : (int64_t)0;
	fields["ts_ms"] = now_ms;
	fields["role"] = p_is_editor ? "editor" : "game";
	// The port that was asked for, and the port the process answers on (always 0
	// here - the field is written explicitly so a reader does not have to know
	// that "disabled" implies it).
	fields["requested_port"] = p_requested_port;
	fields["mcp_port"] = 0;
	// The engine's `Error` number. TASK-063's report records why it is not a
	// socket errno: `SocketServer::_listen` folds every bind failure into
	// `ERR_ALREADY_IN_USE` (22), `core/io/socket_server.cpp:47-52`.
	fields["error"] = p_error;
	fields["reason"] = p_reason;
	fields["version"] = String(GODOT_VERSION_FULL_BUILD);
	return fields;
}

Recorder::~Recorder() {
	close();
}
void Recorder::set_max_args_bytes(int p_bytes) {
	max_args_bytes = p_bytes < 0 ? 0 : p_bytes;
}

void Recorder::set_max_message_bytes(int p_bytes) {
	max_message_bytes = p_bytes < 0 ? 0 : p_bytes;
}

void Recorder::set_write_fault_after_for_tests(int p_lines) {
	write_fault_after_for_tests = p_lines;
}

bool Recorder::open(const String &p_path) {
	if (active) {
		return true;
	}
	path = p_path;
	if (p_path.is_empty()) {
		_disable_after_failure("no trace file was named");
		return false;
	}

	// Append only, and deliberately **not** through Godot's "safe save".
	//
	// `FileAccess::open(path, WRITE)` in an editor process is the backup-save
	// branch (`drivers/windows/file_access_windows.cpp:197-216`): the writes land
	// in `<path><ticks>.tmp` and the target file only appears when the handle is
	// closed. That would destroy the two properties this feature exists for - an
	// observer could not read the file while the observed process is still
	// running, and a process that is killed (which is what every test harness
	// does) would leave no trace at all, only a `.tmp` next to nothing. Measured
	// live: the first wire run of TASK-038 produced exactly that.
	//
	// The same option also hands every non-`READ` handle an *exclusive* share mode
	// (`_SH_DENYRW`, line 218), so even a correctly created file could not be read
	// by a second process while the trace was being written - the observer's whole
	// reason for existing. Both effects are switched off for the two `open()` calls
	// below and the option is restored before returning: this runs on the main
	// thread and neither call re-enters code that opens a file, so nothing else in
	// the process can observe the temporary value.
	//
	// `WRITE_READ` ("wb+") is a different mode and is not the safe-save branch, so
	// it is used once to bring the file into existence; the handle the recorder
	// keeps is `READ_WRITE` ("rb+") positioned at the end, and every line goes
	// straight to the real file.
	const bool previous_backup_save = FileAccess::is_backup_save_enabled();
	FileAccess::set_backup_save(false);

	bool created_ok = true;
	if (!FileAccess::exists(p_path)) {
		Ref<FileAccess> created = FileAccess::open(p_path, FileAccess::WRITE_READ);
		if (created.is_null()) {
			created_ok = false;
		} else {
			created->close();
		}
	}
	Ref<FileAccess> opened;
	if (created_ok) {
		opened = FileAccess::open(p_path, FileAccess::READ_WRITE);
	}

	FileAccess::set_backup_save(previous_backup_save);

	if (opened.is_null()) {
		_disable_after_failure(vformat("cannot open '%s' for appending", p_path));
		return false;
	}
	opened->seek_end();
	file = opened;
	active = true;
	return true;
}

void Recorder::close() {
	if (file.is_valid()) {
		// An explicit flush before the handle goes away: the last lines of a run
		// that is shut down are the ones a report is written from.
		file->flush();
		file->close();
		file.unref();
	}
	active = false;
}

void Recorder::_disable_after_failure(const String &p_reason) {
	if (!disabled_after_failure) {
		// Exactly one warning for the whole run, and it says out loud that the
		// tool calls are unaffected - a debugging side channel must never look
		// like a service failure.
		WARN_PRINT(vformat("[MCP] call trace disabled: %s (file=%s); tool calls are unaffected",
				p_reason, path));
	}
	disabled_after_failure = true;
	active = false;
	if (file.is_valid()) {
		file->close();
		file.unref();
	}
}

bool Recorder::_append(const String &p_line, bool p_counts_as_request) {
	if (!active || file.is_null()) {
		return false;
	}
	if (write_fault_after_for_tests >= 0 && lines_written >= write_fault_after_for_tests) {
		_disable_after_failure(vformat("injected write fault after %d line(s)", write_fault_after_for_tests));
		return false;
	}

	// One `store_string` call per record. The HTTP pump, the tool handlers and
	// this recorder all run on the main thread inside one frame, so a line can
	// never be interleaved with another line even when several connections are
	// served in the same frame: two interleaved connections produce two
	// consecutive records, never a torn one.
	file->store_string(p_line + "\n");
	if (file->get_error() != OK) {
		_disable_after_failure("write failed");
		return false;
	}
	// Flushed per line so that an observer can tail the file while the observed
	// process is still running (and so that a crash keeps every line written
	// before it).
	file->flush();
	if (file->get_error() != OK) {
		_disable_after_failure("flush failed");
		return false;
	}

	// TASK-044: a side-channel line (`event:"capture"`) shares the file and the
	// flush, but neither counter of the request stream - `seq` is the
	// correlation key between a call line and its capture line, and
	// `get_lines_written()` stays "requests recorded" for every caller that
	// already reads it (including the TASK-038 doctests and the injected-write
	// fault seam below).
	if (p_counts_as_request) {
		lines_written++;
		seq++;
	} else {
		event_lines_written++;
	}
	return true;
}

String Recorder::_build_line(uint64_t p_connection_id, const Record &p_record, uint64_t p_duration_ms, uint64_t p_pending_ms) const {
	Dictionary fields;
	fields["seq"] = seq + 1;
	fields["ts_ms"] = _wall_clock_ms();
	fields["connection"] = (int64_t)p_connection_id;
	fields["method"] = p_record.method;
	fields["ok"] = p_record.ok;
	fields["error_code"] = p_record.error_code;

	bool message_truncated = false;
	fields["error_message"] = _truncate_utf8(p_record.error_message, max_message_bytes, message_truncated);
	fields["error_message_truncated"] = message_truncated;

	fields["duration_ms"] = (int64_t)p_duration_ms;
	fields["result_bytes"] = p_record.result_bytes;

	if (p_record.method == "tools/call") {
		fields["tool"] = p_record.tool;
		bool args_truncated = false;
		fields["args"] = _truncate_utf8(p_record.args_json, max_args_bytes, args_truncated);
		fields["args_bytes"] = p_record.args_bytes;
		fields["args_truncated"] = args_truncated;

		// TASK-089 (item A): the file-side side effects of exactly this call.
		// [REBUILT-2C low-confidence: verify] TASK-089 item A: written, not
		// replayed; REBUILT-2C-MANIFEST.md 2c-8 (H-1).
		// `file_effect_status` is only set when a recording really ran around the
		// tool, so an absence of both fields means "this trace predates the
		// recorder or the trace switch was off" and never "nothing changed".
		if (!p_record.file_effect_status.is_empty()) {
			fields["file_effect_status"] = p_record.file_effect_status;
			fields["file_effects"] = p_record.file_effects;
		}
		// [/REBUILT-2C]
	}

	if (p_record.is_tools_list) {
		fields["tools"] = p_record.tool_count;
	}

	if (p_record.deferred) {
		fields["pending_ms"] = (int64_t)p_pending_ms;
		fields["timeout_ms"] = (int64_t)p_record.timeout_ms;
	}

	// TASK-044: the capture extension's half of the call line. Only present when
	// the switch is on and this request is a `tools/call` the capture path really
	// took on (`pending`) or had to refuse (`unavailable`).
	if (p_record.capture_present) {
		Dictionary capture;
		capture["mode"] = p_record.capture_mode;
		capture["viewport"] = p_record.capture_viewport;
		capture["status"] = p_record.capture_status;
		if (!p_record.capture_reason.is_empty()) {
			capture["reason"] = p_record.capture_reason;
		}
		fields["capture"] = capture;
	}

	// The `id` is spliced in verbatim so that the line carries the same JSON type
	// the client used (`1` stays a number, `"a"` stays a string) - the observer
	// correlates trace lines with the client's own requests by that token. A
	// token that does not parse as a JSON value (it never comes from a valid
	// request, but the recorder must not be the place a corrupt line is born) is
	// written as `null`.
	String id_token = p_record.id_json;
	if (id_token.is_empty()) {
		id_token = "null";
	} else {
		// `JSON::parse_string()` answers the parsed `Variant` (and `NIL` for a
		// failure, which a literal `null` would also answer), so the error
		// reporting entry point is the one to ask here.
		JSON id_probe;
		if (id_probe.parse(id_token) != OK) {
			id_token = "null";
		}
	}

	const String body = JSON::stringify(fields);
	if (body == "{}") {
		return String("{\"id\":") + id_token + "}";
	}
	return String("{\"id\":") + id_token + "," + body.substr(1);
}

void Recorder::record(uint64_t p_connection_id, const Record &p_record, uint64_t p_duration_ms, uint64_t p_pending_ms) {
	if (!active || !p_record.traceable) {
		return;
	}
	_append(_build_line(p_connection_id, p_record, p_duration_ms, p_pending_ms));
}

bool Recorder::record_event_line(const Dictionary &p_fields) {
	if (!active) {
		return false;
	}
	// A side-channel line is a plain JSON object: the `id` splice of
	// `_build_line` is specific to a request line (it echoes the client's token
	// verbatim, including its JSON type), and an event has no request to echo.
	return _append(JSON::stringify(p_fields), false);
}

} // namespace MCPTrace
