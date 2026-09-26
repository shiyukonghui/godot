/**************************************************************************/
/*  project_resource_uid_read.cpp                                         */
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
#include "project_resource_uid_read.h"

#include "tool_builder.h"

#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/io/resource_loader.h"
#include "core/io/resource_uid.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// The two resource-identity reads, and the direction problem of their names.
//
// The two *names* are the exact reverse of each other's token order and share
// every token
//       `project_convert_path_to_uid`  vs  `project_convert_uid_to_path`
// so any reader (human or model) that pattern-matches on the token set instead
// of reading the order can pick the wrong one. The renamed contract answers that
// question *inside the description*, with an explicit discriminator sentence in
// both entries:
//
//   project_convert_path_to_uid: "将项目路径转换为 UID 判别点：入参为项目路径
//     （如 res://...），返回 {path,uid}，路径未注册时 uid 为空串且不报错；"
//     "反向转换请用 project_convert_uid_to_path。"
//   project_convert_uid_to_path: "将 UID 转换为项目路径 判别点：入参为字符串文本
//     UID（如 uid://...），返回 {uid,path}，UID 文本格式非法时报参数错误；"
//     "反向转换请用 project_convert_path_to_uid。"
//
// Three independent signals therefore agree, and the implementation makes all
// three observable:
//   1. the argument name (`path` vs `uid`) - the schema of each tool has exactly
//      one property, and its name is the direction;
//   2. the *shape* of the argument (a `res://` path vs a `uid://` text) - each
//      direction refuses the other direction's spelling (`-32001` / `-32602`,
//      see below), so a swapped call is a loud failure, never a mapping;
//   3. the *keys* of the answer (`{path,uid}` vs `{uid,path}`).
//
// The "silently wrong mapping" the task asks to contrast against is what a
// *swapped implementation* would produce: an echo. `uid_to_path` implemented as
// "answer the input under the `path` key" answers `{"uid":"uid://abc",
// "path":"uid://abc"}` - a mapping whose `uid` field is not even a UID and whose
// `path` field is not a `res://` path. The REPORT-018 evidence run records that
// contrast next to the live calls, and the two machine-checkable rules it uses
// are: `path_to_uid` must never answer a `uid` that does not begin with
// `uid://`, and `uid_to_path` must never answer a `path` that does not begin
// with `res://`.
// ---------------------------------------------------------------------------

namespace MCPTools {

bool convert_path_to_uid(const String &p_path, Dictionary &r_out, MCPToolError &r_error) {
	String path;
	if (!normalize_project_path(p_path, path, r_error)) {
		return false;
	}
	if (path == "res://") {
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'path' must name a resource, got the project root '%s'", p_path));
		return false;
	}
	if (!FileAccess::exists(path)) {
		r_error = MCPToolError::not_found(vformat("File '%s'", path),
				"Use project_get_filesystem_tree to list the files of the project");
		return false;
	}
	// `ResourceLoader::get_resource_uid()` is the engine's own path -> UID
	// lookup (`ResourceUID::path_to_uid()` is a one-line wrapper over it). In an
	// editor process it asks every format loader; in a game process it reads the
	// reverse cache, which `Main::setup2()` loads (`main/main.cpp:2256-2258`,
	// `enable_reverse_cache()` + `load_from_cache(true)`), so both endpoints
	// answer from the same project state.
	ResourceUID *uids = ResourceUID::get_singleton();
	const ResourceUID::ID id = uids != nullptr ? ResourceLoader::get_resource_uid(path) : ResourceUID::INVALID_ID;
	// The renamed contract decides this case explicitly: "路径未注册时 uid 为空串
	// 且不报错" - an existing path without a UID is a *success* whose `uid` is the
	// empty string. The migration source answered `-32001` here
	// (project_commands.gd:243-244); the contract wins (PLAYBOOK section 6.6's
	// rule is about behaviour, but here the contract states the behaviour).
	const String uid_text = (id != ResourceUID::INVALID_ID) ? uids->id_to_text(id) : String();

	Dictionary out;
	out["path"] = path;
	out["uid"] = uid_text;
	r_out = out;
	return true;
}

bool convert_uid_to_path(const String &p_uid, Dictionary &r_out, MCPToolError &r_error) {
	ResourceUID *uids = ResourceUID::get_singleton();
	if (uids == nullptr) {
		r_error = MCPToolError::tool_state("ResourceUID is not available in this process",
				"This build has no resource-UID service; use a standard editor/game build");
		return false;
	}
	// `text_to_id()` is the engine's own parser and accepts exactly
	// `uid://<base36 lowercase>`; anything else - a `res://` path, an uppercase
	// suffix, a bare number - is `INVALID_ID`. The contract: "UID 文本格式非法时
	// 报参数错误" -> `-32602`, and this is also the half that makes a swapped call
	// (`project_convert_uid_to_path` handed a `res://` path) fail loudly.
	const ResourceUID::ID id = uids->text_to_id(p_uid);
	if (id == ResourceUID::INVALID_ID) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'uid' is not a valid UID text: '%s' (expected 'uid://...' with a lowercase base-36 suffix). "
				"To go the other way, use project_convert_path_to_uid with a res:// path",
				p_uid));
		return false;
	}
	if (!uids->has_id(id)) {
		r_error = MCPToolError::not_found(vformat("UID '%s'", p_uid),
				"The UID is well formed but no resource of this project is registered under it. Use "
				"project_convert_path_to_uid on the resource's res:// path to see the UID it has (an empty 'uid' means "
				"the resource has none yet)");
		return false;
	}

	Dictionary out;
	out["uid"] = p_uid;
	out["path"] = uids->get_id_path(id);
	r_out = out;
	return true;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// Registration
//
// The `description` and `inputSchema` below are the contract entries of
// docs/tools_list.renamed.json, character for character (parsed from JSON so
// that no hand-written Dictionary can drift from them); `channel`/`verb`/`scope`/
// `mutating` come from docs/tool-rename-map.json.
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_resource_uid_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

// `path` is a required string; the handler reads it with `require_string` so a
// missing / mistyped argument is `-32602` before anything else happens.
static Variant _tool_convert_path_to_uid(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	if (path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'path' must not be empty");
		return Variant();
	}
	Dictionary out;
	if (!convert_path_to_uid(path, out, r_error)) {
		return Variant();
	}
	return out;
}

// `uid` is a required string; an empty one reaches `text_to_id` and is refused
// as a malformed UID text (`-32602`), which is what the contract asks for.
static Variant _tool_convert_uid_to_path(const Dictionary &p_args, MCPToolError &r_error) {
	String uid;
	if (!require_string(p_args, "uid", uid, r_error)) {
		return Variant();
	}
	if (uid.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'uid' must not be empty");
		return Variant();
	}
	Dictionary out;
	if (!convert_uid_to_path(uid, out, r_error)) {
		return Variant();
	}
	return out;
}

void register_project_resource_uid_read_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_convert_path_to_uid", String::utf8(R"desc(将项目路径转换为 UID 判别点：入参为项目路径（如 res://...），返回 {path,uid}，路径未注册时 uid 为空串且不报错；反向转换请用 project_convert_uid_to_path。)desc"));
		builder.channel("project").verb("convert").scope(MCPToolScope::BOTH).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"path":{"type":"string"}},"required":["path"],"type":"object"})schema"));
		builder.handler(_tool_convert_path_to_uid).register_into(r_registry);
	}

	{
		ToolBuilder builder("project_convert_uid_to_path", String::utf8(R"desc(将 UID 转换为项目路径 判别点：入参为字符串文本 UID（如 uid://...），返回 {uid,path}，UID 文本格式非法时报参数错误；反向转换请用 project_convert_path_to_uid。)desc"));
		builder.channel("project").verb("convert").scope(MCPToolScope::BOTH).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"uid":{"type":"string"}},"required":["uid"],"type":"object"})schema"));
		builder.handler(_tool_convert_uid_to_path).register_into(r_registry);
	}
}
