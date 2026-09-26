# REPORT-008 — 移植组 `editor_write_scene_editor`（10 个编辑器写工具 + fix-first）+ 原子发布助手上提

- **status**：`pass` — 五道门全绿（真实退出码 0），§2 的 `fix_implementation_first` 有完整的
  **红（doctest + 线上）→ 修 → 绿（doctest + 线上）** 证据链，原子发布助手的上提有**线上字节等价**证明，
  10 个工具全部在**真实编辑器进程（9888）**上取得三类证据与状态链，游戏端点（9889）上 10 个工具
  **全部缺席且调用得到 `-32601`**。工作树除开工前既有的 4 个未跟踪物（`.graphifyignore`、`build-m0.cmd`、
  `graphify-out/`、`install-deps-m0.cmd`）外干净；**未 push**。
- 冻结态：commit `7292af5930`；引擎二进制 `bin/godot.windows.editor.x86_64.console.exe`
  sha256 `557a31dac29a58c4bd59239350e1c4a65d1292c7634445df7adb03a34b881ce3`（300544 bytes，`--version`
  报 `4.8.dev.custom_build.7292af593`）。**所有门都在它上面跑完**（提交后重建，见 §4.0）。
- **契约与映射未动**：`docs/tools_list.renamed.json` 与 `docs/tool-rename-map.json` 的 sha256 与
  REPORT-007 完全一致（§9）；本任务没有发现契约错误，因此**没有**任何 description/schema 纠正。
- **本组是第一个同时含 `fix_implementation_first` 的组**，也是第一个把 TASK-007 的私有写盘助手
  上提到 `tools/tool_helpers.*` 的组。两件事都有独立证据：§5（红→修全程）、§6（等价性证明）。

## 1. commits

| sha | 说明 |
|---|---|
| `1c577660e9` | `mcp_server: TASK-008 - hoist the atomic publish helper into tools/tool_helpers (framework cleanup)`（3 M：`tool_helpers.{h,cpp}`、`project_write_resource_scene.cpp`） |
| `c3028a07dd` | `mcp_server: TASK-008 - failing tests for the editor_write_scene_editor group (TDD red)`（4 M + 1 new；组文件此时**只**含迁移源逐字复刻的 `clear_output`） |
| `7292af5930` | `mcp_server: TASK-008 - port the editor_write_scene_editor group (10 editor write tools)`（4 M：修实现 + 注册 + `implemented=true` + `accept_m1.ps1` 名单） |

`git diff --stat f312d33cca..7292af5930`（开工前 HEAD = `f312d33cca`）：

```
 modules/mcp_server/docs/tool-groups.json            |    2 +-
 modules/mcp_server/scripts/accept_m1.ps1            |   12 +-
 modules/mcp_server/scripts/mcp008_editor_write_evidence.ps1 | 675 +++++++++++
 modules/mcp_server/tests/test_mcp_server.h          |  409 ++++++-
 modules/mcp_server/tools/editor_write_scene_editor.cpp | 1184 ++++++++++++++++++++
 modules/mcp_server/tools/editor_write_scene_editor.h   |   75 ++
 modules/mcp_server/tools/project_write_resource_scene.cpp |  101 +-
 modules/mcp_server/tools/registration.cpp           |    2 +
 modules/mcp_server/tools/tool_helpers.cpp           |   78 ++
 modules/mcp_server/tools/tool_helpers.h             |   53 +
 10 files changed, 2507 insertions(+), 84 deletions(-)
```

## 2. 逐工具表

10 个工具在 `tool-rename-map.json` 里全部 `scope=editor`、`mutating=true`、`channel=editor`，
因此全部走 `MCP_EDITOR_TOOLS_ENABLED` 守卫、全部以 `MCPToolScope::EDITOR` 注册。

| `new_name` | 迁移源 | 可观察契约（参数 / 返回形状 / 错误） | C++ 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `editor_open_scene` | `scene.rs:117` | `path` str 必填、必须 `res://`、`..` → `-32602`；不存在 → `-32001`+suggestion；**存在但加载不了 → `-32001`+suggestion**；成功 → `{"opened":true,"path":<归一后>}` | `_tool_open_scene` | **一处收紧**：迁移源 `open_scene_from_path` 后无条件报 `opened:true`，因此「文件在但场景载入失败」会被谎报成功。本实现回读 `edited_scene_root()->get_scene_file_path()`，不等即 `-32001`（与 REPORT-007 缺陷 7 给 `project_edit_resource` 的形状一致） |
| `editor_save_scene` | `scene.rs:151` | `path` str 可选（空/缺 → 存回当前路径）；无编辑场景 → `-32000 no_scene`；场景无路径且未给 `path` → `-32000`+suggestion；`path` 非 `res://`/`..` → `-32602`；扩展名不可识别/目标只读 → `-32603`；成功 → `{"saved":true,"path":<归一后>}` | `_tool_save_scene` | **写盘改为原子发布**（§6）。为保持原子性，用 `PackedScene::pack(root)` + `ResourceSaver::save(temp)` 而不是 `EditorInterface::save_scene_as()`：后者写进目标路径**并把编辑场景重指向该路径**，重定向到临时文件会让编辑器指向 `x.mcp-tmp.tscn`。发布成功后才 `set_scene_file_path` + `set_scene_as_saved`。编辑器的额外簿记（editor states/external resources/folding）未复刻，已在 §11 记录 |
| `editor_reload_plugin` | `editor.rs:430` | 无参数；成功 → `{"message":…,"plugins":[…],"reloading":true}`；本工程无启用的 addon → `-32000`+suggestion | `_tool_reload_plugin` | **语义按「内置模块没有 MCP addon」重构**（§5.4）：迁移源对硬编码名 `godot_mcp` 做 disable+enable；本 fork 的 MCP 是内置模块，没有该 addon，照抄只会调用一个不存在的插件再谎报 `reloading:true`。本实现保留「禁用再启用」机制，作用对象改为 `editor_plugins/enabled` 里**真实存在的**插件；列表为空时 `-32000` 而不是假成功 |
| `editor_rescan_project_filesystem` | `editor.rs:445` | 无参数；成功 → `{"message":"文件系统已重新扫描","reloaded":true}` | `_tool_rescan_project_filesystem` | 一致（`EditorFileSystem::scan()` 是异步的，返回的是「已触发」，与迁移源同） |
| `editor_set_node_selection` | `node.rs:651` | `node_paths`(array[str]) 或 `node_path`(str) 二选一，都缺 → `-32602`；`mode` ∈ {replace,add,remove}（默认 replace，越界 → `-32602`）；`inspect` bool 默认 true；`focus` bool 默认 = inspect；节点不存在 → `-32001`+suggestion；无编辑场景 → `-32000 no_scene`；成功 → `{"count":N,"mode":…,"selected":[{name,path,type}]}` | `_tool_set_node_selection` | 一致（含「单节点时 focus/inspect」与「root 记为 `.`、场景外节点跳过」两条序列化规则）；差异仅 PLAYBOOK §6.2 已接受的「present 但类型错 → `-32602`」 |
| `editor_remove_node_selection` | `node.rs:722` | 无参数；无编辑场景 → `-32000 no_scene`；成功 → `{"cleared":<清空前的选中数>,"count":0,"selected":[]}` | `_tool_remove_node_selection` | 一致 |
| `editor_add_resource_to_node_property` | `node.rs:365` | `node_path`/`property`/`resource_type` 必填；`resource_properties` object 可选；类不存在 → `-32602`、类非 `Resource` 子类 → `-32602`、类不可实例化 → `-32602`；节点不存在 → `-32001`；无编辑场景 → `-32000`；成功 → `{"node_path":<相对 root，root 记 ".">,"property","resource_type"}` | `_tool_add_resource_to_node_property` | 一致（未知属性名经 `Object::set()` 静默跳过，与迁移源同）；多一条 `can_instantiate` 检查（见 §11） |
| `editor_set_viewport_3d_camera` | `editor.rs:635` | 四个可选参数 `position`/`rotation_degrees`/`look_at`（`{x,y,z}` object，分量缺省 0.0，非数字 → `-32602`）、`fov`(number，非数字 → `-32602`）；无 3D 视口/相机 → `-32603`「无法获取3D视口, 请确保已打开3D场景」；成功 → `{"fov","position":{x,y,z},"rotation_degrees":{x,y,z}}` | `_tool_set_viewport_3d_camera` | 一致（连设置顺序 position→rotation→look_at→fov 都相同）；迁移源用 GDScript `Expression`，本实现用真实 `Camera3D` API。**实测**：位置的改动可被后续读取工具看到，`fov` 会被编辑器自己的视口控制器每帧回写（§7.4）——不是本实现引入的差异，迁移源形状相同 |
| `editor_capture_screenshot` | `editor.rs:306` | `save_path` str 可选，必须 `res://` 或 `user://`、`..` → `-32602`、必须是文件名（`res://` 本身 → `-32602`）；成功无 `save_path` → `{"height","image_base64","width"}`；有 `save_path` → `{"height","saved_path","width"}`；取不到渲染图像 → `-32603`；写盘失败 → `-32603` | `_tool_capture_screenshot` | **两处收紧**：(1) 写盘走原子发布；(2) `save_path` 写失败是**错误**。迁移源吞掉失败、照样删掉 `image_base64` 并回 `{width,height}`（既没图也没文件却是成功态）——TASK-008 §2(c) 禁止的「假成功」形态。返回键集与迁移源一致（无 `format`，与 game 截图不同） |
| `editor_remove_output_log` | `editor.rs:421` | 无参数；**无 EditorLog 的进程 → `-32000`+suggestion（绝无 `cleared:true`）**；成功 → `{"cleared":true,"log_is_empty":bool,"log_was_empty":bool}`（`null` = 面板视图未定位到，即「未测量」而非「原本就空」） | `_tool_remove_output_log` | **本组的 fix-first 项，见 §5**：迁移源 `godot_print!` 51 个空行 + `{"cleared":true}`，Output 面板一个字都没清。本实现调用面板 *Clear* 按钮真正绑定的那个操作（`EditorLog::clear()` → `_clear_request()`）并回报面板的前后测量值 |

`properties` 值转换（`_property_value_from_json` + `_coerce_to_property_type`）复刻迁移源的
`parse_value_for_property`（`serialize.rs:268`）：JSON 整数在目标是 `int` 属性时折回 `INT`、
`#rrggbb` → `Color`、`Vector2(...)`/`Vector3(...)` → 对应向量、对象保留为 `Dictionary`，最后经
`VariantUtilityFunctions::type_convert`（引擎自带 `@GlobalScope.type_convert`）落到属性类型；非有限数
显式 `-32602`。这是 `project_write_resource_scene.cpp` 同逻辑的一份**局部**副本，理由见 §11.3。

## 3. 红 / 绿证据（TDD）

### 3.1 红阶段（commit `c3028a07dd`）

组文件此时**只**注册 `editor_remove_output_log`，且实现是迁移源逐字复刻（打印空行 + `cleared:true`），
另加两个**测量字段**（`log_was_empty`/`log_is_empty`），因为迁移源**根本没有观测面板的手段**——这正是
它能长期说谎的原因。其余 9 个工具未注册。基线（TASK-007 交付态）= **89 例 / 1213 断言**。

```
[doctest] test cases:   94 |   89 passed | 5 failed | 1429 skipped
[doctest] assertions: 1729 | 1627 passed | 102 failed |
[doctest] Status: FAILURE!
EXIT=1
```

关键失败（`tests/test_mcp_server.h:4210` 起的用例）：

```
===============================================================================
.\modules/mcp_server/tests/test_mcp_server.h(4210):
TEST CASE:  [MCPServer] editor_remove_output_log never reports a clear it cannot perform

.\modules/mcp_server/tests/test_mcp_server.h(4220): ERROR: CHECK( result.get_type() == Variant::NIL ) is NOT correct!
  values: CHECK( 27 == 0 )                       <- 回了一个 DICTIONARY
.\modules/mcp_server/tests/test_mcp_server.h(4222): ERROR: CHECK_FALSE( (bool)((Dictionary)result).get("cleared", false) ) is NOT correct!
  values: CHECK_FALSE( true )                    <- "cleared": true，即那句假话
.\modules/mcp_server/tests/test_mcp_server.h(4224): ERROR: CHECK( error.is_error() ) is NOT correct!
  values: CHECK( false )
.\modules/mcp_server/tests/test_mcp_server.h(4225): ERROR: CHECK( error.code == -32000 ) is NOT correct!
  values: CHECK( 0 == -32000 )
.\modules/mcp_server/tests/test_mcp_server.h(4235): ERROR: CHECK( response.body.contains("\"code\":-32000") ) is NOT correct!
  values: CHECK( false )
===============================================================================
```

其余 4 个失败用例是整组的注册（编辑端 31 = 23+7+1 而不是 40）与参数校验（工具尚不存在 →
`Unknown tool`）。

### 3.2 红阶段的**线上**证据（同一个谎言，在真实编辑器上）

`-Phase redclear` 在真实 headless 编辑器（9888）上，先把 Output 面板喂上内容，再调用工具：

```
[redclear-clear-output-log] curl_exit=0 bytes=142 sha256=1712c33ecf031beee4356062b15aad4e96cb678d445a4eaaaa09963be9bacc7b
        request : {"method":"tools/call","params":{"arguments":{},"name":"editor_remove_output_log"},"id":"801","jsonrpc":"2.0"}
        response: {"id":"801","jsonrpc":"2.0","result":{"content":[{"text":"{\"cleared\":true,\"log_is_empty\":false,\"log_was_empty\":false}","type":"text"}]}}
[PASS] redclear_reports_cleared_without_clearing :: cleared=True log_was_empty=False log_is_empty=False
```

响应体自己就是反证：`cleared:true` 与 `log_is_empty:false` 出现在同一句话里。红阶段证据快照：
`%TEMP%\mcp008-red-evidence\`（含 `redclear-clear-output-log.{request,response}.json` 与 `red-doctest.log`）。

### 3.3 绿阶段（冻结态 `7292af5930`）

```
[doctest] test cases:   94 |   94 passed | 0 failed | 1429 skipped
[doctest] assertions: 1728 | 1728 passed | 0 failed |
[doctest] Status: SUCCESS!
EXIT=0
```

同一个用例同一组断言现在全绿；同一个请求现在得到：

```
[success-clear-output-log] curl_exit=0 bytes=140 sha256=428f4427511b2c037a5d433caa198020f64d6da73eb155311a5f985d4f902ac4
        response: {"id":"81","jsonrpc":"2.0","result":{"content":[{"text":"{\"cleared\":true,\"log_is_empty\":true,\"log_was_empty\":false}","type":"text"}]}}
[success-clear-output-log-again] … sha256=e7951136fffbde92c45dcb73f7087f3c4a637e1b61187ea383eb9192eeabd478
        response: … {"cleared":true,"log_is_empty":true,"log_was_empty":true}
[PASS] success_clear_output_log :: cleared=True log_was_empty=False log_is_empty=True
[PASS] success_clear_output_log_idempotent :: cleared=True log_was_empty=True log_is_empty=True
```

第二次调用报 `log_was_empty:true`，这只可能在第一次真的把面板清空之后成立。

## 4. 五道门

### 4.0 冻结与重建

提交 `7292af5930` 之后**重建**，使二进制版本哈希与被门验证的源码一致：

```
bin/godot.windows.editor.x86_64.console.exe --version
4.8.dev.custom_build.7292af593
sha256 557a31dac29a58c4bd59239350e1c4a65d1292c7634445df7adb03a34b881ce3   (300544 bytes)
```

> 构建命令的坑（已记入 §10.1）：`build-m0.cmd` **不带** `tests=yes`，用它构建出的二进制
> `--test` 直接 Abort（"compiled without support for unit tests"）。本任务用
> `scons platform=windows target=editor module_mono_enabled=no tests=yes -j8`。

### 4.1 门① 契约子集逐字 —— `check_contract_subset.ps1 -Group editor_write_scene_editor` → **3/3 PASS（退出码 0）**

```
scope       : editor-only=17 game-only=0 both/shared=23
editor set  : 40 tool(s)
game set    : 23 tool(s)
[PASS] editor_9888_contract_subset
       editor port=9888 tools=40 order=project_get_info > … > editor_remove_output_log |
         editor_open_scene: name=True description=True inputSchema=True
       | editor_save_scene: name=True description=True inputSchema=True
       | editor_reload_plugin: name=True description=True inputSchema=True
       | editor_rescan_project_filesystem: name=True description=True inputSchema=True
       | editor_set_node_selection: name=True description=True inputSchema=True
       | editor_remove_node_selection: name=True description=True inputSchema=True
       | editor_add_resource_to_node_property: name=True description=True inputSchema=True
       | editor_set_viewport_3d_camera: name=True description=True inputSchema=True
       | editor_capture_screenshot: name=True description=True inputSchema=True
       | editor_remove_output_log: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset
       game port=9889 tools=23 order=… > project_edit_resource |
         editor_open_scene: correctly absent on the game endpoint
       | editor_save_scene: correctly absent on the game endpoint
       | editor_reload_plugin: correctly absent on the game endpoint
       | editor_rescan_project_filesystem: correctly absent on the game endpoint
       | editor_set_node_selection: correctly absent on the game endpoint
       | editor_remove_node_selection: correctly absent on the game endpoint
       | editor_add_resource_to_node_property: correctly absent on the game endpoint
       | editor_set_viewport_3d_camera: correctly absent on the game endpoint
       | editor_capture_screenshot: correctly absent on the game endpoint
       | editor_remove_output_log: correctly absent on the game endpoint
[PASS] guard_user_port_9877
       pid_before=36392 pid_after=36392
3/3 checks passed
```

**逐端点 scope 语义**：门①按 `tool-rename-map.json` 的 `scope` 推导两端期望集合。编辑器 40 /
游戏 23，差值 17 = editor-only 工具总数（TASK-006 的 7 + 本组 10），**没有一条本组工具泄漏到游戏端点，
也没有一条因实现不全而缺席**。

### 4.2 门② 三类证据 + 状态链 —— 见 §7、§8

新增驱动 `scripts/mcp008_editor_write_evidence.ps1`（675 行，四个 phase 加一个红阶段 phase）。

| phase | 端口 | 结果 | 说明 |
|---|---|---|---|
| `main` | 9888（headless 编辑器） | **41/41** | 10 个工具的三类证据 + 状态链 + 只读反例 + 清空面板 |
| `gui` | 9888（真实窗口编辑器 512×384） | **7/7** | `editor_capture_screenshot` 的**成功类**（headless 下渲染驱动是 dummy，取不到图像） |
| `noplugin` | 9888（工程未启用 addon） | **3/3** | `editor_reload_plugin` 的诚实底层失败 |
| `gamecall` | 9889（游戏进程） | **14/14** | 23 条 tools/list + 10 条 `-32601` 且无 `result` |
| `redclear` | 9888（红构建） | **3/3** | §3.2 的谎言 |

### 4.3 门③ 模块 doctest（`--headless --test --test-case="[MCPServer]*"`）→ **SUCCESS（退出码 0）**

```
[doctest] test cases:   94 |   94 passed | 0 failed | 1429 skipped
[doctest] assertions: 1728 | 1728 passed | 0 failed |
```

基线 89 例 / 1213 断言 → **+5 例 / +515 断言**。

### 4.4 门④ 全引擎回归（`--headless --test`）→ **SUCCESS（退出码 0）**

```
[doctest] test cases:   1520 |   1520 passed | 0 failed | 3 skipped
[doctest] assertions: 426009 | 426009 passed | 0 failed |
```

基线 1515 例 / 425494 断言 → **+5 例 / +515 断言，0 failed**。

### 4.5 门⑤ `accept_m1.ps1` 连跑两次 → **A_EXIT=0 / B_EXIT=0**

两次均 **22/22 cases passed**，`PASS` 清单逐条比对**完全一致**（`diff` 无输出）：

```
implemented tools = 40 (editor endpoint) / 23 (game endpoint); contract = 171;
known_deviation = per-batch verbatim gate only
PASS  case20_tools_list_cross_process_restart
      pid_first=51220 pid_second=4024 tools=40 bytes=11400/11400 byte_identical=True
      sha256_first=017223da23eb56c3b006e624c020b6dbb34407169ba9355f02fc7cd8e665081f
      sha256_second=017223da23eb56c3b006e624c020b6dbb34407169ba9355f02fc7cd8e665081f
PASS  case12_game_process_endpoint  … editor_scope_leaked=  editor_tool_call={"error":{"code":-32601,"message":"Method not found: editor_get_errors"}…}
PASS  guard_user_port_9877
22/22 cases passed
```

`accept_m1.ps1` 本轮只改了一处：把 10 个工具按 `tool-groups.json` 的顺序加进 `$ToolNames`
（`accept_m1.ps1:113-124`）；逐端点 scope 推导逻辑**未动**。

## 5. `editor_remove_output_log` 的红→修全程与最终语义（TASK-008 §6.1）

### 5.1 迁移源为什么是坏的

`editor.rs:421-425`：

```rust
fn cmd_clear_output(_args: &serde_json::Map<String, serde_json::Value>) -> Result<serde_json::Value, McpError> {
    // 在 Rust 中通过打印空行来模拟清除
    godot_print!("\n\n…(51 个空行)…\n\n");
    Ok(serde_json::json!({"cleared": true}))
}
```

Output 面板是 `EditorLog` 控件（`editor/editor_log.h:42`），内容存在它的私有
`Vector<LogMessage> messages` 与私有 `RichTextLabel *log` 里，只由 `EditorLog::add_message()`
喂入。向 **stdout** 打印空行与这个控件**没有任何关系**：迁移源既没有清面板，也没有能力观测面板，
所以它能长期报 `cleared:true`。

### 5.2 (a) 优先：真实可用的清空路径

面板自己的 *Clear* 按钮绑定的就是唯一正确的入口：

```
editor_log.cpp:542   clear_button->connect(SceneStringName(pressed), callable_mp(this, &EditorLog::_clear_request));
editor_log.cpp:257   void EditorLog::_clear_request() { log->clear(); messages.clear(); _reset_message_counts(); _set_dock_tab_icon(Ref<Texture2D>()); }
editor_log.cpp:264   void EditorLog::clear() { _clear_request(); }
editor_log.h:186     void clear();          // public
editor/editor_node.h:766  static EditorLog *get_log();   // public
```

本实现调用的就是 `EditorNode::get_log()->clear()`——**也就是 Clear 按钮本身**，因此修复在构造上
不可能与 UI 语义偏离。

**测量**：`EditorLog` 的私有 `log` 是模块无法直接读的（`editor/editor_log.h` 在 `modules/mcp_server/**`
之外，只读），但它是该 dock 里**唯一**的 `RichTextLabel` 后代（`bbcode_parser` 只被 `memnew`、
从未 `add_child`，`editor_log.cpp:377-381`），所以模块能通过场景树定位它并用
`get_parsed_text().is_empty()` 回报前后状态。回报键：`log_was_empty` / `log_is_empty`，
**`null` 表示「没测到」而不是「本来就是空」**。

### 5.3 (b) 诚实失败：绝不在没有面板时报成功

守卫（`_require_editor_ui`，即 `EditorNode::get_singleton() != nullptr`）在**任何**动作之前执行；
`EditorLog::get_log()` 为空时返回 `-32000 not_implemented` + `data.suggestion`。
这条不变式由 doctest `[MCPServer] editor_remove_output_log never reports a clear it cannot perform`
钉住：在 doctest 进程（无 EditorNode）里必须**没有**结果、`-32000`、且线级响应里
`"cleared":true` 不出现。

### 5.4 (c) 禁止的形态：已确认不存在

- 红构建（迁移源逐字复刻）证明过它：§3.1 的 doctest 与 §3.2 的 `{"cleared":true,"log_is_empty":false}`。
- 绿构建里：无面板 → `-32000`；有面板 → 只在真正调用 Clear 之后报 `cleared:true`，并且同时报出
  实测的前后状态。

### 5.5 独立旁证：面板 ≠ 日志文件

`editor_get_output_log` 读的是引擎日志文件 `user://logs/godot.log`，是**另一个对象**。驱动器让
编辑器用 `--log-file` 写这个精确路径（编辑器进程**故意忽略**
`debug/file_logging/enable_file_logging`，见 `main.cpp:2300-2301`，所以必须用 `--log-file`），
并在**编辑器退出后从磁盘**读它：

```
[PASS] log_file_is_not_the_panel :: after the panel was cleared the engine log still holds 3 marker line(s):
       bytes=1582 sha256=2d8d76edb31c478f349c8d12911b7d1df4f0ae71e60ed7c0469372c6a46826b8 marker_lines=3
```

即：清空面板**没有**截断引擎日志（面板清空前 3 条 `MCP008_PLUGIN` 标记行仍在）。附带实测一条
与本任务无关但值得记录的观察（`observation-log-file-while-editor-holds-it`）：编辑器运行期间这个
日志文件被引擎持有，`editor_get_output_log` 回 `-32603 cannot open the log file 'user://logs/godot.log'`
（`FileAccess::exists` 为真、`FileAccess::open` 失败）。这是 TASK-006 的既有行为，只在 `--log-file`
下出现，未修改。

### 5.6 最终语义（供 M2 验收复核）

| 场景 | 响应 |
|---|---|
| 无 EditorNode 的进程（doctest / 非编辑器 tools 进程） | `-32000` `Not implemented: the editor UI (no EditorNode is running in this process)` + suggestion |
| 游戏端点（9889） | 工具未注册 → `-32601 Method not found: editor_remove_output_log` |
| 有 EditorNode 但 `EditorLog` 为空 | `-32000` `Not implemented: the editor output log (this process has no EditorLog)` + suggestion |
| 真实编辑器 | `{"cleared":true,"log_is_empty":<实测>,"log_was_empty":<实测>}`，`log_is_empty` 恒为 `true` |

**契约与映射未改**（工具仍在 171 条里，description/schema 与契约逐字一致）。

## 6. 原子发布助手上提的等价性证明（TASK-008 §6.2）

### 6.1 上提内容

`tools/tool_helpers.{h,cpp}` 新增公开的

```cpp
String temporary_sibling_path(const String &p_path);
typedef Error (*AtomicWriteFunc)(const String &p_temp_path, void *p_userdata);
Error publish_file_atomically(const String &p_path, AtomicWriteFunc p_write, void *p_userdata);
```

函数体是 `project_write_resource_scene.cpp` 私有 `_temporary_sibling_path` /
`_save_resource_atomically` 的**逐字搬运**，仅三处编辑：去掉 `static` 与前导 `_`；把唯一那行
`ResourceSaver::save(p_resource, temp_path)` 换成调用方回调 `p_write(temp_path, p_userdata)`。
写入组那侧只剩一个一行的适配器（`_resource_save_writer` + `_save_resource_atomically` 包装），
四个工具的调用点**一个字都没改**。用函数指针而不是 `std::function`：与引擎自己的
`ResourceSaver::save_callback` 同形，且不引入分配。

### 6.2 线上字节等价（重构前后同一请求序列）

用 TASK-007 的门②驱动（`scripts/mcp007_write_evidence.ps1`，**未改**）在**同一个** `%TEMP%` scratch
工程、同一端口 9888 上跑完整序列，分别对重构前 / 重构后的二进制采集：

```
before 18 个 response 文件，逐个 sha256 拼接后再哈希 = 85f4ca55ad03ba2a34b4f98e7e9f42b6c88b62dbc8b23fadc0dd8ab826a01b8b
after  18 个 response 文件，逐个 sha256 拼接后再哈希 = 85f4ca55ad03ba2a34b4f98e7e9f42b6c88b62dbc8b23fadc0dd8ab826a01b8b
files compared: 36 (18 request + 18 response)   identical: 36   different: 0   missing: 0
VERDICT: BYTE-IDENTICAL
```

覆盖成功 / 缺参 / 底层失败 / 只读反例四类共 18 组请求，全部逐字节相同；而且这些 sha256 前 8 位与
REPORT-007 记录的旧值**逐一相符**（例如 `success-provider-create-resource` = `4962391e…`、
`project_edit_resource` = `6960a865…`、`counter-example-edit-corrupt-file` = `e7dfad9a…`），
即顺带对 TASK-007 的冻结证据做了交叉复核。

**一处必须说明的非确定性**：`project_create_scene_file` 生成的 `.tscn` 里带一个**随机 uid**，
所以该文件的磁盘 sha256 每次运行都不同（本次 `7b69e7eb…`/108 bytes，REPORT-007 §6.3 记的是
`1c9b29d4…`/107 bytes）。等价性比较因此只比**响应体**（响应体里没有 uid，逐字节相同）。这只是
TASK-007 报告里一个不可复现的数值，不是本组引入的行为差异，记录在此备查。

## 7. 编辑器状态变化的前后证据链（TASK-008 §6.3）

全部为**编辑器端点 9888 上的真实请求/响应**（`curl.exe -s -o <file>` 落盘，body 从磁盘算 sha256）。

### 7.1 `editor_open_scene`

| 步骤 | 请求 | 响应（`result.content[0].text`） | sha256 |
|---|---|---|---|
| 操作前 | `editor_get_scene_tree {}` | `{"scene_path":"res://scenes/main.tscn","tree":{…}}` | — |
| 操作 | `editor_open_scene {"path":"res://scenes/second.tscn"}` | `{"opened":true,"path":"res://scenes/second.tscn"}` | `d55a40ea04bf8ec0…` |
| 操作后 | `editor_get_scene_tree {}` | `{"scene_path":"res://scenes/second.tscn",…}` | — |

**`scene_path` 由 `main.tscn` 变为 `second.tscn`** —— 这是用**另一个读工具**观测到的真实编辑器状态变化。

### 7.2 `editor_set_node_selection` / `editor_remove_node_selection`

| 步骤 | 请求 | 响应摘要 |
|---|---|---|
| 操作前 | `editor_get_selection {}` | `count=0` |
| 操作 | `editor_set_node_selection {"node_path":"Marker"}` | `{"count":1,"mode":"replace","selected":[{"name":"Marker","path":"Marker","type":"MeshInstance3D"}]}` (`7246b5a5d2edc0a4…`) |
| 操作后 | `editor_get_selection {}` | `count=1`，`nodes[0].path="Marker"` |
| 追加 | `editor_set_node_selection {"node_paths":["Marker","Group/Nested"],"mode":"add","inspect":false,"focus":false}` | `{"count":2,…}` (`ecd73131d57d44ae…`) |
| 移除一个 | `editor_set_node_selection {"node_paths":["Marker"],"mode":"remove"}` | `{"count":1,…"path":"Group/Nested"}` (`47c68bc1d6ec1864…`) |
| 清空 | `editor_remove_node_selection {}` | `{"cleared":1,"count":0,"selected":[]}` (`0e7e0bf2c16ac1a4…`) |
| 清空后 | `editor_get_selection {}` | `count=0` |

`cleared` 恰好等于上一步的选中数 1，且随后的读工具看到 0 —— 前后一致。

### 7.3 `editor_add_resource_to_node_property` → 落盘复核

1. `editor_add_resource_to_node_property {"node_path":"Marker","property":"material_override","resource_type":"StandardMaterial3D","resource_properties":{"albedo_color":"#ff0000","metallic":0.5}}`
   → `{"node_path":"Marker","property":"material_override","resource_type":"StandardMaterial3D"}` (`1cd9660467b54c4a…`)
2. `editor_save_scene {}` → `{"path":"res://scenes/main.tscn","saved":true}` (`4aef92494f7b3661…`)
3. **磁盘复核**（不是哈希自证）：

```
[PASS] add_resource_landed_in_saved_scene :: main.tscn contains the StandardMaterial3D sub-resource: True
```

即 `res://scenes/main.tscn` 里真的出现了 `sub_resource type="StandardMaterial3D"` 段，且
`albedo_color`/`metallic` 由 `resource_properties` 决定。资源是编辑场景的子资源，**不落成独立文件**。

### 7.4 `editor_set_viewport_3d_camera`（含一条**实测**的编辑器行为）

| 步骤 | 响应摘要 |
|---|---|
| 操作前 | `{"far":4000.01,"fov":70.01,"near":0.05,"position":{"x":1.6829,"y":1.9177,"z":3.0806},"rotation_degrees":{…}}` |
| 操作 | `editor_set_viewport_3d_camera {"position":{"x":1,"y":2,"z":3},"fov":42}` → `{"fov":42.0,"position":{"x":1.0,"y":2.0,"z":3.0},"rotation_degrees":{…}}` (`8d0ddf080d3ce391…`) |
| 操作后 | `editor_get_viewport_3d_camera {}` → `{"fov":70.01,"position":{"x":1.0000001,"y":2.0,"z":3.0},…}` |

[PASS] `state_camera_after_position` —— **位置（和旋转）经另一个读工具确认已被改动**。
[PASS] `state_camera_after_fov_reasserted_by_editor :: fov after the editor's own viewport update = 70.0100021362305 (not 42)`.

`fov` 没有保持，这是**编辑器自身**的行为、不是本实现的差异：
`Node3DEditorViewport::_update_camera()` 每次更新都用自己那份状态重算相机投影
（`node_3d_editor_viewport.cpp:3053-3061`：`camera->set_perspective(get_fov(), get_znear(), get_zfar())`），
而那份状态（`Node3DEditor::get_fov()`，`node_3d_editor_plugin.h:454` 只有 getter）**没有模块可达的
public setter**。迁移源形状完全相同（`cam.fov = …` 之后立刻回读），所以工具响应对 `fov` 的
「设置后立即回读」是这一项唯一可得的持久观测。此处**显式记录，不隐藏**。

## 8. 门② 三类证据逐工具（真实请求/响应）与不可构造类声明

### 8.1 成功类

| label | 响应体 sha256 | `result.content[0].text` |
|---|---|---|
| `success-open-scene` | `d55a40ea04bf8ec0…` | `{"opened":true,"path":"res://scenes/second.tscn"}` |
| `success-select-node` | `7246b5a5d2edc0a4…` | `{"count":1,"mode":"replace","selected":[{"name":"Marker","path":"Marker","type":"MeshInstance3D"}]}` |
| `success-select-add-many` | `ecd73131d57d44ae…` | `{"count":2,"mode":"add","selected":[{"name":"Marker",…},{"name":"Nested","path":"Group/Nested","type":"Node3D"}]}` |
| `success-select-remove` | `47c68bc1d6ec1864…` | `{"count":1,"mode":"remove","selected":[{"name":"Nested","path":"Group/Nested","type":"Node3D"}]}` |
| `success-clear-selection` | `0e7e0bf2c16ac1a4…` | `{"cleared":1,"count":0,"selected":[]}` |
| `success-add-resource` | `1cd9660467b54c4a…` | `{"node_path":"Marker","property":"material_override","resource_type":"StandardMaterial3D"}` |
| `success-save-scene-in-place` | `4aef92494f7b3661…` | `{"path":"res://scenes/main.tscn","saved":true}` |
| `success-save-scene-as` | `7e3337eabdb21096…` | `{"path":"res://scenes/out/copy.tscn","saved":true}`（文件确实出现） |
| `success-rescan-filesystem` | `86eca01a62a20610…` | `{"message":"文件系统已重新扫描","reloaded":true}` |
| `success-reload-plugin` | `c73b8060a215db8b…` | `{"message":"编辑器插件已禁用并重新启用","plugins":["res://addons/mcpreload/plugin.cfg"],"reloading":true}` |
| `success-set-camera` | `8d0ddf080d3ce391…` | `{"fov":42.0,"position":{"x":1.0,"y":2.0,"z":3.0},"rotation_degrees":{…}}` |
| `success-clear-output-log` | `428f4427511b2c03…` | `{"cleared":true,"log_is_empty":true,"log_was_empty":false}` |
| `success-clear-output-log-again` | `e7951136fffbde92…` | `{"cleared":true,"log_is_empty":true,"log_was_empty":true}` |
| `success-capture-base64`（gui） | `a967413b4318955a…` | `{"height":2054,"image_base64":"iVBORw0KGgo…","width":3840}`（前 8 个解码字节 = `137,80,78,71,13,10,26,10`，真 PNG） |
| `success-capture-save`（gui） | `7ae5c941e9ac87a8…` | `{"height":2054,"saved_path":"res://screenshots/editor.png","width":3840}`，磁盘 1424105 bytes sha256 `8e435a2a8faebd93…` |

### 8.2 缺参 / 类型错（`-32602`）

| label | 响应体 sha256 | 响应 |
|---|---|---|
| `missing-param-open-scene` | `a5beaf44146f2031…` | `{"code":-32602,"message":"Missing required parameter: path"}` |
| `mistyped-param-save-scene` | `ad38e3dc71d01535…` | `Parameter 'path' must be a string, got float` |
| `mistyped-param-set-node-selection` | `c085c95005a2cc5b…` | `mode must be one of: replace, add, remove` |
| `mistyped-param-add-resource` | `3aeb93a3a0e2f0a3…` | `Missing required parameter: resource_type` |
| `mistyped-param-set-camera` | `dd14bdfd93c48238…` | `Parameter 'fov' must be a number, got String` |
| `mistyped-param-capture-screenshot` | `4aa5c2a59507947a…` | `Parameter 'save_path' must start with 'res://' or 'user://', got 'C:/outside/shot.png'` |

### 8.3 底层失败（`-32001` / `-32000` / `-32603`，带 `data.suggestion`）

| label | 响应体 sha256 | 响应 |
|---|---|---|
| `bottom-open-missing-scene` | `770b07bbaa6b8033…` | `-32001` `Scene 'res://scenes/never_written.tscn' not found` + suggestion |
| `bottom-open-unloadable-scene` | `a90e2b2e3208027f…` | `-32001` `Loadable scene 'res://scenes/broken.tscn' not found` + suggestion（文件在、载入不了） |
| `bottom-select-missing-node` | `318d10aec7175ccb…` | `-32001` `Node 'NoSuchNode' not found` + suggestion |
| `bottom-add-resource-unknown-class` | `8fa827aec1f59075…` | `-32602` `Unknown resource type: McpNoSuchClass` |
| `bottom-add-resource-missing-node` | `f59489bc1476a51e…` | `-32001` `Node 'NoSuchNode' not found` + suggestion |
| `bottom-save-unrecognized-extension` | `ec564814dc6a3a3f…` | `-32603` `Failed to save scene 'res://scenes/bad.txt' (error 15)`，且 `bad.txt` **未创建** |
| `bottom-reload-plugin-without-addon` | — | `-32000` `No editor addon plugin is enabled in this project, so there is no plugin to reload` + suggestion |
| `headless-capture-base64-refused` | `ae4bd21c351ff8fa…` | `-32603` `截图获取失败, 请重试`，无 `result` 包络、无 `image_base64` |
| `headless-capture-save-refused` | `6472d2f025171c30…` | `-32603` 同上，**无** `saved_path`、文件未创建 |
| `counter-example-save-readonly-destination` | `ddaca664c351118f…` | `-32603` `Failed to save scene 'res://scenes/locked.tscn' (error 1)`，目标 sha256 前/后同为 `4f4642eeae23aa3a…`（**逐字节未变**） |

### 8.4 游戏端点缺席（TASK-008 §4.1）

`gamecall` phase 在**真正的游戏进程**（9889）上：

```
[PASS] gamecall_endpoint_serves_23_tools        tools/list on 9889 returned 23 tool(s)
[PASS] gamecall_group_is_absent_from_tools_list leaked editor tools: none
[PASS] gamecall_refuses_editor_open_scene            :: code=-32601 message='Method not found: editor_open_scene'
… （10 个工具各一条，全部 code=-32601）
[PASS] gamecall_refuses_editor_remove_output_log     :: code=-32601 message='Method not found: editor_remove_output_log'
=== phase gamecall: 14/14 checks passed ===
```

每条都同时断言响应里出现 `"code":-32601` 且**不出现** `"result"` —— 即「拒绝且未执行」。

### 8.5 显式声明的「不可构造」类

| 工具 | 不可构造的类 | 原因 |
|---|---|---|
| `editor_reload_plugin` | 缺参 | schema 是 `{"properties":{},"required":[]}`，没有可缺/可错的参数 |
| `editor_rescan_project_filesystem` | 缺参、底层失败 | 无参数；唯一失败模式是编辑器没有 resource filesystem，而运行中的编辑器必然有（无法由任何请求构造） |
| `editor_remove_node_selection` | 缺参、底层失败 | 无参数；唯一失败模式是「无编辑场景」（`-32000 no_scene`），而本组另外九个工具要求会话里必须有编辑场景，故无法在同一个会话里构造；守卫路径由 doctest 钉住 |
| `editor_set_viewport_3d_camera` | 底层失败 | 失败模式只有参数错（`-32602`，已覆盖）与「无 3D 视口/相机」；带 3D 场景的编辑器必有视口与默认相机（REPORT-006 §6 对读工具测得同一事实），故不可构造 |
| `editor_remove_output_log` | 缺参 | 无参数 |
| `editor_remove_output_log` | 底层失败（编辑器端点上） | 真实编辑器必有 `EditorLog`；「无 EditorLog」只可能出现在非编辑器进程，而那正是 doctest 的用例（`-32000`）与游戏端点的 `-32601` 各自覆盖的形态 |

其余工具（`editor_open_scene`、`editor_save_scene`、`editor_set_node_selection`、
`editor_add_resource_to_node_property`、`editor_capture_screenshot`）**三类证据全部可构造**。

## 9. 文件 sha256（本组脚本、代码与契约）

| 文件 | bytes | sha256 |
|---|---|---|
| `docs/tools_list.renamed.json`（**未改**） | 99698 | `c4f913d65c3f3fd311d36ded44b473189cf886f098959fe7b6edf49b74901298` |
| `docs/tool-rename-map.json`（**未改**） | 70917 | `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd` |
| `docs/tool-groups.json` | 5683 | `24422c2246e73d4b0bc4f949116dce3de39b9456f24c56aa3c223109a5c2e7eb` |
| `tools/tool_helpers.h` | 8199 | `1f8a1f40d48371fe8121a3566a756d1489bed9e216f693695ba24a9c132cdd42` |
| `tools/tool_helpers.cpp` | 9943 | `7f51226dfa8dd768509e52a89e924aea80276de162bbb92db647d41fd2edf7c8` |
| `tools/project_write_resource_scene.cpp` | 27926 | `a179ea46d2fabe68c3d5761823cad3d296ea3b49a63c494fd0a8d9dd91d1b6fd` |
| `tools/editor_write_scene_editor.h` | 4858 | `4e164869f96c41fdc0d63833d2c4970f2bafcb206644a81a0dd936deeeb7dcc1` |
| `tools/editor_write_scene_editor.cpp` | 49327 | `cd765e224867ca209538e032761c6ae7d3dd86fbb270ce631cc3e9638a8a39ee` |
| `tools/registration.cpp` | 3038 | `8957e0d5c31cb51d1d4615198a40af1c73cec4dbd7c52f56b3a73c8af716e947` |
| `tests/test_mcp_server.h` | 184848 | `85214dd8e261dc83c72562695ca7d7ea034eb9092378bde2070ca9d841060aa5` |
| `scripts/mcp008_editor_write_evidence.ps1` | 41734 | `770f67648a028c5ff0b3e322c7758e1fd8e9a9390f8412f7f59b6d221e3a3951` |
| `scripts/accept_m1.ps1` | 59486 | `7184a7afd74db77f5175bb008a73d633983b5d8cef45316a5575e0ef96909122` |
| `scripts/check_contract_subset.ps1`（**未改**） | 23074 | `b2fd8cdbcb9724caa9c0161fde25d38cd176112c171e82c87d21e05be2f952ce` |
| `scripts/mcp007_write_evidence.ps1`（**未改**，等价性证据的驱动） | 17932 | `ecc44655875ae57a56fb5c38a39801f0fc873a35e41da82adaef25cdc3733aff` |

引擎二进制（所有门与证据的对象）：`bin/godot.windows.editor.x86_64.console.exe` 300544 bytes
sha256 `557a31dac29a58c4bd59239350e1c4a65d1292c7634445df7adb03a34b881ce3`。

## 10. 缺陷 / 纠错记录（含环境发现）

1. **`build-m0.cmd` 构建出的二进制不支持 `--test`**（环境发现，非本组缺陷）：该脚本是 M0 基线包装，
   `env["tests"]` 默认 `False`（`SConstruct:254`，只有 `dev_mode=yes` 才默认打开），本次首轮用它构建后
   `--headless --test` 直接
   `ERROR: --test was specified on the command line, but this Godot binary was compiled without support for unit tests. Aborting.`
   （`main/main.cpp:940`）。门③④的正确构建命令是
   `scons platform=windows target=editor module_mono_enabled=no tests=yes -j8`。**未改** `build-m0.cmd`
   （它是开工前既有的未跟踪物，且不是本任务范围）。
2. **改了 `tests/test_mcp_server.h` 后 SCons 不会重编测试 TU**（环境发现）：该头由
   `modules/modules_tests.gen.h`（`env.CommandNoCache`，`modules/SCsub:55`）间接包含进
   `tests/test_main.cpp`，实测仅改头文件时 `test_main.cpp` 与
   `bin/obj/modules/mcp_server/tests/test_mcp_server.obj` 都**不**重建，二进制里仍是旧用例。
   规避：改动该头后删除这两个 obj 再构建。首轮漏做，因此一度在**没有新用例**的二进制上跑门——
   已重做，§3/§4 的数据都是含新用例的构建。
3. **`ClassDB` 在本 fork 没有 singleton accessor**：初版按迁移源写 `ClassDB::get_singleton()`
   导致 `error C2039: "get_singleton": 不是 "ClassDB" 的成员`。改为全静态调用
   （`class_exists` / `is_parent_class` / `can_instantiate` / `instantiate`，
   `core/object/class_db.h:318-327`），并拆成三条互不相同的 `-32602` 消息。
4. **`editor_set_viewport_3d_camera` 的 `fov` 会被编辑器回写**（实测，见 §7.4）：不是本实现的
   缺陷，但与「操作前后必须一致」的直觉相反，故显式记录，并让证据链断言**位置**、把 `fov` 作为
   「工具响应即时回读 + 编辑器随后回写」的两段事实分别列出。若决策者认为这不满足
   TASK-008 §4.2，需要的是在**编辑器**里增加可达的 fov setter，属引擎侧改动、超出本模块范围。
5. **headless 下 `editor_capture_screenshot` 必然失败**：dummy rendering driver 让
   `ViewportTexture::get_image()` 返回空图。这不是缺陷也不允许假成功，于是成功类被放到
   真实窗口 phase（`-Phase gui`，512×384、位置固定），headless 下如实 `-32603`。
   本次实测到真实 3840×2054 视口图像（1424105 bytes PNG）。
6. **`editor_get_output_log` 在编辑器持有 `--log-file` 时读不了自己的日志文件**（既有行为，
   见 §5.5）：`FileAccess::exists` 为真、`FileAccess::open` 失败。属于 TASK-006 的读工具，
   本任务未修改，仅作为观察记录。

## 11. deviations（与手册 / 任务书的偏离，逐条显式列出）

1. **`editor_reload_plugin` 的语义被重构**（§2、§5.4）。迁移源对硬编码名 `godot_mcp` 做
   disable+enable；本 fork 的 MCP 是**内置模块**（`register_types.cpp` 只 `GDREGISTER_CLASS(MCPServer)`，
   没有任何 EditorPlugin / addon），照抄等于操作一个不存在的插件再谎报 `reloading:true`——正是
   TASK-008 §2(c) 禁止的假成功。故保留机制、把作用对象改为 `editor_plugins/enabled` 里真实存在的
   addon；列表为空 → `-32000`+suggestion。返回键仍含迁移源的 `reloading`/`message`，`message` 改为
   与行为相符的中文说明，并新增 `plugins` 数组作为「到底重载了什么」的可核对证据。
   **若决策者要求逐字复刻迁移源（含谎报），需在 M2 裁决**。
2. **`editor_open_scene` 增加载入后回读校验**（§2）：迁移源无条件 `opened:true`。收紧为
   「文件在但编辑器没打开它 → `-32001` + suggestion」。
3. **`editor_add_resource_to_node_property` 的值转换是局部副本**（§2 末）：`tool_helpers.*` 上提的
   范围由 TASK-008 §3 限定为原子发布助手，而 `_property_value_from_json` / `_coerce_to_property_type`
   是 `project_write_resource_scene.cpp` 的**文件私有**函数；PLAYBOOK §2.4「不得改别组文件」，
   因此只在本组文件里写了它需要的那一子集（无 `HashSet` 属性名枚举、无 `changed` 报告）。
   两份实现的**分歧点**：本组多了 `can_instantiate` 检查（第三条 `-32602` 消息），因为它要区分
   「类不存在 / 不是 Resource / 是 Resource 但抽象」。**这是候选的第二次上提**，见 §13。
4. **`_require_editor_ui` 守卫在本组文件里是第二份拷贝**：与
   `editor_read_scene_inspector.cpp` 的同名函数逻辑逐字相同。理由同上（不得改别组文件）；
   TASK-008 §3 只授权上提原子发布助手。**同样列为候选上提**。
5. **`editor_save_scene` 用 `PackedScene::pack` + `ResourceSaver::save` 而非
   `EditorInterface::save_scene_as`**（§2）：后者写进目标路径并**重指向编辑场景**，无法在被重定向到
   临时文件后保持编辑器状态正确。因此编辑器保存流水线的额外副作用（`_save_editor_states`、
   `apply_changes_in_editors`、external resources、folding、`NOTIFICATION_EDITOR_PRE/POST_SAVE`）
   **未复刻**；复刻的是：pack 出来的场景内容、`FLAG_REPLACE_SUBRESOURCE_PATHS` 标志、成功后的
   `set_scene_file_path` 与 `EditorData::set_scene_as_saved`。工具的可观察契约（磁盘上的 `.tscn` +
   `{"saved":true,"path":…}`）完整保留，且**失败不破坏原文件**有反例证据。
6. **`editor_capture_screenshot` 的写盘失败改为错误**（§2）：迁移源吞掉失败仍回成功态。
   这是把 TASK-008 §2(c) 的规则应用到本组第二个文件写入者。
7. **驱动脚本新增一个 `redclear` phase 与两个测量字段**（§3.1、§3.2）：红构建 = 迁移源逐字行为
   **+** 一个只读测量仪器（定位 `EditorLog` 的 `RichTextLabel`）。加仪器是必要的——不然
   「面板其实没清」在线上**无法被观测**，而那正是迁移源能长期说谎的结构性原因。绿构建的
   `log_was_empty`/`log_is_empty` 是同一仪器的正式版。
8. **本组新增 `scripts/mcp008_editor_write_evidence.ps1`**（675 行）：手册没有规定门②驱动的落点，
   TASK-007 的先例是 `scripts/mcp007_write_evidence.ps1`，故沿用同一约定。
9. **`docs/DESIGN-DETAIL.md` 本轮未改**：本任务没有产生需要写进规范的新裁决（`-32001` 用于
   「存在但载入不了」、条件写按 `mutating=true` 记，都已在 REPORT-007 与 GDR-18 里）。
   规范由决策者维护，实现者只写本报告（PLAYBOOK §7.2）。

## 12. blockers

无。五道门在冻结态 `7292af5930` 上跑完，退出码均为 0；证据 phase `main`/`gui`/`noplugin`/`gamecall`
在**同一个冻结二进制**上重跑一遍，65/65 全过。端口纪律：全程只用 9888/9889，用户编辑器
（9877，PID 36392）在每个 phase 里都有 `pid_before == pid_after == 36392` 的正向守卫且全部 PASS；
所有测试进程均自起自停（收尾核对每个 phase 的 own_port_released 均 PASS）。未 push；
工作树除开工前既有的 4 个未跟踪物外干净。

## 13. next_step_recommendation

1. **B1 只剩一组**：`running_game_read_scene`（1 个 `scope=game` 工具
   `running_game_find_nearby_nodes`）。它落地后门①的「game-only 在**编辑器**端点必须缺席」方向
   第一次有真实对象（目前 17 条 editor-only 已有真实对象，game-only 仍是 0）。
2. **第二次上提的候选**（本组留下的两份拷贝，建议在下一个有写工具/编辑器工具的组之前做）：
   `_require_editor_ui`（`editor_read_scene_inspector.cpp` 与本组各一份）与
   `_property_value_from_json`/`_coerce_to_property_type`（本组与
   `project_write_resource_scene.cpp` 各一份）。上提需要同时改两个既有组文件，
   按 PLAYBOOK §17.1 应在**单独一批**里做，并用与 §6 相同的线上字节等价证明收口。
3. **`editor_set_viewport_3d_camera` 的 `fov` 不可持久**（§7.4）需要在引擎侧（
   `Node3DEditor` / `Node3DEditorViewport`）提供一个可达的 fov setter 才能修；
   属 `editor/**` 的改动，超出「只允许改 `modules/mcp_server/**`」的本任务边界，
   建议由决策者决定是否开一个引擎侧任务。
4. **`find_signal_connections` 的 `_meta.overrides` 理由仍带旧事实**（REPORT-007 §13.2 的遗留项），
   与 TASK-008 无关，仍未处理。
5. **`build-m0.cmd` 不含 `tests=yes`**（§10.1）：任何要跑门③④的批次都必须用显式
   `tests=yes` 的 scons 行，或把该包装脚本补上；这属于仓库工具，建议决策者裁决后落到规范里。
