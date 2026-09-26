/**************************************************************************/
/*  tilemap_shared.h                                                      */
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

#include "modules/tilemap/tile_map_layer.h"

// ---------------------------------------------------------------------------
// TASK-035 (B5 batch 3): the engine-facing helpers the two tilemap groups share
// (`editor_tilemap_write` 3 tools, `editor_tilemap_read` 3 tools).
//
// They are *not* a third group: no tool is registered here and
// `docs/tool-groups-b5.json` is untouched. The file exists because the writer's
// read-back and the reader's answers must be the **same** cell shape, or the
// write -> read chain (the one thing that makes the two data-destructive
// fix-first tools detectable) breaks.
//
// The engine's own model is the design basis (GDR-23):
//
//   * the node is a `TileMapLayer` (`modules/tilemap/tile_map_layer.h`). Godot 4
//     replaced the layered `TileMap` with one node per layer, so a layer index
//     does not exist any more: the contract's `layer` member is accepted only as
//     the literal `0` and refused otherwise instead of being silently ignored.
//   * a cell is set with
//     `TileMapLayer::set_cell(const Vector2i &p_coords, int p_source_id,
//     const Vector2i &p_atlas_coords, int p_alternative_tile)`
//     (`tile_map_layer.cpp:...`), and the three read accessors are
//     `get_cell_source_id` / `get_cell_atlas_coords` /
//     `get_cell_alternative_tile` (`tile_map_layer.h:563-566`). The migration
//     source called `set_cell(coords)` - the *erase* shape, because
//     `TileSet::INVALID_SOURCE` is the default - and threw the requested
//     `source_id`/`atlas_coords` away (`godot_mcp_gdext/src/commands/tilemap.rs:124`
//     and `:158`), which is the data-destruction defect this batch fixes.
//   * a source id and an atlas coordinate that the layer's `TileSet` does not
//     contain are refused *before* the write, because `TileMapLayer` stores
//     whatever it is given: the engine does not validate against the `TileSet`
//     (`TileMapLayer::set_cell` has no `has_source` check), so "write a tile that
//     is not there" is a silent data error unless the tool checks.
//   * `get_used_cells()` walks a `HashMap` (`tile_map_layer.h:390`), so its order
//     is **not** reproducible; every answer here sorts the cells (by `y`, then
//     `x`), which is the deterministic form PLAYBOOK section 6.8 requires.
// ---------------------------------------------------------------------------

namespace MCPTools {

// The `TileMapLayer` at `p_node_path` in `p_root`. A path that names nothing is
// `-32001` with a suggestion; a path that names another class is `-32602` naming
// the class it really is.
TileMapLayer *tilemap_layer_at(Node *p_root, const String &p_node_path, MCPToolError &r_error);

// The layer's `TileSet`, refused with `-32000` (with a suggestion) when the node
// has none: without a tile set there is no source and no atlas to name.
Ref<TileSet> tilemap_tile_set_of(TileMapLayer *p_layer, const String &p_node_path, MCPToolError &r_error);

// Resolves the `(source_id, atlas_coords)` pair a write will use and refuses
// anything the layer's `TileSet` cannot hold:
//
//   * `source_id == TileSet::INVALID_SOURCE` (`-1`) is the engine's own *erase*
//     semantic and is accepted, with the atlas forced to
//     `TileSetSource::INVALID_ATLAS_COORDS` (that is what
//     `TileMapLayer::erase_cell` passes);
//   * any other negative source is `-32602`;
//   * a source the `TileSet` does not contain is `-32602` (not `-32001`: the
//     parameter is wrong, the tile set exists) and the message lists the source
//     ids that do exist;
//   * an omitted `atlas_coords` defaults to `(0, 0)` - the origin tile, which is
//     the value the migration source pretended to use - and a coordinate the
//     source has no tile at is `-32602` listing a few coordinates that do exist.
bool tilemap_resolve_cell_target(TileSet *p_tile_set, int p_source_id, bool p_atlas_given,
		const Vector2i &p_atlas_coords, int &r_source_id, Vector2i &r_atlas_coords, MCPToolError &r_error);

// One cell as every tilemap tool answers it: the engine's four cell accessors
// plus the transform flags, i.e. exactly the shape a writer needs to write the
// same cell again (`source_id` + `atlas_coords` + `alternative_tile`).
Dictionary tilemap_cell_record(TileMapLayer *p_layer, const Vector2i &p_coords);

// Every used cell of the layer as `tilemap_cell_record` records, sorted by `y`
// then `x` so two calls on the same tree answer the same array.
Array tilemap_used_cell_records(TileMapLayer *p_layer);

// The layer's own facts (class, cell count, used rect, tile set identity and
// source list), shared by `editor_get_tilemap_info`.
Dictionary tilemap_layer_info(TileMapLayer *p_layer, const String &p_node_path);

} // namespace MCPTools
