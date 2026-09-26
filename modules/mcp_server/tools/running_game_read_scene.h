/**************************************************************************/
/*  running_game_read_scene.h                                             */
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

// ---------------------------------------------------------------------------
// B1 group `running_game_read_scene` (TASK-009): one tool, `scope = GAME`.
//
// `running_game_find_nearby_nodes` is the only `scope = GAME` tool of B1, which
// is why the direction "a game-only tool must not exist on the editor endpoint"
// is end-to-end observable for the first time here: a game process serves it, an
// editor process registers it but never lists it, and `tools/call` on the editor
// endpoint answers -32601 without executing anything (GDR-19 section 17.3).
//
// Its node tree is the **running game's current scene**
// (`SceneTree::get_current_scene()`), not the scene the editor has open, so it is
// only meaningful in the process that is actually playing a scene. When there is
// no scene loop (a `--test` process) or no main scene is loaded, the tool refuses
// with -32000 and a `data.suggestion` (GDR-14) instead of dereferencing a null
// `SceneTree`.
//
// This pair of files is the only file the owner of this group edits, plus one
// call line in the shared tools/registration.cpp - the per-group split of
// TASK-002 section 2.2.1.
void register_running_game_read_scene_tools(MCPToolRegistry &r_registry);
