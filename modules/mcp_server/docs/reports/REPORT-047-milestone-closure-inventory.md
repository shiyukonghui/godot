# REPORT-047 — 收尾：3 脚本的 9877 前置对齐 + 优雅退出 flush + 里程碑闭合清单

> 任务书：`docs/tasks/TASK-047-milestone-closure-inventory.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`（已完整阅读）。
> 交付：`docs/reports/MILESTONES-CLOSURE.md`（本批主要产出）+ `scripts/mcp047_graceful_exit_flush.ps1` +
> `scripts/mcp047_m3_mono_check.ps1` + 3 个脚本的 9877 前置对齐。
> **不改模块行为、不改契约**：本批**没有动任何 `*.cpp` / `*.h` / 契约 / 生成器**，只动 `modules/mcp_server/scripts/**` 与 `docs/reports/**`。

## 0. status / commits

| 项 | 值 |
|---|---|
| status | **完成**（三项全部交付；§5 列了 3 条遗留，均不在本批授权范围内） |
| 分支 / HEAD | `feature/mcp-server-module` / `595607336d7e654b6f736285d9bc437b2c76e5ca`（short 9 `595607336`） |
| commits | 见 §7（两条：脚本/任务书一条，本报告与 `MILESTONES-CLOSURE.md` 一条） |
| 引擎 | 非 mono `--version = 4.8.dev.custom_build.595607336` == HEAD；mono `--version = 4.8.dev.mono.custom_build.595607336` == HEAD |
| 端口 | 全程 9877 无监听（用户编辑器未运行）、**从未占用/杀/重启**；只用 9888/9889；无 push |
| 日志 | `%TEMP%\mcp047-logs\` |

本批改动的文件与 sha256：

| 文件 | sha256 |
|---|---|
| `scripts/mcp010_b2_observation_evidence.ps1` | `5ac8da7e2417b44f7cc59b48421de9c7aeb02e84693707db917db6b2c94979dd` |
| `scripts/mcp019_b4_evidence.ps1` | `8d07159a53f13f3c0703ceae2e12f973599057ce4232b7fa781ba8b7b1554670` |
| `scripts/mcp027_object_shape_and_paths_evidence.ps1` | `07579d3208fd1fe459a1045599e41c99814270a236f57beb0adc90ff408ed741` |
| `scripts/mcp047_graceful_exit_flush.ps1`（新增） | `db98c4e143777e19ca400d40ff4f339616906c2f740d624c0cc9704280bed716` |
| `scripts/mcp047_m3_mono_check.ps1`（新增） | `01efa7d9e4dc4f35658a33450f107a2a574dff07e17b1cdbf4143911bf63e20e` |
| `scripts/mcp_port_guard.ps1`（**未改**，被复用） | `55b39b08be844a76f27f61faa287c275a0d942694fe3258b33fc84374f347fe9` |

五个 `.ps1` 全是**纯 ASCII**（逐字节检查：非 ASCII 字节数 = 0），并用 PowerShell 语法解析器验证 `parse-errors=0`。

---

## 1. section 1 — 3 个脚本的 9877 环境前置对齐（逐条前后对照）

### 1.0 为什么必须对齐（先在机器上把旧谓词求值）

本环境 `Get-ListenerPid 9877 = -1`（无监听者）。旧断言按原样求值：

| 脚本 | 旧谓词 | 求值 |
|---|---|---|
| `mcp010` | `(($Before -eq $after) -and ($Before -ne -1))`，`Before=After=-1` | **False** |
| `mcp019` | `(($before -eq $after) -and ($before -gt 0))`，`-1,-1` | **False** |
| `mcp027` | `($before -gt 0)`（另加收尾 `($after -eq $before)`） | **False**（True 的那一半单独不救） |

即三者在「用户没开编辑器」的机器上**必然报红**，而这条红说的不是本模块的任何行为——正是「掩盖真回归」的形状。
对齐后一律走 `scripts\mcp_port_guard.ps1` 的**七分类**：
`violation_this_script_requested_the_user_port` / `violation_this_script_owns_the_user_port` /
`environment_fact_no_listener_before_or_after` / `user_editor_vanished_during_the_run` /
`foreign_listener_appeared_during_the_run` / `user_editor_present_untouched` / `user_editor_pid_changed_during_the_run`。
**没有放松**「我们没占用 9877」：除 pid 稳定性外，新增了两条**我们自己的**事实（`our_pids` / `our_command_lines` 里是否出现 9877）。

### 1.1 `mcp010_b2_observation_evidence.ps1`（4 处）

| # | 位置 | 对齐前 | 对齐后 |
|---|---|---|---|
| 1 | 脚本头纪律段（原 42–44 行） | 「its listener pid is asserted unchanged by every phase」 | 「every process this script starts is registered with its pid and command line so the shared classification in `mcp_port_guard.ps1` can decide it」 |
| 2 | `Show-PortGuard` 函数体（原 228 行） | `Add-Check $Label (($Before -eq $after) -and ($Before -ne -1))` | 去掉 `-Before` 参数，改为 `$result = Complete-McpPortGuard -Guard $script:McpPortGuard -PidAfter $after` + `Add-Check $Label $result.pass $result.evidence` |
| 3 | `-Phase game` 的 finally（原 706 行） | `Show-PortGuard -Before $userPidBefore -Label 'guard_user_port_9877'` | `Show-PortGuard -Label 'guard_user_port_9877'`（`pid_before` 由守卫持有） |
| 4 | `-Phase scope` 的 finally（原 777 行） | 同上 | 同上 |

新登记点：`. mcp_port_guard.ps1`；`Start-Engine` 里 `Register-McpPortGuardProcess -EnginePid $proc.Id -Arguments $Arguments`；
`Import-Project` 里 `Register-McpPortGuardCommandLine -CommandLine $result.command`；主流程 `$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPidBefore`。

### 1.2 `mcp019_b4_evidence.ps1`（3 处）

| # | 位置 | 对齐前 | 对齐后 |
|---|---|---|---|
| 1 | 头注释（原 38–39 行） | 「the user's 9877 is asserted unchanged before and after」 | 「judged by the shared classification in `mcp_port_guard.ps1`」 |
| 2 | 主流程 `$userPortPidBefore = Get-ListenerPid -Port $UserPort` | 该读值只喂给旧断言 | 同一读值改为 `$script:McpPortGuard = New-McpPortGuard -Port $UserPort -PidBefore $userPortPidBefore`（读值语义不变） |
| 3 | 收尾断言（原 716 行） | `Add-Check 'H1_user_editor_on_9877_untouched' (($before -eq $after) -and ($before -gt 0))` | `$portGuardResult = Complete-McpPortGuard …`；`Add-Check 'H1_user_editor_port_9877_guard' $portGuardResult.pass $portGuardResult.evidence` |

新登记点：`. mcp_port_guard.ps1`；`Start-Engine` 登记 pid+参数；`Import-Project` 登记 `$result.command`。

### 1.3 `mcp027_object_shape_and_paths_evidence.ps1`（3 处）

| # | 位置 | 对齐前 | 对齐后 |
|---|---|---|---|
| 1 | 开工断言（原 258 行） | `Check 'port_9877_owner_before' ($userPidBefore -gt 0) (…)` | 该断言**删除**；改为 `$script:McpPortGuard = New-McpPortGuard …` + 一行 `Write-Host`（信息性打印，不是断言） |
| 2 | 收尾断言（原 630 行） | `Check 'port_9877_owner_after' ($after -eq $before)` | `$portGuardResult = Complete-McpPortGuard …`；`Check 'port_9877_guard' $portGuardResult.pass $portGuardResult.evidence` |
| 3 | `Start-Engine`（原 183 行）与两次 `Import-McpProject`（原 267–268 行） | 无任何登记 | `Register-McpPortGuardProcess -EnginePid $proc.Id -Arguments $Arguments`；`Register-McpPortGuardCommandLine … -CommandLine $import1.command` / `$import2.command` |

### 1.4 对齐后复跑（三条脚本的真实退出码与守卫行）

| 命令 | 退出码 | 结果 | 守卫行（原文） |
|---|---|---|---|
| `mcp010 … -Phase game` | **0** | **29/29 PASS** | `guard_user_port_9877 :: listening=False pid_before=-1 pid_after=-1 ours=False same_pid=True asked_by_us=False classification=environment_fact_no_listener_before_or_after our_pids=[79148,53196] our_ports=[0,9889] our_command_lines=4` |
| `mcp010 … -Phase scope` | **1** | 12/13（唯一红见 §1.5） | `guard_user_port_9877 :: … classification=environment_fact_no_listener_before_or_after our_pids=[8704,55724] our_ports=[0,9888,9889] our_command_lines=3` |
| `mcp010 … -Phase count` | **1** | 4/7（三条红见 §1.5） | 该相位不起引擎，无守卫行 |
| `mcp019_b4_evidence.ps1` | **0** | **`66 checks, 66 passed, 0 failed`** | `H1_user_editor_port_9877_guard :: … classification=environment_fact_no_listener_before_or_after our_pids=[78264,75524] our_ports=[0,9888,9889] our_command_lines=4` |
| `mcp027 … -Phase green` | **1** | **59/60**（唯一红见 §1.5） | `port_9877_guard :: … classification=environment_fact_no_listener_before_or_after our_pids=[…] our_ports=[0,9888,9889]` |

**逐条归因的结论**：三条脚本里**再没有一条红来自 9877 前置**；剩下的红全部是**与本次对齐无关的预先存在项**（下节）。

### 1.5 剩余红的逐条归因（不是「全绿」，也不许含糊）

| 脚本 / 相位 | 红项 | 期望 vs 实测 | 归因 |
|---|---|---|---|
| `mcp010 -Phase scope` | `scope_the_editor_game_split_is_exactly_the_scopes` | 期望 `editor-only=17 / game-only=8`；实测 `102 / 23` | **时代陈旧的不变式**（TASK-010 期 B1+B2 = 48 工具）。171 工具下的正确值由 `accept_m1.ps1` 独立给出（`editor 148 / game 69, editor-only 102, game-only 23`），并由 `--check-completeness` 给出 `171 = 66 + 105` 恰好各一次。**与 9877 对齐无关，不是回归** |
| `mcp010 -Phase count` | `count_implemented_union_is_48` | 期望 48（= B1 41 + B2 **7**）；实测 **66**（= B1 41 + B2 **25**） | 同上：硬编码的是 B2 未完成时的并集（B2 在 TASK-013 收口到 25/25） |
| 同上 | `count_scope_split_is_17_23_8` | 期望 17/23/8；实测 26/23/17 | 同上 |
| 同上 | `count_endpoint_expectations` | 期望编辑器端点 40；实测 49 | 同上 |
| `mcp027 -Phase green` | `D8_whole_resource_bag_round_trips` | `code=-32602 message='Property name 'glow_levels/1' is not a settable property name: Object::set() takes a non-empty identifier'` | **预先存在的 TASK-027 缺陷**，已在 `REPORT-AUDIT-CAPTURE.md` §9.1 登记（走非捕获路径）。与 9877、与本批改动无关 |

> 处置建议（不在本批授权内）：`mcp010` 的 `scope`/`count` 两个相位要么按 171 工具更新断言，要么在脚本头声明
> 「这两个相位是 TASK-010 的**历史视角**、不构成当前树的回归门」。这属于改断言，应由决策层定调。

---

## 2. section 2 — 优雅退出 flush：结论与代码依据

**验证脚本**：`scripts/mcp047_graceful_exit_flush.ps1`（新增，纯 ASCII）；**结果：12/12 PASS，exit 0**，日志
`%TEMP%\mcp047-logs\mcp047_graceful.log`。

### 2.1 实验怎么做到「优雅退出，不是 kill」

- 9877 之外的 9889 上起一个 **headless 游戏进程**：`--mcp-trace=<file> --mcp-capture=every_call`；
- **对照（A）**：一次被捕获的读 `running_game_get_scene_tree`，**等**它的捕获行落盘 → 证明「捕获行确实晚一帧、确实会写」；
- **边界（B）**：`running_game_execute_gdscript`，其 GDScript 体是
  `Engine.get_main_loop().quit(0)` + `return "quit-requested"`。
  **quit 在它自己的工具处理函数里、也就是它被 arm 的同一帧里被请求**，因此 `tick()` 完成一条在飞条目所需的
  **下一帧永远不会到来**——这把「在飞边界」变成了确定事件，而不是靠竞态碰运气。
- 退出码不是从 PowerShell 进程对象读的（实测 `Start-Process -RedirectStandardOutput` 下 `ExitCode` **恒为 `$null`**，
  见脚本注释）；改为经一个生成的 `cmd` 包装器，把**执行时展开**的 `%ERRORLEVEL%` 写进文件再读。

### 2.2 结论（无论哪一侧都如实写）

| 主张 | 证据 | 判定 |
|---|---|---|
| 这是一次**优雅退出** | `process_exited_on_its_own_gracefully`：包装器写回的引擎退出码 = **0**；全程没有 `Stop-Process`/`taskkill` 命中它（`finally` 里的兜底未触发） | **落盘成立** |
| 最后一条**在飞请求的 call line** 在盘上 | `the_quit_call_line_is_on_disk`：trace 共 3 行，最后一行是 `method=tools/call, tool=running_game_execute_gdscript, seq=2, capture.status=unavailable` | **落盘成立** |
| trace 文件没有撕裂尾巴 | `trace_file_non_empty_and_ends_with_a_newline`（1223 B，以 LF 结尾）+ `every_line_including_the_last_parses_as_json`（3 行全部可解析） | **落盘成立** |
| **在飞的 capture event line 没有落盘** | `the_in_flight_capture_line_was_not_written`：`seq=2` 的 call line 宣布了 `capture.status=unavailable`，而 `seq=2` 的 capture 事件行数 = **0**；`the_only_dangling_entry_is_the_in_flight_one`：`call lines announcing a capture=2, capture event lines=1, seqs announced but never written=[2]` | **未落盘（如实）** |
| 对照一致 | `seq=1`（A）的 capture 行在盘上，`frames_waited=1`——即「晚一帧」是设计，而不是丢失 | 一致 |

**一句话结论**：**优雅退出不会丢已经写下的行**（最后一条 `tools/call` 的 call line 在盘上、文件以完整 JSON 行 + LF 收尾），
**但优雅退出同样会丢弃「还没生成的」在飞捕获行**——`REPORT-AUDIT-CAPTURE` §9.2 第 4 条的 `unconfirmed` 由此**收口为已确认**：
它不是 kill 的伪影，「最后一次调用没有捕获行」在**有序退出**下同样成立。

### 2.3 退出路径上的代码依据（逐行对照）

| 事实 | 代码 |
|---|---|
| 每写一行即 flush（所以先前的行在退出前已经耐久） | `mcp_trace.cpp:235` `file->store_string(p_line + "\n")` → `:240-247` 注释与 `file->flush()`（注释：「Flushed per line so that … a crash keeps every line written before it」） |
| 关闭时再 flush 一次 | `mcp_trace.cpp:194-203` `Recorder::close()`：`file->flush(); file->close();`（注释：「the last lines of a run that is shut down are the ones a report is written from」） |
| 优雅退出会走到 `_shutdown()` | `mcp_server.cpp:149-169` `NOTIFICATION_EXIT_TREE → _shutdown()`（另有 `~MCPServer` / `NOTIFICATION_PREDELETE`） |
| `_shutdown()` 的**顺序**：先关 trace，再停捕获引擎 | `mcp_server.cpp:259-283`：`http_server->stop()` → **`trace_recorder->close()`（265-271）** → **`capture_engine->stop()`（275-279）** |
| 在飞条目就是被这里丢掉的 | `mcp_capture.cpp:406-416` `Engine::stop()`：「The in-flight entries hold `Image` refs; there is nowhere left to report them to, so they are dropped rather than written」，逐个 `pending[i] = Pending()` |
| 捕获行**只**由一个地方产生，且要求**至少晚一帧** | `mcp_capture.cpp:594-723` `_complete()` 末尾 `recorder->record_event_line(fields)`（721-723）；唯一调用者是 `tick()`（`:726-755`），条件 `if (p_frame < pending[i].finish_frame + 1) continue;` |
| arm 与 finish 都发生在**同一帧**，所以下一帧必须存在 | `arm_unavailable()`/`arm()` 记 `armed_frame = frame`（`:446` / `:472`）；`finish()` 记 `finish_frame = frame`（`:497`） |

> 换言之：`_complete()` 是捕获行的唯一写入者，而优雅退出路径**先关文件、再清空 `pending`**，两件事都没有调用 `_complete()`。
> 因此「丢弃」不是有条件的行为，而是这条顺序的必然结果。

---

## 3. section 3 — 里程碑闭合清单

**主产出**：`docs/reports/MILESTONES-CLOSURE.md`（逐里程碑的交付物路径、验收证据路径、**在当前 HEAD 上重跑的最小命令 + 真实输出与退出码**、逐条归因、以及「本批没有重跑的东西」）。
本节只摘录结论与关键数字，明细以该文件为准。

| 里程碑 | 本批重跑的最小集合 | 退出码 | 关键真实输出 |
|---|---|---|---|
| M0 | `build_local.cmd -Force`（tests=yes，cmd 启动） | **0** | `--version = 4.8.dev.custom_build.595607336` == HEAD；日志尾 `done building targets.` / `EXIT_CODE=0` |
| M1 | `accept_m1.ps1` ×2 + `check_contract_subset.ps1 -Group editor_input_simulation`（另加 `-Group editor_write_scene_editor`） | **0 / 0 / 0 / 0** | `22/22 cases passed` ×2 且 PASS 清单**逐行相同**；子集 `3/3` ×2；`implemented tools : 171 / contract 171`，`editor 148 / game 69` |
| M2 | `check_tool_groups.py`（无参数，B1）+ `--batch B2` + `mcp010 -Phase game` | **0 / 0 / 0** | `TOOL-GROUPS CHECK PASS`（41 工具）；`TOOL-GROUPS-B2 CHECK PASS`（9 组 25 工具）；`29/29 checks passed` |
| M3 | mono 重建（串行）→ `mcp047_m3_mono_check.ps1` → `build_local.cmd -Force` 恢复 | **0 / 0 / 0** | mono `--version = 4.8.dev.mono.custom_build.595607336` == HEAD；M3 检查 **11/11**：`Mcp014Csharp.dll` 9728 B、`tools/list under mono = 69 == 69`、`[MCP014-CS] Main._Ready ran`、`CsharpReport() = 'csharp: ticks=352 state=csharp-ready'`、C++ 写入后 C# 读回 `state=written-from-mcp`；恢复构建 `Time elapsed: 00:01:46.73` 且 `--version` 再校验 == HEAD |
| M4 | `--batch B3` + `--batch B4` + `mcp019_b4_evidence.ps1` + `mcp027 -Phase green` | **0 / 0 / 0 / 1** | B3 12 组 40 工具、B4 3 组 7 工具（均 PASS）；`mcp019` **66/66**；`mcp027` **59/60**（唯一红 = 预先存在的 `D8_whole_resource_bag_round_trips`，见 §1.5） |
| M5 | `--batch B5` + `--check-completeness` | **0 / 0** | `TOOL-GROUPS-B5 CHECK PASS`（26 组 58 工具）；`COMPLETENESS CHECK PASS`：`66 + 105 = 171`，`each exactly once`，`missing=0, foreign=0` |

五道门 + 门⑥（全部本批自跑）：

| 门 | 退出码 | 输出摘要 |
|---|---|---|
| ① 契约子集 | 0 / 0 | `3/3 checks passed` ×2 |
| ② 三类证据 | 0 / 0 / 1 | `mcp010 -Phase game` 29/29、`mcp019` 66/66、`mcp027` 59/60（§1.5 归因） |
| ③ 模块 doctest | **0** | `293/293 passed | 0 failed | 1429 skipped`；`21431/21431 assertions | 0 failed` |
| ④ 全引擎回归 | **0** | `1719/1719 passed | 0 failed | 3 skipped`；`445713/445713 assertions | 0 failed` |
| ⑤ 独立验收 | 0 / 0 | `accept_m1` ×2 = 22/22，清单一致 |
| ⑥a/⑥b/⑥c | 0 / 0 / 0 | `scanned 75 == pinned 75`；覆盖声明打印；探针 **101/101**，`log sha256=7e2a773f…`（与 `REPORT-046` §12.1 同一 sha） |

**构建纪律**：M3 的 mono 重建是唯一的第二次构建，**全程串行**（开始前实测无 scons、无引擎进程），
重建后用 `build_local.cmd -Force` 把非 mono 二进制**恢复**为当前 HEAD 并再次校验 `--version`（§3 的构建顺序表）。
本批**没有**并发跑过两个 scons，也**没有**抑制 scons 输出。

---

## 4. section 4 — 本批**没有**重跑的东西（明确列出，不写成「通过」）

| 项 | 状态 | 理由 |
|---|---|---|
| `mcp043/042/041_gates.ps1` 三个门批次 | 未跑 | 它们是**聚合器**；其全部构成步骤本批已逐条独立跑过（门①③④⑤⑥ + `mcp010/019/027`）。再跑三遍是 3 倍机时换同样的结论。**取舍已显式登记** |
| `mcp044/045/046` 捕获与成本证据脚本 | 未跑 | 属 TASK-044..046 的证据面，`REPORT-AUDIT-CAPTURE.md` 已登记其上一轮真实输出；本批的 9888/9889 机时留给了 M0–M5 最小集合 |
| M5 的「hof-rs 切端点 + 真实 T=1 冒烟」 | 未跑 | 在 hof-rs 侧（本模块只读）；`docs/RACING-*.md` 是上一次的真实工程冒烟记录 |

---

## 5. deviations / blockers / next_step_recommendation

### deviations（与任务书/手册的偏离，逐条显式）

1. **新增了两个脚本而不是只改三个**：`mcp047_graceful_exit_flush.ps1`（section 2 的可复现证据）与
   `mcp047_m3_mono_check.ps1`（section 3 的 M3 行）。任务书没有要求新增脚本，但它要求**可复现的真实输出**——
   这两条证据不落到脚本就只能是一次性的手工命令。两个脚本都纯 ASCII、只写 `%TEMP%`。
2. **M3 没有用 `mcp014 -Phase m3` 作为唯一证据**：该脚本在 `m06` 之后中止（§5 blockers 第 2 条），
   因此用 `mcp047_m3_mono_check.ps1` 接续。`mcp014` 的前 6 条 PASS 作为**同一轮的**补充证据被引用。
3. **没有改 `mcp014` 的那一行**：本批只被授权对齐任务书点名的 3 个脚本；修 `mcp014:183` 属于扩大范围（一行即可修，见 blockers）。
4. **§1.5 的三条/四条 `mcp010` 红保持原样**：它们是硬编码断言，改断言应由决策层定调（§1.5 末）。
5. **门批次聚合器未跑**（§4）。
6. **控制台中文伪影**：`%TEMP%\mcp047-logs\*.log` 里个别中文（引擎侧 reason 串）被 cmd 重定向塌成 `?`；
   判定所依据的是**引擎自写的 UTF-8 JSONL trace** 与其**盘上 sha256**（`mcp047_graceful.log` 里可核对），
   `MILESTONES-CLOSURE.md` §3.6 已登记。响应体采集一律 `curl.exe -s -o <file>`，**没有走管道**。

### blockers

1. **无阻断本批交付的 blocker**。
2. 留给决策层/下一批的三条遗留：
   - `mcp014_m3_evidence.ps1:183` 使用未定义的 `Write-Utf8NoBom`（应为 `Write-McpUtf8NoBom`）→ `-Phase m3` 必然中止；
   - `mcp027` 的 `D8_whole_resource_bag_round_trips`（`glow_levels/1` 非可 settable 名）仍是红的，属 TASK-027 议题；
   - `mcp010` 的 `scope`/`count` 相位含 4 条 TASK-010 期硬编码不变式，需决定「更新断言」还是「标注为历史视角」。

### next_step_recommendation

1. 若要**逐批次封存**门证据，另开一批按 `mcp041 → mcp042 → mcp043` 顺序把三个聚合器跑完（串行、约 3 倍机时），
   本文件已为它们留好位置。
2. 一行修 `mcp014_m3_evidence.ps1:183`（`Write-Utf8NoBom` → `Write-McpUtf8NoBom`），随后 `-Phase m3` 可在 mono 二进制上完整复跑。
3. 决定 `mcp010` 的历史相位断言处置，并把结论写回该脚本头部（否则下一个人还会看到 4 条红并误判为回归）。

---

## 6. D86 结论锚点

- **锚点提交**：`595607336d7e654b6f736285d9bc437b2c76e5ca`（short 9 `595607336`），分支 `feature/mcp-server-module`。
- 上述**所有**命令、退出码与输出，都是在这个 HEAD 的树上、用**由这个 HEAD 构建的二进制**跑的：
  非 mono `--version = 4.8.dev.custom_build.595607336`、mono `--version = 4.8.dev.mono.custom_build.595607336`，
  两者都与 `git rev-parse --short=9 HEAD` 相等。
- 本批只改 `modules/mcp_server/scripts/**` 与 `docs/reports/**`：**没有触及任何 `*.cpp`/`*.h`、契约或生成器**，
  因此锚点之后不存在任何会改变模块行为的字节。
- 引用他人结论处（M0–M5 的验收证据路径）一律**标注其报告路径**，且本批对其中可在当前 HEAD 重跑的部分**自己重跑并给真实输出**；
  未重跑者在 §4 显式列出。

---

## 7. commits

| # | sha（short 9） | 内容 |
|---|---|---|
| 1 | `05f8713a5d` | `fix(mcp_server): align the last three 9877 preflights with the shared port guard (TASK-047)` —— 3 个对齐脚本（`mcp010`/`mcp019`/`mcp027`）+ 2 个新增证据脚本（`mcp047_graceful_exit_flush.ps1`、`mcp047_m3_mono_check.ps1`）+ 任务书 `TASK-047-milestone-closure-inventory.md`（6 files changed, 792 insertions, 11 deletions） |
| 2 | **append-only，不写 sha 以免自指** | `docs(mcp_server): MILESTONES-CLOSURE + REPORT-047 (TASK-047)` —— 本报告与 `MILESTONES-CLOSURE.md`；**只加文档**，不改任何脚本字节 |

**未 push**（任务书硬性纪律）。提交 1 之后的 HEAD 只多了提交 2 这一个文档提交，因此 §6 的锚点结论依然成立：
上表每一次运行时的 `--version` 都等于运行那一刻的 `HEAD`（`595607336`），且此后没有任何会改变模块行为的字节。
