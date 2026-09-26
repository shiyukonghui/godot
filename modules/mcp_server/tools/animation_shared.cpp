/**************************************************************************/
/*  animation_shared.cpp                                                  */
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
#include "animation_shared.h"

#include "tool_helpers.h"

#include "core/string/ustring.h"

namespace MCPTools {

String animation_track_type_name(Animation::TrackType p_type) {
	switch (p_type) {
		case Animation::TYPE_VALUE:
			return "value";
		case Animation::TYPE_POSITION_3D:
			return "position_3d";
		case Animation::TYPE_ROTATION_3D:
			return "rotation_3d";
		case Animation::TYPE_SCALE_3D:
			return "scale_3d";
		case Animation::TYPE_BLEND_SHAPE:
			return "blend_shape";
		case Animation::TYPE_METHOD:
			return "method";
		case Animation::TYPE_BEZIER:
			return "bezier";
		case Animation::TYPE_AUDIO:
			return "audio";
		case Animation::TYPE_ANIMATION:
			return "animation";
	}
	return "unknown";
}

bool animation_track_type_from_string(const String &p_type, Animation::TrackType &r_out, String &r_reason) {
	const String spelling = p_type.strip_edges().to_lower();
	if (spelling == "value") {
		r_out = Animation::TYPE_VALUE;
		return true;
	}
	if (spelling == "position_3d") {
		r_out = Animation::TYPE_POSITION_3D;
		return true;
	}
	if (spelling == "rotation_3d") {
		r_out = Animation::TYPE_ROTATION_3D;
		return true;
	}
	if (spelling == "scale_3d") {
		r_out = Animation::TYPE_SCALE_3D;
		return true;
	}
	if (spelling == "blend_shape") {
		r_out = Animation::TYPE_BLEND_SHAPE;
		return true;
	}
	if (spelling == "method") {
		r_out = Animation::TYPE_METHOD;
		return true;
	}
	if (spelling == "bezier") {
		r_out = Animation::TYPE_BEZIER;
		return true;
	}
	if (spelling == "audio") {
		r_out = Animation::TYPE_AUDIO;
		return true;
	}
	if (spelling == "animation") {
		r_out = Animation::TYPE_ANIMATION;
		return true;
	}
	// The 2D spellings the migration source accepted. A 2D track is a value
	// track in Godot 4; folding them into `TYPE_POSITION_3D` (what the migration
	// source did) makes the key value impossible to insert afterwards.
	if (spelling == "position_2d" || spelling == "rotation_2d" || spelling == "scale_2d") {
		r_out = Animation::TYPE_VALUE;
		return true;
	}
	r_reason = vformat("'track_type' must be one of the engine's own Animation::TrackType names (value, position_3d, "
					   "rotation_3d, scale_3d, blend_shape, method, bezier, audio, animation) or the 2D aliases "
					   "position_2d/rotation_2d/scale_2d (a 2D track is a value track); got '%s'",
			p_type);
	return false;
}

String animation_update_mode_name(Animation::UpdateMode p_mode) {
	switch (p_mode) {
		case Animation::UPDATE_CONTINUOUS:
			return "continuous";
		case Animation::UPDATE_DISCRETE:
			return "discrete";
		case Animation::UPDATE_CAPTURE:
			return "capture";
	}
	return "unknown";
}

bool animation_update_mode_from_string(const String &p_mode, Animation::UpdateMode &r_out, String &r_reason) {
	const String spelling = p_mode.strip_edges().to_lower();
	if (spelling == "continuous") {
		r_out = Animation::UPDATE_CONTINUOUS;
		return true;
	}
	if (spelling == "discrete") {
		r_out = Animation::UPDATE_DISCRETE;
		return true;
	}
	if (spelling == "capture") {
		r_out = Animation::UPDATE_CAPTURE;
		return true;
	}
	r_reason = vformat("'update_mode' must be the engine's own Animation::UpdateMode name (continuous, discrete or "
					   "capture); got '%s'",
			p_mode);
	return false;
}

String animation_loop_mode_name(Animation::LoopMode p_mode) {
	switch (p_mode) {
		case Animation::LOOP_NONE:
			return "none";
		case Animation::LOOP_LINEAR:
			return "linear";
		case Animation::LOOP_PINGPONG:
			return "pingpong";
	}
	return "unknown";
}

String animation_switch_mode_name(AnimationNodeStateMachineTransition::SwitchMode p_mode) {
	switch (p_mode) {
		case AnimationNodeStateMachineTransition::SWITCH_MODE_IMMEDIATE:
			return "immediate";
		case AnimationNodeStateMachineTransition::SWITCH_MODE_SYNC:
			return "sync";
		case AnimationNodeStateMachineTransition::SWITCH_MODE_AT_END:
			return "at_end";
	}
	return "unknown";
}

bool animation_switch_mode_from_string(const String &p_mode, AnimationNodeStateMachineTransition::SwitchMode &r_out, String &r_reason) {
	const String spelling = p_mode.strip_edges().to_lower();
	if (spelling == "immediate" || spelling == "switch_mode_immediate") {
		r_out = AnimationNodeStateMachineTransition::SWITCH_MODE_IMMEDIATE;
		return true;
	}
	if (spelling == "sync" || spelling == "switch_mode_sync") {
		r_out = AnimationNodeStateMachineTransition::SWITCH_MODE_SYNC;
		return true;
	}
	if (spelling == "at_end" || spelling == "switch_mode_at_end") {
		r_out = AnimationNodeStateMachineTransition::SWITCH_MODE_AT_END;
		return true;
	}
	r_reason = vformat("'switch_mode' must be the engine's own SwitchMode name (immediate, sync or at_end - "
					   "AnimationNodeStateMachineTransition::SwitchMode); got '%s'",
			p_mode);
	return false;
}

String animation_advance_mode_name(AnimationNodeStateMachineTransition::AdvanceMode p_mode) {
	switch (p_mode) {
		case AnimationNodeStateMachineTransition::ADVANCE_MODE_DISABLED:
			return "disabled";
		case AnimationNodeStateMachineTransition::ADVANCE_MODE_ENABLED:
			return "enabled";
		case AnimationNodeStateMachineTransition::ADVANCE_MODE_AUTO:
			return "auto";
	}
	return "unknown";
}

bool animation_advance_mode_from_string(const String &p_mode, AnimationNodeStateMachineTransition::AdvanceMode &r_out, String &r_reason) {
	const String spelling = p_mode.strip_edges().to_lower();
	if (spelling == "disabled" || spelling == "advance_mode_disabled") {
		r_out = AnimationNodeStateMachineTransition::ADVANCE_MODE_DISABLED;
		return true;
	}
	if (spelling == "enabled" || spelling == "advance_mode_enabled") {
		r_out = AnimationNodeStateMachineTransition::ADVANCE_MODE_ENABLED;
		return true;
	}
	if (spelling == "auto" || spelling == "advance_mode_auto") {
		r_out = AnimationNodeStateMachineTransition::ADVANCE_MODE_AUTO;
		return true;
	}
	r_reason = vformat("'advance_mode' must be the engine's own AdvanceMode name (disabled, enabled or auto - "
					   "AnimationNodeStateMachineTransition::AdvanceMode); got '%s'",
			p_mode);
	return false;
}

String animation_state_type_name(const Ref<AnimationNode> &p_node) {
	if (p_node.is_null()) {
		return "null";
	}
	if (Object::cast_to<AnimationNodeStateMachine>(p_node.ptr()) != nullptr) {
		return "state_machine";
	}
	if (Object::cast_to<AnimationNodeBlendTree>(p_node.ptr()) != nullptr) {
		return "blend_tree";
	}
	if (Object::cast_to<AnimationNodeAnimation>(p_node.ptr()) != nullptr) {
		return "animation";
	}
	return "other";
}

bool animation_state_type_from_string(const String &p_type, Ref<AnimationNode> &r_out, String &r_reason) {
	const String spelling = p_type.strip_edges().to_lower();
	if (spelling == "animation" || spelling == "animationnodeanimation") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeAnimation));
		return true;
	}
	if (spelling == "blend_tree" || spelling == "blendtree" || spelling == "animationnodeblendtree") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeBlendTree));
		return true;
	}
	if (spelling == "state_machine" || spelling == "statemachine" || spelling == "animationnodestatemachine") {
		r_out = Ref<AnimationNode>(memnew(AnimationNodeStateMachine));
		return true;
	}
	r_reason = vformat("'state_type' must name the engine class the state holds: animation (AnimationNodeAnimation), "
					   "blend_tree (AnimationNodeBlendTree) or state_machine (AnimationNodeStateMachine); got '%s'",
			p_type);
	return false;
}

AnimationPlayer *animation_player_node(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the edited scene's node paths");
		return nullptr;
	}
	AnimationPlayer *player = Object::cast_to<AnimationPlayer>(node);
	if (player == nullptr) {
		r_error = MCPToolError::invalid_params(vformat("Node '%s' is a %s, not an AnimationPlayer", p_node_path,
				node->get_class()));
		return nullptr;
	}
	return player;
}

AnimationTree *animation_tree_node(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the edited scene's node paths");
		return nullptr;
	}
	AnimationTree *tree = Object::cast_to<AnimationTree>(node);
	if (tree == nullptr) {
		r_error = MCPToolError::invalid_params(vformat("Node '%s' is a %s, not an AnimationTree", p_node_path,
				node->get_class()));
		return nullptr;
	}
	return tree;
}

String animation_state_machine_path_normalize(const String &p_path) {
	String path = p_path.strip_edges();
	// The engine's own parameter prefix (Animation::PARAMETERS_BASE_PATH,
	// scene/resources/animation.h:45) and a trailing separator are folded away so
	// the spelling this module answers with is the one it also accepts.
	if (path.begins_with(Animation::PARAMETERS_BASE_PATH)) {
		path = path.substr(Animation::PARAMETERS_BASE_PATH.length());
	}
	while (path.ends_with("/")) {
		path = path.substr(0, path.length() - 1);
	}
	if (path == ".") {
		return String();
	}
	return path;
}

Ref<AnimationNodeStateMachine> animation_state_machine_at(const Ref<AnimationRootNode> &p_root,
		const String &p_state_machine_path, MCPToolError &r_error) {
	if (p_root.is_null()) {
		r_error = MCPToolError::tool_state("The AnimationTree has no root animation node (tree_root is null)",
				"Create a root node first - editor_create_animation_tree does that, or set the AnimationTree's "
				"'tree_root' to an AnimationNodeStateMachine / AnimationNodeBlendTree");
		return Ref<AnimationNodeStateMachine>();
	}
	Ref<AnimationNodeStateMachine> machine = Object::cast_to<AnimationNodeStateMachine>(p_root.ptr());
	if (machine.is_null()) {
		r_error = MCPToolError::invalid_params(vformat(
				"The AnimationTree's root node is a %s, not an AnimationNodeStateMachine, so 'state_machine_path' "
				"cannot address a state machine",
				p_root->get_class()));
		return Ref<AnimationNodeStateMachine>();
	}
	const String path = animation_state_machine_path_normalize(p_state_machine_path);
	if (path.is_empty()) {
		return machine;
	}
	const Vector<String> parts = path.split("/");
	for (int i = 0; i < parts.size(); i++) {
		const StringName part(parts[i]);
		if (!machine->has_node(part)) {
			const Array known = machine->get_node_list_as_typed_array();
			Vector<String> listed;
			for (int k = 0; k < known.size(); k++) {
				listed.push_back(String(known[k]));
			}
			r_error = MCPToolError::not_found(
					vformat("State '%s' (segment %d of state_machine_path '%s') in the state machine", parts[i], i + 1, path),
					vformat("'state_machine_path' walks nested state machines by state name; this state machine holds: %s",
							listed.is_empty() ? String("(no states yet)") : String(", ").join(listed)));
			return Ref<AnimationNodeStateMachine>();
		}
		Ref<AnimationNode> child = machine->get_node(part);
		Ref<AnimationNodeStateMachine> nested = Object::cast_to<AnimationNodeStateMachine>(child.ptr());
		if (nested.is_null()) {
			r_error = MCPToolError::invalid_params(vformat(
					"State '%s' of state_machine_path '%s' holds a %s, not an AnimationNodeStateMachine",
					parts[i], path, child.is_valid() ? child->get_class() : String("null")));
			return Ref<AnimationNodeStateMachine>();
		}
		machine = nested;
	}
	return machine;
}

} // namespace MCPTools
