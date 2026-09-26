/**************************************************************************/
/*  editor_tilemap_read.cpp                                               */
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
#include "editor_tilemap_read.h"

#include "tilemap_shared.h"
#include "tool_helpers.h"

#include "core/io/json.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-035 section 1: the engine reference behind these three reads.
//
//   * `TileMapLayer::get_cell_source_id(const Vector2i &)`
//     (modules/tilemap/tile_map_layer.h:563) answers `TileSet::INVALID_SOURCE`
//     (`-1`) for an empty coordinate, `get_cell_atlas_coords` (:564) answers
//     `TileSetSource::INVALID_ATLAS_COORDS` there, and `get_cell_alternative_tile`
//     (:565) is the packed id the transform flags live in
//     (`is_cell_flipped_h/v` / `is_cell_transposed`, :572-574). All five are the
//     engine's own accessors, so the answer is the layer's real state.
//   * `get_used_cells()` (:568) and `get_used_rect()` (:570) are the aggregate
//     reads; the first walks a `HashMap` (`tile_map_layer.h:390`), so this tool
//     **sorts** its answer (`tilemap_used_cell_records`) - the same tree must
//     answer the same array twice (PLAYBOOK section 6.8).
//   * `get_cell_tile_data()` (:566) answers whether the cell resolves to a
//     `TileData` at all, which is what tells "a cell exists" from "the cell's
//     source/atlas/alternative really names a tile of the TileSet".
//   * the contract's `layer` member is a Godot-3 leftover: Godot 4 has one
//     `TileMapLayer` node per layer, so `0` is accepted (and echoed) while any
//     other value is refused instead of silently ignored.
// ---------------------------------------------------------------------------

namespace MCPTools {

Dictionary tilemap_cell_at(Node *p_root, const String &p_node_path, int p_x, int p_y, int p_layer,
		MCPToolError &r_error) {
	TileMapLayer *layer = tilemap_layer_at(p_root, p_node_path, r_error);
	if (layer == nullptr) {
		return Dictionary();
	}
	const Vector2i coords(p_x, p_y);
	Dictionary out = tilemap_cell_record(layer, coords);
	out["node_path"] = relative_path(p_root, layer);
	out["node_type"] = layer->get_class();
	out["layer"] = p_layer;
	return out;
}

Dictionary tilemap_info_at(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	TileMapLayer *layer = tilemap_layer_at(p_root, p_node_path, r_error);
	if (layer == nullptr) {
		return Dictionary();
	}
	return tilemap_layer_info(layer, relative_path(p_root, layer));
}

Dictionary tilemap_used_cells_at(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	TileMapLayer *layer = tilemap_layer_at(p_root, p_node_path, r_error);
	if (layer == nullptr) {
		return Dictionary();
	}
	const Array cells = tilemap_used_cell_records(layer);
	const Rect2i used_rect = layer->get_used_rect();
	Dictionary rect;
	rect["x"] = used_rect.position.x;
	rect["y"] = used_rect.position.y;
	rect["width"] = used_rect.size.x;
	rect["height"] = used_rect.size.y;

	Dictionary out;
	out["node_path"] = relative_path(p_root, layer);
	out["node_type"] = layer->get_class();
	out["layer"] = 0;
	out["count"] = cells.size();
	out["used_rect"] = rect;
	out["cells"] = cells;
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

namespace {

// `layer` is optional and must be `0`: Godot 4's `TileMapLayer` is a single
// layer, and answering a non-zero index with the same cells would be a silent
// reinterpretation of the argument.
bool read_layer_argument(const Dictionary &p_args, int &r_layer, MCPToolError &r_error) {
	int64_t layer = 0;
	if (!optional_int(p_args, "layer", 0, layer, r_error)) {
		return false;
	}
	if (layer != 0) {
		r_error = MCPToolError::invalid_params(vformat(
				"'layer' must be 0: since Godot 4 a TileMapLayer node *is* one layer (the layered TileMap node was "
				"removed), so there is no other layer to read; got %d",
				layer));
		return false;
	}
	r_layer = 0;
	return true;
}

bool require_node_path(const Dictionary &p_args, String &r_node_path, MCPToolError &r_error) {
	if (!require_string(p_args, "node_path", r_node_path, r_error)) {
		return false;
	}
	if (r_node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return false;
	}
	return true;
}

} // namespace

static Variant _tool_get_tilemap_cell(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_node_path(p_args, node_path, r_error)) {
		return Variant();
	}
	int64_t x = 0;
	int64_t y = 0;
	if (!require_int(p_args, "x", x, r_error) || !require_int(p_args, "y", y, r_error)) {
		return Variant();
	}
	int layer = 0;
	if (!read_layer_argument(p_args, layer, r_error)) {
		return Variant();
	}
	int cell_x = 0;
	int cell_y = 0;
	if (!value_fits_slot(Variant(x), ValueSlot::INT32, "x", "a 32-bit tile coordinate", r_error) ||
			!value_fits_slot(Variant(y), ValueSlot::INT32, "y", "a 32-bit tile coordinate", r_error)) {
		return Variant();
	}
	cell_x = (int)x;
	cell_y = (int)y;
	if (!require_editor_ui(r_error, "editor tilemap reads outside a running editor",
				"Start the MCP server inside the Godot editor to read editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return tilemap_cell_at(root, node_path, cell_x, cell_y, layer, r_error);
}

static Variant _tool_get_tilemap_info(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_node_path(p_args, node_path, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor tilemap reads outside a running editor",
				"Start the MCP server inside the Godot editor to read editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return tilemap_info_at(root, node_path, r_error);
}

static Variant _tool_get_tilemap_used_cells(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_node_path(p_args, node_path, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor tilemap reads outside a running editor",
				"Start the MCP server inside the Godot editor to read editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return tilemap_used_cells_at(root, node_path, r_error);
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character.
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_tilemap_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_tilemap_read_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_get_tilemap_cell", String::utf8(R"desc(获取瓦片地图指定单元格信息)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		// `layer` carries an integer default (`0`). The engine's JSON parser stores
		// it as a `double`, and the contract declares `"default": 0`, so the member
		// goes through the module's one normalization helper - the same one
		// `editor_add_audio_bus`'s `after_bus_index` uses (TASK-033/034).
		builder.schema(schema_with_integer_defaults(_schema_from_json(R"schema({"properties":{"layer":{"default":0,"type":"integer"},"node_path":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"}},"required":["node_path","x","y"],"type":"object"})schema"), { StringName("layer") }));
		builder.handler(_tool_get_tilemap_cell).register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_get_tilemap_info", String::utf8(R"desc(获取 TileMapLayer 信息)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"}},"required":["node_path"],"type":"object"})schema"));
		builder.handler(_tool_get_tilemap_info).register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_get_tilemap_used_cells", String::utf8(R"desc(获取已使用格子)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"}},"required":["node_path"],"type":"object"})schema"));
		builder.handler(_tool_get_tilemap_used_cells).register_into(r_registry);
	}
}
