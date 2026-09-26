/**************************************************************************/
/*  project_settings.cpp                                                  */
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

#include "project_settings.h"

#include "core/input/input_map.h"
#include "core/io/compression.h"
#include "core/io/config_file.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/file_access_pack.h"
#include "core/io/marshalls.h"
#include "core/io/resource_uid.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/object/message_queue.h"
#include "core/object/script_language.h"
#include "core/os/os.h"
#include "core/templates/rb_set.h"
#include "core/variant/typed_array.h"
#include "core/variant/variant_parser.h"
#include "core/version.h"

#ifdef TOOLS_ENABLED
#include "core/config/engine.h"

#include "modules/modules_enabled.gen.h" // IWYU pragma: keep. For mono.
#endif // TOOLS_ENABLED

ProjectSettings *ProjectSettings::get_singleton() {
	return singleton;
}

String ProjectSettings::get_project_data_dir_name() const {
	return project_data_dir_name;
}

String ProjectSettings::get_project_data_path() const {
	return "res://" + get_project_data_dir_name();
}

String ProjectSettings::get_resource_path() const {
	return resource_path;
}

// This returns paths like "res://.godot/imported".
String ProjectSettings::get_imported_files_path() const {
	return get_project_data_path().path_join("imported");
}

#ifdef TOOLS_ENABLED
// Returns the features that a project must have when opened with this build of Godot.
// This is used by the project manager to provide the initial_settings for config/features.
const PackedStringArray ProjectSettings::get_required_features() {
	PackedStringArray features;
	features.append(GODOT_VERSION_BRANCH);
#ifdef REAL_T_IS_DOUBLE
	features.append("Double Precision");
#endif
	return features;
}

// Returns the features supported by this build of Godot. Includes all required features.
const PackedStringArray ProjectSettings::_get_supported_features() {
	PackedStringArray features = get_required_features();

#ifdef LIBGODOT_ENABLED
	features.append("LibGodot");
#endif

#ifdef MODULE_MONO_ENABLED
	features.append("C#");
#endif
	// Allow pinning to a specific patch number or build type by marking
	// them as supported. They're only used if the user adds them manually.
	features.append(GODOT_VERSION_BRANCH "." _MKSTR(GODOT_VERSION_PATCH));
	features.append(GODOT_VERSION_FULL_CONFIG);
	features.append(GODOT_VERSION_FULL_BUILD);

#ifdef RD_ENABLED
#ifdef FORWARD_RD_ENABLED
	features.append("Forward Plus");
#endif // FORWARD_RD_ENABLED
#ifdef MOBILE_RD_ENABLED
	features.append("Mobile");
#endif // MOBILE_RD_ENABLED
#endif

#ifdef GLES3_ENABLED
	features.append("GL Compatibility");
#endif
	return features;
}

// Returns the features that this project needs but this build of Godot lacks.
const PackedStringArray ProjectSettings::get_unsupported_features(const PackedStringArray &p_project_features) {
	PackedStringArray unsupported_features;
	PackedStringArray supported_features = singleton->_get_supported_features();
	for (int i = 0; i < p_project_features.size(); i++) {
		if (!supported_features.has(p_project_features[i])) {
			// Temporary compatibility code to ease upgrade to 4.0 beta 2+.
			if (p_project_features[i].begins_with("Vulkan")) {
				continue;
			}
			unsupported_features.append(p_project_features[i]);
		}
	}
	unsupported_features.sort();
	return unsupported_features;
}

// Returns the features that both this project has and this build of Godot has, ensuring required features exist.
const PackedStringArray ProjectSettings::_trim_to_supported_features(const PackedStringArray &p_project_features) {
	// Remove unsupported features if present.
	PackedStringArray features = PackedStringArray(p_project_features);
	PackedStringArray supported_features = _get_supported_features();
	for (int i = p_project_features.size() - 1; i > -1; i--) {
		if (!supported_features.has(p_project_features[i])) {
			features.remove_at(i);
		}
	}
	// Add required features if not present.
	PackedStringArray required_features = get_required_features();
	for (int i = 0; i < required_features.size(); i++) {
		if (!features.has(required_features[i])) {
			features.append(required_features[i]);
		}
	}
	features.sort();
	return features;
}
#endif // TOOLS_ENABLED

String ProjectSettings::localize_path(const String &p_path) const {
	String path = p_path.simplify_path();

	if (resource_path.is_empty() || (path.is_absolute_path() && !path.begins_with(resource_path))) {
		return path;
	}

	// Check if we have a special path (like res://) or a protocol identifier.
	int p = path.find("://");
	bool found = false;
	if (p > 0) {
		found = true;
		for (int i = 0; i < p; i++) {
			if (!is_ascii_alphanumeric_char(path[i])) {
				found = false;
				break;
			}
		}
	}
	if (found) {
		return path;
	}

	Ref<DirAccess> dir = DirAccess::create(DirAccess::ACCESS_FILESYSTEM);

	if (dir->change_dir(path) == OK) {
		String cwd = dir->get_current_dir();
		cwd = cwd.replace_char('\\', '/');

		// Ensure that we end with a '/'.
		// This is important to ensure that we do not wrongly localize the resource path
		// in an absolute path that just happens to contain this string but points to a
		// different folder (e.g. "/my/project" as resource_path would be contained in
		// "/my/project_data", even though the latter is not part of res://.
		// `path_join("")` is an easy way to ensure we have a trailing '/'.
		const String res_path = resource_path.path_join("");

		// DirAccess::get_current_dir() is not guaranteed to return a path that with a trailing '/',
		// so we must make sure we have it as well in order to compare with 'res_path'.
		cwd = cwd.path_join("");

		if (!cwd.begins_with(res_path)) {
			return path;
		}

		return cwd.replace_first(res_path, "res://");
	} else {
		int sep = path.rfind_char('/');
		if (sep == -1) {
			return "res://" + path;
		}

		String parent = path.substr(0, sep);

		String plocal = localize_path(parent);
		if (plocal.is_empty()) {
			return "";
		}
		// Only strip the starting '/' from 'path' if its parent ('plocal') ends with '/'
		if (plocal[plocal.length() - 1] == '/') {
			sep += 1;
		}
		return plocal + path.substr(sep);
	}
}

void ProjectSettings::set_initial_value(const String &p_name, const Variant &p_value) {
	ERR_FAIL_COND_MSG(!props.has(p_name), vformat("Request for nonexistent project setting: '%s'.", p_name));

	// Duplicate so that if value is array or dictionary, changing the setting will not change the stored initial value.
	props[p_name].initial = p_value.duplicate();
}

void ProjectSettings::set_restart_if_changed(const String &p_name, bool p_restart) {
	ERR_FAIL_COND_MSG(!props.has(p_name), vformat("Request for nonexistent project setting: '%s'.", p_name));
	props[p_name].restart_if_changed = p_restart;
}

void ProjectSettings::set_as_basic(const String &p_name, bool p_basic) {
	ERR_FAIL_COND_MSG(!props.has(p_name), vformat("Request for nonexistent project setting: '%s'.", p_name));
	props[p_name].basic = p_basic;
}

void ProjectSettings::set_as_internal(const String &p_name, bool p_internal) {
	ERR_FAIL_COND_MSG(!props.has(p_name), vformat("Request for nonexistent project setting: '%s'.", p_name));
	props[p_name].internal = p_internal;
}

void ProjectSettings::set_ignore_value_in_docs(const String &p_name, bool p_ignore) {
	ERR_FAIL_COND_MSG(!props.has(p_name), vformat("Request for nonexistent project setting: '%s'.", p_name));
#ifdef DEBUG_ENABLED
	props[p_name].ignore_value_in_docs = p_ignore;
#endif // DEBUG_ENABLED
}

bool ProjectSettings::get_ignore_value_in_docs(const String &p_name) const {
	ERR_FAIL_COND_V_MSG(!props.has(p_name), false, vformat("Request for nonexistent project setting: '%s'.", p_name));
#ifdef DEBUG_ENABLED
	return props[p_name].ignore_value_in_docs;
#else
	return false;
#endif // DEBUG_ENABLED
}

void ProjectSettings::add_hidden_prefix(const String &p_prefix) {
	ERR_FAIL_COND_MSG(hidden_prefixes.has(p_prefix), vformat("Hidden prefix '%s' already exists.", p_prefix));
	hidden_prefixes.push_back(p_prefix);
}

String ProjectSettings::globalize_path(const String &p_path) const {
	if (p_path.begins_with("res://")) {
		if (!resource_path.is_empty()) {
			return p_path.replace("res:/", resource_path);
		}
		return p_path.replace("res://", "");
	} else if (p_path.begins_with("uid://")) {
		const String path = ResourceUID::uid_to_path(p_path);
		if (!resource_path.is_empty()) {
			return path.replace("res:/", resource_path);
		}
		return path.replace("res://", "");
	} else if (p_path.begins_with("user://")) {
		String data_dir = OS::get_singleton()->get_user_data_dir();
		if (!data_dir.is_empty()) {
			return p_path.replace("user:/", data_dir);
		}
		return p_path.replace("user://", "");
	}

	return p_path;
}

bool ProjectSettings::_set(const StringName &p_name, const Variant &p_value) {
	_THREAD_SAFE_METHOD_

	// Early return if value hasn't changed (unless it's being deleted)
	if (p_value.get_type() != Variant::NIL) {
		if (props.has(p_name) && props[p_name].variant == p_value) {
			return true;
		}
	}

	if (p_value.get_type() == Variant::NIL) {
		props.erase(p_name);
		if (p_name.string().begins_with("autoload/")) {
			String node_name = p_name.string().get_slicec('/', 1);
			if (autoloads.has(node_name)) {
				remove_autoload(node_name);
			}
		} else if (p_name.string().begins_with("global_group/")) {
			String group_name = p_name.string().get_slicec('/', 1);
			if (global_groups.has(group_name)) {
				remove_global_group(group_name);
			}
		}
	} else {
		if (p_name == CoreStringName(_custom_features)) {
			Vector<String> custom_feature_array = String(p_value).split(",");
			for (int i = 0; i < custom_feature_array.size(); i++) {
				custom_features.insert(custom_feature_array[i]);
			}

			_version++;
			_queue_changed(p_name);
			return true;
		}

		{ // Feature overrides.
			int dot = p_name.string().find_char('.');
			if (dot != -1) {
				Vector<String> s = p_name.string().split(".");

				for (int i = 1; i < s.size(); i++) {
					String feature = s[i].strip_edges();
					Pair<StringName, StringName> feature_override(feature, p_name);

					if (!feature_overrides.has(s[0])) {
						feature_overrides[s[0]] = LocalVector<Pair<StringName, StringName>>();
					}

					feature_overrides[s[0]].push_back(feature_override);
				}
			}
		}

		if (props.has(p_name)) {
			props[p_name].variant = p_value;
		} else {
			props[p_name] = VariantContainer(p_value, last_order++);
		}
		if (p_name.string().begins_with("autoload_prepend/")) {
			String node_name = p_name.string().get_slicec('/', 1);
			AutoloadInfo autoload;
			autoload.name = node_name;
			String path = p_value;
			if (path.begins_with("*")) {
				autoload.is_singleton = true;
				autoload.path = path.substr(1).simplify_path();
			} else {
				autoload.path = path.simplify_path();
			}
			add_autoload(autoload, true);
		} else if (p_name.string().begins_with("autoload/")) {
			String node_name = p_name.string().get_slicec('/', 1);
			AutoloadInfo autoload;
			autoload.name = node_name;
			String path = p_value;
			if (path.begins_with("*")) {
				autoload.is_singleton = true;
				autoload.path = path.substr(1).simplify_path();
			} else {
				autoload.path = path.simplify_path();
			}
			add_autoload(autoload);
		} else if (p_name.string().begins_with("global_group/")) {
			String group_name = p_name.string().get_slicec('/', 1);
			add_global_group(group_name, p_value);
		}
	}

	_version++;
	_queue_changed(p_name);
	return true;
}

bool ProjectSettings::_get(const StringName &p_name, Variant &r_ret) const {
	_THREAD_SAFE_METHOD_

	if (!props.has(p_name)) {
		return false;
	}
	r_ret = props[p_name].variant;
	return true;
}

Variant ProjectSettings::get_setting_with_override_and_custom_features(const StringName &p_name, const Vector<String> &p_features) const {
	_THREAD_SAFE_METHOD_

	StringName name = p_name;
	if (feature_overrides.has(name)) {
		const LocalVector<Pair<StringName, StringName>> &overrides = feature_overrides[name];
		for (uint32_t i = 0; i < overrides.size(); i++) {
			if (p_features.has(String(overrides[i].first).to_lower())) {
				if (props.has(overrides[i].second)) {
					name = overrides[i].second;
					break;
				}
			}
		}
	}

	if (!props.has(name)) {
		WARN_PRINT("Property not found: " + String(name));
		return Variant();
	}
	return props[name].variant;
}

Variant ProjectSettings::get_setting_with_override(const StringName &p_name) const {
	_THREAD_SAFE_METHOD_

	const LocalVector<Pair<StringName, StringName>> *overrides = feature_overrides.getptr(p_name);
	if (overrides) {
		for (uint32_t i = 0; i < overrides->size(); i++) {
			if (!OS::get_singleton()->has_feature((*overrides)[i].first)) {
				continue;
			}

			// Custom features are checked in OS.has_feature() already. No need to check twice.
			const RBMap<StringName, VariantContainer>::Element *override_prop = props.find((*overrides)[i].second);
			if (override_prop) {
				return override_prop->get().variant;
			}
		}
	}

	const RBMap<StringName, VariantContainer>::Element *prop = props.find(p_name);
	if (!prop) {
		WARN_PRINT(vformat("Property not found: '%s'.", p_name));
		return Variant();
	}

	return prop->get().variant;
}

struct _VCSort {
	String name;
	Variant::Type type = Variant::VARIANT_MAX;
	int order = 0;
	uint32_t flags = 0;

	bool operator<(const _VCSort &p_vcs) const { return order == p_vcs.order ? name < p_vcs.name : order < p_vcs.order; }
};

void ProjectSettings::_get_property_list(List<PropertyInfo> *p_list) const {
	_THREAD_SAFE_METHOD_

	RBSet<_VCSort> vclist;
	HashMap<String, LocalVector<_VCSort>> setting_overrides;

	for (const KeyValue<StringName, VariantContainer> &E : props) {
		const VariantContainer *v = &E.value;

		if (v->hide_from_editor) {
			continue;
		}

		_VCSort vc;
		vc.name = E.key;
		vc.order = v->order;
		vc.type = v->variant.get_type();

		bool internal = v->internal;
		if (!internal) {
			for (const String &F : hidden_prefixes) {
				if (vc.name.begins_with(F)) {
					internal = true;
					break;
				}
			}
		}

		if (internal) {
			vc.flags = PROPERTY_USAGE_STORAGE;
		} else {
			vc.flags = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE;
		}

		if (v->internal) {
			vc.flags |= PROPERTY_USAGE_INTERNAL;
		}

		if (v->basic) {
			vc.flags |= PROPERTY_USAGE_EDITOR_BASIC_SETTING;
		}

		if (v->restart_if_changed) {
			vc.flags |= PROPERTY_USAGE_RESTART_IF_CHANGED;
		}

		int dot = vc.name.rfind_char('.');
		if (dot != -1) {
			StringName n = vc.name.substr(0, dot);
			if (props.has(n)) {
				// Property is an override.
				setting_overrides[n].push_back(vc);
			} else {
				vclist.insert(vc);
			}
		} else {
			vclist.insert(vc);
		}
	}

	for (const _VCSort &base : vclist) {
		if (custom_prop_info.has(base.name)) {
			PropertyInfo pi = custom_prop_info[base.name];
			pi.name = base.name;
			pi.usage = base.flags;
			p_list->push_back(pi);
#ifdef TOOLS_ENABLED
		} else if (base.name.begins_with(EDITOR_SETTING_OVERRIDE_PREFIX)) {
			PropertyInfo info(base.type, base.name, PROPERTY_HINT_NONE, "", base.flags);

			const PropertyInfo *pi = editor_settings_info.getptr(base.name.trim_prefix(EDITOR_SETTING_OVERRIDE_PREFIX));
			if (pi) {
				info.usage = pi->usage;
				info.hint = pi->hint;
				info.hint_string = pi->hint_string;
			}
			p_list->push_back(info);
#endif
		} else {
			p_list->push_back(PropertyInfo(base.type, base.name, PROPERTY_HINT_NONE, "", base.flags));
		}

		if (setting_overrides.has(base.name)) {
			for (const _VCSort &over : setting_overrides.get(base.name)) {
				if (custom_prop_info.has(over.name)) {
					PropertyInfo pi = custom_prop_info[over.name];
					pi.name = over.name;
					pi.usage = over.flags;
					p_list->push_back(pi);
				} else if (custom_prop_info.has(base.name)) {
					// Fallback to base property info.
					PropertyInfo pi = custom_prop_info[base.name];
					pi.name = over.name;
					pi.usage = over.flags;
					p_list->push_back(pi);
				} else {
					p_list->push_back(PropertyInfo(over.type, over.name, PROPERTY_HINT_NONE, "", over.flags));
				}
			}
		}
	}
}

void ProjectSettings::_queue_changed(const StringName &p_name) {
	changed_settings.insert(p_name);

	if (!MessageQueue::get_singleton() || MessageQueue::get_singleton()->get_max_buffer_usage() == 0) {
		return;
	}

	// Only queue the deferred call once per frame.
	if (!is_changed) {
		is_changed = true;
		callable_mp(this, &ProjectSettings::_emit_changed).call_deferred();
	}
}

void ProjectSettings::_emit_changed() {
	if (!is_changed) {
		return;
	}
	is_changed = false;

	// Emit the general settings_changed signal to indicate changes are complete.
	emit_signal("settings_changed");

	// Clear the changed settings after emitting the signal
	changed_settings.clear();
}

bool ProjectSettings::load_resource_pack(const String &p_pack, bool p_replace_files, int p_offset) {
	return ProjectSettings::_load_resource_pack(p_pack, p_replace_files, p_offset, false);
}

bool ProjectSettings::_load_resource_pack(const String &p_pack, bool p_replace_files, int p_offset, bool p_main_pack) {
	if (PackedData::get_singleton()->is_disabled()) {
		return false;
	}

	if (p_pack == "res://") {
		// Loading the resource directory as a pack source is reserved for internal use only.
		return false;
	}

	if (!p_main_pack && !using_datapack && !OS::get_singleton()->get_resource_dir().is_empty()) {
		// Add the project's resource file system to PackedData so directory access keeps working when
		// the game is running without a main pack, like in the editor or on Android.
		PackedData::get_singleton()->add_pack_source(memnew(PackedSourceDirectory));
		PackedData::get_singleton()->add_pack("res://", false, 0);
		DirAccess::make_default<DirAccessPack>(DirAccess::ACCESS_RESOURCES);
		using_datapack = true;
	}

	bool ok = PackedData::get_singleton()->add_pack(p_pack, p_replace_files, p_offset) == OK;
	if (!ok) {
		return false;
	}

	if (project_loaded) {
		// This pack may have declared new global classes (make sure they are picked up).
		refresh_global_class_list();

		// This pack may have defined new UIDs, make sure they are cached.
		ResourceUID::get_singleton()->load_from_cache(false);
	}

	// If the data pack was found, all directory access will be from here.
	if (!using_datapack) {
		DirAccess::make_default<DirAccessPack>(DirAccess::ACCESS_RESOURCES);
		using_datapack = true;
	}

	return true;
}

void ProjectSettings::_convert_to_last_version(int p_from_version) {
#ifndef DISABLE_DEPRECATED
	if (p_from_version <= 3) {
		// Converts the actions from array to dictionary (array of events to dictionary with deadzone + events)
		for (KeyValue<StringName, ProjectSettings::VariantContainer> &E : props) {
			Variant value = E.value.variant;
			if (String(E.key).begins_with("input/") && value.get_type() == Variant::ARRAY) {
				Array array = value;
				Dictionary action;
				action["deadzone"] = Variant(0.5f);
				action["events"] = array;
				E.value.variant = action;
			}
		}
	} else if (p_from_version <= 6) {
		// Check if we still have legacy boot splash (removed in 4.6), map it to new project setting, then remove legacy setting.
		if (has_setting("application/boot_splash/fullsize")) {
			// See RenderingServerEnums::SplashStretchMode.
			set_setting("application/boot_splash/stretch_mode", get_setting("application/boot_splash/fullsize") ? 1 : 0);
			set_setting("application/boot_splash/fullsize", Variant());
		}
	}
	// Automatically adds overrides for project settings that were changed to editor settings.
	_handle_editor_setting_compat("editor/script/search_in_file_extensions", "text_editor/behavior/general/find_in_file_extensions");
#endif // DISABLE_DEPRECATED
}

#ifndef DISABLE_DEPRECATED
void ProjectSettings::_handle_editor_setting_compat(const String &p_original_setting, const String &p_new_setting) {
	ProjectSettings *ps = ProjectSettings::get_singleton();
	if (ps->has_setting(p_original_setting)) {
		ps->set_editor_setting_override(p_new_setting, ps->get_setting(p_original_setting));
		ps->set_setting(p_original_setting, Variant());
	}
}
#endif

/*
 * This method is responsible for loading a project.godot file and/or data file
 * using the following merit order:
 *  - If using NetworkClient, try to lookup project file or fail.
 *  - If --main-pack was passed by the user (`p_main_pack`), load it or fail.
 *  - Search for project PCKs automatically. For each step we try loading a potential
 *    PCK, and if it doesn't work, we proceed to the next step. If any step succeeds,
 *    we try loading the project settings, and abort if it fails. Steps:
 *    o Bundled PCK in the executable.
 *    o [macOS only] PCK with same basename as the binary in the .app resource dir.
 *    o PCK with same basename as the binary in the binary's directory. We handle both
 *      changing the extension to '.pck' (e.g. 'win_game.exe' -> 'win_game.pck') and
 *      appending '.pck' to the binary name (e.g. 'linux_game' -> 'linux_game.pck').
 *    o PCK with the same basename as the binary in the current working directory.
 *      Same as above for the two possible PCK file names.
 *  - On Android, look for 'assets.sparsepck' and try loading it, if it doesn't work,
 *    proceed to the next step.
 *  - On relevant platforms (Android/iOS), lookup project file in OS resource path.
 *    If found, load it or fail.
 *  - Lookup project file in passed `p_path` (--path passed by the user), i.e. we
 *    are running from source code.
 *    If not found and `p_upwards` is true, look for project files in parent folders
 *    up to the system root (used to run a game from command line while in a subfolder).
 *    If a project file is found, load it or fail.
 *    If nothing was found, error out.
 */
Error ProjectSettings::_setup(const String &p_path, const String &p_main_pack, bool p_upwards, bool p_ignore_override) {
	if (!OS::get_singleton()->get_resource_dir().is_empty()) {
		// OS will call ProjectSettings->get_resource_path which will be empty if not overridden!
		// If the OS would rather use a specific location, then it will not be empty.
		resource_path = OS::get_singleton()->get_resource_dir().replace_char('\\', '/');
		if (!resource_path.is_empty() && resource_path[resource_path.length() - 1] == '/') {
			resource_path = resource_path.substr(0, resource_path.length() - 1); // Chop end.
		}
	}

	// Attempt with a user-defined main pack first

	if (!p_main_pack.is_empty()) {
		bool ok = _load_resource_pack(p_main_pack, false, 0, true);
		ERR_FAIL_COND_V_MSG(!ok, ERR_CANT_OPEN, vformat("Cannot open resource pack '%s'.", p_main_pack));

		Error err = _load_settings_text_or_binary("res://project.godot", "res://project.binary");
#ifdef OVERRIDE_ENABLED
		if (err == OK && !p_ignore_override) {
			// Load override from location of the main pack
			// Optional, we don't mind if it fails
			bool disable_override = GLOBAL_GET("application/config/disable_project_settings_override");
			if (!disable_override) {
				_load_settings_text(p_main_pack.get_base_dir().path_join("override.cfg"));
			}
		}
#endif // OVERRIDE_ENABLED
		return err;
	}

	String exec_path = OS::get_singleton()->get_executable_path();

	if (!exec_path.is_empty()) {
		// We do several tests sequentially until one succeeds to find a PCK,
		// and if so, we attempt loading it at the end.

		// Attempt with PCK bundled into executable.
		bool found = _load_resource_pack(exec_path, false, 0, true);

		// Attempt with exec_name.pck.
		// (This is the usual case when distributing a Godot game.)
		String exec_dir = exec_path.get_base_dir();
		String exec_filename = exec_path.get_file();
		String exec_basename = exec_filename.get_basename();

		// Based on the OS, it can be the exec path + '.pck' (Linux w/o extension, macOS in .app bundle)
		// or the exec path's basename + '.pck' (Windows).
		// We need to test both possibilities as extensions for Linux binaries are optional
		// (so both 'mygame.bin' and 'mygame' should be able to find 'mygame.pck').

#if defined(MACOS_ENABLED) || defined(APPLE_EMBEDDED_ENABLED)
		if (!found) {
			// Attempt to load PCK from macOS .app bundle resources.
			found = _load_resource_pack(OS::get_singleton()->get_bundle_resource_dir().path_join(exec_basename + ".pck"), false, 0, true) || _load_resource_pack(OS::get_singleton()->get_bundle_resource_dir().path_join(exec_filename + ".pck"), false, 0, true);
		}
#endif

		if (!found) {
			// Try to load data pack at the location of the executable.
			// As mentioned above, we have two potential names to attempt.
			found = _load_resource_pack(exec_dir.path_join(exec_basename + ".pck"), false, 0, true) || _load_resource_pack(exec_dir.path_join(exec_filename + ".pck"), false, 0, true);
		}

		if (!found) {
			// If we couldn't find them next to the executable, we attempt
			// the current working directory. Same story, two tests.
			found = _load_resource_pack(exec_basename + ".pck", false, 0, true) || _load_resource_pack(exec_filename + ".pck", false, 0, true);
		}

		// If we opened our package, try and load our project.
		if (found) {
			Error err = _load_settings_text_or_binary("res://project.godot", "res://project.binary");
#ifdef OVERRIDE_ENABLED
			if (err == OK && !p_ignore_override) {
				// Load overrides from the PCK and the executable location.
				// Optional, we don't mind if either fails.
				bool disable_override = GLOBAL_GET("application/config/disable_project_settings_override");
				if (!disable_override) {
					_load_settings_text("res://override.cfg");
					_load_settings_text(exec_path.get_base_dir().path_join("override.cfg"));
				}
			}
#endif // OVERRIDE_ENABLED
			return err;
		}
	}

#ifdef ANDROID_ENABLED
	// Attempt to load sparse PCK assets.
	_load_resource_pack("res://assets.sparsepck", false, 0, true);
#endif

	// Try to use the filesystem for files, according to OS.
	// (Only Android -when reading from PCK-.)

	if (!OS::get_singleton()->get_resource_dir().is_empty()) {
		Error err = _load_settings_text_or_binary("res://project.godot", "res://project.binary");
#ifdef OVERRIDE_ENABLED
		if (err == OK && !p_ignore_override) {
			// Optional, we don't mind if it fails.
			bool disable_override = GLOBAL_GET("application/config/disable_project_settings_override");
			if (!disable_override) {
				_load_settings_text("res://override.cfg");
			}
		}
#endif // OVERRIDE_ENABLED
		return err;
	}

#if defined(MACOS_ENABLED) || defined(APPLE_EMBEDDED_ENABLED)
	// Attempt to load project file from macOS .app bundle resources.
	resource_path = OS::get_singleton()->get_bundle_resource_dir();
	if (!resource_path.is_empty()) {
		if (resource_path[resource_path.length() - 1] == '/') {
			resource_path = resource_path.substr(0, resource_path.length() - 1); // Chop end.
		}
		Ref<DirAccess> d = DirAccess::create(DirAccess::ACCESS_FILESYSTEM);
		ERR_FAIL_COND_V_MSG(d.is_null(), ERR_CANT_CREATE, vformat("Cannot create DirAccess for path '%s'.", resource_path));
		d->change_dir(resource_path);

		Error err;

		err = _load_settings_text_or_binary(resource_path.path_join("project.godot"), resource_path.path_join("project.binary"));
		if (err == OK && !p_ignore_override) {
			// Optional, we don't mind if it fails.
#ifdef OVERRIDE_ENABLED
			bool disable_override = GLOBAL_GET("application/config/disable_project_settings_override");
			if (!disable_override) {
				_load_settings_text(resource_path.path_join("override.cfg"));
			}
#endif // OVERRIDE_ENABLED
			return err;
		}
	}
#endif // MACOS_ENABLED

	// Nothing was found, try to find a project file in provided path (`p_path`)
	// or, if requested (`p_upwards`) in parent directories.

	Ref<DirAccess> d = DirAccess::create(DirAccess::ACCESS_FILESYSTEM);
	ERR_FAIL_COND_V_MSG(d.is_null(), ERR_CANT_CREATE, vformat("Cannot create DirAccess for path '%s'.", p_path));
	d->change_dir(p_path);

	String current_dir = d->get_current_dir();
	bool found = false;
	Error err;

	while (true) {
		// Set the resource path early so things can be resolved when loading.
		resource_path = current_dir;
		resource_path = resource_path.replace_char('\\', '/'); // Windows path to Unix path just in case.
		err = _load_settings_text_or_binary(current_dir.path_join("project.godot"), current_dir.path_join("project.binary"));
		if (err == OK) {
#ifdef OVERRIDE_ENABLED
			if (!p_ignore_override) {
				// Optional, we don't mind if it fails.
				bool disable_override = GLOBAL_GET("application/config/disable_project_settings_override");
				if (!disable_override) {
					_load_settings_text(current_dir.path_join("override.cfg"));
				}
			}
#endif // OVERRIDE_ENABLED
			found = true;
			break;
		}

#if defined(OVERRIDE_PATH_ENABLED)
		if (p_upwards) {
			// Try to load settings ascending through parent directories
			d->change_dir("..");
			if (d->get_current_dir() == current_dir) {
				break; // not doing anything useful
			}
			current_dir = d->get_current_dir();
		} else {
#else
		{
#endif
			break;
		}
	}

	if (!found) {
		return err;
	}

	if (resource_path.length() && resource_path[resource_path.length() - 1] == '/') {
		resource_path = resource_path.substr(0, resource_path.length() - 1); // Chop end.
	}

	return OK;
}

Error ProjectSettings::setup(const String &p_path, const String &p_main_pack, bool p_upwards, bool p_ignore_override) {
	Error err = _setup(p_path, p_main_pack, p_upwards, p_ignore_override);
#ifdef OVERRIDE_ENABLED
	if (err == OK && !p_ignore_override) {
		bool disable_override = GLOBAL_GET("application/config/disable_project_settings_override");
		if (!disable_override) {
			String custom_settings = GLOBAL_GET("application/config/project_settings_override");
			if (!custom_settings.is_empty()) {
				_load_settings_text(custom_settings);
			}
		}
	}
#endif

	// Updating the default value after the project settings have loaded.
	bool use_hidden_directory = GLOBAL_GET("application/config/use_hidden_project_data_directory");
	project_data_dir_name = (use_hidden_directory ? "." : "") + PROJECT_DATA_DIR_NAME_SUFFIX;

	// Using GLOBAL_GET on every block for compressing can be slow, so assigning here.
	Compression::zstd_long_distance_matching = GLOBAL_GET("compression/formats/zstd/long_distance_matching");
	Compression::zstd_level = GLOBAL_GET("compression/formats/zstd/compression_level");
	Compression::zstd_window_log_size = GLOBAL_GET("compression/formats/zstd/window_log_size");

	Compression::zlib_level = GLOBAL_GET("compression/formats/zlib/compression_level");

	Compression::gzip_level = GLOBAL_GET("compression/formats/gzip/compression_level");

	load_scene_groups_cache();

	project_loaded = err == OK;
	return err;
}

bool ProjectSettings::has_setting(const String &p_var) const {
	_THREAD_SAFE_METHOD_

	return props.has(p_var);
}

Error ProjectSettings::_load_settings_binary(const String &p_path) {
	Error err;
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::READ, &err);
	if (err != OK) {
		return err;
	}

	uint8_t hdr[4];
	f->get_buffer(hdr, 4);
	ERR_FAIL_COND_V_MSG((hdr[0] != 'E' || hdr[1] != 'C' || hdr[2] != 'F' || hdr[3] != 'G'), ERR_FILE_CORRUPT, "Corrupted header in binary project.binary (not ECFG).");

	uint32_t count = f->get_32();

	for (uint32_t i = 0; i < count; i++) {
		uint32_t slen = f->get_32();
		CharString cs;
		cs.resize_uninitialized(slen + 1);
		cs[slen] = 0;
		f->get_buffer((uint8_t *)cs.ptr(), slen);
		String key = String::utf8(cs.ptr(), slen);

		uint32_t vlen = f->get_32();
		Vector<uint8_t> d;
		d.resize(vlen);
		f->get_buffer(d.ptrw(), vlen);
		Variant value;
		err = decode_variant(value, d.ptr(), d.size(), nullptr, true);
		ERR_CONTINUE_MSG(err != OK, vformat("Error decoding property: '%s'.", key));
		set(key, value);
	}

	return OK;
}

Error ProjectSettings::_load_settings_text(const String &p_path) {
	Error err;
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::READ, &err);

	if (f.is_null()) {
		// FIXME: Above 'err' error code is ERR_FILE_CANT_OPEN if the file is missing
		// This needs to be streamlined if we want decent error reporting
		return ERR_FILE_NOT_FOUND;
	}

	VariantParser::StreamFile stream;
	stream.f = f;

	String assign;
	Variant value;
	VariantParser::Tag next_tag;

	int lines = 0;
	String error_text;
	String section;
	int config_version = 0;

	while (true) {
		assign = Variant();
		next_tag.fields.clear();
		next_tag.name = String();

		err = VariantParser::parse_tag_assign_eof(&stream, lines, error_text, next_tag, assign, value, nullptr, true);
		if (err == ERR_FILE_EOF) {
			// If we're loading a project.godot from source code, we can operate some
			// ProjectSettings conversions if need be.
			_convert_to_last_version(config_version);
			last_save_time = FileAccess::get_modified_time(get_resource_path().path_join("project.godot"));
			return OK;
		}
		ERR_FAIL_COND_V_MSG(err != OK, err, vformat("Error parsing '%s' at line %d: %s File might be corrupted.", p_path, lines, error_text));

		if (!assign.is_empty()) {
			if (section.is_empty() && assign == "config_version") {
				config_version = value;
				ERR_FAIL_COND_V_MSG(config_version > CONFIG_VERSION, ERR_FILE_CANT_OPEN, vformat("Can't open project at '%s', its `config_version` (%d) is from a more recent and incompatible version of the engine. Expected config version: %d.", p_path, config_version, CONFIG_VERSION));
			} else {
				if (section.is_empty()) {
					set(assign, value);
				} else {
					set(section + "/" + assign, value);
				}
			}
		} else if (!next_tag.name.is_empty()) {
			section = next_tag.name;
		}
	}
}

Error ProjectSettings::_load_settings_text_or_binary(const String &p_text_path, const String &p_bin_path) {
	// Attempt first to load the binary project.godot file.
	Error err = _load_settings_binary(p_bin_path);
	if (err == OK) {
		return OK;
	} else if (err != ERR_FILE_NOT_FOUND) {
		// If the file exists but can't be loaded, we want to know it.
		ERR_PRINT(vformat("Couldn't load file '%s', error code %d.", p_bin_path, err));
	}

	// Fallback to text-based project.godot file if binary was not found.
	err = _load_settings_text(p_text_path);
	if (err == OK) {
#ifndef DISABLE_DEPRECATED
		const PackedStringArray features = get_setting("application/config/features");
		for (const String &feat : features) {
			if (feat.contains_char('.') && feat.get_slice_count(".") == 2) {
				int major_version = feat.get_slicec('.', 0).to_int();
				int minor_version = feat.get_slicec('.', 1).to_int();
				// Major version is irrelevant, but the extra check ensures that the feature is in fact a version string.
				if (major_version == 4 && minor_version < 6) {
					// Enable MeshInstance3D compat for projects created before 4.6.
					set_setting("animation/compatibility/default_parent_skeleton_in_mesh_instance_3d", true);
				}
				break;
			}
		}
#endif
		return OK;
	} else if (err != ERR_FILE_NOT_FOUND) {
		ERR_PRINT(vformat("Couldn't load file '%s', error code %d.", p_text_path, err));
	}

	return err;
}

Error ProjectSettings::load_custom(const String &p_path) {
	if (p_path.ends_with(".binary")) {
		return _load_settings_binary(p_path);
	}
	return _load_settings_text(p_path);
}

int ProjectSettings::get_order(const String &p_name) const {
	ERR_FAIL_COND_V_MSG(!props.has(p_name), -1, vformat("Request for nonexistent project setting: '%s'.", p_name));
	return props[p_name].order;
}

void ProjectSettings::set_order(const String &p_name, int p_order) {
	ERR_FAIL_COND_MSG(!props.has(p_name), vformat("Request for nonexistent project setting: '%s'.", p_name));
	props[p_name].order = p_order;
}

void ProjectSettings::set_builtin_order(const String &p_name) {
	ERR_FAIL_COND_MSG(!props.has(p_name), vformat("Request for nonexistent project setting: '%s'.", p_name));
	if (props[p_name].order >= NO_BUILTIN_ORDER_BASE) {
		props[p_name].order = last_builtin_order++;
	}
}

bool ProjectSettings::is_builtin_setting(const String &p_name) const {
	// Return true because a false negative is worse than a false positive.
	ERR_FAIL_COND_V_MSG(!props.has(p_name), true, vformat("Request for nonexistent project setting: '%s'.", p_name));
	return props[p_name].order < NO_BUILTIN_ORDER_BASE;
}

void ProjectSettings::clear(const String &p_name) {
	ERR_FAIL_COND_MSG(!props.has(p_name), vformat("Request for nonexistent project setting: '%s'.", p_name));
	props.erase(p_name);
	_queue_changed(p_name);
}

Error ProjectSettings::save() {
	Error error = save_custom(get_resource_path().path_join("project.godot"));
	if (error == OK) {
		last_save_time = FileAccess::get_modified_time(get_resource_path().path_join("project.godot"));
	}
	return error;
}

Error ProjectSettings::_save_settings_binary(const String &p_file, const RBMap<String, List<String>> &p_props, const CustomMap &p_custom, const String &p_custom_features) {
	Error err;
	Ref<FileAccess> file = FileAccess::open(p_file, FileAccess::WRITE, &err);
	ERR_FAIL_COND_V_MSG(err != OK, err, vformat("Couldn't save project.binary at '%s'.", p_file));

	uint8_t hdr[4] = { 'E', 'C', 'F', 'G' };
	file->store_buffer(hdr, 4);

	int count = 0;

	for (const KeyValue<String, List<String>> &E : p_props) {
		count += E.value.size();
	}

	if (!p_custom_features.is_empty()) {
		// Store how many properties are saved, add one for custom features, which must always go first.
		file->store_32(uint32_t(count + 1));
		String key = CoreStringName(_custom_features);
		file->store_pascal_string(key);

		int len;
		err = encode_variant(p_custom_features, nullptr, len, false);
		ERR_FAIL_COND_V(err != OK, err);

		Vector<uint8_t> buff;
		buff.resize(len);

		err = encode_variant(p_custom_features, buff.ptrw(), len, false);
		ERR_FAIL_COND_V(err != OK, err);
		file->store_32(uint32_t(len));
		file->store_buffer(buff.ptr(), buff.size());

	} else {
		// Store how many properties are saved.
		file->store_32(uint32_t(count));
	}

	for (const KeyValue<String, List<String>> &E : p_props) {
		for (const String &key : E.value) {
			String k = key;
			if (!E.key.is_empty()) {
				k = E.key + "/" + k;
			}
			Variant value;
			if (p_custom.has(k)) {
				value = p_custom[k];
			} else {
				value = get(k);
			}

			file->store_pascal_string(k);

			int len;
			err = encode_variant(value, nullptr, len, true);
			ERR_FAIL_COND_V_MSG(err != OK, ERR_INVALID_DATA, "Error when trying to encode Variant.");

			Vector<uint8_t> buff;
			buff.resize(len);

			err = encode_variant(value, buff.ptrw(), len, true);
			ERR_FAIL_COND_V_MSG(err != OK, ERR_INVALID_DATA, "Error when trying to encode Variant.");
			file->store_32(uint32_t(len));
			file->store_buffer(buff.ptr(), buff.size());
		}
	}

	return OK;
}

Error ProjectSettings::_save_settings_text(const String &p_file, const RBMap<String, List<String>> &p_props, const CustomMap &p_custom, const String &p_custom_features) {
	Error err;
	Ref<FileAccess> file = FileAccess::open(p_file, FileAccess::WRITE, &err);

	ERR_FAIL_COND_V_MSG(err != OK, err, vformat("Couldn't save project.godot - %s.", p_file));

	file->store_line("; Engine configuration file.");
	file->store_line("; It's best edited using the editor UI and not directly,");
	file->store_line("; since the parameters that go here are not all obvious.");
	file->store_line(";");
	file->store_line("; Format:");
	file->store_line(";   [section] ; section goes between []");
	file->store_line(";   param=value ; assign values to parameters");
	file->store_line("");

	file->store_string("config_version=" + itos(CONFIG_VERSION) + "\n");
	if (!p_custom_features.is_empty()) {
		file->store_string("custom_features=\"" + p_custom_features + "\"\n");
	}
	file->store_string("\n");

	for (const KeyValue<String, List<String>> &E : p_props) {
		if (E.key != p_props.begin()->key) {
			file->store_string("\n");
		}

		if (!E.key.is_empty()) {
			file->store_string("[" + E.key + "]\n\n");
		}
		for (const String &F : E.value) {
			String key = F;
			if (!E.key.is_empty()) {
				key = E.key + "/" + key;
			}
			Variant value;
			if (p_custom.has(key)) {
				value = p_custom[key];
			} else {
				value = get(key);
			}

			String vstr;
			VariantWriter::write_to_string(value, vstr, true);
			file->store_string(F.property_name_encode() + "=" + vstr + "\n");
		}
	}

	return OK;
}

Error ProjectSettings::_save_custom_bnd(const String &p_file) { // add other params as dictionary and array?
	return save_custom(p_file);
}

#ifdef TOOLS_ENABLED
bool _csproj_exists(const String &p_root_dir) {
	Ref<DirAccess> dir = DirAccess::open(p_root_dir);
	ERR_FAIL_COND_V(dir.is_null(), false);

	dir->list_dir_begin();
	String file_name = dir->_get_next();
	while (file_name != "") {
		if (!dir->current_is_dir() && file_name.get_extension() == "csproj") {
			return true;
		}
		file_name = dir->_get_next();
	}

	return false;
}
#endif // TOOLS_ENABLED

// TASK-067 (patch 3): the "which settings would a save write, grouped by
// section" half of the whole-file writer, moved here unchanged so that
// `save_preserving_text()` publishes **exactly** the set `save()` would publish.
// Splitting it out is a pure extraction - every line below was already in
// `save_custom()`, in the same order, with the same `_VCSort` ordering.
Error ProjectSettings::_collect_settings_for_save(const CustomMap &p_custom, bool p_merge_with_current, const Vector<String> &p_custom_features, RBMap<String, List<String>> &r_props, String &r_features) {
#ifdef TOOLS_ENABLED
	PackedStringArray project_features = get_setting("application/config/features");
	// If there is no feature list currently present, force one to generate.
	if (project_features.is_empty()) {
		project_features = ProjectSettings::get_required_features();
	}
	// Check the rendering API.
	const String rendering_api = has_setting("rendering/renderer/rendering_method") ? (String)get_setting("rendering/renderer/rendering_method") : String();
	if (!rendering_api.is_empty()) {
		// Add the rendering API as a project feature if it doesn't already exist.
		if (!project_features.has(rendering_api)) {
			project_features.append(rendering_api);
		}
	}
	// Check for the existence of a csproj file.
	if (_csproj_exists(get_resource_path())) {
		// If there is a csproj file, add the C# feature if it doesn't already exist.
		if (!project_features.has("C#")) {
			project_features.append("C#");
		}
	} else {
		// If there isn't a csproj file, remove the C# feature if it exists.
		if (project_features.has("C#")) {
			project_features.remove_at(project_features.find("C#"));
		}
	}
	project_features = _trim_to_supported_features(project_features);
	set_setting("application/config/features", project_features);
#endif // TOOLS_ENABLED

	RBSet<_VCSort> vclist;

	if (p_merge_with_current) {
		for (const KeyValue<StringName, VariantContainer> &G : props) {
			const VariantContainer *v = &G.value;

			if (v->hide_from_editor) {
				continue;
			}

			if (p_custom.has(G.key)) {
				continue;
			}

			_VCSort vc;
			vc.name = G.key; //*k;
			vc.order = v->order;
			vc.type = v->variant.get_type();
			vc.flags = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE;
			if (v->variant == v->initial) {
				continue;
			}

			vclist.insert(vc);
		}
	}

	for (const KeyValue<String, Variant> &E : p_custom) {
		// Lookup global prop to store in the same order
		RBMap<StringName, VariantContainer>::Iterator global_prop = props.find(E.key);

		_VCSort vc;
		vc.name = E.key;
		vc.order = global_prop ? global_prop->value.order : 0xFFFFFFF;
		vc.type = E.value.get_type();
		vc.flags = PROPERTY_USAGE_STORAGE;
		vclist.insert(vc);
	}

	RBMap<String, List<String>> save_props;

	for (const _VCSort &E : vclist) {
		String category = E.name;
		String name = E.name;

		int div = category.find_char('/');

		if (div < 0) {
			category = "";
		} else {
			category = category.substr(0, div);
			name = name.substr(div + 1);
		}
		save_props[category].push_back(name);
	}

	String save_features;

	for (int i = 0; i < p_custom_features.size(); i++) {
		if (i > 0) {
			save_features += ",";
		}

		String f = p_custom_features[i].strip_edges().remove_char('\"');
		save_features += f;
	}

	r_props = save_props;
	r_features = save_features;
	return OK;
}

Error ProjectSettings::save_custom(const String &p_path, const CustomMap &p_custom, const Vector<String> &p_custom_features, bool p_merge_with_current) {
	ERR_FAIL_COND_V_MSG(p_path.is_empty(), ERR_INVALID_PARAMETER, "Project settings save path cannot be empty.");

	// TASK-067 (patch 3): the collection is shared with `save_preserving_text()`
	// so the whole-file writer and the per-section publisher cannot publish
	// different sets.
	RBMap<String, List<String>> save_props;
	String save_features;
	const Error collect_error = _collect_settings_for_save(p_custom, p_merge_with_current, p_custom_features, save_props, save_features);
	if (collect_error != OK) {
		return collect_error;
	}

	if (p_path.ends_with(".godot") || p_path.ends_with("override.cfg")) {
		return _save_settings_text(p_path, save_props, p_custom, save_features);
	} else if (p_path.ends_with(".binary")) {
		return _save_settings_binary(p_path, save_props, p_custom, save_features);
	} else {
		ERR_FAIL_V_MSG(ERR_FILE_UNRECOGNIZED, vformat("Unknown config file format: '%s'.", p_path));
	}
}

// ---------------------------------------------------------------------------
// Section-granular publish (TASK-057 patch 2).
//
// The whole-file writer above cannot be used when the caller must keep the rest
// of the file: `_save_settings_text()` writes seven header comment lines plus
// every stored setting, so anything a human typed into `project.godot` that the
// engine did not produce - a comment, a blank line, the key order, a section the
// engine does not know about - is gone after one call. This is not a theory:
// TASK-042 / TASK-043 measured it for `project_set_setting` and five tool
// descriptions in modules/mcp_server now say so.
//
// Doing it in the caller instead was tried and rejected: the natural splice
// ("write the new line right after the `[input]` header") silently puts the key
// into the WRONG section when `[input]` is not the last section of the file,
// because the engine's reader (VariantParser -> ConfigFile::_parse) attributes
// every assignment to the section header that preceded it. The failure is
// silent: the file parses, the key is simply not where the writer thought.
//
// So the text work lives here, next to the serializer it has to agree with.
// ---------------------------------------------------------------------------

namespace {

// One statement of the file: a blank line, a comment, a section header, or an
// assignment. Only an assignment carries key and value spans.
//
// Why this is not line based (it was, and that was a real defect): the engine's
// own serializer writes a non-empty `Dictionary` as SEVERAL lines
//
//     jump={
//     "deadzone": 0.5,
//     "events": []
//     }
//
// (`variant_parser.cpp:2187-2201`, and the input actions of every real
// project.godot look like this). A line-based scanner reads `jump={` as a
// complete assignment whose value is `{`; the next call then sees a different
// value, rewrites that one line and leaves the dictionary's remaining lines
// behind - the file ends up with the body of the value twice. The scanner below
// therefore finds the VALUE SPAN by walking the characters: it tracks brace,
// bracket and parenthesis depth and whether it is inside a string, and the value
// ends at the first newline seen at depth zero outside a string.
struct _PSStatement {
	int begin = 0; // First character of the statement's first line.
	int end = 0; // One past the statement's last line terminator.
	int key_begin = -1; // Assignment only; the key's first character.
	int key_end = -1; // Assignment only; one past the key's last character.
	int value_begin = -1; // Assignment only; the value's first character.
	int value_end = -1; // Assignment only; one past the value's last character.
	String key; // The decoded name of an assignment, empty otherwise.
	String header; // The section an assignment belongs to the header of.
	String terminator; // The line ending that closes the statement, or "".
	bool is_blank = false;
	bool is_comment = false;

	bool is_assignment() const { return key_begin >= 0; }
};

String _ps_terminator_at(const String &p_text, int p_newline) {
	return (p_newline > 0 && p_text[p_newline - 1] == '\r') ? String("\r\n") : String("\n");
}

// The name a key was written under. `_save_settings_text()` writes names through
// `String::property_name_encode()`, which quotes anything containing `=`, `"`,
// `;`, `[`, `]`, a space or a non-ASCII character, so a quoted key has to be
// unescaped before it can be compared with the setting name.
String _ps_decode_key(const String &p_key) {
	if (p_key.length() >= 2 && p_key[0] == '"' && p_key[p_key.length() - 1] == '"') {
		return p_key.substr(1, p_key.length() - 2).c_unescape();
	}
	return p_key;
}

Vector<_PSStatement> _ps_scan(const String &p_text) {
	const int length = p_text.length();
	Vector<_PSStatement> statements;

	int i = 0;
	while (i < length) {
		_PSStatement statement;
		statement.begin = i;

		int first = i;
		while (first < length && (p_text[first] == ' ' || p_text[first] == '\t')) {
			first++;
		}

		int line_end = first;
		while (line_end < length && p_text[line_end] != '\n') {
			line_end++;
		}
		const bool has_newline = line_end < length;
		const String line_terminator = has_newline ? _ps_terminator_at(p_text, line_end) : String();
		const bool line_is_empty = (first >= length) || p_text[first] == '\n' || p_text[first] == '\r';

		if (line_is_empty || p_text[first] == ';' || p_text[first] == '#') {
			statement.is_blank = line_is_empty;
			statement.is_comment = !line_is_empty;
			statement.terminator = line_terminator;
			statement.end = has_newline ? line_end + 1 : length;
			statements.push_back(statement);
			i = statement.end;
			continue;
		}

		if (p_text[first] == '[') {
			const int close = p_text.find_char(']', first);
			if (close > first && close < line_end) {
				statement.header = p_text.substr(first + 1, close - first - 1).strip_edges();
				statement.terminator = line_terminator;
				statement.end = has_newline ? line_end + 1 : length;
				statements.push_back(statement);
				i = statement.end;
				continue;
			}
		}

		int equals = -1;
		for (int k = first; k < line_end; k++) {
			if (p_text[k] == '=') {
				equals = k;
				break;
			}
		}
		if (equals < first + 1) {
			// Neither a header nor an assignment: the reader would not see a
			// setting here either, so the line is carried through untouched.
			statement.terminator = line_terminator;
			statement.end = has_newline ? line_end + 1 : length;
			statements.push_back(statement);
			i = statement.end;
			continue;
		}

		int key_end = equals;
		while (key_end > first && (p_text[key_end - 1] == ' ' || p_text[key_end - 1] == '\t')) {
			key_end--;
		}

		int value_begin = equals + 1;
		while (value_begin < length && (p_text[value_begin] == ' ' || p_text[value_begin] == '\t')) {
			value_begin++;
		}

		int cursor = value_begin;
		int depth = 0;
		bool in_string = false;
		bool escaped = false;
		while (cursor < length) {
			const char32_t c = p_text[cursor];
			if (in_string) {
				if (escaped) {
					escaped = false;
				} else if (c == '\\') {
					escaped = true;
				} else if (c == '"') {
					in_string = false;
				}
			} else if (c == '"') {
				in_string = true;
			} else if (c == '{' || c == '[' || c == '(') {
				depth++;
			} else if (c == '}' || c == ']' || c == ')') {
				depth--;
			} else if (c == '\n' && depth <= 0) {
				break;
			}
			cursor++;
		}

		int value_end = cursor;
		while (value_end > value_begin && (p_text[value_end - 1] == ' ' || p_text[value_end - 1] == '\t' || p_text[value_end - 1] == '\r')) {
			value_end--;
		}

		statement.key_begin = first;
		statement.key_end = key_end;
		statement.value_begin = value_begin;
		statement.value_end = value_end;
		statement.key = _ps_decode_key(p_text.substr(first, key_end - first));
		// The statement ends on the line the VALUE ends on, which for a
		// serialized dictionary is several lines below the key.
		const bool value_has_newline = cursor < length;
		statement.terminator = value_has_newline ? _ps_terminator_at(p_text, cursor) : String();
		statement.end = value_has_newline ? cursor + 1 : length;
		statements.push_back(statement);
		i = statement.end;
	}

	return statements;
}

} // namespace

Error ProjectSettings::update_settings_section_text(const String &p_text, const String &p_section, const CustomMap &p_custom, String &r_result) {
	r_result = p_text;

	ERR_FAIL_COND_V_MSG(p_section.is_empty(), ERR_INVALID_PARAMETER,
			"A section-granular project settings publish needs a non-empty section name.");
	ERR_FAIL_COND_V_MSG(p_section.contains_char('[') || p_section.contains_char(']') || p_section.contains_char('\n') || p_section.contains_char('\r'), ERR_INVALID_PARAMETER,
			vformat("'%s' cannot name a project settings section.", p_section));

	// The values are serialized by the same writer `_save_settings_text()` uses,
	// so what lands in the file is byte for byte what a full save of that one
	// setting would have written (ConfigFile reads it back the same way).
	// `RBMap` keeps the requested names in a deterministic order, which is what
	// makes the appended block reproducible.
	RBMap<String, String> serialized;
	for (const KeyValue<String, Variant> &E : p_custom) {
		const String prefix = p_section + "/";
		ERR_FAIL_COND_V_MSG(!E.key.begins_with(prefix) || E.key.length() == prefix.length(), ERR_INVALID_PARAMETER,
				vformat("Setting '%s' does not belong to section '%s': a section publish takes full setting names ('%s<name>').", E.key, p_section, prefix));

		String written;
		ERR_FAIL_COND_V_MSG(VariantWriter::write_to_string(E.value, written, true) != OK, ERR_INVALID_DATA,
				vformat("Setting '%s' cannot be written as project settings text.", E.key));
		serialized[E.key.substr(prefix.length())] = written;
	}

	if (serialized.is_empty()) {
		return OK;
	}

	const Vector<_PSStatement> statements = _ps_scan(p_text);

	// The target section: its header statement, and the first statement after it
	// that is another header.
	int header_index = -1;
	for (int i = 0; i < statements.size(); i++) {
		if (!statements[i].header.is_empty() && statements[i].header == p_section) {
			header_index = i;
			break;
		}
	}
	int section_end = statements.size();
	if (header_index >= 0) {
		for (int i = header_index + 1; i < statements.size(); i++) {
			if (!statements[i].header.is_empty()) {
				section_end = i;
				break;
			}
		}
	}

	// Everything the section already has gets its VALUE span replaced (every
	// occurrence, so a hand-written duplicate cannot leave a later, different
	// value that wins on read). The key text and the rest of the line are copied
	// through, so a caller that writes the same value twice gets the same bytes.
	RBMap<String, String> pending;
	for (const KeyValue<String, String> &E : serialized) {
		pending[E.key] = E.value;
	}

	String out;
	int cursor = 0;
	for (int i = 0; i < statements.size(); i++) {
		const _PSStatement &statement = statements[i];
		if (statement.begin > cursor) {
			out += p_text.substr(cursor, statement.begin - cursor);
		}

		const bool in_section = header_index >= 0 && i > header_index && i < section_end;
		if (in_section && statement.is_assignment() && serialized.has(statement.key)) {
			const String &value = serialized[statement.key];
			pending.erase(statement.key);

			const String existing = p_text.substr(statement.value_begin, statement.value_end - statement.value_begin);
			if (existing != value) {
				out += p_text.substr(statement.begin, statement.key_begin - statement.begin);
				out += statement.key.property_name_encode();
				out += "=";
				out += value;
				out += p_text.substr(statement.value_end, statement.end - statement.value_end);
				cursor = statement.end;
				continue;
			}
		}

		out += p_text.substr(statement.begin, statement.end - statement.begin);
		cursor = statement.end;
	}
	if (cursor < p_text.length()) {
		out += p_text.substr(cursor);
	}

	if (!pending.is_empty()) {
		// The line ending this file uses, taken from the first statement that has
		// one, so a CRLF project keeps CRLF endings.
		String file_terminator = "\n";
		for (const _PSStatement &statement : statements) {
			if (!statement.terminator.is_empty()) {
				file_terminator = statement.terminator;
				break;
			}
		}

		if (header_index >= 0) {
			// Append after the last real line of the section, so the blank line
			// that separates the section from the next one stays where it was.
			// A multi-line serialized value is appended as one block.
			int anchor = header_index;
			for (int i = header_index + 1; i < section_end; i++) {
				if (!statements[i].is_blank && !statements[i].is_comment) {
					anchor = i;
				}
			}
			const int insert_at = statements[anchor].end;
			String block;
			if (insert_at > 0 && p_text[insert_at - 1] != '\n') {
				// The last line has no terminator yet; give it one so the new
				// setting starts on its own line.
				block += file_terminator;
			}
			for (const KeyValue<String, String> &E : pending) {
				block += E.key.property_name_encode() + "=" + E.value + file_terminator;
			}
			out = out.substr(0, insert_at) + block + out.substr(insert_at);
		} else {
			// The section does not exist: create it at the end of the file in the
			// shape `_save_settings_text()` writes (a blank line before the
			// header, a blank line after it, then one assignment per line).
			if (!out.is_empty() && !out.ends_with("\n")) {
				out += file_terminator;
			}
			if (!out.is_empty()) {
				out += file_terminator;
			}
			out += "[" + p_section + "]" + file_terminator;
			out += file_terminator;
			for (const KeyValue<String, String> &E : pending) {
				out += E.key.property_name_encode() + "=" + E.value + file_terminator;
			}
		}
	}

	r_result = out;
	return OK;
}

// ---------------------------------------------------------------------------
// TASK-067 (patch 3): the two I/O halves of the section publish.
//
// They are extracted from `save_custom_section()` so a whole-file publish can do
// ONE read and ONE write instead of one pair per section, and so the read and
// the write rule exist in exactly one place. The byte behaviour is unchanged:
// the reader puts back the UTF-8 BOM that `append_utf8()` skips, and the writer
// replaces the file through a sibling plus a backup and verifies the bytes it
// claims to have written.
// ---------------------------------------------------------------------------

Error ProjectSettings::_read_settings_text_file(const String &p_path, String &r_text) const {
	r_text = String();

	Error err = OK;
	Ref<FileAccess> reader = FileAccess::open(p_path, FileAccess::READ, &err);
	ERR_FAIL_COND_V_MSG(err != OK || reader.is_null(), err != OK ? err : ERR_CANT_OPEN, vformat("Couldn't read project settings from '%s'.", p_path));

	const uint64_t length = reader->get_length();
	// `append_utf8()` takes an `int`, so a file larger than that would be
	// truncated by the cast. Refusing is the only honest answer here; the
	// alternative - publishing a prefix of a project.godot - is silent data
	// loss. (This is a new narrowing site, so it is named and gated rather than
	// left implicit: TASK-057 report section 5.)
	ERR_FAIL_COND_V_MSG(length > (uint64_t)INT32_MAX, ERR_OUT_OF_MEMORY,
			vformat("'%s' is too large to be published section by section (size %d bytes).", p_path, (int64_t)length));
	Vector<uint8_t> raw;
	raw.resize(length + 1);
	const uint64_t read = length > 0 ? reader->get_buffer(raw.ptrw(), length) : 0;
	raw.write[length] = 0;
	reader->close();
	if (read != length) {
		return ERR_FILE_CANT_READ;
	}

	// A UTF-8 BOM is not part of the engine's String: `append_utf8()` skips it
	// and `String::utf8()` writes it back only if the character is really there.
	// It is therefore put back into the text explicitly - measured, not assumed:
	// an unqualified read-modify-write through `get_as_text()`/`store_string()`
	// removes the BOM from a file that had one.
	if (length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) {
		r_text = String::chr(0xFEFF);
	}
	r_text.append_utf8((const char *)raw.ptr(), (int)length);
	return OK;
}

Error ProjectSettings::_publish_settings_text_file(const String &p_path, const String &p_text) const {
	// The destination is replaced the way the rest of this code base replaces a
	// file it must not destroy: write a sibling, keep a backup, publish, roll
	// back if the publish fails.
	const String temp_path = p_path + ".section_tmp";
	const String backup_path = p_path + ".section_bak";

	const Error backup_error = DirAccess::copy_absolute(p_path, backup_path);
	if (backup_error != OK) {
		return backup_error;
	}

	Error err = OK;
	Error result = OK;
	Ref<FileAccess> writer = FileAccess::open(temp_path, FileAccess::WRITE, &err);
	if (err != OK || writer.is_null()) {
		result = err != OK ? err : ERR_CANT_CREATE;
	} else {
		const CharString bytes = p_text.utf8();
		writer->store_buffer((const uint8_t *)bytes.get_data(), bytes.length());
		writer->close();

		if (!FileAccess::exists(temp_path)) {
			result = FAILED;
		} else if (p_text.utf8().length() != FileAccess::get_file_as_bytes(temp_path).size()) {
			// The writer reported success; the file is the only thing that
			// proves the bytes really landed (a store_buffer that ran out of
			// space returns without an error).
			result = FAILED;
		} else {
			DirAccess::remove_absolute(p_path);
			result = DirAccess::rename_absolute(temp_path, p_path);
		}
	}

	if (result != OK) {
		if (!FileAccess::exists(p_path) && FileAccess::exists(backup_path)) {
			DirAccess::copy_absolute(backup_path, p_path);
		}
	}

	DirAccess::remove_absolute(backup_path);
	DirAccess::remove_absolute(temp_path);
	return result;
}

Error ProjectSettings::publish_settings_sections_text(const String &p_text, const Vector<String> &p_sections, const CustomMap &p_values, String &r_result) {
	r_result = p_text;
	for (const String &section : p_sections) {
		if (section.is_empty()) {
			// See `save_preserving_text()`: a sectionless key is a top-level
			// assignment of the file itself and has no section form.
			continue;
		}
		const String prefix = section + "/";
		CustomMap section_settings;
		for (const KeyValue<String, Variant> &E : p_values) {
			if (E.key.begins_with(prefix) && E.key.length() > prefix.length()) {
				section_settings[E.key] = E.value;
			}
		}
		if (section_settings.is_empty()) {
			continue;
		}
		String next;
		const Error update_error = update_settings_section_text(r_result, section, section_settings, next);
		if (update_error != OK) {
			return update_error;
		}
		r_result = next;
	}
	return OK;
}

Error ProjectSettings::save_custom_section(const String &p_path, const String &p_section, const CustomMap &p_custom) {
	ERR_FAIL_COND_V_MSG(p_path.is_empty(), ERR_INVALID_PARAMETER, "Project settings section save path cannot be empty.");

	if (!FileAccess::exists(p_path)) {
		// This method publishes *into* a file; it never creates a project from
		// nothing, exactly like `load_custom()` refuses to invent one.
		return ERR_FILE_NOT_FOUND;
	}

	String text;
	const Error read_error = _read_settings_text_file(p_path, text);
	if (read_error != OK) {
		return read_error;
	}

	String updated;
	const Error update_error = update_settings_section_text(text, p_section, p_custom, updated);
	if (update_error != OK) {
		return update_error;
	}
	if (updated == text) {
		// Nothing to say that the file does not already say. Returning here is
		// what keeps a repeat call from touching the file at all (the bytes and
		// the modification time both stay put).
		return OK;
	}

	return _publish_settings_text_file(p_path, updated);
}

// ---------------------------------------------------------------------------
// TASK-067 (patch 3): the editor's own save on open.
//
// Root cause of "opening the project in a windowed editor eats the comments in
// project.godot" (`editor/editor_node.cpp:1062-1072`, reached only when
// `cmdline_mode` is false - `editor_node.cpp:8479` sets it from
// `DisplayServer::get_name() == "headless"`, which is why `--import` and
// `--headless` never showed it): that call site used `save()`, i.e. the
// whole-file writer, which regenerates `project.godot` from the engine's own
// serializer - seven header comment lines plus every stored setting, and nothing
// a human typed.
//
// `save_preserving_text()` keeps the two things the call site actually wants -
// the settings of the editor's own state, and a fresh modification time (the
// project manager reads `project.godot`'s mtime as "last edited",
// `editor/project_manager/project_list.cpp:866-869`) - and publishes them
// section by section into the file that is there, copying every other byte
// through. It is the same rule the writing tools follow since TASK-057 patch 2.
// ---------------------------------------------------------------------------

Error ProjectSettings::save_preserving_text() {
	const String path = get_resource_path().path_join("project.godot");
	ERR_FAIL_COND_V_MSG(!FileAccess::exists(path), ERR_FILE_NOT_FOUND,
			vformat("There is no project settings file at '%s' to publish into.", path));

	// The same set `save()` would write: `save()` calls
	// `save_custom(path)` with an empty custom map and `p_merge_with_current`
	// true, so the rendering-API and `C#` feature entries `save_custom()`
	// recomputes are part of it and opening a project still persists them.
	RBMap<String, List<String>> save_props;
	String save_features;
	const Error collect_error = _collect_settings_for_save(CustomMap(), true, Vector<String>(), save_props, save_features);
	(void)save_features;
	if (collect_error != OK) {
		return collect_error;
	}

	String text;
	const Error read_error = _read_settings_text_file(path, text);
	if (read_error != OK) {
		return read_error;
	}

	String updated = text;
	{
		// The section order is `save_props`' order (an `RBMap` over section
		// names, so it is sorted and reproducible), and the values are the live
		// settings - the same ones `_save_settings_text()` would have serialized.
		Vector<String> sections;
		CustomMap values;
		for (const KeyValue<String, List<String>> &E : save_props) {
			if (E.key.is_empty()) {
				// A setting with no section is a top-level assignment of the file
				// itself: `_load_settings_text()` calls `set(assign, value)` for one
				// (`project_settings.cpp:1001-1002`). It can only have come from the
				// file, and this publish copies the file through byte for byte, so
				// there is nothing to publish for it. Section publishing has no form
				// for a sectionless key by construction -
				// `update_settings_section_text()` refuses an empty section name, and
				// `_save_settings_text()` writes such a key before the first header.
				continue;
			}
			sections.push_back(E.key);
			for (const String &name : E.value) {
				const String full = E.key + "/" + name;
				values[full] = get(full);
			}
		}
		const Error publish_error = publish_settings_sections_text(text, sections, values, updated);
		if (publish_error != OK) {
			return publish_error;
		}
	}

	// Always write, even when `updated == text`. The call site's stated purpose
	// is to mark the project as last modified, and the project manager reads that
	// timestamp as "the date the project was last edited"; the bytes written in
	// the unchanged case are the file's own bytes, so the comments survive either
	// way. `last_save_time` is refreshed exactly like `save()` does it, so the
	// editor's external-change check (`editor/editor_node.cpp:1627`) does not
	// report the write this call just made as somebody else's.
	const Error write_error = _publish_settings_text_file(path, updated);
	if (write_error != OK) {
		return write_error;
	}
	last_save_time = FileAccess::get_modified_time(path);
	return OK;
}

Error ProjectSettings::_save_custom_section_bnd(const String &p_path, const String &p_section, const Dictionary &p_settings) {
	CustomMap custom;
	for (const KeyValue<Variant, Variant> &E : p_settings) {
		custom[E.key] = E.value;
	}
	return save_custom_section(p_path, p_section, custom);
}

Variant _GLOBAL_DEF(const String &p_var, const Variant &p_default, bool p_restart_if_changed, bool p_ignore_value_in_docs, bool p_basic, bool p_internal) {
	Variant ret;
	if (!ProjectSettings::get_singleton()->has_setting(p_var)) {
		ProjectSettings::get_singleton()->set(p_var, p_default);
	}
	ret = GLOBAL_GET(p_var);

	ProjectSettings::get_singleton()->set_initial_value(p_var, p_default);
	ProjectSettings::get_singleton()->set_builtin_order(p_var);
	ProjectSettings::get_singleton()->set_as_basic(p_var, p_basic);
	ProjectSettings::get_singleton()->set_restart_if_changed(p_var, p_restart_if_changed);
	ProjectSettings::get_singleton()->set_ignore_value_in_docs(p_var, p_ignore_value_in_docs);
	ProjectSettings::get_singleton()->set_as_internal(p_var, p_internal);
	return ret;
}

Variant _GLOBAL_DEF(const PropertyInfo &p_info, const Variant &p_default, bool p_restart_if_changed, bool p_ignore_value_in_docs, bool p_basic, bool p_internal) {
	Variant ret = _GLOBAL_DEF(p_info.name, p_default, p_restart_if_changed, p_ignore_value_in_docs, p_basic, p_internal);
	ProjectSettings::get_singleton()->set_custom_property_info(p_info);
	return ret;
}

void ProjectSettings::_add_property_info_bind(const Dictionary &p_info) {
	ERR_FAIL_COND_MSG(!p_info.has("name"), "Property info is missing \"name\" field.");
	ERR_FAIL_COND_MSG(!p_info.has("type"), "Property info is missing \"type\" field.");

	if (p_info.has("usage")) {
		WARN_PRINT("\"usage\" is not supported in add_property_info().");
	}

	PropertyInfo pinfo;
	pinfo.name = p_info["name"];
	ERR_FAIL_COND(!props.has(pinfo.name));
	pinfo.type = Variant::Type(p_info["type"].operator int());
	ERR_FAIL_INDEX(pinfo.type, Variant::VARIANT_MAX);

	if (p_info.has("hint")) {
		pinfo.hint = PropertyHint(p_info["hint"].operator int());
	}
	if (p_info.has("hint_string")) {
		pinfo.hint_string = p_info["hint_string"];
	}

	set_custom_property_info(pinfo);
}

void ProjectSettings::set_custom_property_info(const PropertyInfo &p_info) {
	const String &prop_name = p_info.name;
	ERR_FAIL_COND(!props.has(prop_name));
	custom_prop_info[prop_name] = p_info;
}

const HashMap<StringName, PropertyInfo> &ProjectSettings::get_custom_property_info() const {
	return custom_prop_info;
}

bool ProjectSettings::is_using_datapack() const {
	return using_datapack;
}

bool ProjectSettings::is_project_loaded() const {
	return project_loaded;
}

bool ProjectSettings::_property_can_revert(const StringName &p_name) const {
	return props.has(p_name) && !String(p_name).begins_with(EDITOR_SETTING_OVERRIDE_PREFIX);
}

bool ProjectSettings::_property_get_revert(const StringName &p_name, Variant &r_property) const {
	const RBMap<StringName, ProjectSettings::VariantContainer>::Element *value = props.find(p_name);
	if (value) {
		r_property = value->value().initial.duplicate();
		return true;
	}
	return false;
}

void ProjectSettings::set_setting(const String &p_setting, const Variant &p_value) {
	set(p_setting, p_value);
}

Variant ProjectSettings::get_setting(const String &p_setting, const Variant &p_default_value) const {
	if (has_setting(p_setting)) {
		return get(p_setting);
	} else {
		return p_default_value;
	}
}

PackedStringArray ProjectSettings::get_changed_settings() const {
	PackedStringArray arr;
	for (const StringName &setting : changed_settings) {
		arr.push_back(setting);
	}
	return arr;
}

bool ProjectSettings::check_changed_settings_in_group(const String &p_setting_prefix) const {
	for (const StringName &setting : changed_settings) {
		if (String(setting).begins_with(p_setting_prefix)) {
			return true;
		}
	}
	return false;
}

void ProjectSettings::refresh_global_class_list() {
	// This is called after mounting a new PCK file to pick up class changes.
	is_global_class_list_loaded = false; // Make sure we read from the freshly mounted PCK.
	Array script_classes = get_global_class_list();
	for (int i = 0; i < script_classes.size(); i++) {
		Dictionary c = script_classes[i];
		if (!c.has("class") || !c.has("language") || !c.has("path") || !c.has("base") || !c.has("is_abstract") || !c.has("is_tool")) {
			continue;
		}
		ScriptServer::add_global_class(c["class"], c["base"], c["language"], c["path"], c["is_abstract"], c["is_tool"]);
	}
}

TypedArray<Dictionary> ProjectSettings::get_global_class_list() {
	if (is_global_class_list_loaded) {
		return global_class_list;
	}

	Ref<ConfigFile> cf;
	cf.instantiate();
	if (cf->load(get_global_class_list_path()) == OK) {
		global_class_list = cf->get_value("", "list", Array());
	} else {
#ifndef TOOLS_ENABLED
		// Script classes can't be recreated in exported project, so print an error.
		ERR_PRINT("Could not load global script cache.");
#endif
	}

	// File read succeeded or failed. If it failed, assume everything is still okay.
	// We will later receive updated class data in store_global_class_list().
	is_global_class_list_loaded = true;

	return global_class_list;
}

String ProjectSettings::get_global_class_list_path() const {
	return get_project_data_path().path_join("global_script_class_cache.cfg");
}

void ProjectSettings::store_global_class_list(const Array &p_classes) {
	Ref<ConfigFile> cf;
	cf.instantiate();
	cf->set_value("", "list", p_classes);
	cf->save(get_global_class_list_path());

	global_class_list = p_classes;
}

bool ProjectSettings::has_custom_feature(const String &p_feature) const {
	return custom_features.has(p_feature);
}

const HashMap<StringName, ProjectSettings::AutoloadInfo> &ProjectSettings::get_autoload_list() const {
	return autoloads;
}

void ProjectSettings::add_autoload(const AutoloadInfo &p_autoload, bool p_front_insert) {
	ERR_FAIL_COND_MSG(p_autoload.name == StringName(), "Trying to add autoload with no name.");
	if (p_front_insert) {
		if (autoloads.has(p_autoload.name)) {
			autoloads.erase(p_autoload.name);
		}
		autoloads.insert(p_autoload.name, p_autoload, true);
	} else {
		autoloads[p_autoload.name] = p_autoload;
	}
}

void ProjectSettings::remove_autoload(const StringName &p_autoload) {
	ERR_FAIL_COND_MSG(!autoloads.has(p_autoload), "Trying to remove non-existent autoload.");
	autoloads.erase(p_autoload);
}

bool ProjectSettings::has_autoload(const StringName &p_autoload) const {
	return autoloads.has(p_autoload);
}

ProjectSettings::AutoloadInfo ProjectSettings::get_autoload(const StringName &p_name) const {
	ERR_FAIL_COND_V_MSG(!autoloads.has(p_name), AutoloadInfo(), "Trying to get non-existent autoload.");
	return autoloads[p_name];
}

void ProjectSettings::fix_autoload_paths() {
	for (KeyValue<StringName, AutoloadInfo> &kv : autoloads) {
		kv.value.path = ResourceUID::ensure_path(kv.value.path);
	}
}

const HashMap<StringName, String> &ProjectSettings::get_global_groups_list() const {
	return global_groups;
}

void ProjectSettings::add_global_group(const StringName &p_name, const String &p_description) {
	ERR_FAIL_COND_MSG(p_name == StringName(), "Trying to add global group with no name.");
	global_groups[p_name] = p_description;
}

void ProjectSettings::remove_global_group(const StringName &p_name) {
	ERR_FAIL_COND_MSG(!global_groups.has(p_name), "Trying to remove non-existent global group.");
	global_groups.erase(p_name);
}

bool ProjectSettings::has_global_group(const StringName &p_name) const {
	return global_groups.has(p_name);
}

void ProjectSettings::remove_scene_groups_cache(const StringName &p_path) {
	scene_groups_cache.erase(p_path);
}

void ProjectSettings::add_scene_groups_cache(const StringName &p_path, const HashSet<StringName> &p_cache) {
	scene_groups_cache[p_path] = p_cache;
}

void ProjectSettings::save_scene_groups_cache() {
	Ref<ConfigFile> cf;
	cf.instantiate();
	for (const KeyValue<StringName, HashSet<StringName>> &E : scene_groups_cache) {
		if (E.value.is_empty()) {
			continue;
		}
		Array list;
		for (const StringName &group : E.value) {
			list.push_back(group);
		}
		cf->set_value(E.key, "groups", list);
	}
	cf->save(get_scene_groups_cache_path());
}

String ProjectSettings::get_scene_groups_cache_path() const {
	return get_project_data_path().path_join("scene_groups_cache.cfg");
}

void ProjectSettings::load_scene_groups_cache() {
	Ref<ConfigFile> cf;
	cf.instantiate();
	if (cf->load(get_scene_groups_cache_path()) == OK) {
		Vector<String> scene_paths = cf->get_sections();
		for (const String &E : scene_paths) {
			Array scene_groups = cf->get_value(E, "groups", Array());
			HashSet<StringName> cache;
			for (const Variant &scene_group : scene_groups) {
				cache.insert(scene_group);
			}
			add_scene_groups_cache(E, cache);
		}
	}
}

const HashMap<StringName, HashSet<StringName>> &ProjectSettings::get_scene_groups_cache() const {
	return scene_groups_cache;
}

#ifdef TOOLS_ENABLED
void ProjectSettings::get_argument_options(const StringName &p_function, int p_idx, List<String> *r_options) const {
	const String pf = p_function;
	if (p_idx == 0) {
		if (pf == "has_setting" || pf == "set_setting" || pf == "get_setting" || pf == "get_setting_with_override" ||
				pf == "set_order" || pf == "get_order" || pf == "set_initial_value" || pf == "set_as_basic" ||
				pf == "set_as_internal" || pf == "set_restart_if_changed" || pf == "clear") {
			for (const KeyValue<StringName, VariantContainer> &E : props) {
				if (E.value.hide_from_editor) {
					continue;
				}

				r_options->push_back(String(E.key).quote());
			}
		}
	}
	Object::get_argument_options(p_function, p_idx, r_options);
}
#endif

void ProjectSettings::set_editor_setting_override(const String &p_setting, const Variant &p_value) {
	set_setting(EDITOR_SETTING_OVERRIDE_PREFIX + p_setting, p_value);
}

bool ProjectSettings::has_editor_setting_override(const String &p_setting) const {
	return has_setting(EDITOR_SETTING_OVERRIDE_PREFIX + p_setting);
}

Variant ProjectSettings::get_editor_setting_override(const String &p_setting) const {
	return get_setting(EDITOR_SETTING_OVERRIDE_PREFIX + p_setting);
}

void ProjectSettings::_bind_methods() {
	ClassDB::bind_method(D_METHOD("has_setting", "name"), &ProjectSettings::has_setting);
	ClassDB::bind_method(D_METHOD("set_setting", "name", "value"), &ProjectSettings::set_setting);
	ClassDB::bind_method(D_METHOD("get_setting", "name", "default_value"), &ProjectSettings::get_setting, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("get_setting_with_override", "name"), &ProjectSettings::get_setting_with_override);
	ClassDB::bind_method(D_METHOD("get_global_class_list"), &ProjectSettings::get_global_class_list);
	ClassDB::bind_method(D_METHOD("get_setting_with_override_and_custom_features", "name", "features"), &ProjectSettings::get_setting_with_override_and_custom_features);
	ClassDB::bind_method(D_METHOD("set_order", "name", "position"), &ProjectSettings::set_order);
	ClassDB::bind_method(D_METHOD("get_order", "name"), &ProjectSettings::get_order);
	ClassDB::bind_method(D_METHOD("set_initial_value", "name", "value"), &ProjectSettings::set_initial_value);
	ClassDB::bind_method(D_METHOD("set_as_basic", "name", "basic"), &ProjectSettings::set_as_basic);
	ClassDB::bind_method(D_METHOD("set_as_internal", "name", "internal"), &ProjectSettings::set_as_internal);
	ClassDB::bind_method(D_METHOD("add_property_info", "hint"), &ProjectSettings::_add_property_info_bind);
	ClassDB::bind_method(D_METHOD("set_restart_if_changed", "name", "restart"), &ProjectSettings::set_restart_if_changed);
	ClassDB::bind_method(D_METHOD("clear", "name"), &ProjectSettings::clear);
	ClassDB::bind_method(D_METHOD("localize_path", "path"), &ProjectSettings::localize_path);
	ClassDB::bind_method(D_METHOD("globalize_path", "path"), &ProjectSettings::globalize_path);
	ClassDB::bind_method(D_METHOD("save"), &ProjectSettings::save);
	ClassDB::bind_method(D_METHOD("load_resource_pack", "pack", "replace_files", "offset"), &ProjectSettings::load_resource_pack, DEFVAL(true), DEFVAL(0));

	ClassDB::bind_method(D_METHOD("save_custom", "file"), &ProjectSettings::_save_custom_bnd);

	// TASK-057 patch 2: the section-granular publish (see the header for why a
	// caller that must keep the rest of the file cannot use `save_custom()`).
	ClassDB::bind_method(D_METHOD("save_custom_section", "path", "section", "settings"), &ProjectSettings::_save_custom_section_bnd);

	// Change tracking methods
	ClassDB::bind_method(D_METHOD("get_changed_settings"), &ProjectSettings::get_changed_settings);
	ClassDB::bind_method(D_METHOD("check_changed_settings_in_group", "setting_prefix"), &ProjectSettings::check_changed_settings_in_group);
	ADD_SIGNAL(MethodInfo("settings_changed"));
}

void ProjectSettings::_add_builtin_input_map() {
	if (InputMap::get_singleton()) {
		HashMap<String, List<Ref<InputEvent>>> builtins(InputMap::get_singleton()->get_builtins());

		for (KeyValue<String, List<Ref<InputEvent>>> &E : builtins) {
			Array events;

			// Convert list of input events into array
			for (const Ref<InputEvent> &event : E.value) {
				events.push_back(event);
			}

			Dictionary action;
			action["deadzone"] = Variant(InputMap::DEFAULT_TOGGLE_DEADZONE);
			action["events"] = events;

			String action_name = "input/" + E.key;
			GLOBAL_DEF(action_name, action);
			input_presets.push_back(action_name);
		}
	}
}

ProjectSettings::ProjectSettings() {
	// Initialization of engine variables should be done in the setup() method,
	// so that the values can be overridden from project.godot or project.binary.

	CRASH_COND_MSG(singleton != nullptr, "Instantiating a new ProjectSettings singleton is not supported.");
	singleton = this;

#ifdef TOOLS_ENABLED
	// Available only at runtime in editor builds. Needs to be processed before anything else to work properly.
	if (!Engine::get_singleton()->is_editor_hint()) {
		String editor_features = OS::get_singleton()->get_environment("GODOT_EDITOR_CUSTOM_FEATURES");
		if (!editor_features.is_empty()) {
			PackedStringArray feature_list = editor_features.split(",");
			for (const String &s : feature_list) {
				custom_features.insert(s);
			}
		}
	}
#endif

	GLOBAL_DEF_BASIC("application/config/name", "");
	GLOBAL_DEF(PropertyInfo(Variant::DICTIONARY, "application/config/name_localized", PROPERTY_HINT_LOCALIZABLE_STRING), Dictionary());
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::STRING, "application/config/description", PROPERTY_HINT_MULTILINE_TEXT), "");
	GLOBAL_DEF_BASIC("application/config/version", "");
	GLOBAL_DEF_INTERNAL(PropertyInfo(Variant::STRING, "application/config/tags"), PackedStringArray());
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::STRING, "application/run/main_scene", PROPERTY_HINT_FILE, "*.tscn,*.scn,*.res"), "");
	GLOBAL_DEF("application/run/disable_stdout", false);
	GLOBAL_DEF("application/run/disable_stderr", false);
	GLOBAL_DEF("application/run/print_header", true);
	GLOBAL_DEF("application/run/enable_alt_space_menu", false);
	GLOBAL_DEF("application/run/use_game_mode", true);
	GLOBAL_DEF_RST("application/config/use_hidden_project_data_directory", true);
	GLOBAL_DEF("application/config/use_custom_user_dir", false);
	GLOBAL_DEF("application/config/custom_user_dir_name", "");
	GLOBAL_DEF("application/config/project_settings_override", "");
	GLOBAL_DEF("application/config/disable_project_settings_override", false);

	GLOBAL_DEF("application/run/main_loop_type", "SceneTree");
	GLOBAL_DEF("application/config/auto_accept_quit", true);
	GLOBAL_DEF("application/config/quit_on_go_back", true);

	GLOBAL_DEF_BASIC(PropertyInfo(Variant::INT, "accessibility/general/accessibility_support", PROPERTY_HINT_ENUM, "Auto (When Screen Reader is Running),Always Active,Disabled"), 0);
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::INT, "accessibility/general/updates_per_second", PROPERTY_HINT_RANGE, "1,100,1"), 60);
	GLOBAL_DEF(PropertyInfo(Variant::STRING, "accessibility/general/accessibility_driver", PROPERTY_HINT_ENUM, "accesskit,dummy"), "accesskit");

	// The default window size is tuned to:
	// - Have a 16:9 aspect ratio,
	// - Have both dimensions divisible by 8 to better play along with video recording,
	// - Be displayable correctly in windowed mode on a 1366×768 display (tested on Windows 10 with default settings).
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::INT, "display/window/size/viewport_width", PROPERTY_HINT_RANGE, "1,7680,1,or_greater"), 1152); // 8K resolution
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::INT, "display/window/size/viewport_height", PROPERTY_HINT_RANGE, "1,4320,1,or_greater"), 648); // 8K resolution

	GLOBAL_DEF_BASIC(PropertyInfo(Variant::INT, "display/window/size/mode", PROPERTY_HINT_ENUM, "Windowed,Minimized,Maximized,Fullscreen,Exclusive Fullscreen"), 0);

	// Keep the enum values in sync with the `Window::WINDOW_INITIAL_POSITION_` enum.
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::INT, "display/window/size/initial_position_type", PROPERTY_HINT_ENUM, "Absolute:0,Center of Primary Screen:1,Center of Other Screen:3,Center of Screen With Mouse Pointer:4,Center of Screen With Keyboard Focus:5"), 1);
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::VECTOR2I, "display/window/size/initial_position"), Vector2i());
	// Keep the enum values in sync with the `DisplayServer::SCREEN_` enum.
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::INT, "display/window/size/initial_screen", PROPERTY_HINT_RANGE, "0,64,1,or_greater"), 0);

	GLOBAL_DEF_BASIC("display/window/size/resizable", true);
	GLOBAL_DEF_BASIC("display/window/size/borderless", false);
	GLOBAL_DEF("display/window/size/always_on_top", false);
	GLOBAL_DEF("display/window/size/transparent", false);
	GLOBAL_DEF("display/window/size/extend_to_title", false);
	GLOBAL_DEF("display/window/size/no_focus", false);
	GLOBAL_DEF("display/window/size/sharp_corners", false);
	GLOBAL_DEF("display/window/size/minimize_disabled", false);
	GLOBAL_DEF("display/window/size/maximize_disabled", false);
	GLOBAL_DEF("display/window/size/enable_toggle_fullscreen_shortcut", true);

	GLOBAL_DEF(PropertyInfo(Variant::INT, "display/window/size/window_width_override", PROPERTY_HINT_RANGE, "0,7680,1,or_greater"), 0); // 8K resolution
	GLOBAL_DEF(PropertyInfo(Variant::INT, "display/window/size/window_height_override", PROPERTY_HINT_RANGE, "0,4320,1,or_greater"), 0); // 8K resolution

	GLOBAL_DEF_BASIC("display/window/hdr/request_hdr_output", false);

	GLOBAL_DEF("display/window/energy_saving/keep_screen_on", true);
	GLOBAL_DEF("animation/warnings/check_invalid_skeleton_modifier_node_paths", true);
	GLOBAL_DEF("animation/warnings/check_invalid_track_paths", true);
	GLOBAL_DEF("animation/warnings/check_angle_interpolation_type_conflicting", true);
#ifndef DISABLE_DEPRECATED
	GLOBAL_DEF_RST("animation/compatibility/default_parent_skeleton_in_mesh_instance_3d", false);
#endif

	GLOBAL_DEF_BASIC(PropertyInfo(Variant::STRING, "audio/buses/default_bus_layout", PROPERTY_HINT_FILE, "*.tres"), "res://default_bus_layout.tres");
	GLOBAL_DEF(PropertyInfo(Variant::INT, "audio/general/default_playback_type", PROPERTY_HINT_ENUM, "Stream,Sample"), 0);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "audio/general/default_playback_type.web", PROPERTY_HINT_ENUM, "Stream,Sample"), 1);
	GLOBAL_DEF_RST("audio/general/text_to_speech", false);
	GLOBAL_DEF_RST(PropertyInfo(Variant::FLOAT, "audio/general/2d_panning_strength", PROPERTY_HINT_RANGE, "0,2,0.01"), 0.5f);
	GLOBAL_DEF_RST(PropertyInfo(Variant::FLOAT, "audio/general/3d_panning_strength", PROPERTY_HINT_RANGE, "0,2,0.01"), 0.5f);

	GLOBAL_DEF(PropertyInfo(Variant::INT, "audio/general/ios/session_category", PROPERTY_HINT_ENUM, "Ambient,Multi Route,Play and Record,Playback,Record,Solo Ambient"), 0);
	GLOBAL_DEF("audio/general/ios/mix_with_others", false);

	_add_builtin_input_map();

	// Keep the enum values in sync with the `DisplayServerEnums::ScreenOrientation` enum.
	custom_prop_info["display/window/handheld/orientation"] = PropertyInfo(Variant::INT, "display/window/handheld/orientation", PROPERTY_HINT_ENUM, "Landscape,Portrait,Reverse Landscape,Reverse Portrait,Sensor Landscape,Sensor Portrait,Sensor");
	GLOBAL_DEF("display/window/subwindows/embed_subwindows", true);
	// Keep the enum values in sync with the `DisplayServerEnums::VSyncMode` enum.
	custom_prop_info["display/window/vsync/vsync_mode"] = PropertyInfo(Variant::INT, "display/window/vsync/vsync_mode", PROPERTY_HINT_ENUM, "Disabled,Enabled,Adaptive,Mailbox");

	GLOBAL_DEF("display/window/frame_pacing/android/enable_frame_pacing", true);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "display/window/frame_pacing/android/swappy_mode", PROPERTY_HINT_ENUM, "pipeline_forced_on,auto_fps_pipeline_forced_on,auto_fps_auto_pipeline"), 2);

#ifdef DISABLE_DEPRECATED
	custom_prop_info["rendering/driver/threads/thread_model"] = PropertyInfo(Variant::INT, "rendering/driver/threads/thread_model", PROPERTY_HINT_ENUM, "Safe:1,Separate");
#else
	custom_prop_info["rendering/driver/threads/thread_model"] = PropertyInfo(Variant::INT, "rendering/driver/threads/thread_model", PROPERTY_HINT_ENUM, "Unsafe (deprecated),Safe,Separate");
#endif

#ifndef PHYSICS_2D_DISABLED
	GLOBAL_DEF("physics/2d/run_on_separate_thread", false);
#endif // PHYSICS_2D_DISABLED
#ifndef PHYSICS_3D_DISABLED
	GLOBAL_DEF("physics/3d/run_on_separate_thread", false);
#endif // PHYSICS_3D_DISABLED

	GLOBAL_DEF_BASIC(PropertyInfo(Variant::STRING, "display/window/stretch/mode", PROPERTY_HINT_ENUM, "disabled,canvas_items,viewport"), "disabled");
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::STRING, "display/window/stretch/aspect", PROPERTY_HINT_ENUM, "ignore,keep,keep_width,keep_height,expand"), "keep");
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::FLOAT, "display/window/stretch/scale", PROPERTY_HINT_RANGE, "0.5,8.0,0.01"), 1.0);
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::STRING, "display/window/stretch/scale_mode", PROPERTY_HINT_ENUM, "fractional,integer"), "fractional");

	GLOBAL_DEF(PropertyInfo(Variant::INT, "debug/settings/profiler/max_functions", PROPERTY_HINT_RANGE, "128,65535,1"), 16384);
	GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "debug/settings/profiler/max_timestamp_query_elements", PROPERTY_HINT_RANGE, "256,65535,1"), 256);

	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "compression/formats/zstd/long_distance_matching"), Compression::zstd_long_distance_matching);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "compression/formats/zstd/compression_level", PROPERTY_HINT_RANGE, "1,22,1"), Compression::zstd_level);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "compression/formats/zstd/window_log_size", PROPERTY_HINT_RANGE, "10,30,1"), Compression::zstd_window_log_size);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "compression/formats/zlib/compression_level", PROPERTY_HINT_RANGE, "-1,9,1"), Compression::zlib_level);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "compression/formats/gzip/compression_level", PROPERTY_HINT_RANGE, "-1,9,1"), Compression::gzip_level);

	GLOBAL_DEF("debug/settings/crash_handler/message",
			String("Please include this when reporting the bug to the project developer."));
	GLOBAL_DEF("debug/settings/crash_handler/message.editor",
			String("Please include this when reporting the bug on: https://github.com/godotengine/godot/issues"));
	GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "rendering/occlusion_culling/bvh_build_quality", PROPERTY_HINT_ENUM, "Low,Medium,High"), 2);
	GLOBAL_DEF_RST("rendering/occlusion_culling/jitter_projection", true);

	GLOBAL_DEF_RST("internationalization/rendering/force_right_to_left_layout_direction", false);
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::INT, "internationalization/rendering/root_node_layout_direction", PROPERTY_HINT_ENUM, "Based on Application Locale,Left-to-Right,Right-to-Left,Based on System Locale"), 0);
	GLOBAL_DEF_BASIC("internationalization/rendering/root_node_auto_translate", true);

	GLOBAL_DEF(PropertyInfo(Variant::INT, "gui/timers/incremental_search_max_interval_msec", PROPERTY_HINT_RANGE, "0,10000,1,or_greater"), 2000);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "gui/timers/tooltip_delay_sec", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater"), 0.5);
#ifdef TOOLS_ENABLED
	GLOBAL_DEF("gui/timers/tooltip_delay_sec.editor_hint", 0.5);
#endif

	GLOBAL_DEF("gui/common/drag_threshold", 10);
	GLOBAL_DEF_BASIC("gui/common/snap_controls_to_pixels", true);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "gui/common/show_focus_state_on_pointer_event", PROPERTY_HINT_ENUM, "Never,Text Input Controls,Always"), 1);
	GLOBAL_DEF_BASIC("gui/fonts/dynamic_fonts/use_oversampling", true);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "gui/common/auto_focus_strategy", PROPERTY_HINT_ENUM, "Legacy,Balloon"), 0);

#ifdef RD_ENABLED
	GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "rendering/rendering_device/vsync/frame_queue_size", PROPERTY_HINT_RANGE, "2,3,1"), 2);
	GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "rendering/rendering_device/vsync/swapchain_image_count", PROPERTY_HINT_RANGE, "2,4,1"), 3);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "rendering/rendering_device/staging_buffer/block_size_kb", PROPERTY_HINT_RANGE, "4,2048,1,or_greater"), 256);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "rendering/rendering_device/staging_buffer/max_size_mb", PROPERTY_HINT_RANGE, "1,1024,1,or_greater"), 128);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "rendering/rendering_device/staging_buffer/texture_upload_region_size_px", PROPERTY_HINT_RANGE, "1,256,1,or_greater"), 64);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "rendering/rendering_device/staging_buffer/texture_download_region_size_px", PROPERTY_HINT_RANGE, "1,256,1,or_greater"), 64);
	GLOBAL_DEF_RST(PropertyInfo(Variant::BOOL, "rendering/rendering_device/pipeline_cache/enable"), true);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "rendering/rendering_device/pipeline_cache/save_chunk_size_mb", PROPERTY_HINT_RANGE, "0.000001,64.0,0.001,or_greater"), 3.0);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "rendering/rendering_device/vulkan/max_descriptors_per_pool", PROPERTY_HINT_RANGE, "1,256,1,or_greater"), 64);

	GLOBAL_DEF_RST("rendering/rendering_device/d3d12/max_resource_descriptors", 65536);
	custom_prop_info["rendering/rendering_device/d3d12/max_resource_descriptors"] = PropertyInfo(Variant::INT, "rendering/rendering_device/d3d12/max_resource_descriptors", PROPERTY_HINT_RANGE, "512,1000000");
	GLOBAL_DEF_RST("rendering/rendering_device/d3d12/max_sampler_descriptors", 1024);
	custom_prop_info["rendering/rendering_device/d3d12/max_sampler_descriptors"] = PropertyInfo(Variant::INT, "rendering/rendering_device/d3d12/max_sampler_descriptors", PROPERTY_HINT_RANGE, "256,2048");

	// The default value must match the minor part of the Agility SDK version
	// installed by the scripts provided in the repository
	// (check `misc/scripts/install_d3d12_sdk_windows.py`).
	// For example, if the script installs 1.618.5, the default value must be 618.
	GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "rendering/rendering_device/d3d12/agility_sdk_version", PROPERTY_HINT_RANGE, "0,10000,1,or_greater,hide_control"), 618);
#endif // RD_ENABLED

	GLOBAL_DEF_BASIC(PropertyInfo(Variant::INT, "rendering/textures/canvas_textures/default_texture_filter", PROPERTY_HINT_ENUM, "Nearest,Linear,Linear Mipmap,Nearest Mipmap"), 1);
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::INT, "rendering/textures/canvas_textures/default_texture_repeat", PROPERTY_HINT_ENUM, "Disable,Enable,Mirror"), 0);

	GLOBAL_DEF("collada/use_ambient", false);

	// Input settings
	GLOBAL_DEF_BASIC("input_devices/pointing/android/enable_long_press_as_right_click", false);
	GLOBAL_DEF_BASIC("input_devices/pointing/android/enable_pan_and_scale_gestures", false);
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::INT, "input_devices/pointing/android/rotary_input_scroll_axis", PROPERTY_HINT_ENUM, "Horizontal,Vertical"), 1);
	GLOBAL_DEF("input_devices/pointing/android/override_volume_buttons", false);
	GLOBAL_DEF_BASIC("input_devices/pointing/android/disable_scroll_deadzone", false);

	// These properties will not show up in the dialog. If you want to exclude whole groups, use add_hidden_prefix().
	GLOBAL_DEF_INTERNAL("application/config/features", PackedStringArray());
	GLOBAL_DEF_INTERNAL("internationalization/locale/translation_remaps", PackedStringArray());
	GLOBAL_DEF_INTERNAL("internationalization/locale/translations", PackedStringArray());
	GLOBAL_DEF_INTERNAL("internationalization/locale/translations_pot_files", PackedStringArray());
	GLOBAL_DEF_INTERNAL("internationalization/locale/translation_add_builtin_strings_to_pot", false);
	GLOBAL_DEF_INTERNAL("internationalization/locale/translation_add_project_title_to_translation_template", false);

#if !defined(NAVIGATION_2D_DISABLED) || !defined(NAVIGATION_3D_DISABLED)
	GLOBAL_DEF("navigation/world/map_use_async_iterations", true);
	GLOBAL_DEF("navigation/world/region_use_async_iterations", true);

	GLOBAL_DEF("navigation/avoidance/thread_model/avoidance_use_multiple_threads", true);
	GLOBAL_DEF("navigation/avoidance/thread_model/avoidance_use_high_priority_threads", true);

	GLOBAL_DEF("navigation/pathfinding/max_threads", 4);

	GLOBAL_DEF("navigation/baking/use_crash_prevention_checks", true);
	GLOBAL_DEF("navigation/baking/thread_model/baking_use_multiple_threads", true);
	GLOBAL_DEF("navigation/baking/thread_model/baking_use_high_priority_threads", true);
#endif // !defined(NAVIGATION_2D_DISABLED) || !defined(NAVIGATION_3D_DISABLED)
#ifndef NAVIGATION_2D_DISABLED
	GLOBAL_DEF("navigation/2d/warnings/navmesh_edge_merge_errors", true);
	GLOBAL_DEF("navigation/2d/warnings/navmesh_cell_size_mismatch", true);
#endif // NAVIGATION_2D_DISABLED
#ifndef NAVIGATION_3D_DISABLED
	GLOBAL_DEF("navigation/3d/warnings/navmesh_edge_merge_errors", true);
	GLOBAL_DEF("navigation/3d/warnings/navmesh_cell_size_mismatch", true);
#endif // NAVIGATION_3D_DISABLED

	ProjectSettings::get_singleton()->add_hidden_prefix("input/");
}

ProjectSettings::ProjectSettings(const String &p_path) {
	if (load_custom(p_path) == OK) {
		resource_path = p_path.get_base_dir();
		project_loaded = true;
	}
}

ProjectSettings::~ProjectSettings() {
	if (singleton == this) {
		singleton = nullptr;
	}
}
