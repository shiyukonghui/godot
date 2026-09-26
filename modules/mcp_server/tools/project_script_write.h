/**************************************************************************/
/*  project_script_write.h                                                */
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

// TASK-018 section 3, group `project_script_write` of docs/tool-groups-b3.json:
// the project-level script file writes.
//
//   project_create_script   (old `create_script`, script.rs:105)
//   project_edit_script     (old `edit_script`, script.rs:159)
//
// Both are channel `project`, `scope = both`, `mutating = true`. One file,
// because they own one thing together: the `.gd` / `.cs` path guard and the
// atomic publish of a text file that a running editor may be holding open.
//
// **Atomic publish.** The migration source opened the destination and wrote into
// it (`FileAccess.open(path, WRITE)`), so a failure halfway through a longer
// script left a truncated file where the caller's script used to be. Both tools
// here go through `MCPTools::publish_file_atomically()` - the same helper the
// resource and scene writers use - so the bytes are produced into
// `<name>.mcp-tmp.gd` and the destination is only replaced once the temporary
// file really exists. An `edit` that fails therefore leaves the original script
// byte-for-byte untouched (proved by sha256 in REPORT-018).
//
// The two testable entry points take the arguments and do the whole job, so the
// group's doctests can pin the template grammar, the search/replace rules and
// the refusals without an HTTP client.
namespace MCPTools {

// The GDScript template `project_create_script` produces when `content` is
// absent, for the `template` base class the caller named. Published (rather than
// file-private) because the doctest asserts the exact bytes, including the
// trailing newline the migration source's `"\n".join(...)` produced.
String script_template_body(const String &p_base_class);

// `path` (required, must end in `.gd` or `.cs`), `content` (optional), `template`
// (optional, default `Node`). An existing file is *replaced* - the migration
// source's behaviour - and the answer says so (`existed_before: true`), so the
// caller is never left guessing whether a script was overwritten.
// Answer: `{"path","created","existed_before","bytes","template"}`.
bool create_script(const String &p_path, bool p_has_content, const String &p_content, const String &p_template,
		Dictionary &r_out, MCPToolError &r_error);

// `path` (required, must exist, must end in `.gd` or `.cs`) and exactly one mode:
//   * `content` (string) - replace the whole file; or
//   * `search` (string, non-empty) + `replace` (string, optional, default empty)
//     - replace **every** occurrence, which is what the migration source's
//     `content.replace(search, replace)` did (script_commands.gd:204-206).
//
// Supplying both modes at once, or neither, is `-32602`: guessing which one the
// caller meant is how a "search and replace" silently becomes "overwrite the
// file". A `search` that matches nothing is `-32001`, because the caller asked
// for a change that did not happen (the migration source answered
// `{"changes_made": 0}` as a success, script_commands.gd:249-250).
// Answer: `{"path","changes_made","mode","replacements","bytes"}`.
bool edit_script(const String &p_path, bool p_has_content, const String &p_content, bool p_has_search,
		const String &p_search, bool p_has_replace, const String &p_replace,
		Dictionary &r_out, MCPToolError &r_error);

} // namespace MCPTools

void register_project_script_write_tools(MCPToolRegistry &r_registry);
