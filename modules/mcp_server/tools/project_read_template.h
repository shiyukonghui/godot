/**************************************************************************/
/*  project_read_template.h                                               */
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

// B1 group `project_read_template` (the manifest is docs/tool-groups.json):
//
//   project_get_info                      (migrated from the M1 tools/project.cpp)
//   project_get_settings                  (migrated from the M1 tools/project.cpp)
//   project_get_filesystem_tree           (new in B1)
//   project_search_file_names             (new in B1)
//   project_search_file_contents          (new in B1)
//   project_find_files_referencing_symbol (new in B1, the de-merged twin)
//
// All six are channel `project`, `mutating = false`, `scope = both`.
//
// This pair of files is the only file the owner of this group edits, plus one
// call line in the shared tools/registration.cpp - which is the whole point of
// the per-group split (TASK-002 section 2.2.1): parallel porting agents never
// touch the same file.
void register_project_read_template_tools(MCPToolRegistry &r_registry);