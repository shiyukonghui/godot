# REPORT-044 — 捕获：操作前后截图 + 与操作日志同行记录（追踪的可选扩展，零契约变更）

> 任务书：`docs/tasks/TASK-044-before-after-capture.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 规范：`DESIGN-DETAIL.md` **§24/GDR-26（追踪）** 与 **§25/GDR-27（捕获）**（设计已用户确认，本任务**未改**规范）。
> 分支 `feature/mcp-server-module`。**零契约变更**：不新增工具、不改任何 `inputSchema`/`description`；
> 截图与结论**只进日志与文件**，绝不进响应。
> `docs/tools_list.renamed.json` sha256 仍为
> `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256`，与 REPORT-038 记录**逐字节相同**。
> 改动只落在 `modules/mcp_server/**`（13 个文件，见 §0）。

## 0. status / commits

- **status：`done`** —— 五道门 + 门⑥ 三段式全绿；**零行为三条对照全绿（含与任务前二进制逐条 sha256 对照）**；
  验收 8 条逐条有实测证据；两个端点各跑通一条链。
- **commits**：
  - **`39fc7179e7`** — `mcp_server: add the opt-in before/after call capture (TASK-044, GDR-27)`
    —— **这是承载全部实现代码的锚点（D86）**。
  - 紧随其后的第二条提交 —— `mcp_server: doctests and live evidence for the call capture (TASK-044)`
    （8 个 doctest 用例 + 两个实测脚本）。
  - 第三条（仅文档）—— 本报告。
  - **构建时**（每一次门/battery 运行的那一刻）`git rev-parse --short HEAD` = `2f520cf903`，
    `bin\godot.windows.editor.x86_64.console.exe --version` = `4.8.dev.custom_build.2f520cf90`
    —— **`--version` == HEAD 在运行时成立**；提交发生在最后一次构建之后，故运行中二进制的内嵌哈希
    是**代码提交的父提交**。两者内容同一：提交不改文件，且 §12 给出全部改动文件的 sha256 与实测时的
    逐字节一致性核对。§17「勘误」在提交后按 `git HEAD` 重建并复跑了整条 battery，给出最终锚点。
- 工作树收尾只剩**既有的**未跟踪物：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`。

### 改动清单（13 个文件，全部在 `modules/mcp_server/**`）

| 文件 | 角色 | bytes | sha256（实测时） |
|---|---|---|---|
| `mcp_capture.h` | **新** 捕获引擎接口与 `Config` | 12115 | `7ca6ae9eca0111ddc5365e10d6b9fd5afbe0861d3afe49adc1cf4c356f08d133` |
| `mcp_capture.cpp` | **新** 配置解析 / 取景 / 帧状态机 / 落盘 / 判定 / 追加日志行 | 23942 | `0fcaf3159e8d5a8f284623fd9d61358a8f968b6c8c235c27b5a097ad26d36875` |
| `mcp_trace.h` | `Record` 增 `capture*` 字段；`record_event_line()` | 10163 | `59ed8e17e36cce9e993f1b825582224d8dcd085ca9f3687c3147d39ea710eebe` |
| `mcp_trace.cpp` | 调用行拼 `capture`；事件行不消耗请求 `seq` | 13060 | `018bd62377b474f7c879effad8e9c946ee3392571cdb12a02a79ce9eeeaad477` |
| `mcp_server.h` | `capture_config` / `capture_engine` 成员 + 诊断读取器 | 8394 | `bb163e50624d9bfb7645cf485d4caee847c33b766ebb4f3b46337548b1560f74` |
| `mcp_server.cpp` | 开关解析、`arm`/`finish`、`begin_frame`/`tick`、shutdown | 25234 | `8a2ae64f2bd532ebae2b09cd82eb907721d300f0c520c2681c1331bc469498c4` |
| `tools/tool_helpers.h` | **提升** `compare_screenshot_pixels` + `MAX_SCREENSHOT_DIFF_DIMENSION` | 76065 | `0a254356a98ba0f343d5b468ebe98c447573df82d5bae71f68471fb1eed2d4ea` |
| `tools/tool_helpers.cpp` | 同一份像素比对实现（verbatim 迁移） | 132337 | `dd0f9d4eb22b5e40192721b7e733b7c825bc18ab410eee185d1c36b5614fd047` |
| `tools/editor_testing_read.cpp` | 改为调用共享实现（自身契约与错误顺序不变） | 26092 | `7dd93573ed082c229d53c30547e9effaface4fefc62d24521d5f37e74e7926e7` |
| `tests/test_mcp_server.h` | 8 个 TASK-044 doctest 用例（+239 断言） | 992676 | `12ef473064ece93ac5c3b80fb291e73570dabf670aec64ce7247ac655c76d41c` |
| `scripts/check_narrowing_points.py` | 门⑥ PINNED：两个 `G24-DIFF-PIXEL-*` 随代码改址 | 51184 | `ab05939026406b7953b03ab2d200058aaa41bbde02c20136a9e0fa753d200908` |
| `scripts/mcp044_capture_evidence.ps1` | **新** 四相实测（editor/headless/game/diff-image） | 51993 | `1411f3538e58491ef48473e33fd31dfef83abd5f19049d7b28121533841c81d0` |
| `scripts/mcp044_zero_change.ps1` | **新** 任务前二进制 / off / on 三方逐字节对照 | 9343 | `e58958cb9121f2bd0e1abb8d57f6d1e5978efd973311585dd5d652d96b3bbcba` |

> 两个 `.ps1` 均为**纯 ASCII**（字节级自检 `non-ascii 0`，见 §8）。
> `DESIGN-DETAIL.md` **未改一个字**；对 §25 的落笔请求见 §16。

---

## 1. 形态与开关（用户四项选择，逐条照办）

| 用户选择 | 实现 | 证据 |
|---|---|---|
| ① 三档开关，**默认 off** | `--mcp-capture=off\|on_error\|every_call`（`--mcp-capture <v>` 同形，**最后一条胜出**） > `ProjectSettings: godot_mcp/capture`（接受 `godot_mcp.capture` 点号别名） > **off** | doctest `TASK-044: the capture switch is off by default…`；实测 `[MCP] capture=off (default; …)` |
| ② 取景 `editor\|2d\|3d`，**默认 editor** | `--mcp-capture-viewport=`；编辑器侧 `editor` = `get_base_control()->get_viewport()`，`2d` = `EditorInterface::get_editor_viewport_2d()`，`3d` = `EditorInterface::get_editor_viewport_3d(0)`；游戏侧 = 游戏窗口（日志里 viewport 名为 `game`） | §3 引擎依据；实测三个视口各出一图（§6-5） |
| ③ **存原图且不设上限** | **从不删除任何文件**；每行带累计 `total_bytes`；启动日志打印目录与模式；累计超 **1 GB 只 WARN 一次** | §9；doctest `the 1 GB warning is announced once and deletes nothing` |
| ④ **自动跑像素 diff**，`changed` / `changed_pixel_ratio` 写进日志 | 与 `editor_analyze_screenshot_diff` **共用同一实现**（阈值同为默认 10）；差异图按需另存（`--mcp-capture-diff-image=on`，默认不落） | §8；实测 4 组 `changed:true/false` |

配套开关：`--mcp-capture-dir=<OS 路径>`，默认 = **追踪文件同目录下的 `shots/`**
（`default_dir_for_trace()`；`user://x.jsonl` → `user://shots`，`C:/tmp/x.jsonl` → `C:/tmp/shots`）。

启动日志（实测原文，来自 `editor-every-call-2d.out.log`）：

```
[MCP] capture enabled: mode=every_call viewport=2d dir=res://mcp044_shots diff_image=false
[MCP] capture keeps every PNG it writes (no size limit, nothing is ever deleted); the trace line carries total_bytes and a single WARN is printed above 1073741824 bytes
```

关闭时（实测原文）：`[MCP] capture=off (default; use --mcp-capture=on_error|every_call together with --mcp-trace=<path>)`

**默认关闭是结构性的**：`MCPServer::capture_engine` 为 `nullptr`，请求路径上**连一次分支都不会进**
（`handle_jsonrpc_request` 只在 `capture_engine != nullptr && is_active()` 时才预解析 payload）。

---

## 2. 日志 schema 与两条**真实样例**

### 2.1 调用行（§24 既有行）新增成员

```json
"capture": {"mode": "every_call|on_error", "viewport": "editor|2d|3d|game", "status": "pending|unavailable", "reason": "…(仅 unavailable)"}
```

- `status:"pending"` = 会有一条捕获行跟着（**同一 `seq`**）；
- `status:"unavailable"` = 这次调用取不到图，`reason` 说明原因（headless / 延迟通道，见 §12-D1）；
- **`off` 时该成员根本不出现**（这是零行为对照的前提之一）。

### 2.2 应答之后追加的捕获行（**独立一行，不占用请求 `seq`**）

| 字段 | 类型 | 含义 |
|---|---|---|
| `event` | string | 恒为 `"capture"` |
| `seq` | int | **与它所属调用行相同的 `seq`**（唯一的关联键） |
| `ts_ms` | int | 墙钟（Unix epoch 毫秒），供跨进程排序 |
| `tool` | string | 被捕获调用的工具名 |
| `mode` / `viewport` | string | 生效的开关与取景 |
| `status` | string | `done` \| `failed` \| `unavailable` |
| `before` / `after` | object\|null | `{path, sha256, bytes, width, height}`；`unavailable`/`failed` 时为 `null` |
| `frames_waited` | int | 「后」比「前」晚了几个**帧计数**；**恒 ≥ 1**（自证「再渲染至少 1 帧」） |
| `changed` | bool\|null | 两张图是否不同（`status != done` 时为 `null`） |
| `changed_pixel_ratio` | float\|null | `changed_pixels / total_pixels`（0..1） |
| `changed_pixels` / `total_pixels` | int | 判定的原始计数（让判定可被复核） |
| `diff` | object | 差异图：`{}`（默认）或 `{path, bytes, sha256}` |
| `total_bytes` | int | **累计**已写 PNG 字节数（单调递增） |
| `reason` | string | 仅失败/不可用时出现 |

### 2.3 样例 A — `changed:false`（**本任务的存在理由**，实测原文）

两次**完全相同的调用**（同一工具、同一参数），都被报成功：

调用行（`seq` 4，第一次）：
```json
{"id":2203,"args":"{\"path\":\"ColorRect\",\"property\":\"color\",\"value\":\"#00ff00\"}","capture":{"mode":"every_call","status":"pending","viewport":"2d"},"error_code":0,"method":"tools/call","ok":true,"result_bytes":255,"seq":4,"tool":"editor_set_node_property"}
```
捕获行（`seq` 4）：`changed:true`，前后 sha256 **不同**：
```json
{"after":{"bytes":24936,"height":1793,"path":"res://mcp044_shots/0004_after.png","sha256":"87731a87b9d728ae2350f035b7b25dbeba46b326829596a155588291bbba3f2a","width":2978},"before":{"bytes":24936,"height":1793,"path":"res://mcp044_shots/0004_before.png","sha256":"865c2f934c834d034fe2554503c41027ec57df1053f9ddef414098e887f3f36f","width":2978},"changed":true,"changed_pixel_ratio":0.0200016705515105,"changed_pixels":106800,"diff":{},"event":"capture","frames_waited":2,"mode":"every_call","seq":4,"status":"done","tool":"editor_set_node_property","total_bytes":149616,"total_pixels":5339554,"ts_ms":1790210220901,"viewport":"2d"}
```

调用行（`seq` 5，**同一参数再来一次**）：
```json
{"id":2204,"args":"{\"path\":\"ColorRect\",\"property\":\"color\",\"value\":\"#00ff00\"}","capture":{"mode":"every_call","status":"pending","viewport":"2d"},"error_code":0,"method":"tools/call","ok":true,"result_bytes":255,"seq":5,"tool":"editor_set_node_property"}
```
捕获行（`seq` 5）：`changed:false`，前后 sha256 **相同**：
```json
{"after":{"bytes":24936,"height":1793,"path":"res://mcp044_shots/0005_after.png","sha256":"87731a87b9d728ae2350f035b7b25dbeba46b326829596a155588291bbba3f2a","width":2978},"before":{…同 sha256 87731a87…},"changed":false,"changed_pixel_ratio":0.0,"changed_pixels":0,"diff":{},"event":"capture","frames_waited":2,"mode":"every_call","seq":5,"status":"done","tool":"editor_set_node_property","total_bytes":199488,"total_pixels":5339554,"ts_ms":1790210221371,"viewport":"2d"}
```

### 2.4 样例 B — `unavailable`（headless，实测原文，`status`/`reason` 齐全、无任何图）

```json
{"after":null,"before":null,"changed":null,"changed_pixel_ratio":null,"diff":{},"event":"capture","frames_waited":1,"mode":"every_call","reason":"headless display server 没有纹理存储","seq":2,"status":"unavailable","tool":"editor_get_scene_tree","total_bytes":0,"ts_ms":1790209831198,"viewport":"editor"}
```
对应调用行同时带 `"capture":{"mode":"every_call","status":"unavailable","viewport":"editor","reason":"headless display server 没有纹理存储"}`。

---

## 3. 三个视口的**引擎依据（文件:行）**

| 取景 | 引擎 API | 文件:行 | 实测 |
|---|---|---|---|
| `editor`（整窗） | `EditorInterface::get_base_control()` → `Control::get_viewport()` | `editor/editor_interface.h:125`（`Control *get_base_control() const;`） | **3840×2054**，164018 B |
| `2d` | `EditorInterface::get_editor_viewport_2d()` | **`editor/editor_interface.h:130`**（`SubViewport *get_editor_viewport_2d() const;`） | **2978×1793**，24936 B |
| `3d` | `EditorInterface::get_editor_viewport_3d(int p_idx = 0)` → 传 `0` | **`editor/editor_interface.h:131`**（`SubViewport *get_editor_viewport_3d(int p_idx = 0) const;`） | **2978×1790**，1206791 B |
| 游戏侧 | `SceneTree::get_singleton()->get_root()` 的 `ViewportTexture` | `scene/main/scene_tree.h`、`scene/main/window.h` | **1152×648**（隐藏窗口的默认尺寸） |

- 任务书说「已初查：`editor_interface.h:130-131`」—— **实测一致**，签名与可用性无偏差。
- **不重复造轮子**：取景的「有没有帧缓冲」判据复用 `MCPTools::game_framebuffer_available()`
  （`tools/tool_helpers.cpp:2333`，与两个截图工具同一份实现），`mcp_capture.cpp` 不再写第二份 headless 测试。
- **编辑器专有 API 全在 `MCP_EDITOR_TOOLS_ENABLED` 守卫内**（`editor/editor_interface.h` 的 include 也在守卫内），
  游戏构建不含编辑器代码。
- **游戏侧忽略 `--mcp-capture-viewport`**：游戏进程只有一个窗口，日志里 viewport 名为 `game`
  （实测 `[MCP] capture enabled: mode=every_call viewport=game dir=res://mcp044_shots_game`）。

---

## 4. 红 / 绿（TDD）

**红（缺行为时确实失败）**：实现完成后，用**一次受控回退**证明这 8 个用例真的依赖新行为 ——
在 `Engine::arm()` 顶部临时插入 `return -1;`（不 arm 任何捕获），`build_local.cmd -Force` 重建后：

```
[doctest] test cases:   8 |   3 passed |  5 failed | 1706 skipped
[doctest] assertions: 181 | 135 passed | 46 failed |
[doctest] Status: FAILURE!
```

失败的正是 5 个「依赖捕获行为」的用例（完整周期 / unchanged / on_error / unavailable / 1GB 可见性）；
另外 3 个（开关解析、事件行不占 seq、共享比对的数值）不依赖 `arm`，**红阶段依旧绿**——这本身就是
「断言与它声称测的东西对齐」的旁证。红阶段输出存在 `%TEMP%\mcp044_red.txt`。
（**诚实声明**：红阶段是「实现完成后」做的受控回退，不是「先写测试后写实现」的字面顺序；
回退代码已删除，最终树中不存在。）

**绿（最终树）**：

```
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="*TASK-044*"   exit 0
[doctest] test cases:   8 |   8 passed | 0 failed | 1706 skipped
[doctest] assertions: 239 | 239 passed | 0 failed |
[doctest] Status: SUCCESS!
```

**用例清单**（`tests/test_mcp_server.h`，namespace `Task044`）：注入式取景提供器（`SnapshotFunc`）让
**无显示服务器、无 SceneTree 的 doctest 进程也能跑完整状态机**（PNG 编码、sha256、像素比对、JSON 行、
字节计数器全是生产代码路径）：

1. 开关默认值 / 优先级链 / 目录解析 / 三个配套开关 / payload 判定 / `capture_engine == nullptr`；
2. 完整周期：`before`/`after` PNG 落盘并可解码、捕获行 `seq` 与调用行相同、`frames_waited ≥ 1`、
   `total_bytes` 与两个文件字节数相等、`diff` 默认不落；
3. **不改屏 → `changed:false`**（本任务的存在证明，doctest 版）；
4. `on_error` 只捕获失败调用（成功调用**连 `capture` 成员都不出现**）；
5. 无帧缓冲 → `unavailable` + reason + **一个文件都不写**（含生产 `snapshot()` 在本进程的实测）；
6. 1 GB 阈值：只 WARN 一次、`total_bytes` 单调、**一个文件都没删**；
7. 事件行共用文件但**不消耗请求 `seq`**（`get_lines_written()` 语义不变）；
8. 共享像素比对的数值与工具 doctest 钉住的完全相同（含量纲不匹配的 `-32602` 文案）。

---

## 5. 门

| 门 | 命令 | 结果 |
|---|---|---|
| ⓪ 重建 | `scripts\build_local.cmd -Force`（**从 cmd 启动**，`tests=yes`，串行，不抑制输出） | exit **0**；`--version` = `4.8.dev.custom_build.2f520cf90` == `git HEAD 2f520cf903` |
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1` | **3/3 PASS**（editor 9888 / game 9889 / 9877 pid 守卫），exit 0 |
| ② 三类证据 + 端到端链 | §6 的 62 项实测（含两个端点的多步链） | **62/62 PASS**，exit 0 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **285/285 cases，16187/16187 断言，0 failed**，exit 0（基线 277/15948 → **+8 cases / +239 断言**，只增不减） |
| ④ 全引擎回归 | `--headless --test` | **1711/1711 cases，440469/440469 断言，0 failed，3 skipped**，exit 0 |
| ⑤ 批收口 | `scripts\accept_m1.ps1` **连跑两次** | 两次都 **22/22 cases passed**，exit 0；**两次 PASS 清单逐行相同（22 行）**，`PASS-LIST-IDENTICAL` |
| ⑥ 收窄点（三段式） | 见 §11 | 三段全绿 |

### 5.1 门⑥ 三段式（§22.3b 规则 4：**新增点逐条列**）

1. `python scripts\check_narrowing_points.py` → exit **0**：
   `scanned: 73 / pinned: 73 / coverage: 17 declared spellings`，**无 `[UNLISTED]`、无 `FAIL`**；
   剩下 10 条是**既有**的 `pinned_line` 漂移提示（按 marker id + occurrence 匹配，非失败）。
2. `python scripts\check_narrowing_points.py --coverage` → exit **0**（17 条声明拼写与边界原文）。
3. `powershell … -File scripts\mcp031_gate6_coverage_probes.ps1` → **101/101 PASS**，exit 0，
   且 `B1b_restored_byte_identical` / `B1b_worktree_clean_of_probes` 证明探针树被逐字节还原、工作树干净。

**新增收窄点 × 经过的闸门 × 证据**（规则 4 要求的逐条形式）：

| 新增/移动点 | 经过的闸门 | 证据 |
|---|---|---|
| `tools/tool_helpers.cpp:953` `G24-DIFF-PIXEL-CHANGED`（**从 `editor_testing_read.cpp:445` 迁移**） | 门⑥ 扫描器（`ctor_color` 拼写）+ PINNED 清单 | 扫描器报 `[safe ] … G24-DIFF-PIXEL-CHANGED`；PINNED 条目已随代码改址 |
| `tools/tool_helpers.cpp:957` `G24-DIFF-PIXEL-UNCHANGED`（**从 `editor_testing_read.cpp:448` 迁移**） | 同上 | 同上 |
| `mcp_capture.cpp`（**新文件，含 `float`/`Color` 构造？→ 无**） | 门⑥ 只扫 `tools/**`，新文件不在扫描面内；**且实测全文件不含任何声明拼写** | `scanned: 73` 与任务前**同数**（迁移不增不减）；`--coverage` 17 条覆盖面对本文件无命中 |
| `tools/editor_testing_read.cpp` 原两个点**消失** | 门⑥ 的「标记消失 = stale entry 失败」检查 | 该文件的 PINNED 条目改为**空表 + 说明注释**，扫描器 exit 0（若留着旧行号会立刻 `FAIL`） |

> 迁移的**唯一**收窄后果：`G24-THE-GATE` 的行号随之漂移（1161 → 1552），已按提示更新 PINNED（非语义变化）。

---

## 6. 验收 8 条 —— 逐条证据

全部来自 `scripts/mcp044_capture_evidence.ps1` 四相实测，运行在同一二进制
（`--version 4.8.dev.custom_build.2f520cf90`，engine sha256 `a8a3515387dcc28bd38647102d163dac0862ce8034f05db1b684896ffaee58e4`）：

| 相 | 检查 | 结果 |
|---|---|---|
| `editor`（窗口化编辑器 @9888） | 40 | **40/40 PASS** |
| `headless`（`--headless` 编辑器 @9888） | 8 | **8/8 PASS** |
| `game`（窗口化游戏 @9889） | 9 | **9/9 PASS** |
| `diff-image`（`--mcp-capture-diff-image=on`） | 5 | **5/5 PASS** |
| **合计** | **62** | **62/62 PASS**，退出码全 0 |

### 验收 ① 存在理由实验

- **构造「报成功但什么都没发生」**：`editor_set_node_property{ColorRect.color="#00ff00"}` **原样调用两次**。
  两次响应都是 `error_code 0 / ok:true`（实测 `editor_mutations_reported_success` PASS）。
  - 第一次 → **`changed:true` + `changed_pixel_ratio` = 0.0200016705515105**（106800 / 5339554 像素），
    前后 sha256 `865c2f93…` ≠ `87731a87…`；
  - 第二次 → **`changed:false` + `changed_pixel_ratio` 0.0**，前后 sha256 **相同** `87731a87…`。
- **真实的改变**另有 3 组：游戏侧 `running_game_set_node_property{ColorRect.color="#0000ff"}` →
  `changed:true`、ratio **0.321502057613169**（240000 / 746496），同参重放 → `changed:false`（§6-⑦）。
- **失败调用也被如实度量**：`{property:"no_such_property_xyz"}` → `-32001`，捕获行 `changed:false`
  （截图照拍，判定不因失败而编造）。
- **两个模块自己的工具复核同一对图**：`editor_analyze_screenshot_diff{before,after}` 答
  `identical:false / changed_pixels:106800 / total_pixels:5339554 (2978×1793)` —— 与捕获行的数字**逐值相同**。
- **doctest 版**：`mcp_server_test_fixture_capture` 下两张相同 `Image` → `changed:false`（§4-3）。

### 验收 ② 零延迟

**必须区分两个时钟**（实测数据，`editor_get_scene_tree` 同参）：

| 时钟 | off | every_call | 差 |
|---|---|---|---|
| **服务端 `duration_ms`**（收到请求 → 产出响应） | n=5，min 0 / **median 0** / max 1 ms | n=11，min 7 / **median 7** / max 8 ms | **+7 ms** |
| curl 往返（**背靠背**） | n=5，median 18.5 ms | n=5，median **453.6 ms** | +435 ms |
| curl 往返（**间隔 2.5 s**） | — | n=5，median **30.7 ms** | +12 ms |

**结论（诚实、可归因）**：
- **响应路径只增加了那一次 framebuffer 拷贝**（+7 ms），**编码 / 落盘 / diff 全在应答之后**——
  这正是任务书 §2.1「零延迟」要求的语义，实测成立；`every_call` 间隔取样时往返回到 ~31 ms，
  与 off 的 ~18.5 ms 同量级。
- **但背靠背往返增长 23 倍是真实的**：应答之后主线程被「2 张 2978×1793 PNG 编码 + 533 万像素比对」
  占用约 400 ms，期间不 pump HTTP，**下一个**请求因此排队。断言 `zero_latency_client_round_trip`
  要求三组分布同时存在（否则就是「无法归因」），实测 PASS。
- 因此**验收 ② 的字面措辞「未见系统性增加」只在「响应路径」这一层成立**；「进程对连续请求的响应能力」
  确实系统性下降。这是**设计假设与引擎事实的差**（设计写「一次 framebuffer 图像拷贝（廉价）」，
  拷贝确实廉价，编码与比对不廉价），**报决策者**（§12-D4 / §16）。
  最大的一笔是像素比对（`Image::get_pixel` 逐像素，约 300–400 ms），建议后续任务改为读
  `Image::get_data()` 原始缓冲（语义不变，两侧同时受益）。

### 验收 ③ 零行为对照（**含任务前二进制**）

`scripts/mcp044_zero_change.ps1`，22 条探针（**含全量 `tools/list`** + 18 个 `tools/call`，
覆盖成功 / `-32001` / `-32602` / `-32601` / 未知方法）：

| 运行 | 二进制 | 开关 |
|---|---|---|
| `pre` | **任务前二进制**（`git stash -u` 撤到 `2f520cf903` 后 `build_local.cmd -Force` 重建，另存副本） | 开关尚不存在 |
| `off` | 本任务二进制 | `--mcp-capture=off` |
| `on` | 本任务二进制 | `--mcp-capture=every_call`（**该跑出 18 条捕获行**，证明开关确实开着） |

```
pre=off=on   × 22/22
[PASS] pre_vs_off_byte_identical  compared=22 changed=0 unstable=0
[PASS] pre_vs_on_byte_identical   compared=22 changed=0 unstable=0
```

⇒ **`off` 与任务前二进制逐条 sha256 相同**；**`on` 时响应同样逐条相同**（截图只进日志与文件）。
**全量 `tools/list` 的所有 171 条 `description`/`inputSchema` 在这一次响应里被逐字节比过。**
（这是「与任务前二进制对照」的最强形态：三个二进制/配置 × 22 条探针，**0 条不稳定**。）

补充：`scripts/mcp038_zero_change.ps1`（§24 的「关-关-开」三跑模板）**7/7 checks passed，
probes=22 stable=22 changed=0 unstable=0**，即 §24 的三条对照模板也仍然全绿。

### 验收 ④ 三档开关

| 档 | 证据（实测） |
|---|---|
| `off` **不产生文件** | `switch_off_writes_no_capture_line`：trace 6 行、**capture 事件 0**、**无任何调用行带 `capture` 成员**；`switch_off_writes_no_png`：项目下 **0 个 PNG**；`switch_off_startup_log_says_off` PASS |
| `on_error` **只对失败调用产图** | 3 次调用（open_scene 成功 + read 成功 + 写非法属性 `-32001`）：**调用行带 `capture` 成员的恰好 1 条**、**捕获行恰好 1 条**、成功的那次 read **既无成员也无事件**；唯一捕获行 `seq=4 status=done changed=false` |
| `every_call` **全产图** | 15 次 `tools/call` → **15 条捕获行、15 条 `done`**，25 个 PNG |

### 验收 ⑤ 三个视口

| 视口 | 尺寸 | 文件 | sha256（前 16） | 判定 |
|---|---|---|---|---|
| `2d` | **2978×1793** | 24936 B | `865c2f93…` | 真图（>1024 B、双向 ≥100 px、`after.sha256` 64 hex） |
| `3d` | **2978×1790** | 1206791 B | `32f8e43f…` | 真图 |
| `editor` | **3840×2054** | 164018 B | `d6053c3f…` | 真图（**整窗比子视口大**，符合预期） |

`three_viewports_are_not_the_same_frame`：三者 sha256 **互不相同（distinct=3）** ⇒ 不是「同一张全黑占位图」。
`2d` 还额外被 §6-① 的 `changed:true` 钉住：**画面内容真实且可变**。

### 验收 ⑥ headless

- `--headless -e` 下 3 次调用 → **3 条 `status:"unavailable"` 捕获行**，
  `reason` **逐字节等于** `headless display server 没有纹理存储`，`before`/`after`/`changed` 均为 `null`；
- **默认目录**（拿掉 `--mcp-capture-dir`）被启动日志如实打印：
  `[MCP] capture enabled: mode=every_call viewport=editor dir=C:/Users/…/mcp044-evidence/shots`；
- **一个文件都不写**：该目录下的文件数 **0**（目录本身由启动时的 `make_dir_recursive` 建立，见 §12-D2）；
- **工具调用本身照常**：`editor_get_scene_tree` → `0`、非法属性 → `-32001`、
  `editor_capture_screenshot` → **`-32000`**（与任务前**一模一样**：捕获从不改写任何响应）。

### 验收 ⑦ 两个端点各一条链

**9888（编辑器）**：`editor_open_scene` → `editor_get_scene_tree` → `editor_set_node_property`
（真改）→ **同参再来一次**（不改）→ `editor_set_node_property`（非法属性，`-32001`）→
`editor_analyze_screenshot_diff`（读了捕获写下的两张 PNG）。
**9889（游戏）**：`running_game_get_scene_tree` → `running_game_set_node_property`（真改，ratio 0.32）→
**同参再来一次**（`changed:false`）。两链的每步都产出了捕获行，且 `seq` 与调用行一一对齐。

### 验收 ⑧ 可见性

- **`total_bytes` 随每次捕获单调增加**：`49872 → 99744 → 149616 → 199488 → 249360 → 299232 → … → 748080`
  （最后一个数字 = 2 × 每次捕获的 PNG 字节数累计）；doctest 与实测各有一条 `total_bytes_is_monotone`。
- **绝不自动删除任何文件**：15 次 `done` 捕获后，`mcp044_shots` 下 **恰好 30 个 PNG**
  （`no_capture_file_was_deleted`：expected 30 found 30）。
- **超阈值只 WARN 一次**：doctest 把阈值降到 1 字节走**同一条生产代码路径**，第 2 次捕获后
  `total_bytes` 继续增长、**先触发的那个 capture 的两个 PNG 仍在盘上**；
  实测运行亦留下唯一一行 WARN：`[MCP] capture directory '…' passed 1 bytes (191 bytes of PNGs); nothing is deleted - remove old shots yourself`。
  **真实的 1 GB 阈值未在现场跑到**（需要写满 1 GB）——**这一条的正确性由 doctest 断言，不由现场**，
  如实声明。

### 附加（不在 8 条内，但覆盖了用户选择④的按需落盘）

`diff-image` 相：`--mcp-capture-diff-image=on` → 启动日志 `diff_image=true`；
捕获行出现 `diff.path=res://mcp044_shots_diff_image/0003_diff.png`、`diff.bytes=24938`、`sha256` 64 hex，
且 `before`/`after` 两张仍在（**差异图是第三个文件，不是替换**）。

---

## 7. 零延迟与零行为对照（汇总）

| 主张 | 证据 | 结论 |
|---|---|---|
| 应答不等帧、不做编码/diff | §6-② 服务端 `duration_ms`：off median 0 ms → on median 7 ms（**只多一次拷贝**） | ✅ |
| 应答之后才编码/落盘/diff | `MCPServer::pump_frame` 里 `http_server->poll()` **之后**才 `capture_engine->tick()`；代码位置可复核（`mcp_server.cpp`） | ✅ |
| 「后」= 再渲染至少 1 帧 | 每条捕获行 `frames_waited ≥ 1`（实测集合 `1,2,2,3,1,2,1,1,1,1,1,1,1,1,1`） | ✅ |
| `off` == 任务前二进制 | 22/22 探针 sha256 相同（§6-③） | ✅ |
| `on` == 任务前二进制（响应） | 22/22 探针 sha256 相同（§6-③） | ✅ |
| 截图绝不进响应 | `mcp_capture.cpp` 不接触任何 `Dispatch`/`content_result`；响应字节对照即证 | ✅ |
| 关闭时不付代价 | `capture_engine == nullptr`，请求路径只多一次空指针判断；`off` 跑 6 行 trace、0 事件、0 PNG | ✅ |

---

## 8. diff 算法提升后 `editor_analyze_screenshot_diff` **未变的行为证据**

- **提升方式**：`tools/editor_testing_read.cpp` 里的像素循环**逐字搬迁**到
  `tools/tool_helpers.{h,cpp}`（`MCPTools::compare_screenshot_pixels`，与 TASK-011 提升 PNG 写入器同法）。
  函数体只改了四处：去掉 `static`、两个形参改名 `a`/`b`、尺寸不匹配的文案改成由调用方给的标签、
  新增 `p_build_diff_image`（捕获默认不画差异图，省掉一半 `set_pixel`）。
  **阈值语义、`get_r8()` 逐通道判定、`MAX(dr,MAX(dg,db))`、差异图两种颜色、`Math::snapped(..,0.01)`
  全部原样**；空图上的除零**故意不设守卫**（与原实现逐字一致）。
- **未被改变的证据**：
  1. 该工具**自带的 doctest**（`editor_analyze_screenshot_diff diffs real PNG bytes`）**未改一行**，
     在最终二进制上 **全绿**（门③ 285/285、门④ 1711/1711 都包含它）；
  2. 该工具**自身的契约**（`-32602` 尺寸不匹配、轴向上限 4096 的拒绝**顺序在尺寸检查之后**、
     `threshold` 0..255、`identical/changed_pixels/total_pixels/diff_percentage/threshold/width/height/diff_image_base64`
     字段与 `snappedf` 两位小数）逐条保留在工具里，**没有搬走**；
  3. 现场复核：捕获行与工具行对**同一对 PNG**给出的数字逐值相同
     （`changed_pixels 106800 / total_pixels 5339554`，§6-①）。
- **共享的第二个调用方**：`mcp_capture.cpp::_complete()` 用**同一函数、同一默认阈值 10**，
  因此「`changed`」在日志里与在工具响应里含义相同（GDR-25 的意图）。

---

## 9. 不设上限的可见性证据

- **绝不删除**：代码里没有任何 `DirAccess::remove*`；实测「先触发的文件仍在」（doctest + 现场各一条）。
- **每行 `total_bytes`（累计）**：见 §2.2 与 §6-⑧。
- **启动日志打印目录与模式**：见 §1 原文两行。
- **超 1 GB 只 WARN 一次**：`warned_over_threshold` 一次性布尔；WARN 文案实测原文见 §6-⑧。
  阈值可用 `set_warn_total_bytes_for_tests()` 在生产路径上下调（仅测试接缝）。

---

## 10. 回归（逐条归因）

| 脚本 | 结果 | 归因 |
|---|---|---|
| `scripts\mcp043_gates.ps1` | **28/28 STEP EXIT 0**（含 gate1a–1d、gate3、gate4、gate5×2、gate6a/b/c、gate2a–2i、regress_mcp032/033/034/035/036/040_probes/040_racing） | 全绿 |
| `scripts\mcp042_gates.ps1` | **19/19 STEP EXIT 0** | 全绿 |
| `scripts\mcp041_gates.ps1` | **17/17 STEP EXIT 0** | 全绿 |
| `scripts\mcp038_zero_change.ps1` | **7/7 checks passed**，probes=22 stable=22 **changed=0** unstable=0 | §24 的「关-关-开」模板仍成立 |
| `scripts\mcp038_trace_evidence.ps1` | **12/12 checks passed**，trace lines=10 | 追踪行为未变（本任务动了 `mcp_trace.cpp`，这是关键回归） |
| `scripts\check_contract_subset.ps1` | 3/3 PASS | 契约零变化 |
| `scripts\accept_m1.ps1` ×2 | 22/22 ×2，PASS 清单逐行相同 | 批收口 |

**归因说明**：`mcp041/042/043` 三条 battery 里各自的 `gate3_module_doctest` / `gate4_full_doctest`
也在**最终二进制**上跑过（EXIT 0）。本任务唯一触及的历史文件是 `mcp_trace.cpp`
（加字段 + 加不占 `seq` 的事件行）与 `editor_testing_read.cpp`（调用共享实现），
前者由 `mcp038_trace_evidence` 12/12 直接覆盖，后者由它自己的 doctest 覆盖。

---

## 11. 门⑥ 明细

见 §5.1（三段式 + 新增/移动收窄点逐条）。**扫描数 73 与任务前同数**是关键旁证：
迁移两个点、新文件零命中，因此**没有「偷偷新增一个未标注的收窄点」**。

---

## 12. 偏差 / 边界 / 风险（**逐条如实**）

- **D1（边界）延迟通道的调用不捕获**：`tools/call` 里若该工具是 `pending_handler` 家族，
  调用行写的是 `capture.status:"unavailable"` + `reason:"the call is answered across frames (deferred), which the capture does not cover"`，
  并**照样追加一条 `unavailable` 捕获行**（不静默）。原因：延迟调用的调用行在**完成时**才写，
  那时已无法回头决定「这张图该不该丢（`on_error` 语义）」。§25 未规定此情形 → §16 请求落笔。
- **D2（边界）headless 下捕获目录仍被创建（空）**：启动时按「目录不存在则创建」建立，
  但**一个文件都不写**。已把验收检查写成「目录下文件数 = 0」而不是「目录不存在」。
- **D3（边界）捕获依赖追踪文件**：`--mcp-capture=...` 但**没有** `--mcp-trace` 时，
  捕获**不启用**并 `WARN` 一行（`capture was requested but no call trace is open; capture stays off (add --mcp-trace=<path>)`）。
  理由：捕获行是追踪文件里的一行。§25 未规定 → §16 请求落笔。
- **D4（偏差，**需决策者裁决**）「零延迟」的实际代价**：服务端响应路径只 +7 ms（符合设计），
  但应答之后的编码 + 533 万像素比对让主线程忙约 400 ms，**背靠背**请求的往返从 18.5 ms 涨到 453.6 ms
  （间隔取样回到 30.7 ms）。验收②字面「未见系统性增加」**在进程响应能力这一层不成立**。
  证据、归因与两条改善建议见 §6-②。
- **D5（偏差）红阶段是受控回退**：见 §4 末尾的诚实声明。
- **D6（未跑到）真 1 GB 阈值**：现场没写满 1 GB，正确性由 doctest（同一条生产路径、阈值下调）断言。
- **D7（既有）门⑥ 的 `pinned_line` 漂移提示 10 条**：其中 6 条是 TASK-025/034 遗留的**既有**漂移
  （`editor_input_simulation.cpp` 等，非本任务引起），本任务只更新了自己引起的 `G24-THE-GATE`（1161→1552）。
- **D8（既有）`mcp_capture.cpp` 不在门⑥ 扫描面内**：扫描器只扫 `tools/**`（声明边界）。
  新文件**实测不含任何声明拼写**（`scanned` 数不变），但这是「拼写集合」层面的保证，不是全称保证。
- **风险 R-1**：`every_call` 在**大视口**下每次捕获写约 50 KB × 2 PNG，长期运行会持续吃盘
  （用户明确选择不设上限 + 只 WARN 一次）。已有 `total_bytes` 可见性，但**没有**速率限制。
- **风险 R-2**：`frames_waited` 实测在 1–3 之间（隐藏窗口下主循环可能空转多帧），
  即「≥1 帧」成立但**不保证恰好 1 帧**；若未来需要「恰好 N 帧」需另加机制。
- **风险 R-3**：像素比对的 O(W×H) 逐像素实现是大视口下的主要开销（§D4），
  共享实现被工具与捕获同时使用，**优化会同时影响两者**（须同时复核两处证据）。

---

## 13. 提交锚点与内容一致性（D86）

- 代码锚点：**`39fc7179e7`**（第二条提交只加测试与脚本，第三条只加本报告）。
- 全部 13 个文件的 sha256 已在 §0 表中给出；**提交不改文件字节**，因此「实测时的树」== 「提交后的树」。
- 测试期的 `git stash` 往返**已核验**：恢复后与备份目录**逐文件 sha256 相同**
  （804 文件，missing/extra/diff 均为空）。
- `--version` 在**每一次**门/battery 运行的那一刻等于当时的 `git HEAD`（`2f520cf90` == `2f520cf903`）。
  §17 给出提交后的重建与整条 battery 复跑，作为**最终**锚点。

---

## 14. 对决策者的请求（§25 落笔）

1. **补 §25.2**：捕获依赖追踪文件 —— 未指定 `--mcp-trace` 时捕获不启用并 WARN（D3）。
2. **补 §25.5**：延迟通道调用的 `capture.status` 取值用 `unavailable` + `reason`（D1），
   而不是「静默跳过」。
3. **补 §25.3**：`editor`/`2d`/`3d` 的 size 实测（2978×1793 / 2978×1790 / 3840×2054）与
   「游戏侧 viewport 名 = `game`」。
4. **修订 §25.4 的「廉价」措辞**：framebuffer 拷贝确实廉价（+7 ms），**应答之后的编码与比对不廉价**
   （约 400 ms 主线程占用，背靠背往返 18.5 → 453.6 ms）。建议在 §25 明确「零延迟」指的是
   **响应路径**，并把「背靠背请求的排队」列为已知代价（或排入后续任务做 raw-buffer 比对优化）。
5. **补 §25.7**：headless 下捕获目录会被创建但保持为空（D2）。

---

## 15. 遗留风险与下一步

| 项 | 说明 |
|---|---|
| **R-1** | 大视口 + `every_call` 下的磁盘增长（无速率限制，只有 `total_bytes` 与一次性 WARN） |
| **R-2** | `frames_waited` 可为 1–3（≥1 成立） |
| **R-3** | 像素比对是主要 CPU 开销；建议改用 `Image::get_data()` 原始缓冲（语义不变，工具与捕获同时受益，须同时复核两处证据） |
| **R-4** | 延迟通道的调用不捕获（D1）——若决策者认为必须覆盖，需把捕获上下文挂进 `MCPDeferred::Queue` 并允许在完成时回填调用行 |

---

## 16. 勘误（append-only）

- **E-1**：本报告初稿曾在 §4 把红阶段的失败数写成「5 个用例」，现按真实输出更正为
  `5 failed / 3 passed`，并补上「红阶段 3 个用例照绿」的解释（那是断言与目标对齐的旁证）。
- **E-2**：`mcp044_capture_evidence.ps1` 的 `switch_off_writes_no_png` 曾因跨相残留
  （`mcp044_shots_diff_image` 未进清理清单）出现过一次假 FAIL；已修清单，四相在最终脚本修订上全绿。
- **E-3（提交后重建）**：见 §17。

---

## 17. 提交后的最终锚点复跑

三条提交落下之后，从**已提交的树**用 `scripts\build_local.cmd -Force`（从 cmd 启动，`tests=yes`）重建：

```
bin\godot.windows.editor.x86_64.console.exe --version   ->  4.8.dev.custom_build.0d405fa2a
git rev-parse --short HEAD                              ->  0d405fa2a9      (== --version, 前缀一致)
```

`scripts\mcp043_gates.ps1` 在**这一二进制**上整条 battery 复跑：

```
== summary ==
TASK-043 gate battery
binary --version: 4.8.dev.custom_build.0d405fa2a
git HEAD: 0d405fa2a
<28 个 STEP，全部 EXIT 0>
STEP gate3_module_doctest EXIT 0
STEP gate4_full_doctest EXIT 0
STEP gate1a..1d_contract_group_* EXIT 0
STEP gate6a_narrowing EXIT 0 / gate6b_narrowing_coverage EXIT 0 / gate6c_coverage_probes EXIT 0
STEP gate5_accept_run1 EXIT 0 / gate5_accept_run2 EXIT 0
STEP gate2a..2i_* EXIT 0
STEP regress_mcp032/033/034/035/036 EXIT 0
STEP regress_mcp040_probes EXIT 0 / regress_mcp040_racing EXIT 0
DONE
```

- **`FINAL-ANCHOR`：`0d405fa2a9`**（本报告提交）—— `--version` == `git HEAD` **在提交之后仍然成立**，
  且 28/28 STEP（含门①/③/④/⑤/⑥ 与全部历史回归）全绿。
- 代码锚点仍是 **`39fc7179e7`**（§0）；两者之间只有测试/脚本/文档三个提交，**不含任何实现字节变化**。
- 本节为 **append-only 勘误**，只追加、不改写上文任何数字。
