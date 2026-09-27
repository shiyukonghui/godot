/**************************************************************************/
/*  editor_node_read.cpp                                                  */
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
#include "editor_node_read.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/io/json.h"
#include "core/object/object.h"
#include "core/string/node_path.h"
#include "core/string/string_name.h"
#include "core/variant/callable.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"

using namespace MCPTools;

// The runtime half of the editor guard lives in `tools/tool_helpers.*` and is
// called below as `require_editor_ui(r_error, <non-editor wording>,
// <suggestion>)`; the `EditorInterface` / `EditorNode` null-check reasoning is
// documented next to that single definition. The edited scene root
// (`MCPTools::edited_scene_root()`) and the migration source's node resolution
// (`MCPTools::find_node()`) were hoisted there by TASK-016 section 1, so this
// group file keeps no copy of either.
//
// Nothing in this file needs an editor-only engine header: the six tools read
// `Node` / `SceneTree` only. The editor/package split is still enforced twice -
// `ToolBuilder` does not even register a `scope = EDITOR` tool in a game process
// (GDR-19 section 17.3), and `require_editor_ui` refuses every call in one.

// ---------------------------------------------------------------------------
// The six argument shapes.
// ---------------------------------------------------------------------------

// A required, non-empty node path. One helper keeps the wording of the refusal
// identical across the three tools that take one (the migration source read them
// with `and_then(as_str)` and then resolved "" to the scene root, which is how a
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

// `properties` (editor_get_node_properties): an optional array of *strings*.
//
// The migration source's `args.get("properties").and_then(|v| v.as_array()).map(
// |arr| arr.iter().filter_map(|v| v.as_str().map(String::from)).collect())`
// (node.rs:241-243) turned a non-array into "no filter at all" and dropped
// non-string elements one by one: `properties: "position"` and
// `properties: ["position", 7]` both silently listed every readable property.
// PLAYBOOK section 6.2 settled that shape for the whole port: present but wrong
// type is `-32602`, never a silently ignored argument.
static bool _optional_string_array(const Dictionary &p_args, const String &p_key, bool &r_present,
		Vector<String> &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	r_present = value.get_type() != Variant::NIL;
	if (!r_present) {
		return true;
	}
	if (value.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be an array of strings, got %s",
				p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	const Array list = value;
	for (int i = 0; i < list.size(); i++) {
		if (list[i].get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter '%s[%d]' must be a string, got %s",
					p_key, i, Variant::get_type_name(list[i].get_type())));
			return false;
		}
		r_out.push_back((String)list[i]);
	}
	return true;
}

// The `target` of a connection, spelled the way the migration source spells it
// (`root.get_path_to(conn_obj)`, editor.rs:481 / batch.rs:244): a path relative
// to the edited scene root, `""` when the `Callable` carries no object, and
// `""` for an object that is not a `Node` (a GDScript `get_path_to()` on
// anything else answers null, which stringifies to "").
//
// `Node::get_path_to()` returns an empty `NodePath` *and logs an engine ERR* for
// two nodes that share no common ancestor (scene/main/node.cpp:2398) - which is
// what an object outside the edited scene is. That ERR is kept: the migration
// source took the same path and answered the same empty string, and "this
// connection's target is not in the edited scene" is a fact worth seeing rather
// than hiding. Nothing is filtered here; only the null cases - which the
// migration source's `if conn_obj else ""` also answers `""` - are explicit.
static String _connection_target(Node *p_root, const Callable &p_callable) {
	Object *object = p_callable.get_object();
	if (object == nullptr) {
		return String();
	}
	Node *target = Object::cast_to<Node>(object);
	if (target == nullptr) {
		return String();
	}
	return String(p_root->get_path_to(target));
}

// ---------------------------------------------------------------------------
// MCPTools:: the testable entry points.
//
// The doctest binary has no `SceneTree` at all (`SceneTree::get_singleton()` is
// nullptr), so a tool-level case can only ever observe the -32000 guards. These
// five entry points take the nodes, which is what lets the group's cases pin the
// real behaviour - including the property-filter correction this group exists
// for - against bare `Node` objects. Their behaviour is documented in
// tools/editor_node_read.h and at each definition below.
// ---------------------------------------------------------------------------
namespace MCPTools {

Dictionary node_entry(Node *p_root, Node *p_node) {
	Dictionary entry;
	entry["name"] = String(p_node->get_name());
	// `get_path_to()` answers "." for the node itself (scene/main/node.cpp:2376),
	// which is exactly the root spelling the migration source and this module use
	// everywhere else.
	entry["path"] = String(p_root->get_path_to(p_node));
	entry["type"] = p_node->get_class();
	return entry;
}

void collect_nodes(Node *p_root, Node *p_node, const String &p_type_name,
		const String &p_group, Array &r_out) {
	bool matches = false;
	if (!p_type_name.is_empty()) {
		// Both halves of the migration source's test are kept (batch.rs:111):
		// `get_class()` is the exact class, `is_class()` also matches a subclass,
		// and a caller that asks for "Control" wants its buttons too.
		matches = p_node->get_class() == p_type_name || p_node->is_class(p_type_name);
	} else if (!p_group.is_empty()) {
		matches = p_node->is_in_group(StringName(p_group));
	}
	if (matches) {
		r_out.push_back(node_entry(p_root, p_node));
	}
	// Pre-order, children in tree order: deterministic, and the same order the
	// migration source's recursion produces.
	const int child_count = p_node->get_child_count();
	for (int i = 0; i < child_count; i++) {
		Node *child = p_node->get_child(i);
		if (child != nullptr) {
			collect_nodes(p_root, child, p_type_name, p_group, r_out);
		}
	}
}

bool node_properties(Node *p_node, const Vector<String> *p_filter,
		Dictionary &r_out, MCPToolError &r_error) {
	r_out = Dictionary();
	// `Object::get_property_list()` fills a `List<PropertyInfo>` - the same list
	// the GDScript binding serialises into the `get_property_list()` array.
	List<PropertyInfo> property_list;
	p_node->get_property_list(&property_list);
	// TASK-032 D3 (M4d): the table also carries the inspector's own *labels* -
	// `ADD_GROUP` / `ADD_SUBGROUP` / `ADD_CATEGORY` entries, which are not
	// properties at all. They are kept by name here for one reason: a caller that
	// asks for one of them *by name* must be told what it actually named instead
	// of getting the generic "not a property of this node" (see the refusal loop
	// below). Everything else skips them outright, so they can never be answered
	// as a fake `null` property.
	Vector<String> label_names;
	for (const PropertyInfo &property : property_list) {
		const String name = String(property.name);
		// The visibility quirk of the migration source (node.rs:256), kept on
		// purpose (PLAYBOOK section 6.8): a *listing* does not enumerate internal
		// properties or the attached script. The write side of the module is not
		// affected - `editor_set_node_property` may still write `script`.
		if (name.begins_with("_") || name == "script") {
			continue;
		}
		if (property_is_label(property)) {
			// The defect this fixes: `Node2D` answers 12 of these, each with
			// `Variant::NIL` (`Node`, `Node2D`, `CanvasItem`, `Transform`,
			// `Visibility`, `Ordering`, `Texture`, `Material`, `Process`,
			// `Thread Group`, `Auto Translate`, `Editor Description`,
			// `Physics Interpolation`), and `Material` collides with the real
			// property `material` under a case-insensitive comparison.
			label_names.push_back(name);
			continue;
		}
		if (p_filter != nullptr && !p_filter->has(name)) {
			continue;
		}
		// The output-key rule: the engine's own spelling, and no second key that
		// only differs from an existing one by case (a case-insensitive client
		// cannot parse such a package at all). After the label filter above, the
		// only way to reach this is two genuine properties whose names differ
		// only by case; the first in the engine's table order wins.
		if (dictionary_has_key_ignoring_case(r_out, name)) {
			continue;
		}
		r_out[name] = serialize_variant(p_node->get(property.name));
	}

	if (p_filter == nullptr) {
		return true;
	}
	// Every name the caller asked for is either in the answer or a refusal. The
	// migration source produced `properties: {}` here, which reads as "this node
	// has none of the properties you asked for" - the failure mode PLAYBOOK
	// section 6.6 bans (REPORT-016 section 2 is the eighth instance of it, and
	// REPORT-016 section 4 quotes the red run this loop turned green).
	for (int i = 0; i < p_filter->size(); i++) {
		const String &wanted = (*p_filter)[i];
		if (r_out.has(wanted)) {
			continue;
		}
		if (label_names.has(wanted)) {
			r_error = MCPToolError::not_found(
					vformat("Property '%s' on node '%s' is an inspector group/category label, not a property", wanted, p_node->get_name()),
					"Inspector group and category labels (PROPERTY_USAGE_GROUP / SUBGROUP / CATEGORY) carry no value and are never listed. "
					"Call editor_get_node_properties without 'properties' to list the readable properties of this node");
		} else if (wanted.begins_with("_") || wanted == "script") {
			r_error = MCPToolError::not_found(
					vformat("Property '%s' on node '%s' is not readable by name", wanted, p_node->get_name()),
					"editor_get_node_properties never answers with an empty map for a property it was asked for by name. "
					"Names starting with '_' and the 'script' property are kept out of the property listing "
					"(the migration source's rule); ask for the properties you need by their public names instead");
		} else {
			r_error = MCPToolError::not_found(
					vformat("Property '%s' on node '%s'", wanted, p_node->get_name()),
					"Call editor_get_node_properties without 'properties' to list every readable property of this node");
		}
		return false;
	}
	return true;
}

Array signal_entries(Node *p_root, Node *p_node) {
	Array out;
	// `Object::get_signal_list()` fills a `List<MethodInfo>` - the same list the
	// GDScript binding serialises into an Array: script signals, ClassDB signals
	// and user signals, in that order (the migration source's
	// `node.get_signal_list()` iterates the same one).
	List<MethodInfo> signal_list;
	p_node->get_signal_list(&signal_list);
	for (const MethodInfo &signal : signal_list) {
		const StringName signal_name = signal.name;

		Dictionary entry;
		entry["name"] = String(signal_name);

		Array args;
		for (const PropertyInfo &argument : signal.arguments) {
			Dictionary arg;
			arg["name"] = String(argument.name);
			// The migration source stringifies the `Variant::Type` enum value
			// (`str(arg["type"])`, editor.rs:478), so it answers "1" where this
			// answers "int". The contract does not prescribe the spelling; the
			// name is the readable half of the same fact (REPORT-016 section 2).
			arg["type"] = Variant::get_type_name(argument.type);
			args.push_back(arg);
		}
		entry["args"] = args;

		Array connections;
		List<Object::Connection> signal_connections;
		p_node->get_signal_connection_list(signal_name, &signal_connections);
		for (const Object::Connection &connection : signal_connections) {
			Dictionary entry_connection;
			entry_connection["target"] = _connection_target(p_root, connection.callable);
			entry_connection["method"] = String(connection.callable.get_method());
			connections.push_back(entry_connection);
		}
		entry["connections"] = connections;

		out.push_back(entry);
	}
	return out;
}

void collect_signal_connections(Node *p_node, Node *p_root,
		const String &p_node_filter, const String &p_signal_filter, Array &r_out) {
	// The migration source compares against `root.get_path_to(node).to_string()`
	// (batch.rs:235), i.e. the root-relative spelling, and both filters are
	// substring tests (`find() >= 0`).
	const String node_path = String(p_root->get_path_to(p_node));
	if (p_node_filter.is_empty() || node_path.find(p_node_filter) >= 0) {
		List<MethodInfo> signal_list;
		p_node->get_signal_list(&signal_list);
		for (const MethodInfo &signal : signal_list) {
			const StringName signal_name = signal.name;
			const String signal_text = String(signal_name);
			if (!p_signal_filter.is_empty() && signal_text.find(p_signal_filter) < 0) {
				continue;
			}
			// `get_signal_connection_list()` answers **every** connection of the
			// signal. It is deliberately not filtered by `CONNECT_PERSIST`: that
			// filter is what `editor_analyze_signal_flow` does, and it is the
			// discriminator GDR-17 kept this tool for.
			List<Object::Connection> signal_connections;
			p_node->get_signal_connection_list(signal_name, &signal_connections);
			for (const Object::Connection &connection : signal_connections) {
				Dictionary entry;
				entry["source"] = node_path;
				entry["signal"] = signal_text;
				entry["target"] = _connection_target(p_root, connection.callable);
				entry["method"] = String(connection.callable.get_method());
				r_out.push_back(entry);
			}
		}
	}
	const int child_count = p_node->get_child_count();
	for (int i = 0; i < child_count; i++) {
		Node *child = p_node->get_child(i);
		if (child != nullptr) {
			collect_signal_connections(child, p_root, p_node_filter, p_signal_filter, r_out);
		}
	}
}

// ---------------------------------------------------------------------------
// TASK-051 O-9: the `scope` narrowing (declared, with its rationale, in
// tools/editor_node_read.h).
//
// One predicate, used by both the filter and the counter, so the `counts` the
// tool reports can never disagree with the `connections` it returns.
// ---------------------------------------------------------------------------
bool signal_connection_method_is_internal(const String &p_method) {
	// `Class::method`: the spelling the engine itself uses for a MethodBind-
	// backed `Callable` (`Callable::get_method()`), and a spelling a
	// GDScript/C# method name cannot contain.
	return p_method.contains("::");
}

bool parse_signal_connection_scope(const String &p_text, SignalConnectionScope &r_scope) {
	if (p_text == "all") {
		r_scope = SignalConnectionScope::ALL;
		return true;
	}
	if (p_text == "user") {
		r_scope = SignalConnectionScope::USER;
		return true;
	}
	if (p_text == "internal") {
		r_scope = SignalConnectionScope::INTERNAL;
		return true;
	}
	return false;
}

const char *signal_connection_scope_name(SignalConnectionScope p_scope) {
	switch (p_scope) {
		case SignalConnectionScope::USER:
			return "user";
		case SignalConnectionScope::INTERNAL:
			return "internal";
		case SignalConnectionScope::ALL:
			break;
	}
	return "all";
}

Array filter_signal_connections_by_scope(const Array &p_all, SignalConnectionScope p_scope) {
	if (p_scope == SignalConnectionScope::ALL) {
		// The default answer is the collector's array itself: nothing is copied
		// and nothing can be lost in a round trip.
		return p_all;
	}
	const bool want_internal = p_scope == SignalConnectionScope::INTERNAL;
	Array out;
	for (int i = 0; i < p_all.size(); i++) {
		const Variant entry = p_all[i];
		if (entry.get_type() != Variant::DICTIONARY) {
			continue;
		}
		const String method = ((Dictionary)entry).get("method", Variant());
		if (signal_connection_method_is_internal(method) == want_internal) {
			out.push_back(entry);
		}
	}
	return out;
}

Dictionary count_signal_connections_by_scope(const Array &p_all) {
	int all = 0;
	int user = 0;
	int internal = 0;
	for (int i = 0; i < p_all.size(); i++) {
		const Variant entry = p_all[i];
		if (entry.get_type() != Variant::DICTIONARY) {
			continue;
		}
		all++;
		const String method = ((Dictionary)entry).get("method", Variant());
		if (signal_connection_method_is_internal(method)) {
			internal++;
		} else {
			user++;
		}
	}
	Dictionary counts;
	counts["all"] = all;
	counts["user"] = user;
	counts["internal"] = internal;
	return counts;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The six tools.
//
// Every one of them answers with root-relative node paths (the spelling
// `MCPTools::find_node` accepts and every other editor tool of this module
// produces), which is what lets a caller feed one tool's answer straight into
// the next one - the read-back chain of REPORT-016 section 5 does exactly that
// (PLAYBOOK section 6.7).
//
// Empty results are successes, not errors: a group nobody is in, a type that is
// not instantiated in the scene, a subtree with no connections. The migration
// source agrees, and a caller that got `-32001` for "there is nothing there"
// would have no way to tell it apart from "the node you named is not there".
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// editor_get_node_properties (old `get_node_properties`, node.rs:232)
// ---------------------------------------------------------------------------
static Variant _tool_get_node_properties(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!_require_node_path(p_args, "path", path, r_error)) {
		return Variant();
	}
	bool has_filter = false;
	Vector<String> filter;
	if (!_optional_string_array(p_args, "properties", has_filter, filter, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor inspectors outside a running editor",
				"Start the MCP server inside the Godot editor to inspect the editor scene")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Node *node = find_node(root, path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}
	Dictionary properties;
	if (!node_properties(node, has_filter ? &filter : nullptr, properties, r_error)) {
		return Variant();
	}

	Dictionary result;
	result["node_path"] = String(root->get_path_to(node));
	result["type"] = node->get_class();
	result["properties"] = properties;
	return result;
}

// ---------------------------------------------------------------------------
// editor_get_node_groups (old `get_node_groups`, node.rs:471)
//
// The internal-group filter (`!group.starts_with('_')`, node.rs:486) is kept:
// Godot's own editor marks its bookkeeping groups that way, and the write side
// of this batch (`editor_set_node_groups`) uses exactly the same rule, so the
// two halves of the read/write pair agree about what is visible.
// ---------------------------------------------------------------------------
static Variant _tool_get_node_groups(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_node_path(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor inspectors outside a running editor",
				"Start the MCP server inside the Godot editor to inspect the editor scene")) {
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

	Array groups;
	// `Node::get_groups()` fills a `List<GroupInfo>`; the GDScript binding
	// `get_groups()` serialises the same list into an Array.
	List<Node::GroupInfo> current;
	node->get_groups(&current);
	for (const Node::GroupInfo &info : current) {
		const String group = String(info.name);
		if (group.begins_with("_")) {
			continue;
		}
		groups.push_back(group);
	}

	Dictionary result;
	result["node_path"] = String(root->get_path_to(node));
	result["groups"] = groups;
	result["count"] = groups.size();
	return result;
}

// ---------------------------------------------------------------------------
// editor_find_nodes_in_group (old `find_nodes_in_group`, node.rs:584)
// ---------------------------------------------------------------------------
static Variant _tool_find_nodes_in_group(const Dictionary &p_args, MCPToolError &r_error) {
	String group;
	if (!require_string(p_args, "group", group, r_error)) {
		return Variant();
	}
	if (group.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'group' must not be empty");
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor inspectors outside a running editor",
				"Start the MCP server inside the Godot editor to inspect the editor scene")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}

	Array nodes;
	collect_nodes(root, root, String(), group, nodes);

	Dictionary result;
	result["group"] = group;
	result["nodes"] = nodes;
	result["count"] = nodes.size();
	return result;
}

// ---------------------------------------------------------------------------
// editor_find_nodes_by_type (old `find_nodes_by_type`, batch.rs:130)
// ---------------------------------------------------------------------------
static Variant _tool_find_nodes_by_type(const Dictionary &p_args, MCPToolError &r_error) {
	String type;
	if (!require_string(p_args, "type", type, r_error)) {
		return Variant();
	}
	if (type.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'type' must not be empty");
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor inspectors outside a running editor",
				"Start the MCP server inside the Godot editor to inspect the editor scene")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}

	Array nodes;
	collect_nodes(root, root, type, String(), nodes);

	Dictionary result;
	result["nodes"] = nodes;
	result["count"] = nodes.size();
	return result;
}

// ---------------------------------------------------------------------------
// editor_get_node_signals (old `get_signals`, editor.rs:460)
//
// The node is addressed the same way as in the rest of the editor node family
// (`MCPTools::find_node`, i.e. the migration source's `node.rs:148` resolution).
// The migration source's own GDScript used `root.find_node(path, true, false)`
// there, a *by-name* recursive search, because it had to reach the node from a
// script string; inside the module the shared resolution is both stricter and
// consistent with every neighbouring tool (REPORT-016 section 2 records this as
// a deviation).
// ---------------------------------------------------------------------------
static Variant _tool_get_node_signals(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_node_path(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor inspectors outside a running editor",
				"Start the MCP server inside the Godot editor to inspect the editor scene")) {
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

	const Array signals = signal_entries(root, node);

	Dictionary result;
	result["node_path"] = String(root->get_path_to(node));
	result["type"] = node->get_class();
	result["signals"] = signals;
	result["count"] = signals.size();
	return result;
}

// ---------------------------------------------------------------------------
// editor_list_signal_connections (old `find_signal_connections`, batch.rs:207)
//
// Both filters are optional substrings, and the two empty cases are different:
// an absent `node_path` means "every node", an absent `signal_name` means "every
// signal". The migration source used `unwrap_or("")` for both, which is the same
// answer; the difference is `optional_string`, which refuses a present-but-wrong
// type with `-32602` instead of ignoring it (PLAYBOOK section 6.2).
//
// TASK-051 O-9 adds `scope` (default `"all"` = this tool's answer before the
// task, byte for byte) on top of those two filters; it is the only filter that
// can separate the editor's own internal wiring from the scene's connections,
// which is what the audit measured on a 5-node scene (60 of 60 internal, 12 659
// B). The `signal_name` filter is deliberately **unchanged** - still a substring
// test - because that substring behaviour is what the frozen contract
// description of this tool promises and what distinguishes it from
// `editor_analyze_signal_flow`'s exact `node_path` (GDR-17, the R-1
// discriminator in `scripts/gen_renamed_contract.py`).
// ---------------------------------------------------------------------------
static Variant _tool_list_signal_connections(const Dictionary &p_args, MCPToolError &r_error) {
	String node_filter;
	if (!optional_string(p_args, "node_path", String(), node_filter, r_error)) {
		return Variant();
	}
	String signal_filter;
	if (!optional_string(p_args, "signal_name", String(), signal_filter, r_error)) {
		return Variant();
	}
	String scope_text;
	if (!optional_string(p_args, "scope", "all", scope_text, r_error)) {
		return Variant();
	}
	SignalConnectionScope scope = SignalConnectionScope::ALL;
	if (!parse_signal_connection_scope(scope_text, scope)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'scope' is '%s'; the accepted values are 'all' (every connection), "
				"'user' (only connections whose method is a scene-side method) and 'internal' "
				"(only the editor/engine Class::method bindings)",
				scope_text));
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor inspectors outside a running editor",
				"Start the MCP server inside the Godot editor to inspect the editor scene")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}

	Array all_connections;
	collect_signal_connections(root, root, node_filter, signal_filter, all_connections);
	const Array connections = filter_signal_connections_by_scope(all_connections, scope);

	Dictionary result;
	result["connections"] = connections;
	result["count"] = connections.size();
	result["scope"] = String::utf8(signal_connection_scope_name(scope));
	// The breakdown of the *unfiltered* collector answer: `scope:"user"` still
	// says how much internal wiring the same request is hiding, which is the
	// number the audit's O-9 is about.
	result["counts"] = count_signal_connections_by_scope(all_connections);
	return result;
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

// The authoritative `description` and `inputSchema` of each tool are the contract
// entries of docs/tools_list.renamed.json, character for character; the schemas
// are *parsed* from the exact contract JSON instead of being rebuilt as a
// hand-written Dictionary, because the gate compares all three fields verbatim.
//
// None of these schemas contains a number (no `minimum`, no numeric `default`),
// so the integral-number folding `editor_read_scene_inspector.cpp` needs to
// survive Godot's single number type has nothing to fold here.
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_node_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_node_read_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_get_node_properties", String::utf8(R"desc(获取节点属性)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"path":{"type":"string"},"properties":{"items":{"type":"string"},"type":"array"}},"required":["path"],"type":"object"})schema"));
		builder.handler(_tool_get_node_properties).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_get_node_groups", String::utf8(R"desc(获取节点所属的分组列表)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"description":"节点路径","type":"string"}},"required":["node_path"],"type":"object"})schema"));
		builder.handler(_tool_get_node_groups).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_find_nodes_in_group", String::utf8(R"desc(按组名查找所有节点)desc"));
		builder.channel("editor").verb("find").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"group":{"description":"组名","type":"string"}},"required":["group"],"type":"object"})schema"));
		builder.handler(_tool_find_nodes_in_group).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_find_nodes_by_type", String::utf8(R"desc(按类型查找所有节点)desc"));
		builder.channel("editor").verb("find").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"type":{"type":"string"}},"required":["type"],"type":"object"})schema"));
		builder.handler(_tool_find_nodes_by_type).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_get_node_signals", String::utf8(R"desc(获取指定节点的信号列表及连接信息)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"description":"节点路径 (相对于场景根节点)","type":"string"}},"required":["node_path"],"type":"object"})schema"));
		builder.handler(_tool_get_node_signals).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_list_signal_connections", String::utf8(R"desc(递归查找场景中所有信号连接 判别点：扁平返回 connections[]（每项 {source,signal,target,method}）与 count，收全部连接（不过滤非持久连接）、node_path 与 signal_name 均按子串匹配；要按节点嵌套的流向分析请用 editor_analyze_signal_flow。)desc"));
		builder.channel("editor").verb("list").scope(MCPToolScope::EDITOR).mutating(false);
		// TASK-110: the registered schema was missing `scope`, so the parameter
		// validator answered -32602 'Unknown parameter' before this handler - which
		// has supported the narrowing since TASK-051 (see the parser and the
		// `counts` breakdown below) - ever saw the argument. The contract
		// (docs/tools_list.renamed.json) declares `scope` with this exact enum,
		// default and description, so the member below is the contract's, copied
		// verbatim; the schema is the only thing that was out of step.
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"description":"节点路径过滤（可选，包含匹配）","type":"string"},"scope":{"default":"all","description":"连接范围：all=全部连接（默认，与本工具旧答案逐字相同）；user=只保留 method 不含 \"::\" 的连接，即场景/脚本自己连的；internal=只保留 method 形如 Class::method 的引擎/编辑器内部连接（编辑器的自连线）。注意内部连接的 source 是普通场景节点路径，按 node_path/signal_name 过滤不掉它们，只有 method 能区分；响应的 counts 给出三种口径各自的条数","enum":["all","user","internal"],"type":"string"},"signal_name":{"description":"信号名过滤（可选，包含匹配）","type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_list_signal_connections).register_into(r_registry);
	}
}
