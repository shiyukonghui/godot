/**************************************************************************/
/*  project_write_resource_scene.h                                        */
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

#include "core/io/resource.h"
#include "core/object/ref_counted.h"

// B1 group `project_write_resource_scene` (the manifest is docs/tool-groups.json):
//
//   project_create_resource     (migrated from resource.rs:199)
//   project_create_scene_file   (migrated from scene.rs:171)
//   project_delete_scene_file   (migrated from scene.rs:251)
//   project_edit_resource       (migrated from resource.rs:131)
//
// This is the **only mutating group of B1**: all four tools write into the
// project on disk (`res://`), so all four are `mutating = true` (GDR-18) and
// `scope = BOTH` (a game process may write the project too - the contract of
// docs/tool-rename-map.json says `both` for every one of them).
//
// The invariants this file owns, beyond "the call returned the right JSON"
// (TASK-007 section 3):
//
//   1. **a failure never damages an existing file.** Every write goes through
//      `_save_resource_atomically`: the resource is fully serialised into a
//      temporary file next to the destination first, and only a *successful*
//      save is published. A caller that cannot even build the object (unknown
//      type, load failure) therefore never opens the destination at all, and
//      the temporary file is removed on every failure path.
//   2. **no temporary or partial artefact survives a call.**
//   3. **path safety**: every path goes through `normalize_project_path`, so it
//      must address `res://` and may not walk upwards with `..`.
//   4. **a `properties` bag never reports a write that did not happen**
//      (DESIGN-DETAIL section 20.6, TASK-037 D2). The two resource writers share
//      one bag writer: **the object's own property table decides what a property
//      name is** (TASK-049 - it is the engine's answer, `Object::set_native()`,
//      and it is what the readers enumerate, so `glow_levels/1` and
//      `shader_parameter/<uniform>` are taken as they are); a name that is not a
//      name at all, or one the table carries only as an inspector label, is
//      `-32602`; a well-formed name the resource does not have is `-32001` naming
//      it (the call is refused as a whole, so no half-applied bag is left
//      behind), and a value the engine's own setter clamped or refused lands in
//      `ignored` with `requested` / `stored` / `reason` instead of being read as
//      "set".
//
// Pinned by the doctests
// `[MCPServer] the write tools never corrupt an existing file when the call fails`,
// `[MCPServer] the write tools leave no temporary or partial file behind`,
// `[MCPServer] project_delete_scene_file ...` and, for the name rule,
// `[MCPServer] TASK-049 ...`.
//
// This pair of files is the only file the owner of this group edits, plus one
// include and one call line in the shared tools/registration.cpp (TASK-002
// section 2.2.1: porting agents never touch the same file, PLAYBOOK section
// 17.1).
namespace MCPTools {

// TASK-049: the one `properties` bag writer of `project_create_resource` and
// `project_edit_resource`, exported for the same reason `set_project_setting`
// and `write_node_property` are - a doctest has to be able to hand it a
// `Resource` and pin the name rule against the engine's whole property table
// without a live project file. `changed` / `ignored` / `properties_set` are
// filled exactly as the two tools answer them (see the definition).
bool write_resource_properties(const Ref<Resource> &p_resource, const Dictionary &p_properties,
		Dictionary &r_changed, Dictionary &r_ignored, Array &r_properties_set, MCPToolError &r_error);

// TASK-049: whether a name the object's own property table does **not** carry is
// still shaped like a property name (an identifier). Exported so the doctest that
// pins the rule can name both halves of the judgement: the table decides
// (`glow_levels/1` is answered `false` here and accepted anyway, because the
// table is consulted first), and this fallback keeps the TASK-037 refusals for
// the names no table can carry - the empty name, a `:` sub-property path, `a.b`,
// `a[0]`, a name with spaces, `metadata/*`.
bool resource_bag_name_is_addressable(const StringName &p_name);

} // namespace MCPTools
void register_project_write_resource_scene_tools(MCPToolRegistry &r_registry);
