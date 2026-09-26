/**************************************************************************/
/*  editor_node_write.h                                                   */
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
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// `Node` and `Object` are only ever used through a pointer by the helpers
// declared below, so the class names are forward declared instead of dragging
// `scene/` into every translation unit that includes this header.
class Node;
class Object;

// B3 group `editor_node_write` (the manifest is docs/tool-groups-b3.json) - the
// first group of the B3 batch and the only one TASK-015 implements:
//
//   editor_add_node                 (node.rs:167)
//   editor_delete_node              (node.rs:202)
//   editor_duplicate_node           (node.rs:269)
//   editor_rename_node              (node.rs:211)
//   editor_reparent_node            (node.rs:291, old `move_node`)
//   editor_set_node_property        (node.rs:221, old `update_property`)
//   editor_set_node_groups          (node.rs:501)
//   editor_connect_signal           (node.rs:319)
//   editor_disconnect_signal        (node.rs:344, fix_implementation_first)
//   editor_set_auto_dismiss_dialogs (editor.rs:613, fix_implementation_first)
//
// Every tool of this group is `scope = editor` and `mutating = true`
// (docs/tool-rename-map.json), so all ten are guarded by
// `MCP_EDITOR_TOOLS_ENABLED`, are registered only in an editor process, and a
// game process must answer `-32601` without executing anything.
//
// The invariants this file owns, beyond "the call returned the right JSON"
// (TASK-015 section 2):
//
//   1. **an editor-side node property write follows the TASK-014 shape.** The
//      property is asked for *before* anything is written (the shared
//      `MCPTools::write_node_property` of tools/running_game_node_write.h is the
//      one definition of that rule), so an unknown property is `-32001` and a
//      write that the engine ignored can never be read as a success.
//   2. **`editor_disconnect_signal` disconnects the connection the caller named.**
//      The migration source ignored `target_path` entirely and always built the
//      `Callable` from the scene root (node.rs:355), so it could disconnect a
//      different connection than the one asked for - or nothing at all - and
//      still answer `{"disconnected": true}`. The first half of this file's
//      TDD pair (see the report) is a red test that pins the difference.
//   3. **`editor_set_auto_dismiss_dialogs` never reports a success it did not
//      perform.** The migration source wrote one `static AtomicBool` that nothing
//      in the whole addon ever reads (editor.rs:31/618) and answered success.
//      This editor has no process-wide "auto dismiss dialogs" knob (the
//      `set_hide_on_ok` calls of `editor/**` are per dialog and hard coded), so
//      the honest answer is `-32000 not_implemented` with a
//      `data.suggestion`, which is what this tool returns.
//
// The helper functions below are declared here for the same reason
// `write_node_property` is declared in tools/running_game_node_write.h: the
// doctest binary has no `SceneTree` at all (`SceneTree::get_singleton()` is
// nullptr), so a *tool-level* test can only ever observe the `-32000` "no
// edited scene" guard. The entry points below take the nodes, which is what lets
// the cases pin the real behaviour - including both fix-first defects - against
// bare `Node` objects. Behaviour is documented at each definition.
namespace MCPTools {

// `Node` for a ClassDB type name, or nullptr + `-32602` when the name is not a
// class that exists or is not a `Node` subclass. `p_name` is applied through
// `Node::set_name()`; the returned pointer is owned by the caller.
Node *instantiate_node_of_type(const String &p_type, const String &p_name, MCPToolError &r_error);

// Applies every `property: value` pair of `p_properties` through
// `MCPTools::write_node_property`, so the editor-side `properties` map of
// `editor_add_node` has exactly one property-write rule in the module.
bool apply_node_properties(Node *p_node, const Dictionary &p_properties, MCPToolError &r_error);

// Writes one property on `p_node` and answers the TASK-014 shape
// (`node_path` / `property` / `old_value` / `new_value`), with `node_path`
// expressed relative to `p_root` (the migration source's own spelling for every
// node it returns).
Variant set_node_property_on(Node *p_root, Node *p_node, const String &p_property, const Variant &p_raw_value, MCPToolError &r_error);

// Renames `p_node` and reports the name the engine actually applied.
// `Node::set_name()` *sanitises* rather than fails (`String::validate_node_name`,
// scene/main/node.cpp:1450), so a caller who asked for `a/b` gets `a_b`; the
// migration source reported the requested string as `new_name` either way.
// `r_sanitized` is true exactly when the engine changed the name.
String rename_node_to(Node *p_node, const String &p_name, bool &r_sanitized);

// Connects `p_source.signal` to `p_target.method`. `r_already_connected` is true
// when the connection was already there (the requested end state holds, so it is
// a success, but the caller is told it was not this call that made it).
// A signal the source does not have, or a `connect()` the engine refused, is a
// `-32001` / `-32000` instead of the migration source's unconditional success.
//
// TASK-040 D-2: the connection is made with `CONNECT_PERSIST`, because that is
// the only flag `PackedScene` serialises (`scene/resources/packed_scene.cpp:1238`,
// restored at `:760`) - without it the answer said `connected` while the next
// save dropped the connection (RACING-FINDINGS section 4 D-2). An *existing*
// non-persistent connection is remade with the bit, so `already_connected` and
// `persisted` can both be true. `r_persisted` is read back from the live
// `Object::Connection` flags, so the answer can only claim a persistence the
// connection really has.
bool connect_signal_on(Node *p_source, const StringName &p_signal, Object *p_target, const String &p_method, bool &r_already_connected, bool &r_persisted, MCPToolError &r_error);

// Disconnects exactly the connection `p_source.signal -> p_target.method`.
// A connection that is not there - or a signal the source does not have - is a
// `-32001` with a suggestion. This is the function the first fix-first red test
// of TASK-015 section 2 is about.
//
// TASK-040 D-2: the lookup is `Object::is_connected`, which matches the callable
// and ignores the flags, so a connection carrying `CONNECT_PERSIST` - i.e. one a
// scene save would keep - is removed by exactly the same call. `r_was_persistent`
// reports whether the connection that was removed was such a one.
bool disconnect_signal_from(Node *p_source, const StringName &p_signal, Object *p_target, const String &p_method, bool &r_was_persistent, MCPToolError &r_error);

} // namespace MCPTools

void register_editor_node_write_tools(MCPToolRegistry &r_registry);
