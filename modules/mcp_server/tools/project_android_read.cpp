/**************************************************************************/
/*  project_android_read.cpp                                              */
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
#include "project_android_read.h"

#include "android_shared.h"

#include "core/io/json.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-036 section 1: the engine reference behind the one tool.
//
//   * the preset itself comes from the engine's own model when this process is
//     the editor (`EditorExportPreset`, `editor/export/editor_export.h:84`) and
//     from `res://export_presets.cfg` otherwise - the same two sources the
//     export reads use (`tools/android_shared.h`);
//   * the **capability** answer is `EditorExportPlatform::can_export`
//     (`editor/export/editor_export_platform.h:360`): the engine's own "can this
//     preset really be exported right now", with its own error text and a
//     `missing_templates` flag. A tool that answered "preset ok" without it
//     would be the exact false-success shape this batch is forbidden to ship;
//   * the SDK/JDK pieces come from `AndroidSDKManager::is_android_sdk_setup` /
//     `is_java_sdk_setup` (`editor/export/android_sdk_manager.cpp:662/698`) and
//     `get_adb_path` (`:781`), read in `android_environment()`;
//   * the migration source answered `-32603 "<preset> is not an Android preset"`
//     for a wrong platform (`android.rs:218-225`) and invented files/settings
//     elsewhere; here a wrong platform is `-32602` (the argument names something
//     the tool cannot use) and a missing preset is `-32001`/`-32000` with a
//     suggestion.
//
// **Design decision (recorded in REPORT-036 `deviations`):** when the Android
// preset *exists* but the SDK is not ready, the tool **answers** (with
// `sdk_ready: false`, `can_export: false` and the engine's error) instead of
// refusing with `-32000`. The tool's own capability is *reading* the preset -
// which the missing SDK does not affect - and refusing would make a readable
// thing unreadable while the honesty the task asks for is already carried by
// `export_capability` and `unavailable`. A missing preset file / missing Android
// preset *is* a `-32000` refusal, because then there is nothing to answer.
// ---------------------------------------------------------------------------

static Variant _tool_get_android_preset_info(const Dictionary &p_args, MCPToolError &r_error) {
	String preset_name;
	if (!optional_string(p_args, "preset_name", String(), preset_name, r_error)) {
		return Variant();
	}
	int64_t preset_index = -1;
	if (!optional_int(p_args, "preset_index", -1, preset_index, r_error)) {
		return Variant();
	}
	preset_name = preset_name.strip_edges();

	const String presets_path = export_presets_path();
	String source;
	bool file_present = false;
	String reason;
	const Array all_presets = export_presets_read(presets_path, source, file_present, reason);

	// The name is checked against **every** preset first, so "the name is wrong"
	// (-32001) and "the name exists but is not an Android preset" (-32602) are
	// told apart instead of collapsing into "no Android preset".
	String named_platform;
	int64_t named_index = -1;
	if (!preset_name.is_empty()) {
		bool name_found = false;
		for (int i = 0; i < all_presets.size(); i++) {
			const Dictionary record = all_presets[i];
			if (String(record.get("name", String())) == preset_name) {
				name_found = true;
				named_platform = record.get("platform", String());
				named_index = (int64_t)record.get("index", (int64_t)-1);
				break;
			}
		}
		if (!name_found) {
			r_error = MCPToolError::not_found(vformat("Export preset '%s'", preset_name),
					"Call project_list_export_presets to see the preset names this project has");
			return Variant();
		}
		if (named_platform != "Android") {
			r_error = MCPToolError::invalid_params(vformat(
					"'%s' is a %s export preset, not an Android preset", preset_name, named_platform));
			return Variant();
		}
		if (preset_index >= 0 && named_index != preset_index) {
			r_error = MCPToolError::invalid_params(vformat(
					"'preset_name' ('%s') and 'preset_index' (%d) name different presets (the name is preset %d)",
					preset_name, (int)preset_index, (int)named_index));
			return Variant();
		}
	} else if (preset_index >= 0) {
		bool index_found = false;
		for (int i = 0; i < all_presets.size(); i++) {
			if ((int64_t)((Dictionary)all_presets[i]).get("index", (int64_t)-1) == preset_index) {
				index_found = true;
				break;
			}
		}
		if (!index_found) {
			r_error = MCPToolError::not_found(vformat("Export preset index %d", (int)preset_index),
					"Call project_list_export_presets to see the preset indices this project has");
			return Variant();
		}
	}

	bool found = false;
	bool find_file_present = false;
	String find_source;
	String find_reason;
	const Dictionary record = android_preset_find(presets_path, preset_name, preset_index, found, find_file_present,
			find_source, find_reason);
	if (!found) {
		const String message = find_file_present
				? String("No Android export preset is configured in this project")
				: vformat("No export preset file exists at '%s'", presets_path);
		const String suggestion = find_file_present
				? vformat(
						  "Add an Android preset in the editor (Project > Export > Add... > Android); this project has %d "
						  "preset(s) and none of them is an Android preset",
						  (int)all_presets.size())
				: vformat(
						  "Add an Android export preset in the editor (Project > Export > Add... > Android) so that '%s' "
						  "exists; nothing can be described until then",
						  presets_path);
		r_error = MCPToolError::tool_state(message, suggestion);
		Dictionary merged = r_error.data;
		merged["presets_file"] = presets_path;
		merged["presets_file_present"] = find_file_present;
		merged["preset_count"] = all_presets.size();
		r_error.data = merged;
		return Variant();
	}

	bool checked = false;
	String can_export_error;
	bool missing_templates = false;
	const bool can_export = android_can_export(record, false, checked, can_export_error, missing_templates);

	const Dictionary environment = android_environment();

	Array unavailable;
	const Array environment_missing = environment.get("missing", Array());
	for (int i = 0; i < environment_missing.size(); i++) {
		unavailable.push_back(environment_missing[i]);
	}
	if (checked && !can_export) {
		Dictionary entry;
		entry["capability"] = "android_export";
		entry["detail"] = can_export_error.is_empty()
				? String("EditorExportPlatform::can_export answered false for this preset")
				: can_export_error;
		entry["missing_export_templates"] = missing_templates;
		unavailable.push_back(entry);
	} else if (!checked) {
		Dictionary entry;
		entry["capability"] = "android_export";
		entry["detail"] = "the engine's export-platform check (EditorExport::get_export_platform + "
						  "EditorExportPlatform::can_export) only runs in an editor process; this process can read the "
						  "preset but cannot decide whether it can be exported";
		unavailable.push_back(entry);
	}

	Dictionary capability;
	capability["checked"] = checked;
	capability["can_export"] = can_export;
	capability["error"] = can_export_error;
	capability["missing_templates"] = missing_templates;

	Dictionary out;
	const Array keys = record.keys();
	for (int i = 0; i < keys.size(); i++) {
		out[keys[i]] = record[keys[i]];
	}
	out["presets_source"] = source;
	out["presets_file"] = presets_path;
	out["presets_file_present"] = file_present;
	out["export_capability"] = capability;
	out["environment"] = environment;
	out["sdk_ready"] = environment.get("android_sdk_ready", false);
	out["adb_present"] = environment.get("adb_present", false);
	out["unavailable"] = unavailable;
	out["unavailable_count"] = unavailable.size();
	return out;
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character.
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_android_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_android_read_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("project_get_android_preset_info", String::utf8(R"desc(获取 Android 导出预设信息)desc"));
	builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false);
	builder.schema(_schema_from_json(R"schema({"properties":{"preset_index":{"description":"预设索引（可选）","type":"integer"},"preset_name":{"description":"预设名称（可选）","type":"string"}},"required":[],"type":"object"})schema"));
	builder.handler(_tool_get_android_preset_info).register_into(r_registry);
}
