/**************************************************************************/
/*  editor_profiling_read.h                                               */
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

// ---------------------------------------------------------------------------
// TASK-034 (B5 batch 2): the `editor_profiling_read` group (1 tool).
//
// `editor_get_performance_monitors` answers **every** monitor the engine offers,
// keyed by the engine's own monitor name:
//
//   * `Performance::get_monitor(Monitor)` (`main/performance.h:140`,
//     `Performance::get_singleton()`);
//   * `Performance::get_monitor_name(Monitor)` (:141), whose table
//     (`main/performance.cpp:174-249`) is the source of the keys
//     (`time/fps`, `memory/static`, `raster/total_draw_calls`, ...), so no name
//     in the answer is invented here;
//   * `MONITOR_MAX` (:130) is the count the iteration runs to, so a monitor the
//     engine adds is answered without this file changing.
//
// The migration source answered a hand-written subset with its own key names and
// its own unit conversions (`godot_mcp_gdext/src/commands/profiling.rs:32-60`:
// `process_msec`, `static_mb`, ...), and `get_editor_performance` was merged into
// this tool by GDR-17. The engine's own names and raw values are used instead, so
// a value can be compared with what the editor's own Monitors panel shows; the
// per-process declaration (`source`, `editor_process`) is part of the answer
// because `Performance` is a singleton of the process the tool runs in.
// ---------------------------------------------------------------------------

namespace MCPTools {

// `{source, editor_process, monitor_count, monitors: {"<engine monitor name>":
// <value>}}`. Every monitor from 0 to `MONITOR_MAX` is included; a name the
// engine answers empty for is skipped rather than keyed by "".
Dictionary performance_monitors();

} // namespace MCPTools

void register_editor_profiling_read_tools(MCPToolRegistry &r_registry);
