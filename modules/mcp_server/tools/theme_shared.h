/**************************************************************************/
/*  theme_shared.h                                                        */
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
#pragma once

#include "tool_builder.h"

#include "scene/resources/theme.h"

// ---------------------------------------------------------------------------
// TASK-036 (B5 batch 4): the engine-facing helpers the two theme groups share
// (`project_theme_write` 5 tools, `project_theme_read` 1 tool).
//
// They are *not* a third group: no tool is registered here.
//
// The engine's own model is the design basis (GDR-23):
//
//   * a Theme is a `Resource` that stores **four typed maps per theme type**
//     (`color_map`, `constant_map`, `font_size_map`, `style_map`,
//     `scene/resources/theme.h:96-110`). The four writers below are exactly the
//     engine's four setters - `Theme::set_color` (:753), `set_constant` (:850),
//     `set_font_size` (:650), `set_stylebox` (:402) - and the readers are the
//     engine's own `has_*` / `get_*` pair for each kind;
//   * **`has_*` is the read-back**, never `get_*` alone: `get_stylebox`
//     (:421-427) and `get_font_size` (:660-668) both answer a **fallback** when
//     the item is absent, so a naive "read it back and compare" would report a
//     write that the engine dropped as a success. The three public predicates
//     `has_color`/`has_constant`/`has_stylebox`/`has_font_size_nocheck` answer
//     what the map really holds;
//   * the engine's own name rule is `Theme::is_valid_item_name` /
//     `is_valid_type_name` (`scene/resources/theme.cpp:180-203`), both **public
//     static** and both used here directly: `set_color` and friends silently
//     return on an invalid name (`ERR_FAIL_COND_MSG`), which is the one class of
//     "the write did nothing" a pre-check can turn into an honest `-32602`;
//   * `set_font_size` **stores a non-positive size but the read API hides it**:
//     `has_font_size`/`get_font_size` require `> 0` (:661/:671) while
//     `has_font_size_nocheck` (:678) says whether the key is really there. A
//     stored non-positive size is therefore reported through the GDR-20 section
//     20.6 `ignored` channel, not as "set";
//   * the save is atomic for the same reason every other resource writer is
//     (PLAYBOOK section 2.4 / `tool_helpers.h`): `ResourceSaver::save()` writes
//     straight into the destination, so a failure halfway leaves a truncated
//     `.tres`/`.res` where the caller's theme used to be. The publish goes
//     through the module's one `publish_file_atomically`.
// ---------------------------------------------------------------------------

namespace MCPTools {

// Normalises `p_input` (`res://` only, folded), loads it and casts it to a
// Theme. `r_path` is the canonical path. A missing/unloadable path is `-32001`
// and a loadable non-Theme is `-32602`; both name what was really found.
Ref<Theme> load_theme_resource(const String &p_input, String &r_path, MCPToolError &r_error);

// Publishes `p_theme` to `p_path` through `publish_file_atomically` (a sibling
// temporary is written by `ResourceSaver::save` and renamed into place, so the
// destination is never half a resource). Returns the engine's `Error`.
Error save_theme_atomically(const Ref<Theme> &p_theme, const String &p_path);

// True when both names pass the engine's own `Theme::is_valid_item_name` /
// `Theme::is_valid_type_name`. On failure `r_error` is a `-32602` that names the
// rule and the offending string; nothing is written.
//
// `p_parameter_name` is the caller's own argument name (`color_name`,
// `stylebox_name`, ...) so the refusal keeps the tool's vocabulary.
bool require_theme_item_and_type(const String &p_parameter_name, const String &p_item_name,
		const String &p_node_type, MCPToolError &r_error);

// The answer envelope the four theme writers share, so "what was really stored"
// has one shape (GDR-25 section 23.4):
//
//   `{theme_path, node_type, <p_parameter_name>: <item>, changed:
//     {<item>: {old, new}}, properties_set: [...], ignored: {...}, saved: true}`
//
// `properties_set` lists the item only when `p_present && p_matches` (the value
// the engine's own reader answers *is* what was asked for); otherwise the item
// goes into `ignored` with `requested`, `stored` and `reason` - the GDR-22
// section 20.6 rule this batch inherits for every resource write.
Dictionary build_theme_write_result(const String &p_theme_path, const String &p_node_type,
		const String &p_item_name, const String &p_parameter_name, const Variant &p_requested,
		const Variant &p_old, const Variant &p_stored, bool p_present, bool p_matches,
		const String &p_ignore_reason);

// The whole state of a loaded theme, as `project_get_theme_info` answers it and
// as the writer's own read-back is checked against:
//
//   `{path, type_list, type_count, colors, constants, font_sizes, styleboxes,
//     fonts, icons, font_count, icon_count}`
//
// The four typed maps answer `{<theme_type>: {<item>: <value>}}` with the value
// the engine really holds (`get_color` / `get_constant` / `get_font_size` /
// `get_stylebox`, each gated by its `has_*` so a fallback is never reported as
// stored state); `fonts`/`icons` answer `{<theme_type>: [<item>...]}` because a
// `Ref<Font>`/`Ref<Texture2D>` has no useful JSON shape here and none of this
// batch's tools can write one. Item names are directly feedable back into the
// four writers (GDR-25 section 23.1).
Dictionary theme_info_of(const Ref<Theme> &p_theme, const String &p_path);

} // namespace MCPTools
