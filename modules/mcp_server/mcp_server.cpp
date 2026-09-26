/**************************************************************************/
/*  mcp_server.cpp                                                        */
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

#include "mcp_server.h"

#include "mcp_frame_clock.h"
#include "mcp_jsonrpc.h"
#include "tools/registration.h"
#include "tools/tool_builder.h"

#include "core/config/engine.h"
#include "core/config/project_settings.h"
#include "core/core_bind.h"
#include "core/io/json.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/object/message_queue.h"
#include "core/os/os.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"

MCPServer *MCPServer::singleton = nullptr;

namespace MCPPort {

static const int DEFAULT_EDITOR_PORT = 9877;
static const int MAX_PORT = 65535;

static bool _try_parse_port(const String &p_text, int &r_port) {
	if (!p_text.is_valid_int()) {
		return false;
	}
	const int parsed = p_text.to_int();
	if (parsed < 0 || parsed > MAX_PORT) {
		return false;
	}
	r_port = parsed;
	return true;
}

MCPPortConfig parse(const Vector<String> &p_cmdline_args, bool p_has_setting, int p_setting_port, bool p_is_editor) {
	MCPPortConfig config;
	// Default: the editor listens on 9877 (same port as the GDExtension addon),
	// while a game process does not listen at all unless asked to.
	config.port = p_is_editor ? DEFAULT_EDITOR_PORT : 0;

	int explicit_port = -1;
	const int arg_count = p_cmdline_args.size();
	for (int i = 0; i < arg_count; i++) {
		const String &arg = p_cmdline_args[i];
		if (arg.begins_with("--mcp-port=")) {
			int parsed = 0;
			if (_try_parse_port(arg.substr(String("--mcp-port=").length()), parsed)) {
				explicit_port = parsed;
			}
		} else if (arg == "--mcp-port") {
			// `--mcp-port N` form.
			if (i + 1 < arg_count) {
				int parsed = 0;
				if (_try_parse_port(p_cmdline_args[i + 1], parsed)) {
					explicit_port = parsed;
				}
				i++;
			}
		}
	}

	if (p_has_setting && p_setting_port > 0 && p_setting_port <= MAX_PORT) {
		config.port = p_setting_port;
		config.from_project_setting = true;
	}

	if (explicit_port >= 0) {
		config.port = explicit_port;
		config.explicit_cmdline = true;
	}

	return config;
}

bool should_listen(bool p_is_editor, const MCPPortConfig &p_config, bool p_enabled_in_game) {
	if (p_config.port <= 0) {
		return false;
	}
	if (p_is_editor) {
		return true;
	}
	// A game process must opt in explicitly (REQUIREMENTS C4).
	return p_config.explicit_cmdline || p_enabled_in_game;
}

} // namespace MCPPort

namespace MCPPendingTimeout {

int effective_ms(int p_configured_ms) {
	// TASK-014 R-3: `<= 0` is not a deadline. The transport reads 0 as "no
	// deadline" and the frame-waiting deferred tools declare no deadline of their
	// own, so a configured 0 would leave them able to hang forever - the exact
	// failure GDR-20 point 4 removes. A positive value is passed through
	// unchanged, so the setting stays a working knob.
	return p_configured_ms <= 0 ? DEFAULT_MS : p_configured_ms;
}

} // namespace MCPPendingTimeout

MCPServer::MCPServer() {
	set_process(false);
}

MCPServer::~MCPServer() {
	_shutdown();
}

void MCPServer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bootstrap"), &MCPServer::bootstrap);
	ClassDB::bind_method(D_METHOD("get_port"), &MCPServer::get_port);
	ClassDB::bind_method(D_METHOD("is_listening"), &MCPServer::is_listening);
	ClassDB::bind_method(D_METHOD("get_frame_count"), &MCPServer::get_frame_count);
	ClassDB::bind_method(D_METHOD("get_tool_count"), &MCPServer::get_tool_count);
	// TASK-063 (a): the recorded startup outcome, reachable from GDScript as well
	// (`get_port()` alone cannot say *why* it is 0). Not a tool and not part of
	// the HTTP contract - see the comment on the accessors.
	ClassDB::bind_method(D_METHOD("get_endpoint_state"), &MCPServer::_get_endpoint_state_bind);
	ClassDB::bind_method(D_METHOD("get_endpoint_state_reason"), &MCPServer::get_endpoint_state_reason);
	ClassDB::bind_method(D_METHOD("get_requested_port"), &MCPServer::get_requested_port);
	ClassDB::bind_method(D_METHOD("is_endpoint_bind_failed"), &MCPServer::is_endpoint_bind_failed);
}

String MCPServer::_get_endpoint_state_bind() const {
	return String(get_endpoint_state());
}

Dictionary MCPServer::debug_endpoint_state() const {
	Dictionary state;
	state["state"] = String(get_endpoint_state());
	state["listening"] = listening;
	state["port"] = port;
	state["requested_port"] = requested_port;
	state["reason"] = endpoint_state_reason;
	state["is_editor"] = is_editor;
	state["tool_count"] = registry.get_visible_tool_count(is_editor);
	return state;
}
void MCPServer::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_PROCESS: {
			pump_frame(get_process_delta_time());
		} break;
		case NOTIFICATION_EXIT_TREE: {
			_shutdown();
		} break;
		case NOTIFICATION_PREDELETE: {
			if (singleton == this) {
				singleton = nullptr;
				if (CoreBind::Engine::get_singleton() != nullptr && CoreBind::Engine::get_singleton()->has_singleton("MCPServer")) {
					CoreBind::Engine::get_singleton()->unregister_singleton("MCPServer");
				}
			}
			_shutdown();
		} break;
		default: {
			Node::_notification(p_what);
		} break;
	}
}

void MCPServer::_retire_unattached() {
	// Disable the module for good and release the instance. A Node that can
	// never enter a tree must not stay alive: `Node::print_orphan_nodes()`
	// reports every tree-less Node in ObjectDB and the engine's own unit-test
	// suite asserts on the exact output of one such probe, so leaving this
	// instance behind makes an unrelated engine test fail.
	MCPServer *server = singleton;
	singleton = nullptr;
	if (CoreBind::Engine::get_singleton() != nullptr && CoreBind::Engine::get_singleton()->has_singleton("MCPServer")) {
		CoreBind::Engine::get_singleton()->unregister_singleton("MCPServer");
	}
	if (server != nullptr) {
		server->_shutdown();
		memdelete(server);
	}
}

void MCPServer::bootstrap() {
	if (service_started) {
		return;
	}

	SceneTree *tree = SceneTree::get_singleton();
	if (tree == nullptr || tree->get_root() == nullptr) {
		// SCENE level initialization happens before the SceneTree exists, so
		// the very first frames may still be too early.
		bootstrap_attempts++;
		if (bootstrap_attempts > 600) {
			ERR_PRINT("[MCP] SceneTree never became available; MCP server disabled.");
			// This is the engine's `--test` harness, which has no SceneTree at
			// all: retire the instance instead of leaving a tree-less Node
			// behind (see _retire_unattached).
			if (MessageQueue::get_singleton() != nullptr) {
				MessageQueue::get_singleton()->push_callable(callable_mp_static(&MCPServer::_retire_unattached));
			} else {
				_retire_unattached();
			}
			return;
		}
		if (MessageQueue::get_singleton() != nullptr) {
			MessageQueue::get_singleton()->push_callable(callable_mp(this, &MCPServer::bootstrap));
		}
		return;
	}

	set_name("MCPServer");
	tree->get_root()->add_child(this);
	set_process(true);

	_start_service();
}
void MCPServer::pump_frame(double p_delta) {
	(void)p_delta;
	// GDR-20 point 7: the frame clock of the deferred channel is the SceneTree's
	// frame counter, not a private counter of this node - the tools have to see
	// the same number of frames the game actually rendered, and a test can drive
	// the transport with an arbitrary frame number. A process without a
	// SceneTree (the doctest binary runs the pump through this same function)
	// keeps the private counter so that the diagnostics still move.
	SceneTree *tree = SceneTree::get_singleton();
	if (tree != nullptr) {
		frame_count = (int)tree->get_frame();
	} else {
		frame_count++;
	}
	// TASK-092 (item B4): one sample per frame for the deferred drivers' stable
	// cost estimate. This is the only caller, so "the duration of a frame" means
	// "the gap between two pumps", which is the frame the tools really run in.
	// It is one clock read per frame: no allocation, no lock, no I/O.
	{
		OS *os = OS::get_singleton();
		if (os != nullptr) {
			MCPFrameClock::note_frame(os->get_ticks_usec());
		}
	}
	// TASK-044: the frame clock of an in-flight capture is handed in *before*
	// the transport poll, so a capture armed while a request is answered is
	// completed one frame later and not in the frame it was taken in.
	if (capture_engine != nullptr && capture_engine->is_active()) {
		capture_engine->begin_frame((int64_t)frame_count);
	}
	if (http_server != nullptr) {
		// Everything (socket polling, parsing, tool execution, advancing the
		// deferred tasks and writing the responses back) happens here, on the
		// main thread, once per frame.
		http_server->poll(max_requests_per_frame, (int64_t)frame_count);
	}
	// TASK-044: strictly after the responses of this frame. The encoding, the
	// PNGs, the pixel comparison and the appended log line of every capture
	// whose call was answered at least one rendered frame ago happen here - the
	// response was produced above and never waits for any of it.
	if (capture_engine != nullptr && capture_engine->is_active()) {
		capture_engine->tick((int64_t)frame_count);
	}
}
void MCPServer::_shutdown() {
	if (http_server != nullptr) {
		http_server->stop();
		memdelete(http_server);
		http_server = nullptr;
	}
	// TASK-038: the trace file is flushed and closed with everything else, so an
	// orderly shutdown never loses the last line. `close()` flushes first.
	if (trace_recorder != nullptr) {
		trace_recorder->close();
		memdelete(trace_recorder);
		trace_recorder = nullptr;
	}
	// TASK-044: the capture engine reports into the trace file, so it is torn
	// down next. In-flight captures are dropped rather than written: there is no
	// longer a file to describe them in.
	if (capture_engine != nullptr) {
		capture_engine->stop();
		memdelete(capture_engine);
		capture_engine = nullptr;
	}
	listening = false;
	port = 0;
	set_process(false);
}

void MCPServer::handle_jsonrpc_request(const String &p_body, MCPHttpOutcome &r_outcome) {
	// GDR-20: the dispatch either answers now or hands over a task for the
	// transport to advance; both are carried by the outcome.
	//
	// TASK-038: `p_trace` is true only while a recorder is open. With the trace
	// switched off (the default) the dispatcher is asked for exactly what it was
	// asked for before this task existed, and `r_outcome.trace` stays untraceable.
	const bool trace_enabled = trace_recorder != nullptr && trace_recorder->is_active();

	// TASK-044: the whole cost this feature adds to a request is the one
	// framebuffer copy below, taken *before* the tool runs so that "before" means
	// "the frame the call was received in". `capture_token` is -1 for everything
	// that is not a captured `tools/call`, which is every request in the default
	// configuration.
	const bool capture_enabled = capture_engine != nullptr && capture_engine->is_active();
	int capture_token = -1;
	if (capture_enabled) {
		String capture_tool;
		if (MCPCapture::payload_calls_tool(p_body, capture_tool)) {
			// TASK-092 (item B2): a deferred call is captured like any other. The
			// `before` frame is the frame the request was read in (which is what
			// `arm()` has always taken); the slot is **not** finished here,
			// because the call has not run yet - it is finished by the transport
			// when the completion arrives, with the `seq` of the line the deferred
			// call will be written as. TASK-090 answered `arm_unavailable` for this
			// case and the reason on the line said so; that verdict is now a real
			// capture whose pixel difference is the deferred call's own effect.
			capture_token = capture_engine->arm(capture_tool);
		}
	}

	const MCPJsonRpc::Dispatch dispatched = MCPJsonRpc::dispatch(p_body, registry, is_editor, (uint64_t)pending_timeout_ms, trace_enabled);
	r_outcome.body = dispatched.response.body;
	r_outcome.http_status = dispatched.response.http_status;
	r_outcome.close = false;
	r_outcome.deferred = dispatched.deferred;
	r_outcome.task = dispatched.task;
	r_outcome.id_json = dispatched.id_json;
	r_outcome.timeout_ms = dispatched.timeout_ms;
	r_outcome.trace = dispatched.trace;

	if (capture_enabled && capture_token >= 0) {
		if (dispatched.deferred) {
			// TASK-092 (item B2): the capture is finished when the call really
			// ends, not when it is accepted - see `finish_deferred_capture`. The
			// token travels on the record, which travels with the pending entry,
			// so the transport can hand it back at completion. `capture_present`
			// stays false until then, which is exactly right: the call line does
			// not exist yet.
			r_outcome.trace.capture_token = capture_token;
		} else {
			// The call line is the *next* request line the recorder writes: the
			// transport writes it immediately after this call returns, with no other
			// line in between, so its `seq` is knowable here - and the capture line,
			// appended a frame later, carries the same number.
			const int capture_seq = trace_recorder->get_seq() + 1;
			if (capture_engine->finish(capture_token, dispatched.trace.ok, capture_seq)) {
				r_outcome.trace.capture_present = true;
				r_outcome.trace.capture_mode = MCPCapture::mode_name(capture_engine->get_config().mode);
				r_outcome.trace.capture_viewport = capture_engine->get_viewport_name();
				r_outcome.trace.capture_status = capture_engine->call_line_status(capture_token);
				r_outcome.trace.capture_reason = capture_engine->call_line_reason(capture_token);
				r_outcome.trace.capture_token = capture_token;
			}
		}
	}
}
bool MCPServer::finish_deferred_capture(MCPTrace::Record &r_record, int p_seq) {
	if (capture_engine == nullptr || !capture_engine->is_active()) {
		return false;
	}
	const int token = r_record.capture_token;
	if (token < 0) {
		return false;
	}
	if (!capture_engine->finish(token, r_record.ok, p_seq)) {
		// `on_error` mode and the call succeeded: the picture is dropped and the
		// call line carries no `capture` member at all (the engine's own rule).
		r_record.capture_token = -1;
		return false;
	}
	r_record.capture_present = true;
	r_record.capture_mode = MCPCapture::mode_name(capture_engine->get_config().mode);
	r_record.capture_viewport = capture_engine->get_viewport_name();
	r_record.capture_status = capture_engine->call_line_status(token);
	r_record.capture_reason = capture_engine->call_line_reason(token);
	return true;
}

void MCPServer::discard_deferred_capture(int p_token) {
	if (capture_engine != nullptr && capture_engine->is_active()) {
		capture_engine->discard(p_token);
	}
}
String MCPServer::build_deferred_body(const MCPDeferred::Completion &p_completion) {
	// The wire shape stays in the JSON-RPC layer, exactly like the immediate
	// path: a success is the same `content` envelope `content_result()` builds,
	// and a failure is the same `error` object any tool error becomes.
	if (p_completion.kind == MCPDeferred::CompletionKind::DONE) {
		return MCPJsonRpc::build_result_raw(p_completion.id_json, MCPTools::content_result(p_completion.result));
	}
	return MCPJsonRpc::build_error_raw(p_completion.id_json, p_completion.error.code, p_completion.error.message, p_completion.error.data);
}
String MCPServer::get_status_body() {
	Dictionary status;
	status["status"] = "ok";
	status["server"] = "godot-mcp-rs";
	status["transport"] = "streamable-http";
	status["tools"] = registry.get_visible_tool_count(is_editor);
	status["port"] = port;
	status["is_editor"] = is_editor;
	status["frame_count"] = frame_count;
	status["listening"] = listening;
	status["connections"] = http_server != nullptr ? http_server->get_connection_count() : 0;
	// GDR-20 point 5: both counts the cleanup rule is judged by are observable.
	status["pending"] = http_server != nullptr ? http_server->get_pending_count() : 0;
	status["pending_connections"] = http_server != nullptr ? http_server->get_pending_connection_count() : 0;
	return JSON::stringify(status);
}

int MCPServer::_get_int_setting(const String &p_name, int p_default) const {
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr) {
		return p_default;
	}

	// Both the section style name (`mcp_server/max_body_bytes`) and the dotted
	// alias (`mcp_server.max_body_bytes`) are accepted.
	Vector<String> names;
	names.push_back(p_name);
	const String alias = p_name.replace("/", ".");
	if (alias != p_name) {
		names.push_back(alias);
	}

	for (int i = 0; i < names.size(); i++) {
		if (!settings->has_setting(names[i])) {
			continue;
		}
		const Variant value = settings->get_setting(names[i]);
		if (value.get_type() == Variant::INT || value.get_type() == Variant::FLOAT) {
			return (int)value;
		}
	}
	return p_default;
}

bool MCPServer::_get_bool_setting(const String &p_name, bool p_default) const {
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr) {
		return p_default;
	}

	Vector<String> names;
	names.push_back(p_name);
	const String alias = p_name.replace("/", ".");
	if (alias != p_name) {
		names.push_back(alias);
	}

	for (int i = 0; i < names.size(); i++) {
		if (!settings->has_setting(names[i])) {
			continue;
		}
		const Variant value = settings->get_setting(names[i]);
		if (value.get_type() == Variant::BOOL) {
			return (bool)value;
		}
	}
	return p_default;
}

void MCPServer::_register_tools() {
	if (registry.get_tool_count() > 0) {
		return;
	}

	// Every implemented group registers itself through the single shared entry
	// point; the group files own their tools (TASK-002 section 2.2.1). Tools that
	// have not been ported yet are not registered at all, so they can never show
	// up in `tools/list` (GDR-7).
	register_all_tools(registry);
}
void MCPServer::_start_service() {
	if (service_started) {
		return;
	}
	service_started = true;

	is_editor = Engine::get_singleton() != nullptr && Engine::get_singleton()->is_editor_hint();

	_register_tools();

	max_body_bytes = _get_int_setting("mcp_server/max_body_bytes", 8 * 1024 * 1024);
	max_requests_per_frame = _get_int_setting("mcp_server/max_requests_per_frame", 8);
	if (max_requests_per_frame < 1) {
		max_requests_per_frame = 1;
	}
	connection_idle_seconds = (double)_get_int_setting("mcp_server/connection_idle_seconds", 30);
	if (connection_idle_seconds < 1.0) {
		connection_idle_seconds = 1.0;
	}

	// GDR-20: the ceiling of a deferred request (30 s by default) and the
	// per-frame tick budget. A budget below 1 would stall every pending request
	// forever, so it is clamped like `max_requests_per_frame`.
	//
	// TASK-014 R-3: a ceiling of 0 (or a negative value) is *not* a working
	// configuration. The transport reads 0 as "no deadline" and the frame-waiting
	// deferred tools declare no deadline of their own, so 0 would switch off the
	// module's only fallback for them. The M2 acceptance found the setting
	// accepted 0 silently (mcp_server.cpp used to fold a negative value into 0
	// and leave 0 alone); `MCPPendingTimeout::effective_ms` now maps `<= 0` to the
	// default and the startup line below reports both values.
	const int configured_pending_timeout_ms = _get_int_setting("mcp_server/pending_timeout_ms", MCPPendingTimeout::DEFAULT_MS);
	pending_timeout_ms = MCPPendingTimeout::effective_ms(configured_pending_timeout_ms);
	pending_ticks_per_frame = _get_int_setting("mcp_server/pending_ticks_per_frame", 8);
	if (pending_ticks_per_frame < 1) {
		pending_ticks_per_frame = 1;
	}
	if (pending_timeout_ms != configured_pending_timeout_ms) {
		WARN_PRINT(vformat("[MCP] mcp_server/pending_timeout_ms=%d is not a usable deadline (0 would switch the deferred fallback off); using %d ms",
				configured_pending_timeout_ms, pending_timeout_ms));
	}
	print_line(vformat("[MCP] pending_timeout_ms=%d (configured=%d) pending_ticks_per_frame=%d",
			pending_timeout_ms, configured_pending_timeout_ms, pending_ticks_per_frame));

	const bool enabled_in_game = _get_bool_setting("godot_mcp/enabled_in_game", false);

	ProjectSettings *settings = ProjectSettings::get_singleton();
	bool has_port_setting = false;
	int setting_port = 0;
	if (settings != nullptr && settings->has_setting("godot_mcp/port")) {
		const Variant value = settings->get_setting("godot_mcp/port");
		if (value.get_type() == Variant::INT || value.get_type() == Variant::FLOAT) {
			has_port_setting = true;
			setting_port = (int)value;
		}
	}

	Vector<String> cmdline_args;
	if (OS::get_singleton() != nullptr) {
		const List<String> args = OS::get_singleton()->get_cmdline_args();
		for (const String &arg : args) {
			cmdline_args.push_back(arg);
		}
	}

	// TASK-038: resolve the opt-in call trace exactly the way the port is
	// resolved (GDR-4): command line beats project setting beats the default, and
	// the default is "off" - no file is opened, and the transport is never given
	// a recorder, so nothing on the request path changes.
	{
		bool has_trace_setting = false;
		String setting_trace_path;
		if (settings != nullptr) {
			const char *const trace_setting_names[] = { "godot_mcp/trace_file", "godot_mcp.trace_file" };
			for (int i = 0; i < 2; i++) {
				if (!settings->has_setting(trace_setting_names[i])) {
					continue;
				}
				const Variant value = settings->get_setting(trace_setting_names[i]);
				if (value.get_type() == Variant::STRING) {
					has_trace_setting = true;
					setting_trace_path = (String)value;
					break;
				}
			}
		}

		trace_config = MCPTrace::parse(cmdline_args, has_trace_setting, setting_trace_path);

		if (trace_config.enabled) {
			trace_recorder = memnew(MCPTrace::Recorder);
			if (!trace_recorder->open(trace_config.path)) {
				// `open()` has already warned once; the recorder is dead but the
				// pointer stays valid (and inert) so `is_active()` is the single
				// question the transport asks.
				WARN_PRINT(vformat("[MCP] call trace could not be started for '%s'", trace_config.path));
			}
			if (trace_recorder->is_active()) {
				// The user has to be told that this file may contain project
				// content: it records the arguments of every tool call.
				print_line(vformat("[MCP] trace enabled: file=%s (records initialize / tools/list / every tools/call; arguments may contain project content)",
						trace_config.path));
			} else {
				print_line(vformat("[MCP] trace requested for '%s' but disabled (see the warning above)", trace_config.path));
			}
		} else {
			print_line("[MCP] trace=off (default; use --mcp-trace=<path> or godot_mcp/trace_file to enable)");
		}
	}

	// TASK-044: the capture extension, resolved exactly like the trace above and
	// only ever *after* it - a capture line is a line in the trace file, so the
	// two switches are not independent, and a capture without a trace is refused
	// with a warning instead of being silently ignored.
	{
		bool has_capture_setting = false;
		String setting_capture_value;
		if (settings != nullptr) {
			const char *const capture_setting_names[] = { "godot_mcp/capture", "godot_mcp.capture" };
			for (int i = 0; i < 2; i++) {
				if (!settings->has_setting(capture_setting_names[i])) {
					continue;
				}
				const Variant value = settings->get_setting(capture_setting_names[i]);
				if (value.get_type() == Variant::STRING) {
					has_capture_setting = true;
					setting_capture_value = (String)value;
					break;
				}
			}
		}

		capture_config = MCPCapture::parse(cmdline_args, has_capture_setting, setting_capture_value, trace_config.path);
		if (!capture_config.warning.is_empty()) {
			WARN_PRINT(vformat("[MCP] %s", capture_config.warning));
		}

		if (capture_config.mode != MCPCapture::Mode::OFF) {
			MCPCapture::Engine *engine = memnew(MCPCapture::Engine);
			if (engine->start(capture_config, trace_recorder, is_editor)) {
				capture_engine = engine;
			} else {
				// `start()` has already warned; the engine holds nothing.
				memdelete(engine);
			}
		} else {
			print_line("[MCP] capture=off (default; use --mcp-capture=on_error|every_call together with --mcp-trace=<path>)");
		}
	}

	port_config = MCPPort::parse(cmdline_args, has_port_setting, setting_port, is_editor);
	const bool listen = MCPPort::should_listen(is_editor, port_config, enabled_in_game);

	const char *source = "default";
	if (port_config.explicit_cmdline) {
		source = "cmdline";
	} else if (port_config.from_project_setting) {
		source = "project_setting";
	}

	print_line(vformat("[MCP] role=%s configured_port=%d source=%s listen=%s",
			is_editor ? "editor" : "game", port_config.port, source, listen ? "true" : "false"));

	// TASK-054 (O-12): the generation marker of this trace file. The file is
	// append-only and may be reused across runs, so the observer needs one line
	// per process that says where a generation begins. It is written here
	// because this is the first place that knows all of its fields - the port is
	// resolved just above, the trace file was opened earlier - and it goes
	// through the event-line path, so it consumes no request `seq` (the first
	// request of this process is still `seq == 1`). It is written whether or not
	// the server ends up listening: the file was opened either way, and a run
	// that failed to bind is exactly the kind of fact a trace should carry.
	if (trace_recorder != nullptr) {
		trace_recorder->record_event_line(MCPTrace::build_trace_opened_fields(is_editor, port_config.port, listen));
	}

	if (!listen) {
		port = 0;
		listening = false;
		print_line("[MCP] not listening (get_port()=0)");
		return;
	}

	http_server = memnew(MCPHttpServer);
	http_server->set_sink(this);
	http_server->set_trace_recorder(trace_recorder);
	http_server->set_max_body_bytes(max_body_bytes);
	http_server->set_connection_idle_seconds(connection_idle_seconds);
	http_server->set_pending_timeout_ms((uint64_t)pending_timeout_ms);
	http_server->set_pending_ticks_per_frame(pending_ticks_per_frame);

	const Error err = http_server->listen((uint16_t)port_config.port);
	if (err != OK) {
		// Binding failures must never take the engine down; the endpoint
		// simply stays disabled and get_port() reports 0.
		print_line(vformat("[MCP] bind failed on 127.0.0.1:%d (error=%d)", port_config.port, (int)err));
		WARN_PRINT(vformat("[MCP] bind failed on 127.0.0.1:%d; MCP server disabled", port_config.port));
		print_line("[MCP] get_port()=0 (MCP server disabled)");

		memdelete(http_server);
		http_server = nullptr;
		port = 0;
		listening = false;
		return;
	}

	port = port_config.port;
	listening = true;
	print_line(vformat("[MCP] listening on 127.0.0.1:%d (editor=%s, tools=%d)",
			port, is_editor ? "true" : "false", registry.get_visible_tool_count(is_editor)));
	// TASK-010 section 3.2: a *successful* bind gets an INFO line carrying the
	// port, the process role and where the port came from. The editor listens by
	// default (GDR-4), so an engine run that was never meant to serve MCP - the
	// obvious one being `--import`, which is an editor process and therefore
	// binds 9877 unless told otherwise - used to do so silently; the INFO line
	// makes that visible in the log next to the role line printed above.
	print_line(vformat("[MCP] INFO: MCP server is ready on 127.0.0.1:%d as the %s process (port source=%s, tools=%d)",
			port, is_editor ? "editor" : "game", source, registry.get_visible_tool_count(is_editor)));
}
