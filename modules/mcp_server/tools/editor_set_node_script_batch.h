/**************************************************************************/
/*  editor_set_node_script_batch.h                                        */
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
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
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

// `Ref<Script>` in a signature needs the complete `Script`, and the two
// primitives below talk about real `Node`s: the editor's node writes are always
// about objects of the edited scene, never about a type-erased `Object`.
#include "core/object/script_language.h"
#include "scene/main/node.h"

// The `ADDED` group `editor_set_node_script_batch` (docs/tool-groups-added.json),
// the second half of C-4 section 4 of REPORT-AUDIT-RACING-BACKLOG:
//
//   editor_set_node_script_batch   (TASK-053 section 2.2)
//
// One channel (`editor`), one verb (`set`, already in the rename map's closed
// set), `scope = EDITOR`, `mutating = true`: it attaches a script to real nodes
// of the edited scene.
void register_editor_set_node_script_batch_tools(MCPToolRegistry &r_registry);

namespace MCPTools {

// ---------------------------------------------------------------------------
// The two read-back primitives the batch is built from.
//
// `editor_set_node_script` (the single-node tool of TASK-018) already made the
// point: the answer is what the node **really carries** after the write, not the
// write it was asked for. `Object::set_script()` is a `void` method whose
// `ERR_FAIL_COND_MSG` early-returns for an abstract script and which stores
// nothing at all when the script cannot be instantiated outside the editor, so
// "I called set_script" is not evidence that anything happened
// (`core/object/object.cpp:1049-1077`). Both halves are exported because the
// take-back is otherwise unreachable through the tool: one `script_path` for the
// whole batch means the engine either accepts it for every node or for none.
// ---------------------------------------------------------------------------

// Applies `p_script` and answers `true` only when the node carries it afterwards.
bool apply_node_script(Node *p_node, const Ref<Script> &p_script, MCPToolError &r_error);

// ---------------------------------------------------------------------------
// TASK-075 (D2): the engine's own instance-creation precondition, measured.
//
// `Object::set_script()` never asks whether the script *fits* the object
// (`core/object/object.cpp:1049-1077`), and in an **editor** process it cannot:
// `EditorNode` turns scripting off for this process
// (`editor/editor_node.cpp:8523` -> `ScriptServer::set_scripting_enabled(false)`),
// so `GDScript::can_instantiate()` is false for every non-`@tool` script and
// `set_script()` takes the placeholder branch (`object.cpp:1069-1072`) - the
// node then answers `get_script()` with the script even though nothing was
// instantiated. The real check happens one level down, when the engine creates
// the instance: `GDScript::instance_create()` refuses when the script's native
// base type is not a class of the object
// (`modules/gdscript/gdscript.cpp:420-426`), and `CSharpScript::instance_create()`
// answer the same question the same way (`modules/mono/csharp_script.cpp:2461-2465`).
//
// So a script attached by this module in the editor can be *silently dropped*
// when the scene is loaded for real (measured, TASK-074 D2/E3: 30 nodes accepted
// `extends Area2D` while being `Node2D`, the editor log said nothing and the game
// log said it 30 times). `script_readable_on()` is that engine rule, read
// directly: `get_instance_base_type()` is a class of the node.
//
// The empty base type is *not* a refusal: the engine's own check is guarded by
// `if (top->native.is_valid())`, so a script that names no native base type is
// not refused by it either. This predicate mirrors the engine, it does not
// invent a stricter rule.
bool script_readable_on(Node *p_node, const Ref<Script> &p_script);

// The message and the `data.suggestion` of that refusal, shared by the singular
// tool and by this batch so the two cannot disagree about why the write is
// refused. Both name the engine rule and both class names.
String script_incompatible_message(const Ref<Script> &p_script, const String &p_node_path, const String &p_node_class);
String script_incompatible_suggestion(const Ref<Script> &p_script, const String &p_node_class);

// Puts `p_previous` back and answers `true` only when the read-back agrees.
bool restore_node_script(Node *p_node, const Ref<Script> &p_previous);

// The transaction, on a root the caller owns (the edited scene root in the tool,
// a hand-built tree in a doctest). All-or-nothing: a refusal leaves every node
// carrying exactly the script it carried when the call arrived, and
// `r_error.data.batch` names what was taken back.
Variant assign_node_scripts_batch_on(Node *p_root, const Array &p_node_paths, const String &p_script_path,
		bool p_keep_existing, Dictionary &r_out, MCPToolError &r_error);

} // namespace MCPTools
