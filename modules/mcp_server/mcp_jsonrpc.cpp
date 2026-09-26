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

Response handle(const String &p_payload, const MCPToolRegistry &p_registry, bool p_is_editor) {
	JSON json;
	if (json.parse(p_payload) != OK) {
		return _error_response("null", PARSE_ERROR, "Parse error", 400);
	}

	const Variant data = json.get_data();
	if (data.get_type() != Variant::DICTIONARY) {
		return _error_response("null", INVALID_REQUEST, "Invalid request: request must be a JSON object");
	}

	const String id_json = _extract_raw_id(p_payload);
	const Dictionary request = (Dictionary)data;

	const Variant method_value = request.get("method", Variant());
	if (method_value.get_type() != Variant::STRING) {
		return _error_response(id_json, INVALID_REQUEST, "Invalid request: missing method");
	}
	const String method = (String)method_value;

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

		return _result_response(200, _envelope_result(id_json, result));
	}

	if (method == "notifications/initialized") {
		// A notification carries no body at all.
		return _result_response(202, String());
	}

	if (method == "tools/list") {
		Dictionary result;
		result["tools"] = p_registry.build_tools_list(p_is_editor);
		return _result_response(200, _envelope_result(id_json, result));
	}

	if (method == "tools/call") {
		return _handle_tools_call(id_json, request.get("params", Variant()), p_registry, p_is_editor);
	}

	if (method == "ping") {
		return _result_response(200, _envelope_result(id_json, Dictionary()));
	}

	return _error_response(id_json, METHOD_NOT_FOUND, vformat("Method not found: %s", method));
}


String build_result_raw(const String &p_id_json, const Variant &p_result) {
	return _envelope_result(p_id_json, p_result);
}

String build_error_raw(const String &p_id_json, int p_code, const String &p_message, const Variant &p_data) {
	return _envelope_error(p_id_json, p_code, p_message, p_data);
}

} // namespace MCPJsonRpc
