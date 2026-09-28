/**************************************************************************/
/*  running_game_script_execution.cpp                                     */
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
#include "running_game_script_execution.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/object/ref_counted.h"
#include "core/object/script_language.h"
#include "core/templates/vector.h"
#include "core/variant/callable.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// running_game_execute_gdscript (old `execute_game_script`)
//
// The E3 lever (DECISIONS D56): the built-in module exists in the game process
// too, so this tool runs the caller's code *there*, where the engine singletons
// are. Nothing is sent over `user://` any more, and - unlike the migration
// source - nothing is limited to a single `Expression`.
//
// Observable contract (as implemented):
//   * `code` (string, required, must not be blank) is a GDScript **function
//     body**: statements, `return`, loops, `match`, and `func` declarations at
//     column 0 (which are lifted to class level so the body can call them);
//   * the code is compiled into `func _mcp_execute()` in the process that serves
//     the endpoint, and called once. Its base class is `Node` when the running
//     game has a reachable scene tree, and `RefCounted` otherwise:
//     [REBUILT-2C low-confidence: verify] TASK-090 (item B, decision D-3) - the
//     executor now reaches the **running scene tree**; see
//     `tools/running_game_script_execution.h` for the mounting contract and
//     REBUILT-2C-MANIFEST.md section 2c-9 (J-2).
//   * with a scene tree: the instance is added as the last child of the current
//     scene root (or of the tree root when no current scene is set) for the
//     duration of the call, so `get_node()` / `$Path` / signals / `get_tree()` /
//     node properties are the real `Node` facilities - the E3 lever can finally
//     drive the game it is executing inside. It is removed again on every path,
//     success or failure, so the game's own node tree is left exactly as it was;
//     because the node lives for less than a frame, `_process` /
//     `_physics_process` do not tick;
//   * without a scene tree: `extends RefCounted`, no mounting, the engine
//     singletons reachable - byte for byte the pre-TASK-090 behaviour.
//   // [/REBUILT-2C]
//   * the answer is
//     `{"result": <serialize_variant of the returned value>, "result_type":
//     "<Variant type name>"}`; a body without `return` answers
//     `{"result": null, "result_type": "Nil"}` and - TASK-103 (X-1) - carries a
//     `note` saying that a null result is not evidence of an effect;
//   * `code` that does not compile is `-32602` ("does not compile: <verdict>") -
//     a malformed argument, not an internal failure;
//   * TASK-151: **a caller's failing body never stops this process in a
//     debugger.** A game child of `editor_play_scene` runs with
//     `--remote-debug` (`editor/run/editor_run.cpp:64-68`), so
//     `EngineDebugger::is_active()` is true in it and the engine's own
//     `debug_break_parse` / `debug_break` would park the main thread - the thread
//     this endpoint is served from - until the editor resumes it (measured: no
//     status line in 20 s, `GET /mcp` silent for 60 s, listener still open). The
//     compile and execution windows therefore run with the engine's error-break
//     switch raised, so a body that does not compile answers `-32602` and a body
//     that fails while it runs answers `-32000`, both immediately, in a debugged
//     process exactly as in an undebugged one. The switch is put back afterwards;
//     see `GDScriptErrorBreakGuard` in `tool_helpers.h` for the engine basis and
//     the boundaries;
//   * `code` that compiles and then fails **while it runs** is `-32000` with
//     `data.script_error` (message, line of `code`, generated line, script path,
//     the GDScript function the engine blamed) and `data.suggestion` - TASK-103
//     (X-1); see the long note in `tool_helpers.h`;
//   * an engine build without the GDScript class is `-32000` with a suggestion
//     (GDR-14's "the capability is absent"), never a crash;
//   * a `Callable` call error (the generated method is missing) is `-32603`,
//     because that would be a bug in this file, not in the caller's code.
//
// Migration source comparison (`addons/godot_mcp_rs/mcp_runtime_agent.gd:230-253`
// plus `godot_mcp_gdext/src/commands/runtime.rs:295-302`):
//   * it stripped a leading `return ` and parsed the rest with
//     `Expression.parse()`; therefore the caller could only send *one
//     expression* and could not use `var`, `for`, `if` or a helper function;
//   * it executed that expression with `expression.execute([], self, false)`,
//     whose base object is the agent node. `Expression` resolves names against
//     that base - it does not consult the global singletons - so
//     `Input.parse_input_event(...)` and even `Engine.get_frames_per_second()`
//     failed with `Invalid named index 'Input' for base type Object`;
//   * it answered `{"result": str(result)}`, a stringified value (and turned its
//     own `{"error": ...}` responses into `-32603` on the Rust side).
//
// This implementation keeps none of those three limitations: full statements,
// real singletons, structured result. `scripts/mcp010_b2_observation_evidence.ps1`
// phase `game` demonstrates all three on the wire against a real game, and the
// doctest `[MCPServer] running_game_execute_gdscript runs a GDScript body and
// reaches engine singletons` pins the same comparison in-process, including the
// legacy `Expression` failure on the very same expression.
//
// Deliberate limitations, stated rather than hidden:
//   * `print()` output is not captured (it goes to the engine log);
//   * the code runs synchronously inside the frame that serves the request, so
//     it must not block and it cannot wait for frames (see
//     `running_game_frame_observation` in docs/tool-groups-b2.json);
//   * a *runtime* error in the body used to be the first entry of this list: it
//     was reported by the engine on stderr and the answer stayed
//     `{"result": null, "result_type": "Nil"}` inside an `ok`. TASK-103 (X-1)
//     removed it from the list - the engine's error handler sees the aborted
//     frame (`gdscript_vm.cpp:3988`) and the capture in `tool_helpers.h` turns it
//     into `-32000` + `data.script_error`; see the contract bullets above;
//   * the one boundary that remains, and that no handler can see: the VM's error
//     report is inside `#ifdef DEBUG_ENABLED`, so a release template
//     (`target=template_release`) would abort the frame silently and this tool
//     would answer `ok` again. Every build this module's gates run is
//     `target=editor` (SConstruct:550/566-569).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// TASK-089 (F1): the source builder and the reload-diagnostic capture are the
// module's hoisted ones (`tool_helpers.h`), not a second copy here.
//
// Before this, the game-side executor carried its own `_build_source` (byte for
// byte the same layout rules as `build_execute_gdscript_source`) and called the
// bare `Script::reload()`. A body that really does not compile therefore
// answered "Parameter 'code' does not compile: Parse error" and the engine's own
// diagnostic - the only thing that names the line and the reason - was printed
// to stderr and lost. Measured on the round-7 session:
//
//   code = `var m = get_node("/root/Main"); return m.move_player(150.0)`
//   answer: -32602 "Parameter 'code' does not compile: Parse error"
//   stderr: "SCRIPT ERROR: Parse Error: Function \"get_node()\" not found in
//            base self." at gdscript://...:4
//
// The editor endpoint (`editor_execute_gdscript`, TASK-063 d) already answered
// the same failure with the line and the message, so the two endpoints described
// one parse error two different ways. They share the definition now.
// ---------------------------------------------------------------------------

Variant execute_gdscript_code(const String &p_code, bool p_tool_script, Node *p_mount_point, MCPToolError &r_error) {
	// The script *languages* are a second, independent prerequisite: GDScript is
	// registered by the gdscript module when the engine initialises its modules,
	// but `ScriptServer::init_languages()` - which is what populates the
	// language's global names - only runs from `Main::setup2()`
	// (main/main.cpp:3863), i.e. when the engine starts a real main loop. The
	// `--test` entry point runs *before* that (main/main.cpp:921-943), and so does
	// `--check-only`. Without this guard such a process would get
	// `does not compile: Compilation failed`, and the engine log's real reason
	// ("Native class "RefCounted" not found") would look like the module's bug.
	if (!ScriptServer::are_languages_initialized()) {
		r_error = MCPToolError::not_implemented("execution of GDScript before the script languages are initialised",
				"This process has no script language yet; call this tool in a running game (or an editor), where the engine initialises them");
		return Variant();
	}

	// GDScript is registered by the gdscript module at
	// MODULE_INITIALIZATION_LEVEL_SERVERS (modules/gdscript/register_types.cpp),
	// i.e. in every build that has it and in no build that does not. Asking
	// ClassDB instead of including the module's own header keeps this group free
	// of a module-to-module dependency, and a build without GDScript gets an
	// explicit capability refusal instead of a link error.
	Object *raw = ClassDB::instantiate("GDScript");
	Ref<Script> script = Object::cast_to<Script>(raw);
	if (script.is_null()) {
		if (raw != nullptr) {
			memdelete(raw);
		}
		r_error = MCPToolError::not_implemented("execution of GDScript in this engine build",
				"This build has no GDScript language; use a build with the gdscript module enabled");
		return Variant();
	}

	// TASK-089 (F1): the shared builder (`build_execute_gdscript_source`, the
	// module-level definition the editor executor already uses) and the shared
	// reload capture. `p_tool_script = false`: a *game* process is never the
	// editor, and `@tool` is what the editor executor needs, not this one.
	// [REBUILT-2C low-confidence: verify] TASK-089 F1: written, not replayed;
	// REBUILT-2C-MANIFEST.md section 2c-8 (H-6).
	//
	// Both helpers are named `MCPTools::` on purpose. `tool_helpers.h` used to
	// declare `build_execute_gdscript_source` and `execute_gdscript_method_name`
	// **twice** - once inside `namespace MCPTools` and once after the namespace
	// closed - so an unqualified call in a file that has `using namespace
	// MCPTools;` was ambiguous (MSVC C2668, measured in TASK-089 as D-4). The
	// stale second block is gone now (TASK-090 item B, manifest 2c-9 (J-2)); the
	// `MCPTools::` qualifiers stay because they are correct either way.
	//
	// TASK-090 (item B): `p_node_base` follows the mount point - a body that is
	// going to be attached under the running scene root must compile to
	// `extends Node`, or `get_node()` / `$Path` / signals do not exist on it.
	String generated_source;
	int body_start_line = 0;
	MCPTools::build_execute_gdscript_source(p_code, p_tool_script, generated_source, &body_start_line, p_mount_point != nullptr);
	script->set_source_code(generated_source);
	// TASK-063 (d) / TASK-089 (F1): `reload()` alone answers a bare `Error`; the
	// capture reads the line and the message the engine itself reports
	// (`_err_print_error("GDScript::reload", ..., <line>, ...)`) and
	// `body_start_line` turns that generated line into a line of `code`.
	const GDScriptReloadReport reload = reload_gdscript_capturing(script.ptr(), body_start_line);
	if (reload.error != OK) {
		r_error = MCPToolError::invalid_params(gdscript_reload_failure_text(reload));
		if (reload.diagnostic_seen) {
			// The same facts, machine-readable: the line of `code` (null when the
			// engine's line is inside this tool's own wrapper), the line the engine
			// named in the generated source, and every diagnostic it printed.
			Dictionary diagnostics;
			diagnostics["line"] = reload.in_caller_code ? Variant((int64_t)reload.caller_line) : Variant();
			diagnostics["generated_line"] = (int64_t)reload.generated_line;
			diagnostics["in_caller_code"] = reload.in_caller_code;
			diagnostics["message"] = reload.diagnostic;
			Array messages;
			for (int i = 0; i < reload.messages.size(); i++) {
				messages.push_back(reload.messages[i]);
			}
			diagnostics["messages"] = messages;
			Dictionary data;
			data["parse_error"] = diagnostics;
			// The engine hands a handler a line, never a column.
			data["parse_error_column"] = Variant();
			r_error.data = data;
		}
		return Variant();
	}
	if (!script->can_instantiate()) {
		r_error = MCPToolError::invalid_params(
				"Parameter 'code' compiled but produced a GDScript this process cannot instantiate");
		return Variant();
	}
	// [/REBUILT-2C]

	// TASK-103 (X-1): the identity of the script the runtime capture below has to
	// attribute its diagnostics to.
	//
	// It cannot be `Script::get_path()`: that is `Resource::get_path()`, which
	// answers the **path cache** (`core/io/resource.cpp:118-120`) and is empty for
	// a script that was never loaded from a resource - measured, the runtime
	// error's `p_file` was `gdscript://-9223371484028730203.gd` while
	// `script->get_path()` answered `""`. The path the engine really uses is
	// `GDScript::path`, which a pathless GDScript makes out of its own instance id
	// (`modules/gdscript/gdscript.cpp:1337`:
	// `path = vformat("gdscript://%d.gd", get_instance_id())`), and
	// `GDScriptFunction::source` is set from it (`gdscript_compiler.cpp:3291`).
	// Reconstructing it exactly that way, from the same object, is what makes the
	// comparison in the capture an exact one without reaching into the gdscript
	// module (which this group deliberately does not depend on).
	const String generated_script_path = vformat("gdscript://%d.gd", script->get_instance_id());

	const StringName method(MCPTools::execute_gdscript_method_name());
	Variant result;
	Callable::CallError call_error;
	// TASK-103 (X-1): filled by whichever branch below runs. A *runtime* error in
	// the body never reaches `Callable::callp`'s `call_error` - GDScript aborts the
	// frame and answers `CALL_OK` with the return type's default value - so this is
	// the only place those facts can come from.
	GDScriptRuntimeReport runtime;

	// TASK-090 (item B): the scene-tree path. The instance is a real `Node`
	// mounted under the mount point the caller supplied, so the body sees the
	// running tree exactly as game code does. The removal below runs on **every**
	// path - the resource is returned whether the entry call succeeded or failed.
	// [REBUILT-2C low-confidence: verify] TASK-090 item B: written, not replayed
	// (no recording carries a mount point); REBUILT-2C-MANIFEST.md 2c-9 (J-2).
	if (p_mount_point != nullptr) {
		Node *instance = memnew(Node);
		instance->set_script(script);
		p_mount_point->add_child(instance);

		// `Callable::callp` rather than `Object::call` / `Callable::call`: both of
		// those are variadic *templates* in this fork, and the explicit
		// `(const Variant **, int, CallError &)` form is the one that reports a call
		// failure instead of templating it away.
		const Callable entry_point(instance, method);
		runtime = MCPTools::call_gdscript_capturing(entry_point, generated_script_path, body_start_line, result, call_error);

		// Away from the game's tree before anything else can happen, and before the
		// instance may be freed. A body that freed itself (`queue_free()`) is left
		// to the message queue that already owns it; freeing it here as well would
		// hand the queue a dangling id.
		const bool queued_for_deletion = instance->is_queued_for_deletion();
		if (instance->get_parent() != nullptr) {
			instance->get_parent()->remove_child(instance);
		}

		if (call_error.error != Callable::CallError::CALL_OK) {
			r_error = MCPToolError::internal(vformat("the generated GDScript method could not be called (%s)",
					Variant::get_call_error_text(instance, method, nullptr, 0, call_error)));
			if (!queued_for_deletion) {
				memdelete(instance);
			}
			return Variant();
		}
		if (!queued_for_deletion) {
			memdelete(instance);
		}
	} else {
		// The fallback, kept byte for byte: a process with no reachable scene tree
		// behaves exactly as it did before this task - `extends RefCounted`, engine
		// singletons reachable, nothing mounted anywhere.
		Ref<RefCounted> instance;
		instance.instantiate();
		instance->set_script(script);

		const Callable entry_point(instance.ptr(), method);
		runtime = MCPTools::call_gdscript_capturing(entry_point, generated_script_path, body_start_line, result, call_error);
		if (call_error.error != Callable::CallError::CALL_OK) {
			r_error = MCPToolError::internal(vformat("the generated GDScript method could not be called (%s)",
					Variant::get_call_error_text(instance.ptr(), method, nullptr, 0, call_error)));
			return Variant();
		}
	}
	// [/REBUILT-2C]

	// -----------------------------------------------------------------------
	// TASK-103 (X-1): a body that compiled and then failed while it ran.
	//
	// The code is `-32000` (`MCP_ERR_TOOL_STATE`), the module's existing
	// convention for "the call is well formed but the state blocks it"
	// (GDR-14; `MCPToolError::tool_state`), and the reasoning is worth writing
	// down because two neighbours are wrong here:
	//
	//   * `-32602` (`invalid_params`, what the parse failure uses) means the
	//     *argument* was malformed. It was not: the body compiled - the engine
	//     accepted every line of it. Reusing `-32602` would tell a caller to fix
	//     its syntax when its syntax is fine;
	//   * `-32603` (`internal`, what a `Callable` failure uses) means *this
	//     module* is broken. It is not: the caller's code is the thing that
	//     failed, and the module correctly observed that it did.
	//
	// `-32000` is the one that says what happened: the tool ran, and the state the
	// caller asked for could not be produced. It also matches how the same family
	// is already spoken about (`not_implemented` and `no_scene` are `-32000`), and
	// it carries `data.suggestion`, which is what GDR-14 requires of it.
	// -----------------------------------------------------------------------
	if (runtime.error_seen) {
		const String where = runtime.in_caller_code
				? vformat("at line %d of 'code'", runtime.caller_line)
				: (runtime.generated_line > 0
								? vformat("at generated line %d (in the tool's own wrapper rather than in 'code')", runtime.generated_line)
								: String("while the body ran"));
		r_error = MCPToolError::tool_state(
				vformat("Parameter 'code' raised a GDScript runtime error %s: %s", where, runtime.diagnostic),
				"A GDScript runtime error aborts the frame: the statements after the failing one did not run and no side effect "
				"of the body can be assumed. Read data.script_error for the engine's own message, the line of 'code', the script "
				"path and the GDScript function it blames, then fix the body and call again. If the error names another script, "
				"the body reached game code that failed - check that script's own diagnostics.");

		Dictionary script_error;
		script_error["message"] = runtime.diagnostic;
		// The engine hands a handler a line, never a column (the same boundary the
		// parse capture documents), so the column is reported as absent rather than
		// invented.
		script_error["line"] = runtime.in_caller_code ? Variant((int64_t)runtime.caller_line) : Variant();
		script_error["column"] = Variant();
		script_error["generated_line"] = (int64_t)runtime.generated_line;
		script_error["in_caller_code"] = runtime.in_caller_code;
		script_error["script_path"] = runtime.script_path;
		script_error["function"] = runtime.function;
		script_error["in_generated_body"] = runtime.in_generated_body;
		// The identity this module reconstructed for the script it generated
		// (`gdscript://<instance id>.gd`). Reported next to `script_path` so the
		// comparison `in_generated_body` makes is auditable from the answer itself.
		script_error["body_script_path"] = generated_script_path;
		script_error["error_count"] = (int64_t)runtime.error_count;
		Array messages;
		for (int i = 0; i < runtime.messages.size(); i++) {
			messages.push_back(runtime.messages[i]);
		}
		script_error["messages"] = messages;

		// `tool_state()` already attached `data.suggestion`; the `script_error`
		// object is added next to it rather than replacing it.
		Dictionary data = r_error.data.get_type() == Variant::DICTIONARY ? (Dictionary)r_error.data : Dictionary();
		data["script_error"] = script_error;
		r_error.data = data;
		return Variant();
	}

	Dictionary answer;
	answer["result"] = serialize_variant(result);
	answer["result_type"] = Variant::get_type_name(result.get_type());
	// TASK-103 (X-1) requirement 2: "ok" on its own cannot tell "the body ran and
	// changed something" apart from "the body returned nothing and changed
	// nothing" - both answer `result: null` / `result_type: "Nil"`. The success
	// path has no JSON-RPC `error.data` to put a note in, so the note lives in the
	// tool's own result object, which is where the rest of the answer is.
	if (result.get_type() == Variant::NIL) {
		answer["note"] = "The body returned no value (result is null / result_type \"Nil\"). This is not evidence that the "
						 "body had an effect: it is also what a body with no `return`, and what a body whose statements were "
						 "all no-ops, answer. Confirm the effect separately (a property sample, a scene-tree snapshot, a "
						 "screenshot diff or a file sha) before treating this call as a change.";
	}
	return answer;
}

// The tool's argument half, and the one place that decides what the body can
// reach: the mount point is the running game's current scene root, or - when the
// current scene is not set but the tree is there - the tree's own root. With no
// `SceneTree` at all the core above keeps its pre-TASK-090 behaviour.
static Variant _tool_execute_gdscript(const Dictionary &p_args, MCPToolError &r_error) {
	String code;
	if (!require_string(p_args, "code", code, r_error)) {
		return Variant();
	}
	if (code.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'code' must not be empty");
		return Variant();
	}

	// TASK-090 (item B): the mount point. `get_current_scene()` is what the
	// contract now says the code runs next to; the tree root is the honest
	// fallback for a running game whose main scene is not set (a `--path` run with
	// no `run/main_scene`), where absolute paths still resolve.
	// [REBUILT-2C low-confidence: verify] TASK-090 item B: written, not replayed;
	// REBUILT-2C-MANIFEST.md 2c-9 (J-2).
	Node *mount_point = nullptr;
	SceneTree *tree = SceneTree::get_singleton();
	if (tree != nullptr) {
		mount_point = tree->get_current_scene();
		if (mount_point == nullptr) {
			// The tree root is a `RequiredResult<Window>` in this fork, whose
			// conversion the module already wraps once (`game_tree_root`).
			mount_point = game_tree_root(tree);
		}
	}
	// [/REBUILT-2C]

	return execute_gdscript_code(code, false, mount_point, r_error);
}

// ---------------------------------------------------------------------------
// Registration
//
// The declaration order follows docs/tool-groups-b2.json; channel, verb, scope
// and mutating come from docs/tool-rename-map.json and the description and
// `inputSchema` are a byte-exact copy of docs/tools_list.renamed.json, emitted
// by `scripts/gen_b2_game_schema.py` (re-running it reproduces this block).
// ---------------------------------------------------------------------------

void register_running_game_script_execution_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("running_game_execute_gdscript", String::utf8("在运行中的游戏内执行 GDScript 代码 有场景树时，代码体作为一个临时 Node 挂在当前场景根节点下执行：get_node()/$Path、节点属性、信号、get_tree() 均可用（路径以该临时节点为基准，绝对路径与 get_tree().current_scene 可达任意节点）；调用返回前该节点必定被移除（成功与失败同样处理），游戏自身的节点树不被改动；调用是同步的，临时节点存活不足一帧，_process/_physics_process 不会被触发。进程内没有场景树时回退为 extends RefCounted，仅全局单例可用。 运行期错误（能编译、但执行中失败，例如调用不存在的方法或方法名大小写错）回 -32000（tool_state：调用格式没问题，是这次执行失败），data.script_error 给出引擎原文 message、'code' 的行号 line（引擎只给行不给列，column 恒为 null）、生成源行号 generated_line、脚本路径 script_path（无路径脚本为 gdscript://<id>.gd）、被点名的 GDScript 函数 function 与错误条数 error_count，data.suggestion 给出改法；同一批事实也进 trace 的调用行（error_data_json），所以溯源里能直接看到这次为什么失败。运行期错误会中止该帧：出错行之后的语句没有执行，脚本的任何副作用都不能假定。脚本运行成功但 result 为 null/Nil 时响应带 note，说明 null 结果不是「有副作用」的证据，须另配效果证据（属性采样 / 场景树快照 / 像素差 / 文件 sha）。"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("要执行的 GDScript 代码");
		v1[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("code")] = v1;
		schema[String::utf8("properties")] = v0;
		Array v2;
		v2.push_back(String::utf8("code"));
		schema[String::utf8("required")] = v2;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("execute").scope(MCPToolScope::GAME).mutating(true).schema(schema).handler(_tool_execute_gdscript);
		builder.register_into(r_registry);
	}
	// END generated
}
