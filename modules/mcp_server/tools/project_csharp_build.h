/**************************************************************************/
/*  project_csharp_build.h                                                */
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

#pragma once

#include "../mcp_deferred.h"
#include "tool_builder.h"

#include "core/io/file_access.h"
#include "core/os/os.h"
#include "core/templates/list.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// ---------------------------------------------------------------------------
// TASK-052 (C tier batch 1, DESIGN-DETAIL.md section 26 / GDR-28): the second
// *added* group - `project_build_csharp`, one tool.
//
// The gap it closes (M-2 of REPORT-AUDIT-RACING-BACKLOG): the module could
// create a C# project - `project_set_setting` writes the project name,
// `project_write_text_file` writes the `.csproj` and the `NuGet.config`,
// `project_create_script` writes the `.cs` - but it could not *compile* one, so
// "build a C# project from nothing" stopped one step short.
//
// The engine has no in-process C# compiler outside the mono/GodotSharp runtime,
// so the tool is honest about what it is: it runs the .NET SDK
// (`dotnet build <project.csproj> -c <Configuration> ...`) as a **child
// process** and answers the child's exit code with the output it captured. The
// three engine facts it is built on:
//
//   * the child is started with `OS::execute_with_pipe(path, args, false)`
//     (`core/os/os.h:216`), which is the only `OS` entry point that returns
//     *both* a pid and non-blocking pipes for stdout/stderr
//     (`platform/windows/os_windows.cpp:1284-1409`); the pid is polled with
//     `OS::is_process_running` and can really be killed with `OS::kill`, which
//     is what "a timeout has to kill the child" needs. `OS::execute()` is
//     deliberately not used: it blocks the caller and cannot be interrupted;
//   * "has C# support" is the engine's own fact, read from
//     `ScriptServer::get_language_count()` / `get_language(i)->get_name()`
//     (`core/object/script_language.h:79-80`; `CSharpLanguage::get_name()` is
//     `"C#"`, `modules/mono/csharp_script.cpp:90-92`), not from a version string;
//   * a `.csproj` is found by walking the project directory the way the module's
//     other project readers do, skipping the engine's own hidden directories and
//     MSBuild's `bin`/`obj` output directories.
//
// Deferred (GDR-20): a build takes seconds to minutes, so the tool answers
// across frames (`MCPDeferred::Task::tick()` never blocks) and the transport
// owns the wait. `get_timeout_ms()` declares the caller's `timeout_ms`, which the
// framework can only *shorten* (`mcp_jsonrpc.cpp:245-253`); the task therefore
// also computes the deadline the server will really apply
// (`MCPPendingTimeout::effective_ms`), fires a little before it, kills the child
// and reports `timed_out: true` itself - a caller must learn that *its build*
// was killed, not that "the request expired".
// ---------------------------------------------------------------------------

namespace MCPTools {

// True when this engine build contains a C# script language
// (`ScriptServer` knows a language whose name is `"C#"`).
bool csharp_support_available();

// The absolute path of the `dotnet` executable found on `PATH`, or an empty
// string when there is none. `dotnet.exe` and `dotnet` are both tried on
// Windows; the search is deterministic (the `PATH` order wins) and never runs a
// process.
String find_dotnet_executable();

// TASK-056 (D3, REPORT-AUDIT-ADDED): the `dotnet` path spelled with **one**
// separator. `String::path_join` only recognises a trailing '/'
// (core/string/ustring.cpp:5061), so a PATH entry spelled the way Windows
// spells them (`C:\Program Files\dotnet\`) produced
// `C:\Program Files\dotnet\/dotnet.exe` in the reported `command` field. This
// helper normalizes the directory to the running platform's separator and joins
// with that same separator, so the result is `C:\Program Files\dotnet\dotnet.exe`
// on Windows and `/usr/local/bin/dotnet` on POSIX. `p_windows` is a parameter
// (not read from `OS`) so both branches are doctestable in one process; the
// resolved file and the executed path are the same ones as before.
String csharp_executable_path(const String &p_directory, const String &p_name, bool p_windows);

// The `.csproj` files below the project directory `p_root` (a `res://` path), as
// `res://` paths, sorted, with hidden directories (a name that starts with `.`,
// which is where `.godot` lives) and MSBuild's `bin` / `obj` output directories
// skipped. The walk is bounded by the project tree; a directory that cannot be
// opened is skipped rather than aborting the search.
Array find_csharp_project_files(const String &p_root);

// Validates `extra_args` element by element. A non-string element or an empty
// one is `-32602` naming the index - an empty argument would be dropped by the
// command line builder, which is exactly the silent-ignore shape the module
// refuses.
bool validate_extra_args(const Array &p_extra_args, Vector<String> &r_out, MCPToolError &r_error);

// The real command line of one build, as a string, plus the argument vector the
// child is started with. `-c <configuration>` is always passed, and the caller's
// `extra_args` are appended verbatim and in order.
String csharp_build_command_line(const String &p_dotnet, const String &p_project_absolute,
		const String &p_configuration, const Vector<String> &p_extra_args, List<String> &r_arguments);

// The deadline the transport will really apply to a deferred request:
// `min(requested, MCPPendingTimeout::effective_ms(server setting))`. Exported so
// that the reserve the task subtracts from it can be tested without a server.
int64_t effective_build_timeout_ms(int64_t p_requested_ms);

// One child process with non-blocking stdout / stderr capture.
//
// The capture is bounded (`p_max_capture_bytes` per stream): once the cap is
// reached the pipe is still drained - so the child never blocks on a full pipe -
// but the bytes are discarded and `*_truncated()` says so. Decoding is lenient:
// a byte that cannot be part of a valid UTF-8 sequence becomes `?` and is
// counted, so a build log in the machine's local codepage is still readable
// instead of being cut off at the first offending byte (`String::append_utf8`
// stops there).
class ChildProcess {
public:
	ChildProcess() {}
	~ChildProcess();

	// `OS::execute_with_pipe(p_path, p_arguments, false)`. Returns the engine
	// error; on success `started()` is true and the process can be polled.
	Error start(const String &p_path, const List<String> &p_arguments, int64_t p_max_capture_bytes);

	// Reads everything that is available on both pipes. Never blocks.
	void pump();

	// True while the child is alive. Calling it after the child exited latches
	// the engine's exit code.
	bool is_running();

	// The engine's exit code, or -1 when it is not known (a killed child's code
	// cannot be read back: `OS::kill` removes the process from the engine's map).
	int exit_code() const { return last_exit_code; }

	// Terminates the child. Idempotent; after it returns the child is gone.
	void kill();

	bool started() const { return child_pid != 0; }
	bool kill_called() const { return killed; }
	int64_t pid() const { return (int64_t)child_pid; }

	const String &stdout_text() const { return out_text; }
	const String &stderr_text() const { return err_text; }
	bool stdout_truncated() const { return out_truncated; }
	bool stderr_truncated() const { return err_truncated; }
	int64_t replaced_bytes() const { return replaced; }

private:
	void _drain(const Ref<FileAccess> &p_pipe, String &r_text, int64_t &r_count, bool &r_truncated);

	ProcessID child_pid = 0;
	Ref<FileAccess> stdout_pipe;
	Ref<FileAccess> stderr_pipe;
	// The one 64 KiB read buffer, allocated once per child: `pump()` runs every
	// frame for the whole build.
	Vector<uint8_t> scratch;
	String out_text;
	String err_text;
	int64_t max_capture_bytes = 0;
	int64_t out_bytes = 0;
	int64_t err_bytes = 0;
	int64_t replaced = 0;
	int last_exit_code = -1;
	bool out_truncated = false;
	bool err_truncated = false;
	bool killed = false;
	bool exited = false;
};

} // namespace MCPTools

void register_project_csharp_build_tools(MCPToolRegistry &r_registry);
