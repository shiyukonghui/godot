/**************************************************************************/
/*  editor_audio_read.h                                                   */
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
// TASK-034 (B5 batch 2): the `editor_audio_read` group (2 tools).
//
// The two readers are the two halves of one answer, split by GDR-17's
// "no lossy merge" rule rather than duplicated:
//
//   * `editor_get_audio_info`        - the **server** as a whole: bus count,
//                                      mix rate, output latency, the output
//                                      device, the playback speed scale and the
//                                      bus names/effect counts. It is the
//                                      "what audio does this project have"
//                                      question, and it answers the same
//                                      per-bus records only as names + counts.
//   * `editor_get_audio_bus_layout`  - the layout itself: every
//                                      `AudioBusLayout::Bus` member of every bus
//                                      plus its effect list, i.e. the shape
//                                      `editor_set_audio_bus_property` and
//                                      `editor_add_audio_bus_effect` write.
//
// The engine's own model is the design basis (GDR-23); the per-tool engine
// reference is in the `.cpp` beside each entry point and in REPORT-034.
// ---------------------------------------------------------------------------

namespace MCPTools {

// `{source, editor_process, bus_count, mix_rate, output_latency, output_device,
//   playback_speed_scale, output_device_count, effect_count,
//   buses: [{index, name, effect_count}]}`
//
// `source` names the process the numbers come from (GDR-25 section 23.3's
// "declare the source" rule applies to any per-process answer): `AudioServer` is
// the *engine process*' own server, and `editor_process` says whether that
// process is an editor or a game.
Dictionary audio_info(AudioServer *p_server);

// `{source, editor_process, bus_count, buses: [<audio_bus_record>...]}` - the
// full layout, in the engine's own bus order, each record carrying the six
// members under the names `editor_set_audio_bus_property` accepts.
Dictionary audio_bus_layout(AudioServer *p_server);

} // namespace MCPTools

void register_editor_audio_read_tools(MCPToolRegistry &r_registry);
