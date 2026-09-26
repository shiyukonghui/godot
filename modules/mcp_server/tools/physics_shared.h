/**************************************************************************/
/*  physics_shared.h                                                      */
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

#include "scene/main/node.h"

// ---------------------------------------------------------------------------
// TASK-035 (B5 batch 3): the engine-facing helpers the two physics groups share
// (`editor_physics_write` 1 tool, `editor_physics_read` 2 tools).
//
// They are *not* a third group: no tool is registered here.
//
// The engine's own model is the design basis (GDR-23):
//
//   * a collision layer is a **32-bit mask member** of a `CollisionObject2D` /
//     `CollisionObject3D`: `uint32_t collision_layer = 1` and `uint32_t
//     collision_mask = 1` (`scene/2d/physics/collision_object_2d.h:52-53` and
//     `scene/3d/physics/collision_object_3d.h:52`), with
//     `set_collision_layer(uint32_t)` / `set_collision_mask(uint32_t)`; the
//     migration source wrote them through `Object::set` with an `int` and
//     defaulted every unknown `layer_type` to `collision`
//     (`godot_mcp_gdext/src/commands/physics.rs:158-162`). The width that matters
//     here is **32 bits unsigned**, which is why the writer checks
//     `0 .. 0xFFFFFFFF` itself - there is no `ValueSlot` for a `uint32_t`, and the
//     engine's `int64 -> uint32` copy truncates silently
//     (`3000000000 -> -1294967296`-style wraparound is exactly the class of defect
//     GDR-22 exists for).
//   * the **names** of the layers are project settings, not node state:
//     `layer_names/2d_physics/layer_<n>` and `layer_names/3d_physics/layer_<n>`
//     are registered by the engine itself (`scene/register_scene_types.cpp:1320`
//     and `:1324`; the inspector reads the same keys,
//     `editor/inspector/editor_properties.cpp:1448-1466`). Answering them is what
//     turns "collision_layer = 5" into "layers 1 and 3, named 'player' and
//     'enemy'".
// ---------------------------------------------------------------------------

namespace MCPTools {

// The two properties a layer mask lives in, in the order the tools list them
// (`collision_layer`, `collision_mask`).
const char *const *physics_layer_property_names();
int physics_layer_property_count();

// True when `p_node` has a `collision_layer` member, i.e. it is a
// `CollisionObject2D`/`CollisionObject3D` (or a subclass).
bool is_physics_object(const Object *p_node);

// The number of layers a mask can name (`CollisionObject2D`/`3D` expose 32).
int physics_layer_count();

// The `ProjectSettings` prefix the node's layer names live under
// (`layer_names/2d_physics` or `layer_names/3d_physics`), chosen by the node's
// class; the empty string for a node that is not a collision object.
String physics_layer_setting_prefix(const Object *p_node);

// The project's name for layer `p_layer_number` (1..32), or the empty string.
String physics_layer_name(const Object *p_node, int p_layer_number);

// The ascending layer numbers (1..32) a mask has set.
Array physics_layer_bits(uint32_t p_mask);

// The names of the set layers, ascending; an unnamed layer answers the empty
// string so the array still lines up with `physics_layer_bits`.
Array physics_layer_names_of_mask(const Object *p_node, uint32_t p_mask);

// The node's whole layer state as every physics tool answers it:
// `{node_path, node_type, dimension, collision_layer, collision_mask,
//   collision_layer_bits, collision_mask_bits, collision_layer_names,
//   collision_mask_names, layer_count}`. A node without the members is refused
// with `-32602` naming the class it really is.
Dictionary physics_layers_record(Object *p_node, const String &p_node_path, MCPToolError &r_error);

} // namespace MCPTools