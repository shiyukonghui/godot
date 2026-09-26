/**************************************************************************/
/*  project_autoload_write.cpp                                            */
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
#include "project_autoload_write.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/config/project_settings.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// The autoload key grammar, and the one thing the migration source got right.
//
// `project_autoload_write` is the one-key pair of `project.godot`: the settings
// key `autoload/<name>` whose value is the *SingletonMarker* string
// `"*" + path` (`"*res://player.gd"` means "register as a singleton"; without
// the `*` Godot loads the scene/script as a plain node). The migration source
// wrote exactly that (project_commands.gd:357-358) and the engine's own
// `ProjectSettings::_get_property_list()` exposes the key the same way, so the
// grammar is kept.
//
// What changes is the write itself and the honesty of the answer:
//   * the migration called `ProjectSettings.save()` - a plain write into
//     `project.godot` - and answered `{"added": true}` whenever the engine's
//     `save()` returned OK. This group publishes through
//     `MCPTools::publish_project_settings()` and *restores* the previous
//     in-memory value when the publish fails, so a failed call cannot leave the
//     project half-configured (`project.godot` keeps its old bytes on disk and
//     the in-memory state matches that file again);
//   * the "already there" case is an explicit success with
//     `already_present: true` instead of the migration's `-32000`
//     (project_commands.gd:351-355), and the "there with another path" case
//     keeps the refusal - the two cases are different and a caller can act on
//     both;
//   * the answer reads the value *back* out of `ProjectSettings` after the
//     publish, so `setting_value` is what the project really holds.
// ---------------------------------------------------------------------------

namespace MCPTools {

// True when `p_name` is a usable autoload name. It has to be a single setting
// key segment: a `/` or a `:` would create a *section* or address another
// setting, and a name that is not a valid identifier (spaces, `=`, quotes) would
// produce a `project.godot` the engine reads back differently from what the
// caller wrote. The migration source did not check this at all.
static bool _validate_autoload_name(const String &p_name, MCPToolError &r_error) {
	if (p_name.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'name' must not be empty");
		return false;
	}
	if (!p_name.is_valid_identifier()) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'name' must be a valid identifier (no '/', ':', spaces, '=' or quotes), got '%s'", p_name));
		return false;
	}
	return true;
}

// The `autoload/<name>` settings key.
static String _autoload_key(const String &p_name) {
	return "autoload/" + p_name;
}

bool add_autoload(const String &p_name, const String &p_path, Dictionary &r_out, MCPToolError &r_error, const String &p_target_path) {
	if (!_validate_autoload_name(p_name, r_error)) {
		return false;
	}
	String path;
	if (!normalize_project_path(p_path, path, r_error)) {
		return false;
	}
	if (path == "res://") {
		r_error = MCPToolError::invalid_params(vformat("Parameter 'path' must name a file, got '%s'", p_path));
		return false;
	}
	// The migration source's guard (project_commands.gd:346-347) kept as a
	// `-32001`: registering an autoload whose file is not there would produce a
	// project.godot the engine refuses to load at startup.
	if (!FileAccess::exists(path)) {
		r_error = MCPToolError::not_found(vformat("File '%s'", path),
				"Create the script or scene first (project_create_script / project_create_scene_file), then register it");
		return false;
	}

	ProjectSettings *settings = ProjectSettings::get_singleton();
	const String key = _autoload_key(p_name);
	const String declared = "*" + path;
	const bool existed = settings->has_setting(key);
	if (existed) {
		const String current = String(settings->get_setting(key));
		if (current == declared) {
			// The requested end state already holds. It is a success - and the
			// caller is told this call is not what established it.
			Dictionary out;
			out["name"] = p_name;
			out["path"] = path;
			out["key"] = key;
			out["setting_value"] = current;
			out["added"] = true;
			out["already_present"] = true;
			r_out = out;
			return true;
		}
		MCPToolError error = MCPToolError::tool_state(
				vformat("Autoload '%s' already exists with a different path", p_name),
				"Call project_remove_autoload first to replace it deliberately; this tool never silently overwrites the "
				"path an autoload already declares");
		Dictionary data = error.data;
		data["current_value"] = current;
		data["requested_value"] = declared;
		error.data = data;
		r_error = error;
		return false;
	}

	// TASK-059: the read-back of the old value was dead (`(void)previous` on every
	// path) and `ProjectSettings::get_setting()` prints "Request for nonexistent
	// project setting" when the key is absent - which is exactly this branch. It
	// was the only reason a first `project_add_autoload` logged an engine ERROR.
	settings->set_setting(key, declared);
	const String target = p_target_path.is_empty() ? project_settings_file_path() : p_target_path;
	if (!publish_project_setting_to(target, key, nullptr, r_error)) {
		// Put the in-memory state back to what the file on disk still holds, so
		// a failed call leaves no trace behind in either place.
		settings->clear(key);
		return false;
	}

	Dictionary out;
	out["name"] = p_name;
	out["path"] = path;
	out["key"] = key;
	out["setting_value"] = String(settings->get_setting(key));
	out["added"] = true;
	r_out = out;
	return true;
}

bool remove_autoload(const String &p_name, Dictionary &r_out, MCPToolError &r_error, const String &p_target_path) {
	if (!_validate_autoload_name(p_name, r_error)) {
		return false;
	}
	ProjectSettings *settings = ProjectSettings::get_singleton();
	const String key = _autoload_key(p_name);
	if (!settings->has_setting(key)) {
		r_error = MCPToolError::not_found(vformat("Autoload '%s'", p_name),
				"Use project_get_settings with prefix 'autoload/' to list the autoloads this project declares");
		return false;
	}
	const String old_value = String(settings->get_setting(key));
	settings->clear(key);
	// TASK-059 D-4: a removal stays on the whole-file writer on purpose -
	// `update_settings_section_text()` cannot delete a key
	// (`core/config/project_settings.h:226-227`). The tool's description states
	// that, and its contract text was rewritten in the same batch.
	const String target = p_target_path.is_empty() ? project_settings_file_path() : p_target_path;
	if (!publish_project_settings_to(target, r_error)) {
		settings->set_setting(key, old_value);
		return false;
	}

	Dictionary out;
	out["name"] = p_name;
	out["key"] = key;
	out["old_path"] = old_value;
	out["removed"] = true;
	r_out = out;
	return true;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// Tool wrappers
// ---------------------------------------------------------------------------

static Variant _tool_add_autoload(const Dictionary &p_args, MCPToolError &r_error) {
	String name;
	if (!require_string(p_args, "name", name, r_error)) {
		return Variant();
	}
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	Dictionary out;
	if (!add_autoload(name, path, out, r_error)) {
		return Variant();
	}
	return out;
}

static Variant _tool_remove_autoload(const Dictionary &p_args, MCPToolError &r_error) {
	String name;
	if (!require_string(p_args, "name", name, r_error)) {
		return Variant();
	}
	Dictionary out;
	if (!remove_autoload(name, out, r_error)) {
		return Variant();
	}
	return out;
}

// ---------------------------------------------------------------------------
// Registration
//
// The `description` and `inputSchema` below are the contract entries of
// docs/tools_list.renamed.json, character for character; `channel`/`verb`/
// `scope`/`mutating` come from docs/tool-rename-map.json.
// ---------------------------------------------------------------------------

static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in project_autoload_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_project_autoload_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("project_add_autoload", String::utf8(R"desc(注册自动加载 When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them.)desc"));
		builder.channel("project").verb("add").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"name":{"type":"string"},"path":{"type":"string"}},"required":["name","path"],"type":"object"})schema"));
		builder.handler(_tool_add_autoload).register_into(r_registry);
	}

	{
		ToolBuilder builder("project_remove_autoload", String::utf8(R"desc(移除自动加载 When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them.)desc"));
		builder.channel("project").verb("remove").scope(MCPToolScope::BOTH).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"name":{"type":"string"}},"required":["name"],"type":"object"})schema"));
		builder.handler(_tool_remove_autoload).register_into(r_registry);
	}
}
