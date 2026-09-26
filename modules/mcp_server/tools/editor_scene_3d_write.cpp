/**************************************************************************/
/*  editor_scene_3d_write.cpp                                             */
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
#include "editor_scene_3d_write.h"

#include "tool_helpers.h"

#include "core/io/json.h"
#include "core/io/resource_loader.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/resources/material.h"
#include "scene/resources/mesh.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-034 section 1: the engine reference behind this tool.
//
//   * `MeshInstance3D::set_surface_override_material(int p_surface, const
//     Ref<Material> &p_material)` (mesh_instance_3d.cpp:375) with
//     `ERR_FAIL_INDEX(p_surface, surface_override_materials.size())` (:376); the
//     array is sized to the mesh's surface count in `set_mesh` (:120-160), so the
//     valid range is exactly `mesh->get_surface_count()`.
//     `get_surface_override_material_count()` (:371) answers the same size, and
//     `get_surface_override_material(int)` (:387) is the read-back. The migration
//     source hard-coded `0` (`scene_3d.rs:142`) after reading a `material_slot`
//     argument it never used (:131) - this is M4c's E-4, and the accepted
//     `surface_index`-shaped GDScript sibling
//     (`addons/godot_mcp/commands/scene_3d_commands.gd:285,351-356`) shows the
//     index is what the reference *meant*.
//   * the slot's material is also readable as the node's own
//     `surface_material_override/<i>` property - `MeshInstance3D::_get_property_list`
//     registers one per surface (mesh_instance_3d.cpp:113-117) - which is what
//     `editor_get_node_properties` lists, so the value written here can be
//     verified by a *different* tool.
//   * `ResourceLoader::load` + `Object::cast_to<Material>` - the engine's own
//     load, with a refusal naming the class that was really loaded (the migration
//     source ran a `load(...)` inside a GDScript `Expression` and answered
//     `set: true` even when the expression produced nothing, `scene_3d.rs:139-158`).
//   * the answer's `material` uses the module's `{type, path}` object shape
//     (GDR-25 section 23.5), which `coerce_to_property_type`'s OBJECT branch
//     loads back.
//   * TASK-035 section 0 changed the *declaration* of `material_slot` from
//     `string` to `integer` (the engine's own shape) through the contract
//     generator's `SCHEMA_OVERRIDES`; the implementation accepts the integer,
//     an integral JSON float and the previous decimal-string spelling, and
//     answers the slot as an integer so the value can be fed back in.
// ---------------------------------------------------------------------------

namespace {

// `material_slot` is an **integer** surface index in the contract since
// TASK-035 section 0 (schema override, generator 1.10.0). A JSON number of the
// integer type arrives as `Variant::INT`; a float that holds a whole number is
// accepted because JSON numbers are doubles in the wire format; and the old
// contract's decimal *string* spelling is still accepted so no caller written
// against the previous declaration breaks. Everything else is refused with the
// message naming the mesh's real surface count.
bool slot_from_variant(const Variant &p_value, int &r_slot, String &r_reason) {
	const Variant::Type type = p_value.get_type();
	if (type == Variant::INT) {
		const int64_t value = p_value;
		if (value < 0 || value > (int64_t)2147483647) {
			r_reason = vformat("'material_slot' must be a surface index in 0..%d, got %d", 2147483647, value);
			return false;
		}
		r_slot = (int)value;
		return true;
	}
	if (type == Variant::FLOAT) {
		const double value = p_value;
		if (!Math::is_finite(value) || value != Math::floor(value) || value < 0.0 || value > (double)2147483647.0) {
			r_reason = vformat("'material_slot' must be a whole-number surface index (0, 1, ...), got %s",
					Variant(p_value).operator String());
			return false;
		}
		r_slot = (int)value;
		return true;
	}
	if (type == Variant::STRING) {
		const String spelling = String(p_value).strip_edges();
		if (spelling.is_empty()) {
			// The migration source's hard-coded 0, now the documented default.
			r_slot = 0;
			return true;
		}
		for (int i = 0; i < spelling.length(); i++) {
			const char32_t c = spelling[i];
			if (c < '0' || c > '9') {
				r_reason = vformat("'material_slot' must be an integer surface index (0, 1, ...); got the string '%s', "
								   "which does not spell an index",
						String(p_value));
				return false;
			}
		}
		const int64_t parsed = spelling.to_int();
		if (parsed > (int64_t)2147483647) {
			r_reason = vformat("'material_slot' is outside the surface range an index can have; got '%s'", String(p_value));
			return false;
		}
		r_slot = (int)parsed;
		return true;
	}
	r_reason = vformat("'material_slot' must be an integer surface index (0, 1, ...), got %s",
			Variant::get_type_name(type));
	return false;
}

// Every slot of the node as the answer lists it, so "slot 1 is not slot 0" is
// one response (the E-4 evidence).
Array surface_slot_records(MeshInstance3D *p_mesh_instance) {
	Array records;
	const Ref<Mesh> mesh = p_mesh_instance->get_mesh();
	const int surfaces = mesh.is_valid() ? mesh->get_surface_count() : p_mesh_instance->get_surface_override_material_count();
	for (int i = 0; i < surfaces; i++) {
		Dictionary record;
		// An integer, the same shape the `material_slot` argument now takes
		// (TASK-035 section 0): a slot answered by this tool can be fed straight
		// back into it (GDR-25 section 23.4).
		record["material_slot"] = i;
		record["surface_index"] = i;
		record["material"] = serialize_variant(
				Variant((Object *)p_mesh_instance->get_surface_override_material(i).ptr()));
		records.push_back(record);
	}
	return records;
}

} // namespace

namespace MCPTools {

Dictionary set_material_3d_on(Node *p_root, const String &p_node_path, const String &p_material_path,
		int p_slot, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the nodes that are there");
		return Dictionary();
	}
	MeshInstance3D *mesh_instance = Object::cast_to<MeshInstance3D>(node);
	if (mesh_instance == nullptr) {
		r_error = MCPToolError::invalid_params(vformat(
				"Node '%s' is a %s, not a MeshInstance3D: a surface override material is a MeshInstance3D member "
				"(MeshInstance3D::set_surface_override_material)",
				p_node_path, node->get_class()));
		return Dictionary();
	}
	const Ref<Mesh> mesh = mesh_instance->get_mesh();
	if (mesh.is_null()) {
		r_error = MCPToolError::tool_state(
				vformat("MeshInstance3D '%s' has no mesh, so it has no surface to write", p_node_path),
				"A surface slot only exists once the node has a mesh (MeshInstance3D::set_mesh sizes the override "
				"array to the mesh's surface count). Assign a mesh first (editor_set_node_property with property "
				"\"mesh\" and a {\"type\":\"...\",\"path\":\"res://...\"} value) and call again");
		return Dictionary();
	}
	const int surface_count = mesh->get_surface_count();
	if (surface_count <= 0) {
		r_error = MCPToolError::tool_state(
				vformat("MeshInstance3D '%s' has a mesh with no surface", p_node_path),
				"Give the node a mesh with at least one surface (a PrimitiveMesh has one) and call again");
		return Dictionary();
	}

	const int slot = p_slot;
	if (slot >= surface_count) {
		// The engine's own `ERR_FAIL_INDEX` would drop the write and print an
		// engine error; refusing here says which slots exist.
		r_error = MCPToolError::not_found(vformat("Surface slot %d on MeshInstance3D '%s'", slot, p_node_path),
				vformat("The mesh '%s' has %d surface(s), so the surface slots are 0..%d; this tool writes the slot "
						"named by 'material_slot'",
						mesh->get_class(), surface_count, surface_count - 1));
		return Dictionary();
	}

	String material_path;
	if (!normalize_project_path(p_material_path, material_path, r_error)) {
		return Dictionary();
	}
	const Ref<Resource> loaded = ResourceLoader::load(material_path);
	if (loaded.is_null()) {
		r_error = MCPToolError::not_found(vformat("Material resource '%s'", material_path),
				"'material_path' is loaded with ResourceLoader::load; name a .tres/.res Material in this project "
				"(project_get_filesystem_tree lists the files of the project)");
		return Dictionary();
	}
	Material *loaded_material = Object::cast_to<Material>(loaded.ptr());
	if (loaded_material == nullptr) {
		// The property is typed `BaseMaterial3D,ShaderMaterial`
		// (mesh_instance_3d.cpp:115), i.e. a `Material`.
		r_error = MCPToolError::invalid_params(vformat("'%s' holds a %s, not a Material", material_path,
				loaded->get_class()));
		return Dictionary();
	}

	// The slots before the write, so the answer can show that no other slot moved.
	const Array before = surface_slot_records(mesh_instance);
	mesh_instance->set_surface_override_material(slot, loaded);

	// Read back through the engine's own accessor: the material really at the
	// slot that was asked for (not slot 0 when another slot was named).
	const Ref<Material> stored = mesh_instance->get_surface_override_material(slot);
	if (stored.is_null()) {
		r_error = MCPToolError::internal(vformat(
				"MeshInstance3D::set_surface_override_material(%d, '%s') left the slot empty", slot, material_path));
		return Dictionary();
	}
	Dictionary out;
	out["node_path"] = relative_path(p_root, mesh_instance);
	out["type"] = mesh_instance->get_class();
	out["material_slot"] = slot;
	out["surface_index"] = slot;
	out["surface_count"] = surface_count;
	out["material_path"] = material_path;
	out["material"] = serialize_variant(Variant((Object *)stored.ptr()));
	out["set"] = true;
	out["applied"] = true;
	out["surface_materials"] = surface_slot_records(mesh_instance);
	out["previous_surface_materials"] = before;
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tool
// ---------------------------------------------------------------------------

static Variant _tool_set_material_3d(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	String material_path;
	if (!require_string(p_args, "material_path", material_path, r_error)) {
		return Variant();
	}
	if (material_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'material_path' must not be empty");
		return Variant();
	}
	// `material_slot` is optional: absent means the first surface (index 0, the
	// migration source's hard-coded slot, now an explicit documented default).
	// The engine's JSON parser stores a JSON integer as a `double`, so an
	// integral FLOAT is the shape the wire actually delivers; the helper accepts
	// INT, integral FLOAT and the previous contract's decimal string.
	int slot = 0;
	if (p_args.has("material_slot")) {
		String reason;
		if (!slot_from_variant(p_args["material_slot"], slot, reason)) {
			r_error = MCPToolError::invalid_params(reason);
			return Variant();
		}
	}
	if (!require_editor_ui(r_error, "editor 3D material writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_material_3d_on(root, node_path, material_path, slot, r_error);
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
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_scene_3d_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_scene_3d_write_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("editor_set_material_3d", String::utf8(R"desc(设置 3D 材质到 MeshInstance3D)desc"));
	builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
	builder.schema(_schema_from_json(R"schema({"properties":{"material_path":{"type":"string"},"material_slot":{"description":"表面索引（整数）；省略 = 第一个表面（索引 0）","type":"integer"},"node_path":{"type":"string"}},"required":["node_path","material_path"],"type":"object"})schema"));
	builder.handler(_tool_set_material_3d).register_into(r_registry);
}
