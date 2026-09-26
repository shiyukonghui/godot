/**************************************************************************/
/*  project_script_write.cpp                                              */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/
#include "project_script_write.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// The compile-time half of the editor guard (TASK-002 section 2.2.3): the
// post-write filesystem notification is an editor-only extra and the group is
// `scope = both`, so in a game build the whole branch disappears and the write
// itself is unaffected.
#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/editor_interface.h"
#include "editor/file_system/editor_file_system.h"
#endif

using namespace MCPTools;

// ---------------------------------------------------------------------------
// project_create_script (old `create_script`, script.rs:105) and
// project_edit_script (old `edit_script`, script.rs:159)
//
// Observable contract (as implemented), and the divergences from the migration
// source, which the report lists one by one:
//
//   * `path` is normalized (`res://a/./b` -> `res://a/b`, PLAYBOOK section 6.7)
//     and must end in `.gd` or `.cs` (case insensitive, the migration source's
//     `_guard_script_file_path`, script_commands.gd:17-29). Anything else is
//     `-32602` with the extension named: writing a `.tscn` through the script
//     tool is how a scene gets replaced by a script.
//   * the rename contract's `create_script` carries `content` + `template`,
//     *not* the migration source's `extends` / `class_name` / `force`
//     (`docs/tools_list.renamed.json` is the authority for the argument set), so
//     `template` is the base class and the generated body is the migration
//     source's own template (script_commands.gd:124-134) with `Node` defaulted.
//   * a create over an existing file is allowed - it is a write tool - but the
//     answer's `existed_before` says so, and the old bytes are preserved by the
//     atomic publish until the new ones are known to be complete.
//   * `edit_script`'s argument grammar is the contract's: `content` **or**
//     `search`+`replace`. The migration source's `replacements` array,
//     `start_line`/`end_line` and `insert_at_line` modes are not in the renamed
//     schema, so they are not accepted; asking for two modes at once is refused
//     rather than guessed.
//   * text lengths are UTF-8 **bytes**, not characters (PLAYBOOK section 6.9),
//     and they are measured from the file that was published, not from the
//     string in memory.
// ---------------------------------------------------------------------------

namespace MCPTools {

// The writer behind `publish_file_atomically`: the text is handed in through the
// opaque userdata, which outlives the call (the callers keep it in a local).
static Error _text_writer(const String &p_temp_path, void *p_userdata) {
	const String *text = static_cast<const String *>(p_userdata);
	Ref<FileAccess> file = FileAccess::open(p_temp_path, FileAccess::WRITE);
	if (file.is_null()) {
		return FileAccess::get_open_error();
	}
	file->store_string(*text);
	file->close();
	return OK;
}

static bool _write_text_atomically(const String &p_path, const String &p_text, MCPToolError &r_error) {
	// A local copy so the callback has a stable address for the whole call;
	// `publish_file_atomically` never stores it.
	String held = p_text;
	const Error error = publish_file_atomically(p_path, _text_writer, &held);
	if (error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to write '%s': %s",
				p_path, VariantUtilityFunctions::error_string(error)));
		return false;
	}
	return true;
}

// The `.gd` / `.cs` guard. `to_lower()` first, which is the migration source's
// rule: `Player.GD` is a GDScript file.
static bool _require_script_path(const String &p_input, String &r_path, MCPToolError &r_error) {
	if (!normalize_project_path(p_input, r_path, r_error)) {
		return false;
	}
	if (r_path == "res://") {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'path' must name a file, got '%s'", p_input));
		return false;
	}
	const String extension = r_path.get_extension().to_lower();
	if (extension != "gd" && extension != "cs") {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'path' must name a script file (.gd or .cs), got '%s'", r_path));
		return false;
	}
	return true;
}

// A best-effort editor filesystem notification. `project_script_write` is
// `scope = both`, so this must never be able to fail the call: in a game
// process, or in an editor process without an `EditorInterface`, the write has
// already happened and the answer simply reports `editor_rescan_triggered: false`.
// (`EditorFileSystem::scan()` is asynchronous in the editor, so "triggered" is
// the only honest claim - the same wording `editor_rescan_project_filesystem`
// uses.)
static bool _notify_editor_of_script_write() {
#ifdef MCP_EDITOR_TOOLS_ENABLED
	if (!is_editor_process()) {
		return false;
	}
	EditorInterface *editor = EditorInterface::get_singleton();
	EditorFileSystem *filesystem = editor != nullptr ? editor->get_resource_filesystem() : nullptr;
	if (filesystem == nullptr) {
		return false;
	}
	filesystem->scan();
	return true;
#else
	return false;
#endif
}

// The number of UTF-8 bytes the published file holds (PLAYBOOK section 6.9).
static int64_t _published_byte_size(const String &p_path) {
	Error error = OK;
	const Vector<uint8_t> bytes = FileAccess::get_file_as_bytes(p_path, &error);
	return error == OK ? (int64_t)bytes.size() : -1;
}

String script_template_body(const String &p_base_class) {
	// The migration source's template verbatim (script_commands.gd:125-134),
	// including the trailing newline `"\n".join(lines)` produced, minus its
	// optional `class_name` line (the renamed contract has no `class_name`).
	Vector<String> lines;
	lines.push_back("extends " + p_base_class);
	lines.push_back("");
	lines.push_back("");
	lines.push_back("func _ready() -> void:");
	lines.push_back("\tpass");
	lines.push_back("");
	return String("\n").join(lines);
}

bool create_script(const String &p_path, bool p_has_content, const String &p_content, const String &p_template,
		Dictionary &r_out, MCPToolError &r_error) {
	String path;
	if (!_require_script_path(p_path, path, r_error)) {
		return false;
	}
	const String base_class = p_template.strip_edges();
	if (!p_has_content && base_class.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'template' must not be empty when 'content' is absent");
		return false;
	}
	if (!p_has_content && !base_class.is_valid_identifier()) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'template' must be a class name (a valid GDScript identifier), got '%s'", p_template));
		return false;
	}
	const String content = p_has_content ? p_content : script_template_body(base_class);

	const bool existed = FileAccess::exists(path);
	if (!_write_text_atomically(path, content, r_error)) {
		return false;
	}
	const bool rescan = _notify_editor_of_script_write();

	Dictionary out;
	out["path"] = path;
	out["created"] = true;
	out["existed_before"] = existed;
	out["bytes"] = _published_byte_size(path);
	out["template"] = p_has_content ? String() : base_class;
	out["editor_rescan_triggered"] = rescan;
	r_out = out;
	return true;
}

bool edit_script(const String &p_path, bool p_has_content, const String &p_content, bool p_has_search,
		const String &p_search, bool p_has_replace, const String &p_replace,
		Dictionary &r_out, MCPToolError &r_error) {
	String path;
	if (!_require_script_path(p_path, path, r_error)) {
		return false;
	}
	const bool has_replace_mode = p_has_search || p_has_replace;
	if (p_has_content && has_replace_mode) {
		r_error = MCPToolError::invalid_params(
				"Parameters 'content' and 'search'/'replace' are alternatives: 'content' replaces the whole file, "
				"'search'/'replace' edits inside it. Send exactly one of the two modes");
		return false;
	}
	if (!p_has_content && !p_has_search) {
		r_error = MCPToolError::invalid_params(
				"Missing required mode: send 'content' to replace the whole file, or 'search' (with an optional "
				"'replace') to edit inside it");
		return false;
	}
	if (p_has_search && p_search.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'search' must not be empty");
		return false;
	}
	if (!FileAccess::exists(path)) {
		r_error = MCPToolError::not_found(vformat("File '%s'", path),
				"Use project_create_script to create it, or project_list_scripts to find the right path");
		return false;
	}
	String existing;
	if (!read_project_text_file(path, existing, r_error)) {
		return false;
	}

	String content;
	String mode;
	int replacements = 0;
	if (p_has_content) {
		content = p_content;
		mode = "content";
		replacements = 1;
	} else {
		const String replacement = p_has_replace ? p_replace : String();
		// All occurrences, like the migration source's `content.replace(search,
		// replace)`; the count is what makes the answer checkable.
		int from = 0;
		while (true) {
			const int found = existing.find(p_search, from);
			if (found < 0) {
				break;
			}
			existing = existing.substr(0, found) + replacement + existing.substr(found + p_search.length());
			from = found + replacement.length();
			replacements++;
		}
		if (replacements == 0) {
			r_error = MCPToolError::not_found(vformat("Search text in '%s'", path),
					"The file exists but does not contain the 'search' text, so nothing was written. Read it with "
					"project_read_script to see its current content");
			return false;
		}
		content = existing;
		mode = "search_replace";
	}

	if (!_write_text_atomically(path, content, r_error)) {
		return false;
	}
	const bool rescan = _notify_editor_of_script_write();

	Dictionary out;
	out["path"] = path;
	out["changes_made"] = replacements;
	out["mode"] = mode;
	out["replacements"] = replacements;
	out["bytes"] = _published_byte_size(path);
	out["editor_rescan_triggered"] = rescan;
	r_out = out;
	return true;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// Tool wrappers
// ---------------------------------------------------------------------------

static Variant _tool_create_script(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	bool has_content = false;
	String content;
	const Variant content_value = p_args.get("content", Variant());
	if (content_value.get_type() != Variant::NIL) {
		if (content_value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'content' must be a string, got %s",
					Variant::get_type_name(content_value.get_type())));
			return Variant();
		}
		has_content = true;
		content = content_value;
	}
	String base_class;
	if (!optional_string(p_args, "template", "Node", base_class, r_error)) {
		return Variant();
	}
	Dictionary out;
	if (!create_script(path, has_content, content, base_class, out, r_error)) {
		return Variant();
	}
	return out;
}

static Variant _tool_edit_script(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	auto read_optional_string = [&](const String &p_key, bool &r_present, String &r_out) -> bool {
		r_present = false;
		const Variant value = p_args.get(p_key, Variant());
		if (value.get_type() == Variant::NIL) {
			return true;
		}
		if (value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be a string, got %s",
					p_key, Variant::get_type_name(value.get_type())));
			return false;
		}
		r_present = true;
		r_out = value;
		return true;
	};
	bool has_content = false;
	String content;
	bool has_search = false;
	String search;
	bool has_replace = false;
	String replace;
	if (!read_optional_string("content", has_content, content) ||
			!read_optional_string("search", has_search, search) ||
			!read_optional_string("replace", has_replace, replace)) {
		return Variant();
	}
	Dictionary out;
	if (!edit_script(path, has_content, content, has_search, search, has_replace, replace, out, r_error)) {
		return Variant();
	}
	return out;
}

// ---------------------------------------------------------------------------
// Registration
//
// The `description` and `inputSchema` below are the contract entries of
// docs/tools_list.renamed.json, character for character; `channel`/`verb`/
// `scope`/`mutating` come from docs/tool-rename-map.json.
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_script_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_script_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_create_script", String::utf8(R"desc(创建脚本文件)desc"));
		builder.channel("project").verb("create").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"content":{"type":"string"},"path":{"type":"string"},"template":{"default":"Node","type":"string"}},"required":["path"],"type":"object"})schema"));
		builder.handler(_tool_create_script).register_into(r_registry);
	}

	{
		ToolBuilder builder("project_edit_script", String::utf8(R"desc(编辑脚本文件)desc"));
		builder.channel("project").verb("edit").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"content":{"description":"直接替换整个内容","type":"string"},"path":{"type":"string"},"replace":{"type":"string"},"search":{"type":"string"}},"required":["path"],"type":"object"})schema"));
		builder.handler(_tool_edit_script).register_into(r_registry);
	}
}