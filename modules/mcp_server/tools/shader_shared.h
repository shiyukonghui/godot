/**************************************************************************/
/*  shader_shared.h                                                       */
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

#include "tool_builder.h"

#include "scene/resources/material.h"
#include "scene/resources/shader.h"

class Node;

// ---------------------------------------------------------------------------
// TASK-035 (B5 batch 3): the engine-facing helpers the three shader groups share
// (`editor_shader_write` 2 tools, `project_shader_write` 2 tools,
// `project_shader_read` 2 tools).
//
// They are *not* a fourth group: no tool is registered here.
//
// The engine's own model is the design basis (GDR-23):
//
//   * a node's materials live in **named object properties** - `CanvasItem.material`
//     (`scene/main/canvas_item.h`), `GeometryInstance3D.material_override` /
//     `material_overlay` and `MeshInstance3D.surface_material_override/<i>`
//     (`scene/3d/mesh_instance_3d.cpp:113-117`) - so a "slot" is a property name,
//     and the set of them is what `Object::get_property_list()` declares as
//     `Object`-typed with a Material class hint. This is why the tool enumerates
//     slots from the engine instead of hard-coding `material`.
//   * a shader parameter is written with
//     `ShaderMaterial::set_shader_parameter(const StringName &, const Variant &)`
//     (`scene/resources/material.cpp:420`) and read with
//     `get_shader_parameter` (:454) / listed with
//     `Shader::get_shader_uniform_list` (`scene/resources/shader.cpp:150`).
//   * the migration source instead did `node.set("material:shader_parameter/<name>", v)`
//     (`godot_mcp_gdext/src/commands/shader.rs:134`). `Object::set` does **not**
//     split a `:` path (`core/object/object.cpp:198` has no `:` handling; it
//     falls through to `_setv`), so that call is a silent no-op. The measured
//     companion facts (REPORT-035 section E-5, asserted by the doctest
//     `TASK-035 E-5` and on the 9888 wire): `Object::set_indexed` *does* split a
//     property path and reaches a compiled `ShaderMaterial`'s `_set` - it is the
//     route the module's own `editor_set_node_property` takes for a `a:b` name
//     (TASK-028) - so the engine route exists and the migration source's defect
//     was its raw single-`Object::set` spelling. The engine's
//     `set_shader_parameter` is still the better lever: no path guessing, no
//     dependence on the material's remap cache, and a uniform-list check.
// ---------------------------------------------------------------------------

namespace MCPTools {

// Every material-bearing property of `p_node`, in the engine's own property-list
// order (deterministic for one class). Each entry is the property name as
// `Object::set` expects it (`material`, `material_override`,
// `surface_material_override/0`, ...).
Array material_slot_names(const Object *p_node);

// True when `p_slot` is one of them.
bool material_slot_exists(const Object *p_node, const StringName &p_slot);

// Resolves the contract's `material_slot` argument to a real property name.
//
//   * an exact property name is taken as-is;
//   * a decimal integer is the engine's own *surface index* spelling and is
//     translated to `surface_material_override/<n>` when the node has that
//     property (the migration source read such a value and then wrote
//     `material`, ignoring it);
//   * anything else is `-32602` and the message lists the slots the node really
//     has, so the caller can correct the call in one step.
//
// TASK-037 R1 - `p_argument_present` says whether the caller *sent*
// `material_slot` at all, and the two cases are answered differently:
//
//   * **present**: only the three rules above apply. `"material"` on a
//     `MeshInstance3D` (which has no such property) is a `-32602` naming the
//     slots it does have;
//   * **absent**: the contract's `default` is `"material"`, which is a
//     `CanvasItem` property and not a general one, so a mechanical client that
//     just takes the schema default fails on every 3D node. The input schema is
//     frozen (a contract change needs a `SCHEMA_OVERRIDES` entry, which
//     TASK-037 is not allowed to add), so the *server* resolves the default at
//     call time instead: `material` when the node has it, otherwise the engine's
//     first material slot in property-list order. This is why the tool's answer
//     carries `material_slot` - a caller that omitted the argument is told which
//     slot the write really went into.
bool resolve_material_slot(Object *p_node, const String &p_slot_argument, bool p_argument_present,
		StringName &r_slot, MCPToolError &r_error);

// The material currently at `p_slot` (`Variant()`, i.e. NIL, when the slot is
// empty).
Variant material_at_slot(Object *p_node, const StringName &p_slot);

// Writes `p_material` into `p_slot` through `Object::set` and answers whether the
// engine really holds it afterwards (read back with `Object::get`).
bool set_material_at_slot(Object *p_node, const StringName &p_slot, const Ref<Material> &p_material,
		bool &r_applied, MCPToolError &r_error);

// The first `ShaderMaterial` a node carries, searching its material slots in
// property-list order. `r_slot` names the slot it was found in. An empty result
// with no error means "this node has no ShaderMaterial at all", which the caller
// answers as `-32001` with a suggestion rather than as a success.
Ref<ShaderMaterial> first_shader_material(Object *p_node, StringName &r_slot);

// Every uniform of a shader as `{name, type, type_id, hint, hint_string}`, in the
// engine's declaration order (deterministic for one shader file). Group markers
// are not answered (`get_shader_uniform_list(..., false)`).
Array shader_uniform_records(Shader *p_shader);

// One uniform by name. False when the shader declares no such parameter.
bool shader_uniform(const Shader *p_shader, const String &p_name, PropertyInfo &r_uniform);

// The names of the first few uniforms, for a refusal that lets the caller fix
// the call in one step.
String shader_uniform_names_preview(const Shader *p_shader, int p_max = 8);

// The engine's own name of a shader mode (`Shader::MODE_SPATIAL` ->
// `"spatial"`), and the mode a name spells. `-1` when the name is not one.
const char *shader_mode_name(int p_mode);
int shader_mode_from_name(const String &p_name);

// The mode the first `shader_type` directive of `p_code` declares, with the mode
// name and the directive line itself. `-1` when the code declares no directive,
// `-2` when it declares one the engine does not know (the two are answered
// differently by the two callers).
int shader_code_mode(const String &p_code, String &r_mode_name, String &r_directive);

// The text `project_create_shader` writes for a mode directive: the directive
// line plus an entry-point stub where the mode has one. `fragment()` is a real
// entry point for the two raster modes only - a `void fragment()` in a
// sky/fog/particles shader is a compile error, which is exactly what the
// migration source's unconditional body produced.
String shader_template(const String &p_mode_directive, int p_mode);

} // namespace MCPTools
