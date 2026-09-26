/**************************************************************************/
/*  editor_tilemap_write.cpp                                              */
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
#include "editor_tilemap_write.h"

#include "tilemap_shared.h"
#include "tool_helpers.h"

#include "core/io/json.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// The three writers.
//
// `fix_implementation_first`, both of them (TASK-035 section 2). The first build
// of this batch carried the faithful port of the migration source
// (`godot_mcp_gdext/src/commands/tilemap.rs:101-164`) - `set_cell(coords)` with
// one argument, `filled: w*h`, `cleared: true` - and its red doctest run measured
// what that port really did:
//
//   * `set_cell(coords)` is the one-argument overload whose defaults are
//     `TileSet::INVALID_SOURCE` / invalid atlas, i.e. the **erase** shape
//     (`tile_map_layer.cpp`: `set_cell` -> `erase_cell`); the requested
//     `source_id` and `atlas_coords` never reached the cell, and the answer
//     echoed the request as `set: true`;
//   * nothing was validated against the layer's `TileSet`, so an unknown source or
//     an atlas coordinate with no tile was accepted (and, with the erase default,
//     destroyed the cell that was there);
//   * `filled: w*h` was computed from the request, not from the layer.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// The fixed bodies.
//
// The pair is resolved against the `TileSet` *before* the write, written through
// the four-argument `set_cell`, read back and answered from the read-back; the
// rectangle is all-or-nothing (pre-validate, snapshot, write, verify, restore on
// any mismatch); and the clear answers the real number of cells it removed, with
// the post-condition verified. See `set_tilemap_cell_on` below.
// ---------------------------------------------------------------------------

namespace MCPTools {

int tilemap_rect_cell_cap() {
	return 65536;
}

namespace {

// The requested pair vs the cell the engine really holds.
bool cell_matches(const Dictionary &p_cell, int p_source_id, const Vector2i &p_atlas) {
	if ((int64_t)p_cell["source_id"] != p_source_id) {
		return false;
	}
	const Dictionary atlas = p_cell["atlas_coords"];
	return (int64_t)atlas["x"] == p_atlas.x && (int64_t)atlas["y"] == p_atlas.y;
}

void write_cell(TileMapLayer *p_layer, const Vector2i &p_coords, int p_source_id, const Vector2i &p_atlas,
		int p_alternative) {
	// The four-argument overload: this is the whole fix of fix-first item 1 - the
	// one-argument form is the erase shape.
	p_layer->set_cell(p_coords, p_source_id, p_atlas, p_alternative);
}

} // namespace

Dictionary set_tilemap_cell_on(Node *p_root, const String &p_node_path, int p_x, int p_y, int p_source_id,
		bool p_atlas_given, const Vector2i &p_atlas_coords, MCPToolError &r_error) {
	TileMapLayer *layer = tilemap_layer_at(p_root, p_node_path, r_error);
	if (layer == nullptr) {
		return Dictionary();
	}
	const Ref<TileSet> tile_set = tilemap_tile_set_of(layer, p_node_path, r_error);
	if (tile_set.is_null()) {
		return Dictionary();
	}
	int source_id = TileSet::INVALID_SOURCE;
	Vector2i atlas = TileSetSource::INVALID_ATLAS_COORDS;
	if (!tilemap_resolve_cell_target(tile_set.ptr(), p_source_id, p_atlas_given, p_atlas_coords, source_id, atlas,
				r_error)) {
		return Dictionary();
	}

	const Vector2i coords(p_x, p_y);
	const Dictionary before = tilemap_cell_record(layer, coords);
	write_cell(layer, coords, source_id, atlas, 0);
	const Dictionary after = tilemap_cell_record(layer, coords);
	if (!cell_matches(after, source_id, atlas)) {
		const Dictionary stored_atlas = after["atlas_coords"];
		r_error = MCPToolError::internal(vformat(
				"TileMapLayer::set_cell(%s, %d, %s, 0) did not store the cell that was asked for (it holds "
				"source_id %d at (%d, %d))",
				String(coords), source_id, String(atlas), (int64_t)after["source_id"],
				(int64_t)stored_atlas["x"], (int64_t)stored_atlas["y"]));
		return Dictionary();
	}

	Dictionary out;
	out["node_path"] = relative_path(p_root, layer);
	out["node_type"] = layer->get_class();
	out["x"] = p_x;
	out["y"] = p_y;
	out["source_id"] = source_id;
	out["atlas_coords"] = after["atlas_coords"];
	out["alternative_tile"] = after["alternative_tile"];
	out["empty"] = after["empty"];
	out["set"] = true;
	out["applied"] = true;
	out["changed"] = !cell_matches(before, source_id, atlas);
	// The cell as it was and as it is: the caller can see the whole transition,
	// and the read-back shape is the same one every tilemap tool answers.
	out["previous"] = before;
	out["cell"] = after;
	return out;
}

Dictionary set_tilemap_cells_in_rect_on(Node *p_root, const String &p_node_path, const Rect2i &p_rect,
		int p_source_id, bool p_atlas_given, const Vector2i &p_atlas_coords, MCPToolError &r_error) {
	TileMapLayer *layer = tilemap_layer_at(p_root, p_node_path, r_error);
	if (layer == nullptr) {
		return Dictionary();
	}
	const Ref<TileSet> tile_set = tilemap_tile_set_of(layer, p_node_path, r_error);
	if (tile_set.is_null()) {
		return Dictionary();
	}
	if (p_rect.size.x <= 0 || p_rect.size.y <= 0) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'rect' must have a positive width and height, got %dx%d", p_rect.size.x, p_rect.size.y));
		return Dictionary();
	}
	if ((int64_t)p_rect.size.x * (int64_t)p_rect.size.y > tilemap_rect_cell_cap()) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'rect' names %d cells (%dx%d), more than this tool writes in one call (%d)",
				p_rect.size.x * p_rect.size.y, p_rect.size.x, p_rect.size.y, tilemap_rect_cell_cap()));
		return Dictionary();
	}
	int source_id = TileSet::INVALID_SOURCE;
	Vector2i atlas = TileSetSource::INVALID_ATLAS_COORDS;
	if (!tilemap_resolve_cell_target(tile_set.ptr(), p_source_id, p_atlas_given, p_atlas_coords, source_id, atlas,
				r_error)) {
		return Dictionary();
	}

	// Every cell of the rectangle, in one deterministic order (row by row), so
	// the snapshot and the verification walk the same sequence.
	Vector<Vector2i> coords;
	coords.resize((int)((int64_t)p_rect.size.x * (int64_t)p_rect.size.y));
	int index = 0;
	for (int y = p_rect.position.y; y < p_rect.position.y + p_rect.size.y; y++) {
		for (int x = p_rect.position.x; x < p_rect.position.x + p_rect.size.x; x++) {
			coords.write[index++] = Vector2i(x, y);
		}
	}

	// The snapshot is what makes the write all-or-nothing: nothing is verified
	// and rolled back from the *request*, only from what the layer really held.
	const int total = coords.size();
	Array snapshot;
	snapshot.resize(total);
	int previously_used = 0;
	for (int i = 0; i < total; i++) {
		const Dictionary record = tilemap_cell_record(layer, coords[i]);
		if (!(bool)record["empty"]) {
			previously_used++;
		}
		snapshot[i] = record;
	}

	for (int i = 0; i < total; i++) {
		write_cell(layer, coords[i], source_id, atlas, 0);
	}

	int verified = 0;
	int first_bad = -1;
	for (int i = 0; i < total; i++) {
		if (cell_matches(tilemap_cell_record(layer, coords[i]), source_id, atlas)) {
			verified++;
		} else if (first_bad < 0) {
			first_bad = i;
		}
	}
	if (verified != total) {
		// Roll the whole rectangle back to the snapshot; the answer is an error,
		// so no caller can mistake a partial write for a success.
		for (int i = 0; i < total; i++) {
			const Dictionary record = snapshot[i];
			if ((bool)record["empty"]) {
				write_cell(layer, coords[i], TileSet::INVALID_SOURCE, TileSetSource::INVALID_ATLAS_COORDS, -1);
			} else {
				const Dictionary stored_atlas = record["atlas_coords"];
				write_cell(layer, coords[i], (int)(int64_t)record["source_id"],
						Vector2i((int)(int64_t)stored_atlas["x"], (int)(int64_t)stored_atlas["y"]),
						(int)(int64_t)record["alternative_tile"]);
			}
		}
		r_error = MCPToolError::internal(vformat(
				"Writing the rectangle %d,%d %dx%d stopped matching the engine at cell %d of %d; the whole rectangle "
				"was restored to its previous content and nothing of this call remains",
				p_rect.position.x, p_rect.position.y, p_rect.size.x, p_rect.size.y, first_bad, total));
		return Dictionary();
	}

	Dictionary rect;
	rect["x"] = p_rect.position.x;
	rect["y"] = p_rect.position.y;
	rect["width"] = p_rect.size.x;
	rect["height"] = p_rect.size.y;
	Dictionary out;
	out["node_path"] = relative_path(p_root, layer);
	out["node_type"] = layer->get_class();
	out["rect"] = rect;
	out["source_id"] = source_id;
	out["atlas_coords"] = serialize_variant(Variant(atlas));
	out["cell_count"] = total;
	// `filled` is the number of cells that now hold the requested tile; erasing a
	// rectangle fills nothing and `removed` says how much was cleared instead.
	out["filled"] = source_id == TileSet::INVALID_SOURCE ? 0 : verified;
	out["removed"] = source_id == TileSet::INVALID_SOURCE ? previously_used : 0;
	out["verified"] = verified;
	out["previous_used_count"] = previously_used;
	out["restored"] = false;
	out["applied"] = true;
	return out;
}

Dictionary remove_all_tilemap_cells_on(Node *p_root, const String &p_node_path, MCPToolError &r_error) {
	TileMapLayer *layer = tilemap_layer_at(p_root, p_node_path, r_error);
	if (layer == nullptr) {
		return Dictionary();
	}
	// The count comes from the engine before the clear, and the post-condition is
	// verified after it: "cleared" is a claim about the tree, not about the call.
	const int before = layer->get_used_cells().size();
	layer->clear();
	const int after = layer->get_used_cells().size();
	if (after != 0) {
		r_error = MCPToolError::internal(vformat(
				"TileMapLayer::clear() left %d used cell(s) behind (it found %d before)", after, before));
		return Dictionary();
	}

	Dictionary out;
	out["node_path"] = relative_path(p_root, layer);
	out["node_type"] = layer->get_class();
	out["cleared"] = true;
	out["removed"] = before;
	out["remaining"] = after;
	out["cell_count_before"] = before;
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// Argument reading
// ---------------------------------------------------------------------------

namespace {

// Every coordinate goes into a `Vector2i`, i.e. a 32-bit `int` member, through
// the module's one width gate (GDR-22; the `INT32` slot).
bool int32_argument(int64_t p_value, const String &p_parameter_name, const String &p_slot_context,
		int &r_out, MCPToolError &r_error) {
	if (!value_fits_slot(Variant(p_value), ValueSlot::INT32, p_parameter_name, p_slot_context, r_error)) {
		return false;
	}
	r_out = (int)p_value;
	return true;
}

// Reads one integer member of a nested object (`atlas_coords`, `rect`). A member
// that is missing is refused (when required) and one that cannot be read as an
// integer is refused too: the migration source defaulted every one of these to
// `0`/`1` and silently wrote the wrong cell.
//
// The value goes through the module's **one** integer rule (`integral_value`,
// the rule `require_int` uses). That is not cosmetic: the wire's JSON parser
// stores every number as a `double`, so a nested member the contract declares
// `integer` arrives as `Variant::FLOAT` - measured by gate 2, which refused
// `atlas_coords = {"x": 0, "y": 0}` with "must be an integer, got float" until
// this call site used the shared rule (REPORT-035 section 6.1).
bool nested_int(const Dictionary &p_object, const String &p_key, const String &p_where, bool p_required,
		int p_default, int &r_out, MCPToolError &r_error) {
	if (!p_object.has(p_key)) {
		if (p_required) {
			r_error = MCPToolError::invalid_params(vformat(
					"Missing required member: '%s.%s'", p_where, p_key));
			return false;
		}
		r_out = p_default;
		return true;
	}
	const Variant value = p_object[p_key];
	int64_t parsed = 0;
	if (!integral_value(value, parsed)) {
		r_error = MCPToolError::invalid_params(vformat(
				"Member '%s.%s' must be an integer, got %s", p_where, p_key,
				Variant::get_type_name(value.get_type())));
		return false;
	}
	return int32_argument(parsed, vformat("%s.%s", p_where, p_key), "a 32-bit tile coordinate", r_out, r_error);
}

// `atlas_coords` is optional but, when given, both of its members are required:
// half an atlas coordinate is not a coordinate.
bool read_atlas_coords(const Dictionary &p_args, bool &r_given, Vector2i &r_atlas, MCPToolError &r_error) {
	r_given = false;
	if (!p_args.has("atlas_coords")) {
		return true;
	}
	const Variant value = p_args["atlas_coords"];
	if (value.get_type() != Variant::DICTIONARY) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'atlas_coords' must be an object {\"x\": int, \"y\": int}, got %s",
				Variant::get_type_name(value.get_type())));
		return false;
	}
	const Dictionary atlas = value;
	int x = 0;
	int y = 0;
	if (!nested_int(atlas, "x", "atlas_coords", true, 0, x, r_error) ||
			!nested_int(atlas, "y", "atlas_coords", true, 0, y, r_error)) {
		return false;
	}
	r_given = true;
	r_atlas = Vector2i(x, y);
	return true;
}

// `rect` is required; `width`/`height` must be given and positive (the migration
// source defaulted them to `1`, so a missing size silently filled one cell).
bool read_rect(const Dictionary &p_args, Rect2i &r_rect, MCPToolError &r_error) {
	Dictionary rect;
	if (!optional_dictionary(p_args, "rect", rect, r_error)) {
		return false;
	}
	if (rect.is_empty() && !p_args.has("rect")) {
		r_error = MCPToolError::invalid_params("Missing required parameter: rect");
		return false;
	}
	if (rect.is_empty()) {
		r_error = MCPToolError::invalid_params(
				"Parameter 'rect' must carry 'width' and 'height' (a rectangle is an area, not a point)");
		return false;
	}
	int x = 0;
	int y = 0;
	int width = 0;
	int height = 0;
	if (!nested_int(rect, "x", "rect", false, 0, x, r_error) ||
			!nested_int(rect, "y", "rect", false, 0, y, r_error) ||
			!nested_int(rect, "width", "rect", true, 0, width, r_error) ||
			!nested_int(rect, "height", "rect", true, 0, height, r_error)) {
		return false;
	}
	if (width <= 0 || height <= 0) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'rect' must have a positive width and height, got %dx%d", width, height));
		return false;
	}
	if ((int64_t)width * (int64_t)height > tilemap_rect_cell_cap()) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'rect' names %d cells (%dx%d), more than this tool writes in one call (%d). "
				"Split the area or use a smaller rectangle",
				width * height, width, height, tilemap_rect_cell_cap()));
		return false;
	}
	r_rect = Rect2i(x, y, width, height);
	return true;
}

} // namespace

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

static Variant _tool_set_tilemap_cell(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	int64_t x = 0;
	int64_t y = 0;
	int64_t source_id = 0;
	if (!require_int(p_args, "x", x, r_error) ||
			!require_int(p_args, "y", y, r_error) ||
			!require_int(p_args, "source_id", source_id, r_error)) {
		return Variant();
	}
	int cell_x = 0;
	int cell_y = 0;
	if (!int32_argument(x, "x", "a 32-bit tile coordinate", cell_x, r_error) ||
			!int32_argument(y, "y", "a 32-bit tile coordinate", cell_y, r_error)) {
		return Variant();
	}
	if (!value_fits_slot(Variant(source_id), ValueSlot::INT32, "source_id", "a 32-bit TileSet source id", r_error)) {
		return Variant();
	}
	bool atlas_given = false;
	Vector2i atlas;
	if (!read_atlas_coords(p_args, atlas_given, atlas, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor tilemap writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_tilemap_cell_on(root, node_path, cell_x, cell_y, (int)source_id, atlas_given, atlas, r_error);
}

static Variant _tool_set_tilemap_cells_in_rect(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	Rect2i rect;
	if (!read_rect(p_args, rect, r_error)) {
		return Variant();
	}
	int64_t source_id = 0;
	if (!require_int(p_args, "source_id", source_id, r_error)) {
		return Variant();
	}
	if (!value_fits_slot(Variant(source_id), ValueSlot::INT32, "source_id", "a 32-bit TileSet source id", r_error)) {
		return Variant();
	}
	bool atlas_given = false;
	Vector2i atlas;
	if (!read_atlas_coords(p_args, atlas_given, atlas, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor tilemap writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_tilemap_cells_in_rect_on(root, node_path, rect, (int)source_id, atlas_given, atlas, r_error);
}

static Variant _tool_remove_all_tilemap_cells(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor tilemap writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return remove_all_tilemap_cells_on(root, node_path, r_error);
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
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_tilemap_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_tilemap_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_remove_all_tilemap_cells", String::utf8(R"desc(清除所有格子)desc"));
		builder.channel("editor").verb("remove").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"node_path":{"type":"string"}},"required":["node_path"],"type":"object"})schema"));
		builder.handler(_tool_remove_all_tilemap_cells).register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_set_tilemap_cell", String::utf8(R"desc(设置瓦片地图单元格 写格子要求目标 TileMapLayer 的 TileSet 里已经存在一个 TileSetAtlasSource：project_create_resource 用 type=TileSet 只会造出一个空 TileSet（source_count=0，既没有 source 也没有 texture），而当前工具集没有任何“给 TileSet 添加 atlas source / texture / tile”的入口，所以在可预见的调用序列里本工具无法成功 —— 这是一处如实声明的能力缺口，不是本工具的缺陷；调用方要么在编辑器里手工建好带 atlas source 的 TileSet，要么在项目里自带一个含 source 的 .tres。TileSet 里没有该 source 时本工具以 -32602 拒绝，并在 data.suggestion 里点名它接受的参数。)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"atlas_coords":{"properties":{"x":{"type":"integer"},"y":{"type":"integer"}},"type":"object"},"node_path":{"type":"string"},"source_id":{"type":"integer"},"x":{"type":"integer"},"y":{"type":"integer"}},"required":["node_path","x","y","source_id"],"type":"object"})schema"));
		builder.handler(_tool_set_tilemap_cell).register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_set_tilemap_cells_in_rect", String::utf8(R"desc(填充瓦片地图矩形区域 写格子要求目标 TileMapLayer 的 TileSet 里已经存在一个 TileSetAtlasSource：project_create_resource 用 type=TileSet 只会造出一个空 TileSet（source_count=0，既没有 source 也没有 texture），而当前工具集没有任何“给 TileSet 添加 atlas source / texture / tile”的入口，所以在可预见的调用序列里本工具无法成功 —— 这是一处如实声明的能力缺口，不是本工具的缺陷；调用方要么在编辑器里手工建好带 atlas source 的 TileSet，要么在项目里自带一个含 source 的 .tres。TileSet 里没有该 source 时本工具以 -32602 拒绝，并在 data.suggestion 里点名它接受的参数。)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"atlas_coords":{"properties":{"x":{"type":"integer"},"y":{"type":"integer"}},"type":"object"},"node_path":{"type":"string"},"rect":{"properties":{"height":{"type":"integer"},"width":{"type":"integer"},"x":{"type":"integer"},"y":{"type":"integer"}},"type":"object"},"source_id":{"type":"integer"}},"required":["node_path","rect","source_id"],"type":"object"})schema"));
		builder.handler(_tool_set_tilemap_cells_in_rect).register_into(r_registry);
	}
}
