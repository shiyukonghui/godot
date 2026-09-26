/**************************************************************************/
/*  editor_node_setup.cpp                                                 */
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
#include "editor_node_setup.h"

#include "tool_builder.h"
#include "tool_helpers.h"
// The group's one node-add path (`add_typed_child`: name, `add_child`, `owner =
// root`) and the module's one property write (`write_node_property`, widened to
// `Object *` by TASK-017 so the collision shape's `shape_params` can go through
// it as well). Neither is copied here.
#include "editor_node_instantiate.h"
#include "running_game_node_write.h"

#include "core/io/json.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/os/memory.h"
#include "core/string/node_path.h"
#include "core/string/string_name.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/3d/camera_3d.h"
#include "scene/3d/world_environment.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/resources/environment.h"

using namespace MCPTools;

// The runtime half of the editor guard lives in `tools/tool_helpers.*` and is
// called below as `require_editor_ui(r_error, <non-editor wording>,
// <suggestion>)`; `MCPTools::edited_scene_root()` and `MCPTools::find_node()`
// are the hoisted single definitions this group calls instead of copying.

// The migration source's own spelling for a node it returns (root is ".") is
// `MCPTools::relative_path` (`tools/tool_helpers.*`): the repair pass hoisted
// the copy this file used to carry.

// Whether `p_node`, or any ancestor of it, is (or derives from) `p_class`.
// `Object::is_class` answers for both the instance's own class and its bases, so
// this is the engine's own answer and not a name-substring test - which is what
// keeps `NavigationAgent3D` (a plain `Node`) out of the 3D test and a
// `CharacterBody3D` in it.
static bool _has_ancestor_class(Node *p_node, const StringName &p_class) {
	for (Node *current = p_node; current != nullptr; current = current->get_parent()) {
		if (current->is_class(p_class)) {
			return true;
		}
	}
	return false;
}

// The migration source's `is_3d_context` (navigation.rs:76-101) decided 3D when
// a class name contained "3D", 2D when it contained "2D", walked upwards and
// **fell through to `false` (2D)**. This implementation uses the class
// relationship instead of the name substring and falls through to **3D**, which
// is the documented default of the contract's own `name` default
// (`NavigationRegion3D` / `NavigationAgent3D`). The deviation is recorded in
// REPORT-017.
static bool _is_3d_context(Node *p_node) {
	for (Node *current = p_node; current != nullptr; current = current->get_parent()) {
		if (current->is_class(StringName("Node3D"))) {
			return true;
		}
		if (current->is_class(StringName("Node2D"))) {
			return false;
		}
	}
	return true;
}

	for (int i = 0; i < 3; i++) {
		const Variant component = components.get(COMPONENT_NAMES[i], Variant());
		if (component.get_type() == Variant::NIL) {
			continue;
		}
		if (component.get_type() != Variant::FLOAT && component.get_type() != Variant::INT) {
			r_error = MCPToolError::invalid_params(vformat("Parameter '%s.%s' must be a number, got %s",
					p_key, COMPONENT_NAMES[i], Variant::get_type_name(component.get_type())));
			return false;
		}
		// MCP-NARROWING: G24-ENV-COLOR-COMPONENT - the `Color(...)` line below
		// narrows; this is the TASK-023 gate that judges it first.
		if (!value_fits_slot(component, ValueSlot::FLOAT32, vformat("%s.%s", p_key, COMPONENT_NAMES[i]),
					"the 32-bit float component of the Color an Environment setter stores", r_error)) {
			return false;
		}
		values[i] = (double)component;
	}
	// MCP-NARROWING: G24-ENV-COLOR-COMPONENT - the `Color(...)` cast below is the
	// narrowing the per-component gate above judged (TASK-023 D-7).
	r_out = Color(values[0], values[1], values[2]);
	return true;
}

// A `number` argument is `MCPTools::optional_float` (`tools/tool_helpers.*`):
// `INT` is accepted because Godot's JSON parser has one number type, and the
// repair pass hoisted this file's reader together with the two other spellings
// of the same five lines.
//
// `shape_params` is an optional object and is `MCPTools::optional_dictionary`
// (`tools/tool_helpers.*`) for the same reason.

// An optional parent path: absent or empty means the edited scene root ("."),
// which is the migration source's `unwrap_or(".")`.
static bool _optional_parent_path(const Dictionary &p_args, String &r_out, MCPToolError &r_error) {
	if (!optional_string(p_args, "parent_path", ".", r_out, r_error)) {
		return false;
	}
	if (r_out.strip_edges().is_empty()) {
		r_out = ".";
	Node *target = find_node(p_root, p_node_path);
	if (target == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", p_node_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}

	MCPToolError instantiate_error;
	Object *shape_object = instantiate_class(p_shape_type, instantiate_error);
	if (shape_object == nullptr) {
		// The migration source's `_ =>` arm silently built a 2D rectangle for
		// *any* unrecognised name (physics.rs:131-139); that is a wrong result
		// reported as the requested one.
		r_error = MCPToolError::invalid_params(vformat(
				"Unknown shape_type: '%s' (%s). Supported: RectangleShape2D, CircleShape2D, BoxShape3D, SphereShape3D",
				p_shape_type, instantiate_error.message));
		return Variant();
	}
	if (!shape_object->is_class(StringName("Shape2D")) && !shape_object->is_class(StringName("Shape3D"))) {
		const String actual = shape_object->get_class();
		memdelete(shape_object);
		r_error = MCPToolError::invalid_params(vformat(
				"shape_type '%s' is neither a Shape2D nor a Shape3D (is %s). Supported: RectangleShape2D, CircleShape2D, BoxShape3D, SphereShape3D",
				p_shape_type, actual));
		return Variant();
	}
	// `Ref<Resource>` takes ownership of the freshly instantiated resource; every
	// early return below releases it.
	Ref<Resource> shape = Ref<Resource>(Object::cast_to<Resource>(shape_object));

	// The migration source accepted `shape_params` and never read it (`let
	// _shape_params`, physics.rs:88). Each entry is written onto the shape
	// resource through the module's one property write - which also gives the
	// vector-component grammar (`{"size": {"x": 32, "y": 32}}`) for free.
	const Array keys = p_shape_params.keys();
	for (int i = 0; i < keys.size(); i++) {
		const String key = keys[i];
		const Variant written = write_node_property(shape.ptr(), key, p_shape_params[key], r_error);
		if (written.get_type() == Variant::NIL) {
			return Variant();
		}
	}

	const bool is_2d = shape_object->is_class(StringName("Shape2D"));
	const String collision_class = is_2d ? "CollisionShape2D" : "CollisionShape3D";
	MCPToolError collision_error;
	Object *collision_object = instantiate_class(collision_class, collision_error);
	if (collision_object == nullptr) {
		r_error = MCPToolError::internal(vformat("Cannot create %s: %s", collision_class, collision_error.message));
		return Variant();
	}
	Node *collision = Object::cast_to<Node>(collision_object);
	collision->set("shape", shape);
	add_typed_child(p_root, target, collision_class, collision);

	const Variant shape_back = collision->get("shape");
	Dictionary result;
	result["setup"] = true;
	result["node_path"] = relative_path(p_root, target);
	result["shape_type"] = p_shape_type;
	result["collision_node_path"] = relative_path(p_root, collision);
	result["collision_node_type"] = collision->get_class();
	result["shape_set"] = shape_back.get_type() != Variant::NIL;
	return result;
}

Variant setup_world_environment_on(Node *p_root, bool p_path_given, const String &p_world_env_path,
		const Variant &p_bg_color, const Variant &p_ambient_color, MCPToolError &r_error) {
	// **Every colour is parsed and judged before anything is created** (TASK-023
	// D-7, the all-or-nothing rule every batch writer of the module keeps). The
	// M4c audit and this task's evidence run both measured the same side effect
	// when the refusal happened later: a `bg_color` the slot cannot hold answered
	// `-32602` **and** still left a freshly created `WorldEnvironment` +
	// `Environment` behind, so the scene file changed across a refused call. The
	// values are therefore read here, at the top, and only *applied* further down
	// where the node is guaranteed to exist.
	const bool has_bg_color = p_bg_color.get_type() != Variant::NIL;
	const bool has_ambient_color = p_ambient_color.get_type() != Variant::NIL;
		}
		WorldEnvironment *created = memnew(WorldEnvironment);
		add_typed_child(p_root, p_root, create_name, created);
		world_env = created;
		world_env_created = true;
	}

	Object *environment_object = world_env->get("environment");
	Ref<Environment> environment = Object::cast_to<Environment>(environment_object);
	bool environment_created = false;
	if (environment.is_null()) {
		environment = memnew(Environment);
		world_env->set("environment", environment);
		environment_created = true;
	}

	// Direct C++ calls, not the migration source's GDScript `Expression`
	// round-trip (scene_3d.rs:214-249): the observable state is the same and it
	// is assertable. `set_ambient_source(AMBIENT_SOURCE_COLOR)` is the explicit
	// behaviour correction - the migration source set the ambient *colour* only,
	// which has no effect while the ambient source is the sky/background.
	//
	// The two colours were already parsed and judged at the top of this function
	// (TASK-023 D-7): reaching this point means both are values the `Color` slot
	// can hold, so a refusal can no longer have created a node first.
	if (has_bg_color) {
		environment->set_background(Environment::BG_COLOR);
		environment->set_bg_color(bg_color);
	}
	if (has_ambient_color) {
		environment->set_ambient_source(Environment::AMBIENT_SOURCE_COLOR);
		environment->set_ambient_light_color(ambient_color);
	}

	Dictionary result;
	result["setup"] = true;
	result["world_environment"] = String(world_env->get_name());
	result["world_environment_path"] = relative_path(p_root, world_env);
	result["world_environment_created"] = world_env_created;
	result["environment_created"] = environment_created;
	return result;
}

Variant setup_lighting_on(Node *p_root, const String &p_parent_path, const String &p_light_type,
		MCPToolError &r_error) {
	Node *parent = find_node(p_root, p_parent_path);
	if (parent == nullptr) {
		r_error = MCPToolError::not_found(vformat("Parent '%s'", p_parent_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}
	// Case-insensitive, and the case-insensitivity is deliberate: the contract's
	// example is lower case (`directional`) while the class names are not.
	// Anything else is refused - the migration source turned every value other
	// than exactly `"directional"` into an omni light (scene_3d.rs:117), so
	// `"spot"` silently produced an `OmniLight3D`.
	const String lowered = p_light_type.to_lower();
	String light_class;
	if (lowered == "directional") {
		light_class = "DirectionalLight3D";
		memdelete(region);
		r_error = MCPToolError::internal(vformat("Cannot create %s: %s", resource_class, instantiate_error.message));
		return Variant();
	}
	Ref<Resource> resource = Ref<Resource>(Object::cast_to<Resource>(resource_object));

	// The configured values go onto the resource, and the answer reads them back
	// from it (the migration source echoed the request, navigation.rs:152-158).
	MCPToolError write_error;
	if (write_node_property(resource.ptr(), "agent_radius", p_agent_radius, write_error).get_type() == Variant::NIL ||
			write_node_property(resource.ptr(), "cell_size", p_cell_size, write_error).get_type() == Variant::NIL ||
			(is_3d && write_node_property(resource.ptr(), "agent_height", p_agent_height, write_error).get_type() == Variant::NIL)) {
		memdelete(region);
		r_error = write_error;
		return Variant();
	}
	region->set(is_3d ? "navigation_mesh" : "navigation_polygon", resource);

	const String region_name = p_name.is_empty() ? region_class : p_name;
	add_typed_child(p_root, parent, region_name, region);

	Ref<Resource> assigned = region->get(is_3d ? "navigation_mesh" : "navigation_polygon");
	Dictionary result;
	result["setup"] = true;
	result["node_path"] = relative_path(p_root, region);
	result["type"] = region->get_class();
	result["agent_radius"] = assigned.is_valid() ? (double)assigned->get("agent_radius") : 0.0;
	result["cell_size"] = assigned.is_valid() ? (double)assigned->get("cell_size") : 0.0;
	result["created"] = true;
	return result;
}

Variant setup_navigation_agent_on(Node *p_root, const String &p_node_path, const String &p_agent_type,
		const String &p_name, double p_radius, double p_max_speed, MCPToolError &r_error) {
	Node *parent = find_node(p_root, p_node_path);
	if (parent == nullptr) {
		r_error = MCPToolError::not_found(vformat("Parent '%s'", p_node_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}
	// Exact and case-sensitive, as the contract's `3D` / `2D` enumeration is.
	if (p_agent_type != "2D" && p_agent_type != "3D") {
		r_error = MCPToolError::invalid_params(vformat(
				"Unknown agent_type: '%s'. Available: 2D, 3D (case-sensitive)", p_agent_type));
		return Variant();
	}
	const bool is_3d = p_agent_type == "3D";
	const String agent_class = is_3d ? "NavigationAgent3D" : "NavigationAgent2D";
	const StringName required_context(is_3d ? "Node3D" : "Node2D");
	if (!_has_ancestor_class(parent, required_context)) {
		return Variant();
	}
	MCPToolError instantiate_error;
	Object *created = instantiate_class(p_body_type, instantiate_error);
	if (created == nullptr) {
		r_error = MCPToolError::internal(vformat("Cannot create %s: %s", p_body_type, instantiate_error.message));
		return Variant();
	}
	Node *body = Object::cast_to<Node>(created);
	add_typed_child(p_root, parent, p_name, body);

	Dictionary result;
	result["setup"] = true;
	result["parent_path"] = relative_path(p_root, parent);
	result["body_type"] = p_body_type;
	result["name"] = String(body->get_name());
	result["node_path"] = relative_path(p_root, body);
	result["type"] = body->get_class();
	result["created"] = true;
	return result;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// Tool handlers: argument parsing/typing only, then the exported helper above.
//
// Every argument-shape refusal is `-32602` and runs before the editor guard, so
// a malformed call is refused even in a process without an edited scene.
// ---------------------------------------------------------------------------
static Variant _tool_setup_camera_3d(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_path' must not be empty");
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
	return setup_camera_3d_on(root, node_path, r_error);
}

static Variant _tool_setup_collision_shape(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_path' must not be empty");
		return Variant();
	}
	String shape_type;
	if (!optional_string(p_args, "shape_type", "RectangleShape2D", shape_type, r_error)) {
		return Variant();
	}
	if (shape_type.strip_edges().is_empty()) {
		shape_type = "RectangleShape2D";
	}
	Dictionary shape_params;
	if (!optional_dictionary(p_args, "shape_params", shape_params, r_error)) {
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
	return setup_collision_shape_on(root, node_path, shape_type, shape_params, r_error);
}

static Variant _tool_setup_world_environment(const Dictionary &p_args, MCPToolError &r_error) {
	const Variant world_env_value = p_args.get("world_env_path", Variant());
	const bool path_given = world_env_value.get_type() != Variant::NIL;
	String world_env_path;
	if (path_given) {
		if (world_env_value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'world_env_path' must be a string, got %s",
					Variant::get_type_name(world_env_value.get_type())));
			return Variant();
		}
		world_env_path = world_env_value;
		if (world_env_path.strip_edges().is_empty()) {
			world_env_path = ".";
		}
	}
	// The colour objects are validated by the helper, so a non-object or a
	// non-numeric component is `-32602` there (nothing is silently swallowed).
	const Variant bg_color = p_args.get("bg_color", Variant());
	const Variant ambient_color = p_args.get("ambient_color", Variant());
	if (!require_editor_ui(r_error, "editor node writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return setup_world_environment_on(root, path_given, world_env_path, bg_color, ambient_color, r_error);
}

static Variant _tool_setup_lighting(const Dictionary &p_args, MCPToolError &r_error) {
	String parent_path;
	if (!_optional_parent_path(p_args, parent_path, r_error)) {
		return Variant();
	}
	String light_type;
static Variant _tool_setup_navigation_agent(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_path' must not be empty");
		return Variant();
	}
	String agent_type;
	if (!optional_string(p_args, "agent_type", "3D", agent_type, r_error)) {
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", String(), name, r_error)) {
		return Variant();
	}
	double radius = 0.0;
	if (!optional_float(p_args, "radius", 0.5, radius, r_error)) {
		return Variant();
	}
	double max_speed = 0.0;
	if (!optional_float(p_args, "max_speed", 10.0, max_speed, r_error)) {
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
	return setup_navigation_agent_on(root, node_path, agent_type, name, radius, max_speed, r_error);
}

static Variant _tool_setup_navigation_region(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_path' must not be empty");
		return Variant();
	}
	String mode;
	if (!optional_string(p_args, "mode", "auto", mode, r_error)) {
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", String(), name, r_error)) {
		return Variant();
	}
	double agent_radius = 0.0;
	if (!optional_float(p_args, "agent_radius", 0.5, agent_radius, r_error)) {
		return Variant();
	}
	double agent_height = 0.0;
	if (!optional_float(p_args, "agent_height", 1.5, agent_height, r_error)) {
		ToolBuilder builder("editor_setup_world_environment", String::utf8(R"desc(设置 3D 环境)desc"));
		builder.channel("editor").verb("setup").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"type":"object","properties":{"ambient_color":{"properties":{"b":{"type":"number"},"g":{"type":"number"},"r":{"type":"number"}},"type":"object"},"bg_color":{"properties":{"b":{"type":"number"},"g":{"type":"number"},"r":{"type":"number"}},"type":"object"},"world_env_path":{"type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_setup_world_environment).register_into(r_registry);
	}

//
// The authoritative `description` and `inputSchema` of each tool are the
// contract entries of docs/tools_list.renamed.json, character for character; the
// schemas are *parsed* from the exact contract JSON instead of being rebuilt as
// a hand-written Dictionary, because the gate compares all three fields
// verbatim.
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_node_setup.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_node_setup_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_setup_camera_3d", String::utf8(R"desc(配置 Camera3D)desc"));
		builder.channel("editor").verb("setup").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"type":"object","properties":{"node_path":{"type":"string"}},"required":["node_path"]})schema"));
		builder.handler(_tool_setup_camera_3d).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_setup_collision_shape", String::utf8(R"desc(为物理体添加碰撞形状)desc"));
		builder.channel("editor").verb("setup").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"type":"object","properties":{"node_path":{"type":"string"},"shape_params":{"description":"形状参数, 如 {\"size\": {\"x\": 32, \"y\": 32}}","type":"object"},"shape_type":{"default":"RectangleShape2D","type":"string"}},"required":["node_path"]})schema"));
		builder.handler(_tool_setup_collision_shape).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_setup_world_environment", String::utf8(R"desc(设置 3D 环境)desc"));
		builder.channel("editor").verb("setup").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"type":"object","properties":{"ambient_color":{"properties":{"b":{"type":"number"},"g":{"type":"number"},"r":{"type":"number"}},"type":"object"},"bg_color":{"properties":{"b":{"type":"number"},"g":{"type":"number"},"r":{"type":"number"}},"type":"object"},"world_env_path":{"type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_setup_world_environment).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_setup_lighting", String::utf8(R"desc(添加光照)desc"));
		builder.channel("editor").verb("setup").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"type":"object","properties":{"light_type":{"default":"directional","type":"string"},"parent_path":{"default":".","type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_setup_lighting).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_setup_navigation_agent", String::utf8(R"desc(设置导航代理)desc"));
		builder.channel("editor").verb("setup").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"type":"object","properties":{"agent_type":{"default":"3D","type":"string"},"max_speed":{"default":10.0,"type":"number"},"name":{"default":"NavigationAgent3D","type":"string"},"node_path":{"type":"string"},"radius":{"default":0.5,"type":"number"}},"required":["node_path"],"type":"object"})schema"));
		builder.handler(_tool_setup_navigation_agent).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_setup_navigation_region", String::utf8(R"desc(设置导航区域)desc"));
		builder.channel("editor").verb("setup").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"type":"object","properties":{"agent_height":{"default":1.5,"type":"number"},"agent_radius":{"default":0.5,"type":"number"},"cell_size":{"default":0.25,"type":"number"},"mode":{"default":"auto","description":"2d/3d/auto","type":"string"},"name":{"default":"NavigationRegion3D","type":"string"},"node_path":{"description":"父节点路径","type":"string"}},"required":["node_path"],"type":"object"})schema"));
		builder.handler(_tool_setup_navigation_region).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_setup_physics_body", String::utf8(R"desc(创建物理体节点)desc"));
		builder.channel("editor").verb("setup").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"type":"object","properties":{"body_type":{"default":"RigidBody2D","type":"string"},"name":{"type":"string"},"parent_path":{"default":".","type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_setup_physics_body).register_into(r_registry);
	}
}