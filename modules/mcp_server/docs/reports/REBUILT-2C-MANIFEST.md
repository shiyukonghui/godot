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

---

# REBUILT-2C MANIFEST — 2c-6 (`H:\rebuild\godot`, branch `feature/mcp-server-module-rebuild`)

* Task: TASK-087 (2c-6) — close TASK-086's step 5, then G6 / G3 / G5 / acceptance.
* Start HEAD: `d82f621fc1`. Tooling: `work\task087\` (`rep.py` UTF-8 reporter, `merge.py`,
  `merge2.py` / `merge3.py`, `editchain.py`, `editmatch.py`, `epoch.py`, `sessions.py`,
  `ps1_parse.ps1`, `verify_dd.py`).
* Method unchanged where the evidence allows it: **recorded text replayed at its recorded
  position**. The one new method this batch is allowed to use is *logical rebuild* for spans the
  evidence genuinely does not carry; every such span is wrapped in
  `// [REBUILT-2C low-confidence: verify] … // [/REBUILT-2C]` (or the file-appropriate comment
  syntax) and listed in the table below with its basis and its behaviour risk.

## E-1. `docs/DESIGN-DETAIL.md` — G3, restored byte-exact (no marker needed)

| item | value |
|---|---|
| before | 31 531 B / 417 lines (the tree copy stopped inside §15's clause table) |
| target | **84 486 B** |
| after | **84 486 B**, sha256 `b8ad40a34a33951b220349ea70ba59fba064ce9fa8b53ed7653b834b33be29c0` |
| basis | **recorded read-window text, not a logical rebuild.** There is no `events-write` row for this path (`reconstruction.jsonl` records `"NO_WRITE_PAYLOAD"`). The 120 recorded read windows cover line numbers **1–1034 with zero holes**; pass A of `merge.py` keeps, for every line number, the text carried by the newest recorded row that has it. |
| cross-check | the independently produced TASK-078 staging body `staging\modules\mcp_server\docs\DESIGN-DETAIL.md` is **byte-identical** (same 84 486 B, same sha256). Two reconstructions from the same index agreeing to the byte is the strongest available evidence, so the residual risk is reset to whether the *recording itself* captured the terminal revision — `epoch.py` shows the newest contributing window is `t=1790349324870`, the newest read of any revision, and every later recorded edit is a no-op on this buffer (0 applied, 0 broken). |
| what was added (the 728 lines the tree had lost) | the §15 clause-table rows for GDR-22/23/24; **§§17–26** in full: GDR-19 B1 framework (17.1–17.4), GDR-20 deferred response channel, GDR-21 input-channel boundary, GDR-22 unified narrowing gate (20.1–20.7), GDR-23 reference-source hierarchy, GDR-24 narrowing-point declaration (22.1–22.4), GDR-25 ergonomics (23.1–23.5), GDR-26 optional server-side call tracing, GDR-27 before/after capture, GDR-28 contract expansion |
| marker | **none** — no byte of this file was invented |
| behaviour risk | none: documentation only, no code path reads it |

## E-2. `scripts/accept_m1.ps1` — G6, `[Parser]::ParseFile` 10 errors → **0**

| item | value |
|---|---|
| before | 57 469 B / 1 008 lines, **10** parse errors (first at `:644` `The Try statement is missing its Catch or Finally block`) |
| after | **49 502 B / 1 022 lines, 0 parse errors** (`[System.Management.Automation.Language.Parser]::ParseFile`) |
| sha256 | `6e2072ac48ae9f09edb50132fb29cb03a3d52b89cf548181dd7910df71215552` |
| basis | **recorded window text, no logical rebuild.** The damaged body is not repairable by patching — it is a concatenation of *fragments*: `:644` is a stray `}` opening the "Game side" banner, `:665`–`:675` is case 18's body under case 13's label, `:814` and `:875` repeat whole cases, `:886`–`:895` repeats case 13's body, and `:976`–`:1 083` appends one and a half further copies of the `guard_user_port_9877` block *after* `exit 0`. Worse, the union of all 128 recorded windows carries **foreign text**: the `// ---` C++ banner of `tools/editor_shader_write.cpp` (`// TASK-035 (B5 batch 3): the \`editor_shader_write\` group`) appears at line 556 of the union, so a "newest text per line number" merge over every window is contaminated. |
| the fix that made it exact | `epoch.py`/`merge2.py --skeleton N` restrict the merge to windows that belong to **one revision skeleton** (`totalLines <= 1022`), which drops the 5 later-revision windows whose bodies are contaminated. 27 window rows, every line 1–1 022 present, **zero holes**; the result parses with 0 errors. The `totalLines <= 1008` skeleton (17 rows, 48 686 B) also parses with 0 errors and is kept as a second witness. |
| what changed, honestly | the restored body carries **case1–case19** (the M1 case list). Two later cases the damaged copy had already named are **not** re-added: `case0_repo_exit_code_propagation` (TASK-069) and `case20_tools_list_cross_process_restart` (TASK-004). Their text *is* recorded (`events-edit seq=1030 t=1790321324515`, 1 998 B; `seq=858 t=1790015088330`, 3 061 B) and both were grafted experimentally onto the clean base at their recorded anchors, but the graft does **not** reach 0 parse errors (17), so it is **not** what was written. Choosing the parseable recorded revision over a broken superset is the conservative reading; the two cases are therefore recorded here as **not rebuilt**, with their exact event ids, so the next batch can add them deliberately. |
| marker | **none** in the file (the whole body is recorded text); the scope reduction is declared here instead |
| behaviour risk | **low, declared.** `accept_m1.ps1` is a *gate*, not shipped code. The restored gate covers the DESIGN-DETAIL §9 M1 rows plus the hardening rows case15–case19; it does not run the TASK-069 exit-propagation probe or the TASK-004 cross-process-restart probe. `case7_parse_error`/`case11`/`case17`/`case18`/`case19` (the GDR-12 rows) are all present. |

## E-4. TASK-086 step 5 (`d82f621fc1`) — per-hunk ruling, and the three conflict cases closed

The diff of `d82f621fc1` is exactly two files: `tests/test_mcp_server.h` (+127 / −58) and this
manifest. Every hunk of the test file was judged against one rule: **an edit that weakens or
deletes an assertion to make a gate green is reverted; an edit that restores test text the
recording does not carry is rebuilt with a marker.**

| # | hunk | verdict | why |
|---|---|---|---|
| 1 | 38 registry-size assertions `48/76/59/35/31/24` → `73/177/154/50` | **keep** | the replacements are what the contract predicts *and* what the live registry measures (`count=177`, `added_count=6`; the doctest values in §2c-5 §3 are the same numbers). No assertion removed; `work\task087\scan_counts.py` re-measures the file and finds **47 registry-size assertion sites, zero of them carrying a stale value** and no site whose expected value was dropped. The recorded edit stream moves exactly these numbers batch by batch (`events-edit seq=974/1085/705`). |
| 2 | `the analysis tools never write to the project`: `before.size() == 13` → `11` (+2 comment lines) | **keep** | the fixture is `ScratchProject`, whose inventory is 11; 13 is `ReadFilesProject`'s (the case below it). The guraded quantity did not change, only the number was wrong. |
| 3 | `payload["reason"]` → `payload["note"].contains("shared")`, and `"no_log_file"` → `"none"` + `note.contains("does not exist")` | **keep** | TASK-026 removed the TASK-024 `reason` key; the replacement asserts on the key the recorded `_add_log_source_fields` / `_read_log_source` actually write. Two assertions became two assertions — nothing weakened. |
| 4 | the two `ScratchLog` fixtures, bare narrow literal → `String(...) + String::utf8(...)` | **keep** | this fork's `String(const char *)` is `append_latin1` (`core/string/ustring.h:693`), so the old text put mojibake in the log and the byte-exact CJK filters could never match. The recorded final text is `events-edit seq=756/758`. |
| 5 | **the three stale explanatory comments step 5 left behind** | **rebuilt, marked** | the commit moved the assertions but not the prose that explains them: `:1419` still said "the game-process table carries the 23 both-scope tools plus the 17 game-scope ones" above `== 73`; `:4664` still said "66 → 76 registered, 49 → 59 visible" above `== 177 / == 154`; `:7759` still said "76 registered tools, 59 of them visible" above `== 177 / == 154`. Each is now realigned to the counts its own assertions use and wrapped in `// [REBUILT-2C low-confidence: verify] … // [/REBUILT-2C]`. These are the only text this batch wrote rather than replayed. |

**Reverts: none.** No hunk of `d82f621fc1` was found to weaken or delete an assertion, so nothing
was rolled back.

### The three conflict cases (TASK-086's "Open conflicts")

All three were *test side = older generation, implementation side = newer recording, updated test
text absent from the recording*. Under this batch's authorization they are closed by **logical
rebuild against the tool's declared schema and its live behaviour**, each wrapped in
`// [REBUILT-2C low-confidence: verify] … // [/REBUILT-2C]`:

| case | old test text (recorded) | what the implementation does (recorded, later) | what was written | why this is the conservative reading |
|---|---|---|---|---|
| `project_edit_resource rewrites an existing resource …` | unknown names skipped, call succeeds (`seq=596 t=1790166576966`) | refuses `-32001` naming the name (`seq=577 t=1790229749088`, TASK-049 D8) | case renamed to `… rewrites an existing resource`; the unknown-name half moved into the second case as a refusal block asserting `result == NIL`, `code == -32001`, `message.contains(name)`, `data.suggestion` present and containing `is not a property of`, and **the file unchanged** | the refusal is a strictly *stronger* claim than the skip was; the "nothing on disk moved" half is preserved, and the resource's real write path is still asserted end to end (byte image changed, reload sees the new value). The suggestion text is the recorded `not_found(...)` wording in `tools/project_write_resource_scene.cpp:592-596`, not invented. |
| `project_edit_resource reports no change and validates its arguments` | same | same | the unknown-name block added (as above) plus an **empty-bag** block asserting `message == "No properties were changed"` and `changed.is_empty()` | the empty bag is the one case the implementation's short circuit is honest for (`project_write_resource_scene.cpp:718-729`), so both branches now have a case instead of one branch being tested twice. |
| `project_read_resource reports the loaded resource type` | TASK-024 E-9 shape: `properties_total` / `properties_count` / `properties_truncated` / `properties_limit == 256` / `properties_byte_limit == 256*1024` (`seq=600 t=1790101526117`) | TASK-026 shape: `total_properties` / `truncated` / `dropped` / `limits.max_properties == 64` (`seq=445/450 t=1790127763038/1790127766391`) | the five key/cap assertions rewritten to the published shape: `total_properties == 2`, `total_properties == properties.size()`, `truncated == false`, `dropped == 0`, `limits.max_properties == 64`; the value halves (`properties.size() == 2`, the two member checks, `resource_path` absent) are unchanged | read straight out of `tools/project_read_files.cpp:789-795` (`MAX_RESOURCE_PROPERTIES = 64`, no byte budget). The cap is the tool's own constant; the count assertion is a tautology-free `total_properties == properties.size()` where the old pair had two independently-wrong numbers. |

## E-5. Gate ledger (TASK-087, real output)

| gate | command | result |
|---|---|---|
| module doctest | `--headless --test --test-case=[MCPServer]*` | **exit 0** — `143 / 143 passed / 0 failed`, `6396 / 6396` assertions, `SUCCESS!` |
| full engine doctest | `--headless --test` | **exit 0** — `1569 / 1569 passed / 0 failed / 3 skipped`, `430702 / 430702` assertions, `SUCCESS!`, no `FATAL` / `SIGSEGV` in stdout or stderr |
| group manifest | `docs/scripts/check_tool_groups.py` | **PASS** (`TOOL-GROUPS CHECK PASS`, 5681 B, sha `b83d79d3…`) |
| contract subset (live) | `scripts/check_contract_subset.ps1` | **3/3 PASS** — editor 9888 `154 == 154`, game 9889 `73 == 73`, verbatim; `guard_user_port_9877` `pid_before=-1 pid_after=-1`; `contract=177` |
| rename map | `docs/scripts/check_rename_map.py` | **PASS** (`all checks green`; G5/G6 re-derive `177 == 174 - 2 - 1 + 6`) |
| tautologies | `scripts/check_tautologies.py` | **PASS** (`every hit is pinned; scanned=2 file kind(s) under 2 root(s)`) |
| exit-code propagation | `scripts/check_exit_propagation.py` (+ `--probes`) | **PASS** (`every aggregator shape is guarded or pinned`) / `PROBES: 10/10` |
| hardcoded counts | `scripts/check_hardcoded_counts.py` | **FAIL (1 unclassified line)** — pre-existing and independently recorded: `docs/scripts/_tmp_gen_b3_b5.py:282` contains the literal `171` in a comment ("`docs/tools_list.renamed.json (171 entries) …`"). That is a `_tmp_` scratch generator, not a contract consumer, and TASK-086's report §5.4 already listed exactly this item as *not done*. Nothing in this batch touched it; it is reported as a known red rather than silenced. |
| engine anchor | `scripts/check_engine_anchor.ps1` | not run (rebuilds the mono binary; out of this batch's scope, unchanged from TASK-086) |
| M1 acceptance | `scripts/accept_m1.ps1` | **16 / 20 cases**, exit 1 — four FAILs, all four are the script's own **M1-era expectations** meeting the now-complete registry. Detail below. |

### E-5.2 `accept_m1.ps1` — the four remaining FAILs, with their measured values

The script now parses (E-2) and runs end to end. Four cases fail; each one is the *script's*
expectation being the M1 generation while the live answer is the TASK-075 registry:

| case | script expects | live answer (measured) | judgement |
|---|---|---|---|
| `case1_GET_mcp_200` | the status body's `tools` count is the 2 M1 tools | `{"connections":1,"frame_count":211,"is_editor":true,"listening":true,"pending":0,"pending_connections":0,"port":9888,"server":"godot-mcp-rs","status":"ok","**tools":154**,"transport":"streamable-http"}` | **script is the old generation.** `tools: 154` is exactly `get_visible_tool_count(true)`, the number the module doctest asserts and the contract predicts. Nothing on the wire is wrong. |
| `case3_tools_list_fixture` | the listing holds the 2 M1 tools | `tools=154`, and the two it checks are `name_verbatim=True inputSchema_verbatim=True description_verbatim=True` | same. The verbatim half of the case **passes**; only the count is stale. |
| `case12_game_process_endpoint` | the game listing holds the M1 game subset | `status=200 is_editor=False`, `initialize` verbatim, and the game endpoint lists what E-5.1's gate compares verbatim; the failing half is a count against the same 2/6-era expectation | same. This is the **same defect as `check_contract_subset`'s**, from the script side: it compares against a hand-maintained M1 list instead of the manifests. |
| `guard_user_port_9877` | `pid_before -gt 0` ("the user's editor is present") | `listening=False pid_before=-1 pid_after=-1` | **script is the old generation.** The user's editor listener on 9877 was retired during the project; the correct invariant is "this script never touches 9877", which `check_contract_subset.ps1`'s own guard states positively as `pid_before=-1 pid_after=-1` and passes. |

**Not fixed in this batch, and why:** repairing these four means rewriting the script's expected
tool sets to be **derived from the manifests** (the way `$ToolNames` already is at the top of the
file) instead of the M1 literal `2`, plus inverting the 9877 guard to the 9877-retired
invariant. That is a change to the gate's *assertions*, so it belongs to a batch that can rebuild
and re-run the whole acceptance; this batch's authorization covers logical rebuild of *missing
text*, and none of these four is missing text — they are positively-wrong expectations with a
recorded later generation on the other side. They are reported as **red with cause**, not
silenced, and the invariant they were meant to protect **is** asserted and passing elsewhere:
`check_contract_subset.ps1` proves `154 == 154` / `73 == 73` verbatim on both endpoints and the
9877 guard, and the module doctest proves the same numbers at the registry level.

### E-5.1 The two missing group manifests (and why the gate was red)

`check_contract_subset.ps1` first failed **2/3** with the registry reading *stronger* than the
gate's expectation: `editor port=9888 tools=154 … tool count actual=154 expected_for_editor=91`
and `game port=9889 tools=73 … expected_for_game=53`. The cause was not the registry. The script
reads six manifests and **two were absent from this tree**:

| manifest | before | after | recorded fingerprint |
|---|---|---|---|
| `docs/tool-groups-b5.json` | absent | 12 012 B → 12 005 B | 12 209 B, sha `85bb783e…` |
| `docs/tool-groups-added.json` | absent | 8 506 B | 9 478 B, sha `72d0c8ae…` |

Both were recovered from the TASK-078 staging reconstruction of the same paths (nothing
invented). That moved the union to 141/61, still 14 short; the remaining 14 contract tools sit in
**8 b5 groups whose `implemented` flag was still `false`** although all 14 are registered and
live. `work\task087\fix_b5_flags.py` flips exactly those eight
(`editor_navigation_write`, `project_theme_write`, `project_theme_read`, `project_export_read`,
`project_android_read`, `os_android_read`, `os_android_write`,
`running_game_navigation_write`) and no other group; the original bytes are preserved at
`work\task087\tool-groups-b5.json.orig`. The manifest is 12 005 B after the rewrite (12 012 B
before) — the 7-byte delta is JSON re-serialisation only, every group name, tool name and
`scope` is unchanged. The gate then read `implemented_union=154 tools (editor endpoint) / 73
tools (game endpoint)` and **3/3 checks passed**.

**Declared risk:** the flag flip is a *gate-metadata* correction, not a behaviour change. Its
justification is not the manifest itself but the live measurement it is compared against: the
registry serves exactly the 177 contract entries, `154` to an editor and `73` to a game, with
zero leakage in either direction, and both endpoints compare **verbatim** (name / description /
inputSchema) against `docs/tools_list.renamed.json`. Before the flip the gate could not state that
invariant at all.

## E-3. `scripts/gen_renamed_contract.py` / G5 — the shape gate passes; 10 overrides stay missing

| item | value |
|---|---|
| generator | `scripts/gen_renamed_contract.py`, 125 454 B, `GENERATOR_VERSION = "1.22.0"` |
| contract | `docs/tools_list.renamed.json`, 136 641 B, sha256 `368cd3c792916088c09e837a12582cde1252e14f6c9ad02110c97059e641b907` |
| shape gate | **passes**: `count=177`, `added_count=6`, `generator_version=1.22.0`, 177 tool entries, editor-visible **154** / game-visible **73** (rename map 174 entries: 47 `both` + 103 `editor` + 24 `game`; `+6 ADDED_TOOLS` → 50 `both`, 104 `editor`, 23 `game` ⇒ 154 / 73), and **idempotent**: two consecutive `python gen_renamed_contract.py` runs both exit 0 and leave the same 136 641 B / same sha256. The generator's own self-checks report `lint 177/177, unique 177/177, disposition enum OK`. |
| recorded artefact | `docs/reports/evidence/task076/contract_fingerprint.txt`: **163 520 B**, sha256 `a5c59853c1e5a4913d600c663c8e972f058f7144869ec20337ab41b7a7bb17ea`, `_meta.overrides = 36`, generator 1.22.0 |
| diff, as measured | **27 879 bytes smaller** (136 641 vs 163 520), `_meta.overrides` **26 vs 36**, all other meta scalars equal (`count 177`, `added_count 6`, `generator_version 1.22.0`, `tool_count_in 174`, `excluded [navigate_to, export_project]`, `merged 1`). The rename-map sha256 the generator prints is `2f552719…` — **identical** to the pinned fingerprint, so the name/scope input is right. |
| what could NOT be replayed, and why | the 10 missing `_meta.overrides` records. Their **names are not in this tree's evidence**: `contract_fingerprint.txt` pins only the array's *length* (36), and there is **no recorded whole-file write of the contract** (`events-write.jsonl` has 0 rows for `docs/tools_list.renamed.json`). `runtime\work\task087\ovkeys.py` harvested every tool-name token near an `overrides` mention across `events-termdump`, `gen-runs`, `events-diff` and `events-termfile` — 109 distinct tokens, all of them names that the **already-present** 26 overrides cover or names from unrelated reports, so no 10-missing set can be identified with evidence. **No override was invented.** |
| second candidate, rejected | the TASK-078 staging body `staging\modules\mcp_server\scripts\gen_renamed_contract.py` (118 449 B) is the **read-epoch of an older generation**: `GENERATOR_VERSION = "1.3.0"`, 9 `DESCRIPTION_OVERRIDES` + 13 `SCHEMA_OVERRIDES` (with `play_scene` duplicated). The tree generator is a strict superset of it (14 + 12, every staging key present), so nothing was gained by swapping. `reconstruction.jsonl` already marked it `"SWAPPED_BY_SYNTAX_CHECK"`, `"conf": "low"`, `"DOWNGRADED_TO_LOW(47 failed edits)"`. |
| a second, independent reason the sha cannot match | `_meta.map_path` is the **absolute path of the working tree**: the pinned contract records the recorded build root `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\tool-rename-map.json`, while this tree writes `H:\rebuild\godot\modules\mcp_server\docs\tool-rename-map.json`. That field alone is 24 bytes shorter *and* makes a byte-identical regeneration impossible by construction, whatever the overrides do. |
| marker | no code marker is needed (nothing was written into the generator); the shortfall is declared here |
| behaviour risk | **none for the gate.** The shape gate is defined on `count` / `added_count` / `generator_version` / the editor-game split / idempotency, and all five hold. The risk is *provenance*: the contract cannot yet be shown to be the byte image the task076 audit pinned, because 10 override records (≈7.4 KB by their mean entry size) and the environment-dependent `map_path` account for the measured 27 879 B gap. |

---

# REBUILT-2C MANIFEST — 2c-7 (`H:\rebuild\godot`, branch `feature/mcp-server-module-rebuild`)

* Task: TASK-088 — the mono axis, the acceptance battery, the contract's missing
  override records, and the traceability capability.
* Start HEAD: `675df5ef27`. Method unchanged: recorded text is replayed at its
  recorded position; anything written instead is wrapped in
  `[REBUILT-2C low-confidence: verify] … [/REBUILT-2C]` in the file and listed
  below with its basis and its behaviour risk.
* Tooling: `C:\Users\wyl\AppData\Local\Temp\mcp-recovery\work\task088\`
  (`ev.py`, `recon_sk.py`, `cov.py`, `ovdiff.py`, `cmp_live.py`, `meta6.py`,
  `add_overrides.py`, `patch_accept_m1.py`, `del_stale_objs.py`, `cov.py`,
  `verify_gen_expr.py`, `find_map_path2.py`, `mk_csharp_proj.py`,
  `mcp088_live_evidence.ps1`).

## G-1. A correction to the 2c-6 section: `seq=1030` is not unique

The 2c-6 section says case0's recorded text is `events-edit seq=1030
t=1790321324515`, and the 2c-6 batch's graft failed with 17 parse errors. The
cause is now measured: **`seq` is only unique inside one session file**, and
TWO rows carry `seq=1030`:

| `seq` | `time` | path | what it is |
|---|---|---|---|
| 1030 | 1790155671555 | `tools/editor_shader_write.h` | a C++ comment rewrite |
| 1030 | 1790321324515 | `scripts/accept_m1.ps1` | the block that adds `case0_repo_exit_code_propagation` |

The 2c-6 graft took the `editor_shader_write.h` row (a C++ banner) and spliced it
into the `.ps1` — which is why the graft could not parse, and why the all-windows
union carried `editor_shader_write.cpp`'s banner at line 556. Selecting on
`(path, seq, time)` yields the correct text, which replays cleanly.
**Ruling: the 2c-6 "not rebuilt" entry for case0 is superseded; case0 is
replayed verbatim in this batch** (`work/task088/patch_accept_m1.py`).

## G-2. Written (marked), with basis and risk

| # | file | what was written | why it could not be replayed | basis | behaviour risk |
|---|---|---|---|---|---|
| 1 | `mcp_jsonrpc.cpp` | `dispatch`: `trace.id_json = id_json; trace.method = method;`; `_dispatch_tools_call`: `r_trace.tool = tool_name;`; the `tools/list` branch: `trace.is_tools_list = true; trace.tool_count = get_visible_tool_count(...)` | TASK-085 ruling (C) already recorded that `dispatch` is written, not replayed: the only recorded definition (rev388:311) takes four parameters and predates the trace, so no recording carries these lines | **measured defect**: a real session (`live/trace-editor.jsonl`) produced call lines with `"method":""`, `"id":null`, no `tool`, no `args`, while the capture line beside them named the tool. The field list and the read conditions are fixed by `mcp_trace.h:132-182` and `mcp_trace.cpp:322-346` | **none on the wire** — the four fields feed the trace line only (`Recorder::_build_line`); a process with `--mcp-trace` off builds no line at all. Risk is that a trace-consuming test asserts an exact line; the module suite was re-run green (G-5) |
| 2 | `scripts/gen_renamed_contract.py` | six `DESCRIPTION_OVERRIDES` records (`validate_script`, `reload_plugin`, `set_input_action`, `add_autoload`, `remove_autoload`, `set_project_setting`), each `value` = the text the server publishes; `play_scene`'s `value` replaced with the published text; `RECORDED_MAP_PATH` and `_meta.map_path` switched to it | the recordings carry no contract body; `events-write` has 0 rows for `docs/tools_list.renamed.json`, so the records could not be replayed | **measured**: the live 154-tool `tools/list` body (`live/editor-tools-list.json`) compared against the contract leaves exactly 10 disagreeing tools (7 descriptions, 3 inputSchemas); `work/task088/cmp_editor.txt` holds every pair. The 6 appended texts are `<contract text> + " " + …` (verified), the shared 400-byte sentence is the recorded TASK-043 constant (`scripts/mcp043_description_evidence.ps1:50`) and the same sentence stands verbatim in the five C++ literals. `RECORDED_MAP_PATH` is replayed from `events-termdump.jsonl` (nine rows, e.g. 228/569/1127) next to the same `map_sha256` this tree has | **medium, declared**: the 7 descriptions now match the wire byte for byte; the 3 inputSchema disagreements were left alone (see G-3). `_meta.overrides` 26 → 32; the pinned 36 is NOT reached and the 4-record shortfall is declared, not invented |
| 3 | `scripts/accept_m1.ps1` | (a) `Compare-ToolListToFixture` rewritten to take the per-endpoint expectation and compare **every** tool's name + description verbatim, plus the name set in both directions; (b) `Get-EndpointExpectation` derives editor/game from the 6 manifests + rename map and cross-checks the union against the contract count; (c) `case1`'s `tools == 2` → the derived count; (d) `guard_user_port_9877` inverted to the 9877-retired invariant; (e) `case0`/`case20` replayed; (f) `case20`'s `$ToolNames.Count` → the derived count | (a)–(d) are positively-wrong M1-era expectations with a recorded later generation on the other side; (e) is recorded text; (f) is the same stale literal as (c) | **measured**: `editor=154, game=73, implemented union=177` is what the derivation prints and what the live registry serves; the 9877 guard's `pid_before=-1 pid_after=-1` is the measured fact. The two cases replay `events-edit seq=858` (t=1790015088330, `old`→`new` = 240→3061 B) and `seq=1030` (t=1790321324515, 77→1998 B) | **none for the gate**: it went 16/20 → 19/22 → **22/22**, and no assertion was deleted — the comparison got *wider*. A declared `inputSchema` deviation is honoured only when it really differs (G-3) |
| 4 | `docs/scripts/_tmp_gen_b3_b5.py` | the stale literal `(171 entries)` and the same literal in `source.excluded` are now derived (`% len(contract_names)`) | the file is a `_tmp_` scratch generator kept as evidence; the literal is prose in a `source` dict | **measured**: the two expressions evaluated against the real contract print `177` and no scanned number remains on either line (`work/task088/verify_gen_expr.txt`, RESULT: PASS) | **none**: `check_hardcoded_counts.py` 1 unclassified line → **0**. The generator itself cannot run end to end today (its SPEC predates the six ADDED_TOOLS) — pre-existing, and the repaired lines are unit-tested directly instead |
| 5 | `scripts/mcp_trace_ledger.py` | **new**: one traceability row per tool call (id / tool / args / start+end / duration / result / capture verdict / pixel diff / declared file-side gap) | new file, nothing to replay | the field model comes from `mcp_trace.h`/`mcp_capture.h` and is stated in `docs/reports/MCP-TRACEABILITY.md` | **none**: read-only reader; not in any gate's scan path except `check_hardcoded_counts.py`, which it passes |
| 6 | `docs/reports/MCP-TRACEABILITY.md` | **new**: the traceability model, the verdict rules, the failure taxonomy, and the live-demo paths | new document | the live session of G-4 | **none**: documentation |

## G-3. The three `inputSchema` disagreements are NOT missing records

The 2c-6 section expected the pinned `_meta.overrides = 36` to be explained by 10
missing records. The measured comparison gives 10 *disagreeing tools*, but they
are not 10 missing records:

* 7 descriptions → 6 new records + 1 existing record (`play_scene`) whose value
  was an earlier revision of the same rewrite. `_meta.overrides` therefore moves
  26 → **32**, not 36.
* 3 inputSchemas (`simulate_sequence`, `find_signal_connections`,
  `get_test_report`) → the generator **already** declares all three as
  `SCHEMA_OVERRIDES`, i.e. the contract deliberately carries a schema the
  implementation does not publish. The C++ confirms it: the rich event-item
  schema of `editor_simulate_input_sequence` appears in no `.cpp`
  (`grep 可粘贴样例 tools/*.cpp` = 0 hits).

So `accept_m1`'s widened comparison excuses an `inputSchema` disagreement **only**
when the contract itself declares an override of kind `inputSchema` for that
tool, and it prints how many were honoured. Measured on the editor endpoint:
**3**, named in the evidence line. The exclusion list is read out of
`_meta.overrides`, not hand-written, so it cannot grow silently.

**Declared risk:** the contract is *richer* than the implementation for those
three tools. That is the contract's own declared deviation and was left as it
is; making the implementation publish the richer schema is the opposite
direction and is **not** done here.

## G-4. Live traceability session (item 5 evidence)

`work/task088/mcp088_live_evidence.ps1`, windowed (a headless process has no
framebuffer and every capture would be `unavailable`). Editor on 9888, game on
9889, both with `--mcp-trace` + `--mcp-capture=every_call` +
`--mcp-capture-dir` (absolute) and `--mcp-capture-viewport=2d`.

| artefact | path (under `work/task088/live/`) | measured |
|---|---|---|
| editor trace | `trace-editor.jsonl` | 10 lines |
| game trace | `trace-game.jsonl` | 7 lines |
| editor shots | `shots-editor/` | 8 PNG, 78 036 B each, 2978×1793 (full raster, `scale=1`) |
| game shots | `shots-game/` | 6 PNG, 12 266 B each |
| editor `tools/list` body | `editor-tools-list.json` | 46 810 B, 154 tools |
| ledger | `ledger-editor.txt` / `.json` | produced by `scripts/mcp_trace_ledger.py` |

## G-5. Route notes worth keeping

* **`Start-Process -Wait` waits for the descendant tree.** MSBuild keeps reuse
  nodes alive for 15 minutes after a successful build, so a *finished*
  `build_assemblies.py` looked hung (0 CPU, log not growing). It was stopped on
  that misreading and then re-run to completion (exit 0, 50.7 s). All task-088
  launchers now use `WaitForExit()` — wait for `cmd.exe` only.
* **`%ERRORLEVEL%` in one `cmd /c` line is expanded at parse time**, so every
  gate echoed `[exitcode]=0` regardless. The launchers now run `cmd /v:on /c`
  and echo `!ERRORLEVEL!`.
* **PowerShell 5.1 mangles embedded quotes in native arguments.** Passing a JSON
  string to `curl.exe --data-binary` produced `-32700 Parse error` on every
  call; the body now goes through a file (`@file`).

## G-6. Gate ledger (task-088, real output)

All nine gates green. The doctests and the anchor verdict were re-taken **after**
the batch was committed, on a mono binary rebuilt at the new HEAD
(`e4b025519a`), so the anchor is `ANCHOR_EQUAL` and not
`STRUCTURAL_EQUIVALENT`:

| # | gate | command | result |
|---|---|---|---|
| 1 | module doctest | `bin\godot.windows.editor.x86_64.mono.console.exe --headless --test --test-case=[MCPServer]*` | **exit 0** — `143 / 143 passed / 0 failed`, `6396 / 6396` assertions, `SUCCESS!` |
| 2 | full engine doctest | the same binary, `--headless --test` | **exit 0** — `1569 / 1569 passed / 0 failed / 3 skipped`, `430709 / 430709` assertions, `SUCCESS!` |
| 3 | group manifest | `docs/scripts/check_tool_groups.py` | **exit 0** — `TOOL-GROUPS CHECK PASS`, 5681 B, sha `b83d79d3…` |
| 4 | contract subset (live) | `scripts/check_contract_subset.ps1` | **exit 0** — `3/3 checks passed`; editor 9888 `tools=154`, game 9889 `tools=73`, `guard_user_port_9877` PASS; `implemented_union=154 / 73` |
| 5 | rename map | `docs/scripts/check_rename_map.py` | **exit 0** — `RESULT: PASS (all checks green)`; `177 == 174 - 2 - 1 + 6` |
| 6 | tautologies | `scripts/check_tautologies.py` | **exit 0** — `TAUTOLOGY CHECK PASS` |
| 7 | exit-code propagation | `scripts/check_exit_propagation.py --probes` | **exit 0** — `PROBES: 10/10` |
| 8 | hardcoded counts | `scripts/check_hardcoded_counts.py` | **exit 0** — `UNCLASSIFIED = 0` (**was the one red gate**) |
| 9 | engine anchor | `scripts/check_engine_anchor.ps1 -VersionText '4.8.dev.mono.custom_build.e4b025519'` | **exit 0** — `VERDICT=ANCHOR_EQUAL  ANCHOR=e4b025519  HEAD=e4b025519  RESULT PASS` |
| + | M1 acceptance | `scripts/accept_m1.ps1` | **exit 0** — `22/22 cases passed` (**was 16/20**) |
| + | traceability demo | `mcp088_live_evidence.ps1` + `scripts/mcp_trace_ledger.py` | editor `calls=4`, `ok_effect_observed=1 / ok_no_effect_observed=3`, `facts_complete 4/4` |

**The plain (non-mono) binary is NOT at HEAD.** `check_engine_anchor.ps1
-VersionText '4.8.dev.custom_build.75d86665e'` answers
`ANCHOR_STALE_COMPILED` with exactly one red file,
`modules/mcp_server/tests/test_mcp_server.h`. That binary was left as it was
(rebuilding it is a second full non-mono build); the *test* evidence for HEAD is
therefore the mono binary of gates 1/2, and the `accept_m1` / contract-subset
evidence describes HEAD's served registry because the only compile input that
differs is the test header.

## G-7. Iron rules

* Only `H:\rebuild\godot` and `C:\Users\wyl\AppData\Local\Temp\mcp-recovery\`
  were written. The gates' own scratch went to
  `…\mcp-recovery\tmp\` because `TEMP`/`TMP` were pointed there for those runs.
* `F:` was **never** written. `DECISIONS.md` 537 251 B sha
  `114B2A8218E35DF8E998FA4329D99F97D6037987E19FBA4A324B567C009CF323` and
  `tests\fixtures\mcp\tools_list.json` 48 749 B sha
  `8F8051C4C0F8941089F0B21A193CEF7C51FA7C41D7E312B1463EA8593F313C54` are
  byte-identical to the pre-flight values (the fixture is the generator's input
  and was only read).
* No shell redirection anywhere: every log is written by
  `Start-Process -RedirectStandardOutput/-RedirectStandardError`, every text file
  by `Set-Content`, `-NoNewline`, `Out-File`-free Python, or the `write` tool.
* Destructive commands: one guarded deletion ran
  (`work/task088/del_stale_objs.py` — three absolute paths under the single
  whitelisted prefix `H:\rebuild\godot\bin\obj\`, the exact four paths the
  tracked `mcp057_build_mono.cmd` names, manifest printed before removal, dry run
  first, no wildcard and no `..`). Nothing else was removed, moved or renamed.
* Builds and engine runs start from `cmd.exe` (iron rule 4): `scons_run.ps1`,
  `run_mono.ps1`, `run_cmd.ps1`, all with `WaitForExit()` and `/v:on`.

---

# REBUILT-2C MANIFEST — 2c-8 (`H:\rebuild\godot`, branch `feature/mcp-server-module-rebuild`)

* Task: TASK-089 — (A) close the one remaining gap in the traceability model
  (file-side side effects on the call line), (B) the round-7 test loop against a
  real mini game project, (C) the nine gates again.
* Start HEAD: `6b4c29dc81`. Method unchanged: recorded text is replayed at its
  recorded position; anything written instead is wrapped in
  `[REBUILT-2C low-confidence: verify] … [/REBUILT-2C]` in the file and listed
  below with its basis and its behaviour risk.
* Tooling: `C:\Users\wyl\AppData\Local\Temp\mcp-recovery\work\task089\`
  (`run_gates.ps1`, `task089_build_mono.cmd`, `task089_gate1_module.cmd`,
  `task089_gate2_full.cmd`, `patch_capture.py`, `mcp089_live_evidence.ps1`,
  `mk_miniproject.py`, `ledger_report.py`); the guards of 2c-7 are reused
  verbatim (`work/task088/del_stale_objs.py`).

## H-1. Written (marked): the call line gains the file-side half

| # | file | what was written | basis | behaviour risk |
|---|---|---|---|---|
| 1 | `mcp_trace.h` | `MCPTrace::Record` gains `Array file_effects` and `String file_effect_status` | the two fields the traceability model declared as missing (`MCP-TRACEABILITY.md` §3.2, `file_effect_evidence: "not_recorded_in_trace"`). Nothing to replay: the recorded `mcp_trace.h` predates any file-side field | **none on the wire** — the fields only reach `Recorder::_build_line` |
| 2 | `mcp_trace.cpp` | `_build_line`: inside the existing `method == "tools/call"` block, emit `file_effect_status` + `file_effects` when the status is non-empty | the fields belong on the **call line**, at the same level as `id`/`method`/`tool`, which is the object this function builds | **none**: with `--mcp-trace` off no line is built; an older trace has neither field and the ledger reads that as `not_recorded` |
| 3 | `mcp_jsonrpc.cpp` | (a) `_dispatch_tools_call`: `MCPFileEffect::begin_recording()` before `call_tool` and `end_recording()` + `take_effects()` + `status_name()` after, both guarded by `r_trace.traceable`; (b) the deferred branch sets `file_effect_status = "not_tracked_deferred"` | the one place a tool is really invoked. A deferred tool is ticked after this function returned, so its disk work is not observable here and is named as such instead of being reported as "no mutation" | **none on tool behaviour**; the recorder is inert unless the switch is on. Risk: an extra `Array` copy per traced `tools/call` |
| 4 | `mcp_file_effects.{h,cpp}` | **new**: `MCPFileEffect` — a per-call buffer plus the `MutationScope` a mutating primitive opens around itself (absolute path, sha256 + byte count before and after, `changed`, `kind` = `write`/`delete`/`mkdir`, and a bounded head/tail line difference for small text destinations) | new files, nothing to replay | **none**: unused unless a trace is on; large files are never read, only hashed |

## H-2. Written (marked): where the one recorder is opened

| # | file | what was written | basis | behaviour risk |
|---|---|---|---|---|
| 1 | `tools/tool_helpers.cpp` | `publish_file_atomically()` opens one `MutationScope` (this is the module's single publish primitive — the editor/scene/resource/script/shader/theme/project-settings/screenshot/test-report writers all reach disk through it); the section arm of `publish_project_setting_to()` opens one too (the engine's own `save_custom_section()` bypasses the primitive); `_ensure_user_data_directory()` opens one with `kind=mkdir` | this is the "one place" the task asks for: no writing group computes a hash and no writing group can forget to. The four sites left are the ones that touch disk **without** the primitive | **none on the file contents**: the scope only observes. Risk: three extra `stat` + one `sha256` per publish while tracing |
| 2 | `tools/project_write_resource_scene.cpp` | `project_delete_scene_file` opens a `MutationScope(kind="delete")` for the scene and for its `.import` sidecar | a deletion is a file mutation and does not go through the publish primitive | **none** |
| 3 | `tools/csharp_verdict.cpp` | `write_csharp_build_record` opens one **before** `FileAccess::open(..., WRITE)` (that call truncates on open, so a later snapshot would describe the truncated file) | the build record is written directly to `user://` | **none** |
| 4 | `tools/editor_testing_read.cpp` | `editor_get_test_report`'s `clear` arm opens one for the bridge-file removal | direct `DirAccess::remove_absolute` | **none** |
| 5 | `tools/project_cross_scene_write.cpp` | both rollback loops (a failed publish, a refused live edit) open one per restored file | a rollback restore writes a destination directly; without it a failed batch call would look like "no mutation" | **none** |

**Declared coverage boundary:** the recorder is opened at disk-mutating
primitives, not per tool. A tool that mutates purely in memory (an editor node
property, an InputMap action before it is published) records `no_mutation`
unless it also publishes a file — that is the intended reading, and the ledger's
`file_effect` column says `none` rather than implying the call did nothing.

## H-3. Written (marked): the reader and the tests

| # | file | what was written | basis | behaviour risk |
|---|---|---|---|---|
| 1 | `scripts/mcp_trace_ledger.py` | `file_effect` is derived from the call line (`changed` / `unchanged` / `mixed` / `none` / `not_recorded` / `not_tracked`); a new verdict `ok_file_effect_observed` when the file side really changed; `file_effect` added to the reconstructible-`FACTS` set; a `file_effect` column in the text table | the reader half of H-1/H-2. The old fixed value `file_effect_evidence: "not_recorded_in_trace"` was the declared gap and is now read off the trace | **none**: read-only. `check_hardcoded_counts.py` scans it and passes |
| 2 | `tests/test_mcp_server.h` | four cases: the recorder is inert with no trace; a create / a real rewrite / a same-content rewrite are told apart (including the head/tail summary); a deleting tool is recorded through the same hook; the rows are emitted on the call line at the top level | the recorder had no test at all (`MCPTrace` had none either) | **none**: the cases create and remove their own `res://mcp_server_file_effect_fixture` tree |

## H-4. Route notes worth keeping

* `bin\obj` is shared between the plain and the mono variant, and scons keeps no
  dependency edge from `tests/test_mcp_server.h` to its object, so
  `del_stale_objs.py --apply` (dry run first) ran before every build — 3 present,
  1 absent, both times.
* `scons platform=windows target=editor module_mono_enabled=yes tests=yes -j8 -k`
  takes ~37-42 s incrementally here.
* `Start-Process -PassThru` on a redirected `cmd.exe` does **not** always expose
  `$p.ExitCode` in this PowerShell (it came back empty for every child), so the
  gate runner echoes `%ERRORLEVEL%` **inside** the cmd child and parses that line.
  This is the same class of trap as 2c-7's G-5 notes.

## H-5. The round-7 test loop: the defect list (the round's main product)

A real mini game project (`H:\rebuild\projects\mcpplay`) was driven over both
endpoints with the trace and the every-call capture on: 30 calls on the editor
(9888) and 15 on the game (9889), every tool family with at least one call that
must take effect and one that must not or must be refused. Full artefacts in
`work/task089/live-{before,after}\`; the ledger is
`live-after/ledger-{editor,game}.{txt,json}`.

| # | tool | evidence | root cause | disposition |
|---|---|---|---|---|
| D-1 | `running_game_execute_gdscript` | `-32602 "Parameter 'code' does not compile: Parse error"` for **all three** bodies (`live-before/g0{3,4,5}-*.json`); the engine's own reason was only on stderr (`logs/task089_live_game.stderr.txt:1-2`: `Parse Error: Function "get_node()" not found in base self.` at `gdscript://…:4`) | the game group carried its own `_build_source` + a bare `Script::reload()`, so the parser diagnostic was discarded; `editor_execute_gdscript` already used `reload_gdscript_capturing` + `gdscript_reload_failure_text`. One parse error, two descriptions | **fixed** (F1) |
| D-2 | `project_create_script` | the same file written twice answered `{"created": true, "existed_before": true}` (`live-before/e08-create-script-again.json`; trace-editor seq=8 id=108) — one response contradicting itself | `out["created"] = true;` is a constant, while the two sibling text writers (`project_text_write.cpp:196`, `project_setting_write.cpp:237`) answer `created = !existed` | **fixed** (F3) |
| D-3 | `running_game_execute_gdscript` (capability) | a body cannot reach the running scene at all: `self` is a bare `extends RefCounted`, so `get_node()` / `$Path` fail — only global singletons work. The published description ("在运行中的游戏内执行 GDScript 代码") does not say so | design question (what should `self` be?), no single root cause | **recorded, not changed** |
| D-4 | `tool_helpers.h` | `build_execute_gdscript_source` and `execute_gdscript_method_name` are declared **twice**: inside `namespace MCPTools` (1137 / 1112) and again after the namespace closes (1531 / 1513). A file with `using namespace MCPTools;` gets MSVC **C2668 ambiguous call** (measured: `logs/task089_build_fixes.err.log`) | a duplicated block outside the namespace | **worked around** with `MCPTools::` qualification; the stray declarations were **not** removed (header change, outside this task's evidence) |
| D-5 | the four assertion tools | every assertion call rewrites `user://mcp_test_report.json` (game ledger seq 9-12, `file_effect=changed`, absolute path and the growing `{"results":[…]}` diff in the trace) | the editor↔game report bridge | **not a defect** — but it is the reason a "read-only-looking" verdict is `ok_file_effect_observed`; the new `result_flags` column qualifies it |
| D-6 | `editor_set_node_property` | the same value written twice has the same **shape** of answer (`old_value`/`new_value` always present); only the pixel diff tells them apart (trace seq 14 `changed` vs seq 15 `unchanged`) | the answer is honest (it carries both values); the reader must compare | **calibration note**, not a defect |

**Evidence completeness, measured:** `facts_complete` is **30/30** (editor) and
**15/15** (game) in **both** runs. No row had `args_truncated` or
`result_json_truncated`; no capture was `unavailable` (both processes windowed).

## H-6. Written (marked): the fixes the defect list justified

| # | file | what was written | basis | behaviour risk |
|---|---|---|---|---|
| 1 | `tools/running_game_script_execution.cpp` | **F1**: the private `_split_code_lines` / `_space_indent_unit` / `_build_source` and the bare `Script::reload()` are gone; the tool now calls `MCPTools::build_execute_gdscript_source(code, false, …)` and `reload_gdscript_capturing(script, body_start_line)`, answers `gdscript_reload_failure_text(reload)` and fills `data.parse_error` + `data.parse_error_column` exactly as `editor_execute_gdscript` does | D-1. The removed builder was byte-for-byte the same three layout rules as the hoisted one, so a **successful** call compiles the same source; only the refusal changes | **none on success**; the refusal text is now longer and carries a line. Verified: `live-after/g03…` answers `data.parse_error{line:1, generated_line:4, in_caller_code:true, message:"Parse Error: Function \"get_node()\" not found in base self."}` where `live-before/g03…` answered only `"Parse error"` |
| 2 | `tools/project_script_write.cpp` | **F3**: `out["created"] = !existed;` | D-2 | **response shape changes for an existing file** (`created` `true` → `false`). No gate reads a tool response body; the module doctest suite is green (`live`/`record` in H-7) and a new doctest pins it |
| 3 | `mcp_trace.{h,cpp}` + `mcp_jsonrpc.cpp` | **F2**: `Record` gains `result_json` + `result_json_bytes`; `_dispatch_tools_call`'s success arm fills them from the tool's own return value; `_build_line` emits `result_json` (bounded by the same `max_args_bytes` the `args` field uses) + `result_json_bytes` + `result_json_truncated` | the round-7 session measured `ok` responses whose **own body** carried the verdict (`passed:false`) with nothing on the line but `result_bytes` — the trace could not be used to judge an assertion | **trace size grows** (measured: 45 138 → 57 590 B editor, 24 755 → 36 572 B game for the same 45 calls). No tool behaviour changes |
| 4 | `scripts/mcp_trace_ledger.py` | **F2/F3 reader**: `result_flags` (`assertion_failed` / `created_conflict` / `result_unparseable`) and the `result_json*` fields on each row; a `flags` column in the text table | so the two shapes D-2 and the failed assertions are visible without re-reading the client's copy of the body | **none**: read-only; `check_hardcoded_counts.py` passes |
| 5 | `tests/test_mcp_server.h` | a fifth case: `project_create_script` answers `created=false` + `existed_before=true` on the second write, and `bytes` is unchanged | D-2's regression pin | **none** |

**Demonstrated by re-running the same call set** (`work/task089/compare_ledgers.py`):
the verdict distribution is **identical** before and after on both endpoints
(editor `failed=4 / ok_effect_observed=1 / ok_file_effect_observed=10 /
ok_no_effect_observed=15`, game `failed=5 / ok_effect_observed=1 /
ok_file_effect_observed=5 / ok_no_effect_observed=4`), because the fixes change
**what the log can prove**, not what the tools do. What changed:

* `live-after/e08-create-script-again.json` = `{"created": false, "existed_before": true, …}`
  where `live-before/…` was `{"created": true, "existed_before": true, …}`;
* `live-after/g03-execute-gdscript.json` carries the parser's line and message;
* the after-run ledger shows `assertion_failed` on game seq 10/11/12 — the three
  `passed:false` responses the before-run trace could not express.

## H-7. Gate ledger (task-089, real output)

Binary: `bin\godot.windows.editor.x86_64.mono.console.exe`, built at HEAD
`80035ed11` and self-reporting `4.8.dev.mono.custom_build.80035ed11`. Gate runner
`work/task089/run_gates.ps1` (each gate is its own `cmd.exe` child; the exit code
is echoed **inside** the child and parsed, because `$p.ExitCode` came back empty
for every redirected child on this machine). Logs:
`logs/task089_final_g0*.stdout.txt`, summary `logs/task089_final.summary.txt`.

| # | gate | command | result |
|---|---|---|---|
| 1 | module doctest | `--headless --test --test-case=[MCPServer]*` | **exit 0** — `148/148 passed`, `6464/6464` assertions, `SUCCESS!` (was 143/6396 at 2c-7; +5 cases from this batch) |
| 2 | full doctest | `--headless --test` | **exit 0** — `1574/1574 passed / 3 skipped`, `430777/430777` assertions, `SUCCESS!` |
| 3 | group manifests | `python docs\scripts\check_tool_groups.py` | **exit 0** — `TOOL-GROUPS CHECK PASS`, 5681 B, sha `b83d79d3…` |
| 4 | contract subset (live) | `scripts\check_contract_subset.ps1` | **exit 0** — `3/3 checks passed`; editor 9888 `tools=154`, game 9889 `tools=73`, `guard_user_port_9877` PASS |
| 5 | rename map | `python docs\scripts\check_rename_map.py` | **exit 0** — `RESULT: PASS`; `177 == 174 - 2 - 1 + 6` |
| 6 | tautologies | `python scripts\check_tautologies.py` | **exit 0** — `TAUTOLOGY CHECK PASS` |
| 7 | exit-code propagation | `python scripts\check_exit_propagation.py --probes` | **exit 0** — `PROBES: 10/10` |
| 8 | hardcoded counts | `python scripts\check_hardcoded_counts.py` | **exit 0** — `UNCLASSIFIED = 0` |
| 9 | engine anchor | `check_engine_anchor.ps1 -VersionText '4.8.dev.mono.custom_build.80035ed11'` | **exit 0** — `VERDICT=ANCHOR_EQUAL`, `diff_count=0`, `RESULT PASS` |
| + | M1 acceptance | `powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1` | **exit 0** — `22/22 cases passed` (log `logs/task089_accept_m1.stdout.txt`) |
| + | traceability demo | `mcp089_live_evidence.ps1` + `mcp_trace_ledger.py` | editor `calls=30` `facts_complete 30/30`; game `calls=15` `facts_complete 15/15`; counts in §4.2 of `MCP-TRACEABILITY.md` |

**Honest note:** the non-mono binary is **not** rebuilt at this HEAD (it is older
than 2c-7's own, which was already declared); every number above is the mono
binary's, which is the same source. The 2c-7 declaration on this point stands.

## H-8. Iron rules

* Only `H:\rebuild\godot`, `H:\rebuild\projects\` and
  `C:\Users\wyl\AppData\Local\Temp\mcp-recovery\` were written.
* `F:` was **never** written. Pre-flight and post-flight measured **byte-identical**:
  `F:\moonbit-hof-rs\DECISIONS.md` 537 251 B sha
  `114B2A8218E35DF8E998FA4329D99F97D6037987E19FBA4A324B567C009CF323`;
  `F:\moonbit-hof-rs\tests\fixtures\mcp\tools_list.json` 48 749 B sha
  `8F8051C4C0F8941089F0B21A193CEF7C51FA7C41D7E312B1463EA8593F313C54`.
* No shell redirection anywhere: every log is written by
  `Start-Process -RedirectStandardOutput/-RedirectStandardError`, every text file
  by `Set-Content`/`-NoNewline`, a Python writer, or the `write` tool.
* Destructive commands: exactly one guarded deletion ran, four times, before each
  build — `work/task088/del_stale_objs.py --apply`: absolute paths only, under the
  single whitelisted prefix `H:\rebuild\godot\bin\obj\`, the exact four paths the
  tracked `mcp057_build_mono.cmd` names, the manifest printed before removal, a
  dry run first, no wildcard and no `..` (3 present, 1 absent each time).
* Builds and engine runs start from `cmd.exe` (iron rule 4), with `WaitForExit()`.

---

# REBUILT-2C MANIFEST — 2c-9 (`H:\rebuild\godot`, branch `feature/mcp-server-module-rebuild`)

* Task: TASK-090 — (A) the failure answer's `data` payload on the call line,
  (B) the D-3 ruling: the game-side executor must reach the running scene tree,
  (C) the round-8 test loop against a purpose-built mini game, (D) the nine gates
  again plus `accept_m1`.
* Start HEAD: `b8e0142b81`. Method unchanged: recorded text is replayed at its
  recorded position; anything written instead is wrapped in
  `[REBUILT-2C low-confidence: verify] … [/REBUILT-2C]` in the file and listed
  below with its basis and its behaviour risk.
* Tooling: `C:\Users\wyl\AppData\Local\Temp\mcp-recovery\work\task090\`
  (`task090_build_mono.cmd`, `task090_gate1_module.cmd`, `mcp090_live_evidence.ps1`,
  `update_contract_description.py`, `analyse_round8.py`, `probe_action.ps1`);
  `work/task089/run_gates.ps1` is reused verbatim as the gate runner.

## J-1. Written (marked): the failure payload on the call line (item A)

| # | file | what was written | basis | behaviour risk |
|---|---|---|---|---|
| 1 | `mcp_trace.h` | `MCPTrace::Record` gains `String error_data_json` and `int error_data_bytes` | the last declared hole of the TASK-089 model: `MCP-TRACEABILITY.md` §3.2 spelled out that `data` (`suggestion` / `parse_error`) never reached the line. Nothing to replay: no recording carries a failure payload | **none on the wire** — the fields only reach `Recorder::_build_line` |
| 2 | `mcp_trace.cpp` | `_build_line`: inside the existing `tools/call` block, emit `error_data_json` + `_bytes` + `_truncated` for **every** failed call (empty string when the tool attached no payload) | the same object the success half (`result_json`) is written into, and the same `max_args_bytes` bound | **none** when `--mcp-trace` is off. Trace size: one extra (usually empty) field per failed call |
| 3 | `mcp_jsonrpc.cpp` | `_record_error_data()` next to `_effective_timeout`; called in the deferred-refusal branch and in the immediate tool-error branch | those are the two places a tool error really becomes an answer; the pre-tool refusals (`-32602` "expected an object" …) carry no `data`, and the field is then still written as `""` | **none**: only reads `MCPToolError::data` |
| 4 | `mcp_http_server.cpp` | `_tick_pending`: the deferred completion writes the same field from `completion.error.data` (empty on `DONE`) | a deferred failure carries the same `data` an immediate one does (`timeout_ms`, a suggestion), and it has to reach the line by the same rule | **none** |
| 5 | `scripts/mcp_trace_ledger.py` | `error_data` / `error_data_evidence` / `error_flags` per row; `error_data` added to the reconstructible-`FACTS` set; a "failure payloads" section in the text report | the reader half. `error_data_evidence` is decidable because a new build writes the field on every failure: present = recorded, absent on a failure = an older trace | **none**: read-only |
| 6 | `tests/test_mcp_server.h` | `[MCPServer] a failed tools/call carries its data payload on the trace line`: a refusal with a suggestion, a body that does not compile (`parse_error` with the line and the message) and a success with no failure payload | the wiring, not just the writer: the three shapes the field has to distinguish | **none**: the case creates and removes its own fixture tree |

## J-2. Written (marked): decision D-3, the executor reaches the running scene tree (item B)

**The ruling.** The generated body is compiled to `extends Node` when the running
game has a reachable scene tree, and the instance is added as the **last child of
the current scene root** (the tree root when no current scene is set) for the
duration of the call, then removed again on every path. The alternatives and why
they lost:

* *inject the scene root into the existing `RefCounted` context* — rejected: it
  cannot deliver the capability. `get_node()` is a `Node` method, so the body
  would still have to spell every access `root.get_node(...)`, i.e. a second
  vocabulary for what the engine already spells `get_node(...)`.
* *attach the generated script to the existing scene root (`set_script`)* —
  rejected: restoring the previous script afterwards rebuilds its script
  instance, so the game's own `_ready`/`_init` state is lost. That is real
  pollution, not a temporary mount.
* *a mount point of our own, removed before control returns* — chosen: one
  `add_child`, one `remove_child`, one delete, on the success path and on both
  failing ones, with the game's tree provably unchanged (round-8 evidence: the
  scene-tree snapshot is byte-identical before the executor batch, right after
  it, and at the end of the session).

**Declared boundary.** The node lives for less than one frame, so `_process` /
`_physics_process` do not tick; `func _ready()` in the body does run (it is
called when the node enters the tree), which is ordinary Godot semantics.
`$Path` / `get_node()` resolve relative to the temporary node, whose parent is
the scene root; absolute paths and `get_tree().current_scene` reach anywhere.
A process with no reachable scene tree keeps the previous `extends RefCounted`
behaviour byte for byte.

| # | file | what was written | basis | behaviour risk |
|---|---|---|---|---|
| 1 | `tools/tool_helpers.h` | `build_execute_gdscript_source()` gains a trailing `bool p_node_base = false`; **and the duplicate declaration block after `namespace MCPTools` is deleted** | the trailing default keeps every existing caller's call site and bytes unchanged; the deleted block is TASK-089's D-4 (two declarations of a function defined inside the namespace, ambiguous for an unqualified call in a file with `using namespace MCPTools;`), which the signature change would otherwise have had to edit a second time | **low**: removing a stale declaration can only break a caller that relied on the global-scope name, and none exists (both callers name `MCPTools::` or are inside the namespace) |
| 2 | `tools/tool_helpers.cpp` | the prelude's base class is `p_node_base ? "Node" : "RefCounted"`; everything else (three layout rules, entry-point name, `body_start_line` arithmetic) untouched | one place decides the base class | **none with the default** |
| 3 | `tools/running_game_script_execution.{h,cpp}` | the tool body is split into `execute_gdscript_code(code, tool_script, mount_point, error)` (exported for the doctest) plus the argument half; the mounted path `memnew(Node)` + `set_script` + `add_child` + call + `remove_child` + delete, with a `queue_free`-aware delete and a single cleanup before the call-error return | the cleanup must be unconditional, and the doctest binary has no `SceneTree`, so the mount point has to be an argument | **the intended change**: a body now runs as an in-tree `Node`. A call that relied on `self` being a `RefCounted` (or on `get_node()` *failing*) changes; every existing success shape (`{"result","result_type"}`, singletons, statements, lifted `func`s) is unchanged, pinned by the TASK-010 doctest |
| 4 | `tools/running_game_script_execution.cpp` (generated span) | re-emitted by `scripts/gen_b2_game_schema.py --group running_game_script_execution --in-place` after the contract description changed | the generated span is the byte-exact copy of `docs/tools_list.renamed.json`; re-running the generator is a no-op (measured) | **none** |
| 5 | `docs/tools_list.renamed.json` | the `running_game_execute_gdscript` description now states the scene-tree reach, the path basis and the lifetime boundary | the contract must say what the tool really does; the old text promised "execute GDScript in the running game" without the boundary | **none**: one JSON string; the rewrite script asserts one changed line and a byte-exact round trip elsewhere |
| 6 | `tests/test_mcp_server.h` | `[MCPServer] running_game_execute_gdscript reaches a live scene tree and leaves it alone`: a hand-built scene root + child, read of the child's property through `get_parent().get_node(...)`, a write that lands on the real node, the mount visible from inside (child count 2), the mount gone after the call, a body that does not compile, a body that fails after mounting, and the no-mount-point fallback | the three claims the task makes, decidable in-process; the `run_test_scenario`-style live half is the round-8 session | **none**: the case builds and frees its own node tree |
| 7 | `tests/test_mcp_server.h` | the pinned description literal of the `running_game_script_execution` group case is updated to the new text | that case compares the live `tools/list` entry against the contract | **none** |

## J-3. Written (marked): the round-8 defects, and the ones that were fixed

See the round-8 defect list in the task report and in §H-5's successor (the
session's own artefacts). The three fixes land in:

| # | file | what was written | basis | behaviour risk |
|---|---|---|---|---|
| 1 | `tools/running_game_test_execution.cpp` | an `input` step's result entry gains `action` + `in_input_map` | round-8 defect: the injected `mcp_right` action never moved the player. Root cause (probe + engine source): the event *is* delivered to `_input`, but `InputEvent::is_action_pressed` resolves through `InputMap::event_get_action_status`, which returns false for an action the InputMap does not declare (`core/input/input_map.cpp:291-292`). `editor_simulate_input_action` already answers `in_input_map` for exactly this reason, so the game-side step was the inconsistent one | **additive** in the result body; no schema, no existing key changed |
| 2 | `scripts/mcp_trace_ledger.py` | `result_flags` also reads a scenario summary: `scenario_passed` / `scenario_assertion_failed` / `scenario_errors` / `scenario_asserted_nothing` | round-8 defect: `running_game_run_test_scenario` answers `all_passed` / `passed` / `failed` / `errors` and nests a verdict per step, so the ledger could not answer "did the scenario's assertions hold" | **none**: read-only |
| 3 | `H:\rebuild\projects\mcpplay8` (outside the repo) | the project declares `mcp_right` in its InputMap in `_ready()` | the harness half of defect 1: the tool cannot declare a game's actions, and the game must for `is_action_pressed` to see them | n/a (test project) |

**Not fixed, by design** (declared, with the measured numbers): the capture's
`changed_pixels` uses `max(|dr|,|dg|,|db|) > 10` (`mcp_capture.cpp:68`), so an
independent recomputation that counts *any* difference disagrees with it on a
text change (1464 vs 1363 for game `seq=8`); with the engine's own rule the
recomputation reproduces all 28 pairs exactly. The deferred channel's
`scene_effect=unavailable` / `file_effect=not_tracked` is the declared boundary
and is why `facts_complete` is 28/30 on the game endpoint.


