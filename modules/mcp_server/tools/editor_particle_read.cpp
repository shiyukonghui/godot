/**************************************************************************/
/*  editor_particle_read.cpp                                              */
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
#include "editor_particle_read.h"

#include "particle_shared.h"
#include "tool_helpers.h"

#include "core/io/json.h"
#include "scene/2d/gpu_particles_2d.h"
#include "scene/3d/gpu_particles_3d.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-034 section 1: the engine reference behind this tool.
//
//   editor_get_particle_info
//     * the node's own simulation members, through the engine's accessors:
//       `amount` (`int amount`, gpu_particles_3d.h:127 / gpu_particles_2d.h:116),
//       `lifetime` (`double`, :128/:117), `one_shot` (:129/:118),
//       `explosiveness`/`randomness` (`real_t`, :131-132/:120-121),
//       `emitting` (:126/:115) and `speed_scale` (`double`, :136/:125). They are
//       read as read - no unit conversion and no rounding, so what a caller sees
//       is what `Object::get()` answers;
//     * the process material through `get_process_material()`
//       (gpu_particles_3d.h:152) and `particle_shared.param`'s own parameter
//       table - the *same* set `editor_set_particle_material` writes, in the same
//       shapes (GDR-25 section 23.4);
//     * the `color_ramp` gradient as `[{offset, color}]` through
//       `GradientTexture1D::get_gradient()` / `Gradient::get_offset` /
//       `Gradient::get_color` (gradient.cpp:202-219);
//     * `draw_passes`/`draw_pass_1` (`int get_draw_passes()`,
//       gpu_particles_3d.h:175) and `texture` (gpu_particles_2d.h:169) for the
//       two classes' own "what does this system draw" members. The migration
//       source answered neither, so a 3D system with no draw pass looked exactly
//       like a working one (`particle.rs:444-455`).
//
// The shape differences from the migration source are declared in REPORT-034:
// every vector/colour is an object (never a `"(x, y, z)"` string), the material
// is named by its `{type, path}` shape (GDR-25 section 23.5), and the answer
// lists the parameter set that the write side of the same batch accepts.
// ---------------------------------------------------------------------------

namespace MCPTools {

Dictionary particle_info_on(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	Node *node = particle_system_node(p_root, p_node_path, r_error);
	if (node == nullptr) {
		return Dictionary();
	}
	const bool is_3d = node->is_class(StringName("GPUParticles3D"));
	// The slot is read as it is: a reader must not refuse a state it can describe
	// (a `ShaderMaterial` in the process-material slot is a fact, not an error),
	// so the material is *cast* here rather than demanded through
	// `particle_process_material_of`'s create/refuse half.
	const Variant slot_value = node->get(StringName("process_material"));
	Ref<ParticleProcessMaterial> material;
	if (slot_value.get_type() == Variant::OBJECT) {
		material = Object::cast_to<ParticleProcessMaterial>(slot_value);
	}

	Dictionary out;
	out["node_path"] = relative_path(p_root, node);
	out["type"] = node->get_class();
	out["is_3d"] = is_3d;
	out["amount"] = (int64_t)node->get(StringName("amount"));
	out["lifetime"] = (double)node->get(StringName("lifetime"));
	out["one_shot"] = (bool)node->get(StringName("one_shot"));
	out["emitting"] = (bool)node->get(StringName("emitting"));
	out["explosiveness"] = (double)node->get(StringName("explosiveness"));
	out["randomness"] = (double)node->get(StringName("randomness"));
	out["speed_scale"] = (double)node->get(StringName("speed_scale"));
	if (is_3d) {
		out["draw_passes"] = (int64_t)node->get(StringName("draw_passes"));
		out["has_draw_pass_mesh"] = node->get(StringName("draw_pass_1")).get_type() != Variant::NIL;
	} else {
		out["texture"] = serialize_variant(node->get(StringName("texture")));
	}

	const char *slot = particle_process_material_slot();
	out["process_material_slot"] = slot;
	out["process_material"] = serialize_variant(slot_value);
	if (material.is_null()) {
		// No process material of this family in the slot: the honest answer is
		// `null` for the parameter set - never an invented one (GDR-25 23.5).
		out["params"] = Variant();
		out["colors"] = Variant();
		out["color_ramp"] = Variant();
		out["color_stop_count"] = 0;
		return out;
	}

	const Ref<Texture2D> ramp = material->get_color_ramp();
	// The write shape, so "read it, change one member, write it back" is one step
	// (GDR-25 section 23.1).
	out["params"] = particle_material_params(material.ptr());
	bool ramp_present = false;
	const Array stops = particle_color_stops(material.ptr(), ramp_present);
	out["colors"] = ramp_present ? Variant(stops) : Variant();
	out["color_ramp"] = serialize_variant(Variant((Object *)ramp.ptr()));
	out["color_stop_count"] = ramp_present ? stops.size() : 0;
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tool
// ---------------------------------------------------------------------------

static Variant _tool_get_particle_info(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor particle reads outside a running editor",
				"Start the MCP server inside the Godot editor to read editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return particle_info_on(root, node_path, r_error);
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
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_particle_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_particle_read_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("editor_get_particle_info", String::utf8(R"desc(获取粒子系统信息)desc"));
	builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
	builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"}},"required":["node_path"],"type":"object"})schema"));
	builder.handler(_tool_get_particle_info).register_into(r_registry);
}
