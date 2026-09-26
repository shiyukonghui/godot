/**************************************************************************/
/*  android_shared.cpp                                                    */
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
#include "android_shared.h"

#include "tool_helpers.h"

#include "core/config/project_settings.h"
#include "core/io/config_file.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/os/os.h"

#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/export/android_sdk_manager.h"
#include "editor/export/editor_export.h"
#include "editor/export/editor_export_platform.h"
#include "editor/export/editor_export_preset.h"
#include "editor/settings/editor_settings.h"
#endif

using namespace MCPTools;

namespace {

// One `preset.N` section of `export_presets.cfg`, in the shape every export tool
// answers. The keys are the engine's (`name`, `platform`, `runnable`,
// `export_path`; `preset.N.options`'s `package/unique_name`).
Dictionary preset_record_from_config(const Ref<ConfigFile> &p_config, int p_index) {
	const String section = "preset." + itos(p_index);
	const String options_section = section + ".options";

	Dictionary record;
	record["index"] = p_index;
	record["name"] = p_config->get_value(section, "name", String());
	record["platform"] = p_config->get_value(section, "platform", String());
	record["runnable"] = p_config->get_value(section, "runnable", false);
	record["export_path"] = p_config->get_value(section, "export_path", String());
	String package_name;
	if (p_config->has_section(options_section)) {
		package_name = (String)p_config->get_value(options_section, "package/unique_name", String());
	}
	record["android_package_name"] = package_name;
	record["custom_features"] = p_config->get_value(section, "custom_features", String());
	return record;
}

bool config_has_section(const Ref<ConfigFile> &p_config, const String &p_section) {
	return p_config->has_section(p_section);
}

#ifdef MCP_EDITOR_TOOLS_ENABLED

// The engine's own loaded presets. Only reachable in an editor process whose
// `EditorExport` singleton exists; the caller checks both.
Array editor_export_presets(EditorExport *p_export) {
	Array presets;
	const int count = p_export->get_export_preset_count();
	for (int i = 0; i < count; i++) {
		const Ref<EditorExportPreset> preset = p_export->get_export_preset(i);
		if (preset.is_null()) {
			continue;
		}
		const Ref<EditorExportPlatform> platform = preset->get_platform();
		Dictionary record;
		record["index"] = i;
		record["name"] = preset->get_name();
		record["platform"] = platform.is_valid() ? platform->get_name() : String();
		record["platform_os"] = platform.is_valid() ? platform->get_os_name() : String();
		record["runnable"] = preset->is_runnable();
		record["export_path"] = preset->get_export_path();
		bool valid = false;
		record["android_package_name"] = preset->get_or_env(StringName("package/unique_name"), String(), &valid);
		record["custom_features"] = preset->get_custom_features();
		presets.push_back(record);
	}
	return presets;
}

#endif // MCP_EDITOR_TOOLS_ENABLED

} // namespace

namespace MCPTools {

String export_presets_path() {
	return "res://export_presets.cfg";
}

Array export_presets_read(const String &p_presets_path, String &r_source, bool &r_file_present, String &r_reason) {
	r_file_present = false;
	r_reason = String();
	r_source = String();

#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorExport *editor_export = is_editor_process() ? EditorExport::get_singleton() : nullptr;
	// Only the engine's **loaded** preset list wins; the `EditorExport` singleton
	// reads `res://export_presets.cfg` once at startup (`EditorExport::load_config`,
	// editor/export/editor_export.cpp:127-139), so a file written after that would
	// otherwise be answered as "0 presets, source=editor_export" - a false empty
	// that hides a preset the engine simply has not re-read. When the engine holds
	// nothing, the file itself is the source of truth.
	if (editor_export != nullptr && editor_export->get_export_preset_count() > 0) {
		r_source = "editor_export";
		r_file_present = FileAccess::exists(p_presets_path);
		return editor_export_presets(editor_export);
	}
#endif

	Ref<ConfigFile> config;
	config.instantiate();
	if (!FileAccess::exists(p_presets_path)) {
		r_reason = vformat("'%s' does not exist: this project has no export presets", p_presets_path);
		return Array();
	}
	const Error error = config->load(p_presets_path);
	if (error != OK) {
		r_reason = vformat("'%s' could not be parsed with ConfigFile: %s", p_presets_path,
				VariantUtilityFunctions::error_string(error));
		return Array();
	}
	r_source = "export_presets.cfg";
	r_file_present = true;
	Array presets;
	int index = 0;
	while (config_has_section(config, "preset." + itos(index))) {
		presets.push_back(preset_record_from_config(config, index));
		index++;
	}
	return presets;
}

Dictionary android_preset_find(const String &p_presets_path, const String &p_name, int64_t p_index,
		bool &r_found, bool &r_file_present, String &r_source, String &r_reason) {
	r_found = false;
	const Array presets = export_presets_read(p_presets_path, r_source, r_file_present, r_reason);
	for (int i = 0; i < presets.size(); i++) {
		const Dictionary record = presets[i];
		if (String(record.get("platform", String())) != "Android") {
			continue;
		}
		if (!p_name.is_empty() && String(record.get("name", String())) != p_name) {
			continue;
		}
		if (p_index >= 0 && (int64_t)record.get("index", (int64_t)-1) != p_index) {
			continue;
		}
		r_found = true;
		return record;
	}
	return Dictionary();
}

Dictionary android_environment() {
	Dictionary out;
	const bool editor_process = is_editor_process();
	out["editor_process"] = editor_process;

	Dictionary missing;
	Array missing_list;

#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorSettings *settings = editor_process ? EditorSettings::get_singleton() : nullptr;
	const bool settings_available = settings != nullptr;
	out["editor_settings_available"] = settings_available;

	if (settings_available) {
		const String android_sdk_path = settings->get_setting("export/android/android_sdk_path");
		const String java_sdk_path = settings->get_setting("export/android/java_sdk_path");
		const String debug_keystore = settings->get_setting("export/android/debug_keystore");
		out["android_sdk_path"] = android_sdk_path;
		out["android_sdk_path_present"] = !android_sdk_path.is_empty() && DirAccess::dir_exists_absolute(android_sdk_path);
		out["java_sdk_path"] = java_sdk_path;
		out["java_sdk_path_present"] = !java_sdk_path.is_empty() && DirAccess::dir_exists_absolute(java_sdk_path);
		out["debug_keystore"] = debug_keystore;
		out["debug_keystore_present"] = !debug_keystore.is_empty() && FileAccess::exists(debug_keystore);

		// The engine's own probes: they check the packages the exporter really
		// needs (platform-tools, build-tools, platforms/android-N,
		// cmdline-tools) and fill its own error text.
		String android_error;
		const bool android_ready = AndroidSDKManager::is_android_sdk_setup(&android_error);
		String java_error;
		const bool java_ready = AndroidSDKManager::is_java_sdk_setup(&java_error);
		out["android_sdk_ready"] = android_ready;
		out["android_sdk_error"] = android_error.strip_edges();
		out["java_sdk_ready"] = java_ready;
		out["java_sdk_error"] = java_error.strip_edges();
		if (!android_ready) {
			missing["capability"] = "android_sdk";
			missing["detail"] = android_error.strip_edges().is_empty()
					? String("the Android SDK is not set up")
					: android_error.strip_edges();
			missing_list.push_back(missing);
		}
		if (!java_ready) {
			Dictionary java_missing;
			java_missing["capability"] = "java_sdk";
			java_missing["detail"] = java_error.strip_edges().is_empty()
					? String("the Java SDK is not set up")
					: java_error.strip_edges();
			missing_list.push_back(java_missing);
		}
	} else {
		out["android_sdk_path"] = String();
		out["android_sdk_path_present"] = false;
		out["java_sdk_path"] = String();
		out["java_sdk_path_present"] = false;
		out["debug_keystore"] = String();
		out["debug_keystore_present"] = false;
		out["android_sdk_ready"] = false;
		out["android_sdk_error"] = "EditorSettings is not available in this process, so the Android SDK state is not knowable here";
		out["java_sdk_ready"] = false;
		out["java_sdk_error"] = "EditorSettings is not available in this process, so the Java SDK state is not knowable here";
		Dictionary settings_missing;
		settings_missing["capability"] = "editor_settings";
		settings_missing["detail"] = "an editor process is required to read the Android SDK configuration (EditorSettings)";
		missing_list.push_back(settings_missing);
	}
#else
	out["editor_settings_available"] = false;
	out["android_sdk_path"] = String();
	out["android_sdk_path_present"] = false;
	out["java_sdk_path"] = String();
	out["java_sdk_path_present"] = false;
	out["debug_keystore"] = String();
	out["debug_keystore_present"] = false;
	out["android_sdk_ready"] = false;
	out["android_sdk_error"] = "this build has no editor code, so EditorSettings (and the Android SDK configuration) does not exist here";
	out["java_sdk_ready"] = false;
	out["java_sdk_error"] = "this build has no editor code, so EditorSettings (and the Java SDK configuration) does not exist here";
	Dictionary settings_missing;
	settings_missing["capability"] = "editor_code";
	settings_missing["detail"] = "the Android SDK probes live in editor code and are absent from this build";
	missing_list.push_back(settings_missing);
#endif

	const String adb_path = android_adb_path();
	const bool adb_present = adb_path != "adb" && FileAccess::exists(adb_path);
	out["adb_path"] = adb_path;
	out["adb_present"] = adb_present;
	if (!adb_present) {
		Dictionary adb_missing;
		adb_missing["capability"] = "adb";
		adb_missing["detail"] = vformat(
				"no adb at '%s' and none configured in EditorSettings (export/android/android_sdk_path/platform-tools); "
				"install Android platform-tools or set the Android SDK path",
				adb_path);
		missing_list.push_back(adb_missing);
	}
	out["missing"] = missing_list;
	out["missing_count"] = missing_list.size();
	return out;
}

String android_adb_path() {
#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorSettings *settings = is_editor_process() ? EditorSettings::get_singleton() : nullptr;
	if (settings != nullptr) {
		const String sdk_path = settings->get_setting("export/android/android_sdk_path");
		if (!sdk_path.is_empty()) {
			String exe_ext;
			if (OS::get_singleton()->get_name() == "Windows") {
				exe_ext = ".exe";
			}
			const String candidate = sdk_path.path_join("platform-tools/adb" + exe_ext);
			if (FileAccess::exists(candidate)) {
				return candidate;
			}
		}
	}
#endif
	// The bare name is resolved through `PATH` by `OS::execute`; the migration
	// source had the same fallback (`godot_mcp_gdext/src/commands/android.rs:176`).
	return "adb";
}

bool run_process_capture(const String &p_path, const List<String> &p_arguments, String &r_output, int &r_exit_code,
		bool &r_ran, MCPToolError &r_error) {
	r_output = String();
	r_exit_code = -1;
	r_ran = false;
	if (p_path.is_empty()) {
		r_error = MCPToolError::internal("An empty process path cannot be executed");
		return false;
	}
	String output;
	int exit_code = -1;
	const Error error = OS::get_singleton()->execute(p_path, p_arguments, &output, &exit_code, true);
	if (error != OK) {
		r_error = MCPToolError::tool_state(
				vformat("Could not run '%s': %s", p_path, VariantUtilityFunctions::error_string(error)),
				"Check that the executable exists and is runnable from this process");
		return false;
	}
	r_output = output;
	r_exit_code = exit_code;
	r_ran = true;
	return true;
}

bool adb_run(const Vector<String> &p_arguments, String &r_output, int &r_exit_code, String &r_adb_path, bool &r_ran,
		MCPToolError &r_error) {
	r_adb_path = android_adb_path();
	List<String> arguments;
	for (int i = 0; i < p_arguments.size(); i++) {
		arguments.push_back(p_arguments[i]);
	}
	return run_process_capture(r_adb_path, arguments, r_output, r_exit_code, r_ran, r_error);
}

Array parse_adb_devices(const String &p_output) {
	Array devices;
	const Vector<String> lines = p_output.split("\n");
	for (int i = 0; i < lines.size(); i++) {
		const String line = lines[i].strip_edges();
		if (line.is_empty() || line.begins_with("List of devices") || line.begins_with("* daemon")) {
			continue;
		}
		// `split_spaces` is the engine's own "split on runs of whitespace"
		// (`core/string/ustring.h:501`), which is what adb really prints between
		// the serial, the state and the `key:value` pairs (the migration source's
		// Rust `split_whitespace()` did the same).
		const Vector<String> parts = line.split_spaces();
		if (parts.size() < 2) {
			continue;
		}
		Dictionary device;
		device["serial"] = parts[0];
		device["state"] = parts[1];
		for (int part = 2; part < parts.size(); part++) {
			const int separator = parts[part].find(":");
			if (separator <= 0) {
				continue;
			}
			device[parts[part].substr(0, separator)] = parts[part].substr(separator + 1);
		}
		devices.push_back(device);
	}
	return devices;
}

Array android_devices(bool &r_ran, String &r_adb_path, String &r_output, MCPToolError &r_error) {
	Vector<String> arguments;
	arguments.push_back("devices");
	arguments.push_back("-l");
	int exit_code = -1;
	r_ran = false;
	if (!adb_run(arguments, r_output, exit_code, r_adb_path, r_ran, r_error)) {
		return Array();
	}
	if (!r_ran) {
		return Array();
	}
	if (exit_code != 0) {
		r_error = MCPToolError::tool_state(
				vformat("adb devices -l failed with exit code %d: %s", exit_code, r_output.strip_edges()),
				"Check that the Android platform-tools are installed and that the adb server can start "
				"(run 'adb start-server' once by hand)");
		return Array();
	}
	return parse_adb_devices(r_output);
}

bool android_can_export(const Dictionary &p_preset, bool p_debug, bool &r_checked, String &r_error_text,
		bool &r_missing_templates) {
	r_checked = false;
	r_error_text = String();
	r_missing_templates = false;
#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorExport *editor_export = is_editor_process() ? EditorExport::get_singleton() : nullptr;
	if (editor_export == nullptr) {
		return false;
	}
	const int preset_index = (int)(int64_t)p_preset.get("index", (int64_t)-1);
	if (preset_index < 0 || preset_index >= editor_export->get_export_preset_count()) {
		r_error_text = "the preset is not one of the engine's loaded export presets";
		return false;
	}
	const Ref<EditorExportPreset> preset = editor_export->get_export_preset(preset_index);
	if (preset.is_null()) {
		r_error_text = "the engine's preset at this index is null";
		return false;
	}
	const Ref<EditorExportPlatform> platform = preset->get_platform();
	if (platform.is_null()) {
		r_error_text = "the preset has no export platform";
		return false;
	}
	r_checked = true;
	return platform->can_export(preset, r_error_text, r_missing_templates, p_debug);
#else
	(void)p_preset;
	(void)p_debug;
	return false;
#endif
}

Array export_platforms_read(bool &r_available) {
	r_available = false;
#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorExport *editor_export = is_editor_process() ? EditorExport::get_singleton() : nullptr;
	if (editor_export == nullptr) {
		return Array();
	}
	r_available = true;
	Array platforms;
	const int count = editor_export->get_export_platform_count();
	for (int i = 0; i < count; i++) {
		const Ref<EditorExportPlatform> platform = editor_export->get_export_platform(i);
		if (platform.is_null()) {
			continue;
		}
		Dictionary record;
		record["name"] = platform->get_name();
		record["os"] = platform->get_os_name();
		platforms.push_back(record);
	}
	return platforms;
#else
	return Array();
#endif
}

} // namespace MCPTools
