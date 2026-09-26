# TASK-024a — 顺手性 E-10：`editor_play_scene` 注入 `--mcp-port`（**拆分后的单点任务**）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-024a-e10-play-scene-port.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 为什么要拆（背景，读一下）

原 **TASK-024** 把 5 个顺手性项（E-10/E-1/E-3/E-9/E-6）放在一个任务里，**上一个执行者中途耗尽上下文而失败**：
工作树里留下了**契约已重生成、但工具代码还没改**的**不一致半成品**，被决策者回退。
**教训**：含「契约 override + 重生成指纹 + 引擎新行为 + 证据链」的一项，本身就接近一个任务的上限。
→ 本任务**只做 E-10**。

**⚠️ 有一份半成品补丁可供参考，但它是未验证的**：
`C:\Users\wyl\AppData\Local\Temp\task024-partial.patch`（36186 B，已从工作树回退）。
它包含：`SCHEMA_OVERRIDES["play_scene"]`（新增可选 `mcp_port`）、
`DESCRIPTION_OVERRIDES["play_scene"]`（说明端口从哪来）、`GENERATOR_VERSION` 1.5.0→1.6.0、
重生成后的 `tools_list.renamed.json`、399 行 doctest、53 行 `DESIGN-DETAIL` 文字。
**你可以参考它**（能省很多时间），但**必须自己复核**：它是**未验证的**，且**工具侧代码它没写**。
**最终结果由你负责**；认为它的做法不对就丢掉并自己来，并在报告里说明。

## 1. 要做的事（E-10）

**现状**：`editor_play_scene` 启动的游戏子进程 cmdline **没有** `--mcp-port`
（实测只有 `--path/--remote-debug/--editor-pid/--scene`）→ 游戏只能读
`ProjectSettings: godot_mcp/port`；**想让游戏被 MCP 观察就得改被测工程设置**（多步舞蹈）。

**引擎正解**：`editor/run/editor_run_bar.h:117/123-125` 的
`play_main_scene / play_current_scene / play_custom_scene(..., const Vector<String> &p_play_args)`；
`editor_run_bar.cpp:355-364` 把 `p_play_args` 交给 `editor_run.run()`。
（`editor_node.cpp:7797 → editor_plugin.h:218 virtual void run_scene(const String&, Vector<String>&)`
是给 **EditorPlugin** 的钩子；**内置模块**走 `EditorRunBar` 单例即可。请自己确认这条路径在本 fork 下可用。）

**要求**：
1. `editor_play_scene` 起游戏时**注入 `--mcp-port=<端口>`**，使编辑器起的游戏**立刻可被 MCP 观察**，
   **不需要改被测工程**。
2. **端口选择**：可选参数 `mcp_port`（调用方可指定，便于自动化用固定端口）；
   **缺省自动挑一个空闲端口**，且**必须与编辑器自身端口不同**（否则子进程 bind 失败）。
3. **响应必须告知端点**：`mcp_port`、端口来源（`mcp_port_source`）、可直连的 `endpoint`、游戏 `pid`，
   使调用方**立刻能连**，不必猜、不必读日志。
4. **不得假装成功**：注入失败、引擎 guard、非编辑器进程、游戏起不来等情形，**诚实报错**。
5. **契约**：新增可选参数属输入 schema 变更 → 用 **`SCHEMA_OVERRIDES`**（`mode=replace` + 理由逐字引用被移除的
   `required` 成员）+ **`DESCRIPTION_OVERRIDES`**（写清端口来源），**重生成契约 + 重渲染 `TOOL-NAMING.md` + 更新全部指纹**，
   并让**门① 在两端点上逐字通过**。**不得手改契约文件**。

## 2. 证据（必须实测，不得推断）

1. **子进程 cmdline 实测包含 `--mcp-port=<你选定的端口>`**（给出实际命令行文本）。
2. **从该端口真的连上并跑一个游戏侧工具**（例如 `running_game_get_scene_tree` 或
   `running_game_get_node_properties`），证明「起游戏 → 立刻观察」闭环。
3. **端口选择**：`mcp_port` 指定时用它；缺省时自动挑的端口**≠ 编辑器端口**且**真的可用**；
   指定一个**已被占用**的端口时的行为（诚实报错或明确回退，说明选择）。
4. **响应字段**（`mcp_port`/`mcp_port_source`/`endpoint`/`pid`）与真实情况一致（自己核对 pid 与端口）。
5. **门①** 两端点契约逐字通过（含 override 后的新 schema）。
6. **门⑥**（收窄点清单）通过。

## 3. 门

- 第 0 步：`modules/mcp_server/scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD。
- 五道门（①按本组 `editor_playback` 跑）+ **门⑥**。
- 回归：`editor_play_scene` 的**原有**行为（`mode` 的三种取值：`main`/`current`/路径）不得破坏；
  给出三种模式各一次的真实证据。

## 4. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-024a-e10-play-scene-port.md`；另加：
「半成品补丁的采纳/丢弃说明（逐项）」「cmdline 实测文本与端口来源」「起游戏→观察闭环证据」
「缺省端口挑选逻辑与冲突处理」「契约 override 的 `_meta` 与指纹」。
**返回值：≤15 行总结 + 报告路径。**