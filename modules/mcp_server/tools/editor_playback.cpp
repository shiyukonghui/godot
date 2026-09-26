/**************************************************************************/
/*  editor_playback.cpp                                                   */
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
#include "editor_playback.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/io/file_access.h"
// TASK-024a E-10: the free-port probe (`TCPServer::listen(0)` +
// `get_local_port()`) and the `IPAddress` it binds. Both are plain `core/`, so
// they need no editor guard - the guard is on the run bar that consumes them.
#include "core/io/tcp_server.h"
#include "core/string/ustring.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// TASK-024a E-10: the editor's *own* MCP port, so that the port this tool hands
// to a game child can never be the one the editor is already listening on.
#include "../mcp_server.h"

// TASK-024a E-10: the run parameters (`--mcp-port=<port>`) reach the game child
// through `EditorRunBar::play_*(..., p_play_args)`. `EditorInterface::play_*`
// cannot carry them - `editor_interface.cpp:815-825` calls the run bar without
// arguments - which is why the tool no longer goes through the interface.
#ifdef MCP_EDITOR_TOOLS_ENABLED
// `editor_stop_scene` still uses the interface (its `stop_playing_scene()` and
// `is_playing_scene()` are one-line forwards to the run bar,
// `editor_interface.cpp:827-833`), so both headers are needed.
#include "editor/editor_interface.h"
#include "editor/run/editor_run_bar.h"
#endif

using namespace MCPTools;

// ---------------------------------------------------------------------------
// Group `editor_playback` (docs/tool-groups-b2.json): `editor_play_scene` and
// `editor_stop_scene`.
//
// **Why these two stay in the editor process.** The mapping
// (`docs/tool-rename-map.json`, both entries) puts them under the `editor_`
// channel with `scope = editor` on purpose: they start and stop the *editor's*
// scene player - the run bar that owns the child process (`EditorInterface` for
// `stop`, whose `stop_playing_scene()` is a one-line forward to it) - which is an
// action on the editor's own playback state. They do not drive a game endpoint
// and they are not available in a game process - that is the other half of the
// DECISIONS D56 split whose input half lives in `tools/running_game_input.cpp`.
//
// What "starting the editor's scene player" *is*, physically, in Godot:
// `EditorRunBar::_run_scene()` -> `EditorRun::run()`, which spawns a **child
// process** (`editor/run/editor_run.cpp:51-190`) and starts the debugger
// protocol. Two consequences that the task book calls out explicitly, and that
// the implementation must not paper over:
//
//   1. the game child's MCP port used to come from *its own* project settings
//      (`godot_mcp/port`), because the editor did not forward a port to it: the
//      measured cmdline carried only `--path / --remote-debug / --editor-pid /
//      --scene` (REPORT-AUDIT-M4c D-13), so "start the game and watch it" was a
//      multi-step dance through the test project's settings. TASK-024a E-10
//      closes that: `editor_play_scene` hands `--mcp-port=<port>` to
//      `EditorRunBar::play_*(..., p_play_args)`, and `EditorRun::run()` appends
//      every argument of `p_run_args` to the child's command line
//      (`editor_run.cpp:157-161`). The port is either the caller's `mcp_port`
//      or one the tool probed as free;
//   2. stopping the playback is what terminates that child, so `editor_stop_scene`
//      is also the module's only "no orphan game process" lever - the report
//      proves the child really goes away rather than being left behind.
//
// Migration source (semantic reference, read-only):
// `godot_mcp_gdext/src/commands/scene.rs:126-149` (`cmd_play_scene` /
// `cmd_stop_scene`).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Game-child MCP port (TASK-024a E-10).
//
// The three functions below are exported through `editor_playback.h` instead of
// being file-private, for one reason: a doctest has to be able to pin the *rule*
// ("1..65535 and never the editor's own port") and the two probes, not merely
// the intention. `port_is_bindable` and `pick_free_game_port` are the socket
// half, and they use the same API and the same bind address the MCP transport
// itself uses (`mcp_http_server.cpp` binds 127.0.0.1), so "free" here means free
// for the exact bind the child is about to perform.
// ---------------------------------------------------------------------------

namespace MCPTools {

bool is_usable_game_port(int p_candidate, int p_avoid) {
	return p_candidate >= 1 && p_candidate <= 65535 && p_candidate != p_avoid;
}

bool port_is_bindable(int p_port) {
	if (p_port < 1 || p_port > 65535) {
		return false;
	}
	Ref<TCPServer> probe;
	probe.instantiate();
	if (probe.is_null()) {
		return false;
	}
	const bool ok = probe->listen((uint16_t)p_port, IPAddress("127.0.0.1")) == OK;
	probe->stop();
	return ok;
}

int pick_free_game_port(int p_avoid, MCPToolError &r_error) {
	// `listen(0)` makes the OS choose a free port and `get_local_port()` reads
	// back what it chose, so the answer was really free a moment ago. It is
	// released before returning: the *child* is what has to hold it, and holding
	// it here would be the one sure way to make the child's bind fail.
	//
	// The loop is not for the OS (each answer is free by construction); it is for
	// `p_avoid`. A port the editor is really listening on cannot come back from
	// `listen(0)` anyway - the editor's own socket holds it - but "the editor is
	// listening" is not something this tool can promise (its bind may have
	// failed, in which case `get_port()` is 0 and nothing is held), so the
	// comparison is the belt to that braces and is kept explicitly.
	for (int attempt = 0; attempt < 8; attempt++) {
		Ref<TCPServer> probe;
		probe.instantiate();
		if (probe.is_null()) {
			r_error = MCPToolError::internal("a TCP socket could not be created to look for a free port");
			return 0;
		}
		if (probe->listen(0, IPAddress("127.0.0.1")) != OK) {
			probe->stop();
			r_error = MCPToolError::internal("no free TCP port could be probed on 127.0.0.1");
			return 0;
		}
		const int candidate = probe->get_local_port();
		probe->stop();
		if (is_usable_game_port(candidate, p_avoid)) {
			return candidate;
		}
	}
	r_error = MCPToolError::internal(
			vformat("no free TCP port different from the editor's own port (%d) could be probed on 127.0.0.1", p_avoid));
	return 0;
}

// ---------------------------------------------------------------------------
// TASK-051 M-3: the child's command line (declared, with its three rules, in
// tools/editor_playback.h).
// ---------------------------------------------------------------------------
bool build_play_args(int p_game_port, bool p_headless, const Array &p_extra_args,
		Vector<String> &r_args, Array &r_deduplicated, MCPToolError &r_error) {
	// Every element is validated before a single argument is produced, so a
	// malformed `extra_args` starts nothing and answers `-32602` in any process
	// (the same ordering the port rule follows).
	Vector<String> extras;
	for (int i = 0; i < p_extra_args.size(); i++) {
		const Variant element = p_extra_args[i];
		if (element.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'extra_args[%d]' must be a string, got %s",
					i, Variant::get_type_name(element.get_type())));
			return false;
		}
		const String argument = element;
		if (argument.is_empty()) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'extra_args[%d]' must not be empty: an empty command-line argument "
					"is not a flag and would be passed to the child verbatim",
					i));
			return false;
		}
		// The port has exactly one source (the `mcp_port` argument), because the
		// answer's `endpoint` names it. `MCPPort::parse` takes the last
		// occurrence, so an appended port would win and the answer would lie.
		if (argument == "--mcp-port" || argument.begins_with("--mcp-port=")) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'extra_args[%d]' is '%s': the game child's MCP port is injected by this tool "
					"from the 'mcp_port' argument (the engine's own parser takes the last occurrence, so a "
					"second spelling would silently move the child off the port this answer reports)",
					i, argument));
			return false;
		}
		extras.push_back(argument);
	}

	r_args.clear();
	r_args.push_back("--mcp-port=" + itos(p_game_port));
	if (p_headless) {
		r_args.push_back("--headless");
	}
	r_deduplicated = Array();
	// `--headless` is idempotent, so a repeated one is dropped rather than passed
	// twice - and the drop is *reported* (`r_deduplicated`) instead of being a
	// silent edit of the caller's list.
	bool headless_seen = p_headless;
	for (int i = 0; i < extras.size(); i++) {
		if (extras[i] == "--headless") {
			if (headless_seen) {
				r_deduplicated.push_back(extras[i]);
				continue;
			}
			headless_seen = true;
		}
		r_args.push_back(extras[i]);
	}
	return true;
}

} // namespace MCPTools

// The port this editor's own MCP server is listening on, or 0 when this process
// has none (a doctest process, or an editor whose bind failed). Read from the
// server that owns the socket rather than from the settings it was configured
// with, because the question is "which port may a child not be given".
static int _editor_mcp_port() {
	MCPServer *server = MCPServer::get_singleton();
	return server != nullptr ? server->get_port() : 0;
}


// ---------------------------------------------------------------------------
// editor_play_scene (old `play_scene`, scene.rs:53/126)
//
// Observable contract (as implemented):
//   * `mode` (string, optional, default "main"):
//       - "main"    -> `EditorRunBar::play_main_scene(false, args)` (the
//                      project's `application/run/main_scene`);
//       - "current" -> `EditorRunBar::play_current_scene(false, args)` (the
//                      scene the editor has open);
//       - anything else is taken as a **project scene path** and validated: it
//         must normalize to a `res://` path (no `..`, no other scheme) and the
//         file must exist -> `-32602` / `-32001` respectively. Both refusals
//         happen *before* playback is started, so a bad path never leaves a
//         game running;
//   * `mcp_port` (integer, optional, 1..65535): the TCP port the game child is
//     told to listen on, through the `--mcp-port=<port>` argument this tool
//     injects. A value outside the range - including `0`, which is *not* the
//     way to say "no choice" (omitting the key is) -> `-32602`. A named port is
//     then verified: the editor's own port, or one another process holds, is
//     refused with `-32000` rather than handed to a child that could not bind
//     it. When the key is absent the tool probes a free port itself, with the
//     same "not the editor's port" rule;
//   * answers `{"playing": true, "mode": <the effective mode>}` plus `path` for
//     a custom scene, `mcp_port`, `mcp_port_source`
//     (`"argument"` / `"auto_free_port"`), `endpoint`
//     (`http://127.0.0.1:<mcp_port>/mcp`) and `pid` (the game child's process
//     id), so a caller can connect immediately without reading a log or a
//     project setting;
//   * `playing: true` means "the editor's player really started a child
//     process", which is *read back* rather than assumed: `EditorRunBar::play_*`
//     returns void and `_run_scene` has four silent early returns (recovery mode,
//     an already running player, a missing `project.godot`, a rejected custom
//     directory), so the tool verifies `is_playing()` and a **changed** child
//     pid after the call and refuses with `-32000` when nothing started. It is
//     still not a promise that the child has already bound its socket: the
//     child is a separate process and this tool does not block the editor
//     waiting for it;
//   * outside a running editor (a game process, a `--test` binary) -> `-32000`
//     with a suggestion: this tool is the editor's.
//
// Deviation from the migration source: it took the custom-path branch on *any*
// string that was not "main"/"current" and only checked
// `FileAccess::file_exists(custom)` - an absolute host path passed that check and
// was then handed to the engine. Here the path goes through the module's
// `normalize_project_path`, so only a project scene can be played.
//
// TASK-024a E-10 (engine basis): `EditorInterface::play_*` is deliberately *not*
// used any more. It forwards to `EditorRunBar::play_*` **without** run arguments
// (`editor_interface.cpp:815-825`), so it cannot express the port; the run bar
// takes `const Vector<String> &p_play_args` and `EditorRun::run()` appends them
// verbatim to the child's command line (`editor_run.cpp:157-161`).
// ---------------------------------------------------------------------------
static Variant _tool_play_scene(const Dictionary &p_args, MCPToolError &r_error) {
	String mode;
	if (!optional_string(p_args, "mode", "main", mode, r_error)) {
		return Variant();
	}
	const bool custom = mode != "main" && mode != "current";
	String scene_path;
	if (custom) {
		if (!normalize_project_path(mode, scene_path, r_error)) {
			return Variant();
		}
	}

	// Argument validation runs before "can I act at all", exactly like `mode`, so
	// a mistyped `mcp_port` is a `-32602` in every process and nothing is
	// started. `0` is not a legal port and is **not** the way to ask for the
	// automatic choice: omitting the key is (an explicit `null` is read as absent
	// too, which is what every `optional_*` of this module does). Presence is
	// therefore tested separately from the value - the first version of this code
	// used `0` as its own "absent" sentinel and silently accepted an explicit
	// `mcp_port: 0`, which the doctest caught.
	const bool port_given = p_args.get("mcp_port", Variant()).get_type() != Variant::NIL;
	int64_t requested_port = 0;
	if (!optional_int(p_args, "mcp_port", 0, requested_port, r_error)) {
		return Variant();
	}
	if (port_given && (requested_port < 1 || requested_port > 65535)) {
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'mcp_port' must be between 1 and 65535, got %s", itos(requested_port)));
		return Variant();
	}

	// TASK-051 M-3: `headless` and `extra_args`. Both top-level *shapes* are read
	// here, next to `mcp_port`, so a wrong top-level type is a `-32602` in *every*
	// process (the module's rule, PLAYBOOK section 6.2). The element-level rules
	// of `extra_args` run where the child's argument list is built
	// (`build_play_args`, after the editor guard) - the same split
	// `editor_add_nodes_batch` uses for `nodes[i]`. The default (`headless`
	// absent, `extra_args` absent) reproduces the E-10 argument list byte for
	// byte.
	bool headless = false;
	if (!optional_bool(p_args, "headless", false, headless, r_error)) {
		return Variant();
	}
	Array extra_args;
	const Variant extra_value = p_args.get("extra_args", Variant());
	if (extra_value.get_type() != Variant::NIL) {
		if (extra_value.get_type() != Variant::ARRAY) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'extra_args' must be an array of strings, got %s",
					Variant::get_type_name(extra_value.get_type())));
			return Variant();
		}
		extra_args = extra_value;
	}

	if (!require_editor_ui(r_error, "editor playback outside a running editor",
				"Start the MCP server inside the Godot editor to start and stop scene playback")) {
		return Variant();
	}
	if (custom && !FileAccess::exists(scene_path)) {
		r_error = MCPToolError::not_found(vformat("Scene '%s'", scene_path),
				"Use project_get_filesystem_tree to list the .tscn files of the project");
		return Variant();
	}

#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorRunBar *run_bar = EditorRunBar::get_singleton();
	if (run_bar == nullptr) {
		r_error = MCPToolError::not_implemented("the editor's run bar (no EditorRunBar in this process)",
				"Start the MCP server inside the Godot editor to start scene playback");
		return Variant();
	}

	const int editor_port = _editor_mcp_port();
	int game_port = 0;
	String port_source;
	if (port_given) {
		game_port = (int)requested_port;
		port_source = "argument";
		// A port the caller names is *checked*, not trusted. Handing the child a
		// port that is already taken would start a game no MCP client can reach
		// while the answer still said `playing: true` - the one shape of
		// "pretended success" this item forbids. The editor's own port has its
		// own message because the advice differs (a caller picking it probably
		// confused "the port I am calling on" with "the port the game should
		// use"), and the check is deterministic rather than a probe result.
		if (editor_port != 0 && game_port == editor_port) {
			r_error = MCPToolError::tool_state(
					vformat("mcp_port %d is the port this editor's own MCP server is listening on", game_port),
					"Pass a different mcp_port, or omit mcp_port to let the tool pick a free one for the game child");
			return Variant();
		}
		if (!port_is_bindable(game_port)) {
			r_error = MCPToolError::tool_state(
					vformat("mcp_port %d is not free on 127.0.0.1 (another process is listening on it)", game_port),
					"Pass a free mcp_port, or omit mcp_port to let the tool pick a free one for the game child");
			return Variant();
		}
	} else {
		game_port = pick_free_game_port(editor_port, r_error);
		if (game_port == 0) {
			return Variant();
		}
		port_source = "auto_free_port";
	}

	// The child is told where to listen; that is the whole point of E-10. The
	// argument is injected as the engine's own spelling, which
	// `MCPPort::parse` (`mcp_server.cpp:77-91`) reads in the child and which
	// makes the child listen even though a game process normally must opt in
	// (`MCPPort::should_listen`, REQUIREMENTS C4).
	//
	// TASK-051 M-3: the whole list (port, optional `--headless`, the caller's
	// extra arguments) comes from the one rule function, so the refusals above it
	// and the answer below it cannot describe a different command line.
	Vector<String> play_args;
	Array args_deduplicated;
	if (!build_play_args(game_port, headless, extra_args, play_args, args_deduplicated, r_error)) {
		return Variant();
	}

	// A child that is already running would make the "did anything start?" check
	// below vacuous, so the pid is captured before the call.
	const ProcessID previous_pid = run_bar->get_current_process();

	if (mode == "main") {
		run_bar->play_main_scene(false, play_args);
	} else if (mode == "current") {
		run_bar->play_current_scene(false, play_args);
	} else {
		run_bar->play_custom_scene(scene_path, play_args);
	}

	// TASK-024a E-10 point 4 ("never pretend success"). Read the result back
	// instead of assuming it: `is_playing()` is true only after
	// `EditorRun::run()` reached `status = STATUS_PLAY`, which it does only when
	// every `OS::create_instance` returned OK, and a pid that is unchanged means
	// the call was swallowed by one of `_run_scene`'s silent early returns
	// (recovery mode is the one that leaves a previous child running).
	const ProcessID child_pid = run_bar->get_current_process();
	if (!run_bar->is_playing()) {
		r_error = MCPToolError::tool_state("the editor's scene player did not start (no game process was created)",
				"Check the editor's output panel for the reason: playing needs a project.godot, and a main scene or a valid mode/scene path");
		return Variant();
	}
	if (child_pid == 0 || child_pid == previous_pid) {
		r_error = MCPToolError::tool_state("the editor reports a running scene but did not start a new game process",
				"Call editor_stop_scene first and try again; if it repeats, the editor's run bar is in an inconsistent state");
		return Variant();
	}

	Dictionary result;
	result["playing"] = true;
	result["mode"] = mode;
	if (custom) {
		result["path"] = scene_path;
	}
	result["mcp_port"] = game_port;
	result["mcp_port_source"] = port_source;
	result["endpoint"] = vformat("http://127.0.0.1:%d/mcp", game_port);
	result["pid"] = (int64_t)child_pid;
	// TASK-051 M-3: the command line the child was actually given, and the
	// caller entries that did not reach it. "Which arguments did my game really
	// get" is otherwise only answerable by inspecting the child process, which is
	// exactly the round trip this item exists to remove.
	result["headless"] = headless;
	Array injected;
	for (int i = 0; i < play_args.size(); i++) {
		injected.push_back(play_args[i]);
	}
	result["args_injected"] = injected;
	result["args_deduplicated"] = args_deduplicated;
	return result;
#else
	(void)scene_path;
	return Variant();
#endif
}

// ---------------------------------------------------------------------------
// editor_stop_scene (old `stop_scene`, scene.rs:58/142)
//
// Observable contract (as implemented):
//   * no parameters;
//   * nothing playing -> `{"stopped": false, "message": "No scene playing"}` -
//     a success, exactly the migration source's answer, because "there was
//     nothing to stop" is information rather than a failure;
//   * playing -> `EditorInterface::stop_playing_scene()` and
//     `{"stopped": true, "message": "Playback stopped"}`;
//   * outside a running editor -> `-32000` with a suggestion.
//
// The answer is *verified*, not assumed: the state is read back after the call
// and a player that is still running is reported with
// `{"stopped": false, "message": "Playback is still running after the stop request"}`.
// The migration source reported `stopped: true` unconditionally, which would hide
// a child process that refused to die - the one failure mode this tool exists to
// let a caller detect.
// ---------------------------------------------------------------------------
static Variant _tool_stop_scene(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	if (!require_editor_ui(r_error, "editor playback outside a running editor",
				"Start the MCP server inside the Godot editor to start and stop scene playback")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorInterface *editor = EditorInterface::get_singleton();
	if (editor == nullptr) {
		r_error = MCPToolError::not_implemented("the editor UI (no EditorInterface in this process)",
				"Start the MCP server inside the Godot editor to stop scene playback");
		return Variant();
	}

	Dictionary result;
	if (!editor->is_playing_scene()) {
		result["stopped"] = false;
		result["message"] = "No scene playing";
		return result;
	}

	editor->stop_playing_scene();

	result["stopped"] = !editor->is_playing_scene();
	result["message"] = (bool)result["stopped"] ? "Playback stopped" : "Playback is still running after the stop request";
	return result;
#else
	return Variant();
#endif
}

// ---------------------------------------------------------------------------
// Registration
//
// The declaration order follows docs/tool-groups-b2.json; channel, verb, scope
// and mutating come from docs/tool-rename-map.json and the description and
// `inputSchema` are a byte-exact copy of docs/tools_list.renamed.json, emitted
// by `scripts/gen_b2_game_schema.py` (re-running it reproduces this block).
// ---------------------------------------------------------------------------

void register_editor_playback_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("editor_play_scene", String::utf8("运行场景 起游戏时经 EditorRunBar::play_*(..., p_play_args) 注入 --mcp-port=<端口>，使编辑器起的游戏子进程立刻可被 MCP 观察，无需改被测工程的 godot_mcp/port 设置：端口可用可选参数 mcp_port 指定（越界、已被占用、以及编辑器自己正在用的端口都会被拒绝，不会把游戏指向一个连不上的端口），缺省时自动挑一个空闲端口，且不与编辑器自身端口相同；响应在确认子进程已创建后给出 mcp_port、mcp_port_source（argument/auto_free_port）、可直连的 endpoint 与游戏 pid，子进程没起来则不报成功。"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		Array v2;
		v1[String::utf8("default")] = v2;
		v1[String::utf8("description")] = String::utf8("追加到游戏子进程命令行的额外参数（逐字追加，排在引擎自己构造的 --path/--remote-debug/--editor-pid/--scene 与固定注入的 --mcp-port=<端口> 之后，所以同名参数以这里的为准）；不得包含 --mcp-port（端口只由 mcp_port 参数注入：引擎的命令行解析取最后一次出现，重复注入会让响应里的 endpoint 指向游戏并未监听的端口，故被明确拒绝）；重复的 --headless 会被去重并在响应的 args_deduplicated 里列出；每个元素必须是非空字符串");
		Dictionary v3;
		v3[String::utf8("type")] = String::utf8("string");
		v1[String::utf8("items")] = v3;
		v1[String::utf8("type")] = String::utf8("array");
		v0[String::utf8("extra_args")] = v1;
		Dictionary v4;
		v4[String::utf8("default")] = false;
		v4[String::utf8("description")] = String::utf8("以 headless 模式启动游戏子进程（给子进程加一个 --headless，即引擎自己的“无音频、无渲染”别名）；默认 false，与旧行为逐字一致。注意 --headless 不会从编辑器继承（引擎的可转发参数表里没有它），所以在无显示环境里必须显式传 true");
		v4[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("headless")] = v4;
		Dictionary v5;
		v5[String::utf8("description")] = String::utf8("游戏子进程监听的 TCP 端口（可选，1-65535）；缺省时自动挑一个空闲端口，且不与编辑器自身端口相同");
		v5[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("mcp_port")] = v5;
		Dictionary v6;
		v6[String::utf8("default")] = String::utf8("main");
		v6[String::utf8("description")] = String::utf8("main/current/路径");
		v6[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("mode")] = v6;
		schema[String::utf8("properties")] = v0;
		Array v7;
		schema[String::utf8("required")] = v7;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("editor").verb("play").scope(MCPToolScope::EDITOR).mutating(true).schema(schema).handler(_tool_play_scene);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_stop_scene", String::utf8("停止运行"));

		Dictionary schema;
		Dictionary v0;
		schema[String::utf8("properties")] = v0;
		Array v1;
		schema[String::utf8("required")] = v1;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("editor").verb("stop").scope(MCPToolScope::EDITOR).mutating(true).schema(schema).handler(_tool_stop_scene);
		builder.register_into(r_registry);
	}
	// END generated
}