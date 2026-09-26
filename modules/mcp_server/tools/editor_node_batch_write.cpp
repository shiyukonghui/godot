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
	// TASK-051 C-3: true when `parent` is a node an *earlier element of this same
	// request* prepared (so it is still detached and `relative_path()` cannot
	// answer for it), false when it came out of the scene tree.
	bool parent_from_batch = false;
	// TASK-097 (D-3): the name the caller asked for, kept after `set_name()` so
	// the commit phase can tell "the engine stored my name" from "the engine
	// renamed it because the name was taken"; `name_conflict_with` is the node
	// that already carried the name (`nullptr` when the divergence has another
	// cause, e.g. `Node::set_name()` sanitising a path separator).
	String requested_name;
	Node *name_conflict_with = nullptr;
};

// ---------------------------------------------------------------------------
// TASK-097 (tool defect D-3): the duplicate generations this session's batches
// created, so `editor_save_scene` can report them instead of saving silently.
//
// The record is written at commit time, and only for a node the engine had to
// rename **because a sibling already carried the requested name**. A caller who
// passes `on_name_conflict: "rename"` is the only way this can happen after this
// task, and the pair (the renamed node, the node that kept the name) is what
// `duplicate_name_conflicts_on()` re-validates against the live tree before it
// answers: if either node was deleted, or the two are no longer siblings, the
// record is dropped, so the answer is always a statement about the tree in front
// of the caller rather than about history.
// ---------------------------------------------------------------------------
namespace {
struct _NameConflictRecord {
	ObjectID scene_root;
	ObjectID added;
	ObjectID existing;
	String requested_name;
	String parent_path;
	String added_path;
	String existing_path;
};

Vector<_NameConflictRecord> _batch_name_conflicts;

Node *_name_conflict_instance(const ObjectID &p_id) {
	return Object::cast_to<Node>(ObjectDB::get_instance(p_id));
}
} // namespace


// TASK-051 C-3: the path a prepared-but-not-yet-attached node will have once the
// commit phase attaches it. This is the expression the prepare phase always
// used, extracted so that the within-batch parent lookup and the rollback
// envelope spell a path the same way:
//
//   * the root itself is "."; a child of the root is its own name;
//   * an unnamed child of a non-root parent answers the parent's path (an
//     unnamed node is only named by the engine on `add_child`);
//   * otherwise parent + "/" + name.
static String _pending_path_for(const String &p_parent_relative, const String &p_name) {
	if (p_parent_relative == ".") {
		return p_name;
	}
	if (p_name.is_empty()) {
		return p_parent_relative;
	}
	return p_parent_relative + "/" + p_name;
}

// TASK-051 C-3: does the requested `parent_path` name this prepared node?
// `find_node()` (`tools/tool_helpers.cpp:1337`) accepts a path relative to the
// root *and* the same path prefixed with the root's own name
// (`"Root/P1"`), so both spellings have to be recognised here or the batch would
// answer "not found" for a parent it did prepare.
static bool _pending_path_matches(const String &p_pending, const String &p_requested, const String &p_root_name) {
	return p_pending == p_requested || (p_root_name + "/" + p_pending) == p_requested;
}

// TASK-051 C-3: the parent lookup of one batch element. The scene tree is asked
// first and wins when it can answer, so the default mode's answer is
// byte-for-byte the `find_node()` call it always was; the prepared nodes of this
// same request are the second source and are only consulted in
// `resolve_within_batch` mode.
//
// `r_parent_relative` is the path the new node's `pending_path` is built from:
// for a tree parent it is `relative_path()`, for a batch parent it is that
// element's own `pending_path` (the node is detached, so the engine cannot be
// asked).
static Node *_resolve_batch_parent(Node *p_root, const String &p_parent_path,
		const Vector<_PendingNode> &p_pending, bool p_resolve_within_batch,
		String &r_parent_relative, bool &r_from_batch) {
	Node *parent = find_node(p_root, p_parent_path);
	if (parent != nullptr) {
		r_from_batch = false;
		r_parent_relative = (parent == p_root) ? String(".") : relative_path(p_root, parent);
		return parent;
	}
	if (!p_resolve_within_batch) {
		return nullptr;
	}
	const String root_name = String(p_root->get_name());
	for (int i = 0; i < p_pending.size(); i++) {
		if (!_pending_path_matches(p_pending[i].pending_path, p_parent_path, root_name)) {
			continue;
		}
		r_from_batch = true;
		r_parent_relative = p_pending[i].pending_path;
		return p_pending[i].node;
	}
	return nullptr;
}

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
//
// TASK-097: `p_extra_data` is an optional additional `error.data` bag (the
// name-conflict refusal attaches `conflicts` and `on_name_conflict` through it).
// It is merged *before* `_attach_batch_envelope` writes `suggestion` and `batch`,
// so those two keys keep the meaning they have on every other refusal of this
// tool.
static Variant _transaction_fail(Vector<_PendingNode> &p_pending, MCPToolError &r_error,
		int p_index, const String &p_type, const String &p_property, const String &p_parent_path,
		const String &p_reason, int p_code, const String &p_message, const String &p_suggestion,
		const Dictionary &p_extra_data = Dictionary()) {
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
	if (!p_extra_data.is_empty()) {
		Dictionary data;
		if (error.data.get_type() == Variant::DICTIONARY) {
			data = error.data;
		}
		const Array extra_keys = p_extra_data.keys();
		for (int i = 0; i < extra_keys.size(); i++) {
			data[extra_keys[i]] = p_extra_data[extra_keys[i]];
		}
		error.data = data;
	}
	r_error = _attach_batch_envelope(error, _rollback_envelope(errors, rolled_back), p_suggestion);
	return Variant();
}

static const char *const BATCH_ROLLBACK_SUGGESTION =
		"editor_add_nodes_batch is all-or-nothing: no node of the request was added. Fix the element the message names "
		"(or split the request into calls that each succeed) and call the tool again.";

// TASK-097 (D-3): the child of `p_parent` whose name is exactly `p_name`, or
// `nullptr`. A linear scan deliberately: `Node::get_node_or_null(NodePath(...))`
// would parse the requested name as a path (`a/b` is a child of `a`), and the
// question here is the engine's own uniqueness question, which
// `Node::_validate_child_name()` answers against `data.children` by name.
static Node *_child_named(Node *p_parent, const String &p_name) {
	const int count = p_parent->get_child_count();
	for (int i = 0; i < count; i++) {
		Node *child = p_parent->get_child(i);
		if (String(child->get_name()) == p_name) {
			return child;
		}
	}
	return nullptr;
}

// TASK-097 (D-3): every element whose requested `name` the target parent already
// carries, collected **before** the prepare phase allocates anything, so the
// refusal can name the whole list instead of only the first offender. Elements
// this pass cannot judge are simply skipped - a malformed element, an element
// without a name, and an element whose `parent_path` only a same-request element
// provides are all reported by the prepare phase, which owns those refusals.
static Array _collect_scene_name_conflicts(Node *p_root, const Array &p_nodes) {
	Array conflicts;
	for (int i = 0; i < p_nodes.size(); i++) {
		const Variant element = p_nodes[i];
		if (element.get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary entry = element;
		const Variant name_value = entry.get("name", Variant());
		if (name_value.get_type() != Variant::STRING || String(name_value).is_empty()) {
			continue;
		}
		String parent_path = ".";
		const Variant parent_value = entry.get("parent_path", Variant());
		if (parent_value.get_type() == Variant::STRING && !String(parent_value).strip_edges().is_empty()) {
			parent_path = parent_value;
		}
		Node *parent = find_node(p_root, parent_path);
		if (parent == nullptr) {
			continue;
		}
		const String requested = name_value;
		Node *clashing = _child_named(parent, requested);
		if (clashing == nullptr) {
			continue;
		}
		const Variant type_value = entry.get("type", Variant());
		const String parent_relative = (parent == p_root) ? String(".") : relative_path(p_root, parent);
		Dictionary conflict;
		conflict["index"] = i;
		conflict["type"] = (type_value.get_type() == Variant::STRING) ? String(type_value) : String();
		conflict["requested_name"] = requested;
		conflict["parent_path"] = parent_path;
		// The path the caller asked for and the path that already answers to it:
		// both are named, because "which node do I mean" is the whole question.
		conflict["node_path"] = _pending_path_for(parent_relative, requested);
		conflict["existing_node_path"] = relative_path(p_root, clashing);
		conflict["existing_type"] = clashing->get_class();
		conflicts.push_back(conflict);
	}
	return conflicts;
}

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
		bool p_resolve_within_batch, const String &p_on_name_conflict) {
	if (p_nodes.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'nodes' must be a non-empty array");
		return Variant();
	}

	// TASK-097 (D-3): the name-conflict policy. `"rename"` is the explicit
	// opt-in that keeps the engine's own behaviour; everything else is the safe
	// default and the tool's own argument guard has already narrowed the value to
	// the two legal spellings, so an unknown value here can only come from a
	// caller that bypassed the tool layer - treat it as the safe default.
	//
	// The scene-tree half of the check runs **before** the prepare phase: nothing
	// has been allocated yet, so the refusal can carry the complete list of
	// conflicts and the rollback envelope is empty because there is nothing to
	// roll back.
	const bool refuse_name_conflicts = p_on_name_conflict != String("rename");
	if (refuse_name_conflicts) {
		const Array conflicts = _collect_scene_name_conflicts(p_root, p_nodes);
		if (!conflicts.is_empty()) {
			String joined;
			for (int i = 0; i < conflicts.size(); i++) {
				const Dictionary conflict = conflicts[i];
				if (i > 0) {
					joined += ", ";
				}
				joined += String(conflict["node_path"]);
			}
			const Dictionary first = conflicts[0];
			const String message = vformat(
					"Refused: %d node(s) of this batch would duplicate a name that already exists under the target parent (%s)",
					conflicts.size(), joined);
			const String reason = vformat(
					"nodes[%d] asks for the name '%s' under '%s', and '%s' already answers to it",
					(int)first["index"], String(first["requested_name"]), String(first["parent_path"]),
					String(first["existing_node_path"]));
			const String suggestion =
					"Nothing was written: the nodes named in 'conflicts' already exist, so the engine would have renamed the "
					"new nodes to '@Type@N' and editor_save_scene would then have written BOTH copies into the scene (the "
					"duplicate draws on top of the real node). Either drop the conflicting elements and change the existing "
					"nodes with editor_set_node_property / editor_set_node_property_batch, or pass on_name_conflict: \"rename\" "
					"to accept the engine's rename explicitly - the answer then lists every renamed node in 'renamed'.";
			Dictionary extra;
			extra["conflicts"] = conflicts;
			extra["on_name_conflict"] = "refuse";
			Vector<_PendingNode> nothing;
			return _transaction_fail(nothing, r_error, (int)first["index"], String(first["type"]), String(),
					String(first["parent_path"]), reason, MCP_ERR_TOOL_STATE, message, suggestion, extra);
		}
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
		const Variant properties_value = entry.get("properties", Variant());
		if (properties_value.get_type() != Variant::NIL) {
			if (properties_value.get_type() != Variant::DICTIONARY) {
				return _transaction_fail(pending, r_error, i, type, String(), String(), "Invalid 'properties'",
						MCP_ERR_INVALID_PARAMS, vformat("'nodes[%d].properties' must be an object", i), BATCH_ROLLBACK_SUGGESTION);
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
			memdelete(created);
			return _transaction_fail(pending, r_error, i, type, String(), parent_path,
					vformat("'%s' is not a Node subclass", type), MCP_ERR_INVALID_PARAMS,
					vformat("nodes[%d]: type '%s' is not a Node subclass", i, type), BATCH_ROLLBACK_SUGGESTION);
		}

		// The name is applied only when the caller gave one: `Node::set_name("")`
		// is an `ERR_FAIL_COND` (scene/main/node.cpp:1441), and an unnamed node
		// gets the engine's own `@Type@N` name on `add_child` - which is what the
		// migration source's `if !node_name.is_empty()` produced.
		//
		// TASK-097 (D-3): the sibling that already carries the requested name is
		// looked up *before* the name is applied, because that lookup is what
		// tells the commit phase "the engine renamed this node because the name
		// was taken" apart from every other reason a name can move
		// (`Node::set_name()` also sanitises `/`, `:`, `@`, `.` and `"`).
		Node *name_conflict_with = nullptr;
		if (!requested_name.is_empty()) {
			name_conflict_with = _child_named(parent, requested_name);
			node->set_name(requested_name);
		}

		// Every property goes through the module's one property write. Its first
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
		prepared.requested_name = requested_name;
		prepared.name_conflict_with = name_conflict_with;
		const String actual_name = String(node->get_name());
		prepared.pending_path = _pending_path_for(parent_relative, actual_name);

		// TASK-051 C-3: in the new mode a duplicate path inside one request is a
		// conflict, not an engine rename. The second element would silently
		// become a node whose name is not the one it asked for, and a later
		// element naming that path could not tell the two apart.
		//
		// TASK-097 (D-3): from this task on, the **default** policy refuses that
		// shape too. Two elements of one request asking for the same path under
		// the same parent is the same duplicate-generation bug as a name the
		// scene already carries - the engine renames the second one to
		// `@Type@N`, and `editor_save_scene` writes both. The engine's own rename
		// is still reachable, but it has to be asked for twice: `on_name_conflict`
		// `"rename"` *and* `resolve_within_batch` (whose rule this was).
		if ((p_resolve_within_batch || refuse_name_conflicts) && !prepared.pending_path.is_empty()) {
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
	Array renamed;
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
		// TASK-097 (D-3): a name the engine moved is reported on the element it
		// happened to, so a `"rename"` call cannot be read as "the names I asked
		// for are the names I got".
		const String actual_name = String(prepared.node->get_name());
		if (!prepared.requested_name.is_empty() && actual_name != prepared.requested_name) {
			entry["requested_name"] = prepared.requested_name;
			entry["name_conflict"] = "renamed";
			Dictionary rename;
			rename["index"] = prepared.index;
			rename["requested_name"] = prepared.requested_name;
			rename["name"] = actual_name;
			rename["node_path"] = relative_path(p_root, prepared.node);
			if (prepared.name_conflict_with != nullptr) {
				entry["conflicting_node_path"] = relative_path(p_root, prepared.name_conflict_with);
				rename["conflicting_node_path"] = entry["conflicting_node_path"];
				// The record `editor_save_scene` reports from: this node exists
				// only because the name it asked for was taken.
				_NameConflictRecord record;
				record.scene_root = p_root->get_instance_id();
				record.added = prepared.node->get_instance_id();
				record.existing = prepared.name_conflict_with->get_instance_id();
				record.requested_name = prepared.requested_name;
				record.parent_path = prepared.requested_parent_path;
				record.added_path = relative_path(p_root, prepared.node);
				record.existing_path = relative_path(p_root, prepared.name_conflict_with);
				_batch_name_conflicts.push_back(record);
			}
			renamed.push_back(rename);
		}
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
	// TASK-097 (D-3): the name-conflict policy is echoed for the same reason, and
	// `renamed` / `renamed_count` make the auto-renames this call was allowed to
	// produce impossible to miss (an empty list means every requested name was
	// stored as asked).
	result["on_name_conflict"] = p_on_name_conflict;
	result["renamed"] = renamed;
	result["renamed_count"] = renamed.size();
	return result;
}

Array duplicate_name_conflicts_on(Node *p_root) {
	Array out;
	if (p_root == nullptr) {
		return out;
	}
	const ObjectID root_id = p_root->get_instance_id();
	for (int i = _batch_name_conflicts.size() - 1; i >= 0; i--) {
		const _NameConflictRecord &record = _batch_name_conflicts[i];
		if (record.scene_root != root_id) {
			continue;
		}
		Node *added = _name_conflict_instance(record.added);
		Node *existing = _name_conflict_instance(record.existing);
		// Stale records are dropped rather than reported: the answer describes
		// the tree in front of the caller, so a pair that is no longer a pair of
		// siblings under one parent (or whose nodes are gone) is not a duplicate
		// any more.
		if (added == nullptr || existing == nullptr || added->get_parent() == nullptr ||
				added->get_parent() != existing->get_parent()) {
			_batch_name_conflicts.remove_at(i);
			continue;
		}
		Dictionary entry;
		entry["requested_name"] = record.requested_name;
		entry["parent_path"] = relative_path(p_root, added->get_parent());
		entry["added_name"] = String(added->get_name());
		entry["added_path"] = relative_path(p_root, added);
		entry["existing_name"] = String(existing->get_name());
		entry["existing_path"] = relative_path(p_root, existing);
		entry["existing_type"] = existing->get_class();
		out.push_back(entry);
	}
	return out;
}

void forget_name_conflicts_for(Node *p_root) {
	if (p_root == nullptr) {
		_batch_name_conflicts.clear();
		return;
	}
	const ObjectID root_id = p_root->get_instance_id();
	for (int i = _batch_name_conflicts.size() - 1; i >= 0; i--) {
		if (_batch_name_conflicts[i].scene_root == root_id) {
			_batch_name_conflicts.remove_at(i);
		}
	}
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
//     missing parent or property, `-32000` for a name the target parent already
//     carries (TASK-097 D-3: the call is well formed and legal, the *state* is
//     what refuses it - the same reading `project_text_write.cpp` records for
//     "the destination exists and `overwrite` is false");
//   * `error.message` - a readable message naming the element index (and, for a
//     name conflict, every conflicting node path);
//   * `error.data.suggestion` - the rollback explanation (for a name conflict:
//     the two legal fixes, including `on_name_conflict: "rename"`);
//   * `error.data.conflicts` - only for a name conflict: one
//     `{index,type,requested_name,parent_path,node_path,existing_node_path,
//     existing_type}` per offending element;
//   * `error.data.on_name_conflict` - the policy the refusal was produced under;
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
	// TASK-097 (D-3): the name-conflict policy is read (and a present-but-wrong
	// value refused) *before* the editor guard, for the reason the mode above is:
	// a mistyped `on_name_conflict` must be a `-32602` in every process rather
	// than a `-32000` that hides it (PLAYBOOK section 6.2). The default is
	// `"refuse"`, so a caller that says nothing never gets the engine's silent
	// duplicate generation.
	String on_name_conflict = "refuse";
	if (!optional_string(p_args, "on_name_conflict", "refuse", on_name_conflict, r_error)) {
		return Variant();
	}
	if (on_name_conflict != "refuse" && on_name_conflict != "rename") {
		r_error = MCPToolError::invalid_params(vformat(
				"'on_name_conflict' must be \"refuse\" or \"rename\", got \"%s\"", on_name_conflict));
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
	return add_nodes_batch_on(root, nodes, r_error, resolve_within_batch, on_name_conflict);
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
		ToolBuilder builder("editor_add_nodes_batch", String::utf8(R"desc(批量添加节点到场景 默认在目标父节点下已存在同名子节点（或本批内同一父节点下重名）时整批拒绝，回 -32000，data.conflicts 列出冲突节点路径、data.suggestion 给出改法，一个节点都不写入——不会把新节点交给引擎改名后与既有节点一起留在场景里。确有需要时用 on_name_conflict="rename" 显式接受引擎改名，响应在 created[i].name_conflict / renamed_count / renamed[] 里说明哪些节点被改名；editor_save_scene 之后仍会报告这些由本模块批量添加产生的同名重复。)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"nodes":{"description":"节点数组，每个元素包含 type（必填）、parent_path、name、properties","items":{"properties":{"name":{"description":"节点名称","type":"string"},"parent_path":{"description":"父节点路径，默认 \".\"","type":"string"},"properties":{"description":"要设置的属性字典","type":"object"},"type":{"description":"节点类型","type":"string"}},"required":["type"],"type":"object"},"type":"array"},"on_name_conflict":{"default":"refuse","description":"同名冲突策略。默认 \"refuse\"：本批任一元素的 name 在目标父节点下已存在（或与本批更早元素在该父节点下重名）时整批拒绝、什么都不写入，回 -32000，data.conflicts 给出冲突节点路径清单，data.suggestion 给出改法——绝不把新节点交给引擎改名后与既有节点一起留在场景里（那正是 editor_save_scene 把整份副本写进 .tscn、副本绘制在真实节点上层的成因）。\"rename\" 是显式开关，保留引擎自己的重名改名行为（新节点成为 @Type@N），响应在 created[i].name_conflict=\"renamed\"、renamed_count 与 renamed[] 里说明哪些节点被改名，editor_save_scene 随后仍会报告这些由本模块批量添加产生的同名重复。","enum":["refuse","rename"],"type":"string"},"resolve_within_batch":{"default":false,"description":"为 true 时元素的 parent_path 可以指向**本批更早的元素**所创建的节点（同一个请求里建父子树）。父元素必须排在子元素之前，父路径指向更后面的元素会被拒绝（父/子循环在按数组顺序应用时就是这个形状）；同一父节点下、同一批内重名会被拒绝（默认 false 时保留引擎自己的重命名）——两种拒绝都仍然整批回滚。默认 false：父路径只按调用到达时的场景树解析，与旧行为逐字相同。响应在每个 created 元素上给出 parent_source（scene/batch），说明父节点来自场景树还是本批","type":"boolean"}},"required":["nodes"],"type":"object"})schema"));
		builder.handler(_tool_add_nodes_batch).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_node_property_batch", String::utf8(R"desc(批量设置同类型节点的属性)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"type":"object","properties":{"node_type":{"type":"string"},"property":{"type":"string"},"value":{}},"required":["node_type","property","value"]})schema"));
		builder.handler(_tool_set_node_property_batch).register_into(r_registry);
	}
}
