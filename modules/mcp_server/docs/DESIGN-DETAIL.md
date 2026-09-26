# DESIGN-DETAIL — Godot 内置 MCP 模块（可实施粒度）

上游：`REQUIREMENTS.md`、`DESIGN-OVERVIEW.md`、hof-rs `DECISIONS.md` D30。
本文件是给**没有上下文的实现者**看的：照着它实现，不需要再做设计决策。规范条款编号用 **GDR-n**（与 hof-rs 的 DR-n 区分）。

基线：fork `57277407`（`4.8.0.dev`）。构建工具链：SCons 4.11.1 / Python 3.9.7 / MSVC 14.42.34433 / WinSDK 10.0.26100.0。
权威契约源：hof-rs 仓库 `tests/fixtures/mcp/tools_list.json`（174 工具的 name/description/inputSchema）。

---

## 1. 模块文件布局（GDR-1）

```
modules/mcp_server/
  config.py                  can_build / configure
  SCsub                      env_modules 克隆 + editor 子目录条件编译
  register_types.h
  register_types.cpp         SCENE 级注册单例；EDITOR 级（可选）注册 EditorPlugin
  mcp_server.h / .cpp        MCPServer : Node —— 生命周期、端口解析、逐帧泵、能力门
  mcp_http_server.h / .cpp   TCPServer 上的 HTTP/1.1 子集
  mcp_jsonrpc.h / .cpp       JSON-RPC 2.0 分发与信封（逐字对齐参考实现）
  tool_registry.h / .cpp     ToolDef 表 + scope 过滤 + 调用 + 结构化工具错误（GDR-19）
  tools/tool_builder.h/.cpp  工具编写助手：ToolBuilder / 参数校验 / 结果封装 / 磁盘助手 / editor 守卫（GDR-19）
  tools/registration.h/.cpp  register_all_tools()：共享注册入口，每组一行调用（GDR-19）
  tools/project_read_template.h/.cpp  B1 组 project_read_template（6 个工具，见 docs/tool-groups.json）
  tools/<group>.h / .cpp     其余 B1 组按 docs/tool-groups.json 并行加入（每组只拥有自己的文件 + 一行注册）
  tools/scene.cpp  tools/editor.cpp  tools/script.cpp  tools/resource.cpp  tools/analysis.cpp   （M2+ 逐步加入）
  tools/runtime.cpp  tools/input.cpp  tools/monitor.cpp  tools/evidence.cpp                  （B2）
  tools/node.cpp  ...                                                                          （B3+）
  editor/mcp_editor_plugin.h / .cpp   （可选，O1：先不做）
```

**除 `modules/mcp_server/**` 外不得修改任何引擎文件**（REQUIREMENTS C5）。文件必须带 Godot 风格 MIT 许可头。

## 2. 构建系统（GDR-2）

`config.py`：

```python
def can_build(env, platform):
    return platform == "windows"          # v1 只支持 Windows（REQUIREMENTS 假设）
def configure(env):
    pass
```

`SCsub`（照 `modules/gltf/SCsub` 模式）：

```python
Import("env")
Import("env_modules")
env_mcp = env_modules.Clone()
env_mcp.add_source_files(env.modules_sources, "*.cpp")
env_mcp.add_source_files(env.modules_sources, "tools/*.cpp")
if env.editor_build:
    env_mcp.add_source_files(env.modules_sources, "editor/*.cpp")
```

构建命令（M1 非 mono；M3 起用 mono）：

```
D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=no -j8
```

关闭模块用 `module_mcp_server_enabled=no`（Godot 对可构建模块自动生成该开关）。

## 3. 生命周期与线程模型（GDR-3）

- `MCPServer : public Node`，`static MCPServer *singleton`，`static MCPServer *get_singleton()`。
- 在 `MODULE_INITIALIZATION_LEVEL_SCENE` 阶段：`GDREGISTER_CLASS(MCPServer)` + `Engine::get_singleton()->register_singleton("MCPServer", instance)`。
- **逐帧泵的启动**：SCENE 级初始化时 `SceneTree` 尚未创建，因此用 `MessageQueue` 推迟挂载：
  `MessageQueue::get_singleton()->push_callable(callable_mp(instance, &MCPServer::_bootstrap));`
  `_bootstrap()` 里若 `SceneTree::get_singleton()` 与 `get_root()` 已就绪，则 `get_tree()->get_root()->add_child(this)`，
  此后由 `_process(double)` 承担泵；未就绪则再次推迟（最多 600 次，之后报错并禁用）。
  **编辑器与游戏两种进程都必须走通这条路径**（编辑器的 `SceneTree` 同样存在）。
- `_process()` 每帧：①`mcp_http_server->poll()` 收取并解析请求；②对可立即完成的请求同步执行工具并写回**发起该请求的连接**；
  ③每帧最多处理 `mcp_server.max_requests_per_frame`（默认 8）条请求，其余留到下一帧。
- **全程主线程**：不得创建线程、不得跨线程读写 Godot 对象（REQUIREMENTS C2）。
- **禁止 FIFO 配对**（REQUIREMENTS C3）：响应只能写回 `Connection` 自身持有的发送缓冲；**不得**存在任何「按到达顺序取响应」的共享队列。参考实现 `mcp/transport_http.rs` 的 `pending_responses.try_recv()` 是**反面教材**（D24 已定位为错位根因）。
- 退出：`NOTIFICATION_PREDELETE` / `_exit_tree()` 中 `mcp_http_server->stop()`；`uninitialize_mcp_server_module` 注销单例。

## 4. 端口解析（GDR-4）

优先级：①`OS::get_singleton()->get_cmdline_args()` 中的 `--mcp-port=N` 或 `--mcp-port N`；
②`ProjectSettings` 的 `godot_mcp/port`（整数）；③默认值：`Engine::is_editor_hint() ? 9877 : 0`（**0 表示游戏进程不监听**）。

- 游戏进程**必须显式** `--mcp-port` 或把 `godot_mcp/enabled_in_game=true` 才会监听（REQUIREMENTS C4）。
- 仅绑定 `127.0.0.1`（不得 `*`）。
- 端口占用：绑定失败**不得崩溃**，写 `WARNING` 到 stdout（`[MCP] bind failed ...`）并禁用服务；`get_port()` 返回 0。

## 5. HTTP 层（GDR-5）

在 `TCPServer` + `StreamPeerTCP` 上实现 HTTP/1.1 子集（引擎无 HTTP 服务端）：

| 项 | 规范 |
|---|---|
| 监听 | `TCPServer::listen(port, IPAddress("127.0.0.1"))`；每帧 `is_connection_available()` → `take_connection()` |
| 连接上限 | 同时保留最多 16 条；超出直接关闭新连接 |
| 读 | 非阻塞：`poll()` → 若状态为 `STATUS_CONNECTED`，`get_available_bytes()` → `get_partial_data(buf, n, received)` |
| 请求行 | `POST /mcp HTTP/1.1`；`GET /mcp` 返回 200 + 状态 JSON（连通性探活）；其它路径 404；其它方法 405 |
| 头部 | 解析 `Content-Length`（必需）；`Connection: close` 支持；大小写不敏感；单头行长上限 8 KiB |
| body 上限 | `mcp_server.max_body_bytes`（默认 8 MiB）→ 超出返回 **413** 并关闭连接 |
| 响应 | `HTTP/1.1 <code> <reason>\r\nContent-Type: application/json\r\nContent-Length: <n>\r\nAccess-Control-Allow-Origin: *\r\nConnection: keep-alive|close\r\n\r\n<body>` |
| 写 | `put_partial_data` 循环直到写完；写不完则把剩余放连接发送缓冲，下一帧继续 |
| keep-alive | 默认保持；空闲超过 `mcp_server.connection_idle_seconds`（默认 30s）关闭；客户端 `Connection: close` 时响应后关闭 |
| 必测反例 | 非法请求行、缺 `Content-Length`、超长 body、半包（分两次写请求）、同连接连续两个请求 |

## 6. JSON-RPC 层（GDR-6）—— 必须与参考实现逐字对齐

请求信封：`{"jsonrpc":"2.0","id":<any>,"method":"<m>","params":{...}}`；`id` 允许 string/number/null，**必须原样回带**。

| method | result 形状（逐字） |
|---|---|
| `initialize` | `{"protocolVersion":"2025-03-26","capabilities":{"tools":{"listChanged":false},"logging":{}},"serverInfo":{"name":"godot-mcp-rs","version":"0.1.0"}}` |
| `notifications/initialized` | **空 body**（HTTP 202、`Content-Length: 0`，不写 JSON） |
| `tools/list` | `{"tools":[{"name":<s>,"description":<s>,"inputSchema":<obj>}, ...]}`，按 `scope` 过滤 |
| `tools/call` | 成功：`{"content":[{"type":"text","text":"<工具结果的 JSON 字符串>"}]}`；若工具结果对象已有 `console_output` 增量则并入该对象（编辑器侧可选能力，见 GDR-8） |
| `ping` | `{}` |
| 未知 method | 错误 `-32601` |
| 非法 JSON | 错误 `-32700`，`id` 为 `null` |
| 非对象请求 / 缺 method | 错误 `-32600` |
| `tools/call` 缺 `name` 或参数类型错 | 错误 `-32602` |

错误对象：`{"code":<i>,"message":<s>[,"data":<obj>]}`；参考实现的 code/message 约定：
`-32700 "Parse error"` / `-32600 "Invalid request: <detail>"` / `-32601 "Method not found: <method>"` /
`-32602 "<原始原因，不加前缀>"` / `-32603 "Internal error: <detail>"` /
`-32000 "No scene is currently open"` + `data.suggestion` / `-32001 "<what> not found"` + `data.suggestion`。

**`tools/call` 的失败语义**（必须与参考实现一致）：工具返回引擎/编辑器错误时，若存在 `console_output` 增量 →
返回**成功形状**的响应，其 `content[0].text` 是 `{"error":<message>,"code":<code>,"console_output":[...]}` 的 JSON 字符串；
否则返回 JSON-RPC 错误对象。

**JSON 实现注意**：使用 `JSON::parse_string` / `JSON::stringify`，`stringify` 用默认 `sort_keys=true`（与参考实现的
serde_json 默认 BTreeMap 有序键一致）。**对等门比较的是解析后的结构**，不是原始字节（键序/空白不保证一致）；但
`inputSchema` 内的键名（如 `inputSchema`、`type`、`properties`、`required`、`default`）必须逐字一致。

## 7. 工具注册表与可见性（GDR-7）

```cpp
enum class MCPToolScope { EDITOR, GAME, BOTH };
struct MCPToolDef {
    StringName name;
    String channel;               // GDR-16：与 name 的通道前缀一致
    String verb;                  // GDR-16：闭集动词
    String description;
    Dictionary input_schema;      // 逐字来自 docs/tools_list.renamed.json
    MCPToolScope scope;
    bool mutating;                // GDR-18：最保守的读写分类（条件写也记 true）
    Variant (*handler)(const Dictionary &p_args, MCPToolError &r_error);  // 返回 Variant 结果或置错误
};
// MCPToolError 携带 code/message/data：-32602 参数、-32001 资源缺失、-32000 状态缺失（GDR-14）。
// 工具不要用裸 String 报错，而是用 MCPTools::ToolBuilder + 助手构造（见 §17 / GDR-19）。
```

- 注册表 `HashMap<StringName, ToolDef>`；`tools/list` 只返回**已实现且 scope 与当前进程匹配**的工具
  （编辑器进程：`Editor|Both`；游戏进程：`Game|Both`）。
- **未移植的工具不出现在 `tools/list` 中**（不得出现却返回 not_implemented，避免误导客户端）。
- 工具执行异常/错误一律走 GDR-6 的失败语义；不得让异常逃逸到崩溃。
- 与 hof-rs 的角色权限无关：模块不做角色概念（权限仍在 hof-rs `tools::policy`）。

## 8. `console_output`（GDR-8，可选能力）

参考实现每次 `tools/call` 后读取编辑器 Output 面板并附上增量。模块 v1 **不实现**该能力，理由：需要 `EditorPlugin`/编辑器日志钩子，
且 hof-rs 不依赖它。**必须在 `tools/list` 之外以文档与 `known_deviations` 显式声明**，并在对等门的偏差清单中登记
（属「字段缺失」而非「工具缺失」）。若后续需要，作为独立 GDR 追加。

## 9. M1 交付物（精确范围）

**必须交付**：

1. §1 布局中除 `editor/**` 与 `tools/{scene,editor,script,resource,analysis,runtime,input,monitor,evidence,node,...}.cpp` 之外的全部文件；
2. `tools/project.cpp` 实现**恰好 2 个**工具：`get_project_info`、`get_project_settings`（`scope=Both`），
   `inputSchema` 与描述**逐字**取自 `tools_list.json`；
3. 参考实现同款的端口解析、HTTP 子集、JSON-RPC 信封、`tools/list` 过滤、并发安全（同一进程内单帧串行、跨连接互不串扰）；
4. 逐帧泵的**可观测证据**：暴露 `get_frame_count()`（诊断用，不进 `tools/list`）。

**不在 M1**：任何写操作工具、任何游戏侧运行/输入工具、mono 相关、EditorPlugin。

**M1 验收脚本**（验收方必须自己跑，不得只读代码；`curl.exe` 为 Windows 自带）：

| 用例 | 期望 |
|---|---|
| `GET http://127.0.0.1:9877/mcp` | 200 + 状态 JSON（含 `tools` 计数、`port`、`is_editor`） |
| `POST initialize` | `protocolVersion == "2025-03-26"`，`serverInfo.name == "godot-mcp-rs"` |
| `POST tools/list` | 恰好 2 个工具，name/description/inputSchema 与权威清单**解析后结构相等** |
| `POST tools/call get_project_info` | `content[0].text` 可解析为 JSON，且含工程名等字段 |
| `POST tools/call get_project_info`（缺参/非法类型） | `-32602` |
| `POST 未知 method` | `-32601`，message = `Method not found: <m>` |
| `POST 非法 JSON` | `-32700`，`id=null` |
| **并发 100 请求（id=1..100）** | **每个响应的 `id` 与其请求一致**（G4；这是本里程碑的关键门） |
| 同连接连续两个请求（keep-alive） | 两条响应都正确且 id 各自匹配 |
| 半包请求（分两次写） | 正确拼接解析 |
| body 超过 `max_body_bytes` | 413 且连接关闭 |
| 游戏进程：`<binary> --path <测试工程> --mcp-port=9878 --headless` | `tools/list` 在 9878 上返回同一份 2 工具；证明**同一份代码在游戏进程内可用** |
| 游戏进程不带 `--mcp-port` | **不监听**（9878 连接被拒） |
| 端口占用（先用别的进程占住 9877） | 引擎不崩溃，记录 WARNING，`get_port()==0` |

## 10. 工具移植批次（GDR-9）

批次表给出**覆盖规则**与 **B1/B2 的精确清单**；B3–B5 按语义分类，每批开工前由实现者产出该批工具清单并经决策者确认后冻结。

**B1（工程/场景只读/编辑器/脚本只读/资源/分析）— 42 个**：
`get_project_info` `get_project_settings` `get_project_statistics` `get_filesystem_tree` `search_files` `search_in_files`
`open_scene` `create_scene` `delete_scene` `save_scene` `get_scene_file_content` `get_scene_tree` `get_scene_dependencies` `get_scene_exports`
`reload_project` `get_editor_errors` `get_output_log` `clear_output` `get_open_scripts` `get_editor_selection` `select_nodes`
`clear_editor_selection` `get_editor_camera` `set_editor_camera` `get_editor_screenshot` `get_editor_performance` `reload_plugin`
`list_scripts` `read_script` `validate_script`
`read_resource` `create_resource` `edit_resource` `add_resource` `get_resource_preview`
`find_unused_resources` `detect_circular_dependencies` `find_node_references` `find_script_references` `analyze_scene_complexity`
`analyze_signal_flow` `find_nearby_nodes`

**B2（游戏进程运行时 + 输入 + 证据）— 25 个**（**E3 解锁点**）：
`play_scene` `stop_scene` `get_game_scene_tree` `get_game_node_properties` `set_game_node_property` `monitor_properties`
`capture_frames` `get_game_screenshot` `execute_game_script`
`simulate_action` `simulate_key` `simulate_mouse_click` `simulate_mouse_move` `simulate_sequence` `get_input_actions` `set_input_action`
`start_recording` `stop_recording` `replay_recording`
`wait_for_node` `click_button_by_text` `find_ui_elements` `get_autoload` `batch_get_properties` `find_nodes_by_script`

**B3**：节点/脚本/资源**写**操作（`add_node` `delete_node` `duplicate_node` `rename_node` `move_node` `update_property`
`batch_set_property` `set_node_groups` `connect_signal` `disconnect_signal` `create_script` `edit_script` `attach_script`
`add_scene_instance` `add_raycast` `add_mesh_instance` `add_gridmap` `setup_*` `set_project_setting` `add_autoload` `remove_autoload` …）
**B4**：测试与断言（`assert_node_state` `assert_screen_text` `run_test_scenario` `run_stress_test` `get_test_report`
`compare_screenshots` `watch_signals` `monitor_properties` 的批量形态 …）
**B5**：其余分类（animation / animation_tree / audio / theme / tilemap / particle / navigation / physics / scene_3d / shader / export / android / profiling）

**每批对等门**（缺一不可）：①`tools/list` 与该批清单解析后结构相等（偏差须列入显式清单）；
②固定 golden 调用序列在同一测试工程上的结果形状一致；③hof-rs 离线测试零回归；④每工具三类证据（成功/缺参/底层失败）。

## 11. C#/mono 相关（GDR-10，M3）

- 构建：`scons platform=windows target=editor module_mono_enabled=yes -j8`，另需 `--generate-mono-glue` 与
  GodotSharp/GodotTools 的 `dotnet build`；模块本身**不依赖 mono**（C++ 与 mono 正交）。
- 工程侧：`.csproj` 由引擎生成，目标框架 `net8.0`；hof-rs 的 `A₀` 脚手架需包含 `.csproj` 与 `.sln`（若引擎要求）。
- 影响 hof-rs：`PRD-mario.md` 增加 **P7**（全部游戏逻辑用 C#）、**P8**（C# 编译零错误）；
  `skills/godot-dev.md` 重写为 C# 版；Tester 的编译证据 = `dotnet build` 输出 + `get_editor_errors`；
  `hoh doctor` 增加「引擎是否 mono / dotnet 可用性」预检。**这些必须显式回到 hof-rs 阶段一更新**（REQUIREMENTS O3）。

## 12. hof-rs 集成契约（GDR-11，M5）

- 新增 `tools.game_endpoint`（默认 `http://127.0.0.1:9878/mcp`）；`tools.endpoint` 语义不变（编辑器端）。
- **Runtime 拥有游戏进程**：启动 `<engine binary> --path <workspace> --mcp-port=<p> [scene]`，捕获 stdout，
  超时/结束即 kill 并回收，退出码与输出落盘。**不再依赖 addon 的 `execute_game_script` 转发。**
- 电池步骤的端点归属：`input_replay` / `monitor_properties` / `capture_frames` / `get_game_scene_tree` → **game endpoint**；
  `open_scene` / `get_scene_file_content` / `scene_structure` / `editor_errors_baseline` → **editor endpoint**。
- DR-35 的「游戏进程内通道」由 `ACTION_BINDING_UNKNOWN` 兜底变为**真正可达**；三态语义与 `supports` 映射**不变**。
- 工具策略（`tools::policy`）：按端点各维护允许名单（默认拒绝），角色权限语义不变。

## 14. M1 独立验收后的修订（GDR-12..GDR-15）

上游：`ACCEPTANCE.md` 的 M1 节（独立验收 pass，含 D-1..D-8 与 U-1..U-5）。以下条款**规范性**，适用于 M2 起。

### GDR-12 HTTP 层四项收紧（产品行为三项微调 + 一项写入规范）

1. **413 后的关闭必须可被正向证明**（D-1）：`accept_m1.ps1` 的「连接已关闭」断言不得用「读超时」代替，
   必须**正向**证明——在同一 socket 上再发一条请求并要求**无响应**（或 `Receive` 返回 0 表示对端关闭）。
   产品行为不变（服务端确实会关；该问题纯属测试质量，但它是**可复制粘贴的假阴性制造器**，必须修掉，
   以免成为 M2..M5 验收脚本的模板）。
2. **`HEADER_TOO_LARGE` → 431**（D-4）：`ParseStatus::HEADER_TOO_LARGE` 必须映射到 **431 Request Header Fields Too Large**
   （`reason_phrase()` 里已有该字符串，当前是死代码），不再用 400。
3. **裸 LF 结束头部 → 400**（D-6）：HTTP/1.1 要求 CRLF，当前裸 LF 会让请求一直缓冲到 30 s 空闲回收（客户端静默 30 s）。
   明确回 **400** 并关闭。
4. **非法 UTF-8 请求体：宽松接受 + 写入规范**（D-5）：`String::utf8` 会把非法字节替换为 U+FFFD 而请求仍被接受；
   保留该**宽松**行为（客户端契约是 UTF-8，不为非法输入增加严格校验路径），但：
   ①本条写入规范作为**已知边界**；②解析时若检测到替换，写一条 `verbose` 警告并记录原始字节长度；
   ③后续若 JSON 解析失败，仍按 GDR-6 返回 `-32700`。
   同理 `id: true` 等非规范 id 类型**原样回显**（D-7），保留宽松并写入规范。

### GDR-13 契约源 fixture 必须重采为干净 UTF-8；对等门要求**逐字相等**

- 事实（独立复核两次）：`tests/fixtures/mcp/tools_list.json` 含 **UTF-8 BOM**，且 **174/174** 条非 ASCII 描述是
  「UTF-8 字节被按 Latin-1 读出再写成 UTF-8」的双重编码；当前对等门用「原始值或还原值任一命中」兜底。
- **后果**：兜底会**放行一个输出乱码的实现**，即该门**不能强制 description 一致**；影响 B1–B5 所有批次。
- 规定：**重采该 fixture**（从 9877 的 `tools/list` 取原始响应字节，以 UTF-8 正确写盘、不带 BOM），
  随后对等门**去掉兜底并改为逐字相等**。重采后必须跑 hof-rs 离线测试确认无回归；并在 `DECISIONS.md` 记录 fixture 的新 sha256。

### GDR-14 `tools/call` 的未知工具名错误码澄清

- 实测：`tools/call` 未知工具名 → `-32601 "Method not found: <name>"`；参照实现
  （`godot_mcp_gdext/src/commands/mod.rs:109`）对未知工具同样是 `method_not_found`。
- 规定：**采纳 `-32601`**（与参照实现一致），因此 **GDR-6 的表述需澄清**：
  `-32601` = 未知 JSON-RPC method **或**未知工具名；`-32001 "<what> not found" + data.suggestion` 专用于
  **工具内部找不到资源**（如 `no_scene`、节点/文件/资源不存在）。参照实现的 `-32001` 用法即此。

### GDR-15 合入门与突发延迟的表述重述

- 引擎 `SocketServer::MAX_PENDING_CONNECTIONS = 8`，因此 G4 的「并发 100」实测形态是
  **「≤8 条连接上的 100 条流水线请求」**（100 条同时连接会被 OS backlog 限制，未被覆盖）。
  §9 的用例措辞据此重述为「**100 条流水线请求（≤8 连接）零错位**」，并保留一条「单连接 8 条流水线按序返回」的用例。
- `mcp_server.max_requests_per_frame`（默认 8）是**全局每帧预算**：突发 N 条请求需要 `ceil(N/8)` 帧才能排空。
  **hof-rs 不得假设「一请求一帧」的延迟**；对电池步骤的顺序调用无影响（每次单条），但任何批量调用须按帧预算估计耗时。
- 是否把预算改为**每连接**预算属 M2 开工前的开放项（B2 的工具更重，可能受帧预算影响）。

---

## 15. 规范条款索引（续）

| 编号 | 内容 |
|---|---|
| GDR-12 | HTTP 四项收紧：413 关闭需正向证明 / HEADER_TOO_LARGE→431 / 裸 LF→400 / 非法 UTF-8 宽松但写入规范 |
| GDR-13 | fixture 重采为干净 UTF-8，对等门改为逐字相等（去掉兜底） |
| GDR-14 | 未知工具名 = `-32601`；`-32001` 专用于工具内部资源未找到 |
| GDR-15 | 合入门措辞重述（≤8 连接上 100 条流水线）；`max_requests_per_frame` 的帧预算影响与开放项 |
| GDR-16 | 命名规范 lint（注册期强制：通道前缀、verb 闭集、与映射表一致、禁 `update_`、长度不设上限） |
| GDR-17 | **合并只在无损时允许**；有损差异必须保留两个工具并给可区分名字（工具总数因此为 171） |
| GDR-18 | 条件写（可选 `save_path` 之类）一律按最保守语义记 `mutating=true` 并在 `reason` 写明触发条件 |
| GDR-19 | B1 框架：`tools/` 按组分文件 + `register_all_tools()` 单入口 + 工具编写助手（ToolBuilder/参数校验/结果封装/磁盘助手）+ 编辑器守卫 + 结构化工具错误（见 §17） |

## 16. 执行顺序修订：**引擎优先，hof-rs 暂停**（2026-09，用户指令）

原 §10 / DECISIONS D34 的 Phase 0–5 是为「hof-rs 在线、两侧工具名需**原子切换**」设计的。用户已下令
**「优先完成 godot 的 mcp 工具集成和测试，hoh 先暂停」**，因此顺序简化为：

1. **引擎内先立规矩**：`tool_registry.cpp` 实现命名 lint（GDR-16），并以 `docs/tool-rename-map.json` 为**唯一事实源**。
2. **生成重命名后的期望契约** `docs/tools_list.renamed.json`：由 `tool-rename-map.json` 机械变换旧契约得到
   （含 merge 项去重、2 个 `unregister_until_implemented` 项剔除）。**它是每批对等门的参照物，不依赖 hof-rs 运行时。**
3. **按批次移植 + 测试**：B1(42) → B2(25) → B3 → B4 → B5。每批四道门：
   ①`tools/list` 与期望契约**逐字相等**（name / description / inputSchema）；
   ②每个工具有**成功 / 缺参 / 底层失败**三类证据；③引擎 doctest 全绿；
   ④全引擎 `--test` 零回归。
4. **处置项必须落地（按 GDR-17/GDR-18 更新，v1.1 已落地）**：3 对 merge 中**2 对因有损而取消合并**、两者各自保留并给可区分名字
   （`editor_analyze_signal_flow` ⇄ `editor_list_signal_connections`；`project_search_file_contents` ⇄ `project_find_files_referencing_symbol`
   ——后者是 `tool-rename-map.json` v1.1 的最终名，`GDR-17` 初稿里的 `project_find_files_containing_pattern` 是占位名，见 `TASK-001` §2.2 / `D45`），
   仅 `editor_get_performance_monitors ⇐ editor_get_performance` 维持合并（真子集，`reason` 写明形状变更）；
   2 个 `unregister_until_implemented` **不移植**；7 个 `fix_implementation_first` **先修实现（写红测试）再注册**——
   其中 `editor_set_tilemap_cell` / `editor_set_tilemap_cells_in_rect` 会**擦除既有格子却报成功**（数据破坏），优先级最高。
   **工具总数 171**（174 − 2 下架 − 1 无损合并）。
5. **推迟到解除暂停之后**：hof-rs 侧授权判定改由表驱动（DECISIONS D41 的三层防御）与产品级 E1–E6 真实冒烟。
   **解除暂停前不得修改 hof-rs 的 policy/adapter。**

---

## 17. B1 框架落点（GDR-19，TASK-002 交付）

来源：TASK-002 §2.2。目的：让**后续每个并行移植子代理只拥有一个组文件 + 一行注册**，互不改共享文件。

### 17.1 注册分组

- 每组一对 `tools/<group>.h / .cpp`，导出 `void register_<group>_tools(MCPToolRegistry &r)`；
- 共享入口 `tools/registration.h / .cpp` 只有 `register_all_tools(MCPToolRegistry &r)`，其中**每组一行调用**
  （含该组头文件的一个 include）；`mcp_server.cpp` 只调用 `register_all_tools()`；
- 组清单与顺序的唯一事实源是 **`docs/tool-groups.json`**（B1 = 41 个工具 / 7 组，每组的 `channel` 与
  `mutating` 唯一，组内可放进同一文件且组间无共享文件）；`docs/scripts/check_tool_groups.py` 做机器校验
  （41 个恰好各出现一次、名称存在于契约、每组一个 channel + 一个 mutating 值、组 ≤10 个工具）。

### 17.2 工具编写助手（`tools/tool_builder.h`）

- `MCPTools::ToolBuilder`：`channel/verb/scope/mutating` **必须显式声明**，缺一即拒绝 build/注册
  （与 GDR-16 lint 对接；GDR-18 的 `mutating` 不再有隐式默认）；
- 参数校验：`require_string` / `require_int` / `optional_string` / `optional_int` / `optional_bool`，
  失败一律 `-32602` 且信息可读；`optional_*` 允许缺省，但**出现即必须类型正确**（静默忽略参数是误配置的来源）；
- 结果封装：`MCPTools::content_result(payload)` → `{"content":[{"type":"text","text":"<json>"}]}`，**唯一实现点**；
- 错误语义：`MCPToolError::invalid_params`(-32602) / `not_found`(-32001，带 `data.suggestion`) /
  `no_scene`、`not_implemented`(-32000，带 `data.suggestion`) / `internal`(-32603)；
  `MCPJsonRpc` 只负责把 `MCPToolError` 变成线上错误对象（GDR-6/GDR-14）；
- 磁盘/资源助手：`normalize_project_path`（只允许 `res://`、禁 `..` 与空段、折叠尾斜杠）、
  `open_project_dir`（不存在 → `-32001`）、`read_project_text_file`、`file_extension`。

### 17.3 编辑器 / 游戏双目标守卫

- **编译期**：编辑器专有 API 用模块别名 `MCP_EDITOR_TOOLS_ENABLED` 包住，该别名只在 Godot 的
  `TOOLS_ENABLED`（本 fork 中 `TOOL_ENABLED` 不存在）下被定义（`tools/tool_builder.h`）；
- **运行期**：`MCPTools::is_editor_process()`（`Engine::is_editor_hint()`）；`ToolBuilder::register_into()`
  在**游戏进程**中直接**不注册** `scope=EDITOR` 的工具，同时注册表按 scope 过滤 `tools/list` 与
  `tools/call`（GDR-7）；
- `project_get_info` 的 `editor_screen_size` 同时受上述两条约束：非 tools 构建里编辑器分支不存在，
  游戏进程里走 `SceneTree` 根视口回退。

---

## 13. 规范条款索引（GDR-1..GDR-11）

### GDR-16 命名规范 lint（注册期强制）

`tool_registry.cpp` 注册时必须校验（不合规即注册失败，构建期/启动期即可发现）：

- `name` 匹配 `^(editor|running_game|project|os)_[a-z0-9_]+$`；**通道前缀按最长匹配剥离**（`running_game_` 自带下划线，
  不能用 `split('_')[1]`）。
- 剥离后的首段（verb）∈ 闭集：`get list read find search create add remove delete set edit rename reparent move duplicate
  connect disconnect play stop run execute evaluate capture assert validate simulate export deploy reload rescan bake
  open save setup analyze detect convert`；**禁用 `update_`**。
- `channel` 与 `verb` 必须与 `docs/tool-rename-map.json` 中的声明一致（该表是唯一事实源）。
- 名字长度**不设上限**（判据是「不看文档只看名字即可确定 通道 + 动作 + 对象」）。

### GDR-17 合并（merge）只在**无损**时允许

来源：独立审计实测——原先 3 对合并里 **2 对不是「重复实现」而是不等价**：

| 对（保留方 ⇐ 被合并方） | 实测差异 | 裁决 |
|---|---|---|
| `editor_analyze_signal_flow` ⇐ `editor_list_signal_connections` | 返回形状（按节点嵌套 vs 扁平 `connections[]`）、非持久连接过滤（`flags & 1`）、编辑场景之外的 target、`node_path` 子串 vs 精确、`signal_name` 过滤 | **取消合并**，两者各自保留并给可区分名字 |
| `project_search_file_contents` ⇐ `project_find_files_referencing_symbol` | 输出形状（逐行 `{file,line,text}` vs 按文件聚合 `{file,lines[]}`）、上限 **50 vs 100**、**大小写不敏感 vs 敏感** | **取消合并**，两者各自保留 |
| `editor_get_performance_monitors` ⇐ `editor_get_performance` | 逐字段核验为**真子集**（8/8 字段可在保留方找到），仅形状由平铺改嵌套 | **维持合并**，`reason` 必须写明形状变更 |

规定：①合并前必须逐字段/逐形状/逐参数比对，**只有真子集或完全等价才算无损**；
②存在任何行为差异时**保留两个工具**并给可区分名字（诉求是**区分度**，不是工具数少，名字长不是约束）；
③维持合并者必须在 `reason` 写明「代价：形状/字段路径变更」。
④因此工具总数由 174 变为 **171**（174 − 2 下架 − 1 无损合并），`docs/tools_list.renamed.json` 与
`docs/TOOL-NAMING.md` 必须随之重生成。

### GDR-18 条件写（conditional write）一律按最保守语义记 `mutating=true`

凡「默认只读、但某参数可触发落盘/改动」的工具（如两个截图工具带可选 `save_path`，可写 `res://`），
**一律记 `mutating=true`**，并在 `reason` 写明触发条件。
理由：`tool-rename-map.json` 是策略生成的唯一事实源，任何「按参数才是写」的模糊语义都可能被消费者误读。

| 编号 | 内容 |
|---|---|
| GDR-1 | 模块文件布局；除 `modules/mcp_server/**` 外不得改引擎源码 |
| GDR-2 | `config.py`/`SCsub`/构建命令 |
| GDR-3 | 生命周期与线程模型：`Node` + `MessageQueue` 推迟挂载 + `_process` 泵 + **禁止 FIFO 配对** |
| GDR-4 | 端口解析优先级；游戏侧默认不监听；仅绑 127.0.0.1；占用不崩溃 |
| GDR-5 | HTTP/1.1 子集（status 码、上限、keep-alive、超时、反例清单） |
| GDR-6 | JSON-RPC 信封与错误码逐字对齐；`tools/call` 失败语义；JSON 键序说明 |
| GDR-7 | 工具注册表与 `scope` 可见性；未移植工具不出现 |
| GDR-8 | `console_output` v1 不实现，须显式登记偏差 |
| GDR-9 | 工具批次（B1=42/B2=25 精确清单）与每批对等门 |
| GDR-10 | mono/C# 构建与 hof-rs 需求变更 |
| GDR-11 | hof-rs 双端点契约与 Runtime 拥有游戏进程 |
