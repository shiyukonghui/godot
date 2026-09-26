/**************************************************************************/
/*  mcp_jsonrpc.h                                                         */
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

#include "mcp_deferred.h"
#include "tool_registry.h"

#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// JSON-RPC 2.0 + MCP dispatch. Envelope shapes, error codes and messages are
// byte-for-byte compatible with the reference GDExtension implementation
// (see DESIGN-DETAIL.md GDR-6 and utils/error.rs).
namespace MCPJsonRpc {

// The canonical code values live in `tool_registry.h` (enum MCPErrorCode) so
// that the tool layer and the transport can never disagree about them.
enum {
	PARSE_ERROR = MCP_ERR_PARSE_ERROR,
	INVALID_REQUEST = MCP_ERR_INVALID_REQUEST,
	METHOD_NOT_FOUND = MCP_ERR_METHOD_NOT_FOUND,
	INVALID_PARAMS = MCP_ERR_INVALID_PARAMS,
	INTERNAL_ERROR = MCP_ERR_INTERNAL_ERROR,
	NO_SCENE = MCP_ERR_TOOL_STATE,
	NOT_FOUND = MCP_ERR_NOT_FOUND,
};

struct Response {
	String body;
	int http_status = 200;
};

// The result of dispatching one payload (GDR-20).
//
// A tool of the deferred family cannot answer inside this frame, so the
// dispatch does not fabricate a response for it: it hands the transport the
// task to adopt, plus everything the transport needs to address the eventual
// response (`id_json`, the connection is known to the transport) and to arm the
// deadline (`timeout_ms`, already clamped against the framework ceiling).
struct Dispatch {
	// Valid when `!deferred`.
	Response response;
	bool deferred = false;
	// Owned by the caller once `deferred` is true. The transport adopts it in
	// its pending table (or deletes it when it refuses the call).
	MCPDeferred::Task *task = nullptr;
	// The verbatim `id` token of the request.
	String id_json;
	// The effective deadline in milliseconds; 0 means "no deadline".
	uint64_t timeout_ms = 0;
	// Filled for the transport's diagnostics.
	String tool_name;
	// TASK-038: the facts of this request for the opt-in call trace. Left
	// untouched - `traceable == false` - unless the caller asked for it, so a
	// build and a process with the trace switched off do no trace work at all.
	MCPTrace::Record trace;
};

// {"jsonrpc":"2.0","id":<id>,"result":<result>}
String build_result(const Variant &p_id, const Variant &p_result);

// {"jsonrpc":"2.0","id":<id>,"error":{"code":<c>,"message":<m>[,"data":<d>]}}
String build_error(const Variant &p_id, int p_code, const String &p_message, const Variant &p_data = Variant());

// The same two envelopes, for a caller that already holds the *verbatim* `id`
// token of a request that was read several frames ago. Building the body for a
// late response must not re-parse the original payload: re-parsing would have
// to happen exactly as it did the first time (raw token, braces, whitespace),
// and a mismatch there would either corrupt the id or change its JSON type.
String build_result_raw(const String &p_id_json, const Variant &p_result);
String build_error_raw(const String &p_id_json, int p_code, const String &p_message, const Variant &p_data = Variant());

// Full dispatch of one payload. `p_is_editor` selects the tool scope of the
// current process. `id` is echoed verbatim (string, number or null).
//
// `p_default_timeout_ms` is the framework ceiling for a deferred request
// (`mcp_server/pending_timeout_ms`, 0 = the transport has no deadline), and the
// tool's own deadline can only *lower* it.
//
// TASK-038: `p_trace` asks the dispatcher to describe the request in
// `Dispatch::trace`. It is `false` by default and is only ever `true` from the
// transport, when a recorder is open - the switch of the trace is therefore also
// the switch of its cost.
Dispatch dispatch(const String &p_payload, const MCPToolRegistry &p_registry, bool p_is_editor, uint64_t p_default_timeout_ms = 0, bool p_trace = false);

// The one-frame-only entry point, kept for the unit tests and for any caller
// that has no frame loop. A deferred tool is refused with `-32603`: there is no
// way to advance it here, and answering it with a single tick would be the
// same-frame lie GDR-20 removes.
Response handle(const String &p_payload, const MCPToolRegistry &p_registry, bool p_is_editor);

} // namespace MCPJsonRpc