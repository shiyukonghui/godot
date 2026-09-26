# REPORT-AUDIT-003 — 独立验收：TASK-003 框架修复与加固

- **verdict（总）**：`pass`
  - **机械门（绕过路径不可用）**：**pass** —— 唯一 friend / 唯一调用点 / 变异编译必须失败（已实测 exit 2，已还原并留证）/ 运行期正反路径断言全过。
  - **行为门（路径归一、顺序确定性、D-3、D-5）**：**pass** —— 30 条路径反例全部符合规范且 **0 条逃逸**；`tools/list` 连续两次、跨端口、跨进程逐字节相同；`accept` 两次 SUMMARY 均打印 6/171 且 `{0}`/`{1}` 字面量为 0；`TOOL-NAMING.md` 174/174 行恰好 9 列（按未转义 `|` 切分）。
  - **工程门**：**pass** —— doctest 55/55·450、全引擎 1481/1481/0 failed/3 skipped·424731、accept ×2 各 21/21、subset `project_read_template` 3/3（9888/9889 各 6/6 逐字）、两个生成器重跑幂等且**逐字节复现仓库文件**。
  - **defects：无 medium/high 级**。4 条 low/info 级（1 条陈旧文档、1 条任务书诊断过时、1 条护栏作用域、1 条输入闸门放宽）均已在下方逐条给出证据与建议。
- **独立性**：本人在 TASK-003 实现期间**未参与任何实现**；`docs/reports/REPORT-003-framework-fixes.md`、`DECISIONS.md` D49 的结论**未被采信为证据**，全部结论来自本人自己跑出的输出。
- **验收对象**：分支 `feature/mcp-server-module`，HEAD `995f601d38`。
- **被测二进制**：本人自建 `bin/godot.windows.editor.x86_64.console.exe`（`scons platform=windows target=editor module_mono_enabled=no tests=yes -j8`，EXIT=0）。

---

## 0. 环境纪律与只读性

| 项 | 实测 |
|---|---|
| 用户编辑器 9877 | `TCP 127.0.0.1:9877 LISTENING 36392` —— 每个阶段前后各查一次，**全程未变** |
| 测试端口 | 仅 9888 / 9889；全部探针进程本人自起自灭，收尾时 `9888/9889 LISTENING = 0` |
| 残留进程 | 收尾 `Get-Process godot*` 只剩用户自己的 `36392` |
| scratch | `%TEMP%\audit003\`（另用既有 `%TEMP%\godot-mcp-m1-scratch` 由 accept 脚本自行维护） |
| 仓库写操作 | 仅 1 处：本报告文件。**无任何 git 写操作**（无 add/commit/checkout/stash） |
| 唯一变异 | `tool_registry.h` 临时改 public（§1.2），已按备份逐字节还原 |
| 收尾 `git status --porcelain` | `?? .graphifyignore` `?? build-m0.cmd` `?? graphify-out/` `?? install-deps-m0.cmd` `?? modules/mcp_server/docs/tasks/TASK-AUDIT-003-framework-fixes.md` —— 除本审计任务书（决策者放置的未跟踪文件）外，与实现方声明一致，**工作树无改动** |

### 0.1 指纹核对（我自己算的 sha256）

| 文件 | 字节 | sha256 | 与实现方声称 |
|---|---|---|---|
| `docs/tools_list.renamed.json` | 98953 | `64723fb9fbe8247512171ee4ae8b6950486bad3722cb957091414b73ecf573f5` | 一致 |
| `docs/TOOL-NAMING.md` | 98720 | `ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975` | 一致 |
| `tool_registry.h` | 7662 | `2a55e68dd54c89f79c3274b222f654e719e8a609d45a5d47c5cb39fb560ec696` | 一致 |

---

## 1. 必核 1 —— 绕过路径不可用（最重要）

### 1.1 ① 模块内调用点唯一（自己 grep）

```
$ grep -rn "\.register_tool(" modules/mcp_server/ --include=*.cpp --include=*.h
modules/mcp_server/tools/tool_builder.cpp:143:	return r_registry.register_tool(built);
GREP_EXIT=0

# 更宽的写法（含 -> / :: 调用形式），排除定义行与 `_register_tools`：
$ grep -rn "register_tool(" modules/mcp_server/ --include=*.cpp --include=*.h | grep -v "_register_tools"
tests/test_mcp_server.cpp:86:  (注释)
tests/test_mcp_server.h:74:    (注释)
tools/tool_builder.cpp:143:     return r_registry.register_tool(built);        ← 唯一调用
tools/tool_builder.h:85:      (注释)
tool_registry.cpp:182:       bool MCPToolRegistry::register_tool(...) {     ← 定义
tool_registry.h:122:         bool register_tool(const MCPToolDef &p_def);  ← 声明（private）
$ grep -rn -- "->register_tool\|::register_tool" modules/mcp_server/   # 仅注释/文档命中，无调用
```

**封装面核查（不止 grep）**：
- `tool_registry.h` 只有 **一个** `friend`：`:124 friend class MCPTools::ToolBuilder;`；`tools`（HashMap）与 `order`（Vector）为 **private**，没有返回它们的 public 访问器；
- `tool_registry.cpp` 中写 `tools`/`order` 的语句只有 `:189 order.push_back(...)`、`:191 tools[p_def.name] = p_def;`，**都在 `register_tool()` 内**；`build_tools_list()`/`call_tool()` 只读；
- `tools/registration.cpp` 只调用 `register_project_read_template_tools(r_registry)`，不进注册表。

结论：**除了 `ToolBuilder::register_into()`，没有任何语言层面可达的入库路径**。

### 1.2 ② 变异编译：改回 public → 编译必须失败（已实测并还原）

**变异前**：`tool_registry.h` 7662 B / `2a55e68d…696`，备份到 `%TEMP%\audit003\tool_registry.h.orig`。

**变异**：把 `bool register_tool(const MCPToolDef &p_def);` 从 private 区移到 `public:` 之后（变异后 sha `ff9cbee99e4306ed13955682c32ee25052b0e5e66f97624528c8f8e63271e2a5`）。

**编译输出（真实）**：

```
$ scons platform=windows target=editor module_mono_enabled=no tests=yes -j8
.\modules/mcp_server/tests/test_mcp_server.h(97): error C2338: static_assert failed:
  'MCPToolRegistry::register_tool is public again: ToolBuilder is no longer the only
   registration path (GDR-19 / TASK-003 1.6)'
scons: *** [bin\obj\tests\test_main.windows.editor.x86_64.obj] Error 2
scons: building terminated because of errors.
INFO: Time elapsed: 00:00:25.42
MUTATION_SCONS_EXIT=2   ELAPSED=38.55s
```

**还原证据（同一枚备份覆盖回写）**：

```
restored bytes=7662
restored sha256=2a55e68dd54c89f79c3274b222f654e719e8a609d45a5d47c5cb39fb560ec696
matches pre-mutation: True
$ git status --porcelain        → 只有 4 个既有未跟踪物 + TASK-AUDIT-003 任务书
$ scons ... tests=yes -j8       → scons: done building targets.  RESTORE_SCONS_EXIT=0 (46.5s)
```

### 1.3 ③ 运行期测试确实断言了「正路仍可注册」

```
$ bin\godot.windows.editor.x86_64.console.exe --headless --test \
    "--test-case=[MCPServer] register_tool is unreachable outside ToolBuilder"
[doctest] test cases: 1 | 1 passed | 0 failed | 1483 skipped
[doctest] assertions: 9 | 9 passed | 0 failed |
[doctest] Status: SUCCESS!      GUARD_TEST_EXIT=0
```

该用例（`tests/test_mcp_server.h:795-815`）不只是断言探针为 false：
- **正向**：`register_probe(...)` 经 `ToolBuilder::register_into()` 成功入库，`get_tool_count()==1`；
- **反向**：游戏进程里的 `scope=EDITOR` 工具、GDR-16 lint 不合规的 `project_update_*` 都被拒且计数不变；
- 探针本体是 `static_assert(!RegisterToolAccessProbe<MCPToolRegistry>::is_public, ...)`（`:78-98`）。
- 测试助手本身也走正路，不是后门：`tests/test_mcp_server.cpp:91-95` 的 `register_probe()` 只有 `ToolBuilder builder(...); ... builder.register_into(...)`；`:134-141` 同。

**结论：必核 1 通过。** 附带发现（非缺陷，记为风险 R-3）：该编译期绊线只存在于 `tests=yes` 的测试二进制；语言层面的 private 在**任何**构建里都仍然拦住裸调用，但没有测试参与时不会有自动红。

---

## 2. 必核 2 —— `normalize_project_path`（30 条反例，全部经线上 9888 实测）

方法：在 `%TEMP%\audit003\proj` 造了一个真实工程（含 `res://src/`、`res://a/.hidden/`），起编辑器于 **9888**，对每条输入发 `tools/call project_get_filesystem_tree`（`curl.exe --data-binary @file`）。归一结果从两条路读取：成功时 `tree.path`，目录不存在时 `-32001` 的 `Directory '<归一后的路径>' not found` 消息。

| # | 输入 | 结论 | 实测归一/错误 |
|---|---|---|---|
| 1 | `res://a/./../b` | REJECT | `-32602 must not walk upwards with '..'` |
| 2 | `res://../x` | REJECT | `-32602`（同上） |
| 3 | `res://..` | REJECT | `-32602` |
| 4 | `res://...` | REJECT | `-32602` |
| 5 | `res://a/..b` | REJECT | `-32602` |
| 6 | `res://a/b/../../c` | REJECT | `-32602` |
| 7 | `res://a%2F..%2Fb` | REJECT | `-32602`（不做百分号解码，`..` 直接可见） |
| 8 | `res://a//b` | FOLD | → `res://a/b` |
| 9 | `res:// /` | ACCEPT | → `res://` |
| 10 | `res://.` | ACCEPT | → `res://` |
| 11 | `res://src/.` | ACCEPT | → `res://src` |
| 12 | `res:// ` | ACCEPT | → `res://` |
| 13 | `res://a/b/` | FOLD | → `res://a/b` |
| 14 | `res://a/.hidden/.` | ACCEPT | → `res://a/.hidden`（`.隐藏名` 是普通段） |
| 15 | `res://a/ /b` | FOLD | → `res://a/b`（仅空白段被折叠） |
| 16 | `res:///x` | FOLD | → `res://x` |
| 17 | `res:// / . /` | ACCEPT | → `res://` |
| 18 | `  res://src  ` | ACCEPT | → `res://src`（先 `strip_edges`） |
| 19 | `res://src` | ACCEPT | → `res://src` |
| 20 | ``（空串） | ACCEPT | → `res://` |
| 21 | `user://x` | REJECT | `-32602 must address the project ('res://...')` |
| 22 | `C:/Windows/System32` | REJECT | `-32602` |
| 23 | `C:\Windows\System32` | REJECT | `-32602` |
| 24 | `//server/share` | REJECT | `-32602` |
| 25 | `\\server\share` | REJECT | `-32602`（UNC） |
| 26 | `/etc/passwd` | REJECT | `-32602`（POSIX 绝对路径） |
| 27 | `res:\\x` | REJECT | `-32602` |
| 28 | `RES://src` | REJECT | `-32602`（前缀大小写敏感） |
| 29 | `res:/src` | REJECT | `-32602` |
| 30 | `res://\u0000evil` | FOLD | JSON 的 NUL 变成 U+FFFD（响应字节 `ef bf bd`）→ `res://\uFFFDdevil` → `-32001` |

**机器汇总（真实输出尾段）**：

```
total=30 accepted/folded=14 rejected(-32602)=16 other=0
escape or format violations among accepted outputs = 0
rejection reason histogram: {"contains '..'": 7, 'no res:// prefix': 9}
```

**判定**：
1. **`..` 在折叠之前被拒**：第 1、6 两条（`res://a/./../b`、`res://a/b/../../c`）若先折叠 `.`/空段就会被洗白，实测仍是 `-32602` —— 与 `tool_builder.cpp:281-287`「在原始剩余部分上判定」一致，**实现方的说法成立**。
2. **无项目根之外的逃逸**：14 条被接受/折叠的输出，**全部以 `res://` 开头**，无 `..` 段，无盘符/根斜杠/反斜杠段（violations = 0）。拒绝原因只有两类（含 `..`、缺 `res://` 前缀），没有第三类漏网。
3. **`res://a//b` 由 `-32602` 变为折叠**：与规范一致 —— TASK-003 §1.3 明写「折叠 `.` 段与**空段**（含仅空白段）」，且 `DESIGN-DETAIL.md §17.2:379` 明确写了 `res://a//b` → `res://a/b`。旧行为（`grep 982dd64f82` 的 `if (path.substr(root.length()).contains("//")) → -32602 must not contain an empty segment`）确实被替换；这是一次**输入闸门的放宽，不是安全边界的放宽**（安全边界只有「必须 `res://`」与「禁 `..`」两条，均未被削弱）。记录为 info 级 D-4（见 §9）。

---

## 3. 必核 3 —— D-1 落地

| 要求 | 实测 | 结论 |
|---|---|---|
| 契约 `_meta.order_normative` 为布尔 `false` | `docs/tools_list.renamed.json:3610  "order_normative": false,`；`python: type = bool value = False`；`tools = 171` | ✅ |
| `DESIGN-DETAIL` 写明「顺序非规范但引擎必须确定性」 | `§17.4`（`:392-403`）：顺序不是契约、**任何实现都不得为对齐契约顺序而重排注册**、同一次构建内连续两次 `tools/list` 必须逐字节相同、给出实现依据（插入序）与护栏名 | ✅ |
| 确定性 doctest 存在且通过 | `--test-case="[MCPServer] tools/list is byte-identical across consecutive calls"` → 1 case / **7 assertions passed**，EXIT=0 | ✅ |
| **自己构造两次调用并比较字节（9888/9889）** | 见下 | ✅ |

**本人自测（真实响应体，非脚本自述）**：

```
9888  call#1  sha256 a726b11a5e00a95b049b114c080479fbcb373f00989a6543c5853053ca90c743  2024 B
9888  call#2  sha256 a726b11a5e00a95b049b114c080479fbcb373f00989a6543c5853053ca90c743  2024 B   → 逐字节相同
9889  call#1  sha256 a726b11a5e00a95b049b114c080479fbcb373f00989a6543c5853053ca90c743  2024 B
9889  call#2  sha256 a726b11a5e00a95b049b114c080479fbcb373f00989a6543c5853053ca90c743  2024 B   → 逐字节相同
id=7 响应把 "id":7 换成 "id":1 后与 id=1 响应完全相等  →  id 是唯一差异
第二次启动的独立进程（同工程、同二进制）→ 仍为 a726b11a…  →  跨进程亦逐字节相同
```

**关于「doctest 是否真能发现问题」**：它比较了①同一注册表两次、②**两个独立构建的注册表**、③换 id、④游戏进程视角。②是关键——若实现改成遍历 `HashMap`，①仍可能碰巧相同，②才有区分力。但仍留一个作用域问题：①②④都在**同一进程**内，而 Godot 的 `HashMap` 无逐实例随机化，同序构建的两张表在同一进程会同样迭代，因此**若真有 hash 序泄漏，单进程断言未必能红**。我用「重启进程再比字节」补强了这一点（上表最后一行）。记为风险 R-2，不构成门失败。

---

## 4. 必核 4 —— D-3（accept ×2）

```
run A:  21/21 cases passed                        ACCEPT_RUN1_EXIT=0
run B:  21/21 cases passed                        ACCEPT_RUN2_EXIT=0

两次 SUMMARY 关键三行（逐字相同）：
implemented tools      : 6 / contract 171
known_deviation        : per-batch gate, NOT a full-contract gate (6 of 171 contract entries are
                         implemented and compared verbatim); unimplemented tools are deliberately
                         absent from tools/list (GDR-7)
implemented tools = 6; contract = 171; known_deviation = per-batch verbatim gate only

正则 \{0\} / \{1\} 命中数：   run A: 0 / 0        run B: 0 / 0
PASS 行数 / FAIL 行数：       21 / 0              21 / 0
Compare-Object(run A 的 PASS 清单, run B 的 PASS 清单) → 空（PASS 清单完全一致）
两次都记录：[PASS] guard_user_port_9877  pid_before=36392 pid_after=36392
```

**根因独立复现（把修前/修后表达式原地跑一遍，不依赖实现方叙述）**：

```
=== OLD (pre-fix, 逐字取自 982dd64f82:scripts/accept_m1.ps1:1046-1048) ===
known_deviation : per-batch gate, NOT a full-contract gate ({0} of {1} contract entries ...   ← 字面量！
=== NEW (HEAD, 内层括号) ===
known_deviation : per-batch gate, NOT a full-contract gate (6 of 171 contract entries ...     ← 正确
```

即：`-f` 比 `+` 结合更紧，缺内层括号时只有最后一段参与格式化。**D-3 修复有效且必要。**

---

## 5. 必核 5 —— D-5 与生成器

### 5.1 `gen_table.py` 两次重渲染逐字节相同，且复现仓库文件

把 `gen_table.py` / `template.md` / `tool-rename-map.json` 复制到 `%TEMP%\audit003\gt\`（仓库文件不被写），跑两次：

```
run#1 EXIT=0  sha256 ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975
run#2 EXIT=0  sha256 ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975
RUN1==RUN2 byte-identical
仓库 docs/TOOL-NAMING.md  同 sha  →  REPRODUCES_REPO_BYTE_IDENTICAL
```

### 5.2 「全部 174 行恰好 9 列」——用我自己的解析器复核（不 import 生成器）

我自己写了 `%TEMP%\audit003\d5_check.py`，直接读仓库 `TOOL-NAMING.md` 与 `tool-rename-map.json`：

```
doc bytes=98720 sha256=ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975
rows whose first cell is a map old_name AND that split into 9 cells = 174
shape-matched tool rows that are NOT 9 cells = 0
escaped-pipe cells in tool rows = 1 ; rows naive split('|') breaks = 1 ['get_project_info']
rows matched to map = 174 ; field mismatches = 0
unique names = 174 / map = 174 ; duplicates = [] ; missing = []
map entries whose reason carries a raw '|': ['get_project_info']
```

生成器自身的输出（异步交叉验证，同为真实输出）：

```
D-5  rows with exactly 9 cells (split on unescaped '|') = 174/174: PASS
D-5  cells unescaping byte-equal to the map field = 174/174: PASS
D-5  escaped cells ('\|') = 1; rows a naive split('|') breaks = 1 (get_project_info) - asserted, not tolerated
TABLE_FINAL  markdown table data rows containing a 9-column tool row = 174
```

**结论：174/174 行按未转义 `|` 切分恰好 9 列，且每个单元格反解后与映射字段逐字节相等。**

### 5.3 独立核实「HEAD 处 `\|` 转义早已存在」——**实现方说法成立**

```
$ git show HEAD~2:modules/mcp_server/docs/scripts/gen_table.py > %TEMP%\audit003\gen_table_HEAD2.py
HEAD2 bytes=25710 sha256=54bb66645e698b922d338cc7f58a618e16171955c154de8dd35362411613410b
$ grep -n 'replace' …gen_table_HEAD2.py
194:    return s.replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ").replace("\r", " ")
（HEAD~2 与更早的 3de118ac2d 同 sha；TASK-002 的 8400dae1e8 版本为 710c4f8c…）

$ git show HEAD~2:modules/mcp_server/docs/TOOL-NAMING.md | grep -n 'get_project_info'
326:| `get_project_info` | … | 读取项目元信息（ProjectSettings 的 application/config/name\|version …
                ↑ 在 TASK-003 之前，表格行里就已经是 \| 转义形态

$ git diff --stat 982dd64f82 1b90ba8336 -- modules/mcp_server/docs/scripts/gen_table.py
 1 file changed, 86 insertions(+)          ← 只新增断言，一行转义逻辑都没改
```

**判定：决策者任务书里的 D-5 诊断（「渲染时没有 `\|` 转义」）确实过时。** 真实的、先前就存在的症状是「天真 `split('|')` 会把 `get_project_info` 那行切成 10 列」——这恰恰是**转义正确**的必然结果。实现方按「未转义管道符切分 + 硬断言裸 `|` 归属与数量」来落地任务书「174 行 9 列」的字面要求，是**在两种读法不可能同时成立时的正确读法**。记为 info 级 D-2（建议决策者签署，实现方 §5 deviation 2 已自陈）。

---

## 6. 另核 6 —— 四道工程门（本人重跑）

| 门 | 命令 | 真实输出 | 退出码 |
|---|---|---|---|
| doctest（模块） | `--headless --test "--test-case=[MCPServer]*"` | `55 \| 55 passed \| 0 failed \| 1429 skipped`；`assertions: 450 \| 450 passed` | 0 |
| 全引擎 | `--headless --test` | `1481 \| 1481 passed \| 0 failed \| 3 skipped`；`assertions: 424731 \| 424731 passed \| 0 failed` | 0 |
| accept ×2 | `scripts/accept_m1.ps1` | 21/21、21/21，SUMMARY 6/171（见 §4） | 0 / 0 |
| subset | `scripts/check_contract_subset.ps1 -Group project_read_template` | `contract: 171 entries`；editor 9888 `tools=6` 6×name/description/inputSchema 全 True；game 9889 同；`guard_user_port_9877 pid_before=36392 pid_after=36392`；`3/3 checks passed` | 0 |

契约/表格两个生成器的幂等门（本人另跑，见 §5.1 与下）：

```
gen_renamed_contract.py  run#1 EXIT=0 → sha256 64723fb9fbe8247512171ee4ae8b6950486bad3722cb957091414b73ecf573f5
gen_renamed_contract.py  run#2 EXIT=0 → sha256 同
RUN1==RUN2 byte-identical ; 与仓库 docs/tools_list.renamed.json 亦逐字节相同
输出：input tools = 174 / output tools = 171 / order_normative = false / merged = 1 / unregister = 2 /
      description overrides = 7 / self-checks = OK (lint 171/171, unique 171/171, disposition enum OK)
```

---

## 7. 另核 7 —— `REPORT-002` 勘误段

```
$ git log --oneline -- docs/reports/REPORT-002-b1-framework.md
1b90ba8336  mcp_server: TASK-003 framework fixes - order contract, path folding, single registration path
05908477e7  mcp_server: REPORT-002 - B1 framework and project_read_template group

$ git diff --numstat 982dd64f82 1b90ba8336 -- docs/reports/REPORT-002-b1-framework.md
26	0	docs/reports/REPORT-002-b1-framework.md          ← +26 / −0：纯追加
$ wc -l …REPORT-002-b1-framework.md → 560
$ grep -n '^## 10\. 勘误' → 538          ← 与 REPORT-003 声称的 ":538-560、全文 560 行" 一致
$ git diff --quiet HEAD -- …/REPORT-002… → CLEAN（工作树 = HEAD）
```

勘误段内容与**我自己的复现**逐项一致（在 `%TEMP%\audit003\proj` 里造 `src/case_target.gd`：三行 `FooBar` / `foobar` / `FOOBAR`，pattern 取 `FOOBAR`）：

```
project_search_file_contents          → {"count":3,"matches":[{line:3,"FooBar"},{line:4,"foobar"},{line:5,"FOOBAR"}]}
                                        （大小写不敏感，3 命中）
project_find_files_referencing_symbol → {"count":1,"matches":[{"file":"res://src/case_target.gd","lines":[5]}]}
                                        （大小写敏感，1 命中）
```

即 **3 vs 1**。勘误段「原叙述 `count:0` 有误、可复现的一对数字是 3 vs 1」**成立**；且**原文一字未改**（diff −0）。✅

---

## 8. 另核 8 —— 文档不一致的严重性判定

- 事实：`docs/reports/REPORT-002-b1-framework.md:194` 仍是
  `bool normalize_project_path(...); // 只允许 res://、禁 .. 与空段`；
  而 D-4 之后**空段被折叠**（`res://a//b` → `res://a/b`）。**不一致成立**，实现方的自述准确。
- 现状权威描述：`docs/DESIGN-DETAIL.md §17.2:377-379`（允许 `res://`；在折叠**之前**判 `..`；折叠 `.` 段与空/仅空白段；并点名 `res://a//b` → `res://a/b`）——这是被 TASK-003 明确要求更新的设计文档，与代码一致。
- 严重性：**low（纯文档，零功能影响）**。REPORT-002 是**历史批次报告**，不是规范来源；本仓库对历史报告已确立「追加勘误、不改原文」的惯例（D-2 就是这么做）。且该处不影响任何门与任何运行行为。
- 建议：不必改代码；如要收口，在 REPORT-002 的 §10 勘误里追加**一行**指向 `DESIGN-DETAIL §17.2`（保持 −0 惯例），或者在 DECISIONS.md 里记一句「REPORT-002:194 为历史文本，现行规范以 DESIGN-DETAIL §17.2 为准」。

---

## 9. defects（severity / claim / evidence / location / recommendation）

| id | severity | claim | evidence | location | recommendation |
|---|---|---|---|---|---|
| D-A-1 | **low** | 文档陈旧：旧签名注释仍写「禁 .. 与空段」，与 D-4 后的折叠行为不符 | 见 §8；`+26/−0` 的 diff 说明原文确实未动 | `docs/reports/REPORT-002-b1-framework.md:194` | 在 §10 勘误追加一行指向 `DESIGN-DETAIL §17.2`，或在 DECISIONS.md 记一句；**无需改代码** |
| D-A-2 | **info** | 任务书 D-5 的诊断过时（转义早已存在），字面验收「174 行按 `|` 切 9 列」在映射含裸 `|` 时不可能成立；实现方改用「按未转义 `|` 切分」 | 见 §5.3：`HEAD~2` 的 `esc()` 已在；`git diff --stat` = +86/−0；本人独立解析器 174/174×9 | `docs/tasks/TASK-003-framework-fixes.md §1.4` vs `docs/scripts/gen_table.py:255-330` | 决策者对该读法**明确签署**（实现方 §5 deviation 2 已自陈）；若坚持天真切分，唯一出路是改 `tool-rename-map.json` 的 `reason` 文本（牵动 map sha/文档头/契约 `_meta.map_sha256`），属另一个决策 |
| D-A-3 | **low（测试强度）** | 编译期绊线只存在于 `tests=yes` 的测试二进制；无测试参与的构建里，若有人把 `register_tool` 改回 public，不会自动红 | §1.2 的变异是在 `tests=yes` 下红的；`static_assert` 位于 `tests/test_mcp_server.h:97` | `tool_registry.h:122` + `tests/test_mcp_server.h:78-98` | 保持现状可接受（语言层 private 在任何构建都拦住裸调用）；若要更强的机制，可把访问探针做成 `static_assert` 放在**模块自身**的某个 TU（不依赖 tests） |
| D-A-4 | **info** | 输入闸门放宽：`res://a//b` 由 `-32602`（空段）变为折叠 | §2 第 8 条线上实测 `→ res://a/b`；`git show 982dd64f82` 的旧分支为 `must not contain an empty segment` | `tools/tool_builder.cpp:288-305` | 与任务书 §1.3、`DESIGN-DETAIL §17.2` 一致，**无安全影响**（逃逸检查 0 违规）；建议在 DECISIONS.md 对该行为变更留一句签署（实现方称 D49 已含） |

**无 medium / high 级缺陷。** 需要特别说明：本人**没有**发现任何可绕过 `ToolBuilder` 的注册路径、任何项目根之外的路径逃逸、任何顺序/指纹漂移。

---

## 10. unverifiable

1. `tools/registration.cpp` 的三方合并冲突**精确条数**（任务书称「4 处冲突」，REPORT-003 称 `exit 2` + 2 个 hunk）—— 不属本次 8 项必核，本人**未重跑** `git merge-file` 实验。**已核实**的是 `DESIGN-DETAIL §17.1:344-354` 确实写入了任务书 §1.7 要求的串行纪律（一批一个实现者改树、注册行由该批实现者单独追加、以 `tool-groups.json` 为唯一事实源）。
2. 契约 171 条中**尚未移植**的 165 条与引擎的一致性——本批只 live 6 个工具，其余无法在本次验收中建立（GDR-7：未移植工具不得出现，这是设计使然）。
3. `REPORT-003` 引用的 `docs/scripts/selfcheck.py` 输出——本人**未重跑该脚本**，改用**自己的**解析器独立复核了同一对象（§5.2），结论一致。

---

## 11. risks

- **R-1（中低）** 覆盖面：当前 live 契约门只覆盖 6/171（本批全部实现），任何「全契约绿」的读法都不成立。`accept_m1.ps1` 已在 SUMMARY 里显式声明 `per-batch gate, NOT a full-contract gate`，方向正确；后续批次仍应保持这一声明。
- **R-2（低）** 确定性断言的**作用域**：随包 doctest 的四组断言都在单进程内，理论上无法排除「确定性 hash 序」的实现（Godot `HashMap` 无逐实例随机化，同序构建会在同进程同样迭代）。本次验收用**跨进程重启再比字节**补强（相同 sha），但该补强**不在随包门里**。建议后续把「重启进程后 `tools/list` 仍逐字节相同」纳入 accept 脚本，做成常设门。
- **R-3（低）** 见 D-A-3：编译期绊线依赖 `tests=yes` 构建。
- **R-4（低）** `..` 判定是朴素的 `path.contains("..")`，因此名为 `..b`（`res://a/..b`）或 `res://...` 的**合法**路径也一律被拒。这是**任务前既有**的保守行为，本批未改；属可用性小刺，不是安全缺陷（安全性优先，维持现状可接受）。
- **R-5（低）** `res://\u0000evil` 不被显式拒绝，NUL 在 JSON 解析阶段变成 U+FFFD 后进入路径，最终 `-32001`。无逃逸（仍 `res://` 前缀），但「路径参数不做控制字符校验」值得在后续批次留意。

---

## 12. next_step_recommendation

1. **可以进入下一批（B1 其余组）的移植**：本次三向门（机械/行为/工程）全绿，绕过路径、路径安全边界与顺序确定性都有可复现证据。
2. **请决策者对两处自陈偏差签署**：deviation 1（`res://a//b` 空段折叠，D-A-4）与 deviation 2（D-5 的「未转义管道符」读法，D-A-2）。两者都已按任务书字面/精神落地，但触及既有期望与既有事实，值得留一句裁决；`DECISIONS.md` 只读，建议落在 hof-rs 侧或本模块 DESIGN-DETAIL。
3. **顺手收口 D-A-1**：REPORT-002 §10 追加一行指向 `DESIGN-DETAIL §17.2`（保持「追加不改原文」惯例）。
4. **把「跨进程 `tools/list` 逐字节相同」加进 accept 脚本**（R-2），把确定性从「同一进程内」提升为「跨进程/跨构建」的常设门。
5. 蘸后即用：后续并行移植遵守 `DESIGN-DETAIL §17.1`（一批一个实现者改树，注册行由该批实现者单独追加），任何组都不得尝试绕开 `ToolBuilder`——现在也绕不开（编译期即断，§1.2 已实测）。

---

## 13. 附：本审计用到的复现命令（scratch 全在 `%TEMP%\audit003\`）

```powershell
# 构建
scons platform=windows target=editor module_mono_enabled=no tests=yes -j8

# 门 1 / 门 2
bin\godot.windows.editor.x86_64.console.exe --headless --test "--test-case=[MCPServer]*"
bin\godot.windows.editor.x86_64.console.exe --headless --test

# 门 3 / 门 4
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\check_contract_subset.ps1 -Group project_read_template

# 生成器（输出进 %TEMP%，仓库只读）
python modules\mcp_server\docs\scripts\gen_table.py                 # 在 %TEMP% 的副本上跑两次
python modules\mcp_server\scripts\gen_renamed_contract.py --out %TEMP%\audit003\contract1.json

# 变异编译（唯一写仓库的例外，已逐字节还原）
#   tool_registry.h: 把 register_tool 声明移入 public → scons → EXIT=2 → 备份覆盖回写 → sha 相同 → scons EXIT=0

# 线上探针
curl.exe -s -X POST http://127.0.0.1:9888/mcp -H "Content-Type: application/json" --data-binary "@list1.json"
python %TEMP%\audit003\normalize_probe.py 9888     # 30 条路径反例
python %TEMP%\audit003\d5_check.py                 # 独立的 174 行 × 9 列复核
```
