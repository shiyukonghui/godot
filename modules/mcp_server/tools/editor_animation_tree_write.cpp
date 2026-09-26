/**************************************************************************/
/*  editor_animation_tree_write.cpp                                       */
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
#include "editor_animation_tree_write.h"

#include "animation_shared.h"
#include "editor_animation_write.h"
#include "running_game_node_write.h"
#include "tool_helpers.h"

#include "core/io/json.h"
#include "core/variant/variant.h"
#include "scene/animation/animation_blend_tree.h"
#include "scene/animation/animation_node_state_machine.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-033 (B5 batch 1): the engine reference behind each tool of this group.
//
//   create_animation_tree_on
//     * `Node::add_child` + `Node::set_owner` - the two calls that put a node
//       into the edited scene and into its saved form;
//     * `AnimationTree::set_animation_player(NodePath)` (animation_tree.h:559) -
//       the member is a NodePath **relative to the AnimationTree itself**, which
//       is why the tool resolves the caller's edited-scene path to a real node
//       and then stores `Node::get_path_to` of it;
//     * `AnimationTree::set_root_animation_node(Ref<AnimationRootNode>)`
//       (animation_tree.h:562) - without a root the tree cannot hold states.
//
//   add_state_machine_state_on
//     * `AnimationNodeStateMachine::add_node(StringName, Ref<AnimationNode>,
//       const Vector2 &p_position)` (animation_node_state_machine.h:173) - the
//       position is part of this one call (the migration source dropped it);
//     * `animation_state_machine_at` (animation_shared.cpp) for the addressing.
//     * TASK-034 section 0: `AnimationNodeAnimation::set_animation(StringName)`
//       (animation_blend_tree.h:71) - the state's animation is a **property** of
//       the node, not a `parameters/...` parameter, so before the `animation`
//       member existed no tool could point a freshly created Animation state at
//       an animation (REPORT-033 section 7.1). The name is checked against the
//       AnimationPlayer the tree names before it is written, so a state cannot be
//       left pointing at an animation that does not exist.
//
//   add_state_machine_transition_on
//     * `AnimationNodeStateMachineTransition::set_switch_mode` /
//       `set_advance_mode` (animation_node_state_machine.h:72-76) - two named
//       setters, never a raw enum number;
//     * TASK-034 section 0: `set_xfade_time(float)` (:86), `set_priority(int)`
//       (:98) and `set_advance_condition(StringName)` (:78) - the three members
//       the contract declared nowhere until this batch, so a cross-fade, a
//       priority and an advance condition were structurally unreachable. The
//       condition is the engine's own: `set_advance_condition` builds
//       `conditions/<name>` (:60) and the state machine registers it as a plain
//       BOOL parameter of the tree (`get_parameter_list`,
//       animation_node_state_machine.cpp:1260-1275), addressed as
//       `parameters/<state machine path>/conditions/<name>` by
//       `AnimationTree::_update_properties_for_node` (animation_tree.cpp:839-854) -
//       which is exactly the name `editor_set_animation_tree_parameter` writes, so
//       the answer carries it and the chain needs no string surgery;
//     * `AnimationNodeStateMachine::add_transition` / `has_transition` /
//       `find_transition` / `get_transition` (animation_node_state_machine.h:188-198).
//
//   remove_state_machine_state_on / remove_state_machine_transition_on
//     * `AnimationNodeStateMachine::remove_node` / `remove_transition`
//       (animation_node_state_machine.h:176 and 201), with
//       `get_node_list()` / `get_transition_count()` on both sides so the answer
//       carries a real count.
//
//   set_blend_tree_node_on
//     * `AnimationNodeBlendTree::add_node(name, node, position)` (animation_blend_tree.h:475),
//       `has_node` (478), `get_node_position` (483), `get_node_connection_array`
//       (480) for the read-back;
//     * TASK-034 section 0: the same `AnimationNodeAnimation::set_animation`
//       (animation_blend_tree.h:71) the state writer uses, for a
//       `bt_node_type=Animation` node.
//
//   set_animation_tree_parameter_on
//     * `Object::get_property_list()` - an AnimationTree exposes its parameters
//       as `parameters/<child>/<name>` properties (`Animation::PARAMETERS_BASE_PATH`,
//       animation_tree.cpp:883) with a declared type each;
//     * `Object::set` / `Object::get` on that name, which is exactly what the
//       engine's own `_set` / `_get` (animation_tree.cpp:1093) route to the node
//       or to the node instance's slot;
//     * the property list is also the *refusal* basis: the migration source
//       wrote a name that did not exist and answered `set: true`.
// ---------------------------------------------------------------------------

namespace MCPTools {

// The blend-tree node kinds, from the engine's own blend-tree classes
// (`scene/animation/animation_blend_tree.h`). The short spellings are the
// migration source's list; the class names are accepted as well, because that is
// what `editor_get_animation_tree_structure` answers.
static bool _blend_tree_node_type_from_string(const String &p_type, Ref<AnimationNode> &r_out, String &r_reason) {
	const String spelling = p_type.strip_edges().to_lower();
	if (spelling == "animation" || spelling == "animationnodeanimation") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeAnimation));
		return true;
	}
	if (spelling == "add2" || spelling == "animationnodeadd2") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeAdd2));
		return true;
	}
	if (spelling == "add3" || spelling == "animationnodeadd3") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeAdd3));
		return true;
	}
	if (spelling == "blend2" || spelling == "animationnodeblend2") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeBlend2));
		return true;
	}
	if (spelling == "blend3" || spelling == "animationnodeblend3") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeBlend3));
		return true;
	}
	if (spelling == "sub2" || spelling == "animationnodesub2") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeSub2));
		return true;
	}
	if (spelling == "timescale" || spelling == "animationnodetimescale") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeTimeScale));
		return true;
	}
	if (spelling == "timeseek" || spelling == "animationnodetimeseek") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeTimeSeek));
		return true;
	}
	if (spelling == "transition" || spelling == "animationnodetransition") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeTransition));
		return true;
	}
	if (spelling == "oneshot" || spelling == "animationnodeoneshot") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeOneShot));
		return true;
	}
	r_reason = vformat("'bt_node_type' must name an AnimationNodeBlendTree node class: Animation, Add2, Add3, Blend2, "
					   "Blend3, Sub2, TimeScale, TimeSeek, Transition or OneShot (the engine class names "
					   "AnimationNode<name> are accepted too); got '%s'",
			p_type);
	return false;
}

// "Is the value that came back the value that was written?" - `Variant::operator==`
// is `hash_compare`, which answers false for an INT next to a FLOAT holding the
// same number, so the two numeric types are compared numerically (the same rule
// `project_write_resource_scene.cpp` uses for its read-back).
static bool _values_agree(const Variant &p_read_back, const Variant &p_written) {
	if (p_read_back.get_type() == p_written.get_type()) {
		return p_read_back == p_written;
	}
	const Variant::Type read_type = p_read_back.get_type();
	const Variant::Type written_type = p_written.get_type();
	const bool read_numeric = (read_type == Variant::INT || read_type == Variant::FLOAT);
	const bool written_numeric = (written_type == Variant::INT || written_type == Variant::FLOAT);
	if (read_numeric && written_numeric) {
		return (double)p_read_back == (double)p_written;
	}
	return false;
}

static AnimationPlayer *_find_first_animation_player(Node *p_node) {
	// The engine's own child order, depth first, so the answer is deterministic
	// (PLAYBOOK section 6.8) - and the same node the editor's "Create
	// AnimationTree" flow would pick.
	for (int i = 0; i < p_node->get_child_count(); i++) {
		Node *child = p_node->get_child(i);
		AnimationPlayer *player = Object::cast_to<AnimationPlayer>(child);
		if (player != nullptr) {
			return player;
		}
		player = _find_first_animation_player(child);
		if (player != nullptr) {
			return player;
		}
	}
	return nullptr;
}

static Array _state_names_for_message(const Ref<AnimationNodeStateMachine> &p_machine) {
	return p_machine->get_node_list_as_typed_array();
}

// TASK-034 section 0: the AnimationPlayer the tree itself names
// (`AnimationTree::get_animation_player()` is a NodePath relative to the tree).
// nullptr when the tree names no player or the named node is not an
// AnimationPlayer - the animation name is then written unchecked, and the answer
// says so.
static AnimationPlayer *_tree_animation_player(AnimationTree *p_tree) {
	const NodePath path = p_tree->get_animation_player();
	if (path.is_empty()) {
		return nullptr;
	}
	Node *node = p_tree->get_node_or_null(path);
	return node != nullptr ? Object::cast_to<AnimationPlayer>(node) : nullptr;
}

// The one place an `animation` argument reaches an `AnimationNodeAnimation`, for
// both entry points of this group that take one.
//
// Two checks run before the engine's own setter:
//   * an empty (or blank) name is refused rather than written: dropping the
//     argument means "leave the node without an animation", giving it as an empty
//     string is a caller mistake, not a second spelling of the same thing;
//   * when the tree names an AnimationPlayer that really exists, the name has to
//     be one that player's default library holds. That is the "a created thing is
//     read back" rule applied before the write: a state pointing at an animation
//     that is not there is a broken chain the engine would accept in silence.
static bool _set_animation_node_animation(AnimationTree *p_tree, AnimationNodeAnimation *p_node,
		const String &p_animation, MCPToolError &r_error) {
	const String name = p_animation.strip_edges();
	if (name.is_empty()) {
		r_error = MCPToolError::invalid_params(
				"'animation' must not be empty when it is given: it is the animation the Animation node plays. "
				"Omit the argument to leave the node without one");
		return false;
	}
	AnimationPlayer *player = _tree_animation_player(p_tree);
	if (player != nullptr && animation_named(player, name).is_null()) {
		const Vector<String> names = animation_names_in_default_library(player);
		r_error = MCPToolError::not_found(
				vformat("Animation '%s' on AnimationPlayer '%s' (the player this AnimationTree names)", name,
						player->get_name()),
				vformat("'animation' is checked against the AnimationTree's own AnimationPlayer before it is written, "
						"because a state pointing at an animation that is not there plays nothing; that player's "
						"default library holds: %s. Create the animation first with editor_create_animation",
						names.is_empty() ? String("(nothing)") : String(", ").join(names)));
		return false;
	}
	p_node->set_animation(StringName(name));
	const String stored = String(p_node->get_animation());
	if (stored != name) {
		r_error = MCPToolError::internal(vformat(
				"AnimationNodeAnimation::set_animation('%s') did not stick: the node answers '%s'", name, stored));
		return false;
	}
	return true;
}

// The tree parameter name an advance condition is registered under. The engine's
// own spelling is `conditions/<name>` (`set_advance_condition`,
// animation_node_state_machine.cpp:60) and the tree prefixes it with the path of
// the state machine that holds the transition plus the `parameters/` base
// (animation_tree.cpp:839-854), which is the name
// `editor_set_animation_tree_parameter` writes.
static String _advance_condition_parameter(const AnimationNodeStateMachineTransition *p_transition,
		const String &p_state_machine_path) {
	const StringName condition_name = p_transition->get_advance_condition_name();
	if (condition_name == StringName()) {
		return String();
	}
	const String machine_path = animation_state_machine_path_normalize(p_state_machine_path);
	const String prefix = machine_path.is_empty() ? String("parameters/") : String("parameters/") + machine_path + "/";
	return prefix + String(condition_name);
}

static String _sorted_names_for_message(const TypedArray<StringName> &p_names) {
	Vector<String> names;
	for (int i = 0; i < p_names.size(); i++) {
		names.push_back(String(p_names[i]));
	}
	names.sort();
	return names.is_empty() ? String("(none)") : String(", ").join(names);
}

// The gate every position pair runs before the two `real_t` members of a
// `Vector2` are written.

Dictionary create_animation_tree_on(Node *p_root, const String &p_parent_path, const String &p_animation_player_path,
		bool p_player_path_given, const String &p_tree_name, MCPToolError &r_error) {
	Node *parent = find_node(p_root, p_parent_path);
	if (parent == nullptr) {
		r_error = MCPToolError::not_found(vformat("Parent node '%s' in the edited scene", p_parent_path),
				"'node_path' is the parent the AnimationTree is added under, relative to the edited scene root "
				"('.' is the root itself); call editor_get_scene_tree to list the paths");
		return Dictionary();
	}
	const String tree_name = p_tree_name.strip_edges().is_empty() ? String("AnimationTree") : p_tree_name.strip_edges();
	if (parent->has_node(NodePath(tree_name))) {
		// `Node::add_child` would silently rename the new node to
		// "AnimationTree2"-style spelling, and the caller would then hold a name
		// that does not exist. Refusing says what is really there.
		r_error = MCPToolError::tool_state(
				vformat("Node '%s' already has a child named '%s'", p_parent_path, tree_name),
				"Pick another 'name', remove the existing node with editor_remove_node, or use the existing tree");
		return Dictionary();
	}

	// The AnimationPlayer: the named one (a real node of the edited scene, so the
	// engine gets a NodePath it can resolve) or, when the argument is absent, the
	// first one in the edited scene - both are reported through
	// `animation_player_source`.
	AnimationPlayer *player = nullptr;
	String player_source = "none";
	if (p_player_path_given && !p_animation_player_path.strip_edges().is_empty()) {
		player = animation_player_node(p_root, p_animation_player_path, r_error);
		if (player == nullptr) {
			return Dictionary();
		}
		player_source = "animation_player_path";
	} else {
		player = _find_first_animation_player(p_root);
		if (player != nullptr) {
			player_source = "auto_first_player";
		}
	}

	AnimationTree *tree = memnew(AnimationTree);
	tree->set_name(tree_name);
	parent->add_child(tree);
	// The owner makes the new node part of what the editor saves; the edited
	// scene root is an ancestor of every node `p_parent_path` can address.
	tree->set_owner(p_root);
	if (player != nullptr) {
		// `animation_player` is a NodePath relative to the AnimationTree
		// (animation_tree.h:500), so the engine's own `get_path_to` is what is
		// stored - never the caller's edited-scene spelling.
		tree->set_animation_player(tree->get_path_to(player));
	}
	Ref<AnimationNodeStateMachine> tree_root;
	tree_root.instantiate();
	tree->set_root_animation_node(tree_root);

	// Read back through the engine: the node really is a child of the parent, and
	// the wiring the answer claims is what the engine stores.
	Node *created = parent->get_node_or_null(NodePath(tree_name));
	AnimationTree *stored = Object::cast_to<AnimationTree>(created);
	if (stored == nullptr) {
		r_error = MCPToolError::internal(vformat(
				"The AnimationTree was added under '%s' but the parent does not answer a child named '%s'",
				p_parent_path, tree_name));
		return Dictionary();
	}

	Dictionary out;
	out["created"] = true;
	out["name"] = tree_name;
	out["node_path"] = relative_path(p_root, stored);
	out["type"] = stored->get_class();
	out["animation_player_source"] = player_source;
	out["animation_player"] = player != nullptr ? relative_path(p_root, player) : String();
	out["animation_player_path_from_tree"] = String(stored->get_animation_player());
	const Ref<AnimationRootNode> root_node = stored->get_root_animation_node();
	out["tree_root"] = root_node.is_valid() ? root_node->get_class() : String();
	out["active"] = stored->is_active();
	return out;
}

Dictionary add_state_machine_state_on(AnimationTree *p_tree, const String &p_state_machine_path,
		const String &p_state_name, const String &p_state_type, double p_position_x, double p_position_y,
		const String &p_animation, bool p_animation_given, MCPToolError &r_error) {
	const String state_name = p_state_name.strip_edges();
	if (state_name.is_empty()) {
		r_error = MCPToolError::invalid_params("'state_name' must not be empty");
		return Dictionary();
	}
	Ref<AnimationNodeStateMachine> machine = animation_state_machine_at(p_tree->get_root_animation_node(),
			p_state_machine_path, r_error);
	if (machine.is_null()) {
		return Dictionary();
	}
	if (machine->has_node(StringName(state_name))) {
		r_error = MCPToolError::tool_state(
				vformat("State '%s' already exists in the state machine", state_name),
				vformat("Pick another 'state_name', or remove the state with editor_remove_state_machine_state; this "
						"machine holds: %s",
						_sorted_names_for_message(_state_names_for_message(machine))));
		return Dictionary();
	}
	Ref<AnimationNode> node;
	String reason;
	if (!animation_state_type_from_string(p_state_type, node, reason)) {
		r_error = MCPToolError::invalid_params(reason);
		return Dictionary();
	}
	if (Math::is_nan(p_position_x) || Math::is_inf(p_position_x) || Math::is_nan(p_position_y) || Math::is_inf(p_position_y)) {
		r_error = MCPToolError::invalid_params("'position_x' and 'position_y' must be finite numbers");
		return Dictionary();
	}
	// MCP-NARROWING: G24-ANIM-POSITION - `_position_fits` below judges both
	// components with `value_fits_slot(REAL_T)` before the `Vector2` is built, so
	// the copies on that line cannot narrow an unfit value.
	if (!value_fits_slot(p_position_x, ValueSlot::REAL_T, "position_x",
				"the real_t x component of the Vector2 this value is copied into", r_error)) {
		return Dictionary();
	}
	if (!value_fits_slot(p_position_y, ValueSlot::REAL_T, "position_y",
				"the real_t y component of the Vector2 this value is copied into", r_error)) {
		return Dictionary();
	}
	// MCP-NARROWING: G24-ANIM-POSITION - the two casts are the pre-gated copy.
	const Vector2 position((real_t)p_position_x, (real_t)p_position_y);

	// `add_node` is the one engine call that creates the state and places it.
	machine->add_node(StringName(state_name), node, position);
	if (!machine->has_node(StringName(state_name))) {
		r_error = MCPToolError::internal(vformat(
				"AnimationNodeStateMachine::add_node('%s') did not register the state", state_name));
		return Dictionary();
	}

	const Ref<AnimationNode> stored = machine->get_node(StringName(state_name));
	// TASK-034 section 0: the `animation` member reaches the engine's own setter
	// *before* anything is reported, and only for an Animation state.
	AnimationNodeAnimation *animation_state = Object::cast_to<AnimationNodeAnimation>(stored.ptr());
	if (p_animation_given) {
		if (animation_state == nullptr) {
			r_error = MCPToolError::invalid_params(vformat(
					"'animation' applies to an animation state only (the state this call created is a %s): "
					"AnimationNodeAnimation::set_animation is the property it writes, and 'state_type' is '%s'",
					stored.is_valid() ? stored->get_class() : String("null"), p_state_type.strip_edges()));
			return Dictionary();
		}
		if (!_set_animation_node_animation(p_tree, animation_state, p_animation, r_error)) {
			return Dictionary();
		}
	}
	Dictionary out;
	out["state_name"] = state_name;
	out["state_type"] = animation_state_type_name(stored);
	out["class"] = stored.is_valid() ? stored->get_class() : String();
	out["state_machine_path"] = animation_state_machine_path_normalize(p_state_machine_path);
	out["position"] = serialize_variant(machine->get_node_position(StringName(state_name)));
	out["added"] = true;
	out["state_count"] = machine->get_node_list().size();
	if (animation_state != nullptr) {
		// Read back: the animation the engine now stores, which is the name a
		// later `editor_list_animations` / `editor_get_animation_info` call and
		// the tree's own parameter list both speak.
		out["animation"] = String(animation_state->get_animation());
		out["animation_given"] = p_animation_given;
	}
	return out;
}

Dictionary add_state_machine_transition_on(AnimationTree *p_tree, const String &p_state_machine_path,
		const String &p_from_state, const String &p_to_state, const String &p_switch_mode,
		const String &p_advance_mode, double p_xfade_time, bool p_xfade_time_given, int64_t p_priority,
		bool p_priority_given, const String &p_advance_condition, bool p_advance_condition_given,
		MCPToolError &r_error) {
	Ref<AnimationNodeStateMachine> machine = animation_state_machine_at(p_tree->get_root_animation_node(),
			p_state_machine_path, r_error);
	if (machine.is_null()) {
		return Dictionary();
	}
	const StringName from(p_from_state);
	const StringName to(p_to_state);
	if (!machine->has_node(from)) {
		r_error = MCPToolError::not_found(vformat("State '%s' (from_state) in the state machine", p_from_state),
				vformat("This machine holds: %s", _sorted_names_for_message(_state_names_for_message(machine))));
		return Dictionary();
	}
	if (!machine->has_node(to)) {
		r_error = MCPToolError::not_found(vformat("State '%s' (to_state) in the state machine", p_to_state),
				vformat("This machine holds: %s", _sorted_names_for_message(_state_names_for_message(machine))));
		return Dictionary();
	}
	if (machine->has_transition(from, to)) {
		r_error = MCPToolError::tool_state(
				vformat("A transition from '%s' to '%s' already exists (index %d)", p_from_state, p_to_state,
						machine->find_transition(from, to)),
				"Remove it with editor_remove_state_machine_transition, or read the machine with "
				"editor_get_animation_tree_structure");
		return Dictionary();
	}
	AnimationNodeStateMachineTransition::SwitchMode switch_mode =
			AnimationNodeStateMachineTransition::SWITCH_MODE_IMMEDIATE;
	AnimationNodeStateMachineTransition::AdvanceMode advance_mode =
			AnimationNodeStateMachineTransition::ADVANCE_MODE_ENABLED;
	String reason;
	if (!animation_switch_mode_from_string(p_switch_mode, switch_mode, reason)) {
		r_error = MCPToolError::invalid_params(reason);
		return Dictionary();
	}
	if (!animation_advance_mode_from_string(p_advance_mode, advance_mode, reason)) {
		r_error = MCPToolError::invalid_params(reason);
		return Dictionary();
	}

	// TASK-034 section 0: the three members the contract declared nowhere until
	// this batch. Each one is judged before the transition object exists, so a
	// refused argument cannot leave a half-configured transition behind.
	if (Math::is_nan(p_xfade_time) || Math::is_inf(p_xfade_time)) {
		r_error = MCPToolError::invalid_params("'xfade_time' must be a finite number of seconds");
		return Dictionary();
	}
	if (p_xfade_time < 0.0) {
		r_error = MCPToolError::invalid_params(vformat(
				"'xfade_time' must not be negative: it is the cross-fade duration "
				"AnimationNodeStateMachineTransition::set_xfade_time stores, and a negative fade is not a fade "
				"(the engine's own editor range is 0..240); got %f",
				p_xfade_time));
		return Dictionary();
	}
	// `xfade_time` is a `float` member (animation_node_state_machine.h:58), so it
	// is judged as 32 bits whatever the build's `real_t` is.
	if (!value_fits_slot(p_xfade_time, ValueSlot::FLOAT32, "xfade_time",
				"the float cross-fade duration this value is copied into "
				"(AnimationNodeStateMachineTransition::set_xfade_time)",
				r_error)) {
		return Dictionary();
	}
	if (p_priority_given && p_priority < 0) {
		r_error = MCPToolError::invalid_params(vformat(
				"'priority' must not be negative: it is the `int priority` member "
				"AnimationNodeStateMachineTransition::set_priority stores and the state machine multiplies a "
				"transition's cost by it (animation_node_state_machine.cpp:582); got %d",
				(int64_t)p_priority));
		return Dictionary();
	}
	// The `int priority` member is an `int32_t`; the gate is the module's one
	// width judgement, so `3e9` is refused instead of wrapping.
	if (p_priority_given && !value_fits_slot(p_priority, ValueSlot::INT32, "priority",
				"the int32_t priority member this value is copied into "
				"(AnimationNodeStateMachineTransition::set_priority)",
				r_error)) {
		return Dictionary();
	}
	const String advance_condition = p_advance_condition.strip_edges();
	if (p_advance_condition_given && advance_condition.contains("/")) {
		r_error = MCPToolError::invalid_params(vformat(
				"'advance_condition' must be a plain name: the engine builds the parameter name "
				"`conditions/<name>` from it (animation_node_state_machine.cpp:60), and a '/' inside the name would "
				"put the parameter at a path no caller can address; got '%s'",
				p_advance_condition));
		return Dictionary();
	}

	Ref<AnimationNodeStateMachineTransition> transition;
	transition.instantiate();
	// The engine's own setters - the enum numbers never appear here, which is
	// what makes the answer's switch_mode/advance_mode trustworthy.
	transition->set_switch_mode(switch_mode);
	transition->set_advance_mode(advance_mode);
	// MCP-NARROWING: G24-ANIM-XFADE - `value_fits_slot(p_xfade_time, FLOAT32)`
	// ran above, so this copy into the engine's `float` member cannot narrow an
	// unfit value.
	transition->set_xfade_time((float)p_xfade_time);
	if (p_priority_given) {
		transition->set_priority((int)p_priority);
	}

	const int count_before = machine->get_transition_count();
	machine->add_transition(from, to, transition);
	const int count_after = machine->get_transition_count();
	const int index = machine->find_transition(from, to);
	if (index < 0 || count_after != count_before + 1) {
		r_error = MCPToolError::internal(vformat(
				"AnimationNodeStateMachine::add_transition('%s' -> '%s') left %d transition(s) (was %d), index %d",
				p_from_state, p_to_state, count_after, count_before, index));
		return Dictionary();
	}
	// The advance condition is set **after** `add_transition`, and that order is
	// part of the behaviour, not a style choice:
	// `AnimationNodeStateMachine::add_transition` is where the transition's
	// `advance_condition_changed` signal is connected to the machine's
	// `_tree_changed` (`scene/animation/animation_node_state_machine.cpp:1581`),
	// and that signal is the only way the owning `AnimationTree` learns that its
	// cached `parameters/...` list gained `conditions/<name>`
	// (`AnimationTree::_tree_changed`, `scene/animation/animation_tree.cpp:760`,
	// refreshes it **deferred**, :765). Setting the condition first - as this
	// function did until the TASK-034 wire evidence caught it - leaves the tree's
	// list without the parameter the answer names, so
	// `editor_set_animation_tree_parameter` then refuses a name this very tool
	// produced.
	if (p_advance_condition_given) {
		// An empty string is the engine's own "no condition" spelling
		// (`set_advance_condition` folds it to the empty StringName, :60-62), so
		// it is a legal clear rather than a mistake.
		transition->set_advance_condition(StringName(advance_condition));
	}

	const Ref<AnimationNodeStateMachineTransition> stored = machine->get_transition(index);
	Dictionary out;
	out["from"] = p_from_state;
	out["to"] = p_to_state;
	out["state_machine_path"] = animation_state_machine_path_normalize(p_state_machine_path);
	out["added"] = true;
	out["transition_index"] = index;
	out["transition_count"] = count_after;
	out["switch_mode"] = animation_switch_mode_name(stored->get_switch_mode());
	out["advance_mode"] = animation_advance_mode_name(stored->get_advance_mode());
	// TASK-034 section 0: the read-back of the three new members, so "it was
	// applied" is the engine's answer. `advance_condition_parameter` is the exact
	// `parameters/...` name `editor_set_animation_tree_parameter` writes - the
	// zero-surgery half of the chain (GDR-25 section 23.1).
	out["xfade_time"] = stored->get_xfade_time();
	out["priority"] = stored->get_priority();
	out["advance_condition"] = String(stored->get_advance_condition());
	out["advance_condition_parameter"] = _advance_condition_parameter(stored.ptr(), p_state_machine_path);
	return out;
}

Dictionary remove_state_machine_state_on(AnimationTree *p_tree, const String &p_state_machine_path,
		const String &p_state_name, MCPToolError &r_error) {
	Ref<AnimationNodeStateMachine> machine = animation_state_machine_at(p_tree->get_root_animation_node(),
			p_state_machine_path, r_error);
	if (machine.is_null()) {
		return Dictionary();
	}
	const StringName state_name(p_state_name);
	if (!machine->has_node(state_name)) {
		r_error = MCPToolError::not_found(vformat("State '%s' in the state machine", p_state_name),
				vformat("This machine holds: %s", _sorted_names_for_message(_state_names_for_message(machine))));
		return Dictionary();
	}
	const int states_before = (int)machine->get_node_list().size();
	const int transitions_before = machine->get_transition_count();
	machine->remove_node(state_name);
	const int states_after = (int)machine->get_node_list().size();
	const int transitions_after = machine->get_transition_count();
	if (machine->has_node(state_name) || states_after != states_before - 1) {
		r_error = MCPToolError::internal(vformat(
				"AnimationNodeStateMachine::remove_node('%s') left %d state(s) (was %d)", p_state_name, states_after,
				states_before));
		return Dictionary();
	}

	Dictionary out;
	out["state_name"] = p_state_name;
	out["state_machine_path"] = animation_state_machine_path_normalize(p_state_machine_path);
	out["removed"] = states_before - states_after;
	// Removing a state also removes every transition that touched it
	// (`AnimationNodeStateMachine::_animation_node_removed`), so the transitions
	// the call really deleted are reported instead of being left implicit.
	out["removed_transitions"] = transitions_before - transitions_after;
	out["state_count"] = states_after;
	out["transition_count"] = transitions_after;
	return out;
}

Dictionary remove_state_machine_transition_on(AnimationTree *p_tree, const String &p_state_machine_path,
		const String &p_from_state, const String &p_to_state, MCPToolError &r_error) {
	Ref<AnimationNodeStateMachine> machine = animation_state_machine_at(p_tree->get_root_animation_node(),
			p_state_machine_path, r_error);
	if (machine.is_null()) {
		return Dictionary();
	}
	const StringName from(p_from_state);
	const StringName to(p_to_state);
	const int index = machine->find_transition(from, to);
	if (index < 0) {
		Array existing;
		for (int i = 0; i < machine->get_transition_count(); i++) {
			Dictionary entry;
			entry["from"] = String(machine->get_transition_from(i));
			entry["to"] = String(machine->get_transition_to(i));
			existing.push_back(entry);
		}
		r_error = MCPToolError::not_found(vformat("Transition '%s' -> '%s'", p_from_state, p_to_state),
				vformat("The machine has %d transition(s); editor_get_animation_tree_structure lists them as "
						"{from,to} pairs, any of which can be passed back here",
						existing.size()));
		return Dictionary();
	}
	const int count_before = machine->get_transition_count();
	machine->remove_transition(from, to);
	const int count_after = machine->get_transition_count();
	if (machine->has_transition(from, to) || count_after != count_before - 1) {
		r_error = MCPToolError::internal(vformat(
				"AnimationNodeStateMachine::remove_transition('%s' -> '%s') left %d transition(s) (was %d)",
				p_from_state, p_to_state, count_after, count_before));
		return Dictionary();
	}

	Dictionary out;
	out["from"] = p_from_state;
	out["to"] = p_to_state;
	out["state_machine_path"] = animation_state_machine_path_normalize(p_state_machine_path);
	out["removed"] = count_before - count_after;
	out["transition_count"] = count_after;
	return out;
}

Dictionary set_blend_tree_node_on(AnimationTree *p_tree, const String &p_state_machine_path,
		const String &p_blend_tree_state, const String &p_bt_node_name, const String &p_bt_node_type,
		double p_position_x, double p_position_y, const String &p_animation, bool p_animation_given,
		MCPToolError &r_error) {
	Ref<AnimationNodeStateMachine> machine = animation_state_machine_at(p_tree->get_root_animation_node(),
			p_state_machine_path, r_error);
	if (machine.is_null()) {
		return Dictionary();
	}
	const StringName blend_tree_state(p_blend_tree_state);
	if (!machine->has_node(blend_tree_state)) {
		r_error = MCPToolError::not_found(vformat("State '%s' (blend_tree_state) in the state machine", p_blend_tree_state),
				vformat("This machine holds: %s", _sorted_names_for_message(_state_names_for_message(machine))));
		return Dictionary();
	}
	const Ref<AnimationNode> state_node = machine->get_node(blend_tree_state);
	Ref<AnimationNodeBlendTree> blend = Object::cast_to<AnimationNodeBlendTree>(state_node.ptr());
	if (blend.is_null()) {
		r_error = MCPToolError::invalid_params(vformat(
				"State '%s' holds a %s, not an AnimationNodeBlendTree, so it cannot take a blend-tree node",
				p_blend_tree_state, state_node.is_valid() ? state_node->get_class() : String("null")));
		return Dictionary();
	}
	const String node_name = p_bt_node_name.strip_edges();
	if (node_name.is_empty()) {
		r_error = MCPToolError::invalid_params("'bt_node_name' must not be empty");
		return Dictionary();
	}
	if (blend->has_node(StringName(node_name))) {
		// The migration source removed the existing node and re-added it, which
		// silently drops every connection into and out of it. This tool creates;
		// it does not destroy.
		r_error = MCPToolError::tool_state(
				vformat("The blend tree of state '%s' already has a node named '%s'", p_blend_tree_state, node_name),
				"Pick another 'bt_node_name'; this tool only adds nodes, because replacing one is what would drop its "
				"connections - use editor_get_animation_tree_structure to see the nodes that are there");
		return Dictionary();
	}
	Ref<AnimationNode> node;
	String reason;
	if (!_blend_tree_node_type_from_string(p_bt_node_type, node, reason)) {
		r_error = MCPToolError::invalid_params(reason);
		return Dictionary();
	}
	if (Math::is_nan(p_position_x) || Math::is_inf(p_position_x) || Math::is_nan(p_position_y) || Math::is_inf(p_position_y)) {
		r_error = MCPToolError::invalid_params("'position_x' and 'position_y' must be finite numbers");
		return Dictionary();
	}
	// MCP-NARROWING: G24-ANIM-POSITION - see `add_state_machine_state_on`; both
	// components passed `value_fits_slot(REAL_T)` immediately above.
	if (!value_fits_slot(p_position_x, ValueSlot::REAL_T, "position_x",
				"the real_t x component of the Vector2 this value is copied into", r_error)) {
		return Dictionary();
	}
	if (!value_fits_slot(p_position_y, ValueSlot::REAL_T, "position_y",
				"the real_t y component of the Vector2 this value is copied into", r_error)) {
		return Dictionary();
	}
	// MCP-NARROWING: G24-ANIM-POSITION - the two casts are the pre-gated copy.
	const Vector2 position((real_t)p_position_x, (real_t)p_position_y);

	blend->add_node(StringName(node_name), node, position);
	if (!blend->has_node(StringName(node_name))) {
		r_error = MCPToolError::internal(vformat("AnimationNodeBlendTree::add_node('%s') did not register the node",
				node_name));
		return Dictionary();
	}

	const Ref<AnimationNode> stored = blend->get_node(StringName(node_name));
	// TASK-034 section 0: the `animation` member, with the same rules as the
	// state-machine state writer above.
	AnimationNodeAnimation *animation_node = Object::cast_to<AnimationNodeAnimation>(stored.ptr());
	if (p_animation_given) {
		if (animation_node == nullptr) {
			r_error = MCPToolError::invalid_params(vformat(
					"'animation' applies to a blend-tree Animation node only (the node this call created is a %s): "
					"AnimationNodeAnimation::set_animation is the property it writes, and 'bt_node_type' is '%s'",
					stored.is_valid() ? stored->get_class() : String("null"), p_bt_node_type.strip_edges()));
			return Dictionary();
		}
		if (!_set_animation_node_animation(p_tree, animation_node, p_animation, r_error)) {
			return Dictionary();
		}
	}

	// Deterministic name list: `AnimationNodeBlendTree::nodes` is an `AHashMap`,
	// so the engine's own iteration order is not reproducible (PLAYBOOK 6.8).
	LocalVector<StringName> listed;
	listed = blend->get_node_list();
	Vector<String> names;
	for (uint32_t i = 0; i < listed.size(); i++) {
		names.push_back(String(listed[i]));
	}
	names.sort();

	Dictionary out;
	out["blend_tree_state"] = p_blend_tree_state;
	out["state_machine_path"] = animation_state_machine_path_normalize(p_state_machine_path);
	out["bt_node_name"] = node_name;
	out["bt_node_type"] = p_bt_node_type.strip_edges();
	out["class"] = stored.is_valid() ? stored->get_class() : String();
	out["position"] = serialize_variant(blend->get_node_position(StringName(node_name)));
	out["added"] = true;
	out["node_count"] = (int)names.size();
	out["nodes"] = names;
	// A fresh node has no connections yet; the engine's own per-node list says so.
	const LocalVector<StringName> *connections = blend->get_node_connection_array(StringName(node_name));
	Array written_connections;
	if (connections != nullptr) {
		for (uint32_t i = 0; i < connections->size(); i++) {
			written_connections.push_back(String((*connections)[i]));
		}
	}
	out["connections"] = written_connections;
	if (animation_node != nullptr) {
		out["animation"] = String(animation_node->get_animation());
		out["animation_given"] = p_animation_given;
	}
	return out;
}

Dictionary set_animation_tree_parameter_on(AnimationTree *p_tree, const String &p_parameter, const Variant &p_value,
		MCPToolError &r_error) {
	String parameter = p_parameter.strip_edges();
	if (parameter.is_empty()) {
		r_error = MCPToolError::invalid_params("'parameter' must not be empty");
		return Dictionary();
	}
	const String prefix = Animation::PARAMETERS_BASE_PATH;
	// The engine's own parameter namespace is `parameters/...`; a bare
	// `blend_amount` is accepted and folded, which is what the migration source
	// did as well.
	if (!parameter.begins_with(prefix)) {
		parameter = prefix + parameter;
	}

	// The tree's own property list is the authority on which parameters exist and
	// what type each one has (`AnimationTree::_update_properties_for_node`,
	// animation_tree.cpp:839-854). A name outside it is a refusal - the migration
	// source wrote it anyway and answered `set: true`.
	List<PropertyInfo> properties;
	p_tree->get_property_list(&properties);
	Variant::Type target_type = Variant::NIL;
	uint32_t target_usage = 0;
	bool found = false;
	Vector<String> known;
	for (const PropertyInfo &property : properties) {
		const String name = String(property.name);
		if (!name.begins_with(prefix)) {
			continue;
		}
		known.push_back(name);
		if (name == parameter) {
			target_type = property.type;
			target_usage = property.usage;
			found = true;
		}
	}
	if (!found) {
		known.sort();
		r_error = MCPToolError::not_found(vformat("Parameter '%s' of this AnimationTree", parameter),
				vformat("The tree's parameters are its own 'parameters/...' properties; this tree answers: %s. Call "
						"editor_get_animation_tree_structure to read them by name and type",
						known.is_empty() ? String("(none - the tree has no root node or no parameters)") : String(", ").join(known)));
		return Dictionary();
	}
	if (target_type == Variant::OBJECT) {
		r_error = MCPToolError::tool_state(
				vformat("Parameter '%s' is an Object parameter of the tree itself", parameter),
				"Object parameters are the AnimationTree's own runtime objects (for example "
				"parameters/playback); this tool writes the value parameters (numbers, booleans, strings, vectors)");
		return Dictionary();
	}
	if ((target_usage & PROPERTY_USAGE_READ_ONLY) != 0) {
		r_error = MCPToolError::tool_state(vformat("Parameter '%s' is read-only", parameter),
				"This parameter is marked PROPERTY_USAGE_READ_ONLY by the tree; read it with "
				"editor_get_animation_tree_structure instead of writing it");
		return Dictionary();
	}

	// Shape a JSON object into the composite value the parameter declares (the
	// same step the node writers use), then the module's one conversion gate, so
	// the width of the slot the parameter stores is judged as well.
	Variant shaped;
	if (!shape_vector_from_json(p_value, target_type, parameter, "value", shaped, r_error)) {
		return Dictionary();
	}
	Variant converted;
	if (!coerce_to_property_type(shaped, target_type, converted, r_error, "value")) {
		return Dictionary();
	}

	const Variant before = p_tree->get(parameter);
	p_tree->set(parameter, converted);
	const Variant stored = p_tree->get(parameter);

	Dictionary out;
	out["parameter"] = parameter;
	out["type"] = Variant::get_type_name(target_type);
	out["value"] = serialize_variant(stored);
	if (_values_agree(stored, converted)) {
		Dictionary changed;
		changed["old"] = serialize_variant(before);
		changed["new"] = serialize_variant(stored);
		out["changed"] = changed;
	} else {
		// PLAYBOOK section 20.6: an engine setter that clamps or ignores must not
		// be reported as a successful write.
		Dictionary ignored;
		ignored["parameter"] = parameter;
		ignored["requested"] = serialize_variant(converted);
		ignored["stored"] = serialize_variant(stored);
		ignored["reason"] = "the engine's own parameter write did not store the requested value (the parameter is "
							"read-only for this node, or the node clamps it)";
		Array ignored_list;
		ignored_list.push_back(ignored);
		out["ignored"] = ignored_list;
		out["changed"] = Dictionary();
	}
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

static bool _require_float(const Dictionary &p_args, const String &p_key, double &r_out, MCPToolError &r_error) {
	if (!p_args.has(p_key)) {
		r_error = MCPToolError::invalid_params("Missing required parameter: " + p_key);
		return false;
	}
	return optional_float(p_args, p_key, 0.0, r_out, r_error);
}

static bool _require_name(const Dictionary &p_args, const String &p_key, String &r_out, MCPToolError &r_error) {
	if (!require_string(p_args, p_key, r_out, r_error)) {
		return false;
	}
	if (r_out.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params(vformat("'%s' must not be empty", p_key));
		return false;
	}
	return true;
}

static AnimationTree *_editor_animation_tree(const String &p_node_path, MCPToolError &r_error) {
	if (!require_editor_ui(r_error, "editor animation tree writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return nullptr;
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return nullptr;
	}
	return animation_tree_node(root, p_node_path, r_error);
}

static Variant _tool_create_animation_tree(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_name(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	String player_path;
	if (!optional_string(p_args, "animation_player_path", String(), player_path, r_error)) {
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", "AnimationTree", name, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor animation tree writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = MCPTools::edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return MCPTools::content_result(MCPTools::create_animation_tree_on(root, node_path, player_path,
			p_args.has("animation_player_path"), name, r_error));
}

static Variant _tool_add_state_machine_state(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_name(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	String state_name;
	if (!_require_name(p_args, "state_name", state_name, r_error)) {
		return Variant();
	}
	String state_machine_path;
	if (!optional_string(p_args, "state_machine_path", String(), state_machine_path, r_error)) {
		return Variant();
	}
	String state_type;
	if (!optional_string(p_args, "state_type", "animation", state_type, r_error)) {
		return Variant();
	}
	double position_x = 0.0;
	if (!optional_float(p_args, "position_x", 0.0, position_x, r_error)) {
		return Variant();
	}
	double position_y = 0.0;
	if (!optional_float(p_args, "position_y", 0.0, position_y, r_error)) {
		return Variant();
	}
	AnimationTree *tree = _editor_animation_tree(node_path, r_error);
	if (tree == nullptr) {
		return Variant();
	}
	return MCPTools::content_result(MCPTools::add_state_machine_state_on(tree, state_machine_path, state_name,
			state_type, position_x, position_y, r_error));
}

static Variant _tool_add_state_machine_transition(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_name(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	String from_state;
	if (!_require_name(p_args, "from_state", from_state, r_error)) {
		return Variant();
	}
	String to_state;
	if (!_require_name(p_args, "to_state", to_state, r_error)) {
		return Variant();
	}
	String state_machine_path;
	if (!optional_string(p_args, "state_machine_path", String(), state_machine_path, r_error)) {
		return Variant();
	}
	String switch_mode;
	if (!optional_string(p_args, "switch_mode", "immediate", switch_mode, r_error)) {
		return Variant();
	}
	String advance_mode;
	if (!optional_string(p_args, "advance_mode", "enabled", advance_mode, r_error)) {
		return Variant();
	}
	AnimationTree *tree = _editor_animation_tree(node_path, r_error);
	if (tree == nullptr) {
		return Variant();
	}
	return MCPTools::content_result(MCPTools::add_state_machine_transition_on(tree, state_machine_path, from_state,
			to_state, switch_mode, advance_mode, r_error));
}

static Variant _tool_remove_state_machine_state(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_name(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	String state_name;
	if (!_require_name(p_args, "state_name", state_name, r_error)) {
		return Variant();
	}
	String state_machine_path;
	if (!optional_string(p_args, "state_machine_path", String(), state_machine_path, r_error)) {
		return Variant();
	}
	AnimationTree *tree = _editor_animation_tree(node_path, r_error);
	if (tree == nullptr) {
		return Variant();
	}
	return MCPTools::content_result(MCPTools::remove_state_machine_state_on(tree, state_machine_path, state_name,
			r_error));
}

static Variant _tool_remove_state_machine_transition(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_name(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	String from_state;
	if (!_require_name(p_args, "from_state", from_state, r_error)) {
		return Variant();
	}
	String to_state;
	if (!_require_name(p_args, "to_state", to_state, r_error)) {
		return Variant();
	}
	String state_machine_path;
	if (!optional_string(p_args, "state_machine_path", String(), state_machine_path, r_error)) {
		return Variant();
	}
	AnimationTree *tree = _editor_animation_tree(node_path, r_error);
	if (tree == nullptr) {
		return Variant();
	}
	return MCPTools::content_result(MCPTools::remove_state_machine_transition_on(tree, state_machine_path,
			from_state, to_state, r_error));
}

static Variant _tool_set_blend_tree_node(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_name(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	String blend_tree_state;
	if (!_require_name(p_args, "blend_tree_state", blend_tree_state, r_error)) {
		return Variant();
	}
	String bt_node_name;
	if (!_require_name(p_args, "bt_node_name", bt_node_name, r_error)) {
		return Variant();
	}
	String bt_node_type;
	if (!_require_name(p_args, "bt_node_type", bt_node_type, r_error)) {
		return Variant();
	}
	String state_machine_path;
	if (!optional_string(p_args, "state_machine_path", String(), state_machine_path, r_error)) {
		return Variant();
	}
	double position_x = 0.0;
	if (!optional_float(p_args, "position_x", 0.0, position_x, r_error)) {
		return Variant();
	}
	double position_y = 0.0;
	if (!optional_float(p_args, "position_y", 0.0, position_y, r_error)) {
		return Variant();
	}
	AnimationTree *tree = _editor_animation_tree(node_path, r_error);
	if (tree == nullptr) {
		return Variant();
	}
	return MCPTools::content_result(MCPTools::set_blend_tree_node_on(tree, state_machine_path, blend_tree_state,
			bt_node_name, bt_node_type, position_x, position_y, r_error));
}

static Variant _tool_set_animation_tree_parameter(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!_require_name(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	String parameter;
	if (!_require_name(p_args, "parameter", parameter, r_error)) {
		return Variant();
	}
	if (!p_args.has("value")) {
		r_error = MCPToolError::invalid_params("Missing required parameter: value");
		return Variant();
	}
	const Variant value = p_args["value"];
	AnimationTree *tree = _editor_animation_tree(node_path, r_error);
	if (tree == nullptr) {
		return Variant();
	}
	return MCPTools::content_result(MCPTools::set_animation_tree_parameter_on(tree, parameter, value, r_error));
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
//
// The authoritative `description` and `inputSchema` of each tool are the
// contract entries of docs/tools_list.renamed.json, character for character; the
// schemas are *parsed* from the exact contract JSON instead of being rebuilt as
// a hand-written Dictionary, because gate 1 compares all three fields verbatim.
// ---------------------------------------------------------------------------
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_animation_tree_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

// The schemas of this group that carry an **integer** `default`
// (`editor_add_state_machine_state` and `editor_set_blend_tree_node` default
// `position_x`/`position_y` to `0`, `editor_add_state_machine_transition`
// defaults `priority` to the engine's own `1`).
//
// The rule and its reason lived here as a file-private static until TASK-034;
// `editor_add_audio_write` needed the same normalisation for `after_bus_index`
// and a group may not call another group's file-private helper (PLAYBOOK section
// 2.4), so it is now `MCPTools::schema_with_integer_defaults` in
// `tool_helpers.{h,cpp}` and the three call sites below name their fields.
static Dictionary _schema_with_position_defaults(const char *p_json) {
	// `0` becomes an `int`, so the Variant is INT and the wire writes `0`.
	return schema_with_integer_defaults(_schema_from_json(p_json),
			{ StringName("position_x"), StringName("position_y") });
}

static Dictionary _schema_with_transition_defaults(const char *p_json) {
	// `1` is the engine's own initial `int priority`
	// (animation_node_state_machine.h:62).
	return schema_with_integer_defaults(_schema_from_json(p_json), { StringName("priority") });
}

void register_editor_animation_tree_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_create_animation_tree", String::utf8(R"desc(创建 AnimationTree 节点)desc"));
		builder.channel("editor").verb("create").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"animation_player_path":{"description":"AnimationPlayer 节点路径","type":"string"},"name":{"default":"AnimationTree","type":"string"},"node_path":{"description":"父节点路径","type":"string"}},"required":["node_path"],"type":"object"})schema"));
		builder.handler(_tool_create_animation_tree).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_add_state_machine_state", String::utf8(R"desc(添加状态机状态)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_with_position_defaults(R"schema({"properties":{"animation":{"description":"state_type=animation 时该状态的动画名（当前库内）","type":"string"},"node_path":{"type":"string"},"position_x":{"default":0,"type":"number"},"position_y":{"default":0,"type":"number"},"state_machine_path":{"default":"","type":"string"},"state_name":{"type":"string"},"state_type":{"default":"animation","type":"string"}},"required":["node_path","state_name"],"type":"object"})schema"));
		builder.handler(_tool_add_state_machine_state).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_add_state_machine_transition", String::utf8(R"desc(添加状态机过渡)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_with_transition_defaults(R"schema({"properties":{"advance_condition":{"description":"该转移的 advance 布尔条件名；引擎注册为 AnimationTree 的 parameters/<状态机路径>/conditions/<名字> 参数（可用 editor_set_animation_tree_parameter 直接写入）","type":"string"},"advance_mode":{"default":"enabled","type":"string"},"from_state":{"type":"string"},"node_path":{"type":"string"},"priority":{"default":1,"type":"integer"},"state_machine_path":{"default":"","type":"string"},"switch_mode":{"default":"immediate","type":"string"},"to_state":{"type":"string"},"xfade_time":{"default":0.0,"type":"number"}},"required":["node_path","from_state","to_state"],"type":"object"})schema"));
		builder.handler(_tool_add_state_machine_transition).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_remove_state_machine_state", String::utf8(R"desc(删除状态机状态)desc"));
		builder.channel("editor").verb("remove").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"},"state_machine_path":{"default":"","type":"string"},"state_name":{"type":"string"}},"required":["node_path","state_name"],"type":"object"})schema"));
		builder.handler(_tool_remove_state_machine_state).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_remove_state_machine_transition", String::utf8(R"desc(删除状态机过渡)desc"));
		builder.channel("editor").verb("remove").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"from_state":{"type":"string"},"node_path":{"type":"string"},"state_machine_path":{"default":"","type":"string"},"to_state":{"type":"string"}},"required":["node_path","from_state","to_state"],"type":"object"})schema"));
		builder.handler(_tool_remove_state_machine_transition).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_blend_tree_node", String::utf8(R"desc(设置混合树节点)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_with_position_defaults(R"schema({"properties":{"animation":{"description":"bt_node_type=Animation 时该节点的动画名","type":"string"},"blend_tree_state":{"description":"BlendTree 所在的状态名称","type":"string"},"bt_node_name":{"type":"string"},"bt_node_type":{"type":"string"},"node_path":{"type":"string"},"position_x":{"default":0,"type":"number"},"position_y":{"default":0,"type":"number"},"state_machine_path":{"default":"","type":"string"}},"required":["node_path","blend_tree_state","bt_node_name","bt_node_type"],"type":"object"})schema"));
		builder.handler(_tool_set_blend_tree_node).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_animation_tree_parameter", String::utf8(R"desc(设置动画树参数)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"},"parameter":{"type":"string"},"value":{}},"required":["node_path","parameter","value"],"type":"object"})schema"));
		builder.handler(_tool_set_animation_tree_parameter).register_into(r_registry);
	}
}
