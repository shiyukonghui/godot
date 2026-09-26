# TASK-014 — M3：mono 构建 + C# 工程可跑（含 M2 验收的 3 项修复）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含；**注意 §3 新增的「门必须先绑定构建」**），再读本文件。
> 报告写到 `docs/reports/REPORT-014-m3-mono-csharp.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 背景

用户要求**用 C# 作为游戏开发语言**（见 `docs/DESIGN-DETAIL.md` §11 / GDR-10 与 hof-rs 的 PRD P7/P8）。
因此 **M3 = mono 构建 + 一个 C# 工程真的能跑**，且**内置 MCP 模块在 mono 构建下照常工作**。
这是必须尽早验证的一条轴：若 mono 构建与模块有冲突，越晚发现越贵。

## 1. 第一部分：修掉 M2 验收的 3 个缺陷 + 1 条加固

1. **D-1（minor，诚实性）**：`running_game_set_node_property` 对**不存在的属性**返回成功形状
   （`new_value:null`）→ 改为 **`-32001` + `data.suggestion`**（属性不存在），并在结果里不再出现「假成功形状」；
   补 doctest（真实属性写入仍成功；不存在的属性 → `-32001`）。记入手册 §6.6 的第 7 例（迁移源同样无条件 `set:true`）。
2. **D-2（nit，一致性）**：headless 下 `editor_capture_screenshot` 用 `-32603` 收尾 →
   与 GDR-20 第 10 条统一为 **`-32000` + `data.suggestion`**（能力不支持），`-32603` 只留给真正的内部错误。
3. **D-3（nit，契约与行为不一致）**：契约里 `running_game_play_input_recording` 的
   `inputSchema.required` 仍是 `[events]`，而实现（依 D59 裁决 1）允许缺省。
   **决策者裁决：契约改成与行为一致** —— 用 `scripts/gen_renamed_contract.py` 的 **`SCHEMA_OVERRIDES`**
   （若该机制不存在则按 `DESCRIPTION_OVERRIDES` 的先例新增，理由写进 `_meta.overrides`）：
   把 `events` 从 `required` 移除，并在 **description 里写清回退规则**：
   「缺省 `events` = 回放**本游戏进程内最近一次 `running_game_stop_input_recording`** 的录制；
   若本进程没有可用录制则 `-32602`」。
   然后**重跑生成器 + 重渲染 `TOOL-NAMING.md` + 更新所有指纹**（`_meta.map_sha256`、文档头部等），
   并**同步 C++ 侧该工具的 description 字面量**（否则门①会失败）。
   **注意**：这是 M2 验收点名的「契约文本变更」，改完必须让门①在两端点上仍逐字通过。
4. **R-3（加固）**：`mcp_server/pending_timeout_ms` 允许配成 `0`，而 0 会**关闭延迟任务的唯一兜底** →
   改为「`<=0 ` 视为使用默认上限（30 s）」或显式拒绝并在启动时警告；补 doctest 或启动日志证据。

## 2. 第二部分：mono 构建（M3 的主体）

1. **环境**：需要 .NET SDK（本机已有 `9.0.100/9.0.300`）与 .NET 8 运行时时（mono 目标框架是 `net8.0`）。
   先检查并记录 `dotnet --info` 的真实输出。
2. **构建步骤**（务必照官方 mono 流程，并在报告里给出每一步的真实命令与输出）：
   - 以 `module_mono_enabled=yes` 构建编辑器目标（`target=editor`）；
   - 生成 mono glue；构建 `modules/mono/glue/GodotSharp`（`dotnet build`）；
   - 产出可用的编辑器二进制；记录**构建时长**与**退出码**。
   - **不要**在同一 `bin/` 里覆盖掉非 mono 二进制而不留证据：若会互相覆盖，就先备份/改名，
     并在报告里说明最终留下的二进制是哪一种（后续批次需要知道）。
3. **断言模块共存**：mono 构建下，内置 MCP 模块**照常工作**：
   - 编辑器端点 9888 能起、`tools/list` = 49（或当前实现的编辑器并集数）；
   - 用 C# 工程起的游戏在 **9889** 上能起、`tools/list` = 40（当前游戏并集数），
     且**游戏侧工具在 C# 游戏进程内可用**（例如 `running_game_execute_gdscript` + 读节点属性）。
4. **注意**：`tests=yes` 与 mono 的组合若不可行，可分别构建（mono 构建不必跑 doctest；
   doctest 仍由非 mono 构建承担）——但要在报告里说清，并保证**两个构建的模块源码一致**（同一 commit）。

## 3. 第三部分：C# 工程真的能跑（M3 的验收核心）

1. 在 `%TEMP%` 造一个**最小 C# 工程**（`project.godot` + `.csproj` + 至少一个 `.cs` 脚本，
   脚本挂到节点上并产生**可观测输出**——例如在 `_Ready` 里打印、并暴露一个可被
   `running_game_execute_gdscript` 或 `running_game_get_node_properties` 读到的状态）。
2. **门 M3-C#**：
   - `dotnet build` 成功（贴真实输出与退出码）；
   - 该工程以 **C# 脚本**运行（`--headless` 或窗口化，用测试端口），并证明**C# 代码真的执行了**
     （日志/状态证据，不是「文件存在」这种间接证据）；
   - 从 **9889** 用 MCP 工具读到该 C# 脚本产生的状态（跨语言可见性）；
   - 收尾：**无孤儿进程**、9888/9889 无 LISTENING、**9877（用户 PID 36392）全程未被触碰**。
3. 记录 C# 相关的**版本事实**（`dotnet --version`、目标框架、Godot 的 mono 版本字符串），供 hof-rs 的
   `hoh doctor` 预检使用（hof-rs 侧以后要用，本次只需把事实写进报告）。

## 4. 报告

按手册 §4 结构（本任务不是普通工具组，故 §4 的「逐工具表」改为「逐项 M3 断言表」），
写到 `docs/reports/REPORT-014-m3-mono-csharp.md`；另加：
「mono 构建全流程命令与输出」「构建产物与最终 bin 状态的说明」「C# 工程运行的直接证据」
「D-1/D-2/D-3/R-3 的前后对照」。**返回值：≤15 行总结 + 报告路径。**