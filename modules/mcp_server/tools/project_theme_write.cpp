/**************************************************************************/
/*  project_theme_write.cpp                                               */
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
#include "project_theme_write.h"

#include "running_game_node_write.h"
#include "theme_shared.h"
#include "tool_helpers.h"

#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/object/class_db.h"
#include "scene/resources/style_box_flat.h"

#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/editor_interface.h"
#include "editor/file_system/editor_file_system.h"
#endif

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-036 section 1: the engine reference behind the five tools.
//
//   * `Theme` is a `Resource` with four typed maps (`scene/resources/theme.h`);
//     the setters are `Theme::set_color` (:753), `set_constant` (:850),
//     `set_font_size` (:650) and `set_stylebox` (:402) and the read-back uses
//     the matching `has_*` before any `get_*` (a `get_stylebox`/`get_font_size`
//     without its `has_*` answers a **fallback**, which would turn a dropped
//     write into a reported success).
//   * the item/type names are validated with the engine's own public predicates
//     `Theme::is_valid_item_name` / `is_valid_type_name`
//     (`scene/resources/theme.cpp:180-203`): every `set_*` above returns
//     silently for a name they reject, so the pre-check is the difference
//     between "-32602, nothing written" and "code 0, nothing written".
//   * the two integer members the constant and font-size setters store into are
//     C++ `int`s, so both values go through the module's one slot gate
//     (`value_fits_slot` with `ValueSlot::INT32`, GDR-22) - `set_constant` would
//     otherwise silently truncate a 64-bit integer.
//   * the colour argument is the module's own component mapping
//     (`shape_vector_from_json`, target `COLOR`) followed by
//     `coerce_to_property_type`: the object form `{"r","g","b"[,"a"]}` and the
//     two engine grammars `Color` really reads (`#rrggbb`, named colours) are
//     accepted and anything else is `-32602`. `serialize_variant` answers a
//     `Color` as `{r,g,b,a}`, which is exactly the object form, so a colour this
//     module read can be fed straight back in (GDR-25 section 23.1).
//   * the file is published through `save_theme_atomically` (temp sibling +
//     rename) for the reason every resource writer of this module is
//     (`tool_helpers.h`): a half-written `.tres` is a corrupted theme.
//   * `project_create_theme` refuses to replace an existing file. The contract
//     has no `overwrite` member, and a theme is a whole hand-authored resource;
//     silently replacing it would be the one behaviour a caller cannot opt out
//     of. (The sibling `project_create_shader` overwrites and reports
//     `existed_before`; that difference is deliberate and recorded in
//     REPORT-036.)
// ---------------------------------------------------------------------------

namespace {

// The `.tres`/`.res`/`.theme` guard described in the header.
bool theme_extension_is_supported(const String &p_path) {
	const String extension = p_path.get_extension().to_lower();
	return extension == "tres" || extension == "res" || extension == "theme";
}

// A best-effort editor filesystem notification, the same shape
// `project_shader_write.cpp` uses for its own write: the file is already on disk,
// so this can never fail the call, and a game process answers `false` honestly.
bool notify_editor_of_theme_write() {
#ifdef MCP_EDITOR_TOOLS_ENABLED
	if (!is_editor_process()) {
		return false;
	}
	EditorInterface *editor = EditorInterface::get_singleton();
	EditorFileSystem *filesystem = editor != nullptr ? editor->get_resource_filesystem() : nullptr;
	if (filesystem == nullptr) {
		return false;
	}
	filesystem->scan();
	return true;
#else
	return false;
#endif
}

int64_t published_byte_size(const String &p_path) {
	Error error = OK;
	const Vector<uint8_t> bytes = FileAccess::get_file_as_bytes(p_path, &error);
	return error == OK ? (int64_t)bytes.size() : -1;
}

// Publishes a theme and turns an engine failure into the `-32603` every resource
// writer of this module answers.
bool save_theme_or_fail(const Ref<Theme> &p_theme, const String &p_path, MCPToolError &r_error) {
	const Error error = save_theme_atomically(p_theme, p_path);
	if (error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to save theme '%s': %s", p_path,
				VariantUtilityFunctions::error_string(error)));
		return false;
	}
	return true;
}

// The `bg_color`/`border_color` string member of `project_set_theme_stylebox`:
// absent means "leave the StyleBoxFlat's own default"; present must be a
// non-empty string that spells a colour the engine's `Color` really reads.
bool optional_stylebox_color(const Dictionary &p_args, const String &p_key, const Color &p_default,
		Color &r_out, bool &r_given, MCPToolError &r_error) {
	r_out = p_default;
	r_given = false;
	if (!p_args.has(p_key)) {
		return true;
	}
	const Variant raw = p_args[p_key];
	if (raw.get_type() != Variant::STRING) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' must be a colour string (\"#rrggbb\" or a named colour), got %s", p_key,
				Variant::get_type_name(raw.get_type())));
		return false;
	}
	const String text = ((String)raw).strip_edges();
	if (text.is_empty()) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' must not be empty: omit it to keep the StyleBoxFlat's default colour, or pass a colour "
				"string such as \"#ff8800\"",
				p_key));
		return false;
	}
	Variant converted;
	if (!coerce_to_property_type(Variant(text), Variant::COLOR, converted, r_error, p_key)) {
		return false;
	}
	r_out = converted;
	r_given = true;
	return true;
}

// An optional 32-bit integer member of the style box (`border_width`,
// `corner_radius`). `ValueSlot::INT32` is the width of the `int` member behind
// `StyleBoxFlat::set_border_width_all` / `set_corner_radius_all`.
bool optional_stylebox_int(const Dictionary &p_args, const String &p_key, int &r_out, bool &r_given,
		MCPToolError &r_error) {
	r_given = false;
	if (!p_args.has(p_key)) {
		return true;
	}
	int64_t value = 0;
	if (!optional_int(p_args, p_key, 0, value, r_error)) {
		return false;
	}
	if (!value_fits_slot(Variant(value), ValueSlot::INT32, p_key,
				"the 32-bit int member StyleBoxFlat stores this member in", r_error)) {
		return false;
	}
	r_out = (int)value;
	r_given = true;
	return true;
}

// One sub-member of the created StyleBoxFlat, read back from the stored
// resource. `matches` is false (and the member lands in `stylebox_ignored`) when
// the engine's own reader does not answer what was asked for.
Dictionary stylebox_member_record(const String &p_member, const Variant &p_requested, const Variant &p_stored,
		bool p_matches, const String &p_reason) {
	Dictionary entry;
	entry["requested"] = p_requested;
	entry["stored"] = p_stored;
	if (!p_matches) {
		entry["reason"] = p_reason;
	}
	return entry;
}

} // namespace

namespace MCPTools {

bool require_theme_file_path(const String &p_raw_path, String &r_path, MCPToolError &r_error) {
	if (!normalize_project_path(p_raw_path, r_path, r_error)) {
		return false;
	}
	if (r_path == "res://") {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'path' must name a file, got the project root '%s'", p_raw_path));
		return false;
	}
	if (!theme_extension_is_supported(r_path)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'path' must end in .tres (ResourceFormatSaverText), .res or .theme "
				"(ResourceFormatSaverBinary); got '%s'",
				r_path));
		return false;
	}
	return true;
}

Dictionary create_theme_file(const String &p_raw_path, const String &p_name, MCPToolError &r_error) {
	String path;
	if (!require_theme_file_path(p_raw_path, path, r_error)) {
		return Dictionary();
	}
	if (FileAccess::exists(path)) {
		r_error = MCPToolError::tool_state(vformat("Theme already exists: %s", path),
				"Pick another path, or remove the existing theme first: a Theme is a whole resource and this tool has no "
				"overwrite argument (project_read_files / project_get_filesystem_tree can list what is there)");
		return Dictionary();
	}
	const StringName theme_class("Theme");
	if (!ClassDB::class_exists(theme_class) || !ClassDB::can_instantiate(theme_class)) {
		r_error = MCPToolError::internal("ClassDB cannot instantiate a Theme in this build");
		return Dictionary();
	}
	Object *created = ClassDB::instantiate(theme_class);
	Theme *theme = Object::cast_to<Theme>(created);
	if (theme == nullptr) {
		if (created != nullptr) {
			memdelete(created);
		}
		r_error = MCPToolError::internal("ClassDB::instantiate(\"Theme\") did not answer a Theme");
		return Dictionary();
	}
	const Ref<Theme> theme_ref(theme);
	if (!p_name.is_empty()) {
		// `Resource::set_name` is the engine's own `resource_name` property.
		theme->set_name(p_name);
	}
	if (!save_theme_or_fail(theme_ref, path, r_error)) {
		return Dictionary();
	}
	const bool rescan = notify_editor_of_theme_write();

	Dictionary out;
	out["path"] = path;
	out["name"] = p_name;
	out["resource_name"] = theme->get_name();
	out["type"] = theme->get_class();
	out["created"] = true;
	out["existed_before"] = false;
	out["bytes"] = published_byte_size(path);
	out["editor_rescan_triggered"] = rescan;
	return out;
}

Dictionary theme_set_color(const Ref<Theme> &p_theme, const String &p_save_path, const String &p_node_type,
		const String &p_color_name, const Variant &p_raw_color, MCPToolError &r_error) {
	if (!require_theme_item_and_type("color_name", p_color_name, p_node_type, r_error)) {
		return Dictionary();
	}
	Variant shaped;
	if (!shape_vector_from_json(p_raw_color, Variant::COLOR, "Theme::set_color", "color", shaped, r_error)) {
		return Dictionary();
	}
	Variant converted;
	if (!coerce_to_property_type(shaped, Variant::COLOR, converted, r_error, "color")) {
		return Dictionary();
	}
	const Color requested = converted;
	const StringName name(p_color_name);
	const StringName type(p_node_type);

	const bool had = p_theme->has_color(name, type);
	const Variant old_value = had ? serialize_variant(Variant(p_theme->get_color(name, type))) : Variant();

	p_theme->set_color(name, type, requested);

	const bool present = p_theme->has_color(name, type);
	const Variant stored = present ? serialize_variant(Variant(p_theme->get_color(name, type))) : Variant();
	const bool matches = present && p_theme->get_color(name, type).is_equal_approx(requested);

	if (!save_theme_or_fail(p_theme, p_save_path, r_error)) {
		return Dictionary();
	}
	const bool rescan = notify_editor_of_theme_write();

	Dictionary out = build_theme_write_result(p_save_path, p_node_type, p_color_name, "color_name",
			serialize_variant(Variant(requested)), old_value, stored, present, matches,
			present
					? String("the engine's own reader did not answer the colour that was requested")
					: String("Theme::set_color stored nothing for this item (check the item and theme type names)"));
	out["editor_rescan_triggered"] = rescan;
	return out;
}

Dictionary theme_set_constant(const Ref<Theme> &p_theme, const String &p_save_path, const String &p_node_type,
		const String &p_constant_name, int64_t p_value, MCPToolError &r_error) {
	if (!require_theme_item_and_type("constant_name", p_constant_name, p_node_type, r_error)) {
		return Dictionary();
	}
	if (!value_fits_slot(Variant(p_value), ValueSlot::INT32, "value",
				"the 32-bit int member Theme::set_constant stores a constant in", r_error)) {
		return Dictionary();
	}
	const StringName name(p_constant_name);
	const StringName type(p_node_type);

	const bool had = p_theme->has_constant(name, type);
	const Variant old_value = had ? Variant((int64_t)p_theme->get_constant(name, type)) : Variant();

	p_theme->set_constant(name, type, (int)p_value);

	const bool present = p_theme->has_constant(name, type);
	const Variant stored = present ? Variant((int64_t)p_theme->get_constant(name, type)) : Variant();
	const bool matches = present && (int64_t)stored == p_value;

	if (!save_theme_or_fail(p_theme, p_save_path, r_error)) {
		return Dictionary();
	}
	const bool rescan = notify_editor_of_theme_write();

	Dictionary out = build_theme_write_result(p_save_path, p_node_type, p_constant_name, "constant_name",
			Variant(p_value), old_value, stored, present, matches,
			present
					? String("the engine's own reader did not answer the constant that was requested")
					: String("Theme::set_constant stored nothing for this item (check the item and theme type names)"));
	out["editor_rescan_triggered"] = rescan;
	return out;
}

Dictionary theme_set_font_size(const Ref<Theme> &p_theme, const String &p_save_path, const String &p_node_type,
		const String &p_font_size_name, int64_t p_size, MCPToolError &r_error) {
	if (!require_theme_item_and_type("font_size_name", p_font_size_name, p_node_type, r_error)) {
		return Dictionary();
	}
	if (!value_fits_slot(Variant(p_size), ValueSlot::INT32, "size",
				"the 32-bit int member Theme::set_font_size stores a size in", r_error)) {
		return Dictionary();
	}
	// TASK-037 R2 - a non-positive size is refused instead of written.
	//
	// The writer used to accept it and answer `ignored{requested, stored:null}` +
	// `font_size_readable:false`, which is honest about the *in-memory* read-back
	// but not about the file: `Theme::_get` (`scene/resources/theme.cpp:661-671`)
	// answers the fallback font size for a stored `<= 0`, so `Theme::get_font_size`
	// can never answer the request, and the serializer persists the engine's
	// `default_font_size` (measured: `Button/font_sizes/zero_size = 16` on disk
	// after a `size = 0` write, and `project_get_theme_info` then lists 16 under
	// `font_sizes` with `font_sizes_stored_not_readable` empty - the two tools
	// told the caller different stories about the same entry).
	//
	// The two possible fixes were "let the reader name the fallback" or "let the
	// writer refuse". The refusal is chosen: the size the caller asked for is
	// **not storeable at all**, so the honest answer is a bad-argument error that
	// says why, and nothing is written. "I set it" and "the engine silently
	// stored 16" then cannot both be true, and both tools that read the theme
	// agree because the entry never exists. (Raising the refusal to a positive
	// minimum would be arbitrary; `<= 0` is exactly the range the engine's own
	// reader rejects.)
	if (p_size < 1) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'size' must be a positive font size, got %d: Theme::set_font_size stores it, but "
				"Theme::get_font_size (Theme::_get, scene/resources/theme.cpp:661-671) answers the fallback font "
				"size for any stored size <= 0, and the saved .tres therefore persists that fallback instead of "
				"the value asked for (measured: size = 0 is saved as the fallback 16 and project_get_theme_info "
				"lists 16). Use a size > 0, or an item the engine accepts",
				(int)p_size));
		return Dictionary();
	}
	const StringName name(p_font_size_name);
	const StringName type(p_node_type);

	// The read side of a font size is not `get_font_size` alone: it answers the
	// fallback for a stored `<= 0`, which is why the "is it really readable"
	// question is `has_font_size_no_default` and the "is it really there"
	// question is `has_font_size_nocheck` (`scene/resources/theme.cpp:661-680`).
	const bool had = p_theme->has_font_size_no_default(name, type);
	const Variant old_value = had ? Variant((int64_t)p_theme->get_font_size(name, type)) : Variant();

	p_theme->set_font_size(name, type, (int)p_size);

	const bool present = p_theme->has_font_size_nocheck(name, type);
	const bool readable = p_theme->has_font_size_no_default(name, type);
	Variant stored;
	bool matches = false;
	if (readable) {
		stored = Variant((int64_t)p_theme->get_font_size(name, type));
		matches = (int64_t)stored == p_size;
	}
	String reason;
	if (!present) {
		reason = "Theme::set_font_size stored nothing for this item (check the item and theme type names)";
	} else if (!readable) {
		reason = vformat(
				"the engine stored %d but its own reader (Theme::has_font_size / Theme::get_font_size, "
				"scene/resources/theme.cpp:661-671) only answers a positive size, so it answers the fallback font size "
				"instead; use a size > 0",
				p_size);
	} else {
		reason = "the engine's own reader did not answer the size that was requested";
	}

	if (!save_theme_or_fail(p_theme, p_save_path, r_error)) {
		return Dictionary();
	}
	const bool rescan = notify_editor_of_theme_write();

	Dictionary out = build_theme_write_result(p_save_path, p_node_type, p_font_size_name, "font_size_name",
			Variant(p_size), old_value, stored, present, matches, reason);
	out["font_size_readable"] = readable;
	out["editor_rescan_triggered"] = rescan;
	return out;
}

bool stylebox_arguments_check(const Dictionary &p_args, MCPToolError &r_error) {
	Color color;
	bool given = false;
	// MCP-NARROWING: G24-THEME-STYLEBOX-DEFAULT - the zero-colour default; no caller value reads it.
	if (!optional_stylebox_color(p_args, "bg_color", Color(), color, given, r_error)) {
		return false;
	}
	// MCP-NARROWING: G24-THEME-STYLEBOX-DEFAULT - the zero-colour default; no caller value reads it.
	if (!optional_stylebox_color(p_args, "border_color", Color(), color, given, r_error)) {
		return false;
	}
	int size = 0;
	if (!optional_stylebox_int(p_args, "border_width", size, given, r_error)) {
		return false;
	}
	if (!optional_stylebox_int(p_args, "corner_radius", size, given, r_error)) {
		return false;
	}
	return true;
}

Dictionary theme_set_stylebox(const Ref<Theme> &p_theme, const String &p_save_path, const String &p_node_type,
		const String &p_stylebox_name, const Dictionary &p_args, MCPToolError &r_error) {
	if (!require_theme_item_and_type("stylebox_name", p_stylebox_name, p_node_type, r_error)) {
		return Dictionary();
	}
	if (!stylebox_arguments_check(p_args, r_error)) {
		return Dictionary();
	}

	Ref<StyleBoxFlat> flat;
	flat.instantiate();

	Dictionary stylebox_properties_set;
	Dictionary stylebox_ignored;
	Dictionary requested_record;

	Color bg_color;
	bool bg_given = false;
	if (!optional_stylebox_color(p_args, "bg_color", flat->get_bg_color(), bg_color, bg_given, r_error)) {
		return Dictionary();
	}
	if (bg_given) {
		flat->set_bg_color(bg_color);
		requested_record["bg_color"] = serialize_variant(Variant(bg_color));
	}

	Color border_color;
	bool border_given = false;
	if (!optional_stylebox_color(p_args, "border_color", flat->get_border_color(), border_color, border_given, r_error)) {
		return Dictionary();
	}
	if (border_given) {
		flat->set_border_color(border_color);
		requested_record["border_color"] = serialize_variant(Variant(border_color));
	}

	int border_width = 0;
	bool border_width_given = false;
	if (!optional_stylebox_int(p_args, "border_width", border_width, border_width_given, r_error)) {
		return Dictionary();
	}
	if (border_width_given) {
		flat->set_border_width_all(border_width);
		requested_record["border_width"] = Variant((int64_t)border_width);
	}

	int corner_radius = 0;
	bool corner_radius_given = false;
	if (!optional_stylebox_int(p_args, "corner_radius", corner_radius, corner_radius_given, r_error)) {
		return Dictionary();
	}
	if (corner_radius_given) {
		flat->set_corner_radius_all(corner_radius);
		requested_record["corner_radius"] = Variant((int64_t)corner_radius);
	}

	const StringName name(p_stylebox_name);
	const StringName type(p_node_type);
	const bool had = p_theme->has_stylebox(name, type);
	const Variant old_value = had
			? serialize_variant(Variant((Object *)p_theme->get_stylebox(name, type).ptr()))
			: Variant();

	p_theme->set_stylebox(name, type, flat);

	// Read-back through `has_stylebox` first: `get_stylebox` answers the global
	// fallback style box for an item the engine dropped, which would make a
	// refused write look stored.
	const bool present = p_theme->has_stylebox(name, type);
	Ref<StyleBoxFlat> stored_flat;
	Variant stored_value;
	bool matches = false;
	String ignore_reason;
	if (present) {
		const Ref<StyleBox> stored = p_theme->get_stylebox(name, type);
		stored_value = serialize_variant(Variant((Object *)stored.ptr()));
		stored_flat = Object::cast_to<StyleBoxFlat>(stored.ptr());
		matches = stored_flat.is_valid();
		ignore_reason = "the engine stored a different style box resource than the StyleBoxFlat this tool built";
	} else {
		ignore_reason = "Theme::set_stylebox stored nothing for this item (check the item and theme type names)";
	}

	// Every member this tool set, read back from the **stored** resource.
	if (bg_given) {
		const bool member_matches = stored_flat.is_valid() && stored_flat->get_bg_color().is_equal_approx(bg_color);
		const Variant stored_member = stored_flat.is_valid()
				? serialize_variant(Variant(stored_flat->get_bg_color()))
				: Variant();
		if (member_matches) {
			stylebox_properties_set["bg_color"] = stored_member;
		} else {
			stylebox_ignored["bg_color"] = stylebox_member_record("bg_color",
					serialize_variant(Variant(bg_color)), stored_member, false,
					"the style box the engine stored does not answer this colour");
		}
		matches = matches && member_matches;
	}
	if (border_given) {
		const bool member_matches = stored_flat.is_valid() && stored_flat->get_border_color().is_equal_approx(border_color);
		const Variant stored_member = stored_flat.is_valid()
				? serialize_variant(Variant(stored_flat->get_border_color()))
				: Variant();
		if (member_matches) {
			stylebox_properties_set["border_color"] = stored_member;
		} else {
			stylebox_ignored["border_color"] = stylebox_member_record("border_color",
					serialize_variant(Variant(border_color)), stored_member, false,
					"the style box the engine stored does not answer this colour");
		}
		matches = matches && member_matches;
	}
	if (border_width_given) {
		const bool member_matches = stored_flat.is_valid() && stored_flat->get_border_width_min() == border_width;
		const Variant stored_member = stored_flat.is_valid() ? Variant((int64_t)stored_flat->get_border_width_min()) : Variant();
		if (member_matches) {
			stylebox_properties_set["border_width"] = stored_member;
		} else {
			stylebox_ignored["border_width"] = stylebox_member_record("border_width", Variant((int64_t)border_width),
					stored_member, false, "the style box the engine stored does not answer this border width");
		}
		matches = matches && member_matches;
	}
	if (corner_radius_given) {
		const bool member_matches = stored_flat.is_valid() &&
				stored_flat->get_corner_radius(CORNER_TOP_LEFT) == corner_radius &&
				stored_flat->get_corner_radius(CORNER_TOP_RIGHT) == corner_radius &&
				stored_flat->get_corner_radius(CORNER_BOTTOM_LEFT) == corner_radius &&
				stored_flat->get_corner_radius(CORNER_BOTTOM_RIGHT) == corner_radius;
		const Variant stored_member = stored_flat.is_valid()
				? Variant((int64_t)stored_flat->get_corner_radius(CORNER_TOP_LEFT))
				: Variant();
		if (member_matches) {
			stylebox_properties_set["corner_radius"] = stored_member;
		} else {
			stylebox_ignored["corner_radius"] = stylebox_member_record("corner_radius", Variant((int64_t)corner_radius),
					stored_member, false, "the style box the engine stored does not answer this corner radius");
		}
		matches = matches && member_matches;
	}

	if (!save_theme_or_fail(p_theme, p_save_path, r_error)) {
		return Dictionary();
	}
	const bool rescan = notify_editor_of_theme_write();

	Dictionary out = build_theme_write_result(p_save_path, p_node_type, p_stylebox_name, "stylebox_name",
			requested_record, old_value, stored_value, present, matches, ignore_reason);
	out["stylebox_type"] = stored_flat.is_valid() ? stored_flat->get_class() : String();
	out["stylebox_properties_set"] = stylebox_properties_set;
	out["stylebox_ignored"] = stylebox_ignored;
	out["stylebox"] = stored_flat.is_valid()
			? serialize_variant(Variant((Object *)stored_flat.ptr()))
			: Variant();
	out["editor_rescan_triggered"] = rescan;
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

static Variant _tool_create_theme(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	if (path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'path' must not be empty");
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", String(), name, r_error)) {
		return Variant();
	}
	Dictionary out = create_theme_file(path, name.strip_edges(), r_error);
	return out.is_empty() ? Variant() : Variant(out);
}

static Variant _tool_set_theme_color(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!require_string(p_args, "theme_path", raw_path, r_error)) {
		return Variant();
	}
	String color_name;
	if (!require_string(p_args, "color_name", color_name, r_error)) {
		return Variant();
	}
	if (color_name.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'color_name' must not be empty");
		return Variant();
	}
	const bool has_color = p_args.has("color");
	if (!has_color) {
		r_error = MCPToolError::invalid_params("Missing required parameter: color");
		return Variant();
	}
	String node_type;
	if (!optional_string(p_args, "node_type", "Button", node_type, r_error)) {
		return Variant();
	}
	String path;
	const Ref<Theme> theme = load_theme_resource(raw_path, path, r_error);
	if (theme.is_null()) {
		return Variant();
	}
	Dictionary out = theme_set_color(theme, path, node_type, color_name, p_args["color"], r_error);
	return out.is_empty() ? Variant() : Variant(out);
}

static Variant _tool_set_theme_constant(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!require_string(p_args, "theme_path", raw_path, r_error)) {
		return Variant();
	}
	String constant_name;
	if (!require_string(p_args, "constant_name", constant_name, r_error)) {
		return Variant();
	}
	if (constant_name.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'constant_name' must not be empty");
		return Variant();
	}
	int64_t value = 0;
	if (!require_int(p_args, "value", value, r_error)) {
		return Variant();
	}
	String node_type;
	if (!optional_string(p_args, "node_type", "Button", node_type, r_error)) {
		return Variant();
	}
	String path;
	const Ref<Theme> theme = load_theme_resource(raw_path, path, r_error);
	if (theme.is_null()) {
		return Variant();
	}
	Dictionary out = theme_set_constant(theme, path, node_type, constant_name, value, r_error);
	return out.is_empty() ? Variant() : Variant(out);
}

static Variant _tool_set_theme_font_size(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!require_string(p_args, "theme_path", raw_path, r_error)) {
		return Variant();
	}
	String font_size_name;
	if (!require_string(p_args, "font_size_name", font_size_name, r_error)) {
		return Variant();
	}
	if (font_size_name.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'font_size_name' must not be empty");
		return Variant();
	}
	int64_t size = 0;
	if (!require_int(p_args, "size", size, r_error)) {
		return Variant();
	}
	String node_type;
	if (!optional_string(p_args, "node_type", "Button", node_type, r_error)) {
		return Variant();
	}
	String path;
	const Ref<Theme> theme = load_theme_resource(raw_path, path, r_error);
	if (theme.is_null()) {
		return Variant();
	}
	Dictionary out = theme_set_font_size(theme, path, node_type, font_size_name, size, r_error);
	return out.is_empty() ? Variant() : Variant(out);
}

static Variant _tool_set_theme_stylebox(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!require_string(p_args, "theme_path", raw_path, r_error)) {
		return Variant();
	}
	String stylebox_name;
	if (!require_string(p_args, "stylebox_name", stylebox_name, r_error)) {
		return Variant();
	}
	if (stylebox_name.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'stylebox_name' must not be empty");
		return Variant();
	}
	String node_type;
	if (!optional_string(p_args, "node_type", "Panel", node_type, r_error)) {
		return Variant();
	}
	// The style-box members are validated **before** the theme is loaded, so a
	// mistyped colour or width is the argument error it is rather than being
	// hidden behind "the theme file does not exist".
	if (!stylebox_arguments_check(p_args, r_error)) {
		return Variant();
	}
	String path;
	const Ref<Theme> theme = load_theme_resource(raw_path, path, r_error);
	if (theme.is_null()) {
		return Variant();
	}
	Dictionary out = theme_set_stylebox(theme, path, node_type, stylebox_name, p_args, r_error);
	return out.is_empty() ? Variant() : Variant(out);
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character. The manifest
// (`docs/tool-rename-map.json`) declares `channel = project`, `scope = both`,
// `mutating = true` for all five; the verbs are `create` / `set`.
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_theme_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_theme_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_create_theme", String::utf8(R"desc(创建 Theme 资源)desc"));
		builder.channel("project").verb("create").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"name":{"description":"主题名称","type":"string"},"path":{"description":"保存路径 (res://)","type":"string"}},"required":["path"],"type":"object"})schema"));
		builder.handler(_tool_create_theme).register_into(r_registry);
	}
	{
		ToolBuilder builder("project_set_theme_color", String::utf8(R"desc(设置主题颜色)desc"));
		builder.channel("project").verb("set").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"color":{"description":"包含 r,g,b,a 的字典","type":"object"},"color_name":{"type":"string"},"node_type":{"default":"Button","type":"string"},"theme_path":{"type":"string"}},"required":["theme_path","color_name","color"],"type":"object"})schema"));
		builder.handler(_tool_set_theme_color).register_into(r_registry);
	}
	{
		ToolBuilder builder("project_set_theme_constant", String::utf8(R"desc(设置主题常量)desc"));
		builder.channel("project").verb("set").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"constant_name":{"type":"string"},"node_type":{"default":"Button","type":"string"},"theme_path":{"type":"string"},"value":{"type":"integer"}},"required":["theme_path","constant_name","value"],"type":"object"})schema"));
		builder.handler(_tool_set_theme_constant).register_into(r_registry);
	}
	{
		ToolBuilder builder("project_set_theme_font_size", String::utf8(R"desc(设置主题字体大小)desc"));
		builder.channel("project").verb("set").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"font_size_name":{"type":"string"},"node_type":{"default":"Button","type":"string"},"size":{"type":"integer"},"theme_path":{"type":"string"}},"required":["theme_path","font_size_name","size"],"type":"object"})schema"));
		builder.handler(_tool_set_theme_font_size).register_into(r_registry);
	}
	{
		ToolBuilder builder("project_set_theme_stylebox", String::utf8(R"desc(设置主题样式盒)desc"));
		builder.channel("project").verb("set").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"bg_color":{"type":"string"},"border_color":{"type":"string"},"border_width":{"type":"integer"},"corner_radius":{"type":"integer"},"node_type":{"default":"Panel","type":"string"},"stylebox_name":{"type":"string"},"theme_path":{"type":"string"}},"required":["theme_path","stylebox_name"],"type":"object"})schema"));
		builder.handler(_tool_set_theme_stylebox).register_into(r_registry);
	}
}
