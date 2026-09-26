/**************************************************************************/
/*  running_game_assertion.cpp                                            */
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
#include "running_game_assertion.h"

#include "../mcp_deferred.h"
#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/object/script_language.h"
#include "core/os/os.h"
#include "core/string/ustring.h"
#include "core/templates/list.h"
#include "core/variant/callable.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// running_game_assert_node_state (old `assert_node_state`)
//
// The migration source has two halves and they disagree; the game-side half is
// the one that can answer, so it is the authority here:
//
//   * `godot_mcp_gdext/src/commands/test.rs:382-401` forwards the arguments over
//     the `user://` file IPC and returns whatever came back;
//   * the game side that really answers is
//     `addons/godot_mcp/mcp_game_inspector_service.gd:1623-1679`, and its shape
//     is the one implemented below (`{"assertion","node_path","property",
//     "operator","expected","actual","passed"}`).
//
// Observable contract (as implemented):
//   * `node_path` (string, required, not blank), `property` (string, required,
//     not blank) and `expected` (required, **any** JSON value - the contract
//     declares it without a type, so its presence is what is required and a JSON
//     `null` is a legal expectation);
//   * `operator` (string, default `eq`) - the eight names of
//     `MCPTools::evaluate_assertion`; anything else is `-32602` listing them;
//   * the node is resolved with the module's shared `resolve_game_node`: `.`/`""`
//     is the scene root, `/root/...` is absolute (an autoload), anything else is
//     relative and falls back to a whole-subtree name search;
//   * a node that does not exist, or one that does not have the property, is
//     `-32001` with `data.suggestion`. **The property test is a real one** -
//     `Object::get()` answers `null` for an unknown property and cannot be told
//     from a property that *is* null (the module's `property_type_of` note says
//     the same), so "the read did nothing" would otherwise be reported as a
//     `passed: false` against `null`. `MCPTools::object_has_property` asks the
//     object's own property list instead;
//   * the verdict is a **structured failure**: the answer always carries `passed`
//     plus `expected` and `actual` (each through `serialize_variant`), so a
//     failure says what was expected and what was found rather than only "it
//     failed";
//   * no running scene -> `-32000`; a mistyped argument -> `-32602`.
//
// **Assertion recording:** this tool runs in the game process, so a verdict it
// makes is recorded in the **game's** accumulator
// (`MCPTools::record_test_result`) and is not visible to
// `editor_get_test_report`, which reads the editor's. That is a consequence of
// the process split (GDR-21) and not a missing wire; the report says
// `source: "editor_process"` so the two cannot be confused. The game-side
// assertion is still observable through the tool's own answer and through the
// live evidence chain in the report.
// ---------------------------------------------------------------------------
static Variant _tool_assert_node_state(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_path' must not be empty");
		return Variant();
	}
	String property;
	if (!require_string(p_args, "property", property, r_error)) {
		return Variant();
	}
	if (property.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'property' must not be empty");
		return Variant();
	}
	// `expected` is required but untyped: the *presence* of the key is what is
	// required, and a JSON `null` is a legal expectation (`actual == null`).
	if (!p_args.has("expected")) {
		r_error = MCPToolError::invalid_params("Missing required parameter: expected");
		return Variant();
	}
	const Variant expected = p_args.get("expected", Variant());

	String op;
	if (!optional_string(p_args, "operator", "eq", op, r_error)) {
		return Variant();
	}

	Node *root = nullptr;
	SceneTree *tree = nullptr;
	if (!game_current_scene(root, tree, r_error)) {
		return Variant();
	}
	Node *node = resolve_game_node(tree, root, node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", node_path),
				"Use running_game_get_scene_tree to list the nodes of the running scene");
		return Variant();
	}
	const StringName property_name = property;
	if (!object_has_property(node, property_name)) {
		r_error = MCPToolError::not_found(vformat("Property '%s' on node '%s'", property, String(node->get_path())),
				"Use running_game_get_node_properties to list the properties the node really has");
		return Variant();
	}

	const Variant actual = node->get(property_name);
	const String resolved_path = String(node->get_path());

	bool passed = false;
	// The operator is validated here, in the one shared comparison: an unknown
	// name is `-32602` and its message lists the eight the tool accepts.
	if (!evaluate_assertion(op, actual, expected, passed, r_error)) {
		return Variant();
	}

	// TASK-020 section 4 (D-3): the verdict is the shared assertion field set
	// (status, the compared values - echoed as they were compared - and the
	// failure `reason` the M4 acceptance found missing here while the scenario
	// runner had it). The scenario runner builds its per-step record from the
	// very same function, so the two entries' failure field sets are one
	// definition.
	const Dictionary result = node_state_tool_verdict(resolved_path, property, op, expected, actual, passed);
	record_test_result(result);
	return result;
}

// ---------------------------------------------------------------------------
// running_game_assert_screen_text (old `assert_screen_text`)
//
// **The defect this implementation exists to avoid.** The migration source
// collects UI elements as `{"name", "path", "type"}`
// (`mcp_runtime_agent.gd:422-428`) and the assertion half
// (`test.rs:404-460`, `test_commands.gd:181-248`) then looks for
// `element.get("text", "")` - a key that collector never wrote. Every element
// therefore contributed an empty text, `all_texts` stayed empty and `found`
// stayed false: the tool could not pass for any input. The fix is not to invent
// a `"text"` key but to read the Control's own text, which is what
// `MCPTools::collect_visible_texts` does.
//
// Observable contract (as implemented):
//   * `text` (string, required, not blank);
//   * `partial` (boolean, default true) - substring vs. equality;
//   * `case_sensitive` (boolean, default true) - the migration source declared
//     the argument and then **ignored it** (`let _case_sensitive = ...`,
//     `test.rs:407`; `test_commands.gd:191` reads it and never uses it), while
//     the description the contract carries promises case folding. It is honoured
//     here, and the answer echoes it so the caller can see which rule ran;
//   * the visible text of the running game's current scene is collected depth
//     first. It is the **control tree**, not rendered pixels: `--headless`
//     renders nothing, and a pixel-level assertion would be unanswerable there.
//     The answer states that (`source: "control_tree"`);
//   * `{"passed", "expected_text", "partial", "case_sensitive", "source",
//     "visible_texts", "visible_elements"}` plus `matched_element` on a hit. The
//     full search space is always returned, so a failure is diagnosable instead
//     of empty;
//   * no running scene -> `-32000`.
// ---------------------------------------------------------------------------
static Variant _tool_assert_screen_text(const Dictionary &p_args, MCPToolError &r_error) {
	String expected_text;
	if (!require_string(p_args, "text", expected_text, r_error)) {
		return Variant();
	}
	if (expected_text.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'text' must not be empty");
		return Variant();
	}
	bool partial = true;
	bool case_sensitive = true;
	if (!optional_bool(p_args, "partial", true, partial, r_error) ||
			!optional_bool(p_args, "case_sensitive", true, case_sensitive, r_error)) {
		return Variant();
	}

	Node *root = nullptr;
	SceneTree *tree = nullptr;
	if (!game_current_scene(root, tree, r_error)) {
		return Variant();
	}

	const Array elements = collect_visible_texts(root);

	const String search_text = case_sensitive ? expected_text : expected_text.to_lower();
	bool found = false;
	Dictionary matched_element;
	Array visible_texts;
	Array visible_elements;
	for (int i = 0; i < elements.size(); i++) {
		const Dictionary element = elements[i];
		const String element_text = element.get("text", String());
		visible_texts.push_back(case_sensitive ? element_text : element_text.to_lower());
		visible_elements.push_back(element);
		const String compare_text = case_sensitive ? element_text : element_text.to_lower();
		const bool hit = partial ? compare_text.contains(search_text) : compare_text == search_text;
		if (hit && !found) {
			found = true;
			matched_element = element;
		}
	}

	Dictionary assertion = screen_text_tool_verdict(expected_text, partial, case_sensitive, visible_texts, visible_elements, found);
	if (found) {
		assertion["matched_element"] = matched_element;
	}

	record_test_result(assertion);
	return assertion;
}

// ---------------------------------------------------------------------------
// TASK-020 section 4 (D-3): this entry's two verdict builders. Each one is the
// shared assertion field set (`tools/tool_helpers.*`) plus the envelope this
// entry adds - and this entry adds none of its own, because its answer *is* the
// assertion verdict. The scenario runner's per-step record is the same field set
// plus its own `type`/`step`. See the header for why they are published.
//
// Declared in `MCPTools` like their declarations (`running_game_assertion.h`):
// with `using namespace MCPTools;` at the top of this file, a global-scope
// definition of a name the namespace already declares would be an ambiguous
// overload at every call site.
// ---------------------------------------------------------------------------
namespace MCPTools {

Dictionary node_state_tool_verdict(const String &p_resolved_node_path, const String &p_property,
		const String &p_operator, const Variant &p_expected_raw, const Variant &p_actual, bool p_passed) {
	return node_state_assertion_fields(p_resolved_node_path, p_resolved_node_path, p_property, p_operator,
			p_expected_raw, p_actual, p_passed);
}

Dictionary screen_text_tool_verdict(const String &p_text, bool p_partial, bool p_case_sensitive,
		const Array &p_visible_texts, const Array &p_visible_elements, bool p_found) {
	return screen_text_assertion_fields(p_text, p_partial, p_case_sensitive, p_visible_texts, p_visible_elements, p_found);
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// running_game_capture_signal_emissions (old `watch_signals`)
//
// The migration source connected a GDScript lambda to every signal of every
// listed node, awaited a timer, and then disconnected `Callable.create(func():
// pass)` - a **different** callable from the one it connected
// (`mcp_runtime_agent.gd:670` vs `:680`), so the disconnection could not match
// and every watched signal stayed connected to a closure appending to a dead
// array. The connection is therefore cancelled here with the very Callable it was
// made with, held on the task and reused verbatim; the framework deletes the
// task immediately after it completes, so nothing outlives the window.
//
// Observable contract (as implemented):
//   * `node_paths` (array of strings, required, not empty) - resolved with the
//     shared `resolve_game_node`; a path that does not resolve is `-32001`. The
//     migration source `continue`d past it and silently watched nothing, which
//     makes "empty result" indistinguishable from "the signal never fired";
//   * `signal_filter` (array of strings, optional) - when non-empty, only those
//     signal names are watched (an empty array means every signal, exactly like
//     an absent one);
//   * `duration_ms` (integer, default 5000, 0..600000) - the listen window. A
//     negative value is `-32602`; the upper bound is stated because the
//     framework's own ceiling is 30 s (GDR-20 point 4) and a window longer than
//     that could never complete;
//   * a signal whose name begins with `_` is skipped (the migration source's own
//     rule), and each (node, signal) pair is connected at most once;
//   * every emission records `{"signal", "node", "args"}`; `node` is the
//     resolved absolute path captured when the watch was created, and the node
//     itself is held as an `ObjectID` and resolved again per emission, never as a
//     `Node *` (GDR-20 point 7);
//   * `{"emitted", "count", "duration_ms", "watched", "watch_ended"}` where
//     `watched` lists `{node, signal, args}` of every connection that really
//     exists. An emissions collector whose answer cannot be told from "nothing
//     was watched" is the defect above, so the search space is always reported;
//   * the window ends with `watch_ended: "duration"`, or early with
//     `"all_watched_nodes_gone"` when every watched node has been freed (there is
//     nothing left to collect from, and waiting out the rest of the window would
//     only delay the same answer);
//   * no `SceneTree` at all -> `-32000`.
//
// **How the callback is built.** A GDScript lambda has no C++ equivalent: a
// `Callable` built from a method pointer has a **fixed argument count**, while a
// signal's is whatever the signal declares, and `call_with_variant_argsc` checks
// only under `DEBUG_ENABLED` (binder_common.h:209-224) - in a release build an
// arity mismatch is undefined behaviour rather than an error. The module
// therefore supplies its own `CallableCustom` (the engine's own `CallableCustomBind`
// has the same shape): a public abstract base class
// (`core/variant/callable.h:143`) whose `call()` receives the arguments as a
// pointer array, so any arity is handled. `get_argument_count()` reports the
// arity as *unknown* (`r_is_valid = false`), which is the engine's own protocol
// for a variadic callable; that is what keeps every signal shape legal.
// ---------------------------------------------------------------------------

// The `CallableCustom` that receives one connection's emissions. One instance per
// (node, signal) pair, so the record the engine calls back into carries the
// signal's identity - there is no lookup by signal name, and duplicate signal
// names on different nodes cannot be confused.
class EmissionRecord : public CallableCustom {
public:
	EmissionRecord(const ObjectID &p_node_id, const String &p_node_path, const StringName &p_signal) :
			node_id(p_node_id), node_path(p_node_path), signal(p_signal) {}

	// Every emitter this record saw, in order.
	Array emitted;
	// The most recent emission's arguments, serialized. Set by `call()`.
	Array last_args;
	int call_count = 0;

	ObjectID node_id;
	String node_path;
	StringName signal;
	// The `Callable` the engine actually stored. Kept so the disconnection uses an
	// equal value (`hash()` is pointer based, so a rebuilt one would not match).
	Callable callable;

	uint32_t hash() const override { return hash_murmur3_one_64((uint64_t)(uintptr_t)this); }
	String get_as_text() const override { return vformat("mcp_signal_watch(%s:%s)", node_path, String(signal)); }
	static bool compare_equal(const CallableCustom *p_a, const CallableCustom *p_b) { return p_a == p_b; }
	static bool compare_less(const CallableCustom *p_a, const CallableCustom *p_b) { return p_a < p_b; }
	CompareEqualFunc get_compare_equal_func() const override { return compare_equal; }
	CompareLessFunc get_compare_less_func() const override { return compare_less; }
	bool is_valid() const override { return true; }
	ObjectID get_object() const override { return ObjectID(); }
	StringName get_method() const override { return StringName(); }

	// `r_is_valid = false` means "this callable does not declare an arity", which
	// is the engine's own spelling for a variadic target (see the block above).
	int get_argument_count(bool &r_is_valid) const override {
		r_is_valid = false;
		return 0;
	}

	void call(const Variant **p_arguments, int p_argcount, Variant &r_return_value, Callable::CallError &r_call_error) const override {
		r_call_error.error = Callable::CallError::CALL_OK;
		(void)r_return_value;
		// `call()` is const, so the collected state is written through the
		// explicit cast used by the engine's own `CallableCustomBind` for exactly
		// the same reason.
		EmissionRecord *self = const_cast<EmissionRecord *>(this);
		self->last_args.clear();
		for (int i = 0; i < p_argcount; i++) {
			self->last_args.push_back(serialize_variant(*p_arguments[i]));
		}
		Dictionary entry;
		entry["signal"] = String(signal);
		entry["node"] = node_path;
		if (!self->last_args.is_empty()) {
			// A **copy** of the argument array, not the array itself: `last_args`
			// is reused by the next emission, and an `Array` is reference counted,
			// so pushing `last_args` directly made every recorded emission show
			// the *last* arguments (measured: 29 emissions of a one-argument
			// signal all reported the same tick). Each recorded emission is a
			// snapshot.
			Array args_snapshot;
			for (int i = 0; i < self->last_args.size(); i++) {
				args_snapshot.push_back(self->last_args[i]);
			}
			entry["args"] = args_snapshot;
		}
		self->emitted.push_back(entry);
		self->call_count++;
	}
};

class SignalEmissionsTask : public MCPDeferred::Task {
public:
	SignalEmissionsTask() {}

	void set_window(uint64_t p_start_ms, int64_t p_duration_ms) {
		start_ms = p_start_ms;
		duration_ms = p_duration_ms;
	}

	void set_filter(const Vector<String> &p_filter) {
		signal_filter = p_filter;
	}

	// Connects every matching signal of one node. Called while the handler still
	// holds a `Node *`; the task keeps only IDs and paths from here on.
	void watch(Node *p_node) {
		const String path = String(p_node->get_path());
		const Array signal_list = _node_signal_list(p_node);
		for (int i = 0; i < signal_list.size(); i++) {
			const Variant entry = signal_list[i];
			if (entry.get_type() != Variant::DICTIONARY) {
				continue;
			}
			const Dictionary description = entry;
			const String name = description.get("name", String());
			if (name.is_empty() || name.begins_with("_")) {
				continue;
			}
			if (!signal_filter.is_empty() && !signal_filter.has(name)) {
				continue;
			}
			if (has_watch(p_node->get_instance_id(), name)) {
				continue;
			}

			// **The record's lifetime belongs to its `Callable`.** A
			// `CallableCustom` is reference-counted by the engine
			// (`SafeRefCount`, `callable.h:145`): `Callable::~Callable` releases
			// one reference and `memdelete`s the custom object when the count
			// reaches zero (callable.cpp:438-445). `Object::connect` keeps a
			// reference of its own (`slot_map`, object.cpp:1713-1728), so the
			// engine owns the record for exactly as long as the connection exists
			// and the task must not free it by hand.
			//
			// The local `Callable` below is therefore **named and kept until after
			// the connect**: `p_node->connect(name, Callable(record))` with a
			// temporary would destroy the only reference on the first step of the
			// argument evaluation, and the record would be freed before the engine
			// ever saw it. `record->callable` is that kept reference, and it is
			// also what the destructor disconnects with - the very value the
			// engine stored, never a rebuilt equivalent.
			EmissionRecord *record = memnew(EmissionRecord(p_node->get_instance_id(), path, name));
			record->callable = Callable(record);
			const Error err = p_node->connect(name, record->callable);
			if (err != OK) {
				// A connection the engine refuses leaves no slot behind, so this
				// is the only reference: dropping it frees the record.
				record->callable = Callable();
				continue;
			}
			watches.push_back(record);
		}
	}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_frame;
		if (!watches.is_empty() && p_now_ms - start_ms >= (uint64_t)duration_ms) {
			return MCPDeferred::TickResult::done(build_result("duration"));
		}
		if (watches.is_empty()) {
			// Nothing was connected at all (every node had no matching signal):
			// waiting out the window would only delay the same empty answer.
			return MCPDeferred::TickResult::done(build_result("duration"));
		}
		if (all_watched_nodes_gone()) {
			return MCPDeferred::TickResult::done(build_result("all_watched_nodes_gone"));
		}
		return MCPDeferred::TickResult::pending();
	}

	uint64_t get_timeout_ms() const override {
		// The window plus a margin so the framework's own deadline is never the
		// thing that ends a legitimate window; it still clamps to its ceiling.
		return (uint64_t)duration_ms + 2000;
	}

	String describe() const override {
		return vformat("watching %d signal(s) for %d ms", watches.size(), (int)duration_ms);
	}

	~SignalEmissionsTask() override {
		for (int i = 0; i < watches.size(); i++) {
			EmissionRecord *record = watches[i];
			Node *node = ObjectDB::get_instance<Node>(record->node_id);
			if (node != nullptr) {
				// The same `Callable` value that was connected (see `watch()`),
				// through `Signal::disconnect`, which is available in every build
				// configuration (unlike `Object::disconnect`, which is empty
				// outside `DEBUG_ENABLED`). Measured: every other spelling
				// (rebuilding an equivalent callable, or reaching through the
				// bound `Object::disconnect`) either does not match the stored
				// value or does not exist - the migration source's own bug was
				// exactly a rebuilt callable that could never match.
				Signal(node, record->signal).disconnect(record->callable);
			}
			// Releasing the task's own reference. If a node replaced the
			// connection inside the window (so the disconnection above could not
			// match) the engine's slot still holds a reference and the record is
			// freed when that slot goes away - never here, where freeing it would
			// leave the slot pointing at dead memory.
			record->callable = Callable();
		}
		watches.clear();
	}

private:
	// Every signal of a node, as `{name, args}` dictionaries: the class' own
	// signals first, then the attached script's.
	//
	// **Why this is not `Object::get_signal_list`.** The bound
	// `Object.get_signal_list()` a GDScript caller uses is `_get_signal_list`,
	// which is `private:` in `object.h` (`:479`), so a module outside the class
	// cannot call it directly; and `p_object->has_method("get_signal_list")` was
	// **measured to answer false on a live `Node`** in this fork, so going
	// through `callp()` finds nothing and the watch would silently watch zero
	// signals. `ClassDB::get_signal_list()` (public, the same call the engine's
	// own `Object::get_signal_list` makes at object.cpp:1512) answers the class
	// half, and `Script::get_script_signal_list()` answers the half a GDScript
	// `signal` declaration lives in - which is exactly the signal a game's own
	// script emits.
	static Array _node_signal_list(Node *p_node) {
		Array out;

		List<MethodInfo> class_signals;
		ClassDB::get_signal_list(p_node->get_class_name(), &class_signals);
		for (const MethodInfo &signal : class_signals) {
			Dictionary entry;
			entry["name"] = String(signal.name);
			entry["args"] = signal.arguments.size();
			out.push_back(entry);
		}

		const Variant script_value = p_node->get_script();
		if (script_value.get_type() == Variant::OBJECT) {
			const Ref<Script> script = script_value;
			if (script.is_valid()) {
				List<MethodInfo> script_signals;
				script->get_script_signal_list(&script_signals);
				for (const MethodInfo &signal : script_signals) {
					Dictionary entry;
					entry["name"] = String(signal.name);
					entry["args"] = signal.arguments.size();
					out.push_back(entry);
				}
			}
		}
		return out;
	}

	bool has_watch(const ObjectID &p_node_id, const StringName &p_signal) const {
		for (int i = 0; i < watches.size(); i++) {
			if (watches[i]->node_id == p_node_id && watches[i]->signal == p_signal) {
				return true;
			}
		}
		return false;
	}

	bool all_watched_nodes_gone() const {
		for (int i = 0; i < watches.size(); i++) {
			if (ObjectDB::get_instance<Node>(watches[i]->node_id) != nullptr) {
				return false;
			}
		}
		return true;
	}

	Dictionary build_result(const String &p_ended_by) const {
		Array emitted;
		Array watched;
		int64_t emission_count = 0;
		for (int i = 0; i < watches.size(); i++) {
			const EmissionRecord *record = watches[i];
			for (int j = 0; j < record->emitted.size(); j++) {
				emitted.push_back(record->emitted[j]);
			}
			emission_count += record->emitted.size();
			Dictionary entry;
			entry["node"] = record->node_path;
			entry["signal"] = String(record->signal);
			entry["emissions"] = record->emitted.size();
			watched.push_back(entry);
		}
		Dictionary result;
		result["emitted"] = emitted;
		result["count"] = emission_count;
		result["duration_ms"] = duration_ms;
		result["watched"] = watched;
		result["watch_ended"] = p_ended_by;
		return result;
	}

	Vector<EmissionRecord *> watches;
	Vector<String> signal_filter;
	uint64_t start_ms = 0;
	int64_t duration_ms = 5000;
};

// A required array of strings (`node_paths`) or an optional one
// (`signal_filter`). A missing required key, a non-array value and a mistyped
// element are all `-32602`, and the message names the caller's own index.
static bool _require_string_array(const Dictionary &p_args, const String &p_key, bool p_required, Vector<String> &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		if (p_required) {
			r_error = MCPToolError::invalid_params("Missing required parameter: " + p_key);
			return false;
		}
		return true;
	}
	if (value.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be an array of strings, got %s",
				p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	const Array array = value;
	for (int i = 0; i < array.size(); i++) {
		const Variant item = array[i];
		if (item.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter '%s[%d]' must be a string, got %s",
					p_key, i, Variant::get_type_name(item.get_type())));
			return false;
		}
		r_out.push_back(item);
	}
	return true;
}

static MCPDeferred::Task *_tool_capture_signal_emissions(const Dictionary &p_args, MCPToolError &r_error) {
	Vector<String> node_paths;
	if (!_require_string_array(p_args, "node_paths", true, node_paths, r_error)) {
		return nullptr;
	}
	if (node_paths.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_paths' must not be empty: there would be nothing to watch");
		return nullptr;
	}
	Vector<String> signal_filter;
	if (!_require_string_array(p_args, "signal_filter", false, signal_filter, r_error)) {
		return nullptr;
	}
	int64_t duration_ms = 5000;
	if (!optional_int(p_args, "duration_ms", 5000, duration_ms, r_error)) {
		return nullptr;
	}
	if (duration_ms < 0) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'duration_ms' must not be negative, got %d", (int)duration_ms));
		return nullptr;
	}
	if (duration_ms > 600000) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'duration_ms' must be at most 600000 (10 minutes), got %d; the framework's own request deadline is 30 s, "
				"so a longer window can never complete",
				(int)duration_ms));
		return nullptr;
	}

	Node *root = nullptr;
	SceneTree *tree = nullptr;
	if (!game_current_scene(root, tree, r_error)) {
		return nullptr;
	}

	SignalEmissionsTask *task = memnew(SignalEmissionsTask());
	// `OS::get_singleton()->get_ticks_msec()` rather than the `Time` singleton:
	// `Time` is registered with the other core classes and its `get_singleton()`
	// is null in a `--test` process (`Main::test_entrypoint()` runs before the
	// registration levels), while `OS` exists before anything else. The
	// `running_game_input` group's replay clock makes the same choice.
	task->set_window((uint64_t)OS::get_singleton()->get_ticks_msec(), duration_ms);
	task->set_filter(signal_filter);
	for (int i = 0; i < node_paths.size(); i++) {
		Node *node = resolve_game_node(tree, root, node_paths[i]);
		if (node == nullptr) {
			// The task owns every connection it already made; `memdelete` runs its
			// destructor, which disconnects them and frees the records.
			memdelete(task);
			r_error = MCPToolError::not_found(vformat("Node '%s'", node_paths[i]),
					"Use running_game_get_scene_tree to list the nodes of the running scene");
			return nullptr;
		}
		task->watch(node);
	}
	return task;
}

// ---------------------------------------------------------------------------
// Registration
//
// Order follows docs/tool-groups-b4.json. Every declaration comes from
// docs/tool-rename-map.json (`channel = running_game`, `scope = game`;
// `mutating = false`) and the description and `inputSchema` are a byte-exact copy
// of the entries of docs/tools_list.renamed.json, emitted from that file by
// `scripts/gen_b2_game_schema.py --in-place` and not retyped; re-running the
// generator reproduces this block byte for byte.
// ---------------------------------------------------------------------------

void register_running_game_assertion_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("running_game_assert_node_state", String::utf8("断言运行中游戏节点的属性值符合预期"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("期望值");
		v0[String::utf8("expected")] = v1;
		Dictionary v2;
		v2[String::utf8("description")] = String::utf8("节点路径");
		v2[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("node_path")] = v2;
		Dictionary v3;
		v3[String::utf8("default")] = String::utf8("eq");
		v3[String::utf8("description")] = String::utf8("比较操作符: eq/neq/gt/lt/gte/lte/contains/type_is");
		v3[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("operator")] = v3;
		Dictionary v4;
		v4[String::utf8("description")] = String::utf8("属性名称");
		v4[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("property")] = v4;
		schema[String::utf8("properties")] = v0;
		Array v5;
		v5.push_back(String::utf8("node_path"));
		v5.push_back(String::utf8("property"));
		v5.push_back(String::utf8("expected"));
		schema[String::utf8("required")] = v5;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("assert").scope(MCPToolScope::GAME).mutating(false).schema(schema).handler(_tool_assert_node_state);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_assert_screen_text", String::utf8("断言运行中游戏屏幕上存在指定文本"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("default")] = true;
		v1[String::utf8("description")] = String::utf8("是否区分大小写");
		v1[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("case_sensitive")] = v1;
		Dictionary v2;
		v2[String::utf8("default")] = true;
		v2[String::utf8("description")] = String::utf8("是否使用部分匹配");
		v2[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("partial")] = v2;
		Dictionary v3;
		v3[String::utf8("description")] = String::utf8("要查找的文本");
		v3[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("text")] = v3;
		schema[String::utf8("properties")] = v0;
		Array v4;
		v4.push_back(String::utf8("text"));
		schema[String::utf8("required")] = v4;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("assert").scope(MCPToolScope::GAME).mutating(false).schema(schema).handler(_tool_assert_screen_text);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_capture_signal_emissions", String::utf8("监听运行中游戏节点的信号发射"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("default")] = 5000;
		v1[String::utf8("description")] = String::utf8("监听持续时间（毫秒）");
		v1[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("duration_ms")] = v1;
		Dictionary v2;
		v2[String::utf8("description")] = String::utf8("要监听的节点路径列表");
		Dictionary v3;
		v3[String::utf8("type")] = String::utf8("string");
		v2[String::utf8("items")] = v3;
		v2[String::utf8("type")] = String::utf8("array");
		v0[String::utf8("node_paths")] = v2;
		Dictionary v4;
		v4[String::utf8("description")] = String::utf8("要监听的信号名称过滤列表（可选）");
		Dictionary v5;
		v5[String::utf8("type")] = String::utf8("string");
		v4[String::utf8("items")] = v5;
		v4[String::utf8("type")] = String::utf8("array");
		v0[String::utf8("signal_filter")] = v4;
		schema[String::utf8("properties")] = v0;
		Array v6;
		v6.push_back(String::utf8("node_paths"));
		schema[String::utf8("required")] = v6;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("capture").scope(MCPToolScope::GAME).mutating(false).schema(schema).pending_handler(_tool_capture_signal_emissions);
		builder.register_into(r_registry);
	}
	// END generated
}
