/**************************************************************************/
/*  editor_profiling_read.cpp                                             */
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
#include "editor_profiling_read.h"

#include "tool_helpers.h"

#include "core/io/json.h"
#include "main/performance.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-034 section 1: the engine reference behind this tool.
//
//   * `Performance::get_singleton()` - the process' own monitor table. It is a
//     singleton of the running process, which is why `source` and
//     `editor_process` are part of the answer (GDR-25 section 23.3's
//     "declare which process" rule).
//   * `Performance::get_monitor_name(Monitor)` (main/performance.h:141) - the
//     engine's own key names (`time/fps`, `time/process`, `memory/static`,
//     `object/nodes`, `raster/total_draw_calls`, `video/video_mem`,
//     `physics_3d/active_objects`, `navigation_2d/...`,
//     `pipeline/compilations_*`, `audio/driver/output_latency` - the table is
//     main/performance.cpp:174-249), used verbatim so nothing here invents a
//     name or a unit.
//   * `Performance::get_monitor(Monitor)` (:140) - the value, answered as the
//     engine's own `double`, without the migration source's unit conversions
//     (`profiling.rs:36-52` divided memory by 1024*1024 and seconds by 1000).
//   * `Performance::Monitor::MONITOR_MAX` (:130) - the iteration bound, so the
//     answer covers every monitor this build has.
// ---------------------------------------------------------------------------

namespace MCPTools {

Dictionary performance_monitors() {
	Dictionary out;
	out["source"] = "engine_process";
	out["editor_process"] = is_editor_process();
	Performance *performance = Performance::get_singleton();
	if (performance == nullptr) {
		out["monitor_count"] = 0;
		out["monitors"] = Dictionary();
		out["unavailable_reason"] = "Performance::get_singleton() answered nothing in this process";
		return out;
	}
	Dictionary monitors;
	int count = 0;
	for (int i = 0; i < (int)Performance::MONITOR_MAX; i++) {
		const Performance::Monitor monitor = (Performance::Monitor)i;
		// The engine's own name for the slot; an empty answer (a monitor this
		// build has no name table entry for) is skipped rather than keyed by "".
		const String name = performance->get_monitor_name(monitor);
		if (name.is_empty()) {
			continue;
		}
		monitors[name] = performance->get_monitor(monitor);
		count++;
	}
	out["monitor_count"] = count;
	out["monitors"] = monitors;
	return out;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tool
// ---------------------------------------------------------------------------

static Variant _tool_get_performance_monitors(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	(void)r_error;
	// No editor prerequisite: the monitor table exists in any process that has a
	// `Performance` singleton, and the answer says which process it came from.
	return performance_monitors();
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
//
// The authoritative `description` and `inputSchema` are the contract entry of
// docs/tools_list.renamed.json, character for character.
// ---------------------------------------------------------------------------
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_profiling_read.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_profiling_read_tools(MCPToolRegistry &r_registry) {
	ToolBuilder builder("editor_get_performance_monitors", String::utf8(R"desc(获取编辑器性能指标)desc"));
	builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false);
	builder.schema(_schema_from_json(R"schema({"properties":{},"required":[],"type":"object"})schema"));
	builder.handler(_tool_get_performance_monitors).register_into(r_registry);
}
