/**************************************************************************/
/*  tilemap_shared.cpp                                                    */
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
#include "tilemap_shared.h"

#include "tool_helpers.h"

#include "core/io/resource_loader.h"

using namespace MCPTools;

namespace {

// The first few ids of an enumerable set, for a message that lets the caller
// correct the call in one step ("0, 1, 3 (and 5 more)").
String enumerate_ints(const Vector<int> &p_values, int p_max = 8) {
	String out;
	const int shown = MIN(p_values.size(), p_max);
	for (int i = 0; i < shown; i++) {
		if (i > 0) {
			out += ", ";
		}
		out += itos(p_values[i]);
	}
	if (p_values.size() > shown) {
		out += vformat(" (and %d more)", p_values.size() - shown);
	}
	return out;
}

} // namespace

namespace MCPTools {

TileMapLayer *tilemap_layer_at(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	Node *node = find_node(p_root, p_node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s' in the edited scene", p_node_path),
				"'node_path' is relative to the edited scene root ('.' is the root itself); call editor_get_scene_tree "
				"to list the nodes that are there");
		return nullptr;
	}
	TileMapLayer *layer = Object::cast_to<TileMapLayer>(node);
	if (layer == nullptr) {
		// Godot 4 replaced the layered `TileMap` with one `TileMapLayer` node per
		// layer; a `TileMap` here has no cells of its own any more.
		r_error = MCPToolError::invalid_params(vformat(
				"Node '%s' is a %s, not a TileMapLayer: the tilemap tools drive the per-layer node the engine uses "
				"since Godot 4 (TileMapLayer::set_cell / get_cell_source_id)",
				p_node_path, node->get_class()));
		return nullptr;
	}
	return layer;
}

Ref<TileSet> tilemap_tile_set_of(TileMapLayer *p_layer, const String &p_node_path, MCPToolError &r_error) {
	const Ref<TileSet> tile_set = p_layer->get_tile_set();
	if (tile_set.is_null()) {
		r_error = MCPToolError::tool_state(
				vformat("TileMapLayer '%s' has no TileSet, so it has no source or atlas to name", p_node_path),
				"Assign a TileSet first (editor_set_node_property with property \"tile_set\" and a "
				"{\"type\":\"TileSet\",\"path\":\"res://...\"} value, or editor_add_resource_to_node_property), then "
				"call again");
		return Ref<TileSet>();
	}
	return tile_set;
}

bool tilemap_resolve_cell_target(TileSet *p_tile_set, int p_source_id, bool p_atlas_given,
		const Vector2i &p_atlas_coords, int &r_source_id, Vector2i &r_atlas_coords, MCPToolError &r_error) {
	if (p_source_id == TileSet::INVALID_SOURCE) {
		// The engine's own erase shape (`TileMapLayer::erase_cell` passes exactly
		// this triple), accepted explicitly instead of being reached by accident.
		r_source_id = TileSet::INVALID_SOURCE;
		r_atlas_coords = TileSetSource::INVALID_ATLAS_COORDS;
		return true;
	}
	if (p_source_id < 0) {
		r_error = MCPToolError::invalid_params(vformat(
				"'source_id' must be a source of the layer's TileSet, or -1 to erase the cell; got %d",
				p_source_id));
		return false;
	}
	if (!p_tile_set->has_source(p_source_id)) {
		Vector<int> ids;
		for (int i = 0; i < p_tile_set->get_source_count(); i++) {
			ids.push_back(p_tile_set->get_source_id(i));
		}
		r_error = MCPToolError::invalid_params(vformat(
				"The TileSet of this TileMapLayer has no source %d; it has: %s", p_source_id,
				ids.is_empty() ? String("no source at all (add a TileSetAtlasSource first)") : enumerate_ints(ids)));
		return false;
	}
	const Ref<TileSetSource> source = p_tile_set->get_source(p_source_id);
	if (source.is_null()) {
		r_error = MCPToolError::invalid_params(vformat(
				"TileSet source %d cannot be read back as a TileSetSource", p_source_id));
		return false;
	}
	// The migration source defaulted the atlas to (0, 0) and then discarded it;
	// keeping the default but *validating* it is the difference between "writes
	// the origin tile" and "writes whatever the engine default happens to be".
	const Vector2i atlas = p_atlas_given ? p_atlas_coords : Vector2i(0, 0);
	if (!source->has_tile(atlas)) {
		Vector<Vector2i> coords;
		for (int i = 0; i < source->get_tiles_count() && coords.size() < 8; i++) {
			coords.push_back(source->get_tile_id(i));
		}
		String available;
		for (int i = 0; i < coords.size(); i++) {
			if (i > 0) {
				available += ", ";
			}
			available += String(coords[i]);
		}
		if (source->get_tiles_count() > coords.size()) {
			available += vformat(" (and %d more)", source->get_tiles_count() - coords.size());
		}
		r_error = MCPToolError::invalid_params(vformat(
				"TileSet source %d has no tile at atlas_coords %s; it has: %s",
				p_source_id, String(atlas), available.is_empty() ? String("no tile") : available));
		return false;
	}
	r_source_id = p_source_id;
	r_atlas_coords = atlas;
	return true;
}

Dictionary tilemap_cell_record(TileMapLayer *p_layer, const Vector2i &p_coords) {
	Dictionary record;
	record["x"] = p_coords.x;
	record["y"] = p_coords.y;
	const int source_id = p_layer->get_cell_source_id(p_coords);
	const Vector2i atlas = p_layer->get_cell_atlas_coords(p_coords);
	const int alternative = p_layer->get_cell_alternative_tile(p_coords);
	Dictionary atlas_record;
	atlas_record["x"] = atlas.x;
	atlas_record["y"] = atlas.y;
	record["source_id"] = source_id;
	record["atlas_coords"] = atlas_record;
	record["alternative_tile"] = alternative;
	record["empty"] = source_id == TileSet::INVALID_SOURCE;
	// The transform flags are separate bits of the alternative tile id; answering
	// them decomposed is what makes a read-back cell re-writable without the
	// caller having to reconstruct the packed id (GDR-25 section 23.1).
	record["flipped_h"] = p_layer->is_cell_flipped_h(p_coords);
	record["flipped_v"] = p_layer->is_cell_flipped_v(p_coords);
	record["transposed"] = p_layer->is_cell_transposed(p_coords);
	record["has_tile_data"] = p_layer->get_cell_tile_data(p_coords) != nullptr;
	return record;
}

Array tilemap_used_cell_records(TileMapLayer *p_layer) {
	// `get_used_cells()` iterates a `HashMap` (tile_map_layer.h:390), so the
	// engine order is not reproducible; sorting is what makes two calls answer the
	// same array (PLAYBOOK section 6.8).
	const TypedArray<Vector2i> used = p_layer->get_used_cells();
	Vector<Vector2i> coords;
	coords.resize(used.size());
	for (int i = 0; i < used.size(); i++) {
		coords.write[i] = used[i];
	}
	struct CellOrder {
		bool operator()(const Vector2i &a, const Vector2i &b) const {
			if (a.y != b.y) {
				return a.y < b.y;
			}
			return a.x < b.x;
		}
	};
	coords.sort_custom<CellOrder>();
	Array records;
	for (int i = 0; i < coords.size(); i++) {
		records.push_back(tilemap_cell_record(p_layer, coords[i]));
	}
	return records;
}

Dictionary tilemap_layer_info(TileMapLayer *p_layer, const String &p_node_path) {
	const Ref<TileSet> tile_set = p_layer->get_tile_set();
	const TypedArray<Vector2i> used = p_layer->get_used_cells();
	const Rect2i used_rect = p_layer->get_used_rect();

	Dictionary out;
	out["node_path"] = p_node_path;
	out["node_type"] = p_layer->get_class();
	// The engine has one layer per node since Godot 4; answering the index keeps
	// the contract's `layer` member visible instead of pretending it is absent.
	out["layer"] = 0;
	out["cell_count"] = used.size();
	out["enabled"] = p_layer->is_enabled();
	Dictionary rect;
	rect["x"] = used_rect.position.x;
	rect["y"] = used_rect.position.y;
	rect["width"] = used_rect.size.x;
	rect["height"] = used_rect.size.y;
	out["used_rect"] = rect;
	out["tile_set"] = serialize_variant(Variant((Object *)tile_set.ptr()));
	out["has_tile_set"] = tile_set.is_valid();
	if (tile_set.is_valid()) {
		out["source_count"] = tile_set->get_source_count();
		out["tile_size"] = serialize_variant(Variant(tile_set->get_tile_size()));
		Array sources;
		for (int i = 0; i < tile_set->get_source_count(); i++) {
			const int source_id = tile_set->get_source_id(i);
			const Ref<TileSetSource> source = tile_set->get_source(source_id);
			Dictionary record;
			record["source_id"] = source_id;
			record["type"] = source.is_valid() ? source->get_class() : String();
			record["tile_count"] = source.is_valid() ? source->get_tiles_count() : 0;
			sources.push_back(record);
		}
		out["sources"] = sources;
	} else {
		out["source_count"] = 0;
	}
	return out;
}

} // namespace MCPTools
