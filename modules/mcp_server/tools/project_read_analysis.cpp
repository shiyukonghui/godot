/**************************************************************************/
/*  project_read_analysis.cpp                                             */
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
#include "project_read_analysis.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/config/engine.h"
#include "core/config/project_settings.h"
#include "core/error/error_macros.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/resource_loader.h"
#include "core/io/resource_uid.h"
#include "core/io/resource_uid.h"
#include "core/object/object.h"
#include "core/object/script_language.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/resources/packed_scene.h"

// NOTE on the editor guard (TASK-002 section 2.2.3): this group's only
// editor-only capability is the run-time half of the "analyse the edited scene"
// fallback, which is wrapped in `MCP_EDITOR_TOOLS_ENABLED` /
// `is_editor_process()` at its call site. The scene lookup itself goes through
// `SceneTree`, whose `edited_scene_root` the editor keeps in sync
// (`EditorNode::set_edited_scene_root`, `EditorNode::_set_current_scene_nocheck`),
// instead of `EditorInterface::get_edited_scene_root()`: that one dereferences
// `EditorNode::get_singleton()` without a null check, so it is a null
// dereference in a process where the editor interface exists but the editor node
// does not - exactly the doctest process, whose `Main::test_setup()` calls
// `register_editor_types()` but never starts `EditorNode`.

using namespace MCPTools;

// ---------------------------------------------------------------------------
// Group-specific helpers
//
// The four generic helpers this group needs - `join_path`, `split_lines`,
// `serialize_variant` and `collect_files_by_extension` - are shared definitions
// in tools/tool_helpers.h since TASK-005 section 1; this group used to carry its
// own file-private copies. What stays here is what is specific to the analysis
// semantics: the `path="..."` attribute reader and the extension tables of the
// reference's per-tool walks.
// ---------------------------------------------------------------------------

// The `path="..."` value of a tag line, or an empty string when there is none.
// Rust: `line.find("path=\"")` followed by the next `"`.
static String _path_attribute(const String &p_line) {
	const int marker = p_line.find("path=\"");
	if (marker < 0) {
		return String();
	}
	const int start = marker + 6;
	const int end = p_line.substr(start).find_char('"');
	if (end < 0) {
		return String();
	}
	return p_line.substr(start, end);
}

// Turns a static extension table into the Vector the walker takes.
template <int N>
static Vector<String> _extension_set(const char *const (&p_extensions)[N]) {
	Vector<String> out;
	for (int i = 0; i < N; i++) {
		out.push_back(String(p_extensions[i]));
	}
	return out;
}

// `resource_exts` of the reference's `find_unused_resources` (analysis.rs:340).
static const Vector<String> &_resource_extensions() {
	static const char *const EXTENSIONS[] = {
		"tres", "tscn", "png", "jpg", "jpeg", "svg",
		"wav", "ogg", "mp3", "ttf", "otf", "gdshader", "material",
		"theme", "stylebox", "font", "anim"
	};
	static const Vector<String> extensions = _extension_set(EXTENSIONS);
	return extensions;
}

// `ref_exts` / `search_exts` of the reference: the extensions whose text is
// scanned for references.
static const Vector<String> &_reference_extensions() {
	static const char *const EXTENSIONS[] = { "tscn", "gd", "tres", "cfg", "godot" };
	static const Vector<String> extensions = _extension_set(EXTENSIONS);
	return extensions;
}

// The scenes of `detect_circular_dependencies` (`&["tscn"]` in the reference).
static const Vector<String> &_scene_extensions() {
	static const char *const EXTENSIONS[] = { "tscn" };
	static const Vector<String> extensions = _extension_set(EXTENSIONS);
	return extensions;
}

// ---------------------------------------------------------------------------
// project_get_statistics (old `get_project_statistics`)
//
// analysis.rs:562. One recursive walk that counts every file, the
// per-extension histogram, the number of lines in the `.gd` files, the
// scene/resource totals, the autoloads from ProjectSettings and the plugins
// found in `res://addons`.
// ---------------------------------------------------------------------------

struct StatisticsAccumulator {
	HashMap<String, int64_t> file_counts;
	// Insertion order of `file_counts`, so the returned dictionary does not
	// depend on the hash map's iteration order.
	Vector<String> extension_order;
	int64_t total_files = 0;
	int64_t script_lines = 0;
	int64_t scene_count = 0;
	int64_t resource_count = 0;
};

static void _collect_statistics_recursive(const String &p_path, bool p_include_addons, StatisticsAccumulator &r_acc) {
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
		// Covers "." , ".." and every hidden file or directory (including
		// `.godot`), exactly like the reference.
		if (entry.begins_with(".")) {
			continue;
		}
		const String full = join_path(p_path, entry);
		if (dir->current_is_dir()) {
			if (entry == "addons" && !p_include_addons) {
				continue;
			}
			_collect_statistics_recursive(full, p_include_addons, r_acc);
			continue;
		}

		const int dot = entry.rfind_char('.');
		if (dot >= 0) {
			const String extension = entry.substr(dot + 1).to_lower();
			if (r_acc.file_counts.has(extension)) {
				r_acc.file_counts[extension] += 1;
			} else {
				r_acc.file_counts[extension] = 1;
				r_acc.extension_order.push_back(extension);
			}
			if (extension == "gd") {
				String contents;
				MCPToolError ignored;
				if (read_project_text_file(full, contents, ignored) && !contents.is_empty()) {
					r_acc.script_lines += split_lines(contents).size();
				}
			} else if (extension == "tscn") {
				r_acc.scene_count++;
			} else if (extension == "tres" || extension == "material" || extension == "theme" || extension == "stylebox" || extension == "font") {
				r_acc.resource_count++;
			}
		}
		r_acc.total_files++;
	}
	dir->list_dir_end();
}

// The reference reads the autoloads with a GDScript Expression over
// `ProjectSettings.get_property_list()`; the property list is the same source
// and is read directly here.
static Dictionary _collect_autoloads() {
	Dictionary autoloads;
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr) {
		return autoloads;
	}
	List<PropertyInfo> properties;
	settings->get_property_list(&properties);
	for (const PropertyInfo &info : properties) {
		const String name = info.name;
		if (!name.begins_with("autoload/")) {
			continue;
		}
		autoloads[name.substr(9)] = settings->has_setting(name) ? (String)settings->get_setting(name) : String();
	}
	return autoloads;
}

// `res://addons/<dir>/plugin.cfg` is a plugin; `editor_plugins/enabled` says
// whether the editor has it switched on.
static Array _collect_plugins() {
	Array plugins;
	Ref<DirAccess> plugin_dir = DirAccess::open("res://addons");
	if (plugin_dir.is_null()) {
		return plugins;
	}
	ProjectSettings *settings = ProjectSettings::get_singleton();

	plugin_dir->list_dir_begin();
	while (true) {
		const String name = plugin_dir->get_next();
		if (name.is_empty()) {
			break;
		}
		if (name.begins_with(".") || !plugin_dir->current_is_dir()) {
			continue;
		}
		const String config_path = "res://addons/" + name + "/plugin.cfg";
		if (!FileAccess::exists(config_path)) {
			continue;
		}
		bool enabled = false;
		if (settings != nullptr && settings->has_setting("editor_plugins/enabled")) {
			const Variant enabled_list = settings->get_setting("editor_plugins/enabled");
			if (enabled_list.get_type() == Variant::ARRAY) {
				enabled = ((Array)enabled_list).has(config_path);
			} else if (enabled_list.get_type() == Variant::PACKED_STRING_ARRAY) {
				enabled = ((PackedStringArray)enabled_list).has(config_path);
			}
		}
		Dictionary entry;
		entry["name"] = name;
		entry["enabled"] = enabled;
		plugins.push_back(entry);
	}
	plugin_dir->list_dir_end();
	return plugins;
}

static Variant _tool_get_project_statistics(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	bool include_addons = false;
	if (!optional_string(p_args, "path", "res://", path, r_error)) {
		return Variant();
	}
	if (!optional_bool(p_args, "include_addons", false, include_addons, r_error)) {
		return Variant();
	}
	String normalized;
	if (!normalize_project_path(path, normalized, r_error)) {
		return Variant();
	}
	// A start directory that does not exist is a tool error (-32001, GDR-14),
	// never a silently empty report.
	Ref<DirAccess> probe = open_project_dir(normalized, r_error);
	if (probe.is_null()) {
		return Variant();
	}

	StatisticsAccumulator accumulator;
	_collect_statistics_recursive(normalized, include_addons, accumulator);

	Dictionary file_counts;
	for (int i = 0; i < accumulator.extension_order.size(); i++) {
		const String extension = accumulator.extension_order[i];
		file_counts[extension] = accumulator.file_counts[extension];
	}

	Dictionary result;
	result["file_counts_by_extension"] = file_counts;
	result["total_files"] = accumulator.total_files;
	result["total_script_lines"] = accumulator.script_lines;
	result["scene_count"] = accumulator.scene_count;
	result["resource_count"] = accumulator.resource_count;
	result["autoloads"] = _collect_autoloads();
	result["plugins"] = _collect_plugins();
	return result;
}

// ---------------------------------------------------------------------------
// project_analyze_scene_complexity (old `analyze_scene_complexity`)
//
// analysis.rs:414. Loads a `.tscn` from disk, instantiates it and walks the
// result: node count, depth, per-type histogram, attached scripts and the
// reference's two-threshold advice list. When `path` is absent the reference
// falls back to the scene the editor is editing - an editor-only branch,
// guarded twice (MCP_EDITOR_TOOLS_ENABLED at compile time,
// `is_editor_process()` at run time).
// ---------------------------------------------------------------------------

static void _analyze_scene_node(Node *p_node, Node *p_root, int64_t p_depth, Dictionary &r_type_counts, Array &r_scripts, int64_t &r_total, int64_t &r_max_depth) {
	const String type_name = p_node->get_class();
	r_type_counts[type_name] = (r_type_counts.has(type_name) ? (int64_t)r_type_counts[type_name] : 0) + 1;

	const Ref<Script> script = p_node->get_script();
	if (script.is_valid()) {
		const String script_path = script->get_path();
		if (!script_path.is_empty()) {
			Dictionary entry;
			entry["node"] = (String)p_root->get_path_to(p_node);
			entry["script"] = script_path;
			r_scripts.push_back(entry);
		}
	}

	int64_t total = 1;
	int64_t max_depth = p_depth;
	const int child_count = p_node->get_child_count();
	for (int i = 0; i < child_count; i++) {
		Node *child = p_node->get_child(i);
		if (child == nullptr) {
			continue;
		}
		int64_t sub_total = 0;
		int64_t sub_depth = 0;
		_analyze_scene_node(child, p_root, p_depth + 1, r_type_counts, r_scripts, sub_total, sub_depth);
		total += sub_total;
		if (sub_depth > max_depth) {
			max_depth = sub_depth;
		}
	}
	r_total = total;
	r_max_depth = max_depth;
}

static Variant _tool_analyze_scene_complexity(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!optional_string(p_args, "path", String(), path, r_error)) {
		return Variant();
	}
	const String requested = path.strip_edges();

	Node *root_node = nullptr;
	String scene_path;
	bool owned = false;

	if (requested.is_empty()) {
		// `path` is absent: the reference analyses the edited scene. That is an
		// editor-only capability, so it is compiled out of a game build and
		// skipped in a game process; both leave an explicit -32000 behind
		// instead of a crash.
#ifdef MCP_EDITOR_TOOLS_ENABLED
		if (is_editor_process()) {
			SceneTree *tree = SceneTree::get_singleton();
			root_node = tree != nullptr ? tree->get_edited_scene_root() : nullptr;
			if (root_node == nullptr) {
				r_error = MCPToolError::no_scene();
				return Variant();
			}
			scene_path = root_node->get_scene_file_path();
		} else
#endif
		{
			r_error = MCPToolError::not_implemented("analysis of the edited scene in a game process",
					"Pass 'path' with a res:// .tscn file to analyse a scene from disk");
			return Variant();
		}
	} else {
		String normalized;
		if (!normalize_project_path(requested, normalized, r_error)) {
			return Variant();
		}
		if (!ResourceLoader::exists(normalized)) {
			r_error = MCPToolError::not_found(vformat("Scene '%s'", normalized),
					"Use project_get_filesystem_tree to list the .tscn files of the project");
			return Variant();
		}
		const Ref<Resource> resource = ResourceLoader::load(normalized);
		if (resource.is_null()) {
			r_error = MCPToolError::internal(vformat("Unable to load scene: %s", normalized));
			return Variant();
		}
		const PackedScene *packed = Object::cast_to<PackedScene>(resource.ptr());
		if (packed == nullptr) {
			r_error = MCPToolError::internal("The loaded resource is not a valid scene file");
			return Variant();
		}
		root_node = packed->instantiate();
		if (root_node == nullptr) {
			r_error = MCPToolError::internal(vformat("Unable to instantiate scene: %s", normalized));
			return Variant();
		}
		scene_path = normalized;
		owned = true;
	}

	Dictionary type_counts;
	Array scripts;
	int64_t total_nodes = 0;
	int64_t max_depth = 0;
	_analyze_scene_node(root_node, root_node, 0, type_counts, scripts, total_nodes, max_depth);

	// The reference's advice thresholds; each pair is an `else if`, so a scene
	// past 1000 nodes gets one warning and not two. The messages are the
	// reference's own, built through String::utf8 (a `const char *` literal
	// would be decoded as Latin-1 and turn into mojibake).
	Array issues;
	if (total_nodes > 1000) {
		Dictionary issue;
		issue["severity"] = "warning";
		issue["message"] = vformat(String::utf8("场景有 %d 个节点 (>1000)。考虑拆分为子场景。"), total_nodes);
		issues.push_back(issue);
	} else if (total_nodes > 500) {
		Dictionary issue;
		issue["severity"] = "info";
		issue["message"] = vformat(String::utf8("场景有 %d 个节点 (>500)。建议监控性能。"), total_nodes);
		issues.push_back(issue);
	}
	if (max_depth > 15) {
		Dictionary issue;
		issue["severity"] = "warning";
		issue["message"] = vformat(String::utf8("最大嵌套深度为 %d (>15)。深层层级难以维护。"), max_depth);
		issues.push_back(issue);
	} else if (max_depth > 10) {
		Dictionary issue;
		issue["severity"] = "info";
		issue["message"] = vformat(String::utf8("最大嵌套深度为 %d (>10)。"), max_depth);
		issues.push_back(issue);
	}

	if (owned) {
		memdelete(root_node);
	}

	Dictionary result;
	result["scene_path"] = scene_path;
	result["total_nodes"] = total_nodes;
	result["max_depth"] = max_depth;
	result["nodes_by_type"] = type_counts;
	result["scripts_attached"] = scripts;
	result["issues"] = issues;
	return result;
}

// ---------------------------------------------------------------------------
// project_detect_circular_dependencies (old `detect_circular_dependencies`)
//
// analysis.rs:520. Reads every `.tscn` below the start path, parses the
// `[ext_resource ... .tscn]` references out of the raw text and runs the
// reference's DFS over the resulting graph.
// ---------------------------------------------------------------------------

// The reference walks the graph with a HashMap, whose iteration order is not
// stable. The order here is the directory scan order, so
// `circular_dependencies` is deterministic for the same tree (DESIGN-DETAIL
// section 17.4 spirit: the engine must be reproducible).
static void _parse_scene_dependencies(const String &p_contents, Vector<String> &r_out) {
	const Vector<String> lines = split_lines(p_contents);
	for (int i = 0; i < lines.size(); i++) {
		const String trimmed = lines[i].strip_edges();
		if (!trimmed.begins_with("[ext_resource") || !trimmed.contains(".tscn")) {
			continue;
		}
		const String reference = _path_attribute(trimmed);
		if (!reference.is_empty() && reference.ends_with(".tscn")) {
			r_out.push_back(reference);
		}
	}
}

static void _dfs_detect_cycle(const String &p_node, const Dictionary &p_graph, Dictionary &r_visited, Array &r_path_stack, Array &r_cycles) {
	r_visited[p_node] = "visiting";
	r_path_stack.push_back(p_node);

	const Array dependencies = p_graph.has(p_node) ? (Array)p_graph[p_node] : Array();
	for (int i = 0; i < dependencies.size(); i++) {
		const String dependency = dependencies[i];
		const String state = r_visited.has(dependency) ? (String)r_visited[dependency] : "unvisited";
		if (state == "visiting") {
			int cycle_start = -1;
			for (int j = 0; j < r_path_stack.size(); j++) {
				if ((String)r_path_stack[j] == dependency) {
					cycle_start = j;
					break;
				}
			}
			if (cycle_start >= 0) {
				Array cycle;
				for (int j = cycle_start; j < r_path_stack.size(); j++) {
					cycle.push_back(r_path_stack[j]);
				}
				// The start node is repeated at the end, like the reference.
				cycle.push_back(dependency);
				r_cycles.push_back(cycle);
			}
		} else if (state == "unvisited") {
			_dfs_detect_cycle(dependency, p_graph, r_visited, r_path_stack, r_cycles);
		}
	}

	r_path_stack.remove_at(r_path_stack.size() - 1);
	r_visited[p_node] = "visited";
}

static Variant _tool_detect_circular_dependencies(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	bool include_addons = false;
	if (!optional_string(p_args, "path", "res://", path, r_error)) {
		return Variant();
	}
	if (!optional_bool(p_args, "include_addons", false, include_addons, r_error)) {
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

	Vector<String> scenes;
	collect_files_by_extension(normalized, _scene_extensions(), include_addons, scenes);
	Dictionary graph;
	Array ordered_scenes;
	for (int i = 0; i < scenes.size(); i++) {
		String contents;
		MCPToolError ignored;
		if (!read_project_text_file(scenes[i], contents, ignored) || contents.is_empty()) {
			// The reference skips an unreadable or empty scene, which is then
			// absent from `dependency_graph` (but still counted below).
			continue;
		}
		Vector<String> dependencies;
		_parse_scene_dependencies(contents, dependencies);
		Array dependency_array;
		for (int j = 0; j < dependencies.size(); j++) {
			dependency_array.push_back(dependencies[j]);
		}
		graph[scenes[i]] = dependency_array;
		ordered_scenes.push_back(scenes[i]);
	}

	Dictionary visited;
	for (int i = 0; i < ordered_scenes.size(); i++) {
		visited[ordered_scenes[i]] = "unvisited";
	}
	Array cycles;
	Array path_stack;
	for (int i = 0; i < ordered_scenes.size(); i++) {
		const String scene = ordered_scenes[i];
		if (visited.has(scene) && (String)visited[scene] == "unvisited") {
			_dfs_detect_cycle(scene, graph, visited, path_stack, cycles);
		}
	}

	Dictionary result;
	result["scenes_checked"] = scenes.size();
	result["circular_dependencies"] = cycles;
	result["has_circular"] = !cycles.is_empty();
	result["dependency_graph"] = graph;
	return result;
}

// ---------------------------------------------------------------------------
// project_find_unused_resources (old `find_unused_resources`)
//
// analysis.rs:336. Collects every resource file, collects the
// `[ext_resource ... path="..."]` references of every
// `.tscn/.gd/.tres/.cfg/.godot` file, and reports the difference.
// ---------------------------------------------------------------------------

static Variant _tool_find_unused_resources(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	bool include_addons = false;
	if (!optional_string(p_args, "path", "res://", path, r_error)) {
		return Variant();
	}
	if (!optional_bool(p_args, "include_addons", false, include_addons, r_error)) {
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

	Vector<String> resources;
	collect_files_by_extension(normalized, _resource_extensions(), include_addons, resources);

	Vector<String> reference_files;
	collect_files_by_extension(normalized, _reference_extensions(), include_addons, reference_files);

	HashMap<String, bool> referenced;
	for (int i = 0; i < reference_files.size(); i++) {
		String contents;
		MCPToolError ignored;
		if (!read_project_text_file(reference_files[i], contents, ignored)) {
			continue;
		}
		const Vector<String> lines = split_lines(contents);
		for (int j = 0; j < lines.size(); j++) {
			// The reference tests the *raw* line here (`line.starts_with`), not
			// the trimmed one. Kept: it is what makes this parser visibly
			// different from the one project_detect_circular_dependencies uses.
			if (!lines[j].begins_with("[ext_resource")) {
				continue;
			}
			const String reference = _path_attribute(lines[j]);
			if (!reference.is_empty()) {
				referenced[reference] = true;
			}
		}
	}

	Array unused;
	for (int i = 0; i < resources.size(); i++) {
		if (!referenced.has(resources[i])) {
			unused.push_back(resources[i]);
		}
	}

	Dictionary result;
	result["unused_resources"] = unused;
	result["unused_count"] = unused.size();
	result["total_resources_scanned"] = resources.size();
	result["total_files_checked"] = reference_files.size();
	return result;
}

// ---------------------------------------------------------------------------
// project_find_script_references (old `find_script_references`)
//
// analysis.rs:485. Per line {file, line, content} for a case SENSITIVE
// substring match over the `.tscn/.gd/.tres/.cfg/.godot` files, plus the
// `files_searched` counter. Deliberately *not* the same tool as
// project_search_file_contents (GDR-17): that one returns {file,line,text},
// matches case insensitively and reads a different extension whitelist.
// ---------------------------------------------------------------------------

static Variant _tool_find_script_references(const Dictionary &p_args, MCPToolError &r_error) {
	String query;
	if (!require_string(p_args, "query", query, r_error)) {
		return Variant();
	}
	String path;
	if (!optional_string(p_args, "path", "res://", path, r_error)) {
		return Variant();
	}
	bool include_addons = false;
	if (!optional_bool(p_args, "include_addons", false, include_addons, r_error)) {
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

	Vector<String> search_files;
	collect_files_by_extension(normalized, _reference_extensions(), include_addons, search_files);

	Array references;
	for (int i = 0; i < search_files.size(); i++) {
		String contents;
		MCPToolError ignored;
		if (!read_project_text_file(search_files[i], contents, ignored) || contents.is_empty()) {
			continue;
		}
		const Vector<String> lines = split_lines(contents);
		for (int j = 0; j < lines.size(); j++) {
			if (!lines[j].contains(query)) {
				continue;
			}
			Dictionary hit;
			hit["file"] = search_files[i];
			hit["line"] = j + 1;
			hit["content"] = lines[j].strip_edges();
			references.push_back(hit);
		}
	}

	Dictionary result;
	result["query"] = query;
	result["references"] = references;
	result["reference_count"] = references.size();
	result["files_searched"] = search_files.size();
	return result;
}

// ---------------------------------------------------------------------------
// project_get_scene_dependencies (old `get_scene_dependencies`)
//
// batch.rs:519 (only category reference: it reads the scene's ext_resource list
// through `ResourceLoader::get_dependencies`).
//
// TASK-024b E-1 + G-2 - the entry's `type` and `path`.
//
// The loader's string layout with `p_add_types = true` is
// (`scene/resources/resource_format_text.cpp:960-968`)
//
//   `res://path::<type>`                       tag without `uid=`
//   `uid://id::<type>::res://fallback`         tag with `uid=`; the engine stores
//                                              the tag's own path as
//                                              `fallback_path` "Used by
//                                              Dependency Editor, in case uid
//                                              path fails" (:949)
//
// With the default `p_add_types = false` there is no type field, but the
// fallback field is still appended (`path += "::"` when there is no type, :964-966)
// - so the *third* field of `uid://id::::res://fallback` is a **path**. Reading
// it as the type is exactly the D-8 defect the M4c audit measured:
// `{"path":"uid://c7mt5x5j361vt","type":"res://main.gd"}`.
//
// The answer now names every field the engine gave, in the shape a caller can
// use without string surgery (GDR-25 section 23.1 rule 1):
//   * `path`       always the `res://` path (never a `uid://` text) so it can be
//                  fed straight back into any other tool;
//   * `uid`        the `uid://` text the scene recorded, or `""` when it has
//                  none (never the path echoed under `uid`);
//   * `path_source` how `path` was obtained - `"uid"` (the UID registry),
//                  `"scene_path"` (the path the scene file records: the tag's
//                  own `path`, which is also the engine's fallback when a UID
//                  cannot be resolved) or `"unresolved"`;
//   * `type`       the type the engine reports for the resolved resource
//                  (`ResourceLoader::get_resource_type`, resource_loader.h:266 -
//                  for `.tres`/`.tscn` this is a header read, not a load), with
//                  the `[ext_resource]` tag's own type as the fallback for the
//                  formats no loader can classify (an imported `.png` says
//                  `Texture2D` in the tag, and nothing else can say it);
//   * `declared_type` the tag's type verbatim, so both answers are always
//                  available and the difference is visible instead of being
//                  guessed at.
// ---------------------------------------------------------------------------

static Variant _tool_get_scene_dependencies(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	String normalized;
	if (!normalize_project_path(path, normalized, r_error)) {
		return Variant();
	}
	if (!FileAccess::exists(normalized)) {
		r_error = MCPToolError::not_found(vformat("File '%s'", normalized),
				"Use project_get_filesystem_tree to list the files of the project");
		return Variant();
	}

	List<String> dependency_paths;
	ResourceLoader::get_dependencies(normalized, &dependency_paths, /*p_add_types=*/true);

	ResourceUID *uids = ResourceUID::get_singleton();

	Array dependencies;
	for (const String &dependency : dependency_paths) {
		const Vector<String> parts = dependency.split("::", true);
		const String id_or_path = parts.size() > 0 ? parts[0] : dependency;
		const String declared_type = parts.size() > 1 ? parts[1] : String();
		const String fallback_path = parts.size() > 2 ? parts[2] : String();

		String uid;
		String resolved;
		String path_source;
		if (!id_or_path.begins_with("uid://")) {
			// No `uid=` in the tag. The engine already localized the tag's own
			// `path` into a resource path (`resource_format_text.cpp:955-958`).
			resolved = id_or_path;
			path_source = "scene_path";
		} else {
			uid = id_or_path;
			// `ensure_path_nocheck` is the non-throwing half of the UID service:
			// it answers the empty string for a well-formed but unregistered UID
			// instead of the `ERR_FAIL` of `uid_to_path` (`resource_uid.cpp:239-268`).
			resolved = (uids != nullptr) ? ResourceUID::ensure_path_nocheck(uid) : String();
			if (!resolved.is_empty()) {
				path_source = "uid";
			} else {
				resolved = fallback_path;
				path_source = "scene_path";
			}
		}
		if (resolved.is_empty()) {
			// Neither the registry nor the scene file names the resource. Say so
			// rather than answering the raw id under `path`, which would break
			// the one promise `path` makes (a `res://` path the next tool takes).
			path_source = "unresolved";
		}

		String type;
		if (!resolved.is_empty()) {
			type = ResourceLoader::get_resource_type(resolved);
		}
		if (type.is_empty()) {
			type = declared_type;
		}

		Dictionary entry;
		entry["path"] = resolved;
		entry["uid"] = uid;
		entry["type"] = type;
		entry["declared_type"] = declared_type;
		entry["path_source"] = path_source;
		dependencies.push_back(entry);
	}

	Dictionary result;
	result["path"] = normalized;
	result["dependencies"] = dependencies;
	result["count"] = dependencies.size();
	return result;
}

// ---------------------------------------------------------------------------
// project_get_scene_exports (old `get_scene_exports`)
//
// scene.rs:344. Instantiates a `.tscn` and reports, per node that carries a
// script, the variables the editor would show: those flagged with
// PROPERTY_USAGE_EDITOR.
//
// Deviation from the reference (recorded in REPORT-004): the reference tests a
// literal bit `1024`, which in this fork is PROPERTY_USAGE_NO_INSTANCE_STATE
// and not PROPERTY_USAGE_SCRIPT_VARIABLE (`1 << 12`), so it never reports an
// export - in either process. The engine's own enum names are used here, and the
// filter reads the *script's* property list because an editor process reports
// the node's script properties without the SCRIPT_VARIABLE bit at all.
// ---------------------------------------------------------------------------

static void _collect_exports_recursive(Node *p_node, Node *p_root, Array &r_nodes) {
	const Ref<Script> script = p_node->get_script();
	if (script.is_valid()) {
		// The filter walks the *script's own* member list instead of the node's
		// merged `get_property_list()`: the two disagree in an editor process.
		// There, the merged list reports the very same exported variable as
		// `PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR` (6) - without
		// `PROPERTY_USAGE_SCRIPT_VARIABLE` - and omits a plain `var` altogether,
		// while `Script::get_script_property_list()` reports 4102 (exported) and
		// 4096 (plain member) in both processes. Measured with a probe on both a
		// game process and an editor process; see REPORT-004 section 3.
		//
		// Therefore `PROPERTY_USAGE_EDITOR` alone is the export test: an
		// exported variable has it, a plain `var` (4096) does not, and the class
		// category that a tools build pushes into the list has no EDITOR bit
		// either. Reading the value through `p_node->get()` also keeps the
		// scene's override (a `.tscn` that sets `speed = 7`).
		List<PropertyInfo> script_properties;
		script->get_script_property_list(&script_properties);

		Dictionary exports;
		for (const PropertyInfo &property : script_properties) {
			if ((property.usage & PROPERTY_USAGE_EDITOR) == 0) {
				continue;
			}
			Dictionary info;
			info["value"] = serialize_variant(p_node->get(property.name));
			info["type"] = (int64_t)property.type;
			info["hint"] = (int64_t)property.hint;
			info["hint_string"] = property.hint_string;
			exports[(String)property.name] = info;
		}

		if (!exports.is_empty()) {
			Dictionary entry;
			entry["node_path"] = (p_node == p_root) ? String(".") : (String)p_root->get_path_to(p_node);
			entry["node_name"] = (String)p_node->get_name();
			entry["node_type"] = p_node->get_class();
			entry["script_path"] = script->get_path();
			entry["exports"] = exports;
			r_nodes.push_back(entry);
		}
	}

	const int child_count = p_node->get_child_count();
	for (int i = 0; i < child_count; i++) {
		Node *child = p_node->get_child(i);
		if (child != nullptr) {
			_collect_exports_recursive(child, p_root, r_nodes);
		}
	}
}

static Variant _tool_get_scene_exports(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	String normalized;
	if (!normalize_project_path(path, normalized, r_error)) {
		return Variant();
	}
	if (!FileAccess::exists(normalized)) {
		r_error = MCPToolError::not_found(vformat("Scene file '%s'", normalized),
				"Use project_get_filesystem_tree to list the .tscn files of the project");
		return Variant();
	}

	const Ref<Resource> resource = ResourceLoader::load(normalized);
	if (resource.is_null()) {
		r_error = MCPToolError::internal(vformat("Unable to load scene: %s", normalized));
		return Variant();
	}
	const PackedScene *packed = Object::cast_to<PackedScene>(resource.ptr());
	if (packed == nullptr) {
		r_error = MCPToolError::internal("The loaded resource is not a valid scene file");
		return Variant();
	}
	Node *instance = packed->instantiate();
	if (instance == nullptr) {
		r_error = MCPToolError::internal(vformat("Unable to instantiate scene: %s", normalized));
		return Variant();
	}

	Array nodes;
	_collect_exports_recursive(instance, instance, nodes);
	memdelete(instance);

	Dictionary result;
	result["path"] = normalized;
	result["nodes"] = nodes;
	result["count"] = nodes.size();
	return result;
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

void register_project_read_analysis_tools(MCPToolRegistry &r_registry) {
	// Order follows docs/tool-groups.json. The order is not a contract, but it
	// has to be stable and append-only. Every tool is channel `project`,
	// `mutating = false`, `scope = BOTH`, and takes its description and
	// `inputSchema` verbatim from docs/tools_list.renamed.json.
	{
		Dictionary path_property;
		path_property["type"] = "string";
		path_property["description"] = String::utf8("统计路径");
		path_property["default"] = "res://";

		Dictionary include_addons_property;
		include_addons_property["type"] = "boolean";
		include_addons_property["description"] = String::utf8("是否包含 addons 目录");
		include_addons_property["default"] = false;

		Dictionary properties;
		properties["path"] = path_property;
		properties["include_addons"] = include_addons_property;

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = Array();

		ToolBuilder builder("project_get_statistics", String::utf8("获取项目统计信息（文件数、脚本行数、场景数等）"));
		builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_get_project_statistics);
		builder.register_into(r_registry);
	}

	{
		Dictionary path_property;
		path_property["type"] = "string";
		path_property["description"] = String::utf8("场景文件路径（可选，不传则分析当前编辑场景）");

		Dictionary properties;
		properties["path"] = path_property;

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = Array();

		ToolBuilder builder("project_analyze_scene_complexity", String::utf8("分析场景的复杂度（节点数、深度、类型分布等）"));
		builder.channel("project").verb("analyze").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_analyze_scene_complexity);
		builder.register_into(r_registry);
	}

	{
		Dictionary path_property;
		path_property["type"] = "string";
		path_property["description"] = String::utf8("搜索路径");
		path_property["default"] = "res://";

		Dictionary include_addons_property;
		include_addons_property["type"] = "boolean";
		include_addons_property["description"] = String::utf8("是否包含 addons 目录");
		include_addons_property["default"] = false;

		Dictionary properties;
		properties["path"] = path_property;
		properties["include_addons"] = include_addons_property;

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = Array();

		ToolBuilder builder("project_detect_circular_dependencies", String::utf8("检测场景文件之间的循环依赖"));
		builder.channel("project").verb("detect").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_detect_circular_dependencies);
		builder.register_into(r_registry);
	}

	{
		Dictionary path_property;
		path_property["type"] = "string";
		path_property["description"] = String::utf8("搜索路径，默认为 res://");
		path_property["default"] = "res://";

		Dictionary include_addons_property;
		include_addons_property["type"] = "boolean";
		include_addons_property["description"] = String::utf8("是否包含 addons 目录");
		include_addons_property["default"] = false;

		Dictionary properties;
		properties["path"] = path_property;
		properties["include_addons"] = include_addons_property;

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = Array();

		ToolBuilder builder("project_find_unused_resources", String::utf8("查找项目中可能未使用的资源文件"));
		builder.channel("project").verb("find").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_find_unused_resources);
		builder.register_into(r_registry);
	}

	{
		Dictionary query_property;
		query_property["type"] = "string";
		query_property["description"] = String::utf8("要搜索的脚本路径或类名");

		Dictionary path_property;
		path_property["type"] = "string";
		path_property["description"] = String::utf8("搜索路径");
		path_property["default"] = "res://";

		Dictionary include_addons_property;
		include_addons_property["type"] = "boolean";
		include_addons_property["description"] = String::utf8("是否包含 addons 目录");
		include_addons_property["default"] = false;

		Dictionary properties;
		properties["query"] = query_property;
		properties["path"] = path_property;
		properties["include_addons"] = include_addons_property;

		Array required;
		required.push_back("query");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		ToolBuilder builder("project_find_script_references", String::utf8("查找引用指定脚本的所有文件"));
		builder.channel("project").verb("find").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_find_script_references);
		builder.register_into(r_registry);
	}

	{
		Dictionary path_property;
		path_property["type"] = "string";
		path_property["description"] = String::utf8("场景文件路径 (res://)");

		Dictionary properties;
		properties["path"] = path_property;

		Array required;
		required.push_back("path");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		ToolBuilder builder("project_get_scene_dependencies", String::utf8("获取场景文件的依赖资源列表"));
		builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_get_scene_dependencies);
		builder.register_into(r_registry);
	}

	{
		Dictionary path_property;
		path_property["type"] = "string";
		path_property["description"] = String::utf8("场景文件路径 (res://)");

		Dictionary properties;
		properties["path"] = path_property;

		Array required;
		required.push_back("path");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		ToolBuilder builder("project_get_scene_exports", String::utf8("获取场景根节点的导出变量列表"));
		builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_get_scene_exports);
		builder.register_into(r_registry);
	}
}
