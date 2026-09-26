/**************************************************************************/
/*  project_setting_write.h                                               */
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

// TASK-018 section 3, group `project_setting_write` of docs/tool-groups-b3.json:
// the one general `ProjectSettings` write.
//
//   project_set_setting   (old `set_project_setting`, project.rs:173)
//
// channel `project`, `scope = both`, `mutating = true`. It is alone because it
// is the only tool that may write an arbitrary key.
//
// Two things the migration source did not do, and this one does:
//
//   1. **Type fidelity.** The engine already knows the declared type of every
//      setting it has (`ProjectSettings::_get_property_list()`), so the value is
//      coerced against that type exactly like a node property is: an integral
//      JSON number reaches an `int` setting as an `int`, `"Vector2(1,2)"` and
//      `{"x":1,"y":2}` reach a `Vector2` setting as one, `"#ff0000"` reaches a
//      `Color`, and a value that cannot fall into the declared type is `-32602`
//      with the target type and the offending value named (TASK-018 section 1,
//      through `coerce_to_property_type`). The migration source ran an
//      `Expression` over the string and otherwise stored whatever arrived, so
//      `1e20` into an `int` setting was a different integer, not an error.
//      The optional `type` argument names the target type explicitly for a key
//      the project does not have yet, and is *checked* against the declared type
//      when the key does exist (a mismatch is `-32602`).
//   2. **Existence is reported, not hidden.** A key the project does not declare
//      is a legitimate thing to create (games define their own settings), so the
//      call is allowed - and the answer says `existed_before: false` plus
//      `created: true`, so the caller can tell "I changed a setting" from "I
//      invented a key that nothing reads".
//
// The write itself goes through `MCPTools::publish_project_settings()`
// (`tools/tool_helpers.*`): the new `project.godot` is produced into
// `project.mcp-tmp.godot` and the destination is replaced only after the engine
// reported the save, with the previous in-memory value restored on failure.
namespace MCPTools {

// The accepted spellings of the optional `type` argument, as
// `Variant::get_type_name()` spellings. Returns `Variant::VARIANT_MAX` and fills
// `r_error` when the name is not one this tool can write.
Variant::Type variant_type_from_name(const String &p_name);

// `{"key","value","type","existed_before","created","saved":true}`.
bool set_project_setting(const String &p_key, const Variant &p_raw_value, bool p_has_type, const String &p_type_name,
		Dictionary &r_out, MCPToolError &r_error);

} // namespace MCPTools

void register_project_setting_write_tools(MCPToolRegistry &r_registry);
