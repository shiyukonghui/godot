/**************************************************************************/
/*  editor_write_scene_editor.h                                           */
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

// B1 group `editor_write_scene_editor` (the manifest is docs/tool-groups.json):
//
//   editor_open_scene                     (migrated from scene.rs:117)
//   editor_save_scene                     (migrated from scene.rs:151)
//   editor_reload_plugin                  (migrated from editor.rs:430)
//   editor_rescan_project_filesystem      (migrated from editor.rs:445)
//   editor_set_node_selection             (migrated from node.rs:651)
//   editor_remove_node_selection          (migrated from node.rs:722)
//   editor_add_resource_to_node_property  (migrated from node.rs:365)
//   editor_set_viewport_3d_camera         (migrated from editor.rs:635)
//   editor_capture_screenshot             (migrated from editor.rs:306)
//   editor_remove_output_log              (migrated from editor.rs:421, fix-first)
//
// Every tool of this group is `scope = editor` and `mutating = true`
// (docs/tool-rename-map.json), so all ten are guarded by
// `MCP_EDITOR_TOOLS_ENABLED`, are registered only in an editor process, and a
// game process must answer `-32601` without executing anything.
//
// The invariants this file owns, beyond "the call returned the right JSON"
// (TASK-008):
//
//   1. **`editor_remove_output_log` never reports a success it did not
//      perform.** The migration source only printed blank lines to stdout and
//      answered `{"cleared": true}` while the Output panel kept every message
//      (`editor.rs:421-425`). This implementation refuses with `-32000` when
//      there is no editor log to clear and, when there is one, calls the very
//      operation the panel's *Clear* button calls and reports the measured
//      before/after state of the panel.
//   2. **the two file writers publish atomically**: `editor_save_scene` and
//      `editor_capture_screenshot` (with a `save_path`) write through the shared
//      `MCPTools::publish_file_atomically` helper, so a failure never truncates
//      or damages an existing file.
//   3. **state changes are observable**: a tool that mutates editor state is
//      paired with a reading tool of the `editor_read_scene_inspector` group
//      (`editor_get_scene_tree` / `editor_get_selection` /
//      `editor_get_viewport_3d_camera`) in the report's evidence chain.
//
// This pair of files is the only file the owner of this group edits, plus one
// include and one call line in the shared tools/registration.cpp (TASK-002
// section 2.2.1: porting agents never touch the same file, PLAYBOOK section
// 17.1).
void register_editor_write_scene_editor_tools(MCPToolRegistry &r_registry);

namespace MCPTools {

// An optional `{x, y, z}` object of `editor_set_viewport_3d_camera`, with every
// present component pushed through `MCPTools::value_fits_slot` **before** the
// `Vector3` is built (TASK-023 D-7 / GDR-24). `r_present` distinguishes
// "absent" from "present but zero", which is why it is an out-parameter.
//
// Declared here for the reason `running_game_node_write.h`'s helpers are: the
// doctest binary cannot build an editor viewport, so the *value* half of the
// tool has to be assertable on its own. The defect this guards was a silent
// `inf` next to a `code=0`, and only a direct assertion pins the refusal.
//
// Returns false and fills `r_error` with a `-32602` naming the offending
// component (`position.x`) when a component is not a number or does not fit the
// 32-bit slot; a `{}` object (every component absent) is accepted and answers
// `Vector3(0, 0, 0)`, which is the migration source's `unwrap_or(0.0)`.
bool vector3_from_json(const Dictionary &p_args, const String &p_key, bool &r_present, Vector3 &r_out, MCPToolError &r_error);

} // namespace MCPTools
