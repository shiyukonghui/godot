# REPORT-AUDIT-M3 — 独立验收：mono 构建 + C# 工程可跑 + M2 三项修复

> 审计方：独立验收子代理（未参与实现）。**不采信** `REPORT-014-m3-mono-csharp.md` 与决策者结论；
> 本报告每一条结论都配**本次审计自己跑出**的命令、退出码、响应体 sha256 或日志行。
> 任务书：`docs/tasks/TASK-AUDIT-M3.md`。审计产物落点：`%TEMP%\audit-m3\`（evidence 78 个文件、logs、脚本）。
> 工作目录 `F:\RustProjects\godot-mcp-pro\code\godot`，分支 `feature/mcp-server-module`，
> 审计期间 HEAD 恒为 `6ea5de6e0b20ea71d3a74caf9932f548e2144ce8`（未做任何 git 写操作）。

## 0. 结论摘要

| 分类 | verdict | 一句话依据 |
|---|---|---|
| mono 构建 | **pass** | 本机重建：scons mono exit 0 / 113 s；`--version` = `4.8.dev.mono.custom_build.6ea5de6e0` == HEAD；glue 重生成 exit 0 且 1110 个文件与仓内逐字节相同；4 个 `4.8.0-dev` nupkg 可被离线 `dotnet build` 消费 |
| C# 可跑 | **pass** | 我自己的 C# 工程副本（无 `.godot`）离线 `dotnet build` exit 0 / 0 警告 0 错误；mono 引擎起游戏后从 **9889** 读到 `csharp: ticks=… state=…`；`CsharpTicks` 620→1060；C++ 写入后 C# 读回 `state=written-from-mcp` |
| 模块共存 | **pass** | mono 下 9888 = **49**、9889 = **40**；我自己的契约逐字比对：49/40 条 name/description/inputSchema **零失配**、零 scope 泄漏；连续 `tools/list` 逐字节相同 |
| 三项修复（D-1/D-2/D-3/R-3） | **pass** | 逐条自己复现：`-32001`+suggestion / `-32000`+suggestion 且参数错仍 `-32602` / 契约差异**只**含该工具 description+required 与 `_meta` / `pending_timeout_ms=0` 实测 **30.022 s** 以 `-32000`+`timeout_ms=30000` 收尾 |
| 工程门 | **pass** | 全部在 `--version` == HEAD 的二进制上：doctest 124/124·3653、全引擎 1550/1550·427935（0 failed）、门① 3/3、`accept_m1.ps1` 22/22 ×2（PASS 清单逐字节相同） |
| 端口纪律 | **pass** | 9877 全程 PID **36392**（起始时间未变）未被触碰；收尾 9888/9889 无 LISTENING；无孤儿进程；`git status` 只剩既有 4 个未跟踪物 |

**总 verdict：pass**（1 条 minor 文档性缺陷 + 5 条风险，见 §9/§11）。

## 1. 开工前置：门的构建绑定（R-1）—— 必须先重建（已做）

- **到货状态**：`bin\godot.windows.editor.x86_64.mono.exe --version` = `4.8.dev.mono.custom_build.eb05a50ed`，
  非 mono = `4.8.dev.custom_build.eb05a50ed`，而 HEAD = `6ea5de6e0b` → **不满足** PLAYBOOK §3 的
  「`--version` hash 前缀 == `git rev-parse --short HEAD`」。
- **差异性质**（`git diff --name-only eb05a50edf..HEAD`）只有 4 个文件、**0 个被编译的源文件**：
  `docs/reports/REPORT-014-m3-mono-csharp.md`、`docs/tasks/PLAYBOOK-group-port.md`、
  `docs/tasks/TASK-AUDIT-M3.md`、`scripts/mcp014_m3_evidence.ps1`。即二进制与 HEAD 在**编译输入上等价**，
  但从流程纪律看仍是「门跑在陈旧产物上」。
- **我的处置**：重建两者（源码零改动，`bin/` 被 `.gitignore` 忽略）。
  - 非 mono：`modules\mcp_server\scripts\build_local.cmd` → `exit code = 0`，45.8 s（scons `INFO: Time elapsed: 00:00:32.20`；
    上一次日志里的 `00:01:39.75` 是原始构建），命令 `D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=no tests=yes -j8`。
  - mono：`D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=yes -j8` → `SCONS_EXIT=0`，113 s
    （`INFO: Time elapsed: 00:01:39.82`，`scons: done building targets.`）。全程**串行**，未并发跑两个 scons。
- **绑定结果**（我自己跑）：

  | 二进制 | `--version` | 字节 | sha256 |
  |---|---|---|---|
  | `bin\godot.windows.editor.x86_64.exe` | `4.8.dev.custom_build.6ea5de6e0` | 191 555 072 | `3326b77768d493cda63e39aec3a4c78534b48826d539dc1bdf77fc320d40fc8b` |
  | `bin\godot.windows.editor.x86_64.console.exe` | 同上 | 300 544 | `f91e4cb99e61397899235ece06caa62020ceb5ac882c51e416e557bfdd2a5efa` |
  | `bin\godot.windows.editor.x86_64.mono.exe` | `4.8.dev.mono.custom_build.6ea5de6e0` | 178 121 216 | `3466829841d417707f407486a61ba957c92a1d621ccb4f4d37e472701a002566` |
  | `bin\godot.windows.editor.x86_64.mono.console.exe` | 同上 | 300 544 | `c223de9d6bac877d620be6fa9f0c6d91f54558c2e9e82cb82cb3b1e9e6fa7273` |

  `git rev-parse --short HEAD` = `6ea5de6e0b`，`6ea5de6e0` 是其前缀 → **绑定成立**，且 mono 与非 mono **同一 commit**。
- 下文所有门与实测都在这两个重建后的二进制上完成。
- 副作用（诚实声明）：REPORT-014 §6 记录的 4 个旧二进制 sha256（eb05a50ed 版）**已随我的重绑定失效**；`bin/` 不受版本控制，不影响仓内状态。

## 2. mono 构建（自己跑）

1. **编辑器目标**：`module_mono_enabled=yes`，exit 0，113 s（见 §1），产物 `.mono.exe`（178 121 216 B）+ `.mono.console.exe`；
   与 `module_mono_enabled=no` 用**不同文件名**，两者在 `bin/` 里并存（我实测两个 `--version` 分别可用）。
2. **glue 生成**（**不改仓**的做法：输出到 `%TEMP%\audit-m3\glue`）：
   `bin\godot.windows.editor.x86_64.mono.console.exe --headless --generate-mono-glue %TEMP%\audit-m3\glue`
   → **exit 0，3.8 s**，末行 `The Godot API sources were successfully generated`；
   生成 1110 个 `Generated/**` 文件，与仓内 `modules/mono/glue/GodotSharp/**/Generated/**`（1118 个）逐文件 sha256 比对：
   **0 处内容差异**，多出的 8 个只是 `obj/**` 的 MSBuild 中间产物 → glue 生成**可复现且与仓内一致**。
   （该进程还打了 `ERROR: [MCP] SceneTree never became available; MCP server disabled.` —— 该模式下没有主循环，属预期，不是崩溃。）
3. **GodotSharp / nupkg**：`bin\GodotSharp\Api\{Debug,Release}\` 有 `GodotSharp.dll`（Debug 6 469 632 B / Release 6 029 312 B）、
   `GodotSharpEditor.dll`、`GodotPlugins.dll`；`bin\GodotSharp\Tools\nupkgs\` 有 **4 个 `.nupkg`**
   （`Godot.NET.Sdk.4.8.0-dev`、`Godot.SourceGenerators.4.8.0-dev`、`GodotSharp.4.8.0-dev`、`GodotSharpEditor.4.8.0-dev`）
   + 2 个 `.snupkg`（符号包）。宣称的「4 个 nupkg」与文件系统一致（`.snupkg` 不计入）。
   它们的**可用性**由 §3 的离线 `dotnet build` 端到端证明（工程 `<clear/>` 后只指向这个目录）。
4. **取舍（显式）**：我**没有**重跑 `build_assemblies.py`，因为它会重写 `bin\GodotSharp\**` 与 `modules/mono/glue/**/{bin,obj}`
   （虽全在 `.gitignore` 内，但会让产物指纹与 REPORT-014 脱钩，且对本次审计的判定轴无增量）。改以
   ① glue 重生成逐字节比对 + ② 离线消费 nupkg 两条**独立**证据覆盖同一主张。

## 3. C# 工程真的能跑（M3 核心，自己跑）

审计为了独立，**自己复制了一份工程**（`%TEMP%\audit-m3\csharp-proj`，robocopy 排除 `.godot`，即无任何既有构建缓存），
并做了两处**仅审计用**的加料（`Main.cs`：`public int PlainField = 4242;`（无 `[Export]`）与 `public string Boom(){ throw new System.Exception("audit-boom"); }`）。
`project.godot` 保留 `[godot_mcp] enabled_in_game=true` 与 `[mcp_server] pending_timeout_ms=0`。

1. **离线 `dotnet build`（我自己跑，未抑制输出）**
   ```text
   $ dotnet build -c Debug                (cwd = %TEMP%\audit-m3\csharp-proj)
     正在确定要还原的项目…
     已还原 …\Mcp014Csharp.csproj (用时 225 毫秒)。
     Mcp014Csharp -> …\.godot\mono\temp\bin\Debug\Mcp014Csharp.dll
   已成功生成。
       0 个警告
       0 个错误
   已用时间 00:00:03.12                  DOTNET_EXIT=0
   ```
   还原 225 ms、包源只有本地 `bin\GodotSharp\Tools\nupkgs`（`NuGet.config` 里 `<clear/>`）→ **离线可用**；
   `nuget.org` 不可达在本机是常态，我**没有**把它当作失败理由。
2. **C# 真的执行了**（mono 引擎，`--headless --path <副本> --mcp-port=9889`，游戏 stdout）：
   `[AUDIT-M3-CS] Main._Ready ran; state=csharp-ready`，随后 `ticks=120 … ticks=5640` —— 只有 `_Process` 真跑才会递增。
3. **从 9889 用 MCP 工具读到 C# 状态**（响应体逐条落盘，sha256 见 §13）：
   - `running_game_execute_gdscript {code: 经 Engine.get_main_loop() 取树后调 node.CsharpReport()}`
     → `{"result":"csharp: ticks=944 state=written-from-mcp","result_type":"String"}`（跨语言可读，且由 C# 拼字符串）。
   - `running_game_get_node_properties {node_path:"/root/Main"}` → `CsharpTicks` **947 → 1314**（两次读数间隔 2.5 s）。
   - 反向：`running_game_set_node_property {property:"CsharpState", value:"written-from-mcp"}` → 成功（old `csharp-ready` → new `written-from-mcp`），
     再由 `running_game_execute_gdscript` 读回 `state=written-from-mcp`。
4. **实现者原样工程也自己跑了一遍**（`%TEMP%\mcp014-scratch\m3-csharp-proj`，未改动）：
   `{"result":"csharp: ticks=617 state=csharp-ready"}`（宣称的形态逐字复现）；`CsharpTicks` 620 → 1060；
   写 `CsharpState` 后 `{"result":"csharp: ticks=1066 state=written-from-mcp"}`。
   注意：宣称里的具体数字（1428→1564）是**计时相关**的，不可能逐字复现，可复现的是「单调递增」与字符串形态。
5. **版本事实**（供 hof-rs `hoh doctor` 交叉核对）：`dotnet --version` = `10.0.300-preview.0.26177.108`；
   目标框架 `net8.0`；包版本 `4.8.0-dev`；程序集落点 `<工程>\.godot\mono\temp\bin\Debug\Mcp014Csharp.dll`（我的副本里 10 240 B）；
   离线包源 `<引擎>\GodotSharp\Tools\nupkgs`；引擎 mono 版本串 `4.8.dev.mono.custom_build.6ea5de6e0`。

## 4. 模块共存（mono）

- 启动日志（我自己起的两端）：mono 编辑器 `[MCP] listening on 127.0.0.1:9888 (editor=true, tools=49)`；
  mono 游戏 `[MCP] listening on 127.0.0.1:9889 (editor=false, tools=40)`。→ **49 / 40**，与宣称一致。
- **我自己的契约比对**（`%TEMP%\audit-m3\compare_contract.py`，不是门脚本）：
  - 9888：49 条（`both`=23 + `editor`=26），全部存在于契约，**name/description/inputSchema 零失配**，无 scope 越界；
  - 9889：40 条（`both`=23 + `game`=17），零失配，**`editor`-scope 工具 0 条**（无泄漏）；
  - 缺席的都是尚未实现的 B3/B4/B5 组（属预期，不是「已实现却缺席」）。
- 反向缺席可观测：在 9888 上按名调用 game-only 的 `running_game_get_node_properties` → `-32601 Method not found`（不是执行）。
- 确定性：同端点连续两次 `tools/list` 响应体逐字节相同（9889 sha256 `3bed9972…` 两次一致）。
- 非 mono 对照：9888/9889 的 `tools/list` payload 与 mono **完全相同**（含顺序，逐字节相同见 §6.5）。

## 5. M2 三项修复 + R-3（逐条自己复现）

### D-1 `running_game_set_node_property` 未知属性（minor，诚实性）
- 不存在属性：`{node_path:"/root/Main", property:"NoSuchPropAudit", value:1}`
  → `{"error":{"code":-32001,"message":"Property 'NoSuchPropAudit' on node '/root/Main' not found",
  "data":{"suggestion":"Use running_game_get_node_properties to list the properties this node has"}}}`
  （响应 216 B，sha256 `fae90a32…`）。**不再出现假成功形状。**
- 真实属性：`property:"CsharpState"` → `{"new_value":"written-from-mcp","node_path":"/root/Main",
  "old_value":"csharp-ready","property":"CsharpState"}`（sha256 `2bdf4dd3…`）；
  **用另一个工具**独立读回：`running_game_get_node_properties` → `"CsharpState":"written-from-mcp"`；
  第三个工具 `running_game_execute_gdscript` → `state=written-from-mcp`。三工具链一致。
- **宣称的引擎事实独立确认（并发现一处措辞过强，见 §9 D-AUDIT-1）**：
  不带 `properties` 的全量列举返回 **29** 个键，其中 `CsharpState`/`CsharpTicks` 在、**`PlainField` 不在** →
  「非 `[Export]` 的 public 字段不进**属性表**」成立（源码依据：`csharp_script.cpp:1510-1521` 的 `exported_members_cache`）。
  但 `running_game_set_node_property {property:"PlainField", value:7}` **成功**（old `4242` → new `7`），
  带 `properties` 的过滤读也返回 `"PlainField":7` → 该成员在**按名读写面**上确实可达
  （源码依据：`csharp_script.cpp:1487-1508` 的 `CSharpInstance::set/get` 走托管桥 `CSharpInstanceBridge_Set/Get`，按名解析字段）。

### D-2 `editor_capture_screenshot` 在 headless（nit，一致性）
- `{}` → `-32000`，message `编辑器没有可读取的帧缓冲（headless display server 没有纹理存储）`，
  `data.suggestion` = `用带 display server 的编辑器进程重跑（去掉 --headless，或换用带渲染驱动的构建）后再次调用`（290 B，sha `f0bf449c…`）。
  **不是 `-32603`**，也没有把空白帧当成功。
- 参数错仍是 `-32602`：`{save_path:123}` → `Parameter 'save_path' must be a string, got float`（110 B，sha `ec73a028…`）。

### D-3 契约 `required` 由 `["events"]` → `[]`（nit）
我自己做的**结构化 diff**（`git show de87d1c737^:…` vs `de87d1c737:…`，脚本 `%TEMP%\audit-m3\d3_contract_diff.py`）：
- 前后工具数均 **171**，名字集合相同；**唯一变化的工具是 `running_game_play_input_recording`**，且只变 `description` 与 `inputSchema`：
  - `inputSchema.required`：`["events"]` → `[]`（`properties` 一字未改：`events`(array)/`speed`(number, default 1.0)）；
  - description 新增回退规则，逐字为：
    `回放之前录制的输入事件序列 缺省 \`events\` 时，回放本游戏进程内最近一次 running_game_stop_input_recording 的录制；若本进程没有可用录制则返回 -32602。`
- `_meta` 变化仅：`generator_version 1.4.0 → 1.5.0`、`overrides` 新增 2 条（`kind=description/mode=append` 与
  `kind=inputSchema/mode=replace`，`old_name=replay_recording`，理由写明 D-3/D59）；`count=171`、`tool_count_in=174`、
  `map_sha256` 不变且**等于** `docs/tool-rename-map.json` 在 git 与磁盘上的真实 sha256
  （`2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`）。
- HEAD 的契约字节 == D-3 提交的契约字节（`sha256 56095079c499477004f70c86def350be6517cb76d3b695c7ba5ed02bffd46cbd`，100 674 B）。
- **线上逐字**：9888 的 49 条与 9889 的 40 条 `tools/list` 与契约的 `name`/`description`/`inputSchema` **全部 True**（我自己的比对 + 门① 3/3）。
- **行为**：本进程没有可用录制时 `running_game_play_input_recording {}` → `-32602`
  `Parameter 'events' must not be empty: there is nothing to replay (pass the events, or call running_game_stop_input_recording in this game process first)`
  （214 B，sha `f0dba6bd…`）。另做了探索性正路径：`create_input_recording` → `stop_input_recording`（headless 下 `event_count=0`）
  → 再缺省回放仍 `-32602`；即「空录制 = 没有可用录制」，与描述一致，可构造的正路径需真实输入源（见 §10）。
- `TOOL-NAMING.md` **未**随 D-3 重渲染，但它由 `tool-rename-map.json` 渲染而映射未动：我实测该文件里
  `inputSchema`/`required` 出现次数均为 **0**，故无漂移；REPORT-014 §9 也自报「逐字节未变」，与我的实测一致。

### R-3 `pending_timeout_ms <= 0` 的兜底（加固）
- 工程 `[mcp_server] pending_timeout_ms=0` 的实际启动输出（我自己跑，未抑制）：
  - stdout：`[MCP] pending_timeout_ms=30000 (configured=0) pending_ticks_per_frame=8` —— **同时报配置值与生效值**；
  - stderr：`WARNING: [MCP] mcp_server/pending_timeout_ms=0 is not a usable deadline (0 would switch the deferred fallback off); using 30000 ms`
    （`modules\mcp_server\mcp_server.cpp:404`）。
- **实测 30 s 兜底**：`running_game_find_node_when_available {node_path:"/root/NoSuchNodeAudit", timeout:600}`
  （工具自报 600 000 ms）→ **elapsed = 30.022 s**，`-32000`，`data.timeout_ms = 30000`，
  message `Deferred call timed out after 30000 ms: waiting for node '/root/NoSuchNodeAudit'`（300 B，sha `e1dfe0ab…`）。
  非 mono 同样 **30.022 s**（sha `d6579651…`）→ 有效值 = min(工具, 框架上限)，框架值取 R-3 映射后的 30 000。
- 正数不被篡改（补测）：`pending_timeout_ms=5000` 的工程启动日志 = `[MCP] pending_timeout_ms=5000 (configured=5000)`。

## 6. 工程门（全部在 §1 重绑定的二进制上；先校验 `--version`）

### 6.0 绑定校验
`bin\godot.windows.editor.x86_64.console.exe --version` = `4.8.dev.custom_build.6ea5de6e0`（exit 0），
`git rev-parse --short HEAD` = `6ea5de6e0b` → **前缀一致**，门成立。

### 6.1 门③ 模块 doctest
`bin\…console.exe --headless --test --test-case="[MCPServer]*"` → **exit 0, 4.6 s**
```
[doctest] test cases:  124 |  124 passed | 0 failed | 1429 skipped
[doctest] assertions: 3653 | 3653 passed | 0 failed |
[doctest] Status: SUCCESS!
```
（与宣称 124/124·3653 一致。日志里的 `ERROR:` 行是**负路径用例的预期输出**：GDR-16 lint 拒绝、corrupt.tres、缺 handler 的 ToolBuilder 等。）

### 6.2 门④ 全引擎回归
`bin\…console.exe --headless --test` → **exit 0, 30.5 s**
```
[doctest] test cases:   1550 |   1550 passed | 0 failed | 3 skipped
[doctest] assertions: 427935 | 427935 passed | 0 failed |
[doctest] Status: SUCCESS!
```
（与宣称 1550/1550·427935、0 failed 一致。mono 构建不带 `tests=yes`，故「mono 下跑 doctest」**未被测也未声称**。）

### 6.3 门① 契约子集逐字
`check_contract_subset.ps1`（默认组）→ **exit 0**：
```
[PASS] editor_9888_contract_subset   (49 tools, 每工具 name=True description=True inputSchema=True)
[PASS] game_9889_contract_subset     (40 tools, 每工具 name=True description=True inputSchema=True)
[PASS] guard_user_port_9877          (pid_before=36392 pid_after=36392)
3/3 checks passed
```
脚本自报 `implemented_union=49 (editor) / 40 (game)`、`editor-only=26 game-only=17 both=23` —— 与我独立计算的分布完全一致。

### 6.4 门⑤ `accept_m1.ps1` 连跑两次
两次均 **exit 0、22/22 cases passed**（48.2 s / 48.0 s），两次 **PASS 清单逐字节相同**：
`case1_GET_mcp_200, case2_initialize, case3_tools_list_fixture, case4_tools_call_project_info, case5_tools_call_invalid_params,
case6_unknown_method, case7_parse_error, case8_concurrent_100, case9_keep_alive_two_requests, case10_half_packet,
case11_body_too_large, case15_connection_reaping, case16_expect_100_continue, case17_header_too_large_431,
case18_bare_lf_terminator_400, case19_invalid_utf8_body_warns, case20_tools_list_cross_process_restart,
case12_game_process_endpoint, case13_game_without_port, case14_port_occupied, guard_user_port_9877, gate_scope_declared`。

### 6.5 mono vs 非 mono 抽样一致性（≥3 个，含 1 个 deferred）
对**同一请求**在两种构建上取响应体、剥去 JSON-RPC `id` 后逐字节比较：**6/6 payload 完全相同**：
`tools/list@9888`、`tools/list@9889`（含工具顺序）、`editor_capture_screenshot`（headless 报错）、
`editor_capture_screenshot`（参数错）、`set_node_property`（未知属性 `-32001`）、`play_input_recording`（无录制 `-32602`）；
deferred 轴另见 `running_game_find_node_when_available`：成功路径两者都正常返回，超时上限两者都 **30.022 s / -32000 / 30000**。

## 7. 端口纪律与收尾

| 项 | 实测 |
|---|---|
| 9877（用户 Godot 4.7.1-mono） | 审计开工与收尾均为 `LISTENING 36392`，`StartTime = 2026/9/21 19:34:39`（未变），全程未杀/未重启/未占用 |
| 9888 / 9889 | 收尾无 LISTENING（仅有 pid=0 的 `TIME_WAIT` 残留，属正常 TCP 回收，不占用端口） |
| 进程 | 收尾仅剩 1 个 godot 进程 = 36392；无孤儿（含 C# 游戏进程、无 `dotnet`/`python` 残留） |
| 仓库 | `git status --porcelain` 只有既有 4 个未跟踪物（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）；HEAD 未变 |
| 文件改动 | 未修改任何**受版本控制**的源码/测试；C# 与 scratch 工程改动均在我的 `%TEMP%\audit-m3\` 副本上；`bin/` 因重绑定而重建（.gitignore 忽略） |
| 自曝过程事故 | 我用 pwsh 起 `--headless --test` 时，因 **PowerShell 不等待 GUI 子系统进程**，产生一个 0 字节输出、未监听任何端口的滞留进程 **PID 33040**；我确认后 kill 并用 Python `subprocess` 重跑，门③④ 的真实结果来自重跑（§6.1/6.2）。它未占用 9877/9888/9889 |

## 8. 对抗性

1. **C# 异常穿过 GDScript 边界**：`running_game_execute_gdscript` 调 `Main.Boom()`（抛 `System.Exception`）→
   工具返回 `{"result":null,"result_type":"Nil"}`；游戏 stderr 可观测到完整证据链：
   `ERROR: System.Exception: audit-boom`、`at Main.Boom() … Main.cs:line 45`、`CSharpInstanceBridge.Call`、
   `GDScript backtrace [0] _mcp_execute`。**模块未崩溃**：随后 `running_game_get_node_properties` 与
   `running_game_execute_gdscript` 均正常作答。
2. **同名节点冲突**：在 `Main` 下再建一个名为 `Label` 的子节点 → Godot 自行改名（返回 `@Label@2`），模块继续正常应答（C# 报告照常）。
3. **无帧缓冲能力**：headless 下 `running_game_capture_frames` → `-32000` + suggestion，不返回假帧。
4. 上述均未导致进程退出/重启，日志里没有 `CrashHandler`/access violation。

## 9. defects

| id | severity | claim | evidence（我自己跑的） | location | recommendation |
|---|---|---|---|---|---|
| **D-AUDIT-1** | minor（文档/事实陈述） | PLAYBOOK §3「C# 的 `public` 字段不是 Godot 属性，只有 `[Export]` 成员才在**游戏侧节点工具读写的属性面**里」；scratch `Main.cs` 注释「`running_game_set_node_property` cannot reach it」 | 全量列举 29 键**不含** `PlainField`（属性表结论正确，源码 `csharp_script.cpp:1510-1521`）；但 `set_node_property{PlainField,7}` **成功**（`old_value:4242` → `new_value:7`，sha `4fb63138…`），过滤读返回 `"PlainField":7`（源码 `csharp_script.cpp:1487-1508`：`CSharpInstance::get/set` 经托管桥按名解析） | `modules/mcp_server/docs/tasks/PLAYBOOK-group-port.md` §3 事实②；`%TEMP%\mcp014-scratch\m3-csharp-proj\Main.cs` 注释 | 把措辞收紧为「非 `[Export]` 的 public 字段**不进 `get_property_list()`**，但 `Object::get/set` 仍**可按名**读写（C# 脚本实例的托管桥按名解析字段）」；B3 任务书若要依赖「不可达」这一结论，须改为不可达性的**实测**断言而不是引用该表述 |

未发现任何「必核」项失败：D-1/D-2/D-3/R-3、构建绑定、C# 轴、共存、四道门、端口纪律全部通过。上面这条是本次审计发现的**唯一**缺陷，且属文档性（不影响工具可用性：写入是真实发生的，`-32001` 语义对真正不存在的名字仍然正确）。

## 10. unconfirmed（无法确认/未构造，显式声明）

1. **宣称里的具体 tick 数**（`1428 → 1564`）：计时相关，不可能逐字复现。我复现的是**可判据**：`CsharpTicks` 单调递增（947→1314、620→1060）且由 C# 的 `_Process` 驱动。
2. **`build_assemblies.py` 未重跑**（取舍见 §2.4）：`bin\GodotSharp\**` 与 4 个 nupkg 的**可用性**由「glue 逐字节可复现」+「离线 `dotnet build` 成功消费」两条间接但独立的证据支撑；其构建过程本身本轮未复现。
3. **D-3 的正路径（缺省 `events` 且本进程有**非空**可用录制）**：headless 下没有输入源，`stop_input_recording` 实测 `event_count=0`，此时缺省回放按设计返回 `-32602`。要构造该路径需要能注入真实输入（窗口化或模拟输入），本轮未做。
4. **mono 构建下的 doctest**：mono 目标未带 `tests=yes`，未测（任务书也未声称）。

## 11. risks

1. **R-1 同源风险再犯**：到货二进制并非 HEAD 绑定（`eb05a50ed` vs `6ea5de6e0b`）。本次差异只在文档/脚本（编译输入等价），我重建后门才成立；若后续批次不改流程，门仍可能在陈旧/错标产物上跑出假绿或假红。
2. **`--import` 在全新 scratch 工程上的一次崩溃**（**非模块责任**）：对**首次**导入（尚无 `.godot`）且 `scenes/main.tscn` 带 UTF-8 BOM 的工程，
   `--headless --path <proj> --import` 曾返回 **0xC0000005（access violation）**，stderr 有
   `ERROR: res://scenes/main.tscn:1 - Parse Error: Expected '['`（BOM 首字符）与 `ERROR: Parameter "singleton" is null. at: EditorNode::is_cmdline_mode`；
   同一工程**第二次**导入（有缓存）exit 0，BOM-free 的全新工程 exit 0。门脚本 (`accept_m1.ps1`/`check_contract_subset.ps1`)
   用 `Set-Content -Encoding UTF8`（BOM）造 scratch `.tscn` 且**不校验** import 退出码 → 该崩溃目前是隐性的；本次所有门仍 22/22、3/3 通过。
3. **默认端口 9877**：`godot_mcp` 启用但未传 `--mcp-port` 时模块会尝试 bind 9877，我的导入/校验进程实测
   `WARNING: [MCP] bind failed on 127.0.0.1:9877; MCP server disabled`（用户的 36392 占着，OS 拒绝，模块优雅自禁）。
   本次未影响用户进程，但若测试进程先于用户编辑器启动，就可能抢到该端口。
4. **REPORT-014 §6 的二进制 sha256 已失效**（我的重绑定导致）；`bin/` 不受版本控制，任何依赖这些指纹的下游证据需重取。
5. **残留 TIME_WAIT**：9888/9889 收尾有大量 pid=0 的 `TIME_WAIT`（高频用例所致），不占端口，但会让「立即可重用端口」的紧随测量偶发 `bind failed`（门①/⑤ 已按此设计等待）。

## 12. next_step_recommendation

1. **可以进入下一批（B3）**：本次审计未发现功能性阻塞。把 §9 D-AUDIT-1 的措辞修正写进 B3 任务书，避免 B3 在 C# 工程上按「不可达」假设做设计。
2. **流程**：把「开工先 `--version` 对 HEAD，否则重建」与物理绑定证据写进每批任务的第 0 步（本次已是第二次踩到）；顺带在 PLAYBOOK §3 记一条「`--import` 退出码必须校验，scratch `.tscn` 不要写 BOM」。
3. **契约变更（D-3）**：已可视为收口；后续若再改契约，建议同时保留 `de87d1c737` 式的「结构化 diff」自证（工具集合不变 + 只动目标字段 + `_meta` 指纹）——本次审计正是用这条证明「只含该工具的 description/required + `_meta`」。
4. **C# 轴**：`hoh doctor` 预检按 §3.5 的事实表落地；另外在预检里加一条「离线包源里存在 `Godot.NET.Sdk.<版本>.nupkg`」比「公网可达」更有意义。

## 13. 证据索引（本轮全部在 `%TEMP%\audit-m3\`）

| 证据 | 位置 |
|---|---|
| 门③/④ 完整日志 + 摘要 | `gate3-doctest.log`、`gate4-fullengine.log`、`gates34-summary.txt`、`gate-version.txt` |
| 门① / 门⑤ | `gate1-contract-subset.log`、`accept-run1.log`、`accept-run2.log`、`gates5-summary.txt` |
| 我自己的 live 探针（请求 + 响应落盘，含 sha256） | `evidence/*.req.json`、`evidence/*.resp.json`（78 个文件）、`phaseA2-summary.txt`、`phaseB-summary.txt`、`phaseC-summary.txt` |
| 契约 D-3 结构化 diff 与逐字描述 | `d3_contract_diff.py`（执行输出）、`d3_desc_utf8.txt`（UTF-8 逐字）、`contract-compare.txt`（49/40 条逐字比对） |
| mono/非 mono 一致性 | `compare_builds.py` 输出、`mono-vs-nonmono.txt` |
| glue 重生成与逐字节比对 | `glue-generate.log`、`glue/GodotSharp/**`（1110 文件） |
| 构建 | `%TEMP%\mcp_server_build_local.log`（`EXIT_CODE=0`、`00:00:32.20`）、`mono_scons.log`（`00:01:39.82`、`done building targets`） |
| C# 与 dotnet | `dotnet-build-mycopy.log`、`logs/A2-*.log`、`logs/C-their-*.log`、`csharp-proj/**` |
| 关键响应 sha256（摘） | `-32001` 未知属性 `fae90a32…`；`-32000` 截图 `f0bf449c…`；`-32602` 参数 `ec73a028…`；`-32602` 无录制 `f0dba6bd…`；R-3 超时 `e1dfe0ab…`（mono）/`d6579651…`（非 mono）；`PlainField` 写入 `4fb63138…`；C# 报告 `f81c9657…` |

**总 verdict：pass。** 所有「必核」项均由我自己的可复现证据支持；唯一缺陷是 PLAYBOOK 一处措辞过强（minor，文档性），另有 5 条风险（多为流程/环境类）供下一批处理。
