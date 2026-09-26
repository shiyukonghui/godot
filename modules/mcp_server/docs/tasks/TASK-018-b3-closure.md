# TASK-018 — B3 收官（10 个工具）+ 静默错值修复 + 门脚本去硬编码

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-018-b3-closure.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 状态

已实现 **96/171**；B3 剩 **10** 个工具（6 组），B4 剩 7，B5 剩 58。

## 1. 第一部分：修一个**静默错值**缺陷（决策者裁决：必须修）

TASK-017 记录（并**正确地没有自行修改**）：`editor_set_node_property_batch`、`editor_add_nodes_batch`
（以及与它们共享同一强转路径的**既有** `editor_set_node_property`）对**布局不兼容**的值
（例如给 `position` 传 `1e20`）会**返回 `status: ok` 却静默写入 `Vector2(0,0)`**。

**决策者裁决：必须修** —— 这与 M2 的 D-1（未知属性返回成功形状）属**同一缺陷类**：
「**静默写入错误的值并报成功**」。本项目存在的首要理由就是消除这类谎报。
本项目已确立的口径（`PLAYBOOK` §6.2 / TASK-010）是：**越界/不兼容一律 `-32602`**。

要求：
1. 让**所有**写入路径（含既有的 `editor_set_node_property`）在值**不能如实落入目标属性类型**时返回
   **`-32602` + 可读消息**（说明目标类型与该值），**不得**写入 `(0,0)`/`0`/空值等替代品。
2. **批量路径**：这类失败属于**校验失败**，必须在**任何写入之前**被捕获（保持 TASK-017 的全成功/回滚语义）。
3. 补 doctest 与**线上证据**：`position: 1e20` → `-32602` 且**磁盘/场景读回证明未被改动**；
   同时确认**合法值仍正常写入**（回归护栏，含 `Vector2`/`Vector3`/`float`/`int`/`Color`/字符串各一例）。
4. 这是**对已验收工具的行为变更**：必须在报告里**显式列出受影响工具与被改变的行为**，
   并说明为何「改变已验收行为」在此是正确的（旧行为=静默错值）。

## 2. 第二部分：门脚本去硬编码

`scripts/accept_m1.ps1` 里的 `$ToolNames` 目前是**硬编码的工具名并集**，导致**每批都要手工追加**
（TASK-014/015/016/017 各改过一次，且已在报告里被标为 declared deviation）。
→ 改为**从 manifest 派生**：读取 `docs/tool-groups*.json` 中所有 `implemented=true` 组的工具并集
（必要时按 `tool-rename-map.json` 的 `scope` 逐端点过滤），**不得削弱任何断言**；
报告里给出「派生结果与上一版硬编码清单完全一致」的证明（逐名 diff 为空），并说明此后新增批次**无需**再改脚本。

## 3. 第三部分：移植 B3 最后 10 个工具（6 组，以 `docs/tool-groups-b3.json` 为准）

| 组 | 数量 | 工具 | 注意 |
|---|---|---|---|
| `editor_script_write` | 2 | `editor_execute_gdscript`、`editor_set_node_script` | 脚本执行**必须沿用 `running_game_execute_gdscript` 的先例**：真编译（非 `Expression`）、结构化返回 `{result, result_type}`、编译/参数错 `-32602`、无脚本语言 `-32000`；并**考虑超时/资源边界**（若可构造） |
| `project_script_write` | 2 | `project_create_script`、`project_edit_script` | **写文件** → 原子发布；失败不得破坏原文件 |
| `project_autoload_write` | 2 | `project_add_autoload`、`project_remove_autoload` | 改 `project.godot` → 原子发布 + **幂等性**证据（重复添加/移除的行为要明确） |
| `project_setting_write` | 1 | `project_set_setting` | 同上；注意值类型保真（`Vector2` 等）与**不存在设置**的处理 |
| `project_cross_scene_write` | 1 | `project_set_node_property_across_scenes` | **多场景事务**：跨多个 `.tscn` 写入，失败时**必须**明确语义（全成功/回滚/逐文件结果），并做**故意坏的中间文件**反例 |
| `project_resource_uid_read` | 2 | `project_convert_path_to_uid`、`project_convert_uid_to_path` | 只读；注意这两个名字**极易互混**（token 集合相同、仅次序相反）——报告里必须演示**按契约描述能否可靠二选一**，并给出「方向搞反会静默返回错映射」的对照证据 |

要求：全部经 `ToolBuilder` 注册；`channel`/`scope`/`mutating` 与映射一致；
`project_*` 只读项在**两端点**都可见（`scope=both`），`editor_*` 项**缺席于 9889**；
`docs/tool-groups-b3.json` 对应 6 组置 `implemented=true`；报告给出 **B3 = 40/40** 的机器校验输出。

## 4. 门

按 `PLAYBOOK-group-port.md` §3 五道门（**门①按 6 组各跑一次**；第 0 步先校验 `--version` == HEAD），
外加：§1 的静默错值前后对照与「未被改动」证明、§2 的派生等价证明、§3 的多场景事务反例与 UID 方向对照。

## 5. 报告

按手册 §4，写到 `docs/reports/REPORT-018-b3-closure.md`；另加：
「静默错值修复的影响面清单」「门脚本派生前后逐名 diff」「**B3 收官 40/40**」
「实施者自行决策的事项（若有）+ 待决策者批准项」。**返回值：≤15 行总结 + 报告路径。**