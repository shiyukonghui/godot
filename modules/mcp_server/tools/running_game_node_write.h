/**************************************************************************/
/*  running_game_node_write.h                                             */
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

#include "../tool_registry.h"

#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// `Node` and `Object` are only ever used through a pointer by the helpers below,
// so the class names are forward declared instead of dragging `scene/` into this
// header.
class Node;
class Object;

namespace MCPTools {

// The component mapping of `running_game_set_node_property`: a JSON object names
// the components of a vector-shaped property (`{"x":1,"y":2}`),
// `property_value_from_json` deliberately keeps it a Dictionary, and
// `coerce_to_property_type` would otherwise convert it to the zero vector.
//
// A **null** answer means "an object of that type could not be built from this
// Dictionary": the target is vector-shaped and the object does not name its
// components. The tool turns that into a `-32602` instead of writing a zero.
//
// Declared here (rather than left file-private in the .cpp) for one reason: the
// doctest has to assert the real function, not a copy of it, and the defect this
// fixes was a *silent wrong value* that only a direct assertion pins
// (REPORT-012, the `position` evidence). Behaviour is documented at the
// definition.
Variant vector_from_dictionary(const Dictionary &p_value, Variant::Type p_target_type);

// The component names a vector-shaped type is built from, for refusal messages
// only, and the **empty string for every other type** (the empty answer is also
// the predicate `shape_vector_from_json` uses to decide whether an object is a
// component target at all):
//
//   `Vector2` / `Vector2i`  -> `"x" and "y"`
//   `Vector3` / `Vector3i`  -> `"x", "y" and "z"`
//   `Vector4` / `Vector4i`  -> `"x", "y", "z" and "w"`
//   `Color`                 -> `"r", "g" and "b"`
//   `Rect2` / `Rect2i`      -> `"x", "y", "width" and "height"`  (TASK-025 E-3)
//
// The list is exactly the set of types `vector_from_dictionary` folds, and it
// must stay that way: a composite type the read side answers as an object with
// no entry here is a value the module returns but cannot take back (TASK-025
// E-3, GDR-25 section 23.1 rules 1 and 4).
//
// Published by TASK-018 section 3 because
// `project_set_setting` writes a `Vector2`-valued project setting through the
// same rule and a group may not copy another group's file-private helper
// (PLAYBOOK section 2.4).
String vector_component_hint(Variant::Type p_target_type);

// The module's one "a JSON object that names a vector's components becomes that
// vector" step, and the refusal when it does not name them (or when a component
// cannot fill its own type):
//
//   * `p_json_value` is not a Dictionary (and not an array of the packed
//     vector-shaped targets), or the target is not vector-shaped -> `r_shaped` is
//     `p_json_value` unchanged;
//   * otherwise **every component is first pushed through
//     `coerce_to_property_type` with the type of the slot it fills** (TASK-020
//     section 1: `x`/`y`/`z` are `FLOAT` for `Vector2`/`Vector3`, `INT` for
//     `Vector2i`/`Vector3i`, `r`/`g`/`b`/`a` are `FLOAT` for `Color`), so a
//     component that cannot fill its slot is a `-32602` naming it
//     (`value.x`) instead of a `0.0` next to a success;
//   * TASK-021 A-3 adds `Vector4` (`x`/`y`/`z`/`w`, `FLOAT` each) to that table,
//     so a `PackedVector4Array`'s object elements are shaped like every other
//     packed vector array's;
//   * TASK-025 E-3 adds `Vector4i`, `Rect2` and `Rect2i` (the three composite
//     types the read side answers as objects - `serialize_variant` - but whose
//     write side had no component spelling, so the module refused a value it had
//     just produced). The rect components are named exactly as the read side
//     spells them (`x`, `y`, `width`, `height`), with the `REAL_T` slot for a
//     `Rect2` and the 32-bit `INT32` slot for a `Rect2i`;
//   * TASK-021 A-4 adds the **width of the member** the component is stored in: a
//     `real_t` (a `float` in this single-precision build) for the vector/colour
//     slots and an `int` (32-bit) for the `Vector2i`/`Vector3i` slots, so
//     `{"x": 1e300}` and `{"x": 3000000000}` on a `Vector2i` are `-32602` naming
//     the component instead of `inf` / a truncated int;
//   * an ARRAY for `PackedVector2Array`/`PackedVector3Array`/`PackedVector4Array`/
//     `PackedColorArray` applies the same gate per element (an object element is
//     shaped into its vector, a bad component is `-32602` naming `value[i].x`);
//   * a **null** answer from `vector_from_dictionary` (the object does not name
//     the components of the target type) is a `-32602` naming `p_parameter_name`
//     and `p_property`.
//
// TASK-018 section 3 hoists the three lines `write_node_property` used to carry
// so that `project_set_setting` produces the identical refusal for the identical
// mistake; the message is byte-identical to the one the node write has always
// answered for a missing component.
bool shape_vector_from_json(const Variant &p_json_value, Variant::Type p_target_type, const String &p_property,
		const String &p_parameter_name, Variant &r_shaped, MCPToolError &r_error);

// One property write on one resolved *object*: the *node independent* half of
// `running_game_set_node_property`, split out by TASK-014 for the reason the
// sibling helper above is declared here - the doctest binary has no `SceneTree`
// at all (`SceneTree::get_singleton() == nullptr`), so the property-existence
// refusal and the real write can only be asserted through an entry point that
// takes the object instead of resolving a `node_path` first. Behaviour is
// documented at the definition; the tool calls exactly this function.
//
// TASK-017 section 4 widened the receiver from `Node *` to `Object *`: the
// collision-shape setup of `editor_node_setup` has to write `shape_params` onto
// a created `Shape2D`/`Shape3D` *resource*, and the task requires that write to
// go through this one definition instead of a second property-write path. Every
// caller passes a `Node *` unchanged; for a node the `node_path` key of the
// answer is the node's path exactly as before, and for a non-node object it is
// the object's class name.
//
// Returns the result dictionary, or fills `r_error` and returns nil.
Variant write_node_property(Object *p_object, const String &p_property, const Variant &p_raw_value, MCPToolError &r_error);

// The **validation half** of the write above, with no write at all: resolves the
// property's declared type, refuses a name the object does not declare, applies
// the vector-component mapping and coerces the caller's JSON value, filling
// `r_converted` with the exact value `write_node_property` would hand to
// `Object::set()`.
//
// TASK-018 section 1.2 splits it out because a *batch* write must capture a
// value-level failure **before any write**: `editor_set_node_property_batch`
// uses this to validate the value against every matched node first, so a
// layout-incompatible value (`{"position": 1e20}`) refuses the whole call while
// nothing on any node has been touched - not even the first one. `write_node_property`
// itself is now this function plus `set()` plus the read-back, so the two can
// never disagree about what "fits" means.
bool prepare_node_property_value(Object *p_object, const String &p_property, const Variant &p_raw_value,
		Variant &r_converted, MCPToolError &r_error);

// ---------------------------------------------------------------------------
// TASK-028 G-1: the engine's **sub-property path** grammar.
//
// `position:y`, `v4:x`, `rect:position:x`, `material:shader_parameter/uv1_scale`
// are what `Object::set_indexed` / `Object::get_indexed` take
// (`core/object/object.h:697-698`), and the editor's own Inspector writes every
// component through them. `write_node_property` / `prepare_node_property_value`
// above take them as well now (the whole design, including the four slots a
// member can be stored in, is documented next to their implementation in
// `running_game_node_write.cpp`). These four entry points exist for the *other*
// members of the node-write family, which hold their own transaction state and
// therefore may not go through `write_node_property`:
//
//   * `editor_set_node_property_batch` pre-checks every matched node
//     (`node_property_path_exists`) and rolls back a partial write with the value
//     it read first (`read_node_property_path`);
//   * `project_set_node_property_across_scenes` applies an already-validated
//     value to an in-memory scene (`apply_node_property_value`).
//
// `split_property_path` implements the engine's `NodePath` property-path grammar
// (`core/string/node_path.cpp:419-452`): the first `:` separates the property
// from its subnames, a trailing `:` contributes nothing, and an empty subname in
// the middle is a `-32602` here where `NodePath` would print an engine ERR.
// ---------------------------------------------------------------------------

// `"position:y"` -> `["position", "y"]`. One `StringName` is always produced for
// a name without a `:`, so a malformed path is the only failure.
bool split_property_path(const String &p_property, Vector<StringName> &r_segments, MCPToolError &r_error);

// The value the path currently holds, read through the engine's own
// `get_indexed` (a single name goes through `get`, byte-identically to before).
Variant read_node_property_path(Object *p_object, const String &p_property, bool &r_valid, MCPToolError &r_error);

// Writes an **already gated** value to the path through the engine's own
// `set_indexed` (a single name goes through `set`, byte-identically to before).
// False with a `-32000` when the engine refuses the write itself.
bool apply_node_property_value(Object *p_object, const String &p_property, const Variant &p_value, MCPToolError &r_error);

// True when every segment of the path resolves on the object. `r_error` is the
// `-32602` of a malformed path, or the `-32001`/`-32602` of the segment that
// failed - which is what lets a caller keep its own wording for "missing" while
// still reporting a shape violation as one.
bool node_property_path_exists(Object *p_object, const String &p_property, MCPToolError &r_error);

} // namespace MCPTools

// TASK-012 section 1, group `running_game_node_write` of
// docs/tool-groups-b2.json: the single game-scope property write of B2
// (`running_game_set_node_property`), and the game-side header of the
// node-write family that B3 continues.
//
// It is its own group because it is one tool (`mutating = true`, `scope = game`)
// that shares the property-coercion helpers of `tools/tool_helpers.h` with the
// project/editor write groups; see the tool's implementation for its observable
// contract, including the range refusal that TASK-010 established for
// `coerce_to_property_type` (an out-of-range integer is a `-32602`, not a
// different number).
void register_running_game_node_write_tools(MCPToolRegistry &r_registry);