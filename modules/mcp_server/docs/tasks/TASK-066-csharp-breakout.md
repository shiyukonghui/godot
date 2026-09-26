# TASK-066 — 补齐 **C# 打砖块工程**（第 2 轮遗留 F1）并在其上重跑整套活链 + ⑤⑥

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 依据：`docs/reports/BREAKOUT-FINDINGS.md`（第 2 轮 F1：C# 工程缺脚本/碰撞/分数 Label）、`BREAKOUT-FINDINGS-R3.md`（**B7 仍空白**）。
> 产物（**绝对路径**）：`F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\` 下
> `REPORT-066-csharp-breakout.md`（A 角色）与 `BREAKOUT-FINDINGS-R4.md`（B 角色）。
> 契约 **176**；线上 9888=153 / 9889=72。**绝对路径、`.ps1` 纯 ASCII、绝不碰 9877（先 netstat）**。

## A 角色（开发者）：把 C# 打砖块补成**完整可跑**

1. **只用 MCP 工具**（编辑器 9888，mono 构建的编辑器）；scratch 工程 `%TEMP%\mcp-breakout-cs\`（**C#**）。
2. **补齐第 2 轮缺的部分**：挡板/球/砖块的 **C# 脚本**（`_process` 驱动移动）、**碰撞与命中后砖块消失**、
   **计分**、**HUD 分数 Label**、**胜负/重开**（可最简）、**场景与 `[input]` 动作**。
3. **自己先跑通**（游戏端点 9889）：输入 → 挡板/球移动 → 命中砖块消失 → 分数变化；**每条给两步证据**
   （动作的前后状态，且**前后 sha 必须不同**）。
4. **§A 六条新能力判据各留一条实测**（尤其 **C# 真结论**：故意写坏 `.cs` → `invalid` + 编译器原文；修好 → `ok`；改过未构建 → `not_compiled`）。
5. **写 `PROGRESS.md` 心跳**（每里程碑一行）并在结束时写 `DEV-DONE.marker`；日志逐条记「想做什么/试过什么/回退是什么」。
6. **不得修改模块实现**；回退必须记录（这是缺失工具的证据源）。

## B 角色（验证者，A 完成后）：在 C# 工程上重跑**整套活链 + ⑤⑥ + 前 8 条空白**

**必须**：①`scripts/mcp_watch_run.ps1` 保证覆盖（**`stop_reason` 必须是 `marker`**）；
②`scripts/mcp_evidence_guard.ps1`（唯一命名 + 快照 before→between→after + 断言两 sha 不同）；
③**不得改模块实现**；④绝对路径。

1. **游戏侧活链（在 C# 工程上）**：输入 → 挡板/球位置**逐帧单调变化**（给采样）；
   砖块命中后**节点集合真的减少**；**分数真的变化**（读回 Label/属性 + 进程内断言）。
2. **⑤ `scope:user`**：默认 vs `user` vs `internal` 各 ≥3 次；**必须再验证 `user ∪ internal = default` 且 `∩ = ∅`**。
3. **⑥ `changed:false`**：**窗口化**进程下构造「报成功但画面没变」→ `changed:false`；真实变化 → `changed:true`；
   **日志 / 工具 / 独立复算三路一致**（C# 工程上重做，这是第 2 轮 F1 的直接收口）。
4. **前 8 条空白尽量收**（能构造就构造；不能就**明确声明为什么**）：
   B1 游戏端窗口化捕获族 / B2 `on_error` 与 `diff_image` / B3 `scale 1/4` / B4 `scope×node_path` /
   B5 连接来源区分 / B6 diff 工具拒绝路径 / **B7（本轮主目标）** / B8 多进程 scope 稳定性。
5. **报告须含**：逐条结论 + 证据路径与 sha256 + `stop_reason` + **仍未构造项及其原因** + 对 A 的**纠错**（若有）。

## 门与纪律

**构建严格串行**（如需重建 mono/plain 则从 cmd 启动、不抑制输出）；**绝不占用/杀/重启 9877**；端口 9888/9889；
禁止 push；**D86** 标提交锚点；收尾核实 `git status --short` 与契约 sha 未变。