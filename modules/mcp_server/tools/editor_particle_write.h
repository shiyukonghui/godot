/**************************************************************************/
/*  editor_particle_write.h                                               */
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

#include "tool_builder.h"

// Only ever used through a pointer here; forward declared so this header does
// not drag `scene/` into every translation unit that includes it.
class Node;
class ParticleProcessMaterial;

// ---------------------------------------------------------------------------
// TASK-034 (B5 batch 2): the `editor_particle_write` group (4 tools).
//
//   * `editor_create_particles`             - `GPUParticles2D`/`GPUParticles3D`
//                                             under a parent of the edited
//                                             scene, with the default
//                                             `ParticleProcessMaterial` the
//                                             migration source also created.
//   * `editor_set_particle_preset`          - one of the six presets, written as
//                                             node properties plus process
//                                             material parameters, every one of
//                                             them read back.
//   * `editor_set_particle_color_gradient`  - `Gradient` + `GradientTexture1D`
//                                             into the material's `color_ramp`
//                                             (the read shape is written back).
//   * `editor_set_particle_material`        - the parameter set of
//                                             `particle_shared.*` onto the
//                                             node's `process_material` slot.
//
// The engine's own model is the design basis (GDR-23); the per-tool engine
// reference is in the `.cpp` beside each entry point and in REPORT-034.
// ---------------------------------------------------------------------------

namespace MCPTools {

// The six presets' names, in the order the contract's description lists them
// (`fire/smoke/magic/explosion/rain/snow`), and how many there are. One
// definition for the refusal message and the preset table.
const char *const *particle_preset_names();
int particle_preset_count();

// Applies `p_preset` to the particle system at `p_node_path`: the node's own
// simulation members and the process material's parameters, each through the
// module's value gate, each read back. The answer lists what the engine stored
// (`node_properties`, `material_params`) and what it did not (`ignored`).
Dictionary set_particle_preset_on(Node *p_root, const String &p_node_path, const String &p_preset,
		MCPToolError &r_error);

// Writes `p_colors` (`[{offset, color}]`) into the process material's
// `color_ramp` and answers the engine's own read-back (`colors`), which is the
// same shape `editor_get_particle_info` answers, so the two round-trip.
Dictionary set_particle_color_gradient_on(Node *p_root, const String &p_node_path, const Array &p_colors,
		MCPToolError &r_error);

// Writes `p_material_params` onto the process material of the particle system at
// `p_node_path`, naming the slot it wrote in the answer.
Dictionary set_particle_material_on(Node *p_root, const String &p_node_path, const Dictionary &p_material_params,
		MCPToolError &r_error);

} // namespace MCPTools

void register_editor_particle_write_tools(MCPToolRegistry &r_registry);
