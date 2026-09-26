/**************************************************************************/
/*  animation_shared.h                                                    */
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

#include "core/string/string_name.h"
#include "core/variant/variant.h"
#include "scene/animation/animation_blend_tree.h"
#include "scene/animation/animation_node_state_machine.h"
#include "scene/animation/animation_player.h"
#include "scene/animation/animation_tree.h"
#include "scene/resources/animation.h"
#include "tool_builder.h"

// ---------------------------------------------------------------------------
// TASK-033 (B5 batch 1): the engine-facing helpers the three editor animation
// groups share.
//
// They are *not* a fourth tool group: no tool is registered here, and
// `docs/tool-groups-b5.json` is untouched. The file exists because the three
// group files (`editor_animation_write`, `editor_animation_tree_write`,
// `editor_animation_read`) need the same four facts about the engine's own
// vocabulary, and a private copy per group is what the module's helper-hoisting
// rule (TASK-005 section 1, `tool_helpers.h`) exists to prevent:
//
//   1. the spelling of `Animation::TrackType` / `UpdateMode` / `LoopMode`;
//   2. the spelling of `AnimationNodeStateMachineTransition::SwitchMode` /
//      `AdvanceMode` - the migration source wrote raw integers here and got
//      every `switch_mode` wrong (see the `_from_string` bodies);
//   3. which `AnimationNode` subclass an `AnimationNodeStateMachine` state
//      holds, and which subclass a `state_type` / `bt_node_type` names;
//   4. how a node path in the *edited scene* becomes the engine object the tool
//      wants (`AnimationPlayer` / `AnimationTree`) and how a state machine is
//      addressed inside a tree (`AnimationNodeStateMachine::get_node`, never a
//      hand-written `states/<name>` property path).
//
// Every function names the engine API it is built on; that API, not the
// migration source, is the authority (GDR-23 / DESIGN-DETAIL section 21).
// ---------------------------------------------------------------------------

namespace MCPTools {

// `Animation::TrackType` -> the tool spelling (`scene/resources/animation.h:48`).
String animation_track_type_name(Animation::TrackType p_type);
// The tool spelling -> `Animation::TrackType`. Accepts the engine's own enum
// names (`value`, `position_3d`, `rotation_3d`, `scale_3d`, `blend_shape`,
// `method`, `bezier`, `audio`, `animation`) plus the two legacy 2D aliases
// `position_2d`/`rotation_2d`/`scale_2d`, which are folded to `TYPE_VALUE`: in
// Godot 4 a 2D animation track **is** a value track (the 2D track editor writes
// `TYPE_VALUE`); there is no 2D position track type. The migration source folded
// `position_2d` into `TYPE_POSITION_3D`, which then cannot take a `Vector2` key
// at all (`Animation::track_insert_key` requires a `Vector3`, animation.cpp:1727).
bool animation_track_type_from_string(const String &p_type, Animation::TrackType &r_out, String &r_reason);
String animation_update_mode_name(Animation::UpdateMode p_mode);
bool animation_update_mode_from_string(const String &p_mode, Animation::UpdateMode &r_out, String &r_reason);
String animation_loop_mode_name(Animation::LoopMode p_mode);

// `animation_node_state_machine.h:41-52`. The migration source wrote
// `{"at_end": 0, "sync": 2, else 1}` and `{"disabled": 0, "auto": 2, else 1}`;
// the engine's own order is `SWITCH_MODE_IMMEDIATE, SWITCH_MODE_SYNC,
// SWITCH_MODE_AT_END` (0, 1, 2) - so every one of its three `switch_mode`
// spellings wrote a different mode than the caller asked for, and the default
// `"immediate"` wrote `SYNC`. `AdvanceMode` is `DISABLED, ENABLED, AUTO`
// (0, 1, 2), where its mapping happened to be right. Both are named by string
// here and set through the engine's own setter, so the number never appears in
// a tool.
String animation_switch_mode_name(AnimationNodeStateMachineTransition::SwitchMode p_mode);
bool animation_switch_mode_from_string(const String &p_mode, AnimationNodeStateMachineTransition::SwitchMode &r_out, String &r_reason);
String animation_advance_mode_name(AnimationNodeStateMachineTransition::AdvanceMode p_mode);
bool animation_advance_mode_from_string(const String &p_mode, AnimationNodeStateMachineTransition::AdvanceMode &r_out, String &r_reason);

// The state kind of a state machine entry: `animation` (`AnimationNodeAnimation`,
// whose `animation` is a *property*, `animation_blend_tree.h:71`), `blend_tree`
// (`AnimationNodeBlendTree`), `state_machine` (`AnimationNodeStateMachine`) or
// `other` for any other `AnimationNode` subclass the engine allows a state to
// hold.
String animation_state_type_name(const Ref<AnimationNode> &p_node);
// Builds the fresh `AnimationNode` a `state_type` / `bt_node_type` names. The
// engine class names are accepted as well as the short spellings, because a
// caller reading `editor_get_animation_tree_structure` gets the class name from
// the engine and must be able to feed it back (GDR-25 section 23.1).
bool animation_state_type_from_string(const String &p_type, Ref<AnimationNode> &r_out, String &r_reason);

// The `AnimationPlayer` at `p_node_path` in the edited scene (`p_root`). A path
// that names nothing is `-32001` with a suggestion; a path that names another
// class is `-32602` naming the class it really is.
AnimationPlayer *animation_player_node(Node *p_root, const String &p_node_path, MCPToolError &r_error);
// The `AnimationTree` at `p_node_path` in the edited scene.
AnimationTree *animation_tree_node(Node *p_root, const String &p_node_path, MCPToolError &r_error);

// The state machine a `state_machine_path` addresses, starting from a tree's
// root animation node. `""` (and `.`) is the root itself; any other spelling is
// a `/`-separated walk of `AnimationNodeStateMachine::get_node` (the engine's
// own state lookup, `animation_node_state_machine.h:175`). A leading
// `parameters/` - the engine's own parameter prefix - and a trailing `/` are
// folded away, so the `state_machine_path` this module *answers* with can be fed
// straight back. A missing state or a state that is not a state machine is
// `-32001` / `-32602` with the machine's own state list in the suggestion.
Ref<AnimationNodeStateMachine> animation_state_machine_at(const Ref<AnimationRootNode> &p_root,
		const String &p_state_machine_path, MCPToolError &r_error);
// The canonical spelling of the same path (`""` for the root).
String animation_state_machine_path_normalize(const String &p_path);

} // namespace MCPTools
