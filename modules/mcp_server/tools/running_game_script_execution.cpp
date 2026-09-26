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
//   * the code is compiled into `extends RefCounted` / `func _mcp_execute()` in
//     the process that serves the endpoint, and called once;
//   * the answer is
//     `{"result": <serialize_variant of the returned value>, "result_type":
//     "<Variant type name>"}`; a body without `return` answers
//     `{"result": null, "result_type": "nil"}`;
//   * `code` that does not compile is `-32602` ("does not compile: <verdict>") -
//     a malformed argument, not an internal failure;
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
//   * a *runtime* error inside the body (calling a missing method, a null
//     dereference) is reported by the engine on stderr and leaves the answer at
//     `{"result": null, "result_type": "nil"}`; GDScript has no exceptions and
//     the script language reports such errors through the engine log, so the
//     tool can not echo a structured failure without installing an error
//     handler that would swallow the engine's own diagnostics;
//   * `print()` output is not captured (it goes to the engine log);
//   * the code runs synchronously inside the frame that serves the request, so
//     it must not block and it cannot wait for frames (see
//     `running_game_frame_observation` in docs/tool-groups-b2.json).
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

static Variant _tool_execute_gdscript(const Dictionary &p_args, MCPToolError &r_error) {
	String code;
	if (!require_string(p_args, "code", code, r_error)) {
		return Variant();
	}
	if (code.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'code' must not be empty");
		return Variant();
	}
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
	// Both helpers are named `MCPTools::` on purpose: `tool_helpers.h` declares
	// `build_execute_gdscript_source` and `execute_gdscript_method_name` **twice**
	// - once inside `namespace MCPTools` (lines 1137 / 1112) and once after the
	// namespace closes (lines 1531 / 1513) - so an unqualified call in a file that
	// has `using namespace MCPTools;` is ambiguous (MSVC C2668, measured). The
	// duplicate declarations are a pre-existing hazard in the header and are
	// recorded in the report rather than removed here.
	String generated_source;
	int body_start_line = 0;
	MCPTools::build_execute_gdscript_source(code, false, generated_source, &body_start_line);
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

	// The generated source always extends `RefCounted`, so the instance is one.
	Ref<RefCounted> instance;
	instance.instantiate();
	instance->set_script(script);

	Callable::CallError call_error;
	// `Callable::callp` rather than `Object::call` / `Callable::call`: both of
	// those are variadic *templates* in this fork, and the explicit
	// `(const Variant **, int, CallError &)` form is the one that reports a call
	// failure instead of templating it away.
	const Callable entry_point(instance.ptr(), StringName(MCPTools::execute_gdscript_method_name()));
	Variant result;
	entry_point.callp(nullptr, 0, result, call_error);
	if (call_error.error != Callable::CallError::CALL_OK) {
		r_error = MCPToolError::internal(vformat("the generated GDScript method could not be called (%s)",
				Variant::get_call_error_text(instance.ptr(), StringName(MCPTools::execute_gdscript_method_name()), nullptr, 0, call_error)));
		return Variant();
	}

	Dictionary answer;
	answer["result"] = serialize_variant(result);
	answer["result_type"] = Variant::get_type_name(result.get_type());
	return answer;
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
		ToolBuilder builder("running_game_execute_gdscript", String::utf8("在运行中的游戏内执行 GDScript 代码"));

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
