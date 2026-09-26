/**************************************************************************/
/*  audio_shared.h                                                        */
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

#include "core/variant/variant.h"
#include "tool_builder.h"

// `AudioServer` is only ever used through a pointer here; the two group files
// include `servers/audio/audio_server.h` themselves when they need a method.
class AudioServer;

// ---------------------------------------------------------------------------
// TASK-034 (B5 batch 2): the engine-facing helpers the two audio groups share.
//
// They are *not* a third group: no tool is registered here and
// `docs/tool-groups-b5.json` is untouched. The file exists because
// `editor_audio_write` (4 tools) and `editor_audio_read` (2 tools) answer the
// same question - "what does this bus hold?" - and a private copy per group is
// what the module's helper-hoisting rule exists to prevent: the writer's
// read-back and the reader's answer would otherwise be free to disagree about
// the spelling of a bus property.
//
// The engine's own model is the design basis (GDR-23 / DESIGN-DETAIL section 21):
// `AudioServer` owns one `AudioBusLayout` whose buses are
// `{name, solo, mute, bypass, effects[], volume_db, send}`
// (`servers/audio/audio_bus_layout.h:42-59`), and every member has its own typed
// accessor on the server (`servers/audio/audio_server.h:237-278`). The six
// property names this module answers with are exactly the six members:
// `name`, `volume_db`, `mute`, `solo`, `bypass_effects`, `send` - so a value one
// tool reads can be fed straight into `editor_set_audio_bus_property`, and the
// `send` of one bus is the `name` of another (zero string surgery, GDR-25
// section 23.1).
// ---------------------------------------------------------------------------

namespace MCPTools {

// The six writable/readable bus members, as a `nullptr`-terminated list. One
// definition, so the writer's refusal and the reader's field set cannot drift.
const char *const *audio_bus_property_names();
int audio_bus_property_count();

// `AudioServer::get_singleton()`, or a `-32000` with a suggestion when the
// process has no audio server at all (a `--check-only` run). Every entry point
// below starts here, so no tool ever dereferences a null singleton.
AudioServer *audio_server_or_error(MCPToolError &r_error);

// The bus at `p_bus_index`, or `-32001` plus a suggestion listing the bus names
// the server really has. `p_parameter` names the caller's argument in the
// message ("bus_index").
bool require_audio_bus(AudioServer *p_server, int64_t p_bus_index, const String &p_parameter,
		MCPToolError &r_error, int &r_index);

// The index of the bus named `p_name`, or -1. `AudioServer::get_bus_index`
// (`audio_server.cpp:812`).
int audio_bus_index_of_name(AudioServer *p_server, const String &p_name);

// `"Master, Music, SFX"`, or `"(the server has no bus)"` - the suggestion text
// every refusal of this family ends with.
String audio_bus_name_list_for_message(AudioServer *p_server);

// One bus as this module answers it:
//   `{index, name, volume_db, mute, solo, bypass_effects, send, effect_count,
//     effects[]}` - the six `AudioBusLayout::Bus` members plus the effect list.
// `effects[]` entries are `{index, type, name, path, enabled}`.
Dictionary audio_bus_record(AudioServer *p_server, int p_bus_index);

// The effects of one bus, in the engine's own order.
Array audio_bus_effect_records(AudioServer *p_server, int p_bus_index);

// The current value of one of the six members, in the shape the reader answers
// (`FLOAT` for `volume_db`, `BOOL` for the three flags, `STRING` for
// `name`/`send`). An unknown name answers a NIL Variant - the caller is expected
// to have validated it with `audio_bus_property_names()` first.
Variant audio_bus_property_value(AudioServer *p_server, int p_bus_index, const String &p_property);

} // namespace MCPTools
