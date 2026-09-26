# TASK-022 — 统一「槽位宽」写值闸门（不再逐类打补丁）+ D-5 + D-6 + 证据形态升级

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-022-unified-narrowing-gate.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 来源与教训（**必须读懂再动手**）

M4 第二次独立验收**仍判 `fail`**（`docs/reports/REPORT-AUDIT-M4b.md`），3 个新缺陷。
**最关键的教训**：「**槽位宽**」这一类已被漏了**三次** ——
①容器元素位宽（TASK-021 A-2）→ ②分量槽位宽（TASK-021 A-4）→ ③**标量 `real_t` 槽（本次 D-4）**。
**逐类打补丁的做法已被证明会继续漏**，因此本次**必须把它变成一条统一原则**，而不是再加一个分支。

## 1. D-4（high）：把「槽位宽」做成**统一的写值闸门**

- 现象：`rotation=1e300` / `3.5e38` / `"1e300"` → `code=0` 写 **`inf`**；`1e-300` / `1e-46` → `code=0` 写 **`0.0`**。
  **5 条写路径复现**：`editor_set_node_property`、`editor_set_node_property_batch`（3 节点全 inf）、
  `editor_add_nodes_batch`（新节点 inf）、`running_game_set_node_property`(9889)、
  `project_set_node_property_across_scenes`(**真的把 `rotation = inf` 落进 `.tscn` 并回 `Applied`**)。
- **要求（核心）**：实现**一处统一的预校验**，判定「**这个 Variant 能否无损地落进目标成员**」，
  覆盖**所有**收窄形态，而不是按类枚举：
  - `double → float`（`real_t`）：**溢出为 `inf`** 与**非零下溢为 `0`** 都要拒绝（`|x| > FLT_MAX`、`0 < |x| < FLT_MIN`）；
  - `int64 → int32/uint8/…`；`float64 ↔ float32` 容器元素；
  - 复合类型的**分量**与向量数组的**元素**；packed 容器的**元素**；
  - **并保留**已实现的其他闸门（`can_convert`、可解析性、有限性）作为**同一条链**的环节。
- **落点**：必须在**任何写入之前**（批量路径保持全成功/回滚）；**5 条写路径必须复用同一处**（给出调用点清单）。
- **自证**：写一份**路径清单**，说明「哪些 Variant→成员 的收窄形态被覆盖」以及「为什么这一处能覆盖全部写入路径」。

## 2. 证据形态**再次升级**（旧形态对 D-4 结构性假绿）

M4b 实测证明旧形态（sha 相同 + 读回≠请求值）**看不见 D-4**：未 save 时 sha 恒同、值真被改时无旧值可读、
读工具对 `inf` 返回 `null`。**新形态必须同时满足**：
1. **错误码** `-32602`；
2. **响应回显值必须有限**（`new_value` 等字段**不得**出现 `inf`/`nan`/`null` 来掩盖）；
3. **落盘文件不得含 `inf`/`nan`**：显式保存后用文件字节扫描断言
   （`.tscn`/`.tres`/`project.godot` 中不含 `inf`/`nan`/`1e99999` 之类）；
4. **另一个读工具**读到旧值未变（并说明为何该工具对本例有效——若它对 `inf` 返回 `null`，就**不能**用它单独作证）。
> 对**每一条** D-4 反例（`1e300`/`3.5e38`/`-3.5e38`/`"1e300"`/`1e-300`/`1e-46`/合法 `1e30`/`1e-30` 对照）
> 都要给出以上四条；**并覆盖 5 条写路径**。

## 3. D-5（medium）：`project_create_resource` 的 `properties_set` 未回读校验

- 现象：`Curve.min_value=5.0` 与 `1e300` 都返回 `code=0` + `properties_set:["min_value"]`，
  而文件里 `_limits` 仍是 `[0.99, 1.0, …]`（引擎 setter 在 `min_value > max_value` 时**静默忽略**）。
  同族的 `project_edit_resource` **反而会真回读**（`changed:{old,new}`）。
- **修法**：`project_create_resource` **复用 `project_edit_resource` 的回读形状**
  （`changed:{<prop>:{old,new}}`），使「报成功」**必须以回读为据**；
  若某属性被引擎静默忽略，必须**如实报告**（不被列为已设置，或明确标注 `ignored`）。
- 证据：`Curve.min_value=5.0` 与 `1e300` 两个反例 + 一个**真生效**的正例。

## 4. D-6（medium）：测试报告累加器**在任何可达端点恒空**

- 现象：`editor_get_test_report` 是 **editor-only**，而 `record_test_result` 的**三个调用点全在 `scope=game` 工具**里
  （跨端点调用被 `-32601` 拦住）→ 客户端永远只能看到 `total=0`，**契约宣称的能力不可达**。
- **决策者裁决（采用文件桥接，不改契约）**：**游戏进程把断言报告持久化到 `user://`**，
  由**编辑器侧的 `editor_get_test_report` 读该文件** —— 这正是迁移源当年的做法（文件 IPC），
  既让能力**真的可达**，又**不需要**改契约/映射/新增工具。
  要求：
  1. 游戏侧累加器每次更新后（或按需）写入 `user://`（如 `user://mcp_test_report.json`），**原子写**；
  2. `editor_get_test_report` 读该文件并返回**结构化报告**，且**标明来源**（`source`）与**文件路径/时间戳**；
  3. **不得谎报**：文件不存在/为空时返回**诚实**结果（`no_results:true` 或明确错误），不得伪造 `total`；
  4. 证据：**游戏进程内跑两个断言（一个过、一个失败）→ 编辑器侧读到 `total≥2`、`failed≥1` 与每条明细**；
     并给出「文件不存在时」的诚实返回。
- 顺带：`editor_get_test_report` 的 **accumulator 语义**要写清（它是**跨进程经文件**的，不是内存直读）。

## 5. 规范与工具

1. 把「**槽位宽必须覆盖标量成员**」以及「**统一收窄闸门**」写进 `docs/DESIGN-DETAIL.md`（新增 **GDR-22** 小节），
   并写明「**声明的确定性转换**不在该类」（`PLAYBOOK` §7.7 的既有口径）。
2. `modules/mcp_server/scripts/build_local.cmd` 增加 **`-Force`**（删除陈旧 `test_mcp_server`/`test_main` 对象后重建），
   并在注释里说明「改动 `tests/*.h` 后不加 `-Force` 可能跑旧用例产生**假绿**」。

## 6. 门

按 `PLAYBOOK-group-port.md` §3 五道门（第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 +
校验 `--version` == HEAD），外加 §1 的 5 条路径 × 反例矩阵、§2 的四条证据形态、
§3 的正反例、§4 的跨进程报告证据、§5 的文档与脚本改动。
**并重跑**：TASK-020/021 的三条判据（五种分量值、字符串值、批量事务）确认**未回退**。

## 7. 报告

按手册 §4，写到 `docs/reports/REPORT-022-unified-narrowing-gate.md`；另加：
「统一收窄闸门的覆盖清单与调用点」「5 条写路径 × 反例矩阵（四条证据形态）」
「D-5 回读形状前后对照」「D-6 跨进程报告的真实数字与诚实失败」「**同类面清零的范围声明**」。
**返回值：≤15 行总结 + 报告路径。**