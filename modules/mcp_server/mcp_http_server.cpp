/**************************************************************************/
/*  mcp_http_server.cpp                                                   */
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

#include "mcp_http_server.h"

#include "core/io/json.h"
#include "core/os/os.h"

namespace MCPHttp {

static void _consume_bytes(Vector<uint8_t> &r_buffer, int p_count) {
	if (p_count <= 0) {
		return;
	}
	if (p_count >= r_buffer.size()) {
		r_buffer.clear();
		return;
	}
	r_buffer = r_buffer.slice(p_count);
}

// How the blank line that ends the header block is terminated. HTTP/1.1
// mandates CRLF, so the bare LF form is not a mere parsing detail: reporting it
// as "not complete yet" is what used to leave a client waiting for the 30 s
// idle timeout with no answer at all (GDR-12.3).
enum class HeaderEndKind {
	NONE,
	CRLF,
	BARE_LF,
};

struct HeaderEnd {
	HeaderEndKind kind = HeaderEndKind::NONE;
	// Number of bytes up to and including that blank line, so `end - 4` is the
	// offset the CRLF-only scan used to return.
	int end = -1;
};

static HeaderEnd _find_header_end(const Vector<uint8_t> &p_buffer) {
	HeaderEnd result;
	int line_start = 0;
	const int size = p_buffer.size();
	for (int i = 0; i < size; i++) {
		if (p_buffer[i] != '\n') {
			continue;
		}
		const bool crlf = i > line_start && p_buffer[i - 1] == '\r';
		const int line_end = crlf ? i - 1 : i;
		if (line_end == line_start) {
			// A blank line terminates the header block.
			result.end = i + 1;
			result.kind = crlf ? HeaderEndKind::CRLF : HeaderEndKind::BARE_LF;
			return result;
		}
		line_start = i + 1;
	}
	return result;
}

static String _buffer_to_string(const Vector<uint8_t> &p_buffer, int p_offset, int p_length) {
	if (p_length <= 0) {
		return String();
	}
	return String::utf8((const char *)p_buffer.ptr() + p_offset, p_length);
}

static String _error_body(const String &p_message) {
	Dictionary body;
	body["error"] = p_message;
	return JSON::stringify(body);
}

bool is_valid_utf8(const uint8_t *p_bytes, int p_length) {
	int i = 0;
	while (i < p_length) {
		const uint8_t lead = p_bytes[i];
		int trailing = 0;
		uint32_t code_point = 0;
		if (lead < 0x80) {
			i++;
			continue;
		} else if ((lead & 0xE0) == 0xC0) {
			trailing = 1;
			code_point = lead & 0x1F;
		} else if ((lead & 0xF0) == 0xE0) {
			trailing = 2;
			code_point = lead & 0x0F;
		} else if ((lead & 0xF8) == 0xF0) {
			trailing = 3;
			code_point = lead & 0x07;
		} else {
			// 0x80..0xBF continuation bytes and 0xF8..0xFF can never lead.
			return false;
		}

		if (i + trailing >= p_length) {
			return false;
		}
		for (int j = 1; j <= trailing; j++) {
			const uint8_t continuation = p_bytes[i + j];
			if ((continuation & 0xC0) != 0x80) {
				return false;
			}
			code_point = (code_point << 6) | (continuation & 0x3F);
		}

		// Sequences that decode to *a* value but are still invalid: overlong
		// encodings, UTF-16 surrogates and code points beyond U+10FFFF.
		if (trailing == 1 && code_point < 0x80) {
			return false;
		}
		if (trailing == 2 && code_point < 0x800) {
			return false;
		}
		if (trailing == 3 && code_point < 0x10000) {
			return false;
		}
		if (code_point > 0x10FFFF) {
			return false;
		}
		if (code_point >= 0xD800 && code_point <= 0xDFFF) {
			return false;
		}
		i += trailing + 1;
	}
	return true;
}

ParseOutcome parse_request(Vector<uint8_t> &r_buffer, int p_max_body_bytes, int p_max_header_bytes) {
	ParseOutcome outcome;
	if (r_buffer.is_empty()) {
		return outcome;
	}

	const HeaderEnd header = _find_header_end(r_buffer);
	if (header.kind == HeaderEndKind::NONE) {
		// The header block is not complete yet. Refuse to buffer an unbounded
		// amount of garbage (a slowloris style request never reaches this size
		// with a legitimate header block).
		if (r_buffer.size() > p_max_header_bytes) {
			outcome.status = ParseStatus::HEADER_TOO_LARGE;
			r_buffer.clear();
		}
		return outcome;
	}
	if (header.kind == HeaderEndKind::BARE_LF) {
		// A complete header block that ends with a bare LF is malformed, not
		// incomplete: answer 400 now instead of stalling until the idle
		// timeout (GDR-12.3).
		outcome.status = ParseStatus::BARE_LF_LINE_ENDING;
		r_buffer.clear();
		return outcome;
	}
	const int header_end = header.end - 4;
	if (header_end > p_max_header_bytes) {
		outcome.status = ParseStatus::HEADER_TOO_LARGE;
		r_buffer.clear();
		return outcome;
	}

	const String header_text = _buffer_to_string(r_buffer, 0, header_end);
	const PackedStringArray lines = header_text.split("\r\n");
	if (lines.size() == 0 || lines[0].is_empty()) {
		outcome.status = ParseStatus::BAD_REQUEST_LINE;
		r_buffer.clear();
		return outcome;
	}

	const PackedStringArray request_line = lines[0].split_spaces();
	if (request_line.size() != 3) {
		outcome.status = ParseStatus::BAD_REQUEST_LINE;
		r_buffer.clear();
		return outcome;
	}

	const String method = request_line[0].to_upper();
	const String path = request_line[1];
	const String version = request_line[2];
	if (!version.begins_with("HTTP/1.")) {
		outcome.status = ParseStatus::UNSUPPORTED_VERSION;
		r_buffer.clear();
		return outcome;
	}

	bool keep_alive = version == "HTTP/1.1";
	bool has_content_length = false;
	bool invalid_content_length = false;
	bool has_expect_continue = false;
	int content_length = 0;

	const int line_count = lines.size();
	for (int i = 1; i < line_count; i++) {
		const String line = lines[i];
		if (line.is_empty()) {
			continue;
		}
		const int colon = line.find(":");
		if (colon <= 0) {
			outcome.status = ParseStatus::BAD_REQUEST_LINE;
			r_buffer.clear();
			return outcome;
		}
		const String key = line.substr(0, colon).strip_edges().to_lower();
		const String value = line.substr(colon + 1).strip_edges();
		if (key == "content-length") {
			if (value.is_valid_int()) {
				const int parsed = value.to_int();
				if (parsed < 0 || parsed > 1024 * 1024 * 1024) {
					invalid_content_length = true;
				} else {
					content_length = parsed;
					has_content_length = true;
				}
			} else {
				invalid_content_length = true;
			}
		} else if (key == "connection") {
			const String connection_value = value.to_lower();
			if (connection_value == "close") {
				keep_alive = false;
			} else if (connection_value == "keep-alive") {
				keep_alive = true;
			}
		} else if (key == "expect") {
			// `Transfer-Encoding`, `Expect` and friends are deliberately not
			// modelled beyond what the transport actually honours: chunked
			// bodies stay unsupported (D33) and an `Expect: 100-continue` only
			// triggers the interim response below.
			if (value.to_lower() == "100-continue") {
				has_expect_continue = true;
			}
		}
	}

	if (invalid_content_length) {
		outcome.status = ParseStatus::INVALID_CONTENT_LENGTH;
		r_buffer.clear();
		return outcome;
	}

	const bool body_expected = method == "POST" || method == "PUT" || method == "PATCH";
	if (!has_content_length) {
		if (body_expected) {
			outcome.status = ParseStatus::MISSING_CONTENT_LENGTH;
			r_buffer.clear();
			return outcome;
		}
		content_length = 0;
	}

	if (p_max_body_bytes >= 0 && content_length > p_max_body_bytes) {
		outcome.status = ParseStatus::BODY_TOO_LARGE;
		r_buffer.clear();
		return outcome;
	}

	const int total = header_end + 4 + content_length;
	if (r_buffer.size() < total) {
		// Body still in flight: leave the buffer untouched so that the rest of
		// the request can be appended and parsed later. A peer that announced
		// `Expect: 100-continue` is waiting for the interim response before it
		// sends that body, so the transport has to be told to answer now.
		outcome.expect_continue = has_expect_continue && content_length > 0;
		return outcome;
	}

	outcome.status = ParseStatus::COMPLETE;
	outcome.request.method = method;
	outcome.request.path = path;
	outcome.request.version = version;
	outcome.request.keep_alive = keep_alive;
	const int body_offset = header_end + 4;
	outcome.request.body = _buffer_to_string(r_buffer, body_offset, content_length);
	// `String::utf8` silently replaces invalid sequences with U+FFFD and the
	// body is deliberately still accepted (the client contract is UTF-8, no
	// strict path is added - GDR-12.4). The substitution must not be silent
	// though: flag it and report the original byte length so that a violation
	// of that contract is visible in a `--verbose` run instead of surfacing as
	// mysteriously mangled JSON.
	if (content_length > 0 && !is_valid_utf8(r_buffer.ptr() + body_offset, content_length)) {
		outcome.body_invalid_utf8 = true;
		print_verbose(vformat("[MCP] request body is not valid UTF-8 (%d bytes); invalid sequences replaced with U+FFFD", content_length));
	}
	_consume_bytes(r_buffer, total);
	return outcome;
}

int status_code_for(ParseStatus p_status) {
	switch (p_status) {
		case ParseStatus::COMPLETE:
			return 200;
		case ParseStatus::NEED_MORE:
			return 0;
		case ParseStatus::MISSING_CONTENT_LENGTH:
			return 411;
		case ParseStatus::BODY_TOO_LARGE:
			return 413;
		case ParseStatus::HEADER_TOO_LARGE:
			// Semantically this is not a generic bad request: the reason phrase
			// for 431 was already defined but unreachable (GDR-12.2).
			return 431;
		case ParseStatus::BARE_LF_LINE_ENDING:
		case ParseStatus::BAD_REQUEST_LINE:
		case ParseStatus::UNSUPPORTED_VERSION:
		case ParseStatus::INVALID_CONTENT_LENGTH:
		default:
			return 400;
	}
}

String reason_phrase(int p_status) {
	switch (p_status) {
		case 200:
			return "OK";
		case 202:
			return "Accepted";
		case 204:
			return "No Content";
		case 400:
			return "Bad Request";
		case 404:
			return "Not Found";
		case 405:
			return "Method Not Allowed";
		case 411:
			return "Length Required";
		case 413:
			return "Payload Too Large";
		case 415:
			return "Unsupported Media Type";
		case 431:
			return "Request Header Fields Too Large";
		case 500:
			return "Internal Server Error";
		case 503:
			return "Service Unavailable";
		default:
			return "Error";
	}
}

String build_continue_response() {
	// Interim responses carry no body and therefore no `Content-Length` or
	// `Content-Type` (RFC 9110 section 15.2). The terminating empty line ends
	// the interim response, after which the final response follows.
	return "HTTP/1.1 100 Continue\r\n\r\n";
}

bool is_idle_timeout(uint64_t p_now_ms, uint64_t p_last_activity_ms, uint64_t p_idle_ms) {
	if (p_idle_ms == 0) {
		return false;
	}
	if (p_now_ms <= p_last_activity_ms) {
		// Activity was seen at (or after) the frame clock, so the connection is
		// not idle. Subtracting here would wrap around.
		return false;
	}
	return (p_now_ms - p_last_activity_ms) > p_idle_ms;
}

String build_response(int p_status, const String &p_body, bool p_keep_alive) {
	const CharString body_utf8 = p_body.utf8();
	const String head = vformat("HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nConnection: %s\r\n\r\n",
			p_status, reason_phrase(p_status), body_utf8.length(), p_keep_alive ? "keep-alive" : "close");
	return head + p_body;
}

} // namespace MCPHttp

MCPHttpServer::MCPHttpServer() {}

MCPHttpServer::~MCPHttpServer() {
	stop();
}

Error MCPHttpServer::listen(uint16_t p_port, const String &p_bind_address) {
	stop();

	tcp_server.instantiate();
	const Error err = tcp_server->listen(p_port, IPAddress(p_bind_address));
	if (err != OK) {
		tcp_server.unref();
		return err;
	}

	listening = true;
	port = p_port;
	return OK;
}

void MCPHttpServer::stop() {
	for (int i = 0; i < connections.size(); i++) {
		memdelete(connections[i]);
	}
	connections.clear();

	// Every adopted task dies with the server; a task is owned by exactly one
	// place (the pending table) and this is that place's release.
	pending_requests.clear();

	if (tcp_server.is_valid()) {
		tcp_server->stop();
		tcp_server.unref();
	}

	listening = false;
	port = 0;
}

void MCPHttpServer::_drop_connection(int p_index) {
	// The single point where a connection's deferred requests are released
	// (GDR-20 point 5). Because `Queue` is keyed by connection id, this is a
	// one-call, complete cleanup: there is no other place a pending entry for
	// this connection can live, so a leak is not expressible.
	//
	// TASK-092 (item B2): the released entries' records come back so the capture
	// slots they armed can be released too. A request nobody will ever answer has
	// no line to carry a capture verdict, but its `before` frame must not stay in
	// memory until the process exits.
	Vector<MCPTrace::Record> dropped;
	pending_requests.drop_connection(connections[p_index]->id, &dropped);
	if (sink != nullptr) {
		for (int i = 0; i < dropped.size(); i++) {
			if (dropped[i].capture_token >= 0) {
				sink->discard_deferred_capture(dropped[i].capture_token);
			}
		}
	}
	memdelete(connections[p_index]);
	connections.remove_at(p_index);
}

int MCPHttpServer::_find_connection(uint64_t p_connection_id) const {
	for (int i = 0; i < connections.size(); i++) {
		if (connections[i]->id == p_connection_id) {
			return i;
		}
	}
	return -1;
}

void MCPHttpServer::_tick_pending(int64_t p_frame, uint64_t p_now) {
	if (pending_requests.get_pending_count() == 0) {
		return;
	}

	Vector<MCPDeferred::Completion> completions;
	pending_requests.tick(p_frame, p_now, pending_ticks_per_frame, completions);

	for (int i = 0; i < completions.size(); i++) {
		const MCPDeferred::Completion &completion = completions[i];
		const int index = _find_connection(completion.connection_id);
		if (index < 0) {
			// Unreachable by construction (dropping a connection releases its
			// entries), but a stale write is worse than a lost one. TASK-092
			// (item B2): a capture armed for this request has no line left to be
			// reported on, so its slot is released here rather than kept armed.
			if (sink != nullptr && completion.trace.capture_token >= 0) {
				sink->discard_deferred_capture(completion.trace.capture_token);
			}
			print_verbose(vformat("[MCP] deferred completion for unknown connection %d dropped",
					(int64_t)completion.connection_id));
			continue;
		}
		Connection *connection = connections[index];
		const String body = sink != nullptr ? sink->build_deferred_body(completion) : MCPHttp::_error_body("Service Unavailable");
		// A JSON-RPC level failure (including the timeout) is still an HTTP
		// 200 with an `error` member, exactly like every immediate tool error of
		// this module (GDR-6): the transport succeeded, the call did not.
		_queue_response(connection, 200, body, completion.keep_alive);
		// TASK-038: the deferred request is written to the trace here, where it
		// really ended - with the code the timeout or the tool produced and with
		// the time the client actually waited.
		if (trace != nullptr && trace->is_active() && completion.trace.traceable) {
			MCPTrace::Record record = completion.trace;
			record.result_bytes = body.utf8().length();
			// TASK-092 (item B2): the file-side verdict the deferred queue
			// accumulated across every frame the call's task ran in. It replaces
			// the `not_tracked_deferred` placeholder the dispatcher put on the
			// record - that placeholder now survives only when no completion was
			// ever produced for the request.
			if (!completion.file_effect_status.is_empty()) {
				record.file_effect_status = completion.file_effect_status;
				record.file_effects = completion.file_effects;
			}
			if (completion.kind == MCPDeferred::CompletionKind::DONE) {
				record.ok = true;
				record.error_code = 0;
				record.error_message = String();
				record.error_data_json = String();
				record.error_data_bytes = 0;
				// TASK-090 (item C): the tool's own body, on the deferred call
				// line too. The TASK-089 half of this field was filled only on
				// the immediate path, so every deferred call - the scenario and
				// stress drivers above all - carried `result_bytes` and nothing
				// else, and their own verdicts (`all_passed`, `passed`) were
				// unreadable from the trace. `completion.result` is the same
				// Variant the immediate path stringifies (`build_deferred_body`
				// wraps it with the same `content_result`), so the two lines
				// carry the same bytes.
				// [REBUILT-2C low-confidence: verify] TASK-090 item C: written,
				// not replayed; REBUILT-2C-MANIFEST.md 2c-9 (J-3).
				record.result_json = JSON::stringify(completion.result);
				record.result_json_bytes = record.result_json.utf8().length();
				// [/REBUILT-2C]
			} else {
				record.ok = false;
				record.error_code = completion.error.code;
				record.error_message = completion.error.message;
				// TASK-090 (item A): a deferred failure carries the same
				// machine-readable payload an immediate one does (`suggestion`,
				// `timeout_ms`), and it has to reach the line by the same rule -
				// an empty string when there is nothing attached.
				// [REBUILT-2C low-confidence: verify] TASK-090 item A: written,
				// not replayed; REBUILT-2C-MANIFEST.md 2c-9 (J-1).
				if (completion.error.data.get_type() == Variant::NIL) {
					record.error_data_json = String();
					record.error_data_bytes = 0;
				} else {
					record.error_data_json = JSON::stringify(completion.error.data);
					record.error_data_bytes = record.error_data_json.utf8().length();
				}
				// [/REBUILT-2C]
			}
			const uint64_t finished = OS::get_singleton()->get_ticks_msec();
			const uint64_t waited = (finished > completion.start_ms) ? finished - completion.start_ms : 0;
			// TASK-092 (item B2): the capture of a deferred call is finished
			// **here**, where the call really ended - the `before` frame was
			// taken when the request was read, the `after` frame is taken one
			// rendered frame after this one, and the pixel difference between them
			// is the deferred call's own effect on the screen. The `seq` handed in
			// is the one the line below is about to be written with, which is what
			// pairs the call line with its capture line.
			if (record.capture_token >= 0 && sink != nullptr) {
				sink->finish_deferred_capture(record, trace->get_seq() + 1);
			}
			// A deferred call spends its whole duration in the pending channel, so
			// the two wall times of the line are the same measurement; they are
			// both reported because `pending_ms` is what an observer compares
			// against the configured ceiling.
			trace->record(completion.connection_id, record, waited, waited);
		}
		// The wait was activity: a connection that is waiting for a later frame
		// is not idle, and the response just queued is a fresh reason to keep it.
		connection->last_activity_ms = p_now;
		if (!completion.keep_alive) {
			connection->close_after_flush = true;
			connection->close_reason = 2;
		}
	}
}

bool MCPHttpServer::_flush(Connection *p_connection) {
	Connection &connection = *p_connection;
	if (connection.write_offset >= connection.out_buffer.size()) {
		connection.out_buffer.clear();
		connection.write_offset = 0;
		return true;
	}

	const int pending = connection.out_buffer.size() - connection.write_offset;
	int sent = 0;
	const Error err = connection.peer->put_partial_data(connection.out_buffer.ptr() + connection.write_offset, pending, sent);
	if (err != OK && sent <= 0) {
		connection.reading_failed = true;
		return false;
	}
	connection.write_offset += sent;

	if (connection.write_offset >= connection.out_buffer.size()) {
		connection.out_buffer.clear();
		connection.write_offset = 0;
		return true;
	}

	// Compact occasionally so that a long lived connection does not keep the
	// already flushed prefix around forever.
	if (connection.write_offset > 65536) {
		connection.out_buffer = connection.out_buffer.slice(connection.write_offset);
		connection.write_offset = 0;
	}
	return false;
}

void MCPHttpServer::_read(Connection *p_connection, uint64_t p_now) {
	Connection &connection = *p_connection;

	// `get_status()` only reflects what the last poll observed, so a peer that
	// went away without sending anything (FIN or RST) would otherwise stay in
	// the connection table until the idle timeout and permanently eat into the
	// connection budget. Polling here makes the socket state authoritative:
	// `StreamPeerSocket::poll()` detects FIN (a readable socket with zero
	// available bytes) and real errors.
	connection.peer->poll();
	if (connection.peer->get_status() != StreamPeerSocket::STATUS_CONNECTED) {
		connection.reading_failed = true;
		return;
	}

	const int available = connection.peer->get_available_bytes();
	if (available <= 0) {
		return;
	}

	Vector<uint8_t> chunk;
	chunk.resize(available);
	int received = 0;
	const Error err = connection.peer->get_partial_data(chunk.ptrw(), available, received);
	if (received <= 0) {
		if (err != OK) {
			connection.reading_failed = true;
		}
		return;
	}

	for (int i = 0; i < received; i++) {
		connection.in_buffer.push_back(chunk[i]);
	}
	// Stamp the activity with the clock of this frame instead of reading
	// `get_ticks_msec()` a second time: that second reading is usually a few
	// ticks later than `p_now`, and an activity stamp that is newer than the
	// frame clock made the idle check underflow (see is_idle_timeout).
	connection.last_activity_ms = p_now;
}

void MCPHttpServer::_queue_bytes(Connection *p_connection, const String &p_text) {
	// Everything a connection will ever send is appended to that connection's
	// own output buffer, never to a shared queue.
	const CharString utf8 = p_text.utf8();
	Connection &connection = *p_connection;
	for (int i = 0; i < utf8.length(); i++) {
		connection.out_buffer.push_back((uint8_t)utf8[i]);
	}
}

void MCPHttpServer::_queue_response(Connection *p_connection, int p_status, const String &p_body, bool p_keep_alive) {
	// The response is appended to the output buffer of the very connection the
	// request was read from. No other connection can observe or steal it.
	_queue_bytes(p_connection, MCPHttp::build_response(p_status, p_body, p_keep_alive));
}

void MCPHttpServer::_queue_continue(Connection *p_connection) {
	// Interim response for a peer that announced `Expect: 100-continue` (D33):
	// without it curl stalls for about a second on bodies over 1 KiB and strict
	// clients give up. Appending it to the connection's own buffer keeps the
	// ordering with the final response intact.
	_queue_bytes(p_connection, MCPHttp::build_continue_response());
}

void MCPHttpServer::_handle_request(Connection *p_connection, const MCPHttp::Request &p_request, int64_t p_frame, uint64_t p_now) {
	String path = p_request.path;
	const int query = path.find("?");
	if (query >= 0) {
		path = path.substr(0, query);
	}

	if (path != "/mcp") {
		_queue_response(p_connection, 404, MCPHttp::_error_body("Not Found"), false);
		p_connection->close_after_flush = true;
		p_connection->close_reason = 1;
		return;
	}

	if (p_request.method == "POST") {
		// TASK-038: the trace observes the call from the outside. `started` is
		// only read when a recorder is open, so a process without
		// `--mcp-trace` performs exactly the work it performed before.
		const bool tracing = trace != nullptr && trace->is_active();
		const uint64_t started = tracing ? OS::get_singleton()->get_ticks_msec() : 0;

		MCPHttpOutcome outcome;
		if (sink != nullptr) {
			sink->handle_jsonrpc_request(p_request.body, outcome);
		} else {
			outcome.http_status = 503;
			outcome.body = MCPHttp::_error_body("Service Unavailable");
		}

		if (outcome.deferred && outcome.task != nullptr) {
			// No response is queued now. The request is parked in the pending
			// table under (this connection, this request id) and the response is
			// written to *this* connection's own buffer when it completes
			// (GDR-20 points 1/2). TASK-038: the trace travels with the entry, so
			// its line is written from the completion and not from here.
			pending_requests.add(p_connection->id, outcome.id_json, outcome.task, outcome.timeout_ms,
					p_request.keep_alive, p_frame, p_now, outcome.trace, started);
			print_verbose(vformat("[MCP] deferred request id=%s on connection %d (pending=%d, timeout_ms=%d)",
					outcome.id_json, (int64_t)p_connection->id, pending_requests.get_pending_count(),
					(int64_t)outcome.timeout_ms));
			return;
		}

		const bool keep_alive = p_request.keep_alive && !outcome.close;
		_queue_response(p_connection, outcome.http_status, outcome.body, keep_alive);
		if (tracing && outcome.trace.traceable) {
			MCPTrace::Record record = outcome.trace;
			record.result_bytes = outcome.body.utf8().length();
			const uint64_t finished = OS::get_singleton()->get_ticks_msec();
			trace->record(p_connection->id, record, (finished > started) ? finished - started : 0, 0);
		}
		if (!keep_alive) {
			p_connection->close_after_flush = true;
			p_connection->close_reason = 2;
		}
		return;
	}

	if (p_request.method == "GET") {
		const String body = sink != nullptr ? sink->get_status_body() : MCPHttp::_error_body("Service Unavailable");
		_queue_response(p_connection, 200, body, p_request.keep_alive);
		if (!p_request.keep_alive) {
			p_connection->close_after_flush = true;
			p_connection->close_reason = 2;
		}
		return;
	}

	_queue_response(p_connection, 405, MCPHttp::_error_body("Method Not Allowed"), p_request.keep_alive);
	if (!p_request.keep_alive) {
		p_connection->close_after_flush = true;
		p_connection->close_reason = 2;
	}
}

void MCPHttpServer::poll(int p_max_requests, int64_t p_frame) {
	if (!listening || tcp_server.is_null()) {
		return;
	}

	const uint64_t now = OS::get_singleton()->get_ticks_msec();

	// Accept new connections, refusing anything beyond the hard cap.
	while (tcp_server->is_connection_available()) {
		const Ref<StreamPeerTCP> peer = tcp_server->take_connection();
		if (peer.is_null()) {
			continue;
		}
		if ((int)connections.size() >= max_connections) {
			peer->disconnect_from_host();
			continue;
		}
		peer->set_no_delay(true);
		Connection *connection = memnew(Connection);
		connection->id = next_connection_id++;
		connection->peer = peer;
		connection->last_activity_ms = now;
		connections.push_back(connection);
	}

	const uint64_t idle_ms = connection_idle_seconds > 0.0 ? (uint64_t)(connection_idle_seconds * 1000.0) : 0;
	const int in_buffer_cap = max_body_bytes + MCPHttp::MAX_HEADER_BYTES * 2;

	int processed = 0;
	int i = 0;
	while (i < connections.size()) {
		Connection *connection = connections[i];
		bool drop = false;

		_flush(connection);
		if (connection->reading_failed) {
			drop = true;
		}

		if (!drop) {
			_read(connection, now);
			if (connection->reading_failed) {
				drop = true;
			}
		}

		if (!drop) {
			// HTTP/1.1 requires responses in request order on one connection. A
			// deferred request has no response yet, so the request stream of
			// *that* connection is held back until it resolves: the bytes stay
			// in `in_buffer` and are dispatched later. This is deliberately not
			// a response queue - nothing is paired by arrival order, and other
			// connections are completely unaffected (GDR-20 point 1).
			while (processed < p_max_requests && !pending_requests.has_connection(connection->id)) {
				const int prior_size = connection->in_buffer.size();
				const MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(connection->in_buffer, max_body_bytes);
				if (outcome.status == MCPHttp::ParseStatus::NEED_MORE) {
					if (outcome.expect_continue && !connection->continue_sent) {
						connection->continue_sent = true;
						_queue_continue(connection);
						// Send it within this frame: the peer is blocked on it.
						_flush(connection);
						if (connection->reading_failed) {
							drop = true;
						}
					}
					break;
				}
				// A complete request ends the interim bookkeeping; anything the
				// connection pipelines next starts from scratch.
				connection->continue_sent = false;
				processed++;
				if (outcome.status != MCPHttp::ParseStatus::COMPLETE) {
					const int status = MCPHttp::status_code_for(outcome.status);
					print_verbose(vformat("[MCP] framing error %d -> HTTP %d on connection %d (buffer was %d bytes)",
							(int)outcome.status, status, i, prior_size));
					_queue_response(connection, status, MCPHttp::_error_body(MCPHttp::reason_phrase(status)), false);
					connection->close_after_flush = true;
					connection->close_reason = 3;
					break;
				}
				_handle_request(connection, outcome.request, p_frame, now);
				if (connection->close_after_flush) {
					break;
				}
			}

			if (connection->in_buffer.size() > in_buffer_cap) {
				connection->close_after_flush = true;
				connection->close_reason = 4;
			}
			// A connection waiting for a later frame is not idle: the pending
			// request is the activity, and closing it here would turn a
			// configured timeout into a bare connection reset - the client would
			// never receive the `-32000` GDR-20 point 4 requires.
			if (!connection->close_after_flush && !pending_requests.has_connection(connection->id) &&
					MCPHttp::is_idle_timeout(now, connection->last_activity_ms, idle_ms)) {
				connection->close_after_flush = true;
				connection->close_reason = 5;
			}
		}

		if (!drop && connection->close_after_flush) {
			_flush(connection);
			if (connection->write_offset >= connection->out_buffer.size() || connection->reading_failed) {
				drop = true;
			}
		}

		if (drop) {
			print_verbose(vformat("[MCP] dropping connection %d (read_failed=%s, reason=%d, idle_ms=%d, in_buffer=%d, out_buffer=%d)",
					i, connection->reading_failed ? "true" : "false", connection->close_reason,
					(int)(now >= connection->last_activity_ms ? now - connection->last_activity_ms : 0),
					connection->in_buffer.size(), connection->out_buffer.size()));
			if (connection->peer.is_valid()) {
				connection->peer->disconnect_from_host();
			}
			_drop_connection(i);
		} else {
			i++;
		}
	}

	// Deferred phase: advance at most `pending_ticks_per_frame` tasks. It runs
	// *after* the request phase above, so a frame always dispatches the ordinary
	// requests first and the budget can never delay them (GDR-20 point 4).
	_tick_pending(p_frame, now);

	// Flush what the deferred phase queued, and reap a connection whose peer
	// went away while its response was being written.
	for (int j = 0; j < connections.size();) {
		Connection *connection = connections[j];
		if (!connection->close_after_flush && connection->out_buffer.is_empty()) {
			j++;
			continue;
		}
		_flush(connection);
		const bool flushed = connection->write_offset >= connection->out_buffer.size();
		if (connection->reading_failed || (connection->close_after_flush && flushed)) {
			print_verbose(vformat("[MCP] closing connection %d after flushing a deferred response (reason=%d)",
					j, connection->close_reason));
			if (connection->peer.is_valid()) {
				connection->peer->disconnect_from_host();
			}
			_drop_connection(j);
			continue;
		}
		j++;
	}
}