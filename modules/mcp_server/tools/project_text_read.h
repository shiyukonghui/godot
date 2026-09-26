/**************************************************************************/
/*  project_text_read.h                                                   */
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

#include "core/string/ustring.h"
#include "core/typedefs.h"
#include "core/variant/variant.h"

// The `ADDED` group `project_text_read` (docs/tool-groups-added.json):
//
//   project_read_text_file   (TASK-075 section 2)
//
// The symmetric half of `project_write_text_file`: the 171 ported readers cover
// scripts, scenes, resources and shaders, and the module's own added writer
// publishes a plain project text file, but nothing could read one back - so the
// round-5 test's "write a JSON file, read it back and verify its sha256 with a
// tool" could only be closed with an OS hash call (PLATFORMER-FINDINGS D3 /
// section 0.6 (8)). One channel (`project`), one verb (`read`, already in the
// rename map's closed set), `scope = BOTH` like every other `project_read_*`
// tool, `mutating = false`.
void register_project_text_read_tools(MCPToolRegistry &r_registry);

namespace MCPTools {

// ---------------------------------------------------------------------------
// TASK-075: the two pure predicates the tool is built from. They are exported
// because the doctest process cannot reach a live editor and because both are
// decisions about *bytes*, which is exactly the kind of rule this module keeps
// in one testable place.
// ---------------------------------------------------------------------------

// True only for a byte sequence that is well-formed UTF-8: no overlong form, no
// surrogate, no code point above U+10FFFF and no truncated sequence. Godot's
// `String::utf8()` does **not** validate (it decodes what it can and keeps going),
// so a reader that answered `text` for arbitrary bytes would silently return a
// string that is not the file's content. Written out rather than borrowed because
// this fork has no `String::is_valid_utf8()`.
bool utf8_bytes_are_valid(const uint8_t *p_bytes, int64_t p_size);

// The omission reason of the `max_bytes` case, in one place so the response text
// and the doctest cannot drift. `p_size` is the whole file, `p_max_bytes` the
// caller's budget.
String text_omission_reason(int64_t p_size, int64_t p_max_bytes);

} // namespace MCPTools
