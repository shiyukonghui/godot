/**************************************************************************/
/*  editor_set_node_script_batch.cpp                                      */
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
#include "editor_set_node_script_batch.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/io/resource_loader.h"

using namespace MCPTools;

namespace {

// One entry of the work list, exactly as the refusal has to describe it.
struct _Assignment {
	int index = 0;
	Node *node = nullptr;
	String node_path;
	Ref<Script> previous;
	String previous_path;
};

Dictionary _error_entry(int p_index, const String &p_node_path, const String &p_reason) {
	Dictionary entry;
	entry["index"] = p_index;
	entry["node_path"] = p_node_path;
	entry["reason"] = p_reason;
	return entry;
}

// The all-or-nothing envelope of a refused batch. `rolled_back` is the boolean
// the call's contract names, and `reverted` is the list of nodes whose previous
// script really was put back - the two are separate fields because "the batch
// left nothing behind" (always true of a refusal) and "something had to be taken
// back" (only true when a later node failed) are different facts, and a caller
// reading only one of them should not have to guess the other.
//
// The shape deliberately mirrors `editor_add_nodes_batch`'s `data.batch`; the one
// divergence is that its `rolled_back` is the *list* and here the list is called
// `reverted`, because `editor_set_node_script_batch`'s own wording fixes
// `rolled_back` as the boolean.
Dictionary _refusal_envelope(const Array &p_errors, const Array &p_reverted, const Array &p_skipped,
		const String &p_script_path, bool p_keep_existing) {
	Dictionary envelope;
	envelope["status"] = "rolled_back";
	envelope["rolled_back"] = true;
	envelope["attached"] = Array();
	envelope["count"] = 0;
	envelope["reverted"] = p_reverted;
	envelope["skipped"] = p_skipped;
	envelope["errors"] = p_errors;
	envelope["script_path"] = p_script_path;
	envelope["keep_existing"] = p_keep_existing;
	envelope["on_error"] = "all_or_nothing";
	return envelope;
}

MCPToolError _with_envelope(MCPToolError p_error, const Dictionary &p_envelope, const String &p_suggestion) {
	Dictionary data;
	if (p_error.data.get_type() == Variant::DICTIONARY) {
		data = p_error.data;
	}
	data["batch"] = p_envelope;
	data["suggestion"] = p_suggestion;
	p_error.data = data;
	return p_error;
}

// Takes every already-applied assignment back, newest first, and reads each one
// back. A node whose previous script could not be restored is named in the
// answer: a rollback that silently failed would be worse than the failure it is
// answering.
Array _revert(const Vector<_Assignment> &p_applied) {
	Array reverted;
	for (int i = p_applied.size() - 1; i >= 0; i--) {
		const _Assignment &assignment = p_applied[i];
		Dictionary entry;
		entry["index"] = assignment.index;
		entry["node_path"] = assignment.node_path;
		entry["restored_script_path"] = assignment.previous_path;
		entry["restored"] = restore_node_script(assignment.node, assignment.previous);
		reverted.push_back(entry);
	}
	return reverted;
}

Variant _fail(const String &p_message, int p_code, const String &p_suggestion, const Array &p_errors,
		const Vector<_Assignment> &p_applied, const Array &p_skipped, const String &p_script_path,
		bool p_keep_existing, MCPToolError &r_error) {
	const Array reverted = _revert(p_applied);
	MCPToolError error;
	switch (p_code) {
		case MCP_ERR_NOT_FOUND:
			error = MCPToolError::not_found(p_message, p_suggestion);
			break;
		case MCP_ERR_TOOL_STATE:
			error = MCPToolError::tool_state(p_message, p_suggestion);
			break;
		default:
			error = MCPToolError::invalid_params(p_message);
			break;
	}
	r_error = _with_envelope(error, _refusal_envelope(p_errors, reverted, p_skipped, p_script_path, p_keep_existing), p_suggestion);
	return Variant();
}

// The engine's `Array of string` rule for this file, with the element index in
// every refusal. An absent `node_paths` is the contract's required-parameter
// refusal (the same wording every `require_*` helper uses), never "an array of
// Nil".
bool _require_node_paths(const Dictionary &p_args, Array &r_out, MCPToolError &r_error) {
	const Variant raw = p_args.get("node_paths", Variant());
	if (raw.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter: node_paths");
		return false;
	}
	if (raw.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(
				"Parameter 'node_paths' must be an array of strings, got " + Variant::get_type_name(raw.get_type()));
		return false;
	}
	const Array values = raw;
	if (values.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_paths' must name at least one node");
		return false;
	}
	for (int i = 0; i < values.size(); i++) {
		const Variant element = values[i];
		if (element.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'node_paths[%d]' must be a string, got %s",
					i, Variant::get_type_name(element.get_type())));
			return false;
		}
		if (((String)element).strip_edges().is_empty()) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'node_paths[%d]' must not be empty", i));
			return false;
		}
	}
	r_out = values;
	return true;
}

const char *const ROLLBACK_SUGGESTION =
		"editor_set_node_script_batch is all-or-nothing: no node of the request kept the script. Fix the entry the "
		"message names (a node that is not there, or a script that cannot be attached) and call the tool again.";

} // namespace

namespace MCPTools {

bool script_readable_on(Node *p_node, const Ref<Script> &p_script) {
	if (p_node == nullptr || p_script.is_null()) {
		return false;
	}
	const StringName base = p_script->get_instance_base_type();
	// The engine's own guard (`modules/gdscript/gdscript.cpp:420`,
	// `modules/mono/csharp_script.cpp:2461`): the question is only asked when the
	// script names a native base type.
	if (base == StringName()) {
		return true;
	}
	return p_node->is_class(base);
}

String script_incompatible_message(const Ref<Script> &p_script, const String &p_node_path, const String &p_node_class) {
	return vformat("Node '%s' (%s) cannot carry script '%s': the script inherits from native type '%s', which is not "
				   "a class of this node, so the engine would drop the attachment when the scene is loaded",
			p_node_path, p_node_class, p_script->get_path(), p_script->get_instance_base_type());
}

String script_incompatible_suggestion(const Ref<Script> &p_script, const String &p_node_class) {
	return vformat("The engine attaches a script only when the script's native base type is a class of the node "
				   "(GDScript::instance_create(), modules/gdscript/gdscript.cpp:420-426; CSharpScript::instance_create(), "
				   "modules/mono/csharp_script.cpp:2461-2465) - the editor process takes the placeholder branch instead "
				   "(Object::set_script(), core/object/object.cpp:1069-1072) and so cannot report the mismatch by itself. "
				   "Attach '%s' to a node that is a '%s' (or a subclass of it), or change the script's 'extends' to a "
				   "class of '%s'",
			p_script->get_path(), p_script->get_instance_base_type(), p_node_class);
}

bool apply_node_script(Node *p_node, const Ref<Script> &p_script, MCPToolError &r_error) {
	// TASK-075 (D2): the compatibility reading comes first, because the read-back
	// below cannot see this failure in an editor process (the placeholder branch
	// makes `get_script()` answer the script for a node the engine will refuse).
	if (!script_readable_on(p_node, p_script)) {
		const String node_path = p_node->is_inside_tree() ? String(p_node->get_path()) : String(p_node->get_name());
		r_error = MCPToolError::tool_state(
				script_incompatible_message(p_script, node_path, p_node->get_class()),
				script_incompatible_suggestion(p_script, p_node->get_class()));
		return false;
	}
	p_node->set_script(p_script);
	// Read back, never assume. `Object::set_script()` returns early - leaving the
	// node exactly as it was - for an abstract script, and stores nothing at all
	// for a script that cannot be instantiated outside the editor, so a null
	// `get_script()` here is a *measured* refusal and not a defensive check.
	const Ref<Script> attached = p_node->get_script();
	if (attached.is_null() || attached->get_path() != p_script->get_path()) {
		r_error = MCPToolError::tool_state(
				vformat("Node '%s' did not accept the script '%s'", p_node->get_name(), p_script->get_path()),
				"The engine refuses some scripts (an 'abstract' script is refused outright, and a script that cannot "
				"be instantiated is only attached as a placeholder inside the editor); use project_validate_scripts to "
				"see the script's own verdict, and attach it to a node that can hold it");
		return false;
	}
	return true;
}

bool restore_node_script(Node *p_node, const Ref<Script> &p_previous) {
	p_node->set_script(p_previous);
	const Ref<Script> now = p_node->get_script();
	if (p_previous.is_null()) {
		return now.is_null();
	}
	return now.is_valid() && now->get_path() == p_previous->get_path();
}

Variant assign_node_scripts_batch_on(Node *p_root, const Array &p_node_paths, const String &p_script_path,
		bool p_keep_existing, Dictionary &r_out, MCPToolError &r_error) {
	Array skipped;
	Array no_errors;

	// (1) The script, once, before anything is touched. The same three refusals
	//     `editor_set_node_script` answers: no such file -> -32001, a file that
	//     cannot be loaded -> -32000, a file that is not a script -> -32602.
	if (!FileAccess::exists(p_script_path)) {
		Array errors;
		errors.push_back(_error_entry(-1, String(), vformat("Script '%s' does not exist", p_script_path)));
		return _fail(vformat("Script '%s'", p_script_path), MCP_ERR_NOT_FOUND,
				"Use project_list_scripts to find the script, or project_create_script to create it",
				errors, Vector<_Assignment>(), skipped, p_script_path, p_keep_existing, r_error);
	}
	const Ref<Resource> loaded = ResourceLoader::load(p_script_path, "", ResourceLoader::CACHE_MODE_REUSE);
	if (loaded.is_null()) {
		Array errors;
		errors.push_back(_error_entry(-1, String(), vformat("Script '%s' could not be loaded", p_script_path)));
		return _fail(vformat("Script '%s' could not be loaded", p_script_path), MCP_ERR_TOOL_STATE,
				"Check the file with project_validate_scripts; a script with a syntax error does not load",
				errors, Vector<_Assignment>(), skipped, p_script_path, p_keep_existing, r_error);
	}
	const Ref<Script> script = loaded;
	if (script.is_null()) {
		Array errors;
		errors.push_back(_error_entry(-1, String(),
				vformat("'%s' loads as a %s, which is not a script", p_script_path, loaded->get_class())));
		return _fail(vformat("Parameter 'script_path' must name a script, but '%s' is a %s", p_script_path, loaded->get_class()),
				MCP_ERR_INVALID_PARAMS,
				"Pass a '.gd' (or '.cs' in a Mono build) script path; project_list_scripts lists the scripts of the project",
				errors, Vector<_Assignment>(), skipped, p_script_path, p_keep_existing, r_error);
	}

	// (2) Every node, before anything is touched.
	Vector<ObjectID> nodes;
	for (int i = 0; i < p_node_paths.size(); i++) {
		const String node_path = p_node_paths[i];
		Node *node = find_node(p_root, node_path);
		if (node == nullptr) {
			Array errors;
			errors.push_back(_error_entry(i, node_path, vformat("Node '%s' is not in the edited scene", node_path)));
			// TASK-063 (b): the plural half of the one rule sentence, so this
			// refusal says which parameter it is, that the path is relative to the
			// edited scene root and that the singular tools spell it `path`.
			return _fail(vformat("Node '%s'", node_path), MCP_ERR_NOT_FOUND,
					node_path_guidance("node_paths", true), errors,
					Vector<_Assignment>(), skipped, p_script_path, p_keep_existing, r_error);
		}
		nodes.push_back(node->get_instance_id());
	}

	// (3) The work list. `keep_existing` is answered from what the node really
	//     carries right now, and a skipped node is reported with the script it
	//     kept - never quietly replaced.
	Vector<_Assignment> pending;
	for (int i = 0; i < nodes.size(); i++) {
		Node *node = ObjectDB::get_instance<Node>(nodes[i]);
		if (node == nullptr) {
			// Unreachable in one synchronous call (nothing runs between the
			// resolve above and here), kept because the id is the only handle
			// that stays valid if it ever is not.
			Array errors;
			errors.push_back(_error_entry(i, p_node_paths[i], "The node disappeared before the write"));
			return _fail(vformat("Node '%s'", p_node_paths[i]), MCP_ERR_NOT_FOUND,
					"Use editor_get_scene_tree to list the nodes of the edited scene, then call the tool again",
					errors, Vector<_Assignment>(), skipped, p_script_path, p_keep_existing, r_error);
		}
		_Assignment assignment;
		assignment.index = i;
		assignment.node = node;
		assignment.node_path = relative_path(p_root, node);
		assignment.previous = node->get_script();
		assignment.previous_path = assignment.previous.is_valid() ? assignment.previous->get_path() : String();

		if (p_keep_existing && assignment.previous.is_valid()) {
			Dictionary entry;
			entry["index"] = i;
			entry["node_path"] = assignment.node_path;
			entry["previous_script_path"] = assignment.previous_path;
			entry["skipped"] = true;
			entry["reason"] = "the node already carries a script and 'keep_existing' is true";
			skipped.push_back(entry);
			continue;
		}
		// TASK-075 (D2): the compatibility reading is a *pre-flight* check, so an
		// incompatible node refuses the whole call before anything is touched -
		// exactly like a node that is not there, and for the same reason: the
		// answer must not report `attached: true` for an attachment the engine
		// will drop when the scene is loaded. `readable: false` is the per-node
		// signal the contract promises ("whether the attachment landed and the
		// script was readable"); it is measured, never assumed.
		if (!script_readable_on(node, script)) {
			Array errors;
			Dictionary entry = _error_entry(i, assignment.node_path,
					script_incompatible_message(script, assignment.node_path, node->get_class()));
			entry["readable"] = false;
			errors.push_back(entry);
			return _fail(vformat("nodes[%d]: %s", i, script_incompatible_message(script, assignment.node_path, node->get_class())),
					MCP_ERR_TOOL_STATE, script_incompatible_suggestion(script, node->get_class()), errors,
					Vector<_Assignment>(), skipped, p_script_path, p_keep_existing, r_error);
		}
		pending.push_back(assignment);
	}

	// (4) The commit phase: apply, read back, and on the first refusal take every
	//     node that already landed back to what it carried.
	Vector<_Assignment> applied;
	Array attached;
	for (int i = 0; i < pending.size(); i++) {
		const _Assignment &assignment = pending[i];
		MCPToolError write_error;
		if (!apply_node_script(assignment.node, script, write_error)) {
			Array errors;
			errors.push_back(_error_entry(assignment.index, assignment.node_path, write_error.message));
			return _fail(vformat("nodes[%d]: %s", assignment.index, write_error.message),
					MCP_ERR_TOOL_STATE, ROLLBACK_SUGGESTION, errors, applied, skipped, p_script_path,
					p_keep_existing, r_error);
		}
		applied.push_back(assignment);

		// TASK-075 (D2): the read-back's own verdict, asked again after the write
		// - `apply_node_script` measured it, and so does this line, because the
		// contract's `readable` field is a per-node answer and a constant `true`
		// would be a claim about the engine rather than a measurement of it. A
		// node that turned out unreadable after the write takes the whole call
		// back like any other refusal.
		const bool readable = script_readable_on(assignment.node, script);
		if (!readable) {
			Array errors;
			Dictionary entry = _error_entry(assignment.index, assignment.node_path,
					script_incompatible_message(script, assignment.node_path, assignment.node->get_class()));
			entry["readable"] = false;
			errors.push_back(entry);
			return _fail(vformat("nodes[%d]: %s", assignment.index, script_incompatible_message(script, assignment.node_path, assignment.node->get_class())),
					MCP_ERR_TOOL_STATE, script_incompatible_suggestion(script, assignment.node->get_class()), errors,
					applied, skipped, p_script_path, p_keep_existing, r_error);
		}

		Dictionary entry;
		entry["index"] = assignment.index;
		entry["node_path"] = assignment.node_path;
		entry["script_path"] = script->get_path();
		entry["previous_script_path"] = assignment.previous_path;
		// The read-back's own verdict, asked again after the write: the field is
		// `true` only because `apply_node_script` measured it - and `readable` is
		// the same measurement spelled as the contract promises it.
		entry["attached"] = true;
		entry["readable"] = readable;
		attached.push_back(entry);
	}

	Dictionary result;
	result["status"] = "ok";
	result["script_path"] = script->get_path();
	result["keep_existing"] = p_keep_existing;
	result["attached"] = attached;
	result["skipped"] = skipped;
	result["count"] = attached.size();
	result["errors"] = no_errors;
	r_out = result;
	return result;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tool
// ---------------------------------------------------------------------------
static Variant _tool_set_node_script_batch(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_script_path;
	if (!require_string(p_args, "script_path", raw_script_path, r_error)) {
		return Variant();
	}
	if (raw_script_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'script_path' must not be empty");
		return Variant();
	}
	Array node_paths;
	if (!_require_node_paths(p_args, node_paths, r_error)) {
		return Variant();
	}
	bool keep_existing = false;
	if (!optional_bool(p_args, "keep_existing", false, keep_existing, r_error)) {
		return Variant();
	}
	String script_path;
	if (!normalize_project_path(raw_script_path, script_path, r_error)) {
		// `normalize_project_path` answers the module's canonical `-32602`; the
		// suggestion is added here because only this tool knows what it is
		// asking for (the registry keeps a handler's own suggestion).
		Dictionary data;
		data["suggestion"] = "'script_path' must address the project ('res://...') and must not contain a '..' segment: this tool attaches scripts of the project";
		r_error.data = data;
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
	Dictionary out;
	return MCPTools::assign_node_scripts_batch_on(root, node_paths, script_path, keep_existing, out, r_error);
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// `docs/tools_list.renamed.json`, character for character - and that entry is
// generated from `ADDED_TOOLS` in `scripts/gen_renamed_contract.py` (GDR-28
// point 1: an added entry is authored by the decision maker, never by this
// file).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Registration.
//
// The contract entry is the one `ADDED_TOOLS` authors, and TASK-063 (b) appended
// the plural half of the node-path rule to it: the parameter name (`node_paths`)
// and the basis (relative to the edited scene root, `/root/...` refused) are now
// in the text a caller reads, because the round-2 trace spent 39 calls of this
// tool learning them. The schema did not move.
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_set_node_script_batch.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_set_node_script_batch_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_set_node_script_batch",
				String::utf8(R"desc(Attach one script to many nodes in the edited scene in a single call, and answer per node whether the attachment landed and the script was readable. 'node_paths' is an array of node paths resolved relative to the edited scene root - the same strings the singular tools take under the name 'path' (editor_set_node_property, editor_get_node_properties): 'Bricks/Car' and './Bricks/Car' address 'Car' inside 'Bricks', and the edited scene root's own name may be used as a prefix ('Main/Bricks/Car' == 'Bricks/Car' == './Bricks/Car'). An absolute scene-tree path ('/root/Main/Bricks/Car') is not accepted, and a bare name such as 'Car' only addresses a direct child of the edited scene root. A refused path names this rule in data.suggestion.)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"keep_existing":{"default":false,"type":"boolean"},"node_paths":{"items":{"type":"string"},"type":"array"},"script_path":{"type":"string"}},"required":["node_paths","script_path"],"type":"object"})schema"));
		builder.handler(_tool_set_node_script_batch).register_into(r_registry);
	}
}