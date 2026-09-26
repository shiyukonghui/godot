/**************************************************************************/
/*  editor_node_instantiate.h                                             */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/
#pragma once

#include "../tool_registry.h"

#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// `Node` is only ever used through a pointer by the helpers declared below, so
// the class name is forward declared instead of dragging `scene/` into every
// translation unit that includes this header.
class Node;

// B3 group `editor_node_instantiate` (docs/tool-groups-b3.json) - node creation
// of a *specific* engine type, four tools:
//
//   editor_add_scene_instance  (scene.rs:284)
//   editor_add_raycast         (physics.rs:67)
//   editor_add_mesh_instance   (scene_3d.rs:73)
//   editor_add_gridmap         (scene_3d.rs:256)
//
// All four are `scope = editor` and `mutating = true`
// (docs/tool-rename-map.json), so they are registered only in an editor process
// and a game process must answer `-32601` without executing anything.
//
// The group deliberately does **not** re-implement what already has one
// definition in the module:
//
//   * the parent path is resolved with `MCPTools::find_node` (hoisted by
//     TASK-016 section 1), never with a copy;
//   * `mesh_library` is written through `MCPTools::write_node_property`
//     (tools/running_game_node_write.h), so "ask the object whether it has the
//     property before writing it" has one implementation for the whole module.
//
// The one behaviour this group corrects is `editor_add_gridmap`: the migration
// source loaded `mesh_library_path` inside an `if let Some(lib)` and answered
// `{"created": true}` when the load failed (scene_3d.rs:273-280), so a caller
// could not tell a GridMap that has its mesh library from one that does not.
// Here a load that does not produce a `MeshLibrary` is a `-32001` with a
// suggestion, and nothing is created.
//
// The helper functions below are declared here for the same reason
// `editor_node_write.h` declares its five: the doctest binary has no `SceneTree`
// at all, so a *tool-level* test can only ever observe the `-32000` "no edited
// scene" guard. The entry points below take the nodes, which is what lets the
// cases pin the real behaviour - including the gridmap correction - against bare
// `Node` objects. Behaviour is documented at each definition.
namespace MCPTools {

// Names `p_node` (when `p_name` is not empty), adds it under `p_parent` and makes
// it part of the saved scene by setting `owner` to `p_root`.
//
// `owner` has to be set *after* `add_child()`: it is the ancestor relationship
// that makes the root a legal owner, and a node without an owner is a runtime
// child that `PackedScene::pack()` silently drops.
void add_typed_child(Node *p_root, Node *p_parent, const String &p_name, Node *p_node);

// Loads `p_mesh_library_path` and writes it into `p_gridmap`'s `mesh_library`
// property through `MCPTools::write_node_property`.
//
// A path that does not name a loadable `MeshLibrary` is a `-32001` with a
// `data.suggestion` - this is the correction described in the file comment above
// and the red half of the group's TDD pair. On failure `p_gridmap` is left
// untouched.
bool attach_mesh_library(Node *p_gridmap, const String &p_mesh_library_path, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_node_instantiate_tools(MCPToolRegistry &r_registry);