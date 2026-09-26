/**************************************************************************/
/*  project_theme_write.h                                                 */
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
// TASK-036 (B5 batch 4): the `project_theme_write` group (5 tools).
//
// `project_create_theme`, `project_set_theme_color`, `project_set_theme_constant`,
// `project_set_theme_font_size`, `project_set_theme_stylebox`. Every tool is
// `channel = project`, `verb` per docs/tool-rename-map.json, `scope = both`,
// `mutating = true`.
//
// The five entry points below are the tools' own bodies, exported so a doctest
// can drive them against a real `Theme` without a live edited scene (the
// doctest process has no `SceneTree`). The engine-facing vocabulary they share
// is in `tools/theme_shared.*`; the reasoning for each write is next to the
// definition.
// ---------------------------------------------------------------------------

namespace MCPTools {

// The three extensions the engine's own savers recognise for a Theme:
// `ResourceFormatSaverText` answers `tres` for a non-scene resource
// (`scene/resources/resource_format_text.cpp:2230-2236`) and
// `ResourceFormatSaverBinary` answers the resource's base extension - `theme`
// for a `Theme` (`scene/resources/theme.h:40` via
// `RES_BASE_EXTENSION("theme")`) - plus `res`
// (`core/io/resource_format_binary.cpp:2476-2482`). `r_error` is the `-32602`
// for anything else.
bool require_theme_file_path(const String &p_raw_path, String &r_path, MCPToolError &r_error);

// `project_create_theme`: instantiates a `Theme` through `ClassDB`, optionally
// names it (`Resource::set_name`, the engine's `resource_name`), and publishes
// it atomically at `p_path`. Refuses to replace an existing file: the contract
// has no `overwrite` argument, and a theme is a whole hand-authored resource.
Dictionary create_theme_file(const String &p_raw_path, const String &p_name, MCPToolError &r_error);

// `project_set_theme_color`. `p_raw_color` is the caller's JSON object
// (`{"r","g","b"[,"a"]}`); it goes through the module's one component mapping
// (`shape_vector_from_json`, target `COLOR`) so every component is width-gated
// (`GDR-24`) and a missing component is a `-32602` naming it.
Dictionary theme_set_color(const Ref<Theme> &p_theme, const String &p_save_path, const String &p_node_type,
		const String &p_color_name, const Variant &p_raw_color, MCPToolError &r_error);

// `project_set_theme_constant`. `p_value` is gated against the `int` member the
// engine's `Theme::set_constant(..., int)` stores it in (`ValueSlot::INT32`).
Dictionary theme_set_constant(const Ref<Theme> &p_theme, const String &p_save_path, const String &p_node_type,
		const String &p_constant_name, int64_t p_value, MCPToolError &r_error);

// `project_set_theme_font_size`. `p_size` is gated against the `int` member of
// `Theme::set_font_size(..., int)` (`ValueSlot::INT32`). A non-positive size is
// **stored but not readable** by the engine's own API and is reported through
// `ignored` (see `theme_shared.h`).
Dictionary theme_set_font_size(const Ref<Theme> &p_theme, const String &p_save_path, const String &p_node_type,
		const String &p_font_size_name, int64_t p_size, MCPToolError &r_error);

// `project_set_theme_stylebox`: builds a `StyleBoxFlat` (the engine's own flat
// style box, `scene/resources/style_box_flat.h`), writes the four optional
// members the contract documents (`bg_color`, `border_color`, `border_width`,
// `corner_radius`), stores it with `Theme::set_stylebox` and reads it back.
// `bg_color`/`border_color` are strings and go through the module's own
// `STRING -> COLOR` conversion (`coerce_to_property_type`, which accepts exactly
// the two grammars `Color` really reads).
Dictionary theme_set_stylebox(const Ref<Theme> &p_theme, const String &p_save_path, const String &p_node_type,
		const String &p_stylebox_name, const Dictionary &p_args, MCPToolError &r_error);

// Checks the four optional style-box members of `project_set_theme_stylebox`
// (`bg_color`, `border_color`, `border_width`, `corner_radius`) and fills the
// `-32602` for each bad one, **without** touching a theme or a `StyleBoxFlat`.
//
// The tool calls it *before* it loads the theme, so a mistyped member is refused
// as the argument error it is instead of being hidden behind "the theme file does
// not exist"; `theme_set_stylebox` calls it again as its own precondition.
bool stylebox_arguments_check(const Dictionary &p_args, MCPToolError &r_error);

} // namespace MCPTools

// TASK-036 section 1: the group of docs/tool-groups-b5.json whose five tools
// create a Theme and set its four entry kinds.
void register_project_theme_write_tools(MCPToolRegistry &r_registry);
