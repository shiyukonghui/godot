# TASK-074 — **试测第 5 轮**：2D 平台跳跃（多场景/动画/UI/音频/混语言/大批量）

> 方案由决策者给定（见 §0）。本文件是**三角色共用**任务书：**只读你那一节** + §0 总则。
> 产物一律写到**绝对路径** `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\`；
> 原始追踪与关键截图**当场复制进** `...\docs\reports\evidence\task074\`。

## §0 总则与方案

1. **手册**：`docs/tasks/PLAYBOOK-group-port.md`。**端口**：9877 属用户（**绝不碰**）；只用 **9888 编辑器** / **9889 游戏**。
2. **scratch 工程**：`%TEMP%\mcp-platformer\`（**C# 工程**，用 mono 编辑器）；**不得修改 `modules/mcp_server/**` 与 `modules/mono/**` 的实现**（只记录发现）。
3. **取证（强制）**：编辑器与游戏都开 `--mcp-trace` + `--mcp-capture=every_call`（`viewport=2d`, `scale=2`，窗口化——**headless 下捕获恒为 `unavailable`**）；
   用 `scripts/mcp_watch_run.ps1`（**`stop_reason` 必须是 `marker`**）；用 `scripts/mcp_evidence_guard.ps1`（唯一命名 + 快照 before→between→after + 断言两 sha 不同）；
   `.ps1` 纯 ASCII；结论按 D86 标锚点；scratch 追踪**当场复制进仓库**。
4. **预算**：开发者 **50 分钟**；观察者/watcher **80 分钟**（`-TimeoutSec 4800`，`-StaleSec 300`）。
5. **游戏（本轮目标）**：**2D 平台跳跃**——玩家可跑/跳、收集金币、碰到敌人扣命、到达终点过关；**headless 与窗口化都能起**。
6. **必须压测的面（每条都要在日志里留下实测响应）**：
   - ①**多场景 + 实例化**：Main/Player/Enemy 各自场景，Enemy 场景**实例化 ≥3 次**，改主场景里的实例属性；
   - ②**TileMapLayer 地形**：建层、设 tile 或至少设其属性（能力缺失就如实记录）；
   - ③**AnimationPlayer + 关键帧**：建 ≥2 个动画（如 run/jump），**真的插关键帧**并在游戏里播放后被读到；
   - ④**Theme + Control UI**：HUD（分数/命数）+ 暂停菜单；给 ≥1 个 Control 设 theme override；
   - ⑤**音频**：≥1 个 `AudioStreamPlayer`（无音频资源就记录缺失/替代）；
   - ⑥**粒子或 CanvasLayer 视差**（至少其一）；
   - ⑦**C# 与 GDScript 混用**：至少 1 个脚本用 GDScript、至少 1 个用 C#，**两种都要被构建/读到**；
   - ⑧**存读档**：用 `project_write_text_file` 写一份 JSON 存档，再用工具**读回并校验 sha**；
   - ⑨**大批量**：一次调用建 **≥100 个节点**（硬币阵列），并**一次调用给其中 ≥8 个写不同值**（`editor_set_node_property_updates`）；
   - ⑩**用户信号连接**：用 `editor_connect_signal` 建 ≥3 条**用户**连接，再用 `editor_list_signal_connections{scope:"user"}` 验证只看到它们；
   - ⑪**运行期**：游戏端点注入输入 → **另一工具**读回位置/分数/命数的**多帧变化**（非瞬移）。
7. **诚实**：摩擦与回退**必须记**；不可构造项**显式声明为什么**；**禁止**为了让判据变绿而改判据表述。

## §A 开发者（用工具真的做出来）

**产出**：`...\reports\PLATFORMER-DEV-LOG.md` + 真能跑的工程。
逐条记 `时间/工具名/参数要点/结果(ok 或错误码)/学到什么`；**回退必须记录**（想做什么/试过哪些工具/为什么不行/回退做了什么）；
**摩擦如实记**（几次才成功/错误消息是否自纠/是否必须先探路）；每里程碑往 `%TEMP%\mcp-platformer\PROGRESS.md` 追加一行；
完成写 `DEV-DONE.marker`。返回：**日志路径 + 工程路径 + 工具调用次数 + 回退次数 + §0.6 十一条各自结论（≤6 行）**。

## §B 观察者（与 §A 并行、只读、不阻塞）

**产出**：`...\reports\PLATFORMER-OBSERVATIONS.md`。
**先跑一次阻塞调用**：`scripts/mcp_watch_run.ps1 -Marker %TEMP%\mcp-platformer\DEV-DONE.marker -TracePath <各 trace> -TimeoutSec 4800 -StaleSec 300 -IntervalSec 30 -OutDir %TEMP%\mcp-platformer\watch`，**等它返回**再分析；**禁止**自行决定收工。
给出：≥3 条「多次调用才摸清用法」（附序列与错误码）、≥2 条缺失工具线索、≥2 条可合并候选、≥2 条异常/矛盾；
**没有就如实说没有**（并说明查了哪些信号）。**必须**报告 `stop_reason`/`polls`/`last_seq`/`trace_lines`。
返回：**观察文件路径 + 四类计数 + stop_reason（≤6 行）**。

## §C 汇总者（最后跑）

**产出**：`...\reports\PLATFORMER-FINDINGS.md`。**必须自己回追踪原文复算**（行号 + 响应 sha256），标注实测/推断；对 A/B 的错**明确指出**。
四张表（异常/缺失工具/可合并/可优化）+ **疑似缺陷**（最小复现 + 期望/实际 + sha256 + 严重度）+ **专答 §0.6 十一条**（通过/不通过/不可构造 + 证据路径与 sha256）。
返回：**发现文件路径 + 四类计数 + 十一条结论 + 最该先做的 2 条 + stop_reason（≤8 行）**。