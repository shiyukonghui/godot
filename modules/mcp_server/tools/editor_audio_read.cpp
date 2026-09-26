/**************************************************************************/
/*  editor_audio_read.cpp                                                 */
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
#include "editor_audio_read.h"

#include "audio_shared.h"
#include "tool_helpers.h"

#include "core/io/json.h"
#include "servers/audio/audio_server.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-034 section 1: the engine reference behind each tool of this group.
//
//   editor_get_audio_info
//     * `AudioServer::get_bus_count()` (audio_server.h:237) and
//       `get_bus_name(int)` (:245);
//     * `get_mix_rate()` (audio_server.h:323, implemented as
//       `AudioDriver::get_singleton()->get_mix_rate()`, audio_server.cpp:1500) -
//       the sample rate the engine really mixes at, which is a fact about this
//       process rather than about the project;
//     * `get_output_latency()` (audio_server.h:330 -> `AudioDriver::get_latency()`,
//       audio_server.cpp:1516) and `get_output_device()` (:347 -> audio_server.cpp:1665);
//     * `get_playback_speed_scale()` (:286). The migration source answered only
//       `bus_count` + `output_latency` (`audio.rs:82-88`), which left the mix
//       rate - the one number a caller needs to reason about latency - out.
//
//   editor_get_audio_bus_layout
//     * the six `AudioBusLayout::Bus` members (audio_bus_layout.h:42-59) through
//       their own typed getters (audio_server.h:245-257) plus the effect list
//       (`get_bus_effect_count` :271, `get_bus_effect` :272,
//       `is_bus_effect_enabled` :278). The migration source's version of this
//       answer (`audio.rs:91-130`) is the one this shape follows, with the two
//       differences REPORT-034 records: the effect record carries the engine's
//       own `Resource::get_name()`/`get_path()` (so an effect added by
//       `editor_add_audio_bus_effect` can be identified), and the answer declares
//       which process it came from.
//
// Both are per-process answers: `AudioServer` is a singleton of the process the
// tool runs in, so `source` + `editor_process` are part of the answer and the
// caller can never mistake a game's buses for the editor's.
// ---------------------------------------------------------------------------

namespace MCPTools {

Dictionary audio_info(AudioServer *p_server) {
	Dictionary out;
	out["source"] = "engine_process";
	out["editor_process"] = is_editor_process();
	const int bus_count = p_server->get_bus_count();
	out["bus_count"] = bus_count;
	out["mix_rate"] = p_server->get_mix_rate();
	out["output_latency"] = p_server->get_output_latency();
	out["output_device"] = p_server->get_output_device();
	out["output_device_count"] = p_server->get_output_device_list().size();
	out["playback_speed_scale"] = p_server->get_playback_speed_scale();

	Array buses;
	int effect_count = 0;
	for (int i = 0; i < bus_count; i++) {
		const int bus_effects = p_server->get_bus_effect_count(i);
		effect_count += bus_effects;
		Dictionary entry;
		entry["index"] = i;
		entry["name"] = p_server->get_bus_name(i);
		entry["effect_count"] = bus_effects;
		buses.push_back(entry);
	}
	out["buses"] = buses;
	out["effect_count"] = effect_count;
	return out;
}

Dictionary audio_bus_layout(AudioServer *p_server) {
	Dictionary out;
	out["source"] = "engine_process";
	out["editor_process"] = is_editor_process();
	const int bus_count = p_server->get_bus_count();
	out["bus_count"] = bus_count;
	Array buses;
	for (int i = 0; i < bus_count; i++) {
		buses.push_back(audio_bus_record(p_server, i));
	}
	out["buses"] = buses;
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

static Variant _tool_get_audio_info(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	AudioServer *server = audio_server_or_error(r_error);
	if (server == nullptr) {
		return Variant();
	}
	return audio_info(server);
}

static Variant _tool_get_audio_bus_layout(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	AudioServer *server = audio_server_or_error(r_error);
	if (server == nullptr) {
		return Variant();
	}
	return audio_bus_layout(server);
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
//
// The authoritative `description` and `inputSchema` of each tool are the
// contract entries of docs/tools_list.renamed.json, character for character.
// ---------------------------------------------------------------------------
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_audio_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_audio_read_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_get_audio_info", String::utf8(R"desc(获取音频信息)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{},"required":[],"type":"object"})schema"));
		builder.handler(_tool_get_audio_info).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_get_audio_bus_layout", String::utf8(R"desc(获取音频总线布局)desc"));
		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{},"required":[],"type":"object"})schema"));
		builder.handler(_tool_get_audio_bus_layout).register_into(r_registry);
	}
}
