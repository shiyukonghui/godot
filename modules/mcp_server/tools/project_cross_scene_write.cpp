/**************************************************************************/
/*  project_cross_scene_write.cpp                                         */
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
#include "project_cross_scene_write.h"

#include "running_game_node_write.h"
#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/io/resource_loader.h"
#include "core/io/resource_saver.h"
#include "core/object/class_db.h"
#include "core/os/memory.h"
#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/resources/packed_scene.h"

// The compile-time half of the editor guard (TASK-002 section 2.2.3). The group
// is `scope = both`, so the closed-scene write is the whole tool in a game
// process; only the "which scenes does this editor have open" question is
// editor-only, and in a game process the answer is "none".
#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/editor_interface.h"
#include "editor/file_system/editor_file_system.h"
#endif

using namespace MCPTools;

// ---------------------------------------------------------------------------
// project_set_node_property_across_scenes (old `cross_scene_set_property`,
// batch.rs:257)
//
// Observable contract (as implemented):
//   * `type` (string, required, non-blank) must be an existing `Node` class -
//     the argument names a class, so a class that does not exist is `-32602`
//     (the migration source matched nothing and answered a success);
//   * `property` (string, required, non-blank);
//   * `value` (**required, any JSON type** - presence, not nullness);
//   * `path_filter` (string, optional, default `res://`): a project directory;
//   * `exclude_addons` (bool, optional, default true);
//   * `force` (bool, optional, default false): allow the *active* edited scene
//     to be edited (see below);
//   * `dry_run` (bool, optional, default `not force`): plan only, write nothing;
//   * answer: `{"type","property","dry_run","force","path_filter",
//     "scenes_affected":[{"scene","nodes","count","mode","written","persisted"}],
//     "skipped_open_scenes":[{"scene","reason"}],"errors":[],
//     "total_scenes","total_nodes","editor_rescan_triggered","message"}`, where
//     `mode` is one of `"dry_run"`, `"offline_saved"` or
//     `"live_open_scene_written"`, and every entry carries two booleans that say
//     the same thing without the caller having to know the `mode` vocabulary:
//     `written` (this call changed the scene's value somewhere) and `persisted`
//     (the new value is on disk, so it survives the editor's own next save).
//
// The active edited scene (**TASK-030 D1**): writing its file on disk while the
// editor holds the same scene in memory is a lost update - the editor's next
// `editor_save_scene` repacks its own in-memory tree and overwrites whatever was
// written - so this scene is not written to disk by this tool. It used to be
// planned and validated on a **detached** copy of the file (`ResourceLoader::load`
// with `CACHE_MODE_IGNORE` + `instantiate()`), that copy was edited, and the call
// answered `code: 0` + `mode: "live_open_scene"` + "edited in memory" while the
// live nodes were never touched: the caller's next save then persisted the OLD
// value (silent data loss, M4d D1).
//
// The active scene is therefore now written where the editor can see it and the
// caller's save will keep it: `edited_scene_root()` is the editor-synchronised
// live tree, and the plan, the write, the **read-back verification** and the
// `EditorInterface::mark_scene_as_unsaved()` call all happen on those very nodes.
// A live write that does not read back as the value that was written is
// **undone** (every node the call already changed is restored from the value read
// before the write) and the call fails - a live edit may never end in "success +
// not written" any more than a disk write may.
//
// The transaction and the divergences from the migration source are documented
// in `project_cross_scene_write.h`; what follows is the implementation of that
// contract.
// ---------------------------------------------------------------------------

namespace MCPTools {

void collect_scene_files(const String &p_path_filter, bool p_exclude_addons, Vector<String> &r_out) {
	r_out.clear();
	Vector<String> files;
	Vector<String> extensions;
	extensions.push_back("tscn");
	// The hoisted walker (`tools/tool_helpers.*`): hidden entries are skipped and
	// the extension test is case insensitive, exactly like the migration source's
	// `_collect_scene_files` (batch.rs:372-391), which also looked at `.tscn`
	// only.
	collect_files_by_extension(p_path_filter, extensions, !p_exclude_addons, files);
	for (int i = 0; i < files.size(); i++) {
		r_out.push_back(files[i]);
	}
	// Deterministic order (PLAYBOOK section 6.8): the migration source answered in
	// `DirAccess` order, which is not part of any contract and differs between
	// runs on a filesystem whose directory enumeration is unsorted.
	r_out.sort();
}

} // namespace MCPTools

// One scene's plan: the packed scene, the instance that carries the matching
// nodes, the nodes themselves and the value that has already been validated for
// every one of them.
struct _PlannedScene {
	String path;
	Ref<PackedScene> packed;
	Node *instance = nullptr;
	// `false` exactly for the active edited scene (TASK-030 D1): `instance` is
	// then the **live** tree the editor owns, so this call may never delete it.
	bool owns_instance = true;
	Vector<Node *> nodes;
	String mode; // "offline_saved" | "live_open_scene_written" | "dry_run"
};

// Drops every instance this call loaded itself. The live edited scene is not one
// of them: deleting it would take the editor's scene away from under the user.
static void _release_planned_scenes(Vector<_PlannedScene> &p_planned) {
	for (int i = 0; i < p_planned.size(); i++) {
		if (p_planned[i].owns_instance && p_planned[i].instance != nullptr) {
			memdelete(p_planned[i].instance);
		}
	}
	p_planned.clear();
}

// "Is the value that came back the value that was written?"
//
// `Variant::operator==` is `hash_compare`, which answers `false` for an `INT`
// next to a `FLOAT` holding the same number, so the two numeric types are
// compared numerically. For every other pair the types have to agree: the
// read-back goes through the property's own declared type and
// `coerce_to_property_type` already produced that type, so a differing
// non-numeric type is a real disagreement, not a spelling difference.
static bool _values_agree(const Variant &p_read_back, const Variant &p_written) {
	if (p_read_back.get_type() == p_written.get_type()) {
		return p_read_back == p_written;
	}
	const Variant::Type read_type = p_read_back.get_type();
	const Variant::Type written_type = p_written.get_type();
	const bool read_numeric = (read_type == Variant::INT || read_type == Variant::FLOAT);
	const bool written_numeric = (written_type == Variant::INT || written_type == Variant::FLOAT);
	if (read_numeric && written_numeric) {
		return (double)p_read_back == (double)p_written;
	}
	return false;
}

namespace MCPTools {

// TASK-030 D1: the live half of the commit - what the **active edited scene**
// gets instead of a file rewrite, so the caller's own next `editor_save_scene`
// keeps the new value instead of overwriting it with the old one.
//
// `p_nodes` are the already matched live nodes (all of them under the tree
// `edited_scene_root()` answered; the caller owns that tree and must not delete
// it). Every step is paired with the step that can undo it:
//
//   * the value is validated per node with `prepare_node_property_value`
//     **before** anything is written (the same rule the file half uses);
//   * the value the path holds right now is read first, so a node this call has
//     already changed can be put back;
//   * after every write the path is read back and compared with the value that
//     was written (`_values_agree`). A node that does not agree makes the whole
//     live edit fail **and be undone** - "reported as written, not written" is
//     the defect this function exists to remove, and it is not allowed to
//     reappear as "written, then silently lost".
//
// Returns true when every node holds the new value; false with `r_error` when it
// does not, in which case every node this call changed has been restored to the
// value it held before.
//
// Declared in the header and not `static` for one reason: the doctest binary has
// no `SceneTree` at all, so the only way to assert the live write (including its
// read-back) is through an entry point that takes the nodes instead of resolving
// the edited scene - the same reason `prepare_node_property_value` is public.
bool write_live_scene_property(const Vector<Node *> &p_nodes, const String &p_property, const Variant &p_raw_value,
		MCPToolError &r_error) {
	Vector<Node *> changed;
	Vector<Variant> previous_values;

	for (int i = 0; i < p_nodes.size(); i++) {
		Node *node = p_nodes[i];
		const String node_name = String(node->get_name());

		Variant converted;
		MCPToolError value_error;
		if (!prepare_node_property_value(node, p_property, p_raw_value, converted, value_error)) {
			r_error = value_error;
			break;
		}

		bool had_value = false;
		MCPToolError read_error;
		const Variant old_value = read_node_property_path(node, p_property, had_value, read_error);
		if (!had_value) {
			r_error = MCPToolError::tool_state(vformat(
					"Node '%s' does not currently hold '%s', so a live edit of it could not be undone if the editor refused the value",
					node_name, p_property),
					"Do not force a write on the active open scene for a property path the node does not currently expose; "
					"editor_set_node_property refuses such a path before writing anything");
			break;
		}

		MCPToolError apply_error;
		if (!apply_node_property_value(node, p_property, converted, apply_error)) {
			r_error = apply_error;
			break;
		}
		changed.push_back(node);
		previous_values.push_back(old_value);

		bool read_back_valid = false;
		MCPToolError read_back_error;
		const Variant read_back = read_node_property_path(node, p_property, read_back_valid, read_back_error);
		if (!read_back_valid || !_values_agree(read_back, converted)) {
			r_error = MCPToolError::tool_state(vformat(
					"The live node '%s' did not read '%s' back as the value that was written to it (%s read back, %s written), so the live edit was undone",
					node_name, p_property,
					read_back_valid ? read_back.stringify() : String("<not readable>"), converted.stringify()),
					"The editor holds the tree this tool writes; if a property cannot be read back, write it through editor_set_node_property, which reports the same read-back");
			break;
		}
	}

	if (!r_error.is_error()) {
		return true;
	}

	// Undo in reverse order: every node this call changed goes back to the value
	// that was read from it before the write.
	Array restored;
	for (int i = changed.size() - 1; i >= 0; i--) {
		MCPToolError restore_error;
		if (apply_node_property_value(changed[i], p_property, previous_values[i], restore_error)) {
			restored.push_back(String(changed[i]->get_name()));
		}
	}
	Dictionary data = r_error.data.get_type() == Variant::DICTIONARY ? (Dictionary)r_error.data : Dictionary();
	data["live_nodes_restored"] = restored;
	r_error.data = data;
	return false;
}

} // namespace MCPTools

static void _collect_matching_nodes(Node *p_node, const StringName &p_type, Vector<Node *> &r_out) {
	if (p_node->get_class() == String(p_type) || p_node->is_class(p_type)) {
		r_out.push_back(p_node);
	}
	const int child_count = p_node->get_child_count();
	for (int i = 0; i < child_count; i++) {
		_collect_matching_nodes(p_node->get_child(i), p_type, r_out);
	}
}

// The node path relative to the scene root, i.e. the migration source's
// `root.get_path_to(node)` (`batch.rs:397`).
//
// It is computed by walking the parent chain instead of calling
// `Node::get_path_to()`, because the scene the tool plans and saves is an
// *instantiated but unattached* tree: `Node::get_path_to()` is an
// `ERR_FAIL_COND_V(!is_inside_tree(), NodePath())` (scene/main/node.cpp), so on
// an unattached scene it answers an empty path and prints an engine error - the
// migration source's `nodes` list was therefore empty for exactly the case this
// tool is used in. The root itself is "." (the migration source's spelling).
static String _relative_node_path(const Node *p_root, const Node *p_node) {
	if (p_root == p_node) {
		return ".";
	}
	Vector<String> parts;
	const Node *current = p_node;
	while (current != nullptr && current != p_root) {
		parts.push_back(String(current->get_name()));
		current = current->get_parent();
	}
	if (current != p_root) {
		// Not below the root. Unreachable through `_collect_matching_nodes`; kept
		// so the answer always names something rather than an empty string.
		return String(p_node->get_name());
	}
	String path;
	for (int i = parts.size() - 1; i >= 0; i--) {
		if (!path.is_empty()) {
			path += "/";
		}
		path += parts[i];
	}
	return path;
}

// The editor's open scenes, or an empty list in a game process / without an
// editor. Wrapped so the game build simply has no editor include.
static bool _is_scene_open_in_editor(const String &p_path) {
#ifdef MCP_EDITOR_TOOLS_ENABLED
	if (!is_editor_process()) {
		return false;
	}
	EditorInterface *editor = EditorInterface::get_singleton();
	if (editor == nullptr) {
		return false;
	}
	const PackedStringArray open_scenes = editor->get_open_scenes();
	for (int i = 0; i < open_scenes.size(); i++) {
		if (String(open_scenes[i]) == p_path) {
			return true;
		}
	}
#endif
	(void)p_path;
	return false;
}

// The scene the editor is editing right now, as a project path (empty when there
// is none). `edited_scene_root()` is the editor-synchronised mirror; see
// tool_helpers.h for why it is not `EditorInterface::get_edited_scene_root()`.
static String _active_edited_scene_path() {
	Node *root = edited_scene_root();
	return root != nullptr ? root->get_scene_file_path() : String();
}

static void _mark_active_scene_unsaved() {
#ifdef MCP_EDITOR_TOOLS_ENABLED
	if (!is_editor_process()) {
		return;
	}
	EditorInterface *editor = EditorInterface::get_singleton();
	if (editor != nullptr) {
		// The live edit changed the in-memory scene without saving it; the editor
		// has to know, or the next save would lose it.
		editor->mark_scene_as_unsaved();
	}
#endif
}

static bool _notify_editor_of_scene_writes() {
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

// The writer for `publish_file_atomically`: a PackedScene into a temporary
// sibling that keeps the `.tscn` extension (the saver recognises the format by
// the text after the *last* dot, REPORT-007 section 8.1).
static Error _packed_scene_writer(const String &p_temp_path, void *p_userdata) {
	const Ref<PackedScene> *packed = static_cast<const Ref<PackedScene> *>(p_userdata);
	Ref<Resource> resource = *packed;
	return ResourceSaver::save(resource, p_temp_path);
}

namespace MCPTools {

bool set_node_property_across_scenes(const String &p_path_filter, const String &p_type, const String &p_property,
		const Variant &p_value, bool p_exclude_addons, bool p_force, bool p_dry_run,
		Dictionary &r_out, MCPToolError &r_error) {
	if (p_type.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'type' must not be empty");
		return false;
	}
	if (p_property.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'property' must not be empty");
		return false;
	}
	// `type` names a class, so a class that does not exist is a malformed
	// argument - never an empty success.
	const StringName type_name(p_type);
	if (!ClassDB::class_exists(type_name)) {
		r_error = MCPToolError::invalid_params(vformat("Type '%s' is not an engine class", p_type));
		return false;
	}
	if (!ClassDB::is_parent_class(type_name, StringName("Node"))) {
		r_error = MCPToolError::invalid_params(vformat("Type '%s' is not a Node subclass", p_type));
		return false;
	}

	String path_filter;
	if (!normalize_project_path(p_path_filter, path_filter, r_error)) {
		return false;
	}

	Vector<String> scene_files;
	collect_scene_files(path_filter, p_exclude_addons, scene_files);

	const String active_scene = _active_edited_scene_path();

	// -----------------------------------------------------------------------
	// Phase 1 - plan. Nothing is written; every refusal is collected so the
	// answer names all of them at once instead of only the first.
	// -----------------------------------------------------------------------
	Vector<_PlannedScene> planned;
	Array skipped_open_scenes;
	Array errors;

	for (int i = 0; i < scene_files.size(); i++) {
		const String scene_path = scene_files[i];
		const bool is_active = !active_scene.is_empty() && scene_path == active_scene;
		const bool is_open = is_active || _is_scene_open_in_editor(scene_path);
		if (is_open && !p_force) {
			Dictionary entry;
			entry["scene"] = scene_path;
			entry["reason"] = "open in the editor; pass force=true to edit the active scene in memory (a disk write "
							  "would be overwritten by the editor's own next save)";
			skipped_open_scenes.push_back(entry);
			continue;
		}
		if (is_open && !is_active) {
			Dictionary entry;
			entry["scene"] = scene_path;
			entry["reason"] = "open in the editor but not the active edited scene";
			skipped_open_scenes.push_back(entry);
			continue;
		}

		// TASK-030 D1: the active edited scene is **not** loaded from disk. The
		// file is the editor's own input, and the tree the editor has in memory is
		// the one the caller's next save will persist: planning and writing a
		// detached copy of the file would answer "edited in memory" about a tree
		// nobody will ever see. So the live root is the instance here, and it is
		// owned by the editor - this call must never delete it.
		Node *instance = nullptr;
		bool owns_instance = true;
		Ref<PackedScene> packed;
		if (is_active) {
			instance = edited_scene_root();
			if (instance == nullptr || instance->get_scene_file_path() != scene_path) {
				// The editor moved on between the `active_scene` read above and
				// this line. Refusing is the only honest answer: there is no tree
				// this call may write that would become the caller's save.
				Dictionary entry;
				entry["scene"] = scene_path;
				entry["reason"] = "the editor's edited scene root is no longer this scene";
				errors.push_back(entry);
				continue;
			}
			owns_instance = false;
		} else {
			// The loaded scene is instantiated once and kept alive through the
			// commit phase: the same instance is what gets packed and saved, so
			// the write cannot disagree with what was validated.
			packed = ResourceLoader::load(scene_path, "PackedScene", ResourceLoader::CACHE_MODE_IGNORE);
			if (packed.is_null()) {
				Dictionary entry;
				entry["scene"] = scene_path;
				entry["reason"] = "not a loadable PackedScene";
				errors.push_back(entry);
				continue;
			}
			instance = packed->instantiate();
			if (instance == nullptr) {
				Dictionary entry;
				entry["scene"] = scene_path;
				entry["reason"] = "the PackedScene could not be instantiated";
				errors.push_back(entry);
				continue;
			}
		}

		Vector<Node *> matched;
		_collect_matching_nodes(instance, type_name, matched);
		Vector<Node *> accepted;
		for (int n = 0; n < matched.size(); n++) {
			Variant converted;
			MCPToolError value_error;
			if (!prepare_node_property_value(matched[n], p_property, p_value, converted, value_error)) {
				Dictionary entry;
				entry["scene"] = scene_path;
				entry["node"] = _relative_node_path(instance, matched[n]);
				entry["reason"] = value_error.message;
				errors.push_back(entry);
				break;
			}
			accepted.push_back(matched[n]);
		}
		if (accepted.size() != matched.size()) {
			// The instance is dropped again: this scene does not enter the
			// transaction, and phase 1 writes nothing anywhere.
			if (owns_instance) {
				memdelete(instance);
			}
			continue;
		}

		if (accepted.is_empty()) {
			// The scene simply contains no node of that type. It is not an error
			// and it is not part of the answer's `scenes_affected`.
			if (owns_instance) {
				memdelete(instance);
			}
			continue;
		}

		_PlannedScene plan;
		plan.path = scene_path;
		plan.packed = packed;
		plan.instance = instance;
		plan.owns_instance = owns_instance;
		plan.nodes = accepted;
		plan.mode = p_dry_run ? "dry_run" : (is_active ? "live_open_scene_written" : "offline_saved");
		planned.push_back(plan);
	}

	if (!errors.is_empty()) {
		// All-or-nothing: a scene that cannot be loaded, or a matched node whose
		// value does not fit, refuses the whole call before a single write. This
		// is the "deliberately broken middle file" case, and the error names the
		// file(s) so the caller can fix the project rather than guess.
		Vector<String> named;
		for (int i = 0; i < errors.size(); i++) {
			named.push_back(String(((Dictionary)errors[i])["scene"]));
		}
		MCPToolError error = MCPToolError::tool_state(vformat(
				"Refusing to write: %d scene(s) of '%s' cannot take this call",
				errors.size(), path_filter),
				"Nothing was written. Fix every file named in data.scenes.errors (a scene that does not load, or a "
				"node of the named type that does not declare the property / cannot hold the value) and call again");
		Dictionary envelope;
		envelope["errors"] = errors;
		envelope["scenes_named"] = named;
		envelope["planned_before_refusal"] = Array();
		Dictionary data = error.data;
		data["scenes"] = envelope;
		error.data = data;
		r_error = error;
		_release_planned_scenes(planned);
		return false;
	}

	// -----------------------------------------------------------------------
	// Phase 2 - commit. The original bytes of every file that is about to be
	// replaced are kept in memory first, so a failure in the middle can put all
	// of them back. The live write of the active edited scene is committed
	// **after** every file, because it is the one target that is not on disk
	// (see `write_live_scene_property`).
	// -----------------------------------------------------------------------
	Array scenes_affected;
	Array rollback;
	int64_t total_nodes = 0;
	int64_t disk_scenes = 0;
	int64_t live_scenes = 0;
	String live_scene_path;

	if (!p_dry_run) {
		Vector<String> to_write;
		for (int i = 0; i < planned.size(); i++) {
			if (planned[i].mode == "offline_saved") {
				to_write.push_back(planned[i].path);
			}
		}
		Vector<Vector<uint8_t>> originals;
		for (int i = 0; i < to_write.size(); i++) {
			Error read_error = OK;
			originals.push_back(FileAccess::get_file_as_bytes(to_write[i], &read_error));
			if (read_error != OK) {
				_release_planned_scenes(planned);
				r_error = MCPToolError::internal(vformat("Cannot read the current bytes of '%s' before writing it: %s",
						to_write[i], VariantUtilityFunctions::error_string(read_error)));
				return false;
			}
		}

		// (a) every closed scene: edit the detached instance, pack it, publish it
		// atomically. A failure puts back every file this call already replaced.
		int written_count = 0;
		for (int i = 0; i < planned.size(); i++) {
			_PlannedScene &plan = planned.write[i];
			if (plan.mode != "offline_saved") {
				continue;
			}
			for (int n = 0; n < plan.nodes.size(); n++) {
				Variant converted;
				MCPToolError value_error;
				// Phase 1 validated every node; this cannot fail, and it is not
				// allowed to silently do nothing if it somehow does.
				if (!prepare_node_property_value(plan.nodes[n], p_property, p_value, converted, value_error)) {
					value_error.message = vformat("Scene '%s': %s", plan.path, value_error.message);
					r_error = value_error;
					_release_planned_scenes(planned);
					return false;
				}
				// TASK-028 G-1: the same write the node family uses, so a
				// `position:y`-style property path writes the component here too.
				MCPToolError apply_error;
				if (!apply_node_property_value(plan.nodes[n], p_property, converted, apply_error)) {
					apply_error.message = vformat("Scene '%s': %s", plan.path, apply_error.message);
					r_error = apply_error;
					_release_planned_scenes(planned);
					return false;
				}
			}

			Ref<PackedScene> rebuilt;
			rebuilt.instantiate();
			const Error pack_error = rebuilt->pack(plan.instance);
			if (pack_error != OK) {
				r_error = MCPToolError::internal(vformat("Failed to pack scene '%s': %s",
						plan.path, VariantUtilityFunctions::error_string(pack_error)));
				_release_planned_scenes(planned);
				return false;
			}
			Ref<PackedScene> held = rebuilt;
			const Error save_error = publish_file_atomically(plan.path, _packed_scene_writer, &held);
			if (save_error != OK) {
				// Roll back every file this call already replaced.
				for (int k = 0; k < written_count; k++) {
					Ref<FileAccess> file = FileAccess::open(to_write[k], FileAccess::WRITE);
					if (file.is_valid()) {
						file->store_buffer(originals[k].ptr(), originals[k].size());
						file->close();
						rollback.push_back(to_write[k]);
					}
				}
				MCPToolError error = MCPToolError::internal(vformat(
						"Failed to save scene '%s': %s. %d earlier scene(s) were restored from their original bytes",
						plan.path, VariantUtilityFunctions::error_string(save_error), rollback.size()));
				Dictionary data = error.data.get_type() == Variant::DICTIONARY ? (Dictionary)error.data : Dictionary();
				data["rollback"] = rollback;
				error.data = data;
				r_error = error;
				_release_planned_scenes(planned);
				return false;
			}
			written_count++;
		}

		// (b) the active edited scene: the live nodes, read back, marked unsaved.
		// Nothing that can fail runs after it, so a file failure can never leave a
		// half-applied live edit behind (and `write_live_scene_property` undoes its
		// own nodes if the editor refuses the value).
		for (int i = 0; i < planned.size(); i++) {
			_PlannedScene &plan = planned.write[i];
			if (plan.mode != "live_open_scene_written") {
				continue;
			}
			MCPToolError live_error;
			if (!write_live_scene_property(plan.nodes, p_property, p_value, live_error)) {
				// The live edit was undone by the callee; put back the files this
				// call already replaced too, so "all or nothing" keeps meaning all.
				for (int k = 0; k < written_count; k++) {
					Ref<FileAccess> file = FileAccess::open(to_write[k], FileAccess::WRITE);
					if (file.is_valid()) {
						file->store_buffer(originals[k].ptr(), originals[k].size());
						file->close();
						rollback.push_back(to_write[k]);
					}
				}
				live_error.message = vformat("Scene '%s' (the active open scene): %s", plan.path, live_error.message);
				Dictionary data = live_error.data.get_type() == Variant::DICTIONARY ? (Dictionary)live_error.data : Dictionary();
				data["rollback"] = rollback;
				live_error.data = data;
				r_error = live_error;
				_release_planned_scenes(planned);
				return false;
			}
			// The live edit changed the in-memory scene without saving it; the
			// editor has to know, or its own next save would discard it.
			_mark_active_scene_unsaved();
		}
	}

	for (int i = 0; i < planned.size(); i++) {
		Array nodes;
		for (int n = 0; n < planned[i].nodes.size(); n++) {
			nodes.push_back(_relative_node_path(planned[i].instance, planned[i].nodes[n]));
		}
		Dictionary entry;
		entry["scene"] = planned[i].path;
		entry["nodes"] = nodes;
		entry["count"] = nodes.size();
		entry["mode"] = planned[i].mode;
		// TASK-030 D1: the two booleans behind the `mode` vocabulary, so a caller
		// never has to guess which token means "this one was written" or whether
		// the new value survives the editor's own next save.
		entry["written"] = !p_dry_run;
		entry["persisted"] = (!p_dry_run && planned[i].mode == "offline_saved");
		scenes_affected.push_back(entry);
		total_nodes += nodes.size();
		if (planned[i].mode == "offline_saved") {
			disk_scenes++;
		} else if (planned[i].mode == "live_open_scene_written") {
			live_scenes++;
			live_scene_path = planned[i].path;
		}
	}

	// Only a real file replacement needs the editor to rescan; a live edit does
	// not touch anything the resource filesystem knows about.
	const bool rescan = (!p_dry_run && disk_scenes > 0) ? _notify_editor_of_scene_writes() : false;

	_release_planned_scenes(planned);

	// TASK-030 D5: the message has to describe the call that really ran. "Applied"
	// is reserved for a call that wrote something; a `path_filter` that matched no
	// scene says so instead of borrowing the sentence of a successful write, and a
	// live edit says that it is **not on disk yet**.
	// TASK-030 D5 + TASK-033 D-M4e-3: the message has to describe the call that
	// really ran. "Applied" is reserved for a call that wrote something; a
	// `path_filter` that wrote nothing says so - but the *reason* has to be the
	// real one. The single sentence that used to cover every empty case
	// ("'path_filter' names a directory that contains .tscn files, not a single
	// scene file") is only true for a filter that really names something the
	// walker cannot open:
	//
	//   * `DirAccess::open` - what `collect_files_by_extension` uses - fails on
	//     any path that is not a directory (`DirAccessWindows::change_dir` ends in
	//     `SetCurrentDirectoryW`, which answers 0 for a file), so a single `.tscn`
	//     filter really does match no scene and "name a directory" is the right
	//     advice for it. `FileAccess::exists` is what tells that case apart;
	//   * scenes that matched but are **open in the editor** and were skipped
	//     because `force` is false are a different case - the filter was right;
	//   * scenes that matched and hold **no node of the requested type** are a
	//     third one - that is the case the M4e re-audit's D-M4e-3 named (its
	//     claim that a single scene FILE "matched" was measured here to be false:
	//     `DirAccess::open` never opens a file, and TASK-030's own doctest pins
	//     that a scene-file filter matches nothing - see REPORT-033 section 3).
	//
	// So the sentence is now emitted only for the file case, and the two other
	// empty cases are named for what they are.
	const bool filter_is_file = FileAccess::exists(path_filter);
	String empty_prefix;
	String empty_note;
	if (filter_is_file) {
		empty_prefix = vformat("No scene matched '%s': nothing was written.", path_filter);
		empty_note = vformat("'%s' is a file, and 'path_filter' has to name a directory that contains .tscn files "
							 "(the walker opens a directory, and a single scene file is not one) - pass its base "
							 "directory and call again",
				path_filter);
	} else if (!skipped_open_scenes.is_empty()) {
		empty_prefix = vformat("%d scene(s) matched '%s' but nothing was written.", skipped_open_scenes.size(), path_filter);
		empty_note = skipped_open_scenes.size() == 1
				? "It is open in the editor: pass force=true to edit the active scene in memory (a disk write would be "
				  "overwritten by the editor's own next save), or close it and call again"
				: "They are open in the editor: pass force=true to edit the active scene in memory, or close them and "
				  "call again";
	} else if (!scene_files.is_empty()) {
		empty_prefix = vformat("%d scene(s) matched '%s' but nothing was written.", scene_files.size(), path_filter);
		empty_note = vformat("None of them contains a node of type '%s'; check 'type' and the scenes named by "
							 "'path_filter'",
				p_type);
	} else {
		empty_prefix = vformat("No scene matched '%s': nothing was written.", path_filter);
		empty_note = "'path_filter' names a directory that contains .tscn files; check it and call again";
	}

	String message;
	if (p_dry_run) {
		message = scenes_affected.is_empty()
				? vformat("Dry run: nothing was written. %s %s.", empty_prefix, empty_note)
				: vformat("Dry run: nothing was written. %d scene(s) / %d node(s) would be written; the closed scenes would be saved to disk and the active open scene would be edited in memory. Call again with force=true and dry_run=false to write.",
						(int64_t)scenes_affected.size(), total_nodes);
	} else if (scenes_affected.is_empty()) {
		message = vformat("%s %s.", empty_prefix, empty_note);
	} else if (live_scenes == 0) {
		message = vformat("Applied: %d closed scene(s) saved to disk (%d node(s) written). They are on disk and survive the editor's own next save.",
				disk_scenes, total_nodes);
	} else if (disk_scenes == 0) {
		message = vformat("Applied: the active open scene '%s' was edited in memory and marked unsaved (%d node(s) written). It is NOT on disk yet: call editor_save_scene to persist it.",
				live_scene_path, total_nodes);
	} else {
		message = vformat("Applied: %d closed scene(s) saved to disk, and the active open scene '%s' was edited in memory and marked unsaved (%d node(s) written in total). The closed scenes are on disk; the open scene is NOT on disk yet, so call editor_save_scene to persist it.",
				disk_scenes, live_scene_path, total_nodes);
	}

	Dictionary out;
	out["type"] = p_type;
	out["property"] = p_property;
	out["dry_run"] = p_dry_run;
	out["force"] = p_force;
	out["path_filter"] = path_filter;
	out["scenes_affected"] = scenes_affected;
	out["skipped_open_scenes"] = skipped_open_scenes;
	out["errors"] = Array();
	out["total_scenes"] = scenes_affected.size();
	out["total_nodes"] = total_nodes;
	out["editor_rescan_triggered"] = rescan;
	out["message"] = message;
	r_out = out;
	return true;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tool
// ---------------------------------------------------------------------------

static Variant _tool_across_scenes(const Dictionary &p_args, MCPToolError &r_error) {
	String type;
	if (!require_string(p_args, "type", type, r_error)) {
		return Variant();
	}
	String property;
	if (!require_string(p_args, "property", property, r_error)) {
		return Variant();
	}
	if (!p_args.has("value")) {
		r_error = MCPToolError::invalid_params("Missing required parameter 'value'");
		return Variant();
	}
	String path_filter;
	if (!optional_string(p_args, "path_filter", "res://", path_filter, r_error)) {
		return Variant();
	}
	bool exclude_addons = true;
	if (!optional_bool(p_args, "exclude_addons", true, exclude_addons, r_error)) {
		return Variant();
	}
	bool force = false;
	if (!optional_bool(p_args, "force", false, force, r_error)) {
		return Variant();
	}
	// `dry_run` defaults to `not force` - the migration source's rule
	// (batch.rs:283): a bare call previews, and asking to write means asking
	// explicitly. The default is answered in the result, so the caller can always
	// tell which mode ran.
	bool dry_run = !force;
	if (!optional_bool(p_args, "dry_run", dry_run, dry_run, r_error)) {
		return Variant();
	}
	Dictionary out;
	if (!set_node_property_across_scenes(path_filter, type, property, p_args["value"], exclude_addons, force, dry_run,
				out, r_error)) {
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
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_cross_scene_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_cross_scene_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_set_node_property_across_scenes", String::utf8(R"desc(跨场景批量设置节点属性)desc"));
		builder.channel("project").verb("set").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"dry_run":{"description":"仅预览，不实际修改","type":"boolean"},"exclude_addons":{"default":true,"description":"是否排除 addons 目录","type":"boolean"},"force":{"default":false,"description":"是否强制修改正在编辑的场景","type":"boolean"},"path_filter":{"description":"路径过滤，默认 res://","type":"string"},"property":{"description":"属性名","type":"string"},"type":{"description":"节点类型","type":"string"},"value":{"description":"属性值"}},"required":["type","property","value"],"type":"object"})schema"));
		builder.handler(_tool_across_scenes).register_into(r_registry);
	}
}
