/**************************************************************************/
/*  project_validate_scripts.h                                            */
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

#include "../tool_registry.h"

// The `ADDED` group `project_validate_scripts` (docs/tool-groups-added.json),
// the first half of C-4 section 3 of REPORT-AUDIT-RACING-BACKLOG:
//
//   project_validate_scripts   (TASK-053 section 2.1)
//
// One channel (`project`), one verb (`validate`, already in the rename map's
// closed set), `scope = BOTH`, `mutating = false`: it only reads files. Its name,
// description and `inputSchema` are authored by the decision maker in
// `ADDED_TOOLS` of `scripts/gen_renamed_contract.py`; this file copies the
// contract entry verbatim, exactly like the TASK-052 added group does.
void register_project_validate_scripts_tools(MCPToolRegistry &r_registry);

namespace MCPTools {

// ---------------------------------------------------------------------------
// The bound of a bulk answer.
//
// The tools of this module that can answer an unbounded number of items always
// carry an explicit cap and an explicit truncation marker
// (`project_read_resource`'s `truncated`/`dropped`/`limits` is the precedent);
// a "validate all scripts" answer must not be the one place where the response
// size is a function of the project the caller happens to have. The number is a
// *count of files*, and the marker says exactly how many were left out - it is
// never a silent cut.
// ---------------------------------------------------------------------------
int max_validated_scripts();

// The three-key marker of a truncated answer, shared with the readers' shape.
Dictionary validation_limits();

// Cuts `p_text` to at most `p_max_bytes` **UTF-8 bytes** on a character
// boundary and appends a marker that names the original size. A text that fits
// is returned unchanged, byte for byte.
//
// The rule is byte based on purpose: every other length this module publishes is
// a UTF-8 byte count (PLAYBOOK section 6, item 9), and a marker that counted
// characters would disagree with the `bytes` fields next to it. The cut is moved
// back to a boundary so the result is always valid UTF-8.
String truncate_marked(const String &p_text, int p_max_bytes);

// The whole tool, minus the argument-envelope handling: `p_paths_given` false
// means "scan the project", which is what an omitted `paths` asks for. Fills
// `r_out` and answers `false` with `r_error` set on a refusal.
//
// Argument refusals are **whole-call** refusals and happen before any file is
// read (an out-of-project path is `-32602`, a path that is not there is
// `-32001`, both naming the entry). That is deliberate: the categories of a
// per-file verdict (`ok` / `invalid` / `not_compiled` / `language_unavailable` /
// `unverifiable`) have to account for every file that *was* classified, and
// "there is no such file" is a property of the request, not a verdict about a
// script. Only `ok` and `invalid` carry a boolean `valid`; the other three
// publish `valid: null` plus a `reason` (TASK-056 D1).
bool validate_scripts(const Array &p_paths, bool p_paths_given, bool p_include_errors_only,
		Dictionary &r_out, MCPToolError &r_error);

} // namespace MCPTools
