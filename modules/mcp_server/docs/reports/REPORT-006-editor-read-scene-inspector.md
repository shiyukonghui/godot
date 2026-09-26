# REPORT-006 — 移植组 `editor_read_scene_inspector`（7 个编辑器专有只读工具）

- **status**：`pass` — 五道门全绿（真实退出码 0），§2 的 editor scope 端到端守卫证据齐备，工作树除开工前既有的
  4 个未跟踪物（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）外干净。
- **本组是第一个 `scope=EDITOR` 的组**，因此额外交付了一直缺失的「游戏进程不暴露编辑器工具」端到端证据（§5）。
- 契约 / 映射 / 生成器**未改动**（`git diff 100fee0050 -- docs/tools_list.renamed.json docs/tool-rename-map.json
  scripts/gen_renamed_contract.py docs/scripts` 为**空**）。

## 1. commits

| sha | 说明 |
|---|---|
| `5501a6c9a4` | `mcp_server: TASK-006 - failing tests for the editor_read_scene_inspector group (TDD red)`（tests 两个文件，+5 用例 / 2 处既有断言） |
| `ea87e8e599` | `mcp_server: TASK-006 - port the editor_read_scene_inspector group (7 editor-only read tools)`（2 new + 5 M：实现、注册行、`tool-groups.json`、`project_read_files.cpp` 的 size 单位、测试收口） |
| `f74176a545` | `mcp_server: TASK-006 - make the contract and acceptance gates scope aware (editor vs game endpoint)`（2 个门脚本） |

被改动文件（`git diff --stat 100fee0050`）：

```
 modules/mcp_server/docs/tool-groups.json                     |   4 +-
 modules/mcp_server/scripts/accept_m1.ps1                     |  ...
 modules/mcp_server/scripts/check_contract_subset.ps1         |  ...
 modules/mcp_server/tests/test_mcp_server.cpp                 |  17 +
 modules/mcp_server/tests/test_mcp_server.h                   | 477 +++++++++-
 modules/mcp_server/tools/editor_read_scene_inspector.cpp     | 684 +++++++++  (new)
 modules/mcp_server/tools/editor_read_scene_inspector.h       |  54 ++        (new)
 modules/mcp_server/tools/project_read_files.cpp              |  12 +-
 modules/mcp_server/tools/registration.cpp                    |   2 +
```

## 2. 逐工具表

`new_name` | 迁移源 | 可观察契约（参数 / 返回形状 / 上限 / 大小写 / 错误）| C++ 落点 | 与迁移源的差异

| 工具 | 迁移源 | 可观察契约 | C++ 落点 | 差异 |
|---|---|---|---|---|
| `editor_get_errors` | `editor.rs:270` + `read_log_file` `editor.rs:147` | `max_lines` int 可选（默认 50）；读 `user://logs/godot.log`；文件不存在 → `{"errors":[],"count":0}`（**不是** 错误）；把全文按 `'\n'` 切（**保留** 末尾换行产生的空串，不是 `str::lines()`），**先取尾部 `max_lines` 窗口，再过滤**；过滤 = 行 `to_upper()` 后含 `"ERROR"`（参照的两个附加判断 `"SCRIPT ERROR"`/`"PARSE ERROR"` 被它蕴含）；返回 `{"errors":[...],"count":N}`；`max_lines` 类型错 → `-32602`；文件存在但打不开 → `-32603` | `_tool_get_errors` / `_log_tail_lines` | 一致（仅手册 §6 第 2 条：`optional_*` 类型错 → `-32602`） |
| `editor_get_output_log` | `editor.rs:290` | `max_lines` int 可选（默认 100）、`filter` str 可选（默认 `""`）；同一尾窗口；过滤是**大小写敏感**子串（`str::contains`）；返回 `{"lines":[...],"count":N,"source":"log_file"\|"no_log_file"}` | `_tool_get_output_log` | 一致 |
| `editor_get_open_scripts` | `script.rs:137` | 无参数；`ScriptEditor::get_open_scripts()` 的页签顺序；每项 `{"path":<Script 资源路径>,"type":<get_class()>}`；返回 `{"scripts":[...],"count":N}`；脚本编辑器不可用 → `-32603 "Internal error: Script editor not available"` | `_tool_get_open_scripts` | 一致；新增非编辑器 UI → `-32000`（见 §7） |
| `editor_get_scene_tree` | `scene.rs:109` | `max_depth` int 可选（默认 -1）；返回 `{"scene_path","tree"}`；`tree` = `{"name","type","path"[, "children"]}`；`children` 仅在 `max_depth == -1 \|\| depth < max_depth` 时出现（`0` = 仅根、`1` = 根+子）；**无节点数上限**（迁移源就没有，唯一的上界是 `max_depth`）；`path` 是 `Node::get_path()`（编辑器内绝对路径）；无编辑场景 → `-32000 "No scene is currently open"` | `_tool_get_scene_tree` / `_build_scene_tree` | 编辑场景根改用 `SceneTree::get_edited_scene_root()`（手册 §6 第 6 条，`EditorInterface` 版无 null 检查、doctest 进程实测 SIGSEGV）；其余一致 |
| `editor_get_selection` | `node.rs:625` | `top_only` bool 可选（默认 false）；返回 `{"nodes":[...],"count":N,"top_only":bool}`；每项 `{"name","path","type"}`，根的 `path` 是 `"."`，非当前场景内的选中节点被跳过；无编辑场景 → `-32000`；`top_only` 类型错 → `-32602` | `_tool_get_selection` | 一致（另加编辑器 UI 守卫） |
| `editor_get_viewport_3d_camera` | `editor.rs:630` → `get_editor_camera_via_script` `editor.rs:188` | 无参数；返回 `{"position":{x,y,z},"rotation_degrees":{x,y,z},"fov","near","far"}`；无 3D 视口/相机 → `-32603 "Internal error: 无法获取3D视口, 请确保已打开3D场景"`（沿用参照原文） | `_tool_get_viewport_3d_camera` | 用真实 API（`Node3DEditor` + `EditorInterface::get_editor_viewport_3d()`）取代参照的 `Expression` 执行 GDScript；**五个键与值语义相同** |
| `editor_analyze_signal_flow` | `analysis.rs:387` | `node_path` str 可选；未传或 `"."` → 全场景，否则对**精确路径**（`root->has_node`）的节点**及其子树**分析；每个"有连接"的节点产出 `{"name","path","type","signals_emitted":[{"signal","targets":[{"target_node","method"}]}],"signals_connected_to":[{"from_node","signal","method"}]}`；**只统计持久连接**；target 必须落在编辑场景内；路径不存在 → `-32001`（带 `data.suggestion`）；返回 `{"scene","nodes":[...],"total_nodes":N}` | `_tool_analyze_signal_flow` / `_collect_signal_flow` | **两处修复**（详见 §8 缺陷 1、2）：递归按节点指针（参照按 `get_node("<name>")` 查名，根节点与孙子节点永远解析不到）；持久位用 `CONNECT_PERSIST`（参照的 `flags & 1` 在 Godot 4 是 `CONNECT_DEFERRED`） |

## 3. 红 / 绿证据（TDD）

**红阶段**（commit `5501a6c9a4` 的树；`editor_read_scene_inspector.{h,cpp}` 尚不存在、
`registration.cpp` 尚未追加、`tool-groups.json` 的 `implemented` 仍为 `false`）：

```
TEST CASE:  [MCPServer] project_read_script returns the file text verbatim
TEST CASE:  [MCPServer] project_read_scene_file_content returns the raw tscn text
TEST CASE:  [MCPServer] the editor_read_scene_inspector group is editor-only
TEST CASE:  [MCPServer] editor_get_errors reports the ERROR lines of the log tail
TEST CASE:  [MCPServer] editor_get_output_log filters the tail case sensitively
TEST CASE:  [MCPServer] the editor UI inspectors refuse cleanly without an editor UI
TEST CASE:  [MCPServer] the edited-scene inspectors need an open scene and validate their arguments
[doctest] test cases:  78 |  71 passed |  7 failed | 1429 skipped
[doctest] assertions: 963 | 901 passed | 62 failed |
[doctest] Status: FAILURE!
```

红 = **5 个新用例全红** + **2 个既有用例**因 `size` 期望改为字节数而红（`CHECK( 40 == 48 )`、
`CHECK( 110 == 114 )`）。基线（TASK-005 交付态）**73 例 / 726 断言**。

**绿阶段**（最终树，commit `f74176a545`）：

```
[doctest] test cases:  78 |  78 passed | 0 failed | 1429 skipped
[doctest] assertions: 995 | 995 passed | 0 failed |
[doctest] Status: SUCCESS!
```

## 4. 五道门

### 4.1 门① 契约子集逐字 —— `check_contract_subset.ps1 -Group editor_read_scene_inspector` → **3/3 PASS（退出码 0）**

```
scope       : editor-only=7 game-only=0 both/shared=19
editor set  : 26 tool(s)
game set    : 19 tool(s)
[PASS] editor_9888_contract_subset
       editor port=9888 tools=26 order=project_get_info > ... > editor_analyze_signal_flow |
       editor_get_errors: name=True description=True inputSchema=True | editor_get_output_log: ...True |
       editor_get_open_scripts: ...True | editor_get_scene_tree: ...True | editor_get_selection: ...True |
       editor_get_viewport_3d_camera: ...True | editor_analyze_signal_flow: ...True
[PASS] game_9889_contract_subset
       game port=9889 tools=19 order=project_get_info > ... > project_read_scene_file_content |
       editor_get_errors: correctly absent on the game endpoint | ...（7 条同样 correctly absent）
[PASS] guard_user_port_9877
       pid_before=36392 pid_after=36392
3/3 checks passed
```

**门①本轮必须改脚本**：TASK-004 的并集语义是「一个并集」，在出现第一个 `scope=editor` 组后不再成立——
原脚本会要求游戏端点也提供那 7 个工具，必然 FAIL。改动仅限于
（a）从 `docs/tool-rename-map.json`（scope 的唯一事实源）导出每个已实现工具的 scope，
（b）编辑器端点比对全集、游戏端点比对「全集 − editor scope」，并把「editor-only 工具**必须缺席**」变成显式断言。
`-Tools` 显式集合路径同样适用。契约、映射、生成器未动。

### 4.2 门② 三类证据 —— 见 §6

### 4.3 门③ 模块 doctest（`--headless --test --test-case="[MCPServer]*"`）→ **SUCCESS**

```
[doctest] test cases:  78 |  78 passed | 0 failed | 1429 skipped
[doctest] assertions: 995 | 995 passed | 0 failed |
```

基线 73 例 / 726 断言 → **+5 例 / +269 断言**。

### 4.4 门④ 全引擎回归（`--headless --test`）→ **SUCCESS**

```
[doctest] test cases:   1504 |   1504 passed | 0 failed | 3 skipped
[doctest] assertions: 425276 | 425276 passed | 0 failed |
```

基线 1499 例 / 425007 断言 → **+5 例 / +269 断言，0 failed**。

### 4.5 门⑤ `accept_m1.ps1` 连跑两次 → **A_EXIT=0 / B_EXIT=0**

两次均 **22/22 cases passed**，`PASS` 清单 `fc` 比对 **no differences encountered**：

```
implemented tools      : 26 / contract 171
process split          : editor endpoint 26 tool(s), game endpoint 19 tool(s), editor-only 7
case20: pid_first=49904 pid_second=36296 tools=26 bytes=7173/7173 byte_identical=True
        sha256_first =c76e0a52191fe857ad903fe72a4fc9a20595756c78cd08bebeb8013f9c105912
        sha256_second=c76e0a52191fe857ad903fe72a4fc9a20595756c78cd08bebeb8013f9c105912
case12: editor_scope_leaked=  editor_tool_call={"error":{"code":-32601,"message":"Method not found: editor_get_errors"},...}
```

`accept_m1.ps1` 本轮也随 scope 一起收口：`$ToolNames` 是**编辑器端点**的 26 条，
`$GameToolNames` 由映射导出为 19 条，`case12` 用后者做逐字比对，并新增
「无 editor scope 泄漏」+「游戏端点调用编辑器工具必须 `-32601`」两条断言。

## 5. editor scope 端到端守卫证据（TASK-006 §2）

三段证据，全部为**独立进程的真实请求/响应**。

**(1) 编辑器端点（9888）：7 个工具全部出现，且与契约逐字相等** —— 见 §4.1 的 `editor_9888_contract_subset`
（`tools=26`，7 条 `name/description/inputSchema = True/True/True`）。

**(2) 游戏端点（9889）：7 个工具一个都不出现** —— 见 §4.1 的 `game_9889_contract_subset`
（`tools=19`，7 条 `correctly absent`）。用 `curl.exe -s -o` 落盘的两次 `tools/list` 对比：

```
editor tools = 26
project_get_info,...,project_read_scene_file_content,
editor_get_errors,editor_get_output_log,editor_get_open_scripts,editor_get_scene_tree,
editor_get_selection,editor_get_viewport_3d_camera,editor_analyze_signal_flow
game   tools = 19  （上面 19 条 project_*，editor_ 前缀 0 条）
```

| 文件 | 字节 | sha256 |
|---|---|---|
| `resp-9888/01_tools_list_editor.resp` | 7172 | `3dd7a6d82606bb7330ee5deea7194a0d00559f8422545d0139f3e77e4318dadc` |
| `resp-9889/02_tools_list_game.resp` | 5392 | `c5af0d2b3e69790c0b0fe5fdf4ef2f3564e05c75078b8f7fa4c2ce937e981ddb` |
| `resp-9889/80_game_call_editor_tool.resp` | 97 | `7e8811559d44ea3cc9fdbeb7d385f2333804ea8dd437c8f7d89b7edae37a5c33` |

**(3) 游戏进程试图调用编辑器工具** → 明确拒绝，**未执行**：

```json
{"error":{"code":-32601,"message":"Method not found: editor_get_errors"},"id":80,"jsonrpc":"2.0"}
```

**(4) 编译期守卫 `MCP_EDITOR_TOOLS_ENABLED` 真的起作用**：doctest
`[MCPServer] the editor guard is an alias of the engine tools macro`（既有）断言
`MCP_EDITOR_TOOLS_ENABLED == 1`；本组文件里 5 个编辑器头（`editor/editor_data.h`、`editor/editor_interface.h`、
`editor/editor_node.h`、`editor/scene/3d/node_3d_editor_plugin.h`、`editor/script/script_editor_plugin.h`）
与**全部**编辑器 API 调用点都在 `#ifdef MCP_EDITOR_TOOLS_ENABLED` 区间内：

```
54:#ifdef MCP_EDITOR_TOOLS_ENABLED   60:#endif         (编辑器头)
81:#ifdef MCP_EDITOR_TOOLS_ENABLED   90:#endif         (_require_editor_ui 里的 EditorNode 探针)
236:#ifdef ... 257:#endif   (_tool_get_open_scripts: ScriptEditor)
333:#ifdef ... 375:#endif   (_tool_get_selection: EditorNode/EditorSelection)
393:#ifdef ... 434:#endif   (_tool_get_viewport_3d_camera: Node3DEditor/EditorInterface)
```

**(5) 运行期守卫 `is_editor_process()` + 单例守卫真的起作用**：doctest
`[MCPServer] the editor UI inspectors refuse cleanly without an editor UI` 分两段断言：

- `is_editor_hint()` 关（游戏进程视角）→ 3 个 UI 工具全部 `-32000`
  `Not implemented: editor inspectors outside a running editor` + `data.suggestion`；
- `is_editor_hint()` 开（但 doctest 进程**有 `EditorInterface`、没有 `EditorNode`**）→ 同样是 `-32000`
  `Not implemented: the editor UI (no EditorNode is running in this process)`。

第二段是**崩溃检测**：`EditorInterface::get_selection()` / `get_script_editor()` /
`get_editor_viewport_3d()` 都会无检查地解引用 `EditorNode::get_singleton()`
（`editor_interface.cpp:105-107`、`:431-441`）；如果守卫只看 `is_editor_process()`，这一循环就是空指针解引用、
测试二进制整体崩溃 —— 用例能跑到断言这一步本身就是该守卫有效的证据。

## 6. 门② 三类证据（真实请求/响应）

采集方式：`curl.exe -s -o <file> -X POST -H "Content-Type: application/json" --data-binary @<body>
http://127.0.0.1:9888/mcp`（**全部落盘，无 `Out-File`/管道**）。证据工程
`%TEMP%\mcp-t006-evidence\proj`（`res://scenes/main.tscn`：`Main(Node2D)+Child+GrandChild+Emitter`、
一条普通持久连接与一条 `flags=1` 的 deferred 持久连接；`res://scripts/alpha.gd`、`res://scripts/cjk.gd`），
编辑器以 `--headless -e --path <proj> res://scenes/main.tscn --mcp-port=9888` 启动，游戏侧
`--headless --path <game> --mcp-port=9889`。

**成功类（编辑器 9888）**

| # | 请求 | 响应（节选） |
|---|---|---|
| 10 | `editor_get_scene_tree {}` | `{"scene_path":"res://scenes/main.tscn","tree":{"children":[{"children":[GrandChild,Emitter],"name":"Child",...}],"name":"Main",...}}` |
| 11 | `editor_get_scene_tree {"max_depth":1}` | 根 + `Child`，`Child` **无** `children` 键 |
| 12 | `editor_get_scene_tree {"max_depth":0}` | 仅根，无 `children` 键 |
| 20 | `editor_get_selection {}` | `{"count":0,"nodes":[],"top_only":false}` |
| 21 | `editor_get_selection {"top_only":true}` | `{"count":0,"nodes":[],"top_only":true}` |
| 30 | `editor_analyze_signal_flow {}` | `{"nodes":[{"name":"Emitter","path":"Child/Emitter","signals_connected_to":[{"from_node":"Child/Emitter","method":"_on_emitter_ready","signal":"ready"},{"from_node":"Child/Emitter","method":"_on_emitter_renamed","signal":"renamed"}],"signals_emitted":[{"signal":"ready","targets":[{"method":"_on_emitter_ready","target_node":"."}]},{"signal":"renamed","targets":[{"method":"_on_emitter_renamed","target_node":"."}]}],"type":"Node"}],"scene":"res://scenes/main.tscn","total_nodes":1}` |
| 31 | `editor_analyze_signal_flow {"node_path":"Child"}` | 同上（`Child` 子树 → 命中 `Child/Emitter`） |
| 40 | `editor_get_open_scripts {}` | `{"count":1,"scripts":[{"path":"res://scripts/alpha.gd","type":"GDScript"}]}` |
| 50 | `editor_get_viewport_3d_camera {}` | `{"far":4000.01000976562,"fov":70.0100021362305,"near":0.0500000007450581,"position":{...},"rotation_degrees":{...}}` |
| 60 | `editor_get_errors {}` | `{"count":4,"errors":["ERROR: a first failure","SCRIPT ERROR: ...","PARSE ERROR: ...","only lowercase error here"]}` |
| 61 | `editor_get_errors {"max_lines":1}` | `{"count":0,"errors":[]}`（尾窗口**先于**过滤：最后一行是换行产生的空串） |
| 70 | `editor_get_output_log {}` | `{"count":8,"lines":["Godot Engine v4.7.1.stable",...,"中文日志行 汉字",""],"source":"log_file"}` |
| 71 | `editor_get_output_log {"filter":"ERROR"}` | `{"count":3,...}`（**不含** 小写那条 → 大小写敏感） |
| 72 | `editor_get_output_log {"max_lines":2}` | `{"count":2,"lines":["中文日志行 汉字",""],"source":"log_file"}` |

**底层失败类**

| # | 请求 | 响应 |
|---|---|---|
| 90 | 无编辑场景时 `editor_get_scene_tree {}` | `-32000 "No scene is currently open"` + `suggestion` |
| 91 | 无编辑场景时 `editor_analyze_signal_flow {}` | 同上 |
| 92 | 无编辑场景时 `editor_get_selection {}` | 同上 |
| 32 | `editor_analyze_signal_flow {"node_path":"Nope"}` | `-32001 "Node 'Nope' not found"` + `suggestion` |
| 33 | `editor_analyze_signal_flow {"node_path":"hil"}` | `-32001 "Node 'hil' not found"`（**精确匹配**，不做子串搜索） |
| 80 | 游戏端点 `editor_get_errors` | `-32601 "Method not found: editor_get_errors"` |

**缺参 / 类型错类（全部 `-32602`）**

```
13 editor_get_scene_tree {"max_depth":"deep"}      -> -32602 Parameter 'max_depth' must be an integer, got String
22 editor_get_selection   {"top_only":"yes"}       -> -32602 Parameter 'top_only' must be a boolean, got String
34 editor_analyze_signal_flow {"node_path":12}     -> -32602 Parameter 'node_path' must be a string, got float
62 editor_get_errors      {"max_lines":"many"}     -> -32602 Parameter 'max_lines' must be an integer, got String
73 editor_get_output_log  {"filter":3}             -> -32602 Parameter 'filter' must be a string, got float
```

**不可构造类（显式声明）**

1. `editor_get_errors` / `editor_get_output_log` 的「文件存在但打不开」：需要制造一个 `user://logs/godot.log`
   存在却不可读的环境（Windows 上要改 ACL 或持有独占锁），本轮未构造；代码路径为 `-32603`（见 §2 表）。
2. `editor_get_viewport_3d_camera` 的「无 3D 视口 / 无相机」：headless 编辑器**仍然**有 3D 视口与默认相机
   （见 #50），无法在不改引擎的前提下构造；代码路径为 `-32603 "无法获取3D视口..."`。
3. `editor_get_open_scripts` / `editor_get_viewport_3d_camera` 的缺参类：契约是 `{"properties":{},"required":[]}`，
   **既无必填也无可选参数**，缺参在语义上不存在（这两个工具因此也没有 `-32602` 路径）。
4. `editor_get_selection` 的非空选中：headless 编辑器不会自动选中任何节点，`count:0` 是真实响应；
   串行化规则（根为 `"."`、跳过场景外节点）由代码与 §4.1 的逐字契约门覆盖，
   **非空选中的真实响应本轮未取得**（见 §8 deviation 6）。

**§3.1 的字节数证据（同一工程，编辑器 9888）**

```
磁盘: scripts/cjk.gd    chars=76  bytes=132
磁盘: scenes/main.tscn  chars=507 bytes=517
100 project_read_script            -> "size":132   (= UTF-8 字节数，不是 76)
101 project_read_scene_file_content-> "size":517   (= UTF-8 字节数，不是 507)
```

## 7. TASK-006 §3 的两个小项

### 7.1 长度单位统一（手册 §6 第 9 条）

`git grep «"size"»` 的结论：已实现组里**只有一处**返回 `size`
（`tools/project_read_files.cpp` 的 `_read_text_payload`，被 `project_read_script` 与
`project_read_scene_file_content` 共用）。它原本写 `content.length()` = **字符数**，已改为
`content.utf8().length()` = **UTF-8 字节数**；契约里这两个工具的 `description`/`inputSchema`
**没有任何**关于字符数的表述，故按「以字节数为准」处理。doctest 与 §6 的线级证据同步更新。
本组 7 个工具都不返回 `size`，无同类问题。

### 7.2 日志文件在游戏进程下的可用性

`editor_get_errors` / `editor_get_output_log` 只做两件事：`FileAccess::exists("user://logs/godot.log")` 与
`FileAccess::open(..., READ)`；`user://` 由 `DirAccess::fix_path` 解析到用户数据目录，**不依赖编辑场景、
不依赖 EditorInterface**。在游戏进程里这两个工具**根本没有被注册**（门① 的 `game_9889` 证据），因此
既不会出现在 `tools/list`，也不可能被 `tools/call` 执行；同时本组的注册函数在游戏进程里只是被
`ToolBuilder::register_into()` 逐个跳过，**引擎启动无异常**（游戏进程正常监听 9889 并服务 19 条工具，
见 §5；门⑤ 的 `case12/case13` 亦然）。

顺带记录一个**实测到的引擎怪癖**（不是本组的缺陷，但会影响任何写 `user://` 的测试/工具）：
`DirAccess::make_dir_recursive_absolute("user://logs")` **不会创建用户数据目录本身** ——
`make_dir_recursive` 把 `user://` 当 base，只逐级创建 base 以下的段，上一层目录不存在时
`make_dir` 直接失败。开发这套 doctest 时它在「只跑 `[MCPServer]*`」时通过、在「跑全引擎」时失败
（`tests/core/io/test_logger.cpp` 把 `application/config/name` 设成 `godot_tests`，其 `cleanup_logs()`
又会把整个 `app_userdata/godot_tests` 删掉）。测试侧已按引擎自带的写法改用**绝对路径**创建
（`OS::get_user_data_dir().path_join("logs")`，与 `test_logger.cpp:47` 一致）；**工具实现不受影响**
（它们只用 `FileAccess`，不需要建目录）。

## 8. 与迁移源的差异、以及发现的契约缺陷

1. **【契约文本缺陷，报给决策者】`editor_analyze_signal_flow` 的 `description` 里「（flags & 1）」是错的。**
   Godot 4 的 `Object::ConnectFlags` 是 `CONNECT_DEFERRED = 1, CONNECT_PERSIST = 2, CONNECT_ONE_SHOT = 4`
   （`core/object/object.h:356-360`），而 `.tscn` 里的一条普通 `[connection]` 在实例化时被
   `cfrom->connect(..., CONNECT_PERSIST | c.flags | ...)` 恢复（`scene/resources/packed_scene.cpp:760`），
   即运行时 `flags = 2`：**`flags & 1 == 0`**。也就是说照抄参照的 `flags & 1` 会让这个工具对**普通场景恒返回
   `nodes: []`**，与描述承诺的"只统计持久连接"完全相反。本组按**意图**实现为
   `flags & CONNECT_PERSIST`，并保留契约 `description` 逐字不动。**建议决策者下批修订该括号说明**
   （改成 `flags & CONNECT_PERSIST (2)`），本组**不自行改契约**。
   线级证据：#30 的响应同时报出 `ready`（`flags=2`，`flags & 1` 会漏掉）与 `flags=1` 的 `renamed`；
   若按 `flags & 1` 实现，第一条会消失。
2. **`editor_analyze_signal_flow` 的递归**：参照用 `EditorInterface.get_edited_scene_root().get_node("<name>")`
   按**节点名**查节点（`analysis.rs:102-131`），于是场景根自己（`get_node("Main")` 找不到名为 `Main` 的子节点）
   与任何**孙子节点**（`get_node("GrandChild")` 不是直接子节点）永远解析不到，被静默丢弃。C++ 版直接递归真实节点指针；
   #30 命中 `Child/Emitter`（深度 2）正是这一修复的线级证据。
3. **编辑场景根取法**：`SceneTree::get_edited_scene_root()`（编辑器持续同步的镜像）取代
   `EditorInterface::get_edited_scene_root()`（手册 §6 第 6 条，后者在 doctest 进程 SIGSEGV）。
4. **`editor_analyze_signal_flow` 的 `-32001` 文案**：参照是 `节点 'x' not found` 且无 `suggestion`；
   本组用 `Node 'x' not found` + `data.suggestion`（手册 §6 第 1 条已接受「`path` 不存在 → `-32001` 带 suggestion」，
   本案是节点版）。
5. **`editor_get_viewport_3d_camera` 的实现路径**：参照经 `Expression` 执行 GDScript 取相机；C++ 版直接调
   `Node3DEditor` / `EditorInterface::get_editor_viewport_3d()` / `Viewport::get_camera_3d()`，**键与语义相同**。
6. **`editor_get_open_scripts` 的 `path`**：参照读 `s.get("resource_path")`；C++ 版读 `Script::get_path()`
   （同一属性），#40 实测 `res://scripts/alpha.gd` + `GDScript`。
7. 手册 §6 第 2 条的通用偏差（`optional_*` 存在但类型错 → `-32602`）在本组 5 处生效（§6 的类型错表）。

## 9. deviations

1. **改了门脚本（2 个）**：`check_contract_subset.ps1` 与 `accept_m1.ps1`。不是「为了过关」，而是
   TASK-004 的并集语义在出现第一个 `scope=editor` 组后**必然**误报（游戏端点不可能提供 editor-only 工具）。
   改动只增加"按 scope 分端点求期望集合"与"editor-only 工具必须缺席"的断言，**不放松任何原有强度**，
   且契约/映射/生成器未动（§4.1）。
2. **改了 `docs/tool-groups.json`**：把 `editor_read_scene_inspector` 的 `implemented` 置 `true`
   （前三个组同样如此；门①的并集断言依赖它），并更新该组 `notes` 说明 scope 证据。未改其它组、未改任何工具名单。
3. **红阶段的 doctest 退出码未被 shell 正确捕获**：红日志里那行 `EXIT=%0%` 是 `%ERRORLEVEL%` 展开时机错误留下的
   **字面量**，不是真实退出码（见附录 A 的采集脚本缺陷）。红阶段的真实证据是 doctest 自身的
   `Status: FAILURE!` 与 62 条失败断言；绿阶段与四道门的退出码均为 0（已用不经过管道的写法取得）。
   **不重跑红树**以免为了一个数字回退实现再重建（代价 > 收益）。
4. **新增 `_schema_from_json` + `_fold_integral_numbers`**：本组的 `inputSchema` 不是手写 `Dictionary`，
   而是把契约里的 `inputSchema` **原样**放进 C++ 原始字符串字面量、注册时解析。原因是"逐字相等"的对象
   包含 `description`；手抄 7 段中文描述是漂移风险。代价是 Godot 的 JSON 只有一种数字类型，
   `"default": 50` 解析后是 `50.0`、`JSON::stringify` 会写成 `50.0` —— 门① 第一轮**真实地**因此 FAIL
   （`inputSchema=False` ×3），已在解析后把整数值折回 `INT`（§附录 B 的第一轮日志）。这是一次
   "门真的抓到了东西"的记录，保留在报告里而非隐去。
5. **`editor_get_scene_tree` 的 `path` 字段**沿用了参照的 `Node::get_path()`（编辑器内绝对路径，
   形如 `/root/@EditorNode@<id>/.../@SubViewport@<id>/Main/Child`）。它较长且含编辑器内部节点名，
   但**这是参照的可观察行为**，属手册 §6 第 8 条的"保留怪癖"。已在 §6 #10 如实记录。
6. **非空 `editor_get_selection` 未取得线级证据**：headless 编辑器不会自动选中节点，
   `editor_get_selection` 的成功类证据只有 `count:0`。串行化规则（`"."`/跳过场景外节点/`top_only` 透传）
   没有运行时正例；如验收方要求，可在编辑器进程内先由写入组 `editor_set_node_selection`（B1 后续批）
   造出选中再复采。
7. **`editor_get_errors` / `editor_get_output_log` 的"文件存在但打不开"未构造**（§6 不可构造类 1）。
8. 本组未修改 `docs/DESIGN-DETAIL.md`、未新建任何 `REQUIREMENTS.md` / `DESIGN-*.md`（手册 §7.2）。
9. 工作树只留既有 4 个未跟踪物（手册 §5）；测试临时物在 `%TEMP%`，`user://logs/godot.log` 由 doctest 夹具
   **备份/还原**（不破坏开发机上的真实日志）。

## 10. 本组文件的 sha256（未动契约/映射/生成器，供验收核对）

```
tools/editor_read_scene_inspector.h     08f3724efb511156cb748d1d68ad0a54167aef8d664446b6354af75cb2077e5a
tools/editor_read_scene_inspector.cpp   caae672b813c5e16a20925cb52e373b2815b95bbd700c30c029de4aa7d491a3c
docs/tool-groups.json                   7352e02e7fa85f69fb072dda5c64285de6832ef630e443721da6f69f6e1925ea
scripts/check_contract_subset.ps1       b2fd8cdbcb9724caa9c0161fde25d38cd176112c171e82c87d21e05be2f952ce
scripts/accept_m1.ps1                   f141de4998f42770bfc587d7405f160446120af36a2bf03682e993ec1ec6ece8
docs/tools_list.renamed.json            64723fb9fbe8247512171ee4ae8b6950486bad3722cb957091414b73ecf573f5  (未改)
docs/tool-rename-map.json               2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd  (未改)
scripts/gen_renamed_contract.py         e6201603ae0fedbdba7cffcf785db6803d610030a2c12f8de549346a6161506f  (未改)
```

## 11. blockers

无。端口纪律：全程只用 9888 / 9889，`9877` 的用户编辑器（PID 36392）在每次门脚本里都有
`pid_before == pid_after` 的正向守卫；所有测试进程均由自己启停（收尾核对：9888/9889 无 LISTENING，
`tasklist` 无残留 console.exe）。

## 12. next_step_recommendation

1. **决策者裁定 §8 缺陷 1**：`editor_analyze_signal_flow` 的契约 `description` 里「（flags & 1）」应否
   改写为「（flags & CONNECT_PERSIST）」。这是**契约文本**修订（改 `tool-rename-map.json` 的 `reason`
   会动映射 sha → 文档指纹 → 契约 `_meta.map_sha256`），必须由决策者发起、并同步重生成契约。
2. 把「按 scope 分端点求期望集合」的语义回写进 `DESIGN-DETAIL.md` §17.3 / 门①的规范描述
   （本组只能改门脚本，规范修订属决策者）。
3. `editor_get_selection` 的正例（非空选中）建议在 `editor_write_scene_editor` 组落地后用
   `editor_set_node_selection` + 本工具做一次联合线级复采。
4. B1 剩余组建议沿用本次的两个模式：**契约 schema 原样解析 + 整数值折回 INT**、
   **`user://` 写测试用绝对路径建目录**。

---

## 附录 A — 复现方法（验收方可独立重跑）

```powershell
# 0) 构建（pwsh/cmd，勿用 Git Bash；MSYSTEM 会让 SCons 去 bin/build_deps 找依赖并失败）
D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8

# 1) 门③ 模块 doctest / 门④ 全引擎（在仓库根运行；harness 自己要求 cwd=仓库根）
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
bin\godot.windows.editor.x86_64.console.exe --headless --test

# 2) 门①（自起 9888/9889、自建 scratch 工程、自带 9877 pid 守卫）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\check_contract_subset.ps1 -Group editor_read_scene_inspector

# 3) 门⑤ 收口脚本 ×2（很慢：每轮多次启停引擎进程）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1

# 4) 门② 证据工程（%TEMP%，刻意不入库）
#    %TEMP%\mcp-t006-evidence\proj：project.godot（name=mcp_t006_evidence）、
#      scenes/main.tscn（Main/Child/GrandChild/Emitter + 一条普通 [connection] + 一条 flags=1 的）、
#      scripts/alpha.gd、scripts/cjk.gd
#    本次还给 %APPDATA%\Godot\app_userdata\mcp_t006_evidence\logs\godot.log 放了固定内容，
#    以覆盖两个日志工具的成功路径；.godot/editor/editor_layout.cfg 预置 [ScriptEditor] open_scripts。
bin\...console.exe --headless --path "%TEMP%\mcp-t006-evidence\proj" --import
bin\...console.exe --headless -e --path "%TEMP%\mcp-t006-evidence\proj" res://scenes/main.tscn --mcp-port=9888
#    每个用例（禁止管道承载响应体）：
curl.exe -s -o resp.json -X POST -H "Content-Type: application/json" --data-binary "@bodies\30_signal_flow_all.json" http://127.0.0.1:9888/mcp
#    游戏侧：去掉 -e、用 --mcp-port=9889（工程里要有 run/main_scene）
```

## 附录 B — 门① 第一轮真实 FAIL（保留记录）

`_fold_integral_numbers` 之前，编辑器端点的 `inputSchema` 有 3 条不等：

```
[FAIL] editor_9888_contract_subset
       editor port=9888 tools=26 ... | editor_get_errors: name=True description=True inputSchema=False |
       editor_get_output_log: ... inputSchema=False | editor_get_open_scripts: ... inputSchema=True |
       editor_get_scene_tree: ... inputSchema=False | ...
诊断: editor_get_errors {"properties":{"max_lines":{"default":50.0,...}}}
      契约                {"properties":{"max_lines":{"default":50,...}}}
```

即 Godot 的 JSON 解析把整数变成浮点、`JSON::stringify` 又写成 `50.0`。修复后门① 3/3 PASS（§4.1）。

## 附录 C — 交付后再构建校验（证明门③④⑤测的就是提交的实现）

报告提交后重跑了一次 `scons platform=windows target=editor tests=yes module_mono_enabled=no -j8`：
**只有 `core\version_hash.gen.cpp` 被重新生成并重链**，`modules\mcp_server` 下 4 个源文件
（`editor_read_scene_inspector.cpp`、`registration.cpp`、`project_read_files.cpp`、`test_mcp_server.cpp`）
**一个都没有重新编译** —— 即门③/④/⑤ 所测二进制与提交的实现源码逐字节一致，
门结果不是"用旧二进制测新源码"得来的。`EXIT=0`。
