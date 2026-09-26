/**************************************************************************/
/*  project_setting_write.cpp                                             */
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
#include "project_setting_write.h"

#include "running_game_node_write.h"
#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/config/project_settings.h"
#include "core/io/json.h"
#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// project_set_setting (old `set_project_setting`, project.rs:173)
//
// Migration source (semantic reference, read-only):
// `addons/godot_mcp/commands/project_commands.gd:173-212`.
//
// Observable contract (as implemented):
//   * `key` (string, required, non-blank): the `ProjectSettings` key, in the
//     engine's own `section/subsection/name` spelling;
//   * `value` (**required, any JSON type** - presence, not nullness, is what
//     "required" means);
//   * `type` (string, optional): the target type's name (see the accepted list
//     in the refusal message). It is the only way to declare the type of a key
//     the project does not have yet; when the key *does* exist the name is
//     checked against the declared type and a mismatch is `-32602`;
//   * the value is parsed with the target type's own grammar
//     (`property_value_from_json`) and coerced with the one shared
//     `coerce_to_property_type`, so `Vector2`/`Color`/`int` settings keep their
//     type and an impossible value (`1e20` into an `int` setting, a scalar into
//     a `Vector2` setting) is `-32602` **instead of being written as a default**
//     (TASK-018 section 1);
//   * `project.godot` is published atomically; a failed publish restores the
//     previous in-memory value and answers `-32603`;
//   * the answer is `{"key","value","type","existed_before","created","saved"}`,
//     where `value` is read **back** from `ProjectSettings` after the write, so
//     a setter that clamped or refused the value is visible.
//
// Deliberate divergences from the migration source, which the report lists:
//   * a key the project does not declare is reported (`created: true`); the
//     migration source could not tell the caller that it had just invented a
//     setting nothing reads;
//   * a string value is *not* run through `Expression` (project_commands.gd:
//     188-201). That path silently turned `"1e20"`/`"true"`/`"Vector2(1,2)"`
//     into different values with no type check; here the property's own type
//     decides, and `"true"` into a `bool` setting is that type's own grammar.
//   * `null` for a brand-new key is refused with `-32602`: it would create a
//     setting whose value the engine cannot store, which is a silent no-op.
// ---------------------------------------------------------------------------

namespace MCPTools {

// The type names this tool can write. An explicit list rather than a loop over
// `Variant::get_type_name()` so that the accepted set is reviewable and can be
// quoted verbatim in the refusal message: every entry is a type a
// `project.godot` value can really hold, and every entry can be produced from
// JSON by `property_value_from_json` + `coerce_to_property_type`.
struct _TypeNameEntry {
	const char *name;
	Variant::Type type;
};

static const _TypeNameEntry TYPE_NAMES[] = {
	{ "bool", Variant::BOOL },
	{ "boolean", Variant::BOOL },
	{ "int", Variant::INT },
	{ "integer", Variant::INT },
	{ "float", Variant::FLOAT },
	{ "number", Variant::FLOAT },
	{ "String", Variant::STRING },
	{ "StringName", Variant::STRING_NAME },
	{ "NodePath", Variant::NODE_PATH },
	{ "Vector2", Variant::VECTOR2 },
	{ "Vector2i", Variant::VECTOR2I },
	{ "Vector3", Variant::VECTOR3 },
	{ "Vector3i", Variant::VECTOR3I },
	{ "Vector4", Variant::VECTOR4 },
	{ "Vector4i", Variant::VECTOR4I },
	{ "Rect2", Variant::RECT2 },
	{ "Rect2i", Variant::RECT2I },
	{ "Color", Variant::COLOR },
	{ "Array", Variant::ARRAY },
	{ "Dictionary", Variant::DICTIONARY },
	{ "PackedStringArray", Variant::PACKED_STRING_ARRAY },
	{ "PackedByteArray", Variant::PACKED_BYTE_ARRAY },
	{ "PackedInt32Array", Variant::PACKED_INT32_ARRAY },
	{ "PackedInt64Array", Variant::PACKED_INT64_ARRAY },
	{ "PackedFloat32Array", Variant::PACKED_FLOAT32_ARRAY },
	{ "PackedFloat64Array", Variant::PACKED_FLOAT64_ARRAY },
	{ "PackedVector2Array", Variant::PACKED_VECTOR2_ARRAY },
	{ "PackedVector3Array", Variant::PACKED_VECTOR3_ARRAY },
	{ "PackedVector4Array", Variant::PACKED_VECTOR4_ARRAY },
	{ "PackedColorArray", Variant::PACKED_COLOR_ARRAY },
};

static const int TYPE_NAME_COUNT = sizeof(TYPE_NAMES) / sizeof(TYPE_NAMES[0]);

Variant::Type variant_type_from_name(const String &p_name) {
	const String wanted = p_name.strip_edges();
	for (int i = 0; i < TYPE_NAME_COUNT; i++) {
		if (wanted == String(TYPE_NAMES[i].name)) {
			return TYPE_NAMES[i].type;
		}
	}
	return Variant::VARIANT_MAX;
}

bool set_project_setting(const String &p_key, const Variant &p_raw_value, bool p_has_type, const String &p_type_name,
		Dictionary &r_out, MCPToolError &r_error) {
	if (p_key.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'key' must not be empty");
		return false;
	}
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr) {
		r_error = MCPToolError::tool_state("ProjectSettings is not available in this process",
				"This build has no project settings service; use a standard editor/game build");
		return false;
	}

	// The declared type of an existing setting. `property_type_of` asks the
	// object's own property list (which is where every setting the engine knows
	// declares itself) and answers NIL for a key the project does not have.
	const Variant::Type declared = property_type_of(settings, StringName(p_key));
	const bool existed = settings->has_setting(p_key);

	Variant::Type target = declared;
	if (p_has_type) {
		const Variant::Type named = variant_type_from_name(p_type_name);
		if (named == Variant::VARIANT_MAX) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'type' names no type this tool can write: '%s'. Accepted names are bool, int, float, "
					"String, StringName, NodePath, Vector2, Vector2i, Vector3, Vector3i, Vector4, Vector4i, Rect2, "
					"Rect2i, Color, Array, Dictionary and the Packed*Array family",
					p_type_name));
			return false;
		}
		if (declared != Variant::NIL && declared != named) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'type' is '%s' but the setting '%s' is declared as %s; omit 'type' to use the declared "
					"type, or change the key's type in the project settings first",
					p_type_name, p_key, Variant::get_type_name(declared)));
			return false;
		}
		target = named;
	}

	Variant converted;
	if (target == Variant::NIL) {
		// A key the project does not declare and no explicit `type`. A game is
		// free to define its own settings, so this is allowed - but the value
		// keeps the JSON type it arrived with and a `null` is refused, because a
		// setting that holds nothing is not something the engine can store.
		const Variant json = property_value_from_json(p_raw_value, Variant::NIL);
		if (json.get_type() == Variant::NIL) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'value' is null for the new setting '%s'. A setting the project does not declare yet "
					"needs a non-null value (and, for a type the JSON value does not reveal, an explicit 'type')", p_key));
			return false;
		}
		converted = json;
	} else {
		const Variant json = property_value_from_json(p_raw_value, target);
		Variant shaped;
		// The same "a JSON object names the components of a vector" rule as the
		// node write (`running_game_node_write.*`), so `{"x":1,"y":2}` reaches a
		// `Vector2` setting as `Vector2(1, 2)` and never as the zero vector.
		if (!shape_vector_from_json(json, target, p_key, "value", shaped, r_error)) {
			return false;
		}
		// TASK-022 D-4: the explicit `ValueSlot::WIDE` is the one place this path
		// has to say something about storage, and what it says is "nothing is
		// narrowed here". `ProjectSettings` stores its values as **Variants**
		// (`set_setting` puts the Variant straight into the settings map), so a
		// float setting is a `double` and not a `real_t` member: applying the
		// member rule would refuse a perfectly storable `1e300`, and a scalar
		// `FLOAT` in a settings map is exactly the case where the "narrowest
		// possible slot" reading of the default would be wrong.
		if (!coerce_to_property_type(shaped, target, converted, r_error, "value", ValueSlot::WIDE)) {
			return false;
		}
	}

	const Variant previous_value = settings->get_setting(p_key);
	settings->set_setting(p_key, converted);
	if (!publish_project_setting(p_key, nullptr, r_error)) {
		// `project.godot` still holds its old bytes; put the in-memory state back
		// to match it, so a failed call leaves no trace in either place.
		if (existed) {
			settings->set_setting(p_key, previous_value);
		} else {
			settings->clear(p_key);
		}
		return false;
	}

	// Read back, never echo: a setter that clamped or refused the value shows up
	// as a `value` that is not what was asked for.
	const Variant written = settings->get_setting(p_key);
	Dictionary out;
	out["key"] = p_key;
	out["value"] = serialize_variant(written);
	out["type"] = Variant::get_type_name(written.get_type());
	out["existed_before"] = existed;
	out["created"] = !existed;
	out["saved"] = true;
	r_out = out;
	return true;
}

} // namespace MCPTools

static Variant _tool_set_setting(const Dictionary &p_args, MCPToolError &r_error) {
	String key;
	if (!require_string(p_args, "key", key, r_error)) {
		return Variant();
	}
	// `value` accepts every JSON type, so its presence (not its nullness) is what
	// "required" means here - the same rule `editor_set_node_property` follows.
	if (!p_args.has("value")) {
		r_error = MCPToolError::invalid_params("Missing required parameter 'value'");
		return Variant();
	}
	bool has_type = false;
	String type_name;
	if (!optional_string(p_args, "type", String(), type_name, r_error)) {
		return Variant();
	}
	if (p_args.has("type")) {
		// `optional_string` folds a present-but-empty string into "absent"; that
		// would silently ignore a caller who sent `"type": ""`, so the presence
		// check above keeps the two apart.
		has_type = true;
	}
	Dictionary out;
	if (!set_project_setting(key, p_args["value"], has_type, type_name, out, r_error)) {
		return Variant();
	}
	return out;
}

// ---------------------------------------------------------------------------
// Registration
//
// The `description` and `inputSchema` below are the contract entries of
// docs/tools_list.renamed.json, character for character; `channel`/`verb`/
// `scope`/`mutating` come from docs/tool-rename-map.json.
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_setting_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_setting_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_set_setting", String::utf8(R"desc(设置项目设置 When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them.)desc"));
		builder.channel("project").verb("set").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"key":{"type":"string"},"type":{"type":"string"},"value":{"description":"设置值"}},"required":["key","value"],"type":"object"})schema"));
		builder.handler(_tool_set_setting).register_into(r_registry);
	}
}
