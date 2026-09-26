/**************************************************************************/
/*  editor_write_scene_editor.cpp                                         */
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
#include "editor_write_scene_editor.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/config/project_settings.h"
#include "core/crypto/crypto_core.h"
#include "core/error/error_macros.h"
#include "core/io/file_access.h"
#include "core/io/image.h"
#include "core/io/json.h"
#include "core/io/resource_saver.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/object/ref_counted.h"
#include "core/string/string_name.h"
#include "core/variant/variant.h"
#include "core/variant/variant_utility.h"
#include "scene/3d/camera_3d.h"
#include "scene/gui/control.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/main/viewport.h"
#include "scene/resources/packed_scene.h"

// The compile-time half of the editor guard (TASK-002 section 2.2.3). In a game
// build (`TOOLS_ENABLED` undefined) none of the includes below and none of the
// guarded call sites exist at all - the ten tools are still *compiled*, because
// the group file is shared, but every editor-only branch collapses into a clean
// -32000 answer.
#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/editor_data.h"
#include "editor/editor_interface.h"
#include "editor/editor_log.h"
#include "editor/editor_node.h"
#include "editor/file_system/editor_file_system.h"
#include "editor/scene/3d/node_3d_editor_plugin.h"
#include "scene/gui/rich_text_label.h"
#endif

using namespace MCPTools;

// The runtime half of the editor guard lives in `tools/tool_helpers.*` since
// TASK-009 section 2.2 - one definition for every editor group instead of one
// copy per group file - and is called below as
// `require_editor_ui(r_error, <non-editor wording>, <suggestion>)`. The
// `EditorInterface` / `EditorNode` null-check reasoning that used to be
// documented here is preserved next to that single definition.

// The edited scene root and the migration source's node resolution were hoisted
// into `tools/tool_helpers.*` by TASK-016 section 1 (`MCPTools::edited_scene_root`
// / `MCPTools::find_node`), together with the `SceneTree` vs `EditorInterface`
// reasoning that used to be documented here. This file now calls the one
// definition instead of keeping a file-private copy of either.

// The selection entry of one node, with the migration source's serialisation
// rules (node.rs:601-622): the root is spelled ".", a node that is neither the
// root nor a descendant of it is skipped.
static bool _selection_entry(Node *p_root, Node *p_node, Dictionary &r_out) {
	if (p_node == nullptr) {
		return false;
	}
	if (p_node != p_root && !p_root->is_ancestor_of(p_node)) {
		return false;
	}
	r_out["name"] = String(p_node->get_name());
	r_out["path"] = p_node == p_root ? String(".") : String(p_root->get_path_to(p_node));
	r_out["type"] = p_node->get_class();
	return true;
}

static Array _selection_entries(Node *p_root, const List<Node *> &p_nodes) {
	Array out;
	for (Node *node : p_nodes) {
		Dictionary entry;
		if (_selection_entry(p_root, node, entry)) {
			out.push_back(entry);
		}
	}
	return out;
}

// `fov` is the one optional *number* of this group. Its value is read by the
// shared `MCPTools::optional_float` (`tools/tool_helpers.*`); what this tool
// keeps at the call site is the *presence* flag, because "the caller did not
// mention fov" and "the caller set fov to 0" are different requests here. A
// present-but-not-a-number value is -32602 (PLAYBOOK section 6.2), never a
// silently ignored argument.

// An optional `{x, y, z}` object. The migration source reads each component with
// `as_f64().unwrap_or(0.0)` (a silently ignored mistake); a component that is
// present but not a number is refused here instead (PLAYBOOK section 6.2), while
// an absent component keeps the reference's 0.0.
//
// **The components are judged before the `Vector3` is built** (GDR-24,
// TASK-023 D-7). This path does not go through `coerce_to_property_type` - it
// builds a `Vector3` and hands it to a dedicated setter (`set_global_position` /
// `set_rotation_degrees` / `look_at`), which is exactly the shape the M4c audit
// caught: `{"x":1e300}` answered `code=0` while the camera really held
// `(inf, 0, 0)`. The cast below is a narrowing copy, so every component that is
// present goes through the module's one width judgement first.
//
// Published as `MCPTools::vector3_from_json` (TASK-023) so the doctest asserts
// **this** function rather than a copy of it: the defect it fixes is a silent
// wrong value, and only a direct assertion pins the refusal.
namespace MCPTools {

bool vector3_from_json(const Dictionary &p_args, const String &p_key, bool &r_present, Vector3 &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	r_present = value.get_type() != Variant::NIL;
	if (!r_present) {
		return true;
	}
	if (value.get_type() != Variant::DICTIONARY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be an object with x, y, z, got %s",
				p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	const Dictionary source = value;
	const char *const axes[3] = { "x", "y", "z" };
	double components[3] = { 0.0, 0.0, 0.0 };
	for (int i = 0; i < 3; i++) {
		const Variant component = source.get(axes[i], Variant());
		if (component.get_type() == Variant::NIL) {
			continue;
		}
		if (component.get_type() != Variant::FLOAT && component.get_type() != Variant::INT) {
			r_error = MCPToolError::invalid_params(vformat("Parameter '%s.%s' must be a number, got %s",
					p_key, axes[i], Variant::get_type_name(component.get_type())));
			return false;
		}
		// MCP-NARROWING: G24-CAMERA-COMPONENT - `components[i] = (double)component`
		// below is the widening read and the `Vector3(...)` construction further
		// down is the narrowing copy: a JSON number arrives as a `double`
		// (`FLOAT`, or `INT` for an integral request), and both are judged here
		// by the TASK-023 gate before either happens. The slot is `FLOAT32`
		// rather than `REAL_T` so the judgement does not depend on the build's
		// `real_t` (GDR-24).
		if (!value_fits_slot(component, ValueSlot::FLOAT32, vformat("%s.%s", p_key, axes[i]),
					"the 32-bit float component of the Vector3 this camera setter stores", r_error)) {
			return false;
		}
		components[i] = (double)component;
	}
	// MCP-NARROWING: G24-CAMERA-COMPONENT - the cast below is the narrowing the
	// loop above judged, component by component.
	r_out = Vector3((real_t)components[0], (real_t)components[1], (real_t)components[2]);
	return true;
}

} // namespace MCPTools

// The property-value conversion lives in `tools/tool_helpers.*` since TASK-009
// section 2.2: `property_value_from_json`, `coerce_to_property_type` and
// `property_type_of` are one definition per helper for both writing groups (this
// file's former copy was a subset of `project_write_resource_scene.cpp`'s, which
// is the one that was hoisted). The conversion rules that used to be documented
// here - the integral fold, `#rrggbb`, the `Vector2(..)` / `Vector3(..)`
// grammar, "an object stays a Dictionary", `type_convert` and the
// non-finite-number refusal - are preserved next to that single definition.

// ---------------------------------------------------------------------------
// editor_open_scene (old `open_scene`, scene.rs:117)
//
// `path` is required and must address the project. The reference only checked
// `FileAccess::file_exists` and then called `open_scene_from_path`, reporting
// success unconditionally - so a scene file that exists but cannot be *loaded*
// was answered with `{"opened": true}`. That is the fake-success shape TASK-008
// section 2 forbids, and `editor_open_scene` is the tool the state-chain evidence
// leans on, so the result is verified: after the call the edited scene must
// really be the requested file, otherwise -32603.
// ---------------------------------------------------------------------------
static Variant _tool_open_scene(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!require_string(p_args, "path", raw_path, r_error)) {
		return Variant();
	}
	String path;
	if (!normalize_project_path(raw_path, path, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	if (!FileAccess::exists(path)) {
		r_error = MCPToolError::not_found(vformat("Scene '%s'", path),
				"Use project_get_filesystem_tree to list the .tscn files of the project");
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorInterface *editor = EditorInterface::get_singleton();
	if (editor == nullptr) {
		r_error = MCPToolError::not_implemented("the editor UI (no EditorInterface in this process)",
				"Start the MCP server inside the Godot editor to open scenes");
		return Variant();
	}
	editor->open_scene_from_path(path);

	Node *root = MCPTools::edited_scene_root();
	if (root == nullptr || root->get_scene_file_path() != path) {
		// The file exists but the editor did not end up editing it: the scene is
		// not *loadable* (a missing script, a dead ext_resource path). That is
		// the same "the file is there but the loadable object is not" shape the
		// write group established for `project_edit_resource`
		// (REPORT-007 deviation 7), so it is `-32001` with a suggestion rather
		// than an internal error.
		r_error = MCPToolError::not_found(vformat("Loadable scene '%s'", path),
				"The file exists but the editor could not open it as a scene; check its dependencies (missing scripts, resources or ext_resource paths)");
		return Variant();
	}

	Dictionary result;
	result["path"] = path;
	result["opened"] = true;
	return result;
#endif
	return Variant();
}

// ---------------------------------------------------------------------------
// editor_save_scene (old `save_scene`, scene.rs:151)
//
// `path` is optional: absent (or empty) means "save where the scene already
// lives", which is the reference's `EditorInterface::save_scene()` branch.
//
// **Atomic publish.** The reference called `EditorInterface::save_scene_as()`,
// which writes straight into the destination *and* retargets the edited scene to
// the file it just wrote (`EditorNode::_save_scene` calls
// `scene->set_scene_file_path()` on success). Redirecting that call into a
// temporary file and renaming it would therefore leave the editor pointing at
// `x.mcp-tmp.tscn`. The scene is instead packed exactly as the editor packs it
// (`EditorNode::_save_scene` does `sdata->pack(scene)`) and published through
// `MCPTools::publish_file_atomically`, so the destination is only ever replaced
// by a complete file and the edited scene is retargeted only after the publish
// succeeded.
//
// The editor's extra bookkeeping (per-scene editor state, external resources,
// folding) is not reproduced: it writes to its own paths, and the tool's
// observable contract is the scene file plus the reported path.
// ---------------------------------------------------------------------------
static Error _packed_scene_writer(const String &p_temp_path, void *p_userdata) {
	const Ref<PackedScene> *scene = static_cast<const Ref<PackedScene> *>(p_userdata);
	// The same flag the editor's own save path passes (editor_node.cpp: `flg |=
	// ResourceSaver::FLAG_REPLACE_SUBRESOURCE_PATHS`).
	return ResourceSaver::save(*scene, p_temp_path, ResourceSaver::FLAG_REPLACE_SUBRESOURCE_PATHS);
}

static Variant _tool_save_scene(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!optional_string(p_args, "path", String(), raw_path, r_error)) {
		return Variant();
	}
	String requested;
	if (!raw_path.is_empty()) {
		if (!normalize_project_path(raw_path, requested, r_error)) {
			return Variant();
		}
	}
	if (!require_editor_ui(r_error, "editor writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	Node *root = MCPTools::edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}

	String target = requested;
	if (target.is_empty()) {
		target = root->get_scene_file_path();
	}
	if (target.is_empty()) {
		r_error = MCPToolError::tool_state("The edited scene has no file path yet, so there is nothing to save to",
				"Pass 'path' to save the scene to a res:// file");
		return Variant();
	}

	Ref<PackedScene> packed;
	packed.instantiate();
	const Error pack_error = packed->pack(root);
	if (pack_error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to pack the edited scene (error %d)", (int)pack_error));
		return Variant();
	}

	Ref<PackedScene> held = packed;
	const Error save_error = publish_file_atomically(target, _packed_scene_writer, &held);
	if (save_error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to save scene '%s' (error %d)", target, (int)save_error));
		return Variant();
	}

	// Only now is the editor told where the scene lives; the reference did the
	// same thing implicitly through `save_scene_as`.
	root->set_scene_file_path(ProjectSettings::get_singleton()->localize_path(target));
	EditorData &editor_data = EditorNode::get_editor_data();
	const int index = editor_data.get_edited_scene();
	if (index >= 0) {
		editor_data.set_scene_as_saved(index);
	}

	Dictionary result;
	result["path"] = target;
	result["saved"] = true;
	return result;
#endif
	return Variant();
}

// ---------------------------------------------------------------------------
// editor_reload_plugin (old `reload_plugin`, editor.rs:430)
//
// The reference disabled and re-enabled the editor addon plugin literally named
// `godot_mcp`. In this fork the MCP server is a *built-in module*, not an addon,
// so there is no plugin of that name: repeating the reference verbatim would call
// `set_addon_plugin_enabled("godot_mcp", ...)` - a no-op that prints an engine
// error - and then answer `{"reloading": true}`. That is exactly the fake success
// TASK-008 section 2(c) forbids, so the mechanism is kept and widened to the
// plugins that actually exist: every addon in `editor_plugins/enabled` is
// disabled and enabled again. When that list is empty there is genuinely nothing
// to reload and the tool says so with -32000 + `data.suggestion` instead of
// claiming a reload it did not perform.
// ---------------------------------------------------------------------------
static Variant _tool_reload_plugin(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	if (!require_editor_ui(r_error, "editor writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	Array names;
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings != nullptr && settings->has_setting("editor_plugins/enabled")) {
		const Variant enabled = settings->get("editor_plugins/enabled");
		if (enabled.get_type() == Variant::PACKED_STRING_ARRAY) {
			const PackedStringArray list = enabled;
			for (int i = 0; i < list.size(); i++) {
				names.push_back(list[i]);
			}
		} else if (enabled.get_type() == Variant::ARRAY) {
			const Array list = enabled;
			for (int i = 0; i < list.size(); i++) {
				names.push_back((String)list[i]);
			}
		}
	}

	if (names.is_empty()) {
		r_error = MCPToolError::tool_state("No editor addon plugin is enabled in this project, so there is no plugin to reload",
				"The MCP server is a built-in module and cannot be unloaded at runtime; enable an addon under Project > Project Settings > Plugins and call editor_reload_plugin again");
		return Variant();
	}

	EditorNode *editor_node = EditorNode::get_singleton();
	if (editor_node == nullptr) {
		r_error = MCPToolError::not_implemented("the editor UI (no EditorNode is running in this process)",
				"Start the MCP server inside the Godot editor to reload plugins");
		return Variant();
	}
	for (int i = 0; i < names.size(); i++) {
		const String name = names[i];
		// `p_config_changed = false`: reloading is not a settings edit, so the
		// project file is not rewritten twice per plugin.
		editor_node->set_addon_plugin_enabled(name, false, false);
		editor_node->set_addon_plugin_enabled(name, true, false);
	}

	Dictionary result;
	result["reloading"] = true;
	result["plugins"] = names;
	result["message"] = String::utf8("编辑器插件已禁用并重新启用");
	return result;
#endif
	return Variant();
}

// ---------------------------------------------------------------------------
// editor_rescan_project_filesystem (old `reload_project`, editor.rs:445)
//
// `EditorFileSystem::scan()` is asynchronous in the editor, so the tool reports
// that the rescan was triggered - which is what it did - and the observable
// effect has to be read back with `project_get_filesystem_tree`.
// ---------------------------------------------------------------------------
static Variant _tool_rescan_project_filesystem(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	if (!require_editor_ui(r_error, "editor writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorInterface *editor = EditorInterface::get_singleton();
	EditorFileSystem *filesystem = editor != nullptr ? editor->get_resource_filesystem() : nullptr;
	if (filesystem == nullptr) {
		r_error = MCPToolError::internal("Failed to get the editor resource filesystem");
		return Variant();
	}
	filesystem->scan();

	Dictionary result;
	result["reloaded"] = true;
	result["message"] = String::utf8("文件系统已重新扫描");
	return result;
#endif
	return Variant();
}

// ---------------------------------------------------------------------------
// editor_set_node_selection (old `select_nodes`, node.rs:651)
//
// `node_paths` (array) and `node_path` (single) are alternatives; the reference
// accepted an array only in `node_paths`, so a `node_paths` that is not an array
// of strings could not be expressed there and is -32602 here. `mode` is one of
// replace/add/remove, `inspect` defaults to true and `focus` defaults to
// `inspect`. The single-node focus/inspect convenience is kept.
// ---------------------------------------------------------------------------

// The reference's path list extraction (node.rs:656-669).
static bool _node_paths_argument(const Dictionary &p_args, Vector<String> &r_paths, MCPToolError &r_error) {
	const Variant list = p_args.get("node_paths", Variant());
	if (list.get_type() == Variant::ARRAY) {
		const Array array = list;
		for (int i = 0; i < array.size(); i++) {
			if (array[i].get_type() != Variant::STRING) {
				r_error = MCPToolError::invalid_params(vformat("Parameter 'node_paths[%d]' must be a string, got %s",
						i, Variant::get_type_name(array[i].get_type())));
				return false;
			}
			r_paths.push_back((String)array[i]);
		}
		return true;
	}
	if (list.get_type() != Variant::NIL) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'node_paths' must be an array of strings, got %s",
				Variant::get_type_name(list.get_type())));
		return false;
	}

	const Variant single = p_args.get("node_path", Variant());
	if (single.get_type() == Variant::STRING) {
		r_paths.push_back((String)single);
		return true;
	}
	if (single.get_type() != Variant::NIL) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'node_path' must be a string, got %s",
				Variant::get_type_name(single.get_type())));
		return false;
	}

	r_error = MCPToolError::invalid_params("Missing required parameter: node_paths or node_path");
	return false;
}

static Variant _tool_set_node_selection(const Dictionary &p_args, MCPToolError &r_error) {
	Vector<String> node_paths;
	if (!_node_paths_argument(p_args, node_paths, r_error)) {
		return Variant();
	}
	String mode;
	if (!optional_string(p_args, "mode", String("replace"), mode, r_error)) {
		return Variant();
	}
	if (mode != "replace" && mode != "add" && mode != "remove") {
		r_error = MCPToolError::invalid_params("mode must be one of: replace, add, remove");
		return Variant();
	}
	bool inspect = true;
	if (!optional_bool(p_args, "inspect", true, inspect, r_error)) {
		return Variant();
	}
	bool focus = inspect;
	if (!optional_bool(p_args, "focus", inspect, focus, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	Node *root = MCPTools::edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}

	Vector<Node *> resolved;
	for (int i = 0; i < node_paths.size(); i++) {
		Node *node = MCPTools::find_node(root, node_paths[i]);
		if (node == nullptr) {
			r_error = MCPToolError::not_found(vformat("Node '%s'", node_paths[i]),
					"Use editor_get_scene_tree to list the nodes of the edited scene");
			return Variant();
		}
		resolved.push_back(node);
	}

	EditorNode *editor_node = EditorNode::get_singleton();
	EditorSelection *selection = editor_node != nullptr ? editor_node->get_editor_selection() : nullptr;
	if (selection == nullptr) {
		r_error = MCPToolError::internal("Failed to get editor selection");
		return Variant();
	}

	if (mode == "replace") {
		selection->clear();
	}
	for (int i = 0; i < resolved.size(); i++) {
		if (mode == "remove") {
			selection->remove_node(resolved[i]);
		} else {
			selection->add_node(resolved[i]);
		}
	}

	if (mode != "remove" && resolved.size() == 1) {
		EditorInterface *editor = EditorInterface::get_singleton();
		if (editor != nullptr) {
			if (focus) {
				editor->edit_node(resolved[0]);
			}
			if (inspect) {
				editor->inspect_object(resolved[0]);
			}
		}
	}

	Dictionary result;
	result["mode"] = mode;
	result["selected"] = _selection_entries(root, selection->get_full_selected_node_list());
	result["count"] = ((Array)result["selected"]).size();
	return result;
#endif
	return Variant();
}

// ---------------------------------------------------------------------------
// editor_remove_node_selection (old `clear_editor_selection`, node.rs:722)
//
// Returns how many nodes were selected *before* the clear, under the reference's
// key `cleared` (node.rs:733-737).
// ---------------------------------------------------------------------------
static Variant _tool_remove_node_selection(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	if (!require_editor_ui(r_error, "editor writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	Node *root = MCPTools::edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	EditorNode *editor_node = EditorNode::get_singleton();
	EditorSelection *selection = editor_node != nullptr ? editor_node->get_editor_selection() : nullptr;
	if (selection == nullptr) {
		r_error = MCPToolError::internal("Failed to get editor selection");
		return Variant();
	}

	const int before = selection->get_full_selected_node_list().size();
	selection->clear();

	Dictionary result;
	result["cleared"] = before;
	result["selected"] = Array();
	result["count"] = 0;
	return result;
#endif
	return Variant();
}

// ---------------------------------------------------------------------------
// editor_add_resource_to_node_property (old `add_resource`, node.rs:365)
//
// `node_path`, `property` and `resource_type` are required; an unknown class or a
// class that is not a `Resource` is a dead `ClassDB::instantiate`, which the
// reference reported as `-32602` and which stays `-32602` here (report §2).
// `resource_properties` is applied to the fresh resource, unknown names are
// silently skipped exactly as `Object::set()` does. The resource is never saved
// to disk: it becomes a sub-resource of the edited scene, which is the
// distinction the tool's name makes against `project_create_resource`.
// ---------------------------------------------------------------------------
static Variant _tool_add_resource_to_node_property(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	String property;
	if (!require_string(p_args, "property", property, r_error)) {
		return Variant();
	}
	String resource_type;
	if (!require_string(p_args, "resource_type", resource_type, r_error)) {
		return Variant();
	}
	Dictionary resource_properties;
	const Variant raw_properties = p_args.get("resource_properties", Variant());
	if (raw_properties.get_type() != Variant::NIL) {
		if (raw_properties.get_type() != Variant::DICTIONARY) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'resource_properties' must be an object, got %s",
					Variant::get_type_name(raw_properties.get_type())));
			return Variant();
		}
		resource_properties = raw_properties;
	}

	// `ClassDB` in this fork has no singleton accessor: its whole surface is
	// static (core/object/class_db.h), so the checks are spelled out in three
	// steps with three distinct -32602 messages. An unknown name, a real class
	// that is not a Resource, and a Resource class that cannot be instantiated
	// are three different mistakes and must not share one message.
	const StringName type_name(resource_type);
	if (!ClassDB::class_exists(type_name)) {
		r_error = MCPToolError::invalid_params(vformat("Unknown resource type: %s", resource_type));
		return Variant();
	}
	if (!ClassDB::is_parent_class(type_name, StringName("Resource"))) {
		r_error = MCPToolError::invalid_params(vformat("'%s' is not a Resource type", resource_type));
		return Variant();
	}
	if (!ClassDB::can_instantiate(type_name)) {
		r_error = MCPToolError::invalid_params(vformat("'%s' cannot be instantiated", resource_type));
		return Variant();
	}

	if (!require_editor_ui(r_error, "editor writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	Node *root = MCPTools::edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Node *node = MCPTools::find_node(root, node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", node_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}

	Object *instance = ClassDB::instantiate(type_name);
	Resource *resource = Object::cast_to<Resource>(instance);
	if (resource == nullptr) {
		if (instance != nullptr) {
			memdelete(instance);
		}
		r_error = MCPToolError::invalid_params(vformat("'%s' is not a Resource type", resource_type));
		return Variant();
	}
	Ref<Resource> resource_ref = resource;

	const Array keys = resource_properties.keys();
	for (int i = 0; i < keys.size(); i++) {
		const StringName key = keys[i];
		const Variant::Type target_type = property_type_of(resource_ref.ptr(), key);
		Variant converted;
		if (!coerce_to_property_type(property_value_from_json(resource_properties[keys[i]], target_type), target_type, converted, r_error, "resource_properties")) {
			return Variant();
		}
		resource_ref->set(key, converted);
	}

	// TASK-040 D-1: the store step is `MCPTools::assign_resource_to_property`
	// (tools/tool_helpers.*), the module's one definition of "put this freshly
	// built resource into this node property". The two lines that used to be here
	// (`node->set(property, Variant(resource_ref))` plus the unconditional
	// success answer below) reported a write on a property the node does not have
	// - and on a property whose declared class cannot hold the resource - while
	// nothing had happened (RACING-FINDINGS section 4 D-1). It is exported
	// because the doctest process has no `SceneTree` and can never reach this
	// tool, so the defect could not be pinned any other way.
	if (!assign_resource_to_property(node, StringName(property), resource_ref, r_error)) {
		return Variant();
	}

	Dictionary result;
	result["node_path"] = node == root ? String(".") : String(root->get_path_to(node));
	result["property"] = property;
	result["resource_type"] = resource_type;
	return result;
#endif
	return Variant();
}

// ---------------------------------------------------------------------------
// editor_set_viewport_3d_camera (old `set_editor_camera`, editor.rs:635)
//
// The reference built a GDScript snippet because its Rust bindings could not
// reach the 3D viewport; the four setters and the returned five keys are the
// same. The order position -> rotation_degrees -> look_at -> fov is the
// reference's (`editor.rs:650-676`). An absent viewport or camera is the
// reference's own "无法获取3D视口, 请确保已打开3D场景" internal error, shared with
// `editor_get_viewport_3d_camera`.
// ---------------------------------------------------------------------------
static Variant _tool_set_viewport_3d_camera(const Dictionary &p_args, MCPToolError &r_error) {
	String property;
	if (!require_string(p_args, "property", property, r_error)) {
		return Variant();
	}
	String resource_type;
	if (!require_string(p_args, "resource_type", resource_type, r_error)) {
		return Variant();
	}
	Dictionary resource_properties;
	const Variant raw_properties = p_args.get("resource_properties", Variant());
	if (raw_properties.get_type() != Variant::NIL) {
		if (raw_properties.get_type() != Variant::DICTIONARY) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'resource_properties' must be an object, got %s",
					Variant::get_type_name(raw_properties.get_type())));
			return Variant();
		}
		resource_properties = raw_properties;
	}

	ClassDB *class_db = ClassDB::get_singleton();
	const StringName type_name(resource_type);
	if (!class_db->class_exists(type_name)) {
		r_error = MCPToolError::invalid_params(vformat("Unknown resource type: %s", resource_type));
		return Variant();
	}
	if (!class_db->is_parent_class(type_name, StringName("Resource"))) {
		r_error = MCPToolError::invalid_params(vformat("'%s' is not a Resource type", resource_type));
		return Variant();
	}

	if (!require_editor_ui(r_error, "editor writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	Node *root = _edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Node *node = _find_node(root, node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", node_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}

	Object *instance = class_db->instantiate(type_name);
	Resource *resource = Object::cast_to<Resource>(instance);
	if (resource == nullptr) {
		if (instance != nullptr) {
// `saved_path`. Both key sets are the reference's.
//
// Two deliberate changes:
//
//   1. the write goes through `MCPTools::publish_file_atomically`, so a failing
//      save cannot truncate a file that was already there;
//   2. a `save_path` that cannot be written is an **error**. The reference
//      swallowed the failure, removed `image_base64` anyway and answered
//      `{"width": .., "height": ..}` - a success with no image and no file. That
//      is the "no fake success" rule of TASK-008 section 2(c) applied to the
//      second file writer of this group.
//
// TASK-014 D-2 (the M2 acceptance's consistency nit): the "this process has no
// framebuffer" half used to be answered with `-32603 Internal error:
// 截图获取失败, 请重试`, which tells a client "the server broke" where the truth is
// "this editor cannot produce a picture". GDR-20 point 10 fixes the code for
// exactly this situation: a capability the process does not have is `-32000`
// with `data.suggestion`, and `-32603` stays for a genuine internal error. The
// availability test is the module's one `MCPTools::game_framebuffer_available()`
// (`tool_helpers.h`), the same call `running_game_capture_screenshot` makes, so
// both capture tools now classify the headless display server the same way.
//
// The path may be `res://` or `user://` (the contract's own wording); `..` is
// refused in both.
// ---------------------------------------------------------------------------
// The destination rule and the PNG writer used to be file-private here
// (`_normalize_screenshot_path` / `_png_writer`). TASK-011 section 2 hoisted them
// into `tools/tool_helpers.{h,cpp}` (`MCPTools::normalize_screenshot_path` /
// `MCPTools::screenshot_png_writer`) because the game-side capture group is the
// second viewport readback of the module and a group may not call another
// group's file-private helper (PLAYBOOK section 2.4). The bodies are verbatim;
// the doctests below still pin every refusal message.
static Variant _tool_capture_screenshot(const Dictionary &p_args, MCPToolError &r_error) {
	String save_path;
	if (!optional_string(p_args, "save_path", String(), save_path, r_error)) {
		return Variant();
	}
	String target;
	if (!save_path.is_empty()) {
		if (!normalize_screenshot_path(save_path, target, r_error)) {
			return Variant();
		}
	}
	if (!require_editor_ui(r_error, "editor writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorInterface *editor = EditorInterface::get_singleton();
	Control *base_control = editor != nullptr ? editor->get_base_control() : nullptr;
	if (base_control == nullptr) {
		r_error = MCPToolError::internal(String::utf8("无法访问编辑器基控件"));
		return Variant();
	}
	// TASK-014 D-2 / GDR-20 point 10: the headless display server's dummy
	// renderer has no texture storage, so `get_texture().get_image()` below would
	// only log an engine error and answer null. Ask the display server first and
	// refuse with `-32000` + a suggestion (a capability this process does not
	// have), never with `-32603` (which is reserved for a genuine internal
	// error) and never with a blank picture.
	if (!game_framebuffer_available()) {
		r_error = MCPToolError::tool_state(
				String::utf8("编辑器没有可读取的帧缓冲（headless display server 没有纹理存储）"),
				String::utf8("用带 display server 的编辑器进程重跑（去掉 --headless，或换用带渲染驱动的构建）后再次调用"));
		return Variant();
	}
	Viewport *viewport = base_control->get_viewport();
	Ref<ViewportTexture> texture = viewport != nullptr ? viewport->get_texture() : Ref<ViewportTexture>();
	Ref<Image> image = texture.is_valid() ? texture->get_image() : Ref<Image>();
	if (image.is_null() || image->is_empty()) {
		// Not an internal error either: the viewport exists but has produced no
		// readable image yet. The suggestion says what to do about it.
		r_error = MCPToolError::tool_state(
				String::utf8("编辑器视口没有可读取的图像数据"),
				String::utf8("在编辑器至少绘制过一帧之后再次调用 editor_capture_screenshot"));
		return Variant();
	}

	Dictionary result;
	result["width"] = image->get_width();
	result["height"] = image->get_height();

	if (target.is_empty()) {
		const Vector<uint8_t> png = image->save_png_to_buffer();
		if (png.is_empty()) {
			// A real internal error: the image was there and could not be
			// encoded. `-32603` keeps its one meaning (GDR-20 point 10).
			r_error = MCPToolError::internal(String::utf8("截图获取失败, 请重试"));
			return Variant();
		}
		result["image_base64"] = CryptoCore::b64_encode_str(png.ptr(), (size_t)png.size());
		return result;
	}

	Ref<Image> held = image;
	const Error save_error = publish_file_atomically(target, screenshot_png_writer, &held);
	if (save_error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to save the screenshot to '%s' (error %d)", target, (int)save_error));
		return Variant();
	}
	result["saved_path"] = target;
	return result;
#endif
	return Variant();
}

// ---------------------------------------------------------------------------
// editor_remove_output_log (old `clear_output`, editor.rs:421) -- fix-first
//
// The migration source printed about fifty empty lines to stdout and answered
// `{"cleared": true}`; the Output panel kept every message, so the tool *always*
// lied. TASK-008 section 2 asked for a red test that proves it and then a fix, in
// this order:
//
//   (a) find the real clearing path - `EditorNode::get_log()->clear()`, which is
//       the very operation the panel's own *Clear* button is wired to
//       (`EditorLog::clear()` -> `_clear_request()`, editor_log.cpp:257-266 and
//       the `pressed` connection at editor_log.cpp:542);
//   (b) never report a success that did not happen.
//
// Both are implemented: the guard runs *first*, so a process without an editor
// log gets `-32000` instead of `{"cleared": true}`; with a real log the tool
// measures the panel content immediately before and after the clear and reports
// it as `log_was_empty` / `log_is_empty`. `null` in either field means the panel
// view could not be located, i.e. "not measured" - never "was empty".
//
// The measured view is the dock's RichTextLabel. `EditorLog` keeps it private and
// `editor/editor_log.h` is outside this module, so it is reached through the scene
// tree; it is the dock's only RichTextLabel descendant (`bbcode_parser` is never
// added as a child, editor_log.cpp:377-381).
// ---------------------------------------------------------------------------
#ifdef MCP_EDITOR_TOOLS_ENABLED
static RichTextLabel *_find_rich_text_label(Node *p_node) {
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
		label = _find_rich_text_label(child);
		if (label != nullptr) {
			return label;
		}
	}
	return nullptr;
}
#endif

static Variant _tool_remove_output_log(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	// (b) runs before anything else: with no editor UI there is nothing that
	// could have been cleared, so no success may be reported.
	if (!require_editor_ui(r_error, "editor writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	EditorNode *editor_node = EditorNode::get_singleton();
	EditorLog *log = editor_node != nullptr ? EditorNode::get_log() : nullptr;
	if (log == nullptr) {
		r_error = MCPToolError::not_implemented("the editor output log (this process has no EditorLog)",
				"Start the MCP server inside the Godot editor to clear the Output panel");
		return Variant();
	}

	RichTextLabel *view = _find_rich_text_label(log);
	const bool measured = view != nullptr;
	const bool was_empty = measured ? view->get_parsed_text().is_empty() : false;

	// (a) the real clearing path: exactly what the panel's Clear button calls.
	log->clear();

	const bool is_empty = measured ? view->get_parsed_text().is_empty() : false;

	Dictionary result;
	result["cleared"] = true;
	result["log_was_empty"] = measured ? Variant(was_empty) : Variant();
	result["log_is_empty"] = measured ? Variant(is_empty) : Variant();
	return result;
#endif
	return Variant();
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

// The authoritative `description` and `inputSchema` of each tool are the contract
// entries of docs/tools_list.renamed.json, character for character. The schemas
// are *parsed* from the exact contract JSON instead of being rebuilt as a
// hand-written Dictionary, because the gate compares all three fields verbatim.
//
// Unlike `editor_read_scene_inspector.cpp` this group's schemas contain no
// numbers at all (no `default`, no `minimum`), so the integral-number folding
// that file needs to survive Godot's single number type has nothing to fold here
// and is not repeated.
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_write_scene_editor.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_write_scene_editor_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_open_scene", String::utf8(R"desc(在编辑器中打开场景)desc"));
		builder.channel("editor").verb("open").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"path":{"description":"res:// 路径","type":"string"}},"required":["path"],"type":"object"})schema"));
		builder.handler(_tool_open_scene).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_save_scene", String::utf8(R"desc(保存当前场景)desc"));
		builder.channel("editor").verb("save").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"path":{"description":"保存路径 (可选)","type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_save_scene).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_reload_plugin", String::utf8(R"desc(重新加载 MCP 插件 When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them.)desc"));
		builder.channel("editor").verb("reload").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{},"required":[],"type":"object"})schema"));
		builder.handler(_tool_reload_plugin).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_rescan_project_filesystem", String::utf8(R"desc(重新扫描项目文件系统)desc"));
		builder.channel("editor").verb("rescan").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{},"required":[],"type":"object"})schema"));
		builder.handler(_tool_rescan_project_filesystem).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_node_selection", String::utf8(R"desc(选中/取消选中场景中的节点)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"focus":{"description":"是否聚焦节点 (可选，默认同 inspect)","type":"boolean"},"inspect":{"description":"是否在检查器中显示 (可选，默认 true)","type":"boolean"},"mode":{"description":"模式: replace, add, remove (可选，默认 replace)","type":"string"},"node_path":{"description":"单个节点路径 (与 node_paths 二选一)","type":"string"},"node_paths":{"description":"节点路径数组","items":{"type":"string"},"type":"array"}},"type":"object"})schema"));
		builder.handler(_tool_set_node_selection).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_remove_node_selection", String::utf8(R"desc(清除编辑器中的所有选中)desc"));
		builder.channel("editor").verb("remove").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{},"type":"object"})schema"));
		builder.handler(_tool_remove_node_selection).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_add_resource_to_node_property", String::utf8(R"desc(创建资源并附加到节点属性)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"description":"节点路径","type":"string"},"property":{"description":"属性名称","type":"string"},"resource_properties":{"description":"要设置的资源属性 (可选)","type":"object"},"resource_type":{"description":"资源类型 (如 GradientTexture1D, StyleBoxFlat)","type":"string"}},"required":["node_path","property","resource_type"],"type":"object"})schema"));
		builder.handler(_tool_add_resource_to_node_property).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_viewport_3d_camera", String::utf8(R"desc(设置编辑器 3D 视口相机参数)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"fov":{"description":"视场角 (度)","type":"number"},"look_at":{"additionalProperties":true,"description":"看向目标 {x, y, z}","type":"object"},"position":{"additionalProperties":true,"description":"位置 {x, y, z}","type":"object"},"rotation_degrees":{"additionalProperties":true,"description":"旋转角度 {x, y, z}","type":"object"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_set_viewport_3d_camera).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_capture_screenshot", String::utf8(R"desc(获取编辑器视口截图 (返回 base64 PNG 或保存到文件))desc"));
		builder.channel("editor").verb("capture").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"save_path":{"description":"保存路径 (res:// 或 user://, 可选)","type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_capture_screenshot).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_remove_output_log", String::utf8(R"desc(清除编辑器输出面板)desc"));
		builder.channel("editor").verb("remove").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{},"required":[],"type":"object"})schema"));
		builder.handler(_tool_remove_output_log).register_into(r_registry);
	}
}
