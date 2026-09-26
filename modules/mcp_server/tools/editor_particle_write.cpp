/**************************************************************************/
/*  editor_particle_write.cpp                                             */
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
#include "editor_particle_write.h"

#include "editor_node_instantiate.h"
#include "particle_shared.h"
#include "tool_helpers.h"

#include "core/io/json.h"
#include "core/math/color.h"
#include "scene/2d/gpu_particles_2d.h"
#include "scene/3d/gpu_particles_3d.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-034 section 1: the engine reference behind each tool of this group.
//
//   editor_create_particles (the tool handler owns this one)
//     * `ClassDB` instantiation restricted to the two classes whose
//       `process_material` slot exists (`GPUParticles2D`/`GPUParticles3D`,
//       `set_process_material`, gpu_particles_3d.h:135 / gpu_particles_2d.h:124);
//       `CPUParticles*` is a different family with no such slot, and the
//       migration source's `ClassDb.instantiate(particle_type)` accepted
//       *anything* that instantiated (`particle.rs:83-91`);
//     * `Node::add_child` + `Node::set_owner` through `MCPTools::add_typed_child`
//       (editor_node_instantiate.cpp:119);
//     * a fresh `ParticleProcessMaterial` in the node's single process-material
//       slot, which is what makes the node immediately simulatable - the
//       migration source created one too (`particle.rs:95-96`).
//
//   set_particle_preset_on
//     * the node's own simulation members (`amount` `int`, `lifetime` `double`,
//       `one_shot` `bool`, `explosiveness`/`randomness` `real_t` -
//       gpu_particles_3d.h:126-136) and the process material's parameters, each
//       through `MCPTools::coerce_to_property_type` with its **own** slot width;
//     * the six preset values are the migration source's table
//       (`particle.rs:310-389`), kept because they are data rather than
//       behaviour, and every one of them is written through the engine's own
//       setters so the stored value is what the answer reports.
//
//   set_particle_color_gradient_on
//     * `ParticleProcessMaterial::set_color_ramp(const Ref<Texture2D> &)`
//       (particle_process_material.h:434) with a `GradientTexture1D` built from a
//       `Gradient` (`Gradient::set_offsets`/`set_colors`,
//       gradient.h:139-143). `Gradient::remove_point` refuses to go below one
//       point (`gradient.cpp:179`), so the stops are always assigned wholesale -
//       the same route the GDScript reference takes
//       (`addons/godot_mcp/commands/particle_commands.gd:285-303`);
//     * reading through `Gradient::get_offset`/`get_color` runs the engine's own
//       `_update_sorting` first (`gradient.cpp:202-219`), so the answer is the
//       gradient's canonical order and a second read is byte-identical.
//
//   set_particle_material_on
//     * `particle_shared.*` - see that file for the per-parameter engine
//       reference. The one thing this file decides is **which slot** the
//       parameters go to: `process_material`, named in the answer.
// ---------------------------------------------------------------------------

namespace {

// The preset table, verbatim from the migration source
// (`godot_mcp_gdext/src/commands/particle.rs:310-389`); `is_2d` selects the two
// velocity columns and the gravity constant, exactly as that source did.
struct Preset {
	const char *name;
	int amount;
	double lifetime;
	bool one_shot;
	double explosiveness;
	double spread;
	double velocity_min_2d;
	double velocity_max_2d;
	double velocity_min_3d;
	double velocity_max_3d;
	bool has_direction;
	bool has_gravity;
	double gravity_scale;
	double gravity_y_2d;
	double gravity_y_3d;
	double scale_min;
	double scale_max;
	double damping_min;
	double damping_max;
	double orbit_min;
	double orbit_max;
	double color_r;
	double color_g;
	double color_b;
	double color_a;
};

const Preset PRESETS[] = {
	// name, amount, lifetime, one_shot, explosiveness, spread, vmin2d, vmax2d, vmin3d, vmax3d,
	// direction?, gravity?, gravity_scale, gravity_y_2d, gravity_y_3d, smin, smax, dmin, dmax, omin, omax,
	// r, g, b, a
	{ "fire", 24, 1.2, false, 0.0, 15.0, 30.0, 60.0, 1.5, 3.0, true, false, 0.0, 0.0, 0.0, 0.8, 1.5, 0.0, 0.0, 0.0, 0.0, 1.0, 0.6, 0.0, 1.0 },
	{ "smoke", 16, 3.0, false, 0.0, 25.0, 10.0, 25.0, 0.5, 1.2, true, false, 0.0, 0.0, 0.0, 1.5, 3.0, 1.0, 2.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.6 },
	{ "magic", 24, 2.0, false, 0.0, 180.0, 20.0, 50.0, 1.0, 2.5, false, false, 0.0, 0.0, 0.0, 0.3, 0.8, 0.0, 0.0, 0.5, 1.5, 0.3, 0.5, 1.0, 1.0 },
	{ "explosion", 32, 0.6, true, 1.0, 180.0, 100.0, 200.0, 5.0, 10.0, false, true, 0.5, 98.0, 9.8, 0.5, 1.5, 2.0, 4.0, 0.0, 0.0, 1.0, 0.6, 0.1, 1.0 },
	{ "rain", 64, 0.8, false, 0.0, 5.0, 300.0, 400.0, 12.0, 16.0, false, true, 1.0, 98.0, 9.8, 0.1, 0.2, 0.0, 0.0, 0.0, 0.0, 0.6, 0.7, 1.0, 0.7 },
	{ "snow", 48, 4.0, false, 0.0, 20.0, 20.0, 40.0, 0.8, 1.5, false, true, 20.0, 20.0, 20.0, 0.3, 0.8, 0.5, 1.5, 0.0, 0.0, 1.0, 1.0, 1.0, 0.9 },
};

const int PRESET_COUNT = (int)(sizeof(PRESETS) / sizeof(PRESETS[0]));

const Preset *find_preset(const String &p_name) {
	const String spelling = p_name.strip_edges().to_lower();
	for (int i = 0; i < PRESET_COUNT; i++) {
		if (spelling == PRESETS[i].name) {
			return &PRESETS[i];
		}
	}
	return nullptr;
}

// One node member of a particle system, written through the module's gate at the
// member's own width and read back. The answer's record is the same shape the
// parameter writer uses, so a caller reads one shape for both halves of a preset.
struct NodeMemberSpec {
	const char *name;
	Variant::Type type;
	ValueSlot slot;
};

bool write_node_member(Node *p_node, const NodeMemberSpec &p_spec, const Variant &p_raw, Array &r_changed,
		Array &r_ignored, MCPToolError &r_error) {
	const StringName name(p_spec.name);
	Variant converted;
	if (!coerce_to_property_type(p_raw, p_spec.type, converted, r_error, p_spec.name, p_spec.slot)) {
		return false;
	}
	p_node->set(name, converted);
	const Variant stored = p_node->get(name);
	Dictionary record;
	record["property"] = p_spec.name;
	record["requested"] = serialize_variant(p_raw);
	record["stored"] = serialize_variant(stored);
	if (stored.get_type() == converted.get_type() && stored == converted) {
		r_changed.push_back(record);
	} else {
		record["reason"] = "the engine stored a different value than the one asked for (the member clamps or "
						   "converts it)";
		r_ignored.push_back(record);
	}
	return true;
}

Dictionary apply_preset_node_members(Node *p_node, const Preset &p_preset, bool p_is_2d, MCPToolError &r_error) {
	// The member's storage is read out of the class itself: `amount` is an `int`
	// (gpu_particles_3d.h:127) and `lifetime` a `double` (:128), so neither is
	// narrowed; `explosiveness`/`randomness` are `real_t` (:131-132).
	const NodeMemberSpec specs[] = {
		{ "amount", Variant::INT, ValueSlot::INT32 },
		{ "lifetime", Variant::FLOAT, ValueSlot::WIDE },
		{ "one_shot", Variant::BOOL, ValueSlot::WIDE },
		{ "explosiveness", Variant::FLOAT, ValueSlot::REAL_T },
	};
	Array changed;
	Array ignored;
	if (!write_node_member(p_node, specs[0], p_preset.amount, changed, ignored, r_error) ||
			!write_node_member(p_node, specs[1], p_preset.lifetime, changed, ignored, r_error) ||
			!write_node_member(p_node, specs[2], p_preset.one_shot, changed, ignored, r_error) ||
			!write_node_member(p_node, specs[3], p_preset.explosiveness, changed, ignored, r_error)) {
		return Dictionary();
	}
	(void)p_is_2d;
	Dictionary out;
	out["node_properties"] = changed;
	out["node_properties_ignored"] = ignored;
	return out;
}

Dictionary preset_material_params(const Preset &p_preset, bool p_is_2d) {
	Dictionary params;
	if (p_preset.has_direction) {
		Dictionary direction;
		direction["x"] = 0.0;
		direction["y"] = -1.0;
		direction["z"] = 0.0;
		params["direction"] = direction;
	}
	params["spread"] = p_preset.spread;
	params["initial_velocity_min"] = p_is_2d ? p_preset.velocity_min_2d : p_preset.velocity_min_3d;
	params["initial_velocity_max"] = p_is_2d ? p_preset.velocity_max_2d : p_preset.velocity_max_3d;
	if (p_preset.has_gravity) {
		Dictionary gravity;
		gravity["x"] = 0.0;
		gravity["y"] = p_is_2d ? p_preset.gravity_y_2d * p_preset.gravity_scale : p_preset.gravity_y_3d * p_preset.gravity_scale;
		gravity["z"] = 0.0;
		params["gravity"] = gravity;
	}
	params["scale_min"] = p_preset.scale_min;
	params["scale_max"] = p_preset.scale_max;
	if (p_preset.damping_min != 0.0 || p_preset.damping_max != 0.0) {
		params["damping_min"] = p_preset.damping_min;
		params["damping_max"] = p_preset.damping_max;
	}
	if (p_preset.orbit_min != 0.0 || p_preset.orbit_max != 0.0) {
		params["orbit_velocity_min"] = p_preset.orbit_min;
		params["orbit_velocity_max"] = p_preset.orbit_max;
	}
	Dictionary color;
	color["r"] = p_preset.color_r;
	color["g"] = p_preset.color_g;
	color["b"] = p_preset.color_b;
	color["a"] = p_preset.color_a;
	params["color"] = color;
	return params;
}

} // namespace

namespace MCPTools {

const char *const *particle_preset_names() {
	static const char *names[PRESET_COUNT + 1];
	static bool initialized = false;
	if (!initialized) {
		for (int i = 0; i < PRESET_COUNT; i++) {
			names[i] = PRESETS[i].name;
		}
		names[PRESET_COUNT] = nullptr;
		initialized = true;
	}
	return names;
}

int particle_preset_count() {
	return PRESET_COUNT;
}

Dictionary set_particle_preset_on(Node *p_root, const String &p_node_path, const String &p_preset,
		MCPToolError &r_error) {
	Node *node = particle_system_node(p_root, p_node_path, r_error);
	if (node == nullptr) {
		return Dictionary();
	}
	const Preset *preset = find_preset(p_preset);
	if (preset == nullptr) {
		Vector<String> names;
		for (int i = 0; i < PRESET_COUNT; i++) {
			names.push_back(PRESETS[i].name);
		}
		r_error = MCPToolError::invalid_params(vformat("Unknown preset: '%s'. Valid presets: %s", p_preset,
				String(", ").join(names)));
		return Dictionary();
	}
	// `GPUParticles2D`/`GPUParticles3D` are the only two classes here, and the
	// engine's own class name is what decides the two velocity columns - the
	// migration source used `class_name.contains("2D")` (`particle.rs:302-303`),
	// which is the same test spelled against the engine's answer.
	const bool is_2d = node->is_class(StringName("GPUParticles2D"));

	Ref<ParticleProcessMaterial> material = particle_process_material_of(node, true, r_error);
	if (material.is_null()) {
		return Dictionary();
	}

	// All-or-nothing: the node members are validated and written first (they can
	// only fail on a value that cannot fall into the member's type, and the
	// preset's own values are all literals), the material parameters are then
	// validated as a whole before any of them is written.
	const Dictionary node_result = apply_preset_node_members(node, *preset, is_2d, r_error);
	if (node_result.is_empty()) {
		return Dictionary();
	}
	const Dictionary params = preset_material_params(*preset, is_2d);
	MCPToolError params_error;
	const Dictionary material_result = apply_particle_material_params(material.ptr(), params, params_error);
	if (material_result.is_empty()) {
		r_error = params_error;
		return Dictionary();
	}

	Dictionary out;
	out["node_path"] = relative_path(p_root, node);
	out["type"] = node->get_class();
	out["preset"] = preset->name;
	out["is_2d"] = is_2d;
	out["applied"] = true;
	// Which slot the parameters went into. There is exactly one process-material
	// slot in the engine, and naming it is what keeps "which material did this
	// write" answerable (see REPORT-034 section 5 for the E-4 comparison).
	out["process_material_slot"] = particle_process_material_slot();
	out["node_properties"] = node_result["node_properties"];
	if (preset->one_shot) {
		// The preset table sets `one_shot` for "explosion" only; the read-back is
		// in `node_properties` either way.
		out["one_shot"] = (bool)node->get(StringName("one_shot"));
	}
	Array changed = material_result["changed"];
	Array ignored = material_result["ignored"];
	Array node_ignored = node_result["node_properties_ignored"];
	for (int i = 0; i < node_ignored.size(); i++) {
		ignored.push_back(node_ignored[i]);
	}
	out["material_params"] = changed;
	out["ignored"] = ignored;
	out["changed_count"] = changed.size();
	out["ignored_count"] = ignored.size();
	return out;
}

Dictionary set_particle_color_gradient_on(Node *p_root, const String &p_node_path, const Array &p_colors,
		MCPToolError &r_error) {
	Node *node = particle_system_node(p_root, p_node_path, r_error);
	if (node == nullptr) {
		return Dictionary();
	}
	Ref<ParticleProcessMaterial> material = particle_process_material_of(node, true, r_error);
	if (material.is_null()) {
		return Dictionary();
	}
	Array stored;
	if (!set_particle_color_stops(material.ptr(), p_colors, stored, r_error)) {
		return Dictionary();
	}

	Dictionary out;
	out["node_path"] = relative_path(p_root, node);
	out["process_material_slot"] = particle_process_material_slot();
	out["requested_count"] = p_colors.size();
	out["stop_count"] = stored.size();
	// The engine's own stops: the same `[{offset, color}]` shape
	// `editor_get_particle_info` answers, so the read side and the write side are
	// one shape (GDR-25 section 23.4).
	out["colors"] = stored;
	out["applied"] = true;
	return out;
}

Dictionary set_particle_material_on(Node *p_root, const String &p_node_path, const Dictionary &p_material_params,
		MCPToolError &r_error) {
	Node *node = particle_system_node(p_root, p_node_path, r_error);
	if (node == nullptr) {
		return Dictionary();
	}
	if (p_material_params.is_empty()) {
		r_error = MCPToolError::invalid_params("'material_params' must not be empty: it is the set of particle "
											   "process-material parameters to write");
		return Dictionary();
	}
	Ref<ParticleProcessMaterial> material = particle_process_material_of(node, true, r_error);
	if (material.is_null()) {
		return Dictionary();
	}
	const Dictionary result = apply_particle_material_params(material.ptr(), p_material_params, r_error);
	if (result.is_empty()) {
		return Dictionary();
	}

	Dictionary out;
	out["node_path"] = relative_path(p_root, node);
	out["type"] = node->get_class();
	out["process_material_slot"] = particle_process_material_slot();
	out["process_material"] = serialize_variant(Variant((Object *)material.ptr()));
	Array changed = result["changed"];
	Array ignored = result["ignored"];
	out["changed"] = changed;
	out["ignored"] = ignored;
	out["changed_count"] = changed.size();
	out["ignored_count"] = ignored.size();
	// The whole parameter set as the engine now holds it, so one call shows every
	// parameter of the material and not only the ones that were written - and the
	// shape is the write shape, so it can be fed straight back.
	out["params"] = particle_material_params(material.ptr());
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

static bool _require_non_empty(const Dictionary &p_args, const String &p_key, String &r_out, MCPToolError &r_error) {
	if (!require_string(p_args, p_key, r_out, r_error)) {
		return false;
	}
	if (r_out.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params(vformat("'%s' must not be empty", p_key));
		return false;
	}
	return true;
}

static Variant _tool_create_particles(const Dictionary &p_args, MCPToolError &r_error) {
	String parent_path;
	if (!optional_string(p_args, "parent_path", ".", parent_path, r_error)) {
		return Variant();
	}
	String particle_type;
	if (!optional_string(p_args, "particle_type", "GPUParticles2D", particle_type, r_error)) {
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", "Particles", name, r_error)) {
		return Variant();
	}
	if (name.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'name' must not be empty: it is the node name every later node_path "
											   "addresses the system by");
		return Variant();
	}
	const String type = particle_type.strip_edges();
	if (type != "GPUParticles2D" && type != "GPUParticles3D") {
		// The other particle classes (`CPUParticles2D`/`CPUParticles3D`) have no
		// `process_material` slot, so every other tool of this family would
		// refuse the node they created.
		r_error = MCPToolError::invalid_params(vformat(
				"particle_type must be GPUParticles2D or GPUParticles3D: this family writes the node's particle "
				"properties and its process_material slot, which those two classes have. Got '%s'", particle_type));
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor particle writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Node *parent = find_node(root, parent_path);
	if (parent == nullptr) {
		r_error = MCPToolError::not_found(vformat("Parent node '%s' in the edited scene", parent_path),
				"'parent_path' is relative to the edited scene root ('.' is the root itself); call "
				"editor_get_scene_tree to list the nodes that are there");
		return Variant();
	}
	const String node_name = name.strip_edges();
	if (parent->has_node(NodePath(node_name))) {
		r_error = MCPToolError::tool_state(
				vformat("Node '%s' already has a child named '%s'", relative_path(root, parent), node_name),
				"Node::add_child would silently rename the new system to \"<name>2\"; pick another 'name' or remove "
				"the existing node first");
		return Variant();
	}

	MCPToolError instantiate_error;
	Object *created = instantiate_class(type, instantiate_error);
	if (created == nullptr) {
		r_error = MCPToolError::internal(vformat("Cannot create %s: %s", type, instantiate_error.message));
		return Variant();
	}
	Node *node = Object::cast_to<Node>(created);
	if (node == nullptr) {
		r_error = MCPToolError::internal(vformat("%s is not a Node", type));
		return Variant();
	}
	add_typed_child(root, parent, node_name, node);
	Ref<ParticleProcessMaterial> material = particle_process_material_of(node, true, r_error);
	if (material.is_null()) {
		return Variant();
	}

	// Read back: the node really is a child of the parent, really is the class
	// the answer claims and really has its process material.
	Node *stored = parent->get_node_or_null(NodePath(node_name));
	if (stored == nullptr || !stored->is_class(StringName(type))) {
		r_error = MCPToolError::internal(vformat(
				"The particle system was added under '%s' but the parent does not answer a %s named '%s'",
				parent_path, type, node_name));
		return Variant();
	}
	Dictionary out;
	out["created"] = true;
	out["name"] = String(stored->get_name());
	out["node_path"] = relative_path(root, stored);
	out["type"] = stored->get_class();
	out["parent_path"] = relative_path(root, parent);
	out["owner"] = stored->get_owner() != nullptr ? relative_path(root, stored->get_owner()) : String();
	out["amount"] = (int64_t)stored->get(StringName("amount"));
	out["lifetime"] = (double)stored->get(StringName("lifetime"));
	out["one_shot"] = (bool)stored->get(StringName("one_shot"));
	out["emitting"] = (bool)stored->get(StringName("emitting"));
	out["process_material_slot"] = particle_process_material_slot();
	out["process_material"] = serialize_variant(Variant((Object *)material.ptr()));
	if (stored->is_class(StringName("GPUParticles3D"))) {
		// A 3D system draws nothing until a draw pass holds a mesh; the engine's
		// own count is answered so the caller can see that state.
		out["draw_passes"] = (int64_t)stored->get(StringName("draw_passes"));
		out["has_draw_pass_mesh"] = stored->get(StringName("draw_pass_1")).get_type() != Variant::NIL;
	} else {
		out["texture"] = serialize_variant(stored->get(StringName("texture")));
	}
	return out;
}

static Variant _tool_set_particle_preset(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_non_empty(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	String preset;
	if (!_require_non_empty(p_args, "preset", preset, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor particle writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_particle_preset_on(root, node_path, preset, r_error);
}

static Variant _tool_set_particle_color_gradient(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_non_empty(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (!p_args.has("colors")) {
		r_error = MCPToolError::invalid_params("Missing required parameter: colors");
		return Variant();
	}
	const Variant colors_value = p_args["colors"];
	if (colors_value.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'colors' must be an array of {offset, color} "
													   "objects (got %s)",
				Variant::get_type_name(colors_value.get_type())));
		return Variant();
	}
	const Array colors = colors_value;
	// `colors` is refused here, before the editor prerequisite, exactly like
	// `material_params` below: an argument that cannot mean anything is an
	// argument error whatever the process is (`set_particle_color_stops` repeats
	// the guard, because it is a public entry point of this family).
	if (colors.is_empty()) {
		r_error = MCPToolError::invalid_params("'colors' must not be empty: a gradient with no stop draws nothing, "
											   "and the migration source silently produced one");
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor particle writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_particle_color_gradient_on(root, node_path, colors, r_error);
}

// The three argument rules of `material_params` (present, an object, not empty)
// in one place, so the handler can run them before the editor prerequisite
// without repeating the messages `set_particle_material_on` uses.
static bool _require_material_params(const Dictionary &p_args, Dictionary &r_out, MCPToolError &r_error) {
	if (!p_args.has("material_params")) {
		r_error = MCPToolError::invalid_params("Missing required parameter: material_params");
		return false;
	}
	const Variant raw_params = p_args["material_params"];
	if (raw_params.get_type() != Variant::DICTIONARY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'material_params' must be an object of parameter "
													   "names (got %s)",
				Variant::get_type_name(raw_params.get_type())));
		return false;
	}
	if (((Dictionary)raw_params).is_empty()) {
		r_error = MCPToolError::invalid_params("'material_params' must not be empty: it is the set of particle "
											   "process-material parameters to write");
		return false;
	}
	r_out = raw_params;
	return true;
}

static Variant _tool_set_particle_material(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_non_empty(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	Dictionary material_params;
	if (!_require_material_params(p_args, material_params, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor particle writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_particle_material_on(root, node_path, material_params, r_error);
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
//
// The authoritative `description` and `inputSchema` of each tool are the
// contract entries of docs/tools_list.renamed.json, character for character.
// ---------------------------------------------------------------------------
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_particle_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_particle_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_create_particles", String::utf8(R"desc(创建粒子系统节点)desc"));
		builder.channel("editor").verb("create").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"name":{"default":"Particles","type":"string"},"parent_path":{"default":".","description":"父节点路径","type":"string"},"particle_type":{"default":"GPUParticles2D","description":"粒子类型","type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_create_particles).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_particle_preset", String::utf8(R"desc(应用粒子预设)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"},"preset":{"description":"fire/smoke/magic/explosion/rain/snow","type":"string"}},"required":["node_path","preset"],"type":"object"})schema"));
		builder.handler(_tool_set_particle_preset).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_particle_color_gradient", String::utf8(R"desc(设置粒子颜色渐变)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"colors":{"description":"颜色停止点数组 [{offset, color}]","type":"array"},"node_path":{"type":"string"}},"required":["node_path","colors"],"type":"object"})schema"));
		builder.handler(_tool_set_particle_color_gradient).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_particle_material", String::utf8(R"desc(设置粒子材质)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"material_params":{"description":"材质参数字典","type":"object"},"node_path":{"type":"string"}},"required":["node_path","material_params"],"type":"object"})schema"));
		builder.handler(_tool_set_particle_material).register_into(r_registry);
	}
}
