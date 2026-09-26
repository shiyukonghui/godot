/**************************************************************************/
/*  mcp_http_server.h                                                     */
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

#include "mcp_deferred.h"

#include "core/io/stream_peer_tcp.h"
#include "core/io/tcp_server.h"
#include "core/string/string_name.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// HTTP/1.1 subset used by the MCP endpoint (GDR-5).
//
// The parser is deliberately free of sockets and engine state so that every
// framing edge case (half packets, keep-alive, missing/oversized bodies) can be
// unit tested without binding a port.
namespace MCPHttp {

enum class ParseStatus {
	NEED_MORE,
	COMPLETE,
	BAD_REQUEST_LINE,
	UNSUPPORTED_VERSION,
	HEADER_TOO_LARGE,
	// The header block was terminated by a bare LF instead of CRLF. HTTP/1.1
	// mandates CRLF, and treating this as "not complete yet" would leave the
	// client waiting for the 30 s idle timeout with no answer at all, so it is
	// an immediate 400 (GDR-12.3).
	BARE_LF_LINE_ENDING,
	MISSING_CONTENT_LENGTH,
	INVALID_CONTENT_LENGTH,
	BODY_TOO_LARGE,
};

struct Request {
	String method;
	String path;
	String version;
	bool keep_alive = true;
	String body;
};

struct ParseOutcome {
	ParseStatus status = ParseStatus::NEED_MORE;
	Request request;
	// Set together with NEED_MORE when the peer announced
	// `Expect: 100-continue` and is therefore waiting for the interim response
	// before it starts sending the body. The parser is stateless, so the
	// once-per-request bookkeeping belongs to the transport.
	bool expect_continue = false;
	// Set when the request body was not valid UTF-8, so `String::utf8` replaced
	// the offending bytes with U+FFFD. The body is still accepted on purpose
	// (the client contract is UTF-8 and no strict validation path is added);
	// this only drives the verbose warning and keeps the substitution
	// observable (GDR-12.4).
	bool body_invalid_utf8 = false;
};

enum {
	MAX_HEADER_BYTES = 8192,
};

// Parses one request out of `r_buffer`. On COMPLETE the consumed bytes are
// removed from the buffer. On NEED_MORE the buffer is left untouched so that
// the remainder of a split request can be appended later. On a framing error
// the buffer is cleared (the connection is going to be closed anyway).
ParseOutcome parse_request(Vector<uint8_t> &r_buffer, int p_max_body_bytes, int p_max_header_bytes = MAX_HEADER_BYTES);

// Strict RFC 3629 validation: rejects truncated sequences, overlong encodings,
// UTF-16 surrogates and code points above U+10FFFF.
//
// `String::utf8` does not fail on any of those, it substitutes U+FFFD, so
// "does the decoded string contain U+FFFD" cannot be used to detect a
// substitution (a payload may legitimately contain U+FFFD). The raw bytes have
// to be checked instead (GDR-12.4).
bool is_valid_utf8(const uint8_t *p_bytes, int p_length);

// Interim `HTTP/1.1 100 Continue\r\n\r\n` (D33). A 1xx response has no body, so
// it must not carry `Content-Type` or `Content-Length`.
String build_continue_response();

// True when a connection has been silent for longer than `p_idle_ms`.
// The subtraction has to be guarded: the activity stamp is taken from a second
// reading of `get_ticks_msec()`, so it can be newer than the frame clock, and
// the plain unsigned `p_now_ms - p_last_activity_ms` would wrap around to a
// huge value and report a live connection as idle.
bool is_idle_timeout(uint64_t p_now_ms, uint64_t p_last_activity_ms, uint64_t p_idle_ms);

// HTTP status code a framing error maps to.
int status_code_for(ParseStatus p_status);

// Reason phrase for a status code ("OK", "Not Found", ...).
String reason_phrase(int p_status);

// Serializes a complete HTTP/1.1 response, including the mandatory headers.
String build_response(int p_status, const String &p_body, bool p_keep_alive);

} // namespace MCPHttp

// What the sink returns for one JSON-RPC payload (GDR-20).
//
// The immediate case is what it always was: a body and an HTTP status. The
// deferred case is new and carries no body at all - the tool handed the
// transport a task, and the response is produced several frames later by
// `MCPHttpServer::poll` through `build_deferred_body()`.
struct MCPHttpOutcome {
	String body;
	int http_status = 200;
	bool close = false;

	// Set when the tool answers across frames: the transport adopts `task` and
	// arms `timeout_ms` on it. Ownership of `task` transfers to the transport.
	bool deferred = false;
	MCPDeferred::Task *task = nullptr;
	// The verbatim `id` token of the request, so the late response can be
	// addressed without re-parsing the payload.
	String id_json;
	uint64_t timeout_ms = 0;
	// TASK-038: what the JSON-RPC layer saw, for the opt-in call trace. The
	// transport adds the connection identity, the two wall times and the size of
	// the response body it really produced, then hands the record to the
	// recorder. `trace.traceable` stays false when the trace is off.
	MCPTrace::Record trace;
};

// Implemented by MCPServer. Keeping the transport behind this interface is what
// makes "responses are written back to the connection that issued them"
// structural: the transport hands out a request and immediately receives the
// matching response body.
class MCPHttpRequestSink {
public:
	virtual ~MCPHttpRequestSink() {}

	// Handles a JSON-RPC payload; fills the outcome (immediate body, or the
	// deferred task the transport has to own).
	virtual void handle_jsonrpc_request(const String &p_body, MCPHttpOutcome &r_outcome) = 0;

	// The JSON-RPC envelope of a deferred request that finished, failed or
	// expired. The transport owns the *frame* bookkeeping, the JSON-RPC layer
	// keeps owning the *wire shape* - this method is where those two meet.
	virtual String build_deferred_body(const MCPDeferred::Completion &p_completion) = 0;

	// Body of `GET /mcp` (connectivity probe).
	virtual String get_status_body() = 0;

	// -----------------------------------------------------------------------
	// TASK-092 (item B2): the capture half of a deferred call.
	//
	// A deferred request is answered frames after it was read, so the machinery
	// that finishes a capture when a response is produced (`MCPServer::
	// handle_jsonrpc_request`) cannot be the place a *deferred* capture is
	// finished: at that moment the call has not run yet. The transport is where
	// the call really ends, and it is the transport that knows the one fact the
	// capture line still needs - the `seq` of the call line it belongs to.
	//
	// Both methods are non-pure with a no-op default: a sink that has no capture
	// engine (every doctest, and every process without `--mcp-capture`) keeps
	// working unchanged, and the transport never has to know whether capture is
	// on. `r_record.capture_token` (present only when the request armed one) is
	// the handle.
	//
	// `finish_deferred_capture` answers whether the call line should carry a
	// `capture` member; it must be called with `r_record.ok` already set, because
	// `on_error` mode drops a successful call's picture.
	virtual bool finish_deferred_capture(MCPTrace::Record &r_record, int p_seq) {
		(void)r_record;
		(void)p_seq;
		return false;
	}

	// Releases an armed capture of a request that will never be answered (its
	// connection went away). Nothing is written: there is no line to describe it.
	virtual void discard_deferred_capture(int p_token) { (void)p_token; }
};

// Non-blocking HTTP/1.1 server on top of TCPServer/StreamPeerTCP.
//
// Threading model: everything here runs on the main thread inside MCPServer's
// `_process`. Every connection owns its input and output buffers, and a
// response is always appended to the output buffer of the connection the
// request was read from. There is intentionally no shared, arrival-ordered
// response queue (that design is the root cause of the known FIFO defect in
// the reference GDExtension transport, see REQUIREMENTS C3).
class MCPHttpServer {
	struct Connection {
		// Identity of the connection in the pending table. A pointer would do
		// while the connection lives, but a pending entry can outlive the frame
		// it was created in, so the key has to be a value that no other
		// connection can reuse.
		uint64_t id = 0;
		Ref<StreamPeerTCP> peer;
		Vector<uint8_t> in_buffer;
		Vector<uint8_t> out_buffer;
		int write_offset = 0;
		uint64_t last_activity_ms = 0;
		bool close_after_flush = false;
		bool reading_failed = false;
		// Diagnostics only (verbose log): 0 = none, 1 = wrong path (404),
		// 2 = `Connection: close`, 3 = framing error, 4 = input buffer over the
		// cap, 5 = idle timeout.
		int close_reason = 0;
		// The `Expect: 100-continue` of the request currently being read has
		// already been answered.
		bool continue_sent = false;
	};

	Ref<TCPServer> tcp_server;
	MCPHttpRequestSink *sink = nullptr;
	Vector<Connection *> connections;
	// TASK-038: owned by MCPServer, may be null (= tracing off, the default).
	MCPTrace::Recorder *trace = nullptr;

	// (connection, request id) -> task. Never an arrival ordered response
	// queue: a completion names the connection it belongs to and can therefore
	// only ever be written there (GDR-20 point 1).
	MCPDeferred::Queue pending_requests;
	uint64_t next_connection_id = 1;

	uint16_t port = 0;
	bool listening = false;
	int max_body_bytes = 8 * 1024 * 1024;
	double connection_idle_seconds = 30.0;
	int max_connections = 16;
	// Ceiling for a deferred request; 0 = no deadline.
	uint64_t pending_timeout_ms = 30000;
	// Upper bound on `Task::tick()` calls per frame, so that a wall of pending
	// requests can never delay the ordinary ones (GDR-20 point 4).
	int pending_ticks_per_frame = 8;

	bool _flush(Connection *p_connection);
	void _read(Connection *p_connection, uint64_t p_now);
	void _queue_bytes(Connection *p_connection, const String &p_text);
	void _queue_response(Connection *p_connection, int p_status, const String &p_body, bool p_keep_alive);
	void _queue_continue(Connection *p_connection);
	void _handle_request(Connection *p_connection, const MCPHttp::Request &p_request, int64_t p_frame, uint64_t p_now);
	void _drop_connection(int p_index);
	void _tick_pending(int64_t p_frame, uint64_t p_now);
	// Finds the live connection with this id, or -1. A completion for a
	// connection that is gone cannot happen (dropping the connection releases
	// its entries), so -1 would be a bug; it is handled defensively instead of
	// dereferencing a stale pointer.
	int _find_connection(uint64_t p_connection_id) const;

public:
	MCPHttpServer();
	~MCPHttpServer();

	Error listen(uint16_t p_port, const String &p_bind_address = "127.0.0.1");
	void stop();

	void set_sink(MCPHttpRequestSink *p_sink) { sink = p_sink; }
	// TASK-038: the opt-in call trace. Setting a recorder is what makes the
	// transport ask the dispatcher to describe its requests; leaving it null (the
	// default) keeps every request on exactly the path it took before TASK-038.
	void set_trace_recorder(MCPTrace::Recorder *p_recorder) { trace = p_recorder; }
	void set_max_body_bytes(int p_bytes) { max_body_bytes = p_bytes; }
	void set_connection_idle_seconds(double p_seconds) { connection_idle_seconds = p_seconds; }
	void set_max_connections(int p_count) { max_connections = p_count; }
	void set_pending_timeout_ms(uint64_t p_ms) { pending_timeout_ms = p_ms; }
	void set_pending_ticks_per_frame(int p_count) { pending_ticks_per_frame = p_count < 0 ? 0 : p_count; }

	// Accepts connections, flushes pending writes, parses requests and hands
	// them to the sink. At most `p_max_requests` requests are dispatched, and at
	// most `pending_ticks_per_frame` deferred tasks are advanced.
	//
	// `p_frame` is the frame clock the deferred tasks are ticked with
	// (`SceneTree::get_frame()`, GDR-20 point 7). It is a parameter and not a
	// read so that a socket-free test can drive arbitrary frames.
	void poll(int p_max_requests, int64_t p_frame);

	bool is_listening() const { return listening; }
	uint16_t get_bound_port() const { return port; }
	int get_connection_count() const { return connections.size(); }
	// Observability of the deferred channel (GDR-20 point 5): the number of
	// requests waiting for a later frame.
	int get_pending_count() const { return pending_requests.get_pending_count(); }
	int get_pending_connection_count() const { return pending_requests.get_connection_count(); }
};