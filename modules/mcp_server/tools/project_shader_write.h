/**************************************************************************/
/*  project_shader_write.h                                                */
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

// ---------------------------------------------------------------------------
// TASK-035 (B5 batch 3): the `project_shader_write` group (2 tools).
//
// The engine's model (GDR-23): a shader is a text file with a **mode directive**
// as its first statement (`shader_type spatial;`, `shader_type canvas_item;`,
// `particles`, `sky`, `fog` - `Shader::Mode`, `scene/resources/shader.h:45-51`),
// and the file is written through `FileAccess` (there is no engine "create
// shader" API; the migration source opened the path directly,
// `godot_mcp_gdext/src/commands/shader.rs:72`). `/`
//
// Differences from the migration source, each with a reason:
//
//   * the path is normalised (`res://a/./b` -> `res://a/b`) and must name a
//     `.gdshader` file, so the shader writer can never be used to overwrite a
//     scene or a script;
//   * the write is published **atomically** (`publish_text_atomically`), so a
//     failing write cannot truncate an existing shader;
//   * `shader_type` is validated against the engine's five modes instead of being
//     pasted into the file, and a bare mode name (`"canvas_item"`) is accepted as
//     the directive's argument - the migration source's `format!("{}\n\nvoid
//     fragment() {{}}\n", stype)` produced a `void fragment()` for **every**
//     mode, which does not compile for `sky`/`fog`/`particles` (their entry
//     points are `sky()`/`fog()`/`start()`+`process()`), so the generated body is
//     only added where `fragment()` is a real entry point;
//   * `project_edit_shader` validates the mode of the code it is about to write
//     (when it declares one) and refuses before the file is touched;
//   * the answer reports the real byte size of the published file (UTF-8 bytes,
//     PLAYBOOK section 6.9) - the migration source reported the *character* count
//     of the string it had in memory.
// ---------------------------------------------------------------------------

namespace MCPTools {

// Creates (or replaces) a `.gdshader` at `p_path` from the mode directive
// `p_shader_type`. `r_out` is the tool answer.
bool create_shader_file(const String &p_path, const String &p_shader_type, Dictionary &r_out,
		MCPToolError &r_error);

// Replaces the whole code of an existing `.gdshader`.
bool edit_shader_file(const String &p_path, const String &p_code, Dictionary &r_out, MCPToolError &r_error);

// `shader_template()` and `shader_code_mode()` - the mode vocabulary this group
// shares with the reader - live in `tools/shader_shared.h`, together with the
// rest of the family's engine-facing vocabulary.

} // namespace MCPTools

void register_project_shader_write_tools(MCPToolRegistry &r_registry);
