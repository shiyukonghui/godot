/**************************************************************************/
/*  editor_control_layout_write.cpp                                       */
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
#include "editor_control_layout_write.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/io/json.h"
#include "core/object/object.h"
#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
// This group is the only node write that needs the Control layout enums
// (`LayoutPreset` / `LayoutPresetMode`); the group note of
// docs/tool-groups-b3.json makes exactly that the reason it is alone.
#include "scene/gui/control.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"

using namespace MCPTools;

// The runtime half of the editor guard lives in `tools/tool_helpers.*` and is
// called below as `require_editor_ui(r_error, <non-editor wording>,
// <suggestion>)`.

// The migration source's own spelling for a node it returns, with the root as
// "." (`root.get_path_to(control)`, node.rs:463), is `MCPTools::relative_path`
// (`tools/tool_helpers.*`): the repair pass hoisted the copy this file used to
// carry.

// The legal `preset` names, in exactly the order the migration source lists them
// in its refusal message (node.rs:445) and the order the contract's description
// uses.
static const char *const LAYOUT_PRESET_NAMES[] = {
	"top_left", "top_right", "bottom_left", "bottom_right",
	"center_left", "center_top", "center_right", "center_bottom", "center",
	"left_wide", "top_wide", "right_wide", "bottom_wide",
	"vcenter_wide", "hcenter_wide", "full_rect"
};
static const int LAYOUT_PRESET_COUNT = 16;

// Index -> `Control::LayoutPreset`. A switch instead of a parallel table so a
// missing case is a compiler warning rather than a silent zero.
static Control::LayoutPreset _layout_preset_of(int p_index) {
	switch (p_index) {
		case 0: return Control::PRESET_TOP_LEFT;
		case 1: return Control::PRESET_TOP_RIGHT;
		case 2: return Control::PRESET_BOTTOM_LEFT;
		case 3: return Control::PRESET_BOTTOM_RIGHT;
		case 4: return Control::PRESET_CENTER_LEFT;
		case 5: return Control::PRESET_CENTER_TOP;
		case 6: return Control::PRESET_CENTER_RIGHT;
		case 7: return Control::PRESET_CENTER_BOTTOM;
		case 8: return Control::PRESET_CENTER;
		case 9: return Control::PRESET_LEFT_WIDE;
		case 10: return Control::PRESET_TOP_WIDE;
		case 11: return Control::PRESET_RIGHT_WIDE;
		case 12: return Control::PRESET_BOTTOM_WIDE;
		case 13: return Control::PRESET_VCENTER_WIDE;
		case 14: return Control::PRESET_HCENTER_WIDE;
		default: return Control::PRESET_FULL_RECT;
	}
}

static String _layout_preset_list() {
	String list;
	for (int i = 0; i < LAYOUT_PRESET_COUNT; i++) {
		if (i > 0) {
			list += ", ";
		}
		list += LAYOUT_PRESET_NAMES[i];
	}
	return list;
}

namespace MCPTools {

const char *const *layout_preset_names(int &r_count) {
	r_count = LAYOUT_PRESET_COUNT;
	return LAYOUT_PRESET_NAMES;
}

bool layout_preset_from_name(const String &p_name, int &r_preset, MCPToolError &r_error) {
	for (int i = 0; i < LAYOUT_PRESET_COUNT; i++) {
		if (p_name == LAYOUT_PRESET_NAMES[i]) {
			r_preset = i;
			return true;
		}
	}
	r_error = MCPToolError::invalid_params(vformat("Unknown preset: '%s'. Available: %s", p_name, _layout_preset_list()));
	return false;
}

Variant apply_anchor_preset_on(Node *p_root, Node *p_node, const String &p_preset_name, bool p_keep_offsets,
		MCPToolError &r_error) {
	const String node_path = _relative_path(p_root, p_node);
	if (!p_node->is_class(StringName("Control"))) {
		r_error = MCPToolError::invalid_params(vformat("Node '%s' is not a Control (is %s)", node_path, p_node->get_class()));
		return Variant();
	}
	int preset_index = 0;
	if (!layout_preset_from_name(p_preset_name, preset_index, r_error)) {
		return Variant();
	}
	Control *control = Object::cast_to<Control>(p_node);
	if (control == nullptr) {
		// Unreachable after the `is_class` check; kept so the cast can never be
		// a silent null dereference.
		r_error = MCPToolError::invalid_params(vformat("Node '%s' is not a Control (is %s)", node_path, p_node->get_class()));
		return Variant();
	}
	// The migration source's `KEEP_SIZE` is `PRESET_MODE_KEEP_SIZE`; its other
	// arm is `MINSIZE` (node.rs:456-460).
	const Control::LayoutPresetMode mode = p_keep_offsets
			? Control::PRESET_MODE_KEEP_SIZE
			: Control::PRESET_MODE_MINSIZE;
	control->set_anchors_and_offsets_preset(_layout_preset_of(preset_index), mode);

	Dictionary result;
	result["node_path"] = node_path;
	result["preset"] = p_preset_name;
	return result;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// editor_set_anchor_preset (old `set_anchor_preset`, node.rs:408)
//
// Observable contract:
//   * `node_path` (required, non-empty), `preset` (required, non-empty),
//     `keep_offsets` (optional bool, default false);
//   * the node is resolved with the shared `MCPTools::find_node` (a miss is
//     `-32001` with a suggestion);
//   * a node that is not a `Control` is `-32602` naming the node and its class;
//   * an unknown `preset` is `-32602` listing the legal names;
//   * the answer is `{"node_path": <root-relative>, "preset": <requested>}`,
//     exactly the migration source's key set.
// ---------------------------------------------------------------------------
static Variant _tool_set_anchor_preset(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_path' must not be empty");
		return Variant();
	}
	String preset;
	if (!require_string(p_args, "preset", preset, r_error)) {
		return Variant();
	}
	if (preset.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'preset' must not be empty");
		return Variant();
	}
	bool keep_offsets = false;
	if (!optional_bool(p_args, "keep_offsets", false, keep_offsets, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor node writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Node *node = find_node(root, node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", node_path),
				"Use editor_get_scene_tree to list the nodes of the edited scene");
		return Variant();
	}
	return apply_anchor_preset_on(root, node, preset, keep_offsets, r_error);
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character; the schema is *parsed*
// from the exact contract JSON instead of being rebuilt as a hand-written
// Dictionary, because the gate compares all three fields verbatim.
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_control_layout_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_control_layout_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_set_anchor_preset", String::utf8(R"desc(设置 Control 节点的锚点预设)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"keep_offsets":{"description":"是否保持偏移量 (可选，默认 false)","type":"boolean"},"node_path":{"description":"节点路径","type":"string"},"preset":{"description":"预设名称 (top_left, top_right, bottom_left, bottom_right, center_left, center_top, center_right, center_bottom, center, left_wide, top_wide, right_wide, bottom_wide, vcenter_wide, hcenter_wide, full_rect)","type":"string"}},"required":["node_path","preset"],"type":"object"})schema"));
		builder.handler(_tool_set_anchor_preset).register_into(r_registry);
	}
}
