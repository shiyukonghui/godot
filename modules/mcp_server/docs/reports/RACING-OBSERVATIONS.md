# RACING-OBSERVATIONS — TASK-039 §C 观察者产物（边观察边追加）

> **角色**：只读、并行、不阻塞的观察者。不修改 scratch 工程、不打断开发者进程、不占用其端口。
> **观察主源**：`%TEMP%\mcp-racing-test\trace-editor.jsonl` 与 `trace-game.jsonl`（服务端真实事实）。
> **产出纪律**：每条记录含 `序号 / 时间(追踪 ts_ms+seq+文件) / 调用序列 / 事实 / 归类 / 证据 / 建议`；
> 区分【实测】与【推断】；D86：标测自提交。

---

## 0. 观察会话锚点（D86）与启动时状态

| 项 | 值 | 来源 |
|---|---|---|
| 观察开始（本地时间） | `2026-09-23 22:44:03` | `Get-Date`【实测】 |
| 仓库 / 分支 | `F:\RustProjects\godot-mcp-pro\code\godot` / `feature/mcp-server-module` | 【实测】 |
| HEAD（完整 sha） | `f34ee937f3d31c49ac42081bb91433c5fc5b36e3` | `git rev-parse HEAD`【实测】 |
| 短 sha | `f34ee937f3` | `git rev-parse --short HEAD`【实测】 |
| 模块树干净？ | **空**（`git status --short modules/mcp_server/tools modules/mcp_server/tests` 无输出） | 【实测】22:44 |
| 9877（用户 Godot） | `TCP 127.0.0.1:9877 LISTENING PID 76048` | `netstat -ano`【实测】22:44 |
| 9888 / 9889 | **未监听**（观察开始时开发者进程尚未启动） | `netstat -ano`【实测】22:44 |
| scratch 工程目录 | `%TEMP%\mcp-racing-test\` **不存在** | `dir`【实测】22:44 |
| `RACING-TEST-PLAN.md`（§A） | 存在 | 【实测】 |
| `RACING-DEV-LOG.md`（§B） | **不存在** | 【实测】22:44 |
| 预算 | 总 45 分钟（至 `2026-09-23 23:29` 左右）或 `DEV-DONE.marker` 出现 | 任务书 §C.3 |

**纪律确认（本次会话）**：观察期间**未**修改 `modules/mcp_server/**` 任何实现；**未**触碰 9877；
**未**启动任何引擎进程；**未**写入 scratch 工程目录。只读探测仅经第二条 MCP 连接（若可用）。

---

## 1. 观察日志（append-only）

> 初始无既存追踪文件，故第 1 条起为「空转期」记录，用于证明观察窗口已覆盖开发者开工前的时间。

### OBS-001 / 空转期（无任何 MCP 流量）：开发者开工前的 10 分钟

| 项 | 内容 |
|---|---|
| 时间 | 本地 `22:44:03 → 22:54:33`（**追踪 ts_ms 不存在**，因为 `trace-editor.jsonl` / `trace-game.jsonl` 尚未创建） |
| 调用序列 | **无**（`tools/call` 记录数 = 0；9888/9889 从未监听） |
| 事实 | 观察开始 → 22:45:59 期间 `%TEMP%\mcp-racing-test\` **不存在**；22:45:59 出现 `project.godot`（104 B），此后 9 分钟内该目录**只有这一个文件**（`Get-ChildItem -Recurse -Force` 只回一行）。整个窗口内 **9888/9889 未监听**、无 `godot.windows.editor.*` 进程，只有用户 Godot（pid 76048 @9877）。 |
| 归类 | **D（可优化/流程）**，非 A 类异常 —— 不能算开发者失误，只能说明「开工前置成本高」 |
| 证据 | `netstat -ano` 每 50-60 s 采样 7 次（22:44 / 22:45:59 / 22:46:54 / 22:49:37 / 22:50:54 / 22:51:53 / 22:52:59 / 22:54:33），9877 恒为 `PID 76048`、9888/9889 恒无；`Get-ChildItem -Recurse -Force` 输出仅 `project.godot 104` |
| 实测/推断 | **实测**（端口、文件、进程列表）。「开发者在重建二进制」为**推断** |
| 推断依据 | `bin\godot.windows.editor.x86_64.mono.console.exe` 与 `mono.exe` 的 `LastWriteTime` = **22:47:52 / 22:47:53**，晚于观察开始（22:44）→ 该窗口内发生过一次构建/拷贝产物落盘。`PLAYBOOK §3`（R-1、D62）要求「开跑门前先重建并校验 `--version` hash 前缀 == `git rev-parse --short HEAD`」，与此时序吻合。 |
| 建议 | 试测「首次 MCP 调用前的固定成本」应在汇总里单列（本会话观测到 **≥10 分钟零流量**）；若下一步确认是重建，建议在任务书里给出「复用已有二进制」的判据以缩短观察窗口。 |

> **对 §A 计划的核对**：`RACING-TEST-PLAN.md §2.5` 把「启动编辑器进程」列为**环境准备（非 MCP 调用）**，
> 因此启动进程本身**不会**进 trace。这也是本报告在 trace 出现前只能靠端口/进程/文件系统取证的原因。

---

### OBS-002 / 连接就绪探测：`initialize` 连打 3 次才拿到响应（第 3 次才成为 trace 的 seq=1）

| 项 | 内容 |
|---|---|
| 时间 | 请求落盘本地 `22:55:34.340` / `22:55:37.437` / `22:55:40.527`；成功响应 `22:55:40.553`。**追踪 ts_ms**：仅第 3 次有记录 = `2283107` → 实际 `1790175340552`（= 本地 `22:55:40.552`），`trace-editor.jsonl` 行 1，`seq=1`，`method=initialize`，`ok=true`，`result_bytes=184`，`duration_ms=0` |
| 调用序列 | ① `initialize{id:1001,params:{}}` @22:55:34.340 → **无响应文件、无 trace 行** ② `initialize{id:1002,params:{}}` @22:55:37.437 → **无响应文件、无 trace 行** ③ `initialize{id:1003,params:{}}` @22:55:40.527 → `ok:true`，`result_bytes=184` |
| 事实 | 同一 `tools/call` 前身（`initialize`）**连续 2 次得不到任何服务端记录**，第 3 次成功。编辑器进程在 `22:55:34.290` 已写出 `editor.err.log`/`editor.pid`，但服务端直到 `22:55:39.792` 才把「已监听」写入 `editor.out.log`（`[MCP] listening on 127.0.0.1:9888 (editor=true, tools=148)`），trace 首行的 `ts_ms` 正好落在其后 0.76 s。 |
| 归类 | **D（可优化 / 就绪性）**，**不是 A6** —— 见下方「为什么不记成 A6」 |
| 证据 | 请求体 sha256：`0001` = `5E5657B46143AD2E0E275335AAF68705824B0435BC86070661B7B436A73D9D65`，`0003` = `5F9B1DA44582FC6CE5B5296FBF099BD7198A37197A87F1242B82AFC5CB5B4079`；响应体 `0003` = `7FD5CC9071268E6B37E74CFFB34B...`（全串 `7FD5CC9071268E6B37E74CFFB35C8CD48B3E7EA5F0AF332EDAB0C5C9BD5C8C39`）。文件时间戳逐条见 `Get-ChildItem -Recurse`（`editor.pid` 22:55:34.301；`editor.out.log` 22:55:39.792；`trace-editor.jsonl` 22:55:40.552）。**错误码：不存在**（无服务端记录，故没有 `error_code`）。`editor.err.log` = 0 字节。 |
| 实测/推断 | 「前 2 次是**连接层**失败（编辑器尚未监听）」= **实测**（服务端零记录 + 监听日志晚于请求 5.4 s）。「curl 收到 ECONNREFUSED」= **推断**（客户端错误未落盘，本报告不编造错误码） |
| **为什么不记成 A6** | `§A §4.1 A6` 的机器判据要求 trace 里出现 `ok:false` 且**有 error_code** 的失败行。本实例**服务端从未收到请求**，因此 `trace-editor.jsonl` 里 `ok:false` 行数 = **0**。若按 §A 误记，会让 §D 无法在 trace 原文复核。**结论：这是环境就绪摩擦，不足以判工具缺陷。** |
| 建议 | 就绪性可观测性缺失：调用方只能盲重试。建议（最小改动）①启动日志/落盘一个 `ready` 标记文件或把端口**先绑后加载**，让「未就绪」与「端口/端点错」可区分；②在 `--mcp-port` 启动路径上，`connection refused` 与 `-32601` 是两种完全不同的自纠信号，文档应显式区分。**不建议**为此新增 MCP 工具（MCP 层不可用时无法用 MCP 自答）。 |

---

### OBS-003 / **【高价值】编辑器角色默认端口 = 9877：任何 `--import` 都会尝试抢占用户 Godot 的端口**

| 项 | 内容 |
|---|---|
| 时间 | 导入尝试 1 `22:55:25.750`（`import.attempt1.log`，3826 B）；导入尝试 2 `22:55:33.573`（`import.attempt2.log`，3616 B） |
| 调用序列 | **无 MCP 调用**（这是开发者的**回退/环境准备**步骤）。命令形如 `b1_bootstrap.ps1:93`：`& $Engine --headless --path $Proj --import`（**未传** `--mcp-port`） |
| 事实 | 两次导入的服务端日志**逐字相同**地出现：`[MCP] role=editor configured_port=9877 source=default listen=true` → `[MCP] bind failed on 127.0.0.1:9877 (error=22)` → `WARNING: [MCP] bind failed on 127.0.0.1:9877; MCP server disabled` → `[MCP] get_port()=0 (MCP server disabled)`。即：**只要不显式给 `--mcp-port`，编辑器角色的默认监听端口就是 9877**，`--import` 这种纯离线导入也会尝试绑定它。本次只是因为**用户 Godot 正占着 9877**（`PID 76048`）才 `error=22` 失败，从而「碰巧」没占到。 |
| 归类 | **A（异常 / 风险）** —— 具体是「默认行为与纪律冲突」型；不是 E-1..E-7 预登记项 |
| 证据 | `import.attempt1.log` sha256 `90AAFEDB75F415F8AE1C8F6DC9A9942E842C718E928391B5CB19C4EF9220A7F6`；`import.attempt2.log` sha256 `3F77BA2C327A8E9F7021A51E79FE1A70F986999D2EC046A0F05F1B531AB190BF`。关键 5 行在两份日志中均存在（上表逐字引用）。源码锚点：`modules\mcp_server\mcp_server.cpp:517`（`MCPServer::_start_service`，由引擎自身栈回溯给出）。`9877` 占用者 `PID 76048`（`netstat -ano`【实测】）。 |
| 实测/推断 | 「无 `--mcp-port` 时编辑器默认端口 = 9877，且 `--import` 也会尝试绑定」= **实测**（两份独立日志）。「若用户 Godot 未运行，则 `--import` 会**真的**绑定 9877 并占用它直到进程退出」= **推断**（因本次被占用而未发生；`.ps1` 纪律禁止我为了复现而停掉用户 Godot，故**不做该复现**）。 |
| 风险 | 严重度 **high（纪律级）**：`§A §5.1`／任务书要求「绝不占用 9877」，但**默认配置**在「用户没开 Godot」时会自动占用。任何 `--import`/`--test`/`--headless` 批量脚本都可能静默抢走用户端口；且日志只说 `bind failed`，**不说「默认值可能就是你不想要的端口」**。 |
| 建议 | ①默认值不应落在用户日常端口上：编辑器角色在**非交互/批处理**场景（`--import`、`--test`、`--headless`）应默认 **不监听**（`listen=false`），或默认端口改为非 9877 的高位端口；②若必须保留 9877，至少在 `--import`/`--test` 路径打印 `data.suggestion` 级提示（「默认端口 9877 属用户日常端口，批处理请显式 `--mcp-port=<n>` 或 `--mcp-port=0`」）；③补充：`import.attempt1.log` 末尾还有 `ERROR: Parameter "singleton" is null. at: EditorNode::is_cmdline_mode (editor\editor_node.cpp:6732)`，attempt2 **没有**该行 → 两次导入的**退出路径不同**，值得 §D 关注（本报告不臆断其与本模块的因果关系）。 |
| 复现要求 | 按 §A A 类「相同 args 再调一次」→ **已天然复现 2 次**（attempt1/attempt2 同现象）。**未**在「9877 空闲」条件下复现（纪律禁止）。 |

---

### OBS-004 / **环境突变：用户 Godot（PID 76048）已退出，9877 变为空闲 → OBS-003 的推断进入「可实测」状态**

| 项 | 内容 |
|---|---|
| 时间 | 本地 `22:58:15`（上一条 OBS-003 写于 `22:57` 前后） |
| 调用序列 | 无 MCP 调用（纯环境观测） |
| 事实 | ①`netstat -ano \| findstr :9877` **无任何输出**（连 TIME_WAIT 都没有）→ 9877 **不再被监听**；②`tasklist /fi "PID eq 76048"` → `INFO: No tasks are running which match the specified criteria.` → **用户 Godot 进程 76048 已退出**；③当前 `tasklist \| findstr /i godot` 只剩**两个**进程：`godot.windows.editor.x86_64.mono`（`PID 70384`，开发者的 9888 编辑器）与 `...mono.console`（`PID 75580`，其控制台壳）；④`netstat` 确认 **9888 归 70384**，**不是** 9877。 |
| 归类 | **环境变更（非缺陷）**，但它**升级了 OBS-003 的风险等级**：风险从「被占用所以碰巧没发生」变成「入口已打开」 |
| 证据 | 三次独立命令输出（`netstat`、`tasklist /fi`、`tasklist \| findstr`）见本节命令；与 `§0` 表中 `22:44` 的 `9877 LISTENING PID 76048` 形成**前后对照** |
| 实测/推断 | **实测**：用户 Godot 已退出、9877 空闲、开发者编辑器只占 9888。「用户是主动关闭还是崩溃」= **未知，不推断**。**未**由本观察者造成（观察者全程只跑 `netstat`/`tasklist`/`Get-ChildItem`/`Get-FileHash`/`Get-Content`，**未启动/杀死任何进程**）。 |
| 风险（升级） | 由 OBS-003：从现在起，**任何**不带 `--mcp-port` 的编辑器/headless 启动（尤其 `--import`、`--test`、`dotnet` 后的引擎调用）都会**成功**绑定 9877，并持续占用到进程退出 —— 即「默认端口」会真的撞上用户日常端口，而不是像 22:55 那样被 `error=22` 挡住。 |
| 建议 | 与 OBS-003 同（默认不监听 / 换默认端口 / 至少给 suggestion）。**给编排者**：若后续要判定「9877 是否被开发者占用」，判据是 `netstat -ano \| findstr :9877` 的 **PID 是否属于 `godot.windows.editor.*`（开发者）**，而不是「9877 是否有监听」——用户自己关闭后，9877 空闲本身就是正常状态。 |
| 持续观察承诺 | 后续每轮轮询都会记录 9877 的 **PID 归属**（不只是有无监听），一旦发现 9877 被开发者进程绑定，立即按 A 类异常记录并附 PID + 启动命令证据。 |

---

### OBS-005 / **【取证级异常】编辑器重启会「清掉」同一路径的旧追踪：`trace-editor.jsonl` 里的 `seq=1` 记录被另一条记录替换**

| 项 | 内容 |
|---|---|
| 时间 | 旧记录 `ts_ms=1790175340552`（本地 `22:55:40.552`）；新记录 `ts_ms=1790175751840`（本地 `23:02:31.840`） |
| 调用序列 | 无 MCP **新工具**调用；这是**同一路径追踪文件的跨进程行为** |
| 事实 | ①`22:55:40.552` 我在 `trace-editor.jsonl`（第 1 行）读到：`{"id":1003,"seq":1,"method":"initialize","ok":true,"result_bytes":184,...}`；②`23:00–23:02` 之间编辑器进程 `70384` 退出、新编辑器 `72876` 启动；③`23:03` 再读**同一文件**，内容只剩 1 行且**已变成** `{"id":1002,"seq":1,"method":"initialize","ok":true,...,"ts_ms":1790175751840}` —— **旧记录不见了**；④`Get-Item` 显示 `CreationTime=22:55:39`（**文件未被重建**）、`LastWriteTime=23:02:31`、`Length=190`。 |
| 归类 | **A（异常）—— 静默证据丢失 / 与「追踪=服务端真实事实」的取证用途冲突**。附带的次生事实：**`seq` 是「每进程从 1 开始」，不是全局单调**。 |
| 证据 | 旧记录全文（本报告已在上文逐字引用）：`{"id":1003,"connection":1,"duration_ms":0,"error_code":0,"error_message":"","error_message_truncated":false,"method":"initialize","ok":true,"result_bytes":184,"seq":1,"ts_ms":1790175340552}`；新记录全文：`{"id":1002,"connection":1,"duration_ms":0,"error_code":0,"error_message":"","error_message_truncated":false,"method":"initialize","ok":true,"result_bytes":184,"seq":1,"ts_ms":1790175751840}`。二者 `id`（1003 vs 1002）、`ts_ms`（相差 411 288 ms）均不同，`seq` 均为 1。文件 `CreationTime=2026/9/23 22:55:39`（`Get-Item` 实测）。 |
| 实测/推断 | **实测**：旧记录消失、文件未被重建（CreationTime 不变）、`seq` 重新从 1 开始。「写入端以 `O_TRUNC`（或等价的清空语义）打开该路径」= **推断**（合理且与观测一致；我没有读 `mcp_trace.cpp` 的写入实现来断言——若要坐实需 §D 或后续批次读源码）。 |
| **未对上的观测（如实记录，不掩盖）** | `23:02:41` 的那次轮询把该文件报为 **`0` 字节**，但同一文件在 `23:03` 读为 `190` 字节且 `LastWriteTime=23:02:31`（**早于** 23:02:41）。这两个数据**互相矛盾，我无法调和**：若 23:02:31 之后再无人写该文件，23:02:41 不应看到 0 字节。**可能解释（均为推断，未证实）**：目录项大小缓存瞬时未刷新；或该路径在 23:02:41 被**另一次**截断后又被写回。**我选择同时保留两次观测并标注矛盾，而不是挑一个好看的说法。** |
| 影响 | ①§D 被要求「回到追踪原文核对」时，**同一路径的早期记录可能已经不存在**（本会话已实际发生一次）；②`seq` 每进程重置 ⇒ §D 若只按 `seq` 定位会串号，必须用 `(文件, seq, ts_ms)` 三元组或文件 sha256；③§C 自己的「用 seq 断段、别重复读旧行」在**重启后失效**（offset 会指到不同记录上）。 |
| 建议 | ①`--mcp-trace` 改为**追加**（或写到 `<path>.<pid>` / 轮转），至少**首行写一条 `{"event":"trace_opened","truncated":true,"pid":...}`** 让丢失可被发现；②若保留截断语义，请在启动日志那行 `[MCP] trace enabled: file=...` 里**显式加 `(truncating)`**；③文档里写明 `seq` 是**进程内**序号。**对 §D 的直接提醒**：本会话的编辑器追踪**至少经历过一次替换**，`trace-editor.jsonl` **不是**完整历史。 |

---

### OBS-006 / 就绪探测摩擦**第二次发生**（编辑器第二次启动）：2 次 `initialize` 才成功

| 项 | 内容 |
|---|---|
| 时间 | 尝试 A `23:02:27`（`calls\0001-raw-initialize.req.json`，无 res）；尝试 B `23:02:30`（`calls\0002-raw-initialize.req.json`）→ 响应 `calls\0002-raw-initialize.res.json` `23:02:31`；追踪 `seq=1` `ts_ms=1790175751840` = `23:02:31.840` |
| 调用序列 | ① `initialize{id:1001}` @23:02:27 → 无响应文件、**无 trace 行** ② `initialize{id:1002}` @23:02:30 → `ok:true`，`result_bytes=184` |
| 事实 | 与 OBS-002 **同型现象再次出现**（第 2 次编辑器启动）：成功前的那次 `initialize` **服务端零记录**。两次启动合计：**5 次** `initialize` 里 **3 次**没有任何服务端痕迹。 |
| 归类 | **D（可优化 / 就绪性）**，与 OBS-002 同一条结论；此处作为**独立复现**（§A A 类要求「异常需按相同 args 复现一次」，本项虽非 A 类，但已自然复现）。 |
| 证据 | `calls\` 目录原始时间戳（`Get-ChildItem` 实测）：`0001-raw-initialize.req.json` 61 B @`23:02:27`；`0002-...req.json` 61 B @`23:02:30`；`0002-...res.json` 184 B @`23:02:31`；**同时**仍留有**上一轮**的 `0003-...req/res.json` @`22:55:40`（说明目录**未被清理**，是客户端的编号从 0001 重新开始 → 旧文件被**覆盖**风险真实存在）。追踪新记录：`ts_ms=1790175751840`。 |
| 实测/推断 | **实测**（文件时间戳 + 追踪 ts）。「失败尝试是连接层 ECONNREFUSED」= **推断**（无客户端错误码落盘；服务端无记录是硬事实）。 |
| 附带发现（**可合并/可优化**） | 开发者自建证据目录 `calls\` 采用**顺序编号**，且**重启后从 0001 重新开始** → 上一轮的 `0001/0002` 会被本轮**无声覆盖**（本会话中 `0001`、`0002` 的时间戳已从 22:55 变为 23:02，而 `0003` 仍是 22:55）。这不是模块缺陷，但它**放大**了 OBS-005 的证据丢失风险。建议 §B 的证据文件名带**运行标识**（如 `r2-0001-...`）。 |
| 建议 | 同 OBS-002：给调用方一个可判定的「已就绪」信号，而不是盲重试。 |

---

### OBS-007 / 开发者工作区时间线：**C# 脚本在首次 MCP 连接之前就已手写落盘**

| 项 | 内容 |
|---|---|
| 时间 | `Car.cs` `22:53:38.658`；`Checkpoint.cs` `22:53:38.666`；`LapTimer.cs` `22:53:53.740`；`Hud.cs` `22:53:53.749`；`ChaseCamera.cs` `22:54:00.345`；`Main.cs` `22:54:00.353`；`rlog.ps1` `22:54:30.539`；`b1_bootstrap.ps1` `22:55:00.793`。**首次成功的 MCP 响应在 `22:55:40.553`**（OBS-002 的 `0003`） |
| 调用序列 | **无**（这些文件早于任何服务端可记录的调用） |
| 事实 | 6 个 C# 脚本 + 2 个 PS 助手**全部**写于**首次 MCP 响应之前 ≥37 秒～2 分钟**。即：至少**脚本正文的创作**不是经 MCP 工具完成的（`trace-editor.jsonl` 在此期间**不存在**）。工作区在 `%TEMP%\mcp-racing-src\`。 |
| 归类 | **B（缺失工具）候选线索** —— 但**证据强度不足以单独定案**，故此处只登记「线索 + 需要的补证」 |
| 证据 | `Get-ChildItem` 全量时间戳（上表逐字）；对照 `calls\0003-raw-initialize.res.json` 时间戳 `22:55:40.553` 与 `trace-editor.jsonl` 首行 `ts_ms`。契约侧对照（`docs\tools_list.renamed.json` 行 1356-1376 / 1378-1401）：`project_create_script{path,content,template:="Node"}`、`project_edit_script{path,content,search,replace}` **都带 `content` 参数**，理论上可以写任意文本（含 `.cs`）。 |
| 实测/推断 | **实测**：文件时间线。**推断**：开发者选择手写（或改用文本编辑器）而非工具。**尚未证实**：这些内容**能否**由 `project_create_script` 成功写入 `.cs`（本观察未调用该工具，因为**写工具会改动 scratch 工程**，违反 §C 只读纪律）。 |
| 为什么不能就此判「缺失工具」 | ①`project_create_script` 有 `content`，未必拒绝 `.cs`；②「手写大段源码」也可能只是**D 类手感问题**（把 5 KB C# 塞进一个 JSON 字符串参数），而非「没有工具能做」；③§B 的 `RACING-DEV-LOG.md` **尚不存在**，无法确认开发者是否**试过并失败**。 |
| 需要的补证（给 §D 的具体动作） | ①读 `RACING-DEV-LOG.md` 看是否有 `project_create_script`/`project_edit_script` 的尝试与错误码；②在**独立 scratch 工程**里对 `.cs` 调一次 `project_create_script`（编辑者侧，9888），看返回；③若返回成功 → 降级为 **D 类手感问题**；若 `-32001`/`-32602` → 升级为 **B 类缺失工具**。**这三步都不应在本试测的只读观察里做**（会写工程）。 |
| 建议（若最终确认） | 若 `.cs` 不被支持：`project_create_script` 的 `template` 默认 `"Node"` 暗示**它面向 GDScript**；建议加 `language`（`gd`/`cs`）或明确支持按扩展名分流模板，并在错误里给出 `data.suggestion`（「C# 需用 `template:"CSharpScript"`」之类），否则调用方无法自纠。 |
| **勘误（append-only，`PLAYBOOK §7.3`）** | 本条的「B 缺失工具候选」**已被后续追踪降级/推翻**：`seq=27..32` 有 **6 次 `project_create_script` 全部 `ok=true`**，且其 `args_bytes` = `5240, 1151, 2932, 3176, 1061, 1550`，与 6 个 C# 脚本的体量吻合（`seq=27` 的 args 中可见 `"content":"using Godot;\\n\\n// TASK-039 section B racing car...public partial class Car : CharacterBody2D..."`，且 `args_truncated=True`）。⇒ **`.cs` 是可以经 `project_create_script` 写入的，工具并不缺失**。早前的「手写时间线」只说明开发者在**首次连通之前**先在 `%TEMP%\mcp-racing-src\` 起草了内容，随后**用工具写入工程**——这是**正常的工作方式**，不是回退。**本条撤回「缺失工具」定性**，仅保留其方法论价值（时间线对照）。另：`project_validate_script` 对 `res://scripts/Car.cs` 共调用 **7 次**（`seq 36,83,121,127..132`）**全部 `ok=true`**（`rb` 171-179 B）⇒ §A AC-2 关心的「`.cs` 能否被校验」实测**可以**。 |

---

## 2. 主观察期（`trace-editor.jsonl` 第 2 代文件，`seq 1..205`）

> **观测窗口**：编辑器第二次启动 `23:02:31` → `23:11:51`（最后一条 `seq=205`）。共 **205** 条记录 = 1 `initialize` + 204 `tools/call`；**失败 25**（+3 在……见下）→ 精确计数见 §3。
> **追踪 sha256**：`trace-editor.jsonl` 在 `23:19` 时的文件 sha256 未固化（文件仍在增长），故本报告一律以 **`(seq, ts_ms)` 定位**，并提供**我自己的只读探测响应 sha256** 作为不可变锚点。

### OBS-008 / **A6#1（最强）：`editor_add_nodes_batch` 无法「一次性建出父子」——24 节点单次批处理在 `nodes[1]` 就失败**

| 项 | 内容 |
|---|---|
| 时间 | `seq=10`，`ts_ms=1790175808839`（本地 `23:03:28.839`） |
| 调用序列 | `project_get_info`(2) → `project_get_settings`(3) → `project_get_filesystem_tree`(4) → `project_search_file_names`(5) → `project_search_file_contents`(6) → `project_create_scene_file`(7) → `editor_open_scene`(8) → `editor_get_scene_tree`(9) → **`editor_add_nodes_batch`(10) ❌** |
| 事实 | 请求体是一个**父先于子**排列的 24 节点数组（`nodes[0]={name:"Track",parent_path:"."}`，`nodes[1]={name:"Road",parent_path:"Track"}`，…，`nodes[24]={name:"StartButton",parent_path:"HUD"}`，`args_bytes=1507`）。服务端在 **`nodes[1]`** 处拒绝：`nodes[1]: parent 'Track' not found`（`-32001`）。**`Track` 就是同一请求的 `nodes[0]`** ⇒ 父路径是在**请求开始前的树**上解析的，**同一批内新建的父节点对后续元素不可见**。 |
| 归类 | **A（异常/能力缺陷）**：名字与描述承诺「批量」，最自然的用法（声明一棵子树）恰好是它做不到的。同时命中 **D5**（见 OBS-009） |
| 证据 | `seq=10` 全文：`error_code=-32001`、`error_message="nodes[1]: parent 'Track' not found"`、`args_bytes=1507`、`args_truncated=False`、`result_bytes=603`、`duration_ms=0`。**参数全文已在本报告 OBS-008 引用**（24 元素，父子顺序可逐项核对）。契约原文（`docs/tools_list.renamed.json` 行 **1645-1683**）：`description="批量添加节点到场景"`，`nodes[].parent_path.description="父节点路径，默认 \".\""` —— **未提及**「父必须已存在」「不接受同批内新建的父」 |
| 实测/推断 | **实测**（请求参数 + 错误消息 + 索引全部在案）。「引擎一次调用本可做到」：`Node::add_child` 在循环里顺序执行即可支持同批父子，故这是**实现选择**而非引擎限制 —— 此句为**推断**（未读 `editor_add_nodes_batch` 实现源码） |
| 建议 | ①按数组顺序**边建边注册**（父先于子时允许同批），或②拓扑排序后分批执行，或③至少把 `parent_path` 的语义写进描述并在错误里给出 `data.suggestion`（「父节点 'Track' 尚不存在；请先单独创建父节点，或把父节点放在同一数组的更前面并由本工具按序解析」）。**签名草案**：`editor_add_nodes_batch{nodes:[{type,name,parent_path,properties}], resolve_within_batch?:boolean=true}` |

### OBS-009 / **A6#1 的后续：调用方用 4 次批处理「按深度手工分层」才绕过，`editor_get_scene_tree` 被调 5 次`**

| 项 | 内容 |
|---|---|
| 时间 | `seq=59..63`（`23:05:00.742` 起）与 `seq=95..103`（`23:07:24` 起） |
| 调用序列（第 2 轮） | `editor_open_scene`(57) → `editor_get_scene_tree`(58) → `editor_add_nodes_batch`(59, **仅 6 个根**) ✅ → `editor_add_nodes_batch`(60, 9 个二层) ✅ → `editor_add_nodes_batch`(61) ❌ `nodes[3]: parent 'Root' not found` → `editor_add_nodes_batch`(62) ❌ `nodes[0]: parent 'Root/VBox' not found` → `editor_get_scene_tree`(63) ✅ |
| 事实 | ①`seq=61` 的 `nodes[3]={name:"VBox",parent_path:"Root"}` 失败，而 `Root` 真实路径是 **`HUD/Root`**（`seq=60` 刚以 `parent_path:"HUD"` 建成）⇒ 错误**正确**，但错误消息**不指出**「可用路径是 `HUD/Root`」；②第 3 轮（`seq=95..100`）调用方改为**更细的分层**：`ab=75,102,90,90,346` 五次 `editor_add_nodes_batch` 全绿，且 `editor_get_scene_tree` 出现 **5 次**（`seq 94,99,101,102,103`，其中 `101/102/103` **同参数连打 3 次**，`rb` 恒 `12308`）。 |
| 归类 | **A6#1 的摩擦延续** + **C（可合并）候选** + **D1（多余往返）** |
| 证据 | `seq=59` args 6 节点 `ab=337`；`seq=60` args 9 节点 `ab=557`；`seq=61` `ec=-32001` `err="nodes[3]: parent 'Root' not found"` `ab=320`；`seq=62` `ec=-32001` `err="nodes[0]: parent 'Root/VBox' not found"` `ab=326`；`seq=94/99/101/102/103` 均 `editor_get_scene_tree` `ab=18`（`{"max_depth":12.0}`，见分析器 `repeated_same_args`）`rb` 依次 `8047/9995/12308/12308/12308` |
| 实测/推断 | **实测**（全部参数与错误码）。「`101/102/103` 是调用方在等场景稳定」= **推断**（无法从追踪看出动机；**注意**：三者 `rb` 完全相同，可作「确定性」正面证据） |
| 建议 | ①`editor_add_nodes_batch` 支持同批父子（OBS-008）；②`editor_get_scene_tree` 的 `max_depth` 默认值偏小导致反复加深（`ab` 从 `6.0`→`8.0`→`12.0` 各调过），建议**默认返回全树**或返回「被截断」标记；③错误消息带**候选路径**（引擎能做最近邻匹配） |

### OBS-010 / **A6#2：`editor_setup_physics_body` **完全相同**的参数先失败两次、36 秒后成功（父存在性隐式依赖）**

| 项 | 内容 |
|---|---|
| 时间 | 失败 `seq=12` `ts=1790175809039` / `seq=13` `ts=1790175809141`；成功 `seq=64` `ts=1790175901240` |
| 调用序列 | `editor_setup_physics_body{body_type:"StaticBody2D",name:"WallOuter",parent_path:"Track"}`(12) ❌ → 同工具 `name:"WallInner"`(13) ❌ → …（中间 50 次调用，含重建 `Track`）… → **完全相同的 args**(64) ✅ |
| 事实 | `seq=12` 与 `seq=64` 的 `args_bytes` **均为 69**，分析器 `repeated_same_args` 亦判为同一 args、`outcomes=[false,true]`。即**同一请求**在树状态改变后成功 ⇒ 这是一个「隐式前置：父必须已存在」的工具，且**错误消息足以自纠**（`Parent 'Track' not found` 直说了缺什么）。 |
| 归类 | **A6（多次调用才摸清用法）**，但**同时是 D3 的正面案例**（错误消息够用：调用方照着消息去建 `Track`，随后同参数直接成功）。按 §A §4.1 A6 判据成立。 |
| 证据 | `seq=12`：`ec=-32001` `err="Parent 'Track' not found"` `ab=69` `rb=176`；`seq=64`：`ec=0` `ab=69` `rb=249`；`seq=13`/`seq=65` 同型（`WallInner`，`ab=69`，`false→true`）。分析器 `repeated_same_args` 两项 `count=2` `outcomes=[false,true]` |
| 实测/推断 | **实测** |
| 建议 | 无需新工具；建议在描述里显式写「`parent_path` 必须已存在」，让调用方**不必**用一轮失败去学。**正面记录**：本条可作为「错误消息够用」的基线，用于对比 OBS-013（同一份消息模式的**反面**案例）。 |

### OBS-011 / **A6#3：`editor_set_node_property` 连续 **20 次** `-32001` 才走通（级联失败）**

| 项 | 内容 |
|---|---|
| 时间 | 第 1 轮 `seq=14..26`（`ts 1790175809249..1790175810546`）；全部失败。第 2 轮 `seq=66` 起开始成功 |
| 调用序列 | `(14) Car ❌ → (15) CP0_StartFinish ❌ → (16) CP1 ❌ → (17) CP2 ❌ → (18) Track/Road ❌ → (19) Track/StartLine ❌ → (20) Car/Body ❌ → (21) HUD/Root/VBox/LapLabel ❌ → (22) TimeLabel ❌ → (23) BestLabel ❌ → (24) CheckLabel ❌ → (25) HUD/StartButton ❌ → (26) Camera ❌`（13 次）+ 第 3 轮 `(67..69)`、`(73..76)` 共 7 次 → **合计 20 次 `-32001`** |
| 事实 | 这 20 次失败**全部是 OBS-008 那次批处理失败的级联**：`seq=10` 的批处理失败后**整棵树并未建立**，于是所有属性写都找不到节点。**但错误消息只说「Node 'X' not found」，没有任何线索指向「你刚才那次批处理整体失败了」**。调用方（开发者）自己也没有在第 1 轮之后立刻重试批处理，而是把 13 次属性写全部试了一遍——这是一次**可被工具避免的浪费**。 |
| 归类 | **A6（第 3 条）** + **D3（错误消息不足以自纠：失败的上游不可见）** |
| 证据 | 分析器 `error_code_by_tool`：`editor_set_node_property: {"-32001": 20}`、`editor_add_nodes_batch: {"-32001": 3}`、`editor_setup_physics_body: {"-32001": 2}`；`error_code_distribution={"-32001":25}`。失败点 `rb` 均 172-193 B（消息很短） |
| 实测/推断 | **实测**（20 条失败记录）。「是 OBS-008 的级联」= **实测 + 推理**：`seq=10` 失败与随后 13 次同型 `not found` 的时间连续性 + 第 2/3 轮重建后才成功，共同支持这一因果；但**我没有读批处理的实现**来断言它是否原子（见 OBS-012） |
| 建议 | ①批处理一旦失败，应让后续错误携带「可疑上游」信息不可行；更实际的建议是**批处理失败时把「本请求未产生任何节点」写进错误**（原子性可声明）；②`editor_set_node_property` 的错误可附**最接近的候选节点路径**；③**可优化**：提供「一次设置多个节点的多个属性」的工具（见 OBS-015） |

### OBS-012 / 未定论：`editor_add_nodes_batch` 失败时**是否部分生效**（`rb=603/866/532` 的形状不够判定）

| 项 | 内容 |
|---|---|
| 时间 | `seq=10` `rb=603`；`seq=61` `rb=866`；`seq=62` `rb=532`（均 `ok=false`） |
| 事实 | 失败的批处理**仍返回 500-900 B 的响应体**，远大于错误消息本身 → 说明响应里**逐节点**报告了结果。**但追踪只记录请求 args，不记录响应体**，因此我**无法**从追踪判定 `nodes[0..2]` 是否真的被创建。 |
| 归类 | **方法论限制（D）**，不是已确认的缺陷 |
| 证据 | 三处 `result_bytes` 显著大于同工具成功时的 `rb=255/306/282/799` 量级区间；`args_truncated=False` 说明 args 完整、`result_bytes` 只是**响应长度** |
| 实测/推断 | **实测**只有长度；「部分生效」= **未证实的推断**，我**不**下结论 |
| 需要的补证 | 用**第二条连接**读一次 `editor_get_scene_tree`，核对 `Checkpoints/CP0_StartFinish/Collision` 等是否存在于该次失败之后（本会话时间不足；§D 可在**独立 scratch** 上构造 3 节点批处理、故意让第 3 个失败，再读树）。**关键**：若确实部分生效，则批处理**非原子**，且错误消息未声明，属 **A5 家族（报成功后状态不定）** |

### OBS-013 / **【高价值】C# 信号名大小写：`speed_changed` 不存在，真实名是 `SpeedChanged`——错误消息不给候选，调用方放弃**

| 项 | 内容 |
|---|---|
| 时间 | 失败 `seq=170/171/172`，`ts_ms=1790176109873/1790176109908/1790176109935`（本地 `23:08:29.873` 起） |
| 调用序列 | `editor_get_node_signals{node_path:"Car"}`(167) ✅ `rb=3915` → `editor_get_node_signals{node_path:"LapTimer"}`(168) ✅ `rb=2975` → `editor_get_node_signals{node_path:"Checkpoints/CP1"}`(169) ✅ `rb=5279` → `editor_connect_signal{source_path:"Car",signal:"speed_changed",target_path:"HUD",method:"OnSpeedChanged"}`(170) ❌ → `{LapTimer, checkpoint_passed, HUD, OnLapEvent}`(171) ❌ → `{LapTimer, lap_completed, HUD, OnLapEvent}`(172) ❌ → **改接引擎原生信号**：`{HUD/StartButton, pressed, ., OnStartPressed}`(173) ✅、`{Checkpoints/CP1, body_entered, LapTimer, OnCheckpointBodyEntered}`(174) ✅ |
| 事实 | 三条失败都是 **C# `[Signal]` 声明的信号**（`Car.cs`/`LapTimer.cs`），两条成功都是**引擎原生**信号。错误消息一律 `Signal '<snake_case>' on node '<X>' not found`。**调用方三次失败后放弃**，改接原生信号——`speed_changed` / `checkpoint_passed` / `lap_completed` **从未连上**。 |
| 归类 | **A6（第 4 条，且是「未解决」型）** + **D3（错误消息不足以自纠）** |
| 证据（不可变锚点） | 【**实测，我自己的只读探测**】`editor_get_node_signals{node_path:"Car"}` @9888（第二条连接，`23:19`）→ 响应 **4823 B**，sha256 **`33B6D24B516DAE305E0736E933949A5E3F5D92FBC1848A81E91C0FE9C3ECE236`**；解析后 `count=23`、`type=CharacterBody2D`、`node_path=Car`；信号名列表**包含 `SpeedChanged`**（PascalCase，**C# 声明名的原样**），**不含 `speed_changed`**。契约侧（`docs/tools_list.renamed.json` 行 394）`editor_set_node_property` 所属族描述极简（`"修改属性"`），`editor_connect_signal` 的错误**未**附候选名。 |
| 实测/推断 | **实测**：`SpeedChanged` 存在于节点上（我的探测响应 sha256 为锚）、`speed_changed` 不存在、`editor_connect_signal` 报 `-32001`。**推断**：失败原因 = C# 声明名未做 snake_case 别名；且 **GDScript/引擎惯例名与 C# 声明名不同**，调用方从工具表面**无法预知**该用哪个。 |
| **勘误（append-only）** | 我曾**推断**「因为 C# 程序集在编辑器启动后才构建（`mcp-racing-test.dll` `23:07:39.397`，失败发生在 `23:08:29.873`，晚 50 s），所以编辑器看不到该信号」。**该推断被我的只读探测证伪**：信号**确实存在**，只是名字是 `SpeedChanged`。**此处显式撤回该推断**（`PLAYBOOK §7.3`）。 |
| 建议 | ①`editor_connect_signal` 失败时返回**候选列表 + `data.suggestion`**（引擎可做：`Object::get_signal_list()` 已能列举 23 个名字）——这是**最小改动、最高收益**的一条；②`editor_get_node_signals` 可在 `signals[].name` 旁标注 `source:"engine"\|"script"` 与**大小写不敏感匹配**提示；③若要跨语言顺手：连接失败时对 `snake_case↔PascalCase` 做一次自动别名匹配并提示。 |

### OBS-014 / **可合并候选：`editor_save_scene` → `project_read_scene_file_content`（保存即读回）**

| 项 | 内容 |
|---|---|
| 时间 | `seq=43→44`（`23:03:32.164/.240`）、`seq=85→86`（`23:05:03.367/.440`）、`seq=123→124`（`23:07:28.266/.340`）—— **3 次完整同型对** |
| 调用序列 | `editor_save_scene{}` ✅ → `project_read_scene_file_content{path:"res://scenes/main.tscn"}` ✅ |
| 事实 | 三对**完全同参数**（`ab=2` → `ab=33`），且**每次都紧接着**在 60-76 ms 内发生；`rb` 依次 `267→2145→3399→6556`（场景逐步变大）。这是「保存后立刻验证落盘」的固定套路（`PLAYBOOK §3` M2 的「只比较读回值不够」教训的应用）。 |
| 归类 | **C（可合并）** |
| 证据 | 6 条 `seq` 的 `ab`/`rb`/`ts_ms` 全部见 OBS 表；分析器 `repeated_same_args` 收录 `editor_save_scene{}(seq 43,85,123)` 与 `project_read_scene_file_content{path:...}(seq 44,86,124)` 各 `count=3` `outcomes=[true,true,true]` |
| C2 合理性检查 | 二者**不完全必然成对**（`project_read_scene_file_content` 也能读未保存的场景）⇒ 按 §A C2，**不建议**把二者合并成一个工具；**建议**改为给 `editor_save_scene` 增加 `verify?:boolean`（返回 `saved:true, path, sha256, bytes`），这样「保存并自证」一趟完成，且**不丢**读文件的独立能力。 |
| 实测/推断 | **实测** |
| 建议 | **签名草案**：`editor_save_scene{verify?:bool=false}` → `{saved:true, path:"res://scenes/main.tscn", sha256, bytes}`。**风险**：`sha256` 与 `project_read_scene_file_content` 的字节口径必须一致（该工具已有 sha 需求，见 §A AC-1），需在实现里统一。 |

### OBS-015 / **可合并候选：同类工具的「重复单点调用」——`editor_get_node_properties` ×3、`editor_set_node_property` ×26、`project_validate_script` ×7、`editor_set_node_script` ×8`**

| 项 | 内容 |
|---|---|
| 时间 | `seq=78/79/80`（同轮连打 3 次读）；`seq=104..115`（12 连写）；`seq=127..132`（6 连校验）；`seq=133..140`（8 连挂脚本） |
| 调用序列 | 读：`editor_get_node_properties{Car}` → `{Track/Road}` → `{HUD/StartButton}`（各只问**一个**属性）；写：`editor_set_node_property` 连续 12 次（每次一个节点一个属性）；`project_validate_script` 连续 6 次（每次一个文件）；`editor_set_node_script` 连续 8 次 |
| 事实 | 同一族工具的**单点调用**高度密集：`editor_set_node_property` 占全部 `tools/call` 的 **37/204 ≈ 18%**（全期），读侧 3 连、校验 6 连、挂脚本 8 连。**注意**：`editor_get_node_properties` 已支持 `properties:[...]` 数组（一次问多属性），但**没有** `paths:[...]`（一次问多节点）——所以「3 个节点」只能 3 次调用。 |
| 归类 | **C（可合并）** |
| 证据 | 分析器 `mergeable.unigrams`（**该字段渲染有缺陷，见 OBS-016**）显示 `editor_set_node_property` 计数最高；我按 `seq` 区间人工统计：`104..115` 共 12 次全为 `editor_set_node_property`，`rb=190..398`、`ab=48..146`，`ok` 全 `true`。`seq=78/79/80` 的 args 分别为 `{"path":"Car","properties":["position"]}`、`{"path":"Track/Road","properties":["polygon"]}`、`{"path":"HUD/StartButton","properties":["text"]}` |
| C2 合理性检查 | **满足**：这些调用**必然成组**出现（写多个节点属性、校验多个脚本、给多个节点挂脚本，都没有「只做其中一个」的场合），且合并后**不掩盖**错误（可逐项返回每个元素的结果）。风险是**失败粒度**：合并后必须保留「第 i 项失败」的定位（`nodes[i]` 风格，`editor_add_nodes_batch` 已有此粒度可参照）。 |
| 实测/推断 | **实测** |
| 建议（签名草案） | ①`editor_get_node_properties_batch{paths:["Car","Track/Road"], properties?:[...]}` → `{results:[{path, properties:{...}}]}`（**引擎一次调用即可**：遍历 `NodePath` + `get_property_list`）；②`editor_set_node_property_batch{updates:[{path,property,value}]}` → `{applied:[{path,property,ok,old_value,new_value}], failed:[{index,path,error}]}`；③`project_validate_script_batch{paths:[...]}`；④`editor_set_node_script_batch{assignments:[{node_path,script_path}]}`。**注意 §A §4.3 C2**：合并后**不得**把「哪一项失败」吞掉。 |

### OBS-016 / **【方法论异常】`connection` 字段恒等于 `seq`：分析器的「可合并序列」信号在本工作流下**结构性失明**`

| 项 | 内容 |
|---|---|
| 时间 | 全期（`trace-editor.jsonl` 第 2 代全部 **205** 条记录） |
| 事实 | 我逐条核对了 **205/205** 条：`connection == seq`？**相同 205 条，不同 0 条；distinct connection = 205；`connection` 上拥有 >1 次调用的连接数 = 0**。即**每一次 `tools/call` 都发生在自己的连接上**（与 `PLAYBOOK §3` 强制要求「证据采集一律 `curl.exe --data-binary @file`」一致：一次 curl = 一条 TCP 连接）。 |
| 归类 | **A（工具/分析链异常）**：`analyze_mcp_trace.py`（TASK-038 交付物）的 `mergeable()` **按 `connection` 分组**计算 2-gram/3-gram；当每个连接只有 1 次调用时，`bigrams`/`trigrams` **必然恒为空**。实测输出正是 `bigrams: none repeated` / `trigrams: none repeated`，而同一份追踪里**肉眼可见**大量高频序列（如 `seq=104..115` 的 12 连 `editor_set_node_property`、`seq=127..132` 的 6 连 `project_validate_script`）。⇒ §A §4.3 C1 的判据「同一次 `connection` 内 2-gram ≥3 次」在本工作流下**不可满足**。 |
| 证据 | 我自写的只读核对（纯 ASCII 脚本）输出：`connection==seq: 205; differ: 0; distinct connections: 205; connections with more than 1 call: 0`。分析器同一次运行的 `JSON`：`"mergeable": {"unigrams":[... 10 项 ...], "bigrams": [], "trigrams": []}`，而 `"repeated_same_args"` 却有 30+ 组、`count` 高达 5。原始行样例：`{"id":1003,"connection":1,...,"seq":1,...}`、`{"connection":10,...,"seq":10}`（`PLAYBOOK §4` 列出的字段确实含 `connection`）。 |
| 归类（次生） | 同一份 JSON 里 `mergeable.unigrams[].sequence` 被渲染成**字符数组**（如 `["e","d","i","t","o","r",...]`）而 bigrams/trigrams 是**字符串数组** —— `shapes()` 里 `list(gram)` 对 unigram 的 `gram`（是字符串）逐字符展开所致。**这是分析器的显示缺陷**（不影响 `repeated_same_args`）。 |
| 实测/推断 | **实测**（我逐条核对 + 分析器输出对照）。「`connection` 语义 = 传输层连接」= **推断**（未读 `mcp_trace.cpp` 的赋值处）；但「它与 `seq` 一一对应」是**实测**。 |
| 建议（对 §D 直接可用） | ①**不要**用 `analyze_mcp_trace.py` 的 `bigrams/trigrams` 找「可合并」——本会话它**必然是空的**；改用「**同工具连续段**」或 `repeated_same_args`，或直接人工读 `seq` 区间。②**分析器最小改动**：当 `max(calls per connection) == 1` 时退化为**按文件顺序**（或按 `ts_ms` 间隔 < 60 s 分簇）计算 n-gram，并在输出里声明退化；同时修 `shapes()` 的 `list(gram)`。③**若要让 `connection` 有用**，追踪应记录稳定的客户端身份（而非每请求一条连接的 id）。 |

### OBS-017 / **缺失工具线索（2 条，均为「有能力缺口但证据强度中等」）**

> **诚实声明**：全期 `trace-editor.jsonl` **没有出现过一次 `-32601`**（`missing_tools.method_not_found = []`），也**没有**「某参数名反复被拒且从未被接受」的记录（`probed_argument_names = []`）。因此**按 §A B1 的机器判据，本会话没有「工具名不存在」型的缺失**。下面两条是**能力缺口线索**，证据来自「契约里搜不到对应工具」+「开发者被迫用工具外手段」，**不是** `-32601`。

| ID | 想做什么 | 试过哪些工具 | 实际结果 | 回退做了什么（证据） | 建议 |
|---|---|---|---|---|---|
| **B-1** | **编译 C# 程序集（GodotSharp 项目）**，使 `[Export]`/`[Signal]` 在编辑器与运行时可见 | 契约 171 条里**没有**构建/编译工具。我按 `"name": ".*(build\|compile\|reload\|restart\|headless).*"` 搜 `docs/tools_list.renamed.json`，**只命中 1 条：`editor_reload_plugin`（行 780）**，那是 GDExtension 插件重载，**不编译 C#** | 无工具可用 | **工具外 `dotnet build`**：`.godot\mono\temp\bin\Debug\mcp-racing-test.dll`（38400 B）`LastWriteTime = 23:07:39.397`；`GodotSharp.dll` = 引擎自带（`13:30:26`） | 建议新增 `project_build_csharp{}` → `{ok, assembly_path, sha256, warnings[], errors[], duration_ms}`（引擎侧 `build_csharp_project()` 或调用 `dotnet build`），并让 `editor_connect_signal`/`editor_set_node_script` 在检测到陈旧程序集时给出 `data.suggestion` |
| **B-2** | **让被观测的游戏以 `--headless` 起来**（§A §2.5 模式 B，自动化取证主模式） | 契约里与「运行」相关的只有 `editor_play_scene`；我按同一正则搜索**未**发现任何 `headless`/`restart` 工具 | 至 `23:11:51` **9889 从未监听**；`trace-game.jsonl` **从未创建** | 到观察窗口结束时**尚未发生**（游戏阶段还没开始） | **本项证据不足，标为「未确认线索」**：§A §2.5 已预判它是缺失候选，但**本会话未实测到**。需要 §D 在 §B 日志出现后确认，或由后续批次复测 |

### OBS-018 / **未确认为异常的两项（如实记录「查过但不算」的负结果）**

1. **A5「报成功但状态未变」：至 `seq=205` 未发现合格实例。** 判定需要「读回值 == 旧值 **且** 事务前后 sha256 相同」，而追踪**不记录响应体**，我无法从追踪单独坐实。可核对的正面信号：`editor_save_scene` 三次（`seq 43/85/123`）**同参数、同 `rb=128`、同 `dur_ms=18`**；`editor_get_scene_tree` 三次（`seq 101/102/103`）**同参数、同 `rb=12308`** —— 均为**确定性**正面证据，**没有**「两次同请求结果不同」的实例。⇒ 本条**不是**「没有异常」，而是「按现有取证手段**无法判定**」。
2. **A7 工具间矛盾：查了两处，均为「不成立」。** ①`editor_list_signal_connections`(175, `rb=94862`) vs `editor_analyze_signal_flow`(176/177, `rb=145`)：二者 `ok=true`，但**追踪不含响应体**，我**未能**比对「连接存在性」的答案是否一致 ⇒ **无法判定**（§A 点名要查的点，本会话**没查成**，如实记录）。②`editor_get_node_signals` 与 `editor_connect_signal`（OBS-013）：**一度以为矛盾**（列表 `ok` 3.9 KB，206 ms 后连接说信号不存在），但我的**只读探测**证明列表里根本没有 `speed_changed`（只有 `SpeedChanged`）⇒ **不矛盾**，是**名字不同**。
3. **`editor_list_signal_connections` 返回 94 862 B（`seq=175`，`args={}`）**：在约 20 节点的场景上接近 95 KB，**未达** §A §4.1 A4 的 1 MiB 阈值，故**不记为 A4**；但按「无界列举」的直觉值得 §D 复核是否含引擎内部连接。
4. **`project_get_settings` 的 `prefix` 敏感性**：`{"prefix":"godot_mcp"}`(`seq=3`) `rb=105` vs `{"prefix":"godot_mcp/"}`(`seq=42/54/90`) `rb=254`。两者**参数不同**（`ab` 22 vs 23），故**不构成 A8**；但**是否尾随斜杠会改变结果集**这件事**没有任何文档**，属 **D5 候选**，需响应体补证。

---

## 3. 计数与达标情况（截至 `seq=205`，本地 `23:11:51`）

| 项 | 值 | 依据 |
|---|---|---|
| 追踪文件（第 2 代） | **205 条** = 1 `initialize` + 204 `tools/call`；失败 **28**（`-32001`：25 + `editor_connect_signal` 3） | 我的 `sum.ps1` + 分析器（分析器在 `seq=125` 时快照，故其计数 125/25 并**不**覆盖全期） |
| **A6 多条调用才摸清用法** | **4 条**：OBS-008（`editor_add_nodes_batch`）、OBS-010（`editor_setup_physics_body`，同 args `false→true`）、OBS-011（`editor_set_node_property` 20×`-32001`）、OBS-013（`editor_connect_signal` 3×`-32001`，**未解决**） | 要求 ≥3 ✅ |
| **B 缺失工具线索** | **2 条线索**（OBS-017 B-1 编译 C# 程序集 = **契约搜索 + 外部构建物证**；B-2 headless 游戏 = **未确认**）；**B1 型（`-32601`）确认为 0** | 要求 ≥2 条线索，已如实标注强度 |
| **C 可合并候选** | **2 组**：OBS-014（save→read 回，3 次同型对）、OBS-015（单点族连打：写 12 连 / 读 3 连 / 校验 6 连 / 挂脚本 8 连） | 要求 ≥2 ✅ |
| **A 异常** | **3 条实测异常**：OBS-003（默认端口 9877 抢占风险，2 次复现）、OBS-005（追踪被清空，证据丢失）、OBS-016（`connection==seq` ⇒ 可合并信号失明）；另 **OBS-004**（环境突变，非缺陷）；**A7/A5 均为「无法判定」而非「不成立」**（OBS-018） | 要求 ≥2 ✅ |
| 预算 | 观察开始 `22:44:03`；本文件上次更新 `23:2x`。**未到 45 分钟**、`DEV-DONE.marker` **未出现** ⇒ 观察**在本报告落笔时仍在继续**，后续条目将追加于 §4 | — |

---

## 4. 观察尾部（滚动追加）

### OBS-019 / 轮询记录（最后一次采样）

| 时间（本地） | 事实 |
|---|---|
| `23:14:29` | **9889 已监听**（`PID 44156`，`godot.windows.editor.x86_64.mono`）；`trace-game.jsonl` 出现（5101 B）；9888 仍 `PID 72876`；**9877 空闲**（`none (free)`，即用户 Godot 退出后**未被**开发者进程占用 —— OBS-003/OBS-004 的风险**本次未实现**）；`DEV-DONE.marker` **仍未出现** |

---

## 5. 游戏端点观察期（`trace-game.jsonl`，`seq 1..14`，本地 `23:13:59` 起）

### OBS-020 / 游戏端点启动与首批调用：`editor_play_scene` 成功注入 9889

| 项 | 内容 |
|---|---|
| 时间 | `editor_play_scene` = `trace-editor.jsonl` `seq=246`，`ts_ms=1790176436142`（`23:13:56.142`），**`duration_ms=1796`**，`ok=true`，`rb=223`；`trace-game.jsonl` 首行 `initialize` `seq=1` `ts_ms=1790176439493`（`23:13:59.493`，晚 3.35 s） |
| 调用序列 | 编辑器侧：`editor_play_scene{mcp_port:9889, mode:"current"}` ✅ → 游戏侧：`initialize`(g1) → `running_game_get_scene_tree`(g2) → 4× `running_game_get_node_properties`(g3-6) → `running_game_find_nodes_by_script`(g7) → `running_game_find_node_when_available`(g8) → `running_game_get_node_properties_batch`(g9) → `running_game_find_ui_elements`(g10) → `running_game_assert_screen_text`(g11) |
| 事实 | **正面结论（对 §A §2.5 模式 B 的预判是反例）**：`editor_play_scene` **带 `mcp_port` 参数**即可把游戏拉起来并让 9889 监听，**不需要**「绕过工具自启进程」。`running_game_assert_screen_text`（g11）在**窗口化**游戏里 `ok=true`（`rb=980`）。`running_game_get_scene_tree` 在游戏端点 `ok=true`（`rb=3218`）。 |
| 归类 | 正面实测（用于修正 §A §2.5 与 OBS-017 B-2 的「缺失」预判） |
| 证据 | `seq=246` args 全文 `{"mcp_port":9889.0,"mode":"current"}`；`trace-game.jsonl` `seq=1..11` 全部 `ok=true`，`ec=0`；9889 监听者 `PID 44156`（`netstat -ano`） |
| 实测/推断 | **实测**。「游戏是窗口化而非 headless」= **推断**（`editor_play_scene` 契约无 headless 参数，且 `running_game_assert_screen_text` 成功；但**未**核实游戏进程命令行） |
| 对 OBS-017 B-2 的影响 | **降级**：B-2（「没有工具能让游戏 headless 起来」）在**本会话未被证实**，且观察到的路径是「`editor_play_scene` + `mcp_port` → 9889 起来」——**可用**。B-2 应改述为「无法用工具让游戏以 **headless** 起来（可窗口化起来）」，需 §D 用游戏进程命令行复核。 |

### OBS-021 / **A6#5：`running_game_find_nearby_nodes` 的参数名靠猜；`running_game_get_autoload_node` 的必填参数靠猜**

| 项 | 内容 |
|---|---|
| 时间 | g`seq=12` `ts_ms=1790176439926`（`-32602` `Missing required parameter: name`，`ab=2`=`{}`）；g`seq=13` `ts_ms=1790176439960`（`-32602` `Unknown parameter 'node_path' for tool 'running_game_find_nearby_nodes'`，`ab=45`） |
| 调用序列 | `running_game_get_autoload_node{}`(12) ❌ → `running_game_find_nearby_nodes{node_path:"/root/Main/Car", radius:300.0}`(13) ❌ → `running_game_set_node_property{node_path:"no_such_node_zzq", property:"x", value:1.0}`(14) ❌（**这是 §A AC-8 要求的负例，属预期**） |
| 事实 | 调用方把 `node_path` 用到了 `running_game_find_nearby_nodes` 上 → 被拒。错误消息**点名了**非法参数（`Unknown parameter 'node_path'`）但**不列出**合法参数名，调用方必须回到 `tools/list` 或再猜。`running_game_get_autoload_node` 则连「需要 `name`」这件事都要靠一次失败才知道（`ab=2` 说明调用方以为它是无参工具）。 |
| 归类 | **A6（第 5 条）** + **D3（错误消息不足以自纠：不含 `data.suggestion`、不含合法参数集）** |
| 证据 | 两行全文（`ec`/`err`/`ab`/`rb` 见上）；`rb=96` 与 `rb=271`。与 g`seq=14`（**故意**的 `-32001` 负例，`err="Node 'no_such_node_zzq' not found"`）对照 |
| 实测/推断 | **实测**。「调用方随后是否自纠成功」= 至本报告落笔时游戏追踪只有 14 行，**未见**这两个工具的成功重试 ⇒ **未解决**（与 OBS-013 同型） |
| 建议 | ①`-32602 Unknown parameter` 应在 `data.suggestion` 里列出**该工具的合法参数名**（实现侧已持有 `inputSchema`，零成本）；②`-32602 Missing required parameter: name` 应同时给出**工具签名**；③端点级：`running_game_*` 的参数命名在 `node_path`/`path`/`name` 之间不统一（编辑器侧用 `path`，游戏侧用 `node_path`，`get_autoload_node` 用 `name`）⇒ **D4（参数形状不对称）**，且是**跨端点**的，调用方无法从一端迁移到另一端。 |

### OBS-022 / **【最强异常】跨端点矛盾 + 同端点内部不一致：`physics_material_override` 在 `Car` 上「不存在」，在 `WallOuter` 上读得到，而游戏端点说它存在（值为 `null`）**

| 项 | 内容 |
|---|---|
| 时间 | 开发者轨迹：e`seq=208`（`ts 1790176283946`）、e`seq=239` ✅、e`seq=240` ✅、e`seq=241` ❌（`ts 1790176368546` = `23:12:48.546`）。**我的独立只读探测**：`23:14` 之后（在 `editor_play_scene` 之后），两个端点各 1 次 |
| 调用序列（开发者） | ① `editor_get_node_properties{path:"Car", properties:["physics_material_override"]}`(208) ❌ `-32001` → ② `editor_add_resource_to_node_property{node_path:"Track/WallOuter", property:"physics_material_override", resource_type:"PhysicsMaterial", resource_properties:{bounce:0.5,friction:0.25}}`(238) ✅ → ③ `editor_get_node_properties{path:"Track/WallOuter", properties:["physics_material_override"]}`(239) ✅ → ④ `editor_add_resource_to_node_property{node_path:"Car", property:"physics_material_override", ...}`(240) ✅ → ⑤ `editor_get_node_properties{path:"Car", properties:["physics_material_override"]}`(241) ❌ `-32001 Property 'physics_material_override' on node 'Car' not found` |
| 事实 | **同一个属性名**：在 `Track/WallOuter`（StaticBody2D）上**可读**（239 ✅），在 `Car` 上**报不存在**（208/241 ❌）。而 `Car` 与 `WallOuter` **都继承 `CollisionObject2D`**（`physics_material_override` 定义于此），且**游戏端点**对**同一个 `Car`** 说它**存在**（值为 `null`）。 |
| 归类 | **A（异常）—— 同时构成 §A A7「工具间说法矛盾」**（编辑器 vs 游戏、同一节点同一属性）**与同端点内部不一致**（Car vs WallOuter）。这**不是**我早前怀疑的「报成功但没写」（见下） |
| 证据（**双 sha256 锚点，我自己的探测**） | ①**编辑器 9888**：`editor_get_node_properties{path:"Car", properties:["physics_material_override","collision_layer"]}` → `{"error":{"code":-32001,"data":{"suggestion":"Call editor_get_node_properties without 'properties' to list every readable property of this node"},"message":"Property 'physics_material_override' on node 'Car' not found"},"id":90002,"jsonrpc":"2.0"}`，**247 B，sha256 `C444B1B49830635B7397979A907F73BCBCE0CF58FC26D9CE3725E7475F19AA2B`** ②**游戏 9889**：`running_game_get_node_properties{node_path:"/root/Main/Car", properties:["physics_material_override","collision_layer"]}` → `{"id":90003,...,"result":{...,"text":"{\"node_path\":\"/root/Main/Car\",\"properties\":{\"collision_layer\":1,\"physics_material_override\":null},\"type\":\"CharacterBody2D\"}"}}`，**214 B，sha256 `E863485EA43B5943A80D4CD3DCDA393B092034F82D674FBF8EF8174CD51A8849`**。**两边都自报 `type=CharacterBody2D`** ⇒ 同节点同类型。请求体：`car-pmo.req.json` / `game-pmo.req.json`（`%TEMP%\mcp-observer\`） |
| 关键对照 | 编辑器在同一请求里**找到了** `collision_layer`（同为 `CollisionObject2D` 属性），**只**没找到 `physics_material_override`；而它的当前值恰好是 `null`（游戏端点为证）⇒ **最强假设（推断）**：编辑器侧的「属性存在性/可读性」判定把「**值当前为 null**」误判为「**属性不存在**」——这正是 `PLAYBOOK §6.6` 第 7 例点名的同一类混淆（「声明类型是 `Variant::NIL`」与「不存在」同形）在**另一个工具**上的复发。 |
| 实测/推断 | **实测**：矛盾本身、两侧 sha256、同类型自报。**推断**：根因是 null 与 not-found 的混淆（未读编辑器侧实现源码）。 |
| **同时澄清（避免过度指控）** | 我曾怀疑 e`seq=240` 的 `ok=true` 是「报成功但没写」（A5）。**不成立/未证实**：`main.tscn` 落盘时间 `23:11:26.467`，而 `seq=238/240` 在 `23:12:46/47`，且 **e`seq=240` 与 e`seq=246`（play_scene）之间没有任何 `editor_save_scene`** ⇒ 游戏进程读到的是**未包含这些写入的磁盘场景**，其 `physics_material_override: null` **不能**证明写入失败。**故本报告不主张 A5**；要坐实需「写入 → `editor_save_scene` → 再读两个端点 → 同时核 `.tscn` 字节」。 |
| 严重度建议 | **high**（属性存在性判定错误会让调用方写不进去、也读不出来；且**仅编辑器端**受影响、游戏端正确 ⇒ 同一会话内两套语义） |
| 建议 | ①统一「属性存在性」判定：存在性应查 `ClassDB`/`get_property_list()`，**与当前值是否为 null 无关**；②`editor_get_node_properties` 与 `running_game_get_node_properties` 对同一节点同一属性必须给出一致答案（建议加一条**跨端点一致性**的 doctest/活证据链）；③`-32001` 的消息已带 `data.suggestion`（好），可再补「该属性当前值是否为 null」的区分用语 |

---

## 6. 观察窗口结束时的状态与自我声明

| 项 | 值 |
|---|---|
| 观察开始 / 本报告最后更新 | `22:44:03` / 观察窗口内（`DEV-DONE.marker` **未出现**；总预算 45 分钟**未到顶**） |
| 追踪规模 | `trace-editor.jsonl` = **246 行**（`seq 1..246`，含开局 `initialize`）；`trace-game.jsonl` = **14 行**（`seq 1..14`） |
| 累计失败 | **编辑器端 32 次 `ok:false`，全部是 `-32001`**（`seq≤205` 内 28 次：25 次为 `editor_set_node_property`×20 + `editor_add_nodes_batch`×3 + `editor_setup_physics_body`×2，另 3 次是 `editor_connect_signal`（OBS-013）；`seq 206..246` 内 4 次：`seq=208/241` `editor_get_node_properties`、`seq=242` `editor_set_node_property`（**故意**的 `no_such_property_zzq` 负例）、`seq=245` `project_read_resource`（**故意**的 `no_such_resource_zzq` 负例））。**游戏端 3 次**（`-32602`×2、`-32001`×1，其中 1 次是**故意**的负例） |
| 锚点（D86） | 全部结论测自 `f34ee937f3`（`feature/mcp-server-module`）；引擎自报 `v4.8.dev.mono.custom_build.f34ee937f`（`editor.out.log` 首行，**hash 前缀与 HEAD 一致**） |
| 纪律自证 | **未**修改 `modules/mcp_server/**` 任何实现（只写本报告）；**未**碰 9877（每轮 `netstat`，`9877` 全程空闲或属于用户 `PID 76048`，**从未**被开发者进程占用）；**未**启动/杀死任何引擎进程；**未**写入 scratch 工程（我的中间产物在 `%TEMP%\mcp-observer\`）；**未**占用 9888/9889（仅 2 次一次性只读探测，各自独立连接） |
| 未完成项（如实列出） | ①§A 点名的 `editor_list_signal_connections` vs `editor_analyze_signal_flow` 一致性 **未判定**（缺响应体）；②`editor_add_nodes_batch` 失败是否**部分生效** **未判定**（见 OBS-012）；③游戏端注入输入/采样/截图**尚未发生**（观察窗口结束时游戏追踪仅 14 行）⇒ **本报告不覆盖 AC-3/AC-4/AC-5/AC-7 的观察**，需后续窗口补 |

---

### OBS-023 / **OBS-005 在游戏端点复现：`trace-game.jsonl` 被清空为 0 字节，游戏进程换 PID**

| 项 | 内容 |
|---|---|
| 时间 | `23:23:23`（本地）采样 |
| 调用序列 | 无（跨进程行为） |
| 事实 | ①`trace-game.jsonl` 从 5 101 B / 14 行（`23:14:29` 我读到）变为 **0 字节**（`23:23:23`）；②9889 的监听 PID 从 **44156** 变为 **70456**（新游戏进程）；③9888 仍是 `72876`（编辑器未变）；④`editor.out.log` 由 780 B 增至 862 B；⑤**9877 仍空闲**（未被开发者占用）；⑥`DEV-DONE.marker` **仍未出现**。 |
| 归类 | **A（异常）—— OBS-005 的第二次独立实例**，这次在**游戏**端点。使 OBS-005 从「单次现象」升级为「**跨两个端点、可复现**」。 |
| 证据 | `Get-ChildItem` 两次采样：`23:14:29 trace-game.jsonl 5101` / `23:23:23 trace-game.jsonl 0`；`netstat -ano`：`23:14:29 9889 PID 44156` / `23:23:23 9889 PID 70456`；`PROC` 列表：`23:14:29` 有 `pid=44156` 与 `72876`，`23:23:23` 有 `pid=70456` 与 `72876`。 |
| 实测/推断 | **实测**：文件被清空、PID 变化。「游戏进程被 `editor_play_scene` 重启（或再次 play）」= **推断**（未保留启动命令；但两次 PID 都监听 9889 且带 `--mcp-trace` 到同一路径，与该推断一致）。 |
| **对 §D 的直接影响（重要）** | 我在 §5（OBS-020/021）引用的**游戏端点 14 行追踪，在本报告落笔时已不在磁盘上**。§D 若要求「回到追踪原文核对」，**无法**复核游戏端 `seq 1..14`——只能依据本报告抄录的字段（`seq/ts_ms/ec/err/ab/rb`，逐行见 OBS-020/021）。⇒ 这**坐实**了 OBS-005 的影响判断：**同一路径的追踪不是完整历史**，跨重启的证据会消失。 |
| 建议 | 同 OBS-005（改追加 / 带 pid 轮转 / 至少写一条 `trace_opened{truncated:true,pid}`）。**追加一条**：`editor_play_scene` 每次拉起游戏都会**重开**同一路径追踪 ⇒ 若 §B 需要在同一次试测里保留**多次 play** 的证据，必须为每次 play 指定不同 `--mcp-trace` 路径（当前工具面**没有**这个参数，属 **D5/D1 候选**：`editor_play_scene` 无法为被拉起的游戏指定**追踪路径**，调用方只能吃默认同名文件被清空的后果）。 |

---

### OBS-024 / 观察窗口收尾

| 项 | 值 |
|---|---|
| 收尾时间（本地） | `23:23:23`（观察开始 `22:44:03`，共约 **39 分钟**） |
| `DEV-DONE.marker` | **未出现** |
| 预算 | 45 分钟**未到顶**；本观察者**自行在收尾**（不阻塞开发者，遵守「不打断、不占用」），并**如实声明**：游戏端 AC-3/AC-4/AC-5/AC-7 的观察**未覆盖** |
| 最终追踪规模 | `trace-editor.jsonl` = 101 939 B（`seq` 已远超 246）；`trace-game.jsonl` = **0 B**（被重启清空，见 OBS-023） |
| 9877 最终状态 | **空闲**（`none (free)`）—— 全程**未**被开发者进程占用 |
| 模块纪律 | `modules/mcp_server/**` **未**被本观察者改动；本报告是唯一写入物 |
| **最终自证（命令输出）** | `git status --short modules/mcp_server/tools modules/mcp_server/tests` → **无输出（空）** ✅；`git status --short modules/mcp_server/docs/reports` → 仅 `?? RACING-OBSERVATIONS.md`、`?? RACING-TEST-PLAN.md`（均为报告，非实现）；`netstat` → `9888 LISTENING 72876` / `9889 LISTENING 70456` / **`9877` 无监听（空闲）** |
| 本报告自身锚点 | **本文件是 append-only，因此「本文件的 sha256」自指且不稳定**（每追加一行都会变）。可用的稳定锚点是**观察期内的外部证据哈希**，本报告中已给出的有：`import.attempt1/2.log` = `90AAFEDB…`/`3F77BA2C…`、`0003-raw-initialize.res.json` = `7FD5CC90…`、**我的探测响应** `car-pmo.res.json` = `C444B1B4…` 与 `game-pmo.res.json` = `E863485E…`、`car-sig.res.json` = `33B6D24B…`。**§D 复核时请对这些外部文件算哈希，不要对本报告算。** |
| **给 §D 的一句话** | 本报告最值得先复算的三条：**OBS-022**（跨端点属性存在性矛盾，双 sha256 锚点）、**OBS-016**（`connection==seq` 使分析器的可合并信号失明）、**OBS-005/023**（追踪跨重启被清空，游戏端 14 行已消失） |
