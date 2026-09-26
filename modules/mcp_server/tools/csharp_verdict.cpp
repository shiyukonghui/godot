/**************************************************************************/
/*  csharp_verdict.cpp                                                    */
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
#include "csharp_verdict.h"

// TASK-089 (item A): the file-side effect recorder, for the build record write.
#include "../mcp_file_effects.h"

#include "core/config/project_settings.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/os/time.h"

namespace {

// One `dotnet build` of a project with many broken files can print hundreds of
// diagnostics; the record exists to answer one file at a time, so the first 64
// are kept and the cut is recorded (`truncated`) instead of being silent.
const int MAX_RECORDED_ERRORS = 64;

// A diagnostic line is one sentence of compiler output; 512 bytes holds the
// longest CS/ MSB message this record is meant to carry whole.
const int MAX_ERROR_TEXT_BYTES = 512;

// `C:\path\x.cs` or `/home/x.cs`. MSBuild prints absolute paths; a res:// path
// is already project-relative.
bool _is_absolute_path(const String &p_path) {
	return p_path.begins_with("/") || (p_path.length() > 2 && p_path[1] == ':');
}

String _to_project_path(const String &p_path) {
	const String slashed = p_path.replace("\\", "/");
	if (!_is_absolute_path(slashed)) {
		return slashed;
	}
	return ProjectSettings::get_singleton()->localize_path(slashed);
}

// Cut on a UTF-8 character boundary, the same rule the bulk readers use.
String _cap_text(const String &p_text) {
	const CharString utf8 = p_text.utf8();
	if (utf8.length() <= MAX_ERROR_TEXT_BYTES) {
		return p_text;
	}
	int cut = MAX_ERROR_TEXT_BYTES;
	const char *bytes = utf8.get_data();
	while (cut > 0 && (((uint8_t)bytes[cut]) & 0xC0) == 0x80) {
		cut--;
	}
	return String::utf8(bytes, cut) + "...";
}

// The trailing `[C:\path\project.csproj]` MSBuild appends to a diagnostic is the
// project the compiler was invoked for, not part of the message. It is dropped
// from `message` so that field is the compiler's own sentence - but only when
// the bracket really holds a project file (MSBuild also appends
// `[...csproj::TargetFramework=net8.0]`), because a message may legitimately end
// with a bracket of its own (`... type 'int[]' to 'string[]'`).
String _strip_project_suffix(const String &p_message) {
	const String message = p_message.strip_edges();
	if (!message.ends_with("]")) {
		return message;
	}
	const int open = message.rfind_char('[');
	if (open <= 0) {
		return message;
	}
	const String tail = message.substr(open + 1);
	if (!tail.contains(".csproj")) {
		return message;
	}
	return message.substr(0, open).strip_edges();
}

} // namespace

namespace MCPTools {

MCPCSharpVerdict classify_csharp_verdict(bool p_class_loaded, bool p_source_newer_than_assembly, bool p_has_recorded_errors) {
	// "Compiled" is the only case where the loaded assembly is a build of this
	// exact source: the class was found *and* the file has not moved since the
	// assembly was built.
	if (p_class_loaded && !p_source_newer_than_assembly) {
		return MCPCSharpVerdict::COMPILED;
	}
	// A recorded rejection always wins over "nothing compiled it": if the source
	// that is on disk right now (the record carries the modification time it
	// was seen with) was rejected by a build, then this file did not compile.
	if (p_has_recorded_errors) {
		return MCPCSharpVerdict::BUILD_FAILED;
	}
	return MCPCSharpVerdict::NOT_COMPILED;
}

Array parse_csharp_build_errors(const String &p_output) {
	Array out;

	// `String::split` keeps empty lines out of the way by the `is_empty` test
	// below; the separators are normalized first so a `\r\n` capture does not
	// leave a stray `\r` on every diagnostic.
	const String normalized = p_output.replace("\r\n", "\n").replace("\r", "\n");
	const Vector<String> lines = normalized.split("\n");
	for (int i = 0; i < lines.size(); i++) {
		const String line = lines[i].strip_edges();
		if (line.is_empty()) {
			continue;
		}

		// Two shapes are parsed, both of them MSBuild's own:
		//   C:\proj\scripts\broken.cs(3,5): error CS1002: ; expected [C:\proj\X.csproj]
		//   CSC : error CS2001: Source file 'x.cs' could not be found
		// A localized MSBuild prints a translated word instead of `error` and is
		// deliberately *not* parsed: inventing a match for it would be guessing.
		String position;
		String rest;
		const int anchored = line.find(": error ");
		if (anchored >= 0) {
			position = line.substr(0, anchored).strip_edges();
			rest = line.substr(anchored + 8);
		} else if (line.begins_with("error ")) {
			rest = line.substr(6);
		} else {
			continue;
		}

		const int colon = rest.find_char(':');
		if (colon <= 0) {
			// `error <something>` with no `:<message>` is not a diagnostic this
			// record can name a code for.
			continue;
		}
		const String code = rest.substr(0, colon).strip_edges();
		if (code.is_empty()) {
			continue;
		}

		Dictionary entry;
		String file;
		int64_t line_number = 0;
		int64_t column = 0;
		// `file(line,column)` - MSBuild's own position spelling.
		const int open = position.rfind_char('(');
		if (open > 0 && position.ends_with(")")) {
			const String inside = position.substr(open + 1, position.length() - open - 2);
			const int comma = inside.find_char(',');
			if (comma > 0) {
				const String file_text = position.substr(0, open).strip_edges();
				const String line_text = inside.substr(0, comma).strip_edges();
				const String column_text = inside.substr(comma + 1).strip_edges();
				if (file_text.is_valid_int() == false && line_text.is_valid_int() && column_text.is_valid_int()) {
					file = _to_project_path(file_text);
					line_number = line_text.to_int();
					column = column_text.to_int();
				}
			}
		}
		if (file.is_empty() && !position.is_empty() && position != "CSC" && position != "MSBUILD") {
			// A path with no position (`x.cs : error CS...`).
			file = _to_project_path(position);
		}

		const String message = _strip_project_suffix(rest.substr(colon + 1));
		entry["file"] = file;
		entry["line"] = line_number;
		entry["column"] = column;
		entry["code"] = code;
		entry["text"] = _cap_text(line);
		entry["message"] = _cap_text(message);
		out.push_back(entry);
	}

	if (out.size() > MAX_RECORDED_ERRORS) {
		Array cut;
		for (int i = 0; i < MAX_RECORDED_ERRORS; i++) {
			cut.push_back(out[i]);
		}
		out = cut;
	}
	return out;
}

String csharp_build_record_path() {
	return "user://mcp_csharp_build_state.json";
}

void write_csharp_build_record(const String &p_configuration, const Array &p_project_files,
		int64_t p_exit_code, bool p_timed_out, const Array &p_errors, bool p_truncated) {
	Array errors;
	for (int i = 0; i < p_errors.size(); i++) {
		const Variant element = p_errors[i];
		if (element.get_type() != Variant::DICTIONARY) {
			continue;
		}
		Dictionary error = element;
		// The modification time the file had while the build ran. This is what
		// makes a recorded diagnostic expire the moment the file is edited: a
		// caller that fixed the source must not be told about the old error.
		const String file = error.get("file", String());
		error["mtime"] = file.is_empty() ? 0 : (int64_t)FileAccess::get_modified_time(file);
		errors.push_back(error);
	}

	Dictionary record;
	record["schema"] = 1;
	record["tool"] = "project_build_csharp";
	record["time_unix"] = (int64_t)Time::get_singleton()->get_unix_time_from_system();
	record["configuration"] = p_configuration;
	record["project_files"] = p_project_files;
	record["exit_code"] = p_exit_code;
	record["timed_out"] = p_timed_out;
	record["error_count"] = errors.size();
	record["truncated"] = p_truncated;
	record["errors"] = errors;

	// TASK-089 (item A): the build record is a file the tool writes on its own,
	// without the module's publish primitive, so the one recorder is opened here
	// too - a caller must be able to see that `project_build_csharp` wrote
	// something even when its build output is truncated. The scope is opened
	// **before** the file: `FileAccess::open(..., WRITE)` truncates on open, so a
	// snapshot taken afterwards would describe the truncated file, not the one
	// the call found.
	// [REBUILT-2C low-confidence: verify] TASK-089 item A: written, not
	// replayed; REBUILT-2C-MANIFEST.md 2c-8 (H-2).
	MCPFileEffect::MutationScope record_effect(csharp_build_record_path(), "write");
	// [/REBUILT-2C]
	Ref<FileAccess> file = FileAccess::open(csharp_build_record_path(), FileAccess::WRITE);
	if (file.is_null()) {
		record_effect.mark_failed();
		// The build itself already happened and its answer does not depend on
		// this record; a project that cannot write `user://` simply keeps the
		// engine-only half of the verdict.
		print_verbose("MCP: could not write the C# build record to " + csharp_build_record_path());
		return;
	}
	file->store_string(JSON::stringify(record));
	file->close();
}

Dictionary read_csharp_build_record() {
	if (!FileAccess::exists(csharp_build_record_path())) {
		return Dictionary();
	}
	Ref<FileAccess> file = FileAccess::open(csharp_build_record_path(), FileAccess::READ);
	if (file.is_null()) {
		return Dictionary();
	}
	const String text = file->get_as_text();
	file->close();

	JSON json;
	if (json.parse(text) != OK || json.get_data().get_type() != Variant::DICTIONARY) {
		// A corrupted record is not a verdict: it is dropped rather than
		// guessed at.
		return Dictionary();
	}
	return json.get_data();
}

Array recorded_csharp_build_errors(const String &p_path) {
	Array out;
	const Dictionary record = read_csharp_build_record();
	if (record.is_empty()) {
		return out;
	}
	const Variant raw = record.get("errors", Variant());
	if (raw.get_type() != Variant::ARRAY) {
		return out;
	}
	const Array errors = raw;
	const uint64_t current_mtime = FileAccess::get_modified_time(p_path);
	for (int i = 0; i < errors.size(); i++) {
		const Variant element = errors[i];
		if (element.get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary error = element;
		if ((String)error.get("file", String()) != p_path) {
			continue;
		}
		const uint64_t recorded_mtime = (uint64_t)(int64_t)error.get("mtime", 0);
		if (recorded_mtime != current_mtime) {
			// This source is not the source that build rejected.
			continue;
		}
		out.push_back(error);
	}
	return out;
}

} // namespace MCPTools
