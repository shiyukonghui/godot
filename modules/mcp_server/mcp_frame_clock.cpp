/**************************************************************************/
/*  mcp_frame_clock.cpp                                                   */
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

#include "mcp_frame_clock.h"

namespace MCPFrameClock {

namespace {
uint64_t samples[SAMPLE_COUNT];
int sample_count_value = 0;
int next_index = 0;
uint64_t last_usec = 0;
bool has_last = false;

uint64_t _clamp_ms(uint64_t p_ms) {
	if (p_ms < FLOOR_MS) {
		return FLOOR_MS;
	}
	if (p_ms > CEILING_MS) {
		return CEILING_MS;
	}
	return p_ms;
}
} // namespace

void note_frame(uint64_t p_now_usec) {
	if (!has_last) {
		has_last = true;
		last_usec = p_now_usec;
		return;
	}
	const uint64_t now = p_now_usec;
	// `last_usec` can be newer than `now` only when the clock wrapped (the
	// unsigned subtraction would then produce a huge "duration"); both readings
	// come from the same monotonic clock, so the guard is for the wrap only.
	if (now < last_usec) {
		last_usec = now;
		return;
	}
	const uint64_t delta = now - last_usec;
	last_usec = now;
	// Two calls inside one microsecond are not a frame, and neither is a stall
	// (see the header): neither is a sample.
	if (delta == 0 || delta > MAX_SAMPLE_US) {
		return;
	}
	samples[next_index] = delta;
	next_index = (next_index + 1) % SAMPLE_COUNT;
	if (sample_count_value < SAMPLE_COUNT) {
		sample_count_value++;
	}
}

uint64_t frame_cost_ms() {
	if (sample_count_value == 0) {
		// Nothing has been timed yet. The answer is the floor, and the engine's
		// own one-second reading is deliberately **not** consulted: `Engine::_fps`
		// defaults to 1 (`core/config/engine.h:67`), so "no frame rate yet" would
		// be read as 1000 ms per frame - a 60x inflated deadline manufactured out
		// of a placeholder. Every process that can compute a deadline at all has
		// already pumped frames (`MCPServer::pump_frame` samples before any
		// request is served), so this branch is reached by the doctest binary and
		// by a single-frame process, and the old constant is the right answer for
		// both.
		return FLOOR_MS;
	}

	// Insertion sort of a 15 element window: no allocation (this runs on the
	// main thread inside a frame) and no dependency on a sort helper's order for
	// equal elements, which is irrelevant here anyway.
	uint64_t sorted[SAMPLE_COUNT];
	for (int i = 0; i < sample_count_value; i++) {
		sorted[i] = samples[i];
	}
	for (int i = 1; i < sample_count_value; i++) {
		const uint64_t value = sorted[i];
		int j = i - 1;
		while (j >= 0 && sorted[j] > value) {
			sorted[j + 1] = sorted[j];
			j--;
		}
		sorted[j + 1] = value;
	}
	// The median of an even count is the upper of the two middle samples: one
	// convention has to be picked, and the upper one is the conservative choice
	// for a deadline (it never under-estimates the cost of a frame).
	const uint64_t median_us = sorted[sample_count_value / 2];
	return _clamp_ms(median_us / 1000);
}

int sample_count() {
	return sample_count_value;
}

void reset_for_tests() {
	for (int i = 0; i < SAMPLE_COUNT; i++) {
		samples[i] = 0;
	}
	sample_count_value = 0;
	next_index = 0;
	last_usec = 0;
	has_last = false;
}

} // namespace MCPFrameClock
