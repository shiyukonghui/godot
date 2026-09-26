/**************************************************************************/
/*  running_game_node_write.cpp                                           */
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
#include "running_game_node_write.h"

#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/string/string_name.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// running_game_set_node_property (old `set_game_node_property`)
//
// The one game-scope property write of B2, and the game-side header of the
// node-write family B3 completes (docs/tool-groups-b2.json).
//
// Migration source (semantic reference, read-only):
// `godot_mcp_gdext/src/commands/runtime.rs:240-253` (a `send_game_command`
// forwarder) and its game-side handler
// `addons/godot_mcp/mcp_game_inspector_service.gd:575-607`.
//
// Observable contract (as implemented):
//   * `node_path` (string, required; blank -> `-32602`), `property` (string,
//     required; blank -> `-32602`), `value` (**required, any JSON type** -
//     present-but-null is a legitimate value and is therefore not "missing");
//   * the node is resolved with the shared `resolve_game_node` semantics every
//     game-side `node_path` tool uses;
//   * the answer is the before/after pair
//     `{"node_path": <resolved absolute path>, "property": ..., "old_value":
//       <serialized>, "new_value": <serialized>}` - the migration source's key
//     set with the resolved path substituted for the echoed argument
//     (PLAYBOOK section 6.7);
//   * the value is coerced to the property's own type through the module's
//     single `property_type_of` / `coerce_to_property_type` pair (the helpers
//     TASK-009 hoisted and TASK-010 hardened), so an `int` property written from
//     JSON's one number type stays an `int` and a `#rrggbb` string reaches a
//     `Color` property;
//   * an out-of-range or non-finite number for an integer property -> `-32602`
//     with `Parameter 'value' ...` (the TASK-010 semantics: a caller who asked
//     for an integer and sent `1e20` is refused, not given a different number);
//   * no current scene -> `-32000`; the node is not there -> `-32001` with a
//     suggestion; **a property the node does not have -> `-32001` with a
//     suggestion** (TASK-014 D-1, see below);
//   * the write is **observed**, not assumed: the answer's `new_value` is read
//     back from the object after `Object::set()`, so a property that silently
//     refuses the value (a setter that clamps, a read-only property) shows up as
//     a `new_value` that did not become `value` instead of a false success.
//
// TASK-014 D-1 (the M2 acceptance's honesty defect): this tool used to answer a
// **success shape** for a property the node does not have -
// `{"old_value":null,"new_value":null}` - because `property_type_of` answers
// `Variant::NIL` for an unknown name, `Object::set()` on an unknown name is a
// silent no-op and the read-back therefore also answers null. A caller that only
// branches on "error or not" read "nothing happened" as "written". The migration
// source is worse rather than better here (its `mcp_runtime_agent.gd:159-160`
// answers an unconditional `set: true`), so this is not a divergence from the
// reference but the "the tool really works" standard of PLAYBOOK section 6.6 -
// recorded there as its seventh measured case. `write_node_property` now asks
// the object whether the property exists before it writes anything.
//
// Deviation from the migration source: it parsed the incoming value against
// `typeof(old_value)` with its own hand-written dictionary->Vector/Color
// conversions (`mcp_game_inspector_service.gd:610-660`), which has no case for a
// *string* spelling of a Vector and no range guard for integers. This
// implementation reuses the module's one coercion helper instead, which is what
// gives it the documented `-32602` refusals above.
// ---------------------------------------------------------------------------
// JSON has no vector type, so a caller names the components: `{"x":1,"y":2}`.
// The component mapping and the whole per-node write live in
// `write_node_property` below (TASK-014 split it out of the tool so that the
// doctest can reach it without a `SceneTree`); its comment carries the argument
// for the mapping and for the refusal that replaces the silent zero vector.
// `vector_from_dictionary` folds the components this function has already
// checked. **Every narrowing cast below is safe because
// `_check_components`/`shape_vector_from_json` runs first** (TASK-020 section 1,
// TASK-021 A-3/A-4, TASK-023 D-15 for `Color`): each object that reaches this
// function has been rebuilt with every component either passed through
// `coerce_to_property_type` or judged by `_component_fits_slot`, so a narrowing
// cast can only ever see a value that fits the slot it is copied into. The
// comment is the TASK-023 D-7 scan marker for the constructors below (nine
// types since TASK-025 E-3 added `Vector4i`/`Rect2`/`Rect2i`).
namespace MCPTools {

Variant vector_from_dictionary(const Dictionary &p_value, Variant::Type p_target_type) {
Variant vector_from_dictionary(const Dictionary &p_value, Variant::Type p_target_type) {
	switch (p_target_type) {
		case Variant::VECTOR2: {
			if (!p_value.has("x") || !p_value.has("y")) {
				return Variant();
			}
			// MCP-NARROWING: G24-NW-COMPONENTS - every object reaching this
			// function was rebuilt by `_check_components` + this line's own
			// call, so the cast cannot narrow an unfit value.
			return Vector2((real_t)(double)p_value["x"], (real_t)(double)p_value["y"]);
		}
		case Variant::VECTOR2I: {
			if (!p_value.has("x") || !p_value.has("y")) {
				return Variant();
			}
			// MCP-NARROWING: G24-NW-COMPONENTS - see above (`INT32` slot).
			return Vector2i((int)p_value["x"], (int)p_value["y"]);
		}
		case Variant::VECTOR3: {
			if (!p_value.has("x") || !p_value.has("y") || !p_value.has("z")) {
				return Variant();
			}
			// MCP-NARROWING: G24-NW-COMPONENTS - see above.
			return Vector3((real_t)(double)p_value["x"], (real_t)(double)p_value["y"], (real_t)(double)p_value["z"]);
		}
		case Variant::VECTOR3I: {
			if (!p_value.has("x") || !p_value.has("y") || !p_value.has("z")) {
				return Variant();
			}
			// MCP-NARROWING: G24-NW-COMPONENTS - see above (`INT32` slot).
			return Vector3i((int)p_value["x"], (int)p_value["y"], (int)p_value["z"]);
		}
		// TASK-021 A-3: `Vector4` is a vector-shaped type the engine has and the
		// conversion relation lists (`VECTOR4I`, `NIL`); it had no component
		// spelling here, so `PackedVector4Array`'s object elements could not be
		// shaped the way a `Vector2`/`Vector3`/`Color` element is. The four
		// components are its own (`x`/`y`/`z`/`w`).
		case Variant::VECTOR4: {
			if (!p_value.has("x") || !p_value.has("y") || !p_value.has("z") || !p_value.has("w")) {
				return Variant();
			}
			// MCP-NARROWING: G24-NW-COMPONENTS - see above.
			return Vector4((real_t)(double)p_value["x"], (real_t)(double)p_value["y"], (real_t)(double)p_value["z"], (real_t)(double)p_value["w"]);
		}
		case Variant::COLOR: {
			if (!p_value.has("r") || !p_value.has("g") || !p_value.has("b")) {
				return Variant();
			}
			// MCP-NARROWING: G24-NW-COMPONENTS - see above. The `Color` slot is
			// `COMPONENT_WIDTH_FLOAT32` (GDR-24), not `REAL_T`.
			// MCP-NARROWING: G24-NW-COMPONENTS - the four casts below (the `a`
			// one is on the continuation line) are the same pre-gated narrowing.
			return Color((real_t)(double)p_value["r"], (real_t)(double)p_value["g"], (real_t)(double)p_value["b"],
					// MCP-NARROWING: G24-NW-COMPONENTS - the `a` component.
					p_value.has("a") ? (real_t)(double)p_value["a"] : 1.0f);
		}
		// -------------------------------------------------------------------
		// TASK-025 E-3 (the write half): the three shapes the read side has
		// answered as objects since TASK-024b but the write side had no
		// component spelling for - `Vector4i`, `Rect2` and `Rect2i`.
		//
		// The whole point of E-3 is that a value the module *returns* can be
		// fed straight back (GDR-25 section 23.1 rules 1 and 4). A read-back of
		// `Vector4i(1,2,3,4)` is `{"x":1,"y":2,"z":3,"w":4}` and a read-back of
		// `Rect2i(1,2,30,40)` is `{"x":1,"y":2,"width":30,"height":40}`; without
		// a case here the object went to `coerce_to_property_type` untouched,
		// `Variant::can_convert(DICTIONARY, VECTOR4I/RECT2I)` is false, and the
		// call answered `-32602` for a value this very module had just produced
		// (measured in the TASK-024b evidence run, checks `GAP_v4i_*` /
		// `GAP_rect_i_*`). `Rect2`'s object read shape predates TASK-024b and
		// was refused for the same reason.
		//
		// The members are the engine's own (`core/math/vector4.h`'s x/y/z/w,
		// `core/math/rect2.h`'s `position.x/position.y/size.x/size.y`), and the
		// casts are the same pre-gated ones as the cases above: `_check_components`
		// rebuilt every component through `coerce_to_property_type` and
		// `_component_fits_slot` first (`INT32` for the `i` types, `REAL_T` for
		// `Rect2`), so no cast below can narrow a value that was not judged.
		// -------------------------------------------------------------------
		case Variant::VECTOR4I: {
			if (!p_value.has("x") || !p_value.has("y") || !p_value.has("z") || !p_value.has("w")) {
				return Variant();
			}
			// MCP-NARROWING: G24-NW-COMPONENTS - see above (`INT32` slot).
			return Vector4i((int)p_value["x"], (int)p_value["y"], (int)p_value["z"], (int)p_value["w"]);
		}
		case Variant::RECT2I: {
			if (!p_value.has("x") || !p_value.has("y") || !p_value.has("width") || !p_value.has("height")) {
				return Variant();
			}
			// MCP-NARROWING: G24-NW-RECT-COMPONENTS - see the `Rect2` case below
			// (`INT32` slot for the two `Vector2i` members of a `Rect2i`).
			return Rect2i((int)p_value["x"], (int)p_value["y"], (int)p_value["width"], (int)p_value["height"]);
		}
		case Variant::RECT2: {
			if (!p_value.has("x") || !p_value.has("y") || !p_value.has("width") || !p_value.has("height")) {
				return Variant();
			}
			// MCP-NARROWING: G24-NW-RECT-COMPONENTS - every component was rebuilt
			// by `_check_components` with the `REAL_T` slot above (`Rect2` stores
			// `real_t` members), so the four casts on the line below cannot narrow
			// an unfit value.
			return Rect2((real_t)(double)p_value["x"], (real_t)(double)p_value["y"], (real_t)(double)p_value["width"], (real_t)(double)p_value["height"]);
		}
		default: {
			// Not a vector-shaped type: nothing to map, and no component naming
			// to demand. The caller passes objects of every other type straight
			// through to `coerce_to_property_type`.
			return p_value;
		}
	}
}

} // namespace MCPTools

namespace MCPTools {

// The component names a vector-shaped type is built from, for the refusal
// message only (`vector_from_dictionary` is the one that decides). Published as
// `MCPTools::vector_component_hint` since TASK-018 section 3: the project
// setting write needs the identical wording.
String vector_component_hint(Variant::Type p_target_type) {
	switch (p_target_type) {
		case Variant::VECTOR2:
		case Variant::VECTOR2I:
			return "\"x\" and \"y\"";
		case Variant::VECTOR3:
		case Variant::VECTOR3I:
			return "\"x\", \"y\" and \"z\"";
		case Variant::VECTOR4:
		case Variant::VECTOR4I:
			return "\"x\", \"y\", \"z\" and \"w\"";
		case Variant::COLOR:
			return "\"r\", \"g\" and \"b\"";
		// TASK-025 E-3: a `Rect2`/`Rect2i` is read back as the four members of
		// its two `Vector2`/`Vector2i` halves (TASK-024b), so the components the
		// write side asks for are named the way the read side spells them.
		case Variant::RECT2:
		case Variant::RECT2I:
			return "\"x\", \"y\", \"width\" and \"height\"";
		default:
			return String();
	}
}

// ---------------------------------------------------------------------------
// TASK-020 section 1 (D-1) - the components of a composite value.
//
// `vector_component_hint` above names the components; this table says what each
// one **is**. It is the fact the engine does not carry: a `Vector2` property is
// one `Variant::VECTOR2` in `PropertyInfo`, not an x and a y, so nothing in the
// conversion relation can tell "the string `"abc"` in the x slot" from "the
// string `"abc"` for the whole property". Measured by the M4 acceptance: the
// whole-property form is refused (`can_convert(STRING, VECTOR2)` is false), while
// `{"x":"abc"}` was folded by `vector_from_dictionary`'s `(double)` cast into
// `0.0` and the call answered `code=0`.
//
// The table is the minimal one the module's own component mapping supports
// (`vector_from_dictionary` folds exactly these types); the struct types have
// no component spelling in this build and are refused by the conversion relation
// as they always were. TASK-021 A-3 adds `Vector4` (the four components of
// `PackedVector4Array`'s element) to the same table; TASK-025 E-3 adds the three
// types whose read-back shape TASK-024b made an object but whose write side had
// no spelling at all - `Vector4i`, `Rect2` and `Rect2i`. The rule for what
// belongs here is now the round trip, not an enumeration: **everything
// `serialize_variant` answers for a composite target must have a component
// spelling here**, which is what makes the returned value feedable straight
// back (GDR-25 section 23.1 rules 1 and 4).
//
// TASK-021 A-4 adds the **width** of the slot each component is stored in. The
// gate below judges the component against FLOAT/INT, which is what the engine's
// conversion relation knows; the C++ member is narrower than that:
//
//   * a `Vector2`/`Vector3`/`Vector4`/`Color` component is a `real_t` - a
//     **float** in this build (`precision` defaults to `single`,
//     `SConstruct:192`), so `{"x": 1e300}` used to become `inf` inside the
//     vector;
//   * a `Vector2i`/`Vector3i` component is an `int` (32-bit), and
//     `vector_from_dictionary`'s `(int)` cast truncated an int64 that did not
//     fit.
//
// Both were silent: the call answered `code=0` and the property held a value
// nobody asked for.
// ---------------------------------------------------------------------------
enum _ComponentWidth {
	// A `real_t` slot: as wide as `float` unless the build is double precision.
	COMPONENT_WIDTH_REAL,
	// A `float` slot **in every build** (GDR-24 / TASK-023 D-15): `Color`'s
	// components are declared `float r,g,b,a` (`core/math/color.h:39-42`), so in
	// a `precision=double` build the `real_t` slot above would accept `1e300`
	// and `Color(...)` would store `inf`.
	COMPONENT_WIDTH_FLOAT32,
	// An `int` slot (32-bit).
	COMPONENT_WIDTH_INT32,
};

struct _VectorComponent {
	const char *name;
	Variant::Type type;
	_ComponentWidth width;
};

static int _vector_components(Variant::Type p_target_type, _VectorComponent *r_out) {
	int count = 0;
	switch (p_target_type) {
		case Variant::VECTOR2: {
			r_out[count++] = _VectorComponent{ "x", Variant::FLOAT, COMPONENT_WIDTH_REAL };
			r_out[count++] = _VectorComponent{ "y", Variant::FLOAT, COMPONENT_WIDTH_REAL };
		} break;
		case Variant::VECTOR2I: {
			r_out[count++] = _VectorComponent{ "x", Variant::INT, COMPONENT_WIDTH_INT32 };
			r_out[count++] = _VectorComponent{ "y", Variant::INT, COMPONENT_WIDTH_INT32 };
		} break;
		case Variant::VECTOR3: {
			r_out[count++] = _VectorComponent{ "x", Variant::FLOAT, COMPONENT_WIDTH_REAL };
			r_out[count++] = _VectorComponent{ "y", Variant::FLOAT, COMPONENT_WIDTH_REAL };
			r_out[count++] = _VectorComponent{ "z", Variant::FLOAT, COMPONENT_WIDTH_REAL };
		} break;
		case Variant::VECTOR3I: {
			r_out[count++] = _VectorComponent{ "x", Variant::INT, COMPONENT_WIDTH_INT32 };
			r_out[count++] = _VectorComponent{ "y", Variant::INT, COMPONENT_WIDTH_INT32 };
			r_out[count++] = _VectorComponent{ "z", Variant::INT, COMPONENT_WIDTH_INT32 };
		} break;
		case Variant::VECTOR4: {
			r_out[count++] = _VectorComponent{ "x", Variant::FLOAT, COMPONENT_WIDTH_REAL };
			r_out[count++] = _VectorComponent{ "y", Variant::FLOAT, COMPONENT_WIDTH_REAL };
			r_out[count++] = _VectorComponent{ "z", Variant::FLOAT, COMPONENT_WIDTH_REAL };
			r_out[count++] = _VectorComponent{ "w", Variant::FLOAT, COMPONENT_WIDTH_REAL };
		} break;
		// TASK-025 E-3: the integer twin of `Vector4`, and the rect family -
		// the shapes the read side answers as objects. Same components, same
		// slot widths as the members the engine declares
		// (`core/math/vector4.h`: `int32_t x,y,z,w` for `Vector4i`;
		// `core/math/rect2.h`: `Point2 position; Size2 size;`, i.e. `real_t`
		// members for `Rect2` and `int32_t` members for `Rect2i`).
		case Variant::VECTOR4I: {
			r_out[count++] = _VectorComponent{ "x", Variant::INT, COMPONENT_WIDTH_INT32 };
			r_out[count++] = _VectorComponent{ "y", Variant::INT, COMPONENT_WIDTH_INT32 };
			r_out[count++] = _VectorComponent{ "z", Variant::INT, COMPONENT_WIDTH_INT32 };
			r_out[count++] = _VectorComponent{ "w", Variant::INT, COMPONENT_WIDTH_INT32 };
		} break;
		case Variant::COLOR: {
			// GDR-24: `Color`'s four components are `float` in every build, so
			// this is not the `REAL_T` slot the vector types use.
			r_out[count++] = _VectorComponent{ "r", Variant::FLOAT, COMPONENT_WIDTH_FLOAT32 };
			r_out[count++] = _VectorComponent{ "g", Variant::FLOAT, COMPONENT_WIDTH_FLOAT32 };
			r_out[count++] = _VectorComponent{ "b", Variant::FLOAT, COMPONENT_WIDTH_FLOAT32 };
			r_out[count++] = _VectorComponent{ "a", Variant::FLOAT, COMPONENT_WIDTH_FLOAT32 };
		} break;
		// TASK-025 E-3: the two halves of a `Rect2`/`Rect2i`, named exactly the
		// way `serialize_variant` spells them (`position.x`, `position.y`,
		// `size.x`, `size.y` -> `x`, `y`, `width`, `height`).
		case Variant::RECT2: {
			r_out[count++] = _VectorComponent{ "x", Variant::FLOAT, COMPONENT_WIDTH_REAL };
			r_out[count++] = _VectorComponent{ "y", Variant::FLOAT, COMPONENT_WIDTH_REAL };
			r_out[count++] = _VectorComponent{ "width", Variant::FLOAT, COMPONENT_WIDTH_REAL };
			r_out[count++] = _VectorComponent{ "height", Variant::FLOAT, COMPONENT_WIDTH_REAL };
		} break;
		case Variant::RECT2I: {
			r_out[count++] = _VectorComponent{ "x", Variant::INT, COMPONENT_WIDTH_INT32 };
			r_out[count++] = _VectorComponent{ "y", Variant::INT, COMPONENT_WIDTH_INT32 };
			r_out[count++] = _VectorComponent{ "width", Variant::INT, COMPONENT_WIDTH_INT32 };
			r_out[count++] = _VectorComponent{ "height", Variant::INT, COMPONENT_WIDTH_INT32 };
		} break;
		default:
			break;
	}
	return count;
}

// TASK-021 A-4: does one already-coerced component fit the member it is stored
// in? The refusal names the component (`value.x`) and states what the mapping
// would have written - the same shape as the element-width refusal of
// `coerce_to_property_type` (TASK-021 A-2).
//
// TASK-022 D-4: the judgement itself is **not** here any more. It is the one
// `MCPTools::value_fits_slot` (`tools/tool_helpers.*`, GDR-22), shared with the
// scalar member, the packed element and the `ProjectSettings` case. This function
// only maps the component table's own vocabulary onto that gate's `ValueSlot`, so
// there is exactly one place where "does this value survive the copy" is decided -
// which is the point: three consecutive tasks each added a *shape* to the width
// judgement and each time the next shape was missed.
static bool _component_fits_slot(const Variant &p_component, _ComponentWidth p_width,
		const String &p_parameter_name, MCPToolError &r_error) {
	if (p_width == COMPONENT_WIDTH_INT32) {
		return value_fits_slot(p_component, ValueSlot::INT32, p_parameter_name,
				"the 32-bit signed integer component this property stores", r_error);
	}
	if (p_width == COMPONENT_WIDTH_FLOAT32) {
		// GDR-24: a `Color` component is a `float` even in a double-precision
		// build, so it uses the build-independent slot.
		return value_fits_slot(p_component, ValueSlot::FLOAT32, p_parameter_name,
				"the 32-bit float component this property stores (a Color component, a float in every build)", r_error);
	}
	return value_fits_slot(p_component, ValueSlot::REAL_T, p_parameter_name,
			"the 32-bit float component this property stores", r_error);
}

// The object's components, each one pushed through the module's one gate before
// it is folded. A component that is not laid out for its own type (a string that
// spells no number, `null`, an object, an array, a non-finite number, an
// out-of-range integer) produces the `-32602` of `coerce_to_property_type` and
// the parameter name carries the component (`value.x`), so the caller is told
// which slot failed. A member that is not a component of the target is copied
// unchanged: `vector_from_dictionary` ignores it, exactly as before.
static bool _check_components(const Dictionary &p_value, Variant::Type p_target_type,
		const String &p_parameter_name, Dictionary &r_checked, MCPToolError &r_error) {
	_VectorComponent components[4];
	const int count = _vector_components(p_target_type, components);
	const Array keys = p_value.keys();
	r_checked.clear();
	for (int i = 0; i < keys.size(); i++) {
		const String key = keys[i];
		bool known = false;
		for (int c = 0; c < count; c++) {
			if (key == components[c].name) {
				const String slot_name = vformat("%s.%s", p_parameter_name, components[c].name);
				Variant component;
				if (!coerce_to_property_type(p_value[key], components[c].type, component, r_error, slot_name)) {
					return false;
				}
				// TASK-021 A-4: the component passed the gate for FLOAT/INT; the
				// member it is stored in is narrower (a `real_t`, an `int`), and
				// the mapping's own cast used to truncate silently.
				if (!_component_fits_slot(component, components[c].width, slot_name, r_error)) {
					return false;
				}
				r_checked[key] = component;
				known = true;
				break;
			}
		}
		if (!known) {
			r_checked[key] = p_value[key];
		}
	}
	return true;
}

// The element type of a packed *vector-shaped* array, or `Variant::NIL` when the
// target is not one. `shape_vector_from_json` uses it to shape the objects inside
// the array with the very component gate above.
static Variant::Type _packed_vector_element_type(Variant::Type p_target_type) {
	switch (p_target_type) {
		case Variant::PACKED_VECTOR2_ARRAY: {
			return Variant::VECTOR2;
		}
		case Variant::PACKED_VECTOR3_ARRAY: {
			return Variant::VECTOR3;
		}
		case Variant::PACKED_VECTOR4_ARRAY: {
			// TASK-021 A-3: the element type `coerce_to_property_type` already
			// knew (`_container_element_type`) now has a component spelling too.
			return Variant::VECTOR4;
		}
		case Variant::PACKED_COLOR_ARRAY: {
			return Variant::COLOR;
		}
		default: {
			return Variant::NIL;
		}
	}
}

bool shape_vector_from_json(const Variant &p_json_value, Variant::Type p_target_type, const String &p_property,
		const String &p_parameter_name, Variant &r_shaped, MCPToolError &r_error) {
	r_shaped = p_json_value;

	// (1) An array of vector-shaped values: an element is a composite value of
	// its own, so it goes through exactly the same component gate. This is the
	// `Line2D.points = [{"x":1,"y":2}]` shape, which used to reach
	// `Variant::operator Vector2()`'s `else` branch and become `(0,0)` next to a
	// success. An element that is *not* an object is left for the element gate of
	// `coerce_to_property_type`, which knows the element type just as well.
	const Variant::Type element_type = _packed_vector_element_type(p_target_type);
	if (p_json_value.get_type() == Variant::ARRAY && element_type != Variant::NIL) {
		const Array source = p_json_value;
		Array shaped;
		for (int i = 0; i < source.size(); i++) {
			if (source[i].get_type() != Variant::DICTIONARY) {
				shaped.push_back(source[i]);
				continue;
			}
			Dictionary checked;
			if (!_check_components(source[i], element_type, vformat("%s[%d]", p_parameter_name, i), checked, r_error)) {
				return false;
			}
			const Variant element = vector_from_dictionary(checked, element_type);
			if (element.get_type() == Variant::NIL) {
				r_error = MCPToolError::invalid_params(vformat(
						"Parameter '%s[%d]' sets '%s', which is a %s, so every element has to provide its components (%s)",
						p_parameter_name, i, p_property, Variant::get_type_name(element_type), vector_component_hint(element_type)));
				return false;
			}
			shaped.push_back(element);
		}
		r_shaped = shaped;
		return true;
	}

	if (p_json_value.get_type() != Variant::DICTIONARY || vector_component_hint(p_target_type).is_empty()) {
		return true;
	}
	// (2) The property itself is the composite value: the same gate, per
	// component, before anything is folded.
	Dictionary checked;
	if (!_check_components(p_json_value, p_target_type, p_parameter_name, checked, r_error)) {
		return false;
	}
	const Variant shaped = vector_from_dictionary(checked, p_target_type);
	if (shaped.get_type() == Variant::NIL) {
		// `vector_from_dictionary` answers null exactly when the object does not
		// name the components of the target type: refuse instead of writing a
		// zero nobody asked for.
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' sets '%s', which is a %s, so the object has to provide its components (%s)",
				p_parameter_name, p_property, Variant::get_type_name(p_target_type), vector_component_hint(p_target_type)));
		return false;
	}
	r_shaped = shaped;
}

} // namespace MCPTools

// ---------------------------------------------------------------------------
// TASK-014 D-1: the write itself.
//
// Split out of `_tool_set_node_property` (behaviour preserving at the split, the
// tool now only resolves the `node_path` and delegates here) so that the
// doctest can reach it: the doctest binary has no `SceneTree`
// (`SceneTree::get_singleton() == nullptr`), so a tool-level test can only ever
// observe the -32000 "no current scene" guard. This entry point takes the node,
// which lets the case below pin both halves of D-1 against a real `Node2D`:
// a real property still writes and reads back, and a property the node does not
// have is a -32001 instead of a success shape.
//
// JSON has no vector type, so a caller names the components: `{"x":1,"y":2}`.
// The migration source did exactly this in its own `_parse_value_for_type`
// (`mcp_game_inspector_service.gd:610-660`: Dictionary -> Vector2 / Vector2i /
// Vector3 / Vector3i / Color), and it is the only way the tool's declared
// "supports numbers, strings, booleans, arrays, objects" can reach a Vector2
// property - `property_value_from_json` deliberately keeps a JSON object a
// Dictionary (its comment: "retain the structure").
//
// Without this step the observed behaviour was "the call succeeds and the
// property becomes (0,0)": `property_value_from_json({"x":321,"y":123}, Vector2)`
// answers a Dictionary, and `type_convert` of a Dictionary with no matching keys
// to a Vector2 is the zero vector. That is the silent-wrong-value shape this
// module refuses to ship (measured in the TASK-012 evidence run, check g04).
//
// The map is deliberately *partial* and never invents a component: a Dictionary
// whose members do not match the target type answers a **null** Variant, which is
// how the caller learns "I could not build the value you asked for" instead of
// receiving a silent zero.
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// The definition lives in `MCPTools` like its declaration
// (`tools/running_game_node_write.h`): with `using namespace MCPTools;` at the
// top of this file, a global-scope definition of a name the namespace already
// declares would be an ambiguous overload at every call site.
// ---------------------------------------------------------------------------
namespace MCPTools {

// TASK-014 D-1: does the object *really* have this property?
//
// The rule now lives once, as `MCPTools::object_has_property`
// (tools/tool_helpers.*), because TASK-017's batch and setup groups have to ask
// the same pre-write question and a group may not copy another group's
// file-private helper (PLAYBOOK section 2.4). The former `_object_has_property`
// here was a verbatim move into that function: the body is unchanged, so every
// answer `write_node_property` gives is byte-identical.
//
// `property_type_of` cannot answer the question on its own: it answers
// `Variant::NIL` both for "there is no such property" and for "there is one
// whose declared type is the `Variant` type" (`Object::get()` is NIL for both,
// and the property list entry of a `Variant`-typed declaration carries
// `Variant::NIL` as its type). The property list is the one place a declaration
// always shows up in, so it is what decides; the "it has a value right now"
// shortcut above it costs nothing and keeps the answer true for anything the
// engine can read back.

// The node path of the object the write is reported against. TASK-017 widened
// the receiver to `Object *` (a shape resource has to go through the same one
// property write); for a non-node the class name is the honest identifier,
// because a `Resource` has no scene path.
//
// TASK-027 E-8: the body is now the shared `MCPTools::wire_node_path`, because
// `Node::get_path()` spelled the editor's **internal absolute** path in this
// group's refusals (`Property 'x' on node '/root/@EditorNode@<id>/.../Main/Actor'
// not found`) while the same tool's success answer spelled the very same node
// relatively (`"Actor"`). The engine's own `get_path_to()` is what the answer
// should have used inside the editor; a running game keeps its byte-identical
// `/root/Main/Actor` (the `edited_scene_root()` branch is unreachable there).
static String _node_path_for_result(const Object *p_object) {
	return wire_node_path(p_object);
}

Variant write_node_property(Object *p_object, const String &p_property, const Variant &p_raw_value, MCPToolError &r_error) {
	const StringName property_name(p_property);
	// TASK-018 section 1.2: the validation half (existence, declared type, the
	// component mapping, the coercion and its `Variant::can_convert` gate) is
	// `prepare_node_property_value` below, so a batch can run exactly this
	// validation over every matched node *before* it writes the first one, and
	// the two steps cannot drift apart.
	Variant converted;
	if (!prepare_node_property_value(p_object, p_property, p_raw_value, converted, r_error)) {
		return Variant();
	}

	const Variant old_value = p_object->get(property_name);
	p_object->set(property_name, converted);
	const Variant new_value = p_object->get(property_name);

	Dictionary result;
	result["node_path"] = _node_path_for_result(p_object);
	result["property"] = p_property;
	result["old_value"] = serialize_variant(old_value);
	result["new_value"] = serialize_variant(new_value);
	return result;
}

// `Node::get_path()` spelled the editor's **internal absolute** path in this
// group's refusals (`Property 'x' on node '/root/@EditorNode@<id>/.../Main/Actor'
// not found`) while the same tool's success answer spelled the very same node
// relatively (`"Actor"`). The engine's own `get_path_to()` is what the answer
// should have used inside the editor; a running game keeps its byte-identical
// `/root/Main/Actor` (the `edited_scene_root()` branch is unreachable there).
static String _node_path_for_result(const Object *p_object) {
	return wire_node_path(p_object);
}

// ---------------------------------------------------------------------------
// TASK-028 G-1: **sub-property paths** (`position:y`, `v4:x`,
// `material:shader_parameter/uv1_scale`).
//
// The engine has always been able to read and write one component of a compound
// property, and the editor's own Inspector is built on it: `Object::set_indexed`
// / `Object::get_indexed` (`core/object/object.h:697-698`, implementation
// `object.cpp:475-532`), reached from GDScript as
// `node.set_indexed("position:y")` through `Object::_set_indexed_bind`
// (`object.cpp:1764-1770`). This module only ever called
// `Object::set(name)` / `Object::get(name)`, so every path that addressed a
// component answered `-32001 Property 'position:y' ... not found` - measured by
// the TASK-027 acceptance as G-1.
//
// What the two engine calls mean, exactly, and therefore what this module
// implements:
//
//   * the path is the engine's **NodePath property-path grammar**
//     (`core/string/node_path.cpp:419-452`): everything before the first `:` is
//     the first name, the remainder are the subnames, and one trailing `:` is
//     allowed and contributes nothing;
//   * the *first* name is an object property, so the module's own pre-write rule
//     applies to it unchanged (`object_has_property`, TASK-014 D-1);
//   * every following name is a **named member of a value**: a `Variant` member
//     of an engine built-in type (`Vector2.x`, `Rect2.position`, `Color.r8`,
//     `Transform3D.origin`, ... - the list `Variant::get_member_list` answers), a
//     property of a nested `Object` (a node's `material`), or a key of a
//     `Dictionary`;
//   * a value whose type has **no** named members (`float`, `String`, `Array`, a
//     packed array, a null reference) cannot be indexed - that is the `-32602`
//     TASK-028 asks for, not a "not found";
//   * a segment that does not exist is the `-32001`, and the message names the
//     **exact segment** that failed together with the engine's own member list
//     for that type.
//
// **The gate is not bypassed.** The last segment's declared type and the width of
// the C++ member it is stored in are resolved *before* anything is written, and
// the value goes through exactly the same three steps as a whole-property write
// (`property_value_from_json` -> `shape_vector_from_json` ->
// `coerce_to_property_type`, whose `value_fits_slot` judgement is the one gate of
// GDR-22/GDR-24). The write itself is then the engine's own `set_indexed`, so no
// second write path exists.
//
// The slot of a member is:
//
//   * `FLOAT` member of a `Color` -> `FLOAT32` (a `Color` component is a `float`
//     in every build, GDR-24);
//   * `FLOAT` member of anything else -> `REAL_T` (a `Vector2/3/4` or `Rect2`
//     component is the build's `real_t`);
//   * `INT` member of a `Vector2i`/`Vector3i`/`Vector4i`/`Rect2i`/`Color` ->
//     `INT32` (the member really is an `int32_t`);
//   * anything else -> the module's own property-member rule
//     (`scalar_member_slot`), which is `WIDE` for an `INT` member - the honest
//     boundary documented next to `ValueSlot`.
//
// A `Dictionary` member is `WIDE` for the same reason a `ProjectSettings` value
// is: it really is stored as a `Variant`, so nothing is narrowed.
//
// Two deliberate, narrow divergences from `Object::set_indexed` are recorded in
// REPORT-028: a leading `:` (`":y"`, which `NodePath` silently reads as the bare
// path `y`) is refused as malformed rather than reinterpreted, and a sub-path on
// a **null** object reference is a `-32001` naming the null rather than a crash
// or an invented member.
// ---------------------------------------------------------------------------

bool split_property_path(const String &p_property, Vector<StringName> &r_segments, MCPToolError &r_error) {
	r_segments.clear();
	const int first = p_property.find_char(':');
	if (first < 0) {
		r_segments.push_back(StringName(p_property));
		return true;
	}
	const String head = p_property.substr(0, first);
	const String tail = p_property.substr(first + 1);
	if (head.is_empty()) {
		r_error = MCPToolError::invalid_params(vformat(
				"Invalid property path '%s': the property name before the first ':' must not be empty", p_property));
		return false;
	}
	r_segments.push_back(StringName(head));
	int from = 0;
	while (from <= tail.length()) {
		const int next = tail.find_char(':', from);
		const int end = next < 0 ? tail.length() : next;
		const String piece = tail.substr(from, end - from);
		if (piece.is_empty()) {
			if (from == tail.length()) {
				// The engine's grammar allows one trailing ':' (node_path.cpp:438-441);
				// it contributes no subname.
				break;
			}
			r_error = MCPToolError::invalid_params(vformat(
					"Invalid property path '%s': the sub-property at offset %d is empty", p_property, (int)(first + 1 + from)));
			return false;
		}
		r_segments.push_back(StringName(piece));
		if (next < 0) {
			break;
		}
		from = next + 1;
	}
	return true;
}

// The width of the C++ member a named member of a built-in value is stored in.
// See the section comment above for the four cases and why each one is what it
// is; everything not listed falls back to the module's property-member rule.
static ValueSlot _path_member_slot(Variant::Type p_base_type, Variant::Type p_member_type) {
	if (p_member_type == Variant::FLOAT) {
		return p_base_type == Variant::COLOR ? ValueSlot::FLOAT32 : ValueSlot::REAL_T;
	}
	if (p_member_type == Variant::INT) {
		switch (p_base_type) {
			case Variant::VECTOR2I:
			case Variant::VECTOR3I:
			case Variant::VECTOR4I:
			case Variant::RECT2I:
			case Variant::COLOR:
				return ValueSlot::INT32;
			default:
				break;
		}
	}
	return scalar_member_slot(p_member_type);
}

// One named member of one value of the walk.
struct _PathMember {
	Variant value;
	Variant::Type type = Variant::NIL;
	ValueSlot slot = ValueSlot::WIDE;
	// The object the member belongs to, when the base value *is* an object (a
	// nested node or resource). It is what a declared-class check needs.
	const Object *base_object = nullptr;
	bool valid = false;
	// False when the value cannot hold named members at all (the `-32602`).
	bool indexable = false;
	// True for a `null` object reference: indexable in principle, but there is
	// nothing to read a member from, so the message has to say so.
	bool null_object = false;
	String base_type_name;
};

// The engine's own answer to "does this value have this member, what is it, and
// how wide is the member it is stored in".
//
// A built-in type is asked through the tables `Variant::has_member` /
// `Variant::get_member_type` read (`core/variant/variant_setget.cpp:159-180`,
// filled by `register_named_setters_getters`, `:67-150`) - the *same* table
// `Variant::get_named`/`set_named` (and therefore `Object::set_indexed`) uses, so
// the module can never accept a member the engine would then ignore. An `Object`
// is asked through the module's own property-existence rule, because an object
// property may be *declared* and still unset - `ShaderMaterial`'s
// `shader_parameter/<uniform>` is exactly that case, and `Object::get()` alone
// answers "no" for a uniform that was never written.
static void _path_member_of(const Variant &p_base, const StringName &p_member, _PathMember &r_out) {
	const Variant::Type base_type = p_base.get_type();
	r_out.base_type_name = Variant::get_type_name(base_type);
	if (base_type == Variant::OBJECT) {
		const Object *object = p_base;
		r_out.base_object = object;
		if (object == nullptr) {
			r_out.null_object = true;
			return;
		}
		r_out.indexable = true;
		r_out.valid = object_has_property(object, p_member);
		r_out.value = object->get(p_member);
		r_out.type = property_type_of(object, p_member);
		r_out.slot = scalar_member_slot(r_out.type);
		return;
	}
	if (base_type == Variant::DICTIONARY) {
		const Dictionary dict = p_base;
		r_out.indexable = true;
		r_out.valid = dict.has(p_member);
		if (r_out.valid) {
			r_out.value = dict[p_member];
			r_out.type = r_out.value.get_type();
			r_out.slot = ValueSlot::WIDE;
		}
		return;
	}
	r_out.indexable = Variant::get_member_count(base_type) > 0;
	r_out.valid = Variant::has_member(base_type, p_member);
	if (!r_out.valid) {
		return;
	}
	r_out.type = Variant::get_member_type(base_type, p_member);
	bool valid = false;
	r_out.value = p_base.get_named(p_member, valid);
	r_out.slot = _path_member_slot(base_type, r_out.type);
}

// The engine's own member list of a built-in type, for the `data.suggestion` of
// a missing segment (a caller that misspelt `position:x` on a `Rect2` should see
// that a `Rect2` has `position`, `size` and `end`).
static String _member_list_hint(Variant::Type p_type) {
	List<StringName> members;
	Variant::get_member_list(p_type, &members);
	Vector<String> names;
	for (const StringName &member : members) {
		names.push_back(String(member));
	}
	names.sort();
	return String(", ").join(names);
}

// Fills `r_error`'s `data.suggestion` for a `-32602` (the factory that builds an
// invalid-params error carries a message only).
static void _add_path_suggestion(MCPToolError &r_error, const String &p_suggestion) {
	Dictionary data = r_error.data;
	data["suggestion"] = p_suggestion;
	r_error.data = data;
}

// Walks `p_segments` from `p_object` and answers the last segment's declared
// type, slot, current value and (for an object-valued base) the class hint its
// property declares. False with `r_error` filled otherwise:
//
//   * `-32602` - a value that cannot be indexed at all, or a malformed path;
//   * `-32001` - a segment that really does not exist, naming that segment.
static bool _resolve_property_path(const Object *p_object, const String &p_property, const Vector<StringName> &p_segments,
		Variant::Type &r_type, ValueSlot &r_slot, const Object *&r_base_object, MCPToolError &r_error) {
	Variant base = Variant(const_cast<Object *>(p_object));
	String walked;
	for (int i = 0; i < p_segments.size(); i++) {
		_PathMember member;
		_path_member_of(base, p_segments[i], member);
		const String spelling = walked.is_empty() ? String(p_segments[i]) : walked + ":" + String(p_segments[i]);

		if (member.null_object) {
			// `MCPToolError::not_found` appends " not found" when the message does
			// not already end with it (tool_registry.cpp:122), and "is null not
			// found" is not a sentence: the message is therefore spelled out here.
			r_error = MCPToolError::not_found(
					vformat("Sub-property '%s' of the property path '%s' on node '%s'",
							p_segments[i], p_property, wire_node_path(p_object)),
					vformat("Set '%s' to a real object first - a null reference has no members - or address a property "
							"that exists",
							walked));
			r_error.message = vformat("Sub-property '%s' of the property path '%s' on node '%s': the object at '%s' is null",
					p_segments[i], p_property, wire_node_path(p_object), walked);
			return false;
		}
		if (!member.indexable) {
			const String type_name = member.base_type_name;
			r_error = MCPToolError::invalid_params(vformat(
					"Property path '%s' cannot be followed: '%s' is a %s, which has no named members to index",
					p_property, walked, type_name));
			_add_path_suggestion(r_error,
					vformat("A sub-property path can only walk through an Object property (a nested resource or node), a "
							"Dictionary, or the named members of an engine built-in type (a Vector2's 'x'/'y', a "
							"Rect2's 'position'/'size'/'end', a Color's 'r'/'g'/'b'/'a'). Write the whole property '%s' "
							"instead, or address a member the engine's own Object::set_indexed accepts.",
							walked));
			return false;
		}
		if (!member.valid) {
			if (i == 0) {
				// The module's existing one-property refusal, unchanged: the first
				// segment is an object property, not a sub-property.
				r_error = MCPToolError::not_found(
						vformat("Property '%s' on node '%s'", p_segments[0], wire_node_path(p_object)),
						"Use running_game_get_node_properties to list the properties this node has");
				return false;
			}
			String suggestion;
			if (member.base_object != nullptr) {
				suggestion = vformat("Use running_game_get_node_properties on '%s' to list the properties it has", walked);
			} else {
				suggestion = vformat("'%s' has these members: %s", member.base_type_name, _member_list_hint(base.get_type()));
			}
			r_error = MCPToolError::not_found(
					vformat("Sub-property '%s' of the property path '%s' on node '%s' ('%s' is a %s)",
							p_segments[i], p_property, wire_node_path(p_object), walked, member.base_type_name),
					suggestion);
			return false;
		}
		if (i == p_segments.size() - 1) {
			r_type = member.type;
			r_slot = member.slot;
			r_base_object = member.base_object;
			return true;
		}
		base = member.value;
		walked = spelling;
	}
	// `p_segments` is never empty at any call site.
	r_error = MCPToolError::internal(vformat("Empty property path '%s'", p_property));
	return false;
}

// The value a property path currently holds. `r_valid` is false when the engine
// could not follow the path (a malformed path fills `r_error`); the read uses the
// engine's own `get_indexed` for a path and `get` for a single name, so it can
// never disagree with what `Object::set_indexed` reads.
Variant read_node_property_path(Object *p_object, const String &p_property, bool &r_valid, MCPToolError &r_error) {
	Vector<StringName> segments;
	if (!split_property_path(p_property, segments, r_error)) {
		r_valid = false;
		return Variant();
	}
	r_valid = true;
	if (segments.size() == 1) {
		return p_object->get(segments[0]);
	}
	return p_object->get_indexed(segments, &r_valid);
}

bool apply_node_property_value(Object *p_object, const String &p_property, const Variant &p_value, MCPToolError &r_error) {
	Vector<StringName> segments;
	if (!split_property_path(p_property, segments, r_error)) {
		return false;
	}
	if (segments.size() == 1) {
		// The one-property write, unchanged: a read-only property or a setter that
		// silently refuses is reported by the caller's read-back, which is what
		// every tool of the family has always done (TASK-014 D-1).
		p_object->set(segments[0], p_value);
		return true;
	}
	bool valid = false;
	p_object->set_indexed(segments, p_value, &valid);
	if (!valid) {
		r_error = MCPToolError::tool_state(
				vformat("The engine refused to write the value %s through the property path '%s' on node '%s'",
						p_value.stringify(), p_property, _node_path_for_result(p_object)),
				"Use editor_get_node_properties (or running_game_get_node_properties) to read the property back, and "
				"address a path the engine can walk");
		return false;
	}
	return true;
}

bool node_property_path_exists(Object *p_object, const String &p_property, MCPToolError &r_error) {
	Vector<StringName> segments;
	if (!split_property_path(p_property, segments, r_error)) {
		return false;
	}
	Variant::Type type = Variant::NIL;
	ValueSlot slot = ValueSlot::WIDE;
	const Object *base_object = nullptr;
	return _resolve_property_path(p_object, p_property, segments, type, slot, base_object, r_error);
}

// The value at a path, read through the engine's own accessors (a single name is
// `get`, which is byte-identical to what this file did before TASK-028).
static Variant _read_path_value(Object *p_object, const Vector<StringName> &p_segments) {
	return p_segments.size() == 1 ? p_object->get(p_segments[0]) : p_object->get_indexed(p_segments);
}

Variant write_node_property(Object *p_object, const String &p_property, const Variant &p_raw_value, MCPToolError &r_error) {
	// TASK-018 section 1.2: the validation half (existence, declared type, the
	// component mapping, the coercion and its `Variant::can_convert` gate) is
	// `prepare_node_property_value` below, so a batch can run exactly this
	// validation over every matched node *before* it writes the first one, and
	// the two steps cannot drift apart.
	Variant converted;
	if (!prepare_node_property_value(p_object, p_property, p_raw_value, converted, r_error)) {
		return Variant();
	}
	Vector<StringName> segments;
	if (!split_property_path(p_property, segments, r_error)) {
		return Variant();
	}
	// TASK-028 G-1: a path with one name keeps the exact calls the module made
	// before (a `get`/`set` pair); a path with sub-names reads and writes through
	// the engine's `get_indexed`/`set_indexed`.
	const bool is_path = segments.size() > 1;
	const Variant old_value = _read_path_value(p_object, segments);
	// The compound the last segment lives in: what `Object::set_indexed` reads,
	// changes and writes back. The answer carries it as well (below), because the
	// value *at the path* alone does not show what happened to the rest of it.
	Vector<StringName> parent_segments = segments;
	if (is_path) {
		parent_segments.resize(segments.size() - 1);
	}
	const Variant parent_old_value = is_path ? _read_path_value(p_object, parent_segments) : Variant();

	if (!apply_node_property_value(p_object, p_property, converted, r_error)) {
		return Variant();
	}
	// The answer's values are what the object answers *after* the write (GDR-25
	// section 23.4's level 2), never the value that was sent.
	const Variant new_value = _read_path_value(p_object, segments);
	const Variant parent_new_value = is_path ? _read_path_value(p_object, parent_segments) : Variant();

	Dictionary result;
	result["node_path"] = _node_path_for_result(p_object);
	result["property"] = p_property;
	result["old_value"] = serialize_variant(old_value);
	result["new_value"] = serialize_variant(new_value);
	if (is_path) {
		String parent_property;
		for (int i = 0; i < parent_segments.size(); i++) {
			if (i > 0) {
				parent_property += ":";
			}
			parent_property += String(parent_segments[i]);
		}
		result["parent_property"] = parent_property;
		result["parent_old_value"] = serialize_variant(parent_old_value);
		result["parent_new_value"] = serialize_variant(parent_new_value);
	}
	return result;
}

// The validation half of a **sub-property path**: the same three steps as the
// whole-property write below, with the last segment's declared type and slot
// coming from `_resolve_property_path` instead of from `property_type_of`.
static bool _prepare_sub_property_value(Object *p_object, const String &p_property, const Vector<StringName> &p_segments,
		const Variant &p_raw_value, Variant &r_converted, MCPToolError &r_error) {
	Variant::Type target_type = Variant::NIL;
	ValueSlot slot = ValueSlot::WIDE;
	const Object *base_object = nullptr;
	if (!_resolve_property_path(p_object, p_property, p_segments, target_type, slot, base_object, r_error)) {
		return false;
	}
	const Variant json_value = property_value_from_json(p_raw_value, target_type);
	Variant shaped_value;
	if (!shape_vector_from_json(json_value, target_type, p_property, "value", shaped_value, r_error)) {
		return false;
	}
	// The parameter name stays `value`, exactly as the whole-property write spells
	// it: a caller that switches from `position` to `position:y` reads the same
	// refusals.
	const String class_hint = base_object != nullptr ? object_property_class_hint(base_object, p_segments[p_segments.size() - 1]) : String();
	return coerce_to_property_type(shaped_value, target_type, r_converted, r_error, "value", slot, class_hint);
}

bool prepare_node_property_value(Object *p_object, const String &p_property, const Variant &p_raw_value,
		Variant &r_converted, MCPToolError &r_error) {
	Vector<StringName> segments;
	if (!split_property_path(p_property, segments, r_error)) {
		return false;
	}
	if (segments.size() > 1) {
		return _prepare_sub_property_value(p_object, p_property, segments, p_raw_value, r_converted, r_error);
	}
	const StringName property_name(p_property);
	const Variant::Type target_type = property_type_of(p_object, property_name);

	// TASK-014 D-1: ask the object *before* writing anything. Without this the
	// steps below report a success for a name that does not exist at all:
	// `target_type` is NIL, `Object::set()` of an unknown name is a silent no-op
	// and the read-back is null as well, so the caller received
	// `{"old_value":null,"new_value":null}` next to a top-level success. A caller
	// that only branches on "error or not" read "nothing happened" as "written".
	if (!object_has_property(p_object, property_name)) {
		r_error = MCPToolError::not_found(
				vformat("Property '%s' on node '%s'", p_property, _node_path_for_result(p_object)),
				"Use running_game_get_node_properties to list the properties this node has");
		return false;
	}

	// `property_value_from_json` first (the migration source's "parse the string
	// with the property's own type" step), then the type coercion and its range
	// guard - the same two steps every other write tool of the module takes.
	const Variant json_value = property_value_from_json(p_raw_value, target_type);
	// A JSON *object* is still a Dictionary at this point. When the target is a
	// vector-shaped type the object has to name its components (`{"x":1,"y":2}`),
	// because `property_value_from_json` deliberately keeps an object a
	// Dictionary and `type_convert` of a keyless Dictionary to a Vector2 is the
	// **zero vector** - the silent wrong value the first TASK-012 evidence run
	// measured (`{"x":321,"y":123}` answered `new_value: {"x":0,"y":0}`).
	// TASK-018 section 3: the step itself is `shape_vector_from_json`, the one
	// definition `project_set_setting` shares.
	Variant shaped_value;
	if (!shape_vector_from_json(json_value, target_type, p_property, "value", shaped_value, r_error)) {
		return false;
	}
	// TASK-018 section 1: `coerce_to_property_type` is where a value that cannot
	// fall into the target type is refused (`Variant::can_convert`), so the
	// layout-incompatible case never reaches `Object::set()`.
	//
	// TASK-027 D-8: for an Object-valued property the engine's own conversion
	// relation is not the rule any more (`DICTIONARY -> OBJECT` is not listed, yet
	// `{"type","path"}` has to be taken back). What is passed along is the class
	// the *property* declares (`Texture2D` for `Sprite2D.texture`), so a resource
	// of a class the setter would silently drop is refused with both names in the
		return false;
	}
	// The parameter name stays `value`, exactly as the whole-property write spells
	// it: a caller that switches from `position` to `position:y` reads the same
	// refusals.
	const String class_hint = base_object != nullptr ? object_property_class_hint(base_object, p_segments[p_segments.size() - 1]) : String();
	return coerce_to_property_type(shaped_value, target_type, r_converted, r_error, "value", slot, class_hint);
}

bool prepare_node_property_value(Object *p_object, const String &p_property, const Variant &p_raw_value,
		Variant &r_converted, MCPToolError &r_error) {
	Vector<StringName> segments;
	if (!split_property_path(p_property, segments, r_error)) {
		return false;
	}
	if (segments.size() > 1) {
		return _prepare_sub_property_value(p_object, p_property, segments, p_raw_value, r_converted, r_error);
	}
	const StringName property_name(p_property);
	const Variant::Type target_type = property_type_of(p_object, property_name);

	// TASK-014 D-1: ask the object *before* writing anything. Without this the
	// steps below report a success for a name that does not exist at all:
	// `target_type` is NIL, `Object::set()` of an unknown name is a silent no-op
	// and the read-back is null as well, so the caller received
	// `{"old_value":null,"new_value":null}` next to a top-level success. A caller
	// that only branches on "error or not" read "nothing happened" as "written".
	if (!object_has_property(p_object, property_name)) {
		r_error = MCPToolError::not_found(
				vformat("Property '%s' on node '%s'", p_property, _node_path_for_result(p_object)),
				"Use running_game_get_node_properties to list the properties this node has");
		return false;
	}

	// `property_value_from_json` first (the migration source's "parse the string
	// with the property's own type" step), then the type coercion and its range
	// guard - the same two steps every other write tool of the module takes.
	const Variant json_value = property_value_from_json(p_raw_value, target_type);
	// A JSON *object* is still a Dictionary at this point. When the target is a
	// vector-shaped type the object has to name its components (`{"x":1,"y":2}`),
	// because `property_value_from_json` deliberately keeps an object a
	// Dictionary and `type_convert` of a keyless Dictionary to a Vector2 is the
	// **zero vector** - the silent wrong value the first TASK-012 evidence run
	// measured (`{"x":321,"y":123}` answered `new_value: {"x":0,"y":0}`).
	// TASK-018 section 3: the step itself is `shape_vector_from_json`, the one
	// definition `project_set_setting` shares.
	Variant shaped_value;
	if (!shape_vector_from_json(json_value, target_type, p_property, "value", shaped_value, r_error)) {
		return false;
	}
	// TASK-018 section 1: `coerce_to_property_type` is where a value that cannot
	// fall into the target type is refused (`Variant::can_convert`), so the
	// layout-incompatible case never reaches `Object::set()`.
	//
	// TASK-027 D-8: for an Object-valued property the engine's own conversion
	// relation is not the rule any more (`DICTIONARY -> OBJECT` is not listed, yet
	// `{"type","path"}` has to be taken back). What is passed along is the class
	// the *property* declares (`Texture2D` for `Sprite2D.texture`), so a resource
	// of a class the setter would silently drop is refused with both names in the
	// message instead of being stored as `null` next to a success.
	return coerce_to_property_type(shaped_value, target_type, r_converted, r_error, "value",
			ValueSlot::FROM_TARGET_TYPE, object_property_class_hint(p_object, property_name));
}

} // namespace MCPTools

static Variant _tool_set_node_property(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return Variant();
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_path' must not be empty");
		return Variant();
	}
	String property;
	if (!require_string(p_args, "property", property, r_error)) {
		return Variant();
	}
	if (property.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'property' must not be empty");
		return Variant();
	}
	// `value` has no `type` in the contract (it accepts every JSON type), so it
	// cannot go through `require_*`. Presence, not nullness, is what "required"
	// means here: `"value": null` is a real request to set `null`.
	if (!p_args.has("value")) {
		r_error = MCPToolError::invalid_params("Missing required parameter 'value'");
		return Variant();
	}
	const Variant raw_value = p_args["value"];

	Node *root = nullptr;
	SceneTree *tree = nullptr;
	if (!game_current_scene(root, tree, r_error)) {
		return Variant();
	}
	(void)tree;
	Node *node = resolve_game_node(SceneTree::get_singleton(), root, node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", node_path),
				"Use running_game_get_scene_tree to list the nodes of the running scene");
		return Variant();
	}

	return write_node_property(node, property, raw_value, r_error);
}

// ---------------------------------------------------------------------------
// Registration
//
// The declaration order follows docs/tool-groups-b2.json; channel, verb, scope
// and mutating come from docs/tool-rename-map.json and the description and
// `inputSchema` are a byte-exact copy of docs/tools_list.renamed.json, emitted
// by `scripts/gen_b2_game_schema.py` (re-running it reproduces this block).
// ---------------------------------------------------------------------------

void register_running_game_node_write_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("running_game_set_node_property", String::utf8("设置运行中游戏节点的属性值"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("节点路径");
		v1[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("node_path")] = v1;
		Dictionary v2;
		v2[String::utf8("description")] = String::utf8("属性名称");
		v2[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("property")] = v2;
		Dictionary v3;
		v3[String::utf8("description")] = String::utf8("属性值（支持数字、字符串、布尔、数组、对象等类型）");
		v0[String::utf8("value")] = v3;
		schema[String::utf8("properties")] = v0;
		Array v4;
		v4.push_back(String::utf8("node_path"));
		v4.push_back(String::utf8("property"));
		v4.push_back(String::utf8("value"));
		schema[String::utf8("required")] = v4;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("set").scope(MCPToolScope::GAME).mutating(true).schema(schema).handler(_tool_set_node_property);
		builder.register_into(r_registry);
	}
	// END generated
}
