/**************************************************************************/
/*  editor_script_write.h                                                 */
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

// TASK-018 section 3, group `editor_script_write` of docs/tool-groups-b3.json:
// the two script writes that act on the editor's live scene.
//
//   editor_execute_gdscript   (old `execute_editor_script`, editor.rs:353)
//   editor_set_node_script    (old `attach_script`, script.rs:282)
//
// Both are channel `editor`, `scope = editor`, `mutating = true`. The group is
// `scope = editor` only: the tools answer in the editor process and are not
// registered in a game process at all (GDR-19 section 17.3, proved on the wire
// by the `9889` half of gate 1).
//
// `editor_execute_gdscript` **follows the `running_game_execute_gdscript`
// precedent of TASK-010** exactly, because the two are one capability in two
// processes:
//   * the code is a GDScript **function body** and is *compiled for real*
//     (`GDScript` + `reload()`), never parsed as a single `Expression`
//     (the migration source used `Expression`, editor_commands.gd:364-388, which
//     cannot hold a `var`, a loop or a helper `func`);
//   * the answer is structured - `{"result", "result_type"}` - instead of the
//     migration source's `str(output)`;
//   * a body that does not compile is `-32602` ("does not compile", a malformed
//     argument), a process without a script language is `-32000` (a capability
//     that is absent, GDR-14), and a missing generated method is `-32603` (a bug
//     in the module, not in the caller's code);
//   * the generated source comes from `MCPTools::build_execute_gdscript_source()`
//     (`tools/tool_helpers.*`), the one definition both executors call, so "what
//     counts as a function body" cannot have two answers.
//
// The two tools the migration source had that this group deliberately does not
// keep:
//   * the `allow_unsafe_editor_io` guard (editor_commands.gd:415-439). It was a
//     *textual* blacklist (`ResourceSaver.save(`, `FileAccess.open(` + WRITE,
//     `DirAccess.remove_absolute(`) over code with whitespace stripped out. That
//     is trivially bypassed (`FileAccess` + `"".join(...)`, an alias, a helper
//     method) while refusing honest code, and this whole module exists to make
//     editor writes go through named, atomic tools. The renamed contract does
//     not carry the argument either, so the decision is to run the code the
//     caller sent - in the editor process, where the caller asked for it - and to
//     say so plainly rather than pretend a blacklist is a sandbox.
//   * `_mcp_print` output capture. `print()` goes to the engine log, exactly as
//     it does for the game-side executor; capturing it would mean installing a
//     global print handler that swallows the engine's own diagnostics.
namespace MCPTools {

// Execute `p_code` in this process and answer `{"result","result_type"}`.
// `p_code` is a function body; see `build_execute_gdscript_source()`.
bool execute_gdscript(const String &p_code, Dictionary &r_out, MCPToolError &r_error);

// The largest `code` this tool accepts, in UTF-8 bytes. It is a *resource*
// boundary, not a timeout: the code runs synchronously on the main thread inside
// the frame that serves the request (GDScript touches the scene tree, so it
// cannot be moved to a worker), which means a `while true: pass` body blocks the
// editor until the process is killed. The one bound that can be enforced
// honestly is therefore the size of what may be compiled and injected, and it is
// enforced with a readable `-32602` (249 KiB is well above any real script body
// and well below the point where the JSON-RPC body limit of the transport is the
// thing that refuses).
int64_t max_gdscript_bytes();

} // namespace MCPTools

void register_editor_script_write_tools(MCPToolRegistry &r_registry);
