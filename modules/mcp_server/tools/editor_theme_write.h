/**************************************************************************/
/*  editor_theme_write.h                                                  */
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

#include "tool_builder.h"

// Only ever used through a pointer here; forward declared so this header does
// not drag `scene/` into every translation unit that includes it.
class Node;

// ---------------------------------------------------------------------------
// TASK-034 (B5 batch 2): the `editor_theme_write` group (1 tool).
//
// `editor_set_control_theme` is `Control::set_theme(const Ref<Theme> &)`
// (`scene/gui/control.h:801`) with `Control::get_theme()` (:802) as the read-back.
// There is no other engine call in it - the whole tool is the three decisions
// around that pair:
//
//   * the node has to be a `Control` (the migration source checked it, and that
//     check is the one thing it got right - `theme.rs:257-261`);
//   * an omitted/empty `theme_path` **clears** the Control's own theme instead of
//     doing nothing while reporting success - the migration source answered
//     `theme_applied: true` without touching anything (`theme.rs:264-271`), which
//     is PLAYBOOK section 6.6's "nothing happened, reported as done";
//   * the value written is read back, and the answer carries the `{type, path}`
//     shape of the theme that is really on the node (GDR-25 section 23.5).
//
// The engine's own model is the design basis (GDR-23); the engine reference is
// in the `.cpp` beside the entry point and in REPORT-034.
// ---------------------------------------------------------------------------

namespace MCPTools {

// Applies `p_theme_path` to the Control at `p_node_path` in the edited scene, or
// clears the Control's theme when `p_theme_path_given` is false / the path is
// empty. The answer carries the read-back (`theme`) plus `cleared` so the two
// halves are never confused.
Dictionary set_control_theme_on(Node *p_root, const String &p_node_path, const String &p_theme_path,
		bool p_theme_path_given, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_theme_write_tools(MCPToolRegistry &r_registry);
