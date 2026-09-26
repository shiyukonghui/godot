/**************************************************************************/
/*  editor_shader_write.cpp                                               */
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
#include "editor_shader_write.h"

#include "shader_shared.h"
#include "running_game_node_write.h"
#include "tool_helpers.h"

#include "core/io/json.h"
#include "core/io/resource_loader.h"
#include "scene/main/node.h"

using namespace MCPTools;

namespace {

// The node at a path, or the tool's two refusals (nothing there / not an Object
// the shader tools can write).
Node *shader_node_at(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the nodes that are there");
		return nullptr;
	}
	return node;
}

} // namespace

// ---------------------------------------------------------------------------
// The two writers.
//
// `editor_set_shader_param` is the E-5 case of this batch. The first build
// carried the migration source's exact call
// (`godot_mcp_gdext/src/commands/shader.rs:134`),
// `node.set("material:shader_parameter/<name>", v)`, and the red doctest run
// measured it: **nothing happens** - `Object::set` does not split a `:`-joined
// name (`core/object/object.cpp` has no `:` handling; it falls through to
// `_setv`), so the call returns without an error and the material never sees the
// value, while the tool answered `set: true`. `Object::set_indexed` *does* split
// the path and reaches the material's `_set` - but only when the shader is
// compiled, and it needs the caller to guess the property path.
//
// Both writers therefore go through the engine's own API:
// `ShaderMaterial::set_shader_parameter` (material.cpp:420) with the parameter
// name checked against `Shader::get_shader_uniform_list` (shader.cpp:150), and a
// read-back for every claim.
// ---------------------------------------------------------------------------

namespace MCPTools {

Dictionary set_shader_material_on(Node *p_root, const String &p_node_path, const String &p_shader_path,
		const String &p_slot_argument, bool p_slot_present, MCPToolError &r_error) {
	Node *node = shader_node_at(p_root, p_node_path, r_error);
	if (node == nullptr) {
		return Dictionary();
	}
	String shader_path;
	if (!normalize_project_path(p_shader_path, shader_path, r_error)) {
		return Dictionary();
	}
	const Ref<Resource> loaded = ResourceLoader::load(shader_path);
	if (loaded.is_null()) {
		r_error = MCPToolError::not_found(vformat("Shader resource '%s'", shader_path),
				"'shader_path' is loaded with ResourceLoader::load; name a .gdshader in this project "
				"(project_search_file_names lists the files of the project)");
		return Dictionary();
	}
	Shader *shader = Object::cast_to<Shader>(loaded.ptr());
	if (shader == nullptr) {
		r_error = MCPToolError::invalid_params(vformat("'%s' holds a %s, not a Shader", shader_path,
				loaded->get_class()));
		return Dictionary();
	}

	// The slot is resolved against the node's **own** material properties: the
	// migration source read `material_slot` and then wrote the hard-coded
	// `"material"`, so the argument only worked for a node that happened to have
	// that property. TASK-037 R1: when the caller did **not** send the argument,
	// the contract default (`"material"`) is resolved against the node instead of
	// being taken literally, so a `MeshInstance3D` gets its own first slot rather
	// than a `-32602` a client that just fills in schema defaults could not avoid.
	StringName slot;
	if (!resolve_material_slot(node, p_slot_argument, p_slot_present, slot, r_error)) {
		return Dictionary();
	}
	const Variant previous = material_at_slot(node, slot);
	ShaderMaterial *existing = Object::cast_to<ShaderMaterial>(previous);
	const bool reused_existing = existing != nullptr;
	Ref<ShaderMaterial> material;
	if (reused_existing) {
		// Reusing the slot's ShaderMaterial and replacing only its shader keeps
		// the parameters that still apply - and the answer says which of the two
		// happened.
		material = Ref<ShaderMaterial>(existing);
	} else {
		material.instantiate();
	}
	material->set_shader(shader);

	bool applied = false;
	if (!set_material_at_slot(node, slot, material, applied, r_error)) {
		return Dictionary();
	}
	// Read the slot back through the engine: the material really there, with the
	// shader really assigned.
	ShaderMaterial *stored = Object::cast_to<ShaderMaterial>(node->get(slot));
	if (stored == nullptr || stored->get_shader().ptr() != shader) {
		r_error = MCPToolError::internal(vformat(
				"Assigning the ShaderMaterial built from '%s' into '%s' did not stick (the slot holds %s)",
				shader_path, String(slot),
				stored == nullptr ? String("something else") : String("a ShaderMaterial with another shader")));
		return Dictionary();
	}
	const Array uniforms = shader_uniform_records(shader);

	Dictionary out;
	out["node_path"] = relative_path(p_root, node);
	out["node_type"] = node->get_class();
	out["material_slot"] = String(slot);
	out["material_slot_kind"] = String(slot).begins_with("surface_material_override/") ? "surface_index" : "property";
	if (String(slot).begins_with("surface_material_override/")) {
		out["surface_index"] = String(slot).trim_prefix("surface_material_override/").to_int();
	}
	out["shader_path"] = shader_path;
	out["shader"] = serialize_variant(Variant((Object *)stored));
	out["shader_type"] = shader_mode_name(shader->get_mode());
	out["uniform_count"] = uniforms.size();
	out["assigned"] = true;
	out["applied"] = applied;
	out["reused_existing"] = reused_existing;
	out["previous_material"] = serialize_variant(previous);
	out["material_slots"] = material_slot_names(node);
	return out;
}

Dictionary set_shader_param_on(Node *p_root, const String &p_node_path, const String &p_param,
		const Variant &p_value, MCPToolError &r_error) {
	Node *node = shader_node_at(p_root, p_node_path, r_error);
	if (node == nullptr) {
		return Dictionary();
	}
	StringName slot;
	const Ref<ShaderMaterial> material = first_shader_material(node, slot);
	if (material.is_null()) {
		r_error = MCPToolError::not_found(vformat("A ShaderMaterial on '%s'", p_node_path),
				"No material slot of this node holds a ShaderMaterial, so there is no shader parameter to write; "
				"editor_set_shader_material assigns one (it answers the slot it wrote)");
		return Dictionary();
	}
	const Ref<Shader> shader = material->get_shader();
	if (shader.is_null()) {
		r_error = MCPToolError::tool_state(
				vformat("The ShaderMaterial in '%s' has no shader, so '%s' cannot be checked against a uniform",
						String(slot), p_param),
				"Assign a shader first: editor_set_shader_material with shader_path, or set the material's \"shader\" "
				"property to a {\"type\":\"Shader\",\"path\":\"res://...\"} value");
		return Dictionary();
	}

	// `不得假成功`: a name the shader does not declare would be stored by the
	// engine and never read by any shader, i.e. "reported success but nothing
	// happened" - the exact class this batch is closing.
	PropertyInfo uniform;
	if (!shader_uniform(shader.ptr(), p_param, uniform)) {
		const String declared = shader_uniform_names_preview(shader.ptr());
		r_error = MCPToolError::not_found(vformat("Shader parameter '%s' of '%s'", p_param,
												   shader->get_path().is_empty() ? String("this material's shader")
																				 : String(shader->get_path())),
				declared.is_empty()
						? "The engine reports no shader parameter for this shader (a shader with no uniform and a "
						  "shader that failed to compile answer the same empty list), so nothing can be written; "
						  "project_get_shader_params reports the same list"
						: vformat("The shader declares: %s. A parameter the shader does not declare cannot be "
								  "written; project_get_shader_params lists the parameters of a shader file",
								  declared));
		return Dictionary();
	}

	const Variant previous = material->get_shader_parameter(StringName(p_param));
	// The module's canonical JSON -> engine-value sequence - the same three steps
	// `prepare_node_property_value` runs for a node property
	// (`property_value_from_json` -> `shape_vector_from_json` ->
	// `coerce_to_property_type`), so a uniform accepts exactly the shapes every
	// other write path of the module accepts: `{x,y,z}` for a `vec3`,
	// `[r,g,b,a]`/`{r,g,b,a}`/`"#rrggbb"` for a colour, and so on. Gate 2 measured
	// the missing middle step: a `{x,y,z}` object for a `vec3` uniform was refused
	// with "Dictionary -> Vector3 is not a conversion" (REPORT-035 section 6.1).
	const Variant json_value = property_value_from_json(p_value, uniform.type);
	Variant shaped;
	if (!shape_vector_from_json(json_value, uniform.type, p_param, "value", shaped, r_error)) {
		return Dictionary();
	}
	// A shader `float` is 32 bits whatever the build's `real_t` is (GDR-24 section
	// 22.2), so that is the slot the value has to survive; every other uniform goes
	// through its own target-type rule.
	Variant converted;
	const ValueSlot slot_width = uniform.type == Variant::FLOAT ? ValueSlot::FLOAT32 : ValueSlot::FROM_TARGET_TYPE;
	if (!coerce_to_property_type(shaped, uniform.type, converted, r_error, "value", slot_width)) {
		return Dictionary();
	}

	// The engine's own API, not a property path (E-5).
	material->set_shader_parameter(StringName(p_param), converted);
	const Variant stored = material->get_shader_parameter(StringName(p_param));
	if (stored.get_type() == Variant::NIL) {
		r_error = MCPToolError::internal(vformat(
				"ShaderMaterial::set_shader_parameter(\"%s\", ...) left the parameter unset", p_param));
		return Dictionary();
	}
	bool equal = false;
	if (stored.get_type() == Variant::FLOAT) {
		equal = Math::is_equal_approx((double)converted, (double)stored);
	} else {
		equal = stored == converted;
	}
	if (!equal) {
		r_error = MCPToolError::internal(vformat(
				"ShaderMaterial::set_shader_parameter(\"%s\", ...) stored a different value (%s instead of %s)",
				p_param, String(serialize_variant(stored)), String(serialize_variant(converted))));
		return Dictionary();
	}

	const Array uniforms = shader_uniform_records(shader.ptr());
	Dictionary out;
	out["node_path"] = relative_path(p_root, node);
	out["node_type"] = node->get_class();
	out["material_slot"] = String(slot);
	out["shader_path"] = shader->get_path();
	out["param"] = p_param;
	out["uniform_type"] = Variant::get_type_name(uniform.type);
	out["uniform_type_id"] = (int)uniform.type;
	out["param_count"] = uniforms.size();
	out["previous_value"] = serialize_variant(previous);
	out["new_value"] = serialize_variant(stored);
	out["value"] = serialize_variant(stored);
	out["set"] = true;
	out["applied"] = true;
	out["changed"] = previous.get_type() == Variant::NIL || previous != stored;
	// The engine lever the answer was produced with, so the write path is not a
	// matter of trust (E-5).
	out["write_path"] = "ShaderMaterial::set_shader_parameter";
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

static Variant _tool_set_shader_material(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	String shader_path;
	if (!require_string(p_args, "shader_path", shader_path, r_error)) {
		return Variant();
	}
	if (shader_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'shader_path' must not be empty");
		return Variant();
	}
	String material_slot;
	if (!optional_string(p_args, "material_slot", "material", material_slot, r_error)) {
		return Variant();
	}
	// TASK-037 R1: "the caller did not send material_slot" and "the caller sent
	// 'material'" are different requests on a 3D node, so the presence of the
	// argument is kept here (the same reason `fov` above carries a presence flag).
	const bool slot_present = p_args.has("material_slot");
	if (!require_editor_ui(r_error, "editor shader writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_shader_material_on(root, node_path, shader_path, material_slot, slot_present, r_error);
}

static Variant _tool_set_shader_param(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	String param;
	if (!require_string(p_args, "param", param, r_error)) {
		return Variant();
	}
	if (param.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'param' must not be empty");
		return Variant();
	}
	if (!p_args.has("value")) {
		r_error = MCPToolError::invalid_params("Missing required parameter: value");
		return Variant();
	}
	const Variant value = p_args["value"];
	if (!require_editor_ui(r_error, "editor shader writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_shader_param_on(root, node_path, param, value, r_error);
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
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_shader_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_shader_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_set_shader_material", String::utf8(R"desc(为节点分配 ShaderMaterial)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"material_slot":{"default":"material","type":"string"},"node_path":{"type":"string"},"shader_path":{"type":"string"}},"required":["node_path","shader_path"],"type":"object"})schema"));
		builder.handler(_tool_set_shader_material).register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_set_shader_param", String::utf8(R"desc(设置着色器参数)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"},"param":{"type":"string"},"value":{"description":"参数值"}},"required":["node_path","param","value"],"type":"object"})schema"));
		builder.handler(_tool_set_shader_param).register_into(r_registry);
	}
}
