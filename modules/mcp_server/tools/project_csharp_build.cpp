/**************************************************************************/
/*  project_csharp_build.cpp                                              */
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
#include "project_csharp_build.h"

#include "../mcp_server.h"
#include "csharp_verdict.h"
#include "tool_helpers.h"

#include "core/config/project_settings.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/object/script_language.h"

#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/editor_interface.h"
#include "editor/file_system/editor_file_system.h"
#endif

using namespace MCPTools;

namespace {

Dictionary _suggestion(const String &p_text) {
	Dictionary data;
	data["suggestion"] = p_text;
	return data;
}

// ---------------------------------------------------------------------------
// Lenient UTF-8 decoding.
//
// `String::utf8()` decodes through `String::append_utf8()`, which *stops* at the
// first byte that cannot continue a sequence (`core/string/ustring.cpp`) - so a
// build log in the machine's local codepage, or a log whose last multi-byte
// character was cut by the capture cap, would lose everything after that byte.
// A byte that cannot be part of a valid sequence becomes `?` instead and is
// counted, so the answer says how much of the capture was not UTF-8 rather than
// silently dropping it.
// ---------------------------------------------------------------------------
void _append_utf8_lossy(String &r_text, int64_t &r_replaced, const uint8_t *p_data, int64_t p_size) {
	int64_t i = 0;
	while (i < p_size) {
		const uint8_t lead = p_data[i];
		int extra = 0;
		uint32_t code_point = 0;
		if (lead < 0x80) {
			extra = 0;
			code_point = lead;
		} else if ((lead & 0xE0) == 0xC0) {
			extra = 1;
			code_point = lead & 0x1F;
		} else if ((lead & 0xF0) == 0xE0) {
			extra = 2;
			code_point = lead & 0x0F;
		} else if ((lead & 0xF8) == 0xF0) {
			extra = 3;
			code_point = lead & 0x07;
		} else {
			r_text += "?";
			r_replaced++;
			i++;
			continue;
		}
		if (i + extra >= p_size) {
			// The capture ended in the middle of a sequence (or the process was
			// killed mid-write): every remaining byte is undecodable.
			r_text += "?";
			r_replaced += p_size - i;
			break;
		}
		bool continuation_ok = true;
		for (int k = 1; k <= extra; k++) {
			const uint8_t next = p_data[i + k];
			if ((next & 0xC0) != 0x80) {
				continuation_ok = false;
				break;
			}
			code_point = (code_point << 6) | (next & 0x3F);
		}
		const bool overlong = (extra == 1 && code_point < 0x80) ||
				(extra == 2 && code_point < 0x800) ||
				(extra == 3 && code_point < 0x10000);
		const bool surrogate = code_point >= 0xD800 && code_point <= 0xDFFF;
		if (!continuation_ok || overlong || surrogate || code_point > 0x10FFFF) {
			r_text += "?";
			r_replaced++;
			i++;
			continue;
		}
		r_text += String::chr((char32_t)code_point);
		i += 1 + extra;
	}
}

// A best-effort editor filesystem notification, the same one `project_script_write`
// and `project_shader_write` use: a build writes `bin/` / `obj/` next to the
// project, and the editor only records what its own scan has seen. It can never
// fail the call - in a game process, or without an `EditorInterface`, the honest
// answer is `rescanned: false`.
bool _notify_editor_of_new_files() {
#ifdef MCP_EDITOR_TOOLS_ENABLED
	if (!is_editor_process()) {
		return false;
	}
	EditorInterface *editor = EditorInterface::get_singleton();
	EditorFileSystem *filesystem = editor != nullptr ? editor->get_resource_filesystem() : nullptr;
	if (filesystem == nullptr) {
		return false;
	}
	filesystem->scan();
	return true;
#else
	return false;
#endif
}

// The capture cap, per stream and per project. A build log that matters is far
// smaller; a log that does not fit is reported as truncated instead of being
// allowed to grow the answer without bound.
const int64_t MAX_CAPTURE_BYTES_PER_STREAM = 65536;

// How much earlier than the transport's deadline this task fires. The transport
// checks its deadline *before* it ticks the task
// (`mcp_deferred.cpp:126-137`), so a task that wants to answer `timed_out: true`
// itself has to be strictly earlier. 400 ms is several frames at any frame rate
// the editor runs at and is still inside the 1000 ms minimum the schema allows.
const int64_t TIMEOUT_RESERVE_MS = 400;

// ---------------------------------------------------------------------------
// The deferred task: one `dotnet build` per discovered `.csproj`, in order.
//
// `tick()` never blocks: it reads whatever the pipes already hold and returns
// `PENDING` while the child is alive. When the process is gone (or the deadline
// has passed) the captured output and the exit code are recorded and the next
// project starts - or the request is answered. A timeout kills the child
// *inside* `tick()` and is reported as `timed_out: true` with `exit_code: -1`
// (a killed child's code is not readable: `OS::kill` removes the process from
// the engine's map), never as a successful build.
// ---------------------------------------------------------------------------
class CSharpBuildTask : public MCPDeferred::Task {
public:
	CSharpBuildTask(const String &p_dotnet, const Array &p_projects, const String &p_configuration,
			const Vector<String> &p_extra_args, int64_t p_requested_timeout_ms, int64_t p_effective_timeout_ms,
			bool p_rescan, const String &p_project_root) :
			dotnet(p_dotnet),
			configuration(p_configuration),
			extra_args(p_extra_args),
			requested_timeout_ms(p_requested_timeout_ms),
			effective_timeout_ms(p_effective_timeout_ms),
			rescan(p_rescan),
			project_root(p_project_root) {
		for (int i = 0; i < p_projects.size(); i++) {
			projects.push_back(p_projects[i]);
		}
		// Our own deadline, strictly before the transport's (see the constant).
		deadline_ms = effective_timeout_ms > TIMEOUT_RESERVE_MS + 1
				? effective_timeout_ms - TIMEOUT_RESERVE_MS
				: effective_timeout_ms;
	}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_frame;
		if (start_ms == 0) {
			start_ms = (int64_t)p_now_ms;
		}
		const int64_t elapsed = (int64_t)p_now_ms - start_ms;

		if (!timed_out && !running) {
			const MCPDeferred::TickResult started = _start_current();
			if (started.state != MCPDeferred::State::PENDING) {
				return started;
			}
			return MCPDeferred::TickResult::pending();
		}

		child.pump();
		if (child.is_running()) {
			if (elapsed >= deadline_ms) {
				// Drain what is already in the pipes before the kill, then kill
				// for real: the deadline is not "stop waiting", it is "stop the
				// build".
				child.pump();
				child.kill();
				timed_out = true;
				_absorb();
				return MCPDeferred::TickResult::done(_payload(elapsed));
			}
			return MCPDeferred::TickResult::pending();
		}

		// The child is gone: collect the tail of both pipes and its exit code.
		child.pump();
		_absorb();
		const int exit = child.exit_code();
		exit_codes.push_back((int64_t)exit);
		if (exit != 0 && overall_exit == 0) {
			overall_exit = exit;
		}
		running = false;
		project_index++;
		if (project_index < projects.size()) {
			return MCPDeferred::TickResult::pending();
		}
		return MCPDeferred::TickResult::done(_payload(elapsed));
	}

	uint64_t get_timeout_ms() const override { return (uint64_t)requested_timeout_ms; }

	String describe() const override {
		return vformat("dotnet build of %d project file(s)", projects.size());
	}

private:
	MCPDeferred::TickResult _start_current() {
		const String res_path = projects[project_index];
		const String absolute = ProjectSettings::get_singleton()->globalize_path(res_path);
		List<String> arguments;
		const String command = csharp_build_command_line(dotnet, absolute, configuration, extra_args, arguments);
		commands.push_back(command);
		project_files.push_back(res_path);

		const Error error = child.start(dotnet, arguments, MAX_CAPTURE_BYTES_PER_STREAM);
		if (error != OK) {
			return MCPDeferred::TickResult::failed(MCPToolError::tool_state(
					vformat("Could not start the .NET SDK ('%s') for '%s'", dotnet, res_path),
					"Check that 'dotnet' is really executable (run 'dotnet --version' in a shell on this machine) and that this process may start children"));
		}
		running = true;
		return MCPDeferred::TickResult::pending();
	}

	// Appends one project's captured output to the run's answer. The per-project
	// header is only added when there is more than one project, so a single
	// project's output stays byte-for-byte the child's own.
	void _absorb() {
		if (projects.size() > 1) {
			stdout_text += vformat("== %s ==\n", projects[project_index]);
		}
		stdout_text += child.stdout_text();
		stderr_text += child.stderr_text();
		out_truncated = out_truncated || child.stdout_truncated();
		err_truncated = err_truncated || child.stderr_truncated();
		replaced_bytes += child.replaced_bytes();
	}

	Dictionary _payload(int64_t p_elapsed_ms) {
		// TASK-055 (D112): leave the project-level half of the C# verdict behind.
		// The engine cannot know *why* a C# file does not compile (there is no C#
		// compiler in the engine, see `tools/csharp_verdict.h`), so the per-file
		// diagnostics of this run are recorded here and `project_validate_script`
		// / `project_validate_scripts` read them: "the last build this server ran
		// rejected this file" is a truth a caller can act on, and it is only
		// asserted while the file still has the bytes it had at that build.
		// Recording is a side effect of the run, never of the answer: the payload
		// below is built exactly as it was before.
		{
			const Array errors = parse_csharp_build_errors(stdout_text + "\n" + stderr_text);
			write_csharp_build_record(configuration, project_files,
					(int64_t)(timed_out ? -1 : overall_exit), timed_out, errors,
					out_truncated || err_truncated);
		}

		Dictionary out;
		out["exit_code"] = (int64_t)(timed_out ? -1 : overall_exit);
		out["stdout"] = stdout_text;
		out["stderr"] = stderr_text;
		out["duration_ms"] = p_elapsed_ms;
		out["command"] = commands.is_empty() ? String() : String(commands[0]);
		out["commands"] = commands;
		out["project_files"] = project_files;
		out["exit_codes"] = exit_codes;
		out["rescanned"] = rescan ? _notify_editor_of_new_files() : false;
		out["timed_out"] = timed_out;
		out["killed"] = child.kill_called();
		out["stdout_truncated"] = out_truncated;
		out["stderr_truncated"] = err_truncated;
		out["non_utf8_bytes"] = replaced_bytes;
		out["timeout_ms"] = requested_timeout_ms;
		out["effective_timeout_ms"] = effective_timeout_ms;
		out["project_root"] = project_root;
		return out;
	}

	String dotnet;
	Vector<String> projects;
	String configuration;
	Vector<String> extra_args;
	int64_t requested_timeout_ms = 0;
	int64_t effective_timeout_ms = 0;
	int64_t deadline_ms = 0;
	bool rescan = true;
	String project_root;

	int64_t start_ms = 0;
	int project_index = 0;
	bool running = false;
	bool timed_out = false;
	int overall_exit = 0;

	ChildProcess child;
	String stdout_text;
	String stderr_text;
	bool out_truncated = false;
	bool err_truncated = false;
	int64_t replaced_bytes = 0;
	Array exit_codes;
	Array commands;
	Array project_files;
};

} // namespace

namespace MCPTools {

bool csharp_support_available() {
	const int count = ScriptServer::get_language_count();
	for (int i = 0; i < count; i++) {
		ScriptLanguage *language = ScriptServer::get_language(i);
		if (language != nullptr && language->get_name() == "C#") {
			return true;
		}
	}
	return false;
}

String csharp_executable_path(const String &p_directory, const String &p_name, bool p_windows) {
	// TASK-056 (D3): one spelling for the whole path. The directory is
	// normalized to this platform's separator first (Windows: '/', from a
	// forward-spelled PATH entry, becomes '\'; POSIX: the reverse), then the
	// trailing separators are dropped, then exactly one is inserted. The result
	// names the same file the old `path_join` expression did - it only stops
	// printing two separators at the junction.
	String directory = p_directory.strip_edges();
	directory = p_windows ? directory.replace("/", "\\") : directory.replace("\\", "/");
	const String separator = p_windows ? "\\" : "/";
	while (!directory.is_empty() && directory.ends_with(separator)) {
		directory = directory.substr(0, directory.length() - 1);
	}
	if (directory.is_empty()) {
		return p_name;
	}
	return directory + separator + p_name;
}

String find_dotnet_executable() {
	OS *os = OS::get_singleton();
	if (os == nullptr) {
		return String();
	}
	const String path_variable = os->get_environment("PATH");
	if (path_variable.strip_edges().is_empty()) {
		return String();
	}
	const bool windows = os->get_name() == "Windows";
	const String separator = windows ? ";" : ":";
	Vector<String> candidates;
	if (windows) {
		candidates.push_back("dotnet.exe");
	}
	candidates.push_back("dotnet");

	const Vector<String> directories = path_variable.split(separator);
	for (int i = 0; i < directories.size(); i++) {
		const String directory = directories[i].strip_edges();
		if (directory.is_empty()) {
			continue;
		}
		for (int j = 0; j < candidates.size(); j++) {
			const String candidate = csharp_executable_path(directory, candidates[j], windows);
			if (FileAccess::exists(candidate)) {
				return candidate;
			}
		}
	}
	return String();
}

Array find_csharp_project_files(const String &p_root) {
	Vector<String> directories;
	directories.push_back(p_root);
	Vector<String> found;
	while (!directories.is_empty()) {
		const String current = directories[directories.size() - 1];
		directories.remove_at(directories.size() - 1);
		Ref<DirAccess> dir = DirAccess::open(current);
		if (dir.is_null()) {
			continue;
		}
		Vector<String> subdirectories;
		dir->list_dir_begin();
		while (true) {
			const String entry = dir->get_next();
			if (entry.is_empty()) {
				break;
			}
			if (entry == "." || entry == "..") {
				continue;
			}
			const String full = current.path_join(entry);
			if (!dir->current_is_dir()) {
				if (entry.get_extension().to_lower() == "csproj") {
					found.push_back(full);
				}
				continue;
			}
			// A hidden directory is the engine's own (`.godot`, `.git`), and
			// `bin` / `obj` hold MSBuild's *output*: a `.csproj` copied in there is
			// not a project to build.
			const String lowered = entry.to_lower();
			if (entry.begins_with(".") || lowered == "bin" || lowered == "obj") {
				continue;
			}
			subdirectories.push_back(full);
		}
		dir->list_dir_end();
		for (int i = 0; i < subdirectories.size(); i++) {
			directories.push_back(subdirectories[i]);
		}
	}
	found.sort();
	Array out;
	for (int i = 0; i < found.size(); i++) {
		out.push_back(found[i]);
	}
	return out;
}

bool validate_extra_args(const Array &p_extra_args, Vector<String> &r_out, MCPToolError &r_error) {
	for (int i = 0; i < p_extra_args.size(); i++) {
		const Variant element = p_extra_args[i];
		if (element.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'extra_args[%d]' must be a string, got %s",
					(int64_t)i, Variant::get_type_name(element.get_type())));
			return false;
		}
		const String text = element;
		if (text.is_empty()) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'extra_args[%d]' must not be empty: an empty command-line argument would be dropped",
					(int64_t)i));
			return false;
		}
		r_out.push_back(text);
	}
	return true;
}

String csharp_build_command_line(const String &p_dotnet, const String &p_project_absolute,
		const String &p_configuration, const Vector<String> &p_extra_args, List<String> &r_arguments) {
	r_arguments.clear();
	r_arguments.push_back("build");
	r_arguments.push_back(p_project_absolute);
	r_arguments.push_back("-c");
	r_arguments.push_back(p_configuration);
	for (int i = 0; i < p_extra_args.size(); i++) {
		r_arguments.push_back(p_extra_args[i]);
	}

	String command = p_dotnet;
	for (const String &argument : r_arguments) {
		command += " ";
		command += argument.find(" ") >= 0 ? String("\"") + argument + String("\"") : argument;
	}
	return command;
}

// The pipe `OS::execute_with_pipe()` hands back (`{"stdio": <FileAccess>,
// "stderr": <FileAccess>, "pid": <int>}`). A missing member is not an error here:
// a platform whose `execute_with_pipe` answered only a pid would still be
// polled and killed correctly, it would just capture nothing.
static Ref<FileAccess> _pipe_from(const Variant &p_value) {
	if (p_value.get_type() != Variant::OBJECT) {
		return Ref<FileAccess>();
	}
	return Ref<FileAccess>(Object::cast_to<FileAccess>(p_value.operator Object *()));
}

int64_t effective_build_timeout_ms(int64_t p_requested_ms) {
	const MCPServer *server = MCPServer::get_singleton();
	const int configured = server != nullptr ? server->get_pending_timeout_ms() : MCPPendingTimeout::DEFAULT_MS;
	const int64_t ceiling = (int64_t)MCPPendingTimeout::effective_ms(configured);
	if (p_requested_ms <= 0) {
		return ceiling;
	}
	return MIN(p_requested_ms, ceiling);
}

// ---------------------------------------------------------------------------
// ChildProcess
// ---------------------------------------------------------------------------

ChildProcess::~ChildProcess() {
	// The one guarantee that survives every way a task can be dropped (the
	// transport's own timeout, a dead connection, a shutdown): the child this
	// process started is not left running. `tick()` normally kills it and reports
	// `timed_out`; this is the safety net behind that.
	kill();
}

Error ChildProcess::start(const String &p_path, const List<String> &p_arguments, int64_t p_max_capture_bytes) {
	if (child_pid != 0) {
		return ERR_ALREADY_IN_USE;
	}
	OS *os = OS::get_singleton();
	if (os == nullptr) {
		return ERR_UNAVAILABLE;
	}
	max_capture_bytes = p_max_capture_bytes;
	scratch.resize(65536);

	const Dictionary info = os->execute_with_pipe(p_path, p_arguments, false);
	int64_t reported_pid = 0;
	const Variant pid_value = info.get("pid", Variant());
	if (info.is_empty() || !integral_value(pid_value, reported_pid) || reported_pid <= 0) {
		return FAILED;
	}
	child_pid = (ProcessID)reported_pid;

	stdout_pipe = _pipe_from(info.get("stdio", Variant()));
	stderr_pipe = _pipe_from(info.get("stderr", Variant()));
	return OK;
}

void ChildProcess::_drain(const Ref<FileAccess> &p_pipe, String &r_text, int64_t &r_count, bool &r_truncated) {
	if (p_pipe.is_null()) {
		return;
	}
	// `get_buffer()` is the only read that does not first ask `PeekNamedPipe`:
	// the pipe was opened non-blocking (`open_existing(..., p_blocking=false)` sets
	// `PIPE_NOWAIT`, drivers/windows/file_access_windows_pipe.cpp:48-52), so an
	// empty pipe answers 0 immediately. `get_length()` reports an ERROR line of
	// its own once the writing end is gone, which is exactly the moment the tail
	// of the output still has to be collected.
	while (true) {
		const uint64_t read = p_pipe->get_buffer(scratch.ptrw(), (uint64_t)scratch.size());
		if (read == 0) {
			break;
		}
		if (max_capture_bytes > 0 && r_count >= max_capture_bytes) {
			r_truncated = true;
			r_count += (int64_t)read;
			continue;
		}
		int64_t keep = (int64_t)read;
		if (max_capture_bytes > 0 && r_count + keep > max_capture_bytes) {
			keep = max_capture_bytes - r_count;
			r_truncated = true;
		}
		_append_utf8_lossy(r_text, replaced, scratch.ptr(), keep);
		r_count += (int64_t)read;
	}
}

void ChildProcess::pump() {
	_drain(stdout_pipe, out_text, out_bytes, out_truncated);
	_drain(stderr_pipe, err_text, err_bytes, err_truncated);
}

bool ChildProcess::is_running() {
	if (child_pid == 0 || exited) {
		return false;
	}
	OS *os = OS::get_singleton();
	if (os == nullptr) {
		return false;
	}
	if (os->is_process_running(child_pid)) {
		return true;
	}
	last_exit_code = os->get_process_exit_code(child_pid);
	exited = true;
	return false;
}

void ChildProcess::kill() {
	if (child_pid == 0 || exited) {
		return;
	}
	OS *os = OS::get_singleton();
	if (os != nullptr && os->is_process_running(child_pid)) {
		os->kill(child_pid);
		killed = true;
	}
	// `OS::kill` removes the process from the engine's map, so its exit code is
	// no longer readable - -1 is the honest answer for a child this tool killed.
	last_exit_code = -1;
	exited = true;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tool
// ---------------------------------------------------------------------------

static MCPDeferred::Task *_tool_build_csharp(const Dictionary &p_args, MCPToolError &r_error) {
	// --- arguments, before anything else -------------------------------------
	int64_t timeout_ms = 120000;
	if (!optional_int(p_args, "timeout_ms", 120000, timeout_ms, r_error)) {
		return nullptr;
	}
	if (timeout_ms < 1000 || timeout_ms > 600000) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'timeout_ms' must be between 1000 and 600000 milliseconds, got %s",
				itos(timeout_ms)));
		return nullptr;
	}
	// The contract's two configurations. They are not passed to the SDK blindly:
	// a typo like "Fast" would otherwise become an MSBuild configuration that
	// does not exist, and the answer would be the SDK's error rather than the
	// tool naming the enum it accepts.
	String configuration;
	if (!optional_string(p_args, "configuration", "Debug", configuration, r_error)) {
		return nullptr;
	}
	if (configuration != "Debug" && configuration != "Release") {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'configuration' must be one of \"Debug\" or \"Release\", got '%s'", configuration));
		return nullptr;
	}
	bool rescan = true;
	if (!optional_bool(p_args, "rescan", true, rescan, r_error)) {
		return nullptr;
	}
	Array extra_args;
	const Variant extra_value = p_args.get("extra_args", Variant());
	if (extra_value.get_type() != Variant::NIL) {
		if (extra_value.get_type() != Variant::ARRAY) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'extra_args' must be an array of strings, got %s",
					Variant::get_type_name(extra_value.get_type())));
			return nullptr;
		}
		extra_args = extra_value;
	}
	Vector<String> extra;
	if (!validate_extra_args(extra_args, extra, r_error)) {
		return nullptr;
	}

	// --- capability (GDR-28 point 6) -----------------------------------------
	// Both halves are reported as what to install, never as a fake success: the
	// tool cannot build C# without a C#-capable engine build *and* the SDK.
	if (!csharp_support_available()) {
		r_error = MCPToolError::tool_state(
				"This engine build has no C# support (no C# script language is registered in this process)",
				"Run the tool from a Godot build with the C#/mono module compiled in (an official .NET build, or a local build with module_mono_enabled=yes); the plain editor cannot compile C#");
		return nullptr;
	}
	const String dotnet = find_dotnet_executable();
	if (dotnet.is_empty()) {
		r_error = MCPToolError::tool_state(
				"No 'dotnet' executable was found on PATH",
				"Install the .NET SDK (https://dotnet.microsoft.com/download) and make sure 'dotnet --version' works in a shell; restart the editor afterwards so it inherits the updated PATH");
		return nullptr;
	}

	// --- the concrete thing the tool looks for -------------------------------
	const String project_root = String::utf8("res://");
	const Array projects = find_csharp_project_files(project_root);
	if (projects.is_empty()) {
		r_error = MCPToolError::not_found(vformat("A '.csproj' file below '%s'", project_root),
				"Write one with project_write_text_file (e.g. 'res://MyProject.csproj'), or add the C# project directory to the project");
		return nullptr;
	}

	const int64_t effective = effective_build_timeout_ms(timeout_ms);
	return memnew(CSharpBuildTask(dotnet, projects, configuration, extra, timeout_ms, effective, rescan, project_root));
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// `docs/tools_list.renamed.json` (generated from `ADDED_TOOLS`).
// ---------------------------------------------------------------------------

// The `inputSchema` of `project_build_csharp`, built as a C++ `Dictionary`
// instead of being parsed from the same JSON text the contract spells.
//
// Why: `JSON::parse` turns **every** JSON number into a FLOAT Variant
// (`core/io/json.cpp`), and `JSON::stringify` then writes a float that happens to
// be integral as `1000.0`. This is the first contract schema with numeric
// *bounds*, so the parsed form would put `"minimum":1000.0` and
// `"maximum":600000.0` on the wire where the contract says `1000` and `600000`,
// and gate 1 compares the live `inputSchema` against the contract field by field
// (`scripts/check_contract_subset.ps1` -> `Get-CanonicalJson`). The module
// already has the same rule for a single integer `default`
// (`MCPTools::schema_with_integer_defaults`, tool_helpers.cpp:3198); a schema
// whose numbers are *all* integral is built with INT literals here, which is also
// what the generated b2/b3/b5 groups do.
//
// The shape is the contract's entry verbatim (`docs/tools_list.renamed.json`,
// generated from `ADDED_TOOLS` in scripts/gen_renamed_contract.py): key order
// inside a JSON object is not part of the contract, the values are.
static Dictionary _build_csharp_schema() {
	Dictionary configuration;
	configuration["default"] = "Debug";
	Array configuration_enum;
	configuration_enum.push_back("Debug");
	configuration_enum.push_back("Release");
	configuration["enum"] = configuration_enum;
	configuration["type"] = "string";

	Dictionary extra_args;
	Array extra_args_default;
	extra_args["default"] = extra_args_default;
	Dictionary extra_args_items;
	extra_args_items["type"] = "string";
	extra_args["items"] = extra_args_items;
	extra_args["type"] = "array";

	Dictionary rescan;
	rescan["default"] = true;
	rescan["type"] = "boolean";

	Dictionary timeout_ms;
	timeout_ms["default"] = (int64_t)120000;
	timeout_ms["maximum"] = (int64_t)600000;
	timeout_ms["minimum"] = (int64_t)1000;
	timeout_ms["type"] = "integer";

	Dictionary properties;
	properties["configuration"] = configuration;
	properties["extra_args"] = extra_args;
	properties["rescan"] = rescan;
	properties["timeout_ms"] = timeout_ms;

	Array required;

	Dictionary schema;
	schema["properties"] = properties;
	schema["required"] = required;
	schema["type"] = "object";
	return schema;
}

void register_project_csharp_build_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_build_csharp",
				String::utf8(R"desc(Build the project's C# solution by running the .NET SDK on its .csproj files, and answer the exit code with the captured output. Requires a Godot build with C# support and a .NET SDK on PATH; when either is missing the call is refused with the reason and what to install.)desc"));
		builder.channel("project").verb("build").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_build_csharp_schema());
		builder.pending_handler(_tool_build_csharp).register_into(r_registry);
	}
}
