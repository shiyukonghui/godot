# TASK-013 — B2 收官：移植组 `editor_input_simulation`（6 个工具）+ 录制上限 + 规范条款

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-013-b2-closure-editor-input-simulation.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 状态

B2 已完成 **19/25**；本任务完成后 B2 = **25/25**，随后进入 **M2 里程碑独立验收**（覆盖 B1+B2 全部 66 个工具）。

## 1. 组 `editor_input_simulation`（6 个工具，**B2 的最后一组**）

成员以 `docs/tool-groups-b2.json` 为准（预计）：`editor_simulate_input_action`、`editor_simulate_key`、
`editor_simulate_mouse_click`、`editor_simulate_mouse_move`、`editor_simulate_input_sequence`、
`editor_add_input_action`（旧 `set_input_action`，创建型 → `add_`）。

要求：
1. **编辑器专有**：全部走 `MCP_EDITOR_TOOLS_ENABLED` 守卫；**必须缺席于游戏端点 9889**，
   且在游戏进程调用必须得到 `-32601` 且**不执行**（给真实响应）。
2. **必须在报告里显式复述并实测 D59 / `DESIGN-DETAIL` §19（GDR-21）的边界**：
   `editor_*` 输入工具注入的是**编辑器进程**的 `Input`/`InputMap`，**不能驱动游戏**。
   TASK-012 已给出双向线上证据；本组必须**自己再给一组**（编辑器侧可观察的输入状态变化，
   以及**同一动作对游戏端点没有任何影响**的对照——例如注入后从 9889 读游戏节点状态，值不变）。
   这条对照是本组**最有价值**的证据，因为它把「为什么编辑器注入驱动不了游戏」钉在实测上。
3. `editor_add_input_action` 写的是 `InputMap`（编辑器进程），**不落盘**到 `ProjectSettings`；
   若迁移源有落盘行为，须按手册 §6.6 判定并显式记录。
4. 参考 TASK-012 的 editor 侧写法（`editor_playback`/`editor_input_read` 已把 editor-scope 的声明、
   非编辑器进程拒绝、端点缺席都走通）。

## 2. 录制上限（D59 第 5 条 / `DESIGN-DETAIL` §19.5）

TASK-012 新增的录制设施（`tools/input_recorder.{h,cpp}`）**目前无长度上限**：
长时间录制会持续持有事件、无界增长内存。→ 实现**可配置上限**（事件数与总时长各一个，
默认值取合理值并在报告中说明理由），达到上限时：
- **停止采集**；
- 在 `running_game_stop_input_recording` 的结果里报 **`truncated: true`** 与已达的上限值；
- **不得**静默丢弃、**不得**崩溃、**不得**只截断而不标记。
补 doctest（含一个把上限调小后确定触发截断的用例）。

## 3. 门

按 `PLAYBOOK-group-port.md` §3 五道门（门①用 `-Group editor_input_simulation`，**逐端点 scope 语义**），
外加 §1.2 的边界对照证据与 §2 的截断证据。完成后给出 **B2 = 25/25** 的机器校验输出
（`check_tool_groups.py --batch B2` + 已实现并集计数）。

## 4. 报告

按手册 §4，写到 `docs/reports/REPORT-013-b2-closure-editor-input-simulation.md`；
另加：「D59/GDR-21 边界的本组实测对照（编辑器变化 vs 游戏无变化）」「录制上限与截断证据」
「B2 收官计数 25/25」。**返回值：≤15 行总结 + 报告路径。**