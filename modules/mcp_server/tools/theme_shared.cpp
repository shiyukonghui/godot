/**************************************************************************/
/*  theme_shared.cpp                                                      */
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
#include "theme_shared.h"

#include "tool_helpers.h"

#include "core/io/resource_loader.h"
#include "core/io/resource_saver.h"

using namespace MCPTools;

namespace {

// The `AtomicWriteFunc` of `publish_file_atomically` for a Theme: the whole
// resource is serialised into the caller's temporary sibling. `p_userdata` is
// the `Ref<Theme>` the wrapper below keeps alive across the call.
Error _theme_save_writer(const String &p_temp_path, void *p_userdata) {
	const Ref<Theme> *theme = static_cast<const Ref<Theme> *>(p_userdata);
	return ResourceSaver::save(*theme, p_temp_path);
}

// One `{<theme_type>: {<item>: <value>}}` map of a typed theme map, with the
// engine's `has_*` predicate deciding whether a value is really stored (a
// `get_*` fallback is never reported as stored state).
Dictionary _items_of(const Ref<Theme> &p_theme, int p_kind) {
	Dictionary out;
	List<StringName> types;
	p_theme->get_type_list(&types);
	for (const StringName &type : types) {
		List<StringName> names;
		Dictionary entries;
		switch (p_kind) {
			case 0:
				p_theme->get_color_list(type, &names);
				break;
			case 1:
				p_theme->get_constant_list(type, &names);
				break;
			case 2:
				p_theme->get_font_size_list(type, &names);
				break;
			default:
				p_theme->get_stylebox_list(type, &names);
				break;
		}
		for (const StringName &name : names) {
			switch (p_kind) {
				case 0:
					if (p_theme->has_color(name, type)) {
						entries[String(name)] = serialize_variant(Variant(p_theme->get_color(name, type)));
					}
					break;
				case 1:
					if (p_theme->has_constant(name, type)) {
						entries[String(name)] = p_theme->get_constant(name, type);
					}
					break;
				case 2:
					// `has_font_size_no_default` is the engine's "the map holds
					// a positive size" test; `get_font_size` would otherwise
					// answer the fallback font size for a stored `<= 0` key.
					if (p_theme->has_font_size_no_default(name, type)) {
						entries[String(name)] = p_theme->get_font_size(name, type);
					}
					break;
				default:
					if (p_theme->has_stylebox(name, type)) {
						entries[String(name)] = serialize_variant(Variant((Object *)p_theme->get_stylebox(name, type).ptr()));
					}
					break;
			}
		}
		if (!entries.is_empty()) {
			out[String(type)] = entries;
		}
	}
	return out;
}

// `{<theme_type>: [<item>...]}` for the two resource maps no tool of this batch
// can write; the names are answered so the caller can address them with the
// engine's own `theme/<type>/<map>/<name>` property path if it needs to.
Dictionary _resource_item_names(const Ref<Theme> &p_theme, bool p_fonts) {
	Dictionary out;
	List<StringName> types;
	p_theme->get_type_list(&types);
	for (const StringName &type : types) {
		List<StringName> names;
		if (p_fonts) {
			p_theme->get_font_list(type, &names);
		} else {
			p_theme->get_icon_list(type, &names);
		}
		Array array;
		for (const StringName &name : names) {
			array.push_back(String(name));
		}
		if (!array.is_empty()) {
			out[String(type)] = array;
		}
	}
	return out;
}

} // namespace

namespace MCPTools {

Ref<Theme> load_theme_resource(const String &p_input, String &r_path, MCPToolError &r_error) {
	if (!normalize_project_path(p_input, r_path, r_error)) {
		return Ref<Theme>();
	}
	if (r_path == "res://") {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'theme_path' must name a file, got the project root '%s'", p_input));
		return Ref<Theme>();
	}
	const Ref<Resource> loaded = ResourceLoader::load(r_path);
	if (loaded.is_null()) {
		r_error = MCPToolError::not_found(vformat("Theme resource '%s'", r_path),
				"Theme resources are loaded with ResourceLoader::load; name a .tres/.res Theme in this project "
				"(project_get_filesystem_tree lists the files of the project, project_create_theme creates one)");
		return Ref<Theme>();
	}
	Theme *theme = Object::cast_to<Theme>(loaded.ptr());
	if (theme == nullptr) {
		r_error = MCPToolError::invalid_params(vformat("'%s' holds a %s, not a Theme", r_path,
				loaded->get_class()));
		return Ref<Theme>();
	}
	return Ref<Theme>(theme);
}

Error save_theme_atomically(const Ref<Theme> &p_theme, const String &p_path) {
	// The wrapper keeps a second reference to the theme alive for the whole
	// publish: `publish_file_atomically` may retry the writer, and the engine's
	// `ResourceSaver::save` only borrows the pointer.
	Ref<Theme> held = p_theme;
	return publish_file_atomically(p_path, _theme_save_writer, &held);
}

bool require_theme_item_and_type(const String &p_parameter_name, const String &p_item_name,
		const String &p_node_type, MCPToolError &r_error) {
	// The engine's own predicates, called directly: `Theme::set_*` returns
	// silently (`ERR_FAIL_COND_MSG`) for a name these reject, so pre-checking is
	// the difference between "-32602, nothing was written" and "error code 0,
	// nothing was written".
	if (!Theme::is_valid_item_name(p_item_name)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' must be a non-empty ASCII identifier: Theme::is_valid_item_name "
				"(scene/resources/theme.cpp:191-203) rejects '%s', and Theme::set_color/set_constant/set_font_size/"
				"set_stylebox return without storing anything for a name it rejects",
				p_parameter_name, p_item_name));
		return false;
	}
	if (!Theme::is_valid_type_name(p_node_type)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'node_type' must be an ASCII identifier (the theme type to write into, e.g. Button, Panel, "
				"Label): Theme::is_valid_type_name (scene/resources/theme.cpp:180-189) rejects '%s'",
				p_node_type));
		return false;
	}
	return true;
}

Dictionary build_theme_write_result(const String &p_theme_path, const String &p_node_type,
		const String &p_item_name, const String &p_parameter_name, const Variant &p_requested,
		const Variant &p_old, const Variant &p_stored, bool p_present, bool p_matches,
		const String &p_ignore_reason) {
	Array properties_set;
	Dictionary ignored;
	Dictionary changed;

	Dictionary entry;
	entry["old"] = p_old;
	entry["new"] = p_stored;
	changed[p_item_name] = entry;

	if (p_present && p_matches) {
		properties_set.push_back(p_item_name);
	} else {
		Dictionary miss;
		miss["requested"] = p_requested;
		miss["stored"] = p_present ? p_stored : Variant();
		miss["reason"] = p_ignore_reason;
		ignored[p_item_name] = miss;
	}

	Dictionary out;
	out["theme_path"] = p_theme_path;
	out["node_type"] = p_node_type;
	out[p_parameter_name] = p_item_name;
	out["changed"] = changed;
	out["properties_set"] = properties_set;
	out["ignored"] = ignored;
	out["saved"] = true;
	return out;
}

Dictionary theme_info_of(const Ref<Theme> &p_theme, const String &p_path) {
	List<StringName> types;
	p_theme->get_type_list(&types);
	Array type_list;
	for (const StringName &type : types) {
		type_list.push_back(String(type));
	}

	// Keys present in `font_size_map` that the engine's own read API cannot
	// answer (`has_font_size`/`get_font_size` require a positive size,
	// `scene/resources/theme.cpp:661-671`). They are named so "the theme holds
	// an entry that reads back as the fallback" is visible instead of silently
	// missing from `font_sizes`.
	Array unreadable_font_sizes;
	for (const StringName &type : types) {
		List<StringName> names;
		p_theme->get_font_size_list(type, &names);
		for (const StringName &name : names) {
			if (p_theme->has_font_size_nocheck(name, type) && !p_theme->has_font_size_no_default(name, type)) {
				unreadable_font_sizes.push_back(String(name));
			}
		}
	}

	const Dictionary fonts = _resource_item_names(p_theme, true);
	const Dictionary icons = _resource_item_names(p_theme, false);
	int font_count = 0;
	const Array font_types = fonts.keys();
	for (int i = 0; i < font_types.size(); i++) {
		font_count += ((Array)fonts[font_types[i]]).size();
	}
	int icon_count = 0;
	const Array icon_types = icons.keys();
	for (int i = 0; i < icon_types.size(); i++) {
		icon_count += ((Array)icons[icon_types[i]]).size();
	}

	Dictionary out;
	out["path"] = p_path;
	out["type_list"] = type_list;
	out["type_count"] = type_list.size();
	out["colors"] = _items_of(p_theme, 0);
	out["constants"] = _items_of(p_theme, 1);
	out["font_sizes"] = _items_of(p_theme, 2);
	out["styleboxes"] = _items_of(p_theme, 3);
	out["fonts"] = fonts;
	out["icons"] = icons;
	out["font_count"] = font_count;
	out["icon_count"] = icon_count;
	out["font_sizes_stored_not_readable"] = unreadable_font_sizes;
	return out;
}

} // namespace MCPTools
