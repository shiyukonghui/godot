/**************************************************************************/
/*  editor_particle_read.h                                                */
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
// TASK-034 (B5 batch 2): the `editor_particle_read` group (1 tool).
//
// `editor_get_particle_info` answers one particle system in the shapes the write
// tools of the same batch take back (GDR-25 section 23.4): the node's own
// simulation members, the process material's curated parameter set, and the
// `color_ramp` stops as `[{offset, color}]`. The migration source answered the
// material as `to_string()` spellings (`particle.rs:417-442`: `direction` and
// `gravity` were printed as `"(x, y, z)"` strings), which is exactly the string
// surgery section 23.1 forbids - a read value could not be fed into any tool.
//
// The engine's own model is the design basis (GDR-23); the engine reference is
// in the `.cpp` beside the entry point and in REPORT-034.
// ---------------------------------------------------------------------------

namespace MCPTools {

// The whole answer of `editor_get_particle_info` for the particle system at
// `p_node_path` (see the `.cpp` for the field-by-field engine reference).
Dictionary particle_info_on(Node *p_root, const String &p_node_path, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_particle_read_tools(MCPToolRegistry &r_registry);
