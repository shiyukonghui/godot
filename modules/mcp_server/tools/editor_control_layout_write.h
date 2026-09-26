/**************************************************************************/
/*  editor_control_layout_write.h                                         */
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
#pragma once

#include "../tool_registry.h"

#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// `Node` is only ever used through a pointer by the helpers declared below, so
// the class name is forward declared instead of dragging `scene/gui/control.h`
// (and `scene/main/node.h` with it) into every translation unit that includes
// this header. The preset is passed as an `int` for the same reason.
class Node;

// B3 group `editor_control_layout_write` (docs/tool-groups-b3.json; TASK-017
// section 2) - one tool:
//
//   editor_set_anchor_preset (node.rs:408)
//
// It is `channel = editor`, `scope = editor`, `mutating = true`
// (docs/tool-rename-map.json), so it is registered only in an editor process and
// a game endpoint must answer `-32601` without executing anything.
//
// It is alone in its group because it is the one Control-layout write: it needs
// `scene/gui/control.h` (`Control::LayoutPreset` / `LayoutPresetMode`) and no
// other node write does (the group note of docs/tool-groups-b3.json says so).
//
// The helper functions below are declared here for the same reason
// `tools/editor_node_write.h` declares its five: the doctest binary has no
// `SceneTree` at all, so a tool-level test can only observe the guards. The
// exported entries let the cases pin the name mapping and the applied anchors
// against bare `Control` objects. Behaviour is documented at each definition.
namespace MCPTools {

// The `preset` names the contract lists, in the contract's own order, exported
// so a test can prove the list (and its distinctness) without copying it.
const char *const *layout_preset_names(int &r_count);

// Maps a `preset` argument to `Control::LayoutPreset`. Returns false with
// `-32602` listing the legal names for anything else (the migration source did
// the same, node.rs:444-447). The mapping is case-sensitive, as it is there.
bool layout_preset_from_name(const String &p_name, int &r_preset, MCPToolError &r_error);

// Applies `p_preset_name` to `p_control` (which must be a `Control`; otherwise
// `-32602` naming the node and its actual class). `p_keep_offsets` selects
// `LayoutPresetMode::PRESET_MODE_KEEP_SIZE` instead of `PRESET_MODE_MINSIZE`.
// Answers `{"node_path": <root-relative>, "preset": <requested>}`.
Variant apply_anchor_preset_on(Node *p_root, Node *p_node, const String &p_preset_name, bool p_keep_offsets,
		MCPToolError &r_error);

} // namespace MCPTools

void register_editor_control_layout_write_tools(MCPToolRegistry &r_registry);
