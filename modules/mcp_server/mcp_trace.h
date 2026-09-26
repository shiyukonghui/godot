/**************************************************************************/
/*  mcp_trace.h                                                           */
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

#include "core/io/file_access.h"
#include "core/string/ustring.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

// ---------------------------------------------------------------------------
// Opt-in server-side call trace (TASK-038).
//
// The MCP server is asked to answer "what did the client really do", not "what
// did the client say it did". A client's own log is the *observed party's*
// account of itself: the friction it silently worked around (calls that failed
// before the right shape was found, arguments it probed, waiting it did) is
// exactly the part such a log omits. This records the raw facts on the server
// side, once per JSON-RPC request, into a JSON Lines file that an observer can
// read while the process is still running.
//
// Two hard constraints shape the whole design:
//
//   1. **Off by default.** No switch means no file is opened and no line is
//      built. `parse()` answers `enabled = false` and nothing in the dispatch
//      path does any extra work (the JSON-RPC layer only fills a `Record` when
//      it is told to).
//   2. **The trace is a bystander.** It is never allowed to change a tool's
//      observable behaviour: a failed write disables the recorder (one stderr
//      warning, no repeating, no exception) and the tool call goes on as if the
//      trace had never been requested.
//
// Like the port resolution (GDR-4), the switch has a command line form
// (`--mcp-trace=<path>` / `--mcp-trace <path>`) that wins over
// `ProjectSettings: godot_mcp/trace_file`, and a default of "off".
// ---------------------------------------------------------------------------

namespace MCPTrace {

struct Config {
	bool enabled = false;
	String path;
	bool explicit_cmdline = false;
	bool from_project_setting = false;
};

// Priority: `--mcp-trace=<path>` / `--mcp-trace <path>` > `ProjectSettings:
// godot_mcp/trace_file` > off. An empty path (either an empty command line value
// or an empty setting) is not a file name, so it does not enable anything.
Config parse(const Vector<String> &p_cmdline_args, bool p_has_setting, const String &p_setting_path);

// ---------------------------------------------------------------------------
// TASK-054 (O-12): the generation marker.
//
// The file is append-only and a wrapper may reuse the same path across runs, so
// a trace collected from three processes was one file with three `seq == 1`
// lines and no way to tell where one run ended and the next began
// (REPORT-AUDIT-RACING-BACKLOG section 5.12: 28 lines, 3 generations, no
// `trace_opened`). Every process that opens the file now writes exactly one
// `{"event":"trace_opened", ...}` line before it serves anything, and
// `scripts/analyze_mcp_trace.py` cuts the file on those lines.
//
// It is an **event** line, not a request line: it goes through
// `Recorder::record_event_line()`, so it does not consume a `seq` and does not
// move `get_lines_written()` - the first request of every generation is still
// `seq == 1`, and every existing field of a request line is untouched.
//
// `version` is spelled exactly like `--version` prints it
// (`main/main.cpp:319-325`: `GODOT_VERSION_FULL_BUILD` + `.` + the first nine
// characters of the build hash), so a trace can be tied to the binary that wrote
// it.
// ---------------------------------------------------------------------------
Dictionary build_trace_opened_fields(bool p_is_editor, int p_port, bool p_listen);

// ---------------------------------------------------------------------------
// TASK-063 (a): the "this process serves no endpoint" event line.
//
// The generation marker above is written *before* the bind is attempted (it has
// to be: it is what cuts the file into generations), so its `listen: false` says
// "not listening" without saying why. When the bind really fails, this second
// event line records the three facts the failure must not lose - the port that
// was requested, the error the engine answered, and the reason the module
// diagnosed - because there is no endpoint left to ask and, without
// `--mcp-trace`, no record at all beyond the log.
//
// It is an **event** line on the same terms as the marker: no `seq`, no effect
// on `get_lines_written()`, and it is only written when a bind was attempted and
// failed (so a normal run's trace is byte-identical to what it was).
// ---------------------------------------------------------------------------
Dictionary build_endpoint_disabled_fields(bool p_is_editor, int p_requested_port, int p_error,
		const String &p_reason);

namespace Limits {
// Long arguments are recorded truncated: the trace is a debugging side channel,
// not a copy of the project. `args_bytes` always carries the true size.
const int DEFAULT_MAX_ARGS_BYTES = 4096;
const int DEFAULT_MAX_MESSAGE_BYTES = 512;
} // namespace Limits

// Everything the JSON-RPC layer knows about one request, plus what the
// transport learns when the response is actually produced.
//
// `traceable` is the single flag the JSON-RPC layer sets: when the trace is
// switched off it is never set, so none of the string work below happens at all.
struct Record {
	bool traceable = false;
	// The JSON-RPC method. Empty for a payload that did not parse into a request
	// object at all (the `-32700` / `-32600` family); the trace still records the
	// attempt, with `ok = false`.
	String method;
	// The `params.name` of a `tools/call`, *before* the registry is consulted, so
	// that a name which does not exist is still on record (`-32601`).
	String tool;
	// `params.arguments` as canonical JSON (keys sorted by `JSON::stringify`), or
	// `null`. Only set for `tools/call`.
	String args_json = "null";
	// The true UTF-8 length of `args_json`, before any truncation.
	int args_bytes = 0;
	// The verbatim `id` token of the request, so the trace line carries the same
	// JSON type the client used (number vs string).
	String id_json = "null";
	bool ok = true;
	int error_code = 0;
	String error_message;
	// Set by the transport: the UTF-8 length of the complete JSON-RPC response
	// body it wrote (or queued) back to the connection.
	int result_bytes = 0;
	// `tools/list` only: the number of tools in the answer. The list itself is
	// deliberately not recorded (it is a contract, not a call).
	bool is_tools_list = false;
	int tool_count = 0;
	// The call was handed to the deferred channel; `ok`/`error_code` are only
	// known when the completion arrives (`pending_ms` and `timeout_ms` are
	// recorded on that line).
	bool deferred = false;
	uint64_t timeout_ms = 0;

	// TASK-044: the optional before/after capture extension (GDR-27). Every
	// member here is inert - `capture_present == false` - unless
	// `--mcp-capture` is on, so a process that did not ask for capture writes
	// exactly the line TASK-038 wrote.
	//
	// The call line carries `capture:{mode, viewport, status[, reason]}`; the
	// pictures and the verdict are a *separate* line (`{"event":"capture",...}`)
	// appended after the response, which is why `capture_token` exists: it names
	// the in-flight entry in the capture engine's table.
	bool capture_present = false;
	String capture_mode;
	String capture_viewport;
	// "pending" (a capture line will follow) or "unavailable" (this call cannot
	// be captured, `capture_reason` says why).
	String capture_status;
	String capture_reason;
	int capture_token = -1;

	// TASK-089 (item A): the **file-side** half of "did this call do anything".
	// [REBUILT-2C low-confidence: verify] TASK-089 item A: written, not replayed
	// (no recording carries a file-side field). Registered in
	// REBUILT-2C-MANIFEST.md section 2c-8 (H-1).
	// The capture extension above observes the screen; neither it nor anything
	// else observed the disk, which is the gap MCP-TRACEABILITY.md §3.2 declared
	// as `file_effect_evidence: "not_recorded_in_trace"`.
	//
	// `file_effects` is one row per destination the call mutated (`write` /
	// `delete` / `mkdir`), each carrying the absolute path, the sha256 and byte
	// count before and after, whether they really differ, and - for a small text
	// destination - a bounded head/tail line difference. `file_effect_status`
	// summarises the rows (`no_mutation` / `observed_changed` /
	// `observed_no_change` / `observed_mixed`).
	//
	// Both are empty exactly when the call carries no file-side evidence at all:
	// the trace was off, the method was not `tools/call`, or the request was
	// refused before a tool ran. The fields are emitted on the **call line**, at
	// the same level as `id` / `method` / `tool` (see `_build_line`).
	Array file_effects;
	String file_effect_status;

	// TASK-089 (F2): the **result body** of a successful `tools/call`, as the
	// tool produced it (canonical JSON, truncated by the same limit `args` uses).
	//
	// Why it is needed, from the round-7 session: `running_game_assert_node_state`
	// answered `{"passed": false, ...}` inside an `ok` response, and the line
	// carried only `result_bytes`. "The call succeeded" and "the thing it was
	// asked about really holds" are different facts, and a trace that cannot show
	// the second one cannot be used to judge an assertion. The same applies to a
	// response whose own fields contradict each other (`created: true` next to
	// `existed_before: true`). `result_json_bytes` is the true size, so
	// `result_json_truncated` never hides how much was dropped.
	String result_json;
	int result_json_bytes = 0;

	// TASK-090 (item A): the **failure payload** of a `tools/call` that answered a
	// JSON-RPC error, as the tool produced it - `data.suggestion`,
	// `data.parse_error` and anything else the tool layer attached to the error.
	//
	// Why it is needed: until this field existed the trace carried only
	// `error_code` and a 512 byte `error_message`, so the one thing a caller
	// actually needs to *act* on a failure - the machine-readable reason and the
	// named line - was visible to the client and invisible to the observer. The
	// round-7 session measured the cost: a body that did not compile answered
	// `-32602 "Parameter 'code' does not compile: Parse error"` with the line and
	// the cause sitting in `data.parse_error`, unreadable from the trace.
	//
	// It shares the success half's shape and bounds on purpose: the same
	// `max_args_bytes` ceiling, the same canonical `JSON::stringify`, and
	// `error_data_json_bytes` always carries the true size, so
	// `error_data_json_truncated` never hides how much was dropped.
	//
	// Emitted on **every** failed `tools/call` line, `""` when the tool attached
	// no data, so that "this trace has the field" and "this failure had no payload"
	// stay distinguishable from "this trace was written before the field existed".
	String error_data_json;
	int error_data_bytes = 0;
	// [/REBUILT-2C]
};

// Appends one JSON object per request to one file. Never propagates a failure.
class Recorder {
public:
	Recorder() = default;
	~Recorder();

	Recorder(const Recorder &) = delete;
	Recorder &operator=(const Recorder &) = delete;

	// Opens `p_path` for appending (creating it when it does not exist). Answers
	// false - after one warning - when the file cannot be used; the recorder
	// stays disabled from then on.
	bool open(const String &p_path);
	void close();

	bool is_active() const { return active; }
	bool is_disabled_after_failure() const { return disabled_after_failure; }
	const String &get_path() const { return path; }
	// Number of lines written so far, and the next `seq` value (1 based).
	int get_lines_written() const { return lines_written; }
	int get_seq() const { return seq; }

	void set_max_args_bytes(int p_bytes);
	void set_max_message_bytes(int p_bytes);

	// Test seam: make every append fail once `p_lines` lines have been written
	// (`-1` disables the fault). A real write error cannot be provoked from a
	// test without depending on the platform's file sharing rules, and the
	// "a failed write disables the trace, it does not disturb the call" contract
	// is exactly what has to be pinned.
	void set_write_fault_after_for_tests(int p_lines);

	// Emits one line. No-op when disabled or when the record is not traceable.
	// `p_duration_ms` is the wall time from the arrival of the request to the
	// production of its response; `p_pending_ms` is the part of it spent in the
	// deferred channel (0 for an immediate answer).
	void record(uint64_t p_connection_id, const Record &p_record, uint64_t p_duration_ms, uint64_t p_pending_ms);

	// TASK-044: appends one side-channel line (`{"event":"capture", ...}`) to the
	// same file. It deliberately does **not** consume a request sequence number:
	// `seq` counts JSON-RPC requests (GDR-26 point 2), and the capture line
	// carries the `seq` of the call line it belongs to. Returns false when the
	// recorder is not active; a failed append disables the recorder exactly like
	// a request line's does.
	bool record_event_line(const Dictionary &p_fields);

	// Number of side-channel lines written so far (never counted by
	// `get_lines_written()`, which stays "requests recorded").
	int get_event_lines_written() const { return event_lines_written; }

private:
	String _build_line(uint64_t p_connection_id, const Record &p_record, uint64_t p_duration_ms, uint64_t p_pending_ms) const;
	bool _append(const String &p_line, bool p_counts_as_request = true);
	void _disable_after_failure(const String &p_reason);

	Ref<FileAccess> file;
	String path;
	bool active = false;
	bool disabled_after_failure = false;
	int seq = 0;
	int lines_written = 0;
	int event_lines_written = 0;
	int max_args_bytes = Limits::DEFAULT_MAX_ARGS_BYTES;
	int max_message_bytes = Limits::DEFAULT_MAX_MESSAGE_BYTES;
	int write_fault_after_for_tests = -1;
};

} // namespace MCPTrace
