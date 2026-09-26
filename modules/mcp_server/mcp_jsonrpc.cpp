/**************************************************************************/
/*  mcp_jsonrpc.cpp                                                       */
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

#include "mcp_jsonrpc.h"

#include "mcp_file_effects.h"
#include "tools/tool_builder.h"

#include "core/io/json.h"

namespace MCPJsonRpc {

// ---------------------------------------------------------------------------
// Raw `id` extraction.
//
// Godot's JSON parser turns *every* number into a double, so an integer id
// such as `1` would be echoed back as `1.0`. That is not a cosmetic detail:
// `serde_json::Number::as_u64()` (used by the hof-rs client to correlate
// responses) yields `None` for a float, so the client would see a mismatch on
// every single response. The `id` member is therefore taken verbatim from the
// request text and spliced into the response.
// ---------------------------------------------------------------------------

static void _skip_whitespace(const String &p_text, int &r_index) {
	const int size = p_text.length();
	while (r_index < size && p_text[r_index] <= 32) {
		r_index++;
	}
}

static String _scan_string_token(const String &p_text, int &r_index) {
	const int start = r_index;
	const int size = p_text.length();
	r_index++;
	while (r_index < size) {
		const char32_t c = p_text[r_index];
		if (c == '\\') {
			r_index += 2;
			continue;
		}
		if (c == '"') {
			r_index++;
			break;
		}
		r_index++;
	}
	return p_text.substr(start, r_index - start);
}

static String _scan_balanced_token(const String &p_text, int &r_index) {
	const int start = r_index;
	const int size = p_text.length();
	int depth = 0;
	while (r_index < size) {
		const char32_t c = p_text[r_index];
		if (c == '"') {
			_scan_string_token(p_text, r_index);
			continue;
		}
		if (c == '{' || c == '[') {
			depth++;
			r_index++;
			continue;
		}
		if (c == '}' || c == ']') {
			depth--;
			r_index++;
			if (depth <= 0) {
				break;
			}
			continue;
		}
		r_index++;
	}
	return p_text.substr(start, r_index - start);
}

static String _scan_value_token(const String &p_text, int &r_index) {
	_skip_whitespace(p_text, r_index);
	const int size = p_text.length();
	if (r_index >= size) {
		return String();
	}
	const char32_t c = p_text[r_index];
	if (c == '"') {
		return _scan_string_token(p_text, r_index);
	}
	if (c == '{' || c == '[') {
		return _scan_balanced_token(p_text, r_index);
	}

	const int start = r_index;
	while (r_index < size) {
		const char32_t d = p_text[r_index];
		if (d == ',' || d == '}' || d == ']' || d <= 32) {
			break;
		}
		r_index++;
	}
	return p_text.substr(start, r_index - start);
}

// Returns the verbatim JSON token of the top level `id` member, or "null".
// Nested members are skipped by token, so an `id` inside `params` can never be
// mistaken for the request id.
static String _extract_raw_id(const String &p_payload) {
	int index = 0;
	_skip_whitespace(p_payload, index);
	if (index >= p_payload.length() || p_payload[index] != '{') {
		return "null";
	}
	index++;

	while (index < p_payload.length()) {
		_skip_whitespace(p_payload, index);
		if (index >= p_payload.length() || p_payload[index] == '}') {
			break;
		}
		if (p_payload[index] != '"') {
			break;
		}
		const String key_token = _scan_string_token(p_payload, index);
		_skip_whitespace(p_payload, index);
		if (index < p_payload.length() && p_payload[index] == ':') {
			index++;
		}
		const String value_token = _scan_value_token(p_payload, index);

		if (key_token == "\"id\"") {
			return value_token.is_empty() ? String("null") : value_token;
		}

		_skip_whitespace(p_payload, index);
		if (index < p_payload.length() && p_payload[index] == ',') {
			index++;
			continue;
		}
		break;
	}
	return "null";
}

static String _id_to_json_token(const Variant &p_id) {
	if (p_id.get_type() == Variant::NIL) {
		return "null";
	}
	return JSON::stringify(p_id);
}

static String _envelope_result(const String &p_id_json, const Variant &p_result) {
	return String("{\"id\":") + p_id_json + ",\"jsonrpc\":\"2.0\",\"result\":" + JSON::stringify(p_result) + "}";
}

static String _envelope_error(const String &p_id_json, int p_code, const String &p_message, const Variant &p_data) {
	Dictionary error;
	error["code"] = p_code;
	error["message"] = p_message;
	if (p_data.get_type() != Variant::NIL) {
		error["data"] = p_data;
	}
	return String("{\"error\":") + JSON::stringify(error) + ",\"id\":" + p_id_json + ",\"jsonrpc\":\"2.0\"}";
}

String build_result(const Variant &p_id, const Variant &p_result) {
	// Default `sort_keys = true`, which matches the ordered (BTreeMap) key
	// output of the reference Rust implementation.
	return _envelope_result(_id_to_json_token(p_id), p_result);
}

String build_error(const Variant &p_id, int p_code, const String &p_message, const Variant &p_data) {
	return _envelope_error(_id_to_json_token(p_id), p_code, p_message, p_data);
}

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------

static Response _result_response(int p_http_status, const String &p_body) {
	Response response;
	response.http_status = p_http_status;
	response.body = p_body;
	return response;
}

static Response _error_response(const String &p_id_json, int p_code, const String &p_message, int p_http_status = 200, const Variant &p_data = Variant()) {
	return _result_response(p_http_status, _envelope_error(p_id_json, p_code, p_message, p_data));
}

static Response _handle_tools_call(const String &p_id_json, const Variant &p_params, const MCPToolRegistry &p_registry, bool p_is_editor) {
	if (p_params.get_type() != Variant::NIL && p_params.get_type() != Variant::DICTIONARY) {
		return _error_response(p_id_json, INVALID_PARAMS, "Invalid params: expected an object");
	}

	Dictionary params;
	if (p_params.get_type() == Variant::DICTIONARY) {
		params = (Dictionary)p_params;
	}

	const Variant name_value = params.get("name", Variant());
	if (name_value.get_type() != Variant::STRING || ((String)name_value).is_empty()) {
		return _error_response(p_id_json, INVALID_PARAMS, "Missing tool name");
	}
	const String tool_name = (String)name_value;

	const Variant arguments_value = params.get("arguments", Variant());
	if (arguments_value.get_type() != Variant::NIL && arguments_value.get_type() != Variant::DICTIONARY) {
		return _error_response(p_id_json, INVALID_PARAMS, "Invalid arguments: expected an object");
	}
	Dictionary arguments;
	if (arguments_value.get_type() == Variant::DICTIONARY) {
		arguments = (Dictionary)arguments_value;
	}

	if (!p_registry.is_tool_visible(tool_name, p_is_editor)) {
		// Unknown tool, or a tool that belongs to the other process.
		return _error_response(p_id_json, METHOD_NOT_FOUND, vformat("Method not found: %s", tool_name));
	}

	MCPToolError tool_error;
	const Variant tool_result = p_registry.call_tool(tool_name, arguments, tool_error);
	if (tool_error.is_error()) {
		// The code and the optional `data` (a `suggestion`) come from the tool
		// layer (GDR-6 / GDR-14): -32602 for an argument problem, -32001 for a
		// missing resource, -32000 for a missing state. No `console_output`
		// delta exists in v1, so a failing tool always maps to a JSON-RPC error
		// object (GDR-6, GDR-8).
		return _error_response(p_id_json, tool_error.code, tool_error.message, 200, tool_error.data);
	}

	// `MCPTools::content_result` is the single place that builds the success
	// envelope, so every tool answers with the very same wire shape (GDR-6).
	return _result_response(200, _envelope_result(p_id_json, MCPTools::content_result(tool_result)));
}

// ---------------------------------------------------------------------------
// `_immediate` / `_tag` / `_effective_timeout` / `_dispatch_tools_call`:
// Wraps one immediate response in a `Dispatch`.
static Dispatch _immediate(const Response &p_response) {
	Dispatch dispatch;
	dispatch.response = p_response;
	return dispatch;
}

// is a pass-through that copies nothing.
static Dispatch _tag(Dispatch p_dispatch, const MCPTrace::Record &p_trace) {
	if (p_trace.traceable) {
		p_dispatch.trace = p_trace;
	}
	return p_dispatch;
}

// The effective deadline of a deferred request: the framework ceiling
// (`p_default_timeout_ms`, 0 = none) can only be *lowered* by the tool's own
// deadline (`Task::get_timeout_ms()`, 0 = none). A tool may therefore shorten a
// wait - `running_game_find_node_when_available` does, from its own `timeout`
// parameter - but never extend it past the configured ceiling.
static uint64_t _effective_timeout(uint64_t p_default_timeout_ms, uint64_t p_task_timeout_ms) {
	if (p_task_timeout_ms == 0) {
		return p_default_timeout_ms;
	}
	if (p_default_timeout_ms == 0) {
		return p_task_timeout_ms;
	}
	return MIN(p_task_timeout_ms, p_default_timeout_ms);
}

// TASK-090 (item A): the failure half of "what did this call really answer".
//
// `MCPToolError::data` is where the tool layer puts the machine-readable reason
// (`suggestion`, `parse_error`); the trace carried only the code and the
// 512 byte message, so the observer could see *that* a call failed and not *why*.
// This puts the payload on the record, and an empty string when the failure
// carries none - the field is then still written, which is what makes a missing
// field readable as "old trace" rather than as "no payload".
// [REBUILT-2C low-confidence: verify] TASK-090 item A: written, not replayed
// (no recording carries a failure payload); REBUILT-2C-MANIFEST.md 2c-9 (J-1).
static void _record_error_data(MCPTrace::Record &r_trace, const Variant &p_data) {
	if (!r_trace.traceable) {
		return;
	}
	if (p_data.get_type() == Variant::NIL) {
		r_trace.error_data_json = String();
		r_trace.error_data_bytes = 0;
		return;
	}
	r_trace.error_data_json = JSON::stringify(p_data);
	r_trace.error_data_bytes = r_trace.error_data_json.utf8().length();
}
// [/REBUILT-2C]

static Dispatch _dispatch_tools_call(const String &p_id_json, const Variant &p_params, const MCPToolRegistry &p_registry, bool p_is_editor, uint64_t p_default_timeout_ms, MCPTrace::Record &r_trace) {
	if (p_params.get_type() != Variant::NIL && p_params.get_type() != Variant::DICTIONARY) {
		r_trace.ok = false;
		r_trace.error_code = INVALID_PARAMS;
		r_trace.error_message = "Invalid params: expected an object";
		return _tag(_immediate(_error_response(p_id_json, INVALID_PARAMS, "Invalid params: expected an object")), r_trace);
	}

	Dictionary params;
	if (p_params.get_type() == Variant::DICTIONARY) {
		params = (Dictionary)p_params;
	}

	const Variant name_value = params.get("name", Variant());
	if (name_value.get_type() != Variant::STRING || ((String)name_value).is_empty()) {
		r_trace.ok = false;
		r_trace.error_code = INVALID_PARAMS;
		r_trace.error_message = "Missing tool name";
		return _tag(_immediate(_error_response(p_id_json, INVALID_PARAMS, "Missing tool name")), r_trace);
	}
	const String tool_name = (String)name_value;

	const Variant arguments_value = params.get("arguments", Variant());
	if (arguments_value.get_type() != Variant::NIL && arguments_value.get_type() != Variant::DICTIONARY) {
		r_trace.ok = false;
		r_trace.error_code = INVALID_PARAMS;
		r_trace.error_message = "Invalid arguments: expected an object";



		return _tag(_immediate(_error_response(p_id_json, INVALID_PARAMS, "Invalid arguments: expected an object")), r_trace);
	}
	Dictionary arguments;
	if (arguments_value.get_type() == Variant::DICTIONARY) {
		arguments = (Dictionary)arguments_value;
	}

	if (r_trace.traceable) {
		// The canonical form of the arguments (sorted keys) - the same
		// `JSON::stringify` the wire uses, so "the same arguments twice" is
		// recognisable as such in the trace.
		r_trace.args_json = JSON::stringify(arguments);
		r_trace.args_bytes = r_trace.args_json.utf8().length();
		// [REBUILT-2C low-confidence: verify] TASK-088: the tool name, taken
		// before the registry is consulted, so a call to a tool that does not
		// exist still names itself on the line (`-32601`). Written, not
		// replayed - same reason as the identity block in `dispatch`.
		r_trace.tool = tool_name;
		// [/REBUILT-2C]
	}

	if (!p_registry.is_tool_visible(tool_name, p_is_editor)) {
		// Unknown tool, or a tool that belongs to the other process.
		const String message = vformat("Method not found: %s", tool_name);
		r_trace.ok = false;
		r_trace.error_code = METHOD_NOT_FOUND;
		r_trace.error_message = message;
		return _tag(_immediate(_error_response(p_id_json, METHOD_NOT_FOUND, message)), r_trace);
	}

	MCPToolError tool_error;

	if (p_registry.is_deferred_tool(tool_name)) {
		// GDR-20: the tool answers across frames, so the request is handed over
		// to the transport's pending table instead of being answered here.
		MCPDeferred::Task *task = p_registry.call_deferred_tool(tool_name, arguments, tool_error);		if (tool_error.is_error() || task == nullptr) {
			if (!tool_error.is_error()) {
				tool_error = MCPToolError::internal(vformat("Deferred tool returned no task: %s", tool_name));
			}
			r_trace.ok = false;
			r_trace.error_code = tool_error.code;
			r_trace.error_message = tool_error.message;
			// TASK-090 (item A): the failure payload of a deferred tool that
			// refused before it could be deferred.
			_record_error_data(r_trace, tool_error.data);
			return _tag(_immediate(_error_response(p_id_json, tool_error.code, tool_error.message, 200, tool_error.data)), r_trace);
		}
		Dispatch deferred;
		deferred.deferred = true;
		deferred.task = task;
		deferred.id_json = p_id_json;
		deferred.tool_name = tool_name;
		deferred.timeout_ms = _effective_timeout(p_default_timeout_ms, task->get_timeout_ms());
		// Whether the call succeeded is only known when the completion arrives,
		// so the trace is marked deferred and the transport finishes it.
		r_trace.deferred = true;
		r_trace.timeout_ms = deferred.timeout_ms;
		// TASK-089: a deferred tool's disk work happens after this function has
		// returned (its task is ticked by the transport), so the file-side
		// recorder - which is per-call and synchronous - cannot see it *here*.
		// TASK-092 (item B2) closed the gap at the place the work really happens:
		// `MCPDeferred::Queue::tick` wraps every tick in the same recorder and
		// accumulates its rows for the whole deferred window, and the transport
		// writes that verdict onto this record before the line is emitted. What is
		// set here is therefore a **placeholder for a request that never
		// completes** (its connection went away): it is overwritten on every path
		// that produces a line, and it says "not observed" rather than "nothing
		// changed" - which is what it means.
		// [REBUILT-2C low-confidence: verify] TASK-089 item A: written, not
		// replayed; REBUILT-2C-MANIFEST.md 2c-8 (H-1). TASK-092 item B2 keeps the
		// placeholder and adds the overwrite.
		if (r_trace.traceable) {
			r_trace.file_effect_status = "not_tracked_deferred";
		}
		// [/REBUILT-2C]
		return _tag(deferred, r_trace);
	}

	// TASK-089 (item A): the file-side recorder is opened around the one place a
	// tool is really invoked, so every mutation a tool makes through the
	// module's publish primitives lands in this call's buffer - and no mutation
	// made outside a call is ever attributed to one. With the trace off nothing
	// is opened and no primitive pays for a snapshot.
	// [REBUILT-2C low-confidence: verify] TASK-089 item A: written, not
	// replayed; REBUILT-2C-MANIFEST.md 2c-8 (H-1).
	if (r_trace.traceable) {
		MCPFileEffect::begin_recording();
	}
	const Variant tool_result = p_registry.call_tool(tool_name, arguments, tool_error);
	if (r_trace.traceable) {
		MCPFileEffect::end_recording();
		r_trace.file_effects = MCPFileEffect::take_effects();
		r_trace.file_effect_status = MCPFileEffect::status_name();
	}
	// [/REBUILT-2C]
	if (tool_error.is_error()) {
		// The code and the optional `data` (a `suggestion`) come from the tool
		// layer (GDR-6 / GDR-14): -32602 for an argument problem, -32001 for a
		// missing resource, -32000 for a missing state. No `console_output`
		// delta exists in v1, so a failing tool always maps to a JSON-RPC error
		// object (GDR-6, GDR-8).
		r_trace.ok = false;
		r_trace.error_code = tool_error.code;
		r_trace.error_message = tool_error.message;
		// TASK-090 (item A): `data.suggestion` / `data.parse_error` on the line.
		// [REBUILT-2C low-confidence: verify] TASK-090 item A: written, not
		// replayed; REBUILT-2C-MANIFEST.md 2c-9 (J-1).
		_record_error_data(r_trace, tool_error.data);
		// [/REBUILT-2C]
		return _tag(_immediate(_error_response(p_id_json, tool_error.code, tool_error.message, 200, tool_error.data)), r_trace);
	}

	// `MCPTools::content_result` is the single place that builds the success
	// envelope, so every tool answers with the very same wire shape (GDR-6).
	// [REBUILT-2C low-confidence: verify] TASK-089 F2: the tool's own body, on
	// the call line; written, not replayed (REBUILT-2C-MANIFEST.md 2c-8 (H-6)).
	if (r_trace.traceable) {
		r_trace.result_json = JSON::stringify(tool_result);
		r_trace.result_json_bytes = r_trace.result_json.utf8().length();
	}
	// [/REBUILT-2C]
	r_trace.ok = true;
	return _tag(_immediate(_result_response(200, _envelope_result(p_id_json, MCPTools::content_result(tool_result)))), r_trace);
}


Response handle(const String &p_payload, const MCPToolRegistry &p_registry, bool p_is_editor) {
	Dispatch dispatched = dispatch(p_payload, p_registry, p_is_editor);
	if (!dispatched.deferred) {
		return dispatched.response;
	}
	// No frame loop exists on this path, so the task the tool just produced has
	// to be released here and the call has to be refused. Answering it would
	// mean ticking once and returning the first frame's observation as if it
	// were the whole series (GDR-20).
	const String tool_name = dispatched.tool_name;
	memdelete(dispatched.task);
	return _error_response(dispatched.id_json, INTERNAL_ERROR,
			vformat("Tool '%s' answers across frames and needs the transport's deferred channel (GDR-20)", tool_name));
}
Dispatch dispatch(const String &p_payload, const MCPToolRegistry &p_registry, bool p_is_editor, uint64_t p_default_timeout_ms, bool p_trace) {
	MCPTrace::Record trace;
	trace.traceable = p_trace;
	JSON json;
	if (json.parse(p_payload) != OK) {
		return _tag(_immediate(_error_response("null", PARSE_ERROR, "Parse error", 400)), trace);
	}

	const Variant data = json.get_data();
	if (data.get_type() != Variant::DICTIONARY) {
		return _tag(_immediate(_error_response("null", INVALID_REQUEST, "Invalid request: request must be a JSON object")), trace);
	}

	const String id_json = _extract_raw_id(p_payload);
	const Dictionary request = (Dictionary)data;

	const Variant method_value = request.get("method", Variant());
	if (method_value.get_type() != Variant::STRING) {
		return _tag(_immediate(_error_response(id_json, INVALID_REQUEST, "Invalid request: missing method")), trace);
	}
	const String method = (String)method_value;

	// [REBUILT-2C low-confidence: verify] TASK-088 (item 5): the request
	// identity. The trace line this record becomes carries the RESPONSE half
	// (`ok`, `error_code`, `duration_ms`, `result_bytes`) and, with capture on,
	// the pixel verdict - but the request half was never filled, so a live
	// session produced lines with `"method":""` and `"id":null` while the
	// capture line right next to them named the tool. A trace line that cannot
	// say which request it describes is not traceability, so the four facts the
	// JSON-RPC layer already holds are put on the record here (and `tool` /
	// `tools` below). This is written text, not replayed text: the recorded
	// `dispatch` predates the trace parameter entirely (see the TASK-085 ruling
	// in REBUILT-2C-MANIFEST.md (C)), so no recording carries these lines.
	if (trace.traceable) {
		trace.id_json = id_json;
		trace.method = method;
	}
	// [/REBUILT-2C]

	if (method == "initialize") {
		Dictionary tools_capability;
		tools_capability["listChanged"] = false;

		Dictionary capabilities;
		capabilities["tools"] = tools_capability;
		capabilities["logging"] = Dictionary();

		Dictionary server_info;
		server_info["name"] = "godot-mcp-rs";
		server_info["version"] = "0.1.0";

		Dictionary result;
		result["protocolVersion"] = "2025-03-26";
		result["capabilities"] = capabilities;
		result["serverInfo"] = server_info;

		return _tag(_immediate(_result_response(200, _envelope_result(id_json, result))), trace);
	}

	if (method == "notifications/initialized") {
		// A notification carries no body at all.
		return _tag(_immediate(_result_response(202, String())), trace);
	}

	if (method == "tools/list") {
		Dictionary result;
		result["tools"] = p_registry.build_tools_list(p_is_editor);
		// [REBUILT-2C low-confidence: verify] TASK-088: `tools` is the one field
		// a `tools/list` line is read for (the published table size), and
		// `MCPTrace::_build_line` emits it only when `is_tools_list` is set.
		// Written, not replayed - same reason as the identity block above.
		if (trace.traceable) {
			trace.is_tools_list = true;
			trace.tool_count = p_registry.get_visible_tool_count(p_is_editor);
		}
		// [/REBUILT-2C]
		return _tag(_immediate(_result_response(200, _envelope_result(id_json, result))), trace);
	}

	if (method == "tools/call") {
		return _dispatch_tools_call(id_json, request.get("params", Variant()), p_registry, p_is_editor, p_default_timeout_ms, trace);
	}

	if (method == "ping") {
		return _tag(_immediate(_result_response(200, _envelope_result(id_json, Dictionary()))), trace);
	}

	return _tag(_immediate(_error_response(id_json, METHOD_NOT_FOUND, vformat("Method not found: %s", method))), trace);
}


String build_result_raw(const String &p_id_json, const Variant &p_result) {
	return _envelope_result(p_id_json, p_result);
}

String build_error_raw(const String &p_id_json, int p_code, const String &p_message, const Variant &p_data) {
	return _envelope_error(p_id_json, p_code, p_message, p_data);
}

} // namespace MCPJsonRpc
