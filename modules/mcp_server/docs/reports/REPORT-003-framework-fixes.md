# REPORT-003 — 框架修复与加固（审计 5 缺陷 + 两条机制性建议）

- **status**：`pass` — 6 个门全绿（退出码 0），无 blocker；工作树除既有未跟踪物外干净。
- **任务书**：`docs/tasks/TASK-003-framework-fixes.md`（唯一来源，自包含）。
- **分支**：`feature/mcp-server-module`；**未 push**。
- **范围**：只改 `modules/mcp_server/**`；`F:\moonbit-hof-rs` 与 `godot_mcp_gdext` 全程**只读**
  （`git status` 的改动集 100% 落在 `modules/mcp_server/` 内，见 §4）。
- **端口纪律**：用户编辑器（PID 36392）占 9877，全程 `pid_before=36392 pid_after=36392`；
  测试只用 9888 / 9889；scratch 在 `%TEMP%`。所有子进程都是我脚本起的 PID，结束后无残留（见 §3 末）。

---

## 0. commits

| sha | 一行说明 |
|---|---|
| `1b90ba8336` | `mcp_server: TASK-003 framework fixes - order contract, path folding, single registration path`（13 files changed, +451 / −96） |
| 本报告 | 随第二个提交入库（docs only）。`git log --oneline -1` 即本报告的 sha；它不包含任何实现改动。 |

`F:\moonbit-hof-rs\DECISIONS.md` 的 **D49** 是这批裁决的权威日志；按硬性约束 hof-rs **只读**，
因此「为什么代码长这样」的记录落在本报告与 `docs/DESIGN-DETAIL.md §17.1/§17.2/§17.4`。

---

## 1. 逐条处置

### D-1 `tools/list` 顺序不是契约语义

**改了什么**

1. `scripts/gen_renamed_contract.py`：`_meta` 新增 `"order_normative": False`（含解释注释），
   生成器版本 `1.2.0 → 1.3.0`，并加一行自证输出 `order_normative = false`；**契约文件由重跑生成，未手改**
   （`scripts/gen_renamed_contract.py:397`、`:44-49`、`:422`）。
2. 重生成 `docs/tools_list.renamed.json`：契约仍 **171 条**，与 HEAD 的差异**只有 2 行**
   （`+order_normative` / `-1.2.0 +1.3.0`）→ 171 个工具条目的字节**未动**。
3. `docs/DESIGN-DETAIL.md` 新增 **§17.4「`tools/list` 的顺序与确定性」**（`:392-403`）：
   顺序非规范、**不得为重排注册而对齐契约**、但**同一次构建内连续两次调用必须逐字节相同**，
   并写明实现依据（插入序 `Vector<StringName> order`，HashMap 迭代序不出现在响应里）与回归护栏名。
4. 新增 doctest `[MCPServer] tools/list is byte-identical across consecutive calls`
   （`tests/test_mcp_server.h:817`）：同注册表连续两次、两个独立注册表、换 id、游戏进程视角各一组断言。

**证据**

```
$ git diff -U0 modules/mcp_server/docs/tools_list.renamed.json | grep '^[+-]'
+    "order_normative": false,
-    "generator_version": "1.2.0",
+    "generator_version": "1.3.0",

$ python -c "...json.loads(...)..."          # 见 §3 门 6
tools = 171
_meta.order_normative = False  (type bool)
meta keys = [..., 'order_normative', ...]
```
契约 `:3610` 为 `"order_normative": false`；doctest 通过（门 1）。

### D-3 `accept_m1.ps1` 的 SUMMARY 打印字面 `{0}/{1}`

**改了什么**：`scripts/accept_m1.ps1:1050` —— 把拼接结果**用括号包起来再套 `-f`**
（`("A" + "B" + "C") -f a, b`），并加注释说明 `-f` 比 `+` 结合更紧、缺内层括号时只有最后一段被格式化
（`:1046-1049`）。

**证据**（先复现、后验证，同一台机器）

```
--- OLD (unparenthesised, reproduce) ---
known_deviation : per-batch gate ({0} of {1} contract entries are implemented); absent from tools/list (GDR-7)
--- NEW (double parentheses) ---
known_deviation : per-batch gate (6 of 171 contract entries are implemented); absent from tools/list (GDR-7)
```
真实 accept 两次（§3 门 3）的 SUMMARY：
```
implemented tools      : 6 / contract 171
known_deviation        : per-batch gate, NOT a full-contract gate (6 of 171 contract entries are implemented and compared verbatim); unimplemented tools are deliberately absent from tools/list (GDR-7)
implemented tools = 6; contract = 171; known_deviation = per-batch verbatim gate only
```
两份日志里正则 `\{0\}` / `\{1\}` 的命中数均为 **0**。全脚本只有这一处 `/ +` 混用（已 `Select-String` 全查）。

### D-4 `normalize_project_path` 折叠 `.` 段与空段

**改了什么**：`tools/tool_builder.cpp:270-307`：

- **先**在**原始剩余部分**上判定 `..`（保持既有拒绝，并在注释里写明「折叠规则不得把已拒路径变回合法」）；
- 再按 `/` 切段，**折叠 `.` 段与空/仅空白段**（`trimmed.is_empty() || trimmed == "."`），非空段保留自身字节
  （`res://a dir/x` 不受影响），尾斜杠随之消失；
- 旧的「`//` → `-32602 空段」分支被折叠替换（这是行为变更，见 §4 deviation 1）。

**证据**（`tests/test_mcp_server.h:1277` 起，全部通过；门 1 的 450 断言含它们）

```
CHECK(normalize("res://.", ...))       -> "res://"
CHECK(normalize("res://src/.", ...))   -> "res://src"
CHECK(normalize("res:// ", ...))       -> "res://"
CHECK(normalize("res://a//b", ...))    -> "res://a/b"      ← 旧行为是 -32602
CHECK(normalize("res://a/b/", ...))    -> "res://a/b"
CHECK(normalize("res:// / . /", ...))  -> "res://"
CHECK_FALSE(normalize("res://a/./../b")) -> -32602  （折叠不放宽 ..）
CHECK_FALSE(normalize("res://..."))      -> -32602
CHECK(normalize("res://a/.hidden/."))    -> "res://a/.hidden"
```
端到端（同一测试文件 `project_get_filesystem_tree` 用例内）：`path="res://."` 与 `path="res:// "` 成功且
`tree.path == "res://"`；再用**真实树里发现的第一个子目录**做 `"<dir>/."` → `tree.path == <dir>`
（不依赖 `res://` 在 doctest 二进制里恰好解析到哪个目录）。

### D-5 `TOOL-NAMING.md` 那一行的 `|`

**事实纠正（重要）**：审计 D-5 的诊断「渲染时没有 `\|` 转义」在 HEAD 上**不成立**——

```
$ git show HEAD:modules/mcp_server/docs/scripts/gen_table.py   # esc()
def esc(s):
    return s.replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ").replace("\r", " ")
$ git show HEAD:modules/mcp_server/docs/TOOL-NAMING.md | bytes around 'config/name'
b'config/name\\|version'          # 即 name\|version，已经是转义形态
```
真正可观测的症状是**「天真 `split("|")` 会把该行切成 10 列」**——而这**恰恰是转义后的必然结果**
（转义只多一个反斜杠字节，管道符还在）。因此把不变量写成「按管道符切 9 列」在两种读法下不可能同时成立。

**改了什么**：`docs/scripts/gen_table.py:255-330` 新增 **D-5 回归护栏**（渲染器本身不动，仍用 `esc()`）：

- 用一个**只按未转义管道符**切分的解析器（`CELL_SPLIT_RE = re.compile(r"(?<!\\)\|")`）断言
  **174/174 行恰好 9 个单元格**；
- 断言**每个单元格反解（`unescape_md`）后与映射字段逐字节相等**（8 个字段 + reason）；
- 断言映射里裸 `|` 的归属与数量恰好是 `get_project_info`、`1`，且**天真切分只破坏 1 行**——
  把「已知的 1 行」变成硬断言，第二处裸 `|` 出现即构建红；
- 这三条进 `ev()`，因此**写进了文档 §7 的 EVIDENCE**（`docs/TOOL-NAMING.md` 末尾 3 行）。
- 生成器 docstring 同步说明「为什么必须按未转义管道符切」。

**证据**：门 5（重渲染幂等 + 独立复核脚本 `%TEMP%\t003-verify_naming.py`，不 import 生成器）：
`DATA_ROWS 174 / ROWS_NOT_9_CELLS 0 / FIELD_MISMATCHES 0 / ESCAPED_PIPE_CELLS 1 / NAIVE_SPLIT_BROKEN_ROWS 1 → VERIFY PASS`。

### D-2 `REPORT-002` 的叙述错误（**只改文档**）

**改了什么**：`docs/reports/REPORT-002-b1-framework.md` **末尾追加**「## 10. 勘误」段
（`:538-560`，全文 560 行），**原文一字未改**。写了：审计方 TASK-AUDIT-002 复现为
`FOOBAR` → `project_search_file_contents` **3 命中** / `project_find_files_referencing_symbol` **1 命中**；
原叙述「0 命中」有误；机制与结论（两套独立实现：形状/大小写/上限 50 vs 100）不受影响；
并补一条**读源码可得的事实**（非推断）：查找方只扫 `.tscn/.gd/.tres/.gdshader`，
`PLAYER_README.md` 是 `.md`，所以「文件里存在小写 `playerhealth`」只能被搜索方命中。

**证据**：`git diff` 显示 REPORT-002 只新增 26 行、删除 0 行。

### 机制性建议①：`register_tool` 不可绕过

**改了什么**

- `tool_registry.h:122`：`bool register_tool(const MCPToolDef &p_def);` 移入 **private**；
  `:124` 加 `friend class MCPTools::ToolBuilder;`（`namespace MCPTools { class ToolBuilder; }` 前向声明在 `:100-104`）；
  private 区带完整理由注释；`tool_registry.cpp:182` 定义处注释说明 lint 保留为注册表自身不变量。
- `tools/tool_builder.h:85-92` 更新为「这是**唯一合法**注册路径」。
- **测试**（`tests/test_mcp_server.h`）：
  - `:78-98` 编译期访问探针 `RegisterToolAccessProbe` + `static_assert(!...::is_public, ...)`（`:97`）；
  - `:795` `[MCPServer] register_tool is unreachable outside ToolBuilder`：运行期断言探针为 false，
    并断言正路仍工作（`register_probe` 成功入库）、且仍拒绝（游戏进程里的 `EDITOR` 工具、
    lint 不合规的名字），注册表计数不变；
  - 原先**所有**直接 `registry.register_tool(def)` 的测试（`tests/test_mcp_server.cpp` 的 scope/error 探针注册、
    L1–L4 lint 测试）全部改为经 `TestMCPServer::register_probe()` → `ToolBuilder::register_into()`。
  - `build_scope_registry()` 需要「游戏进程里装进一个 EDITOR 工具」来做过滤断言，现在改为
    **临时翻转 `Engine::set_editor_hint(true)` 注册后立刻还原**（`tests/test_mcp_server.cpp:115-131`），
    不再存在任何绕过 ToolBuilder 的注册入口。
- `docs/DESIGN-DETAIL.md §17.2`（`:358-368`）写明「所有组必须经 `ToolBuilder` 注册」+ review 用的机械检查。

**贴出证明（编译期拒绝 + 运行期用例）**

```
$ grep -rn "\.register_tool(" modules/mcp_server/ --include=*.cpp --include=*.h
modules/mcp_server/tools/tool_builder.cpp:143:	return r_registry.register_tool(built);      # 全模块唯一调用点

# 变异检验：把 register_tool 临时放回 public，重新编译
$ scons platform=windows target=editor module_mono_enabled=no tests=yes -j8
.\modules/mcp_server/tests/test_mcp_server.h(97): error C2338: static_assert failed:
  'MCPToolRegistry::register_tool is public again: ToolBuilder is no longer the only registration path (GDR-19 / TASK-003 1.6)'
scons: *** [bin\obj\tests\test_main.windows.editor.x86_64.obj] Error 2
scons: building terminated because of errors.
MUTATION_SCONS_EXIT=2
# 还原后 tool_registry.h sha256 与变异前逐字节相同，重建 EXIT=0
tool_registry.h bytes=7662 sha256=2a55e68dd54c89f79c3274b222f654e719e8a609d45a5d47c5cb39fb560ec696
matches pre-mutation:  True
```
运行期用例通过（门 1）。

### 机制性建议②：并行/串行纪律写入文档

**改了什么**：`docs/DESIGN-DETAIL.md §17.1` 追加「**串行纪律**」段（`:344-354`）：
`tools/registration.cpp` 是所有组**共写的同一处**；**一批只有一个实现者在改树**；
注册行（include + 调用各一行）由该批实现者**单独追加**，任务书不得把它分派给多个并行子代理；
追加顺序以 `docs/tool-groups.json` 为唯一事实源。

**证据（我自跑的 `git merge-file` 三方合并模拟，scratch 在 `%TEMP%\t003-mergefile`）**

```
$ python (构造 ours/theirs：各自在基线 registration.cpp 上追加 1 个 include + 1 个调用)
$ git merge-file -p ours.cpp base.cpp theirs.cpp
merge-file exit code = 2
conflict markers: <<<<<<< = 2  ======= = 2  >>>>>>> = 2
---- merged output（节选）----
 #include "project_read_template.h"
 <<<<<<< ours.cpp
 #include "project_read_analysis.h"
 =======
 #include "project_read_files.h"
 >>>>>>> theirs.cpp
 ...
 	register_project_read_template_tools(r_registry);
 <<<<<<< ours.cpp
 	register_project_read_analysis_tools(r_registry);
 =======
 	register_project_read_files_tools(r_registry);
 >>>>>>> theirs.cpp
```
即：**2 个冲突 hunk（include 区 + 调用区）**，`exit code 2`。任务书/审计的「4 处冲突」是粗粒度计数
（按行/按侧），上面是精确测量值；结论方向一致：**必然冲突**。

---

## 2. 变更文件与「唯一实现点」自查

- `tool_registry.h/.cpp`：private + friend；无其它调用点（grep 见上）。
- `tools/tool_builder.h/.cpp`：唯一注册调用 `:143`；`normalize_project_path` 折叠逻辑；
- `tests/test_mcp_server.h/.cpp`：注册路径收敛 + 2 条新 doctest + D-4 断言扩展；
- `docs/DESIGN-DETAIL.md`：§17.1/§17.2/§17.4；
- `docs/tools_list.renamed.json` + `scripts/gen_renamed_contract.py`：`order_normative`；
- `docs/TOOL-NAMING.md` + `docs/scripts/gen_table.py`：D-5 护栏 + 重渲染；
- `scripts/accept_m1.ps1`：D-3 括号；
- `docs/reports/REPORT-002-b1-framework.md`：D-2 勘误。

---

## 3. 门（真实输出 + 退出码，全部在**最终二进制**上重跑）

构建命令（与既有基线一致；`bin\*.exe` 不被 git 跟踪）：
`scons platform=windows target=editor module_mono_enabled=no tests=yes -j8` → `EXIT=0`。

### 门 1 `--headless --test --test-case="[MCPServer]*"` → EXIT=0

```
[doctest] test cases:  55 |  55 passed | 0 failed | 1429 skipped
[doctest] assertions: 450 | 450 passed | 0 failed |
[doctest] Status: SUCCESS!
```
基线 53/53·410 → 现在 55/55·450（**+2 例 / +40 断言**，只增不减）。

### 门 2 全引擎 `--headless --test` → EXIT=0

```
[doctest] test cases:   1481 |   1481 passed | 0 failed | 3 skipped
[doctest] assertions: 424731 | 424731 passed | 0 failed |
[doctest] Status: SUCCESS!
```
基线 1479/0/3·424691 → 现在 1481/0/3·424731（+2 例）。

### 门 3 `scripts/accept_m1.ps1` **连跑两次** → 两次 EXIT=0

```
run A:  21/21 cases passed   (PASS=21 FAIL=0 literal{0}=0)
run B:  21/21 cases passed   (PASS=21 FAIL=0 literal{0}=0)
两次 PASS 清单 Compare-Object → 无差异
```
两次的 SUMMARY（关键三行，见 D-3 证据）都打印 `6` 与 `171`；两次都记录
`[PASS] guard_user_port_9877  listening=True pid_before=36392 pid_after=36392`；
`case8_concurrent_100` = `connections=8 sent=100 received=100 unique_ids=100 mismatches=`
（末尾为空是脚本 `($mismatches -join '; ')` 对**空数组**的输出，即 0 条不匹配；该 case 的判定要求
`$mismatches.Count -eq 0`，日志里同一行没有出现任何 `connN: …` 文本）；
`case14_port_occupied` = `blocker_listening=True bind_failed_warning=True get_port_zero=True engine_alive=True`；
`gate_scope_declared` = `implemented=6 contract=171 expected_contract=171`。

### 门 4 `scripts/check_contract_subset.ps1 -Group project_read_template` → EXIT=0

```
contract    : 171 entries
[PASS] editor_9888_contract_subset   editor port=9888 tools=6 order=… | 6 个工具 name/description/inputSchema 全 True
[PASS] game_9889_contract_subset     game   port=9889 tools=6 order=… | 6 个工具 name/description/inputSchema 全 True
[PASS] guard_user_port_9877          pid_before=36392 pid_after=36392
3/3 checks passed
```
（`order=` 只作为**证据打印**，脚本不做顺序断言——与 §17.4 一致。）

### 门 5 `docs/scripts/gen_table.py` 重渲染 + 独立复核 → EXIT=0

```
$ python modules/mcp_server/docs/scripts/gen_table.py   # run1
D-5     rows with exactly 9 cells (split on unescaped '|') = 174/174: PASS
D-5     cells unescaping byte-equal to the map field = 174/174: PASS
D-5     escaped cells ('\|') = 1; rows a naive split('|') breaks = 1 (get_project_info) - asserted, not tolerated
DETERMINISM  render run#1 == render run#2 byte-identical: PASS
ASSERT  rows == 174 : PASS
$ python …gen_table.py   # run2
RUN1 BYTES 98720 SHA256 ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975
RUN2 BYTES 98720 SHA256 ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975
$ python modules/mcp_server/docs/scripts/selfcheck.py
TOOLROWS 174  HEADERS 4  PLACEHOLDERS_LEFT 0  HEADER_FINGERPRINT OK  SECTION7_EVIDENCE EMBEDDED
SELFCHECK  result: PASS
```
独立复核（`%TEMP%\t003-verify_naming.py`，**不 import** 生成器，模拟审计方的读法）：
```
DATA_ROWS 174 (expect 174)      ROWS_NOT_9_CELLS 0
FIELD_MISMATCHES 0              ESCAPED_PIPE_CELLS 1 (map raw '|' count: 1)
NAIVE_SPLIT_BROKEN_ROWS 1       VERIFY PASS   (EXIT=0)
```
头部指纹：头部内嵌的 `tool-rename-map.json` `70917 B / 2f552719…c2bd / 174 → 171` 与映射实测一致。

### 门 6 `scripts/gen_renamed_contract.py` 幂等 + `_meta` → EXIT=0

```
RUN1 BYTES 98953 SHA256 64723fb9fbe8247512171ee4ae8b6950486bad3722cb957091414b73ecf573f5
RUN2 BYTES 98953 SHA256 64723fb9fbe8247512171ee4ae8b6950486bad3722cb957091414b73ecf573f5
tools = 171
_meta.order_normative = False  (type bool)
_meta.count = 171   _meta.tool_count_in = 174   generator_version = 1.3.0
$ git diff --numstat modules/mcp_server/docs/tools_list.renamed.json
2	1	modules/mcp_server/docs/tools_list.renamed.json
```

### 环境/进程收尾

```
$ Get-NetTCPConnection -State Listen | ? LocalPort -in 9877,9888,9889
9877  OwningProcess 36392        # 用户编辑器，能且只能是它
$ Get-Process | ? ProcessName -like 'godot.windows*'   → 空
```

---

## 4. 新指纹（字节数 + sha256）

| 文件（相对 `modules/mcp_server/`） | bytes | sha256 |
|---|---|---|
| `docs/tools_list.renamed.json` | 98953 | `64723fb9fbe8247512171ee4ae8b6950486bad3722cb957091414b73ecf573f5` |
| `docs/TOOL-NAMING.md` | 98720 | `ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975` |
| `docs/tool-rename-map.json`（未改） | 70917 | `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd` |
| `scripts/gen_renamed_contract.py` | 22525 | `e6201603ae0fedbdba7cffcf785db6803d610030a2c12f8de549346a6161506f` |
| `docs/scripts/gen_table.py` | 30073 | `34cf8a944cace924fd180992a72aac819d57c7893dbeaeb62ff3568f8959a597` |
| `scripts/accept_m1.ps1` | 52389 | `022b75d5c05e662faa82abdd2dd23cf600d43c2a8a484cec3bad273658073645` |
| `scripts/check_contract_subset.ps1`（未改） | 17788 | `c167e747627d4c1338149db899985b4b1f03ea353a1b05d62214e5d9bb7528c2` |
| `tool_registry.h` | 7662 | `2a55e68dd54c89f79c3274b222f654e719e8a609d45a5d47c5cb39fb560ec696` |
| `tool_registry.cpp` | 10679 | `c0e6a2123de27cd018c0266b8dc4c60f76312c2bbb393f5ba9543c058a079b4b` |
| `tools/tool_builder.h` | 8642 | `607f9c1b7f9d2ab9892425621d2b4a2522ee7bd46c026883a0f0f4c30cd821a1` |
| `tools/tool_builder.cpp` | 12098 | `6b23a4e5c048acd7c403510704078971beaaf93decf7a5b44dbca99984c29c45` |
| `tests/test_mcp_server.h` | 71939 | `40738fd0a8335f9a16a8a710a997ccc07d03af0091cdc0f637f20768545bbd28` |
| `tests/test_mcp_server.cpp` | 6894 | `a81274d0e8f6e545dc9e0c4fb62d5d60350e1131b79ffd88c1eaa66fc25a667a` |
| `docs/DESIGN-DETAIL.md` | 35409 | `d81601c5576319e595813e763e5fd1d9d999033e3d33d26148932f17b19236a2` |
| `docs/reports/REPORT-002-b1-framework.md` | 37749 | `2e53c029b539b5cfc4d0b41a35075ffc8e04e3bb49fa480c25259d0cabb663b4` |

`docs/tool-rename-map.json` **一个字节都没动**（映射 v1.1 不变；契约只多了 2 行 `_meta`）。

## 5. deviations

1. **`res://a//b` 的既有期望被改了**（`tests/test_mcp_server.h:1277` 起）：D-4 要求「折叠空段」，
   而 HEAD 上的旧行为是 `-32602 must not contain an empty segment`。我按任务书 §1.3 改成折叠
   （`res://a/b`），并**没有**放宽 `..`（仍在折叠前判定，含 `res://a/./../b` 的新断言）。旧错误分支
   因此在代码里消失，`-32602` 只剩「非 `res://`」与「含 `..`」两类。若决策者要保留空段拒绝，
   那与「折叠空段」的指令冲突，需回到阶段三改设计。
2. **D-5 的诊断与 HEAD 事实不符**（转义早已存在，见 §1 D-5）。我按任务书**保留**「转义」这一现状
   （未把 `|` 从映射里拿掉，映射 `reason` 是历史数据），把任务书要求的「174 行恰好 9 列」落成
   **按未转义管道符切分**的断言，并把「天真切分破坏 1 行」也断言下来。若决策者坚持「天真 `split('|')`
   也必须 9 列」，唯一办法是改 `tool-rename-map.json` 的 `reason` 文本（会牵动映射 sha / 文档头 / 契约
   `_meta.map_sha256`），属另一个决策，本任务未做。
3. **`generator_version` 1.2.0 → 1.3.0**：`_meta` 形状变了，按本仓库既有惯例（1.1.0→1.2.0）同步版本号，
   便于审计对账。契约的**工具内容**零改动（diff 只有 2 行）。
4. **`REPORT-002:194` 的旧签名注释**（`// 只允许 res://、禁 .. 与空段`）与 D-4 后的行为不再一致。
   任务书只要求追加 D-2 勘误，因此**没有**改这一行；权威描述是 `DESIGN-DETAIL §17.2`。
5. **`docs/DESIGN-DETAIL.md` 被改了**（§17.1/§17.2/§17.4）：这是任务书 §1.1 / §1.6 / §1.7 的明确要求，
   不是自选动作。
6. **测试侧的注册路径改写**：为满足「唯一注册路径」，`tests/test_mcp_server.cpp` 里 3 处直接
   `register_tool` 与 `tests/test_mcp_server.h` 里 7 处 lint 测试改成经 ToolBuilder；scope 探针
   用**临时翻转 editor hint** 的方式保持原断言不变（不新增任何后门）。
7. 未把 `.graphifyignore` / `build-m0.cmd` / `graphify-out/` / `install-deps-m0.cmd` 纳入提交
   （**在我开始前即未跟踪**，与 TASK-002 报告一致）。

## 6. blockers

无。

## 7. next_step_recommendation

1. 请决策者对 **deviation 1（空段折叠 vs 旧拒绝）** 与 **deviation 2（D-5 的两种读法）** 明确签署；
   两者都已按任务书字面执行，但都触及既有期望/既有事实，值得留一句裁决。
2. 后续并行移植请照 `DESIGN-DETAIL §17.1` 执行：**一批一个实现者**，注册行由该批实现者追加；
   任何组都不得尝试绕开 `ToolBuilder`（现在也绕不开：编译期就会断）。
3. 下一批若新增 `scope=EDITOR` 工具，建议在**游戏进程 9889** 上补一条端到端「`tools/list` 不含它」的证据
   （审计 TASK-AUDIT-002 的 unconfirmed 项 1）；本任务未新增 editor 工具，故未改变该项状态。
4. 独立验收（TASK-AUDIT-003）复核时的最小命令集：门 1/2 的 doctest 命令、门 3 的 accept ×2、
   门 4 的 `-Group project_read_template`、门 5 的 `gen_table.py` + `%TEMP%` 独立复核脚本、
   门 6 的 `gen_renamed_contract.py` 重跑比对 sha，以及 §1「建议①」里的变异编译器检验。
