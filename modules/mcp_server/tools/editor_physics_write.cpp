/**************************************************************************/
/*  editor_physics_write.cpp                                              */
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
#include "editor_physics_write.h"

#include "physics_shared.h"
#include "tool_helpers.h"

#include "core/io/json.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-035 section 1: the engine reference behind this tool.
//
//   * `CollisionObject2D`/`CollisionObject3D` store the two masks as `uint32_t`
//     members (`scene/2d/physics/collision_object_2d.h:52-53`,
//     `scene/3d/physics/collision_object_3d.h:52`), exposed as `collision_layer`
//     and `collision_mask` with `PROPERTY_HINT_LAYERS_*`; `Object::get` answers
//     the stored `uint32_t` as an `INT`, which is the read-back this tool compares
//     the request against.
//   * the range check is done here, not left to the engine: there is no
//     `ValueSlot` for a `uint32_t` (the four slots are `WIDE`, `REAL_T`, `INT32`,
//     `UINT8`, GDR-22 section 20.1) and `Variant::operator uint32_t()` truncates
//     silently, so `4294967296` would land as `0` next to `applied: true`.
//     `0 .. 0xFFFFFFFF` is the member's real width, and a bitmask has no negative
//     values.
//   * the layer *names* are project settings
//     (`layer_names/<2d|3d>_physics/layer_<n>`, `scene/register_scene_types.cpp:1320/1324`),
//     read through `ProjectSettings::get_setting` so the answer says which named
//     layers the new mask turns on.
// ---------------------------------------------------------------------------

namespace {

String layer_type_list() {
	return "'collision' (collision_layer) or 'mask' (collision_mask)";
}

// `layer_type` is a closed set: the migration source's fall-through default wrote
// `collision` for any typo while echoing the typo back.
bool resolve_layer_property(const String &p_layer_type, StringName &r_property, MCPToolError &r_error) {
	const String value = p_layer_type.strip_edges();
	if (value == "collision") {
		r_property = StringName("collision_layer");
		return true;
	}
	if (value == "mask") {
		r_property = StringName("collision_mask");
		return true;
	}
	r_error = MCPToolError::invalid_params(vformat(
			"'layer_type' must be one of %s; got '%s'", layer_type_list(), p_layer_type));
	return false;
}

} // namespace

namespace MCPTools {

Dictionary set_physics_layers_on(Node *p_root, const String &p_node_path, const String &p_layer_type,
		int64_t p_layers, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the nodes that are there");
		return Dictionary();
	}
	StringName property;
	if (!resolve_layer_property(p_layer_type, property, r_error)) {
		return Dictionary();
	}
	// The member's real width: 32 unsigned bits. There is no `ValueSlot` for it
	// (GDR-22 section 20.1 lists four), so the check is explicit and lives right
	// here, before the node is touched at all; the report lists it as a new
	// narrowing point with this line and the doctest as its evidence (GDR-24
	// section 22.3b rule 4).
	if (p_layers < 0 || p_layers > (int64_t)0xFFFFFFFFll) {
		r_error = MCPToolError::invalid_params(vformat(
				"'layers' must be a 32-bit layer mask in 0..4294967295 (the width of the engine's uint32_t "
				"collision_layer/collision_mask member); got %d. A value outside that range would be truncated by "
				"the engine's own copy (4294967296 would land as 0)",
				p_layers));
		return Dictionary();
	}
	if (!object_has_property(node, property)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Node '%s' is a %s and has no '%s' member: physics layers live on a "
				"CollisionObject2D/CollisionObject3D (CharacterBody2D, RigidBody3D, Area2D, ...)",
				p_node_path, node->get_class(), String(property)));
		return Dictionary();
	}
	const uint32_t requested = (uint32_t)p_layers;
	const int64_t previous = (int64_t)(uint32_t)(int64_t)node->get(property);
	node->set(property, Variant((int64_t)requested));
	const int64_t stored = (int64_t)(uint32_t)(int64_t)node->get(property);
	if ((uint32_t)stored != requested) {
		r_error = MCPToolError::internal(vformat(
				"Writing %d into '%s' of '%s' stored %d instead", (int64_t)requested, String(property),
				p_node_path, stored));
		return Dictionary();
	}

	Dictionary out;
	out["node_path"] = relative_path(p_root, node);
	out["node_type"] = node->get_class();
	out["dimension"] = node->is_class("CollisionObject3D") ? "3d" : "2d";
	out["layer_type"] = p_layer_type.strip_edges();
	out["property"] = String(property);
	out["layers"] = (int64_t)requested;
	out["previous_layers"] = previous;
	out["new_value"] = stored;
	out["applied"] = true;
	out["changed"] = previous != stored;
	out["layer_count"] = physics_layer_count();
	out["layer_bits"] = physics_layer_bits(requested);
	out["layer_names"] = physics_layer_names_of_mask(node, requested);
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tool
// ---------------------------------------------------------------------------

static Variant _tool_set_physics_layers(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	int64_t layers = 0;
	if (!require_int(p_args, "layers", layers, r_error)) {
		return Variant();
	}
	String layer_type;
	if (!optional_string(p_args, "layer_type", "collision", layer_type, r_error)) {
		return Variant();
	}
	StringName property;
	if (!resolve_layer_property(layer_type, property, r_error)) {
		return Variant();
	}
	if (layers < 0 || layers > (int64_t)0xFFFFFFFFll) {
		r_error = MCPToolError::invalid_params(vformat(
				"'layers' must be a 32-bit layer mask in 0..4294967295 (the width of the engine's uint32_t "
				"collision_layer/collision_mask member); got %d",
				layers));
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor physics writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_physics_layers_on(root, node_path, layer_type, layers, r_error);
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
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_physics_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_physics_write_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("editor_set_physics_layers", String::utf8(R"desc(设置物理层)desc"));
	builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
	builder.schema(_schema_from_json(R"schema({"properties":{"layer_type":{"default":"collision","type":"string"},"layers":{"type":"integer"},"node_path":{"type":"string"}},"required":["node_path","layers"],"type":"object"})schema"));
	builder.handler(_tool_set_physics_layers).register_into(r_registry);
}