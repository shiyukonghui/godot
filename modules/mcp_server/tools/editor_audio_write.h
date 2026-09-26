/**************************************************************************/
/*  editor_audio_write.h                                                  */
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

#include "tool_builder.h"

class AudioServer;

// ---------------------------------------------------------------------------
// TASK-034 (B5 batch 2): the `editor_audio_write` group (4 tools).
//
//   * `editor_add_audio_bus`           - `AudioServer::add_bus(int at_pos)` with
//                                        the *insert-after* semantics the
//                                        argument's name promises, then the
//                                        engine's own `set_bus_name`.
//   * `editor_add_audio_bus_effect`    - `ClassDB` instantiation checked against
//                                        `AudioEffect`, then
//                                        `AudioServer::add_bus_effect`.
//   * `editor_add_audio_player`        - a node of the migration source's class
//                                        (`AudioStreamPlayer2D`) added to the
//                                        edited scene with its owner set.
//   * `editor_set_audio_bus_property`  - one of the six `AudioBusLayout::Bus`
//                                        members through its own typed setter,
//                                        with the module's value gate in front of
//                                        it and a read-back behind it.
//
// The engine's own model is the design basis (GDR-23); the per-tool engine
// reference is in the `.cpp` beside each entry point and in REPORT-034.
// ---------------------------------------------------------------------------

namespace MCPTools {

// `AudioServer::add_bus(p_at_pos)` (`audio_server.cpp:677-731`) inserts *at*
// `p_at_pos` and appends when it is out of range; the contract's argument is
// named `after_bus_index`, so this maps it to the engine call the name promises
// (-1 and every "after the last bus" spelling append, otherwise insert after the
// named bus). Every bus of the server is validated first, so a refused call
// creates nothing.
Dictionary add_audio_bus_on(AudioServer *p_server, const String &p_bus_name, int64_t p_after_bus_index,
		MCPToolError &r_error);

// Instantiates `p_effect_type` through `ClassDB`, refuses anything that is not an
// `AudioEffect`, and appends it to the bus. `p_effect_name` is optional and
// becomes the effect resource's `Resource::set_name()`.
Dictionary add_audio_bus_effect_on(AudioServer *p_server, int64_t p_bus_index, const String &p_effect_type,
		const String &p_effect_name, bool p_effect_name_given, MCPToolError &r_error);

// Writes one of the six `AudioBusLayout::Bus` members of `p_bus_index` through
// its own typed `AudioServer` setter. The value is converted and width-judged by
// the module's one gate before the setter runs, and the answer carries the
// read-back plus `applied` (whether the engine stored what was asked).
Dictionary set_audio_bus_property_on(AudioServer *p_server, int64_t p_bus_index, const String &p_property,
		const Variant &p_value, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_audio_write_tools(MCPToolRegistry &r_registry);
