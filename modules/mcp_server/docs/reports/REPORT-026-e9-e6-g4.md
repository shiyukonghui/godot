# REPORT-026 — 顺手性批次 3：**E-9**（读资源给内容）· **E-6+G-4**（日志来源与即时性）

> 任务书：`docs/tasks/TASK-026-e9-e6-g4.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`；
> 判据：`docs/DESIGN-DETAIL.md` §23 / GDR-25（§23.1 零字符串手术、§23.3 日志来源、§23.4 双向闭合）。
> 本批**不新增工具、不改名字、不改契约**（`tools_list.renamed.json` / `tool-rename-map.json` /
> `tool-groups.json` **均未改动**，见 §8 指纹）。

## 0. status / commits / 构建绑定

| 项 | 值 |
|---|---|
| status | **complete**（两项都落地；另修一处由 E-9 链式喂回要求暴露出来的写侧缺口，见 §1.4 / §7） |
| 实现提交 | **`48474b5a8d`** — `TASK-026 ergonomics batch 3: E-9 resource values, E-6+G-4 log source`（8 files changed, 1576 insertions, 76 deletions） |
| 报告提交 | 第二条提交（本文件 + `scripts/mcp026_object_shape_probe.ps1`，见 `git log`；本报告不引用自己的 sha，避免自指）|
| 分支 | `feature/mcp-server-module`（**未 push**） |
| 构建 | `modules/mcp_server/scripts/build_local.cmd -Force`（`tests=yes`），**串行**，scons 输出未抑制（`%TEMP%\mcp_server_build_local.log`，末次 `exit 0`） |

**构建与门的绑定关系（R-1 口径，必须说清）**：门全部跑在「内容 == `48474b5a8d`」的工作树上，
但 `--version` 自报的是**构建时刻的 HEAD（`f4339864e`，即本提交的父提交）**——
二进制里的 hash 只能记录构建时已存在的提交，而门必须在提交之前跑。证据：

* 门开跑前 `--version` = `4.8.dev.custom_build.f4339864e`，`git rev-parse --short HEAD` = `f4339864ee` → **匹配**；
* 提交后 `git status --short modules/mcp_server` **为空** → 被门测量的树与 `48474b5a8d` 逐字节相同
  （改动全部在提交前完成，之后只新增了本报告文件）。

> 如果评审要求「二进制 hash == 当前 HEAD」，需要在 `48474b5a8d` 上再重建一次（约 2.5 min）并重跑门③④①⑤；
> 本报告没有这样做，因为门的对象是**代码内容**，而内容已经由 `git status` 证明一致。这是本批**唯一**
> 已知的流程性残留，登记在此供决策者裁决。

## 1. 逐工具表

### 1.1 `project_read_resource`（E-9）

| 项 | 内容 |
|---|---|
| 迁移源位置（**仅类别参考**） | `godot_mcp_gdext/src/commands/resource.rs:75`（`read_resource`）：只报 `{loaded,path,type}` |
| **引擎依据** | 一次调用即可给内容：`ResourceLoader::load()` → `Resource::get_property_list()`（`core/object/object.cpp:653`）→`Object::get()`。判定「这条属性属于文件」用引擎自己的旗标 `PROPERTY_USAGE_STORAGE`（`core/object/property_info.h:91`）——**资源保存器自己就是用它决定 `.tres` 里写什么的**（`core/io/resource.cpp:248/409/498/639`）。值的形状走模块既有的唯一序列化器 `MCPTools::serialize_variant()`（§23.4）。 |
| **自然契约** | 成功：`{loaded, path, type, properties:{<名>:<值>…}, total_properties, truncated, dropped, limits:{max_properties}, message}`；`path` 必填（缺失 `-32602`）；文件不存在/不可加载 → `-32001` + `data.suggestion`（沿用既有语义，未改）；路径归一后回显；属性顺序 = `get_property_list()` 顺序（确定性）；**上限 64 条** + 截断标记（§2）。 |
| C++ 落点 | `tools/project_read_files.cpp`（`_tool_read_resource`，`MAX_RESOURCE_PROPERTIES = 64`） |
| 与迁移源的差异及理由 | 差异巨大且是**本任务的目的**：迁移源「读资源却不给内容」，调用方被迫再走一趟 `editor_execute_gdscript`（M4c 实测违反 §23.1）。按手册 D74/§6.8b「引擎明明能给更有用结果就按引擎来」。契约的 `inputSchema`/`description` **未改**（输出形状不在 `inputSchema` 里，无需 override）。 |

**实测（编辑器 9888，`E9_read_gradient`，响应 sha256 `7fbddd45…`）**：

```json
{"dropped":0,"limits":{"max_properties":64},"loaded":true,
 "message":"All 7 stored properties of the resource are returned",
 "path":"res://resources/gradient.tres",
 "properties":{"colors":[{"a":1.0,"b":0.0,"g":0.0,"r":1.0},{"a":1.0,"b":1.0,"g":0.0,"r":0.0}],
               "interpolation_color_space":0,"interpolation_mode":0,"offsets":[0.0,1.0],
               "resource_local_to_scene":false,"resource_name":"","script":null},
 "total_properties":7,"truncated":false,"type":"Gradient"}
```

引擎侧交叉核对（同一个 `.tres`，`editor_execute_gdscript` 里手写 `get_property_list()` +
`p.usage & PROPERTY_USAGE_STORAGE`）：

```
engine STORAGE = [resource_local_to_scene, resource_name, interpolation_mode,
                  interpolation_color_space, offsets, colors, script]
tool properties = [colors, interpolation_color_space, interpolation_mode, offsets,
                   resource_local_to_scene, resource_name, script]      → 排序后逐项相等（E9_6 PASS）
```

**§23.1 的证据形态**：`script` 是 STORAGE（引擎把它当存储属性），未挂脚本时**读作 `null`**；
实测这条在 `Gradient` 上闭合——整包写回把 `script:null` 一起喂回去，`code=0`（§4 链 2/3 步）。
注意这**不**等于「所有 OBJECT 都闭合」：换成 `Environment.sky` 那种 **OBJECT 空指针**，读侧答 `{}`，
写侧 `-32602`（§2.1 实测）。

### 1.2 `editor_get_errors` / `editor_get_output_log`（E-6 + G-4）

| 项 | 内容 |
|---|---|
| 迁移源位置（**仅类别参考**） | `resource.rs` 无；`editor.rs:270` `get_editor_errors`、`editor.rs:290` `get_output_log`（都只读 `user://logs/godot.log` 的尾窗，然后分别按 `"ERROR"` 大写包含 / 大小写敏感子串过滤） |
| **引擎依据** | ①**进程内来源**：编辑器进程的 Output 面板就是 `EditorLog`（`editor/editor_log.h:182 add_message`），它的内容由**本进程**的打印/错误处理器喂入：`EditorNode::_print_handler`（`editor/editor_node.cpp:8024/9724-9726`，`add_print_handler`）与 `EditorLog::_error_handler`（`editor/editor_log.cpp:68`）；`RichTextLabel` 的 `ERROR: …` 前缀就写在里面（`editor_log.cpp:426`）。②**为什么文件不是「本进程的日志」**：`main/main.cpp:2287` 把文件日志默认关掉，`:2292` 只对 `pc` 特性标签打开，而引擎自己的注释（`:2290-2292`）写明「**这也阻止为编辑器实例创建日志，因为编辑器里特性标签是关闭的**」——所以写那个文件的是**工程的游戏进程**。③同族语义：`editor_remove_output_log` 一直走进程内 `EditorLog`（`EditorNode::get_log()`），本批把读侧对齐到同一侧，消除语义分裂。 |
| **自然契约** | 共用同一个「来源块」（G-4 统一的 9 个键）：`source` = `editor_log` \| `log_file` \| `none`；`in_process`（这份行是不是本进程的）；`available`；`editor` / `process`（**回答者**是不是编辑器）；`pid`；`port`（本进程 MCP 端口，0 = 没监听）；`log_path`（`user://logs/godot.log`，后备路径，恒在）；`note`（不可用原因 / 「共享文件，可能不是本进程」的告示，可用且干净时为空串）。工具各自的载荷不变：`{errors,count}` / `{lines,count}`（`max_lines` 尾窗、过滤器、`-32602` 语义全部与迁移源逐字保持）。**不可用 = 诚实空**（`source:"none"`、`available:false`、空列表 + `note`），**绝不 `-32603`**。 |
| C++ 落点 | `tools/editor_read_scene_inspector.cpp`（`MCPLogSource` / `_read_log_source` / `_log_tail` / `_add_log_source_fields`）；进程内读取 `MCPTools::editor_log_lines()` 新增在 `tools/tool_helpers.{h,cpp}`（与 §17.1「一组一个定义」一致，避免每个组文件各copy一份面板查找） |
| 与迁移源的差异及理由 | 迁移源把「读日志」实现成「读一个**别人的**文件」：M4c 在 9888 上读到 `[MCP] listening on 127.0.0.1:9889 (editor=false)`，并实测「存在但打不开」时直接 `-32603`。本批按 §23.3 改为**进程内优先、文件仅后备**，并把「这是谁的日志」变成响应里的字段。**`editor_get_errors` 新增 `source` 等字段正是 G-4 要修的形状分裂**（原来只有 `editor_get_output_log` 有 `source`，且取值是 `log_file`/`no_log_file`；现在两者同形，后者统一为 `none`）。 |

### 1.3 端到端实测（编者 9888 与游戏 9889）

| 观测 | 红（旧代码）| 绿（本批） |
|---|---|---|
| 编辑器端点、游戏进程还活着时读日志 | `-32603 "cannot open the log file 'user://logs/godot.log'"`（两个工具**都是**这个，响应 sha256 `f4bb0c25…`） | `source=editor_log, in_process=true, available=true, pid=62616(=9888 监听者), port=9888, note=""`，`editor_get_output_log` 返回 **22 行本进程内容**（含本进程 `print` 标记与 `ERROR: …MCP026-EDITOR-ERROR marker`），**不含**任何 `MCP026-GAME-*` 行 |
| 游戏进程启动前读日志 | `{"count":0,"lines":[],"source":"no_log_file"}`——**本进程自己刚打印的标记一行也看不到** | `source=editor_log`，标记可见 |
| `editor_get_errors` 的来源字段 | **没有** `source`（G-4） | 与 `editor_get_output_log` 同形（`E6_5` 逐键逐值相等） |
| 游戏端点 9889 调日志工具 | `-32601 Method not found: editor_get_errors` | 同（**未改**，工具 `scope=editor`，游戏进程根本不注册；`tools/list` 53 条里没有它们） |
| 共享文件被独占（模拟轮转窗口） | `-32603`（与「游戏持有」时**同一份响应字节**，`f4bb0c25…`） | `code=0`，`source=editor_log / available=true / in_process=true`（编辑器进程压根不依赖那个文件） |

> 「游戏进程持有时那份文件连外部读都失败」是**实测**而非推测：`observation: '…\logs\godot.log'
> readable from outside while the game process is alive = False`——Godot 的写句柄在开启备份保存时
> 用 `_SH_DENYWR`/`_SH_DENYRW`（`drivers/windows/file_access_windows.cpp`，
> `is_backup_save_enabled()` 分支），这就是 M4c「轮转窗口 `-32603`」的**确定性成因**；
> 门②用 `FileShare.None` 独占复现它，得到**逐字节相同**的旧行为。

### 1.4 附带修复：两个**资源**写工具缺少分量整形（E-3 的第三张脸）

| 项 | 内容 |
|---|---|
| 触发 | E-9 要求 4「读到的属性**原样**写回」。资源属性只能经 `project_edit_resource` 写回（节点工具写不了资源自身属性），而实测 `project_edit_resource(colors = 读回值)` → **`-32602`**（红证据见 §5.1 的 `E9_12`）。 |
| 根因（引擎/模块依据） | 模块的写路径是三步：`property_value_from_json` → **`shape_vector_from_json`** → `coerce_to_property_type`（见 `MCPTools::prepare_node_property_value`，`tools/running_game_node_write.cpp:664-680`）。编辑器节点写、批量写、跨场景写、`project_set_setting` 都走三步；**两个资源写工具只走第一、第三步**，所以 `{"x":1,"y":2}`/`[{r,g,b,a}]` 这类 **§23.4 读回形状**在资源路径上被拒，而在节点路径上被接受——同模块内两个工具间违反 §23.4 闭合规则。 |
| 修法 | 新增文件私有 `_resource_property_value()`（`tools/project_write_resource_scene.cpp`），把中间的整形步补上，`project_create_resource` / `project_edit_resource` 两个调用点改用它。`shape_vector_from_json` 对非分量形状目标是**恒等**的，所以其余行为不变（旧测试全绿、`G24-RESOURCE-SET-WIDTH` 收窄点未新增）。 |
| 范围声明 | 这**超出**任务书两项的字面范围（动了第三张「脸」），但它是 E-9 要求 4 的**必要条件**（否则本批的链式喂回对分量形状不可能成立），且属于 §23.4 明确规定的「新增读回必须同时能写回」。已在决策日志层面**显式登记**（本表 + §10 deviations），请决策者复核。 |
| 反例（仍然拒） | 不命名分量的对象仍被拒并给出分量提示（§5.3 引 TASK-018 的既有 `-32602`），不会静默写零向量。 |

## 2. 「属性值形状与限量策略」

**取哪些**：`get_property_list()` 里 `usage & PROPERTY_USAGE_STORAGE` 的条目，**全部**（不过滤 `_` 前缀、
不特判 `script`）。理由：对 **资源** 而言 STORAGE 就是「这个文件存了什么」（资源保存器同一旗标），
`_`-前缀在资源里恰恰常是真实数据（`Curve._data`）；而节点侧的 `_`/`script` 过滤是迁移源的可见性怪癖
（`editor_get_node_properties` 沿用），与本工具的目标（「这份文件存了什么」）不同，故**有意不同形**。

**形状（§23.4，走既有 `serialize_variant`，读侧形状与节点读属性工具一致）**：

| 引擎类型 | 读回形状 | 实测来源 |
|---|---|---|
| `PackedColorArray` | `[{r,g,b,a}, …]`（对象数组） | `colors = [{"a":1.0,"b":0.0,"g":0.0,"r":1.0},{…}]` |
| `PackedFloat32Array` | `[数字, …]` | `offsets = [0.0,1.0]` |
| `bool` / `int` / `float` / `String` | 直接 JSON 标量 | `resource_local_to_scene=false`、`interpolation_mode=0`、`resource_name=""` |
| **NIL**（属性存在但值为 nil，如未挂脚本的 `script`） | `null` | `"script":null` |
| **OBJECT，空指针**（`Environment.sky` 未设置） | **`{}`（空对象）** | `"sky":{}` —— `serialize_variant` 的 OBJECT 分支对空指针返回空 `Dictionary`（`tools/tool_helpers.cpp`）|
| OBJECT，引用已设置 | `{"type":<类>,"value":<to_string()>}` | 未在本批夹具里构造 |

**字段命名**：与既有读属性工具一致用 `properties`（名字 → 值），与写工具的同名参数 `properties` 对称。

**限量策略（给出上限 + 截断标记；不新增参数，因为改 `inputSchema` 要走 `SCHEMA_OVERRIDES` 且属决策者权限）**：

* `MAX_RESOURCE_PROPERTIES = 64`（常量在 `tools/project_read_files.cpp`，无参数开关）。
  取 64 的理由：逐个查看的资源都远小于它（`Gradient` 2+2，`PhysicsMaterial` 3，`Curve` < 10），
  而批量资源（`Environment` 101）本来就更适合按名读；它只是**条数**上界，不是字节预算。
* 恒在的三个键（沿用 `running_game_stop_input_recording` 的既有惯例）：
  `truncated`(bool) / `dropped`(int) / `limits:{max_properties:64}`；另加 `total_properties`（引擎报的总数）
  与 `message`（人话说明）。
* 实测（`E9_7`，`Environment`，101 条）：`total_properties=101, returned=64, dropped=37,
  truncated=True, message='64 of 101 stored properties returned; 37 omitted by the tool's limit'`。
  上限是**活的**：`total_properties > 64` 是断言的一部分，若引擎类变小到 ≤64，测试会红（保持诚实）。

**诚实空**：`total == 0` 的分支给 `properties:{}` + `message`（「引擎没报任何 STORAGE 条目」）。
**实测补充**：可加载的 `Resource` 在本引擎里**恒有** ≥1 个 STORAGE 属性（`resource_local_to_scene`、
`resource_name`，以及 `Object` 级声明的 `script`；`resource_path` 是 `PROPERTY_USAGE_EDITOR`、
`resource_scene_unique_id` 是 `PROPERTY_USAGE_NONE`，都不算），所以这个分支在本引擎**不可达**，
属**防御性**代码而非实测结论——但它输出的形状与「没有可读来源」时的诚实空一致。

**残留（登记，非缺陷）**：

1. **字节预算没有**：条数有界 ≠ 体积有界。一个 `PackedFloat32Array` 属性仍可能很大
   （例如 `Environment` 里没有大数组，但 `TileSet`/`Gradient` 这类可以很大）。
   若决策者要字节上界，需要一个新参数或全局上限（属契约变更，须走 override）。
2. **任务书示例 `Curve.min_value` 不是存储属性**（见 §10 deviations D-1），链式喂回改用
   `Gradient.colors`（`PackedColorArray`）+ 整包 `properties`。

### 2.1 【发现】OBJECT 值的读回缺口：E-9 第一个把 `serialize_variant` 的 OBJECT 形态暴露出来

E-9 是**第一个读回 OBJECT 值**的工具，因此它也是第一个撞到这条 §23.4 缺口的地方。**全部实测**，
可复现脚本：`scripts/mcp026_object_shape_probe.ps1`（自建 scratch 工程，**11/11 checks，exit 0**，
evidence log sha256 `4e5b1b63a05b9e631ffe143c67c75164dec7a07ccc53f3f9f251aea16e59cd60`，
`%TEMP%\task026-object-shape\evidence\`）：

| 步骤 | 输入 | 结果 |
|---|---|---|
| 读 | `project_read_resource(environment.tres)` | `"sky":{}`（101 条 STORAGE 之一，值 = 空对象）|
| 写（照读到的写回） | `project_edit_resource(properties={sky:{}})` | **`-32602`**：`Parameter 'properties' cannot be written to a Object property: the value is a Dictionary ({}) and this engine's own conversion relation (Variant::can_convert) does not list Dictionary -> Object …` |
| 对照（整包写回） | `project_edit_resource(properties = 上面读到的整个 properties)` | **`-32602`**（同一个 `sky:{}` 卡住整包）|
| 对照组 1（标量） | `background_mode = 0` | `code=0`，`changed.background_mode.new = 0` |
| 对照组 2（分量形状） | `background_color = {r:0.1,g:0.2,b:0.3,a:1.0}` | `code=0`，`new = {r:0.100000001490116,…}`（**§1.4 的整形修复在资源路径上生效**）|
| 试探 2（换成 JSON `null`） | `project_edit_resource(properties={sky:null})` | `code=0`，但 `changed.sky.new = {}`、`old = {}` —— **写进去了却仍读回 `{}` ≠ 输入 `null`**，往返不等 |

**结论（实测，不是推断）**：OBJECT 类型的属性**今天在两个方向上都不闭合**——
读侧答 `{}` 而写侧不接受 `{}`（`can_convert(DICTIONARY, OBJECT)` 为假，`{}` 是**可证的死形状**）；
即使调用方自己改写成 `null` 写进去，读回仍是 `{}`，结构上也不相等。

**最小修法（建议，未自行实施）**：`MCPTools::serialize_variant()` 的 OBJECT 分支对**空指针**
返回 `Variant()`（即 JSON `null`）而不是空 `Dictionary`——`null` 是本引擎**已经接受**的写侧形态
（上表试探 2 实测 `code=0`），因此修完后「未设置引用」这一半立刻闭合
（读 `null` → 写 `null` → 读 `null`）。这是**共享序列化器**的一行改动，会影响所有读回工具
（节点读属性、资源读属性……）的输出形态，属**模块级形状决定**；而「**已设置**引用该用什么形状」
（`{"type","value"}` 既不可喂回，也没有「按名引用资源」的约定）是一个需要**决策者**定的设计问题
（候选：`res://` 路径字符串 / `uid://`）。按手册 §7.2「实现者只写报告、规范由决策者维护」，
**本批不改这一行**，只登记缺陷与证据（§10 D-8、§10 next_step 第 1 条）。

## 3. 日志来源矩阵（编辑器/游戏 × 可用/不可用 × 返回形状）

| 回答者进程 | 进程内来源 | 后备文件 | `source` | `in_process` | `available` | 返回形状（两个工具同形） | 实测 |
|---|---|---|---|---|---|---|---|
| 编辑器（9888）| `EditorLog` 面板可读（源码依据：调试器把**本编辑器启动的**游戏子进程输出也路由进 EditorLog，`editor/debugger/script_editor_debugger.cpp:590`；本批证据里的游戏是**独立启动**的，所以实测到的是「游戏日志**不在**编辑器日志里」的那一半）| **不读** | `editor_log` | `true` | `true` | `{errors|lines, count, source, in_process, available, editor:true, process:"editor", pid, port, log_path, note:""}` | `E6_2/E6_3/E6_5/E6_12/E6_16` |
| 编辑器（9888）| 无 `EditorNode`/无面板（理论上：`--test`、或停靠面板未建）| 读 | `log_file` | `false` | `true` | 同上，`source:"log_file"`，`note` = 「共享文件，可能不是本进程」 | 仅单测覆盖（`--test` 进程结构性无 EditorLog） |
| 编辑器（9888）| 同上 | 文件不存在 | `none` | `false` | `false` | 空列表 + `note`（说清试过哪个文件） | 单测（`ScratchLog::remove_file` / 同名目录） |
| 编辑器（9888）| 同上 | 文件存在但打不开（轮转窗口 / 别的进程独占）| `none` | `false` | `false` | 空列表 + `note`（「可能正在被其它 Godot 进程轮转」）| **门②实测**：旧代码同一构造给 `-32603`，新代码给诚实空（新代码里编辑器走 `editor_log`，文件根本没被打开）|
| 游戏（9889）| 无（`EditorLog` 是编辑器独有）| — | — | — | — | **工具不注册**：`tools/list` 无此二者，`tools/call` → `-32601` | `E6_8/E6_9` |

**架构事实（任务书要求说清「现在能不能读到、经哪条通道、为什么」）**：

* **编辑器 ↔ 游戏是跨进程**，没有任何共享内存通道；进程内 `EditorLog` 只能看到**本进程**的消息
  （外加调试器转发来的、由**本编辑器启动**的游戏子进程输出）。
* 共享文件 `user://logs/godot.log` 是**另一条通道**，由**游戏进程**写（PC 上
  `debug/file_logging/enable_file_logging.pc=true`；编辑器被 `main.cpp:2290-2292` 明确排除），
  并且**轮转**（`RotatedFileLogger`，`max_log_files=5`，`core/io/logger.cpp:139-166`）。
  它同时是「存在但不可读」的来源（写句柄 `_SH_DENYRW`，实测外部读失败）。
* 所以：**编辑器端点从此不再返回游戏进程的行**（那是把别人的日志当自己的，E-6 的缺陷本体）；
  走 `editor_play_scene`（E-10，已在 8 月批次落地）**从编辑器起的游戏**，其输出会经调试器
  进入编辑器自己的 `EditorLog`，因此「起游戏 → 立刻看日志」这条路在编辑器端点是**通的**。
  而**独立启动**的游戏进程（例如本批证据里 `--mcp-port=9889` 手起的那个）只有文件通道，
  编辑器端点不会再替它显示——这是 §23.3「来源优先」的**代价**，登记为残留（§9 / §10 B-1）。

## 4. 零字符串手术链（§23.1；调用方字符串处理次数 = **0**）

实测（`E9_12` PASS，编辑器 9888 + 游戏 9889，6 步，全部消费上一步的**字段**）：

```
1 project_read_resource -> .properties = {colors:[{a,b,g,r}×2], offsets:[0.0,1.0],
      interpolation_mode:0, interpolation_color_space:0, resource_local_to_scene:false,
      resource_name:"", script:null}                       (string ops: 0)
2 project_edit_resource(properties = step1 .properties) -> code=0
      .changed.colors.new = [{a,b,g,r}×2]                  (string ops: 0)   ← 整包原样写回
3 project_read_resource -> .properties.colors = 同上        (string ops: 0)   ← 再读仍相等
4 running_game endpoint project_read_resource -> .properties.colors = 同上  (string ops: 0)
5 game endpoint project_edit_resource(colors = step4 .properties.colors) -> code=0
      .changed.colors.new = 同上                            (string ops: 0)
6 game endpoint project_read_resource -> .properties.colors = 同上          (string ops: 0)
```

比较方式：**结构化**比较（PowerShell 里逐键/逐元素比 JSON 值，不比较响应字符串）；
`E9_13` 还对脚本自身的链区做**机械检查**：`.Split(` / `.Replace(` / `.Substring(` / `.Trim(` /
`-match ` / `-replace ` / `[double]` / `[int]` / `[regex]` / `ConvertTo-Json` 全部不得出现 → `forbidden
tokens in the chain region: <none>`。

**闭合范围（必须说清的边界）**：这条链证明的是**标量 / 字符串 / 布尔 / 向量-颜色-矩形对象 /
打包数组**这些类型的读回→写回闭合（`Gradient` 的整包 `properties` 里恰好只含这些 + 一个 NIL 的
`script`）。它**不**证明 OBJECT 引用的闭合——`Environment` 的整包写回**实测 `-32602`**（§2.1），
因为 `serialize_variant` 对空 Object 指针答 `{}` 而写侧不接受 `{}`。这是本批发现的缺陷，
按手册 §7.2 只登记、不自行改共享形状（§10 D-8）。

单测里还有一条同规则的往返（`project_read_resource` → `project_edit_resource` → 再读，断言
`changed.<名>.new == 读回值` 且再读相等），以及一条**活性**断言（经 `project_edit_resource` 改
`interpolation_mode=1` 后**再读**必须为 1 —— 证明读的是文件而不是默认值）。

## 5. 红/绿证据（真实输出）

### 5.1 模块 doctest 红 → 绿（`--headless --test --test-case="[MCPServer]*"`）

* **基线（父提交 `f4339864e`）**：`test cases: 205 | 205 passed | 0 failed | 1429 skipped`，
  `assertions: 8102 | 8102 passed`，`exit 0`。
* **红**（只留新测试 + 新夹具，把实现 `git stash` 掉重建，`build_local.cmd -Force`）：
  `test cases: 208 | 201 passed | **7 failed**`，`assertions: 8157 | 8120 passed | **37 failed**`，
  `Status: FAILURE!`，`exit 1`（log `%TEMP%\t026_red_mcpserver.log`）。失败点直接点名缺口：

  ```
  test_mcp_server.h(2976): CHECK( payload.has("properties") ) is NOT correct!   values: CHECK( false )
  test_mcp_server.h(3040): FATAL ERROR: REQUIRE( stored_value.get_type() == Variant::DICTIONARY )
  test_mcp_server.h(3164): CHECK( total > 64 ) is NOT correct!   values: CHECK( 0 > 64 )
  test_mcp_server.h(3093): CHECK_MESSAGE(!edit_error.is_error(), ...) is NOT correct!
         project_edit_resource refused the value read back: code=-32602
  test_mcp_server.h(3454): CHECK( payload.size() == 11 ) is NOT correct!   values: CHECK( 2 == 11 )
  test_mcp_server.h(3535): CHECK( payload.size() == 11 ) is NOT correct!   values: CHECK( 3 == 11 )
  test_mcp_server.h(3677): CHECK( (String)errors_payload["source"] == "log_file" )   values: CHECK( <null> == log_file )
  test_mcp_server.h(3685): CHECK( (int64_t)errors_payload["pid"] > 0 )               values: CHECK( 0 > 0 )
  test_mcp_server.h(3628): CHECK( (String)payload["source"] == "none" )  values: CHECK( no_log_file == none )
  ```

  （其中 1 条是**测试自身的夹具清点**：新添两个 `.tres` 使夹具文件数 11 → 13，已同步更新并注明；
  它不是产品缺陷，在此显式区分。）
* **绿**（本提交工作树重建后）：`test cases: 209 | 209 passed | **0 failed** | 1429 skipped`，
  `assertions: 8228 | 8228 passed | **0 failed**`，`Status: SUCCESS!`，`exit 0`
  （log `%TEMP%\t026_gate3_final.log`，sha256 `0a3903be…`）。相对基线 **+4 用例 / +126 断言**。

### 5.2 端到端活证据 红 → 绿（`scripts/mcp026_e9_e6_evidence.ps1`，9888/9889）

同一脚本在两种二进制上各跑一遍（脚本自身不改）：

| | 红（旧代码，`git stash` + `-Force` 重建）| 绿（本提交）|
|---|---|---|
| 结果 | **20/37**，`exit 1`（evidence log sha256 `f140c1c8…`）| **37/37**，`exit 0`（evidence log sha256 `330359f8…`）|
| E-9 | `properties keys = []`、`total_properties=`、`truncated=`（**根本不存在**）| 7 条 STORAGE，与引擎侧列表逐项相等 |
| E-6 | 编辑器端点 `source=log_file`（读的是别人的文件）/ 游戏持有时两工具 **`-32603`** / 独占锁时两工具 **`-32603`** | `source=editor_log`、本进程 pid/端口、本进程标记可见、游戏标记**不可见**、任何文件状态下都 `code=0` |
| 链 | `code=-32602`（整包/分量都喂不回去）| 6 步全部 `code=0` 且再读相等 |

关键红字节（可直接核对 sha256）：

```
[E6_editor_output_log_after_game] bytes=125 sha256=f4bb0c2517ade6342e12fbde281a8d3342cb2000e6403c193853f183c2dc6bb6
response: {"error":{"code":-32603,"message":"Internal error: cannot open the log file 'user://logs/godot.log'"},"id":1,"jsonrpc":"2.0"}
[E6_locked_output_log] 同一个 sha256：f4bb0c2517ade6342e12fbde281a8d3342cb2000e6403c193853f183c2dc6bb6
```

> 即：「游戏进程持有」与「外部独占锁」产生**完全相同的旧行为**——独占锁是对轮转窗口的忠实复现。

### 5.3 门② 三类证据（每工具）

| 工具 | 成功 | 缺参 | 底层失败 |
|---|---|---|---|
| `project_read_resource` | 见 §1.1（`E9_1/2/…`）；两端点各一遍（`E9_10`）| `{}` → `-32602 "Missing required parameter: path"`（`E9_8`，sha256 `cb651b9d…`）| `res://resources/does_not_exist.tres` → `-32001 "Resource '…' not found"` + `data.suggestion`（`E9_9`，sha256 `3351f3cd…`）|
| `editor_get_errors` | `source=editor_log` + 本进程错误行（`E6_6`）| `max_lines:"many"` → `-32602`（单测，既有）| 不可用来源 → **诚实空**（`source:"none"` + `note`；单测 + `E6_15`）|
| `editor_get_output_log` | 同上（22 行，`E6_4`）| `filter:3` → `-32602`（单测，既有）| 同上（`E6_15`）|
| `project_edit_resource` / `project_create_resource`（附带修复）| 分量形状写回成功（单测 `the resource writers take the component shapes the readers answer`；活证据 `E9_12` 步 2/5）| `properties` 非对象 → `-32602`（既有）| 资源不可加载 → `-32001` + 建议（既有）|
| **不可构造类声明** | ①**游戏端点上的日志工具**：`scope=editor`，游戏进程不注册 → `-32601`；这不是「工具失败」而是架构事实，已在 §3 说明。②**编辑器端点上的 `log_file`/`none` 形状**：headless 编辑器**恒有**可读 `EditorLog`，所以只能由单测（`--test` 进程结构性无 EditorLog）覆盖；**不是没证据，而是通道不同**。③`Curve.min_value` 那种「示例属性」：见 §10 D-1。| | |

## 6. 门（全部自跑，真实输出与退出码）

| 门 | 命令 | 结果 | 证据（文件 / sha256）|
|---|---|---|---|
| ⓪ 构建绑定 | `build_local.cmd -Force` + `--version` v.s. `git rev-parse --short HEAD` | `exit 0`；`--version` = `4.8.dev.custom_build.f4339864e`，(构建时) HEAD = `f4339864ee` → 匹配 | `%TEMP%\mcp_server_build_local.log` |
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1 -Group project_read_files` | **3/3 PASS，exit 0**；编辑器 91 工具 / 游戏 53 工具；本组 6 条在**两端点** `name/description/inputSchema` 全 True；实现并集 113 == 契约标记数 | `%TEMP%\t026_gate1.out.txt` |
| ② 三类证据 + 端到端活证据 | `scripts\mcp026_e9_e6_evidence.ps1` | **37/37 checks，exit 0** | evidence log sha256 `330359f886e15e0dea1d96f2bd79596181c60ca355fcf54f5558a3163c124876`（`%TEMP%\task026-e9-e6\evidence\`）|
| ②补 缺陷实测（OBJECT 读回） | `scripts\mcp026_object_shape_probe.ps1` | **11/11 checks，exit 0** | evidence log sha256 `4e5b1b63a05b9e631ffe143c67c75164dec7a07ccc53f3f9f251aea16e59cd60`（`%TEMP%\task026-object-shape\evidence\`）|
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **209/209 passed，0 failed，8228/8228 断言，exit 0**（基线 205/8102）| `%TEMP%\t026_gate3_final.log` sha256 `0a3903be5da426b942dadfefbf1d6a6c8bafc969b3b1c85e6913e7e4d0518b33` |
| ④ 全引擎回归 | `--headless --test` | **1635/1635 passed，0 failed，432510/432510 断言，SUCCESS!，exit 0**（上一批：1631/432384）| `%TEMP%\t026_gate4_full.log` sha256 `418b367b553eade0ab03c35cb0c07aad3dc142e85962974091dd390a5c78f23e` |
| ⑤ 批次收口 | `scripts\accept_m1.ps1` **连跑两次** | 两次都 **22/22 PASS，exit 0**，两次 PASS 清单逐条一致（case1..case20 + `guard_user_port_9877` + `gate_scope_declared`；`implemented=113 contract=171`）| `%TEMP%\t026_gate5_run1.out.txt`、`%TEMP%\t026_gate5_run2.out.txt` |
| ⑥ 收窄点清单 | `python scripts\check_narrowing_points.py` | **exit 0**；无 `drifted`、无 `FAIL:`；两个 pin 的行号已按脚本自己的提示更新（`project_write_resource_scene.cpp` 147→183、`tool_helpers.cpp` 986→1051）| `%TEMP%\t026_gate6_final.out.txt` sha256 `8cfd325050def2b17ceff6850864da6b15506811b851b0ebf622c5dde8f1a2e4` |

端口纪律：全程只占 **9888/9889**；用户 Godot 4.7.1-mono 的 **9877（PID 36392）在每次门/证据前后都被读 pid 校验未变**，
从未占用/杀/重启。工作树收尾只剩既有未跟踪物（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、
`install-deps-m0.cmd`）。

## 7. 写侧闭合复核（GDR-25 §23.4）

* 读侧新增的**对象/对象数组**形状（`PackedColorArray` → `[{r,g,b,a}]`）现在**两端点**都能写回：
  节点路径早已走 `prepare_node_property_value`；资源路径本批补上同一步（§1.4）。
* 「不命名分量」的反例仍被拒（既有 `-32602`，消息给出分量表，`tools/running_game_node_write.cpp:507-510/532-535`），
  未把拒绝变成「静默零值」。
* `Color` 分量仍走 `ValueSlot::FLOAT32`（`value_fits_slot` 在 `_check_components` 内），
  没有新增收窄点（门⑥ exit 0 佐证）。
* 仍登记的残留：**OBJECT 值**（§2.1 / D-8，实测双向不闭合）、矩阵/变换族（§23.4 原有欠账，本批未触碰）。

## 8. 改动文件与指纹（sha256，本提交内容）

| 文件 | sha256 | 说明 |
|---|---|---|
| `tools/project_read_files.cpp` | `5a2b8f7e3582803a7688d2d71638be676e0d20f3eff17d77b1d759fe40cdb013` | E-9：STORAGE 属性 + 限量/截断 |
| `tools/project_write_resource_scene.cpp` | `b30cae0a69f93f177df2acfa7f86498de5a4c88bd3f48fe341c5ed31759dd9c1` | §1.4 分量整形补步 |
| `tools/editor_read_scene_inspector.cpp` | `8407d8fc3fb4995a40d0ca7b4c6b7851a1c84223bb8ffb81be3980732a1dfa6b` | E-6+G-4：来源选择 + 统一来源块 |
| `tools/tool_helpers.h` | `523b4135bcf946e0cf2bff75be1b9459a59564894cf5a096e3103375f7db697a` | `editor_log_lines()` 声明 |
| `tools/tool_helpers.cpp` | `bebe56b240d6f43d4252b1b0b462b9ecca78de828dab9d578431356d14e9570c` | `editor_log_lines()` 定义 + 面板查找 |
| `tests/test_mcp_server.h` | `6eee488c77b3918cf4286ab2293cb45c6048aa292c10e1ae3fd6fc028b9ac8f4` | +4 用例（3 个新增 + 1 个重写）+ 2 个新夹具 |
| `scripts/mcp026_e9_e6_evidence.ps1` | `68f318b3a5180954bdaabf759715589064c94171107cf07c47101cbc88e8e54c` | 门②证据脚本（新） |
| `scripts/mcp026_object_shape_probe.ps1` | `e028833a2b7463700fda1473d5672129493d6f86cce79261bb03f1c1f7e1b17d` | §2.1 的 OBJECT 读回缺陷实测脚本（新，自包含） |
| `scripts/check_narrowing_points.py` | `6aaabd67df4ec2641ccddf39eb30cb0ffcacb0f46263cee1932baee7900665a2` | 仅两个 pin 行号 |

**契约/映射/生成器**：`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、`docs/tool-groups*.json`
**本批零改动**（未 `git add`、未出现在本提交），因此文档指纹与 `_meta.map_sha256` 不变。

## 9. 仍未处理的顺手性项（本批未领）

| 项 | 现状（M4c 口径）| 引擎正解 | 建议归属 |
|---|---|---|---|
| **E-2** | `editor_get_scene_tree` 返回编辑器 UI 内部绝对路径（`/root/@EditorNode@…/@SubViewport@9998/Main/Actor`，含 8 个内部 `@` 节点），与契约口径「相对于场景根的节点路径」不一致；对照游戏侧是 `/root/Main/Actor` | `NodePath get_path_to(const Node*, bool p_use_unique_path)`（`scene/main/node.h:573`）；本 fork 还有每节点稳定 `unique_id`（`node.h:554`、`node.cpp:2139`）| 独立小批（编辑器「读场景树」的口径统一）|
| **E-8** | 同源：`editor_set_node_property` 的**错误消息**里回显同一条内部绝对路径，而成功响应里 `node_path` 是 `"Actor"`（同一工具两套口径）| 同上（`relative_path()` 模块里已有）| 与 E-2 合并一批 |
| **G-1** | 没有子属性路径：`editor_set_node_property` 不接受 `position:y` / `v4:x`（实测 `-32001`）；要改 `material.albedo_color`、`shape.radius` 只能「取/建资源 → 写资源 → 赋回节点」多趟 | `Object::set_indexed()` / `get_indexed()`（`core/object/object.h:697-698`、`object.cpp:475-532`），编辑器 Inspector 自己就用它 | 独立批次（参数语义扩展，可能须动 schema）|
| **G-3** | `editor_get_test_report` 的 `clear` 默认 `true` 且**删除共享桥接文件**：多客户端下一次读取会清掉别人还没读的报告（读的语义带破坏性副作用）| 把默认改为「不删」或增显式 `clear` 断层（须决策）| 决策者裁决（契约/schema 影响）|
| 本批新增残留 | 见 §3 末与 §10 B-1：独立启动的游戏进程日志不再出现在编辑器端点；共享文件仍是唯一跨进程通道 | 若要在编辑器端点显式读共享文件，需要新参数（`SCHEMA_OVERRIDES`，属决策者权限）| 决策者裁决 |
| **OBJECT 读回形状不闭合**（本批新发现，§2.1 / D-8）| `{}` 读得出、写不进；换 `null` 写进去读回仍是 `{}` → OBJECT 属性双向不闭合；E-9 因此对含 Object 属性的资源（如 `Environment`）无法整包喂回 | `serialize_variant` 对空 Object 指针答 `null`（一行，已实测写侧接受）；「已设置引用」需要一个新的形状约定（`res://` 路径 / `uid://`）| **决策者裁决**（模块级形状决定）|

## 10. deviations / blockers / next_step

### deviations（逐条显式）

* **D-1（任务书示例与引擎事实不符）**：任务书写「读资源拿到属性**如 `Curve.min_value`**」。
  实测/源码：`Curve` 的 `min_value`/`max_value`/`min_domain`/`max_domain` 声明为
  `PROPERTY_USAGE_EDITOR`（**无 STORAGE**，`scene/resources/curve.cpp:640-643`），是从 `_data`
  派生出来的编辑期属性；`Curve` 真正的 7 个 STORAGE 属性是 `_limits`、`bake_resolution`、`_data`、
  `point_count`（`ADD_ARRAY_COUNT`）、`resource_local_to_scene`、`resource_name`、`script`
  （正好等于 M4c 量到的 7）。任务书要求 1 明确「取 STORAGE 的属性」，所以本实现**不给**
  `min_value`；链式喂回改用 `Gradient.colors`（对象数组，更强的 §23.4 例）+ 整包 `properties`。
  **请决策者确认**：这是「按任务书要求 1 的字面执行」，若希望「派生属性也可见」，需另立一项并说明口径。
* **D-2（超出两项字面的第三张脸）**：见 §1.4——为满足 E-9 要求 4，改了 `project_edit_resource` /
  `project_create_resource`（同模块、`modules/mcp_server/**` 内、无契约变更）。若不接受，可回退
  这两个文件而不影响其余两项；但那样 E-9 的链式喂回对分量形状不成立（红证据 §5.1 `E9_12` 就是它）。
* **D-3（`source` 取值词汇变化）**：`editor_get_output_log` 的 `source` 由迁移源的
  `log_file`/`no_log_file` 改为 `editor_log`/`log_file`/`none`（§23.3 指定了前两者；
  「都不可用」用 `none` + `available:false` + `note` 表达）。这是 G-4 要求的形状统一，
  属**输出形状**变化，不在 `inputSchema` 内，故未动契约；若决策者要求保留 `no_log_file` 拼写，
  需要一次显式决定。
* **D-4（构建 hash 的时序）**：见 §0 末尾——门在提交前跑，二进制自报父提交 hash；内容由
  `git status` 证明一致。
* **D-5（门⑥ pin 行号）**：按脚本自身提示更新了两个 pin 的行号（不是绕过失败；不更新也 `exit 0`，
  只是会留下 `drifted` 提示）。
* **D-6（残余重复）**：`tools/tool_helpers.cpp` 新加的 `_editor_log_view()` 与
  `tools/editor_write_scene_editor.cpp` 里 `editor_remove_output_log` 用的文件私有同名 walker
  是**重复逻辑**。本次**没有**去重构另一组的文件（PLAYBOOK §2.4 的组边界），登记为后续
  「hoist 修复批」的候选（与 TASK-017 的 `_relative_path` 合并同类项）。
* **D-7（`editor_log_lines()` 的语义边界）**：它读的是**面板渲染出来的文本**（`RichTextLabel`
  的 `get_parsed_text()`）：`ERROR:`/`WARNING:` 前缀在里面，用户关掉的类型过滤器、搜索框内容、
  进入树之前到达的消息**不在**里面，面板自身还有 10000 行上限。这已在 `tool_helpers.h` 与
  `tool_helpers.cpp` 就地写明；若决策者要求「无论如何都是全量消息」，需要引擎给 `EditorLog` 一个
  公开读取口（越出本模块权限，须报给引擎侧）。
* **D-8（发现但未自行修：OBJECT 读回形状不闭合）**：见 §2.1。E-9 是第一个读回 OBJECT 值的工具，
  实测 `{}`（空 Object）**既能被读侧答出、又绝不可能被写侧接受**，且换成 `null` 写进去读回仍是 `{}`
  → OBJECT 属性双向不闭合。最小修法是一行（`serialize_variant` 对空 Object 指针答 `null`），
  但它是**全模块共享的形状决定**（所有读属性工具的输出一起变），且「已设置引用」还缺一个形状约定
  → 按 `PLAYBOOK` §7.2「实现者不得创建竞争性规范 / 认为规范有误就报缺陷」，本批**只报不改**，
  请决策者裁决。**注意**：这不影响本批两项的验收对象（E-9 的标量/向量/颜色/数组值、E-6 的来源块），
  但它是 E-9 走向「所有读回都可喂回」的**唯一拦路项**。

### blockers

* 无。端口 9877 未受影响；无网络/依赖受阻；无未决构建错误。

### next_step_recommendation

1. **先裁决 D-8（OBJECT 读回形状）**：这是 E-9 唯一未闭合的读回类型，一行改动即可闭合「未设置引用」
   的一半（`serialize_variant` 空 Object → `null`，写侧已实测接受），另一半（已设置引用）需要
   一个形状约定。它同时影响节点读属性工具的同类输出，属模块级决定。
2. **请决策者再裁决 D-1 / D-2 / D-3**（三项都会影响「E-9/E-6 的验收口径」与是否要保持旧拼写）。
3. 若要「编辑器端点也能显式读共享文件（别的进程的日志）」，请决定是否走 `SCHEMA_OVERRIDES`
   （可选 `source` 参数：`auto`/`editor_log`/`log_file`）——本批**没有**擅自加参数。
4. 建议下一批处理 **E-2 + E-8**（同根因，一次改完两个工具的口径），随后 **G-1**，最后 **G-3**。
5. 若需要「二进制 hash == 当前 HEAD」的严格绑定，请在本提交上重建一次并重跑门③④①⑤（约 15 min）。