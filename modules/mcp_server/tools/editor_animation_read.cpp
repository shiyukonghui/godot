/**************************************************************************/
/*  editor_animation_read.cpp                                             */
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
#include "editor_animation_read.h"

#include "animation_shared.h"
#include "editor_animation_write.h"
#include "tool_helpers.h"

#include "core/io/json.h"
#include "core/string/ustring.h"
#include "core/variant/variant.h"
#include "scene/animation/animation_blend_tree.h"
#include "scene/animation/animation_node_state_machine.h"
#include "scene/resources/animation_library.h"

using namespace MCPTools;

namespace MCPTools {

static Array _sorted_state_names(const Ref<AnimationNodeStateMachine> &p_machine) {
	Array names;
	const TypedArray<StringName> listed = p_machine->get_node_list_as_typed_array();
	for (int i = 0; i < listed.size(); i++) {
		names.push_back(String(listed[i]));
	}
	names.sort();
	return names;
}

static Array _blend_tree_node_entries(const Ref<AnimationNodeBlendTree> &p_blend) {
	// `AnimationNodeBlendTree::nodes` is an `AHashMap`: its order is not
	// reproducible, so the list is sorted before it is answered.
	Vector<String> names;
	const LocalVector<StringName> listed = p_blend->get_node_list();
	for (uint32_t i = 0; i < listed.size(); i++) {
		names.push_back(String(listed[i]));
	}
	names.sort();
	Array out;
	for (int i = 0; i < names.size(); i++) {
		const StringName name(names[i]);
		const Ref<AnimationNode> node = p_blend->get_node(name);
		Dictionary entry;
		entry["name"] = names[i];
		entry["class"] = node.is_valid() ? node->get_class() : String();
		entry["state_type"] = animation_state_type_name(node);
		entry["position"] = serialize_variant(p_blend->get_node_position(name));
		AnimationNodeAnimation *animation_node = Object::cast_to<AnimationNodeAnimation>(node.ptr());
		if (animation_node != nullptr) {
			entry["animation"] = String(animation_node->get_animation());
		}
		out.push_back(entry);
	}
	return out;
}

static Array _blend_tree_connections(const Ref<AnimationNodeBlendTree> &p_blend) {
	LocalVector<AnimationNodeBlendTree::NodeConnection> connections;
	p_blend->get_node_connections(&connections);
	Array out;
	for (uint32_t i = 0; i < connections.size(); i++) {
		Dictionary entry;
		entry["input_node"] = String(connections[i].input_node);
		entry["input_index"] = connections[i].input_index;
		entry["output_node"] = String(connections[i].output_node);
		out.push_back(entry);
	}
	return out;
}

Dictionary animation_state_machine_structure(const Ref<AnimationNodeStateMachine> &p_machine, const String &p_path,
		HashSet<ObjectID> &r_visited) {
	Dictionary machine;
	machine["path"] = p_path;
	if (p_machine.is_null()) {
		machine["state_count"] = 0;
		machine["states"] = Array();
		machine["transitions"] = Array();
		machine["blend_trees"] = Array();
		machine["machines"] = Array();
		return machine;
	}

	const TypedArray<StringName> listed = p_machine->get_node_list_as_typed_array();
	Array states;
	Array blend_trees;
	Array machines;
	for (int i = 0; i < listed.size(); i++) {
		const StringName name = listed[i];
		const Ref<AnimationNode> node = p_machine->get_node(name);
		Dictionary entry;
		entry["name"] = String(name);
		entry["state_type"] = animation_state_type_name(node);
		entry["class"] = node.is_valid() ? node->get_class() : String();
		entry["position"] = serialize_variant(p_machine->get_node_position(name));
		AnimationNodeAnimation *animation_node = Object::cast_to<AnimationNodeAnimation>(node.ptr());
		if (animation_node != nullptr) {
			// The engine property the state really holds; the state's `animation`
			// member is not settable through this batch's schema (REPORT-033
			// section 7 D-3), so the read side reports it honestly rather than
			// hiding it.
			entry["animation"] = String(animation_node->get_animation());
		}
		states.push_back(entry);

		Ref<AnimationNodeBlendTree> blend = Object::cast_to<AnimationNodeBlendTree>(node.ptr());
		if (blend.is_valid()) {
			Dictionary tree;
			tree["state_name"] = String(name);
			tree["nodes"] = _blend_tree_node_entries(blend);
			tree["connections"] = _blend_tree_connections(blend);
			blend_trees.push_back(tree);
		}
		Ref<AnimationNodeStateMachine> nested = Object::cast_to<AnimationNodeStateMachine>(node.ptr());
		if (nested.is_valid()) {
			const String nested_path = p_path.is_empty() ? String(name) : p_path + "/" + String(name);
			if (nested->get_instance_id() == p_machine->get_instance_id() || r_visited.has(nested->get_instance_id())) {
				// A state machine that holds itself would otherwise recurse
				// forever; the answer names the cycle instead.
				Dictionary cycle;
				cycle["path"] = nested_path;
				cycle["cycle"] = true;
				machines.push_back(cycle);
			} else {
				r_visited.insert(nested->get_instance_id());
				machines.push_back(animation_state_machine_structure(nested, nested_path, r_visited));
			}
		}
	}
	// The engine's `Vector<Transition>` is ordered, so the list keeps that order
	// and carries the index the write side's `find_transition` reports.
	Array transitions;
	for (int i = 0; i < p_machine->get_transition_count(); i++) {
		const Ref<AnimationNodeStateMachineTransition> transition = p_machine->get_transition(i);
		Dictionary entry;
		entry["index"] = i;
		entry["from"] = String(p_machine->get_transition_from(i));
		entry["to"] = String(p_machine->get_transition_to(i));
		if (transition.is_valid()) {
			entry["switch_mode"] = animation_switch_mode_name(transition->get_switch_mode());
			entry["advance_mode"] = animation_advance_mode_name(transition->get_advance_mode());
		}
		transitions.push_back(entry);
	}

	machine["state_count"] = listed.size();
	machine["transition_count"] = p_machine->get_transition_count();
	machine["states"] = states;
	machine["state_names"] = _sorted_state_names(p_machine);
	machine["transitions"] = transitions;
	machine["blend_trees"] = blend_trees;
	machine["machines"] = machines;
	return machine;
}

Dictionary list_animations_on(Node *p_root, AnimationPlayer *p_player) {
	// `get_sorted_animation_list` is the engine's own alphabetical, flat list
	// (`animation_mixer.cpp:395`), and each entry is exactly what
	// `AnimationMixer::get_animation` / `has_animation` take - so the answer can
	// be fed into `editor_get_animation_info` or `editor_remove_animation`
	// without touching it.
	Dictionary out;
	out["node_path"] = relative_path(p_root, p_player);
	const LocalVector<StringName> flat = p_player->get_sorted_animation_list();
	Array animations;
	for (uint32_t i = 0; i < flat.size(); i++) {
		animations.push_back(String(flat[i]));
	}
	out["animations"] = animations;
	out["count"] = (int)animations.size();

	// The per-library breakdown behind the flat list: a named library prefixes
	// its animations with "<library>/" (`animation_mixer.cpp:162`).
	LocalVector<StringName> library_names;
	p_player->get_animation_library_list(&library_names);
	Array libraries;
	for (uint32_t i = 0; i < library_names.size(); i++) {
		const Ref<AnimationLibrary> library = p_player->get_animation_library(library_names[i]);
		Dictionary entry;
		entry["name"] = String(library_names[i]);
		Array names;
		if (library.is_valid()) {
			// `AnimationLibrary::animations` is an `RBMap` ordered by
			// `StringName::AlphCompare` (animation_library.h:48), so this list is
			// already deterministic.
			LocalVector<StringName> listed;
			library->get_animation_list(&listed);
			for (uint32_t n = 0; n < listed.size(); n++) {
				names.push_back(String(listed[n]));
			}
		}
		entry["animations"] = names;
		libraries.push_back(entry);
	}
	out["libraries"] = libraries;
	return out;
}

Dictionary animation_info_on(Node *p_root, AnimationPlayer *p_player, const String &p_animation_name,
		MCPToolError &r_error) {
	const Ref<Animation> animation = animation_named(p_player, p_animation_name);
	if (animation.is_null()) {
		Vector<String> known;
		const LocalVector<StringName> listed = p_player->get_sorted_animation_list();
		for (uint32_t i = 0; i < listed.size(); i++) {
			known.push_back(String(listed[i]));
		}
		r_error = MCPToolError::not_found(
				vformat("Animation '%s' on AnimationPlayer '%s'", p_animation_name, p_player->get_name()),
				vformat("AnimationMixer::get_animation does not answer that name. This player holds: %s "
						"(editor_list_animations answers the same list, and any entry can be passed here verbatim)",
						known.is_empty() ? String("(none)") : String(", ").join(known)));
		return Dictionary();
	}

	Dictionary out;
	out["node_path"] = relative_path(p_root, p_player);
	out["name"] = p_animation_name;
	out["length"] = animation->get_length();
	out["loop_mode"] = animation_loop_mode_name(animation->get_loop_mode());
	out["loop_mode_code"] = (int)animation->get_loop_mode();
	out["step"] = animation->get_step();
	const int track_count = animation->get_track_count();
	out["track_count"] = track_count;

	Array tracks;
	for (int i = 0; i < track_count; i++) {
		const Animation::TrackType track_type = animation->track_get_type(i);
		const int key_count = animation->track_get_key_count(i);
		Dictionary track;
		// `index`, `type` and `path` are the identifiers
		// `editor_set_animation_keyframe` (`track_index`) and
		// `editor_add_animation_track` (`track_type`) take, so the answer feeds
		// straight back.
		track["index"] = i;
		track["path"] = String(animation->track_get_path(i));
		track["type"] = animation_track_type_name(track_type);
		track["type_code"] = (int)track_type;
		track["key_count"] = key_count;
		if (track_type == Animation::TYPE_VALUE) {
			track["update_mode"] = animation_update_mode_name(animation->value_track_get_update_mode(i));
		}
		// `Animation::find_track` is the engine's own (path, type) lookup; the
		// write side's `previous_track_index` uses the same call, so a caller can
		// compare the two answers directly.
		track["find_track_index"] = animation->find_track(animation->track_get_path(i), track_type);

		Array keys;
		for (int k = 0; k < key_count; k++) {
			Dictionary key;
			key["time"] = animation->track_get_key_time(i, k);
			key["value"] = serialize_variant(animation->track_get_key_value(i, k));
			key["easing"] = animation->track_get_key_transition(i, k);
			keys.push_back(key);
		}
		track["keys"] = keys;
		tracks.push_back(track);
	}
	out["tracks"] = tracks;
	return out;
}

Dictionary animation_tree_structure_on(Node *p_root, AnimationTree *p_tree) {
	Dictionary out;
	out["node_path"] = relative_path(p_root, p_tree);
	out["type"] = p_tree->get_class();
	out["active"] = p_tree->is_active();
	const NodePath player_path = p_tree->get_animation_player();
	out["animation_player"] = String(player_path);
	// The engine resolves `animation_player` from the tree itself; the caller
	// gets the edited-scene spelling when it resolves, so the field can be fed
	// into the node-path argument of the animation tools verbatim.
	Node *player_node = p_tree->get_node_or_null(player_path);
	out["animation_player_node_path"] = player_node != nullptr ? relative_path(p_root, player_node) : String();

	const Ref<AnimationRootNode> root_node = p_tree->get_root_animation_node();
	out["tree_root"] = root_node.is_valid() ? root_node->get_class() : String();
	Ref<AnimationNodeStateMachine> machine = Object::cast_to<AnimationNodeStateMachine>(root_node.ptr());
	if (machine.is_valid()) {
		HashSet<ObjectID> visited;
		visited.insert(machine->get_instance_id());
		out["state_machine"] = animation_state_machine_structure(machine, String(), visited);
	}
	Ref<AnimationNodeBlendTree> blend = Object::cast_to<AnimationNodeBlendTree>(root_node.ptr());
	if (blend.is_valid()) {
		out["blend_tree_nodes"] = _blend_tree_node_entries(blend);
		out["blend_tree_connections"] = _blend_tree_connections(blend);
	}

	// The tree's writable values: its own `parameters/...` properties, with the
	// declared type of each, sorted. The names are exactly what
	// `editor_set_animation_tree_parameter` takes (with or without the prefix).
	List<PropertyInfo> properties;
	p_tree->get_property_list(&properties);
	const String prefix = Animation::PARAMETERS_BASE_PATH;
	Vector<String> parameter_names;
	for (const PropertyInfo &property : properties) {
		const String name = String(property.name);
		if (name.begins_with(prefix)) {
			parameter_names.push_back(name);
		}
	}
	parameter_names.sort();
	Array parameters;
	for (int i = 0; i < parameter_names.size(); i++) {
		Dictionary entry;
		entry["name"] = parameter_names[i];
		parameters.push_back(entry);
	}
	for (const PropertyInfo &property : properties) {
		const String name = String(property.name);
		if (!name.begins_with(prefix)) {
			continue;
		}
		for (int i = 0; i < parameters.size(); i++) {
			Dictionary entry = parameters[i];
			if (String(entry["name"]) != name) {
				continue;
			}
			entry["type"] = Variant::get_type_name(property.type);
			entry["read_only"] = (property.usage & PROPERTY_USAGE_READ_ONLY) != 0;
			parameters[i] = entry;
			break;
		}
	}
	out["parameters"] = parameters;
	out["parameter_count"] = parameters.size();
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

static AnimationPlayer *_editor_animation_player_for_read(const String &p_node_path, MCPToolError &r_error) {
	if (!require_editor_ui(r_error, "editor animation reads outside a running editor",
				"Start the MCP server inside the Godot editor to read editor state")) {
		return nullptr;
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return nullptr;
	}
	return animation_player_node(root, p_node_path, r_error);
}

static Node *_edited_root_for(const String &p_node_path, MCPToolError &r_error) {
	if (p_node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return nullptr;
	}
	if (!require_editor_ui(r_error, "editor animation reads outside a running editor",
				"Start the MCP server inside the Godot editor to read editor state")) {
		return nullptr;
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return nullptr;
	}
	return root;
}

static Variant _tool_list_animations(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	Node *root = _edited_root_for(node_path, r_error);
	if (root == nullptr) {
		return Variant();
	}
	AnimationPlayer *player = animation_player_node(root, node_path, r_error);
	if (player == nullptr) {
		return Variant();
	}
	return content_result(list_animations_on(root, player));
}

static Variant _tool_get_animation_info(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	String animation;
	if (!require_string(p_args, "animation", animation, r_error)) {
		return Variant();
	}
	if (animation.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'animation' must not be empty");
		return Variant();
	}
	AnimationPlayer *player = _editor_animation_player_for_read(node_path, r_error);
	if (player == nullptr) {
		return Variant();
	}
	Node *root = edited_scene_root();
	return content_result(animation_info_on(root, player, animation, r_error));
}

static Variant _tool_get_animation_tree_structure(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	Node *root = _edited_root_for(node_path, r_error);
	if (root == nullptr) {
		return Variant();
	}
	AnimationTree *tree = animation_tree_node(root, node_path, r_error);
	if (tree == nullptr) {
		return Variant();
	}
	return content_result(animation_tree_structure_on(root, tree));
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
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_animation_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_animation_read_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_list_animations", String::utf8(R"desc(列出所有动画)desc"));
		builder.channel("editor").verb("list").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"}},"required":["node_path"],"type":"object"})schema"));
		builder.handler(_tool_list_animations).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_get_animation_info", String::utf8(R"desc(获取动画的详细信息（时长、轨道、关键帧等）)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"animation":{"type":"string"},"node_path":{"type":"string"}},"required":["node_path","animation"],"type":"object"})schema"));
		builder.handler(_tool_get_animation_info).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_get_animation_tree_structure", String::utf8(R"desc(获取动画树结构)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"}},"required":["node_path"],"type":"object"})schema"));
		builder.handler(_tool_get_animation_tree_structure).register_into(r_registry);
	}
}
