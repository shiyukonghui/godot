# TASK-010 — B2 开局：manifest + 游戏侧观测组（**E3 解锁点的第一刀**）+ 3 项小修

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-010-b2-manifest-game-observation.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 背景

**B1 已收官 41/41**。现在进入 **B2 = 25 个工具**（`docs/DESIGN-DETAIL.md` §10），
它是 **M2 的 E3 解锁点**：让「游戏可玩性」可被自动判定。

关键事实（决策者已裁定，见 `F:\moonbit-hof-rs\DECISIONS.md` D56）：
- 内置模块**同时存在于游戏进程**，因此 `scope=game` 的工具**在游戏进程内直接执行**，
  不再需要 GDExtension 时代的 `user://` 文件 IPC。
- **`running_game_execute_gdscript`**（旧 `execute_game_script`）是在游戏进程内跑脚本的能力，
  **取代了迁移源里受 `Expression.execute([], base, false)` 限制的旧路径**（旧路径连 `Input` 单例都够不到）
  → **这是 E3 解锁的杠杆点**。
- 映射把 `editor_simulate_*` 定为 `channel=editor`（它们当年注入的是**编辑器进程**的 `Input`，正是 E3 根因），
  **不得**把「驱动游戏」寄托在它们身上；游戏侧驱动必须走 `scope=game` 的工具。

## 1. 第一部分：产出 B2 manifest

新增 `docs/tool-groups.json` 的**姐妹文件** `docs/tool-groups-b2.json`（不要改 B1 的文件），结构一致：

```json
{ "batch": "B2", "total": 25, "groups": [
  { "name": "<组名>", "channel": "...", "scope": "...", "mutating": true, "implemented": false, "tools": ["<new_name>", ...] } ] }
```

要求：
1. B2 的 25 个工具**恰好各出现一次**（双向差集为空；报告里给机器校验的真实输出）；
   名字必须都存在于 171 条契约；`DESIGN-DETAIL` §10 的 B2 清单是旧名 → 用 `docs/tool-rename-map.json` 换算成新名。
2. 分组依据：**`scope` + 通道 + 依赖**；每组应能放进一个 `tools/<group>.{h,cpp}`，且组 ≤10 个工具。
3. 建议至少区分出：**游戏侧观测/驱动组**（`scope=game`）、**编辑器播放/输入组**（`channel=editor`）。
4. 每个组给出 `implemented: false`，除你本任务实际完成的那一组。

## 2. 第二部分：移植**游戏侧观测组**（本任务的实质交付）

从 manifest 里挑出「**游戏侧观测/驱动**」这一组（`scope=game`，只读或最小副作用），建议包含
（以你换算出的新名为准）：`running_game_get_scene_tree`、`running_game_get_node_properties`、
`running_game_get_node_property_samples`（旧 `monitor_properties`）、`running_game_find_nodes_by_script`、
`running_game_get_autoload`、`running_game_get_properties_batch`、`running_game_execute_gdscript`
——**若某工具属于其他组，不要硬塞**；你可在报告里说明最终组内成员与理由。

**本部分的验收重点：把 E3 杠杆点钉死。**
必须给出一条**从 9889（游戏进程端点）发起**的完整证据链，证明：
1. 能在游戏进程内**读取运行中的场景树与节点属性**（贴真实响应）；
2. 能通过 **`running_game_execute_gdscript`** 在游戏进程内执行脚本，
   并**读到引擎单例**（例如 `Input` / `Engine` / 场景节点）——这是旧路径做不到的事，
   **要显式对比说明「旧路径为何做不到」**（旧实现用 `Expression.execute([], base, false)`，
   只能解析 base 的成员，`Invalid named index 'Input' for base type Object`）；
3. **在游戏进程内注入输入并观察到可观测的状态变化**
   （例如：脚本里用 `Input.parse_input_event` 投递一个动作/按键 → 随后同一进程内读到某个节点的位置/状态确实变了）。
   这是 E3 的核心能力证据；若某一步在本环境不可行，**必须显式说明卡在哪并给出最小反例**，不要含糊过去。
4. 说明：这条证据链**不需要编辑器进程参与**（除启动游戏本身）。

## 3. 第三部分：3 项小修（决策者已裁决，见 D56）

1. **`MCPToolError::no_scene()` 的 `data.suggestion` 按 `scope` 自适应**：
   game-only 工具不得再说「请先用 `editor_open_scene`」；改为中立或按 scope 给出各自可用的工具名。
   （注意：该分支在编辑器端点上不可达，改动只影响游戏侧与 doctest——报告里说明措辞规则即可。）
2. **绑定成功时打印 INFO**：MCP 服务成功监听时打印一条 **INFO（端口 + 进程类型：editor/game）**，
   使 `--import` 之类的意外绑定**可见**（默认端口仍保持 9877/0，不改，见 GDR-4）。
3. **修掉两处无守卫的 `double→int64` 强转**（实测越界值 `1e20` 静默变 `0`）：
   `tools/tool_builder.cpp` 的 `_integral_value`，以及 `coerce_to_property_type` 把越界 double 交给 `type_convert` 的路径
   → **越界一律拒绝并返回 `-32602`**，并补 doctest（含 `1e20`、`NaN`、`inf` 的反例）。

## 4. 门

按 `PLAYBOOK-group-port.md` §3 五道门（门①用 `-Group <你实现的组名>`，注意**逐端点 scope 语义**：
本组是 `scope=game`，因此**必须缺席于编辑器端点 9888**，且在 9888 调用必须得到 `-32601`），
外加 §1 的 manifest 校验输出、§2 的 E3 证据链、§3 三项小修的证据。
**注意**：门① 与门⑤ 的脚本可能是按 B1 的 `tool-groups.json` 写的——若需要支持 B2 的 manifest，
请以**最小改动**扩展（并说明），**不得**削弱任何既有断言。

## 5. 报告

按手册 §4，写到 `docs/reports/REPORT-010-b2-manifest-game-observation.md`；
另加三节：「B2 manifest 与组划分理由」「**E3 解锁证据链**（含旧路径对比）」「三项小修的前后对照」。
**返回值：≤15 行总结 + 报告路径。**