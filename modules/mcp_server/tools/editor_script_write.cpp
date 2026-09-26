/**************************************************************************/
/*  editor_script_write.cpp                                               */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/
#include "editor_script_write.h"

#include "editor_set_node_script_batch.h"
#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/io/resource_loader.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/object/ref_counted.h"
#include "core/object/script_language.h"
#include "core/os/memory.h"
#include "core/string/string_name.h"
#include "core/variant/callable.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// editor_execute_gdscript (old `execute_editor_script`, editor.rs:353)
//
// One capability with `running_game_execute_gdscript` (TASK-010): compile the
// caller's GDScript body for real and answer `{"result","result_type"}` with the
// engine singletons reachable. The three differences that follow from *where* it
// runs are stated rather than hidden:
//
//   * the code runs in the **editor** process, so `EditorInterface`,
//     `EditorNode` and the edited scene are what a body can reach (that is the
//     migration source's own reason for having a second executor at all);
//   * it is *not* wrapped in `get_editor_ui()`: the tool touches no
//     `EditorInterface` accessor itself, and refusing a headless editor whose
//     `EditorNode` has not started yet would refuse a legitimate request for no
//     safety gain (the runtime guard exists for unchecked dereferences, see
//     `require_editor_ui`);
//   * the body runs on the main thread inside the frame that serves the request.
//     There is no timeout to install - GDScript touches the scene tree, so the
//     call cannot be moved off the main thread - and the one bound that can be
//     enforced honestly is the size of the injected source (`max_gdscript_bytes()`).
//
// Migration source comparison (editor_commands.gd:353-412):
//   * it wrapped the code in a `@tool extends Node` script and ran it through a
//     temporary child node (`add_child(temp_node)` + `temp_node.run()`). Nothing
//     about the caller's code needs a node in the tree, and the temporary node
//     became a real child of the plugin's own scene for one frame; this
//     implementation uses the same `extends RefCounted` instance the game-side
//     executor uses, which also keeps the two executors' behaviour comparable;
//   * it answered `{"output": [...], "return_value": str(output)}` - the
//     stringified value, and an `_mcp_output` array fed by a `_mcp_print`
//     helper the caller had to know about. The answer here is structured, and
//     `print()` is left where every other script's output goes: the engine log;
//   * a compile failure was `-32002` in the migration source, a code that is not
//     in this module's error contract (GDR-6/GDR-14). It is `-32602` here, the
//     same as the game-side executor's "does not compile".
// ---------------------------------------------------------------------------

namespace MCPTools {

int64_t max_gdscript_bytes() {
	return 249 * 1024;
}

bool execute_gdscript(const String &p_code, Dictionary &r_out, MCPToolError &r_error) {
	if (p_code.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'code' must not be empty");
		return false;
	}
	const int64_t byte_length = (int64_t)p_code.utf8().length();
	if (byte_length > max_gdscript_bytes()) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'code' is %d bytes, above the %d byte limit of this tool. Split the work into several calls "
				"(the code runs synchronously in the editor's main thread, so its size is the bound this tool can "
				"enforce)",
				(int)byte_length, (int)max_gdscript_bytes()));
		return false;
	}
	// The script languages are a second, independent prerequisite, exactly as in
	// the game-side executor: `ScriptServer::init_languages()` runs from
	// `Main::setup2()` (main/main.cpp:3863), and the `--test` entry point runs
	// before that, so a test binary would get "does not compile" instead of the
	// real reason.
	if (!ScriptServer::are_languages_initialized()) {
		r_error = MCPToolError::not_implemented("execution of GDScript before the script languages are initialised",
				"This process has no script language yet; call this tool in a running editor, where the engine initialises them");
		return false;
	}

	// Asking `ClassDB` instead of including the gdscript module keeps this group
	// free of a module-to-module dependency; a build without GDScript gets an
	// explicit capability refusal instead of a link error.
	Object *raw = ClassDB::instantiate("GDScript");
	Ref<Script> script = Object::cast_to<Script>(raw);
	if (script.is_null()) {
		if (raw != nullptr) {
			memdelete(raw);
		}
		r_error = MCPToolError::not_implemented("execution of GDScript in this engine build",
				"This build has no GDScript language; use a build with the gdscript module enabled");
		return false;
	}

	String generated_source;
	int body_start_line = 0;
	// `p_tool_script = true`: the code runs in the editor process, and Godot
	// refuses to instantiate a non-`@tool` script while the editor is running
	// (`GDScript::can_instantiate()` is
	// `valid && (is_tool() || !Engine::is_editor_hint())`). Without the
	// annotation every call of this tool answered `-32602` - first measured on
	// the wire as "does not compile: OK", which is REPORT-018's D-4.
	build_execute_gdscript_source(p_code, true, generated_source, &body_start_line);
	script->set_source_code(generated_source);
	// TASK-063 (d): `reload()` alone answers a bare `Error`, and the round-2
	// trace measured 7 fail-then-succeed pairs that each cost a call because the
	// caller was told only "Parse error". The capture around the call reads the
	// line the engine itself reports (`_err_print_error("GDScript::reload", ...,
	// <line>, ...)`), and `body_start_line` turns that generated line into a line
	// of `code`.
	const GDScriptReloadReport reload = reload_gdscript_capturing(script.ptr(), body_start_line);
	if (reload.error != OK) {
		r_error = MCPToolError::invalid_params(gdscript_reload_failure_text(reload));
		if (reload.diagnostic_seen) {
			// The same facts, machine-readable: the line of `code` (0/absent when
			// the engine's line is in the wrapper), the line the engine named in
			// the generated source, and every diagnostic the engine printed.
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
			// The engine hands a handler a line, never a column: `ParserError`
			// carries `start_column`/`end_column`
			// (`modules/gdscript/gdscript_parser.h:273-288`) but the call site
			// drops them before any handler runs (`gdscript.cpp:828`), so the
			// boundary is stated instead of a column being invented.
			data["parse_error_column"] = Variant();
			r_error.data = data;
		}
		return false;
	}
	if (!script->can_instantiate()) {
		r_error = MCPToolError::invalid_params(
				"Parameter 'code' compiled but produced a GDScript the editor cannot instantiate");
		return false;
	}

	// The generated source always extends `RefCounted`, so the instance is one.
	Ref<RefCounted> instance;
	instance.instantiate();
	instance->set_script(script);

	Callable::CallError call_error;
	const Callable entry_point(instance.ptr(), StringName(execute_gdscript_method_name()));
	Variant result;
	entry_point.callp(nullptr, 0, result, call_error);
	if (call_error.error != Callable::CallError::CALL_OK) {
		r_error = MCPToolError::internal(vformat("the generated GDScript method could not be called (%s)",
				Variant::get_call_error_text(instance.ptr(), StringName(execute_gdscript_method_name()), nullptr, 0, call_error)));
		return false;
	}

	Dictionary answer;
	answer["result"] = serialize_variant(result);
	answer["result_type"] = Variant::get_type_name(result.get_type());
	r_out = answer;
	return true;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// editor_set_node_script (old `attach_script`, script.rs:282)
//
// Observable contract (as implemented):
//   * `node_path` and `script_path` are both required and both non-blank; the
//     node is resolved with the module's editor `find_node` semantics
//     (`MCPTools::find_node`), the script path is normalized by
//     `normalize_project_path` (PLAYBOOK section 6.7) and must exist;
//   * the file has to load as a `Script`; a file that exists but is something
//     else is `-32602` (the argument names a non-script), a file that cannot be
//     loaded at all is `-32000`;
//   * the answer reports the script the node **really carries** after the write
//     (`node->get_script()`), plus `previous_script_path`, so a node that
//     refused the attachment cannot be reported as `attached: true`. The
//     migration source answered the constant `{"attached": true}` next to an
//     UndoRedo action that had not run yet (script.rs:310-320);
//   * the migration source's UndoRedo wrapping is not reproduced: the editor
//     write groups of this module act on the live scene directly
//     (`editor_node_write`, TASK-015), and one tool of one batch registering its
//     own `EditorUndoRedoManager` action would be the only place in the module
//     that behaves differently. Recorded as a divergence in REPORT-018.
// ---------------------------------------------------------------------------
static Variant _tool_set_node_script(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_path' must not be empty");
		return Variant();
	}
	String raw_script_path;
	if (!require_string(p_args, "script_path", raw_script_path, r_error)) {
		return Variant();
	}
	if (raw_script_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'script_path' must not be empty");
		return Variant();
	}
	String script_path;
	if (!normalize_project_path(raw_script_path, script_path, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor script writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Node *node = find_node(root, node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", node_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}
	// The file must be there before the load: `ResourceLoader::load()` on a
	// missing path answers an engine error and null, which would be reported as
	// "could not load" instead of "there is no such script".
	if (!FileAccess::exists(script_path)) {
		r_error = MCPToolError::not_found(vformat("Script '%s'", script_path),
				"Use project_list_scripts to find the script, or project_create_script to create it");
		return Variant();
	}
	const Ref<Resource> loaded = ResourceLoader::load(script_path, "", ResourceLoader::CACHE_MODE_REUSE);
	if (loaded.is_null()) {
		r_error = MCPToolError::tool_state(vformat("Script '%s' could not be loaded", script_path),
				"Check the file with project_validate_script; a script with a syntax error does not load");
		return Variant();
	}
	const Ref<Script> script = loaded;
	if (script.is_null()) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'script_path' must name a script, but '%s' is a %s", script_path, loaded->get_class()));
		return Variant();
	}

	const Ref<Script> previous = node->get_script();
	const String previous_path = previous.is_valid() ? previous->get_path() : String();
	// TASK-075 (D2): the engine's own compatibility rule, read before the write.
	// `Object::set_script()` cannot answer it in an editor process - scripting is
	// off for this process (editor/editor_node.cpp:8523), so the placeholder
	// branch is taken and `get_script()` reports a script the engine will drop
	// when the scene is loaded (`GDScript::instance_create()`,
	// modules/gdscript/gdscript.cpp:420-426). The same check the batch tool makes,
	// so the two cannot disagree about what "attached" means.
	if (!MCPTools::script_readable_on(node, script)) {
		const String node_class = node->get_class();
		r_error = MCPToolError::tool_state(
				MCPTools::script_incompatible_message(script, relative_path(root, node), node_class),
				MCPTools::script_incompatible_suggestion(script, node_class));
		return Variant();
	}
	node->set_script(script);
	// Read back, never assume: what the node carries now is what the answer says.
	const Ref<Script> attached = node->get_script();
	if (attached.is_null()) {
		r_error = MCPToolError::tool_state(vformat("Node '%s' did not accept the script '%s'",
												  node->get_name(), script_path),
				"Some node types have no script slot; attach the script to a node that can hold one "
				"(a plain Node, Node2D, Node3D, Control, ...)");
		return Variant();
	}

	Dictionary out;
	out["node_path"] = relative_path(root, node);
	out["script_path"] = attached->get_path();
	out["attached"] = true;
	out["previous_script_path"] = previous_path;
	return out;
}

// ---------------------------------------------------------------------------
// Registration
//
// The `description` and `inputSchema` below are the contract entries of
// docs/tools_list.renamed.json, character for character; `channel`/`verb`/
// `scope`/`mutating` come from docs/tool-rename-map.json.
// ---------------------------------------------------------------------------

static Variant _tool_execute_gdscript(const Dictionary &p_args, MCPToolError &r_error) {
	String code;
	if (!require_string(p_args, "code", code, r_error)) {
		return Variant();
	}
	Dictionary out;
	if (!execute_gdscript(code, out, r_error)) {
		return Variant();
	}
	return out;
}

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_script_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_script_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_execute_gdscript", String::utf8(R"desc(在编辑器上下文中执行 GDScript 代码)desc"));
		builder.channel("editor").verb("execute").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"code":{"description":"要执行的 GDScript 代码","type":"string"}},"required":["code"],"type":"object"})schema"));
		builder.handler(_tool_execute_gdscript).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_node_script", String::utf8(R"desc(为节点附加脚本)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"},"script_path":{"type":"string"}},"required":["node_path","script_path"],"type":"object"})schema"));
		builder.handler(_tool_set_node_script).register_into(r_registry);
	}
}
