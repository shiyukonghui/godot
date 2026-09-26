/**************************************************************************/
/*  project_read_files.h                                                  */
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

#include "../tool_registry.h"

// B1 group `project_read_files` (the manifest is docs/tool-groups.json):
//
//   project_list_scripts            (migrated from script.rs:68)
//   project_read_script             (migrated from script.rs:73)
//   project_validate_script         (migrated from script.rs:158)
//   project_read_resource           (migrated from resource.rs:75)
//   project_get_resource_preview    (migrated from resource.rs:278)
//   project_read_scene_file_content (migrated from scene.rs:228)
//
// All six are channel `project`, `mutating = false`, `scope = BOTH`, and they
// only ever read the project on disk: no tool of this group may create, modify
// or delete a file - not even a `.uid` or an import sidecar (pinned by the
// doctest "the file readers never write to the project").
//
// This pair of files is the only file the owner of this group edits, plus one
// call line in the shared tools/registration.cpp - which is the whole point of
// the per-group split (TASK-002 section 2.2.1): porting agents never touch the
// same file (PLAYBOOK section 17.1).
void register_project_read_files_tools(MCPToolRegistry &r_registry);

namespace MCPTools {

// ---------------------------------------------------------------------------
// TASK-050 N-2: `project_validate_script` has to be able to tell three
// situations apart, and only one of them is a compilation verdict.
//
// The defect (found by the racing-backlog audit, N-2, and reproduced on 9888
// before this change): the tool resolved the language from the file's extension
// and, when that language was absent, **fell back to GDScript**
// (`project_read_files.cpp`, old `get_language_for_extension("gd")` fallback).
// In a `module_mono_enabled=no` build `get_language_for_extension("cs")` is null,
// so a legitimate C# file was parsed as GDScript and its parser error was
// reported as `{"valid": false, "error_text": "ERR_PARSE_ERROR", "message":
// "Compilation failed..."}` - "this build has no C# backend" was published as
// "your script does not compile".
//
// The classification below is the whole decision, and it is a pure function so
// that every combination is testable in a process that has no language at all
// (the `--test` process, where `ScriptServer::init_languages()` was never
// called):
//
//   * no script language server      -> STRUCTURAL: the documented bracket check
//     (unreachable in a real editor/game process, which always initialises its
//     languages; it is what the doctest process can observe);
//   * a server, but not for `ext`    -> LANGUAGE_UNAVAILABLE: honest refusal,
//     never a borrowed verdict;
//   * a server that has `ext`        -> COMPILE: the real `reload()`.
// ---------------------------------------------------------------------------
enum class MCPValidateScriptMode {
	COMPILE,
	LANGUAGE_UNAVAILABLE,
	STRUCTURAL,
};

MCPValidateScriptMode classify_validate_script_mode(bool p_languages_initialized, bool p_language_found);

// The honest refusal of the LANGUAGE_UNAVAILABLE case: `-32000` (GDR-14, "the
// call is well formed but this build cannot serve it") with `data.suggestion`.
// It carries no `valid` field at all: a script that was never parsed must not be
// answered with a verdict, and `valid: null` would be read as `false` by every
// client that tests the field for truth.
MCPToolError validate_script_language_unavailable_error(const String &p_path, const String &p_extension);

// TASK-056 (D1, `REPORT-AUDIT-ADDED.md`): the engine basis of the
// `language_unavailable` classification, published as the batch item's `reason`
// - the same shape `unverifiable` / `not_compiled` already use. The batch tool
// cannot refuse per file, so "this build has no backend for that extension"
// travels as `valid: null` + `category` + `reason`; it is never `valid: false`,
// which is the verdict "it does not compile" (TASK-050 N-2).
String validate_script_language_unavailable_reason(const String &p_path, const String &p_extension);

// ---------------------------------------------------------------------------
// TASK-055 (D112): the C# compile verdict, and the one residual "no verdict".
//
// TASK-054 had to *stop* answering for `.cs`: `CSharpScript::reload()` returns
// `OK` unconditionally (the only `return` in its body) and never parses the
// string `set_source_code()` was handed, so a broken `.cs` used to be published
// as `{"valid": true, "message": "Script compiles successfully"}`.
// The engine now carries a second, honest signal (TASK-055's patch:
// `CSharpScript::is_source_newer_than_assembly()`, `modules/mono/csharp_script.h`,
// the same comparison `_update_exports()` already made for the editor's
// placeholders, exposed as a public read-only accessor), and the already public
// `Script::is_script_valid()` (`core/object/script_language.h:180`, overridden by
// `CSharpScript` with the old private `valid` field) says whether the loaded
// assembly holds a class for this script's path. Together they separate:
//
//   * `ok`           - the loaded assembly contains a build of this exact source
//                      (class found, file not modified after the assembly);
//   * `invalid`      - a build **this MCP server ran** rejected this file and the
//                      file has not changed since (`project_build_csharp` records
//                      the per-file diagnostics, `tools/csharp_verdict.h`), so
//                      `error_text` carries the compiler's own text;
//   * `not_compiled` - no build of this source is loaded and none was recorded
//                      as rejecting it: "it was edited after the last build" or
//                      "no class for this path is in the assembly". This is
//                      deliberately **not** `invalid`: the engine has no C#
//                      compiler, so "nothing compiled it" must never be
//                      published as "it does not compile";
//   * `unverifiable` - the engine could not be asked at all (the file did not
//                      load as a `Script` resource); no `valid` is published.
// ---------------------------------------------------------------------------

// The engine basis of the `unverifiable` classification - the residual case
// where even the two signals above could not be read - as one sentence: the
// `reason` a batch item carries so the caller can check the claim at its source.
String validate_script_unverifiable_reason(const String &p_path);

// The singular tool's refusal for the `unverifiable` case: `-32000` with
// `data.suggestion`, carrying no `valid` field whatsoever.
MCPToolError validate_script_unverifiable_error(const String &p_path);

// The engine basis of the `not_compiled` classification: which of the two
// signals says "no build of this source is loaded", plus why the engine cannot
// turn that into a failure verdict on its own.
String validate_script_not_compiled_reason(bool p_class_loaded, bool p_source_newer_than_assembly);

// The singular tool's refusal for the `not_compiled` case (`-32000` with
// `data.suggestion`): the file was not compiled, which is a different answer
// from "it does not compile" and therefore cannot be a `valid: false` payload.
MCPToolError validate_script_not_compiled_error(const String &p_path, bool p_class_loaded, bool p_source_newer_than_assembly);

// The `error_text` of a recorded C# build failure: the diagnostics themselves
// (compiler text, never an invented `ERR_*`), joined and capped.
String csharp_recorded_error_text(const Array &p_errors);

// The `message` of a recorded C# build failure: names the tool that produced the
// record and the file the compiler rejected.
String csharp_recorded_failure_message(const String &p_path, const Array &p_errors);

// ---------------------------------------------------------------------------
// TASK-053 section 2.1: the per-file verdict of the two validate tools.
//
// `project_validate_script` answers one file and can put the refusal in the
// JSON-RPC error (a language this build does not contain is `-32000`, TASK-050
// N-2). `project_validate_scripts` answers *many* files, so it cannot: one file
// of a batch must not delete the verdict of the others, and the three categories
// it publishes (`ok` / `invalid` / `language_unavailable`) have to account for
// every file it was asked about. Both tools therefore share this one decision,
// and "is this file valid" has exactly one definition in the module.
//
// `category` is the wire spelling of `MCPValidateScriptCategory`; `valid` is a
// real verdict only in the `ok` / `invalid` cases (`language_unavailable` is
// never a `false`, for the same reason the single tool refuses instead of
// answering `valid: false`).
//
// The one case that keeps the *single* tool's documented behaviour: a process
// with no initialised script language at all (the `--test` process) still runs
// the bracket-balance fallback, and its `message` says so. A batch item that
// took that path is categorised by its bracket result so that the four
// counters stay exhaustive, and its `message` carries the same disclaimer the
// single tool publishes.
// ---------------------------------------------------------------------------
struct MCPValidateScriptVerdict {
	// The extension the verdict was made with, exactly as `file_extension()`
	// spells it (case preserved); empty when the file has no extension.
	String language;
	// "ok" | "invalid" | "language_unavailable" | "not_compiled" | "unverifiable".
	String category;
	bool valid = false;
	// Present only for an `invalid` verdict: the engine's `ERR_*` identifier for
	// a language that compiles through `reload()`, or (TASK-055) the recorded C#
	// compiler's own diagnostic text - never an invented identifier.
	String error_text;
	String message;
	// TASK-054/TASK-055/TASK-056: present for every category that cannot carry a
	// verdict (`unverifiable` / `not_compiled` / `language_unavailable`) - the
	// engine basis (`file:line` + behaviour) of "no verdict is possible here".
	String reason;
};

// `p_path` must already be normalized and exist; `p_source` is its text.
MCPValidateScriptVerdict validate_script_source(const String &p_path, const String &p_source);

// The C# verdict itself (TASK-055). Only reachable in a build that contains the
// C# backend (the branch is taken when `ScriptServer` resolves `.cs` to the `C#`
// language); the policy it applies is the pure `MCPTools::classify_csharp_verdict`
// (`tools/csharp_verdict.h`), which is doctested in this build too.
MCPValidateScriptVerdict validate_csharp_script_source(const String &p_path);

// The singular tool's refusal for the two categories that cannot be a payload
// (`unverifiable` / `not_compiled`): `-32000` with `data.suggestion`, built from
// the verdict itself so the single-file and the batch answer carry the same
// sentences (TASK-055 moved `not_compiled` here; TASK-054 had `unverifiable`).
MCPToolError validate_script_verdict_refusal(const String &p_path, const MCPValidateScriptVerdict &p_verdict);

} // namespace MCPTools
