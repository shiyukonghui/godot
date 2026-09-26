/**************************************************************************/
/*  csharp_verdict.h                                                      */
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

#pragma once

#include "core/string/ustring.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

namespace MCPTools {

// ---------------------------------------------------------------------------
// TASK-055 (decision D112): the C# compile verdict.
//
// Why this file exists: the engine has **no C# compiler** on the native side.
// `CSharpScript::reload()` looks the type up in the .NET assembly that was
// already built and returns `OK` unconditionally, so "does this `.cs` file
// compile?" cannot be answered from it (TASK-054 measured that the answer used
// to be a silent `valid: true` for a file with a syntax error). The two truths
// that *can* be read are:
//
//   * `Script::is_script_valid()` - the loaded assembly contains a class for
//     this script path (public since before this task, in
//     `core/object/script_language.h:180`);
//   * `CSharpScript::is_source_newer_than_assembly()` - the file on disk is
//     newer than the assembly that is loaded, i.e. the assembly does *not*
//     contain a build of this source (TASK-055's engine patch: the same
//     comparison `CSharpScript::_update_exports()` already made for the
//     editor's placeholders, exposed as a public read-only accessor).
//
// Those two answer "compiled / not compiled". They cannot answer *why* a file
// that is not compiled does not compile - the diagnostic text is produced by
// MSBuild inside `GodotTools`' build pipeline
// (`modules/mono/editor/GodotTools/GodotTools.BuildLogger/GodotBuildLogger.cs:82,89`
// writes it to `msbuild_issues.csv`, and it never reaches the engine), so the
// project-level half of the verdict comes from the record this module writes
// when *its own* build tool runs: `project_build_csharp` captures the compiler
// output and the per-file diagnostics are stored here, with the modification
// time of each file at the moment of the build. That extra timestamp is what
// keeps "it failed to compile" apart from "it was edited after that build": a
// diagnostic is only applied while the file still has the bytes it had when
// the compiler rejected it.
// ---------------------------------------------------------------------------

// The policy, as a pure function so it can be doctested in a build without the
// C# backend (where the live branch is unreachable, documented in the report).
enum class MCPCSharpVerdict {
	// The loaded assembly contains a build of this file's current source.
	COMPILED,
	// A recorded build of this module rejected this file and the file has not
	// changed since that build: this is `invalid` plus the compiler's own text.
	BUILD_FAILED,
	// Nothing compiled this source: no class for it in the loaded assembly, or
	// the file was modified after the assembly was built, and no recorded build
	// rejected the file as it is now. This is **not** a compile failure.
	NOT_COMPILED,
};

MCPCSharpVerdict classify_csharp_verdict(bool p_class_loaded, bool p_source_newer_than_assembly, bool p_has_recorded_errors);

// ---------------------------------------------------------------------------
// The project-level record of the last `project_build_csharp` run.
//
// `user://mcp_csharp_build_state.json` (the same user-visible convention
// `editor_get_test_report` uses for `user://mcp_test_report.json`), so both the
// editor and the game process of one project read the same record.
// ---------------------------------------------------------------------------

// One entry per compiler diagnostic, parsed out of the captured output:
// `{"file": <res:// path or the absolute path as printed>, "line": <int>,
//   "column": <int>, "code": <string>, "text": <the diagnostic line verbatim>}`.
// Bounded (see the constants in the .cpp): the text is what a caller reads.
Array parse_csharp_build_errors(const String &p_output);

String csharp_build_record_path();

// Overwrites the record with one run's outcome. A failure to write is not an
// error for the build tool (the build itself already happened); it is reported
// with `print_verbose` and the record simply stays as it was.
void write_csharp_build_record(const String &p_configuration, const Array &p_project_files,
		int64_t p_exit_code, bool p_timed_out, const Array &p_errors, bool p_truncated);

// The whole record, or an empty Dictionary when there is none.
Dictionary read_csharp_build_record();

// The recorded diagnostics that still apply to `p_path`: same file, and the
// file still has the modification time it had when that build ran. A recorded
// diagnostic for a file that was edited afterwards does **not** apply - that is
// exactly the distinction between "failed to compile" and "changed since the
// last build".
Array recorded_csharp_build_errors(const String &p_path);

} // namespace MCPTools
