/**************************************************************************/
/*  project_autoload_write.h                                              */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/
#pragma once

#include "../tool_registry.h"

#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// TASK-018 section 3, group `project_autoload_write` of
// docs/tool-groups-b3.json: the autoload pair, one `project.godot` key
// (`autoload/<name>`) added and removed.
//
//   project_add_autoload      (old `add_autoload`, project.rs:335)
//   project_remove_autoload   (old `remove_autoload`, project.rs:370)
//
// Both are channel `project`, `scope = both`, `mutating = true`.
//
// The write goes through `MCPTools::publish_project_settings()`
// (`tools/tool_helpers.*`), so `project.godot` is never left truncated: the new
// bytes are produced into `project.mcp-tmp.godot` and the destination is only
// replaced once the engine reported the save. On a failed publish the previous
// in-memory value is put back before the error is answered.
//
// The two testable entry points take the parsed arguments, so a doctest can pin
// the idempotence rules below without a project (they run against the process'
// real `ProjectSettings`, which exists in every build).
namespace MCPTools {

// `{"name","path","key","setting_value","added":true}` plus
// `"already_present":true` when the requested end state already held.
//
// The autoload setting value is `"*" + path` - the `*` prefix is what makes the
// entry a singleton (`project.godot` `[autoload]` `<name>="*res://x.gd"`); the
// migration source wrote the same string (project_commands.gd:357-358).
//
// Idempotence, stated rather than left to be discovered:
//   * the same name with the same path again -> **success**, nothing is written,
//     and `already_present: true` says that this call is not what established it
//     (the same shape `editor_connect_signal` uses for an existing connection);
//   * the same name with a *different* path -> `-32000` with
//     `data.current_value`, because silently replacing an autoload the project
//     already declares is exactly the kind of unannounced change this module
//     refuses (the migration source answered that same refusal,
//     project_commands.gd:351-355);
//   * `path` that is not an existing project file -> `-32001`.
//
// TASK-059 D-4: `p_target_path` is where the setting is published. An empty
// string (the default, and what the tool wrapper passes) means this process' real
// `project.godot`; a doctest passes a file it owns, because the doctest process
// runs against the engine source tree and must never create or write a
// `project.godot` there. The publish itself is section-granular when it can be
// (`tools/tool_helpers.h` lists the four declared fall-backs).
bool add_autoload(const String &p_name, const String &p_path, Dictionary &r_out, MCPToolError &r_error, const String &p_target_path = String());

// `{"name","key","old_path","removed":true}`.
//
// An autoload the project does not declare is `-32001` with a suggestion: the
// caller asked for a removal that did not happen, and the mirror of the
// connect/disconnect rule is that only an existing entry is removed
// (`editor_disconnect_signal`, TASK-015). Removing an existing one clears the
// key, publishes atomically and answers the value the key held.
//
// TASK-059 D-4: this tool **keeps the whole-file writer**, and its description
// says so. `ProjectSettings::update_settings_section_text()` replaces the values
// of the names it is given and never deletes a key
// (`core/config/project_settings.h:226-227`), so a removal cannot be expressed as
// a section publish. `p_target_path` has the same meaning as above.
bool remove_autoload(const String &p_name, Dictionary &r_out, MCPToolError &r_error, const String &p_target_path = String());

} // namespace MCPTools

void register_project_autoload_write_tools(MCPToolRegistry &r_registry);
