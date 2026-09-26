/**************************************************************************/
/*  running_game_frame_observation.h                                      */
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

// TASK-011 section 2, group `running_game_frame_observation` of
// docs/tool-groups-b2.json: the three game-scope reads whose observable
// behaviour is the passage of frames.
//
// The group is the reason GDR-20 exists. In the module's original model a tool
// ran synchronously inside one frame (`MCPServer::pump_frame` ->
// `MCPHttpServer::poll` -> handler), so `running_game_get_node_property_samples`
// returned N copies of one observation - TASK-010 recorded exactly that as the
// minimal counterexample - and it therefore stayed unregistered (GDR-7: never
// register what does not work). All three tools now return a
// `MCPDeferred::Task` instead of a result and are driven by the transport once
// per frame. See REPORT-011 for the state machine proof and the wire evidence.
//
// Every tool is `scope = game` (docs/tool-rename-map.json), so it is served by
// the game endpoint (9889) and refused with `-32601` by the editor endpoint.
void register_running_game_frame_observation_tools(MCPToolRegistry &r_registry);

namespace MCPTools {

// ---------------------------------------------------------------------------
// TASK-053 section 2.3 (M-5): the one rule of the new `sample_stride` parameter
// of `running_game_get_node_property_samples`, exported because it is the whole
// decision and the process it runs in (a live game with a SceneTree) is not the
// process a doctest has.
//
// An observation at series index `p_index` (0 based, in the order the frames
// were actually observed) is returned when `p_index` is a multiple of the
// stride; index 0 is therefore always returned, whatever the stride. A stride of
// 1 (or less, which the argument validation refuses) returns every observation.
// ---------------------------------------------------------------------------
bool sample_is_returned(int p_index, int p_stride);

} // namespace MCPTools
