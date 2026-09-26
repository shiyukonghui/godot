# -*- coding: utf-8 -*-
"""Render docs/TOOL-NAMING.md from docs/tool-rename-map.json (v1.1).

This is the v1.0 generator (`%TEMP%\\namdoc\\gen_table.py`) folded into the
repository, with the v1.1 changes required by TASK-001 section 2.5.2:

  * the map is the single source of truth and is read from this repo;
  * the document header fingerprint (bytes / sha256 / entry count) is computed
    from the map bytes, so it can never drift from the data;
  * `disposition` is an enum (no `merge_into:<old_name>` inline form) and merge
    groups are derived from `merge_target` - GDR-17 leaves exactly 1 group;
  * the structural counts of v1.1 are asserted (174 entries, disposition
    164/7/1/2, channel 103/45/24/2, mutating true == 103) so an accidental edit
    of the map becomes a hard failure instead of a silent document;
  * the generator is idempotent and deterministic: it renders twice, asserts the
    two renders are byte-identical, then writes and reads the file back.

TASK-003 section 1.4 adds one more hard assertion (v1.1 document, unchanged
data): every one of the 174 rendered rows must have exactly 9 markdown cells
when split on *unescaped* `|`, and each cell must unescape byte-for-byte back
to the map field. `esc()` already turns a `|` inside a cell into `\|` (the map
carries exactly one, in `get_project_info`), which is why the cell split has to
ignore escaped pipes; the naive `split("|")` reading stays visible as "exactly
1 of the 174 rows breaks" and is asserted as such.

It reads exactly two files (`tool-rename-map.json`, `scripts/template.md`) and
writes exactly one (`TOOL-NAMING.md`).

Usage:  python modules/mcp_server/docs/scripts/gen_table.py [--check-only]
Standard library only (Python 3.9).
"""

import collections
import hashlib
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
MODULE_ROOT = os.path.dirname(DOCS)

SRC = os.path.join(DOCS, "tool-rename-map.json")
DST = os.path.join(DOCS, "TOOL-NAMING.md")
TPL = os.path.join(HERE, "template.md")

SCRIPT_REL = "modules/mcp_server/docs/scripts/gen_table.py"

EXPECTED_ROWS = 174
EXPECTED_CHANNEL = {"editor": 103, "project": 45, "running_game": 24, "os": 2}
EXPECTED_DISPOSITION = {
    "rename": 164,
    "merge_into": 1,
    "unregister_until_implemented": 2,
    "fix_implementation_first": 7,
}
EXPECTED_MUTATING_TRUE = 103
EXPECTED_VERBS = 37
EXPECTED_GROUP_COUNT = 11
DE_MERGED = ("project_search_file_contents", "project_find_files_referencing_symbol",
             "editor_analyze_signal_flow", "editor_list_signal_connections")

EVID = []


def ev(s):
    EVID.append(s)
    print(s)


# --------------------------------------------------------------------------
# 0. read the data source
# --------------------------------------------------------------------------
raw = open(SRC, "rb").read()
sha = hashlib.sha256(raw).hexdigest()
ev("SOURCE  tool-rename-map.json  bytes=%d  sha256=%s" % (len(raw), sha))

D = json.loads(raw.decode("utf-8"))
tools = D["tools"]
assert D["total"] == EXPECTED_ROWS, D["total"]
assert len(tools) == EXPECTED_ROWS, len(tools)

VERBS_JSON = D["convention"]["verb_closed_set"]
FIELDS = ["old_name", "new_name", "channel", "verb", "object",
          "mutating", "scope", "disposition", "reason"]
for t in tools:
    missing = [f for f in FIELDS if f not in t]
    assert not missing, (t.get("old_name"), missing)
    assert t["reason"].strip(), t["old_name"]

CHANNELS = ["editor", "running_game", "project", "os"]

# v1.1 shape assertions (TASK-001 section 2.3 / 2.4).
DISPOSITION_ENUM = D["convention"]["disposition_enum"]
assert DISPOSITION_ENUM == ["rename", "keep", "merge_into",
                            "unregister_until_implemented",
                            "fix_implementation_first"], DISPOSITION_ENUM
assert D["convention"]["scope_enum"] == ["editor", "game", "both"]
assert "conditional_write_clause" in D["convention"]
assert "103" in D["convention"]["mutating_semantics"]
for t in tools:
    assert t["disposition"] in DISPOSITION_ENUM, (t["old_name"], t["disposition"])
    assert not str(t["disposition"]).startswith("merge_into:"), t["old_name"]
    if t["disposition"] == "merge_into":
        assert t["merge_target"] in set(x["old_name"] for x in tools), t["old_name"]
    else:
        assert "merge_target" not in t, t["old_name"]

# --------------------------------------------------------------------------
# 1. lint re-check: longest-prefix parse + declared consistency + closed set
# --------------------------------------------------------------------------
NAME_RE = re.compile(r"^(editor|running_game|project|os)_[a-z0-9_]+$")


def parse_name(name):
    for ch in sorted(CHANNELS, key=len, reverse=True):  # longest prefix first
        if name.startswith(ch + "_"):
            rest = name[len(ch) + 1:]
            verb, _, tail = rest.partition("_")
            return ch, verb, tail
    raise ValueError("no channel prefix: " + name)


lint_fail = []
for t in tools:
    n = t["new_name"]
    if not NAME_RE.match(n):
        lint_fail.append((n, "L1 regex"))
        continue
    ch, vb, obj = parse_name(n)
    if ch != t["channel"]:
        lint_fail.append((n, "L3 channel %s != declared %s" % (ch, t["channel"])))
    if vb != t["verb"]:
        lint_fail.append((n, "L3 verb %s != declared %s" % (vb, t["verb"])))
    if vb not in VERBS_JSON:
        lint_fail.append((n, "L2 verb not in closed set: " + vb))
    if "update_" in n:
        lint_fail.append((n, "L4 banned update_"))
    if not obj:
        lint_fail.append((n, "object empty"))
assert not lint_fail, lint_fail
ev("LINT    L1..L4 over %d new_name: 0 violations (longest-prefix parse)" % len(tools))

naive_bad = [t["new_name"] for t in tools
             if t["new_name"].startswith("running_game_") and t["new_name"].split("_")[1] != t["verb"]]
assert len(naive_bad) > 0, "expected the naive split('_')[1] to demonstrably fail"
ev("LINT    demonstration: split('_')[1] misparses %d/%d running_game_* names "
   "(e.g. %s -> '%s' instead of verb '%s')"
   % (len(naive_bad), sum(1 for t in tools if t["channel"] == "running_game"),
      naive_bad[0], naive_bad[0].split("_")[1], parse_name(naive_bad[0])[1]))

# --------------------------------------------------------------------------
# 2. aggregates (v1.1 counts are asserted, not just printed)
# --------------------------------------------------------------------------
ch_counts = collections.Counter(t["channel"] for t in tools)
disp_counts = collections.Counter(t["disposition"] for t in tools)
scope_counts = collections.Counter(t["scope"] for t in tools)
mut_counts = collections.Counter(t["mutating"] for t in tools)

ev("CHANNEL " + "  ".join("%s=%d" % (c, ch_counts[c]) for c in CHANNELS)
   + "  (sum=%d)" % sum(ch_counts[c] for c in CHANNELS))
assert sum(ch_counts[c] for c in CHANNELS) == EXPECTED_ROWS
assert {c: ch_counts[c] for c in EXPECTED_CHANNEL} == EXPECTED_CHANNEL, dict(ch_counts)
ev("DISPO   " + "  ".join("%s=%d" % (k, disp_counts[k]) for k in EXPECTED_DISPOSITION))
assert {k: disp_counts[k] for k in EXPECTED_DISPOSITION} == EXPECTED_DISPOSITION, dict(disp_counts)
ev("SCOPE   " + "  ".join("%s=%d" % (k, scope_counts[k]) for k in ("editor", "both", "game")))
ev("MUT     mutating=true %d / false %d" % (mut_counts[True], mut_counts[False]))
assert mut_counts[True] == EXPECTED_MUTATING_TRUE, mut_counts[True]

DISP_ORDER = ["rename", "merge_into", "unregister_until_implemented", "fix_implementation_first"]

for fam in ("merge_into", "unregister_until_implemented", "fix_implementation_first"):
    items = [t for t in tools if t["disposition"] == fam]
    ev("%-28s %d 项: %s" % (fam, len(items), ", ".join(t["old_name"] for t in items)))
assert len([t for t in tools if t["disposition"] == "merge_into"]) == 1
assert len([t for t in tools if t["disposition"] == "unregister_until_implemented"]) == 2
assert len([t for t in tools if t["disposition"] == "fix_implementation_first"]) == 7

by_old = {t["old_name"]: t for t in tools}
assert len(by_old) == EXPECTED_ROWS, "old_name not unique"

# GDR-17 / D-1 / D-5 specifics that the document talks about must really hold.
merged_entry = [t for t in tools if t["disposition"] == "merge_into"][0]
ev("MERGE   survivor=%s target=%s (shared new_name=%s)"
   % (merged_entry["old_name"], merged_entry["merge_target"], merged_entry["new_name"]))
assert "平铺改嵌套" in merged_entry["reason"], merged_entry["reason"]
for name in DE_MERGED:
    assert name in set(t["new_name"] for t in tools), name
shots = [by_old["get_editor_screenshot"], by_old["get_game_screenshot"]]
assert all(t["mutating"] is True and "条件写" in t["reason"] for t in shots), shots
ev("D-1     conditional writes: %s / %s both mutating=true (GDR-18)"
   % (shots[0]["new_name"], shots[1]["new_name"]))
ev("D-2/D-3 de-merged pairs kept as 4 distinct names: %s" % ", ".join(DE_MERGED))
ev("D-5     verb_notes.evaluate = %r" % D["convention"]["verb_notes"]["evaluate"])

# --------------------------------------------------------------------------
# 3. table rendering
# --------------------------------------------------------------------------
def esc(s):
    return s.replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ").replace("\r", " ")


HEADER = ("| old_name | channel | verb | object | new_name | mutating | scope | disposition | reason |\n"
          "|---|---|---|---|---|---|---|---|---|\n")


def table(ch):
    rows = [t for t in tools if t["channel"] == ch]
    out = [HEADER]
    for t in rows:
        disp = "`%s`" % t["disposition"]
        # N-1 (audit REPORT-AUDIT-001 rename-map v1.1): the cell must be the pure
        # enum value so that a machine consumer parsing this table sees exactly
        # the value stored in the map. v1.1 rendered `` `merge_into`→`<target>` ``
        # for the single merge row, which is not equal to the enum; the survivor
        # already has its own `merge_target` column, so the decoration was both
        # redundant and a parse hazard.
        out.append("| `%s` | `%s` | `%s` | `%s` | `%s` | %s | `%s` | %s | %s |\n" % (
            esc(t["old_name"]), esc(t["channel"]), esc(t["verb"]), esc(t["object"]),
            esc(t["new_name"]), "true" if t["mutating"] else "false",
            esc(t["scope"]), disp, esc(t["reason"])))
    return "".join(out), len(rows)


tables = {}
for ch in CHANNELS:
    txt, n = table(ch)
    tables[ch] = txt
    assert n == ch_counts[ch], (ch, n, ch_counts[ch])
TABLE_ROWS = sum(ch_counts[c] for c in CHANNELS)
ev("TABLE   rendered rows=%d (assert rows == %d: %s)"
   % (TABLE_ROWS, EXPECTED_ROWS, "PASS" if TABLE_ROWS == EXPECTED_ROWS else "FAIL"))
assert TABLE_ROWS == EXPECTED_ROWS

# N-1 regression guard: the disposition cell is the pure enum value on *every*
# rendered row, so a machine consumer can parse the table straight into the map.
DISP_CELL_RE = re.compile(
    r"^\| `[^`]+` \| `[^`]+` \| `[^`]+` \| `[^`]+` \| `[^`]+` \| (?:true|false) \| `[^`]+` \| `([a-z_]+)` \|")
disp_cells = []
for ch in CHANNELS:
    for line in tables[ch].splitlines():
        match = DISP_CELL_RE.match(line)
        if match:
            disp_cells.append(match.group(1))
assert len(disp_cells) == EXPECTED_ROWS, len(disp_cells)
bad_cells = sorted(set(disp_cells) - set(DISPOSITION_ENUM))
assert not bad_cells, bad_cells
assert "merge_into" in disp_cells
ev("N-1     disposition cells parsed = %d, all pure enum values (no '->target' "
   "decoration); merge_into cells = %d" % (len(disp_cells), disp_cells.count("merge_into")))

# --------------------------------------------------------------------------
# 3.1 D-5 regression guard (TASK-003 section 1.4): a `|` inside a cell is
#     rendered as `\|` by esc(), so a machine consumer has to split on
#     *unescaped* pipes. Note what that implies: `naive.split("|")` can never
#     yield 9 cells for a row that carries an escaped pipe, because the escape
#     only *adds* a backslash byte in front of the pipe - the pipe is still
#     there. The honest invariant is therefore the pair pinned below:
#       (a) exactly 9 cells per row when splitting on unescaped `|`, for all
#           174 rows, and
#       (b) every cell unescapes byte-for-byte back to the map field.
#     The naive splitter stays observable as "exactly 1 of 174 rows breaks".
# --------------------------------------------------------------------------
CELL_SPLIT_RE = re.compile(r"(?<!\\)\|")


def split_md_row(line):
    parts = CELL_SPLIT_RE.split(line.rstrip("\n"))
    assert parts[0] == "" and parts[-1] == "", "a rendered row must start and end with '|': %r" % line
    return [part.strip() for part in parts[1:-1]]


def unescape_md(text):
    # The exact inverse of esc(): `\|` -> `|`, then `\\` -> `\`.
    return text.replace("\\|", "|").replace("\\\\", "\\")


d5_rows = [(ch, line) for ch in CHANNELS for line in tables[ch].splitlines() if line.startswith("| `")]
d5_expected = [(ch, t) for ch in CHANNELS for t in tools if t["channel"] == ch]
assert len(d5_rows) == len(d5_expected) == EXPECTED_ROWS, (len(d5_rows), len(d5_expected))
d5_pairs = list(zip(d5_rows, d5_expected))

d5_bad_columns = []
d5_bad_cells = []
d5_bad_reason = []
d5_escaped_cells = 0
for (ch, line), (ch2, t) in d5_pairs:
    assert ch == ch2, (ch, ch2)
    cells = split_md_row(line)
    if len(cells) != 9:
        d5_bad_columns.append((str(t["old_name"]), len(cells)))
        continue
    d5_escaped_cells += line.count("\\|")
    want = [
        "`%s`" % esc(t["old_name"]), "`%s`" % esc(t["channel"]), "`%s`" % esc(t["verb"]),
        "`%s`" % esc(t["object"]), "`%s`" % esc(t["new_name"]),
        "true" if t["mutating"] else "false", "`%s`" % esc(t["scope"]),
        "`%s`" % t["disposition"], esc(t["reason"]),
    ]
    if cells != want:
        d5_bad_cells.append(str(t["old_name"]))
    if unescape_md(cells[8]) != t["reason"]:
        d5_bad_reason.append(str(t["old_name"]))

assert not d5_bad_columns, d5_bad_columns
assert not d5_bad_cells, d5_bad_cells
assert not d5_bad_reason, d5_bad_reason

# The map is expected to carry exactly one raw `|` (get_project_info, whose
# reason quotes `application/config/name|version`). Pinning both the owner and
# the count makes a second raw pipe - the only way a row could stop being 9
# cells - a hard failure instead of a silent widening.
d5_raw_pipes = [str(t["old_name"]) for t in tools if "|" in t["reason"]]
assert d5_raw_pipes == ["get_project_info"], d5_raw_pipes
# `line.split("|")` on `| a | b | ... | i |` returns 11 parts for the 9 cells
# (the two outer empties plus one part per pipe), so a *naive* parser sees
# `len(parts) - 2` cells: 9 normally, 10 for the one row with the escaped pipe.
d5_naive_broken = [str(t["old_name"]) for (_, line), (_, t) in d5_pairs
                   if len(line.split("|")) - 2 != 9]
assert d5_naive_broken == ["get_project_info"], d5_naive_broken
assert d5_escaped_cells == 1, d5_escaped_cells

ev("D-5     rows with exactly 9 cells (split on unescaped '|') = %d/%d: PASS"
   % (len(d5_rows) - len(d5_bad_columns), EXPECTED_ROWS))
ev("D-5     cells unescaping byte-equal to the map field = %d/%d: PASS"
   % (EXPECTED_ROWS - len(d5_bad_reason), EXPECTED_ROWS))
ev("D-5     escaped cells ('\\|') = %d; rows a naive split('|') breaks = %d (%s) - "
   "asserted, not tolerated" % (d5_escaped_cells, len(d5_naive_broken), ", ".join(d5_naive_broken)))

# --------------------------------------------------------------------------
# 4. verb definitions (37 closed-set verbs, one definition + one real example)
# --------------------------------------------------------------------------
VERB_DEFS = {
    "get": ("读取**已知对象**的当前状态并返回值（单对象状态查询，不遍历集合）。", "editor_get_node_properties"),
    "list": ("**枚举一个集合**（磁盘上的文件、总线、动画、预设、设备、信号连接），返回元素清单。", "project_list_scripts"),
    "read": ("读取**文件 / 资源的文本或内容本身**（内容即返回值，而非对象的属性状态）。", "project_read_scene_file_content"),
    "find": ("在已知容器内**按条件定位**匹配项，返回位置或句柄；不返回文件内容。", "editor_find_nodes_in_group"),
    "search": ("在**一批文件**中按模式检索，命中结果是「哪些文件/哪些行」。", "project_search_file_contents"),
    "create": ("在目标容器中**新建**一个此前不存在的实体（新节点、新文件、新动画）。", "project_create_scene_file"),
    "add": ("把**已有**实体**挂到 / 挂入**目标容器或集合（节点、总线、轨道、autoload 项）。", "editor_add_node"),
    "remove": ("从容器中**移除**一个成员，容器本身仍存在（动画、轨道、autoload、选中集合、日志）。", "editor_remove_node_selection"),
    "delete": ("**销毁实体本身**（文件落盘删除 / 节点不存在了），而不只是从集合里摘掉。", "project_delete_scene_file"),
    "set": ("**写单个属性 / 单个值**（唯一合法的单值写动词，取代 `update_`）。", "editor_set_node_property"),
    "edit": ("对**磁盘文件内容**做整篇或模式化**读改写**（是文件编辑，不是单属性赋值）。", "project_edit_script"),
    "rename": ("改变对象的**名字**，不改变它在结构中的位置。", "editor_rename_node"),
    "reparent": ("把节点挂到**新的父节点**下（结构位置变更；不是坐标移动）。", "editor_reparent_node"),
    "move": ("改变对象的**空间位置 / 坐标**（玩家、视角随动位姿）。", "running_game_move_player_to_target"),
    "duplicate": ("**复制**一个对象（连同其属性/子树）产生副本。", "editor_duplicate_node"),
    "connect": ("在两个对象之间**建立**一条关联（信号→Callable）。", "editor_connect_signal"),
    "disconnect": ("**解除**两个对象之间已有的关联（`connect` 的逆操作）。", "editor_disconnect_signal"),
    "play": ("**开始播放**一个可播放资源（场景、录制回放）。", "editor_play_scene"),
    "stop": ("**停止**正在进行的播放 / 录制（`play`/`create` 的逆操作）。", "editor_stop_scene"),
    "run": ("**启动一项较长任务**并等它产出结果（测试场景、压力测试），而不是控制某一次播放。", "running_game_run_test_scenario"),
    "execute": ("在**目标上下文里直接执行代码**（编辑器侧或游戏侧的 GDScript），副作用由代码决定。", "editor_execute_gdscript"),
    "evaluate": ("**求值一个表达式**并返回其结果值（不提交任何副作用）。", None),
    "capture": ("**取像 / 取观测样本**：截图、连续抓帧、监听并回传信号发射（截图带 `save_path` 时属条件写，GDR-18）。", "running_game_capture_screenshot"),
    "assert": ("在目标进程内**断言**某个条件成立并回报判定（失败即测试证据，不修改产物）。", "running_game_assert_node_state"),
    "validate": ("对对象**做只读校验 / 编译检查**并返回结论（不修复、不落盘）。", "project_validate_script"),
    "simulate": ("**注入输入事件**以模拟交互（有副作用、通常非幂等）。", "editor_simulate_input_action"),
    "export": ("**生成导出产物**（导出为可分发包）。", "project_export_game"),
    "deploy": ("把产物**安装 / 启用到外部设备**。", "os_deploy_to_android_device"),
    "reload": ("让组件**重新初始化 / 重新加载**（插件重建）。", "editor_reload_plugin"),
    "rescan": ("让编辑器**重扫资源 / 文件系统索引**以刷新认知（不改文件内容）。", "editor_rescan_project_filesystem"),
    "bake": ("**预计算 / 预烘**派生数据（如导航网格），让运行期不必现算。", "editor_bake_navigation_mesh"),
    "open": ("让编辑器**打开 / 切到**某个资源或场景（改变编辑器当前工作对象）。", "editor_open_scene"),
    "save": ("把**内存中的编辑结果写回**其持久位置（当前编辑场景）。", "editor_save_scene"),
    "setup": ("**配置 / 搭好**一个对象或结构（一次性的成型动作，可能创建多个相关节点）。", "editor_setup_physics_body"),
    "analyze": ("**分析 / 汇总**产出派生结论（流向、复杂度、差异图），不改变被分析对象。", "editor_analyze_signal_flow"),
    "detect": ("**检测**存在性问题并回报布尔/清单（环、冲突），是判定而非分析。", "project_detect_circular_dependencies"),
    "convert": ("**转换表示形式**（UID↔路径），不改变任何状态。", "project_convert_uid_to_path"),
}

NEWNAME_SET = set(t["new_name"] for t in tools)
VERB_USED = collections.Counter(t["verb"] for t in tools)
assert set(VERB_USED) <= set(VERBS_JSON), set(VERB_USED) - set(VERBS_JSON)
missing_defs = [v for v in VERBS_JSON if v not in VERB_DEFS]
assert not missing_defs, missing_defs
unused = [v for v in VERBS_JSON if VERB_USED[v] == 0]
ev("VERBS   closed set=%d  used=%d  unused=%s (annotated unused_in_v1)"
   % (len(VERBS_JSON), len(VERB_USED), unused or "none"))
assert unused == ["evaluate"], unused
assert D["convention"]["verb_notes"]["evaluate"].startswith("unused_in_v1")

vrows = ["| 动词 | 唯一含义（一句话） | 用对了的例子（真实新名） | 用量 |", "|---|---|---|---|"]
for v in VERBS_JSON:
    d, ex = VERB_DEFS[v]
    if ex is not None:
        assert ex in NEWNAME_SET, ("example not in JSON new_name set", v, ex)
    note = "（`unused_in_v1`：闭集保留，v1.1 的 174 项中用量为 0）" if VERB_USED[v] == 0 else None
    vrows.append("| `%s` | %s | %s | %d |" % (v, d, ("`%s`" % ex) if ex else note, VERB_USED[v]))
ev("VERBS   every example verified against JSON new_name set: PASS")
assert len(VERBS_JSON) == len(set(VERBS_JSON)), "verb closed set contains duplicates"
defined = [v for v in VERBS_JSON if VERB_DEFS[v][0].strip()]
assert len(defined) == len(VERBS_JSON) == EXPECTED_VERBS, (len(defined), len(VERBS_JSON))
ev("VERBS   one definition per verb: %d/%d distinct definitions" % (len(defined), len(VERBS_JSON)))
VERB_TABLE = "\n".join(vrows) + "\n"

# --------------------------------------------------------------------------
# 5. merge alias table (one new_name shared by two old_names)
# --------------------------------------------------------------------------
alias = collections.defaultdict(list)
for t in tools:
    alias[t["new_name"]].append(t["old_name"])
dups = {k: v for k, v in alias.items() if len(v) > 1}
assert len(dups) == 1, dups
merge_rows = ["| 新名（同 1 个） | 对应旧名（2 个） | disposition | merge_target |", "|---|---|---|---|"]
for k, v in dups.items():
    for old in v:
        entry = by_old[old]
        merge_rows.append("| `%s` | `%s` | `%s` | %s |" % (
            k, old, entry["disposition"],
            ("`%s`" % entry["merge_target"]) if entry.get("merge_target") else "—"))
ev("MERGE   duplicate new_name groups=%d (expect 1): %s" % (len(dups), "; ".join(sorted(dups))))
MERGE_TABLE = "\n".join(merge_rows) + "\n"

# --------------------------------------------------------------------------
# 6. assemble
# --------------------------------------------------------------------------
tpl = io.open(TPL, encoding="utf-8").read()


def fill(text):
    text = text.replace("@@MAPBYTES@@", str(len(raw)))
    text = text.replace("@@MAPSHA@@", sha)
    text = text.replace("@@CNT:editor@@", str(ch_counts["editor"]))
    text = text.replace("@@CNT:running_game@@", str(ch_counts["running_game"]))
    text = text.replace("@@CNT:project@@", str(ch_counts["project"]))
    text = text.replace("@@CNT:os@@", str(ch_counts["os"]))
    text = text.replace("@@VERBCOUNT@@", str(len(VERBS_JSON)))
    text = text.replace("@@VERBDEFS@@", VERB_TABLE)
    text = text.replace("@@CHANNELSUM@@",
                        " + ".join("%d" % ch_counts[c] for c in CHANNELS) + " = %d 条。" % EXPECTED_ROWS
                        + "（`editor` %d / `running_game` %d / `project` %d / `os` %d；"
                          "脚本断言与 JSON `total` 一致，脚本输出见 §7。）"
                          % (ch_counts["editor"], ch_counts["running_game"],
                             ch_counts["project"], ch_counts["os"]))
    text = text.replace("@@DISPAGG@@",
                        "；".join("`%s %d`" % (k, disp_counts[k]) for k in DISP_ORDER)
                        + "（合计 %d）" % EXPECTED_ROWS)
    text = text.replace("@@MERGEALIAS@@", MERGE_TABLE)
    return text


doc = fill(tpl)
GROUP_ACTUAL = len(re.findall(r"^### 3\.(?!0)\d+ ", doc, re.M))
assert GROUP_ACTUAL == EXPECTED_GROUP_COUNT, (GROUP_ACTUAL, EXPECTED_GROUP_COUNT)
doc = doc.replace("@@GROUPCOUNT@@", str(GROUP_ACTUAL))
ev("GROUPS  §3 消歧分组数 = %d（3.1..3.%d；另加 3.0 新名重名表；断言 == %d: PASS）"
   % (GROUP_ACTUAL, GROUP_ACTUAL, EXPECTED_GROUP_COUNT))
for ch in CHANNELS:
    doc = doc.replace("@@TABLE:%s@@" % ch, tables[ch])

LEFTOVER = [p for p in re.findall(r"@@[A-Za-z0-9_:]+@@", doc)
            if p not in ("@@EVIDENCE@@", "@@SCRIPT@@", "@@CHECKSCRIPT@@", "@@GROUPCOUNT@@",
                         "@@SELFSIZE@@", "@@SELFSHA@@")]
assert not LEFTOVER, "unreplaced placeholder(s): " + ", ".join(LEFTOVER)

doc = doc.replace("@@SCRIPT@@", SCRIPT_REL)
doc = doc.replace("@@CHECKSCRIPT@@", SCRIPT_REL + "（§7 的 CONSISTENCY 段）")

# --------------------------------------------------------------------------
# 7. consistency self-check: every channel-prefixed identifier in the document
#    must be traceable to the map (new_name or old_name)
# --------------------------------------------------------------------------
TOKEN_RE = re.compile(r"\b(?:editor|running_game|project|os)_[a-z0-9_]+\b")
TOKENS = sorted(set(TOKEN_RE.findall(doc)))
OLDNAME_SET = set(t["old_name"] for t in tools)
# Non-tool identifiers that are legitimately channel-prefixed:
#   editor_process / game_process : channel constants of hof-rs (godot.rs:2382-2383)
#   project_filesystem            : the object segment of editor_rescan_project_filesystem
#   the *_<verb>_ fragments        : wildcard spellings of a verb segment in the
#                                    prose (§1.3 / §3.5 / §6.2 / §6.3). Each one
#                                    is proved below to be a substring of a real
#                                    new_name, so it is traceable to the map too.
ALLOWED_NON_TOOL = {"editor_process", "game_process", "project_filesystem",
                    "editor_add_", "editor_set_", "editor_simulate_",
                    "project_edit_", "running_game_assert_"}
FRAGMENTS = {"editor_add_", "editor_set_", "editor_simulate_",
             "project_edit_", "running_game_assert_", "project_filesystem"}
assert all(any(f in t for t in NEWNAME_SET) for f in FRAGMENTS), FRAGMENTS
NEW_TOKENS = [t for t in TOKENS if t in NEWNAME_SET]
OLD_TOKENS = [t for t in TOKENS if t not in NEWNAME_SET and t in OLDNAME_SET]
OTHER_TOKENS = [t for t in TOKENS if t not in NEWNAME_SET and t not in OLDNAME_SET]
UNKNOWN_TOKENS = [t for t in OTHER_TOKENS if t not in ALLOWED_NON_TOOL]
ev("CONSISTENCY  channel-prefixed identifiers in doc: %d distinct (occurrences %d)"
   % (len(TOKENS), sum(collections.Counter(TOKEN_RE.findall(doc)).values())))
ev("CONSISTENCY  ├─ 命中 JSON new_name: %d 个（新名）" % len(NEW_TOKENS))
ev("CONSISTENCY  ├─ 命中 JSON old_name: %d 个（仅作为「旧名」被引用，属预期）" % len(OLD_TOKENS))
ev("CONSISTENCY  ├─ 非工具标识符（白名单，通道常量/object 片段）: %d 个 %s"
   % (len([t for t in OTHER_TOKENS if t in ALLOWED_NON_TOOL]),
      sorted(t for t in OTHER_TOKENS if t in ALLOWED_NON_TOOL)))
ev("CONSISTENCY  └─ 无法回查 JSON 的标识符: %s" % (UNKNOWN_TOKENS or "NONE"))
ev("CONSISTENCY  result: %s"
   % ("PASS（文档中出现的工具名 100% 来自 JSON 的 old_name/new_name 集合）"
      if not UNKNOWN_TOKENS else "FAIL"))
assert not UNKNOWN_TOKENS, UNKNOWN_TOKENS

table_line_count = sum(1 for ln in doc.splitlines()
                       if ln.startswith("| `") and ln.count("` |") >= 7)
ev("TABLE_FINAL  markdown table data rows containing a 9-column tool row = %d" % table_line_count)
assert table_line_count == EXPECTED_ROWS, table_line_count
ev("ASSERT  rows == %d : PASS" % EXPECTED_ROWS)

EVID_HEAD = ["$ python %s" % SCRIPT_REL]

# --------------------------------------------------------------------------
# 8. determinism (two renders must be byte-identical)
# --------------------------------------------------------------------------
RENDER_A = doc.replace("@@EVIDENCE@@", "")
RENDER_B = fill(io.open(TPL, encoding="utf-8").read()).replace("@@EVIDENCE@@", "")
RENDER_B = RENDER_B.replace("@@SCRIPT@@", SCRIPT_REL)
RENDER_B = RENDER_B.replace("@@CHECKSCRIPT@@", SCRIPT_REL + "（§7 的 CONSISTENCY 段）")
RENDER_B = RENDER_B.replace("@@GROUPCOUNT@@", str(GROUP_ACTUAL))
for c in CHANNELS:
    RENDER_B = RENDER_B.replace("@@TABLE:%s@@" % c, tables[c])
assert RENDER_A == RENDER_B, "rendering is not deterministic"
ev("DETERMINISM  render run#1 == render run#2 byte-identical (%d bytes): PASS"
   % len(RENDER_A.encode("utf-8")))

doc = doc.replace("@@EVIDENCE@@", "\n".join(EVID_HEAD + EVID))

# --------------------------------------------------------------------------
# 9. write, then read back and compare byte for byte
# --------------------------------------------------------------------------
if "--check-only" not in sys.argv:
    with io.open(DST, "w", encoding="utf-8", newline="\n") as f:
        f.write(doc)
    b = io.open(DST, "rb").read()
    assert b == doc.encode("utf-8"), "write-then-read-back mismatch"
    ev("WROTE   %s  bytes=%d  sha256=%s  (write-then-read-back byte-identical)" % (
        DST, len(b), hashlib.sha256(b).hexdigest()))
    print("BYTES %d" % len(b))
    print("SHA256 " + hashlib.sha256(b).hexdigest())
    print("DETERMINISM PASS")
else:
    print("CHECK-ONLY: document not written.")