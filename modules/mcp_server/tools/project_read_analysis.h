/**************************************************************************/
/*  project_read_analysis.h                                               */
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

// B1 group `project_read_analysis` (the manifest is docs/tool-groups.json):
//
//   project_get_statistics                (migrated from analysis.rs:562)
//   project_analyze_scene_complexity      (migrated from analysis.rs:414)
//   project_detect_circular_dependencies  (migrated from analysis.rs:520)
//   project_find_unused_resources         (migrated from analysis.rs:336)
//   project_find_script_references        (migrated from analysis.rs:485)
//   project_get_scene_dependencies        (migrated from batch.rs:519)
//   project_get_scene_exports             (migrated from scene.rs:344)
//
// All seven are channel `project`, `mutating = false`, `scope = BOTH`, and they
// only ever read the project on disk: no tool of this group may create, modify
// or delete a file (pinned by the doctest "the analysis tools never write to
// the project").
//
// This pair of files is the only file the owner of this group edits, plus one
// call line in the shared tools/registration.cpp - which is the whole point of
// the per-group split (TASK-002 section 2.2.1): porting agents never touch the
// same file (PLAYBOOK section 17.1).
void register_project_read_analysis_tools(MCPToolRegistry &r_registry);