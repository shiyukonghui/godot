/**************************************************************************/
/*  editor_navigation_write.h                                             */
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

// ---------------------------------------------------------------------------
// TASK-036 (B5 batch 4): the `editor_navigation_write` group (2 tools).
//
// `editor_bake_navigation_mesh` (**`fix_implementation_first`**, the third one
// of B5 after the two tilemap writers) and `editor_set_navigation_layers`. Both
// are `channel = editor`, `scope = editor`, `mutating = true`.
//
// The engine's own model is the design basis (GDR-23):
//
//   * `NavigationRegion3D::bake_navigation_mesh(bool)` (`scene/3d/navigation/
//     navigation_region_3d.cpp:222-236`) **is asynchronous** when its
//     `on_thread` argument is true: it parses the source geometry on the main
//     thread and hands the bake to a `WorkerThreadPool` task
//     (`modues/navigation_3d/3d/nav_mesh_generator_3d.cpp:199-233`), whose
//     completion `is_baking()` reports (`navigation_region_3d.cpp:247-249`) and
//     whose result is written into the mesh before `is_baking()` turns false
//     (`NavMeshGenerator3D::sync`, `:89-121`). `NavigationRegion2D` has the
//     identical pair (`bake_navigation_polygon` / `is_baking`,
//     `scene/2d/navigation/navigation_region_2d.cpp:233-260`). Answering inside
//     the frame that started the bake can therefore only ever be a lie.
//   * `NavigationServer3D::map_get_regions(map)`
//     (`modules/navigation_3d/3d/godot_navigation_server_3d.cpp`) is the
//     engine's own "is this region registered on a real navigation map" test:
//     the dummy navigation server (`servers/navigation_3d/
//     navigation_server_3d_dummy.h:58`) answers an empty list, so a process
//     whose navigation server cannot bake is refused instead of reporting a
//     bake that did nothing.
//   * `navigation_layers` is a **32-bit mask member** of every navigation node
//     (`NavigationRegion3D`, `NavigationAgent3D`, `NavigationLink3D`,
//     `NavigationObstacle3D` and their 2D siblings all register the same
//     property name); its width is checked explicitly here because there is no
//     `ValueSlot` for a `uint32_t` (GDR-22 section 20.1), exactly like
//     `editor_set_physics_layers` (TASK-035).
//   * the layer **names** are project settings - `layer_names/2d_navigation/
//     layer_<n>` and `layer_names/3d_navigation/layer_<n>` are registered by the
//     engine itself (`scene/register_scene_types.cpp:1322/1326`) - so the answer
//     can name the layers the new mask turns on.
// ---------------------------------------------------------------------------

class Node;

namespace MCPTools {

// ---- `editor_set_navigation_layers` -----------------------------------------

// The engine's own `uint32_t` width for a navigation layer mask. A `ValueSlot`
// for it does not exist; the range check is explicit (documented at the
// definition) and the report lists it as a narrowing point.
int navigation_layer_count();

// True and silent when `p_layers` fits `0 .. 0xFFFFFFFF`; otherwise a `-32602`
// naming the width (nothing is written).
bool navigation_layer_mask_fits(int64_t p_layers, MCPToolError &r_error);

// The `ProjectSettings` prefix the node's layer names live under
// (`layer_names/3d_navigation` for a `Node3D`, `layer_names/2d_navigation`
// otherwise), or the empty string for a node without the mask property.
String navigation_layer_setting_prefix(const Object *p_node);

// The ascending layer numbers (1..32) a mask has set.
Array navigation_layer_bits(uint32_t p_mask);

// The project's names of the set layers, ascending; an unnamed layer answers the
// empty string so the array lines up with `navigation_layer_bits`.
Array navigation_layer_names_of_mask(const Object *p_node, uint32_t p_mask);

// The whole `editor_set_navigation_layers` body: resolve `p_node_path` inside
// `p_root`, check the node really declares `navigation_layers`, range-check the
// mask, write it, read it back and answer the real state. Exported so the
// doctest drives the real function (the doctest process cannot construct a
// navigation node - see the `.cpp` - so what it asserts is the refusal path and
// the mask helpers).
Dictionary set_navigation_layers_on(Node *p_root, const String &p_node_path, int64_t p_layers, MCPToolError &r_error);

// ---- `editor_bake_navigation_mesh` ------------------------------------------

// The region family `p_node` belongs to: `"3d"` for a `NavigationRegion3D`,
// `"2d"` for a `NavigationRegion2D`. Anything else is a `-32602` naming the
// class the node really is. This decides **before** anything navigation-owned is
// constructed or touched, which is what keeps it usable from a doctest.
bool navigation_region_kind(Object *p_node, const String &p_node_path, String &r_kind, MCPToolError &r_error);

// The property a region keeps its navigation resource in (the `"navigation_mesh"`
// of the 3D family, the `"navigation_polygon"` of the 2D one).
const char *navigation_region_resource_property(const String &p_kind);

} // namespace MCPTools

// TASK-036 section 2: the navigation writes - the fix-first bake and the layer
// mask.
void register_editor_navigation_write_tools(MCPToolRegistry &r_registry);
