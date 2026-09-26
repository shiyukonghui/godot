/**************************************************************************/
/*  tool_builder.h                                                        */
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

#include "../tool_registry.h"

#include "core/io/dir_access.h"
#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// ---------------------------------------------------------------------------
// Editor / game double target guard (TASK-002 section 2.2.3).
//
// The module is compiled for both the editor and the game target. Godot's own
// macro for "this build contains the editor/tools code" is `TOOLS_ENABLED`; the
// spelling `TOOL_ENABLED` does not exist anywhere in this fork. Editor-only
// engine APIs must be wrapped in this module-level alias, so that
//   (a) a game build simply does not contain the call, and
//   (b) every guard site can be found by grepping one module-owned name.
// The runtime half of the rule is `is_editor_process()` plus the tool scope:
// an editor-only tool is not even registered in a game process.
// ---------------------------------------------------------------------------
#ifdef TOOLS_ENABLED
#define MCP_EDITOR_TOOLS_ENABLED 1
#endif

namespace MCPTools {

// True when the current process is the editor (Engine::is_editor_hint()).
// A game process - and a build without an Engine singleton - returns false.
bool is_editor_process();

// ---------------------------------------------------------------------------
// Tool definition builder (TASK-002 section 2.2.2).
//
// `channel`, `verb`, `scope` and `mutating` must all be declared explicitly.
// The builder refuses to build - and therefore refuses to register - when one of
// them is missing, so no tool can silently inherit a default where GDR-16 or
// GDR-18 required a decision.
// ---------------------------------------------------------------------------
class ToolBuilder {
public:
	ToolBuilder(const String &p_name, const String &p_description);

	ToolBuilder &channel(const String &p_channel);
	ToolBuilder &verb(const String &p_verb);
	ToolBuilder &scope(MCPToolScope p_scope);
	ToolBuilder &mutating(bool p_mutating);
	ToolBuilder &schema(const Dictionary &p_schema);
	ToolBuilder &handler(Variant (*p_handler)(const Dictionary &p_args, MCPToolError &r_error));
	// GDR-20: the deferred alternative to `handler()`. Declaring both is a
	// build failure, because "answer now" and "answer across frames" cannot both
	// describe the same tool.
	ToolBuilder &pending_handler(MCPDeferred::Task *(*p_handler)(const Dictionary &p_args, MCPToolError &r_error));

	// Validates the declared metadata and fills `r_def`.
	// Returns false and fills `r_reason` when a declaration is missing or when
	// the GDR-16 naming lint rejects the name.
	bool build(MCPToolDef &r_def, String &r_reason) const;

	// build() + `MCPToolRegistry::register_tool()`. This is the *only* legal
	// registration path: the registry method is private and this class is its
	// only friend (GDR-19 / TASK-003 section 1.6), and the doctest
	// `[MCPServer] register_tool is unreachable outside ToolBuilder` pins that.
	// Additionally, an
	// `MCPToolScope::EDITOR` tool is not registered at all in a game process
	// (TASK-002 section 2.2.3); the registry would hide it from `tools/list`
	// anyway, but a game process must not even carry it in the table.
	// Returns false when the tool was not declared completely, when the lint
	// rejects it, or when it was skipped because of the process scope.
	bool register_into(MCPToolRegistry &r_registry) const;

private:
	MCPToolDef def;
	bool has_channel = false;
	bool has_verb = false;
	bool has_scope = false;
	bool has_mutating = false;
	bool has_handler = false;
	bool has_pending_handler = false;
};

// The parameterless schema, `{"type":"object","properties":{},"required":[]}`.
Dictionary empty_object_schema();

// ---------------------------------------------------------------------------
// Argument validation (TASK-002 section 2.2.2).
//
// Every failure is `-32602` with a readable message: the helper fills `r_error`
// and returns false, so the call site stays one `if` long. `optional_*` accepts
// an absent key, but a key that is present with the wrong type is an error as
// well - a silently ignored argument is how a caller ends up believing it
// configured something.
// ---------------------------------------------------------------------------
bool require_string(const Dictionary &p_args, const String &p_key, String &r_out, MCPToolError &r_error);
// The module's one "is this value an integer" rule (TASK-010 section 3.3): an
// `INT` passes, and a `FLOAT` passes only when it is finite, inside
// `[INT64_MIN, INT64_MAX]` and exactly representable as an `int64_t` - because
// JSON-RPC clients (and this module's own harness) may spell an integer as
// `2.0`. Exported by TASK-035 so a caller that reads an integer out of a nested
// object uses the same rule: the wire's JSON parser stores every number as a
// `double`, so a member the contract declares `integer` arrives as
// `Variant::FLOAT`, and a reader that only accepted `INT` would refuse it.
bool integral_value(const Variant &p_value, int64_t &r_out);
bool require_int(const Dictionary &p_args, const String &p_key, int64_t &r_out, MCPToolError &r_error);
bool optional_string(const Dictionary &p_args, const String &p_key, const String &p_default, String &r_out, MCPToolError &r_error);
bool optional_int(const Dictionary &p_args, const String &p_key, int64_t p_default, int64_t &r_out, MCPToolError &r_error);
bool optional_bool(const Dictionary &p_args, const String &p_key, bool p_default, bool &r_out, MCPToolError &r_error);

// ---------------------------------------------------------------------------
// Result envelope (GDR-6):
//   `{"content":[{"type":"text","text":"<工具结果的 JSON 字符串>"}]}`
// Built in exactly one place so the wire shape can never drift between tools.
// ---------------------------------------------------------------------------
Dictionary content_result(const Variant &p_payload);

// ---------------------------------------------------------------------------
// Disk / resource access helpers (TASK-002 section 2.2.2).
//
// The module only ever addresses the project (`res://`). A path that points
// elsewhere, or that walks upwards with `..`, is rejected with `-32602`; a
// project path that does not exist is rejected with `-32001` (GDR-14) instead of
// silently returning an empty result, which is what the reference addon did.
//
// D-4 (TASK-003 section 1.3): `.` segments and empty / whitespace-only segments
// are folded away, so the returned value is canonical - `res://.` -> `res://`,
// `res://src/.` -> `res://src`, `res:// ` -> `res://`, `res://a//b` ->
// `res://a/b`. The `..` rejection runs before the folding and is unchanged.
// ---------------------------------------------------------------------------
bool normalize_project_path(const String &p_input, String &r_out, MCPToolError &r_error);
// Opens a project directory. Fails with `-32001` when it does not exist.
Ref<DirAccess> open_project_dir(const String &p_path, MCPToolError &r_error);
// Reads a project text file. Fails with `-32001` when it does not exist.
bool read_project_text_file(const String &p_path, String &r_out, MCPToolError &r_error);
// Extension without the dot (`""` when the name has none). Case is preserved on
// purpose: the reference addon's extension tests are case sensitive.
String file_extension(const String &p_file_name);

} // namespace MCPTools