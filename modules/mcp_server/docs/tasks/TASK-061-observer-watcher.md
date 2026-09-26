# TASK-061 — **修「观察者提前结束」**：确定性 watcher + 硬停止条件 + 停止理由证据

> 先读 `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）与本文件。
> 报告 `docs/reports/REPORT-061-observer-watcher.md`。返回决策者：**≤8 行总结 + 报告路径**。

## 0. 问题（用户报告，已定位为**协议设计缺陷**，不是偶发）

第 2 轮试测中**观察者在开发尚未结束时就结束了**。三个根因：
1. **预算比工作短**：观察者预算 25 分钟，而完整开发几乎必然更久 → **到点必退**；
2. **停止条件交给智能体判断**：`轮询直到 marker 或预算到顶` 没有**机器可核对的停止理由**，LLM 长轮询里会「觉得够了」；
3. **等待没有交给确定性进程**：真正该做等待与记录的是**脚本**，不是智能体的意志力。

## 1. 要做的事

### 1.1 新增确定性 watcher：`scripts/mcp_watch_run.ps1`

**纯 ASCII**；参数：`-Marker <path>`（开发完成标记）、`-TracePath <path>`（可多个）、`-TimeoutSec <n>`、
`-StaleSec <n>`（超过这么久**没有新追踪行**=开发疑似卡死）、`-IntervalSec <n>`（默认 30）、`-OutDir <path>`。
**行为**（**必须**）：
1. **阻塞等待**，每 `IntervalSec` 检查一次：①marker 是否存在；②追踪文件**新增行数/最后 `seq`**（用**行道数**与最后一行 `seq`，别解析本地化文本）；
2. 每次检查把一行状态**追加**到 `-OutDir\watch.log`（时刻 / marker? / 每个 trace 的行数与最后 seq / 距上次新增秒数）；
3. **停止并退出**，退出码与**机器可读的一行结论**必须给出**哪一种**：
   - `marker`（开发完成）→ **exit 0**；
   - `timeout`（到 `-TimeoutSec`）→ **exit 0 但 `reason=timeout`**（让上层能区分"正常完成"与"被迫放弃"）；
   - `stale`（`-StaleSec` 内无新行）→ **exit 0 但 `reason=stale`**；
4. 结束时**打印并写文件**：`stop_reason`、耗时、观察到的**最后一个 `seq`**、追踪总行数、watcher 轮询次数；
5. **不得**依赖 `netstat`/本地化输出；**不得**杀任何进程；**绝不**碰 9877。

### 1.2 改写试测协议（改 `docs/tasks/TASK-060-breakout-round-2.md` 的 §0/§C/§D）

1. **预算必须对齐**：开发者 **45 分钟**；**观察者/watcher 75 分钟**（**严格大于**开发者，使"开发者还没完、观察者已退"在构造上不可能）。
2. **观察者不许自行决定结束**：它**必须**先用**一次阻塞调用**跑 `mcp_watch_run.ps1`（`-TimeoutSec 4500`），
   **等它返回**；然后**只能**基于完整记录分析。**禁止**自己写 sleep 轮询循环来"看着办"。
3. **必须在产物与返回值里给出停止理由**：`stop_reason`（`marker|timeout|stale`）、`polls`、`last_seq`、`trace_lines`、
   以及 watcher 日志路径；**若 `reason != marker`，必须显式声明"观察在开发结束前停止"**，并说明原因。
4. **§D 汇总者**必须**核对**该 `stop_reason`：若为 `timeout|stale`，报告里要**明确标注**「本轮观察不完整」。

### 1.3 顺带：开发者必须留**心跳**

在 TASK-060 §B 加一句：开发者**每个里程碑**往 `%TEMP%\mcp-breakout\PROGRESS.md` 追加一行（时间 + 已完成 + 下一步），
使 `stale` 判据有**第二个**信号（追踪之外）。

## 2. 证据（必须给）

1. **三种停止各演示一次**（可构造）：①`marker`：起一个后台进程 10 秒后写 marker → watcher 立即返回 `reason=marker` 且退出码 0；
   ②`timeout`：不写 marker、`-TimeoutSec 15` → `reason=timeout`；③`stale`：先追加几行追踪再停止追加（`-StaleSec 10`）→ `reason=stale`；
   三种都要贴 `watch.log` 与结论行。
2. **反例演示（关键）**：证明**旧协议会早退** —— 用旧口径（25 分钟预算）模拟"开发进行中"（marker 不存在）→、
   watcher 在 `timeout` 时**明确报 `reason=timeout`**，而不是静默结束（贴证据）。
3. **`-TimeoutSec` 的计算依据**：写明"观察者 > 开发者"的取值与理由（写进 TASK-060 与报告）。
4. 改完 TASK-060 后，**逐条自查** §C 里**不再存在**"由智能体自行决定结束"的措辞（贴改动前后的 §C 片段对照）。

## 3. 门与纪律

本批**只改 `scripts/**` 与 `docs/**`**：`git diff --stat -- modules/mcp_server/tools tests` 必须为空（给证据）；
**契约不动**；脚本纯 ASCII 且 `parse-errors=0`；
**绝不占用/杀/重启 9877**；端口 9888/9889（本批若不需要起引擎则说明）；禁止 push；结论按 D86 标锚点。