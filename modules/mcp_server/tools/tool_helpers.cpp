/**************************************************************************/
/*  tool_helpers.cpp                                                      */
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
#include "tool_helpers.h"

// `MCPTools::vector_from_dictionary` for `assertion_expectation_for` below: the
// assertion comparison has to put a caller's `{"x":3,"y":4}` expectation into the
// same shape the property writer accepts, so `{"x":3,"y":4}` against a `Vector2`
// property is `passed: true` instead of `false`. There is no circular include
// (`running_game_node_write.h` does not include this file).
#include "running_game_node_write.h"

#include "core/config/project_settings.h"
// TASK-063 (d): the error-handler list is how the engine's own `GDScript::reload`
// diagnostics (which carry the *line*) are made readable without a
// module-to-module dependency on `modules/gdscript/**`; `script_language.h`
// declares `Script::reload()`, the one call the capture wraps. `strcmp` is used
// instead of a `String` comparison inside the handler: a handler runs while an
// error is being printed, and it must not allocate more than it has to.
#include <cstring>

#include "core/error/error_macros.h"
#include "core/object/script_language.h"
// TASK-041 section 2: the `project.godot` `[input]` bridge reads the published
// bytes back with the engine's own config reader (`ConfigFile`, objects allowed -
// `core/io/config_file.cpp:289`) and builds its value out of the live `InputMap`.
#include "core/input/input_event.h"
#include "core/input/input_map.h"
#include "core/io/config_file.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
// TASK-027 D-8: an Object-valued property is written back by loading the
// resource its `res://` path names (section 23.5 of DESIGN-DETAIL.md).
#include "core/io/resource.h"
#include "core/io/resource_loader.h"
#include "core/math/color.h"
#include "core/object/class_db.h"
#include "core/os/keyboard.h"
#include "core/os/os.h"
#include "core/os/time.h"
#include "scene/gui/control.h"
#include "scene/gui/rich_text_label.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/main/viewport.h"
#include "scene/main/window.h"
#include "servers/display/display_server.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/main/viewport.h"
#include "scene/main/window.h"
#include "servers/display/display_server.h"

// The compile-time half of the editor guard (TASK-002 section 2.2.3). In a game
// build (`TOOLS_ENABLED` undefined) the include disappears together with the
// branch that needs it, so a game build never carries editor code.
#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/editor_log.h"
#include "editor/editor_node.h"
#include "scene/gui/rich_text_label.h"
#endif

// The bodies below are the verbatim bodies of the helpers that used to be
// file-private in `tools/project_read_analysis.cpp` (and, for the three that
// group also needs, duplicated in `tools/project_read_template.cpp`). TASK-005
// section 1 hoists them here; the only edits are the removed `static`, the
// removed leading `_` and the renamed recursive calls. See tool_helpers.h.

namespace MCPTools {

String join_path(const String &p_dir, const String &p_entry) {
	if (p_dir.ends_with("/")) {
		return p_dir + p_entry;
	}
	return p_dir + "/" + p_entry;
}

Vector<String> split_lines(const String &p_text) {
	Vector<String> lines;
	if (p_text.is_empty()) {
		return lines;
	}
	Vector<String> raw = p_text.split("\n", true);
	if (raw.size() > 0 && raw[raw.size() - 1].is_empty() && p_text.ends_with("\n")) {
		raw.remove_at(raw.size() - 1);
	}
	for (int i = 0; i < raw.size(); i++) {
		String line = raw[i];
		if (line.ends_with("\r")) {
			line = line.substr(0, line.length() - 1);
		}
		lines.push_back(line);
	}
	return lines;
}

Variant serialize_variant(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::NIL: {
			return Variant();
		}
		case Variant::BOOL: {
			return (bool)p_value;
		}
		case Variant::INT: {
			return (int64_t)p_value;
		}
		case Variant::FLOAT: {
			return (double)p_value;
		}
		case Variant::STRING:
		case Variant::STRING_NAME: {
			return (String)p_value;
		}
		case Variant::VECTOR2: {
			const Vector2 value = p_value;
			Dictionary out;
			out["x"] = value.x;
			out["y"] = value.y;
			return out;
		}
		case Variant::VECTOR2I: {
			const Vector2i value = p_value;
			Dictionary out;
			out["x"] = value.x;
			out["y"] = value.y;
			return out;
		}
		case Variant::VECTOR3: {
			const Vector3 value = p_value;
			Dictionary out;
			out["x"] = value.x;
			out["y"] = value.y;
			out["z"] = value.z;
			return out;
		}
		case Variant::VECTOR3I: {
			const Vector3i value = p_value;
			Dictionary out;
			out["x"] = value.x;
			out["y"] = value.y;
			out["z"] = value.z;
			return out;
		}
		case Variant::VECTOR4: {
			// TASK-024 E-3: `Vector4` had no branch and fell into `default:` ->
			// `stringify()`, so the *same* readback answered an object for
			// `position` (Vector2/Vector3) and a string for `v4`, and a consumer
			// had to branch on the shape. `Vector4i` is the same shape one line
			// below; a write of `{x,y,z,w}` can now be read back and fed back in.
			const Vector4 value = p_value;
			Dictionary out;
			out["x"] = value.x;
			out["y"] = value.y;
			out["z"] = value.z;
			out["w"] = value.w;
			return out;
		}
		case Variant::VECTOR4I: {
			const Vector4i value = p_value;
			Dictionary out;
			out["x"] = value.x;
			out["y"] = value.y;
			out["z"] = value.z;
			out["w"] = value.w;
			return out;
		}
		// -----------------------------------------------------------------------
		// TASK-033 (B5 batch 1, GDR-25 section 23.4): `Quaternion` joins the
		// read/write matrix. `editor_get_animation_info` reads back a rotation
		// track's keys, and the engine stores those as `Quaternion`
		// (`Animation::RotationTrack` -> `TKey<Quaternion>`), so the read side had
		// to name the four members the write side now accepts
		// (`MCPTools::vector_component_hint` / `_vector_components` /
		// `vector_from_dictionary` in `running_game_node_write.cpp`). Before this,
		// the value was `stringify()`d into a `"Quaternion(...)"` string - a shape
		// the write side can never take - which is exactly the string surgery
		// section 23.1 forbids. The members are the engine's own and are `real_t`
		// (`core/math/quaternion.h`: `real_t x, y, z, w`).
		// -----------------------------------------------------------------------
		case Variant::QUATERNION: {
			const Quaternion value = p_value;
			Dictionary out;
			out["x"] = value.x;
			out["y"] = value.y;
			out["z"] = value.z;
			out["w"] = value.w;
			return out;
		}
		case Variant::COLOR: {
			const Color value = p_value;
			Dictionary out;
			out["r"] = value.r;
			out["g"] = value.g;
			out["b"] = value.b;
			out["a"] = value.a;
			return out;
		}
		case Variant::RECT2: {
			const Rect2 value = p_value;
			Dictionary out;
			out["x"] = value.position.x;
			out["y"] = value.position.y;
			out["width"] = value.size.x;
			out["height"] = value.size.y;
			return out;
		}
		// -----------------------------------------------------------------------
		// TASK-024b E-3 - one shape per kind.
		//
		// Everything below used to fall into `default: p_value.stringify()`: a
		// `Vector4` answered the **string** `"(5.0, 6.0, 7.0, 8.0)"` and every
		// packed array the string `"[(1.0, 2.0)]"`, while `Vector2` answered
		// `{"x":..,"y":..}`. A consumer of one read-back therefore had to branch
		// on "object vs string" for values of the same kind, and the string form
		// could not be written back without parsing it (GDR-25 section 23.1,
		// forbidden practices 1 and 4). The branches below are the *only* rule:
		// a vector/rect/colour names its components in an object, a packed array
		// answers a JSON array whose elements are what the element alone answers.
		//
		// `PackedByteArray` is an array of integers, not a base64 or hex string:
		// every other packed array is an array, a byte buffer is the same kind of
		// container, and `[1,200]` is exactly the shape the write side takes back
		// for a `PackedByteArray` target (`_container_element_type` answers INT
		// for it, `_container_element_slot` `UINT8`) - so bytes round-trip with
		// no encoding step in the caller.
		// -----------------------------------------------------------------------
		case Variant::VECTOR4: {
			const Vector4 value = p_value;
			Dictionary out;
			out["x"] = value.x;
			out["y"] = value.y;
			out["z"] = value.z;
			out["w"] = value.w;
			return out;
		}
		case Variant::VECTOR4I: {
			const Vector4i value = p_value;
			Dictionary out;
			out["x"] = value.x;
			out["y"] = value.y;
			out["z"] = value.z;
			out["w"] = value.w;
			return out;
		}
		case Variant::RECT2I: {
			const Rect2i value = p_value;
			Dictionary out;
			out["x"] = value.position.x;
			out["y"] = value.position.y;
			out["width"] = value.size.x;
			out["height"] = value.size.y;
			return out;
		}
		case Variant::PACKED_BYTE_ARRAY: {
			const PackedByteArray source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				// The element's own kind: an integer, widened explicitly so that
				// no implicit `uint8_t -> bool` conversion is a candidate.
				out.push_back(Variant((int64_t)source[i]));
			}
			return out;
		}
		case Variant::PACKED_INT32_ARRAY: {
			const PackedInt32Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(Variant((int64_t)source[i]));
			}
			return out;
		}
		case Variant::PACKED_INT64_ARRAY: {
			const PackedInt64Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(Variant(source[i]));
			}
			return out;
		}
		case Variant::PACKED_FLOAT32_ARRAY: {
			const PackedFloat32Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(Variant((double)source[i]));
			}
			return out;
		}
		case Variant::PACKED_FLOAT64_ARRAY: {
			const PackedFloat64Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(Variant(source[i]));
			}
			return out;
		}
		case Variant::PACKED_STRING_ARRAY: {
			const PackedStringArray source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(Variant(source[i]));
			}
			return out;
		}
		case Variant::PACKED_VECTOR2_ARRAY: {
			const PackedVector2Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(serialize_variant(Variant(source[i])));
			}
			return out;
		}
		case Variant::PACKED_VECTOR3_ARRAY: {
			const PackedVector3Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(serialize_variant(Variant(source[i])));
			}
			return out;
		}
		case Variant::PACKED_VECTOR4_ARRAY: {
			const PackedVector4Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(serialize_variant(Variant(source[i])));
			}
			return out;
		}
		case Variant::PACKED_COLOR_ARRAY: {
			const PackedColorArray source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(serialize_variant(Variant(source[i])));
			}
			return out;
		}
		case Variant::NODE_PATH: {
			return (String)p_value;
		}
		case Variant::DICTIONARY: {
			const Dictionary source = p_value;
			Dictionary out;
			const Array keys = source.keys();
			for (int i = 0; i < keys.size(); i++) {
				const Variant key = keys[i];
				String key_string;
				if (key.get_type() == Variant::STRING || key.get_type() == Variant::STRING_NAME) {
					key_string = (String)key;
				} else {
					key_string = key.stringify();
				}
				out[key_string] = serialize_variant(source[key]);
			}
			return out;
		}
		case Variant::ARRAY: {
			const Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(serialize_variant(source[i]));
			}
			return out;
		}
		// -------------------------------------------------------------------
		// TASK-024 E-3: the packed containers.
		//
		// Every one of them used to fall into `default:` -> `stringify()`, so a
		// single readback mixed shapes: `position` was an object while `v4` was
		// `"(5.0, 6.0, 7.0, 8.0)"` and `pv2` was `"[(1.0, 2.0)]"`. Each branch
		// below answers the JSON shape a consumer can feed straight back into
		// the write side (`coerce_to_property_type` accepts an `ARRAY` for every
		// one of these targets, and an `OBJECT`-shaped element for the four
		// composite ones), so **no branch on the consumer's side is needed any
		// more**.
		//
		// The element spellings follow the engine's own semantics, which is also
		// what its `Array(packed)` conversion produces:
		//   * `PackedByteArray` -> a JSON array of integers in 0..255 (its
		//     element is a `uint8_t`, and the write side takes `[1,2,3]` - the
		//     same shape a `PackedByteArray` round-trips through). It is
		//     deliberately *not* base64: this is a value readback, and base64
		//     would be a third shape no other container uses, and one no write
		//     path accepts.
		//   * `PackedStringArray` -> a JSON array of strings (its element is a
		//     `String`; the engine keeps them as text, so they stay text).
		//   * the four composite containers -> an array of the *same* object the
		//     scalar branch above emits for that type.
		// -------------------------------------------------------------------
		case Variant::PACKED_BYTE_ARRAY: {
			const PackedByteArray value = p_value;
			Array out;
			for (int i = 0; i < value.size(); i++) {
				out.push_back((int64_t)value[i]);
			}
			return out;
		}
		case Variant::PACKED_INT32_ARRAY: {
			const PackedInt32Array value = p_value;
			Array out;
			for (int i = 0; i < value.size(); i++) {
				out.push_back((int64_t)value[i]);
			}
			return out;
		}
		case Variant::PACKED_INT64_ARRAY: {
			const PackedInt64Array value = p_value;
			Array out;
			for (int i = 0; i < value.size(); i++) {
				out.push_back(value[i]);
			}
			return out;
		}
		case Variant::PACKED_FLOAT32_ARRAY: {
			const PackedFloat32Array value = p_value;
			Array out;
			for (int i = 0; i < value.size(); i++) {
				out.push_back((double)value[i]);
			}
			return out;
		}
		case Variant::PACKED_FLOAT64_ARRAY: {
			const PackedFloat64Array value = p_value;
			Array out;
			for (int i = 0; i < value.size(); i++) {
				out.push_back((double)value[i]);
			}
			return out;
		}
		case Variant::PACKED_STRING_ARRAY: {
			const PackedStringArray value = p_value;
			Array out;
			for (int i = 0; i < value.size(); i++) {
				out.push_back((String)value[i]);
			}
			return out;
		}
		case Variant::PACKED_VECTOR2_ARRAY: {
			const PackedVector2Array value = p_value;
			Array out;
			for (int i = 0; i < value.size(); i++) {
				const Vector2 element = value[i];
				Dictionary entry;
				entry["x"] = element.x;
				entry["y"] = element.y;
				out.push_back(entry);
			}
			return out;
		}
		case Variant::PACKED_VECTOR3_ARRAY: {
			const PackedVector3Array value = p_value;
			Array out;
			for (int i = 0; i < value.size(); i++) {
				const Vector3 element = value[i];
				Dictionary entry;
				entry["x"] = element.x;
				entry["y"] = element.y;
				entry["z"] = element.z;
				out.push_back(entry);
			}
			return out;
		}
		case Variant::PACKED_VECTOR4_ARRAY: {
			const PackedVector4Array value = p_value;
			Array out;
			for (int i = 0; i < value.size(); i++) {
				const Vector4 element = value[i];
				Dictionary entry;
				entry["x"] = element.x;
				entry["y"] = element.y;
				entry["z"] = element.z;
				entry["w"] = element.w;
				out.push_back(entry);
			}
			return out;
		}
		case Variant::PACKED_COLOR_ARRAY: {
			const PackedColorArray value = p_value;
			Array out;
			for (int i = 0; i < value.size(); i++) {
				const Color element = value[i];
				Dictionary entry;
				entry["r"] = element.r;
				entry["g"] = element.g;
				entry["b"] = element.b;
				entry["a"] = element.a;
				out.push_back(entry);
			}
			return out;
		}
		case Variant::OBJECT: {
			// -----------------------------------------------------------------
			// GDR-25 section 23.5 (TASK-027 D-8) - the one shape an Object-valued
			// property is read back in, and the shape the write side takes back.
			//
			// Before this: a null pointer answered `{}`, and `{}` is a shape the
			// write side can *never* accept (`Variant::can_convert(DICTIONARY,
			// OBJECT)` is false), so the read was unusable; writing `null` to
			// clear the property still read back `{}`. Measured end to end in
			// REPORT-026 section 2.1 (scripts/mcp026_object_shape_probe.ps1).
			//
			// Now:
			//   * an unset reference (`nullptr`) is JSON `null` (a `NIL` Variant),
			//     **not** `{}`: `{}` claims "there is an object and it has no
			//     information", which is false information;
			//   * a `Resource` is named by its own path (`res://...`); a
			//     sub-resource / built-in resource has none, and says so with an
			//     empty `path` plus the `local_to_scene` flag it really has;
			//   * any other object (a `Node`) is named by its node path, in the
			//     module's wire spelling (`wire_node_path`: relative to the edited
			//     scene root inside the editor, the engine's own path elsewhere).
			// No pointer / address is ever spelled: the old `to_string()` value
			// was `Object(0x...)` for every class without its own overload, which
			// is neither stable nor reusable.
			//
			// `{"type","path"}` is exactly what `_object_value_from_json`
			// (`coerce_to_property_type`, OBJECT target) loads back, so the read
			// value feeds the write path with no string surgery (section 23.1).
			// -----------------------------------------------------------------
			// RED PHASE ONLY (TASK-027): the pre-fix OBJECT branch, restored so
			// the new cases can be observed failing on the real wire shape.
			Object *object = p_value;
			Dictionary out;
			if (object != nullptr) {
				out["type"] = object->get_class();
				out["value"] = object->to_string();
			}
			return out;
		}
		default: {
			// The shape rule above covers every type the module reads back today.
			// What is left are the matrix/transform family and the callables
			// (`Transform2D/3D`, `Basis`, `Plane`, `Projection`,
			// `AABB`, `RID`, `Callable`, `Signal`, `PACKED_*` - all handled
			// above) - they keep the reference's `stringify()` spelling until a
			// tool actually reads one back (REPORT-024b section 6).
			// TASK-033 moved `Quaternion` out of this list: the animation family
			// reads rotation keys back, so read and write now share the
			// `{x,y,z,w}` shape (REPORT-033 section 5.3).
			return p_value.stringify();
		}
	}
}

void collect_files_by_extension(const String &p_path, const Vector<String> &p_extensions, bool p_include_addons, Vector<String> &r_out) {
	Ref<DirAccess> dir = DirAccess::open(p_path);
	if (dir.is_null()) {
		// A directory that cannot be read is skipped silently, exactly like the
		// reference; the *start* directory is validated by the caller.
		return;
	}
	dir->list_dir_begin();
	while (true) {
		const String entry = dir->get_next();
		if (entry.is_empty()) {
			break;
		}
		if (entry.begins_with(".")) {
			continue;
		}
		const String full = join_path(p_path, entry);
		if (dir->current_is_dir()) {
			if (entry == "addons" && !p_include_addons) {
				continue;
			}
			collect_files_by_extension(full, p_extensions, p_include_addons, r_out);
		} else {
			const int dot = entry.rfind_char('.');
			if (dot < 0) {
				continue;
			}
			const String extension = entry.substr(dot + 1).to_lower();
			for (int i = 0; i < p_extensions.size(); i++) {
				if (p_extensions[i] == extension) {
					r_out.push_back(full);
					break;
				}
			}
		}
	}
	dir->list_dir_end();
}

// ---------------------------------------------------------------------------
// Atomic publish (TASK-008 section 3).
//
// These two functions are the *verbatim bodies* of the file-private helpers that
// used to live in `tools/project_write_resource_scene.cpp`
// (`_temporary_sibling_path` / `_save_resource_atomically`), hoisted here so that
// the next writing group shares one definition instead of growing a second copy
// (the same move TASK-005 made for the four read helpers). The only edits are:
//
//   * the removed `static` and the removed leading `_` on the two names;
//   * the single line that used to be `ResourceSaver::save(p_resource, temp_path)`
//     is now the caller's `p_write(temp_path, p_userdata)` callback.
//
// Everything else - the order in which the destination is probed, the parent
// directory is created, the backup is taken, the temporary file is checked and
// published, the rollback runs and the scratch files are removed - is unchanged,
// so the observable behaviour of `project_write_resource_scene` is identical.
// REPORT-008 proves that on the wire with a byte-for-byte before/after compare of
// the same request sequence.
// ---------------------------------------------------------------------------

String temporary_sibling_path(const String &p_path) {
	const String base = p_path.get_file();
	const String directory = p_path.get_base_dir();
	const String extension = p_path.get_extension();
	const String name = extension.is_empty() ? base : base.get_basename();
	if (extension.is_empty() || name.is_empty()) {
		return directory.path_join(base + ".mcp-tmp");
	}
	return directory.path_join(vformat("%s.mcp-tmp.%s", name, extension));
}

Error publish_file_atomically(const String &p_path, AtomicWriteFunc p_write, void *p_userdata) {
	const bool destination_exists = FileAccess::exists(p_path);
	const String temp_path = temporary_sibling_path(p_path);
	const String backup_path = temporary_sibling_path(p_path) + ".bak";

	if (!destination_exists && !DirAccess::dir_exists_absolute(p_path.get_base_dir())) {
		const Error dir_error = DirAccess::make_dir_recursive_absolute(p_path.get_base_dir());
		if (dir_error != OK) {
			return dir_error;
		}
	}

	const Error backup_error = destination_exists
			? DirAccess::copy_absolute(p_path, backup_path)
			: OK;
	if (backup_error != OK) {
		return backup_error;
	}

	Error result = p_write(temp_path, p_userdata);
	if (result == OK) {
		// The writer reported success; prove the artefact is really there before
		// anything is published over the destination.
		if (!FileAccess::exists(temp_path)) {
			result = FAILED;
		} else {
			DirAccess::remove_absolute(p_path);
			result = DirAccess::rename_absolute(temp_path, p_path);
		}
	}

	if (result != OK && destination_exists) {
		// Put the original bytes back if the publish step got far enough to
		// remove them.
		if (!FileAccess::exists(p_path) && FileAccess::exists(backup_path)) {
			DirAccess::copy_absolute(backup_path, p_path);
		}
	}

	DirAccess::remove_absolute(backup_path);
	DirAccess::remove_absolute(temp_path);
	return result;
}

// ---------------------------------------------------------------------------
// TASK-035: the plain-text `AtomicWriteFunc` of `publish_file_atomically`, so a
// group that publishes a text file (the shader writes) does not need its own
// seventeen-line copy.
// ---------------------------------------------------------------------------

static Error _text_file_writer(const String &p_temp_path, void *p_userdata) {
	const String *text = static_cast<const String *>(p_userdata);
	Ref<FileAccess> file = FileAccess::open(p_temp_path, FileAccess::WRITE);
	if (file.is_null()) {
		return FileAccess::get_open_error();
	}
	file->store_string(*text);
	file->close();
	return OK;
}

Error publish_text_atomically(const String &p_path, const String &p_text) {
	// A local copy so the callback has a stable address for the whole call;
	// `publish_file_atomically` never stores it.
	String held = p_text;
	return publish_file_atomically(p_path, _text_file_writer, &held);
}

// ---------------------------------------------------------------------------
// project.godot atomic publish (TASK-018 section 3). See tool_helpers.h for the
// argument; the writer is the engine's own `ProjectSettings::save_custom()`, so
// what is published is byte-for-byte what `ProjectSettings::save()` produces.
// ---------------------------------------------------------------------------

static Error _project_settings_writer(const String &p_temp_path, void *p_userdata) {
	ProjectSettings *settings = static_cast<ProjectSettings *>(p_userdata);
	return settings->save_custom(p_temp_path);
}

String project_settings_file_path() {
	return ProjectSettings::get_singleton()->get_resource_path().path_join("project.godot");
}

bool publish_project_settings(MCPToolError &r_error) {
	return publish_project_settings_to(project_settings_file_path(), r_error);
}

bool publish_project_settings_to(const String &p_target_path, MCPToolError &r_error) {
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr) {
		r_error = MCPToolError::tool_state("ProjectSettings is not available in this process",
				"This build has no project settings service; use a standard editor/game build");
		return false;
	}
	const Error error = publish_file_atomically(p_target_path, _project_settings_writer, settings);
	if (error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to publish project settings to '%s': %s",
				p_target_path, VariantUtilityFunctions::error_string(error)));
		return false;
	}
	return true;
}

// ---------------------------------------------------------------------------
// TASK-059 D-4: the section-granular `project.godot` publish. The declared
// fall-backs and the engine-side argument are in tool_helpers.h.
// ---------------------------------------------------------------------------

String project_setting_section(const String &p_key) {
	const int div = p_key.find_char('/');
	if (div <= 0) {
		return String();
	}
	return p_key.substr(0, div);
}

// Fall-back case 4: the setting name is already written in the file's header-less
// global block, which `ConfigFile` calls the "" section
// (`core/io/config_file.cpp:282/298`). `true` means "do not use the section
// writer" - including when the file cannot be read as a config file at all,
// because then the global block could not be checked.
static bool _setting_sits_in_the_global_block(const String &p_path, const String &p_key) {
	Ref<ConfigFile> probe;
	probe.instantiate();
	if (probe->load(p_path) != OK) {
		return true;
	}
	return probe->has_section_key("", p_key);
}

bool publish_project_setting_to(const String &p_target_path, const String &p_key, bool *r_whole_file, MCPToolError &r_error) {
	if (r_whole_file != nullptr) {
		*r_whole_file = false;
	}
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr) {
		r_error = MCPToolError::tool_state("ProjectSettings is not available in this process",
				"This build has no project settings service; use a standard editor/game build");
		return false;
	}

	// The section writer is used only when it can serve the whole request. The
	// four conditions are the declared fall-backs in tool_helpers.h; naming them
	// here is what keeps the contract's list and the code the same list.
	const String section = project_setting_section(p_key);
	if (!section.is_empty() && settings->has_setting(p_key) && FileAccess::exists(p_target_path) &&
			!_setting_sits_in_the_global_block(p_target_path, p_key)) {
		ProjectSettings::CustomMap custom;
		// The value comes from the in-memory settings, not from the caller: that is
		// the same read `_save_settings_text()` makes (`get(key)`,
		// `core/config/project_settings.cpp:1200`), so the bytes published here are
		// the bytes the whole-file writer would have produced for this one key.
		custom[p_key] = settings->get_setting(p_key);
		if (settings->save_custom_section(p_target_path, section, custom) == OK) {
			return true;
		}
		// Fall-back 3: the engine refused (an unwritable section name, a value it
		// cannot serialize, a file it could not read back). Falling through is the
		// declared behaviour, not a silent downgrade - the callers' descriptions
		// name this case and the whole-file writer is what they had before
		// TASK-059.
	}

	if (r_whole_file != nullptr) {
		*r_whole_file = true;
	}
	return publish_project_settings_to(p_target_path, r_error);
}

bool publish_project_setting(const String &p_key, bool *r_whole_file, MCPToolError &r_error) {
	return publish_project_setting_to(project_settings_file_path(), p_key, r_whole_file, r_error);
}

// ---------------------------------------------------------------------------
// project.godot's `[input]` section (TASK-041 section 2; RACING-FINDINGS M-6 /
// RACING-DEV-LOG E-4). See tool_helpers.h for the argument; the short version is
// that an editor's `InputMap` and a game's `InputMap` meet in exactly one place -
// the `input/*` entries of `project.godot` - and these four functions are that
// meeting point.
// ---------------------------------------------------------------------------

String input_action_setting_key(const String &p_action) {
	return "input/" + p_action;
}

// `ProjectSettings` treats two characters inside a key as structure rather than
// as part of the name: `_get_property_list` splits a setting on its first `/`
// into section and key (`project_settings.cpp:1312-1319`) and `_set` reads
// anything after a `.` as a feature override (`project_settings.cpp:328-344`).
// A name carrying either therefore cannot be stored as **one** `input/<action>`
// entry, and storing it anyway would produce a file whose action name is not the
// one that was asked for - so it is refused with the reason spelled out.
static bool _input_action_name_is_setting_key(const String &p_action, String &r_reason) {
	if (p_action.contains("/")) {
		r_reason = vformat("The action name '%s' cannot be a project setting key: `%s` would be split on '/' by ProjectSettings, so the game could not read the action back under this name. Use a name without '/' (the action was still created in this process' InputMap)",
				p_action, input_action_setting_key(p_action));
		return false;
	}
	if (p_action.contains(".")) {
		r_reason = vformat("The action name '%s' cannot be a project setting key: `%s` would be read as a feature override by ProjectSettings, so the game could not read the action back under this name. Use a name without '.' (the action was still created in this process' InputMap)",
				p_action, input_action_setting_key(p_action));
		return false;
	}
	return true;
}

bool input_action_project_value(InputMap *p_map, const String &p_action, Dictionary &r_value, String &r_reason) {
	r_reason = String();
	if (p_map == nullptr) {
		r_reason = "This process has no InputMap singleton, so there is no action state to publish";
		return false;
	}
	if (!_input_action_name_is_setting_key(p_action, r_reason)) {
		return false;
	}
	if (!p_map->has_action(p_action)) {
		r_reason = vformat("The InputMap of this process has no action '%s', so there is nothing to publish", p_action);
		return false;
	}

	// Exactly the two keys `InputMap::load_from_project_settings()` reads
	// (`core/input/input_map.cpp:325-358`) - and `events` is not optional there:
	// an entry without it is skipped, which would be a file that looks written and
	// loads as nothing.
	Dictionary value;
	value["deadzone"] = (double)p_map->action_get_deadzone(p_action);
	Array events;
	if (const List<Ref<InputEvent>> *bound = p_map->action_get_events(p_action)) {
		for (const List<Ref<InputEvent>>::Element *E = bound->front(); E; E = E->next()) {
			events.push_back(E->get());
		}
	}
	value["events"] = events;
	r_value = value;
	return true;
}

bool read_input_action_from_disk(const String &p_path, const String &p_action, const Dictionary &p_expected, String &r_reason) {
	r_reason = String();
	if (!FileAccess::exists(p_path)) {
		r_reason = vformat("'%s' does not exist, so the action '%s' could not be read back", p_path, p_action);
		return false;
	}
	Ref<ConfigFile> file;
	file.instantiate();
	const Error error = file->load(p_path);
	if (error != OK) {
		r_reason = vformat("'%s' could not be parsed as a config file (%s), so the action '%s' could not be read back", p_path,
				VariantUtilityFunctions::error_string(error), p_action);
		return false;
	}
	if (!file->has_section_key("input", p_action)) {
		r_reason = vformat("The [input] section of '%s' has no key '%s'", p_path, p_action);
		return false;
	}
	const Variant read = file->get_value("input", p_action, Variant());
	if (read.get_type() != Variant::DICTIONARY) {
		r_reason = vformat("The [input] key '%s' of '%s' holds a %s on disk, not the Dictionary `InputMap::load_from_project_settings()` needs",
				p_action, p_path, Variant::get_type_name(read.get_type()));
		return false;
	}
	const Dictionary stored = read;

	// The deadzone is compared at the width `InputMap::Action::deadzone` stores it
	// (`float`, `core/input/input_map.h:55`): the engine writes a 32-bit float as
	// its own float text (`rtos_fix`, `core/variant/variant_parser.cpp:1857`), so
	// `0.2f` is written as `0.2` and parses back as the *double* 0.2 - comparing
	// the doubles would reject a perfectly good round trip.
	if (!stored.has("deadzone")) {
		r_reason = vformat("The [input] key '%s' of '%s' has no 'deadzone' on disk", p_action, p_path);
		return false;
	}
	// MCP-NARROWING: G24-INPUT-PERSIST-DEADZONE - safe: this is the comparison's
	// own width, not a store. `InputMap::Action::deadzone` is a `float`
	// (`core/input/input_map.h:55`) and the file carries that float's own text
	// (`rtos_fix`, `core/variant/variant_parser.cpp:1857` writes `0.2f` as `0.2`),
	// so the parsed value is a *double* that is only equal to the map's value at
	// `float` width; comparing as `double` would report every well-published
	// `0.2f` as a mismatch and turn a correct write into a false `persisted:false`.
	const float expected_deadzone = (float)(double)p_expected.get("deadzone", Variant(0.0));
	const double stored_deadzone = (double)stored["deadzone"];
	// MCP-NARROWING: G24-INPUT-PERSIST-DEADZONE - safe: the other side of the same
	// comparison. Nothing is written through this cast, and a deadzone that cannot
	// be a `float` at all (e.g. `1e300` in a hand-edited file) becomes `inf` here
	// and compares unequal, so the read-back refuses instead of claiming success.
	if ((float)stored_deadzone != expected_deadzone) {
		r_reason = vformat("The action '%s' has deadzone %f on disk and %f in this process' InputMap", p_action, stored_deadzone, (double)expected_deadzone);
		return false;
	}

	if (!stored.has("events") || stored["events"].get_type() != Variant::ARRAY) {
		r_reason = vformat("The [input] key '%s' of '%s' has no 'events' array on disk; `load_from_project_settings()` skips an entry without one", p_action, p_path);
		return false;
	}
	const Array expected_events = p_expected.get("events", Array());
	const Array stored_events = stored["events"];
	if (stored_events.size() != expected_events.size()) {
		r_reason = vformat("The action '%s' has %d event(s) on disk and %d in this process' InputMap", p_action, stored_events.size(), expected_events.size());
		return false;
	}
	// `Variant` equality on an object is identity, and a parsed
	// `Object(InputEventKey,...)` is a brand-new object, so the events are compared
	// by class and - for the key events this module creates - by keycode.
	for (int i = 0; i < stored_events.size(); i++) {
		const Ref<InputEvent> stored_event = stored_events[i];
		const Ref<InputEvent> expected_event = expected_events[i];
		if (stored_event.is_null() || expected_event.is_null()) {
			r_reason = vformat("Event %d of the action '%s' is %s on disk and %s in this process' InputMap", i, p_action,
					stored_event.is_null() ? "null" : "an event", expected_event.is_null() ? "null" : "an event");
			return false;
		}
		if (stored_event->get_class() != expected_event->get_class()) {
			r_reason = vformat("Event %d of the action '%s' is a %s on disk and a %s in this process' InputMap", i, p_action,
					stored_event->get_class(), expected_event->get_class());
			return false;
		}
		const Ref<InputEventKey> stored_key = stored_event;
		const Ref<InputEventKey> expected_key = expected_event;
		if (stored_key.is_valid() && expected_key.is_valid() && stored_key->get_keycode() != expected_key->get_keycode()) {
			r_reason = vformat("Event %d of the action '%s' is the key %s on disk and the key %s in this process' InputMap", i, p_action,
					keycode_get_string(stored_key->get_keycode()), keycode_get_string(expected_key->get_keycode()));
			return false;
		}
	}
	return true;
}

// TASK-042 section 3 (O-6 honesty): what the `[input]` entry for `p_action`
// looks like on the **disk** right now, read with the engine's own reader.
// `Created` covers "there is no file yet" as well as "the file has no entry for
// this action": both mean the entry this call writes is new.
static InputActionPublish _input_action_entry_state_on_disk(const String &p_path, const String &p_action, const Dictionary &p_expected) {
	if (!FileAccess::exists(p_path)) {
		return InputActionPublish::Created;
	}
	Ref<ConfigFile> file;
	file.instantiate();
	if (file->load(p_path) != OK) {
		// The file exists but is not parseable: whatever this call writes is not
		// a "replacement" of something that was read, so it is reported as
		// unknown rather than guessed. The publish + read-back below still
		// decides `persisted`.
		return InputActionPublish::Unknown;
	}
	if (!file->has_section_key("input", p_action)) {
		return InputActionPublish::Created;
	}
	String ignored;
	if (read_input_action_from_disk(p_path, p_action, p_expected, ignored)) {
		return InputActionPublish::Unchanged;
	}
	return InputActionPublish::Replaced;
}

const char *input_action_publish_name(InputActionPublish p_publish) {
	switch (p_publish) {
		case InputActionPublish::Created:
			return "created";
		case InputActionPublish::Replaced:
			return "replaced";
		case InputActionPublish::Unchanged:
			return "unchanged";
		case InputActionPublish::Unknown:
			return "unknown";
		case InputActionPublish::None:
			break;
	}
	return "none";
}

bool persist_input_action_to(InputMap *p_map, const String &p_action, const String &p_target_path, String &r_reason, InputActionPublish *r_publish) {
	r_reason = String();
	if (r_publish != nullptr) {
		*r_publish = InputActionPublish::None;
	}
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr) {
		r_reason = "ProjectSettings is not available in this process, so the input action cannot be written to project.godot";
		return false;
	}
	Dictionary value;
	if (!input_action_project_value(p_map, p_action, value, r_reason)) {
		return false;
	}

	// TASK-042 section 3: what the entry is *before* the write, taken from the
	// disk (never from the in-memory `ProjectSettings`, which is what is about to
	// be changed). This is what makes "the entry is new" distinguishable from "an
	// existing action's entry was mirrored / replaced".
	const InputActionPublish before = _input_action_entry_state_on_disk(p_target_path, p_action, value);

	const String key = input_action_setting_key(p_action);
	const bool existed = settings->has_setting(key);
	const Variant previous = existed ? settings->get_setting(key) : Variant();
	settings->set_setting(key, value);

	MCPToolError error;
	if (!publish_project_setting_to(p_target_path, key, nullptr, error)) {
		// The target still holds its old bytes; put the in-memory setting back so
		// memory and disk agree (the rule `project_set_setting` already follows).
		if (existed) {
			settings->set_setting(key, previous);
		} else {
			settings->clear(key);
		}
		r_reason = vformat("The action was written to this process' InputMap, but publishing it to '%s' failed: %s", p_target_path, error.message);
		return false;
	}

	// Read back *from the file*, never from the `ProjectSettings` memory that was
	// just written: "the writer returned OK" is not evidence that the file changed.
	if (!read_input_action_from_disk(p_target_path, p_action, value, r_reason)) {
		r_reason = vformat("The action was published to '%s', but reading it back from disk did not confirm it: %s", p_target_path, r_reason);
		if (r_publish != nullptr) {
			*r_publish = InputActionPublish::Unknown;
		}
		return false;
	}
	if (r_publish != nullptr) {
		*r_publish = before;
	}
	return true;
}

bool persist_input_action(InputMap *p_map, const String &p_action, String &r_reason, InputActionPublish *r_publish) {
	r_reason = String();
	if (r_publish != nullptr) {
		*r_publish = InputActionPublish::None;
	}
	if (ProjectSettings::get_singleton() == nullptr) {
		r_reason = "ProjectSettings is not available in this process, so the input action cannot be written to project.godot";
		return false;
	}
	const String path = project_settings_file_path();
	// This is the guard that keeps the *editor tool* honest in a process that has
	// no project at all - the doctest process runs against the engine source tree,
	// and a `--check-only`-style run has nothing to write to. It never *creates*
	// `project.godot`: publishing to a destination that does not exist yet is only
	// reachable through `persist_input_action_to()`, which a test owns.
	if (!FileAccess::exists(path)) {
		r_reason = vformat("This process has no project.godot (looked for '%s'), so the action was written to its InputMap only and a game cannot see it. Run this tool against an editor opened with --path <project directory>",
				path.is_empty() ? String("<unknown>") : path);
		return false;
	}
	return persist_input_action_to(p_map, p_action, path, r_reason, r_publish);
}

// ---------------------------------------------------------------------------
// Screenshot destination + PNG writer (hoisted by TASK-011 section 2 from
// `tools/editor_write_scene_editor.cpp`). Verbatim move; the two refusal
// messages are unchanged, and the editor group's doctests still pin them.
// ---------------------------------------------------------------------------

bool normalize_screenshot_path(const String &p_input, String &r_out, MCPToolError &r_error) {
	const String path = p_input.replace("\\", "/");
	if (path.contains("..")) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'save_path' must not walk upwards with '..', got '%s'", p_input));
		return false;
	}
	if (!path.begins_with("res://") && !path.begins_with("user://")) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'save_path' must start with 'res://' or 'user://', got '%s'", p_input));
		return false;
	}
	if (path.get_file().is_empty() || path.get_file() == ".") {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'save_path' must name a file, got '%s'", p_input));
		return false;
	}
	r_out = path;
	return true;
}

Error screenshot_png_writer(const String &p_temp_path, void *p_userdata) {
	const Ref<Image> *image = static_cast<const Ref<Image> *>(p_userdata);
	return (*image)->save_png(p_temp_path);
}

// TASK-046: the one place the module can ask the PNG driver for the fast
// encoding. See tool_helpers.h for the file:line chain (`image_to_png(p_fast)` ->
// `PNG_IMAGE_FLAG_FAST` -> no filters + level 3) and for why `p_fast == false`
// is left as the old `Image::save_png()` call rather than re-implemented: the two
// screenshot tools' bytes must not move.
Error write_screenshot_png(const String &p_path, const Ref<Image> &p_image, bool p_fast) {
	if (p_image.is_null()) {
		return ERR_INVALID_PARAMETER;
	}
	if (!p_fast) {
		// The exact call every existing caller makes, error behaviour included
		// (`ERR_UNAVAILABLE` when the build has no PNG saver).
		return p_image->save_png(p_path);
	}

	// `_save_png_to_buffer` answers an **empty** buffer - not an error - when
	// `Image::save_png_buffer_func` was never registered, so that case is turned
	// back into the refusal `save_png` would have given.
	const Vector<uint8_t> buffer = p_image->_save_png_to_buffer(true);
	if (buffer.is_empty()) {
		return ERR_UNAVAILABLE;
	}

	Error err = OK;
	Ref<FileAccess> file = FileAccess::open(p_path, FileAccess::WRITE, &err);
	if (file.is_null()) {
		return err;
	}
	file->store_buffer(buffer.ptr(), buffer.size());
	const Error write_error = file->get_error();
	if (write_error != OK && write_error != ERR_FILE_EOF) {
		return ERR_CANT_CREATE;
	}
	return OK;
}

// ---------------------------------------------------------------------------
// Screenshot pixel comparison (hoisted by TASK-044 section 2.5).
//
// Verbatim move of the loop that used to live in
// `_tool_analyze_screenshot_diff` (`tools/editor_testing_read.cpp`). The only
// edits are the removed `static`, the two image parameters renamed to `a`/`b`,
// the caller-supplied labels of the size-mismatch message and the
// `p_build_diff_image` switch. See tool_helpers.h for the two callers and for
// why the tool's argument handling deliberately stayed with the tool.
//
// TASK-045 (the capture's post-response cost) added the raw-byte walk below:
// `Image::get_pixel` was called 5.3 million times per comparison in the
// `every_call` capture, which is what made the back-to-back round trip 453.6 ms
// (REPORT-044 D4). The bytes of the very same buffer are available through
// `Image::get_data()` (`core/io/image.h:392`, `const Vector<uint8_t> &` - a
// reference, so no copy is made), and `Image::get_pixel` itself indexes that
// buffer as `p_y * width + p_x` (`core/io/image.cpp:3816`) with a *pixel* size
// from `Image::get_format_pixel_size` (`core/io/image.cpp:137`), so a linear
// row walk with `pixel_size` bytes per pixel reads exactly the pixels the
// per-pixel loop reads.
// ---------------------------------------------------------------------------

namespace {

// The byte layout of the formats the raw-byte path can walk. `r`/`g`/`b` are
// byte offsets inside one pixel; `-1` marks a channel the format never fills,
// i.e. one whose `Color` component is exactly `0.0` (`FORMAT_R8` and
// `FORMAT_RG8` decode to `Color(r, 0, 0, 1)` / `Color(r, g, 0, 1)`), so the byte
// difference on that channel is 0 in both paths.
struct RawPixelLayout {
	bool usable = false;
	int pixel_size = 0;
	int r = -1;
	int g = -1;
	int b = -1;
};

// Only the formats whose `Image::_get_color_at_ofs` branch
// (`core/io/image.cpp:3560-3590`) is a plain `byte / 255.0` per channel:
// `FORMAT_L8` (`Color(l, l, l, 1)`), `FORMAT_LA8` (the same triplet), `FORMAT_R8`,
// `FORMAT_RG8`, `FORMAT_RGB8` and `FORMAT_RGBA8`. Everything else - the packed
// 4444/565 forms (`color_from_rgba4444`/`color_from_rgb565` are quantised, not
// raw bytes), the float/half/16-bit forms and every compressed format - keeps
// the per-pixel loop, which is also what preserves the engine's own
// "Can't get_pixel() on compressed image" refusal (`image.cpp:3690`).
RawPixelLayout raw_pixel_layout(Image::Format p_format) {
	switch (p_format) {
		case Image::FORMAT_L8: {
			return RawPixelLayout{ true, 1, 0, 0, 0 };
		}
		case Image::FORMAT_LA8: {
			return RawPixelLayout{ true, 2, 0, 0, 0 };
		}
		case Image::FORMAT_R8: {
			return RawPixelLayout{ true, 1, 0, -1, -1 };
		}
		case Image::FORMAT_RG8: {
			return RawPixelLayout{ true, 2, 0, 1, -1 };
		}
		case Image::FORMAT_RGB8: {
			return RawPixelLayout{ true, 3, 0, 1, 2 };
		}
		case Image::FORMAT_RGBA8: {
			return RawPixelLayout{ true, 4, 0, 1, 2 };
		}
		default: {
			return RawPixelLayout();
		}
	}
}

// One channel of one pixel as the byte the format stores (0 when the format has
// no such channel).
int raw_pixel_byte(const uint8_t *p_pixel, int p_offset) {
	if (p_offset < 0) {
		return 0;
	}
	return (int)p_pixel[p_offset];
}

// The `Color` `Image::_get_color_at_ofs` builds for a pixel of one of the six
// formats above, from the same bytes and with the same expression the engine
// uses (`float r = ptr[i] / 255.0;`), so `Color::get_r8()` on it is the byte.
// Only the "unchanged pixel keeps a dimmed copy of the source" half of the
// difference picture needs it; the comparison itself never builds a `Color`.
Color raw_pixel_colour(const uint8_t *p_pixel, const RawPixelLayout &p_layout) {
	float r = 0.0f;
	float g = 0.0f;
	float b = 0.0f;
	if (p_layout.r >= 0) {
		r = p_pixel[p_layout.r] / 255.0;
	}
	if (p_layout.g >= 0) {
		g = p_pixel[p_layout.g] / 255.0;
	}
	if (p_layout.b >= 0) {
		b = p_pixel[p_layout.b] / 255.0;
	}
	// MCP-NARROWING: G24-DIFF-PIXEL-UNCHANGED - the raw-byte twin of the
	// per-pixel loop's own "unchanged" colour: `r`/`g`/`b` are 32-bit floats
	// produced by the engine's own `byte / 255.0`, and `* 0.3` is the same
	// product of two 32-bit-descended values the pinned point in the fallback
	// loop uses. No caller input reaches either (TASK-045).
	return Color(r * 0.3, g * 0.3, b * 0.3, 1.0);
}

// `true` unless a doctest asked for the per-pixel loop on purpose.
bool raw_path_enabled = true;

// Whether the most recent call took the raw-byte path (TASK-045's test seam: the
// equivalence doctests pass whichever path runs, so "the fast path really is the
// one being exercised" has to be observable).
bool raw_path_used_by_last_call = false;

} // namespace

void set_compare_screenshot_pixels_raw_path_for_tests(bool p_enabled) {
	raw_path_enabled = p_enabled;
}

bool compare_screenshot_pixels_last_call_used_raw_path_for_tests() {
	return raw_path_used_by_last_call;
}

bool compare_screenshot_pixels(const Ref<Image> &p_a, const Ref<Image> &p_b, int p_threshold,
		bool p_build_diff_image, const String &p_label_a, const String &p_label_b,
		ScreenshotDiff &r_out, MCPToolError &r_error) {
	raw_path_used_by_last_call = false;
	if (p_a.is_null() || p_b.is_null()) {
		// A caller-side programming error, not something a client can send: the
		// tool has already refused a missing/unloadable image and the capture
		// only ever reaches this with two decoded frames.
		r_error = MCPToolError::internal("Two images are required for a pixel comparison");
		return false;
	}

	const int width = p_a->get_width();
	const int height = p_a->get_height();
	if (width != p_b->get_width() || height != p_b->get_height()) {
		r_error = MCPToolError::invalid_params(vformat(
				"Image size mismatch: %s is %dx%d and %s is %dx%d",
				p_label_a, width, height, p_label_b, p_b->get_width(), p_b->get_height()));
		return false;
	}

	Ref<Image> diff_image;
	if (p_build_diff_image) {
		diff_image = Image::create_empty(width, height, false, Image::FORMAT_RGBA8);
	}

	const int64_t total = (int64_t)width * (int64_t)height;

	// The raw-byte path needs the two images to have the *same* size (already
	// checked above) and the *same* covered format: a comparison is only defined
	// channel by channel between two decodes of the same kind. Two different
	// formats are **not** normalised with `Image::convert()` - that would add a
	// second full-image copy plus a second conversion table (whose rounding for
	// the float/half/16-bit sources is not `Color::get_r8`'s), and neither
	// caller has that shape: the capture compares two frames of the same
	// viewport and the tool two PNGs, both of which decode to the same format.
	// Such a pair keeps the per-pixel loop, exactly as before TASK-045.
	const Image::Format format_a = p_a->get_format();
	const RawPixelLayout layout = raw_pixel_layout(format_a);
	const int64_t needed = total * (int64_t)layout.pixel_size;
	const bool raw_path = raw_path_enabled && layout.usable && format_a == p_b->get_format() &&
			p_a->get_data().size() >= needed && p_b->get_data().size() >= needed;

	int64_t changed = 0;
	if (raw_path) {
		raw_path_used_by_last_call = true;
		const uint8_t *bytes_a = p_a->get_data().ptr();
		const uint8_t *bytes_b = p_b->get_data().ptr();
		const int pixel_size = layout.pixel_size;
		for (int y = 0; y < height; y++) {
			const uint8_t *row_a = bytes_a + (int64_t)y * width * pixel_size;
			const uint8_t *row_b = bytes_b + (int64_t)y * width * pixel_size;
			for (int x = 0; x < width; x++) {
				const uint8_t *pixel_a = row_a + x * pixel_size;
				const uint8_t *pixel_b = row_b + x * pixel_size;
				// The same three per-channel byte differences the per-pixel loop
				// takes through `Color::get_r8()`: for the six covered formats
				// that accessor answers the stored byte itself (exhaustively
				// pinned in the TASK-045 doctest).
				const int dr = Math::abs(raw_pixel_byte(pixel_a, layout.r) - raw_pixel_byte(pixel_b, layout.r));
				const int dg = Math::abs(raw_pixel_byte(pixel_a, layout.g) - raw_pixel_byte(pixel_b, layout.g));
				const int db = Math::abs(raw_pixel_byte(pixel_a, layout.b) - raw_pixel_byte(pixel_b, layout.b));
				const int max_diff = MAX(dr, MAX(dg, db));
				if (max_diff > p_threshold) {
					changed++;
					if (p_build_diff_image) {
						// MCP-NARROWING: G24-DIFF-PIXEL-CHANGED - the raw-byte twin
						// of the pinned point in the fallback loop below; the same
						// `CLAMP(max_diff / 255.0, 0.3, 1.0)` over the same
						// byte-derived difference, so no caller input reaches it
						// (TASK-045).
						diff_image->set_pixel(x, y, Color(1, 0, 0, CLAMP((double)max_diff / 255.0, 0.3, 1.0)));
					}
				} else if (p_build_diff_image) {
					diff_image->set_pixel(x, y, raw_pixel_colour(pixel_a, layout));
				}
			}
		}
	} else {
		for (int y = 0; y < height; y++) {
			for (int x = 0; x < width; x++) {
				const Color a = p_a->get_pixel(x, y);
				const Color b = p_b->get_pixel(x, y);
				// `Color::get_r8()` is this fork's own 8-bit accessor (the GDScript
				// `Color.r8` property binding, `color.h:233`); the float `Color::r` is
				// multiplied by 255 and *rounded* inside it, which is exactly the
				// "per channel byte difference" the threshold is defined in.
				const int dr = Math::abs(a.get_r8() - b.get_r8());
				const int dg = Math::abs(a.get_g8() - b.get_g8());
				const int db = Math::abs(a.get_b8() - b.get_b8());
				const int max_diff = MAX(dr, MAX(dg, db));
				if (max_diff > p_threshold) {
					changed++;
					if (p_build_diff_image) {
						// The migration source's difference colour, verbatim.
						// MCP-NARROWING: G24-DIFF-PIXEL-CHANGED - both `Color(...)` calls
						// below build `float` components out of *computed* values this
						// function owns: `CLAMP(max_diff/255.0, 0.3, 1.0)` is bounded to
						// [0.3, 1], and `a.r * 0.3` is a product of two values the engine
						// already stores as 32-bit floats. No caller input reaches them,
						// so no gate is possible or needed (TASK-023 D-7 scan entry).
						diff_image->set_pixel(x, y, Color(1, 0, 0, CLAMP((double)max_diff / 255.0, 0.3, 1.0)));
					}
				} else if (p_build_diff_image) {
					// MCP-NARROWING: G24-DIFF-PIXEL-UNCHANGED - see above.
					diff_image->set_pixel(x, y, Color(a.r * 0.3, a.g * 0.3, a.b * 0.3, 1.0));
				}
			}
		}
	}

	// Deliberately unguarded, exactly like the moved body: a zero-pixel image
	// cannot be loaded (the engine's decoders refuse it) and the capture only
	// ever compares two frames a viewport really produced.
	const double diff_percentage = (double)changed / (double)total * 100.0;

	r_out.width = width;
	r_out.height = height;
	r_out.changed_pixels = changed;
	r_out.total_pixels = total;
	r_out.identical = changed == 0;
	// `snappedf(diff_pct, 0.01)`: two decimals, the migration source's own
	// rounding (`stepify`), applied so two runs print the same number.
	r_out.diff_percentage = Math::snapped(diff_percentage, 0.01);
	r_out.diff_image = diff_image;
	return true;
}

// ---------------------------------------------------------------------------
// Editor-UI guard (TASK-009 section 2.2).
//
// The verbatim union of the two file-private copies, with the two message
// strings parameterised (see tool_helpers.h for both long explanatory comments:
// the `EditorInterface` / `EditorNode` null-check reasoning and the
// compile-time guard). Nothing else changed, so every call site answers exactly
// what it answered before.
// ---------------------------------------------------------------------------

bool require_editor_ui(MCPToolError &r_error, const String &p_what, const String &p_hint) {
#ifdef MCP_EDITOR_TOOLS_ENABLED
	if (is_editor_process()) {
		if (EditorNode::get_singleton() != nullptr) {
			return true;
		}
		r_error = MCPToolError::not_implemented("the editor UI (no EditorNode is running in this process)", p_hint);
		return false;
	}
#endif
	r_error = MCPToolError::not_implemented(p_what, p_hint);
	return false;
}

// ---------------------------------------------------------------------------
// The in-process editor log (TASK-026; see tool_helpers.h for the contract and
// for what "the panel is showing" does and does not include).
//
// `EditorLog` keeps both its message list and its `RichTextLabel` private
// (`editor/editor_log.h:129/133`) and exposes no reader, so the rendered text is
// what can be read. The label is found through the dock's children, which is the
// same route `editor_remove_output_log` takes to measure the panel: the dock's
// only `RichTextLabel` descendant is the log itself (`bbcode_parser` is created
// but never added as a child, editor_log.cpp:377-381).
//
// The walker is deliberately *not* shared with `editor_remove_output_log`: that
// tool measures and clears the panel, this one only reads it as lines, and
// moving the panel-locating code into a common helper is a refactor of another
// group's file that this task's scope does not include. The duplication is
// recorded as a residual in REPORT-026.
// ---------------------------------------------------------------------------
#ifdef MCP_EDITOR_TOOLS_ENABLED
static RichTextLabel *_editor_log_view(Node *p_node) {
	const int children = p_node->get_child_count();
	for (int i = 0; i < children; i++) {
		Node *child = p_node->get_child(i);
		if (child == nullptr) {
			continue;
		}
		RichTextLabel *label = Object::cast_to<RichTextLabel>(child);
		if (label != nullptr) {
			return label;
		}
		label = _editor_log_view(child);
		if (label != nullptr) {
			return label;
		}
	}
	return nullptr;
}
#endif

bool editor_log_lines(Vector<String> &r_lines) {
#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorNode *editor_node = EditorNode::get_singleton();
	if (editor_node == nullptr) {
		return false;
	}
	EditorLog *log = EditorNode::get_log();
	if (log == nullptr) {
		return false;
	}
	RichTextLabel *view = _editor_log_view(log);
	if (view == nullptr) {
		return false;
	}
	// Split exactly the way the file branch does (`split("\n", true)`, no
	// `str::lines()`), so both sources answer the same line-list shape and the
	// tail window means the same thing on either of them.
	r_lines = view->get_parsed_text().split("\n", true);
	return true;
#else
	(void)r_lines;
	return false;
#endif
}

// ---------------------------------------------------------------------------
// Editor node-path resolution (TASK-016 section 1).
//
// The verbatim union of the five file-private copies (three `_edited_scene_root`,
// two `_find_node`). Only the `static` keyword and the leading `_` were removed:
// no branch, no comparison and no order changed, which is what the before/after
// wire comparison of REPORT-016 section 1 proves byte for byte. See
// tool_helpers.h for the `SceneTree` vs `EditorInterface` reasoning and for the
// migration source's resolution order.
// ---------------------------------------------------------------------------

Node *edited_scene_root() {
	SceneTree *tree = SceneTree::get_singleton();
	if (tree == nullptr) {
		return nullptr;
	}
	return tree->get_edited_scene_root();
}

// The body of tools/editor_node_write.cpp:81, verbatim: only the `static` and the
// leading `_` were removed. TASK-017's three groups had copied it byte for byte;
// the four copies are gone and every call site calls this one (repair pass D3).
String relative_path(Node *p_root, Node *p_node) {
	if (p_node == p_root) {
		return ".";
	}
	return String(p_root->get_path_to(p_node));
}

// ---------------------------------------------------------------------------
// TASK-027 E-2/E-8 - the module's wire spelling of a *node* the tool answered
// about (a success field or a refusal message).
//
// Engine basis: the path a node has *inside the edited scene* is
// `Node::get_path_to(root, ...)` (`scene/main/node.h:573`), because the edited
// scene root is the creation-semantics root. `Node::get_path()`
// (`node.cpp:2462`) walks to the **scene-tree** root instead, which inside the
// editor is the editor's own UI layout: `/root/@EditorNode@<id>/@Panel@<id>/.../
// @SubViewport@<id>/Main/Actor` - unreproducible across machines/layouts and
// unusable as an input to any other tool (M4c E-2/E-8, REPORT-026 section 9).
//
// The three cases, in order:
//   1. not a Node at all -> its class name (a `Resource` has no scene path - the
//      rule tools/running_game_node_write.cpp:600 already used);
//   2. not inside a scene tree -> the empty string, and deliberately **without**
//      calling `Node::get_path()`, which is an `ERR_FAIL_COND_V_MSG` in that
//      state (node.cpp:2463) - the same guard (and the same answer) the node
//      write group had;
//   3. inside a tree: relative to the edited scene root when the node really
//      belongs to it (the editor case), otherwise the engine's own path (a
//      running game: `/root/Main/Actor`, which is what every game tool of the
//      module answers - changing that is not this task).
// ---------------------------------------------------------------------------
String wire_node_path(const Object *p_object) {
	const Node *node = Object::cast_to<Node>(p_object);
	if (node == nullptr) {
		return p_object->get_class();
	}
	if (!node->is_inside_tree()) {
		return String();
	}
	Node *root = edited_scene_root();
	if (root != nullptr && (root == node || root->is_ancestor_of(const_cast<Node *>(node)))) {
		return relative_path(root, const_cast<Node *>(node));
	}
	return String(node->get_path());
}

Node *find_node(Node *p_root, const String &p_path) {
	if (p_path == "." || p_path == String(p_root->get_name())) {
		return p_root;
	}
	const NodePath requested(p_path);
	if (p_root->has_node(requested)) {
		return p_root->get_node(requested);
	}
	const String root_name = String(p_root->get_name());
	const String prefix = root_name + "/";
	if (p_path.begins_with(prefix)) {
		const NodePath nested(p_path.substr(prefix.length()));
		if (p_root->has_node(nested)) {
			return p_root->get_node(nested);
		}
	}
	return nullptr;
}

// TASK-063 (b): the appended half of the two single-path descriptions. It is
// ASCII, so it travels as a plain `const char *` and the Chinese head of each
// description is added by the registrar (which is where the original wording
// lives). The text is byte-identical to `NODE_PATH_RULE_SENTENCE` in
// `scripts/gen_renamed_contract.py`; gate 1 is what keeps them together.
const char *const NODE_PATH_RULE_SENTENCE =
		"A node path here is resolved relative to the edited scene root and this parameter names ONE node "
		"(the plural tools spell the same strings as 'node_paths', an array: editor_set_node_script_batch "
		"and editor_set_node_property_updates): 'Bricks/Car' and './Bricks/Car' address 'Car' inside "
		"'Bricks', and the edited scene root's own name may be used as a prefix ('Main/Bricks/Car' == "
		"'Bricks/Car' == './Bricks/Car'). An absolute scene-tree path ('/root/Main/Bricks/Car') is not "
		"accepted, and a bare name such as 'Car' only addresses a direct child of the edited scene root. A "
		"refused path names this rule in data.suggestion.";

// TASK-063 (b): the one node-path guidance sentence. See the declaration for the
// defect it answers; the two halves differ only in whether the parameter names
// one node or many, and both name the tool the caller should use to see the paths
// that exist. The trailing sentence is the one TASK-016's refusals already
// carried, kept so an existing reader does not lose it.
String node_path_guidance(const String &p_parameter, bool p_plural) {	const String shape = p_plural
			? vformat("Parameter '%s' is an array of node paths, each resolved relative to the edited scene root "
					  "(the singular node tools take the same strings under the name 'path')",
					  p_parameter)
			: vformat("Parameter '%s' takes ONE node path, resolved relative to the edited scene root "
					  "(the plural node tools take the same strings under the name 'node_paths')",
					  p_parameter);
	return vformat(
			"%s: 'Bricks/Car' and './Bricks/Car' address 'Car' inside 'Bricks', and the edited "
			"scene root's own name may be used as a prefix ('Main/Bricks/Car' == 'Bricks/Car' == "
			"'./Bricks/Car'). An absolute scene-tree path ('/root/Main/Bricks/Car') is not accepted, and a "
			"bare name such as 'Car' only addresses a direct child of the edited scene root. Use "
			"editor_get_scene_tree to list the nodes of the edited scene",
			shape);
}

// ---------------------------------------------------------------------------
// ClassDB instantiation + property existence (TASK-017 section 4).
//
// The body is the class-level half of the rule TASK-015 wrote inside
// `MCPTools::instantiate_node_of_type` (tools/editor_node_write.cpp); that
// function is now the node-flavoured wrapper over this one, so the module still
// has exactly one ClassDB instantiation. The refusal messages keep TASK-015's
// wording (only the leading noun is generic, because a `Shape2D`/`Environment`
// is not a node); the doctests that pin them assert substrings
// ("no such class" / "not a Node subclass") and stay green.
// ---------------------------------------------------------------------------
Object *instantiate_class(const String &p_type, MCPToolError &r_error) {
	const StringName type_name(p_type);
	if (!ClassDB::class_exists(type_name)) {
		r_error = MCPToolError::invalid_params(vformat("Cannot instantiate type '%s': no such class", p_type));
		return nullptr;
	}
	if (!ClassDB::can_instantiate(type_name)) {
		r_error = MCPToolError::invalid_params(vformat("Cannot instantiate type '%s': the class is abstract or not instantiable", p_type));
		return nullptr;
	}
	Object *created = ClassDB::instantiate(type_name);
	if (created == nullptr) {
		r_error = MCPToolError::invalid_params(vformat("Cannot instantiate type '%s'", p_type));
		return nullptr;
	}
	return created;
}

bool object_has_property(const Object *p_object, const StringName &p_name) {
	if (p_object->get(p_name).get_type() != Variant::NIL) {
		return true;
	}
	List<PropertyInfo> properties;
	p_object->get_property_list(&properties);
	for (const PropertyInfo &property : properties) {
		if (property.name == p_name) {
			return true;
		}
	}
	return false;
}

// ---------------------------------------------------------------------------
// Argument-shape helpers (hoisted by the TASK-017 repair pass).
//
// `optional_dictionary` is the body of tools/editor_node_write.cpp:91 (identical
// to tools/editor_node_setup.cpp:163); `optional_float` is the body of
// tools/editor_node_setup.cpp:142. The same five lines also existed as
// `_optional_number` in editor_input_simulation.cpp:202 and
// running_game_read_scene.cpp:110 (both removed), as the value half of
// editor_write_scene_editor.cpp:115's presence-flag variant (removed; the
// presence flag stays at its call site), and as the value half of
// running_game_frame_observation.cpp:148's positive-seconds reader (that file
// keeps its own two refusals and calls this reader). Only the `static` and the
// leading `_` were removed. See tool_helpers.h.
// ---------------------------------------------------------------------------

bool optional_dictionary(const Dictionary &p_args, const String &p_key, Dictionary &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = Dictionary();
		return true;
	}
	if (value.get_type() != Variant::DICTIONARY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be an object, got %s",
				p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	r_out = value;
	return true;
}

bool optional_float(const Dictionary &p_args, const String &p_key, double p_default, double &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_out = p_default;
		return true;
	}
	if (value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be a number, got %s",
				p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	r_out = (double)value;
	return true;
}

// ---------------------------------------------------------------------------
// Property-value helpers (TASK-009 section 2.2).
//
// `property_value_from_json` is the *superset* of the two former copies: the
// editor copy's extra `INT` case is included (Godot's JSON parser has a single
// number type, so an integral value arrives as a float and is folded back when
// the property is an int), and the `FLOAT` INT-target guard is the range test
// taken from the former `project_write_resource_scene.cpp` copy (equivalent in
// range, and unlike the original `(double)(int64_t)number` form it does not
// invoke UB for a finite double outside the int64 range).
// `coerce_to_property_type` differs from the former
// copies only by the parameter name inside the non-finite-number message, which
// is now `p_parameter_name`, so every wire message stays byte-identical.
// ---------------------------------------------------------------------------

Variant property_value_from_json(const Variant &p_value, Variant::Type p_target_type) {
	switch (p_value.get_type()) {
		case Variant::NIL: {
			return Variant();
		}
		case Variant::BOOL: {
			return (bool)p_value;
		}
		case Variant::INT: {
			return p_target_type == Variant::INT ? Variant((int64_t)p_value) : Variant((double)p_value);
		}
		case Variant::FLOAT: {
			const double number = (double)p_value;
			// The INT-target folding, and its guard: the cast below is only defined
			// for a finite value inside the int64 range, so the range is tested first
			// (the pre-refactor `project_write_resource_scene.cpp` copy did the same
			// with -9.0e15..9.0e15).
			if (p_target_type == Variant::INT && Math::is_finite(number) && number >= -9.0e15 && number <= 9.0e15) {
				const int64_t truncated = (int64_t)number;
				if ((double)truncated == number) {
					return Variant(truncated);
				}
			}
			return Variant(number);
		}
		case Variant::STRING: {
			// **A string is only ever a String here.** The migration source also
			// parsed the Godot string grammar out of this branch (`"#rrggbb"` as a
			// Color, `"Vector2(1,2)"` as a Vector, serialize.rs:299-317) by calling
			// `Variant::construct_from_string`, but that function is a **stub in
			// this fork** (TASK-018 report): it always leaves its output as `NIL`,
			// the two `begins_with` guards above never once produced a value, and
			// the dead branch only invited a later batch to believe the syntax
			// worked. P-1 (TASK-019 section 2) deletes it instead of teaching the
			// engine core a parser the fork does not share with upstream: a string
			// therefore reaches `coerce_to_property_type` unchanged and a
			// `"Vector2(1,2)"` for a Vector2 property is refused with `-32602`
			// (`Variant::can_convert(STRING, VECTOR2)` is false) - the honest
			// answer for a syntax this fork cannot evaluate. Send the structured
			// object (`{"x": 1, "y": 2}`) or a JSON string for a String property.
			//
			// `"#rrggbb"` is *not* lost: `coerce_to_property_type` reaches it
			// through `Variant::can_convert(STRING, COLOR)`, which the engine does
			// list, so a colour string still becomes a Color there.
			return (String)p_value;
		}
		case Variant::DICTIONARY: {
			// The `Variant::NIL` target type is deliberate: this branch keeps the
			// JSON structure, it never folds a value, so there is no component
			// type to judge a member against (a `DICTIONARY` property legitimately
			// holds strings). The components of a *composite* target are judged
			// where they are really folded - see the TASK-020 section 1 note in
			// tool_helpers.h and `shape_vector_from_json`.
			const Dictionary source = p_value;
			Dictionary out;
			const Array keys = source.keys();
			for (int i = 0; i < keys.size(); i++) {
				out[keys[i]] = property_value_from_json(source[keys[i]], Variant::NIL);
			}
			return out;
		}
		case Variant::ARRAY: {
			const Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(property_value_from_json(source[i], Variant::NIL));
			}
			return out;
		}
		default: {
			return p_value;
		}
	}
}

// TASK-010 section 3.3: the int64 range as a double, and the only value a double
// can express exactly at that magnitude (2^63). See `_integral_value` in
// tools/tool_builder.cpp for the whole argument: `type_convert` reaches
// `Variant::operator int64_t()`, whose FLOAT case is `T(_data._float)` - a raw
// cast that is undefined behaviour outside the int64 range, and whose result on
// this fork's `/fp:strict` x64 build is INT64_MIN. A caller that asked for an
// integer property and sent `1e20` must be refused, not given a different number.
static const double INT64_MAX_AS_DOUBLE = 9223372036854775808.0;

// TASK-018 section 1: the spelling of an offending value inside a refusal
// message. It is the module's own wire spelling (`serialize_variant` + JSON)
// truncated, so the message names what the caller sent in the same shape the
// caller would see in a successful answer, and a pathological array cannot turn
// one error message into a megabyte of text.
static String _value_spelling(const Variant &p_value) {
	const String text = JSON::stringify(serialize_variant(p_value), "", false, true);
	if (text.is_empty()) {
		return Variant::get_type_name(p_value.get_type());
	}
	return text.length() > 120 ? text.substr(0, 117) + "..." : text;
}

// TASK-020 D-2: does this string spell a number the engine will really read?
//
// `can_convert(STRING, FLOAT)` and `can_convert(STRING, INT)` are both **true** -
// the engine lists every string - because the two text-to-number parsers answer a
// default instead of failing. The honest question is therefore "does this string,
// as a whole, spell the number the target type receives?", which each parser can
// be asked directly:
//
//   * FLOAT (`String::to_float` / `built_in_strtod`): the engine's own spelling
//     test (`String::is_valid_float`, which is what rules out `"abc"`, `"NaN"`,
//     `"inf"` and `" 1.5"`) **and** a parse that consumes the whole string
//     (`"1e"` leaves its exponent behind and answers `1`) **and** a finite
//     result (`"1e999"` overflows to `inf` inside `built_in_strtod`).
//   * INT (`String::to_int`, a digit scanner): the whole string, apart from an
//     optional sign, is digits (`String::is_valid_int` - which is what rules out
//     `"1e3"`, whose `to_int` answer would be `1`, and `"1.5"`), plus the same
//     int64 range guard the FLOAT branch carries.
//
// Accepted spellings are unchanged: `"1.5"`, `"-3"`, `"2e3"` for a float and
// `"7"` for an integer convert exactly as they always did.
static bool _string_spells_number(const String &p_text, Variant::Type p_target_type, double &r_parsed) {
	if (p_target_type == Variant::INT) {
		if (!p_text.is_valid_int()) {
			return false;
		}
	} else {
		if (!p_text.is_valid_float()) {
			return false;
		}
		const char32_t *end = nullptr;
		String::to_float(p_text.get_data(), &end);
		if (end == nullptr || *end != 0) {
			return false;
		}
	}
	r_parsed = p_text.to_float();
	return true;
}

// TASK-021 A-1: does this string spell a boolean the tool may write?
//
// `Variant::can_convert(STRING, BOOL)` is **true** and
// `VariantUtilityFunctions::type_convert(string, BOOL)` reaches
// `Variant::booleanize()`, which is `!is_zero()` (`variant_op.cpp:1116-1124`,
// `variant.cpp`'s STRING case of `is_zero()` is `== String()`). Every
// **non-empty** string is therefore `true`: `"false"`, `"0"` and `"abc"` all
// wrote `true` next to a success (measured on the wire: `visible: "abc"` ->
// `code=0`). The engine's own text-to-bool notion is not a parser - this fork's
// `ustring.h` carries `is_valid_int`/`is_valid_float` and nothing for booleans -
// so the accepted spellings are named here, and only spellings that name a
// boolean unambiguously are accepted:
//
//   * the two words, case insensitively (`"true"`/`"True"`/`"TRUE"`, the same
//     for `"false"`), which is what a caller writing JSON-shaped data means;
//   * `"1"` and `"0"`, the numeric counterparts of the two booleans.
//
// Note the deliberate divergence from the *engine's* answer for `"0"`: this
// function maps it to `false` (what the spelling names) while `booleanize("0")`
// is `true` (the string is not empty). Writing `true` for `"0"` is exactly the
// silent wrong value this gate exists to remove, so the spelling wins; the
// report records the divergence.
static bool _string_spells_bool(const String &p_text, bool &r_out) {
	const String lowered = p_text.to_lower();
	if (lowered == "true" || lowered == "1") {
		r_out = true;
		return true;
	}
	if (lowered == "false" || lowered == "0") {
		r_out = false;
		return true;
	}
	return false;
}

// ---------------------------------------------------------------------------
// GDR-22 / TASK-022 D-4: the **one** slot-width judgement.
//
// This is the body the two shape-specific gates used to have separately
// (TASK-021 A-2's `_element_fits_container` here and A-4's
// `_component_fits_slot` in `running_game_node_write.cpp`). The two were the same
// judgement with two wordings, which is exactly why the third shape - the plain
// scalar member - was missed: each new shape needed a new function, and nobody
// added one. The `(width, value)` question now has one answer, and the call sites
// below only say *which* slot they are filling.
//
// `#ifdef REAL_T_IS_DOUBLE` branch accepted **everything**, and the same function
// judged a `PackedFloat32Array` element and a `Color` component - both `float`
// members in every build (`core/math/color.h:39-42`,
// `PackedFloat32Array::operator[]`) - so `precision=double` would have brought
// the whole class back. TASK-023 D-15 therefore split that slot: `FLOAT32` is
// judged as 32 bits in every build and is what a `Color` component and a
// `PackedFloat32Array` element use, while `REAL_T` follows the build.
//
// What the engine's own copy does in each case (measured by the TASK-021,
// TASK-022 and TASK-023 evidence runs):
//
//   * a `real_t` slot (`Object::set()` of a `real_t` member, a
//     `Vector2`/`Vector3`/`Vector4` component): `(float)1e300` is `inf`,
//     `(float)1e-300` is `0.0`;
//   * a `float32` slot (`Color` component, `PackedFloat32Array` element): the
//     same copy in every build;
//   * an `int32_t` slot: the low 32 bits (`(int32_t)3000000000LL` is
//     `-1294967296`);
//   * a `uint8_t` slot: the low 8 bits (`300` -> `44`, `-1` -> `255`).
//
// Both halves of a 32-bit float case are refusals. Overflow to `inf` is a value
// nobody sent, and a **non-zero** value underflowing to `0` is the same defect in
// the other direction; a genuinely zero (or denormal-representable) input is
// accepted, which is why the underflow test is `value != 0.0`.
// ---------------------------------------------------------------------------
ValueSlot scalar_member_slot(Variant::Type p_target_type) {
	// A `FLOAT` member of an `Object` is a `real_t` (`Object::set()` reaches the
	// bound setter, whose parameter is the declared C++ type). `INT` answers
	// `WIDE` on purpose - see the declaration for why that is the honest boundary
	// of this gate and not an omission.
	return p_target_type == Variant::FLOAT ? ValueSlot::REAL_T : ValueSlot::WIDE;
}

bool value_fits_slot(const Variant &p_value, ValueSlot p_slot, const String &p_parameter_name,
		const String &p_slot_context, MCPToolError &r_error) {
	// Two independent questions decide whether the 32-bit half below runs:
	//
	//   * `REAL_T` is as wide as the build's `real_t` - a `float` in this build,
	//     a `double` in a `precision=double` build, where the copy really cannot
	//     narrow anything;
	//   * `FLOAT32` is 32 bits **in every build** (GDR-24 / TASK-023 D-15):
	//     `Color`'s components and `PackedFloat32Array`'s elements are `float`
	//     members even when `real_t` is a `double`, so the build must not decide
	//     this one. Compiling `p_slot == ValueSlot::FLOAT32` in as "always judge"
	//     is what makes the correctness configuration-independent.
	const bool judge_32_bit =
			p_slot == ValueSlot::FLOAT32 ||
#ifdef REAL_T_IS_DOUBLE
			false;
#else
			p_slot == ValueSlot::REAL_T;
#endif

	if (!judge_32_bit) {
		switch (p_slot) {
			case ValueSlot::WIDE:
			case ValueSlot::REAL_T:
			case ValueSlot::FLOAT32: {
				// `WIDE` is the value's own type; `REAL_T`/`FLOAT32` reached here
				// only when their 32-bit half does not apply, i.e. the slot is a
				// `double` (the build's `real_t`, or - defensively - a
				// `REAL_T`/`FLOAT32` that a future build widened).
				return true;
			}
			case ValueSlot::INT32:
			case ValueSlot::UINT8:
			case ValueSlot::FROM_TARGET_TYPE:
				break;
		}
	}
	// `FROM_TARGET_TYPE` never reaches this function: the only caller that can
	// pass it (`coerce_to_property_type`) resolves it first. Treating it as
	// "nothing to judge" is the safe fallback rather than a silent refusal.
	if (p_slot == ValueSlot::FROM_TARGET_TYPE) {
		return true;
	}

	if (p_slot == ValueSlot::UINT8) {
		const int64_t value = (int64_t)p_value;
		if (value >= 0 && value <= 255) {
			return true;
		}
		const int64_t wrapped = (int64_t)(uint8_t)((uint64_t)value & 0xFFULL);
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' is the integer %s, which does not fit in %s: the engine's own copy would write %s "
				"instead of the value you sent. Send an integer between 0 and 255.",
				p_parameter_name, _value_spelling(p_value), p_slot_context, itos(wrapped)));
		return false;
	}

	if (p_slot == ValueSlot::INT32) {
		const int64_t value = (int64_t)p_value;
		if (value >= (int64_t)INT32_MIN && value <= (int64_t)INT32_MAX) {
			return true;
		}
		const int64_t low = (int64_t)(uint32_t)((uint64_t)value & 0xFFFFFFFFULL);
		const int64_t wrapped = low > (int64_t)INT32_MAX ? low - 4294967296LL : low;
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' is the integer %s, which does not fit in %s: the engine's own copy would write the "
				"low 32 bits (%s) instead of the value you sent. Send an integer between -2147483648 and 2147483647.",
				p_parameter_name, _value_spelling(p_value), p_slot_context, itos(wrapped)));
		return false;
	}

	// The 32-bit float half: `ValueSlot::REAL_T` in a single-precision build and
	// `ValueSlot::FLOAT32` in every build (GDR-24).
	//
	// MCP-NARROWING: G24-THE-GATE - this `(float)` is **the gate itself**: it is
	// the copy whose result the check below compares against, not a write into a
	// storage slot. It is the one narrow point of the module that must not call
	// `value_fits_slot` (that would recurse).
	const double value = (double)p_value;
	// MCP-NARROWING: G24-THE-GATE - see above: this cast IS the judgement.
	const float narrowed = (float)value;
	if (!Math::is_finite((double)narrowed)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' is the number %s, which does not fit in %s: the engine's own copy would write %s "
				"instead of the value you sent. The largest 32-bit float is about 3.4e38.",
				p_parameter_name, rtoss(value), p_slot_context, rtos((double)narrowed)));
		return false;
	}
	if (value != 0.0 && narrowed == 0.0f) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' is the number %s, which is too small for %s: the engine's own copy would write 0 "
				"instead of the value you sent. The smallest positive 32-bit float is about 1.4e-45.",
				p_parameter_name, rtoss(value), p_slot_context));
		return false;
	}
	return true;
}

// The slot one element of a packed container is copied into, or
// `ValueSlot::WIDE` when the container's element type is exactly as wide as the
// element gate already judged. `Variant::NIL` (a target this module does not
// treat as a container) answers `WIDE` as well: `_container_element_type` decides
// *whether* there is an element gate at all, and this only decides its width.
static ValueSlot _container_element_slot(Variant::Type p_container_type) {
	switch (p_container_type) {
		case Variant::PACKED_BYTE_ARRAY: {
			return ValueSlot::UINT8;
		}
		case Variant::PACKED_INT32_ARRAY: {
			return ValueSlot::INT32;
		}
		case Variant::PACKED_FLOAT32_ARRAY: {
			// GDR-24 / TASK-023 D-15: a `PackedFloat32Array` element is a
			// `float` **in every build**, so this slot must not be `REAL_T`
			// (`ValueSlot::FLOAT32` is judged as 32 bits even when `real_t` is a
			// `double`, where the old `REAL_T` answer accepted `1e300` and the
			// element copy wrote `inf`).
			return ValueSlot::FLOAT32;
		}
		default: {
			// `PackedInt64Array`/`PackedFloat64Array` store the type the element
			// gate judged, and the vector/colour arrays are judged per component
			// by the component table.
			return ValueSlot::WIDE;
		}
	}
}

// The element half of the gate: TASK-020 D-1 pushed every element through the
// type conversion, TASK-021 A-2 added the element's width, and TASK-022 routes
// that width through the one judgement above.
static bool _element_fits_container(const Variant &p_element, Variant::Type p_container_type,
		const String &p_parameter_name, MCPToolError &r_error) {
	const ValueSlot slot = _container_element_slot(p_container_type);
	if (slot == ValueSlot::WIDE) {
		return true;
	}
	return value_fits_slot(p_element, slot, p_parameter_name,
			vformat("the %s element a %s stores", (slot == ValueSlot::REAL_T || slot == ValueSlot::FLOAT32) ? "32-bit float" : (slot == ValueSlot::INT32 ? "32-bit signed integer" : "8-bit unsigned integer"),
					Variant::get_type_name(p_container_type)),
			r_error);
}

// TASK-020 D-1 (the container half): the type one element of a container target
// has to fill, or `Variant::NIL` when the target is not a container whose element
// type this module can name. A plain `ARRAY` (and a `DICTIONARY`) answers NIL on
// purpose: a JSON array has no declared element type, so its members are left
// exactly as they are.
static Variant::Type _container_element_type(Variant::Type p_target_type) {
	switch (p_target_type) {
		case Variant::PACKED_INT32_ARRAY:
		case Variant::PACKED_INT64_ARRAY:
		case Variant::PACKED_BYTE_ARRAY: {
			return Variant::INT;
		}
		case Variant::PACKED_FLOAT32_ARRAY:
		case Variant::PACKED_FLOAT64_ARRAY: {
			return Variant::FLOAT;
		}
		case Variant::PACKED_VECTOR2_ARRAY: {
			return Variant::VECTOR2;
		}
		case Variant::PACKED_VECTOR3_ARRAY: {
			return Variant::VECTOR3;
		}
		case Variant::PACKED_VECTOR4_ARRAY: {
			return Variant::VECTOR4;
		}
		case Variant::PACKED_COLOR_ARRAY: {
			return Variant::COLOR;
		}
		case Variant::PACKED_STRING_ARRAY: {
			return Variant::STRING;
		}
		default: {
			return Variant::NIL;
		}
	}
}

// ---------------------------------------------------------------------------
// TASK-027 D-8 (GDR-25 section 23.5) - the write half of the Object shape.
//
// The read half (`serialize_variant`) answers exactly three things, and this is
// the one place all three are taken back:
//
//   * `null`     -> a null reference (clear the property). This is the value
//                   `type_convert(null, OBJECT)` used to answer - the shape the
//                   TASK-026 probe measured as accepted - spelled explicitly so
//                   the acceptance does not depend on `can_convert(NIL, OBJECT)`
//                   staying listed.
//   * `"res://..."` -> `ResourceLoader::load()` and the loaded object.
//   * `{"type","path"}` -> the read-back shape itself, loaded by `path`, with
//                   `type` **checked** against what the file really loads as.
//
// Refusals, each honest about *why*:
//   * `{}` / an object without a usable `path` -> `-32602`. `{}` carries no
//     information at all (`Variant::can_convert(DICTIONARY, OBJECT)` is false, so
//     it was a provably dead shape); treating it as "clear" would be a silent
//     destructive guess;
//   * a path that does not exist / does not load -> `-32001` + suggestion, never
//     a silent no-op (section 23.5 rule 2);
//   * a `type` that is not what the file loads as, or a resource that is not of
//     the class the *property* declares -> `-32602`, the message naming both the
//     expected and the actual class. Without this second check the engine's own
//     setter would store `null` for a resource of the wrong class next to a
//     success (`Sprite2D.texture` is declared `Texture2D`), which is exactly the
//     "failure -> default -> report success" family the module refuses.
// ---------------------------------------------------------------------------
// Does `p_object` satisfy a class specification in the engine's own grammar
// (property_info.h:57): a comma separated list of class names; a name prefixed
// with `-` is an *exclusion* and only means anything after a base class
// (`"Texture2D,-MeshTexture"`). An empty specification accepts everything.
//
// The engine's own setter does this test implicitly by failing a cast and storing
// `null`; asking it here is what turns that silent default into a refusal that
// names both sides. It is defined before `_load_object_resource` (which uses it)
// and is shared by the node and the resource write paths, both of which arrive
// here through `coerce_to_property_type`.
static bool _object_fits_declared_class(const Object *p_object, const String &p_spec) {
	if (p_spec.is_empty()) {
		return true;
	}
	bool any_positive = false;
	bool matched_positive = false;
	const PackedStringArray parts = p_spec.split(",");
	for (int i = 0; i < parts.size(); i++) {
		String name = parts[i].strip_edges();
		if (name.is_empty()) {
			continue;
		}
		if (name.begins_with("-")) {
			const String excluded = name.substr(1).strip_edges();
			if (!excluded.is_empty() && p_object->is_class(excluded)) {
				return false;
			}
			continue;
		}
		any_positive = true;
		if (p_object->is_class(name)) {
			matched_positive = true;
		}
	}
	return !any_positive || matched_positive;
}

static bool _load_object_resource(const String &p_path, const String &p_declared_type, const String &p_payload_type,
		const String &p_parameter_name, Variant &r_out, MCPToolError &r_error) {
	if (!ResourceLoader::exists(p_path)) {
		r_error = MCPToolError::not_found(vformat("Resource '%s' named by parameter '%s'", p_path, p_parameter_name),
				"Pass the res:// path of a resource that exists in this project (project_get_filesystem_tree lists "
				"them), or null to clear an Object-valued property");
		return false;
	}
	const Ref<Resource> loaded = ResourceLoader::load(p_path);
	if (loaded.is_null()) {
		r_error = MCPToolError::not_found(vformat("Loadable resource '%s' named by parameter '%s'", p_path, p_parameter_name),
				"The file exists but this engine could not load it as a resource; fix or delete the file, or pass null "
				"to clear an Object-valued property");
		return false;
	}
	const String actual = loaded->get_class();
	if (!p_payload_type.is_empty() && !loaded->is_class(p_payload_type)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' names type '%s' but '%s' loads as a '%s': the 'type' member of an Object shape is checked "
				"against the resource its 'path' names, so send the class the engine really reports (as the read side "
				"answered it) or drop the member",
				p_parameter_name, p_payload_type, p_path, actual));
		return false;
	}
	if (!p_declared_type.is_empty() && !_object_fits_declared_class(loaded.ptr(), p_declared_type)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' loads '%s', which is a '%s', but this property is declared for a '%s' (the engine's own "
				"setter would store null instead of the value you sent): expected '%s', got '%s'",
				p_parameter_name, p_path, actual, p_declared_type, p_declared_type, actual));
		return false;
	}
	r_out = Variant(loaded.ptr());
	return true;
}

static bool _object_value_from_json(const Variant &p_value, const String &p_declared_type, const String &p_parameter_name,
		Variant &r_out, MCPToolError &r_error) {
	switch (p_value.get_type()) {
		case Variant::OBJECT: {
			// Not reachable from JSON; kept so the helper is total (an
			// already-typed object passes through).
			r_out = p_value;
			return true;
		}
		case Variant::NIL: {
			r_out = Variant((const Object *)nullptr);
			return true;
		}
		case Variant::STRING: {
			const String path = ((String)p_value).strip_edges();
			if (path.is_empty()) {
				r_error = MCPToolError::invalid_params(vformat(
						"Parameter '%s' is an empty string, which names no resource: send null to clear an Object-valued "
						"property or the res:// path of a resource to set it",
						p_parameter_name));
				return false;
			}
			return _load_object_resource(path, p_declared_type, String(), p_parameter_name, r_out, r_error);
		}
		case Variant::DICTIONARY: {
			const Dictionary shape = p_value;
			if (shape.is_empty()) {
				r_error = MCPToolError::invalid_params(vformat(
						"Parameter '%s' is the empty object {} and an Object-valued property cannot take it: {} names no "
						"resource, so it is not a legal value in either direction (the read side answers null for an "
						"unset reference and {\"type\",\"path\"} for a set one). Send null to clear the property, a "
						"res:// string, or the {\"type\":...,\"path\":...} shape the read side answered",
						p_parameter_name));
				return false;
			}
			const Variant path_value = shape.get("path", Variant());
			if (path_value.get_type() != Variant::STRING || ((String)path_value).strip_edges().is_empty()) {
				r_error = MCPToolError::invalid_params(vformat(
						"Parameter '%s' is an object without a usable 'path': an Object-valued property is written back in "
						"the shape it was read back in ({\"type\":\"<class>\",\"path\":\"res://...\"}). A pathless object "
						"(a sub-resource or a built-in resource) has no file to load, so pass a resource by its res:// path "
						"or null to clear the property",
						p_parameter_name));
				return false;
			}
			String payload_type;
			const Variant type_value = shape.get("type", Variant());
			if (type_value.get_type() != Variant::NIL) {
				if (type_value.get_type() != Variant::STRING) {
					r_error = MCPToolError::invalid_params(vformat(
							"Parameter '%s.type' must be a string naming the class the path loads as, got %s",
							p_parameter_name, Variant::get_type_name(type_value.get_type())));
					return false;
				}
				payload_type = (String)type_value;
			}
			return _load_object_resource(((String)path_value).strip_edges(), p_declared_type, payload_type, p_parameter_name, r_out, r_error);
		}
		default: {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter '%s' cannot be written to an Object-valued property: the value is a %s (%s) and an Object "
					"property takes null (clear), a res:// path string, or the {\"type\":\"<class>\",\"path\":\"res://...\"} "
					"shape the read side answered",
					p_parameter_name, Variant::get_type_name(p_value.get_type()), _value_spelling(p_value)));
			return false;
		}
	}
}

// The type half of `coerce_to_property_type`: everything the module judged before
// TASK-022 (the conversion relation, the string grammars, the boolean and colour
// spellings, the container element gate) plus the final `type_convert`.
//
// It is `static` and the array-element recursion calls **it** rather than the
// public entry point on purpose: an element's slot is its container's element
// slot, and the recursion must not apply the *member* rule (a `FLOAT` element of
// a `PackedFloat64Array` is a `double`, not a `real_t`). `_element_fits_container`
// above is what judges the element's width.
static bool _coerce_to_property_type_typed(const Variant &p_value, Variant::Type p_target_type, Variant &r_out,
		MCPToolError &r_error, const String &p_parameter_name) {
	if (p_value.get_type() == Variant::FLOAT) {
		const double number = (double)p_value;
		if (Math::is_nan(number) || Math::is_inf(number)) {
			r_error = MCPToolError::invalid_params(vformat("Parameter '%s' contains a non-finite number", p_parameter_name));
			return false;
		}
		if (p_target_type == Variant::INT && !(number >= -INT64_MAX_AS_DOUBLE && number < INT64_MAX_AS_DOUBLE)) {
			r_error = MCPToolError::invalid_params(vformat("Parameter '%s' is outside the range of a 64-bit integer", p_parameter_name));
			return false;
		}
	}
	// -----------------------------------------------------------------------
	// TASK-020 D-2 - the string half of the silent-wrong-value gate.
	//
	// The TASK-018 gate asks `Variant::can_convert`, and `can_convert(STRING,
	// FLOAT)` is **true**: the engine lists every string as convertible because
	// `String::to_float` answers `0` for the ones it cannot parse instead of
	// failing. Measured by the M4 acceptance: `rotation: "abc"` answered `code=0`
	// and wrote `0.0`, so the gate that was supposed to refuse an unfittable
	// value let the most common unfittable spelling through. `STRING -> INT` is
	// the same story one step further in - `String::to_int` is a digit scanner,
	// so `"abc"` answers `0` and `"1e3"` answers `1`.
	//
	// So the question asked here is the one the conversion really answers: does
	// this string, as a whole, spell the number the target type will receive?
	// See `_string_spells_number` for the two engine parsers it is asked of. A
	// string that does not is refused instead of written as a default, and the
	// `#rrggbb` colour string is untouched (`STRING -> COLOR` is a different
	// pair, handled by the conversion relation below).
	// -----------------------------------------------------------------------
	if (p_value.get_type() == Variant::STRING && (p_target_type == Variant::FLOAT || p_target_type == Variant::INT)) {
		double parsed = 0.0;
		if (!_string_spells_number((String)p_value, p_target_type, parsed)) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter '%s' is the string %s and a %s property cannot take it: this engine's own text-to-number "
					"conversion (%s) does not read that string as a number, so type_convert would answer a default (0) "
					"instead of the value you sent. Send a JSON number, or a string in plain decimal spelling - "
					"\"1.5\" or \"-3\" for a float, \"7\" for an integer.",
					p_parameter_name, _value_spelling(p_value), Variant::get_type_name(p_target_type),
					p_target_type == Variant::INT ? "String::to_int" : "String::to_float"));
			return false;
		}
		if (Math::is_nan(parsed) || Math::is_inf(parsed)) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter '%s' is the string %s, which parses to a non-finite number", p_parameter_name, _value_spelling(p_value)));
			return false;
		}
		if (p_target_type == Variant::INT && !(parsed >= -INT64_MAX_AS_DOUBLE && parsed < INT64_MAX_AS_DOUBLE)) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter '%s' is the string %s, which is outside the range of a 64-bit integer", p_parameter_name, _value_spelling(p_value)));
			return false;
		}
	}
	// -----------------------------------------------------------------------
	// TASK-021 A-1 - the boolean half of the string gate.
	//
	// `can_convert(STRING, BOOL)` is true, and the conversion behind it is
	// `Variant::booleanize()` (`!is_zero()`), which answers `true` for **every
	// non-empty string**: `visible: "abc"`, `visible: "false"` and
	// `visible: "0"` all wrote `true` next to a success (measured on the wire by
	// the TASK-021 evidence run). A string that does not spell a boolean is
	// refused instead, and an accepted spelling is written as the boolean it
	// *names* - never as `type_convert` would answer. See
	// `_string_spells_bool` for the four accepted spellings and for the
	// deliberate divergence on `"0"`.
	// -----------------------------------------------------------------------
	if (p_value.get_type() == Variant::STRING && p_target_type == Variant::BOOL) {
		bool spelled = false;
		if (!_string_spells_bool((String)p_value, spelled)) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter '%s' is the string %s and a bool property cannot take it: this engine's own "
					"text-to-bool conversion (Variant::booleanize) answers true for every non-empty string, so "
					"\"false\", \"0\" and \"abc\" would all be written as true instead of the value you sent. Send a "
					"JSON boolean, or one of the spellings \"true\"/\"false\"/\"1\"/\"0\".",
					p_parameter_name, _value_spelling(p_value)));
			return false;
		}
		r_out = spelled;
		return true;
	}
	// -----------------------------------------------------------------------
	// TASK-021 A-5 - the colour half of the string gate.
	//
	// `can_convert(STRING, COLOR)` is true and `Variant::operator Color()`
	// reaches the `Color(const String &)` constructor, which is
	// `html_is_valid(code) ? html(code) : named(code)` - and `Color::named()`
	// without a default is `ERR_FAIL_V_MSG(Color(), ...)`, i.e. **black**, for a
	// string that is neither. `modulate: "notacolor"` therefore wrote
	// `Color(0,0,0,1)` next to a success (measured). The two grammars the
	// constructor really reads are asked directly here - an HTML code
	// (`#rgb`/`#rgba`/`#rrggbb`/`#rrggbbaa`, with `html_is_valid`'s own
	// `#`-optional spelling) or a named colour (`find_named_color` is exactly the
	// lookup `named()` uses, including its `remove_chars(" -_'.")`/uppercase
	// normalisation) - and anything else is refused before the conversion can
	// answer its default. `INT -> COLOR` (`Color::hex`) is a different pair and
	// is untouched.
	// -----------------------------------------------------------------------
	if (p_value.get_type() == Variant::STRING && p_target_type == Variant::COLOR) {
		const String text = (String)p_value;
		if (!Color::html_is_valid(text) && Color::find_named_color(text) == -1) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter '%s' is the string %s, which is neither an HTML colour code nor a named colour, so this "
					"engine's own string-to-colour conversion would answer black (Color(0,0,0,1)) instead of the value "
					"you sent. Send a code like \"#rrggbb\"/\"#rgb\" or a named colour like \"red\"; a JSON object "
					"naming the components ({\"r\":1,\"g\":0,\"b\":0}) is accepted as well.",
					p_parameter_name, _value_spelling(p_value)));
			return false;
		}
	}
	// -----------------------------------------------------------------------
	// TASK-020 D-1, the container half - an array element is a value of its own
	// type and gets the same gate.
	//
	// `coerce_to_property_type([{"x":"abc","y":1}], PACKED_VECTOR2_ARRAY)` used to
	// pass (the engine lists `ARRAY -> PACKED_VECTOR2_ARRAY`) and then reached
	// `Variant::operator Vector2()`, whose `else` branch is the default-constructed
	// `Vector2()`: `(0,0)` next to a success. The element type below is the one
	// fact the target type carries (`ARRAY` itself has no declared element type,
	// so a plain array - and a `Dictionary` property - is left exactly as it was),
	// and every element is pushed through this same function, which means the D-2
	// string rule covers `["abc"]` for a `PackedFloat64Array` too.
	//
	// A dictionary element of a *vector-shaped* packed array is refused here
	// (`DICTIONARY -> VECTOR2` is not a conversion the engine declares); the
	// shaping step that turns such an object into the vector
	// (`MCPTools::shape_vector_from_json`) runs in front of this call on the
	// paths that have it, and the refusal is the honest answer on the paths that
	// do not.
	// -----------------------------------------------------------------------
	if (p_value.get_type() == Variant::ARRAY) {
		const Variant::Type element_type = _container_element_type(p_target_type);
		if (element_type != Variant::NIL) {
			const Array source = p_value;
			for (int i = 0; i < source.size(); i++) {
				const String element_name = vformat("%s[%d]", p_parameter_name, i);
				Variant element;
				if (!_coerce_to_property_type_typed(source[i], element_type, element, r_error, element_name)) {
					return false;
				}
				// TASK-021 A-2: the element's *type* is what the gate above
				// judges; the width of the slot it is finally copied into is a
				// second fact, and an element outside it used to be truncated
				// (300 -> 44 for a `PackedByteArray`, 1e300 -> inf for a
				// `PackedFloat32Array`) while the call reported success.
				if (!_element_fits_container(element, p_target_type, element_name, r_error)) {
					return false;
				}
			}
		}
	}
	if (p_target_type == Variant::NIL || p_value.get_type() == p_target_type) {
		r_out = p_value;
		return true;
	}
	// -----------------------------------------------------------------------
	// TASK-018 section 1 - the silent-wrong-value gate.
	//
	// `VariantUtilityFunctions::type_convert` ignores `Variant::can_convert`, so
	// for a pair the engine does not declare convertible it walks into the
	// `else` branch of `Variant::operator <T>()` and answers the
	// default-constructed `<T>`. Measured for the reported defect:
	//
	//   type_convert(1e20, VECTOR2) == Vector2(0, 0)
	//     `Variant::operator Vector2()` (variant.cpp:1777-1793) has cases for
	//     VECTOR2/VECTOR2I/VECTOR3/VECTOR3I/VECTOR4/VECTOR4I only; everything
	//     else - FLOAT, INT, STRING, DICTIONARY, NIL - returns `Vector2()`.
	//
	// The engine's own relation is the honest test of "can this value fall into
	// that type": `can_convert(FLOAT, VECTOR2)` is false (VECTOR2's valid list is
	// `{VECTOR2I, NIL}`, variant.cpp can_convert), while every conversion the
	// module legitimately relies on is listed there (`FLOAT -> INT`,
	// `INT -> FLOAT`, `STRING -> COLOR`, `INT -> COLOR`, `STRING -> NODE_PATH`,
	// `ARRAY <-> PACKED_*_ARRAY`, `VECTOR2I <-> VECTOR2`, `NIL -> OBJECT`, ...).
	// A pair that is not listed is refused instead of written, so no write path
	// of the module can turn an incompatible value into a default one.
	// -----------------------------------------------------------------------
	if (!Variant::can_convert(p_value.get_type(), p_target_type)) {
		const Variant would_write = VariantUtilityFunctions::type_convert(p_value, p_target_type);
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' cannot be written to a %s property: the value is a %s (%s) and this engine's own "
				"conversion relation (Variant::can_convert) does not list %s -> %s, so type_convert would answer %s "
				"instead of the value you sent. Send the property type's own shape: a JSON object naming its "
				"components for a vector/colour, the property's own JSON type, or a JSON string for a "
				"String-typed property (a \"#rrggbb\" string is accepted for a colour; the "
				"\"Vector2(...)\" string grammar is not available in this build - see TASK-019 P-1).",
				p_parameter_name, Variant::get_type_name(p_target_type),
				Variant::get_type_name(p_value.get_type()), _value_spelling(p_value),
				Variant::get_type_name(p_value.get_type()), Variant::get_type_name(p_target_type),
				_value_spelling(would_write)));
		return false;
	}
	r_out = VariantUtilityFunctions::type_convert(p_value, p_target_type);
	return true;
}

// ---------------------------------------------------------------------------
// GDR-22 / TASK-022 D-4: the public entry point, and the one place the width
// judgement runs for a **scalar member**.
//
// Every property writer of the module comes through here, so this is where "the
// type is right" is followed by "the value survives the member". Before
// TASK-022 the second question was asked only for a packed element and for a
// composite component, which is how `rotation = 1e300` answered `code=0` and
// stored `inf` on all five write paths (including
// `project_set_node_property_across_scenes`, which wrote it to disk).
//
// The slot is resolved here rather than at the call sites on purpose: the default
// is the *member* rule, so a writer that says nothing about storage still gets
// it. A caller that knows its storage is **not** a member of the declared type
// passes the slot explicitly - `project_set_setting` passes `WIDE` because
// `ProjectSettings` stores Variants, and the element half above passes the
// container's element slot through `_element_fits_container`.
//
// The refusal is *after* the conversion, never before it: the caller is told
// about a slot it really could not fill, and everything the pre-TASK-022 gate
// already refused is still refused with its own message.
// ---------------------------------------------------------------------------
static String _member_slot_context(ValueSlot p_slot) {
	switch (p_slot) {
		case ValueSlot::REAL_T: {
			return "the 32-bit float slot this value is copied into (this build's single-precision real_t: a scalar "
				   "member or a Vector2/Vector3/Vector4 component)";
		}
		case ValueSlot::FLOAT32: {
			// GDR-24: the `float`-in-every-build slot. The wording names both
			// members so the caller can tell it from the `real_t` one.
			return "the 32-bit float slot this value is copied into (a Color component, which is a float in every "
				   "build, or a PackedFloat32Array element)";
		}
		case ValueSlot::INT32: {
			return "the 32-bit signed integer slot this value is copied into (a Vector2i/Vector3i component, or a "
				   "PackedInt32Array element)";
		}
		case ValueSlot::UINT8: {
			return "the 8-bit unsigned integer slot this value is copied into (a PackedByteArray element)";
		}
		default: {
			return "the slot this value is copied into";
		}
	}
}

bool coerce_to_property_type(const Variant &p_value, Variant::Type p_target_type, Variant &r_out,
		MCPToolError &r_error, const String &p_parameter_name, ValueSlot p_slot, const String &p_expected_class) {
	// TASK-027 D-8: an Object-valued property has its own three-way grammar
	// (`null` / `res://` string / `{"type","path"}`), so it is answered before
	// the type-conversion machinery below - `can_convert(DICTIONARY, OBJECT)` and
	// `can_convert(STRING, OBJECT)` are both false, which is how the shape the
	// read side answered used to be refused. The width judgement does not apply
	// (an object reference is never narrowed), so this branch returns directly.
	if (false && p_target_type == Variant::OBJECT) { // RED PHASE ONLY (TASK-027)
		return _object_value_from_json(p_value, p_expected_class, p_parameter_name, r_out, r_error);
	}
	Variant converted;
	if (!_coerce_to_property_type_typed(p_value, p_target_type, converted, r_error, p_parameter_name)) {
		return false;
	}
	if (p_slot == ValueSlot::FROM_TARGET_TYPE) {
		p_slot = scalar_member_slot(p_target_type);
	}
	if (!value_fits_slot(converted, p_slot, p_parameter_name, _member_slot_context(p_slot), r_error)) {
		return false;
	}
	r_out = converted;
	return true;
}

Variant::Type property_type_of(const Object *p_object, const StringName &p_name) {
	// `project_write`'s rule verbatim: the type of the value the property
	// currently holds answers immediately.
	const Variant current = p_object->get(p_name);
	if (current.get_type() != Variant::NIL) {
		return current.get_type();
	}
	// `editor_write`'s rule as the fallback: the declared type. Needed for a
	// property whose current value is `null` (a fresh `Resource` reference, an
	// empty Object), where the runtime type carries no information.
	List<PropertyInfo> properties;
	p_object->get_property_list(&properties);
	for (const PropertyInfo &property : properties) {
		if (property.name == p_name) {
			return property.type;
		}
	}
	return Variant::NIL;
}

bool property_is_label(const PropertyInfo &p_property) {
	// TASK-032 D3: the engine's own three label bits, in one place because the
	// editor-side and the game-side property readers must not drift apart (see
	// the declaration in tool_helpers.h for the evidence).
	return (p_property.usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_CATEGORY)) != 0;
}

bool dictionary_has_key_ignoring_case(const Dictionary &p_dict, const String &p_name) {
	const String wanted = p_name.to_lower();
	const Array keys = p_dict.keys();
	for (int i = 0; i < keys.size(); i++) {
		if (((String)keys[i]).to_lower() == wanted) {
			return true;
		}
	}
	return false;
}

String object_property_class_hint(const Object *p_object, const StringName &p_name) {
	// TASK-027 D-8: the *declared* class of an Object-valued property is what
	// makes "does this resource really belong there" answerable before the write.
	// `PropertyInfo::class_name` is the engine's own carrier: it is the
	// `hint_string` for `PROPERTY_HINT_RESOURCE_TYPE` (property_info.h:153-155 -
	// `"Texture2D"` for `Sprite2D.texture`, and a comma separated list with
	// optional `-Excluded` entries for e.g. `CanvasItem.material`) and the
	// declared class for `PROPERTY_HINT_NODE_TYPE` (which the constructor keeps in
	// `class_name`, falling back to `hint_string` when it is empty).
	List<PropertyInfo> properties;
	p_object->get_property_list(&properties);
	for (const PropertyInfo &property : properties) {
		if (property.name != p_name) {
			continue;
		}
		if (property.type != Variant::OBJECT) {
			return String();
		}
		if (property.hint != PROPERTY_HINT_RESOURCE_TYPE && property.hint != PROPERTY_HINT_NODE_TYPE) {
			return String();
		}
		const String declared = String(property.class_name);
		if (!declared.is_empty()) {
			return declared;
		}
		return String(property.hint_string).strip_edges();
	}
	return String();
}

bool assign_resource_to_property(Object *p_object, const StringName &p_property, const Ref<Resource> &p_resource, MCPToolError &r_error) {
	// TASK-040 D-1, the second half of the red/green pair. The red run pinned
	// three shapes of the defect, all of which are answered here:
	//
	//   1. the object does not declare the property at all. `Object::set()` of an
	//      unknown name is a silent no-op and the answer used to be the success
	//      image (`node_path` / `property` / `resource_type`), while the read side
	//      of the same endpoint answered `-32001` for the same name
	//      (RACING-FINDINGS section 4 D-1: `CharacterBody2D
	//      .physics_material_override`). `object_has_property` is the module's one
	//      pre-write question (TASK-014 D-1), and the refusal is its `-32001`
	//      shape, with the property named in both the message and the suggestion.
	//   2. the property exists but is not Object-valued, or its declared class
	//      specification refuses this resource. The engine's own setter fails the
	//      cast and stores `null` next to a success (`CanvasItem.material` with a
	//      `Gradient`), which is the "failure -> default -> report success" family.
	//      Both are answered as `-32602`, the declared classes being named; the
	//      class test is `_object_fits_declared_class` below, the module's one
	//      reading of the engine's own `hint_string` grammar.
	//   3. the write itself did not take. The read-back is the judgement, never
	//      the `set()` call, exactly like the node-property writers.
	if (!object_has_property(p_object, p_property)) {
		r_error = MCPToolError::not_found(
				vformat("Property '%s' on %s", String(p_property), p_object->get_class()),
				vformat("'%s' is not a property of %s. Call editor_get_node_properties without 'properties' to list every "
						"property this node really has",
						String(p_property), p_object->get_class()));
		return false;
	}
	const Variant::Type target_type = property_type_of(p_object, p_property);
	if (target_type != Variant::OBJECT) {
		r_error = MCPToolError::invalid_params(vformat(
				"Property '%s' of %s is declared %s, not an Object-valued property: this tool stores a Resource in a "
				"property that declares one",
				String(p_property), p_object->get_class(), Variant::get_type_name(target_type)));
		return false;
	}
	// An empty specification means "the property declares no class", which
	// accepts everything (the engine's own rule, `_object_fits_declared_class`).
	const String declared = object_property_class_hint(p_object, p_property);
	if (!_object_fits_declared_class(p_resource.ptr(), declared)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Property '%s' of %s declares %s and cannot hold a %s: the engine's own setter would store null next "
				"to a success, so the write is refused instead",
				String(p_property), p_object->get_class(), declared, p_resource->get_class()));
		if (!declared.is_empty()) {
			Dictionary data;
			data["suggestion"] = vformat("'%s' accepts %s; build one with this tool's 'resource_type' argument, or "
										"write the resource into a property that declares a %s",
					String(p_property), declared, p_resource->get_class());
			r_error.data = data;
		}
		return false;
	}

	p_object->set(p_property, Variant((Object *)p_resource.ptr()));
	const Variant stored = p_object->get(p_property);
	Object *stored_object = stored.get_type() == Variant::OBJECT ? (Object *)stored : nullptr;
	if (stored_object != (Object *)p_resource.ptr()) {
		r_error = MCPToolError::tool_state(
				vformat("Writing a %s into property '%s' of %s did not change the property (it holds %s)",
						p_resource->get_class(), String(p_property), p_object->get_class(),
						stored_object != nullptr ? stored_object->get_class() : Variant::get_type_name(stored.get_type())),
				vformat("Read it back with editor_get_node_properties, and check that '%s' is the property this node "
						"really stores its resource in",
						String(p_property)));
		return false;
	}
	return true;
}

// ---------------------------------------------------------------------------
// GDScript source builder (TASK-018 section 3).
//
// Verbatim move of the three helpers TASK-010 wrote inside
// `tools/running_game_script_execution.cpp` (`_split_code_lines`,
// `_space_indent_unit`, `_build_source`). Only `static` and the leading `_` are
// gone, plus the method name is now the exported
// `execute_gdscript_method_name()`; see tool_helpers.h for why the two executors
// must share exactly one definition.
// ---------------------------------------------------------------------------

const char *execute_gdscript_method_name() {
	return "_mcp_execute";
}

// The caller's code, as lines, with `\r\n` and `\r` normalised to `\n`.
static Vector<String> _split_code_lines(const String &p_code) {
	const PackedStringArray raw = p_code.replace("\r\n", "\n").replace("\r", "\n").split("\n");
	Vector<String> lines;
	for (int i = 0; i < raw.size(); i++) {
		lines.push_back(raw[i]);
	}
	return lines;
}

// The smallest positive number of leading spaces of any line, i.e. the space
// indent unit of the body. GDScript forbids mixing tabs and spaces inside one
// block, and an HTTP client has no reason to know the module's convention, so
// spaces are converted to tabs first (the fuller GDScript implementation's rule,
// mcp_game_inspector_service.gd:678-695).
static int _space_indent_unit(const Vector<String> &p_lines) {
	int unit = 0;
	for (int i = 0; i < p_lines.size(); i++) {
		const String &line = p_lines[i];
		int spaces = 0;
		while (spaces < line.length() && line[spaces] == ' ') {
			spaces++;
		}
		if (spaces > 0 && (unit == 0 || spaces < unit)) {
			unit = spaces;
		}
	}
	return unit;
}

// Builds the GDScript source. Three rules, all of them about making the input a
// usable *function body*:
//
//   1. the space indent unit becomes one tab;
//   2. a `func` declaration at column 0 - plus the blank and tab-indented lines
//      that belong to it - is lifted to class level, so the caller can define
//      helpers (`mcp_game_inspector_service.gd:697-740`);
//   3. everything else becomes the body of `_mcp_execute`, indented by one tab.
//
// The generated method is deliberately *untyped* (`func _mcp_execute():`, no
// `-> Variant`): GDScript refuses to compile a typed function with a code path
// that returns nothing ("Not all code paths return a value"), and a body without
// `return` is a perfectly reasonable request (the answer is then `null`).
bool build_execute_gdscript_source(const String &p_code, bool p_tool_script, String &r_source,
		int *r_body_start_line) {
	Vector<String> lines = _split_code_lines(p_code);
	const int unit = _space_indent_unit(lines);
	if (unit > 0) {
		const String space_unit = String(" ").repeat(unit);
		for (int i = 0; i < lines.size(); i++) {
			String line = lines[i];
			String tabs;
			while (line.begins_with(space_unit)) {
				tabs += "\t";
				line = line.substr(unit);
			}
			lines.write[i] = tabs + line;
		}
	}

	String class_part;
	String body_part;
	int i = 0;
	while (i < lines.size()) {
		const String line = lines[i];
		if (!line.begins_with("\t") && !line.begins_with(" ") && line.begins_with("func ")) {
			class_part += line + "\n";
			i++;
			while (i < lines.size()) {
				const String next = lines[i];
				if (next.strip_edges().is_empty() || next.begins_with("\t")) {
					class_part += next + "\n";
					i++;
				} else {
					break;
				}
			}
			continue;
		}
		if (line.strip_edges().is_empty()) {
			body_part += "\n";
		} else {
			body_part += "\t" + line + "\n";
		}
		i++;
	}

	// `@tool` first when the caller is the editor executor: without it
	// `GDScript::can_instantiate()` answers false while the editor is running
	// (`gdscript.cpp`: `valid && (is_tool() || !Engine::is_editor_hint())`), and
	// the script could be compiled but never instantiated.
	String source = p_tool_script ? String("@tool\nextends RefCounted\n") : String("extends RefCounted\n");
	if (!class_part.is_empty()) {
		source += "\n" + class_part;
	}
	source += "\nfunc " + String(execute_gdscript_method_name()) + "():\n";
	// TASK-063 (d): the caller's first body line is the line after this header.
	// Counting the header's own newlines is what keeps the number honest when a
	// caller lifts one or more `func` declarations to class level (each of those
	// lines adds one), so a parser diagnostic can be mapped back to `p_code`
	// without a second copy of the layout rules here.
	if (r_body_start_line != nullptr) {
		*r_body_start_line = source.count("\n") + 1;
	}
	source += body_part.is_empty() ? "\tpass\n" : body_part;
	r_source = source;
	return true;
}

// ---------------------------------------------------------------------------
// TASK-063 (d): the parser diagnostic capture. See the declaration in
// `tool_helpers.h` for the engine basis and for the boundary this deliberately
// stops at (a line, never a column).
// ---------------------------------------------------------------------------

namespace {

// The one function name `GDScript::reload()` reports under. Matching on it is
// what keeps a diagnostic from *anything else* that happens to be emitted while
// the handler is installed (the reload touches `GDScriptCache`, `ResourceLoader`
// and the linter) out of the answer.
const char *const GDSCRIPT_RELOAD_FUNCTION = "GDScript::reload";

// Bounded, like every list this module puts on the wire: a script whose every
// line is broken must not be able to make the refusal unbounded.
const int GDSCRIPT_RELOAD_MAX_MESSAGES = 12;

struct _ReloadCapture {
	GDScriptReloadReport report;
};

void _capture_reload_diagnostic(void *p_userdata, const char *p_function, const char *p_file, int p_line,
		const char *p_error, const char *p_message, bool p_editor_notify, ErrorHandlerType p_type) {
	_ReloadCapture *capture = static_cast<_ReloadCapture *>(p_userdata);
	if (capture == nullptr || p_function == nullptr) {
		return;
	}
	if (strcmp(p_function, GDSCRIPT_RELOAD_FUNCTION) != 0) {
		return;
	}
	// `ERR_HANDLER_SCRIPT` is the type both call sites pass
	// (`modules/gdscript/gdscript.cpp:828/850/864`); a warning emitted by the
	// same function while the handler is installed is not a parse failure.
	if (p_type != ERR_HANDLER_SCRIPT) {
		return;
	}
	// The engine can report several diagnostics for one reload (it walks the
	// parser's error list). Only the first is mapped to a line; the rest are
	// listed so a caller is not told about one broken line while five are broken.
	if (!capture->report.diagnostic_seen) {
		capture->report.diagnostic_seen = true;
		capture->report.diagnostic = String(p_error != nullptr ? p_error : "");
		capture->report.generated_line = p_line;
	}
	if (capture->report.messages.size() < GDSCRIPT_RELOAD_MAX_MESSAGES) {
		if (p_message != nullptr && *p_message != '\0') {
			capture->report.messages.push_back(String(p_message));
		} else if (p_error != nullptr) {
			capture->report.messages.push_back(String(p_error));
		}
	}
}

} // namespace

GDScriptReloadReport reload_gdscript_capturing(Script *p_script, int p_body_start_line) {
	GDScriptReloadReport report;
	if (p_script == nullptr) {
		report.error = ERR_UNAVAILABLE;
		return report;
	}
	_ReloadCapture capture;
	ErrorHandlerList handler;
	handler.errfunc = _capture_reload_diagnostic;
	handler.userdata = &capture;
	handler.next = nullptr;

	// The engine's default printing happens *before* the handler list is walked
	// (`core/error/error_macros.cpp:125-141`), so installing this costs the log
	// nothing; removing it immediately is what keeps the process-wide list
	// exactly as it was found.
	add_error_handler(&handler);
	report.error = p_script->reload();
	remove_error_handler(&handler);

	report.diagnostic_seen = capture.report.diagnostic_seen;
	report.diagnostic = capture.report.diagnostic;
	report.generated_line = capture.report.generated_line;
	report.messages = capture.report.messages;

	// The mapping. `p_body_start_line` is the generated line of the caller's
	// first line; a diagnostic above it belongs to the tool's own wrapper (the
	// `@tool` / `extends RefCounted` prelude, a lifted `func`, or the
	// `func _mcp_execute():` header itself), not to the caller's code - and that
	// is reported as such instead of being blamed on line 1.
	if (report.diagnostic_seen && report.generated_line > 0 && p_body_start_line > 0) {
		const int caller_line = report.generated_line - p_body_start_line + 1;
		if (caller_line >= 1) {
			report.in_caller_code = true;
			report.caller_line = caller_line;
		}
	}
	return report;
}

String gdscript_reload_failure_text(const GDScriptReloadReport &p_report) {
	// No diagnostic at all: the engine still answered an `Error`, and the honest
	// message is the one this tool has always given (`error_string`), with no line
	// to name. This is the path a `reload()` that fails before the parser runs
	// takes (`ERR_ALREADY_IN_USE`, "Cannot reload script while instances exist",
	// modules/gdscript/gdscript.cpp:758).
	if (!p_report.diagnostic_seen) {
		return vformat("Parameter 'code' does not compile: %s",
				VariantUtilityFunctions::error_string(p_report.error));
	}
	// The ordinary case: the engine named a line and it is a line of the caller's
	// own code. The line is 1-based and refers to `code` as it was sent.
	if (p_report.in_caller_code) {
		return vformat("Parameter 'code' does not compile at line %d of 'code': %s",
				p_report.caller_line, p_report.diagnostic);
	}
	// The engine named a line of the generated wrapper (the `@tool` / `extends`
	// prelude, a lifted `func`, or the `func _mcp_execute():` header), so blaming
	// line 1 of the caller's code would be a lie. The generated line is still
	// reported, because that number is what the engine's own log line carries and
	// a caller comparing the two must be able to reconcile them.
	return vformat("Parameter 'code' does not compile: %s (the engine reports generated line %d, which is in "
				   "the tool's own wrapper rather than in 'code')",
			p_report.diagnostic, p_report.generated_line);
}

// ---------------------------------------------------------------------------
// Running-game scene helpers (hoisted by TASK-011 section 2 from
// `tools/running_game_observation.cpp`). Verbatim move: the bodies are the ones
// that file already had, with `static`/`_` removed and the two helpers they call
// moved along with them.
// ---------------------------------------------------------------------------

// The tree's root window as a `Node *`. `SceneTree::get_root()` returns the
// `RequiredResult<Window>` wrapper this fork uses for "null only on error", and
// a plain `Node *root = tree->get_root();` would need two user-defined
// conversions, which C++ does not allow; going through `Window *` costs nothing
// and keeps the two call sites readable.
Node *game_tree_root(SceneTree *p_tree) {
	if (p_tree == nullptr) {
		return nullptr;
	}
	Window *root = p_tree->get_root();
	return root;
}

// Depth-first pre-order search for a node whose *name* is exactly `p_name`.
// Case sensitive, like the reference's `_find_by_name_recursive` (the comment in
// the migration source claims case insensitivity; the code is an exact `==`, and
// the code is what the tool ever did - REPORT-010 records the discrepancy).
static Node *_find_by_name(Node *p_node, const String &p_name) {
	if (String(p_node->get_name()) == p_name) {
		return p_node;
	}
	const int child_count = p_node->get_child_count();
	for (int i = 0; i < child_count; i++) {
		Node *found = _find_by_name(p_node->get_child(i), p_name);
		if (found != nullptr) {
			return found;
		}
	}
	return nullptr;
}

bool game_current_scene(Node *&r_root, SceneTree *&r_tree, MCPToolError &r_error) {
	SceneTree *tree = SceneTree::get_singleton();
	Node *root = tree != nullptr ? tree->get_current_scene() : nullptr;
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return false;
	}
	r_tree = tree;
	r_root = root;
	return true;
}

Node *resolve_game_node(SceneTree *p_tree, Node *p_root, const String &p_node_path) {
	if (p_node_path.is_empty() || p_node_path == ".") {
		return p_root;
	}
	if (p_node_path.begins_with("/root/")) {
		Node *tree_root = game_tree_root(p_tree);
		return tree_root != nullptr ? tree_root->get_node_or_null(NodePath(p_node_path)) : nullptr;
	}
	Node *relative = p_root->get_node_or_null(NodePath(p_node_path));
	if (relative != nullptr) {
		return relative;
	}
	return _find_by_name(p_root, p_node_path);
}

bool game_framebuffer_available() {
	DisplayServer *display_server = DisplayServer::get_singleton();
	if (display_server == nullptr) {
		return false;
	}
	// "headless" is the `DisplayServerHeadless::get_name()` of this fork. The
	// dummy renderer behind it has no texture storage at all, so
	// `get_texture().get_image()` logs `Parameter "t" is null` and returns null
	// (measured, REPORT-011 section 2).
	return display_server->get_name() != "headless";
}

Ref<Image> game_viewport_image(bool p_half_resolution) {
	if (!game_framebuffer_available()) {
		return Ref<Image>();
	}
	SceneTree *tree = SceneTree::get_singleton();
	if (tree == nullptr) {
		return Ref<Image>();
	}
	Window *root = tree->get_root();
	if (root == nullptr) {
		return Ref<Image>();
	}
	Ref<ViewportTexture> texture = root->get_texture();
	Ref<Image> image = texture.is_valid() ? texture->get_image() : Ref<Image>();
	if (image.is_null() || image->is_empty()) {
		return Ref<Image>();
	}
	if (p_half_resolution) {
		// `MAX(1, ..)`: a halved dimension of zero would be an invalid image and
		// `Image::resize()` would fail on it. The reference divides by two with
		// integer arithmetic and does not guard, which is one of the places its
		// behaviour is undefined for a 1 pixel viewport.
		image->resize(MAX(1, image->get_width() / 2), MAX(1, image->get_height() / 2), Image::INTERPOLATE_LANCZOS);
	}
	return image;
}

// ---------------------------------------------------------------------------
// Screen-text observation + assertion comparison (TASK-019). See the header for
// the migration-source defect that makes the first one necessary and for the
// comparison rules the second one keeps.
// ---------------------------------------------------------------------------

// The text of one Control, or an empty String when it has none. The primary
// question is the *property* (`text` is what every text-bearing Control
// registers); `get_text()` is the fallback for a class that exposes the method
// under a different property name (the `AcceptDialog` family registers
// `dialog_text`). A class with neither answers with an empty String and is
// skipped by the caller.
static String _control_text(Node *p_node) {
	if (object_has_property(p_node, SNAME("text"))) {
		const Variant value = p_node->get(SNAME("text"));
		if (value.get_type() == Variant::STRING) {
			return value;
		}
	}
	static const StringName get_text_method = SNAME("get_text");
	if (p_node->has_method(get_text_method)) {
		const Variant value = p_node->call(get_text_method);
		if (value.get_type() == Variant::STRING) {
			return value;
		}
	}
	return String();
}

static void _collect_visible_texts_recursive(Node *p_node, Array &r_out) {
	Control *control = Object::cast_to<Control>(p_node);
	// `is_visible_in_tree()` rather than the local `visible` flag: a label under
	// a hidden parent is not on screen, and this tool's whole question is what is.
	if (control != nullptr && control->is_visible_in_tree()) {
		const String text = _control_text(p_node);
		if (!text.is_empty()) {
			Dictionary entry;
			entry["name"] = String(p_node->get_name());
			entry["type"] = p_node->get_class();
			entry["path"] = String(p_node->get_path());
			entry["text"] = text;
			r_out.push_back(entry);
		}
	}
	const int child_count = p_node->get_child_count();
	for (int i = 0; i < child_count; i++) {
		_collect_visible_texts_recursive(p_node->get_child(i), r_out);
	}
}

Array collect_visible_texts(Node *p_root) {
	Array out;
	if (p_root != nullptr) {
		_collect_visible_texts_recursive(p_root, out);
	}
	return out;
}

static const char *const _ASSERT_OPERATORS[] = {
	"eq", "neq", "gt", "lt", "gte", "lte", "contains", "type_is"
};

const char *const *assert_operator_names() {
	return _ASSERT_OPERATORS;
}

int assert_operator_count() {
	return 8;
}

bool is_valid_assert_operator(const String &p_operator) {
	for (int i = 0; i < assert_operator_count(); i++) {
		if (p_operator == _ASSERT_OPERATORS[i]) {
			return true;
		}
	}
	return false;
}

// See the header: this is the module's own "str(value)", not
// `Variant::operator String()`. The numeric cases are spelled out because
// `JSON::stringify` of a float answers `10.0` while the caller's `str()` answers
// `10`, and `eq` has to treat an int 10 and a float 10.0 as the same value (the
// JSON boundary is where that difference is created, not where it means anything).
String assertion_text_of(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::NIL:
			return "<null>";
		case Variant::BOOL:
			return (bool)p_value ? "true" : "false";
		case Variant::INT:
			return itos((int64_t)p_value);
		case Variant::FLOAT: {
			const double number = (double)p_value;
			// The integral float: print it the way an integer would be printed, so
			// `str(10.0) == str(10)` - the rule `eq`/`neq` depend on.
			if (Math::is_finite(number) && (double)(int64_t)number == number) {
				return itos((int64_t)number);
			}
			return rtos(number);
		}
		case Variant::STRING:
			return (String)p_value;
		case Variant::STRING_NAME:
			return String((StringName)p_value);
		default: {
			// Everything else through the module's own serializer, so the spelling
			// matches what a successful answer carries (a Vector2 is
			// `{"x":3,"y":4}`, not `"(3, 4)"`).
			return JSON::stringify(serialize_variant(p_value), "", false, true);
		}
	}
}

// The migration source's own refusal wording, with the valid names listed.
static void _unknown_operator_error(const String &p_operator, MCPToolError &r_error) {
	String valid;
	for (int i = 0; i < assert_operator_count(); i++) {
		if (i > 0) {
			valid += ", ";
		}
		valid += _ASSERT_OPERATORS[i];
	}
	r_error = MCPToolError::invalid_params(vformat("Invalid operator '%s'. Valid: [%s]", p_operator, valid));
}

// The module's one component mapping lives in `running_game_node_write.cpp`, and
// `assertion_expectation_for` below is its second caller (see the contract note
// in this file's header): a `{"x":3,"y":4}` expectation against a `Vector2`
// property has to go through the very mapping the property writer uses, or the
// two sides can never be equal. The group's header is included rather than
// declaring the function by hand, so the two call sites cannot drift apart.
// There is no circular include (`running_game_node_write.h` does not include
// this file).

Variant assertion_expectation_for(const Variant &p_actual, const Variant &p_expected) {
	if (p_expected.get_type() != Variant::DICTIONARY) {
		return p_expected;
	}
	const Variant mapped = vector_from_dictionary(p_expected, p_actual.get_type());
	if (mapped.get_type() == p_actual.get_type()) {
		return mapped;
	}
	// A Dictionary that does not name the components stays a Dictionary: the
	// comparison then simply fails, which is the honest answer for a shape
	// nothing in the module can interpret.
	return p_expected;
}

bool evaluate_assertion(const String &p_operator, const Variant &p_actual, const Variant &p_expected,
		bool &r_passed, MCPToolError &r_error) {
	if (!is_valid_assert_operator(p_operator)) {
		_unknown_operator_error(p_operator, r_error);
		return false;
	}

	// See the header: an expectation written the way a caller writes one
	// (`{"x":3,"y":4}` for a vector property) is the *same value* as the vector
	// the property holds, and has to be put into that shape before comparing.
	// The normalized value is what `assertion_expectation_for` hands back to the
	// callers, so a response echoes the expectation as it was really compared.
	Variant expected = assertion_expectation_for(p_actual, p_expected);

	// The string spellings of the two values, computed once: `eq`/`neq` and
	// `contains` all need them, and computing them in one place keeps the three
	// operators from drifting apart.
	const String actual_text = assertion_text_of(p_actual);
	const String expected_text = assertion_text_of(expected);

	if (p_operator == "eq") {
		r_passed = actual_text == expected_text || p_actual == expected;
		return true;
	}
	if (p_operator == "neq") {
		r_passed = p_actual != expected && actual_text != expected_text;
		return true;
	}
	if (p_operator == "contains") {
		r_passed = actual_text.contains(expected_text);
		return true;
	}
	if (p_operator == "type_is") {
		const int actual_type = (int)p_actual.get_type();
		if (p_expected.get_type() == Variant::INT) {
			r_passed = actual_type == (int)(int64_t)p_expected;
			return true;
		}
		if (p_expected.get_type() == Variant::FLOAT) {
			r_passed = actual_type == (int)(double)p_expected;
			return true;
		}
		if (p_expected.get_type() == Variant::STRING) {
			// `type_string(typeof(actual)) == str(expected)`, the second half of
			// the migration source's `type_is`. The names are the engine's own
			// (`Variant::get_type_name`), which is what `type_string()` returns -
			// lowercase since Godot 4 (`"int"`, `"float"`, `"String"`, `"Vector2"`).
			r_passed = Variant::get_type_name(p_actual.get_type()) == (String)p_expected;
			return true;
		}
		r_passed = false;
		return true;
	}

	// The four ordering operators. Both operands go through `float()`, exactly
	// like the migration source; a non-finite result is refused rather than
	// turned into a verdict.
	const double actual_number = (double)p_actual;
	const double expected_number = (double)expected;
	if (!Math::is_finite(actual_number) || !Math::is_finite(expected_number)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Operator '%s' compares numbers, but %s of the two operands is not a finite number",
				p_operator, Math::is_finite(actual_number) ? "the expected value" : "the actual value"));
		return false;
	}
	if (p_operator == "gt") {
		r_passed = actual_number > expected_number;
	} else if (p_operator == "lt") {
		r_passed = actual_number < expected_number;
	} else if (p_operator == "gte") {
		r_passed = actual_number >= expected_number;
	} else {
		r_passed = actual_number <= expected_number;
	}
	return true;
}

// ---------------------------------------------------------------------------
// TASK-020 D-3 - one assertion verdict, two entries.
//
// The M4 acceptance measured the same assertion answering two different shapes
// depending on how it was reached: the standalone tools
// (`running_game_assert_node_state` / `running_game_assert_screen_text`) answered
// `passed:false` with `actual`/`expected` (and `visible_elements[]`) but **no
// `reason`**, while the very same assertion inside
// `running_game_run_test_scenario`'s `assert` step carried the full `reason`. A
// caller therefore had to spell the failure out itself on one path and could read
// it on the other.
//
// The correction is not "add a reason in one more place" but "there is one place
// the verdict is built": the two builders below are the *whole* assertion field
// set (status, the compared values and, on a failure, the reason text), and both
// entries merge exactly this object into their own record - the standalone tool
// as its answer, the scenario runner into its per-step envelope (`type`/`step`
// are the runner's own metadata, not assertion fields). A field added here is
// therefore added to both entries at once and the two cannot drift apart; the
// doctest asserts the two entries' failure field sets are equal, and the wire
// evidence compares the two answers of the *same* failing assertion.
// ---------------------------------------------------------------------------

String node_assertion_failure_reason(const String &p_property, const String &p_operator,
		const Variant &p_expected, const Variant &p_actual) {
	return vformat("expected %s %s %s, found %s", p_property, p_operator,
			assertion_text_of(p_expected), assertion_text_of(p_actual));
}

String screen_text_failure_reason(const String &p_text, bool p_partial, int p_visible_text_count) {
	return vformat("screen text %s '%s' was not found in the %d visible text(s) of the control tree",
			p_partial ? "containing" : "equal to", p_text, p_visible_text_count);
}

Dictionary node_state_assertion_fields(const String &p_node_path, const String &p_resolved_node_path,
		const String &p_property, const String &p_operator, const Variant &p_expected_raw,
		const Variant &p_actual, bool p_passed) {
	// The expectation as it was **really compared** (see
	// `assertion_expectation_for`): a `{"x":3,"y":4}` object against a vector
	// property is echoed as the vector, so `expected` and `actual` in one answer
	// cannot look equal while `passed` says false.
	const Variant expected = assertion_expectation_for(p_actual, p_expected_raw);
	Dictionary verdict;
	verdict["assertion"] = "node_state";
	verdict["node_path"] = p_node_path;
	verdict["resolved_node_path"] = p_resolved_node_path;
	verdict["property"] = p_property;
	verdict["operator"] = p_operator;
	verdict["expected"] = serialize_variant(expected);
	verdict["actual"] = serialize_variant(p_actual);
	verdict["passed"] = p_passed;
	if (!p_passed) {
		verdict["reason"] = node_assertion_failure_reason(p_property, p_operator, expected, p_actual);
	}
	return verdict;
}

Dictionary screen_text_assertion_fields(const String &p_text, bool p_partial, bool p_case_sensitive,
		const Array &p_visible_texts, const Array &p_visible_elements, bool p_found) {
	Dictionary verdict;
	verdict["passed"] = p_found;
	verdict["expected_text"] = p_text;
	verdict["partial"] = p_partial;
	verdict["case_sensitive"] = p_case_sensitive;
	// The search space is the **control tree**, not rendered pixels: `--headless`
	// renders nothing, and a pixel-level assertion could not be answered there.
	verdict["source"] = "control_tree";
	verdict["visible_texts"] = p_visible_texts;
	verdict["visible_elements"] = p_visible_elements;
	if (!p_found) {
		verdict["reason"] = screen_text_failure_reason(p_text, p_partial, p_visible_texts.size());
	}
	return verdict;
}

// ---------------------------------------------------------------------------
// Test-result accumulator (TASK-019). See the header for why it exists and why
// it is one definition instead of one copy per B4 group file.
//
// The storage is a function-local `static Array *`. A function-local static is
// deliberately chosen over a namespace-scope one: a namespace-scope `Array`
// would run its constructor during the module's static initialization, before
// `Variant` and `StringName` are usable, and the doctest process (`Main::
// test_entrypoint()` runs before the module initialization levels) would then
// observe a half-constructed container. A pointer that is allocated on first use
// has no such window, and `Array` is reference-counted so the leak is one small
// object for the process' lifetime - the same shape `input_recorder`'s session
// state uses.
// ---------------------------------------------------------------------------

static Array *_test_results_storage() {
	static Array *storage = nullptr;
	if (storage == nullptr) {
		storage = memnew(Array);
	}
	return storage;
}

void record_test_result(const Dictionary &p_result) {
	_test_results_storage()->push_back(p_result);
	// TASK-022 D-6: the persisted list is what the *editor-side*
	// `editor_get_test_report` answers from, so it is refreshed on every update
	// rather than on request - the reader lives in another process and cannot ask
	// for it on demand. A failed persist is deliberately silent here: recording an
	// assertion must never be turned into a tool failure by a read-only user data
	// directory. The reader reports the missing file honestly instead
	// (`report_file_present: false`).
	String persist_reason;
	persist_test_report_to(test_report_bridge_path(), persist_reason);
}

Array get_test_results() {
	return *_test_results_storage();
}

void clear_test_results() {
	_test_results_storage()->clear();
}

Dictionary build_test_report_from(const Array &p_records) {
	int pass_count = 0;
	int fail_count = 0;
	Array details;
	for (int i = 0; i < p_records.size(); i++) {
		const Variant entry = p_records[i];
		if (entry.get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary record = entry;
		// An entry without a boolean `passed` carries no verdict (an input or
		// wait step); it is not an assertion and is not counted either way.
		if (record.get("passed", Variant()).get_type() != Variant::BOOL) {
			continue;
		}
		const bool passed = (bool)record.get("passed", Variant());
		if (passed) {
			pass_count++;
		} else {
			fail_count++;
		}
		details.push_back(record);
	}

	const int total = pass_count + fail_count;
	Dictionary report;
	report["total"] = total;
	report["passed"] = pass_count;
	report["failed"] = fail_count;
	// `N/A` for an empty report, like the migration source (`test_commands.gd:364`);
	// a division by zero would otherwise be an `inf` the caller cannot read.
	if (total > 0) {
		report["pass_rate"] = vformat("%.1f%%", 100.0 * (double)pass_count / (double)total);
	} else {
		report["pass_rate"] = "N/A";
	}
	// `all_passed` is false for an empty report on purpose: "no assertion ran" is
	// not "everything passed" (the migration source has the same `total > 0`
	// guard), and the two are separately visible through `no_results`.
	report["all_passed"] = fail_count == 0 && total > 0;
	report["no_results"] = total == 0;
	report["details"] = details;
	return report;
}

Dictionary build_test_report() {
	return build_test_report_from(get_test_results());
}

// ---------------------------------------------------------------------------
// TASK-022 D-6: the `user://` report bridge. See tool_helpers.h for the defect
// (the editor-scope reader had no possible writer) and for the decision
// (the migration source's own file IPC, no contract change).
// ---------------------------------------------------------------------------

String test_report_bridge_path() {
	return "user://mcp_test_report.json";
}

// `user://` resolves through the OS to a real directory that is not guaranteed to
// exist yet: in the doctest process - and in a freshly launched test project -
// `app_userdata/<name>` may be missing, and a recursive `mkdir` on a
// `user://`-prefixed path only walks the segments *below* the prefix (the engine's
// own logger test makes the same note, tests/core/io/test_logger.cpp:47). The
// absolute directory is therefore created from `OS::get_user_data_dir()`.
static bool _ensure_user_data_directory(String &r_reason) {
	OS *os = OS::get_singleton();
	if (os == nullptr) {
		r_reason = "the OS singleton is not available in this process, so user:// cannot be resolved";
		return false;
	}
	const String directory = os->get_user_data_dir();
	if (directory.is_empty()) {
		r_reason = "user:// does not resolve to a directory in this process";
		return false;
	}
	if (DirAccess::dir_exists_absolute(directory)) {
		return true;
	}
	const Error error = DirAccess::make_dir_recursive_absolute(directory);
	if (error != OK) {
		r_reason = vformat("could not create the user data directory '%s' (%s)", directory,
				VariantUtilityFunctions::error_string(error));
		return false;
	}
	return true;
}

// The `AtomicWriteFunc` of `publish_file_atomically`: the JSON text in full.
static Error _test_report_writer(const String &p_temp_path, void *p_userdata) {
	const String *text = static_cast<const String *>(p_userdata);
	Ref<FileAccess> file = FileAccess::open(p_temp_path, FileAccess::WRITE);
	if (file.is_null()) {
		return ERR_CANT_CREATE;
	}
	file->store_string(*text);
	file->close();
	// `publish_file_atomically` proves the artefact is really there before it
	// replaces the destination, so a short write must be reported as a failure.
	return FileAccess::exists(p_temp_path) ? OK : FAILED;
}

bool persist_test_report_to(const String &p_path, String &r_reason) {
	r_reason = String();
	if (p_path.begins_with("user://")) {
		if (!_ensure_user_data_directory(r_reason)) {
			return false;
		}
	}

	// The envelope is what a reader needs to trust the list: the format version,
	// which process wrote it, when, and the records themselves under one key, so
	// the file can grow a field without breaking an older reader.
	Dictionary envelope;
	envelope["version"] = 1;
	envelope["source_process"] = "game";
	Time *time = Time::get_singleton();
	envelope["written_at_unix"] = time != nullptr ? (int64_t)time->get_unix_time_from_system() : (int64_t)0;
	envelope["results"] = get_test_results();

	const String text = JSON::stringify(serialize_variant(envelope));
	const Error error = publish_file_atomically(p_path, _test_report_writer, (void *)&text);
	if (error != OK) {
		r_reason = vformat("could not publish the test report to '%s' (%s)", p_path,
				VariantUtilityFunctions::error_string(error));
		return false;
	}
	return true;
}

bool load_persisted_test_report_from(const String &p_path, Array &r_records,
		Dictionary &r_meta, bool &r_found, String &r_reason) {
	r_records = Array();
	r_meta = Dictionary();
	r_found = false;
	r_reason = String();

	if (!FileAccess::exists(p_path)) {
		r_reason = vformat("'%s' does not exist", p_path);
		return true;
	}
	const String text = FileAccess::get_file_as_string(p_path);
	if (text.strip_edges().is_empty()) {
		r_reason = vformat("'%s' is empty", p_path);
		return true;
	}
	JSON json;
	if (json.parse(text) != OK) {
		r_reason = vformat("'%s' is not valid JSON: %s", p_path, json.get_error_message());
		return true;
	}
	const Variant data = json.get_data();
	if (data.get_type() != Variant::DICTIONARY) {
		r_reason = vformat("'%s' does not hold a report object", p_path);
		return true;
	}
	const Dictionary envelope = data;
	const Variant results = envelope.get("results", Variant());
	if (results.get_type() != Variant::ARRAY) {
		r_reason = vformat("'%s' holds no 'results' array", p_path);
		return true;
	}
	r_meta = envelope;
	r_records = results;
	r_found = !r_records.is_empty();
	if (!r_found) {
		r_reason = vformat("'%s' holds no recorded results", p_path);
	}
	return true;
}

// ---------------------------------------------------------------------------
// TASK-024 E-6: the editor Output panel view (hoisted from
// `tools/editor_write_scene_editor.cpp`; see the declaration in tool_helpers.h
// for why the panel can only be reached through the scene tree).
// ---------------------------------------------------------------------------

RichTextLabel *find_rich_text_label(Node *p_node) {
	if (p_node == nullptr) {
		return nullptr;
	}
	const int children = p_node->get_child_count();
	for (int i = 0; i < children; i++) {
		Node *child = p_node->get_child(i);
		if (child == nullptr) {
			continue;
		}
		RichTextLabel *label = Object::cast_to<RichTextLabel>(child);
		if (label != nullptr) {
			return label;
		}
		label = find_rich_text_label(child);
		if (label != nullptr) {
			return label;
		}
	}
	return nullptr;
}

} // namespace MCPTools
