/**************************************************************************/
/*  editor_shader_write.h                                                 */
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
// TASK-035 (B5 batch 3): the `editor_shader_write` group (2 tools).
//
// Both tools began this batch as a faithful port of the migration source
// (`godot_mcp_gdext/src/commands/shader.rs`), and its red doctest run measured
// the two defects the batch closes:
//
//   * `assign_shader_material` (:90-113) read `material_slot` and then wrote the
//     hard-coded `"material"` property (`:93`, `:111`), so on a node whose
//     material lives elsewhere (a `MeshInstance3D` surface, or any node without a
//     `material` property) the write either landed in the wrong slot or nowhere,
//     next to `assigned: true`;
//   * `set_shader_param` (:117-137) wrote `node.set("material:shader_parameter/<name>", v)`
//     through the **composite property path**, which is the E-5 question of this
//     batch: `Object::set` does not split `:` paths, so the call is a silent
//     no-op announced as `set: true`.
//
// The fixed implementation enumerates the node's real material slots, writes the
// slot the caller named, and takes the shader parameter path through
// `ShaderMaterial::set_shader_parameter` - each with a read-back, so neither can
// report a write the engine did not store.
// ---------------------------------------------------------------------------

namespace MCPTools {

// Loads `p_shader_path` as a `Shader`, creates or reuses the `ShaderMaterial` in
// `p_slot_argument` and assigns it. The answer names the slot really written,
// every slot the node has and the material that was replaced.
//
// TASK-037 R1: `p_slot_present` says whether the caller sent `material_slot`.
// The contract's `default` is `"material"`, which only a `CanvasItem` has; when
// the argument was omitted this function resolves that default against the node
// (its own first material slot) instead of taking the literal, so a 3D mesh is
// not refused by a client that simply filled in the schema default.
Dictionary set_shader_material_on(Node *p_root, const String &p_node_path, const String &p_shader_path,
		const String &p_slot_argument, bool p_slot_present, MCPToolError &r_error);

// Writes one shader parameter of the node's first `ShaderMaterial` through
// `ShaderMaterial::set_shader_parameter`, after checking the name against the
// shader's own uniform list, and answers the value the engine holds afterwards.
Dictionary set_shader_param_on(Node *p_root, const String &p_node_path, const String &p_param,
		const Variant &p_value, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_shader_write_tools(MCPToolRegistry &r_registry);
