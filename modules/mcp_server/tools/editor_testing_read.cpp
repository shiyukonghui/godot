/**************************************************************************/
/*  editor_testing_read.cpp                                               */
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
#include "editor_testing_read.h"

// TASK-089 (item A): the file-side effect recorder, for the bridge-file removal
// of `editor_get_test_report`'s `clear` arm.
#include "../mcp_file_effects.h"
#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/crypto/crypto_core.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/image.h"
#include "core/math/math_funcs.h"
#include "core/string/ustring.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// editor_get_test_report (old `get_test_report`, test.rs:561-589)
//
// **The `fix_implementation_first` entry of B4, and what was really wrong.**
//
// The migration source answered, in every case, a JSON object whose `message`
// said 「使用 assert_node_state 等测试命令会自动收集结果。请查阅最近执行的测试命令输出。」
// and which listed the tool names that would supposedly have collected results.
// Its whole body was a GDScript `Expression` built from a literal string and a
// second literal fallback object; no accumulator, no state, no read of anything.
// A caller that ran `assert_node_state` and then asked for the report received
// the same sentence as a caller that had run nothing at all: a **fabricated
// success** in precisely the category TASK-019 section 1.1 forbids.
//
// The honest shape is not "refuse with -32000": the newer migration source shows
// the right answer (`addons/godot_mcp/commands/test_commands.gd:337-373`) and the
// module already has the two halves it needs - the assertion tools of B4 make
// verdicts, and `MCPTools::build_test_report` (`tools/tool_helpers.{h,cpp}`)
// aggregates whatever was recorded. So the tool reports **what really ran**:
//
//   * `total`      - assertions that carried a verdict;
//   * `passed` / `failed`;
//   * `pass_rate`  - `"%.1f%%"`, or `"N/A"` for an empty report;
//   * `all_passed` - false for an empty report ("nothing ran" is not "all green");
//   * `no_results` - true when nothing was recorded, which is the very thing the
//                    migration source was hiding;
//   * `details`    - the records themselves, in insertion order;
//   * `source`     - where the answer came from. TASK-022 D-6: it is
//                    `"game_process_file"` when the game process' persisted
//                    report was read (`user://mcp_test_report.json`, via the
//                    bridge of `tools/tool_helpers.*` - the file IPC the
//                    migration source used) and `"editor_process"` when only this
//                    process' accumulator was available. Saying so is the
//                    difference between "no results" and "the results are
//                    somewhere else", and after D-6 it is also the difference
//                    between "there is nothing" and "here is what really ran".
//
// Observable contract (as implemented):
//   * `clear` (boolean, **opt-in**, TASK-028 G-3) - when it is `true` the
//     **editor process'** accumulator and the persisted game report are emptied
//     *after* the answer has been built; when it is absent or `false` the call is
//     a pure read. The migration source's declared default was `true` and the
//     bridge file is shared, so its default deleted the report other clients had
//     not read yet; the safe behaviour is an explicit opt-in (the declared
//     schema default is left untouched here and reported to the decision maker).
//     The `cleared` list says which of the two was really emptied; the game
//     process' *memory* is not reachable from here and is not claimed to be (see
//     the implementation note below);
//   * `{"total","passed","failed","pass_rate","all_passed","no_results",
//     "details","source"}`, plus `report_path` / `report_file_present` /
//     `report_unavailable_reason` and `cleared` (TASK-022 D-6), plus
//     `report_written_at_unix` / `report_source_process` /
//     `report_format_version` when the persisted report was read;
//   * no argument is required and none is refused except a mistyped `clear`
//     (`-32602`);
//   * the process needs no editor: the accumulator is process state, so the tool
//     works (and is testable) in a build without `EditorInterface`.
//
// **Red-then-fix evidence (TASK-019 section 1.1)**: the doctest
// `[MCPServer] editor_get_test_report reports the assertions that really ran`
// was written against this contract *before* the implementation, and its first
// assertion is that an empty accumulator answers `no_results: true` with
// `total == 0`. The migration source's fixed message cannot satisfy it (it always
// carries a `message` string and never a `total`), and its GDScript-Expression
// shape cannot be reached from the module at all.
// ---------------------------------------------------------------------------
// TASK-022 D-6: the cross-process half.
//
// **What was still wrong after TASK-019.** The tool answered from the accumulator
// of *its own* process, and every `record_test_result` caller is a game-scope
// tool that the editor endpoint does not even register. So the editor-scope
// reader had no possible writer: the M4b re-audit measured `total: 0` for every
// sequence a client could produce, i.e. the contract's capability was
// unreachable. `source: "editor_process"` was honest and useless.
//
// **The fix is the file bridge, not a contract change** (the decision recorded in
// the task book, section 4): the game process persists its list to
// `user://mcp_test_report.json` on every `record_test_result` (`tools/tool_helpers.*`),
// and this tool reads that file. The migration source handed the report between
// its processes over a `user://` file in exactly this way.
//
// The answer therefore says **where it came from**, and it never invents a total:
//
//   * a usable file -> the report is aggregated from the persisted records, with
//     `source: "game_process_file"`, `report_path`, `report_written_at_unix` and
//     the writing process (`report_source_process`);
//   * no file, an unreadable file or an empty one -> the editor process' own
//     accumulator (normally empty) with `source: "editor_process"`,
//     `report_file_present` and `report_unavailable_reason` saying exactly what
//     was wrong. `total` is then 0 and `no_results` is true, which is the honest
//     answer and not a fabricated report.
//
// `clear: true` empties **both** things this tool can answer from - the editor
// process' accumulator and the persisted bridge file - so "the next call starts
// from nothing" holds across processes as well (`cleared` lists what was really
// emptied, and the file is only removed when it existed). TASK-028 G-3 makes that
// an explicit request instead of the default: a plain read leaves the shared file
// alone, so a second client still sees the whole report. The game process'
// *memory* cannot be reached from here and is not claimed to be: its next
// recorded assertion re-persists its own full list, which is stated in the
// header and in the report. The response says which processes were touched
// instead of pretending the other one was reset.
static Variant _tool_get_test_report(const Dictionary &p_args, MCPToolError &r_error) {
	// TASK-028 G-3: **reading is not destroying.**
	//
	// The migration source's flag kept its declared default of `true`, and the
	// bridge file is *shared* (`user://`, one file for every client of the same
	// editor process), so the first client to read deleted the report the others
	// had not read yet - a read with a side effect nobody asked for (measured by
	// the M4c acceptance as G-3).
	//
	// The flag is therefore an **opt-in** now: absent and `false` both mean a pure
	// read, and only an explicit `clear: true` empties what this call answered
	// from. The two halves of "clear" stay separate and are reported separately in
	// `cleared`, because they belong to two different processes: `editor_process`
	// is this process' own accumulator, `game_process_file` is the shared bridge
	// file. The game process' *memory* is still not reachable from here and is not
	// claimed to be - its next recorded assertion re-persists its own full list.
	//
	// **Contract note (closed by TASK-029):** the registered `inputSchema` used to
	// still declare `"clear": {"default": true}` - the safe behaviour and the
	// declared one differed, and REPORT-028 raised that to the decision maker
	// instead of silently rewriting the byte-exact contract of
	// `docs/tools_list.renamed.json` (which may only change through
	// `SCHEMA_OVERRIDES`, GDR-25 section 23.2 point 5). The ruling was "fix the
	// contract, not the behaviour" (option A): the declaration is now `false` and
	// the description names the shared file, both emitted by
	// `scripts/gen_renamed_contract.py` and copied into the registration block
	// below byte for byte. This function itself never changed.
	bool clear = false;
	if (!optional_bool(p_args, "clear", false, clear, r_error)) {
		return Variant();
	}

	const String bridge_path = test_report_bridge_path();
	const bool file_present = FileAccess::exists(bridge_path);
	Array records;
	Dictionary meta;
	bool found = false;
	String read_reason;
	load_persisted_test_report_from(bridge_path, records, meta, found, read_reason);

	Dictionary answer;
	if (found) {
		answer = build_test_report_from(records);
		answer["source"] = "game_process_file";
		answer["report_path"] = bridge_path;
		answer["report_file_present"] = true;
		answer["report_written_at_unix"] = (int64_t)meta.get("written_at_unix", Variant(0.0));
		answer["report_source_process"] = String(meta.get("source_process", String("game")));
		answer["report_format_version"] = (int64_t)meta.get("version", Variant(0.0));
	} else {
		// The editor process' own list (see the header). `total: 0` with
		// `no_results: true` is the honest answer when no game report is there;
		// the reason field says which of the two cases it was.
		answer = build_test_report();
		answer["source"] = "editor_process";
		answer["report_path"] = bridge_path;
		answer["report_file_present"] = file_present;
		answer["report_unavailable_reason"] = read_reason;
	}
	Array cleared;
	if (clear) {
		clear_test_results();
		cleared.push_back("editor_process");
		if (file_present) {
			// TASK-089 (item A): this arm deletes the bridge file, so it is a
			// file mutation and is recorded as one.
			// [REBUILT-2C low-confidence: verify] TASK-089 item A: written, not
			// replayed; REBUILT-2C-MANIFEST.md 2c-8 (H-2).
			MCPFileEffect::MutationScope bridge_delete(bridge_path, "delete");
			if (DirAccess::remove_absolute(bridge_path) != OK) {
				bridge_delete.mark_failed();
			}
			// [/REBUILT-2C]
			cleared.push_back("game_process_file");
		}
	}
	answer["cleared"] = cleared;
	return answer;
}

// ---------------------------------------------------------------------------
// editor_analyze_screenshot_diff (old `compare_screenshots`, editor.rs:509-608)
//
// Observable contract (as implemented):
//   * `image_a` / `image_b` (string, required, must not be blank): a project path
//     (`res://` or `user://`) or a base64 PNG. The migration source's own
//     discriminator is kept - `begins_with("res://") or begins_with("user://")`
//     is a path, everything else is base64 - and a base64 string that does not
//     decode is `-32001` naming the argument;
//   * `threshold` (integer, default 10, 0..255): a pixel counts as changed when
//     the **largest per-channel absolute difference of its RGB bytes** is
//     strictly greater than it. `-32602` outside 0..255 (the migration source
//     cast an arbitrary JSON integer to `i32` and used it as a threshold, so
//     `threshold: -1` marked every pixel changed and `threshold: 300` marked
//     none - a parameter that cannot mean anything must not be silently used);
//   * a size mismatch is `-32602` (the migration source's `size_mismatch`
//     branch, which its caller mapped to invalid_params);
//   * `{"identical", "changed_pixels", "total_pixels", "diff_percentage",
//     "threshold", "width", "height", "diff_image_base64"}`, with
//     `diff_percentage` rounded to two decimals (`snappedf(diff_pct, 0.01)` in
//     the migration source) and the difference image built exactly like the
//     migration source's: changed pixels get `Color(1, 0, 0, clamp(max_d/255,
//     0.3, 1.0))`, unchanged ones `Color(r*0.3, g*0.3, b*0.3, 1.0)`.
//
// **Deviations from the migration source, all deliberate:**
//   1. the migration source *generated GDScript source text* with both arguments
//      interpolated into it after escaping only `\` and `"` (`escaped_a` /
//      `escaped_b`). That is a code-injection surface by construction; here the
//      two images are loaded by the engine directly and no caller text is ever
//      parsed as code.
//   2. **no display server is needed.** The migration source ran the load
//      through an editor `Expression`, which needs a full editor; `Image::load`
//      and `Image::load_png_from_buffer` are CPU-side, so this tool also works
//      in a `--headless` process. That is measured and used by the batch's
//      evidence: the diff of two scratch PNGs is a **headless** success case.
//   3. the comparison walks the u8 colour fields (`Color::r8`/`g8`/`b8`), which
//      is what the GDScript `int(ca.r8)` spelling reads, instead of the
//      float `Color::r` and its 0..1 rounding.
//   4. a size cap. The pixel loop is O(width*height) with a per-pixel
//      `get_pixel`/`set_pixel`, and the migration source's own `total` is
//      `width*height`; a 16384x16384 pair would be a ~10 minute request that the
//      framework would time out mid-way. The cap is therefore stated in the
//      refusal (`-32602`) rather than discovered as a timeout.
// ---------------------------------------------------------------------------

// The largest image this tool will diff, on each axis. See deviation 4 above.
static const int64_t MAX_DIFF_DIMENSION = 4096;

// A base64 decoder for the two arguments of this tool, local to the file.
//
// Why not `Marshalls::base64_to_raw`: the module's own note on
// `project_read_files.cpp:397` records that the engine's `Marshalls` singleton is
// not reachable from a module at all in this fork (its `get_singleton()` answers
// null outside the script-language setup), and `MCPTools` already depends on
// `CryptoCore` for the *encode* half (`running_game_frame_observation.cpp`,
// `editor_testing_read.cpp`'s own diff writer). A decode is twenty lines and has
// no singleton to fail on, so it is written once, here, where it is needed.
//
// The rules are RFC 4648's: the alphabet plus `=` padding, whitespace ignored
// anywhere (the migration source's caller could paste a wrapped payload), and a
// length that is not a multiple of four is rejected. A `-`/`_` URL-safe alphabet
// is deliberately *not* accepted: the caller is expected to send the standard
// spelling, and guessing between the two alphabets is how a payload is silently
// mis-decoded.
static bool _decode_base64(const String &p_text, Vector<uint8_t> &r_out) {
	static const char *const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	int values[256];
	for (int i = 0; i < 256; i++) {
		values[i] = -1;
	}
	for (int i = 0; i < 64; i++) {
		values[(uint8_t)ALPHABET[i]] = i;
	}

	int accumulator = 0;
	int bits = 0;
	int padding = 0;
	bool saw_padding = false;
	r_out.clear();
	for (int i = 0; i < p_text.length(); i++) {
		const char32_t c = p_text[i];
		if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
			continue;
		}
		if (c == '=') {
			saw_padding = true;
			padding++;
			continue;
		}
		if (c > 127 || values[c] < 0 || saw_padding) {
			// A character outside the alphabet, or data after the padding: not
			// base64.
			return false;
		}
		accumulator = (accumulator << 6) | values[c];
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			r_out.push_back((uint8_t)((accumulator >> bits) & 0xFF));
		}
	}
	// A trailing group of 6 bits is a truncated symbol, and more than two pad
	// characters cannot appear in a valid encoding.
	if (bits >= 6 || padding > 2) {
		return false;
	}
	return !r_out.is_empty();
}

static bool _load_png_base64(const String &p_base64, Ref<Image> &r_out) {
	Vector<uint8_t> bytes;
	if (!_decode_base64(p_base64, bytes)) {
		return false;
	}
	Ref<Image> image;
	image.instantiate();
	if (image->load_png_from_buffer(bytes) != OK) {
		return false;
	}
	r_out = image;
	return true;
}

// One argument: a project path or a base64 PNG. Fills `r_error` on every failure
// and returns an invalid Ref. The wording names the caller's own argument, so the
// two call sites below need no separate messages.
static Ref<Image> _load_diff_image(const Dictionary &p_args, const String &p_key, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter: " + p_key);
		return Ref<Image>();
	}
	if (value.get_type() != Variant::STRING) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be a string, got %s",
				p_key, Variant::get_type_name(value.get_type())));
		return Ref<Image>();
	}
	const String text = (String)value;
	if (text.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter '" + p_key + "' must not be empty");
		return Ref<Image>();
	}

	if (text.begins_with("res://") || text.begins_with("user://")) {
		Ref<Image> image;
		image.instantiate();
		const Error err = image->load(text);
		if (err != OK) {
			r_error = MCPToolError::not_found(vformat("Image '%s'", text),
					"Check the path with project_get_filesystem_tree, or send the PNG as base64 instead of a path");
			return Ref<Image>();
		}
		return image;
	}

	Ref<Image> image;
	if (!_load_png_base64(text, image)) {
		r_error = MCPToolError::not_found(vformat("The base64 PNG in parameter '%s'", p_key),
				"Send either a res:// or user:// path to a PNG, or the raw base64 of a PNG (no data: prefix)");
		return Ref<Image>();
	}
	return image;
}

static Variant _tool_analyze_screenshot_diff(const Dictionary &p_args, MCPToolError &r_error) {
	int64_t threshold = 10;
	if (!optional_int(p_args, "threshold", 10, threshold, r_error)) {
		return Variant();
	}
	if (threshold < 0 || threshold > 255) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'threshold' must be between 0 and 255 (it is a per-channel byte difference), got %d", (int)threshold));
		return Variant();
	}

	const Ref<Image> image_a = _load_diff_image(p_args, "image_a", r_error);
	if (image_a.is_null()) {
		return Variant();
	}
	const Ref<Image> image_b = _load_diff_image(p_args, "image_b", r_error);
	if (image_b.is_null()) {
		return Variant();
	}

	const int width = image_a->get_width();
	const int height = image_a->get_height();
	if (width != image_b->get_width() || height != image_b->get_height()) {
		r_error = MCPToolError::invalid_params(vformat(
				"Image size mismatch: image_a is %dx%d and image_b is %dx%d",
				width, height, image_b->get_width(), image_b->get_height()));
		return Variant();
	}
	if (width > MAX_DIFF_DIMENSION || height > MAX_DIFF_DIMENSION) {
		r_error = MCPToolError::invalid_params(vformat(
				"Image is %dx%d; this tool diffs at most %dx%d pixels (the comparison is per pixel)",
				width, height, (int)MAX_DIFF_DIMENSION, (int)MAX_DIFF_DIMENSION));
		return Variant();
	}

	Ref<Image> diff_image = Image::create_empty(width, height, false, Image::FORMAT_RGBA8);

	int64_t changed = 0;
	for (int y = 0; y < height; y++) {
		for (int x = 0; x < width; x++) {
			const Color a = image_a->get_pixel(x, y);
			const Color b = image_b->get_pixel(x, y);
			// `Color::get_r8()` is this fork's own 8-bit accessor (the GDScript
			// `Color.r8` property binding, `color.h:233`); the float `Color::r` is
			// multiplied by 255 and *rounded* inside it, which is exactly the
			// "per channel byte difference" the threshold is defined in.
			const int dr = Math::abs(a.get_r8() - b.get_r8());
			const int dg = Math::abs(a.get_g8() - b.get_g8());
			const int db = Math::abs(a.get_b8() - b.get_b8());
			const int max_diff = MAX(dr, MAX(dg, db));
			if (max_diff > (int)threshold) {
				changed++;
				// The migration source's difference colour, verbatim.
				// MCP-NARROWING: G24-DIFF-PIXEL-CHANGED - both `Color(...)` calls
				// below build `float` components out of *computed* values this
				// function owns: `CLAMP(max_diff/255.0, 0.3, 1.0)` is bounded to
				// [0.3, 1], and `a.r * 0.3` is a product of two values the engine
				// already stores as 32-bit floats. No caller input reaches them,
				// so no gate is possible or needed (TASK-023 D-7 scan entry).
				diff_image->set_pixel(x, y, Color(1, 0, 0, CLAMP((double)max_diff / 255.0, 0.3, 1.0)));
			} else {
				// MCP-NARROWING: G24-DIFF-PIXEL-UNCHANGED - see above.
				diff_image->set_pixel(x, y, Color(a.r * 0.3, a.g * 0.3, a.b * 0.3, 1.0));
			}
		}
	}

	const int64_t total = (int64_t)width * (int64_t)height;
	const Vector<uint8_t> diff_png = diff_image->save_png_to_buffer();
	if (diff_png.is_empty()) {
		r_error = MCPToolError::internal("The difference image could not be encoded as PNG");
		return Variant();
	}

	const double diff_percentage = (double)changed / (double)total * 100.0;

	Dictionary result;
	result["identical"] = changed == 0;
	result["changed_pixels"] = changed;
	result["total_pixels"] = total;
	// `snappedf(diff_pct, 0.01)`: two decimals, the migration source's own
	// rounding (`stepify`), applied so two runs print the same number.
	result["diff_percentage"] = Math::snapped(diff_percentage, 0.01);
	result["threshold"] = threshold;
	result["width"] = width;
	result["height"] = height;
	result["diff_image_base64"] = CryptoCore::b64_encode_str(diff_png.ptr(), (size_t)diff_png.size());
	return result;
}

// ---------------------------------------------------------------------------
// Registration
//
// Order follows docs/tool-groups-b4.json. Every declaration comes from
// docs/tool-rename-map.json (`channel = editor`, `scope = editor`,
// `mutating = false`); the description and the `inputSchema` are a byte-exact
// copy of the entries of docs/tools_list.renamed.json, emitted from that file by
// `scripts/gen_b2_game_schema.py --in-place` and not retyped; re-running the
// generator reproduces this block byte for byte.
// ---------------------------------------------------------------------------

void register_editor_testing_read_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("editor_get_test_report", String::utf8("获取测试结果报告"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("default")] = true;
		v1[String::utf8("description")] = String::utf8("是否清除结果");
		v1[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("clear")] = v1;
		schema[String::utf8("properties")] = v0;
		Array v2;
		schema[String::utf8("required")] = v2;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false).schema(schema).handler(_tool_get_test_report);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("editor_analyze_screenshot_diff", String::utf8("比较两张截图并生成差异图"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("第一张图片 (路径或 base64 PNG)");
		v1[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("image_a")] = v1;
		Dictionary v2;
		v2[String::utf8("description")] = String::utf8("第二张图片 (路径或 base64 PNG)");
		v2[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("image_b")] = v2;
		Dictionary v3;
		v3[String::utf8("default")] = 10;
		v3[String::utf8("description")] = String::utf8("像素差异阈值 (0-255)");
		v3[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("threshold")] = v3;
		schema[String::utf8("properties")] = v0;
		Array v4;
		v4.push_back(String::utf8("image_a"));
		v4.push_back(String::utf8("image_b"));
		schema[String::utf8("required")] = v4;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("editor").verb("analyze").scope(MCPToolScope::EDITOR).mutating(false).schema(schema).handler(_tool_analyze_screenshot_diff);
		builder.register_into(r_registry);
	}
	// END generated
}
