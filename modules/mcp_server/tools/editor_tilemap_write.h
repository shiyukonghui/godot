/**************************************************************************/
/*  editor_tilemap_write.h                                                */
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

class Node;

// ---------------------------------------------------------------------------
// TASK-035 (B5 batch 3): the `editor_tilemap_write` group (3 tools), two of them
// `fix_implementation_first`.
//
// The baseline this batch starts from is a faithful port of the migration source
// (`godot_mcp_gdext/src/commands/tilemap.rs`), which is why the first build's
// doctest run is red:
//
//   * `tilemap_set_cell` (:124) called `layer.set_cell(Vector2i(x, y))` - the
//     one-argument overload, whose default `source_id` is `TileSet::INVALID_SOURCE`
//     and whose default atlas is invalid - i.e. it **erased** the cell and then
//     answered `set: true` with the `source_id` it never used;
//   * `tilemap_fill_rect` (:158) did the same per cell and answered `filled: w*h`;
//   * `tilemap_clear` (:96) returned `{"cleared": true}` with no count at all.
//
// The fixed implementation resolves the `(source_id, atlas_coords)` pair against
// the layer's own `TileSet`, writes it through the four-argument `set_cell`, reads
// the cell back and refuses rather than claiming a write that did not happen. The
// rectangle write is all-or-nothing (pre-validation, then a snapshot, then a
// verify that restores the snapshot on any mismatch), and the clear answers the
// real number of cells it removed.
// ---------------------------------------------------------------------------

namespace MCPTools {

// Writes one cell of the `TileMapLayer` at `p_node_path` and answers the cell the
// engine holds afterwards. `p_source_id == -1` is the engine's erase shape.
Dictionary set_tilemap_cell_on(Node *p_root, const String &p_node_path, int p_x, int p_y, int p_source_id,
		bool p_atlas_given, const Vector2i &p_atlas_coords, MCPToolError &r_error);

// Writes every cell of `p_rect` and answers the real number of cells written.
Dictionary set_tilemap_cells_in_rect_on(Node *p_root, const String &p_node_path, const Rect2i &p_rect,
		int p_source_id, bool p_atlas_given, const Vector2i &p_atlas_coords, MCPToolError &r_error);

// Clears the layer and answers how many cells it really removed.
Dictionary remove_all_tilemap_cells_on(Node *p_root, const String &p_node_path, MCPToolError &r_error);

// The hard cap on one rectangle write: `width * height` cells are allocated,
// written and verified in one call, so an unbounded request is a denial of
// service on the editor's own process. 65536 cells (a 256x256 area) is far above
// any hand-authored tilemap region and keeps the snapshot at a few megabytes.
int tilemap_rect_cell_cap();

} // namespace MCPTools

void register_editor_tilemap_write_tools(MCPToolRegistry &r_registry);
