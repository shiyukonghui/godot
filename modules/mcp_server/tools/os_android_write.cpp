/**************************************************************************/
/*  os_android_write.cpp                                                  */
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
#include "os_android_write.h"

#include "../mcp_deferred.h"
#include "android_shared.h"
#include "tool_helpers.h"

#include "core/config/project_settings.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/os/os.h"
#include "scene/main/scene_tree.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-036 section 1: the engine reference behind the one tool.
//
//   * the export is the engine's own command line, the same one the migration
//     source ran (`android.rs:289-298`): `<engine> --headless --path <project>
//     --export-debug|--export-release <preset> <apk>`. It is started with
//     `OS::create_process` (`core/os/os.h:217`) and **polled** with
//     `is_process_running` / `get_process_exit_code`, so the main thread is
//     never blocked (GDR-20 point 3);
//   * adb is the transport the engine's Android exporter uses
//     (`platform/android/export/export_plugin.cpp:341/2375`): `adb install -r
//     [-s <serial>] <apk>`, then `adb shell monkey -p <package> -c
//     android.intent.category.LAUNCHER 1` to launch it - the same two commands
//     the migration source built (`android.rs:300-344`);
//   * the package name comes from the preset's `package/unique_name` option
//     (the migration read the same key, `android.rs:321-324`);
//   * **every** capability is checked before the request is handed to the task:
//     a missing SDK/adb/device is a `-32000` whose `data` names exactly what is
//     missing and how to install it. Nothing is faked and no device is echoed.
//   * `skip_export = true` is the branch that needs no export platform at all:
//     it installs the already-built APK at the preset's `export_path`, which is
//     also the only branch a game process can reach.
// ---------------------------------------------------------------------------

namespace {

// The absolute APK path a preset names: `res://...` is globalised with
// `ProjectSettings::globalize_path`, an already-absolute path is kept, and
// anything else is taken relative to the project directory.
String absolute_export_path(const String &p_export_path) {
	if (p_export_path.begins_with("res://")) {
		return ProjectSettings::get_singleton()->globalize_path(p_export_path);
	}
	if (p_export_path.is_absolute_path()) {
		return p_export_path;
	}
	return ProjectSettings::get_singleton()->globalize_path("res://").path_join(p_export_path);
}

void add_missing(Array &r_missing, const String &p_capability, const String &p_detail) {
	Dictionary entry;
	entry["capability"] = p_capability;
	entry["detail"] = p_detail;
	r_missing.push_back(entry);
}

// One `{step, ...}` record of the deployment.
Dictionary step_record(const String &p_step) {
	Dictionary step;
	step["step"] = p_step;
	return step;
}

} // namespace

// ---------------------------------------------------------------------------
// The deferred task
//
// Phases: EXPORT (game/editor CLI export, polled) -> INSTALL (adb install -r)
// -> LAUNCH (adb shell monkey). Every step is recorded, and the answer the
// caller receives is the list of steps with their real exit codes. A failure of
// any step ends the request with a tool error carrying that step, never with a
// success shape.
// ---------------------------------------------------------------------------

class DeployToAndroidTask : public MCPDeferred::Task {
public:
	DeployToAndroidTask(const String &p_preset_name, const String &p_apk_absolute, const String &p_export_path,
			const String &p_device_serial, const String &p_package_name, const String &p_adb_path,
			bool p_debug, bool p_launch, bool p_skip_export) :
			preset_name(p_preset_name),
			apk_absolute(p_apk_absolute),
			export_path(p_export_path),
			device_serial(p_device_serial),
			package_name(p_package_name),
			adb_path(p_adb_path),
			debug(p_debug),
			launch(p_launch),
			skip_export(p_skip_export) {
		if (p_skip_export) {
			phase = Phase::INSTALL;
		}
	}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_frame;
		(void)p_now_ms;
		switch (phase) {
			case Phase::EXPORT: {
				return tick_export();
			}
			case Phase::INSTALL: {
				return tick_install();
			}
			case Phase::LAUNCH: {
				return tick_launch();
			}
			default: {
				return MCPDeferred::TickResult::done(build_result());
			}
		}
	}

	uint64_t get_timeout_ms() const override { return 0; }

	String describe() const override {
		return vformat("deploying preset '%s' to device '%s'", preset_name,
				device_serial.is_empty() ? String("(default)") : device_serial);
	}

	// The project directory the export child is pointed at (`--path`).
	void set_project_dir(const String &p_dir) { project_dir = p_dir; }

private:
	enum class Phase {
		EXPORT,
		INSTALL,
		LAUNCH,
		DONE,
	};

	MCPDeferred::TickResult tick_export() {
		if (export_pid == 0) {
			OS *os = OS::get_singleton();
			List<String> arguments;
			arguments.push_back("--headless");
			arguments.push_back("--path");
			arguments.push_back(project_dir);
			arguments.push_back(debug ? "--export-debug" : "--export-release");
			arguments.push_back(preset_name);
			arguments.push_back(apk_absolute);
			ProcessID pid = 0;
			const Error error = os->create_process(os->get_executable_path(), arguments, &pid, false);
			if (error != OK) {
				return MCPDeferred::TickResult::failed(MCPToolError::tool_state(
						vformat("Could not start the export process: %s", VariantUtilityFunctions::error_string(error)),
						"Check that this process may spawn children and that the engine binary is still where it was started "
						"from"));
			}
			export_pid = pid;
			Dictionary step = step_record("export");
			step["command"] = vformat("%s --headless --path %s %s %s %s", os->get_executable_path(), project_dir,
					debug ? "--export-debug" : "--export-release", preset_name, apk_absolute);
			step["pid"] = (int64_t)pid;
			step["started"] = true;
			steps.push_back(step);
			return MCPDeferred::TickResult::pending();
		}
		OS *os = OS::get_singleton();
		if (os->is_process_running(export_pid)) {
			return MCPDeferred::TickResult::pending();
		}
		const int exit_code = os->get_process_exit_code(export_pid);
		const bool apk_present = FileAccess::exists(apk_absolute);
		Dictionary step = (Dictionary)steps[steps.size() - 1];
		step["exit_code"] = exit_code;
		step["apk_present"] = apk_present;
		steps[steps.size() - 1] = step;
		export_pid = 0;
		if (exit_code != 0) {
			return MCPDeferred::TickResult::failed(MCPToolError::tool_state(
					vformat("The export command failed with exit code %d (preset '%s', output '%s')", exit_code,
							preset_name, apk_absolute),
					"Run the same export from the editor (Project > Export) and read its error output; the most common causes "
					"are missing export templates, a missing Android SDK/JDK and a keystore that is not configured"));
		}
		if (!apk_present) {
			return MCPDeferred::TickResult::failed(MCPToolError::tool_state(
					vformat("The export command reported success but no file exists at '%s'", apk_absolute),
					"Check the preset's export_path and that the export really wrote there"));
		}
		phase = Phase::INSTALL;
		return MCPDeferred::TickResult::pending();
	}

	MCPDeferred::TickResult tick_install() {
		Vector<String> arguments;
		if (!device_serial.is_empty()) {
			arguments.push_back("-s");
			arguments.push_back(device_serial);
		}
		arguments.push_back("install");
		arguments.push_back("-r");
		arguments.push_back(apk_absolute);
		String output;
		int exit_code = -1;
		bool ran = false;
		MCPToolError error;
		if (!adb_run(arguments, output, exit_code, adb_path, ran, error)) {
			return MCPDeferred::TickResult::failed(error);
		}
		Dictionary step = step_record("install");
		step["adb"] = adb_path;
		step["apk"] = apk_absolute;
		step["device"] = device_serial.is_empty() ? String("(default)") : device_serial;
		step["exit_code"] = exit_code;
		step["output"] = output.strip_edges();
		steps.push_back(step);
		if (exit_code != 0) {
			return MCPDeferred::TickResult::failed(MCPToolError::tool_state(
					vformat("adb install failed with exit code %d: %s", exit_code, output.strip_edges()),
					"Check that the device is connected and authorised ('adb devices -l' must show it as 'device') and that "
					"the APK is valid for it"));
		}
		phase = launch ? Phase::LAUNCH : Phase::DONE;
		return MCPDeferred::TickResult::pending();
	}

	MCPDeferred::TickResult tick_launch() {
		if (package_name.is_empty()) {
			Dictionary step = step_record("launch");
			step["skipped"] = true;
			step["reason"] = "the preset has no package/unique_name option, so there is no package to launch";
			steps.push_back(step);
			phase = Phase::DONE;
			return MCPDeferred::TickResult::pending();
		}
		Vector<String> arguments;
		if (!device_serial.is_empty()) {
			arguments.push_back("-s");
			arguments.push_back(device_serial);
		}
		arguments.push_back("shell");
		arguments.push_back("monkey");
		arguments.push_back("-p");
		arguments.push_back(package_name);
		arguments.push_back("-c");
		arguments.push_back("android.intent.category.LAUNCHER");
		arguments.push_back("1");
		String output;
		int exit_code = -1;
		bool ran = false;
		MCPToolError error;
		if (!adb_run(arguments, output, exit_code, adb_path, ran, error)) {
			return MCPDeferred::TickResult::failed(error);
		}
		Dictionary step = step_record("launch");
		step["package"] = package_name;
		step["exit_code"] = exit_code;
		step["output"] = output.strip_edges();
		steps.push_back(step);
		phase = Phase::DONE;
		return MCPDeferred::TickResult::pending();
	}

	Dictionary build_result() const {
		Dictionary out;
		out["preset"] = preset_name;
		out["apk_path"] = apk_absolute;
		out["export_path_res"] = export_path;
		out["device"] = device_serial.is_empty() ? String("(default)") : device_serial;
		out["package_name"] = package_name;
		out["debug"] = debug;
		out["launch"] = launch;
		out["skip_export"] = skip_export;
		out["adb_path"] = adb_path;
		out["steps"] = steps;
		out["step_count"] = steps.size();
		out["deployed"] = true;
		return out;
	}

	String preset_name;
	String apk_absolute;
	String export_path;
	String device_serial;
	String package_name;
	String adb_path;
	bool debug = true;
	bool launch = true;
	bool skip_export = false;
	Phase phase = Phase::EXPORT;
	String project_dir;
	ProcessID export_pid = 0;
	Array steps;
};

// ---------------------------------------------------------------------------
// The handler
// ---------------------------------------------------------------------------

static MCPDeferred::Task *_tool_deploy_to_android_device(const Dictionary &p_args, MCPToolError &r_error) {
	String preset_name;
	if (!require_string(p_args, "preset_name", preset_name, r_error)) {
		return nullptr;
	}
	preset_name = preset_name.strip_edges();
	if (preset_name.is_empty()) {
		r_error = MCPToolError::invalid_params("'preset_name' must not be empty");
		return nullptr;
	}
	String device_id;
	if (!optional_string(p_args, "device_id", String(), device_id, r_error)) {
		return nullptr;
	}
	device_id = device_id.strip_edges();
	bool debug = true;
	if (!optional_bool(p_args, "debug", true, debug, r_error)) {
		return nullptr;
	}
	bool launch = true;
	if (!optional_bool(p_args, "launch", true, launch, r_error)) {
		return nullptr;
	}
	bool skip_export = false;
	if (!optional_bool(p_args, "skip_export", false, skip_export, r_error)) {
		return nullptr;
	}

	const String presets_path = export_presets_path();
	String source;
	bool file_present = false;
	String read_reason;
	const Array presets = export_presets_read(presets_path, source, file_present, read_reason);

	Dictionary preset;
	for (int i = 0; i < presets.size(); i++) {
		const Dictionary record = presets[i];
		if (String(record.get("name", String())) == preset_name) {
			preset = record;
			break;
		}
	}
	if (preset.is_empty()) {
		r_error = MCPToolError::not_found(vformat("Export preset '%s'", preset_name),
				"Call project_list_export_presets to see the preset names this project has");
		return nullptr;
	}
	const String platform = preset.get("platform", String());
	if (platform != "Android") {
		r_error = MCPToolError::invalid_params(vformat(
				"'%s' is a %s export preset, not an Android preset; this tool only deploys Android presets", preset_name,
				platform));
		return nullptr;
	}

	const String export_path = preset.get("export_path", String());
	const String package_name = preset.get("android_package_name", String());
	if (export_path.strip_edges().is_empty()) {
		r_error = MCPToolError::tool_state(
				vformat("Android preset '%s' has no export_path configured", preset_name),
				"Set the preset's export path in the editor (Project > Export > preset > Export Path); the APK is written "
				"there and installed from there");
		return nullptr;
	}
	const String apk_absolute = absolute_export_path(export_path);

	Dictionary environment = android_environment();
	Array missing = environment.get("missing", Array());

	// (2) the export platform, when the export step is not skipped.
	if (!skip_export) {
		bool checked = false;
		String can_export_error;
		bool missing_templates = false;
		const bool can_export = android_can_export(preset, debug, checked, can_export_error, missing_templates);
		if (!checked) {
			r_error = MCPToolError::tool_state(
					vformat("The export step of '%s' needs the editor process, which owns the export platforms", preset_name),
					"Call this tool on the editor endpoint (it runs the export itself), or export from the editor and call it "
					"again with skip_export=true to install the APK that is already there");
			Dictionary merged = r_error.data;
			merged["presets_source"] = source;
			merged["missing"] = missing;
			r_error.data = merged;
			return nullptr;
		}
		if (!can_export) {
			r_error = MCPToolError::tool_state(
					vformat("The engine cannot export preset '%s' right now: %s", preset_name,
							can_export_error.is_empty() ? String("EditorExportPlatform::can_export answered false")
														: can_export_error),
					"Install the Android export templates (Editor > Manage Export Templates) and configure the Android SDK "
					"and Java SDK paths (Editor Settings > Export > Android), then call the tool again");
			Dictionary merged = r_error.data;
			merged["presets_source"] = source;
			merged["missing_templates"] = missing_templates;
			add_missing(missing, "android_export",
					can_export_error.is_empty() ? String("EditorExportPlatform::can_export answered false")
												: can_export_error);
			merged["missing"] = missing;
			r_error.data = merged;
			return nullptr;
		}
	}

	// (3) adb and a device.
	bool devices_ran = false;
	String adb_path;
	String devices_output;
	MCPToolError devices_error;
	const Array devices = android_devices(devices_ran, adb_path, devices_output, devices_error);
	if (!devices_ran) {
		if (devices_error.is_error()) {
			r_error = devices_error;
		} else {
			r_error = MCPToolError::tool_state("adb could not be run",
					"Install Android platform-tools or set EditorSettings export/android/android_sdk_path");
		}
		Dictionary merged = r_error.data;
		merged["presets_source"] = source;
		merged["missing"] = missing;
		r_error.data = merged;
		return nullptr;
	}

	Array states;
	String device_serial;
	bool device_usable = false;
	for (int i = 0; i < devices.size(); i++) {
		const Dictionary device = devices[i];
		const String serial = device.get("serial", String());
		const String state = device.get("state", String());
		if (!states.has(state)) {
			states.push_back(state);
		}
		if (!device_id.is_empty()) {
			if (serial == device_id) {
				device_serial = serial;
				device_usable = state == "device";
			}
			continue;
		}
		if (!device_usable && state == "device") {
			device_serial = serial;
			device_usable = true;
		}
	}

	if (!device_id.is_empty() && device_serial.is_empty()) {
		r_error = MCPToolError::not_found(
				vformat("Android device '%s' (adb reports %d connected device(s))", device_id, (int)devices.size()),
				"Call os_list_android_devices to see the device serials adb reports, or omit device_id to use the first "
				"usable device");
		Dictionary merged = r_error.data;
		merged["devices_file"] = String("adb devices -l");
		merged["states"] = states;
		r_error.data = merged;
		return nullptr;
	}
	if (!device_usable) {
		String state_list;
		for (int i = 0; i < states.size(); i++) {
			if (i > 0) {
				state_list += ",";
			}
			state_list += (String)states[i];
		}
		r_error = MCPToolError::tool_state(
				vformat("No Android device in 'device' state is available (adb reports %d device(s), states: %s)",
						(int)devices.size(), state_list),
				"Connect and authorise a device (accept the USB debugging prompt on the device) or start an emulator; "
				"os_list_android_devices shows what adb currently reports");
		Dictionary merged = r_error.data;
		merged["states"] = states;
		merged["device_count"] = devices.size();
		r_error.data = merged;
		return nullptr;
	}

	DeployToAndroidTask *task = memnew(DeployToAndroidTask(preset_name, apk_absolute, export_path, device_serial,
			package_name, adb_path, debug, launch, skip_export));
	task->set_project_dir(ProjectSettings::get_singleton()->globalize_path("res://"));
	return task;
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
		ERR_PRINT("MCPTools: invalid inputSchema literal in os_android_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_os_android_write_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("os_deploy_to_android_device", String::utf8(R"desc(将项目导出并部署到 Android 设备)desc"));
	builder.channel("os").verb("deploy").scope(MCPToolScope::BOTH).mutating(true);
	builder.schema(_schema_from_json(R"schema({"properties":{"debug":{"default":true,"description":"是否以 debug 模式导出","type":"boolean"},"device_id":{"description":"目标设备 serial（可选，部署到第一个可用设备）","type":"string"},"launch":{"default":true,"description":"安装后是否启动应用","type":"boolean"},"preset_name":{"description":"Android 导出预设名称","type":"string"},"skip_export":{"default":false,"description":"是否跳过导出步骤（直接安装已有 APK）","type":"boolean"}},"required":["preset_name"],"type":"object"})schema"));
	builder.pending_handler(_tool_deploy_to_android_device).register_into(r_registry);
}
