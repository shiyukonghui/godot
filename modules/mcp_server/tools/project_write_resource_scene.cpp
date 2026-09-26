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

	const HashSet<StringName> names = _property_names(resource.ptr());
	Dictionary changed;

	const Array keys = properties.keys();
	for (int i = 0; i < keys.size(); i++) {
		const StringName key(keys[i]);
		if (!names.has(key) || !_is_settable_property_name(key)) {
			continue;
		}
		const Variant old_value = _serialized_property(resource.ptr(), key);
		const Variant::Type target_type = property_type_of(resource.ptr(), key);
		Variant value;
		if (!coerce_to_property_type(property_value_from_json(properties[keys[i]], target_type),
					target_type, value, r_error, "properties")) {
			return Variant();
		}
		resource->set(key, value);

		Dictionary entry;
		entry["old"] = old_value;
		entry["new"] = _serialized_property(resource.ptr(), key);
		changed[String(key)] = entry;
	}

	// The reference's "nothing to do" short circuit: when the bag named no
	// property the resource actually has, nothing is written and no file is
	// touched at all. (A property that is written with its current value *is* a
	// change - the reference reports it the same way - and rewriting identical
	// bytes is harmless.)
	if (changed.is_empty()) {
		Dictionary result;
		result["path"] = path;
		result["changed"] = Dictionary();
		result["message"] = "No properties were changed";
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
				r_error = MCPToolError::invalid_params(vformat(
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