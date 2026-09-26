# MCP-TRACEABILITY — 一次操作是否有效，以及凭什么判定

* Task: TASK-088 item ⑤；TASK-089 item A 关闭了当时的唯一缺口（文件侧副作用）。
* 口径：本文定义**溯源模型**（字段 / 判定规则 / 失败分类）与**如何用日志判定一次操作是否有效**，
  并给出一次真实会话的产物路径。所有字段名都以实际写出的 JSON 行为准，逐条给出源码位置。

---

## 0. 一句话结论

运行期已经**把判定一次操作是否有效所需的全部事实写进日志**：每条请求一行，每次 `tools/call`
另配一行 `{"event":"capture"}`（截图像素差），并且（TASK-089 起）调用行本身还带着**这次调用改了
哪些文件**（绝对路径 + 前后 sha256/大小 + 是否真的变了 + 文本文件的首尾差异摘要）与**这次调用
答了什么**（`result_json`，有界）。读取侧由 `scripts/mcp_trace_ledger.py` 把这些行合成**每次调用
一行**的有效性台账。

**TASK-088 声明的唯一缺口（文件侧副作用 `not_recorded_in_trace`）已在 TASK-089 补上**，见 §2.4
与 §3.2。

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
                not_tracked 延迟应答通道（工具的实际工作在应答之后），本进程无法观测
                not_recorded 这条 trace 由没有文件侧记录器的版本写出（声明的缺失，不读作「没变」）

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
`request_id` / `tool` / `args`（未截断）/ `times` / `result` / `capture` / `scene_evidence` /
`file_effect`，以及 `facts_complete`。用它区分「证据支持」与「推断」：`facts_complete=false`
的行不得用来下结论。

### 3.2 缺口状态（TASK-089）

* **文件侧副作用：已补**（TASK-089 item A）。调用行带 `file_effect_status` + `file_effects`，
  §2.4 是字段表与界。台账不再写 `file_effect_evidence: "not_recorded_in_trace"`——除非它读的是
  一条**由更早版本写出的** trace，那种情况仍如实写 `not_recorded_in_trace`。旧 trace 与新 trace
  因此可以并存，缺字段一律读作「这份证据不存在」，绝不读作「没有改动」。
* **延迟应答通道（deferred）不算已补**：`file_effect_status` 写 `not_tracked_deferred`。工具的
  实际磁盘工作发生在应答之后（运输层逐帧 tick），同步的每调用缓冲看不到它。声明的边界。
* `args` 超过 4096 B 会被截断（`args_bytes` 仍给真实值，`args_truncated=true`）；`result_json`
  用同一上限（`result_json_bytes` 给真实值）；`error_message` 上限 512 B。这三条是刻意的。
* 捕获只在 `tools/call` 上开（`initialize` / `tools/list` 无副作用可观测）。
* **失败应答的 `data`（例如 `data.suggestion`、`data.parse_error`）不在 trace 上**，只有
  `error_code` 与 512 B 的 `error_message`。TASK-089 修掉了其中一个最要命的形状（`-32602` 只说
  "Parse error"、不说哪一行），但**结构化失败细节仍未入日志**——这是一个仍然开着的缺口。


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

---

## 5. 失败分类（判定用）

| 类别 | 入口 | 判据 |
|---|---|---|
| 协议失败 | 调用行 `ok=false` + `error_code` | `-32700`/`-32600`/`-32601`/`-32602`/`-32000`/`-32001` |
| 工具失败 | 同上，`error_code` 为工具自报 | 消息在 `error_message`（≤512 B）；`data`（`suggestion` / `parse_error`）**不在** trace |
| 无效成功（本模型的核心） | `ok=true` + `scene_effect=unchanged` + `file_effect∈{unchanged,none}` | 画面没动、盘上也没动 |
| 成功但结论为否 | `ok=true` + `result_flags` 含 `assertion_failed` | 工具答 `passed:false`；TASK-089 起可见 |
| 自相矛盾的声称 | `ok=true` + `result_flags` 含 `created_conflict` | `created:true` 与 `existed_before:true` 并存 |
| 无法判定的成功（诚实边界） | `ok=true` + `unavailable` / `not_observed` / `not_tracked_deferred` | 无 framebuffer / 没开捕获 / 延迟应答通道 |
| 证据不完整 | `args_truncated=true` 或 `result_json_truncated=true` 或 `facts_complete=false` | 不得据此下结论 |
| 文件侧证据缺失 | `file_effect_evidence=not_recorded_in_trace` | 只对**旧版本写出的** trace 成立，见 §3.2 |
