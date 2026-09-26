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