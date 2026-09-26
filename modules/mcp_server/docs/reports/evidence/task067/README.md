# evidence/task067 -- how to read this tree (TASK-067)

All files are written by `scripts/mcp_evidence_guard.ps1`'s `Write-McpEvidenceBytes`,
so every name is `<leaf>__<seq>__<sha8>.<ext>` and the `sha8` in the name is the
first eight hex digits of the file's own SHA-256 (the writer asserts that after
writing). Two files with the same `sha8` hold the same bytes.

## run-mono-prefix / run-mono-head

`run-mono-prefix` is the **pre-change** run (`mcp067_live.ps1 -Phase pre`) and
`run-mono-head` the **post-change** run (`-Phase post`), both on
`bin\godot.windows.editor.x86_64.mono.console.exe` (see `engine_version.txt` in
each directory for what that binary reported; note that the version string is a
source revision and does **not** distinguish the two builds -- REPORT-067
section 0 says how they are told apart).

| file | what it is |
|---|---|
| `calls/*.request.json` / `*.response.json` | one MCP `tools/call`, the exact bytes on the wire |
| `*_p1_list_scripts_summary__*.summary.json` | the parsed `project_list_scripts` answer: the script set, the per-language counts, the shape check, and the response sha256 |
| `*_p1_fs_tree_paths__*.summary.json` | the parsed `project_get_filesystem_tree` answer (the independent third observation) |
| `*_p2_{A,B,D,E,F}_*.project.godot` | `project.godot` at each point of the comment chain (A hand written, B after `--import`, D after the windowed editor's own save, F after the tool writes, E after the session) |
| `*_p2_B_vs_D_line_diff__*.summary.json` | the line-level diff between B and D, plus whether the bytes are identical |
| `*_p2_snapshots__*.summary.json` | the snapshot table (bytes, sha256, comment-line count per point) and the four probe comment texts |
| `*_run_summary__*.summary.json` | every check of that run with its result |

## SUPERSEDED files (kept on purpose, do not cite)

`run-mono-prefix` holds **two** runs. The first one had a broken fixture: the
harness copied the C# fixture with `Copy-Item <dir> -Destination <existing dir>
-Recurse`, which nests it as `proj-mixed\proj\...`, so the editor's `res://` was a
directory that was not a project and `cs=0` was produced for the wrong reason.
The harness now copies the *contents* and asserts `project.godot` at the root
(then `p1_mixed_fixture_root_is_a_project`, and `res://scripts cs=6 gd=2`).

Superseded (first, broken-fixture run) -- **do not cite**:

* `mono-prefix_p1_fs_tree_paths__0001__660a3fba.summary.json`
* `mono-prefix_run_summary__0001__459e781f.summary.json`
* `calls/mono-prefix_p1_fs_tree_scripts__0002__0bf6c235.response.json`
* `calls/mono-prefix_p1_read_main_cs__0003__168924df.response.json`

The current pre-change evidence is `mono-prefix_p1_fs_tree_paths__0001__73166d4e.summary.json`
and `mono-prefix_run_summary__0001__f3c3a5e0.summary.json` (28/28 checks pass,
including `p1_PRE_defect_reproduces_cs_invisible :: cs=0 gd=2` with a verified
fixture and `p1_crosscheck_the_cs_is_a_readable_project_script :: size=2389`).

## logs/

Red and green doctest outputs, the two live run logs, and the first/last lines of
the seven build logs (with their exit codes). `red_*` were produced by binaries
built from the unmodified tree, `green_*` by the final ones; REPORT-067 section 4.1
gives the build-log timestamps and the source file mtimes that separate them.
