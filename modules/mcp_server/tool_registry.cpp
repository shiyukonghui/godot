/**************************************************************************/
/*  tool_registry.cpp                                                     */
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

#include "tool_registry.h"

#include "core/config/engine.h"
#include "core/error/error_macros.h"
#include "core/io/json.h"

// ---------------------------------------------------------------------------
// MCPToolError factories (GDR-6 / GDR-14). The messages match the reference
// implementation (godot_mcp_gdext/src/utils/error.rs) character for character,
// because hof-rs parses both codes and messages.
// ---------------------------------------------------------------------------

static Variant _suggestion_data(const String &p_suggestion) {
	if (p_suggestion.is_empty()) {
		return Variant();
	}
	Dictionary data;
	data["suggestion"] = p_suggestion;
	return data;
}

MCPToolError MCPToolError::invalid_params(const String &p_message) {
	MCPToolError error;
	error.code = MCP_ERR_INVALID_PARAMS;
	// GDR-6: `-32602` carries the raw reason, never a prefix.
	//
	// TASK-050 O-1/N-7: the factory itself stays data-free - it does not know the
	// tool it is called for, and a handler must not have to repeat the schema it
	// was registered with. The one place that *does* know both is the registry
	// entry point, and it adds `data.suggestion` there (`call_tool()` /
	// `call_deferred_tool()`), so every `-32602` that leaves this module carries
	// one no matter which handler produced it.
	error.message = p_message;
	return error;
}

MCPToolError MCPToolError::internal(const String &p_message) {
	MCPToolError error;
	error.code = MCP_ERR_INTERNAL_ERROR;
	error.message = "Internal error: " + p_message;
	return error;
}

MCPToolError MCPToolError::no_scene() {
	MCPToolError error;
	error.code = MCP_ERR_TOOL_STATE;
	error.message = "No scene is currently open";
	// TASK-010 section 3.1: the advice has to match the *process*. "Use
	// editor_open_scene to open a scene first" is impossible advice in a game
	// process - there is no editor, and a game-only tool is not even served by an
	// editor endpoint - so a game-side caller is told what actually produces a
	// current scene there: the project's main scene, in a running game.
	//
	// The scope of the *tool* is deliberately not consulted: a game-only tool in
	// an editor process is refused with -32601 before any handler runs (GDR-7 /
	// GDR-19 section 17.3), so the editor branch is unreachable for it, and this
	// branch is unreachable in the game side of an editor *process*. What is left
	// is the honest question "which scene can this process have at all", and the
	// engine answers that: `Engine::is_editor_hint()`.
	Engine *engine = Engine::get_singleton();
	const bool editor_process = engine != nullptr && engine->is_editor_hint();
	error.data = _suggestion_data(editor_process
					? String("Use editor_open_scene to open a scene first")
					: String("Start the game with a main scene (application/run/main_scene in project.godot) and call this tool while the game is running"));
	return error;
}

// GDR-14: the call is well formed but the state blocks it. The tool supplies its
// own readable reason ("Resource already exists: res://x.tres") and the
// suggestion that says how to get past it, so the wire error stays actionable.
MCPToolError MCPToolError::tool_state(const String &p_message, const String &p_suggestion) {
	MCPToolError error;
	error.code = MCP_ERR_TOOL_STATE;
	error.message = p_message;
	error.data = _suggestion_data(p_suggestion);
	return error;
}

MCPToolError MCPToolError::not_implemented(const String &p_what, const String &p_suggestion) {
	MCPToolError error;
	error.code = MCP_ERR_TOOL_STATE;
	error.message = "Not implemented: " + p_what;
	error.data = _suggestion_data(p_suggestion.is_empty()
					? String("This capability is not implemented in the built-in module yet")
					: p_suggestion);
	return error;
}

MCPToolError MCPToolError::not_found(const String &p_what, const String &p_suggestion) {
	MCPToolError error;
	error.code = MCP_ERR_NOT_FOUND;
	// TASK-017 section 3: the " not found" suffix is appended **exactly once**.
	// A caller is allowed to spell the finding into `p_what` itself (the property
	// readback of `editor_get_node_properties` says "Property 'p' on node 'n' is
	// not readable by name"), and the unconditional suffix turned that into
	// "... is not readable by name not found" on the wire. Appending only when
	// the wording does not already end in the suffix keeps every other caller's
	// message byte-identical: their `p_what` never ends with the phrase, so the
	// concatenation is the same string it always was.
	error.message = p_what.ends_with(" not found") ? p_what : p_what + " not found";
	error.data = _suggestion_data(p_suggestion);
	return error;
}

// GDR-16 L1: the legal channel prefixes, tried longest first. `running_game_`
// carries its own underscore, so a `split('_')[1]` parse would read the verb of
// `running_game_get_scene_tree` as `game` instead of `get`.
static const char *MCP_TOOL_CHANNELS[] = { "running_game", "project", "editor", "os" };

// GDR-16 L2: the closed verb set, byte for byte the `convention.verb_closed_set`
// of docs/tool-rename-map.json. It is duplicated here because registration
// cannot read JSON; scripts/gen_renamed_contract.py re-validates the 171 renamed
// names against the same set, so any drift between the two definitions becomes a
// reproducible red instead of a silent divergence.
static const char *MCP_TOOL_VERBS[] = {
	"get", "list", "read", "find", "search", "create", "add", "remove", "delete",
	"set", "edit", "rename", "reparent", "move", "duplicate", "connect",
	"disconnect", "play", "stop", "run", "execute", "evaluate", "capture",
	"assert", "validate", "simulate", "export", "deploy", "reload", "rescan",
	"bake", "open", "save", "setup", "analyze", "detect", "convert"
};

// TASK-052 (DESIGN-DETAIL.md section 26 / GDR-28 point 4): the verbs an *added*
// tool may introduce.
//
// GDR-28 requires an added entry to be named by the rule of GDR-16 and spells
// out the channel restriction and the L4 `update_` ban, but it does not say
// whether the map's closed set binds added names too; and the decision maker
// fixed the two names of TASK-052 section 1 (`project_build_csharp`,
// `project_write_text_file`), so the two verbs have to be legal somewhere.
//
// The choice recorded here (and in REPORT-052) is the conservative one: the 37
// word list above stays **byte for byte the map's set** - it is not edited - and
// an added verb enters through this second, explicit list instead. So "which
// verbs are the map's" and "which verbs were invented by an expansion" stay two
// readable questions, and the same two records exist in
// `scripts/gen_renamed_contract.py` (`ADDED_VERB_EXTENSIONS`) and in
// `docs/tool-groups-added.json` (`verb_extensions`, where `--added` requires
// each one to be used by a group).
static const char *MCP_ADDED_TOOL_VERBS[] = { "build", "write" };

static bool _is_closed_verb(const String &p_verb) {
	for (const char *verb : MCP_TOOL_VERBS) {
		if (p_verb == verb) {
			return true;
		}
	}
	for (const char *verb : MCP_ADDED_TOOL_VERBS) {
		if (p_verb == verb) {
			return true;
		}
	}
	return false;
}

bool MCPToolRegistry::parse_tool_name(const String &p_name, String &r_channel, String &r_verb) {
	for (const char *channel : MCP_TOOL_CHANNELS) {
		const String prefix = String(channel) + "_";
		if (!p_name.begins_with(prefix)) {
			continue;
		}
		const String rest = p_name.substr(prefix.length());
		if (rest.is_empty()) {
			return false;
		}
		// L1: the remainder may only contain [a-z0-9_].
		for (int i = 0; i < rest.length(); i++) {
			const char32_t c = rest[i];
			const bool allowed = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_';
			if (!allowed) {
				return false;
			}
		}
		const int separator = rest.find("_");
		r_channel = channel;
		// `editor_get` is legal: the object segment is not required (D-E4).
		r_verb = separator < 0 ? rest : rest.substr(0, separator);
		return true;
	}
	return false;
}

bool MCPToolRegistry::validate_tool_name(const String &p_name, const String &p_declared_channel, const String &p_declared_verb, String &r_error) {
	if (p_name.is_empty()) {
		r_error = "MCPToolRegistry: refusing to register a tool without a name (GDR-16 L1).";
		return false;
	}
	// L4 runs before L1/L2/L3 so that the banned verb stays independently
	// observable: `editor_update_node_property` is otherwise fully legal.
	if (p_name.contains("update_")) {
		r_error = vformat("MCPToolRegistry: tool name '%s' contains the banned verb 'update_' (GDR-16 L4).", p_name);
		return false;
	}
	String channel;
	String verb;
	if (!parse_tool_name(p_name, channel, verb)) {
		r_error = vformat("MCPToolRegistry: tool name '%s' must match ^(editor|running_game|project|os)_[a-z0-9_]+$ (GDR-16 L1).", p_name);
		return false;
	}
	if (!_is_closed_verb(verb)) {
		r_error = vformat("MCPToolRegistry: tool name '%s' has verb '%s', which is not in the closed verb set (GDR-16 L2).", p_name, verb);
		return false;
	}
	if (p_declared_channel != channel) {
		r_error = vformat("MCPToolRegistry: tool name '%s' declares channel '%s' but the name says '%s' (GDR-16 L3).", p_name, p_declared_channel, channel);
		return false;
	}
	if (p_declared_verb != verb) {
		r_error = vformat("MCPToolRegistry: tool name '%s' declares verb '%s' but the name says '%s' (GDR-16 L3).", p_name, p_declared_verb, verb);
		return false;
	}
	return true;
}

// Private by design (GDR-19 / TASK-003 section 1.6): `MCPTools::ToolBuilder` is
// the only friend of `MCPToolRegistry`, so the only way in is
// `ToolBuilder::register_into()` - which has already forced channel / verb /
// scope / mutating to be declared and has applied the editor-process guard. The
// lint below stays as the registry's own invariant, independent of its caller.
bool MCPToolRegistry::register_tool(const MCPToolDef &p_def) {
	String reason;
	if (!validate_tool_name(String(p_def.name), p_def.channel, p_def.verb, reason)) {
		ERR_PRINT(reason);
		return false;
	}
	if (!tools.has(p_def.name)) {
		order.push_back(p_def.name);
	}
	tools[p_def.name] = p_def;
	return true;
}

bool MCPToolRegistry::has_tool(const StringName &p_name) const {
	return tools.has(p_name);
}

bool MCPToolRegistry::scope_matches(MCPToolScope p_scope, bool p_is_editor) {
	switch (p_scope) {
		case MCPToolScope::EDITOR:
			return p_is_editor;
		case MCPToolScope::GAME:
			return !p_is_editor;
		case MCPToolScope::BOTH:
			return true;
	}
	return false;
}

MCPToolScope MCPToolRegistry::scope_from_string(const String &p_scope, bool &r_ok) {
	// The spelling of docs/tool-rename-map.json (`scope_enum`).
	if (p_scope == "editor") {
		r_ok = true;
		return MCPToolScope::EDITOR;
	}
	if (p_scope == "game") {
		r_ok = true;
		return MCPToolScope::GAME;
	}
	if (p_scope == "both") {
		r_ok = true;
		return MCPToolScope::BOTH;
	}
	r_ok = false;
	return MCPToolScope::BOTH;
}

bool MCPToolRegistry::is_tool_visible(const StringName &p_name, bool p_is_editor) const {
	const MCPToolDef *def = tools.getptr(p_name);
	if (def == nullptr) {
		return false;
	}
	return scope_matches(def->scope, p_is_editor);
}

int MCPToolRegistry::get_visible_tool_count(bool p_is_editor) const {
	int count = 0;
	for (int i = 0; i < order.size(); i++) {
		const MCPToolDef *def = tools.getptr(order[i]);
		if (def != nullptr && scope_matches(def->scope, p_is_editor)) {
			count++;
		}
	}
	return count;
}

Array MCPToolRegistry::build_tools_list(bool p_is_editor) const {
	Array list;
	for (int i = 0; i < order.size(); i++) {
		const MCPToolDef *def = tools.getptr(order[i]);
		if (def == nullptr || !scope_matches(def->scope, p_is_editor)) {
			// Tools that have not been ported yet are simply not in the
			// registry, and tools of the other process are hidden here.
			continue;
		}
		Dictionary entry;
		entry["name"] = String(def->name);
		entry["description"] = def->description;
		entry["inputSchema"] = def->input_schema;
		list.push_back(entry);
	}
	return list;
}

// ---------------------------------------------------------------------------
// TASK-050 O-1 (the missing-required half) + N-7 (the rest of the family):
// every `-32602` this module answers carries `data.suggestion`.
//
// Why this lives in the registry and not in the ~30 handlers: `call_tool()` and
// `call_deferred_tool()` are the only two ways a handler can be reached (the
// transport, the deferred channel and the doctests all go through them - GDR-19
// section 17.2) and both already hold the tool's `MCPToolDef`, i.e. its contract
// `inputSchema`. A per-handler fix would have to be written 171 times and would
// rot at the first new tool; here it is one rule, for every tool, current and
// future. N-7's "no `-32602` may carry an empty suggestion" is therefore a
// property of the registry, not a convention.
//
// What may and may not move (TASK-050 section 4):
//   * the error **code** and the **message text** are untouched - a `-32602`
//     keeps its code and its exact wording, only `data` grows;
//   * the suggestion is only ever *added*: an error that already carries a
//     non-empty `data.suggestion` keeps it byte for byte (that is what keeps the
//     TASK-032 unknown-argument suggestion and the batch rollback envelope -
//     `data.batch` *and* a suggestion in one payload - unchanged);
//   * the accepted-parameter list is read from the live `inputSchema` and is
//     therefore in the schema's own order, exactly like the TASK-032 gate's.
//
// The generator is schema-driven on purpose: it never guesses a per-tool
// vocabulary. When the schema does not declare enough (a bare `array` with no
// `items` shape, a member no schema declares) it says so *and* still lists the
// accepted parameters, which is N-7's "explain the reason, never leave it empty".
// ---------------------------------------------------------------------------

static bool _has_non_empty_suggestion(const Variant &p_data) {
	if (p_data.get_type() != Variant::DICTIONARY) {
		return false;
	}
	const Variant suggestion = ((Dictionary)p_data).get("suggestion", Variant());
	return suggestion.get_type() == Variant::STRING && !String(suggestion).is_empty();
}

// The accepted-parameter list of the TASK-032 gate and of every TASK-050
// suggestion. A tool that declares nothing says so instead of listing an empty
// set.
static String _accepted_parameters_of(const MCPToolDef &p_def) {
	Dictionary declared;
	const Variant properties_value = p_def.input_schema.get("properties", Variant());
	if (properties_value.get_type() == Variant::DICTIONARY) {
		declared = properties_value;
	}
	Vector<String> accepted;
	const Array keys = declared.keys();
	for (int i = 0; i < keys.size(); i++) {
		accepted.push_back((String)keys[i]);
	}
	if (accepted.is_empty()) {
		return vformat("%s accepts no parameters", String(p_def.name));
	}
	return vformat("Accepted parameters of %s: %s", String(p_def.name), String(", ").join(accepted));
}

// A suggestion is a wire message, so every list it prints is bounded and says
// when it was cut: an `Environment`-sized property bag must not be able to push
// an unbounded `data` through the transport.
static const int MCP_SUGGESTION_MEMBER_CAP = 12;

static String _schema_member_list(const Dictionary &p_properties) {
	const Array names = p_properties.keys();
	Vector<String> shown;
	for (int i = 0; i < names.size() && i < MCP_SUGGESTION_MEMBER_CAP; i++) {
		shown.push_back((String)names[i]);
	}
	String joined = String(", ").join(shown);
	if (names.size() > MCP_SUGGESTION_MEMBER_CAP) {
		joined += vformat(", ... (%d members in total)", names.size());
	}
	return joined;
}

static String _schema_required_list(const Variant &p_node) {
	if (p_node.get_type() != Variant::DICTIONARY) {
		return String();
	}
	const Variant required_value = ((Dictionary)p_node).get("required", Variant());
	if (required_value.get_type() != Variant::ARRAY) {
		return String();
	}
	const Array required = required_value;
	if (required.is_empty()) {
		return String();
	}
	Vector<String> names;
	for (int i = 0; i < required.size() && i < MCP_SUGGESTION_MEMBER_CAP; i++) {
		names.push_back((String)required[i]);
	}
	return String(", ").join(names);
}

// "a string" / "an integer" / "an array of an object with members {a, b}" ...
static String _schema_type_phrase(const Variant &p_node, int p_depth) {
	if (p_node.get_type() != Variant::DICTIONARY) {
		return "any value";
	}
	const Dictionary node = p_node;
	const String type = node.get("type", String());
	if (type == "array") {
		const Variant items = node.get("items", Variant());
		if (items.get_type() == Variant::DICTIONARY && p_depth < 3) {
			return "an array of " + _schema_type_phrase(items, p_depth + 1);
		}
		return "an array";
	}
	if (type == "object" || type == "dictionary") {
		const Variant members_value = node.get("properties", Variant());
		if (members_value.get_type() == Variant::DICTIONARY && !((Dictionary)members_value).is_empty() && p_depth < 3) {
			String phrase = vformat("an object with members {%s}", _schema_member_list(members_value));
			const String required = _schema_required_list(node);
			if (!required.is_empty()) {
				phrase += vformat(", requiring {%s}", required);
			}
			return phrase;
		}
		return "an object";
	}
	if (type == "string" || type == "number" || type == "boolean") {
		return String("a ") + type;
	}
	if (type == "integer") {
		return "an integer";
	}
	if (type.is_empty()) {
		return "any value";
	}
	return type;
}

// The acceptable *form* of one declared parameter: its type and its `enum` when
// the contract declares one. Requiredness is added by `_schema_form` below and
// deliberately left out of the bare phrase: a "Missing required parameter"
// refusal already says which parameter is missing, and repeating "(required)"
// inside its own parentheses is noise.
static String _schema_options_phrase(const Variant &p_node) {
	String phrase = _schema_type_phrase(p_node, 0);
	if (p_node.get_type() == Variant::DICTIONARY) {
		const Variant enum_value = ((Dictionary)p_node).get("enum", Variant());
		if (enum_value.get_type() == Variant::ARRAY) {
			const Array values = enum_value;
			Vector<String> spellings;
			for (int i = 0; i < values.size() && i < MCP_SUGGESTION_MEMBER_CAP; i++) {
				spellings.push_back(values[i].get_type() == Variant::STRING ? String(values[i]) : JSON::stringify(values[i]));
			}
			if (!spellings.is_empty()) {
				phrase += ", one of: " + String("|").join(spellings);
			}
		}
	}
	return phrase;
}

static String _schema_form(const Variant &p_node, bool p_required) {
	String form = _schema_options_phrase(p_node);
	if (p_required) {
		form += " (required)";
	} else if (p_node.get_type() == Variant::DICTIONARY && ((Dictionary)p_node).has("default")) {
		form += vformat(", optional (default %s)", JSON::stringify(((Dictionary)p_node)["default"]));
	} else {
		form += " (optional)";
	}
	return form;
}

// The walk of one parameter path (`events[0].type`) through the contract schema.
struct _SchemaPathLookup {
	// The leaf member was found and `node` describes it.
	bool resolved = false;
	// Set when the path indexed an array whose schema declares no `items`: the
	// value is the name of the member that carries that bare array, which is the
	// fact the suggestion has to report instead of inventing a shape.
	String array_name;
	Variant node;
	bool required = false;
};

static _SchemaPathLookup _lookup_schema_path(const Dictionary &p_properties, const Array &p_required, const String &p_path) {
	_SchemaPathLookup lookup;
	Dictionary members = p_properties;
	Array required = p_required;
	String rest = p_path;
	// The last member name resolved, used for the "declares 'x' as a bare array"
	// sentence.
	String last_member;
	bool have_node = false;
	Variant node;

	while (!rest.is_empty()) {
		if (rest[0] == '.') {
			rest = rest.substr(1);
			continue;
		}
		if (rest[0] == '[') {
			if (!have_node || node.get_type() != Variant::DICTIONARY) {
				return lookup;
			}
			const Variant items = ((Dictionary)node).get("items", Variant());
			if (items.get_type() != Variant::DICTIONARY) {
				lookup.array_name = last_member;
				return lookup;
			}
			node = items;
			const Dictionary item_node = items;
			members = item_node.get("properties", Dictionary());
			required = item_node.get("required", Array());
			const int close = rest.find("]");
			rest = close < 0 ? String() : rest.substr(close + 1);
			continue;
		}
		int end = rest.length();
		for (int i = 0; i < rest.length(); i++) {
			const char32_t c = rest[i];
			if (c == '.' || c == '[') {
				end = i;
				break;
			}
		}
		const String name = rest.substr(0, end);
		rest = rest.substr(end);
		if (name.is_empty() || !members.has(name)) {
			return lookup;
		}
		node = members[name];
		have_node = true;
		last_member = name;
		lookup.required = required.has(name);
		if (node.get_type() == Variant::DICTIONARY) {
			const Dictionary child = node;
			members = child.get("properties", Dictionary());
			required = child.get("required", Array());
		} else {
			members = Dictionary();
			required = Array();
		}
	}
	if (!have_node) {
		return lookup;
	}
	lookup.resolved = true;
	lookup.node = node;
	return lookup;
}

// The parameter a `-32602` message is about, as a schema path. Only the module's
// own spellings are recognised; anything else returns an empty string and the
// caller falls back to the explicit "we cannot narrow it further" sentence.
static String _parameter_name_in_message(const String &p_message) {
	const String missing_prefix("Missing required parameter: ");
	if (p_message.begins_with(missing_prefix)) {
		return p_message.substr(missing_prefix.length()).strip_edges();
	}
	// `Parameter 'events[0].keycode' must be a string, got float`.
	const int marker = p_message.find("Parameter '");
	if (marker >= 0) {
		const int start = marker + String("Parameter '").length();
		const int close = p_message.find("'", start);
		if (close > start) {
			String name = p_message.substr(start, close - start);
			// One parser (the scenario step reader) spells the member *after* the
			// quoted index: `Parameter 'steps[0]'.type must be a string`. A path
			// continuation right after the closing quote belongs to the same
			// parameter.
			int index = close + 1;
			if (index < p_message.length() && (p_message[index] == '.' || p_message[index] == '[')) {
				int end = index;
				while (end < p_message.length()) {
					const char32_t c = p_message[end];
					const bool path_char = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
							c == '_' || c == '.' || c == '[' || c == ']';
					if (!path_char) {
						break;
					}
					end++;
				}
				name += p_message.substr(index, end - index);
			}
			return name;
		}
	}
	// The batch writers' spelling: `'nodes[0].type' must be a string`.
	if (p_message.begins_with("'")) {
		const int close = p_message.find("'", 1);
		if (close > 1) {
			return p_message.substr(1, close - 1);
		}
	}
	return String();
}

// `<name> must be ...` at the very start of a message, but only when the schema
// really declares that name: the selection tool answers an unknown mode with
// `mode must be one of: replace, add, remove` and names no parameter any other
// way. Returning a declaration-checked name keeps this from inventing one.
static String _declared_leading_word(const String &p_message, const Dictionary &p_properties) {
	const int space = p_message.find(" ");
	if (space <= 0) {
		return String();
	}
	const String candidate = p_message.substr(0, space);
	const Array names = p_properties.keys();
	for (int i = 0; i < names.size(); i++) {
		if (String(names[i]) == candidate) {
			return candidate;
		}
	}
	return String();
}

static String _invalid_params_suggestion(const MCPToolDef &p_def, const String &p_message) {
	const String accepted = _accepted_parameters_of(p_def);
	Dictionary properties;
	const Variant properties_value = p_def.input_schema.get("properties", Variant());
	if (properties_value.get_type() == Variant::DICTIONARY) {
		properties = properties_value;
	}
	Array required;
	const Variant required_value = p_def.input_schema.get("required", Variant());
	if (required_value.get_type() == Variant::ARRAY) {
		required = required_value;
	}

	String name = _parameter_name_in_message(p_message);
	if (name.is_empty()) {
		name = _declared_leading_word(p_message, properties);
	}
	if (name.is_empty()) {
		// N-7's last resort, and it is still not empty: say which tool's own rule
		// refused the call and list what it accepts, so the caller can move.
		return vformat("The refusal comes from %s's own value rule and names no member its inputSchema declares; %s",
				String(p_def.name), accepted);
	}

	const bool missing = p_message.begins_with("Missing required parameter: ");
	const _SchemaPathLookup lookup = _lookup_schema_path(properties, required, name);
	if (lookup.resolved) {
		if (missing) {
			return vformat("Missing required parameter '%s' (%s); %s", name, _schema_options_phrase(lookup.node), accepted);
		}
		return vformat("Parameter '%s' accepts %s; %s", name, _schema_form(lookup.node, lookup.required), accepted);
	}
	if (!lookup.array_name.is_empty()) {
		return vformat("%s '%s': the schema declares '%s' as an array with no item shape, so no accepted member value can be "
					   "derived from it; %s",
				missing ? "Missing required parameter" : "Parameter", name, lookup.array_name, accepted);
	}
	if (missing) {
		return vformat("Missing required parameter '%s'; %s", name, accepted);
	}
	return vformat("Parameter '%s' is not declared by %s's inputSchema; the refusal is the tool's own value rule; %s",
			name, String(p_def.name), accepted);
}

// Adds the suggestion to a `-32602` that does not have one. Everything else -
// code, message, and any `data` a handler already attached - is preserved.
static void _add_invalid_params_suggestion(const MCPToolDef &p_def, MCPToolError &r_error) {
	if (r_error.code != MCP_ERR_INVALID_PARAMS || _has_non_empty_suggestion(r_error.data)) {
		return;
	}
	Dictionary data;
	if (r_error.data.get_type() == Variant::DICTIONARY) {
		data = r_error.data;
	}
	data["suggestion"] = _invalid_params_suggestion(p_def, r_error.message);
	r_error.data = data;
}

// An unknown tool name is a `-32602` as well, and it has no schema to read a
// suggestion off - so it points at the one place the real names live.
static Variant _unknown_tool_suggestion_data(const StringName &p_name) {
	return _suggestion_data(vformat("'%s' is not a tool of this process; call tools/list to get the exact names it serves",
			String(p_name)));
}

// ---------------------------------------------------------------------------
// TASK-063 (b): the node-path alias hint.
//
// The unknown-argument gate knows which member names a tool declares, but not
// what they *mean*. A caller who guessed the sibling tool's spelling - `node_path`
// where this tool declares `path` - therefore got only the accepted-parameter
// list: it names the right member and says nothing about what a path is. That is
// the measured first half of TASK-060 D-5 (`-32602 Unknown parameter
// 'node_path'`), and the 20 single writes it cost are why the second half is now
// spelled out.
//
// The hint is keyed by an explicit table rather than by a name heuristic: an
// editor tool that declares `path` for something that is NOT a node path
// (`editor_open_scene`'s scene path), and every `project_*` tool that takes a
// `res://` path, must not get advice about the edited scene root. The table is
// the decision, so the decision is auditable and cannot misfire elsewhere.
// ---------------------------------------------------------------------------
struct _NodePathAliasTool {
	const char *tool;
	// The spelling this tool really requires.
	const char *parameter;
	// How many paths it takes, and where they live.
	const char *shape;
};

static const _NodePathAliasTool NODE_PATH_ALIAS_TOOLS[] = {
	{ "editor_set_node_property", "path", "one node path" },
	{ "editor_get_node_properties", "path", "one node path" },
	{ "editor_set_node_script_batch", "node_paths", "an array of node paths" },
	{ "editor_set_node_property_updates", "updates", "one 'path' per entry of the 'updates' array" },
};

static const char *const NODE_PATH_ALIASES[] = { "path", "paths", "node_path", "node_paths" };

static bool _is_node_path_alias(const String &p_name) {
	for (int i = 0; i < 4; i++) {
		if (p_name == NODE_PATH_ALIASES[i]) {
			return true;
		}
	}
	return false;
}

// The text appended to the accepted-parameter list, or an empty string when the
// unknown name says nothing about a node path.
static String _node_path_alias_hint(const MCPToolDef &p_def, const Vector<String> &p_unknown) {
	const String tool = String(p_def.name);
	const _NodePathAliasTool *record = nullptr;
	for (int i = 0; i < 4; i++) {
		if (tool == NODE_PATH_ALIAS_TOOLS[i].tool) {
			record = &NODE_PATH_ALIAS_TOOLS[i];
			break;
		}
	}
	if (record == nullptr) {
		return String();
	}
	String alias;
	for (int i = 0; i < p_unknown.size(); i++) {
		if (_is_node_path_alias(p_unknown[i]) && p_unknown[i] != String(record->parameter)) {
			alias = p_unknown[i];
			break;
		}
	}
	if (alias.is_empty()) {
		return String();
	}
	return vformat("; '%s' is not a parameter of this tool: its node path is spelled '%s' (%s), and every node "
				   "path of the editor node tools is resolved relative to the edited scene root - an absolute "
				   "scene-tree path such as '/root/Main/Car' is not accepted",
			alias, String(record->parameter), String(record->shape));
}

// ---------------------------------------------------------------------------
// TASK-032 D4 (M4d): every argument a tool accepts is declared by its contract
// `inputSchema`. A name outside that set is not "an extra the tool ignores" but
// a caller's mistake: `project_get_settings` documents `prefix`, and a caller
// who spelled it `filter` used to get `code: 0` plus the *unfiltered* list of 981
// settings - a plausible-looking answer to a question that was never asked.
//
// The check lives here, in the registry, because this is the one entry point
// every caller goes through: the immediate JSON-RPC path, the deferred channel
// and the doctests all reach a handler through `call_tool()` /
// `call_deferred_tool()`. A gate in the transport would leave the in-process
// paths able to violate the rule.
//
// The message names the offending parameter(s) and `data.suggestion` lists the
// accepted ones (in the schema's own order, so the answer is deterministic).
// The check runs *before* the handler, which is also what makes the "accepted
// set == schema" sweep in the TASK-032 doctest side-effect free: a call whose
// only member is an undeclared name never reaches a handler.
//
// One boundary this gate does *not* cross (found by the TASK-032 doctest suite
// itself): a parameter that the schema **does** declare but that the tool cannot
// honour is the handler's business, not this one's.
// `running_game_run_test_scenario.scene_path` is exactly that case - the
// contract declares it (it is the editor-side migration source's argument), the
// schema-driven gate therefore lets it through, and the handler still refuses a
// non-empty value with its own explanation. The gate's rule is about *names no
// schema declares*, and keeping those two rules apart is what lets a tool own a
// semantic refusal without reopening the silent-ignore hole.
// ---------------------------------------------------------------------------
static bool _reject_unknown_arguments(const MCPToolDef &p_def, const Dictionary &p_args, MCPToolError &r_error) {
	const Variant properties_value = p_def.input_schema.get("properties", Variant());
	if (properties_value.get_type() != Variant::DICTIONARY) {
		// A tool whose schema declares no `properties` object cannot be checked
		// (the empty schema every no-parameter tool uses does declare one, so this
		// is a defect in a *schema literal*, not a silent bypass: it is reported
		// once, loudly, and the call proceeds as it did before TASK-032).
		if (!p_def.input_schema.is_empty()) {
			ERR_PRINT(vformat("MCPToolRegistry: tool '%s' has an inputSchema without a 'properties' object; "
							  "the unknown-argument gate cannot check its arguments",
					String(p_def.name)));
		}
		return true;
	}
	const Dictionary declared = properties_value;

	Vector<String> unknown;
	const Array given = p_args.keys();
	for (int i = 0; i < given.size(); i++) {
		const String key = given[i];
		if (!declared.has(key)) {
			unknown.push_back(key);
		}
	}
	if (unknown.is_empty()) {
		return true;
	}

	String message;
	if (unknown.size() == 1) {
		message = vformat("Unknown parameter '%s' for tool '%s'", unknown[0], String(p_def.name));
	} else {
		message = vformat("Unknown parameters %s for tool '%s'", String(", ").join(unknown), String(p_def.name));
	}
	// The one list both this gate and the TASK-050 suggestions print, so the two
	// can never drift apart. TASK-063 (b) appends the node-path half when the
	// mistake is a node-path spelling: the accepted list names the right member,
	// and the hint says what a path is (see `_node_path_alias_hint`).
	const String suggestion = _accepted_parameters_of(p_def) + _node_path_alias_hint(p_def, unknown);

	r_error = MCPToolError::invalid_params(message);
	r_error.data = _suggestion_data(suggestion);
	return false;
}

Variant MCPToolRegistry::call_tool(const StringName &p_name, const Dictionary &p_args, MCPToolError &r_error) const {
	const MCPToolDef *def = tools.getptr(p_name);
	if (def == nullptr) {
		r_error = MCPToolError::invalid_params(vformat("Unknown tool: %s", String(p_name)));
		r_error.data = _unknown_tool_suggestion_data(p_name);
		return Variant();
	}
	if (!_reject_unknown_arguments(*def, p_args, r_error)) {
		return Variant();
	}
	if (def->is_deferred()) {
		// GDR-20: a deferred tool cannot be answered by a single call. Refusing
		// here is what keeps the one-frame path honest - silently ticking once
		// would answer a lie (N samples of the same frame), which is exactly the
		// defect TASK-011 exists to remove. The transport routes these calls
		// through `call_deferred_tool()`.
		r_error = MCPToolError::internal(vformat("Tool '%s' answers across frames and must be called through the deferred channel", String(p_name)));
		return Variant();
	}
	if (def->handler == nullptr) {
		r_error = MCPToolError::internal(vformat("Tool has no handler: %s", String(p_name)));
		return Variant();
	}
	const Variant result = def->handler(p_args, r_error);
	// TASK-050 O-1/N-7: the immediate half of the one place every `-32602` gets
	// its `data.suggestion`.
	_add_invalid_params_suggestion(*def, r_error);
	return result;
}

bool MCPToolRegistry::is_deferred_tool(const StringName &p_name) const {
	const MCPToolDef *def = tools.getptr(p_name);
	return def != nullptr && def->is_deferred();
}

MCPDeferred::Task *MCPToolRegistry::call_deferred_tool(const StringName &p_name, const Dictionary &p_args, MCPToolError &r_error) const {
	const MCPToolDef *def = tools.getptr(p_name);
	if (def == nullptr) {
		r_error = MCPToolError::invalid_params(vformat("Unknown tool: %s", String(p_name)));
		r_error.data = _unknown_tool_suggestion_data(p_name);
		return nullptr;
	}
	// TASK-032 D4: the deferred half of the same gate, before the tool is handed
	// over to the transport (a task that was never demanded must not be created).
	if (!_reject_unknown_arguments(*def, p_args, r_error)) {
		return nullptr;
	}
	if (!def->is_deferred()) {
		r_error = MCPToolError::internal(vformat("Tool is not deferred: %s", String(p_name)));
		return nullptr;
	}
	MCPDeferred::Task *task = def->pending_handler(p_args, r_error);
	// TASK-050 O-1/N-7: the deferred half. A `pending_handler` validates its
	// arguments before it builds a task, so a refused call is refused *here* -
	// the O-1 rule must hold on this entry point too, not only on `call_tool`.
	_add_invalid_params_suggestion(*def, r_error);
	return task;
}
