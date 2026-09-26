/**************************************************************************/
/*  project_shader_write.cpp                                              */
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
#include "project_shader_write.h"

#include "shader_shared.h"
#include "tool_helpers.h"

#include "core/io/file_access.h"
#include "core/io/json.h"

#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/editor_interface.h"
#include "editor/file_system/editor_file_system.h"
#endif

using namespace MCPTools;

namespace {

// The `.gdshader` guard: writing a `.tscn` or a `.gd` through the shader tool is
// how a scene or a script gets replaced by shader text.
bool require_shader_path(const String &p_input, String &r_path, MCPToolError &r_error) {
	if (!normalize_project_path(p_input, r_path, r_error)) {
		return false;
	}
	if (r_path == "res://") {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'path' must name a file, got '%s'", p_input));
		return false;
	}
	if (r_path.get_extension().to_lower() != "gdshader") {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'path' must name a shader file (.gdshader), got '%s'", r_path));
		return false;
	}
	return true;
}

// A best-effort editor filesystem notification, exactly like the script writer's
// (`project_script_write.cpp`): the write already happened, so this can never
// fail the call, and a game process reports `false` honestly.
bool notify_editor_of_shader_write() {
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

int64_t published_byte_size(const String &p_path) {
	Error error = OK;
	const Vector<uint8_t> bytes = FileAccess::get_file_as_bytes(p_path, &error);
	return error == OK ? (int64_t)bytes.size() : -1;
}

bool write_text(const String &p_path, const String &p_text, MCPToolError &r_error) {
	const Error error = publish_text_atomically(p_path, p_text);
	if (error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to write '%s': %s", p_path,
				VariantUtilityFunctions::error_string(error)));
		return false;
	}
	return true;
}

} // namespace

namespace MCPTools {

bool create_shader_file(const String &p_path, const String &p_shader_type, Dictionary &r_out,
		MCPToolError &r_error) {
	String path;
	if (!require_shader_path(p_path, path, r_error)) {
		return false;
	}
	const String given = p_shader_type.strip_edges();
	if (given.is_empty()) {
		r_error = MCPToolError::invalid_params(
				"Parameter 'shader_type' must not be empty: pass the engine's mode directive (\"shader_type "
				"spatial;\") or a bare mode name (\"spatial\")");
		return false;
	}
	String directive = given;
	if (!directive.begins_with("shader_type")) {
		// A bare mode name is the natural shorthand; validate it against the
		// engine's own five modes instead of pasting an unknown word into a file.
		if (shader_mode_from_name(given) < 0) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'shader_type' must be a shader mode directive or one of the engine's modes "
					"(spatial, canvas_item, particles, sky, fog); got '%s'",
					given));
			return false;
		}
		directive = "shader_type " + given.to_lower() + ";";
	} else if (!directive.ends_with(";")) {
		directive += ";";
	}
	String mode_name;
	String parsed_directive;
	const int mode = shader_code_mode(directive, mode_name, parsed_directive);
	if (mode < 0) {
		r_error = MCPToolError::invalid_params(vformat(
				"'shader_type' names a mode the engine does not have; the modes are spatial, canvas_item, particles, "
				"sky and fog (Shader::Mode, scene/resources/shader.h:45-51). Got '%s'",
				directive));
		return false;
	}

	const String content = shader_template(parsed_directive, mode);
	const bool existed = FileAccess::exists(path);
	if (!write_text(path, content, r_error)) {
		return false;
	}
	const bool rescan = notify_editor_of_shader_write();

	Dictionary out;
	out["path"] = path;
	out["created"] = true;
	out["existed_before"] = existed;
	out["shader_type"] = String(shader_mode_name(mode));
	out["directive"] = parsed_directive;
	out["bytes"] = published_byte_size(path);
	out["lines"] = content.split("\n").size();
	out["editor_rescan_triggered"] = rescan;
	r_out = out;
	return true;
}

bool edit_shader_file(const String &p_path, const String &p_code, Dictionary &r_out, MCPToolError &r_error) {
	String path;
	if (!require_shader_path(p_path, path, r_error)) {
		return false;
	}
	if (!FileAccess::exists(path)) {
		r_error = MCPToolError::not_found(vformat("Shader file '%s'", path),
				"Use project_create_shader to create it, or project_search_file_names to find the right path");
		return false;
	}
	String mode_name;
	String directive;
	const int mode = shader_code_mode(p_code, mode_name, directive);
	if (mode == -2) {
		r_error = MCPToolError::invalid_params(vformat(
				"The code declares '%s', which is not one of the engine's shader modes (spatial, canvas_item, "
				"particles, sky, fog)",
				directive));
		return false;
	}
	const int64_t previous_bytes = published_byte_size(path);
	if (!write_text(path, p_code, r_error)) {
		return false;
	}
	const bool rescan = notify_editor_of_shader_write();

	Dictionary out;
	out["path"] = path;
	out["edited"] = true;
	out["bytes"] = published_byte_size(path);
	out["previous_bytes"] = previous_bytes;
	out["lines"] = p_code.split("\n").size();
	out["changes_made"] = 1;
	out["shader_type"] = mode >= 0 ? String(shader_mode_name(mode)) : String();
	out["declares_shader_type"] = mode >= 0;
	out["editor_rescan_triggered"] = rescan;
	r_out = out;
	return true;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

static Variant _tool_create_shader(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	if (path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'path' must not be empty");
		return Variant();
	}
	String shader_type;
	if (!optional_string(p_args, "shader_type", "shader_type spatial;", shader_type, r_error)) {
		return Variant();
	}
	Dictionary out;
	if (!create_shader_file(path, shader_type, out, r_error)) {
		return Variant();
	}
	return out;
}

static Variant _tool_edit_shader(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	if (path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'path' must not be empty");
		return Variant();
	}
	String code;
	if (!require_string(p_args, "code", code, r_error)) {
		return Variant();
	}
	Dictionary out;
	if (!edit_shader_file(path, code, out, r_error)) {
		return Variant();
	}
	return out;
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character.
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_shader_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_shader_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_create_shader", String::utf8(R"desc(创建着色器文件)desc"));
		builder.channel("project").verb("create").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"path":{"type":"string"},"shader_type":{"default":"shader_type spatial;","type":"string"}},"required":["path"],"type":"object"})schema"));
		builder.handler(_tool_create_shader).register_into(r_registry);
	}
	{
		ToolBuilder builder("project_edit_shader", String::utf8(R"desc(编辑着色器代码)desc"));
		builder.channel("project").verb("edit").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"code":{"type":"string"},"path":{"type":"string"}},"required":["path","code"],"type":"object"})schema"));
		builder.handler(_tool_edit_shader).register_into(r_registry);
	}
}