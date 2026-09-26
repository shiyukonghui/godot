/**************************************************************************/
/*  mcp_frame_clock.h                                                     */
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
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                  */
/**************************************************************************/

#pragma once

#include "core/string/ustring.h"

// ---------------------------------------------------------------------------
// TASK-092 (item B4): a **stable** per-frame cost estimate.
//
// The deferred drivers of this module size their own deadlines from the cost of
// one frame (a scenario advances one step per frame, a stress test one iteration
// per frame), so the estimate is what the deadline is made of. TASK-090 read it
// from `Engine::get_frames_per_second()`, which is a **one-second reading
// updated once per second**: a single stalled second is inherited by every
// deadline computed during the whole next second. The round-8 session measured
// the consequence - two instances of the same 3-step scenario, one second apart,
// were given `timeout_ms: 4396` and `timeout_ms: 1150`.
//
// This replaces the moment reading with a **median over a window**:
//
//   * `note_frame()` is called exactly once per frame by `MCPServer::pump_frame`
//     (the module already runs there every frame), with the frame clock as its
//     argument so a test can drive it;
//   * the duration of a frame is the difference between two consecutive calls;
//     a gap of 0 us (two calls inside one microsecond - the doctest binary) and a
//     gap over `MAX_SAMPLE_US` (a load stall, a paused debugger, a suspended
//     process - not a frame cost) are both **not** recorded as samples;
//   * `frame_cost_ms()` is the **median** of the last `SAMPLE_COUNT` samples,
//     truncated to whole milliseconds and clamped to
//     [`FLOOR_MS`, `CEILING_MS`]. Truncation is deliberate: at 60 fps the window's
//     median is 16667 us, which truncates to **16** - the constant the deadline
//     formula used before this estimate existed, so a 60 fps process keeps
//     exactly the deadline it always had;
//   * with no samples at all (a process that never pumped a frame - the doctest
//     binary, or the first single-frame process) the answer is `FLOOR_MS`. The
//     engine's own one-second reading is deliberately **not** used as a fallback:
//     `Engine::_fps` defaults to 1 (`core/config/engine.h:67`), so a placeholder
//     would be read as "1000 ms per frame" and inflate every deadline 60x. Every
//     process that can compute a deadline has already pumped frames, because the
//     sampler runs before any request is served.
//
// The median is what makes a single outlier harmless: one 500 ms stall among
// fifteen 16 ms frames changes the median by nothing at all, while a genuinely
// slow loop (every frame slow) moves it to the slow value. The window is small
// on purpose - 15 frames is a quarter of a second at 60 fps, so a change of
// regime is reflected within one scenario's own duration.
//
// Main thread only, like every other recorder in this module: it holds no lock
// because every caller is on the same thread inside one frame.
// ---------------------------------------------------------------------------

namespace MCPFrameClock {

// How many frame durations the median is taken over.
const int SAMPLE_COUNT = 15;
// The old hard-coded frame time, kept as the floor so that a fast process cannot
// get a *shorter* deadline than it had before this estimate existed.
const uint64_t FLOOR_MS = 16;
// One second per frame: a slower frame is a stall, and the deadline formula has
// the framework ceiling (30 s) as its real bound anyway.
const uint64_t CEILING_MS = 1000;
// A gap longer than this is not recorded as a frame cost (see the header note).
const uint64_t MAX_SAMPLE_US = 2000ULL * 1000ULL;

// Samples the frame that just ended. `p_now_usec` is `OS::get_ticks_usec()`; it
// is a parameter so that a doctest can drive an arbitrary, deterministic clock.
void note_frame(uint64_t p_now_usec);

// The stable estimate, in whole milliseconds.
uint64_t frame_cost_ms();

// The number of samples currently in the window (0 when nothing was sampled).
int sample_count();

// Drops the window and the last reading. Test seam only: it changes nothing a
// running process depends on, because the next frame refills the window.
void reset_for_tests();

} // namespace MCPFrameClock
