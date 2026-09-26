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
| GDR-22 | **统一收窄闸门**：「转换关系」与「槽位宽」分开判，槽位宽只有一处实现（`ValueSlot` + `value_fits_slot`）并覆盖**全部**写路径（含标量成员）；**标量 `INT` 成员宽度是显式诚实边界**；资源写入必须写后回读（见 §20） |
| GDR-23 | **参考源层级：引擎源码是第一参考源**；迁移源只提供「工具类别 + 大致用途」，**不是**行为预言机；与它不同是常态；**顺手性是验收条款**；怪癖不默认保留（见 §21） |
| GDR-24 | **收窄点必须显式标注且被机器检查**（TASK-023 D-7/D-15）：槽位判定覆盖**不经 `Object::set()` 的专用 setter 路径**；`FLOAT32`（`Color` 分量、`PackedFloat32Array` 元素）与 `REAL_T` 拆成两个槽位，前者**在任何构建配置下都按 32 位判**；全模块收窄点清单 + `scripts/check_narrowing_points.py`（门⑥，新增未标注收窄点即失败）（见 §22） |

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

## 19. GDR-21 输入通道边界（editor 输入 ≠ 游戏输入）

来源：E3 根因 + TASK-012 的双向线上证据（决策者裁决 D59）。

**这是本模块存在的首要理由之一，必须被视为硬性规范：**

1. `editor_*` 的输入类工具（`editor_simulate_input_action` / `editor_simulate_key` /
   `editor_simulate_mouse_*` / `editor_simulate_input_sequence` / `editor_add_input_action` /
   `editor_get_input_actions`）作用于**编辑器进程**的 `Input` / `InputMap` 单例。
   **它们永远不能用来驱动运行中的游戏**——这正是旧 GDExtension 架构下 E3 无法达成的根因
   （游戏是独立子进程，注入到编辑器的 `Input` 到不了游戏）。
2. **驱动运行中的游戏必须走 `scope=game` 的工具**，且这些工具**只在游戏端点（`--mcp-port` 指定的游戏端口）
   可见**；它们必须缺席于编辑器端点，反之亦然（双向缺席都有线上证据）。
3. 游戏子进程的端口来源：
   - 由 **harness/Runtime 自己启动游戏**时 → 传 `--mcp-port=N`；
   - 由**编辑器**（`editor_play_scene`）启动游戏时 → **编辑器不会转发 `--mcp-port`**
     （`editor_run.cpp` 的参数构造里没有端口），此时游戏的端口来自 `ProjectSettings: godot_mcp/port`。
   **模块不为「别人启动的游戏」发明端口**；写到规范里以免后续误判为缺陷。
4. 录制设施用**引擎内 C++ 子类覆写的 `Node::input()`**，**不能**用 `_input` GDVIRTUAL——
   后者只经 `ScriptInstance`/GDExtension 解析，引擎内的 C++ 子类**永远收不到**。
5. 录制必须有**长度上限**（事件数与总时长），达到上限时停止采集并在结果里报 `truncated: true`，
   不得无界增长内存。

## 18. GDR-20 延迟响应通道（deferred response channel）

来源：TASK-011（决策者裁决 D57）。**一请求一帧**模型无法实现跨帧工具（B2 的采样/等待/多帧捕获、
B4 的 `running_game_assert_*`/`run_test_scenario`/`watch_signals` 等）——最小证明：同一帧取 N 次样本得到 N 个相同的值。

规范条款：

1. **保持「无 FIFO」原则**：pending 请求按 **(连接, 请求 id)** 关联；响应**始终**写回发起它的那条连接。
   禁止全局 FIFO 或「按到达顺序配对」（与 GDR-3 同一条纪律）。
2. **状态机归框架**：处理器返回「已完成结果」或「pending 句柄（`tick()` → `Pending`/`Done`/`Failed`）」；
   逐帧推进由 `MCPHttpServer` 负责，工具实现保持简单。
3. **绝不阻塞主线程**（禁止 sleep/忙等）；每帧推进 pending 的**预算有上限**（默认 8），
   且**不得饿死常规请求**（有 pending 时 `ping` 仍须毫秒级作答）。
4. **超时**默认 30 s，以 **`-32000` + `data.suggestion` + `data.timeout_ms`** 收尾，**不得静默丢弃**；
   工具自报的超时只能**收紧**（`_effective_timeout = min(工具, 框架上限)`）。
5. **连接断开是唯一清理点**（`drop_connection()`）：该连接的 pending 必须全部释放、**不得泄漏**；
   `get_status_body()` 暴露 `pending` / `pending_connections` 供观测。
6. **帧时钟**用 `SceneTree::get_frame()`。
7. **跨帧持有的对象必须用 `ObjectID`**，不得跨帧持裸 `Node*`（悬垂指针）。
8. **每连接请求背压**：同一连接上必须保持 HTTP/1.1 的响应顺序（前一响应未发完不得发出后一响应）。
9. **空闲回收豁免**：有 pending 的连接**不得**被空闲超时回收（否则 30 s 空闲回收会抢在框架超时前斩断连接）。
10. **能力不满足时诚实拒绝**：`--headless` 的 dummy renderer 没有纹理存储
    （`get_texture().get_image()` 打 `ERROR: Parameter "t" is null.` 并返回 null）→ 捕获类工具
    **先判定 display server 能力**，不支持时返回 `-32000`+建议，**不得**把空白帧当成功；
    成功证据改在**窗口化进程**采集（两相证据结构：headless 判能力 / 窗口化取证据）。

## 17. B1 框架落点（GDR-19，TASK-002 交付；§17.1 串行纪律 / §17.2 唯一注册路径 / §17.4 顺序确定性为 TASK-003 补强）

来源：TASK-002 §2.2。目的：让**后续每个并行移植子代理只拥有一个组文件 + 一行注册**，互不改共享文件。

### 17.1 注册分组

- 每组一对 `tools/<group>.h / .cpp`，导出 `void register_<group>_tools(MCPToolRegistry &r)`；
- 共享入口 `tools/registration.h / .cpp` 只有 `register_all_tools(MCPToolRegistry &r)`，其中**每组一行调用**
  （含该组头文件的一个 include）；`mcp_server.cpp` 只调用 `register_all_tools()`；
- 组清单与顺序的唯一事实源是 **`docs/tool-groups.json`**（B1 = 41 个工具 / 7 组，每组的 `channel` 与
  `mutating` 唯一，组内可放进同一文件且组间无共享文件）；`docs/scripts/check_tool_groups.py` 做机器校验
  （41 个恰好各出现一次、名称存在于契约、每组一个 channel + 一个 mutating 值、组 ≤10 个工具）。

**串行纪律（TASK-003 §1.7，机制性建议②）**：`tools/registration.cpp` 是**所有组共写的同一处**——
「每组各加一行」听起来互不干扰，但它就是**同一个文件**。实测：把「两个实现者各自追加一行
（一个 include + 一个调用）」建模为三方合并（`git merge-file ours base theirs`，两个分支从同一基线出发），
**必然冲突**：`exit code 2`，**2 个冲突 hunk**（include 区、调用区各一），`<<<<<<<`/`=======`/`>>>>>>>`
各 2 行。因此：

- **同一批（同一个 merge 窗口）里只有一个实现者在改树**；并行只发生在**不同批**之间，不发生在同批内部；
- **注册行由该批实现者单独追加**（include + `register_<group>_tools(...)` 各一行）。任务书**不要**把
  「去 `registration.cpp` 加你自己的注册行」分派给多个并行子代理——那不是并行化，而是制造冲突；
- 追加顺序以 `docs/tool-groups.json` 为唯一事实源；`registration.cpp` 里的行序 = 该清单顺序
  （顺序本身不是契约，见 §17.4，但它必须稳定、可追加）。

### 17.2 工具编写助手（`tools/tool_builder.h`）

- **所有组必须经 `ToolBuilder` 注册（TASK-003 §1.6，机制性建议①）**：`MCPToolRegistry::register_tool()`
  是 **private**，`MCPTools::ToolBuilder` 是它**唯一的 friend**（`tool_registry.h`；`register_into()`
  是唯一的调用点 `tool_builder.cpp:143`）。于是裸 `MCPToolDef` 直接入库这条路**不存在**，
  以下三条无法被绕过：显式声明 `channel/verb/scope/mutating`（GDR-16/GDR-18）、命名 lint、
  以及「游戏进程里根本不注册 `scope=EDITOR` 的工具」（GDR-19 §17.3）。
  该不变式**不是注释**：`tests/test_mcp_server.h` 用编译期访问探针 + `static_assert` 把它钉死——
  `register_tool` 一旦变回 public，**测试二进制编译失败**；另有运行期用例
  `[MCPServer] register_tool is unreachable outside ToolBuilder`，同时断言 ToolBuilder 这条正路仍然工作、
  且仍拒绝（游戏进程里的 editor 工具 / lint 不合规的名字）。
  review 时的机械检查：`grep -rn "\.register_tool(" modules/mcp_server/tools/` 应**恰好只剩
  `tool_builder.cpp` 一处**；
- `MCPTools::ToolBuilder`：`channel/verb/scope/mutating` **必须显式声明**，缺一即拒绝 build/注册
  （与 GDR-16 lint 对接；GDR-18 的 `mutating` 不再有隐式默认）；
- 参数校验：`require_string` / `require_int` / `optional_string` / `optional_int` / `optional_bool`，
  失败一律 `-32602` 且信息可读；`optional_*` 允许缺省，但**出现即必须类型正确**（静默忽略参数是误配置的来源）；
- 结果封装：`MCPTools::content_result(payload)` → `{"content":[{"type":"text","text":"<json>"}]}`，**唯一实现点**；
- 错误语义：`MCPToolError::invalid_params`(-32602) / `not_found`(-32001，带 `data.suggestion`) /
  `no_scene`、`not_implemented`(-32000，带 `data.suggestion`) / `internal`(-32603)；
  `MCPJsonRpc` 只负责把 `MCPToolError` 变成线上错误对象（GDR-6/GDR-14）；
- 磁盘/资源助手：`normalize_project_path`（只允许 `res://`；禁 `..`——在**折叠之前**对原始剩余部分判定，
  折叠规则不得把已被拒的路径变回合法；折叠 `.` 段与空/仅空白段，并折叠尾斜杠，因此返回值是规范形态：
  `res://.` → `res://`、`res://src/.` → `res://src`、`res:// ` → `res://`、`res://a//b` → `res://a/b`）、
  `open_project_dir`（不存在 → `-32001`）、`read_project_text_file`、`file_extension`。

### 17.3 编辑器 / 游戏双目标守卫

- **编译期**：编辑器专有 API 用模块别名 `MCP_EDITOR_TOOLS_ENABLED` 包住，该别名只在 Godot 的
  `TOOLS_ENABLED`（本 fork 中 `TOOL_ENABLED` 不存在）下被定义（`tools/tool_builder.h`）；
- **运行期**：`MCPTools::is_editor_process()`（`Engine::is_editor_hint()`）；`ToolBuilder::register_into()`
  在**游戏进程**中直接**不注册** `scope=EDITOR` 的工具，同时注册表按 scope 过滤 `tools/list` 与
  `tools/call`（GDR-7）；
- `project_get_info` 的 `editor_screen_size` 同时受上述两条约束：非 tools 构建里编辑器分支不存在，
  游戏进程里走 `SceneTree` 根视口回退。
- **按端点推导期望工具集（TASK-006 §2，TASK-007 §2 写入规范）**：`scope` 决定端点可见性——
  `scope=editor` 的工具**只能**出现在编辑器端点（9888），`scope=game` 只能出现在游戏端点（9889），
  `scope=both` 两端都出现。`docs/tool-rename-map.json` 是 `scope` 的唯一事实源，因此
  `scripts/check_contract_subset.ps1` 与 `scripts/accept_m1.ps1` **按端点**推导期望集合并断言，而不是
  维护第二份手写清单：把「所有 `implemented=true` 组的并集」按 `scope` 分成三类——editor-only、
  game-only、both——**两端点都用同一套对称规则推导**：编辑器端点的期望集合是「全体 − game-only」，
  游戏端点是「全体 − editor-only」（`scope=both` 因此在两端都出现，两个端点各自排除的正是**只属
  于另一端**的工具）；已实现却属于
  另一端点的工具**缺席**是显式断言（`MUST be hidden on the <label> endpoint`），不是「没比对到就算过」，
  任一方向泄漏都判 FAIL。线上行为的另一半由此钉死：游戏端点上按名调用 editor-only 工具必须是
  `-32601`（`accept_m1.ps1` 的 `case12`），绝不是执行。注册表自己按 scope 过滤（GDR-7）是同一规则
  的进程内半边，doctest `[MCPServer] the editor_read_scene_inspector group is editor-only` 与
  `[MCPServer] the project_write_resource_scene tools are registered as mutating both-scope tools`
  分别钉住两个方向。

### 17.4 `tools/list` 的顺序与确定性（TASK-003 §1.1，裁决 D-1）

- **顺序不是契约**：`docs/tools_list.renamed.json` 的 `_meta.order_normative = false`
  （由 `scripts/gen_renamed_contract.py` 生成，v1.3 起；契约仍 171 条）。契约约束的是 `result.tools` 的
  **集合与内容**——名字、description、inputSchema 逐字（GDR-13 的对等门按名字逐个比较）——**不是顺序**。
  因此：**任何实现都不得为了对齐契约文件的顺序而重排注册**，顺序吻合与否**不构成门**
  （`accept_m1.ps1` 与 `check_contract_subset.ps1` 都把顺序只当证据打印，不做断言）。
- **引擎必须确定性**：同一次构建内，**连续两次 `tools/list` 必须逐字节相同**（同 id 请求的响应体
  byte-identical；两个独立构建出来的注册表也必须给出同样的字节）。实现依据：`MCPToolRegistry` 用
  **插入序**（`Vector<StringName> order`）生成清单，`HashMap` 的迭代序永远不出现在响应里。
- **回归护栏**：doctest `[MCPServer] tools/list is byte-identical across consecutive calls`
  （同注册表两次、两个独立注册表、同注册表换 id、游戏进程视角各一组断言）。

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

---

## 21. GDR-23 参考源层级：**引擎源码是第一参考源**（决策者指令，2026-09）

**背景**：本模块从 Rust GDExtension（迁移源 `godot_mcp_gdext` / `addons/godot_mcp_rs`）迁移而来。
早期把迁移源当作**行为预言机**，造成两类系统性代价：
①它的**缺陷**被当成规范（已实证 7 例，见 `PLAYBOOK` §6.6）；
②它的**怪癖**被照抄（如 `project_get_scene_dependencies` 的 `type` 恒为空串、
`editor_get_scene_tree` 的路径含**每次运行都变**的编辑器内部节点 id、
`Vector4`/packed 的读回形状是 `String` 而 `Vector2` 是对象）。

**规范（参考源层级；冲突时按此裁决）**：

1. **第一参考源 = 引擎源码**（本 fork 的 `core/**`、`scene/**`、`editor/**`）。
   「该能力对应引擎哪个 API」「一次调用能做到什么」「参数取什么形态最自然」
   「返回哪些字段才能被别的工具**链式喂回**」——**一律以引擎为准**。
2. **迁移源只回答两个问题**：**有哪些类别的工具**、**大致干什么**。
   它**不是**参数表/返回形状/错误语义的权威，**不得**作为「应该这样做」的论据。
3. **与迁移源不同是常态**：差异只需满足两点 —— ①有**引擎依据**；②在报告里**显式记录**。
   「与参照一致」**不是**优点；「照抄参照的怪癖」**是缺陷**。
4. **顺手性（ergonomics）是验收条款**：工具必须让调用方**一趟做完引擎一趟能做的事**；
   不得要求调用方用多步舞蹈换取引擎一次调用即可给出的结果；跨工具的输出→输入应**可直接喂回**。
   违反者按缺陷记录（minor 起），并附「引擎本来能做到什么」的证据。
5. **契约（`tools_list.renamed.json`）仍是名字/描述/参数 schema 的对等门**。
   若引擎依据表明**参数形态或 schema 应改变**，走**既有 override 机制**
   （`DESCRIPTION_OVERRIDES` / `SCHEMA_OVERRIDES`，理由入 `_meta.overrides`）并**重生成指纹**；
   **不得**绕过门、也不得手改契约文件。
6. **不保留无收益的怪癖**（对 `PLAYBOOK` §6.8 的修订）：怪癖**不再默认保留**；
   只有引擎本身只能给出该行为时才保留，并在报告里说明。

## 20. GDR-22 统一收窄闸门（写值「槽位宽」）

来源：M4b 第二次独立验收的 **D-4（high）**。**「槽位宽」这一类被漏了三次**：
①容器元素位宽（TASK-021 A-2）→ ②复合值的分量位宽（TASK-021 A-4）→ ③**标量 `real_t` 槽**（TASK-022 D-4）。
逐类打补丁的做法已被证明会继续漏，因此本条款把它定成**一条作用于「Variant → C++ 成员收窄」的统一规则**，
而不是再加一个分支。

「**一处**」的含义是**判定只有一份实现**：TASK-021 的元素闸门（`_element_fits_container`）与分量闸门
（`_component_fits_slot`）的内部实现已删除，改为调用同一条判定。

### 20.1 判据：转换关系与槽位宽**分开判**

写一个值进有类型的槽，依次过三关，缺一不可：

1. **转换关系**：`Variant::can_convert(来源类型, 目标类型)` 为假 → 拒绝（TASK-018）。理由：`type_convert`
   对未列出的对会走到 `Variant::operator <T>()` 的 `else` 分支，写的是默认构造的 `<T>`（实证：`1e20 → Vector2(0,0)`）。
2. **可解析性 / 有限性**：字符串必须**整体**拼出目标数值；`STRING→BOOL` 只接受命名布尔的拼写；
   `STRING→COLOR` 只接受引擎真读的两套语法；非有限数一律拒绝（TASK-020、TASK-021）。
3. **槽位宽**：值必须能**无损落进**它即将被拷入的 C++ 成员。**`can_convert` 为真不代表值能落进槽位**
   （实证：`300→44`、`-1→255`、`3e9` 截断、`1e300→inf`、`1e-300→0`）。

第 3 关只有一处实现：

```
MCPTools::value_fits_slot(value, ValueSlot, 参数名, 槽位描述, error)
```

由 `MCPTools::ValueSlot` 指名槽宽：

| `ValueSlot` | 代表的槽 | 判据（单精度构建） | 拒绝时报告「引擎实写值」 |
|---|---|---|---|
| `WIDE` | 与 Variant 类型同宽：`double` 成员、`int64_t` 成员、`PackedFloat64Array`/`PackedInt64Array` 元素、`ProjectSettings` 值 | 不判（恒通过） | — |
| `REAL_T` | `real_t`：标量成员、向量 / 颜色分量、`PackedFloat32Array` 元素 | `\|x\| > FLT_MAX`（→ `inf`）**或** `x != 0 && (float)x == 0`（→ `0`）即拒绝 | `inf` / `0` |
| `INT32` | `int32_t` | 越界即拒绝 | 低 32 位（如 `3000000000 → -1294967296`） |
| `UINT8` | `uint8_t` | 越界即拒绝 | 低 8 位（`300 → 44`、`-1 → 255`） |

`REAL_T` 在 `REAL_T_IS_DOUBLE` 构建下恒通过（槽本来就是 `double`）。拒绝消息必须同时给出：
**参数名（含分量/元素下标，如 `value.x`、`value[0]`）、槽位描述、引擎本会写入的值、可接受范围**。

### 20.2 落点：**任何写入之前**，且所有写路径复用同一处

唯一入口是 `coerce_to_property_type(value, target_type, out, error, 参数名, p_slot = FROM_TARGET_TYPE)`
（`tools/tool_helpers.{h,cpp}`）：类型转换成功之后、返回之前，按 `p_slot` 过第 3 关。

* **默认 `FROM_TARGET_TYPE` ＝属性成员规则**：`FLOAT` 目标经 `scalar_member_slot()` 映射为 `REAL_T`，
  其余为 `WIDE`。因此**所有**属性成员写路径自动获得该闸门，且都发生在 `Object::set()` **之前**：
  `running_game_set_node_property`、`editor_set_node_property`、`editor_set_node_property_batch`、
  `editor_add_nodes_batch`（三者经 `write_node_property` / `prepare_node_property_value`）、
  `project_set_node_property_across_scenes`（同一预校验，保持全成功 / 全回滚）、
  `project_create_resource`、`project_edit_resource`、`editor_add_resource_to_node_property`。
* **显式槽**（调用方自己声明存储形态）：
  * `project_set_setting` 传 `WIDE` —— `ProjectSettings` 以 **Variant** 存储（`set_setting` 直接放 Variant），
    不是有类型的 C++ 成员，按成员规则判会误拒本可存储的 `1e300`；
  * 容器元素由 `_element_fits_container` 按容器类型映射（`PACKED_BYTE_ARRAY→UINT8`、
    `PACKED_INT32_ARRAY→INT32`、`PACKED_FLOAT32_ARRAY→REAL_T`、其余 `WIDE`）；
  * 复合分量由 `running_game_node_write.cpp` 的分量表给出 `REAL_T` / `INT32`。
* 数组元素的**类型转换递归**刻意走内部 `_coerce_to_property_type_typed`，不使用成员规则：
  元素的槽是容器的元素槽，`PackedFloat64Array` 的元素是 `double` 而不是 `real_t`。

### 20.3 覆盖清单与**诚实边界**

**覆盖**：`double → float32`（溢出为 `inf` 与非零下溢为 `0` 两向）、`int64 → int32`、`int64 → uint8`、
packed 容器元素、向量 / 颜色分量、packed 向量数组元素、标量属性成员。

**显式不覆盖（诚实边界，不是遗漏）**：**标量 `INT` 成员的 C++ 宽度**。
`PropertyInfo` 只携带 Variant 类型、不携带 C++ 宽度，因此**无法**从外部区分 `int` 成员与 `int64_t` 成员；
一律按 32 位判会**误拒**合法的 64 位成员。该处因此保持 `WIDE`，由「每次写入后读回真值」保证诚实：
M4b 观测的 `z_index = 3000000000` 正是此类——引擎丢弃越界值、响应回显**写后真值**（`5`），
不属静默错值。宽度**可知**的两处（容器元素、复合分量）已由本闸门覆盖。

### 20.4 不属该类：**已声明的确定性转换**

以下都是 PLAYBOOK §7.7 口径下的**声明过的确定性转换**，**不**属于「失败→默认值→报成功」，不在本条款的拒绝范围内，
但必须在报告中逐条声明：整值 `FLOAT→INT` 截断（`1.9→1`、`[255.9]→[255]`）、`INT→FLOAT`、
`INT→BOOL`（`booleanize`：非零即真）、`BOOL→FLOAT`、写入 `String` 目标时的字符串化、
对象中不属于目标分量的键被忽略、`"0"→false` 与引擎 `booleanize("0")==true` 的**有意背离**（见 §17 / REPORT-021）。

### 20.5 验收证据形态（**四条必须同时成立**）

旧形态（「文件 sha256 相同 + 读回值 ≠ 请求值」）对 D-4 这一类会**结构性假绿**（M4b 已实证：
未 `save` 时 sha 恒同；值真被改时**没有旧值可读**；`serialize_variant` 把非有限 float 输出为 `null`，
读工具甚至看不见 `inf`）。因此每条反例必须同时给出：

1. **错误码** `-32602`；
2. **响应回显值有限**：`new_value` 等回显字段**不得**出现 `inf` / `nan` / `null` 来掩盖；
3. **落盘文件不得含 `inf`/`nan`**：显式保存后对文件字节扫描断言（`.tscn`/`.tres`/`project.godot`）；
4. **另一个读工具读到旧值未变**，并说明该工具对本例为何有效（若它对 `inf` 返回 `null`，就不能单独作证）。

### 20.6 资源写入的写后回读（D-5 一并落为规范）

`project_create_resource` 与 `project_edit_resource` 必须**同口径**：写入后**回读**目标对象，以
`changed:{<prop>:{old,new}}` 报告真实结果。「报成功必须以回读为据」：

* `properties_set` 只列**回读值就是请求值**的属性（`FLOAT` 目标按 `real_t` 宽度比较，
  否则 `(double)(float)0.1 != 0.1` 会把一次正常写入误报为失败）；
* 引擎 setter **夹取或忽略**的属性（如 `Curve.min_value = 5.0` 被夹成 `max_value - 0.01`）
  **不得**列为已设置，必须列入 `ignored`，并给出 `requested` / `stored` / `reason`。

### 20.7 跨进程能力必须以**可达**为准（D-6 的规范含义）

工具的 `scope` 分隔（GDR-19 §17.3、GDR-21）意味着「A 进程的写者 + B 进程的读者」这种组合会让能力**结构性不可达**。
凡出现这类组合，必须给出**可达通道**（本模块采用迁移源当年的 `user://` 文件 IPC：游戏进程原子持久化、编辑器侧读取），
且读取方必须：

1. **标明来源**（`source`）与文件路径 / 时间戳；
2. 文件不存在 / 为空时返回**诚实**结果（`no_results:true` + `report_file_present:false` + 原因），**不得伪造 `total`**；
3. `clear` 语义必须写清「清了哪一侧」，并让「下一次调用从零开始」在本进程**与桥接文件**上都成立
   （游戏进程的内存不可达，工具不得声称已清）。

## 22. GDR-24 收窄点必须显式标注，且被机器检查（TASK-023）

来源：M4 第三次独立验收（`REPORT-AUDIT-M4c.md`）的 **D-7（high）** 与 **D-15（medium，latent）**。
这是同一类「静默写错值」缺陷的**第 4 种形态**：

| 形态 | 例子 | 修在哪 |
|---|---|---|
| ① 容器元素 | `PackedByteArray` 元素 `300 → 44` | TASK-021 A-2 |
| ② 复合值分量 | `{"x":"abc"}` → `0.0` | TASK-021 A-4 |
| ③ 标量成员 | `rotation: 1e300` → `inf` | TASK-022 D-4 |
| ④ **专用 setter 路径** | `editor_set_viewport_3d_camera.position`、`editor_setup_world_environment.bg_color` → `code=0` + `inf`（且落盘） | **TASK-023 D-7** |
| ⑤ 构建配置 | 双精度构建下 `Color` 分量 / `PackedFloat32Array` 元素被 `REAL_T` 放行 | **TASK-023 D-15** |

根因不是漏了某处判断，而是**闸门的位置**：判定挂在 `coerce_to_property_type` 内部，所以只覆盖
「走 `Object::set()` 的属性写」。凡「**先算出值、再调用专用 setter**」的路径全都绕过它。
「逐形态打补丁」已被证明会继续漏，因此本条把判据升级为**结构性**的。

### 22.1 钳制点覆盖规则（D-7）

1. **`coerce_to_property_type` 不是唯一落点，而是默认落点**。任何**把 `double` 收窄进更窄的 C++
   存储**的代码位置（`(real_t)`/`(float)` 转换、`Color(...)`/`Vector2(...)`/`Vector3(...)`/`Vector4(...)`
   构造），必须在**收窄之前**经过 `MCPTools::value_fits_slot` —— 除非该值**不可能来自调用方**
   （由模块自己算出的常量、引擎自己的值、与构建无关的加宽转换），且该理由写在收窄点旁。
2. **专用 setter 路径按同一标准处理**：`Camera3D::set_global_position` / `set_rotation_degrees` /
   `set_fov`、`Environment::set_bg_color` / `set_ambient_light_color` 这类调用之前，
   参数（**含每个分量**）必须已被闸门判过；批量/跨对象路径保持「**任何写入之前**整体拒绝」。
3. **不接受「引擎反正会拒绝」作为理由**：引擎自己的范围校验（`Camera3D::set_fov` 的 1–179）
   只说明**结果**是诚实的，不说明这次收窄通过了闸门；而 `set_bg_color` 这类**没有**校验的
   setter 会把 `inf` 写进场景并随 `editor_save_scene` 落盘（M4c 已实证 `Color(inf, 0, 0, 1)`）。

### 22.2 槽位拆分：`FLOAT32` 与 `REAL_T`（D-15）

`ValueSlot` 增加 **`FLOAT32`**：**在任何构建配置下都按 32 位判**。

| 槽 | 用途 | 判据 |
|---|---|---|
| `REAL_T` | 标量 `FLOAT` 成员、`Vector2`/`Vector3`/`Vector4` 分量 | 随构建：单精度按 32 位判，双精度放行 |
| **`FLOAT32`** | **`Color` 分量**（`core/math/color.h:39-42` 声明 `float r,g,b,a`）、**`PackedFloat32Array` 元素** | **恒按 32 位判**（溢出 `inf` / 非零下溢 `0` 即拒绝） |

正确性来自**代码结构**而不是构建配置：`FLOAT32` 不参与 `#ifdef REAL_T_IS_DOUBLE` 分支，
所以 `precision=double` 下同一类静默 `inf` 不会复活。
**风险登记**：本机只构建单精度二进制，**未做双精度端到端验证**（见 `REPORT-023`）；
D-15 的结论是**源码级 + 单元级**（`value_fits_slot` 对 `FLOAT32` 的断言在任何构建下都成立）。

### 22.3 门⑥：收窄点清单检查（本条的**可执行**部分）

* 脚本：`modules/mcp_server/scripts/check_narrowing_points.py`（`--list` 打印清单、`--json` 机读）。
* 扫描范围：`modules/mcp_server/tools/**`，模式 `(real_t)`、`(float)`、`Color(`、`Vector2(`、
  `Vector3(`、`Vector4(`（注释与字符串内的出现不计）。
* 规则：**每个收窄点必须在源码该行（或其正上方注释块）带 `// MCP-NARROWING: <ID>`，
  并在脚本的 `PINNED` 清单里按「文件:行」登记理由**。
* 失败条件（任一即**门⑥红**）：①出现未标注的收窄点；②清单里没有该点或名字不符；
  ③清单条目失配（行号挪动/模式消失 → 陈旧条目）。
* 每个点必须归入四类之一并在报告中说明：`gated`（被 `value_fits_slot` 判过）、
  `pregated`（同一函数更早的步骤已判，如同一条组件的 `_check_component`）、
  `safe`（调用方值不可能到达：模块自算常量 / 引擎自己的值 / 加宽转换）、
  `gate`（该点**就是**闸门实现本身，如 `value_fits_slot` 内部的 `(float)` 拷贝）。
* 收纳进 `PLAYBOOK` §3 的**门⑥**，因此**后续批次自动生效**：新增收窄点而未标注 = 门失败。

### 22.3b 覆盖面的**声明边界**（M4d 第四次验收 D2 之后的修订，决策者落笔）

**教训**：第一版扫描器只认 `(real_t)`/`(float)`/`Color(`/`Vector2(`/`Vector3(`/`Vector4(` **六种字面拼写**，
而 `const real_t x = 1.0e300;`（**隐式收窄**）、`static_cast<float>(1e300)`、`::Color(…)`、
`Vector3{…}`、以及**跨行**构造**全都能绕过**（M4d 用五个探针实测门⑥ 仍 exit 0）。
→ 因此**禁止**再把门⑥ 描述成「每个收窄点都必须标注」这种**无边界**的说法。

**修订后的规则**：

1. 门⑥ 的保证**仅限于它的扫描器已覆盖的拼写集合**，且该集合**必须**：
   - 在脚本里**显式声明**（`--coverage` 可打印），
   - 有**探针回归**：集合内**每一种**拼写都必须有一个「插入即 exit 1」的探针（在脚本或证据里）；
2. 门⑥ **不能**作为「没有新的静默收窄」的**唯一**证据；它必须与**代码审查**（新增写值路径必须点名它经过的闸门）
   和**行为证据**（M4 的静态错值反例矩阵）**共同**构成保证；
3. **若采用编译器级检查**（如对模块自身源码启用 `-Wconversion` / MSVC `/we4244`）**且**它能覆盖更多拼写，
   则以编译器为准，门⑥ 退化为「标注与清单一致性」检查；采用与否及实测代价（告警量、构建影响）必须写进报告；
4. 任何**新增/修改**收窄代码的批次，必须在报告里**逐条**列出「新增点 × 它经过的闸门 × 证据」，
   **不得**只依赖门⑥ 变绿。

**三条实测事实（TASK-031 落地，决策者落笔）**：

5. **编译器级检查在本仓库实测**不可用**（rule 3 的前提不成立）**：
   本模块的 TU 会包含 **17 个引擎头**（`core/math/*.h`、`ustring.h`、`typedefs.h` …），它们**自身**就触发 `C4244`，
   而 `SConstruct` **全局**禁用了 `C4244`（注释原文 "Unavoidable at this scale"）。
   实测把 `/we4244` 只作用于模块**做不到**：实验构建 **exit 2**、301 行 C4244、8 个 TU 即死。
   合成 TU 另证：即便能开，它**也挡不住**「显式 `static_cast` / 限定构造 / 跨行构造」三类拼写。
   → 因此**以扫描器为门⑥ 的实现**，并把「未覆盖边界」**打印出来**（见第 6 条）。
6. **门⑥ 必须打印「覆盖集合」与「未覆盖边界」**：覆盖集合由 `--coverage` 声明
   （当前 **17 种拼写** = TASK-031 的 16 种 + TASK-033 补入的「同文件别名」类），
   **每一种拼写都必须有一个「插入即 exit 1」的探针**（由 `scripts/mcp031_gate6_coverage_probes.ps1` **机器强制**，
   TASK-033 后探针 **101/101**）；
   未覆盖的边界必须**显式打印**（例如「运行时隐式 `double→real_t`」「表达式推导出的越界值」「整数收窄」「`tools/**` 之外」），
   **不得**靠沉默暗示。
7. **门⑥ 是三腿之一，不是唯一证据**：`机器检查 + 代码审查 + 行为证据（静态错值反例矩阵）`。
   这一点必须出现在脚本 docstring、PASS 行、`--coverage` 的 `guarantee_position` 字段与 `PLAYBOOK` §3 里。

### 22.4 与 GDR-22 的关系

GDR-22 定义**判据**（转换关系 / 可解析性 / 槽位宽三关，`value_fits_slot` 只有一份实现）；
GDR-24 定义**覆盖面的证明方式**（每个收窄点都点名它经过的闸门，或被机器检查证明不需要）。
两条**同时**成立才算闭合：GDR-22 修「判错了」，GDR-24 修「没判到」。

## 23. GDR-25 顺手性（ergonomics）的可执行条款（决策者落笔，2026-09）

来源：用户指令（**引擎源码是第一参考源**，GDR-23 §21）与 M4 第三次独立验收的 §2.F（E-1..E-10、G-1..G-4）。
GDR-23 已把「顺手」定为验收条款，本条把它变成**可执行判据**，并补上 E-10 的设计含义。

### 23.1 判据：**零字符串手术链**

一条「顺手」的调用链必须满足：**调用方在整个链路里不需要做任何字符串手工处理**。具体禁止事项：

1. **不得**要求调用方把工具返回的标识**转形后才能喂回**给另一个工具
   （例：返回 `uid://…` 却要求调用方先调转换工具；返回 `Vector4` 的**字符串**却要求调用方自己解析）。
2. **不得**要求调用方从返回值里**剔除引擎内部装饰**才能使用
   （例：编辑器内部绝对路径 `/root/@EditorNode@<id>/…`——它**不可复现**，也不该出现在创作语义的路径里）。
3. **不得**要求调用方**改被测工程**才能让能力生效
   （例：靠 `ProjectSettings: godot_mcp/port` 才能让编辑器起的游戏可被观察）。
4. 工具的返回值必须是**可直接复用**的形态：路径是 `res://`、节点路径是**相对编辑场景根**的稳定形式、
   值是与同类值**形状一致**的结构（对象 vs 对象、数组 vs 数组）。

**验收方式**：在报告里写出一条真实执行过的**多步链**（≥4 步，跨工具），并**逐步标出调用方的字符串处理次数**；
目标为 **0**。M4 第四次复核将**自己重跑**该链。

### 23.2 E-10 的设计含义：**编辑器起的游戏由工具注入端口**

**事实（引擎侧）**：`EditorInterface::play_*` **无法携带 run args**（`editor/editor_interface.cpp:815-825`）；
能携带的是 `EditorRunBar::play_main_scene / play_current_scene / play_custom_scene(..., const Vector<String> &p_play_args)`
（`editor/run/editor_run_bar.h:117/123-125`），`EditorRun::run()` 会把 `p_play_args` **原样附加**到子进程命令行
（`editor/run/editor_run.cpp:157-161`）。

**规范**：

1. 编辑器侧**启动游戏**的工具（`editor_play_scene`）**必须**向子进程注入 `--mcp-port=<端口>`，
   使「起游戏 → 立刻用 MCP 观察」**不需要改被测工程**。
2. 端口来源必须**可指定也可自动**：可选参数 `mcp_port`；缺省时自动挑一个空闲端口，
   且**必须与编辑器自身端口不同**（同端口会让子进程 bind 失败并自我禁用）。
3. 响应**必须告知端点位置**：`mcp_port`、`mcp_port_source`（`argument` / `auto_free_port`）、可直连的 `endpoint`、子进程 `pid`。
4. **不得假成功**：端口被占、端口等于编辑器自身端口、注入失败、子进程未起来，一律**诚实报错**
   （`-32000` + `data.suggestion`）；`playing:true` 必须是**读回**的结果（`is_playing()` + 子进程 pid 变化），
   不是「调用过 `play_*`」。
5. **契约**：新增参数属输入 schema 变更 → 走 **`SCHEMA_OVERRIDES`（`mode=replace`，理由逐字引用被移除的 `required` 成员）**
   + `DESCRIPTION_OVERRIDES`（说明端口来源），**重生成契约 + 更新全部指纹**；**不得手改契约文件**。
6. 若引擎路径变化导致无法注入，**诚实降级**并在契约描述里写明，不得静默恢复「只能靠工程设置」。

### 23.3 日志类工具必须声明**来源进程**

`user://logs/godot.log` 是**编辑器与游戏进程共享并轮转**的文件（M4c 实测：编辑器端点会读到**游戏进程**的行，
且轮转窗口里直接 `-32603`）。因此：

1. 日志/错误类工具**优先**读**本进程内**的来源（编辑器进程内为 `EditorLog`，与 `editor_remove_output_log` 同侧语义）；
   文件仅作后备。
2. 响应**必须**带来源字段：`source`（`editor_log` / `log_file`）与**所属进程**（至少 `editor: true/false` 与端口或 pid），
   使调用方**不会把别的进程的日志当成自己的**。
3. 不可用时必须**诚实空**（`no_results` 语义或明确 `-32000` + 建议），**不得**用 `-32603` 掩盖「读不到」。
4. 同一族工具（`editor_get_errors` 与 `editor_get_output_log`）的**返回形状必须一致**。

### 23.4 读回形状 ↔ 写回形状：**双向闭合规则**（TASK-024b/025 落地）

**规则（规范）**：**「读侧能答出对象形态的类型集合」必须等于「写侧能接受对象形态的类型集合」**。
任一方向多出一个类型，都会破坏「零字符串手术链」（读到的值喂不回去，或写侧接受读侧答不出的形态）。

* **读回→写回矩阵（19 项，两端点各 19/19 往返通过，TASK-025 证据）**：

| 读回形状 | 类型 |
|---|---|
| `{x,y[,z[,w]]}` | `Vector2` `Vector2i` `Vector3` `Vector3i` `Vector4` `Vector4i` |
| `{r,g,b,a}` | `Color` |
| `{x,y,width,height}` | `Rect2` `Rect2i` |
| 整数数组 | `PackedByteArray` `PackedInt32Array` `PackedInt64Array` |
| 数字数组 | `PackedFloat32Array` `PackedFloat64Array` |
| 字符串数组 | `PackedStringArray` |
| 元素对象数组 | `PackedVector2Array` `PackedVector3Array` `PackedVector4Array` `PackedColorArray` |

* **写侧分量表规则**：`vector_component_hint` 的类型列表**必须等于**读侧能答出对象的类型集合
  （TASK-025 补齐 `Vector4i`/`Rect2`/`Rect2i`；分量名与读侧**逐字一致**）。
  新增读回类型时，**必须同时**加写侧，否则算缺陷。
* **分量槽位**：`Rect2` 分量为 `real_t` → `ValueSlot::REAL_T`；`Rect2i`/`Vector4i` 分量为 `int32_t` → `INT32`；
  `Color` 分量为 `float` → `FLOAT32`（见 §22.2）。**每个分量**都必须经 `value_fits_slot`（GDR-22/24）。
* **已知残留（登记的欠账，非缺陷）**：`Transform2D/Transform3D`、`Basis`、`Plane`、
  `Projection`、`AABB` 目前**没有任何工具读回**；**一旦有工具要读回它们**，必须按本规则同时给出
  对象形态的读与写，**不得**用 `stringify()` 的字符串形态（那会立刻破坏零字符串手术链）。
  （`Quaternion` 已由 **TASK-033** 补齐读/写对，**不再是残留**。）
* **证据形态**：往返测试必须断言 ③ 层等价 —— ①`code=0`；②`new_value` 与读回值**结构化**相等
  （**不是**把响应拼成字符串比较）；③**再读**一次仍相等。两端点各跑一遍。

## 24. GDR-26 可选的服务端调用追踪（决策者落笔，TASK-038）

**目的**：为**实机游戏开发试测**提供**观察者的诚实证据源** ——
若只让被观察者自述日志，观察者看不到被掐掉的摩擦；追踪由**服务端自己**记录真实调用事实。

**规范**：

1. **开关与优先级**：`--mcp-trace=<path>`（`<path>` 形式亦接受，**最后一条胜出**）
   > `ProjectSettings: godot_mcp/trace_file` > **默认关闭**（**不写任何文件**）。
   空值/缺值**不启用**；关闭时**不开文件、不序列化参数、不读时钟**。启动日志必须报 `trace=off` 或
   `trace enabled: file=… (arguments may contain project content)`。
2. **产物契约 = JSON Lines**（每行一条；`initialize` / `tools/list` / 每次 `tools/call` / 每个进 sink 的 JSON-RPC 请求）：
   `seq`、`ts_ms`、`connection`、`id`（**原样 token**，保数字/字符串类型）、`method`、`ok`、`error_code`、
   `error_message`（+ `_truncated`）、`duration_ms`、`result_bytes`；
   仅 `tools/call` 另加 `tool`、`args`（**规范化 JSON，键排序**）、`args_bytes`、`args_truncated`；
   仅 `tools/list` 加 `tools`（条数）；仅延迟调用加 `pending_ms`、`timeout_ms`。
   截断按 **UTF-8 边界**回退（`args` 4096 B、`error_message` 512 B）。
3. **零行为变化是硬条款**：①**关闭**时与改动前二进制的响应**逐字节相同**；
   ②**开启**时 ≥10 个工具 + **全量 `tools/list`** 响应逐字节相同；
   ③门① 在两端点逐字通过。**证据模板**：与改动前二进制做**逐条 sha256 对照**，并必须含 **「关-关-开」三跑**的对照组。
4. **健壮性**：写失败只 **WARN 一次并自禁**（工具调用不受影响）；**只追加**；每行 flush；退出 flush；
   **不得走 safe save**、不得独占句柄；主线程单帧保证**行不撕裂**。
5. **隐私与边界**：追踪**含调用参数**（可能含工程内容）→ 必须默认关闭 + 启动日志提示；
   它**不进** `tools/list`、**不进** `GET /mcp` 契约；只覆盖 sink 收到的请求；
   **连接先消失的延迟请求**不产生行（登记为已知边界）。
6. **分析脚本的启发式不是契约**：`scripts/analyze_mcp_trace.py` 的四类信号（摩擦=连续失败后成功/同参重复/错误码分布；
   缺失工具=`-32601` 与反复试探的参数名；可合并=高频 2-3 步 n-gram；异常=超时/`pending_ms>timeout_ms`/超大响应/单工具占比>30%）
   是**启发式**，参数可调，**不得**被当作规范判据。

### 23.5 `OBJECT` 属性的读回/写回形状（决策者裁决，TASK-026 D-8）

**实测缺陷**：`serialize_variant` 对**空 `Object` 指针**答 `{}`；而写侧拒绝 `{}`
（`can_convert(DICTIONARY, OBJECT)` 为 `false`），把 `null` 写进去**读回仍是 `{}`** →
**`OBJECT` 属性双向不闭合**（违反 §23.4）。

**规范（读回形状）**：

| 情形 | 读回形状 |
|---|---|
| 未设置（空指针） | **`null`**（**不得**答 `{}`；`{}` 语义上等于「有个对象但无信息」，是**假信息**） |
| 已设置**资源**（有路径） | `{"type": "<类名>", "path": "res://…"}` |
| 已设置**资源**（无路径：子资源 / 内建） | `{"type": "<类名>", "path": ""}` + `"local_to_scene": true/false`（若适用） |
| 已设置**非资源对象**（节点等） | `{"type": "<类名>", "path": "<节点路径或空>"}`；**不得**泄露指针/地址 |

**规范（写回形状）——必须接受读回形状本身（零字符串手术）**：
1. **`null`** → 清除引用；
2. **字符串** `res://…` → 加载并设置（加载失败 → `-32001` + 建议，**不得**静默忽略）；
3. **对象** `{"type","path"}` → **与读回形状同形**，按 `path` 加载；`type` 若给出则**校验一致性**
   （不符 → `-32602`，消息给出期望与实际）；
4. `{}`（空对象）→ **`-32602`**（信息不足；**不得**当成「清除」）。
5. 写回后必须**读回验证**（§23.4 的三层等价）；`null` 写回后**必须读回 `null`**（而不是 `{}`）。

**说明**：「已设置引用」的语义以**引擎为准**（`Object::get` / `ResourceLoader::load`）；
本条规定的是**本模块的 JSON 形状契约**，目标是「读到的值能原样喂回」。

## 25. GDR-27 操作前后的**捕获**（决策者落笔，TASK-044）

**目的**：让「**报成功但画面/状态没变**」（本项目核心命题，D-1/D-2 家族）从**推断**变成**机器可判事实**：
一次操作**前后各一张截图**，与**操作日志同行记录**，并自动给出 `changed` 与 `changed_pixel_ratio`。

**规范**：

1. **形态与契约面**：它是 **`§24/GDR-26` 追踪的可选扩展** —— **零契约变更**：
   **不新增工具、不改任何 `inputSchema`/`description`**（171 条逐字对等门不动）；
   截图与结论**只进日志与文件**，**绝不进工具响应**。
2. **开关**（默认关闭）：`--mcp-capture=off|on_error|every_call`（**默认 `off`**）
   > `ProjectSettings: godot_mcp/capture`；配套 `--mcp-capture-dir=<OS 路径>`（默认 = 追踪文件同目录的 `shots/`）、
   `--mcp-capture-viewport=editor|2d|3d`（**默认 `editor`**）、差异图落盘开关（默认不落）。
3. **取景**：编辑器侧 `editor` = 现有 `get_base_control()->get_viewport()`（整窗）；
   `2d` = `EditorInterface::get_editor_viewport_2d()`；`3d` = `EditorInterface::get_editor_viewport_3d(0)`
   （依据：`editor/editor_interface.h:130-131`）；游戏侧 = 游戏窗口。
4. **时序（诚实语义 + 零延迟）**：收到请求时**只做一次 framebuffer 图像拷贝**，**随后照常应答**（**不等帧**）；
   编码 / 落盘 / diff 一律在**应答之后**执行。→ 捕获**不改变**任何工具的响应内容与时序。
   日志里「前」= 收到请求时最近渲染的帧；「后」= 该调用生效并**再渲染至少 1 帧**之后的帧
   （用既有**帧计数 + 延迟通道**，与 `editor_bake_navigation_mesh` 的轮询同法），并带 `frames_waited` 自证。
5. **日志 schema**：调用行增加 `capture:{mode, viewport, status:"pending"|"unavailable"}`；
   **应答之后追加一行** `{"event":"capture", "seq":<同一 seq>, "tool":…, "status":"done|unavailable|failed",`
   `"before":{path,sha256,bytes,width,height}, "after":{…}, "frames_waited":N,`
   `"changed":bool, "changed_pixel_ratio":float, "diff":{path?}, "total_bytes":N, "reason"?}`。
6. **headless 不得静默**：无帧缓冲时写 `status:"unavailable"` + `reason`（**不写空白图**）；
   写图失败写 `status:"failed"` + `reason`，**绝不影响**工具调用。
7. **不设上限但必须可见**：**不设容量上限、绝不自动删除任何文件**；
   每行带 **`total_bytes`（累计）**；启动日志打印捕获目录与模式；累计超 **1 GB** 时**只 WARN 一次**。
8. **复用而非重写**（GDR-25）：`normalize_screenshot_path` / `screenshot_png_writer` / `game_framebuffer_available`
   已在 `tool_helpers`；**像素比对算法必须从 `tools/editor_testing_read.cpp` 提升到 `tool_helpers`**，
   使**捕获与 `editor_analyze_screenshot_diff` 共用同一实现**（与 TASK-011 提升 PNG 写入器同法），
   并证明后者**行为与证据不变**。
9. **零行为变化**：`off` 时与改动前二进制的响应**逐字节相同**；`on` 时 171 工具的**响应**逐字节相同
   （沿用 `§24` 的三条对照模板，含**与任务前二进制比对**与**「关-关-开」对照组**）。
10. **验收的存在理由**：必须有一个构造实验证明「报成功但什么都没发生」得到 **`changed:false`**，
    以及一个真实改变得到 **`changed:true` + `changed_pixel_ratio>0`**。

**实测事实与边界（TASK-044 落地，决策者落笔）**：

11. **实测**（基准提交 `0d405fa2a9`）：三个视口尺寸 —— `2d` 2978×1793、`3d` 2978×1790、
    `editor` 3840×2054（**整窗，比子视口大**）、游戏侧 `viewport="game"` 1152×648；
    存在理由实验：同参同调用两次都 `error_code 0`，第一次 `changed:true` / ratio `0.0200016705515105`，
    第二次 `changed:false` 且前后 sha256 相同（游戏端点 0.3215 → false 同型）。
12. **「零延迟」的准确含义 = 响应路径**：响应路径只多**一次 framebuffer 拷贝**
    （同调用服务端 `off` 中位 0–1 ms → `every_call` 中位 7–8 ms）。
    **应答之后的代价已被拆开实测**（TASK-045 归因，非推断）：
    **像素比对 ~89 ms → ~14 ms**（TASK-045 改原始字节遍历），
    **两张 PNG 编码 ~356 ms**（2978×1793 各 ~177 ms，TASK-045 未触及）。
    → **背靠背**往返：18.5 ms（off）→ 453.6/458.6 ms（TASK-044）→ **377.6/386.6 ms**（TASK-045）；
    **请求间有空隙时 ~30 ms**。→ 本条**不得**写成「无代价」；**高频场景下背靠背调用会排队**是**已知代价**，
    且其**主因是 PNG 编码**（优化方向见 §25 第 14 条）。
13. **边界（必须知道，不得沉默）**：
    ① **捕获依赖 `--mcp-trace`**：没有追踪文件时 `--mcp-capture` 不生效并**给一次 WARN**；
    ② **延迟通道（`pending_handler`）的 `tools/call`** 记为 `capture.status:"unavailable"` + `reason`（**不静默 skip**）；
    ③ **headless** 下捕获目录仍会被创建但**永远为空**；
    ④ `mcp_capture.cpp` 在门⑥ 扫描器的声明范围（`tools/**`）**之外** → 扫描数不变（73）**不能**当作
    「未引入新收窄拼写」的证据，该文件须走**代码审查 + 行为证据**两腿。

14. **编码代价已收（TASK-046 实测）**：捕获落盘走**快速压缩**（`Image::_save_png_to_buffer(true)` →
    `image_to_png(..., p_fast)` → `PNG_IMAGE_FLAG_FAST`，即 NO_FILTERS + level 3）；
    **既有截图工具的字节不得变**（`screenshot_png_writer` 不动，`p_fast=false` 就是原来的 `save_png()`）。
    实测：编码 **174.1 → 34.7 ms/帧（5.0×）**，两帧 **354 → 69.4 ms**；**体积约 4.5×**（诊断产物，可接受）。
    另加 `--mcp-capture-scale=1|2|4`（**默认 1**，**命令行 only**）：
    **缩放必须发生在比对之前**并在日志记 `scale`，使 `changed_pixel_ratio` 与**文件**自洽
    （否则拿文件调 `editor_analyze_screenshot_diff` 会得到**不同**数字——陷阱）；
    插值用 **BILINEAR**（LANCZOS 实测 77–83 ms/对会让 `scale=2` **比 scale=1 更慢**）；
    `scale=4` **会欠采样**（诊断光栅的已知代价）。
    → **背靠背**：18.5 ms（off）→ 458.6（TASK-044）→ 386.6（TASK-045）→ **99.0–101.4 ms（TASK-046）**；
    有空隙时 ~30 ms。管线归因（scale=1）：**69.8 ms 编码 + 14.4 ms 比对 = 84.2 ms**。
    **捕获行新增字段 `scale`**（所有 status 都带），启动行**追加** `scale=<n>`（追加而非插入，避免破坏既有断言）。
15. **非主线程化：评估后不做**（TASK-046 结论）：`ViewportTexture::get_image()` → `RS::texture_2d_get`
    在主线程**同步等待**渲染线程（`servers/server_wrap_mt_common.h:153-165`），那 7–8 ms **移不走**；
    可移的是编码/缩放/比对/写文件，但 `FileAccess::backup_save` 是**进程级静态**、追踪器 `Recorder` **无锁**
    （其行完整性明确依赖「全在主线程」，`mcp_trace.cpp:230-235`）→ 需要**先在规范里定义有界队列/丢弃语义**。
    收益已从 ~357 ms 降到 ~84 ms，**属架构选择而非性能必需** → **暂缓**；若将来要做，**先改规范再动人**。

## 26. GDR-28 **契约扩张：新增工具**（决策者落笔，TASK-052）

**背景**：`gen_renamed_contract.py` 至今只做「**重命名 + override 既有 174 条**」，
契约因此恰好是 171 条移植工具。用户已授权实施**经独立确认**的改进，其中 C 档需要**新增工具**
（`M-2 project_build_csharp`、`N-3` 工程文本写能力等）→ 必须先把**新增机制**写成规范，否则无法诚实扩张。

**规范**：

1. **新增条目由决策者撰写**（名 / 描述 / `inputSchema`），落在生成器里的 **`ADDED_TOOLS`** 列表
   （**与 `DESCRIPTION_OVERRIDES`/`SCHEMA_OVERRIDES` 分离**），在重命名 + override 之后**确定性追加**；
   `_meta` 增加 **`added_tools`**（名字列表，有序）与 `added_count`；生成器**幂等**（连跑两次同 sha）。
2. **对等门的表述随之改变**：门① 从「171 条逐字」变为
   「**171 条移植工具逐字 + N 条新增自撰条目逐字**」；
   `check_tool_groups.py --check-completeness` 的并集断言从 `171 = 66 + 105` 变为
   `**171 + N = 66 + 105 + N**`，且**新增工具必须恰好出现一次**（missing=0 / foreign=0 / duplicated=0）。
3. **新增工具也必须进组清单**：落在**新的** `docs/tool-groups-added.json`（**不改**既有批次清单），
   并受与移植批次**同样的组规则**约束（单渠道 / 单作用域 / 单 mutating / 组大小 ≤10 / 名字派生 channel+verb 一致）；
   `check_tool_groups.py` 增加 `--added` 校验该清单，并把它计入完备性。
4. **命名同规**（GDR-16/D38）：`<channel>_<verb>_<object>[_<qualifier>]`，渠道限 `editor_`/`running_game_`/`project_`/`os_`；
   **不使用 `update_`**；**可判别性优先**。
5. **新增工具与移植工具同标准**：三类证据、错误码与建议、写后读回、`scope` 隔离、门① 逐字、组规则、契约指纹；
   **不得**低于移植批次的要求（新增不是「降级通道」）。
6. **capability-aware 拒绝**：新工具依赖**外部能力**（如 .NET SDK / MSBuild）时，
   缺能力必须 **`-32000` + `data.suggestion`**（说缺什么、怎么装），**不得**伪造成功或回显假数据。
7. **不可手改契约**：一切改动经生成器；改完必须给**结构化 diff**（只动新增条目 + `_meta`）与**幂等证明**。

**实测事实（TASK-052 落地，决策者落笔）**：

8. **机制已落地**：`ADDED_TOOLS` 为**第三张表**（与两张 override 表分离），`GENERATOR_VERSION` **1.14.0**；
   `_meta` 增 `added_tools`（有序）+ `added_count`；**幂等**（连跑两次同 sha `1cb68de8…`）；
   结构化 diff **34 checks / 0 problems**（**171 条移植条目逐字不变**、新增**恰为末两条**、
   `_meta` 只动 `count/generator_version/added_tools/added_count`、`map_sha256` 未动）。
9. **计数与清单**：契约 **173** 条；`--check-completeness` 证 **`171+2 = 66+105+2`**（四桶互斥）、
   `--added` 校验**新的** `docs/tool-groups-added.json`（既有五份批次清单 **sha 未变**）；
   注册表为新增动词保留**一个显式扩展**（`MCP_ADDED_TOOL_VERBS = {build, write}`），
   **与映射自带的 37 词表分开**，使后者逐字不变。线上：**9888 = 150 / 9889 = 71**（由映射 + 新增清单**派生**，非硬编码）。
10. **错误码裁决（改判任务书）**：`project_write_text_file` 在「**目标已存在且 `overwrite:false`**」时
    **不用 `-32001`**（GDR-14：`-32001` = **你要找的东西不存在**；此处它**存在**），
    也**不用 `-32602`**（该参数**已声明且取值合法**）→ 用 **`-32000` + `data.suggestion`**（点名 `overwrite:true`），
    因为**是状态**不允许该调用。**并**必须在拒绝后证明**文件字节未变**。

**实测事实（TASK-053 落地，决策者落笔）**：

11. **计数以「新增清单」为准，不靠任务书里的数字**：`ADDED_TOOLS` 落地后契约 **175 条**
    （171 移植 + 4 新增：`project_build_csharp`/`project_write_text_file`/`project_validate_scripts`/
    `editor_set_node_script_batch`），生成器 **1.15.0**，`tool-groups-added.json` 4 组；
    线上 **9888 = 152 / 9889 = 72**；`--check-completeness` 打印 **`171+4 = 66+105+4`**。
    → **教训**：任务书里的条数**必须从清单派生**（我在 TASK-053 手写「176」而 §2 只有两条 → 执行者按规范**没有替我编条目**，
    这是正确的；**手写条数 = 又一次「用简短描述代替确切规格」**）。
12. **给既有工具加参数仍走 `SCHEMA_OVERRIDES`**（不改条目数、有 `_meta.overrides` 留痕），
    与「新增条目走 `ADDED_TOOLS`」是**两条不同的通道**，不得混用；M-5 的 `sample_stride` 即此例
    （默认响应与改动前**逐字节相同** `sha eef36e62…`；`sample_stride=10` 时 180 点 6147 B → **781 B（−87%）**）。
13. **已登记的引擎级诚实性缺陷（待立项）**：`CSharpScript::reload()` **恒返回 OK**
    （`modules/mono/csharp_script.cpp:2593-2620`）→ mono 构建里**语法错误的 `.cs` 也报 `valid:true`**，
    **单数与批量校验工具都受影响**（同一共享判定）。→ 在修好之前，C# 的「有效」**不得**被当作已验证事实；
    修法二选一：(a) 找到**真能区分**的引擎信号（先读源码）；(b) **下调声明**（分类为 `unverifiable` + 引擎依据 `文件:行`）。

