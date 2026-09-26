# TASK-051 — B 档（改 `inputSchema`、条目数不变）：C-3 / O-9 / O-4 / O-5 / M-3

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件；**每条都已被独立确认**
> （`docs/reports/REPORT-AUDIT-RACING-BACKLOG.md`）。报告 `docs/reports/REPORT-051-b-tier-schemas.md`。
> 返回决策者的内容**只允许**是「≤10 行总结 + 报告路径」。

## 0. 契约机制（本批统一）

**条目数不变、只改 `inputSchema`** → 一律走 **`SCHEMA_OVERRIDES`（`mode=replace`，理由里**逐字引用**被替换成员）
+ `GENERATOR_VERSION` 递增 + **重生成契约 + 更新全部指纹**（**不得手改契约文件**）；门① 逐字通过；
并给**结构化 diff** 证明只动了这几个工具的 schema + `_meta`。**新参数的含义/默认值必须在描述里说清**。

## 1. 五项（每条先按 D86 **复测**再改）

1. **C-3（最高价值）** `editor_add_nodes_batch` 支持**同批父子**：
   现状 `editor_node_batch_write.cpp:251-258` 在**构造之前**解析父路径，于是 `nodes[1].parent="P1"`（P1 由同批
   `nodes[0]` 创建）报 `-32001 nodes[1] parent 'P1' not found`，**全批回滚**。
   → 新增 **`resolve_within_batch`**（**布尔，默认保持现语义**）：为真时父路径可引用**本批先建**的节点；
   冲突/循环/重复名要**明确拒绝**（`-32602`/`-32001` + 建议），**不得**产生重复或悬挂节点；
   **失败仍全批回滚**（保持既有语义）。给「同批父子成功」与「引用不存在的父仍拒绝」两条线上证据。
2. **O-9** `editor_list_signal_connections` 加 **`scope`**：
   实测 5 节点小场景就返回 **60/60 条**、**12 659 B**，且全是**编辑器内部**方法
   （`ScriptEditor::*` / `SceneTreeEditor::*` / `Viewport::*`）——因为 `source` 是**场景节点路径**，
   **按 source 过滤无效**，必须能按 **`method`/`target`** 缩小。
   → 设计并实现 `scope`（例如 `all|user|internal`，或 `method_prefix`/`exclude_editor_internal` 之类；
   **你定名并说明为何更顺手**，含默认值 = **保持现语义**）；**保留** `signal_name` 的精确过滤；
   给「同一场景在默认/收窄下返回条数与字节数」的前后对照。
3. **O-4** 补 `editor_simulate_input_sequence` 的 `events.items`（现在 schema 只写 `array`，
   工具不知道元素形状；实测报错走的是 `events[0].type` 的路径定位）→ 补全 `items` 结构。
4. **O-5** 补 `steps[].pressed` / `steps[].strength`（同理的 schema 缺项）。
5. **M-3** `editor_play_scene` 的 **headless / extra_args**（改 schema，条目数不变）：
   让工具能**以 headless 或带额外命令行参数**启动被播放的场景（例如注入 `--headless`、`--mcp-port`）。
   **必须**：默认行为**不变**；与既有 E-10 端口注入**兼容不冲突**（若重复注入要**明确去重**并说明）；
   给「headless 启动成功 + 游戏端点可用 + 端口注入只有一次」的线上证据。

## 2. 不做（决策者裁决）

**O-2（`editor_add_resource_to_node_property` 的 `old_value`/`new_value`）本批不做**：
TASK-040 已裁定——`editor` 侧资源写是**另一种形状**，加它会造出**第二个序列化器**，违反 GDR-25 单一形状规则
（见 `DECISIONS.md` D95(c)）。若将来要做，必须先统一形状。

## 3. 门与纪律

第 0 步 `scripts/build_local.cmd -Force`（tests=yes，**从 cmd 启动**）+ `--version == HEAD`；五道门 + 门⑥ 三段式
（新收窄点逐条列，§22.3b 规则 4）；回归 `mcp041/042/043` + `mcp010/019/027` + `mcp044/045/046` + TASK-050 的证据脚本，
**逐条归因**（受影响就改调用点，**不得**放松断言）；
**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；构建串行、不抑制输出；`.ps1` 纯 ASCII；结论按 D86 标锚点。