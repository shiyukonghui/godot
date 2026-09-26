/**************************************************************************/
/*  project_text_write.h                                                  */
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
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
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

#include "tool_builder.h"

// ---------------------------------------------------------------------------
// TASK-052 (C tier batch 1, DESIGN-DETAIL.md section 26 / GDR-28): the first
// *added* group - `project_write_text_file`, one tool.
//
// The gap it closes (N-3 of REPORT-AUDIT-RACING-BACKLOG): the 171 ported writers
// cover scenes, resources, scripts, shaders, themes and `project.godot`, but not
// the plain project text file a C# project or a tool configuration needs
// (`.csproj`, `.sln`, `NuGet.config`, `.cfg`). Where a dedicated writer exists,
// this tool **points at it** instead of doing the same job a second, weaker way:
//
//   * `project.godot`          -> `project_set_setting` (the engine's own
//     `ProjectSettings::save_custom()` publish, which no caller should bypass by
//     writing the settings file as text);
//   * `.tscn` / `.tres`        -> `project_create_scene_file` /
//     `project_create_resource` / `project_edit_resource`;
//   * `.gd` / `.cs`            -> `project_create_script` / `project_edit_script`.
//
// The two halves of the refusal rule are the ones the module already uses for a
// destination path: only `res://`, no `..` (`normalize_project_path`, the same
// family `normalize_screenshot_path` belongs to), and the path has to name a
// file rather than a directory.
//
// The write itself is `publish_text_atomically` - the hoisted backup + rename
// publish of `publish_file_atomically`: the bytes go into a `*.mcp-tmp.*` sibling
// first and the destination is only replaced once the temporary file is really
// there, with the previous bytes copied aside and restored if the publish step
// fails. The answer is built from a **read-back** of the file that is on disk
// now (its byte size and its sha256), never from the string that was meant to be
// written.
//
// There is deliberately **no delete path**: the tool's schema has exactly three
// members, it never opens a file for removal, and `overwrite: false` (the
// default) turns an occupied destination into a refusal instead of a silent
// replacement.
// ---------------------------------------------------------------------------

namespace MCPTools {

// Writes `p_content` to the project text file `p_path`.
//
// Refusals (`-32602`, each with a `data.suggestion` that names the dedicated
// tool where one exists): a path outside `res://`, a `..` segment, a path that
// names a directory, `project.godot`, and the four extensions of the resource
// and script families.
//
// Refusal (`-32001`, with a `data.suggestion` naming `overwrite`): the
// destination exists and `p_overwrite` is false. The file's bytes are untouched
// in that case.
//
// On success `r_out` is `{path, bytes, sha256, created}` - `bytes` and `sha256`
// describe the file that is on disk after the publish.
bool write_project_text_file(const String &p_path, const String &p_content, bool p_overwrite,
		Dictionary &r_out, MCPToolError &r_error);

} // namespace MCPTools

void register_project_text_write_tools(MCPToolRegistry &r_registry);
