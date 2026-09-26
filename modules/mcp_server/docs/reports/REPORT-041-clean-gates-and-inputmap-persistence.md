# REPORT-041 — 干净门复跑（释放我方遗留端口 9889）+ `editor_add_input_action` 真的持久化

> 任务书：`docs/tasks/TASK-041-clean-gates-and-inputmap-persistence.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 本报告只报告**模块**的改动与证据；**未改** `docs/DESIGN-DETAIL.md`，**未改**契约/映射/组清单/生成器
> （`docs/tools_list.renamed.json` sha256 = `C844EC8AF9EF00D2E6EC7008C9806B3E2B16757E78794D3CCCA0704EDF844256`，
> 与 REPORT-040 §0 逐字相同），**未新建**任何竞争性规范文档（PLAYBOOK §7.2）。
> 唯一的文档性风险见 §4.3（`docs/tool-groups-b2.json` 的 `notes` 里有一句已过期的行为描述，**我按纪律没有自行改它**，报给决策者）。

---

## 0. 结论速览与锚点（D86）

| 项 | 值 |
|---|---|
| 仓库 / 分支 | `F:\RustProjects\godot-mcp-pro\code\godot` / `feature/mcp-server-module`（**未 push**） |
| **M-6 代码锚点** | `36c485834e` — `mcp_server: TASK-041 M-6 - persist editor_add_input_action into project.godot's [input] and read it back from disk` |
| **门⑤ 修复 + 证据脚本锚点** | `49a99fdf1a` — `mcp_server: TASK-041 clean gates - 9877 guard distinguishes an environment fact from a violation, plus the M-6 wire evidence script` |
| **门⑥ 修复锚点（收窄点标注 + PINNED）** | `96a2dc3331` — `mcp_server: TASK-041 gate 6 - annotate and pin the two new deadzone comparison points, plus the serial gate-battery driver` |
| **门批次的被测提交（本报告全部门与线上证据测自它）** | `6f5b981ac2` — `mcp_server: TASK-041 gate 6 probes - baseline is 73 pinned points now, plus the append-only REPORT-013 erratum` |
| **门的被测二进制** | `4.8.dev.custom_build.6f5b981ac` == `git rev-parse --short=9 HEAD`（`scripts\build_local.cmd -Force`，`tests=yes`，**从 cmd 启动**，串行） |
| 本报告提交 | `100d230673`（本报告本体 + `evidence/task041/**` + 边界探针脚本；**没有**进入二进制的文件）。实测：`git diff --stat 6f5b981ac2 HEAD -- modules/mcp_server/tools modules/mcp_server/tests` **为空** ⇒ 门的被测代码 == 门批次提交 `6f5b981ac2`。本提交之后的补记提交只改本文件（见 git log 末尾） |
| ① 释放我方遗留端口 | **已完成且已核验**：PID 73176 的命令行逐字命中 `--path %TEMP%\mcp-racing-test --mcp-port=9889`，终止后 9888/9889/9877 **全部空闲**（§2） |
| ② M-6 最终状态 | **已实现**：写进 `project.godot` 的 `[input]`（引擎自己的 `save_custom()` 原子发布）、幂等、**从磁盘回读**得 `persisted`；失败诚实 `false` + `persisted_reason`；**未新增参数**、`inputSchema` 零改动（§3） |
| ③ 三条决策项 | O-2 **暂不实现**（确认）；O-3 **不加 `persist` 参数**（确认）；门⑤ 的 9877 断言**改成可区分「环境事实」与「违规」**且**未降低守卫强度**（§5） |
| 门结果一句话 | **① 3/3；② 32/32；③ 277/277（15919 断言）；④ 1703/1703（440201 断言）；⑤ 22/22 ×2 两次**；**⑥ 三段全 0**（73/73 pinned + 17 拼写 + 101/101 探针）；回归脚本群 8 个脚本里 **6 个的唯一失败是「用户 Godot 不在 9877 上」的环境前置断言**，两个 `mcp040` **0 失败**（§7） |
| 契约/组清单/DESIGN-DETAIL | **未改**（sha256 见 §1.3） |

---

## 1. 交付面

### 1.1 提交

| sha | 说明 |
|---|---|
| `36c485834e` | M-6 实现 + 红/绿 doctest（4 文件，+531/−17） |
| `49a99fdf1a` | 门⑤ 的 9877 断言修复 + `mcp041_inputmap_persistence_evidence.ps1`（2 文件，+497/−1） |
| `96a2dc3331` | 门⑥：两个新收窄点的标注 + `PINNED` 登记 + 串行门驱动 `mcp041_gates.ps1`（3 文件） |
| `6f5b981ac2` | 门⑥ 探针脚本的基线点数 71→73 + REPORT-013 的 append-only 勘误（2 文件）**← 门批次测的就是这个提交** |
| `100d230673` | 本报告 + `evidence/task041/**` + 边界探针脚本（只动 `docs/` 与 `scripts/`，见 §10） |

### 1.2 改动文件与 sha256

| 文件 | 字节 | sha256 | 改动 |
|---|---|---|---|
| `tools/tool_helpers.h` | 71 386 | `5d3aceeb340ddc77bfca225518f84698b6fcb1159294b207e59b1d8d3fc8cb9b` | 新增 `class InputMap;` 前向声明 + 5 个 `[input]` 持久化函数声明（含判定依据注释） |
| `tools/tool_helpers.cpp` | 126 111 | `28a51af2f5827f516264f7f83f83c501ca471322a03caa8eb523dd4125c6fe61` | `input_action_setting_key` / `input_action_project_value` / `read_input_action_from_disk` / `persist_input_action_to` / `persist_input_action` 实现 + 两个收窄点的 `// MCP-NARROWING: G24-INPUT-PERSIST-DEADZONE` 标注 |
| `tools/editor_input_simulation.cpp` | 55 262 | `c1a96dc1c667b259c270412422f4cd1a0aca18bed0d81b0a25711a69ba9ccc8d` | `editor_add_input_action` 的成功响应改为「发布 + 回读」；组头注释与工具契约注释同步更新（旧注释说「只改内存、恒回 `persisted:false`」） |
| `tests/test_mcp_server.h` | 954 044 | `090326de28fe9b9baee72540383d408dfdf8e702fcb5070d56578b681d24f190` | 旧用例加 3 条诚实性断言；新增 `TASK-041 an input action is published to project.godot's [input] section...`（41 断言）+ `core/io/config_file.h` include |
| `scripts/accept_m1.ps1` | 66 475 | `8234cce135a8f050165e8f65e6b99250411eafaa02bbb2a14f2c43b4ccc3798d` | 门⑤ 的 `guard_user_port_9877` 改为「记录每个自启进程的 pid **与命令行**」+ 六分类判定（纯 ASCII 增补） |
| `scripts/mcp041_inputmap_persistence_evidence.ps1`（新） | 25 931 | `d682b7e0045325327cb0f5ae08a6d150a5c6c5a9422ca9845dbba8cf10e1d1d3` | 门② 的线上证据链（32 条检查，纯 ASCII） |
| `scripts/mcp041_gates.ps1`（新） | 4 455 | `a05ecab84a94c4fc7950605660dfaf2c334d8c618ad1e61f65ef130bca93839c` | 本轮门批次的串行驱动（纯 ASCII；每步独立日志 + 退出码） |
| `scripts/check_narrowing_points.py` | 50 499 | `ae5aa1c9b252345024738deee6d89e3ebc16eda782a4105eef4ed617f8633e66` | `PINNED` 新增 `tools/tool_helpers.cpp` 的 `G24-INPUT-PERSIST-DEADZONE` 两条（`safe` + 理由） |
| `scripts/mcp031_gate6_coverage_probes.ps1` | 22 403 | `4dc976a5d6e85e22c75d76998015cd581fe739ae3f3bd09c75ab83ceb4e83ee3` | 基线点数期望 71 → **73**（`B1_baseline_scanned_73` / `B1b_restored_scanned_73`）+ 注释里的由来 |
| `docs/reports/REPORT-013-...md` | —— | 见 `git show 6f5b981ac2` | **append-only** 追加「TASK-041 勘误」一节，原文未改 |
| `scripts/mcp041_builtin_action_probe.ps1`（新） | 8 632 | `5d06eefe273cf3e3447dd3a749b1a4d3a3d8062e7a197d93ad4b639c40bc0d13` | §8 的内置动作名（`ui_accept`）边界实测（8 条检查，纯 ASCII） |
| `docs/reports/evidence/task041/**`（新） | —— | 见该目录的 `INDEX.md`（48 个文件的字节数 + sha256） | 门② 原始响应体、红/绿 doctest 日志、门批次日志、边界探针响应 |

> `.ps1` 全部纯 ASCII：`mcp041_*.ps1` 非 ASCII 字节 = 0；`accept_m1.ps1` 的 22 个非 ASCII 字节是**既有**的 `§`（`git diff` 里零新增，已核对）。

### 1.3 未改动的规范面

| 文件 | 字节 | sha256 |
|---|---|---|
| `docs/tools_list.renamed.json` | 110 770 | `C844EC8AF9EF00D2E6EC7008C9806B3E2B16757E78794D3CCCA0704EDF844256`（**与 REPORT-040 相同**） |
| `docs/tool-rename-map.json` | 70 917 | `2F552719F6A23FE328DF0A2944C6048824C1B2A750AEBC0FE2CABBCD3529C2BD` |
| `docs/tool-groups.json` | 5 682 | `0CFCAC80F0D999FA7DB713AE48F43FEBE96AE52E2C93633257EEED00FFDFBFAC` |
| `docs/tool-groups-b2.json` | 11 623 | `14EBA00016C00BFF914BB39AFF9CFB5F01E375A43FA2FF5038D69BDEDFC8B75D` |
| `docs/DESIGN-DETAIL.md` | 71 551 | `7E84BF874934AAFF9129B2558832247ADF8153BB7DEB26495FFB3291FC4E1784` |

---

## 2. ① 释放我方遗留端口（已授权的唯一一次终止）

### 2.1 核实过程（先核实，后终止）

TASK-040 出于纪律没有杀 TASK-039 遗留的游戏进程。本批被授权终止它，**条件是命令行核验**。终止前的实测：

```
> netstat -ano | findstr ":9877 :9888 :9889"
  TCP    127.0.0.1:9889         0.0.0.0:0              LISTENING       73176

> wmic process where "ProcessId=73176" get ProcessId,CreationDate,ExecutablePath /format:list
CreationDate=20260923233644.747779+480
ExecutablePath=F:\RustProjects\godot-mcp-pro\code\godot\bin\godot.windows.editor.x86_64.mono.exe
ProcessId=73176

> wmic process where "ProcessId=73176" get CommandLine /format:list
CommandLine=F:\...\bin\godot.windows.editor.x86_64.mono.exe --headless --path C:\Users\wyl\AppData\Local\Temp\mcp-racing-test --mcp-port=9889 --mcp-trace=C:\Users\wyl\AppData\Local\Temp\mcp-racing-test\trace-game.jsonl

> tasklist /FI "PID eq 73176" /V      → 镜像名 ...mono.exe，Status: Not Responding，PID 73176
```

判定：可执行文件是**本 fork 的构建**、`--path` 指向 `%TEMP%\mcp-racing-test`（TASK-039 的 scratch 工程）、
`--mcp-port=9889`、`--headless` —— **逐字命中任务书 §0.1 描述的进程**。**9877 上没有任何监听者**，
本批次自始至终**没有碰过 9877**（§6 的门⑤ 与 §7 的每个回归脚本都带 9877 断言）。

### 2.2 终止与释放后的干净状态

```
> taskkill /PID 73176 /F
SUCCESS: The process with PID 73176 has been terminated.

> netstat -ano | findstr ":9877 :9888 :9889"
（无输出：三个端口全部空闲）

> tasklist /FI "PID eq 73176" | findstr /i godot
（无输出：进程已消失）
```

之后每一次跑门/回归之前，脚本都会重新断言 `9888`/`9889` 空闲（`mcp041_inputmap_persistence_evidence.ps1`
的 `A02_port_9888_free` / `A03_port_9889_free`，以及 §7 各脚本自己的端口断言），实测全 PASS。
`accept_m1.ps1` 里原本因「9889 被遗留进程占用」而失败的 `case13_game_without_port` 也随之转绿（§6.5）。

> 本批**没有**杀任何其它进程：删除的 PID 只有 73176，且它是**核验过命令行之后**才被终止的。

---

## 3. ② M-6：`editor_add_input_action` 真的持久化

### 3.1 问题（红）与引擎依据

TASK-039/040 在实机试测中实证（`RACING-DEV-LOG` E-4、`RACING-FINDINGS` M-6、证据 `evidence/racing/0075..0076-*.json`）：
该工具只写**编辑器进程的 `InputMap`**，响应老实回 `persisted:false`，**赛车工程的 `project.godot` 里没有任何 `[input]` 段**，
游戏进程 `action_exists=False` → 「工具说创建了，游戏永远看不到」。

引擎里编辑器与游戏两张输入映射**唯一**的汇合点就是 `project.godot` 的 `[input]`：

| 事实 | 源码锚点 |
|---|---|
| 游戏启动时**从工程设置重建**整张映射；`input/<action>` 的值是 `{"deadzone", "events"}`；**没有 `events` 键的条目会被跳过** | `core/input/input_map.cpp:325-358`（`InputMap::load_from_project_settings()`） |
| **编辑器进程根本不会加载工程的 `[input]`**：`editor/project_manager` 分支走 `load_default()`（编辑器自己的内建键），只有游戏分支走 `load_from_project_settings()` | `main/main.cpp:2330-2336` |
| 磁盘形状：`Object(InputEventKey, ...)` 文本；`ConfigFile` 以 `allow_objects=true` 解析它 | `core/io/config_file.cpp:289`；引擎自测 `tests/core/io/test_config_file.cpp:166-203`（`[input]` 段的逐字期望） |
| 32 位浮点写回的是它自己的 float 文本（`0.2f` → `"0.2"`），所以**不能按 double 比较回读值** | `core/variant/variant_parser.cpp:1857`（`rtos_fix`） |
| `ProjectSettings` 把键名里的 `/` 当层级、`.` 当 feature override，所以特殊名字**不能**当一个 key 存 | `core/config/project_settings.cpp:328-344`、`:1312-1319` |

### 3.2 设计（为什么是这个形状）

新增的四个函数（`tools/tool_helpers.*`，与 `publish_project_settings_to` 同一个家，PLAYBOOK §2.4 禁止各组自建副本）：

1. `input_action_project_value(map, action, value, reason)`：**从活的 `InputMap` 取值**（不是从请求），
   产出 `{"deadzone": <map 的>, "events": [<map 的事件对象>]}` —— 因此**第二次同参调用发布的字节完全相同（幂等）**；
2. `read_input_action_from_disk(path, action, expected, reason)`：用**引擎自己的 `ConfigFile`** 重新解析刚发布的文件，
   逐项比对（`deadzone` 按 `float` 比、事件按类名与 `keycode` 比）；
3. `persist_input_action_to(map, action, target, reason)`：`set_setting("input/"+action, value)` → `publish_project_settings_to()`
   （引擎 `save_custom()` 到临时兄弟文件 + rename，**失败时把内存里的设置还原**，与 `project_set_setting` 同规则）→ **从磁盘回读**；
   **返回值就是回读结论**，`reason` 恰好在为 `true` 时为空；
4. `persist_input_action(map, action, reason)`：工具调用的那一个。**只更新已存在的 `project.godot`，绝不新建**
   （doctest 进程跑在引擎源码树上，那里没有工程文件 —— 与 TASK-018 的 `publish_project_settings_to` 同一条纪律）。

工具侧（`tools/editor_input_simulation.cpp`）：

```cpp
String persist_reason;
result["persisted"] = MCPTools::persist_input_action(map, trimmed, persist_reason);
result["persisted_reason"] = persist_reason;
```

- **未新增参数**，`inputSchema` **零改动**（契约逐字门的对象是 `name`/`description`/`inputSchema`）；
- 响应是**超集**（多一个 `persisted_reason`），既有键 `action`/`target`/`created`/`key`/`event_count`/`persisted` 保留；
- 三条**诚实 false + 原因**：进程里没有 `project.godot`；名字含 `/` 或 `.`（`ProjectSettings` 无法当作一个 key）；
  发布失败（`-32603` 的引擎原因被转述进 `reason`）。这三种情况下**内存写仍然完成**（工具原有行为），响应如实说明。

### 3.3 TDD 红 → 绿（真实输出）

**红 A（行为红，可编译，`docs` 未动之前）**：先给旧用例加 3 条诚实性断言，重建后跑
`--headless --test --test-case="*editor input simulation*"`：

```
.\modules/mcp_server/tests/test_mcp_server.h(7579): ERROR: CHECK( created.has("persisted_reason") ) is NOT correct!
  values: CHECK( false )
.\modules/mcp_server/tests/test_mcp_server.h(7581): ERROR: CHECK_FALSE( persist_reason.strip_edges().is_empty() ) is NOT correct!
  values: CHECK_FALSE( true )
.\modules/mcp_server/tests/test_mcp_server.h(7582): ERROR: CHECK( persist_reason.contains("project.godot") ) is NOT correct!
  values: CHECK( false )
[doctest] test cases:   2 |   1 passed | 1 failed | 1703 skipped
[doctest] assertions: 216 | 213 passed | 3 failed |
[doctest] Status: FAILURE!
```

**红 B（新 API 不存在）**：把 5 个函数声明与上面那个新 doctest 先写进去，重建 → **5 个 LNK2019**：

```
tests.windows.editor.x86_64.lib(test_main...) : error LNK2019: unresolved external symbol
  "class String __cdecl MCPTools::input_action_setting_key(class String const &)"
  "bool __cdecl MCPTools::input_action_project_value(...InputMap *...)"
  "bool __cdecl MCPTools::read_input_action_from_disk(...)"
  "bool __cdecl MCPTools::persist_input_action_to(...)"
  "bool __cdecl MCPTools::persist_input_action(...)"
bin\godot.windows.editor.x86_64.exe : fatal error LNK1120: 5 unresolved externals
EXIT_CODE=2
```

> 中间还出现一次**我自己的编译错**：`tool_helpers.h(251) error C2065: "InputMap": undeclared identifier` ——
> `InputMap` 只在 `.cpp` 里被 include，头部缺前向声明。这一版也被真实构建抓到（同一日志），随后在
> `tool_helpers.h` 的既有前向声明块里补 `class InputMap;` 并注明理由。

**绿**（`scripts\build_local.cmd -Force` 重建后）：

```
--test-case="*editor input simulation*"  → test cases: 2 | 2 passed | 0 failed；assertions: 216 | 216 passed
--test-case="*TASK-041*"                 → test cases: 1 | 1 passed | 0 failed；assertions:  41 |  41 passed
[doctest] Status: SUCCESS!
```

新用例覆盖：值形状（`deadzone`/`events`）、`/` 与 `.` 名字被拒且**没有半写文件**、发布 + `ConfigFile` 独立读回、
**把磁盘改回没有该动作后回读必须变 `false`**（「写成功了」与「文件真的改了」的分界）、**幂等（两次发布字节相同）**、
以及在无工程进程里**拒绝且不新建** `project.godot`。

### 3.4 线上证据（门②，32/32 PASS）

`scripts/mcp041_inputmap_persistence_evidence.ps1`，scratch 工程 `%TEMP%\mcp041-inputmap\proj`（初始**没有** `[input]` 段）：

| 证据 | 实测 |
|---|---|
| 写之前 | `sha256=2c144290165de1e7...`，`has_[input]=False`，`has_InputEventKey=False` |
| `editor_add_input_action{action:"mcp041_drive_forward", key:"W"}` | `{"action":"...","created":true,"event_count":1,"key":"W","persisted":true,"persisted_reason":"","target":"editor"}`（226 B，sha256 `6a18bdc8606a4b01...`） |
| 磁盘（**由脚本自己读**，不是由判 `persisted` 的工具读） | `sha256 2c144290... -> 30881da0...`，`[input]` 段 394 B：`mcp041_drive_forward={ "deadzone": 0.2, "events": [Object(InputEventKey, ... "pressed": true, "keycode": 87 ... )] }` |
| 幂等 | 第二次同参调用 `persisted=true / created=false / event_count=1`，**sha256 不变**；不带 `key` 的第三次调用同样 `persisted=true` 且字节不变 |
| 诚实负例 | `action:"mcp041.dotted"` → `{"created":true,"event_count":1,"persisted":false,"persisted_reason":"The action name 'mcp041.dotted' cannot be a project setting key: \`input/mcp041.dotted\` would be read as a feature override by ProjectSettings, so the game could not read the action back under this name. Use a name without '.' (the action was still created in this process' InputMap)"}`；**磁盘上没有它**，而**编辑器内存里有它** |
| **游戏侧（`editor_play_scene` 起的游戏进程）** | `InputMap.has_action("mcp041_drive_forward") = True`；`InputMap.action_get_events(...).size() = 1`；被拒名字在游戏里 `= False` |
| **游戏侧（直接在 9889 上另起的游戏进程）** | 同上三项全部一致 → **不是同一进程的内存，而是启动时从磁盘读到的** |
| 引擎事实（把「错误 oracle」钉住） | 一个**全新的编辑器进程**的 `editor_get_input_actions`（count=89）**仍然不含**该动作 —— 因为 `main.cpp:2333` 给编辑器的是 `load_default()`；这正是「编辑器列表不能当持久化判据」的机器证据（见 §4.2） |
| 收尾 | `9888`/`9889` 全部释放；`9877` owner 前后一致（-1） |

---

## 4. 同类排查：`editor_add_input_action` 的兄弟是否也应能读写工程级输入映射

排查方法：对 `modules/mcp_server/tools/**` 全量检索 `add_action|erase_action|action_add_event|action_erase|action_set_deadzone|get_actions()`，
再对 171 条契约里名字含 `input|action|key|mouse` 的 11 条逐条判定。

| 工具 | 读写的是哪张映射 | 是否该动工程级 `[input]` | 结论与依据 |
|---|---|---|---|
| `editor_add_input_action` | 写**编辑器进程** `InputMap` + 现在**写 `project.godot` 的 `[input]`** | **是**（本次已做） | 唯一会创建 action 的工具（`action_add_event`/`add_action` 的**全部**调用点只有它：`editor_input_simulation.cpp:584,588`） |
| `editor_get_input_actions` | 读**编辑器进程** `InputMap`（`InputMap::get_singleton()->get_actions()`） | **否，且不能靠它判持久化** | 映射 `reason` 明写「reads the editor process' InputMap singleton (not project.godot)」；引擎事实：编辑器进程只有 `load_default()`（`main.cpp:2333`），**永远不会**载入工程 `[input]`（§3.4 实测 count=89 不含该动作）。改它=改既有契约语义与 TASK-013 的结论，**超出本任务授权** → 记为 **O-4 建议**（若要「列出工程级映射」应作为新工具立项） |
| `editor_simulate_input_action` | 只 `Input::parse_input_event()`，并按进程映射回 `in_input_map` | 否 | 不写映射；其 `in_input_map` 是「这次注入能不能动 action 状态」的诚实说明，语义正确 |
| `editor_simulate_key` / `editor_simulate_mouse_click` / `editor_simulate_mouse_move` | 只注入事件（含 GDR-24 的收窄闸门） | 否 | 与映射无关 |
| `editor_simulate_input_sequence` | 只注入事件序列（按帧推进） | 否 | 同上；它按**名字**注入 action 事件，不需要该 action 存在（知识边界已在契约里写明） |
| `running_game_create_input_recording` / `running_game_stop_input_recording` / `running_game_play_input_recording` | 游戏进程侧的录制/回放（事件流） | 否 | 它们从不调用 `add_action`；录制的是事件而不是映射，回放也是注入事件 |
| `editor_set_animation_keyframe` | 动画关键帧，与输入映射无关（仅名字里含 `key`） | 否 | 词面命中，语义无关 |
| **「remove/erase/rename action」类工具** | —— | —— | **契约里不存在**（`grep erase_action modules/mcp_server/tools/**` → 0 命中）。若日后新增，必须**同时**清掉 `input/<action>` 并发布，否则会在 `project.godot` 里留一个「下次启动又读回来」的幽灵条目 → 记为 **O-5 建议** |

**一句话结论**：家族里**只有** `editor_add_input_action` 需要动工程级映射，本次已按引擎语义补齐；
`editor_get_input_actions` **不是**持久化的判据（这是引擎设计而非缺陷），移除类工具在 171 条契约里不存在。

### 4.3 需要决策者处理的文档过期（我按纪律没有自行修改）

`docs/tool-groups-b2.json` 的 `editor_input_simulation` 组 `notes` 里仍写着
「`editor_add_input_action` reports persisted=false because it writes the editor process' InputMap in memory only」。
本批之后这句话**已与行为相反**。它属于**组清单（规范输入）**，按 PLAYBOOK §5「不得修改契约/映射/文档生成器」与
「发现契约有误就停下来报缺陷」的精神，我只报告、不改动（改它还会动到门①依赖的清单 sha）。
**REPORT-013 §3 的逐工具表**同样记着「不落盘 ProjectSettings」，那是历史结论：我按 D86 在
`docs/reports/REPORT-013-b2-closure-editor-input-simulation.md` **append-only 追加了一段勘误**（不改原文）。

---

## 5. ③ 三条决策项的确认

| 决策项 | 结论 | 理由（一句话） |
|---|---|---|
| **O-2**（`editor_add_resource_to_node_property` 的 `old_value`/`new_value` 形状） | **暂不实现**（确认） | `editor` 侧资源写的形状与 `running_game` 侧不同，加它会造出**第二个序列化器**，违反 GDR-25 的单一形状规则；不是本批的收益点 |
| **O-3**（给 `editor_add_input_action` 加 `persist:bool` 参数） | **不加**（确认） | 会动 `inputSchema` → 动 171 条逐字门，且「是否持久化」不是调用方该做的选择（持久化正是这个工具的用途）；若日后要「可选不持久」，应作为**独立契约变更**立项 |
| **门⑤ 的 9877 环境断言** | **已改，且不是恒真**（见下） | 任务是「区分环境事实与违规」，不是「让它变绿」 |

门⑤ 的改法（`scripts/accept_m1.ps1`，新增 56 行，纯 ASCII）：

1. `Start-Engine` 现在把每个自启进程的 **pid 与命令行**都记进 `$script:StartedArguments`；
2. 判定的**不变式**是「**我们**没占用 9877」，它由三条机器事实支撑：
   - 有任何自启进程被要求过 `--mcp-port=9877` → **FAIL**（`violation_this_script_requested_the_user_port`）；
   - 9877 的监听者是我们自己的 pid → **FAIL**（`violation_this_script_owns_the_user_port`）；
   - 9877 一直有监听者但 pid 变了 → **FAIL**（`user_editor_pid_changed_during_the_run`，旧断言在这里也失败）；
   - 9877 **自始至终没有监听者** → **PASS**，且证据行明写 `classification=environment_fact_no_listener_before_or_after`
     （"没人在用"绝不能读成"我们证明了没占用"而看不到理由）；
   - 本来就有监听者且 pid 不变 → **PASS**（`user_editor_present_untouched`）。
3. 证据行现在是：`listening=… pid_before=… pid_after=… ours=… same_pid=… asked_by_us=… classification=…`。

**强度对比**：旧断言要求「9877 上必须有监听者且 pid 不变」；新断言**多**了两条更强的事实（我们的 pid 集合、我们的命令行），
且在「有监听者」的所有情形下**仍然**要求 pid 不变。唯一被放宽的是「一个本来就没有监听者的环境」——
那正是任务书 §1.3 要求区分的那一类，而不是把守卫变成恒真。

实测（门⑤ 两次运行，逐字相同）：

```
[PASS] guard_user_port_9877
       listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True asked_by_us=False classification=environment_fact_no_listener_before_or_after
```

---

## 6. 门（③④①②⑤⑥ 的真实输出与退出码）

### 6.0 门的绑定（R-1）

```
> modules\mcp_server\scripts\build_local.cmd -Force      (tests=yes，从 cmd 启动，串行，未抑制输出)
build_local: exit code = 0

> bin\godot.windows.editor.x86_64.console.exe --version
4.8.dev.custom_build.6f5b981ac
> git rev-parse --short=9 HEAD
6f5b981ac
```

门批次由一个显式串行驱动 `scripts/mcp041_gates.ps1` 执行（每步独立日志 + 退出码，**两个引擎从不同时启动**，
本驱动**不调用 scons**）。`exit code` 逐条如下（原始日志：`%TEMP%\mcp041\gates\summary.txt` 与 `*.log`）：

| 步 | 门 | 退出码 |
|---|---|---|
| `gate3_module_doctest` | ③ 模块 doctest | **0** |
| `gate4_full_doctest` | ④ 全引擎回归 | **0** |
| `gate1_contract_subset` | ① 契约子集逐字（`-Group editor_input_simulation`） | **0** |
| `gate6a_narrowing` | ⑥ 收窄点清单 | **0** |
| `gate6b_narrowing_coverage` | ⑥ `--coverage` | **0** |
| `gate6c_coverage_probes` | ⑥ 探针 101/101 | **0** |
| `gate5_accept_run1` / `run2` | ⑤ `accept_m1.ps1` ×2 | **0** / **0** |
| `gate2_wire_evidence` | ② 线上证据（本批的 M-6 证据链） | **0** |
| `regress_*` | 回归脚本群（见 §7） | 1（**唯一失败是 9877 环境前置断言**） |

### 6.1 ① 契约子集逐字

```
PASS  editor_9888_contract_subset     editor port=9888 tools=148
      editor_add_input_action: name=True description=True inputSchema=True
      editor_simulate_input_action/key/mouse_click/mouse_move/input_sequence: name=True description=True inputSchema=True
PASS  game_9889_contract_subset       game port=9889  tools=69
      editor_add_input_action: correctly absent on the game endpoint
      （六个 editor_* 输入工具在游戏端点全部 correctly absent）
PASS  guard_user_port_9877
3/3 checks passed
```

要点：本批**没有动契约**（§1.3 的 sha256 与 REPORT-040 逐字相同），所以这条门测的是「改动没有漂移契约」——
`editor_add_input_action` 的 `inputSchema` 仍然是 `{action: string, key?: string}`（**未新增参数**），
`description` 逐字未变，而响应新增的 `persisted_reason` 不在契约对象内（契约只钉 name/description/inputSchema）。

### 6.2 ③ 模块 doctest

```
[doctest] test cases:   277 |   277 passed | 0 failed | 1429 skipped
[doctest] assertions: 15919 | 15919 passed | 0 failed |
[doctest] Status: SUCCESS!
```

基线（TASK-040）= 276 用例；本批 **+1**（TASK-041 的新用例 41 断言）。`passed` 只增不减，**0 failed**。

### 6.3 ④ 全引擎回归

```
[doctest] test cases:   1703 |   1703 passed | 0 failed | 3 skipped
[doctest] assertions: 440201 | 440201 passed | 0 failed |
[doctest] Status: SUCCESS!
```

TASK-040 基线 1702 用例；**+1**（同上），**0 failed**。

### 6.4 ⑥ 收窄点三段式（GDR-24）

- `check_narrowing_points.py` → **exit 0**：`scanned 73 / pinned 73`，`unannotated=0 unlisted=0 stale=0`；
- `--coverage` → **exit 0**：17 种已声明拼写（保证的有界集合，脚本自己打印边界）；
- `mcp031_gate6_coverage_probes.ps1` → **exit 0**：**101/101 checks passed**，`B1_baseline_scanned_73` / `B1b_restored_scanned_73`
  全 PASS，探针后 `running_game_read_scene.cpp` sha256 逐字节还原、`git status` 无残留。

> **这一段是本批唯一一次真正的门失败，必须如实记录**：第一次门批次里 `gate6a`/`gate6c` **exit 1** ——
> 我在 `read_input_action_from_disk` 里新加的 **2 个收窄点没有标注**（`scanned 73 / pinned 71`）：
> ```
> FAIL: 2 narrowing point(s) carry no `// MCP-NARROWING:` marker:
>   tools/tool_helpers.cpp:690  const float expected_deadzone = (float)(double)p_expected.get("deadzone", Variant(0.0));
>   tools/tool_helpers.cpp:692  if ((float)stored_deadzone != expected_deadzone) {
> ```
> 修法（提交 `96a2dc3331`）：两点都标 `// MCP-NARROWING: G24-INPUT-PERSIST-DEADZONE` 并在 `PINNED` 里登记理由
> （`safe`：**这是比较自身的宽度，不是写入**——引擎的 `Action::deadzone` 是 `float`，写盘用的是它自己的 float 文本，
> 按 `double` 比会把每一个正常的 `0.2f` 判成不匹配；反过来说，装不进 `float` 的值会变成 `inf` 而比较不等，回读会**诚实拒绝**）。
> 探针脚本里「基线点数 == 71」的期望同步改为 73（提交 `6f5b981ac2`，并在注释里按既有格式追加 71→73 的由来）。
> 这就是 §22.3b 要求的「三腿」：机器检查 + 代码审查（新写路径必须点名它经过哪次闸门）+ 行为证据，三者都在本报告里。

### 6.5 ⑤ `accept_m1.ps1` ×2

```
22/22 cases passed
implemented tools = 148 (editor endpoint) / 69 (game endpoint); contract = 171; known_deviation = per-batch verbatim gate only
```

两次运行的 PASS 清单**逐条一致**（22 条 case，含 `case3_tools_list_fixture`、`case12_game_process_endpoint`、
`case13_game_without_port`、`case14_port_occupied`、`guard_user_port_9877`、`gate_scope_declared`），
两次都 **exit 0**。与 TASK-040 的差别正是本批的两项工作：`guard_user_port_9877` 从 FAIL 变 PASS（§5），
`case13_game_without_port` 从 FAIL 变 PASS（§2 释放了 9889）——**第一次做到门⑤ 全绿**。

### 6.6 ② 线上证据

见 §3.4：`mcp041_inputmap_persistence_evidence.ps1` **32/32 PASS**（exit 0）。
三类证据齐备：成功路径（发布 + 回读 + 幂等）、缺参/非法名（`mcp041.dotted` → `-32602` 级的诚实 false + 原因）、
底层失败（无工程文件的进程 → 诚实 false + 原因，且**不新建** `project.godot`）。
端到端活证据链：`editor_add_input_action` → `project.godot` 字节变化 → **两个独立游戏进程** `InputMap.has_action=True`。

---

## 7. 回归脚本群：逐条归因（不得只报「全绿」）

命令：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts\<脚本>`，串行，9889 已空闲（§2）。
**每个脚本的唯一失败项都是同一类「环境前置断言」**：它要求「用户的 Godot 正在 9877 上监听（pid > 0）」，
而本环境里用户没有开 Godot（`pid=-1`）——**这是环境事实，不是回归**。除此之外**全部转绿**，
包括 TASK-040 首轮因 9889 被遗留进程占用而失败的全部用例。

| 脚本 | 检查数 | 结果 | 唯一失败项（逐字） |
|---|---|---|---|
| `mcp032_d3_d4_d6_evidence.ps1` | 39 | 38 PASS / 1 FAIL | `port_9877_owner_before` — `user Godot on 9877: pid=-1 (never touched)` |
| `mcp033_b5_animation_evidence.ps1` | 75 | 74 PASS / 1 FAIL | 同上 |
| `mcp034_b5_audio_particle_theme_evidence.ps1` | 114 | 113 PASS / 1 FAIL | 同上 |
| `mcp035_b5_tilemap_shader_physics_evidence.ps1` | 67 | 66 PASS / 1 FAIL | 同上 |
| `mcp036_b5_navigation_theme_export_android_evidence.ps1` | 59 | 58 PASS / 1 FAIL | `port_9877_guard_before` — `the user's editor still listens on 9877 (pid=-1)` |
| `probe037_d2_d1_r1r2.ps1` | 40 | 39 PASS / 1 FAIL | `port_9877_owner_before` — 同上 |
| `mcp040_defect_probes.ps1 -Label task041` | 47 | **47 PASS / 0 FAIL** | ——（这条**没有** 9877 前置断言，它只断言「前后一致」） |
| `mcp040_racing_regression.ps1` | 35 | **35 PASS / 0 FAIL** | ——（同上） |

归因细节与 TASK-040 的对照：

1. **9877 的 6 条环境前置断言**（5 个 `port_9877_owner_before` + 1 个 `port_9877_guard_before`）：
   它们的「前后 pid 一致」那一半**全部 PASS**（-1 == -1），失败的是「必须有监听者」这一半。
   与 TASK-040 §9 的归因**完全相同**（当时二轮 416 条里 7 条失败同属这一类）。
   → **建议**：把这 6 处也改成 `accept_m1.ps1` 那样的六分类判定（判据、理由、`classification=` 证据行都已现成）。
   本批**只改了任务书 §1.3 明确点名的 `accept_m1.ps1`**，没有擅自扩大改动面（§8 deviations 第 3 条）。
2. **TASK-040 首轮的游戏侧失败全部消失**：`mcp033` 的 `m4e2_game_reads_the_full_set`、`mcp035` 的
   `scope_9889_project_tool_runs`、`mcp036` 的 6 条 `move*`/`class_*`/`navl*`、`mcp032` 的 5 条 `d6_*`、
   `mcp034`/`mcp030` 的 `port_9889_free`——它们在 TASK-040 首轮失败是因为 9889 上坐着**赛车工程的游戏进程**，
   本批把它核验后释放（§2），于是这些用例拿到的是它们**自己**的 scratch 工程。**逐条转绿**。
3. **`mcp040` 两个脚本 0 失败**：`mcp040_defect_probes` 的 47 条（D-1/D-2/D-3 的红转绿回归）与
   `mcp040_racing_regression` 的 35 条（赛车工程端到端）全绿，其中
   `racing_game_on_9889_untouched` 现在断言的是 `-1 == -1`（遗留进程已被本批核验后终止），语义从
   「别碰别人的进程」变成「这个端口仍是空的」——**不是弱化**：`mcp040_racing_regression` 自己起的游戏子进程
   仍被逐条断言（`port_9889` 释放）并与 9877 的前后一致性一起收口。
4. **`mcp-racing-test` 原工程一字未改**：本批只动了 `%TEMP%\mcp041-inputmap\proj`（新 scratch）。

---

## 8. 边界实测：把**内置**动作名交给这个工具会发生什么

`editor_add_input_action` 发布的是「**该 action 在编辑器 map 里的真实状态**」。名字若是编辑器自己就有的内置动作
（`ui_accept` 等，由 `InputMap::load_default()` 在 `main/main.cpp:2333` 加进编辑器进程），`created` 是 `false`，
但发布路径**照样**会把它写进工程。这一条不是猜的，`scripts/mcp041_builtin_action_probe.ps1` 实测（8/8 PASS）：

```
[Z4_add_builtin_ui_accept] bytes=215 sha256=0dbe623af379e8b35c10e1a41805b2776dc2b71a9126f79b82a400c5ec7f03ec
       {"id":1,...,"text":"{\"action\":\"ui_accept\",\"created\":false,\"event_count\":3,\"key\":\"\",\"persisted\":true,
        \"persisted_reason\":\"\",\"target\":\"editor\"}"...}
[PASS] Z5_builtin_action_is_not_created_but_is_persisted   created=False persisted=True event_count=3
[PASS] Z6_builtin_entry_lands_in_project_godot             sha256 30881da06ddcc571 -> a03c54dd1d2a7242; [input] has 'ui_accept=': True
[PASS] Z7_builtin_entry_carries_the_editors_events         [input] section bytes=1446（4 个 Object(InputEventKey)，其中 3 个属于 ui_accept）
[PASS] Z8/Z9                                               9877 owner 前后一致；9888 释放
```

**这意味着**：对内置名字调用一次，`project.godot` 会多出一条 `input/ui_accept`，内容是**编辑器的那份内置绑定**
（3 个键盘事件），即「把编辑器的默认绑定固化成工程级覆盖」。这**不**是本批的单方面改动所带来的新缺陷
（`project_set_setting` 一直能改 `input/*`，只是 JSON 表达不了事件对象），但它现在是**一个动作名的副作用**，
而且**只有决策者能判**它该不该：
- 对「我想给 ui_accept 再加一个键」的游戏开发者，这个行为是**有用的**（工程里从此有一条显式覆盖）；
- 对「我只想确认这个工具不会乱动我的工程」的调用方，它是**意外的写入**。

→ 记为 **O-6（决策项，不是缺陷）**：是否把「内置动作名」列为**拒绝持久化**（`persisted:false` + 原因，内存写照旧），
或者在 `description` 里写清「内置名会被镜像进 `[input]`」。**本批不改**（改判定即改行为，且 `description` 属契约逐字门的对象）。

---

## 9. deviations / blockers / risks / next_step

### 9.1 deviations（与任务书/手册的显式偏离）

1. **只改了任务书 §1.3 点名的 `accept_m1.ps1`**。同样的「必须有监听者」环境前置断言在
   `mcp032/033/034/035/036` 与 `probe037` 里各有 1 条（`port_9877_owner_before` / `port_9877_guard_before`），
   本批**没有**改它们，只按任务书要求**逐条归因**（§7），并把「照 `accept_m1.ps1` 的六分类改」写成建议。
   理由：任务书只授权了那一处；擅自改 7 个回归脚本会扩大改动面，且它们不是本批的门。
2. **本批多出两个提交**（`96a2dc3331` 门⑥ 标注、`6f5b981ac2` 探针点数 71→73）：第一次门批次**真的红了**
   （我自己新加的 2 个收窄点没标注，`scanned 73 / pinned 71`）。修它是门纪律的硬性要求，且两处改动都只影响门自身。
3. **响应新增一个键 `persisted_reason`**（成功时为空串）。契约逐字门只比较 `name`/`description`/`inputSchema`，
   `inputSchema` **零改动**、参数**零新增**。若决策者认为响应形状也应受 171 条逐字约束，需要重新裁决
   （但响应形状从来不在 `tools_list.renamed.json` 里）。
4. **`editor_get_input_actions` 的语义未改**（它读编辑器进程的 map）。本批把它「不能当持久化判据」这一
   **引擎事实**钉成了机器证据（§3.4 的 `E02`），但没有改它，也没给它加参数 → O-4。
5. **`docs/tool-groups-b2.json` 的过期 `notes` 未改**（§4.3）；`docs/DESIGN-DETAIL.md` 未改；
   `REPORT-013` 只做 append-only 追加（不改原文）。
6. **红阶段的中间态没有单独落提交**：这一次的「红」是「先加 3 条断言 + 先加 5 个声明与新用例」，
   两者都在随后的绿提交 `36c485834e` 里收口；红/绿两次真实构建的输出都记在 §3.3 与证据目录里。
7. **`accept_m1.ps1` 的 `foreign_listener_appeared_during_the_run` 判定为 PASS 并带分类**：
   任务书 §1.3 给的形式是「**若** 9877 有监听者，则必须是别人的」；本实现对「监听者不是我们」这一类放行
   （有 `asked_by_us=False` / `ours=False` 的机器证据），但对「本来有、现在 pid 变了」仍然 **FAIL**。
8. **`ui_accept` 的边界行为未按「应该怎样」修**，只实测 + 记决策项（§8，O-6）。

### 9.2 blockers

**无**。9877 无监听者是**环境事实**，不是阻塞；它是唯一让回归脚本群退出的原因，已逐条归因。

### 9.3 risks（遗留风险，交给决策者）

1. **`project.godot` 会被引擎整体重写**：`save_custom()` 的语义是重新生成整份配置（注释丢失、键序按引擎顺序）。
   这是 `project_set_setting` / `project_add_autoload` 早已有的行为，但 TASK-041 让它成了「加一个输入动作」的副作用。
   本批只在**本来没有注释**的 scratch 工程上实测（字节变化 + 幂等都有证据），**没有**在带注释的真实工程上测「注释是否丢」。
   → 若在意的，是**一次真实工程实测**就能判的事。
2. **未测双精度构建**（继承欠账）：本批新增的比较按 `float` 宽度判定，在 `precision=double` 构建下语义不变
   （引擎的 `Action::deadzone` 仍是 `float`），但没有实跑。
3. **动作名含 `/` 或 `.` 无法持久化**（诚实 `false` + 原因）。这是 `ProjectSettings` 的键名语义边界，不是可修的缺陷；
   但它是**能力边界**，调用方需要从 `persisted_reason` 里读出来。
4. **内置动作名会被镜像进工程**（§8，O-6）——行为已实测，取舍未决。
5. **7 个回归脚本的 9877 环境前置断言仍在**：在「用户没开 Godot」的环境里它们会**永远 exit 1**，
   这会持续污染后续批次的「全绿」判读（TASK-040 已经踩过一次）。

### 9.4 next_step_recommendation

1. **裁决 O-4 / O-6**（都很小）：
   - O-4：要不要给「读**工程级**输入映射」立一个独立工具（当前只有「编辑器进程的 map」这一种读法）；
   - O-6：内置动作名是拒绝持久化，还是在 `description` 里写明「会被镜像进 `[input]`」。
2. **授权把 7 个回归脚本的环境前置断言按 `accept_m1.ps1` 的六分类对齐**（纯脚本、无契约影响），
   让后续批次的回归结果只剩「真回归」这一类失败。
3. **授权一次真实（带注释的）工程实测**，确认 §9.3-1 的影响面，并决定是否需要把「重写整份 project.godot」
   在工具级 `description` 里写清（那会动契约 → 独立变更）。
4. 若要继续「输入动作」这条线：下一步自然是 `running_game_*` 侧**读**工程级映射的能力（当前只有游戏进程的 `InputMap`），
   以及 O-5 的「删除动作也要清 `[input]`」配套。

---

## 10. 结论锚点（D86）与证据清单

- **M-6 的结论**（§3）：测自 `36c485834e`（代码）与 `6f5b981ac2`（门批次）；
  行为自 `36c485834e` 起未再改变（`96a2dc3331` **只加了 11 行注释**，`6f5b981ac2` 只动门脚本与文档）——
  可核对：`git diff --numstat 36c485834e 6f5b981ac2 -- modules/mcp_server/tools modules/mcp_server/tests`
  = `11 0 modules/mcp_server/tools/tool_helpers.cpp`（**纯新增注释，0 行代码**，且 `tests/` 无改动）。
- **① 释放 9889 的结论**（§2）：命令行的观测发生在终止**之前**，未测自任何提交（环境事实），
  其影响面（门⑤ `case13`、回归的游戏侧用例）测自 `6f5b981ac2`。
- **③ 三条决策项**（§5）：O-2/O-3 是**决策确认**（无代码）；门⑤ 的断言改动测自 `49a99fdf1a`，
  其行为证据（`22/22` 两次全绿、`classification=environment_fact_no_listener_before_or_after`）测自 `6f5b981ac2`。
- **门⑥ 的三段式**（§6.4）：测自 `6f5b981ac2` 的工作树（源码扫描，与二进制无关）。
- **本报告提交**：`100d230673`，只加 `docs/reports/REPORT-041-*.md`、`docs/reports/evidence/task041/**`
  与 `scripts/mcp041_builtin_action_probe.ps1`（**没有一个文件进入二进制**）；
  `REPORT-013` 的勘误在 `6f5b981ac2` 里追加；本提交之后的补记提交只改本文件。
  实测：`git diff --stat 6f5b981ac2 HEAD -- modules/mcp_server/tools modules/mcp_server/tests` **为空**
  ⇒ **门的被测代码 == 门批次提交 `6f5b981ac2`**（与 REPORT-040 §0 同一种论证）。

原始证据（本报告内联的每一条都能在这里找到原文）：

| 位置 | 内容 |
|---|---|
| `docs/reports/evidence/task041/INDEX.md` | 48 个证据文件的**字节数与 sha256** |
| `.../task041/inputmap/*.json` | 门② 的原始请求/响应体（`curl.exe -s -o`）+ `checks.json`（32/32） |
| `.../task041/inputmap/Z4_*` | §8 的内置动作名边界探针的原始响应 |
| `.../task041/logs/doctest-red-behaviour.log` | 红 A：3 条失败断言（行为红）的真实输出 |
| `.../task041/logs/doctest-green-*.log` | 绿：216/216 与 41/41 |
| `.../task041/logs/gate-battery-summary.txt` | 门批次的逐步退出码（本报告 §6 的那张表） |
| `.../task041/logs/gate{1,2,3,4,6a,6b,6c}-*.log` | 各门的原始输出（含 `scanned 73 / pinned 73`、`101/101`、`277/277`、`1703/1703`、`3/3`、`32/32`） |

> 红 B（5 个 `LNK2019`）没有单独的日志文件：它的原文是 `scripts\build_local.cmd -Force` 的构建日志片段
> （`%TEMP%\mcp_server_build_local.log`，该文件是**跨批次追加**的，锚点不稳定），本报告 §3.3 逐字抄录了
> 五条未解析符号与 `LNK1120`；复现它只需把 `tool_helpers.{h,cpp}` 里的 5 个定义删掉再构建。

