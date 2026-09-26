/**************************************************************************/
/*  mcp_server.h                                                          */
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

#include "mcp_capture.h"
#include "mcp_http_server.h"
#include "mcp_trace.h"
#include "tool_registry.h"

#include "core/string/string_name.h"
#include "scene/main/node.h"

// Port resolution result (GDR-4). Kept free of engine state so that the whole
// priority chain can be unit tested without binding a socket.
struct MCPPortConfig {
	int port = 0;
	bool explicit_cmdline = false;
	bool from_project_setting = false;
};

namespace MCPPort {

// Priority: `--mcp-port=N` / `--mcp-port N` > `ProjectSettings: godot_mcp/port`
// > default (editor 9877, game 0 = do not listen).
MCPPortConfig parse(const Vector<String> &p_cmdline_args, bool p_has_setting, int p_setting_port, bool p_is_editor);

// A game process listens only when the port was requested explicitly or when
// `godot_mcp/enabled_in_game` is set (REQUIREMENTS C4).
bool should_listen(bool p_is_editor, const MCPPortConfig &p_config, bool p_enabled_in_game);

} // namespace MCPPort

// GDR-20 point 4 / TASK-014 R-3: the framework ceiling of a deferred request.
//
// `mcp_server/pending_timeout_ms` is a *safety net*: GDR-20 point 4 requires a
// deferred request to end with `-32000` + `data.suggestion` + `data.timeout_ms`
// rather than hang. Some deferred tools declare no deadline of their own -
// `running_game_get_node_property_samples` and `running_game_capture_frames`
// wait on a frame count and `MCPDeferred::Task::get_timeout_ms()` defaults to 0 -
// so this ceiling is their **only** bound, and in the transport 0 means "no
// deadline": `MCPJsonRpc::_effective_timeout` answers the ceiling unchanged when
// the task has no deadline of its own, and `MCPHttpServer::_tick_pending` never
// expires an entry whose `timeout_ms` is 0.
//
// A configured `0` (or a negative value) would therefore silently switch the net
// off - a configuration mistake should not be able to do that. `<= 0` falls back
// to the documented default, and the startup log reports both the configured and
// the effective value.
namespace MCPPendingTimeout {

const int DEFAULT_MS = 30000;

// The ceiling actually handed to the transport. `p_configured_ms <= 0` answers
// `DEFAULT_MS` (so the fallback can never be switched off); every positive value
// is passed through unchanged.
int effective_ms(int p_configured_ms);

} // namespace MCPPendingTimeout

// Built-in MCP server: a main-thread-only Node that pumps a non-blocking HTTP
// transport once per frame (GDR-3).
class MCPServer : public Node, public MCPHttpRequestSink {
	GDCLASS(MCPServer, Node);

	MCPToolRegistry registry;
	MCPHttpServer *http_server = nullptr;

	MCPPortConfig port_config;
	int port = 0;
	bool listening = false;
	bool is_editor = false;
	int frame_count = 0;
	int bootstrap_attempts = 0;
	bool service_started = false;

	// TASK-063 (a): the recorded outcome of the startup bind.
	//
	// The defect (TASK-060 D-7 / A-5, measured): `[MCP] bind failed on
	// 127.0.0.1:9889 (error=22)` followed by `get_port()=0` was the *entire*
	// trace of a game endpoint that never came up. `error=22` is not a socket
	// errno - it is the engine's `ERR_ALREADY_IN_USE`, the one code
	// `SocketServer::_listen` folds **every** `NetSocket::bind` failure into
	// (`core/io/socket_server.cpp:47-52`), so the number named neither the cause
	// nor the occupant, and nothing inside the process could be asked what
	// happened.
	//
	// Both halves are fixed here: the failure is reported at ERROR level with the
	// requested port, the diagnosed reason and the fact that the endpoint is
	// disabled, and the same three facts stay readable for the whole life of the
	// process (`get_endpoint_state*()` / `debug_endpoint_state()`), so a caller
	// that only notices "nothing answers on 9889" has somewhere to look beyond a
	// log line.
	enum EndpointState {
		// The server bound and is serving.
		ENDPOINT_LISTENING,
		// No listen was attempted (a game process that was not asked to listen).
		ENDPOINT_NOT_REQUESTED,
		// A listen was attempted and the bind failed.
		ENDPOINT_BIND_FAILED,
	};
	EndpointState endpoint_state = ENDPOINT_NOT_REQUESTED;
	// The port the bind was attempted on (0 when none was attempted).
	int requested_port = 0;
	// Why the endpoint is not listening, in the wire/log wording, or empty while
	// it is listening.
	String endpoint_state_reason;

	int max_body_bytes = 8 * 1024 * 1024;
	int max_requests_per_frame = 8;
	double connection_idle_seconds = 30.0;
	// GDR-20: ceiling of a deferred request and the per-frame bound on
	// `Task::tick()` calls.
	int pending_timeout_ms = 30000;
	int pending_ticks_per_frame = 8;

	// TASK-038: the opt-in call trace. `trace_recorder` is null unless the
	// switch named a file, which is what makes "off" the cheap path everywhere.
	MCPTrace::Config trace_config;
	MCPTrace::Recorder *trace_recorder = nullptr;

	// TASK-044: the opt-in before/after capture, an extension of the trace
	// above. `capture_engine` is null unless `--mcp-capture` named a mode *and* a
	// trace file is open - the capture line is a line in that file - which is
	// what makes "off" (the default) the unchanged request path.
	MCPCapture::Config capture_config;
	MCPCapture::Engine *capture_engine = nullptr;

	void _start_service();
	void _register_tools();
	void _shutdown();
	int _get_int_setting(const String &p_name, int p_default) const;
	bool _get_bool_setting(const String &p_name, bool p_default) const;

	// Releases a server instance whose SceneTree never showed up (see
	// bootstrap()). Static so that the instance can be deleted by a callable
	// that does not reference it.
	static void _retire_unattached();

protected:
	static void _bind_methods();
	void _notification(int p_what);
	// TASK-063 (a): `ClassDB::bind_method` needs a `String`-returning method, and
	// the accessor itself answers a `const char *` (the three states are literals,
	// so nothing should have to allocate to ask which one it is).
	String _get_endpoint_state_bind() const;

public:
	// Owned by register_types.cpp; public so that module registration can set
	// it without a friend declaration.
	static MCPServer *singleton;

	static MCPServer *get_singleton() { return singleton; }

	MCPServer();
	~MCPServer();

	// Deferred attachment to the SceneTree root (see register_types.cpp).
	void bootstrap();

	// Drives the transport. `_process` itself is a GDVIRTUAL on Node in 4.8, so
	// the pump is hooked through NOTIFICATION_PROCESS instead.
	void pump_frame(double p_delta);

	// MCPHttpRequestSink.
	void handle_jsonrpc_request(const String &p_body, MCPHttpOutcome &r_outcome) override;
	String build_deferred_body(const MCPDeferred::Completion &p_completion) override;
	String get_status_body() override;

	// Diagnostics; intentionally not exposed through tools/list.
	int get_port() const { return port; }
	bool is_listening() const { return listening; }
	// TASK-063 (a): the recorded startup outcome. `get_endpoint_state()` answers
	// the three states above as one machine-readable word, so
	// `get_port() == 0` is never the only thing a caller can learn from a process
	// whose endpoint never came up. Read-only, and deliberately not a tool: this
	// is what an in-process caller (the module's own tests, a debugger, a future
	// diagnostic tool) can ask when there is no endpoint to ask over.
	const char *get_endpoint_state() const {
		switch (endpoint_state) {
			case ENDPOINT_LISTENING:
				return "listening";
			case ENDPOINT_BIND_FAILED:
				return "bind_failed";
			case ENDPOINT_NOT_REQUESTED:
				break;
		}
		return "not_requested";
	}
	bool is_endpoint_bind_failed() const { return endpoint_state == ENDPOINT_BIND_FAILED; }
	int get_requested_port() const { return requested_port; }
	const String &get_endpoint_state_reason() const { return endpoint_state_reason; }
	// All of it at once, for a caller that wants one object (and for a doctest
	// that has no editor and no socket).
	Dictionary debug_endpoint_state() const;
	int get_frame_count() const { return frame_count; }
	int get_tool_count() const { return registry.get_visible_tool_count(is_editor); }
	// Requests waiting for a later frame (GDR-20 point 5).
	int get_pending_count() const { return http_server != nullptr ? http_server->get_pending_count() : 0; }
	// TASK-052: the ceiling the transport applies to a deferred request
	// (`mcp_server/pending_timeout_ms`, resolved once at startup). A deferred
	// tool's own deadline can only *lower* it
	// (`MCPJsonRpc::_effective_timeout`, mcp_jsonrpc.cpp:245-253), and a tool
	// that has to answer "the child I started was killed" rather than "the
	// request expired" needs the number the transport will really use. Read-only,
	// like the three diagnostics above.
	int get_pending_timeout_ms() const { return pending_timeout_ms; }
	MCPToolRegistry &get_registry() { return registry; }
	// TASK-038 diagnostics: the resolved switch and the recorder's own state.
	// Intentionally not exposed through `tools/list`, and deliberately not added
	// to `GET /mcp` either - the status body is an existing contract and this
	// task is not allowed to change one.
	bool is_trace_enabled() const { return trace_recorder != nullptr && trace_recorder->is_active(); }
	const MCPTrace::Config &get_trace_config() const { return trace_config; }
	// TASK-044 diagnostics, on the same terms as the trace's two: not in
	// `tools/list`, not in `GET /mcp`, so no existing contract moves.
	bool is_capture_enabled() const { return capture_engine != nullptr && capture_engine->is_active(); }
	const MCPCapture::Config &get_capture_config() const { return capture_config; }
};
