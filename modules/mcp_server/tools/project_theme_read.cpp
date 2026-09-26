/**************************************************************************/
/*  project_theme_read.cpp                                                */
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
#include "project_theme_read.h"

#include "theme_shared.h"

#include "core/io/json.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-036 section 1: the engine reference behind the one tool.
//
//   * `Theme::get_type_list` (`scene/resources/theme.cpp:1358`) is the engine's
//     own "which theme types does this resource carry", and
//     `get_color_list` / `get_constant_list` / `get_font_size_list` /
//     `get_stylebox_list` are per-type item lists of the four typed maps;
//   * every value is read through its `has_*` predicate first, because
//     `Theme::get_stylebox`/`get_font_size` answer a **global fallback** for an
//     item that is not stored - reporting that as the theme's content would be
//     the same false-success shape this module removes everywhere else;
//   * a font size the engine stored but cannot read back (`<= 0`, see
//     `scene/resources/theme.cpp:661-680`) is listed separately
//     (`font_sizes_stored_not_readable`) instead of being silently dropped from
//     `font_sizes`;
//   * the migration source answered a hard-coded
//     `colors: {"<type>": "(详见 type_list)"}` placeholder and never read a
//     single item (`godot_mcp_gdext/src/commands/theme.rs:305-315`); this tool
//     answers the real maps.
// ---------------------------------------------------------------------------

static Variant _tool_get_theme_info(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!require_string(p_args, "theme_path", raw_path, r_error)) {
		return Variant();
	}
	if (raw_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'theme_path' must not be empty");
		return Variant();
	}
	String path;
	const Ref<Theme> theme = load_theme_resource(raw_path, path, r_error);
	if (theme.is_null()) {
		return Variant();
	}
	return theme_info_of(theme, path);
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
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_theme_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_theme_read_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("project_get_theme_info", String::utf8(R"desc(获取主题信息)desc"));
	builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false);
	builder.schema(_schema_from_json(R"schema({"properties":{"theme_path":{"type":"string"}},"required":["theme_path"],"type":"object"})schema"));
	builder.handler(_tool_get_theme_info).register_into(r_registry);
}
