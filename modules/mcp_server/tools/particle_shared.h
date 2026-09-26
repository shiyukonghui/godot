/**************************************************************************/
/*  particle_shared.h                                                     */
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
#pragma once

#include "scene/resources/particle_process_material.h"

#include "tool_builder.h"

// ---------------------------------------------------------------------------
// TASK-034 (B5 batch 2): the engine-facing helpers the two particle groups
// share (`editor_particle_write` 4 tools, `editor_particle_read` 1 tool).
//
// They are *not* a third group: no tool is registered here and
// `docs/tool-groups-b5.json` is untouched. The file exists because the writer's
// read-back and the reader's answer must be the *same* parameter set and the
// same shapes, or "read it, feed it back" breaks (GDR-25 section 23.4); a copy
// per group is exactly how the two would drift.
//
// The engine's own model is the design basis (GDR-23):
//
//   * a particle system is a `GPUParticles2D`/`GPUParticles3D` node whose
//     simulation parameters are members of the node (`amount`, `lifetime`,
//     `one_shot`, `explosiveness`, `randomness`, `speed_scale`, `emitting` -
//     `scene/3d/gpu_particles_3d.h:126-136`) and whose *process material* is one
//     `ParticleProcessMaterial` held in the node's single
//     `process_material` slot (`set_process_material`, gpu_particles_3d.h:135).
//     There is **no slot index** for the process material - that is the whole
//     answer to E-4 for this tool (see REPORT-034 section 5) - so the answer
//     names the slot it wrote instead of leaving it implicit.
//   * a gradient is a `Gradient` resource (offsets + colours,
//     `scene/resources/gradient.h:139-143`) wrapped in a `GradientTexture1D`
//     (`scene/resources/gradient_texture.h`) and held in `color_ramp`
//     (particle_process_material.cpp:2666). Both halves are read back through the
//     engine's own accessors, so the stops a reader answers are the stops the
//     engine holds.
// ---------------------------------------------------------------------------

namespace MCPTools {

// True for a `GPUParticles2D`/`GPUParticles3D` (the engine's own `is_class`
// test, so a subclass answers true as well). `CPUParticles*` is deliberately not
// a particle system *of this family*: it has no `process_material` slot, and
// every other tool here writes exactly that slot.
bool is_particle_system(const Object *p_object);

// The particle system at `p_node_path` in the edited scene. A path that names
// nothing is `-32001` with a suggestion; a path that names another class is
// `-32602` naming the class it really is.
Node *particle_system_node(Node *p_root, const String &p_node_path, MCPToolError &r_error);

// The one slot name a particle system holds its process material in. Answered by
// every write tool, so "which slot was written" is never implicit.
const char *particle_process_material_slot();

// The node's process material. `p_create` decides whether an absent one is
// created and assigned (the write tools) or answered as a null ref (the reader).
// A slot holding a *different* `Material` is refused instead of replaced: a
// `ShaderMaterial` a user put there is not a particle process material, and
// silently swapping it would destroy it.
Ref<ParticleProcessMaterial> particle_process_material_of(Node *p_node, bool p_create, MCPToolError &r_error);

// The parameter names this family writes, in the order they are listed, and how
// many there are. One definition, so the writer's refusal and the reader's
// parameter set cannot disagree.
const char *const *particle_material_param_names();
int particle_material_param_count();

// Writes every member of `p_params` onto `p_material` through the module's own
// value gate (component mapping + `coerce_to_property_type` with the member's
// slot width), then reads each one back. The answer is
// `{changed: [{property, requested, stored}...], ignored: [...]}`: `changed`
// lists the parameters the engine really stored as asked, `ignored` lists the
// ones it clamped or dropped, each with the value it holds and the reason
// (PLAYBOOK section 20.6 - a clamp is never reported as a successful write).
//
// A member that is not a parameter of this family, or whose value cannot fall
// into the parameter's type, is a `-32602` and **nothing** of that call is
// written: the whole set is validated and converted before the first write.
Dictionary apply_particle_material_params(ParticleProcessMaterial *p_material, const Dictionary &p_params,
		MCPToolError &r_error);

// Every parameter of the family as the engine holds it, in the shape the writer
// takes back: floats are numbers, `direction`/`gravity`/... are `{x,y,z}`
// objects, `color` is `{r,g,b,a}`, and `emission_shape` is the engine's own
// shape **name** (not its enum number), because that is what the writer accepts.
Dictionary particle_material_params(ParticleProcessMaterial *p_material);

// The stops of the material's `color_ramp` as `[{offset, color:{r,g,b,a}}]`, in
// the engine's own (sorted) order. `r_present` is false when the slot holds no
// `GradientTexture1D`, in which case the answer is an empty array - the caller
// answers `null` rather than inventing a gradient.
Array particle_color_stops(ParticleProcessMaterial *p_material, bool &r_present);

// Builds `Gradient` + `GradientTexture1D` from `p_colors`
// (`[{offset, color}]`) and assigns it to the material's `color_ramp`. Every
// offset is judged as a `PackedFloat32Array` element and every colour component
// as a `float` (GDR-24 section 22.2) before the gradient is built, and an offset
// outside `[0, 1]` is refused. `r_stored` is the read-back, so the answer carries
// the stops the engine holds (its own sorted order, not the request's).
bool set_particle_color_stops(ParticleProcessMaterial *p_material, const Array &p_colors, Array &r_stored,
		MCPToolError &r_error);

} // namespace MCPTools