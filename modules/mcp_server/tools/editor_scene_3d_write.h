/**************************************************************************/
/*  editor_scene_3d_write.h                                               */
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

// ---------------------------------------------------------------------------
// TASK-034 (B5 batch 2): the `editor_scene_3d_write` group (1 tool).
//
// `editor_set_material_3d` writes one **surface slot** of a `MeshInstance3D`:
// `MeshInstance3D::set_surface_override_material(int p_surface, const Ref<Material> &)`
// (`scene/3d/mesh_instance_3d.cpp:375`) with `get_surface_override_material`
// (:387) as the read-back and `get_surface_override_material_count` (:371) as the
// range the slot has to be in.
//
// This is the tool M4c's **E-4** is about: the migration source *read* a
// `material_slot` argument and then wrote slot **0** in a hard-coded GDScript
// expression (`godot_mcp_gdext/src/commands/scene_3d.rs:131` and `:142`), so the
// slot a caller asked for was silently ignored. This implementation honours the
// slot, validates it against the mesh's own surface count and answers **every**
// slot's material, so "slot 0 and slot 1 really differ" is observable in one
// response.
//
// The contract declared the argument as a *string* until TASK-035 section 0 and
// the implementation worked around it by accepting the decimal spelling of an
// index (`"0"`, `"1"`, ...). The decision maker approved the schema override
// (`scripts/gen_renamed_contract.py`, `SCHEMA_OVERRIDES["set_material_3d"]`,
// generator 1.10.0) that declares `material_slot` as an **integer** instead -
// the engine's own shape. The string spellings are still *accepted* on the way
// in so a client written against the old contract does not break, and both
// spellings resolve to the same surface index; anything that cannot be read as
// a non-negative index is refused with the mesh's real surface count.
// ---------------------------------------------------------------------------

namespace MCPTools {

// Assigns the material at `p_material_path` to surface slot `p_slot` of the
// `MeshInstance3D` at `p_node_path`. The answer carries the slot really
// written, the mesh's surface count and every slot's material.
Dictionary set_material_3d_on(Node *p_root, const String &p_node_path, const String &p_material_path,
		int p_slot, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_scene_3d_write_tools(MCPToolRegistry &r_registry);
