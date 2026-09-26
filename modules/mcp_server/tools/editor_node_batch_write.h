/**************************************************************************/
/*  editor_node_batch_write.h                                             */
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

#include "core/string/string_name.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// `Node` is only ever used through a pointer by the helpers declared below, so
// the class name is forward declared instead of dragging `scene/` into every
// translation unit that includes this header.
class Node;

// B3 group `editor_node_batch_write` (docs/tool-groups-b3.json; TASK-017
// section 2) - the two batch shapes, two tools:
//
//   editor_add_nodes_batch        (batch.rs:270)
//   editor_set_node_property_batch (batch.rs:147)
//
// Both are `channel = editor`, `scope = editor`, `mutating = true`
// (docs/tool-rename-map.json), so both are registered only in an editor process
// and a game endpoint must answer `-32601` without executing anything.
//
// **Transaction semantics (DECISION D1 / D2).** The migration source answered
// `{"created": [...], "errors": [...]}` for `batch_add_nodes` - a *success*
// envelope that can carry a partially applied batch, because it `continue`d past
// each broken element after having already added the earlier ones
// (batch.rs:291-402) - and it answered `{"updated": N}` for
// `batch_set_property`, where `N` could be 0 and nothing was checked at all
// (batch.rs:147-180). Both shapes let a caller read "nothing happened" or "some
// of what I asked happened" as a success. This module forbids that
// (PLAYBOOK section 6.6), so both tools are **all-or-nothing**:
//
//   * `add_nodes_batch_on` prepares every element (instantiate, validate every
//     property against the new node, resolve the parent, apply name +
//     properties) **without attaching anything**, and only when all elements
//     prepared does it attach them. A failure `memdelete`s everything already
//     prepared and answers the single refusal; the rollback envelope is attached
//     to `error.data.batch` (see the wire shape in the .cpp);
//   * `set_node_property_batch_on` decides the target set first
//     (`get_class() == node_type || is_class(node_type)`, natural pre-order),
//     refuses when *any* matched node does not declare the property before a
//     single write happens, and restores the previous values of the nodes it
//     already wrote if a write fails mid-loop.
//
// The helper functions below are declared here for the same reason
// `tools/editor_node_write.h` declares its five: the doctest binary has no
// `SceneTree` at all (`SceneTree::get_singleton()` is nullptr), so a
// *tool-level* test can only ever observe the `-32000` / `-32601` guards. The
// entry points below take a root `Node *`, which is what lets the cases pin the
// transaction - including the deliberately broken middle element - against bare
// `Node` objects. Behaviour is documented at each definition.
namespace MCPTools {

// Every node in `p_root`'s subtree whose class is `p_type` or derives from it,
// in deterministic natural pre-order (the migration source's `collect_by_type`,
// batch.rs:105-123). `p_root` itself is tested first.
void collect_nodes_by_type(Node *p_root, const String &p_type, Vector<Node *> &r_out);

// Applies an `editor_add_nodes_batch` request against `p_root`. Returns the
// success payload (`{"status":"ok","created":[...],"count":N,"errors":[]}`) or
// fills `r_error` with the transaction refusal and returns nil. On a refusal
// nothing of the request stays attached to `p_root`, and `error.data.batch`
// carries the `{"status":"rolled_back", ...}` envelope.
//
// TASK-051 C-3 (D86 item C-3): `p_resolve_within_batch` decides what an
// element's `parent_path` may name.
//
//   * `false` (the default, and the behaviour every earlier batch had): the
//     parent is resolved against the scene tree **as it was when the call
//     arrived**, so an element may not name a node a sibling element creates.
//     A parent that only a *later* element asks for is a `-32001`, and one that
//     an *earlier* element created in this same request is too - the earlier
//     element is only *prepared* at that point, not attached;
//   * `true`: the lookup also sees the nodes this same request already
//     prepared, i.e. the parent may be an earlier element of the batch
//     (`nodes[1].parent_path = "P1"` with `P1` created by `nodes[0]`). The
//     scene tree still wins over the batch when both carry the same path, and
//     every `created[]` entry names which of the two answered through
//     `parent_source` (`"scene"` / `"batch"`).
//
// Three request shapes are refused **explicitly** in the `true` mode, because
// each of them would otherwise produce a node whose path is not the one the
// caller wrote:
//
//   * a **duplicate** pending path inside one batch (`nodes[i]` and `nodes[j]`
//     with the same parent and the same name) is a `-32602` naming both
//     indexes - the default mode keeps the engine's own rename of the second
//     node, which is what the existing doctest pins;
//   * a **forward reference** (the named parent is a path a *later* element
//     asks for) is a `-32001` whose message names that later index and whose
//     suggestion asks for the parent to be ordered first. A parent/child
//     *cycle* is exactly this shape whichever way the array is ordered, so it
//     is refused here rather than by an engine rename or a dangling node;
//   * a parent that neither the scene nor any element of the batch provides
//     stays the plain `-32001` "not found" it always was.
//
// The transaction itself does not change: a refusal still rolls the whole
// request back (`error.data.batch.rolled_back`, nothing attached), in either
// mode.
Variant add_nodes_batch_on(Node *p_root, const Array &p_nodes, MCPToolError &r_error,
		bool p_resolve_within_batch = false);

// Applies an `editor_set_node_property_batch` request against `p_root`. Returns
// the success payload or fills `r_error` and returns nil; a refusal leaves every
// matched node untouched.
Variant set_node_property_batch_on(Node *p_root, const String &p_node_type, const String &p_property,
		const Variant &p_raw_value, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_node_batch_write_tools(MCPToolRegistry &r_registry);
