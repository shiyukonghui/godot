/**************************************************************************/
/*  editor_read_scene_inspector.cpp                                       */
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
#include "editor_read_scene_inspector.h"

// TASK-024 E-6/G-4: the log tools report which process and which MCP endpoint
// answered (`MCPServer::get_port()`), so the process' own port is part of the
// provenance fields.
#include "../mcp_server.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/config/engine.h"
#include "core/error/error_macros.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/object/object.h"
#include "core/object/script_language.h"
#include "core/os/os.h"
#include "core/variant/callable.h"
#include "core/variant/variant.h"
#include "scene/3d/camera_3d.h"
#include "scene/gui/rich_text_label.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include "scene/main/viewport.h"

// ---------------------------------------------------------------------------
// The compile-time half of the editor guard (TASK-002 section 2.2.3). In a game
// build (`TOOLS_ENABLED` undefined) none of the includes below and none of the
// guarded call sites exist at all - the seven tools are still *compiled*, because
// the group file is shared, but every editor-only branch collapses into a clean
// -32000 answer.
// ---------------------------------------------------------------------------
#ifdef MCP_EDITOR_TOOLS_ENABLED
#include "editor/editor_data.h"
#include "editor/editor_interface.h"
#include "editor/editor_log.h"
#include "editor/editor_node.h"
#include "editor/scene/3d/node_3d_editor_plugin.h"
#include "editor/script/script_editor_plugin.h"
#endif

using namespace MCPTools;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

// Both log tools read exactly this path (`read_log_file`, editor.rs:147-152) and
// take no path argument, so there is nothing to normalise or validate.
static const char *LOG_PATH = "user://logs/godot.log";

// The runtime half of the editor guard lives in `tools/tool_helpers.*` since
// TASK-009 section 2.2 - one definition for every editor group instead of one
// copy per group file - and is called below as
// `require_editor_ui(r_error, <non-editor wording>, <suggestion>)`. The
// `EditorInterface` / `EditorNode` reasoning that used to be documented here is
// preserved next to that single definition.

// The scene the editor is editing, or nullptr when there is none.
//
// This goes through `SceneTree::get_edited_scene_root()` - the mirror the editor
// keeps in sync (`EditorNode::set_edited_scene_root`,
// `EditorNode::_set_current_scene_nocheck`) - instead of
// `EditorInterface::get_edited_scene_root()`, which is the same unchecked
// `EditorNode::get_singleton()` dereference as above and was measured to SIGSEGV
// in the doctest process (REPORT-004 section 9). It is also the same choice the
// `project_read_analysis` group already made.
static Node *_edited_scene_root() {
	SceneTree *tree = SceneTree::get_singleton();
	if (tree == nullptr) {
		return nullptr;
	}
	return tree->get_edited_scene_root();
}

// The tail window of `read_log_file` (editor.rs:147-177): the whole file is split
// on '\n' - *not* `str::lines()`, so the empty element a trailing newline
// produces is kept - and the last `max_lines` elements are returned.
//
// The reference clamps with `std::cmp::max(1, max_lines as usize)`; a
// non-positive `max_lines` casts to a huge `usize`, which means "no truncation at
// all" rather than "one line". That is reproduced here as `start = 0`.
// `r_exists` reports the reference's `source` marker ("no_log_file" when the log
// is absent; the caller turns it into "log_file" otherwise).
static Vector<String> _log_tail_lines(int64_t p_max_lines, bool &r_exists, MCPToolError &r_error) {
	Vector<String> lines;
	r_exists = FileAccess::exists(String(LOG_PATH));
	if (!r_exists) {
		return lines;
	}
	Ref<FileAccess> file = FileAccess::open(String(LOG_PATH), FileAccess::READ);
	if (file.is_null()) {
		// The reference maps this to an internal error as well.
		r_error = MCPToolError::internal("cannot open the log file 'user://logs/godot.log'");
		return lines;
	}
	const String content = file->get_as_text();
	file->close();

	const Vector<String> all = content.split("\n", true);
	const int total = all.size();
	int start = 0;
	if (p_max_lines >= 1 && (int64_t)total > p_max_lines) {
		start = total - (int)p_max_lines;
	}
	for (int i = start; i < total; i++) {
		lines.push_back(all[i]);
	}
	return lines;
}

// ---------------------------------------------------------------------------
// editor_get_errors (old `get_editor_errors`, editor.rs:270)
//
// The reference upper-cases every line and reports the ones containing "ERROR"
// (its two extra tests, "SCRIPT ERROR" and "PARSE ERROR", are already implied by
// that). The tail window is computed *before* this filter, which is observable:
// the final empty line of a log that ends in a newline can push every error out
// of a small `max_lines` window.
// ---------------------------------------------------------------------------

static Variant _tool_get_errors(const Dictionary &p_args, MCPToolError &r_error) {
	int64_t max_lines = 50;
	if (!optional_int(p_args, "max_lines", 50, max_lines, r_error)) {
		return Variant();
	}

	bool exists = false;
	const Vector<String> lines = _log_tail_lines(max_lines, exists, r_error);
	if (r_error.is_error()) {
		return Variant();
	}

	Array errors;
	for (int i = 0; i < lines.size(); i++) {
		if (lines[i].to_upper().contains("ERROR")) {
			errors.push_back(lines[i]);
		}
	}

	Dictionary result;
	result["errors"] = errors;
	result["count"] = errors.size();
	return result;
}

// ---------------------------------------------------------------------------
// editor_get_output_log (old `get_output_log`, editor.rs:290)
//
// Same tail window, then a *case sensitive* substring filter (`str::contains`).
// Note the name collision: this is the log *file*, not the editor Output panel
// (`editor_remove_output_log` of the write group is what touches the panel).
// ---------------------------------------------------------------------------

static Variant _tool_get_output_log(const Dictionary &p_args, MCPToolError &r_error) {
	int64_t max_lines = 100;
	if (!optional_int(p_args, "max_lines", 100, max_lines, r_error)) {
		return Variant();
	}
	String filter;
	if (!optional_string(p_args, "filter", String(), filter, r_error)) {
		return Variant();
	}

	bool exists = false;
	const Vector<String> lines = _log_tail_lines(max_lines, exists, r_error);
	if (r_error.is_error()) {
		return Variant();
	}

	Array out;
	for (int i = 0; i < lines.size(); i++) {
		if (filter.is_empty() || lines[i].contains(filter)) {
			out.push_back(lines[i]);
		}
	}

	Dictionary result;
	result["lines"] = out;
	result["count"] = out.size();
	// The reference's explicit marker: it is how a caller tells "the editor wrote
	// no log yet" from "the filter matched nothing".
	result["source"] = exists ? "log_file" : "no_log_file";
	return result;
}

// ---------------------------------------------------------------------------
// editor_get_open_scripts (old `get_open_scripts`, script.rs:137)
//
// The tabs the script editor has open, in tab order. `path` comes from the
// Script's resource path (the reference reads the `resource_path` property).
// ---------------------------------------------------------------------------

static Variant _tool_get_open_scripts(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	if (!require_editor_ui(r_error, "editor inspectors outside a running editor",
				"Start the MCP server inside the Godot editor to inspect the editor scene")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	ScriptEditor *script_editor = ScriptEditor::get_singleton();
	if (script_editor == nullptr) {
		r_error = MCPToolError::internal("Script editor not available");
		return Variant();
	}

	const Vector<Ref<Script>> open_scripts = script_editor->get_open_scripts();
	Array scripts;
	for (int i = 0; i < open_scripts.size(); i++) {
		const Ref<Script> script = open_scripts[i];
		Dictionary entry;
		entry["path"] = script.is_valid() ? script->get_path() : String();
		entry["type"] = script.is_valid() ? script->get_class() : String();
		scripts.push_back(entry);
	}

	Dictionary result;
	result["scripts"] = scripts;
	result["count"] = scripts.size();
	return result;
#endif
	// A game build has no editor API at all; `_require_editor_ui` has already
	// filled `r_error` in that case.
	return Variant();
}

// ---------------------------------------------------------------------------
// editor_get_scene_tree (old `get_scene_tree`, scene.rs:109)
//
// `max_depth` is the *reference's* semantics: `children` is emitted when
// `max_depth == -1 || depth < max_depth`, so `max_depth = 0` is the bare root,
// `1` adds the root's children and nothing deeper. There is no node cap in the
// reference - the recursion is bounded by the scene itself.
//
// `path` is `Node::get_path()`, i.e. the path from the scene-tree root, exactly
// as the reference writes it (inside the editor that is an editor-internal path
// such as `/root/@EditorNode@...`, not a path relative to the edited scene).
// ---------------------------------------------------------------------------

static Dictionary _build_scene_tree(Node *p_node, int64_t p_max_depth, int64_t p_depth) {
	Dictionary tree;
	tree["name"] = String(p_node->get_name());
	tree["type"] = p_node->get_class();
	tree["path"] = String(p_node->get_path());

	if (p_max_depth == -1 || p_depth < p_max_depth) {
		const int child_count = p_node->get_child_count();
		if (child_count > 0) {
			Array children;
			for (int i = 0; i < child_count; i++) {
				Node *child = p_node->get_child(i);
				if (child == nullptr) {
					continue;
				}
				children.push_back(_build_scene_tree(child, p_max_depth, p_depth + 1));
			}
			tree["children"] = children;
		}
	}
	return tree;
}

static Variant _tool_get_scene_tree(const Dictionary &p_args, MCPToolError &r_error) {
	int64_t max_depth = -1;
	if (!optional_int(p_args, "max_depth", -1, max_depth, r_error)) {
		return Variant();
	}

	Node *root = _edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}

	Dictionary result;
	result["scene_path"] = root->get_scene_file_path();
	result["tree"] = _build_scene_tree(root, max_depth, 0);
	return result;
}

// ---------------------------------------------------------------------------
// editor_get_selection (old `get_editor_selection`, node.rs:625)
//
// The selection, filtered to the edited scene: a node that is neither the root
// nor a descendant of it is skipped, and the root itself is spelled "." - the
// same rule the write group's selection tool will have to share.
// ---------------------------------------------------------------------------

static Variant _tool_get_selection(const Dictionary &p_args, MCPToolError &r_error) {
	bool top_only = false;
	if (!optional_bool(p_args, "top_only", false, top_only, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor inspectors outside a running editor",
				"Start the MCP server inside the Godot editor to inspect the editor scene")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	Node *root = _edited_scene_root();
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

	List<Node *> selected;
	if (top_only) {
		selected = selection->get_top_selected_node_list();
	} else {
		selected = selection->get_full_selected_node_list();
	}

	Array nodes;
	for (Node *node : selected) {
		if (node == nullptr) {
			continue;
		}
		// A node selected in another open scene is not part of this answer.
		if (node != root && !root->is_ancestor_of(node)) {
			continue;
		}
		Dictionary entry;
		entry["name"] = String(node->get_name());
		entry["path"] = node == root ? String(".") : String(root->get_path_to(node));
		entry["type"] = node->get_class();
		nodes.push_back(entry);
	}

	Dictionary result;
	result["nodes"] = nodes;
	result["count"] = nodes.size();
	result["top_only"] = top_only;
	return result;
#endif
	return Variant();
}

// ---------------------------------------------------------------------------
// editor_get_viewport_3d_camera (old `get_editor_camera`, editor.rs:630)
//
// The reference runs a GDScript snippet through `Expression` because its Rust
// bindings could not reach the 3D viewport; the values below are the same five
// keys, read through the real API. An absent viewport or camera is the
// reference's own "无法获取3D视口, 请确保已打开3D场景" internal error.
// ---------------------------------------------------------------------------

static Variant _tool_get_viewport_3d_camera(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	if (!require_editor_ui(r_error, "editor inspectors outside a running editor",
				"Start the MCP server inside the Godot editor to inspect the editor scene")) {
		return Variant();
	}
#ifdef MCP_EDITOR_TOOLS_ENABLED
	if (Node3DEditor::get_singleton() == nullptr) {
		r_error = MCPToolError::internal(String::utf8("无法获取3D视口, 请确保已打开3D场景"));
		return Variant();
	}
	EditorInterface *editor = EditorInterface::get_singleton();
	if (editor == nullptr) {
		r_error = MCPToolError::internal(String::utf8("无法获取3D视口, 请确保已打开3D场景"));
		return Variant();
	}
	SubViewport *viewport = editor->get_editor_viewport_3d();
	if (viewport == nullptr) {
		r_error = MCPToolError::internal(String::utf8("无法获取3D视口, 请确保已打开3D场景"));
		return Variant();
	}
	Camera3D *camera = viewport->get_camera_3d();
	if (camera == nullptr) {
		r_error = MCPToolError::internal(String::utf8("无法获取3D视口, 请确保已打开3D场景"));
		return Variant();
	}

	const Vector3 position = camera->get_global_position();
	const Vector3 rotation = camera->get_rotation_degrees();

	Dictionary position_json;
	position_json["x"] = position.x;
	position_json["y"] = position.y;
	position_json["z"] = position.z;

	Dictionary rotation_json;
	rotation_json["x"] = rotation.x;
	rotation_json["y"] = rotation.y;
	rotation_json["z"] = rotation.z;

	Dictionary result;
	result["position"] = position_json;
	result["rotation_degrees"] = rotation_json;
	result["fov"] = camera->get_fov();
	result["near"] = camera->get_near();
	result["far"] = camera->get_far();
	return result;
#endif
	return Variant();
}

// ---------------------------------------------------------------------------
// editor_analyze_signal_flow (old `analyze_signal_flow`, analysis.rs:387)
//
// GDR-17 kept this tool separate from `editor_list_signal_connections` (B3), and
// the contract description spells out the discriminators that must not drift:
// a per-node nesting (`nodes[]`, each with `signals_emitted` /
// `signals_connected_to`), persistent connections only, an exact `node_path`
// match, and no `signal_name` filter.
//
// Two deliberate deviations from the reference, both in the "the reference is
// broken, the tool must work" class of PLAYBOOK section 6.6:
//   1. its recursion looked nodes up *by name* with `get_node("<name>")` on the
//      scene root, so the root itself and anything deeper than a direct child
//      could never be resolved and were silently dropped;
//   2. its persistent test is `flags & 1`, which is `CONNECT_DEFERRED` in
//      Godot 4 (`core/object/object.h:356-360`) - a plain `.tscn` connection is
//      restored with `CONNECT_PERSIST` (`scene/resources/packed_scene.cpp:760`),
//      i.e. flags 2, so `flags & 1` reports nothing for an ordinary scene. The
//      intended `CONNECT_PERSIST` bit is tested here.
// Both are reported to the decision maker in REPORT-006.
// ---------------------------------------------------------------------------

static void _collect_signal_flow(Node *p_node, Node *p_root, Array &r_out) {
	const String node_path = p_node == p_root ? String(".") : String(p_root->get_path_to(p_node));

	Array signals_emitted;
	Array signals_connected_to;

	// `Object::get_signal_list()` fills a `List<MethodInfo>`, which is the same
	// list the GDScript binding `get_signal_list()` serialises into an Array:
	// script signals, ClassDB signals and user signals, in that order.
	List<MethodInfo> signal_list;
	p_node->get_signal_list(&signal_list);
	for (const MethodInfo &signal : signal_list) {
		const StringName signal_name = signal.name;
		if (signal_name == StringName()) {
			continue;
		}

		List<Object::Connection> connections;
		p_node->get_signal_connection_list(signal_name, &connections);
		Array targets;
		for (const Object::Connection &connection : connections) {
			// Persistent connections only. The reference spells this test as
			// `flags & 1`, which is `CONNECT_DEFERRED` in Godot 4 and
			// `CONNECT_PERSIST` in Godot 3 - so it drops exactly the ordinary
			// `.tscn` connections the description promises to report (see the
			// "known contract defect" note in the TASK-006 report). The
			// intended flag is used here instead.
			if ((connection.flags & Object::CONNECT_PERSIST) == 0) {
				continue;
			}
			const Callable &callable = connection.callable;
			Node *target = Object::cast_to<Node>(callable.get_object());
			if (target == nullptr) {
				continue;
			}
			// A target outside the edited scene is not part of this scene's flow.
			if (target != p_root && !p_root->is_ancestor_of(target)) {
				continue;
			}

			Dictionary target_entry;
			target_entry["target_node"] = String(p_root->get_path_to(target));
			target_entry["method"] = String(callable.get_method());
			targets.push_back(target_entry);

			Dictionary connection_entry;
			connection_entry["from_node"] = node_path;
			connection_entry["signal"] = String(signal_name);
			connection_entry["method"] = String(callable.get_method());
			signals_connected_to.push_back(connection_entry);
		}

		if (targets.size() > 0) {
			Dictionary emitted;
			emitted["signal"] = String(signal_name);
			emitted["targets"] = targets;
			signals_emitted.push_back(emitted);
		}
	}

	if (signals_emitted.size() > 0 || signals_connected_to.size() > 0) {
		Dictionary node_entry;
		node_entry["name"] = String(p_node->get_name());
		node_entry["path"] = node_path;
		node_entry["type"] = p_node->get_class();
		node_entry["signals_emitted"] = signals_emitted;
		node_entry["signals_connected_to"] = signals_connected_to;
		r_out.push_back(node_entry);
	}

	const int child_count = p_node->get_child_count();
	for (int i = 0; i < child_count; i++) {
		Node *child = p_node->get_child(i);
		if (child != nullptr) {
			_collect_signal_flow(child, p_root, r_out);
		}
	}
}

static Variant _tool_analyze_signal_flow(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!optional_string(p_args, "node_path", String(), node_path, r_error)) {
		return Variant();
	}

	Node *root = _edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}

	Node *start = root;
	if (!node_path.is_empty() && node_path != ".") {
		// An *exact* match: `has_node` resolves a path, it does not search for a
		// substring. That is the discriminator against
		// editor_list_signal_connections (GDR-17).
		const NodePath requested(node_path);
		if (!root->has_node(requested)) {
			r_error = MCPToolError::not_found(vformat("Node '%s'", node_path),
					"Use editor_get_scene_tree to list the nodes of the edited scene");
			return Variant();
		}
		start = root->get_node(requested);
	}

	Array nodes;
	_collect_signal_flow(start, root, nodes);

	Dictionary result;
	result["scene"] = root->get_scene_file_path();
	result["nodes"] = nodes;
	result["total_nodes"] = nodes.size();
	return result;
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

// The authoritative `description` and `inputSchema` of each tool are the contract
// entries of docs/tools_list.renamed.json, character for character. The schemas
// are therefore *parsed* from the exact contract JSON instead of being rebuilt as
// a hand-written Dictionary: a hand transcription is where a description byte or
// the type of a `"default": 50` drifts, and the gate compares all three fields
// verbatim.
//
// Godot's JSON has a single number type, so the parse turns every `"default": 50`
// into a float and `JSON::stringify` then writes it back as `50.0` - which is
// exactly the "type of a default drifted" failure the parse was meant to avoid.
// Integral numbers are therefore folded back to INT. The reference contract only
// ever uses integral numbers inside `inputSchema` (defaults, and integers in a
// `minimum`/`maximum`), so this is lossless for it.
static Variant _fold_integral_numbers(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::FLOAT: {
			const double number = p_value;
			if (number >= -9.0e15 && number <= 9.0e15) {
				const int64_t truncated = (int64_t)number;
				if ((double)truncated == number) {
					return Variant(truncated);
				}
			}
			return p_value;
		}
		case Variant::DICTIONARY: {
			const Dictionary source = p_value;
			Dictionary out;
			const Array keys = source.keys();
			for (int i = 0; i < keys.size(); i++) {
				out[keys[i]] = _fold_integral_numbers(source[keys[i]]);
			}
			return out;
		}
		case Variant::ARRAY: {
			const Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(_fold_integral_numbers(source[i]));
			}
			return out;
		}
		default:
			return p_value;
	}
}

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_read_scene_inspector.cpp");
		return Dictionary();
	}
	return _fold_integral_numbers(json.get_data());
}

void register_editor_read_scene_inspector_tools(MCPToolRegistry &r_registry) {
// @@REGISTRATION_BLOCK@@
}
