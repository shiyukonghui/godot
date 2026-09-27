#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate docs/tools_list.renamed.json from the old contract + the rename map.

Spec source
-----------
* docs/DESIGN-DETAIL.md section 16 item 2 (the renamed contract is the reference
  artifact of every per-batch equality gate), GDR-16, GDR-17 and GDR-18.
* docs/B0-BRIEF.md section 2 (frozen task book for B0).
* docs/tool-rename-map.json is the single source of truth (174 entries).
* docs/tasks/TASK-001-rename-map-v1.1.md section 2.5.1 (the v1.1 map shape).

The transform is mechanical and idempotent:

  * `name`         <- the map's `new_name`;
  * `description`  <- the old contract object, carried over verbatim;
  * `inputSchema`  <- the old contract object, carried over verbatim;
  * top level `id` / `jsonrpc` are carried over from the old contract;
  * `disposition == "unregister_until_implemented"` entries are dropped (2);
  * `disposition == "merge_into"` entries are dropped (1), where the surviving
    entry is named by the entry's own `merge_target` field (= its `old_name`).
    v1.1 replaced the v1.0 inline `merge_into:<old_name>` form with that field
    (D-4), and GDR-17 cancelled two of the three v1.0 merges because they were
    lossy - the two de-merged tools now each keep their own, distinct name.

Expected output: 174 - 2 unregistered - 1 lossless merge == 171 tools.

`description` / `inputSchema` may only ever change through the explicit
DESCRIPTION_OVERRIDES / SCHEMA_OVERRIDES lists below (SCHEMA_OVERRIDES is still
empty, every entry must carry a `reason` that ends up in `_meta.overrides`).
Without such an entry, not a single character of those fields is allowed to move -
the script asserts that by re-serializing both objects and comparing.

v1.2 (TASK-002 section 2.1, audit risks R-1/R-2/R-3): DESCRIPTION_OVERRIDES is no
longer empty. Seven tools stay ambiguous "by name alone" because each pair shares
channel / verb / scope / mutating and differs only in the result shape, the hit
cap or the case sensitivity, so every one of them gets one inline discriminator
sentence. The discriminators are transcribed from the *migration source* (read,
not guessed): commands/project.rs, commands/batch.rs, commands/analysis.rs.
Each override is append-only (`<old description> + " " + <discriminator>`), which
the script enforces, so no original wording can be silently dropped. A stale
override (an `old_name` that never matches) is a hard failure as well.

v1.3 (TASK-003 section 1.1, decision D49/D-1): `_meta.order_normative = false`.
The *membership* and the *content* of `result.tools` are the contract; their
*order* is explicitly not. The engine still has to be deterministic (two
consecutive `tools/list` calls of one build must be byte-identical, see
DESIGN-DETAIL section 17.4 and the doctest
`[MCPServer] tools/list is byte-identical across consecutive calls`), but it is
free to differ from the order of this file. Nothing else in the transform
changed, so the two artifacts can be compared key by key.

v1.4 (TASK-007 section 1): an override record may carry `"mode": "replace"`.
Every override was append-only until then, which is the right default - but an
append cannot fix a sentence that is *factually wrong*: the reader would keep the
false statement in the field and have to reconcile it with the appended one.
`editor_analyze_signal_flow` is the first such case (its description claimed the
persistent test was `flags & 1`, which is `CONNECT_DEFERRED` in Godot 4 while the
implementation - correctly - tests `CONNECT_PERSIST`). A replacing override is
only accepted when its `reason` quotes the text it replaces verbatim, so the
original wording stays in `_meta.overrides` even though the field is rewritten;
append remains the default and every existing entry is unchanged.

v1.5 (TASK-014 section 1 D-3, decision D59 ruling 1 + the M2 acceptance): the
first `SCHEMA_OVERRIDES` entry, and the two rules that make a schema override
auditable. `running_game_play_input_recording` (old `replay_recording`) had
`inputSchema.required = ["events"]` while its implementation - correctly - lets
`events` be omitted and replays this game process' most recent recording instead
(D59 ruling 1). The contract was the side that lied, and the decision was to fix
the contract, not the behaviour, so the *only* edit is "remove `events` from
`required`" plus the description sentence that documents the fallback:

  * a schema override is always a **replacement** (there is no append for an
    object) and must therefore carry `"mode": "replace"`, like the factual
    correction of v1.4;
  * its `reason` has to quote the removed `required` member verbatim
    (`json.dumps(..., ensure_ascii=False)` of the old list), so the member that
    disappeared from the contract is still reconstructible from
    `_meta.overrides` - a reason that does not name what it deletes is refused.

The declared/fired override bookkeeping is now per `(kind, old_name)` instead of
per `old_name`: until v1.5 a single `old_name` could not carry both a description
and a schema override, because `declared_overrides` was the *union* of the two
tables and the count check compared it against one record per fired override.
Each table is still required to fire exactly once per declared name, and a
declared name that never fires is still a hard failure.

v1.6 (TASK-024a section 1 - the E-10 item, alone after the TASK-024 mid-flight
failure): the second `SCHEMA_OVERRIDES` entry, and a `DESCRIPTION_OVERRIDES`
entry for the *same* tool. `editor_play_scene` (old `play_scene`) now injects
`--mcp-port=<port>` into the game process it spawns
(`EditorRunBar::play_*(..., p_play_args)`; `EditorInterface::play_*` does not
forward run arguments, which is why the module stopped going through it). The
port becomes discoverable only if the schema carries it - hence the optional
`mcp_port` integer - and the fact that the child's port no longer comes from the
test project's `godot_mcp/port` setting has to be readable from the contract,
otherwise the tool would only have traded one undiscoverable rule for another.
That is the description entry, and it stays **append-only** (`运行场景` is still
its prefix). The schema entry is a replacement like v1.5's, with the same
obligation: its reason names the removed `required` member verbatim (here the
empty list - this tool never had a required parameter). Both mechanisms are
unchanged; only the tables grew.

v1.7 (TASK-029 - the follow-up the TASK-028 report asked the decision maker
for): `editor_get_test_report` (old `get_test_report`) declares
`"clear": {"default": true}` while its implementation has been an explicit
opt-in since TASK-028 G-3 - an omitted `clear` reads, and only `clear: true`
deletes anything. The bridge file it deletes is `user://mcp_test_report.json`
and it is **shared**: every client of the same editor process reads the same
one, so a default that deletes means the first reader takes the report away
from the next. The decision was to fix the contract, not the behaviour
("option A"), so the *only* edit is that one member's value - `true` -> `false`
- plus the sentence that names the shared file, and both are the third
`SCHEMA_OVERRIDES` entry and the second entry that is a *pair* with a
description override of the same tool. The mechanism is v1.6's unchanged:

  * the schema entry is a replacement (`"mode": "replace"`), and its `reason`
    quotes the removed `required` member verbatim (`[]`, this schema never had
    a required parameter) as the v1.5 guard demands. On top of that guard it
    quotes the member whose *value* it rewrites, verbatim:
    `"default": true` (the spelling in the emitted JSON). A value change is not
    covered by the machinery - the guard can only see the `required` list - so
    the quotation is what keeps the replaced declaration reconstructible from
    `_meta.overrides`. Every other character of the schema (`clear.description`
    = `是否清除结果`, the two `type`s) is carried over unchanged;
  * the description entry stays **append-only** (`获取测试结果报告` is still its
    prefix): the original wording was never wrong, it was just silent about the
    destructive half of `clear`, and a caller has to be able to see that from
    `tools/list` alone.

Standard library only (Python 3.9). No third party package is used anywhere.

v1.8 (TASK-032 D6, the second half of the M4d defect report): the seventh
`DESCRIPTION_OVERRIDES` entry, for `running_game_get_node_properties` (old
`get_game_node_properties`). Its family returns **SceneTree absolute** paths -
`running_game_get_scene_tree` answers `path = "/root/Main/Actor"` - while the
`node_path` description of the same family reads "relative to the scene root"
("节点路径（相对于场景根节点）"). Measured on 9889, both spellings are accepted on
the way in (an absolute `/root/...` path, a path relative to the current scene's
root, or a by-name walk), so the tool is usable - but a client that only reads
`tools/list` could not know that, and would have to guess whether one tool's
answer can be fed into the next. The entry is **append-only** (the original
`获取运行中游戏指定节点的属性` stays first, verbatim) and declares the shape the
tool really answers with plus both accepted input spellings. Nothing else of the
transform changed, and no other field of that entry moved.

v1.9 (TASK-034 section 0, the four schema gaps TASK-033 reported): the three
`SCHEMA_OVERRIDES` entries of the animation-tree family, all `mode=replace` and
all recorded in `_meta.overrides` with the `required` member they keep quoted
verbatim.

TASK-033 measured the opposite direction of the "declared but not delivered"
defect: `editor_add_state_machine_state` / `editor_set_blend_tree_node` read an
`animation` member (both the GDScript
`addons/godot_mcp_rs/commands/animation_tree_commands.gd:271,504` and the Rust
`godot_mcp_gdext/src/commands/animation_tree.rs`) that the contract never
declared, and `editor_add_state_machine_transition` could not reach
`AnimationNodeStateMachineTransition::set_xfade_time` / `set_priority` /
`set_advance_condition` at all - so a newly created Animation state could not be
pointed at an animation and a transition could not be given a cross-fade, a
priority or an advance condition by any tool. The tools now deliver those four
members; the contract is the side that was missing them, and it is corrected
through the mechanism `DESIGN-DETAIL` section 21.5 / 23.2 point 5 prescribes
(a schema override plus a reason that names what it touches), never by hand.

v1.10 (TASK-035 section 0, the declaration TASK-034 section 7.1 reported): the
fourth `SCHEMA_OVERRIDES` entry, `mode=replace`, for `editor_set_material_3d`
(old `set_material_3d`). The contract declared its `material_slot` as `string`
while the engine's API takes an integer surface index
(`MeshInstance3D::set_surface_override_material(int p_surface, ...)`,
`scene/3d/mesh_instance_3d.cpp:375`); a client that sends `0` was answered
"must be a string". The implementation's own `material_slot` grammar (a decimal
string) was a workaround for that declaration, not a behaviour worth keeping,
so the contract is corrected. It is a *value/type* change inside one property,
which the `required` guard cannot see, so - like v1.7 - the reason quotes the
replaced member verbatim (`"material_slot": {"type": "string"}`) as well as the
removed `required` member (`["node_path", "material_path"]`, kept unchanged).

v1.11 (TASK-043, the rewrite side effect TASK-042 section 3 measured): five
*description* overrides, all **append-only** (the original wording stays first,
verbatim), one sentence each, for the five tools that really do save the whole
`project.godot` through the engine's own writer. TASK-042 measured the effect on
a real, hand-commented `project.godot`: the engine rewrites the **entire** file,
writes its own seven-line header, drops every hand-written comment, re-emits the
other settings verbatim and is idempotent - and there is no partial-publish API
(`ProjectSettings::save_custom()` has one whole-file output; `ConfigFile::save()`
likewise). The side effect was silent, so the ruling is that the text a client
reads before calling has to carry it. The five tools are the ones confirmed from
the source, never guessed:

  * `set_project_setting` (project_set_setting) - `MCPTools::publish_project_settings()`
    (`tools/project_setting_write.cpp:218`);
  * `add_autoload` / `remove_autoload` (project_add_autoload /
    project_remove_autoload) - the same helper
    (`tools/project_autoload_write.cpp:150` / `:181`);
  * `set_input_action` (editor_add_input_action) - `MCPTools::persist_input_action()`
    -> `persist_input_action_to()` -> `publish_project_settings_to()`
    (`tools/editor_input_simulation.cpp:665`, `tools/tool_helpers.cpp:788-815`);
  * `reload_plugin` (editor_reload_plugin) - `EditorNode::set_addon_plugin_enabled(name, false, false)`
    / `(name, true, false)` (`tools/editor_write_scene_editor.cpp:396-397`) ends in
    `EditorNode::_update_addon_config()` (`editor/editor_node.cpp:4548` / `:4627`),
    which is **not** gated on `p_config_changed` and arms
    `ProjectSettingsEditor::queue_save()` (`editor/settings/project_settings_editor.cpp:97-99`,
    1.5 s one-shot timer -> `_save()` -> `ProjectSettings::save()`, `:102-106`).

The sentence is conditional ("when this call saves"), because three of the five
have paths that write nothing (`project_add_autoload` on an already-present
autoload, `editor_add_input_action` in a process without a `project.godot`,
`editor_reload_plugin` with no addon enabled). No `inputSchema` moves, no
parameter is added, and no other description changes: the five entries below are
the only diff of the transformed contract apart from `_meta`.

v1.12 (TASK-050 N-2, the honesty gap the racing-backlog audit recorded as N-2):
one **append-only** description override, for `project_validate_script` (old
`validate_script`). The tool resolved the file's language from its extension and
fell back to GDScript when that language was absent, so a legitimate `.cs` file in
a `module_mono_enabled=no` build was answered `{"error_text":"ERR_PARSE_ERROR",
"valid":false,"message":"Compilation failed. Check the script for errors."}` -
this build's missing C# backend was published as the file's compile failure. The
fallback is gone (a language the build does not contain is now a `-32000` refusal
with `data.suggestion`), and the sentence appended here is what tells a client
that `valid` is only ever a verdict of the file's **own** language. The original
`验证脚本语法` stays first, verbatim, and nothing but that one description and
`_meta` moves.

v1.13 (TASK-051, the B-tier `inputSchema` batch the racing-backlog audit
scheduled as C-3 / O-9 / O-4 / O-5 / M-3): **five `SCHEMA_OVERRIDES` entries,
all `mode=replace`** - the count of contract entries (171) does not move, only
five `inputSchema` objects do, so the whole batch is one contract regeneration
away from the authority. Each entry adds members only (no member that existed is
dropped or re-typed), and every reason quotes the `required` member it keeps
verbatim, as the v1.5 guard demands:

  * `batch_add_nodes` (`editor_add_nodes_batch`) gains the optional boolean
    `resolve_within_batch` (default `false`). The measured defect (audit §4.3,
    `editor_node_batch_write.cpp:251-258`): the parent path was resolved against
    the tree *as it was when the call arrived*, so `nodes[1].parent_path="P1"`
    with `P1` created by `nodes[0]` answered `-32001 nodes[1]: parent 'P1'` and
    rolled the whole request back. The schema is the only place a client can
    learn that the batch *can* build a subtree in one call;
  * `find_signal_connections` (`editor_list_signal_connections`) gains the
    optional enum string `scope` (`all` / `user` / `internal`, default `all`).
    The measured defect (audit §5.9): a 5-node scene with no hand-made
    connection of its own answered 60 of 60 connections and 12 659 B, all of them
    the editor's own `Class::method` wiring, and neither `node_path` nor
    `signal_name` can separate them (the `source` of an internal connection is an
    ordinary scene-node path). `scope` is an enum rather than a boolean so the
    `internal` half is expressible too, and its default is the pre-TASK-051
    answer. The `signal_name` substring filter is deliberately **not** changed -
    it is the frozen discriminator against `editor_analyze_signal_flow`
    (GDR-17 / R-1);
  * `simulate_input_sequence` (`editor_simulate_input_sequence`) gains the
    `events[].items` object schema. The measured defect (audit §5.4, `X11`):
    `{"type":"array"}` with no `items` meant a client could only learn the
    element shape - starting with the required `type` and its `enum` - by
    failing once (`-32602 "Missing required parameter: events[0].type"`);
  * `run_test_scenario` (`running_game_run_test_scenario`) gains
    `steps[].pressed` and `steps[].strength`, both of which the implementation
    has read since TASK-019 (`running_game_test_execution.cpp:141-148`) while the
    declaration named only nine of the eleven members (audit §5.5);
  * `play_scene` (`editor_play_scene`) gains `headless` (boolean, default false)
    and `extra_args` (array of strings, default `[]`). The measured defect
    (audit §3.3): the child's command line was `--path / --remote-debug /
    --editor-pid / --scene` plus this tool's own `--mcp-port=<port>`, so
    `--headless` - a routine CI need, and *not* inherited from the editor (it is
    absent from `Main::get_forwardable_cli_arguments(CLI_SCOPE_PROJECT)`) - could
    not be requested at all. `--mcp-port` inside `extra_args` is refused rather
    than appended, because `MCPPort::parse` takes the last occurrence and the
    answer's `endpoint` would then name a port the child is not listening on.

No `description` field moves in this version: every new meaning is carried by
the property it belongs to, which is also what a client reads in `tools/list`.

v1.8 (TASK-052, `DESIGN-DETAIL.md` section 26 / GDR-28 - "契约扩张：新增工具"):
the generator stops being a pure *rename + override* of the 174 old entries. The
decision maker may now author **new** tool entries, and they live in a third,
separate table:

  * `ADDED_TOOLS` is a list, not a dict keyed by `old_name`: a new entry has no
    old name to be keyed by, which is exactly what makes it a *new* entry rather
    than an override of a migrated one. It is therefore separate from both
    `DESCRIPTION_OVERRIDES` and `SCHEMA_OVERRIDES` (GDR-28 point 1), and the
    append happens **after** the rename + override pass, so an added entry can
    never be mistaken for a carried-over one;
  * the append is **deterministic**: the list's order is the output's order, the
    entry carries only `name` / `description` / `inputSchema` (the three fields
    of the contract), and the two name lists (`ported` vs `added`) are proved
    disjoint - a new name that collided with a ported or a dropped name is a
    hard failure;
  * the naming lint of GDR-16 is applied to an added name exactly as it is to a
    ported one (L1 pattern, L4 no `update_`, L2 verb inside the closed set,
    L3 channel and verb derived from the name itself, because there is no
    `tool-rename-map.json` row for a new tool);
  * `_meta` gains **`added_tools`** (the ordered list of names) and
    **`added_count`** (its length), and `_meta.count` stays `len(result.tools)`,
    so the contract's own `count` is `171 + N` from now on;
  * the transform is still idempotent: two runs of one build write byte-identical
    files (the same property the rename pass has always had).

Note what did **not** change: `result.tools` of the 171 ported entries is still a
byte-exact carry-over unless an override records the deviation, the frozen old
contract sha is still enforced, and `order_normative` is still false. The
machine checks that consume the two numbers are `check_tool_groups.py
--check-completeness` (`171 + N = 66 + 105 + N`, each name exactly once) and its
`--added` mode (which validates `docs/tool-groups-added.json`).

v1.16 (TASK-054, the C# honesty defect the audit's D-053-3 registered and
`DESIGN-DETAIL.md` section 26 / GDR-28 point 13 parked): **no entry is added and
no `inputSchema` moves** - the count stays 175 - but two `description` fields
stop over-promising about C#. `CSharpScript::reload()` returns `OK`
unconditionally (`modules/mono/csharp_script.cpp:2588-2621`) and never compiles
the source it was given, so in a Mono build a `.cs` file with a syntax error used
to be answered `{"valid": true, "message": "Script compiles successfully"}`
(measured: TASK-053 `c03`, and again by this task on the pre-change binary). The
single-file tool now refuses that file with `-32000` and the plural tool
classifies it `unverifiable` (no `valid` value, plus the engine basis in
`reason`), so both tools say the same thing:

  * `validate_script` (`project_validate_script`) gets one more **append-only**
    sentence - the v1.12 override already exists, so its original wording is
    untouched and this is a change to that entry's `value` and `reason`;
  * `project_validate_scripts` is an **added** entry (`ADDED_TOOLS`), which has no
    `old_name` and therefore no `DESCRIPTION_OVERRIDES` key: its description
    lives in the table the decision maker authored, and it is extended there. The
    four categories it publishes become five (`ok` / `invalid` /
    `language_unavailable` / `unverifiable`), which is why the sentence has to be
    in the field a client reads.

v1.17 (TASK-055, decision D112 - the engine patch that gives C# a real verdict):
**no entry is added and no `inputSchema` moves** - the count stays 175 - but the
two C# sentences TASK-054 added describe behaviour that no longer holds, so both
`description` fields are rewritten to what the tools now answer:

  * the engine patch is one public read-only accessor,
    `CSharpScript::is_source_newer_than_assembly()` (`modules/mono/csharp_script.h`,
    the comparison `CSharpScript::_update_exports()` already made for the editor's
    placeholders, exposed); together with the already public
    `Script::is_script_valid()` (`core/object/script_language.h:180`) it separates
    "the loaded assembly holds a build of this source" from "nothing compiled
    this source";
  * the project-level half of the verdict is recorded by this module's own build
    tool: `project_build_csharp` parses the compiler's diagnostics out of the
    output it already captures and writes them, with the modification time each
    file had at that build, to `user://mcp_csharp_build_state.json`. A diagnostic
    therefore expires the moment its file is edited, which is what keeps "it
    failed to compile" apart from "it was changed after that build";
  * `validate_script` (`project_validate_script`) gets one more **append-only**
    sentence - the v1.12 entry already exists, so this changes that entry's
    `value` and `reason`, and the TASK-054 sentence it used to end with (a `.cs`
    file gets no verdict here) is replaced because it is no longer true;
  * `project_validate_scripts` is an **added** entry, so its description is
    rewritten in `ADDED_TOOLS`: `unverifiable` stays for the residual "the engine
    could not load the file at all", `not_compiled` is new, and a sixth counter
    (`not_compiled_count`) joins the response.

Nothing else moves: 173 of the 175 entries are byte-identical, both `inputSchema`
objects are untouched, and the two validate tools publish the same verdict for
the same file.

v1.18 (TASK-059 D-4 - the sentence TASK-057 patch 2 falsified): **no entry is
added and no `inputSchema` moves** - the count stays 175 - but five `description`
fields stop claiming a missing capability. TASK-043 had appended, verbatim to all
five, a sentence containing `(the engine has no partial-publish API)` because at
the time that was true and the whole-file rewrite really did destroy every
hand-written comment. TASK-057 patch 2 added exactly that API -
`ProjectSettings::save_custom_section()` and `update_settings_section_text()`
(`core/config/project_settings.h:209-241`, `project_settings.cpp:1537-1779`) - and
TASK-057 deliberately did not switch any tool, reporting D-4 instead. This batch
switches the behaviour and the text **together**:

  * three of the five are genuinely single-section writes and now say so:
    `set_project_setting`, `set_input_action` (`editor_add_input_action`) and
    `add_autoload` (`project_add_autoload`). Their new text states the section
    rule, that comments and every other byte outside the target section survive,
    the four cases in which the whole file is still rewritten, and that this is a
    behaviour improvement (comments are no longer lost);
  * two are not, and their new text says why rather than claiming the capability:
    `remove_autoload` (`project_remove_autoload`) - the section writer replaces
    the values it is given and never deletes a key
    (`core/config/project_settings.h:226-227`), so a removal cannot be expressed
    as a section publish; and `reload_plugin` (`editor_reload_plugin`) - the save
    is the editor's own `ProjectSettingsEditor` settings-changed timer, not this
    module, so there is no section to name.

All five are `mode: "replace"`: the sentence being removed is factually wrong, and
an append-only discriminator would leave the false statement in the field a caller
reads - which is what `mode: "replace"` exists for (TASK-007). Every new value
still begins with the Chinese head of the old contract description, verbatim, and
every `reason` quotes both that head (the append-only guard's obligation) and the
false sentence it removes. The shared text of the three switched tools is one
module-level literal, so the three cannot drift apart. The four whole-file
fall-backs the new text names are the ones `tools/tool_helpers.h` documents and
`MCPTools::publish_project_setting_to()` implements case for case.

v1.19 (TASK-063 - the second round's four product defects): the count moves
**175 -> 176** (one new added tool) and five `description` fields move, three of
them because the text a caller reads was missing a rule that cost the round-2
developer 39 failed calls (TASK-060 D-5/O-2/O-3):

  * **one added entry**: `editor_set_node_property_updates` (the path-scoped
    batch property write; TASK-060 M-1/D-6 - only a *type*-scoped batch existed,
    so twenty geometry values cost twenty single writes). Its description,
    `inputSchema` and `reason` follow the TASK-052/TASK-053 shape;
  * **`update_property`** (`editor_set_node_property`) and
    **`get_node_properties`** (`editor_get_node_properties`) each get one
    **append-only** sentence built from one shared module-level literal
    (`NODE_PATH_RULE_SENTENCE`), so the two cannot drift apart. The parameter
    *names* do not move: `path` (singular) and `node_paths` (plural) stay, and
    what changes is that the text now states the path basis ("relative to the
    edited scene root", `/root/...` refused) and which of the two spellings takes
    one node and which takes many;
  * **`editor_set_node_script_batch`** (an added entry, so its description lives
    in `ADDED_TOOLS`) gets the plural half of the same sentence appended.

All three sentences are append-only (`mode` stays the default): the original
Chinese head of each ported description is preserved verbatim, which the
append-only guard checks character for character.

v1.20 (TASK-068 - the registered items of REPORT-067 section 7): the count and
every `inputSchema` stay exactly where v1.19 left them (**176 entries**), and
exactly two `description` fields move, both append-only, both because the text a
caller reads was silent about something the tool really does:

  * **`list_scripts`** (`project_list_scripts`) now states the walk's one
    observable consequence: it recurses from `res://` and skips only `.` and
    `..`, so the engine's own project cache comes back with the rest
    (`res://.godot/mono/temp/obj/**` on a Mono project) and filtering is the
    caller's job. TASK-067 made the script set a property of the build and
    deliberately did **not** narrow the walk (narrowing would break the pinned
    `.hiddendir/secret.gd` assertion; listing a generated file is honest), so
    the sentence is the declaration the decision owed (D125 (b), TASK-067
    deviation 5);
  * **`run_test_scenario`** (`running_game_run_test_scenario`) now says which of
    the two wait-related spellings is the input and which is the echo. The facts
    were measured before the sentence was written (REPORT-068 section 3): the
    contract declares `seconds` as the only duration member
    (`inputSchema.properties.steps.items.properties.seconds`), the implementation
    reads only `seconds` (`tools/running_game_test_execution.cpp:316-317`), and
    the result entry echoes `waited_seconds` (`:440`, `:459`). They are two
    different members in two different objects, so nothing is renamed, no alias
    is added (an undeclared input would fail gate 1's verbatim schema
    comparison), and the R4 section 8.2 registration is closed by the text alone.

Neither sentence changes a byte of behaviour, and no `required` member moves, so
no `SCHEMA_OVERRIDES` record is touched by this version.

v1.21 (TASK-075 section 2 - the round-5 findings' M1/D3): the count moves
**176 -> 177** (one new added tool) and nothing else moves:

  * **one added entry**: `project_read_text_file`, the symmetric half of the
    module's own added `project_write_text_file`. The round-5 test's judgement
    table (PLATFORMER-FINDINGS section 0.6 (8)) asked for "write it, read it back
    and verify the sha256 - with a tool", and the loop could only be closed with an
    OS `Get-FileHash` call, because the contract had readers for scripts, scenes,
    resources and shaders but none for a plain project text file. Its description
    is the task's own sentence, verbatim.

v1.22 (TASK-076 section A.1 - the two boundaries TASK-075's D4/D5 established):
the count and every `inputSchema` stay exactly where v1.21 left them (**177
entries**), and three descriptions move - the two boundaries that were measured
in TASK-075 but only ever written down in a report the caller never reads:

  * **`editor_get_scene_tree`** (old `get_scene_tree`) is the *authority* for
    editor-side addressability, and its answer can be narrower than the project
    on disk: an instantiated sub-scene's internal nodes may not appear in the
    tree, because the editor caches the `PackedScene` as an instance snapshot, so
    both existing and newly created instances keep the old cache until a new
    editor session (REPORT-075 section 5, `scripts/mcp075_d4_staleness.ps1`,
    9/9). The boundary sentence says what to do instead (edit the sub-scene
    first; or add the node under the instance in the outer scene) and, because
    round 5 misread the same measurement as "the tools disagree", it states the
    measured fact: the property-write and signal tools resolve through the same
    `MCPTools::find_node` and agree on the same path - the difference is the
    editor cache, not the tool.

  * **`editor_set_tilemap_cell` / `editor_set_tilemap_cells_in_rect`** (old
    `tilemap_set_cell` / `tilemap_fill_rect`): writing a cell requires a
    `TileSetAtlasSource` to exist in the layer's `TileSet`.
    `project_create_resource{type:TileSet}` yields an *empty* TileSet
    (`source_count:0`) and no tool of this module can add an atlas source, so
    the two tools are unreachable in any call sequence this tool set can build.
    TASK-075 classified that as a capability gap and recorded it in a report
    only; the sentence declares the gap in the text the caller reads, and names
    the two ways out (build the TileSet by hand in the editor, or ship a `.tres`
    that already has a source) instead of leaving the caller to follow a
    `data.suggestion` that no tool can satisfy.

The sentences are two module-level literals (`SCENE_TREE_ADDRESSABILITY_SENTENCE`
and `TILEMAP_ATLAS_GAP_SENTENCE`) so the two tilemap entries cannot drift apart,
exactly like `NODE_PATH_RULE_SENTENCE` (v1.19) and `_T059_SECTION_WRITE` (v1.18).

v1.23 (TASK-112 D-T111-3): the count and every `description` stay exactly where
v1.22 left them (**177 entries**, `overrides` 26 -> 27), and **one `inputSchema`
moves** - the first schema override since the animation-tree family:

  * **`editor_add_raycast`** (old `add_raycast`): `dimension` is declared as the
    closed set it always was (`enum: ["2d", "3d"]`, `default`/`type` unchanged).
    The old schema said only `{"default":"2d","type":"string"}` and the
    implementation was `dimension == "2d" ? RayCast2D : RayCast3D`, so every
    other spelling - a typo, `"2D"`, `"4d"` - silently built a `RayCast3D` and
    answered `added: true` (measured, `c4-033`:
    `{"dimension":"4d"}` -> `{"added":true,"name":"Ray4d","type":"RayCast3D"}`).
    TASK-111 registered that as D-T111-3; TASK-112 fixes the runtime with a
    closed-set refusal *before* the editor guard and makes the set visible before
    the call. The same commit's doctest pins the refusal; the enum is the
    contract half of the same fact. No `required` member moves (it is `[]` before
    and after).
"""

import argparse
import hashlib
import json
import os
import re
import sys

GENERATOR_VERSION = "1.23.0"
GENERATED_BY = "modules/mcp_server/scripts/gen_renamed_contract.py"

# Explicit override hooks. SCHEMA_OVERRIDES was empty for B0/B1: the rename is
# name-only plus, from v1.2 on, the seven description disambiguations below.
# Any entry has to look like {"reason": "...", "value": <object>} and is recorded
# in `_meta.overrides` so that the deviation stays auditable.
#
# v1.5 (TASK-014 D-3): SCHEMA_OVERRIDES takes its first entry. A schema override
# is a whole-object *replacement* (there is nothing to append to), so it must
# carry `"mode": "replace"`, and its reason must quote the `required` member it
# removes verbatim - see the guard in `main`. No other character of the schema
# moves.
#
# v1.2: R-1/R-2/R-3 disambiguation (TASK-002 section 2.1.1). Each discriminator
# below is a *fact read out of the migration source*, never an invention; the
# line references are the ones already audited for tool-rename-map.json v1.1.

# v1.22 (TASK-076 section A.1): the two append-only boundary sentences, as
# module-level literals so the two tilemap entries cannot drift apart - the same
# device as `NODE_PATH_RULE_SENTENCE` (v1.19) and `_T059_SECTION_WRITE` (v1.18).
#
# Reconstructed byte-exactly (TASK-082): the scene-tree sentence is the one
# REPORT-076 section 1.2 records together with the "42 -> 898" byte count, and
# the tilemap sentence is the one carried verbatim by the C++ literals in
# `tools/editor_tilemap_write.cpp:532/:538`, which the same table records as
# "27 -> 717" and "30 -> 720".  Both byte counts reproduce exactly, so the text
# below is the artefact's text and not a paraphrase.
SCENE_TREE_ADDRESSABILITY_SENTENCE = (
    '本工具是“此刻编辑器侧可寻址什么”的权威：实例子场景内部的节点可能不出现在这棵树里，因为编辑器把 PackedScene 缓存成实例快照 —— 子场景改了以后，同一会话里既有的实例与新建的实例都仍带旧缓存（游戏进程从磁盘加载，因此能看到新节点）；要操作子场景新增的内部节点，就把 editor_add_node 的 parent_path 指向该实例、把它作为外层场景里实例下的子节点写（实测可寻址并可连信号），或者开一个新的编辑器会话让缓存重建；子场景本身的编辑永远应当先做，再做外层场景的实例化。这不是“各工具看不看得见不一致”：属性写工具与信号工具经同一个 MCPTools::find_node 解析路径，对同一路径给出同一结论，差别只在编辑器缓存。'
)

TILEMAP_ATLAS_GAP_SENTENCE = (
    '写格子要求目标 TileMapLayer 的 TileSet 里已经存在一个 TileSetAtlasSource：project_create_resource 用 type=TileSet 只会造出一个空 TileSet（source_count=0，既没有 source 也没有 texture），而当前工具集没有任何“给 TileSet 添加 atlas source / texture / tile”的入口，所以在可预见的调用序列里本工具无法成功 —— 这是一处如实声明的能力缺口，不是本工具的缺陷；调用方要么在编辑器里手工建好带 atlas source 的 TileSet，要么在项目里自带一个含 source 的 .tres。TileSet 里没有该 source 时本工具以 -32602 拒绝，并在 data.suggestion 里点名它接受的参数。'
)

# The measured facts both tilemap `reason` fields cite (REPORT-076 section 1.3
# (ii), measured in REPORT-075 section 6 D5).
_T076_TILEMAP_GAP_REASON = (
    "依据 REPORT-075 §6 D5 / REPORT-076 §1.3(ii)：project_create_resource"
    "{path:res://tiles/empty_tileset.tres,type:TileSet} 返回 "
    "{\"properties_set\":[],…,\"type\":\"TileSet\"}；赋值前 has_tile_set:false, source_count:0, sources:[]；"
    "editor_add_resource_to_node_property{tile_set} 与 editor_set_node_property{tile_set} 都成功；"
    "赋值后 has_tile_set:true, source_count:0（E8 的“赋值没落地”被证伪）；"
    "editor_set_tilemap_cell{source_id:0,…} 返回 -32602 "
    "\"The TileSet of this TileMapLayer has no source 0; it has: no source at all (add a TileSetAtlasSource first)\" "
    "并带 data.suggestion。缺口 = 无任何工具能创建/填充 TileSetAtlasSource，故按能力缺口记账、不改行为。"
    "范围裁决：缺口句只挂在两个写工具上——editor_get_tilemap_info/_used_cells/_cell 与 "
    "editor_remove_all_tilemap_cells 不要求 source 存在、也不会因此失败，挂上去只会噪音化真正的调用方。"
)

# [REBUILT-2C low-confidence: verify] TASK-088 item 4: the canonical `map_path`
# written into `_meta`. It is the recorded build root, recovered verbatim from
# `staging/__payload-index/events-termdump.jsonl` (lines 228, 268, 498, 569, 812,
# 1073, 1120, 1127, 1586 all carry it next to `map_sha256` =
# `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`, which is
# this tree's rename-map sha as well), so the value is replayed, not invented.
RECORDED_MAP_PATH = "F:\\RustProjects\\godot-mcp-pro\\code\\godot\\modules\\mcp_server\\docs\\tool-rename-map.json"

DESCRIPTION_OVERRIDES = {
    # R-1: editor_analyze_signal_flow vs editor_list_signal_connections.
    # analysis.rs:387-410 / analysis.rs:96-160 (nested nodes[], flags & 1, exact
    # node_path via had_node, no signal_name filter) against
    # batch.rs:207-263 (flat connections[], all connections, substring matches).
    "analyze_signal_flow": {
        "reason": (
            "R-1 消歧 + 事实纠正（TASK-007 §1）：原文按迁移源 analysis.rs:387 写成“只统计持久连接（flags & 1）”，"
            "但 Godot 4 里 CONNECT_DEFERRED = 1、CONNECT_PERSIST = 2（core/object/object.h:356-360），"
            "照字面实现会让普通 .tscn 场景恒返回 nodes: []。实现（TASK-006 已交付）按意图用了 CONNECT_PERSIST，"
            "契约描述是唯一还在说 flags & 1 的地方，故用 mode=replace 纠正。"
            "被替换的原文（逐字保留以便审计）："
            "分析当前场景的信号连接流 判别点：按节点嵌套返回 nodes[]（每节点含 signals_emitted/signals_connected_to），"
            "只统计持久连接（flags & 1）、node_path 精确匹配、无 signal_name 过滤；"
            "要扁平 connections[] 或子串匹配请用 editor_list_signal_connections。"
        ),
        "mode": "replace",
        "value": "分析当前场景的信号连接流 判别点：按节点嵌套返回 nodes[]（每节点含 signals_emitted/signals_connected_to），只收集持久连接（CONNECT_PERSIST，值为 2；注意 Godot 4 中 flags & 1 是 CONNECT_DEFERRED，不是持久连接）、node_path 精确匹配、无 signal_name 过滤；要扁平 connections[] 或子串匹配请用 editor_list_signal_connections。",
    },
    "find_signal_connections": {
        "reason": (
            "R-1 消歧：与 editor_analyze_signal_flow 形状/过滤/匹配方式不同（batch.rs:207 扁平 "
            "connections[]+count、不过滤非持久连接、node_path 与 signal_name 均子串匹配）。"
        ),
        "value": "递归查找场景中所有信号连接 判别点：扁平返回 connections[]（每项 {source,signal,target,method}）与 count，收全部连接（不过滤非持久连接）、node_path 与 signal_name 均按子串匹配；要按节点嵌套的流向分析请用 editor_analyze_signal_flow。",
    },
    # R-2: project_search_file_names vs project_search_file_contents.
    # project.rs:159-191 (file name substring, case insensitive, cap 200) against
    # project.rs:194-246 (per line, case insensitive, cap 50).
    "search_files": {
        "reason": (
            "R-2 消歧：search_files 只按文件名子串匹配（project.rs:175，大小写不敏感、上限 200，"
            "不读内容不返回行号），与 search_in_files 的逐行内容匹配完全不同。"
        ),
        "value": "搜索文件 判别点：只匹配文件名子串（大小写不敏感、上限 200），不读文件内容、不返回行号；要搜索文件内容请用 project_search_file_contents。",
    },
    "search_in_files": {
        "reason": (
            "R-2 消歧：search_in_files 逐行返回 {file,line,text}（project.rs:221-229，大小写不敏感、"
            "上限 50、跳过 addons 与 .godot），与 find_node_references 的按文件聚合不同。"
        ),
        "value": "在文件内容中搜索文本 判别点：逐行返回 {file,line,text}（大小写不敏感、上限 50，跳过 addons 与 .godot 目录）；要按文件聚合的 {file,lines[]}（大小写敏感、上限 100）请用 project_find_files_referencing_symbol。",
    },
    # R-2/R-3: project_find_files_referencing_symbol (batch.rs:419-512) is the
    # de-merged twin of project_search_file_contents (GDR-17).
    "find_node_references": {
        "reason": (
            "R-2 消歧：find_node_references 按文件聚合 {file,lines[]}（batch.rs:474-489，大小写敏感、"
            "上限 100、每文件最多 5 行），与 search_in_files 的逐行形状互为对照（GDR-17 取消合并）。"
        ),
        "value": "在项目文件中搜索指定模式的引用 判别点：按文件聚合返回 {file,lines[]}（每文件最多 5 行、大小写敏感、上限 100，跳过隐藏文件与 addons，只扫 .tscn/.gd/.tres/.gdshader）；要逐行 {file,line,text}（大小写不敏感、上限 50）请用 project_search_file_contents。",
    },
    # R-3: the two converts are a pure direction pair (project.rs:295-322).
    "uid_to_project_path": {
        "reason": (
            "R-3 消歧：uid_to_project_path 入参是文本 UID、出参 {uid,path}，UID 文本非法即报参数错误"
            "（project.rs:295-305），与反向转换项目路径->UID 是纯方向对。"
        ),
        "value": "将 UID 转换为项目路径 判别点：入参为字符串文本 UID（如 uid://...），返回 {uid,path}，UID 文本格式非法时报参数错误；反向转换请用 project_convert_path_to_uid。",
    },
    "project_path_to_uid": {
        "reason": (
            "R-3 消歧：project_path_to_uid 入参是项目路径、出参 {path,uid}，路径未注册时 uid 为空串且"
            "不报错（project.rs:308-322），与反向转换 UID->路径是纯方向对。"
        ),
        "value": "将项目路径转换为 UID 判别点：入参为项目路径（如 res://...），返回 {path,uid}，路径未注册时 uid 为空串且不报错；反向转换请用 project_convert_uid_to_path。",
    },
    # D-3 (TASK-014 section 1.3): the fallback D59 ruling 1 introduced, mirrored
    # into the text a client actually reads. The schema override below stops
    # requiring `events`, so this sentence has to say what omitting it does -
    # otherwise the contract would only have traded one silent rule for a missing
    # one.
    "replay_recording": {
        "reason": (
            "D-3 契约与行为一致（TASK-014 §1.3 / D59 裁决 1）：实现允许缺省 events，并回放本游戏进程内"
            "最近一次 running_game_stop_input_recording 的录制；契约原文的 required=[events] 与描述都没有"
            "这条回退，按契约传 events 的消费者反而享受不到它。"
        ),
        "value": "回放之前录制的输入事件序列 缺省 `events` 时，回放本游戏进程内最近一次 running_game_stop_input_recording 的录制；若本进程没有可用录制则返回 -32602。",
    },
    # TASK-024 E-10: the game child's MCP port is now injected by the tool, and
    # that is only discoverable if the contract says so. Append-only (the
    # original wording "运行场景" stays, first, verbatim).
    "play_scene": {
        "reason": (
            "TASK-024 E-10 顺手性（GDR-23）：原描述只说“运行场景”，没有告诉调用方游戏子进程的 MCP 端口"
            "从哪来，于是“跑起来观察”只能靠改被测工程的 godot_mcp/port 设置（REPORT-AUDIT-M4c D-13）。"
            "实现改为经 EditorRunBar 的 p_play_args 注入 --mcp-port，并在响应里回 mcp_port/endpoint/pid，"
            "故追加一句判别点；原文逐字保留在句首。"
            "[REBUILT-2C low-confidence: verify] TASK-088 第 4 项：本记录的 value 已改为服务端实际发布的文本"
            "（实测 work/task088/live/editor-tools-list.json），因为录制里这条记录是同一改写的更早一版；"
            "TASK-024 的原判据保留，文本细节以实测为准。"
        ),
        "value": "运行场景 起游戏时经 EditorRunBar::play_*(..., p_play_args) 注入 --mcp-port=<端口>，使编辑器起的游戏子进程立刻可被 MCP 观察，无需改被测工程的 godot_mcp/port 设置：端口可用可选参数 mcp_port 指定（越界、已被占用、以及编辑器自己正在用的端口都会被拒绝，不会把游戏指向一个连不上的端口），缺省时自动挑一个空闲端口，且不与编辑器自身端口相同；响应在确认子进程已创建后给出 mcp_port、mcp_port_source（argument/auto_free_port）、可直连的 endpoint 与游戏 pid，子进程没起来则不报成功。",
    },
    # v1.22 (TASK-076 section A.1): the two boundaries TASK-075's D4/D5 measured
    # and REPORT-076 section 1 implemented.  All three records are append-only
    # (`mode` stays the default), so the original wording stays first and
    # verbatim; the `startswith(<original> + " ")` guard above enforces that.
    "get_scene_tree": {
        "reason": (
            "TASK-076 §A.1 / REPORT-076 §1.3(i)，依据 REPORT-075 §5 D4 的最小复现"
            "（scripts/mcp075_d4_staleness.ps1，9/9 PASS）：player.tscn 无子节点、main.tscn 实例化它后 "
            "Player 子节点数 = 0、Player/Anim 报 -32001；打开 player.tscn 加入 AnimationPlayer \"Anim\" 保存后"
            "磁盘确实含 Anim，回到 main.tscn 仍为 0/-32001，新建同文件实例同样为 0，"
            "而游戏进程（从磁盘加载）/World/Player/{Body,Art,Anim} 齐全；机制是编辑器把 PackedScene 缓存成实例快照。"
            "会话内的绕法 editor_add_node{parent_path:'Player'} 之后 Player/Anim 可寻址且 editor_connect_signal 成功"
            "（connected:true, persisted:true）。「不是各工具口径不一」的出处：属性写与信号工具都经同一个 "
            "MCPTools::find_node（tools/tool_helpers.cpp:1417），同一路径结论一致；round-5 的"
            "「属性写工具到得了 Anim」来自另一上下文（先 editor_open_scene res://scenes/player.tscn，"
            "再写 path:'Anim'，那是被编辑场景根的直接子节点，不是外层场景里实例下的路径）。"
            "裁决是不改 find_node（穿越缓存会改变所有编辑器工具语义、并让读取产生写副作用），只声明边界。"
        ),
        "value": "获取当前编辑场景的完整场景树 " + SCENE_TREE_ADDRESSABILITY_SENTENCE,
    },
    # TASK-076 section 1.2(ii): one shared sentence, two entries - they cannot
    # drift apart because both read the literal below.
    "tilemap_set_cell": {
        "reason": _T076_TILEMAP_GAP_REASON,
        "value": "设置瓦片地图单元格 " + TILEMAP_ATLAS_GAP_SENTENCE,
    },
    "tilemap_fill_rect": {
        "reason": _T076_TILEMAP_GAP_REASON,
        "value": "填充瓦片地图矩形区域 " + TILEMAP_ATLAS_GAP_SENTENCE,
    },
    # v1.20 (TASK-068, description-only). Both records are append-only, so the
    # original wording stays first and verbatim and the
    # `startswith(<original> + " ")` guard above enforces it. The two `value`
    # strings below are the ones `docs/reports/evidence/task076/
    # contract_fingerprint.txt` reads back out of the generated contract (the
    # same file that pins sha256 a5c59853... / 36 overrides / generator 1.22.0)
    # and the ones REPORT-068 section 2.3 quotes.
    "list_scripts": {
        "reason": (
            "TASK-068 §2.3(i) / REPORT-068 §2.3：TASK-067 §1.4 承认的 walk 边界（从 res:// 起递归、"
            "只跳过 . 与 ..）此前只写在报告里，客户端真正读到的描述没说。追加一句把它变成可读事实，"
            "行为一字未改（walk 仍然只跳过 . 与 ..）。"
        ),
        "value": "列出所有脚本文件 会包含 .godot 下的生成脚本：本工具的 walk 从 res:// 起递归，只跳过 . 与 ..，因此引擎自己生成的文件也在答案里（真实 mono 工程会出现 res://.godot/mono/temp/obj/** 下的 .cs，例如 res://.godot/mono/temp/obj/Debug/*.AssemblyInfo.cs），调用方若要只看手写脚本请自行过滤这些路径。",
    },
    "run_test_scenario": {
        "reason": (
            "TASK-068 §2.3(ii) / REPORT-068 §2.3：R4 §8.2 登记的 waited_seconds 陷阱是文档含混，"
            "不是同名异义——入参是 steps[].seconds（契约 schema 里唯一的等待时长成员），结果的 wait 条目"
            "回显字段是 waited_seconds，回显的是**请求侧**的值、并随 wait 形式而变"
            "（tools/running_game_test_execution.cpp:440 镜像 seconds，:459 镜像 timeout）。只追加一句描述，"
            "不加别名、不动 schema、不改行为；原文逐字保留在句首。"
        ),
        "value": "运行测试场景并执行一系列测试步骤 wait 步骤的入参名是 seconds（steps[i].seconds，契约 schema 里唯一的等待时长成员），结果里每个 wait 条目的回显字段叫 waited_seconds（按时间等待的步骤回显的就是 seconds；按 node_path 等待的步骤回显 timeout，见 tools/running_game_test_execution.cpp:440 与:459）；两者在**不同的对象**里，waited_seconds 不是入参（把它写进请求的 step 不生效，seconds 才是入参），入参名与结果字段名都未改动、既有调用不受影响。",
    },
    # [REBUILT-2C low-confidence: verify] TASK-088 item 4: registered from the measured published text.
    "validate_script": {
        "reason": (
            "[REBUILT-2C low-confidence: verify] TASK-088 第 4 项（逻辑重建，依据=实测发布文本）：契约此前只写“验证脚本语法”，而服务端实际发布的描述在原文之后追加了 TASK-055 的 `.cs` 裁决说明（`valid` 只在本进程已加载的程序集确实是该源文件的构建时才为 true；`valid: false` 必须伴随 `project_build_csharp` 记录的编译诊断；两者都不是的文件以 -32000 的 'not compiled' 拒绝）。追加句取自 154 条 `tools/list` 实测响应（work/task088/live/editor-tools-list.json），原文逐字保留在句首。"
            "TASK-088 依据：work/task088/live/editor-tools-list.json（实测 154 条 tools/list）与 work/task088/cmp_editor.txt（逐工具差异）；被替换的原文逐字为：验证脚本语法"
        ),
        "value": "验证脚本语法 判别点：valid 只在真的用该文件自身的脚本语言编译过时才是结论（true=编译通过；false=编译失败，error_text 给 ERR_* 标识符）；本构建不含该语言的脚本后端时（例如 module_mono_enabled=no 的构建里的 .cs）不借用别的语言解析、也不给出 valid，而是以 -32000 拒绝并在 data.suggestion 里说明该用哪个构建或文件；进程根本没有初始化任何脚本语言时（--test 进程）只做括号平衡的结构检查，message 会明说没有编译。 A '.cs' file now gets a real verdict (TASK-055): `valid: true` means the loaded .NET assembly contains a build of this exact source (Script::is_script_valid() found a class for the script's path and CSharpScript::is_source_newer_than_assembly() says the file has not changed since that assembly was built); `valid: false` with `error_text` carrying the compiler's own diagnostic text means a project-level build of its .csproj that project_build_csharp ran and recorded rejected the file as it is now; and a file nothing has compiled - edited after the last build, or with no class in the loaded assembly - is refused with -32000 saying 'not compiled', never answered `valid: false`, because the engine itself has no C# compiler (CSharpScript::reload() returns OK unconditionally).",
    },
    # [REBUILT-2C low-confidence: verify] TASK-088 item 4: registered from the measured published text.
    "reload_plugin": {
        "reason": (
            "[REBUILT-2C low-confidence: verify] TASK-088 第 4 项（逻辑重建，依据=实测发布文本 + 已录制常量）：服务端在这 5 个工具的描述里追加了 TASK-043 的整文件写入诚实声明（`project.godot` 由引擎的整文件写入器重写、手写注释会丢失、同一调用重复执行不改变字节）。该句逐字取自录制证据 `scripts/mcp043_description_evidence.ps1:50` 的 `$Sentence`，而这 5 个工具确实在 C++ 里逐字带有它（`tools/editor_input_simulation.cpp:1244`、`tools/editor_write_scene_editor.cpp:1026`、`tools/project_autoload_write.cpp:256/263`、`tools/project_setting_write.cpp:293`）。原文逐字保留在句首。"
            "TASK-088 依据：work/task088/live/editor-tools-list.json（实测 154 条 tools/list）与 work/task088/cmp_editor.txt（逐工具差异）；被替换的原文逐字为：重新加载 MCP 插件"
        ),
        "value": "重新加载 MCP 插件 When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them.",
    },
    # [REBUILT-2C low-confidence: verify] TASK-088 item 4: registered from the measured published text.
    "set_input_action": {
        "reason": (
            "[REBUILT-2C low-confidence: verify] TASK-088 第 4 项（逻辑重建，依据=实测发布文本 + 已录制常量）：服务端在这 5 个工具的描述里追加了 TASK-043 的整文件写入诚实声明（`project.godot` 由引擎的整文件写入器重写、手写注释会丢失、同一调用重复执行不改变字节）。该句逐字取自录制证据 `scripts/mcp043_description_evidence.ps1:50` 的 `$Sentence`，而这 5 个工具确实在 C++ 里逐字带有它（`tools/editor_input_simulation.cpp:1244`、`tools/editor_write_scene_editor.cpp:1026`、`tools/project_autoload_write.cpp:256/263`、`tools/project_setting_write.cpp:293`）。原文逐字保留在句首。"
            "TASK-088 依据：work/task088/live/editor-tools-list.json（实测 154 条 tools/list）与 work/task088/cmp_editor.txt（逐工具差异）；被替换的原文逐字为：创建 Input Action"
        ),
        "value": "创建 Input Action When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them.",
    },
    # [REBUILT-2C low-confidence: verify] TASK-088 item 4: registered from the measured published text.
    "add_autoload": {
        "reason": (
            "[REBUILT-2C low-confidence: verify] TASK-088 第 4 项（逻辑重建，依据=实测发布文本 + 已录制常量）：服务端在这 5 个工具的描述里追加了 TASK-043 的整文件写入诚实声明（`project.godot` 由引擎的整文件写入器重写、手写注释会丢失、同一调用重复执行不改变字节）。该句逐字取自录制证据 `scripts/mcp043_description_evidence.ps1:50` 的 `$Sentence`，而这 5 个工具确实在 C++ 里逐字带有它（`tools/editor_input_simulation.cpp:1244`、`tools/editor_write_scene_editor.cpp:1026`、`tools/project_autoload_write.cpp:256/263`、`tools/project_setting_write.cpp:293`）。原文逐字保留在句首。"
            "TASK-088 依据：work/task088/live/editor-tools-list.json（实测 154 条 tools/list）与 work/task088/cmp_editor.txt（逐工具差异）；被替换的原文逐字为：注册自动加载"
        ),
        "value": "注册自动加载 When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them.",
    },
    # [REBUILT-2C low-confidence: verify] TASK-088 item 4: registered from the measured published text.
    "remove_autoload": {
        "reason": (
            "[REBUILT-2C low-confidence: verify] TASK-088 第 4 项（逻辑重建，依据=实测发布文本 + 已录制常量）：服务端在这 5 个工具的描述里追加了 TASK-043 的整文件写入诚实声明（`project.godot` 由引擎的整文件写入器重写、手写注释会丢失、同一调用重复执行不改变字节）。该句逐字取自录制证据 `scripts/mcp043_description_evidence.ps1:50` 的 `$Sentence`，而这 5 个工具确实在 C++ 里逐字带有它（`tools/editor_input_simulation.cpp:1244`、`tools/editor_write_scene_editor.cpp:1026`、`tools/project_autoload_write.cpp:256/263`、`tools/project_setting_write.cpp:293`）。原文逐字保留在句首。"
            "TASK-088 依据：work/task088/live/editor-tools-list.json（实测 154 条 tools/list）与 work/task088/cmp_editor.txt（逐工具差异）；被替换的原文逐字为：移除自动加载"
        ),
        "value": "移除自动加载 When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them.",
    },
    # [REBUILT-2C low-confidence: verify] TASK-088 item 4: registered from the measured published text.
    "set_project_setting": {
        "reason": (
            "[REBUILT-2C low-confidence: verify] TASK-088 第 4 项（逻辑重建，依据=实测发布文本 + 已录制常量）：服务端在这 5 个工具的描述里追加了 TASK-043 的整文件写入诚实声明（`project.godot` 由引擎的整文件写入器重写、手写注释会丢失、同一调用重复执行不改变字节）。该句逐字取自录制证据 `scripts/mcp043_description_evidence.ps1:50` 的 `$Sentence`，而这 5 个工具确实在 C++ 里逐字带有它（`tools/editor_input_simulation.cpp:1244`、`tools/editor_write_scene_editor.cpp:1026`、`tools/project_autoload_write.cpp:256/263`、`tools/project_setting_write.cpp:293`）。原文逐字保留在句首。"
            "TASK-088 依据：work/task088/live/editor-tools-list.json（实测 154 条 tools/list）与 work/task088/cmp_editor.txt（逐工具差异）；被替换的原文逐字为：设置项目设置"
        ),
        "value": "设置项目设置 When this call saves, it rewrites the entire project.godot with the engine's own whole-file writer (the engine has no partial-publish API), so every hand-written comment in that file is lost: the remaining settings are re-emitted verbatim and a repeated identical call changes no bytes (idempotent), and because the comments cannot be kept, back the file up yourself before calling if you need them.",
    },
    # [REBUILT-2C low-confidence: verify] TASK-090 item B (decision D-3),
    # registered from the measured published text of the round-8 session. The
    # tool's old description promised "execute GDScript in the running game" and
    # said nothing about the one boundary that mattered: the generated body used
    # to compile to `extends RefCounted`, so `self` was in no scene tree at all -
    # `get_node()`, `$Path`, signals and `get_tree()` did not exist on it (TASK-089
    # round-7 defect D-3). With the body mounted under the current scene root the
    # description has to state the reach, the path basis and the lifetime
    # boundary. Append-only, like every description override in this table: the
    # old sentence stays first, verbatim.
    "execute_game_script": {
        "reason": (
            "[REBUILT-2C low-confidence: verify] TASK-090 item B（决策 D-3，依据=实测发布文本 + 实测应答）："
            "旧描述只写「在运行中的游戏内执行 GDScript 代码」，没有写「执行体根本不在场景树里」这条边界；"
            "TASK-089 第 7 轮实测（D-3）证明 `self` 是裸 `extends RefCounted`，get_node()/$Path/节点属性/信号/get_tree() 全部不可用。"
            "本任务把执行体改为挂到当前场景根节点下的临时 Node（成功与失败都在返回前移除；无场景树时回退为 RefCounted），"
            "因此描述必须补上：能触达运行中的场景树、路径以临时节点为基准（绝对路径与 get_tree().current_scene 可达任意节点）、"
            "调用同步且节点存活不足一帧（_process/_physics_process 不会被触发）、游戏自身节点树不被改动。原文逐字保留在句首。"
            "TASK-103（X-1，工具缺陷，依据=实测发布文本 + TASK-102 的现场应答）：补上运行期错误的应答契约。"
            "X-1 的现场是 TASK-102 的 m3-task102-r1/g115-runtime-overlay："
            "脚本能编译、执行时调了 C# 拼写的 addChild，VM 中止该帧并只把 SCRIPT ERROR 打到引擎 stderr，"
            "而工具回 ok + {\"result\":null,\"result_type\":\"Nil\"}——没有错误码、没有消息、没有建议，"
            "于是「脚本炸了」与「脚本跑了但没有可见副作用」在答复里无法区分（那一轮真正抓到它的是像素差 0 与场景树里没有该节点）。"
            "修好之后：运行期错误回 -32000 并带 data.script_error（引擎原文、'code' 的行、生成源行、脚本路径、被点名的 GDScript 函数）"
            "与 data.suggestion；成功但 result 为 null/Nil 的应答带 note。这两条都必须写进契约，否则消费者仍会把 ok 当成「脚本执行成功」。"
            "追加式 override：TASK-090 的句子逐字保留在其前，本任务只在其后追加。"
        ),
        "value": "在运行中的游戏内执行 GDScript 代码 有场景树时，代码体作为一个临时 Node 挂在当前场景根节点下执行：get_node()/$Path、节点属性、信号、get_tree() 均可用（路径以该临时节点为基准，绝对路径与 get_tree().current_scene 可达任意节点）；调用返回前该节点必定被移除（成功与失败同样处理），游戏自身的节点树不被改动；调用是同步的，临时节点存活不足一帧，_process/_physics_process 不会被触发。进程内没有场景树时回退为 extends RefCounted，仅全局单例可用。 运行期错误（能编译、但执行中失败，例如调用不存在的方法或方法名大小写错）回 -32000（tool_state：调用格式没问题，是这次执行失败），data.script_error 给出引擎原文 message、'code' 的行号 line（引擎只给行不给列，column 恒为 null）、生成源行号 generated_line、脚本路径 script_path（无路径脚本为 gdscript://<id>.gd）、被点名的 GDScript 函数 function 与错误条数 error_count，data.suggestion 给出改法；同一批事实也进 trace 的调用行（error_data_json），所以溯源里能直接看到这次为什么失败。运行期错误会中止该帧：出错行之后的语句没有执行，脚本的任何副作用都不能假定。脚本运行成功但 result 为 null/Nil 时响应带 note，说明 null 结果不是「有副作用」的证据，须另配效果证据（属性采样 / 场景树快照 / 像素差 / 文件 sha）。",
    },
    # -----------------------------------------------------------------------
    # TASK-097 (GENERATOR_VERSION stays "1.22.0": the six shape quantities of
    # the contract - count 177, added_count 6, generator_version, editor 154,
    # game 73, idempotency - are unchanged by this task, and the version string
    # is one of them). The first description override of `batch_add_nodes`,
    # and it is append-only like every other one in this table: the original
    # wording ("批量添加节点到场景") stays first and verbatim, the discriminator
    # sentence is what changed. It exists because the *default behaviour* of
    # the tool changed: a requested `name` the target parent already carries is
    # now a refusal (-32000 + `data.conflicts`) instead of a silent duplicate
    # the engine renames to `@ColorRect@N` and `editor_save_scene` then writes
    # into the `.tscn` (tool defect D-3; those copies draw on top of the real
    # nodes). The escape hatch is explicit (`on_name_conflict: "rename"`), so
    # the description has to name it.
    # -----------------------------------------------------------------------
    "batch_add_nodes": {
        "reason": (
            "TASK-097（工具缺陷 D-3，根因见 MCP-TRACEABILITY.md §7）：旧描述只写「批量添加节点到场景」，"
            "既没有说同名冲突会怎样，也没有说默认会拒绝。D-3 的实测成因是：目标父节点下已有同名子节点时，"
            "旧实现既不拒绝也不报告，Godot 把新节点自动改名成 @Type@N，随后 editor_save_scene 把两份都写进 .tscn，"
            "副本排在树最后、绘制在真实节点之上（pong 5 / breakout 18 / snake 37 个副本由此而来，"
            "也是像素差列「不可得（D-1）」的真因）。本任务把默认行为改成拒绝，并加显式开关。"
            "原文逐字保留在句首（追加式 override）。"
        ),
        "value": "批量添加节点到场景 默认在目标父节点下已存在同名子节点（或本批内同一父节点下重名）时整批拒绝，回 -32000，data.conflicts 列出冲突节点路径、data.suggestion 给出改法，一个节点都不写入——不会把新节点交给引擎改名后与既有节点一起留在场景里。确有需要时用 on_name_conflict=\"rename\" 显式接受引擎改名，响应在 created[i].name_conflict / renamed_count / renamed[] 里说明哪些节点被改名；editor_save_scene 之后仍会报告这些由本模块批量添加产生的同名重复。",
    },
}
# v1.5: a schema override replaces the whole `inputSchema` object (there is
# nothing to append to), so it must carry `"mode": "replace"` and a `reason` that
# quotes the `required` member it removes verbatim - see the guard in `main`.
# `"required": []` (rather than a dropped key) is the shape every
# no-required-parameter tool of this contract already has
# (`running_game_get_scene_tree`), and `scripts/gen_b2_game_schema.py`
# reproduces it in the C++ literal.
SCHEMA_OVERRIDES = {
    # TASK-053 section 2.3 (M-5): the sampling stride. This is the first override
    # of a **ported** entry in the C tier, and it is the reason the entry count
    # does not move: adding a member to an existing tool is a schema override, not
    # an added tool (GDR-28 point 1 appends new tools; it does not silently
    # rewrite an existing one, so the rewrite has to be recorded here with its
    # reason - which is what `_meta.overrides` is for).
    #
    # The three members that were already there are copied verbatim (`frame_count`
    # 60/采集帧数, `frame_interval` 1/采集间隔帧数, `node_path`/节点路径,
    # `properties`/要监控的属性列表) and `sample_stride` is the only addition.
    # The removed `required` member is quoted below exactly as the guard asks:
    # ["node_path", "properties"] - it is *not* removed, it stays, and the
    # quotation is the guard's way of proving the override did not drop it.
    "monitor_properties": {
        "reason": (
            "TASK-053 第 2.3 节 M-5（决策者裁决）新增可选整数参数 sample_stride（默认 1，最小 1）："
            "保留采样读取工具 running_game_get_node_property_samples 的“观察网格”（frame_interval 决定每隔几帧观察一次）"
            "并把“回传网格”交给 sample_stride（每隔 N 个观察点回传一个，第一个恒回传）。"
            "依据：RACING-TEST-PLAN 的 AC-4/AC-5 连续性断言必须用 frame_interval=1（每帧观察），"
            "而该调用在 3 属性×180 帧下回 23 020 B（REPORT-AUDIT-RACING-BACKLOG §3.5 已记录该体积风险）。"
            "缺省（或显式 1）时响应逐字节与改动前相同：只有 stride>1 时才追加 sample_stride 与 observed_count 两个键；"
            "frame_count 的含义不变成“回传样本数”。被移除的 required 成员逐字为 [\"node_path\", \"properties\"]"
            "（它并未被移除，仍逐字保留在 required 里）；原有四个属性（frame_count/frame_interval/node_path/properties "
            "的 type/default/description）一字未动，只是新增一个属性。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "frame_count": {
                    "default": 60,
                    "description": "采集帧数",
                    "type": "integer",
                },
                "frame_interval": {
                    "default": 1,
                    "description": "采集间隔帧数",
                    "type": "integer",
                },
                "node_path": {
                    "description": "节点路径",
                    "type": "string",
                },
                "properties": {
                    "description": "要监控的属性列表",
                    "items": {"type": "string"},
                    "type": "array",
                },
                "sample_stride": {
                    "default": 1,
                    "description": "回传采样步长：仍然每 frame_interval 帧观察一次，但只回传每第 N 个观察点（第一个恒回传）；缺省 1 与旧行为逐字节一致，大于 1 时响应追加 sample_stride 与 observed_count 两个字段（观察点总数），frame_count 始终是回传的样本数",
                    "type": "integer",
                },
            },
            "required": ["node_path", "properties"],
            "type": "object",
        },
    },
    "replay_recording": {
        "reason": (
            "D-3 契约与行为一致（TASK-014 §1.3 / D59 裁决 1）：把 events 从 required 移除，使契约与实现"
            "（缺省 events 时回退到本游戏进程最近一次录制）一致。被移除的 required 成员逐字为 [\"events\"]；"
            "properties 的两个成员一字未动。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "events": {
                    "description": "要回放的事件数组",
                    "type": "array",
                },
                "speed": {
                    "default": 1.0,
                    "description": "回放速度倍率",
                    "type": "number",
                },
            },
            "required": [],
            "type": "object",
        },
    },
    # TASK-024a E-10: the new optional `mcp_port` argument. A schema override
    # replaces the whole object, so `mode` is repeated verbatim and nothing else
    # moves; this schema never carried a required parameter, and the reason names
    # that removed member (`[]`) verbatim as the guard requires.
    "play_scene": {
        "reason": (
            "TASK-024a E-10 顺手性（GDR-23 §21 第 4 条）：新增可选整数参数 mcp_port，让调用方指定游戏子进程"
            "监听的端口（缺省由模块自动挑一个空闲端口并经 --mcp-port 注入）。被移除的 required 成员逐字为 []"
            "（该 schema 本来就没有必填参数，故“移除”的是一个空列表）；原有的 mode 属性一字未动，只是新增一个属性。"
            "TASK-051 M-3 增补（同一 override 条目，因为一个 old_name 只能有一条 schema override）："
            "再新增 headless（boolean，默认 false）与 extra_args（array of string，默认 []），"
            "因为实测（racing-backlog §3.3，编辑起的子进程命令行只有 --path/--remote-debug/--editor-pid/--scene "
            "加本工具注入的 --mcp-port=<端口>）证明调用方无法给子进程加 --headless，而 --headless 也不会从编辑器继承"
            "（它不在 Main::get_forwardable_cli_arguments(CLI_SCOPE_PROJECT) 里，main.cpp:1123-1155）。"
            "被移除的 required 成员仍然逐字为 []（未删任何成员）；mode 与 mcp_port 两个既有属性（type/default/description）"
            "一字未动，只是新增 headless 与 extra_args 两个属性。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "extra_args": {
                    "default": [],
                    "description": "追加到游戏子进程命令行的额外参数（逐字追加，排在引擎自己构造的 --path/--remote-debug/--editor-pid/--scene 与固定注入的 --mcp-port=<端口> 之后，所以同名参数以这里的为准）；不得包含 --mcp-port（端口只由 mcp_port 参数注入：引擎的命令行解析取最后一次出现，重复注入会让响应里的 endpoint 指向游戏并未监听的端口，故被明确拒绝）；重复的 --headless 会被去重并在响应的 args_deduplicated 里列出；每个元素必须是非空字符串",
                    "items": {"type": "string"},
                    "type": "array",
                },
                "headless": {
                    "default": False,
                    "description": "以 headless 模式启动游戏子进程（给子进程加一个 --headless，即引擎自己的“无音频、无渲染”别名）；默认 false，与旧行为逐字一致。注意 --headless 不会从编辑器继承（引擎的可转发参数表里没有它），所以在无显示环境里必须显式传 true",
                    "type": "boolean",
                },
                "mcp_port": {
                    "description": "游戏子进程监听的 TCP 端口（可选，1-65535）；缺省时自动挑一个空闲端口，且不与编辑器自身端口相同",
                    "type": "integer",
                },
                "mode": {
                    "default": "main",
                    "description": "main/current/路径",
                    "type": "string",
                },
            },
            "required": [],
            "type": "object",
        },
    },
    # TASK-029: `clear` was declared `"default": true` while TASK-028 G-3 made it
    # an explicit opt-in, so the contract was the side that lied. The one member
    # whose *value* changes is `clear.default`; the quotation obligation of v1.5
    # is about `required`, which cannot see a value change, so the reason also
    # quotes the replaced member verbatim (`"default": true`) and this comment
    # together with `_meta.overrides` keeps the old declaration reconstructible.
    "get_test_report": {
        "reason": (
            "TASK-029 契约与行为一致（TASK-028 G-3 收口，决策者裁决方案 A）：把 clear 的 default 由 true 改为 false。"
            "被替换的成员逐字为 \"default\": true；被移除的 required 成员逐字为 []"
            "（该 schema 本来就没有必填参数，“移除”的是一个空列表）；"
            "clear 的 description（\"是否清除结果\"）与两个 type 成员一字未动，properties 只此一个成员。"
            "TASK-028 的实现已是显式 opt-in（缺省或 false = 纯读、不删共享桥接文件），"
            "契约是唯一还在宣称“缺省即清”的地方。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "clear": {
                    "default": False,
                    "description": "是否清除结果",
                    "type": "boolean",
                },
            },
            "required": [],
            "type": "object",
        },
    },
    # -----------------------------------------------------------------------
    # TASK-034 section 0: the four animation-family members TASK-033 measured as
    # *reachable in the migration source but undeclared in the contract*. Each
    # entry adds members only; `required` is quoted verbatim in its reason so the
    # guard in `main` can see that the obligation of the old declaration is
    # unchanged. The reason strings are byte-identical text for the guard, the
    # record and the report (REPORT-034 section 2).
    # -----------------------------------------------------------------------
    "add_state_machine_state": {
        "reason": (
            "TASK-034 §0 契约与行为一致（TASK-033 §7.1 上报的 schema 缺口）：新增可选 animation 成员。"
            "迁移源（addons/godot_mcp_rs/commands/animation_tree_commands.gd:271 与 "
            "godot_mcp_gdext/src/commands/animation_tree.rs）读一个契约未声明的 animation，"
            "而 AnimationNodeAnimation::animation 是**属性**、不是 parameters/… 参数，"
            "所以没有该成员时“给新建的 Animation 状态指定动画”结构性不可达（新建状态永远指向空动画名）。"
            "本次不改 required：被移除的 required 成员逐字为 [\"node_path\", \"state_name\"]（原样保留，未删任何成员）；"
            "原有六个 properties 成员（node_path/position_x/position_y/state_machine_path/state_name/state_type）"
            "的 type 与 default 一字未动，只新增 animation 一个成员。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "animation": {
                    "description": "state_type=animation 时该状态的动画名（当前库内）",
                    "type": "string",
                },
                "node_path": {"type": "string"},
                "position_x": {"default": 0, "type": "number"},
                "position_y": {"default": 0, "type": "number"},
                "state_machine_path": {"default": "", "type": "string"},
                "state_name": {"type": "string"},
                "state_type": {"default": "animation", "type": "string"},
            },
            "required": ["node_path", "state_name"],
            "type": "object",
        },
    },
    "set_blend_tree_node": {
        "reason": (
            "TASK-034 §0 契约与行为一致（TASK-033 §7.1 上报的 schema 缺口）：新增可选 animation 成员。"
            "同 editor_add_state_machine_state：bt_node_type=Animation 时该节点的动画名，"
            "引擎侧是 AnimationNodeAnimation::set_animation（属性），迁移源读了未声明的同名参数。"
            "本次不改 required：被移除的 required 成员逐字为 "
            "[\"node_path\", \"blend_tree_state\", \"bt_node_name\", \"bt_node_type\"]（原样保留，未删任何成员）；"
            "原有七个 properties 成员的 type 与 default 一字未动，只新增 animation 一个成员。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "animation": {
                    "description": "bt_node_type=Animation 时该节点的动画名",
                    "type": "string",
                },
                "blend_tree_state": {
                    "description": "BlendTree 所在的状态名称",
                    "type": "string",
                },
                "bt_node_name": {"type": "string"},
                "bt_node_type": {"type": "string"},
                "node_path": {"type": "string"},
                "position_x": {"default": 0, "type": "number"},
                "position_y": {"default": 0, "type": "number"},
                "state_machine_path": {"default": "", "type": "string"},
            },
            "required": ["node_path", "blend_tree_state", "bt_node_name", "bt_node_type"],
            "type": "object",
        },
    },
    # -----------------------------------------------------------------------
    # TASK-035 section 0: the declaration TASK-034 section 7.1 reported and the
    # decision maker approved. `editor_set_material_3d.material_slot` was declared
    # `string` while the engine's API takes an *integer surface index*
    # (`MeshInstance3D::set_surface_override_material(int p_surface, ...)`,
    # mesh_instance_3d.cpp:375) - so the type risk was pushed onto the client,
    # which would naturally send `0` and be answered "must be a string". The
    # reason names both members it touches verbatim: the replaced `type` of
    # `material_slot` and the `required` list it keeps.
    # -----------------------------------------------------------------------
    "set_material_3d": {
        "reason": (
            "TASK-035 §0 契约与引擎一致（REPORT-034 §7.1 上报、决策者批准）：把 material_slot 的声明由 string 改为 "
            "integer。引擎的 API 是整数表面索引 MeshInstance3D::set_surface_override_material(int p_surface, "
            "const Ref<Material> &p_material)（scene/3d/mesh_instance_3d.cpp:375，ERR_FAIL_INDEX 对 "
            "mesh->get_surface_count()），而契约把 material_slot 声明成 string，等于把类型风险推给客户端："
            "客户端自然会传 0，得到 -32602「must be a string」。被替换的成员逐字为 \"material_slot\": {\"type\": \"string\"}"
            "（其 type 由 \"string\" 改为 \"integer\"，并新增一句 description 说明「表面索引，省略 = 索引 0」，"
            "该成员原本没有 description）；被移除的 required 成员逐字为 [\"node_path\", \"material_path\"]"
            "（原样保留，未删任何成员）；material_path 与 node_path 两个成员一字未动。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "material_path": {"type": "string"},
                "material_slot": {
                    "description": "表面索引（整数）；省略 = 第一个表面（索引 0）",
                    "type": "integer",
                },
                "node_path": {"type": "string"},
            },
            "required": ["node_path", "material_path"],
            "type": "object",
        },
    },
    "add_state_machine_transition": {
        "reason": (
            "TASK-034 §0 契约与行为一致（TASK-033 §7.2 上报的 schema 缺口）：新增 xfade_time / priority / "
            "advance_condition 三个可选成员。三者分别对应 "
            "AnimationNodeStateMachineTransition::set_xfade_time（animation_node_state_machine.h:86）、"
            "set_priority（:98）与 set_advance_condition（:78），"
            "而这三条能力在本批之前**没有任何工具可达**（转移只能设 switch_mode/advance_mode）。"
            "默认值取引擎自己的成员初值：xfade_time=0.0、priority=1（:58/:62）；"
            "advance_condition 缺省为空串，引擎把它注册成布尔参数 "
            "parameters/<状态机路径>/conditions/<名字>，可用 editor_set_animation_tree_parameter 直接喂回。"
            "本次不改 required：被移除的 required 成员逐字为 [\"node_path\", \"from_state\", \"to_state\"]"
            "（原样保留，未删任何成员）；原有六个 properties 成员的 type 与 default 一字未动，只新增三个成员。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "advance_condition": {
                    "description": "该转移的 advance 布尔条件名；引擎注册为 AnimationTree 的 parameters/<状态机路径>/conditions/<名字> 参数（可用 editor_set_animation_tree_parameter 直接写入）",
                    "type": "string",
                },
                "advance_mode": {"default": "enabled", "type": "string"},
                "from_state": {"type": "string"},
                "node_path": {"type": "string"},
                "priority": {"default": 1, "type": "integer"},
                "state_machine_path": {"default": "", "type": "string"},
                "switch_mode": {"default": "immediate", "type": "string"},
                "to_state": {"type": "string"},
                "xfade_time": {"default": 0.0, "type": "number"},
            },
            "required": ["node_path", "from_state", "to_state"],
            "type": "object",
        },
    },
    # -----------------------------------------------------------------------
    # TASK-051 (v1.13): the four remaining entries of the B-tier `inputSchema`
    # batch. Each one *adds* members only; every pre-existing member keeps its
    # type, its default and its description character for character, and the
    # `required` member each entry keeps is quoted verbatim in its reason (the
    # v1.5 guard reads that quotation).
    # -----------------------------------------------------------------------
    "batch_add_nodes": {
        "reason": (
            "TASK-051 C-3 顺手性（racing-backlog 审计 §4.3 confirmed；D86 复测见 REPORT-051 §2.1）："
            "新增可选布尔参数 resolve_within_batch（默认 false）。缺陷的源码位置是 "
            "tools/editor_node_batch_write.cpp:251-258 —— 父路径在**构造之前**用 find_node() 按“调用到达时的场景树”解析，"
            "于是 nodes[1].parent_path=\"P1\"（P1 由同批 nodes[0] 创建）报 -32001「nodes[1]: parent 'P1'」并把整批回滚；"
            "绕法是每深一层多一次调用（审计 A06-A09 实测）。为 true 时父路径可以指向本批更早的元素所创建的节点，"
            "同时把「同批重名」「指向更后面元素的父路径」明确拒绝，并且失败仍然整批回滚（既有语义不变）；"
            "响应在每个 created 元素上给出 parent_source（scene/batch）。被移除的 required 成员逐字为 [\"nodes\"]"
            "（原样保留，未删任何成员）；nodes 属性一字未动（它的 type/description，以及 items 的 properties/required/type "
            "与其中四个成员的 type/description，全部逐字保留），只新增 resolve_within_batch 一个属性。"
            "TASK-097（工具缺陷 D-3）：再新增可选字符串参数 on_name_conflict（默认 \"refuse\"，枚举 "
            "[\"refuse\", \"rename\"]）。D-3 的成因是「目标父节点下已有同名子节点」时旧实现既不拒绝也不报告，"
            "Godot 按既有规则把新节点自动改名成 @Type@N，随后 editor_save_scene 把两份都写进 .tscn，"
            "副本排在树最后、绘制在真实节点之上（pong 5 / breakout 18 / snake 37 个副本即由此而来）。"
            "默认 \"refuse\" 时不写入任何节点，回 -32000，data.conflicts 列出冲突节点路径、data.suggestion 给出改法；"
            "\"rename\" 是显式开关，保留引擎改名行为并在 created[i].name_conflict / renamed_count / renamed[] 里说明。"
            "同一次修改对 required 成员仍是 [\"nodes\"]（逐字保留，未删任何成员），nodes 属性仍一字未动。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "nodes": {
                    "description": "节点数组，每个元素包含 type（必填）、parent_path、name、properties",
                    "items": {
                        "properties": {
                            "name": {
                                "description": "节点名称",
                                "type": "string",
                            },
                            "parent_path": {
                                "description": "父节点路径，默认 \".\"",
                                "type": "string",
                            },
                            "properties": {
                                "description": "要设置的属性字典",
                                "type": "object",
                            },
                            "type": {
                                "description": "节点类型",
                                "type": "string",
                            },
                        },
                        "required": ["type"],
                        "type": "object",
                    },
                    "type": "array",
                },
                "on_name_conflict": {
                    "default": "refuse",
                    "description": "同名冲突策略。默认 \"refuse\"：本批任一元素的 name 在目标父节点下已存在（或与本批更早元素在该父节点下重名）时整批拒绝、什么都不写入，回 -32000，data.conflicts 给出冲突节点路径清单，data.suggestion 给出改法——绝不把新节点交给引擎改名后与既有节点一起留在场景里（那正是 editor_save_scene 把整份副本写进 .tscn、副本绘制在真实节点上层的成因）。\"rename\" 是显式开关，保留引擎自己的重名改名行为（新节点成为 @Type@N），响应在 created[i].name_conflict=\"renamed\"、renamed_count 与 renamed[] 里说明哪些节点被改名，editor_save_scene 随后仍会报告这些由本模块批量添加产生的同名重复。",
                    "enum": [
                        "refuse",
                        "rename",
                    ],
                    "type": "string",
                },
                "resolve_within_batch": {
                    "default": False,
                    "description": "为 true 时元素的 parent_path 可以指向**本批更早的元素**所创建的节点（同一个请求里建父子树）。父元素必须排在子元素之前，父路径指向更后面的元素会被拒绝（父/子循环在按数组顺序应用时就是这个形状）；同一父节点下、同一批内重名会被拒绝（默认 false 时保留引擎自己的重命名）——两种拒绝都仍然整批回滚。默认 false：父路径只按调用到达时的场景树解析，与旧行为逐字相同。响应在每个 created 元素上给出 parent_source（scene/batch），说明父节点来自场景树还是本批",
                    "type": "boolean",
                },
            },
            "required": ["nodes"],
            "type": "object",
        },
    },
    "find_signal_connections": {
        "reason": (
            "TASK-051 O-9 顺手性（racing-backlog 审计 §5.9 confirmed；D86 复测见 REPORT-051 §2.2）："
            "新增可选字符串参数 scope（枚举 all/user/internal，默认 \"all\"）。实测一个 5 节点、用户一条连接都没连的小场景，"
            "{} 请求返回 60/60 条、12 659 B，且 60 条全是编辑器内部方法（ScriptEditor::_queue_update_list、"
            "SceneTreeEditor::_node_script_changed、Viewport::canvas_parent_mark_dirty…）；内部连接的 source 也是普通场景节点路径，"
            "所以 node_path/signal_name 都过滤不掉它们，唯一能区分的是 method（引擎对 MethodBind 型 Callable 的拼写是 Class::method）。"
            "scope=user 只保留 method 不含 :: 的连接（场景/脚本自己连的），scope=internal 只保留引擎/编辑器内部连接；"
            "默认 all 与本工具旧答案逐字相同。signal_name 的子串过滤**刻意不改**：它是与 editor_analyze_signal_flow（精确 node_path）"
            "之间的冻结判别点（GDR-17 / R-1）。被移除的 required 成员逐字为 []（该 schema 本来就没有必填参数，“移除”的是一个空列表）；"
            "node_path 与 signal_name 两个属性（type/description）一字未动，只新增 scope 一个属性。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "node_path": {
                    "description": "节点路径过滤（可选，包含匹配）",
                    "type": "string",
                },
                "scope": {
                    "default": "all",
                    "description": "连接范围：all=全部连接（默认，与本工具旧答案逐字相同）；user=只保留 method 不含 \"::\" 的连接，即场景/脚本自己连的；internal=只保留 method 形如 Class::method 的引擎/编辑器内部连接（编辑器的自连线）。注意内部连接的 source 是普通场景节点路径，按 node_path/signal_name 过滤不掉它们，只有 method 能区分；响应的 counts 给出三种口径各自的条数",
                    "enum": ["all", "user", "internal"],
                    "type": "string",
                },
                "signal_name": {
                    "description": "信号名过滤（可选，包含匹配）",
                    "type": "string",
                },
            },
            "required": [],
            "type": "object",
        },
    },
    "simulate_sequence": {
        "reason": (
            "TASK-051 O-4 契约与行为一致（racing-backlog 审计 §5.4 confirmed；D86 复测见 REPORT-051 §2.3）："
            "为 events 补上 items 对象 schema。原文 events 只有 {\"type\":\"array\"}，调用方无法从 tools/list 得知元素形状，"
            "只能靠失败一次学到（实测 X11：{\"events\":[{\"keycode\":\"W\",\"pressed\":true}]} → -32602 "
            "\"Missing required parameter: events[0].type\"）；items 现在声明 type 的 enum（key/mouse_click/mouse_button/"
            "mouse_move/mouse_motion/action）与各类型读取的成员，全部照实现的读取路径写"
            "（editor_input_simulation.cpp:843-971 的 _build_sequence_event 与 _sequence_* 助手）。"
            "本工具不对嵌套成员做类型闸门（tool_registry.cpp 的未知参数检查只查顶层），所以 items 是声明与文档，"
            "不是新的校验层：行为一字未改。被移除的 required 成员逐字为 [\"events\"]（原样保留，未删任何成员）；"
            "frame_delay 属性（type/default）一字未动；events 的 type 仍是 array，只是补上 items。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "events": {
                    "description": "事件数组, 每个事件包含 type 和对应参数",
                    "items": {
                        "description": "一个输入事件的形状：type 必填（key/mouse_click/mouse_button/mouse_move/mouse_motion/action），其余成员按 type 取用。可粘贴样例：[{\"type\":\"key\",\"keycode\":\"W\",\"pressed\":true},{\"type\":\"key\",\"keycode\":\"W\",\"pressed\":false}]",
                        "properties": {
                            "action": {
                                "description": "InputMap 动作名（type=action 必填）",
                                "type": "string",
                            },
                            "alt": {
                                "default": False,
                                "description": "Alt 修饰键（type=key 用，默认 false）",
                                "type": "boolean",
                            },
                            "button": {
                                "default": 1,
                                "description": "鼠标键（type=mouse_click 用，1=左键，1..9）",
                                "type": "integer",
                            },
                            "button_mask": {
                                "default": 0,
                                "description": "按住的鼠标键位掩码（type=mouse_move 用，默认 0）",
                                "type": "integer",
                            },
                            "ctrl": {
                                "default": False,
                                "description": "Ctrl 修饰键（type=key 用，默认 false）",
                                "type": "boolean",
                            },
                            "keycode": {
                                "description": "按键名（type=key 必填，引擎的按键名，如 \"W\"/\"Space\"/\"Escape\"）",
                                "type": "string",
                            },
                            "position": {
                                "description": "{x,y} 坐标（type=mouse_click/mouse_move 用；与 x/y 等价，两者都给时以 position 为准）",
                                "type": "object",
                            },
                            "pressed": {
                                "default": True,
                                "description": "按下(true，默认)还是松开(false)（type=key/mouse_click/action 用）",
                                "type": "boolean",
                            },
                            "relative": {
                                "description": "{x,y} 相对位移（type=mouse_move 用）",
                                "type": "object",
                            },
                            "relative_x": {
                                "default": 0.0,
                                "description": "相对位移 x（type=mouse_move 用，默认 0）",
                                "type": "number",
                            },
                            "relative_y": {
                                "default": 0.0,
                                "description": "相对位移 y（type=mouse_move 用，默认 0）",
                                "type": "number",
                            },
                            "shift": {
                                "default": False,
                                "description": "Shift 修饰键（type=key 用，默认 false）",
                                "type": "boolean",
                            },
                            "strength": {
                                "default": 1.0,
                                "description": "动作强度（type=action 用，默认 1.0；引擎会夹到 0..1）",
                                "type": "number",
                            },
                            "time_ms": {
                                "description": "被忽略：本工具按 frame_delay 逐帧注入，不按时间戳（给了它只会在响应的 time_ms_ignored 里体现）"
                            },
                            "type": {
                                "description": "事件类型（必填）",
                                "enum": ["key", "mouse_click", "mouse_button", "mouse_move", "mouse_motion", "action"],
                                "type": "string",
                            },
                            "x": {
                                "default": 0.0,
                                "description": "x 坐标（type=mouse_click/mouse_move 用，默认 0）",
                                "type": "number",
                            },
                            "y": {
                                "default": 0.0,
                                "description": "y 坐标（type=mouse_click/mouse_move 用，默认 0）",
                                "type": "number",
                            },
                        },
                        "required": ["type"],
                        "type": "object",
                    },
                    "type": "array",
                },
                "frame_delay": {
                    "default": 1,
                    "type": "integer",
                },
            },
            "required": ["events"],
            "type": "object",
        },
    },
    "run_test_scenario": {
        "reason": (
            "TASK-051 O-5 契约与行为一致（racing-backlog 审计 §5.5 confirmed；D86 复测见 REPORT-051 §2.4）："
            "为 steps[].properties 补上实现一直在读、契约却没写的 pressed 与 strength"
            "（tools/running_game_test_execution.cpp:141-148 optional_bool(p_step,\"pressed\",true,…) 与 "
            "optional_float(p_step,\"strength\",1.0,…)）。两者只对 type=input 的步骤有效：pressed 决定按下还是松开，"
            "strength 是作用在 action 上的强度（引擎夹到 0..1）。这一步只是把既有能力写进声明，行为一字未改"
            "（G03 实测带 pressed:true 的调用本来就成功）。被移除的 required 成员逐字为 [\"steps\"]（原样保留，未删任何成员）；"
            "steps 的 items 里原有九个属性（action/expected/keycode/node_path/operator/property/seconds/text/type，"
            "含 type 的 enum 与 items.required=[\"type\"]）一字未动，只新增两个属性。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "scene_path": {
                    "description": "场景路径，可选 'main', 'current' 或 res:// 路径",
                    "type": "string",
                },
                "steps": {
                    "description": "测试步骤数组，每个步骤包含 type(input/wait/assert) 和相关参数",
                    "items": {
                        "properties": {
                            "action": {
                                "description": "操作名称（input 类型使用）",
                                "type": "string",
                            },
                            "expected": {
                                "description": "期望值（assert 类型使用）"
                            },
                            "keycode": {
                                "description": "按键代码（input 类型使用）",
                                "type": "string",
                            },
                            "node_path": {
                                "description": "节点路径（wait/assert 类型使用）",
                                "type": "string",
                            },
                            "operator": {
                                "default": "eq",
                                "description": "比较操作符: eq/neq/gt/lt/gte/lte/contains/type_is",
                                "type": "string",
                            },
                            "pressed": {
                                "default": True,
                                "description": "input 步骤：注入的事件是按下(true，默认)还是松开(false)",
                                "type": "boolean",
                            },
                            "property": {
                                "description": "属性名（assert 类型使用）",
                                "type": "string",
                            },
                            "seconds": {
                                "description": "等待秒数（wait 类型使用）",
                                "type": "number",
                            },
                            "strength": {
                                "default": 1.0,
                                "description": "input 步骤作用于 action 时的强度（默认 1.0；引擎会夹到 0..1）",
                                "type": "number",
                            },
                            "text": {
                                "description": "期望文本（assert 类型使用）",
                                "type": "string",
                            },
                            "type": {
                                "description": "步骤类型",
                                "enum": ["input", "wait", "assert"],
                                "type": "string",
                            },
                        },
                        "required": ["type"],
                        "type": "object",
                    },
                    "type": "array",
                },
            },
            "required": ["steps"],
            "type": "object",
        },
    },
    # TASK-112 D-T111-3 (v1.23): `editor_add_raycast.dimension` becomes a
    # declared closed set.
    #
    # Rationale for changing the contract at all: the tool is a closed-set tool
    # by nature (it builds exactly one of two node classes), the sibling closed
    # sets in this contract already declare their `enum`
    # (`editor_set_node_selection.mode`, `running_game_run_test_scenario.steps[].type`),
    # and a caller who reads `tools/list` had no way to learn that `"4d"` was
    # anything other than a third option: the old schema said only
    # `{"default":"2d","type":"string"}`, so a typo was accepted and silently
    # produced a `RayCast3D` (measured, `c4-033`). Declaring the enum makes the
    # accepted set visible *before* the call, which is the point of publishing a
    # schema; the runtime refusal added in the same commit is the enforcement.
    #
    # This is a whole-object replacement (the generator has no other mode), so
    # the three members and their `default`s are copied verbatim from the old
    # schema and the only change is the added `enum` on `dimension`. No member is
    # dropped and no `required` member changes: the old schema's `required` member
    # is `[]` and it stays `[]` (逐字：`[]`).
    "add_raycast": {
        "reason": (
            "TASK-112 D-T111-3：把 dimension 声明为闭集 enum [\"2d\",\"3d\"]。"
            "依据：实测 c4-033 的 {\"dimension\":\"4d\"} 返回 ok 且建出 RayCast3D"
            "（旧的 dimension == \"2d\" ? RayCast2D : RayCast3D 对任何非 \"2d\" 值都落 3D），"
            "而契约只写 {\"default\":\"2d\",\"type\":\"string\"}，调用方无法从 tools/list 得知 \"4d\" 非法；"
            "同契约的其它闭集（editor_set_node_selection.mode、run_test_scenario.steps[].type）都已声明 enum。"
            "本次 schema override 是整体替换（mode=replace），dimension 的 default/type、name 与 parent_path 的 "
            "default/type 逐字保留，只新增 enum；被移除的 required 成员逐字为 []（本来为空，且仍为 []，未移除任何成员）。"
        ),
        "mode": "replace",
        "value": {
            "properties": {
                "dimension": {
                    "default": "2d",
                    "enum": ["2d", "3d"],
                    "type": "string",
                },
                "name": {
                    "default": "RayCast",
                    "type": "string",
                },
                "parent_path": {
                    "default": ".",
                    "type": "string",
                },
            },
            "required": [],
            "type": "object",
        },
    },
}

# ---------------------------------------------------------------------------
# v1.8 (TASK-052 section 0, DESIGN-DETAIL.md section 26 / GDR-28): the added
# tools.
#
# Each entry is authored by the decision maker (TASK-052 section 1 gives the
# wording of both entries verbatim) and carries exactly the three contract fields
# plus a `reason` that records *why* the tool exists. The reason is not emitted
# into the contract - `_meta.added_tools` is the ordered list of names that
# GDR-28 point 1 asks for - it is printed by the generator and quoted in
# `docs/reports/REPORT-052-added-tools.md`, which is where the audit trail for
# an added entry lives.
#
# The entries are separate from the two override tables on purpose: those two are
# keyed by an `old_name` of the frozen 174 entry map, an added tool has no such
# row, and mixing the two would make "this description was corrected" and "this
# tool did not exist before" indistinguishable in `_meta.overrides`.
# ---------------------------------------------------------------------------
ADDED_TOOLS = [
    {
        "name": "project_build_csharp",
        "channel": "project",
        "verb": "build",
        "description": (
            "Build the project's C# solution by running the .NET SDK on its .csproj files, and answer the "
            "exit code with the captured output. Requires a Godot build with C# support and a .NET SDK on "
            "PATH; when either is missing the call is refused with the reason and what to install."
        ),
        "inputSchema": {
            "properties": {
                "configuration": {
                    "default": "Debug",
                    "enum": ["Debug", "Release"],
                    "type": "string",
                },
                "extra_args": {
                    "default": [],
                    "items": {"type": "string"},
                    "type": "array",
                },
                "rescan": {
                    "default": True,
                    "type": "boolean",
                },
                "timeout_ms": {
                    "default": 120000,
                    "maximum": 600000,
                    "minimum": 1000,
                    "type": "integer",
                },
            },
            "required": [],
            "type": "object",
        },
        "reason": (
            "M-2 (REPORT-AUDIT-RACING-BACKLOG): the module could create C# projects "
            "(`project_set_setting`, `project_write_text_file`, `project_create_script`) but had no way to "
            "compile one, so the closed loop 'write a C# project from nothing and see it build' stopped one "
            "step short. The engine-side basis is the .NET SDK on PATH (the same tool `dotnet build` runs "
            "through, and the toolchain the engine's own C# exporter expects); the tool is capability-aware "
            "(GDR-28 point 6) because neither the C# module nor the SDK is guaranteed to be present."
        ),
    },
    {
        "name": "project_write_text_file",
        "channel": "project",
        "verb": "write",
        "description": (
            "Write a project text file such as a .csproj, .sln, NuGet.config or .cfg, and answer the "
            "resulting size and sha256. Refuses scene, resource and script paths (use the dedicated tools "
            "for those) and refuses project.godot (use project_set_setting)."
        ),
        "inputSchema": {
            "properties": {
                "content": {"type": "string"},
                "overwrite": {"default": False, "type": "boolean"},
                "path": {"type": "string"},
            },
            "required": ["path", "content"],
            "type": "object",
        },
        "reason": (
            "N-3 (REPORT-AUDIT-RACING-BACKLOG): the 171 ported writers cover scenes, resources, scripts, "
            "shaders, themes and `project.godot`, but not the plain project text file a C# project or a "
            "config needs (.csproj / .sln / NuGet.config / .cfg), so building a C# project from scratch "
            "still required a hand-written file. The tool is deliberately narrow: it refuses the four "
            "dedicated families and `project.godot`, it has no delete path, and it reads the file back "
            "after the publish (size + sha256) instead of reporting the bytes it meant to write."
        ),
    },
    {
        "name": "project_validate_scripts",
        "channel": "project",
        "verb": "validate",
        "description": (
            "Validate every script of the project in one call and answer a per-file verdict, so a batch "
            "of edited scripts can be checked without one call per file. The categories are `ok` (the "
            "file's own language compiled it), `invalid` (it did not compile - for a `.cs` file that is a "
            "project-level build of its .csproj that project_build_csharp ran and recorded, and the item "
            "carries the compiler's own diagnostic text), `not_compiled` (no build of this source is "
            "loaded: the file was modified after the loaded .NET assembly was built, or that assembly has "
            "no class for the script's path - deliberately not `invalid`, because the engine has no C# "
            "compiler and CSharpScript::reload() returns OK unconditionally), `language_unavailable` (this "
            "build has no script backend for the extension) and `unverifiable` (the engine could not load "
            "the file as a Script resource); `valid` is published only for `ok` and `invalid`, and `count` "
            "is always the sum of the per-category counters."
        ),
        "inputSchema": {
            "properties": {
                "include_errors_only": {
                    "default": False,
                    "type": "boolean",
                },
                "paths": {
                    "items": {"type": "string"},
                    "type": "array",
                },
            },
            "required": [],
            "type": "object",
        },
        "reason": (
            "C-4 (3) of REPORT-AUDIT-RACING-BACKLOG: the racing trace calls `project_validate_script` "
            "seventeen times, six of them back to back (seq 127-132 and 274-279), because one call answers "
            "one file - and the ported contract has only the singular tool. The engine-side basis is "
            "already there: `ScriptServer::get_language_for_extension()` plus `Script::set_source_code()` "
            "+ `Script::reload()` is one loop, and TASK-050 N-2's three-way decision (a language this "
            "build does not contain is a refusal, never a borrowed verdict) is the same per file. The tool "
            "answers a category per file (`ok` / `invalid` / `language_unavailable`) whose counters account "
            "for every file it classified, and it is bounded (an explicit truncation marker) because a "
            "response must not be a function of how many scripts the caller's project has. "
            "TASK-054 (D-053-3) adds the fifth category `unverifiable`: a language this build contains whose "
            "scripts the engine API cannot compile. `CSharpScript::reload()` returns OK unconditionally "
            "(modules/mono/csharp_script.cpp:2588-2621) and never parses the source, so the plural tool used "
            "to answer a syntax-error `.cs` with `ok` / `valid: true` (measured: TASK-053 c03). The item now "
            "carries `valid: null`, a `reason` quoting the engine basis (the private `CSharpScript::valid` "
            "field, csharp_script.h:137, set at csharp_script.cpp:2599 from ScriptManagerBridge.cs:436-463) "
            "and a `suggestion`; `unverifiable_count` joins the counters so `count` stays the sum of the "
            "categories. The singular tool refuses the same file with -32000, so the two tools agree. "
            "TASK-055 (D112) replaces the TASK-054 half of this description: C# now has a real verdict "
            "(the engine accessor `CSharpScript::is_source_newer_than_assembly()` plus the public "
            "`Script::is_script_valid()`), the project-level half comes from the per-file diagnostics "
            "`project_build_csharp` records, `not_compiled` joins the categories for 'nothing compiled "
            "this source' (never published as `invalid`), `unverifiable` stays for the residual 'the "
            "engine could not load the file as a Script', and `not_compiled_count` joins the counters so "
            "`count` remains the sum of the five."
        ),
    },
    {
        "name": "editor_set_node_script_batch",
        "channel": "editor",
        "verb": "set",
        "description": (
            "Attach one script to many nodes in the edited scene in a single call, and answer per node "
            "whether the attachment landed and the script was readable. 'node_paths' is an array of node "
            "paths resolved relative to the edited scene root - the same strings the singular tools take "
            "under the name 'path' (editor_set_node_property, editor_get_node_properties): 'Bricks/Car' "
            "and './Bricks/Car' address 'Car' inside 'Bricks', and the edited scene root's own name may "
            "be used as a prefix ('Main/Bricks/Car' == 'Bricks/Car' == './Bricks/Car'). An absolute "
            "scene-tree path ('/root/Main/Bricks/Car') is not accepted, and a bare name such as 'Car' "
            "only addresses a direct child of the edited scene root. A refused path names this rule in "
            "data.suggestion."
        ),
        "inputSchema": {
            "properties": {
                "keep_existing": {
                    "default": False,
                    "type": "boolean",
                },
                "node_paths": {
                    "items": {"type": "string"},
                    "type": "array",
                },
                "script_path": {"type": "string"},
            },
            "required": ["node_paths", "script_path"],
            "type": "object",
        },
        "reason": (
            "C-4 (4) of REPORT-AUDIT-RACING-BACKLOG: `editor_set_node_script` is called eight times in a "
            "row (racing trace seq 133-140) to give the nodes of one edited scene their scripts, and the "
            "ported contract has no batch form. The engine-side basis is `Object::set_script()` plus the "
            "read-back `editor_set_node_script` already performs (`node->get_script()`): `set_script()` is "
            "a void method whose early return for an abstract script is exactly why a batch must answer "
            "what each node really carries. The tool is all-or-nothing like `editor_add_nodes_batch`, "
            "`keep_existing` skips a node that already has a script instead of silently replacing it, and "
            "one `script_path` for the batch is the whole reason the take-back exists."
        ),
    },
    {
        "name": "editor_set_node_property_updates",
        "channel": "editor",
        "verb": "set",
        "description": (
            "Set a different value on each of many nodes in the edited scene in one call, and answer per "
            "entry whether the value landed."
        ),
        "inputSchema": {
            "properties": {
                "updates": {
                    "items": {
                        "properties": {
                            "path": {"type": "string"},
                            "property": {"type": "string"},
                            "value": {},
                        },
                        "required": ["path", "property", "value"],
                        "type": "object",
                    },
                    "minItems": 1,
                    "type": "array",
                },
                "stop_on_error": {
                    "default": False,
                    "type": "boolean",
                },
            },
            "required": ["updates"],
            "type": "object",
        },
        "reason": (
            "TASK-060 M-1 / D-6 (the second round's capability gap): the ported contract's only batch "
            "property write is `editor_set_node_property_batch`, whose grammar is "
            "`{node_type, property, value}` - one **type-scoped** value for every node of a class. Laying "
            "out a level therefore costs one `editor_set_node_property` per node: the round-2 trace called "
            "it 60 times (57 of them the same tool back to back, `fragments`/bigrams of "
            "REPORT-062's TRACE-FRICTION-ANALYSIS), and the request that asked for the missing shape "
            "(`updates:[...]`) was answered `-32602 Unknown parameter 'updates'` (c3_a5_batch_positions). "
            "The engine-side basis is that the write itself is already per node and already gated: "
            "`MCPTools::write_node_property` is one property write on one `Object` (declared type, "
            "component mapping, `ValueSlot` narrowing gate, read-back), so a *path*-scoped list is one loop "
            "over it and needs no new narrowing rule. The engine has no batch setter, so the tool must be "
            "an added name rather than a ported one (GDR-28). `updates[].path` is the same string the "
            "singular tools take under the name `path` (see `NODE_PATH_RULE_SENTENCE`); `stop_on_error` "
            "exists because the useful answer depends on the caller's intent - `false` (the default) "
            "reports every entry and leaves the ones that landed in place, `true` is all-or-nothing like "
            "the rest of this module's batches: the first refusal stops the call and every entry that "
            "already landed is put back to the value it had. The per-entry `changed`/`old_value`/"
            "`new_value` triple is the read-back the sibling tools publish, so 'the value landed' is "
            "never asserted from the request."
        ),
    },
    {
        # TASK-075 section 2: the symmetric half of `project_write_text_file`. The
        # description is the task's own sentence, verbatim.
        "name": "project_read_text_file",
        "channel": "project",
        "verb": "read",
        "description": (
            "Read a text file inside the project and answer its bytes, size and digest, so a file written "
            "by a tool can be verified with a tool."
        ),
        "inputSchema": {
            "properties": {
                "max_bytes": {
                    "default": 1048576,
                    "maximum": 16777216,
                    "type": "integer",
                },
                "path": {"type": "string"},
            },
            "required": ["path"],
            "type": "object",
        },
        "reason": (
            "M1/D3 of PLATFORMER-FINDINGS (the round-5 test's section 0.6 (8)): `project_write_text_file` "
            "is this module's own added writer, so a file it publishes must be verifiable *with a tool* - "
            "and the contract had readers for scripts, scenes, resources, shaders, themes, UIDs and the "
            "filesystem tree, but none for the plain project text file. The round-5 session closed the "
            "write-read-verify loop with an OS hash call (`Get-FileHash`), and its own judgement table "
            "recorded the target as substituted (write passed, read-back could not be constructed). The "
            "engine-side basis is `FileAccess::get_file_as_bytes()` + `FileAccess::get_sha256()`, the two "
            "calls `project_write_text_file` already reads its receipt from, so the write receipt and the "
            "read answer are byte-comparable. The tool is deliberately narrow: read-only, inside `res://`, "
            "it refuses a directory / a missing file / non-UTF-8 bytes, it declares in every answer that it "
            "does not parse or validate the format, and it bounds the text with `max_bytes` (1 MiB default, "
            "16 MiB ceiling) while still answering the WHOLE file's size and digest when the text is "
            "omitted."
        ),
    },
]

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT = os.path.dirname(HERE)

# ---------------------------------------------------------------------------
# The verbs an *added* tool may introduce.
#
# `tool-rename-map.json`'s `convention.verb_closed_set` is the map's own closed
# set for the 174 ported entries, and it stays the authority for those - this
# generator must never widen it (the map's sha256 travels into
# `_meta.map_sha256` and every ported name is validated against it). GDR-28 point
# 4 requires an added entry to be named by the same rule as a ported one, and it
# spells out the channel restriction and the `update_` ban; it does not say
# whether the closed set binds added names too. The decision taken here (recorded
# in `docs/reports/REPORT-052-added-tools.md`, and reported as a gap in the spec
# wording) is: **the closed set keeps its meaning, and a new verb may only enter
# through an explicit record below**, so `--added` can print the exact set of
# verbs the contract ever invented. Two records exist because the decision maker
# fixed the two names of TASK-052 section 1:
#
#   * `build` - `project_build_csharp`. No existing verb says "compile the
#     project with an external toolchain": `run`/`execute` name a script or a
#     scenario, `export` names a Godot export preset;
#   * `write` - `project_write_text_file`. `create` would claim the file is new
#     (it may overwrite), `edit` names a change to an existing file, `set` names
#     a *setting* (`project_set_setting` is the sibling this tool points callers
#     to for `project.godot`), and `save` names the engine's save_* writers.
#     `write` is the verb the contract wording itself uses ("Write a project text
#     file").
#
# The same two records live in `docs/tool-groups-added.json` as
# `verb_extensions`, where `check_tool_groups.py --added` requires each one to be
# actually used by a group, so neither side can accumulate a stale entry.
# ---------------------------------------------------------------------------
ADDED_VERB_EXTENSIONS = {
    "build": "project_build_csharp - no existing verb names 'compile the project with an external toolchain'",
    "write": "project_write_text_file - the file may or may not exist, so create/edit/set/save all overclaim",
}

DEFAULT_OLD_CONTRACT = r"F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json"
DEFAULT_MAP = os.path.join(MODULE_ROOT, "docs", "tool-rename-map.json")
DEFAULT_OUT = os.path.join(MODULE_ROOT, "docs", "tools_list.renamed.json")

OLD_CONTRACT_SHA256 = "8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54"

# GDR-16 L1: channels tried longest prefix first. `running_game_` carries its own
# underscore, so a `split('_')[1]` parse would read the verb as `game`.
CHANNELS = ("running_game", "project", "editor", "os")
L1_PATTERN = re.compile(r"^(editor|running_game|project|os)_[a-z0-9_]+$")

# D-4: the disposition field is an enum, and a merge names its survivor through
# the separate `merge_target` field instead of the v1.0 `merge_into:<old_name>`
# string form.
DISPOSITION_ENUM = (
    "rename",
    "keep",
    "merge_into",
    "unregister_until_implemented",
    "fix_implementation_first",
)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_tool_name(name):
    """Isomorphic to MCPToolRegistry::parse_tool_name (tool_registry.cpp)."""
    for channel in CHANNELS:
        prefix = channel + "_"
        if not name.startswith(prefix):
            continue
        rest = name[len(prefix):]
        if not rest:
            return None
        if not all((("a" <= c <= "z") or ("0" <= c <= "9") or c == "_") for c in rest):
            return None
        # `editor_get` is legal: the object segment is not required (D-E4).
        verb = rest.split("_", 1)[0]
        return channel, verb
    return None


def validate_renamed(entry, closed_set):
    """GDR-16 L1..L4 checks for one map entry. Returns None or a reason."""
    name = entry["new_name"]
    if "update_" in name:
        return "L4 banned 'update_': %s" % name
    if not L1_PATTERN.match(name):
        return "L1 pattern mismatch: %s" % name
    parsed = parse_tool_name(name)
    if parsed is None:
        return "L1 parse failure: %s" % name
    channel, verb = parsed
    if verb not in closed_set:
        return "L2 verb '%s' outside the closed set: %s" % (verb, name)
    if verb != entry.get("verb"):
        return "L3 declared verb '%s' != parsed '%s': %s" % (entry.get("verb"), verb, name)
    if channel != entry.get("channel"):
        return "L3 declared channel '%s' != parsed '%s': %s" % (entry.get("channel"), channel, name)
    return None


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def validate_added(entry, closed_set):
    """GDR-28 point 4 naming lint for one `ADDED_TOOLS` record.

    There is no `tool-rename-map.json` row for a new tool, so the two facts a
    ported entry is cross-checked against the map (`channel`, `verb`) are
    cross-checked against the record's own declaration here: the name is parsed
    with the isomorphic `parse_tool_name`, and the channel and the verb the name
    spells out have to be the ones the record declares. A verb outside the map's
    closed set is accepted only when `ADDED_VERB_EXTENSIONS` carries a record for
    it (see the table's comment). Returns None or a reason."""
    for field in ("name", "channel", "verb", "description", "inputSchema", "reason"):
        if field not in entry:
            return "missing field '%s'" % field
    if not str(entry["name"]).strip():
        return "empty name"
    if not str(entry["reason"]).strip():
        return "empty reason (an added entry has to say why it exists)"
    name = entry["name"]
    if "update_" in name:
        return "L4 banned 'update_': %s" % name
    if not L1_PATTERN.match(name):
        return "L1 pattern mismatch: %s" % name
    parsed = parse_tool_name(name)
    if parsed is None:
        return "L1 parse failure: %s" % name
    channel, verb = parsed
    if channel != entry["channel"]:
        return "declared channel '%s' != parsed '%s': %s" % (entry["channel"], channel, name)
    if verb != entry["verb"]:
        return "declared verb '%s' != parsed '%s': %s" % (entry["verb"], verb, name)
    if verb not in closed_set and verb not in ADDED_VERB_EXTENSIONS:
        return "L2 verb '%s' is outside the closed set and has no ADDED_VERB_EXTENSIONS record: %s" % (verb, name)
    if not isinstance(entry["description"], str) or not entry["description"].strip():
        return "description must be a non-empty string"
    if not isinstance(entry["inputSchema"], dict):
        return "inputSchema must be a JSON object"
    return None


def apply_override(table, old_name, fallback, used, kind):
    """Returns (value, overridden). `overridden` is what makes the carry-over
    assertion below precise: the promise is "nothing moves *without* an explicit
    override", so a fired override has to be exempt from it (in B0 the table was
    empty, so the distinction was not observable and the blanket assertion made
    every override impossible).

    An entry is either

      * append-only (the default, v1.2): `value` is `<old value> + " " +
        <discriminator>`, so not a byte of the original wording can be lost; or
      * `"mode": "replace"` (v1.4): `value` is the corrected text and the
        *reason* has to carry the old text verbatim, so the correction stays
        auditable in `_meta.overrides` even though the field itself is rewritten.
        This mode exists for a value that is factually **wrong**, where an
        append-only discriminator would leave the false statement in the field a
        caller reads (`TASK-007` section 1).
    """
    record = table.get(old_name)
    if record is None:
        return fallback, False
    if "reason" not in record or "value" not in record:
        raise SystemExit("override for %s must carry 'reason' and 'value'" % old_name)
    if not str(record["reason"]).strip():
        raise SystemExit("override for %s carries an empty 'reason'" % old_name)
    mode = record.get("mode", "append")
    if mode not in ("append", "replace"):
        raise SystemExit("override for %s carries an unknown mode %r" % (old_name, mode))
    used.append({"kind": kind, "old_name": old_name, "mode": mode, "reason": record["reason"]})
    return record["value"], True


def main():
    parser = argparse.ArgumentParser(description="Generate the renamed tools/list contract.")
    parser.add_argument("--old-contract", default=DEFAULT_OLD_CONTRACT)
    parser.add_argument("--map", default=DEFAULT_MAP)
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()

    old_path = os.path.abspath(args.old_contract)
    map_path = os.path.abspath(args.map)
    out_path = os.path.abspath(args.out)

    for path, label in ((old_path, "old contract"), (map_path, "rename map")):
        if not os.path.isfile(path):
            sys.exit("FATAL: %s not found: %s" % (label, path))

    old_sha = sha256_file(old_path)
    map_sha = sha256_file(map_path)

    with open(old_path, "r", encoding="utf-8") as handle:
        old_contract = json.load(handle)
    with open(map_path, "r", encoding="utf-8") as handle:
        rename_map = json.load(handle)

    if old_sha != OLD_CONTRACT_SHA256:
        sys.exit("FATAL: old contract sha256 %s != the frozen %s" % (old_sha, OLD_CONTRACT_SHA256))

    # --- self check 1: map vs old contract are the same 174 tool names -------
    entries = rename_map["tools"]
    total = rename_map.get("total")
    if not (len(entries) == total == 174):
        sys.exit("FATAL: map total=%s but %d entries" % (total, len(entries)))

    old_names = [tool["name"] for tool in old_contract["result"]["tools"]]
    entry_names = [entry["old_name"] for entry in entries]
    if len(set(old_names)) != len(old_names):
        sys.exit("FATAL: the old contract has duplicate tool names")
    if set(old_names) != set(entry_names):
        missing = sorted(set(old_names) - set(entry_names))
        extra = sorted(set(entry_names) - set(old_names))
        sys.exit("FATAL: map does not cover the old contract: missing=%s extra=%s" % (missing, extra))

    by_old_name = {entry["old_name"]: entry for entry in entries}
    closed_set = set(rename_map["convention"]["verb_closed_set"])

    # --- D-4: disposition is an enum, and a merge is named by merge_target ----
    bad_enum = sorted({entry.get("disposition") for entry in entries} - set(DISPOSITION_ENUM))
    if bad_enum:
        sys.exit("FATAL: disposition value(s) outside the enum: %s" % bad_enum)
    legacy = [entry["old_name"] for entry in entries
              if str(entry.get("disposition", "")).startswith("merge_into:")]
    if legacy:
        sys.exit("FATAL: the v1.0 inline 'merge_into:<old_name>' form survives on %s" % legacy)

    # --- disposition split ---------------------------------------------------
    excluded = [entry["old_name"] for entry in entries
                if entry.get("disposition") == "unregister_until_implemented"]
    merged = []
    for entry in entries:
        if entry.get("disposition") != "merge_into":
            continue
        target = entry.get("merge_target")
        if not target:
            sys.exit("FATAL: merge_into entry %s carries no merge_target" % entry["old_name"])
        merged.append({
            "old_name": entry["old_name"],
            "new_name": entry["new_name"],
            "merged_into": target,
        })
    for entry in entries:
        if entry.get("disposition") != "merge_into" and "merge_target" in entry:
            sys.exit("FATAL: merge_target on a non-merge entry: %s" % entry["old_name"])

    if len(excluded) != 2:
        sys.exit("FATAL: expected 2 unregister_until_implemented entries, got %d" % len(excluded))
    if len(merged) != 1:
        sys.exit("FATAL: expected 1 merge_into entry (GDR-17), got %d" % len(merged))

    keep_names = set(entry["old_name"] for entry in entries)
    for item in merged:
        keep = item["merged_into"]
        if keep not in keep_names:
            sys.exit("FATAL: merge keep '%s' is not an old_name in the map" % keep)
        if keep in excluded:
            sys.exit("FATAL: merge keep '%s' is itself excluded" % keep)
        # self check 4: the merged entry and its keeper share one new name, so
        # deduplication cannot create a duplicate.
        if by_old_name[keep]["new_name"] != item["new_name"]:
            sys.exit("FATAL: merge %s -> %s but keeper %s -> %s"
                     % (item["old_name"], item["new_name"], keep, by_old_name[keep]["new_name"]))

    excluded_set = set(excluded)
    merged_set = set(item["old_name"] for item in merged)
    dropped = excluded_set | merged_set

    # --- self check 2: every emitted new name passes the isomorphic lint -----
    for entry in entries:
        if entry["old_name"] in dropped:
            continue
        reason = validate_renamed(entry, closed_set)
        if reason is not None:
            sys.exit("FATAL: %s" % reason)

    # --- transform: name only, description / inputSchema verbatim ------------
    overrides_used = []
    new_tools = []
    name_sources = []
    for tool in old_contract["result"]["tools"]:
        entry = by_old_name[tool["name"]]
        if entry["old_name"] in dropped:
            continue

        new_tool = dict(tool)  # keeps the old key order
        new_tool["name"] = entry["new_name"]

        description, desc_overridden = apply_override(DESCRIPTION_OVERRIDES, entry["old_name"],
                                                     tool["description"], overrides_used, "description")
        schema, schema_overridden = apply_override(SCHEMA_OVERRIDES, entry["old_name"],
                                                  tool["inputSchema"], overrides_used, "inputSchema")

        # The no-override case must be a byte-exact carry over at the object
        # level; the assertion is what keeps the promise from section 2 honest.
        if not desc_overridden and canonical(description) != canonical(tool["description"]):
            sys.exit("FATAL: description of %s changed without an explicit override" % entry["old_name"])
        if not schema_overridden and canonical(schema) != canonical(tool["inputSchema"]):
            sys.exit("FATAL: inputSchema of %s changed without an explicit override" % entry["old_name"])
        # v1.2: an *append* override may only add one discriminator sentence, so
        # the original wording can never be silently dropped. v1.4 adds the
        # explicit `mode: "replace"` escape hatch for text that is factually
        # wrong; it is refused unless the record's reason quotes the text it
        # replaces, so a replacement cannot be a silent edit either.
        mode = DESCRIPTION_OVERRIDES.get(entry["old_name"], {}).get("mode", "append") if desc_overridden else "append"
        if desc_overridden and mode == "append" and not str(description).startswith(str(tool["description"]) + " "):
            sys.exit("FATAL: description override of %s is not append-only (original wording lost)"
                     % entry["old_name"])
        if desc_overridden and mode == "replace":
            original = str(tool["description"])
            reason = str(DESCRIPTION_OVERRIDES[entry["old_name"]]["reason"])
            if original not in reason:
                sys.exit("FATAL: replacing description override of %s must quote the text it replaces in "
                         "'reason' (original wording would be lost from the record)"
                         % entry["old_name"])
        # v1.5: a schema override is a whole-object replacement, and the one thing
        # it can silently drop is a `required` member. The record must therefore
        # name what it removes, verbatim, or the contract's old obligation is gone
        # with no trace beyond "a schema override fired".
        if schema_overridden:
            record = SCHEMA_OVERRIDES[entry["old_name"]]
            if record.get("mode") != "replace":
                sys.exit("FATAL: schema override of %s must carry \"mode\": \"replace\" (a schema is "
                         "replaced, there is nothing to append to)" % entry["old_name"])
            removed_required = canonical(tool["inputSchema"].get("required", []))
            if removed_required not in str(record["reason"]):
                sys.exit("FATAL: schema override of %s must quote the 'required' member it removes "
                         "verbatim in 'reason' (expected %s)"
                         % (entry["old_name"], removed_required))

        new_tool["description"] = description
        new_tool["inputSchema"] = schema
        new_tools.append(new_tool)
        name_sources.append(entry["new_name"])

    # --- v1.8 (GDR-28 point 1): deterministic append of the new tools ---------
    # After the rename + override pass, never before: an added entry is not a
    # carried-over entry with a changed field, and the two name lists are proved
    # disjoint in both directions below. The output key order is the ported
    # entries' key order (`description`, `inputSchema`, `name`, which is the old
    # contract's own order with `name` replaced), so the file stays diffable.
    ported_names = set(name_sources)
    map_new_names = set(entry["new_name"] for entry in entries)
    added_names = []
    added_verbs_used = set()
    for record in ADDED_TOOLS:
        reason = validate_added(record, closed_set)
        if reason is not None:
            sys.exit("FATAL: added tool: %s" % reason)
        name = record["name"]
        if name in ported_names:
            sys.exit("FATAL: added tool %s has the same name as a ported tool" % name)
        if name in map_new_names:
            sys.exit("FATAL: added tool %s collides with a rename-map new_name" % name)
        if name in added_names:
            sys.exit("FATAL: added tool %s is declared twice" % name)
        if record["verb"] not in closed_set:
            added_verbs_used.add(record["verb"])
        added_names.append(name)
        new_tools.append({
            "description": record["description"],
            "inputSchema": record["inputSchema"],
            "name": name,
        })
        name_sources.append(name)
    stale_verbs = sorted(set(ADDED_VERB_EXTENSIONS) - added_verbs_used)
    if stale_verbs:
        sys.exit("FATAL: ADDED_VERB_EXTENSIONS record(s) never used: %s" % stale_verbs)

    # --- self check 5: every declared override fired exactly once ------------
    # v1.5: per `(kind, old_name)`, not per `old_name`. One tool may legitimately
    # carry both a description and a schema override (D-3 is the first), and
    # nothing about that should make either record disappear. The counters are
    # still exact in both directions: a declared name that never fires is a hard
    # failure, and so is a record count that does not match the declaration.
    declared_overrides = set(
        (kind, name)
        for kind, table in (("description", DESCRIPTION_OVERRIDES), ("inputSchema", SCHEMA_OVERRIDES))
        for name in table)
    fired_overrides = set((record["kind"], record["old_name"]) for record in overrides_used)
    stale_overrides = sorted("%s/%s" % pair for pair in (declared_overrides - fired_overrides))
    if stale_overrides:
        sys.exit("FATAL: override(s) never fired (typo in old_name?): %s" % stale_overrides)
    if len(overrides_used) != len(declared_overrides):
        sys.exit("FATAL: %d override records for %d declared overrides"
                 % (len(overrides_used), len(declared_overrides)))

    # --- self check 3: count and uniqueness ----------------------------------
    # 174 entries - 2 unregister_until_implemented - 1 lossless merge == 171,
    # plus the N entries the decision maker authored (GDR-28): 171 + N.
    EXPECTED_OUTPUT = 174 - 2 - 1 + len(ADDED_TOOLS)
    if len(new_tools) != EXPECTED_OUTPUT:
        sys.exit("FATAL: expected %d output tools, got %d" % (EXPECTED_OUTPUT, len(new_tools)))
    if len(set(name_sources)) != len(name_sources):
        duplicates = sorted(name for name in set(name_sources) if name_sources.count(name) > 1)
        sys.exit("FATAL: duplicate new names in the output: %s" % duplicates)

    meta = {
        "generated_from": old_path,
        "generated_from_sha256": old_sha,
        # [REBUILT-2C low-confidence: verify] TASK-088 item 4: `map_path` is the
        # RECORDED build root, not this machine's, so the contract's sha256 is a
        # function of its content and not of where it was generated. It used to
        # be `map_path` - `os.path.abspath(args.map)` - which made a byte-identical
        # regeneration impossible by construction (`H:\rebuild\godot\...` is 24
        # bytes shorter than the recorded `F:\RustProjects\godot-mcp-pro\...`).
        # The recorded value is not a guess: it appears verbatim, with the same
        # `map_sha256` this tree has, in the recorded terminal dumps
        # (`staging/__payload-index/events-termdump.jsonl`, e.g. lines 228, 569,
        # 1127; extracted to work/task088/map_path2.txt).
        "map_path": RECORDED_MAP_PATH,
        "map_sha256": map_sha,
        "tool_count_in": len(old_names),
        "count": len(new_tools),
        # v1.8 (GDR-28 point 1): the entries that did not come from the map. The
        # list is ordered exactly like the append, so `result.tools[-N:]` are
        # these names in this order; `added_count` is redundant with the list's
        # length on purpose (a consumer that only needs the arithmetic does not
        # have to trust a length).
        "added_count": len(added_names),
        "added_tools": added_names,
        # D-1 (TASK-003 section 1.1, D49): `result.tools` is a *set* for the
        # consumers; the order is explicitly outside the contract. The engine is
        # only required to be deterministic within one build (a second
        # `tools/list` on the same registry is byte-identical), not to reproduce
        # the order below - so no implementation may ever be "fixed" to match it.
        "order_normative": False,
        "excluded": excluded,
        "merged": merged,
        "generator_version": GENERATOR_VERSION,
        "generated_by": GENERATED_BY,
    }
    if overrides_used:
        meta["overrides"] = overrides_used

    output = {
        "id": old_contract["id"],
        "jsonrpc": old_contract["jsonrpc"],
        "result": {"tools": new_tools},
        "_meta": meta,
    }

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(output, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    out_sha = sha256_file(out_path)

    print("gen_renamed_contract: input tools = %d" % len(old_names))
    print("gen_renamed_contract: output tools = %d" % len(new_tools))
    print("gen_renamed_contract: order_normative = %s (order is not part of the contract)"
          % json.dumps(output["_meta"]["order_normative"]))
    print("gen_renamed_contract: merged = %d (%s)" % (
        len(merged), ", ".join("%s -> %s" % (m["old_name"], m["merged_into"]) for m in merged)))
    print("gen_renamed_contract: unregister = %d (%s)" % (len(excluded), ", ".join(excluded)))
    print("gen_renamed_contract: added = %d (%s)" % (len(added_names), ", ".join(added_names)))
    for record in ADDED_TOOLS:
        print("gen_renamed_contract: added[%s] verb=%s reason=%s"
              % (record["name"], record["verb"], record["reason"]))
    print("gen_renamed_contract: added verb extensions used = %s"
          % (", ".join(sorted(added_verbs_used)) if added_verbs_used else "(none)"))
    print("gen_renamed_contract: description overrides = %d (append-only, %s)"
          % (len(overrides_used), ", ".join(record["old_name"] for record in overrides_used)))
    print("gen_renamed_contract: old contract sha256 = %s" % old_sha)
    print("gen_renamed_contract: rename map sha256 = %s" % map_sha)
    print("gen_renamed_contract: output sha256 = %s" % out_sha)
    print("gen_renamed_contract: self-checks = OK (lint %d/%d, unique %d/%d, disposition enum OK)"
          % (len(new_tools), len(new_tools), len(new_tools), len(new_tools)))
    print("gen_renamed_contract: wrote %s" % out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
