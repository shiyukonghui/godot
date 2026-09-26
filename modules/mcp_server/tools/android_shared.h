/**************************************************************************/
/*  android_shared.h                                                      */
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
#pragma once

#include "tool_builder.h"

#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// ---------------------------------------------------------------------------
// TASK-036 (B5 batch 4): the engine-facing helpers the four export/Android
// groups share (`project_export_read` 2, `project_android_read` 1,
// `os_android_read` 1, `os_android_write` 1).
//
// They are *not* a fifth group: no tool is registered here.
//
// The engine's own model is the design basis (GDR-23), and it has **two
// layers** for everything Android/export:
//
//   * **the project file** `res://export_presets.cfg`, readable in *both*
//     processes with `ConfigFile` (`core/io/config_file.h`); sections are
//     `preset.N` and `preset.N.options`, and the migration source read exactly
//     those (`godot_mcp_gdext/src/commands/export.rs:44-80`,
//     `android.rs:106-159`). That is the honest fallback for a game process,
//     which has no editor at all;
//   * **the editor's own state**, when this process *is* the editor: the engine
//     has already parsed the presets into `EditorExportPreset` objects
//     (`EditorExport::get_export_preset`, `editor/export/editor_export.h:84`)
//     and knows whether a platform can really export a preset
//     (`EditorExportPlatform::can_export`, `editor/export/editor_export_platform.h:360`,
//     which fills the engine's own error text and a `missing_templates` flag).
//     That is the capability evidence the Android tools report - not a guess.
//   * **the Android SDK**: `AndroidSDKManager::is_android_sdk_setup` /
//     `is_java_sdk_setup` (`editor/export/android_sdk_manager.cpp:662/698`)
//     answer whether a path from `EditorSettings` really holds the packages the
//     engine's exporter needs, and `AndroidSDKManager::get_adb_path()`
//     (`:781`) is the adb the exporter itself would run. Both are editor-only
//     (they read `EditorSettings`), which is why every caller of the capability
//     probe reports "this is only knowable in an editor process" instead of
//     inventing an answer.
//   * **the device list** is `adb devices -l`, the transport the engine's own
//     Android exporter uses (`platform/android/export/export_plugin.cpp:341`).
//     Its output is parsed here, and the transport stays honest about a missing
//     adb: a tool that cannot run it answers `-32000` with what to install.
// ---------------------------------------------------------------------------

namespace MCPTools {

// `res://export_presets.cfg`, the one path every export read addresses.
String export_presets_path();

// The project's export presets, in the engine's own order, as
// `[{index, name, platform, runnable, export_path, android_package_name,
//    custom_features}]`.
//
// `r_source` is `"editor_export"` when the engine's loaded
// `EditorExportPreset` objects answered (an editor process) and
// `"export_presets.cfg"` otherwise. `r_file_present` is false when the project
// has no readable `export_presets.cfg`; the array is then empty and `r_reason`
// says why - a preset is never invented.
Array export_presets_read(const String &p_presets_path, String &r_source, bool &r_file_present, String &r_reason);

// The first preset whose `platform` is exactly `Android`.
//
// `p_name` (when non-empty) selects by name and `p_index` (when >= 0) selects by
// the preset's position in the whole list; both filters are applied together, so
// a name that is not an Android preset is not found rather than silently
// skipped. `r_found` is false when nothing matched, and the caller decides
// whether that is `-32000` (no Android preset configured) or `-32001` (a named
// preset that does not exist).
Dictionary android_preset_find(const String &p_presets_path, const String &p_name, int64_t p_index,
		bool &r_found, bool &r_file_present, String &r_source, String &r_reason);

// Everything about this machine that the Android tools depend on:
//
//   `{editor_process, editor_settings_available, android_sdk_path,
//     android_sdk_path_present, android_sdk_ready, android_sdk_error,
//     java_sdk_path, java_sdk_path_present, java_sdk_ready, java_sdk_error,
//     debug_keystore, debug_keystore_present, adb_path, adb_present, missing[]}`
//
// `missing` carries one `{capability, detail}` per unavailable piece, so a
// refusal can name exactly what is absent and how to install it. The values come
// from `EditorSettings` and the engine's own `AndroidSDKManager` probes; a
// non-editor process reports `editor_settings_available: false` and no
// fabricated paths.
Dictionary android_environment();

// The adb the tools run: `AndroidSDKManager::get_adb_path()` when it exists on
// disk, the bare name `adb` (resolved through `PATH` by `OS::execute`)
// otherwise. Never empty.
String android_adb_path();

// Runs one process and waits for it (the engine's own Android exporter blocks on
// adb the same way, `platform/android/export/export_plugin.cpp:341/2375`).
// `r_output` receives stdout (and stderr, which `OS::execute` merges when
// `p_read_stderr` is true). `r_ran` is false when the process could not be
// started at all, with `r_error` naming the engine error.
bool run_process_capture(const String &p_path, const List<String> &p_arguments, String &r_output,
		int &r_exit_code, bool &r_ran, MCPToolError &r_error);

// `adb <arguments>` through `run_process_capture`.
bool adb_run(const Vector<String> &p_arguments, String &r_output, int &r_exit_code, String &r_adb_path,
		bool &r_ran, MCPToolError &r_error);

// `adb devices -l` output -> `[{serial, state, model, product, device, ...}]`.
// The parser is the migration source's (`android.rs:71-103`) and it is exported
// so the doctest pins the real function: the header line, the daemon banners and
// blank lines are skipped, the first two fields are the serial and its state,
// and every later `key:value` pair becomes a member.
Array parse_adb_devices(const String &p_output);

// The `adb devices -l` device list of this machine. `r_ran` false when adb could
// not be executed at all (the caller refuses honestly instead of answering an
// empty list, which would claim "no devices" for "cannot ask").
Array android_devices(bool &r_ran, String &r_adb_path, String &r_output, MCPToolError &r_error);

// True when a preset the engine can really export exists for the Android
// platform, with the engine's own `can_export` answer. Editor-only: in a game
// process `r_checked` is false and the caller must not treat that as "cannot".
bool android_can_export(const Dictionary &p_preset, bool p_debug, bool &r_checked, String &r_error_text,
		bool &r_missing_templates);

// The export platforms this build registered, as `[{name, os}]`. `r_available`
// is false outside an editor process (the engine's platform registry lives in
// `EditorExport`, `editor/export/editor_export.h:79`), which is the honest
// answer for a game process - not an empty list of platforms.
Array export_platforms_read(bool &r_available);

} // namespace MCPTools
