/**************************************************************************/
/*  mcp_deferred.h                                                        */
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

#include "mcp_trace.h"
#include "tool_registry.h"

#include "core/string/ustring.h"
#include "core/templates/vector.h"
#include "core/variant/variant.h"

// ---------------------------------------------------------------------------
// Deferred response channel (GDR-20 / TASK-011).
//
// Every tool in this module used to answer inside the frame that read the
// request: `MCPServer::pump_frame` -> `MCPHttpServer::poll` -> tool handler ->
// response. That is a hard wall for a whole family of tools whose observable
// behaviour *is* the passage of frames - sampling a property over N frames,
// polling until a node appears, capturing N rendered frames - because in a
// single frame all N observations are the same observation. TASK-010 proved it
// with the minimal counterexample (N samples, N identical values).
//
// This header holds the *state machine*, deliberately free of sockets, of the
// engine's SceneTree and of the JSON-RPC wire format, so that all of it can be
// unit tested in the doctest binary:
//
//   * `Task`  - the handle a tool returns instead of a result. `tick()` is the
//               only thing the tool has to implement and it must never block.
//   * `Queue` - the pending table. It is keyed by **(connection, request id)**,
//               never by arrival order: there is no FIFO of responses to pair
//               up, which is the defect REQUIREMENTS C3 forbids. A response can
//               only ever be produced for the connection that issued the
//               request, and `drop_connection()` is the single place a dead
//               connection's pending entries are released (GDR-20 point 5: no
//               leak, and the count is observable).
//
// The frame clock is the SceneTree's frame counter; it is passed in by the
// caller (`MCPServer::pump_frame` reads `SceneTree::get_frame()`), never read
// here, so a test drives an arbitrary number of frames with no engine at all.
// ---------------------------------------------------------------------------

namespace MCPDeferred {

// The outcome of one `tick()`.
enum class State {
	// Not finished: the queue keeps the entry and tries again next frame.
	PENDING,
	// Finished with a tool result.
	DONE,
	// Finished with a tool error (`-32602` / `-32001` / `-32000` / `-32603`).
	FAILED,
};

struct TickResult {
	State state = State::PENDING;
	// Valid when `state == DONE`.
	Variant result;
	// Valid when `state == FAILED`.
	MCPToolError error;

	static TickResult pending() { return TickResult(); }

	static TickResult done(const Variant &p_result) {
		TickResult result;
		result.state = State::DONE;
		result.result = p_result;
		return result;
	}

	static TickResult failed(const MCPToolError &p_error) {
		TickResult result;
		result.state = State::FAILED;
		result.error = p_error;
		return result;
	}
};

// A tool's deferred handle. The transport adopts every instance handed to it
// (`Queue::add`) and deletes it exactly once: on completion, on timeout or when
// its connection goes away.
class Task {
public:
	virtual ~Task() {}

	// Advances the task by at most one frame. **Must not block**: no `sleep`,
	// no busy wait, no nested frame loop (GDR-20 point 3).
	//
	// `p_frame` is the SceneTree frame counter, `p_now_ms` the monotonic
	// millisecond clock of the same frame. Both come from the framework, so a
	// task never reads a clock of its own.
	virtual TickResult tick(int64_t p_frame, uint64_t p_now_ms) = 0;

	// The task's own deadline in milliseconds, or 0 to use the framework
	// default. The framework uses the *smaller* of this and its configured
	// ceiling, so a per-call timeout can shorten a wait but never extend it.
	virtual uint64_t get_timeout_ms() const { return 0; }

	// Diagnostics only (the verbose drop/log lines).
	virtual String describe() const { return "deferred task"; }
};

// How a deferred request ended. Produced by `Queue::tick()` and turned into a
// JSON-RPC body by the transport (the queue never formats the wire).
enum class CompletionKind {
	DONE,
	FAILED,
	// The deadline passed. Always `-32000` with `data.suggestion` and
	// `data.timeout_ms` (GDR-20 point 4); a timed out request is never silently
	// dropped.
	TIMEOUT,
};

struct Completion {
	CompletionKind kind = CompletionKind::DONE;
	// The connection the request was read from. The transport writes the
	// response back to *this* connection and no other.
	uint64_t connection_id = 0;
	// The verbatim `id` token of the request, echoed unchanged.
	String id_json;
	// Valid when `kind == DONE`.
	Variant result;
	// Valid when `kind == FAILED` or `kind == TIMEOUT`.
	MCPToolError error;
	// The `Connection:` of the request that started the wait.
	bool keep_alive = true;
	// TASK-038: the trace record of the request, carried through the wait so the
	// one line describing this call is written when the call really ended (with
	// its true duration and pending time), not when it was accepted. Untouched
	// - `traceable == false` - whenever the trace is switched off.
	MCPTrace::Record trace;
	// The transport clock reading (`OS::get_ticks_msec()`) at which the request
	// was read; the transport computes the two wall times of the trace line from
	// it. 0 when the trace is off.
	uint64_t start_ms = 0;
};

// The pending table.
class Queue {
public:
	~Queue();

	// Adopts `p_task` (ownership transfers to the queue). `p_timeout_ms` is the
	// already-clamped effective deadline; 0 means "no timeout".
	//
	// TASK-038: `p_trace` (and `p_start_ms`) travel with the entry so that the
	// completion of a deferred request can be recorded with its own facts. Both
	// default to "nothing to record", so every caller that does not care about
	// the trace - the doctests, above all - keeps its old call.
	void add(uint64_t p_connection_id, const String &p_id_json, Task *p_task, uint64_t p_timeout_ms, bool p_keep_alive, int64_t p_frame, uint64_t p_now_ms,
			const MCPTrace::Record &p_trace = MCPTrace::Record(), uint64_t p_start_ms = 0);

	// Advances at most `p_budget` pending entries and appends every request that
	// finished (or expired) to `r_out`. A task added in `p_frame` is never
	// advanced in that same frame: the frame it arrived in has already been
	// observed by the tool, so ticking there would count one frame twice.
	//
	// The budget is what keeps a wall of pending requests from starving the
	// ordinary ones (GDR-20 point 4): the transport dispatches requests *before*
	// it calls this, and it calls this with a bounded budget.
	void tick(int64_t p_frame, uint64_t p_now_ms, int p_budget, Vector<Completion> &r_out);

	// Releases every pending entry of one connection. Called from the single
	// point where a connection is dropped, which is what makes a leak
	// structurally impossible.
	void drop_connection(uint64_t p_connection_id);

	void clear();

	int get_pending_count() const { return entries.size(); }
	// Number of distinct connections currently owning at least one entry.
	int get_connection_count() const;
	// True when this connection has at least one request waiting for a later
	// frame. The transport uses it to hold back that connection's request
	// stream (HTTP/1.1 response ordering) and to keep it out of the idle reaper.
	bool has_connection(uint64_t p_connection_id) const;

private:
	struct Entry {
		uint64_t sequence = 0;
		uint64_t connection_id = 0;
		String id_json;
		bool keep_alive = true;
		uint64_t timeout_ms = 0;
		int64_t start_frame = 0;
		uint64_t start_ms = 0;
		Task *task = nullptr;
		MCPTrace::Record trace;
		// The transport's clock reading when the request was read, used only for
		// the trace line's two wall times (0 when the trace is off).
		uint64_t trace_start_ms = 0;
	};

	Vector<Entry> entries;
	// Round-robin start, so that a long running entry cannot make the entries
	// behind it starve.
	int cursor = 0;
	uint64_t next_sequence = 1;
};

// The `-32000` refusal of an expired wait, with both required `data` members.
MCPToolError make_timeout_error(const String &p_description, uint64_t p_timeout_ms);

} // namespace MCPDeferred