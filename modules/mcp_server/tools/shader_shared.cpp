/**************************************************************************/
/*  shader_shared.cpp                                                     */
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
#include "shader_shared.h"

#include "tool_helpers.h"

using namespace MCPTools;

namespace {

// A material slot is an `Object`-typed property whose declared class hint names
// `Material` or whose current value is a `Material`. Both halves are needed: a
// slot that is currently empty (`Sprite2D.material` before anything is assigned)
// has no value to cast, and its hint is what says it can hold a material.
bool is_material_slot_property(const Object *p_node, const PropertyInfo &p_property) {
	if (p_property.type != Variant::OBJECT) {
		return false;
	}
	if (p_property.hint == PROPERTY_HINT_RESOURCE_TYPE && p_property.hint_string.contains("Material")) {
		return true;
	}
	const Variant value = p_node->get(p_property.name);
	return Object::cast_to<Material>(value) != nullptr;
}

// A decimal-spelled surface index: the spelling the old contract used for
// `material_slot`, and the engine's own shape for a mesh surface.
bool decimal_surface_index(const String &p_text, int &r_index) {
	const String spelling = p_text.strip_edges();
	if (spelling.is_empty()) {
		return false;
	}
	for (int i = 0; i < spelling.length(); i++) {
		const char32_t c = spelling[i];
		if (c < '0' || c > '9') {
			return false;
		}
	}
	const int64_t parsed = spelling.to_int();
	if (parsed > (int64_t)2147483647) {
		return false;
	}
	r_index = (int)parsed;
	return true;
}

} // namespace

namespace MCPTools {

Array material_slot_names(const Object *p_node) {
	Array names;
	if (p_node == nullptr) {
		return names;
	}
	List<PropertyInfo> properties;
	p_node->get_property_list(&properties);
	for (const PropertyInfo &property : properties) {
		// The property list contains group/subgroup markers whose type is NIL;
		// `is_material_slot_property` excludes them by requiring OBJECT.
		if (is_material_slot_property(p_node, property)) {
			names.push_back(String(property.name));
		}
	}
	return names;
}

bool material_slot_exists(const Object *p_node, const StringName &p_slot) {
	if (p_node == nullptr) {
		return false;
	}
	const Array names = material_slot_names(p_node);
	for (int i = 0; i < names.size(); i++) {
		if (String(names[i]) == String(p_slot)) {
			return true;
		}
	}
	return false;
}

bool resolve_material_slot(Object *p_node, const String &p_slot_argument, bool p_argument_present,
		StringName &r_slot, MCPToolError &r_error) {
	if (p_node == nullptr) {
		r_error = MCPToolError::internal("internal error: resolve_material_slot without a node");
		return false;
	}
	const String argument = p_slot_argument.strip_edges();
	if (!argument.is_empty() && material_slot_exists(p_node, StringName(argument))) {
		r_slot = StringName(argument);
		return true;
	}
	int surface_index = 0;
	if (!argument.is_empty() && decimal_surface_index(argument, surface_index)) {
		// The engine's own surface-index spelling: `MeshInstance3D` exposes one
		// property per surface (`_get_property_list`, mesh_instance_3d.cpp:113-117).
		const StringName surface_slot(vformat("surface_material_override/%d", surface_index));
		if (material_slot_exists(p_node, surface_slot)) {
			r_slot = surface_slot;
			return true;
		}
	}
	// TASK-037 R1: the argument was *not* sent. The contract's `default` is
	// `"material"`, but that property only exists on a `CanvasItem`; a
	// `MeshInstance3D` carries `material_override` / `material_overlay` /
	// `surface_material_override/<n>` instead. The schema is frozen, so the
	// server resolves the contract default against the node it was given: plenty
	// of nodes have `material` and keep the historical behaviour, and every other
	// node gets its own first material slot (property-list order, which is
	// deterministic for one class) instead of a refusal the caller cannot act on.
	// The answer names the slot it used (`material_slot`).
	if (!p_argument_present) {
		const Array omitted_slots = material_slot_names(p_node);
		if (omitted_slots.size() > 0) {
			r_slot = StringName(String(omitted_slots[0]));
			return true;
		}
	}
	const Array names = material_slot_names(p_node);
	String listed;
	for (int i = 0; i < names.size(); i++) {
		if (i > 0) {
			listed += ", ";
		}
		listed += "'" + String(names[i]) + "'";
	}
	r_error = MCPToolError::invalid_params(vformat(
			"'material_slot' must name a material slot of this node; %s has: %s. A decimal index is also accepted "
			"for a MeshInstance3D surface (it means 'surface_material_override/<n>')",
			p_node->get_class(), listed.is_empty() ? String("no material slot at all") : listed));
	return false;
}

Variant material_at_slot(Object *p_node, const StringName &p_slot) {
	if (p_node == nullptr || !material_slot_exists(p_node, p_slot)) {
		return Variant();
	}
	return p_node->get(p_slot);
}

bool set_material_at_slot(Object *p_node, const StringName &p_slot, const Ref<Material> &p_material,
		bool &r_applied, MCPToolError &r_error) {
	r_applied = false;
	if (p_node == nullptr) {
		r_error = MCPToolError::internal("internal error: set_material_at_slot without a node");
		return false;
	}
	p_node->set(p_slot, Variant((Object *)p_material.ptr()));
	// Read back through the engine's own accessor: `Object::set` on an unknown
	// property is silent, so the answer must come from `get`, not from the call.
	const Variant stored = p_node->get(p_slot);
	Material *stored_material = Object::cast_to<Material>(stored);
	if (stored_material != p_material.ptr()) {
		r_error = MCPToolError::internal(vformat(
				"Writing the material into '%s' did not change the property (the slot holds %s)",
				String(p_slot), stored.get_type() == Variant::OBJECT && stored_material != nullptr
										? stored_material->get_class()
										: Variant::get_type_name(stored.get_type())));
		return false;
	}
	r_applied = true;
	return true;
}

Ref<ShaderMaterial> first_shader_material(Object *p_node, StringName &r_slot) {
	r_slot = StringName();
	if (p_node == nullptr) {
		return Ref<ShaderMaterial>();
	}
	const Array names = material_slot_names(p_node);
	for (int i = 0; i < names.size(); i++) {
		const StringName slot = StringName(String(names[i]));
		const Variant value = p_node->get(slot);
		ShaderMaterial *material = Object::cast_to<ShaderMaterial>(value);
		if (material != nullptr) {
			r_slot = slot;
			return Ref<ShaderMaterial>(material);
		}
	}
	return Ref<ShaderMaterial>();
}

Array shader_uniform_records(Shader *p_shader) {
	Array records;
	if (p_shader == nullptr) {
		return records;
	}
	List<PropertyInfo> uniforms;
	p_shader->get_shader_uniform_list(&uniforms);
	for (const PropertyInfo &uniform : uniforms) {
		Dictionary record;
		record["name"] = String(uniform.name);
		record["type"] = Variant::get_type_name(uniform.type);
		record["type_id"] = (int)uniform.type;
		record["hint"] = (int)uniform.hint;
		record["hint_string"] = uniform.hint_string;
		records.push_back(record);
	}
	return records;
}

bool shader_uniform(const Shader *p_shader, const String &p_name, PropertyInfo &r_uniform) {
	if (p_shader == nullptr) {
		return false;
	}
	// `get_shader_uniform_list` is non-const in the engine's declaration, so the
	// lookup goes through a mutable handle; the list itself is read-only.
	Shader *shader = const_cast<Shader *>(p_shader);
	List<PropertyInfo> uniforms;
	shader->get_shader_uniform_list(&uniforms);
	for (const PropertyInfo &uniform : uniforms) {
		if (String(uniform.name) == p_name) {
			r_uniform = uniform;
			return true;
		}
	}
	return false;
}

String shader_uniform_names_preview(const Shader *p_shader, int p_max) {
	if (p_shader == nullptr) {
		return String();
	}
	Shader *shader = const_cast<Shader *>(p_shader);
	List<PropertyInfo> uniforms;
	shader->get_shader_uniform_list(&uniforms);
	String out;
	int count = 0;
	for (const PropertyInfo &uniform : uniforms) {
		if (count > 0) {
			out += ", ";
		}
		out += "'" + String(uniform.name) + "'";
		count++;
		if (count >= p_max) {
			if (uniforms.size() > p_max) {
				out += vformat(" (and %d more)", uniforms.size() - p_max);
			}
			break;
		}
	}
	return out;
}

const char *shader_mode_name(int p_mode) {
	switch ((Shader::Mode)p_mode) {
		case Shader::MODE_SPATIAL:
			return "spatial";
		case Shader::MODE_CANVAS_ITEM:
			return "canvas_item";
		case Shader::MODE_PARTICLES:
			return "particles";
		case Shader::MODE_SKY:
			return "sky";
		case Shader::MODE_FOG:
			return "fog";
	}
	return "";
}

int shader_mode_from_name(const String &p_name) {
	const String name = p_name.strip_edges().to_lower();
	if (name == "spatial") {
		return Shader::MODE_SPATIAL;
	}
	if (name == "canvas_item") {
		return Shader::MODE_CANVAS_ITEM;
	}
	if (name == "particles") {
		return Shader::MODE_PARTICLES;
	}
	if (name == "sky") {
		return Shader::MODE_SKY;
	}
	if (name == "fog") {
		return Shader::MODE_FOG;
	}
	return -1;
}

int shader_code_mode(const String &p_code, String &r_mode_name, String &r_directive) {
	r_mode_name = String();
	r_directive = String();
	const Vector<String> lines = split_lines(p_code);
	for (int i = 0; i < lines.size(); i++) {
		const String line = lines[i].strip_edges();
		if (!line.begins_with("shader_type")) {
			continue;
		}
		r_directive = line;
		String rest = line.substr(String("shader_type").length()).strip_edges();
		if (rest.ends_with(";")) {
			rest = rest.substr(0, rest.length() - 1).strip_edges();
		}
		// A directive can carry extra statements on the same line in theory; the
		// mode is the first word.
		const int space = rest.find(" ");
		r_mode_name = (space >= 0 ? rest.substr(0, space) : rest).strip_edges();
		const int mode = shader_mode_from_name(r_mode_name);
		// `-2` distinguishes "declares a mode the engine does not have" from `-1`,
		// "declares no mode at all": the two are answered differently.
		return mode >= 0 ? mode : -2;
	}
	return -1;
}

String shader_template(const String &p_mode_directive, int p_mode) {
	String out = p_mode_directive + "\n";
	if (p_mode == Shader::MODE_SPATIAL || p_mode == Shader::MODE_CANVAS_ITEM) {
		out += "\nvoid fragment() {\n}\n";
	}
	return out;
}

} // namespace MCPTools
