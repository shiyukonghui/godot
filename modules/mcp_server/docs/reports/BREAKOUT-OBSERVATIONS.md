> ## ⚠️ 状态声明（TASK-062 回收时前插；**原正文未改动**）
>
> 1. **本轮 workflow 被取消（TASK-060 第 2 轮试测）。** 本文件是**中断时的快照**，不是完成态产物；
>    TASK-060 §D（汇总者）**从未运行**。
> 2. **观察者使用旧协议（TASK-061 之前）—— 观察在开发结束前停止，本文件覆盖不完整。**
>    §C 的观察窗口是 **2026-09-25 05:34:40 → 06:00:25**，由自建 watchdog
>    （`evidence/task060/c-obs/watch.ps1`，预算 1500 s）以 **`BUDGET_REACHED`** 结束
>    （`c-obs/watch.log` 末行 `t+1505s 06:00:25 … BUDGET_REACHED`，`marker=False` 全部 76 次采样）
>    ——**不是** TASK-061 的 `mcp_watch_run.ps1` / `stop_reason=marker`，也**没有**机器可读的
>    `stop_reason` / `polls` / `last_seq` 字段。
>    开发实际持续到 **08:01:15**（`evidence/task060/c4/` 最后一份证据的 mtime），
>    §B 的**第一次**工具调用发生在 **06:26:28**（`DEV-LOG-raw-run.log:74` 之后，
>    `c1/c1_g1_remove_autoload.*` 的 mtime）→ **观察在开发开始调用工具之前 26 分钟就结束了，
>    距离开发真正结束约 2 小时。**
>    因此本文 §5 的结论「§B 在整整 25 分钟预算内没有向服务端发出任何一条 `tools/call`」
>    **只对 06:00:25 之前成立**；把它读成「本轮 §B 从未调用工具」是**错的**。
> 3. **不得把本快照当作完整记录使用。** 六条新能力判据的结论、四张表与疑似缺陷，
>    一律以 `modules/mcp_server/docs/reports/BREAKOUT-FINDINGS.md` 为准——它按
>    `evidence/task060/**`（含 `trace-recovered/` 的完整追踪）的**原文**复算，并逐条标注
>    哪些结论受「观察不完整」影响。
> 4. **回收说明。** 本文件原被写到**引擎仓根** `docs/reports/`（未跟踪，445 个文件）；
>    TASK-062 将其整体搬入 `modules/mcp_server/docs/reports/`，并把正文里指向根
>    `docs/...` 的路径引用改为 `modules/mcp_server/docs/...`。
>    **除路径引用外，原正文一字未改。** 逐文件搬前/搬后 sha256 对照见
>    `evidence/task060/recovery/PATHFIX-TRANSFORM.tsv` 与 `docs/reports/REPORT-062-breakout-recovery.md`。
> 5. **锚点（D86）**：正文写作时的 HEAD 是 `4f99a4e37ac4160b5c9b98513068872521bee975`
>    （`feature/mcp-server-module`）；回收动作的记录见 `REPORT-062-breakout-recovery.md`。


# BREAKOUT-OBSERVATIONS — TASK-060 §C（试测观察者）

> **角色**：§C 观察者。**只读、并行、不阻塞**。**产出**：本文件（边观察边追加）。
> **任务书**：`modules/mcp_server/docs/tasks/TASK-060-breakout-round-2.md`（§0 总则 + §C）。
> **手册**：`modules/mcp_server/docs/tasks/PLAYBOOK-group-port.md`。
> **方案与观察规则**：`modules/mcp_server/docs/reports/BREAKOUT-TEST-PLAN.md`（§3 观察规则，本文件按其 §3.3 四条信号口径收口）。
> **纪律**：绝不占用/杀/重启 **9877**；绝不改 `modules/mcp_server/**`、`modules/mono/**` 的实现；
> 绝不改 scratch 工程、绝不打断 §B 进程。**本文件只写「服务端追踪里真实发生过的事」**，推断一律标注。
> **预算**：25 分钟（或到 `%TEMP%\mcp-breakout\DEV-DONE.marker` 出现为止，先到者为准）。

---

## §0 环境基线（开工第一步，**实测**）

| 项 | 值 | 证据 | 性质 |
|---|---|---|---|
| HEAD | `4f99a4e37ac4160b5c9b98513068872521bee975`（`feature/mcp-server-module`） | `git log --oneline -3` | 实测 |
| 契约 | `modules/mcp_server/docs/tools_list.renamed.json`，**175 条** | `json.load(...)['result']['tools']` → `n=175` | 实测 |
| 契约前缀分布 | `project_*` **47**、`editor_*` **103**、`running_game_*` **23**、`os_*` **2** | 同上（按 `name.split('_')[0]` 计数） | 实测 |
| **9877 守卫** | 开工时 `netstat -ano \| findstr ":9877 :9888 :9889"` → **无输出（exit 1）** | 见 §1 第 1 行 | 实测 |
| **9888 / 9889** | 同上：**无监听** | 同上 | 实测 |
| scratch 工程 | `%TEMP%\mcp-breakout\` = `C:\Users\wyl\AppData\Local\Temp\mcp-breakout` → **不存在** | `dir` → `File Not Found`；`Test-Path` → `False` | 实测 |
| Godot 进程 | `Get-Process *godot*` → 空 | 同上 | 实测 |
| 分析器真实路径 | `modules/mcp_server/scripts/analyze_mcp_trace.py`（**不是** `scripts/analyze_mcp_trace.py`） | `glob` 命中；方案 §0 亦已记载 | 实测 |
| 观察者 watchdog | `modules/mcp_server/docs/reports/evidence/task060/c-obs/watch.ps1`（纯 ASCII）+ `watch.log`（每 20 s 一行，只读探测） | 本目录 | 实测 |
| 观察者证据目录 | `modules/mcp_server/docs/reports/evidence/task060/c-obs/` | `New-Item -ItemType Directory -Force` | 实测 |

**开工时的关键事实（决定了本文件的证据来源）**：§C 开工时 **§B 尚未启动**——
scratch 工程不存在、两个试测端口都没有监听、`trace-*.jsonl` 一个都没有。
因此本文件**先写基线**，再按 §3.2 的节奏轮询，逐段追加。

---

## §1 时间线（append-only，每行一条实测）

| # | 时刻 | 观察 | 证据 |
|---|---|---|---|
| 1 | 2026-09-25T05:34:40+08:00 | `netstat -ano \| findstr ":9877 :9888 :9889"` → **无输出，exit 1**；`%TEMP%\mcp-breakout` 不存在；`Get-Process *godot*` 空 | `c-obs/watch.log` 起始行；本条为直接命令输出（未落盘，属**过程性事实**，已由后续 watchdog 每 20 s 复测并落盘） |
| 2 | 05:34:40 | 观察者 watchdog 启动（预算 1500 s，间隔 20 s） | `c-obs/watch.ps1`；`watch.log` |
| 3 | 05:34:40 | 契约清点为 **175 条**，前缀分布 47/103/23/2 | 见 §0 表 |

---

## §2 发现（按 §C 的四类要求收口）

> **填写规则**：未观测到就**如实说没有**并列出**查了哪些信号**（§C 明令，不得凑数）。
> 每条发现必须有：`seq` / 工具名 / 参数要点 / 错误码 / 追踪行号 / 响应 sha256（若已落盘）。
> **⚠️ 本节 2.1–2.4 的「待填」占位符的最终结论见 §5；结论是「§B 零工具调用」，故四类要求的计数以 §5 为准。**

### 2.1 「多次调用才摸清用法」（目标 ≥3）

**待填。** 口径（方案 §3.3-1）：**同一工具、同一连接、同代、中间无别的工具调用**的「先失败后成功」对；
须附**连续失败的错误码序列** + 成功的**参数差异**。

### 2.2 缺失工具线索（目标 ≥2）

**待填。** 口径（方案 §3.3-2）：只有两种判法 —— ①工具名不存在 → **`-32601`**；
②参数名被反复试探（≥2 次）且**从未被接受**。**必须解析 `tools/list` 的 `name` 字段做集合判断**
（**不得**用文本包含；M4 已实测两次假 PASS）。
> 静态可用的对照集（**推断**，非实测）：契约 175 条的 `name` 集合 = 期望集；两端点各自的期望子集由 `scope` 派生。

### 2.3 可合并候选（目标 ≥2）

**待填。** 口径（方案 §3.3-3）：**高频 2–3 步工具序列**（n-gram，同代同会话内），
判定门槛 = **引擎一次调用本可以做到**（须给引擎 API 依据）**且**合并后仍**全或无 + 第 i 项定位**。

### 2.4 异常 / 矛盾（目标 ≥2）

**待填。** 口径（方案 §3.3-4，对齐分析器默认阈值）：①延迟等待撞到自己的上限；
②**异常大的响应（>1 MiB）**；③**单工具占比 >30%**。此外：`seq` 跨代比较、`capture` 事件的
`changed` 与 `before/after` sha 矛盾、`status:"ok"` 但状态未变等**矛盾实例**。

---

## §3 诚实声明

- 本文件的每条结论**前缀**标 `实测`（有落盘响应/追踪 + sha256）或 `推断`（读源码/契约得出）。
- **事件行不是工具调用**（方案 §3.2）：`trace_opened` 与 `event:"capture"` **不计入**调用数/异常大响应/单工具占比。
- **`seq` 只在同一代内可比**（`trace_opened` 是唯一分代边界，每进程从 1 重启）；本文件**不跨代比 `seq`**。
- **只读**：观察者从未写入 scratch 工程、从未停止 §B 进程、从未监听 9877/9888/9889。
- 9877 守卫在每次「进程启动前后」的纪律适用于 §B；观察者**不启动任何 Godot**，故只做周期性 `netstat` 复测（见 `watch.log`）。

---
*(以下为轮询期间的追加内容)*

## §1-续 轮询记录（增量，`seq` 断段）

### 观察窗口 W1 — 05:36:00 ~ 05:39:47（§B 启动与首导，**尚无任何工具调用**）

| 时刻 | 观察（**实测**） | 证据 |
|---|---|---|
| 05:36:00 | scratch 工程 `%TEMP%\mcp-breakout\` **出现**；工程实体在 `proj\` 子目录 | `c-obs/watch.log` `t+40s scratch=True`；`Get-ChildItem` 列目录 |
| 05:36:27/34 | §B 自备脚本 `mcp060_bootstrap.ps1`(12728 B) / `mcp060_lib.ps1`(10995 B)；`logs\import-bootstrap.attempt1.log`(3864 B) 存在 | 目录清单 |
| 05:36:30 | 工程骨架：`proj\project.godot`(383 B)、`proj\Mcp060Breakout.csproj`(270 B)、`proj\NuGet.config`(297 B)、`proj\scenes\main.tscn`(54 B)、`proj\scripts\*.cs` **7 个**（`Ball.cs` 932 / `BreakoutMain.cs` 1953 / `Brick.cs` 457 / `Legit.cs` 52 / `Paddle.cs` 1209 / `SignalRegistry.cs` 767） | 目录清单（长度=字节） |
| 05:36:34 | `--import` 完成（`import-bootstrap.attempt1.log`）；`.cs.uid` **6 个**生成 | 目录清单 |
| 05:36:38 | 追踪**开启**：`%TEMP%\mcp-breakout\trace-editor-headless.jsonl`，**第 1 行 = `trace_opened`** | 见下方原文 |
| 05:36:38 | 首导**未崩溃**：`logs\editor-headless.err.log` = **0 B**；`out.log` 有 `[ DONE ] first_scan_filesystem` / `loading_editor_layout` | 文件长度 + `out.log` |
| 05:37:35 | 9888 **LISTENING**（PID **87116**）—— 与追踪里 `trace_opened.pid=87116` **一致** | `netstat -ano`；追踪第 1 行 |
| 05:37:35 | `run.log` 仅 1 行：`9877-guard[bootstrap-before] FREE`（§B 遵守 9877 纪律） | `run.log`(35 B) |
| **05:39:47** | 追踪仍**只有 1 行**（`trace_*.jsonl` 总数 = **1**，另一份 **游戏追踪尚未出现**）；**9889 未监听** | 文件长度 200 B；`netstat` |
