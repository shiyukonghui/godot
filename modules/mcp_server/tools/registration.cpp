/**************************************************************************/
/*  registration.cpp                                                      */
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
#include "registration.h"

// One include per group file. This include and the one call below are the only
// shared-file edits the owner of a group makes.
#include "project_read_template.h"
#include "project_read_analysis.h"
#include "project_read_files.h"
#include "project_write_resource_scene.h"
#include "editor_read_scene_inspector.h"
#include "editor_write_scene_editor.h"
#include "running_game_read_scene.h"
// TASK-010 opens B2 with two groups of the B2 manifest
// (docs/tool-groups-b2.json); the B1 manifest is untouched. The order follows
// the B2 manifest's group order, which is also the order the groups are ported
// in.
#include "running_game_observation.h"
#include "running_game_script_execution.h"
// TASK-011 section 2: the frame-clock group (the first users of the GDR-20
// deferred channel) and the single-shot capture group.
#include "running_game_frame_observation.h"
#include "running_game_capture.h"
// TASK-012 section 1: B2's third batch - the four groups of
// docs/tool-groups-b2.json that close B2's game-scope tools and open its
// editor-scope ones (`running_game_input`, `running_game_node_write`,
// `editor_playback`, `editor_input_read`). The order is the manifest's.
#include "running_game_input.h"
#include "running_game_node_write.h"
#include "editor_playback.h"
#include "editor_input_read.h"
// TASK-013 section 1: B2's last group - the six editor-process input
// simulation tools. The order is the manifest's.
#include "editor_input_simulation.h"
// TASK-015 section 2: the first B3 group
// (docs/tool-groups-b3.json), the editor-process in-memory node writes. It is
// the only group of the three new manifests marked implemented.
#include "editor_node_write.h"
// TASK-016 section 2: B3's second and third groups - the typed-node
// instantiation family (`editor_node_instantiate`, four tools) and the read half
// of the node family (`editor_node_read`, six tools). The order is the manifest's
// (docs/tool-groups-b3.json lists instantiate before read), and `tools/list`
// order is not a contract either way (DESIGN-DETAIL section 17.4).
#include "editor_node_instantiate.h"
#include "editor_node_read.h"
// TASK-017 section 2: B3's third batch - the batch writes
// (`editor_node_batch_write`, two tools), the one Control-layout write
// (`editor_control_layout_write`) and the seven `setup_*` builders
// (`editor_node_setup`). The order is the manifest's.
#include "editor_node_batch_write.h"
#include "editor_control_layout_write.h"
#include "editor_node_setup.h"
// TASK-018 section 3: B3's closing batch - the six remaining groups of
// docs/tool-groups-b3.json, in the manifest's order: the two editor-process
// script writes, the project-level script writes, the autoload pair, the general
// project-setting write, the cross-scene property write and the two
// resource-identity reads.
#include "editor_script_write.h"
#include "project_script_write.h"
#include "project_autoload_write.h"
#include "project_setting_write.h"
#include "project_cross_scene_write.h"
#include "project_resource_uid_read.h"
// TASK-019 section 1: B4's three groups, in docs/tool-groups-b4.json order - the
// editor's two test-artefact readers, the running game's three assertions, and
// the two scenario drivers. All three are new files this batch owns; the order
// is the manifest's, and `tools/list` order is not a contract either way
// (DESIGN-DETAIL section 17.4).
#include "editor_testing_read.h"
#include "running_game_assertion.h"
#include "running_game_test_execution.h"
// TASK-033 section 1: B5's first batch - the animation family, in
// docs/tool-groups-b5.json order (`editor_animation_write` before
// `editor_animation_tree_write` before `editor_animation_read`). The shared
// engine-facing helpers those three groups use are in `animation_shared.*`,
// which registers nothing (`tools/list` order is not a contract either way,
// DESIGN-DETAIL section 17.4).
#include "editor_animation_write.h"
#include "editor_animation_tree_write.h"
#include "editor_animation_read.h"
// TASK-034 section 1: B5's second batch - the eight remaining editor-scope
// groups of docs/tool-groups-b5.json, in manifest order: the audio write group,
// the particle write group, the three sole tools (theme, 3D material,
// navigation) and the four readers (audio, particle, navigation, profiling).
// The two shared, non-registering helper files of this batch are
// `tools/audio_shared.*` and `tools/particle_shared.*` (`tools/list` order is
// not a contract either way, DESIGN-DETAIL section 17.4).
#include "editor_audio_write.h"
#include "editor_particle_write.h"
#include "editor_theme_write.h"
#include "editor_scene_3d_write.h"
#include "editor_audio_read.h"
#include "editor_particle_read.h"
#include "editor_navigation_read.h"
#include "editor_profiling_read.h"
// TASK-035 section 1: B5's third batch - the tilemap family (three write tools,
// two of them data-destructive fix-first ports, and three readers), the editor
// shader writes, the node physics-layer write and its two readers, and the two
// project shader groups. The three shared, non-registering helper files of this
// batch are `tools/tilemap_shared.*`, `tools/shader_shared.*` and
// `tools/physics_shared.*` (`tools/list` order is not a contract either way,
// DESIGN-DETAIL section 17.4).
#include "editor_tilemap_write.h"
#include "editor_shader_write.h"
#include "editor_physics_write.h"
#include "editor_tilemap_read.h"
#include "editor_physics_read.h"
#include "project_shader_write.h"
#include "project_shader_read.h"
// TASK-036 section 1: B5's fourth batch - the closing 14 tools. The order is the
// manifest's for the new groups: the navigation write, the two theme groups, the
// two export reads, the Android preset read, the two os-channel Android tools
// and the single game-scope movement write. Two of the batch's shared,
// non-registering helper files are new (`tools/theme_shared.*`,
// `tools/android_shared.*`); `editor_navigation_write` deliberately re-registers
// nothing that `editor_navigation_read` already owns (`tools/list` order is not
// a contract either way, DESIGN-DETAIL section 17.4).
#include "editor_navigation_write.h"
#include "project_theme_write.h"
#include "project_theme_read.h"
#include "project_export_read.h"
#include "project_android_read.h"
#include "os_android_read.h"
#include "os_android_write.h"
#include "running_game_navigation_write.h"
// TASK-052 section 1 (DESIGN-DETAIL.md section 26 / GDR-28): the *added* groups,
// in `docs/tool-groups-added.json` order. These two names are not ports of the
// frozen rename map - they were authored by the decision maker and appended to
// the contract by `scripts/gen_renamed_contract.py` (`ADDED_TOOLS`) - so they are
// registered from their own files and their own manifest, and no historical
// batch manifest is touched.
#include "project_csharp_build.h"
#include "project_text_write.h"
// TASK-053 section 2: the two added groups of the C tier's second batch, in
// `docs/tool-groups-added.json` order (`project_validate_scripts`, then
// `editor_set_node_script_batch`). Like the TASK-052 pair they are not ports of
// the frozen rename map - they were authored by the decision maker and appended
// to the contract by `scripts/gen_renamed_contract.py` (`ADDED_TOOLS`) - so the
// five historical batch manifests stay untouched. (The batch's third change,
// M-5's `sample_stride`, is a SCHEMA_OVERRIDES change to the ported
// `running_game_get_node_property_samples` and adds no group here.)
#include "project_validate_scripts.h"
#include "editor_set_node_script_batch.h"
// TASK-063 section 3: the one added group of this batch, in
// `docs/tool-groups-added.json` order. Like the four above it is not a port of
// the frozen rename map - it was authored by the decision maker and appended to
// the contract by `scripts/gen_renamed_contract.py` (`ADDED_TOOLS`) - so the five
// historical batch manifests stay untouched. (The batch's other three contract
// changes are `description`-only - the two single-path entries and this group's
// own batch sibling - and add no group here.)
#include "editor_node_property_updates.h"
// TASK-075 section 2: the added group of this batch, registered last so the
// added manifest's order is the live order too (`tools/list` order is not a
// contract either way, DESIGN-DETAIL section 17.4). `project_read_text_file` is
// `scope = both` and the 177th contract entry - the symmetric half of the
// module's own added `project_write_text_file`.
#include "project_text_read.h"

void register_all_tools(MCPToolRegistry &r_registry) {
	// One call per group, in `tools/list` order.
	register_project_read_template_tools(r_registry);
	register_project_read_analysis_tools(r_registry);
	register_project_read_files_tools(r_registry);
	register_project_write_resource_scene_tools(r_registry);
	register_editor_read_scene_inspector_tools(r_registry);
	register_editor_write_scene_editor_tools(r_registry);
	// TASK-009: the last B1 group, `scope = GAME`, registered last to match the
	// group order of docs/tool-groups.json.
	register_running_game_read_scene_tools(r_registry);
	// TASK-010 section 2: the B2 game-side observation group and the E3 lever.
	register_running_game_observation_tools(r_registry);
	register_running_game_script_execution_tools(r_registry);
	// TASK-011 section 2: the frame-clock group (deferred, GDR-20) and the
	// single-shot capture group.
	register_running_game_frame_observation_tools(r_registry);
	register_running_game_capture_tools(r_registry);
	// TASK-012 section 1: the game-scope input family and the game-scope
	// property write, then the editor's play/stop pair and its InputMap read.
	register_running_game_input_tools(r_registry);
	register_running_game_node_write_tools(r_registry);
	register_editor_playback_tools(r_registry);
	register_editor_input_read_tools(r_registry);
	// TASK-013 section 1: the editor-process input simulation family, which
	// closes B2 (25/25).
	register_editor_input_simulation_tools(r_registry);
	// TASK-015 section 2: B3's first group, the editor-process node writes.
	register_editor_node_write_tools(r_registry);
	// TASK-016 section 2: B3's second group, the typed-node instantiations, and
	// its third, the node read family.
	register_editor_node_instantiate_tools(r_registry);
	register_editor_node_read_tools(r_registry);
	// TASK-017 section 2: B3's third batch, in manifest order.
	register_editor_node_batch_write_tools(r_registry);
	register_editor_control_layout_write_tools(r_registry);
	register_editor_node_setup_tools(r_registry);
	// TASK-018 section 3: B3's closing batch, in manifest order (`editor_*` first
	// because docs/tool-groups-b3.json lists the editor groups before the project
	// ones; `tools/list` order is not a contract either way, section 17.4).
	register_editor_script_write_tools(r_registry);
	register_project_script_write_tools(r_registry);
	register_project_autoload_write_tools(r_registry);
	register_project_setting_write_tools(r_registry);
	register_project_cross_scene_write_tools(r_registry);
	register_project_resource_uid_read_tools(r_registry);
	// TASK-019 section 1: B4's three groups, in manifest order (see the includes
	// above). B4 is the batch that closes M4 (B3 + B4 = 47 tools).
	register_editor_testing_read_tools(r_registry);
	register_running_game_assertion_tools(r_registry);
	register_running_game_test_execution_tools(r_registry);
	// TASK-033 section 1: B5's first batch - the 14 animation tools, in the
	// manifest's group order.
	register_editor_animation_write_tools(r_registry);
	register_editor_animation_tree_write_tools(r_registry);
	register_editor_animation_read_tools(r_registry);
	// TASK-034 section 1: B5's second batch, in the manifest's group order (the
	// two write groups first, then the four sole tools and the readers).
	register_editor_audio_write_tools(r_registry);
	register_editor_particle_write_tools(r_registry);
	register_editor_theme_write_tools(r_registry);
	register_editor_scene_3d_write_tools(r_registry);
	register_editor_audio_read_tools(r_registry);
	register_editor_particle_read_tools(r_registry);
	register_editor_navigation_read_tools(r_registry);
	register_editor_profiling_read_tools(r_registry);
	// TASK-035 section 1: B5's third batch, in the manifest's group order (the
	// three write groups, then the readers, then the two project shader groups).
	register_editor_tilemap_write_tools(r_registry);
	register_editor_shader_write_tools(r_registry);
	register_editor_physics_write_tools(r_registry);
	register_editor_tilemap_read_tools(r_registry);
	register_editor_physics_read_tools(r_registry);
	register_project_shader_write_tools(r_registry);
	register_project_shader_read_tools(r_registry);
	// TASK-036 section 1: B5's closing batch, in the manifest's group order. This
	// is the batch that closes B5 (B1..B5 = 171 tools).
	register_editor_navigation_write_tools(r_registry);
	register_project_theme_write_tools(r_registry);
	register_project_theme_read_tools(r_registry);
	register_project_export_read_tools(r_registry);
	register_project_android_read_tools(r_registry);
	register_os_android_read_tools(r_registry);
	register_os_android_write_tools(r_registry);
	register_running_game_navigation_write_tools(r_registry);
	// TASK-052 section 1: the two added tools, in the added manifest's order
	// (`project_csharp_build`, then `project_text_write`). They are `scope = both`
	// and the last two entries of the 173 entry contract, so `tools/list` order is
	// their append order (which is not a contract either way, section 17.4).
	register_project_csharp_build_tools(r_registry);
	register_project_text_write_tools(r_registry);
	// TASK-053 section 2: the batch's own two added groups, in the added
	// manifest's order. `project_validate_scripts` is `scope = both` and
	// `editor_set_node_script_batch` is `scope = editor` (registered only in an
	// editor process, by the builder's own process guard).
	register_project_validate_scripts_tools(r_registry);
	register_editor_set_node_script_batch_tools(r_registry);
	// TASK-063 section 3: the batch's own added group, registered last so the
	// added manifest's order is the live order too (`tools/list` order is not a
	// contract either way, section 17.4). `editor_set_node_property_updates` is
	// `scope = editor`, so the builder's own process guard keeps it out of a game
	// process' table entirely.
	register_editor_node_property_updates_tools(r_registry);
	// TASK-075 section 2: the batch's own added group, registered last so the
	// added manifest's order is the live order too. `project_read_text_file` is
	// `scope = both`, so both endpoints serve it and the contract's union grows
	// to 177 entries.
	register_project_text_read_tools(r_registry);
}