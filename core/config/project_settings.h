/**************************************************************************/
/*  project_settings.h                                                    */
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

#include "core/object/object.h"
#include "core/os/thread_safe.h"
#include "core/templates/rb_map.h"

template <typename T>
class TypedArray;

class ProjectSettings : public Object {
	GDCLASS(ProjectSettings, Object);
	_THREAD_SAFE_CLASS_
	friend class TestProjectSettingsInternalsAccessor;

	bool is_changed = false;

	// Starting version from 1 ensures that all callers can reset their tested version to 0,
	// and will always detect the initial project settings as a "change".
	uint32_t _version = 1;

	// Track changed settings for get_changed_settings functionality
	HashSet<StringName> changed_settings;

public:
	typedef HashMap<String, Variant> CustomMap;
	// This constant is used to make the ".godot" folder and paths like "res://.godot/editor".
	static inline const String PROJECT_DATA_DIR_NAME_SUFFIX = "godot";
	static inline const String EDITOR_SETTING_OVERRIDE_PREFIX = PNAME("editor_overrides") + String("/");

	// Properties that are not for built in values begin from this value, so builtin ones are displayed first.
	constexpr static const int32_t NO_BUILTIN_ORDER_BASE = 1 << 16;

#ifdef TOOLS_ENABLED
	const static PackedStringArray get_required_features();
	const static PackedStringArray get_unsupported_features(const PackedStringArray &p_project_features);
#endif // TOOLS_ENABLED

	struct AutoloadInfo {
		StringName name;
		String path;
		bool is_singleton = false;
	};

protected:
	struct VariantContainer {
		int order = 0;
		bool persist = false;
		bool basic = false;
		bool internal = false;
		Variant variant;
		Variant initial;
		bool hide_from_editor = false;
		bool restart_if_changed = false;
#ifdef DEBUG_ENABLED
		bool ignore_value_in_docs = false;
#endif // DEBUG_ENABLED

		VariantContainer() {}

		VariantContainer(const Variant &p_variant, int p_order, bool p_persist = false) :
				order(p_order),
				persist(p_persist),
				variant(p_variant) {
		}
	};

	int last_order = NO_BUILTIN_ORDER_BASE;
	int last_builtin_order = 0;
	uint64_t last_save_time = 0;

	RBMap<StringName, VariantContainer> props; // NOTE: Key order is used e.g. in the save_custom method.
	String resource_path;
	HashMap<StringName, PropertyInfo> custom_prop_info;
	bool using_datapack = false;
	bool project_loaded = false;
	List<String> input_presets;

	HashSet<String> custom_features;
	HashMap<StringName, LocalVector<Pair<StringName, StringName>>> feature_overrides;

	LocalVector<String> hidden_prefixes;
	HashMap<StringName, AutoloadInfo> autoloads;
	HashMap<StringName, String> global_groups;
	HashMap<StringName, HashSet<StringName>> scene_groups_cache;

	Array global_class_list;
	bool is_global_class_list_loaded = false;

	String project_data_dir_name;

	bool _set(const StringName &p_name, const Variant &p_value);
	bool _get(const StringName &p_name, Variant &r_ret) const;
	void _get_property_list(List<PropertyInfo> *p_list) const;
	bool _property_can_revert(const StringName &p_name) const;
	bool _property_get_revert(const StringName &p_name, Variant &r_property) const;

	void _queue_changed(const StringName &p_name);
	void _emit_changed();

	static inline ProjectSettings *singleton = nullptr;

	Error _load_settings_text(const String &p_path);
	Error _load_settings_binary(const String &p_path);
	Error _load_settings_text_or_binary(const String &p_text_path, const String &p_bin_path);

	Error _save_settings_text(const String &p_file, const RBMap<String, List<String>> &p_props, const CustomMap &p_custom = CustomMap(), const String &p_custom_features = String());
	Error _save_settings_binary(const String &p_file, const RBMap<String, List<String>> &p_props, const CustomMap &p_custom = CustomMap(), const String &p_custom_features = String());

	// TASK-067 (patch 3). The three pieces `save_custom()` and the section
	// publish share, so the whole-file writer and the per-section writer cannot
	// drift apart:
	//   * `_collect_settings_for_save()` is the "which settings would a save
	//     write, grouped by section" half of `save_custom()`;
	//   * `_read_settings_text_file()` reads a settings file as the engine
	//     decodes it, UTF-8 BOM included;
	//   * `_publish_settings_text_file()` replaces it atomically (sibling,
	//     backup, verify-bytes, rename, roll back).
	Error _collect_settings_for_save(const CustomMap &p_custom, bool p_merge_with_current, const Vector<String> &p_custom_features, RBMap<String, List<String>> &r_props, String &r_features);
	Error _read_settings_text_file(const String &p_path, String &r_text) const;
	Error _publish_settings_text_file(const String &p_path, const String &p_text) const;

	Error _save_custom_bnd(const String &p_file);
	Error _save_custom_section_bnd(const String &p_path, const String &p_section, const Dictionary &p_settings);

#ifdef TOOLS_ENABLED
	const static PackedStringArray _get_supported_features();
	const static PackedStringArray _trim_to_supported_features(const PackedStringArray &p_project_features);
#endif // TOOLS_ENABLED

	void _convert_to_last_version(int p_from_version);
#ifndef DISABLE_DEPRECATED
	void _handle_editor_setting_compat(const String &p_original_setting, const String &p_new_setting);
#endif

	bool load_resource_pack(const String &p_pack, bool p_replace_files, int p_offset);
	bool _load_resource_pack(const String &p_pack, bool p_replace_files = true, int p_offset = 0, bool p_main_pack = false);

	void _add_property_info_bind(const Dictionary &p_info);

	Error _setup(const String &p_path, const String &p_main_pack, bool p_upwards = false, bool p_ignore_override = false);

	void _add_builtin_input_map();

protected:
	static void _bind_methods();

public:
	static const int CONFIG_VERSION = 5;

#ifdef TOOLS_ENABLED
	HashMap<String, PropertyInfo> editor_settings_info;
#endif

	void set_setting(const String &p_setting, const Variant &p_value);
	Variant get_setting(const String &p_setting, const Variant &p_default_value = Variant()) const;
	TypedArray<Dictionary> get_global_class_list();
	void refresh_global_class_list();
	void store_global_class_list(const Array &p_classes);
	String get_global_class_list_path() const;

	bool has_setting(const String &p_var) const;
	String localize_path(const String &p_path) const;
	String globalize_path(const String &p_path) const;

	void set_initial_value(const String &p_name, const Variant &p_value);
	void set_as_basic(const String &p_name, bool p_basic);
	void set_as_internal(const String &p_name, bool p_internal);
	void set_restart_if_changed(const String &p_name, bool p_restart);
	void set_ignore_value_in_docs(const String &p_name, bool p_ignore);
	bool get_ignore_value_in_docs(const String &p_name) const;
	void add_hidden_prefix(const String &p_prefix);

	String get_project_data_dir_name() const;
	String get_project_data_path() const;
	String get_resource_path() const;
	String get_imported_files_path() const;

	static ProjectSettings *get_singleton();

	void clear(const String &p_name);
	int get_order(const String &p_name) const;
	void set_order(const String &p_name, int p_order);
	void set_builtin_order(const String &p_name);
	bool is_builtin_setting(const String &p_name) const;

	Error setup(const String &p_path, const String &p_main_pack, bool p_upwards = false, bool p_ignore_override = false);

	Error load_custom(const String &p_path);
	Error save_custom(const String &p_path = "", const CustomMap &p_custom = CustomMap(), const Vector<String> &p_custom_features = Vector<String>(), bool p_merge_with_current = true);
	Error save();

	// A section-granular publish, for callers that must not rewrite the rest of
	// the file. `save_custom()` -> `_save_settings_text()` writes the header
	// comment plus every stored setting, so a caller that only wants to add one
	// `input/<action>` entry has to accept that the whole `project.godot` is
	// regenerated and every hand written comment in it is lost. Editing the text
	// from the caller side instead is not a way out either: the obvious
	// "insert the line after the `[input]` header" splice has a silent failure
	// when that section is not the last one, because the engine's own reader
	// attributes a key to the section that precedes it.
	//
	// `save_custom_section()` moves that text handling into the engine - the
	// engine serializes the target section with the same `VariantWriter` call
	// `_save_settings_text()` uses - and rewrites **only that section**. Every
	// other byte of the file is copied through untouched: comments, blank lines,
	// key order, a UTF-8 BOM and CRLF line endings included. Keys the section
	// already has are updated in place, new keys are appended to the section
	// (never to the wrong one), and a section that does not exist yet is created
	// at the end of the file in the shape `_save_settings_text()` writes. Keys
	// that are not named are never touched and never removed.
	//
	// Neither method changes the in-memory settings: they publish text into a
	// file, exactly like `save_custom()` does.
	//
	// `p_custom` is keyed by the **full** setting name (`"input/jump"`), and every
	// key must belong to `p_section` - the part before the first `/`. The name
	// inside the section may itself contain `/` (`rendering/renderer/...` is
	// stored under `[rendering]`), which is why only the first separator splits.
	Error save_custom_section(const String &p_path, const String &p_section, const CustomMap &p_custom);
	// TASK-067 (patch 3). The editor's own "save the project on open" call
	// (`editor/editor_node.cpp:1071`) - it must not be a different writer from the
	// section publish, or the editor would preserve comments while every tool
	// that writes one section does, and lose them the moment it opens the project
	// itself.
	//
	// It publishes **the settings `save()` would publish** (the same collection
	// `save_custom()` builds, section by section) into the file that is already
	// there, and copies every other byte through: comments, blank lines, key
	// order, a BOM and CRLF included. Unlike `save_custom_section()` it always
	// writes the file - the call site's stated purpose is to mark the project as
	// last modified (`editor/project_manager/project_list.cpp:866-869` reads that
	// timestamp as "last edited") - and it refreshes `get_last_saved_time()`, so
	// the editor's own external-change check
	// (`editor/editor_node.cpp:1627`) does not fire on the write it just made.
	//
	// It does not create a project: a missing `project.godot` is
	// `ERR_FILE_NOT_FOUND`, and the caller keeps `save()` for that (and for
	// binary projects).
	Error save_preserving_text();
	// The text half of `save_custom_section()`, without any I/O, so the exact
	// byte behaviour can be exercised on a string. `p_text` is the file as the
	// engine decodes it (a UTF-8 BOM, if the caller put one in, is ordinary
	// content of the first line and is therefore preserved).
	static Error update_settings_section_text(const String &p_text, const String &p_section, const CustomMap &p_custom, String &r_result);
	// TASK-067 (patch 3): the text half of `save_preserving_text()` - the same
	// per-section publish, applied to every named section in one pass over the
	// text (one read, one write, one rollback point instead of one per section).
	// `p_values` is keyed by full setting name; a section takes the keys whose
	// first `/`-separated part is its name, which is exactly the grouping
	// `_save_settings_text()` writes. `p_sections` fixes the order, so the result
	// is reproducible for a given input. It is static and free of I/O for the same
	// reason `update_settings_section_text()` is: the byte behaviour can be
	// exercised on a string without touching the running project's own file.
	static Error publish_settings_sections_text(const String &p_text, const Vector<String> &p_sections, const CustomMap &p_values, String &r_result);
	void set_custom_property_info(const PropertyInfo &p_info);
	const HashMap<StringName, PropertyInfo> &get_custom_property_info() const;
	uint64_t get_last_saved_time() { return last_save_time; }

	List<String> get_input_presets() const { return List<String>(input_presets); }

	Variant get_setting_with_override(const StringName &p_name) const;
	Variant get_setting_with_override_and_custom_features(const StringName &p_name, const Vector<String> &p_features) const;

	bool is_using_datapack() const;
	bool is_project_loaded() const;

	bool has_custom_feature(const String &p_feature) const;

	// Change tracking methods
	PackedStringArray get_changed_settings() const;
	bool check_changed_settings_in_group(const String &p_setting_prefix) const;

	const HashMap<StringName, AutoloadInfo> &get_autoload_list() const;
	void add_autoload(const AutoloadInfo &p_autoload, bool p_front_insert = false);
	void remove_autoload(const StringName &p_autoload);
	bool has_autoload(const StringName &p_autoload) const;
	AutoloadInfo get_autoload(const StringName &p_name) const;
	void fix_autoload_paths();

	const HashMap<StringName, String> &get_global_groups_list() const;
	void add_global_group(const StringName &p_name, const String &p_description);
	void remove_global_group(const StringName &p_name);
	bool has_global_group(const StringName &p_name) const;

	const HashMap<StringName, HashSet<StringName>> &get_scene_groups_cache() const;
	void add_scene_groups_cache(const StringName &p_path, const HashSet<StringName> &p_cache);
	void remove_scene_groups_cache(const StringName &p_path);
	void save_scene_groups_cache();
	String get_scene_groups_cache_path() const;
	void load_scene_groups_cache();

	// Testing a version allows fast cached GET_GLOBAL macros.
	uint32_t get_version() const { return _version; }

#ifdef TOOLS_ENABLED
	virtual void get_argument_options(const StringName &p_function, int p_idx, List<String> *r_options) const override;
#endif

	void set_editor_setting_override(const String &p_setting, const Variant &p_value);
	bool has_editor_setting_override(const String &p_setting) const;
	Variant get_editor_setting_override(const String &p_setting) const;

	ProjectSettings();
	ProjectSettings(const String &p_path);
	~ProjectSettings();
};

// Not a macro any longer.
Variant _GLOBAL_DEF(const String &p_var, const Variant &p_default, bool p_restart_if_changed = false, bool p_ignore_value_in_docs = false, bool p_basic = false, bool p_internal = false);
Variant _GLOBAL_DEF(const PropertyInfo &p_info, const Variant &p_default, bool p_restart_if_changed = false, bool p_ignore_value_in_docs = false, bool p_basic = false, bool p_internal = false);

#define GLOBAL_DEF(m_var, m_value) _GLOBAL_DEF(m_var, m_value)
#define GLOBAL_DEF_RST(m_var, m_value) _GLOBAL_DEF(m_var, m_value, true)
#define GLOBAL_DEF_NOVAL(m_var, m_value) _GLOBAL_DEF(m_var, m_value, false, true)
#define GLOBAL_DEF_RST_NOVAL(m_var, m_value) _GLOBAL_DEF(m_var, m_value, true, true)
#define GLOBAL_GET(m_var) ProjectSettings::get_singleton()->get_setting_with_override(m_var)

#define GLOBAL_DEF_BASIC(m_var, m_value) _GLOBAL_DEF(m_var, m_value, false, false, true)
#define GLOBAL_DEF_RST_BASIC(m_var, m_value) _GLOBAL_DEF(m_var, m_value, true, false, true)
#define GLOBAL_DEF_NOVAL_BASIC(m_var, m_value) _GLOBAL_DEF(m_var, m_value, false, true, true)
#define GLOBAL_DEF_RST_NOVAL_BASIC(m_var, m_value) _GLOBAL_DEF(m_var, m_value, true, true, true)

#define GLOBAL_DEF_INTERNAL(m_var, m_value) _GLOBAL_DEF(m_var, m_value, false, false, false, true)

/////////////////////////////////////////////////////////////////////////////////////////
// Cached versions of GLOBAL_GET.
// Cached but uses a typed variable for storage, this can be more efficient.
// Variables prefixed with _ggc_ to avoid shadowing warnings.
#define GLOBAL_GET_CACHED(m_type, m_setting_name) ([](const char *p_name) -> m_type {\
static_assert(std::is_trivially_destructible<m_type>::value, "GLOBAL_GET_CACHED must use a trivial type that allows static lifetime.");\
static m_type _ggc_local_var;\
static uint32_t _ggc_local_version = 0;\
static SpinLock _ggc_spin;\
uint32_t _ggc_new_version = ProjectSettings::get_singleton()->get_version();\
if (_ggc_local_version != _ggc_new_version) {\
	_ggc_spin.lock();\
	_ggc_local_version = _ggc_new_version;\
	_ggc_local_var = ProjectSettings::get_singleton()->get_setting_with_override(p_name);\
	m_type _ggc_temp = _ggc_local_var;\
	_ggc_spin.unlock();\
	return _ggc_temp;\
}\
_ggc_spin.lock();\
m_type _ggc_temp2 = _ggc_local_var;\
_ggc_spin.unlock();\
return _ggc_temp2; })(m_setting_name)
