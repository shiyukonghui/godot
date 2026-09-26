/**************************************************************************/
/*  running_game_input.h                                                  */
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

// TASK-012 section 1, group `running_game_input` of docs/tool-groups-b2.json:
// the four game-scope tools that record, replay and synthesise input **in the
// running game**.
//
// This is the half of the input family that DECISIONS D56 made non-negotiable:
// `editor_*` input tools act on the editor process' own `Input`/`InputMap`,
// which cannot drive a game, so anything that must move the game's state has to
// be a `scope = game` tool and run inside the game process. Each of the four is
// documented at its implementation, together with the migration source it came
// from and every place where the two migration sources disagreed.
//
// `running_game_play_input_recording` is registered through the GDR-20 deferred
// channel (it replays on a time line); the other three answer inside the frame
// that read the request.
//
// The recorder facility itself (`tools/input_recorder.{h,cpp}`) is the module's
// own replacement for the GDScript autoload the migration source captured input
// with: `running_game_create_input_recording` adds it to the tree root,
// `running_game_stop_input_recording` takes it away again.
void register_running_game_input_tools(MCPToolRegistry &r_registry);
