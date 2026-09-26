/**************************************************************************/
/*  project_write_resource_scene.cpp                                      */
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
#include "project_write_resource_scene.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/error/error_macros.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/io/resource_loader.h"
#include "core/io/resource_saver.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/object/ref_counted.h"
#include "core/os/os.h"
#include "core/string/string_name.h"
#include "core/templates/hash_map.h"
#include "core/variant/callable.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/resources/packed_scene.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// Shared helpers
//
// The four tools of this group all follow the same shape: normalise the path,
// build or load an object, apply a caller supplied property bag, and publish the
// result. The helpers below are the three things they must do identically - a
// JSON value becomes a property value, a resource becomes a file, and an object
// becomes a property bag.
// ---------------------------------------------------------------------------

// `properties` is an *optional* argument in three of the four tools, but when it
// is present it must be an object (PLAYBOOK section 6.2: a present argument with
// the wrong type is an error, never silently ignored).
static bool _optional_properties(const Dictionary &p_args, Dictionary &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get("properties", Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = Dictionary();
		return true;
	}
	if (value.get_type() != Variant::DICTIONARY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'properties' must be an object, got %s",
				Variant::get_type_name(value.get_type())));
		return false;
	}
	r_out = value;
	return true;
}

// `shape_vector_from_json` for `_resource_property_value` below - the
// component-shaping step TASK-026 added to the two resource writers (the
// reasoning is next to that helper). No circular include:
// `running_game_node_write.h` does not include this file.
#include "running_game_node_write.h"

// The property-value conversion lives in `tools/tool_helpers.*` since TASK-009
// section 2.2: `property_value_from_json`, `coerce_to_property_type` and
// `property_type_of` are one definition per helper for both writing groups (this
// file used to own the full copy and `editor_write_scene_editor.cpp` a subset of
// it; the union, i.e. the superset, is what was hoisted). The conversion rules
// that used to be documented here - the integral fold, `#rrggbb`, the
// `Vector2(..)` / `Vector3(..)` grammar, "an object stays a Dictionary",
// `type_convert` and the non-finite-number refusal - are preserved next to that
// single definition.

// ---------------------------------------------------------------------------
// TASK-026 (E-9, third surface of E-3): the three steps every *other* write path
// of the module takes.
//
// `property_value_from_json` -> `shape_vector_from_json` -> `coerce_to_property_type`
// is the exact sequence of `MCPTools::prepare_node_property_value`
// (tools/running_game_node_write.cpp:664-680), which the editor node writer, the
// batch writer, the cross-scene writer and `project_set_setting` all use. The
// two resource writers used only the first and the third step, so every value
// the module's own read side answers as an *object* or as an array of objects -
// `{"x":..,"y":..}` for a `Vector2`, `{"r":..,"g":..,"b":..,"a":..}` for a
// `Color`, `[{x,y},..]` for a `PackedVector2Array`, all of them GDR-25 section
// 23.4's read-back shapes - was refused with `-32602` here while the same value
// was accepted on the node path. That is section 23.4's closure rule failing
// *between two tools of one module*: `project_read_resource` now answers those
// shapes (TASK-026 E-9) and `project_edit_resource` has to take them back.
//
// `shape_vector_from_json` is a no-op for a target that is not component-shaped,
// so nothing else about these two tools changes.
//
// TASK-027 D-8: an Object-valued property of a resource (`Environment.sky`,
// `Object.script`, ...) is taken by the same `coerce_to_property_type` OBJECT
// branch the node path uses, and the class the property declares is passed along
// so a resource of the wrong class is refused by name instead of stored as null.
// ---------------------------------------------------------------------------
static bool _resource_property_value(const Variant &p_raw_value, Variant::Type p_target_type,
		const StringName &p_property_name, const Object *p_object, Variant &r_out, MCPToolError &r_error) {
	const Variant json_value = property_value_from_json(p_raw_value, p_target_type);
	Variant shaped;
	if (!shape_vector_from_json(json_value, p_target_type, String(p_property_name), "properties", shaped, r_error)) {
		return false;
	}
	return coerce_to_property_type(shaped, p_target_type, r_out, r_error, "properties",
			ValueSlot::FROM_TARGET_TYPE,
			p_target_type == Variant::OBJECT ? object_property_class_hint(p_object, p_property_name) : String());
}

// The names of every property the object can be given through `set()`.
static HashSet<StringName> _property_names(const Object *p_object) {
	HashSet<StringName> names;
	List<PropertyInfo> properties;
	p_object->get_property_list(&properties);
	for (const PropertyInfo &property : properties) {
		names.insert(property.name);
	}
	return names;
}

// Whether `p_name` may be handed to `Object::set()` at all.
static bool _is_settable_property_name(const StringName &p_name) {
	return String(p_name).is_valid_identifier();
}

static HashMap<StringName, bool> _property_table(const Object *p_object) {
	HashMap<StringName, bool> table;
	List<PropertyInfo> properties;
	p_object->get_property_list(&properties);
	for (const PropertyInfo &property : properties) {
		const bool is_label = property_is_label(property);
		if (table.has(property.name)) {
			table[property.name] = table[property.name] && is_label;
		} else {
			table[property.name] = is_label;
		}
	}
	return table;
}

namespace MCPTools {

bool resource_bag_name_is_addressable(const StringName &p_name) {
	return String(p_name).is_valid_identifier();
}

} // namespace MCPTools


// The JSON image of a property, for the old/new pair of a `changed` entry.
static Variant _serialized_property(const Object *p_object, const StringName &p_name) {
	return serialize_variant(p_object->get(p_name));
}

// ---------------------------------------------------------------------------
// TASK-022 D-5: "was it really set?" is a **read-back** question.
//
// `project_create_resource` used to answer `properties_set: ["min_value"]` for
// `Curve.min_value = 5.0` and report nothing else, while the engine's own setter
// had stored `max_value - 0.01` (0.99) - the M4b re-audit measured it and noted
// that the sibling `project_edit_resource` answers the same call with a real
// `changed: {min_value: {old, new}}`. The two entries now have one standard: the
// value is read back after `Object::set()` and compared with what the caller
// asked for, and an attribute the setter did not store as asked is reported as
// `ignored` instead of as "set".
//
// The comparison is made at the width the member really stores. A single
// precision member keeps the nearest `float`, so `(double)(float)0.1` is not
// `0.1`; comparing doubles would report a perfectly good write as "ignored". For
// every other target the serialized images are compared directly (a vector is a
// component object on both sides, so the comparison is a structural one).
//
// MCP-NARROWING: G24-RESOURCE-SET-WIDTH (TASK-023 D-7). The `(real_t)` casts
// below narrow a serialized `double` to the member's width; they are safe
// **because they are the comparison's own width**, and they cannot lose a value
// the write gate has already refused: `properties` is coerced through
// `coerce_to_property_type` (the `REAL_T` slot) *before* `Object::set()`, so the
// requested side is a value the 32-bit slot can hold, and both sides are then
// narrowed to that one width. A caller that could reach this line with `1e300`
// would get the honest answer "the stored value is not the request" - which is
// what the `ignored` entry of the D-5 read-back exists to say.
// ---------------------------------------------------------------------------
static bool _stored_value_matches_request(const Variant &p_requested_serialized,
		const Variant &p_stored_serialized, Variant::Type p_target_type) {
	if (p_target_type == Variant::FLOAT) {
		// MCP-NARROWING: G24-RESOURCE-SET-WIDTH - the two `(real_t)` casts below
		// are the comparison's own width, and the requested side reached this
		// function through the `REAL_T` gate (TASK-023 D-7).
		return (real_t)p_requested_serialized == (real_t)p_stored_serialized;
	}
	return p_requested_serialized == p_stored_serialized;
}

// The one `properties` bag writer both resource tools use. It is declared here
// and defined further down (next to `project_edit_resource`, where its rules are
// written out) because `project_create_resource` calls it and the two tools are
// otherwise ordered as the manifest lists them.
static bool _write_resource_properties(const Ref<Resource> &p_resource, const Dictionary &p_properties,
		Dictionary &r_changed, Dictionary &r_ignored, Array &r_properties_set, MCPToolError &r_error);

	// The body stays where the recorded revision keeps it (next to `project_edit_resource`);
	// `_tool_create_resource` calls it long before that.
	static bool _require_properties(const Dictionary &p_args, Dictionary &r_out, MCPToolError &r_error);

// ---------------------------------------------------------------------------
// Atomic publish (TASK-007 section 3.1)
//
// `ResourceSaver::save()` writes straight into the destination, so a failure in
// the middle of a save (a full disk, a format saver that refuses the value, a
// write error) can leave a truncated - that is, **corrupted** - file where the
// caller's resource used to be. The migration source did exactly that.
//
// TASK-008 section 3 hoisted the mechanism into `tools/tool_helpers.*`
// (`publish_file_atomically`, `temporary_sibling_path`) so that the editor write
// group's `editor_save_scene` shares it instead of growing a second, subtly
// different copy. What is left here is the same private name the four tools of
// this group already call, plus the one-line adapter that lets the shared helper
// drive `ResourceSaver::save()`:
//
//   * the temporary file name keeps its extension last (`created.mcp-tmp.tres`),
//     because `ResourceFormatSaver::recognize_path()` compares the text after the
//     **last** dot against the saver's extension list (a measured bug of an
//     earlier revision, REPORT-007 section 8.1);
//   * the destination is only touched after a *successful* save of a temporary
//     sibling that really exists, the old bytes are copied aside first, and a
//     failed publish puts them back.
//
// On every failure path the temporary file (and the backup) is removed: the
// group may not leave a half-written artefact behind.
// ---------------------------------------------------------------------------

static Error _resource_save_writer(const String &p_temp_path, void *p_userdata) {
	const Ref<Resource> *resource = static_cast<const Ref<Resource> *>(p_userdata);
	return ResourceSaver::save(*resource, p_temp_path);
}

static Error _save_resource_atomically(const Ref<Resource> &p_resource, const String &p_path) {
	// The `Ref` is copied into a local so that the callback has a stable address
	// for the whole call; `publish_file_atomically` never stores it.
	Ref<Resource> held = p_resource;
	return publish_file_atomically(p_path, _resource_save_writer, &held);
}

// ---------------------------------------------------------------------------
// project_create_resource (old `create_resource`, resource.rs:199)
//
// `path` + `type` are required; `properties` (object) and `overwrite` (bool,
// default false) are optional. The type has to be an *instantiable* `Resource`
// subclass; an unknown or non-resource class is -32602, because it is the
// argument that names the class. An existing file is refused with -32000 unless
// `overwrite = true` says otherwise - the migration source had that guard, and
// the write group keeps it.
//
// Returns `{"path","type","properties_set":[...],"changed":{}}`.
// ---------------------------------------------------------------------------

static Variant _tool_create_resource(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!require_string(p_args, "path", raw_path, r_error)) {
		return Variant();
	}
	String path;
	if (!normalize_project_path(raw_path, path, r_error)) {
		return Variant();
	}
	String type_name;
	if (!require_string(p_args, "type", type_name, r_error)) {
		return Variant();
	}
	Dictionary properties;
	if (!_optional_properties(p_args, properties, r_error)) {
		return Variant();
	}
	bool overwrite = false;
	if (!optional_bool(p_args, "overwrite", false, overwrite, r_error)) {
		return Variant();
	}

	if (path == String("res://")) {
		r_error = MCPToolError::invalid_params(
				"Parameter 'path' must name a file, got the project root 'res://'");
		return Variant();
	}
	if (FileAccess::exists(path) && !overwrite) {
		r_error = MCPToolError::tool_state(vformat("Resource already exists: %s", path),
				"Set overwrite=true to replace the existing file");
		return Variant();
	}

	const StringName class_name(type_name);
	if (!ClassDB::class_exists(class_name) || !ClassDB::can_instantiate(class_name) ||
			!ClassDB::is_parent_class(class_name, "Resource")) {
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'type' must name a resource class, got '%s'", type_name));
		return Variant();
	}
	Object *created = ClassDB::instantiate(class_name);
	Resource *resource = Object::cast_to<Resource>(created);
	if (resource == nullptr) {
		if (created != nullptr) {
			memdelete(created);
		}
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'type' must name a resource class, got '%s'", type_name));
		return Variant();
	}
	const Ref<Resource> resource_ref(resource);

	Array properties_set;
	// TASK-022 D-5: the three fields the answer carries about the `properties`
	// bag, all of them built from a read-back of the object (see
	// `_stored_value_matches_request`):
	//   * `changed` - `{<name>: {old, new}}`, the same shape
	//     `project_edit_resource` answers, so the caller can see what the engine
	//     really stored;
	//   * `properties_set` - only the names whose read-back **is** the value that
	//     was asked for;
	//   * `ignored` - the names the engine's own setter stored differently (it
	//     clamped or refused the value), with the requested and the stored value
	//     and the reason, so "I set it" is never claimed for them.
	//
	// TASK-037 D2: the validation, the write and the read-back moved into
	// `_write_resource_properties` (below), because `project_edit_resource` has
	// to answer the *same* call the same way. What changed for this tool is the
	// unknown-name rule: a name the resource does not have is a `-32001` naming
	// it, not a silent skip (see the comment on the helper).
	Dictionary ignored;
	Dictionary changed;
	if (!properties.is_empty()) {
		if (!_write_resource_properties(resource, properties, changed, ignored, properties_set, r_error)) {
			return Variant();
		}
	}

	const Error save_error = _save_resource_atomically(resource_ref, path);
	if (save_error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to save resource: %s", error_names[(int)save_error]));
		return Variant();
	}

	Dictionary result;
	result["path"] = path;
	result["type"] = resource->get_class();
	result["properties_set"] = properties_set;
	result["ignored"] = ignored;
	// TASK-037 D2: the same "was anything not stored as asked?" counter the
	// sibling `project_edit_resource` answers, so a caller can branch on one
	// number instead of walking the bag.
	result["ignored_count"] = ignored.size();
	result["changed"] = changed;
	return result;
}

// ---------------------------------------------------------------------------
// project_create_scene_file (old `create_scene`, scene.rs:171)
//
// `path` is required; `root_type` (default "Node2D") and `root_name` (default:
// the file stem) are optional. The root type has to be an instantiable `Node`
// subclass. Unlike the migration source this tool **refuses to replace an
// existing file** (-32000 + suggestion): the contract has no `overwrite`
// argument, and a write tool that silently replaces a scene is not something a
// caller can opt out of. Everything else - the packing, the root name default,
// the "Node" fallback of the reference's `unwrap_or` - is unchanged.
//
// Returns `{"path","root_type","root_name","created":true}`.
// ---------------------------------------------------------------------------

static Variant _tool_create_scene_file(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!require_string(p_args, "path", raw_path, r_error)) {
		return Variant();
	}
	String path;
	if (!normalize_project_path(raw_path, path, r_error)) {
		return Variant();
	}
	String type_name;
	if (!optional_string(p_args, "root_type", "Node2D", type_name, r_error)) {
		return Variant();
	}
	String requested_name;
	if (!optional_string(p_args, "root_name", String(), requested_name, r_error)) {
		return Variant();
	}

	if (path == String("res://")) {
		r_error = MCPToolError::invalid_params(
				"Parameter 'path' must name a file, got the project root 'res://'");
		return Variant();
	}
	if (FileAccess::exists(path)) {
		r_error = MCPToolError::tool_state(vformat("Scene file already exists: %s", path),
				"Delete it first with project_delete_scene_file, or choose another path");
		return Variant();
	}

	const StringName class_name(type_name);
	if (!ClassDB::class_exists(class_name) || !ClassDB::can_instantiate(class_name) ||
			!ClassDB::is_parent_class(class_name, "Node")) {
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'root_type' must name a node class, got '%s'", type_name));
		return Variant();
	}
	Object *created = ClassDB::instantiate(class_name);
	Node *root = Object::cast_to<Node>(created);
	if (root == nullptr) {
		if (created != nullptr) {
			memdelete(created);
		}
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'root_type' must name a node class, got '%s'", type_name));
		return Variant();
	}

	String root_name = requested_name;
	if (root_name.is_empty()) {
		root_name = path.get_file().get_basename();
	}
	if (root_name.is_empty()) {
		root_name = "Node";
	}
	root->set_name(root_name);

	Ref<PackedScene> scene;
	scene.instantiate();
	const Error pack_error = scene->pack(root);
	if (pack_error != OK) {
		memdelete(root);
		r_error = MCPToolError::internal(vformat("Failed to pack the scene: %s", error_names[(int)pack_error]));
		return Variant();
	}
	// The packed scene holds everything it needs; the temporary root node goes
	// away again once packing succeeded (the reference `queue_free()`s it).
	memdelete(root);

	const Error save_error = _save_resource_atomically(scene, path);
	if (save_error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to save the scene: %s", error_names[(int)save_error]));
		return Variant();
	}

	Dictionary result;
	result["path"] = path;
	result["root_type"] = type_name;
	result["root_name"] = root_name;
	result["created"] = true;
	return result;
}


// ---------------------------------------------------------------------------
// project_delete_scene_file (old `delete_scene`, scene.rs:251)
//
// `path` is required and must exist, otherwise -32001 with a suggestion (the
// migration source returned not_found as well). The scene file and, when it is
// there, its `<path>.import` sidecar are removed - the `rescan` the reference
// performed afterwards is an editor-side refresh that the tool does not need.
//
// Returns `{"path","deleted":true}` where `path` is the *normalised* path.
// ---------------------------------------------------------------------------

static Variant _tool_delete_scene_file(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!require_string(p_args, "path", raw_path, r_error)) {
		return Variant();
	}
	String path;
	if (!normalize_project_path(raw_path, path, r_error)) {
		return Variant();
	}

	if (!FileAccess::exists(path)) {
		r_error = MCPToolError::not_found(vformat("Scene file '%s'", path),
				"Use project_get_filesystem_tree to list the .tscn files of the project");
		return Variant();
	}

	const Error remove_error = DirAccess::remove_absolute(path);
	if (remove_error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to delete the scene file: %s",
				error_names[(int)remove_error]));
		return Variant();
	}
	// A scene that was imported has a sidecar; it is removed with the scene.
	const String import_path = path + ".import";
	if (FileAccess::exists(import_path)) {
		DirAccess::remove_absolute(import_path);
	}

	Dictionary result;
	result["path"] = path;
	result["deleted"] = true;
	return result;
}

// ---------------------------------------------------------------------------
// TASK-037 D2: the one `properties` bag writer of the two resource tools.
//
// Before this task the two tools were *almost* the same loop and differed in
// exactly the way the M4e/B5 audit (REPORT-AUDIT-B5 D2) reported:
//
//   * `project_create_resource` skipped a name the object does not have and
//     answered `{"properties_set":[],"message":"No properties were changed"}`
//     (a success shape);
//   * `project_edit_resource` did the same, *and* it listed an engine-clamped
//     value in `changed` with no `ignored` entry at all.
//
// Both halves are the failure class this module exists to remove: a response
// that is a success and says nothing about a parameter that was never applied.
// The rule is now one rule, taken from `DESIGN-DETAIL` section 20.6 and
// PLAYBOOK section 6.1:
//
//   * a key that is not a settable property name is a bad *argument*
//     (`-32602`) - it can never address a property, so the name is the problem
//     (the same judgement `editor_set_node_property` makes through
//     `split_property_path` / `_is_settable_property_name`);
//   * a well-formed key the object does not have is `-32001` **naming it** in
//     `data.suggestion` (the TASK-014 D-1 shape). The whole call is refused and
//     nothing is written, so "some of my properties were applied and some were
//     not" cannot be mistaken for "all of them were";
//   * only then is the value coerced and written, and the object is read back:
//     a value the engine's own setter stored differently goes to `ignored` with
//     `requested` / `stored` / `reason`, and only a name whose read-back **is**
//     the request goes to `properties_set`.
//
// Refusing on the first unknown name (rather than reporting a partial write) is
// what makes the refusal *actionable*: the caller learns the name, fixes it and
// re-sends, and no half-applied bag is left behind. A bag that legitimately
// wants "whatever exists" has no expression here - and that is deliberate, since
// a silent subset write is exactly the shape being eliminated.
// ---------------------------------------------------------------------------
static bool _write_resource_properties(const Ref<Resource> &p_resource, const Dictionary &p_properties,
		Dictionary &r_changed, Dictionary &r_ignored, Array &r_properties_set, MCPToolError &r_error) {
	const HashMap<StringName, bool> table = _property_table(p_resource.ptr());
	const Array keys = p_properties.keys();
	for (int i = 0; i < keys.size(); i++) {
		const StringName key(keys[i]);
		const bool *is_label = table.getptr(key);
		if (String(key).is_empty()) {
			// A nameless key can never address a property: it is the argument
			// that is wrong, not the resource.
			r_error = MCPToolError::invalid_params(
					"Property name must not be empty: Object::set() cannot address a property without a name");
			return false;
		}
		if (is_label != nullptr && *is_label) {
			r_error = MCPToolError::invalid_params(vformat(
					"Property name '%s' is an inspector group/category label, not a property: %s's own property list "
					"carries it with PROPERTY_USAGE_GROUP/SUBGROUP/CATEGORY, which has no value and no setter",
					String(key), p_resource->get_class()));
			return false;
		}
		if (is_label == nullptr) {
			// TASK-049: the object's own property table is the authority on what
			// a property is - it is the table `Object::set()` itself resolves
			// through, and it is what the readers enumerate. A name that is not
			// a *name* at all is the argument's fault (-32602); a well-formed
			// name the table does not carry is an unknown property (-32001,
			// naming it).
			if (!resource_bag_name_is_addressable(key)) {
				// [REBUILT-2C low-confidence: verify]
				r_error = MCPToolError::invalid_params(vformat(
						"Property name '%s' is not a settable property name: Object::set() takes a non-empty identifier",
						String(key)));
				return false;
			}
			r_error = MCPToolError::not_found(
					vformat("Property '%s' on %s", String(key), p_resource->get_class()),
					vformat("'%s' is not a property of %s; read the properties this resource really has with "
							"project_read_resource (its 'properties' object is exactly what this tool takes back)",
							String(key), p_resource->get_class()));
			return false;
		}
		const Variant::Type target_type = property_type_of(p_resource.ptr(), key);
		Variant value;
		if (!_resource_property_value(p_properties[keys[i]], target_type, key, p_resource.ptr(), value, r_error)) {
			return false;
		}
		const Variant old_value = _serialized_property(p_resource.ptr(), key);
		p_resource->set(key, value);
		const Variant new_value = _serialized_property(p_resource.ptr(), key);

		Dictionary entry;
		entry["old"] = old_value;
		entry["new"] = new_value;
		r_changed[String(key)] = entry;

		// TASK-022 D-5 / DESIGN-DETAIL section 20.6: "was it really set?" is a
		// read-back question. The comparison is made at the member's width (see
		// `_stored_value_matches_request`).
		if (_stored_value_matches_request(serialize_variant(value), new_value, target_type)) {
			r_properties_set.push_back(String(key));
		} else {
			Dictionary miss;
			miss["requested"] = serialize_variant(value);
			miss["stored"] = new_value;
			miss["reason"] = "the engine's own property setter stored a different value for this property "
							 "(it clamps or refuses input outside its own range), so it is not reported as set";
			r_ignored[String(key)] = miss;
		}
	}
	return true;
}

namespace MCPTools {

// The exported name the header declares (project_write_resource_scene.h).
bool write_resource_properties(const Ref<Resource> &p_resource, const Dictionary &p_properties,
		Dictionary &r_changed, Dictionary &r_ignored, Array &r_properties_set, MCPToolError &r_error) {
	return _write_resource_properties(p_resource, p_properties, r_changed, r_ignored, r_properties_set, r_error);
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// project_edit_resource (old `edit_resource`, resource.rs:131)
//
// `path` and `properties` are both required. The resource is loaded, every
// property of the bag is written through `_write_resource_properties`, and the
// result is saved.
//
// TASK-037 D2 - the observable contract of the bag, one rule for both resource
// writers (see the helper):
//   * a name that is not a settable identifier -> `-32602`, nothing written;
//   * a name the resource does not have -> `-32001` + `data.suggestion` naming
//     it, nothing written and **no file is touched**;
//   * a value the engine's setter clamped or refused -> the entry appears in
//     `ignored` with `requested` / `stored` / `reason` (it is *also* in
//     `changed`, which reports the read-back truth); `properties_set` lists the
//     names whose read-back is the request.
//
// Returns `{"path","type","changed":{<name>:{"old","new"}},"ignored":{...},
// "properties_set":[...]}`. An **empty** `properties` bag still answers the
// reference's `{"path","changed":{},"message":"No properties were changed"}`
// shape and writes nothing: "the caller named no property at all" is a
// different statement from "a name the caller gave does not exist", and only the
// second one is an error.
// ---------------------------------------------------------------------------

static bool _require_properties(const Dictionary &p_args, Dictionary &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get("properties", Variant());
	if (value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter: properties");
		return false;
	}
	if (value.get_type() != Variant::DICTIONARY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'properties' must be an object, got %s",
				Variant::get_type_name(value.get_type())));
		return false;
	}
	r_out = value;
	return true;
}

static Variant _tool_edit_resource(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!require_string(p_args, "path", raw_path, r_error)) {
		return Variant();
	}
	String path;
	if (!normalize_project_path(raw_path, path, r_error)) {
		return Variant();
	}
	Dictionary properties;
	if (!_require_properties(p_args, properties, r_error)) {
		return Variant();
	}

	if (!FileAccess::exists(path)) {
		r_error = MCPToolError::not_found(vformat("Resource '%s'", path),
				"Use project_get_filesystem_tree to list the resources of the project");
		return Variant();
	}
	const Ref<Resource> resource = ResourceLoader::load(path);
	if (resource.is_null()) {
		// The file is there but is not (or no longer) a loadable resource. It is
		// deliberately left exactly as it is: a read failure must never turn
		// into a write.
		r_error = MCPToolError::not_found(vformat("Loadable resource '%s'", path),
				"The file exists but could not be loaded as a resource; fix or delete it first");
		return Variant();
	}

	Dictionary changed;
	Dictionary ignored;
	Array properties_set;
	if (!properties.is_empty()) {
		if (!write_resource_properties(resource, properties, changed, ignored, properties_set, r_error)) {
			return Variant();
		}
	}

	// The reference's "nothing to do" short circuit, kept for the one case where
	// it is honest: the caller sent an **empty** bag. A bag that named a property
	// the resource does not have never reaches this line (it is a -32001 above),
	// which is the TASK-037 D2 fix - the old code answered this same success
	// shape for `{"no_such_property": 1}` and left the caller unable to tell the
	// two apart.
	if (changed.is_empty()) {
		Dictionary result;
		result["path"] = path;
		result["changed"] = Dictionary();
		result["message"] = "No properties were changed";
		return result;
	}

	const Error save_error = _save_resource_atomically(resource, path);
	if (save_error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to save resource: %s", error_names[(int)save_error]));
		return Variant();
	}

	Dictionary result;
	result["path"] = path;
	result["type"] = resource->get_class();
	result["changed"] = changed;
	result["properties_set"] = properties_set;
	// DESIGN-DETAIL section 20.6: an attribute the engine's setter stored
	// differently is named here, with the requested value, the stored value and
	// the reason, so a `changed` entry is never read as "the value I asked for".
	result["ignored"] = ignored;
	result["ignored_count"] = ignored.size();
	return result;
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

// The authoritative `description` and `inputSchema` of each tool are the contract
// entries of docs/tools_list.renamed.json, character for character. The schemas
// are parsed from the exact contract JSON instead of being rebuilt as a
// hand-written Dictionary - a hand transcription is where a description byte or
// the type of a `"default": false` drifts, and gate 1 compares all three fields
// verbatim. Godot's JSON has a single number type, so integral numbers are
// folded back to INT (`"default": 256` would otherwise be written `256.0`).
static Variant _fold_integral_numbers(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::FLOAT: {
			const double number = p_value;
			if (number >= -9.0e15 && number <= 9.0e15) {
				const int64_t truncated = (int64_t)number;
				if ((double)truncated == number) {
					return Variant(truncated);
				}
			}
			return p_value;
		}
		case Variant::DICTIONARY: {
			const Dictionary source = p_value;
			Dictionary out;
			const Array keys = source.keys();
			for (int i = 0; i < keys.size(); i++) {
				out[keys[i]] = _fold_integral_numbers(source[keys[i]]);
			}
			return out;
		}
		case Variant::ARRAY: {
			const Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(_fold_integral_numbers(source[i]));
			}
			return out;
		}
		default:
			return p_value;
	}
}

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_write_resource_scene.cpp");
		return Dictionary();
	}
	return _fold_integral_numbers(json.get_data());
}

void register_project_write_resource_scene_tools(MCPToolRegistry &r_registry) {
	// Order follows docs/tool-groups.json. The order is not a contract, but it
	// has to be stable and append-only. Every tool is channel `project`,
	// `mutating = true` (the only mutating group of B1) and `scope = BOTH`.
	{
		ToolBuilder builder("project_create_resource", String::utf8(R"desc(创建新资源文件)desc"));
		builder.channel("project").verb("create").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"overwrite":{"default":false,"description":"是否覆盖已存在的文件","type":"boolean"},"path":{"description":"保存路径 (res://)","type":"string"},"properties":{"description":"初始属性字典","type":"object"},"type":{"description":"资源类型","type":"string"}},"required":["path","type"],"type":"object"})schema"));
		builder.handler(_tool_create_resource).register_into(r_registry);
	}

	{
		ToolBuilder builder("project_create_scene_file", String::utf8(R"desc(创建新场景文件)desc"));
		builder.channel("project").verb("create").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"path":{"description":"保存路径 (res://)","type":"string"},"root_name":{"description":"根节点名称 (可选)","type":"string"},"root_type":{"default":"Node2D","description":"根节点类型","type":"string"}},"required":["path"],"type":"object"})schema"));
		builder.handler(_tool_create_scene_file).register_into(r_registry);
	}

	{
		ToolBuilder builder("project_delete_scene_file", String::utf8(R"desc(删除场景文件)desc"));
		builder.channel("project").verb("delete").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"path":{"description":"要删除的场景文件路径 (res://)","type":"string"}},"required":["path"],"type":"object"})schema"));
		builder.handler(_tool_delete_scene_file).register_into(r_registry);
	}

	{
		ToolBuilder builder("project_edit_resource", String::utf8(R"desc(编辑资源文件属性并保存)desc"));
		builder.channel("project").verb("edit").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"path":{"description":"资源文件路径 (res://)","type":"string"},"properties":{"description":"要修改的属性字典","type":"object"}},"required":["path","properties"],"type":"object"})schema"));
		builder.handler(_tool_edit_resource).register_into(r_registry);
	}
}
