# TASK-047 — 收尾：3 个脚本的 9877 前置对齐 + 优雅退出 flush + **里程碑闭合清单（M0–M5 可复现）**

> 执行者须知：先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册），再读本文件。
> 报告写到 `docs/reports/REPORT-047-milestone-closure-inventory.md`；
> 返回给决策者的内容**只允许**是「≤15 行总结 + 报告路径」。

## 1. 三项（都不改模块行为、不改契约）

1. **对齐 3 个脚本的 9877 环境前置断言**：`scripts/mcp010_b2_observation_evidence.ps1`（4 处）、
   `mcp019_b4_evidence.ps1`（3 处）、`mcp027_object_shape_and_paths_evidence.ps1`（3 处）
   —— TASK-042 只对齐了 6 个 + `accept_m1.ps1`，这 3 个仍把「9877 pid 不变**且不为 -1**」当断言，
   在当前环境（**用户编辑器未运行**）**必然报红**，掩盖真回归。
   → 复用 `scripts/mcp_port_guard.ps1` 的**七分类**（含更严的 `user_editor_vanished_during_the_run`），
   **不得**放松「**我们**没占用 9877」这个真不变式；对齐后**复跑**这 3 个脚本并**逐条归因**（预期：只剩真实回归）。
2. **优雅退出 flush 验证**（TASK-AUDIT-CAPTURE 的 `unconfirmed` 之一）：
   追踪/捕获行在 `Engine::stop()` 时是否会丢弃「在飞条目」—— 构造一次**优雅退出**（不是 kill），
   退出后读 trace，证明**最后一条在飞行是否落盘**；结论**无论是否落盘**都要如实写（并说明退出路径上的代码依据）。
3. **里程碑闭合清单（本批的主要产出）**：产出一份**可复现**的清单 `docs/reports/MILESTONES-CLOSURE.md`，
   逐里程碑给出：**交付物路径**、**验收证据路径**（`REPORT-AUDIT-*` / 门⑤ / 构建基线）、
   以及**在【当前 HEAD】上重跑的最小命令与实际结果**：

| 里程碑 | 本批要重跑/核对的最小集合 |
|---|---|
| M0 工具链/非 mono 基线 | `build_local.cmd -Force`（tests=yes）+ `--version == HEAD` |
| M1 骨架+HTTP+JSON-RPC | `accept_m1.ps1` ×2（22/22，清单一致）+ `check_contract_subset.ps1 -Group <任一组>` |
| M2 B1+B2 | `check_tool_groups.py --batch B2`（B1 走无参数路径）+ 任一条 B2 证据脚本 |
| M3 mono 构建 + C# 工程 | **重建 mono 构建**（`scons ... module_mono_enabled=yes`）+ 一个 C# 工程起得来（可复用 `%TEMP%\mcp-racing-test` 或新建最小工程）|
| M4 B3+B4 | `check_tool_groups.py --batch B3` 与 `--batch B4` + 一条 B3/B4 证据脚本 |
| M5 B5 | `check_tool_groups.py --batch B5` + `--check-completeness`（171/171）|

   要求：**每条都给真实输出与退出码**；**任何一条跑不起来或红**，必须**逐条归因**（不得只报「全绿」）。
   **注意**：M3 的 mono 重建是**唯一允许的第二次构建**；**构建必须串行**（不得与其它 scons 并发），
   重建后如需要，**再次**用 `build_local.cmd -Force` 把非 mono 二进制恢复为当前 HEAD（并在报告里说明顺序）。

## 2. 门

- 第 0 步：`scripts/build_local.cmd -Force`（`tests=yes`）重建 + 校验 `--version` == HEAD（**从 cmd 启动**）。
- 五道门 + 门⑥ 三段式；回归：`mcp043/042/041` 门批次 + `mcp044/045/046` 证据脚本 + `mcp010/019/027` 对齐后复跑。

## 3. 报告

按手册 §4，写到 `docs/reports/REPORT-047-milestone-closure-inventory.md`；另加：
「3 脚本对齐前后对照（逐条）」「优雅退出 flush 的结论与代码依据」「**里程碑清单的实际命令与输出**」
「结论锚点（D86）」。**返回值：≤15 行总结 + 报告路径。**