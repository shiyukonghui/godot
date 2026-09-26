/**************************************************************************/
/*  editor_node_setup.h                                                   */
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

// `Color` is named by value in the declaration below; `editor_node_setup.cpp`
// includes the math header itself.
class Color;

#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// `Node` is only ever used through a pointer by the helpers declared below, so
// the class name is forward declared instead of dragging `scene/` into every
// translation unit that includes this header.
class Node;

// B3 group `editor_node_setup` (docs/tool-groups-b3.json; TASK-017 section 2) -
// the seven `setup_*` builders, one file:
//
//   editor_setup_camera_3d          (scene_3d.rs:85)
//   editor_setup_collision_shape    (physics.rs:85)
//   editor_setup_world_environment  (scene_3d.rs:162, old `setup_environment`)
//   editor_setup_lighting           (scene_3d.rs:104)
//   editor_setup_navigation_agent   (navigation.rs:231)
//   editor_setup_navigation_region  (navigation.rs:104)
//   editor_setup_physics_body       (physics.rs:189)
//
// All seven are `channel = editor`, `scope = editor`, `mutating = true`
// (docs/tool-rename-map.json), so they are registered only in an editor process
// and a game endpoint must answer `-32601` without executing anything.
//
// The migration source accepted many of these arguments and then ignored them
// (`_shape_params`, physics.rs:88), fell back to a wrong type instead of
// refusing (`_ =>` a 2D rectangle, physics.rs:131-139; anything but
// `"directional"` became an omni light, scene_3d.rs:117), executed GDScript
// `Expression` instead of calling the engine (`scene_3d.rs:214-249`) or echoed
// the request instead of reading the created state back (navigation.rs:152-158).
// Each helper below states its own correction.
//
// The helper functions are declared here for the same reason
// `tools/editor_node_write.h` declares its five: the doctest binary has no
// `SceneTree` at all, so a tool-level test can only observe the guards. The
// entries below take a root `Node *` and do their own resolution, which is what
// lets the cases pin the `-32001` / `-32000` / `-32602` refusals against bare
// nodes. Behaviour is documented at each definition.
namespace MCPTools {

// A `{"r":..,"g":..,"b":..}` object as a `Color`, every present component pushed
// through `MCPTools::value_fits_slot(FLOAT32)` **before** the `Color` is built
// (TASK-023 D-7 / GDR-24). An absent component takes `p_default_component` (the
// migration source's `unwrap_or(0.3)` for `bg_color`, `unwrap_or(1.0)` for
// `ambient_color`); a present non-numeric or non-representable component is a
// `-32602` naming it (`bg_color.r`).
//
// Declared here for the reason the helpers below are: the result of this
// function goes to `Environment::set_bg_color` / `set_ambient_light_color`,
// dedicated setters that never passed through `coerce_to_property_type`, so the
// value half has to be assertable without an editor. The M4c audit measured
// `{"r":1e300}` answering `code=0` with `Color(inf, 0, 0, 1)` reaching the saved
// `.tscn`; the doctest pins the refusal that replaced it.
bool color_from_json(const Variant &p_value, double p_default_component, const String &p_key,
		Color &r_out, MCPToolError &r_error);

// `find_node(root, path)`; a `Camera3D` hit is configured (`created:false`), a
// `Node3D` hit receives a new `Camera3D` named `Camera3D` (`created:true`), any
// other hit is `-32602` naming its real class and a miss is `-32001`. Both
// refusals run before anything is allocated. Answers
// `{"setup","created","node_path","type","current"}` with `node_path` and
// `current` read back from the engine.
Variant setup_camera_3d_on(Node *p_root, const String &p_path, MCPToolError &r_error);

// Adds a `CollisionShape2D`/`CollisionShape3D` under `p_node_path`, carrying the
// shape named by `p_shape_type` with `p_shape_params` applied to the shape
// *resource* through `MCPTools::write_node_property`. The collision node class
// is derived from the resource's own kind (`Shape2D` -> 2D, `Shape3D` -> 3D), not
// from a hand-written type table.
Variant setup_collision_shape_on(Node *p_root, const String &p_node_path, const String &p_shape_type,
		const Dictionary &p_shape_params, MCPToolError &r_error);

// Ensures a `WorldEnvironment` (and its `Environment`) exists, then applies
// `bg_color` / `ambient_color` with direct C++ calls. `p_path_given` is whether
// `world_env_path` was supplied at all; `p_world_env_path` is used as a node path
// only (never loaded as a resource).
Variant setup_world_environment_on(Node *p_root, bool p_path_given, const String &p_world_env_path,
		const Variant &p_bg_color, const Variant &p_ambient_color, MCPToolError &r_error);

// Adds a `DirectionalLight3D` / `OmniLight3D` / `SpotLight3D` under
// `p_parent_path`. `p_light_type` is matched case-insensitively; anything else is
// `-32602` naming the three values.
Variant setup_lighting_on(Node *p_root, const String &p_parent_path, const String &p_light_type,
		MCPToolError &r_error);

// Adds a `NavigationRegion3D` (+ `NavigationMesh`) or `NavigationRegion2D`
// (+ `NavigationPolygon`) under `p_parent_path`. `p_mode` is `2d` / `3d` / `auto`
// (case-insensitive); `auto` chooses 3D when the parent or an ancestor is a
// `Node3D`, 2D when it is a `Node2D`, and 3D otherwise (the documented default).
// The configured values are read back from the created resource.
Variant setup_navigation_region_on(Node *p_root, const String &p_parent_path, const String &p_mode,
		const String &p_name, double p_agent_radius, double p_agent_height, double p_cell_size,
		MCPToolError &r_error);

// Adds a `NavigationAgent3D` / `NavigationAgent2D` under `p_node_path`.
// `p_agent_type` is exactly `2D` or `3D` (case-sensitive). `radius` and
// `max_speed` are read back from the created agent.
Variant setup_navigation_agent_on(Node *p_root, const String &p_node_path, const String &p_agent_type,
		const String &p_name, double p_radius, double p_max_speed, MCPToolError &r_error);

// Adds `p_body_type` under `p_parent_path`. The class must exist, be a `Node`
// subclass and be a `PhysicsBody2D`/`PhysicsBody3D`; anything else is `-32602`.
Variant setup_physics_body_on(Node *p_root, const String &p_parent_path, const String &p_body_type,
		const String &p_name, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_node_setup_tools(MCPToolRegistry &r_registry);
