# TASK-012 — B2 第三批：游戏输入/节点写/编辑器播放/输入读取（8 个工具）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-012-b2-input-playback-groups.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 1. 组与成员（**以 `docs/tool-groups-b2.json` 为准**，共 8 个工具）

| 组 | 数量 | 说明 |
|---|---|---|
| `running_game_input` | 4 | 运行中游戏的输入录制/回放族（`running_game_create_input_recording`、`running_game_stop_input_recording`、`running_game_play_input_recording`、`running_game_simulate_button_click_by_text`） |
| `running_game_node_write` | 1 | `running_game_set_node_property`（游戏进程内改节点属性） |
| `editor_playback` | 2 | `editor_play_scene`、`editor_stop_scene`（编辑器发起播放/停止） |
| `editor_input_read` | 1 | `editor_get_input_map_actions`（读编辑器的 `InputMap`） |

> 若 `tool-groups-b2.json` 里的成员与此表不一致，**以 manifest 为准**并在报告里注明差异。

## 2. 本批的关键纪律（**必须写进报告**）

1. **禁止混淆两个进程的输入**（`DECISIONS.md` **D56** / 映射裁定）：
   `editor_*` 的输入类工具（含 `editor_add_input_action`、`editor_simulate_*`）作用于**编辑器进程**的
   `Input`/`InputMap`；**驱动游戏**必须走 `scope=game` 的工具。
   请在报告里明确写：**`running_game_input` 组的 4 个工具驱动的是游戏进程**，
   并给出「**在游戏进程内**注入/回放输入 → 观察到游戏状态变化」的证据。
2. **`running_game_set_node_property`**：改的是**运行中游戏**的节点；证据必须包含「改前值 → 调用 → 改后值」，
   并覆盖「越界/类型错」的参数拒绝（复用 TASK-010 已修的 `coerce_to_property_type` 语义：越界 → `-32602`）。
3. **`editor_play_scene` / `editor_stop_scene`**：发起/停止播放是**编辑器**行为 → 它们**必须缺席于游戏端点 9889**；
   证据要能显示「调用后游戏进程真的起来了 / 真的停了」（例如随后游戏端点可/不可用，
   或在编辑器端点读到播放状态）。**注意**：播放会产生一个**游戏子进程**，本批必须确保该子进程
   使用了**测试端口**（`--mcp-port=9889`）、且**测试结束时不留下孤儿进程**（报告里给出进程清理证据）。
4. **`editor_get_input_map_actions`** 读编辑器 `InputMap`；若映射里有 `editor_get_input_actions` 之类的成对工具，
   注意**读**与**写**分开（写属 B3/B5），不要越界。

## 3. 门

按 `PLAYBOOK-group-port.md` §3 五道门（门①按**四个组各跑一次**；注意**逐端点 scope 语义**），
外加 §2 的三条证据（游戏侧输入驱动、属性写前后、播放/停止的进程级证据与清理）。

## 4. 报告

按手册 §4，写到 `docs/reports/REPORT-012-b2-input-playback-groups.md`；
另加：「两个进程输入的分野（D56 纪律）」「游戏侧输入驱动的端到端证据」
「播放/停止的进程级证据与无孤儿进程证明」。**返回值：≤15 行总结 + 报告路径。**