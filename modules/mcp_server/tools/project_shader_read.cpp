/**************************************************************************/
/*  project_shader_read.cpp                                               */
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
#include "project_shader_read.h"

#include "shader_shared.h"
#include "tool_helpers.h"

#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/io/resource_loader.h"

using namespace MCPTools;

namespace {

// The same `.gdshader` guard the two write tools use: this reader is *the*
// shader reader, not a second `project_read_file`.
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

int64_t file_byte_size(const String &p_path) {
	Error error = OK;
	const Vector<uint8_t> bytes = FileAccess::get_file_as_bytes(p_path, &error);
	return error == OK ? (int64_t)bytes.size() : -1;
}

} // namespace

namespace MCPTools {

bool read_shader_file(const String &p_path, Dictionary &r_out, MCPToolError &r_error) {
	String path;
	if (!require_shader_path(p_path, path, r_error)) {
		return false;
	}
	String content;
	if (!read_project_text_file(path, content, r_error)) {
		// `read_project_text_file` answers -32001 with the path; add the shader
		// family's next step so the refusal is actionable.
		if (r_error.code == MCP_ERR_NOT_FOUND) {
			r_error = MCPToolError::not_found(vformat("Shader file '%s'", path),
					"Use project_create_shader to create it, or project_search_file_names to find the right path");
		}
		return false;
	}
	String mode_name;
	String directive;
	const int mode = shader_code_mode(content, mode_name, directive);

	Dictionary out;
	out["path"] = path;
	out["content"] = content;
	out["bytes"] = file_byte_size(path);
	out["lines"] = content.split("\n").size();
	out["declares_shader_type"] = mode >= 0;
	out["shader_type"] = mode >= 0 ? String(shader_mode_name(mode)) : String();
	r_out = out;
	return true;
}

bool shader_params_of(const String &p_path, Dictionary &r_out, MCPToolError &r_error) {
	String path;
	if (!require_shader_path(p_path, path, r_error)) {
		return false;
	}
	const Ref<Resource> loaded = ResourceLoader::load(path);
	if (loaded.is_null()) {
		r_error = MCPToolError::not_found(vformat("Shader resource '%s'", path),
				"'path' is loaded with ResourceLoader::load; name a .gdshader in this project "
				"(project_search_file_names lists the files of the project)");
		return false;
	}
	Shader *shader = Object::cast_to<Shader>(loaded.ptr());
	if (shader == nullptr) {
		r_error = MCPToolError::invalid_params(vformat("'%s' holds a %s, not a Shader", path, loaded->get_class()));
		return false;
	}
	const Array params = shader_uniform_records(shader);

	Dictionary out;
	out["path"] = path;
	out["shader_type"] = shader_mode_name(shader->get_mode());
	out["param_count"] = params.size();
	out["params"] = params;
	if (params.is_empty()) {
		// The engine exposes no "did it compile" flag, and a shader that failed to
		// compile reports the same empty list as a valid shader with no uniform;
		// saying so is the honest answer (PLAYBOOK section 5: no silent claims).
		out["note"] = "The engine reports no shader parameter for this shader. A valid shader with no uniform and a "
					  "shader that failed to compile answer the same list (Shader exposes no compile-status flag).";
	}
	r_out = out;
	return true;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

static Variant _tool_read_shader(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	if (path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'path' must not be empty");
		return Variant();
	}
	Dictionary out;
	if (!read_shader_file(path, out, r_error)) {
		return Variant();
	}
	return out;
}

static Variant _tool_get_shader_params(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	if (path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'path' must not be empty");
		return Variant();
	}
	Dictionary out;
	if (!shader_params_of(path, out, r_error)) {
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
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_shader_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_shader_read_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_get_shader_params", String::utf8(R"desc(获取着色器参数列表)desc"));
		builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"path":{"type":"string"}},"required":["path"],"type":"object"})schema"));
		builder.handler(_tool_get_shader_params).register_into(r_registry);
	}
	{
		ToolBuilder builder("project_read_shader", String::utf8(R"desc(读取着色器文件)desc"));
		builder.channel("project").verb("read").scope(MCPToolScope::BOTH).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"path":{"type":"string"}},"required":["path"],"type":"object"})schema"));
		builder.handler(_tool_read_shader).register_into(r_registry);
	}
}
