/**************************************************************************/
/*  editor_physics_write.h                                                */
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

class Node;

// ---------------------------------------------------------------------------
// TASK-035 (B5 batch 3): the `editor_physics_write` group (1 tool).
//
// `editor_set_physics_layers` writes one of the node's two 32-bit mask members
// (`collision_layer` / `collision_mask`, `scene/2d/physics/collision_object_2d.h:52-53`)
// and answers the read-back value plus the project's names for the bits that are
// set. The migration source (`godot_mcp_gdext/src/commands/physics.rs:146-164`)
// had two silent shapes this batch removes:
//
//   * an unknown `layer_type` fell through to `collision` (`:161`), so a typo
//     wrote the wrong member while answering the typo back;
//   * the value was cast to `int` and handed to `Object::set`, whose `int64 ->
//     uint32_t` copy truncates silently for anything outside `0 .. 0xFFFFFFFF`.
// ---------------------------------------------------------------------------

namespace MCPTools {

// Writes `p_layers` (a 32-bit mask) into `p_layer_type` (`"collision"` or
// `"mask"`) of the node at `p_node_path` and answers the value the engine reads
// back. `p_layers` is the JSON integer as delivered, judged as a `uint32_t` here
// because no `ValueSlot` describes that width.
Dictionary set_physics_layers_on(Node *p_root, const String &p_node_path, const String &p_layer_type,
		int64_t p_layers, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_physics_write_tools(MCPToolRegistry &r_registry);
