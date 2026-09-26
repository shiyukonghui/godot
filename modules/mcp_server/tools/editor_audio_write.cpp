/**************************************************************************/
/*  editor_audio_write.cpp                                                */
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
#include "editor_audio_write.h"

#include "audio_shared.h"
#include "editor_node_instantiate.h"
#include "tool_helpers.h"

#include "core/io/json.h"
#include "scene/2d/audio_stream_player_2d.h"
#include "servers/audio/audio_effect.h"
#include "servers/audio/audio_server.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-034 section 1: the engine reference behind each tool of this group.
//
//   add_audio_bus_on
//     * `AudioServer::add_bus(int p_at_pos)` (audio_server.cpp:677) - the engine
//       call whose *position* argument the contract's `after_bus_index` names:
//       `p_at_pos >= buses.size()` appends (:680-681), and index 0 is reserved
//       for "Master" (:682-688). This tool therefore passes
//       `after_bus_index + 1` (or -1 for "at the end"), which is the reading the
//       argument name promises - the migration source appended the bus and then
//       renamed whatever bus sat at `after_bus_index`
//       (`godot_mcp_gdext/src/commands/audio.rs:137-141`), so the index it
//       reported was not the bus it created.
//     * `AudioServer::set_bus_name(int, const String &)` (:763) with
//       `get_bus_index` (:812) / `get_bus_name` (:807) on both sides of it, so
//       `index` in the answer is the engine's own answer and not the request.
//       `set_bus_name` silently disambiguates a duplicate to `"<name> 2"`
//       (:783-798), which is why a duplicate is refused *before* the add.
//
//   add_audio_bus_effect_on
//     * `ClassDB::instantiate` through `MCPTools::instantiate_class`, then
//       `Object::is_class("AudioEffect")` - the engine's own inheritance test;
//       the migration source handed any instantiable class to
//       `add_bus_effect` and reported success
//       (`audio.rs:192-204`).
//     * `AudioServer::add_bus_effect(int, const Ref<AudioEffect> &, int)` (:923)
//       appends when the position is out of range (:939-940), and
//       `get_bus_effect_count` (:963) / `get_bus_effect` (:977) /
//       `is_bus_effect_enabled` (:1006) read it back. A fresh effect is enabled
//       (:934), which is what the answer reports.
//     * `Resource::set_name` is the engine's own name for the optional `name`
//       argument (an `AudioEffect` **is** a `Resource`,
//       `servers/audio/audio_effect.h`).
//
//   add_audio_player (the node half; the tool handler owns it)
//     * `Node::add_child` + `Node::set_owner` through `MCPTools::add_typed_child`
//       (editor_node_instantiate.cpp:119) - the module's one node-add path, which
//       is also what keeps the new node part of the saved scene;
//     * `AudioStreamPlayer2D::get_bus()` / `set_bus()`
//       (`scene/audio/audio_stream_player_2d.h`; the class the migration source
//       created, `audio.rs:75`). The bus name is answered so the caller can feed
//       it straight into the bus tools.
//
//   set_audio_bus_property_on
//     * the six typed setters of `AudioServer` (audio_server.h:244/250/256/259/262/265)
//       - one per member of `AudioBusLayout::Bus` (audio_bus_layout.h:42-59).
//       The migration source folded every member into `unwrap_or`: a mistyped
//       `volume_db` wrote `0.0`, a mistyped `mute` wrote `false`, an unknown
//       property was refused but a *wrong type* was not (`audio.rs:147-181`).
//     * `MCPTools::coerce_to_property_type` with the member's **own** slot width
//       (`volume_db` is a `float` member, so `FLOAT32`) - GDR-22's one gate, run
//       before the setter.
//     * `AudioBusLayout::Bus::send` is a `StringName` naming **another bus**
//       (audio_server.cpp:849), so a `send` is checked against the server's own
//       `get_bus_index` and refused with a suggestion when no bus has that name;
//       `editor_get_audio_bus_layout` answers the same spelling back.
// ---------------------------------------------------------------------------

namespace MCPTools {

Dictionary add_audio_bus_on(AudioServer *p_server, const String &p_bus_name, int64_t p_after_bus_index,
		MCPToolError &r_error) {
	const String name = p_bus_name.strip_edges();
	if (name.is_empty()) {
		r_error = MCPToolError::invalid_params("'name' must not be empty: it is the bus name every other tool and "
											   "the engine's own `send` reference address the bus by");
		return Dictionary();
	}
	const int count_before = p_server->get_bus_count();
	if (p_after_bus_index < -1 || p_after_bus_index >= (int64_t)count_before) {
		r_error = MCPToolError::invalid_params(vformat(
				"'after_bus_index' must be -1 (append at the end) or an existing bus index (0..%d); the server has %d "
				"bus(es): %s. Got %d",
				count_before - 1, count_before, audio_bus_name_list_for_message(p_server), (int64_t)p_after_bus_index));
		return Dictionary();
	}
	if (audio_bus_index_of_name(p_server, name) >= 0) {
		// `AudioServer::set_bus_name` would rename the new bus to "<name> 2"
		// (audio_server.cpp:783-798) while this tool reported the requested name,
		// and two buses with one name make `get_bus_index` (and therefore every
		// `send`) ambiguous.
		r_error = MCPToolError::tool_state(vformat("A bus named '%s' already exists", name),
				vformat("Bus names are the engine's own addressing (`AudioServer::get_bus_index` answers the first "
						"match), so a second bus with this name would make every `send` to it ambiguous; the server "
						"has: %s. Pick another name, or set the existing bus with editor_set_audio_bus_property",
						audio_bus_name_list_for_message(p_server)));
		return Dictionary();
	}

	// "after bus N" is "at position N+1" for the engine (and -1 appends).
	const int at_position = p_after_bus_index < 0 ? -1 : (int)p_after_bus_index + 1;
	p_server->add_bus(at_position);
	const int count_after = p_server->get_bus_count();
	if (count_after != count_before + 1) {
		r_error = MCPToolError::internal(vformat("AudioServer::add_bus(%d) left %d bus(es) (was %d)", at_position,
				count_after, count_before));
		return Dictionary();
	}
	// The engine appended when `at_position` was out of range, so the new bus is
	// the last one in that case and the insertion point otherwise.
	const int index = at_position < 0 ? count_after - 1 : at_position;
	p_server->set_bus_name(index, name);
	const String stored_name = p_server->get_bus_name(index);
	if (stored_name != name) {
		// The engine's own disambiguation; the caller is told which name really
		// exists instead of being told the name it asked for.
		r_error = MCPToolError::internal(vformat(
				"AudioServer::set_bus_name(%d, '%s') answered '%s' - the engine disambiguated a duplicate name",
				index, name, stored_name));
		return Dictionary();
	}

	Dictionary out;
	out["created"] = true;
	out["name"] = stored_name;
	out["index"] = index;
	out["after_bus_index"] = (int64_t)p_after_bus_index;
	out["bus_count"] = count_after;
	out["previous_bus_count"] = count_before;
	return out;
}

Dictionary add_audio_bus_effect_on(AudioServer *p_server, int64_t p_bus_index, const String &p_effect_type,
		const String &p_effect_name, bool p_effect_name_given, MCPToolError &r_error) {
	int bus_index = 0;
	if (!require_audio_bus(p_server, p_bus_index, "bus_index", r_error, bus_index)) {
		return Dictionary();
	}
	const String type = p_effect_type.strip_edges();
	if (type.is_empty()) {
		r_error = MCPToolError::invalid_params("'effect_type' must not be empty: it is an AudioEffect class name "
											   "(AudioEffectAmplify, AudioEffectReverb, AudioEffectChorus, ...)");
		return Dictionary();
	}
	MCPToolError instantiate_error;
	Object *created = instantiate_class(type, instantiate_error);
	if (created == nullptr) {
		r_error = MCPToolError::invalid_params(vformat("Unknown effect_type: '%s' (%s)", type,
				instantiate_error.message));
		return Dictionary();
	}
	if (!created->is_class(StringName("AudioEffect"))) {
		const String actual = created->get_class();
		// The engine's own inheritance test, run before the effect is handed to
		// the server: `add_bus_effect` takes a `Ref<AudioEffect>` and a wrong
		// class would otherwise be an engine-side crash/refusal nobody sees.
		Ref<Resource> released = Ref<Resource>(Object::cast_to<Resource>(created));
		r_error = MCPToolError::invalid_params(vformat(
				"effect_type '%s' is not an AudioEffect (it is a %s)", type, actual));
		return Dictionary();
	}
	Ref<AudioEffect> effect = Ref<AudioEffect>(Object::cast_to<AudioEffect>(created));
	if (p_effect_name_given) {
		const String name = p_effect_name.strip_edges();
		if (name.is_empty()) {
			r_error = MCPToolError::invalid_params("'name' must not be empty when it is given: it becomes the effect "
												   "resource's own Resource::set_name; omit it for an unnamed effect");
			return Dictionary();
		}
		effect->set_name(name);
	}

	const int count_before = p_server->get_bus_effect_count(bus_index);
	p_server->add_bus_effect(bus_index, effect, -1);
	const int count_after = p_server->get_bus_effect_count(bus_index);
	if (count_after != count_before + 1) {
		r_error = MCPToolError::internal(vformat(
				"AudioServer::add_bus_effect(%d, ...) left %d effect(s) on the bus (was %d)", bus_index, count_after,
				count_before));
		return Dictionary();
	}
	const int effect_index = count_after - 1;
	const Ref<AudioEffect> stored = p_server->get_bus_effect(bus_index, effect_index);
	if (stored.is_null()) {
		r_error = MCPToolError::internal(vformat(
				"AudioServer::get_bus_effect(%d, %d) answers nothing right after the effect was added", bus_index,
				effect_index));
		return Dictionary();
	}

	Dictionary out;
	out["added"] = true;
	out["bus_index"] = bus_index;
	out["bus_name"] = p_server->get_bus_name(bus_index);
	out["effect_type"] = stored->get_class();
	out["effect_index"] = effect_index;
	out["effect_count"] = count_after;
	out["name"] = stored->get_name();
	out["enabled"] = p_server->is_bus_effect_enabled(bus_index, effect_index);
	return out;
}

Dictionary set_audio_bus_property_on(AudioServer *p_server, int64_t p_bus_index, const String &p_property,
		const Variant &p_value, MCPToolError &r_error) {
	int bus_index = 0;
	if (!require_audio_bus(p_server, p_bus_index, "bus_index", r_error, bus_index)) {
		return Dictionary();
	}
	const String property = p_property.strip_edges();
	bool known = false;
	Vector<String> valid;
	for (int i = 0; i < audio_bus_property_count(); i++) {
		const String candidate = audio_bus_property_names()[i];
		valid.push_back(candidate);
		if (candidate == property) {
			known = true;
		}
	}
	if (!known) {
		// The migration source's own branch was an unknown-property refusal, but
		// a *known* property with the wrong type was written as its default
		// (`audio.rs:154-177`); both halves are refused here.
		r_error = MCPToolError::invalid_params(vformat(
				"Unknown bus property '%s'. The writable members of an audio bus are: %s", p_property,
				String(", ").join(valid)));
		return Dictionary();
	}

	const String bus_name_before = p_server->get_bus_name(bus_index);
	const Variant old_value = audio_bus_property_value(p_server, bus_index, property);
	// The value the engine's setter really receives, in the member's own type -
	// which is what `applied` compares the read-back against (GDR-25 23.4's
	// level 2: the answer's `new_value` is the engine's, never the request).
	Variant requested;

	if (property == "name") {
		if (p_value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'value' must be a string for 'name' (got %s)",
					Variant::get_type_name(p_value.get_type())));
			return Dictionary();
		}
		const String wanted = ((String)p_value).strip_edges();
		if (wanted.is_empty()) {
			r_error = MCPToolError::invalid_params("'value' must not be empty for 'name': a bus name is how the "
												   "engine and every `send` address the bus");
			return Dictionary();
		}
		if (bus_index == 0 && wanted != "Master") {
			// `set_bus_name(0, ...)` returns in silence unless the name is
			// "Master" (audio_server.cpp:765-767), so a caller that asked for a
			// rename of bus 0 would be told nothing.
			r_error = MCPToolError::tool_state("Bus 0 is always named \"Master\"",
					"AudioServer::set_bus_name refuses to rename bus 0 to anything but \"Master\" "
					"(audio_server.cpp:765-767); rename another bus, or add a bus with editor_add_audio_bus");
			return Dictionary();
		}
		const int other = audio_bus_index_of_name(p_server, wanted);
		if (other >= 0 && other != bus_index) {
			r_error = MCPToolError::tool_state(vformat("A bus named '%s' already exists (index %d)", wanted, other),
					"set_bus_name would rename this bus to \"<name> 2\" in silence (audio_server.cpp:783-798); the "
					"server has: " + audio_bus_name_list_for_message(p_server));
			return Dictionary();
		}
		p_server->set_bus_name(bus_index, wanted);
		requested = wanted;
	} else if (property == "volume_db") {
		Variant converted;
		// The member is a `float` (audio_bus_layout.h:55), so the gate is told the
		// slot width explicitly: `FLOAT32` is judged as 32 bits whatever the
		// build's `real_t` is (GDR-24 section 22.2).
		if (!coerce_to_property_type(p_value, Variant::FLOAT, converted, r_error, "value", ValueSlot::FLOAT32)) {
			return Dictionary();
		}
		const double db = converted;
		// MCP-NARROWING: G24-AUDIO-VOLUME - `coerce_to_property_type` judged the
		// value as a `FLOAT32` slot immediately above, so this copy into the
		// engine's `float` member cannot narrow an unfit value.
		p_server->set_bus_volume_db(bus_index, (float)db);
		// Compared at the member's own width: the request is a `double` and the
		// member a `float`, so `0.1` would never compare equal as a `double`
		// (PLAYBOOK section 20.6's trap).
		// MCP-NARROWING: G24-AUDIO-VOLUME - the comparison's own width (the same
		// `FLOAT32` slot `coerce_to_property_type` judged above); nothing is
		// stored through this cast.
		requested = Variant((double)(float)db);
	} else if (property == "mute" || property == "solo" || property == "bypass_effects") {
		Variant converted;
		if (!coerce_to_property_type(p_value, Variant::BOOL, converted, r_error, "value")) {
			return Dictionary();
		}
		const bool flag = converted;
		if (property == "mute") {
			p_server->set_bus_mute(bus_index, flag);
		} else if (property == "solo") {
			p_server->set_bus_solo(bus_index, flag);
		} else {
			p_server->set_bus_bypass_effects(bus_index, flag);
		}
		requested = flag;
	} else { // "send"
		if (p_value.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'value' must be a string for 'send' (got %s)",
					Variant::get_type_name(p_value.get_type())));
			return Dictionary();
		}
		const String target = ((String)p_value).strip_edges();
		if (!target.is_empty() && audio_bus_index_of_name(p_server, target) < 0) {
			// A send to a bus that does not exist is accepted by the engine and
			// then routes nowhere; refusing it is what keeps "configured" and
			// "working" the same thing.
			r_error = MCPToolError::not_found(vformat("Audio bus '%s' ('send' target)", target),
					"'send' names another bus of this server, and no bus has that name; the server has: " +
							audio_bus_name_list_for_message(p_server) +
							". `editor_get_audio_bus_layout` answers each bus's `name`, which is the spelling this "
							"argument takes");
			return Dictionary();
		}
		p_server->set_bus_send(bus_index, StringName(target));
		requested = target;
	}

	const Variant new_value = audio_bus_property_value(p_server, bus_index, property);
	// Two different questions, two different fields: `changed` is "the bus is not
	// what it was", `applied` is "the engine stores what was asked for". Neither
	// is inferred from the other, and `applied: false` is never reported as a
	// successful write (PLAYBOOK section 20.6).
	const bool applied = new_value.get_type() == requested.get_type() && new_value == requested;

	Dictionary out;
	out["bus_index"] = bus_index;
	out["bus_name"] = p_server->get_bus_name(bus_index);
	out["previous_bus_name"] = bus_name_before;
	out["property"] = property;
	out["old_value"] = serialize_variant(old_value);
	out["new_value"] = serialize_variant(new_value);
	out["changed"] = !(old_value.get_type() == new_value.get_type() && old_value == new_value);
	out["applied"] = applied;
	out["bus_count"] = p_server->get_bus_count();
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

static bool _require_non_empty(const Dictionary &p_args, const String &p_key, String &r_out, MCPToolError &r_error) {
	if (!require_string(p_args, p_key, r_out, r_error)) {
		return false;
	}
	if (r_out.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params(vformat("'%s' must not be empty", p_key));
		return false;
	}
	return true;
}

static Variant _tool_add_audio_bus(const Dictionary &p_args, MCPToolError &r_error) {
	String name;
	if (!_require_non_empty(p_args, "name", name, r_error)) {
		return Variant();
	}
	int64_t after_bus_index = -1;
	if (!optional_int(p_args, "after_bus_index", -1, after_bus_index, r_error)) {
		return Variant();
	}
	AudioServer *server = audio_server_or_error(r_error);
	if (server == nullptr) {
		return Variant();
	}
	return add_audio_bus_on(server, name, after_bus_index, r_error);
}

static Variant _tool_add_audio_bus_effect(const Dictionary &p_args, MCPToolError &r_error) {
	int64_t bus_index = 0;
	if (!require_int(p_args, "bus_index", bus_index, r_error)) {
		return Variant();
	}
	String effect_type;
	if (!_require_non_empty(p_args, "effect_type", effect_type, r_error)) {
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", String(), name, r_error)) {
		return Variant();
	}
	AudioServer *server = audio_server_or_error(r_error);
	if (server == nullptr) {
		return Variant();
	}
	return add_audio_bus_effect_on(server, bus_index, effect_type, name, p_args.has("name"), r_error);
}

static Variant _tool_add_audio_player(const Dictionary &p_args, MCPToolError &r_error) {
	String parent_path;
	if (!optional_string(p_args, "parent_path", ".", parent_path, r_error)) {
		return Variant();
	}
	String name;
	if (!optional_string(p_args, "name", "AudioPlayer", name, r_error)) {
		return Variant();
	}
	if (name.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'name' must not be empty: it is the node name the caller and every "
											   "later node_path address the player by");
		return Variant();
	}
	// The argument contract runs before the editor prerequisite, so a mistyped
	// call is answered without an editor.
	if (!require_editor_ui(r_error, "editor audio writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	Node *parent = find_node(root, parent_path);
	if (parent == nullptr) {
		r_error = MCPToolError::not_found(vformat("Parent node '%s' in the edited scene", parent_path),
				"'parent_path' is relative to the edited scene root ('.' is the root itself); call "
				"editor_get_scene_tree to list the nodes that are there");
		return Variant();
	}
	const String node_name = name.strip_edges();
	if (parent->has_node(NodePath(node_name))) {
		r_error = MCPToolError::tool_state(
				vformat("Node '%s' already has a child named '%s'", relative_path(root, parent), node_name),
				"Node::add_child would silently rename the new player to \"<name>2\", so nothing was created; pick "
				"another 'name' or remove the existing node first");
		return Variant();
	}

	AudioStreamPlayer2D *player = memnew(AudioStreamPlayer2D);
	add_typed_child(root, parent, node_name, player);

	// Read back: the node is really a child of the parent and really is the class
	// the answer claims (the "a created thing is read back" rule).
	Node *created = parent->get_node_or_null(NodePath(node_name));
	AudioStreamPlayer2D *stored = Object::cast_to<AudioStreamPlayer2D>(created);
	if (stored == nullptr) {
		r_error = MCPToolError::internal(vformat(
				"The audio player was added under '%s' but the parent does not answer an AudioStreamPlayer2D named "
				"'%s'",
				parent_path, node_name));
		return Variant();
	}
	Dictionary out;
	out["created"] = true;
	out["name"] = String(stored->get_name());
	out["node_path"] = relative_path(root, stored);
	out["type"] = stored->get_class();
	out["parent_path"] = relative_path(root, parent);
	out["owner"] = stored->get_owner() != nullptr ? relative_path(root, stored->get_owner()) : String();
	// The bus name is what `editor_set_audio_bus_property` / the bus finds; the
	// default is the engine's own "Master".
	out["bus"] = String(stored->get_bus());
	out["playing"] = stored->is_playing();
	return out;
}

static Variant _tool_set_audio_bus_property(const Dictionary &p_args, MCPToolError &r_error) {
	int64_t bus_index = 0;
	if (!require_int(p_args, "bus_index", bus_index, r_error)) {
		return Variant();
	}
	String property;
	if (!_require_non_empty(p_args, "property", property, r_error)) {
		return Variant();
	}
	if (!p_args.has("value")) {
		r_error = MCPToolError::invalid_params("Missing required parameter: value");
		return Variant();
	}
	AudioServer *server = audio_server_or_error(r_error);
	if (server == nullptr) {
		return Variant();
	}
	return set_audio_bus_property_on(server, bus_index, property, p_args["value"], r_error);
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
//
// The authoritative `description` and `inputSchema` of each tool are the
// contract entries of docs/tools_list.renamed.json, character for character; the
// schemas are *parsed* from the exact contract JSON instead of being rebuilt as
// a hand-written Dictionary, because gate 1 compares all three fields verbatim.
// ---------------------------------------------------------------------------
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_audio_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_audio_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_add_audio_bus", String::utf8(R"desc(添加音频总线)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		// `after_bus_index` is the second tool of the module whose schema carries
		// an **integer** default: the engine's JSON parser stores every number as
		// a `double` and the wire would spell `-1.0` where the contract says `-1`,
		// so the field is put back as an INT Variant
		// (`MCPTools::schema_with_integer_defaults`, tool_helpers.cpp).
		builder.schema(schema_with_integer_defaults(
				_schema_from_json(R"schema({"properties":{"after_bus_index":{"default":-1,"type":"integer"},"name":{"type":"string"}},"required":["name"],"type":"object"})schema"),
				{ StringName("after_bus_index") }));
		builder.handler(_tool_add_audio_bus).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_add_audio_bus_effect", String::utf8(R"desc(添加音频总线效果)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"bus_index":{"type":"integer"},"effect_type":{"type":"string"},"name":{"type":"string"}},"required":["bus_index","effect_type"],"type":"object"})schema"));
		builder.handler(_tool_add_audio_bus_effect).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_add_audio_player", String::utf8(R"desc(添加音频播放器)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"name":{"default":"AudioPlayer","type":"string"},"parent_path":{"default":".","type":"string"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_add_audio_player).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_audio_bus_property", String::utf8(R"desc(设置音频总线属性)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"bus_index":{"type":"integer"},"property":{"type":"string"},"value":{"description":"属性值"}},"required":["bus_index","property","value"],"type":"object"})schema"));
		builder.handler(_tool_set_audio_bus_property).register_into(r_registry);
	}
}
