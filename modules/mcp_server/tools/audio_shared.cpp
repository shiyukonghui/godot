/**************************************************************************/
/*  audio_shared.cpp                                                      */
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
#include "audio_shared.h"

#include "servers/audio/audio_effect.h"
#include "servers/audio/audio_server.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// The engine reference of this file (TASK-034).
//
//   * `AudioServer::get_bus_count()` (audio_server.h:237) / `get_bus_name`
//     (:245) / `get_bus_index` (:246) - the index<->name pair the whole family
//     is addressed by. The migration source mixed the two up: `add_audio_bus`
//     appended a bus and then renamed *whatever sat at* `after_bus_index`
//     (`godot_mcp_gdext/src/commands/audio.rs:137-141`), so the bus it reported
//     was not the bus it created.
//   * `set_bus_volume_db(int, float)` (:250), `set_bus_send(int, const
//     StringName &)` (:256), `set_bus_mute` (:262), `set_bus_solo` (:259),
//     `set_bus_bypass_effects` (:265), `set_bus_name(int, const String &)`
//     (:244) - the six members of `AudioBusLayout::Bus` (audio_bus_layout.h:42-59),
//     one typed setter each. The tool writes through these, never through a
//     property bag, so the type of every member is the engine's own.
//   * `get_bus_effect_count` (:271) / `get_bus_effect` (:272) / `is_bus_effect_enabled`
//     (:278) - the effect half of the layout, read back so an already added
//     effect can be named.
// ---------------------------------------------------------------------------

namespace {

const char *const AUDIO_BUS_PROPERTY_NAMES[] = {
	"name",
	"volume_db",
	"mute",
	"solo",
	"bypass_effects",
	"send",
	nullptr,
};

} // namespace

namespace MCPTools {

const char *const *audio_bus_property_names() {
	return AUDIO_BUS_PROPERTY_NAMES;
}

int audio_bus_property_count() {
	return 6;
}

AudioServer *audio_server_or_error(MCPToolError &r_error) {
	AudioServer *server = AudioServer::get_singleton();
	if (server == nullptr) {
		r_error = MCPToolError::tool_state("The AudioServer singleton is not available in this process",
				"AudioServer::get_singleton() is created by the engine's server setup; run the tool in a normal "
				"editor or game process (a --check-only run has no servers)");
		return nullptr;
	}
	return server;
}

bool require_audio_bus(AudioServer *p_server, int64_t p_bus_index, const String &p_parameter,
		MCPToolError &r_error, int &r_index) {
	const int count = p_server->get_bus_count();
	if (p_bus_index < 0 || p_bus_index >= (int64_t)count) {
		r_error = MCPToolError::not_found(vformat("Audio bus index %d", (int64_t)p_bus_index),
				vformat("'%s' is the engine's own bus index (0..%d); bus 0 is always \"Master\". The server has: %s. "
						"Call editor_get_audio_bus_layout to read the indices",
						p_parameter, count - 1, audio_bus_name_list_for_message(p_server)));
		return false;
	}
	r_index = (int)p_bus_index;
	return true;
}

int audio_bus_index_of_name(AudioServer *p_server, const String &p_name) {
	// The engine's own lookup; it answers the *first* bus with that name, which
	// is why `editor_add_audio_bus` refuses a duplicate instead of creating one.
	return p_server->get_bus_index(StringName(p_name));
}

String audio_bus_name_list_for_message(AudioServer *p_server) {
	const int count = p_server->get_bus_count();
	if (count <= 0) {
		return String("(the server has no bus)");
	}
	Vector<String> names;
	for (int i = 0; i < count; i++) {
		names.push_back(vformat("%d:%s", i, p_server->get_bus_name(i)));
	}
	return String(", ").join(names);
}

Array audio_bus_effect_records(AudioServer *p_server, int p_bus_index) {
	Array effects;
	const int effect_count = p_server->get_bus_effect_count(p_bus_index);
	for (int i = 0; i < effect_count; i++) {
		const Ref<AudioEffect> effect = p_server->get_bus_effect(p_bus_index, i);
		// `Resource::get_name()` answers a `StringName`; the two branches have to
		// agree on one type (a `?:` of `String` and `StringName` is ambiguous in
		// this fork's MSVC build).
		StringName effect_name;
		if (effect.is_valid()) {
			effect_name = effect->get_name();
		}
		Dictionary record;
		record["index"] = i;
		record["type"] = effect.is_valid() ? effect->get_class() : String();
		// A bus effect is a sub-resource of the layout, so its `path` is empty
		// unless it was saved as an external resource; the `name` is the engine's
		// own `Resource::get_name()`, which is what `editor_add_audio_bus_effect`
		// writes when the caller gives one (GDR-25 section 23.5's shape).
		record["name"] = effect_name;
		record["path"] = effect.is_valid() ? effect->get_path() : String();
		record["enabled"] = p_server->is_bus_effect_enabled(p_bus_index, i);
		effects.push_back(record);
	}
	return effects;
}

Dictionary audio_bus_record(AudioServer *p_server, int p_bus_index) {
	Dictionary record;
	record["index"] = p_bus_index;
	record["name"] = p_server->get_bus_name(p_bus_index);
	record["volume_db"] = p_server->get_bus_volume_db(p_bus_index);
	record["mute"] = p_server->is_bus_mute(p_bus_index);
	record["solo"] = p_server->is_bus_solo(p_bus_index);
	record["bypass_effects"] = p_server->is_bus_bypassing_effects(p_bus_index);
	record["send"] = String(p_server->get_bus_send(p_bus_index));
	record["effect_count"] = p_server->get_bus_effect_count(p_bus_index);
	record["effects"] = audio_bus_effect_records(p_server, p_bus_index);
	return record;
}

Variant audio_bus_property_value(AudioServer *p_server, int p_bus_index, const String &p_property) {
	if (p_property == "name") {
		return p_server->get_bus_name(p_bus_index);
	}
	if (p_property == "volume_db") {
		return p_server->get_bus_volume_db(p_bus_index);
	}
	if (p_property == "mute") {
		return p_server->is_bus_mute(p_bus_index);
	}
	if (p_property == "solo") {
		return p_server->is_bus_solo(p_bus_index);
	}
	if (p_property == "bypass_effects") {
		return p_server->is_bus_bypassing_effects(p_bus_index);
	}
	if (p_property == "send") {
		return String(p_server->get_bus_send(p_bus_index));
	}
	return Variant();
}

} // namespace MCPTools
