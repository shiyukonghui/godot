/**************************************************************************/
/*  editor_navigation_read.cpp                                            */
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
#include "editor_navigation_read.h"

#include "tool_helpers.h"

#include "core/io/json.h"
#include "scene/main/node.h"
#include "scene/resources/2d/navigation_polygon.h"
#include "scene/resources/navigation_mesh.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-034 section 1: the engine reference behind this tool.
//
// The walk and the classification are the engine's own:
//
//   * `Node::get_child_count()` / `Node::get_child(i)` in index order - the
//     engine's child order, so the answer is deterministic within one build and
//     identical on a second call (PLAYBOOK section 6.8);
//   * `Object::is_class()` is the classifier. It is used instead of a set of
//     `Object::cast_to<...>` calls because the four families are addressed
//     through their *properties* (`Object::get`), which is also how the engine's
//     own inspector reads them: the class name is a fact of the object, while the
//     property list is what decides which of them exist
//     (`MCPTools::object_has_property`).
//   * `NavigationRegion3D`'s `navigation_mesh`/`enabled`/`navigation_layers`
//     (navigation_region_3d.h:78-102), `NavigationRegion2D`'s
//     `navigation_polygon`/`enabled`/`navigation_layers`
//     (navigation_region_2d.h:84-108), `NavigationAgent3D`'s
//     `radius`/`max_speed`/`navigation_layers`/`avoidance_enabled`/`target_position`
//     (navigation_agent_3d.h:138-207) and the two link classes'
//     `start_position`/`end_position`/`bidirectional`/`navigation_layers`/`enabled`
//     (navigation_link_3d.h:72-90) are read back through `Object::get`, so the
//     answer is the node's real state;
//   * a region's mesh is decomposed with the *resource* classes' own counts:
//     `NavigationMesh::get_vertices()` (navigation_mesh.h:188) and
//     `get_polygon_count()` (:191), `NavigationPolygon::get_vertices()`
//     (2d/navigation_polygon.h:103) and `get_polygon_count()` (:106), so a caller
//     can see whether a region is actually baked (`bake_navigation_mesh` is the
//     write tool of the same family) instead of only whether a resource is set -
//     which is exactly what the migration source's `has_mesh` could not tell
//     (`navigation.rs:381/390`).
//
// The engine's own model is the design basis (GDR-23); the shape differences
// from the migration source are recorded in REPORT-034.
// ---------------------------------------------------------------------------

namespace {

// The properties one navigation family answers, read only when the object
// declares them (a class that gates one behind a build flag is then answered
// without it instead of with a fabricated default).
Dictionary read_properties(Object *p_object, const char *const *p_names, int p_count) {
	Dictionary record;
	for (int i = 0; i < p_count; i++) {
		const StringName name(p_names[i]);
		if (!object_has_property(p_object, name)) {
			continue;
		}
		record[p_names[i]] = serialize_variant(p_object->get(name));
	}
	return record;
}

// The mesh/polygon a region holds, decomposed by the resource's own counts.
void add_region_mesh_info(Object *p_region, Dictionary &r_record) {
	const StringName mesh_name("navigation_mesh");
	if (object_has_property(p_region, mesh_name)) {
		const Variant value = p_region->get(mesh_name);
		r_record["navigation_mesh"] = serialize_variant(value);
		NavigationMesh *mesh = Object::cast_to<NavigationMesh>(value);
		if (mesh != nullptr) {
			r_record["vertex_count"] = mesh->get_vertices().size();
			r_record["polygon_count"] = mesh->get_polygon_count();
			r_record["baked"] = mesh->get_polygon_count() > 0;
		} else {
			r_record["vertex_count"] = 0;
			r_record["polygon_count"] = 0;
			r_record["baked"] = false;
		}
		return;
	}
	const StringName polygon_name("navigation_polygon");
	if (object_has_property(p_region, polygon_name)) {
		const Variant value = p_region->get(polygon_name);
		r_record["navigation_polygon"] = serialize_variant(value);
		NavigationPolygon *polygon = Object::cast_to<NavigationPolygon>(value);
		if (polygon != nullptr) {
			r_record["vertex_count"] = polygon->get_vertices().size();
			r_record["polygon_count"] = polygon->get_polygon_count();
			r_record["baked"] = polygon->get_polygon_count() > 0;
		} else {
			r_record["vertex_count"] = 0;
			r_record["polygon_count"] = 0;
			r_record["baked"] = false;
		}
	}
}

void collect_navigation_nodes(Node *p_root, Node *p_node, Array &r_regions, Array &r_agents, Array &r_links,
		Array &r_obstacles) {
	const String class_name = p_node->get_class();
	const String path = relative_path(p_root, p_node);

	if (class_name == "NavigationRegion3D" || class_name == "NavigationRegion2D") {
		Dictionary record;
		record["path"] = path;
		record["type"] = p_node->get_class();
		const char *const names[] = { "enabled", "navigation_layers" };
		const Dictionary properties = read_properties(p_node, names, 2);
		const Array keys = properties.keys();
		for (int i = 0; i < keys.size(); i++) {
			record[keys[i]] = properties[keys[i]];
		}
		add_region_mesh_info(p_node, record);
		r_regions.push_back(record);
	} else if (class_name == "NavigationAgent2D" || class_name == "NavigationAgent3D") {
		Dictionary record;
		record["path"] = path;
		record["type"] = p_node->get_class();
		const char *const names[] = { "radius", "max_speed", "navigation_layers", "avoidance_enabled",
			"target_position" };
		const Dictionary properties = read_properties(p_node, names, 5);
		const Array keys = properties.keys();
		for (int i = 0; i < keys.size(); i++) {
			record[keys[i]] = properties[keys[i]];
		}
		r_agents.push_back(record);
	} else if (class_name == "NavigationLink2D" || class_name == "NavigationLink3D") {
		Dictionary record;
		record["path"] = path;
		record["type"] = p_node->get_class();
		const char *const names[] = { "enabled", "bidirectional", "navigation_layers", "start_position",
			"end_position" };
		const Dictionary properties = read_properties(p_node, names, 5);
		const Array keys = properties.keys();
		for (int i = 0; i < keys.size(); i++) {
			record[keys[i]] = properties[keys[i]];
		}
		r_links.push_back(record);
	} else if (class_name == "NavigationObstacle2D" || class_name == "NavigationObstacle3D") {
		Dictionary record;
		record["path"] = path;
		record["type"] = p_node->get_class();
		const char *const names[] = { "radius", "avoidance_enabled", "navigation_layers" };
		const Dictionary properties = read_properties(p_node, names, 3);
		const Array keys = properties.keys();
		for (int i = 0; i < keys.size(); i++) {
			record[keys[i]] = properties[keys[i]];
		}
		r_obstacles.push_back(record);
	}

	// The engine's own child order, depth first: deterministic and the same
	// order the scene tree shows.
	for (int i = 0; i < p_node->get_child_count(); i++) {
		Node *child = p_node->get_child(i);
		if (child == nullptr) {
			continue;
		}
		collect_navigation_nodes(p_root, child, r_regions, r_agents, r_links, r_obstacles);
	}
}

} // namespace

namespace MCPTools {

Dictionary navigation_info_on(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the nodes that are there");
		return Dictionary();
	}
	Array regions;
	Array agents;
	Array links;
	Array obstacles;
	collect_navigation_nodes(p_root, node, regions, agents, links, obstacles);

	Dictionary out;
	out["node_path"] = relative_path(p_root, node);
	out["node_type"] = node->get_class();
	out["region_count"] = regions.size();
	out["agent_count"] = agents.size();
	out["link_count"] = links.size();
	out["obstacle_count"] = obstacles.size();
	out["regions"] = regions;
	out["agents"] = agents;
	out["links"] = links;
	out["obstacles"] = obstacles;
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tool
// ---------------------------------------------------------------------------

static Variant _tool_get_navigation_info(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!optional_string(p_args, "node_path", ".", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty (pass \".\" for the edited scene root)");
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor navigation reads outside a running editor",
				"Start the MCP server inside the Godot editor to read editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return navigation_info_on(root, node_path, r_error);
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character.
// ---------------------------------------------------------------------------
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_navigation_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_navigation_read_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("editor_get_navigation_info", String::utf8(R"desc(获取导航信息)desc"));
	builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
	builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"default":".","type":"string"}},"required":[],"type":"object"})schema"));
	builder.handler(_tool_get_navigation_info).register_into(r_registry);
}