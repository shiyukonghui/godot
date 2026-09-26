/**************************************************************************/
/*  running_game_navigation_write.cpp                                     */
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
#include "running_game_navigation_write.h"

#include "../mcp_deferred.h"
#include "tool_helpers.h"

#include "core/io/json.h"
#include "core/object/object.h"
#include "core/variant/typed_array.h"
#include "scene/2d/navigation/navigation_agent_2d.h"
#include "scene/2d/node_2d.h"
#include "scene/2d/physics/character_body_2d.h"
#include "scene/3d/navigation/navigation_agent_3d.h"
#include "scene/3d/node_3d.h"
#include "scene/3d/physics/character_body_3d.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/resources/3d/world_3d.h"
#include "scene/resources/world_2d.h"
#include "servers/navigation_2d/navigation_server_2d.h"
#include "servers/navigation_3d/navigation_server_3d.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-036 section 3: the engine reference behind the one tool.
//
//   * `NavigationAgent3D::set_target_position` / `get_next_path_position` /
//     `is_navigation_finished` (`scene/3d/navigation/navigation_agent_3d.h:206/
//     229/240`) and their 2D pair (`navigation_agent_2d.h:183/206/217`) are the
//     engine's own path-following loop; the agent owns the pathfinding query
//     (`get_current_navigation_path`, `:233/:210`) and the path is recomputed by
//     `NavigationServer*` each frame;
//   * without an agent, `NavigationServer3D::map_get_path`
//     (`servers/navigation_3d/navigation_server_3d.h:90`) answers the corridor
//     polyline for the map the player's `World3D` owns
//     (`scene/resources/3d/world_3d.h:74`, `world_2d.h:64`), and the tool walks
//     its waypoints;
//   * `NavigationServer3D::map_get_regions`
//     (`navigation_server_3d.h:98`) is the engine's own "has this map any
//     navigation data"; an empty list is a `-32000` refusal, because moving
//     straight to a target in a world without navigation data is not
//     pathfinding and the tool is forbidden to pretend it is;
//   * `CharacterBody2D`/`CharacterBody3D` are moved through `velocity` +
//     `move_and_slide()` (their own movement API); every other `Node2D`/`Node3D`
//     is advanced by `speed * delta` per frame. The migration source did the
//     latter for both and **never touched navigation at all**
//     (`addons/godot_mcp_rs/mcp_runtime_agent.gd:561-623`, which moved straight
//     towards the target and only handled `Vector2`).
//   * holding the player across frames is done with its `ObjectID` (GDR-20
//     point 7): the migration source held a bare node reference.
// ---------------------------------------------------------------------------

namespace {

// The first descendant (including `p_root` itself) whose name is `p_name`.
Node *find_descendant_by_name(Node *p_root, const String &p_name) {
	if (p_root == nullptr) {
		return nullptr;
	}
	if (String(p_root->get_name()) == p_name) {
		return p_root;
	}
	for (int i = 0; i < p_root->get_child_count(); i++) {
		Node *found = find_descendant_by_name(p_root->get_child(i), p_name);
		if (found != nullptr) {
			return found;
		}
	}
	return nullptr;
}

// The first descendant (including `p_root`) that `is_class(p_class)`.
Node *find_descendant_by_class(Node *p_root, const String &p_class) {
	if (p_root == nullptr) {
		return nullptr;
	}
	if (p_root->is_class(p_class)) {
		return p_root;
	}
	for (int i = 0; i < p_root->get_child_count(); i++) {
		Node *found = find_descendant_by_class(p_root->get_child(i), p_class);
		if (found != nullptr) {
			return found;
		}
	}
	return nullptr;
}

// The navigation agent of a player that owns one: the player itself or the
// first `NavigationAgent2D`/`NavigationAgent3D` below it (the shape the editor's
// own navigation setup produces).
Node *find_player_agent(Node *p_player, bool p_is_3d, const String &p_player_path) {
	const char *agent_class = p_is_3d ? "NavigationAgent3D" : "NavigationAgent2D";
	Node *agent = p_player->is_class(agent_class) ? p_player : find_descendant_by_class(p_player, agent_class);
	if (agent != nullptr && !agent->is_inside_tree()) {
		// An agent outside the tree has no map; it cannot drive anything.
		agent = nullptr;
	}
	(void)p_player_path;
	return agent;
}

// The component reader of one `{x,y[,z]}` member. A missing component and a
// component that cannot fill the `real_t` slot are both `-32602`, naming the
// member.
bool read_component(const Dictionary &p_object, const String &p_key, const String &p_parameter_name, double &r_out,
		MCPToolError &r_error) {
	if (!p_object.has(p_key)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' names a position, so it must carry '%s'; it has only [%s]", p_parameter_name, p_key,
				"x/y/z members"));
		return false;
	}
	const Variant raw = p_object[p_key];
	if (raw.get_type() != Variant::FLOAT && raw.get_type() != Variant::INT) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s.%s' must be a number, got %s", p_parameter_name, p_key,
				Variant::get_type_name(raw.get_type())));
		return false;
	}
	const double value = (double)raw;
	if (!value_fits_slot(Variant(value), ValueSlot::REAL_T, p_parameter_name + "." + p_key,
				"the real_t member a node position is stored in", r_error)) {
		return false;
	}
	r_out = value;
	return true;
}

// The node's current position as a `Vector3` (a 2D node answers `z = 0`).
Vector3 node_position(Node *p_node, bool p_is_3d) {
	if (p_is_3d) {
		if (Node3D *node = Object::cast_to<Node3D>(p_node)) {
			return node->get_global_position();
		}
		return Vector3();
	}
	if (Node2D *node = Object::cast_to<Node2D>(p_node)) {
		const Vector2 position = node->get_global_position();
		return Vector3(position.x, position.y, 0.0);
	}
	return Vector3();
}

// Writes the node's position.
void set_node_position(Node *p_node, bool p_is_3d, const Vector3 &p_position) {
	if (p_is_3d) {
		if (Node3D *node = Object::cast_to<Node3D>(p_node)) {
			node->set_global_position(p_position);
		}
		return;
	}
	if (Node2D *node = Object::cast_to<Node2D>(p_node)) {
		node->set_global_position(Vector2(p_position.x, p_position.y));
	}
}

Dictionary position_record(const Vector3 &p_position, bool p_is_3d) {
	Dictionary out;
	out["x"] = p_position.x;
	out["y"] = p_position.y;
	if (p_is_3d) {
		out["z"] = p_position.z;
	}
	return out;
}

} // namespace

namespace MCPTools {

bool move_is_3d(const Object *p_node) {
	return p_node != nullptr && p_node->is_class("Node3D");
}

Node *resolve_move_player(SceneTree *p_tree, Node *p_root, const String &p_player_path, MCPToolError &r_error) {
	if (!p_player_path.strip_edges().is_empty()) {
		Node *node = p_tree != nullptr ? resolve_game_node(p_tree, p_root, p_player_path)
									   : find_node(p_root, p_player_path);
		if (node == nullptr) {
			r_error = MCPToolError::not_found(vformat("Player node '%s'", p_player_path),
					"Call running_game_get_scene_tree to list the nodes of the running scene, and pass 'player_path' as "
					"one of them");
			return nullptr;
		}
		if (!move_is_3d(node) && !node->is_class("Node2D")) {
			r_error = MCPToolError::invalid_params(vformat(
					"Player node '%s' is a %s: this tool moves a Node2D or a Node3D (it needs a position)", p_player_path,
					node->get_class()));
			return nullptr;
		}
		return node;
	}

	// The heuristic the migration source documented (`mcp_runtime_agent.gd:571-579`),
	// kept engine-first: the engine's movable character classes win over a bare
	// node name when the name search finds something that cannot move.
	Node *named = find_descendant_by_name(p_root, "Player");
	if (named != nullptr && (move_is_3d(named) || named->is_class("Node2D"))) {
		return named;
	}
	Node *third = find_descendant_by_class(p_root, "CharacterBody3D");
	if (third == nullptr) {
		third = find_descendant_by_class(p_root, "CharacterBody2D");
	}
	if (third == nullptr) {
		third = find_descendant_by_class(p_root, "Node3D");
	}
	if (third == nullptr) {
		third = find_descendant_by_class(p_root, "Node2D");
	}
	if (third != nullptr) {
		return third;
	}
	r_error = MCPToolError::not_found("A movable player node in the running scene",
			"Pass 'player_path' (running_game_get_scene_tree lists the nodes): the tool looks for a node named 'Player' "
			"and then for the first CharacterBody2D/CharacterBody3D");
	return nullptr;
}

bool move_target_from_value(SceneTree *p_tree, Node *p_root, const Variant &p_target, bool p_is_3d,
		Vector3 &r_target_3d, Vector2 &r_target_2d, String &r_source, MCPToolError &r_error) {
	switch (p_target.get_type()) {
		case Variant::STRING: {
			const String path = p_target;
			Node *node = p_tree != nullptr ? resolve_game_node(p_tree, p_root, path) : find_node(p_root, path);
			if (node == nullptr) {
				r_error = MCPToolError::not_found(vformat("Target node '%s'", path),
						"Call running_game_get_scene_tree to list the nodes of the running scene, and pass 'target' as "
						"one of them or as an object of coordinates ({x,y} in 2D, {x,y,z} in 3D)");
				return false;
			}
			if (!move_is_3d(node) && !node->is_class("Node2D")) {
				r_error = MCPToolError::invalid_params(vformat(
						"Target node '%s' is a %s and has no position: name a Node2D/Node3D or pass an object of "
						"coordinates",
						path, node->get_class()));
				return false;
			}
			if (move_is_3d(node) != p_is_3d) {
				r_error = MCPToolError::invalid_params(vformat(
						"Target node '%s' is a %s but the player is %s: both must live in the same dimension", path,
						node->get_class(), p_is_3d ? "3D" : "2D"));
				return false;
			}
			r_target_3d = node_position(node, p_is_3d);
			r_target_2d = Vector2(r_target_3d.x, r_target_3d.y);
			r_source = "node_path:" + path;
			return true;
		}
		case Variant::VECTOR2: {
			if (p_is_3d) {
				r_error = MCPToolError::invalid_params(
						"'target' is a Vector2 but the player is a Node3D: pass {x,y,z}");
				return false;
			}
			r_target_2d = p_target;
			r_target_3d = Vector3(r_target_2d.x, r_target_2d.y, 0.0);
			r_source = "vector2";
			return true;
		}
		case Variant::VECTOR3: {
			if (!p_is_3d) {
				r_error = MCPToolError::invalid_params(
						"'target' is a Vector3 but the player is a Node2D: pass {x,y}");
				return false;
			}
			r_target_3d = p_target;
			r_source = "vector3";
			return true;
		}
		case Variant::DICTIONARY: {
			const Dictionary object = p_target;
			double x = 0.0;
			double y = 0.0;
			if (!read_component(object, "x", "target", x, r_error)) {
				return false;
			}
			if (!read_component(object, "y", "target", y, r_error)) {
				return false;
			}
			double z = 0.0;
			if (p_is_3d) {
				if (!read_component(object, "z", "target", z, r_error)) {
					return false;
				}
			} else if (object.has("z")) {
				r_error = MCPToolError::invalid_params(
						"'target' carries 'z' but the player is a Node2D: pass {x,y} (a z member would be ignored, and "
						"this module never ignores a supplied value)");
				return false;
			}
			r_target_3d = Vector3(x, y, z);
			r_target_2d = Vector2(x, y);
			r_source = "coordinates";
			return true;
		}
		default:
			r_error = MCPToolError::invalid_params(vformat(
					"'target' must be a node path (string) or an object of coordinates ({x,y} in 2D, {x,y,z} in 3D), got %s",
					Variant::get_type_name(p_target.get_type())));
			return false;
	}
}

double move_speed_of(Node *p_player, double p_agent_max_speed, bool p_run, String &r_source) {
	double base = 0.0;
	if (p_agent_max_speed > 0.0) {
		base = p_agent_max_speed;
		r_source = "navigation_agent_max_speed";
	} else if (p_player != nullptr && object_has_property(p_player, StringName("speed"))) {
		const Variant value = p_player->get(StringName("speed"));
		if (value.get_type() == Variant::FLOAT || value.get_type() == Variant::INT) {
			const double speed = (double)value;
			if (speed > 0.0) {
				base = speed;
				r_source = "player_speed";
			}
		}
	}
	if (base <= 0.0) {
		base = 200.0;
		r_source = "default_200";
	}
	return p_run ? base * 2.0 : base;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The deferred movement task
// ---------------------------------------------------------------------------

namespace {

const double MOVE_ARRIVAL_RADIUS_DEFAULT = 10.0;
// A generous cap so a request whose framework deadline was disabled cannot loop
// forever; the caller's `timeout` (the framework's own deadline) is the real
// bound.
const int64_t MOVE_MAX_FRAMES = 100000;
const int MOVE_SAMPLE_LIMIT = 32;

class MovePlayerToTargetTask : public MCPDeferred::Task {
public:
	MovePlayerToTargetTask(ObjectID p_player_id, const String &p_player_path, bool p_is_3d, const Vector3 &p_target,
			double p_arrival_radius, double p_speed, const String &p_speed_source, bool p_run, bool p_look_at_target,
			ObjectID p_camera_id, const String &p_camera_path, const Vector3 &p_camera_offset, bool p_has_camera,
			ObjectID p_agent_id, const String &p_navigation_source, const Vector<Vector3> &p_path, int p_map_regions,
			uint64_t p_timeout_ms) :
			player_id(p_player_id),
			player_path(p_player_path),
			is_3d(p_is_3d),
			target(p_target),
			arrival_radius(p_arrival_radius),
			speed(p_speed),
			speed_source(p_speed_source),
			run(p_run),
			look_at_target(p_look_at_target),
			camera_id(p_camera_id),
			camera_path(p_camera_path),
			camera_offset(p_camera_offset),
			has_camera(p_has_camera),
			agent_id(p_agent_id),
			navigation_source(p_navigation_source),
			path(p_path),
			map_regions(p_map_regions),
			timeout_ms(p_timeout_ms) {
		start_position = node_position(Object::cast_to<Node>(ObjectDB::get_instance(player_id)), is_3d);
		current_position = start_position;
	}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		Node *player = Object::cast_to<Node>(ObjectDB::get_instance(player_id));
		if (player == nullptr) {
			return MCPDeferred::TickResult::failed(MCPToolError::not_found(
					vformat("Player node '%s'", player_path),
					"The player was removed while it was moving; re-open the scene and call the tool again"));
		}

		const double delta = previous_ms == 0 ? 0.0 : MIN((double)(p_now_ms - previous_ms) / 1000.0, 0.1);
		previous_ms = p_now_ms;
		current_position = node_position(player, is_3d);
		sample(p_frame, current_position);

		const double remaining = (is_3d ? Vector3(target - current_position).length()
									   : Vector2(target.x - current_position.x, target.y - current_position.y).length());
		if (remaining <= arrival_radius) {
			return MCPDeferred::TickResult::done(build_result(true, player));
		}
		if (frames >= MOVE_MAX_FRAMES) {
			return MCPDeferred::TickResult::done(build_result(false, player));
		}

		const Vector3 waypoint = next_waypoint(player);
		Vector3 direction = waypoint - current_position;
		if (is_3d) {
			direction.z = 0.0;
			if (direction.length() > 0.0) {
				direction.normalize();
			}
		} else {
			direction.z = 0.0;
			if (direction.length() > 0.0) {
				direction.normalize();
			}
		}

		if (is_3d) {
			if (CharacterBody3D *body = Object::cast_to<CharacterBody3D>(player)) {
				body->set_velocity(direction * speed);
				body->move_and_slide();
				movement = "character_body_move_and_slide";
			} else {
				Vector3 step = direction * speed * delta;
				const double step_length = step.length();
				if (step_length >= remaining) {
					step = target - current_position;
				}
				set_node_position(player, true, current_position + Vector3(step.x, 0.0, step.z));
				movement = "direct_position_step";
			}
		} else {
			if (CharacterBody2D *body = Object::cast_to<CharacterBody2D>(player)) {
				body->set_velocity(Vector2(direction.x, direction.y) * (real_t)speed);
				body->move_and_slide();
				movement = "character_body_move_and_slide";
			} else {
				Vector2 step = Vector2(direction.x, direction.y) * (real_t)(speed * delta);
				if (step.length() >= remaining) {
					step = Vector2(target.x - current_position.x, target.y - current_position.y);
				}
				set_node_position(player, false, current_position + Vector3(step.x, step.y, 0.0));
				movement = "direct_position_step";
			}
		}

		if (look_at_target) {
			const Vector3 facing = target - current_position;
			if (is_3d) {
				if (Object::cast_to<Node3D>(player) != nullptr) {
					player->set(StringName("rotation"), Vector3(0.0, Math::atan2(-facing.x, -facing.z), 0.0));
				}
			} else {
				if (Object::cast_to<Node2D>(player) != nullptr) {
					player->set(StringName("rotation"), Math::atan2(facing.y, facing.x));
				}
			}
		}

		follow_camera(look_at_target);
		frames++;
		return MCPDeferred::TickResult::pending();
	}

	uint64_t get_timeout_ms() const override { return timeout_ms; }

	String describe() const override { return vformat("moving '%s' to the target", player_path); }

private:
	Vector3 next_waypoint(Node *p_player) {
		if (agent_id.is_valid()) {
			Object *object = ObjectDB::get_instance(agent_id);
			if (object != nullptr) {
				if (NavigationAgent3D *agent = Object::cast_to<NavigationAgent3D>(object)) {
					if (!agent->is_navigation_finished()) {
						return agent->get_next_path_position();
					}
					return target;
				}
				if (NavigationAgent2D *agent = Object::cast_to<NavigationAgent2D>(object)) {
					if (!agent->is_navigation_finished()) {
						const Vector2 next = agent->get_next_path_position();
						return Vector3(next.x, next.y, 0.0);
					}
					return target;
				}
			}
		}
		// The precomputed `map_get_path` polyline.
		if (path.is_empty()) {
			return target;
		}
		while (path_index < path.size()) {
			const Vector3 waypoint = path[path_index];
			const double distance = is_3d
					? Vector3(waypoint - current_position).length()
					: Vector2(waypoint.x - current_position.x, waypoint.y - current_position.y).length();
			if (distance > 1.0) {
				return waypoint;
			}
			path_index++;
		}
		return target;
	}

	void sample(int64_t p_frame, const Vector3 &p_position) {
		if (samples.size() >= MOVE_SAMPLE_LIMIT) {
			return;
		}
		if (samples.size() >= 8 && (frames % 15) != 0) {
			return;
		}
		const double remaining = is_3d ? Vector3(target - p_position).length()
									   : Vector2(target.x - p_position.x, target.y - p_position.y).length();
		Dictionary entry;
		entry["frame"] = p_frame;
		entry["position"] = position_record(p_position, is_3d);
		entry["distance_to_target"] = remaining;
		samples.push_back(entry);
	}

	void follow_camera(bool p_look) {
		(void)p_look;
		if (!has_camera || !camera_id.is_valid()) {
			return;
		}
		Object *object = ObjectDB::get_instance(camera_id);
		if (object == nullptr) {
			return;
		}
		Node *camera = Object::cast_to<Node>(object);
		if (camera == nullptr) {
			return;
		}
		set_node_position(camera, is_3d, current_position + camera_offset);
		if (!camera_made_current && camera->has_method("make_current")) {
			camera->call("make_current");
			camera_made_current = true;
		}
	}

	Dictionary build_result(bool p_reached, Node *p_player) {
		const Vector3 final_position = p_player != nullptr ? node_position(p_player, is_3d) : current_position;
		const double traveled = is_3d
				? Vector3(final_position - start_position).length()
				: Vector2(final_position.x - start_position.x, final_position.y - start_position.y).length();

		Dictionary navigation;
		navigation["path_source"] = navigation_source;
		navigation["map_region_count"] = map_regions;
		navigation["path_point_count"] = path.size();
		if (agent_id.is_valid()) {
			Object *object = ObjectDB::get_instance(agent_id);
			if (NavigationAgent3D *agent = Object::cast_to<NavigationAgent3D>(object)) {
				navigation["agent_path_point_count"] = agent->get_current_navigation_path().size();
				navigation["agent_path_index"] = agent->get_current_navigation_path_index();
			} else if (NavigationAgent2D *agent = Object::cast_to<NavigationAgent2D>(object)) {
				navigation["agent_path_point_count"] = agent->get_current_navigation_path().size();
				navigation["agent_path_index"] = agent->get_current_navigation_path_index();
			}
		}

		// The final sample, so the observable series always ends on the real
		// final position even when the sampling budget is used up.
		if (samples.size() > 0) {
			Dictionary last = (Dictionary)samples[samples.size() - 1];
			if (last.get("position", Dictionary()) != position_record(final_position, is_3d)) {
				Dictionary entry;
				entry["frame"] = frames;
				entry["position"] = position_record(final_position, is_3d);
				entry["distance_to_target"] = is_3d
						? Vector3(target - final_position).length()
						: Vector2(target.x - final_position.x, target.y - final_position.y).length();
				samples.push_back(entry);
			}
		}

		Dictionary out;
		out["reached"] = p_reached;
		out["player_path"] = p_player != nullptr ? String(p_player->get_path()) : player_path;
		out["dimension"] = is_3d ? "3d" : "2d";
		out["target"] = position_record(target, is_3d);
		out["target_source"] = target_source;
		out["arrival_radius"] = arrival_radius;
		out["speed"] = speed;
		out["speed_source"] = speed_source;
		out["run"] = run;
		out["run_multiplier"] = 2.0;
		out["movement"] = movement;
		out["frames"] = frames;
		out["navigation"] = navigation;
		out["start_position"] = position_record(start_position, is_3d);
		out["final_position"] = position_record(final_position, is_3d);
		out["distance_traveled"] = traveled;
		out["positions_sampled"] = samples;
		out["position_sample_count"] = samples.size();
		out["verify_tool"] = "running_game_get_node_properties";
		if (has_camera) {
			Dictionary camera;
			camera["camera_path"] = camera_path;
			camera["following"] = ObjectDB::get_instance(camera_id) != nullptr;
			camera["made_current"] = camera_made_current;
			out["camera"] = camera;
		}
		if (!p_reached) {
			out["timeout"] = true;
			out["message"] = "The movement budget of this request ended before the player reached the target; the "
							 "positions above are the real path it covered";
		}
		return out;
	}

public:
	// Set by the handler: how the target was spelled.
	String target_source;

private:
	ObjectID player_id;
	String player_path;
	bool is_3d = false;
	Vector3 target;
	double arrival_radius = MOVE_ARRIVAL_RADIUS_DEFAULT;
	double speed = 0.0;
	String speed_source;
	bool run = false;
	bool look_at_target = false;
	ObjectID camera_id;
	String camera_path;
	Vector3 camera_offset;
	bool has_camera = false;
	bool camera_made_current = false;
	ObjectID agent_id;
	String navigation_source;
	Vector<Vector3> path;
	int path_index = 0;
	int map_regions = 0;
	uint64_t timeout_ms = 0;

	Vector3 start_position;
	Vector3 current_position;
	uint64_t previous_ms = 0;
	int64_t frames = 0;
	String movement;
	Array samples;
};

} // namespace

// ---------------------------------------------------------------------------
// The handler
// ---------------------------------------------------------------------------

static MCPDeferred::Task *_tool_move_player_to_target(const Dictionary &p_args, MCPToolError &r_error) {
	SceneTree *tree = SceneTree::get_singleton();
	// `game_current_scene` answers the -32000 state error when this process has
	// no running scene at all.
	Node *root = nullptr;
	if (!game_current_scene(root, tree, r_error)) {
		return nullptr;
	}

	String player_path;
	if (!optional_string(p_args, "player_path", String(), player_path, r_error)) {
		return nullptr;
	}
	String camera_path;
	if (!optional_string(p_args, "camera_path", String(), camera_path, r_error)) {
		return nullptr;
	}
	if (!p_args.has("target")) {
		r_error = MCPToolError::invalid_params("Missing required parameter: target");
		return nullptr;
	}
	const Variant target_value = p_args["target"];
	double arrival_radius = MOVE_ARRIVAL_RADIUS_DEFAULT;
	if (!optional_float(p_args, "arrival_radius", MOVE_ARRIVAL_RADIUS_DEFAULT, arrival_radius, r_error)) {
		return nullptr;
	}
	if (arrival_radius < 0.0 || !Math::is_finite(arrival_radius)) {
		r_error = MCPToolError::invalid_params(vformat(
				"'arrival_radius' must be a finite number >= 0, got %f", arrival_radius));
		return nullptr;
	}
	bool look_at_target = false;
	if (!optional_bool(p_args, "look_at_target", false, look_at_target, r_error)) {
		return nullptr;
	}
	bool run = false;
	if (!optional_bool(p_args, "run", false, run, r_error)) {
		return nullptr;
	}
	double timeout_seconds = 15.0;
	if (!optional_float(p_args, "timeout", 15.0, timeout_seconds, r_error)) {
		return nullptr;
	}
	if (timeout_seconds <= 0.0 || !Math::is_finite(timeout_seconds)) {
		r_error = MCPToolError::invalid_params(vformat(
				"'timeout' must be a positive finite number of seconds, got %f", timeout_seconds));
		return nullptr;
	}

	Node *player = resolve_move_player(tree, root, player_path, r_error);
	if (player == nullptr) {
		return nullptr;
	}
	const bool is_3d = move_is_3d(player);

	Vector3 target_3d;
	Vector2 target_2d;
	String target_source;
	if (!move_target_from_value(tree, root, target_value, is_3d, target_3d, target_2d, target_source, r_error)) {
		return nullptr;
	}
	const Vector3 target = is_3d ? target_3d : Vector3(target_2d.x, target_2d.y, 0.0);

	// The navigation capability: an agent on the player, or the player's own
	// navigation map with at least one region. Without either there is no
	// navigation data, and moving straight to the target would not be
	// pathfinding.
	Node *agent = find_player_agent(player, is_3d, player_path);
	RID map;
	TypedArray<RID> regions;
	Vector<Vector3> path;
	String navigation_source;
	if (agent != nullptr) {
		if (NavigationAgent3D *agent_3d = Object::cast_to<NavigationAgent3D>(agent)) {
			agent_3d->set_target_position(target);
			map = agent_3d->get_navigation_map();
			navigation_source = "navigation_agent";
		} else if (NavigationAgent2D *agent_2d = Object::cast_to<NavigationAgent2D>(agent)) {
			agent_2d->set_target_position(Vector2(target.x, target.y));
			map = agent_2d->get_navigation_map();
			navigation_source = "navigation_agent";
		}
	}
	if (!map.is_valid()) {
		if (is_3d) {
			Node3D *node = Object::cast_to<Node3D>(player);
			if (node != nullptr) {
				Ref<World3D> world = node->get_world_3d();
				if (world.is_valid()) {
					map = world->get_navigation_map();
				}
			}
		} else {
			Node2D *node = Object::cast_to<Node2D>(player);
			if (node != nullptr) {
				Ref<World2D> world = node->get_world_2d();
				if (world.is_valid()) {
					map = world->get_navigation_map();
				}
			}
		}
		if (navigation_source.is_empty()) {
			navigation_source = "navigation_server";
		}
	}

	if (!map.is_valid()) {
		r_error = MCPToolError::tool_state(
				vformat("Player '%s' has no navigation map: it is not inside a viewport's World3D/World2D",
						String(player->get_path())),
				"Add the player to the running scene tree, and give the scene navigation data (a NavigationRegion2D/3D "
				"with a baked mesh) before moving to a target");
		return nullptr;
	}
	if (is_3d) {
		NavigationServer3D *server = NavigationServer3D::get_singleton();
		if (server == nullptr) {
			r_error = MCPToolError::tool_state("This process has no NavigationServer3D",
					"Run the game in a build that includes the navigation_3d module");
			return nullptr;
		}
		regions = server->map_get_regions(map);
	} else {
		NavigationServer2D *server = NavigationServer2D::get_singleton();
		if (server == nullptr) {
			r_error = MCPToolError::tool_state("This process has no NavigationServer2D",
					"Run the game in a build that includes the navigation_2d module");
			return nullptr;
		}
		regions = server->map_get_regions(map);
	}
	if (regions.is_empty()) {
		r_error = MCPToolError::tool_state(
				vformat("The navigation map of player '%s' has no region: there is no navigation data to follow, so this "
						"tool refuses instead of moving the player straight through the world",
						String(player->get_path())),
				"Add a NavigationRegion2D/3D to the scene, bake its navigation mesh/resource and make sure the region is "
				"enabled and its navigation_layers overlap the agent's; then call the tool again");
		Dictionary merged = r_error.data;
		merged["map_region_count"] = 0;
		merged["navigation_source"] = navigation_source;
		r_error.data = merged;
		return nullptr;
	}

	if (agent == nullptr) {
		const Vector3 from = node_position(player, is_3d);
		if (is_3d) {
			const Vector<Vector3> server_path = NavigationServer3D::get_singleton()->map_get_path(map, from, target, true, 1);
			for (int i = 0; i < server_path.size(); i++) {
				path.push_back(server_path[i]);
			}
		} else {
			const Vector<Vector2> server_path = NavigationServer2D::get_singleton()->map_get_path(map,
					Vector2(from.x, from.y), Vector2(target.x, target.y), true, 1);
			for (int i = 0; i < server_path.size(); i++) {
				path.push_back(Vector3(server_path[i].x, server_path[i].y, 0.0));
			}
		}
		if (path.size() < 2) {
			r_error = MCPToolError::tool_state(
					vformat("NavigationServer did not find a path from the player to the target (%d point(s))",
							path.size()),
					"Check that the target is on the baked navigation mesh (or reachable from it) and that the region's "
					"agent parameters fit the player; editor_get_navigation_info / running_game_get_scene_tree can show "
					"the regions and the player position");
			Dictionary merged = r_error.data;
			merged["map_region_count"] = regions.size();
			r_error.data = merged;
			return nullptr;
		}
		navigation_source = "navigation_server";
	}

	double agent_max_speed = 0.0;
	if (agent != nullptr) {
		if (NavigationAgent3D *agent_3d = Object::cast_to<NavigationAgent3D>(agent)) {
			agent_max_speed = agent_3d->get_max_speed();
		} else if (NavigationAgent2D *agent_2d = Object::cast_to<NavigationAgent2D>(agent)) {
			agent_max_speed = agent_2d->get_max_speed();
		}
	}
	String speed_source;
	const double speed = move_speed_of(player, agent_max_speed, run, speed_source);
	// Every movement step is computed in `real_t`, so the speed that reaches it
	// is judged by the module's one slot gate (GDR-22): a player `speed` property
	// of `1e300` (or an agent `max_speed` of it) would otherwise put `inf` into
	// every position. The two `(real_t)` casts in the task are
	// `// MCP-NARROWING: G24-MOVE-VECTOR` points pinned as `gated`.
	if (!value_fits_slot(Variant(speed), ValueSlot::REAL_T, "speed",
				"the real_t a node movement step is computed in", r_error)) {
		return nullptr;
	}
	// Every movement step is computed in `real_t`, so the speed that reaches it
	// is judged by the module's one slot gate (GDR-22): a player `speed` property
	// of `1e300` (or an agent `max_speed` of it) would otherwise put `inf` into
	// every position. The two `(real_t)` casts in the task are
	// `// MCP-NARROWING: G24-MOVE-VECTOR` points pinned as `gated`.
	if (!value_fits_slot(Variant(speed), ValueSlot::REAL_T, "speed",
				"the real_t a node movement step is computed in", r_error)) {
		return nullptr;
	}

	// The camera (optional): followed with the offset it had when the move
	// started, so the shot does not jump.
	ObjectID camera_id;
	Vector3 camera_offset;
	bool has_camera = false;
	if (!camera_path.strip_edges().is_empty()) {
		Node *camera = resolve_game_node(tree, root, camera_path);
		if (camera == nullptr) {
			r_error = MCPToolError::not_found(vformat("Camera node '%s'", camera_path),
					"Call running_game_get_scene_tree to list the nodes of the running scene");
			return nullptr;
		}
		if (!move_is_3d(camera) && !camera->is_class("Node2D")) {
			r_error = MCPToolError::invalid_params(vformat(
					"Camera node '%s' is a %s: it must be a Node2D/Node3D to follow the player", camera_path,
					camera->get_class()));
			return nullptr;
		}
		camera_id = camera->get_instance_id();
		camera_offset = node_position(camera, is_3d) - node_position(player, is_3d);
		has_camera = true;
	}

	const uint64_t timeout_ms = (uint64_t)(timeout_seconds * 1000.0 + 0.5);
	MovePlayerToTargetTask *task = memnew(MovePlayerToTargetTask(player->get_instance_id(),
			String(player->get_path()), is_3d, target, arrival_radius, speed, speed_source, run, look_at_target,
			camera_id, camera_path, camera_offset, has_camera,
			agent != nullptr ? agent->get_instance_id() : ObjectID(), navigation_source, path, regions.size(),
			timeout_ms));
	task->target_source = target_source;
	return task;
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character.
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in running_game_navigation_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_running_game_navigation_write_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("running_game_move_player_to_target", String::utf8(R"desc(控制游戏角色直接移动到目标位置)desc"));
	builder.channel("running_game").verb("move").scope(MCPToolScope::GAME).mutating(true);
	builder.schema(_schema_from_json(R"schema({"properties":{"arrival_radius":{"description":"到达判定半径","type":"number"},"camera_path":{"description":"相机节点路径","type":"string"},"look_at_target":{"default":false,"description":"是否面向目标","type":"boolean"},"player_path":{"description":"玩家节点路径","type":"string"},"run":{"default":false,"description":"是否奔跑","type":"boolean"},"target":{"description":"目标位置（字符串路径或坐标字典）"},"timeout":{"default":15.0,"description":"超时时间（秒）","type":"number"}},"required":["target"],"type":"object"})schema"));
	builder.pending_handler(_tool_move_player_to_target).register_into(r_registry);
}
