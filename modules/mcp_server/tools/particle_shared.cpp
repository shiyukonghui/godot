/**************************************************************************/
/*  particle_shared.cpp                                                   */
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
#include "particle_shared.h"

#include "running_game_node_write.h"
#include "tool_helpers.h"

#include "scene/2d/gpu_particles_2d.h"
#include "scene/3d/gpu_particles_3d.h"
#include "scene/resources/gradient_texture.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-034: the parameter table.
//
// Every entry names a property the engine registers itself
// (`particle_process_material.cpp:2609-2611`, `:2587-2598`, `:2637`, `:2651`,
// `:2665-2666`, `:2680-2684`), and the **slot** column is read out of the setter
// the property is bound to, not guessed:
//
//   * `spread`, `flatness` and every `*_min`/`*_max` pair are
//     `set_spread(float)` / `set_flatness(float)` / `set_param_min(Parameter,
//     float)` (particle_process_material.h:405-421) - a `float` parameter, so the
//     slot is `FLOAT32` whatever the build's `real_t` is;
//   * `emission_sphere_radius` and the `emission_ring_*` family are `real_t`
//     members (`set_emission_sphere_radius(real_t)`, :465, `set_emission_ring_*(real_t)`,
//     :470-474), so their slot is `REAL_T`;
//   * `direction`, `gravity`, `emission_box_extents`, `emission_ring_axis`,
//     `turbulence_noise_speed` and `velocity_pivot` are `Vector3` properties
//     (`:402`, `:502`, `:466`, `:470`, `:494`, `:411`) - their components go
//     through the module's component table (`shape_vector_from_json`,
//     `REAL_T` per component);
//   * `color` is a `Color` (`:431`), whose components are `float`
//     (`core/math/color.h:39-42`) - `FLOAT32` per component (GDR-24 section 22.2);
//   * `emission_shape` is an `INT` enum property (`:464`, registered with the
//     `Point,Sphere,...` hint at `:2587`), and it is written as a named shape so
//     the reader's answer can be fed straight back (GDR-25 section 23.1).
//
// The set is the migration source's parameter list
// (`godot_mcp_gdext/src/commands/particle.rs:134-215`, `addons/godot_mcp/commands/particle_commands.gd:138-254`)
// plus the emission-shape geometry members that source already read
// (`particle_commands.gd:199-224`): it is the set the reference *category*
// covers, and every name in it is a registered property of the engine class.
// ---------------------------------------------------------------------------

namespace {

enum class ParamKind {
	FLOAT, // `ValueSlot::FLOAT32` (a `float` parameter)
	REAL_T, // `ValueSlot::REAL_T` (a `real_t` member)
	VECTOR3, // `{x,y,z}` -> `Vector3`, components through the module's table
	COLOR, // `{r,g,b,a}` or an HTML string -> `Color`
	BOOL,
	EMISSION_SHAPE, // a shape name -> the engine's own enum
};

struct ParamSpec {
	const char *name;
	ParamKind kind;
};

const ParamSpec PARAM_SPECS[] = {
	{ "direction", ParamKind::VECTOR3 },
	{ "spread", ParamKind::FLOAT },
	{ "flatness", ParamKind::FLOAT },
	{ "initial_velocity_min", ParamKind::FLOAT },
	{ "initial_velocity_max", ParamKind::FLOAT },
	{ "gravity", ParamKind::VECTOR3 },
	{ "velocity_pivot", ParamKind::VECTOR3 },
	{ "scale_min", ParamKind::FLOAT },
	{ "scale_max", ParamKind::FLOAT },
	{ "angular_velocity_min", ParamKind::FLOAT },
	{ "angular_velocity_max", ParamKind::FLOAT },
	{ "orbit_velocity_min", ParamKind::FLOAT },
	{ "orbit_velocity_max", ParamKind::FLOAT },
	{ "damping_min", ParamKind::FLOAT },
	{ "damping_max", ParamKind::FLOAT },
	{ "color", ParamKind::COLOR },
	{ "emission_shape", ParamKind::EMISSION_SHAPE },
	{ "emission_sphere_radius", ParamKind::REAL_T },
	{ "emission_box_extents", ParamKind::VECTOR3 },
	{ "emission_ring_axis", ParamKind::VECTOR3 },
	{ "emission_ring_height", ParamKind::REAL_T },
	{ "emission_ring_radius", ParamKind::REAL_T },
	{ "emission_ring_inner_radius", ParamKind::REAL_T },
	{ "emission_ring_cone_angle", ParamKind::REAL_T },
	{ "attractor_interaction_enabled", ParamKind::BOOL },
	{ "turbulence_enabled", ParamKind::BOOL },
	{ "turbulence_noise_strength", ParamKind::FLOAT },
	{ "turbulence_noise_scale", ParamKind::FLOAT },
	{ "turbulence_noise_speed", ParamKind::VECTOR3 },
	{ "turbulence_noise_speed_random", ParamKind::FLOAT },
};

const int PARAM_SPEC_COUNT = (int)(sizeof(PARAM_SPECS) / sizeof(PARAM_SPECS[0]));

const ParamSpec *find_param_spec(const String &p_name) {
	for (int i = 0; i < PARAM_SPEC_COUNT; i++) {
		if (p_name == PARAM_SPECS[i].name) {
			return &PARAM_SPECS[i];
		}
	}
	return nullptr;
}

// The shape names, in the engine's own enum order (`particle_process_material.h:84-92`)
// and with the spellings the editor's enum hint uses
// (`particle_process_material.cpp:2587`: `Point,Sphere,Sphere Surface,Box,Points,Directed Points,Ring`).
struct ShapeName {
	const char *name;
	ParticleProcessMaterial::EmissionShape value;
};

const ShapeName SHAPE_NAMES[] = {
	{ "point", ParticleProcessMaterial::EMISSION_SHAPE_POINT },
	{ "sphere", ParticleProcessMaterial::EMISSION_SHAPE_SPHERE },
	{ "sphere_surface", ParticleProcessMaterial::EMISSION_SHAPE_SPHERE_SURFACE },
	{ "box", ParticleProcessMaterial::EMISSION_SHAPE_BOX },
	{ "points", ParticleProcessMaterial::EMISSION_SHAPE_POINTS },
	{ "directed_points", ParticleProcessMaterial::EMISSION_SHAPE_DIRECTED_POINTS },
	{ "ring", ParticleProcessMaterial::EMISSION_SHAPE_RING },
};

const int SHAPE_NAME_COUNT = (int)(sizeof(SHAPE_NAMES) / sizeof(SHAPE_NAMES[0]));

String shape_name_of(ParticleProcessMaterial::EmissionShape p_shape) {
	for (int i = 0; i < SHAPE_NAME_COUNT; i++) {
		if (SHAPE_NAMES[i].value == p_shape) {
			return SHAPE_NAMES[i].name;
		}
	}
	return String();
}

bool shape_from_name(const String &p_name, int &r_out, String &r_reason) {
	// The migration source lowercased the argument and matched the short
	// spellings (`particle_commands.gd:193-225`); the engine's own
	// `EMISSION_SHAPE_*` constant names are accepted as well, because that is
	// what the engine's documentation and enum use (GDR-25 section 23.1).
	String spelling = p_name.strip_edges().to_lower();
	if (spelling.begins_with("emission_shape_")) {
		spelling = spelling.substr(String("emission_shape_").length());
	}
	for (int i = 0; i < SHAPE_NAME_COUNT; i++) {
		if (spelling == SHAPE_NAMES[i].name) {
			r_out = (int)SHAPE_NAMES[i].value;
			return true;
		}
	}
	Vector<String> names;
	for (int i = 0; i < SHAPE_NAME_COUNT; i++) {
		names.push_back(SHAPE_NAMES[i].name);
	}
	r_reason = vformat("'emission_shape' must name one of the engine's emission shapes (%s); got '%s'",
			String(", ").join(names), p_name);
	return false;
}

// Compares a value the engine stored with the value that was asked for, at the
// width of the member the value went into.
//
// The comparison's own width, not a storage copy: `coerce_to_property_type`
// judged the value as the member's slot before the write, so a value that got
// this far can only differ from the read-back by the member's own rounding
// (`0.1` is not representable as a `float`). Reporting that as "the engine
// ignored the value" would be wrong for every perfectly good write, which is the
// trap PLAYBOOK section 20.6 names.
bool values_agree(const Variant &p_read_back, const Variant &p_written, ParamKind p_kind) {
	if (p_read_back.get_type() != p_written.get_type()) {
		return false;
	}
	if (p_kind == ParamKind::FLOAT) {
		// MCP-NARROWING: G24-PARTICLE-WIDTH - the comparison's own width (the
		// `float` slot `value_fits_slot(FLOAT32)` accepted above); nothing is
		// stored through this cast.
		const float narrowed = (float)(double)p_written;
		return (double)p_read_back == (double)narrowed;
	}
	return p_read_back == p_written;
}

String json_type_list() {
	return "a number for a float parameter, {\"x\",\"y\",\"z\"} for a vector3 parameter, "
		   "{\"r\",\"g\",\"b\",\"a\"} (or an #rrggbb string) for the colour, a boolean, or a shape name for "
		   "emission_shape";
}

} // namespace

namespace MCPTools {

bool is_particle_system(const Object *p_object) {
	if (p_object == nullptr) {
		return false;
	}
	return p_object->is_class(StringName("GPUParticles2D")) || p_object->is_class(StringName("GPUParticles3D"));
}

Node *particle_system_node(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the nodes that are there");
		return nullptr;
	}
	if (!is_particle_system(node)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Node '%s' is a %s, not a GPUParticles2D/GPUParticles3D: this family writes the node's own particle "
				"properties and its process material, which only those two classes have",
				p_node_path, node->get_class()));
		return nullptr;
	}
	return node;
}

const char *particle_process_material_slot() {
	return "process_material";
}

Ref<ParticleProcessMaterial> particle_process_material_of(Node *p_node, bool p_create, MCPToolError &r_error) {
	const Variant current = p_node->get(StringName("process_material"));
	// "The slot is empty" has two spellings the engine really produces: a NIL
	// Variant (a null `Ref<Material>` read from a fresh node) and an OBJECT
	// Variant whose pointer is null (the same ref after a round trip through
	// `Object::set`). Both mean "there is no process material here", and neither
	// is a caller mistake.
	bool empty = current.get_type() == Variant::NIL;
	Object *object = nullptr;
	if (!empty && current.get_type() == Variant::OBJECT) {
		object = current;
		empty = object == nullptr;
	}
	if (empty) {
		if (!p_create) {
			return Ref<ParticleProcessMaterial>();
		}
		Ref<ParticleProcessMaterial> created;
		created.instantiate();
		p_node->set(StringName("process_material"), created);
		const Variant stored = p_node->get(StringName("process_material"));
		Ref<ParticleProcessMaterial> back = Object::cast_to<ParticleProcessMaterial>(stored);
		if (back.is_null()) {
			r_error = MCPToolError::internal(vformat(
					"The process material was assigned to '%s' but the node does not answer a ParticleProcessMaterial",
					p_node->get_name()));
			return Ref<ParticleProcessMaterial>();
		}
		return back;
	}
	if (current.get_type() != Variant::OBJECT) {
		r_error = MCPToolError::invalid_params(vformat(
				"'%s'.process_material holds a %s, not a ParticleProcessMaterial", p_node->get_name(),
				Variant::get_type_name(current.get_type())));
		return Ref<ParticleProcessMaterial>();
	}
	Ref<ParticleProcessMaterial> material = Object::cast_to<ParticleProcessMaterial>(object);
	if (material.is_null()) {
		// The slot holds a *different* material (a ShaderMaterial a user put
		// there, for instance). Replacing it would destroy that work, and
		// silently applying the parameters somewhere else is worse.
		r_error = MCPToolError::invalid_params(vformat(
				"The process_material slot of '%s' holds a %s, not a ParticleProcessMaterial: this tool writes the "
				"particle simulation parameters, which only a ParticleProcessMaterial carries",
				p_node->get_name(), object != nullptr ? object->get_class() : String("Object")));
		return Ref<ParticleProcessMaterial>();
	}
	return material;
}

const char *const *particle_material_param_names() {
	static const char *names[PARAM_SPEC_COUNT + 1];
	static bool initialized = false;
	if (!initialized) {
		for (int i = 0; i < PARAM_SPEC_COUNT; i++) {
			names[i] = PARAM_SPECS[i].name;
		}
		names[PARAM_SPEC_COUNT] = nullptr;
		initialized = true;
	}
	return names;
}

int particle_material_param_count() {
	return PARAM_SPEC_COUNT;
}

Dictionary particle_material_params(ParticleProcessMaterial *p_material) {
	Dictionary params;
	for (int i = 0; i < PARAM_SPEC_COUNT; i++) {
		const ParamSpec &spec = PARAM_SPECS[i];
		const Variant value = p_material->get(StringName(spec.name));
		if (spec.kind == ParamKind::EMISSION_SHAPE) {
			// The name, never the enum number: the writer takes the name back.
			params[spec.name] = shape_name_of((ParticleProcessMaterial::EmissionShape)(int)value);
		} else {
			params[spec.name] = serialize_variant(value);
		}
	}
	return params;
}

Array particle_color_stops(ParticleProcessMaterial *p_material, bool &r_present) {
	r_present = false;
	Array stops;
	const Ref<Texture2D> ramp = p_material->get_color_ramp();
	if (ramp.is_null()) {
		return stops;
	}
	const GradientTexture1D *gradient_texture = Object::cast_to<GradientTexture1D>(ramp.ptr());
	if (gradient_texture == nullptr) {
		// `color_ramp` is typed `GradientTexture1D` by the engine's own
		// PROPERTY_HINT_RESOURCE_TYPE (particle_process_material.cpp:2666), so a
		// different texture in that slot is a state this family does not read.
		return stops;
	}
	const Ref<Gradient> gradient = gradient_texture->get_gradient();
	if (gradient.is_null()) {
		return stops;
	}
	r_present = true;
	// `Gradient::get_offset`/`get_color` run the engine's own `_update_sorting`
	// first, so the stops are answered in the engine's canonical (offset sorted)
	// order whatever order they were inserted in (gradient.cpp:202-219).
	const int count = gradient->get_point_count();
	for (int i = 0; i < count; i++) {
		Dictionary stop;
		stop["offset"] = (double)gradient->get_offset(i);
		stop["color"] = serialize_variant(gradient->get_color(i));
		stops.push_back(stop);
	}
	return stops;
}

bool set_particle_color_stops(ParticleProcessMaterial *p_material, const Array &p_colors, Array &r_stored,
		MCPToolError &r_error) {
	if (p_colors.is_empty()) {
		r_error = MCPToolError::invalid_params("'colors' must not be empty: a gradient needs at least one stop "
											   "({offset, color}); the engine cannot hold an empty Gradient");
		return false;
	}
	// Everything is validated and converted before any resource is built, so a
	// rejected stop cannot leave a half-built gradient in the node.
	Array offsets_json;
	Array colors_json;
	Vector<double> offsets;
	for (int i = 0; i < p_colors.size(); i++) {
		const Variant entry = p_colors[i];
		if (entry.get_type() != Variant::DICTIONARY) {
			r_error = MCPToolError::invalid_params(vformat(
					"'colors[%d]' must be an object {\"offset\": <number in 0..1>, \"color\": <{\"r\",\"g\",\"b\",\"a\"} "
					"or \"#rrggbb\">}; got %s",
					i, Variant::get_type_name(entry.get_type())));
			return false;
		}
		const Dictionary stop = entry;
		const String offset_key = vformat("colors[%d].offset", i);
		if (!stop.has("offset")) {
			r_error = MCPToolError::invalid_params(vformat("'%s' is missing: a stop is {offset, color}", offset_key));
			return false;
		}
		const Variant offset_value = stop["offset"];
		if (offset_value.get_type() != Variant::FLOAT && offset_value.get_type() != Variant::INT) {
			r_error = MCPToolError::invalid_params(vformat("'%s' must be a number; got %s", offset_key,
					Variant::get_type_name(offset_value.get_type())));
			return false;
		}
		const double offset = offset_value;
		if (Math::is_nan(offset) || Math::is_inf(offset) || offset < 0.0 || offset > 1.0) {
			r_error = MCPToolError::invalid_params(vformat(
					"'%s' must be a finite number in 0..1: it is the gradient position the engine samples at, and the "
					"engine stores an out-of-range offset without clamping it while the sampled colour is undefined; "
					"got %f",
					offset_key, offset));
			return false;
		}
		offsets.push_back(offset);
		offsets_json.push_back(offset);

		const String color_key = vformat("colors[%d].color", i);
		if (!stop.has("color")) {
			r_error = MCPToolError::invalid_params(vformat("'%s' is missing: a stop is {offset, color}", color_key));
			return false;
		}
		const Variant color_value = stop["color"];
		Variant shaped;
		if (color_value.get_type() == Variant::DICTIONARY) {
			// The component mapping judges every present component with the
			// `FLOAT32` slot `Color` stores (GDR-24 section 22.2).
			if (!shape_vector_from_json(color_value, Variant::COLOR, color_key, color_key, shaped, r_error)) {
				return false;
			}
		} else {
			Variant converted;
			if (!coerce_to_property_type(color_value, Variant::COLOR, converted, r_error, color_key)) {
				return false;
			}
			shaped = converted;
		}
		colors_json.push_back(shaped);
	}

	// The offsets go through the module's packed-container element gate (a
	// `PackedFloat32Array` element is a `float`, `REAL_T`/`FLOAT32` in this build
	// because the container is 32 bit by definition - GDR-22).
	Variant packed_offsets;
	if (!coerce_to_property_type(offsets_json, Variant::PACKED_FLOAT32_ARRAY, packed_offsets, r_error,
				"colors[].offset")) {
		return false;
	}
	Variant packed_colors;
	if (!coerce_to_property_type(colors_json, Variant::PACKED_COLOR_ARRAY, packed_colors, r_error, "colors[].color")) {
		return false;
	}

	Ref<Gradient> gradient;
	gradient.instantiate();
	// `Gradient::set_offsets` / `set_colors` are the engine's own writers
	// (gradient.h:139-143) and are what the properties are bound to
	// (`gradient.cpp:64-67`); `Object::set` is used so the already-converted
	// packed arrays are handed over as they are.
	gradient->set(StringName("offsets"), packed_offsets);
	gradient->set(StringName("colors"), packed_colors);
	if (gradient->get_point_count() != offsets.size()) {
		r_error = MCPToolError::internal(vformat(
				"The gradient was built with %d stop(s) but the engine holds %d", offsets.size(),
				gradient->get_point_count()));
		return false;
	}

	Ref<GradientTexture1D> texture;
	texture.instantiate();
	texture->set_gradient(gradient);
	// One slot, named in the answer: the process material's `color_ramp`
	// (particle_process_material.cpp:2666).
	p_material->set_color_ramp(texture);

	const Ref<Texture2D> stored_ramp = p_material->get_color_ramp();
	if (stored_ramp.is_null()) {
		r_error = MCPToolError::internal("The colour gradient was assigned to color_ramp but the material answers "
										 "nothing for it");
		return false;
	}
	bool present = false;
	r_stored = particle_color_stops(p_material, present);
	if (!present || r_stored.size() != offsets.size()) {
		r_error = MCPToolError::internal(vformat(
				"The gradient was assigned but the material's color_ramp answers %d stop(s)", r_stored.size()));
		return false;
	}
	return true;
}

Dictionary apply_particle_material_params(ParticleProcessMaterial *p_material, const Dictionary &p_params,
		MCPToolError &r_error) {
	Array changed;
	Array ignored;
	// Pass 1: every key and every value is validated and converted, and only then
	// is anything written. A refused call therefore leaves the material exactly
	// as it was (the all-or-nothing rule every batch writer of this module keeps).
	const Array keys = p_params.keys();
	Vector<const ParamSpec *> specs;
	Vector<Variant> converted_values;
	Vector<Variant> requested_values;
	for (int i = 0; i < keys.size(); i++) {
		const String key = keys[i];
		const ParamSpec *spec = find_param_spec(key);
		if (spec == nullptr) {
			Vector<String> known;
			for (int j = 0; j < PARAM_SPEC_COUNT; j++) {
				known.push_back(PARAM_SPECS[j].name);
			}
			// The migration source silently dropped every unknown key
			// (particle.rs:133-215), so a typo read as "applied"; this is the
			// same refusal TASK-032 D4 gave the tool arguments.
			r_error = MCPToolError::invalid_params(vformat(
					"Unknown material parameter '%s'. The parameters of a particle process material this tool writes "
					"are: %s",
					key, String(", ").join(known)));
			return Dictionary();
		}
		const Variant raw = p_params[key];
		const String context = vformat("material_params.%s", key);
		Variant converted;
		switch (spec->kind) {
			case ParamKind::FLOAT: {
				converted = Variant();
				if (!coerce_to_property_type(raw, Variant::FLOAT, converted, r_error, context, ValueSlot::FLOAT32)) {
					return Dictionary();
				}
			} break;
			case ParamKind::REAL_T: {
				converted = Variant();
				if (!coerce_to_property_type(raw, Variant::FLOAT, converted, r_error, context, ValueSlot::REAL_T)) {
					return Dictionary();
				}
			} break;
			case ParamKind::VECTOR3: {
				Variant shaped;
				if (raw.get_type() != Variant::DICTIONARY) {
					r_error = MCPToolError::invalid_params(vformat(
							"'%s' must be a {\"x\",\"y\",\"z\"} object (%s)", context, json_type_list()));
					return Dictionary();
				}
				// The component mapping is what judges each component with the
				// `REAL_T` slot a `Vector3` stores and what makes the read shape
				// writable again (GDR-25 section 23.4).
				if (!shape_vector_from_json(raw, Variant::VECTOR3, context, context, shaped, r_error)) {
					return Dictionary();
				}
				if (!coerce_to_property_type(shaped, Variant::VECTOR3, converted, r_error, context)) {
					return Dictionary();
				}
			} break;
			case ParamKind::COLOR: {
				if (raw.get_type() == Variant::DICTIONARY) {
					Variant shaped;
					if (!shape_vector_from_json(raw, Variant::COLOR, context, context, shaped, r_error)) {
						return Dictionary();
					}
					if (!coerce_to_property_type(shaped, Variant::COLOR, converted, r_error, context)) {
						return Dictionary();
					}
				} else if (!coerce_to_property_type(raw, Variant::COLOR, converted, r_error, context)) {
					return Dictionary();
				}
			} break;
			case ParamKind::BOOL: {
				if (!coerce_to_property_type(raw, Variant::BOOL, converted, r_error, context)) {
					return Dictionary();
				}
			} break;
			case ParamKind::EMISSION_SHAPE: {
				if (raw.get_type() != Variant::STRING) {
					r_error = MCPToolError::invalid_params(vformat(
							"'%s' must be a shape name (a string); got %s", context,
							Variant::get_type_name(raw.get_type())));
					return Dictionary();
				}
				int shape = 0;
				String reason;
				if (!shape_from_name(raw, shape, reason)) {
					r_error = MCPToolError::invalid_params(reason);
					return Dictionary();
				}
				if (!value_fits_slot(shape, ValueSlot::INT32, context,
							"the int32_t emission_shape member this value is copied into", r_error)) {
					return Dictionary();
				}
				converted = shape;
			} break;
		}
		specs.push_back(spec);
		converted_values.push_back(converted);
		requested_values.push_back(raw);
	}

	// Pass 2: write, then read every one back through the engine's own
	// accessor. `changed` lists only what the engine really stored as asked;
	// anything else is `ignored` with the value the engine holds (PLAYBOOK
	// section 20.6 - a clamped or dropped write is never reported as done).
	for (int i = 0; i < specs.size(); i++) {
		const ParamSpec &spec = *specs[i];
		const StringName name(spec.name);
		p_material->set(name, converted_values[i]);
		const Variant stored = p_material->get(name);
		Dictionary record;
		record["property"] = spec.name;
		record["requested"] = serialize_variant(requested_values[i]);
		if (spec.kind == ParamKind::EMISSION_SHAPE) {
			record["stored"] = shape_name_of((ParticleProcessMaterial::EmissionShape)(int)stored);
		} else {
			record["stored"] = serialize_variant(stored);
		}
		// The comparison is made at the member's width (`values_agree`), and the
		// shape parameter is compared as the engine's own enum number.
		bool applied = false;
		if (spec.kind == ParamKind::EMISSION_SHAPE) {
			applied = (int)stored == (int)converted_values[i];
		} else {
			applied = values_agree(stored, converted_values[i], spec.kind);
		}
		if (applied) {
			changed.push_back(record);
		} else {
			record["reason"] = "the engine stored a different value than the one asked for (the parameter clamps or "
							   "converts it)";
			ignored.push_back(record);
		}
	}

	Dictionary out;
	out["changed"] = changed;
	out["ignored"] = ignored;
	return out;
}

} // namespace MCPTools
