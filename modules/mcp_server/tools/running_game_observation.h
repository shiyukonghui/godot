/**************************************************************************/
/*  running_game_observation.h                                            */
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

#include "core/string/string_name.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"

// `Node` is only ever used through a pointer by the helper below, so the engine
// scene class is forward declared instead of dragging `scene/` into every
// translation unit that includes this header.
class Node;

// ---------------------------------------------------------------------------
// TASK-040 D-3: the named-property reader of the game-side family, exported.
//
// `running_game_get_node_properties` (and the `properties` filter of its batch,
// autoload and find-by-script siblings) answered `null` for a name the node does
// not have, while `running_game_set_node_property` answered `-32001 Property
// '<name>' ... not found` for the very same name on the very same endpoint
// (RACING-FINDINGS section 4 D-3). This is the one definition of the named read:
//
//   * a name that is an inspector *label* (a group/category entry, e.g.
//     `Material`) is skipped - the TASK-032 D3 rule, kept;
//   * a name the node really has is read through `serialize_variant` and put
//     into `r_out` under the caller's own spelling;
//   * a name the node does not have is `-32001` naming it, with
//     `data.suggestion` (TASK-040 D-3), and the call fails instead of writing a
//     `null` into `r_out`.
//
// Exported because the doctest process has no `SceneTree`: this function is what
// the tool *calls*, so a case can pin the rule against a bare `Node`.
// ---------------------------------------------------------------------------
namespace MCPTools {
bool read_named_properties(Node *p_node, const Vector<String> &p_names, Dictionary &r_out, MCPToolError &r_error);
} // namespace MCPTools

// TASK-010 section 2, group `running_game_observation` of
// docs/tool-groups-b2.json: the six read-only game-side observers.
//
// Every tool of the group is `scope = game` (docs/tool-rename-map.json), so it is
// served by the game endpoint (9889) and hidden - and refused with `-32601` - by
// the editor endpoint (9888). `ToolBuilder::register_into()` does not skip
// `scope = GAME` tools in an editor process (only `scope = EDITOR` tools are
// skipped in a game process), so the registry carries them in both and the scope
// filter decides what a `tools/list` shows.
//
// Notice what is *not* here: `running_game_get_node_property_samples`,
// `running_game_find_node_when_available` and `running_game_capture_frames` live
// in the `running_game_frame_observation` group of the manifest and are
// deliberately not registered. They need the game to advance frames between two
// observations, and a tool in this module runs synchronously inside one frame
// (MCPServer::pump_frame -> MCPHttpServer::poll -> handler). Registering them
// without that mechanism would be a tool that answers a lie (GDR-7). See
// REPORT-010 section "manifest 与组划分理由".
void register_running_game_observation_tools(MCPToolRegistry &r_registry);
