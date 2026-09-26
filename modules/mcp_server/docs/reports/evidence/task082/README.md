# TASK-082 evidence — "advance the rebuild tree to buildable" (2c-1)

Branch `feature/mcp-server-module-rebuild`, work tree `H:\rebuild\godot`.
This directory is the raw evidence behind `TASK-082-2C1-REPORT.md` (kept outside the
tree, in `%TEMP%\mcp-recovery\`).  Nothing here is a summary: every claim in the
report can be re-derived from these files.

## Files

| file | what it is |
|---|---|
| `item1-promoted-lowconf.txt` | the 13 low-confidence sources promoted in commit ①: path, source, bytes, sha256, read-coverage confidence, failed-edit count, a suspicious-feature scan and the last 80 bytes of each file |
| `item3-contract-regeneration.txt` | full stdout of the two generator runs (idempotence) plus the count / endpoint / override checks and the sha comparison against `a5c59853…` |
| `build1-tests-yes.stdout.txt` / `.stderr.txt` | `scons platform=windows target=editor tests=yes -j8` (aborted after 22 s) |
| `build2-tests-no.stdout.txt` / `.stderr.txt` | `scons platform=windows target=editor tests=no -j8` (aborted after 188 s) |
| `build3-keepgoing.stdout.txt` / `.stderr.txt` | `scons platform=windows target=editor tests=no -j8 -k` (keep going, 635 s) — the authoritative error inventory |
| `item4-build3-errors-summary.txt` | build 3 errors grouped by owning file, with the error-code histogram, the 38 failing targets and the first 12 error lines of every module file |
| `item4-truncation-classes.txt` | structural scan of all 172 module `.cpp`/`.h` (head / tail / unterminated-literal / brace-delta classes) |

The `.stderr.txt` files were produced by `cl.exe` under a non-UTF-8 console code page
and were re-encoded from `cp936` to UTF-8 unchanged apart from the newlines; MSVC's own
message text contains a few bytes that are not valid `cp936` and show as U+FFFD.  The
diagnostic codes and the file:line prefixes are ASCII and are intact.

## Build matrix

| run | command | exit | elapsed | result |
|---|---|---|---|---|
| 1 | `scons platform=windows target=editor tests=yes -j8` | non-zero | 22 s | stopped in `tests/test_main.cpp`: 8 × `C2248` in the 09-22 fossil `modules/mcp_server/tests/test_mcp_server.h` (lines 1253, 1270, 1283, 1298, 1309, 1327, 1352, 1390) |
| 2 | `scons platform=windows target=editor tests=no -j8` | non-zero | 188 s | stopped in `modules/mcp_server/mcp_server.cpp`: 109 errors from **line 4**. The module sources were the first thing to fail; `bin\obj\core\core.windows.editor.x86_64.lib` was produced fine |
| 3 | `scons platform=windows target=editor tests=no -j8 -k` | non-zero | 635 s | **1,575 error lines, 48 files, 38 failing targets — all 38 are inside `modules/mcp_server`** |

`module_mono_enabled=yes` was **not** attempted: the module does not compile without it,
so a Mono run could only re-report the same errors while costing a full second build.
That decision is recorded in the report.

## What build 3 proves

* The **engine itself is healthy**: `core` and `thirdparty` linked into static libraries,
  and every one of the 38 failing targets is a `modules/mcp_server/**` object.
* **1,348 errors are attributed to module files** and 227 to engine headers
  (`core/object/object.h` 132, `core/io/resource.h` 40, `core/object/method_info.h` 20,
  `core/object/property_info.h` 16, `scene/main/node.h` 15,
  `core/extension/gdextension_interface.gen.h` 4).  Those 227 are **cascades**, not
  engine defects: they are reported inside translation units whose brace / namespace
  state was already broken by a module header, which is why `core/object/object.h`
  complains about `MCPTools::String` while the same header parses cleanly everywhere else
  in the build.
* Error-code histogram: `C2065` 316, `C4430` 198, `C3861` 167, `C2143` 161, `C2059` 111,
  `C2653` 73, `C2146` 63, `C3646` 58, `C2447` 55, `C2825` 32, `C2510` 32, `C2601` 30 …
  `C2267` / `C2601` ("block-scope function definition is illegal" / "local function
  definitions are illegal") and `C2870` ("a namespace definition must appear at file
  scope") appear only when a `{` or a `namespace` was left open earlier in the TU.

## Proven root causes (each has a file:line)

### R1 — three sources lost their HEAD (class A)

| file | bytes | first line of the file | errors |
|---|---:|---|---:|
| `modules/mcp_server/mcp_server.cpp` | 20,934 | `static const int DEFAULT_EDITOR_PORT = 9877;` | 109 (from line 4) |
| `tools/editor_node_read.cpp` | 21,233 | `// ------…` (a banner, no licence, no includes) | 101 (from line 9) |
| `tools/running_game_read_scene.cpp` | 7,665 | `if (p_a.distance != p_b.distance) {` | 106 (from line 1) |

All three fail **before reaching any real code**, so nothing they define is visible to the
rest of the module; `running_game_read_scene.cpp` additionally starts *inside* a
comparator body and ends inside a `for` loop, i.e. it is an interior fragment, not a file.
The other 169 module sources do start with the Godot licence block.

### R2 — five sources lost their TAIL (class B)

`tools/project_write_resource_scene.cpp` (ends mid-comment `// two apart.`),
`tools/running_game_frame_observation.cpp` (ends on `if (!game_framebuffer_available()) {`),
`tools/running_game_node_write.cpp` (ends on `// END generated`),
`tools/running_game_read_scene.cpp` (ends on a `for` header),
`tools/tool_helpers.h` (ends on a bare `//`).

### R3 — one source has an unterminated literal (class C)

`tools/project_validate_scripts.cpp` — the lexer cannot close a string or block comment;
MSVC reports `C1903` / `C3516` there.

### R4 — `tools/project_read_files.h` lost its `namespace MCPTools {` opener

The header has **no `namespace MCPTools {` at all** but closes it:

```
 52: void register_project_read_files_tools(MCPToolRegistry &r_registry);
 53: //   * a server that has `ext`        -> COMPILE: the real `reload()`.
 54: // ---------------------------------------------------------------------------
 55: enum class MCPValidateScriptMode {
…
190: MCPToolError validate_script_verdict_refusal(const String &p_path, const MCPValidateScriptVerdict &p_verdict);
191:
192: } // namespace MCPTools
```

Lines 53-54 are a comment block spliced in from another file, so the damage is a lost
block boundary, not just a lost `namespace`.  The stray `}` at line 192 **closes the
enclosing namespace in every TU that includes this header**, which is exactly the
mechanism behind `C2870`, `C2601` and the engine-header cascades listed above.  This
defect is *not* in the TASK-081 gap list (G1–G12); it is new evidence.

### R5 — nine more sources have well-formed ends but unbalanced braces (class D, suspected)

`tool_registry.cpp` (+3), `tools/editor_input_simulation.cpp` (+2/+2),
`tools/editor_node_batch_write.cpp` (+1), `tools/editor_node_setup.cpp` (−1),
`tools/editor_node_write.cpp` (+6), `tools/editor_write_scene_editor.cpp` (+5),
`tools/project_read_files.h` (−1), `tools/running_game_script_execution.cpp` (−1),
`tools/running_game_test_execution.cpp` (+8).

These carry real errors of their own (`C2267`/`C2601` in `editor_node_batch_write.cpp`
from line 153, `C2196` duplicate `case` labels in `tool_helpers.cpp` from line 254,
`C3861` unresolved `_pending_path_for` / `_pending_path_matches`), so the imbalance is a
*consequence* of the dropped blocks.  Flagged as suspects rather than proven because the
scan's brace counter is approximate around preprocessor conditionals.

### R6 — the test blocker is a fossil, not just damage

`tests/test_mcp_server.h` in the tree is 66,392 B / 1,392 lines (the 09-22 fossil) and
calls `registry.register_tool(...)` directly at 8 sites, while
`tool_registry.h:141` declares `bool register_tool(...)` **private** with
`friend class MCPTools::ToolBuilder` as the only friend (GDR-19 / TASK-003 §1.6).

The `_low-confidence` copy is 431,976 B / 9,626 lines and contains
`RegisterToolAccessProbe` + the `static_assert` that *proves* the method is private, so it
is the right revision for that rule.  It also ends with a block that must **not** be
promoted: lines 9506-9626 are headed

```
// Independent acceptance probes (appended by the acceptance agent for one run,
// then reverted). No assertion here is copied from the shipped tests.
```

and that block calls the private `register_tool` three more times (9535, 9557, 9607).
Promoting the file without dropping lines 9506-9626 would reproduce the same `C2248`
errors.  The shipped file is therefore the `_low-confidence` payload **minus its tail
block** — that subtraction is a reconstruction judgement and needs the decision maker's
sign-off before it is committed.

## Fix plan (ordered — each step is a gate for the next)

**Step 0 — restore the three heads (blocking everything).**
`mcp_server.cpp`, `editor_node_read.cpp`, `running_game_read_scene.cpp` must be complete
files before any other error is meaningful, because 316 of the 1,348 module errors and
most of the cascade come from them.  Donors that exist and were verified present:
`C:\Users\wyl\AppData\Local\Temp\mcp044-module-backup\mcp_server\` holds a **complete**
older revision of all three (`mcp_server.cpp` 25,234 B, `tools/editor_node_read.cpp`
30,008 B, `tools/running_game_read_scene.cpp` 18,213 B) with the licence block, the
include block and the namespace opener intact.  Only the *stable* parts (licence,
includes, `namespace` open/close) may be taken from it; the bodies differ by
TASK-045…TASK-076 and must come from the transcript read windows.  Do **not** substitute
the backup wholesale — that would silently roll the module back ~30 tasks.

**Step 1 — restore the five tails (class B).**  Same rule: the missing tail must come
from the transcript read windows; the TASK-044 backup is a last resort and its bytes are
demonstrably older.

**Step 2 — fix `tools/project_read_files.h` (R4).**  This is the single highest-leverage
repair after Step 0: it explains `C2870` / `C2601` and the 227 engine-header cascades.
The `namespace MCPTools {` opener (and the block boundary around lines 52-55) must be
re-inserted, not guessed: the header's own docstring and the nine sibling group headers
(`tools/project_*_read.h`) show the intended shape.

**Step 3 — re-verify the nine class-D suspects** against the transcript windows once
Steps 0-2 stop poisoning their translation units; several may turn out to be healthy
(R5 is explicitly a suspicion list).

**Step 4 — the test header.**  Promote the `_low-confidence` payload **minus lines
9506-9626**, then re-run with `tests=yes` and confirm the fossil's 8 × `C2248`
disappear while `static_assert` still holds.

**Step 5 — the fossil `tests/` residue.**  `tests/_task044_block.txt` (32,581 B) and
`tests/__tmp_task052_tests.txt` (17,102 B) are recovery by-products inside the module and
are not compiled; they should be removed in the same hygiene commit as
`modules/mcp_server/gen_b2_restore.tmp.py` (flagged in commit ② and deliberately left
alone because it does not match the `b2*.tmp.*` glob the task named).

**Step 6 — re-run the full build** `scons platform=windows target=editor tests=yes -j8`
and only then attempt `module_mono_enabled=yes`.

## What this evidence does NOT establish

* It does **not** establish that the three head-damaged files can be restored byte-exactly.
  The transcript read windows for them have not been merged in this task.
* It does **not** establish that the 13 promoted low-confidence files are correct — three
  of them (`editor_node_read.cpp`, `project_write_resource_scene.cpp`,
  `running_game_node_write.cpp`) are independently shown here to be truncated.
* It does **not** claim the 227 engine-header errors are engine defects.  They are
  attributed inside module translation units and disappear once the module headers stop
  unbalancing the translation unit; that prediction has not been tested by a rebuild.
