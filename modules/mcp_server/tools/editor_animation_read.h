/**************************************************************************/
/*  editor_animation_read.h                                               */
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

#include "scene/animation/animation_node_state_machine.h"
#include "scene/animation/animation_player.h"
#include "scene/animation/animation_tree.h"

#include "tool_builder.h"

// ---------------------------------------------------------------------------
// TASK-033 (B5 batch 1): the `editor_animation_read` group (3 tools).
//
// Everything the write half of the family *answers with* is produced here, so
// the read shapes are the ones the write tools accept (GDR-25 section 23.1):
//
//   * `editor_list_animations` - `AnimationMixer::get_sorted_animation_list()`
//     (animation_mixer.cpp:395): the flat, alphabetically sorted identifiers the
//     mixer itself uses, one of which is exactly what
//     `editor_get_animation_info`'s `animation` argument takes. The per-library
//     breakdown comes from `AnimationMixer::get_animation_library` +
//     `AnimationLibrary::get_animation_list`;
//   * `editor_get_animation_info` - `Animation::get_length` / `get_loop_mode` /
//     `get_step` / `get_track_count` / `track_get_type` / `track_get_path` /
//     `track_get_key_count` / `track_get_key_time` / `track_get_key_value` /
//     `track_get_key_transition` / `value_track_get_update_mode`;
//   * `editor_get_animation_tree_structure` - the tree's root animation node plus
//     `AnimationNodeStateMachine::get_node_list_as_typed_array` /
//     `get_node_position` / `get_transition_count` / `get_transition_from` /
//     `get_transition_to` / `get_transition`,
//     `AnimationNodeBlendTree::get_node_list` / `get_node_connections`, and the
//     tree's own `parameters/...` property list.
//
// Two engine facts shape the answers:
//   * `AnimationNodeStateMachine::states` and `AnimationNodeBlendTree::nodes` are
//     hash maps, so their iteration order is **not** reproducible; every list
//     this group answers with is sorted, and the transition list keeps the
//     engine's own `Vector` order because that vector *is* ordered
//     (PLAYBOOK section 6.8);
//   * `Animation::track_get_key_value` is serialized through the module's one
//     `serialize_variant`, so a key reads back in the same shape the matching
//     write path accepts - `{x,y,z}` for a position key, `{x,y,z,w}` for a
//     rotation key (see REPORT-033 section 5.3).
// ---------------------------------------------------------------------------

namespace MCPTools {

// The player's animations, flat (what the mixer answers) and per library, with
// the player's edited-scene-relative path echoed in `node_path`.
Dictionary list_animations_on(Node *p_root, AnimationPlayer *p_player);
// One animation's full description: length, loop mode, step and every track with
// its keys. `track_index` and the track `type` spelling feed
// `editor_set_animation_keyframe` / `editor_add_animation_track` verbatim.
Dictionary animation_info_on(Node *p_root, AnimationPlayer *p_player, const String &p_animation_name,
		MCPToolError &r_error);
// The tree's structure: root class, states, transitions, blend-tree nodes,
// nested state machines and the `parameters/...` list.
Dictionary animation_tree_structure_on(Node *p_root, AnimationTree *p_tree);
// The structure of one state machine, for the recursion above and for the
// doctests (a state machine is a `Resource`, so it can be exercised without an
// editor). `p_visited` stops a state machine that (directly or indirectly) holds
// itself from recursing forever. Published rather than file-private so the
// doctest can pin the shape without an `AnimationTree` node.
Dictionary animation_state_machine_structure(const Ref<AnimationNodeStateMachine> &p_machine, const String &p_path,
		HashSet<ObjectID> &r_visited);

} // namespace MCPTools

void register_editor_animation_read_tools(MCPToolRegistry &r_registry);
