/**************************************************************************/
/*  os_android_read.cpp                                                   */
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
#include "os_android_read.h"

#include "android_shared.h"

#include "core/io/json.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-036 section 1: the engine reference behind the one tool.
//
//   * the engine's own Android exporter asks the same question the same way:
//     `OS::execute(adb, ["devices", ...])` with the adb path the editor's
//     Android SDK configuration names
//     (`platform/android/export/export_plugin.cpp:341`,
//     `editor/export/android_sdk_manager.cpp:781`);
//   * the parser is the migration source's (`android.rs:71-103`): blank lines,
//     `List of devices attached` and the `* daemon ...` banners are skipped, the
//     first two whitespace-separated fields are `serial` and `state`, and every
//     later `key:value` pair becomes a member (`model`, `product`, `device`,
//     `transport_id`, ...);
//   * **a device that is not authorised is still a real answer**: adb prints it
//     with `state: unauthorized` and the tool reports it, so a caller can tell
//     "no device" from "a device that needs confirmation on screen".
//   * a machine without adb is a `-32000` refusal naming what to install; it is
//     never an empty `devices` list, which would claim "no devices".
// ---------------------------------------------------------------------------

static Variant _tool_list_android_devices(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;

	const Dictionary environment = android_environment();

	bool ran = false;
	String adb_path;
	String output;
	MCPToolError adb_error;
	const Array devices = android_devices(ran, adb_path, output, adb_error);
	if (!ran) {
		// The process could not be started at all, or adb exited non-zero:
		// `android_devices` filled one of the two refusals.
		if (adb_error.is_error()) {
			r_error = adb_error;
		} else {
			r_error = MCPToolError::tool_state("adb could not be run",
					"Install Android platform-tools or set EditorSettings export/android/android_sdk_path");
		}
		Dictionary merged = r_error.data;
		merged["adb_path"] = adb_path;
		merged["adb_present"] = environment.get("adb_present", false);
		merged["missing"] = environment.get("missing", Array());
		r_error.data = merged;
		return Variant();
	}

	int usable = 0;
	Array states;
	for (int i = 0; i < devices.size(); i++) {
		const Dictionary device = devices[i];
		const String state = device.get("state", String());
		if (state == "device") {
			usable++;
		}
		if (!states.has(state)) {
			states.push_back(state);
		}
	}

	Dictionary out;
	out["devices"] = devices;
	out["count"] = devices.size();
	out["usable_count"] = usable;
	out["states"] = states;
	out["adb_path"] = adb_path;
	out["adb_present"] = environment.get("adb_present", false);
	out["source"] = "adb devices -l";
	if (devices.is_empty()) {
		out["message"] = "adb ran and reported no connected device (connect a device, or start an emulator, and make sure "
						 "adb debugging is enabled)";
	}
	return out;
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character. The tool declares the
// empty object schema, so any argument is refused by the registry's
// unknown-argument gate (TASK-032 D4).
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in os_android_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_os_android_read_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("os_list_android_devices", String::utf8(R"desc(列出已连接的 Android 设备)desc"));
	builder.channel("os").verb("list").scope(MCPToolScope::BOTH).mutating(false);
	builder.schema(_schema_from_json(R"schema({"properties":{},"required":[],"type":"object"})schema"));
	builder.handler(_tool_list_android_devices).register_into(r_registry);
}
