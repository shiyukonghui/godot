/**************************************************************************/
/*  editor_testing_read.h                                                 */
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

// TASK-019 section 1, group `editor_testing_read` of `docs/tool-groups-b4.json`:
// the editor process' two windows onto test artefacts.
//
// The group is the B4 batch's editor half and its members are two different
// sources of truth, deliberately in one file because the manifest puts them
// there and because both are read-only, editor-scope and non-mutating:
//
//   * `editor_get_test_report` reads the **in-process assertion accumulator**
//     (`MCPTools::build_test_report`, `tools/tool_helpers.{h,cpp}`). It is the
//     batch's `fix_implementation_first` entry: the migration source answered a
//     hard-coded message string built by a GDScript `Expression` and collected
//     nothing at all (`godot_mcp_gdext/src/commands/test.rs:561-589`). An
//     implementation that keeps that shape would be a *fabricated success*, so
//     the report is built from what really ran and an empty accumulator is
//     reported as `no_results: true`;
//   * `editor_analyze_screenshot_diff` compares two PNGs pixel by pixel and
//     returns the difference image. The migration source did it by generating a
//     GDScript `Expression` that encoded both arguments *into source text*
//     (`editor.rs:512-607`, `escaped_a` / `escaped_b` interpolated into a
//     `load_img("...")` call). Inside the engine the two images are loaded
//     directly, so no caller-controlled text ever reaches a parser.
//
// Both are `scope = editor` (docs/tool-rename-map.json), so both are served by
// the editor endpoint (9888) and refused with `-32601` by the game endpoint.
void register_editor_testing_read_tools(MCPToolRegistry &r_registry);
