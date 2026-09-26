/**************************************************************************/
/*  editor_node_property_updates.cpp                                      */
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
#include "editor_node_property_updates.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/object/object.h"
#include "core/string/ustring.h"
// The entry point takes a `Node *` (the root the batch is applied to), and every
// write hands it to `Object *`-taking helpers, so this translation unit needs
// the complete type: a derived-to-base pointer conversion is not available for a
// forward-declared class. The *header* keeps the forward declaration.
#include "scene/main/node.h"

// The two helpers this group borrows are the module's one property-write path:
//   * `read_node_property_path` / `apply_node_property_value` - the sub-property
//     aware read and the already-gated write the type-scoped batch also rolls
//     back with (`tools/running_game_node_write.h`);
//   * `write_node_property` - the whole write, including the TASK-022/TASK-023
//     `ValueSlot` narrowing gate, so this tool cannot be a back door around it.
#include "running_game_node_write.h"

using namespace MCPTools;

namespace {

// One entry of the request, after the shape pass. The `value` is kept as the raw
// JSON Variant: the whole point is that it goes through the same gate the
// single-node writer uses, not through a copy of the gate written here.
struct _Update {
	int index = 0;
	String path;
	String property;
	Variant value;
};

// The members an entry may carry. Anything else is refused rather than ignored
// (PLAYBOOK section 6.2: an argument a tool silently drops is how a caller ends
// up believing it configured something). The top-level gate in
// `tool_registry.cpp` cannot see inside an array element, so this is the one
// place that can.
const char *const UPDATE_MEMBERS[] = { "path", "property", "value" };

Variant _suggestion_data(const String &p_suggestion) {
	Dictionary data;
	data["suggestion"] = p_suggestion;
	return data;
}

// `updates[i].<member>` must be a non-empty string. The index is part of the
// name so the refusal can never be read as being about the wrong entry - the
// same rule `editor_add_nodes_batch` applies to `nodes[i].type`.
bool _require_entry_string(const Dictionary &p_entry, const String &p_member, int p_index, String &r_out,
		MCPToolError &r_error) {
	if (!p_entry.has(p_member)) {
		r_error = MCPToolError::invalid_params(vformat("Missing required parameter 'updates[%d].%s'",
				p_index, p_member));
		return false;
	}
	const Variant value = p_entry[p_member];
	if (value.get_type() != Variant::STRING && value.get_type() != Variant::STRING_NAME) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'updates[%d].%s' must be a string, got %s", p_index, p_member,
				Variant::get_type_name(value.get_type())));
		return false;
	}
	r_out = String(value);
	if (r_out.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'updates[%d].%s' must not be empty",
				p_index, p_member));
		return false;
	}
	return true;
}

String _suggestion_of(const MCPToolError &p_error) {
	if (p_error.data.get_type() != Variant::DICTIONARY) {
		return String();
	}
	return String(((Dictionary)p_error.data).get("suggestion", Variant()));
}

Dictionary _error_entry(int p_index, const String &p_path, const String &p_property, int p_code,
		const String &p_message, const String &p_suggestion) {
	Dictionary entry;
	entry["index"] = p_index;
	entry["path"] = p_path;
	entry["property"] = p_property;
	entry["status"] = "error";
	entry["changed"] = false;
	Dictionary error;
	error["code"] = (int64_t)p_code;
	error["message"] = p_message;
	entry["error"] = error;
	if (!p_suggestion.is_empty()) {
		entry["suggestion"] = p_suggestion;
	}
	return entry;
}

// The shape pass. Every element is validated before a single node is looked up,
// so a mistyped entry is a `-32602` naming its index and nothing is written -
// the same ordering `editor_add_nodes_batch` uses for `nodes[i]`.
bool _validate_updates(const Array &p_updates, Vector<_Update> &r_out, MCPToolError &r_error) {
	for (int i = 0; i < p_updates.size(); i++) {
		const Variant element = p_updates[i];
		if (element.get_type() != Variant::DICTIONARY) {
			r_error = MCPToolError::invalid_params(vformat(
					"Parameter 'updates[%d]' must be an object with 'path', 'property' and 'value', got %s",
					i, Variant::get_type_name(element.get_type())));
			return false;
		}
		const Dictionary entry = element;
		const Array keys = entry.keys();
		for (int k = 0; k < keys.size(); k++) {
			const String key = keys[k];
			bool known = false;
			for (int m = 0; m < 3; m++) {
				if (key == UPDATE_MEMBERS[m]) {
					known = true;
					break;
				}
			}
			if (!known) {
				r_error = MCPToolError::invalid_params(vformat(
						"Unknown parameter 'updates[%d].%s' for tool 'editor_set_node_property_updates'",
						i, key));
				r_error.data = _suggestion_data(vformat(
						"An entry of 'updates' accepts exactly: path, property, value; use "
						"editor_set_node_property for a single write"));
				return false;
			}
		}

		_Update update;
		update.index = i;

		MCPToolError path_error;
		if (!_require_entry_string(entry, "path", i, update.path, path_error)) {
			r_error = path_error;
			return false;
		}
		MCPToolError property_error;
		if (!_require_entry_string(entry, "property", i, update.property, property_error)) {
			r_error = property_error;
			return false;
		}
		// `value` accepts every JSON type (the contract declares `{}` for it), so
		// presence - not nullness - is what "required" means, exactly like the
		// single-node writer's `value`.
		if (!entry.has("value")) {
			r_error = MCPToolError::invalid_params(vformat("Missing required parameter 'updates[%d].value'", i));
			return false;
		}
		update.value = entry["value"];
		r_out.push_back(update);
	}
	return true;
}

} // namespace

namespace MCPTools {

bool validate_node_property_updates(const Array &p_updates, MCPToolError &r_error) {
	Vector<_Update> discarded;
	if (p_updates.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'updates' must name at least one update");
		return false;
	}
	return _validate_updates(p_updates, discarded, r_error);
}

Variant set_node_property_updates_on(Node *p_root, const Array &p_updates, bool p_stop_on_error,
		MCPToolError &r_error) {
	if (p_updates.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'updates' must name at least one update");
		return Variant();
	}

	Vector<_Update> updates;
	if (!_validate_updates(p_updates, updates, r_error)) {
		return Variant();
	}

	// What a `stop_on_error: true` call has to be able to put back, and what it
	// actually managed to put back. `_Applied` holds the *engine* value the path
	// had (not its serialized form: `apply_node_property_value` hands it straight
	// to `set_indexed`, and a Vector2 stored as a Dictionary would be refused by
	// the engine instead of restored).
	struct _Applied {
		int index = 0;
		String path;
		String property;
		Variant previous;
		bool restorable = false;
	};
	Vector<_Applied> applied;
	Vector<String> rollback_failures;
	Array results;
	int updated = 0;
	int failed = 0;
	bool stopped = false;
	// The index of the entry that stopped the call, so the ones behind it can be
	// named as `skipped` instead of being silently absent from `results`.
	int failed_index = -1;

	for (int i = 0; i < updates.size(); i++) {
		const _Update &update = updates[i];

		Node *node = find_node(p_root, update.path);
		if (node == nullptr) {
			// TASK-063 (b): the refusal points the way instead of only saying
			// "use editor_get_scene_tree" - the round-2 trace burned 20 single
			// writes and 39 batch calls on a path basis nobody had written down.
			const String suggestion = node_path_guidance("path", false);
			results.push_back(_error_entry(update.index, update.path, update.property,
					MCP_ERR_NOT_FOUND, vformat("Node '%s'", update.path), suggestion));
			failed++;
			if (p_stop_on_error) {
				stopped = true;
				failed_index = update.index;
				r_error = MCPToolError::not_found(vformat("updates[%d]: Node '%s'", update.index, update.path), suggestion);
				break;
			}
			continue;
		}

		// The take-back value is read *before* the write and only when the caller
		// asked for the all-or-nothing mode: the default mode never restores
		// anything, and reading a composite just to throw it away would be twice
		// the work for no answer.
		_Applied record;
		record.index = update.index;
		record.path = update.path;
		record.property = update.property;
		if (p_stop_on_error) {
			bool previous_valid = false;
			MCPToolError read_error;
			record.previous = read_node_property_path(node, update.property, previous_valid, read_error);
			record.restorable = previous_valid;
		}

		// The one write path. `write_node_property` is the module's single
		// property-write definition: declared type, component mapping, the
		// `ValueSlot` narrowing gate and the read-back all live inside it.
		MCPToolError write_error;
		const Variant written = write_node_property(node, update.property, update.value, write_error);
		if (written.get_type() == Variant::NIL) {
			const String suggestion = _suggestion_of(write_error);
			results.push_back(_error_entry(update.index, update.path, update.property,
					write_error.code, write_error.message, suggestion));
			failed++;
			if (p_stop_on_error) {
				stopped = true;
				failed_index = update.index;
				r_error = write_error;
				r_error.message = vformat("updates[%d]: %s", update.index, write_error.message);
				if (suggestion.is_empty()) {
					r_error.data = _suggestion_data(
							"Nothing was changed: stop_on_error is true, so the whole call is taken back. "
							"Fix the entry the message names, or pass stop_on_error: false to keep the entries that land");
				}
				break;
			}
			continue;
		}

		const Dictionary answer = written;
		Dictionary entry;
		entry["index"] = update.index;
		entry["path"] = update.path;
		entry["property"] = update.property;
		entry["node_path"] = answer.get("node_path", Variant());
		entry["old_value"] = answer.get("old_value", Variant());
		entry["new_value"] = answer.get("new_value", Variant());
		// "Did the value land" is a read-back question, and this is the read-back:
		// the values on both sides are what the engine answered after the write
		// (`write_node_property` reads them), never the request.
		entry["changed"] = Variant(entry["old_value"]) != Variant(entry["new_value"]);
		entry["status"] = "ok";
		// The engine's own setter may store something else than it was asked
		// (`ignored` is `write_node_property`'s per-property bag: `requested` /
		// `stored` / `reason`). It is carried per entry so a clamp is visible on
		// exactly the node it happened to.
		const Variant ignored_value = answer.get("ignored", Variant());
		entry["ignored"] = ignored_value;
		entry["stored_as_requested"] = ignored_value.get_type() == Variant::DICTIONARY
				? ((Dictionary)ignored_value).is_empty()
				: true;
		results.push_back(entry);
		updated++;
		if (p_stop_on_error) {
			applied.push_back(record);
		}
	}

	// The all-or-nothing half. Every entry that landed is put back, newest first,
	// so two entries on the same path restore in the reverse order they were
	// applied.
	if (p_stop_on_error && stopped) {
		for (int i = applied.size() - 1; i >= 0; i--) {
			const _Applied &record = applied[i];
			Node *node = find_node(p_root, record.path);
			if (node == nullptr || !record.restorable) {
				rollback_failures.push_back(vformat("updates[%d]: the previous value of '%s' could not be read before the write, so this entry could not be put back",
						record.index, record.property));
				continue;
			}
			MCPToolError rollback_error;
			if (!apply_node_property_value(node, record.property, record.previous, rollback_error)) {
				rollback_failures.push_back(vformat("updates[%d]: the engine refused to put '%s' back (%s)",
						record.index, record.property, rollback_error.message));
			}
		}
		// The entries the early exit never reached are named, not silently absent:
		// a caller reading `results` must not have to count to notice that the
		// list is short.
		for (int i = 0; i < updates.size(); i++) {
			if (updates[i].index <= failed_index) {
				continue;
			}
			Dictionary entry;
			entry["index"] = updates[i].index;
			entry["path"] = updates[i].path;
			entry["property"] = updates[i].property;
			entry["status"] = "skipped";
			entry["changed"] = false;
			entry["reason"] = "stop_on_error is true and an earlier entry failed, so this entry was not attempted";
			results.push_back(entry);
		}

		Array reverted;
		for (int i = 0; i < applied.size(); i++) {
			Dictionary item;
			item["index"] = applied[i].index;
			item["path"] = applied[i].path;
			item["property"] = applied[i].property;
			item["status"] = applied[i].restorable ? "reverted" : "not_restorable";
			reverted.push_back(item);
		}
		Array failures;
		for (int i = 0; i < rollback_failures.size(); i++) {
			failures.push_back(rollback_failures[i]);
		}

		Dictionary data;
		if (r_error.data.get_type() == Variant::DICTIONARY) {
			data = r_error.data;
		}
		data["stop_on_error"] = true;
		data["rolled_back"] = rollback_failures.is_empty();
		data["count"] = updates.size();
		data["updated"] = updated;
		data["failed"] = failed;
		data["applied"] = reverted;
		data["rollback_failures"] = failures;
		data["results"] = results;
		r_error.data = data;
		return Variant();
	}

	Dictionary result;
	result["status"] = failed == 0 ? "ok" : "partial";
	if (failed > 0) {
		// A partial answer must say so in the one field a caller reads first.
		result["message"] = vformat(
				"%d of %d update(s) landed; %d entry/entries were refused and are named in 'results' with their own error code",
				updated, updates.size(), failed);
	}
	result["count"] = updates.size();
	result["updated"] = updated;
	result["failed"] = failed;
	result["stop_on_error"] = p_stop_on_error;
	result["rolled_back"] = false;
	result["results"] = results;
	return result;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// editor_set_node_property_updates (added by TASK-063 section 3)
//
// The argument grammar is validated here (array-ness, non-emptiness, the type of
// `stop_on_error`) so a malformed call is a `-32602` even in a process without an
// edited scene; the per-entry work is `MCPTools::set_node_property_updates_on`.
//
// Wire shape of the success / partial answer:
//   * `status`  - `"ok"` when every entry landed, `"partial"` when some did not;
//   * `count` / `updated` / `failed`;
//   * `results` - one object per entry, in request order:
//       - landed: `{index,path,property,node_path,old_value,new_value,changed,
//                   ignored,stored_as_requested,status:"ok"}`;
//       - refused: `{index,path,property,status:"error",changed:false,
//                    error:{code,message},suggestion?}`.
//   * a whole-call refusal (`stop_on_error: true`) attaches the same `results`
//     array plus `rolled_back` / `applied` / `rollback_failures` to `error.data`.
//
// A `stop_on_error: true` call whose first entry fails is a refusal even when
// nothing had been applied yet: the caller asked for "nothing half-applied", and
// the honest answer is an error code rather than a payload with one error in it.
// ---------------------------------------------------------------------------
static Variant _tool_set_node_property_updates(const Dictionary &p_args, MCPToolError &r_error) {
	const Variant updates_value = p_args.get("updates", Variant());
	if (updates_value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter 'updates'");
		return Variant();
	}
	if (updates_value.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'updates' must be an array, got %s",
				Variant::get_type_name(updates_value.get_type())));
		return Variant();
	}
	const Array updates = updates_value;
	if (updates.is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'updates' must name at least one update");
		return Variant();
	}
	// The element grammar, before the guard: `updates[0]` being a number, or an
	// element that names no `path`, is the caller's mistake and must be reported
	// as one in *every* process - an editor guard that answered `-32000` first
	// would hide it (PLAYBOOK section 6.2).
	if (!validate_node_property_updates(updates, r_error)) {
		return Variant();
	}
	// The mode is read - and a present-but-wrong type refused - *before* the
	// editor guard, so a mistyped `stop_on_error` is a `-32602` in every process
	// rather than a `-32000` that hides it (PLAYBOOK section 6.2).
	bool stop_on_error = false;
	if (!optional_bool(p_args, "stop_on_error", false, stop_on_error, r_error)) {
		return Variant();
	}
	if (!require_editor_ui(r_error, "editor node writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return Variant();
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return Variant();
	}
	return set_node_property_updates_on(root, updates, stop_on_error, r_error);
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// `docs/tools_list.renamed.json` (generated from `ADDED_TOOLS`).
// ---------------------------------------------------------------------------

// The `inputSchema`, built as a C++ `Dictionary` instead of being parsed from the
// same JSON text the contract spells.
//
// Why: `JSON::parse` turns **every** JSON number into a FLOAT Variant
// (`core/io/json.cpp`), and `JSON::stringify` writes a float that happens to be
// integral as `1.0`. `updates.minItems` is the schema's one number, so a parsed
// form would put `"minItems":1.0` on the wire where the contract says `1`, and
// gate 1 compares the live `inputSchema` against the contract field by field.
// The same reasoning `project_build_csharp` records for its `minimum`/`maximum`
// applies here. Key order inside a JSON object is not part of the contract; the
// values are.
static Dictionary _updates_schema() {
	Dictionary item;
	Dictionary item_properties;
	Dictionary path;
	path["type"] = "string";
	item_properties["path"] = path;
	Dictionary property;
	property["type"] = "string";
	item_properties["property"] = property;
	// `value` accepts every JSON type: the contract declares an empty object for
	// it, and an empty object must stay an empty object (not "no type").
	item_properties["value"] = Dictionary();
	item["properties"] = item_properties;
	Array item_required;
	item_required.push_back("path");
	item_required.push_back("property");
	item_required.push_back("value");
	item["required"] = item_required;
	item["type"] = "object";

	Dictionary updates;
	updates["items"] = item;
	updates["minItems"] = (int64_t)1;
	updates["type"] = "array";

	Dictionary stop_on_error;
	stop_on_error["default"] = false;
	stop_on_error["type"] = "boolean";

	Dictionary properties;
	properties["updates"] = updates;
	properties["stop_on_error"] = stop_on_error;

	Array required;
	required.push_back("updates");

	Dictionary schema;
	schema["properties"] = properties;
	schema["required"] = required;
	schema["type"] = "object";
	return schema;
}

void register_editor_node_property_updates_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_set_node_property_updates",
				String::utf8(R"desc(Set a different value on each of many nodes in the edited scene in one call, and answer per entry whether the value landed.)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_updates_schema());
		builder.handler(_tool_set_node_property_updates).register_into(r_registry);
	}
}
