/**************************************************************************/
/*  editor_input_read.cpp                                                 */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/
#include "editor_input_read.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/input/input_map.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"
#include "core/variant/variant.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// editor_get_input_actions (old `get_input_actions`, input.rs:32/104)
//
// The read-only member of the editor input family. `docs/tool-groups-b2.json`
// gives the reason it stands alone: it cannot join `editor_input_simulation`
// (the `mutating` axis differs - and a group may only carry one value, GDR-18)
// nor `editor_playback`, so it is a one-tool group.
//
// **Which `InputMap` this reads** (DECISIONS D56). The mapping's reason for the
// `editor_` channel is explicit - "reads the *editor process'* InputMap
// singleton (not `project.godot`)" - and that is exactly what this tool does:
// `InputMap::get_singleton()`. It is therefore a *read of the editor's own input
// configuration*, served by the editor endpoint, and it says nothing about the
// actions a running game sees. The tool that observes a game's input is a
// `scope = game` tool; the tool that changes the map (`editor_add_input_action`)
// belongs to B3/B5 and is deliberately not here.
//
// Observable contract (as implemented):
//   * no parameters;
//   * answers `{"actions": [<String>, ...], "count": N}` - the migration source's
//     key set - where the list is the InputMap singleton's action names;
//   * the list is **sorted ascending**. `InputMap::get_actions()` returns a
//     `TypedArray<StringName>` built by iterating a `HashMap`
//     (`core/input/input_map.cpp:133-141`), so its order is not part of the
//     engine's contract and differs between runs and builds. PLAYBOOK section 6.8
//     requires the module's non-deterministic reference behaviour to be made
//     deterministic; a caller diffing two calls (or two processes) would
//     otherwise see spurious changes;
//   * an editor whose InputMap is empty answers `{"actions": [], "count": 0}` -
//     the engine always populates the `ui_*` built-ins, so this is the shape for
//     a hypothetical build without them rather than an error;
//   * there is no editor guard: unlike the write and playback tools, reading an
//     `InputMap` needs no `EditorInterface`, and the singleton exists in every
//     process. The tool's *scope* is what keeps it out of a game endpoint.
// ---------------------------------------------------------------------------
static Variant _tool_get_input_actions(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	(void)r_error;

	const TypedArray<StringName> raw = InputMap::get_singleton()->get_actions();
	Vector<String> names;
	names.resize(raw.size());
	for (int i = 0; i < raw.size(); i++) {
		names.write[i] = String(raw[i]);
	}
	// A plain insertion sort over an action list (tens of entries) instead of
	// `SortArray`: `SortArray::sort` reorders a `Vector<T>` in place with a
	// comparator, and this keeps the ordering rule visible where it matters.
	for (int i = 1; i < names.size(); i++) {
		const String value = names[i];
		int j = i - 1;
		while (j >= 0 && names[j] > value) {
			names.write[j + 1] = names[j];
			j--;
		}
		names.write[j + 1] = value;
	}

	Array actions;
	for (int i = 0; i < names.size(); i++) {
		actions.push_back(names[i]);
	}

	Dictionary result;
	result["actions"] = actions;
	result["count"] = actions.size();
	return result;
}

// ---------------------------------------------------------------------------
// Registration
//
// The declaration order follows docs/tool-groups-b2.json; channel, verb, scope
// and mutating come from docs/tool-rename-map.json and the description and
// `inputSchema` are a byte-exact copy of docs/tools_list.renamed.json, emitted
// by `scripts/gen_b2_game_schema.py` (re-running it reproduces this block).
// ---------------------------------------------------------------------------

void register_editor_input_read_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("editor_get_input_actions", String::utf8("列出所有 Input Action"));

		Dictionary schema;
		Dictionary v0;
		schema[String::utf8("properties")] = v0;
		Array v1;
		schema[String::utf8("required")] = v1;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("editor").verb("get").scope(MCPToolScope::EDITOR).mutating(false).schema(schema).handler(_tool_get_input_actions);
		builder.register_into(r_registry);
	}
	// END generated
}