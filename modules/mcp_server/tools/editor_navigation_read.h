/**************************************************************************/
/*  editor_navigation_read.h                                              */
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

// `navigation_info_on` walks a `Node` subtree but never dereferences one here,
// so the class is forward declared instead of dragging `scene/` into every
// translation unit that includes this header.
class Node;

// ---------------------------------------------------------------------------
// TASK-034 (B5 batch 2): the `editor_navigation_read` group (1 tool).
//
// `editor_get_navigation_info` walks the subtree of `node_path` (default `.`)
// and answers the navigation nodes it really holds, grouped by the engine's own
// classes, in the engine's own child order (deterministic - PLAYBOOK 6.8):
//
//   * regions: `NavigationRegion3D` (`get_navigation_mesh`/`is_enabled`/
//     `get_navigation_layers`, `scene/3d/navigation/navigation_region_3d.h:78-102`)
//     with the mesh's own vertex/polygon counts (`NavigationMesh::get_vertices`,
//     `scene/resources/navigation_mesh.h:188`, `get_polygon_count`, :191), and
//     `NavigationRegion2D` (`navigation_region_2d.h:84-108`) with
//     `NavigationPolygon`'s (`scene/resources/2d/navigation_polygon.h:103,106`);
//   * agents: `NavigationAgent2D`/`NavigationAgent3D` - `radius`, `max_speed`,
//     `navigation_layers`, `avoidance_enabled` and the target position
//     (`navigation_agent_3d.h:138-207`);
//   * links: `NavigationLink2D`/`NavigationLink3D` - start/end position,
//     `bidirectional`, `navigation_layers`, `enabled`
//     (`navigation_link_3d.h:72-90`);
//   * obstacles: `NavigationObstacle2D`/`NavigationObstacle3D` - their radius and
//     avoidance flags.
//
// The migration source's category is the same walk (`navigation.rs:365-420`) but
// its `path` field was the node's **name** (`node.get("name").to_string()`,
// `navigation.rs:377`), not a path any other tool can consume, and it knew only
// the four region/agent classes. Every entry here answers the edited-scene-root
// relative path that the module's `node_path` arguments take, so a result can be
// fed straight back into `editor_set_navigation_layers`, the node tools or
// another read (GDR-25 section 23.1).
//
// The engine's own model is the design basis (GDR-23); the reference is in the
// `.cpp` beside the entry point and in REPORT-034.
// ---------------------------------------------------------------------------

namespace MCPTools {

// The whole answer of `editor_get_navigation_info` for the subtree at
// `p_node_path` in the edited scene.
Dictionary navigation_info_on(Node *p_root, const String &p_node_path, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_navigation_read_tools(MCPToolRegistry &r_registry);