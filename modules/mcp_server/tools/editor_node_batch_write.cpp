/**************************************************************************/
/*  editor_node_batch_write.cpp                                           */
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
#include "editor_node_batch_write.h"

#include "tool_builder.h"
#include "tool_helpers.h"
// The one definition of the module's node-property write. The batch grammar
// asks it for every `properties` entry and for the batched property write, so
// "does the object really have this property, how is the caller's JSON value
// coerced into it" has one implementation for the whole module (TASK-014 D-1 /
// TASK-017 section 4).
#include "running_game_node_write.h"

#include "core/io/json.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/os/memory.h"
#include "core/string/node_path.h"
#include "core/string/string_name.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"

using namespace MCPTools;

// The runtime half of the editor guard lives in `tools/tool_helpers.*` and is
// called below as `require_editor_ui(r_error, <non-editor wording>,
// <suggestion>)`; `MCPTools::edited_scene_root()` and `MCPTools::find_node()`
// are the hoisted single definitions this group calls instead of copying.

// The migration source's own spelling for a node it returns: the path relative
// to the edited scene root, with the root itself as "." (node.rs' `get_path_to`
// idiom). It is `MCPTools::relative_path` (`tools/tool_helpers.*`): the repair
// pass hoisted the copy this file used to carry.

// ---------------------------------------------------------------------------
// The batch transaction (DECISION D1).
//
// A prepared element: the node exists, its name and properties are applied, but
// it is **not** in the scene tree yet. The commit phase attaches every prepared
// node in input order. `pending_path` is the path the node will have once
// attached, computed from the parent's relative path and the (possibly
// sanitised) name - a detached node has no `get_path_to` answer, and the
// rollback envelope has to name what was rolled back.
// ---------------------------------------------------------------------------
struct _PendingNode {
	int index = 0;
	Node *parent = nullptr;
	Node *node = nullptr;
	String requested_type;
	String actual_class;
	String requested_parent_path;
	String pending_path;
};

// `{"index":N,"type":"...","property":"...","parent_path":"...","reason":"..."}`.
static Dictionary _batch_error_entry(int p_index, const String &p_type, const String &p_property,
		const String &p_parent_path, const String &p_reason) {
	Dictionary entry;
	entry["index"] = p_index;
	entry["type"] = p_type;
	entry["property"] = p_property;
	entry["parent_path"] = p_parent_path;
	entry["reason"] = p_reason;
	return entry;
}

// The `data.batch` envelope of a rolled-back call. Its `status` is never "ok",
// its `created` list is empty and it names both the refusal and everything that
// was taken back, so the wire cannot be read as a partial success.
static Dictionary _rollback_envelope(const Array &p_errors, const Array &p_rolled_back) {
	Dictionary envelope;
	envelope["status"] = "rolled_back";
	envelope["created"] = Array();
	envelope["count"] = 0;
	envelope["errors"] = p_errors;
	envelope["rolled_back"] = p_rolled_back;
	envelope["on_error"] = "all_or_nothing";
	return envelope;
}

// The chosen wire shape (documented in REPORT-017 section 5): the JSON-RPC
// `error` carries the failure code and a readable message naming the element
// index, `error.data.suggestion` explains the rollback, and `error.data.batch`
// is the full `{"status":"rolled_back", ...}` envelope. `result` is null because
// a tool that fills `r_error` answers no payload (mcp_jsonrpc.cpp:296-303), so
// a rolled-back call is impossible to read as a success.
static MCPToolError _attach_batch_envelope(MCPToolError p_error, const Dictionary &p_envelope,
		const String &p_suggestion) {
	Dictionary data;
	if (p_error.data.get_type() == Variant::DICTIONARY) {
		data = p_error.data;
	}
	data["batch"] = p_envelope;
	data["suggestion"] = p_suggestion;
	p_error.data = data;
	return p_error;
}

// Rolls the prepare phase back (reverse order, `memdelete`, nothing is attached
// yet) and builds the single refusal of the call.
static Variant _transaction_fail(Vector<_PendingNode> &p_pending, MCPToolError &r_error,
		int p_index, const String &p_type, const String &p_property, const String &p_parent_path,
		const String &p_reason, int p_code, const String &p_message, const String &p_suggestion) {
	Array rolled_back;
	for (int i = p_pending.size() - 1; i >= 0; i--) {
		Dictionary entry;
		entry["index"] = p_pending[i].index;
		entry["type"] = p_pending[i].actual_class;
		entry["node_path"] = p_pending[i].pending_path;
		entry["reason"] = "transaction rollback";

// TASK-051 C-3: is the parent this element cannot find the *requested* path of a
// later element of the same batch? Only used to improve the refusal message -
// the batch is refused either way - but the distinction matters to a caller:
// "there is no such node" and "your parent is created later in this array" need
// opposite fixes (create it first vs. reorder the array). It is also the shape a
// parent/child *cycle* takes, since the batch is applied in array order and only
// ever looks backwards.
//
// The paths compared are the elements' **requested** ones (`parent_path` +
// `name`), not the prepared `pending_path`, because the elements after
// `p_from_index` have not been prepared yet.
static int _later_element_requesting(const Array &p_nodes, int p_from_index,
		const String &p_parent_path, const String &p_root_name, String &r_later_path) {
	for (int j = p_from_index + 1; j < p_nodes.size(); j++) {
		const Variant element = p_nodes[j];
		if (element.get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary entry = element;
		const Variant name_value = entry.get("name", Variant());
		if (name_value.get_type() != Variant::STRING) {
			continue;
		}
		const String name = name_value;
		if (name.is_empty()) {
			continue;
		}
		String parent_path = ".";
		const Variant parent_value = entry.get("parent_path", Variant());
		if (parent_value.get_type() == Variant::STRING && !String(parent_value).strip_edges().is_empty()) {
			parent_path = parent_value;
		}
		const String requested = _pending_path_for(parent_path, name);
		if (_pending_path_matches(requested, p_parent_path, p_root_name)) {
			r_later_path = requested;
			return j;
		}
	}
	return -1;
}

// `{"index":N,"type":"...","property":"...","parent_path":"...","reason":"..."}`.
static Dictionary _batch_error_entry(int p_index, const String &p_type, const String &p_property,
		const String &p_parent_path, const String &p_reason) {
	Dictionary entry;
	entry["index"] = p_index;
	entry["type"] = p_type;
	entry["property"] = p_property;
	entry["parent_path"] = p_parent_path;
	entry["reason"] = p_reason;
	return entry;
}

// The `data.batch` envelope of a rolled-back call. Its `status` is never "ok",
// its `created` list is empty and it names both the refusal and everything that
// was taken back, so the wire cannot be read as a partial success.
static Dictionary _rollback_envelope(const Array &p_errors, const Array &p_rolled_back) {
	Dictionary envelope;
	envelope["status"] = "rolled_back";
	envelope["created"] = Array();
	envelope["count"] = 0;
	envelope["errors"] = p_errors;
	envelope["rolled_back"] = p_rolled_back;
	envelope["on_error"] = "all_or_nothing";
	return envelope;
}

// The chosen wire shape (documented in REPORT-017 section 5): the JSON-RPC
// `error` carries the failure code and a readable message naming the element
// index, `error.data.suggestion` explains the rollback, and `error.data.batch`
// is the full `{"status":"rolled_back", ...}` envelope. `result` is null because
// a tool that fills `r_error` answers no payload (mcp_jsonrpc.cpp:296-303), so
// a rolled-back call is impossible to read as a success.
static MCPToolError _attach_batch_envelope(MCPToolError p_error, const Dictionary &p_envelope,
		const String &p_suggestion) {
	Dictionary data;
	if (p_error.data.get_type() == Variant::DICTIONARY) {
		data = p_error.data;
	}
	data["batch"] = p_envelope;
	data["suggestion"] = p_suggestion;
	p_error.data = data;
	return p_error;
}

// Rolls the prepare phase back (reverse order, `memdelete`, nothing is attached
// yet) and builds the single refusal of the call.
static Variant _transaction_fail(Vector<_PendingNode> &p_pending, MCPToolError &r_error,
		int p_index, const String &p_type, const String &p_property, const String &p_parent_path,
		const String &p_reason, int p_code, const String &p_message, const String &p_suggestion) {
	Array rolled_back;
	for (int i = p_pending.size() - 1; i >= 0; i--) {
		Dictionary entry;
		entry["index"] = p_pending[i].index;
		entry["type"] = p_pending[i].actual_class;
		entry["node_path"] = p_pending[i].pending_path;
		entry["reason"] = "transaction rollback";
		rolled_back.push_back(entry);
	}
	for (int i = p_pending.size() - 1; i >= 0; i--) {
		memdelete(p_pending[i].node);
	}
	p_pending.clear();

	Array errors;
	errors.push_back(_batch_error_entry(p_index, p_type, p_property, p_parent_path, p_reason));

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
	r_error = _attach_batch_envelope(error, _rollback_envelope(errors, rolled_back), p_suggestion);
	return Variant();
}

static const char *const BATCH_ROLLBACK_SUGGESTION =
		"editor_add_nodes_batch is all-or-nothing: no node of the request was added. Fix the element the message names "
		"(or split the request into calls that each succeed) and call the tool again.";

// ---------------------------------------------------------------------------
// MCPTools:: the testable entry points.
// ---------------------------------------------------------------------------
namespace MCPTools {

static void _collect_by_type(Node *p_node, const StringName &p_type, Vector<Node *> &r_out) {
	if (p_node->get_class() == String(p_type) || p_node->is_class(p_type)) {
		r_out.push_back(p_node);
	}
	const int child_count = p_node->get_child_count();
	for (int i = 0; i < child_count; i++) {
		_collect_by_type(p_node->get_child(i), p_type, r_out);
	}
}

void collect_nodes_by_type(Node *p_root, const String &p_type, Vector<Node *> &r_out) {
	_collect_by_type(p_root, StringName(p_type), r_out);
}

Variant add_nodes_batch_on(Node *p_root, const Array &p_nodes, MCPToolError &r_error,
		bool p_resolve_within_batch) {
	if (p_nodes.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'nodes' must be a non-empty array");
		return Variant();
	}

	Vector<_PendingNode> pending;

	for (int i = 0; i < p_nodes.size(); i++) {
		const Variant element = p_nodes[i];
		if (element.get_type() != Variant::DICTIONARY) {
			return _transaction_fail(pending, r_error, i, String(), String(), String(), "Entry is not an object",
					MCP_ERR_INVALID_PARAMS, vformat("Parameter 'nodes[%d]' must be an object", i), BATCH_ROLLBACK_SUGGESTION);
		}
		const Dictionary entry = element;

		// `type` is the only required member (batch.rs:301).
		const Variant type_value = entry.get("type", Variant());
		if (type_value.get_type() != Variant::STRING) {
			return _transaction_fail(pending, r_error, i, String(), String(), String(), "Missing or invalid 'type'",
					MCP_ERR_INVALID_PARAMS, vformat("'nodes[%d].type' must be a string", i), BATCH_ROLLBACK_SUGGESTION);
		}
		const String type = type_value;
		if (type.strip_edges().is_empty()) {
			return _transaction_fail(pending, r_error, i, type, String(), String(), "Missing or invalid 'type'",
					MCP_ERR_INVALID_PARAMS, vformat("'nodes[%d].type' must not be empty", i), BATCH_ROLLBACK_SUGGESTION);
		}

		String parent_path = ".";
		const Variant parent_value = entry.get("parent_path", Variant());
		if (parent_value.get_type() != Variant::NIL) {
			if (parent_value.get_type() != Variant::STRING) {
				return _transaction_fail(pending, r_error, i, type, String(), String(), "Invalid 'parent_path'",
						MCP_ERR_INVALID_PARAMS, vformat("'nodes[%d].parent_path' must be a string", i), BATCH_ROLLBACK_SUGGESTION);
			}
			parent_path = parent_value;
			if (parent_path.strip_edges().is_empty()) {
				parent_path = ".";
			}
		}

		String requested_name;
		const Variant name_value = entry.get("name", Variant());
		if (name_value.get_type() != Variant::NIL) {
			if (name_value.get_type() != Variant::STRING) {
				return _transaction_fail(pending, r_error, i, type, String(), String(), "Invalid 'name'",
						MCP_ERR_INVALID_PARAMS, vformat("'nodes[%d].name' must be a string", i), BATCH_ROLLBACK_SUGGESTION);
			}
			requested_name = name_value;
		}

		Dictionary properties;
			}
			properties = properties_value;
		}

		// The parent is resolved before the node is constructed, so a refused
		// element does not even allocate an orphan.
		//
		// TASK-051 C-3: `_resolve_batch_parent` asks the scene tree first and,
		// only in `resolve_within_batch` mode, falls back to the nodes this same
		// request already prepared; `parent_relative` is the resolver's answer
		// (it cannot be recomputed below - a batch parent is detached, and
		// `relative_path()` on a detached node logs an engine ERR).
		String parent_relative;
		bool parent_from_batch = false;
		Node *parent = _resolve_batch_parent(p_root, parent_path, pending, p_resolve_within_batch,
				parent_relative, parent_from_batch);
		if (parent == nullptr) {
			// TASK-051 C-3: in the new mode the two "-32001" causes are told
			// apart, because they have opposite fixes. The forward-reference
			// scan only feeds the message; the refusal itself is the same.
			if (p_resolve_within_batch) {
				String later_path;
				const int later_index = _later_element_requesting(p_nodes, i, parent_path,
						String(p_root->get_name()), later_path);
				if (later_index >= 0) {
					return _transaction_fail(pending, r_error, i, type, String(), parent_path,
							vformat("Parent '%s' is created later in this batch (nodes[%d])", parent_path, later_index),
							MCP_ERR_NOT_FOUND,
							vformat("nodes[%d]: parent '%s' is the path nodes[%d] asks for, and a node's parent must appear before it in the batch (a forward reference is what a parent/child cycle looks like when the batch is applied in array order)",
									i, parent_path, later_index),
							"Put the parent element before the child in 'nodes' (the batch is applied in array order), or split the request into two editor_add_nodes_batch calls");
				}
			}
			return _transaction_fail(pending, r_error, i, type, String(), parent_path,
					vformat("Parent '%s' not found", parent_path), MCP_ERR_NOT_FOUND,
					vformat("nodes[%d]: parent '%s'", i, parent_path), BATCH_ROLLBACK_SUGGESTION);
		}

		const StringName type_name(type);
		if (!ClassDB::class_exists(type_name)) {
			return _transaction_fail(pending, r_error, i, type, String(), parent_path,
					vformat("Unknown node type: %s", type), MCP_ERR_INVALID_PARAMS,
					vformat("nodes[%d]: cannot instantiate node type '%s': no such class", i, type), BATCH_ROLLBACK_SUGGESTION);
		}
		if (!ClassDB::is_parent_class(type_name, StringName("Node"))) {
			return _transaction_fail(pending, r_error, i, type, String(), parent_path,
					vformat("'%s' is not a Node subclass", type), MCP_ERR_INVALID_PARAMS,
					vformat("nodes[%d]: type '%s' is not a Node subclass", i, type), BATCH_ROLLBACK_SUGGESTION);
		}
		MCPToolError instantiate_error;
		Object *created = instantiate_class(type, instantiate_error);
		if (created == nullptr) {
			return _transaction_fail(pending, r_error, i, type, String(), parent_path,
					instantiate_error.message, instantiate_error.code,
					vformat("nodes[%d]: %s", i, instantiate_error.message), BATCH_ROLLBACK_SUGGESTION);
		}
		Node *node = Object::cast_to<Node>(created);
		if (node == nullptr) {
			// Unreachable after the `is_parent_class` check; kept so the cascade
			// to `memdelete` cannot be reached by accident.
		// action is the existence check, so an undeclared name is refused here
		// with the element index and the property name instead of being silently
		// skipped (the migration source's `if exists` at batch.rs:358-387).
		const Array keys = properties.keys();
		for (int k = 0; k < keys.size(); k++) {
			const String property = keys[k];
			MCPToolError property_error;
			const Variant written = write_node_property(node, property, properties[keys[k]], property_error);
			if (written.get_type() == Variant::NIL) {
				memdelete(node);
				return _transaction_fail(pending, r_error, i, type, property, parent_path,
						property_error.message, property_error.code,
						vformat("nodes[%d]: %s", i, property_error.message), BATCH_ROLLBACK_SUGGESTION);
			}
		}

		// Prepared, deliberately still unattached.
		_PendingNode prepared;
		prepared.index = i;
		prepared.parent = parent;
		prepared.node = node;
		prepared.requested_type = type;
		prepared.actual_class = node->get_class();
		prepared.requested_parent_path = parent_path;
		prepared.parent_from_batch = parent_from_batch;
		const String actual_name = String(node->get_name());
		prepared.pending_path = _pending_path_for(parent_relative, actual_name);

		// TASK-051 C-3: in the new mode a duplicate path inside one request is a
		// conflict, not an engine rename. The second element would silently
		// become a node whose name is not the one it asked for, and a later
		// element naming that path could not tell the two apart. The default mode
		// keeps the engine's own rename (the existing doctest pins it).
		if (p_resolve_within_batch && !prepared.pending_path.is_empty()) {
			for (int p = 0; p < pending.size(); p++) {
				if (pending[p].pending_path != prepared.pending_path) {
					continue;
				}
				memdelete(node);
				return _transaction_fail(pending, r_error, i, type, String(), parent_path,
						vformat("Two nodes of this batch would both be '%s' (nodes[%d] and nodes[%d])",
								prepared.pending_path, pending[p].index, i),
						MCP_ERR_INVALID_PARAMS,
						vformat("nodes[%d]: '%s' is already created by nodes[%d] of this batch, so a reference to it would be ambiguous",
								i, prepared.pending_path, pending[p].index),
						"Give every element of one parent's children a distinct 'name' (the engine would otherwise rename the second node), or split the request into two editor_add_nodes_batch calls");
			}
		}
		pending.push_back(prepared);
	}

	// Commit phase: attach in input order, then read the real name and path back.
	Array created;
	for (int i = 0; i < pending.size(); i++) {
		const _PendingNode &prepared = pending[i];
		prepared.parent->add_child(prepared.node);
		// `owner` has to be set *after* `add_child()`: it is the ancestor
		// relationship that makes the root a legal owner.
		prepared.node->set_owner(p_root);

		Dictionary entry;
		entry["index"] = prepared.index;
		entry["type"] = prepared.node->get_class();
		entry["name"] = String(prepared.node->get_name());
		entry["parent_path"] = prepared.requested_parent_path;
		// TASK-051 C-3: which of the two parent sources answered. It is the only
		// way to tell "attached under a node this call created" from "attached
		// under a same-named node that was already in the scene", and a client
		// feeding `node_path` back into another tool needs that distinction.
		entry["parent_source"] = prepared.parent_from_batch ? "batch" : "scene";
		entry["node_path"] = relative_path(p_root, prepared.node);
		created.push_back(entry);
	}

	Dictionary result;
	result["status"] = "ok";
	result["created"] = created;
	result["count"] = created.size();
	result["errors"] = Array();
	// TASK-051 C-3: the mode is echoed so a caller (and a doctest) can read back
	// which parent-resolution rule the answer was produced under.
	result["resolve_within_batch"] = p_resolve_within_batch;
	return result;
}

Variant set_node_property_batch_on(Node *p_root, const String &p_node_type, const String &p_property,
		const Variant &p_raw_value, MCPToolError &r_error) {
	const StringName type_name(p_node_type);
	if (!ClassDB::class_exists(type_name)) {
		r_error = MCPToolError::invalid_params(vformat("Unknown node type: '%s'", p_node_type));
		return Variant();
	}

	Vector<Node *> matched;
	collect_nodes_by_type(p_root, p_node_type, matched);
	if (matched.is_empty()) {
		// The migration source answered `{"updated": 0}` as a success here. This
		// module refuses a call that could not do what its name says.
		r_error = MCPToolError::not_found(vformat("No node of type '%s' in the edited scene", p_node_type),
				"Use editor_find_nodes_by_type to list the nodes this scene has, or editor_add_nodes_batch/add a node of that type first");
		return Variant();
	}

	// The pre-check the migration source did not do at all: one missing property
	// on one matched node refuses the whole call *before* a single write.
	//
	// TASK-028 G-1: the question is asked about the whole **property path**
	// (`position:y` is as much a property of the node as `position` is), so the
	// batch accepts exactly what `editor_set_node_property` accepts. A path that
	// cannot be indexed at all, or that is malformed, is a request-shape
	// violation and is reported as such instead of as "the node does not declare
	// it".
	for (Node *node : matched) {
		MCPToolError path_error;
		if (node_property_path_exists(node, p_property, path_error)) {
			continue;
		}
		if (path_error.is_error() && path_error.code == -32602) {
			r_error = path_error;
			return Variant();
		}
		r_error = MCPToolError::not_found(
				vformat("Property '%s' on node '%s'", p_property, relative_path(p_root, node)),
				"Every matched node must declare the property. Use editor_get_node_properties on the nodes "
				"editor_find_nodes_by_type returns to see which one does not");
		return Variant();
	}

	// TASK-018 section 1.2: the *value* is validated against every matched node
	// as well, before the first write. A layout-incompatible value
	// (`{"node_type":"Node2D","property":"position","value":1e20}`) is a
	// validation failure, so it must be caught here rather than by the first
	// write inside the loop below: `prepare_node_property_value` is the exact
	// validation half of `write_node_property`, so "this value fits" has one
	// definition and the whole call is refused with nothing written on any node.
	for (Node *node : matched) {
		Variant converted;
		MCPToolError value_error;
		if (!prepare_node_property_value(node, p_property, p_raw_value, converted, value_error)) {
			value_error.message = vformat(
					"Property '%s' write refused before any node was written: %s", p_property, value_error.message);
			r_error = value_error;
			return Variant();
		}
	}

	Vector<Node *> written;
	Vector<Variant> previous_values;
	// TASK-037 D2 (self-audit): the same read-back question the single-node
	// writer answers, asked per matched node. `write_node_property` returns the
	// engine's `ignored` bag for the node it just wrote; a batch that answered
	// only `{"updated": N, "status": "ok"}` hid the fact that the engine's own
	// setter clamped the value on some (or every) node - the exact shape
	// `editor_set_node_property(path=Sprite, property=hframes, value=0)` exposes
	// live (`new_value: 1`). The bag is keyed by the node's relative path so one
	// entry is still readable, and `ignored_count` says at a glance whether the
	// call stored the request everywhere.
	Dictionary ignored;
	for (Node *node : matched) {
		// TASK-028 G-1: the value to put back is read through the same property
		// path the write uses, so a sub-property write is rolled back to the
		// component's own previous value instead of to nothing.
		bool previous_valid = false;
		MCPToolError previous_error;
		const Variant previous = read_node_property_path(node, p_property, previous_valid, previous_error);
		MCPToolError write_error;
		const Variant written_result = write_node_property(node, p_property, p_raw_value, write_error);
		if (written_result.get_type() == Variant::NIL) {
			// Restore what this call already changed, newest first, so a failure
			// in the middle leaves no node written.
			for (int j = written.size() - 1; j >= 0; j--) {
				MCPToolError rollback_error;
				apply_node_property_value(written[j], p_property, previous_values[j], rollback_error);
			}
			write_error.message = vformat(
					"Property '%s' write failed after %d node(s) had been written; their previous values were restored: %s",
					p_property, written.size(), write_error.message);
			r_error = write_error;
			return Variant();
		}
		const Dictionary node_answer = written_result;
		const Dictionary node_ignored = node_answer.has("ignored") ? (Dictionary)node_answer["ignored"] : Dictionary();
		if (node_ignored.has(p_property)) {
			ignored[relative_path(p_root, node)] = node_ignored[p_property];
		}
		written.push_back(node);
		previous_values.push_back(previous);
	}

	Array paths;
	for (Node *node : written) {
		paths.push_back(relative_path(p_root, node));
	}

	Dictionary result;
	result["updated"] = written.size();
	result["property"] = p_property;
	result["node_type"] = p_node_type;
	result["status"] = "ok";
	result["nodes"] = paths;
	result["count"] = written.size();
	// Per-node `{requested, stored, reason}` for every node whose write the engine
	// stored differently (TASK-037 D2; see the comment above). Empty means the
	// engine stored the request on every matched node.
	result["ignored"] = ignored;
	result["ignored_count"] = ignored.size();
	return result;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// editor_add_nodes_batch (old `batch_add_nodes`, batch.rs:270)
//
// The argument grammar is validated here (array-ness, non-emptiness) so a
// malformed call is `-32602` even in a process without an edited scene; the
// transaction itself is `MCPTools::add_nodes_batch_on`.
//
// Wire shape of a rolled-back call (the decision recorded in REPORT-017):
//   * `error.code`  - `-32602` for a shape/type violation, `-32001` for a
//     missing parent or property;
//   * `error.message` - a readable message naming the element index;
//   * `error.data.suggestion` - the rollback explanation;
//   * `error.data.batch` - `{"status":"rolled_back","created":[],"count":0,
//     "errors":[{index,type,property,parent_path,reason}],
//     "rolled_back":[{index,type,node_path,reason}],"on_error":"all_or_nothing"}`;
//   * `result` is null (the handler answers no payload).
// ---------------------------------------------------------------------------
static Variant _tool_add_nodes_batch(const Dictionary &p_args, MCPToolError &r_error) {
	const Variant nodes_value = p_args.get("nodes", Variant());
	if (nodes_value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter: nodes");
		return Variant();
	}
	if (nodes_value.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(vformat("'nodes' must be an array, got %s",
				Variant::get_type_name(nodes_value.get_type())));
		return Variant();
	}
	const Array nodes = nodes_value;
	if (nodes.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'nodes' must be a non-empty array");
		return Variant();
	}
	// TASK-051 C-3: the mode is read (and a present-but-wrong type refused)
	// *before* the editor guard, exactly like the array shape above, so a
	// mistyped `resolve_within_batch` is a `-32602` in every process rather than
	// a `-32000` that hides it (PLAYBOOK section 6.2).
	bool resolve_within_batch = false;
	if (!optional_bool(p_args, "resolve_within_batch", false, resolve_within_batch, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor node writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return add_nodes_batch_on(root, nodes, r_error, resolve_within_batch);
}

// ---------------------------------------------------------------------------
// editor_set_node_property_batch (old `batch_set_property`, batch.rs:147)
//
// `value` accepts every JSON type, so its presence (not its nullness) is what
// "required" means - the same rule `editor_set_node_property` follows.
// ---------------------------------------------------------------------------
static Variant _tool_set_node_property_batch(const Dictionary &p_args, MCPToolError &r_error) {
	String node_type;
	if (!require_string(p_args, "node_type", node_type, r_error)) {
		return Variant();
	}
	if (node_type.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_type' must not be empty");
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
	if (!p_args.has("value")) {
		r_error = MCPToolError::invalid_params("Missing required parameter: value");
		return Variant();
	}
	const Variant raw_value = p_args["value"];
	if (!require_editor_ui(r_error, "editor node writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_node_property_batch_on(root, node_type, property, raw_value, r_error);
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
//
// The authoritative `description` and `inputSchema` of each tool are the
// contract entries of docs/tools_list.renamed.json, character for character; the
// schemas are *parsed* from the exact contract JSON instead of being rebuilt as
// a hand-written Dictionary, because the gate compares all three fields
// verbatim.
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_node_batch_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_node_batch_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_add_nodes_batch", String::utf8(R"desc(批量添加节点到场景)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"type":"object","properties":{"nodes":{"description":"节点数组，每个元素包含 type（必填）、parent_path、name、properties","items":{"properties":{"name":{"description":"节点名称","type":"string"},"parent_path":{"description":"父节点路径，默认 \".\"","type":"string"},"properties":{"description":"要设置的属性字典","type":"object"},"type":{"description":"节点类型","type":"string"}},"required":["type"],"type":"object"},"type":"array"},"resolve_within_batch":{"default":false,"description":"为 true 时元素的 parent_path 可以指向**本批更早的元素**所创建的节点（同一个请求里建父子树）。父元素必须排在子元素之前，父路径指向更后面的元素会被拒绝（父/子循环在按数组顺序应用时就是这个形状）；同一父节点下、同一批内重名会被拒绝（默认 false 时保留引擎自己的重命名）——两种拒绝都仍然整批回滚。默认 false：父路径只按调用到达时的场景树解析，与旧行为逐字相同。响应在每个 created 元素上给出 parent_source（scene/batch），说明父节点来自场景树还是本批","type":"boolean"}},"required":["nodes"]})schema"));
		builder.handler(_tool_add_nodes_batch).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_node_property_batch", String::utf8(R"desc(批量设置同类型节点的属性)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"type":"object","properties":{"node_type":{"type":"string"},"property":{"type":"string"},"value":{}},"required":["node_type","property","value"]})schema"));
		builder.handler(_tool_set_node_property_batch).register_into(r_registry);
	}
}