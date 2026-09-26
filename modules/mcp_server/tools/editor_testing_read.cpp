#include "editor_testing_read.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/crypto/crypto_core.h"
#include "core/core_bind.h"
#include "core/io/image.h"
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
			DirAccess::remove_absolute(bridge_path);
			cleared.push_back("game_process_file");
		}
	}
	answer["cleared"] = cleared;
	return answer;
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
			const int dr = ABS((int)a.r8 - (int)b.r8);
			const int dg = ABS((int)a.g8 - (int)b.g8);
			const int db = ABS((int)a.b8 - (int)b.b8);
			const int max_diff = MAX(dr, MAX(dg, db));
			if (max_diff > (int)threshold) {
				changed++;
				// The migration source's difference colour, verbatim.
				diff_image->set_pixel(x, y, Color(1, 0, 0, CLAMP((double)max_diff / 255.0, 0.3, 1.0)));
			} else {
				diff_image->set_pixel(x, y, Color(a.r * 0.3, a.g * 0.3, a.b * 0.3, 1.0));
			}
		}
	}

	const int64_t total = (int64_t)width * (int64_t)height;
	const Vector<uint8_t> diff_png = diff_image->save_png_to_buffer();
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

	// TASK-044 section 2.5 (GDR-25): the comparison itself is one definition in
	// `tool_helpers` now, shared with the call capture. The two checks above -
	// the size mismatch and the axis cap - stay here: they are *this tool's*
	// contract and they have to be decided in this order.
	ScreenshotDiff diff;
	if (!compare_screenshot_pixels(image_a, image_b, (int)threshold, true, "image_a", "image_b", diff, r_error)) {
		return Variant();
	}

	const Vector<uint8_t> diff_png = diff.diff_image->save_png_to_buffer();
	if (diff_png.is_empty()) {
		r_error = MCPToolError::internal("The difference image could not be encoded as PNG");
		return Variant();
	}

	Dictionary result;
	result["identical"] = diff.identical;
	result["changed_pixels"] = diff.changed_pixels;
	result["total_pixels"] = diff.total_pixels;
	result["diff_percentage"] = diff.diff_percentage;
	result["threshold"] = threshold;
	result["width"] = diff.width;
	result["height"] = diff.height;
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
		ToolBuilder builder("editor_get_test_report", String::utf8("获取测试结果报告 缺省（不给 clear）或 clear:false 是纯读取：不改变、不删除任何东西，cleared 为空数组；只有显式 clear:true 才会清空，并且会删除**共享**的桥接文件 user://mcp_test_report.json —— 该文件由同一编辑器进程的所有客户端共用，删除后其它尚未读取该报告的客户端就读不到了（cleared 会列出真正被清掉的范围：editor_process / game_process_file）。"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("default")] = false;
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