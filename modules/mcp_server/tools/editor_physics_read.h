/**************************************************************************/
/*  editor_physics_read.h                                                 */
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
// TASK-035 (B5 batch 3): the `editor_physics_read` group (2 tools).
//
//   * `editor_get_physics_layers` answers one node's two masks plus the project's
//     names for the set bits - i.e. exactly the shape `editor_set_physics_layers`
//     writes, so the write can be read back by a different tool.
//   * `editor_get_collision_info` walks a subtree and answers every collision
//     shape it holds **and** every collision object's layers, in the engine's own
//     child order (deterministic). The migration source answered only the shapes
//     (`godot_mcp_gdext/src/commands/physics.rs:216-256`) with a hand-joined
//     `"<path>/<name>"` string, which is why the layers of the body a shape
//     belongs to were unreachable; this version answers the owning body's path as
//     the engine's own `get_path_to` produces it, plus the layers themselves.
// ---------------------------------------------------------------------------

namespace MCPTools {

// The collision shapes and collision objects at and below `p_node_path`.
Dictionary collision_info_at(Node *p_root, const String &p_node_path, MCPToolError &r_error);

// One node's layer state (`physics_layers_record`).
Dictionary physics_layers_at(Node *p_root, const String &p_node_path, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_physics_read_tools(MCPToolRegistry &r_registry);
