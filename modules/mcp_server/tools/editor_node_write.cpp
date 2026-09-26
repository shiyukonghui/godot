/**************************************************************************/
/*  editor_node_write.cpp                                                 */
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
#include "editor_node_write.h"

#include "tool_builder.h"
#include "tool_helpers.h"
// The one definition of "does this object really have this property, and how is
// the caller's JSON value coerced into it" - TASK-014 D-1 established the
// editor-side node write's shape there and TASK-015 section 2 makes that shape
// this group's rule too. The two helpers are declared in that header on purpose
// (`vector_from_dictionary` / `write_node_property`), so this is a use of a
// published entry point and not a reach into another group's file-private code.
#include "running_game_node_write.h"

#include "core/io/json.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/os/memory.h"
#include "core/string/node_path.h"
#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"

// The compile-time half of the editor guard (TASK-002 section 2.2.3). In a game
// build (`TOOLS_ENABLED` undefined) none of the includes below and none of the
// guarded call sites exist at all - the ten tools are still *compiled*, because
// the group file is shared, but every editor-only branch collapses into a clean
// -32000 answer.
#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/editor_interface.h"
#include "editor/editor_node.h"
#endif

using namespace MCPTools;

// The runtime half of the editor guard lives in `tools/tool_helpers.*` and is
// called below as `require_editor_ui(r_error, <non-editor wording>,
// <suggestion>)`; the `EditorInterface` / `EditorNode` null-check reasoning is
// documented next to that single definition.

// The edited scene root and the migration source's node resolution were hoisted
// into `tools/tool_helpers.*` by TASK-016 section 1 (`MCPTools::edited_scene_root`
// / `MCPTools::find_node`), together with the `SceneTree` vs `EditorInterface`
// reasoning that used to be documented here. This file now calls the one
// definition instead of keeping a fifth and sixth copy.

// The migration source's own spelling for a node it returns: the path relative
// to the edited scene root, with the root itself as "." (`root.get_path_to(node)`
// in node.rs, and `_selection_entry()` of `editor_write_scene_editor.cpp`). Used
// for every `node_path` / `source` / `target` / `path` this group answers with,
// so a caller can feed the answer straight back into another tool of the group.
//
// TASK-017's three groups copied this function byte for byte; the repair pass
// hoisted it to `MCPTools::relative_path` (`tools/tool_helpers.*`) and removed
// all four file-private copies (this one included).

// An optional `properties`-style object. A present-but-not-an-object value is
// `-32602` (PLAYBOOK section 6.2: a silently ignored argument is how a caller
// ends up believing it configured something); an absent one is the empty map.
// It is `MCPTools::optional_dictionary` (`tools/tool_helpers.*`): the repair
// pass hoisted this copy and the byte-identical one in editor_node_setup.cpp.

// The group's `path` / `node_path` / `source_path` / `target_path` arguments are
// all the same kind of string: a non-empty node path. One helper keeps the
// wording of the refusal identical everywhere (the migration source read them
// with `unwrap_or("")` and then resolved "" to the scene root, which is how a
// misspelt argument silently addressed the root).
static bool _require_node_path(const Dictionary &p_args, const String &p_key, String &r_out, MCPToolError &r_error) {
	if (!require_string(p_args, p_key, r_out, r_error)) {
		return false;
	}
	if (r_out.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must not be empty", p_key));
		return false;
	}
	return true;
}

// An optional path argument. Absent means "the caller did not name one" and is
// reported through `r_present`; present-but-wrong-type is `-32602` (PLAYBOOK
// section 6.2), never silently treated as absent - which is what the migration
// source did with `and_then(as_str)`.
static bool _optional_node_path(const Dictionary &p_args, const String &p_key, bool &r_present, String &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	r_present = value.get_type() != Variant::NIL;
	if (!r_present) {
		return true;
	}
	if (value.get_type() != Variant::STRING && value.get_type() != Variant::STRING_NAME) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be a string, got %s",
				p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	r_out = String(value);
	if (r_out.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must not be empty", p_key));
		return false;
	}
	return true;
}

// The three argument shapes every signal tool of this group shares.
struct SignalRequest {
	Node *source = nullptr;
	Node *target = nullptr;
	StringName signal;
	String method;
	String source_path;
	String target_path;
};

// ---------------------------------------------------------------------------
// MCPTools:: the testable entry points.
//
// The doctest binary has no `SceneTree` at all (`SceneTree::get_singleton()` is
// nullptr), so a tool-level case can only ever observe the -32000 guards. These
// five entry points take the nodes, which is what lets the group's cases pin the
// real behaviour - including both fix-first defects - against bare `Node`
// objects. Their behaviour is documented in tools/editor_node_write.h and at
// each definition below.
// ---------------------------------------------------------------------------
namespace MCPTools {

Node *instantiate_node_of_type(const String &p_type, const String &p_name, MCPToolError &r_error) {
	// The class-level rule (does the class exist, is it instantiable) lives in
	// `MCPTools::instantiate_class` (tools/tool_helpers.*): TASK-017 section 4
	// hoisted it there because the new B3 groups instantiate classes that are not
	// nodes (`Shape2D`, `Environment`, `NavigationMesh`) and because a batch
	// element may need to keep its name unset. This function is now only the node
	// half: the subclass test, the cast and the name.
	//
	// The migration source's checks (node.rs:177-184) still run in the same
	// order: a class that does not exist is refused by `instantiate_class` with
	// "no such class", a class that exists but is not a `Node` subclass is
	// refused here before anything is constructed, and an abstract class is
	// refused by `instantiate_class`.
	const StringName type_name(p_type);
	if (ClassDB::class_exists(type_name) && !ClassDB::is_parent_class(type_name, StringName("Node"))) {
		r_error = MCPToolError::invalid_params(vformat("Type '%s' is not a Node subclass", p_type));
		return nullptr;
	}
	Object *created = instantiate_class(p_type, r_error);
	if (created == nullptr) {
		return nullptr;
	}
	Node *node = Object::cast_to<Node>(created);
	if (node == nullptr) {
		// Unreachable after the `is_parent_class` check; kept because it is the
		// migration source's own `try_to::<Node>().map_err(...)` branch and
		// because a cascade to `memdelete` has to be impossible to reach by
		// accident.
		memdelete(created);
		r_error = MCPToolError::invalid_params(vformat("Type '%s' is not a Node subclass", p_type));
		return nullptr;
	}
	// `Node::set_name()` *sanitises* rather than fails (String::validate_node_name,
	// scene/main/node.cpp:1450); the name the engine applied is what the caller is
	// answered with further up.
	node->set_name(p_name);
	return node;
}

bool apply_node_properties(Node *p_node, const Dictionary &p_properties, MCPToolError &r_error) {
	// The `properties` map of `editor_add_node` goes through the *same* property
	// write as `editor_set_node_property`, so the whole node-write family has one
	// rule: ask the object whether it has the property before writing anything,
	// coerce the JSON value to the declared type, and report what the object
	// answers back. The migration source applied `parse_value_for_property()`
	// straight (node.rs:188-192), so a misspelt key was a silent no-op inside an
	// otherwise successful `add_node`.
	//
	// Iteration order: a `Dictionary` preserves insertion order in this engine,
	// so the caller's own key order is kept and a failure always names the first
	// offending key deterministically.
	const Array keys = p_properties.keys();
	for (int i = 0; i < keys.size(); i++) {
		const String key = keys[i];
		const Variant written = write_node_property(p_node, key, p_properties[key], r_error);
		if (written.get_type() == Variant::NIL) {
			return false;
bool connect_signal_on(Node *p_source, const StringName &p_signal, Object *p_target, const String &p_method, bool &r_already_connected, bool &r_persisted, MCPToolError &r_error) {
	r_already_connected = false;
	r_persisted = false;
	if (p_target == nullptr) {
		// Unreachable through the tools below (the target is always resolved to a
		// real node first); kept so the helper is total.
		r_error = MCPToolError::not_found("Target object for the connection", "Name a node that exists in the edited scene with 'target_path'");
		return false;
	}
	if (!p_source->has_signal(p_signal)) {
		// The migration source called `connect()` and ignored its `Error`, so a
		// signal the node does not have was answered with `{"connected": true}`.
		r_error = MCPToolError::not_found(vformat("Signal '%s' on node '%s'", p_signal, p_source->get_name()),
				"Use editor_get_node_signals to list the signals this node has");
		return false;
	}
	const Callable callable(p_target, p_method);
	if (p_source->is_connected(p_signal, callable)) {
		// The requested end state already holds. It is a success - but the caller
		// is told that this call is not what established it.
		r_already_connected = true;
		if (_connection_is_persistent(p_source, p_signal, callable)) {
			r_persisted = true;
			return true;
		}
		// TASK-040 D-2: the connection exists but is not persistent, so the next
		// `editor_save_scene` would drop it while this answer said `connected`.
		// Adding the bit to an *existing* connection is not something the engine
		// offers (`Object::connect` refuses a second connect with different flags),
		// so the connection is remade with `CONNECT_PERSIST`: the same callable,
		// the same signal, one flag changed. `already_connected` stays true - the
		// end state did hold before this call - and the caller learns through
		// `persisted` what the connection now is.
		p_source->disconnect(p_signal, callable);
	}
	if (p_source->connect(p_signal, callable, Object::CONNECT_PERSIST) != OK) {
		r_error = MCPToolError::tool_state(vformat("Cannot connect signal '%s' of node '%s' to method '%s' to a persistent connection",
												 p_signal, p_source->get_name(), p_method),
				"Check that the target node exposes the method and that no conflicting connection exists");
		return false;
	}
	// Honest reporting: the answer's `persisted` is the flag the live connection
	// really carries, not the flag this call asked for.
	r_persisted = _connection_is_persistent(p_source, p_signal, callable);
	return true;
}

bool disconnect_signal_from(Node *p_source, const StringName &p_signal, Object *p_target, const String &p_method, bool &r_was_persistent, MCPToolError &r_error) {
	r_was_persistent = false;
	// -----------------------------------------------------------------------
//     edited scene root and `name` / `type` read back from the created node (the
//     migration source echoed the request, which hides a sanitised name).
// ---------------------------------------------------------------------------
static Variant _tool_add_node(const Dictionary &p_args, MCPToolError &r_error) {
	String type;
	if (!require_string(p_args, "type", type, r_error)) {
		return Variant();
	}
	if (type.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'type' must not be empty");
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", type, name, r_error)) {
		return Variant();
	}
	String parent_path;
	if (!optional_string(p_args, "parent_path", ".", parent_path, r_error)) {
		return Variant();
	}
	if (parent_path.strip_edges().is_empty()) {
		parent_path = ".";
	}
	Dictionary properties;
	if (!_optional_dictionary(p_args, "properties", properties, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor node writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = _edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Node *parent = _find_node(root, parent_path);
	if (parent == nullptr) {
		r_error = MCPToolError::not_found(vformat("Parent '%s'", parent_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}
	Node *node = instantiate_node_of_type(type, name, r_error);
	if (node == nullptr) {
		return Variant();
	}
	if (!apply_node_properties(node, properties, r_error)) {
		// The node was never added to the tree, so destroying it here is what
		// keeps a refused call free of side effects.
		memdelete(node);
		return Variant();
	}
	parent->add_child(node);
	// `owner` is what makes the new node part of the saved scene rather than a
	// runtime child; it has to be set *after* `add_child` because it is the
	// ancestor relationship that makes the root a legal owner.
	node->set_owner(root);

	Dictionary result;
	result["node_path"] = _relative_path(root, node);
	result["name"] = String(node->get_name());
	result["type"] = node->get_class();
	return result;
}

// ---------------------------------------------------------------------------
// editor_delete_node (old `delete_node`, node.rs:202)
//
// `queue_free()` is what the migration source called, and it is a *deferred*
// free: the node is gone at the end of the frame, not when the tool returns. The
// answer therefore reports what the engine really accepted
// (`deleted` = `is_queued_for_deletion()` measured after the call) together with
// `deferred: true`, instead of the migration source's unconditional
// `{"deleted": true}`.
//
// The edited scene root itself is refused with `-32000`: `queue_free()` on it
// would tear the open scene out from under the editor, and "close the scene" is
// not what this tool is for. That is a deliberate divergence from the migration
// source (which would happily queue the root) and is recorded in the report.
// ---------------------------------------------------------------------------
static Variant _tool_delete_node(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!_require_node_path(p_args, "path", path, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor node writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = _edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Node *node = _find_node(root, path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}
	if (node == root) {
		r_error = MCPToolError::tool_state("The edited scene root cannot be deleted",
				"Open another scene (editor_open_scene) to replace this one instead of deleting its root");
		return Variant();
	}
	const String resolved = _relative_path(root, node);
	node->queue_free();

	Dictionary result;
	result["deleted"] = node->is_queued_for_deletion();
	result["path"] = resolved;
	result["deferred"] = true;
	return result;
}

// ---------------------------------------------------------------------------
// editor_duplicate_node (old `duplicate_node`, node.rs:269)
//
// `new_name` is optional and keeps the migration source's default: the *path*
// string the caller passed (node.rs:273). That is a quirk rather than a
// sensible default, and it is preserved because PLAYBOOK section 6.8 says a
// quirk is kept unless it makes the tool unusable - here the engine sanitises
// the invalid characters and the answer names what actually happened, so the
// caller is never misled.
//
// The duplicate is answered with its real path and real name, and the `owner` is
// set so it is part of the saved scene. `duplicate()` copies signals and groups
// (`Node::DUPLICATE_GROUPS | DUPLICATE_SIGNALS | DUPLICATE_SCRIPTS`), which is
// the migration source's behaviour as well.
// ---------------------------------------------------------------------------
// is coerced to the property's declared type, and the answer carries the value
// read *back* from the object after the write - `{"node_path", "property",
// "old_value", "new_value"}` - so a setter that refused or clamped the value is
// visible instead of being reported as `{"updated": true}`. The migration source
// answered exactly that constant `updated: true` after a silent `set()`.
// ---------------------------------------------------------------------------
static Variant _tool_set_node_property(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!_require_node_path(p_args, "path", path, r_error)) {
		return Variant();
	}
	String property;
	if (!require_string(p_args, "property", property, r_error)) {
		return Variant();
	}
	if (property.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'property' must not be empty");
		return Variant();
	}
	// `value` has no `type` in the contract (it accepts every JSON type), so it
	// cannot go through `require_*`: presence, not nullness, is what "required"
	// means here.
	if (!p_args.has("value")) {
		r_error = MCPToolError::invalid_params("Missing required parameter 'value'");
		return Variant();
	}
	const Variant raw_value = p_args["value"];
	if (!require_editor_ui(r_error, "editor node writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = MCPTools::edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Node *node = MCPTools::find_node(root, path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}
	return set_node_property_on(root, node, property, raw_value, r_error);
}

// ---------------------------------------------------------------------------
// editor_set_node_groups (old `set_node_groups`, node.rs:501)
//
// `groups` is the *desired* set of (non-internal) groups; the tool adds what is
// missing and removes what is no longer wanted. Rules kept from the migration
// source: names starting with `_` are internal and invisible in both directions.
//
// Rules changed, each because the migration source's version is not usable as
// evidence:
//   * a `groups` element that is not a string is `-32602` (the migration source
//     dropped it silently with `filter_map(as_str)`, so `["a", 7]` reported
//     four keys and configured two groups);
//   * `added` / `removed` are answered in a *deterministic* order. `added`
//     follows the caller's own order (de-duplicated); `removed` is sorted
//     ascending, because it comes from `Node::get_groups()`, whose order is a
//     `HashSet` iteration order and is not part of the engine's contract
//     (PLAYBOOK section 6.8);
//   * `groups` echoes the parsed desired list (the migration source's own
//     value), so the caller's request is not confused with the result;
//     `added` / `removed` are the measured delta.
// ---------------------------------------------------------------------------
static Variant _tool_set_node_groups(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_node_path(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	const Variant groups_value = p_args.get("groups", Variant());
	if (groups_value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter 'groups'");
		return Variant();
	}
	if (groups_value.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'groups' must be an array, got %s",
				Variant::get_type_name(groups_value.get_type())));
		return Variant();
	}
	const Array requested = groups_value;
	Vector<String> desired;
	for (int i = 0; i < requested.size(); i++) {
		if (requested[i].get_type() != Variant::STRING && requested[i].get_type() != Variant::STRING_NAME) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'groups[%d]' must be a string, got %s",
					i, Variant::get_type_name(requested[i].get_type())));
			return Variant();
		}
		desired.push_back(String(requested[i]));
	}
	if (!require_editor_ui(r_error, "editor node writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = MCPTools::edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Node *node = MCPTools::find_node(root, node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", node_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}

	Vector<String> current;
	List<Node::GroupInfo> existing;
	node->get_groups(&existing);
	for (const Node::GroupInfo &group : existing) {
		const String name = String(group.name);
		if (!name.begins_with("_")) {
			current.push_back(name);
		}
	}

	Vector<String> removed;
	for (const String &name : current) {
		if (!desired.has(name)) {
			removed.push_back(name);
		}
	}
	removed.sort();

	Vector<String> added;
	for (const String &name : desired) {
		if (current.has(name) || added.has(name)) {
			continue;
		}
// editor_connect_signal (old `connect_signal`, node.rs:319)
//
// `source_path` / `signal` / `method` are required, `target_path` is optional and
// means the edited scene root when it is absent (the migration source's rule).
// Both nodes are resolved before anything is connected, so a misspelt target is
// `-32001` and never a connection to the root.
//
// The migration source ignored the `Error` `connect()` returned, which is how a
// nonexistent signal - or an already existing identical connection, which
// `Object::connect` refuses with `ERR_INVALID_PARAMETER` - was answered with
// `{"connected": true}`. Here: a signal the source does not have is `-32001`, a
// refused `connect()` is `-32000`, and an already present identical connection is
// a success that says so (`already_connected: true`), because the requested end
// state does hold.
//
// The answer names both nodes by their path relative to the edited scene root;
// the migration source echoed the raw arguments and omitted `target` entirely
// when it defaulted to the root.
// ---------------------------------------------------------------------------
static Variant _tool_connect_signal(const Dictionary &p_args, MCPToolError &r_error) {
	SignalRequest request;
	if (!_require_node_path(p_args, "source_path", request.source_path, r_error)) {
		return Variant();
	}
	String signal;
	if (!require_string(p_args, "signal", signal, r_error)) {
		return Variant();
	}
	if (signal.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'signal' must not be empty");
		return Variant();
	}
	if (!require_string(p_args, "method", request.method, r_error)) {
		return Variant();
	}
	if (request.method.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'method' must not be empty");
		return Variant();
	}
	bool has_target = false;
	if (!_optional_node_path(p_args, "target_path", has_target, request.target_path, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor node writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = MCPTools::edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	request.source = MCPTools::find_node(root, request.source_path);
	if (request.source == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", request.source_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}
	if (has_target) {
		request.target = MCPTools::find_node(root, request.target_path);
		if (request.target == nullptr) {
			r_error = MCPToolError::not_found(vformat("Node '%s'", request.target_path),
					"Use editor_get_scene_tree to list the nodes of the edited scene");
			return Variant();
		}
	} else {
		request.target = root;
	}
	request.signal = StringName(signal);

	bool already = false;
	bool persisted = false;
	if (!connect_signal_on(request.source, request.signal, request.target, request.method, already, persisted, r_error)) {
		return Variant();
	}

	Dictionary result;
	result["connected"] = true;
	result["signal"] = signal;
	result["source"] = relative_path(root, request.source);
	result["target"] = relative_path(root, request.target);
	// TASK-040 D-2: the honest half of `connected`. `PackedScene` only keeps a
	// connection that carries `CONNECT_PERSIST`, so "will this survive
	// editor_save_scene?" is a separate question from "is it connected?", and the
	// answer must state it (the racing test's `[connection]` count was 0 after
	// this tool answered `connected: true`). `editor_add_input_action` already
	// answers `persisted: false` for the same reason.
	result["persisted"] = persisted;
	if (already) {
		result["already_connected"] = true;
	}
	return result;
}

// ---------------------------------------------------------------------------
// editor_disconnect_signal (old `disconnect_signal`, node.rs:344) - fix first.
//
// **The defect.** The migration source takes `target_path` in its schema
// (`required: ["source_path", "signal", "method"]`, `target_path` optional) and
// then never reads it: it builds the `Callable` from the *scene root*
// unconditionally (node.rs:355) and ignores the result of `disconnect()`
// (node.rs:356). So the call either disconnects a completely different
// connection - whatever the root happens to expose under `method` - or nothing
// at all, and answers `{"disconnected": true}` either way. A caller that used
// `target_path` to name the connection it wanted broken could therefore get a
// *different* connection removed, with no way to notice.
//
// **The fix.** `target_path` is an input: the target node is resolved exactly
// like the source (defaulting to the edited scene root when it is absent, which
// keeps the reference's one documented default), the `Callable` is built from
// that node, and the connection is looked up *before* anything is touched. A
// connection that is not there - wrong target, wrong method, wrong signal, or a
// signal the source does not have - is `-32001` with a suggestion, and only an
// existing connection is disconnected. The answer names the connection that was
// really removed.
//
// The red test that pins this before the fix is
// `[MCPServer] editor_disconnect_signal disconnects the named connection, not the scene root` in
// tests/test_mcp_server.h; see REPORT-015 section 3 for its before/after output.
// ---------------------------------------------------------------------------
}

// ---------------------------------------------------------------------------
// editor_set_auto_dismiss_dialogs (old `set_auto_dismiss`, editor.rs:613) -
// fix first, second half.
//
// **The defect.** The migration source stores the flag in one
// `static AtomicBool` (editor.rs:31). Nothing in the addon - and nothing in the
// engine - ever reads it: `grep -rn auto_dismiss` over the addon finds exactly
// the declaration, the store and the tool description, and the engine's own
// dialogs are configured per dialog (`set_hide_on_ok`, 29 call sites under
// `editor/`, all hard coded). The tool therefore answered
// `{"auto_dismiss": <enabled>, "message": "..."}` while the editor's behaviour
// did not change at all: pure fake success, the shape PLAYBOOK section 6.6 and
// TASK-015 section 2 forbid.
//
// **The fix.** There is no process-wide "auto dismiss dialogs" behaviour in this
// engine to switch, so the honest answer is `-32000 Not implemented` with a
// `data.suggestion` that names the real knobs (per-dialog `hide_on_ok`, and the
// editor's `interface/editor/appearance/accept_dialog_cancel_ok_buttons`
// ordering setting). The alternative - inventing a static and reading it back -
// is exactly the lie being removed. The argument contract is still validated
// first, so a malformed call is `-32602` rather than a misleading
// "not implemented".
//
// The red test is
// `[MCPServer] editor_set_auto_dismiss_dialogs never reports a success it did not perform`
// in tests/test_mcp_server.h; see REPORT-015 section 3.
// ---------------------------------------------------------------------------
static Variant _tool_set_auto_dismiss_dialogs(const Dictionary &p_args, MCPToolError &r_error) {
	const Variant enabled = p_args.get("enabled", Variant());
	if (enabled.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter 'enabled'");
		return Variant();
	}
	if (enabled.get_type() != Variant::BOOL) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'enabled' must be a boolean, got %s",
				Variant::get_type_name(enabled.get_type())));
		return Variant();
	}
	// -----------------------------------------------------------------------
	// GREEN - the fix. There is no process-wide dialogs knob to switch, so the
	// honest answer is a -32000 with a suggestion instead of the success shape
	// the red version (and the migration source) produced. The requested value
	// is deliberately *not* echoed back: the call changed nothing, and an answer
	// carrying `auto_dismiss: true` next to a failure is exactly how the fake
	// success started.
	// -----------------------------------------------------------------------
	r_error = MCPToolError::not_implemented("editor_set_auto_dismiss_dialogs",
			"This engine has no process-wide auto-dismiss setting for editor dialogs; the behaviour is "
			"configured per dialog (AcceptDialog.hide_on_ok) and the only editor-wide dialog setting is "
			"interface/editor/appearance/accept_dialog_cancel_ok_buttons, which orders the buttons rather "
			"than dismissing the dialog. Use the per-dialog behaviour from a script "
			"(editor_execute_gdscript), or an editor tool that acts on a named dialog.");
	return Variant();
		builder.channel("editor").verb("reparent").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"new_name":{"description":"移动后的新名称 (可选)","type":"string"},"new_parent":{"description":"目标父节点路径","type":"string"},"path":{"description":"要移动的节点路径","type":"string"}},"required":["path","new_parent"],"type":"object"})schema"));
		builder.handler(_tool_reparent_node).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_node_property", String::utf8(R"desc(修改属性)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"path":{"type":"string"},"property":{"type":"string"},"value":{}},"required":["path","property","value"],"type":"object"})schema"));
		builder.handler(_tool_set_node_property).register_into(r_registry);
	}
