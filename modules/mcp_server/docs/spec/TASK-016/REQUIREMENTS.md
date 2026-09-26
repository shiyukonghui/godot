# TASK-016 — REQUIREMENTS（阶段一工件，决策者维护）

> 本目录是 **决策过程**工件（需求 / 概要设计 / 详细设计），**不是**运行时规范。
> 运行时规范仍是 `docs/DESIGN-DETAIL.md` / `docs/tool-groups-b3.json` / `docs/tools_list.renamed.json`；
> 实现者只在 `docs/reports/REPORT-016-b3-node-read-instantiate.md` 写报告（PLAYBOOK §7.2 的不创建竞争规范之纪律）。
> 执行者为全新子代理，本目录对它的作用 = 把 TASK-016 的任务书落到可实施粒度。

## 1. 目标（不可再分的目的）

TASK-016（`docs/tasks/TASK-016-b3-node-read-instantiate.md`）有三件事，按依赖顺序：

1. **助手上提**：把编辑器侧**节点路径解析**（`_find_node`）及其依赖上提到 `tools/tool_helpers.*`，
   删除各调用者的本地副本，并给出**与重构前逐字节等价**的证明。
2. **本批移植接下来 2 组**（≤20 个工具，优先 `editor_node_read`），并更新 manifest 的 `implemented`。
3. **写族→读族互验的活证据链** + **本批后已实现总数与剩余计数**。

## 2. 非目标

- 不改契约（`docs/tools_list.renamed.json`）、映射（`docs/tool-rename-map.json`）、任何生成器。
- 不改 B1/B2 任何工具的**行为**（本次对 B1 组文件的编辑只允许删除已上提的本地副本）。
- 不顺手「修好」迁移源的怪癖（PLAYBOOK §6.8），除非它让工具不可用（PLAYBOOK §6.6）。
- 不引入新依赖、不访问 `100.105.152.101:18080`、不 push。
- 不动引擎其它目录、`godot_mcp_gdext`、`F:\moonbit-hof-rs`。

## 3. 已确认的事实基线（自下而上）

| 事实 | 证据 |
|---|---|
| HEAD = `c26516becc`，分支 `feature/mcp-server-module`，工作树只剩 4 个既有未跟踪物 | `git status --short` |
| 已实现 76 个（编辑器进程可见 59，游戏进程 40） | `tests/test_mcp_server.h:7255-7263` |
| B3 manifest 12 组 40 个工具，仅 `editor_node_write` 为 `implemented=true` | `docs/tool-groups-b3.json` |
| 编辑器侧跨组重复：`_find_node` **2 份**、`_edited_scene_root` **3 份**、`_relative_path` **1 份** | `grep '^static .*_find_node\|_relative_path\|_edited_scene_root' tools/*.cpp` |
| `write_node_property` 已经是**一份共享定义**（`tools/running_game_node_write.{h,cpp}`） | 只有 1 处定义，`editor_node_write.cpp` 已在用 |
| 门必须绑定二进制：`--version` hash 前缀 == `git rev-parse --short HEAD` | PLAYBOOK §3 第 0 步 / R-1 |
| 迁移源的位置在本机是 `F:\RustProjects\godot-mcp-pro\godot_mcp_gdext\src\commands\*` 与 `F:\RustProjects\godot-mcp-pro\addons\**`（**只读**） | 实测（PLAYBOOK 写作时的相对路径已不适用） |

## 4. 硬性约束（违反即 fail）

1. 只允许改 `modules/mcp_server/**`。
2. 绝不占用 / 杀 / 重启 **9877**（用户 Godot 4.7.1-mono，PID 36392）；测试端口 **9888（编辑器）/ 9889（游戏）**；scratch 放 `%TEMP%`。
3. 构建**串行**、**不抑制输出**、不并发跑两个 scons（D62）；改 `tests/*.h` 后先删陈旧 `test_mcp_server` / `test_main` 对象。
4. 证据一律 `curl.exe -s -o <file>` 落盘 + sha256，请求体用 `ConvertTo-Json` 写文件后 `--data-binary @file`；禁止 `Out-File` 承载响应体（PLAYBOOK §7.1）。
5. scratch 的 `.tscn` **不写 BOM**，且 `--import` 必须校验退出码（PLAYBOOK §3）。
6. 全部工具仅经 `MCPTools::ToolBuilder` 注册；`scope=editor` 者必须缺席于 9889 且游戏进程调用回 `-32601` 不执行。
7. 未实现者不得注册；不得注册两个 `unregister_until_implemented`。
8. 不伪造任何输出（之后有**全新子代理**独立验收）。

## 5. 验收标准（逐条可验）

| id | 标准 | 判定方式 |
|---|---|---|
| A1 | `_find_node` 与 `_edited_scene_root` 在模块内**各只有一处定义**，且在 `tools/tool_helpers.*` | `grep -c '^static Node \*_find_node'` = 0；`grep` 命名空间内定义 = 1 |
| A2 | 上提**不改变行为**：同一请求序列在重构前后响应**逐字节相同** | 对照提交 = 重构前那一刻（`c26516becc`），脚本对同一序列算 sha256 并逐个相等 |
| A3 | 两组共 10 个工具全部注册、契约 `name`/`description`/`inputSchema` 逐字相等 | 门①（9888 与 9889 各条 True） |
| A4 | `scope=editor` 的 10 个工具缺席于 9889，且 9889 调用回 `-32601` | 门② 的 scope 缺席证据 |
| A5 | 每个工具都有 成功 / 缺参 / 底层失败 三类真实请求-响应 | 门② |
| A6 | 每组各一条**跨工具活证据链**；读族链必须**用 TASK-015 的写族改、用本批读族读回** | 门② |
| A7 | 模块 doctest 全绿（`--test-case="[MCPServer]*"`），全引擎回归 0 failed | 门③/门④ |
| A8 | `accept_m1.ps1` 连跑两次全过且 PASS 清单一致 | 门⑤ |
| A9 | manifest 两组的 `implemented` 置 `true` | `docs/tool-groups-b3.json` |
| A10 | 报告给出**本批后已实现总数与剩余计数** | 报告 § |
| A11 | 报告给出**红/绿两阶段真实输出**、四/五道门真实输出与退出码、sha256、deviations/blockers | 报告 |

## 6. 假设与待确认问题（决策者代答，交互通道不可用，逐条给理由）

| # | 问题 | 决策 | 理由 |
|---|---|---|---|
| Q1 | 取哪两组？ | `editor_node_read`(6) + `editor_node_instantiate`(4)，合计 10 | manifest 中紧接 `editor_node_write` 的两组，正好是任务书建议的「read + 实例化」，总数为 76+10=86 ≤ 上限 |
| Q2 | `editor_get_node_properties` 的 `properties` 过滤请求了不存在的属性名怎么办？ | `-32001` + `data.suggestion`，记 PLAYBOOK §6.6 第 8 例 | 任务书 §2.3 明文硬要求「未知属性…一律 -32001，不得产出成功形状」；迁移源「过滤后剩空即静默回 `properties:{}`」正是「什么也没发生被读成已成功」的第 8 例 |
| Q3 | `properties` 数组里有非字符串元素怎么办？ | `-32602`（不静默丢弃） | PLAYBOOK §6.2 已确立：「optional_* 存在但类型错 → -32602」，TASK-015 的 `editor_set_node_groups` 同处置 |
| Q4 | 上提哪些？ | `_find_node` + `_edited_scene_root`；`_relative_path` 原地不动 | 前者各有 2/3 份真实重复；`_relative_path` 只有 1 份，§1.4 明令「不要顺手改行为」 |
| Q5 | `node_path` / `path` 回显要不要归一？ | 回显**解析后**的相对路径（`_relative_path`），不是调用方原文 | PLAYBOOK §6.7「路径参数一律归一后回显」；`editor_get_node_properties` 迁移源回显原文，属该条要纠正的偏离 |
| Q6 | 写族链的证据工程在哪？ | `%TEMP%` scratch 工程副本，只在其上做破坏性操作 | 任务书 §2.4 |
| Q7 | 上提是否需要「对照提交」的物理重建？ | 需要：`git stash` 或临时 checkout 该提交重建 before 二进制，采完证据再回到 after | A2 要求对照提交 = 重构前那一刻；门不能跑在陈旧二进制上（R-1） |