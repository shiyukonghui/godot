/**************************************************************************/
/*  project_cross_scene_write.h                                           */
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
#pragma once

#include "../tool_registry.h"

#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// Only ever used through a pointer by the declaration below, so the class name is
// forward declared instead of dragging `scene/` into this header.
class Node;

// TASK-018 section 3, group `project_cross_scene_write` of
// docs/tool-groups-b3.json: one property written into every scene that contains
// a node of a given type.
//
//   project_set_node_property_across_scenes   (old `cross_scene_set_property`,
//                                              batch.rs:257)
//
// channel `project`, `scope = both`, `mutating = true`. It is alone because it
// owns the multi-scene transaction.
//
// ## The transaction, stated up front
//
// The tool is **all-or-nothing**, in two phases, and neither phase can leave a
// half-written project behind:
//
//   * **plan (no writes).** Every `.tscn` under `path_filter` is loaded, every
//     node matching `type` is resolved, and the property is validated *per node*
//     through `MCPTools::prepare_node_property_value()` - the same rule the node
//     write uses. A scene that cannot be loaded, a matched node that does not
//     declare the property, or a value that cannot fall into the property's type
//     (TASK-018 section 1) refuses the **whole call** with `data.scenes`
//     naming every offending file, and nothing is written anywhere. This is the
//     "deliberately broken middle file" case of the task book, and it is a
//     refusal rather than a skip: skipping is how a caller ends up believing a
//     30-scene edit happened while one scene silently kept its old value.
//   * **commit (all files or none).** The original bytes of every target file
//     are read first, then each scene is packed and published atomically
//     (`publish_file_atomically`, so a single file cannot be truncated either).
//     If any publish fails, every file already published is restored **from those
//     bytes**, and the answer is `-32603` with `data.rollback` listing what was
//     put back.
//
// `dry_run` defaults to `not force` and the default is answered in the result,
// so "preview" is the default and a write needs an explicit `force: true,
// dry_run: false` (the migration source's rule, batch.rs:283-285).
//
// ## Divergences from the migration source, which the report lists
//
//   * the migration skipped a matched node that did not declare the property
//     (`if property in node`, batch.rs:396); here that refuses the call, because
//     the caller named `type` + `property` and a matched node that cannot take it
//     is a fact the caller has to know;
//   * the migration skipped any scene that failed to load
//     (`if packed == null: continue`, batch.rs:316-318) and answered a success;
//     here it is an error naming the file;
//   * the migration wrote through `ResourceSaver::save()` straight into the
//     destination (batch.rs:341) with no rollback across files;
//   * a `type` that is not a class at all produced `total_nodes: 0` as a
//     success (`_collect_scene_files` + a match that could never fire); here it
//     is `-32602`;
//   * the scene-file list is **sorted**, where the migration used
//     `DirAccess` iteration order (PLAYBOOK section 6.8: a non-deterministic
//     order is not an answer, and `scenes_affected` is part of the answer).
namespace MCPTools {

// The scene-file collection rule: every `.tscn` under `p_path_filter`, `addons`
// skipped when `p_exclude_addons`, sorted ascending so the answer is
// reproducible. Published because the doctest asserts the rule directly.
void collect_scene_files(const String &p_path_filter, bool p_exclude_addons, Vector<String> &r_out);

// The whole tool, minus argument reading. See the header comment for the
// transaction; `r_out` is the `{"type","property","dry_run","force",
// "path_filter","scenes_affected","skipped_open_scenes","errors","total_scenes",
// "total_nodes","editor_rescan_triggered","message"}` answer, where each
// `scenes_affected` entry is `{"scene","nodes","count","mode","written",
// "persisted"}`.
bool set_node_property_across_scenes(const String &p_path_filter, const String &p_type, const String &p_property,
		const Variant &p_value, bool p_exclude_addons, bool p_force, bool p_dry_run,
		Dictionary &r_out, MCPToolError &r_error);

// TASK-030 D1: the live half of the commit - `p_nodes` are the matched nodes of
// the **live** edited scene (the tree `edited_scene_root()` answers, which the
// caller owns and must not delete). Validates each value first, reads the current
// value before writing it, writes every node, reads every write back and compares
// it with the value that was written; the moment one step fails, every node this
// call already changed is restored to the value it held before, and `r_error`
// (with `data.live_nodes_restored`) says what happened.
//
// Public (not `static`) for the reason the node write helpers are: the doctest
// binary has no `SceneTree`, so the live write - including its read-back - can
// only be asserted through an entry point that takes the nodes directly.
bool write_live_scene_property(const Vector<Node *> &p_nodes, const String &p_property, const Variant &p_raw_value,
		MCPToolError &r_error);

} // namespace MCPTools

void register_project_cross_scene_write_tools(MCPToolRegistry &r_registry);
//     here it is an error naming the file;
//   * the migration wrote through `ResourceSaver::save()` straight into the
//     destination (batch.rs:341) with no rollback across files;
//   * a `type` that is not a class at all produced `total_nodes: 0` as a
//     success (`_collect_scene_files` + a match that could never fire); here it
//     is `-32602`;
//   * the scene-file list is **sorted**, where the migration used
//     `DirAccess` iteration order (PLAYBOOK section 6.8: a non-deterministic
//     order is not an answer, and `scenes_affected` is part of the answer).
namespace MCPTools {

// The scene-file collection rule: every `.tscn` under `p_path_filter`, `addons`
// skipped when `p_exclude_addons`, sorted ascending so the answer is
// reproducible. Published because the doctest asserts the rule directly.
void collect_scene_files(const String &p_path_filter, bool p_exclude_addons, Vector<String> &r_out);

// The whole tool, minus argument reading. See the header comment for the
// transaction; `r_out` is the `{"type","property","dry_run","force",
// "path_filter","scenes_affected","skipped_open_scenes","errors","total_scenes",
// "total_nodes","message"}` answer.
bool set_node_property_across_scenes(const String &p_path_filter, const String &p_type, const String &p_property,
		const Variant &p_value, bool p_exclude_addons, bool p_force, bool p_dry_run,
		Dictionary &r_out, MCPToolError &r_error);

} // namespace MCPTools

