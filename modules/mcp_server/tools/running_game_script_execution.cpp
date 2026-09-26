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

	String generated_source;
	int body_start_line = 0;
	build_execute_gdscript_source(code, false, generated_source, &body_start_line);
	script->set_source_code(generated_source);
	// TASK-063 (d): the same capture the editor executor uses (one definition in
	// `tool_helpers.cpp`), so the two endpoints answer the same parse error with
	// the same text and the same line - the game-side executor had the identical
	// "Parse error, no line" gap.
	const GDScriptReloadReport reload = reload_gdscript_capturing(script.ptr(), body_start_line);
	if (reload.error != OK) {
		// The engine has already printed the parser's own diagnostics (with the
		// line of the *generated* source) to stderr; this message carries the
		// verdict the caller can act on, including the line mapped back to `code`.
		r_error = MCPToolError::invalid_params(gdscript_reload_failure_text(reload));
		if (reload.diagnostic_seen) {
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
			data["parse_error_column"] = Variant();
			r_error.data = data;
		}
		return Variant();
	}
	if (!script->can_instantiate()) {
		// TASK-018 section 3: `reload()` answering OK while the script cannot be
		// instantiated is a real state (measured: the editor refuses a non-`@tool`
		// script), and reporting it as "does not compile: OK" was a nonsense
		// message. The two states are answered separately now.
		r_error = MCPToolError::invalid_params(
				"Parameter 'code' compiled but produced a GDScript this process cannot instantiate");
		return Variant();
	}

	// The generated source always extends `RefCounted`, so the instance is one.
	Ref<RefCounted> instance;
	instance.instantiate();
	instance->set_script(script);

	Callable::CallError call_error;
	// `Callable::callp` rather than `Object::call` / `Callable::call`: both of
	// those are variadic *templates* in this fork, and the explicit
	// `(const Variant **, int, CallError &)` form is the one that reports a call
	// failure instead of templating it away.
	const Callable entry_point(instance.ptr(), StringName(execute_gdscript_method_name()));
	Variant result;
	entry_point.callp(nullptr, 0, result, call_error);
	if (call_error.error != Callable::CallError::CALL_OK) {
		r_error = MCPToolError::internal(vformat("the generated GDScript method could not be called (%s)",
				Variant::get_call_error_text(instance.ptr(), StringName(execute_gdscript_method_name()), nullptr, 0, call_error)));
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
			memdelete(raw);
		}
		r_error = MCPToolError::not_implemented("execution of GDScript in this engine build",
				"This build has no GDScript language; use a build with the gdscript module enabled");
		return Variant();
	}

	script->set_source_code(_build_source(code));
	const Error reload_error = script->reload();
	if (reload_error != OK || !script->can_instantiate()) {
		// The engine has already printed the parser's own diagnostics (with the
		// line of the *generated* source) to stderr; the message here carries
		// the verdict the caller can act on.
		r_error = MCPToolError::invalid_params(vformat("Parameter 'code' does not compile: %s",
				VariantUtilityFunctions::error_string(reload_error)));
		return Variant();
	}

	// The generated source always extends `RefCounted`, so the instance is one.
	Ref<RefCounted> instance;
	instance.instantiate();
	instance->set_script(script);

	Callable::CallError call_error;
	// `Callable::callp` rather than `Object::call` / `Callable::call`: both of
	// those are variadic *templates* in this fork, and the explicit
	// `(const Variant **, int, CallError &)` form is the one that reports a call
	// failure instead of templating it away.
	const Callable entry_point(instance.ptr(), StringName(MCP_EXECUTE_METHOD));
	Variant result;
	entry_point.callp(nullptr, 0, result, call_error);
	if (call_error.error != Callable::CallError::CALL_OK) {
		r_error = MCPToolError::internal(vformat("the generated GDScript method could not be called (%s)",
				Variant::get_call_error_text(instance.ptr(), StringName(MCP_EXECUTE_METHOD), nullptr, 0, call_error)));
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