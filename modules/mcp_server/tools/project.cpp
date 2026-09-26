/**************************************************************************/
/*  project.cpp                                                           */
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

#include "project.h"

#include "core/config/engine.h"
#include "core/config/project_settings.h"
#include "core/error/error_macros.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

#ifdef TOOLS_ENABLED
#include "editor/editor_interface.h"
#include "scene/gui/control.h"
#endif

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static String _get_project_string(const String &p_key) {
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr || !settings->has_setting(p_key)) {
		return String();
	}
	return (String)settings->get_setting(p_key);
}

// Mirrors `serialize_variant` of the reference implementation: everything that
// is not directly JSON representable is converted into a plain structure so
// that `JSON::stringify` never has to deal with engine-only types.
static Variant _serialize_variant(const Variant &p_value) {
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
				out[key_string] = _serialize_variant(source[key]);
			}
			return out;
		}
		case Variant::ARRAY: {
			const Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(_serialize_variant(source[i]));
			}
			return out;
		}
		case Variant::OBJECT: {
			Object *object = p_value;
			Dictionary out;
			if (object != nullptr) {
				out["type"] = object->get_class();
				out["value"] = object->to_string();
			}
			return out;
		}
		default: {
			return p_value.stringify();
		}
	}
}

static Vector2 _get_screen_size() {
#ifdef TOOLS_ENABLED
	if (Engine::get_singleton() != nullptr && Engine::get_singleton()->is_editor_hint()) {
		EditorInterface *editor = EditorInterface::get_singleton();
		if (editor != nullptr) {
			Control *base_control = editor->get_base_control();
			if (base_control != nullptr) {
				return base_control->get_size();
			}
		}
	}
#endif
	SceneTree *tree = SceneTree::get_singleton();
	if (tree != nullptr && tree->get_root() != nullptr) {
		const Vector2i size = tree->get_root()->get_visible_rect().size;
		return Vector2(size);
	}
	return Vector2();
}

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

// project_get_info -- no arguments.
static Variant _tool_get_project_info(const Dictionary &p_args, String &r_error) {
	// This tool takes no arguments and cannot fail.
	(void)p_args;
	(void)r_error;

	Dictionary result;
	result["project_name"] = _get_project_string("application/config/name");
	result["version"] = _get_project_string("application/config/version");

	const Vector2 screen_size = _get_screen_size();
	Dictionary size;
	size["width"] = (double)screen_size.x;
	size["height"] = (double)screen_size.y;
	result["editor_screen_size"] = size;

	return result;
}

// project_get_settings -- {prefix?: string, include_default?: boolean}.
static Variant _tool_get_project_settings(const Dictionary &p_args, String &r_error) {
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr) {
		r_error = "ProjectSettings is not available";
		return Variant();
	}

	String prefix;
	const Variant prefix_value = p_args.get("prefix", Variant());
	if (prefix_value.get_type() == Variant::STRING) {
		prefix = (String)prefix_value;
	}

	// Accepted for contract compatibility; the reference implementation does
	// not use it either (it always reports the current effective values).
	const Variant include_default_value = p_args.get("include_default", Variant());
	bool include_default = false;
	if (include_default_value.get_type() == Variant::BOOL) {
		include_default = (bool)include_default_value;
	}
	(void)include_default;

	Dictionary out;
	int count = 0;

	List<PropertyInfo> property_list;
	settings->get_property_list(&property_list);
	for (const PropertyInfo &info : property_list) {
		const String name = info.name;
		if (!prefix.is_empty() && !name.begins_with(prefix)) {
			continue;
		}
		const Variant value = settings->has_setting(name) ? settings->get_setting(name) : Variant();
		out[name] = _serialize_variant(value);
		count++;
	}

	Dictionary result;
	result["settings"] = out;
	result["count"] = count;
	return result;
}

void register_project_tools(MCPToolRegistry *p_registry) {
	ERR_FAIL_NULL(p_registry);

	MCPToolDef project_info;
	project_info.name = "project_get_info";
	project_info.channel = "project";
	project_info.verb = "get";
	// `String(const char *)` decodes as Latin-1, so UTF-8 literals must go
	// through String::utf8().
	project_info.description = String::utf8("获取项目信息");
	project_info.input_schema = Dictionary();
	{
		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = Dictionary();
		schema["required"] = Array();
		project_info.input_schema = schema;
	}
	project_info.scope = MCPToolScope::BOTH;
	project_info.handler = _tool_get_project_info;
	p_registry->register_tool(project_info);

	MCPToolDef project_settings;
	project_settings.name = "project_get_settings";
	project_settings.channel = "project";
	project_settings.verb = "get";
	project_settings.description = String::utf8("获取项目设置");
	project_settings.input_schema = Dictionary();
	{
		Dictionary prefix_property;
		prefix_property["type"] = "string";

		Dictionary include_default_property;
		include_default_property["type"] = "boolean";
		include_default_property["default"] = false;

		Dictionary properties;
		properties["prefix"] = prefix_property;
		properties["include_default"] = include_default_property;

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = Array();
		project_settings.input_schema = schema;
	}
	project_settings.scope = MCPToolScope::BOTH;
	project_settings.handler = _tool_get_project_settings;
	p_registry->register_tool(project_settings);
}