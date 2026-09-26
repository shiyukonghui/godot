# TASK-030 — D1（活动编辑场景**静默丢失写入**，high）+ D5（零命中仍宣称已应用）

> 执行者须知：先完整阅读 `docs/tasks/PLAYBOOK-group-port.md`（自包含），再读本文件。
> 报告写到 `docs/reports/REPORT-030-live-open-scene-write.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 0. 来源（M4d 第四次独立验收，`REPORT-AUDIT-M4d.md`）

### D1（high）：`project_set_node_property_across_scenes` 对**活动编辑场景**报成功但**未写入**

**实测（验收方证据链）**：`force=true` → `code:0`、
`scenes_affected=[{"count":1,"mode":"live_open_scene","nodes":["."],"scene":"res://scenes/good.tscn"}, …]`、
`message="Applied: every closed scene was saved and the active open scene was edited in memory."`；
但**另一个工具** `editor_get_node_properties(path='.')` **仍读到旧值** `{"x":1.0,"y":2.0}`，
随后 `editor_save_scene` 落盘的**仍是旧值**；同一次调用里**关闭的** `side.tscn` 确实被写成 `Vector2(3,4)`。

**源码根因（验收方定位，请自己复核）**：`project_cross_scene_write.cpp`
`:309-317` 对**活动场景**也走 `CACHE_MODE_IGNORE` 加载并 `instantiate()` 出**游离副本**
（匹配/校验都作用在副本上）；`:451-455` 对 `live_open_scene` **跳过落盘**、只调 `_mark_active_scene_unsaved()`，
副本随后被丢弃；而 `:81-86` 的注释却声称「edits the live nodes」。

**这是本项目要消灭的那一类**：**报成功、什么都没发生**，而且**额外更危险**——
它把场景标记为「已修改」，调用方按报告继续 `editor_save_scene` 就会把**旧值**当成「已保存的新值」写下去
（**静默数据丢失**）。

**要求（二选一，必须明说选了哪个并给理由）**：
1. **真的写活节点**（推荐）：对活动编辑场景改**真的活节点**（编辑器持续同步的那份），
   保留 `mark_scene_as_unsaved`，并**读回验证**；
2. 或**诚实拒绝**：活动场景在 `force` 下**不可**由此工具写入 → 明确错误（`-32000` + `data.suggestion`，
   建议调用方改用 `editor_set_node_property`），**并且**消息里**不得**再出现「edited in memory / Applied」这类措辞。
**无论选哪种**：`scenes_affected[].mode` 必须让调用方**一眼看出**「这条到底写没写」；
**不得**出现「成功 + 未写入」的组合。

**必须新增回归**：一条**端到端链** —— 写活动场景 → **另一个工具读回新值** → `editor_save_scene` → **文件里含新值**。
还要覆盖：多场景（活动 + 关闭）混合时，**关闭的**那些仍然真落盘。

### D5（minor，同文件）：零命中仍宣称「已应用」

`path_filter="res://scenes/good.tscn"`（**文件**而不是目录）→ `total_scenes=0`、`scenes_affected=[]`，
但 `message` 仍是 `"Applied: every closed scene was saved and the active open scene was edited in memory."`、`code:0`。
→ `total_scenes==0` 时消息必须**显式说明没有场景匹配**，或返回 `-32001` + `data.suggestion`（二选一，说明理由）。

## 1. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD。
- 五道门 + **门⑥**；**重跑 TASK-028/TASK-029 的证据脚本**确认未回退。
- 证据：D1 的**红→绿**（红：活动场景写后另一工具仍读旧值 + save 后文件仍旧值；绿：三段链全通）、
  多场景混合（活动 + 关闭）分别的落盘结果、D5 的前后对照。

## 2. 报告

按手册 §4（含「引擎依据」列），写到 `docs/reports/REPORT-030-live-open-scene-write.md`；另加：
「选了哪个方案 + 理由」「根因复核（行号是否与验收方一致）」「`mode` 字段语义表（写没写一眼可判）」
「端到端链证据」「D5 前后对照」。**返回值：≤15 行总结 + 报告路径。**