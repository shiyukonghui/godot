/**************************************************************************/
/*  project_read_files.cpp                                                */
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
#include "project_read_files.h"

#include "csharp_verdict.h"
#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/crypto/crypto_core.h"
#include "core/error/error_list.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/image.h"
#include "core/io/resource_loader.h"
#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/object/script_language.h"
#include "core/variant/variant.h"
#include "scene/resources/texture.h"

#include "modules/modules_enabled.gen.h" // IWYU pragma: keep. For mono.

#ifdef MODULE_MONO_ENABLED
// TASK-055 (D112): the C# compile verdict reads the engine accessor this task
// added (`CSharpScript::is_source_newer_than_assembly()`); including the mono
// header is what makes the signal reachable from this module and only in a build
// that actually contains it (the `MODULE_MONO_ENABLED` branch below).
#include "modules/mono/csharp_script.h"
#endif

using namespace MCPTools;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

// The reference formats engine errors with Rust's `{:?}`, which prints the
// enum variant name (`ERR_PARSE_ERROR`). This fork only exposes a prose table
// (`error_names[]` -> "Parse error"), so the identifiers a script compiler or
// an image decoder actually returns are spelled out here; anything else falls
// back to the engine's own description rather than inventing an identifier.
static String _error_identifier(Error p_error) {
	switch (p_error) {
		case ERR_COMPILATION_FAILED:
			return "ERR_COMPILATION_FAILED";
		case ERR_PARSE_ERROR:
			return "ERR_PARSE_ERROR";
		case ERR_INVALID_DECLARATION:
			return "ERR_INVALID_DECLARATION";
		case ERR_DUPLICATE_SYMBOL:
			return "ERR_DUPLICATE_SYMBOL";
		case ERR_SCRIPT_FAILED:
			return "ERR_SCRIPT_FAILED";
		case ERR_CYCLIC_LINK:
			return "ERR_CYCLIC_LINK";
		case ERR_FILE_NOT_FOUND:
			return "ERR_FILE_NOT_FOUND";
		case ERR_FILE_CANT_OPEN:
			return "ERR_FILE_CANT_OPEN";
		case ERR_FILE_CANT_READ:
			return "ERR_FILE_CANT_READ";
		case ERR_FILE_UNRECOGNIZED:
			return "ERR_FILE_UNRECOGNIZED";
		case ERR_FILE_CORRUPT:
			return "ERR_FILE_CORRUPT";
		case ERR_CANT_OPEN:
			return "ERR_CANT_OPEN";
		case ERR_UNAVAILABLE:
			return "ERR_UNAVAILABLE";
		default: {
			const int index = (int)p_error;
			if (index >= 0 && index < ERR_MAX) {
				return String(error_names[index]);
			}
			return vformat("Error %d", index);
		}
	}
}

// project_read_script and project_read_scene_file_content have the same result
// shape ({path, content, size}); only the "not found" wording differs, which the
// caller supplies. The text itself comes from `read_project_text_file`, i.e. it
// is `FileAccess::get_as_text()` - the same call the reference makes.
static Variant _read_text_payload(const Dictionary &p_args, const String &p_not_found_what, const String &p_suggestion, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	String normalized;
	if (!normalize_project_path(path, normalized, r_error)) {
		return Variant();
	}
	if (!FileAccess::exists(normalized)) {
		r_error = MCPToolError::not_found(vformat("%s '%s'", p_not_found_what, normalized), p_suggestion);
		return Variant();
	}
	String content;
	if (!read_project_text_file(normalized, content, r_error)) {
		return Variant();
	}

	Dictionary result;
	result["path"] = normalized;
	result["content"] = content;
	// UTF-8 *bytes*, not `String::length()` characters: the reference reports
	// `String::len()` of the Rust string, which is a byte count, and the contract
	// says nothing about characters (PLAYBOOK section 6, item 9). TASK-006
	// section 3.1 fixed this - the character count it used to return was an
	// unnecessary deviation (REPORT-005, ACCEPTANCE-005 section B/6).
	const CharString content_utf8 = content.utf8();
	result["size"] = content_utf8.length();
	return result;
}

// ---------------------------------------------------------------------------
// project_list_scripts (old `list_scripts`)
//
// script.rs:68. A recursive walk from `res://` - the tool takes no argument -
// that collects the project's script files.
//
// Which extensions those are is NOT a constant of this tool: it is a property of
// the build, and the engine already publishes it. `ScriptServer` holds every
// registered `ScriptLanguage` (`core/object/script_language.cpp:239`
// `register_language()`, `:221` `get_language()`, `:227`
// `get_language_for_extension()`), and each language names exactly one extension
// (`ScriptLanguage::get_extension()`, `core/object/script_language.h:224`):
// GDScript registers "gd" and the .NET module registers "cs", the latter only
// when that module is compiled in (`modules/mono/register_types.cpp:57` ->
// `modules/mono/csharp_script.cpp:98`). Asking `ScriptServer` is also the honest
// answer for a build that has no C# at all: it must not claim a language it does
// not contain.
//
// TASK-067 (REPORT-066 F-066-1): this walk used to test the literal `.gd` /
// `.gdshader`, so on a Mono project with five readable `.cs` files on disk the
// tool answered `{"count":0,"scripts":[]}` - while four of the module's own error
// messages told the caller to use it to find scripts
// (`editor_script_write.cpp:271`, `editor_set_node_script_batch.cpp:219/:237`,
// `project_script_write.cpp:234`, `project_validate_scripts.cpp:246`).
//
// The walk itself is unchanged, including its deliberate quirk: only `.` and
// `..` are skipped, so `.godot`, `.import` and any other hidden entry *is*
// descended into, and `addons` is not special here. That is deliberately not the
// same walk as project_get_statistics' (which skips every `.`-prefixed entry and
// leaves `addons` alone by default). One measured consequence of extending the
// set rather than constraining the walk: a real Mono project also has generated
// `.cs` files under `res://.godot/mono/temp/obj/...`, and they are listed too.
// Narrowing the walk is a separate decision; this batch does not take it, and
// REPORT-067 section 1 records the files it would concern.
//
// Two more deliberate properties:
//   * `.gdshader` is in the set although no `ScriptLanguage` registers it - a
//     shader is a `Shader` (`ResourceFormatLoaderShader`), not a script. It is
//     listed because the reference lists it and because it is the other text
//     file this question is asked about.
//   * the comparison stays case sensitive, exactly like the reference's
//     `ends_with(".gd")`: `upper.GD` is not a script.
//
// The order is the language registration order, which is fixed for a given
// build, so two calls in one process answer the same set.
// ---------------------------------------------------------------------------

static Vector<String> _script_extensions() {
	Vector<String> extensions;
	const int language_count = ScriptServer::get_language_count();
	for (int i = 0; i < language_count; i++) {
		const ScriptLanguage *language = ScriptServer::get_language(i);
		if (language == nullptr) {
			continue;
		}
		const String extension = language->get_extension();
		if (!extension.is_empty()) {
			extensions.push_back("." + extension);
		}
	}
	extensions.push_back(".gdshader");
	return extensions;
}

static bool _has_script_extension(const String &p_entry, const Vector<String> &p_extensions) {
	for (int i = 0; i < p_extensions.size(); i++) {
		if (p_entry.ends_with(p_extensions[i])) {
			return true;
		}
	}
	return false;
}

static void _collect_scripts_recursive(const String &p_path, const Vector<String> &p_extensions, Vector<String> &r_out) {
	Ref<DirAccess> dir = DirAccess::open(p_path);
	if (dir.is_null()) {
		// An unreadable directory is skipped silently, exactly like the
		// reference: this tool has no error of its own, not even for `res://`.
		return;
	}
	dir->list_dir_begin();
	while (true) {
		const String entry = dir->get_next();
		if (entry.is_empty()) {
			break;
		}
		if (entry == "." || entry == "..") {
			continue;
		}
		const String full = join_path(p_path, entry);
		if (dir->current_is_dir()) {
			_collect_scripts_recursive(full, p_extensions, r_out);
		} else if (_has_script_extension(entry, p_extensions)) {
			r_out.push_back(full);
		}
	}
	dir->list_dir_end();
}

static Variant _tool_list_scripts(const Dictionary &p_args, MCPToolError &r_error) {
	(void)p_args;
	(void)r_error;

	Vector<String> scripts;
	_collect_scripts_recursive("res://", _script_extensions(), scripts);

	Array out;
	for (int i = 0; i < scripts.size(); i++) {
		out.push_back(scripts[i]);
	}

	// `scripts` is an array of path *strings*, not of objects: that is the
	// reference's shape, and callers that expect {path,type} objects use
	// project_get_filesystem_tree instead.
	Dictionary result;
	result["scripts"] = out;
	result["count"] = out.size();
	return result;
}

// ---------------------------------------------------------------------------
// project_read_script (old `read_script`)
//
// script.rs:73. The file text verbatim: no line numbers, no truncation, no
// case folding of the path. `size` is the UTF-8 byte count (Rust's
// `String::len()`), fixed in TASK-006 section 3.1.
// ---------------------------------------------------------------------------

static Variant _tool_read_script(const Dictionary &p_args, MCPToolError &r_error) {
	return _read_text_payload(p_args, "File",
			"Use project_get_filesystem_tree to list the files of the project", r_error);
}

// ---------------------------------------------------------------------------
// project_validate_script (old `validate_script`)
//
// script.rs:158. The reference creates a GDScript, assigns the source and calls
// `reload()`. That is only meaningful once a script language has been
// *initialised*: `ScriptServer::register_language()` runs during module
// initialisation in every process, but `init_languages()` does not call
// `init()` in the test process - so `get_language_count() > 0` is the wrong
// test (measured: count is 1 in the doctest process while
// `are_languages_initialized()` is false). With an uninitialised language the
// compiler cannot even resolve a native base class and reports *every* script as
// ERR_COMPILATION_FAILED (measured: a valid `extends Node` script returns 36
// while the broken one returns 43), i.e. the honest answer for a valid file
// would be a false "invalid". Compilation is therefore attempted only when the
// languages are ready; otherwise the structural fallback below runs and its
// message says so explicitly.
//
// TASK-050 N-2 (the racing-backlog audit's honesty gap, reproduced on 9888 at
// the pre-change revision): this tool used to fall back to GDScript whenever the
// file's own extension had no language, so a legitimate `.cs` in a
// `module_mono_enabled=no` build answered
//   {"error_text":"ERR_PARSE_ERROR","message":"Compilation failed. Check the
//    script for errors.","path":"res://scripts/legit.cs","valid":false}
// - the GDScript parser's verdict about a C# file, published as a C# verdict.
// The fallback is gone. Only the file's own language is ever asked, and a build
// that does not contain it refuses with `-32000` + `data.suggestion` instead
// (the classification and the refusal live in the `MCPTools` namespace below and
// in `project_read_files.h`). The `valid` field is therefore always a real
// verdict of the file's own language: `true` compiled, `false` did not compile.
// ---------------------------------------------------------------------------

// A coarse bracket-balance check over `#` comments and quoted strings. It is
// deliberately not a parser: its only job is to avoid answering "valid" for a
// file whose delimiters cannot close, and its result is never described as
// "the syntax is correct".
static bool _structurally_balanced(const String &p_source) {
	int round = 0;
	int square = 0;
	int curly = 0;
	bool in_single = false;
	bool in_double = false;
	bool in_comment = false;
	for (int i = 0; i < p_source.length(); i++) {
		const char32_t c = p_source[i];
		if (c == '\n') {
			in_comment = false;
			continue;
		}
		if (in_comment) {
			continue;
		}
		if (c == '#' && !in_single && !in_double) {
			in_comment = true;
			continue;
		}
		if (c == '"' && !in_single) {
			in_double = !in_double;
			continue;
		}
		if (c == '\'' && !in_double) {
			in_single = !in_single;
			continue;
		}
		if (in_single || in_double) {
			continue;
		}
		if (c == '(') {
			round++;
		} else if (c == ')') {
			round--;
		} else if (c == '[') {
			square++;
		} else if (c == ']') {
			square--;
		} else if (c == '{') {
			curly++;
		} else if (c == '}') {
			curly--;
		}
		if (round < 0 || square < 0 || curly < 0) {
			return false;
		}
	}
	return round == 0 && square == 0 && curly == 0;
}

namespace MCPTools {

MCPValidateScriptMode classify_validate_script_mode(bool p_languages_initialized, bool p_language_found) {
	if (!p_languages_initialized) {
		// No script language server in this process at all: the documented
		// structural fallback, which says in its own message that nothing was
		// compiled.
		return MCPValidateScriptMode::STRUCTURAL;
	}
	return p_language_found ? MCPValidateScriptMode::COMPILE : MCPValidateScriptMode::LANGUAGE_UNAVAILABLE;
}

MCPToolError validate_script_language_unavailable_error(const String &p_path, const String &p_extension) {
	const String spelled = p_extension.is_empty() ? String("this file type") : ("'." + p_extension + "'");
	const String message = vformat(
			"Cannot validate '%s': this build has no script backend for %s, so the file was not parsed or compiled",
			p_path, spelled);
	const String suggestion = vformat(
			"The script backend for %s is not part of this build, so no verdict is possible here: validate the file in a build "
			"that contains that backend (for '.cs' that is a Mono build, module_mono_enabled=yes), or validate a '.gd' script "
			"with this build",
			spelled);
	return MCPToolError::tool_state(message, suggestion);
}

// TASK-056 (D1): the "no verdict" claim and its source, for the batch tool. It
// has to fit the item's `reason` bound (800 bytes, MAX_REASON_BYTES in
// tools/project_validate_scripts.cpp) and to name the two engine calls that
// decided it, so a caller can check the claim instead of believing it.
String validate_script_language_unavailable_reason(const String &p_path, const String &p_extension) {
	return vformat("This build cannot judge '%s': ScriptServer::are_languages_initialized() / "
				   "ScriptServer::get_language_for_extension(\"%s\") (core/object/script_language.h) found no script "
				   "language for the extension '%s', so the file was never parsed or compiled here and no 'valid' "
				   "value is published (a missing backend is a property of this build, not a verdict on the file).",
			p_path, p_extension, p_extension);
}

// TASK-055 (D112): the residual case where the engine cannot be asked at all.
// TASK-054 used this classification for every `.cs` file because no signal
// existed; the engine now carries one (`CSharpScript::is_source_newer_than_assembly()`,
// TASK-055's patch) and `Script::is_script_valid()` was always public, so this is
// only reached when the file does not load as a `Script` resource.
String validate_script_unverifiable_reason(const String &p_path) {
	return vformat("The engine could not load '%s' as a Script resource, so neither Script::is_script_valid() "
		   "(core/object/script_language.h:180) nor CSharpScript::is_source_newer_than_assembly() "
		   "(modules/mono/csharp_script.h) could be read: no compile state of this file is known here.",
			p_path);
}

MCPToolError validate_script_unverifiable_error(const String &p_path) {
	const String message = vformat(
			"Cannot validate '%s': the engine could not load it as a Script resource, so the file was not verified "
			"and no 'valid' value is published",
			p_path);
	const String suggestion = vformat(
			"'%s' exists but did not load as a Script, so the engine's compile state for it could not be read "
			"(is a class for its path in the loaded .NET assembly, and has the file changed since that assembly was "
			"built); check that the file is a readable C# source of this project",
			p_path);
	return MCPToolError::tool_state(message, suggestion);
}

// TASK-055 (D112): the engine basis of `not_compiled`. Written as the batch
// item's `reason` (< 800 bytes, MAX_REASON_BYTES) so the claim can be checked at
// its source instead of believed.
String validate_script_not_compiled_reason(bool p_class_loaded, bool p_source_newer_than_assembly) {
	Vector<String> signals;
	if (p_source_newer_than_assembly) {
		signals.push_back("the file was modified after the .NET assembly that is loaded was built "
						  "(CSharpScript::is_source_newer_than_assembly(), modules/mono/csharp_script.h)");
	}
	if (!p_class_loaded) {
		signals.push_back("the loaded assembly has no class for this script's path "
						  "(Script::is_script_valid(), core/object/script_language.h:180)");
	}
	if (signals.is_empty()) {
		// Not reachable through `classify_csharp_verdict`; kept total anyway.
		signals.push_back("no class for this path is loaded and no build of this source was recorded");
	}
	return vformat("No build of this source is loaded: %s. The engine has no C# compiler - "
				   "CSharpScript::reload() only looks the type up in the already built assembly and returns OK "
				   "unconditionally (modules/mono/csharp_script.cpp) - so 'nothing compiled it yet' is not a compile "
				   "failure. Run project_build_csharp (its per-file diagnostics are recorded) and ask again.",
			String(", and ").join(signals));
}

MCPToolError validate_script_not_compiled_error(const String &p_path, bool p_class_loaded, bool p_source_newer_than_assembly) {
	const String message = vformat(
			"Cannot validate '%s': no build of this source is loaded, so the file was not compiled and no 'valid' "
			"value is published",
			p_path);
	const String suggestion = vformat(
			"This is 'not compiled', which is not 'does not compile': %s Run project_build_csharp (it records the "
			"compiler's own diagnostics per file) and call project_validate_script again.",
			validate_script_not_compiled_reason(p_class_loaded, p_source_newer_than_assembly));
	return MCPToolError::tool_state(message, suggestion);
}

// TASK-055: the `error_text` of an `invalid` C# verdict is the compiler's own
// text, joined, never an `ERR_*` identifier this module invented.
String csharp_recorded_error_text(const Array &p_errors) {
	Vector<String> texts;
	for (int i = 0; i < p_errors.size(); i++) {
		const Variant element = p_errors[i];
		if (element.get_type() != Variant::DICTIONARY) {
			continue;
		}
		const String text = ((Dictionary)element).get("text", String());
		if (!text.is_empty()) {
			texts.push_back(text.strip_edges());
		}
	}
	return String(" | ").join(texts);
}

// The verdict is *project-level*: the diagnostics come from a build of the
// whole `.csproj`, and the message says so rather than pretending the compiler
// judged this file alone.
String csharp_recorded_failure_message(const String &p_path, const Array &p_errors) {
	const Dictionary record = read_csharp_build_record();
	const Array project_files = record.get("project_files", Array());
	Vector<String> projects;
	for (int i = 0; i < project_files.size(); i++) {
		projects.push_back(project_files[i]);
	}
	const String scope = projects.is_empty() ? String("the project's C# solution") : String(", ").join(projects);
	return vformat("Compilation failed. The last C# build recorded by project_build_csharp (a project-level build of "
				   "%s) rejected '%s' as it is now: %s",
			scope, p_path, csharp_recorded_error_text(p_errors));
}

// TASK-055 (D112): the C# verdict, built from the two engine signals plus the
// project-level build record. The decision itself is the pure
// `classify_csharp_verdict` (tools/csharp_verdict.h), which the doctests cover in
// this build as well; this function is the part that has to talk to the engine.
MCPValidateScriptVerdict validate_csharp_script_source(const String &p_path) {
	MCPValidateScriptVerdict verdict;
	verdict.language = "cs";

#ifdef MODULE_MONO_ENABLED
	// `ResourceLoader::load` is the path the editor itself uses for a `.cs` file:
	// `ResourceFormatLoaderCSharpScript::load()` asks the bridge for the script
	// of this path and calls `reload()`, which is what fills `valid`, so this
	// reads the engine's *current* state instead of manufacturing one.
	const Ref<Script> script = ResourceLoader::load(p_path, "Script");
	const CSharpScript *csharp = Object::cast_to<CSharpScript>(script.ptr());
	if (script.is_null() || csharp == nullptr) {
		verdict.category = "unverifiable";
		verdict.valid = false;
		verdict.reason = validate_script_unverifiable_reason(p_path);
		verdict.message = validate_script_unverifiable_error(p_path).message;
		return verdict;
	}

	const bool class_loaded = script->is_script_valid();
	const bool source_newer_than_assembly = csharp->is_source_newer_than_assembly();
	const Array recorded_errors = recorded_csharp_build_errors(p_path);

	switch (classify_csharp_verdict(class_loaded, source_newer_than_assembly, !recorded_errors.is_empty())) {
		case MCPCSharpVerdict::COMPILED: {
			verdict.category = "ok";
			verdict.valid = true;
			verdict.message = "Compiled: the loaded .NET assembly contains a build of this source, and the file has "
							  "not been modified since that build";
		} break;
		case MCPCSharpVerdict::BUILD_FAILED: {
			verdict.category = "invalid";
			verdict.valid = false;
			verdict.error_text = csharp_recorded_error_text(recorded_errors);
			verdict.message = csharp_recorded_failure_message(p_path, recorded_errors);
		} break;
		case MCPCSharpVerdict::NOT_COMPILED: {
			verdict.category = "not_compiled";
			// Inert on the wire (the plural tool publishes no `valid` for this
			// category and the singular tool refuses); kept `false` so no caller
			// can read this struct as a positive verdict.
			verdict.valid = false;
			verdict.reason = validate_script_not_compiled_reason(class_loaded, source_newer_than_assembly);
			verdict.message = validate_script_not_compiled_error(p_path, class_loaded, source_newer_than_assembly).message;
		} break;
	}
	return verdict;
#else
	// Unreachable: this function is only called when `ScriptServer` resolved the
	// file's extension to the `C#` language, which a build without the module
	// cannot have. It is written out so the function is total.
	verdict.category = "language_unavailable";
	verdict.valid = false;
	verdict.reason = validate_script_language_unavailable_reason(p_path, "cs");
	verdict.message = validate_script_language_unavailable_error(p_path, "cs").message;
	return verdict;
#endif
}

// TASK-053 section 2.1: the one per-file decision both validate tools publish.
// `_tool_validate_script` below is written on top of it, so the single-file
// answer did not move by a byte when the batch tool was added.
MCPValidateScriptVerdict validate_script_source(const String &p_path, const String &p_source) {
	MCPValidateScriptVerdict verdict;
	const String extension = file_extension(p_path);
	verdict.language = extension;

	const bool languages_initialized = ScriptServer::are_languages_initialized();
	ScriptLanguage *language = languages_initialized ? ScriptServer::get_language_for_extension(extension) : nullptr;

	if (classify_validate_script_mode(languages_initialized, language != nullptr) == MCPValidateScriptMode::LANGUAGE_UNAVAILABLE) {
		verdict.category = "language_unavailable";
		verdict.valid = false;
		// Inert on the wire: the plural tool publishes `valid: null` for this
		// category (TASK-056 D1) and the singular tool refuses. Kept `false` so
		// no caller can read this struct as a positive verdict.
		verdict.reason = validate_script_language_unavailable_reason(p_path, extension);
		verdict.message = validate_script_language_unavailable_error(p_path, extension).message;
		return verdict;
	}

	// TASK-055 (D112): C# is the one language of this fork whose `reload()` cannot
	// answer the question, and it now has its own verdict path built on the two
	// engine signals (`Script::is_script_valid()` and the `CSharpScript::
	// is_source_newer_than_assembly()` accessor this task added) plus the
	// project-level build record. It is reachable only in a build that contains
	// the C# backend, which is exactly when `language` can be non-null here.
	if (language != nullptr && language->get_name() == "C#") {
		MCPValidateScriptVerdict csharp = validate_csharp_script_source(p_path);
		// The extension as this file spells it (`file_extension()`), not as the
		// language's own `get_extension()` spells it: every other verdict of this
		// function publishes the extension of the *path*.
		csharp.language = extension;
		return csharp;
	}

	bool compile_attempted = false;
	bool compiled = false;
	String error_text;
	if (language != nullptr && ClassDB::class_exists(language->get_type())) {
		// The same two calls the reference makes through the GDScript
		// binding: `set_source_code()` + `reload()`.
		Ref<Script> script = Object::cast_to<Script>(ClassDB::instantiate(language->get_type()));
		if (script.is_valid()) {
			script->set_source_code(p_source);
			const Error compile_error = script->reload();
			compile_attempted = true;
			compiled = (compile_error == OK);
			if (!compiled) {
				error_text = _error_identifier(compile_error);
			}
		}
	}

	if (compile_attempted) {
		verdict.valid = compiled;
		if (compiled) {
			verdict.category = "ok";
			verdict.message = "Script compiles successfully";
		} else {
			verdict.category = "invalid";
			verdict.error_text = error_text;
			verdict.message = "Compilation failed. Check the script for errors.";
		}
		return verdict;
	}

	// The documented structural fallback. Its message has to survive verbatim:
	// the single-file tool has always said that nothing was compiled, and a
	// batch item that took this path says it too.
	const bool plausible = _structurally_balanced(p_source);
	verdict.valid = plausible;
	verdict.category = plausible ? "ok" : "invalid";
	if (!plausible) {
		verdict.error_text = "ERR_PARSE_ERROR";
	}
	verdict.message = "No script language is initialised in this process; a structural bracket check was performed instead of a compilation.";
	return verdict;
}

MCPToolError validate_script_verdict_refusal(const String &p_path, const MCPValidateScriptVerdict &p_verdict) {
	if (p_verdict.category == "unverifiable") {
		return validate_script_unverifiable_error(p_path);
	}
	const String suggestion = vformat(
			"This is 'not compiled', which is not 'does not compile': %s Run project_build_csharp (it records the "
			"compiler's own diagnostics per file) and call project_validate_script again.",
			p_verdict.reason);
	return MCPToolError::tool_state(p_verdict.message, suggestion);
}

} // namespace MCPTools

static Variant _tool_validate_script(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	String normalized;
	if (!normalize_project_path(path, normalized, r_error)) {
		return Variant();
	}
	if (!FileAccess::exists(normalized)) {
		r_error = MCPToolError::not_found(vformat("Script '%s'", normalized),
				"Use project_get_filesystem_tree to list the .gd files of the project");
		return Variant();
	}
	String source;
	if (!read_project_text_file(normalized, source, r_error)) {
		return Variant();
	}

	const MCPValidateScriptVerdict verdict = validate_script_source(normalized, source);

	// The batch tool's third category has to be a refusal *here*: one file asked
	// about by name cannot answer "no verdict" as a successful payload, and
	// `valid: false` would be read as "it does not compile" (TASK-050 N-2).
	if (verdict.category == "language_unavailable") {
		r_error = validate_script_language_unavailable_error(normalized, verdict.language);
		return Variant();
	}
	// TASK-054/TASK-055: the two categories that cannot answer with a payload.
	// This tool has no `category` field, so `valid: true` would be a lie and
	// `valid: false` would be read as "it does not compile"; the refusal carries
	// the same sentences the plural tool's item carries (TASK-050 N-2 shape).
	// `not_compiled` is the TASK-055 addition: "nothing compiled this source"
	// must not be published as "it does not compile".
	if (verdict.category == "unverifiable" || verdict.category == "not_compiled") {
		r_error = validate_script_verdict_refusal(normalized, verdict);
		return Variant();
	}

	Dictionary result;
	result["path"] = normalized;
	// A script that does not compile is still a *successful* tool call: the
	// answer is `valid: false`, not a JSON-RPC error. Preserved from the
	// reference.
	result["valid"] = verdict.valid;
	if (verdict.category == "invalid" && !verdict.error_text.is_empty()) {
		result["error_text"] = verdict.error_text;
	}
	result["message"] = verdict.message;
	return result;
}

// ---------------------------------------------------------------------------
// project_read_resource (old `read_resource`)
//
// resource.rs:75. Loads the resource and reports its class.
//
// TASK-026 (E-9): the tool used to answer `{loaded, path, type}` and nothing
// else, so a caller who wanted one value of the resource it had just read had to
// run a second tool (`editor_execute_gdscript`); M4c measured exactly that
// against `res://cv_d5_b.tres`. That is the "multiple-step dance" GDR-25 section
// 23.1 rules out, and the engine contradicts it: one `ResourceLoader::load()`
// plus one `Resource::get_property_list()` already yields every value the
// resource stores.
//
// "Stores" is the engine's own word: `PROPERTY_USAGE_STORAGE`
// (`core/object/property_info.h:91`) is the flag the resource saver itself uses
// to decide what goes into the `.tres`, so it is the exact set a reader can
// expect the file to hold. (It is *not* every readable property: a `Curve`'s
// `min_value` is declared `PROPERTY_USAGE_EDITOR` only - it is derived from the
// stored `_data` - and is therefore deliberately not part of a "what does this
// file store" answer.)
//
// Every value goes through the module's single `serialize_variant()`, so it
// answers the shape the write side accepts (GDR-25 section 23.4) and can be fed
// back into `project_edit_resource` as it is.
//
// The answer is bounded in *count* with an explicit truncation marker
// (`truncated` / `dropped` / `limits`, the same three keys
// `running_game_stop_input_recording` uses): a resource with a hundred stored
// properties must not be able to push an unbounded body through the transport.
// ---------------------------------------------------------------------------

// 64 stored properties is a complete answer for the resources a caller inspects
// one at a time (a `Gradient` stores 2, a `PhysicsMaterial` 3, a `Curve` fewer
// than 10); a larger one is a bulk resource (`Environment` stores 90+) whose
// individual values are more usefully read by name. The cap is a count, not a
// byte budget - a single `PackedFloat32Array` property can still be large, which
// is recorded as a residual in REPORT-026 rather than silently implied to be
// bounded.
static const int MAX_RESOURCE_PROPERTIES = 64;

static Variant _tool_read_resource(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	String normalized;
	if (!normalize_project_path(path, normalized, r_error)) {
		return Variant();
	}
	if (!FileAccess::exists(normalized)) {
		r_error = MCPToolError::not_found(vformat("Resource '%s'", normalized),
				"Use project_get_filesystem_tree to list the files of the project");
		return Variant();
	}
	const Ref<Resource> resource = ResourceLoader::load(normalized);
	if (resource.is_null()) {
		r_error = MCPToolError::not_found(vformat("Resource '%s'", normalized),
				"Use project_get_filesystem_tree to list the files of the project");
		return Variant();
	}

	Dictionary result;
	result["path"] = normalized;
	result["type"] = resource->get_class();
	result["loaded"] = true;

	// The same `List<PropertyInfo>` the GDScript binding serialises into
	// `get_property_list()`, in the engine's own order - so the answer is
	// deterministic (PLAYBOOK section 6.4) instead of being at the mercy of a
	// hash map.
	List<PropertyInfo> property_list;
	resource->get_property_list(&property_list);

	Dictionary properties;
	int total = 0;
	int dropped = 0;
	for (const PropertyInfo &property : property_list) {
		if (!(property.usage & PROPERTY_USAGE_STORAGE)) {
			continue;
		}
		total++;
		if (total > MAX_RESOURCE_PROPERTIES) {
			dropped++;
			continue;
		}
		properties[String(property.name)] = serialize_variant(resource->get(property.name));
	}

	result["properties"] = properties;
	result["total_properties"] = total;
	result["truncated"] = dropped > 0;
	result["dropped"] = dropped;
	Dictionary limits;
	limits["max_properties"] = MAX_RESOURCE_PROPERTIES;
	result["limits"] = limits;
	if (total == 0) {
		// The honest empty answer: "this resource stores no property" is a
		// result, not a reason to invent a placeholder key.
		result["message"] = "The resource stores no property (get_property_list() reports no PROPERTY_USAGE_STORAGE entry)";
	} else if (dropped > 0) {
		result["message"] = vformat("%d of %d stored properties returned; %d omitted by the tool's limit",
				(int)properties.size(), total, dropped);
	} else {
		result["message"] = vformat("All %d stored properties of the resource are returned", total);
	}
	return result;
}

// ---------------------------------------------------------------------------
// project_get_resource_preview (old `get_resource_preview`)
//
// resource.rs:278. An image file is decoded straight by `Image::load`; any other
// path goes through `ResourceLoader` and is accepted when the loaded object is,
// or carries, an `Image`. The output is always a PNG, base64 encoded.
//
// Two deliberate differences from the reference:
//   * `max_size <= 0` is an explicit -32602. The reference would pass 0 to
//     `Image::resize()`, which is an ERR_FAIL and a division by zero in the
//     scale computation.
//   * base64 goes through `CryptoCore::b64_encode_str()`, an engine static, and
//     never through `Marshalls::get_singleton()`: the singleton is not
//     guaranteed to exist in a process that only runs the tool layer.
// ---------------------------------------------------------------------------

static const char *const PREVIEW_IMAGE_EXTENSIONS[] = {
	"png", "jpg", "jpeg", "bmp", "webp", "svg"
};

static Variant _tool_get_resource_preview(const Dictionary &p_args, MCPToolError &r_error) {
	String path;
	if (!require_string(p_args, "path", path, r_error)) {
		return Variant();
	}
	int64_t max_size = 256;
	if (!optional_int(p_args, "max_size", 256, max_size, r_error)) {
		return Variant();
	}
	if (max_size <= 0) {
		r_error = MCPToolError::invalid_params(
				vformat("Parameter 'max_size' must be a positive integer, got %d", max_size));
		return Variant();
	}
	String normalized;
	if (!normalize_project_path(path, normalized, r_error)) {
		return Variant();
	}
	// A path that is not there is -32001 in *both* branches, before any decoder
	// gets a chance to turn it into a decode error.
	if (!FileAccess::exists(normalized)) {
		r_error = MCPToolError::not_found(vformat("File '%s'", normalized),
				"Use project_get_filesystem_tree to list the files of the project");
		return Variant();
	}

	const String extension = file_extension(normalized).to_lower();
	bool is_image_file = false;
	for (const char *candidate : PREVIEW_IMAGE_EXTENSIONS) {
		if (extension == candidate) {
			is_image_file = true;
			break;
		}
	}

	Ref<Image> image;
	if (is_image_file) {
		image.instantiate();
		const Error load_error = image->load(normalized);
		if (load_error != OK) {
			r_error = MCPToolError::internal(vformat("Failed to load image: %s", _error_identifier(load_error)));
			return Variant();
		}
	} else {
		const Ref<Resource> resource = ResourceLoader::load(normalized);
		if (resource.is_null()) {
			r_error = MCPToolError::not_found(vformat("Resource '%s'", normalized),
					"Use project_get_filesystem_tree to list the files of the project");
			return Variant();
		}
		// Texture first, then Image, in that order - like the reference.
		Texture2D *texture = Object::cast_to<Texture2D>(resource.ptr());
		if (texture != nullptr) {
			image = texture->get_image();
		} else {
			Image *as_image = Object::cast_to<Image>(resource.ptr());
			if (as_image != nullptr) {
				image = as_image;
			} else {
				// The object exists and is applicable to no preview: that is an
				// argument-class error, not a "not found".
				r_error = MCPToolError::invalid_params(
						vformat("Resource type '%s' does not have an image preview", resource->get_class()));
				return Variant();
			}
		}
	}

	if (image.is_null()) {
		r_error = MCPToolError::internal("Could not extract image from resource");
		return Variant();
	}

	// Uniform scale, truncated to whole pixels: `min(max/w, max/h)`.
	const int width = image->get_width();
	const int height = image->get_height();
	if (width > max_size || height > max_size) {
		const double scale = MIN((double)max_size / (double)width, (double)max_size / (double)height);
		const int new_width = (int)((double)width * scale);
		const int new_height = (int)((double)height * scale);
		image->resize(new_width, new_height);
	}

	const Vector<uint8_t> png = image->save_png_to_buffer();
	if (png.is_empty()) {
		r_error = MCPToolError::internal("Failed to encode the preview as PNG");
		return Variant();
	}

	Dictionary result;
	result["image_base64"] = CryptoCore::b64_encode_str(png.ptr(), png.size());
	result["width"] = image->get_width();
	result["height"] = image->get_height();
	result["format"] = "png";
	result["path"] = normalized;
	return result;
}

// ---------------------------------------------------------------------------
// project_read_scene_file_content (old `get_scene_file_content`)
//
// scene.rs:228. The raw text of a `.tscn` file and nothing else: no parsing, no
// node tree, no line numbers. "Scene file '<path>'" is this tool's own wording
// for a missing file, exactly as the reference has one wording per tool.
// ---------------------------------------------------------------------------

static Variant _tool_read_scene_file_content(const Dictionary &p_args, MCPToolError &r_error) {
	return _read_text_payload(p_args, "Scene file",
			"Use project_get_filesystem_tree to list the .tscn files of the project", r_error);
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

void register_project_read_files_tools(MCPToolRegistry &r_registry) {
	// Order follows docs/tool-groups.json. The order is not a contract, but it
	// has to be stable and append-only. Every tool is channel `project`,
	// `mutating = false`, `scope = BOTH`, and takes its description and
	// `inputSchema` verbatim from docs/tools_list.renamed.json.
	{
		// No parameters at all: the contract's schema is the empty object.
		//
		// TASK-068 (2.i): the description states the walk's one observable
		// consequence. The walk is deliberately NOT narrowed - only `.` and `..`
		// are skipped (see `_collect_scripts_recursive`), so the engine's own
		// project cache is collected with everything else, and the
		// `.hiddendir/secret.gd` doctest is what pins that rule. Listing a
		// generated file is honest; hiding one needs a machine-checkable rule
		// this tool does not have (D125 (b)), so the caller is told to filter.
		// The text is the contract's `project_list_scripts.description` verbatim
		// (`DESCRIPTION_OVERRIDES["list_scripts"]`, append mode) - gate 1 compares
		// the two character for character.
		ToolBuilder builder("project_list_scripts", String::utf8("列出所有脚本文件 会包含 .godot 下的生成脚本：本工具的 walk 从 res:// 起递归，只跳过 . 与 ..，因此引擎自己生成的文件也在答案里（真实 mono 工程会出现 res://.godot/mono/temp/obj/** 下的 .cs，例如 res://.godot/mono/temp/obj/Debug/*.AssemblyInfo.cs），调用方若要只看手写脚本请自行过滤这些路径。"));
		builder.channel("project").verb("list").scope(MCPToolScope::BOTH).mutating(false).schema(empty_object_schema()).handler(_tool_list_scripts);
		builder.register_into(r_registry);
	}

	{
		Dictionary path_property;
		path_property["type"] = "string";

		Dictionary properties;
		properties["path"] = path_property;

		Array required;
		required.push_back("path");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		ToolBuilder builder("project_read_script", String::utf8("读取脚本文件"));
		builder.channel("project").verb("read").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_read_script);
		builder.register_into(r_registry);
	}

	{
		Dictionary path_property;
		path_property["type"] = "string";

		Dictionary properties;
		properties["path"] = path_property;

		Array required;
		required.push_back("path");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		ToolBuilder builder("project_validate_script", String::utf8("验证脚本语法 判别点：valid 只在真的用该文件自身的脚本语言编译过时才是结论（true=编译通过；false=编译失败，error_text 给 ERR_* 标识符）；本构建不含该语言的脚本后端时（例如 module_mono_enabled=no 的构建里的 .cs）不借用别的语言解析、也不给出 valid，而是以 -32000 拒绝并在 data.suggestion 里说明该用哪个构建或文件；进程根本没有初始化任何脚本语言时（--test 进程）只做括号平衡的结构检查，message 会明说没有编译。 A '.cs' file now gets a real verdict (TASK-055): `valid: true` means the loaded .NET assembly contains a build of this exact source (Script::is_script_valid() found a class for the script's path and CSharpScript::is_source_newer_than_assembly() says the file has not changed since that assembly was built); `valid: false` with `error_text` carrying the compiler's own diagnostic text means a project-level build of its .csproj that project_build_csharp ran and recorded rejected the file as it is now; and a file nothing has compiled - edited after the last build, or with no class in the loaded assembly - is refused with -32000 saying 'not compiled', never answered `valid: false`, because the engine itself has no C# compiler (CSharpScript::reload() returns OK unconditionally)."));
		builder.channel("project").verb("validate").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_validate_script);
		builder.register_into(r_registry);
	}

	{
		Dictionary path_property;
		path_property["type"] = "string";

		Dictionary properties;
		properties["path"] = path_property;

		Array required;
		required.push_back("path");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		ToolBuilder builder("project_read_resource", String::utf8("读取资源文件"));
		builder.channel("project").verb("read").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_read_resource);
		builder.register_into(r_registry);
	}

	{
		Dictionary max_size_property;
		max_size_property["type"] = "integer";
		max_size_property["description"] = String::utf8("最大尺寸 (默认 256)");
		max_size_property["default"] = 256;

		Dictionary path_property;
		path_property["type"] = "string";
		path_property["description"] = String::utf8("资源文件路径 (res://)");

		Dictionary properties;
		properties["max_size"] = max_size_property;
		properties["path"] = path_property;

		Array required;
		required.push_back("path");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		ToolBuilder builder("project_get_resource_preview", String::utf8("获取资源预览图片 (base64编码PNG)"));
		builder.channel("project").verb("get").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_get_resource_preview);
		builder.register_into(r_registry);
	}

	{
		Dictionary path_property;
		path_property["type"] = "string";
		path_property["description"] = String::utf8("场景文件路径 (res://)");

		Dictionary properties;
		properties["path"] = path_property;

		Array required;
		required.push_back("path");

		Dictionary schema;
		schema["type"] = "object";
		schema["properties"] = properties;
		schema["required"] = required;

		ToolBuilder builder("project_read_scene_file_content", String::utf8("读取 .tscn 场景文件内容"));
		builder.channel("project").verb("read").scope(MCPToolScope::BOTH).mutating(false).schema(schema).handler(_tool_read_scene_file_content);
		builder.register_into(r_registry);
	}
}