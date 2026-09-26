/**************************************************************************/
/*  editor_navigation_write.cpp                                           */
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
#include "editor_navigation_write.h"

#include "../mcp_deferred.h"
#include "editor_navigation_read.h"
#include "tool_helpers.h"

#include "core/config/project_settings.h"
#include "core/io/json.h"
#include "core/object/object.h"
#include "core/variant/typed_array.h"
#include "scene/2d/navigation/navigation_region_2d.h"
#include "scene/3d/navigation/navigation_region_3d.h"
#include "scene/resources/2d/navigation_polygon.h"
#include "scene/resources/navigation_mesh.h"
#include "servers/navigation_2d/navigation_server_2d.h"
#include "servers/navigation_3d/navigation_server_3d.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-036 section 2: the engine reference behind the two tools.
//
//   * `NavigationRegion3D::bake_navigation_mesh(true)` is **asynchronous**:
//     `scene/3d/navigation/navigation_region_3d.cpp:222-236` parses the source
//     geometry on the main thread and calls
//     `NavigationServer3D::bake_from_source_geometry_data_async`, whose worker
//     task is drained by `NavMeshGenerator3D::sync`
//     (`modules/navigation_3d/3d/nav_mesh_generator_3d.cpp:89-121`). Until that
//     drain, `NavigationRegion3D::is_baking()`
//     (`navigation_region_3d.cpp:247-249`) answers true and the mesh has not
//     been written. `NavigationRegion2D` has the same pair
//     (`scene/2d/navigation/navigation_region_2d.cpp:233-260`).
//   * the migration source never called either: it wrote
//     `region.set("bake_navigation_mesh", nil)` - a property that does not
//     exist - and answered `baked: true, note: "bake triggered via property set"`
//     (`godot_mcp_gdext/src/commands/navigation.rs:193-228`). That is this
//     batch's `fix_implementation_first`: "started nothing and said baked".
//   * `NavigationServer3D::map_get_regions(map)` is the engine's own "is this
//     region on a real navigation map" answer; the dummy server
//     (`servers/navigation_3d/navigation_server_3d_dummy.h:58`) and a region
//     outside the tree both answer an empty list, which is the honest
//     precondition failure this tool reports as `-32000`.
//   * the read-back is `editor_get_navigation_info`'s own entry point
//     (`MCPTools::navigation_info_on`, `editor_navigation_read.cpp`): the same
//     function the read tool serves, called from inside the bake task, so "the
//     bake really produced something" is proven by **another tool** and not by a
//     parallel count written for the occasion.
// ---------------------------------------------------------------------------

namespace {

// One region's counts out of `editor_get_navigation_info`'s answer.
bool region_counts(const Dictionary &p_info, const String &p_path, int64_t &r_polygons, int64_t &r_vertices,
		bool &r_baked) {
	r_polygons = 0;
	r_vertices = 0;
	r_baked = false;
	const Array regions = p_info.get("regions", Array());
	for (int i = 0; i < regions.size(); i++) {
		const Dictionary record = regions[i];
		if (String(record.get("path", String())) != p_path) {
			continue;
		}
		r_polygons = (int64_t)record.get("polygon_count", (int64_t)0);
		r_vertices = (int64_t)record.get("vertex_count", (int64_t)0);
		r_baked = (bool)record.get("baked", false);
		return true;
	}
	return false;
}

// The navigation resource a region holds, or a null Ref (`-32001` filled).
Ref<Resource> region_navigation_resource(Object *p_node, const String &p_kind, const String &p_node_path,
		MCPToolError &r_error) {
	const char *property = navigation_region_resource_property(p_kind);
	const Variant value = p_node->get(StringName(property));
	Resource *resource = Object::cast_to<Resource>(value);
	if (resource == nullptr) {
		r_error = MCPToolError::not_found(
				vformat("%s of '%s'", p_kind == "3d" ? "the NavigationMesh" : "the NavigationPolygon", p_node_path),
				"Assign the resource first: editor_setup_navigation_region creates a region with one, and the region's "
				"`navigation_mesh`/`navigation_polygon` member can be set with editor_set_node_property");
		return Ref<Resource>();
	}
	return Ref<Resource>(resource);
}

// The resource's own polygon/vertex counts (the resource classes the region
// holds; `NavigationMesh::get_vertices`/`get_polygon_count` and
// `NavigationPolygon`'s pair).
void resource_counts(const Ref<Resource> &p_resource, int64_t &r_polygons, int64_t &r_vertices) {
	r_polygons = 0;
	r_vertices = 0;
	if (NavigationMesh *mesh = Object::cast_to<NavigationMesh>(p_resource.ptr())) {
		r_polygons = mesh->get_polygon_count();
		r_vertices = mesh->get_vertices().size();
		return;
	}
	if (NavigationPolygon *polygon = Object::cast_to<NavigationPolygon>(p_resource.ptr())) {
		r_polygons = polygon->get_polygon_count();
		r_vertices = polygon->get_vertices().size();
	}
}

} // namespace

namespace MCPTools {

int navigation_layer_count() {
	// `NavigationServer3D`/`NavigationServer2D` use the 32 bits of the
	// `uint32_t navigation_layers` member (every navigation node declares it).
	return 32;
}

bool navigation_layer_mask_fits(int64_t p_layers, MCPToolError &r_error) {
	// There is no `ValueSlot` for a `uint32_t` (GDR-22 section 20.1 lists
	// `WIDE`/`REAL_T`/`FLOAT32`/`INT32`/`UINT8`) and `Variant::operator
	// uint32_t()` truncates silently, so the width is checked explicitly - the
	// same decision `editor_set_physics_layers` made for the same member type
	// (TASK-035). Negative masks do not exist.
	if (p_layers < 0 || p_layers > (int64_t)0xFFFFFFFFll) {
		r_error = MCPToolError::invalid_params(vformat(
				"'layers' must be a 32-bit navigation layer mask in 0..4294967295 (the width of the engine's uint32_t "
				"navigation_layers member); got %d. A value outside that range would be truncated by the engine's own "
				"copy (a mask of 4294967296 would land as 0)",
				p_layers));
		return false;
	}
	return true;
}

String navigation_layer_setting_prefix(const Object *p_node) {
	if (p_node == nullptr) {
		return String();
	}
	if (p_node->is_class("Node3D")) {
		return "layer_names/3d_navigation";
	}
	if (p_node->is_class("Node2D") || p_node->is_class("Node")) {
		return "layer_names/2d_navigation";
	}
	return String();
}

Array navigation_layer_bits(uint32_t p_mask) {
	Array bits;
	for (int bit = 1; bit <= navigation_layer_count(); bit++) {
		if (p_mask & (uint32_t)(1u << (bit - 1))) {
			bits.push_back(bit);
		}
	}
	return bits;
}

Array navigation_layer_names_of_mask(const Object *p_node, uint32_t p_mask) {
	Array names;
	ProjectSettings *settings = ProjectSettings::get_singleton();
	const String prefix = navigation_layer_setting_prefix(p_node);
	for (int bit = 1; bit <= navigation_layer_count(); bit++) {
		if (!(p_mask & (uint32_t)(1u << (bit - 1)))) {
			continue;
		}
		String name;
		if (settings != nullptr && !prefix.is_empty()) {
			const String key = vformat("%s/layer_%d", prefix, bit);
			if (settings->has_setting(key)) {
				name = (String)settings->get_setting(key);
			}
		}
		names.push_back(name);
	}
	return names;
}

Dictionary set_navigation_layers_on(Node *p_root, const String &p_node_path, int64_t p_layers, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the nodes that are there");
		return Dictionary();
	}
	const StringName property("navigation_layers");
	if (!object_has_property(node, property)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Node '%s' is a %s and has no 'navigation_layers' member: the mask lives on a navigation node "
				"(NavigationRegion2D/3D, NavigationAgent2D/3D, NavigationLink2D/3D, NavigationObstacle2D/3D)",
				p_node_path, node->get_class()));
		return Dictionary();
	}
	if (!navigation_layer_mask_fits(p_layers, r_error)) {
		return Dictionary();
	}
	const uint32_t requested = (uint32_t)p_layers;
	const int64_t previous = (int64_t)(uint32_t)(int64_t)node->get(property);
	node->set(property, Variant((int64_t)requested));
	const int64_t stored = (int64_t)(uint32_t)(int64_t)node->get(property);
	if ((uint32_t)stored != requested) {
		r_error = MCPToolError::internal(vformat("Writing %d into 'navigation_layers' of '%s' stored %d instead",
				(int64_t)requested, p_node_path, stored));
		return Dictionary();
	}

	Dictionary out;
	out["node_path"] = relative_path(p_root, node);
	out["node_type"] = node->get_class();
	out["dimension"] = node->is_class("Node3D") ? "3d" : "2d";
	out["property"] = String(property);
	out["layers"] = (int64_t)requested;
	out["previous_layers"] = previous;
	out["new_value"] = stored;
	out["applied"] = true;
	out["changed"] = previous != stored;
	out["layer_count"] = navigation_layer_count();
	out["layer_bits"] = navigation_layer_bits(requested);
	out["layer_names"] = navigation_layer_names_of_mask(node, requested);
	return out;
}

bool navigation_region_kind(Object *p_node, const String &p_node_path, String &r_kind, MCPToolError &r_error) {
	if (p_node == nullptr) {
		r_error = MCPToolError::internal("No node was resolved for the navigation region");
		return false;
	}
	if (p_node->is_class("NavigationRegion3D")) {
		r_kind = "3d";
		return true;
	}
	if (p_node->is_class("NavigationRegion2D")) {
		r_kind = "2d";
		return true;
	}
	r_error = MCPToolError::invalid_params(vformat(
			"Node '%s' is a %s, not a NavigationRegion: baking needs a NavigationRegion3D (NavigationMesh) or a "
			"NavigationRegion2D (NavigationPolygon)",
			p_node_path, p_node->get_class()));
	return false;
}

const char *navigation_region_resource_property(const String &p_kind) {
	return p_kind == "2d" ? "navigation_polygon" : "navigation_mesh";
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// editor_bake_navigation_mesh - the deferred bake task
//
// The handler does every precondition (including the capability check that the
// region is registered on a real navigation map) and **starts** the bake on the
// main thread; the task then polls `is_baking()` every frame and only answers
// once the engine says the bake is over. Its answer carries the before/after
// counts read through `editor_get_navigation_info`'s own entry point, so "it
// really baked" is a proof by another tool.
// ---------------------------------------------------------------------------

namespace {

// The frame budget after which a bake that never finishes is reported as a
// state error rather than waited on forever (the framework's own deadline is
// the outer bound; this one exists so the error can name the bake).
const int64_t BAKE_NAVIGATION_MESH_MAX_FRAMES = 1800;

class BakeNavigationMeshTask : public MCPDeferred::Task {
public:
	BakeNavigationMeshTask(ObjectID p_region_id, const String &p_node_path, const String &p_kind,
			int64_t p_before_polygons, int64_t p_before_vertices) :
			region_id(p_region_id),
			node_path(p_node_path),
			kind(p_kind),
			before_polygons(p_before_polygons),
			before_vertices(p_before_vertices) {}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_frame;
		(void)p_now_ms;
		Object *object = ObjectDB::get_instance(region_id);
		if (object == nullptr) {
			return MCPDeferred::TickResult::failed(MCPToolError::not_found(
					vformat("Navigation region '%s'", node_path),
					"The region was removed while its bake was running; re-open the scene and bake again"));
		}
		if (is_baking(object)) {
			frames_waited++;
			if (frames_waited > BAKE_NAVIGATION_MESH_MAX_FRAMES) {
				return MCPDeferred::TickResult::failed(MCPToolError::tool_state(
						vformat("The navigation bake of '%s' did not finish after %d frames", node_path,
								(int)frames_waited),
						"Check the editor output for navigation bake errors; a very large scene can need longer than this "
						"budget, in which case bake it from the editor's NavigationRegion3D menu"));
			}
			return MCPDeferred::TickResult::pending();
		}

		const Ref<Resource> resource = Object::cast_to<Resource>(object->get(navigation_region_resource_property(kind)));
		int64_t polygons = 0;
		int64_t vertices = 0;
		resource_counts(resource, polygons, vertices);

		// The cross-tool proof: `editor_get_navigation_info`'s own function, on
		// the same region, at the moment the bake is over.
		Dictionary verify;
		String verify_error;
		Node *root = edited_scene_root();
		if (root != nullptr) {
			MCPToolError info_error;
			const Dictionary info = navigation_info_on(root, node_path, info_error);
			if (info_error.is_error()) {
				verify_error = info_error.message;
			} else {
				int64_t verify_polygons = 0;
				int64_t verify_vertices = 0;
				bool verify_baked = false;
				if (region_counts(info, node_path, verify_polygons, verify_vertices, verify_baked)) {
					verify = info;
				} else {
					verify_error = "the region is no longer part of the edited scene";
				}
			}
		} else {
			verify_error = "the edited scene was closed while the bake was running";
		}

		Dictionary out;
		out["node_path"] = node_path;
		out["type"] = object->get_class();
		out["kind"] = kind;
		out["baked"] = polygons > 0;
		out["polygon_count"] = polygons;
		out["vertex_count"] = vertices;
		out["before_polygon_count"] = before_polygons;
		out["before_vertex_count"] = before_vertices;
		out["changed"] = polygons != before_polygons || vertices != before_vertices;
		out["frames_waited"] = (int)frames_waited;
		out["bake_signalled_done"] = true;
		out["resource_path"] = resource.is_valid() ? resource->get_path() : String();
		out["verify_tool"] = "editor_get_navigation_info";
		out["verify"] = verify;
		if (!verify_error.is_empty()) {
			out["verify_error"] = verify_error;
		}
		if (polygons == 0) {
			out["message"] = "The bake ran and finished but produced no polygons: the region's navigation_mesh has no "
							 "source geometry to parse (add MeshInstance3D children under the region, and check the "
							 "mesh's geometry_parsed_geometry_type/geometry_source_geometry_mode and its agent "
							 "parameters). The mesh is not a stale copy - it was really re-baked.";
		}
		return MCPDeferred::TickResult::done(out);
	}

	uint64_t get_timeout_ms() const override { return 25000; }

	String describe() const override { return vformat("baking the navigation mesh of '%s'", node_path); }

private:
	static bool is_baking(Object *p_object) {
		if (NavigationRegion3D *region = Object::cast_to<NavigationRegion3D>(p_object)) {
			return region->is_baking();
		}
		if (NavigationRegion2D *region = Object::cast_to<NavigationRegion2D>(p_object)) {
			return region->is_baking();
		}
		return false;
	}

	ObjectID region_id;
	String node_path;
	String kind;
	int64_t before_polygons = 0;
	int64_t before_vertices = 0;
	int64_t frames_waited = 0;
};

} // namespace

static MCPDeferred::Task *_tool_bake_navigation_mesh(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "navigation_region_path", node_path, r_error)) {
		return nullptr;
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'navigation_region_path' must not be empty (pass \".\" for the scene root)");
		return nullptr;
	}
	if (!require_editor_ui(r_error, "editor navigation writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return nullptr;
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return nullptr;
	}
	Node *region = find_node(root, node_path);
	if (region == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", node_path),
				"'navigation_region_path' is relative to the edited scene root ('.' is the root itself); call "
				"editor_get_scene_tree to list the nodes that are there");
		return nullptr;
	}
	String kind;
	if (!navigation_region_kind(region, node_path, kind, r_error)) {
		return nullptr;
	}
	const Ref<Resource> navigation_resource = region_navigation_resource(region, kind, node_path, r_error);
	if (navigation_resource.is_null()) {
		return nullptr;
	}

	// Capability precondition: the region must be registered on a real
	// navigation map. A dummy navigation server (or a region outside the tree)
	// answers an empty list, and baking there would silently do nothing.
	RID map;
	TypedArray<RID> registered;
	String server_name;
	if (kind == "3d") {
		NavigationServer3D *server = NavigationServer3D::get_singleton();
		if (server == nullptr) {
			r_error = MCPToolError::tool_state(
					"This process has no NavigationServer3D, so a navigation mesh cannot be baked here",
					"Run the tool inside a build that includes the navigation_3d module");
			return nullptr;
		}
		NavigationRegion3D *typed = Object::cast_to<NavigationRegion3D>(region);
		map = typed->get_navigation_map();
		server_name = "NavigationServer3D";
		if (map.is_valid()) {
			registered = server->map_get_regions(map);
		}
	} else {
		NavigationServer2D *server = NavigationServer2D::get_singleton();
		if (server == nullptr) {
			r_error = MCPToolError::tool_state(
					"This process has no NavigationServer2D, so a navigation polygon cannot be baked here",
					"Run the tool inside a build that includes the navigation_2d module");
			return nullptr;
		}
		NavigationRegion2D *typed = Object::cast_to<NavigationRegion2D>(region);
		map = typed->get_navigation_map();
		server_name = "NavigationServer2D";
		if (map.is_valid()) {
			registered = server->map_get_regions(map);
		}
	}
	if (!map.is_valid()) {
		r_error = MCPToolError::tool_state(
				vformat("Navigation region '%s' has no navigation map: it is not inside a viewport's World3D/World2D", node_path),
				"Add the region to the edited scene (it is registered when it enters the tree), then bake again");
		return nullptr;
	}
	if (registered.is_empty()) {
		r_error = MCPToolError::tool_state(
				vformat("Navigation region '%s' is not registered on its navigation map (%s): the navigation server cannot "
						"bake here (a dummy/disabled navigation server answers an empty region list)",
						node_path, server_name),
				"Make sure the region is inside the edited scene tree and that this build includes the navigation modules "
				"(navigation_2d/navigation_3d); without a real navigation server the bake would do nothing and this tool "
				"refuses instead of reporting a bake that did not happen");
		return nullptr;
	}

	// The before-state, through `editor_get_navigation_info`'s own function (the
	// same call the completion makes, so "changed" compares like with like).
	const String resolved_path = relative_path(root, region);
	int64_t before_polygons = 0;
	int64_t before_vertices = 0;
	{
		MCPToolError info_error;
		const Dictionary info = navigation_info_on(root, resolved_path, info_error);
		bool baked = false;
		if (!info_error.is_error()) {
			region_counts(info, resolved_path, before_polygons, before_vertices, baked);
		}
	}

	// Start the bake on the main thread (the engine requires it:
	// `NavigationRegion3D::bake_navigation_mesh` is an `ERR_FAIL_COND_MSG` off
	// the main thread).
	if (kind == "3d") {
		Object::cast_to<NavigationRegion3D>(region)->bake_navigation_mesh(true);
	} else {
		Object::cast_to<NavigationRegion2D>(region)->bake_navigation_polygon(true);
	}

	return memnew(BakeNavigationMeshTask(region->get_instance_id(), resolved_path, kind, before_polygons,
			before_vertices));
}

// ---------------------------------------------------------------------------
// The layer tool
// ---------------------------------------------------------------------------

static Variant _tool_set_navigation_layers(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	int64_t layers = 0;
	if (!require_int(p_args, "layers", layers, r_error)) {
		return Variant();
	}
	if (!navigation_layer_mask_fits(layers, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor navigation writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Dictionary out = set_navigation_layers_on(root, node_path, layers, r_error);
	return out.is_empty() ? Variant() : Variant(out);
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character. `editor_bake_navigation_mesh`
// is the group's `pending_handler`: its bake spans frames (GDR-20), and the
// builder refuses a tool that declares both halves.
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_navigation_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_navigation_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_bake_navigation_mesh", String::utf8(R"desc(烘焙导航网格)desc"));
		builder.channel("editor").verb("bake").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"navigation_region_path":{"type":"string"}},"required":["navigation_region_path"],"type":"object"})schema"));
		builder.pending_handler(_tool_bake_navigation_mesh).register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_set_navigation_layers", String::utf8(R"desc(设置导航层)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"layers":{"type":"integer"},"node_path":{"type":"string"}},"required":["node_path","layers"],"type":"object"})schema"));
		builder.handler(_tool_set_navigation_layers).register_into(r_registry);
	}
}
