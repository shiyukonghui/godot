# MCP-TRACEABILITY — 一次操作是否有效，以及凭什么判定

* Task: TASK-088 item ⑤. Module: `modules/mcp_server`.
* 口径：本文定义**溯源模型**（字段 / 判定规则 / 失败分类）与**如何用日志判定一次操作是否有效**，
  并给出一次真实会话的产物路径。所有字段名都以实际写出的 JSON 行为准，逐条给出源码位置。

---

## 0. 一句话结论

运行期已经**把判定一次操作是否有效所需的全部事实写进日志**：每条请求一行、每次 `tools/call`
另配一行 `{"event":"capture"}`（截图像素差）；调用行的请求身份字段此前**没有被填**
（`method` 为空、`id` 为 null、无 `tool`/`args`），本轮补齐。
读取侧由 `scripts/mcp_trace_ledger.py` 把这两类行合成**每次调用一行**的有效性台账。

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

verdict       = failed                  ok=false（带 error_code/error_message）
                ok_effect_observed      ok=true 且 scene_effect=changed      ← 有效，且效果有画面证据
                ok_no_effect_observed   ok=true 且 scene_effect=unchanged    ← 「报成功但画面没动」
                ok_effect_unavailable   ok=true 但本进程无法取景（诚实边界，不是失败）
                ok_effect_not_observed  ok=true 但没开捕获（无信息，不得读作「无效」）
```

**读法（重要）**：`ok_no_effect_observed` 不等于「这次调用没用」——读工具本来就不该动画面。
它等于「**若这次调用宣称改了画面，画面没有变**」。判一次**写**调用是否有效，看
`ok_effect_observed`；判一次**读**调用，看 `failed` / `ok_effect_*` 中的 `ok` 与 `result_bytes`。

### 3.1 可重建性（facts）

每一行同时给出该调用**可从日志重建的事实**是否齐备：
`request_id` / `tool` / `args`（未截断）/ `times` / `result` / `capture` / `scene_evidence`，
以及 `facts_complete`。用它区分「证据支持」与「推断」：`facts_complete=false` 的行不得用来下结论。

### 3.2 已知缺口（声明，不掩盖）

* **文件侧副作用没有写进运行期日志。** 调用行只有 `result_bytes`，没有「这次调用改了盘上哪个
  文件的 sha」。像素差覆盖的是**画面侧**副作用；文件侧目前只能由工具自身的响应（例如
  `project_write_text_file` 回 `sha256`/`size`）或工具外核验（`project_read_text_file`、
  `Get-FileHash`）补。台账里该字段显式写 `file_effect_evidence: "not_recorded_in_trace"`，
  不写空成功。
* `args` 超过 4096 B 会被截断（`args_bytes` 仍给真实值，`args_truncated=true`）；`error_message`
  上限 512 B。这两条是刻意的，`mcp_trace.h:120-125` 有据。
* 捕获只在 `tools/call` 上开（`initialize` / `tools/list` 无副作用可观测，
  `mcp_capture.h:166-169`）。

---

## 4. 实测演示（真实会话）

驱动：`C:\Users\wyl\AppData\Local\Temp\mcp-recovery\work\task088\mcp088_live_evidence.ps1`
（窗口化，**非 headless**：headless 无 framebuffer，捕获恒 `unavailable`，不得拿来顶替）。
产物根：`…\work\task088\live\`。

| 产物 | 路径 | 实测摘要 |
|---|---|---|
| 编辑器 trace | `live\trace-editor.jsonl` | 10 行；`trace_opened` + 5 条调用 + 4 条 capture |
| 游戏 trace | `live\trace-game.jsonl` | 7 行 |
| 编辑器截图 | `live\shots-editor\` | 8 个 PNG（4 组 before/after），每个 78 036 B，**2978×1793 原图** |
| 游戏截图 | `live\shots-game\` | 6 个 PNG（3 组），每个 12 266 B |
| 编辑器 `tools/list` 原文 | `live\editor-tools-list.json` | 46 810 B，154 条工具 |
| 台账（文本 / JSON） | `live\ledger-editor.txt` / `.json` | `calls=4`，`ok_effect_observed=1 / ok_no_effect_observed=3`，`facts_complete 4/4` |

真实调用（编辑器侧）：`editor_open_scene`（改）→ `editor_get_scene_tree`（读）→
`editor_set_node_property` ×2（同一颜色写两次）。台账（`live/ledger-editor.txt`）**逐行实测**：

```
calls=4 malformed_lines=0
verdicts: ok_effect_observed=1, ok_no_effect_observed=3

seq    req_id   tool                        dur_ms  ok    err  scene_effect  verdict
2      102      editor_open_scene           18      True  0    unchanged     ok_no_effect_observed
3      103      editor_get_scene_tree       18      True  0    unchanged     ok_no_effect_observed
4      104      editor_set_node_property    18      True  0    changed       ok_effect_observed
5      105      editor_set_node_property    19      True  0    unchanged     ok_no_effect_observed

rows whose reconstructible facts are all present: 4/4
```

读法：**第 4 行是「有效」**（写入真的上了屏，像素差 `changed`），**第 5 行是同参数再写一次**
（`ok=true` 但画面没动 → `ok_no_effect_observed`，即本模型要钉住的「报成功但没动」形态）。
`id`（102–105）与 `tool` 一栏能在台账上读出来，就是 §2.3 那处补齐的直接结果——修复前的同一份
trace 里这两列分别是 `null` 与空。

像素差实测：编辑器侧 2978×1793 = 5 339 554 像素；`changed:false` 的组
`before.sha256 == after.sha256`（例：`0002` 组两侧同为
`c337ce706bf7bcd85435b45b4ffb10b7005a727536b4fec9e93244024fc9bbbc`），`changed:true` 的那组
两侧 sha 不同且 `changed_pixels>0`。判定规则在这份证据上如实工作，演示没有被粉饰。

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
| 工具失败 | 同上，`error_code` 为工具自报 | 消息与 `data.suggestion` 在响应里，**不在** trace |
| 无效成功（本模型的核心） | `ok=true` + `scene_effect=unchanged` | 画面未变 |
| 无法判定的成功（诚实边界） | `ok=true` + `unavailable` / `not_observed` | 无 framebuffer / 没开捕获 |
| 证据不完整 | `args_truncated=true` 或 `facts_complete=false` | 不得据此下结论 |
| 副作用无日志 | `file_effect_evidence=not_recorded_in_trace` | 声明的缺口，见 §3.2 |
