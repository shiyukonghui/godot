/**************************************************************************/
/*  os_android_write.h                                                    */
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

// ---------------------------------------------------------------------------
// TASK-036 (B5 batch 4): the `os_android_write` group (1 tool).
//
// `os_deploy_to_android_device` (`os`, `deploy`, `scope = both`,
// `mutating = true`). It is the module's only tool that talks to a device, and
// it is a `pending_handler` (GDR-20): a real Android export is a child process
// that takes far longer than one frame, so the request is carried by the
// deferred channel.
//
// The three real capabilities it needs are checked **before** any work starts,
// and a missing one is an honest `-32000` (with the engine's own error text and
// the exact `missing` pieces) rather than a fabricated success:
//
//   1. the named Android export preset exists (project file / `EditorExport`);
//   2. `skip_export = false` needs a platform the engine can really export
//      (`EditorExportPlatform::can_export`) - the export itself is the engine's
//      own CLI (`--export-debug|--export-release <preset> <apk>`), started with
//      `OS::create_process` and polled (never blocked on);
//   3. adb - from the configured Android SDK, else from `PATH` - plus a device
//      in `device` state (`adb devices -l`).
// ---------------------------------------------------------------------------

// TASK-036 section 1: the one os-channel write (deferred).
void register_os_android_write_tools(MCPToolRegistry &r_registry);
