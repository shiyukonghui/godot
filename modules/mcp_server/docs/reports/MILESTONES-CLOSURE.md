# MILESTONES-CLOSURE — M0..M5 的闭合清单（在 HEAD `595607336d` 上重跑）

> **TASK-048 追加（HEAD `019c4b019`）**：本文件 §4 原来的「**未跑**」条目已被**真实结果**替换——
> `mcp041/042/043_gates.ps1` 三个门批次聚合器与 `mcp044/045/046` 三条捕获/成本证据脚本
> 已在 HEAD `019c4b019` 上**串行**跑完、**全部 exit 0**（详见 §4）；§3.2 与 §5 遗留
> 第 1/2/4 条也已按 TASK-048 的结果复核（§5、§5.1）。§0~§3 与 §2 的门表本身**未改**，其数字
> 在 §4.3 的最终二进制复核中**逐字复现**。

> **本文件是 TASK-047 section 3 的产出**（任务书 `docs/tasks/TASK-047-milestone-closure-inventory.md`）。
> 目的不是「再宣布一遍全绿」，而是让**任何一个人在这个 HEAD 上、照着本文件的命令、拿到同样可核对的输出**。
>
> 三条自我约束：
> 1. 每一行都给**真实命令 + 日志路径 + 退出码 + 关键输出的原文行**；不写「应该通过」。
> 2. **任何一条红或跑不起来都逐条归因**（§3），并区分「与本次改动有关 / 时代陈旧的不变式 / 预先存在的缺陷 / 环境事实」。
> 3. 明确列出**本批没有重跑**的东西（§4）——不把「没跑」写成「通过」。

---

## 0. 锚点、环境与构建顺序

### 0.1 锚点

| 项 | 值 |
|---|---|
| 仓库 | `F:\RustProjects\godot-mcp-pro\code\godot` |
| 分支 | `feature/mcp-server-module` |
| **HEAD** | `595607336d7e654b6f736285d9bc437b2c76e5ca`（short 9 = `595607336`） |
| 非 mono 引擎 | `bin\godot.windows.editor.x86_64.console.exe`，sha256 `8ec87f58224136a546911dbc27b0e5c28d4ffd9e03fbe677993299f8d2ec2abb`，`--version` = `4.8.dev.custom_build.595607336` |
| mono 引擎 | `bin\godot.windows.editor.x86_64.mono.console.exe`，sha256 `1eab293c0ef502cf7b260c5018547d61fa6ae88dd23a582ce09e8e076016a658`，`--version` = `4.8.dev.mono.custom_build.595607336` |
| 全部本批日志 | `%TEMP%\mcp047-logs\`（`C:\Users\wyl\AppData\Local\Temp\mcp047-logs`） |

### 0.2 环境事实（本批每一次运行都成立，逐条实测）

| 事实 | 实测 |
|---|---|
| 9877 **没有监听者**（用户的 Godot 编辑器未运行） | 每一次运行前后 `netstat -ano -p TCP \| findstr LISTENING` 在 9877 上 **0 命中**，`Get-ListenerPid 9877 = -1` |
| 共享守卫对 9877 的分类 | `classification=environment_fact_no_listener_before_or_after`，`asked_by_us=False`，`our_ports` 只含 `0`/`9888`/`9889`（见 §1 各里程碑的证据行） |
| 测试端口 | 只用 9888（编辑器）/ 9889（游戏）；开工前、**mono 构建开始前**、收尾（恢复构建之后）各核对一次，9877/9888/9889 均无 LISTENING |
| 未 push | 本批只有本地提交 |

> **这条环境事实正是 TASK-047 section 1 要消灭的假红**：三个脚本原先断言「9877 pid 不变**且不为 -1**」。
> 在本环境下 `pid_before = pid_after = -1`，旧谓词的机器求值结果是 **False**（§3.1 有逐条求值），
> 也就是说它们在任何「用户没开编辑器」的机器上**必然报红**，而这条红与本模块的行为无关。

### 0.3 构建顺序（构建一律串行，任何时刻只有一个 scons；**从 cmd 启动**，不抑制输出）

| 序 | 命令 | 结果 | 说明 |
|---|---|---|---|
| 1 | `modules\mcp_server\scripts\build_local.cmd -Force`（`tests=yes`，非 mono） | **exit 0**；`--version = 595607336` == HEAD；日志尾部 `scons: done building targets.` / `EXIT_CODE=0` | 门①..⑥ 与 M0/M1/M2/M4/M5 全部跑在**这个**二进制上 |
| 2 | `D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=yes -j8` | **exit 0**；mono `--version = 4.8.dev.mono.custom_build.595607336` == HEAD（`%TEMP%\mcp047-logs\mono_build.log`） | **唯一允许的第二次构建**；M3 行跑在它上面 |
| 3 | `modules\mcp_server\scripts\build_local.cmd -Force`（恢复非 mono） | **exit 0**（`INFO: Time elapsed: 00:01:46.73`）；`--version` 重新校验 == HEAD | 把 `bin\` 的非 mono 二进制**恢复为当前 HEAD**；恢复后再次确认 9877/9888/9889 无监听 |

> 三次构建**全部串行**：M3 的 mono 构建开始前与结束后都没有第二个 scons 在跑（D62 的假编译错误风险），
> 且未与任何引擎/证据脚本并发。日志路径分别是 `%TEMP%\mcp_server_build_local.log`（序 1 与序 3）与 `%TEMP%\mcp047-logs\mono_build.log`（序 2）。

---

## 1. 逐里程碑

每一行下面的「本批重跑」都是**真的跑过**的命令；日志在 `%TEMP%\mcp047-logs\`。

### M0 — 工具链 + 非 mono 基线构建

| 项 | 内容 |
|---|---|
| 交付物 | `modules/mcp_server/config.py`、`modules/mcp_server/SCsub`、`modules/mcp_server/scripts/build_local.cmd`（含 `tests=yes` 与 `-Force` 的纪律）、`bin\godot.windows.editor.x86_64.console.exe` |
| 验收证据 | `docs/ACCEPTANCE.md` §M0（独立验收 **PASS**，逐项复现）；本文件 §0.3 序 1/序 3 |
| 本批重跑 | `modules\mcp_server\scripts\build_local.cmd -Force`（cmd 启动 → 串行 → 不抑制输出） |
| 真实输出 | `build_local: exit code = 0`；`%TEMP%\mcp_server_build_local.log` 尾 `scons: done building targets.` / `INFO: Time elapsed: 00:01:46.73` / `EXIT_CODE=0`；`bin\godot.windows.editor.x86_64.console.exe --version` → `4.8.dev.custom_build.595607336`，`git rev-parse --short=9 HEAD` → `595607336` |
| 结果 | **PASS** |

### M1 — 模块骨架 + HTTP/1.1 子集 + JSON-RPC 2.0（2 个 B1 工具）

| 项 | 内容 |
|---|---|
| 交付物 | `modules/mcp_server/mcp_server.{h,cpp}`、`mcp_http_server.{h,cpp}`、`mcp_jsonrpc.{h,cpp}`、`tool_registry.{h,cpp}`、`register_types.{h,cpp}`、`tools/tool_builder.{h,cpp}`、`tools/registration.{h,cpp}`、`tools/project_read_template.{h,cpp}`、`tools/tool_helpers.{h,cpp}`、`tests/test_mcp_server.h` |
| 验收证据 | `docs/ACCEPTANCE.md` §M1（14/14 行 PASS + D-1..D-8/U-1..U-5）；`docs/reports/REPORT-AUDIT-003-framework-fixes.md`；**门⑤** `scripts\accept_m1.ps1` ×2 |
| 本批重跑 ① | `powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1`（连跑两次） |
| 真实输出 ① | 两次都 **`22/22 cases passed`，exit 0**；两次的 `PASS/FAIL` 清单**逐行相同**（`Compare-Object` 空）；共同摘要 `implemented tools : 171 / contract 171`、`process split : editor endpoint 148 / game endpoint 69, editor-only 102, game-only 23`、守卫 `guard_user_port_9877` PASS（日志 `accept_m1_run1.log` / `accept_m1_run2.log`） |
| 本批重跑 ② | `scripts\check_contract_subset.ps1 -Group editor_input_simulation`，另加 `-Group editor_write_scene_editor` |
| 真实输出 ② | 两次都 **`3/3 checks passed`，exit 0**；`editor_9888_contract_subset` / `game_9889_contract_subset` / `guard_user_port_9877` 全 PASS；`group=editor_input_simulation tools=6`、`group=editor_write_scene_editor tools=10`，`implemented_union=148 tools (editor) / 69 tools (game)` |
| 结果 | **PASS** |

### M2 — B1 + B2 批次（游戏中注入输入 → 观测到变化）

| 项 | 内容 |
|---|---|
| 交付物 | `docs/tool-groups-b2.json`；B1 的 7 个源文件与 B2 的 10 个源文件（逐文件清单由本批机器推导，见 §1.1）：<br>`tools/editor_read_scene_inspector.cpp`、`editor_write_scene_editor.cpp`、`project_read_analysis.cpp`、`project_read_files.cpp`、`project_read_template.cpp`、`project_write_resource_scene.cpp`、`running_game_read_scene.cpp`；<br>`tools/editor_input_read.cpp`、`editor_input_simulation.cpp`、`editor_playback.cpp`、`running_game_capture.cpp`、`running_game_frame_observation.cpp`、`running_game_input.cpp`、`running_game_navigation_write.cpp`、`running_game_node_write.cpp`、`running_game_observation.cpp`、`running_game_script_execution.cpp` |
| 验收证据 | `docs/reports/REPORT-AUDIT-M2.md`（总判决 **pass**，含 1 minor + 3 unconfirmed）；批次报告 `REPORT-010/011/012/013` |
| 本批重跑 ①（B1 走无参数路径） | `python modules\mcp_server\docs\scripts\check_tool_groups.py` |
| 真实输出 ① | **exit 0**，`TOOL-GROUPS CHECK PASS`（`41 == 42 - 1: PASS`、`every name exists in the 171 entry contract: PASS`、`BYTES 5682`、`SHA256 0cfcac80…`） |
| 本批重跑 ② | `python …\check_tool_groups.py --batch B2` |
| 真实输出 ② | **exit 0**，`TOOL-GROUPS-B2 CHECK PASS`；`implemented=true groups = 9, carrying 25 tool(s)`、`25 == 25 - 0: PASS`、`SHA256 14eba000…` |
| 本批重跑 ③（B2 证据脚本） | `powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp010_b2_observation_evidence.ps1 -Phase game` |
| 真实输出 ③ | **exit 0**，**`29/29 checks passed`**；`running_game_execute_gdscript` 注入 → `player_x` 0.0（注入前）… 该相位的活证据链逐条 PASS；守卫行 `guard_user_port_9877 :: listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True asked_by_us=False classification=environment_fact_no_listener_before_or_after our_pids=[79148,53196] our_ports=[0,9889] our_command_lines=4` |
| 另外两项（**同属本脚本，逐条归因见 §3.2**） | `-Phase scope` → `12/13`（exit 1）；`-Phase count` → `4/7`（exit 1） |
| 结果 | 里程碑门**通过**（M2 时代的那两条不变式例外，见 §3.2） |

### M3 — mono 构建 + C# 工程可跑

| 项 | 内容 |
|---|---|
| 交付物 | mono 构建产物 `bin\godot.windows.editor.x86_64.mono.exe` / `.mono.console.exe`（本批重建）、`bin\GodotSharp\**`（含 `Tools\nupkgs\Godot.NET.Sdk.4.8.0-dev.nupkg` 等 5 个本地包） |
| 验收证据 | `docs/reports/REPORT-AUDIT-M3.md`（mono 构建 / C# 可跑 / 模块共存 / 三项修复 / 工程门 / 端口纪律 六类 **pass**）；`REPORT-014-m3-mono-csharp.md` |
| 本批重跑 ① | `D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=yes -j8`（串行；非 `build_local.cmd`，因为要的是 **mono 变体**） |
| 真实输出 ① | `MONO_BUILD_EXIT=0`；`bin\godot.windows.editor.x86_64.mono.console.exe --version` → `4.8.dev.mono.custom_build.595607336` == HEAD |
| 本批重跑 ② | `powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp014_m3_evidence.ps1 -Phase m3 -Engine bin\godot.windows.editor.x86_64.mono.console.exe` |
| 真实输出 ② | **exit 1**：先 6 条 PASS（`m01_sdk_version_available='4.8.0-dev'`、`m02` 4 个本地 nupkg、`dotnet build -c Debug exit code = 0`、`m04` 工程程序集 `Mcp014Csharp.dll (9728 bytes)`、`m05` mono `--version`、`m06` 9888/9889 两个端点在 mono 下都起得来），随后**脚本自身报错中止**（`Write-Utf8NoBom : The term … is not recognized … mcp014_m3_evidence.ps1:183`）。**预先存在的脚本缺陷**，归因见 §3.3 |
| 本批重跑 ③（补上 ② 缺的那一段） | `powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp047_m3_mono_check.ps1`（本批新增，复用 ② 刚构建出来的 C# 工程） |
| 真实输出 ③ | **exit 0，11/11 PASS**：`m3a` mono 构建、`m3b` `--version` == HEAD、`m3c` 程序集存在（9728 B，sha256 `67ea2030…`）、`m3d` 游戏端点在 mono 下就绪、`m3e` `tools/list under mono = 69 tool(s); expected 69`（由契约 171 − `scope=editor` 102 机器推导，不是写死的数字）、`m3f` C# 自己的 stdout `[MCP014-CS] Main._Ready ran; state=csharp-ready`、`m3g` C# 成员 `CsharpTicks`/`CsharpState` 出现在模块读到的属性表里（59 个属性中）、`m3h` `running_game_execute_gdscript → C# CsharpReport() = 'csharp: ticks=352 state=csharp-ready'`、`m3i` C++ 写入 `CsharpState='written-from-mcp'` 后 C# 读回 `state=written-from-mcp`、`port_9877_guard` PASS |
| 本批重跑 ④ | 构建序 3：`build_local.cmd -Force` 恢复非 mono，并重新校验 `--version` == HEAD |
| 结果 | **PASS（要求「重建 mono 构建 + 一个 C# 工程起得来」两条都满足）**，但绕过了 `mcp014` 的脚本缺陷，见 §3.3 |

### M4 — B3 + B4 批次（47 个工具）

| 项 | 内容 |
|---|---|
| 交付物 | `docs/tool-groups-b3.json`（40）+ `docs/tool-groups-b4.json`（7）；源文件 12 + 3（§1.1）：<br>B3：`editor_control_layout_write.cpp`、`editor_node_batch_write.cpp`、`editor_node_instantiate.cpp`、`editor_node_read.cpp`、`editor_node_setup.cpp`、`editor_node_write.cpp`、`editor_script_write.cpp`、`project_autoload_write.cpp`、`project_cross_scene_write.cpp`、`project_resource_uid_read.cpp`、`project_script_write.cpp`、`project_setting_write.cpp`；<br>B4：`editor_testing_read.cpp`、`running_game_assertion.cpp`、`running_game_test_execution.cpp` |
| 验收证据 | `docs/reports/REPORT-AUDIT-M4.md`、`-M4b`、`-M4c`、`-M4d`、`-M4e`（五轮独立验收）；批次报告 `REPORT-015..022` |
| 本批重跑 ① | `python …\check_tool_groups.py --batch B3` 与 `--batch B4` |
| 真实输出 ① | 都是 **exit 0**：`TOOL-GROUPS-B3 CHECK PASS`（`implemented=true groups = 12, carrying 40 tool(s)`、`SHA256 d3422a6e…`）；`TOOL-GROUPS-B4 CHECK PASS`（`implemented=true groups = 3, carrying 7 tool(s)`、`SHA256 d95d7d9e…`） |
| 本批重跑 ②（B4 证据脚本） | `powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp019_b4_evidence.ps1` |
| 真实输出 ② | **exit 0，`TASK-019 evidence summary: 66 checks, 66 passed, 0 failed`**；`H1_user_editor_port_9877_guard :: listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True asked_by_us=False classification=environment_fact_no_listener_before_or_after our_pids=[78264,75524] our_ports=[0,9888,9889] our_command_lines=4` |
| 本批重跑 ③（B3/B4 活证据脚本） | `powershell … mcp027_object_shape_and_paths_evidence.ps1 -Phase green` |
| 真实输出 ③ | **exit 1，59/60**：唯一红是 `[FAIL] D8_whole_resource_bag_round_trips`（`-32602 'Property name 'glow_levels/1' is not a settable property name…'`）——**预先存在的 TASK-027 缺陷**，归因见 §3.4；`port_9877_guard` PASS |
| 结果 | 里程碑门**通过**（例外逐条归因） |

### M5 — B5 批次 + 契约 171/171 收口

| 项 | 内容 |
|---|---|
| 交付物 | `docs/tool-groups-b5.json`（26 组 58 工具）；B5 的 26 个源文件（§1.1），另加 `docs/tools_list.renamed.json`（**171** 条契约）、`docs/tool-rename-map.json`（v1.1） |
| 验收证据 | `docs/reports/REPORT-AUDIT-B5.md`（B5 全 58 工具 + 契约 171/171 收口，总判决 pass）；`docs/reports/REPORT-AUDIT-CAPTURE.md`（TASK-037..046 的捕获/成本链）；`docs/RACING-*.md`（真实工程 T=1 冒烟） |
| 本批重跑 ①（B5 清单） | `python …\check_tool_groups.py --batch B5` |
| 真实输出 ① | **exit 0**，`TOOL-GROUPS-B5 CHECK PASS`；`implemented=true groups = 26, carrying 58 tool(s)`、`SHA256 85bb783e…` |
| 本批重跑 ②（**171/171 收口**） | `python …\check_tool_groups.py --check-completeness` |
| 真实输出 ② | **exit 0**，`TOOL-GROUPS-COMPLETENESS CHECK PASS`；`SOURCE contract entries = 171`、`implemented by the B1/B2 manifests = 66`、`B3 + B4 + B5 = 40 + 7 + 58 = 105 tool(s), each exactly once: PASS`、`B3/B4/B5 disjoint from B1/B2 (66 tools): PASS`、`in_contract_and_not_implemented, both directions of the difference: PASS (missing=0, foreign=0)`、`every claimed name exists in the 171 entry contract: PASS` —— **66 + 105 = 171，恰好各一次** |
| 交叉核对 | `accept_m1.ps1` 独立给出同一组数字：`implemented tools : 171 / contract 171`；`editor endpoint 148 / game endpoint 69`（148 + 69 = 171 + 46 个 both-scope 的重复计数） |
| 结果 | **PASS** |

### 1.1 批次 → 源文件的机器推导（可复跑）

上表的文件清单不是手写的：脚本 `%TEMP%\mcp047-logs\map_batches.py` 读取每个 `tool-groups-bN.json` 中
`implemented=true` 的工具名，再在 `modules/mcp_server/tools/*.{h,cpp}` 中找出现 `"<tool_name>"` 的 `.cpp`，
输出 `%TEMP%\mcp047-logs\batch_files.txt`：

```
B1 implemented=41 tools=41 files=7
B2 implemented=25 tools=25 files=10
B3 implemented=40 tools=40 files=12
B4 implemented=7  tools=7  files=3
B5 implemented=58 tools=58 files=26
```

---

## 2. 五道门 + 门⑥（三段式）：本批的真实输出

| 门 | 命令 | 结果（原文摘要） |
|---|---|---|
| 门① 契约子集 | `check_contract_subset.ps1 -Group editor_input_simulation` / `-Group editor_write_scene_editor` | 两次 **3/3 PASS，exit 0**；`implemented_union=148 (editor) / 69 (game)`，契约 171 |
| 门② 三类证据 | B2 `mcp010 -Phase game`（29/29）、B4 `mcp019`（66/66）、B3/B4 `mcp027`（59/60）、捕获链 `mcp044/045/046`（见 §4） | 三条主证据脚本的请求/响应体都以 `curl.exe -s -o <file>` 落盘并算 sha256；**唯一红见 §3.4** |
| 门③ 模块 doctest | `bin\godot.windows.editor.x86_64.console.exe --headless --test "--test-case=[MCPServer]*"` | **`293 / 293 passed | 0 failed | 1429 skipped`；`assertions: 21431 | 21431 passed | 0 failed`；`Status: SUCCESS!`，exit 0**（与 `REPORT-046` 记录的 293/21431 一致） |
| 门④ 全引擎回归 | `… --headless --test` | **`1719 / 1719 passed | 0 failed | 3 skipped`；`assertions: 445713 | 445713 passed | 0 failed`；`Status: SUCCESS!`，exit 0**（passed 只增不减；`3 skipped` 与 TASK-046 基线相同） |
| 门⑤ 独立验收 | `accept_m1.ps1` 连跑两次 | **两次 22/22，exit 0，PASS 清单逐行相同**（`Compare-Object` 空） |
| 门⑥a 收窄点 | `python modules\mcp_server\scripts\check_narrowing_points.py` | **exit 0**；`scanned : 75 narrowing point(s) in 16 file(s)`、`pinned : 75`；附注「10 pinned line number(s) drifted」是**按 marker id + occurrence 定位**的设计行为，不是失败（§3.5） |
| 门⑥b 覆盖声明 | `… check_narrowing_points.py --coverage` | **exit 0**；打印已声明拼写集合与集合外部分（含探针脚本指引） |
| 门⑥c 覆盖探针 | `powershell -File scripts\mcp031_gate6_coverage_probes.ps1` | **exit 0，101/101 PASS**；`log sha256=7e2a773f9f4bd483018830420b4fd7cdb22d3997f54e0bd7707696b2b3af7bd3` —— **与 `REPORT-046` §12.1 记录的 sha 相同**，即跨批次可复现；其中 `B1b_worktree_clean_of_probes` 证明探针后工作树逐字节还原 |

---

## 3. 逐条归因（所有非绿项与附注）

> 规则：先把红**分类**，再说它是否与本批改动有关。四类：**(A)** 时代陈旧的不变式、**(B)** 预先存在的缺陷、
> **(C)** 环境事实导致的旧断言、**(D)** 本批引入的问题。**本批没有 (D)。**

### 3.1 三个脚本的「9877 前置」旧谓词（TASK-047 section 1 的对象）——(C)

旧谓词在本环境的**机器求值**（用实测 `pid_before = pid_after = -1`）：

| 脚本 | 旧断言（原文） | 求值 | 结论 |
|---|---|---|---|
| `mcp010` | `(($Before -eq $after) -and ($Before -ne -1))` | `False` | 恒红 |
| `mcp019` | `(($userPortPidBefore -eq $userPortPidAfter) -and ($userPortPidBefore -gt 0))` | `False` | 恒红 |
| `mcp027` | `Check 'port_9877_owner_before' ($userPidBefore -gt 0)` | `False` | 恒红（`port_9877_owner_after` 单独看是 `True`，但同一脚本已有另一条恒红） |

对齐后：三者都改为调用 `scripts\mcp_port_guard.ps1` 的**七分类**，并在运行中登记**我们自己启动的每个 pid 与命令行**
（`Register-McpPortGuardProcess` / `Register-McpPortGuardCommandLine`），最后用 `Complete-McpPortGuard` 一次判定。
复跑结果全部为 `classification=environment_fact_no_listener_before_or_after` 且 **PASS**——即「我们没占用 9877」这条**真不变式**被保留并加强
（新增「我们的 pid / 我们的命令行里是否出现过 9877」两条事实），而「用户必须在跑编辑器」这条环境前提被移出断言。

### 3.2 `mcp010` zone scope / count 两相位——(A) 时代陈旧的不变式

| 红项 | 期望 | 实测 | 归因 |
|---|---|---|---|
| `scope_the_editor_game_split_is_exactly_the_scopes` | `editor-only=17, game-only=8`（TASK-010 时代：B1+B2 = 48 工具） | `editor-only=102, game-only=23` | 硬编码的 TASK-010 期不变式。171 工具下的**正确**值由 `accept_m1.ps1` 独立给出：`148/69, editor-only 102, game-only 23`；`check_tool_groups --check-completeness` 也给出 `171 = 66 + 105` 恰好各一次。**与 TASK-047 的改动无关**，也不是回归 |
| `count_implemented_union_is_48` | 48（= B1 41 + B2 **7**） | **66**（= B1 41 + B2 **25**） | 硬编码的是 B2 尚未做完时的并集；B2 在 TASK-013 收口到 25/25 起这条就不成立了 |
| `count_scope_split_is_17_23_8` | 17 / 23 / 8 | 26 / 23 / 17 | 同上（B1+B2 内的 scope 分布随 B2 增长而变） |
| `count_endpoint_expectations` | 编辑器端点 40 | 49 | 同上 |

- `-Phase game`（本批主门）**29/29 PASS，exit 0**：这三条红只存在于 `scope`/`count` 两个相位，且都在「B1+B2 时代」的硬编码断言上。
- **不做静默处理**：这三条/四条要修，应当**回到 TASK-010 任务书明确该脚本的适用范围**（是「B2 批次视角」还是「当前树视角」），
  由决策层决定是改脚本还是标注「历史相位」。本批不做，以免替决策层改断言。

### 3.3 `mcp014 -Phase m3` 中止——(B) 预先存在的脚本缺陷

```
Write-Utf8NoBom : The term 'Write-Utf8NoBom' is not recognized as the name of a cmdlet, function, script file, ...
At F:\...\modules\mcp_server\scripts\mcp014_m3_evidence.ps1:183 char:5
```

- 根因：TASK-028 把本地的 `Write-Utf8NoBom` 替换为 `mcp_import_guard.ps1` 的 `Write-McpUtf8NoBom` 时，**第 183 行漏改**
  （该脚本只 dot-source 了 `mcp_import_guard.ps1`，其中没有旧名字）。
- 影响：`-Phase m3` 在 `m06` 之后必然中止（**与 mono 构建、与本批改动无关**；缺陷在脚本，不在模块）。
- 已做的补救：本批新增 `scripts\mcp047_m3_mono_check.ps1` 接着它跑完 M3 的实质部分（**11/11 PASS**），
  并**没有**顺手改 `mcp014`（它不在 TASK-047 section 1 的 3 个脚本清单里，改它是替决策层扩大范围）。

### 3.4 `mcp027` 的 `D8_whole_resource_bag_round_trips`——(B) 预先存在的缺陷

```
[FAIL] D8_whole_resource_bag_round_trips
       code=-32602 message='Property name 'glow_levels/1' is not a settable property name: Object::set() takes a non-empty identifier'
```

- 已在 `docs/reports/REPORT-AUDIT-CAPTURE.md` §9.1 作为**独立的 TASK-027 对象形态/资源包往返议题**登记过（走的是非捕获路径）。
- **与 9877 前置、与 TASK-047 的改动无关**；该脚本的 9877 守卫行在本批是 **PASS**。其余 59 条（含跨工具链、路径形态）全 PASS。

### 3.5 门⑥a 的「10 pins drifted」附注——非失败

输出明确写着 `the pin is by marker id + occurrence, so this is not a failure`；`scanned = pinned = 75` 且 exit 0。
漂移来自后续批次（TASK-031/033/035/041/045）在同一文件里插入代码。归因为**信息性附注**。

### 3.6 证据采集的一个已知呈现层伪影（如实登记）

mcp047 的**控制台日志**里有中文被 cmd 重定向塌成 `?` 的现象（例如捕获行 `reason` 里的
「headless display server 没有纹理存储」在 `%TEMP%\mcp047-logs\mcp047_graceful.log` 里显示为 `??????????`）。
**不是数据问题**：判定所依据的是**引擎自己写的 JSONL trace 文件**（UTF-8），其**字节数与 sha256 都是从盘上取的**
（`trace-graceful.jsonl`，1223 B，sha256 `2c3ec7f5…`）；脚本自写的 `evidence/evidence.log.txt` 走 `[IO.File]::WriteAllBytes(UTF8)`，也不经过控制台。
这是 PLAYBOOK §7.1 那条纪律（证据不走管道）的**同族风险**，只是本批出现在控制台回显而非响应体上，故显式记下。

---

## 4. TASK-048 补跑：三个门批次 + 三条捕获/成本证据

> **本节由 TASK-048 section 3 改写**（任务书 `docs/tasks/TASK-048-derived-invariants-and-battery.md`）。
> 原 §4 把 `mcp041/042/043_gates.ps1` 与 `mcp044/045/046` 记为「**未跑**」。本批在
> **HEAD `019c4b019`** 上、用该 HEAD 经 `modules\mcp_server\scripts\build_local.cmd -Force`
> 构建出的二进制（`--version` = `4.8.dev.custom_build.019c4b019`）把六者**串行**跑完：
> 三个聚合器**各一个大脚本、内部步骤全部串行**，捕获/成本三条也**逐条串行**，任何时刻只有一个
> 引擎进程、只有一个 scons。原「取舍」说明保留在 §4.4，但其状态不再是「未跑」。

### 4.1 三个门批次聚合器

| 脚本 | 退出码 | 关键计数 | 汇总日志 |
|---|---|---|---|
| `mcp041_gates.ps1` | **exit 0** | **17/17 步骤 EXIT 0** | `%TEMP%\mcp041\gates\summary.txt` |
| `mcp042_gates.ps1` | **exit 0** | **19/19 步骤 EXIT 0** | `%TEMP%\mcp042\gates\summary.txt` |
| `mcp043_gates.ps1` | **exit 0** | **28/28 步骤 EXIT 0** | `%TEMP%\mcp043\gates\summary.txt` |

三个 `summary.txt` 各自声明 `binary --version: 4.8.dev.custom_build.019c4b019` 与
`git HEAD: 019c4b019`，逐步骤退出码原文（`STEP <name> EXIT <rc>`）：

- **mcp041**（17）：`gate3_module_doctest 0`、`gate4_full_doctest 0`、`gate1_contract_subset 0`、
  `gate6a_narrowing 0`、`gate6b_narrowing_coverage 0`、`gate6c_coverage_probes 0`、
  `gate5_accept_run1 0`、`gate5_accept_run2 0`、`gate2_wire_evidence 0`、
  `regress_mcp032 0`、`regress_mcp033 0`、`regress_mcp034 0`、`regress_mcp035 0`、
  `regress_mcp036 0`、`regress_probe037 0`、`regress_mcp040_probes 0`、`regress_mcp040_racing 0`。
- **mcp042**（19）：同上八道门/六条回归，另加 `gate2_rewrite_and_honesty_evidence 0`、
  `gate2b_port_guard_probes 0`、`gate2c_task041_evidence 0`。
- **mcp043**（28）：`gate2f_snapshot_before_contract 0`、`gate3/gate4 0`、
  `gate1a..gate1d`（四个契约分组）`0`、`gate6a/b/c 0`、`gate5_accept_run1/2 0`、
  `gate2a_description_evidence 0`、`gate2b_reload_plugin_probe 0`、`gate2c_probe037 0`、
  `gate2d_rewrite_evidence 0`、`gate2e_task041_evidence 0`、`gate2f_port_guard_probes 0`、
  `gate2g_contract_diff 0`、`gate2h_registration_literals 0`、`gate2i_group_lookup 0`、
  `regress_mcp032..036 0`、`regress_mcp040_probes 0`、`regress_mcp040_racing 0`。

各步骤的关键计数原文：

| 步骤 | 真实输出（原文行） |
|---|---|
| 三个批次的门③/门④ | 均 `test cases: 293 \| 293 passed \| 0 failed \| 1429 skipped` / `assertions: 21431`，以及 `1719 \| 1719 passed \| 0 failed \| 3 skipped` / `assertions: 445713` |
| 门⑤（每批两次，共 6 次） | 均 `22/22 cases passed`；`implemented tools : 171 / contract 171`；`process split : editor endpoint 148 tool(s), game endpoint 69 tool(s), editor-only 102, game-only 23` |
| `gate2_wire_evidence` / `gate2c/gate2e_task041_evidence` | `32 checks, 0 failed` |
| `gate2_rewrite_and_honesty_evidence`（mcp042/043） | `30 checks, 0 failed` |
| `gate2b_port_guard_probes`（mcp042/043） | `21 checks, 0 failed` |
| `regress_mcp032` | `TASK-032 evidence: 38 checks, 0 failed` |
| `regress_mcp033` | `74/74 checks passed`（summary sha256 `37b18a3e…`） |
| `regress_mcp034` | `113/113 checks passed`（summary sha256 `0e510e7b…`） |
| `regress_mcp035` | `66/66 checks passed`（summary sha256 `eda6d7b9…`） |
| `regress_mcp036` | `58/58 checks passed`（summary sha256 `b941cdb4…`） |
| `regress_probe037` | `PROBE037 base: 39/39 checks passed` |
| `regress_mcp040_probes` | `47 checks, 0 failed`（label task041/042/043） |
| `regress_mcp040_racing` | `35 checks, 0 failed` |
| `mcp043 gate2f_snapshot_before_contract` | `806d5396b:…tools_list.renamed.json sha256=c844ec8af9ef… (expected c844ec8af9ef…)` —— 快照逐字节相符 |
| `mcp043 gate2a_description_evidence` | `16 checks, 0 failed`；`143 untouched live descriptions sha256=44f12a29…` 与契约侧同 sha |
| `mcp043 gate2b_reload_plugin_probe` | `14 checks, 0 failed`（`P25b_second_reload_still_succeeded`） |
| `mcp043 gate2g_contract_diff` | `problems = 0`；`changed tools = editor_add_input_action, editor_reload_plugin, project_add_autoload, project_remove_autoload, project_set_setting`；`overrides 18 -> 23` |
| `mcp043 gate2h_registration_literals` | `failures = 0`（4 条工具字面量 `EQUAL`） |
| `mcp043 gate2i_group_lookup` | `rows=5` |

### 4.2 `mcp044` / `mcp045` / `mcp046` 三条捕获/成本证据

| 脚本 | 命令 | 退出码 | 关键计数 |
|---|---|---|---|
| `mcp044_capture_evidence.ps1 -Phase editor` | `powershell -NoProfile -ExecutionPolicy Bypass -File … -Phase editor` | **exit 0** | **`40/40 checks passed (phase editor)`**；三个视口帧互异 `2d=2978x1793 3d=2978x1790 editor=3840x2054`；`duration_ms` 中位数 off `0.0` → every_call `7.0 ms` |
| `mcp044 -Phase headless` | 同上 `-Phase headless` | **exit 0** | **`8/8 checks passed (phase headless)`** |
| `mcp044 -Phase game` | 同上 `-Phase game` | **exit 0** | **`9/9 checks passed (phase game)`** |
| `mcp044 -Phase diff-image` | 同上 `-Phase diff-image` | **exit 0** | **`5/5 checks passed (phase diff-image)`** |
| `mcp045_pixel_compare_cost.ps1 -Label post` | `… -Label post` | **exit 0** | **`15/15 checks passed`**；`changed_pixels=106800 total_pixels=5339554 ratio=0.0200016705515105`（与 TASK-044 的数一致）；第二次同值写入 `changed=False changed_pixels=0`；`png_encoding_expected=fast`；往返中位数 off `0.0234s` / back-to-back `0.1012s` / spaced `0.0321s` / diff 工具 `0.3339s` |
| `mcp046_capture_encode_cost.ps1 -Label post` | `… -Label post` | **exit 0** | **`23/23 checks passed`**；scale1 PNG `113929 / 112102 B`（sha `c2d7a1bf…` / `45160828…`），scale2 `29072 / 29064 B`；`paid_back_to_back_ratio_scale2_over_scale1=0.906`；`curl_round_trip_every_call_scale1_back_to_back` 中位数 `0.0997s` |

三个脚本的 9877 守卫均 **PASS**（本环境 9877 无监听者：`pid_before=-1 pid_after=-1`），
引擎 sha256 与 `--version` 写进各自的 `summary.txt`；`mcp044` 的四个相位各写
`%TEMP%\mcp044-evidence\evidence\summary-<phase>.txt`，`mcp045/046` 写
`%TEMP%\mcp045-evidence|mcp046-evidence\evidence\post\summary.txt`。

### 4.3 门①~⑥ 在本批最终二进制上的复核

`mcp041/042/043` 已各跑一遍门③/④/⑤/⑥；为让证据绑定**最终**产物，本批又在
`build_local.cmd -Force` 恢复非 mono 之后（sha256 `690807df…`，`--version` == HEAD）
独立复跑一次门①③④⑤⑥并把退出码写进 `%TEMP%\task048-final-gates\summary.txt`：
**九个步骤全部 EXIT 0**，且计数与 §2 的表**逐字相同**——门③ `293/293 · 21431`、
门④ `1719/1719 · 445713 · 0 failed · 3 skipped`、门① `3/3`、门⑥a `scanned=75 pinned=75`
（`coverage: 17 declared spelling(s)`）、门⑥c `101/101`（log sha256 `7e2a773f…`，与 §2 同）、
门⑤ `22/22` **连跑两次且 22 行 PASS 清单 `Compare-Object` 为空**、`mcp010 -Phase count` `12/12`。
（门⑥a 打印的 `10 pinned line number(s) drifted` 仍是 §3.5 的信息性附注，非失败。）

### 4.4 仍然**没有**重跑的东西（不写成「通过」）

| 项 | 状态 | 理由 |
|---|---|---|
| M5 的「hof-rs 切端点 + 真实 T=1 冒烟」 | **未跑** | 属 hof-rs 侧（`F:\moonbit-hof-rs`，本模块只读）；`docs/RACING-*.md` 记录的是上一次的真实工程冒烟 |
| clean 全量重建的位级可复现性 | **未验** | 与 `ACCEPTANCE.md` §M0 的 U1 相同，本批只验证到「同命令 → exit 0 → `--version` == HEAD」。实测旁证：同源码两次 `build_local -Force` 产出的 `bin\…console.exe` sha256 不同（`e4060b0f…` → `690807df…`），即本工具链下重建**不是位级可复现**的——与 U1 的结论一致，不影响门判据 |

---

## 5. 结论

| 里程碑 | 本批在 HEAD `595607336d` 上的重跑结论 |
|---|---|
| M0 | **PASS**（`build_local.cmd -Force` exit 0，`--version` == HEAD） |
| M1 | **PASS**（`accept_m1` 22/22 ×2 且清单一致；契约子集 3/3 ×2） |
| M2 | **PASS**（`check_tool_groups` 无参数与 `--batch B2` 均 exit 0；`mcp010 -Phase game` 29/29、exit 0） |
| M3 | **PASS**（mono 重建 exit 0 且 `--version` == HEAD；C# 工程起来、C# 方法过 MCP、C++ 写入被 C# 读到，11/11） |
| M4 | **PASS**（B3/B4 清单 exit 0；`mcp019` 66/66、exit 0；`mcp027` 59/60，唯一红为预先存在的 D8） |
| M5 | **PASS**（`--batch B5` exit 0；`--check-completeness` 给出 **66 + 105 = 171 恰好各一次**） |
| 门①~⑥ | **全绿**：门③ 293/293·21431，门④ 1719/1719·445713（0 failed、3 skipped），门⑤ 22/22 ×2，门⑥a/b/c exit 0 且 `scanned=pinned=75`、探针 101/101（sha 与上批相同） |

**遗留（不阻断闭合，但必须由决策层处置）**——**TASK-048 状态复核**见每条末尾：

1. `mcp010` 的 `scope`/`count` 两个相位含 4 条 **TASK-010 时代硬编码不变式**（§3.2）——需决策层定调「改脚本还是标注历史相位」。
   **TASK-048 section 1 已关闭**：4 条全部改为**派生**（manifest 并集 + rename map 的 scope），
   `-Phase scope` 另加**活端点集合相等**断言；复跑 `15/15` 与 `12/12`，均 **exit 0**（§4.3）。
2. `mcp014_m3_evidence.ps1:183` 的 `Write-Utf8NoBom` **脚本缺陷**（§3.3）——一行可修，但不在本批授权范围内。
   **TASK-048 section 2 已关闭**：改为 `Write-McpUtf8NoBom`；串行重建 mono（`--version == 019c4b019`）后
   `-Phase m3` **跑到底**（18/20）。**新暴露两条红**，见 §5.1——都是本次才看得见的**陈旧不变式**，
   不是回归；不在 TASK-048 授权范围内，**留待决策层**。
3. `mcp027` 的 `D8_whole_resource_bag_round_trips`（§3.4）——TASK-027 议题，仍未修。**TASK-048 未动。**
4. 三个**门批次聚合器**（`mcp041/042/043_gates.ps1`）与 `mcp044/045/046` 未在本批重跑（§4），本文件明确标为「未跑」。
   **TASK-048 section 3 已关闭**：六个脚本全部串行跑完、全部 exit 0，真实结果见 §4；§4 原来的
   「未跑」字样已被替换（仍跑不起来的只剩 §4.4 的两条）。

### 5.1 `mcp014 -Phase m3` 新暴露的两条陈旧不变式（TASK-048 发现，未修）

`Write-Utf8NoBom` 那一行修好之前，`-Phase m3` 在 `m06` 之后必然中止，因此下面两条**从来没有被跑出来过**；
修好之后它们立刻现形，且**都不是回归**——是本文件 §3.1/§3.2 已经分类过的同一类**陈旧不变式**：

| 检查 | 断言（原文） | 实测 | 归因 |
|---|---|---|---|
| `m09_mono_tool_counts_49_and_40` | 编辑器端点 `49` 工具、游戏端点 `40` 工具（TASK-014 时代） | mono 下 `tools/list = 148 on 9888` 与 `69 on 9889` | **(A) 陈旧不变式**。148/69 与该 HEAD 上**派生**出来的期望**完全相等**（§4.3 门⑤；`accept_m1` 与 `mcp010 -Phase scope` 各自独立给出同一组数字），所以活的工具集没有漂移，唯一错的是脚本里冻结的 `49/40` |
| `m23_guard_user_port_9877` | `pid_before -eq pid_after -and pid_before -gt 0` | `pid_before=-1 pid_after=-1` | **(C) 环境事实**。与 §3.1 的 `mcp010/mcp019/mcp027` 同类：`-gt 0` 把「用户必须在跑 Godot 编辑器」当成不变式，在本环境恒为 False；「我们没占用 9877」这条**真**不变式并未被违反 |

同一脚本的 `-Phase gate2` 还带着**同源的** `g06_tool_counts_49_and_40` 与
`g26_guard_user_port_9877`（非 mono 相位的原版），本批**没有**跑 `-Phase gate2`，故未复现，但源码逐字同形。
**本批按任务书把 section 2 限定为「一行」，因此这四条（m09/m23/g06/g26）原样保留、只登记不修改**；
建议决策层把它们并入 TASK-048 section 1 已经建立的「派生 / 共享端口守卫」处理。

**D86 提交锚点（TASK-048）**：本节 §4 与 `docs/reports/REPORT-048-derived-invariants-and-battery.md` 是在
**HEAD `019c4b019`** 的树上、用该 HEAD 构建出的二进制
（非 mono `--version` = `4.8.dev.custom_build.019c4b019`，mono `--version` = `4.8.dev.mono.custom_build.019c4b019`）
跑完 §4 全部命令后写的；本批对脚本的两处改动（`mcp010` 派生不变式、`mcp014:183` 一行）已在提交
**`cef846a418fddeabe764ef0d65b5fde48ca12c1d`**
（`fix(mcp_server): derive mcp010's TASK-010 invariants and repair the mcp014 m3 call site (TASK-048)`）落地，
本文件与 REPORT-048 随其后的**纯文档**提交落地、其 sha 不写进自身以免自指——
即「`--version` == HEAD」在 §4 中**每一次运行的那一刻**成立。

**D86 提交锚点**：本文件与 `REPORT-047-milestone-closure-inventory.md` 是在
HEAD `595607336d7e654b6f736285d9bc437b2c76e5ca` 的树上、用**该 HEAD 构建出的二进制**跑完上表所有命令后写的；
脚本改动（3 个对齐 + 2 个新增）已在提交 **`05f8713a5d`** 落地（`fix(mcp_server): align the last three 9877 preflights with the shared port guard (TASK-047)`），
本文件随其后的**纯文档**提交落地、其 sha 不写进自身以免自指——即
「`--version` == HEAD」在上表中**每一次运行的那一刻**成立。
