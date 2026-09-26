/**************************************************************************/
/*  tool_registry.h                                                       */
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

#include "core/string/string_name.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// Which process a tool is exposed in (GDR-7).
enum class MCPToolScope {
	EDITOR,
	GAME,
	BOTH,
};

// JSON-RPC error codes (GDR-6/GDR-14). They live here because the tool layer is
// what produces a tool error; MCPJsonRpc re-uses these exact values through its
// own enum, so the two definitions can never drift apart.
enum MCPErrorCode {
	MCP_ERR_PARSE_ERROR = -32700,
	MCP_ERR_INVALID_REQUEST = -32600,
	MCP_ERR_METHOD_NOT_FOUND = -32601,
	MCP_ERR_INVALID_PARAMS = -32602,
	MCP_ERR_INTERNAL_ERROR = -32603,
	// GDR-14: the tool ran but the state it needs is absent (no edited scene, or
	// a capability that is deliberately not implemented yet). Always carries
	// `data.suggestion`.
	MCP_ERR_TOOL_STATE = -32000,
	// GDR-14: the tool looked for a concrete thing (scene/node/file/resource) and
	// it is not there.
	MCP_ERR_NOT_FOUND = -32001,
};

// Structured tool failure. `code == 0` means success. A tool never formats a
// JSON-RPC envelope itself: it fills this structure through the factories below
// and `MCPJsonRpc` turns it into the wire error object (GDR-6).
struct MCPToolError {
	int code = 0;
	String message;
	Variant data; // NIL when the error carries no payload.

	bool is_error() const { return code != 0; }

	static MCPToolError invalid_params(const String &p_message);
	static MCPToolError internal(const String &p_message);
	// GDR-14: the call is well formed but the state of the project blocks it
	// (e.g. "the file already exists"). Always carries `data.suggestion`.
	static MCPToolError tool_state(const String &p_message, const String &p_suggestion);
	static MCPToolError no_scene();
	static MCPToolError not_implemented(const String &p_what, const String &p_suggestion = String());
	static MCPToolError not_found(const String &p_what, const String &p_suggestion = String());
};

// Forward declaration of the deferred handle (GDR-20). `mcp_deferred.h` is the
// header that defines it and it includes *this* file, so the dependency runs
// one way only and there is no include cycle. A registered tool is either
// immediate (`handler`) or deferred (`pending_handler`), never both.
namespace MCPDeferred {
class Task;
}

struct MCPToolDef {
	StringName name;
	// GDR-16: explicit naming metadata; both must agree with `name`.
	String channel; // editor | running_game | project | os
	String verb; // member of the closed verb set
	String description;
	// Byte-exact copy of the authoritative `inputSchema` from
	// docs/tools_list.renamed.json.
	Dictionary input_schema;
	MCPToolScope scope = MCPToolScope::BOTH;
	// GDR-18: the most conservative read/write classification of the tool. A
	// conditional write (an optional `save_path`) is `mutating = true`.
	bool mutating = false;
	// Returns the tool result, or fills `r_error` and returns nil.
	// Build tools through `MCPTools::ToolBuilder`, which forces channel, verb,
	// scope and mutating to be declared explicitly instead of defaulted.
	Variant (*handler)(const Dictionary &p_args, MCPToolError &r_error) = nullptr;
	// GDR-20: the deferred half of the same contract. The handler validates its
	// arguments and returns a task the *transport* adopts; the transport owns
	// every later frame. `nullptr` plus a filled `r_error` means the request
	// failed before it could be deferred (a mistyped argument, a node that is
	// not there, a process without a scene), which is answered immediately.
	MCPDeferred::Task *(*pending_handler)(const Dictionary &p_args, MCPToolError &r_error) = nullptr;

	bool is_deferred() const { return pending_handler != nullptr; }
};

// Forward declaration for the single friend below. `tools/tool_builder.h`
// defines it (and includes this header first, so the two spellings agree).
namespace MCPTools {
class ToolBuilder;
}

class MCPToolRegistry {
	HashMap<StringName, MCPToolDef> tools;
	// Insertion order, so that `tools/list` is deterministic.
	Vector<StringName> order;

	// GDR-19 / TASK-003 section 1.6: `MCPTools::ToolBuilder::register_into()` is
	// the *only* legal registration path. A raw `MCPToolDef` handed straight to
	// the registry would skip the builder's explicit-declaration check
	// (GDR-16 lint + GDR-18 `mutating`) and, worse, the editor-process guard of
	// GDR-19 section 17.3 - an editor-only tool could then enter a game build's
	// table. The method is therefore private; `ToolBuilder` is its only friend,
	// and `[MCPServer] register_tool is unreachable outside ToolBuilder` pins
	// that mechanically (a compile-time probe, not a comment).
	//
	// The lint is repeated here on purpose: it is the registry's own invariant,
	// and it must not depend on the caller having gone through `build()` first.
	bool register_tool(const MCPToolDef &p_def);

	friend class MCPTools::ToolBuilder;

public:
	// GDR-16 L1: `<channel>_<verb>_<object>[_<qualifier>]`, channel stripped by
	// longest prefix. Returns false when no channel prefix matches or when the
	// remainder is empty / contains a character outside [a-z0-9_].
	static bool parse_tool_name(const String &p_name, String &r_channel, String &r_verb);
	// GDR-16 L1..L4 plus the declared-metadata cross check. On failure it fills
	// `r_error` with an ASCII reason and returns false.
	static bool validate_tool_name(const String &p_name, const String &p_declared_channel, const String &p_declared_verb, String &r_error);

	// The `scope` spelling of docs/tool-rename-map.json ("editor"/"game"/"both").
	static MCPToolScope scope_from_string(const String &p_scope, bool &r_ok);

	// Number of registered tools, independent of the process scope (diagnostics
	// and the registration idempotence guard).
	int get_tool_count() const { return order.size(); }

	bool has_tool(const StringName &p_name) const;
	bool is_tool_visible(const StringName &p_name, bool p_is_editor) const;
	int get_visible_tool_count(bool p_is_editor) const;

	// Array of {"name", "description", "inputSchema"} dictionaries, filtered by
	// the scope of the current process. Tools that have not been ported yet are
	// never present in the registry, so they can never leak into the listing.
	Array build_tools_list(bool p_is_editor) const;

	// Executes a tool. Fills `r_error` when the tool fails.
	Variant call_tool(const StringName &p_name, const Dictionary &p_args, MCPToolError &r_error) const;

	// True when the tool answers across frames and therefore must be routed
	// through the transport's deferred channel (GDR-20). An unknown tool is not
	// deferred.
	bool is_deferred_tool(const StringName &p_name) const;

	// Starts a deferred tool: validates the arguments and returns the task the
	// *caller* now owns (the transport adopts it in its pending table), or
	// `nullptr` with `r_error` filled when the request is refused before the
	// wait begins.
	MCPDeferred::Task *call_deferred_tool(const StringName &p_name, const Dictionary &p_args, MCPToolError &r_error) const;

	static bool scope_matches(MCPToolScope p_scope, bool p_is_editor);
};