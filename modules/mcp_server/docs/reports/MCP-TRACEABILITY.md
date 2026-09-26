# MCP-TRACEABILITY — 一次操作是否有效，以及凭什么判定

* Task: TASK-088 item ⑤；TASK-089 item A 关闭了当时的唯一缺口（文件侧副作用）；
  TASK-090 item A 关闭了剩下的一个（失败应答的 `data` 载荷）；
  **TASK-092 关闭了最后三个**：截断参数的旁路证据（item B1`args_complete`）、延迟调用的文件侧与画面侧
  证据（item B2）、帧代价取值的稳定性规则（item B4，见 §6）。
* 口径：本文定义**溯源模型**（字段 / 判定规则 / 失败分类）与**如何用日志判定一次操作是否有效**，
  并给出一次真实会话的产物路径。所有字段名都以实际写出的 JSON 行为准，逐条给出源码位置。

---

## 0. 一句话结论

运行期已经**把判定一次操作是否有效所需的全部事实写进日志**：每条请求一行，每次 `tools/call`
另配一行 `{"event":"capture"}`（截图像素差），并且（TASK-089 起）调用行本身还带着**这次调用改了
哪些文件**（绝对路径 + 前后 sha256/大小 + 是否真的变了 + 文本文件的首尾差异摘要）与**这次调用
答了什么**（`result_json`，有界；TASK-090 起失败时还有 `error_data_json`）。读取侧由
`scripts/mcp_trace_ledger.py` 把这些行合成**每次调用一行**的有效性台账。

TASK-092 起，**任何被 trace 的字节上限裁掉的载荷都有可核的旁路证据**：整份载荷写进同目录的
sidecar 文件，调用行给出相对路径 + 绝对路径 + 真实字节数 + sha256，台账在读取时**重新算一遍
hash 与大小**并据此判 `args_complete`（§2.6 / §3.1）。**延迟调用的文件侧副作用与画面侧效果也
在完成时刻被采集**（§2.7）：文件侧复用同一个 `MutationScope`，在延迟窗口的每一帧累计；画面侧
在请求到达帧取 `before`、完成帧之后取 `after`。仍然做不到的那一类（超时到**一帧都没被观测**）
在行里写 `not_tracked_deferred`，是一个**明确命名的边界**而不是静默缺失。

---

## 1. 运行期捕获能力（实测）

| 开关 | 取值 | 默认 | 依据（实测/源码） |
|---|---|---|---|
| 捕获模式 | `--mcp-capture=off\|on_error\|every_call` | `off` | 启动行 `[MCP] capture=enabled: mode=every_call viewport=2d dir=…`（本轮实测）；`mcp_capture.h:74-78` |
| 取景 | `--mcp-capture-viewport=editor\|2d\|3d` | `editor` | 实测三档；`mcp_capture.h:88`；游戏进程只有一个窗口，恒回 `game`（`mcp_capture.cpp:375-376`） |
| 落盘目录 | `--mcp-capture-dir=<OS 路径>` | 追踪文件同目录的 `shots/` | 本轮显式指到绝对路径，实测 8 + 6 个 PNG |
| 缩放 | `--mcp-capture-scale=1\|2\|4` | `1` = **不缩放** | `mcp_capture.h:90-93`；`scale=1` 时帧不拷贝、不重采样，落盘的即原图 |
| 差异图 | `--mcp-capture-diff-image=on` | 不落 | `mcp_capture.h:101-104` |
| 截断 | **不截断** | — | `WARN_TOTAL_BYTES = 1 GiB` 只 WARN，从不删除（`mcp_capture.h:175-177`）；启动行逐字打印 "capture keeps every PNG it writes (no size limit, nothing is ever deleted)"。`--mcp-capture` 与 `--mcp-trace` 同开才生效（无 trace 时给一次 WARN 并关闭）。 |

**捕获发生在应答之后**：应答路径只多一次 framebuffer 拷贝，编码/解码/哈希/落盘/像素比对都在
「至少晚一帧」的 `tick()` 里做（`mcp_capture.h:56-62`）。因此 `changed` 的含义是
「这次调用的效果**已经上屏**」。

---

## 2. 每次调用留下的字段

### 2.1 调用行（一请求一行，`Recorder::_build_line`，`mcp_trace.cpp:320-380`）

| 字段 | 含义 | 源码 |
|---|---|---|
| `seq` | 本进程内的请求序号（**调用 id**；只在一次 generation 内可比） | `mcp_trace.cpp:322` |
| `id` | 客户端 `id` 的**原样词法**（数字仍是数字） | `mcp_trace.cpp:367-380` |
| `connection` | 连接号 | `:324` |
| `method` | JSON-RPC 方法 | `:325` |
| `tool` | `params.name`（在查注册表**之前**取，故 -32601 也留名） | `:337` |
| `args` / `args_bytes` / `args_truncated` | 规范化参数（键排序）、真实字节数、是否截断 | `:339-341` |
| `ts_ms` | 该行写出时刻（= 结束时刻） | `:323` |
| `duration_ms` | 请求到应答的墙钟毫秒 | `:333` |
| **开始时刻** | `ts_ms - duration_ms`（**导出量**，非独立字段） | — |
| `ok` / `error_code` / `error_message` | 结果码 | `:326-331` |
| `result_bytes` | 回写响应体的 UTF-8 字节数 | `:334` |
| `tools` | 仅 `tools/list`：表大小 | `:344-346` |
| `pending_ms` / `timeout_ms` | 仅延迟应答通道 | `:348-351` |
| `capture{mode,viewport,status[,reason]}` | 捕获档位与状态（`pending` / `unavailable`） | `:356-365` |
| `file_effect_status` / `file_effects` | **TASK-089 新增**：这次调用对磁盘做了什么，见 §2.4 | `mcp_file_effects.*`；`mcp_trace.cpp` 的 `_build_line` |
| `result_json` / `result_json_bytes` / `result_json_truncated` | **TASK-089 新增**：成功应答的**工具自身返回体**（规范化 JSON，按 `args` 同一上限截断；真实字节数另给）。看的不是「调用成功」，而是「它自己说什么」：`passed:false`、`created:true`、`ignored`、`changed` | `mcp_jsonrpc.cpp`（`_dispatch_tools_call` 成功分支）；`mcp_trace.cpp` 的 `_build_line` |
| `error_data_json` / `error_data_json_bytes` / `error_data_json_truncated` | **TASK-090 新增**：失败应答的**工具自身 `data` 载荷**（`suggestion`、`parse_error` 等），与 `result_json` 同一收口、同一上限策略。**每一次失败的 `tools/call` 都写**，工具没带载荷时写 `""`——「有这个字段」因此可以与「这条 trace 出自旧版本」区分开 | `mcp_jsonrpc.cpp`（`_record_error_data`；延迟分支与立即分支）；`mcp_http_server.cpp`（延迟完成）；`mcp_trace.cpp` 的 `_build_line` |
| `args_sidecar` / `result_json_sidecar` / `error_data_json_sidecar` | **TASK-092 (B1) 新增**：被上限裁掉的载荷的**完整旁路证据**，`{path, relative_path, bytes, sha256}`。只在载荷真的超限时出现（未超限的载荷是 inline 完整的，不产生文件也不产生这个字段）。写文件失败时同一位置写 `<同名前缀>_sidecar_error`（字符串原因），裁断因此是**声明的**而不是隐形的 | `mcp_trace.cpp` 的 `Recorder::_write_sidecar` / `Recorder::record` / `_emit_sidecar`；读取规则见 §2.6 与 §3.1 |

### 2.4 TASK-089 新增：文件侧副作用（`file_effect_status` + `file_effects`）

**它补的是什么缺口。** 像素差覆盖的是**画面侧**副作用；在此之前，一次 `project_write_text_file`
或 `editor_save_scene` 在日志里只有 `result_bytes`，**没有任何字段能证明盘上哪个文件变了**。台账
只能显式写 `file_effect_evidence: "not_recorded_in_trace"`。现在调用行自己带着答案：

```
file_effect_status ∈ { no_mutation, observed_changed, observed_no_change, observed_mixed,
                       not_tracked_deferred }        // 空串 = 这条 trace 不带文件侧证据
file_effects: [ {                                   // 一次调用一个受影响的落点一行
    "path":       "res://notes.txt",                // 原样（模块路径）
    "abs_path":   "H:\\rebuild\\projects\\...\\notes.txt",   // 绝对路径（可核）
    "kind":       "write" | "delete" | "mkdir",
    "existed_before": true,
    "before":     {"sha256": "...", "bytes": 197} | null,   // 不存在就是 null，不是 {}
    "after":      {"sha256": "...", "bytes": 51}  | null,
    "changed":    true,                              // 前后 sha/存在性真的不同
    "failed":     false,                             // 这次落点操作报了失败
    "diff":       { ... }                            // 见下，仅小文本文件
} ]
```

`diff` 是**有界的首尾差异摘要**（`"type": "line_head_tail"`，如实命名，**不是**完整 LCS diff）：

| 键 | 含义 |
|---|---|
| `lines.before` / `lines.after` | 前后行数 |
| `same_head_lines` / `same_tail_lines` | 首部 / 尾部**逐行相同**的行数 |
| `changed_lines.before` / `.after` | 夹在中间的那一段的行数 |
| `head_lines` / `tail_lines` | 摘要里给出的差异行数（`- ` 删除 / `+ ` 新增 前缀） |
| `head` / `tail` | 差异段的**头** / **尾**各最多 3 行（每行最多 200 字符） |
| `sampled_partial` | 差异段比采样窗口大（摘要只是一部分） |

开销是显式有界的：**大于 256 KiB 的文件只记 sha256 与大小，从不整份读**；含 NUL 字节的文件不
算文本，不产生 `diff`；每行最多 200 字符；每次调用最多 256 行（超出置 `truncated`）。**trace 关
闭时整套机制完全不动**：`begin_recording()` 不由 JSON-RPC 层调用，任何一次快照、哈希、读取都不
会发生。

**收口在一处，不是逐个工具散改。** 记录器只有一个 API（`MCPFileEffect::MutationScope`），打开它的
地方是模块自己的磁盘原语：

| 打开处 | 覆盖 |
|---|---|
| `publish_file_atomically()`（`tool_helpers.cpp`） | **模块唯一的发布原语**：场景 / 资源 / 脚本 / shader / theme / `project.godot` / 截图 / 测试报告的写出全部经它 |
| `publish_project_setting_to()` 的 section 分支 | 引擎自己的 `save_custom_section()` 不走上面的原语，是唯一例外，就地补一处 |
| `_ensure_user_data_directory()` | 唯一由模块代为建目录的地方（`kind: mkdir`） |
| `project_delete_scene_file`（+ `.import`）、`editor_get_test_report` 的 `clear`、`write_csharp_build_record`、两处跨场景 rollback | 这四处**不走发布原语**地直接写盘，各自打开同一个 scope |

**声明的覆盖边界**：记录器开在**磁盘原语**上，不在每个工具上。纯内存改动（编辑器里的节点属性、
尚未发布进 `project.godot` 的 InputMap 动作）记为 `no_mutation`——那是正确的读法，台账的
`file_effect` 一列写 `none`，而不是暗示「这次调用什么都没做」。

### 2.6 TASK-092 (item B1)：超限载荷的 sidecar（`*_sidecar`）

**它补的是什么缺口。** trace 对三个载荷有字节上限（`args` / `result_json` / `error_data_json`，
默认 4096 B）。超限就只写前缀 + 真实字节数，于是**台账恰好在载荷最值得看的时候失去可重建性**：
Pong 会话里 `project_edit_script` 的行写着 `args_truncated: true` 与 `args_bytes: 9464`，读者能
看见「被裁了」，永远看不见「裁掉的是什么」。

**现在的规则**（写侧：`mcp_trace.cpp` 的 `_write_sidecar` / `record` / `_emit_sidecar`）：

| 情形 | 行上的字段 | 文件侧 |
|---|---|---|
| 载荷未超限 | `args`（完整）、`args_truncated: false` | 无文件 |
| 载荷超限 | `args`（仍是裁断后的前缀）、`args_truncated: true`、`args_sidecar: {path, relative_path, bytes, sha256}` | `res://`… 之外，写进**trace 文件同目录**的 `<trace 名>.sidecar/<行号>-<种类>.json`，内容是**整份**规范化载荷 |
| 文件写不出来 | 同上，但改为 `args_sidecar_error: "<原因>"` | 无文件 |

三个载荷同一套机制，种类后缀是 `args` / `result` / `error_data`，trace 字段前缀分别是
`args` / `result_json` / `error_data_json`。

**为什么可核，而不是「它说写了就写了」。** 字段给的是**路径 + 相对路径 + 真实字节数 +
sha256**，台账（`sidecar_of()`）读取时**自己重新打开文件、重新算 sha256、重新量大小**：
`sidecar_verified` 只在**三者全都对上**时才成立，否则是 `sidecar_mismatch`（并给出实际值）；
两个路径都找不到就是 `sidecar_missing`。`sha256` 用的是 `FileAccess::get_sha256()`——和
`file_effects` 的前后 hash **同一个函数**，所以「读侧重算」与「写侧记录」按构造同源；`bytes` 是
**把文件读回来量出来的**，不是把写进去的字符串长度抄一遍。`path` 是 `--mcp-trace` 给的那个形式
**原样**（试测里是绝对 OS 路径；`res://` / `user://` 形式原样保留），`relative_path` 相对 **trace
文件所在目录**，因此 trace 被拷到别的机器/别的目录后旁路证据仍然可核——读侧**先试 `path`、
再试 `<trace 目录>/<relative_path>`**。

**成本是显式有界的**：只有超限的载荷才落盘，每份一次 `store_string` + 一次 `get_sha256`（读回
自己刚写的文件），且写失败**绝不打断它描述的那次调用**（记录器是旁观者，见 `mcp_trace.h` 的
两条硬约束）。

### 2.7 TASK-092 (item B2)：延迟调用的文件侧与画面侧证据

**它补的是什么缺口。** 延迟通道（GDR-20：工具跨帧作答）此前在文件侧只有一个声明
（`file_effect_status: "not_tracked_deferred"`），在画面侧只有 `capture.status: "unavailable"`：
每调用一次的同步缓冲看不到「应答之后」的落盘，而截图在 TASK-090 之前的实现里根本没被 arm。
于是场景 / 压力这两个**整个答案就是判定**的工具，在台账上既没有磁盘证据也没有画面证据。

**文件侧。** 记录器（TASK-089 的 `MutationScope`）现在开在**任务真正跑的那一处**：
`MCPDeferred::Queue::tick()` 在调用 `entry.task->tick()` 前后各开/收一次，把这一次 tick 的行
**跨整个延迟窗口累计**到该 pending 条目上，完成时随 `Completion` 交回运输层，写进调用行。
`Completion::file_effect_status` 的取值规则：

| 情形 | 状态 | 读法 |
|---|---|---|
| 至少有一帧被观测，且这些帧里有落盘改动 | `observed_changed` / `observed_mixed` | 真的写了文件，行里有 sha 证据 |
| 至少有一帧被观测，没有落盘改动 | `no_mutation` | **是事实**：窗口被看着，什么都没变 |
| 一帧都没被观测（deadline 在第一次 tick 之前就到了） | `not_tracked_deferred` | **明确命名的边界**，不是「没变」 |
| trace 关（`traceable=false`） | 空串 | 这条 trace 不带文件侧证据 |

**画面侧。** 延迟调用的 `before` 帧在**请求被读到的帧**取（`Engine::arm()`，与立即调用同一处），
`after` 帧在**完成帧之后至少一整个渲染帧**取（`Engine::_complete()`，与立即调用同一处）——
不同的只是 `finish()` 从「应答时」移到了「完成时」，而 `seq` 用**完成时才知道的那个行号**。
调用行因此仍然写 `capture.status: "pending"`，紧随其后的 `{"event":"capture"}` 行带着
`changed` / `changed_pixels` / `total_changed_ratio` 与两张 PNG，`frames_waited` 就是**这个延迟
窗口的长度**——它本身就是「after 帧确实在完成之后」的证据。

**声明的代价与边界**：每个在飞的延迟调用会多持有一帧 framebuffer 拷贝，直到它完成；数量上界
就是 pending 表的上界。连接在完成前断开时，slot 由运输层显式释放（`Engine::discard()`），
不留内存、也不写行（没有应答可依附）。`on_error` 模式下成功的延迟调用与立即调用一样被丢弃。

### 2.2 捕获行（`{"event":"capture"}`，与调用行同 `seq`，`mcp_capture.cpp:608-710`）

`status`、`tool`、`mode`、`viewport`、`scale`、`frames_waited`、`ts_ms`、
`before{path,sha256,bytes,width,height}`、`after{…}`、
**`changed` / `changed_pixels` / `total_pixels` / `changed_pixel_ratio`**（像素差，自动写入日志）、
`diff{…}`（仅 `--mcp-capture-diff-image=on`）、`total_bytes`、可选 `reason`。

### 2.3 本轮补齐：调用行的请求身份（`mcp_jsonrpc.cpp`）

实测（`work/task088/live/trace-editor.jsonl`，修复前）暴露的事实：调用行是
`{"id":null,…,"method":""…, "capture":{…}}`，**没有 `tool` 与 `args`**，而紧邻的捕获行却写着
`"tool":"editor_open_scene"`。即 JSON-RPC 层只把捕获态挂上了记录，请求身份从未填。
本轮补了四处（均在源码里用 `// [REBUILT-2C low-confidence: verify] … // [/REBUILT-2C]` 包住，
并登记进 `REBUILT-2C-MANIFEST.md`）：

| 位置 | 补的内容 |
|---|---|
| `dispatch`（`method` 取到之后） | `trace.id_json = id_json; trace.method = method;` |
| `_dispatch_tools_call`（traceable 块内） | `r_trace.tool = tool_name;` |
| `dispatch` 的 `tools/list` 分支 | `trace.is_tools_list = true; trace.tool_count = get_visible_tool_count(...)` |

**依据**：TASK-085 裁决 (C) 已记录 `dispatch` 是「写出来的、不是重放出来的」——录制里唯一的
`dispatch` 定义（rev388:311）早于 trace 参数，所以没有任何录制文本带这几行；方向由
`mcp_trace.h:132-182` 的字段声明与 `_build_line` 的读取条件唯一确定。

---

## 3. 溯源模型与判定规则

`scripts/mcp_trace_ledger.py` 把 2.1 与 2.2 按 `seq` 合成一行，并给出判定：

```
scene_effect  = changed    捕获行说 before/after 像素不同
                unchanged  捕获行说像素完全相同
                unavailable 捕获被拒（无 framebuffer / 无该视口 / 该调用无法取景），reason 说明原因
                not_observed 没开捕获（或 on_error 下这次成功因此不捕获）

file_effect   = changed    这次调用真的改写了盘上的落点（`file_effect_status` = observed_changed / mixed）
                unchanged  走了写出原语，字节与之前完全相同（observed_no_change）
                none       这次调用没有碰盘（no_mutation）
                not_tracked 延迟应答通道里**一帧都没被观测**（deadline 先到）；这是命名的边界，不是「没变」
                not_recorded 这条 trace 由没有文件侧记录器的版本写出（声明的缺失，不读作「没变」）

args_complete = true       参数完整：要么 inline 未截断，要么超限但 sidecar 被读侧**重新核对通过**
                            （`args_evidence` = inline_complete / sidecar_verified）
                false      截断了且没有可核的旁路证据（`truncated_no_sidecar` /
                            `sidecar_missing` / `sidecar_mismatch` / `sidecar_not_recorded_in_trace`）

verdict       = failed                   ok=false（带 error_code/error_message）
                ok_file_effect_observed  file_effect ∈ {changed, mixed}   ← 有效，且改动有 sha 证据
                ok_effect_observed       scene_effect=changed             ← 有效，且效果有画面证据
                ok_no_effect_observed    file_effect=unchanged 或 scene_effect=unchanged ←「报成功但没动」
                ok_effect_unavailable    ok=true 但本进程无法取景（诚实边界，不是失败）
                ok_effect_not_observed   ok=true 但没有任何有效证据（没开捕获 / 读工具）
```

**判定优先级：文件侧强于画面侧。** 一次真的改写了文件的调用「做了事」，无论画面动没动；因此
`ok_file_effect_observed` 先于 `ok_effect_observed` 判定。

**读法（重要）**：`ok_no_effect_observed` 不等于「这次调用没用」——读工具本来就不该动画面。
它等于「**若这次调用宣称改了画面或改了文件，两者都没有变**」。判一次**写**调用是否有效，看
`ok_file_effect_observed`；判一次**读**调用，看 `failed` / `ok_effect_*` 中的 `ok` 与 `result_bytes`。

**`ok` 不等于「它断言的事成立」。** `running_game_assert_node_state` 在断言不成立时仍然是一次
成功的调用（应答里 `passed:false`）。TASK-089 起调用行带 `result_json`，台账据此给出
`result_flags`（`assertion_failed` / `created_conflict` / `result_unparseable`），把这一类
「成功但结论为否」的调用从 `ok` 里挑出来。

### 3.1 可重建性（facts）

每一行同时给出该调用**可从日志重建的事实**是否齐备：
`request_id` / `tool` / `args`（未截断，**或**有通过核对的 sidecar）/ `times` / `result` / `capture` /
`scene_evidence` / `file_effect` / `error_data`，以及 `facts_complete`。用它区分「证据支持」与「推断」：
`facts_complete=false` 的行不得用来下结论。

`args` 的事实（TASK-092 item B1 起）由 `args_complete` 判定，而 `args_complete` 由台账**实际读盘**
得出，不是照抄行上的 `args_truncated`：

| `args_evidence` | 含义 | `facts.args` |
|---|---|---|
| `inline_complete` | 未截断，参数就在行上 | true |
| `sidecar_verified` | 截断了，但 sidecar 存在且 sha256 与字节数与行上一致 | true |
| `truncated_no_sidecar` | 截断了，写 sidecar 时报了错（`args_sidecar_error`） | false |
| `sidecar_missing` | 截断了，行指名了文件，两个候选路径都找不到 | false |
| `sidecar_mismatch` | 文件在，但 sha256 或字节数与行上不符（`args_sidecar_detail.actual_*`） | false |
| `sidecar_not_recorded_in_trace` | 截断了，行上连 sidecar 字段都没有 → 旧版本写出的 trace | false |

读法（重要）：`sidecar_not_recorded_in_trace` **只对旧 trace 成立**；新版本对每一个被裁的载荷
要么写出可核的 sidecar，要么写出 `args_sidecar_error`，两者都让「为什么不可重建」有名字。

`error_data`（TASK-090 新增）只在**失败**的调用上不可省略：新版本对每一次失败的
`tools/call` 都写这个字段（没载荷就是 `""`），所以「字段在」＝可重建；「失败却没有这个
字段」只可能是**旧版本写出的 trace**，如实记为不可重建，而不是当作「这次失败没有载荷」。

### 3.2 缺口状态（TASK-090）

* **文件侧副作用：已补**（TASK-089 item A）。调用行带 `file_effect_status` + `file_effects`，
  §2.4 是字段表与界。台账不再写 `file_effect_evidence: "not_recorded_in_trace"`——除非它读的是
  一条**由更早版本写出的** trace，那种情况仍如实写 `not_recorded_in_trace`。旧 trace 与新 trace
  因此可以并存，缺字段一律读作「这份证据不存在」，绝不读作「没有改动」。
* **失败应答的 `data`：已补**（TASK-090 item A）。调用行带 `error_data_json`
  （+ `error_data_json_bytes` / `error_data_json_truncated`），字段名与上限都跟成功的
  `result_json` 同构。写入点是工具错误真正成形的那两处（`_dispatch_tools_call` 的立即分支与
  延迟拒绝分支）以及延迟通道的完成处（`mcp_http_server.cpp::_tick_pending`），所以
  `suggestion`、`parse_error`、延迟超时的 `data.timeout_ms` 都在线上。台账据此给出
  `error_data` / `error_data_evidence` / `error_flags`（`error_suggestion` / `error_parse_error`），
  并在文本里单列「failure payloads」一段。
  **旧 trace 读法**：`error_data_evidence = not_recorded_in_trace`（失败行没有该字段）。
* **延迟应答通道（deferred）的文件侧：已补**（TASK-092 item B2）。记录器开在
  `MCPDeferred::Queue::tick()`——任务真正运行的那一处——并把每一帧的行**跨整个延迟窗口累计**，
  完成时写进调用行（`Completion::file_effects` / `file_effect_status`）。仍然存在的边界只有一条，
  而且是**命名的**：deadline 在第一次 tick 之前就到（一帧都没被观测）时写 `not_tracked_deferred`，
  读作「没有可观测量」，绝不读作「没有改动」。dispatch 时放在记录上的
  `not_tracked_deferred` 只是占位，任何产生了行的路径都会覆盖它（`mcp_http_server.cpp::_tick_pending`）。
* **延迟应答通道（deferred）的画面侧：已补**（TASK-092 item B2）。`before` 帧在请求被读到的帧取，
  `finish()` 移到完成时（`MCPHttpRequestSink::finish_deferred_capture`），`after` 帧在完成帧之后
  至少一个渲染帧取，像素差与两张 PNG 与立即调用同一套代码。见 §2.7。
* **延迟调用的 `result_json`：已补**（TASK-090 item C）。TASK-089 只在**立即**成功分支写这个字段，
  于是每一个 deferred 调用行只有 `result_bytes`——而场景（`running_game_run_test_scenario`）与
  压力（`running_game_run_stress_test`）这两个工具**整个答案就是判定**（`all_passed` / 每步
  `passed`），台账因此无法回答「断言成立吗」，无论读取侧怎么写。现在 `_tick_pending` 在
  `CompletionKind::DONE` 时从 `completion.result` 写同族字段——那正是 `build_deferred_body`
  用 `content_result` 包起来的**同一个 Variant**，所以调用行与 wire body 字节同源。
* **`args` 超过 4096 B 被截断**：**已补旁路证据**（TASK-092 item B1）。行上保留裁断后的前缀与
  真实 `args_bytes`，同时给出 `args_sidecar`（完整载荷 + 相对/绝对路径 + 真实字节数 + sha256），
  台账**重算并核对**后判 `args_complete`，见 §2.6 与 §3.1。`result_json` 与 `error_data_json`
  用同一上限、同一机制（`error_message` 上限 512 B 仍然是纯截断，见下）。
* **仍然是纯截断的**：`error_message` 上限 512 B（它是一句给人看的话，载荷在
  `error_data_json` 里，机器可读的那一半从不丢）。
* **捕获只在 `tools/call` 上开**（`initialize` / `tools/list` 无副作用可观测）。

---


---

## 4. 实测演示（真实会话）

### 4.1 TASK-088（编辑器 + 游戏，4 + 3 次调用）

驱动：`C:\Users\wyl\AppData\Local\Temp\mcp-recovery\work\task088\mcp088_live_evidence.ps1`
（窗口化，**非 headless**：headless 无 framebuffer，捕获恒 `unavailable`，不得拿来顶替）。
产物根：`…\work\task088\live\`。编辑器 `calls=4`，`ok_effect_observed=1 / ok_no_effect_observed=3`，
`facts_complete 4/4`；`editor_set_node_property` 同参数写两次 → 第一次 `changed`、第二次
`unchanged`，即本模型要钉住的「报成功但画面没动」。

### 4.2 TASK-089 第 7 轮试测（真实小游戏工程，30 + 15 次调用）

驱动：`…\work\task089\mcp089_live_evidence.ps1`。工程 `H:\rebuild\projects\mcpplay`
（一个 `Node2D` 场景 + `main.gd` + Theme 资源 + 文本资源 + `project.godot`，能真跑起来：
`MCP089_MINIGAME_READY`）。编辑器 9888 + 游戏 9889，两侧都开
`--mcp-trace` + `--mcp-capture=every_call` + `--mcp-capture-viewport=2d`。

| 产物 | 路径（`…\work\task089\`） | 实测摘要 |
|---|---|---|
| 编辑器 trace（修复前 / 后） | `live-before\trace-editor.jsonl` / `live-after\…` | 62 行；后者 57 590 B（多出 `result_json`） |
| 游戏 trace（修复前 / 后） | `live-before\trace-game.jsonl` / `live-after\…` | 31 行；后者 36 572 B |
| 编辑器截图 | `live-after\shots-editor\` | **60 个 PNG**（30 组 before/after），每个 82 341 B 或 82 024 B |
| 游戏截图 | `live-after\shots-game\` | **30 个 PNG**（15 组），每个 11 815 B，800×600 |
| 台账 | `live-after\ledger-{editor,game}.{txt,json}` | 见下 |
| 请求 / 响应逐条 | `live-after\e??-*.json`、`g??-*.json`（+ `.request.json`） | 45 组 |

台账（`live-after/ledger-editor.txt` 与 `ledger-game.txt`）**逐行实测**：

```
编辑器：calls=30 malformed_lines=0
        verdicts: failed=4, ok_effect_observed=1, ok_file_effect_observed=10, ok_no_effect_observed=15
        file_effects: changed=10, none=15, unchanged=5          facts_complete 30/30
游戏：  calls=15 malformed_lines=0
        verdicts: failed=5, ok_effect_observed=1, ok_file_effect_observed=5, ok_no_effect_observed=4
        file_effects: changed=5, none=10                        facts_complete 15/15
```

三条要看的行（编辑器 `seq=2/3/16`，游戏 `seq=9/10`）：

```
seq  req_id  tool                       scene_effect  file_effect  flags               verdict
2    102     project_write_text_file    unchanged     changed      -                   ok_file_effect_observed   ← 真的改了文件
3    103     project_write_text_file    unchanged     unchanged    -                   ok_no_effect_observed     ← 同内容重复写
16   116     editor_save_scene          unchanged     changed      -                   ok_file_effect_observed   ← 编辑器保存落了盘
9    209     running_game_assert_node_state  unchanged changed    -                   ok_file_effect_observed   ← 断言通过（并写测试报告）
10   210     running_game_assert_node_state  unchanged changed    assertion_failed    ok_file_effect_observed   ← 断言**不通过**，ok 仍是 true
```

`file_effects` 行实测（`seq=2`，`project_write_text_file` 真改了 `res://notes.txt`）：

```
path=res://notes.txt  abs_path=H:\rebuild\projects\mcpplay\notes.txt  kind=write  changed=True  failed=False
before={"bytes":197,"sha256":"67EED4FD…"}   after={"bytes":51,"sha256":"FDFC1FB0…"}
diff={"type":"line_head_tail","lines":{"before":9,"after":3},"same_head_lines":0,"same_tail_lines":0,
      "changed_lines":{"before":9,"after":3},"head_lines":4,"tail_lines":6,"sampled_partial":false, …}
```

`seq=3`（**同内容重复写**）实测：`changed=False`，`before.sha256 == after.sha256`
（`FDFC1FB0…`），台账于是判 `ok_no_effect_observed`；`seq=123`（`project_set_setting` 同值再写，
走的是**另一条写入口**：引擎的 `save_custom_section()`）同样 `unchanged`。

与工具外核验一致：会话前后对 `project.godot` / `main.tscn` / `notes.txt` / `util.gd` /
`scratch/paint.tres` / `created/inner/first.txt` / `shots/editor1.png` 直接算 `Get-FileHash`
（`live-after\live-session.txt` 末尾的独立快照），判定与 trace 的 `file_effects` 逐条相同。

复现：

```
python modules\mcp_server\scripts\mcp_trace_ledger.py <trace.jsonl> --text out.txt --json out.json
python modules\mcp_server\scripts\mcp_trace_ledger.py <trace.jsonl> --only-ineffective
```

### 4.3 TASK-090 第 8 轮试测（真实小游戏工程，27 + 30 次调用，多步编排）

驱动：`…\work\task090\mcp090_live_evidence.ps1`。工程 `H:\rebuild\projects\mcpplay8`
（`Node2D` + `main.gd`，含一个 `ColorRect` 玩家、一个 `Label` HUD、一个 Button；`_input` 响应
`mcp_right`，`_ready` 里把该 action 注册进 InputMap）。编辑器 9888 + 游戏 9889，两侧都开
`--mcp-trace` + `--mcp-capture=every_call` + `--mcp-capture-viewport=2d`。工程每次会话前被重置到
同一份 `project.godot` / `main.tscn` / `main.gd`，所以同一批调用可以重放做前后对比。

| 产物 | 路径（`…\work\task090\`） | 实测摘要 |
|---|---|---|
| 最终会话 trace | `live-after3\trace-editor.jsonl` / `trace-game.jsonl` | 55 338 B / 56 行、59 950 B / 61 行 |
| 最终会话截图 | `live-after3\shots-editor\` / `shots-game\` | 54 / 56 个 PNG |
| 台账 | `live-after3\ledger-{editor,game}.{txt,json}` | 见下 |
| 工具外像素复核 | `live-after3\analysis.json`（`analyse_round8.py`） | 28 对 PNG 全部重算，与 trace **逐对相等** |
| 场景树快照对比 | 同上 | 执行器批量调用前 / 后 / 会话末尾各 5 个节点，**逐字节相同** |

台账逐行实测（最终会话）：

```
编辑器：calls=27 malformed_lines=0
        verdicts: failed=3, ok_effect_observed=1, ok_file_effect_observed=10, ok_no_effect_observed=13
        file_effects: changed=10, none=13, unchanged=4      facts_complete 27/27
        error_data_evidence: not_applicable=24, recorded_in_trace=3
游戏：  calls=30 malformed_lines=0
        verdicts: failed=3, ok_effect_observed=6, ok_effect_unavailable=2, ok_file_effect_observed=5, ok_no_effect_observed=14
        file_effects: changed=5, none=22, not_tracked=2, unchanged=1      facts_complete 28/30
        error_data_evidence: not_applicable=27, recorded_in_trace=3
```

**失败载荷实测（item A）**：编辑器 `seq=12/13/15`（trace 行 23/25/29）逐字给出建议：

```
seq=12 req_id=112 project_create_resource err=-32000 |
  {"suggestion":"Set overwrite=true to replace the existing file"}
seq=13 req_id=113 project_create_scene_file err=-32000 |
  {"suggestion":"Delete it first with project_delete_scene_file, or choose another path"}
seq=15 req_id=115 project_delete_scene_file err=-32001 |
  {"suggestion":"Use project_get_filesystem_tree to list the .tscn files of the project"}
```

游戏 `seq=14`（trace 行 28）给出完整的 `parse_error`（行与消息都在；列如实在 §2 说明的边界上为 null）：

```
{"parse_error":{"generated_line":4,"in_caller_code":true,"line":1,
  "message":"Parse Error: Expected grouping expression.","messages":[...]},"parse_error_column":null,
 "suggestion":"Parameter 'code' accepts a string (required); ..."}
```

**场景树可达性实测（item B）**：游戏 `seq=3..12`（trace 行 6..24），全部为
`running_game_execute_gdscript`：

```
seq=3  return get_parent().name                     -> "Main"                     (+0 px)
seq=4  return get_parent().get_node("Player").position.x -> 100.0                 (+0 px)
seq=5  Player.position.x += 120                     -> 220.0                      (+12 800 px)
seq=6  同上再来一次                                  -> 340.0                      (+12 800 px)
seq=7  return Player.get_path()                     -> "/root/Main/Player"        (+0 px)
seq=8  set_hud("HUD from executor")                 -> "HUD from executor"        (+1 363 px)
seq=9  return get_path()                            -> "/root/Main/@Node@8"       (+0 px)
seq=10 return get_tree().current_scene.name         -> "Main"                     (+0 px)
seq=11 Player.color = (0.1,0.9,0.1,1)               -> Color(...)                 (+6 400 px)
seq=12 同色再写一次                                  -> Color(...)                 (+0 px)
```

`seq=9` 是这条能力的直接证据：执行体自己报出的路径就是 `/root/Main/<临时节点>`——它在运行中的场景树里，
父节点是当前场景根；而 `seq=1/13/30`（trace 行 2/26/60）三次场景树快照完全相同，说明它**没有留下来**。

**多步编排实测（item C③）**：`running_game_simulate_button_click_by_text`（`seq=22`，trace 行 44，
+1 600 px）→ `running_game_assert_node_state`（`seq=23`，`passed:true`；
`seq=21` 是故意写错的期望，`assertion_failed`）。deferred 编排 `seq=25/26`（trace 行 51/53）：

```
seq=25 req_id=325  result_json = {"all_passed":true,"passed":1,"failed":0,"errors":0,
       "results":[{"action":"mcp_right","in_input_map":true,"injected":1,"step":0,"type":"input"},
                  {"step":1,"type":"wait","waited_seconds":0.4},
                  {"actual":{"x":95.0,"y":420.0},"expected":{"x":95.0,"y":420.0},"passed":true,...}]}
       -> 台账 flags = scenario_passed
seq=26 req_id=326  result_json = {"all_passed":false,"passed":0,"failed":1,...}
       -> 台账 flags = scenario_assertion_failed
```

**工具外核验（像素）**：`analyse_round8.py` 把 capture 行指到的 28 对 PNG 读回来重算像素差
（规则与引擎一致：`max(|dr|,|dg|,|db|) > 10`，`mcp_capture.cpp:68` + `tool_helpers.cpp:1223`），
**28/28 与 trace 的 `changed_pixels` 完全相等**（其中 6 对 `changed=True`：12 800 / 12 800 / 1 363 /
6 400 / 12 800 / 1 600）。若按「任意差异 > 0」重算，`seq=8` 会是 1 464 而不是 1 363——差的就是
阈值以下的抗锯齿像素；这条口径写在读数侧而不是靠 trace 自证。

**工具外核验（文件）**：`live-after3\live-session.txt` 末尾的独立快照（`Get-FileHash`）与
`file_effects` 逐条相同。例：`res://scratch/box.tscn` 由编辑器 `seq=10`（req 110，trace 行 19）
创建为 `after.sha256=9E4B4985…`，同一 sha 又出现在 `seq=14`（req 114，trace 行 27）的删除行里
（`kind=delete`，`before=9E4B4985…`，`after=ABSENT`，
`abs_path=H:\rebuild\projects\mcpplay8\scratch\box.tscn`）——「建了又删」在盘上和日志上是同一对 sha。

---

## 5. 失败分类（判定用）

| 类别 | 入口 | 判据 |
|---|---|---|
| 协议失败 | 调用行 `ok=false` + `error_code` | `-32700`/`-32600`/`-32601`/`-32602`/`-32000`/`-32001` |
| 工具失败 | 同上，`error_code` 为工具自报 | 消息在 `error_message`（≤512 B）；**载荷**在 `error_data_json`（TASK-090 起；`suggestion` / `parse_error` / `timeout_ms`）。旧 trace 上仍是 `not_recorded_in_trace` |
| 无效成功（本模型的核心） | `ok=true` + `scene_effect=unchanged` + `file_effect∈{unchanged,none}` | 画面没动、盘上也没动 |
| 成功但结论为否 | `ok=true` + `result_flags` 含 `assertion_failed` | 工具答 `passed:false`；TASK-089 起可见 |
| 自相矛盾的声称 | `ok=true` + `result_flags` 含 `created_conflict` | `created:true` 与 `existed_before:true` 并存 |
| 无法判定的成功（诚实边界） | `ok=true` + `unavailable` / `not_observed` / `not_tracked_deferred` | 无 framebuffer / 没开捕获 / 延迟窗口一帧都没被观测 |
| 证据不完整 | `args_complete=false` 或 `result_json_truncated=true` 或 `error_data_json_truncated=true` 或 `facts_complete=false` | 不得据此下结论。**参数**的完整性与 sidecar 核对结果绑定（§3.1），不再与「行上的前缀有多长」绑定 |
| 文件侧证据缺失 | `file_effect_evidence=not_recorded_in_trace` | 只对**旧版本写出的** trace 成立，见 §3.2 |
| 失败载荷缺失 | `error_data_evidence=not_recorded_in_trace` | 只对**旧版本写出的** trace 成立，见 §3.2 |
| 参数证据缺失 | `args_evidence=sidecar_not_recorded_in_trace` / `sidecar_missing` / `sidecar_mismatch` | 只对**旧版本写出的** trace 或**写不出文件**的那种成立；`sidecar_mismatch` 还给出 `args_sidecar_detail.actual_*` |

---

## 6. 帧代价的取值规则（TASK-092 item B4）

延迟驱动器（`running_game_run_test_scenario` / `running_game_run_stress_test`）**每帧推进一步**，
所以「一帧的代价」是它们 deadline 的**构成**，不是诊断信息。取值规则写在
`modules/mcp_server/mcp_frame_clock.h`，实现在 `.cpp`，读法如下（台账与报告引用的是同一套）：

| 项 | 规则 | 为什么 |
|---|---|---|
| 采样点 | `MCPServer::pump_frame()` 每帧一次，`OS::get_ticks_usec()` | 模块本来每帧都在那里；帧的定义就是「两次 pump 之间的间隔」，不是调用 tool 的时刻 |
| 样本 | 相邻两次采样的差值 | 一次时钟读，无分配、无锁、无 I/O |
| 丢弃的样本 | 差值 = 0（同一微秒内两次，doctest 会这样）或 > 2000 ms（加载卡顿、断点、挂起进程——那是停顿不是帧代价） | 让「代价」这个词只覆盖帧 |
| 窗口 | **最近 15 帧** | 60 fps 下约四分之一秒：一次卡顿不影响，换了工况在一场场景自己的时长内就被反映 |
| 估计值 | 窗口中位数，**截断**到整毫秒，再夹到 [16, 1000] | 见下 |
| 截断 | 16667 µs → **16 ms** | 60 fps 下与 `_frame_cost_ms` 出现之前的硬编码常量**逐字相同**，deadline 公式的行为对快进程零变化 |
| 下限 | 16 ms | 同上；一个比旧常量更短的 deadline 不是这次改动要引入的东西 |
| 上限 | 1000 ms | 比一秒更慢的帧是停顿；deadline 真正的上界是框架的 30 s 天花板（GDR-20） |
| 无样本时 | 下限 16 ms | 从没 pump 过帧的进程（doctest、单帧进程）拿到确定答案。**不**退回 `Engine::get_frames_per_second()`：`Engine::_fps` 的默认值是 **1**（`core/config/engine.h:67`），一个占位值会被读成「每帧 1000 ms」并把每个 deadline 放大 60 倍；而任何能算出 deadline 的进程都已经 pump 过帧（采样在请求被服务之前） |
| 中位数取偶数个时 | 取中间两个中**较大**的那个 | 一种约定必须被选定；对 deadline 而言偏大是不低估一帧代价的那一侧 |

**它替换掉了什么**：TASK-090 读的是 `Engine::get_frames_per_second()`，那是**一秒一次更新的
一秒读数**——一次卡顿会被接下来整整一秒里计算的每一个 deadline 继承。第 8 轮会话实测到后果：
同一个 3 步场景的两个实例相差一秒，拿到的 `timeout_ms` 分别是 `4396` 与 `1150`。中位数窗口
让单个离群值不再移动答案，而**真的慢**的循环（每一帧都慢）会把答案搬到慢的那一侧。

**读法**：行上的 `timeout_ms` 是**由这个估计造出来的**，所以两条相同场景的 `timeout_ms` 不同
只说明它们的**取值时刻**不同，不说明契约变了；`duration_ms` 才是这次调用实际花了多久。
