/**************************************************************************/
/*  running_game_capture.h                                                */
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

// TASK-011 section 2, group `running_game_capture` of
// docs/tool-groups-b2.json: the single-shot viewport readback of the running
// game.
//
// It is one capability with `running_game_capture_frames` (which sits in
// `running_game_frame_observation`) and is split from it by GDR-18, not by a
// dependency: an optional `save_path` can write into the project, so
// `running_game_capture_screenshot` is `mutating = true` while the frames tool
// stays `mutating = false`, and one group may only carry one of those values.
// The two groups share the framebuffer helpers through
// `tools/tool_helpers.{h,cpp}`.
//
// Unlike the other three tools of TASK-011 this one needs no cross-frame
// mechanism: the migration source only spanned frames because the picture
// travelled through the `user://mcp_screenshot.png` file IPC, and inside the game
// process there is no IPC left to wait for. It is therefore registered as an
// ordinary immediate tool.
//
// `scope = game` (docs/tool-rename-map.json), so it is served by the game
// endpoint (9889) and refused with `-32601` by the editor endpoint.
void register_running_game_capture_tools(MCPToolRegistry &r_registry);
