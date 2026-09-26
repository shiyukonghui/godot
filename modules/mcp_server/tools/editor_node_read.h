/**************************************************************************/
/*  editor_node_read.h                                                    */
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
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// `Node` is only ever used through a pointer by the helpers declared below, so
// the class name is forward declared instead of dragging `scene/` into every
// translation unit that includes this header.
class Node;

// B3 group `editor_node_read` (docs/tool-groups-b3.json) - the six read tools of
// the node family, and the read-back half of TASK-015's `editor_node_write`:
//
//   editor_get_node_properties     (node.rs:232)
//   editor_get_node_groups         (node.rs:471)
//   editor_find_nodes_in_group     (node.rs:584)
//   editor_find_nodes_by_type      (batch.rs:130)
//   editor_get_node_signals        (editor.rs:460)
//   editor_list_signal_connections (batch.rs:207)
//
// All six are `scope = editor` and `mutating = false`
// (docs/tool-rename-map.json), so they are registered only in an editor process
// and a game process must answer `-32601` without executing anything.
//
// The invariants this file owns, beyond "the call returned the right JSON":
//
//   1. **a property the caller *named* is either in the answer or a `-32001`.**
//      The migration source filtered the property list and answered
//      `properties: {}` when nothing matched (node.rs:257), so a misspelt name -
//      or a filter that named nothing the node has - was read as "the node has
//      no properties". This is PLAYBOOK section 6.6's failure mode (nothing
//      happened, reported as success) and the eighth instance of it in this
//      port; the red half of this group's TDD pair is the case that pins it.
//   2. **the visibility quirk is kept.** A full listing still skips names
//      starting with `_` and `script` (node.rs:256, PLAYBOOK section 6.8). It is
//      the read side of the write side's freedom: `editor_set_node_property` may
//      write `script`, the listing just does not enumerate internal/script
//      properties. A caller who *names* one of them is told it is not readable
//      rather than answered with an empty success.
//   3. **`editor_list_signal_connections` collects every connection.** It does
//      not filter by `CONNECT_PERSIST`; that is precisely what distinguishes it
//      from `editor_analyze_signal_flow` (GDR-17, and the migration source's
//      `get_signal_connection_list` which returns all of them).
//
// The helper functions below are declared here for the same reason
// `editor_node_write.h` declares its pair: the doctest binary has no `SceneTree`
// at all (`SceneTree::get_singleton()` is nullptr), so a *tool-level* test can
// only ever observe the `-32000` "no edited scene" guard. The entry points below
// take the nodes, which is what lets the cases pin the real behaviour against
// bare `Node` objects. Behaviour is documented at each definition.
namespace MCPTools {

// One `{name, path, type}` entry, with `path` relative to `p_root` (the root
// itself is "."). This is the shape the migration source produces in all three
// of its collectors (`collect_by_type` batch.rs:112, `find_in_group_recursive`
// node.rs:568, `serialize_selection_nodes` node.rs:613).
Dictionary node_entry(Node *p_root, Node *p_node);

// Pre-order collection of the descendants of `p_node` (including `p_node`
// itself) that match `p_type_name` **or** belong to `p_group`. At most one of
// the two is non-empty; the type test is the migration source's pair
// `get_class() == name || is_class(name)` (batch.rs:111). The order is the
// children order of the scene tree, which is deterministic.
void collect_nodes(Node *p_root, Node *p_node, const String &p_type_name,
		const String &p_group, Array &r_out);

// The readable property table of `p_node`.
//
// `p_filter` is either nullptr (list everything readable) or the exact list of
// names the caller asked for. A requested name that does not end up in `r_out`
// - because the node has no such property, or because the visibility rule keeps
// it out of the answer - is a `-32001` with a `data.suggestion`; it is never a
// silently empty success. An empty filter is a valid request for nothing.
bool node_properties(Node *p_node, const Vector<String> *p_filter,
		Dictionary &r_out, MCPToolError &r_error);

// The signal table of `p_node`, in the migration source's shape
// (`editor.rs:474-492`):
//
//   `[{name, args: [{name, type}], connections: [{target, method}]}]`
//
// `p_root` is the edited scene root the `target` of a connection is spelled
// relative to (`root.get_path_to(conn_obj)`, editor.rs:481); a `Callable` with
// no object answers `""`.
//
// `args[].type` is the **name** of the argument's type (`Variant::get_type_name`,
// "int" / "Vector2" / ...) rather than the migration source's `str(arg["type"])`,
// which stringifies the `Variant::Type` enum number. The contract does not
// prescribe the spelling; this one is the readable half of the same fact.
Array signal_entries(Node *p_root, Node *p_node);

// Every signal connection of the `p_node` subtree, flattened into
// `[{source, signal, target, method}]` in pre-order. `p_node_filter` and
// `p_signal_filter` are **substring** filters (the migration source's
// `np.find(node_filter) >= 0` / `sn.find(signal_filter) >= 0`, batch.rs:236-239);
// an empty filter matches everything. Persistent and non-persistent connections
// are both collected - see the file comment above.
//
// The collector itself is deliberately scope-free: it answers the union, and
// `filter_signal_connections_by_scope` / `count_signal_connections_by_scope`
// below are the one definition of the TASK-051 O-9 narrowing (so the counts the
// tool reports and the entries it returns can never disagree).
void collect_signal_connections(Node *p_node, Node *p_root,
		const String &p_node_filter, const String &p_signal_filter, Array &r_out);

// ---------------------------------------------------------------------------
// TASK-051 O-9: the `scope` narrowing of `editor_list_signal_connections`.
//
// Why it exists (the audit's O-9, reproduced on a 5-node scene): a scene that
// connects nothing of its own still answers ~60 connections on the editor
// endpoint, all of them the editor's *own* internal wiring - `ScriptEditor::*`,
// `SceneTreeEditor::*`, `Viewport::*` and friends. Neither `node_path` nor
// `signal_name` can separate them, because the `source` of an internal
// connection is an ordinary scene-node path (the editor connects to the edited
// scene's nodes) - only the **method** distinguishes the two kinds.
//
// The discriminator is therefore the method: a connection whose callable method
// is a `Class::method` engine binding (`ScriptEditor::_queue_update_list`,
// `Viewport::canvas_parent_mark_dirty`) is internal, and one whose method is a
// plain identifier (`_on_button_pressed`, `queue_free`) is the scene's own.
// `Object::Connection.callable.get_method()` is what both this module
// (`collect_signal_connections`) and the migration source read, and for a
// MethodBind-backed callable Godot itself spells it `Class::method`.
//
// `scope` is a closed enum rather than a boolean `exclude_editor_internal`,
// for three reasons: it uses the module's own vocabulary (the rename map
// declares a `scope` per tool); it names the axis the caller is thinking about
// ("whose connections?") instead of a negation that leaves "what is left" to be
// inferred; and it has room for the `internal` half, which is exactly what a
// caller debugging the editor's own wiring wants. Its default is `ALL`, which
// is the behaviour every earlier build had - no existing call changes.
// ---------------------------------------------------------------------------
enum class SignalConnectionScope {
	ALL, // every connection (the default; identical to the pre-TASK-051 answer)
	USER, // only connections whose method is not an engine `Class::method` binding
	INTERNAL, // only those engine/editor bindings
};

// The enum's wire spelling: `"all"`, `"user"`, `"internal"` (case sensitive, like
// every other closed vocabulary of the module). An unknown spelling is a
// `-32602` naming the three accepted values; it is never silently read as the
// default.
bool parse_signal_connection_scope(const String &p_text, SignalConnectionScope &r_scope);
const char *signal_connection_scope_name(SignalConnectionScope p_scope);

// True when `p_method` is a `Class::method` engine binding, i.e. an internal
// connection (`ScriptEditor::_queue_update_list`). A GDScript/C# method name
// cannot contain `::`, so the test cannot mistake a scene's own connection for
// an internal one.
bool signal_connection_method_is_internal(const String &p_method);

// The `connections` array narrowed to `p_scope`, preserving the collector's
// order (pre-order, then the signal list's order).
Array filter_signal_connections_by_scope(const Array &p_all, SignalConnectionScope p_scope);

// `{"all":N,"user":N,"internal":N}` for the *unfiltered* collector answer, so a
// caller that asked for `user` can still see how many internal entries exist.
Dictionary count_signal_connections_by_scope(const Array &p_all);

} // namespace MCPTools

void register_editor_node_read_tools(MCPToolRegistry &r_registry);