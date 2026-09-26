/**************************************************************************/
/*  project_export_read.cpp                                               */
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
#include "project_export_read.h"

#include "android_shared.h"

#include "core/config/project_settings.h"
#include "core/io/json.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-036 section 1: the engine reference behind the two tools.
//
//   * `EditorExport::get_export_preset` / `get_export_platform_count`
//     (`editor/export/editor_export.h:79/84`) are the editor's own loaded
//     presets and registered platforms - the source an editor process answers
//     from, because the engine has already parsed the file the same way;
//   * `res://export_presets.cfg` through `ConfigFile` is the source a **game
//     process** has (`godot_mcp_gdext/src/commands/export.rs:44-80` read the
//     same file), and it is also the answer when `EditorExport` is present but
//     empty;
//   * `ProjectSettings::get_setting("application/config/name")` is the project
//     name the migration source answered
//     (`godot_mcp_gdext/src/commands/export.rs:36-40`);
//   * a missing `export_presets.cfg` is **not** an error: the project really has
//     no presets, and the answer says so (`presets_file_present: false`,
//     `presets: []`, `count: 0`) instead of failing or inventing one. That is
//     the "capability missing" evidence this batch must keep separable from a
//     real success.
// ---------------------------------------------------------------------------

namespace {

// The distinct platform names the presets name, with their preset counts, in
// the engine's own preset order.
Array platform_summary(const Array &p_presets) {
	Array out;
	Array seen;
	for (int i = 0; i < p_presets.size(); i++) {
		const Dictionary record = p_presets[i];
		const String platform = record.get("platform", String());
		if (seen.has(platform)) {
			continue;
		}
		seen.push_back(platform);
		int count = 0;
		for (int j = 0; j < p_presets.size(); j++) {
			if (String(((Dictionary)p_presets[j]).get("platform", String())) == platform) {
				count++;
			}
		}
		Dictionary entry;
		entry["platform"] = platform;
		entry["preset_count"] = count;
		out.push_back(entry);
	}
	return out;
}

} // namespace

static Variant _tool_get_export_info(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	(void)r_error;

	String source;
	bool file_present = false;
	String reason;
	const String presets_path = export_presets_path();
	const Array presets = export_presets_read(presets_path, source, file_present, reason);

	ProjectSettings *settings = ProjectSettings::get_singleton();
	const String project_name = settings != nullptr
			? (String)settings->get_setting("application/config/name", String())
			: String();

	bool platforms_available = false;
	const Array export_platforms = export_platforms_read(platforms_available);

	Dictionary capabilities;
	capabilities["editor_process"] = is_editor_process();
	capabilities["editor_export"] = platforms_available;
	capabilities["presets_source"] = source;

	Array unavailable;
	if (!file_present) {
		Dictionary entry;
		entry["capability"] = "export_presets";
		entry["detail"] = reason.is_empty()
				? vformat("'%s' does not exist", presets_path)
				: reason;
		unavailable.push_back(entry);
	}
	if (!platforms_available) {
		Dictionary entry;
		entry["capability"] = "editor_export";
		entry["detail"] = "the engine's export-platform registry lives in EditorExport, which only exists in an editor "
						  "process; this process can still read export_presets.cfg but cannot enumerate the platforms";
		unavailable.push_back(entry);
	}

	Dictionary out;
	out["project_name"] = project_name;
	out["presets_file"] = presets_path;
	out["presets_file_present"] = file_present;
	out["preset_count"] = presets.size();
	out["presets_source"] = source;
	out["platforms"] = platform_summary(presets);
	out["export_platforms"] = export_platforms;
	out["export_platform_count"] = export_platforms.size();
	out["capabilities"] = capabilities;
	out["unavailable"] = unavailable;
	out["unavailable_count"] = unavailable.size();
	if (!file_present) {
		out["message"] = reason;
	}
	return out;
}

static Variant _tool_list_export_presets(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	(void)r_error;

	String source;
	bool file_present = false;
	String reason;
	const String presets_path = export_presets_path();
	const Array presets = export_presets_read(presets_path, source, file_present, reason);

	Dictionary out;
	out["presets"] = presets;
	out["count"] = presets.size();
	out["presets_file"] = presets_path;
	out["presets_file_present"] = file_present;
	out["presets_source"] = source;
	if (!file_present) {
		out["message"] = reason;
	}
	return out;
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character. Both tools declare the
// empty object schema (`{"properties":{},"required":[]}`), so a caller passing
// any argument is refused by the registry's unknown-argument gate (TASK-032 D4).
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_export_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_export_read_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_get_export_info", String::utf8(R"desc(获取导出信息)desc"));
		builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{},"required":[],"type":"object"})schema"));
		builder.handler(_tool_get_export_info).register_into(r_registry);
	}
	{
		ToolBuilder builder("project_list_export_presets", String::utf8(R"desc(列出所有导出预设)desc"));
		builder.channel("project").verb("list").scope(MCPToolScope::BOTH).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{},"required":[],"type":"object"})schema"));
		builder.handler(_tool_list_export_presets).register_into(r_registry);
	}
}
