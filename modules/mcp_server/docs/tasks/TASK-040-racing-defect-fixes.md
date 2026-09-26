# TASK-040 — 修复实机试测发现的 3 条**疑似缺陷**（+ 同类系统排查）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册），再读本文件；
> 证据原文见 `docs/reports/RACING-FINDINGS.md` §4（**含可直接粘贴的最小复现与源码行号**）。
> 报告写到 `docs/reports/REPORT-040-racing-defect-fixes.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 来源

**实机赛车游戏开发试测**（TASK-039）——开发者**真的**用这套工具做了一台 C# 赛车，
由此发现 3 条**正确性/诚实性**缺陷（**不是**手感问题）。三条都必须**先红后修**。

## 1. **D-1（high）**：`editor_add_resource_to_node_property` 对**不存在的属性**报成功

- 实测：给 `CharacterBody2D` 写 `physics_material_override` → `ok`（180 B，回显 `node_path/property/resource_type`），
  而 `editor_get_node_properties` 读同一属性 → **`-32001`**；属性表 66 项里**没有**该属性。
- 源码：`tools/editor_write_scene_editor.cpp:697` 的 `node->set(property, Variant(resource_ref));` **没有** `object_has_property` 检查，
  `:699-703` **无条件回显**。对照：`editor_set_node_property` 写 `no_such_property_zzq` → **正确地** `-32001`。
- **要求**：写入前先判「该对象是否有这个属性」，没有 → **`-32001` + `data.suggestion`**；
  **并且**属性存在但**类型/类别不接受该资源**时也要明确拒绝（不得回显成功形状）。
- **同类系统排查（必做）**：**扫遍全部写工具**，凡「先 `set()` 再无条件回显成功」的模式，
  **逐条列出**（工具名 + 源码行 + 是否有前置属性检查）→ 有缺口的**一并修**（同口径）。
  （已知历史：`running_game_set_node_property` 在 TASK-014 D-1 已修；本次要证明**编辑器侧与其它写工具都无同类缺口**。）

## 2. **D-2（high）**：`editor_connect_signal` 的连接**不持久化**（存盘即消失）

- 实测：`editor_connect_signal` → `ok {"connected":true,…}`（**响应无 `persisted` 字段**）；
  随后 `editor_save_scene` → 读盘 `.tscn` **`[connection]` 块数 = 0`**；重开即消失。
  **试测的真实后果**：一台不会开始计时的车（脚本被迫自己 `Connect`）。
- 源码：`tools/editor_node_write.cpp:257` 的 `p_source->connect(p_signal, callable);` **未传 `CONNECT_PERSIST`**；
  `scene/resources/packed_scene.cpp:1238` **只序列化带该位的连接**，恢复侧 `:760` 正是用 `CONNECT_PERSIST`。
  `grep CONNECT_PERSIST modules/mcp_server/tools/**` = **0 命中**。
- **要求**：
  1. 连接**必须**带 `CONNECT_PERSIST`（按引擎语义），使连接随场景保存；
  2. 响应**必须**有 **`persisted`** 布尔（诚实：真的持久化才 true）；
  3. **并且**：`editor_disconnect_signal` 必须能断开**持久化**的连接（否则会留下断不掉的连接）；
  4. **同类排查**：`editor_analyze_signal_flow`（按 `CONNECT_PERSIST` 判定）与 `editor_list_signal_connections`
     在**修复前后**的结论变化要如实说明；并检查**是否还有其它「应为持久/应落盘」的写操作没有落盘**（逐条列）。
- **回归**：**端到端链** —— 连信号 → `editor_save_scene` → **从磁盘重开** → 用 `editor_list_signal_connections`
  （或 `project_read_scene_file_content` 看 `[connection]` 块）证明**连接仍在**，且运行时真的被触发。

## 3. **D-3（medium）**：`running_game_get_node_properties` 与同端点写工具的**结论相反**

- 实测：同节点同名字，`get` 回 `{"physics_material_override":null}`（`ok`），`set` 回 **`-32001 … not found`**。
  源码：`tools/running_game_observation.cpp:167-168` 的注释**明文**说「不存在的名字仍答 `null`，这是本工具已声明的行为」，
  `:194` 无条件 `serialize_variant(p_node->get(name))`；而写侧 `:1158` 有 `object_has_property` 检查。
  **契约 `description` 并未记载这个 null 语义**。
- **要求（二选一，说明理由）**：
  1. **与写侧一致**：不存在的名字 → **`-32001` + 建议**（推荐：一个端点内不得自相矛盾）；或
  2. **保留 null 语义但把它写进契约描述**（走 `DESCRIPTION_OVERRIDES` + 重生成 + 指纹），
     并**同时**保证编辑器侧同族工具口径一致（若选此路，编辑器侧也要有同样记载）。
  **不得**保持「写侧说没有、读侧说值是 null」而**什么也不做**。

## 4. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD（**从 cmd 启动**）。
- 五道门（**门①按受影响组各跑一次**）+ 门⑥ 三段式；若改契约描述 → **override + 重生成 + 指纹**，门① 逐字通过。
- **回归**：重跑 `probe037`、`mcp036`、`mcp035`、`mcp034`、`mcp033`、`mcp032`、`mcp030` 并逐条归因。
- **额外回归（关键）**：把 TASK-039 的**赛车工程**（`%TEMP%\mcp-racing-test\`，若仍在）作为**真实下游**复测：
  重开该工程 → 用工具连信号 → 保存 → 重开 → **连接仍在**；并说明「若当时有这个修复，试测里那台车会不会自己计时」。

## 5. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-040-racing-defect-fixes.md`；另加：
「三条缺陷的红→修全程」「**写工具属性检查缺口全表**」「持久化写操作排查表」
「D-3 的选择与理由」「对赛车工程的端到端回归」「结论锚点（D86）」。
**返回值：≤15 行总结 + 报告路径。**