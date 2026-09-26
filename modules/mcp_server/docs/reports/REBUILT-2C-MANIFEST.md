# REBUILT-2C MANIFEST — 2c-3 (`H:\rebuild\godot`, branch `feature/mcp-server-module-rebuild`)

* Task: TASK-084 (2c-3) — push the reconstructed `modules/mcp_server` toward a green build.
* Start HEAD: `be6aa88c8c` (== `origin/feature/mcp-server-module-rebuild`).
* Every fragment below is either **recorded text** replayed at its recorded position, or a
  **mechanical call-site alignment** to an already-declared/wording-identical sibling. Where a
  fragment had to be written rather than replayed it is wrapped in
  `// [REBUILT-2C low-confidence: verify] ... // [/REBUILT-2C]` in the code and marked
  `REBUILT` in the table.

## Evidence sources used (this is the change of method versus TASK-083)

| source | what it gives | how it was used |
|---|---|---|
| `staging\__payload-index\events-read.jsonl` | per-revision read windows (`totalLines`, numbered `lines`) | line-number skeleton, byte-comparison against the tree |
| `staging\__payload-index\events-write.jsonl` | **whole recorded file contents** | replay base (`rec.py`) |
| `staging\__payload-index\events-edit.jsonl` | **every edit's full OLD and NEW text** | exact text for the dropped spans (`ev.py`) |
| `work\task084\{probe,windows,search,igrep,ev,layout,rgn,showdiff,rec,buflen,bal}.py` | the forensics tooling | see "Reproduce" below |

TASK-083 chose a "read epoch" base and reported 4 files as **unrecoverable**. That conclusion is
refuted: `events-edit.jsonl` stores the full `new` text of every edit, so the dropped spans are
recorded text, not a guess. `work\task084\rec.py` rebuilds a file from the newest recorded
whole-file write plus every later recorded edit, and fills the uncovered runs of the newest
revision skeleton from that replay.

## Files changed

| # | file | lines | what was done | basis | behaviour risk |
|---|---|---|---|---|---|
| 1 | `modules/mcp_server/tools/project_cross_scene_write.h` | insert 4 lines after 36 | restore `class Node;` + its 2-line comment + blank | rev156 window lines 37–40, **byte-identical**, and the same forward declaration is the module's own idiom (`running_game_node_write.h:40`, `tool_helpers.h:48`) | none — restores the declaration; removes the `int MCPTools::Node/String/Variant` cascade |
| 2 | `modules/mcp_server/tools/editor_node_batch_write.cpp` | replace 75–190 (116), 350–354 (5), 415–429 (15) | replay the recorded whole-file write `seq=274` + all 13 later edits; every diff hunk must fall inside an **uncovered** run of rev766 (asserted) | `events-write seq=274` + `events-edit` (incl. `seq=267`, 272, 277, 282, 287, 292, 686) | none — recorded text; the replaced 84–149 was a stale pre-TASK-051 duplicate and 415–429 was a `set_node_property_batch_on` fragment spliced into `add_nodes_batch_on` |
| 3 | `modules/mcp_server/tools/tool_helpers.h` | replace 1124–1130 (7) with 72 lines, then 9 with 19 | replay `seq=810` (4-argument `build_execute_gdscript_source`, `struct GDScriptReloadReport`, `reload_gdscript_capturing`) and `seq=860` (`gdscript_reload_failure_text`) | `events-edit seq=810 t=1790298746575`, `seq=860 t=1790298785652`, both applied in time order | none — recorded text; the stale 3-argument duplicate further down becomes an overload, still compiling |
| 4 | `modules/mcp_server/tools/editor_input_simulation.cpp` | insert 21 lines before the "Event construction" header | replay the recorded `_number_fits_event` definition + its TASK-023 D-7 comment | `events-edit seq=324 t=1790093826031`, verbatim | none — recorded text |
| 5 | `modules/mcp_server/tools/editor_control_layout_write.cpp` | 123 | `_relative_path(` → `relative_path(` | hoist recorded in `events-edit seq=367` NEW ("is `MCPTools::relative_path`"); declared at `tool_helpers.h:608` | none — same signature, same semantics, the file-local copy no longer exists |
| 6 | `modules/mcp_server/tools/editor_node_write.cpp` | 383 | `_optional_dictionary(` → `optional_dictionary(` | hoist recorded in `events-edit seq=387/397` NEW ("It is `MCPTools::optional_dictionary`"); declared at `tool_helpers.h:736` | none — same signature |
| 7 | `modules/mcp_server/tools/editor_read_scene_inspector.cpp` | 225, 322, 382 | `_require_editor_ui(r_error)` → `require_editor_ui(r_error, "<wording>", "<hint>")` | `events-edit seq=713/470/431` NEW states the guard "is called below as `require_editor_ui(r_error, <non-editor wording>, <suggestion>)`"; the exact wording is the one the **same group** already uses at `editor_node_read.cpp:467` | **low**: the two literal strings are chosen from the sibling group, not read out of this file (no recorded edit rewrites these three call sites) |
| 8 | `modules/mcp_server/tools/editor_write_scene_editor.cpp` | 760 | same 1-argument → 3-argument alignment | same recorded NEW text; wording from the same file's own line 211 | **low**: same caveat as #7 |
| 9 | `modules/mcp_server/tools/editor_node_setup.cpp` | 794–798 → 1 line | **REBUILT**: the body of `if (!optional_float(p_args, "agent_height", …))` had been replaced by a whole register-tool block; restored to the sibling body `return Variant();` | the identical register block already exists at 873–878; every other `optional_*` check in the same function answers `return Variant();` (`781/785/789/797/800`) | none — restores the documented body of an already-present check; marked in code |

## Examined and deliberately **not** changed (the TASK-083 §5.3 diagnosis for these was wrong)

| file | finding |
|---|---|
| `modules/mcp_server/tools/tool_helpers.h` (the "87 errors at line 83") | The file is **byte-identical to its newest read window** over the whole covered range (842/842 lines, `cmp.py`). Line 83's `C2371 MCPTools::String: redefinition` was a *cascade* of file #1 (MSVC's `note:` points at `project_cross_scene_write.h(118)`). No head was lost. |
| `modules/mcp_server/tools/running_game_node_write.h` (the "22 errors at line 59") | byte-identical to rev216 (216/216 lines, `cmp.py`); the same cascade. |
| `modules/mcp_server/tools/tool_builder.h`, `tools/editor_node_setup.h`, `tools/project.cpp` | the tree already equals the reconstruction; their errors are not splice damage. |

## Result (measured, same counter on both logs — `recount84.py`)

| build | error lines | files |
|---|---:|---:|
| TASK-083 `build ②` (`tests=no -j8 -k`) | 444 | 20 |
| **TASK-084 `build ③`** (`tests=no -j8 -k`) | **191** | **10** |

`project_cross_scene_write.cpp`, `editor_node_batch_write.cpp`, `editor_node_setup.cpp`,
`editor_read_scene_inspector.cpp`, `editor_input_simulation.cpp`, `editor_script_write.cpp`,
`editor_control_layout_write.cpp`, `editor_animation_tree_write.cpp` and `tool_helpers.h`'s hosting
translation units all compile now (object files rebuilt **after** the edits — see the report §5).

## Reproduce

```
python probe.py   <relpath> [a b [rev]]   # read windows of one file
python cmp.py     <relpath> <rev>         # tree vs newest-revision window, line by line
python ev.py      <relpath> [seq]         # recorded write/edit events, full OLD/NEW
python rec.py     <relpath> [--out f]     # replay-based reconstruction + coverage report
python showdiff.py <relpath>              # tree vs reconstruction
python recount84.py <stderr.txt>          # error count + per-file grouping
```

## Iron rules

* Only `H:\rebuild\godot` and `C:\Users\wyl\AppData\Local\Temp\mcp-recovery\` were written.
* `F:` was never written; §6 of the report carries the byte-identical `DECISIONS.md` hash check.
* Builds are started from `cmd.exe` via `Start-Process … -RedirectStandardOutput/-RedirectStandardError`
  (`work\task084\scons_run.ps1`); **no shell redirection** is used for log capture.
* Two accidental `>` redirects happened in scratch commands inside `work\task084\` before the
  launcher existed (`dump_batch.txt`, `blk267.txt`); both scratch files were removed and the
  deviation is recorded in the report.

---

# REBUILT-2C MANIFEST — 2c-4 (`H:\rebuild\godot`, branch `feature/mcp-server-module-rebuild`)

* Task: TASK-085 (2c-4) — 191 error lines → a green compile and the first runnable exe.
* Start HEAD: `a26cf4fd83`; reached `081f95e65f`.
* Method as 2c-3: **recorded text replayed at its recorded position**; every written fragment is
  marked `// [REBUILT-2C low-confidence: verify]` in code and `REBUILT` below.
* Tooling: `work\task085\` (`evfetch.py`, `replay2.py`, `rebuild.py`, `fix_*.py`, `find_sym.py`).

## Result (measured with the same counter, `recount84.py`)

| build | error lines | files | outcome |
|---|---:|---:|---|
| TASK-084 `build ③` (`tests=no -j8 -k`) | 191 | 10 | red |
| **TASK-085 r7** (`tests=no -j8 -k`) | **0** | **0** | compiles; 5 undefined symbols at link |
| **TASK-085 r12** (`tests=no -j8 -k`) | **0** | **0** | **exit 0 — `bin/godot.windows.editor.x86_64.exe` (179 007 488 B)** |
| `tests=yes -j8 -k` (first) | 80 | 1 | `tests/test_mcp_server.h` only |
| **`tests=yes -j8 -k` (last)** | **0** | **0** | **exit 0 — exe 193 225 216 B** |

## Ruling (B) — duplicate generations, later one kept

| file | generation A (discarded) | generation B (kept) | criterion |
|---|---|---|---|
| `tools/tool_helpers.cpp` | 171–193 `VECTOR4`/`VECTOR4I` gen-0 and 390–515 `PACKED_*` gen-2 | the `VECTOR4I`/`QUATERNION` cases moved after line 271 | later **edit order** (`events-edit seq=853`, evidence rev2487 t=1790147836781 lines 184–213) and consistent with the current `switch` |
| `tools/running_game_node_write.cpp` | the earlier `_node_path_for_result` | the later `_node_path_for_result` | later edit order; consistent with the current declaration/schema/registration |
| `tests/test_mcp_server.h` | 9133–9487 — the five `editor_read_scene_inspector` TEST_CASEs at 19 game-scope / 26 editor-process tools | 2941–3583 — the same five at 48 / 76 tools | the kept copy's counts are what the current registration produces; the discarded copy's are the pre-TASK-009/010/011/012 counts |

Discarded-generation summary (content, not bytes): `tool_helpers.cpp` A = a first `VECTOR4`/
`VECTOR4I` dictionary-generation pair and a second PACKED-array generation, both superseded by the
single generation that now stands at 254–320. `running_game_node_write.cpp` A = an
`_node_path_for_result` that took `(Node *, const String &)`. `test_mcp_server.h` A = the
pre-GDR-19 table sizes above.

## Ruling (C) — written, marked, registered

| file | lines | what was written | why it could not be replayed |
|---|---|---|---|
| `tools/project_write_resource_scene.cpp` | the `is_label == nullptr` branch of `_write_resource_properties` | 13 lines closing the branch with `-32602` / `-32001` refusals | the tree opens `MCPToolError::invalid_params(vformat(` and then jumps into the older revision's tail; the refusal **sentences** are recorded verbatim (rev775/rev768 windows), the two calls around them are the shape the file's own comment prescribes |
| `tools/project_write_resource_scene.cpp` | `MCPTools::write_resource_properties` | a 10-line adapter over the private `_write_resource_properties` | the header (line 92) exports the name, `_tool_edit_resource` calls it, and the tree only has the private copy — the body is untouched |
| `tools/tool_helpers.cpp` | `schema_with_integer_defaults` closing | `return schema;` + `}` | the rev3233 window stops at `schema["properties"] = properties;`; the return type and the helper's own comment admit no other reading |
| `mcp_jsonrpc.cpp` | `dispatch` | `MCPTrace::Record trace; trace.traceable = p_trace;` + 8 `_tag(..., trace)` wraps | the header declares `dispatch(..., bool p_trace)`; the only recorded definition (rev388 line 311) takes four parameters and predates the trace. The body, `_immediate`, `_tag`, `_effective_timeout`, `_dispatch_tools_call` and `handle` are all recorded text. |
| `mcp_jsonrpc.cpp` | `_dispatch_tools_call` 272–284 | the 13-line gap rebuilt ("Missing tool name" + the arguments guard) | rev453's window has a 13-line hole; the wording is the tree's own recorded `_handle_tools_call` and rev453 line 285 pins the second message |

## Restored verbatim (no marker needed)

| file | span restored | recorded source |
|---|---|---|
| `tool_registry.cpp` | whole file (914 lines, 0 breaks) | strict replay of `events-write` + `events-edit` in time order |
| `tools/project_write_resource_scene.cpp` | `_tool_create_scene_file` 393–468 | rev697 t=1790165880935 lines 379–459 |
| `tools/project_write_resource_scene.cpp` | `_tool_delete_scene_file` | rev775 t=1790229066466 lines 446–490 |
| `tools/project_write_resource_scene.cpp` | `_property_table`, `resource_bag_name_is_addressable` | replay (recorded write + edits) |
| `tools/editor_write_scene_editor.cpp` | the `_tool_set_viewport_3d_camera` body | rev1088 t=1790180050322 719–749 + rev1046 t=1790093622477 721–760, anchor-aligned |
| `tools/running_game_frame_observation.cpp` | whole file + regenerated schema | replay + `gen_b2_game_schema.py --group running_game_frame_observation --in-place` |
| `tools/running_game_node_write.cpp` | whole file | `rebuild --base read` (rev774 complete) |
| `tools/running_game_test_execution.cpp` | whole file + regenerated schema | replay + the recorded `scene_path` refusal block + `gen_b2_game_schema.py --in-place` |
| `tools/project_validate_scripts.cpp` | `_is_script_extension` body, one registration | replay |
| `tools/editor_node_write.cpp` | 6 call sites | hoisted spellings (`MCPTools::edited_scene_root`, `MCPTools::find_node`, `relative_path`) |
| `mcp_jsonrpc.cpp` | `build_result_raw`, `build_error_raw` | rev388 t=1790170254765 lines 199–206 |
| `tests/test_mcp_server.h` | `#ifdef MCP_EDITOR_TOOLS_ENABLED` before the orphan `#endif`; 10 `TestMCPServer::ScratchProject` + 5 `TestMCPServer::list_files_recursive` qualifications; 2 `(bool)` casts; 3 parenthesised `CHECK`s | the file's own dominant spellings and the recorded `CHECK((bool)payload["created"]);` |

## Reproduce (2c-4)

```
python work\task085\replay2.py   <relpath>            # strict replay (result=="...has been updated")
python work\task085\rebuild.py   <relpath> --base read|rev:N
python work\task085\fix_pwrs4.py --apply              # project_write_resource_scene.cpp
python work\task085\fix_link.py  --apply              # the two link gaps
python work\task085\fix_jsonrpc3.py --apply           # dispatch + the deferred layer
python work\task085\fix_jsonrpc2.py --apply           # the two envelope builders (AFTER jsonrpc3)
python work\task085\fix_tests2.py --apply             # test header duplicates + qualifications
python work\task085\fix_doctest2.py --apply           # doctest C2338
python work\task085\scons_run.ps1 -Command '<scons>' -Tag <tag>
python work\task085\run_godot.ps1 -ArgLine '<args>' -Tag <tag>
```

## Iron rules (2c-4)

* Only `H:\rebuild\godot` and `C:\Users\wyl\AppData\Local\Temp\mcp-recovery\` were written.
* `F:` was never written; the byte-identical `DECISIONS.md` hash check is in the report §7.
* Every build and every Godot run is started from `cmd.exe` via `Start-Process
  -RedirectStandardOutput/-RedirectStandardError`; **no shell redirection** is used.
* Destructive operations ran only through the guarded `remove_legacy.py` (absolute path, sha256
  pre-check, manifest printed first).

---

# REBUILT-2C MANIFEST — 2c-5 (`H:\rebuild\godot`, branch `feature/mcp-server-module-rebuild`)

* Task: TASK-086 (2c-5) — 21 failing cases / 271 failing assertions → **3 failing cases / 15
  failing assertions**, all three with a recorded cause (see "Open conflicts").
* Start HEAD: `de7e93d06a`; end HEAD `058f618bb2` (this section is the fifth commit).
* Method: unchanged — **recorded text replayed at its recorded position**. Nothing in this
  section is written from memory; every fragment names the event (`seq`/`time`) or the generator
  that produced it.
* Tooling: `work\task086\` (`stat_names.py`, `scopes.py`, `rp.py`, `evlist.py`, `evhit.py`,
  `apply_ev.py`, `apply_tail.py`, `insert_head.py`, `span_from_edit.py`, `fix_counts.py`,
  `fix_log_fixture.py`, `cdiff.py`, `sessions.py`, `reads.py`).
* Logs: `logs\task086_build1..3.*`, `logs\task086_run1..3.*`, baseline `logs\task086_baseline.*`.

## Result (measured)

| run | cases | passed | failed | assertions | passed | failed | exit |
|---|---:|---:|---:|---:|---:|---:|---:|
| baseline (`de7e93d06a`) | 111 | 90 | 21 | 4370 | 4099 | 271 | 1 |
| after step 1 (registration) | 143 | 124 | 19 | 6381 | 6279 | 102 | 1 |
| after step 2+3 | 143 | 136 | 7 | 6390 | 6368 | 22 | 1 |
| **after step 4 (final)** | **143** | **140** | **3** | **6391** | **6376** | **15** | **1** |

The case count moves 111 → 143 because the baseline run died of SIGSEGV in
`the replay tool validates every event before it waits for a frame` (test_mcp_server.h:6219); with
that tool registered the case completes and the 32 cases after it run for the first time.

## The one root cause of the `-32601` cluster

`work\task086\stat_names.py` compares the `ToolBuilder builder("<name>")` declarations of
`modules/mcp_server/tools/*.cpp` against the contract: **158 of 177 names were declared**. The 19
missing ones are in four group files whose `// BEGIN generated` span was empty or stale:

| # | file | missing | restored from | measured |
|---|---|---|---|---|
| 1 | `tools/running_game_input.cpp` | 4 | `gen_b2_game_schema.py --group running_game_input --in-place` | 33 270 → 36 295 B |
| 2 | `tools/running_game_observation.cpp` | 6 | `gen_b2_game_schema.py --group running_game_observation --in-place` | 36 845 → 43 267 B |
| 3 | `tools/running_game_assertion.cpp` | 2 | `gen_b2_game_schema.py --group running_game_assertion --in-place` | 32 767 → 36 161 B |
| 4 | `tools/editor_read_scene_inspector.cpp` | 7 | replay of the recorded `C:\…\Temp\t006_gen_reg.py` (events-write seq=593) | placeholder → 7 registrations |

After the four, `177 contract entries = 177 declared, 0 either way` and the live registry measures
exactly what the contract predicts (`work\task086\scopes.py`: 46 `both` + 102 `editor` + 23
`game` + 6 `ADDED_TOOLS` = 177 registered in an editor process, 154 visible to an editor, 73 in a
game process, 50 `both` = the editor view of a game table).

## Restored verbatim (recorded text at its recorded position)

| file | span | recorded source |
|---|---|---|
| `tools/editor_read_scene_inspector.cpp` | `MCPLogSource`, `_log_tail`, `_read_log_source`, `_add_log_source_fields`, both log tools (TASK-026 E-6/G-4) | `events-edit seq=470 t=1790127805398`, 130 → 209 lines; old-tail anchored on `// The tail window of \`read_log_file\``, the `struct` + section comment inserted in front of it |
| `tools/project_read_analysis.cpp` | the whole `project_get_scene_dependencies` block (TASK-024b E-1/G-2) | `events-edit seq=480 t=1790120943437`, 46 → 123 lines; applied to tree span 707–800 after asserting both boundaries |
| `tests/test_mcp_server.h` | the fixture of `editor_get_errors reports the ERROR lines of the log tail` | `events-edit seq=756 t=1790023248440` |
| `tests/test_mcp_server.h` | the fixture of `editor_get_output_log filters the tail case sensitively` | `events-edit seq=758 t=1790023248475` |
| `tests/test_mcp_server.h` | `CHECK(before.size() == 11)` + its own inventory comment in `the analysis tools never write to the project` | `events-edit seq=457 t=1790014377020` |
| `scripts/gen_renamed_contract.py` | the two TASK-068 append-only `DESCRIPTION_OVERRIDES` records | `docs/reports/evidence/task076/contract_fingerprint.txt` lines 20–24 / REPORT-068 §2.3 |
| `tools/running_game_input.cpp`, `tools/running_game_observation.cpp`, `tools/running_game_assertion.cpp`, `tools/running_game_test_execution.cpp` | the whole registration span | `scripts/gen_b2_game_schema.py` over `docs/tools_list.renamed.json` + `docs/tool-rename-map.json` |

## The two log fixtures, and why the third one is absent

`String(const char *)` in this fork is `append_latin1` (`core/string/ustring.h:693`), so a narrow
literal holding non-ASCII bytes produces mojibake. Two of the three log fixtures in the tree were
reconstructed with the bare literal; the recorded final text (seq=756/758) keeps the ASCII half in
`String(...)` and appends `String::utf8(...)` for the CJK line. The third
(`the log tools declare their source and their process`) already used `String(content)` with
`String::utf8(...)` inside and needed nothing.

## Ruling (D) — the stale registry-size assertions are the OLD generation

38 assertions across four test cases still carried the TASK-015/TASK-017 generation of the table
sizes (48 / 76 / 59 / 35 / 31 / 24). They are the old side, on three independent pieces of
evidence:

1. the recorded edit stream of `tests/test_mcp_server.h` contains edit after edit whose whole
   purpose is to move exactly these numbers up as each batch lands - `get_tool_count() == 40` (7
   occurrences at once, `events-edit seq=974 t=1790074265360`), then 175 (`seq=1085
   t=1790298972674`), then 176 (`seq=705 t=1790342829701`);
2. the recorded final-generation numbers 176 / 153 / 72 are exactly 177 / 154 / 73 minus the
   TASK-075 tool (`project_read_text_file`, `scope = both`), i.e. the same quantity one batch
   earlier;
3. `docs/tools_list.renamed.json` + `docs/tool-rename-map.json` predict 177 / 154 / 73 / 50, and
   after the registration recovery the registry measures exactly those numbers.

`work\task086\fix_counts.py` rewrites each of the 39 sites by line number with its expected old
text asserted (the 39th is `source == "no_log_file"` → `"none"`, the TASK-026 marker). Two stale
key-set assertions went with them: `payload["reason"]` (TASK-024 key, replaced by the nine-key
TASK-026 block) → `payload["note"].contains("shared")`, and the same key in the honest-empty
branch → `note.contains("does not exist")`.

## Open conflicts (the three remaining cases, each with its recorded cause)

| case | test side | implementation side (later recording) | judgement |
|---|---|---|---|
| `project_edit_resource rewrites an existing resource and skips unknown properties` (8 assertions) | unknown names are skipped, call succeeds - `events-edit seq=596 t=1790166576966` | unknown names are refused `-32001` naming them - `events-edit seq=577 t=1790229749088` | **the test is the older generation**: the implementation recording is 6.3e7 ms later, and TASK-049 D8 is the task that closed the name shape on both sides. The test text for the refusal rule is **not in the recording** (no edit of `tests/test_mcp_server.h` matches `is not a property of`), so it is left for a batch that can obtain it |
| `project_edit_resource reports no change and validates its arguments` (2) | same | same | same |
| `project_read_resource reports the loaded resource type` (5) | TASK-024 E-9 shape: `properties_total`, `properties_count`, `properties_truncated`, `properties_limit == 256`, `properties_byte_limit == 256*1024` - `events-edit seq=600 t=1790101526117` | TASK-026 shape: `total_properties`, `truncated`, `dropped`, `limits.max_properties == 64` - `events-edit seq=445/450 t=1790127763038/1790127766391` | **the test is the older generation** (1.3e7 ms earlier); the test text for the TASK-026 shape is not in the recording |

## Reproduce (2c-5)

```
python work\task086\stat_names.py x            # 177 declared == 177 contract entries
python work\task086\scopes.py                  # 177 / 154 / 73 / 50, contract-derived
python work\task086\rp.py <path> --out <f>     # strict replay (exact old, time-ordered)
python work\task086\evlist.py <path> [seq field]   # every recorded edit of one file
python work\task086\evhit.py <path> "<needle>" [old|new|both]  # recorded text around a needle
python work\task086\apply_tail.py  <path> <seq> "<anchor>" <target> [--check]
python work\task086\insert_head.py <path> <seq> "<marker>" "<anchor>" <target>
python work\task086\span_from_edit.py <path> <seq> <target> <startline> <endline>
python work\task086\fix_counts.py ; python work\task086\fix_log_fixture.py
python work\task086\cdiff.py <before.json> <after.json>
python work\task085\scons_run.ps1 -Command '<scons>' -Tag <tag>
python work\task085\run_godot.ps1 -ArgLine '<args>' -Tag <tag>
```

## Iron rules (2c-5)

* Only `H:\rebuild\godot` and `C:\Users\wyl\AppData\Local\Temp\mcp-recovery\` were written.
  `F:` was only *read*: `F:\moonbit-hof-rs\DECISIONS.md` (537 251 B, sha256 `114B2A8218…`) and
  `F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json` (48 749 B, sha256 `8F8051C4C0…`, the
  frozen input `gen_renamed_contract.py` re-reads) are byte-identical to the pre-flight values, and
  `Get-PSDrive F` still reports 922 841 124 864 used / 392 138 186 752 free.
* Every build and every Godot run is started from `cmd.exe` via
  `Start-Process -RedirectStandardOutput/-RedirectStandardError`; no log is captured with a shell
  redirection. One deviation is recorded: a single scratch command used `>nul 2>nul` as a no-op
  guard (no file written, nothing captured); the task's own scratch commands use `-OutFile` or the
  wrappers above.
* No destructive command ran at all in this task: every change is a write over an existing file
  with the recorded text as its source, and no file was removed.
