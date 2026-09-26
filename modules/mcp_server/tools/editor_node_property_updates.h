/**************************************************************************/
/*  editor_node_property_updates.h                                        */
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

#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// `Node` is only ever used through a pointer by the helper declared below, so
// the class name is forward declared instead of dragging `scene/` into every
// translation unit that includes this header.
class Node;

// Added group `editor_node_property_updates` (docs/tool-groups-added.json,
// GDR-28) - one tool, authored by TASK-063 section 3:
//
//   editor_set_node_property_updates
//
// It is `channel = editor`, `scope = editor`, `mutating = true`, so it is
// registered only in an editor process and a game endpoint answers `-32601`
// without executing anything.
//
// **Why it exists (TASK-060 M-1 / D-6, the second round's capability gap).**
// The ported contract's only batch property write is
// `editor_set_node_property_batch`, whose grammar is
// `{node_type, property, value}` - one *type-scoped* value for every node of a
// class. Laying out a level is therefore one single-node write per node: the
// round-2 trace called `editor_set_node_property` 60 times (57 of them back to
// back) and the request that asked for the missing shape was answered
// `-32602 Unknown parameter 'updates'` (`c3_a5_batch_positions`).
//
// **It is deliberately not a back door.** Every write goes through
// `MCPTools::write_node_property`, the module's one property-write path, so the
// TASK-014 D-1 property-existence refusal, the TASK-018 declared-type coercion
// and the TASK-022/TASK-023 `ValueSlot` narrowing gate apply unchanged - the
// same gate `editor_set_node_property` passes through. No new narrowing point
// exists in this file (gate 6 has nothing to look for here).
//
// **The two modes are the caller's choice, and both are stated in the answer.**
// `stop_on_error: false` (the default, and the shape the contract's own
// description promises: "answer per entry whether the value landed") reports
// every entry and leaves the ones that landed in place - `status` says `ok` or
// `partial` so a partially applied call can never be read as a whole success.
// `stop_on_error: true` is all-or-nothing like the rest of this module's
// batches: the first refusal stops the call and every entry that already landed
// is put back to the value it had, so the caller who asked to stop at the first
// error is not left with a half-applied scene.
//
// Behaviour is documented at the definition; the entry point takes a root
// `Node *` (not the edited scene) for the same reason the other two batch groups
// do: the doctest binary has no `SceneTree`, so a tool-level test could only ever
// observe the `-32000` "no edited scene" guard.
namespace MCPTools {

// The request-shape pass of `editor_set_node_property_updates`, on its own.
//
// It exists so the *handler* can run it **before** the editor guard: a malformed
// entry (`updates[0].path` missing, an unknown member inside an element, a
// non-object element) is a request-shape violation, and the module's rule is
// that such a violation is a `-32602` in every process rather than a `-32000`
// that hides it (PLAYBOOK section 6.2; the same ordering
// `editor_add_nodes_batch` records for its `resolve_within_batch`).
//
// `set_node_property_updates_on` calls the same pass again, because it is an
// exported entry point and a direct caller must not be able to hand it a
// malformed array. The pass is a pure read of the request, so running it twice
// costs nothing and cannot disagree with itself.
bool validate_node_property_updates(const Array &p_updates, MCPToolError &r_error);

// Applies an `editor_set_node_property_updates` request against `p_root`.
//
// Returns the success payload, or fills `r_error` and returns nil. The only
// whole-call refusals are a malformed `updates` (a `-32602` naming the index)
// and, in `p_stop_on_error` mode, the first entry the engine refused - in which
// case the payload is attached to `error.data` instead and every entry that had
// landed was reverted first.
//
// `p_updates` is the validated-but-untrusted array: each element must be an
// object with exactly `path`, `property` and `value`.
Variant set_node_property_updates_on(Node *p_root, const Array &p_updates, bool p_stop_on_error,
		MCPToolError &r_error);

} // namespace MCPTools

void register_editor_node_property_updates_tools(MCPToolRegistry &r_registry);
