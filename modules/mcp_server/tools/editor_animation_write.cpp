/**************************************************************************/
/*  editor_animation_write.cpp                                            */
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
#include "editor_animation_write.h"

#include "animation_shared.h"
#include "running_game_node_write.h"
#include "tool_helpers.h"

#include "core/io/json.h"
#include "core/io/resource_loader.h"
#include "core/variant/variant.h"
#include "scene/resources/animation_library.h"

// The registration functions below are at global scope and declare the
// `ToolBuilder` / schema / handler triple the same way every other group file
// does; the directive is what makes that read the same in all of them.
using namespace MCPTools;

// ---------------------------------------------------------------------------
// TASK-033 (B5 batch 1): the engine reference behind each tool of this group.
//
//   create_animation_on
//     * `AnimationMixer::get_animation_library(StringName())` /
//       `AnimationMixer::add_animation_library` (animation_mixer.cpp:405-408) -
//       the default library is the **empty** name (animation_mixer.cpp:162);
//     * `AnimationLibrary::add_animation(StringName, Ref<Animation>)`
//       (animation_library.cpp:49) - the one call that puts an animation into a
//       library, and the one that decides the name is legal;
//     * `Animation::set_length(double)` (animation.h:537).
//     Read back through `AnimationMixer::get_animation` (animation_mixer.cpp:409)
//     so "created" is the mixer's own answer, not ours.
//
//   add_animation_track_on
//     * `Animation::add_track(TrackType, int p_at_pos)` (animation.cpp, bound as
//       `add_track`) - creates the track and returns its index in one call;
//     * `Animation::track_set_path(int, NodePath)` (animation.h:428);
//     * `Animation::value_track_set_update_mode(int, UpdateMode)`
//       (animation.h:516) - the update mode exists **only** for a value track;
//     * `Animation::find_track(NodePath, TrackType)` (animation.h:430) - the
//       engine's own "is this track already here" lookup.
//
//   set_animation_keyframe_on
//     * `Animation::track_insert_key(int p_track, double p_time, const Variant
//       &p_key, real_t p_transition)` (animation.cpp:1719) - **one** call inserts
//       or replaces the key at that time *and* takes the easing (the engine's
//       `transition`); its return value is the key index, and it answers `-1`
//       when the key type does not match the track (animation.cpp:1727-1767),
//       which is why every key is type-checked before the call and the `-1` is
//       itself a refusal;
//     * `Animation::track_get_key_time` / `track_get_key_value` /
//       `track_get_key_transition` for the read-back.
//
//   remove_animation_on
//     * `AnimationLibrary::remove_animation(StringName)`
//       (animation_library.cpp) and `get_animation_list_size()` on both sides of
//       it, so `removed` is a real count (0 or 1) and not a claim.
//
// The migration source (`godot_mcp_gdext/src/commands/animation.rs`, category
// reference only) differs on three points, all recorded in REPORT-033 section 4:
// it read `length` into an `f32`, it dropped `position`/`update_mode` mistakes
// silently, and it answered `removed: true` without ever counting.
// ---------------------------------------------------------------------------

namespace MCPTools {

// The two file-local helpers the entry points below use before their own
// definitions at the bottom of this file.
static bool _key_value_for_track(const Variant &p_value, Animation::TrackType p_track_type, Variant &r_out,
		MCPToolError &r_error);
static String _animation_name_list_for_message(AnimationPlayer *p_player);

Ref<AnimationLibrary> animation_default_library(AnimationPlayer *p_player, MCPToolError &r_error) {
	// The engine's own default-library name is the empty `StringName`
	// (`animation_mixer.cpp:162`: a named library prefixes its animations with
	// "<library>/"). `get_animation_library` returns a null ref when there is no
	// such library yet, which is the normal state of a fresh AnimationPlayer.
	Ref<AnimationLibrary> library = p_player->get_animation_library(StringName());
	if (library.is_valid()) {
		return library;
	}
	library.instantiate();
	const Error add_error = p_player->add_animation_library(StringName(), library);
	if (add_error != OK) {
		r_error = MCPToolError::internal(vformat(
				"Cannot create the AnimationPlayer's default animation library: AnimationMixer::add_animation_library "
				"answered %s",
				VariantUtilityFunctions::error_string(add_error)));
		return Ref<AnimationLibrary>();
	}
	return library;
}

Ref<Animation> animation_named(AnimationPlayer *p_player, const String &p_name) {
	// `get_animation_or_null` is the non-erroring half of
	// `AnimationMixer::get_animation`; the tool decides whether a miss is a
	// refusal and answers with a suggestion instead of printing an engine error.
	return p_player->get_animation_or_null(StringName(p_name));
}

Vector<String> animation_names_in_default_library(AnimationPlayer *p_player) {
	Vector<String> names;
	Ref<AnimationLibrary> library = p_player->get_animation_library(StringName());
	if (library.is_null()) {
		return names;
	}
	// `AnimationLibrary::animations` is an `RBMap` ordered by `StringName::AlphCompare`
	// (animation_library.h:48), so this list is already sorted: the answer is
	// deterministic without a second sort (PLAYBOOK section 6.8).
	LocalVector<StringName> listed;
	library->get_animation_list(&listed);
	for (uint32_t i = 0; i < listed.size(); i++) {
		names.push_back(String(listed[i]));
	}
	return names;
}

Dictionary create_animation_on(AnimationPlayer *p_player, const String &p_animation_name, double p_length,
		MCPToolError &r_error) {
	if (!AnimationLibrary::is_valid_animation_name(p_animation_name)) {
		// The engine's own rule for the name (animation_library.cpp:37) - the
		// same one `add_animation` would refuse with an engine error, which a
		// caller would never see.
		r_error = MCPToolError::invalid_params(vformat(
				"'name' must be a legal animation name (AnimationLibrary::is_valid_animation_name): it must not be "
				"empty, must not contain '/' or ':' and must not be \".\" or \"..\"; got '%s'",
				p_animation_name));
		return Dictionary();
	}
	// The migration source cast the JSON number into an `f32`; the engine's own
	// member is a `double` (animation.h:292), so a double is what it gets.
	if (Math::is_nan(p_length) || Math::is_inf(p_length)) {
		r_error = MCPToolError::invalid_params("'length' must be a finite number");
		return Dictionary();
	}
	if (p_length < 0.0) {
		r_error = MCPToolError::invalid_params(vformat(
				"'length' must not be negative: Animation::set_length answers ERR_FAIL_COND for a negative length, "
				"so %f would leave the animation at its default instead of the length you asked for",
				p_length));
		return Dictionary();
	}
	Ref<AnimationLibrary> library = animation_default_library(p_player, r_error);
	if (library.is_null()) {
		return Dictionary();
	}
	if (library->has_animation(StringName(p_animation_name))) {
		r_error = MCPToolError::tool_state(
				vformat("Animation '%s' already exists in the AnimationPlayer's default library", p_animation_name),
				vformat("Remove it first (editor_remove_animation) or pick another name; the names this player already "
						"has are: %s",
						_animation_name_list_for_message(p_player)));
		return Dictionary();
	}

	Ref<Animation> animation;
	animation.instantiate();
	animation->set_length(p_length);
	const Error add_error = library->add_animation(StringName(p_animation_name), animation);
	if (add_error != OK) {
		r_error = MCPToolError::tool_state(
				vformat("AnimationLibrary::add_animation refused '%s': %s", p_animation_name,
						VariantUtilityFunctions::error_string(add_error)),
				"Pick a legal name (no '/', no ':', not '.' or '..') that the library does not already hold");
		return Dictionary();
	}

	// Read back: the animation the *mixer* answers with, which is the same flat
	// lookup every other tool of the family uses - "created" is therefore the
	// engine's answer and not a restatement of the request (TASK-033 section 1.4).
	Ref<Animation> stored = animation_named(p_player, p_animation_name);
	if (stored.is_null()) {
		r_error = MCPToolError::internal(vformat(
				"Animation '%s' was added to the default library but AnimationMixer::get_animation does not answer it",
				p_animation_name));
		return Dictionary();
	}

	Dictionary out;
	out["created"] = true;
	out["name"] = p_animation_name;
	// The engine's own name for the default library is the empty string; the
	// field is here so the caller can see which library was written.
	out["library"] = String();
	out["length"] = stored->get_length();
	out["track_count"] = stored->get_track_count();
	out["animation_count"] = library->get_animation_list_size();
	return out;
}

Dictionary add_animation_track_on(AnimationPlayer *p_player, const String &p_animation_name, const String &p_track_path,
		const String &p_track_type, const String &p_update_mode, bool p_update_mode_given, MCPToolError &r_error) {
	Ref<Animation> animation = animation_named(p_player, p_animation_name);
	if (animation.is_null()) {
		r_error = MCPToolError::not_found(vformat("Animation '%s' on AnimationPlayer '%s'", p_animation_name,
												  p_player->get_name()),
				vformat("This AnimationPlayer's default library holds: %s", _animation_name_list_for_message(p_player)));
		return Dictionary();
	}
	Animation::TrackType track_type = Animation::TYPE_VALUE;
	String reason;
	if (!animation_track_type_from_string(p_track_type, track_type, reason)) {
		r_error = MCPToolError::invalid_params(reason);
		return Dictionary();
	}
	if (p_track_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'track_path' must not be empty: it is the NodePath the track animates "
											   "(relative to the AnimationPlayer's 'root_node', e.g. \".:position\")");
		return Dictionary();
	}
	Animation::UpdateMode update_mode = Animation::UPDATE_CONTINUOUS;
	if (p_update_mode_given) {
		if (!animation_update_mode_from_string(p_update_mode, update_mode, reason)) {
			r_error = MCPToolError::invalid_params(reason);
			return Dictionary();
		}
		// `Animation::value_track_set_update_mode` is only defined for a value
		// track (animation.h:516); the migration source silently dropped the
		// argument for every other track type, which reads as "it was applied".
		if (track_type != Animation::TYPE_VALUE) {
			r_error = MCPToolError::invalid_params(vformat(
					"'update_mode' applies to a value track only (Animation::value_track_set_update_mode), and "
					"'track_type' is '%s'; drop the argument or ask for a value track",
					animation_track_type_name(track_type)));
			return Dictionary();
		}
	}

	const NodePath track_path(p_track_path);
	// The engine's own duplicate lookup, before the add, so the answer can point
	// at the track that was already there.
	const int previous_index = animation->find_track(track_path, track_type);
	const int track_index = animation->add_track(track_type, -1);
	if (track_index < 0 || track_index >= animation->get_track_count()) {
		r_error = MCPToolError::internal(vformat(
				"Animation::add_track answered %d for '%s' on animation '%s'", track_index, p_track_path, p_animation_name));
		return Dictionary();
	}
	animation->track_set_path(track_index, track_path);
	if (p_update_mode_given) {
		animation->value_track_set_update_mode(track_index, update_mode);
	}

	// Read back from the track the engine now holds.
	const NodePath stored_path = animation->track_get_path(track_index);
	const Animation::TrackType stored_type = animation->track_get_type(track_index);
	if (stored_type != track_type) {
		r_error = MCPToolError::internal(vformat(
				"The track created at index %d answers type '%s', not the requested '%s'",
				track_index, animation_track_type_name(stored_type), animation_track_type_name(track_type)));
		return Dictionary();
	}

	Dictionary out;
	out["animation"] = p_animation_name;
	out["track_index"] = track_index;
	out["track_path"] = String(stored_path);
	out["track_type"] = animation_track_type_name(stored_type);
	out["key_count"] = animation->track_get_key_count(track_index);
	// `-1` means the engine held no track with this path and type before this
	// call; a duplicate path/type pair is legal in Godot, so the caller is told
	// which one it now also has instead of being refused.
	out["previous_track_index"] = previous_index;
	if (stored_type == Animation::TYPE_VALUE) {
		out["update_mode"] = animation_update_mode_name(animation->value_track_get_update_mode(track_index));
	}
	return out;
}

Dictionary set_animation_keyframe_on(AnimationPlayer *p_player, const String &p_animation_name, int64_t p_track_index,
		double p_time, const Variant &p_value, double p_easing, MCPToolError &r_error) {
	Ref<Animation> animation = animation_named(p_player, p_animation_name);
	if (animation.is_null()) {
		r_error = MCPToolError::not_found(vformat("Animation '%s' on AnimationPlayer '%s'", p_animation_name,
												  p_player->get_name()),
				vformat("This AnimationPlayer's default library holds: %s", _animation_name_list_for_message(p_player)));
		return Dictionary();
	}
	const int track_count = animation->get_track_count();
	if (p_track_index < 0 || p_track_index >= (int64_t)track_count) {
		r_error = MCPToolError::not_found(vformat("Track index %d in animation '%s'", (int64_t)p_track_index, p_animation_name),
				vformat("'track_index' is the engine's own Animation::get_track_count index; '%s' has %d track(s) "
						"(0..%d) - call editor_get_animation_info to read them, or editor_add_animation_track to add one",
						p_animation_name, track_count, track_count - 1));
		return Dictionary();
	}
	if (Math::is_nan(p_time) || Math::is_inf(p_time)) {
		r_error = MCPToolError::invalid_params("'time' must be a finite number of seconds");
		return Dictionary();
	}
	// `easing` is the engine's `real_t p_transition`; the slot gate runs before
	// the cast below, so `1e300` is refused instead of landing as `inf`.
	MCPToolError easing_error;
	if (!value_fits_slot(p_easing, ValueSlot::REAL_T, "easing",
				"the real_t key transition this value is copied into (Animation::track_insert_key's p_transition)",
				easing_error)) {
		r_error = easing_error;
		return Dictionary();
	}
	if (p_easing < 0.0) {
		r_error = MCPToolError::invalid_params("'easing' must not be negative: it is the engine's key transition "
											   "(Animation::track_set_key_transition), which the engine itself clamps");
		return Dictionary();
	}

	const int track_index = (int)p_track_index;
	const Animation::TrackType track_type = animation->track_get_type(track_index);
	Variant key;
	if (!_key_value_for_track(p_value, track_type, key, r_error)) {
		return Dictionary();
	}

	// MCP-NARROWING: G24-ANIM-EASING - `value_fits_slot(REAL_T)` judged `p_easing`
	// immediately above, so this copy cannot narrow an unfit value.
	const int key_index = animation->track_insert_key(track_index, p_time, key, (real_t)p_easing);
	if (key_index < 0 || key_index >= animation->track_get_key_count(track_index)) {
		// The engine answers -1 from `track_insert_key` when the key does not
		// fit the track (animation.cpp:1727-1767). Refusing here is what keeps
		// "nothing was inserted" out of the success shape.
		r_error = MCPToolError::invalid_params(vformat(
				"Animation::track_insert_key refused the key for track %d (type '%s'): the key must be the shape that "
				"track type stores",
				track_index, animation_track_type_name(track_type)));
		return Dictionary();
	}

	// Read back through the engine's own accessors: `time`, `value` and `easing`
	// in the answer are what the animation now holds, not what was requested.
	Dictionary out;
	out["animation"] = p_animation_name;
	out["track_index"] = track_index;
	out["track_type"] = animation_track_type_name(track_type);
	out["key_index"] = key_index;
	out["time"] = animation->track_get_key_time(track_index, key_index);
	out["value"] = serialize_variant(animation->track_get_key_value(track_index, key_index));
	out["easing"] = animation->track_get_key_transition(track_index, key_index);
	out["key_count"] = animation->track_get_key_count(track_index);
	return out;
}

Dictionary remove_animation_on(AnimationPlayer *p_player, const String &p_animation_name, MCPToolError &r_error) {
	Ref<AnimationLibrary> library = p_player->get_animation_library(StringName());
	if (library.is_null()) {
		r_error = MCPToolError::not_found(vformat("The default animation library of AnimationPlayer '%s'",
												  p_player->get_name()),
				"This AnimationPlayer has no default library yet, so it holds no animation to remove; create one with "
				"editor_create_animation first");
		return Dictionary();
	}
	const int count_before = library->get_animation_list_size();
	if (!library->has_animation(StringName(p_animation_name))) {
		r_error = MCPToolError::not_found(
				vformat("Animation '%s' in the AnimationPlayer's default library", p_animation_name),
				vformat("The default library holds: %s. This tool removes from the default library only; an animation "
						"that lives in a named library is addressed by the mixer as \"<library>/<name>\"",
						_animation_name_list_for_message(p_player)));
		return Dictionary();
	}
	library->remove_animation(StringName(p_animation_name));
	const int count_after = library->get_animation_list_size();
	if (library->has_animation(StringName(p_animation_name)) || count_after != count_before - 1) {
		r_error = MCPToolError::internal(vformat(
				"AnimationLibrary::remove_animation('%s') left the library at %d animation(s) (was %d) - the count "
				"did not move by one",
				p_animation_name, count_after, count_before));
		return Dictionary();
	}

	Dictionary out;
	out["name"] = p_animation_name;
	out["library"] = String();
	// A real removal count: the library's own size before and after.
	out["removed"] = count_before - count_after;
	out["animation_count"] = count_after;
	return out;
}

// ---------------------------------------------------------------------------
// The key-value shapes, straight from `Animation::track_insert_key`.
//
// The engine's own dispatch (animation.cpp:1725-1828) is what decides whether a
// key fits a track, and it answers `-1` - "nothing was inserted" - when it does
// not. This function asks the same questions *first* so the caller gets a
// message naming the shape the track stores instead of a silent `-1`, and so the
// answer can never claim a key that the engine dropped.
// ---------------------------------------------------------------------------
static bool _key_component_value(const Variant &p_value, Variant::Type p_target_type, const String &p_expected,
		Variant &r_out, MCPToolError &r_error) {
	// The same two-step the node writers use: shape a JSON object into the
	// composite value (component by component, each through the module's one
	// width gate), then run the module's conversion gate. A Quaternion is part of
	// the read/write matrix since TASK-033 (REPORT-033 section 5.3), which is what
	// makes a rotation key readable and writable in one shape.
	Variant shaped;
	if (!shape_vector_from_json(p_value, p_target_type, "key", "value", shaped, r_error)) {
		return false;
	}
	if (shaped.get_type() != p_target_type) {
		r_error = MCPToolError::invalid_params(vformat(
				"'value' must be %s for this track (Animation::track_insert_key requires exactly that type); got %s",
				p_expected, Variant::get_type_name(p_value.get_type())));
		return false;
	}
	if (!coerce_to_property_type(shaped, p_target_type, r_out, r_error, "value")) {
		return false;
	}
	return true;
}

static bool _key_value_for_track(const Variant &p_value, Animation::TrackType p_track_type, Variant &r_out,
		MCPToolError &r_error) {
	switch (p_track_type) {
		case Animation::TYPE_VALUE: {
			// A value track stores the Variant itself (animation.cpp:1750), so
			// there is nothing to convert - and nothing to lose.
			r_out = p_value;
			return true;
		}
		case Animation::TYPE_POSITION_3D:
		case Animation::TYPE_SCALE_3D: {
			return _key_component_value(p_value, Variant::VECTOR3, "a Vector3 ({\"x\",\"y\",\"z\"})", r_out, r_error);
		}
		case Animation::TYPE_ROTATION_3D: {
			// The engine accepts a Quaternion or a Basis; only the quaternion has
			// a JSON shape in this module (and it is the shape the read side
			// answers), so a Basis is refused rather than silently defaulted.
			return _key_component_value(p_value, Variant::QUATERNION, "a quaternion ({\"x\",\"y\",\"z\",\"w\"})", r_out, r_error);
		}
		case Animation::TYPE_BLEND_SHAPE: {
			return _key_component_value(p_value, Variant::FLOAT, "a number", r_out, r_error);
		}
		case Animation::TYPE_METHOD: {
			if (p_value.get_type() != Variant::DICTIONARY) {
				r_error = MCPToolError::invalid_params(
						"'value' must be a method key: {\"method\": \"name\", \"args\": [...]} (Animation::track_insert_key reads exactly those two members)");
				return false;
			}
			const Dictionary key = p_value;
			if (key.get("method", Variant()).get_type() != Variant::STRING) {
				r_error = MCPToolError::invalid_params("'value.method' must be a string naming the method to call");
				return false;
			}
			if (key.get("args", Variant()).get_type() != Variant::ARRAY) {
				r_error = MCPToolError::invalid_params("'value.args' must be an array of arguments");
				return false;
			}
			r_out = key;
			return true;
		}
		case Animation::TYPE_BEZIER: {
			if (p_value.get_type() != Variant::ARRAY) {
				r_error = MCPToolError::invalid_params(
						"'value' must be a bezier key: [value, in_handle.x, in_handle.y, out_handle.x, out_handle.y]");
				return false;
			}
			const Array key = p_value;
			if (key.size() != 5) {
				r_error = MCPToolError::invalid_params(vformat(
						"'value' must hold exactly the five bezier members ([value, in_handle.x, in_handle.y, "
						"out_handle.x, out_handle.y]); got %d",
						key.size()));
				return false;
			}
			for (int i = 0; i < key.size(); i++) {
				const Variant::Type element_type = key[i].get_type();
				if (element_type != Variant::INT && element_type != Variant::FLOAT) {
					// `Animation::track_insert_key` folds `arr[i]` into a `real_t`
					// member, and a non-numeric Variant answers 0 there.
					r_error = MCPToolError::invalid_params(vformat(
							"'value[%d]' must be a number; a bezier key is five numbers and this engine's "
							"conversion of a %s into the real_t member answers 0 instead",
							i, Variant::get_type_name(element_type)));
					return false;
				}
			}
			r_out = key;
			return true;
		}
		case Animation::TYPE_AUDIO: {
			if (p_value.get_type() != Variant::DICTIONARY) {
				r_error = MCPToolError::invalid_params(
						"'value' must be an audio key: {\"stream\": \"res://...\", \"start_offset\": 0, \"end_offset\": 0}");
				return false;
			}
			const Dictionary key = p_value;
			Dictionary built;
			const char *const offsets[2] = { "start_offset", "end_offset" };
			for (int i = 0; i < 2; i++) {
				double offset = 0.0;
				if (!optional_float(key, offsets[i], 0.0, offset, r_error)) {
					return false;
				}
				// The engine's `AudioKey` members are `real_t`; the gate runs
				// before the engine's own copy, so `1e300` is refused here
				// instead of landing as `inf` in the key.
				MCPToolError slot_error;
				if (!value_fits_slot(offset, ValueSlot::REAL_T, vformat("value.%s", offsets[i]),
							"the real_t audio-key member this value is copied into", slot_error)) {
					r_error = slot_error;
					return false;
				}
				built[offsets[i]] = offset;
			}
			const Variant stream_value = key.get("stream", Variant());
			if (stream_value.get_type() == Variant::STRING && !((String)stream_value).is_empty()) {
				const Ref<Resource> stream = ResourceLoader::load((String)stream_value);
				if (stream.is_null()) {
					r_error = MCPToolError::not_found(vformat("Audio stream '%s'", (String)stream_value),
							"'value.stream' is loaded with ResourceLoader::load; give a res:// path that a "
							"ResourceLoader can load, or omit the member for a silent key");
					return false;
				}
				built["stream"] = stream;
			} else if (stream_value.get_type() != Variant::NIL) {
				r_error = MCPToolError::invalid_params("'value.stream' must be a res:// path string or omitted");
				return false;
			} else {
				built["stream"] = Variant();
			}
			r_out = built;
			return true;
		}
		case Animation::TYPE_ANIMATION: {
			const Variant::Type value_type = p_value.get_type();
			if (value_type != Variant::STRING && value_type != Variant::STRING_NAME) {
				// `TKey<StringName>::value = p_key` (animation.cpp:1824) reaches
				// `Variant::operator StringName()`, whose default branch answers
				// an empty name for anything that is not a string.
				r_error = MCPToolError::invalid_params(vformat(
						"'value' must be the animation name this track plays (a string); a %s would become the empty "
						"StringName in the key",
						Variant::get_type_name(value_type)));
				return false;
			}
			r_out = StringName((String)p_value);
			return true;
		}
	}
	r_error = MCPToolError::invalid_params(vformat("Unknown track type %d", (int)p_track_type));
	return false;
}

static String _animation_name_list_for_message(AnimationPlayer *p_player) {
	const Vector<String> names = animation_names_in_default_library(p_player);
	return names.is_empty() ? String("(the default library is empty)") : String(", ").join(names);
}

// ---------------------------------------------------------------------------
// The tools
// ---------------------------------------------------------------------------

static bool _require_float(const Dictionary &p_args, const String &p_key, double &r_out, MCPToolError &r_error) {
	if (!p_args.has(p_key)) {
		r_error = MCPToolError::invalid_params("Missing required parameter: " + p_key);
		return false;
	}
	return optional_float(p_args, p_key, 0.0, r_out, r_error);
}

// Every tool of the group takes the same `node_path` and needs the same two
// prerequisites (a running editor and an edited scene root). The argument
// contract of the caller's own tool runs *before* this, so a mistyped argument
// is still answered without an editor.
static AnimationPlayer *_editor_animation_player(const String &p_node_path, MCPToolError &r_error) {
	if (!require_editor_ui(r_error, "editor animation writes outside a running editor",
				"Start the MCP server inside the Godot editor to write editor state")) {
		return nullptr;
	}
	Node *root = edited_scene_root();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return nullptr;
	}
	return animation_player_node(root, p_node_path, r_error);
}

static Variant _tool_create_animation(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	String name;
	if (!require_string(p_args, "name", name, r_error)) {
		return Variant();
	}
	if (name.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'name' must not be empty");
		return Variant();
	}
	double length = 1.0;
	if (!optional_float(p_args, "length", 1.0, length, r_error)) {
		return Variant();
	}
	AnimationPlayer *player = _editor_animation_player(node_path, r_error);
	if (player == nullptr) {
		return Variant();
	}
	return create_animation_on(player, name, length, r_error);
}

static Variant _tool_add_animation_track(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	String animation;
	if (!require_string(p_args, "animation", animation, r_error)) {
		return Variant();
	}
	String track_path;
	if (!require_string(p_args, "track_path", track_path, r_error)) {
		return Variant();
	}
	String track_type;
	if (!optional_string(p_args, "track_type", "value", track_type, r_error)) {
		return Variant();
	}
	String update_mode;
	if (!optional_string(p_args, "update_mode", String(), update_mode, r_error)) {
		return Variant();
	}
	AnimationPlayer *player = _editor_animation_player(node_path, r_error);
	if (player == nullptr) {
		return Variant();
	}
	return add_animation_track_on(player, animation, track_path, track_type, update_mode,
			p_args.has("update_mode"), r_error);;
}

static Variant _tool_set_animation_keyframe(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	String animation;
	if (!require_string(p_args, "animation", animation, r_error)) {
		return Variant();
	}
	int64_t track_index = 0;
	if (!require_int(p_args, "track_index", track_index, r_error)) {
		return Variant();
	}
	double time = 0.0;
	if (!_require_float(p_args, "time", time, r_error)) {
		return Variant();
	}
	if (!p_args.has("value")) {
		r_error = MCPToolError::invalid_params("Missing required parameter: value");
		return Variant();
	}
	const Variant value = p_args["value"];
	double easing = 1.0;
	if (!optional_float(p_args, "easing", 1.0, easing, r_error)) {
		return Variant();
	}
	AnimationPlayer *player = _editor_animation_player(node_path, r_error);
	if (player == nullptr) {
		return Variant();
	}
	return set_animation_keyframe_on(player, animation, track_index, time, value, easing, r_error);
}

static Variant _tool_remove_animation(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'node_path' must not be empty");
		return Variant();
	}
	String name;
	if (!require_string(p_args, "name", name, r_error)) {
		return Variant();
	}
	if (name.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("'name' must not be empty");
		return Variant();
	}
	AnimationPlayer *player = _editor_animation_player(node_path, r_error);
	if (player == nullptr) {
		return Variant();
	}
	return remove_animation_on(player, name, r_error);
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------
//
// The authoritative `description` and `inputSchema` of each tool are the
// contract entries of docs/tools_list.renamed.json, character for character; the
// schemas are *parsed* from the exact contract JSON instead of being rebuilt as
// a hand-written Dictionary, because gate 1 compares all three fields verbatim.
// ---------------------------------------------------------------------------
static Dictionary _schema_from_json(const char *p_json) {
	JSON json;
	if (json.parse(String::utf8(p_json)) != OK) {
		ERR_PRINT("MCPTools: invalid inputSchema literal in editor_animation_write.cpp");
		return Dictionary();
	}
	return json.get_data();
}

void register_editor_animation_write_tools(MCPToolRegistry &r_registry) {
	{
		ToolBuilder builder("editor_create_animation", String::utf8(R"desc(创建动画)desc"));
		builder.channel("editor").verb("create").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"length":{"default":1.0,"type":"number"},"name":{"type":"string"},"node_path":{"type":"string"}},"required":["node_path","name"],"type":"object"})schema"));
		builder.handler(MCPTools::_tool_create_animation).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_add_animation_track", String::utf8(R"desc(在指定动画中添加轨道)desc"));
		builder.channel("editor").verb("add").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"animation":{"type":"string"},"node_path":{"type":"string"},"track_path":{"type":"string"},"track_type":{"default":"value","type":"string"},"update_mode":{"type":"string"}},"required":["node_path","animation","track_path"],"type":"object"})schema"));
		builder.handler(MCPTools::_tool_add_animation_track).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_set_animation_keyframe", String::utf8(R"desc(在指定轨道的指定时间插入或更新关键帧)desc"));
		builder.channel("editor").verb("set").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"animation":{"type":"string"},"easing":{"default":1.0,"type":"number"},"node_path":{"type":"string"},"time":{"type":"number"},"track_index":{"type":"integer"},"value":{}},"required":["node_path","animation","track_index","time","value"],"type":"object"})schema"));
		builder.handler(MCPTools::_tool_set_animation_keyframe).register_into(r_registry);
	}

	{
		ToolBuilder builder("editor_remove_animation", String::utf8(R"desc(从 AnimationPlayer 的默认库中删除指定动画)desc"));
		builder.channel("editor").verb("remove").scope(MCPToolScope::EDITOR).mutating(true);
		builder.schema(_schema_from_json(R"schema({"properties":{"name":{"type":"string"},"node_path":{"type":"string"}},"required":["node_path","name"],"type":"object"})schema"));
		builder.handler(MCPTools::_tool_remove_animation).register_into(r_registry);
	}
}