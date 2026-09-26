/**************************************************************************/
/*  project_validate_scripts.cpp                                          */
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
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/
#include "project_validate_scripts.h"

#include "project_read_files.h"
#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/variant/dictionary.h"

using namespace MCPTools;

namespace {

// TASK-053 section 2.1: what an omitted `paths` discovers.
//
// The two extensions the module's own script tools write and read
// (`project_create_script` / `project_edit_script` accept exactly `.gd` and
// `.cs`), and the set is **fixed** rather than derived from
// `ScriptServer::get_language(i)->get_recognized_extensions()`. The derived set
// would have a dishonest property: in a `module_mono_enabled=no` build the C#
// language is absent, so every `.cs` file would silently disappear from the scan
// instead of being reported as `language_unavailable` - the scan would agree
// with the build's limitations instead of telling the caller about them.
//
// `.gdshader` is deliberately **not** part of the walk (it is the shader family,
// written by the shader tools, and the engine has no `ScriptLanguage` for it);
// a `paths` argument that names one still answers `language_unavailable`, which
// is the honest per-file verdict.
const char *const SCRIPT_EXTENSIONS[] = { "gd", "cs" };

const int MAX_VALIDATED_SCRIPTS = 64;

// 400 bytes is far more than any `ERR_*` identifier or engine sentence this
// answer can carry, so the cut never fires on the messages the tools of this
// module produce - which is exactly why it has to exist: the guarantee must not
// depend on that continuing to be true.
const int MAX_TEXT_BYTES = 400;

// TASK-054 (D-053-3): the `unverifiable` item's `reason` is a *citation*, not a
// sentence: it has to name the engine file and line the "no verdict is possible"
// claim rests on (`CSharpScript::reload()`'s unconditional `return OK`, the
// private `valid` field, the bridge lookup), or the classification would be
// unsourced. 800 bytes is the smallest round bound that holds the citation
// whole; it is a separate constant so the 400-byte rule for messages does not
// silently cut the evidence in half.
const int MAX_REASON_BYTES = 800;

bool _is_script_extension(const String &p_extension) {
	for (const char *extension : SCRIPT_EXTENSIONS) {
		if (p_extension == String(extension)) {
			return true;
		}
	}
	return false;
}


Array _discover_scripts() {
	Vector<String> extensions;
	for (const char *extension : SCRIPT_EXTENSIONS) {
		extensions.push_back(String(extension));
	}
	Vector<String> found;
	// `addons` is descended into: an addon's scripts are scripts of this project,
	// and a batch that silently skipped them would be the "static answer" GDR-25
	// rules out. Hidden entries are skipped by the walk itself (`.godot` and
	// `.import` are caches, not sources).
	collect_files_by_extension("res://", extensions, true, found);
	// Deterministic order: the directory order of a filesystem is not a promise,
	// and two runs over the same tree must answer the same array.
	found.sort();

	Array out;
	for (int i = 0; i < found.size(); i++) {
		// `collect_files_by_extension` matches extensions case insensitively;
		// the per-file verdict is made from the extension as `file_extension()`
		// spells it, so a `UPPER.GD` is *discovered* here and then honestly
		// answers `language_unavailable` (this build has no language for "GD").
		if (!_is_script_extension(file_extension(found[i]))) {
			continue;
		}
		out.push_back(found[i]);
	}
	return out;
}

// The engine's `Array of string` rule for this file: every element has to be a
// non-empty string, and the refusal names the index. Deliberately not shared
// with the game-side `_require_string_array` of
// `running_game_frame_observation.cpp` (which allows an empty array, because
// there "no property" is a legal request); here an empty list would be a call
// that can answer nothing.
bool _require_path_string(const Dictionary &p_args, Array &r_out, MCPToolError &r_error) {
	const Variant raw = p_args.get("paths", Variant());
	if (raw.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(
				"Parameter 'paths' must be an array of strings, got " + Variant::get_type_name(raw.get_type()));
		return false;
	}
	const Array values = raw;
	for (int i = 0; i < values.size(); i++) {
		const Variant element = values[i];
		if (element.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'paths[%d]' must be a string, got %s",
					i, Variant::get_type_name(element.get_type())));
			return false;
		}
		if (((String)element).strip_edges().is_empty()) {
			r_error = MCPToolError::invalid_params(vformat("Parameter 'paths[%d]' must not be empty", i));
			return false;
		}
	}
	r_out = values;
	return true;
}

Dictionary _item(const String &p_path, const MCPValidateScriptVerdict &p_verdict) {
	Dictionary entry;
	entry["path"] = p_path;
	// The extension the verdict was made with, exactly as the language lookup
	// spells it (case preserved - `scripts/upper.GD` has no language in this
	// build, and saying "gd" would hide why).
	entry["language"] = p_verdict.language;
	entry["category"] = p_verdict.category;
	if (p_verdict.category == "unverifiable" || p_verdict.category == "not_compiled") {
		// TASK-054/TASK-055: a file this process cannot judge (`unverifiable`) or
		// whose source no build has compiled (`not_compiled`). The `valid` key is
		// published as `null`, not `false` - `false` is the verdict "it does not
		// compile", which is exactly what nobody can say here (the same reason the
		// singular tool refuses instead of answering).
		entry["valid"] = Variant();
		entry["reason"] = truncate_marked(p_verdict.reason, MAX_REASON_BYTES);
		entry["message"] = truncate_marked(p_verdict.message, MAX_TEXT_BYTES);
		const MCPToolError refusal = validate_script_verdict_refusal(p_path, p_verdict);
		if (refusal.data.get_type() == Variant::DICTIONARY) {
			entry["suggestion"] = ((Dictionary)refusal.data).get("suggestion", Variant());
		}
		return entry;
	}
	entry["valid"] = p_verdict.valid;
	if (!p_verdict.error_text.is_empty()) {
		entry["error_text"] = truncate_marked(p_verdict.error_text, MAX_TEXT_BYTES);
	}
	entry["message"] = truncate_marked(p_verdict.message, MAX_TEXT_BYTES);
	if (p_verdict.category == "language_unavailable") {
		// The missing half of "this build cannot answer this file": what to do
		// instead. The single-file tool carries the same sentence in
		// `data.suggestion`, and a batch item that only said "unavailable" would
		// send the caller to the tool's description to find it.
		const MCPToolError refusal = validate_script_language_unavailable_error(p_path, p_verdict.language);
		if (refusal.data.get_type() == Variant::DICTIONARY) {
			entry["suggestion"] = ((Dictionary)refusal.data).get("suggestion", Variant());
		}
	}
	return entry;
}

} // namespace

namespace MCPTools {

int max_validated_scripts() {
	return MAX_VALIDATED_SCRIPTS;
}

Dictionary validation_limits() {
	Dictionary limits;
	limits["max_scripts"] = MAX_VALIDATED_SCRIPTS;
	return limits;
}

String truncate_marked(const String &p_text, int p_max_bytes) {
	const CharString utf8 = p_text.utf8();
	if (utf8.length() <= p_max_bytes) {
		return p_text;
	}
	// Cut on a character boundary: a byte is a UTF-8 continuation byte when its
	// top two bits are `10`, and a cut must not land in the middle of a
	// character (`String::utf8(bytes, len)` validates what it is given). A byte
	// based cut is what every other length in this module is measured in
	// (PLAYBOOK section 6 item 9).
	int cut = p_max_bytes;
	const char *bytes = utf8.get_data();
	while (cut > 0 && (((uint8_t)bytes[cut]) & 0xC0) == 0x80) {
		cut--;
	}
	return String::utf8(bytes, cut) + vformat("...(truncated, %d bytes total)", (int64_t)utf8.length());
}

bool validate_scripts(const Array &p_paths, bool p_paths_given, bool p_include_errors_only,
		Dictionary &r_out, MCPToolError &r_error) {
	Array candidates;

	if (p_paths_given) {
		if (p_paths.is_empty()) {
			r_error = MCPToolError::invalid_params(
					"Parameter 'paths' must name at least one script when it is present");
			return false;
		}
		for (int i = 0; i < p_paths.size(); i++) {
			const String given = p_paths[i];
			const String prefix = vformat("Parameter 'paths[%d]'", i);
			String normalized;
			if (!normalize_project_path(given, normalized, r_error)) {
				// The suggestion is added here because only this tool knows what
				// it is asking for; the registry keeps it (it only adds one when
				// `data` carries none).
				Dictionary data;
				data["suggestion"] = vformat(
						"%s must address the project ('res://...') and must not contain a '..' segment: this tool validates project scripts only", prefix);
				r_error.data = data;
				return false;
			}
			// Request-shape refusals run before any file is read, so a mistyped
			// batch never answers a partial verdict set.
			if (!FileAccess::exists(normalized)) {
				r_error = MCPToolError::not_found(
						vformat("Script '%s' (%s)", normalized, prefix),
						"Use project_list_scripts to list the scripts of the project, or project_create_script to create the file");
				return false;
			}
			candidates.push_back(normalized);
		}
	} else {
		candidates = _discover_scripts();
	}

	Array verdicts;
	const int total_candidates = candidates.size();
	int dropped = 0;
	for (int i = 0; i < total_candidates; i++) {
		if (verdicts.size() >= MAX_VALIDATED_SCRIPTS) {
			dropped++;
			continue;
		}
		const String path = candidates[i];
		String source;
		if (!read_project_text_file(path, source, r_error)) {
			return false;
		}
		verdicts.push_back(_item(path, validate_script_source(path, source)));
	}

	Array results;
	int valid_count = 0;
	int invalid_count = 0;
	int unavailable_count = 0;
	int unverifiable_count = 0;
	int not_compiled_count = 0;
	for (int i = 0; i < verdicts.size(); i++) {
		const Dictionary entry = verdicts[i];
		const String category = entry["category"];
		if (category == "ok") {
			valid_count++;
		} else if (category == "invalid") {
			invalid_count++;
		} else if (category == "unverifiable") {
			unverifiable_count++;
		} else if (category == "not_compiled") {
			not_compiled_count++;
		} else {
			unavailable_count++;
		}
		if (p_include_errors_only && category == "ok") {
			continue;
		}
		results.push_back(entry);
	}

	Dictionary out;
	out["results"] = results;
	out["count"] = verdicts.size();
	out["valid_count"] = valid_count;
	out["invalid_count"] = invalid_count;
	out["unavailable_count"] = unavailable_count;
	// TASK-054 (D-053-3): the residual counter (the engine could not be asked).
	// TASK-055 added the fifth one: `count` stays the sum of the five, so no file
	// the caller asked about can disappear from the classification.
	out["unverifiable_count"] = unverifiable_count;
	out["not_compiled_count"] = not_compiled_count;
	// Echoed, so a filtered answer cannot be mistaken for the whole set - and
	// `returned` makes the difference readable without recomputing anything.
	out["errors_only"] = p_include_errors_only;
	out["returned"] = results.size();
	// The three-key truncation marker of the bulk readers.
	out["truncated"] = dropped > 0;
	out["dropped"] = dropped;
	out["limits"] = validation_limits();
	r_out = out;
	return true;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// The tool
// ---------------------------------------------------------------------------

static Variant _tool_validate_scripts(const Dictionary &p_args, MCPToolError &r_error) {
	Array paths;
	const bool paths_given = p_args.has("paths");
	if (paths_given) {
		if (!_require_path_string(p_args, paths, r_error)) {
			return Variant();
		}
	}
	bool include_errors_only = false;
	if (!optional_bool(p_args, "include_errors_only", false, include_errors_only, r_error)) {
		return Variant();
	}
	Dictionary out;
	if (!MCPTools::validate_scripts(paths, paths_given, include_errors_only, out, r_error)) {
		return Variant();
	}
	return out;
}

// ---------------------------------------------------------------------------
// Registration
//
// The authoritative `description` and `inputSchema` are the contract entry of
// `docs/tools_list.renamed.json`, character for character - and that entry is
// generated from `ADDED_TOOLS` in `scripts/gen_renamed_contract.py` (GDR-28
// point 1: an added entry is authored by the decision maker, never by this
// file).
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_validate_scripts.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_validate_scripts_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_validate_scripts",
				String::utf8(R"desc(Validate every script of the project in one call and answer a per-file verdict, so a batch of edited scripts can be checked without one call per file. The categories are `ok` (the file's own language compiled it), `invalid` (it did not compile - for a `.cs` file that is a project-level build of its .csproj that project_build_csharp ran and recorded, and the item carries the compiler's own diagnostic text), `not_compiled` (no build of this source is loaded: the file was modified after the loaded .NET assembly was built, or that assembly has no class for the script's path - deliberately not `invalid`, because the engine has no C# compiler and CSharpScript::reload() returns OK unconditionally), `language_unavailable` (this build has no script backend for the extension) and `unverifiable` (the engine could not load the file as a Script resource); `valid` is published only for `ok` and `invalid`, and `count` is always the sum of the per-category counters.)desc"));
		builder.channel("project").verb("validate").scope(MCPToolScope::BOTH).mutating(false);
		builder.schema(_schema_from_json(R"schema({"properties":{"include_errors_only":{"default":false,"type":"boolean"},"paths":{"items":{"type":"string"},"type":"array"}},"required":[],"type":"object"})schema"));
		builder.handler(_tool_validate_scripts).register_into(r_registry);
	}
}
