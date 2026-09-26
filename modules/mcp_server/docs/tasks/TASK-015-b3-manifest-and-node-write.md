# TASK-015 — B3/B4/B5 分类清单 + B3 首组（节点写族，含 2 个 fix-first）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含；
> **注意 §3 新增的「门必须先绑定构建」「禁止并发 scons」「C# 事实」「BOM/import 校验」**），再读本文件。
> 报告写到 `docs/reports/REPORT-015-b3-manifest-and-node-write.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 状态与范围

已实现 **66** 个工具（B1 = 41、B2 = 25）。契约 171 条中还有 **2 个 `unregister`**（不实现）
→ **剩余待移植 103 个**，需要归入 **B3 / B4 / B5**。
本任务 = **①把剩下 103 个工具完整分类成三个 manifest**（像 B1/B2 那样机器可校验）
+ **②移植 B3 的首组（节点写族）**，其中包含 **2 个 `fix_implementation_first`**，必须**先红后修**。

## 1. 第一部分：B3/B4/B5 manifest（分类必须完备且可校验）

产出 `docs/tool-groups-b3.json`、`docs/tool-groups-b4.json`、`docs/tool-groups-b5.json`，
结构与 B1/B2 完全一致（`batch` / `total` / `groups[{name,channel,scope,mutating,implemented,tools}]`），并要求：

1. **完备性**：三个 manifest 的并集 **恰好等于**「契约 171 − 2 个 `unregister` − 已实现 66 = **103**」
   （自己写检查并贴出：`in_contract_and_not_implemented` 双向差集为空、103 恰好各一次、三 manifest 彼此无交集、与 B1/B2 无交集）。
2. **名字必须存在于契约**；`channel`/`verb`/`scope`/`mutating` 必须与 `docs/tool-rename-map.json` **逐条一致**
   （以映射为唯一事实源，不得自行发明）。
3. **分组依据**：`scope` + 通道 + 读写 + 依赖；每组 ≤10 个工具、组内可放进一个 `tools/<group>.{h,cpp}`、组间无共享文件。
4. **分类依据**（`docs/DESIGN-DETAIL.md` §10）：
   - **B3** = 节点/脚本/资源**写**操作（`add_node`/`delete_node`/`duplicate_node`/`rename_node`/`move_node`/`update_property`/
     `batch_set_property`/`set_node_groups`/`connect_signal`/`disconnect_signal`/`create_script`/`edit_script`/`attach_script`/
     `add_scene_instance`/`add_raycast`/`add_mesh_instance`/`add_gridmap`/`setup_*`/`set_project_setting`/`add_autoload`/`remove_autoload` …）
   - **B4** = 测试与断言（`assert_node_state`/`assert_screen_text`/`run_test_scenario`/`run_stress_test`/`get_test_report`/
     `compare_screenshots`/`watch_signals`/`monitor_properties` 的批量形态 …）
   - **B5** = 其余分类（animation / animation_tree / audio / theme / tilemap / particle / navigation / physics / scene_3d /
     shader / export / android / profiling …）
   若某工具难以归类，**在报告里写明判据**，不要硬塞。
5. 每组的 `implemented` 只有你本任务实际完成的那一组为 `true`。
6. `docs/scripts/check_tool_groups.py` 需以**最小改动**支持新 manifest（可加 `--batch B3|B4|B5`），
   **不得削弱既有断言**（B1/B2 的检查必须保持逐字节不变）。

## 2. 第二部分：移植 B3 首组 —— **编辑器节点写族**（建议 8–10 个工具）

从你产出的 B3 manifest 里挑「**编辑器节点写**」这一组实现（例如 `editor_add_node`、`editor_delete_node`、
`editor_duplicate_node`、`editor_rename_node`、`editor_reparent_node`（旧 `move_node`）、`editor_set_node_property`（旧 `update_property`）、
`editor_set_node_groups`、`editor_add_scene_instance`、`editor_add_raycast`、`editor_connect_signal`、
**`editor_disconnect_signal`**、**`editor_set_auto_dismiss_dialogs`** ——以你的 manifest 为准，**不要跨组硬塞**）。

**其中 2 个是 `fix_implementation_first`，必须按「先红后修」处理：**

1. **`editor_disconnect_signal`（旧 `disconnect_signal`，`node.rs:344-358`）**：迁移源**忽略 `target_path`**，
   固定用场景根作 `Callable`，因此**断开的可能不是你想断的那条连接**，却报成功。
   → **先写会失败的红测试**证明「传入 `target_path` 时断开的仍是场景根那条（或根本没断开目标）」，再修实现。
2. **`editor_set_auto_dismiss_dialogs`（旧 `set_auto_dismiss`，`editor.rs:613-625`）**：迁移源只写一个
   **无人读取的 static**（全仓仅 2 处引用）后返回成功 → **纯谎报**。
   → 红测试证明「调用后没有任何行为变化」；修法按 `PLAYBOOK` §6.6：
   **要么真的实现**（找到编辑器真正控制自动关闭弹窗的位置），**要么诚实地返回 `-32000 not_implemented` + 建议**，
   **禁止**「返回成功但什么都没发生」。选择依据与证据写进报告。

其他要求：
- 全部 `scope=editor`、`mutating=true`、走 `MCP_EDITOR_TOOLS_ENABLED`；**必须缺席于游戏端点 9889**，
  且在游戏进程调用必须 `-32601` 且不执行。
- **节点写族的行为基准**：TASK-014 已把 `running_game_set_node_property` 确立为「**先查属性表再写**」的形状；
  编辑器侧同类工具应照此办理（未知属性 → `-32001`，不得产出成功形状）。注意手册 §3 的 C# 事实②：
  **非 `[Export]` 的 `public` 字段按名可写但不在属性表里** —— 对这种情况要么显式允许、要么显式拒绝并在报告说明。
- **写操作安全性**：编辑器场景写属于**内存态**（不落盘）还是也落盘，按迁移源语义；若涉及落盘，走原子发布。
- 破坏性/写入操作只在 `%TEMP%` 的 **scratch 工程副本**上进行（**`.tscn` 不要写 BOM**）。

## 3. 门

按 `PLAYBOOK-group-port.md` §3 五道门（门①按本组跑；**第 0 步先校验 `--version` == `git rev-parse --short HEAD`，不一致先重建**），
外加：§1 的完备性校验输出、§2 的红→绿证据（两个 fix-first 各一组）、节点写族的「另一个工具独立读回」证据。

## 4. 报告

按手册 §4，写到 `docs/reports/REPORT-015-b3-manifest-and-node-write.md`；另加：
「103 个工具的 B3/B4/B5 分类判据与完备性证明」「两个 fix-first 的红→修全程与最终语义」
「节点写族的先查属性表形状与 C# 字段边界的处理」。**返回值：≤15 行总结 + 报告路径。**