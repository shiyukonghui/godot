/**************************************************************************/
/*  tool_helpers.h                                                        */
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

#include "core/io/dir_access.h"
#include "core/io/image.h"
#include "core/math/math_funcs.h"
#include "core/object/object.h"
#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "core/variant/variant_utility.h"

// `Node` and `SceneTree` are only ever used through a pointer by the game-scene
// helpers declared below, so the two class names are forward declared instead of
// dragging `scene/` into every translation unit that needs `serialize_variant`.
// `InputMap` is the same story for the TASK-041 `[input]` helpers below: no
// translation unit needs its definition to *call* them, and `core/input/` would
// otherwise be pulled into every file that includes this header.
class InputMap;
class Node;
class Resource;
class SceneTree;
// TASK-063 (d): `reload_gdscript_capturing` takes a raw `Script *` (the callers
// pass `Ref<Script>::ptr()`), so the class name is all this header needs.
class Script;

// `MCPToolError` (`../tool_registry.h`) and `is_editor_process()` plus the
// `MCP_EDITOR_TOOLS_ENABLED` definition (`tool_builder.h`). The include is what
// makes the editor guard below one function instead of one per group file.
#include "tool_builder.h"

// ---------------------------------------------------------------------------
// Shared MCP tool helpers (TASK-005 section 1).
//
// These four functions used to exist twice: once as file-private helpers of
// `tools/project_read_analysis.cpp` and once, for the three that group also
// needed, in `tools/project_read_template.cpp`. Internal linkage made them
// impossible to share across group files, and the second copy was a copy of the
// first byte for byte (verified with a function-level sha256 before the hoist,
// see REPORT-005 section "reconstruction equivalence"). They live here now so
// that every group file has exactly one definition to call and no new copy is
// created by the next group.
//
// The bodies are verbatim moves: only the `static` keyword, the leading `_` and
// the recursive self-calls changed. Behaviour is pinned byte for byte by the
// before/after `tools/list` and tool-response comparison in REPORT-005.
//
// They are deliberately free of singletons and of any IO policy decision: the
// caller decides which directory to walk and what to do with the result.
// ---------------------------------------------------------------------------

namespace MCPTools {

// `res://a/b` -> `res://a/b/c`; the root keeps exactly one slash.
String join_path(const String &p_dir, const String &p_entry);

// Rust's `str::lines()`: splits on '\n', drops a trailing '\r' and does not
// invent a final empty line for a trailing newline. The line count of
// project_get_statistics and the line numbers of
// project_find_script_references have to agree with the reference, so this is
// spelled out instead of using `String::split` directly.
Vector<String> split_lines(const String &p_text);

// Mirrors `serialize_variant` of the reference implementation: everything that
// is not directly JSON representable is converted into a plain structure, so
// that `JSON::stringify` never has to deal with an engine-only type.
//
// Shape rule (TASK-024b E-3, GDR-25 section 23.1 rule 4): a value answers the
// shape of its *kind*, so one read-back never mixes "object" and "string" for
// values of the same kind and both can be fed back into a write as they are.
//   * `Vector2/2i/3/3i/4/4i`, `Color`, `Rect2/Rect2i` -> a JSON object naming
//     the components (`{"x":..,"y":..,"z":..,"w":..}`, `{"r","g","b","a"}`,
//     `{"x","y","width","height"}`); the number kind follows the engine's
//     (a `Vector4i` answers integers, a `Vector4` doubles).
//   * a packed array -> a JSON array whose elements are what the element alone
//     answers (`PackedVector4Array` -> `[{x,y,z,w}, ...]`), `PackedByteArray`
//     -> an array of integers (`[1,200]`, the shape the write side takes back).
//   * an `Object` -> `{"type": <class>, "value": <to_string()>}`.
//   * anything else (the matrix/transform family: `Transform2D/3D`, `Basis`,
//     `Quaternion`, `Plane`, `Projection`, `AABB`, `RID`, `Callable`, ...) is
//     still `p_value.stringify()` - a string. That is the remaining half of E-3
//     and is recorded as such in REPORT-024b; no tool in the module currently
//     reads one of those types back.
Variant serialize_variant(const Variant &p_value);

// Mirrors `collect_files_by_ext` of the reference: hidden entries (anything
// whose name starts with '.', which covers "." and ".." as well) are skipped,
// `addons` is only descended into on request, and the extension test is case
// insensitive (`to_lowercase()` in the reference).
void collect_files_by_extension(const String &p_path, const Vector<String> &p_extensions,
		bool p_include_addons, Vector<String> &r_out);

// ---------------------------------------------------------------------------
// Atomic publish (hoisted by TASK-008 section 3 from the file-private helpers of
// `tools/project_write_resource_scene.cpp`; TASK-007 wrote them there).
//
// `ResourceSaver::save()` - and every other engine writer used by a tool - writes
// straight into the destination, so a failure in the middle of a write can leave
// a truncated (that is, corrupted) file where the caller's data used to be.
// `publish_file_atomically` never lets that happen: the bytes are produced into a
// temporary sibling first and the destination is only touched once the writer
// reported success and the temporary file is really there.
// ---------------------------------------------------------------------------

// A sibling of `p_path` that lives in the same directory (so publishing is a
// rename on one volume, never a cross-device copy) and is recognisably temporary.
//
// Two constraints decide the exact shape:
//
//   1. the *extension has to stay the last component*. `ResourceSaver::save()`
//      picks the format saver through `ResourceFormatSaver::recognize_path()`,
//      which compares `p_path.get_extension()` (the text after the **last** dot)
//      against the saver's extension list. A name like `created.tres.mcp-tmp`
//      therefore has the extension `mcp-tmp`, and every save fails with "File
//      unrecognized" - a measured bug of an earlier revision (REPORT-007
//      section 8.1). The scratch name is inserted *before* the extension, so the
//      saver still sees `tres`;
//   2. the name is plain and deterministic (no leading dot, no per-call random
//      suffix), so it is visible in a directory listing, overwritten by the next
//      call and removed on every path. A hidden or per-call-unique name was tried
//      and rejected: Godot's `ResourceSaver::save()` runs its `save_callback` for
//      `res://` paths *before* the caller renames the file, so the editor's
//      resource filesystem records the scratch path either way and leaves a
//      `<path>-folding-<hash>.cfg` in `.godot/editor/` - measured. Keeping the
//      scratch file in the open is the honest option.
String temporary_sibling_path(const String &p_path);

// Produces the bytes of `p_path` into `p_temp_path`; returns OK only when the
// whole file is there. A plain function pointer (plus an opaque userdata) is used
// instead of `std::function` so that the helper stays allocation free and matches
// the engine's own `ResourceSaver::save_callback` shape.
typedef Error (*AtomicWriteFunc)(const String &p_temp_path, void *p_userdata);

// Writes `p_path` through `p_write` with a backup + rename publish:
//
//   * when the destination does not exist, `DirAccess::rename_absolute` is a
//     single MoveFile - the new file appears complete or not at all;
//   * when it does exist, the old bytes are copied aside first; if the publish
//     step fails, the copy is put back, so the original is preserved.
//
// On every failure path the temporary file (and the backup) is removed: a caller
// may not leave a half-written artefact behind. The parent directory is created
// when it is missing and the destination does not exist yet.
Error publish_file_atomically(const String &p_path, AtomicWriteFunc p_write, void *p_userdata);

// The `AtomicWriteFunc` for a whole text file, plus the one-line wrapper every
// text-file writer of a *new* group uses (TASK-035: `project_create_shader` /
// `project_edit_shader`). The existing text writer of `project_script_write` keeps
// its own private callback because a group file may not be refactored by another
// group's batch (PLAYBOOK section 2.4); this one exists so the shader group does
// not become the third copy of the same seventeen lines.
Error publish_text_atomically(const String &p_path, const String &p_text);

// ---------------------------------------------------------------------------
// project.godot atomic publish (added by TASK-018 section 3).
//
// `ProjectSettings::save()` writes straight into `project.godot`
// (`project_settings.cpp`: `save_custom(get_resource_path().path_join("project.godot"))`),
// so a failure in the middle of that write can leave a truncated
// **project.godot** - the file the whole project is addressed by. Both B3 groups
// that change a project setting (`project_autoload_write` and
// `project_setting_write`) therefore publish through the one atomic path
// instead, and a group may not copy the helper (PLAYBOOK section 2.4), so it
// lives here.
//
// The writer is `ProjectSettings::save_custom(temp_path)`: it is exactly the
// function `save()` reaches, it selects the text format from the `.godot`
// suffix, and the temporary sibling keeps that suffix
// (`project.mcp-tmp.godot`, see `temporary_sibling_path`), so the published file
// is byte-for-byte what `ProjectSettings::save()` would have written.
// ---------------------------------------------------------------------------

// The absolute path of the project's `project.godot`.
String project_settings_file_path();

// Publishes the current in-memory `ProjectSettings` to `project.godot` through
// `publish_file_atomically`. On failure `r_error` is a `-32603` naming the
// engine error, and the destination still holds its previous bytes.
bool publish_project_settings(MCPToolError &r_error);

// The same publish, to an explicit destination. `project_setting_write` and
// `project_autoload_write` always use `publish_project_settings()`; this entry
// point exists because the doctest process runs against the *engine source
// tree* (there is no `project.godot` there), so the only place a doctest may
// exercise the atomic project-settings publish is a file it owns itself. The
// bytes written are the engine's own (`save_custom`), so the assertion still
// covers the real writer.
bool publish_project_settings_to(const String &p_target_path, MCPToolError &r_error);

// ---------------------------------------------------------------------------
// Section-granular `project.godot` publish (TASK-059 D-4). The engine half is
// TASK-057 patch 2: `ProjectSettings::save_custom_section()`.
//
// The whole-file writer above regenerates `project.godot` out of the in-memory
// settings: it writes the engine's own fixed header and re-emits every setting,
// so every hand written comment in the file is lost (`_save_settings_text()`,
// `core/config/project_settings.cpp:1170-1210`). For a call that changes exactly
// one setting that loss is needless, and since TASK-057 the engine can do
// better: `save_custom_section()` rewrites **only** the named section and copies
// every other byte of the file through - comments, blank lines, key order, a
// UTF-8 BOM and CRLF line endings included
// (`core/config/project_settings.h:209-241`, `project_settings.cpp:1537-1779`).
//
// The key's section is the part before its **first** `/`
// (`_get_property_list()` splits on the first separator, `project_settings.cpp:
// 1312-1319`), which is also the rule `save_custom_section()` enforces on its
// `p_custom` argument (`project_settings.cpp:1552-1554`).
//
// `r_whole_file` is the honesty channel for the declared fall-backs. It is set
// to `true` exactly when the whole-file writer did the publish - i.e. when the
// comments in the file were destroyed. The four cases, all of them things the
// section writer cannot serve, are named in the contract descriptions of the
// tools that call this:
//
//   1. the key names **no** section: it has no `/`, or its `/` is the first
//      character. `_save_settings_text()` writes such a key into the header-less
//      global block at the top of the file (`category = ""`, `:1314-1315`), and
//      that block has no section name to hand `save_custom_section()`;
//   2. the destination **does not exist yet**: `save_custom_section()` publishes
//      *into* a file and never creates one (`ERR_FILE_NOT_FOUND`, `:1685-1689`),
//      while the whole-file writer does create it. The fall-back is what keeps
//      the pre-TASK-059 behaviour of that case;
//   3. the **engine refuses** the section write: a section name carrying `[`,
//      `]` or a line break, a value it cannot serialize, or a file it cannot read
//      back (`:1540-1558`, `:1691-1710`). The whole-file writer is then the only
//      writer that can still produce the requested end state;
//   4. the file already carries the same setting name in its header-less **global
//      block**. `ConfigFile` names that block with the empty section string
//      (`core/io/config_file.cpp:282/298`), and `ProjectSettings` resolves a
//      `section/key` line written there to the very setting name a section
//      publish is about to write - so a section publish would leave a stale
//      duplicate line behind instead of normalising it the way the whole-file
//      writer does. A file that cannot be read as a config file at all counts as
//      this case: surgery on a file the engine's own reader rejects is not
//      attempted.
//
// What this deliberately does **not** do: remove a key.
// `update_settings_section_text()` never deletes one (`project_settings.h:
// 226-227`), so a tool that clears a setting (`project_remove_autoload`) stays on
// the whole-file writer and says so in its own description.
// ---------------------------------------------------------------------------

// The section a setting key belongs to: the part before its first `/`, or an
// empty string when the key has no section (fall-back case 1).
String project_setting_section(const String &p_key);

// Publishes the **current in-memory value** of `p_key`, so what lands in the file
// is exactly what the whole-file writer would have written for that key
// (`_save_settings_text()` reads `get(key)`, `project_settings.cpp:1200`). The
// caller is expected to have called `set_setting()` first.
//
// `r_whole_file` may be null; when it is not, it always reports which writer ran,
// on success and on failure alike.
bool publish_project_setting(const String &p_key, bool *r_whole_file, MCPToolError &r_error);
bool publish_project_setting_to(const String &p_target_path, const String &p_key, bool *r_whole_file, MCPToolError &r_error);

// ---------------------------------------------------------------------------
// `project.godot`'s `[input]` section (added by TASK-041 section 2; the
// RACING-FINDINGS M-6 / RACING-DEV-LOG E-4 capability gap).
//
// `editor_add_input_action` wrote only the editor process' `InputMap` singleton:
// the action was live in that one process and nowhere else, so a running game
// could never see it. The engine's own bridge between the two worlds is the
// `[input]` section of `project.godot`:
// `InputMap::load_from_project_settings()` (`core/input/input_map.cpp:325-358`)
// rebuilds the map at startup from every `input/<action>` entry, where an entry
// is a Dictionary with `"deadzone"` and `"events"` - and an entry **without**
// `"events"` is skipped. These helpers are that bridge:
//
//   * the value is built from the live **map**, not from the request, so what is
//     published is the action's real state (its `deadzone` included) and a second
//     identical call publishes the same bytes (idempotent);
//   * the publish goes through `publish_project_setting_to()`, i.e. the engine's
//     own `save_custom_section()` (TASK-059 D-4), which replaces the target
//     section through a temporary sibling plus a backup and a rename, so
//     `project.godot` is never truncated by a failed publish **and** every byte
//     outside `[input]` - hand written comments included - is preserved. The
//     whole-file writer is still the declared fall-back (see the four cases
//     above); it is the writer that creates the file when it does not exist yet;
//   * `r_persisted` is the result of **reading the file back off disk**: the
//     published bytes are parsed with `ConfigFile` (the engine's own reader, with
//     objects allowed - `core/io/config_file.cpp:289`) and compared with what was
//     meant to be written. "I called the writer" is not evidence that the file
//     changed.
//
// Two refusals are reported as `false` plus a reason rather than as an MCP error,
// because the in-memory write the tool already performed did happen:
//   * a name that cannot be a project setting key (`input/<name>` is split by
//     `ProjectSettings` on `/` and reinterpreted on `.`);
//   * a process without a `project.godot`. This helper never **creates**
//     `project.godot`: publishing to a destination that does not exist yet is
//     reachable only through the explicit-destination entry point a test owns.
// ---------------------------------------------------------------------------

// The `ProjectSettings` key of an action: `"input/" + p_action`.
String input_action_setting_key(const String &p_action);

// Builds the engine's `input/<action>` value for `p_action` out of the live
// `InputMap`: `{"deadzone": <the map's>, "events": [<its events>]}`. Returns
// false and fills `r_reason` when the name cannot be addressed as a setting.
bool input_action_project_value(InputMap *p_map, const String &p_action, Dictionary &r_value, String &r_reason);

// Reads `input/<action>` back **from the file at `p_path`** (never from the
// in-memory `ProjectSettings`) and compares it with `p_expected`, the value
// `input_action_project_value()` produced. Returns false with `r_reason` naming
// the first difference. The comparison is structural, and it has to be:
//   * the engine writes a 32-bit float as its float text (`rtos_fix`,
//     `core/variant/variant_parser.cpp:1857`): `0.2f` is written as `0.2` and
//     parses back as the **double** 0.2, so the deadzone is compared as the
//     `float` the engine's own `InputMap::Action::deadzone` holds;
//   * `Variant` equality on an object is identity and a parsed
//     `Object(InputEventKey,...)` is a new object, so the event arrays are
//     compared by class name and, for keys, by keycode.
bool read_input_action_from_disk(const String &p_path, const String &p_action, const Dictionary &p_expected, String &r_reason);

// Sets `input/<action>` in this process' `ProjectSettings`, publishes it to
// `p_target_path`, reads it back from disk. A failed publish puts the in-memory
// setting back the way it was, so memory and disk agree. The return value **is**
// the read-back verdict - "the action is on disk, verified by parsing the file
// that is there now" - and `r_reason` is empty exactly when it is true. The
// `InputMap` edit itself is **not** rolled back: it is the tool's original,
// documented in-memory behaviour.
//
// TASK-042 section 3 (O-6 honesty): `r_publish` (optional) reports what this
// call did to the `[input]` **entry on disk**, which `persisted` alone cannot
// say. The distinction it exists for: a name this process already knows - every
// engine built-in (`ui_accept`, ...) is one, added by `InputMap::load_default()`
// in `main/main.cpp:2333` - makes the tool answer `created: false` while it is
// still writing that action's bindings into `project.godot` for the first time.
// "nothing new" and "an existing action was mirrored into the project" must not
// read the same.
enum class InputActionPublish {
	// Nothing was written: no `project.godot`, a name ProjectSettings cannot
	// address as one key, no `ProjectSettings`, or a publish that failed before
	// the file was touched.
	None,
	// The file (or the `input/<action>` entry in it) did not exist before this
	// call, so the entry is new.
	Created,
	// An entry was already on disk with a different value, and this call
	// replaced it.
	Replaced,
	// An entry was already on disk with exactly this value: the re-publish is
	// idempotent and the bytes did not change.
	Unchanged,
	// The publish reported OK but the read-back could not confirm the file, so
	// what is on disk now is not known. `persisted` is false in this case.
	Unknown,
};

// The wire spelling of the above, for the tool's `project_entry` field.
const char *input_action_publish_name(InputActionPublish p_publish);

bool persist_input_action_to(InputMap *p_map, const String &p_action, const String &p_target_path, String &r_reason, InputActionPublish *r_publish = nullptr);

// The same, against this process' real `project.godot` - the one the tool calls.
// A process without a `project.godot` on disk refuses honestly (and never
// creates one): that is the doctest process, which runs against the engine
// source tree, and any `--check-only`-style process without a project. It
// reports `InputActionPublish::None` in that case.
bool persist_input_action(InputMap *p_map, const String &p_action, String &r_reason, InputActionPublish *r_publish = nullptr);

// ---------------------------------------------------------------------------
// Screenshot destination + PNG writer (hoisted by TASK-011 section 2).
//
// `editor_capture_screenshot` (B1) and `running_game_capture_screenshot` (B2)
// are the module's two viewport readbacks; they used to have one copy each of
// these two helpers, and a group may not call another group's file-private
// helper (PLAYBOOK section 2.4). They are moved here verbatim: the refusal
// messages are the ones the editor tool already emitted, and its doctests pin
// them (TASK-011's wire evidence pins the game-side copy).
// ---------------------------------------------------------------------------

// A screenshot destination: `res://` or `user://`, no `..`, and a real file
// name. Returns false with `-32602` filled in.
bool normalize_screenshot_path(const String &p_input, String &r_out, MCPToolError &r_error);

// `AtomicWriteFunc` for an `Image`: writes the PNG. `p_userdata` is a
// `const Ref<Image> *` that outlives the call.
Error screenshot_png_writer(const String &p_temp_path, void *p_userdata);

// The same PNG, written with the engine's compression switch (TASK-046).
//
// `Image::save_png()` has no `p_fast` parameter; the switch lives one level
// down in `PNGDriverCommon::image_to_png(..., p_fast)`
// (`drivers/png/png_driver_common.cpp:128`; `:142-144` turns it into
// `PNG_IMAGE_FLAG_FAST`, which libpng reads as *no row filters plus compression
// level 3* - `thirdparty/libpng/pngwrite.c:2172-2184`). The engine reaches that
// switch from C++ through `Image::_save_png_to_buffer(p_fast)`
// (`core/io/image.h:400`, `core/io/image.cpp:2926`), which is the buffer half of
// the very `ResourceSaverPNG` pair `Image::save_png` uses
// (`drivers/png/resource_saver_png.cpp:86-87`). The in-tree precedent for
// "write a plain file through the fast buffer" is the movie writer
// (`servers/movie_writer/movie_writer_pngwav.cpp:147-150`).
//
// `p_fast == false` is deliberately the *old* call, `Image::save_png()`, byte for
// byte and error for error: the two screenshot tools call
// `screenshot_png_writer`, which is this function's `false` arm, so their
// published bytes and their refusal on a build without a PNG saver are
// untouched. Only the call capture's diagnostic pictures ask for `true`.
Error write_screenshot_png(const String &p_path, const Ref<Image> &p_image, bool p_fast);

// ---------------------------------------------------------------------------
// Screenshot pixel comparison (hoisted by TASK-044 section 2.5, GDR-25 /
// GDR-27 section 8).
//
// `editor_analyze_screenshot_diff` was the module's only pixel-by-pixel
// comparison, as a body inside `tools/editor_testing_read.cpp`. TASK-044 adds
// the **call capture** (`mcp_capture.cpp`), which has to answer the same
// question - "did this picture change?" - about the before/after pair it took
// around one tool call. Two implementations of "the same" comparison is exactly
// the drift GDR-25 forbids (the same rule TASK-011 applied to the PNG writer),
// so the loop itself moved here and both callers use it.
//
// What is *not* here, deliberately: the argument handling of the tool
// (`image_a`/`image_b` as path-or-base64, the 0..255 threshold rule, the axis
// cap and the `-32603` of a PNG that cannot be encoded). Those are one caller's
// contract, and the other caller has no arguments at all.
//
// The body is a verbatim move of the tool's loop: the same `Color::get_r8`
// bytes (the GDScript `Color.r8` spelling the threshold is defined in), the same
// `MAX(dr, MAX(dg, db)) > threshold` test, the same difference colours, the same
// `Math::snapped(.., 0.01)` rounding of the percentage. The one addition is
// `p_build_diff_image`: the capture path does not draw a difference picture
// unless it was asked to, and drawing it is the expensive half of the loop.
//
// TASK-045 added a **raw-byte fast path** to the same function: when both images
// share a size *and* one of the six 8-bit formats whose `Image::get_pixel`
// decode is a plain `byte / 255.0` (`FORMAT_L8`, `FORMAT_LA8`, `FORMAT_R8`,
// `FORMAT_RG8`, `FORMAT_RGB8`, `FORMAT_RGBA8`), the walk reads
// `Image::get_data()` - a reference, not a copy (`core/io/image.h:392`) - and
// compares the bytes directly. For those formats `Color::get_r8()`
// (`core/math/color.h:233`: `clamp(round(c * 255.0f), 0, 255)`) answers the raw
// byte itself for every one of the 256 values, which is what makes the two paths
// bit-identical; `tests/test_mcp_server.h` proves that exhaustively and diffs
// the two paths' difference pictures byte for byte. Every other format (float,
// half, 16-bit, the packed 4444/565 forms, compressed) keeps the original
// per-pixel loop, so no format's behaviour changes - including the engine's own
// "Can't get_pixel() on compressed image" refusal.
// ---------------------------------------------------------------------------

// The largest image the *diff tool* will compare, on each axis. Kept here (and
// not in the tool) because it is part of the shared comparison's declared
// working range; the capture path has no such cap of its own (its pictures are
// whatever the viewport is, and it runs after the response).
const int64_t MAX_SCREENSHOT_DIFF_DIMENSION = 4096;

struct ScreenshotDiff {
	int width = 0;
	int height = 0;
	int64_t changed_pixels = 0;
	int64_t total_pixels = 0;
	bool identical = true;
	// `changed_pixels / total_pixels * 100`, rounded to two decimals the way the
	// migration source's `stepify(diff_pct, 0.01)` was.
	double diff_percentage = 0.0;
	// The difference picture, or a null Ref when `p_build_diff_image` was false.
	Ref<Image> diff_image;
};

// Compares two images pixel by pixel.
//
// `p_label_a` / `p_label_b` name the two images in the one refusal this
// function can produce (a size mismatch - a per-pixel walk cannot be defined
// across two geometries), so the tool keeps its own `image_a`/`image_b` wording
// and the capture says `before`/`after`.
//
// A `p_threshold` outside 0..255 is **not** refused here: it is a caller-side
// rule of the tool's own contract, and the capture uses the tool's documented
// default. Returns false with `r_error` filled on a null image or a mismatch.
bool compare_screenshot_pixels(const Ref<Image> &p_a, const Ref<Image> &p_b, int p_threshold,
		bool p_build_diff_image, const String &p_label_a, const String &p_label_b,
		ScreenshotDiff &r_out, MCPToolError &r_error);

// Test-only switch, the same shape as `MCPCapture::set_warn_total_bytes_for_tests`:
// `false` forces `compare_screenshot_pixels` down its per-pixel loop even when
// the raw-byte path is available, so a doctest can run both paths over the very
// same images and diff the two answers. Production never calls it and the
// default is the raw-byte path (TASK-045).
void set_compare_screenshot_pixels_raw_path_for_tests(bool p_enabled);

// Test-only: `true` when the most recent `compare_screenshot_pixels` call took
// the raw-byte path. The equivalence doctests answer the same on both paths, so
// this is what makes "the fast path is really the one being exercised" an
// assertion instead of an assumption (TASK-045).
bool compare_screenshot_pixels_last_call_used_raw_path_for_tests();

// ---------------------------------------------------------------------------
// Editor-UI guard (hoisted by TASK-009 section 2.2).
//
// This is the runtime half of the editor guard (GDR-19 section 17.3). It used to
// exist twice, as a file-private `static` helper in
// `tools/editor_read_scene_inspector.cpp` and again in
// `tools/editor_write_scene_editor.cpp`, because a group may not call another
// group's file-private helper (PLAYBOOK section 2.4 / 17.1). The two copies were
// byte-identical logic and differed only in their two message strings, which are
// now parameters:
//
//   * `p_what`  - the non-editor wording ("... outside a running editor");
//   * `p_hint`  - the `data.suggestion` of both branches.
//
// `EditorInterface` is created by `register_editor_types()` and therefore exists
// in *every* tools process, including `--test` and a headless tools build that
// never started an editor. Its accessors, however, dereference
// `EditorNode::get_singleton()` (editor_interface.cpp:105-107) without a null
// check, so asking for the selection in such a process is a null dereference.
// The guard is therefore the singleton itself, not only `is_editor_process()`.
//
// In a game build (`MCP_EDITOR_TOOLS_ENABLED` undefined) the whole editor branch
// does not exist and every caller collapses into a clean -32000 answer.
// ---------------------------------------------------------------------------
bool require_editor_ui(MCPToolError &r_error, const String &p_what, const String &p_hint);

// ---------------------------------------------------------------------------
// The in-process editor log (new in TASK-026; GDR-25 section 23.3).
//
// `editor_get_errors` / `editor_get_output_log` used to read the *shared*
// `user://logs/godot.log` and nothing else, so an editor endpoint answered with
// lines another Godot process had written. The in-process source is the Output
// panel - the same `EditorLog` the sibling `editor_remove_output_log` operates
// on - and this is the one definition of "what the panel is showing, as lines".
//
// What it answers, exactly: the rendered text of the dock's `RichTextLabel`
// (the `ERROR: ` / `WARNING: ` prefixes are part of it, a message-type filter
// the user switched off or a populated search box is *not*, and neither is a
// message that arrived before the dock entered the tree). It is this process's
// own content, live at the moment of the call.
//
// Returns false when there is no editor log to read at all - a game process, a
// `--test` process, or an editor whose dock has not been built - which is the
// caller's signal to fall back to the file. `EditorLog` keeps its message list
// and its label private (`editor/editor_log.h:129/133`), so the panel text is
// the only readable form; the reasoning for reaching it through the scene tree
// is in tool_helpers.cpp.
// ---------------------------------------------------------------------------
bool editor_log_lines(Vector<String> &r_lines);

// ---------------------------------------------------------------------------
// Editor node-path resolution (hoisted by TASK-016 section 1).
//
// Two file-private helpers had grown one copy per editor group file: the edited
// scene root existed **three** times (tools/editor_node_write.cpp:79,
// tools/editor_read_scene_inspector.cpp:89, tools/editor_write_scene_editor.cpp:87)
// and the migration source's node resolution **twice**
// (tools/editor_node_write.cpp:102, tools/editor_write_scene_editor.cpp:99 - the
// second copy was TASK-015's deliberate duplicate, made because a group may not
// call another group's file-private helper, PLAYBOOK section 2.4). They live
// here now as verbatim moves: the only edits are the removed `static`, the
// removed leading `_` and the call sites' spelling. Behaviour is pinned by the
// before/after wire comparison in REPORT-016 section 1 (same request sequence,
// byte-identical responses).
//
// `_relative_path` was deliberately **not** hoisted by TASK-016 section 1 because
// it then had exactly one definition (tools/editor_node_write.cpp:126), so there
// was no duplicate to remove. TASK-017's three groups each wrote their own copy
// (editor_control_layout_write.cpp, editor_node_batch_write.cpp,
// editor_node_setup.cpp), turning that one definition into four byte-identical
// ones. The TASK-017 repair pass hoists it here as `relative_path` and removes
// all four file-private copies, so the *next* group has one definition to call
// and no copy to make. The name is the hoisted form of the old spelling; the
// body is the verbatim body of `tools/editor_node_write.cpp`.
// ---------------------------------------------------------------------------

// The scene the editor is editing, or nullptr when there is none.
//
// `SceneTree::get_edited_scene_root()` is the mirror the editor keeps in sync
// (`EditorNode::set_edited_scene_root`, `EditorNode::_set_current_scene_nocheck`),
// while `EditorInterface::get_edited_scene_root()` is the unchecked
// `EditorNode::get_singleton()` dereference of editor_interface.cpp:105-107 and
// was measured to SIGSEGV in the doctest process (REPORT-004 section 9). It is
// also the same choice `project_read_analysis.cpp` already made, and it is
// available in a game build as well (it is plain `SceneTree`), which is why it
// needs no `MCP_EDITOR_TOOLS_ENABLED` guard of its own.
Node *edited_scene_root();

// The migration source's own spelling for a node it returns: the path relative
// to the edited scene root, with the root itself as ".". It is the answer every
// `node_path` / `source` / `target` field of an editor write group carries, so a
// caller can feed the answer straight back into another tool.
String relative_path(Node *p_root, Node *p_node);

// ---------------------------------------------------------------------------
// ClassDB instantiation + property existence (hoisted by TASK-017 section 4).
//
// TASK-015 wrote the module's one "instantiate a class by name" rule inside
// `MCPTools::instantiate_node_of_type` (tools/editor_node_write.cpp). TASK-017's
// three new groups need the same rule for classes that are *not* nodes (a
// `Shape2D`, an `Environment`, a `NavigationMesh`) and for nodes whose name must
// stay unset (`Node::set_name("")` is an `ERR_FAIL_COND`), so the class-level
// half lives here and `instantiate_node_of_type` is now the one-line node
// wrapper over it. Two group files (`editor_node_batch_write.cpp` and
// `editor_node_setup.cpp`) also need a *read-only* property-existence test
// before any write - the batch grammar requires "all matched nodes declare the
// property" to be decided first - so `object_has_property` is hoisted as well
// and `running_game_node_write.cpp`'s former file-private copy is gone.
// ---------------------------------------------------------------------------

// Instantiates `p_type` through `ClassDB`, or fills `r_error` with `-32602`
// (unknown class / abstract or otherwise not instantiable) and returns nullptr.
// `Node` subclass-ness is deliberately *not* checked here: a resource class is
// a legal answer for this helper.
Object *instantiate_class(const String &p_type, MCPToolError &r_error);

// True when the object declares `p_name` in its property list, or already
// answers a non-nil value for it. This is the pre-write question of TASK-014
// D-1 and the all-or-nothing pre-check of TASK-017 D2, in one definition.
bool object_has_property(const Object *p_object, const StringName &p_name);

// ---------------------------------------------------------------------------
// TASK-040 D-1: writing a *resource the caller just built* into a property.
//
// `editor_add_resource_to_node_property` is not a property write of a caller's
// JSON value (that is `write_node_property`): it instantiates a `Resource` by
// class name, applies `resource_properties` to it and then stores the fresh
// object in a node property. Until TASK-040 that last step was a bare
// `Object::set()` followed by an unconditional success answer, so a property the
// node does not have at all - and a property that exists but whose declared
// class cannot hold this resource - were both reported as written while nothing
// had happened (RACING-FINDINGS section 4 D-1: `CharacterBody2D
// .physics_material_override` answers `ok` and the read side still answers
// `-32001`).
//
// This is the one definition of that step, and it is exported for the same
// reason the node-write helpers are: the doctest process has no `SceneTree`, so
// the tool itself can only ever answer its `-32000` guard there. The refusals:
//
//   * the object does not declare the property at all -> `-32001` naming it,
//     with `data.suggestion` (the TASK-014 D-1 shape, the same one
//     `editor_set_node_property` answers with);
//   * the property exists but is not an Object-valued one (`Variant::OBJECT`),
//     or its declared class specification refuses this resource -> `-32602`,
//     the message naming the declared classes (`_object_fits_declared_class` is
//     the module's one reading of the engine's own class-list grammar);
//   * the engine's setter stored something else -> `-32000` tool_state, never a
//     success shape (PLAYBOOK section 20.6).
// ---------------------------------------------------------------------------
bool assign_resource_to_property(Object *p_object, const StringName &p_property, const Ref<Resource> &p_resource, MCPToolError &r_error);

// The migration source's `find_node`
// (`godot_mcp_gdext/src/commands/node.rs:148-165`):
//
//   1. "." or the bare root name             -> the root;
//   2. `p_root->has_node(path)`              -> that node;
//   3. a path prefixed with the root's name  -> retried without the prefix;
//   4. anything else                         -> nullptr.
//
// The checks run in exactly that order. Unlike `Node::get_node`, a miss is
// `nullptr` instead of an engine error. It is deliberately *not* the same rule
// as the game-side `resolve_game_node` above: the migration source has two
// different resolutions and unifying them would change the behaviour of already
// accepted tools (DESIGN-OVERVIEW section 5).
Node *find_node(Node *p_root, const String &p_path);

// TASK-063 (b): the `data.suggestion` every node-path refusal of the editor node
// family now carries, built in one place so `editor_set_node_property`,
// `editor_get_node_properties`, `editor_set_node_script_batch` and
// `editor_set_node_property_updates` cannot disagree about what a path is.
//
// The defect it answers (TASK-060 D-5 / O-2 / O-3, measured): the three tools
// require the same kind of path - relative to the edited scene root, `/root/...`
// refused - but spell it two ways and none of their descriptions stated the
// basis, so a caller spent 20 single writes and 39 batch calls discovering it.
// The old suggestion said only "Use editor_get_scene_tree to list the nodes of
// the edited scene", which says nothing about the accepted spelling.
//
// `p_parameter` is the name the *refusing* tool uses (`path` or `node_paths`),
// and `p_plural` picks the singular/plural half. The text says the same thing as
// the sentence the contract now carries (`NODE_PATH_RULE_SENTENCE` in
// `scripts/gen_renamed_contract.py`): the description a caller reads and the
// refusal it gets when it gets it wrong must not disagree.
String node_path_guidance(const String &p_parameter, bool p_plural);

// TASK-063 (b): the sentence `docs/tools_list.renamed.json` appends to both
// single-path descriptions (`editor_set_node_property` -> old name
// `update_property`, and `editor_get_node_properties` -> `get_node_properties`).
//
// It is one literal because the two registrars must produce the contract entry
// character for character, and two hand-typed copies of a 619 character sentence
// is exactly how a verbatim gate goes red on a typo. The generator has its own
// copy (`NODE_PATH_RULE_SENTENCE`), and the two are checked against each other by
// gate 1 (the live `tools/list` versus the contract) rather than by a third
// mechanism.
extern const char *const NODE_PATH_RULE_SENTENCE;

// ---------------------------------------------------------------------------
// Argument-shape helpers (hoisted by the TASK-017 repair pass).
//
// `_optional_dictionary` existed twice, byte for byte
// (tools/editor_node_write.cpp:91 and tools/editor_node_setup.cpp:163), and the
// optional *number* reader existed in five byte-identical spellings across the
// module (`_optional_float` of editor_node_setup.cpp, `_optional_number` of
// editor_input_simulation.cpp, editor_write_scene_editor.cpp with an extra
// presence flag and running_game_read_scene.cpp, and the value half of
// `_optional_positive_seconds` of running_game_frame_observation.cpp). The first
// four are semantically the same five lines - absent means the default, `INT`
// and `FLOAT` are both a number, anything else is `-32602` with one message - so
// they are now one definition. `_optional_positive_seconds` keeps its own
// refusals (a different wrong-type wording and a positivity/finiteness rule that
// TASK-010's doctests pin) and calls the shared reader for the value itself.
//
// This is the same rule TASK-005/TASK-016 applied to their helpers: the *next*
// group calls the one definition instead of making the fifth copy. Behaviour is
// pinned by the before/after wire comparison in REPORT-017 section 14.
// ---------------------------------------------------------------------------

// An optional object argument. Absent -> the empty Dictionary; present but not a
// DICTIONARY -> `-32602` naming the argument and the type that arrived.
bool optional_dictionary(const Dictionary &p_args, const String &p_key, Dictionary &r_out, MCPToolError &r_error);

// An optional number argument. Absent -> `p_default`; `FLOAT` and `INT` are
// accepted (Godot's JSON parser has one number type, so an integral JSON number
// may arrive as either); anything else -> `-32602` naming the argument and the
// type that arrived.
bool optional_float(const Dictionary &p_args, const String &p_key, double p_default, double &r_out, MCPToolError &r_error);

// ---------------------------------------------------------------------------
// Running-game scene helpers (hoisted by TASK-011 section 2).
//
// These three used to be file-private in `tools/running_game_observation.cpp`.
// TASK-011 adds a second game-scope group that resolves `node_path` the same
// way, and a group may not call another group's file-private helper (PLAYBOOK
// section 2.4): either the semantics are duplicated - and then the two groups
// can disagree about what `Player` means - or the one definition is shared. It
// is shared here, as a verbatim move (only `static` and the leading `_` were
// removed); the observation group's doctests and its wire evidence still pass
// unchanged, which is what pins the move as behaviour preserving.
// ---------------------------------------------------------------------------

// The running game's current scene, or the GDR-14 state error. A process without
// a `SceneTree` (the doctest binary, a `--check-only` run) and a running game
// whose `current_scene` has been cleared both land in the same refusal, which is
// the module's mapping of the reference's `{"error": "No current scene"}`.
bool game_current_scene(Node *&r_root, SceneTree *&r_tree, MCPToolError &r_error);

// The SceneTree's root window as a `Node *`, or `nullptr` when there is no tree.
// A game-side tool that only addresses the tree root (an autoload at
// `/root/<name>`) needs this and deliberately *not* a current scene.
Node *game_tree_root(SceneTree *p_tree);

// The migration source's node resolution, kept because it is the observable
// contract of every game-side tool that takes a `node_path`:
//
//   1. "" or "."                        -> the current scene root;
//   2. a path that starts with `/root/` -> an absolute path from the tree root
//      (this is how an autoload is addressed);
//   3. anything else                    -> a path relative to the current scene
//      root;
//   4. if that fails                    -> a whole-subtree search for a node
//      *named* exactly like the argument, so `Player` finds
//      `/root/Main/World/Player`.
Node *resolve_game_node(SceneTree *p_tree, Node *p_root, const String &p_node_path);

// ---------------------------------------------------------------------------
// Framebuffer helpers (TASK-011 section 2).
//
// `running_game_capture_frames` and `running_game_capture_screenshot` are one
// capability (read the running game's viewport back) split into two groups by
// GDR-18, so the two file-scope helpers they share live here rather than being
// written twice.
//
// The `--headless` display server is a real, engine-imposed limitation and not a
// detail: `RendererDummy::TextureStorage::texture_2d_get()` logs an engine ERROR
// and returns null, so asking for the image in a headless process spams the log
// with failures that are not the caller's fault. The availability test therefore
// asks the display server first, and both capture tools refuse with a readable
// -32000 instead of returning an empty picture.
// ---------------------------------------------------------------------------

// True when the current process has a display server that can hand out a
// framebuffer.
bool game_framebuffer_available();

// The running game's root viewport as an `Image`, optionally halved, or a null
// Ref when no framebuffer is available (see above).
Ref<Image> game_viewport_image(bool p_half_resolution);

// ---------------------------------------------------------------------------
// Property-value helpers (hoisted by TASK-009 section 2.2).
//
// These three used to exist twice, once in
// `tools/project_write_resource_scene.cpp` and once, as a subset, in
// `tools/editor_write_scene_editor.cpp`; the editor copy of
// `property_value_from_json` was the superset (it accepted an incoming JSON
// `INT`), and that superset is what lives here now.
// ---------------------------------------------------------------------------

// The JSON value of a property as a Godot value.
//
// The migration source reads the *typed* property before it assigns, and parses
// the incoming string with the property's own type (`serialize.rs:268`). Godot's
// JSON parser has one number type, so a plain `int` property would otherwise be
// written as a float. `p_target_type` is that property's type. A JSON *object*
// becomes a Dictionary ("retain the structure", serialize.rs:288; the recursion
// passes `Variant::NIL` down so nested values keep their JSON shape).
//
// **Where a component is really judged (TASK-020 section 1).** The `NIL` in that
// recursion is deliberate and stays: nothing is *folded* here, so there is no
// component type to judge a member against - an object for a `DICTIONARY`
// property legitimately holds strings, and `DICTIONARY -> VECTOR2` is not even a
// pair `Variant::can_convert` lists. The composite targets that *do* have
// components (`Vector2`/`Vector3`/`Vector2i`/`Vector3i`/`Color`) are folded one
// step later by the module's component mapping, and that step
// (`MCPTools::shape_vector_from_json` / `vector_from_dictionary`,
// `running_game_node_write.*`) is where each member now goes through
// `coerce_to_property_type` with the type of the slot it fills.
//
// **A JSON string stays a String.** The migration source's string grammar
// (`"#rrggbb"` -> Color, `"Vector2(1,2)"` -> Vector) was dropped by TASK-019
// P-1: it went through `Variant::construct_from_string`, which is a stub in this
// fork, so the branch was dead code that made the syntax look available. The
// `"#rrggbb"` case is not lost - `coerce_to_property_type` converts it through
// the engine's own `Variant::can_convert(STRING, COLOR)` - but
// `"Vector2(1,2)"` is now refused with `-32602` and the structured object
// (`{"x": 1, "y": 2}`) is the way to send a vector.
// `Variant::operator String()` is **not** that: it answers `stringify()`
// (variant.cpp:1590), so an `INT` 10 turns into `"10"` only by luck of
// `stringify`'s own spelling, while a `FLOAT` 10.0 turns into `"10"` too - which
// is the one thing this comparison relies on. The explicit conversion below makes
// that a decision instead of an accident: integers and floats print without a
// trailing `.0`, strings print verbatim (no quotes), booleans as `true`/`false`,
// and everything else through the module's single `serialize_variant` + JSON,
// which is the same spelling a caller sees in a successful answer.
String assertion_text_of(const Variant &p_value);

// The expectation put into the shape the actual value has, or the expectation
// unchanged when it needs no mapping. `evaluate_assertion` calls it before
// comparing, and an assertion tool calls it so that its answer echoes the
// expectation as it was really compared.
//
// The one mapping that matters here is the module's component mapping
// (`MCPTools::vector_from_dictionary`, owned by `running_game_node_write`):
// `{"x":3,"y":4}` against a `Vector2` property. Without it the two sides can
// never be equal - measured on the wire, `assert_node_state` on `position`
// answered `passed: false` with `expected` and `actual` both printing
// `{"x":3.0,"y":4.0}` - and the same mapping is what makes
// `running_game_set_node_property` accept that object. A Dictionary that does
// not name the components is returned unchanged, so the comparison fails rather
// than quietly succeeding.
Variant assertion_expectation_for(const Variant &p_actual, const Variant &p_expected);

// True when `p_operator` is one of the eight names.
bool is_valid_assert_operator(const String &p_operator);

// Evaluates one comparison. `p_error` is filled (`-32602`) and false returned for
// an unknown operator or a non-finite operand of an ordering comparison.
//
// `p_actual` is the value a property really holds, and its **type is the shape
// the expectation has to have**: when the actual value is vector-shaped
// (`Vector2`/`Vector2i`/`Vector3`/`Vector3i`/`Color`) and the expectation arrived
// as the JSON object a caller naturally writes (`{"x":3,"y":4}`), the
// expectation goes through the module's one component mapping
// (`MCPTools::vector_from_dictionary`) before it is compared. Without that step
// the two sides can never be equal - measured on the wire, `assert_node_state`
// on `position` answered `passed: false` with `expected` and `actual` both
// printing `{"x":3.0,"y":4.0}`, because a Dictionary and a `Vector2` are
// different values - and the same normalization is what makes `running_game_set_
// node_property` accept that object in the first place. A Dictionary that does
// not name the components is left as it is: the comparison then simply fails,
// which is the honest answer for a shape nothing can interpret.
bool evaluate_assertion(const String &p_operator, const Variant &p_actual, const Variant &p_expected,
		bool &r_passed, MCPToolError &r_error);

// ---------------------------------------------------------------------------
// TASK-020 D-3: the one assertion verdict both entries build.
//
// The standalone assertion tools and the `assert` steps of
// `running_game_run_test_scenario` used to answer two different shapes for the
// same failing assertion: the tools carried `actual`/`expected` (and
// `visible_elements[]`) without a `reason`, the scenario step carried the
// `reason` too. The builders below are the whole assertion field set - status,
// the compared values, the search space and, on a failure, the reason text - and
// both entries merge exactly this object into their own record (the runner adds
// only its own `type`/`step` envelope). One field definition, so the two cannot
// drift apart.
//
// `node_state_assertion_fields` echoes the expectation as it was really compared
// (`assertion_expectation_for`), which is what keeps `expected` and `actual` from
// printing the same value next to `passed: false`.
// ---------------------------------------------------------------------------

// "expected <property> <operator> <expected>, found <actual>", the failure text
// of a node-state assertion (one definition; the scenario runner used to spell
// it out itself).
String node_assertion_failure_reason(const String &p_property, const String &p_operator,
		const Variant &p_expected, const Variant &p_actual);

// "screen text <containing|equal to> '<text>' was not found in the <n> visible
// text(s) of the control tree", the failure text of a screen-text assertion.
String screen_text_failure_reason(const String &p_text, bool p_partial, int p_visible_text_count);

// The verdict of one node-state assertion. `p_passed` comes from
// `evaluate_assertion`; on a failure the verdict carries `reason`.
Dictionary node_state_assertion_fields(const String &p_node_path, const String &p_resolved_node_path,
		const String &p_property, const String &p_operator, const Variant &p_expected_raw,
		const Variant &p_actual, bool p_passed);

// The verdict of one screen-text assertion. `p_visible_elements` is the control
// tree the search ran over; on a miss the verdict carries `reason`.
Dictionary screen_text_assertion_fields(const String &p_text, bool p_partial, bool p_case_sensitive,
		const Array &p_visible_texts, const Array &p_visible_elements, bool p_found);

// ---------------------------------------------------------------------------
// Test-result accumulator (TASK-019, `editor_get_test_report`).
//
// The migration source's `get_test_report` was a `fix_implementation_first`
// entry for a measured reason: it answered a **hard-coded message string** built
// with a GDScript `Expression` and never collected anything (`test.rs:561-589`,
// "使用 assert_node_state 等测试命令会自动收集结果"), so a caller that ran an
// assertion and asked for the report learned nothing about it. The newer
// migration source already has the right shape (`test_commands.gd:20`,
// `_test_results`), and this is that accumulator, in one place:
//
//   * the B4 assertion/observation tools record one entry per assertion
//     (`running_game_assert_node_state`, `running_game_assert_screen_text`, the
//     assert steps of `running_game_run_test_scenario`);
//   * `editor_get_test_report` reads it and, when `clear` is true, empties it.
//
// Both halves used to run in different processes with no way across: a game-scope
// assertion called over the game endpoint records in the game process, and the
// editor tool that reads the accumulator lives in the editor process, so the
// editor's list is one nothing can write to. TASK-022 D-6 closes that with the
// **file bridge** documented below: the game persists its list to `user://` and
// the editor-side tool reads it. The in-memory list stays per process (it is
// still the only thing `build_test_report()` can see), and the tool says which
// of the two it answered from.
//
// The storage is deliberately a plain `Array` of `Dictionary` with the engine's
// own JSON-friendly values, and the accessor below is the only way to reach it.
// The accumulator starts empty for every process **and every doctest case that
// clears it**, which is what makes the red test of TASK-019 section 1.1 possible
// (an empty accumulator must be reported as `no_results`, not masked by a
// fabricated message).
// ---------------------------------------------------------------------------

// Appends one already-serialized assertion record. The caller decides the shape
// (it is the tool's observable answer); this never rewrites it.
void record_test_result(const Dictionary &p_result);

// The recorded records, in insertion order, and how many there are.
Array get_test_results();

// Empties the accumulator.
void clear_test_results();

// The report of `editor_get_test_report`, built from the accumulator:
//   `{"total", "passed", "failed", "pass_rate", "all_passed", "no_results",
//     "details"}`.
// An entry without a boolean `passed` is not an assertion and is skipped (an
// input/wait step has no verdict) - the same rule as `test_commands.gd:351`.
// `source` is added by the tool, not here, so the shape stays testable.
Dictionary build_test_report();

// The same aggregation over an arbitrary list of records. `build_test_report()`
// is exactly `build_test_report_from(get_test_results())`, and the file bridge
// below feeds a persisted list through this one function so an in-memory report
// and a cross-process report cannot disagree about what `total` means.
Dictionary build_test_report_from(const Array &p_records);

// ---------------------------------------------------------------------------
// TASK-022 D-6: the cross-process test-report bridge (file IPC).
//
// **The defect.** `editor_get_test_report` is editor-scope, and *every* caller of
// `record_test_result` (`running_game_assertion.cpp:160`/`:242`,
// `running_game_test_execution.cpp:466`) lives in a game-scope tool, which is not
// registered on the editor endpoint at all (a cross-endpoint call is a `-32601`
// and never runs). The editor's accumulator is therefore a table nothing can
// write to: the M4b re-audit measured `total: 0` for every possible sequence of
// calls, i.e. the contract's "get the test report" capability was unreachable
// from a client no matter what it did.
//
// **The decision (the task book's, section 4): the file bridge, no contract
// change.** The migration source did the same thing - it handed the report
// between its processes over a `user://` file - so this is not a new mechanism
// invented for the occasion. The game process persists its accumulator; the
// editor-side tool reads the file:
//
//   * every `record_test_result` rewrites the whole accumulator to
//     `test_report_bridge_path()` **atomically** (`publish_file_atomically`: a
//     sibling temporary file is published with a rename, so a reader never sees
//     half a report);
//   * `editor_get_test_report` answers from that file when it is there, and says
//     so (`source: "game_process_file"`, plus the path and the write time);
//   * when the file is absent or holds no records the answer is the *honest*
//     empty report (`total: 0`, `no_results: true`) with
//     `report_file_present: false` - a `total` is never invented;
//   * `clear` (the tool's flag, default true) empties the **editor process'**
//     accumulator *and* removes the bridge file, so "the next call starts from
//     nothing" holds across processes; the answer's `cleared` list says which of
//     the two was really touched. The game process' memory cannot be reached from
//     the editor and is not claimed to be: the game re-persists its own full list
//     on its next recorded assertion.
//
// The accumulator semantics are therefore: **one in-memory list per process, and
// one `user://` file carrying the game process' list to the editor process.** It
// is not a memory read of the other process and cannot be.
// ---------------------------------------------------------------------------

// `user://mcp_test_report.json`: the bridge file. One definition, so the game's
// writer and the editor's reader cannot disagree about the path.
String test_report_bridge_path();

// Persists the current accumulator to `p_path` as JSON, atomically. Returns false
// and fills `r_reason` when the file could not be written (a read-only user data
// directory, a `user://` that does not resolve in this process); the in-memory
// accumulator is unaffected either way, so a failed persist can never fail the
// assertion tool that recorded the result.
bool persist_test_report_to(const String &p_path, String &r_reason);

// Reads a persisted report. `r_found` is false when the file does not exist or
// could not be read (`r_reason` says which); when it is true, `r_records` holds
// the persisted list and `r_meta` the envelope the writer stored
// (`written_at_unix`, `source_process`, `version`). The records are handed back
// as the engine's own values (the file is JSON), so the caller aggregates them
// with `build_test_report_from`.
bool load_persisted_test_report_from(const String &p_path, Array &r_records,
		Dictionary &r_meta, bool &r_found, String &r_reason);

// ---------------------------------------------------------------------------
// Schema integer-`default` normalisation (hoisted by TASK-034).
//
// A schema parsed from the contract JSON cannot carry an integer `default`: the
// engine's JSON parser stores every number as a `double` (`json.cpp:393-396`) and
// stringifies a float zero as `0.0`, while the contract spells `0` - and gate 1
// compares the live `inputSchema` field by field. This returns a copy of
// `p_schema` in which the named `properties` members carry an INT `default`
// again; every other character is untouched, and a name the schema does not
// declare is skipped rather than invented.
//
// TASK-033 wrote this as a file-private static of
// `editor_animation_tree_write.cpp`; TASK-034 needs it in a second group file
// (`editor_audio_write.cpp`, `after_bus_index`) and a group may not call another
// group's file-private helper (PLAYBOOK section 2.4), so there is one definition
// here and both call it.
// ---------------------------------------------------------------------------
Dictionary schema_with_integer_defaults(const Dictionary &p_schema, const Vector<StringName> &p_names);

} // namespace MCPTools

// ---------------------------------------------------------------------------
// GDScript source builder (hoisted by TASK-018 section 3).
//
// TASK-010 wrote the module's one "compile the caller's code for real" rule as
// file-private helpers of `tools/running_game_script_execution.cpp`
// (`_split_code_lines` / `_space_indent_unit` / `_build_source`). TASK-018's
// `editor_execute_gdscript` is the same capability in the editor process, and a
// group may not copy another group's file-private helper (PLAYBOOK section 2.4):
// if the two executors did not share this, "what counts as a function body today"
// would have two answers. They share it here.
//
// The body is a verbatim move: same three rules (the smallest positive space
// indent becomes one tab, a `func` at column 0 is lifted to class level with the
// blank/tab-indented lines that belong to it, everything else is indented into
// `_mcp_execute`), same `extends RefCounted` prelude, same deliberate
// untyped `func _mcp_execute():`. `running_game_execute_gdscript`'s doctest and
// its wire evidence pin the move as behaviour preserving.
// ---------------------------------------------------------------------------

// The method the generated script exposes. Both executors answer
// `{"result","result_type"}` and both find the entry point by this name.
const char *execute_gdscript_method_name();

// Builds `@tool` (editor only) + `extends RefCounted` + optional lifted
// functions + `func _mcp_execute()`.
//
// `p_tool_script` is the one thing the two executors may *not* share. Godot
// refuses to instantiate a non-`@tool` script **while the editor is running**:
//
//     bool GDScript::can_instantiate() const {
//         return valid && (is_tool() || !Engine::get_singleton()->is_editor_hint());
//     }
//
// so the editor executor compiles its source with `@tool` and the game executor
// without it (where the annotation is unnecessary and the generated source
// stays byte-identical to the one TASK-010's evidence pinned). Measured on the
// wire before the fix: every `editor_execute_gdscript` call answered `-32602
// "does not compile: OK"` - `reload()` succeeded, so the message was nonsense,
// and the real reason was this predicate.
bool build_execute_gdscript_source(const String &p_code, bool p_tool_script, String &r_source);

// ---------------------------------------------------------------------------
// Screen-text observation (TASK-019, `running_game_assert_screen_text`).
//