# REPORT-007 — 契约描述纠正 + 移植组 `project_write_resource_scene`（4 个写工具）

- **status**：`pass` — 五道门全绿（真实退出码 0），写操作在 **真实编辑器进程 + `%TEMP%` scratch 工程**上有完整
  文件系统前后状态证据（§6），「失败不破坏原文件」有反例证据（§7）。工作树除开工前既有的 4 个未跟踪物
  （`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）外干净。
- **本组是第一个 `mutating=true` 的写组**，因此额外交付：原子发布（临时文件 + 重命名 + 备份回滚）的实现与
  证据、scratch 工程副本的逐文件 sha256 清单、以及一个**只读/损坏**既有文件作为反例。
- **契约改了**（这是本任务的第一部分，决策者已裁决）：`docs/tools_list.renamed.json` 只有
  `editor_analyze_signal_flow` 一行变化，仍 **171 条**；`tool-rename-map.json` **未动**（sha 不变）。
- 冻结态：commit `7cb87e78cb`；引擎二进制 `bin/godot.windows.editor.x86_64.console.exe`
  sha256 `32436f6b51c45c297ba71d003ac8cc5f68413471e1cfa24ee905281443936880`（所有门都在它上面跑完）。

## 1. commits

| sha | 说明 |
|---|---|
| `4b8f193082` | `mcp_server: TASK-007 - failing tests for the project_write_resource_scene group (TDD red)`（`tests/test_mcp_server.h`：+11 用例 + 既有计数断言按新并集校正） |
| `63fb07c942` | `mcp_server: TASK-007 - port the project_write_resource_scene group (4 write tools, atomic publish)`（2 new + 5 M） |
| `bd1961a250` | `mcp_server: TASK-007 - write-group doctests assert the successful write (temp-file naming fixed)` |
| `7b0eb1c013` | `mcp_server: TASK-007 - contract description fix (analyze_signal_flow), scope semantics in DESIGN-DETAIL 17.3, deterministic scratch file` |
| `7cb87e78cb` | `mcp_server: TASK-007 - prove the create_resource overwrite with CACHE_MODE_IGNORE (stale loader cache)` |

`git diff --stat 902cdac636..7cb87e78cb`（开工前的 HEAD = `902cdac636`）：

```
 modules/mcp_server/docs/DESIGN-DETAIL.md               |  12 +
 modules/mcp_server/docs/tool-groups.json               |   2 +-
 modules/mcp_server/docs/tools_list.renamed.json        |  13 +-
 modules/mcp_server/scripts/accept_m1.ps1               |   4 +
 modules/mcp_server/scripts/gen_renamed_contract.py     |  67 +-
 modules/mcp_server/scripts/mcp007_write_evidence.ps1   | 330 +++++++++
 modules/mcp_server/tests/test_mcp_server.h             | 718 +++++++++++++++++++-
 modules/mcp_server/tool_registry.cpp                   |  11 +
 modules/mcp_server/tool_registry.h                     |   3 +
 modules/mcp_server/tools/editor_read_scene_inspector.cpp | 2 +-
 modules/mcp_server/tools/project_write_resource_scene.cpp | 738 +++++++++++++++++++++
 modules/mcp_server/tools/project_write_resource_scene.h   |  68 ++
 modules/mcp_server/tools/registration.cpp              |   2 +
 13 files changed, 1933 insertions(+), 37 deletions(-)
```

## 2. 逐工具表

| `new_name` | 迁移源 | 可观察契约（参数 / 返回形状 / 上限 / 大小写 / 错误）| C++ 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `project_create_resource` | `resource.rs:199` | `path` str 必填、`type` str 必填、`properties` object 可选、`overwrite` bool 可选（默认 false）；`path` 必须指向 `res://` 内的**文件**（根 `res://` → `-32602`），`..` → `-32602`；`type` 必须是**可实例化的 `Resource` 子类**（未知类/`Node` → `-32602`）；已存在且 `overwrite=false` → `-32000` + `data.suggestion`；`properties` 里资源没有的属性**静默跳过**；返回 `{"path","type"(实例的真实类),"properties_set":[...],"changed":{}}` | `_tool_create_resource` | **两处有意收紧**：(1) 迁移源的「失败」是 `-32603`，本 fork 沿用手册 §6 第 1 条把「找不到具体东西」归 `-32001`；这里不是 not_found 而是参数错，故未知类改 `-32602`；(2) `"res://"` 本身当文件名 → `-32602`（迁移源会去 `ResourceSaver` 里失败）。其余一致 |
| `project_create_scene_file` | `scene.rs:171` | `path` str 必填、`root_type` str 可选（默认 `Node2D`）、`root_name` str 可选（默认 = 文件名去扩展名，空则 `"Node"`）；`root_type` 必须是可实例化的 `Node` 子类（未知类/`Resource` → `-32602`）；**已存在 → `-32000` + suggestion（不可覆盖）**；返回 `{"path","root_type","root_name","created":true}` | `_tool_create_scene_file` | **一处有意收紧**：迁移源无存在性检查、会**静默覆盖**已有场景（契约也没有 `overwrite` 参数），本实现改为拒绝覆盖（`-32000`）；根名默认、`pack` 流程、返回键与迁移源一致。另：迁移源每次 `Instantiate` 后 `queue_free()`，本实现 `memdelete` 临时根节点 |
| `project_delete_scene_file` | `scene.rs:251` | `path` str 必填；不存在 → `-32001` + `data.suggestion`；删除文件与其 `<path>.import` sidecar（存在才删）；返回 `{"path"(归一后),"deleted":true}` | `_tool_delete_scene_file` | 一处**行为差异**：迁移源删除后调用 `EditorInterface::get_resource_filesystem()->scan()`；本实现**不触发**编辑器重扫（那是编辑器副作用，不是工具的契约），因此 `.import` sidecar 可能被编辑器自己的 rescan 重建（见 §6 实测）。删除本身与返回值一致 |
| `project_edit_resource` | `resource.rs:131` | `path` str 必填、`properties` object 必填；`path` 不存在或**不可加载** → `-32001` + suggestion；未知属性名**跳过**；属性值按属性自身类型转换（`serialize.rs:268`）；**无属性被改** → `{"path","changed":{},"message":"No properties were changed"}` 且**不写盘**；有改动 → `{"path","type","changed":{<name>:{"old","new"}}}` | `_tool_edit_resource` | 与迁移源一致（除 §6 的 `-32001` 归类） |

`properties` 的值转换（`_property_value_from_json` + `_coerce_to_property_type`）复刻迁移源的
`parse_value_for_property`（`serialize.rs:268`），并补上 Rust 版按属性类型解析的那一步：JSON 整数在
目标是 `int` 属性时折回 `INT`（否则 Godot 的单一数字类型会写成 `float`）、`#rrggbb` → `Color`、
`Vector2(...)`/`Vector3(...)` → 对应向量、其余 JSON 对象 → `Dictionary`（「保留结构」），最后经
`VariantUtilityFunctions::type_convert`（引擎自带的 `@GlobalScope.type_convert`）落到属性类型。
非有限数（`nan`/`inf`）显式拒绝为 `-32602`，不交给未定义的整数转换。

## 3. 红 / 绿证据（TDD）

**红阶段**（commit `4b8f193082`，`project_write_resource_scene.{h,cpp}` 尚不存在、`registration.cpp`
未追加、`tool-groups.json` 的 `implemented` 仍为 `false`；基线 = TASK-006 交付态
**78 例 / 995 断言**）：

```
[doctest] test cases:   89 |   78 passed | 11 failed | 1429 skipped
[doctest] assertions: 1177 | 1096 passed | 81 failed |
[doctest] Status: FAILURE!
EXIT=1
```

11 个新用例**全红**，例如：

```
.\modules/mcp_server/tests/test_mcp_server.h(3253): ERROR: CHECK( p_registry.has_tool(tools[i].name) ) is NOT correct!
  values: CHECK( false )
.\modules/mcp_server/tests/test_mcp_server.h(3293): ERROR: CHECK_FALSE( error.is_error() ) is NOT correct!
  values: CHECK_FALSE( true )
  values: CHECK( -32603 == 0 )      <- 工具不存在 → -32601/-32603 路径
```

**绿阶段**（最终树 `7cb87e78cb`）：

```
[doctest] test cases:   89 |   89 passed | 0 failed | 1429 skipped
[doctest] assertions: 1213 | 1213 passed | 0 failed |
[doctest] Status: SUCCESS!
EXIT=0
```

## 4. 五道门

### 4.1 门① 契约子集逐字 —— `check_contract_subset.ps1 -Group project_write_resource_scene` → **3/3 PASS（退出码 0）**

```
scope       : editor-only=7 game-only=0 both/shared=23
editor set  : 30 tool(s)
game set    : 23 tool(s)
[PASS] editor_9888_contract_subset
       editor port=9888 tools=30 ... | project_create_resource: name=True description=True inputSchema=True
       | project_create_scene_file: name=True description=True inputSchema=True
       | project_delete_scene_file: name=True description=True inputSchema=True
       | project_edit_resource: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset
       game port=9889 tools=23 ... | （同样 4 条 name=True description=True inputSchema=True）
[PASS] guard_user_port_9877
       pid_before=36392 pid_after=36392
3/3 checks passed
```

**逐端点 scope 语义**（TASK-007 §2 要求门①覆盖）：4 个写工具在 `tool-rename-map.json` 里都是
`scope=both`，因此**两个端点都必须服务**它们——上面两条 PASS 就是逐端点断言的结果。编辑器端点 30 条 /
游戏端点 23 条 = 同一差值 7（editor-only），**没有一条写工具缺席，也没有一条 editor-only 工具泄漏**。

### 4.2 门② 三类证据 —— 见 §6（真实请求 + 响应 + 文件系统前后状态）

### 4.3 门③ 模块 doctest（`--headless --test --test-case="[MCPServer]*"`）→ **SUCCESS**

```
[doctest] test cases:   89 |   89 passed | 0 failed | 1429 skipped
[doctest] assertions: 1213 | 1213 passed | 0 failed |
```

基线 78 例 / 995 断言 → **+11 例 / +218 断言**。

### 4.4 门④ 全引擎回归（`--headless --test`）→ **SUCCESS（退出码 0）**

```
[doctest] test cases:   1515 |   1515 passed | 0 failed | 3 skipped
[doctest] assertions: 425494 | 425494 passed | 0 failed |
```

基线 1504 例 / 425276 断言 → **+11 例 / +218 断言，0 failed**。

### 4.5 门⑤ `accept_m1.ps1` 连跑两次 → **A_EXIT=0 / B_EXIT=0**

两次均 **22/22 cases passed**，`PASS` 清单逐条比对 **完全一致**：

```
implemented tools      : 30 / contract 171
process split          : editor endpoint 30 tool(s), game endpoint 23 tool(s), editor-only 7
known_deviation        : per-batch gate, NOT a full-contract gate (30 of 171 ...)
case20_tools_list_cross_process_restart
  A: pid_first=52988 pid_second=52864 tools=30 bytes=8568/8568 byte_identical=True
     sha256_first=9a9b767d193c3c2d6d6fe84ec7c2ab03c19b7470ccb2d4f417cff585f84fec50
     sha256_second=9a9b767d193c3c2d6d6fe84ec7c2ab03c19b7470ccb2d4f417cff585f84fec50
  B: pid_first=52964 pid_second=46480 tools=30 bytes=8568/8568 byte_identical=True
     sha256_first=9a9b767d193c3c2d6d6fe84ec7c2ab03c19b7470ccb2d4f417cff585f84fec50
     sha256_second=9a9b767d193c3c2d6d6fe84ec7c2ab03c19b7470ccb2d4f417cff585f84fec50
22/22 cases passed   (A/B 的 PASS 清单 id 序列完全相同，逐条 True)
```

`accept_m1.ps1` 本轮只改了一处：把 4 个写工具按 `tool-groups.json` 的顺序加进 `$ToolNames`
（`accept_m1.ps1:100-107`），逐端点 scope 推导逻辑（TASK-006 §2 引入）**未动**。

## 5. 契约描述纠正的前后对照与 override 理由

### 5.1 前后对照（`docs/tools_list.renamed.json`）

| | 文本 |
|---|---|
| OLD | 分析当前场景的信号连接流 判别点：按节点嵌套返回 nodes[]（每节点含 signals_emitted/signals_connected_to），**只统计持久连接（flags & 1）**、node_path 精确匹配、无 signal_name 过滤；要扁平 connections[] 或子串匹配请用 editor_list_signal_connections。 |
| NEW | 分析当前场景的信号连接流 判别点：按节点嵌套返回 nodes[]（每节点含 signals_emitted/signals_connected_to），**只收集持久连接（CONNECT_PERSIST，值为 2；注意 Godot 4 中 flags & 1 是 CONNECT_DEFERRED，不是持久连接）**、node_path 精确匹配、无 signal_name 过滤；要扁平 connections[] 或子串匹配请用 editor_list_signal_connections。 |

`tool-rename-map.json` 的 `reason` 仍写着 `flags & 1 只留持久连接`（**未动，避免映射 sha 漂移**：
`map_sha256 = 2f552719…` 前后一致）。描述与实现（TASK-006 已交付，按意图用 `CONNECT_PERSIST`）现在一致。

### 5.2 生成器结果与断言

```
$ python -X utf8 scripts/gen_renamed_contract.py
gen_renamed_contract: input tools = 174
gen_renamed_contract: output tools = 171                       <- 仍 171 条
gen_renamed_contract: order_normative = false (order is not part of the contract)
gen_renamed_contract: description overrides = 7 (search_files:append, search_in_files:append,
    uid_to_project_path:append, project_path_to_uid:append, find_signal_connections:append,
    find_node_references:append, analyze_signal_flow:replace)
gen_renamed_contract: old contract sha256 = 8f8051c4c0f8941089f0b21a193cef7c51fa7c41d7e312b1463ea8593f313c54
gen_renamed_contract: rename map sha256 = 2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd
gen_renamed_contract: output sha256 = c4f913d65c3f3fd311d36ded44b473189cf886f098959fe7b6edf49b74901298
gen_renamed_contract: self-checks = OK (lint 171/171, unique 171/171, disposition enum OK)
EXIT=0
```

逐条断言（`%TEMP%` 侧保存旧契约后按键比对，见 §10 脚本 `mcp007_diff_contract.py`）：

```
before count = 171, after count = 171
name set identical = True
changed tool rows = 1 ['editor_analyze_signal_flow']
  description changed: True
  inputSchema changed: False          <- schema 一字未动
meta overrides before = 7, after = 7
order_normative = False
map_sha256 unchanged = True
generator_version = 1.4.0
```

### 5.3 `_meta.overrides` 里的理由（节选）

```json
{ "kind": "description", "old_name": "analyze_signal_flow", "mode": "replace",
  "reason": "R-1 消歧 + 事实纠正（TASK-007 §1）：原文按迁移源 analysis.rs:387 写成“只统计持久连接（flags & 1）”，但 Godot 4 里 CONNECT_DEFERRED = 1、CONNECT_PERSIST = 2（core/object/object.h:356-360），照字面实现会让普通 .tscn 场景恒返回 nodes: []。实现（TASK-006 已交付）按意图用了 CONNECT_PERSIST，契约描述是唯一还在说 flags & 1 的地方，故用 mode=replace 纠正。被替换的原文（逐字保留以便审计）：分析当前场景的信号连接流 判别点：…只统计持久连接（flags & 1）…" }
```

### 5.4 为什么是 `mode: replace` 而不是 append（这是对生成器的一处最小扩展，需决策者知悉）

生成器 v1.2 的 `DESCRIPTION_OVERRIDES` 是 **append-only**（`gen_renamed_contract.py:357` 的 `startswith`
自检）：只能在原文后追加一句。但本任务要求「**描述要改对**」，而原文的「`flags & 1` 只统计持久连接」是
**事实错误**——append 会让调用方同时读到「(flags & 1)」和「flags & 1 不是持久连接」两句互相矛盾的话，
工具的 description 反而更差。因此：

- 新增 `"mode": "replace"`（默认仍是 `"append"`，7 条既有 override 的 `kind`/`reason`/`value` 逐字未动——除
  `editor_analyze_signal_flow` 外 6 条 append 条目的记录与旧契约**逐键相等**，已按键比对；
  契约里也只有 `editor_analyze_signal_flow` 一条 description 发生变化）；
- replace 有硬性自检：`reason` **必须逐字包含被替换的原文**，否则 `FATAL`（原文因此仍逐字留在
  `_meta.overrides` 里，审计不丢）；未知 `mode` 值也 `FATAL`。
- `mode` 字段被写进 `_meta.overrides` 的每一条记录（append 条目也带上 `"mode":"append"`），
  `_meta` 因此比旧版多一个键——这是本任务的**有意变更**，已在此显式列出。

### 5.5 C++ 字面量与 `TOOL-NAMING.md`

- `tools/editor_read_scene_inspector.cpp:679` 的 `String::utf8(R"desc(...)desc")` 已同步为新契约文本，
  并用脚本逐字与 `tools_list.renamed.json` 比对：`literal equals contract description = True`
  （394 bytes）；门①的 `description=True` 是它在**线上**的独立复核。
- `docs/TOOL-NAMING.md` 用 `docs/scripts/gen_table.py` 重渲染：**字节完全相同**，因为该文档由
  `tool-rename-map.json` 渲染，而映射未动：
  `before bytes 98720 sha256 ce9bc325…` == `after bytes 98720 sha256 ce9bc325…`，`byte-identical: True`。
  脚本自检全过（174 行 / 9 单元格 / DETERMINISM PASS）。

## 6. 写操作的文件系统证据

### 6.1 scratch 工程（`%TEMP%` 的**副本**，不在仓库、不在用户工程）

```
scratch root : C:\Users\wyl\AppData\Local\Temp\mcp007-write-scratch
evidence dir : C:\Users\wyl\AppData\Local\Temp\mcp007-write-evidence
engine       : bin\godot.windows.editor.x86_64.console.exe --headless -e --path <scratch> --mcp-port=9888
driver       : modules\mcp_server\scripts\mcp007_write_evidence.ps1  (exit 0)
guard        : user editor on 9877 before pid=36392 after pid=36392 same=True
```

**操作前清单（`fs.before.txt`，`path|size|sha256`，sha256 `9bf80c04…`）**：

```
.godot/.gdignore|1|01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b
project.godot|218|bd5f5524a81063b57079ce9c70bf599204eb363294e15f9ccab7d5d8d7fc198d
resources/corrupt.tres|80|2800faaa84853893bec271f500f9230586aaeb819c1f4e62c1da513c169fd5dd
resources/editable.tres|78|95be599dcb61ce9dd59b0b1a7ca022957856c2df78c4cf726ffbe4b8ffa6bbf8
scenes/doomed.tscn|56|332da267d0b5a5d91106fb5a342793c64ee5c311be7aa3ea740d28de39405e80
```

### 6.2 四类请求的完整证据（`curl.exe -s -o <file>` 落盘后算 sha256；**无管道承载响应体**）

每条证据都有 `%TEMP%\mcp007-write-evidence\<label>.request.json` 与 `.response.json` 两个文件。

**成功路径（4 个工具各一条 + `overwrite=true` 一条）**

| label | curl | 响应体 sha256 | 响应（`result.content[0].text`） |
|---|---|---|---|
| `success-provider-create-resource` | exit 0 | `4962391e…` | `{"changed":{},"path":"res://generated/created.tres","properties_set":["resource_name"],"type":"Resource"}` |
| `success-provider-create-scene` | exit 0 | `78cfb58a…` | `{"created":true,"path":"res://generated/created.tscn","root_name":"ScratchRoot","root_type":"Node3D"}` |
| `success-provider-edit-resource` | exit 0 | `6960a865…` | `{"changed":{"resource_name":{"new":"edited","old":"original"}},"path":"res://resources/editable.tres","type":"Resource"}` |
| `success-provider-delete-scene` | exit 0 | `8446b551…` | `{"deleted":true,"path":"res://scenes/doomed.tscn"}` |
| `success-provider-create-resource-overwrite` | exit 0 | `df55ef6d…` | `{"changed":{},"path":"res://resources/editable.tres","properties_set":["resource_name"],"type":"Resource"}` |

请求体示例（`--data-binary @file`，原样落盘）：

```json
{"method":"tools/call","params":{"arguments":{"path":"res://generated/created.tres","properties":{"resource_name":"mcp_created"},"type":"Resource"},"name":"project_create_resource"},"id":"101","jsonrpc":"2.0"}
```

**缺参 / 类型错（`-32602`）**

| label | 响应体 sha256 | 响应 |
|---|---|---|
| `missing-param-create-resource` | `4f386ff6…` | `{"error":{"code":-32602,"message":"Missing required parameter: type"},"id":"201",…}` |
| `missing-param-edit-resource` | `8d2991c7…` | `{"error":{"code":-32602,"message":"Missing required parameter: properties"},"id":"202",…}` |
| `mistyped-param-delete-path-outside-project` | `a412a064…` | `{"error":{"code":-32602,"message":"Parameter 'path' must not walk upwards with '..', got 'res://../escape.tscn'"},"id":"203",…}` |
| `mistyped-param-create-scene-bad-root` | `c11a17fb…` | `{"error":{"code":-32602,"message":"Parameter 'root_type' must name a node class, got 'McpNoSuchNodeClass'"},"id":"204",…}` |

**底层失败（`-32001` / `-32000`，带 `data.suggestion`）**

| label | 响应体 sha256 | 响应 |
|---|---|---|
| `bottom-delete-missing-file` | `a5c9a5cb…` | `{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the .tscn files of the project"},"message":"Scene file 'res://scenes/never-existed.tscn' not found"}` |
| `bottom-edit-missing-resource` | `453080a8…` | `{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the resources of the project"},"message":"Resource 'res://resources/never-written.tres' not found"}` |
| `bottom-create-existing-without-overwrite` | `4a93ed66…` | `{"code":-32000,"data":{"suggestion":"Set overwrite=true to replace the existing file"},"message":"Resource already exists: res://resources/editable.tres"}` |
| `bottom-create-scene-existing` | `47c8a4a9…` | `{"code":-32000,"data":{"suggestion":"Delete it first with project_delete_scene_file, or choose another path"},"message":"Scene file already exists: res://generated/created.tscn"}` |

三类证据**全部可构造**，没有需要声明「不可构造」的一类。

### 6.3 操作后清单与 diff（`fs.after.txt` sha256 `d8fd98bb…`）

```
--- diff (before -> after) ---
ADDED:
  + .godot/editor/created.mcp-tmp.tres-folding-6eecae6c….cfg|49|fa44dfba…      (编辑器缓存，见 6.5)
  + .godot/editor/created.mcp-tmp.tscn-folding-100dd84e….cfg|49|fa44dfba…      (编辑器缓存，见 6.5)
  + .godot/editor/editable.mcp-tmp.tres-folding-b984c871….cfg|49|fa44dfba…     (编辑器缓存，见 6.5)
  + .godot/editor/filesystem_update4|38|9f6cc285…
  + .godot/uid_cache.bin|53|6457e53b…
  + generated/created.tres|106|c363de15a54af19b738d0309848d6aa32380c02cf9c61067f7633ba515300afb
  + generated/created.tscn|107|1c9b29d4995a1dcb5b6761c537d6d55339474fd1490cf58f958e7e9c6ec0dcea
  + resources/editable.tres|107|b1c2aaa3079ba61d64bfb26ff6d4c51c37c33b3b94e131f8e364d791eed861f7
REMOVED:
  - resources/editable.tres|78|95be599dcb61ce9dd59b0b1a7ca022957856c2df78c4cf726ffbe4b8ffa6bbf8
  - scenes/doomed.tscn|56|332da267d0b5a5d91106fb5a342793c64ee5c311be7aa3ea740d28de39405e80
```

**发布出来的文件是真资源**（用**另一个工具** `project_read_resource` 线上复读，不是只看哈希）：

```
generated/created.tres loads as: type=Resource path=res://generated/created.tres sha256=c363de15…  (工具 self-report 的 path 与磁盘 sha256 相符)
generated/created.tscn loads as: type=PackedScene path=res://generated/created.tscn sha256=1c9b29d4…
resources/editable.tres loads as: type=Resource path=res://resources/editable.tres sha256=b1c2aaa3…
```

文件内容（操作后 `%TEMP%\mcp007-write-scratch` 实读）：

```
generated/created.tres   : [gd_resource type="Resource" format=3 uid="uid://…"] …  resource_name = "mcp_created"
generated/created.tscn   : [gd_scene format=3 uid="uid://…"] …  [node name="ScratchRoot" type="Node3D" unique_id=…]
resources/editable.tres  : [gd_resource type="Resource" format=3 uid="uid://…"] …  resource_name = "overwritten"
```

### 6.4 「删除是可观察且可核对的」

- 请求 `{"path":"res://scenes/doomed.tscn"}` → 响应 `{"deleted":true,"path":"res://scenes/doomed.tscn"}`；
- 前后清单差异里 `scenes/doomed.tscn` **消失**（`REMOVED` 段），`FileAccess::exists` 侧由 doctest
  `[MCPServer] project_delete_scene_file removes the scene and reports the deleted path` 断言
  （前后文件清单 + 目标不存在 + 数量 −2）；
- 再次删除同一路径 → `-32001` + suggestion（`bottom-delete-missing-file` 用的是另一个从未存在的路径；
  同路径二次删除的断言在 doctest 里）。

### 6.5 已知的编辑器侧副作用（不是留下半成品，但必须显式说明）

`ResourceSaver::save()` 在 `res://` 路径上会调用 `save_callback`（`resource_saver.cpp:146-148`），
编辑器据此在自己的资源文件系统里**登记了临时文件的路径**，于是 `.godot/editor/` 下留下 3 个 49 字节的
`<temp>-folding-<hash>.cfg`。要点：

- 名称是**确定的**（`created.mcp-tmp.tres` 等），因此**不会随调用次数增长**；工程内**没有任何**
  `.mcp-tmp` 文件残留（`temporary / partial artefacts left behind in the project (outside .godot/): 0`）；
- 试过两种规避都无效并已记录：把临时文件命名带前导 `.`（dock 跳过它，但 `save_callback` 仍登记）、
  用每次唯一的文件名（只会积累更多）。最终选择**确定性的朴素名字**：可被目录列表看见、下次调用覆盖它、
  每条路径都会删它；
- 若临时文件名不以 `.` 结尾且**扩展名不是最后一段**（例如 `created.tres.mcp-tmp`），
  `ResourceFormatSaver::recognize_path()` 拿到的扩展名就不是 `tres`，**每一次保存都会失败**
  （`File unrecognized`）。这是本任务中实测到并修掉的一个真 bug（见 §8 缺陷 1）。

## 7. 「失败不破坏原文件」——反例证据

反例是一个**只读/损坏**的既有文件 `resources/corrupt.tres`（80 字节，内容是被截断的 `.tres`，
sha256 `2800faaa…`，`corrupt.tres` 本身仍可被 `FileAccess` 读到、但 `ResourceLoader` 无法加载）。
四条失败调用全部以同一个文件为目标：

| label | 请求 | 响应（sha256） | 目标文件之后 |
|---|---|---|---|
| `counter-example-edit-corrupt-file` | `project_edit_resource` 改其属性 | `-32001` `Loadable resource '…corrupt.tres' not found`，suggestion「…could not be loaded as a resource; fix or delete it first」（`e7dfad9a…`） | 未变 |
| `counter-example-create-over-corrupt-without-overwrite` | `project_create_resource` 无 overwrite | `-32000` `Resource already exists: …corrupt.tres` + suggestion（`2a5c02b6…`） | 未变 |
| `counter-example-create-over-corrupt-bad-class` | `project_create_resource` `overwrite=true` + 未知类 | `-32602` `Parameter 'type' must name a resource class…`（`624b2718…`） | 未变 |
| `counter-example-create-scene-over-corrupt` | `project_create_scene_file` 覆盖它 | `-32000` `Scene file already exists: …corrupt.tres` + suggestion（`9f5c8d23…`） | 未变 |

逐字节核对（驱动脚本自己算的，也在 §6.3 的清单里）：

```
corrupt.tres before: resources/corrupt.tres|80|2800faaa84853893bec271f500f9230586aaeb819c1f4e62c1da513c169fd5dd
corrupt.tres after : resources/corrupt.tres|80|2800faaa84853893bec271f500f9230586aaeb819c1f4e62c1da513c169fd5dd
corrupt.tres unchanged: True
```

机制上这不是巧合：`_save_resource_atomically()` 把 `ResourceSaver::save()` 重定向到临时文件，
**只有保存成功后**才 `remove(dest)` + `rename(temp, dest)`；目的文件已存在时先把旧字节
`copy` 到备份，发布步骤失败就把备份拷回。任何一条失败路径最后都 `remove` 掉临时文件与备份。
doctest `[MCPServer] the write tools never corrupt an existing file when the call fails` 把同一组
反例（外加「覆盖损坏文件时 `after != before` 为假、`after` 非空」）钉在单元层。

## 8. 缺陷 / 纠错记录（含已撤回的主张）

1. **临时文件名破坏了扩展名识别（实测的真 bug，已修）**：初版把临时文件命名为
   `<path>.mcp-tmp-<ticks>`（如 `created.tres.mcp-tmp-123`）。`ResourceSaver::save()` 用
   `ResourceFormatSaver::recognize_path()`（`resource_saver.cpp:74-89`）比较
   `p_path.get_extension()`——即**最后一个点**之后的部分——与 saver 的扩展名表，于是扩展名成了
   `mcp-tmp-123`，**所有保存都失败**（`File unrecognized`）。证据：第一次 gate② 驱动在**真实编辑器**
   上 3 条成功路径全部返回 `-32603 Internal error: Failed to save resource: File unrecognized`。
   修法：把临时名插在扩展名**之前**（`created.mcp-tmp.tres`），并把该约束写进源码注释（§6.5）。
2. **`ResourceLoader` 的按路径缓存曾伪造出一个「覆盖无效」的假象（已澄清）**：写组 doctest 一度断言
   `overwrite=true` 后 `resource_name == "mcp_overwritten"` 而失败，得到 `mcp_created`。当时据此写下
   「`ResourceSaver::save()` 保留已有资源的 `resource_name`」的结论，**该结论已撤回**：磁盘上的文件确实
   是 `resource_name = "overwritten"`，失败原因是 `ResourceLoader::load()` 的按路径缓存把之前读过的实例
   还了回来。修法：断言改用 `ResourceLoader::load(path, "", CACHE_MODE_IGNORE)`，更强的名字断言随即全绿。
3. **`project_delete_scene_file` 的 `.import` sidecar 不能作为稳定可观察量（已撤回一项主张）**：
   scratch 工程里预先放好的 `scenes/doomed.tscn.import` 在工具删除后**又出现了**——因为 scratch 编辑器
   自己的 rescan 会为它认识的 `.tscn` 重建 sidecar。故：工具删 sidecar 的行为保留在实现里（与迁移源一致），
   但 scratch 证据不再以「sidecar 不存在」为断言，报告 §2 已把这条差异写明。
4. **`.godot/editor/*-folding-*.cfg` 是编辑器缓存，不是工程残留**：见 §6.5，已量化（3 个 49 字节，
   名称确定、不增长），并在驱动脚本里单独统计、不混入「工程内残留」的计数。

## 9. 文件 sha256（本组脚本与契约）

| 文件 | bytes | sha256 |
|---|---|---|
| `docs/tools_list.renamed.json` | 99698 | `c4f913d65c3f3fd311d36ded44b473189cf886f098959fe7b6edf49b74901298` |
| `docs/tool-rename-map.json`（**未改**） | 70917 | `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd` |
| `docs/tool-groups.json` | 5684 | `da0570143060b820f81a6d245a0d48660f363996fc0ac7c877299706420cd19b` |
| `docs/TOOL-NAMING.md` | 98720 | `ce9bc325699cae6cfaec104d1e3477e91d78a5440f8893366cc030c03c36c975` |
| `docs/DESIGN-DETAIL.md` | 36749 | `75ccf5d9d358d24d87135daf5c0782576a59389d3d4216eaed2ba655ee63649e` |
| `scripts/gen_renamed_contract.py` | 25621 | `8c719c2db2682b290d2cd931f1c77033db719a902796f91ff2433c0dc6fb8164` |
| `scripts/check_contract_subset.ps1` | 23074 | `b2fd8cdbcb9724caa9c0161fde25d38cd176112c171e82c87d21e05be2f952ce` |
| `scripts/accept_m1.ps1` | 59153 | `efb20daae1de4626916b99576b5371123cdb65668bc64df04acf4f23661542f1` |
| `scripts/mcp007_write_evidence.ps1` | 17932 | `ecc44655875ae57a56fb5c38a39801f0fc873a35e41da82adaef25cdc3733aff` |
| `tools/project_write_resource_scene.cpp` | 30212 | `c1d0a2d0d79e36f3dfa4b8fca4354451d8359bf6188d1c4ffc8810af64e07928` |
| `tools/project_write_resource_scene.h` | 4252 | `2c4efd518f9bfcc0e25c40f24df402afa3f57e94ac9bb72ee8ab00a858111407` |
| `tools/editor_read_scene_inspector.cpp` | 27992 | `cab2a176d157bdd13cecc5b1493387ca2ff99e6a4552bcf85761d335f33ded9c` |
| `tool_registry.cpp` | 11154 | `9c3a1064ff0ef2cea1574417831ab27489e74f7f888ba410dded20019880a24a` |
| `tool_registry.h` | 7895 | `ffb1c65d9c9b2c70bafa0880ddecdb3aef08dae2df2b3438adf797ebf2f420c6` |
| `tools/registration.cpp` | 2944 | `668f34482e335d695b82a3519b35b850c7442620119af0c53f6f54de9cdb1892` |
| `tests/test_mcp_server.h` | 168554 | `d6277fcfc09a290050aa1195fe39abc4d85098e01860ce1f83786e9a08c9f634` |

引擎二进制（所有门的对象）：`bin/godot.windows.editor.x86_64.console.exe` 300544 bytes
sha256 `32436f6b51c45c297ba71d003ac8cc5f68413471e1cfa24ee905281443936880`。

## 10. `docs/DESIGN-DETAIL.md` §17.3 的补充（第二部分交付物）

在 §17.3 末尾追加一条（不新建规范文档）：

> **按端点推导期望工具集（TASK-006 §2，TASK-007 §2 写入规范）**：`scope` 决定端点可见性——
> `scope=editor` 的工具**只能**出现在编辑器端点（9888），`scope=game` 只能出现在游戏端点（9889），
> `scope=both` 两端都出现。`docs/tool-rename-map.json` 是 `scope` 的唯一事实源，因此
> `check_contract_subset.ps1` 与 `accept_m1.ps1` **按端点**推导期望集合并断言，而不是维护第二份手写清单：
> 把「所有 `implemented=true` 组的并集」按 `scope` 分成 editor-only / game-only / both 三类，编辑器端点
> 期望全体、游戏端点期望「全体 − editor-only」；已实现却属于另一端点的工具**缺席**是显式断言
> （`MUST be hidden on the <label> endpoint`），任一方向泄漏都判 FAIL。线上行为另一半：游戏端点上按名
> 调用 editor-only 工具必须是 `-32601`（`accept_m1.ps1` 的 `case12`）。doctest
> `[MCPServer] the editor_read_scene_inspector group is editor-only` 与
> `[MCPServer] the project_write_resource_scene tools are registered as mutating both-scope tools`
> 分别钉住进程内的两个方向。

## 11. deviations（与手册 / 任务书的偏离，逐条显式列出）

1. **生成器新增 `mode: "replace"`**（§5.4）：TASK-007 §1 要求「描述要改对」，而 v1.2 的 append-only
   自检只能追加，会在 description 里留下互相矛盾的两句。扩展是**向后兼容**的（默认 append、6 条既有
   append 条目字节不变），并加了两条新自检（replace 必须在 `reason` 里逐字引用旧文本；未知 mode 报错）。
   `_meta.overrides` 的每条记录因此多了 `mode` 键。
2. **`project_create_scene_file` 拒绝覆盖已有文件**（§2）：迁移源会静默覆盖，契约也没有 `overwrite`
   参数。写组的第一条纪律是「不得破坏既有文件」，故按最保守语义拒绝（`-32000` + suggestion）。
3. **临时文件机制**（§6.5）：迁移源直接 `ResourceSaver::save()` 到目标路径；本实现改为
   「临时文件 + 备份 + 重命名」，并把临时文件命名为 `"<base>.mcp-tmp.<ext>"`（确定性、扩展名在最后）。
4. **`ToolBuilder` 之外的一处共享文件改动**：为 `-32000` 增加了一个集中的工厂
   `MCPToolError::tool_state(message, suggestion)`（`tool_registry.{h,cpp}`），而不是在写组文件里手工拼
   `MCPToolError` 结构体。理由：`data.suggestion` 的拼法与 `no_scene()` / `not_implemented()` 必须一致，
   否则同一类错误会长出两种形状。既有工厂未动。
5. **`accept_m1.ps1` 的 `$ToolNames` 追加 4 个写工具**：该脚本的逐端点 scope 推导（TASK-006 §2）已经
   是「按 map 推导」，AI 只需把新工具加进「已实现并集」这一份清单；顺序按 `tool-groups.json`。
6. **doctest 一度被改成断言「保存失败」**：在本组的历史中间态里，`_temporary_sibling_path()` 的扩展名
   bug 让 doctest 进程里所有保存都失败（`ERR_FILE_UNRECOGNIZED`），当时据此把 5 个用例改成断言失败路径。
   修掉 bug 后**已改回成功路径**（`bd1961a250`）。同一份 doctest 现在同时断言：成功写盘后的文件系统
   状态、失败调用的 `-32603/-32602/-32001/-32000`、以及「不留下半成品」。
7. **`project_read_resource` 的 `-32001` 措辞用于损坏文件**：`edit_resource` 对「存在但加载不了」的文件
   返回 `Loadable resource '<path>' not found`（`-32001`），而不是 `-32603`。理由：`-32001` 的语义正是
   「工具找的那个具体东西不在那里」，且带 suggestion；`-32603` 更适合「操作已开始但底层失败」。
8. **报告新增 §8 纠错记录**：按手册 §7.3 的要求，把「临时名扩展名 bug」「缓存假象」「sidecar 主张撤回」
   写成 append-only 式的显式勘误，而不是悄悄改掉。

## 12. blockers

无。所有门在冻结态 `7cb87e78cb` 上跑完，退出码均为 0。工作树除既有 4 个未跟踪物外干净；未 push；
未占用 9877（每次运行的 `pid_before == pid_after == 36392` 守卫均 PASS）。

## 13. next_step_recommendation

1. **B1 剩余两组**：`editor_write_scene_editor`（10 个工具，含 `fix_implementation_first` 的
   `editor_remove_output_log`——必须先写红测试证明当前缺陷再修）与 `running_game_read_scene`（1 个
   `scope=game` 工具）。后者落地后门①的「game-only 在编辑器端点必须缺席」方向第一次有真实对象。
2. **`find_signal_connections` 的 `_meta.overrides` 理由仍带着旧事实**（“与 editor_analyze_signal_flow …
   不过滤非持久连接”对照的是已被纠正的描述）。本次未改它，避免扩大范围；若决策者认可 §5.4 的
   `mode: replace`，可顺手用同一机制纠正该理由的措辞。
3. **`tool-rename-map.json` 里 `analysis.rs:387 …（flags & 1）` 的 reason 仍是旧事实**。改它会动 map sha →
   文档指纹 → 契约 `_meta.map_sha256`，按手册 §6 第 5 条应由决策者裁决，不宜由实现者顺手改。
4. **写组后续**可考虑把「原子发布 + 临时文件命名约束」提到 `tool_helpers`（目前是写组文件私有），
   下一批有写工具时再评估；现在只有一个写组，提前抽象会制造无第二用户的接口。