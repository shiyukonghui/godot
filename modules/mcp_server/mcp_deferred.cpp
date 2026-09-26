/**************************************************************************/
/*  mcp_deferred.cpp                                                      */
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

#include "mcp_deferred.h"

#include "mcp_file_effects.h"

namespace MCPDeferred {

MCPToolError make_timeout_error(const String &p_description, uint64_t p_timeout_ms) {
	MCPToolError error = MCPToolError::tool_state(
			vformat("Deferred call timed out after %d ms: %s", (int64_t)p_timeout_ms, p_description),
			"Make the awaited state happen earlier, or call the tool again (the wait started at the frame the request was read)");
	// GDR-20 point 4: the timeout carries its own deadline on the wire, in
	// addition to the suggestion every -32000 of this module carries. `data`
	// already holds the suggestion, so the two members are merged rather than
	// one replacing the other.
	Dictionary data;
	if (error.data.get_type() == Variant::DICTIONARY) {
		data = error.data;
	}
	data["timeout_ms"] = (int64_t)p_timeout_ms;
	error.data = data;
	return error;
}

Queue::~Queue() {
	clear();
}

void Queue::clear() {
	for (int i = 0; i < entries.size(); i++) {
		memdelete(entries[i].task);
	}
	entries.clear();
	cursor = 0;
}

void Queue::add(uint64_t p_connection_id, const String &p_id_json, Task *p_task, uint64_t p_timeout_ms, bool p_keep_alive, int64_t p_frame, uint64_t p_now_ms,
		const MCPTrace::Record &p_trace, uint64_t p_start_ms) {
	if (p_task == nullptr) {
		// A deferred dispatch without a handle would be an unroutable request:
		// refuse it here instead of leaving a hole the timeout can never fill.
		return;
	}
	Entry entry;
	entry.sequence = next_sequence++;
	entry.connection_id = p_connection_id;
	entry.id_json = p_id_json;
	entry.keep_alive = p_keep_alive;
	entry.timeout_ms = p_timeout_ms;
	entry.start_frame = p_frame;
	entry.start_ms = p_now_ms;
	entry.task = p_task;
	// TASK-038: the trace travels with the request it describes, so the line is
	// written from the completion and not from the acceptance of the call.
	entry.trace = p_trace;
	entry.trace_start_ms = p_start_ms;
	// The key is (connection, request id): the same request id on two
	// connections is two independent entries, which is exactly the interleaving
	// case of TASK-011 section 1.8 (4).
	entries.push_back(entry);
}

void Queue::tick(int64_t p_frame, uint64_t p_now_ms, int p_budget, Vector<Completion> &r_out) {
	if (p_budget <= 0 || entries.is_empty()) {
		return;
	}

	Vector<uint64_t> finished_sequences;
	int ticks = 0;
	int scanned = 0;
	int index = entries.is_empty() ? 0 : (cursor % entries.size());
	const int total = entries.size();
	while (ticks < p_budget && scanned < total) {
		if (index >= entries.size()) {
			index = 0;
		}
		// This fork's `Vector` exposes no non-const `operator[]`; element writes
		// go through the `write` proxy (`core/templates/vector.h:43-51`).
		Entry &entry = entries.write[index];
		scanned++;

		if (entry.start_frame == p_frame) {
			// Added in this frame: the frame it arrived in is already the frame
			// the tool looked at, so it is not advanced here.
			index++;
			continue;
		}

		ticks++;

		Completion completion;
		completion.connection_id = entry.connection_id;
		completion.id_json = entry.id_json;
		completion.keep_alive = entry.keep_alive;
		// TASK-038: hand the trace back to the transport with the completion.
		completion.trace = entry.trace;
		completion.start_ms = entry.trace_start_ms;

		if (entry.timeout_ms > 0 && p_now_ms > entry.start_ms && (p_now_ms - entry.start_ms) > entry.timeout_ms) {
			// The deadline is checked *before* the tick: an expired wait is a
			// timeout even if the task would have finished now, so that the
			// answer never depends on the ordering of two events inside one
			// frame.
			completion.kind = CompletionKind::TIMEOUT;
			completion.error = make_timeout_error(entry.task->describe(), entry.timeout_ms);
			// TASK-092 (item B2): the window observed so far travels with the
			// timeout too. A wait that ran for ten frames and then expired has
			// ten frames of file-side evidence; the ones it never got are not
			// claimed as "no mutation". A record that is not traceable carries no
			// file-side evidence at all (`""`), exactly like an immediate call
			// with the trace switched off.
			if (entry.trace.traceable) {
				completion.file_effects = entry.file_effects;
				completion.file_effect_status = entry.effects_observed ? MCPFileEffect::status_of(entry.file_effects) : String("not_tracked_deferred");
			}
			finished_sequences.push_back(entry.sequence);
			r_out.push_back(completion);
			index++;
			continue;
		}

		// TASK-092 (item B2): the tool's own frame, wrapped. `Queue::tick` is the
		// only place a deferred task runs, so this is where a deferred call's disk
		// work can be seen at all. The rows are accumulated across the whole
		// deferred window (not per tick) so the completion's status is the verdict
		// of the call, exactly like a synchronous call's single buffer.
		//
		// `is_recording()` is checked, not assumed: nothing opens a scope around
		// this loop today, and if something ever does, the outer buffer is left
		// alone rather than being reset from under it.
		const bool observe_files = entry.trace.traceable && !MCPFileEffect::is_recording();
		if (observe_files) {
			MCPFileEffect::begin_recording();
		}
		const TickResult result = entry.task->tick(p_frame, p_now_ms);
		if (observe_files) {
			MCPFileEffect::end_recording();
			const Array ticked = MCPFileEffect::take_effects();
			entry.effects_observed = true;
			for (int r = 0; r < ticked.size() && entry.file_effects.size() < MCPFileEffect::MAX_ROWS; r++) {
				entry.file_effects.push_back(ticked[r]);
			}
		}
		if (entry.trace.traceable) {
			completion.file_effects = entry.file_effects;
			completion.file_effect_status = entry.effects_observed ? MCPFileEffect::status_of(entry.file_effects) : String("not_tracked_deferred");
		}

		if (result.state == State::DONE) {
			completion.kind = CompletionKind::DONE;
			completion.result = result.result;
			finished_sequences.push_back(entry.sequence);
			r_out.push_back(completion);
		} else if (result.state == State::FAILED) {
			completion.kind = CompletionKind::FAILED;
			completion.error = result.error;
			finished_sequences.push_back(entry.sequence);
			r_out.push_back(completion);
		}
		index++;
	}

	cursor = entries.is_empty() ? 0 : (index % entries.size());

	// Remove by *sequence*, not by the index the entry had during the scan: the
	// scan is round-robin, so the entries that finished are not in ascending
	// index order (the first tick can finish entry 4 and the second entry 0), and
	// a reverse walk over unordered indices walks off the end - measured, it
	// crashed with `Index p_index = 2 is out of bounds (size() = 1)`.
	// `remove_at()` while walking downwards keeps the remaining indices valid, and
	// every adopted task is deleted exactly once.
	for (int i = entries.size() - 1; i >= 0; i--) {
		if (!finished_sequences.has(entries[i].sequence)) {
			continue;
		}
		memdelete(entries[i].task);
		entries.remove_at(i);
	}
}

void Queue::drop_connection(uint64_t p_connection_id, Vector<MCPTrace::Record> *r_dropped_traces) {
	int removed = 0;
	for (int i = entries.size() - 1; i >= 0; i--) {
		if (entries[i].connection_id != p_connection_id) {
			continue;
		}
		if (r_dropped_traces != nullptr) {
			// TASK-092 (item B2): the record still names the capture slot this
			// request armed, so the transport can release it. Order does not
			// matter; only the tokens do.
			r_dropped_traces->push_back(entries[i].trace);
		}
		memdelete(entries[i].task);
		entries.remove_at(i);
		removed++;
	}
	if (removed > 0 && entries.is_empty()) {
		cursor = 0;
	}
}

bool Queue::has_connection(uint64_t p_connection_id) const {
	for (int i = 0; i < entries.size(); i++) {
		if (entries[i].connection_id == p_connection_id) {
			return true;
		}
	}
	return false;
}

int Queue::get_connection_count() const {
	// Deliberately a scan and not a set: the pending table is tiny (bounded by
	// the connection cap) and a scan cannot get out of sync with the entries.
	Vector<uint64_t> seen;
	for (int i = 0; i < entries.size(); i++) {
		const uint64_t id = entries[i].connection_id;
		if (!seen.has(id)) {
			seen.push_back(id);
		}
	}
	return seen.size();
}

} // namespace MCPDeferred
