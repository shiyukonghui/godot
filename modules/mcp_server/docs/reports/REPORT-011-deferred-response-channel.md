# REPORT-011 — 延迟响应通道（GDR-20）+ 4 个跨帧工具

任务书：`modules/mcp_server/docs/tasks/TASK-011-deferred-response-channel.md`
通用规范：`modules/mcp_server/docs/tasks/PLAYBOOK-group-port.md`（已完整阅读）
执行者：Godot 内置 MCP 模块实现工程师（TASK-011）
分支：`feature/mcp-server-module`（**未推送**）

## 0. 状态摘要

**commits**（英文提交信息，**未推送**）：

```
2cb36fa71e  mcp_server: the deferred response channel (GDR-20) and the frame/capture groups (TASK-011)
            mcp_deferred.{h,cpp} + MCPJsonRpc::dispatch() + MCPHttpServer 的 pending 表
            + tools/tool_helpers 的三处 verbatim hoist
            + tools/running_game_frame_observation.{h,cpp}（3 工具，deferred）
            + tools/running_game_capture.{h,cpp}（1 工具）
            + manifest / accept_m1 清单 / 生成器 / 6 个 doctest 用例

a7a860cae6  mcp_server: TASK-011 report and the corrected evidence script
            本报告 + 证据脚本 ④/注入用例的修正（只动 scripts/mcp011_deferred_evidence.ps1
            与 docs/reports/REPORT-011-*.md，不含代码改动）

640c4e7dc1  mcp_server: TASK-011 report - record gate 1 run twice per group and the report commit sha
            只补记门①的每組两次运行与上面两条 sha，不含代码改动

（本报告自身的后续补记提交以 `git log -- modules/mcp_server/docs/reports/REPORT-011-*.md` 为准；
其内容不会改变任何门或任何代码。）
```

| 项 | 结果 |
|---|---|
| `status` | **完成**：延迟响应通道（GDR-20）实现并证明；4 个工具移植完毕；五道门全绿 |
| 实现的工具数 | 4（`running_game_frame_observation` 3 + `running_game_capture` 1），已实现并集 48 → **52** |
| 端点 | 编辑器 9888 = **40**（不变），游戏 9889 = 31 → **35** |
| 门① 契约子集逐字 | 两组**各跑两次**（共 4 次运行）各 **3/3 PASS**（9888 与 9889 双向 + 9877 守卫） |
| 门② 三类证据 + 真实跨帧 | 游戏相 **21/21 PASS**、窗口相 **9/9 PASS**（见 §5/§7） |
| 门③ 模块 doctest | `[MCPServer]*`：**112/112 用例、2911/2911 断言全绿** |
| 门④ 全引擎回归 | `--headless --test`：**1538/1538 用例、427192/427192 断言，0 failed** |
| 门⑤ `accept_m1.ps1` ×2 | runA / runB 各 **22/22 PASS**，两次 PASS 清单**逐字节相同** |
| 5 类状态机 | doctest 6 个用例 + 线上 21 项检查（§2 / §2.3–2.5） |
| 对既有门无回归 | keep-alive / 流水线 / 413 / 431 / `Expect: 100-continue` / 并发 100 / 跨进程重启 / 连接回收 **全过**（§8） |
| 9877 纪律 | 每次运行前后断言用户编辑器 pid 仍为 **36392**（全部通过） |

---

## 1. 延迟通道的设计（GDR-20 的 8 条要求 → 落点）

| 要求 | 落点 | 证据 |
|---|---|---|
| 1. **保持「无 FIFO」**：pending 按 (连接, 请求 id) 关联，响应写回原连接 | `MCPDeferred::Queue` 的 `Entry{connection_id, id_json, …}`（`mcp_deferred.h:139-160`）是唯一的 pending 表；`Completion` 带 `connection_id`，`MCPHttpServer::_tick_pending()` 只按它找连接（`mcp_http_server.cpp:455-486`）。没有「按到达顺序配对」的队列 | doctest：3 个 pending 以 **非到达顺序**完成（连接 7 的 id 12 先于 id 10，连接 9 的 id 11 在两者之间），每个 completion 的 (connection, id) 与 body 载荷各自对上；线上：两条连接同时 pending，A(id 101) 成功、B(id 202) 超时，`crossed=False` |
| 2. **状态机归框架** | 工具只实现 `MCPDeferred::Task::tick()`；`MCPHttpServer` 逐帧推进、`MCPJsonRpc` 只负责 dispatch 交接与 wire 形状（`build_result_raw` / `build_error_raw`），工具不碰帧、不碰 envelope | 三个工具文件里没有一处 sleep / 帧循环；`pending_handler` 与 `handler` 由 builder 互斥 |
| 3. **绝不阻塞主线程** | `tick()` 契约明写非阻塞；实现里没有任何等待原语；超时由框架时钟判定，工具不 sleep | `running_game_find_node_when_available(timeout=2)` 的**实测耗时 2046 ms**，且期间 `ping` 27 ms、`execute_gdscript` 28 ms 正常作答 |
| 4. **每帧预算有上限、不饿死常规请求** | `pending_ticks_per_frame`（默认 8，`mcp_server/pending_ticks_per_frame`）传给 `Queue::tick()`；`poll()` 先派发请求、后推进 pending（`mcp_http_server.cpp:691-696`） | doctest：5 个「一次 tick 即完成」的 pending，budget=2 → 恰好 2 个完成、3 个仍在；budget=0 → 0 个；线上：pending=1 时 `ping` **27 ms** |
| 5. **超时默认 30 s（可配置），以 `-32000` + `data.suggestion` + `data.timeout_ms` 收尾** | `pending_timeout_ms`（默认 30000，`mcp_server/pending_timeout_ms`）；`_effective_timeout = min(工具自报, 框架上限)`（`mcp_jsonrpc.cpp`）；`MCPDeferred::make_timeout_error()` 合并 suggestion 与 timeout_ms | `{"code":-32000,"data":{"suggestion":"…","timeout_ms":2000},"message":"Deferred call timed out after 2000 ms: …"}`（真实响应，sha256 见 §6） |
| 6. **断连清理不泄漏，连接数与 pending 数可观测** | `_drop_connection()` 是唯一的连接释放点，且只在此调用 `pending_requests.drop_connection(id)`（`mcp_http_server.cpp:441-449`）；`GET /mcp` 暴露 `pending` 与 `pending_connections` | doctest：3 条（连接 1×2、连接 2×1）→ `drop_connection(1)` 后 pending=1 且 `fake_pending_live()` 恰好减 2；线上：pending 1→0、`pending_connections` 1→0 |
| 7. **帧时钟用 SceneTree 帧计数** | `MCPServer::pump_frame()` 读 `SceneTree::get_frame()` 传给 `poll(max_requests, frame)`；无 SceneTree 的进程（doctest）退回私有计数器以免诊断失真 | 采样响应里 `moved_frames` 逐帧递增；窗口相 `frames[].frame = 169/173/177`（间隔 4 帧） |
| 8. **先证明状态机，再用真实工具验证** | 受控假 pending 工具（`tests/test_mcp_server.cpp` 的 `project_get_fake_pending`，由参数驱动 tick 数/失败/超时），经**真实 dispatch 路径**进入队列 | §2 |

### 1.1 新增/改动的文件（框架）

- 新增 `mcp_deferred.h/.cpp`：`State` / `TickResult` / `Task` / `Completion` / `Queue` + `make_timeout_error()`。
  - `Queue` 还提供 `has_connection()`：传输层用它做**每连接**的响应顺序背压（见 1.2）与空闲回收豁免。
- `tool_registry.{h,cpp}`：`MCPToolDef::pending_handler` + `is_deferred()`；`is_deferred_tool()`；`call_deferred_tool()`；`call_tool()` 对 deferred 工具返回 `-32603`（拒绝而非单帧假答）。
- `tools/tool_builder.{h,cpp}`：`pending_handler()`；**同时声明两半**或**两半都不声明**都是构建失败。
- `mcp_jsonrpc.{h,cpp}`：`Dispatch`（`deferred` / `task` / `id_json` / `timeout_ms` / `tool_name`）+ `dispatch()`；`build_result_raw()` / `build_error_raw()`；`handle()` 保留为单帧入口，遇到 deferred 工具返回 `-32603` 并 `memdelete` 掉刚建出的 task。
- `mcp_http_server.{h,cpp}`：`MCPHttpOutcome`（sink 接口由「返回 body」改为「填充 outcome」）；`Connection::id`；`pending_requests`；`set_pending_timeout_ms()` / `set_pending_ticks_per_frame()` / `get_pending_count()` / `get_pending_connection_count()`；`poll(max_requests, frame)`；`_tick_pending()`；`_find_connection()`。
- `mcp_server.{h,cpp}`：`handle_jsonrpc_request()` 走 `dispatch()`；`build_deferred_body()` 是「帧管理（传输）」与「wire 形状（JSON-RPC）」的接缝；`pending_timeout_ms` / `pending_ticks_per_frame` 项目设置；`pump_frame()` 用 SceneTree 帧计数；`GET /mcp` 增加 `pending` / `pending_connections`。

### 1.2 两处必须写明的框架决策

1. **每连接响应顺序背压（HTTP/1.1 语义）**：一条连接上有未完成的 deferred 请求时，该连接的**请求流被暂时扣住**（字节留在 `in_buffer`，`poll()` 的派发循环多一个 `!pending_requests.has_connection(id)` 条件），直到它完成为止。理由：HTTP/1.1 要求同一连接上的响应按请求顺序返回；若把后面的即时响应先写出去，就是协议违规（而 M1 的流水线用例如今仍在门⑤里跑）。这**不是**全局 FIFO：没有跨连接配对、没有响应队列，其他连接完全不受影响。代价是「同一连接上 deferred 之后流水线的请求要等」——这是 HTTP 语义要求的等待，不是服务器饿死；且 `in_buffer` 上限（既有机制）仍会对滥发连接收尾。**线上证据用的是两条不同连接**，见 §2.3–2.4。
2. **per-request 超时只能收紧、不能放宽框架上限**：`_effective_timeout()` 取 `min(工具自报, 框架上限)`；`find_node_when_available` 用契约里的 `timeout` 参数做自报值，所以 `timeout=2` 真的 2 s 收尾（`data.timeout_ms=2000`），而 `timeout=900` 会被夹到 30 s——**被夹这件事不隐藏**，到期响应里的 `timeout_ms` 就是实际生效值。
3. **超时先于 tick 判定**（`Queue::tick()` 里 deadline 检查在 `task->tick()` 之前）：过期即超时，答案不依赖同一帧内两个事件的先后。

---

## 2. 5 类状态机的证明（先证明，再用真实工具验证）

### 2.1 doctest（受控假 pending 工具，红→绿）

6 个新用例（`tests/test_mcp_server.h`，全部 `[MCPServer]` 前缀）：

| 用例 | 覆盖的类 | 关键断言 |
|---|---|---|
| `the deferred channel hands the transport a task, not a body` | 交接 | `deferred=true` / `task!=nullptr` / `id_json=="41"` 逐字 / `timeout_ms=30000`；工具自报 250 → 250；自报 900000 → 夹到 30000；`handle()` 对 deferred 返回 `-32603` 且**释放 task**（`fake_pending_live()` 回到基线） |
| `the deferred queue completes on the right frame and keeps (connection, id) apart` | ①正常完成 + ④多 pending 交错不串线 | 到达帧不推进（frame=100 → 0 个完成）；frame=101 完成 `9/11`；frame=102 完成 `7/10`；frame=103 完成 `7/12`；三个 body 各带自己的 payload（`beta`/`alpha`/`gamma`） |
| `a deferred timeout is -32000 with data.suggestion and data.timeout_ms` | ②超时 | `kind=TIMEOUT`、`code=-32000`、`data.suggestion` 非空、`data.timeout_ms=50`；再用 `build_error_raw()` 验证**线上形状**（`error.data.timeout_ms == 50`）；另有 `FAILED` 分支（`code=-32000`、消息带 payload） |
| `dropping a connection releases exactly its pending requests` | ③断连清理不泄漏 | 3 条（连接 1×2、2×1）→ `drop_connection(1)`：pending 3→1、连接数 2→1、存活 task 恰好 −2；再 drop 2 → 0；`clear()` 全清 |
| `the per-frame pending budget cannot starve the ordinary requests` | ⑤不饿死常规请求 | budget=2 → 恰好 2 个完成、剩 3；此时**同一 registry 的即时工具照常在帧内作答**；budget=0 → 0 个；再 budget=8 → 剩 3 个全完成 |
| `the tool builder refuses a tool that declares both halves` | 声明互斥 | 两半都声明 → 拒绝；两半都不声明 → 拒绝；registry 计数保持 0 |

另加两组形状用例：`the running_game_frame_observation group is game-only and deferred`（3 个工具 `is_deferred_tool==true`、game 可见 / editor 不可见、`call_tool()` 返回 `-32603`）与 `the running_game_capture group is game-only and immediate`（screenshot 非 deferred），以及 `the frame tools validate their arguments before any wait, and need a game`（全部 `-32602` 分支 + 无 SceneTree/无 framebuffer 的 `-32000` + `save_path` 先于 framebuffer 判定）。

**红阶段（真实）**：本任务的红是**真红**，不是「先写测试再看它失败」的仪式——

```
[doctest] test cases:  108 |  107 passed | 1 failed
[doctest] assertions: 2742 | 2742 passed | 0 failed
.\modules/mcp_server/tests/test_mcp_server.h(5643): TEST CASE: [MCPServer] the per-frame pending budget ...
ERROR: FATAL: Index p_index = 2 is out of bounds (size() = 1).
   at: CowData<struct MCPDeferred::Queue::Entry>::get (.\core\templates\cowdata.h:199)
```

这是**我自己队列里的真缺陷**：`tick()` 是轮转扫描，完成项的**索引不是升序**（第一次 tick 完成 4 号、第二次完成 0 号），原来是「按收集到的索引倒序 `remove_at`」，于是越过尾部（`finished=[2,0,1]` → 删 1、删 0、再删 2 而 size 只剩 1）。修法是**按 `sequence` 删除**（`mcp_deferred.cpp:148-161`）。修后：

```
[doctest] test cases:  112 |  112 passed | 0 failed | 1429 skipped
[doctest] assertions: 2911 | 2911 passed | 0 failed
[doctest] Status: SUCCESS!
```

（门③基线：TASK-010 的 103/2554 → 现在 112/2911，只增不减；用例 +9、断言 +357。）

### 2.2 线上（真实游戏进程，9889）

| 类 | 检查 id | 结果 |
|---|---|---|
| ① 正常完成 | `g01_samples_cross_frame_distinct`、`g04_find_success` | `moved_frames=[406,408,410,413,415,418]` 严格递增；`found=true, node_path=/root/Main/Latecomer` |
| ② 超时 | `g06_find_timeout_is_-32000_with_timeout_ms` | 实测 **2046 ms** 后 `code=-32000`、`timeout_ms=2000`、`suggestion` 非空 |
| ③ 断连清理 | `g08`→`g09_disconnect_releases_pending` | pending **1 → 0**、`pending_connections` **1 → 0**、连接数 2 → 1；此后 `ping` 正常（`g10`） |
| ④ 多 pending 交错不串线 | `g11_interleaved_pendings_do_not_cross` | probe 时刻 `pending=2 / pending_connections=2`；A(id 101) `found=true /root/Main/DeferredLatecomer`；B(id 202) `-32000 timeout_ms=2000`；`crossed=False` |
| ⑤ 不饿死 | `g15_pending_does_not_starve`、`g11b_injection_answered_while_two_pending` | pending=1 时 `ping` **27 ms**；两个 pending 在飞时 `running_game_execute_gdscript` **28 ms** 返回 `{"result":"added","result_type":"String"}` |
| 超时后服务仍可用 | `g07_service_alive_after_timeout` | `ping` 正常且 `pending` 回到 0 |
| 请求不得静默丢弃 | ②③④ 三项 | 每个 pending 都以结果或 `-32000` 收尾，无一是「悄悄消失」 |

**证明手法说明（可复现性）**：④ 的第一个版本失败过——A 等的是早就存在的节点，于是在 probe 之前就完成了，probe 只看到 1 个 pending。修法不是放宽断言，而是让 A 等一个**此刻不存在**的节点（`DeferredLatecomer`），并在两个 pending 都在飞时用 `running_game_execute_gdscript` 现场把它创建出来；这样 probe 必然看到 2 个 pending，A 又必然成功。这一版同时把「pending 期间即时工具仍作答」变成同一条证据链的一部分。见 §11 勘误。

---

## 3. 4 个工具：逐工具表（可观察契约与差异）

「迁移源」= PLAYBOOK §1 指定的语义参照（`godot_mcp_gdext/src/commands/*.rs`、`addons/godot_mcp_rs/**`，**只读**）。

| new_name | 迁移源位置 | 可观察契约（as-built） | C++ 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `running_game_get_node_property_samples` | `mcp_runtime_agent.gd:201-223`（IPC 转发：`runtime.rs:272-292`） | `node_path`(str, 必填；空白 → -32602)、`properties`(str 数组, **必填**)、`frame_count`(int, 默认 60, ≥1)、`frame_interval`(int, 默认 1, **≥1**)。每 `frame_interval` 帧采一次，共 `frame_count` 次 → `{"node_path":<解析后的绝对路径>,"samples":[{"frame":<样本序号>,<属性>:<值>,…}],"frame_count":N}`；值全部过模块唯一 `serialize_variant`。起始找不到节点 → -32001；**采样途中节点被删** → -32001；无场景 → -32000；参数类型错 → -32602；框架上限到期 → -32000 + suggestion + timeout_ms | `tools/running_game_frame_observation.cpp:186-283` | ①`frame_interval`/`frame_count` 为 0 **被拒绝**（迁移源接受 0，而 0 就是「同帧采 N 次」这个本任务要消灭的缺陷）；②跨帧**不持有裸 `Node*`**，改持 `ObjectID` 每 tick 重解析（迁移源在循环外拿指针，节点中途释放即 UB）；③`node_path` 回显**解析后的绝对路径**（PLAYBOOK §6.7）；④超时归框架（迁移源用 `frame_count*interval/60+3` 自算） |
| `running_game_find_node_when_available` | `mcp_runtime_agent.gd:478-494`（IPC 转发：`runtime.rs:396-410`） | `node_path`(str, 必填；空白 → -32602)、`poll_frames`(int, 默认 5, ≥1)、`timeout`(number, 默认 5.0, 必须正且有限 → 否则 -32602)。每 `poll_frames` 帧查一次 → `{"found":true,"node_path":<绝对路径>,"type":<class>,"name":<name>}`；`/root/...` 绝对路径在**还没有 current_scene 时也查**（等 autoload / 场景加载），相对路径等场景出现；到期 → -32000 + suggestion + timeout_ms；无 SceneTree → 立即 -32000；类型错 → -32602 | `running_game_frame_observation.cpp:330-395` | **超时形态改变（任务书要求，见下）**；`node_path` 回显解析后绝对路径（迁移源回显入参）；`timeout` 只能收紧框架 30 s 上限 |
| `running_game_capture_frames` | `mcp_runtime_agent.gd:167-194`（IPC 转发：`runtime.rs:256-270`） | `count`(int, 默认 5, ≥1)、`frame_interval`(int, 默认 10, ≥1)、`half_resolution`(bool, 默认 true)。每 `frame_interval` 帧回读一次根视口 → `{"frames":[{"index","frame","width","height","image_base64","sha256"}],"count":N}`；无 framebuffer（`--headless` 的 dummy renderer）→ 建 task **之前** -32000 + suggestion；到期 → -32000 + suggestion + timeout_ms | `tools/running_game_frame_observation.cpp:430-545` | ①新增 `frame`（SceneTree 帧号）与 `sha256`（该帧 PNG 摘要）——任务书 §2.2 要求「多帧且可区分」，而单靠 `index` 无法排除「一张图发 N 次」；②无 framebuffer 时拒绝而非返回 N 张空图；③`count`/`frame_interval` 为 0 被拒绝 |
| `running_game_capture_screenshot` | `editor.rs:362-418`（`cmd_get_game_screenshot`，编辑器侧读 `user://mcp_screenshot.png`；映射按 `tool-rename-map.json` 归 `running_game_*`） | `save_path`(str, 可选；必须 `res://`/`user://`、无 `..`、必须点名文件 → 否则 -32602)。不带 → `{"image_base64","width","height","format":"png"}`；带 → PNG 原子落盘 + `{"saved_path","width","height","format":"png"}`；无 framebuffer → -32000 + suggestion | `tools/running_game_capture.cpp:96-160` | ①**不需要跨帧**：迁移源跨帧只因 `user://` 文件 IPC，模块在游戏进程内，IPC 消失 → 注册为普通即时工具；②`save_path` 只接受 `res://`/`user://`（迁移源 `globalize_path()` 接受任意绝对路径）；③写失败是错误（迁移源吞掉失败并回成功）；④落盘走 `publish_file_atomically`，不截断既有文件 |

### 3.1 与任务书表格的一处措辞差异（已在报告显式记录）

任务书 §2 的表格把这一组称为「4 个**跨帧**工具」。以 `docs/tool-groups-b2.json` 为准，两组共 4 个成员是
`running_game_frame_observation`(3) + `running_game_capture`(1)；其中**只有前者 3 个需要帧时钟**，
`running_game_capture_screenshot` 是单帧回读（迁移源之所以跨帧，是因为它经文件 IPC 等游戏侧 autoload 落盘）。
因此它按普通工具实现，并**没有**为了凑「4 个跨帧」而给它套一层假的 deferred。这与 §1「每个工具的依赖决定它属于哪一组」一致。

### 3.2 超时形态的偏离（任务书 §2.3 强制）

迁移源 `wait_for_node` 超时后回**成功**形态 `{"found":false,"node_path":…,"timeout":true}`。
TASK-011 §2.3 要求真实复现「超时后返回 `-32000` 且带 `timeout_ms`」，而 GDR-20 把截止时刻放进框架，
所以本实现里**过期 = 框架超时**：`{"code":-32000,"data":{"suggestion":…,"timeout_ms":2000},"message":"Deferred call timed out after 2000 ms: waiting for node 'NeverAppears'"}`。
一条规则覆盖所有 deferred 工具，而不是每个工具一套。`found:false` 形态因此不再出现。

---

## 4. 组与端点（机器可见的计数）

| 项 | 值 |
|---|---|
| 新实现组 | `running_game_frame_observation`(3) + `running_game_capture`(1)，均 `scope=game`、按 manifest 的 `mutating`（false / true） |
| 已实现并集 | 48 → **52**（17 editor-scope + 23 both + **12** game-scope） |
| 编辑器端点 9888 | **40**（不变） |
| 游戏端点 9889 | 31 → **35** |
| B2 manifest | `docs/tool-groups-b2.json` 两组 `implemented` 由 false 翻为 true（`sha256 a818e6c3b7d282bcae258d5cffa69f18d148e0e2cdbb3536ee19bf8751f31fe0`） |
| `tools/list` 顺序 | 4 个新工具追加在既有顺序之后（`registration.cpp` 追加两行调用），同一次构建内确定性不变（门⑤ case20 跨进程重启仍逐字节相同） |

---

## 5. 五道门（真实输出与退出码）

### 门① 契约子集逐字（`check_contract_subset.ps1`，**每组各跑两次**）

```
===== running_game_frame_observation (run 1) =====   exit 0
group=running_game_frame_observation tools=3 contract=171
[PASS] editor_9888_contract_subset
[PASS] game_9889_contract_subset
[PASS] guard_user_port_9877
3/3 checks passed

===== running_game_frame_observation (run 2) =====   exit 0
3/3 checks passed（同样三条 PASS）

===== running_game_capture (run 1) =====             exit 0
group=running_game_capture tools=1 contract=171
implemented_union=40 tools (editor endpoint) / 35 tools (game endpoint)
[PASS] editor_9888_contract_subset
[PASS] game_9889_contract_subset
[PASS] guard_user_port_9877
3/3 checks passed

===== running_game_capture (run 2) =====             exit 0
3/3 checks passed（同样三条 PASS）
```

（任务书 §3 的「门①按组跑两次」按「两个组各跑一次」也可满足；为免歧义这里每组各跑两次，共 4 次运行、12/12 检查全过。）

两个端点的 `name`/`description`/`inputSchema` 与 `docs/tools_list.renamed.json` **逐字相等**（脚本内 `-ceq` 比较），
且「未实现却已注册」的工具为 0（脚本按已实现并集断言 extra/missing）。

### 门② 三类证据 + 真实跨帧（`mcp011_deferred_evidence.ps1`）

```
-Phase game     : phase=game 21/21 checks passed      (exit 0)
-Phase capture  : phase=capture 9/9 checks passed     (exit 0)
```

「跨工具的端到端活证据链」（手册 §3 门②）在本任务里就是 §2.2 的那条链：
`find_node_when_available`(pending×2) → 在 pending 期间 `execute_gdscript` 创建节点 → A 找到它返回绝对路径、
B 到期返回 `-32000`+`timeout_ms` → 期间 `ping` 与注入都即时作答；每一步都是真实 HTTP 请求与真实响应文件（sha256 见 §6）。

### 门③ 模块 doctest

```
[doctest] test cases:  112 |  112 passed | 0 failed | 1429 skipped
[doctest] assertions: 2911 | 2911 passed | 0 failed
[doctest] Status: SUCCESS!        (exit 0)
```

### 门④ 全引擎回归

```
[doctest] test cases:   1538 |   1538 passed | 0 failed | 3 skipped
[doctest] assertions: 427192 | 427192 passed | 0 failed
[doctest] Status: SUCCESS!        (exit 0)
```

（基线 1529/426835 → +9 用例 / +357 断言，**0 failed**。）

### 门⑤ `accept_m1.ps1` 连跑两次

```
runA: 22/22 cases passed   (exit 0)
runB: 22/22 cases passed   (exit 0)
diff(runA PASS 清单, runB PASS 清单) = IDENTICAL
implemented tools = 40 (editor endpoint) / 35 (game endpoint); contract = 171
process split     = editor endpoint 40, game endpoint 35, editor-only 17, game-only 12
```

---

## 6. 门②的证据文件（`curl.exe -s -o` 落盘 + sha256）

证据目录：`%TEMP%\mcp011-deferred-evidence\`。所有简单请求都用
`curl.exe -s --max-time N -o <file> --data-binary @<body-file>`；需要连接控制的用例（断连 / 交错 / 计时）
用原始 socket 读回后 `[IO.File]::WriteAllBytes` 落盘（手册 §7.1 允许的第二条路径）。**没有任何响应体经过管道或 `Out-File`。**

| 检查 | 证据文件 | sha256 |
|---|---|---|
| `g00_baseline` | `g00_baseline.response.json` | `c2f397e4b1071816b80af82d61037cfe38d701446e6805209718bd80baf5927a` |
| `g01_samples_success` | `g01_samples_success.response.json` | `da092b88864c478c1193a4b752497578ccd77ad84cef2d2915b2e919c6c476e9` |
| `g03_samples_bottom_layer` | `g03_samples_bottom_layer.response.json` | `9a62ab972806a96369d900a50947f8168ce11e09b387ae0d9236bffce95d0303` |
| `g04_find_success` | `g04_find_success.response.json` | `dae8e08775ebc41c7b0ffd233cc9966fcb2cf86cefc791d7f2468d6d8631d167` |
| `g06_find_timeout` | `g06_find_timeout.response.json` | `2c8f38a25164fc5f43e8078693c8a9ce6ca2551965d6d11139fc1e1487776a85` |
| `g08_pending_during_disconnect` | `g08_pending_during_disconnect.response.json` | `a2f2d44e13df47d5fc5c52cbc86cd6e86b967aa89f4af75e2185c095ef2f0451` |
| `g09_pending_after_disconnect` | `g09_pending_after_disconnect.response.json` | `62bf7f571b9b31f1acc5e36736f2c009c9c418dd71ce7c0396b9274f3470bd99` |
| `g11_pending_interleaved` | `g11_pending_interleaved.response.json` | `856dc34fdb57b57282117ebf226b58263245cde9ef160205dcefba770eab1ce5` |
| `g11b_inject_node_while_two_pending` | `g11b_inject_node_while_two_pending.response.json` | `effbde1ff4394022b7bf18fb9e689d5a1a0c98b6ade273025f818f54338f2f34` |
| `g12_interleaved_b` | `g12_interleaved_b.response.json` | `323b2901ad802afc5d23455ba649de2956799bbb59a2c8d78f655e77f5c2c16e` |
| `g13_interleaved_a` | `g13_interleaved_a.response.json` | `60b1ef4dc218abcab99bfdf0ba242878019ca75288bf63969c0d1ed5487a749e` |
| `g14_pending_during_starvation_probe` | `g14_…json` | `e7ba21ad022bafc9c929bf056688255a1a3abb16cc8734f748dc2b811fd27333` |
| `g15_ping_while_pending` | `g15_ping_while_pending.response.json` | `bd828251bcbf8f1d92fed7909bacf39aaf1444c201200b0ca1b3dfcc9978734d` |
| `g16_pending_after_starvation_probe` | `g16_…json` | `5fc07cf1f46c936f5a43cbbc7c5dcc4e361b68f00bb3e3d78a1c3ea8f6d4d96b` |
| `g17_pending_after_long_close` | `g17_…json` | `bffd1460ea2396569ccd7086ff6a3848c9a96f88cc4a7f5de3497d40d11b9845` |
| `g22_tools_list` | `g22_tools_list.response.json` | `4b6f71847dde6052ea66eeb09ba3a971c862512125ccb1d07ef1736dfecd2ad7` |
| `c01_samples_windowed` | `c01_samples_windowed.response.json` | `60e6c4bc621746842a4c39bbe3e72195651967424ed7478d0c12ba24e3346b8b` |
| `c02_capture_frames` | `c02_capture_frames.response.json` | `aa45b7eb0a7a0bd7d90095eda9412f421b557c680a2cb1fae6d8dde810bd9bcc` |
| `c03_capture_screenshot` | `c03_capture_screenshot.response.json` | `5de4abfd608f098a4ff8391a3878a3e0cca3b76de4a49ea2858a981812122ef5` |
| `c04_capture_screenshot_save` | `c04_capture_screenshot_save.response.json` | `02552a2564c609cc32bda0c71c0ed4cc6dadfec02c5c7bc34d55ae042f6d6a68` |

关键响应原文（逐字，来自上表文件）：

```
g01  {"id":11,"jsonrpc":"2.0","result":{"content":[{"text":"{\"frame_count\":6,\"node_path\":\"/root/Main/Player\",\"samples\":[{\"frame\":0,\"moved_frames\":406,...},{\"frame\":1,\"moved_frames\":408,...},{\"frame\":2,\"moved_frames\":410,...},{\"frame\":3,\"moved_frames\":413,...},{\"frame\":4,\"moved_frames\":415,...},{\"frame\":5,\"moved_frames\":418,...}]","type":"text"}]}}
g06  {"error":{"code":-32000,"data":{"suggestion":"Make the awaited state happen earlier, or call the tool again (the wait started at the frame the request was read)","timeout_ms":2000},"message":"Deferred call timed out after 2000 ms: waiting for node 'NeverAppears'"},"id":16,"jsonrpc":"2.0"}
g09  {"connections":1,"frame_count":417,"is_editor":false,"listening":true,"pending":0,"pending_connections":0,"port":9889,"server":"godot-mcp-rs","status":"ok","tools":35,"transport":"streamable-http"}
g12  {"error":{"code":-32000,"data":{...,"timeout_ms":2000},"message":"Deferred call timed out after 2000 ms: waiting for node 'NeverAppears'"},"id":202,"jsonrpc":"2.0"}
g13  {"id":101,"jsonrpc":"2.0","result":{"content":[{"text":"{\"found\":true,\"name\":\"DeferredLatecomer\",\"node_path\":\"/root/Main/DeferredLatecomer\",\"type\":\"Node2D\"}","type":"text"}]}}
g11b {"id":203,"jsonrpc":"2.0","result":{"content":[{"text":"{\"result\":\"added\",\"result_type\":\"String\"}","type":"text"}]}}
```

### 6.1 三类证据（成功 / 缺参 / 底层失败）与**不可构造类的声明**

| 工具 | 成功 | 缺参/类型错 → -32602 | 底层失败 |
|---|---|---|---|
| `running_game_get_node_property_samples` | `g01`（6 帧样本严格递增） | `g02`（缺 `properties`） | `g03`：`node_path=DoesNotExist` → `-32001 Node 'DoesNotExist' not found` + suggestion |
| `running_game_find_node_when_available` | `g04`（等待 1 s 后出现的 `Latecomer`） | `g05`（缺 `node_path`） | `g06`：**该类就是超时**——节点永不存在 → `-32000` + `timeout_ms=2000`（`found:false` 形态已按 §3.2 取消，故无第二条底层失败形态） |
| `running_game_capture_frames` | 窗口相 `c02`（3 帧、帧号 169/173/177、3 个不同 PNG 摘要） | `g20`（`count=0`） | `g18`：headless 无 framebuffer → `-32000` + suggestion（**声明**：本进程类型下这是唯一可构造的底层失败） |
| `running_game_capture_screenshot` | 窗口相 `c03`（base64 PNG 1152×648）、`c04`（`res://mcp011_capture.png`，盘上 4890 B、PNG magic 正确） | `g21` / `c05`（`C:/outside/shot.png`；`res://../escape.png`） | `g19`：headless 无 framebuffer → `-32000` + suggestion（同上声明） |

**不可构造类的显式声明**：`running_game_capture_frames` / `running_game_capture_screenshot` 的「成功」在 **headless**
进程下不可构造，这不是本实现的取舍，而是引擎事实：`--headless` 的 dummy renderer 没有纹理存储，
`RendererDummy::TextureStorage::texture_2d_get()` 会打 `ERROR: Parameter "t" is null.` 并返回 null（本任务先跑了一次 spike 实测复现，见 §11）。
因此两个 capture 工具在 headless 下**先询问 display server 再决定**（`game_framebuffer_available()`），
其成功证据改在 **窗口化**（真实 display server / OpenGL）的游戏进程里采集（`-Phase capture` 9/9）。

---

## 7. 四个跨帧工具的真实证据（跨帧可区分）

### 7.1 headless 游戏进程（9889）

- **采样真的跨帧**：`frame_count=6, frame_interval=1` → `moved_frames = [406,408,410,413,415,418]`（**严格递增**），
  `node_path` 回显解析后的 `/root/Main/Player`。这就是 TASK-010 最小反例（同帧 N 次采样得到 N 个相同值）被消灭的正面证据。
- **等待真的等待**：`Latecomer` 由游戏侧 `Timer`（1.0 s）创建；`timeout=8.0` 的调用在它出现后返回
  `{"found":true,"node_path":"/root/Main/Latecomer","type":"Node2D","name":"Latecomer"}`。
- **超时真的到期**：`NeverAppears` + `timeout=2.0` → 实测 **2046 ms** 后 `-32000` + `timeout_ms=2000`。
- **capture 两工具在 headless 下诚实拒绝**（`-32000` + suggestion），而不是回 N 张空图。

### 7.2 窗口化游戏进程（9889，真实 display server）

启动参数只去掉 `--headless`（`--path <scratch> --mcp-port=9889`），其余一致；证据：

- `c01_samples_cross_frame_windowed`：6 个样本、`moved_frames=[8599,8707,8811,8924,9036,9145]` 严格递增，
  `position.x=[196,28,444,296,144,580]`（脚本里刻意做了绕回，保证长时间运行后 sprite 仍在视口内）。
- `c02_capture_frames_cross_frame_distinguishable`：`count=3, frame_interval=4, half_resolution=false` →
  `frames[].frame = 169,173,177`（**间隔恰好 4 帧**），三个 `sha256` **互不相同**：

  ```
  63605ba2a817f2b1e54280afa59364c34b25c1fa7e1e0d01f24835e7a044ae57   (frame 169)
  a4621d54cc74e1cef2800b0f7781caff3d3d24640fe8431ff65d8f04a01397c2   (frame 173)
  d7344ec314b59c279b0a8fc070c225d07ef0d25aa5413225ad4d2121b58d483b   (frame 177)
  ```

  每帧都有非空 `image_base64`、`width=1152`、`height=648`。**帧号证明「真的隔了 4 帧」，摘要证明「像素真的不同」**——
  这正是任务书 §2.2 要的「不是同一帧的副本」。
- `c03_capture_screenshot_base64`：`{"format":"png","width":1152,"height":648,"image_base64":<6516 B>}`。
- `c04_capture_screenshot_writes_a_real_png`：`save_path=res://mcp011_capture.png` → 盘上 **4890 B**，
  PNG magic `89 50 4E 47` 正确，`sha256 2b3a2fd4efc409b213779f357aa9c57c850db44af37627be3fd1380e517a74d5`。
- `c05_capture_screenshot_bad_path`：`res://../escape.png` → `-32602 must not walk upwards with '..'`。
- `c06_windowed_renderer_used`：3 个不同摘要 + 4890 B 的真实 PNG，证明**渲染器真的跑了**。
- 9877 守卫：`pid_before=36392 pid_after=36392`（窗口化运行同样不触碰用户编辑器）。

---

## 8. 对既有门无回归的证据（尤其 HTTP 边缘用例）

本任务改了 HTTP/JSON-RPC 核心，因此**最重要的回归证据是门⑤两次全过的既有用例**（§5）。逐条取出 HTTP 边缘用例的原始 evidence：

```
case8_concurrent_100            connections=8 sent=100 received=100 unique_ids=100 mismatches=
case9_keep_alive_two_requests   first={"id":"ka-1",...} second={"id":"ka-2",...}
case10_half_packet              （半包缓冲，PASS）
case11_body_too_large           status=413 closed_after=True proof=FIN (zero-length read (peer FIN) within 300 ms)
                                body={"error":"Payload Too Large"}
case15_connection_reaping       （连接回收，PASS）
case16_expect_100_continue      interim='HTTP/1.1 100 Continue' after 23 ms; interim_sent_times=1; final_status=200
case17_header_too_large_431     status=431 reason='Request Header Fields Too Large' closed_after=True proof=FIN
case18_bare_lf_terminator_400   status=400 answered_after=27 ms closed_after=True proof=FIN
case20_tools_list_cross_process_restart  （跨进程重启 tools/list 逐字节相同，PASS）
case12/13/14                    （game endpoint / 未开端口 / 端口占用，PASS）
```

为什么它们**仍然成立**（设计层面，不是巧合）：

1. `poll()` 的项目派发顺序、`Expect: 100-continue` 的当场 flush、framing error 的 400/411/413/431 语义、
   `in_buffer` 上限、空闲回收、`close_after_flush` 路径**逐条保留**；
2. 新增的 pending 相位只在所有连接处理完之后运行，且不改变任何既有判定；
3. 两处有意的行为差异都只针对「该连接上有 pending」这一新状态：
   - 空闲回收**豁免**有 pending 的连接（否则 30 s 的等待会被 30 s 的空闲回收抢先斩断，客户端拿不到 `-32000`）；
   - 请求流**背压**（HTTP/1.1 同连接响应顺序，见 §1.2）；
   两条在没有 pending 的普通连接上完全不生效——这正是 case 8/9/10/11/16/17/18/20 全部原样通过的原因。
4. 最终 flush 相位补上了 deferred 相位排入的响应，并对写失败/`close_after_flush` 做同样的断开与 `drop_connection()` 清理。

另外，门④（全引擎 1538 用例）里包含引擎自身的 `Node::print_orphan_nodes` 等探针，模块新增的 doctest 不改变其输出；
`_retire_unattached()` 的既有逻辑未动。

---

## 9. 关键工件 sha256

引擎二进制（本次全部门与证据使用的构建）：
`6d6478c02ca131ca891f80d0225016223fe18095b6b3df32e048ceae8a7edf5c`
（`bin\godot.windows.editor.x86_64.console.exe`，`--headless --test` 与证据脚本各自打印同一值。）

```
c8ecdd83b0f9392d6d2606c2cdd9a4367fc3d1eddfc18c0bc8061f5d26e8914f  mcp_deferred.h
e047458bc2da0d3c42dc9674c47619cecba6fdc0870cf0078e7bcbf560deba22  mcp_deferred.cpp
ec237ef3811baede410f9375a6a6021c6a6bf526759ab5b0ff2a6c5e53504bc0  mcp_http_server.h
419093048308b9e0867ee35a8b4f5018198aa54f478ca829e3d8c9506635125a  mcp_http_server.cpp
c4623b24169d68cfa9dabbf1d15e0ed4911e8fff622c65d4372a7694e60e4829  mcp_jsonrpc.h
1e518ebf7b9c0b512dbb3e2507a373711da0f873739c37ebf5d0df2c4d122f7f  mcp_jsonrpc.cpp
f8c4c9026d999edd3f50b1053d281a9abc0ecbc5cad6bccfc7fa7658294a85ac  mcp_server.cpp
42af0a84e88b6fb118955feead78d8d9c41a6a23ee53bea2ed8e8fcacb2297e7  tool_registry.h
a5b62fa1e73d3aa160acc7afdf7b596ee08eba2697db1900cb13aef27a14ef44  tool_registry.cpp
b418813bf653d25ef6a70c2aaed8fcfaff752ae108aa579e53ba9182aa9a8c3f  tools/tool_builder.h
efe335b3547322da55a4d0ad493521a4b245fb21e677205e4990d3b417f1d858  tools/tool_builder.cpp
396651c8bb01bc68e120985cc2ac4fd4ba440541194f81b05e3a8884d8bc7ede  tools/tool_helpers.h
4550fbb2aa873d1a286240df4046819b969ebb2ae7f8fe3c254c34dda65ab098  tools/tool_helpers.cpp
ea347c423f7eb917280e66669c6ec1289c2c1edf0d203ca51a421e7fb097aeb0  tools/running_game_frame_observation.h
a3a2d83f0296f101ec7b7b7132b6e60e3cef44a0dacbbe6767846499cf00ac39  tools/running_game_frame_observation.cpp
37bb23eaf3cdcedf86c89016853431e1c23dd5b29a64ba3f96f38f1c30ba41e6  tools/running_game_capture.h
ba293fa1b0181d9716f1d7f14b80cb0be5efd383909fd8e84a29b93afca51069  tools/running_game_capture.cpp
48d04b204fb4571aef82a166f9b615f7a271cff282c817465057482fd2bbcca0  tools/registration.cpp
0334b7378d0d88e7baa60d6f6639d6316faf2bb1f4f4d6fb02f3113a465f5369  tests/test_mcp_server.h
4d552e061a442c8b73ea755b2b90649e620021f0628eee44a6138611b34101ae  tests/test_mcp_server.cpp
df7cb236446dcfc7648327ff32597dbd86c16ef399d61a6626752fa7e9f52c30  scripts/gen_b2_game_schema.py
fce4c3b86a2ced22653b289a08591cc54207dac9d6f4021e6b0c55f9b8fc10c8  scripts/mcp011_deferred_evidence.ps1
146880552b6d0a62035bbeee0ccc2319ffb60252c6aad8237092a6c80b38033c  scripts/accept_m1.ps1
a818e6c3b7d282bcae258d5cffa69f18d148e0e2cdbb3536ee19bf8751f31fe0  docs/tool-groups-b2.json
```

契约与映射**未被触碰**（`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、`docs/tool-groups.json` 均无改动，
`git diff HEAD~1 HEAD` 对这三个文件为空）。B1 manifest 的指纹仍是 TASK-009/010 引用的那个：

```
0cfcac80f0d999fa7db713ae48f43febe96ae52e2c93633257eeed00ffdfbfac  docs/tool-groups.json   (B1，未改)
c4f913d65c3f3fd311d36ded44b473189cf886f098959fe7b6edf49b74901298  docs/tools_list.renamed.json       (未改)
2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd  docs/tool-rename-map.json          (未改)
```

新增工具的描述与 `inputSchema` 全部由
`scripts/gen_b2_game_schema.py`（新增两个组的条目）从契约**逐字节生成**，手工未誊写一个汉字；
生成器 `--in-place` 连跑两次为 no-op（幂等）。

---

## 10. deviations / blockers / next_step_recommendation

### deviations（与手册/任务书的偏离，逐条显式）

1. **`running_game_capture_screenshot` 不是 deferred 工具**（任务书把它列在「跨帧工具」表里）。理由：它的跨帧依赖来自迁移源的文件 IPC，模块在游戏进程内该依赖消失；按 manifest 它是 `running_game_capture` 组唯一成员。若决策者认为它也必须走 deferred（例如为了统一语义），这是一个可以直接回退的决定。
2. **`find_node_when_available` 超时回 `-32000` 而非迁移源的 `{"found":false}`**（任务书 §2.3 强制，见 §3.2）。
3. **`frame_interval`/`poll_frames`/`count`/`frame_count` 必须 ≥1**：迁移源接受 0，而 0 会退回「同帧重复观测」这一本任务要消灭的缺陷。属手册 §6.2「参数不能静默无用」的应用。
4. **采样期间不持有裸 `Node*`**（改 `ObjectID` 重解析）：迁移源持指针跨帧，在本模块里等于跨帧悬垂指针。属安全性改进，非行为约定。
5. **`running_game_capture_frames` 新增 `frame` 与 `sha256` 两个键**（任务书 §2.2 要求的「可区分」在仅有 `index` 时不可证）。
6. **`running_game_capture_screenshot` 的 `save_path` 只接受 `res://`/`user://`**（迁移源接受任意绝对路径）。与模块其它写工具一致（`editor_capture_screenshot` 同规则，且该规则由 TASK-011 hoist 成共享 helper）。
7. **每连接请求背压**（§1.2）：GDR-20 未提，但 HTTP/1.1 响应顺序要求它；不影响跨连接并发与既有流水线用例。
8. **空闲回收豁免有 pending 的连接**：否则 `--headless` 下 30 s 的空闲回收会与 30 s 的框架上限竞争，客户端可能拿不到 `-32000` 而只看到连接被关。
9. **`get_status_body()` 新增 `pending` / `pending_connections` 两个键**（GDR-20 要求「可观测」）。
10. **`_effective_timeout` 用 `min` 夹住工具自报的超时**：`timeout` 参数只能收紧 30 s 上限、不能放宽；实际生效值在 `data.timeout_ms` 里如实回报。
11. **hoist 了三处既有 helper**（`tools/tool_helpers`）：`game_current_scene` / `game_tree_root` / `resolve_game_node`（从 `running_game_observation.cpp` 原样搬移）、`game_framebuffer_available` / `game_viewport_image`（新增）、`normalize_screenshot_path` / `screenshot_png_writer`（从 `editor_write_scene_editor.cpp` 原样搬移）。按手册 §2.4「一组不得调用另一组的 file-private helper」与本仓库 TASK-005/009 的先例处理；搬移处只去掉了 `static`/前导 `_`，行为由既有 doctest 与线上证据钉住。
12. **`accept_m1.ps1` 的 `$ToolNames` 只追加 4 个名字**（未削弱任何断言；`process split`/`gate_scope_declared` 等派生量自动跟随映射）。
13. **`docs/tool-groups-b2.json` 两组的 `implemented` 翻为 true 并更新 notes**（manifest 是数据文件；B1 的 `tool-groups.json` 未动）。

### blockers

- 无阻塞。一个**引擎事实**被显式登记而非绕过：`--headless` 的 dummy renderer 没有纹理存储，`get_texture().get_image()` 不可用（实测 `ERROR: Parameter "t" is null.` + 返回 null）。这不是环境问题也不是实现残缺，而是渲染后端的能力边界；两个 capture 工具因此按 display server 能力**先判定后拒绝**，其成功证据改在窗口化进程采集。

### 勘误（append-only，允许且鼓励）

1. **队列删除逻辑的真缺陷**（红阶段抓到，已修）：`Queue::tick()` 轮转扫描时完成项的索引非升序，按索引倒序 `remove_at` 会越界（`FATAL: Index p_index = 2 is out of bounds (size() = 1)`）。修法是按 `sequence` 删除。这是本任务**自己写出的**缺陷，由「⑤预算不饿死」那个用例暴露——正因为它不是照抄参考实现，才需要真的跑测试。
2. **证据脚本的第一版 ④ 用例前提错误**（已修）：A 等待的 `Latecomer` 在该测试开始时早已存在，导致 probe 只看到 1 个 pending（第一次运行 `g11` 因此 FAIL，输出为 `during=1 pendings over 1 connections`）。修法不是放宽断言，而是让 A 等一个此刻不存在的节点、并在两个 pending 在飞时用 `execute_gdscript` 现场创建它（见 §2.2）。
3. **第一次 `execute_gdscript` 注入脚本写错**（已修）：用了 `get_tree().current_scene`，但工具把用户代码包进 `extends RefCounted`，那里没有 `Node::get_tree()` → `-32602 Parameter 'code' does not compile: Parse error`（`g11b` 第一次 FAIL，证据文件随后被成功版覆盖，原始输出留在本次运行的 job 日志里）。改用 `(Engine.get_main_loop() as SceneTree).current_scene` 后成功（`{"result":"added"}`）。
4. **一次 `build_local.cmd` 没有真正执行**：第一次用 `cmd /c scripts\\build_local.cmd` 后台调用时 cmd 进入了交互模式（只打印 banner 后退出，exit 0），日志里那条 7:49 的记录是**上一次会话**的构建，不是我的。发现后改用 `terminal: cmd` + `workdir` 直接调用脚本；本报告的门③/④数字来自**真正编译出本提交**的那次构建（引擎 sha256 见 §9）。
5. **`test_mcp_server.h` 的硬编码工具计数**（31/48/40/31）随 +4 工具更新为 35/52/40/35，并**双向**更新了 `tools of later batches are not registered`：原先作为「未注册」示例的 `capture_frames`/`find_node_when_available` 现在是已实现工具，而 `running_game_set_node_property`、`running_game_create_input_recording`、`editor_play_scene`、`editor_simulate_key`、`editor_get_input_actions` 仍是「必须缺席」的示例——该用例断言强度未降低。

### next_step_recommendation

1. **B4 的 `assert_*` / `run_test_scenario` / `watch_signals` 可以直接建在 GDR-20 上**：框架已提供 `Task::tick(frame, now)`、每帧预算、统一超时与断连清理；它们只需要新增各自的 `Task` 子类，不必再改 HTTP/JSON-RPC 核心。
2. **建议决策者把「每连接背压」与「空闲回收豁免」写进 DESIGN-DETAIL 的 GDR-20 条目**（本报告只实现了它们，规范由决策者维护）。
3. **`running_game_capture_frames` 的像素证据依赖 display server**：如果后续 CI 只有 headless，建议在 B5 录制族里沿用「按 display server 能力拒绝 + 窗口化相采集证据」这套两相结构，而不是把 headless 的空白帧当成成功。
4. **可选加固**：`pending` 目前无硬上限（受连接数上限 16 间接约束，每连接未限 pending 数）。若后续担心同一连接灌入大量 deferred 请求，可在 `Queue::add()` 加每连接上限；目前 `in_buffer` 上限与请求背压已能兜住。