/**************************************************************************/
/*  editor_tilemap_read.h                                                 */
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
// TASK-035 (B5 batch 3): the `editor_tilemap_read` group (3 tools).
//
// These are the readers the two `fix_implementation_first` writers of the same
// batch are verified with: `editor_get_tilemap_cell` and
// `editor_get_tilemap_used_cells` answer the *same* cell shape the writers take
// (`source_id` + `atlas_coords` + `alternative_tile`, plus the decomposed
// transform flags), so a write can be read back cell by cell and the whole cell
// can be written again unchanged (GDR-25 sections 23.1/23.4).
//
// `editor_get_tilemap_used_cells` sorts its cells (the engine's own
// `get_used_cells` walks a `HashMap`, so its order is not reproducible) and
// `editor_get_tilemap_cell` answers `empty: true` for a coordinate the layer has
// no cell at instead of an error: "the cell is empty" is a fact about the
// tilemap, not a bad argument.
// ---------------------------------------------------------------------------

namespace MCPTools {

// One cell of the layer plus the layer's identity, i.e. everything a caller
// needs to write the same cell somewhere else.
Dictionary tilemap_cell_at(Node *p_root, const String &p_node_path, int p_x, int p_y, int p_layer,
		MCPToolError &r_error);

// The layer's own facts (`tilemap_layer_info`).
Dictionary tilemap_info_at(Node *p_root, const String &p_node_path, MCPToolError &r_error);

// Every used cell of the layer, sorted and in the writable shape.
Dictionary tilemap_used_cells_at(Node *p_root, const String &p_node_path, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_tilemap_read_tools(MCPToolRegistry &r_registry);
