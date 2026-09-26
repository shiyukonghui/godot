/**************************************************************************/
/*  test_mcp_server.cpp                                                   */
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

// NOTE: this translation unit deliberately does NOT include
// "test_mcp_server.h". That header holds the TEST_CASEs and is pulled into
// `tests/test_main.cpp` through `modules/modules_tests.gen.h`; including it here
// as well would register every test case twice. The definitions below are
// matched against the declarations in the header by the linker.

#include "../mcp_deferred.h"
#include "../tools/project_read_template.h"
#include "../tools/registration.h"
#include "../tools/tool_builder.h"
// TASK-092 (item B2): the fake deferred task publishes its file through the
// module's own write primitive - the one place a `MutationScope` is opened -
// so the file-side half of a deferred call has a deterministic source. This
// translation unit deliberately does not include `test_mcp_server.h`, so the
// declaration has to be pulled in here.
#include "../tools/tool_helpers.h"

#include "core/config/engine.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"

namespace TestMCPServer {

Vector<uint8_t> to_bytes(const String &p_text) {
	CharString utf8 = p_text.utf8();
	Vector<uint8_t> bytes;
	bytes.resize(utf8.length());
	for (int i = 0; i < utf8.length(); i++) {
		bytes.write[i] = (uint8_t)utf8[i];
	}
	return bytes;
}

Variant parse_json(const String &p_text) {
	JSON json;
	if (json.parse(p_text) != OK) {
		return Variant();
	}
	return json.get_data();
}

String canonical(const Variant &p_value) {
	return JSON::stringify(p_value);
}

void build_project_registry(MCPToolRegistry &r_registry) {
	register_project_read_template_tools(r_registry);
}

void build_all_tools_registry(MCPToolRegistry &r_registry) {
	register_all_tools(r_registry);
}

Variant unused_handler(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	r_error = MCPToolError::invalid_params("unused");
	return Variant();
}

static Variant _unused_handler(const Dictionary &p_args, MCPToolError &r_error) {
	return unused_handler(p_args, r_error);
}

// TASK-003 section 1.6: `MCPToolRegistry::register_tool()` is private, so a
// probe is declared exactly like a real tool - through the builder, with
// channel / verb / scope / mutating all explicit (GDR-16 / GDR-18). The return
// value is `ToolBuilder::register_into()`'s, so a test can assert that a bad
// declaration never reaches the table.
bool register_probe(MCPToolRegistry &r_registry, const String &p_name, const String &p_channel, const String &p_verb, MCPToolScope p_scope) {
	MCPTools::ToolBuilder builder(p_name, p_name + " description");
	builder.channel(p_channel).verb(p_verb).scope(p_scope).mutating(false).schema(MCPTools::empty_object_schema()).handler(_unused_handler);
	return builder.register_into(r_registry);
}

// A handler that always fails with -32001 and a suggestion, so the JSON-RPC
// mapping of a tool error can be observed without depending on the file system.
static Variant _not_found_handler(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	r_error = MCPToolError::not_found("Probe resource 'x'", "Create it first");
	return Variant();
}

static Variant _not_implemented_handler(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	r_error = MCPToolError::not_implemented("probe feature", "Wait for a later batch");
	return Variant();
}

static void _register_scope_tool(MCPToolRegistry &r_registry, const String &p_name, const String &p_channel, const String &p_verb, MCPToolScope p_scope) {
	register_probe(r_registry, p_name, p_channel, p_verb, p_scope);
}

void build_scope_registry(MCPToolRegistry &r_registry) {
	// GDR-19 section 17.3 does not register an `EDITOR` scope tool in a game
	// process, and the doctest process is *not* an editor. The scope filtering
	// test needs the tool in the table, so the Engine's editor hint is flipped
	// for exactly that one registration and restored before returning - no
	// other test case can observe it.
	Engine *engine = Engine::get_singleton();
	const bool was_editor = engine != nullptr && engine->is_editor_hint();
	if (engine != nullptr) {
		engine->set_editor_hint(true);
	}
	_register_scope_tool(r_registry, "editor_get_scope_probe", "editor", "get", MCPToolScope::EDITOR);
	if (engine != nullptr) {
		engine->set_editor_hint(was_editor);
	}
	_register_scope_tool(r_registry, "running_game_get_scope_probe", "running_game", "get", MCPToolScope::GAME);
	_register_scope_tool(r_registry, "project_get_scope_probe", "project", "get", MCPToolScope::BOTH);
}

void build_editor_process_registry(MCPToolRegistry &r_registry) {
	// `ToolBuilder::register_into()` skips a `scope = EDITOR` tool in a game
	// process, and the doctest process is not an editor. Flipping the hint for
	// exactly this registration (and restoring it before returning) is the only
	// way to observe the editor-process table from the test binary; the same
	// idiom as `build_scope_registry`.
	Engine *engine = Engine::get_singleton();
	const bool was_editor = engine != nullptr && engine->is_editor_hint();
	if (engine != nullptr) {
		engine->set_editor_hint(true);
	}
	register_all_tools(r_registry);
	if (engine != nullptr) {
		engine->set_editor_hint(was_editor);
	}
}

void build_error_probe_registry(MCPToolRegistry &r_registry) {
	MCPTools::ToolBuilder builder("project_get_error_probe", "error probe");
	builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(MCPTools::empty_object_schema()).handler(_not_found_handler);
	builder.register_into(r_registry);

	MCPTools::ToolBuilder unimplemented("project_get_unimplemented_probe", "unimplemented probe");
	unimplemented.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(MCPTools::empty_object_schema()).handler(_not_implemented_handler);
	unimplemented.register_into(r_registry);
}

// NOTE: the `ScratchProject` fixture used by the `project_read_analysis` tests
// is defined inline in tests/test_mcp_server.h: this translation unit does not
// include that header (it would register every TEST_CASE twice), so a
// definition here could not see the declarations.

// ---------------------------------------------------------------------------
// GDR-20 / TASK-011: a *controlled fake pending tool*, test only.
//
// The deferred channel's state machine is proven on this tool before any real
// cross-frame tool is trusted with it (TASK-011 section 1.8). It is a real tool
// in every other respect - it is declared through `ToolBuilder` and reached
// through the real `MCPJsonRpc::dispatch` path - so the proof covers argument
// validation, the dispatch-to-task handover and the queue, not just the queue.
//
// The task is steered entirely by its arguments, so one tool covers every class
// of the state machine: how many ticks it takes (`ticks`), whether it completes
// or fails (`fail`), and its own deadline (`timeout_ms`). `payload` makes two
// concurrent requests distinguishable, which is what the interleaving test needs.
// ---------------------------------------------------------------------------

// Number of fake tasks alive right now; the leak assertions compare it before
// and after.
static int fake_pending_live_tasks = 0;

int fake_pending_live() {
	return fake_pending_live_tasks;
}

class FakePendingTask : public MCPDeferred::Task {
public:
	FakePendingTask(const String &p_payload, int p_ticks_to_finish, uint64_t p_timeout_ms, bool p_fail, const String &p_write_path = String()) :
			payload(p_payload),
			ticks_to_finish(p_ticks_to_finish),
			timeout_ms(p_timeout_ms),
			fail(p_fail),
			write_path(p_write_path) {
		fake_pending_live_tasks++;
	}

	~FakePendingTask() override {
		fake_pending_live_tasks--;
	}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_now_ms;
		ticks++;

		if (ticks_to_finish < 0 || ticks < ticks_to_finish) {
			return MCPDeferred::TickResult::pending();
		}
		if (fail) {
			return MCPDeferred::TickResult::failed(MCPToolError::tool_state(
					vformat("fake pending failure for '%s'", payload), "fake suggestion"));
		}

		// TASK-092 (item B2): a deferred task's disk work happens **in its own
		// tick**, which is exactly what the per-call recorder could not see. A
		// task that writes here is what the "a deferred call's file effects reach
		// the completion" case needs; `write_path` empty (every pre-TASK-092
		// use of this class) writes nothing at all.
		if (!write_path.is_empty()) {
			MCPTools::publish_text_atomically(write_path, "written in a deferred tick\n" + payload + "\n");
		}

		Dictionary result;
		result["payload"] = payload;
		result["ticks"] = ticks;
		result["frame"] = p_frame;
		return MCPDeferred::TickResult::done(result);
	}

	uint64_t get_timeout_ms() const override { return timeout_ms; }
	String describe() const override { return vformat("fake pending '%s'", payload); }

	int ticks = 0;

private:
	String payload;
	// < 0 = never finishes (the timeout class).
	int ticks_to_finish = 1;
	uint64_t timeout_ms = 0;
	bool fail = false;
	// Non-empty: the finishing tick publishes this `res://` path through the
	// module's own publish primitive, so the file-effect recorder sees it.
	String write_path;
};

static MCPDeferred::Task *_fake_pending_handler(const Dictionary &p_args, MCPToolError &r_error) {
	const Variant refuse = p_args.get("refuse", Variant());
	if (refuse.get_type() == Variant::BOOL && (bool)refuse) {
		r_error = MCPToolError::invalid_params("fake pending tool refuses this call");
		return nullptr;
	}

	String payload = "fake-default";
	const Variant payload_value = p_args.get("payload", Variant());
	if (payload_value.get_type() == Variant::STRING) {
		payload = payload_value;
	}
	int64_t ticks = 1;
	if (!MCPTools::optional_int(p_args, "ticks", 1, ticks, r_error)) {
		return nullptr;
	}
	int64_t timeout_ms = 0;
	if (!MCPTools::optional_int(p_args, "timeout_ms", 0, timeout_ms, r_error)) {
		return nullptr;
	}
	bool fail = false;
	if (!MCPTools::optional_bool(p_args, "fail", false, fail, r_error)) {
		return nullptr;
	}
	String write_path;
	if (!MCPTools::optional_string(p_args, "write_path", String(), write_path, r_error)) {
		return nullptr;
	}
	return memnew(FakePendingTask(payload, (int)ticks, (uint64_t)timeout_ms, fail, write_path));
}

// A plain immediate tool of the same registry, so that "an ordinary request is
// still answered while a deferred one is in flight" is observable next to the
// pending table rather than only inside it.
static Variant _fake_immediate_handler(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	(void)r_error;
	Dictionary result;
	result["probe"] = true;
	return result;
}

// TASK-032 D4: the registry's unknown-argument gate refuses a name the tool's
// *schema* does not declare, for every tool - including this test-only one. A
// fake probe that read `payload` while declaring nothing would be refused before
// its handler ever ran, so the five names `_fake_pending_handler` actually reads
// are declared here with the types they are read as. An empty schema
// (`MCPTools::empty_object_schema()`) stays correct for the probes that take no
// argument at all.
static Dictionary _fake_pending_schema() {
	Dictionary properties;
	Dictionary payload;
	payload["type"] = "string";
	properties["payload"] = payload;
	Dictionary refuse;
	refuse["type"] = "boolean";
	properties["refuse"] = refuse;
	Dictionary ticks;
	ticks["type"] = "integer";
	properties["ticks"] = ticks;
	Dictionary timeout_ms;
	timeout_ms["type"] = "integer";
	properties["timeout_ms"] = timeout_ms;
	Dictionary fail;
	fail["type"] = "boolean";
	properties["fail"] = fail;
	// TASK-092 (item B2): a path the finishing tick publishes through the
	// module's own primitive, so a deferred call's file-side effect has a
	// deterministic source. Declared here because the unknown-argument gate
	// refuses any name a schema does not carry.
	Dictionary write_path;
	write_path["type"] = "string";
	properties["write_path"] = write_path;

	Dictionary schema;
	schema["type"] = "object";
	schema["properties"] = properties;
	schema["required"] = Array();
	return schema;
}

void build_deferred_probe_registry(MCPToolRegistry &r_registry) {
	MCPTools::ToolBuilder deferred("project_get_fake_pending", "controlled fake deferred tool (test only)");
	deferred.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(_fake_pending_schema()).pending_handler(_fake_pending_handler);
	deferred.register_into(r_registry);

	MCPTools::ToolBuilder immediate("project_get_fake_immediate", "controlled immediate tool (test only)");
	immediate.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(MCPTools::empty_object_schema()).handler(_fake_immediate_handler);
	immediate.register_into(r_registry);
}

// ---------------------------------------------------------------------------
// Helpers that drive the pending table from a test.
// ---------------------------------------------------------------------------

// The `ID` and `payload` of the `tools/call` body that starts one fake request.
String fake_call_body(int p_id, const String &p_payload, int p_ticks, int p_timeout_ms, bool p_fail) {
	const String fail_json = p_fail ? "true" : "false";
	return vformat(
			"{\"jsonrpc\":\"2.0\",\"id\":%d,\"method\":\"tools/call\",\"params\":{\"name\":\"project_get_fake_pending\","
			"\"arguments\":{\"payload\":\"%s\",\"ticks\":%d,\"timeout_ms\":%d,\"fail\":%s}}}",
			p_id, p_payload, p_ticks, p_timeout_ms, fail_json);
}

// Wraps `MCPDeferred::Completion` into a comparable one-line summary, so a test
// can assert on the pair that must never cross.
String completion_key(const MCPDeferred::Completion &p_completion) {
	const String kind = p_completion.kind == MCPDeferred::CompletionKind::DONE ? "DONE" : (p_completion.kind == MCPDeferred::CompletionKind::TIMEOUT ? "TIMEOUT" : "FAILED");
	return vformat("%d/%s/%s", (int64_t)p_completion.connection_id, p_completion.id_json, kind);
}

} // namespace TestMCPServer