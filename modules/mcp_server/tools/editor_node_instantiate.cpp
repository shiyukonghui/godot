/**************************************************************************/
/*  editor_node_instantiate.cpp                                           */
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
#include "editor_node_instantiate.h"

#include "tool_builder.h"
#include "tool_helpers.h"
// The one definition of the module's node-property write ("does this object
// really have this property, how is the caller's value coerced into it"). This
// group writes exactly one property (`mesh_library`) and it goes through that
// definition, not through a second one.
#include "running_game_node_write.h"

#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/io/resource_loader.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
// `GridMap` lives in the `gridmap` module (enabled by default in this fork),
// which is why its include names the module path rather than the `scene/` tree.
#include "modules/gridmap/grid_map.h"
#include "scene/2d/physics/ray_cast_2d.h"
#include "scene/3d/mesh_instance_3d.h"
#include "scene/3d/physics/ray_cast_3d.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/resources/3d/mesh_library.h"
#include "scene/resources/packed_scene.h"

using namespace MCPTools;

// The runtime half of the editor guard lives in `tools/tool_helpers.*` and is
// called below as `require_editor_ui(r_error, <non-editor wording>,
// <suggestion>)`. The edited scene root (`MCPTools::edited_scene_root()`) and the
// migration source's node resolution (`MCPTools::find_node()`) were hoisted there
// by TASK-016 section 1, so this group file keeps no copy of either.
//
// Nothing in this file needs an editor-only engine header: these four tools
// create nodes in the edited scene through `memnew` + `add_child` + `set_owner`,
// which is plain scene-tree API. The editor/process split is still enforced
// twice - `ToolBuilder` does not even register a `scope = EDITOR` tool in a game
// process (GDR-19 section 17.3), and `require_editor_ui` refuses every call in
// one.

// ---------------------------------------------------------------------------
// The argument shapes.
// ---------------------------------------------------------------------------

// `parent_path` is optional everywhere in this group and defaults to ".", the
// edited scene root. A present-but-empty value means the same thing the migration
// source's `unwrap_or(".")` meant ("" is not a node path); a present-but-wrong
// type is `-32602` (PLAYBOOK section 6.2).
static bool _optional_parent_path(const Dictionary &p_args, String &r_out, MCPToolError &r_error) {
	if (!optional_string(p_args, "parent_path", ".", r_out, r_error)) {
		return false;
	}
	if (r_out.strip_edges().is_empty()) {
		r_out = ".";
	}
	return true;
}

// A required, non-empty string argument of this group. One helper keeps the
// wording of the refusal identical for `scene_path` and `mesh_library_path` (the
// migration source read the second one with `and_then(as_str)` and reported
// "Missing mesh_library_path").
static bool _require_non_empty_string(const Dictionary &p_args, const String &p_key, String &r_out, MCPToolError &r_error) {
	if (!require_string(p_args, p_key, r_out, r_error)) {
		return false;
	}
	if (r_out.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must not be empty", p_key));
		return false;
	}
	return true;
}

// ---------------------------------------------------------------------------
// MCPTools:: the testable entry points.
//
// The doctest binary has no `SceneTree` at all (`SceneTree::get_singleton()` is
// nullptr), so a tool-level case can only ever observe the -32000 guards. These
// two entry points take the nodes, which is what lets the group's cases pin the
// real behaviour - including the gridmap correction - against bare `Node`
// objects. Their behaviour is documented in tools/editor_node_instantiate.h and
// at each definition below.
// ---------------------------------------------------------------------------
namespace MCPTools {

void add_typed_child(Node *p_root, Node *p_parent, const String &p_name, Node *p_node) {
	if (!p_name.is_empty()) {
		// `Node::set_name()` sanitises rather than fails; every caller answers
		// the name the engine actually applied.
		p_node->set_name(p_name);
	}
	p_parent->add_child(p_node);
	// `owner` is what makes the new node part of the saved scene rather than a
	// runtime child; it has to be set *after* `add_child()` because it is the
	// ancestor relationship that makes the root a legal owner.
	p_node->set_owner(p_root);
}

bool attach_mesh_library(Node *p_gridmap, const String &p_mesh_library_path, MCPToolError &r_error) {
	Ref<Resource> loaded = ResourceLoader::load(p_mesh_library_path);
	MeshLibrary *library = Object::cast_to<MeshLibrary>(loaded.ptr());
	if (library == nullptr) {
		// The migration source loaded the library inside `if let Some(lib)`
		// (scene_3d.rs:273-275) and answered `{"created": true}` even when the
		// load produced nothing, so a GridMap without its mesh library was
		// indistinguishable from a working one. This is PLAYBOOK section 6.6's
		// failure mode ("nothing happened, reported as done"), and the honest
		// answer is a `-32001` with a suggestion - the same shape the unknown
		// property of `editor_get_node_properties` gets.
		r_error = MCPToolError::not_found(vformat("MeshLibrary '%s'", p_mesh_library_path),
				"editor_add_gridmap does not create a GridMap without its mesh library. Name a .tres/.res MeshLibrary that "
				"exists in this project (project_get_filesystem_tree lists the files of the project), or drop 'mesh_library_path' "
				"and set the GridMap's mesh_library later with editor_set_node_property");
		return false;
	}
	Ref<MeshLibrary> library_ref = library;
	const Variant written = write_node_property(p_gridmap, "mesh_library", library_ref, r_error);
	return written.get_type() != Variant::NIL;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// editor_add_scene_instance (old `add_scene_instance`, scene.rs:284)
//
// The answer is the migration source's own key set
// (`node_path` / `scene_path` / `name`), with `name` read back from the engine:
// an empty `name` means "keep the name the instantiated scene already has", and
// the migration source read the applied name back too (scene.rs:330).
//
// `scene_path` is normalised like every other path argument of the module
// (PLAYBOOK section 6.3/6.7); the migration source compared the raw string with
// `FileAccess::file_exists`, so `res://./scenes/main.tscn` was a miss there.
// ---------------------------------------------------------------------------
static Variant _tool_add_scene_instance(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_scene_path;
	if (!_require_non_empty_string(p_args, "scene_path", raw_scene_path, r_error)) {
		return Variant();
	}
	String scene_path;
	if (!normalize_project_path(raw_scene_path, scene_path, r_error)) {
		return Variant();
	}
	String parent_path;
	if (!_optional_parent_path(p_args, parent_path, r_error)) {
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", String(), name, r_error)) {
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
	// The migration source's own order: the file is checked before the parent is
	// resolved (scene.rs:294-307).
	if (!FileAccess::exists(scene_path)) {
		r_error = MCPToolError::not_found(vformat("Scene '%s'", scene_path),
				"Use project_get_filesystem_tree to list the .tscn files of the project");
		return Variant();
	}
	Node *parent = find_node(root, parent_path);
	if (parent == nullptr) {
		r_error = MCPToolError::not_found(vformat("Parent '%s'", parent_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}

	Ref<PackedScene> packed = ResourceLoader::load(scene_path);
	if (packed.is_null()) {
		// The file is there but is not a loadable scene: a state problem, not a
		// missing thing (GDR-14).
		r_error = MCPToolError::tool_state(vformat("Scene '%s' could not be loaded as a PackedScene", scene_path),
				"The file exists but the resource loader did not produce a PackedScene; check its ext_resource paths and any script it depends on");
		return Variant();
	}
	Node *instance = packed->instantiate();
	if (instance == nullptr) {
		r_error = MCPToolError::tool_state(vformat("Scene '%s' could not be instantiated", scene_path),
				"The PackedScene was loaded but produced no node tree; re-save the scene in the editor");
		return Variant();
	}

	add_typed_child(root, parent, name, instance);

	Dictionary result;
	result["node_path"] = String(root->get_path_to(instance));
	result["scene_path"] = scene_path;
	result["name"] = String(instance->get_name());
	return result;
}

// ---------------------------------------------------------------------------
// editor_add_raycast (old `add_raycast`, physics.rs:67)
//
// `dimension == "2d"` selects `RayCast2D`, **everything else** selects
// `RayCast3D` - the migration source's `match dim { "2d" => ..., _ => ... }` has
// exactly one arm and a catch-all (physics.rs:77-80), and that quirk is kept
// (PLAYBOOK section 6.8). `type` and `node_path` are read back from the created
// node, which the migration source's `{"added": true, "name": name}` did not do.
//
// The parent is resolved *before* the node is created, so a refused call leaves
// no orphan behind - the migration source's `root.get_node_as::<Node>(path)`
// produced a null `Gd` for a missing parent and then added the node to nothing.
// ---------------------------------------------------------------------------
// TASK-112 D-T111-3: `dimension` is a **closed set**.
//
// The first implementation wrote `dimension == "2d" ? RayCast2D : RayCast3D`, so
// every value other than the exact literal `"2d"` - `"4d"`, `"2D"`, a typo, an
// empty string - silently produced a `RayCast3D` and the answer echoed the
// caller's own spelling back next to `added: true`. Measured (`c4-033`):
// `{"dimension":"4d","name":"Ray4d"}` answered
// `{"added":true,"name":"Ray4d","node_path":"Ray4d","type":"RayCast3D"}` - a
// wrong node under a successful exit code, which is the worst of the three
// outcomes.
//
// The sibling closed sets do exactly this (`editor_set_physics_layers`'
// `layer_type`, `editor_physics_write.cpp:68-81`;
// `editor_setup_navigation_region`'s `mode`, `editor_node_setup.cpp:462`): a
// value outside the set is a `-32602` that names the set. The registry attaches
// the `data.suggestion` every `-32602` of this module carries (TASK-050 N-7),
// which lists the parameters the tool really declares.
static bool _resolve_raycast_dimension(const String &p_dimension, bool &r_is_2d, MCPToolError &r_error) {
	const String value = p_dimension.strip_edges();
	if (value == "2d") {
		r_is_2d = true;
		return true;
	}
	if (value == "3d") {
		r_is_2d = false;
		return true;
	}
	r_error = MCPToolError::invalid_params(vformat(
			"'dimension' must be one of '2d' or '3d'; got '%s'", p_dimension));
	return false;
}

static Variant _tool_add_raycast(const Dictionary &p_args, MCPToolError &r_error) {
	String parent_path;
	if (!_optional_parent_path(p_args, parent_path, r_error)) {
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", "RayCast", name, r_error)) {
		return Variant();
	}
	String dimension;
	if (!optional_string(p_args, "dimension", "2d", dimension, r_error)) {
		return Variant();
	}
	// TASK-112 D-T111-3: decided **before** the editor guard, so the refusal is
	// the caller's argument and not the process's state - and so a doctest can
	// pin it without an editor.
	bool is_2d = true;
	if (!_resolve_raycast_dimension(dimension, is_2d, r_error)) {
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
	Node *parent = find_node(root, parent_path);
	if (parent == nullptr) {
		r_error = MCPToolError::not_found(vformat("Parent '%s'", parent_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}

	Node *node = is_2d ? (Node *)memnew(RayCast2D) : (Node *)memnew(RayCast3D);
	add_typed_child(root, parent, name, node);

	Dictionary result;
	result["added"] = true;
	result["name"] = String(node->get_name());
	result["node_path"] = String(root->get_path_to(node));
	result["type"] = node->get_class();
	return result;
}

// ---------------------------------------------------------------------------
// editor_add_mesh_instance (old `add_mesh_instance`, scene_3d.rs:73)
//
// `MeshInstance3D` is constructed directly (`memnew`) instead of through
// `ClassDB::instantiate()`, which is what the migration source had to do because
// of its bindings; the C++ side has the class. The answer carries the same
// `added`/`name` pair plus the created node's real path and class.
// ---------------------------------------------------------------------------
static Variant _tool_add_mesh_instance(const Dictionary &p_args, MCPToolError &r_error) {
	String parent_path;
	if (!_optional_parent_path(p_args, parent_path, r_error)) {
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", "Mesh", name, r_error)) {
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
	Node *parent = find_node(root, parent_path);
	if (parent == nullptr) {
		r_error = MCPToolError::not_found(vformat("Parent '%s'", parent_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}

	Node *node = memnew(MeshInstance3D);
	add_typed_child(root, parent, name, node);

	Dictionary result;
	result["added"] = true;
	result["name"] = String(node->get_name());
	result["node_path"] = String(root->get_path_to(node));
	result["type"] = node->get_class();
	return result;
}

// ---------------------------------------------------------------------------
// editor_add_gridmap (old `add_gridmap`, scene_3d.rs:256)
//
// This is the group's behaviour correction. The migration source loaded
// `mesh_library_path` inside `if let Some(lib)` (scene_3d.rs:273-275) and then
// answered `{"created": true}` either way, so a GridMap whose mesh library never
// loaded was indistinguishable from a working one. Here the library is loaded
// first, through `MCPTools::attach_mesh_library`, and a load that produces no
// `MeshLibrary` is a `-32001` with a suggestion and **no node**.
//
// The answer keeps the migration source's four keys and adds the three the rest
// of the module uses (`node_path`, `type`, `mesh_library_set`); `parent_path` is
// echoed in its normalised, root-relative form (PLAYBOOK section 6.7).
// ---------------------------------------------------------------------------
static Variant _tool_add_gridmap(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_mesh_library_path;
	if (!_require_non_empty_string(p_args, "mesh_library_path", raw_mesh_library_path, r_error)) {
		return Variant();
	}
	String mesh_library_path;
	if (!normalize_project_path(raw_mesh_library_path, mesh_library_path, r_error)) {
		return Variant();
	}
	String parent_path;
	if (!_optional_parent_path(p_args, parent_path, r_error)) {
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", "GridMap", name, r_error)) {
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
	Node *parent = find_node(root, parent_path);
	if (parent == nullptr) {
		r_error = MCPToolError::not_found(vformat("Parent '%s'", parent_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}

	GridMap *gridmap = memnew(GridMap);
	if (!attach_mesh_library(gridmap, mesh_library_path, r_error)) {
		// The node was never added to the tree, so nothing of this call stays
		// behind - not even a GridMap without its library.
		memdelete(gridmap);
		return Variant();
	}
	add_typed_child(root, parent, name, gridmap);

	const Variant library = gridmap->get("mesh_library");

	Dictionary result;
	result["name"] = String(gridmap->get_name());
	result["parent_path"] = String(root->get_path_to(parent));
	result["mesh_library_path"] = mesh_library_path;
	result["created"] = true;
	result["node_path"] = String(root->get_path_to(gridmap));
	result["type"] = gridmap->get_class();
	result["mesh_library_set"] = library.get_type() != Variant::NIL;
	return result;
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

// The authoritative `description` and `inputSchema` of each tool are the contract
// entries of docs/tools_list.renamed.json, character for character; the schemas
// are *parsed* from the exact contract JSON instead of being rebuilt as a
// hand-written Dictionary, because the gate compares all three fields verbatim.
//
// `editor_add_raycast` and `editor_add_mesh_instance` carry string defaults
// ("2d" / "RayCast" / "Mesh"), which survive the JSON round trip unchanged; no
// schema of this group has a *number*, so the integral-number folding
// `editor_read_scene_inspector.cpp` needs has nothing to fold here.
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_node_instantiate.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_node_instantiate_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_add_scene_instance", String::utf8(R"desc(将外部场景作为实例添加到当前编辑场景)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"name":{"description":"实例节点名称 (可选)","type":"string"},"parent_path":{"default":".","description":"父节点路径, 默认 '.'","type":"string"},"scene_path":{"description":"要实例化的场景路径 (res://)","type":"string"}},"required":["scene_path"],"type":"object"})schema"));
		builder.handler(_tool_add_scene_instance).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_add_raycast", String::utf8(R"desc(添加射线检测节点)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"dimension":{"default":"2d","enum":["2d","3d"],"type":"string"},"name":{"default":"RayCast","type":"string"},"parent_path":{"default":".","type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_add_raycast).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_add_mesh_instance", String::utf8(R"desc(添加 MeshInstance3D)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"name":{"default":"Mesh","type":"string"},"parent_path":{"default":".","type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_add_mesh_instance).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_add_gridmap", String::utf8(R"desc(添加 GridMap 节点)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"mesh_library_path":{"type":"string"},"name":{"type":"string"},"parent_path":{"default":".","type":"string"}},"required":["mesh_library_path"],"type":"object"})schema"));
		builder.handler(_tool_add_gridmap).register_into(r_registry);
	}
}