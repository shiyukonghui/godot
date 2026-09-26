/**************************************************************************/
/*  tool_builder.cpp                                                      */
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
#include "tool_builder.h"

#include "core/config/engine.h"
#include "core/error/error_macros.h"
#include "core/io/file_access.h"
#include "core/io/json.h"

namespace MCPTools {

bool is_editor_process() {
	Engine *engine = Engine::get_singleton();
	return engine != nullptr && engine->is_editor_hint();
}

// ---------------------------------------------------------------------------
// ToolBuilder
// ---------------------------------------------------------------------------

ToolBuilder::ToolBuilder(const String &p_name, const String &p_description) {
	def.name = p_name;
	def.description = p_description;
}

ToolBuilder &ToolBuilder::channel(const String &p_channel) {
	def.channel = p_channel;
	has_channel = true;
	return *this;
}

ToolBuilder &ToolBuilder::verb(const String &p_verb) {
	def.verb = p_verb;
	has_verb = true;
	return *this;
}

ToolBuilder &ToolBuilder::scope(MCPToolScope p_scope) {
	def.scope = p_scope;
	has_scope = true;
	return *this;
}

ToolBuilder &ToolBuilder::mutating(bool p_mutating) {
	def.mutating = p_mutating;
	has_mutating = true;
	return *this;
}

ToolBuilder &ToolBuilder::schema(const Dictionary &p_schema) {
	def.input_schema = p_schema;
	return *this;
}

ToolBuilder &ToolBuilder::handler(Variant (*p_handler)(const Dictionary &p_args, MCPToolError &r_error)) {
	def.handler = p_handler;
	has_handler = true;
	return *this;
}

ToolBuilder &ToolBuilder::pending_handler(MCPDeferred::Task *(*p_handler)(const Dictionary &p_args, MCPToolError &r_error)) {
	def.pending_handler = p_handler;
	has_pending_handler = true;
	return *this;
}

bool ToolBuilder::build(MCPToolDef &r_def, String &r_reason) const {
	// A successful build must never leave the reason of a previous failure
	// behind: the caller reads `r_reason` only when the return value is false,
	// but a stale message is exactly what ends up in a misleading error report.
	r_reason = String();

	Vector<String> missing;
	if (def.name == StringName()) {
		missing.push_back("name");
	}
	if (!has_channel) {
		missing.push_back("channel");
	}
	if (!has_verb) {
		missing.push_back("verb");
	}
	if (!has_scope) {
		missing.push_back("scope");
	}
	if (!has_mutating) {
		missing.push_back("mutating");
	}
	if (!has_handler && !has_pending_handler) {
		missing.push_back("handler");
	}
	if (has_handler && has_pending_handler) {
		r_reason = vformat("MCPTools::ToolBuilder: tool '%s' must declare exactly one of handler / pending_handler (GDR-20).",
				String(def.name));
		return false;
	}
	if (!missing.is_empty()) {
		r_reason = vformat("MCPTools::ToolBuilder: tool '%s' must declare %s explicitly (GDR-16 / GDR-18).",
				String(def.name), String(", ").join(missing));
		return false;
	}

	// The registry lints again; doing it here as well makes the failure point at
	// the builder call site instead of only at registration.
	String lint_error;
	if (!MCPToolRegistry::validate_tool_name(String(def.name), def.channel, def.verb, lint_error)) {
		r_reason = lint_error;
		return false;
	}

	r_def = def;
	return true;
}

bool ToolBuilder::register_into(MCPToolRegistry &r_registry) const {
	MCPToolDef built;
	String reason;
	if (!build(built, reason)) {
		ERR_PRINT(reason);
		return false;
	}
	if (built.scope == MCPToolScope::EDITOR && !is_editor_process()) {
		// Expected in a game process, not an error: the tool is editor-only and
		// this process will never be able to serve it.
		return false;
	}
	return r_registry.register_tool(built);
}

Dictionary empty_object_schema() {
	Dictionary schema;
	schema["type"] = "object";
	schema["properties"] = Dictionary();
	schema["required"] = Array();
	return schema;
}

// ---------------------------------------------------------------------------
// Argument validation
// ---------------------------------------------------------------------------

static String _type_error_message(const String &p_key, const Variant &p_value, const String &p_expected) {
	return vformat("Parameter '%s' must be %s, got %s", p_key, p_expected, Variant::get_type_name(p_value.get_type()));
}

// TASK-010 section 3.3: the only values this function may hand back are ones the
// conversion is actually defined for. `(int64_t)number` is undefined behaviour
// for a double outside [INT64_MIN, INT64_MAX] and for NaN/INF, and what the
// compiler then produces is an implementation detail (this fork is built with
// `/fp:strict`; MSVC's x64 `cvttsd2si` yields INT64_MIN, another target may
// yield 0). The old code compared that junk back to the double and usually
// refused - usually is not a contract. The range test runs first, so a value
// that does not fit is refused deterministically, with no cast executed at all.
static const double INT64_MAX_AS_DOUBLE = 9223372036854775808.0; // 2^63, the first out-of-range value

bool integral_value(const Variant &p_value, int64_t &r_out) {
	if (p_value.get_type() == Variant::INT) {
		r_out = (int64_t)p_value;
		return true;
	}
	if (p_value.get_type() == Variant::FLOAT) {
		// JSON-RPC clients are allowed to spell an integer as `2.0`.
		const double number = (double)p_value;
		// `>=` / `<` against 2^63 (the only bound a double can express exactly
		// here): every accepted value is inside [INT64_MIN, INT64_MAX] because
		// INT64_MAX rounds up to 2^63 as a double. NaN compares false against
		// both bounds and is refused by the same test.
		if (!(number >= -INT64_MAX_AS_DOUBLE && number < INT64_MAX_AS_DOUBLE)) {
			return false;
		}
		const int64_t truncated = (int64_t)number;
		if ((double)truncated == number) {
			r_out = truncated;
			return true;
		}
	}
	return false;
}

bool require_string(const Dictionary &p_args, const String &p_key, String &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter: " + p_key);
		return false;
	}
	if (value.get_type() != Variant::STRING) {
		r_error = MCPToolError::invalid_params(_type_error_message(p_key, value, "a string"));
		return false;
	}
	r_out = value;
	return true;
}

bool require_int(const Dictionary &p_args, const String &p_key, int64_t &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter: " + p_key);
		return false;
	}
	if (!integral_value(value, r_out)) {
		r_error = MCPToolError::invalid_params(_type_error_message(p_key, value, "an integer"));
		return false;
	}
	return true;
}

bool optional_string(const Dictionary &p_args, const String &p_key, const String &p_default, String &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = p_default;
		return true;
	}
	if (value.get_type() != Variant::STRING) {
		r_error = MCPToolError::invalid_params(_type_error_message(p_key, value, "a string"));
		return false;
	}
	r_out = value;
	return true;
}

bool optional_int(const Dictionary &p_args, const String &p_key, int64_t p_default, int64_t &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = p_default;
		return true;
	}
	if (!integral_value(value, r_out)) {
		r_error = MCPToolError::invalid_params(_type_error_message(p_key, value, "an integer"));
		return false;
	}
	return true;
}

bool optional_bool(const Dictionary &p_args, const String &p_key, bool p_default, bool &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = p_default;
		return true;
	}
	if (value.get_type() != Variant::BOOL) {
		r_error = MCPToolError::invalid_params(_type_error_message(p_key, value, "a boolean"));
		return false;
	}
	r_out = value;
	return true;
}

// ---------------------------------------------------------------------------
// Result envelope
// ---------------------------------------------------------------------------

Dictionary content_result(const Variant &p_payload) {
	Dictionary text_entry;
	text_entry["type"] = "text";
	text_entry["text"] = JSON::stringify(p_payload);

	Array content;
	content.push_back(text_entry);

	Dictionary result;
	result["content"] = content;
	return result;
}

// ---------------------------------------------------------------------------
// Disk / resource access
// ---------------------------------------------------------------------------

static const char *PROJECT_ROOT = "res://";

bool normalize_project_path(const String &p_input, String &r_out, MCPToolError &r_error) {
	String path = p_input.strip_edges();
	if (path.is_empty()) {
		path = PROJECT_ROOT;
	}
	const String root = String(PROJECT_ROOT);
	if (!path.begins_with(root)) {
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'path' must address the project ('res://...'), got '%s'", p_input));
		return false;
	}
	// `..` is rejected on the raw remainder, *before* any folding: a folding
	// rule must never be able to turn a rejected path into an accepted one.
	if (path.contains("..")) {
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'path' must not walk upwards with '..', got '%s'", p_input));
		return false;
	}
	// D-4 (TASK-003 section 1.3): fold `.` segments and empty / whitespace-only
	// segments away, so what is echoed back (and what is opened) is the
	// canonical path: `res://.` -> `res://`, `res://src/.` -> `res://src`,
	// `res:// ` -> `res://`, `res://a//b` -> `res://a/b`. Non-empty segments
	// keep their own bytes, so a real directory name may still contain spaces.
	String normalized = root;
	const Vector<String> segments = path.substr(root.length()).split("/", true);
	for (int i = 0; i < segments.size(); i++) {
		const String segment = segments[i];
		const String trimmed = segment.strip_edges();
		if (trimmed.is_empty() || trimmed == ".") {
			continue;
		}
		if (normalized.length() > root.length()) {
			normalized += "/";
		}
		normalized += segment;
	}
	r_out = normalized;
	return true;
}

Ref<DirAccess> open_project_dir(const String &p_path, MCPToolError &r_error) {
	Ref<DirAccess> dir = DirAccess::open(p_path);
	if (dir.is_null()) {
		r_error = MCPToolError::not_found(vformat("Directory '%s'", p_path),
				"Call the tool without 'path' (or with 'res://') to address the project root");
		return Ref<DirAccess>();
	}
	return dir;
}

bool read_project_text_file(const String &p_path, String &r_out, MCPToolError &r_error) {
	if (!FileAccess::exists(p_path)) {
		r_error = MCPToolError::not_found(vformat("File '%s'", p_path),
				"Use project_get_filesystem_tree to list the files of the project");
		return false;
	}
	Ref<FileAccess> file = FileAccess::open(p_path, FileAccess::READ);
	if (file.is_null()) {
		r_error = MCPToolError::not_found(vformat("File '%s'", p_path),
				"The file exists but could not be opened for reading");
		return false;
	}
	r_out = file->get_as_text();
	file->close();
	return true;
}

String file_extension(const String &p_file_name) {
	// The extension is deliberately *not* lowercased: both callers mirror the
	// reference addon, whose whitelist (`project.rs:216`) and suffix test
	// (`batch.rs:461-464`) are case sensitive.
	const int dot = p_file_name.rfind_char('.');
	if (dot < 0) {
		return String();
	}
	return p_file_name.substr(dot + 1);
}

} // namespace MCPTools