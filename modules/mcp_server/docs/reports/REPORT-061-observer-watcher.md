# REPORT-061 — 修「观察者提前结束」：确定性 watcher + 硬停止条件 + 停止理由证据

- `status`：**完成**（三件事全部落地，五种情景实测 PASS；门与纪律逐条给证据）
- `task`：`docs/tasks/TASK-061-observer-watcher.md`（TASK-061）
- `base`（本轮开工时的仓库锚点，D86）：`feature/mcp-server-module` @ **`0a9fc1d466`**
- `commits`：见 §8（**提交 A** = 脚本 + TASK-060 改写 + 证据 + 本报告；**提交 B** = 只回填本报告里的 A 锚点）
- `branch`：`feature/mcp-server-module`；**未 push**
- 报告口径：每条结论都标注**实测** / **推断**；引用的外部结论都带锚点（D86）

---

## 1. 交付物（全部 `scripts/**` 与 `docs/**`，契约与实现零改动）

| 文件 | 字节 | sha256 | 说明 |
|---|---|---|---|
| `modules/mcp_server/scripts/mcp_watch_run.ps1` | 15880 | `9e1d595cd45cf294c793e863c22b83399bd021bd953bd3574ae026eb97319906`（blob `5ee7dd287da4af26694856d29abf951226911d94`） | **新增**：确定性 watcher（纯 ASCII，`parse-errors=0`） |
| `modules/mcp_server/scripts/mcp061_watch_evidence.ps1` | 14555 | `364f9a0163d492a64614bce5577bd4f050c8561f9f7f6ce3b81b1e5535527816`（blob `6211ad989dcbb88b020f3ad918a51be43f0f77d6`） | **新增**：5 个情景的证据生成器（纯 ASCII，`parse-errors=0`） |
| `modules/mcp_server/docs/tasks/TASK-060-breakout-round-2.md` | — | blob `469710580bdd6fa435a296ab8623781ceef47291`（`git rev-parse 提交A:<path>`） | **改写** §0 第 8/9 条、§B 心跳、§C 全节（含 `*.log` 陷阱注记）、§D 核对条款（+56 −15） |
| `modules/mcp_server/docs/reports/evidence/task061/**` | **33 个文件** | 全量清单 `evidence/task061/sha256.txt`（33 行，**覆盖目录内全部文件含其自身**） | 三种停止 + 反例 + 旧协议对照 + §C 前后快照 + 自身缺陷的前后证据 |
| ‣ 其中 8 个 `watch.log` / `PREFIX-*.log` | — | 同上清单 | **必须 `git add -f`**：`.gitignore:308` 的 `*.log` 会把它们静默排除（见 §9.1 D-061-2，**实测**） |
| `modules/mcp_server/docs/reports/REPORT-061-observer-watcher.md` | 本文件 | — | 本报告 |

**实测**（非推断）的两条硬纪律其实测值见 §6.1（`git status` / `git diff --stat` 的完整粘贴）与 §6.2
（ASCII 字节数与 `parse-errors` 的完整粘贴）。

---

## 2. 问题定位（复述 + 本报告的判据）

第 2 轮试测的「观察者在开发结束前结束」**不是偶发**，是三条协议设计缺陷的必然结果：

1. **预算比工作短**：观察者预算 25 分钟（1500 s），完整开发几乎必然更久 → **到点必退**；
2. **停止条件交给智能体判断**：`轮询直到 marker 或预算到顶` 没有**机器可核对的停止理由**；
3. **等待没有交给确定性进程**：等待与记录由智能体的 sleep 循环承担。

TASK-061 的修法与判据一一对应：①预算对齐（观察者 > 开发者）；②停止理由**机器可读**（`stop_reason`）
且**必须进产物**；③等待交给 `mcp_watch_run.ps1`（**阻塞调用**）。

---

## 3. 第一件事：`scripts/mcp_watch_run.ps1`

### 3.1 接口契约（as-built）

| 参数 | 必填 | 默认 | 语义 |
|---|---|---|---|
| `-Marker <path>` | 是 | — | 开发完成标记（**唯一**的 `marker` 信号） |
| `-TracePath <path>` | 是（可多个/可重复） | — | 追踪或任意按行追加的文件；**支持 `*`/`?` 通配**；文件**尚不存在**时记 `MISSING` 并在出现后纳入 |
| `-TimeoutSec <n>` | 是 | — | 预算上界（秒） |
| `-StaleSec <n>` | 否 | `0` | `0` = 关闭 stale；>0 且**已观测到活动**后，超过这么久没有新行 → `stale` |
| `-IntervalSec <n>` | 否 | `30` | 轮询间隔（<1 时夹到 1） |
| `-OutDir <path>` | 是 | — | 输出目录（不存在则创建）；**唯一的写入位置** |

**停止理由与退出码**（实测）：

| reason | 触发 | 退出码 |
|---|---|---|
| `marker` | marker 存在 | **0** |
| `timeout` | `elapsed >= TimeoutSec` 且无 marker | **0**（靠 reason 区分，不靠退出码） |
| `stale` | 已有活动、且 `StaleSec` 内无新行 | **0** |
| （usage/setup 错） | `-TimeoutSec < 1` 或 `-OutDir` 建不出来 | **2**（**不是**停止理由，不得被读成停止理由） |

**同一次轮询里两个理由同时成立时的优先级：`marker` > `timeout` > `stale`** —— 预算是外边界，`timeout` 优先。

**产物**（实测样本见 §3.4）：`watch.log`（每次轮询追加一行 + `DECISION`/`WATCH_STOP`）、
`watch-summary.json`（机器可读）、`watch-summary.txt`（key=value）；stdout 最后一行：

```
WATCH_STOP stop_reason=timeout elapsed_sec=20 polls=11 last_seq=8 trace_lines=8 trace_files=1 stale_age_sec=2 watch_log=... summary=...
```

### 3.2 关键设计决策与理由

1. **活动度用「行道数 + 每行 `seq`」，不解析本地化文本**（要求 1；**实测**）：
   追踪的每个**换行结尾**记录算一行；`seq` 用 `'"seq"\s*:\s*([0-9]+)'` 取该行**第一个**匹配。
   依据（引擎源码，第一参考源）：请求行是 `{"id":<token>,"seq":N,...}`（`mcp_trace.cpp:295` + `:363` 的 id 拼接），
   捕获行是 `{"event":"capture","seq":N,...}`（`mcp_capture.cpp:609`）——**两者 `seq` 都在任何回显参数之前**，
   因此「第一个匹配」就是该行的顶层 `seq`，且不会被 `args`/`error_message` 里回显出来的 `"seq"` 干扰。
   **已声明的残余风险**：请求的 `id` 是**逐字**拼进 JSON 的（`mcp_trace.cpp:346-363`），
   理论上一个刻意构造的 `id`（如 `1,"seq":999`）能污染该行的首个匹配。本批为自用测试链路，风险可接受；
   写进 §6 风险登记，不隐藏。
2. **增量读，不重复读全文件**：保存每文件的字节偏移、行数、最后 `seq`；每轮只读**新增字节**，
   单轮上限 8 MiB（超出的下一轮继续）。**文件被截断/重建**时计数归零并记 `TRUNCATED`。
3. **`stale` 需要「先有活动」**（**这是对任务书字面语义的收紧，显式声明**）：
   任务书说「`StaleSec` 内无新行 = stale」。若**逐字**执行，则开发者**还没开工**（追踪还没生成）时也会判 stale，
   于是观察者会在开发者开工前退出——**正是本轮要修的缺陷换个形式复活**。
   因此 as-built：`stale` 只在 `activity_seen=true` 后成立；开工之前只由 `timeout` 收口。
   每次轮询的日志都打印 `stale_ok=`（资格）与 `activity_seen=`，**策略可见、可核对**（不藏在代码里）。
4. **心跳纳入 `-TracePath`**：§1.3 要求心跳成为 stale 的第二个信号。`PROGRESS.md` 是「按行追加的文本文件」，
   放进 `-TracePath` 即可用同一套行数判据覆盖，且它没有 `seq`（`last_seq` 自然保持 0）。
   因此 §C 的命令行**同时**传追踪与 `PROGRESS.md`（见 §4）。
5. **超时不是精确时刻**：`elapsed` 只在轮询点采样，所以实际停止时刻 ∈ `[TimeoutSec, TimeoutSec + IntervalSec]`。
   即 `-TimeoutSec 4500 -IntervalSec 30` ⇒ 最迟 4530 s 返回。**契约这样写死**，避免调用方以为 4500 是精确时刻。
6. **不杀进程、不用 netstat、不碰 9877**（要求 5；**实测**：脚本全文无 `Stop-Process`/`netstat`/`Get-NetTCPConnection`；
   对输入文件只读，`Open`+`FileShare.ReadWrite` 打开，写入只在 `-OutDir`）。

### 3.3 停止理由的实现要点（要求 3/4；**实测**）

- `watch.log` 每次轮询一行：`t+<秒>s <时刻> polls= marker= files= lines= seq= new= stale_age= stale_ok= activity_seen= [<每文件 l=行数 s=最后seq n=本轮新增 ...>]`；
- 结束写 `DECISION stop_reason=... elapsed_sec=... polls=...`；**`reason != marker` 时再写一行**
  `DECISION observation_stopped_before_development_ended=1 stop_reason=...`（让「被强制停止」在日志里**无法被读成观察完成**）；
- `watch-summary.json` 含 `stop_reason / exit_code / elapsed_sec / polls / last_seq / trace_lines / trace_files /
  marker_seen / activity_seen / stale_age_sec / observation_stopped_before_development_ended / traces[]`。

### 3.4 证据：三种停止各一次（要求 §2.1）

证据生成器：`scripts/mcp061_watch_evidence.ps1`（一条命令重跑全部 5 个情景，**实测** exit 0）：

```
S1_marker expected=marker actual=marker exit=0 PASS
S2_timeout expected=timeout actual=timeout exit=0 PASS
S3_stale expected=stale actual=stale exit=0 PASS
S4_counterexample expected=timeout actual=timeout exit=0 PASS
S5_old_protocol silent_end=yes last_log_line=t+  21s 08:32:38 scratch=True marker=False ports9877=0 ports9888/9=0 BUDGET_REACHED traces=1 exit=0 PASS
EVIDENCE_OK scenarios=5
```

**① `marker`**（`evidence/task061/s1-marker/watch.log`，helper 进程 10 s 后写 marker）：

```
t+0s  2026-09-25 08:31:11 polls=1 marker=0 files=1 lines=3 seq=3 new=3 stale_age=0 stale_ok=0 activity_seen=1 [trace-editor.jsonl l=3 s=3 n=3]
t+10s 2026-09-25 08:31:21 polls=6 marker=1 files=1 lines=3 seq=3 new=0 stale_age=10 stale_ok=0 activity_seen=1 [trace-editor.jsonl l=3 s=3 n=0]
DECISION stop_reason=marker elapsed_sec=10 polls=6
WATCH_STOP stop_reason=marker elapsed_sec=10 polls=6 last_seq=3 trace_lines=3 trace_files=1 ...
```

结论行（stdout，`evidence/task061/s1-marker/stdout.txt`）：`stop_reason=marker`，**exit 0**，`polls=6`，`last_seq=3`。

**② `timeout`**（`s2-timeout/watch.log`，无 marker、`-TimeoutSec 12 -StaleSec 600`）：

```
t+12s 2026-09-25 08:31:35 polls=7 marker=0 files=1 lines=2 seq=2 new=0 stale_age=12 stale_ok=1 activity_seen=1 [trace-editor.jsonl l=2 s=2 n=0]
DECISION stop_reason=timeout elapsed_sec=12 polls=7
DECISION observation_stopped_before_development_ended=1 stop_reason=timeout
WATCH_STOP stop_reason=timeout elapsed_sec=12 polls=7 last_seq=2 trace_lines=2 trace_files=1 ...
```

**exit 0 且 `reason=timeout`** —— 上层可以区分「正常完成」与「被迫放弃」（这正是要求 3 的要点）。

**③ `stale`**（`s3-stale/watch.log`，预置 5 行后不再追加，`-StaleSec 10 -IntervalSec 2`）：

```
t+0s  2026-09-25 08:31:36 polls=1 marker=0 files=1 lines=5 seq=5 new=5 stale_age=0  stale_ok=1 activity_seen=1 [trace-editor.jsonl l=5 s=5 n=5]
t+8s  2026-09-25 08:31:44 polls=5 marker=0 files=1 lines=5 seq=5 new=0 stale_age=8  stale_ok=1 activity_seen=1 [trace-editor.jsonl l=5 s=5 n=0]
t+10s 2026-09-25 08:31:46 polls=6 marker=0 files=1 lines=5 seq=5 new=0 stale_age=10 stale_ok=1 activity_seen=1 [trace-editor.jsonl l=5 s=5 n=0]
DECISION stop_reason=stale elapsed_sec=10 polls=6
DECISION observation_stopped_before_development_ended=1 stop_reason=stale
WATCH_STOP stop_reason=stale elapsed_sec=10 polls=6 last_seq=5 trace_lines=5 trace_files=1 ...
```

**退出码全为 0**，三种理由**只**由 `stop_reason` 区分——**实测**，不是推断。

### 3.5 反例演示（要求 §2.2，关键）

**构造**：「开发进行中」= marker 不存在 + 追踪**持续增长**（helper 每 3 s 追加一行，共 10 行）；
预算是**旧口径 25 分钟（1500 s）**，为可跑通按 **50× 压缩**到 20 s（**语义不变**：marker 缺失 + 预算耗尽）。
同一状态跑**两个** watchdog：

**(a) 新 watcher**（`evidence/task061/s4-counterexample/watch.log`；**实测**）：

```
t+0s  2026-09-25 08:31:47 polls=1  marker=0 lines=2 seq=2  new=2 ...
t+4s  2026-09-25 08:31:51 polls=3  marker=0 lines=3 seq=3  new=1 ...   <- 开发仍在推进
t+18s 2026-09-25 08:32:05 polls=10 marker=0 lines=8 seq=8  new=1 ...   <- 仍在推进
t+20s 2026-09-25 08:32:07 polls=11 marker=0 lines=8 seq=8  new=0 ...
DECISION stop_reason=timeout elapsed_sec=20 polls=11
DECISION observation_stopped_before_development_ended=1 stop_reason=timeout
WATCH_STOP stop_reason=timeout elapsed_sec=20 polls=11 last_seq=8 trace_lines=8 ...
```

→ watcher **明确报 `reason=timeout`**（`trace_lines=8`、`last_seq=8` 证明开发当时**仍在进行**），
并且在同一个文件里写了 `observation_stopped_before_development_ended=1`。**不是静默结束。**

**(b) 旧协议 watchdog 对照**（第 2 轮 `watch.ps1`，TASK-060 证据原物；**实测**）：
证据生成本着「不改历史证据」的原则，把旧脚本**只改两个常量**（`$scratch` 与 `$log` 指向本次 scratch）后运行，
改动逐行留档（`s5-old-protocol/transformation-diff.txt`）：

```
original_sha256 : 21c99ce28aa83e02c7a8231811e4eaf3e2dec921225da7946adab1021faa23ba
copy_sha256     : 48a89d4641c444341ec9400c368a9425cee468575497da5b5d1b50f575d749a2
changed_lines   : 2
line 9 OLD: $scratch  = Join-Path $env:TEMP 'mcp-breakout'
line 9 NEW: $scratch  = 'C:\Users\wyl\AppData\Local\Temp\task061\s5-old-protocol'
line 11 OLD: $log      = 'F:\...\evidence\task060\c-obs\watch.log'
line 11 NEW: $log      = 'C:\Users\wyl\AppData\Local\Temp\task061\s5-old-protocol\watch.log'
```

旧 watchdog 的 `watch.log`（**实测**，注意 `traces=1 [trace-editor.jsonl=186→651]`：开发**正在推进**）：

```
t+   0s 08:32:18 ... [trace-editor.jsonl=186]
t+   4s 08:32:22 ... [trace-editor.jsonl=279]
t+   8s 08:32:26 ... [trace-editor.jsonl=372]
t+  12s 08:32:30 ... [trace-editor.jsonl=558]
t+  16s 08:32:34 ... [trace-editor.jsonl=651]
t+  21s 08:32:38 ... BUDGET_REACHED traces=1
```

其 **stdout 只有 1 字节（一个裸 LF）**，`watch.log` 全文**不含 `stop_reason`**
（机器检查：`silent_end=yes`），**退出码 0**。也就是说旧协议**在开发进行中静默结束**，
而且**任何上层产物都拿不到「这是一次被迫停止」的事实**——这正是第 2 轮事故的机器侧形态。

> **对照结论（实测）**：同一状态、同一「预算耗尽」事件，旧协议输出 `BUDGET_REACHED` 而无理由；
> 新 watcher 输出 `stop_reason=timeout` + `observation_stopped_before_development_ended=1`。

### 3.6 `-TimeoutSec` 取值依据（要求 §2.3；观察者 > 开发者）

| 量 | 值 | 依据 |
|---|---|---|
| 开发者硬停止 | **2700 s（45 分钟）** | §0 第 8 条；观察者必须比它活得久 |
| 观察者/watcher 预算 | **4500 s（75 分钟）** | `-TimeoutSec 4500`，**严格大于** 2700 |
| 余量 | **1800 s** | ①引擎启动/导入/首次构建的前段开销；②开发者可能**晚于**约定开工；③`IntervalSec=30` 的采样误差（最迟 `4500+30=4530 s` 返回） |
| `-IntervalSec` | **30 s** | 轮询开销 ≪ 开发粒度；给 `stale` 留 10 倍于采样间隔的判据余量 |
| `-StaleSec` | **300 s** | **实测**依据：第 1 轮 400 条真实调用（16 个 run）里**同一 run 内相邻 `seq` 调用的最大间隔 = 92.235 s**（`docs/reports/evidence/racing/CALL-LOG.jsonl`，复算命令见 §7.2）；300 s ≈ **3.2×** 观测到的最大合法静默，并覆盖第 1 轮 ~100 s 级的导入/播放开销 |

> 关键判据由算术保证：**4500 > 2700**，所以「开发者还没完、观察者已退」在**构造上不可能**
> （除非开发真的卡死 = `stale`，那是**该**停下来报警的情形）。

---

## 4. 第二件事：改写 `TASK-060` 的 §0/§B/§C/§D（按任务书 §1.2 校验并补齐）

`git diff` 统计（**实测**）：`1 file changed, 56 insertions(+), 15 deletions(-)`。

### 4.1 §0 第 8/9 条（校验 + 补齐）

- **保留**任务书已写：开发者 45 分钟 / 观察者 75 分钟（严格大于）、禁止自行决定结束、`stop_reason/polls/last_seq/trace_lines/watch 日志路径`、`reason != marker` 必须声明「观察在开发结束前停止」；
- **补齐**（原文缺失的部分）：①**取值依据**（`2700 vs 4500` 的算术 + 1800 s 余量构成 + `TimeoutSec+IntervalSec` 上界）；
  ②**完整命令行**（含 `PROGRESS.md` 与窗外层 `OutDir`）；③`stale` 的**两个信号**与**「先有活动才可 stale」**策略；
  ④`-StaleSec 300` 的**实测依据**（92.235 s）；
- **§0 第 9 条补齐**：心跳必须**追加**、不得整体重写（重写会让「新增行数」失真）。

### 4.2 §B（要求 §1.3）

新增「**心跳（强制，§0 第 9 条）**」条目：每个里程碑向 `%TEMP%\mcp-breakout\PROGRESS.md` **追加**
一行（时间 + 已完成 + 下一步），并说明它是 `stale` 的第二个信号；同时把 `DEV-DONE.marker`
明确为**唯一**完成信号（`stop_reason=marker` 判据）。

### 4.3 §C（改动前后片段对照 + 机器自查）

**改前**（`evidence/task061/task060-sectionC-before.md`，锚点 `git show HEAD:...@0a9fc1d466`）：

```
## §C 观察者（与 §B **并行**、**只读**、**不阻塞**）
- **以服务端追踪为主**（`%TEMP%\mcp-breakout\trace-*.jsonl`），**但等待与记录交给确定性脚本**：
  **先**跑**一次阻塞调用** `scripts/mcp_watch_run.ps1 -Marker ... -TracePath <各 trace> -TimeoutSec 4500 -StaleSec 300 -OutDir ...`，
  **等它返回**（它会给出 `stop_reason`）；**然后**再基于**完整**记录做分析与记录。
  **禁止**用自己的 sleep 循环决定何时收工；**不得**在 `stop_reason=marker` 之前收尾。
- **至少给出**：≥3 条「多次调用才摸清用法」...
- 返回**观察文件路径 + ≤6 行摘要**。
```

**改后**（`evidence/task061/task060-sectionC-after.md`）——差异只在**收紧**，逐条：

1. 标题 `**不阻塞**` → `**不打断开发者**`，并加注：**「不打断开发者」≠「观察者可以自由收工」**——
   观察者**自己必须阻塞在 watcher 上**（旧的「不阻塞」措辞正是根因③的温床）；
2. 阻塞调用从**一行内嵌**改为**可直接复制的完整命令行**：`-TracePath` **必须含 `PROGRESS.md`**，
   追踪名不确定时用 `trace-*.jsonl` 通配；明确 **`-TimeoutSec 4500` 禁止改小**；
3. 新增独立条目「**停止理由必须进产物**」：`stop_reason/polls/elapsed_sec/last_seq/trace_lines/`
   `watch.log 与 watch-summary.json 路径`；`stop_reason != marker` 时必须写「观察在开发结束前停止」，
   并把 `watch.log` **复制进仓库**（`docs/reports/evidence/task060/`）；
4. 返回值摘要**必须**含 `stop_reason` 与 watcher 日志路径；
5. 追加**`*.log` 陷阱注记**（§9.1 D-061-2）：`.gitignore:308` 的 `*.log` 会让 `git add` **静默跳过**
   「复制进仓库」的 `watch.log`，必须 `git add -f` 并给出提交锚点。

**逐条自查（机器扫描，非人眼）**：对 §C 全节做关键词扫描 `决定|收工|轮询|预算|sleep`（**实测**）

```
=== 改前 §C 命中 ===
  **禁止**用自己的 sleep 循环决定何时收工；**不得**在 `stop_reason=marker` 之前收尾。

=== 改后 §C 命中 ===
  > 「不打断开发者」≠「观察者可以自由收工」：**观察者自己必须阻塞在确定性 watcher 上**（下面第一条），
- **等待与记录一律交给确定性脚本，观察者不得自行决定何时结束**（§0 第 8 条，TASK-061 根因③）：
  **禁止**用自己的 sleep 轮询循环决定何时收工；**不得**在自己的分析中忽略 `stop_reason`。
```

改后的**每一处**命中都是**禁止/否定**句式（`禁止`/`不得`/`≠`），**没有任何**「由智能体自行决定结束」的许可措辞；
改后还**多出**一条正面义务（「必须阻塞在 watcher 上」）。→ **§C 里不再存在「由智能体自行决定结束」的措辞（实测）**。

### 4.4 §D（补齐核对义务）

`stop_reason` 核对从「若为 timeout|stale 要标注」升级为**不可转述的强制对账**：
必须自己打开 `watch.log`（仓库内副本）与 `watch-summary.json`，把
`stop_reason/polls/elapsed_sec/last_seq/trace_lines` **逐项抄进报告并与 §C 说的对账**，对不上要**指出**；
`marker` 才能称「观察覆盖了整个开发过程」，`timeout|stale` 必须标注「**本轮观察不完整**」；
**产物缺这些字段、或 §C 在 watcher 返回前收尾 → 观察环节不合格，单列**。

---

## 5. 第三件事：实现过程中发现并修复的**自身缺陷**（append-only，不隐藏）

**症状**（**实测**）：证据生成器第一版跑出 S4 时，`watch.log` 里**行数正确增长**（l=1..6），
但 `last_seq` **恒为 1**（首行的 `seq`）。三种停止的理由仍然正确，因此这是一个**会静默给出错值**的缺陷
（正是 PLAYBOOK 反复强调的那类）：

```
# evidence/task061/defect-seek/PREFIX-watch-plain.log（修复前，实测）
t+0s  ... lines=1 seq=1 new=1 ...
t+4s  ... lines=2 seq=1 new=1 ...     <- 行数涨了，seq 没动
t+10s ... lines=4 seq=1 new=1 ...
t+12s ... lines=5 seq=1 new=1 ...
```

**定位**（**实测**）：给脚本注入一行调试输出后重跑（`defect-seek/PREFIX-instrumented-parse.log`）：

```
LINE=[{"id":1,"seq":1,"method":"tools/call"}] SUCCESS=True VAL=1    <- 每一轮处理的都是第 1 行
LINE=[{"id":1,"seq":1,"method":"tools/call"}] SUCCESS=True VAL=1
LINE=[{"id":1,"seq":1,"method":"tools/call"}] SUCCESS=True VAL=1
LINE=[{"id":1,"seq":1,"method":"tools/call"}] SUCCESS=True VAL=1
```

**根因**：每轮**新开**一个 `FileStream`（位置 = 0），却按保存的偏移计算 `remaining` 后直接 `Read`，
**没有 `Seek` 到偏移** → 读到的永远是文件**开头** `remaining` 字节。偏移推进使得「剩余量」恰好像是新增量，
于是「行数正确、内容恒为首行」——一个自洽的假象。

**修复**（一行 + 注释）：

```powershell
+        # The stream is opened fresh on every poll, so its position is 0: it
+        # MUST be moved to the saved offset, otherwise the reader re-reads the
+        # head of the file and reports the first line's `seq` forever ...
+        [void]$stream.Seek([int64]$State.Offset, [System.IO.SeekOrigin]::Begin)
```

**修复后**（**实测**，`evidence/task061/defect-seek/` 的 PRE 版 vs §3.5 的 POST 版）：行数与 `seq` 同步推进
（`l=2 s=2` → `l=5 s=5`）；本报告 §3.4/§3.5 的**全部**证据都是**修复后**重跑生成——
可核对的机器事实是 `s4-counterexample/watch.log` 的 `start=` 时间戳
（PRE 版 `08:16:54` vs POST 版 `08:31:47`，见 `defect-seek/PREFIX-watch.log` 与
`s4-counterexample/watch.log` 的首行）以及 POST 版 `seq` 与行数同步（PRE 版恒为 1）。
重跑后 5 个情景仍全部 PASS（`s4-counterexample/watch-summary.txt` 为 `stop_reason=timeout`、`last_seq=8`）。

> 教训（写进 `next_step`）：**「行数增长」不能证明「读位点正确」**——单调计数器与偏移是两套状态，
> 只测其一必然漏掉这一类。这也是「证据生成器本身要有反例情景（S4 渐进追加）」的价值。

---

## 6. 门与纪律（逐条给证据）

### 6.1 只改 `scripts/**` 与 `docs/**`（**实测**）

```
$ git -C F:\RustProjects\godot-mcp-pro\code\godot status --porcelain
 M modules/mcp_server/docs/tasks/TASK-060-breakout-round-2.md
?? docs/
?? modules/mcp_server/docs/reports/REPORT-061-observer-watcher.md
?? modules/mcp_server/docs/reports/evidence/task061/
?? modules/mcp_server/scripts/mcp061_watch_evidence.ps1
?? modules/mcp_server/scripts/mcp_watch_run.ps1
（另有本批之前就存在的既有未跟踪物：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`
 —— 与 PLAYBOOK §5 的清单一致；`?? docs/` 是**第 2 轮遗留**，见 §9.1 D-061-1，本批未改动它）

$ git diff --stat -- modules/mcp_server
 .../docs/tasks/TASK-060-breakout-round-2.md        | 71 +++++++++++++++++-----
 1 file changed, 56 insertions(+), 15 deletions(-)

$ git diff --stat -- modules/mcp_server/tools modules/mcp_server/tests
（空输出 —— 逐字节与 HEAD 相同）
```

**契约不动**：`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、`docs/tool-groups.json`
均未出现在 `git status` 中（**实测**）。`tools/**` 与 `tests/**` **零改动**。

**证据入仓的强制动作（实测）**：8 个 `watch.log`/`PREFIX-*.log` 被 `.gitignore:308` 的 `*.log` 忽略，
必须 `git add -f`：

```
$ git check-ignore -v modules/mcp_server/docs/reports/evidence/task061/s1-marker/watch.log
.gitignore:308:*.log	modules/mcp_server/docs/reports/evidence/task061/s1-marker/watch.log
$ git status --porcelain --ignored | Select-String 'task061'
!! modules/mcp_server/docs/reports/evidence/task061/s1-marker/watch.log
!! modules/mcp_server/docs/reports/evidence/task061/s2-timeout/watch.log
!! modules/mcp_server/docs/reports/evidence/task061/s3-stale/watch.log
!! modules/mcp_server/docs/reports/evidence/task061/s4-counterexample/watch.log
!! modules/mcp_server/docs/reports/evidence/task061/s5-old-protocol/watch.log
!! modules/mcp_server/docs/reports/evidence/task061/defect-seek/PREFIX-watch.log
!! modules/mcp_server/docs/reports/evidence/task061/defect-seek/PREFIX-watch-plain.log
!! modules/mcp_server/docs/reports/evidence/task061/defect-seek/PREFIX-instrumented-parse.log
```

**本批的处置**：`git add -f` 后它们**已进入提交 A**（`git ls-tree -r ea345b51df --name-only -- modules/mcp_server/docs/reports/evidence/task061 | Select-String 'log'` 列出 8 个，已实测）。

### 6.2 脚本纯 ASCII 且 `parse-errors=0`（**实测**）

```
scripts\mcp_watch_run.ps1          bytes=15880 nonascii=0 parse-errors=0
scripts\mcp061_watch_evidence.ps1  bytes=14555 nonascii=0 parse-errors=0
```

（`nonascii` = 全文 `>127` 字节数，逐字节统计；`parse-errors` =
`[System.Management.Automation.Language.Parser]::ParseFile` 的错误数。两者均按任务书要求为 0。）

### 6.3 端口与进程纪律（**实测**）

- 全文**无** `netstat` / `Get-NetTCPConnection` / `Stop-Process` / `taskkill`；
- **9877 从未被占用、探测、杀或重启**（本批**根本不启动引擎**，因此 9888/9889 也未被使用——
  **显式声明**：本批的四道门与 9888/9889 无关，未起任何引擎进程）；
- 证据里的 `ports9877=0` 是**旧脚本自己**的 netstat 采样（对照物），不是 watcher 的行为。

### 6.4 未 push（**实测**）：本批结束后分支 `feature/mcp-server-module` 仍为本地状态，无 remote 写入。

### 6.5 证据 sha256 必须能从仓库复现（**实测**，并修掉了一个陷阱）

`.gitattributes` 有 `* text=auto eol=lf`，所以**工作区 CRLF 的文件在提交里是 LF**：
本批第一版证据（CRLF 工作区）里 `s1-marker/watch.log` 工作区 1538 字节、提交 blob **1525** 字节
——即「我贴的 sha256 是工作区的，而仓库里存的是另一份字节」。任何人 `git clone` 后校验 sha256 都会失败。
**处置**：watcher 与生成器改为**只写 LF**（`AppendAllText` 用 `` `n ``；`ConvertTo-Json` 的输出显式
`.Replace("`r`n","`n")`；旧协议 watchdog 的 CRLF 日志在复制前做**仅 EOL** 的归一化，内容一字未改），
全部证据重新生成。**验收判据（可复跑）**：对 `evidence/task061/**` 每一个文件，
`git cat-file -s <index blob>` 必须等于工作区文件字节数（相等 ⇒ 没有发生 EOL 归一化）：

```
$ git ls-files -s modules/mcp_server/docs/reports/evidence/task061 | ... # 逐个比对 blob 与工作区字节数
mismatches=0        # 实测（33 个文件全部相等；CRLF 版本当时 mismatches=5）
```

> 这条与 §9.1 的 D-061-1/D-061-2 是**同一族**问题：**「文件在磁盘上」不等于「证据在仓库里」，
> 「字节在磁盘上」也不等于「字节在仓库里」**。两层都要机器校验。

---

## 7. 复算命令（谁都能重跑）

### 7.1 纪律门

```powershell
cd F:\RustProjects\godot-mcp-pro\code\godot
git diff --stat -- modules/mcp_server/tools modules/mcp_server/tests   # 期望：空
cd modules\mcp_server
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp061_watch_evidence.ps1   # 期望：EVIDENCE_OK scenarios=5，exit 0
```

### 7.2 `-StaleSec` 依据（第 1 轮真实追踪的最大 run 内间隔）

```powershell
$rows = Get-Content modules\mcp_server\docs\reports\evidence\racing\CALL-LOG.jsonl | ForEach-Object { $_ | ConvertFrom-Json }
$max=0; foreach($g in ($rows | Group-Object run)){ $s=$g.Group|Sort-Object seq
  for($i=1;$i -lt $s.Count;$i++){ $d=([datetime]::ParseExact($s[$i].ts,'HH:mm:ss.fff',$null)-[datetime]::ParseExact($s[$i-1].ts,'HH:mm:ss.fff',$null)).TotalSeconds
    if($d -gt $max){$max=$d} } }
"max_intra_run_gap_sec=$max"   # 实测：92.235
```

---

## 8. 提交与锚点（D86）

- `base anchor`：`0a9fc1d466`（本轮开工时的 HEAD；本报告 §3.4/§3.5/§3.6 的**全部实测**证据在此基线上产生）
- **本批提交**（英文提交信息）：

| 提交 | sha | 内容 |
|---|---|---|
| A（实现 + 证据 + 本报告） | **`ea345b51dff9565d7aa91e1676175621891655f5`**（**本报告无法包含自己的 sha**：A 同时包含本报告，写进去就改了自己的 blob；因此 A 锚点由提交 B 回填，B 的内容是「A 的 sha」这一行的加入） | `mcp: deterministic watcher + machine-checkable stop reasons (TASK-061)`；含两个脚本、TASK-060 改写、`evidence/task061/**`（含 `-f` 强加的 8 个 `*.log`）与本报告 |
| B（回填锚点，只改本节） | 见 `git log --format=%H -1 -- modules/mcp_server/docs/reports/REPORT-061-observer-watcher.md` | 只把 A 的 sha 写进本表 |

> 复算：`git show --stat <A>` 应列出 `mcp_watch_run.ps1`、`mcp061_watch_evidence.ps1`、
> `TASK-060-breakout-round-2.md`、本报告与 `evidence/task061/**`；
> `git show --stat <A> -- modules/mcp_server/tools modules/mcp_server/tests` **为空**（已实测）。

- **D86 复测声明**：本报告引用的**唯一**外部数字是第 1 轮 `CALL-LOG.jsonl` 的 92.235 s 最大 run 内间隔
  （来源：`docs/reports/evidence/racing/CALL-LOG.jsonl`，**本轮当场复算**，命令见 §7.2）；
  该文件的行数/内容在本轮未改动（`git status` 未列出它）。第 2 轮 `watch.log` 与 `watch.ps1` 的引用
  均为**仓库内原物当场读取**（sha256 见 §3.5 的 `original_sha256`）。

---

## 9. 缺陷与风险登记（诚实清单）

### 9.1 本轮发现的缺陷（不在本批范围内，报给决策者）

- **D-061-1（medium，流程/可追溯性）**：第 2 轮 TASK-060 的产物写在**仓库根的未跟踪目录** `docs/`
  （`git status` 显示 `?? docs/`），而 TASK-060 的规范路径按 `modules/mcp_server/docs/reports/` 应为**已跟踪**
  目录（对照：`modules/mcp_server/docs/reports/evidence/` 是 tracked）。**实测**：`modules/mcp_server/docs/reports/`
  下**没有**任何 `BREAKOUT-*` 文件，根 `docs/reports/` 下有 3 份报告 + `evidence/task060/**`；
  PLAYBOOK §5 的「既有未跟踪物」清单里也**没有** `docs/`（清单是 `.graphifyignore`、`build-m0.cmd`、
  `graphify-out/`、`install-deps-m0.cmd`）。后果：**第 2 轮的全部证据没有提交锚点**，D86 要求的
  「引用别处结论须标提交锚点」在这些产物上**无法满足**（观察者报告里写的 `4f99a4e37ac...` 锚点是**追踪的构建**，
  不是产物自身的锚点）。→ 建议：把 `docs/reports/**` 归位到 `modules/mcp_server/docs/reports/`（或明确允许根 `docs/`），
  这是**决策者的裁决项**，本批**不擅自移动**（动了会改变第 2 轮证据的可追溯位置）。
- 附带**实测**事实：第 2 轮 `watch.log`（根 `docs/.../c-obs/watch.log`）末行是
  `t+1505s ... BUDGET_REACHED traces=1`，全文无 `stop_reason` —— 与本报告 §3.5(b) 在临时副本上**复现**的
  静默结束形态一致（同一脚本、同一语义）。
- **D-061-2（low→**已在本批内处置**，但仍是流程陷阱）**：`.gitignore:308` 有 `*.log`，因此
  「把 `watch.log` 复制进仓库」（TASK-060 §C 的强制动作）会**静默失败**——`git add` 跳过它且**不报错**，
  只有 `git status --ignored` 才显示 `!!`。**实测**：本批 8 个 `watch.log` 全部落在忽略名单里
  （`git check-ignore -v` = `.gitignore:308:*.log`）。**处置**：本批用 `git add -f` 把它们**强制纳入**提交
  （见 §8 的文件清单），并在 TASK-060 §C 加了一条显式陷阱说明。
  → 这类「证据没进仓库而没人发现」正是第 2 轮产物无法带锚点的同一类问题，建议在 PLAYBOOK 里登记。
- **D-061-3（low，**已在本批内处置**）**：`.gitattributes` 的 `* text=auto eol=lf` 会让**CRLF 工作区**
  与**LF 提交**的字节不同，于是「贴出来的 sha256 校验不过」（**实测**：`s1-marker/watch.log`
  工作区 1538 → blob 1525 字节）。→ 已把全部证据改成只写 LF 并重新生成，判据与命令见 §6.5。

### 9.2 本批实现自身的残余风险

- **R-061-1（low）**：`seq` 用「行内第一个 `"seq"` 匹配」取得；请求的 `id` 是**逐字**拼入的
  （`mcp_trace.cpp:346-363`），一个刻意构造的 `id` 可污染首个匹配。自用链路风险低；若未来要抵御，
  应对 `id` 做 JSON 类型/内容校验后再取 `seq`。
- **R-061-2（low）**：`stale` 的「先有活动」策略是对任务书字面语义的**收紧**（§3.2 决策 3）。
  已在脚本头、`watch.log` 每行（`stale_ok`）与 TASK-060 §0 第 8 条**三处显式声明**，不隐藏。
- **R-061-3（low）**：超时不是精确时刻（上界 `TimeoutSec + IntervalSec`）。已写入契约与 TASK-060 §0 第 8 条。
- **R-061-4（low）**：单轮最多读 8 MiB；极大追踪的行数/`seq` 会**滞后**到下一轮。不影响停止理由的正确性
  （停止理由只看「有没有新行」与耗时），但是 `last_seq` 的**读取延迟**，写进契约。
- **R-061-5（low）**：`.ps1` 的 ASCII 纪律意味着**无法**在脚本内写中文诊断；因此所有诊断字段都是
  `snake_case` 的机器可读键值（这同时也是要求 2「机器可核对」的正面选择）。

### 9.3 `deviations`（与手册/任务书的偏离，逐条显式）

1. **`stale` 需先有活动**（R-061-2）：任务书字面是「`StaleSec` 内无新行 = stale」；as-built 收紧为
   「有活动之后才可 stale」。理由：逐字执行会把「开发者尚未开工」判成「卡死」，让观察者再次早退。
2. **`-StaleSec` 默认值 0（关闭）**：任务书只给了 `-IntervalSec` 的默认值（30）；`StaleSec` 未给默认，
   as-built 取 `0=关闭` 并在头部与日志注明。§C 的命令行**显式**传 `300`。
3. **`-Marker`/`-TracePath`/`-TimeoutSec`/`-OutDir` 设为 Mandatory**：任务书未说必填性；设为必填
   可以避免「忘了传 marker → 永远等不到 marker」这类**静默**协议错误（缺参在 PowerShell 里**立即报错**）。
4. **退出码 2 的存在**：任务书只说三种理由 exit 0；as-built 为 usage/setup 错误保留 exit 2，
   并在头部与 §3.1 声明「2 不是停止理由」。
5. **多写两个文件**（`watch-summary.json`/`watch-summary.txt`）：任务书要求「结束时打印并写文件」，
   未指定文件名/格式；as-built 同时给 JSON（机器读）与 key=value（人读/grep）。
6. **多写一个脚本** `scripts/mcp061_watch_evidence.ps1`：任务书只要求新增 watcher；
   证据生成器是**可复跑**的必需项（否则 §2.1/§2.2 的演示无法被独立验收复现）。它只写 `%TEMP%` 与 `docs/reports/evidence/`。
7. **§C 标题措辞 `不阻塞` → `不打断开发者`**：任务书要求「改写 §0/§C/§D」；原措辞与「观察者必须阻塞」
   直接冲突，属必须消除的歧义（根因③）。

### 9.4 `blockers`

**无**。（本批不需要起引擎、不需要网络；未触碰 9877；四道门中与本批相关的两道
——「只改 scripts/docs」与「脚本纯 ASCII/parse 0」——**已实测通过**；模块 doctest/契约门
**与本批无关**，因为 `tools/**`、`tests/**`、契约**零改动**，故**未运行**——这是**显式声明**而不是遗漏。）

### 9.5 `next_step_recommendation`

1. **决策者裁决 D-061-1**（第 2 轮产物落在未跟踪的根 `docs/`）：归位或明确允许，并为 TASK-060 产物补锚点。
2. **TASK-060 第 3 轮开跑时按新 §C 执行**；`§D` 必须交回「`stop_reason` 逐项对账」的结果。
3. 后续若有**第二个确定性等待**的需求（例如等某个产物），优先复用 `mcp_watch_run.ps1` 的
   「行数 + 偏移 + 机器可读理由」骨架，而不是再写一个 sleep 循环。
4. 把 §5 的教训写进 PLAYBOOK：「单调计数器（行数）与读位点（offset）是两套状态，必须分别出反例」。

---

## 10. 返回给决策者（≤8 行）

见本次委派的返回值（`stop_reason` 三类演示 + 反例 + 门结果 + 本报告路径）。
