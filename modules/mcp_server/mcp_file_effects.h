/**************************************************************************/
/*  mcp_file_effects.h                                                    */
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
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                  */
/**************************************************************************/
#pragma once

#include "core/string/ustring.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

// ---------------------------------------------------------------------------
// File-side side effects on the call trace (TASK-089 item A).
//
// The trace (TASK-038) records what a JSON-RPC request *was* and what it
// answered; the capture extension (TASK-044) records whether the **screen**
// changed. Neither says whether the call changed a **file**, which was the one
// declared gap left in the traceability model (MCP-TRACEABILITY.md §3.2:
// `file_effect_evidence: "not_recorded_in_trace"`).
//
// This is the one recorder for that fact. A mutating primitive opens a
// `MutationScope` around itself; the scope snapshots the destination before,
// snapshots it again when it goes out of scope and appends one row to the
// per-call buffer. Nothing else in the module computes a file hash, so the
// cost is paid exactly once per mutation and only while a trace is on:
//
//   * `begin_recording()` is called by the JSON-RPC layer immediately before a
//     `tools/call` runs its tool, and only when the request is traceable. With
//     `--mcp-trace` off, no scope ever becomes active and every primitive
//     performs the work it performed before - no `exists` probe, no hash, no
//     read.
//   * the buffer is drained by the same layer after the tool returned, and the
//     rows are handed to `MCPTrace::Record::file_effects`, i.e. they are emitted
//     **on the call line**, at the same level as `id` / `method` / `tool`.
//
// Cost control (declared, not implied): a file larger than `MAX_TEXT_BYTES` is
// never read for a difference - only its sha256 and byte count are kept - and
// every recorded difference line is truncated to `MAX_LINE_CHARS`. The whole
// buffer is bounded by `MAX_ROWS`; a tool that mutates more files than that
// keeps the first rows and sets `truncated`.
// ---------------------------------------------------------------------------

namespace MCPFileEffect {

// A file bigger than this is recorded by hash and size only.
const int MAX_TEXT_BYTES = 262144;
// How many lines of each side of the differing block are sampled at its head
// and at its tail.
const int DIFF_SAMPLE_LINES = 3;
// Per recorded difference line, in characters.
const int MAX_LINE_CHARS = 200;
// Per call. A batch tool that touches more destinations than this is recorded
// as truncated rather than unbounded.
const int MAX_ROWS = 256;

// Starts a fresh per-call buffer. Called by the JSON-RPC layer for a traceable
// `tools/call`, before the tool runs.
void begin_recording();

// Stops collecting. The buffer is kept until `take_effects()` reads it, so the
// layer may stop collection and still drain.
void end_recording();

bool is_recording();

// The rows collected for the call that just finished, and a reset of the
// buffer. Always an `Array` (empty when nothing touched the disk).
Array take_effects();

// How many rows were collected in total (including ones beyond `MAX_ROWS`).
int last_total_rows();

// True when more mutations happened than `MAX_ROWS`.
bool last_truncated();

// One of:
//   "no_mutation"        the call ran and touched no file
//   "observed_changed"   every recorded mutation really changed its destination
//   "observed_no_change" every recorded mutation left its destination as it was
//   "observed_mixed"     some changed, some did not
//   "recording"          still inside a call
// An empty string means "this call carries no file-side evidence at all" (the
// trace was off, or the call never reached a tool).
String status_name();

// TASK-092 (item B2): the same vocabulary, computed from an **accumulated** set
// of rows instead of the buffer of one call. A deferred call's disk work is
// spread over the frames its task is ticked in, so its rows are collected
// tick by tick and the verdict can only be taken once, when the call really
// ends. `p_rows` empty answers `no_mutation`, which for a deferred call means
// "every frame it ran in was observed and none of them touched disk" - the
// caller is responsible for saying `not_tracked_deferred` when it observed no
// frame at all (see `MCPDeferred::Queue::tick`).
String status_of(const Array &p_rows);

// The scope a mutating primitive opens around itself. Non-copyable; the
// destructor is what appends the row.
//
// `p_kind` is the spelling that goes on the wire: "write", "delete", "mkdir".
class MutationScope {
public:
	MutationScope(const String &p_path, const String &p_kind);
	~MutationScope();

	MutationScope(const MutationScope &) = delete;
	MutationScope &operator=(const MutationScope &) = delete;

	// The primitive failed. The destination is still snapshotted (that is what
	// proves the file was not left half-written), and the row says so.
	void mark_failed();

private:
	String path;
	String kind;
	bool active = false;
	bool failed = false;
	// The "before" half, taken in the constructor.
	bool before_exists = false;
	int64_t before_bytes = 0;
	String before_sha;
	String before_text;
	bool before_text_read = false;
};

} // namespace MCPFileEffect
