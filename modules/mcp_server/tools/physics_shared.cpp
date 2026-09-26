/**************************************************************************/
/*  physics_shared.cpp                                                    */
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
#include "physics_shared.h"

#include "tool_helpers.h"

#include "core/config/project_settings.h"

using namespace MCPTools;

namespace {

const char *const PHYSICS_LAYER_PROPERTIES[] = { "collision_layer", "collision_mask", nullptr };

const int PHYSICS_LAYER_COUNT = 32;

} // namespace

namespace MCPTools {

const char *const *physics_layer_property_names() {
	return PHYSICS_LAYER_PROPERTIES;
}

int physics_layer_property_count() {
	return 2;
}

bool is_physics_object(const Object *p_node) {
	if (p_node == nullptr) {
		return false;
	}
	return p_node->get_class_name() != StringName() && object_has_property(p_node, StringName("collision_layer"));
}

int physics_layer_count() {
	return PHYSICS_LAYER_COUNT;
}

String physics_layer_setting_prefix(const Object *p_node) {
	if (p_node == nullptr) {
		return String();
	}
	if (p_node->is_class("CollisionObject3D")) {
		return "layer_names/3d_physics";
	}
	if (p_node->is_class("CollisionObject2D")) {
		return "layer_names/2d_physics";
	}
	// A node that carries the members without being one of the two classes (a
	// script-defined class, or a compat node): the project setting to read is
	// chosen by the class name's dimension suffix, and a node with neither is not
	// a physics object at all.
	const String class_name = p_node->get_class();
	if (class_name.ends_with("3D")) {
		return "layer_names/3d_physics";
	}
	return "layer_names/2d_physics";
}

String physics_layer_name(const Object *p_node, int p_layer_number) {
	if (p_layer_number < 1 || p_layer_number > PHYSICS_LAYER_COUNT) {
		return String();
	}
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (settings == nullptr) {
		return String();
	}
	const String prefix = physics_layer_setting_prefix(p_node);
	if (prefix.is_empty()) {
		return String();
	}
	const String key = vformat("%s/layer_%d", prefix, p_layer_number);
	if (!settings->has_setting(key)) {
		return String();
	}
	return String(settings->get_setting(key));
}

Array physics_layer_bits(uint32_t p_mask) {
	Array bits;
	for (int i = 0; i < PHYSICS_LAYER_COUNT; i++) {
		if (p_mask & (1u << i)) {
			bits.push_back(i + 1);
		}
	}
	return bits;
}

Array physics_layer_names_of_mask(const Object *p_node, uint32_t p_mask) {
	Array names;
	for (int i = 0; i < PHYSICS_LAYER_COUNT; i++) {
		if (p_mask & (1u << i)) {
			names.push_back(physics_layer_name(p_node, i + 1));
		}
	}
	return names;
}

Dictionary physics_layers_record(Object *p_node, const String &p_node_path, MCPToolError &r_error) {
	if (!object_has_property(p_node, StringName("collision_layer")) ||
			!object_has_property(p_node, StringName("collision_mask"))) {
		r_error = MCPToolError::invalid_params(vformat(
				"Node '%s' is a %s and has no collision_layer/collision_mask: physics layers live on a "
				"CollisionObject2D/CollisionObject3D (CharacterBody2D, RigidBody3D, Area2D, ...)",
				p_node_path, p_node->get_class()));
		return Dictionary();
	}
	const uint32_t layer = (uint32_t)(int64_t)p_node->get(StringName("collision_layer"));
	const uint32_t mask = (uint32_t)(int64_t)p_node->get(StringName("collision_mask"));

	Dictionary out;
	out["node_path"] = p_node_path;
	out["node_type"] = p_node->get_class();
	out["dimension"] = p_node->is_class("CollisionObject3D") ? "3d" : "2d";
	out["collision_layer"] = (int64_t)layer;
	out["collision_mask"] = (int64_t)mask;
	out["collision_layer_bits"] = physics_layer_bits(layer);
	out["collision_mask_bits"] = physics_layer_bits(mask);
	out["collision_layer_names"] = physics_layer_names_of_mask(p_node, layer);
	out["collision_mask_names"] = physics_layer_names_of_mask(p_node, mask);
	out["layer_count"] = PHYSICS_LAYER_COUNT;
	return out;
}

} // namespace MCPTools
