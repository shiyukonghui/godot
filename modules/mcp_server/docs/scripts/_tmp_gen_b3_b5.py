# -*- coding: utf-8 -*-
"""TASK-015 part 1: build docs/tool-groups-b3.json / -b4.json / -b5.json.

Temporary generator (lives outside the repository). The classifier below is the
explicit decision table; the script only enforces the invariants and serialises.
Run:  python gen_b3_b5.py <docs_dir>
"""
import collections
import io
import json
import os
import sys

DOCS = sys.argv[1]

def L(name):
    return json.load(io.open(os.path.join(DOCS, name), encoding="utf-8"))

contract = L("tools_list.renamed.json")
rename_map = L("tool-rename-map.json")
b1 = L("tool-groups.json")
b2 = L("tool-groups-b2.json")

contract_names = [t["name"] for t in contract["result"]["tools"]]
by_new = dict((t["new_name"], t) for t in rename_map["tools"])

implemented = set()
for g in b1["groups"]:
    if g.get("implemented"):
        implemented |= set(g["tools"])
for g in b2["groups"]:
    if g.get("implemented"):
        implemented |= set(g["tools"])

remaining = [n for n in contract_names if n not in implemented]

# ---------------------------------------------------------------------------
# The decision table: batch -> [(group, [tools])]
# ---------------------------------------------------------------------------
SPEC = {
 "B3": [
  ("editor_node_write", [
    "editor_add_node", "editor_delete_node", "editor_duplicate_node",
    "editor_rename_node", "editor_reparent_node", "editor_set_node_property",
    "editor_set_node_groups", "editor_connect_signal",
    "editor_disconnect_signal", "editor_set_auto_dismiss_dialogs"]),
  ("editor_node_instantiate", [
    "editor_add_scene_instance", "editor_add_raycast",
    "editor_add_mesh_instance", "editor_add_gridmap"]),
  ("editor_node_batch_write", [
    "editor_add_nodes_batch", "editor_set_node_property_batch"]),
  ("editor_control_layout_write", [
    "editor_set_anchor_preset"]),
  ("editor_node_setup", [
    "editor_setup_camera_3d", "editor_setup_collision_shape",
    "editor_setup_world_environment", "editor_setup_lighting",
    "editor_setup_navigation_agent", "editor_setup_navigation_region",
    "editor_setup_physics_body"]),
  ("editor_script_write", [
    "editor_execute_gdscript", "editor_set_node_script"]),
  ("editor_node_read", [
    "editor_get_node_properties", "editor_get_node_groups",
    "editor_find_nodes_in_group", "editor_find_nodes_by_type",
    "editor_get_node_signals", "editor_list_signal_connections"]),
  ("project_script_write", [
    "project_create_script", "project_edit_script"]),
  ("project_autoload_write", [
    "project_add_autoload", "project_remove_autoload"]),
  ("project_setting_write", [
    "project_set_setting"]),
  ("project_cross_scene_write", [
    "project_set_node_property_across_scenes"]),
  ("project_resource_uid_read", [
    "project_convert_path_to_uid", "project_convert_uid_to_path"]),
 ],
 "B4": [
  ("editor_testing_read", [
    "editor_get_test_report", "editor_analyze_screenshot_diff"]),
  ("running_game_assertion", [
    "running_game_assert_node_state", "running_game_assert_screen_text",
    "running_game_capture_signal_emissions"]),
  ("running_game_test_execution", [
    "running_game_run_test_scenario", "running_game_run_stress_test"]),
 ],
 "B5": [
  ("editor_animation_write", [
    "editor_add_animation_track", "editor_create_animation",
    "editor_remove_animation", "editor_set_animation_keyframe"]),
  ("editor_animation_tree_write", [
    "editor_create_animation_tree", "editor_add_state_machine_state",
    "editor_add_state_machine_transition", "editor_remove_state_machine_state",
    "editor_remove_state_machine_transition", "editor_set_blend_tree_node",
    "editor_set_animation_tree_parameter"]),
  ("editor_audio_write", [
    "editor_add_audio_bus", "editor_add_audio_bus_effect",
    "editor_add_audio_player", "editor_set_audio_bus_property"]),
  ("editor_particle_write", [
    "editor_create_particles", "editor_set_particle_preset",
    "editor_set_particle_color_gradient", "editor_set_particle_material"]),
  ("editor_theme_write", [
    "editor_set_control_theme"]),
  ("editor_tilemap_write", [
    "editor_remove_all_tilemap_cells", "editor_set_tilemap_cell",
    "editor_set_tilemap_cells_in_rect"]),
  ("editor_shader_write", [
    "editor_set_shader_material", "editor_set_shader_param"]),
  ("editor_physics_write", [
    "editor_set_physics_layers"]),
  ("editor_navigation_write", [
    "editor_bake_navigation_mesh", "editor_set_navigation_layers"]),
  ("editor_scene_3d_write", [
    "editor_set_material_3d"]),
  ("editor_animation_read", [
    "editor_get_animation_info", "editor_get_animation_tree_structure",
    "editor_list_animations"]),
  ("editor_audio_read", [
    "editor_get_audio_info", "editor_get_audio_bus_layout"]),
  ("editor_particle_read", [
    "editor_get_particle_info"]),
  ("editor_tilemap_read", [
    "editor_get_tilemap_cell", "editor_get_tilemap_info",
    "editor_get_tilemap_used_cells"]),
  ("editor_physics_read", [
    "editor_get_collision_info", "editor_get_physics_layers"]),
  ("editor_navigation_read", [
    "editor_get_navigation_info"]),
  ("editor_profiling_read", [
    "editor_get_performance_monitors"]),
  ("project_shader_write", [
    "project_create_shader", "project_edit_shader"]),
  ("project_theme_write", [
    "project_create_theme", "project_set_theme_color",
    "project_set_theme_constant", "project_set_theme_font_size",
    "project_set_theme_stylebox"]),
  ("project_shader_read", [
    "project_get_shader_params", "project_read_shader"]),
  ("project_theme_read", [
    "project_get_theme_info"]),
  ("project_export_read", [
    "project_get_export_info", "project_list_export_presets"]),
  ("project_android_read", [
    "project_get_android_preset_info"]),
  ("os_android_read", [
    "os_list_android_devices"]),
  ("os_android_write", [
    "os_deploy_to_android_device"]),
  ("running_game_navigation_write", [
    "running_game_move_player_to_target"]),
 ],
}

GROUP_NOTES = {
 "editor_node_write": "TASK-015 section 2 - the first B3 group and the only one this task implements. The ten editor-process, in-memory scene writes that share one dependency surface (the edited scene root plus EditorInterface) and one property-write shape. It contains both of the batch's fix_implementation_first tools: editor_disconnect_signal (the migration source ignored target_path and used the scene root as the Callable) and editor_set_auto_dismiss_dialogs (the migration source wrote a static nobody reads - pure fake success). editor_set_auto_dismiss_dialogs is not a node write; it is here because TASK-015 section 2 names it as a member of this group and because its dependency surface (EditorInterface / EditorNode level editor state, no disk write, no frame clock) is this group's.",
 "editor_node_instantiate": "Node creation of a specific engine type: an instance of another packed scene, a RayCast2D/3D, a MeshInstance3D and a GridMap. One dependency (ClassDB instantiation plus the node-add path of the group above) and one file.",
 "editor_node_batch_write": "The two batch shapes: many nodes added with one call, and one property written across many nodes. They are together because both own the batch argument grammar (a JSON array of objects) and the partial-failure policy.",
 "editor_control_layout_write": "editor_set_anchor_preset is alone: it is the one Control-layout write and needs scene/gui/control.h (LayoutPreset) that no other node write needs.",
 "editor_node_setup": "The setup_* family: one call that builds a configured subtree (camera, collision shape, world environment, lighting, navigation agent/region, physics body). One file, one shared 'instantiate + configure + add + set owner' path.",
 "editor_script_write": "The two script writes that act on the editor's live scene: attaching a script to a node and executing a caller-supplied GDScript inside the editor process.",
 "editor_node_read": "The read tools of the node family. They are in B3 because they observe exactly the state the writes of this batch produce (PLAYBOOK section 3 gate 2 requires a read-back chain per group); they cannot share editor_node_write because mutating differs. They own the node-signal inspection too, which is the read half of connect/disconnect.",
 "project_script_write": "Project-level script file writes (create / edit). They touch res:// through the shared atomic publish helper and share the GDScript validation step.",
 "project_autoload_write": "The autoload pair: one project setting key (`autoload/<name>`), added and removed. One file, one key grammar.",
 "project_setting_write": "editor_set_... the single general ProjectSettings write. Alone because it is the only tool that may write an arbitrary key, and that decision deserves its own file.",
 "project_cross_scene_write": "One property written into every scene that contains a node matching a name/path - the cross-scene shape of the node property write. Alone because it owns the multi-scene transaction (open, edit, save) policy.",
 "project_resource_uid_read": "The resource-identity reads (path <-> uid). They are the resource half of B3 and are read-only, so they cannot join a write group.",
 "editor_testing_read": "The editor-side test readers: the report of the last run and the screenshot diff. Read-only, one file, one dependency (the editor's test artefacts).",
 "running_game_assertion": "The running game's assertion/observation tools (node state, screen text, signal emissions). All read-only and all answer from the current frame, so they share running_game_observation's dependency without sharing its file.",
 "running_game_test_execution": "The two scenario drivers. They are mutating because they run the caller's scenario (input, waits, assertions) inside the game process, and they are the group that will need the deferred channel (GDR-20) the same way play_input_recording did.",
 "editor_animation_write": "Animation resource writes: create/remove an Animation, add a track, set a keyframe.",
 "editor_animation_tree_write": "AnimationTree writes: create the tree, add/remove state machine states and transitions, set a blend-tree node and a tree parameter.",
 "editor_audio_write": "Audio bus layout and AudioStreamPlayer writes.",
 "editor_particle_write": "GPUParticles writes: creation, a preset, a colour gradient and a process material.",
 "editor_theme_write": "editor_set_control_theme is alone: it is the one Control theme write and the only editor tool that needs a Theme resource on a Control.",
 "editor_tilemap_write": "TileMap writes. Contains the two data-destructive fix_implementation_first tools (set_tilemap_cell, set_tilemap_cells_in_rect) - they are B5 by subsystem and are NOT part of TASK-015.",
 "editor_shader_write": "ShaderMaterial assignment and ShaderMaterial parameter writes.",
 "editor_physics_write": "editor_set_physics_layers is alone: it writes the project's collision layer names through ProjectSettings, not through the scene.",
 "editor_navigation_write": "Navigation writes: baking a NavigationMesh (fix_implementation_first) and setting the navigation layer names.",
 "editor_scene_3d_write": "editor_set_material_3d is alone: it assigns a material to a MeshInstance3D surface, which is a different path from editor_set_shader_material.",
 "editor_animation_read": "Animation reads: one animation, an AnimationTree's structure, the list of animations.",
 "editor_audio_read": "Audio reads: one bus's info and the whole bus layout.",
 "editor_particle_read": "editor_get_particle_info is alone: the one particle read.",
 "editor_tilemap_read": "TileMap reads: one cell, the layer info, the used cells. The read half of editor_tilemap_write.",
 "editor_physics_read": "Physics reads: collision info and the collision layer names.",
 "editor_navigation_read": "editor_get_navigation_info is alone: the one navigation read.",
 "editor_profiling_read": "editor_get_performance_monitors is alone: the profiling read, and the tool get_editor_performance was merged into (GDR-17).",
 "project_shader_write": "Project shader file writes (create / edit).",
 "project_theme_write": "Theme resource writes: create the theme and set its four entry kinds (colour, constant, font size, stylebox).",
 "project_shader_read": "Project shader reads: the parameters of a shader resource and the raw shader text.",
 "project_theme_read": "project_get_theme_info is alone: the one theme read.",
 "project_export_read": "Export reads: the export info and the export presets.",
 "project_android_read": "project_get_android_preset_info is alone: the Android export preset read.",
 "os_android_read": "os_list_android_devices is alone: the one os-channel read.",
 "os_android_write": "os_deploy_to_android_device is alone: the one os-channel write, and the only tool of the module that talks to a device.",
 "running_game_navigation_write": "running_game_move_player_to_target is alone: the one game-scope movement write, split from running_game_test_execution because it is a movement and not a test.",
}

# ---------------------------------------------------------------------------
# Invariants
# ---------------------------------------------------------------------------
seen = collections.Counter()
docs = {}
for batch, groups in SPEC.items():
    total = 0
    out_groups = []
    for name, tools in groups:
        if not tools:
            sys.exit("FATAL: %s/%s is empty" % (batch, name))
        if len(tools) > 10:
            sys.exit("FATAL: %s/%s has %d tools (> 10)" % (batch, name, len(tools)))
        chans = set()
        scopes = set()
        muts = set()
        for t in tools:
            seen[t] += 1
            e = by_new.get(t)
            if e is None:
                sys.exit("FATAL: %s/%s lists unknown tool %s" % (batch, name, t))
            chans.add(e["channel"]); scopes.add(e["scope"]); muts.add(bool(e["mutating"]))
        if len(chans) != 1 or len(scopes) != 1 or len(muts) != 1:
            sys.exit("FATAL: %s/%s mixes channel/scope/mutating: %s %s %s" % (batch, name, chans, scopes, muts))
        total += len(tools)
        if name not in GROUP_NOTES:
            sys.exit("FATAL: group %s has no note" % name)
        out_groups.append({
            "name": name,
            "batch": batch,
            "channel": sorted(chans)[0],
            "scope": sorted(scopes)[0],
            "mutating": sorted(muts)[0],
            "implemented": (name == "editor_node_write"),
            "tools": tools,
            "notes": GROUP_NOTES[name],
        })
    docs[batch] = out_groups

dups = sorted(n for n, c in seen.items() if c > 1)
if dups:
    sys.exit("FATAL: tool(s) in more than one group: %s" % dups)
foreign = sorted(set(seen) - set(remaining))
if foreign:
    sys.exit("FATAL: tool(s) that are not unimplemented contract entries: %s" % foreign)
absent = sorted(set(remaining) - set(seen))
if absent:
    sys.exit("FATAL: unimplemented tool(s) missing from the three manifests: %s" % absent)
allseen = set(seen)
b12 = set()
for g in b1["groups"]:
    b12 |= set(g["tools"])
for g in b2["groups"]:
    b12 |= set(g["tools"])
inter = sorted(allseen & b12)
if inter:
    sys.exit("FATAL: overlap with B1/B2: %s" % inter)

print("remaining          = %d" % len(remaining))
print("classified exactly once = %d" % len(seen))
print("B3=%d tools/%d groups  B4=%d/%d  B5=%d/%d" % (
    sum(len(g["tools"]) for g in docs["B3"]), len(docs["B3"]),
    sum(len(g["tools"]) for g in docs["B4"]), len(docs["B4"]),
    sum(len(g["tools"]) for g in docs["B5"]), len(docs["B5"])))

# ---------------------------------------------------------------------------
# Serialise
# ---------------------------------------------------------------------------
NOTES = {
 "B3": "B3 is the write batch that the node/script/resource families of DESIGN-DETAIL.md section 10 name, plus the read tools that observe exactly the state those writes produce (the state-chain evidence of PLAYBOOK section 3 gate 2). Groups are split by channel + scope + mutating; a group is one tools/<group>.{h,cpp} file. Only editor_node_write is implemented by TASK-015.",
 "B4": "B4 is the test and assertion batch: the editor-side test report/screenshot-diff readers, the running game's three assertion/observation tools, and the two scenario/stress runners. The mutating split is forced by GDR-18 exactly as it was for the capture family in B2.",
 "B5": "B5 is every remaining subsystem batch named by DESIGN-DETAIL.md section 10: animation, animation_tree, audio, theme, tilemap, particle, navigation, physics, scene_3d, shader, export, android, profiling and the one game-scope movement write. A tool is put in B5 when the subsystem it drives (not the shape of its argument) is one of those; a tool whose subsystem also needs a B3 write (a script, a resource identity) stays in B3.",
}

for batch in ("B3", "B4", "B5"):
    doc = collections.OrderedDict()
    doc["_comment"] = ("%s group manifest for TASK-015. The unimplemented contract entries of "
        "docs/tools_list.renamed.json are partitioned into B3/B4/B5 so that each group is one "
        "tools/<group>.{h,cpp} file: one channel, one scope, one mutating value, at most 10 tools, "
        "every tool exactly once across the three files. The union of the three manifests is exactly "
        "the contract minus the 66 B1/B2 tools; docs/scripts/check_tool_groups.py --batch %s and "
        "--check-completeness make that assertion executable." % (batch, batch))
    doc["batch"] = batch
    doc["total"] = sum(len(g["tools"]) for g in docs[batch])
    doc["source"] = {
        "batch_list": "docs/DESIGN-DETAIL.md section 10 (%s)" % batch,
        "names": "docs/tools_list.renamed.json (171 entries) minus the 66 tools of docs/tool-groups.json and docs/tool-groups-b2.json",
        "map": "docs/tool-rename-map.json (v1.1, 174 entries; channel/scope/mutating are read from it, never invented)",
        "excluded": "none: the two unregister_until_implemented entries are absent from the 171 entry contract already",
    }
    doc["counts"] = {
        "unimplemented_contract_tools": len(remaining),
        "unimplemented_in_this_batch": doc["total"],
        "groups": len(docs[batch]),
    }
    doc["notes"] = {
        "partition_axis": NOTES[batch],
        "fix_implementation_first": [t for t in sorted(seen) if by_new[t]["disposition"] == "fix_implementation_first" and t in set(x for g in docs[batch] for x in g["tools"])],
    }
    doc["groups"] = docs[batch]
    path = os.path.join(DOCS, "tool-groups-%s.json" % batch.lower())
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(doc, ensure_ascii=False, indent=2))
        f.write("\n")
    print("wrote %s" % path)
