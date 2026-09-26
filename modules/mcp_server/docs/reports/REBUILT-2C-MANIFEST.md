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
