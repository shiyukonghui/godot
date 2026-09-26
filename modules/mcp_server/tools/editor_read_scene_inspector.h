/**************************************************************************/
/*  editor_read_scene_inspector.h                                         */
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

class Node;

// B1 group `editor_read_scene_inspector` (the manifest is docs/tool-groups.json):
//
//   editor_get_errors               (migrated from editor.rs:270)
//   editor_get_output_log           (migrated from editor.rs:290)
//   editor_get_open_scripts         (migrated from script.rs:137)
//   editor_get_scene_tree           (migrated from scene.rs:109)
//   editor_get_selection            (migrated from node.rs:625)
//   editor_get_viewport_3d_camera   (migrated from editor.rs:630)
//   editor_analyze_signal_flow      (migrated from analysis.rs:387)
//
// All seven are channel `editor`, `mutating = false` and - for the first time in
// this port - `scope = EDITOR`. That scope is not cosmetic: a game process must
// not even *carry* these tools in its registry table, so `ToolBuilder` skips them
// at registration and no later filtering is what hides them (GDR-19 section 17.3).
//
// Editor-only engine APIs are wrapped in `MCP_EDITOR_TOOLS_ENABLED` at compile
// time (defined in tools/tool_builder.h) and their singletons are null-checked at
// run time: in a process where `EditorInterface` exists but `EditorNode` does not
// (`--test`, or any tools build without a running editor) the tools answer with
// -32000 instead of dereferencing a null `EditorNode::get_singleton()`.
void register_editor_read_scene_inspector_tools(MCPToolRegistry &r_registry);

namespace MCPTools {

// The `tree` payload of `editor_get_scene_tree` for one root (TASK-027 E-2).
//
// Exported because the path rule it implements - `path` relative to the root
// (`"."` for the root itself), `absolute_path` the engine's own `get_path()` - is
// the whole point of the task and a doctest can pin it against a bare node tree:
// the doctest process has no `SceneTree`, so the tool itself can only ever answer
// its `-32000` guard, while `get_path_to()` works on an unattached tree.
Dictionary scene_tree_of(Node *p_root, int64_t p_max_depth);

} // namespace MCPTools

