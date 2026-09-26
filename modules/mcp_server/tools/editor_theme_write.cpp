/**************************************************************************/
/*  editor_theme_write.cpp                                                */
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
#include "editor_theme_write.h"

#include "tool_helpers.h"

#include "core/io/json.h"
#include "core/io/resource_loader.h"
#include "scene/gui/control.h"
#include "scene/resources/theme.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-034 section 1: the engine reference behind this tool.
//
//   * `Control::set_theme(const Ref<Theme> &)` (scene/gui/control.h:801) and
//     `Control::get_theme()` (:802) - the pair the tool is built on. Passing a
//     null ref is the engine's own "no local theme" state, which is why an
//     omitted `theme_path` is a *clear* and the answer reports `cleared: true`
//     rather than a write.
//   * `ResourceLoader::load` + `Object::cast_to<Theme>` - the engine's own way
//     to turn `res://...` into the resource, with a refusal that names the class
//     that was really loaded (the migration source refused a non-Theme too,
//     `theme.rs:99-103`, but answered `theme_applied: true` for a call with no
//     theme at all, `theme.rs:264-271`).
//   * `MCPTools::normalize_project_path` - every path this module echoes is
//     folded (`res://a/./b` -> `res://a/b`, PLAYBOOK section 6.7).
// ---------------------------------------------------------------------------

namespace MCPTools {

Dictionary set_control_theme_on(Node *p_root, const String &p_node_path, const String &p_theme_path,
		bool p_theme_path_given, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the nodes that are there");
		return Dictionary();
	}
	Control *control = Object::cast_to<Control>(node);
	if (control == nullptr) {
		// `Control::set_theme` only exists on a Control; the engine's own class
		// answer is what the refusal names.
		r_error = MCPToolError::invalid_params(vformat(
				"Node '%s' is a %s, not a Control: a theme is a property of Control (Control::set_theme), so this tool "
				"cannot apply one to it",
				p_node_path, node->get_class()));
		return Dictionary();
	}

	const String raw_theme_path = p_theme_path_given ? p_theme_path.strip_edges() : String();
	if (raw_theme_path.is_empty()) {
		// The engine's own "no local theme" state. The migration source returned
		// success here without calling anything; this clears and says so.
		control->set_theme(Ref<Theme>());
		const Ref<Theme> after_clear = control->get_theme();
		if (after_clear.is_valid()) {
			r_error = MCPToolError::internal(vformat(
					"Control::set_theme(null) did not clear the theme of '%s' (it still answers a %s)", p_node_path,
					after_clear->get_class()));
			return Dictionary();
		}
		Dictionary cleared;
		cleared["node_path"] = relative_path(p_root, control);
		cleared["type"] = control->get_class();
		cleared["cleared"] = true;
		cleared["theme_applied"] = false;
		cleared["theme"] = Variant();
		cleared["theme_path"] = String();
		return cleared;
	}

	String theme_path;
	if (!normalize_project_path(raw_theme_path, theme_path, r_error)) {
		return Dictionary();
	}
	const Ref<Resource> loaded = ResourceLoader::load(theme_path);
	if (loaded.is_null()) {
		r_error = MCPToolError::not_found(vformat("Theme resource '%s'", theme_path),
				"'theme_path' is loaded with ResourceLoader::load; name a .tres/.res Theme in this project "
				"(project_get_filesystem_tree lists the files of the project)");
		return Dictionary();
	}
	Theme *loaded_theme = Object::cast_to<Theme>(loaded.ptr());
	if (loaded_theme == nullptr) {
		r_error = MCPToolError::invalid_params(vformat("'%s' holds a %s, not a Theme", theme_path,
				loaded->get_class()));
		return Dictionary();
	}
	const Ref<Theme> theme = Ref<Theme>(loaded_theme);

	control->set_theme(theme);
	// Read back through the engine: the theme the Control really holds, and its
	// own path - so "applied" is an observation (GDR-25 section 23.4/23.5).
	const Ref<Theme> stored = control->get_theme();
	if (stored.is_null()) {
		r_error = MCPToolError::internal(vformat("Control::set_theme('%s') left the Control with no theme", theme_path));
		return Dictionary();
	}
	Dictionary out;
	out["node_path"] = relative_path(p_root, control);
	out["type"] = control->get_class();
	out["theme_path"] = theme_path;
	out["theme"] = serialize_variant(Variant((Object *)stored.ptr()));
	out["applied"] = true;
	out["theme_applied"] = true;
	out["cleared"] = false;
	// The engine's own type list, so "the theme is really there and really holds
	// something" is visible without a second tool call.
	List<StringName> theme_types;
	stored->get_type_list(&theme_types);
	out["theme_type_count"] = theme_types.size();
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tool
// ---------------------------------------------------------------------------

static Variant _tool_set_control_theme(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	String theme_path;
	if (!optional_string(p_args, "theme_path", String(), theme_path, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor theme writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_control_theme_on(root, node_path, theme_path, p_args.has("theme_path"), r_error);
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character.
// ---------------------------------------------------------------------------
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_theme_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_theme_write_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("editor_set_control_theme", String::utf8(R"desc(对 Control 节点应用主题)desc"));
	builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
	builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"},"theme_path":{"type":"string"}},"required":["node_path"],"type":"object"})schema"));
	builder.handler(_tool_set_control_theme).register_into(r_registry);
}