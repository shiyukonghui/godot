/**************************************************************************/
/*  running_game_navigation_write.h                                       */
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
// TASK-036 (B5 batch 4): the `running_game_navigation_write` group (1 tool).
//
// `running_game_move_player_to_target` (`running_game`, `move`, `scope = game`,
// `mutating = true`). It is the only game-scope movement write and the only
// B5 tool that answers across frames for a *movement* reason (GDR-20).
//
// The engine's own model is the design basis (GDR-23):
//
//   * a `NavigationAgent2D`/`NavigationAgent3D` is the engine's pathfinding
//     agent. `set_target_position()` + `get_next_path_position()` +
//     `is_navigation_finished()` is the engine's own "follow the path" loop,
//     which is what the engine's documentation puts in `_physics_process`
//     (`scene/3d/navigation/navigation_agent_3d.h`), and it is what this tool
//     drives when the player owns one;
//   * without an agent, a `Node2D`/`Node3D` still has a navigation map
//     (`World2D::get_navigation_map` / `World3D::get_navigation_map`) and the
//     engine can answer a path for it: `NavigationServer2D/3D::map_get_path`
//     returns the corridor polyline, which the tool walks waypoint by waypoint;
//   * a map **without any region** has no navigation data at all; the tool
//     refuses with `-32000` (with the engine's own region list as evidence)
//     rather than moving the player straight through the world and calling it
//     pathfinding. That is the honest answer the task book asks for.
//   * a `CharacterBody2D`/`CharacterBody3D` is moved with the engine's own
//     movement API (`velocity` + `move_and_slide()`); any other `Node2D`/`Node3D`
//     is advanced by `speed * delta` per frame along the path. Either way the
//     position changes over many frames, which is observable per frame by
//     `running_game_get_node_properties` - never a single teleport.
//   * the migration source's `_cmd_move_to`
//     (`addons/godot_mcp_rs/mcp_runtime_agent.gd:561-623`) did walk in a
//     `while`/`await` loop, but it never consulted the navigation server or an
//     agent at all: it moved straight towards the target position, so it walked
//     through walls and only handled `Vector2`.
// ---------------------------------------------------------------------------

class Node;
class SceneTree;

namespace MCPTools {

// True when the node's movement dimension is 3D (`Node3D` subclass).
bool move_is_3d(const Object *p_node);

// The player the tool moves: `p_player_path` when it is given (resolved with the
// game-side `resolve_game_node` semantics, or with the editor-side `find_node`
// when this process has no `SceneTree`), otherwise the engine's own movable
// character classes - a node named `Player` that is a `Node2D`/`Node3D` first,
// then the first `CharacterBody2D`/`CharacterBody3D` of the subtree. A miss is a
// `-32001` naming what was searched for.
Node *resolve_move_player(SceneTree *p_tree, Node *p_root, const String &p_player_path, MCPToolError &r_error);

// The destination of the move. `p_target` is either a node path (the node's
// `global_position`) or an object of coordinates (`{x,y}` for a 2D player,
// `{x,y,z}` for a 3D one); a `Vector2`/`Vector3` value is taken as-is. Every
// component is width-gated through the module's one slot gate by the same
// component mapping the node writes use (`coerce_to_property_type` with
// `ValueSlot::REAL_T`, GDR-22). `r_source` says which spelling answered.
bool move_target_from_value(SceneTree *p_tree, Node *p_root, const Variant &p_target, bool p_is_3d,
		Vector3 &r_target_3d, Vector2 &r_target_2d, String &r_source, MCPToolError &r_error);

// The speed the move uses and where it came from:
//   * the `NavigationAgent*`'s own `max_speed` when an agent drives the move and
//     it is positive (`navigation_agent_max_speed`);
//   * the player's own `speed` property when it declares one (`player_speed`);
//   * `200.0` units per second otherwise (`default_200`), the migration source's
//     own default `move_speed` (`mcp_runtime_agent.gd:564`).
// `run = true` doubles the speed (the engine has no "run" concept; the contract's
// only lever is this boolean, so the multiplier is reported as `run_multiplier`).
double move_speed_of(Node *p_player, double p_agent_max_speed, bool p_run, String &r_source);

} // namespace MCPTools

// TASK-036 section 3: the one game-scope movement write (deferred).
void register_running_game_navigation_write_tools(MCPToolRegistry &r_registry);
