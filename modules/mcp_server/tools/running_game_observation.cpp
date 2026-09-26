/**************************************************************************/
/*  running_game_observation.cpp                                          */
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
#include "running_game_observation.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/object/object.h"
#include "core/object/script_language.h"
#include "core/templates/list.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/gui/control.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// running_game_observation - the six game-side observers of B2.
//
// Migration source (semantic reference, read-only): the game-process half of the
// batch lives in `addons/godot_mcp_rs/mcp_runtime_agent.gd`, which the Rust
// GDExtension forwards to over the `user://` file IPC
// (`godot_mcp_gdext/src/commands/runtime.rs:216-382`). Because the module now
// lives *inside* the game process, the IPC disappears and the tool answers
// directly from `SceneTree::get_current_scene()`.
//
// A second, fuller implementation of the same tools exists in the older pure
// GDScript addon (`addons/godot_mcp/mcp_game_inspector_service.gd`, read-only)
// and one editor-side shape exists in the Rust addon
// (`godot_mcp_gdext/src/commands/node.rs:232-266`). Where the two disagree, the
// choice is argued at the tool and recorded in REPORT-010's per-tool table; the
// three rules used are:
//
//   1. the node-property shape follows the *Rust* reference
//      (`{"node_path", "type", "properties": {...}}`, values through the
//      module's single `serialize_variant`), because a flat property dictionary
//      collides with the structural keys and because the module has exactly one
//      serializer;
//   2. a contract parameter that the migration source accepted but silently
//      ignored is implemented as documented instead of ignored
//      (`get_scene_tree`'s `script_filter` / `type_filter` / `named_only`, whose
//      intended semantics are visible in the fuller GDScript implementation and
//      in the contract's own description of the parameters) - PLAYBOOK section
//      6.6: behaviour is decided by "the tool really works";
//   3. a lookup failure is `-32001` with a suggestion (GDR-14 / PLAYBOOK section
//      6.1), not the migration source's silent empty answer.
//
// Shared decisions that are *not* per tool:
//
//   * argument validation happens before the scene guard, so a malformed call
//     is answered with the same `-32602` whether or not a game is running (the
//     order B1's `running_game_find_nearby_nodes` already established);
//   * every path parameter is resolved by `MCPTools::resolve_game_node` (the
//     migration source's `_find_node`, `mcp_runtime_agent.gd:690-714`, hoisted
//     by TASK-011) and the resolved
//     *absolute* path is what the answer echoes;
//   * all list answers are deterministic: the walks are pre-order over
//     `Node::get_child(i)` (insertion order), so the same scene produces byte
//     identical answers (PLAYBOOK section 6.8).
// ---------------------------------------------------------------------------

// The running game's current scene and its node resolution used to be
// file-private here (`_current_scene`, `_tree_root_node`, `_find_by_name`,
// `_resolve_node`). TASK-011 section 2 hoisted them, verbatim, into
// `tools/tool_helpers.{h,cpp}` (`MCPTools::game_current_scene`,
// `MCPTools::game_tree_root`, `MCPTools::resolve_game_node`), because the
// frame-observation group of the same batch has to resolve `node_path` exactly
// the same way and a group may not call another group's file-private helper
// (PLAYBOOK section 2.4). The wire evidence of both groups therefore describes
// one resolution rule, not two.

// An optional JSON array of strings. An absent key is an empty filter; a present
// key of the wrong shape is `-32602` (PLAYBOOK section 6.2), never a silent
// default. `p_qualifier` is the prefix of the message for an array nested in
// another argument (`nodes[0].`), so every message names the caller's own path.
static bool _optional_string_array(const Dictionary &p_args, const String &p_key, const String &p_qualifier, Vector<String> &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		return true;
	}
	if (value.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s%s' must be an array of strings, got %s",
				p_qualifier, p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	const Array array = value;
	for (int i = 0; i < array.size(); i++) {
		const Variant item = array[i];
		if (item.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter '%s%s[%d]' must be a string, got %s",
					p_qualifier, p_key, i, Variant::get_type_name(item.get_type())));
			return false;
		}
		r_out.push_back(item);
	}
	return true;
}

// ---------------------------------------------------------------------------
// TASK-040 D-3: the named-property read, exported.
//
// This is the verbatim body of the NAMED branch of `_read_properties` below,
// moved into a function of its own for the same reason the editor-side write
// helpers are exported: every tool that uses it needs a running game, and the
// doctest process has no `SceneTree` at all, so a tool-level case can only ever
// observe the `-32000` guard. The `properties` filter of
// `running_game_get_node_properties` (and of its batch, autoload and
// find-by-script siblings) is what a doctest *can* drive, and it is where the
// defect lives.
//
// The TASK-032 D3 rule is kept: a name that is only an inspector *label*
// (`PROPERTY_USAGE_GROUP / SUBGROUP / CATEGORY`, e.g. `Material`) is skipped
// rather than answered - it names a category, not a value, and answering it with
// `null` was the case-collision defect TASK-032 D3 removed. A name the node does
// not have at all is *not* the same thing, and is what step 2 refuses: the write
// side of this very endpoint already answers `-32001 Property '<name>' ... not
// found` (tools/running_game_node_write.cpp), and one endpoint may not answer
// "there is no such property" and "its value is null" for the same name.
// ---------------------------------------------------------------------------
namespace MCPTools {

bool read_named_properties(Node *p_node, const Vector<String> &p_names, Dictionary &r_out, MCPToolError &r_error) {
	// TASK-040 D-3, the second half of the red/green pair. The gate is
	// `object_has_property` - the same question the write side of this endpoint
	// asks before it writes (`prepare_node_property_value`,
	// tools/running_game_node_write.cpp) - so the two sides can no longer answer
	// "there is no such property" and "its value is null" for the same name.
	List<PropertyInfo> named_list;
	p_node->get_property_list(&named_list);
	Vector<String> named_labels;
	for (const PropertyInfo &property : named_list) {
		if (property_is_label(property)) {
			named_labels.push_back(String(property.name));
		}
	}
	for (int i = 0; i < p_names.size(); i++) {
		const String &name = p_names[i];
		if (named_labels.has(name)) {
			continue;
		}
		if (dictionary_has_key_ignoring_case(r_out, name)) {
			continue;
		}
		if (!object_has_property(p_node, StringName(name))) {
			r_error = MCPToolError::not_found(
					vformat("Property '%s' on node '%s'", name, wire_node_path(p_node)),
					"Call running_game_get_node_properties without 'properties' to list every property this node has, or "
					"running_game_get_node_signals for its signals");
			return false;
		}
		r_out[name] = serialize_variant(p_node->get(name));
	}
	return true;
}

} // namespace MCPTools

// Which properties a read answers with.
enum class PropertySelection {
	// Every property a game inspector wants: `PROPERTY_USAGE_EDITOR` *or*
	// `PROPERTY_USAGE_SCRIPT_VARIABLE`, skipping the `_`-prefixed internals and
	// the `script` slot.
	//
	// The first version of this filter used `PROPERTY_USAGE_EDITOR` alone, which
	// silently dropped a node's script variables - in Godot 4 a plain `var x` is
	// in the property list with `PROPERTY_USAGE_SCRIPT_VARIABLE` and *not* with
	// EDITOR unless it is `@export`ed. The wire evidence caught it: the
	// all-properties read of the scratch `Player` listed 27 engine properties and
	// no `moved_frames` (REPORT-010 section 5). Excluding `_`-prefixed names and
	// `script` keeps the engine's internals out, exactly like the Rust reference
	// (node.rs:256), and neither the category entries nor the group entries have
	// either usage bit, so they stay out as well - spelled out through the shared
	// `property_is_label()` since TASK-032 D3.
	EDITOR_OR_SCRIPT,
	// Exactly the caller's `properties` list, in the caller's order.
	NAMED,
	// Nothing (`properties` absent): the answer stays a node summary. Used by
	// the tools whose contract does not say "all properties when absent".
	NONE,
};

// Fills `r_out` with the requested properties, each value through the module's
// single serializer (`serialize_variant`), so an engine type (Vector2, Color,
// Object, ...) never reaches `JSON::stringify` raw.
//
// TASK-032 D3 (the same-family check of `running_game_get_node_properties`):
// * the enumeration path never let a label through - it tests the engine's three
//   label bits through `property_is_label()` (a group or category entry carries
//   one of them; measured on the wire: the game-side listing of a `Node2D` has no
//   `Material` key, the editor-side one had it);
// * the *named* path used to answer a label name with a fake `null`
//   (`{"Material": null}`), because `Object::get()` of a label is `nil`; it is
//   now skipped, so `properties: ["Material", "material"]` can no longer produce
//   two keys that differ only by case (the package a case-insensitive client
//   refuses). TASK-040 D-3 changed the other half of that sentence: a name the
//   node does not have **at all** used to answer `null` next to a success; it is
//   now the `-32001` the write side of this same endpoint has always answered
//   (see `MCPTools::read_named_properties`), so one endpoint can no longer hold
//   two opposite opinions about one name.
//
// TASK-033 D-M4e-2: the enumeration no longer requires the inspector-visibility
// bits, so this reader answers the same set as `editor_get_node_properties` for
// the same node (the reasoning is on the loop itself, below).
static bool _read_properties(Node *p_node, const Vector<String> &p_filter, PropertySelection p_selection, Dictionary &r_out, MCPToolError &r_error) {
	if (p_selection == PropertySelection::NONE) {
		return true;
	}
	if (p_selection == PropertySelection::NAMED) {
		// TASK-040 D-3: the named path is `MCPTools::read_named_properties`
		// (exported so a doctest can pin it - this file's tools need a running
		// game and the doctest process has no `SceneTree`). The call keeps the
		// TASK-032 D3 label rule and, in step 2 of the red/green pair, turns a
		// name the node does not have into the same refusal the write side of
		// this endpoint already answers.
		return read_named_properties(p_node, p_filter, r_out, r_error);
	}
	List<PropertyInfo> property_list;
	p_node->get_property_list(&property_list);
	// TASK-033 (D-M4e-2): the unfiltered path answers **every** property of the
	// node, which is what the contract says ("不传则返回所有属性") and what the
	// engine's own `Object::get_property_list()` means by a property list.
	//
	// Until this batch the loop additionally required
	// `PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE`. Both bits are
	// *inspector visibility* flags, not property-existence flags
	// (`object.h`: PROPERTY_USAGE_EDITOR - "the property is shown in the Editor
	// Inspector"; PROPERTY_USAGE_SCRIPT_VARIABLE - "the property is a script
	// variable which should be serialized and shown in the editor"), so the answer
	// was a 27-of-42 subset of a `Node2D` while the same family's editor-side read
	// (`editor_get_node_properties`, `editor_node_read.cpp:185-231`) answers all 42
	// - two tools with the same name and two different answers for the same node.
	// The M4e re-audit recorded that as a description/behaviour mismatch
	// (D-M4e-2) and as an ergonomics defect: a caller cannot predict which of the
	// two enumerations it will get. The narrower set was also the *migration
	// source's* rule (`mcp_game_inspector_service.gd:271`), i.e. a quirk rather
	// than an engine fact, and GDR-23 section 21.6 does not keep a quirk that buys
	// nothing.
	//
	// What is *not* widened is the shape rule: the same four skips as the editor
	// family above - empty names, `_`-prefixed internals, the attached `script`,
	// and the inspector's own group/category **labels** (which carry no value and
	// whose `Material` entry collides with the real `material` property under a
	// case-insensitive client).
	for (const PropertyInfo &property : property_list) {
		const String name = property.name;
		if (name.is_empty() || name.begins_with("_") || name == "script") {
			continue;
		}
		if (property_is_label(property)) {
			continue;
		}
		if (dictionary_has_key_ignoring_case(r_out, name)) {
			continue;
		}
		r_out[name] = serialize_variant(p_node->get(name));
	}
	return true;
}

// The summary of one node, shared by the tree and every finder, so all of them
// use the same three keys (plus `script` when one is attached).
static Dictionary _node_entry(Node *p_node) {
	Dictionary entry;
	entry["name"] = String(p_node->get_name());
	entry["type"] = p_node->get_class();
	entry["path"] = String(p_node->get_path());
	const Variant script = p_node->get_script();
	if (script.get_type() == Variant::OBJECT) {
		const Ref<Script> attached = script;
		if (attached.is_valid()) {
			entry["script"] = String(attached->get_path());
		}
	}
	return entry;
}

// The unfiltered tree, exactly the reference's `_build_node_tree`: the node's
// own keys always, `children` only when the depth allows *and* the array is
// non-empty (an empty `children` key is never emitted).
static Dictionary _build_tree(Node *p_node, int p_max_depth, int p_depth) {
	Dictionary entry = _node_entry(p_node);
	if (p_max_depth == -1 || p_depth < p_max_depth) {
		Array children;
		const int child_count = p_node->get_child_count();
		for (int i = 0; i < child_count; i++) {
			children.push_back(_build_tree(p_node->get_child(i), p_max_depth, p_depth + 1));
		}
		if (!children.is_empty()) {
			entry["children"] = children;
		}
	}
	return entry;
}

// Whether one node satisfies the three filters. `named_only` skips the nodes
// with an auto-generated name - Godot prefixes those with `@` (the fuller
// GDScript implementation's rule, mcp_game_inspector_service.gd:238); the
// script filter is a case insensitive substring test on the attached script's
// resource path and rejects a node without a script.
static bool _node_matches(Node *p_node, const String &p_script_filter, const String &p_type_filter, bool p_named_only) {
	if (p_named_only && String(p_node->get_name()).begins_with("@")) {
		return false;
	}
	if (!p_type_filter.is_empty() && !p_node->is_class(p_type_filter)) {
		return false;
	}
	if (!p_script_filter.is_empty()) {
		const Variant script = p_node->get_script();
		if (script.get_type() != Variant::OBJECT) {
			return false;
		}
		const Ref<Script> attached = script;
		if (attached.is_null() || !String(attached->get_path()).to_lower().contains(p_script_filter.to_lower())) {
			return false;
		}
	}
	return true;
}

// The filtered tree: a node is kept when it matches *or* when any descendant
// matches (so the answer still shows where a match lives), which is the fuller
// GDScript implementation's `_build_filtered_node_tree`
// (mcp_game_inspector_service.gd:205-234). A subtree without a match answers
// nil, and the caller turns "the root is nil" into the documented
// `{"tree": null, "message": ...}`.
static Variant _build_filtered_tree(Node *p_node, int p_max_depth, int p_depth, const String &p_script_filter, const String &p_type_filter, bool p_named_only) {
	const bool matches = _node_matches(p_node, p_script_filter, p_type_filter, p_named_only);

	Array matched_children;
	if (p_max_depth == -1 || p_depth < p_max_depth) {
		const int child_count = p_node->get_child_count();
		for (int i = 0; i < child_count; i++) {
			const Variant child = _build_filtered_tree(p_node->get_child(i), p_max_depth, p_depth + 1,
					p_script_filter, p_type_filter, p_named_only);
			if (child.get_type() != Variant::NIL) {
				matched_children.push_back(child);
			}
		}
	}

	if (!matches && matched_children.is_empty()) {
		return Variant();
	}

	Dictionary entry = _node_entry(p_node);
	if (!matched_children.is_empty()) {
		entry["children"] = matched_children;
	}
	return entry;
}

// `max_depth` arrives as a JSON number; the depth comparison is an `int`, so the
// value is clamped into the int range before it is used (a client may send
// 1e18, which is integral and therefore accepted by `optional_int`).
static int _depth_limit(int64_t p_max_depth) {
	static const int64_t INT_MAX_64 = 2147483647;
	static const int64_t INT_MIN_64 = -2147483648;
	if (p_max_depth > INT_MAX_64) {
		return (int)INT_MAX_64;
	}
	if (p_max_depth < INT_MIN_64) {
		return (int)INT_MIN_64;
	}
	return (int)p_max_depth;
}

// ---------------------------------------------------------------------------
// running_game_get_scene_tree (old `get_game_scene_tree`)
//
// Observable contract (as implemented):
//   * `max_depth` (integer, default -1 = unlimited; children are emitted only
//     while `depth < max_depth`, so 0 is the root alone), `script_filter`
//     (string), `type_filter` (string), `named_only` (boolean, default false);
//   * no filter -> `{"tree": <node>}`, where `<node>` is
//     `{name, type, path, script?, children?}` and `children` is omitted when
//     empty or when the depth limit was reached;
//   * with a filter -> the same tree pruned to the nodes that match or that have
//     a matching descendant; no match at all -> `{"tree": null, "message": "No
//     nodes matched the filter"}`;
//   * no running scene -> `-32000` (`no_scene`), mistyped parameters -> `-32602`.
//
// The migration source forwards all four parameters but only `max_depth` reaches
// its tree builder (`mcp_runtime_agent.gd:82-107`), so the three filters were
// silently ignored; the semantics implemented here are the documented ones (the
// contract's own parameter descriptions and the fuller GDScript implementation).
// See the file header, rule 2.
// ---------------------------------------------------------------------------
static Variant _tool_get_scene_tree(const Dictionary &p_args, MCPToolError &r_error) {
	int64_t max_depth = -1;
	if (!optional_int(p_args, "max_depth", -1, max_depth, r_error)) {
		return Variant();
	}
	String script_filter;
	if (!optional_string(p_args, "script_filter", String(), script_filter, r_error)) {
		return Variant();
	}
	String type_filter;
	if (!optional_string(p_args, "type_filter", String(), type_filter, r_error)) {
		return Variant();
	}
	bool named_only = false;
	if (!optional_bool(p_args, "named_only", false, named_only, r_error)) {
		return Variant();
	}

	Node *root = nullptr;
	SceneTree *tree = nullptr;
	if (!game_current_scene(root, tree, r_error)) {
		return Variant();
	}

	const int depth_limit = _depth_limit(max_depth);
	const bool filtered = !script_filter.is_empty() || !type_filter.is_empty() || named_only;

	Dictionary result;
	if (!filtered) {
		result["tree"] = _build_tree(root, depth_limit, 0);
		return result;
	}

	const Variant filtered_tree = _build_filtered_tree(root, depth_limit, 0, script_filter, type_filter, named_only);
	if (filtered_tree.get_type() == Variant::NIL) {
		result["tree"] = Variant();
		result["message"] = "No nodes matched the filter";
	} else {
		result["tree"] = filtered_tree;
	}
	return result;
}

// ---------------------------------------------------------------------------
// running_game_get_node_properties (old `get_game_node_properties`)
//
// Observable contract (as implemented):
//   * `node_path` (string, required), `properties` (array of strings, optional);
//   * a node is resolved by `MCPTools::resolve_game_node` (root for ""/"." ,
//     absolute for
//     `/root/...`, relative otherwise, then a by-name search);
//   * the answer is `{"node_path": <absolute path>, "type": <class>,
//     "properties": {...}}`; every value goes through `serialize_variant`;
//   * an absent or empty `properties` list answers every editor-visible property
//     and every script variable (skipping `_`-prefixed names and `script`),
//     which is what the contract says ("不传则返回所有属性");
//   * an unknown node -> `-32001` with a suggestion, no running scene ->
//     `-32000`, missing/mistyped parameters -> `-32602`.
//
// The migration source's shape is flat (it writes each property next to
// `node_path`/`type`/`name`, mcp_runtime_agent.gd:114-135) and its "all
// properties" branch iterates `get_property_list()` unfiltered. The nested shape
// and the usage filter follow the Rust editor-side reference (node.rs:232-266)
// and the fuller GDScript implementation, so the whole port has one property
// vocabulary. REPORT-010 records the divergence, including the dropped `name`
// key (the resolved path already carries it).
// ---------------------------------------------------------------------------
static Variant _tool_get_node_properties(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	Vector<String> filter;
	if (!_optional_string_array(p_args, "properties", String(), filter, r_error)) {
		return Variant();
	}

	Node *root = nullptr;
	SceneTree *tree = nullptr;
	if (!game_current_scene(root, tree, r_error)) {
		return Variant();
	}

	Node *node = resolve_game_node(tree, root, node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", node_path),
				"Use running_game_get_scene_tree to list the nodes of the running scene");
		return Variant();
	}

	Dictionary properties;
	// TASK-040 D-3: a name the node does not have fails the whole call with the
	// write side's own `-32001` shape, so this endpoint has one answer per name.
	if (!_read_properties(node, filter, filter.is_empty() ? PropertySelection::EDITOR_OR_SCRIPT : PropertySelection::NAMED, properties, r_error)) {
		return Variant();
	}

	Dictionary result;
	result["node_path"] = String(node->get_path());
	result["type"] = node->get_class();
	result["properties"] = properties;
	return result;
}

// ---------------------------------------------------------------------------
// running_game_get_node_properties_batch (old `batch_get_properties`)
//
// Observable contract (as implemented):
//   * `nodes` (array, required) of `{node_path (string, required), properties
//     (array of strings, optional)} objects;
//   * `{"results": [...], "count": N}` in the caller's order; each entry is the
//     single-node shape, or `{"node_path": <as asked>, "error": "Node not
//     found: <path>"}` when that one node is gone - one missing node never fails
//     the whole call (the migration source's per-item error entry,
//     mcp_runtime_agent.gd:384-402);
//   * TASK-040 D-3: an item naming a property its node does not have answers
//     `{"node_path": <resolved>, "error": "Property '...' ... not found"}` for
//     that item only - the same per-item granularity, and the same rule the
//     single-node read now answers with a whole-call `-32001`;
//   * a malformed *request* is still `-32602` (an item that is not an object, an
//     item without `node_path`, a mistyped `properties`), and it is answered
//     before any node is read, so a bad request never half-answers;
//   * no running scene -> `-32000`.
// ---------------------------------------------------------------------------
static Variant _tool_get_node_properties_batch(const Dictionary &p_args, MCPToolError &r_error) {
	const Variant nodes_value = p_args.get("nodes", Variant());
	if (nodes_value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter: nodes");
		return Variant();
	}
	if (nodes_value.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'nodes' must be an array, got %s",
				Variant::get_type_name(nodes_value.get_type())));
		return Variant();
	}

	const Array nodes = nodes_value;
	Vector<String> paths;
	Vector<Vector<String>> filters;
	for (int i = 0; i < nodes.size(); i++) {
		const Variant item = nodes[i];
		if (item.get_type() != Variant::DICTIONARY) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'nodes[%d]' must be an object, got %s",
					i, Variant::get_type_name(item.get_type())));
			return Variant();
		}
		const Dictionary entry = item;
		const Variant path_value = entry.get("node_path", Variant());
		if (path_value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'nodes[%d].node_path' must be a string, got %s",
					i, Variant::get_type_name(path_value.get_type())));
			return Variant();
		}
		Vector<String> filter;
		if (!_optional_string_array(entry, "properties", vformat("nodes[%d].", i), filter, r_error)) {
			return Variant();
		}
		paths.push_back(path_value);
		filters.push_back(filter);
	}

	Node *root = nullptr;
	SceneTree *tree = nullptr;
	if (!game_current_scene(root, tree, r_error)) {
		return Variant();
	}

	Array results;
	for (int i = 0; i < paths.size(); i++) {
		Node *node = resolve_game_node(tree, root, paths[i]);
		if (node == nullptr) {
			Dictionary missing;
			missing["node_path"] = paths[i];
			missing["error"] = "Node not found: " + paths[i];
			results.push_back(missing);
			continue;
		}
		Dictionary properties;
		MCPToolError read_error;
		// TASK-040 D-3: the batch keeps its per-item granularity - one node the
		// caller named with a property the node does not have answers an `error`
		// entry for *that* item (the same shape the missing-node branch above
		// uses), and the other items are still answered.
		if (!_read_properties(node, filters[i], filters[i].is_empty() ? PropertySelection::EDITOR_OR_SCRIPT : PropertySelection::NAMED, properties, read_error)) {
			Dictionary failed;
			failed["node_path"] = String(node->get_path());
			failed["error"] = read_error.message;
			results.push_back(failed);
			continue;
		}
		Dictionary entry;
		entry["node_path"] = String(node->get_path());
		entry["type"] = node->get_class();
		entry["properties"] = properties;
		results.push_back(entry);
	}

	Dictionary result;
	result["results"] = results;
	result["count"] = results.size();
	return result;
}

// ---------------------------------------------------------------------------
// running_game_get_autoload_node (old `get_autoload`)
//
// Observable contract (as implemented):
//   * `name` (string, required; empty/blank is `-32602`), `properties` (array of
//     strings, optional);
//   * the node is `/root/<name>` from the *SceneTree root*, which is where an
//     autoload lives - the current scene is deliberately not required, exactly
//     like the reference (`mcp_runtime_agent.gd:364-377`), so this tool answers
//     in a running game whose current scene has been cleared and refuses with
//     `-32000` only when there is no SceneTree at all;
//   * the answer is `{"name": <as asked>, "path": <absolute path>, "type":
//     <class>}` plus `"properties"` *only when* the caller asked for some - the
//     contract's `properties` is a list of properties to fetch, not an
//     "all when absent" switch (unlike `running_game_get_node_properties`, whose
//     contract says so explicitly);
//   * an unknown autoload -> `-32001` with a suggestion.
// ---------------------------------------------------------------------------
static Variant _tool_get_autoload_node(const Dictionary &p_args, MCPToolError &r_error) {
	String name;
	if (!require_string(p_args, "name", name, r_error)) {
		return Variant();
	}
	if (name.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'name' must not be empty");
		return Variant();
	}
	Vector<String> filter;
	if (!_optional_string_array(p_args, "properties", String(), filter, r_error)) {
		return Variant();
	}

	SceneTree *tree = SceneTree::get_singleton();
	Node *tree_root = game_tree_root(tree);
	if (tree_root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}

	Node *node = tree_root->get_node_or_null(NodePath("/root/" + name));
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Autoload '%s'", name),
				"Check the [autoload] section of project.godot for the exact name");
		return Variant();
	}

	Dictionary result;
	result["name"] = name;
	result["path"] = String(node->get_path());
	result["type"] = node->get_class();
	if (!filter.is_empty()) {
		Dictionary properties;
		// TASK-040 D-3: same rule as the single-node read (this is the same
		// `properties` filter one call away).
		if (!_read_properties(node, filter, PropertySelection::NAMED, properties, r_error)) {
			return Variant();
		}
		result["properties"] = properties;
	}
	return result;
}

// ---------------------------------------------------------------------------
// running_game_find_nodes_by_script (old `find_nodes_by_script`)
//
// Observable contract (as implemented):
//   * `script` (string, required; empty/blank is `-32602`), `properties` (array
//     of strings, optional);
//   * the current scene is walked depth-first pre-order and a node is kept when
//     its attached script's resource path is **exactly** `script`;
//   * `{"nodes": [{name, path, type, properties?}], "count": N}`, where
//     `properties` is present only when the caller asked for some;
//   * no running scene -> `-32000`.
//
// The exact match (case sensitive) is the reference's rule
// (`mcp_runtime_agent.gd:348-357`: `script.resource_path == script_path`); the
// fuller GDScript implementation used a case insensitive substring test, which
// would make `res://enemy.gd` also find a node running `res://boss_enemy.gd`.
// The contract's own description ("脚本路径（如 res://enemy.gd）") is an exact
// path, so exactness is what is implemented; REPORT-010 records the choice.
// ---------------------------------------------------------------------------
static Variant _tool_find_nodes_by_script(const Dictionary &p_args, MCPToolError &r_error) {
	String script_path;
	if (!require_string(p_args, "script", script_path, r_error)) {
		return Variant();
	}
	if (script_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'script' must not be empty");
		return Variant();
	}
	Vector<String> filter;
	if (!_optional_string_array(p_args, "properties", String(), filter, r_error)) {
		return Variant();
	}

	Node *root = nullptr;
	SceneTree *tree = nullptr;
	if (!game_current_scene(root, tree, r_error)) {
		return Variant();
	}

	// An explicit stack instead of recursion: a deeply nested scene must not be
	// able to overflow the C++ call stack, and pre-order is preserved by
	// pushing the children in reverse.
	Array nodes;
	Vector<Node *> pending;
	pending.push_back(root);
	while (!pending.is_empty()) {
		Node *node = pending[pending.size() - 1];
		pending.remove_at(pending.size() - 1);

		const Variant script = node->get_script();
		if (script.get_type() == Variant::OBJECT) {
			const Ref<Script> attached = script;
			if (attached.is_valid() && String(attached->get_path()) == script_path) {
				Dictionary entry = _node_entry(node);
				if (!filter.is_empty()) {
					Dictionary properties;
					// TASK-040 D-3: the same rule as the single-node read.
					if (!_read_properties(node, filter, PropertySelection::NAMED, properties, r_error)) {
						return Variant();
					}
					entry["properties"] = properties;
				}
				nodes.push_back(entry);
			}
		}

		const int child_count = node->get_child_count();
		for (int i = child_count - 1; i >= 0; i--) {
			pending.push_back(node->get_child(i));
		}
	}

	Dictionary result;
	result["nodes"] = nodes;
	result["count"] = nodes.size();
	return result;
}

// ---------------------------------------------------------------------------
// running_game_find_ui_elements (old `find_ui_elements`)
//
// Observable contract (as implemented):
//   * `type_filter` (string, optional);
//   * the current scene is walked pre-order and every `Control` is kept whose
//     class is `type_filter` (or every `Control` when no filter is given), so a
//     filter of `Button` matches a `Button` *and* its subclasses
//     (`Node::is_class`, the reference's `node.is_class(type_filter)`);
//   * `{"elements": [{name, path, type}], "count": N}`;
//   * no running scene -> `-32000`.
// ---------------------------------------------------------------------------
static Variant _tool_find_ui_elements(const Dictionary &p_args, MCPToolError &r_error) {
	String type_filter;
	if (!optional_string(p_args, "type_filter", String(), type_filter, r_error)) {
		return Variant();
	}

	Node *root = nullptr;
	SceneTree *tree = nullptr;
	if (!game_current_scene(root, tree, r_error)) {
		return Variant();
	}

	Array elements;
	Vector<Node *> pending;
	pending.push_back(root);
	while (!pending.is_empty()) {
		Node *node = pending[pending.size() - 1];
		pending.remove_at(pending.size() - 1);

		if (Object::cast_to<Control>(node) != nullptr && (type_filter.is_empty() || node->is_class(type_filter))) {
			elements.push_back(_node_entry(node));
		}

		const int child_count = node->get_child_count();
		for (int i = child_count - 1; i >= 0; i--) {
			pending.push_back(node->get_child(i));
		}
	}

	Dictionary result;
	result["elements"] = elements;
	result["count"] = elements.size();
	return result;
}

// ---------------------------------------------------------------------------
// Registration
//
// Order follows docs/tool-groups-b2.json. Every declaration comes from
// docs/tool-rename-map.json (`channel = running_game`, `scope = game`,
// `mutating = false`); the description and the `inputSchema` are a byte-exact
// copy of the entries of docs/tools_list.renamed.json, emitted from that file by
// `scripts/gen_b2_game_schema.py` and not retyped; re-running that script
// reproduces this block byte for byte.
// ---------------------------------------------------------------------------

void register_running_game_observation_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("running_game_get_scene_tree", String::utf8("获取运行中游戏的场景树结构"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("default")] = -1;
		v1[String::utf8("description")] = String::utf8("最大遍历深度，-1 表示无限");
		v1[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("max_depth")] = v1;
		Dictionary v2;
		v2[String::utf8("default")] = false;
		v2[String::utf8("description")] = String::utf8("是否只返回有名称的节点");
		v2[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("named_only")] = v2;
		Dictionary v3;
		v3[String::utf8("description")] = String::utf8("按脚本路径过滤节点");
		v3[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("script_filter")] = v3;
		Dictionary v4;
		v4[String::utf8("description")] = String::utf8("按节点类型过滤（如 Node2D, Control）");
		v4[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("type_filter")] = v4;
		schema[String::utf8("properties")] = v0;
		Array v5;
		schema[String::utf8("required")] = v5;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("get").scope(MCPToolScope::GAME).mutating(false).schema(schema).handler(_tool_get_scene_tree);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_get_node_properties", String::utf8("获取运行中游戏指定节点的属性"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("节点路径（相对于场景根节点）");
		v1[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("node_path")] = v1;
		Dictionary v2;
		v2[String::utf8("description")] = String::utf8("要获取的属性列表（可选，不传则返回所有属性）");
		Dictionary v3;
		v3[String::utf8("type")] = String::utf8("string");
		v2[String::utf8("items")] = v3;
		v2[String::utf8("type")] = String::utf8("array");
		v0[String::utf8("properties")] = v2;
		schema[String::utf8("properties")] = v0;
		Array v4;
		v4.push_back(String::utf8("node_path"));
		schema[String::utf8("required")] = v4;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("get").scope(MCPToolScope::GAME).mutating(false).schema(schema).handler(_tool_get_node_properties);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_get_node_properties_batch", String::utf8("批量获取多个节点的属性"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("节点信息数组，每个元素包含 node_path 和可选的 properties");
		Dictionary v2;
		Dictionary v3;
		Dictionary v4;
		v4[String::utf8("description")] = String::utf8("节点路径");
		v4[String::utf8("type")] = String::utf8("string");
		v3[String::utf8("node_path")] = v4;
		Dictionary v5;
		v5[String::utf8("description")] = String::utf8("需要获取的属性");
		Dictionary v6;
		v6[String::utf8("type")] = String::utf8("string");
		v5[String::utf8("items")] = v6;
		v5[String::utf8("type")] = String::utf8("array");
		v3[String::utf8("properties")] = v5;
		v2[String::utf8("properties")] = v3;
		Array v7;
		v7.push_back(String::utf8("node_path"));
		v2[String::utf8("required")] = v7;
		v2[String::utf8("type")] = String::utf8("object");
		v1[String::utf8("items")] = v2;
		v1[String::utf8("type")] = String::utf8("array");
		v0[String::utf8("nodes")] = v1;
		schema[String::utf8("properties")] = v0;
		Array v8;
		v8.push_back(String::utf8("nodes"));
		schema[String::utf8("required")] = v8;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("get").scope(MCPToolScope::GAME).mutating(false).schema(schema).handler(_tool_get_node_properties_batch);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_get_autoload_node", String::utf8("获取自动加载节点的信息"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("自动加载节点名称");
		v1[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("name")] = v1;
		Dictionary v2;
		v2[String::utf8("description")] = String::utf8("需要获取的属性列表");
		Dictionary v3;
		v3[String::utf8("type")] = String::utf8("string");
		v2[String::utf8("items")] = v3;
		v2[String::utf8("type")] = String::utf8("array");
		v0[String::utf8("properties")] = v2;
		schema[String::utf8("properties")] = v0;
		Array v4;
		v4.push_back(String::utf8("name"));
		schema[String::utf8("required")] = v4;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("get").scope(MCPToolScope::GAME).mutating(false).schema(schema).handler(_tool_get_autoload_node);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_find_nodes_by_script", String::utf8("在运行中的游戏中按脚本路径查找节点"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("需要同时获取的属性列表");
		Dictionary v2;
		v2[String::utf8("type")] = String::utf8("string");
		v1[String::utf8("items")] = v2;
		v1[String::utf8("type")] = String::utf8("array");
		v0[String::utf8("properties")] = v1;
		Dictionary v3;
		v3[String::utf8("description")] = String::utf8("脚本路径（如 res://enemy.gd）");
		v3[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("script")] = v3;
		schema[String::utf8("properties")] = v0;
		Array v4;
		v4.push_back(String::utf8("script"));
		schema[String::utf8("required")] = v4;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("find").scope(MCPToolScope::GAME).mutating(false).schema(schema).handler(_tool_find_nodes_by_script);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_find_ui_elements", String::utf8("查找运行中游戏的所有 UI 元素"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("按控件类型过滤（如 Button, Label）");
		v1[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("type_filter")] = v1;
		schema[String::utf8("properties")] = v0;
		Array v2;
		schema[String::utf8("required")] = v2;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("find").scope(MCPToolScope::GAME).mutating(false).schema(schema).handler(_tool_find_ui_elements);
		builder.register_into(r_registry);
	}
	// END generated
}
