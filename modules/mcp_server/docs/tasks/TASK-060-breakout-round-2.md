# TASK-060 — **游戏测试循环第 2 轮**：打砖块（Breakout，C#）+ 新能力专项压测

> 本文件是**四角色共用**的试测任务书。每个子代理**只读自己那一节** + §0 总则。
> 产物一律写到 `docs/reports/`；**原始追踪与截图当场复制进仓库**（`docs/reports/evidence/task060/`）——上一轮的教训（N-6）。
> 你是哪个角色，由派发你的提示指定。**报告返回值 ≤8 行**（细节全写进文件）。

## §0 总则

1. **手册**：`docs/tasks/PLAYBOOK-group-port.md`（必读）。
2. **端口**：用户 Godot 在 **9877**（PID 会变）—— **绝不占用/杀/重启**；只用 **9888（编辑器）/ 9889（游戏）**。
3. **不得修改模块实现**（`modules/mcp_server/**`、`modules/mono/**` 的源码）：四角色**只记录发现**。
4. **scratch 工程**：`%TEMP%\mcp-breakout\`（**C# 工程**，用 **mono 构建**的编辑器 `bin\godot.windows.editor.x86_64.mono.console.exe`）。
5. **取证**：编辑器与游戏都开 `--mcp-trace=<path>` 与 `--mcp-capture=every_call`（`viewport=2d`，`scale=2`）；
   分析用 `scripts/analyze_mcp_trace.py`。**追踪与关键截图要当场复制进 `docs/reports/evidence/task060/`**。
6. **诚实**：结论必须带证据（调用序列/响应 sha256/耗时/错误码/文件 sha256）；区分**实测**与**推断**；不可构造项**显式声明**。
   **D86**：引用别处结论须标提交锚点并复测。
7. **`.ps1` 一律纯 ASCII**。
8. **预算与停止条件（TASK-061 修订，强制；锚点：`REPORT-061-observer-watcher.md`，基线 HEAD `0a9fc1d466`）**：
   **开发者 45 分钟**（硬停止 = 2700 秒）；**观察者/watcher 75 分钟**（`-TimeoutSec 4500`，**严格大于**开发者）。
   **取值依据（观察者 > 开发者）**：观察者必须比开发者**活得久**，否则「开发者还没完、观察者已退」在构造上就可能发生
   ——这正是第 2 轮的缺陷。4500 − 2700 = **1800 秒余量**，用于：①引擎启动/导入/首次 C# 构建的**前段开销**
   （第 1 轮实测单次 `editor_play_scene` 与工程导入可达 100 秒级）；②开发者可能**晚于**约定时刻开工；
   ③marker 落盘与观察者被唤醒之间的间隔（`-IntervalSec` 默认 30，watcher 实际最迟 `4500 + IntervalSec` 返回）。
   观测者**不得自行决定结束**：**必须先用一次阻塞调用**跑
   `scripts/mcp_watch_run.ps1 -Marker %TEMP%\mcp-breakout\DEV-DONE.marker -TracePath <各 trace> -TracePath %TEMP%\mcp-breakout\PROGRESS.md -TimeoutSec 4500 -StaleSec 300 -OutDir %TEMP%\mcp-breakout\watch`
   （**完整命令见 §C**），**等它返回**后再分析；**禁止**自己写 sleep 轮询循环决定何时收工，**禁止**在 watcher 返回前收尾。
   **产物与返回值必须**给出**机器可读的停止理由**：`stop_reason`（`marker|timeout|stale`）、`polls`、`last_seq`、
   `trace_lines`、watcher 日志路径；**若 `stop_reason != marker`，必须显式声明「观察在开发结束前停止」**并说明原因。
   > `stale` 判据的两个信号：①追踪文件**新增行数**；②开发者心跳 `PROGRESS.md` 的**新增行数**。
   > `stale` **只有在先观测到活动之后**才可成立（`mcp_watch_run.ps1` 的 `stale_ok`）；未开工不算「卡死」，
   > 未开工只由 `timeout` 收口。`-StaleSec 300` 的依据：第 1 轮 400 条真实调用记录里**同一 run 内相邻调用的
   > 最大间隔 = 92.2 秒**（`docs/reports/evidence/racing/CALL-LOG.jsonl`，run 内 seq 相邻），取 ~3 倍余量。
9. **开发者心跳（强制）**：开发者**每个里程碑**往 `%TEMP%\mcp-breakout\PROGRESS.md` **追加**一行
   （时间 + 已完成 + 下一步）—— 这是 `stale` 判据的第二个信号（追踪之外）。**必须追加，不得重写整个文件**
   （重写会让「新增行数」这个信号失真）。

## §A 组织者（先跑）

**产出**：`docs/reports/BREAKOUT-TEST-PLAN.md`（**方案** + **观察规则**）。

- **游戏**：**打砖块**（挡板 + 球 + 砖块阵列 + 计分 + 失败/胜利），**C# 实现**，headless 与窗口化两种模式。
- **必须点名压测这些新能力**（每条都写进方案与验收判据）：
  ①**注释保全**：先手写带注释的 `project.godot`，再用 `project_set_setting`/`editor_add_input_action` 改设置 → 判据=**注释仍在**；
  ②**C# 真结论**：故意写一个语法错误的 `.cs` → `project_validate_scripts` 必须给 **`invalid` + 编译器原文**；
  再修好 → `ok`；改过但未构建 → **`not_compiled`**（与「编译失败」区分）；
  ③**批量父子**：`editor_add_nodes_batch{resolve_within_batch:true}` 一次建出「父 + 子」；
  ④**批量挂脚本**：`editor_set_node_script_batch` 给多个砖块一次挂脚本（含 `keep_existing` 的跳过语义）；
  ⑤**`scope` 收窄**：`editor_list_signal_connections{scope:"user"}` 的返回必须**干净**（不再淹没在编辑器内部连接里）；
  ⑥**捕获的诚实性**：用 `--mcp-capture=every_call` 的 `changed:false` 判定「**报成功但画面没变**」（至少造一次）。
- **不要**动手做游戏、**不要**等开发者。写完方案返回**方案路径 + ≤6 行摘要**。

## §B 开发者（用 MCP 工具真的做出来）

**产出**：`docs/reports/BREAKOUT-DEV-LOG.md` + 一个**真的能跑**的 C# 打砖块工程。

- 按 §A 方案实现；**主手段是 MCP 工具**；**逐条记录**：`时间 / 工具名 / 参数要点 / 结果(ok 或错误码) / 学到什么`。
- **回退必须记录**（想做什么 / 试过哪些工具 / 为什么不行 / 回退做了什么）—— 这是**缺失工具**的证据源。
- **摩擦如实记**（同一工具调几次才成功 / 错误消息够不够自纠 / 是否必须先 A 探路再 B）。
- **自己先跑通验收**：①工程能起；②在 **9889** 注入输入让挡板动、球动，并**用另一个工具**读回位置变化；
  ③砖块被击中后**真的消失/计分真的变**；④**§A 的六条新能力判据逐条有实测响应**（含 sha256）。
- **心跳（强制，§0 第 9 条）**：**每个里程碑**往 `%TEMP%\mcp-breakout\PROGRESS.md`**追加**一行
  （时间 + 已完成 + 下一步）。它是观察者 `stale` 判据的第二个信号：只有追踪在动、心跳不动，与两者都不动，
  是两种不同的结论。
- 做完写 `%TEMP%\mcp-breakout\DEV-DONE.marker`（**这是唯一的完成信号**，观察者与 watcher 的 `stop_reason=marker`
  都以它为准）。返回**日志路径 + ≤6 行摘要**。

## §C 观察者（与 §B **并行**、**只读**、**不打断**开发者）

**产出**：`docs/reports/BREAKOUT-OBSERVATIONS.md`（边观察边追加）。

- **只读**：绝不改 scratch 工程、绝不打断开发者进程、绝不占用它的端口；可用**第二条 MCP 连接**做只读探测。
  > 「不打断开发者」≠「观察者可以自由收工」：**观察者自己必须阻塞在确定性 watcher 上**（下面第一条），
  > 因为第 2 轮的缺陷正是「等待由智能体的意志力完成」。
- **等待与记录一律交给确定性脚本，观察者不得自行决定何时结束**（§0 第 8 条，TASK-061 根因③）：
  **先**跑**一次阻塞调用**（`-TimeoutSec 4500` 由 §0 第 8 条给定，**禁止**改小）：

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp_watch_run.ps1 `
    -Marker    "%TEMP%\mcp-breakout\DEV-DONE.marker" `
    -TracePath "%TEMP%\mcp-breakout\trace-editor-headless.jsonl" `
    -TracePath "%TEMP%\mcp-breakout\trace-game.jsonl" `
    -TracePath "%TEMP%\mcp-breakout\PROGRESS.md" `
    -TimeoutSec 4500 -StaleSec 300 -IntervalSec 30 `
    -OutDir    "%TEMP%\mcp-breakout\watch"
  ```

  （`-TracePath` 取实际存在的追踪名，**并必须把心跳 `PROGRESS.md` 一起纳入**；追踪名不确定时可用
  `-TracePath "%TEMP%\mcp-breakout\trace-*.jsonl"` 通配。）
  **等它返回**（它以 `WATCH_STOP stop_reason=...` 一行收口，并写 `watch.log` / `watch-summary.json`）；
  **然后**再基于**完整**记录做分析与记录。
  **禁止**用自己的 sleep 轮询循环决定何时收工；**不得**在自己的分析中忽略 `stop_reason`。
- **停止理由必须进产物**（机器可读，逐项抄自 watcher 返回值或 `watch-summary.json`）：
  `stop_reason`（`marker|timeout|stale`）、`polls`、`elapsed_sec`、`last_seq`、`trace_lines`、watcher 日志路径
  （`watch.log` 与 `watch-summary.json` 的路径）。**`stop_reason != marker` 时，必须在观察文件与返回值里显式写
  「观察在开发结束前停止」**，并给出 reason 与最后 `seq`/行数，**不得**把「被强制停止」写成「观察完成」；
  同时把 `watch.log` **复制进仓库**（`docs/reports/evidence/task060/`）。
  > **陷阱（TASK-061 实测）**：`.gitignore:308` 有 `*.log`，所以「复制进仓库」**不等于**「进了提交」——
  > `git add` 会**静默跳过**它（`git status --ignored` 才看得见 `!!`）。必须 `git add -f <watch.log>`，
  > 并在报告里给出该文件在本提交中的锚点。（同理适用于 `watch-summary.json` 之外任何 `*.log` 证据。）
- **至少给出**：≥3 条「多次调用才摸清用法」（连续失败后成功，附序列与错误码）、≥2 条缺失工具线索、
  ≥2 条可合并候选（高频 2-3 步序列）、≥2 条异常或矛盾。**没有就如实说没有**（说明查了哪些信号）——**不得凑数**。
- 返回**观察文件路径 + ≤6 行摘要**（摘要**必须**含 `stop_reason` 与 watcher 日志路径）。

## §D 汇总者（最后跑）

**产出**：`docs/reports/BREAKOUT-FINDINGS.md`。

- 输入：§A 方案、§B 日志、§C 观察、两份追踪原文（**仓库内副本**）。
- **必须自己回追踪原文复算**（行号 + 响应 sha256），标注**实测/推断**；发现对不上的**明确指出**（对观察者也要纠错）。
- **四张表**（异常 / 缺失工具 / 可合并 / 可优化），每条带证据；按**证据强度 × 影响面**排序；标出**不建议做**的。
- **单列「疑似缺陷」**：真缺陷给**最小复现** + 期望/实际 + 证据 sha256 + 严重度。
- **并回答一个专问**：**§A 的六条新能力判据**逐条给「**通过 / 不通过 / 不可构造**」+ 证据（这是本轮的主要验收点）。
- **必须核对 `stop_reason`**（TASK-061，§0 第 8 条）：**不得**采信 §C 的转述，必须自己打开
  `watch.log`（§C 已复制进 `docs/reports/evidence/task060/`）与 `watch-summary.json`，把
  `stop_reason` / `polls` / `elapsed_sec` / `last_seq` / `trace_lines` **逐项抄进报告并与 §C 说的对账**；
  对不上就**明确指出**（对观察者也要纠错）。
  - `stop_reason = marker` → 才能称「观察覆盖了整个开发过程」；
  - `stop_reason = timeout|stale` → **报告里必须明确标注「本轮观察不完整」**并说明原因（并写明最后 `seq`/行数）；
  - 若产物/返回值**缺少**这些字段，或 §C 在 watcher 返回前就收尾 → 视为**观察环节不合格**，在报告里单列。
- 返回**发现文件路径 + ≤8 行摘要**（含：确认的异常数/缺失数/可合并数/可优化数 + 六条新能力判据的结论 + 最该先做的 2 条）。