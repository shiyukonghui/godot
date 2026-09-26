/**************************************************************************/
/*  running_game_read_scene.cpp                                           */
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
#include "running_game_read_scene.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/object/object.h"
#include "core/string/string_name.h"
#include "core/templates/sort_array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// running_game_find_nearby_nodes (old `find_nearby_nodes`)
//
// Migration source: `addons/godot_mcp_rs/mcp_runtime_agent.gd:501-546`, the
// game-process half of `godot_mcp_gdext/src/commands/runtime.rs:413` (the Rust
// file only forwards the arguments over IPC and never touches a node tree).
//
// Observable contract (as implemented):
//   * `position` (object, required), `radius` (number, default 100.0),
//     `type_filter` (string, default ""), `group_filter` (string, default ""),
//     `max_results` (integer, default 50);
//   * the tree is the *running game's current scene*
//     (`SceneTree::get_current_scene()`), walked depth-first pre-order with the
//     root included;
//   * a kept node is `{name, path, type, distance}` where `path` is the absolute
//     path (`str(node.get_path())` of the reference) and `distance` is measured
//     from `position`;
//   * the result is `{nodes: [...], count: N}`, ascending by distance, at most
//     `max_results` entries.
//
// Deliberate differences from the migration source, all of them forced by the
// module's contract (GDR-14 / GDR-16 / GDR-18) or by determinism:
//
//   1. a present parameter of the wrong type is `-32602`, never silently
//      coerced. The reference's `params.get("position", {})` turned
//      `position: 5` into an empty dictionary, and `radius: "big"` became
//      `float("big")` -> 0.0 in the typed assignment; PLAYBOOK section 6 item 2
//      accepts the stricter rule.
//   2. the reference stops the walk as soon as `max_results` nodes were
//      *discovered* (`if results.size() >= max_results: return`), so it returns
//      the first N in pre-order, not the N nearest. This implementation collects
//      the whole candidate set, sorts it and then truncates, which is what the
//      contract says ("最大的返回结果数" over a distance-sorted list) and what
//      makes the boundary/`max_results` evidence verifiable. `max_results <= 0`
//      still yields `{"nodes": [], "count": 0}`, matching the reference's
//      short-circuit.
//   3. the result order is deterministic. The reference's `sort_custom` is not
//      stable, so equal distances could come out in any order (PLAYBOOK section
//      6 item 8); here the comparison key is `(distance, pre-order index)`,
//      which is a total order.
// ---------------------------------------------------------------------------

// A candidate plus the pre-order index that makes ties deterministic. The
// payload is the exact dictionary that goes on the wire, so nothing is
// re-serialised after the sort.
struct NearbyCandidate {
	Dictionary entry;
	double distance = 0.0;
	int discovery_index = 0;
};

// Ascending distance, ties broken by the pre-order discovery index. A total
// order, so the result does not depend on the sort algorithm's stability.
struct NearbyCandidateLess {
	bool operator()(const NearbyCandidate &p_a, const NearbyCandidate &p_b) const {
		if (p_a.distance != p_b.distance) {
			return p_a.distance < p_b.distance;
		}
		return p_a.discovery_index < p_b.discovery_index;
	}
};

// An optional JSON number is `MCPTools::optional_float` (`tools/tool_helpers.*`):
// `NIL` means the key was absent (or explicitly null) and takes the default;
// anything that is neither a float nor an int is `-32602`. The repair pass hoisted
// this file's copy as well - it was a fifth byte-identical spelling of the same
// five lines (the D3 list named the other four).

// One component of `position`: an absent component is `0.0`, a present one that
// is not a number is `-32602` (same rule as `_optional_number`, different key
// spelling in the message).
static bool _position_component(const Dictionary &p_position, const String &p_component, double &r_out, MCPToolError &r_error) {
	const Variant value = p_position.get(p_component, Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = 0.0;
		return true;
	}
	if (value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'position.%s' must be a number, got %s",
				p_component, Variant::get_type_name(value.get_type())));
		return false;
	}
	r_out = (double)value;
	return true;
}

// The 2D position this implementation measures for a node, and a deliberate
// divergence from the reference.
//
// `global_position` is preferred over `position`, both through the property
// system, and only a real `Vector2` counts as a hit: a `Node3D` has both
// properties, but as a `Vector3` - such a node is therefore measured at the
// origin, and so is a node with neither property.
//
// The reference's `_find_nearby_recursive`
// (addons/godot_mcp_rs/mcp_runtime_agent.gd:535-539) is:
//
//     var node_pos := Vector2.ZERO
//     if "global_position" in node:
//         node_pos = node.global_position
//     elif "position" in node:
//         node_pos = node.position
//
// A `Node3D` *does* have `global_position`, so that branch is taken, the value is
// a `Vector3`, and the assignment into the typed `Vector2` binding raises a loud
// runtime error - `Trying to assign value of type 'Vector3' to a variable of type
// 'Vector2'`. That error aborts only the frame that raised it, and therefore that
// node's own whole subtree (its child loop never runs); the caller's child loop
// continues, so the reference still walks and answers every other node in the
// tree and merely *omits* the `Node3D` together with its descendants. Measured by
// replicating those three lines verbatim over a root whose children are A
// (`Node2D`), N3 (`Node3D` with a `Node2D` child) and Z (`Node2D`, visited after
// N3): the error is printed, Z is still visited, and the answer is `[Root, A, Z]`
// - the `Node3D` and its child are the only omissions.
//
// This implementation instead measures such a node at `(0,0)` and keeps walking,
// so it *includes* a `Node3D` where the reference omits it (measured: the
// `Child3D` node of the evidence scene is returned at distance `0.0`). That is a
// deliberate divergence, recorded here because the project requires such
// divergences to be written down. It is not justified by "the reference returns
// nothing" - it does not - but by (a) a probe tool must not fail on an ordinary
// node tree, and (b) the `(0,0)` 2D projection, though lossy for a 3D node, is at
// least well defined. PLAYBOOK adaptation §6.6 decides behaviour by "the tool
// actually working" rather than by copying a broken interaction.
static Vector2 _node_position(Node *p_node) {
	const Variant global_position = p_node->get(SNAME("global_position"));
	if (global_position.get_type() == Variant::VECTOR2) {
		return global_position;
	}
	const Variant local_position = p_node->get(SNAME("position"));
	if (local_position.get_type() == Variant::VECTOR2) {
		return local_position;
	}
	// MCP-NARROWING: G24-NODE-POSITION-FALLBACK - the zero vector this returns is
	// the "no 2D position property at all" fallback (see the block above: a
	// `Node3D` is deliberately measured at `(0,0)`); it names no caller value
	// (TASK-023 D-7 scan entry).
	return Vector2();
}

// Depth-first pre-order walk from `p_node`, the root included.
//
// `p_discovery` is the running pre-order index; it advances for every visited
// node (filtered out or not), so it is strictly increasing and can never make two
// candidates compare equal. A failing filter skips the node but never prunes the
// subtree, exactly like the reference.
static void _collect_nearby(Node *p_node, const Vector2 &p_target, real_t p_radius,
		const String &p_type_filter, const String &p_group_filter,
		Vector<NearbyCandidate> &r_out, int &r_discovery) {
	const int discovery_index = r_discovery++;

	bool keep = true;
	if (!p_type_filter.is_empty() && !p_node->is_class(p_type_filter)) {
		keep = false;
	}
	if (keep && !p_group_filter.is_empty() && !p_node->is_in_group(p_group_filter)) {
		keep = false;
	}

	if (keep) {
		const Vector2 node_position = _node_position(p_node);
		const real_t distance = p_target.distance_to(node_position);
		// The boundary is inclusive: `distance <= radius`.
		if (distance <= p_radius) {
			Dictionary entry;
			entry["name"] = String(p_node->get_name());
			entry["path"] = String(p_node->get_path());
			entry["type"] = p_node->get_class();
			entry["distance"] = (double)distance;

			NearbyCandidate candidate;
			candidate.entry = entry;
			candidate.distance = (double)distance;
			candidate.discovery_index = discovery_index;
			r_out.push_back(candidate);
		}
	}

	const int child_count = p_node->get_child_count();
	for (int i = 0; i < child_count; i++) {
		_collect_nearby(p_node->get_child(i), p_target, p_radius, p_type_filter, p_group_filter, r_out, r_discovery);
	}
}

static Variant _tool_find_nearby_nodes(const Dictionary &p_args, MCPToolError &r_error) {
	// --- `position` (required, object) ------------------------------------
	const Variant position_value = p_args.get("position", Variant());
	if (position_value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter: position");
		return Variant();
	}
	if (position_value.get_type() != Variant::DICTIONARY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'position' must be an object, got %s",
				Variant::get_type_name(position_value.get_type())));
		return Variant();
	}
	const Dictionary position = position_value;
	double position_x = 0.0;
	double position_y = 0.0;
	if (!_position_component(position, "x", position_x, r_error)) {
		return Variant();
	}
	if (!_position_component(position, "y", position_y, r_error)) {
		return Variant();
	}
	// MCP-NARROWING: G24-GAME-FIND-NEARBY-TARGET - the two `(real_t)` casts below
	// narrow; this is the TASK-023 gate that judges them first. This tool only
	// *reads*, but its answer is still a wrong answer when the search point
	// silently became `inf` (`distance <= inf` matches every node) or `0`
	// (`position: {"x": 1e-300}` searches at the origin), so the same rule the
	// write paths use applies: refuse a value the 32-bit slot cannot hold.
	if (!value_fits_slot(Variant(position_x), ValueSlot::FLOAT32, "position.x",
				"the 32-bit float component of the search point this tool measures distances from", r_error) ||
			!value_fits_slot(Variant(position_y), ValueSlot::FLOAT32, "position.y",
					"the 32-bit float component of the search point this tool measures distances from", r_error)) {
		return Variant();
	}
	// MCP-NARROWING: G24-GAME-FIND-NEARBY-TARGET - the cast below is the
	// narrowing the gate above judged.
	const Vector2 target((real_t)position_x, (real_t)position_y);

	// --- the optional parameters ------------------------------------------
	double radius = 100.0;
	if (!optional_float(p_args, "radius", 100.0, radius, r_error)) {
		return Variant();
	}
	// MCP-NARROWING: G24-GAME-FIND-NEARBY-RADIUS - the `(real_t)` cast of the
	// radius narrows; this is the TASK-023 gate that judges it first.
	if (!value_fits_slot(Variant(radius), ValueSlot::FLOAT32, "radius",
				"the 32-bit float slot the distance boundary this tool compares against is stored in", r_error)) {
		return Variant();
	}
	String type_filter;
	if (!optional_string(p_args, "type_filter", String(), type_filter, r_error)) {
		return Variant();
	}
	String group_filter;
	if (!optional_string(p_args, "group_filter", String(), group_filter, r_error)) {
		return Variant();
	}
	int64_t max_results = 50;
	if (!optional_int(p_args, "max_results", 50, max_results, r_error)) {
		return Variant();
	}

	// --- the running game's current scene ---------------------------------
	// Both a `SceneTree`-less process (a `--test` binary, or any process without
	// a scene loop) and a process whose main scene has not been set yet land in
	// the same GDR-14 state error: the tool has nothing to walk and must never
	// dereference a null singleton. This is the reference's own
	// `{"error": "No current scene"}` on the module's error vocabulary.
	SceneTree *tree = SceneTree::get_singleton();
	Node *root = tree != nullptr ? tree->get_current_scene() : nullptr;
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}

	// The reference's first line of `_find_nearby_recursive` is
	// `if results.size() >= max_results: return`, so a non-positive limit is an
	// empty result and never an error. Checked before the walk, after the scene
	// guard: the scene error still wins, exactly as in the reference.
	if (max_results <= 0) {
		Dictionary empty_result;
		empty_result["nodes"] = Array();
		empty_result["count"] = 0;
		return empty_result;
	}

	Vector<NearbyCandidate> candidates;
	int discovery = 0;
	// MCP-NARROWING: G24-GAME-FIND-NEARBY-RADIUS - the cast below is the
	// narrowing the `radius` gate above judged.
	_collect_nearby(root, target, (real_t)radius, type_filter, group_filter, candidates, discovery);

	SortArray<NearbyCandidate, NearbyCandidateLess> sorter;
	sorter.sort(candidates.ptrw(), candidates.size());

	const int keep = max_results < (int64_t)candidates.size() ? (int)max_results : candidates.size();
	Array nodes;
	for (int i = 0; i < keep; i++) {
		nodes.push_back(candidates[i].entry);
	}

	Dictionary result;
	result["nodes"] = nodes;
	result["count"] = nodes.size();
	return result;
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

void register_running_game_read_scene_tools(MCPToolRegistry &r_registry) {
	// Order follows docs/tool-groups.json, which lists this group last. Every
	// declaration comes from docs/tool-rename-map.json (`channel = running_game`,
	// `verb = find`, `scope = game`, `mutating = false`); the description and the
	// `inputSchema` are a byte-exact copy of the entry of
	// docs/tools_list.renamed.json, emitted from that file by
	// `scripts/gen_running_game_schema.py` and not retyped; re-running that
	// script reproduces this block byte for byte.
	{
		// BEGIN generated
		// (scripts/gen_running_game_schema.py: contract entry copied byte for byte)
		ToolBuilder builder("running_game_find_nearby_nodes", String::utf8("在运行中的游戏内查找指定位置附近的节点"));

		Dictionary properties;
		{
			Dictionary property;
			property["type"] = "string";
			property["description"] = String::utf8("节点组过滤");
			properties["group_filter"] = property;
		}
		{
			Dictionary property;
			property["type"] = "integer";
			property["description"] = String::utf8("最大返回结果数");
			properties["max_results"] = property;
		}
		{
			Dictionary property;
			property["type"] = "object";
			property["description"] = String::utf8("中心位置，如 {\"x\": 0, \"y\": 0}");
			property["additionalProperties"] = true;
			properties["position"] = property;
		}
		{
			Dictionary property;
			property["type"] = "number";
			property["description"] = String::utf8("搜索半径");
			properties["radius"] = property;
		}
		{
			Dictionary property;
			property["type"] = "string";
			property["description"] = String::utf8("节点类型过滤");
			properties["type_filter"] = property;
		}

		Array required;
		required.push_back("position");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		builder.channel("running_game").verb("find").scope(MCPToolScope::GAME).mutating(false).schema(schema).handler(_tool_find_nearby_nodes);
		builder.register_into(r_registry);
		// END generated
	}
}
