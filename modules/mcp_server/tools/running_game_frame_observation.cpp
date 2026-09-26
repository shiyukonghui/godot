/**************************************************************************/
/*  running_game_frame_observation.cpp                                    */
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
#include "running_game_frame_observation.h"

#include "../mcp_deferred.h"
#include "tool_builder.h"
#include "tool_helpers.h"

#include "core/crypto/crypto_core.h"
#include "core/io/image.h"
#include "core/math/math_funcs.h"
#include "core/object/object.h"
#include "core/string/ustring.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"

using namespace MCPTools;

// ---------------------------------------------------------------------------
// running_game_frame_observation - the three frame-clock tools of B2.
//
// Migration source (semantic reference, read-only): the game-process half lives
// in `addons/godot_mcp_rs/mcp_runtime_agent.gd` (the Rust GDExtension forwards to
// it over the `user://` file IPC, `godot_mcp_gdext/src/commands/runtime.rs`):
//
//   * `_cmd_monitor_properties`  - runtime.rs:273 / mcp_runtime_agent.gd:201
//   * `_cmd_wait_for_node`       - runtime.rs:396 / mcp_runtime_agent.gd:478
//   * `_cmd_capture_frames`      - runtime.rs:256 / mcp_runtime_agent.gd:167
//
// All three were `await`-driven coroutines on the game side and were reached
// through a request/response file handshake from the editor. Inside the game
// process both halves disappear: there is no IPC to wait for, and the only thing
// that still has to span frames is the observation itself. They are therefore
// written as `MCPDeferred::Task`s (GDR-20): the handler validates the arguments
// and hands the transport a task, and the transport's per-frame budget drives it
// with the SceneTree frame counter. No tool here ever sleeps or waits.
//
// Shared decisions:
//
//   * `frame_interval` / `poll_frames` must be **at least 1**. The migration
//     source accepted 0, and with 0 it observes the same frame N times - the
//     exact defect (N identical samples) TASK-010 recorded as the counterexample
//     for this whole task. Accepting 0 would reintroduce it under a different
//     name, so it is refused with `-32602` and a readable reason (PLAYBOOK
//     section 6.2: a parameter that cannot do anything must not be silently
//     accepted).
//   * the awaiting side never holds a raw `Node *` across frames. The migration
//     source does (`var node := _find_node(node_path)` before the loop); in C++
//     that is a use-after-free as soon as the node is deleted between two
//     samples. The sampling task holds the node's `ObjectID` and resolves it
//     again every tick, so a node that disappears turns into a clean `-32001`
//     instead of a crash.
//   * a path parameter is echoed back **resolved** (the absolute path), which is
//     the rule the observation group already established (PLAYBOOK section 6.7).
//   * timeouts belong to the framework (GDR-20 point 4): a task only reports its
//     own budget through `get_timeout_ms()`, and the transport turns an expired
//     wait into `-32000` with `data.suggestion` and `data.timeout_ms`.
// ---------------------------------------------------------------------------

// A required JSON array of strings. A missing key and a mistyped element are
// both `-32602` (the `properties` member is `required` in the contract), and the
// message names the caller's own path for every element.
static bool _require_string_array(const Dictionary &p_args, const String &p_key, Vector<String> &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() == Variant::NIL) {
		r_error = MCPToolError::invalid_params("Missing required parameter: " + p_key);
		return false;
	}
	if (value.get_type() != Variant::ARRAY) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be an array of strings, got %s",
				p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	const Array array = value;
	for (int i = 0; i < array.size(); i++) {
		const Variant item = array[i];
		if (item.get_type() != Variant::STRING) {
			r_error = MCPToolError::invalid_params(vformat("Parameter '%s[%d]' must be a string, got %s",
					p_key, i, Variant::get_type_name(item.get_type())));
			return false;
		}
		r_out.push_back(item);
	}
	return true;
}

// `max_depth`-style clamp for an `int64_t` that is about to become an `int`.
static int _int_clamped(int64_t p_value) {
	static const int64_t INT_MAX_64 = 2147483647;
	static const int64_t INT_MIN_64 = -2147483648;
	if (p_value > INT_MAX_64) {
		return (int)INT_MAX_64;
	}
	if (p_value < INT_MIN_64) {
		return (int)INT_MIN_64;
	}
	return (int)p_value;
}

namespace MCPTools {

// TASK-053 section 2.3 (M-5): the whole rule of `sample_stride`, in one place
// and with no dependency on a game being up - which is what makes it testable in
// the `--test` process (`tools/running_game_frame_observation.h`).
bool sample_is_returned(int p_index, int p_stride) {
	if (p_stride <= 1) {
		return true;
	}
	return p_index >= 0 && (p_index % p_stride) == 0;
}

} // namespace MCPTools

// A count of frames that has to be at least one, or `-32602`.
static bool _require_at_least_one(const Dictionary &p_args, const String &p_key, int64_t p_default, int64_t &r_out, MCPToolError &r_error) {	if (!optional_int(p_args, p_key, p_default, r_out, r_error)) {
		return false;
	}
	if (r_out < 1) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter '%s' must be at least 1: an observation needs the game to advance at least one frame, and %d would observe one frame repeatedly",
				p_key, (int)r_out));
		return false;
	}
	return true;
}

// A positive, finite number of seconds (the `timeout` member of
// `running_game_find_node_when_available`). The value and the "absent means the
// default" / "INT is a number" rules come from the shared
// `MCPTools::optional_float` (`tools/tool_helpers.*`, hoisted by the repair
// pass). What stays here are this tool's two own refusals: the wrong-type
// message names seconds (TASK-010's doctest pins it) and a present number must
// be positive and finite.
static bool _optional_positive_seconds(const Dictionary &p_args, const String &p_key, double p_default, double &r_out, MCPToolError &r_error) {
	const Variant value = p_args.get(p_key, Variant());
	if (value.get_type() != Variant::NIL && value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be a number of seconds, got %s",
				p_key, Variant::get_type_name(value.get_type())));
		return false;
	}
	double seconds = 0.0;
	if (!optional_float(p_args, p_key, p_default, seconds, r_error)) {
		// Unreachable after the type test above; kept so the shared reader owns
		// the cast and the default.
		return false;
	}
	if (value.get_type() != Variant::NIL && (!Math::is_finite(seconds) || seconds <= 0.0)) {
		r_error = MCPToolError::invalid_params(vformat("Parameter '%s' must be a positive finite number of seconds, got %s",
				p_key, (String)value));
		return false;
	}
	r_out = seconds;
	return true;
}

// The `sha256` of one captured frame, as lowercase hex. This is what makes the
// frames of a run *comparable*: TASK-011 section 2.2 requires the tool to prove
// that `count` frames are not `count` copies of one frame, and a digest of the
// encoded PNG answers that in one value that can be compared across calls.
static String _sha256_hex(const Vector<uint8_t> &p_bytes) {
	unsigned char hash[32];
	if (CryptoCore::sha256(p_bytes.ptr(), (size_t)p_bytes.size(), hash) != OK) {
		return String();
	}
	return String::hex_encode_buffer(hash, 32);
}

// ---------------------------------------------------------------------------
// running_game_get_node_property_samples (old `monitor_properties`)
//
// Observable contract (as implemented):
//   * `node_path` (string, required; blank -> -32602), `properties` (array of
//     strings, required), `frame_count` (integer, default 60, >= 1),
//     `frame_interval` (integer, default 1, >= 1), `sample_stride` (integer,
//     default 1, >= 1 - TASK-053 section 2.3, M-5);
//   * one sample every `frame_interval` frames, `frame_count` times, each
//     `{"frame": <sample index>, <property>: <value>, ...}` with every value
//     through the module's single `serialize_variant`;
//   * `{"node_path": <resolved absolute path>, "samples": [...],
//     "frame_count": <returned sample count>}`, and - only when the caller asked
//     for a stride greater than 1 - `"sample_stride"` and `"observed_count"`;
//   * TASK-053 section 2.3 (M-5) added `sample_stride`, and it is a **payload**
//     knob, not a time knob: the game is still observed every `frame_interval`
//     frames (`observed_count` of them), and the answer carries every
//     `sample_stride`-th observation, the first one always. Omitting it (or
//     passing 1) answers the shape above with no extra key, byte for byte;
//   * a node that is not there when the call arrives -> `-32001`; a node that
//     disappears while the series runs -> `-32001` as well (the migration source
//     would have dereferenced a freed object); no running scene -> `-32000`;
//     mistyped arguments -> `-32602`;
//   * the framework ceiling (30 s by default) ends a series that is still
//     running with `-32000`, `data.suggestion` and `data.timeout_ms`.
//
// `properties` is declared `required` by the contract, unlike
// `running_game_get_node_properties` where an absent list means "everything"; it
// is therefore required here too, and an *empty* list is still accepted (the
// migration source's behaviour: the sample then carries only its index).
//
// `sample_stride` versus `frame_interval` - why both exist, and why the name is
// `sample_stride`:
//   * `frame_interval` decides **when the game is observed** (the sampling grid
//     of the game clock). Raising it makes the observation cheaper and changes
//     what the series is about;
//   * `sample_stride` decides **how much of the observed series travels back**
//     (the grid of the answer). The racing test plan's own continuity assertions
//     (`RACING-TEST-PLAN.md` AC-4/AC-5) need `frame_interval: 1` - a moving body
//     sampled every 10th frame cannot be checked for "no teleport" - and that is
//     exactly the call whose answer is 23 020 bytes for three properties over
//     180 frames (REPORT-AUDIT-RACING-BACKLOG section 3.5). A stride lets that
//     call keep its one-frame observation grid and answer 18 points instead;
//   * the name is `sample_stride` rather than `sample_interval`/`sample_step`
//     because "interval" already means a frame gap in this schema
//     (`frame_interval`) and "step" already means an element of
//     `running_game_run_test_scenario`'s `steps` array. "Stride" has exactly one
//     meaning here ("keep every Nth"), and it is the word the caller needs to
//     read the answer: `observed_count` observations, one every `sample_stride`.
// ---------------------------------------------------------------------------
class NodePropertySamplesTask : public MCPDeferred::Task {
public:
	NodePropertySamplesTask(const ObjectID &p_node_id, const String &p_requested_path, const Vector<String> &p_properties,
			int p_frame_count, int p_frame_interval, int p_sample_stride, int64_t p_start_frame) :
			node_id(p_node_id),
			requested_path(p_requested_path),
			properties(p_properties),
			frame_count(p_frame_count),
			frame_interval(p_frame_interval),
			sample_stride(p_sample_stride),
			next_frame(p_start_frame) {}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_now_ms;
		if (p_frame < next_frame) {
			return MCPDeferred::TickResult::pending();
		}

		// Re-resolving through the id (instead of holding the `Node *`) is what
		// makes a node deleted between two samples a clean error.
		Node *node = ObjectDB::get_instance<Node>(node_id);
		if (node == nullptr) {
			return MCPDeferred::TickResult::failed(MCPToolError::not_found(
					vformat("Node '%s'", requested_path),
					"The node was removed while it was being sampled; sample it again from a node of the current scene"));
		}

		Dictionary sample;
		// The index of the observation in the series, not the engine frame: the
		// first observation is 0 whatever the frame clock says.
		sample["frame"] = collected;
		for (int i = 0; i < properties.size(); i++) {
			sample[properties[i]] = serialize_variant(node->get(properties[i]));
		}
		// TASK-053 M-5: every observation is made, and one in `sample_stride`
		// travels back (the first one always). Nothing is dropped silently: the
		// answer reports both counts when the stride is not 1.
		if (sample_is_returned(collected, sample_stride)) {
			samples.push_back(sample);
		}
		resolved_path = String(node->get_path());
		collected++;
		next_frame = p_frame + frame_interval;

		if (collected >= frame_count) {
			Dictionary result;
			result["node_path"] = resolved_path;
			result["samples"] = samples;
			result["frame_count"] = samples.size();
			if (sample_stride > 1) {
				result["sample_stride"] = sample_stride;
				result["observed_count"] = collected;
			}
			return MCPDeferred::TickResult::done(result);
		}
		return MCPDeferred::TickResult::pending();
	}

	String describe() const override {
		return vformat("sampling node '%s'", requested_path);
	}

private:
	ObjectID node_id;
	String requested_path;
	Vector<String> properties;
	int frame_count = 0;
	int frame_interval = 1;
	int sample_stride = 1;
	int64_t next_frame = 0;
	int collected = 0;
	String resolved_path;
	Array samples;
};

static MCPDeferred::Task *_tool_get_node_property_samples(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return nullptr;
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_path' must not be empty");
		return nullptr;
	}
	Vector<String> properties;
	if (!_require_string_array(p_args, "properties", properties, r_error)) {
		return nullptr;
	}
	int64_t frame_count = 0;
	if (!_require_at_least_one(p_args, "frame_count", 60, frame_count, r_error)) {
		return nullptr;
	}
	int64_t frame_interval = 0;
	if (!_require_at_least_one(p_args, "frame_interval", 1, frame_interval, r_error)) {
		return nullptr;
	}
	// TASK-053 M-5. `_require_at_least_one` is not reused: its message is about
	// observing a frame ("an observation needs the game to advance at least one
	// frame"), which is the wrong sentence for a stride.
	int64_t sample_stride = 0;
	if (!optional_int(p_args, "sample_stride", 1, sample_stride, r_error)) {
		return nullptr;
	}
	if (sample_stride < 1) {
		r_error = MCPToolError::invalid_params(vformat(
				"Parameter 'sample_stride' must be at least 1: a stride of %d would return no sample at all",
				(int)sample_stride));
		return nullptr;
	}

	SceneTree *tree = SceneTree::get_singleton();
	if (tree == nullptr) {
		r_error = MCPToolError::no_scene();
		return nullptr;
	}
	Node *root = tree->get_current_scene();
	if (root == nullptr) {
		r_error = MCPToolError::no_scene();
		return nullptr;
	}
	Node *node = resolve_game_node(tree, root, node_path);
	if (node == nullptr) {
		r_error = MCPToolError::not_found(vformat("Node '%s'", node_path),
				"Use running_game_get_scene_tree to list the nodes of the running scene");
		return nullptr;
	}

	// The frame the request arrived in is already the frame the dispatching
	// transport is in; the task's first observation therefore lands on the next
	// frame (the queue never ticks a task in its own start frame).
	return memnew(NodePropertySamplesTask(node->get_instance_id(), node_path, properties,
			_int_clamped(frame_count), _int_clamped(frame_interval), _int_clamped(sample_stride),
			(int64_t)tree->get_frame()));
}

// ---------------------------------------------------------------------------
// running_game_find_node_when_available (old `wait_for_node`)
//
// Observable contract (as implemented):
//   * `node_path` (string, required; blank -> -32602), `poll_frames` (integer,
//     default 5, >= 1), `timeout` (number, default 5.0, must be positive and
//     finite -> -32602 otherwise);
//   * the node is looked up every `poll_frames` frames with the shared
//     `resolve_game_node` semantics; the first hit answers
//     `{"found": true, "node_path": <resolved absolute path>, "type": ...,
//     "name": ...}`;
//   * an absolute `/root/...` path is looked up even while the game has no
//     current scene yet (that is how an autoload or a scene being loaded is
//     awaited); a relative path waits for a current scene;
//   * the wait ends with `-32000`, `data.suggestion` and `data.timeout_ms` when
//     `timeout` seconds pass without the node appearing;
//   * no SceneTree at all -> `-32000` immediately (there is nothing to poll in
//     this process), mistyped arguments -> `-32602`.
//
// **Deviation from the migration source (deliberate, task-book mandated):** the
// migration source answered `{"found": false, "node_path": ..., "timeout": true}`
// as a *success* when its own timer expired. TASK-011 section 2.3 requires the
// timeout path to be observable as `-32000` with `timeout_ms`, and GDR-20 puts
// the deadline in the framework rather than in each tool, so the expired wait is
// the framework's timeout: one rule for every deferred tool instead of one per
// tool. The caller's `timeout` becomes the task's own deadline and can only
// shorten the framework ceiling (30 s), never extend it - see
// `MCPJsonRpc::_effective_timeout`. The effective value is never hidden: it is
// what `data.timeout_ms` reports on expiry.
// ---------------------------------------------------------------------------
class FindNodeWhenAvailableTask : public MCPDeferred::Task {
public:
	FindNodeWhenAvailableTask(const String &p_node_path, int p_poll_frames, uint64_t p_timeout_ms, int64_t p_start_frame) :
			node_path(p_node_path),
			poll_frames(p_poll_frames),
			timeout_ms(p_timeout_ms),
			next_frame(p_start_frame) {}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_now_ms;
		if (p_frame < next_frame) {
			return MCPDeferred::TickResult::pending();
		}
		next_frame = p_frame + poll_frames;

		SceneTree *tree = SceneTree::get_singleton();
		if (tree == nullptr) {
			// The SceneTree can disappear while a game is shutting down; there
			// is nothing left to wait for.
			return MCPDeferred::TickResult::failed(MCPToolError::no_scene());
		}

		Node *found = nullptr;
		Node *root = tree->get_current_scene();
		if (root != nullptr) {
			found = resolve_game_node(tree, root, node_path);
		} else if (node_path.begins_with("/root/")) {
			Node *tree_root = game_tree_root(tree);
			found = tree_root != nullptr ? tree_root->get_node_or_null(NodePath(node_path)) : nullptr;
		}

		if (found == nullptr) {
			return MCPDeferred::TickResult::pending();
		}

		Dictionary result;
		result["found"] = true;
		result["node_path"] = String(found->get_path());
		result["type"] = found->get_class();
		result["name"] = String(found->get_name());
		return MCPDeferred::TickResult::done(result);
	}

	uint64_t get_timeout_ms() const override { return timeout_ms; }

	String describe() const override {
		return vformat("waiting for node '%s'", node_path);
	}

private:
	String node_path;
	int poll_frames = 5;
	uint64_t timeout_ms = 0;
	int64_t next_frame = 0;
};

static MCPDeferred::Task *_tool_find_node_when_available(const Dictionary &p_args, MCPToolError &r_error) {
	String node_path;
	if (!require_string(p_args, "node_path", node_path, r_error)) {
		return nullptr;
	}
	if (node_path.strip_edges().is_empty()) {
		r_error = MCPToolError::invalid_params("Parameter 'node_path' must not be empty");
		return nullptr;
	}
	int64_t poll_frames = 0;
	if (!_require_at_least_one(p_args, "poll_frames", 5, poll_frames, r_error)) {
		return nullptr;
	}
	double timeout_seconds = 0.0;
	if (!_optional_positive_seconds(p_args, "timeout", 5.0, timeout_seconds, r_error)) {
		return nullptr;
	}

	SceneTree *tree = SceneTree::get_singleton();
	if (tree == nullptr) {
		// Nothing to poll at all (the doctest binary, a process that never
		// started a main loop). Waiting the full `timeout` here would be a lie
		// about what this process can ever observe.
		r_error = MCPToolError::no_scene();
		return nullptr;
	}

	const uint64_t timeout_ms = (uint64_t)(timeout_seconds * 1000.0 + 0.5);
	return memnew(FindNodeWhenAvailableTask(node_path, _int_clamped(poll_frames), timeout_ms, (int64_t)tree->get_frame()));
}

// ---------------------------------------------------------------------------
// running_game_capture_frames (old `capture_frames`)
//
// Observable contract (as implemented):
//   * `count` (integer, default 5, >= 1), `frame_interval` (integer, default 10,
//     >= 1), `half_resolution` (boolean, default true);
//   * every `frame_interval` frames one frame of the running game's root viewport
//     is read back; each entry is
//     `{"index": <i>, "frame": <SceneTree frame counter>, "width", "height",
//     "image_base64": <PNG>, "sha256": <hex digest of that PNG>}`;
//   * `{"frames": [...], "count": N}` in capture order;
//   * a process without a framebuffer (the `--headless` display server, whose
//     dummy renderer has no texture storage) is refused with `-32000` and a
//     suggestion *before* the task is created, instead of returning `count`
//     empty pictures;
//   * the framework ceiling ends a still-running capture with `-32000`,
//     `data.suggestion` and `data.timeout_ms`.
//
// `frame` and `sha256` are additions to the migration source's key set
// (`index`/`width`/`height`/`image_base64`), and they are the point of the tool:
// TASK-011 section 2.2 asks for frames that are provably *not* the same frame
// copied N times, and `index` alone cannot prove it (a broken implementation
// would happily emit 0..N-1 over one image). The SceneTree frame counter proves
// the frames were really N frames apart and the digest proves the pixels differ.
// ---------------------------------------------------------------------------
class CaptureFramesTask : public MCPDeferred::Task {
public:
	CaptureFramesTask(int p_count, int p_frame_interval, bool p_half_resolution, int64_t p_start_frame) :
			count(p_count),
			frame_interval(p_frame_interval),
			half_resolution(p_half_resolution),
			next_frame(p_start_frame) {}

	MCPDeferred::TickResult tick(int64_t p_frame, uint64_t p_now_ms) override {
		(void)p_now_ms;
		if (p_frame < next_frame) {
			return MCPDeferred::TickResult::pending();
		}

		Ref<Image> image = game_viewport_image(half_resolution);
		if (image.is_null()) {
			return MCPDeferred::TickResult::failed(framebuffer_error());
		}
		const Vector<uint8_t> png = image->save_png_to_buffer();
		if (png.is_empty()) {
			return MCPDeferred::TickResult::failed(MCPToolError::internal("The captured frame could not be encoded as PNG"));
		}

		Dictionary entry;
		entry["index"] = index;
		entry["frame"] = p_frame;
		entry["width"] = image->get_width();
		entry["height"] = image->get_height();
		entry["image_base64"] = CryptoCore::b64_encode_str(png.ptr(), (size_t)png.size());
		entry["sha256"] = _sha256_hex(png);
		frames.push_back(entry);

		index++;
		next_frame = p_frame + frame_interval;

		if (index >= count) {
			Dictionary result;
			result["frames"] = frames;
			result["count"] = frames.size();
			return MCPDeferred::TickResult::done(result);
		}
		return MCPDeferred::TickResult::pending();
	}

	String describe() const override {
		return vformat("capturing %d frame(s)", count);
	}

	// Shared with the single-shot sibling in `tools/running_game_capture.cpp`
	// through `MCPTools::game_framebuffer_available()`; the wording lives here
	// because this is the tool that can discover the loss mid-series.
	static MCPToolError framebuffer_error() {
		return MCPToolError::tool_state(
				"The running game has no framebuffer to read (the headless display server has no texture storage)",
				"Run the game with a display server (drop --headless, or use a build with a rendering driver) and call the tool again");
	}

private:
	int count = 0;
	int frame_interval = 10;
	bool half_resolution = true;
	int64_t next_frame = 0;
	int index = 0;
	Array frames;
};

static MCPDeferred::Task *_tool_capture_frames(const Dictionary &p_args, MCPToolError &r_error) {
	int64_t count = 0;
	if (!_require_at_least_one(p_args, "count", 5, count, r_error)) {
		return nullptr;
	}
	int64_t frame_interval = 0;
	if (!_require_at_least_one(p_args, "frame_interval", 10, frame_interval, r_error)) {
		return nullptr;
	}
	bool half_resolution = true;
	if (!optional_bool(p_args, "half_resolution", true, half_resolution, r_error)) {
		return nullptr;
	}

	SceneTree *tree = SceneTree::get_singleton();
	if (tree == nullptr) {
		r_error = MCPToolError::no_scene();
		return nullptr;
	}
	if (!game_framebuffer_available()) {
		r_error = CaptureFramesTask::framebuffer_error();
		return nullptr;
	}

	return memnew(CaptureFramesTask(_int_clamped(count), _int_clamped(frame_interval), half_resolution, (int64_t)tree->get_frame()));
}

// ---------------------------------------------------------------------------
// Registration
//
// Order follows docs/tool-groups-b2.json. Every declaration comes from
// docs/tool-rename-map.json (`channel = running_game`, `scope = game`,
// `mutating = false`); the description and the `inputSchema` are a byte-exact
// copy of the entries of docs/tools_list.renamed.json, emitted from that file by
// `scripts/gen_b2_game_schema.py` and not retyped; re-running that script
// reproduces this block byte for byte.
//
// These are the module's first `pending_handler()` registrations: the builder
// refuses a tool that declares both halves, so "this tool answers across frames"
// is a declaration and not a convention.
// ---------------------------------------------------------------------------

void register_running_game_frame_observation_tools(MCPToolRegistry &r_registry) {
	// BEGIN generated
	// (scripts/gen_b2_game_schema.py: docs/tools_list.renamed.json entries copied byte for byte;
	//  channel/verb/scope/mutating read from docs/tool-rename-map.json. Re-running the generator
	//  --in-place reproduces this span byte for byte.)
	{
		ToolBuilder builder("running_game_get_node_property_samples", String::utf8("监控运行中游戏节点的属性随时间的变化"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("default")] = 60;
		v1[String::utf8("description")] = String::utf8("采集帧数");
		v1[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("frame_count")] = v1;
		Dictionary v2;
		v2[String::utf8("default")] = 1;
		v2[String::utf8("description")] = String::utf8("采集间隔帧数");
		v2[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("frame_interval")] = v2;
		Dictionary v3;
		v3[String::utf8("description")] = String::utf8("节点路径");
		v3[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("node_path")] = v3;
		Dictionary v4;
		v4[String::utf8("description")] = String::utf8("要监控的属性列表");
		Dictionary v5;
		v5[String::utf8("type")] = String::utf8("string");
		v4[String::utf8("items")] = v5;
		v4[String::utf8("type")] = String::utf8("array");
		v0[String::utf8("properties")] = v4;
		Dictionary v6;
		v6[String::utf8("default")] = 1;
		v6[String::utf8("description")] = String::utf8("回传采样步长：仍然每 frame_interval 帧观察一次，但只回传每第 N 个观察点（第一个恒回传）；缺省 1 与旧行为逐字节一致，大于 1 时响应追加 sample_stride 与 observed_count 两个字段（观察点总数），frame_count 始终是回传的样本数");
		v6[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("sample_stride")] = v6;
		schema[String::utf8("properties")] = v0;
		Array v7;
		v7.push_back(String::utf8("node_path"));
		v7.push_back(String::utf8("properties"));
		schema[String::utf8("required")] = v7;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("get").scope(MCPToolScope::GAME).mutating(false).schema(schema).pending_handler(_tool_get_node_property_samples);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_find_node_when_available", String::utf8("等待运行中游戏的指定节点出现"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("description")] = String::utf8("要等待的节点路径");
		v1[String::utf8("type")] = String::utf8("string");
		v0[String::utf8("node_path")] = v1;
		Dictionary v2;
		v2[String::utf8("default")] = 5;
		v2[String::utf8("description")] = String::utf8("每隔多少帧检查一次");
		v2[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("poll_frames")] = v2;
		Dictionary v3;
		v3[String::utf8("default")] = 5.0;
		v3[String::utf8("description")] = String::utf8("超时时间（秒）");
		v3[String::utf8("type")] = String::utf8("number");
		v0[String::utf8("timeout")] = v3;
		schema[String::utf8("properties")] = v0;
		Array v4;
		v4.push_back(String::utf8("node_path"));
		schema[String::utf8("required")] = v4;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("find").scope(MCPToolScope::GAME).mutating(false).schema(schema).pending_handler(_tool_find_node_when_available);
		builder.register_into(r_registry);
	}
	{
		ToolBuilder builder("running_game_capture_frames", String::utf8("连续截取运行中游戏的帧画面"));

		Dictionary schema;
		Dictionary v0;
		Dictionary v1;
		v1[String::utf8("default")] = 5;
		v1[String::utf8("description")] = String::utf8("截取帧数");
		v1[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("count")] = v1;
		Dictionary v2;
		v2[String::utf8("default")] = 10;
		v2[String::utf8("description")] = String::utf8("帧间隔");
		v2[String::utf8("type")] = String::utf8("integer");
		v0[String::utf8("frame_interval")] = v2;
		Dictionary v3;
		v3[String::utf8("default")] = true;
		v3[String::utf8("description")] = String::utf8("是否使用半分辨率");
		v3[String::utf8("type")] = String::utf8("boolean");
		v0[String::utf8("half_resolution")] = v3;
		schema[String::utf8("properties")] = v0;
		Array v4;
		schema[String::utf8("required")] = v4;
		schema[String::utf8("type")] = String::utf8("object");

		builder.channel("running_game").verb("capture").scope(MCPToolScope::GAME).mutating(false).schema(schema).pending_handler(_tool_capture_frames);
		builder.register_into(r_registry);
	}
	// END generated
}
