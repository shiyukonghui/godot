/**************************************************************************/
/*  editor_physics_read.cpp                                               */
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
#include "editor_physics_read.h"

#include "physics_shared.h"
#include "tool_helpers.h"

#include "core/io/json.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-035 section 1: the engine reference behind these two reads.
//
//   * a collision shape is a `CollisionShape2D`/`CollisionShape3D` node with a
//     `shape` (`Shape2D`/`Shape3D`) resource in an `Object`-typed property and a
//     `disabled` flag; a polygon body part is `CollisionPolygon2D`/`3D`. The class
//     name plus the engine's own property reads are the whole answer - the shape
//     resource is serialized as the module's `{type, path}` object shape
//     (GDR-25 section 23.5), which the write tools can load back.
//   * a shape's **owning body** is the nearest ancestor that declares
//     `collision_layer` (the property `Object::get_property_list` reports with
//     `PROPERTY_HINT_LAYERS_*`); walking `Node::get_parent()` is the engine's own
//     tree relation, and the path is asked as `Node::get_path_to` from the
//     subtree root, so it is a real engine path rather than a hand-joined string
//     (the migration source built `"<node_path>/<name>"` by concatenation,
//     `godot_mcp_gdext/src/commands/physics.rs:237`).
//   * the walk is `Node::get_child(i)` in index order: the engine's child order,
//     so two calls on the same tree answer the same array (PLAYBOOK section 6.8).
// ---------------------------------------------------------------------------

namespace {

bool is_collision_shape_class(const String &p_class) {
	return p_class == "CollisionShape2D" || p_class == "CollisionShape3D" ||
			p_class == "CollisionPolygon2D" || p_class == "CollisionPolygon3D";
}

// The nearest ancestor (including the node itself) that carries the layer
// members; an empty path when there is none.
String owning_body_path(Node *p_root, Node *p_node) {
	Node *current = p_node;
	while (current != nullptr) {
		if (object_has_property(current, StringName("collision_layer"))) {
			return relative_path(p_root, current);
		}
		if (current == p_root) {
			break;
		}
		current = current->get_parent();
	}
	return String();
}

void collect_collision_nodes(Node *p_root, Node *p_node, Array &r_shapes, Array &r_objects) {
	const String class_name = p_node->get_class();
	const String path = relative_path(p_root, p_node);

	if (is_collision_shape_class(class_name)) {
		Dictionary record;
		record["node_path"] = path;
		record["type"] = class_name;
		const StringName disabled_name("disabled");
		record["disabled"] = object_has_property(p_node, disabled_name) ? (bool)p_node->get(disabled_name) : false;
		const StringName shape_name("shape");
		if (object_has_property(p_node, shape_name)) {
			record["shape"] = serialize_variant(p_node->get(shape_name));
			record["has_shape"] = Object::cast_to<Resource>(p_node->get(shape_name)) != nullptr;
		} else {
			record["shape"] = Variant();
			record["has_shape"] = false;
		}
		record["owner_body"] = owning_body_path(p_root, p_node);
		r_shapes.push_back(record);
	}

	if (object_has_property(p_node, StringName("collision_layer"))) {
		Dictionary record;
		record["node_path"] = path;
		record["type"] = class_name;
		record["dimension"] = p_node->is_class("CollisionObject3D") ? "3d" : "2d";
		const uint32_t layer = (uint32_t)(int64_t)p_node->get(StringName("collision_layer"));
		const uint32_t mask = (uint32_t)(int64_t)p_node->get(StringName("collision_mask"));
		record["collision_layer"] = (int64_t)layer;
		record["collision_mask"] = (int64_t)mask;
		record["collision_layer_bits"] = physics_layer_bits(layer);
		record["collision_mask_bits"] = physics_layer_bits(mask);
		record["collision_layer_names"] = physics_layer_names_of_mask(p_node, layer);
		record["collision_mask_names"] = physics_layer_names_of_mask(p_node, mask);
		r_objects.push_back(record);
	}

	for (int i = 0; i < p_node->get_child_count(); i++) {
		Node *child = p_node->get_child(i);
		if (child != nullptr) {
			collect_collision_nodes(p_root, child, r_shapes, r_objects);
		}
	}
}

} // namespace

namespace MCPTools {

Dictionary collision_info_at(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the nodes that are there");
		return Dictionary();
	}
	Array shapes;
	Array objects;
	collect_collision_nodes(p_root, node, shapes, objects);

	Dictionary out;
	out["node_path"] = relative_path(p_root, node);
	out["node_type"] = node->get_class();
	out["shape_count"] = shapes.size();
	out["collision_shapes"] = shapes;
	out["object_count"] = objects.size();
	out["collision_objects"] = objects;
	return out;
}

Dictionary physics_layers_at(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the nodes that are there");
		return Dictionary();
	}
	return physics_layers_record(node, relative_path(p_root, node), r_error);
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

namespace {

bool require_node_path(const Dictionary &p_args, String &r_node_path, MCPToolError &r_error) {
	if (!require_string(p_args, "node_path", r_node_path, r_error)) {
		return false;
	}
	if (r_node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return false;
	}
	return true;
}

} // namespace

static Variant _tool_get_collision_info(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!optional_string(p_args, "node_path", ".", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty (pass \".\" for the edited scene root)");
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor physics reads outside a running editor",
				"Start the MCP server inside the Godot editor to read editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return collision_info_at(root, node_path, r_error);
}

static Variant _tool_get_physics_layers(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_node_path(p_args, node_path, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor physics reads outside a running editor",
				"Start the MCP server inside the Godot editor to read editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return physics_layers_at(root, node_path, r_error);
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
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_physics_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_physics_read_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_get_collision_info", String::utf8(R"desc(获取碰撞信息)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_get_collision_info).register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_get_physics_layers", String::utf8(R"desc(获取物理层信息)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"}},"required":["node_path"],"type":"object"})schema"));
		builder.handler(_tool_get_physics_layers).register_into(r_registry);
	}
}
