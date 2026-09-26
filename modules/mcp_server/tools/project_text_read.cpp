/**************************************************************************/
/*  project_text_read.cpp                                                 */
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
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/
#include "project_text_read.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"

using namespace MCPTools;

namespace {

// The contract's own numbers (`ADDED_TOOLS` in scripts/gen_renamed_contract.py):
// 1 MiB by default, 16 MiB as the ceiling. They live here as literals because the
// *enforcement* is a separate fact from the schema: a schema is published, a
// refusal is measured, and a caller that never reads `inputSchema` still gets the
// same two bounds.
const int64_t DEFAULT_MAX_BYTES = 1048576; // 1 MiB
const int64_t MAX_MAX_BYTES = 16777216; // 16 MiB

Dictionary _suggestion(const String &p_text) {
	Dictionary data;
	data["suggestion"] = p_text;
	return data;
}

// The project root, spelled the one way `normalize_project_path` produces it.
const char *const PROJECT_ROOT = "res://";

// The honesty sentence every answer carries. The tool answers *bytes*; it is not
// a reader of any format, and a caller must not read `text` as "this is valid
// JSON / a valid scene / a valid config". TASK-075 section 2 requires that
// declaration to be explicit rather than implied.
const char *const NO_INTERPRETATION_NOTE =
		"The bytes are answered as they are: this tool does not parse, validate or interpret the file's format "
		"(a JSON, config, project or scene file is returned as text, exactly like any other file).";

// The refusal shape for "the path names a directory". `-32602` and not `-32001`:
// the thing the caller named *exists* - it is simply not a file, and that is a
// property of the argument, not of the project's state (GDR-14).
MCPToolError _is_a_directory(const String &p_path) {
	MCPToolError error = MCPToolError::invalid_params(
			vformat("Parameter 'path' names the directory '%s', not a file", p_path));
	error.data = _suggestion("Append the file name, e.g. 'res://save/slot1.json'; project_get_filesystem_tree lists the files of the project");
	return error;
}

} // namespace

namespace MCPTools {

bool utf8_bytes_are_valid(const uint8_t *p_bytes, int64_t p_size) {
	int64_t i = 0;
	while (i < p_size) {
		const uint8_t lead = p_bytes[i];
		int extra = 0;
		uint32_t code_point = 0;
		if (lead < 0x80) {
			i++;
			continue;
		} else if ((lead & 0xE0) == 0xC0) {
			extra = 1;
			code_point = lead & 0x1F;
		} else if ((lead & 0xF0) == 0xE0) {
			extra = 2;
			code_point = lead & 0x0F;
		} else if ((lead & 0xF8) == 0xF0) {
			extra = 3;
			code_point = lead & 0x07;
		} else {
			// A continuation byte where a lead byte belongs, or one of the five
			// byte/0xFE/0xFF forms UTF-8 does not have.
			return false;
		}
		if (i + extra >= p_size) {
			return false; // truncated sequence
		}
		for (int k = 1; k <= extra; k++) {
			const uint8_t continuation = p_bytes[i + k];
			if ((continuation & 0xC0) != 0x80) {
				return false;
			}
			code_point = (code_point << 6) | (uint32_t)(continuation & 0x3F);
		}
		// Overlong forms, UTF-16 surrogates and the code points above U+10FFFF
		// are all encodable byte sequences and all invalid UTF-8 text.
		if (extra == 1 && code_point < 0x80) {
			return false;
		}
		if (extra == 2 && code_point < 0x800) {
			return false;
		}
		if (extra == 3 && code_point < 0x10000) {
			return false;
		}
		if (code_point > 0x10FFFF) {
			return false;
		}
		if (code_point >= 0xD800 && code_point <= 0xDFFF) {
			return false;
		}
		i += extra + 1;
	}
	return true;
}

String text_omission_reason(int64_t p_size, int64_t p_max_bytes) {
	return vformat("The file is %d byte(s), larger than 'max_bytes' (%d): its text was not put into this answer. The "
				   "'size' and 'sha256' fields describe the WHOLE file, so it can still be verified without reading "
				   "it; pass a larger 'max_bytes' (up to %d) to read the text",
			p_size, p_max_bytes, MAX_MAX_BYTES);
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// // project_read_text_file (TASK-075 section 2)
//
// The symmetric half of `project_write_text_file`. The answer is built from the
// bytes on disk and nothing else:
//
//   * `path`   - the normalised project path that was read (PLAYBOOK 6.7);
//   * `size`   - the UTF-8 byte count of the whole file (PLAYBOOK 6.9: this
//                module answers byte counts, never `String::length()`);
//   * `sha256` - `FileAccess::get_sha256()`, i.e. the engine's own hash of the
//                file, the same call `project_write_text_file` puts in its
//                receipt, so the write receipt and the read answer are directly
//                comparable - and both are comparable with an OS hash;
//   * `text`   - the bytes decoded as UTF-8, or `text_omitted: true` plus a
//                `reason` when the file is larger than `max_bytes`.
//
// The four refusals are the whole error surface, and they are deliberately
// different from each other:
//
//   1. a path that does not address the project (`user://x`, `C:/x`) or that
//      walks upwards (`..`) -> the module's canonical `-32602`, with the
//      suggestion this tool adds (`normalize_project_path` answers the message);
//   2. a path that names a directory -> `-32602` (`_is_a_directory`);
//   3. a file that is not there -> `-32001` + `data.suggestion`;
//   4. a file whose bytes are not valid UTF-8 -> `-32000` + `data.suggestion`,
//      because the file *is* there and *is* readable - it simply has no text.
//      Answering `text` for those bytes would publish a string that is not the
//      file's content, which is the one thing this tool must not do.
// ---------------------------------------------------------------------------

static Variant _tool_read_text_file(const Dictionary &p_args, MCPToolError &r_error) {
	String raw_path;
	if (!require_string(p_args, "path", raw_path, r_error)) {
		return Variant();
	}
	if (raw_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'path' must not be empty");
		return Variant();
	}
	int64_t max_bytes = DEFAULT_MAX_BYTES;
	if (!optional_int(p_args, "max_bytes", DEFAULT_MAX_BYTES, max_bytes, r_error)) {
		return Variant();
	}
	if (max_bytes <= 0) {
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'max_bytes' must be a positive integer, got %d", max_bytes));
		r_error.data = _suggestion("Pass a byte budget of at least 1, or omit 'max_bytes' for the 1 MiB default");
		return Variant();
	}
	if (max_bytes > MAX_MAX_BYTES) {
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'max_bytes' must not exceed %d (16 MiB), got %d", MAX_MAX_BYTES, max_bytes));
		r_error.data = _suggestion(
				"The tool's ceiling exists so one answer cannot carry an unbounded file; read the file in the project "
				"with a smaller 'max_bytes', or use an OS-level reader for a file this large");
		return Variant();
	}

	String path;
	if (!normalize_project_path(raw_path, path, r_error)) {
		// `normalize_project_path` answers the module's canonical `-32602`; the
		// suggestion is added here because only this tool knows why it is asking.
		r_error.data = _suggestion(
				"'path' must address the project ('res://...') and must not contain a '..' segment: this tool reads only "
				"inside the project directory");
		return Variant();
	}
	// The *raw* spelling decides "names a file": after normalisation `res://dir/`
	// and `res://dir` are the same string, and only one of them names a file (the
	// same rule `project_text_write.cpp:_prepare_target` applies on the write side).
	const String raw = raw_path.replace("\\", "/").strip_edges();
	if (raw.ends_with("/") || path == String(PROJECT_ROOT) || path.get_file().is_empty()) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'path' must name a file, got '%s'", raw_path));
		r_error.data = _suggestion("Pass the file name too, e.g. 'res://save/slot1.json'");
		return Variant();
	}
	if (DirAccess::dir_exists_absolute(path)) {
		r_error = _is_a_directory(path);
		return Variant();
	}
	if (!FileAccess::exists(path)) {
		r_error = MCPToolError::not_found(vformat("File '%s'", path),
				"Use project_get_filesystem_tree to list the files of the project, or project_write_text_file to create this one");
		return Variant();
	}

	Error read_error = OK;
	const Vector<uint8_t> bytes = FileAccess::get_file_as_bytes(path, &read_error);
	if (read_error != OK) {
		r_error = MCPToolError::tool_state(
				vformat("File '%s' exists but could not be read (engine error %d)", path, (int64_t)read_error),
				"Check that the file is not locked by another process and that it is inside the project's own directory");
		return Variant();
	}

	Dictionary out;
	out["path"] = path;
	out["size"] = (int64_t)bytes.size();
	// The engine's own hash of the file on disk right now, byte for byte the call
	// `project_write_text_file` publishes.
	out["sha256"] = FileAccess::get_sha256(path);
	out["parsed"] = false;
	out["note"] = String::utf8(NO_INTERPRETATION_NOTE);

	if ((int64_t)bytes.size() > max_bytes) {
		// The omission is a *declared* answer, never a silent truncation: `size`
		// and `sha256` still describe the whole file, and `reason` says what
		// happened and what to do.
		out["text_omitted"] = true;
		out["reason"] = text_omission_reason((int64_t)bytes.size(), max_bytes);
		out["max_bytes"] = max_bytes;
		return out;
	}

	if (!utf8_bytes_are_valid(bytes.ptr(), (int64_t)bytes.size())) {
		r_error = MCPToolError::tool_state(
				vformat("File '%s' is %d byte(s) long but its bytes are not valid UTF-8 text", path, (int64_t)bytes.size()),
				"This tool answers text and refuses to publish a decoded string that is not the file's content. Read it as "
				"a resource with project_read_resource if it is a .tres/.res, or read it outside the tool surface (the "
				"sha256 of the bytes is still obtainable by asking for this path with 'max_bytes' below the file size)");
		return Variant();
	}
	out["text"] = String::utf8((const char *)bytes.ptr(), bytes.size());
	out["text_omitted"] = false;
	return out;
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// `docs/tools_list.renamed.json`, character for character - and that entry is
// generated from `ADDED_TOOLS` in `scripts/gen_renamed_contract.py` (GDR-28
// point 1: an added entry is authored by the decision maker, never by this file).
// ---------------------------------------------------------------------------

// The schema literal is *parsed* rather than built by hand (a hand transcription
// is where a default's type drifts), and Godot's JSON has one number type: a
// parsed `1048576` is a **float**, and `JSON::stringify` then publishes `1048576.0`
// where the contract says `1048576`. Integral numbers are therefore folded back to
// INT. This is the same helper the two earlier parsing registrars carry
// (`tools/editor_read_scene_inspector.cpp:681`, `tools/project_write_resource_scene.cpp:789`);
// it stays a file-local copy here because hoisting it means touching three
// already-shipped files, and the module's rule is that a shared helper is hoisted
// by the task that needs it in a *new* place only (PLAYBOOK section 6.5).
// Lossless for this contract: its numbers are integral (the default and the
// maximum).
static Variant _fold_integral_numbers(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::FLOAT: {
			const double number = p_value;
			if (number >= -9.0e15 && number <= 9.0e15) {
				const int64_t truncated = (int64_t)number;
				if ((double)truncated == number) {
					return Variant(truncated);
				}
			}
			return p_value;
		}
		case Variant::DICTIONARY: {
			const Dictionary source = p_value;
			Dictionary out;
			const Array keys = source.keys();
			for (int i = 0; i < keys.size(); i++) {
				out[keys[i]] = _fold_integral_numbers(source[keys[i]]);
			}
			return out;
		}
		case Variant::ARRAY: {
			const Array source = p_value;
			Array out;
			for (int i = 0; i < source.size(); i++) {
				out.push_back(_fold_integral_numbers(source[i]));
			}
			return out;
		}
		default:
			return p_value;
	}
}

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_text_read.cpp");
		return Dictionary();
	}
	return _fold_integral_numbers(json.get_data());
}

void register_project_text_read_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("project_read_text_file",
			String::utf8(R"desc(Read a text file inside the project and answer its bytes, size and digest, so a file written by a tool can be verified with a tool.)desc"));
	builder.channel("project").verb("read").scope(MCPToolScope::BOTH).mutating(false);
	builder.schema(_schema_from_json(R"schema({"properties":{"max_bytes":{"default":1048576,"maximum":16777216,"type":"integer"},"path":{"type":"string"}},"required":["path"],"type":"object"})schema"));
	builder.handler(_tool_read_text_file).register_into(r_registry);
}