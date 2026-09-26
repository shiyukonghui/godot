/**************************************************************************/
/*  test_mcp_server.h                                                     */
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

#include "../mcp_http_server.h"
#include "../mcp_jsonrpc.h"
#include "../mcp_server.h"
#include "../tool_registry.h"
#include "../tools/tool_builder.h"

#include "core/io/json.h"
#include "core/variant/variant.h"
#include "tests/test_macros.h"

namespace TestMCPServer {

Vector<uint8_t> to_bytes(const String &p_text);
Variant parse_json(const String &p_text);
String canonical(const Variant &p_value);

// A handler that only ever fails: the tool-builder tests need a complete
// declaration without exercising real behaviour.
Variant unused_handler(const Dictionary &p_args, MCPToolError &r_error);

// Registry holding the six B1 template tools exactly as
// `tools/project_read_template.cpp` defines them.
void build_project_registry(MCPToolRegistry &r_registry);
// Registry built through the shared `register_all_tools()` entry point.
void build_all_tools_registry(MCPToolRegistry &r_registry);
// Registry with one editor-only, one game-only and one both-scope tool.
void build_scope_registry(MCPToolRegistry &r_registry);
// Registry with a -32001 probe and a -32000 probe, to observe the tool error
// mapping of the JSON-RPC layer without touching the file system.
void build_error_probe_registry(MCPToolRegistry &r_registry);

} // namespace TestMCPServer

// ---------------------------------------------------------------------------
// HTTP/1.1 framing (GDR-5)
// ---------------------------------------------------------------------------

TEST_CASE("[MCPServer] HTTP parses request line, headers and body") {
	Vector<uint8_t> buffer = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:9888\r\nContent-Length: 2\r\nContent-Type: application/json\r\n\r\n{}");

	MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(buffer, 1024);
	CHECK(outcome.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK(outcome.request.method == "POST");
	CHECK(outcome.request.path == "/mcp");
	CHECK(outcome.request.version == "HTTP/1.1");
	CHECK(outcome.request.body == "{}");
	CHECK(outcome.request.keep_alive);
	// The request must be consumed exactly.
	CHECK(buffer.is_empty());
}

TEST_CASE("[MCPServer] HTTP header names are case insensitive") {
	Vector<uint8_t> buffer = TestMCPServer::to_bytes("post /mcp HTTP/1.1\r\nhost: x\r\ncontent-LENGTH: 7\r\n\r\n{\"a\":1}");

	MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(buffer, 1024);
	CHECK(outcome.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK(outcome.request.method == "POST");
	CHECK(outcome.request.body == "{\"a\":1}");
}

TEST_CASE("[MCPServer] HTTP connection close is honoured") {
	Vector<uint8_t> buffer = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}");

	MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(buffer, 1024);
	CHECK(outcome.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK_FALSE(outcome.request.keep_alive);
}

TEST_CASE("[MCPServer] HTTP half packet is buffered until complete") {
	// Half 1: header and part of the body.
	Vector<uint8_t> buffer = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\n\r\n{");
	CHECK(MCPHttp::parse_request(buffer, 1024).status == MCPHttp::ParseStatus::NEED_MORE);
	// The partial request must not be consumed.
	int size_before = buffer.size();
	CHECK(MCPHttp::parse_request(buffer, 1024).status == MCPHttp::ParseStatus::NEED_MORE);
	CHECK(buffer.size() == size_before);

	// Half 2: the rest of the body.
	Vector<uint8_t> rest = TestMCPServer::to_bytes("}");
	buffer.append_array(rest);
	MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(buffer, 1024);
	CHECK(outcome.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK(outcome.request.body == "{}");
	CHECK(buffer.is_empty());
}

TEST_CASE("[MCPServer] HTTP header split mid line is buffered") {
	Vector<uint8_t> buffer = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nContent-Len");
	CHECK(MCPHttp::parse_request(buffer, 1024).status == MCPHttp::ParseStatus::NEED_MORE);

	Vector<uint8_t> rest = TestMCPServer::to_bytes("gth: 2\r\n\r\n{}");
	buffer.append_array(rest);
	MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(buffer, 1024);
	CHECK(outcome.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK(outcome.request.body == "{}");
}

TEST_CASE("[MCPServer] HTTP keep-alive two requests in one buffer") {
	Vector<uint8_t> buffer = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nContent-Length: 8\r\n\r\n{\"id\":1}POST /mcp HTTP/1.1\r\nContent-Length: 8\r\n\r\n{\"id\":2}");

	MCPHttp::ParseOutcome first = MCPHttp::parse_request(buffer, 1024);
	CHECK(first.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK(first.request.body == "{\"id\":1}");

	MCPHttp::ParseOutcome second = MCPHttp::parse_request(buffer, 1024);
	CHECK(second.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK(second.request.body == "{\"id\":2}");

	MCPHttp::ParseOutcome third = MCPHttp::parse_request(buffer, 1024);
	CHECK(third.status == MCPHttp::ParseStatus::NEED_MORE);
	CHECK(buffer.is_empty());
}

TEST_CASE("[MCPServer] HTTP missing Content-Length") {
	// A POST always carries a body, so the header is mandatory.
	Vector<uint8_t> buffer = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
	CHECK(MCPHttp::parse_request(buffer, 1024).status == MCPHttp::ParseStatus::MISSING_CONTENT_LENGTH);
	CHECK(MCPHttp::status_code_for(MCPHttp::ParseStatus::MISSING_CONTENT_LENGTH) == 411);

	// A GET without a body does not need one.
	Vector<uint8_t> get_buffer = TestMCPServer::to_bytes("GET /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");
	MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(get_buffer, 1024);
	CHECK(outcome.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK(outcome.request.method == "GET");
	CHECK(outcome.request.body.is_empty());
}

TEST_CASE("[MCPServer] HTTP invalid Content-Length") {
	Vector<uint8_t> buffer = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nContent-Length: abc\r\n\r\n");
	CHECK(MCPHttp::parse_request(buffer, 1024).status == MCPHttp::ParseStatus::INVALID_CONTENT_LENGTH);
	CHECK(MCPHttp::status_code_for(MCPHttp::ParseStatus::INVALID_CONTENT_LENGTH) == 400);
}

TEST_CASE("[MCPServer] HTTP body over the limit is rejected with 413") {
	// The declared length alone is enough to reject; the body is never read.
	Vector<uint8_t> buffer = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nContent-Length: 4096\r\n\r\n");
	CHECK(MCPHttp::parse_request(buffer, 1024).status == MCPHttp::ParseStatus::BODY_TOO_LARGE);
	CHECK(MCPHttp::status_code_for(MCPHttp::ParseStatus::BODY_TOO_LARGE) == 413);
	CHECK(buffer.is_empty());

	// Exactly at the limit is accepted.
	Vector<uint8_t> accepted = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}");
	CHECK(MCPHttp::parse_request(accepted, 2).status == MCPHttp::ParseStatus::COMPLETE);
}

TEST_CASE("[MCPServer] HTTP malformed request line and oversized header") {
	Vector<uint8_t> malformed = TestMCPServer::to_bytes("GARBAGE\r\n\r\n");
	CHECK(MCPHttp::parse_request(malformed, 1024).status == MCPHttp::ParseStatus::BAD_REQUEST_LINE);
	CHECK(MCPHttp::status_code_for(MCPHttp::ParseStatus::BAD_REQUEST_LINE) == 400);

	Vector<uint8_t> bad_version = TestMCPServer::to_bytes("POST /mcp HTTP/9.9\r\nContent-Length: 2\r\n\r\n{}");
	CHECK(MCPHttp::parse_request(bad_version, 1024).status == MCPHttp::ParseStatus::UNSUPPORTED_VERSION);

	String long_header = "POST /mcp HTTP/1.1\r\n";
	for (int i = 0; i < 400; i++) {
		long_header += "X-Pad: 0123456789012345678901234567890123456789\r\n";
	}
	Vector<uint8_t> oversized = TestMCPServer::to_bytes(long_header);
	CHECK(MCPHttp::parse_request(oversized, 1024).status == MCPHttp::ParseStatus::HEADER_TOO_LARGE);
}

TEST_CASE("[MCPServer] HTTP oversized header is 431, not 400") {
	// GDR-12.2: a header block over the 8 KiB cap is `431 Request Header Fields
	// Too Large`. `reason_phrase(431)` already carried the correct string, but
	// the mapping never selected it, so the branch was dead code.
	CHECK(MCPHttp::status_code_for(MCPHttp::ParseStatus::HEADER_TOO_LARGE) == 431);
	CHECK(MCPHttp::reason_phrase(431) == "Request Header Fields Too Large");

	// The mapping has to be reachable from both oversized shapes: the announced
	// block whose blank line has arrived, and one that is still being buffered.
	String terminated = "POST /mcp HTTP/1.1\r\n";
	for (int i = 0; i < 400; i++) {
		terminated += "X-Pad: 0123456789012345678901234567890123456789\r\n";
	}
	terminated += "\r\n";
	Vector<uint8_t> with_terminator = TestMCPServer::to_bytes(terminated);
	const MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(with_terminator, 1024);
	CHECK(outcome.status == MCPHttp::ParseStatus::HEADER_TOO_LARGE);
	CHECK(MCPHttp::status_code_for(outcome.status) == 431);
	CHECK(with_terminator.is_empty());

	String unterminated = "POST /mcp HTTP/1.1\r\n";
	for (int i = 0; i < 400; i++) {
		unterminated += "X-Pad: 0123456789012345678901234567890123456789\r\n";
	}
	Vector<uint8_t> without_terminator = TestMCPServer::to_bytes(unterminated);
	CHECK(MCPHttp::parse_request(without_terminator, 1024).status == MCPHttp::ParseStatus::HEADER_TOO_LARGE);
}

TEST_CASE("[MCPServer] HTTP bare LF header terminator is rejected with 400") {
	// GDR-12.3: HTTP/1.1 requires CRLF. A peer that ends its header block with a
	// bare LF used to leave the request sitting in the input buffer until the
	// 30 s idle timeout and never got an answer at all. It must be answered
	// with 400 right away and the connection closed.
	//
	// The red form of this assertion deliberately used only symbols that
	// already existed, so that the failure was a real assertion failure instead
	// of a build error; the exact status is pinned now that it exists.
	Vector<uint8_t> buffer = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\nHost: 127.0.0.1\nContent-Length: 2\n\n{}");
	const MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(buffer, 1024);
	CHECK(outcome.status == MCPHttp::ParseStatus::BARE_LF_LINE_ENDING);
	CHECK(outcome.status != MCPHttp::ParseStatus::NEED_MORE);
	CHECK(MCPHttp::status_code_for(outcome.status) == 400);
	CHECK(buffer.is_empty());

	// Neither does the bodyless form get to wait.
	Vector<uint8_t> get_buffer = TestMCPServer::to_bytes("GET /mcp HTTP/1.1\n\n");
	const MCPHttp::ParseOutcome get_outcome = MCPHttp::parse_request(get_buffer, 1024);
	CHECK(get_outcome.status == MCPHttp::ParseStatus::BARE_LF_LINE_ENDING);
	CHECK(get_outcome.status != MCPHttp::ParseStatus::NEED_MORE);
	CHECK(MCPHttp::status_code_for(get_outcome.status) == 400);
	CHECK(get_buffer.is_empty());

	// A bare LF anywhere else in the header block cannot be split into header
	// lines either, so it is a 400 as well - what matters is that no request
	// with a bare LF is left buffered.
	Vector<uint8_t> mixed = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\nContent-Length: 2\r\n\r\n{}");
	const MCPHttp::ParseOutcome mixed_outcome = MCPHttp::parse_request(mixed, 1024);
	CHECK(mixed_outcome.status != MCPHttp::ParseStatus::NEED_MORE);
	CHECK(MCPHttp::status_code_for(mixed_outcome.status) == 400);
}

TEST_CASE("[MCPServer] HTTP invalid UTF-8 body stays accepted but is reported") {
	// GDR-12.4: the client contract is UTF-8 and a strict validation path is
	// deliberately not added, so an invalid body is still accepted. What is not
	// allowed is the current silence: `String::utf8` swaps every invalid byte
	// for U+FFFD without saying anything, so the parser has to notice the
	// substitution and hand it to the transport for a verbose warning that
	// carries the original byte length.
	//
	// The validator itself is strict RFC 3629, because "does the decoded string
	// contain U+FFFD" cannot tell a substitution apart from a legitimate
	// U+FFFD in the payload.
	CHECK(MCPHttp::is_valid_utf8((const uint8_t *)"plain ascii", 11));
	const uint8_t chinese[] = { 0xE8, 0x8E, 0xB7, 0xE5, 0x8F, 0x96 }; // 获取
	CHECK(MCPHttp::is_valid_utf8(chinese, 6));
	CHECK(MCPHttp::is_valid_utf8(nullptr, 0));
	CHECK_FALSE(MCPHttp::is_valid_utf8((const uint8_t *)"\xC3", 1)); // truncated 2 byte sequence
	CHECK_FALSE(MCPHttp::is_valid_utf8((const uint8_t *)"\xE8\x8E", 2)); // truncated 3 byte sequence
	CHECK_FALSE(MCPHttp::is_valid_utf8((const uint8_t *)"\xC0\xAF", 2)); // overlong '/'
	CHECK_FALSE(MCPHttp::is_valid_utf8((const uint8_t *)"\xED\xA0\x80", 3)); // UTF-16 surrogate
	CHECK_FALSE(MCPHttp::is_valid_utf8((const uint8_t *)"\xF4\x90\x80\x80", 4)); // beyond U+10FFFF
	CHECK_FALSE(MCPHttp::is_valid_utf8((const uint8_t *)"\xFF", 1)); // never a valid lead byte

	// A payload that is valid JSON once the offending byte has been replaced is
	// still served (loose acceptance), but the substitution is flagged.
	const Vector<uint8_t> prefix = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nContent-Length: 7\r\n\r\n");
	Vector<uint8_t> buffer = prefix;
	const uint8_t payload[] = { '{', '"', 0xFF, '"', ':', '1', '}' };
	for (int i = 0; i < 7; i++) {
		buffer.push_back(payload[i]);
	}
	const MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(buffer, 1024);
	CHECK(outcome.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK(outcome.body_invalid_utf8);
	CHECK(outcome.request.body.contains(String::chr(0xFFFD)));

	// An ASCII body is never flagged.
	Vector<uint8_t> ascii = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}");
	const MCPHttp::ParseOutcome ascii_outcome = MCPHttp::parse_request(ascii, 1024);
	CHECK(ascii_outcome.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK_FALSE(ascii_outcome.body_invalid_utf8);

	// A valid multi byte body is never flagged either.
	Vector<uint8_t> valid = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nContent-Length: 6\r\n\r\n");
	valid.append_array(chinese);
	const MCPHttp::ParseOutcome valid_outcome = MCPHttp::parse_request(valid, 1024);
	CHECK(valid_outcome.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK_FALSE(valid_outcome.body_invalid_utf8);
}

TEST_CASE("[MCPServer] HTTP response envelope is byte exact") {
	CHECK(MCPHttp::build_response(200, "{}", true) == "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nAccess-Control-Allow-Origin: *\r\nConnection: keep-alive\r\n\r\n{}");
	CHECK(MCPHttp::build_response(202, "", false) == "HTTP/1.1 202 Accepted\r\nContent-Type: application/json\r\nContent-Length: 0\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n");
	CHECK(MCPHttp::build_response(413, "nope", true) == "HTTP/1.1 413 Payload Too Large\r\nContent-Type: application/json\r\nContent-Length: 4\r\nAccess-Control-Allow-Origin: *\r\nConnection: keep-alive\r\n\r\nnope");

	CHECK(MCPHttp::reason_phrase(200) == "OK");
	CHECK(MCPHttp::reason_phrase(404) == "Not Found");
	CHECK(MCPHttp::reason_phrase(405) == "Method Not Allowed");
	CHECK(MCPHttp::reason_phrase(411) == "Length Required");
}

TEST_CASE("[MCPServer] HTTP Expect: 100-continue is detected before the body arrives") {
	// A client that announces `Expect: 100-continue` waits for the interim
	// response before it starts sending the body (curl does this for bodies
	// over 1 KiB). Without one it either stalls for a second or fails outright,
	// so the framing layer has to report that the interim step is owed.
	Vector<uint8_t> withheld = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nExpect: 100-continue\r\nContent-Length: 4\r\n\r\n");
	const MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(withheld, 1024);
	CHECK(outcome.status == MCPHttp::ParseStatus::NEED_MORE);
	CHECK(outcome.expect_continue);

	// The interim response is byte exact and must not carry Content-Type or
	// Content-Length (RFC 9110: a 100 response has no body and no headers).
	CHECK(MCPHttp::build_continue_response() == "HTTP/1.1 100 Continue\r\n\r\n");

	// Header name and expectation token are case insensitive.
	Vector<uint8_t> mixed_case = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nEXPECT: 100-Continue\r\nContent-Length: 4\r\n\r\n");
	CHECK(MCPHttp::parse_request(mixed_case, 1024).expect_continue);

	// Once the body has arrived there is nothing left to wait for.
	Vector<uint8_t> complete = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nExpect: 100-continue\r\nContent-Length: 2\r\n\r\n{}");
	const MCPHttp::ParseOutcome complete_outcome = MCPHttp::parse_request(complete, 1024);
	CHECK(complete_outcome.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK_FALSE(complete_outcome.expect_continue);

	// A zero length body is complete on the spot as well.
	Vector<uint8_t> empty = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nExpect: 100-continue\r\nContent-Length: 0\r\n\r\n");
	const MCPHttp::ParseOutcome empty_outcome = MCPHttp::parse_request(empty, 1024);
	CHECK(empty_outcome.status == MCPHttp::ParseStatus::COMPLETE);
	CHECK_FALSE(empty_outcome.expect_continue);

	// A request without the header never asks for an interim response.
	Vector<uint8_t> plain = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nContent-Length: 4\r\n\r\n");
	const MCPHttp::ParseOutcome plain_outcome = MCPHttp::parse_request(plain, 1024);
	CHECK(plain_outcome.status == MCPHttp::ParseStatus::NEED_MORE);
	CHECK_FALSE(plain_outcome.expect_continue);
}

TEST_CASE("[MCPServer] HTTP idle timeout never underflows") {
	// A connection that received data is not idle, no matter how the two
	// timestamps relate to each other.
	CHECK(MCPHttp::is_idle_timeout(100000, 40000, 30000)); // 60 s of silence
	CHECK_FALSE(MCPHttp::is_idle_timeout(100000, 90000, 30000)); // 10 s of silence
	CHECK_FALSE(MCPHttp::is_idle_timeout(40000, 40000, 30000)); // same tick

	// The activity stamp comes from a second reading of `get_ticks_msec()`, so
	// it can be newer than the frame clock. The naive `now - last_activity`
	// wraps around to ~1.8e19 ms there, which used to close live connections -
	// including ones with pipelined requests still in the input buffer.
	CHECK_FALSE(MCPHttp::is_idle_timeout(100000, 100016, 30000));
	CHECK_FALSE(MCPHttp::is_idle_timeout(5, 6, 1));

	// A non-positive timeout disables the check entirely.
	CHECK_FALSE(MCPHttp::is_idle_timeout(100000, 0, 0));
}

TEST_CASE("[MCPServer] HTTP Transfer-Encoding chunked stays unsupported and is rejected") {
	// D33: decoding `Transfer-Encoding: chunked` is a deferred hardening item,
	// not part of M1 (the hof-rs contract only ever sends `Content-Length`).
	// The trade off is pinned here so that it can never change silently: a POST
	// that carries only `Transfer-Encoding: chunked` has no `Content-Length`,
	// so it is rejected by the length-required path and the connection is
	// closed without the chunked framing ever being interpreted.
	//
	// Note for the record: DESIGN-DETAIL / D33 describe this as a generic 4xx,
	// the concrete status is 411 `Length Required` (the parser deliberately
	// maps a missing `Content-Length` on a request with a body to 411).
	Vector<uint8_t> chunked = TestMCPServer::to_bytes("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n");
	const MCPHttp::ParseOutcome outcome = MCPHttp::parse_request(chunked, 1024);
	CHECK(outcome.status == MCPHttp::ParseStatus::MISSING_CONTENT_LENGTH);
	CHECK(MCPHttp::status_code_for(outcome.status) == 411);
	CHECK(MCPHttp::reason_phrase(411) == "Length Required");
	// The undecodable payload is dropped, so it can never be mistaken for a body.
	CHECK(chunked.is_empty());
}

// ---------------------------------------------------------------------------
// Port resolution (GDR-4). Function level only: no socket is ever bound.
// ---------------------------------------------------------------------------

TEST_CASE("[MCPServer] port defaults are 9877 for the editor and 0 for a game") {
	Vector<String> no_args;

	MCPPortConfig editor = MCPPort::parse(no_args, false, 0, true);
	CHECK(editor.port == 9877);
	CHECK_FALSE(editor.explicit_cmdline);
	CHECK_FALSE(editor.from_project_setting);
	CHECK(MCPPort::should_listen(true, editor, false));

	MCPPortConfig game = MCPPort::parse(no_args, false, 0, false);
	CHECK(game.port == 0);
	CHECK_FALSE(MCPPort::should_listen(false, game, false));
	CHECK_FALSE(MCPPort::should_listen(false, game, true));
}

TEST_CASE("[MCPServer] --mcp-port forms are parsed and take priority") {
	Vector<String> equals_form;
	equals_form.push_back("--headless");
	equals_form.push_back("--mcp-port=9888");
	MCPPortConfig equals_config = MCPPort::parse(equals_form, true, 9911, true);
	CHECK(equals_config.port == 9888);
	CHECK(equals_config.explicit_cmdline);
	CHECK(MCPPort::should_listen(true, equals_config, false));

	Vector<String> space_form;
	space_form.push_back("--mcp-port");
	space_form.push_back("9889");
	MCPPortConfig space_config = MCPPort::parse(space_form, false, 0, false);
	CHECK(space_config.port == 9889);
	CHECK(space_config.explicit_cmdline);
	// Explicitly requested, so a game process listens.
	CHECK(MCPPort::should_listen(false, space_config, false));

	Vector<String> trailing_space;
	trailing_space.push_back("--mcp-port");
	MCPPortConfig trailing_config = MCPPort::parse(trailing_space, false, 0, true);
	CHECK(trailing_config.port == 9877);
	CHECK_FALSE(trailing_config.explicit_cmdline);

	Vector<String> invalid;
	invalid.push_back("--mcp-port=abc");
	MCPPortConfig invalid_config = MCPPort::parse(invalid, false, 0, true);
	CHECK(invalid_config.port == 9877);
	CHECK_FALSE(invalid_config.explicit_cmdline);

	Vector<String> zero;
	zero.push_back("--mcp-port=0");
	MCPPortConfig zero_config = MCPPort::parse(zero, false, 0, false);
	CHECK(zero_config.port == 0);
	CHECK(zero_config.explicit_cmdline);
	CHECK_FALSE(MCPPort::should_listen(false, zero_config, true));
}

TEST_CASE("[MCPServer] project setting port and game opt-in") {
	Vector<String> no_args;

	MCPPortConfig from_setting = MCPPort::parse(no_args, true, 9911, true);
	CHECK(from_setting.port == 9911);
	CHECK(from_setting.from_project_setting);
	CHECK(MCPPort::should_listen(true, from_setting, false));

	// A game process must opt in explicitly (C4).
	MCPPortConfig game_setting = MCPPort::parse(no_args, true, 9889, false);
	CHECK(game_setting.port == 9889);
	CHECK_FALSE(MCPPort::should_listen(false, game_setting, false));
	CHECK(MCPPort::should_listen(false, game_setting, true));

	// Out of range settings are ignored.
	MCPPortConfig out_of_range = MCPPort::parse(no_args, true, 70000, false);
	CHECK(out_of_range.port == 0);
	CHECK_FALSE(out_of_range.from_project_setting);
}

// ---------------------------------------------------------------------------
// JSON-RPC envelope (GDR-6). The strings below are the reference shapes.
// ---------------------------------------------------------------------------

TEST_CASE("[MCPServer] JSON-RPC initialize envelope") {
	MCPToolRegistry registry;

	MCPJsonRpc::Response numeric = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}", registry, true);
	CHECK(numeric.http_status == 200);
	CHECK(numeric.body == "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"capabilities\":{\"logging\":{},\"tools\":{\"listChanged\":false}},\"protocolVersion\":\"2025-03-26\",\"serverInfo\":{\"name\":\"godot-mcp-rs\",\"version\":\"0.1.0\"}}}");

	MCPJsonRpc::Response string_id = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"method\":\"initialize\"}", registry, true);
	CHECK(string_id.body.begins_with("{\"id\":\"abc\",\"jsonrpc\":\"2.0\",\"result\":{\"capabilities\":"));
}

TEST_CASE("[MCPServer] JSON-RPC ping envelope") {
	MCPToolRegistry registry;

	MCPJsonRpc::Response response = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ping\"}", registry, true);
	CHECK(response.http_status == 200);
	CHECK(response.body == "{\"id\":7,\"jsonrpc\":\"2.0\",\"result\":{}}");
}

TEST_CASE("[MCPServer] JSON-RPC notifications/initialized has an empty body") {
	MCPToolRegistry registry;

	MCPJsonRpc::Response response = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}", registry, true);
	CHECK(response.http_status == 202);
	CHECK(response.body.is_empty());
}

TEST_CASE("[MCPServer] JSON-RPC unknown method is -32601") {
	MCPToolRegistry registry;

	MCPJsonRpc::Response response = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"does/not/exist\"}", registry, true);
	CHECK(response.body == "{\"error\":{\"code\":-32601,\"message\":\"Method not found: does/not/exist\"},\"id\":1,\"jsonrpc\":\"2.0\"}");
}

TEST_CASE("[MCPServer] JSON-RPC parse error is -32700 with a null id") {
	MCPToolRegistry registry;

	MCPJsonRpc::Response response = MCPJsonRpc::handle("{this is not json", registry, true);
	CHECK(response.http_status == 400);
	CHECK(response.body == "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}");
}

TEST_CASE("[MCPServer] JSON-RPC invalid request is -32600") {
	MCPToolRegistry registry;

	MCPJsonRpc::Response not_an_object = MCPJsonRpc::handle("[]", registry, true);
	CHECK(not_an_object.body == "{\"error\":{\"code\":-32600,\"message\":\"Invalid request: request must be a JSON object\"},\"id\":null,\"jsonrpc\":\"2.0\"}");

	MCPJsonRpc::Response no_method = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":3}", registry, true);
	CHECK(no_method.body == "{\"error\":{\"code\":-32600,\"message\":\"Invalid request: missing method\"},\"id\":3,\"jsonrpc\":\"2.0\"}");

	MCPJsonRpc::Response bad_method = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":42}", registry, true);
	CHECK(bad_method.body == "{\"error\":{\"code\":-32600,\"message\":\"Invalid request: missing method\"},\"id\":4,\"jsonrpc\":\"2.0\"}");
}

TEST_CASE("[MCPServer] JSON-RPC tools/call argument errors are -32602") {
	MCPToolRegistry registry;
	TestMCPServer::build_project_registry(registry);

	MCPJsonRpc::Response missing_name = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{}}", registry, true);
	CHECK(missing_name.body == "{\"error\":{\"code\":-32602,\"message\":\"Missing tool name\"},\"id\":5,\"jsonrpc\":\"2.0\"}");

	MCPJsonRpc::Response bad_arguments = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"project_get_info\",\"arguments\":\"nope\"}}", registry, true);
	CHECK(bad_arguments.body == "{\"error\":{\"code\":-32602,\"message\":\"Invalid arguments: expected an object\"},\"id\":6,\"jsonrpc\":\"2.0\"}");

	MCPJsonRpc::Response bad_params = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":7}", registry, true);
	CHECK(bad_params.body == "{\"error\":{\"code\":-32602,\"message\":\"Invalid params: expected an object\"},\"id\":6,\"jsonrpc\":\"2.0\"}");

	MCPJsonRpc::Response unknown_tool = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"not_a_tool\"}}", registry, true);
	CHECK(unknown_tool.body == "{\"error\":{\"code\":-32601,\"message\":\"Method not found: not_a_tool\"},\"id\":8,\"jsonrpc\":\"2.0\"}");
}

TEST_CASE("[MCPServer] JSON-RPC echoes string and number ids verbatim") {
	MCPToolRegistry registry;
	TestMCPServer::build_project_registry(registry);

	// Godot's JSON parser turns every number into a double, so the raw token
	// has to be preserved: `1.0` would break serde_json's `as_u64()` on the
	// client side and therefore id correlation as a whole.
	MCPJsonRpc::Response number_id = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":123,\"method\":\"tools/list\"}", registry, true);
	CHECK(number_id.body.begins_with("{\"id\":123,"));

	MCPJsonRpc::Response string_id = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":\"req-42\",\"method\":\"tools/list\"}", registry, true);
	CHECK(string_id.body.begins_with("{\"id\":\"req-42\","));

	MCPJsonRpc::Response float_id = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":1.5,\"method\":\"ping\"}", registry, true);
	CHECK(float_id.body == "{\"id\":1.5,\"jsonrpc\":\"2.0\",\"result\":{}}");

	// Whitespace between the key and the value is allowed.
	MCPJsonRpc::Response spaced_id = MCPJsonRpc::handle("{ \"id\" : 8 , \"method\" : \"ping\" }", registry, true);
	CHECK(spaced_id.body.begins_with("{\"id\":8,"));

	// An `id` nested in `params` must never be mistaken for the request id.
	MCPJsonRpc::Response nested_id = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"project_get_info\",\"arguments\":{\"id\":99}}}", registry, true);
	CHECK(nested_id.body.begins_with("{\"id\":5,\"jsonrpc\":"));

	// Requests without an id are answered with a null id.
	MCPJsonRpc::Response no_id = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}", registry, true);
	CHECK(no_id.body == "{\"id\":null,\"jsonrpc\":\"2.0\",\"result\":{}}");

	// Interleaved ids keep their own response.
	MCPJsonRpc::Response a = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}", registry, true);
	MCPJsonRpc::Response b = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}", registry, true);
	CHECK(a.body.begins_with("{\"id\":1,"));
	CHECK(b.body.begins_with("{\"id\":2,"));
}

// ---------------------------------------------------------------------------
// Tool registry and scope filtering (GDR-7)
// ---------------------------------------------------------------------------

TEST_CASE("[MCPServer] tools/list filters by process scope") {
	MCPToolRegistry registry;
	TestMCPServer::build_scope_registry(registry);

	CHECK(MCPToolRegistry::scope_matches(MCPToolScope::EDITOR, true));
	CHECK_FALSE(MCPToolRegistry::scope_matches(MCPToolScope::EDITOR, false));
	CHECK_FALSE(MCPToolRegistry::scope_matches(MCPToolScope::GAME, true));
	CHECK(MCPToolRegistry::scope_matches(MCPToolScope::GAME, false));
	CHECK(MCPToolRegistry::scope_matches(MCPToolScope::BOTH, true));
	CHECK(MCPToolRegistry::scope_matches(MCPToolScope::BOTH, false));

	CHECK(registry.is_tool_visible("editor_get_scope_probe", true));
	CHECK_FALSE(registry.is_tool_visible("editor_get_scope_probe", false));
	CHECK(registry.is_tool_visible("running_game_get_scope_probe", false));
	CHECK_FALSE(registry.is_tool_visible("running_game_get_scope_probe", true));

	MCPJsonRpc::Response editor = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}", registry, true);
	Variant parsed_editor = TestMCPServer::parse_json(editor.body);
	CHECK(parsed_editor.get_type() == Variant::DICTIONARY);
	if (parsed_editor.get_type() == Variant::DICTIONARY) {
		Dictionary editor_result = (Dictionary)parsed_editor;
		CHECK(editor_result.has("result"));
		if (editor_result.has("result")) {
			Dictionary result_body = editor_result["result"];
			CHECK(result_body.has("tools"));
			if (result_body.has("tools")) {
				Array editor_tools = result_body["tools"];
				CHECK(editor_tools.size() == 2);
				if (editor_tools.size() == 2) {
					CHECK((String)((Dictionary)editor_tools[0])["name"] == "editor_get_scope_probe");
					CHECK((String)((Dictionary)editor_tools[1])["name"] == "project_get_scope_probe");
				}
			}
		}
	}

	MCPJsonRpc::Response game = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}", registry, false);
	Variant parsed_game = TestMCPServer::parse_json(game.body);
	CHECK(parsed_game.get_type() == Variant::DICTIONARY);
	if (parsed_game.get_type() == Variant::DICTIONARY) {
		Dictionary game_result = (Dictionary)parsed_game;
		CHECK(game_result.has("result"));
		if (game_result.has("result")) {
			Dictionary result_body = game_result["result"];
			CHECK(result_body.has("tools"));
			if (result_body.has("tools")) {
				Array game_tools = result_body["tools"];
				CHECK(game_tools.size() == 2);
				if (game_tools.size() == 2) {
					CHECK((String)((Dictionary)game_tools[0])["name"] == "running_game_get_scope_probe");
					CHECK((String)((Dictionary)game_tools[1])["name"] == "project_get_scope_probe");
				}
			}
		}
	}
}

TEST_CASE("[MCPServer] tools/list exposes exactly the six template group tools") {
	MCPToolRegistry registry;
	TestMCPServer::build_project_registry(registry);

	CHECK(registry.get_visible_tool_count(true) == 6);
	CHECK(registry.get_visible_tool_count(false) == 6);

	// Byte exact, including the descriptions and input schemas taken verbatim
	// from docs/tools_list.renamed.json (= the renamed old contract). The first
	// two entries are byte-identical to the M1 revision of this test, which is
	// the migration regression guard for project_get_info /
	// project_get_settings.
	MCPJsonRpc::Response response = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}", registry, true);
	CHECK(response.body == String::utf8("{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"tools\":["
										"{\"description\":\"获取项目信息\",\"inputSchema\":{\"properties\":{},\"required\":[],\"type\":\"object\"},\"name\":\"project_get_info\"},"
										"{\"description\":\"获取项目设置\",\"inputSchema\":{\"properties\":{\"include_default\":{\"default\":false,\"type\":\"boolean\"},\"prefix\":{\"type\":\"string\"}},\"required\":[],\"type\":\"object\"},\"name\":\"project_get_settings\"},"
										"{\"description\":\"获取文件系统树状结构\",\"inputSchema\":{\"properties\":{\"max_depth\":{\"default\":-1,\"type\":\"integer\"},\"path\":{\"default\":\"res://\",\"type\":\"string\"}},\"required\":[],\"type\":\"object\"},\"name\":\"project_get_filesystem_tree\"},"
										"{\"description\":\"搜索文件 判别点：只匹配文件名子串（大小写不敏感、上限 200），不读文件内容、不返回行号；要搜索文件内容请用 project_search_file_contents。\",\"inputSchema\":{\"properties\":{\"path\":{\"default\":\"res://\",\"type\":\"string\"},\"pattern\":{\"type\":\"string\"}},\"required\":[\"pattern\"],\"type\":\"object\"},\"name\":\"project_search_file_names\"},"
										"{\"description\":\"在文件内容中搜索文本 判别点：逐行返回 {file,line,text}（大小写不敏感、上限 50，跳过 addons 与 .godot 目录）；要按文件聚合的 {file,lines[]}（大小写敏感、上限 100）请用 project_find_files_referencing_symbol。\",\"inputSchema\":{\"properties\":{\"file_pattern\":{\"default\":\"*\",\"type\":\"string\"},\"path\":{\"default\":\"res://\",\"type\":\"string\"},\"pattern\":{\"type\":\"string\"}},\"required\":[\"pattern\"],\"type\":\"object\"},\"name\":\"project_search_file_contents\"},"
										"{\"description\":\"在项目文件中搜索指定模式的引用 判别点：按文件聚合返回 {file,lines[]}（每文件最多 5 行、大小写敏感、上限 100，跳过隐藏文件与 addons，只扫 .tscn/.gd/.tres/.gdshader）；要逐行 {file,line,text}（大小写不敏感、上限 50）请用 project_search_file_contents。\",\"inputSchema\":{\"properties\":{\"pattern\":{\"description\":\"要搜索的模式\",\"type\":\"string\"}},\"required\":[\"pattern\"],\"type\":\"object\"},\"name\":\"project_find_files_referencing_symbol\"}"
										"]}}"));
}

TEST_CASE("[MCPServer] the shared registration entry point registers the group") {
	MCPToolRegistry registry;
	TestMCPServer::build_all_tools_registry(registry);

	CHECK(registry.get_tool_count() == 6);
	CHECK(registry.has_tool("project_get_info"));
	CHECK(registry.has_tool("project_find_files_referencing_symbol"));
}

TEST_CASE("[MCPServer] tools of later batches are not registered") {
	// GDR-7: registering an unimplemented tool just to make a gate look complete
	// is forbidden, so the unimplemented B1 groups must be absent from the
	// registry (and therefore from `tools/list`).
	MCPToolRegistry registry;
	TestMCPServer::build_all_tools_registry(registry);

	CHECK(registry.get_tool_count() == 6);
	CHECK_FALSE(registry.has_tool("editor_open_scene"));
	CHECK_FALSE(registry.has_tool("project_create_scene_file"));
	CHECK_FALSE(registry.has_tool("running_game_find_nearby_nodes"));
	CHECK_FALSE(registry.has_tool("editor_remove_output_log"));
}

// ---------------------------------------------------------------------------
// Tool builder + argument helpers + error factories (TASK-002 section 2.2.2)
// ---------------------------------------------------------------------------

TEST_CASE("[MCPServer] the editor guard is an alias of the engine tools macro") {
	// The module-owned guard must be defined exactly when Godot's TOOLS_ENABLED
	// is: the doctest binary is an editor build, so both are defined here. If
	// the guard ever drifted (e.g. to a macro name this fork does not define),
	// every editor-only call site would silently disappear from an editor build.
#ifdef TOOLS_ENABLED
	CHECK(MCP_EDITOR_TOOLS_ENABLED == 1);
#endif
	CHECK_FALSE(MCPTools::is_editor_process());
}

TEST_CASE("[MCPServer] tool builder refuses an incomplete declaration") {
	MCPToolDef built;
	String reason;

	// Nothing but the name and the description: channel, verb, scope, mutating
	// and handler are all missing.
	MCPTools::ToolBuilder bare("project_get_bare_probe", "bare");
	CHECK_FALSE(bare.build(built, reason));
	CHECK(reason.contains("must declare"));
	CHECK(reason.contains("channel"));
	CHECK(reason.contains("verb"));
	CHECK(reason.contains("scope"));
	CHECK(reason.contains("mutating"));
	CHECK(reason.contains("handler"));

	// Declaring only `mutating` still fails: every dimension is mandatory.
	MCPTools::ToolBuilder partial("project_get_partial_probe", "partial");
	partial.mutating(false);
	CHECK_FALSE(partial.build(built, reason));
	CHECK(reason.contains("channel"));
	CHECK_FALSE(reason.contains("mutating"));

	// A complete declaration builds and carries every declared value.
	MCPTools::ToolBuilder complete("project_get_complete_probe", "complete");
	complete.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(true).schema(MCPTools::empty_object_schema()).handler(TestMCPServer::unused_handler);
	CHECK(complete.build(built, reason));
	CHECK(reason.is_empty());
	CHECK(built.mutating == true);
	CHECK(built.scope == MCPToolScope::BOTH);
	CHECK(built.handler != nullptr);

	// The GDR-16 lint runs inside the builder as well.
	MCPTools::ToolBuilder bad_verb("project_update_probe", "bad");
	bad_verb.channel("project").verb("update").scope(MCPToolScope::BOTH).mutating(false).schema(MCPTools::empty_object_schema()).handler(TestMCPServer::unused_handler);
	CHECK_FALSE(bad_verb.build(built, reason));
	CHECK(reason.contains("GDR-16 L4"));
}

TEST_CASE("[MCPServer] AUDIT002 every missing declaration combination is refused") {
	// 16 masks over the four dimensions the builder must force explicitly.
	// `name` is always given; `schema` is always given; `handler` is attached
	// only for the complete mask, and missing-handler is covered separately.
	struct Dimensions {
		int bit;
		const char *name;
	};
	const Dimensions dims[4] = { { 1, "channel" }, { 2, "verb" }, { 4, "scope" }, { 8, "mutating" } };

	int refused = 0;
	for (int mask = 0; mask < 16; mask++) {
		MCPTools::ToolBuilder b("project_get_violation_probe", "probe");
		b.schema(MCPTools::empty_object_schema());
		if (mask & 1) { b.channel("project"); }
		if (mask & 2) { b.verb("get"); }
		if (mask & 4) { b.scope(MCPToolScope::BOTH); }
		if (mask & 8) { b.mutating(false); }
		if (mask == 15) {
			b.handler(TestMCPServer::unused_handler);
		}

		MCPToolDef built;
		String reason;
		const bool ok = b.build(built, reason);

		if (mask == 15) {
			CHECK(ok);
			CHECK(reason.is_empty());
			CHECK(built.mutating == false);
			CHECK(built.scope == MCPToolScope::BOTH);
			CHECK(built.handler != nullptr);
		} else {
			CHECK_FALSE(ok);
			refused++;
			for (int d = 0; d < 4; d++) {
				if ((mask & dims[d].bit) == 0) {
					CHECK(reason.contains(dims[d].name));
				}
			}
			// the missing handler must be reported as well
			CHECK(reason.contains("handler"));
		}
	}
	CHECK(refused == 15);

	// The very first violation: no name given at all.
	{
		MCPToolDef built;
		String reason;
		MCPTools::ToolBuilder no_name(String(), "probe");
		no_name.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).handler(TestMCPServer::unused_handler);
		CHECK_FALSE(no_name.build(built, reason));
		CHECK(reason.contains("name"));
	}

	// register_into() must refuse as well and must not touch the table.
	{
		MCPToolRegistry registry;
		MCPTools::ToolBuilder no_mutating("project_get_no_mutating_probe", "probe");
		no_mutating.channel("project").verb("get").scope(MCPToolScope::BOTH).schema(MCPTools::empty_object_schema()).handler(TestMCPServer::unused_handler);
		CHECK_FALSE(no_mutating.register_into(registry));
		CHECK_FALSE(registry.has_tool("project_get_no_mutating_probe"));
		CHECK(registry.get_tool_count() == 0);
	}

	// A complete declaration does register, so the refusal above is about the
	// declaration and not about the probe name being un-registrable.
	{
		MCPToolRegistry registry;
		MCPTools::ToolBuilder complete("project_get_complete_probe", "probe");
		complete.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(MCPTools::empty_object_schema()).handler(TestMCPServer::unused_handler);
		CHECK(complete.register_into(registry));
		CHECK(registry.has_tool("project_get_complete_probe"));
		CHECK(registry.get_tool_count() == 1);
	}
}

TEST_CASE("[MCPServer] tool builder keeps editor-only tools out of a game process") {
	MCPToolRegistry registry;

	MCPTools::ToolBuilder editor_only("editor_get_builder_probe", "editor only");
	editor_only.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false).schema(MCPTools::empty_object_schema()).handler(TestMCPServer::unused_handler);
	const bool registered = editor_only.register_into(registry);

	// The doctest process is not an editor, so the editor-only tool must not
	// even enter the table (registering it would still be hidden by the scope
	// filter, but a game process must not carry it at all).
	CHECK_FALSE(MCPTools::is_editor_process());
	CHECK_FALSE(registered);
	CHECK_FALSE(registry.has_tool("editor_get_builder_probe"));
	CHECK(registry.get_tool_count() == 0);

	// A `both` scope tool registers in exactly the same process.
	MCPTools::ToolBuilder both("project_get_builder_probe", "both");
	both.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(MCPTools::empty_object_schema()).handler(TestMCPServer::unused_handler);
	CHECK(both.register_into(registry));
	CHECK(registry.has_tool("project_get_builder_probe"));
	CHECK(registry.get_tool_count() == 1);
}

TEST_CASE("[MCPServer] argument helpers report -32602") {
	MCPToolError error;
	Dictionary args;
	String text;
	int64_t number = 0;
	bool flag = false;

	// Required, missing.
	CHECK_FALSE(MCPTools::require_string(args, "pattern", text, error));
	CHECK(error.code == -32602);
	CHECK(error.message == "Missing required parameter: pattern");
	CHECK(error.data.get_type() == Variant::NIL);

	// Required, wrong type.
	error = MCPToolError();
	args["pattern"] = 42;
	CHECK_FALSE(MCPTools::require_string(args, "pattern", text, error));
	CHECK(error.code == -32602);
	CHECK(error.message.contains("must be a string"));
	CHECK(error.message.contains("int"));

	// Required int accepts an integral float (JSON-RPC clients may send 2.0) and
	// rejects a fractional one.
	error = MCPToolError();
	args["max_depth"] = 2.0;
	CHECK(MCPTools::require_int(args, "max_depth", number, error));
	CHECK(number == 2);
	error = MCPToolError();
	args["max_depth"] = 2.5;
	CHECK_FALSE(MCPTools::require_int(args, "max_depth", number, error));
	CHECK(error.code == -32602);
	CHECK(error.message.contains("must be an integer"));

	// Optional: absent means default, present with the wrong type is an error.
	error = MCPToolError();
	CHECK(MCPTools::optional_string(args, "absent", "fallback", text, error));
	CHECK(text == "fallback");
	CHECK_FALSE(error.is_error());

	error = MCPToolError();
	CHECK(MCPTools::optional_int(args, "absent", -1, number, error));
	CHECK(number == -1);

	error = MCPToolError();
	CHECK(MCPTools::optional_bool(args, "absent", true, flag, error));
	CHECK(flag == true);

	error = MCPToolError();
	args["prefix"] = true;
	CHECK_FALSE(MCPTools::optional_string(args, "prefix", "", text, error));
	CHECK(error.code == -32602);
	CHECK(error.message.contains("must be a string"));
	CHECK(error.message.contains("bool"));

	error = MCPToolError();
	args["include_default"] = "yes";
	CHECK_FALSE(MCPTools::optional_bool(args, "include_default", false, flag, error));
	CHECK(error.code == -32602);
	CHECK(error.message.contains("must be a boolean"));
}

TEST_CASE("[MCPServer] tool error factories carry the reference codes and data") {
	MCPToolError invalid = MCPToolError::invalid_params("Missing required parameter: pattern");
	CHECK(invalid.code == -32602);
	CHECK(invalid.message == "Missing required parameter: pattern"); // no prefix (GDR-6)

	MCPToolError not_found = MCPToolError::not_found("File 'res://nope.gd'", "List the project first");
	CHECK(not_found.code == -32001);
	CHECK(not_found.message == "File 'res://nope.gd' not found");
	CHECK(((Dictionary)not_found.data)["suggestion"] == "List the project first");

	MCPToolError no_scene = MCPToolError::no_scene();
	CHECK(no_scene.code == -32000);
	CHECK(no_scene.message == "No scene is currently open");
	CHECK(((Dictionary)no_scene.data).has("suggestion"));

	MCPToolError unimplemented = MCPToolError::not_implemented("probe feature", "Wait for a later batch");
	CHECK(unimplemented.code == -32000);
	CHECK(unimplemented.message == "Not implemented: probe feature");
	CHECK(((Dictionary)unimplemented.data)["suggestion"] == "Wait for a later batch");

	MCPToolError internal = MCPToolError::internal("boom");
	CHECK(internal.code == -32603);
	CHECK(internal.message == "Internal error: boom");
}

TEST_CASE("[MCPServer] tools/call maps a tool error to its own code and data") {
	MCPToolRegistry registry;
	TestMCPServer::build_error_probe_registry(registry);

	MCPJsonRpc::Response not_found = MCPJsonRpc::handle(
			"{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{\"name\":\"project_get_error_probe\"}}", registry, true);
	CHECK(not_found.http_status == 200);
	CHECK(not_found.body == "{\"error\":{\"code\":-32001,\"data\":{\"suggestion\":\"Create it first\"},"
							"\"message\":\"Probe resource 'x' not found\"},\"id\":11,\"jsonrpc\":\"2.0\"}");

	MCPJsonRpc::Response unimplemented = MCPJsonRpc::handle(
			"{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"project_get_unimplemented_probe\"}}", registry, true);
	CHECK(unimplemented.body == "{\"error\":{\"code\":-32000,\"data\":{\"suggestion\":\"Wait for a later batch\"},"
								"\"message\":\"Not implemented: probe feature\"},\"id\":12,\"jsonrpc\":\"2.0\"}");
}

TEST_CASE("[MCPServer] project_get_info success path") {
	MCPToolRegistry registry;
	TestMCPServer::build_project_registry(registry);

	MCPToolError tool_error;
	Variant result = registry.call_tool("project_get_info", Dictionary(), tool_error);
	CHECK_FALSE(tool_error.is_error());
	CHECK(result.get_type() == Variant::DICTIONARY);
	if (result.get_type() == Variant::DICTIONARY) {
		Dictionary info = (Dictionary)result;
		CHECK(info.has("project_name"));
		CHECK(info.has("version"));
		CHECK(info.has("editor_screen_size"));
		if (info.has("editor_screen_size")) {
			CHECK(((Dictionary)info["editor_screen_size"]).has("width"));
			CHECK(((Dictionary)info["editor_screen_size"]).has("height"));
		}
	}
}

TEST_CASE("[MCPServer] tools/call wraps the result in the content envelope") {
	MCPToolRegistry registry;
	TestMCPServer::build_project_registry(registry);

	MCPJsonRpc::Response response = MCPJsonRpc::handle("{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"project_get_info\"}}", registry, true);
	CHECK(response.http_status == 200);

	Variant parsed = TestMCPServer::parse_json(response.body);
	CHECK(parsed.get_type() == Variant::DICTIONARY);
	if (parsed.get_type() == Variant::DICTIONARY) {
		Dictionary envelope = (Dictionary)parsed;
		CHECK(envelope["jsonrpc"] == "2.0");
		CHECK((int)envelope["id"] == 9);
		CHECK(envelope.has("result"));
		if (envelope.has("result")) {
			Dictionary result_body = envelope["result"];
			CHECK(result_body.has("content"));
			if (result_body.has("content")) {
				Array content = result_body["content"];
				CHECK(content.size() == 1);
				if (content.size() == 1) {
					Dictionary item = (Dictionary)content[0];
					CHECK(item["type"] == "text");
					CHECK(item.has("text"));
					if (item.has("text")) {
						Variant parsed_text = TestMCPServer::parse_json(item["text"]);
						CHECK(parsed_text.get_type() == Variant::DICTIONARY);
						if (parsed_text.get_type() == Variant::DICTIONARY) {
							Dictionary payload = (Dictionary)parsed_text;
							CHECK(payload.has("project_name"));
							CHECK(payload.has("version"));
						}
					}
				}
			}
		}
	}
}

TEST_CASE("[MCPServer] project_get_settings filters by prefix") {
	MCPToolRegistry registry;
	TestMCPServer::build_project_registry(registry);

	Dictionary args;
	args["prefix"] = "application/config/name";
	MCPToolError tool_error;
	Variant result = registry.call_tool("project_get_settings", args, tool_error);
	CHECK_FALSE(tool_error.is_error());
	CHECK(result.get_type() == Variant::DICTIONARY);
	if (result.get_type() == Variant::DICTIONARY) {
		Dictionary payload = (Dictionary)result;
		CHECK(payload.has("settings"));
		CHECK(payload.has("count"));
		if (payload.has("settings")) {
			Dictionary settings = payload["settings"];
			CHECK(settings.has("application/config/name"));
			CHECK((int)payload["count"] == settings.size());
		}
	}
}

TEST_CASE("[MCPServer] project_get_settings rejects a mistyped optional argument") {
	MCPToolRegistry registry;
	TestMCPServer::build_project_registry(registry);

	Dictionary args;
	args["prefix"] = 7;
	MCPToolError tool_error;
	const Variant result = registry.call_tool("project_get_settings", args, tool_error);
	CHECK(tool_error.code == -32602);
	CHECK(tool_error.message.contains("must be a string"));
	CHECK(result.get_type() == Variant::NIL);
}

// ---------------------------------------------------------------------------
// The four new B1 template tools
// ---------------------------------------------------------------------------

TEST_CASE("[MCPServer] project_get_filesystem_tree lists a directory and reports a missing one") {
	MCPToolRegistry registry;
	TestMCPServer::build_project_registry(registry);

	// max_depth = 0 keeps the walk to the root entry, so the assertion does not
	// depend on how many files happen to sit next to the test binary.
	Dictionary args;
	args["max_depth"] = 0;
	MCPToolError tool_error;
	const Variant result = registry.call_tool("project_get_filesystem_tree", args, tool_error);
	CHECK_FALSE(tool_error.is_error());
	CHECK(result.get_type() == Variant::DICTIONARY);
	if (result.get_type() == Variant::DICTIONARY) {
		const Dictionary payload = (Dictionary)result;
		CHECK(payload.has("tree"));
		if (payload.has("tree")) {
			const Dictionary tree = payload["tree"];
			CHECK(tree.has("name"));
			CHECK(tree.has("path"));
			CHECK((String)tree["path"] == "res://");
			CHECK((String)tree["type"] == "directory");
		}
	}

	// A project directory that does not exist is a `-32001` tool error with a
	// suggestion (GDR-14), not an empty tree.
	Dictionary missing;
	missing["path"] = "res://__no_such_directory_for_mcp_tests__";
	MCPToolError missing_error;
	const Variant missing_result = registry.call_tool("project_get_filesystem_tree", missing, missing_error);
	CHECK(missing_error.code == -32001);
	CHECK(missing_error.message.contains("not found"));
	CHECK(missing_error.message.contains("__no_such_directory_for_mcp_tests__"));
	CHECK(((Dictionary)missing_error.data).has("suggestion"));
	CHECK(missing_result.get_type() == Variant::NIL);

	// A path outside the project is an argument error.
	Dictionary outside;
	outside["path"] = "C:/Windows";
	MCPToolError outside_error;
	registry.call_tool("project_get_filesystem_tree", outside, outside_error);
	CHECK(outside_error.code == -32602);
	CHECK(outside_error.message.contains("res://"));

	Dictionary upwards;
	upwards["path"] = "res://../etc";
	MCPToolError upwards_error;
	registry.call_tool("project_get_filesystem_tree", upwards, upwards_error);
	CHECK(upwards_error.code == -32602);
	CHECK(upwards_error.message.contains(".."));
}

TEST_CASE("[MCPServer] project_search_file_names requires a pattern") {
	MCPToolRegistry registry;
	TestMCPServer::build_project_registry(registry);

	MCPToolError tool_error;
	const Variant result = registry.call_tool("project_search_file_names", Dictionary(), tool_error);
	CHECK(tool_error.code == -32602);
	CHECK(tool_error.message == "Missing required parameter: pattern");
	CHECK(result.get_type() == Variant::NIL);

	Dictionary wrong_type;
	wrong_type["pattern"] = 12;
	MCPToolError type_error;
	registry.call_tool("project_search_file_names", wrong_type, type_error);
	CHECK(type_error.code == -32602);
	CHECK(type_error.message.contains("must be a string"));

	// A missing search root is the bottom layer failure class of this tool.
	Dictionary missing_root;
	missing_root["pattern"] = "anything";
	missing_root["path"] = "res://__no_such_directory_for_mcp_tests__";
	MCPToolError missing_error;
	registry.call_tool("project_search_file_names", missing_root, missing_error);
	CHECK(missing_error.code == -32001);
	CHECK(missing_error.message.contains("not found"));
}

TEST_CASE("[MCPServer] the two de-merged search tools stay distinct (GDR-17)") {
	MCPToolRegistry registry;
	TestMCPServer::build_project_registry(registry);

	// Two registered tools, two names, two handlers, two result shapes.
	CHECK(registry.has_tool("project_search_file_contents"));
	CHECK(registry.has_tool("project_find_files_referencing_symbol"));

	Array tools = registry.build_tools_list(true);
	Dictionary contents;
	Dictionary references;
	for (int i = 0; i < tools.size(); i++) {
		const Dictionary entry = tools[i];
		if ((String)entry["name"] == "project_search_file_contents") {
			contents = entry;
		}
		if ((String)entry["name"] == "project_find_files_referencing_symbol") {
			references = entry;
		}
	}
	CHECK_FALSE(contents.is_empty());
	CHECK_FALSE(references.is_empty());

	// Different parameters: the content search takes `file_pattern` and `path`,
	// the reference scan takes neither.
	const Dictionary contents_properties = ((Dictionary)contents["inputSchema"])["properties"];
	const Dictionary references_properties = ((Dictionary)references["inputSchema"])["properties"];
	CHECK(contents_properties.has("file_pattern"));
	CHECK(contents_properties.has("path"));
	CHECK_FALSE(references_properties.has("file_pattern"));
	CHECK_FALSE(references_properties.has("path"));

	// Different descriptions, each naming the other as the alternative. The
	// Chinese literals have to go through String::utf8(): `String(const char *)`
	// decodes as Latin-1, which would compare mojibake against a real string.
	const String contents_description = contents["description"];
	const String references_description = references["description"];
	CHECK(contents_description != references_description);
	CHECK(contents_description.contains(String::utf8("逐行")));
	CHECK(contents_description.contains("project_find_files_referencing_symbol"));
	CHECK(references_description.contains(String::utf8("按文件聚合")));
	CHECK(references_description.contains("project_search_file_contents"));

	// A pattern that cannot exist anywhere: the reference scan must answer with
	// its own result shape {pattern, matches[], count} and no hit. The walk only
	// ever *reads* .tscn/.gd/.tres/.gdshader files, so it stays cheap.
	MCPToolError references_error;
	Dictionary references_args;
	references_args["pattern"] = "MCP_TEST_PATTERN_THAT_CANNOT_EXIST_12345";
	const Variant references_result = registry.call_tool("project_find_files_referencing_symbol", references_args, references_error);
	CHECK_FALSE(references_error.is_error());
	CHECK(references_result.get_type() == Variant::DICTIONARY);
	if (references_result.get_type() == Variant::DICTIONARY) {
		const Dictionary payload = (Dictionary)references_result;
		CHECK((int)payload["count"] == 0);
		CHECK((String)payload["pattern"] == "MCP_TEST_PATTERN_THAT_CANNOT_EXIST_12345");
		CHECK(((Array)payload["matches"]).is_empty());
		CHECK_FALSE(payload.has("query"));
	}

	// The argument contract differs as well.
	MCPToolError missing;
	registry.call_tool("project_find_files_referencing_symbol", Dictionary(), missing);
	CHECK(missing.code == -32602);
	CHECK(missing.message == "Missing required parameter: pattern");

	MCPToolError contents_type_error;
	Dictionary wrong_file_pattern;
	wrong_file_pattern["pattern"] = "x";
	wrong_file_pattern["file_pattern"] = 5;
	registry.call_tool("project_search_file_contents", wrong_file_pattern, contents_type_error);
	CHECK(contents_type_error.code == -32602);
	CHECK(contents_type_error.message.contains("file_pattern"));
	CHECK(contents_type_error.message.contains("must be a string"));
}

TEST_CASE("[MCPServer] project_search_file_contents maps a missing root to -32001") {
	MCPToolRegistry registry;
	TestMCPServer::build_project_registry(registry);

	Dictionary args;
	args["pattern"] = "x";
	args["path"] = "res://__no_such_directory_for_mcp_tests__";
	MCPToolError tool_error;
	registry.call_tool("project_search_file_contents", args, tool_error);
	CHECK(tool_error.code == -32001);
	CHECK(tool_error.message.contains("not found"));
}

TEST_CASE("[MCPServer] project_path_is_normalized_for_every_project_tool") {
	MCPToolError error;
	String normalized;

	CHECK(MCPTools::normalize_project_path("", normalized, error));
	CHECK(normalized == "res://");
	CHECK(MCPTools::normalize_project_path("res://", normalized, error));
	CHECK(normalized == "res://");
	CHECK(MCPTools::normalize_project_path("res://scenes/", normalized, error));
	CHECK(normalized == "res://scenes");
	CHECK(MCPTools::normalize_project_path("  res://scenes  ", normalized, error));
	CHECK(normalized == "res://scenes");

	CHECK_FALSE(MCPTools::normalize_project_path("user://x", normalized, error));
	CHECK(error.code == -32602);
	CHECK_FALSE(MCPTools::normalize_project_path("res://a//b", normalized, error));
	CHECK(error.code == -32602);
	CHECK_FALSE(MCPTools::normalize_project_path("res://..", normalized, error));
	CHECK(error.code == -32602);
}

// ---------------------------------------------------------------------------
// GDR-16 naming lint, enforced at registration time.
//
// The predicates are static so that a failure points at the exact rule (L1
// prefix / L2 verb set / L3 declared metadata / L4 banned `update_`) instead of
// only at "the tool did not show up".
// ---------------------------------------------------------------------------

TEST_CASE("[MCPServer] naming lint accepts compliant names across all four channels") {
	MCPToolRegistry registry;

	const String names[4] = { "editor_get_node_properties", "running_game_get_scene_tree", "project_get_info", "os_deploy_to_android_device" };
	const String channels[4] = { "editor", "running_game", "project", "os" };
	const String verbs[4] = { "get", "get", "get", "deploy" };

	for (int i = 0; i < 4; i++) {
		String error;
		CHECK(MCPToolRegistry::validate_tool_name(names[i], channels[i], verbs[i], error));
		CHECK(error.is_empty());

		MCPToolDef def;
		def.name = names[i];
		def.channel = channels[i];
		def.verb = verbs[i];
		def.description = names[i];
		CHECK(registry.register_tool(def));
		CHECK(registry.has_tool(names[i]));
	}
}

TEST_CASE("[MCPServer] naming lint rejects an unknown channel prefix") {
	MCPToolRegistry registry;
	const int count_before = registry.get_visible_tool_count(true);

	String error;
	CHECK_FALSE(MCPToolRegistry::validate_tool_name("game_get_x", "game", "get", error));
	CHECK(error.contains("GDR-16 L1"));

	MCPToolDef bad;
	bad.name = "game_get_x";
	bad.channel = "game";
	bad.verb = "get";
	CHECK_FALSE(registry.register_tool(bad));
	CHECK_FALSE(registry.has_tool("game_get_x"));
	CHECK(registry.get_visible_tool_count(true) == count_before);

	// L1 is lowercase only, so a capitalized channel fails it too.
	String upper_error;
	CHECK_FALSE(MCPToolRegistry::validate_tool_name("Editor_get_info", "Editor", "get", upper_error));
	CHECK(upper_error.contains("GDR-16 L1"));

	MCPToolDef upper;
	upper.name = "Editor_get_info";
	upper.channel = "Editor";
	upper.verb = "get";
	CHECK_FALSE(registry.register_tool(upper));
	CHECK_FALSE(registry.has_tool("Editor_get_info"));
}

TEST_CASE("[MCPServer] naming lint rejects a verb outside the closed set") {
	MCPToolRegistry registry;

	String error;
	CHECK_FALSE(MCPToolRegistry::validate_tool_name("editor_navigate_to_node", "editor", "navigate", error));
	CHECK(error.contains("GDR-16 L2"));

	MCPToolDef bad;
	bad.name = "editor_navigate_to_node";
	bad.channel = "editor";
	bad.verb = "navigate";
	CHECK_FALSE(registry.register_tool(bad));
	CHECK_FALSE(registry.has_tool("editor_navigate_to_node"));

	String clear_error;
	CHECK_FALSE(MCPToolRegistry::validate_tool_name("editor_clear_output_panel", "editor", "clear", clear_error));
	CHECK(clear_error.contains("GDR-16 L2"));

	MCPToolDef clear_def;
	clear_def.name = "editor_clear_output_panel";
	clear_def.channel = "editor";
	clear_def.verb = "clear";
	CHECK_FALSE(registry.register_tool(clear_def));
	CHECK_FALSE(registry.has_tool("editor_clear_output_panel"));
}

TEST_CASE("[MCPServer] naming lint bans update_ anywhere in the name") {
	MCPToolRegistry registry;

	// The channel and the declared verb are both legal here, so only L4 can
	// reject this name - which is why L4 has to run before the L1/L2/L3 checks.
	String error;
	CHECK_FALSE(MCPToolRegistry::validate_tool_name("editor_update_node_property", "editor", "set", error));
	CHECK(error.contains("GDR-16 L4"));
	CHECK(error.contains("update_"));

	MCPToolDef bad;
	bad.name = "editor_update_node_property";
	bad.channel = "editor";
	bad.verb = "set";
	CHECK_FALSE(registry.register_tool(bad));
	CHECK_FALSE(registry.has_tool("editor_update_node_property"));
}

TEST_CASE("[MCPServer] naming lint rejects a declared channel or verb that disagrees with the name") {
	String channel_error;
	CHECK_FALSE(MCPToolRegistry::validate_tool_name("editor_get_node_properties", "project", "get", channel_error));
	CHECK(channel_error.contains("GDR-16 L3"));
	CHECK(channel_error.contains("declares channel"));

	String verb_error;
	CHECK_FALSE(MCPToolRegistry::validate_tool_name("project_get_settings", "project", "list", verb_error));
	CHECK(verb_error.contains("GDR-16 L3"));
	CHECK(verb_error.contains("declares verb"));

	// An undeclared verb is a disagreement as well, never an "anything goes".
	String undeclared_error;
	CHECK_FALSE(MCPToolRegistry::validate_tool_name("project_get_info", "project", "", undeclared_error));
	CHECK(undeclared_error.contains("GDR-16 L3"));

	MCPToolRegistry registry;
	MCPToolDef bad;
	bad.name = "editor_get_node_properties";
	bad.channel = "project";
	bad.verb = "get";
	CHECK_FALSE(registry.register_tool(bad));
	CHECK_FALSE(registry.has_tool("editor_get_node_properties"));
}

TEST_CASE("[MCPServer] naming lint strips running_game_ by longest prefix") {
	// `running_game_` carries its own underscore, so a `split('_')[1]` parse
	// would read the verb as `game`. The longest prefix has to win.
	String channel;
	String verb;
	CHECK(MCPToolRegistry::parse_tool_name("running_game_get_scene_tree", channel, verb));
	CHECK(channel == "running_game");
	CHECK(verb == "get");
	CHECK(verb != "game");

	String editor_channel;
	String editor_verb;
	CHECK(MCPToolRegistry::parse_tool_name("editor_get_node_properties", editor_channel, editor_verb));
	CHECK(editor_channel == "editor");
	CHECK(editor_verb == "get");

	String project_channel;
	String project_verb;
	CHECK(MCPToolRegistry::parse_tool_name("project_get_settings", project_channel, project_verb));
	CHECK(project_channel == "project");
	CHECK(project_verb == "get");

	String os_channel;
	String os_verb;
	CHECK(MCPToolRegistry::parse_tool_name("os_deploy_to_android_device", os_channel, os_verb));
	CHECK(os_channel == "os");
	CHECK(os_verb == "deploy");

	MCPToolRegistry registry;
	MCPToolDef def;
	def.name = "running_game_get_scene_tree";
	def.channel = "running_game";
	def.verb = "get";
	def.scope = MCPToolScope::GAME;
	CHECK(registry.register_tool(def));
	CHECK(registry.is_tool_visible("running_game_get_scene_tree", false));
}
