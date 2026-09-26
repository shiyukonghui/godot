/**************************************************************************/
/*  running_game_capture.cpp                                              */
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
#include "running_game_capture.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/crypto/crypto_core.h"
#include "core/io/image.h"
#include "core/string/ustring.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// running_game_capture_screenshot (old `get_game_screenshot`)
//
// Migration source (semantic reference, read-only):
// `godot_mcp_gdext/src/commands/editor.rs:362-418` (`cmd_get_game_screenshot`,
// the *editor-side* half) - it checked that the editor was playing a scene, then
// read `user://mcp_screenshot.png`, a file the game-side `MCPScreenshot` autoload
// was supposed to have written. The mapping to `running_game_*` is deliberate
// (`docs/tool-rename-map.json`: the picture is the *game's*, and the game is
// where it is produced); this module moves the production into the game process,
// which is exactly what makes the file handshake disappear.
//
// Observable contract (as implemented):
//   * `save_path` (string, optional);
//   * without it: `{"image_base64": <PNG>, "width": W, "height": H,
//     "format": "png"}` - the migration source's key set;
//   * with it: the PNG is written to that path and the answer is
//     `{"saved_path": <normalised path>, "width", "height", "format": "png"}`
//     (again the migration source's key set);
//   * `save_path` accepts `res://` or `user://` only, never `..`, and must name
//     a file -> `-32602` (the shared rule of `editor_capture_screenshot`);
//   * a process without a framebuffer (the `--headless` display server) ->
//     `-32000` with a suggestion; the underlying engine call
//     (`RendererDummy::TextureStorage::texture_2d_get`) logs an engine ERROR and
//     returns null, so it is never reached;
//   * a failing write is an error, and the write goes through
//     `publish_file_atomically`, so an existing file is never truncated by a
//     failed save (the rule TASK-008 section 2(c) established for the editor
//     sibling).
//
// Deviations from the migration source, all in one direction - "the tool really
// works" (PLAYBOOK section 6.6):
//   * the reference answered `McpError::internal` ("当前没有游戏在运行") when the
//     *editor* was not playing a scene. There is no editor on this side: the tool
//     runs in the game process, and "is a game running" is answered by whether a
//     SceneTree and a framebuffer exist;
//   * the reference wrote to `ProjectSettings::globalize_path(save_path)`, i.e.
//     any absolute path the caller named. This module addresses the project (and
//     `user://` where the contract asks for it) and never an arbitrary absolute
//     path, like every other writer of this module;
//   * the reference swallowed a failed save and answered a success with no file.
//     A failed save is an error here.
// ---------------------------------------------------------------------------
static Variant _tool_capture_screenshot(const Dictionary &p_args, MCPToolError &r_error) {
	String save_path;
	if (!optional_string(p_args, "save_path", String(), save_path, r_error)) {
		return Variant();
	}
	String target;
	if (!save_path.is_empty()) {
		if (!normalize_screenshot_path(save_path, target, r_error)) {
			return Variant();
		}
	}

	if (!game_framebuffer_available()) {
		r_error = MCPToolError::tool_state(
				"The running game has no framebuffer to read (the headless display server has no texture storage)",
				"Run the game with a display server (drop --headless, or use a build with a rendering driver) and call the tool again");
		return Variant();
	}

	// `false`: the contract has no `half_resolution` member, so the picture is
	// returned at the viewport's own size (the migration source's behaviour).
	Ref<Image> image = game_viewport_image(false);
	if (image.is_null()) {
		r_error = MCPToolError::tool_state(
				"The running game's root viewport could not be read back",
				"Call the tool while the game is drawing (after at least one rendered frame) and try again");
		return Variant();
	}

	Dictionary result;
	result["width"] = image->get_width();
	result["height"] = image->get_height();
	result["format"] = "png";

	if (target.is_empty()) {
		const Vector<uint8_t> png = image->save_png_to_buffer();
		if (png.is_empty()) {
			r_error = MCPToolError::internal("The captured frame could not be encoded as PNG");
			return Variant();
		}
		result["image_base64"] = CryptoCore::b64_encode_str(png.ptr(), (size_t)png.size());
		return result;
	}

	Ref<Image> held = image;
	const Error save_error = publish_file_atomically(target, screenshot_png_writer, &held);
	if (save_error != OK) {
		r_error = MCPToolError::internal(vformat("Failed to save the screenshot to '%s' (error %d)", target, (int)save_error));
		return Variant();
	}
	result["saved_path"] = target;
	return result;
}

// ---------------------------------------------------------------------------
// Registration
//
// The description and `inputSchema` are the byte-exact contract entries, emitted
// from docs/tools_list.renamed.json by `scripts/gen_b2_game_schema.py`; the
// declaration (`channel = running_game`, `scope = game`, `mutating = true`) comes
// from docs/tool-rename-map.json.
// ---------------------------------------------------------------------------

void register_running_game_capture_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("running_game_capture_screenshot", String::utf8("获取正在运行的游戏截图"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("保存路径 (可选)");
		v1[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("save_path")] = v1;
		schema[String::utf8("properties")] = v0;
		Array v2;
		schema[String::utf8("required")] = v2;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("capture").scope(MCPToolScope::GAME).mutating(true).schema(schema).handler(_tool_capture_screenshot);
		builder.register_into(r_registry);
	}
	// END generated
}