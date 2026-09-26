# TASK-017 — B3 续批之二：节点批量写 / 布局 / 7 个 setup 族（共 10 个工具）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含；**注意开头关于「决策日志在 hof-rs、fork 内不得新建竞争性文档」的说明**），
> 再读本文件。报告写到 `docs/reports/REPORT-017-b3-batch-layout-setup.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 状态

已实现 **86/171**；B3 剩余 20 个工具 / 9 组。本任务取 **3 组共 10 个工具**。

## 1. 要移植的组（**以 `docs/tool-groups-b3.json` 为准**）

| 组 | 数量 | 工具 |
|---|---|---|
| `editor_node_batch_write` | 2 | `editor_add_nodes_batch`、`editor_set_node_property_batch` |
| `editor_control_layout_write` | 1 | `editor_set_anchor_preset` |
| `editor_node_setup` | 7 | `editor_setup_camera_3d`、`editor_setup_collision_shape`、`editor_setup_world_environment`、`editor_setup_lighting`、`editor_setup_navigation_agent`、`editor_setup_navigation_region`、`editor_setup_physics_body` |

## 2. 特别注意

1. **批量写必须防半成品**：`editor_add_nodes_batch` / `editor_set_node_property_batch` 在多元素输入下，
   若第 k 个元素失败，**必须明确事务语义**（全成功 / 部分成功需报**逐元素结果** / 回滚），
   并且在报告里写清选择与理由；**禁止**「报成功但只做了一半」。用**故意坏的中间元素**做反例证据。
2. `editor_set_anchor_preset`：`Control` 锚点预设；注意非法预设名 → `-32602`，非 `Control` 节点 → 明确错误。
3. **setup 族**（`editor_setup_*`）：迁移源里这批工具**是本轮审计点名的「可疑」项之一**
   （曾出现在「30 条语义可写」清单里），要求：
   - 逐个写出**可观察契约**（参数、创建的节点/资源、返回形状）；
   - 每个工具的证据必须包含**用读族独立读回**（例如 setup_camera_3d 后用 `editor_get_node_properties`
     读到 `Camera3D` 及其属性；setup_collision_shape 后读到 `CollisionShape2D/3D` 与 shape 资源）；
   - **若迁移源某工具名与实际行为不符**（例如参数被忽略、创建的形状不对），按 `PLAYBOOK` §6.6 处理并**显式记录**。
4. 全部 `scope=editor`、`mutating=true`：**必须缺席于游戏端点 9889**，游戏进程调用 `-32601` 不执行。
5. 复用已上提的共享助手（`MCPTools::find_node`、`edited_scene_root`、`write_node_property`）——**不得**再复制本地副本；
   若确需新助手，上提到 `tools/tool_helpers.*` 并给等价证明。
6. `docs/tool-groups-b3.json` 里这三组的 `implemented` 置 `true`。

## 3. 顺带修一个文案缺陷（TASK-016 验收发现，minor）

`MCPToolError::not_found()` 在"被列举规则隐藏但被点名"的属性上会**重复追加后缀**，
出现形如 `... is not readable by name not found` 的消息（行为正确、仅文案）。
→ 修掉重复追加，并补一条 doctest 断言消息形态；报告里给出前后对照。

## 4. 门

按 `PLAYBOOK-group-port.md` §3 五道门（**门①按三组各跑一次**；第 0 步先校验 `--version` == HEAD，不一致先重建），
外加 §2 的批量事务反例、setup 族的读回证据、scope 缺席证据。

## 5. 报告

按手册 §4，写到 `docs/reports/REPORT-017-b3-batch-layout-setup.md`；另加：
「批量事务语义与中间失败反例」「7 个 setup 族的读回证据表」「文案缺陷前后对照」
「本批后已实现总数与剩余计数」。**返回值：≤15 行总结 + 报告路径。**