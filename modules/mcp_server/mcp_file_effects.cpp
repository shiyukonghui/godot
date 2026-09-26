/**************************************************************************/
/*  mcp_file_effects.cpp                                                  */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                  */
/**************************************************************************/
#include "mcp_file_effects.h"

#include "core/config/project_settings.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"

namespace MCPFileEffect {

namespace {

struct Snapshot {
	bool exists = false;
	int64_t bytes = 0;
	String sha256;
};

// The per-call buffer. The module serves its endpoints from the main thread
// only (no `Thread` is created anywhere in `modules/mcp_server`), so a plain
// namespace-scope buffer is the whole synchronisation this needs. `recording`
// is the zero-overhead switch: with a trace off, no scope ever snapshots.
bool recording = false;
Array rows;
int total_rows = 0;
bool truncated = false;
bool any_changed = false;
bool any_unchanged = false;

String absolute_path(const String &p_path) {
	if (p_path.begins_with("res://") || p_path.begins_with("user://")) {
		ProjectSettings *settings = ProjectSettings::get_singleton();
		if (settings != nullptr) {
			return settings->globalize_path(p_path);
		}
	}
	return p_path;
}

Snapshot snapshot_file(const String &p_path) {
	Snapshot out;
	if (!FileAccess::exists(p_path)) {
		return out;
	}
	Ref<FileAccess> file = FileAccess::open(p_path, FileAccess::READ);
	if (file.is_null()) {
		return out;
	}
	out.exists = true;
	out.bytes = (int64_t)file->get_length();
	file->close();
	// The engine's own hash of the bytes that are there right now.
	out.sha256 = FileAccess::get_sha256(p_path);
	return out;
}

// `MCPTools::split_lines` semantics (Rust's `str::lines()`): split on '\n',
// drop one trailing '\r', do not invent a final empty line.
Vector<String> split_lines(const String &p_text) {
	Vector<String> out;
	int start = 0;
	while (start < p_text.length()) {
		int end = p_text.find_char('\n', start);
		if (end < 0) {
			end = p_text.length();
		}
		int line_end = end;
		if (line_end > start && p_text[line_end - 1] == '\r') {
			line_end--;
		}
		out.push_back(p_text.substr(start, line_end - start));
		start = end + 1;
	}
	return out;
}

String clip_line(const String &p_line) {
	if (p_line.length() <= MAX_LINE_CHARS) {
		return p_line;
	}
	return p_line.substr(0, MAX_LINE_CHARS) + "...";
}

// Reads the file as text when that is cheap and honest: the file has to be
// within the size cap and has to contain no NUL byte, which is what separates a
// text destination (a `.gd`, a `.tscn`, a `project.godot`) from a PNG or a
// compiled blob. `r_ok` answers whether a difference may be computed.
String read_text(const String &p_path, bool &r_ok) {
	r_ok = false;
	if (!FileAccess::exists(p_path)) {
		return String();
	}
	Ref<FileAccess> file = FileAccess::open(p_path, FileAccess::READ);
	if (file.is_null()) {
		return String();
	}
	const int64_t length = (int64_t)file->get_length();
	if (length > MAX_TEXT_BYTES) {
		file->close();
		return String();
	}
	const Vector<uint8_t> bytes = file->get_buffer(length);
	file->close();
	for (int i = 0; i < bytes.size(); i++) {
		if (bytes[i] == 0) {
			return String();
		}
	}
	r_ok = true;
	return String::utf8((const char *)bytes.ptr(), bytes.size());
}

// A bounded head/tail difference summary.
//
// This is deliberately **not** a full LCS diff: an LCS over two arbitrary files
// is unbounded work inside a request path, and the fact an operator needs is
// "how many lines are the same at the top, how many at the bottom, how big is
// the block in between, and what does that block look like at its two ends". The
// equal prefix and the equal suffix are trimmed first, then the differing block
// is sampled from both ends. `type` says so on the wire.
Dictionary build_diff(const String &p_before, const String &p_after) {
	const Vector<String> before = split_lines(p_before);
	const Vector<String> after = split_lines(p_after);

	const int min_lines = MIN(before.size(), after.size());
	int same_head = 0;
	while (same_head < min_lines && before[same_head] == after[same_head]) {
		same_head++;
	}
	int same_tail = 0;
	while (same_tail < min_lines - same_head &&
			before[before.size() - 1 - same_tail] == after[after.size() - 1 - same_tail]) {
		same_tail++;
	}

	const int changed_before = before.size() - same_head - same_tail;
	const int changed_after = after.size() - same_head - same_tail;

	Array head;
	Array tail;
	int head_lines = 0;
	int tail_lines = 0;
	for (int i = 0; i < DIFF_SAMPLE_LINES && i < changed_before; i++) {
		head.push_back("- " + clip_line(before[same_head + i]));
		head_lines++;
	}
	for (int i = 0; i < DIFF_SAMPLE_LINES && i < changed_after; i++) {
		head.push_back("+ " + clip_line(after[same_head + i]));
		head_lines++;
	}
	for (int i = changed_before - 1; i >= 0 && i >= changed_before - DIFF_SAMPLE_LINES; i--) {
		tail.push_back("- " + clip_line(before[same_head + i]));
		tail_lines++;
	}
	for (int i = changed_after - 1; i >= 0 && i >= changed_after - DIFF_SAMPLE_LINES; i--) {
		tail.push_back("+ " + clip_line(after[same_head + i]));
		tail_lines++;
	}

	Dictionary lines;
	lines["before"] = before.size();
	lines["after"] = after.size();

	Dictionary changed;
	changed["before"] = changed_before;
	changed["after"] = changed_after;

	Dictionary diff;
	diff["type"] = "line_head_tail";
	diff["lines"] = lines;
	diff["same_head_lines"] = same_head;
	diff["same_tail_lines"] = same_tail;
	diff["changed_lines"] = changed;
	diff["head_lines"] = head_lines;
	diff["tail_lines"] = tail_lines;
	diff["head"] = head;
	diff["tail"] = tail;
	// True when the differing block is bigger than what was sampled.
	diff["sampled_partial"] = (changed_before > DIFF_SAMPLE_LINES * 2 || changed_after > DIFF_SAMPLE_LINES * 2);
	return diff;
}

Variant state_dictionary(const Snapshot &p_snapshot) {
	if (!p_snapshot.exists) {
		// A destination that is not there is `null`, not `{}`: `{}` would claim
		// "there is a state and it has no information".
		return Variant();
	}
	Dictionary out;
	out["sha256"] = p_snapshot.sha256;
	out["bytes"] = p_snapshot.bytes;
	return out;
}

} // namespace

void begin_recording() {
	recording = true;
	rows = Array();
	total_rows = 0;
	truncated = false;
	any_changed = false;
	any_unchanged = false;
}

void end_recording() {
	recording = false;
}

bool is_recording() {
	return recording;
}

Array take_effects() {
	const Array out = rows;
	rows = Array();
	return out;
}

int last_total_rows() {
	return total_rows;
}

bool last_truncated() {
	return truncated;
}

String status_name() {
	if (recording) {
		return "recording";
	}
	if (total_rows == 0) {
		return "no_mutation";
	}
	if (any_changed && any_unchanged) {
		return "observed_mixed";
	}
	return any_changed ? "observed_changed" : "observed_no_change";
}

MutationScope::MutationScope(const String &p_path, const String &p_kind) {
	if (!recording) {
		return;
	}
	active = true;
	path = p_path;
	kind = p_kind;
	// A directory creation is the one mutation whose destination is not a file:
	// it is reported by existence alone, which is the whole of what changed.
	if (kind == "mkdir") {
		before_exists = DirAccess::dir_exists_absolute(absolute_path(p_path));
		return;
	}
	const Snapshot before = snapshot_file(p_path);
	before_exists = before.exists;
	before_bytes = before.bytes;
	before_sha = before.sha256;
	before_text = read_text(p_path, before_text_read);
}

void MutationScope::mark_failed() {
	failed = true;
}

MutationScope::~MutationScope() {
	if (!active) {
		return;
	}

	Dictionary row;
	row["path"] = path;
	row["abs_path"] = absolute_path(path);
	row["kind"] = kind;
	row["failed"] = failed;

	bool changed = false;
	bool text_known = false;

	if (kind == "mkdir") {
		const bool after_exists = DirAccess::dir_exists_absolute(absolute_path(path));
		row["existed_before"] = before_exists;
		row["exists_after"] = after_exists;
		changed = (before_exists != after_exists);
		row["changed"] = changed;
	} else {
		const Snapshot after = snapshot_file(path);
		row["existed_before"] = before_exists;
		row["before"] = state_dictionary({ before_exists, before_bytes, before_sha });
		row["after"] = state_dictionary(after);
		changed = (before_exists != after.exists) || (before_exists && before_sha != after.sha256);
		row["changed"] = changed;

		// The difference is computed over the text that is there **before** and
		// **after**; the "after" file is read back off disk rather than taken
		// from the writer, so the recorded difference describes the destination,
		// not the intent. A destination that did not exist counts as the empty
		// text, so creating a file records "every line is new" instead of
		// recording no difference at all. Only small text destinations get one.
		bool after_text_read = false;
		const String after_text = changed ? read_text(path, after_text_read) : String();
		text_known = after_text_read && (before_text_read || !before_exists);
		if (text_known) {
			row["diff"] = build_diff(before_text_read ? before_text : String(), after_text);
		}
	}

	total_rows++;
	if (total_rows > MAX_ROWS) {
		truncated = true;
		return;
	}
	if (changed) {
		any_changed = true;
	} else {
		any_unchanged = true;
	}
	rows.push_back(row);
}

} // namespace MCPFileEffect
