/**************************************************************************/
/*  project_read_template.cpp                                             */
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
#include "project_read_template.h"

#include "tool_builder.h"

#include "core/config/engine.h"
#include "core/config/project_settings.h"
#include "core/error/error_macros.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/variant/variant.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

// Editor-only engine APIs are compiled in only for a tools build (TASK-002
// section 2.2.3). `MCP_EDITOR_TOOLS_ENABLED` is defined in tools/tool_builder.h.
#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/editor_interface.h"
#include "scene/gui/control.h"
#endif

using namespace MCPTools;

// ---------------------------------------------------------------------------
// Shared helpers
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
	// The editor viewport is an editor-only API: in a game build the guarded
	// branch does not exist at all, and in a game process the runtime check keeps
	// EditorInterface out of the path.
#ifdef MCP_EDITOR_TOOLS_ENABLED
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

// `res://a/b` -> `res://a/b/c`; the root keeps exactly one slash.
static String _join_path(const String &p_dir, const String &p_entry) {
	if (p_dir.ends_with("/")) {
		return p_dir + p_entry;
	}
	return p_dir + "/" + p_entry;
}

// Rust's `str::lines()`: splits on '\n', drops a trailing '\r' and does not
// invent a final empty line for a trailing newline. Line numbers of the search
// results have to agree with the reference implementation, so this is spelled
// out instead of using `String::split` directly.
static Vector<String> _split_lines(const String &p_text) {
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

// Rust's `str::trim_matches('*')`.
static String _trim_stars(const String &p_value) {
	int begin = 0;
	int end = p_value.length();
	while (begin < end && p_value[begin] == '*') {
		begin++;
	}
	while (end > begin && p_value[end - 1] == '*') {
		end--;
	}
	return p_value.substr(begin, end - begin);
}

// ---------------------------------------------------------------------------
// project_get_info
// ---------------------------------------------------------------------------

// Takes no arguments and cannot fail (the reference implementation is equally
// total: a missing setting reads as an empty string).
static Variant _tool_get_project_info(const Dictionary &p_args, MCPToolError &r_error) {
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

// ---------------------------------------------------------------------------
// project_get_settings
// ---------------------------------------------------------------------------

static Variant _tool_get_project_settings(const Dictionary &p_args, MCPToolError &r_error) {
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr) {
		r_error = MCPToolError::not_implemented("ProjectSettings",
				"ProjectSettings is only available inside a running engine");
		return Variant();
	}

	String prefix;
	if (!optional_string(p_args, "prefix", String(), prefix, r_error)) {
		return Variant();
	}
	bool include_default = false;
	if (!optional_bool(p_args, "include_default", false, include_default, r_error)) {
		return Variant();
	}
	// Accepted for contract compatibility; the reference implementation does not
	// use it either (it always reports the current effective values).
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

// ---------------------------------------------------------------------------
// project_get_filesystem_tree
// ---------------------------------------------------------------------------

static Dictionary _scan_directory(const String &p_path, int64_t p_max_depth, int64_t p_depth) {
	Dictionary node;
	node["name"] = (p_path == "res://") ? String("res://") : p_path.get_file();
	node["path"] = p_path;
	node["type"] = "directory";

	if (p_max_depth >= 0 && p_depth > p_max_depth) {
		return node;
	}
	Ref<DirAccess> dir = DirAccess::open(p_path);
	if (dir.is_null()) {
		// A nested directory that cannot be read is skipped silently, exactly
		// like the reference; the *root* is validated by the caller.
		return node;
	}

	Array children;
	dir->list_dir_begin();
	while (true) {
		const String entry = dir->get_next();
		if (entry.is_empty()) {
			break;
		}
		if (entry == "." || entry == "..") {
			continue;
		}
		const bool is_dir = dir->current_is_dir();
		const String full = _join_path(p_path, entry);
		if (is_dir) {
			children.push_back(_scan_directory(full, p_max_depth, p_depth + 1));
		} else {
			Dictionary file_node;
			file_node["name"] = entry;
			file_node["path"] = full;
			file_node["type"] = "file";
			children.push_back(file_node);
		}
	}
	dir->list_dir_end();

	if (!children.is_empty()) {
		node["children"] = children;
	}
	return node;
}

static Variant _tool_get_filesystem_tree(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	int64_t max_depth = -1;
	if (!optional_string(p_args, "path", "res://", path, r_error)) {
		return Variant();
	}
	if (!optional_int(p_args, "max_depth", -1, max_depth, r_error)) {
		return Variant();
	}
	String normalized;
	if (!normalize_project_path(path, normalized, r_error)) {
		return Variant();
	}
	// A root directory that does not exist is a tool error (-32001, GDR-14).
	Ref<DirAccess> probe = open_project_dir(normalized, r_error);
	if (probe.is_null()) {
		return Variant();
	}

	Dictionary result;
	result["tree"] = _scan_directory(normalized, max_depth, 0);
	return result;
}

// ---------------------------------------------------------------------------
// project_search_file_names (old `search_files`)
//
// Only the *file name* is matched, case insensitively, with a cap of 200. Note
// that the reference does not skip `addons` or `.godot` here (unlike the content
// search), which is part of why the two tools are not the same tool.
// ---------------------------------------------------------------------------

static const int SEARCH_FILE_NAMES_MAX = 200;

static void _search_file_names_recursive(const String &p_path, const String &p_query, Array &r_matches, int p_max) {
	if (r_matches.size() >= p_max) {
		return;
	}
	Ref<DirAccess> dir = DirAccess::open(p_path);
	if (dir.is_null()) {
		return;
	}
	dir->list_dir_begin();
	while (true) {
		const String entry = dir->get_next();
		if (entry.is_empty()) {
			break;
		}
		if (entry == "." || entry == "..") {
			continue;
		}
		const String full = _join_path(p_path, entry);
		if (dir->current_is_dir()) {
			_search_file_names_recursive(full, p_query, r_matches, p_max);
		} else if (entry.to_lower().contains(p_query.to_lower())) {
			r_matches.push_back(full);
		}
		if (r_matches.size() >= p_max) {
			break;
		}
	}
	dir->list_dir_end();
}

static Variant _tool_search_file_names(const Dictionary &p_args, MCPToolError &r_error) {
	String pattern;
	if (!require_string(p_args, "pattern", pattern, r_error)) {
		return Variant();
	}
	String path;
	if (!optional_string(p_args, "path", "res://", path, r_error)) {
		return Variant();
	}
	String normalized;
	if (!normalize_project_path(path, normalized, r_error)) {
		return Variant();
	}
	Ref<DirAccess> probe = open_project_dir(normalized, r_error);
	if (probe.is_null()) {
		return Variant();
	}

	Array matches;
	_search_file_names_recursive(normalized, pattern, matches, SEARCH_FILE_NAMES_MAX);

	Dictionary result;
	result["matches"] = matches;
	result["count"] = matches.size();
	return result;
}

// ---------------------------------------------------------------------------
// project_search_file_contents (old `search_in_files`)
//
// Per line {file, line, text}, case insensitive, cap 50, skipping the `addons`
// and `.godot` directories and restricted to a fixed text extension whitelist.
// ---------------------------------------------------------------------------

static const int SEARCH_FILE_CONTENTS_MAX = 50;

static const char *SEARCH_CONTENTS_EXTENSIONS[] = {
	"gd", "tscn", "tres", "cfg", "godot", "gdshader", "md", "txt", "json", "yaml", "yml", "xml", "csv", "ini"
};

static bool _is_searchable_text_extension(const String &p_extension) {
	for (const char *extension : SEARCH_CONTENTS_EXTENSIONS) {
		if (p_extension == extension) {
			return true;
		}
	}
	return false;
}

static void _search_file_contents_recursive(const String &p_path, const String &p_query, const String &p_file_pattern, Array &r_matches, int p_max) {
	if (r_matches.size() >= p_max) {
		return;
	}
	Ref<DirAccess> dir = DirAccess::open(p_path);
	if (dir.is_null()) {
		return;
	}
	dir->list_dir_begin();
	while (true) {
		const String entry = dir->get_next();
		if (entry.is_empty()) {
			break;
		}
		if (entry == "." || entry == "..") {
			continue;
		}
		const String full = _join_path(p_path, entry);
		if (dir->current_is_dir()) {
			if (entry != "addons" && entry != ".godot") {
				_search_file_contents_recursive(full, p_query, p_file_pattern, r_matches, p_max);
			}
		} else if (p_file_pattern == "*" || entry.contains(_trim_stars(p_file_pattern))) {
			if (_is_searchable_text_extension(file_extension(entry))) {
				String contents;
				MCPToolError ignored;
				if (read_project_text_file(full, contents, ignored)) {
					const Vector<String> lines = _split_lines(contents);
					for (int i = 0; i < lines.size(); i++) {
						if (r_matches.size() >= p_max) {
							break;
						}
						if (lines[i].to_lower().contains(p_query.to_lower())) {
							Dictionary hit;
							hit["file"] = full;
							hit["line"] = i + 1;
							hit["text"] = lines[i].strip_edges();
							r_matches.push_back(hit);
						}
					}
				}
			}
		}
		if (r_matches.size() >= p_max) {
			break;
		}
	}
	dir->list_dir_end();
}

static Variant _tool_search_file_contents(const Dictionary &p_args, MCPToolError &r_error) {
	String pattern;
	if (!require_string(p_args, "pattern", pattern, r_error)) {
		return Variant();
	}
	String file_pattern;
	if (!optional_string(p_args, "file_pattern", "*", file_pattern, r_error)) {
		return Variant();
	}
	String path;
	if (!optional_string(p_args, "path", "res://", path, r_error)) {
		return Variant();
	}
	String normalized;
	if (!normalize_project_path(path, normalized, r_error)) {
		return Variant();
	}
	Ref<DirAccess> probe = open_project_dir(normalized, r_error);
	if (probe.is_null()) {
		return Variant();
	}

	Array matches;
	_search_file_contents_recursive(normalized, pattern, file_pattern, matches, SEARCH_FILE_CONTENTS_MAX);

	Dictionary result;
	result["matches"] = matches;
	result["count"] = matches.size();
	// The reference returns the query back as well; the contract keeps it.
	result["query"] = pattern;
	return result;
}

// ---------------------------------------------------------------------------
// project_find_files_referencing_symbol (old `find_node_references`)
//
// Aggregated per file {file, lines[]}, case SENSITIVE, cap 100, at most 5 line
// numbers per file, hidden entries and `addons` skipped, and only the four
// reference-bearing extensions scanned. This is the de-merged twin of
// project_search_file_contents (GDR-17): the two must never be collapsed back
// into one implementation.
// ---------------------------------------------------------------------------

static const int FIND_REFERENCES_MAX = 100;
static const int FIND_REFERENCES_MAX_LINES_PER_FILE = 5;

static bool _has_reference_extension(const String &p_file_name) {
	// Suffix test, exactly like the reference (case sensitive).
	return p_file_name.ends_with(".tscn") || p_file_name.ends_with(".gd") ||
			p_file_name.ends_with(".tres") || p_file_name.ends_with(".gdshader");
}

static void _scan_for_pattern_recursive(const String &p_path, const String &p_pattern, Array &r_matches, int p_max) {
	if (r_matches.size() >= p_max) {
		return;
	}
	Ref<DirAccess> dir = DirAccess::open(p_path);
	if (dir.is_null()) {
		return;
	}
	dir->list_dir_begin();
	while (true) {
		const String entry = dir->get_next();
		if (entry.is_empty()) {
			break;
		}
		if (r_matches.size() >= p_max) {
			break;
		}
		// Covers "." and ".." as well as any hidden entry.
		if (entry.begins_with(".")) {
			continue;
		}
		const String full = _join_path(p_path, entry);
		if (dir->current_is_dir()) {
			if (entry == "addons") {
				continue;
			}
			_scan_for_pattern_recursive(full, p_pattern, r_matches, p_max);
		} else if (_has_reference_extension(entry)) {
			String contents;
			MCPToolError ignored;
			if (read_project_text_file(full, contents, ignored) && contents.contains(p_pattern)) {
				Array lines;
				const Vector<String> split = _split_lines(contents);
				for (int i = 0; i < split.size(); i++) {
					if (lines.size() >= FIND_REFERENCES_MAX_LINES_PER_FILE) {
						break;
					}
					if (split[i].contains(p_pattern)) {
						lines.push_back(i + 1);
					}
				}
				Dictionary hit;
				hit["file"] = full;
				hit["lines"] = lines;
				r_matches.push_back(hit);
			}
		}
	}
	dir->list_dir_end();
}

static Variant _tool_find_files_referencing_symbol(const Dictionary &p_args, MCPToolError &r_error) {
	String pattern;
	if (!require_string(p_args, "pattern", pattern, r_error)) {
		return Variant();
	}

	// The contract exposes no `path`: the scan always starts at the project
	// root, so a missing root is the only bottom layer failure this tool has.
	Ref<DirAccess> probe = open_project_dir("res://", r_error);
	if (probe.is_null()) {
		return Variant();
	}

	Array matches;
	_scan_for_pattern_recursive("res://", pattern, matches, FIND_REFERENCES_MAX);

	Dictionary result;
	result["pattern"] = pattern;
	result["matches"] = matches;
	result["count"] = matches.size();
	return result;
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

void register_project_read_template_tools(MCPToolRegistry &r_registry) {
	// Order matters: `tools/list` is returned in registration order, and the two
	// migrated M1 tools must keep their exact positions (regression guard).
	{
		ToolBuilder builder("project_get_info", String::utf8("获取项目信息"));
		builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(empty_object_schema()).handler(_tool_get_project_info);
		builder.register_into(r_registry);
	}

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

		ToolBuilder builder("project_get_settings", String::utf8("获取项目设置"));
		builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_get_project_settings);
		builder.register_into(r_registry);
	}

	{
		Dictionary path_property;
		path_property["type"] = "string";
		path_property["default"] = "res://";

		Dictionary max_depth_property;
		max_depth_property["type"] = "integer";
		max_depth_property["default"] = -1;

		Dictionary properties;
		properties["path"] = path_property;
		properties["max_depth"] = max_depth_property;

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = Array();

		ToolBuilder builder("project_get_filesystem_tree", String::utf8("获取文件系统树状结构"));
		builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_get_filesystem_tree);
		builder.register_into(r_registry);
	}

	{
		Dictionary pattern_property;
		pattern_property["type"] = "string";

		Dictionary path_property;
		path_property["type"] = "string";
		path_property["default"] = "res://";

		Dictionary properties;
		properties["pattern"] = pattern_property;
		properties["path"] = path_property;

		Array required;
		required.push_back("pattern");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		ToolBuilder builder("project_search_file_names",
				String::utf8("搜索文件 判别点：只匹配文件名子串（大小写不敏感、上限 200），不读文件内容、不返回行号；要搜索文件内容请用 project_search_file_contents。"));
		builder.channel("project").verb("search").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_search_file_names);
		builder.register_into(r_registry);
	}

	{
		Dictionary pattern_property;
		pattern_property["type"] = "string";

		Dictionary file_pattern_property;
		file_pattern_property["type"] = "string";
		file_pattern_property["default"] = "*";

		Dictionary path_property;
		path_property["type"] = "string";
		path_property["default"] = "res://";

		Dictionary properties;
		properties["pattern"] = pattern_property;
		properties["file_pattern"] = file_pattern_property;
		properties["path"] = path_property;

		Array required;
		required.push_back("pattern");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		ToolBuilder builder("project_search_file_contents",
				String::utf8("在文件内容中搜索文本 判别点：逐行返回 {file,line,text}（大小写不敏感、上限 50，跳过 addons 与 .godot 目录）；要按文件聚合的 {file,lines[]}（大小写敏感、上限 100）请用 project_find_files_referencing_symbol。"));
		builder.channel("project").verb("search").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_search_file_contents);
		builder.register_into(r_registry);
	}

	{
		Dictionary pattern_property;
		pattern_property["type"] = "string";
		pattern_property["description"] = String::utf8("要搜索的模式");

		Dictionary properties;
		properties["pattern"] = pattern_property;

		Array required;
		required.push_back("pattern");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		ToolBuilder builder("project_find_files_referencing_symbol",
				String::utf8("在项目文件中搜索指定模式的引用 判别点：按文件聚合返回 {file,lines[]}（每文件最多 5 行、大小写敏感、上限 100，跳过隐藏文件与 addons，只扫 .tscn/.gd/.tres/.gdshader）；要逐行 {file,line,text}（大小写不敏感、上限 50）请用 project_search_file_contents。"));
		builder.channel("project").verb("find").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_find_files_referencing_symbol);
		builder.register_into(r_registry);
	}
}
