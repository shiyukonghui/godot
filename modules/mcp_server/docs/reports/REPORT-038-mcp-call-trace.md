# REPORT-038 — MCP 调用追踪（观察者的诚实证据源）

> 任务书：`docs/tasks/TASK-038-mcp-call-trace.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 分支 `feature/mcp-server-module`；本批**不新增工具、不改契约**：
> `docs/tools_list.renamed.json` 的 sha256 为
> `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256`，与 REPORT-037 记录**逐字节相同**；
> `git status` 对 `modules/mcp_server/docs/**` 无任何条目。
> 改动只落在 `modules/mcp_server/**`（16 个文件，见 §0）。

## 0. status / commits

- **status：`done`**（五道门 + 门⑥ 三段式全绿；三条零行为变化对照全绿；真实追踪样例已产出）。
- **commits**：
  - **`39a4e59b54`** — `feat(mcp_server): TASK-038 opt-in server side call trace`
    （16 files changed, 2468 insertions(+), 31 deletions(-)）。
    **这是承载全部代码与本文全部结论的锚点（D86）**：运行中的二进制绑定它 ——
    `git rev-parse --short HEAD` = `39a4e59b54`，`bin\godot.windows.editor.x86_64.console.exe --version`
    = `4.8.dev.custom_build.39a4e59b5`。
  - 提交后按门纪律**重建并复跑全部门**（§5 的每个数字都是这次重建之后复跑的）。
  - 本报告自身作为**仅文档**的 follow-up 提交落地（`git diff --stat <代码提交> <文档提交>` 只含本文件；
    对 `modules/mcp_server/{tools,tests,mcp_*.cpp,mcp_*.h}` 为空）。**本报告不引用承载它自己的那条提交的 sha**
    （REPORT-037 §12 第 7 条记录过这个自引用环），用提交标题定位即可；被测代码的锚点仍是 `39a4e59b54`。
- 工作树收尾只应剩既有未跟踪物：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`（实测一致）。

## 1. 开关与默认值（GDR-4 端口解析的先例）

| 优先级 | 形式 | 说明 |
|---|---|---|
| ① | `--mcp-trace=<path>` / `--mcp-trace <path>` | 与 `--mcp-port=N` / `--mcp-port N` 同形；**命令行上最后一条胜出**（与端口一致） |
| ② | `ProjectSettings: godot_mcp/trace_file`（同时接受点号别名 `godot_mcp.trace_file`） | 仅当它是 `STRING` 且非空 |
| ③ | **默认：关闭** | 不打开文件、不构造任何记录、`MCPHttpServer` 拿不到 recorder |

- **空值不启用**：`--mcp-trace=`（空值）、`--mcp-trace`（后面没有值）、`--mcp-trace --headless`（下一个是开关）都**不启用**。
- 关掉时启动日志一行：`[MCP] trace=off (default; use --mcp-trace=<path> or godot_mcp/trace_file to enable)`；
  打开时：`[MCP] trace enabled: file=<path> (records initialize / tools/list / every tools/call; arguments may contain project content)`
  —— 后半句就是任务书 §1.4 要求的**隐私提示**（"它会写下调用参数（可能含工程内容）"）。
- 开不了文件时：`WARN_PRINT` 一次（stderr）+ 启动日志一行 `[MCP] trace requested for '<path>' but disabled`；
  **工具调用照旧**（§9）。
- 默认关闭的**实测**：不传开关的编辑器在 9888 上跑了 3 条请求（initialize / tools/list / tools/call）后，
  指定路径**不存在**：`trace path C:\...\mcp038-trace-sample.jsonl exists=False after 3 requests`（`default_off_writes_no_file` PASS）。

## 2. 一行 JSON 的字段表

每次 `POST /mcp` 的 JSON-RPC 请求写**一行**（`JSON::stringify` 的紧凑形式 + `\n`；`id` 用请求里的**原样 token** 拼接，
所以 `1` 仍是数字、`"a"` 仍是字符串，观测者可以拿它和客户端自己的请求对齐）。

| 字段 | 何时出现 | 类型 | 含义 |
|---|---|---|---|
| `seq` | 总是 | int | 进程内单调递增，从 1 开始（**每次启动重新计数**） |
| `ts_ms` | 总是 | int | 墙钟（Unix epoch 毫秒），供跨进程排序 |
| `connection` | 总是 | int | 连接标识（`MCPHttpServer::Connection::id`，进程内唯一且不复用） |
| `id` | 总是 | 原样 | 请求的 JSON-RPC `id` token（不可解析为 JSON 值时写 `null`） |
| `method` | 总是 | string | JSON-RPC 方法名；**载荷整体解析失败时为 `""`**（`-32700`/`-32600` 也留痕） |
| `ok` | 总是 | bool | 这次调用成功了吗 |
| `error_code` | 总是 | int | 0 或 JSON-RPC 错误码（`-32001`/`-32602`/`-32600`/`-32601`/`-32603`/`-32700`/`-32000`） |
| `error_message` | 总是 | string | 错误消息（截断到 512 字节，UTF-8 边界对齐） |
| `error_message_truncated` | 总是 | bool | 上面是否被截断 |
| `duration_ms` | 总是 | int | 从**读到请求**到**产出响应**的墙钟毫秒 |
| `result_bytes` | 总是 | int | 完整 JSON-RPC **响应体**的 UTF-8 字节数（`notifications/initialized` 的 202 空体为 0） |
| `tool` | `method=="tools/call"` | string | `params.name`，**在查注册表之前就记下** —— 不存在的工具名是缺失工具线索 |
| `args` | `method=="tools/call"` | string | `params.arguments` 的规范 JSON（键排序）；超过 4096 字节截断 |
| `args_bytes` | `method=="tools/call"` | int | **截断前**的真实 UTF-8 字节数 |
| `args_truncated` | `method=="tools/call"` | bool | `args` 是否被截断 |
| `tools` | `method=="tools/list"` | int | 返回的工具条数（**紧凑形式：不落全量 list**） |
| `pending_ms` | 走延迟通道时 | int | 在延迟通道里等待的墙钟毫秒 |
| `timeout_ms` | 走延迟通道时 | int | 当时武装的截止时间（0 = 无截止）；用于判"pending 超上限" |

> `initialize` / `tools/list` / 其它 method 都是**同一张表减去 `tool`/`args*`**（`tools/list` 额外带 `tools`）。
> 只有 `POST /mcp` 且进到 sink 的请求才记；HTTP 框架级失败（404/405/413/431/缺 `Content-Length`…）在 sink 之外，**不记**（§10）。

## 3. 引擎依据（为什么这样落）

| 设计点 | 引擎依据 | 结论 |
|---|---|---|
| 开关与优先级 | `mcp_server.cpp` 的 `MCPPort::parse`（GDR-4） | 逐字沿用「命令行 > ProjectSettings > 默认」，连「最后一条命令行胜出」都一致 |
| 一请求一行 | `JSON::stringify` 会转义换行，`FileAccess::store_string` 一次写一整行 | **行天然不可撕裂**：整个泵（读 socket → 解析 → 执行工具 → 写回）都在 `MCPServer::pump_frame` 的**主线程一帧**里，多连接只是**连续两行**，不存在交错写 |
| 只追加 | `FileAccess` 没有 APPEND 模式；`READ_WRITE`(rb+) + 一次 `seek_end()` | 追加而不截断；重开同一文件是**扩展**（有 doctest 钉住） |
| **绕开 safe save** | `drivers/windows/file_access_windows.cpp:197-216`：`is_backup_save_enabled() && p_mode_flags == WRITE` 时写 `<path><ticks>.tmp`，**只在 close 时改名** | 编辑器进程开着 safe save，用它就会：（a）进程存活期间目标文件根本不存在，（b）**被 kill 时一行都不落盘**。实测踩到（见 §9.1）。改用 `WRITE_READ`(wb+) 创建 + `READ_WRITE`(rb+) 持有 |
| **并发可读** | 同文件 `:218`：`is_backup_save_enabled()` 时非 READ 句柄用 `_SH_DENYRW`（独占） | 独占会让「观察者在被观察进程运行时读」不可能。`open()` 期间把 `FileAccess::set_backup_save(false)`、**返回前恢复**（主线程、`open()` 不重入任何开文件代码），句柄于是是 `_SH_DENYNO`；`analyzer` 那样**非 Godot 读者**可并发打开 |
| flush 每行 | `FileAccess::flush()` → `fflush` | 观测者可以边跑边 tail；崩溃/强杀也保住已写的行 |
| 写失败自禁 | 无异常可逃逸：`record()` 返回 `void`，失败路径只 `WARN_PRINT` 一次 + 关闭句柄 | 工具调用路径**不可能**因追踪失败而改变 |
| 延迟通道 | `MCPDeferred::Queue` 以 `(connection, id)` 为键、`Completion` 携带终局 | 追踪记录**跟着请求走**，延迟请求的行在**它真正结束时**写（带真实 `pending_ms`/`timeout_ms`），而不是在被接受时写 |
| 零行为变化 | `MCPJsonRpc::dispatch(..., p_trace=false)` 默认关；`MCPHttpServer::set_trace_recorder(nullptr)` 默认关 | 关闭时 JSON-RPC 层**不做任何字符串工作**（不 stringify 参数），传输层连 `OS::get_ticks_msec()` 都不读 |

## 4. 红 / 绿（TDD）

**红（测试先写）**：`scripts/build_local.cmd -Force`（从 cmd 启动，串行，不抑制输出），构建日志
`%TEMP%\mcp_server_build_local.log` 的第 130 段（`===== build_local START ... 2026/09/23 21:43:12.35 =====`）：

```
scons: *** [bin\obj\tests\test_main.windows.editor.x86_64.obj] Error 2
.\modules/mcp_server/tests/test_mcp_server.h(20449): error C2653: "MCPTrace": 不是类或命名空间名称
.\modules/mcp_server/tests/test_mcp_server.h(20449): error C4430: 缺少类型说明符 - 假定为 int
.\modules/mcp_server/tests/test_mcp_server.h(20465): error C2653: "MCPTrace": 不是类或命名空间名称
...
EXIT_CODE=2
```

该段共 138 行、**109 个 `error C…`，全部 109 个都在 `tests/test_mcp_server.h`**（机器统计：按文件分桶，
`109 modules/mcp_server/tests/test_mcp_server.h`，0 其它文件），是 `MCPTrace` 未声明引发的级联。
这是 C++ 里诚实的红阶段形态：用例先于实现存在，构建以"未声明符号"失败 —— 它同时证明了用例确实进了 `tests_main` 的编译单元。

> 引用说明：MSVC 的中文诊断在 GBK 控制台下显示为乱码，上面三行的**中文措辞**是按诊断语义转写的，
> **错误码（C2653/C4430/C2146/C2143/C2447）、行号（20449/20465/…）与文件名逐字来自日志**
> （原始日志：`%TEMP%\mcp_server_build_local.log` 第 130 段，可用 §5 的分段扫描脚本复读）。

**绿**：实现补齐后 `build_local.cmd -Force` → `exit code = 0`；门③ `272/272 passed / 15831/15831 assertions / 0 failed`（§5）。
**中间两轮红→绿**（实现期实测，同样如实给出）：

| 轮次 | 红的表现 | 根因 | 修法 |
|---|---|---|---|
| 1 | `mcp_trace.cpp(266): error C2666: operator != 不明确` | `JSON::parse_string()` 返回**解析后的 `Variant`**，不是 `Error` | 改用 `JSON::parse()`（同 `mcp_jsonrpc.cpp` 的用法） |
| 2 | `CHECK(Task038::read_lines(path).size() == 1)` 失败 | **safe save**：文件只在 close 后才出现（§9.1） | 绕开 safe save（§3 第 4 行）+ 新增一条专门钉住它的用例 |
| 3 | `REQUIRE(completions.size() == 1)` 失败后**用例崩溃**（SEH） | PLAYBOOK §7.6：本 harness 的 `REQUIRE` 不中止用例，`completions[0]` 越界 | `ticks=1` + 读前显式守卫 |
| 4 | 同上 `read_lines == 1` 仍失败 | Godot 自己的 `READ` 句柄在 safe save 下取 `_SH_DENYWR`，与已开的写句柄互斥（**是读者的属性，不是追踪文件的**） | 该用例只在这一次读取期间把 safe save 调低，并把这条事实写进注释 |

## 5. 门（全部真实输出与退出码；全部在绑定 `39a4e59b54` 的二进制上复跑）

第 0 步（从 cmd 启动、串行、不抑制输出）：

```
modules\mcp_server\scripts\build_local.cmd -Force   -> build_local: exit code = 0
git rev-parse --short HEAD                          -> 39a4e59b54
bin\godot.windows.editor.x86_64.console.exe --version -> 4.8.dev.custom_build.39a4e59b5
```

| 门 | 命令 | 结果 | 退出码 |
|---|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group project_read_template` | `editor_9888_contract_subset` PASS、`game_9889_contract_subset` PASS、`guard_user_port_9877` PASS = **3/3**；`editor set: 148 tool(s)` / `game set: 69 tool(s)` / `scope: editor-only=102 game-only=23 both/shared=46`（与 REPORT-036 记录一致） | 0 |
| ② 三类证据 | 本批**不新增工具**，任务书 §2 要求的证据是 §6 的三条零行为变化对照 + §7 的真实追踪样例 | 三条对照全绿（§6）、样例 12/12（§7） | 0 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | `272/272 passed / 15831/15831 assertions / 0 failed`（基线 262 → 新增 10 条 TASK-038 用例） | 0 |
| ④ 全引擎回归 | `--headless --test` | `1698/1698 passed / 440113/440113 assertions / 0 failed`（基线 1688 → +10，只增） | 0 |
| ⑤ 每批收口 | `accept_m1.ps1` **连跑两次** | 两次各 **22/22 cases passed**；两份 `PASS  …` 清单 `Compare-Object` 空（`run1=22 run2=22 diff_count=0`）；两次都打印 `implemented tools = 148 (editor) / 69 (game); contract = 171` | 0 / 0 |
| ⑥ 收窄点（三段式） | `check_narrowing_points.py` | `scanned 71 == pinned 71`，17 个文件，PASS（本批**未新增任何收窄点**：`git status` 对 `tools/**` 为空） | 0 |
| ⑥ | `check_narrowing_points.py --coverage` | 17 种已声明拼写；`--coverage` 四项边界照旧打印 | 0 |
| ⑥ | `mcp031_gate6_coverage_probes.ps1` | **101/101 checks passed**（`log sha256=65ec2c3f92ab834ef43f40597ed7919946021fe0636fad5dccdc7d396d3417ab`） | 0 |

> 门⑥ 备注（**非本批引入，如实记录**）：`check_narrowing_points.py` 报告 **4 个 pinned 行号漂移**
> （`editor_animation_tree_write.cpp` G24-ANIM-POSITION、`project_theme_write.cpp` G24-THEME-STYLEBOX-DEFAULT ×2、
> `tool_helpers.cpp` G24-THE-GATE）。pin 是按"marker id + 文件内出现次序"匹配的，脚本自己说明**这不是失败**；
> 这些文件本批**一个字节都没动**，所以漂移是 HEAD 上既有的（TASK-037 的编辑落在 pin 之后）。建议下一批顺手刷新。

## 6. 零行为变化的三条对照

### 6.1 关闭时 vs **TASK-038 之前的二进制**：22/22 逐字节相同（含全量 `tools/list`）

做法（可复现）：用 `git checkout HEAD -- <8 个实现文件>` + 移走两个新文件，**只还原到 HEAD 源码**，
`build_local.cmd -Force` 得到**任务之前的二进制**（`--version` 仍是 `b6476fc48`，因为版本串只嵌 commit hash），
用同一个 scratch 工程、同一组 22 个探针（`scripts/mcp038_probes.ps1`）跑一遍并逐条算 sha256；
再还原本批源码、重建，跑第二遍。`scripts/mcp038_baseline_compare.ps1 -Mode compare`：

```
22 identical, 0 different, 22 probes
  [SAME] tools/list                               F2B8D51511EE5AA1
  [SAME] project_get_info                         B0E800E6D1C29A77
  [SAME] project_read_script missing              CA091E38ECE90086
  [SAME] project_get_info unknown argument        54357D3A81EA54A8
  [SAME] unknown tool                             71ACDC800F58A4DB
  [SAME] unknown method                           C598B249E42AAA99
  ...（22 条全部 SAME，完整表见 %TEMP%\mcp038_cmp2.txt）
```

### 6.2 开启 vs 关闭：22 个探针逐字节相同，且**先跑了两遍关闭做对照**

`scripts/mcp038_zero_change.ps1`：run A（关）→ run B（关，对照组）→ run C（开 `--mcp-trace`），
每条响应 `curl.exe -s -o <file>` 落盘 + sha256：

```
probe response sha256 (first 16 hex digits):
  initialize                               03BF3A11CDEF472B  off=on
  tools/list                               F2B8D51511EE5AA1  off=on
  ...（22 条全部 off=on）
[PASS] deterministic_control_run   stable=22 unstable=0
[PASS] trace_does_not_change_any_stable_probe  compared=22 changed=0
[PASS] tools_list_is_stable_and_complete  editor tools=148 sha_off_a=F2B8D515… sha_off_b=F2B8D515… sha_on=F2B8D515…
[PASS] startup_log_says_off_for_runs_ab / startup_log_says_on_for_run_c
[PASS] guard_user_port_9877  pid_before=76048 pid_after=76048
7/7 checks passed; probes=22 stable=22 changed=0 unstable=0
```

> 对照组的价值：如果某条响应本来就不确定（不同进程间会变），它会在 A vs B 先被判为 non-deterministic 并**排除**，
> 而不是被记成"追踪改变了行为"。本批 22 条**全部**是稳定的，所以"0 changed"不是靠排除换来的。
> 探针覆盖：`initialize` / `tools/list`（148 条全量）/ `ping` / 14 个成功工具调用 / `-32001`（资源不存在）/
> `-32602`（缺参、未知参数）/ `-32601`（未知工具、未知方法）—— 22 条中 **17 条成功、5 条错误**
> （任务书要求抽 ≥10 个工具，本组覆盖 15 个不同工具）。

### 6.3 门① 在两个端点上仍逐字通过

见 §5 门①：`editor_9888` / `game_9889` 各条 `name`/`description`/`inputSchema` 逐字 `True`，
"implemented 并集 − editor-only/game-only"双向成立，3/3 PASS。

## 7. 真实追踪样例（含**故意构造**的摩擦）与分析器输出

`scripts/mcp038_trace_evidence.ps1` 自己驱动 10 次调用（1 次就绪探针 + 9 次刻意编排），真实产出如下。

**原始 10 行**（`%TEMP%\mcp038-trace-sample.jsonl`，此处原样粘贴；`ts_ms` 是墙钟毫秒）：

```json
{"id":900,"connection":1,"duration_ms":0,"error_code":0,"error_message":"","error_message_truncated":false,"method":"initialize","ok":true,"result_bytes":183,"seq":1,"ts_ms":1790173070931}
{"id":1,"connection":2,"duration_ms":0,"error_code":0,"error_message":"","error_message_truncated":false,"method":"initialize","ok":true,"result_bytes":181,"seq":2,"ts_ms":1790173070958}
{"id":2,"connection":3,"duration_ms":2,"error_code":0,"error_message":"","error_message_truncated":false,"method":"tools/list","ok":true,"result_bytes":43186,"seq":3,"tools":148,"ts_ms":1790173070981}
{"id":3,"args":"{}","args_bytes":2,"args_truncated":false,"connection":4,"duration_ms":0,"error_code":0,"error_message":"","error_message_truncated":false,"method":"tools/call","ok":true,"result_bytes":183,"seq":4,"tool":"project_get_info","ts_ms":1790173071005}
{"id":4,"args":"{\"path\":\"res://no_such_script_038.gd\"}","args_bytes":38,"args_truncated":false,"connection":5,"duration_ms":0,"error_code":-32001,"error_message":"File 'res://no_such_script_038.gd' not found","error_message_truncated":false,"method":"tools/call","ok":false,"result_bytes":194,"seq":5,"tool":"project_read_script","ts_ms":1790173071027}
{"id":5,"args":"{\"path\":\"res://scripts/hello.gd\"}","args_bytes":33,"args_truncated":false,"connection":6,"duration_ms":0,"error_code":0,"error_message":"","error_message_truncated":false,"method":"tools/call","ok":true,"result_bytes":191,"seq":6,"tool":"project_read_script","ts_ms":1790173071047}
{"id":6,"args":"{}","args_bytes":2,"args_truncated":false,"connection":7,"duration_ms":0,"error_code":-32601,"error_message":"Method not found: project_get_no_such_tool_038","error_message_truncated":false,"method":"tools/call","ok":false,"result_bytes":107,"seq":7,"tool":"project_get_no_such_tool_038","ts_ms":1790173071075}
{"id":7,"args":"{\"bogus_argument\":1.0}","args_bytes":22,"args_truncated":false,"connection":8,"duration_ms":0,"error_code":-32602,"error_message":"Unknown parameter 'bogus_argument' for tool 'project_get_info'","error_message_truncated":false,"method":"tools/call","ok":false,"result_bytes":186,"seq":8,"tool":"project_get_info","ts_ms":1790173071097}
{"id":8,"args":"{}","args_bytes":2,"args_truncated":false,"connection":9,"duration_ms":3,"error_code":0,"error_message":"","error_message_truncated":false,"method":"tools/call","ok":true,"result_bytes":261,"seq":9,"tool":"project_get_statistics","ts_ms":1790173071121}
{"id":9,"args":"{}","args_bytes":2,"args_truncated":false,"connection":10,"duration_ms":0,"error_code":0,"error_message":"","error_message_truncated":false,"method":"tools/call","ok":true,"result_bytes":183,"seq":10,"tool":"project_get_info","ts_ms":1790173071145}
```

**`python scripts/analyze_mcp_trace.py <trace>` 的真实输出**：

```
trace: 10 JSON-RPC request(s), 7 tools/call, 3 failed
methods: tools/call=7, initialize=2, tools/list=1
seq 1..10, connection(s): [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
wall span (from ts_ms): 214 ms

== friction ==
  fail->success  project_read_script: seq 5 failed with -32001 (File 'res://no_such_script_038.gd' not found), seq 6 succeeded
                 failed args: "{\"path\":\"res://no_such_script_038.gd\"}"
  fail->success  project_get_info: seq 8 failed with -32602 (Unknown parameter 'bogus_argument' for tool 'project_get_info'), seq 10 succeeded
                 failed args: "{\"bogus_argument\":1.0}"
  repeated       project_get_info x2 "{}"
  error codes    {"-32001": 1, "-32601": 1, "-32602": 1}
                 project_get_info: {"-32602": 1}
                 project_get_no_such_tool_038: {"-32601": 1}
                 project_read_script: {"-32001": 1}

== missing tool clues ==
  -32601         project_get_no_such_tool_038 (seq 7)
  probed args    none

== mergeable call sequences ==
  bigrams: none repeated
  trigrams: none repeated

== anomalies ==
  timeouts       0
  pending over ceiling  0
  large responses       0
  dominant tool  project_get_info: 3/7 calls (42.9%)
```

→ **摩擦信号真的抓到了**：两条"先失败后成功"（一条 `-32001` 资源不存在、一条 `-32602` 未知参数）、
一条重复同参调用、`-32601` 缺失工具线索、以及"单一工具占比 42.9% > 30%"的异常。
脚本同时断言这四件事（`analyzer_reports_the_fail_then_success` / `…_missing_tool` / `…_error_distribution` /
`analyzer_exit_code_is_zero`），并落 JSON 到 `%TEMP%\mcp038-trace-analysis.json`。
**证据脚本自身 12/12 PASS**（含"关闭时不写文件"与"9877 pid 不变"）。

> 样例里 `connection` 是 1..10：每次 `curl` 都是新连接。`connection` 相同才是"同一会话内的连续步骤"，
> 分析器的 n-gram 因此**只在同一 connection 内**统计（不同客户端不是一条工作流）。

## 8. `scripts/analyze_mcp_trace.py`：信号定义与它们的**边界**

输入是 JSON Lines；坏行**不致命**（计入 `bad_lines`，继续分析）。输出 = 人可读摘要 + JSON（`--json <path>` 写文件）。

| 组 | 信号 | 判据（可调参数） |
|---|---|---|
| 摩擦 | `fail_then_success` | 某工具的**失败**调用之后 `--window`（默认 12）次调用内，**同一工具**出现成功调用；带失败参数与两次 `seq` |
| | `repeated_same_args` | 同 `tool` + **规范化后的同一 `args`**（`json.dumps(sort_keys=True)`）出现 ≥2 次 |
| | `error_code_distribution` / `…_by_tool` | 失败调用的错误码分布（总体 + 按工具） |
| 缺失工具 | `method_not_found` | `tools/call` 上 `-32601` 的工具名（注册表里根本没有，或属于另一个进程） |
| | `probed_argument_names` | 某参数名在**失败**调用里出现 `--probe-min`（默认 2）次以上、且在**任何成功**调用里 **0** 次 → "被反复试探" |
| 可合并 | `unigrams`/`bigrams`/`trigrams` | **同一 connection 内**按 `seq` 的工具序列 n-gram 频次（默认输出前 10） |
| 异常 | `timeouts` | `error_code == -32000` 且带 `pending_ms`（即延迟通道超时） |
| | `pending_over_ceiling` | `pending_ms > timeout_ms`（`timeout_ms>0`） |
| | `large_responses` | `result_bytes > --max-result-bytes`（默认 1 MiB） |
| | `dominant_tool` | 单一工具占 `tools/call` 总数 **> `--dominance`**（默认 0.30） |
| | `parse_errors` | `method==""` 且 `ok=false` 的载荷（`-32700`/`-32600`） |

**边界（必须写清楚，避免观察者过度解读）**：这些是**启发式**，不是契约。
"先失败后成功"不等于"工具有缺陷"（可能是调用方打错字）；`probed_argument_names` 只覆盖**解析出来是对象**的 `args`
（被截断的 `args` 仍参与键提取，但只看到前缀里的键）；"可合并"只统计同一连接的相邻序列，
**跨连接的长时间工作流不会被发现**；`dominant_tool` 在只有 3 次调用的会话里天然容易触发（样例即是）。

## 9. 健壮性证据（写失败不得影响工具调用 / 只追加 / flush / 不撕裂）

### 9.1 实测踩到的真缺陷：**safe save 让追踪文件"运行期间不存在"**

第一次实地跑证据脚本时：日志说 `[MCP] trace enabled: file=C:\...\mcp038-trace-sample.jsonl`（即 `open()` 成功），
但进程停下后**目标文件不存在**，`%TEMP%` 里只多了一个 `mcp038-trace-sample.jsonl2725113.tmp`。
根因见 §3 第 4 行：编辑器进程开着 safe save，`FileAccess::open(..., WRITE)` 写临时文件、**只在 close 时改名**，
而证据脚本是 `Stop-Process -Force`（正是所有测试脚本的做法）→ 一行都不落盘。
这正是任务书里"实时/流式证据"要防的事，**doctest 抓不到**（doctest 进程不启用 safe save），只有实地证据抓到了。
修法：绕开 safe save（`WRITE_READ` 创建 + `READ_WRITE` 持有），并新增用例
`[MCPServer] TASK-038: the trace file is readable while the recorder is still open`（在用例里**把 safe save 打开**
再断言"文件立刻存在、行在 close 之前就在盘上、不留 `.tmp`"）—— 即让这条回归**能被机器抓住**。

### 9.2 单元级（doctest，10 条 TASK-038 用例）

| 契约 | 用例 | 断言要点 |
|---|---|---|
| 默认关闭 | `…the trace switch is off by default…` | 无开关/无设置 → off；空设置不启用；命令行两种形式；空值/缺值/下一个是开关 → 都不启用；最后一条命令行胜出 |
| 关闭即空转 | `…a recorder that was never opened writes nothing` | 未 `open()` 时 `record()` **不创建文件**、`lines_written==0`（用一个 `traceable=true` 的记录证明门槛在开关而不是记录） |
| 一行一请求 / 只追加 / 字段齐全 | `…the trace is JSON Lines, appends, and describes the call` | 4 行（跨两次 open，第二次**追加**）；每行可解析；`seq` 1..3 后重新从 1（进程内计数）；`ts_ms` 非降；`id` 原样（数字保持数字、字符串保持字符串）；`tools` 只在 `tools/list`；`tool`/`args` 只在 `tools/call`；`pending_ms`/`timeout_ms` 只在延迟调用；`\n` 计数 == 行数 |
| 截断 | `…long arguments are truncated to a decodable prefix` | `args_bytes` 是**真实**长度；`args_truncated=true`；记录下来的前缀 ≤ 上限、是原文前缀、**不含 U+FFFD**（UTF-8 边界回退） |
| 写失败自禁 | `…a failed write disables the trace once and keeps the earlier lines` | 注入第 3 次写失败后：`is_active()==false`、`is_disabled_after_failure()==true`、`lines_written` 停在 2、**文件仍是前 2 行**（不截断）、之后的 `record()` 全部 no-op |
| 开不了文件 | `…an unusable path disables the trace…` | `open()` 返回 false、自禁、不产生文件、之后 `record()` 惰性 |
| safe save / 并发可读 | `…the trace file is readable while the recorder is still open` | 打开 safe save 后仍：文件立刻存在、行在 close 前可读、文件以 `\n` 结尾、无 `.tmp` 残留；重开是追加（2 行） |
| dispatch 只在被要求时描述 | `…dispatch describes a request only when the trace asks for it` | 关：`traceable==false`；开：`method/tool/args/id/ok/code` 正确，且**响应与关闭时逐字节相同**；未知工具记名 + `-32601`；未知参数 `-32602`；`tools/list` 记 `tools` 计数；`initialize`；`-32700`；`-32600`（`id` 仍记下） |
| 延迟调用 | `…a deferred call carries its trace to the completion` | `deferred=true`、`timeout_ms` == 下发时武装的截止；`Queue` 完成后 `Completion.trace` 带回工具名与 `start_ms` |
| 传输层默认 | `…the transport's outcome carries an untraceable record by default` | `MCPHttpOutcome.trace` 默认 `traceable==false` |

**多连接交错不撕裂**：整个 HTTP 泵与工具执行都在主线程、`MCPServer::pump_frame` 一帧内完成
（`mcp_http_server.cpp` 的 `poll()` 是唯一的驱动点，模块不建线程 —— REQUIREMENTS C2）。
一次 `record()` 就是一次 `store_string(整行 + "\n")`，没有"两个写者拼一行"的可能；
同一帧里的两条连接只会产生**两个连续的行**。`connection` 字段让观测者能把它们分回各自的会话。
（`mcp_deferred.cpp` 的 `Queue` 自持 `(connection, id)` 键，见 GDR-20。）

## 10. 已知边界与**未覆盖**（不粉饰）

1. **只记 sink 收到的 JSON-RPC 请求**：HTTP 框架级失败（404/405/413/431/400 裸 LF/缺 `Content-Length`）在
   `MCPHttpRequestSink` 之外产生，**不记**。要连这些也记，得把 recorder 下沉到 `MCPHttpServer` 的框架层，
   本批按任务书 §1.2 的范围（`tools/call` + `initialize`/`tools/list`）做到"每个 JSON-RPC 请求一条"。
2. **连接在延迟请求完成前消失 → 没有行**：`Queue::drop_connection()` 释放条目，客户端也没拿到响应。
   这类"被放弃的等待"是本追踪的盲区（`pending_over_ceiling` 只能看已完成的那些）。
3. **文本字段单位**：`args_bytes`/`result_bytes`/`error_message` 截断上限都是 **UTF-8 字节**
   （PLAYBOOK §6.9 的要求）；`error_message` 与 `args` 的截断按 UTF-8 边界回退，不会留半个字符。
4. **`args` 是规范化后的形态**（`JSON::stringify`，键排序），不是请求原文的子串：
   `{"b":1,"a":2}` 与 `{"a":2,"b":1}` 在追踪里**同形**（这正是"重复相同参数"能工作的前提），
   代价是**丢失键序与空白**。数字经 Godot JSON 解析后一律是 double，所以 `1` 会记成 `1.0`（样例第 8 行可见）。
5. **`seq` 是进程内的**：跨进程不连续（样例里第 4 行 `seq` 重新从 1 开始，因为那是第二次 `open()`）。
   跨进程排序请用 `ts_ms`。
6. **隐私**：追踪文件会写下**工具参数**（可能含工程内容）与**错误消息**。默认关闭；开启时启动日志明确提示；
   开关是本地调试旁路，**不进入** `tools/list` 契约、**不进入** `GET /mcp` 的状态体（后者是既有契约，本批一字未动）。
7. **`tools/**` 之外的源码不在门⑥ 的扫描范围**：新增的 `mcp_trace.cpp` 里没有任何收窄点
   （无 `real_t`/`float`/`Color(`/`Vector2(` 等），`scanned` 仍是 71。

## 11. 给决策者的**规范落笔请求**（`DESIGN-DETAIL` 由你落笔，我不动）

建议新增一节（例如 **§23 / GDR-25「可选的服务端调用追踪」**），内容按下面写：

1. **开关与优先级**：`--mcp-trace=<path>`（及空格形式）> `ProjectSettings: godot_mcp/trace_file` >
   **默认关闭且不写任何文件**；空值/缺值不启用；命令行最后一条胜出（与 GDR-4 的端口同构）。
2. **产物契约**：JSON Lines，一行一条 `POST /mcp` 的 JSON-RPC 请求；字段表用 §2 那张表（含
   `seq/ts_ms/connection/id/method/tool/args/args_bytes/args_truncated/ok/error_code/error_message/
   error_message_truncated/duration_ms/result_bytes/tools/pending_ms/timeout_ms` 与各自的出现条件）。
   明确"`id` 是**原样 token**"（保住数字/字符串类型）与"`args` 是规范化 JSON"这两条。
3. **零行为变化是硬条款**：关闭时不得做任何追踪工作（不 stringify 参数、不读时钟、不开文件）；
   开启时 `tools/list` 与任何工具响应**逐字节不变**。**门的形态**：≥10 个工具 + 全量 `tools/list`，
   在（关、关、开）三次运行间逐字节比对；**必须**有"关-关"对照组，把端点本身的不确定性排除而不是记成差异。
4. **与 TASK-038 之前的二进制对照**（推荐写进规范作为"新增旁路能力"的证据模板）：
   还原到 HEAD 源码建一个任务前二进制，同一组探针逐条 sha256 比对。
5. **健壮性**：写失败/开不了文件 → **只警告一次并自禁**，工具调用不受影响；只追加；
   每行 flush；退出时 flush；**不得使用 Godot 的 safe save 路径**（否则运行期间文件不存在、被 kill 时全丢），
   并**不得让句柄独占**（否则观察者无法在被观察进程运行时读取）；一行一次写入 → 行不撕裂（主线程单帧）。
6. **隐私与边界**：追踪文件含调用参数，可能含工程内容；默认关闭 + 启动日志提示；
   追踪**不属于** `tools/list` / `GET /mcp` 契约（两者本批一字未改）；
   只覆盖 sink 收到的 JSON-RPC 请求（HTTP 框架级失败不记）；
   连接在延迟完成前消失的请求**不产生行**。
7. **观察者工具不是契约**：`scripts/analyze_mcp_trace.py` 的启发式判据（窗口、阈值、n-gram 口径）
   允许随观察需要调整，**不得**被当成工具行为契约引用。

**另一条（PLAYBOOK 级别，同样请你落笔）**：`scripts/import_guard` 的用法里要写明
**`Import-McpProject -NoPort` 与 `--mcp-port=0` 不是一回事**：`-NoPort` 是"不传端口参数"，
而编辑器进程**不传端口就是默认 9877** —— 实测某次 `--import` 的引擎日志出现
`[MCP] role=editor configured_port=9877 source=default listen=true` 与 `bind failed on 127.0.0.1:9877`。
`-NoPort` 因此会**尝试占用用户编辑器的端口**（本次因 9877 已被用户编辑器持有而只是绑定失败，
且三次独立运行的前后 pid 守卫都显示 9877 **从未易主**）。本批已把三个证据脚本改成用助手默认的
`--mcp-port=0`，并把这条写进脚本注释。

## 12. 环境与流程事实（供后续批次直接照用）

1. **用户 Godot 在本批期间重启过**：`9877` 的持有者从 `PID 36392`（本批前三段证据）变成
   `PID 76048`（`Godot_v4.7.1-stable_mono_win64.exe`，`tasklist` 实测）。两条都是用户进程，**本批从未占用/杀/重启 9877**；
   每次运行都记录"运行前后 9877 的 pid 不变"（`guard_user_port_9877` PASS，`pid_before=76048 pid_after=76048`）。
   测试端口固定 9888（编辑器）/9889（游戏），追踪文件全部落在 `%TEMP%`。
2. **构建很快**：一次增量 `-Force` 重建约 20–90 s（SCons 只重编改动的 TU + `test_main`），
   所以"红/绿两阶段各建一次"与"还原到 HEAD 建一次任务前二进制"都是可负担的。
3. **`build_local.cmd` 的日志是 UTF-8（无 BOM）**，但其行内中文在 GBK 控制台下会 `UnicodeEncodeError`；
   解析日志请显式用 UTF-8 并只打 ASCII。
4. **PowerShell 5.1 的 `Set-Content` 处理 `$` 变量**：本批一次 `-replace | Set-Content` 把脚本里
   `(Join-Path $ProjectPath 'scripts\hello.gd')` 变成了 `(Join-Path  'scripts\hello.gd')`（`$ProjectPath` 被外层展开掉）。
   脚本改动一律用文件编辑工具，不要用 `powershell -Command` 里的字符串替换。
5. **证据落盘一律 `curl.exe -s -o <file>` + sha256**（PLAYBOOK §7.1）；请求体一律 `ConvertTo-Json -Depth 10 -Compress`
   写进文件再 `--data-binary @file`。

## 13. deviations / blockers / next_step_recommendation

**deviations（逐条显式）**

1. **追踪的覆盖面比任务书字面更宽一格**：任务书点名 `tools/call`、`initialize`、`tools/list`；
   本实现记录**每一个进入 sink 的 JSON-RPC 请求**（含 `ping`、`notifications/initialized`、未知方法、
   `-32700`/`-32600` 载荷），用同一张字段表。理由：观察者要判"异常"就必须看得见非法/未知请求；
   代价只是几行噪声，且 `method==""` 本身就是信号。已在 §2 与 §10 声明。
2. **新增一个任务书未列出的字段 `timeout_ms`（延迟调用专用）**，并保留 `error_message_truncated`/`args_truncated`。
   理由：没有它就无法机器判定任务书 §1.6 要求的"`pending` 超上限"；截断标记让"被截断"不被误读成"原文如此"。
   字段表已在 §2 完整给出（任务书 §3 本就要求"一行 JSON 的字段表"）。
3. **`args` 用规范化 JSON 而不是请求原文切片**：使"同样参数"可判（§10.4）；代价是丢键序/空白、`1` → `1.0`。
4. **`open()` 期间临时把 `FileAccess::set_backup_save(false)` 再恢复**（§3）：不改用户的编辑器设置，
   但确实触碰了一个全局静态开关。理由与风险（主线程、`open()` 不重入）写在源码注释里；
   若不接受这个手法，替代方案是接受"追踪文件在编辑器进程里独占、只能事后读"（会削弱观察者的实时性）。
5. **三个证据脚本额外落成 `scripts/mcp038_*.ps1` + `scripts/analyze_mcp_trace.py`**：任务书只点名分析脚本；
   三个 ps1 是"零行为变化三条对照 + 真实样例"的可复跑载体（PLAYBOOK §4 要求门的真实输出与退出码）。
6. **`-NoPort` → `--mcp-port=0`** 的修正（§11 末 + §12）：本批前期三个证据脚本的 `--import` 曾尝试绑定 9877
   （日志有 `bind failed on 127.0.0.1:9877`），已修并记录；9877 的用户进程全程未受影响（pid 守卫三次通过）。

**blockers**：无。

**next_step_recommendation**

1. 本批已提交 `39a4e59b54`（承载全部代码），运行中二进制绑定它；本报告作为仅文档提交落地。
   `DECISIONS.md` 的对应条目由决策者写入（本 fork 内不维护竞争性决策日志）。
2. 建议由决策者落笔 §11 的 `DESIGN-DETAIL` 新节与 PLAYBOOK 的 `-NoPort` 条目，然后即可开跑
   **实机赛车游戏试测**：开发子代理用 MCP 工具实操，观察者用 `--mcp-trace` + `analyze_mcp_trace.py` 出摘要。
   建议观察者同时打开 `--mcp-trace`（编辑器端）与游戏端（`--mcp-port=<p> --mcp-trace=<path>`），
   并在试测前清空追踪文件以避免与分析脚本的"跨运行拼接"混淆（脚本按行分析，不区分运行；可用 `seq` 回绕与 `ts_ms` 断段）。
3. 门⑥ 的 4 个 pinned 行号漂移（§5 备注）建议下批顺手刷新，与本批无关。
4. 建议下一批考虑（**不在本批范围**）：把 HTTP 框架级失败也纳入追踪（§10.1），
   以及给"连接在延迟完成前消失"补一条 `abandoned` 行（§10.2）。
