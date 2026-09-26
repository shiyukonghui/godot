# TASK-065 — 补 mono 锚点缺口 + **缺口专项第 3 轮**（⑤ `scope:user` / ⑥ 窗口化 `changed:false` / 游戏侧活链）

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 报告：A 部分 `REPORT-065A-mono-anchor-rerun.md`；B 部分 `BREAKOUT-FINDINGS-R3.md`（**绝对路径**：
> `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\...`）。
> 返回决策者：**≤6 行总结 + 报告路径**。契约 **176**（171 移植 + 5 新增）；线上 9888=153 / 9889=72。

## A 部分（先做）：补 TASK-064 的覆盖缺口

1. **串行**重建 mono（`scripts/mcp057_build_mono.cmd` 或等价 `scons … module_mono_enabled=yes tests=yes`），
   校验 `--version == HEAD`；随后如需恢复 plain（`build_local.cmd -Force`）并复验。
2. **复跑 `mcp052`/`mcp053`/`mcp054`** 到 exit 0，给**修复前后对照**（这三个脚本此前因 mono 锚点旧而红）。
3. 若仍有红 → **逐条归因**（不得只报「全绿」）。

## B 部分：缺口专项第 3 轮（三条必须**真正构造出来**）

**必须**：①用 `scripts/mcp_watch_run.ps1` 保证观察覆盖（**`stop_reason` 必须是 `marker`**）；
②用 `scripts/mcp_evidence_guard.ps1`（唯一命名 + 快照 before→between→after + 断言两 sha 不同）；
③**所有产物绝对路径**；④**绝不改模块实现**（只记录）；⑤绝不碰 9877。

1. **⑤ `scope` 收窄（第 2 轮「未构造」）**：
   在编辑器端点**真实调用** `editor_list_signal_connections`：
   ①默认（`scope` 省略）与 `scope:"user"` 与 `scope:"internal"` 三种各 ≥3 次；
   ②判据：**`scope:"user"` 的返回必须只含用户连接**（对比默认结果，给出条数/字节数与**集合差**），
   并验证 `signal_name` 与 `scope` **组合**时行为正确；③给证据（请求/响应 sha256 + 计数）。

2. **⑥ 捕获 `changed:false`（第 2 轮「未构造」）**：
   **必须用窗口化进程**（`--mcp-capture=every_call`，`viewport=2d`，`scale=2`）—— headless 下永远是 `unavailable`，**不得顶替**。
   ①构造一次「**报成功但画面没变**」（同参同值重放）→ 必须得到 **`changed:false`**；
   ②构造一次**真实变化** → `changed:true` + `changed_pixel_ratio>0`；
   ③**自己用同一对落盘文件**（`editor_analyze_screenshot_diff`）复核日志里的数字，**三路一致**（日志 / 工具 / 你的独立复算）。

3. **游戏侧活链（第 2 轮仍空白）**：在**游戏端点 9889** 上：
   ①注入输入 → **用另一个工具**读回**位置真的变化**（多帧、非瞬移，给采样）；
   ②砖块被击中后**真的消失/减少**（读回节点集合或计数）；
   ③计分**真的变化**（读回属性/标签文本）；
   ④若某条**不可构造**，给出**为什么**（端口/能力/工具缺失）并明确声明。

## 门与纪律

A 部分完成后跑五道门 + 门⑥ 三段式 + `--check-completeness/--added/--generator-version`；
B 部分**不改代码**（只记录），但**必须**在收尾核实 `git status --short` 与契约 sha 未变；
**构建严格串行**、从 cmd 启动、不抑制输出；**绝不占用/杀/重启 9877**；端口 9888/9889；禁止 push；
`.ps1` 纯 ASCII；**D86**：结论标提交锚点。