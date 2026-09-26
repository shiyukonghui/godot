/**************************************************************************/
/*  editor_animation_write.h                                              */
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

#include "scene/animation/animation_player.h"

#include "tool_builder.h"

// ---------------------------------------------------------------------------
// TASK-033 (B5 batch 1): the `editor_animation_write` group (4 tools).
//
//   * `editor_create_animation`        - a new `Animation` in the player's
//                                        default library, with its length
//                                        already set in the same engine call.
//   * `editor_add_animation_track`     - `Animation::add_track` +
//                                        `Animation::track_set_path` +
//                                        `Animation::value_track_set_update_mode`.
//   * `editor_set_animation_keyframe`  - `Animation::track_insert_key`, which
//                                        inserts **or replaces** the key at that
//                                        time and takes the easing in the same
//                                        call.
//   * `editor_remove_animation`        - `AnimationLibrary::remove_animation`,
//                                        with the real removal count.
//
// The engine APIs are the design basis (GDR-23 / DESIGN-DETAIL section 21); the
// per-tool engine reference is in the `.cpp` beside each entry point and in
// REPORT-033 section 4.
// ---------------------------------------------------------------------------

namespace MCPTools {

// `AnimationPlayer::get_animation_library("")` is the engine's **default**
// library (the empty `StringName`, `animation_mixer.cpp:162`). It is created on
// demand, because a scene whose AnimationPlayer has no library yet is the normal
// state of a fresh node. Returns a null ref and fills `r_error` when the library
// cannot be created.
Ref<AnimationLibrary> animation_default_library(AnimationPlayer *p_player, MCPToolError &r_error);

// The `Animation` `p_name` names in the mixer's flat list, or a null ref. The
// caller decides whether that is a refusal.
Ref<Animation> animation_named(AnimationPlayer *p_player, const String &p_name);

// The names the player's default library holds, in the engine's own spelling
// (`AnimationLibrary::get_animation_list`), sorted for a deterministic answer.
Vector<String> animation_names_in_default_library(AnimationPlayer *p_player);

// Tool entry points. Each one is the *testable* half of a registered tool: the
// registered handler validates the arguments and the editor prerequisite, then
// calls one of these with an engine object.
Dictionary create_animation_on(AnimationPlayer *p_player, const String &p_animation_name, double p_length,
		MCPToolError &r_error);
Dictionary add_animation_track_on(AnimationPlayer *p_player, const String &p_animation_name, const String &p_track_path,
		const String &p_track_type, const String &p_update_mode, bool p_update_mode_given, MCPToolError &r_error);
Dictionary set_animation_keyframe_on(AnimationPlayer *p_player, const String &p_animation_name, int64_t p_track_index,
		double p_time, const Variant &p_value, double p_easing, MCPToolError &r_error);
Dictionary remove_animation_on(AnimationPlayer *p_player, const String &p_animation_name, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_animation_write_tools(MCPToolRegistry &r_registry);
