/**************************************************************************/
/*  project_resource_uid_read.h                                           */
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

// TASK-018 section 3, group `project_resource_uid_read` of
// docs/tool-groups-b3.json: the two resource-identity reads of B3.
//
//   project_convert_path_to_uid   (old `project_path_to_uid`, project.rs)
//   project_convert_uid_to_path   (old `uid_to_project_path`, project.rs)
//
// Both are channel `project`, `scope = both`, `mutating = false`. They are one
// file because they are one capability read in two directions, and because the
// two *names* are the batched pair this task has to disambiguate: the token sets
// are identical and only their order differs (`path_to_uid` vs `uid_to_path`).
//
// The two testable entry points below take the text the caller sent and are the
// whole tool minus argument reading, so a doctest (which has no project) can pin
// the format rules and the refusal codes of both directions.
namespace MCPTools {

// `{"path": <normalized>, "uid": <text or "">}`.
//
// `path` is normalized first (`res://a/./b` -> `res://a/b`, PLAYBOOK section 6.7)
// and must address the project; a path that does not exist is `-32001`. A path
// that exists but has no UID assigned answers the empty string **as a success**,
// which is what the renamed contract says
// ("路径未注册时 uid 为空串且不报错") and what the migration source did not do
// (it answered `-32001` for that case, project_commands.gd:243-244).
bool convert_path_to_uid(const String &p_path, Dictionary &r_out, MCPToolError &r_error);

// `{"uid": <the text as sent>, "path": <the registered path>}`.
//
// The text must be a well-formed `uid://...` (otherwise `-32602`, the contract's
// "UID 文本格式非法时报参数错误") and must be registered (`-32001` otherwise).
bool convert_uid_to_path(const String &p_uid, Dictionary &r_out, MCPToolError &r_error);

} // namespace MCPTools

void register_project_resource_uid_read_tools(MCPToolRegistry &r_registry);
