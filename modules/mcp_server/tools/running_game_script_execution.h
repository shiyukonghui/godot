/**************************************************************************/
/*  running_game_script_execution.h                                       */
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

#include "../tool_registry.h"

#include "core/variant/variant.h"

class Node;

// TASK-010 section 2, group `running_game_script_execution` of
// docs/tool-groups-b2.json: `running_game_execute_gdscript`, the E3 lever.
//
// The tool compiles the caller's code into a GDScript *in the process that
// serves the endpoint* - i.e. inside the running game - and calls it. That is
// what reaches the engine singletons (`Input`, `Engine`, `OS`), which the
// migration source's `Expression.execute([], self, false)` path could not: an
// expression resolves names against its base object only.
//
// It is a group of its own because it is `mutating = true` (the script may
// change anything) while every tool of the observation group is read-only, and a
// group carries exactly one `mutating` value (GDR-18 / GDR-19 section 17.1).
void register_running_game_script_execution_tools(MCPToolRegistry &r_registry);

// ---------------------------------------------------------------------------
// TASK-090 (item B), decision D-3: the game-side executor must be able to reach
// the **running scene tree**.
//
// The defect, measured in TASK-089's round-7 session: the generated script was
// `extends RefCounted` and its instance was never in a tree, so `get_node()`,
// `$Path`, node properties, signals and `get_tree()` simply did not exist on
// `self` - the body could reach the global singletons and nothing else. The
// contract said "execute GDScript in the running game" and did not say that.
//
// The ruling (TASK-090 item B): run the body in the live scene tree's context by
// mounting the generated script instance as a real `Node` **under the current
// scene root** for the duration of the call. The alternatives and why they were
// rejected are in `REBUILT-2C-MANIFEST.md` section 2c-9 (J-2); the short form:
//
//   * a `RefCounted` body cannot call `get_node()` at all, so "inject the scene
//     root into the existing context" cannot deliver the capability the task
//     asks for - it would only add a second spelling (`root.get_node(...)`) for
//     what the engine already spells `get_node(...)`;
//   * attaching the script to the *existing* scene root (`set_script()`) would
//     have to restore the previous script afterwards, and re-attaching a script
//     is not free of side effects (the previous script instance is rebuilt, and
//     its own `_ready`/`_init` state is lost) - i.e. it really does pollute the
//     game;
//   * a mount point of our own, removed before control returns, is the only
//     option with a **deterministic** end: one `add_child`, one `remove_child`,
//     one delete, on every path including the failing ones.
//
// The mounting contract, as implemented:
//
//   * the code compiles to `extends Node` and the instance is added as the last
//     child of the mount point;
//   * `self` is therefore a genuine in-tree node: `get_node()` / `$Path` resolve
//     **relative to it** (its parent is the scene root, so a game script written
//     against the scene root reaches a child with `get_parent().get_node(...)`),
//     absolute paths (`/root/Main/...`) and `get_tree().current_scene` reach the
//     whole tree, signals connect and emit, and a `func _ready()` in the body
//     runs when the node enters the tree - the ordinary Godot semantics;
//   * the node is removed again **on every path**, success or failure, and never
//     outlives the call. `_process` / `_physics_process` therefore do not tick:
//     the call is synchronous, the node exists for less than one frame, and that
//     boundary is stated rather than papered over;
//   * when this process has **no** scene tree (`SceneTree::get_singleton()` is
//     null, or it has neither a current scene nor a root) the tool falls back to
//     the previous `extends RefCounted` behaviour, so a call that worked before
//     (engine singletons only) keeps working, byte for byte, with the same
//     answer shape.
//
// `execute_gdscript_code()` is that whole body with the mount point passed in -
// exported because the doctest binary has no `SceneTree`, so the only way to pin
// the new capability in-process is to hand it a real node tree the test built.
// It sits at the same (global) scope as `register_...` above, which is this
// group header's convention: the group's own entry points are not inside
// `namespace MCPTools` even though the definitions use that namespace's helpers.
// ---------------------------------------------------------------------------
Variant execute_gdscript_code(const String &p_code, bool p_tool_script, Node *p_mount_point, MCPToolError &r_error);
