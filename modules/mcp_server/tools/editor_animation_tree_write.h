/**************************************************************************/
/*  editor_animation_tree_write.h                                         */
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

#include "scene/animation/animation_tree.h"

#include "tool_builder.h"

// ---------------------------------------------------------------------------
// TASK-033 (B5 batch 1): the `editor_animation_tree_write` group (7 tools).
//
// The engine's own model of an AnimationTree is used throughout: a tree is a
// `Node` carrying an `AnimationRootNode`, a state machine is a *resource* whose
// states are `AnimationNode`s and whose transitions are
// `AnimationNodeStateMachineTransition` resources, a blend tree is a resource
// whose nodes are `AnimationNode`s, and the tree's writable values live in its
// own `parameters/...` property namespace.
//
// The migration source (`commands/animation_tree.rs`, category reference only)
// diverges in five places, each recorded in REPORT-033 section 4:
//   * every `switch_mode` integer was off by one or two (the engine's order is
//     IMMEDIATE, SYNC, AT_END - see `animation_shared.cpp`);
//   * `position_x`/`position_y` were parsed and then never passed to `add_node`;
//   * `set_blend_tree_node` removed an existing node and re-added it, dropping
//     every connection into and out of it;
//   * `remove_transition` was called without checking whether the transition
//     existed, and answered `removed: true` either way;
//   * `set_tree_parameter` wrote blindly through `Object::set` and answered
//     `set: true` for a parameter that does not exist.
// ---------------------------------------------------------------------------

namespace MCPTools {

// Adds an `AnimationTree` under `p_parent_path` in the edited scene, wires it to
// an AnimationPlayer and gives it a fresh `AnimationNodeStateMachine` root, so
// that "create the tree, then add a state" needs no second engine step.
//
// `p_player_path_given` decides whether `p_animation_player_path` is used; when
// it is not, the first `AnimationPlayer` of the edited scene (depth first, in
// the engine's own child order) is wired in and `animation_player_source` says
// so. The response's `node_path` is the *edited scene root relative* path of the
// new node, which every other tool of the family accepts verbatim.
Dictionary create_animation_tree_on(Node *p_root, const String &p_parent_path, const String &p_animation_player_path,
		bool p_player_path_given, const String &p_tree_name, MCPToolError &r_error);

// `AnimationNodeStateMachine::add_node(name, node, position)`: the position is
// part of the same engine call, so the two numbers are honoured (the migration
// source read them and dropped them).
//
// TASK-034 section 0: `p_animation` (used only when `p_animation_given`) is
// written with `AnimationNodeAnimation::set_animation` for an
// `AnimationNodeAnimation` state, and the answer reads it back. Before the
// contract declared the member, a freshly created Animation state could not be
// pointed at an animation by any tool (REPORT-033 section 7.1).
Dictionary add_state_machine_state_on(AnimationTree *p_tree, const String &p_state_machine_path,
		const String &p_state_name, const String &p_state_type, double p_position_x, double p_position_y,
		const String &p_animation, bool p_animation_given, MCPToolError &r_error);

// `AnimationNodeStateMachine::add_transition(from, to, transition)` with the
// modes set through the engine's own setters.
//
// TASK-034 section 0 adds the three transition members the contract declared
// nowhere until this batch: `xfade_time`, `priority` and `advance_condition`,
// each judged before the transition resource is built and each read back. The
// answer's `advance_condition_parameter` is the engine's own
// `parameters/<state machine path>/conditions/<name>` spelling, which
// `editor_set_animation_tree_parameter` takes verbatim.
Dictionary add_state_machine_transition_on(AnimationTree *p_tree, const String &p_state_machine_path,
		const String &p_from_state, const String &p_to_state, const String &p_switch_mode,
		const String &p_advance_mode, double p_xfade_time, bool p_xfade_time_given, int64_t p_priority,
		bool p_priority_given, const String &p_advance_condition, bool p_advance_condition_given,
		MCPToolError &r_error);

// `AnimationNodeStateMachine::remove_node`, with the real state and transition
// counts before and after (`removing a state also removes every transition that
// touched it`).
Dictionary remove_state_machine_state_on(AnimationTree *p_tree, const String &p_state_machine_path,
		const String &p_state_name, MCPToolError &r_error);

// `AnimationNodeStateMachine::remove_transition(from, to)`, refused when there is
// no such transition, with the real transition count in the answer.
Dictionary remove_state_machine_transition_on(AnimationTree *p_tree, const String &p_state_machine_path,
		const String &p_from_state, const String &p_to_state, MCPToolError &r_error);

// `AnimationNodeBlendTree::add_node(name, node, position)` inside the blend tree
// a state of the addressed state machine holds. An existing name is refused
// instead of being removed and re-added (which is what the migration source did,
// and what silently drops the node's connections).
Dictionary set_blend_tree_node_on(AnimationTree *p_tree, const String &p_state_machine_path,
		const String &p_blend_tree_state, const String &p_bt_node_name, const String &p_bt_node_type,
		double p_position_x, double p_position_y, const String &p_animation, bool p_animation_given,
		MCPToolError &r_error);

// Writes one `parameters/...` value of the tree through the engine's own
// property machinery, after checking the name really is a parameter of this tree
// and converting the value to the parameter's declared type. The answer carries
// the read-back, and reports `ignored` - never a silent success - when the
// engine did not store what was asked.
Dictionary set_animation_tree_parameter_on(AnimationTree *p_tree, const String &p_parameter, const Variant &p_value,
		MCPToolError &r_error);

} // namespace MCPTools

void register_editor_animation_tree_write_tools(MCPToolRegistry &r_registry);
