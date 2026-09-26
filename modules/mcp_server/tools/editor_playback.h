/**************************************************************************/
/*  editor_playback.h                                                     */
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

// TASK-012 section 1, group `editor_playback` of docs/tool-groups-b2.json:
// `editor_play_scene` and `editor_stop_scene`.
//
// Both are `scope = editor`, so they are served by the editor endpoint (9888)
// and are **absent** from a game endpoint - which is also the wire-level proof
// that starting and stopping playback is an editor action (DECISIONS D56: the
// tool that drives a game is on the game side; the tool that drives the editor's
// player is on the editor side).
//
// Playback is a child process: `EditorRunBar::play_*()` reaches
// `EditorRun::run()`, which spawns the game. `editor_stop_scene` is therefore
// also the module's lever for not leaving an orphan game behind, and its answer
// reports the state it read back rather than the request it made.
//
// TASK-024a E-10: `editor_play_scene` also tells the child which MCP port to
// listen on, by passing `--mcp-port=<port>` through the run bar's
// `p_play_args`. Until that item the child read its port from *its own* project
// settings (`godot_mcp/port`), so observing the game over MCP required editing
// the test project first. See the implementation for the full observable
// contract of both tools.
void register_editor_playback_tools(MCPToolRegistry &r_registry);

// ---------------------------------------------------------------------------
// Game-child MCP port (TASK-024a E-10).
//
// Exported rather than file-private so that a doctest can pin the *rule* and the
// probe, not just the intention. Both are module-internal: neither is a tool and
// neither is reachable through `tools/list`.
// ---------------------------------------------------------------------------

namespace MCPTools {

// True when `p_candidate` is a port a game child may be told to listen on:
// inside 1..65535 and not `p_avoid`, the port the editor's own MCP server uses
// (a child told to bind the editor's port fails to bind, and the tool would then
// have reported a port nothing can ever connect to).
bool is_usable_game_port(int p_candidate, int p_avoid);

// True when a TCP socket can really be bound on `p_port` right now. The probe
// binds and immediately releases 127.0.0.1:`p_port` - the same address and the
// same API the MCP transport uses - so an answer of `true` means "the child's
// bind is expected to succeed". On Windows this is a trustworthy occupancy test,
// not merely best effort: `NetSocketWinSock::set_reuse_address_enabled()` is
// deliberately a no-op there, so a second bind of a held port fails with
// `ERR_ALREADY_IN_USE` instead of stealing it.
bool port_is_bindable(int p_port);

// A free TCP port for a game child, or 0 when none could be probed (`r_error`
// then carries a `-32603` naming what failed). The answer was really free a
// moment ago and is released before this returns: the child - not the editor -
// is what has to hold it.
int pick_free_game_port(int p_avoid, MCPToolError &r_error);

// ---------------------------------------------------------------------------
// TASK-051 M-3: the child's command line.
//
// `EditorRun::run()` appends every element of the run bar's `p_run_args` to the
// child's command line *after* the arguments the engine itself builds
// (`editor_run.cpp:157-161`; the `--path` / `--remote-debug` / `--editor-pid` /
// `--scene` group), so this is the one place a tool can add to it. TASK-024a
// E-10 uses it for the port; TASK-051 M-3 adds `headless` and `extra_args`.
//
// The argument list is built by this pure function rather than inline, so a
// doctest can pin the three rules without an editor, a run bar or a child
// process:
//
//   1. `--mcp-port=<p_game_port>` is always the **first** argument. The tool's
//      answer names that port as the child's `endpoint`, so a caller-supplied
//      `--mcp-port` (either spelling, `--mcp-port=9889` or the two-element
//      `--mcp-port 9889`) is refused with a `-32602` instead of being appended:
//      the engine's own parser takes the *last* occurrence
//      (`MCPPort::parse`, `mcp_server.cpp:75-92`), so appending one would make
//      the answer describe a port the child is not listening on. Refusing is the
//      honest half of "compatible with the E-10 injection" - the port has
//      exactly one source, and it is the `mcp_port` argument.
//   2. `p_headless` adds exactly one `--headless` (the engine spells that alias
//      itself: `main.cpp:1453`, "no audio, no rendering"). It is *not*
//      inherited from the editor - `--headless` is absent from
//      `Main::get_forwardable_cli_arguments(CLI_SCOPE_PROJECT)`
//      (`main.cpp:1123-1155`), which is why a child of a headless editor still
//      opens a window unless it is told not to.
//   3. every `p_extra_args` element is appended verbatim, **except** that a
//      repeated `--headless` is dropped and its spelling reported in
//      `r_deduplicated`: the token is idempotent, so dropping the duplicate
//      changes nothing about the child, and the caller is told which of its
//      entries did not reach the command line instead of being left to compare
//      command lines. Everything else, including a token the engine also sets
//      (`--path`, `--scene`), is passed through unchanged - the extra arguments
//      are the caller's explicit wish and come last, so they win.
//
// Returns false with `r_error` filled on a malformed `p_extra_args` (a non-string
// or empty element, or a port spelling) and leaves `r_args`/`r_deduplicated`
// untouched.
bool build_play_args(int p_game_port, bool p_headless, const Array &p_extra_args,
		Vector<String> &r_args, Array &r_deduplicated, MCPToolError &r_error);

} // namespace MCPTools