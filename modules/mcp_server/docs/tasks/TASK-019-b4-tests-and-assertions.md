# TASK-019 — M4 收官：B4 全批次（7 个工具）+ P-1 死代码清理

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（通用规范，自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-019-b4-tests-and-assertions.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 状态

已实现 **106/171**（B1 41 + B2 25 + B3 40）。本任务 = **B4 全部 7 个工具**（3 组，以 `docs/tool-groups-b4.json` 为准）
+ 一处死代码清理。**完成后 M4 = B3+B4 收官**（B4 是「游戏可玩性自动判定」的工具族，M2 的 E3 解锁在此完整）。

## 1. B4 的 7 个工具（**以 manifest 为准**）

预计包含：`running_game_assert_node_state`、`running_game_assert_screen_text`、`running_game_run_test_scenario`、
`running_game_run_stress_test`、`editor_get_test_report`（**`fix_implementation_first`**）、`compare_screenshots`（或 `running_game_compare_screenshots`）、
`running_game_watch_signals`（或 `editor_*`）——**以 `docs/tool-groups-b4.json` 的实际成员为准**，报告里列清单。

要求：
1. **`editor_get_test_report` 必须先红后修**：迁移源**恒返回固定文案**（`test.rs:561`，写死的提示串，**未收集任何结果**）。
   红测试要证明「调用后拿到的不是真实测试结果」；修法：**真的收集**（例如从 B4 断言族的执行结果里累积）
   或**诚实地返回 `-32000 not_implemented` + 建议**——按 `PLAYBOOK` §6.6，**禁止假成功**。
   这是 D45 的 7 个 fix-first 中的**第 4 个**（前三个：`editor_remove_output_log`、`editor_disconnect_signal`、
   `editor_set_auto_dismiss_dialogs`）。
2. **断言类**（`assert_node_state`/`assert_screen_text`）：必须给**通过**与**失败**两类真实证据；
   失败必须是**结构化的失败**（例如 `{passed:false, expected, actual, reason}`）而不是模糊错误；
   需要跨帧的（截图对比、等待条件）**必须走 GDR-20 延迟通道**。
3. **`run_test_scenario` / `run_stress_test`**：这两个是**E3 的自动化判定载体**，要求：
   - 给出一条**从游戏端点 9889 发起**的完整场景：启动游戏 → 注入输入/等待 → 断言节点状态与屏幕文本 →
     返回**结构化结论**（步骤、每步结果、总体 pass/fail、耗时）；
   - 报告中给出**至少一个「故意失败」的场景**（例如断言一个不可能的条件），证明它**真的会报 fail**，
     而不是永远报 pass；
   - 复用 `build_execute_gdscript_source` / `coerce_to_property_type` 的 `can_convert` 门 / 两阶段校验等既有设施。
4. **`compare_screenshots` / `watch_signals`**（若在 B4 内）：跨帧能力走延迟通道；
   headless 下若能力不足（无纹理存储）必须**先判能力后诚实拒绝**（GDR-20 §10），成功证据在**窗口化进程**采集。
5. 全部经 `ToolBuilder` 注册，契约逐字，`scope` 与映射一致（`running_game_*` 必须**缺席于 9888**、
   在 9888 调用 `-32601`；`editor_*` 反之）。
6. `docs/tool-groups-b4.json` 三组置 `implemented=true`；报告给出 **B3+B4 = 47/47（M4）** 的机器校验输出。

## 2. P-1 清理（决策者裁决：**不修引擎核心，删死代码**）

TASK-018 报告：本 fork 的 `Variant::construct_from_string` 是**空壳**，因此 `"Vector2(…)"` 字符串语法**从未生效**
（旧实现把它**静默写成零向量**，现在已是 `-32602`）。

**裁决：不要修改引擎核心**（`Variant::construct_from_string` 在我们的改动范围之外，且会让 fork 与上游分叉）。
→ 删除 `property_value_from_json` 里**已死的字符串语法分支及其注释**（避免后续批次误以为它可用），
并在该函数旁写一行注释说明「字符串→Vector/Color 的语法在此 fork 不可用，传结构化对象」。
补一条 doctest 断言「`"Vector2(1,2)"` 这类字符串一律 `-32602`」。

## 3. 门

按 `PLAYBOOK-group-port.md` §3 五道门（**门①按 B4 三组各跑一次**；第 0 步先校验 `--version` == HEAD），
外加：§1.1 的红→修证据、§1.2 的断言通过与失败两类证据、§1.3 的**故意失败场景**、
§1.4 的能力判定（若适用）、§2 的死代码清理对照。
**并确认**：本批**不需要**修改 `accept_m1.ps1`（它已从 manifest 派生）——如果确实需要改，说明派生逻辑有缺口，报缺陷。

## 4. 报告

按手册 §4，写到 `docs/reports/REPORT-019-b4-tests-and-assertions.md`；另加：
「`editor_get_test_report` 的红→修全程与最终语义」「场景运行器的结构化结论样例（含一个故意失败的场景）」
「B4 = 7/7 与 **M4 = 47/47** 的机器校验」「实现者自行决策事项（若有）」。
**返回值：≤15 行总结 + 报告路径。**