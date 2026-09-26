/**************************************************************************/
/*  project_shader_read.h                                                 */
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
// TASK-035 (B5 batch 3): the `project_shader_read` group (2 tools).
//
//   * `project_read_shader` reads the file's **text** through the engine's
//     `FileAccess` path (`MCPTools::read_project_text_file`), reports the UTF-8
//     byte size (PLAYBOOK section 6.9 - the migration source reported
//     `code.len()`, a *Rust* byte count of the string it had in memory, which is
//     the same number only for valid UTF-8 with no re-encoding) and names the mode
//     the file declares.
//   * `project_get_shader_params` lists the **engine's own** uniform list
//     (`Shader::get_shader_uniform_list`, `scene/resources/shader.cpp:150`)
//     instead of the migration source's GDScript `Expression` that walked
//     `get_property_list()` and stripped a `shader_parameter/` prefix by hand
//     (`godot_mcp_gdext/src/commands/shader.rs:149-157`). The names are the bare
//     parameter names `ShaderMaterial::set_shader_parameter` takes, so a name
//     answered here is directly feedable into `editor_set_shader_param`
//     (GDR-25 section 23.1).
// ---------------------------------------------------------------------------

namespace MCPTools {

// The text of the shader file at `p_path`.
bool read_shader_file(const String &p_path, Dictionary &r_out, MCPToolError &r_error);

// The shader's uniform list, as `{path, shader_type, param_count, params[]}` where
// each parameter is `{name, type, type_id, hint, hint_string}`.
bool shader_params_of(const String &p_path, Dictionary &r_out, MCPToolError &r_error);

} // namespace MCPTools

void register_project_shader_read_tools(MCPToolRegistry &r_registry);
