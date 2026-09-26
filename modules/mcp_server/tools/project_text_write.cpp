/**************************************************************************/
/*  project_text_write.cpp                                                */
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
#include "project_text_write.h"

#include "tool_helpers.h"

#include "core/io/file_access.h"
#include "core/io/json.h"

using namespace MCPTools;

namespace {

// The refusal shape for "the destination exists and `overwrite` is false".
//
// TASK-052 used `-32001` here; TASK-053 section 1 (DESIGN-DETAIL.md section 26 /
// GDR-28 point 10) **re-judged** it, and the new code is `-32000`:
//
//   * `-32001` is GDR-14's "the concrete thing you looked for is absent". The
//     destination is the one thing this call *did* find - it is there, and that
//     is exactly why the call is refused;
//   * `-32602` is "a declared parameter carries a value the schema forbids".
//     `overwrite` is declared and `false` is one of its legal values, so the
//     argument is not at fault either;
//   * what is at fault is the **state** of the project, which is the one meaning
//     GDR-14 gives `-32000`: the call is well formed and legal, and the state
//     does not allow it. `MCPToolError::tool_state()` is the module's factory for
//     that, and it always carries `data.suggestion` - here the advice names
//     `overwrite: true`, the single argument that gets past the refusal.
//
// `MCPToolError::not_found()` was never usable for this: it appends " not found"
// to its `p_what`, the opposite of the condition being reported.
MCPToolError _already_exists(const String &p_path, const String &p_suggestion) {
	return MCPToolError::tool_state(
			vformat("Project file '%s' already exists and 'overwrite' is false", p_path), p_suggestion);
}

Dictionary _suggestion(const String &p_text) {
	Dictionary data;
	data["suggestion"] = p_text;
	return data;
}

// The project root, spelled the one way `normalize_project_path` produces it.
const char *const PROJECT_ROOT = "res://";

// The four extensions that have a dedicated writer, and the tool that owns each.
// `.tscn` and `.tres` are two halves of the resource family; so are `.gd` and
// `.cs` for the script family (which is why `project_create_script` accepts both
// extensions - `project_script_write.cpp:109-126`).
struct DedicatedFamily {
	const char *extension;
	const char *suggestion;
};

const DedicatedFamily DEDICATED_FAMILIES[] = {
	{ "tscn", "Use project_create_scene_file to create a scene file, or editor_save_scene for the scene the editor has open" },
	{ "tres", "Use project_create_resource or project_edit_resource to write a resource" },
	{ "gd", "Use project_create_script or project_edit_script to write a GDScript file" },
	{ "cs", "Use project_create_script or project_edit_script to write a C# script file" },
};

// Turns the raw `path` argument into the canonical `res://` path that is opened,
// or fills a `-32602` whose suggestion names the rule (or the dedicated tool).
bool _prepare_target(const String &p_input, String &r_path, MCPToolError &r_error) {
	// The *raw* spelling is what the "names a file" rule reads: after
	// `normalize_project_path` folded the trailing segment away, `res://dir/` and
	// `res://dir` are the same string, and only one of them names a file. The
	// backslash normalisation and the `strip_edges` are `normalize_screenshot_path`'s
	// (a Windows caller may spell a project path either way, and `"   "` is the
	// project root, not a file name).
	const String raw = p_input.replace("\\", "/").strip_edges();
	if (!normalize_project_path(p_input, r_path, r_error)) {
		// `normalize_project_path` answers the module's canonical `-32602`; the
		// suggestion is added here because only this tool knows why it is asking.
		r_error.data = _suggestion("'path' must address the project ('res://...') and must not contain a '..' segment: this tool writes only inside the project directory");
		return false;
	}
	if (raw.is_empty() || raw.ends_with("/") || r_path == PROJECT_ROOT || r_path.get_file().is_empty()) {
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'path' must name a file, got '%s'", p_input));
		r_error.data = _suggestion("Pass the file name too, e.g. 'res://MyProject.csproj' or 'res://NuGet.config'");
		return false;
	}

	const String file_name = r_path.get_file();
	// `project.godot` is the project's own settings file. It is not "just another
	// text file": `project_set_setting` publishes it through the engine's own
	// `ProjectSettings::save_custom()` writer, and a second writer that produced
	// different bytes for the same settings would be a way to corrupt the project
	// with a call that looks harmless. Compared case insensitively, because
	// `PROJECT.GODOT` is the same file on Windows.
	if (file_name.to_lower() == "project.godot") {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'path' names '%s', the project's own settings file, which this tool does not write", r_path));
		r_error.data = _suggestion("Use project_set_setting to change a project setting: it publishes project.godot through the engine's own ProjectSettings writer");
		return false;
	}

	const String extension = file_name.get_extension().to_lower();
	for (const DedicatedFamily &family : DEDICATED_FAMILIES) {
		if (extension != String::utf8(family.extension)) {
			continue;
		}
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'path' names a '.%s' file ('%s'), which has a dedicated tool", String::utf8(family.extension), r_path));
		r_error.data = _suggestion(String::utf8(family.suggestion));
		return false;
	}
	return true;
}

} // namespace

namespace MCPTools {

bool write_project_text_file(const String &p_path, const String &p_content, bool p_overwrite,
		Dictionary &r_out, MCPToolError &r_error) {
	String path;
	if (!_prepare_target(p_path, path, r_error)) {
		return false;
	}

	const bool existed = FileAccess::exists(path);
	if (existed && !p_overwrite) {
		r_error = _already_exists(path,
				"Pass \"overwrite\": true to replace the existing file, or choose another path");
		return false;
	}

	// The atomic publish: bytes into a sibling temporary, then a rename over the
	// destination, with the previous bytes copied aside and put back if the
	// publish step fails (`publish_file_atomically`, tools/tool_helpers.cpp:488).
	const Error publish_error = publish_text_atomically(path, p_content);
	if (publish_error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to write '%s': %s", path,
				VariantUtilityFunctions::error_string(publish_error)));
		return false;
	}

	// The read-back is the point of the answer: "I called the writer" is not
	// evidence that the file holds the bytes the caller asked for.
	Error read_error = OK;
	const Vector<uint8_t> on_disk = FileAccess::get_file_as_bytes(path, &read_error);
	if (read_error != OK) {
		r_error = MCPToolError::internal(vformat(
				"Wrote '%s' but could not read it back to verify it (error %d)", path, (int64_t)read_error));
		return false;
	}
	const CharString expected = p_content.utf8();
	bool same = (int64_t)on_disk.size() == (int64_t)expected.length();
	for (int i = 0; same && i < on_disk.size(); i++) {
		if (on_disk[i] != (uint8_t)expected[i]) {
			same = false;
		}
	}
	if (!same) {
		r_error = MCPToolError::internal(vformat(
				"Wrote '%s' but the file on disk (%d bytes) differs from the requested content (%d bytes)",
				path, (int64_t)on_disk.size(), (int64_t)expected.length()));
		return false;
	}

	Dictionary out;
	out["path"] = path;
	out["bytes"] = (int64_t)on_disk.size();
	// The engine's own hash of the file that is on disk right now.
	out["sha256"] = FileAccess::get_sha256(path);
	out["created"] = !existed;
	r_out = out;
	return true;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tool
// ---------------------------------------------------------------------------

static Variant _tool_write_text_file(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	String content;
	if (!require_string(p_args, "content", content, r_error)) {
		return Variant();
	}
	bool overwrite = false;
	if (!optional_bool(p_args, "overwrite", false, overwrite, r_error)) {
		return Variant();
	}
	Dictionary out;
	if (!MCPTools::write_project_text_file(path, content, overwrite, out, r_error)) {
		return Variant();
	}
	return out;
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// `docs/tools_list.renamed.json`, character for character - and that entry is
// generated from `ADDED_TOOLS` in `scripts/gen_renamed_contract.py` (GDR-28
// point 1: an added entry is authored by the decision maker, never by this
// file).
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_text_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_text_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_write_text_file",
				String::utf8(R"desc(Write a project text file such as a .csproj, .sln, NuGet.config or .cfg, and answer the resulting size and sha256. Refuses scene, resource and script paths (use the dedicated tools for those) and refuses project.godot (use project_set_setting).)desc"));
		builder.channel("project").verb("write").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"content":{"type":"string"},"overwrite":{"default":false,"type":"boolean"},"path":{"type":"string"}},"required":["path","content"],"type":"object"})schema"));
		builder.handler(_tool_write_text_file).register_into(r_registry);
	}
}