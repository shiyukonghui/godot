# REPORT-017 — B3 第三批：批量写 / Control 布局写 / setup 族（10 工具）

- `status`: **done**（五道门在本机全绿；有一例「契约层面的死分支」与若干「doctest 进程无法构造」的
  限制，均在下方显式记录，未伪装通过）
- **（最终修复轮，见 §15）** 独立验收发现的 1 个过程阻断 + 4 个缺陷已在本轮关闭：二进制重新绑定到
  HEAD、`editor_setup_camera_3d` 的创建分支真正实现（原「死分支」结论被证伪并原地更正）、
  §14.4(a) 的假 grep 声明与 §14.4(b) 的脆计数均替换为真实输出/可复现方法。本文件上方的
  `§2` / `§4` / `§11` / `§13` / `§14.4` / `§14.7` 中与 §15 冲突的句子都已原地标注更正。
- `branch`: `feature/mcp-server-module`（**未 push**）
- `task`: `modules/mcp_server/docs/tasks/TASK-017-b3-batch-layout-setup.md`
- 实现者：单个串行 implementer（D3）；构建串行，任何时刻只有一个 `scons`。

## 1. 提交与门绑定证据

| # | commit | 一行说明 |
|---|---|---|
| 1 | `787c5e7538` | `mcp_server: append exactly one " not found" suffix in MCPToolError::not_found (TASK-017 section 3)` |
| 2 | `568119c360` | `mcp_server: hoist instantiate_class/object_has_property and widen write_node_property to Object (TASK-017 section 4)` |
| 3 | `01f0606361` | `mcp_server: port B3 editor_node_batch_write, editor_control_layout_write, editor_node_setup (TASK-017 section 2)` |
| 4 | `8594eceda1` | `mcp_server: TASK-017 registration, manifest flags, tests, gate-2 evidence script and M1 union` |

门绑定（`--version` 的 9 位哈希前缀 == `git rev-parse --short HEAD` 的前 9 位）：

| 阶段 | `git rev-parse --short HEAD` | `--version` | 结论 |
|---|---|---|---|
| 提交前（①②③④⑤ 首轮） | `1af7d21647` | `4.8.dev.custom_build.1af7d2164` | 匹配 |
| 提交后（重建；③④①②⑤ 复核） | `8594eceda1` | `4.8.dev.custom_build.8594eceda` | 匹配 |

本报告遵循 REPORT-016 先例：**五道门在提交前、提交后各跑一轮**（提交本身不改变源码内容，重建只重生成
`core/version_hash.gen.cpp` 并重新链接）。

构建：`modules\mcp_server\scripts\build_local.cmd`（`tests=yes`，日志落 `%TEMP%`）。

| 构建 | 日志 | EXIT_CODE |
|---|---|---|
| 红（第 1 轮：测试自身编译错，`Control::SIDE_LEFT`） | `%TEMP%\mcp017_red.log` | 2 |
| 红（第 2 轮：三个组的实现不存在 → 链接失败） | `%TEMP%\mcp017_red2.log` | 2 |
| 绿（实现齐备） | `%TEMP%\mcp017_green2.log` | 0 |
| 绿（测试修正后） | `%TEMP%\mcp017_green7.log` / `green8.log` | 0 / 0 |
| 绿（提交后重建） | `%TEMP%\mcp017_postcommit.log` | 0 |

二进制 sha256：`550c35cdea3c5ba65412a7f0de036b8e8bc6d4f037351833b4271ee5a32bf425`
（`bin\godot.windows.editor.x86_64.console.exe`，提交后重建版本）

## 2. 每工具表

| new_name | 迁移源位置（只读参考） | 可观察契约（实现值） | C++ 位置 | 与迁移源的偏差 |
|---|---|---|---|---|
| `editor_add_nodes_batch` | `batch.rs:270` `cmd_batch_add_nodes` | `nodes` 非空数组；全成功 → `{status:"ok",created[],count,errors:[]}`；任一元素失败 → 单条 `-32001`/`-32602`，`result=null`，`error.data.batch` 携带 `{status:"rolled_back",created:[],count:0,errors[],rolled_back[],on_error:"all_or_nothing"}` | `tools/editor_node_batch_write.cpp` | 迁移源逐元素 `continue` 后仍回 `{"created":...}`（**半成品 + 成功信封**）；本实现全有或全无并回滚 |
| `editor_set_node_property_batch` | `batch.rs:147` `cmd_batch_set_property` | 目标集 = `get_class()==type \|\| is_class(type)` 自然前序；无匹配 → `-32001`；任一匹配节点不声明属性 → 写前 `-32001`；中途写失败 → 恢复旧值后再报错；成功 → `{updated,property,node_type,status:"ok",nodes[],count}` | `tools/editor_node_batch_write.cpp` | 迁移源无匹配时回 `updated:0` 成功、完全不检查属性是否存在；本实现两个都拒绝 |
| `editor_set_anchor_preset` | `node.rs:408` | 16 个预设名（区分大小写）→ `Control::LayoutPreset`；非 `Control` → `-32602`（含实际类名）；非法名 → `-32602` 列出全部合法名；`keep_offsets` 选 `PRESET_MODE_KEEP_SIZE`/`PRESET_MODE_MINSIZE`；回 `{"node_path","preset"}` | `tools/editor_control_layout_write.cpp` | 一致（仅 `KEEP_SIZE` 的引擎拼写为 `PRESET_MODE_KEEP_SIZE`） |
| `editor_setup_camera_3d` | `scene_3d.rs:85` | 命中且是 `Camera3D` → `set_current(true)` 并回读（`created:false`）；命中是 `Node3D`（非相机）→ 在其下新建名为 `Camera3D` 的相机（`owner`=场景根、`set_current(true)`、新路径由引擎回读，`created:true`）；命中其它类 → `-32602`（含实际类名）且**建前**拒绝；未命中 → `-32001`；回 `{setup,created,node_path,type,current}` | `tools/editor_node_setup.cpp` | **（修复轮更正，见 §15.1）** 原表述「命中非相机一律 `-32602`、创建分支不可达（迁移源同分支也是死代码）」只对**非 `Node3D`** 命中成立：同一路径两次 `find_node` 都命中时，旧代码在第二次解析前就返回了。现按命中的**类**分流（单参数 `node_path` 下唯一可用的边界，契约没有 `parent_path`），创建分支可达并由门②线上钉死；响应形状按 TASK-017 §3.4 扩展 |
| `editor_setup_collision_shape` | `physics.rs:85` | `shape_params` 写入形状资源；碰撞节点类由资源自身种类派生（`Shape2D`→`CollisionShape2D`，`Shape3D`→`CollisionShape3D`）；未知/非形状类 → `-32602` 列出支持名；回 `{setup,node_path,shape_type,collision_node_path,collision_node_type,shape_set}`（`shape_set` 引擎回读） | `tools/editor_node_setup.cpp` | `_shape_params` 被忽略 → 现在真正写入；未知 `shape_type` 静默退化为 2D 矩形 → 现在拒绝 |
| `editor_setup_world_environment` | `scene_3d.rs:162` `cmd_setup_environment` | 有 `world_env_path` → 命中须是 `WorldEnvironment`（否则 `-32602`），未命中则按路径末段命名新建；无路径 → 复用根下第一个 `WorldEnvironment`，否则新建；确保 `Environment` 存在；`bg_color` → `set_background(BG_COLOR)`+`set_bg_color`；`ambient_color` → `set_ambient_source(AMBIENT_SOURCE_COLOR)`+`set_ambient_light_color`；回 `{setup,world_environment,world_environment_path,world_environment_created,environment_created}` | `tools/editor_node_setup.cpp` | 不跑 GDScript `Expression` 而用直接 C++ 调用；补上 `ambient_source` 切换（否则颜色无效果）；`world_env_path` 只当节点路径（不加载资源）；响应形状扩展 |
| `editor_setup_lighting` | `scene_3d.rs:104` | `directional`/`omni`/`spot`（大小写不敏感，已记录）→ `DirectionalLight3D`/`OmniLight3D`/`SpotLight3D`；其它 → `-32602` 列出三值；节点名用真实类名；回 `{setup,light_type,node_path,type}` | `tools/editor_node_setup.cpp` | 迁移源「非 directional 一律 OmniLight」并命名为 `DirectionalLight`/`OmniLight` → 现在拒绝未知值并命名真实类名（读回证据需要） |
| `editor_setup_navigation_agent` | `navigation.rs:231` | `agent_type` 精确 `2D`/`3D`（区分大小写）；父或其祖先须是对应 `Node2D`/`Node3D`，否则建前 `-32000`；`radius`/`max_speed` 回读；回 `{setup,node_path,type,radius,max_speed,created}` | `tools/editor_node_setup.cpp` | 新增上下文拒绝（否则引擎拒绝 add_child 并留孤儿）；回读而非回显 |
| `editor_setup_navigation_region` | `navigation.rs:104` | `mode` ∈ `2d`/`3d`/`auto`（大小写不敏感）；`auto`：父/祖先 `Node3D` → 3D，`Node2D` → 2D，否则**默认 3D**；父无对应上下文 → 建前 `-32000`；3D 建 `NavigationRegion3D`+`NavigationMesh`（`agent_radius`/`cell_size`/`agent_height`），2D 建 `NavigationRegion2D`+`NavigationPolygon`（`agent_radius`/`cell_size`）；回读资源值 | `tools/editor_node_setup.cpp` | `is_3d_context` 的 `false`（2D）兜底 → 本实现默认 **3D**（契约 `name` 默认值为 `NavigationRegion3D`），已记录；回读而非回显；新增上下文拒绝 |
| `editor_setup_physics_body` | `physics.rs:189` | `body_type` 须存在、是 `Node` 子类、且派生 `PhysicsBody2D`/`PhysicsBody3D`，否则 `-32602` 说明原因；回 `{setup,parent_path,body_type,name,node_path,type,created}` | `tools/editor_node_setup.cpp` | 迁移源接受**任意** Node 子类（工具名失真）→ 现在要求真是物理体；响应形状扩展 |

十者均 `channel=editor`、`scope=editor`、`mutating=true`（`docs/tool-rename-map.json`），均以
`MCP_EDITOR_TOOLS_ENABLED` 守卫 body，9889 全缺席、直接调用 `-32601`。

## 3. 红 → 绿（真实输出）

三个组共用一个 doctest 二进制，因此红证据是一次覆盖三组全部 13 个导出入口 + 3 个注册函数的链接失败
（TDD 的红：**被测行为尚不存在**）。

红（`%TEMP%\mcp017_red2.log`，`EXIT_CODE=2`，只节选 ASCII 可辨部分）：

```
tests...test_main... : error LNK2019: unresolved external symbol
  "char const * const * __cdecl MCPTools::layout_preset_names(int &)"     <- editor_control_layout_write
  "bool __cdecl MCPTools::layout_preset_from_name(...)"                  <- editor_control_layout_write
  "class Variant __cdecl MCPTools::apply_anchor_preset_on(...)"          <- editor_control_layout_write
  "class Variant __cdecl MCPTools::add_nodes_batch_on(...)"              <- editor_node_batch_write
  "class Variant __cdecl MCPTools::set_node_property_batch_on(...)"      <- editor_node_batch_write
  "class Variant __cdecl MCPTools::setup_camera_3d_on(...)"              <- editor_node_setup
  "class Variant __cdecl MCPTools::setup_collision_shape_on(...)"        <- editor_node_setup
  "class Variant __cdecl MCPTools::setup_world_environment_on(...)"      <- editor_node_setup
  "class Variant __cdecl MCPTools::setup_lighting_on(...)"               <- editor_node_setup
  "class Variant __cdecl MCPTools::setup_navigation_region_on(...)"      <- editor_node_setup
  "class Variant __cdecl MCPTools::setup_navigation_agent_on(...)"       <- editor_node_setup
  "class Variant __cdecl MCPTools::setup_physics_body_on(...)"           <- editor_node_setup
module_mcp_server...registration... : error LNK2019:
  "void __cdecl register_editor_node_batch_write_tools(...)"
  "void __cdecl register_editor_control_layout_write_tools(...)"
  "void __cdecl register_editor_node_setup_tools(...)"
bin\godot.windows.editor.x86_64.exe : fatal error LNK1120: 15 unresolved externals
INFO: Time elapsed: 00:00:32.82
EXIT_CODE=2
```

（更早的第 1 轮红还包含测试自身的 `Control::SIDE_LEFT` 编译错——本 fork 的 `Side` 是
`core/math/math_defs.h` 的全局枚举，不是 `Control` 的成员；已改正。）

绿（同一构建脚本）：

```
Compiling modules\mcp_server\tools\editor_node_batch_write.cpp ...
Linking Program bin\godot.windows.editor.x86_64.console.exe ...
Linking Program bin\godot.windows.editor.x86_64.console.exe (console wrapper) ...
scons: done building targets.
INFO: Time elapsed: 00:00:30.88
EXIT_CODE=0
```

模块 doctest 绿：

```
[doctest] test cases:  156 |  156 passed | 0 failed | 1429 skipped
[doctest] assertions: 5807 | 5807 passed | 0 failed |
```

测试用例（15 例，含 1 例注册/作用域、1 例 `not_found` 形态断言）：批量全成功/重复名/三种中间失败/
属性缺失；属性批量成功 + 基类匹配 + 无匹配 + 全有或全无；锚点映射 + 几何 + `keep_offsets` 模式；
camera/碰撞/世界环境/光照/导航代理/导航区域/物理体的拒绝类；十条工具的参数拒绝。

## 4. 五道门（真实输出与 exit code）

| 门 | 命令 | 结果 | exit |
|---|---|---|---|
| ① 契约子集（每组一次） | `check_contract_subset.ps1 -Group <g>` | `editor_node_batch_write` `3/3 checks passed`；`editor_control_layout_write` `3/3`；`editor_node_setup` `3/3`；每个工具 `name/description/inputSchema` 全 True，9889 全「correctly absent」 | 0 / 0 / 0 |
| ② 三类证据 + scope + 链 + 批量计数 + setup 读回 | `mcp017_batch_layout_setup_evidence.ps1` | `84/84 checks passed` | 0 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | `156/156` 用例、`5807/5807` 断言、0 failed | 0 |
| ④ 全引擎回归（仓库根） | `--headless --test` | `1582/1582` 用例、`430089/430089` 断言、0 failed、3 skipped | 0 |
| ⑤ 批量收口 ×2 | `accept_m1.ps1` | `22/22 cases passed` ×2，两次 PASS 清单由实现者用 `Compare-Object` 比较（结果为空，即逐条一致）——脚本本身**不**输出任何 `PASS-SET-IDENTICAL` 之类的 token（原文此处引用了不存在的脚本断言，已在修复轮改正，见 §14 D5） | 0 / 0 |

基线对照（REPORT-016）：③ 139/139 · 5185 → 本次 156/156 · 5807（+17 用例 / +622 断言）；
④ 1565/1565 · 429467 → 本次 1582/1582 · 430089（同增量）。

提交后复核（`8594eceda` 绑定）：① 3/3×3、② 84/84、③ 156/156、④ 1582/1582、⑤ 22/22×2 全绿。

### 门② 关键线上片段（`curl.exe -s -o`，sha256 由响应字节算出）

成功批量（`batch_01_good`，sha256 `3fec0b59fc633dd88232a26eae509cc61394ad9466f11fbcfeb2f45b36161ab4`）：

```json
{"count":3,"created":[{"index":0,"name":"Ok1","node_path":"Ok1","parent_path":".","type":"Node2D"},
{"index":1,"name":"Ok2","node_path":"World3D/Ok2","parent_path":"World3D","type":"Node2D"},
{"index":2,"name":"Ok3","node_path":"Ok3","parent_path":".","type":"Node2D"}],"errors":[],"status":"ok"}
```

**中间失败反例**（`batch_05_bad_middle_parent`，627 bytes，sha256 `41798edc9d4b39709703ed5a634e72213d85873c471a1c18a88f15f903a36bdd`）：

请求：
```json
{"method":"tools/call","params":{"arguments":{"nodes":[{"name":"BadB1","type":"Node2D"},
{"parent_path":"NoSuchParentXYZ","name":"BadB2","type":"Node2D"},{"name":"BadB3","type":"Node2D"}]},
"name":"editor_add_nodes_batch"},"id":1,"jsonrpc":"2.0"}
```
响应（`error` 非空、`result` 为 null、`status` 为 `rolled_back`）：
```json
{"error":{"code":-32001,"data":{"batch":{"count":0,"created":[],
"errors":[{"index":1,"parent_path":"NoSuchParentXYZ","property":"","reason":"Parent 'NoSuchParentXYZ' not found","type":"Node2D"}],
"on_error":"all_or_nothing","rolled_back":[{"index":0,"node_path":"BadB1","reason":"transaction rollback","type":"Node2D"}],
"status":"rolled_back"},"suggestion":"editor_add_nodes_batch is all-or-nothing: ..."},
"message":"nodes[1]: parent 'NoSuchParentXYZ' not found"},"id":1,"jsonrpc":"2.0"}
```
同形反例 `batch_04_bad_middle_type`（`NoSuchTypeXYZ`）→ `-32602`，
sha256 `ed953f890758eb3f3a053a2ab7e9d6c910bc5ef66dfd291186a04aabc4ea3a8c`。

属性批量全有或全无（`prop_06_partial_property`，sha256
`85f30274e9e93b94a4db3a042f951a6fa24a189f86933826ff00fa1cda5f4e34`）：

```json
{"error":{"code":-32001,"data":{"suggestion":"Every matched node must declare the property. ..."},
"message":"Property 'texture' on node '.' not found"},"id":1,"jsonrpc":"2.0"}
```
随后 `editor_get_node_properties {path:"A",properties:["position"]}` 仍为 `{x:3.0,y:4.0}`（证明无成员被改）。

**「不可构造」声明**：`editor_setup_world_environment`、`editor_setup_lighting`、
`editor_setup_physics_body` 的契约 `required: []`，因此**没有**「缺必填参数」这一失败类；三者改用
底层失败类（非法颜色 / 非法 `light_type` / 非法 `body_type` / 缺失父节点）。
`editor_setup_camera_3d` 的「创建」分支**（修复轮更正，见 §15.1：原文称其不可达，该说法为假）**
在命中 `Node3D` 父节点时可达，门② 的线上链 `setup_03b_camera_create_under_parent` →
`setup_03c_read_created_camera` / `setup_03d_read_created_camera_current` 即取自该路径；「配置已存在
相机」路径仍保留为 `setup_01_camera` / `setup_02_read_camera` / `setup_03_read_camera_props`。

`%TEMP%` 临时工程：editor（无 main_scene）与 game（有 main_scene）两个 `project.godot`；`.tscn`
用 `WriteAllBytes(UTF8.GetBytes(...))` 写（**无 BOM**）；两个工程 `--import` 均 `exit 0`（attempts 1/1）。

## 5. 批量事务语义与中间失败反例

**选择：全有或全无（all-or-nothing with rollback）**，理由：

1. 迁移源 `batch_add_nodes` 先加后错、仍回成功信封（`batch.rs:291-402`），调用方无法区分「全做了」与
   「做了一半」——这正是 PLAYBOOK §6.6 / 本模块 G-6.6 明令禁止的失败模式；
2. 逐元素结果（partial success + per-element errors）虽然信息更多，但它把「请求 N 个、实际建了 k 个」
   的收尾责任推给调用方：编辑器场景一旦被留下半成品，下一句 `editor_save_scene` 就会把半成品写盘；
3. 回滚成本可控：prepare 阶段**不 attach**，失败时按逆序 `memdelete` 未挂树的节点，代价 O(N) 且不触碰现场；
4. `editor_set_node_property_batch` 同理：先收集目标集、先验证属性在**所有**匹配节点上都存在，才允许
   第一次写入；中途写失败则按逆序恢复已写节点的旧值。

线上反例（§4）证明：`[good, {parent missing}, good]` 与 `[good, {unknown type}, good]` 之后，
`editor_find_nodes_by_type {type:"Node2D"}` 得到的路径集合为 `., A, B, World3D/Ok2, Ok1, Ok3`，
**没有任何 BadB1/BadA1/BadA3**（`leftovers=[]`），即第一个成功 prepare 的元素也被收回。

## 6. 7 个 setup 族的读回证据表

| setup 工具 | 创建/配置的东西 | 独立读族工具 | 读回值 |
|---|---|---|---|
| `editor_setup_camera_3d` | `World3D/WorldCamera`（Camera3D，`set_current(true)`） | `editor_find_nodes_by_type` + `editor_get_node_properties` | path=`World3D/WorldCamera`；`current=true` |
| `editor_setup_collision_shape` | `A/CollisionShape2D` + `RectangleShape2D`（`size={x:32,y:32}`） | `editor_find_nodes_by_type` + `editor_get_node_properties` | `A/CollisionShape2D`；`shape.type=RectangleShape2D` |
| `editor_setup_world_environment` | `WorldEnvironment` + `Environment` | `editor_find_nodes_by_type` + `editor_get_node_properties` + `editor_save_scene` → `project_read_scene_file_content` | `WorldEnvironment`；`environment.type=Environment`；落盘 `background_color = Color(0.1, 0.2, 0.3, 1)`、`ambient_light_color = Color(0.4, 0.5, 0.6, 1)`、`ambient_light_source = 2` |
| `editor_setup_lighting` | `DirectionalLight3D` | `editor_find_nodes_by_type` | `DirectionalLight3D` |
| `editor_setup_navigation_agent` | `World3D/Agent3D`（NavigationAgent3D） | `editor_find_nodes_by_type` + `editor_get_node_properties` | `World3D/Agent3D`；`radius=0.75`、`max_speed=12.0` |
| `editor_setup_navigation_region` | `World3D/Region3D`（NavigationRegion3D + NavigationMesh，`mode=auto` → 3D） | `editor_find_nodes_by_type` + `editor_get_node_properties` | `World3D/Region3D`；`navigation_mesh.type=NavigationMesh`；响应回读 `agent_radius=0.5`、`cell_size=0.25` |
| `editor_setup_physics_body` | `Body1`（RigidBody2D） | `editor_find_nodes_by_type` | `Body1` |

跨工具链（每组一条）：批量建 `Control`+`RigidBody2D` → `editor_set_anchor_preset(full_rect)` →
读 `anchor_left=0 / anchor_right=1`；对该 body `editor_setup_collision_shape(CircleShape2D)` →
读 `ChainBody/CollisionShape2D` 且 `shape.type=CircleShape2D`；批量建 2 个 Node2D →
`editor_set_node_property_batch(position={21,22})` → 读 `PropBatch1.position={21.0,22.0}`。

## 7. 文案缺陷前后对照（TASK-017 §3）

改动点：`modules/mcp_server/tool_registry.cpp` `MCPToolError::not_found()`。

| | 代码 | 一个已带后缀的 `p_what` 的结果 | 现场消息 |
|---|---|---|---|
| before | `error.message = p_what + " not found";` | `"Node 'x' not found"` → `"Node 'x' not found not found"` | `Property 'script' on node 'A' is not readable by name not found` |
| after | `error.message = p_what.ends_with(" not found") ? p_what : p_what + " not found";` | `"Node 'x' not found"` → `"Node 'x' not found"` | 同上（**未变**） |

**（本节结论已在修复轮更正，见 §14 D1）** 该修复**不是**防御性的，它在今天的线上就载重：
`tools/editor_node_batch_write.cpp` 的 `_transaction_fail`（`:160`）把 `write_node_property`
已经用 `MCPToolError::not_found` 拼好的 `property_error.message`（`running_game_node_write.cpp:258`）
再交给 `MCPToolError::not_found`，因此 `editor_add_nodes_batch` 的**元素属性校验拒绝**路径会触发双后缀：

| | `editor_add_nodes_batch` 属性拒绝的 `error.message`（index 1） |
|---|---|
| before | `nodes[1]: Property 'NoSuchPropertyXYZ' on node '' not found not found` |
| after | `nodes[1]: Property 'NoSuchPropertyXYZ' on node '' not found` |

修复前 §7 曾声称「树中没有任何调用点传入已带后缀的 `p_what`，故线上消息逐字节不变」；该声称是**错的**
（它只检查了直接 `not_found(...)` 调用点的字面量，看不到 helper 运行时转发的值），修复轮已删除该声称，
把门②的 `text_no_caller_with_suffixed_p_what` 换成了对真实响应体的断言，并在 §14.2 给出真实响应体与红/绿输出。
其余调用点（`p_what` 不以 `" not found"` 结尾者）的消息确实逐字节不变，这一点由门②的
`text_01_not_readable_by_name` / `text_02_plain_not_found` 与 §14.4(b) 的 wire 对比佐证。doctest 形态：

```
plain    : "Node 'x'"                                   -> "Node 'x' not found"
already  : "Property 'p' on node 'n' is not readable by name" -> "... not readable by name not found" (count(" not found")==1)
suffixed : "Node 'x' not found"                          -> "Node 'x' not found"   (count==1, find(" not found not found")<0)
```

线上捕获（`text_01_not_readable_by_name`，sha256
`83eac0c599ceb9d05270976c7855a8931ab2d30dd007a69494ec3e87e19eb6a1`）：

```
code=-32001 message='Property 'script' on node 'A' is not readable by name not found'
```

## 8. 本批后已实现总数与剩余计数

`accept_m1.ps1` 收口输出：

```
implemented tools      : 96 / contract 171
process split          : editor endpoint 79 tool(s), game endpoint 40 tool(s), editor-only 56, game-only 17
equality gate coverage : 79 tool(s) compared verbatim on the editor endpoint
```

- 已实现 **86 → 96**（+10）；契约总数 **171**；剩余 **75**；
- B3 批次 **20 → 30 / 40**（本批 30 = `editor_node_write` 10 + `editor_node_instantiate` 4 +
  `editor_node_read` 6 + 本批 10）；
- 编辑器端点 **69 → 79**，游戏端点 **40**（不变）；`get_tool_count()` 86→96、
  `get_visible_tool_count(true)` 69→79、`editor_list.size()` 69→79（测试内 6/6/5 处全改，
  复检无残留）。

## 9. 触碰文件的 sha256

> **修复轮说明（见 §14）**：下表是**修复前**的 sha256；下表中被修复轮改动的文件（`tool_helpers.*`、
> `editor_node_write.cpp`、`editor_control_layout_write.cpp`、`editor_node_batch_write.cpp`、
> `editor_node_setup.cpp`、`tests/test_mcp_server.h`、`mcp017_batch_layout_setup_evidence.ps1`、
> 二进制）的新值见 §14.7。`tool_registry.cpp` 行不变（修复轮的临时回退仅用于红相位，最终状态与
> 下表一致）。

| sha256 | 文件 |
|---|---|
| `d7a5fcac39582821506c757db203cb32ecc2f18211b7027523bcc1e734cc73b6` | `modules/mcp_server/tool_registry.cpp` |
| `1fad2119c24422945bcf984bfbbc7ebdc7841f615400c061ebd893e6db240cd3` | `modules/mcp_server/tools/tool_helpers.h` |
| `580a18f9565557927cf068a1ee1756ffe66fbf9c5ebc32fcd75f0628f31d7708` | `modules/mcp_server/tools/tool_helpers.cpp` |
| `dfba9883db3ce96e0175f71ec08ffec403b23bc0926789506e0d2daac0f0790d` | `modules/mcp_server/tools/editor_node_write.cpp` |
| `c1396b4c9b4534b2c5d2781fe4a0e616d9f840171b73b3cac11984d2e33ee20c` | `modules/mcp_server/tools/running_game_node_write.h` |
| `b13a3b11fe8d31ddf0cf3cd8b9aaae8378f049b89dc3652206b456acfe90d0ea` | `modules/mcp_server/tools/running_game_node_write.cpp` |
| `41b6fddbb1f8afa487697b0fa86cde2797b67a959d9f53cd560126c9d984c4e3` | `modules/mcp_server/tools/editor_node_batch_write.h` |
| `e3b12462ba660626279d24c42df986619c07403a24267a38866b67cee597b3bf` | `modules/mcp_server/tools/editor_node_batch_write.cpp` |
| `7e49eae6dd4d894903bbc4a0cbd56cb92566e5b4516251636b74b722df3a9e3b` | `modules/mcp_server/tools/editor_control_layout_write.h` |
| `3688f8e9094d66cc0f63f3c930a38efef8500dd15d46140066493f6b302a40b5` | `modules/mcp_server/tools/editor_control_layout_write.cpp` |
| `4b74b9d49b93d0ca27f96f6e56b599b82254bf35ea063dcce1013349928ee570` | `modules/mcp_server/tools/editor_node_setup.h` |
| `b76e914b5aa30ac4f1e239bc5f954f2d118a4151ac13726f9abab0d3b73fbbc1` | `modules/mcp_server/tools/editor_node_setup.cpp` |
| `1e12b2659f2fc6d511e09f035dc480b6ba4950954ca2a8f7a4715b5b986bd70d` | `modules/mcp_server/tools/registration.cpp` |
| `1a7c09c274d55cc33bb94ed4897aadebd9dd8f895b49780e75038c91a0eb64fc` | `modules/mcp_server/tests/test_mcp_server.h` |
| `f0dface85db0124b1dad6dad7282ada0f0ec2c65bd3c67fa1b86a1a683da27cd` | `modules/mcp_server/docs/tool-groups-b3.json` |
| `5a5accf90d18a87c3d63027a9d1e679b0c1a0763c856f427c62cc9929555534d` | `modules/mcp_server/scripts/mcp017_batch_layout_setup_evidence.ps1` |
| `635a858a1a91ee0542ef5854cbc426931e299b2239849adb484d90df89a6402c` | `modules/mcp_server/scripts/accept_m1.ps1` |
| `550c35cdea3c5ba65412a7f0de036b8e8bc6d4f037351833b4271ee5a32bf425` | `bin/godot.windows.editor.x86_64.console.exe`（提交后重建） |

## 10. 设计决策（自决项）与备选方案

- **D1 `editor_add_nodes_batch` = 全有或全无 + 回滚**。备选（否决）：逐元素结果 + 部分成功——它把
  「半成品现场」留给调用方，且与迁移源的「成功信封里塞错误」同类；备选（否决）：只做形状预校验不做
  事务——第 k 个元素失败仍会留下前 k-1 个节点。
- **D2 `editor_set_node_property_batch` = 「递归匹配 `node_type` 的全部节点，属性必须在所有节点上都
  存在，才允许第一次写；中途失败按逆序恢复旧值」**。备选（否决）：跳过不声明该属性的节点（静默部分写）；
  备选（否决）：写失败后不回滚只报错（现场留下部分新值）。
- **D3 单串行实现者**（本任务的实现与证据收集由同一个 implementer 串行完成；构建严格串行，任何时刻
  只有一个 `scons`）。备选（未采用）：并行多 agent——模块内 `registration.cpp`/`tests/` 是共享文件，
  并行会互相踩踏。
- **D4 共享助手处置**：契约要求 `shape_params` 走 `write_node_property`，而该函数原签名是 `Node *`；
  故把它拓宽为 `Object *`（对节点行为逐字节不变，由全引擎回归 1582/1582 背书），并把
  `instantiate_class`（类级实例化）与 `object_has_property`（写前存在性检查）上提到
  `tools/tool_helpers.*`；`instantiate_node_of_type` 改成其节点包装，`running_game_node_write.cpp`
  的 `_object_has_property` 删除。备选（否决）：在 setup 组里再写一份「资源属性写」——那会成为模块内
  第二条属性写路径。

## 11. deviations（相对 PLAYBOOK / 任务书的显式偏差）

1. **`write_node_property` 签名拓宽为 `Object *`**（任务 §3.5 要求 `shape_params` 走它；`Node *`
   使这一点不可能实现）。同时 `instantiate_class` / `object_has_property` 上提到 `tool_helpers.*`，
   并改写了 `editor_node_write.cpp` / `running_game_node_write.cpp` 中的原实现为该单一实现。
2. **doctest 无法构造的成功路径**：`editor_setup_collision_shape` 正向、
   `editor_setup_physics_body` 正向、`editor_setup_navigation_region/agent` 正向。原因已实测：
   * `RectangleShape2D::RectangleShape2D()` 经 `PhysicsServer2D::get_singleton()->rectangle_shape_create()`
     建 RID（`scene/resources/2d/rectangle_shape_2d.cpp:107-108`），`RigidBody2D` 经
     `PhysicsServer2D::get_singleton()->body_create()`（`scene/2d/physics/physics_body_2d.cpp:49`），
     而 doctest 进程没有 physics server → `ClassDB::instantiate` 空指针 SIGSEGV；
   * 导航区/代理的构造在**模块单跑**下通过、在**全量 `--test`**（其它套件先跑过）下 SIGSEGV——
     与 REPORT-016 记录的 `memnew(GridMap)` 同属「引擎全局状态」类别。
   因此这些路径改由门②在真实编辑器进程里线上钉死（§4/§6），doctest 只钉拒绝类与
   `ClassDB` 分类规则（`is_parent_class` / `get_property_list`，不实例化）。
3. **`editor_setup_camera_3d` 的 `created:true` 分支不可达**（§7.4）。
   **（修复轮更正，见 §15.1：本条为假，已删除并改为实现）** 真实情况是旧代码把
   `find_node(p_root, p_path)` 用**同一个路径**解析两次（`:158` 与 `:178`），第二次必然与第一次同结果，
   所以「创建」块确实不可达；但可构造的修复是把命中的**类**作为分流边界（`Camera3D` → 配置；
   `Node3D` → 以其为父新建；其它 → 建前 `-32602`），于是创建分支可达且由门② 与 doctest 双向钉死，
   死代码与那句「命中即配置、未命中即父」的错误注释一并删除。
4. **`accept_m1.ps1` 的 `$ToolNames` 是硬编码并集**（不是任务书设想的「读 `docs/tool-groups*.json`」）；
   已按 TASK-015/016 先例追加本批 10 个名字（脚本内 4 行注释 + 10 行数据）。
5. **导航 `auto` 默认 3D**（迁移源 `navigation.rs:100` 兜底 2D）——任务书要求选 3D 并记录，已记录。
6. **`editor_setup_lighting` 对 `light_type` 大小写不敏感**（契约示例是小写，类名不是）；未知值拒绝。
7. **`_optional_float` / `_optional_dictionary` / `_optional_parent_path`** 为
   `editor_node_setup.cpp` 的文件内静态小助手：前者因为 `tool_builder.h` 没有 `optional_float` 且
   只有这一个文件需要浮点参数；后两者是纯参数形状检查（3 行），不是 node-add / property-write 路径。
   **（修复轮更正，见 §14 D3：本条为假。这三者的前两者已上提到 `tools/tool_helpers.*`
   ——`MCPTools::relative_path`、`MCPTools::optional_dictionary`、`MCPTools::optional_float`；
   `_relative_path` 在全树曾有 **4** 份、`_optional_dictionary` **2** 份、同义的浮点读取器 **5** 份。
   模块里还额外存在若干**不同**的数值读取器（带参数名前缀或不同措辞），它们保持原状。§11.7 的
   「只有这一个文件需要浮点参数」不成立。）**
8. **`editor_setup_world_environment` 的 `world_env_path` 只当节点路径**，不当作 `res://` 资源加载
   （契约只说「WorldEnvironment 节点的路径」）。
9. **`editor_set_node_property_batch` 的错误消息**形如
   `Property 'texture' on node '.' not found`（`not_found` 工厂自动追加后缀）；节点为根时路径为 `.`，
   这是 `_relative_path` 的既有拼写。
10. 过程记录（非交付偏差）：用 PowerShell 5.1 的 `-Encoding utf8` 回写 `test_mcp_server.h` 时引入
    BOM 并把既有中文注释转成 mojibake；已 `git checkout` 恢复并用 UTF-8 安全的编辑工具重放全部改动，
    复检 `contains 获取: True`、无 BOM。此后所有文件写入都走编辑工具或 `WriteAllBytes`。

## 12. blockers

**无**。端口 9877（用户编辑器，PID 36392）全程未被绑定/杀掉/重启；门①与门②各自记录了
`pid_before == pid_after`。未 push。

## 13. next_step_recommendation

1. 继续 B3 剩余 10 个组的移植（当前 30/40）；`project_set_node_property_across_scenes` 与
   `project_resource_uid_read` 需要单独的事务/资源身份策略，建议各成一个决策点。
2. 建议把 `accept_m1.ps1` 的 `$ToolNames` 改成从 `docs/tool-groups*.json` 的 implemented 并集推导
   （脚本注释已自称如此，实际是硬编码）——否则每批都要手改脚本，正是本次门⑤首轮红的根因。
3. **（修复轮更正，见 §15.1：本条建议已执行，不再是 open 项）** `editor_setup_camera_3d` 的死「创建」
   分支：曾判断它属于契约修订而建议立项；修复轮证明无需改契约——单参数 `node_path` 下用命中的类
   （`Camera3D` / `Node3D` / 其它）即可分流，已实现并由门②线上证据覆盖。原先记录的「命中但非相机
   定义为父节点，与 §3.4 的 `-32602` 冲突」只在**非 `Node3D`** 命中时成立，那一路仍返回 `-32602`。
   另一条契约层面瑕疵（`not_found` 对「已含 not found 语义」措辞的拼接风格，如
   `No node of type 'Sprite2D' in the edited scene not found`）**仍未关闭**。
4. 若后续任务要在 doctest 里钉物理/导航正向路径，建议先在 `tests/test_main.cpp` 的
   `[MCPServer]` 标签下初始化对应的 server 单例（与本模块无关的引擎测试基础设施改动，需单独立项）。

## 14. 独立验收后的修复（repair pass）

独立验收给出 `verdict: pass` + 5 条 minor defect（D1–D5）。本节是修复轮的自包含记录：5 条各自的
判定、改动、**真实**红/绿输出、门号与退出码、被触碰文件的新 sha256，以及**没有**修的项及理由。
本轮只动 `modules/mcp_server/**`；契约/清单/生成器一行未改；未 push。

### 14.1 提交与门绑定

| # | commit | 说明 |
|---|---|---|
| 1 | `c750093e23` | `mcp_server: hoist relative_path / optional_dictionary / optional_float into tool_helpers (TASK-017 repair)` |
| 2 | `de98a2b4b0` | `mcp_server: pin the not_found suffix on the live batch path and fix the vacuous gate check (TASK-017 repair)`（含上提的 doctest 与本条 doctest） |
| 3 | `efe376fd5b` | `mcp_server: drop the duplicated type key from the anchor-preset schema literal (TASK-017 repair)` |
| 4 | `d26fc530aa` | `mcp_server: correct the hoist provenance comments after the TASK-017 repair review`（注释保真，无语义改动） |

本 §14 本身追加在随后一个 doc-only 提交里（`git log -- modules/mcp_server/docs/reports/REPORT-017-b3-batch-layout-setup.md`）。
修复轮的构建：`build_local.cmd`（`tests=yes`），日志 `%TEMP%\mcp017_repair_{green1,red,green2,d2probe,green3,finalbuild,build_d26}.log`；
全部 `EXIT_CODE=0`。门 ①②④⑤ 运行的二进制绑定 `efe376fd5b`
（`--version` = `4.8.dev.custom_build.efe376fd5`，与当时的 `git rev-parse --short HEAD` 前 9 位一致）；
提交 4 之后又重建一次，二进制绑定 `d26fc530aa`（`--version` = `4.8.dev.custom_build.d26fc530a`），
并在该二进制上重跑门 ③ 复核（`157/157`、`5832/5832`，exit 0）——提交 4 只改注释。

### 14.2 D1 —— 假声明 + 空洞门检查（最重要）

**(a) 传递调用者清单（不是只看直接 `not_found(` 字面量）**

全模块 `MCPToolError::not_found(...)` 的调用点里，**只有**一个把“运行时捕获的错误消息”当参数转发：
`tools/editor_node_batch_write.cpp:160` 的 `MCPToolError::not_found(p_message, p_suggestion)`，位于文件内
helper `_transaction_fail`（同文件 137–171 行）。其余调用点的实参都是 `vformat(...)` 或字面量。因此
`_transaction_fail` 的传递上游才是关键：

| 调用点 | 传入的 `p_message` | `p_code` | 是否已带 `" not found"` |
|---|---|---|---|
| `add_nodes_batch_on` 属性校验拒绝（`editor_node_batch_write.cpp:313-315`，经 `_transaction_fail`） | `property_error.message`（来自 `running_game_node_write.cpp:258` 的 `not_found("Property 'x' on node 'y'")`） | `MCP_ERR_NOT_FOUND` | **是** ← 线上今天可达 |
| `add_nodes_batch_on` 父节点缺失（`:261-263`，经 `_transaction_fail`） | `vformat("Parent '%s' not found")` | `MCP_ERR_NOT_FOUND` | 是（自造字面量，仅一次后缀语义） |
| `add_nodes_batch_on` 未知类型 / 非 Node 子类 / `instantiate_class` 失败（`:268-282`，经 `_transaction_fail`） | `vformat` 或 `instantiate_error.message` | `MCP_ERR_INVALID_PARAMS` | 否（走 `_transaction_fail` 的 default 分支 `invalid_params`，不经过 `not_found`） |
| `set_node_property_batch_on` 的目标/属性拒绝（`:374`、`:384`，**直接**调用，不经 `_transaction_fail`） | `vformat(...)` | `MCP_ERR_NOT_FOUND` | 否（单后缀） |

结论：传递调用链**只有一条**会在 `MCPToolError::not_found` 里再套一次后缀，即
`editor_add_nodes_batch` 的元素属性校验拒绝；`write_node_property` → `MCPToolError::not_found`
（`running_game_node_write.cpp:258`）→ `_transaction_fail(p_message=...)` → `MCPToolError::not_found`
（`editor_node_batch_write.cpp:160`）。**修复是线上载重的，不是防御性的。**

**(b) 精确 before/after（真实响应体）**

请求（门② `text_03_batch_bad_property`）：

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"editor_add_nodes_batch","arguments":{"nodes":[{"type":"Node2D","name":"PropOk"},{"type":"Node2D","name":"PropBad","properties":{"NoSuchPropertyXYZ":1}}]}}}
```

| | `error.message` |
|---|---|
| before（`tool_registry.cpp` 无条件拼接） | `nodes[1]: Property 'NoSuchPropertyXYZ' on node '' not found not found` |
| after（`ends_with(" not found")` 守卫） | `nodes[1]: Property 'NoSuchPropertyXYZ' on node '' not found` |

after 的真实响应体（`%TEMP%\mcp017-evidence\text_03_batch_bad_property.response.json`，
661 bytes，sha256 `1013fb1f2525ed9d3342b80f8b137f0b73638bb5da172771ddb52af323c65ff6`）：

```json
{"error":{"code":-32001,"data":{"batch":{"count":0,"created":[],"errors":[{"index":1,"parent_path":".","property":"NoSuchPropertyXYZ","reason":"Property 'NoSuchPropertyXYZ' on node '' not found","type":"Node2D"}],"on_error":"all_or_nothing","rolled_back":[{"index":0,"node_path":"PropOk","reason":"transaction rollback","type":"Node2D"}],"status":"rolled_back"},"suggestion":"editor_add_nodes_batch is all-or-nothing: ..."},"message":"nodes[1]: Property 'NoSuchPropertyXYZ' on node '' not found"},"id":1,"jsonrpc":"2.0"}
```

`message` 中 `" not found"` 出现 **1** 次；`result` 为 null；`rolled_back` 里是 index 0。

**(c) doctest 红/绿（真输出）**

新增断言位于 `[MCPServer] editor_add_nodes_batch rolls the whole batch back on a broken middle element`
（`tests/test_mcp_server.h`，第 2 个元素属性缺失，index 1；另在
`[MCPServer] MCPToolError::not_found appends the suffix exactly once` 里有直接工厂断言）。
红相位：临时把 `tool_registry.cpp:122` 回退为 `error.message = p_what + " not found";` 后重建并运行
（日志 `%TEMP%\mcp017_repair_red_dt2.log`，`EXIT=1`）：

```
.\modules/mcp_server/tests/test_mcp_server.h(8755): ERROR: CHECK( e5.message == "nodes[1]: Property 'mcp017_no_such_property' on node '' not found" ) is NOT correct!
  values: CHECK( nodes[1]: Property 'mcp017_no_such_property' on node '' not found not found == nodes[1]: Property 'mcp017_no_such_property' on node '' not found )
.\modules/mcp_server/tests/test_mcp_server.h(8756): ERROR: CHECK( e5.message.count(" not found") == 1 ) is NOT correct!
  values: CHECK( 2 == 1 )
[doctest] test cases:  1 |  0 passed | 1 failed | 1585 skipped
[doctest] assertions: 45 | 42 passed | 3 failed |
[doctest] Status: FAILURE!
```

同一次红构建下直接工厂用例也红（`%TEMP%\mcp017_repair_red_dt.log`）：
`CHECK( Node 'x' not found not found == Node 'x' not found )`。恢复修复后重建，`[MCPServer]*` 全绿：

```
[doctest] test cases:  157 |  157 passed | 0 failed | 1429 skipped
[doctest] assertions: 5832 | 5832 passed | 0 failed |
[doctest] Status: SUCCESS!
```

**(d) 门② 的空洞检查已替换**

删除了 `text_no_caller_with_suffixed_p_what`（逐行 `git grep`，只检查直接调用点的字面量，**看不到
helper 运行时转发的值**，因此恒真）。替换为两条基于真实响应体的断言：

* `text_batch_property_refusal_has_exactly_one_not_found`：`-32001`、`result` 为 null、
  `([regex]::Matches($msg,' not found')).Count -eq 1`、且 `$msg -ceq "nodes[1]: Property 'NoSuchPropertyXYZ' on node '' not found"`；
* `text_batch_bad_property_rolled_back`：随后 `editor_find_nodes_by_type` 证明 `PropOk`/`PropBad` 都没留下。

门② 总检查数 **84 → 85**（删 1 加 2），`85/85 checks passed`，exit 0。

### 14.3 D2 —— 契约字面量逐字节保真（两条 nits）

**(a) `editor_set_anchor_preset` 重复的 `"type":"object"`**：已删除
（`editor_control_layout_write.cpp` 的 schema 字面量现在以 `{"properties":...}` 开头，和契约
`docs/tools_list.renamed.json:550-570` 的顺序一致）。JSON 解析器本来会折叠重复键，所以这是**纯源码
整洁性**改动；实证：修复前后整份 `tools/list` 的 sha256 都是
`3514e16dd2bbc27cfc0b933de5c8c6023e46881160d7d0b4922b4116d377fe20`（22788 bytes）。

**(b) `editor_setup_navigation_agent` 的 `"default":10.0` —— 缺陷前提为假，未改。**
验收称「契约是 `10`」，但契约原文第 3109-3111 行是：

```
            "max_speed": {
              "default": 10.0,
              "type": "number"
            },
```

即契约就是 `10.0`，而线上 served bytes 也是 `10.0`（`"max_speed":{"default":10.0,"type":"number"}`），
两者已经逐字节一致。为验证「改成 `10`」到底会发生什么，修复轮临时把字面量改为 `"default":10` 后重建
（日志 `%TEMP%\mcp017_repair_d2probe.log`、`%TEMP%\mcp017_d2probe_gate1.log`）：

* 门① `-Group editor_node_setup`：**仍然 3/3 通过、exit 0**——但原因是 **Godot 的 JSON 解析器把所有
  数字统一解析为 double**（`_schema_from_json`），`10` 与 `10.0` 在服务端是同一个 `Variant::FLOAT`；
* 直接抓 served bytes（`%TEMP%\mcp017-d2probe\tools_list.response.json`，22788 bytes，
  sha256 `3514e16dd2bbc27cfc0b933de5c8c6023e46881160d7d0b4922b4116d377fe20`）：
  `"default":10.0` —— **与字面量 `10.0` 时完全相同**，整份清单 sha256 也相同。

因此「改字面量为 `10`」对线上字节是 **no-op**，而且会让 C++ 源码与契约原文（`10.0`）不再逐字一致。
验收很可能是用 `jq` 打印契约（jq 把 `10.0` 规范化成 `10`）才得出「契约是 10」。决定：**保持 `10.0`**，
不制造一个与原意相反的源码差异。门①仍按 D2 要求复核了这两个组的 `inputSchema` 与契约一致
（`-Group editor_node_setup`: 7/7 `inputSchema=True`；`-Group editor_control_layout_write`:
`editor_set_anchor_preset: name=True description=True inputSchema=True`），线上 `tools/list` 的 sha256
见 §14.7。

### 14.4 D3 —— 去重上提（`tool_helpers.{h,cpp}`）

**(a) 上提了什么、删了几份**

| helper | 上提后的名字 | 删除的文件内副本 | 更新调用点 |
|---|---|---|---|
| `_relative_path` | `MCPTools::relative_path` | **4**：`editor_node_write.cpp:81`、`editor_control_layout_write.cpp:55`、`editor_node_batch_write.cpp:64`、`editor_node_setup.cpp:64` | 30 处（node_write 11 / node_setup 14 / batch 4 / control 1） |
| `_optional_dictionary` | `MCPTools::optional_dictionary` | **2**：`editor_node_write.cpp:91`、`editor_node_setup.cpp:163`（两份逐字节相同：`NIL`→空字典，非 `DICTIONARY`→`-32602`，否则原样） | 2 处 |
| `_optional_float` 等价体 | `MCPTools::optional_float` | **5**：`editor_node_setup.cpp:142`（`_optional_float`）、`editor_input_simulation.cpp:202`（`_optional_number`）、`editor_write_scene_editor.cpp:115`（`_optional_number`，带 `r_present`）、`running_game_frame_observation.cpp:148`（`_optional_positive_seconds` 的取值核心）、`running_game_read_scene.cpp:110`（`_optional_number`——**任务书只点名了 3 处，这是第 5 份，逐字节相同，已一并上提**） | 13 处 |

上提后的定义数（grep 证据，`tools/` 全树；**修复轮重跑的真实输出**，工作目录 `modules/mcp_server/`）：

```
$ grep -rn "^static String _relative_path\|^static bool _optional_dictionary\|^static bool _optional_float\|^static bool _optional_number\|^static bool _optional_positive_seconds" tools/ ; echo "--- exit=$?"
tools/running_game_frame_observation.cpp:150:static bool _optional_positive_seconds(const Dictionary &p_args, const String &p_key, double p_default, double &r_out, MCPToolError &r_error) {
--- exit=0
$ grep -c "String relative_path(Node" tools/tool_helpers.cpp                 -> 1
$ grep -c "bool optional_dictionary(const Dictionary" tools/tool_helpers.cpp -> 1
$ grep -c "bool optional_float(const Dictionary" tools/tool_helpers.cpp      -> 1
```

**（修复轮更正，见 §15.3：原块为假声明）** 原块声称该 grep「无输出：五种文件内拼写全部消失」，但它在
HEAD 上**打印一行**——`_optional_positive_seconds`，正是本节下文 12 行处自己写明「故意保留」的那一个，
原文因此自相矛盾。真实情况：`_relative_path`/`_optional_dictionary`/`_optional_float`/`_optional_number`
四种文件内拼写确实全部消失（上面的 grep 只命中 `_optional_positive_seconds` 一处），而
`_optional_positive_seconds` 保留，因为它有**不同的拒绝措辞**（`must be a number of seconds`）与
「正数且有限」规则，二者都被 TASK-010 的 doctest 钉死；它现在只把「取值」这一步交给
`optional_float`，自己的两条拒绝留在调用点。

**保留未统一的语义**（任务书允许的例外）：`running_game_frame_observation.cpp` 的
`_optional_positive_seconds` 仍留在原文件，因为它的错误措辞不同（`must be a number of seconds`）且有
「正数且有限」规则，二者都被 TASK-010 的 doctest 钉死（`tests/test_mcp_server.h:5898-5900`）；它现在只把
「取值」这一步交给 `optional_float`，自己的两条拒绝保持在调用点。模块里另有若干**形态不同**的数值读取器
（`running_game_input.cpp:280`/`:552`、`editor_input_simulation.cpp:667`、`editor_node_setup.cpp` 的颜色分量、
`editor_write_scene_editor.cpp` 的 Vector3 分量），它们的参数名消息/前缀不同，本轮**未**动。

**(b) 行为保持的实证（修复轮重测；替换原先的 175/171/3/1 脆计数，见 §15.4）**

* doctest：`[MCPServer]*` 157/157（修复轮为 5875 断言，详见 §15.5）；
* 线上 wire 对比的**方法**（可复现，不依赖具体数字）：同一份二进制下把门② 完整跑两遍
  （脚本固定写 `%TEMP%\mcp017-evidence`，两遍之间把第一遍的目录整体复制到
  `%TEMP%\mcp017-evidence-runA`），然后**只枚举文件**（`Get-ChildItem -File`，以免把快照里的嵌套
  目录名算成一个「missing」条目）逐一比每个 `*.response.json` 的 sha256；
* 修复轮实测（run A vs run B）：**186 个文件，184 个逐字节相同，2 个不同**——
  `status_9888.response.json`（唯一差异字段 `frame_count`：本机 212 vs 218，服务端帧计数随运行时点
  变化）与 `setup_16_read_scene_file.response.json`（差异是引擎保存 `.tscn` 时为每个节点生成的随机
  `unique_id=<int>` 及由此派生的 `size` 字段：`Main unique_id=1130187279` vs `317961269`、
  `size=1686` vs `1682`；节点名/类型/父子关系、`uid://bdslpbp0h5217` 与全部属性值逐字节相同）；
* **易变字段清单（穷举）**：`status_9888.response.json` 的 `frame_count`；
  `setup_16_read_scene_file.response.json` 中 `.tscn` 文本内的每个 `unique_id=<int>` 与其派生的
  `size`。`status_9889.response.json` 同样含 `frame_count`，它在两次运行间**是否**恰好相同取决于时序，
  所以原先把 `status_9888/9889` 一并列为「不同」只在那一轮成立——这正是脆计数不可复现的原因；
* 整份 `tools/list` 的 sha256 修复前后都是 `3514e16dd2bbc27cfc0b933de5c8c6023e46881160d7d0b4922b4116d377fe20`
  （22788 bytes，编辑器端点 79 tools；与「相机分流实现不改 schema」一致）。

**(c) 新增 doctest**：`[MCPServer] MCPTools::relative_path / optional_dictionary / optional_float`
覆盖根/子/孙路径、两个读取器的 absent / 接受（`FLOAT`+`INT`）/ 拒绝分支与确切错误消息。
**（修复轮补充，见 §15.2）** 另加：跨树 `relative_path`（`Node::get_path_to` 无共同祖先 → 空
`NodePath` → 空字符串）、`@` 净化自动名（同名第二个节点返回引擎实际应用的 `@Node2D@N`）、
两个读取器的 `null`（等同 absent）与 `bool`（拒绝，`got bool`）分支。

**(d) §11.7 的错误声明已在原地更正**（见 §11.7 的修复轮标注），§14.4(a) 给出准确描述。

### 14.5 D4 —— 未声明行为：类型错误的 `value` 静默写成零向量

**已复现（真实请求/响应 + 回读，`%TEMP%\mcp017-d4\`）：**

| # | 请求 | 响应 | 回读 |
|---|---|---|---|
| 1 | `editor_set_node_property_batch {"node_type":"Node2D","property":"position","value":1e20}` | `{"count":8,...,"status":"ok","updated":8}` | `A.position = {"x":0.0,"y":0.0}` |
| 2 | `editor_add_nodes_batch {"nodes":[{"type":"Node2D","name":"Big1","properties":{"position":1e20}}]}` | `{"count":1,"created":[...],"errors":[],"status":"ok"}` | `Big1.position = {"x":0.0,"y":0.0}` |
| 对照 | `... property:"position", value:{"x":5,"y":6}` | `status:"ok"` | `Big1.position = {"x":5.0,"y":6.0}` |

**根因（共享、既有，不是本批引入）**：`coerce_to_property_type`
（`tools/tool_helpers.cpp:599`）对任意不匹配类型调用
`VariantUtilityFunctions::type_convert(p_value, p_target_type)`
（`core/variant/variant_utility.cpp:862-863`），后者对 `VECTOR2` 目标执行
`p_variant.operator Vector2()`；`Variant::operator Vector2()`
（`core/variant/variant.cpp:1777-1793`）对**非向量形状**的源类型直接 `return Vector2();`——即静默默认
构造值，无错误。同一模式覆盖 `Rect2`/`Color`/`Transform2D`/`Plane`/`AABB`/`Basis`… 一族目标类型。

**处置（按任务书给定的选择）**：**不改共享 coercion 语义**。理由：

1. 要在两个新 batch 工具里做诚实拒绝，必须判断「这次 `type_convert` 是不是有意义的转换」。合法输入
   （`{"x":5,"y":6}` 字典经 `vector_from_dictionary`、`"Vector2(1,2)"` 字符串经
   `Variant::construct_from_string`、`"#rrggbb"` 颜色串）都依赖 `write_node_property` 内部的预处理，
   在 batch 工具里复刻这套判断等于把 property-write 规则复制出第二份——正是 PLAYBOOK/本模块禁止的；
   直接看 `type_convert` 的结果也无法与合法转换区分（两者都是 `Vector2`）。
2. 只改两个新 batch 工具会让同一份 JSON 在 `editor_set_node_property`（既有，仍静默）与
   `editor_set_node_property_batch`（拒绝）之间行为分叉；那是**设计决策**，超出「只关这 5 条缺陷」。
3. 正确的修法在共享层：让 `coerce_to_property_type` 拒绝「非 layout-兼容源 → 复合类型目标」的转换
   （或让批量的响应回显 `new_value` 让调用方可检测）。这属于 `editor_set_node_property` /
   `running_game_set_node_property` 的既有语义变更，需单独立项。**建议（follow-up）**：
   `coerce_to_property_type` 增加一条「源类型必须与目标类型在 `Variant::operator <T>()` 的映射集内，
   或目标类型是标量/字符串」的规则，并用一条整数/浮点标量打到 `Vector2` 属性的 doctest 钉住。

**另外记录（不声称覆盖）**：`set_node_property_batch_on` 的「中途写失败后按逆序恢复旧值」
（`editor_node_batch_write.cpp:398-409`）在当前工具语法下**不可达**——写入前已经在所有匹配节点上验证过
属性存在，而 `write_node_property` 的其余拒绝（类型/形状）对同类型节点是齐次的，因此任何可构造的失败
都落在 index 0，消息为 `Property 'x' write failed after 0 node(s) had been written; ...`。该分支只有
代码审阅，没有 wire 证据，报告不声称它被覆盖。

### 14.6 D5 —— 报告引用了不存在的脚本断言

`REPORT-017` §4 门⑤ 原文（第 122 行）称两次运行的 PASS 清单 `PASS-SET-IDENTICAL`。
`scripts/accept_m1.ps1` 全文**没有**这个字符串（`grep -c "SET-IDENTICAL" scripts/accept_m1.ps1` = 0）；
它是实现者在脚本之外用 `Compare-Object` 比较两次运行的 PASS 行、结果为空。已在 §4 原地改正为
「由实现者用 `Compare-Object` 比较，脚本本身不输出该 token」。

### 14.7 门与退出码（二进制绑定 `efe376fd5b`；门③另在 `d26fc530aa` 上复跑）

> **（修复轮第二次更正，见 §15.5）** 下表的门号属于 `efe376fd5b` / `d26fc530aa` 两个构建，是**当时**
> 的真实记录，不是最终 HEAD 的构建。最终提交后的五道门数字（绑定 `3905126482`）在 §15.5；本节保留
> 为历史，不再代表当前二进制。

| 门 | 命令 | 结果 | exit |
|---|---|---|---|
| ① 契约子集 | `check_contract_subset.ps1 -Group editor_node_setup` | `3/3 checks passed`，7 个工具全部 `inputSchema=True` | 0 |
| ① 契约子集 | `check_contract_subset.ps1 -Group editor_control_layout_write` | `3/3 checks passed`，`editor_set_anchor_preset: name=True description=True inputSchema=True` | 0 |
| ② 三类证据 + scope + 链 + 批量计数 + setup 读回 | `mcp017_batch_layout_setup_evidence.ps1` | `85/85 checks passed`（修复前 84，删 1 加 2），含新的 `text_batch_property_refusal_has_exactly_one_not_found` | 0 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | `157/157` 用例、`5832/5832` 断言、0 failed | 0 |
| ④ 全引擎回归（仓库根） | `--headless --test` | `1583/1583` 用例、`430114/430114` 断言、0 failed、3 skipped | 0 |
| ⑤ 批量收口 | `accept_m1.ps1` | `22/22 cases passed`；`implemented tools = 79 (editor endpoint) / 40 (game endpoint); contract = 171` | 0 |

与修复前的 delta：③ 156/5807 → **157/5832**（+1 用例 / +25 断言）；④ 1582/430089 → **1583/430114**
（同增量，新增的就是 §14.4(c) 的 helper 用例 + §14.2(c) 的批量属性断言）。

日志：`%TEMP%\mcp017_repair_gate1_setup.log`、`gate1_layout.log`、`gate2.log`、`gate3.log`、
`gate4.log`、`gate5.log`、`gate3_final.log`。

线上 `tools/list`（9888，编辑器端点，79 tools）sha256：
`3514e16dd2bbc27cfc0b933de5c8c6023e46881160d7d0b4922b4116d377fe20`（22788 bytes，
`%TEMP%\mcp017-evidence\scope_editor_tools_list.response.json`）；
门⑤ 的跨进程重启两次 `tools/list` 亦逐字节一致（`22789/22789`，sha256
`e367792baa936a845cd1ae7ff45c0144bb5ba3c0108f6f72e9f5d6d3fa86a8f0`，请求体带 initialize 前缀故长度差 1）。

### 14.8 修复轮触碰文件的新 sha256

| sha256 | 文件 |
|---|---|
| `dc996ee9c0053c2940ad5afd65e156db00ff2f5f09c5698b13c9f902ef231863` | `modules/mcp_server/tools/tool_helpers.h`（含提交 4 的注释修正） |
| `63492760f9f76940c00acaa070577d04798c60c7d2af6b30d873c7fc3793c70a` | `modules/mcp_server/tools/tool_helpers.cpp`（含提交 4 的注释修正） |
| `ac19fb02b7eb98ed13aa6e73a28b83f47ef96b6d8f6b4f9f8bae1711aad467e4` | `modules/mcp_server/tools/editor_node_write.cpp` |
| `7cf5eb7e8c25da221a624bcec0fcd6fce2a03884d18aa25ae1540e26dfe23b52` | `modules/mcp_server/tools/editor_control_layout_write.cpp` |
| `81660314490b400774df1e88554b51def13c694ac0d71471556c104d082f0ea6` | `modules/mcp_server/tools/editor_input_simulation.cpp` |
| `70b62d1aadebd17180bf6903344eff97e64fd9caa89d304578dc4d30bac34b25` | `modules/mcp_server/tools/editor_node_batch_write.cpp` |
| `339e051c5c35c5fcf4261c35d568e1f4dad1448c42bc30222ad6a23d73832bda` | `modules/mcp_server/tools/editor_node_setup.cpp` |
| `86fb18fe87b9d6caaf67e596fbafd03268b6bf39339cbded6c4320ab5077a5e8` | `modules/mcp_server/tools/editor_write_scene_editor.cpp` |
| `cbeff50bd77893ed4dbaf10cf21f776947f78275b74de5778b174a699771237b` | `modules/mcp_server/tools/running_game_frame_observation.cpp` |
| `4059ccee40f7b28e09bb6e3b202d2ef916daae457a27241c82309afec5bf51fb` | `modules/mcp_server/tools/running_game_read_scene.cpp` |
| `7711aee0cc31be8e76f6c96e4a846cdd467b4ed7036834b81686d5db26f61bb9` | `modules/mcp_server/tests/test_mcp_server.h` |
| `668bc1baef440673938601d9ea1728f8a7aa8fcd22c0e85b08f16a5d739b616a` | `modules/mcp_server/scripts/mcp017_batch_layout_setup_evidence.ps1` |
| `fe438bff0823a07a05677ecd3a974b3129c62938eb692be5111ec2d6ea16202b` | `bin/godot.windows.editor.x86_64.console.exe`（绑定 `d26fc530aa` 的重建；门①②④⑤ 那轮绑定 `efe376fd5b` 的二进制为 `0b571684cc72256c7c5fdbd47081c6bd8351cf0027a525cedb0843d7f10b3ce1`） |
| `d7a5fcac39582821506c757db203cb32ecc2f18211b7027523bcc1e734cc73b6` | `modules/mcp_server/tool_registry.cpp`（临时回退仅用于红相位，最终状态与修复前一致） |

契约/清单/生成器（`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、`docs/tool-groups*.json`、
`scripts/gen_*.py`）`git diff` 为空，未触碰。

### 14.9 未关闭 / 明确不做的项

1. **D2(a) 的 `"default":10` 改动未执行**：缺陷前提为假（契约原文就是 `10.0`），且实测对 served bytes 是
   no-op（§14.3(b)）。保持 `10.0` 才与契约逐字一致。
2. **D4 的共享 coercion 未改**：属既有工具语义，按任务书允许的路径只做精确记录 + follow-up 建议（§14.5）。
3. **D4 的 mid-loop 恢复分支**：不可达，只做代码审阅记录，不声称覆盖（§14.5）。
4. `_optional_parent_path`、`_has_ancestor_class`、`_optional_vector3` 等非同义 helper 未动（不在 D3 范围）。

## 15. 最终修复（final repair pass）

独立验证给出 **1 个过程阻断 + 4 个缺陷**。本轮只动 `modules/mcp_server/**`，未 push，未新增任何
spec/decision 文档；契约/清单/生成器一行未改（§15.7 给出 `git diff` 为空的对象）。工作量按
「代码修复 → 提交 → 重建 → 五道门 → 本报告追加 → 提交报告 → 再重建」的顺序执行（§15.9）。

### 15.1 缺陷 1（major，过程）——二进制未绑定 HEAD

**原状**：`bin\godot.windows.editor.x86_64.console.exe --version` = `4.8.dev.custom_build.d26fc530a`，
而 `git rev-parse --short HEAD` = `38a9b8c352`；其后的三个提交是 docs-only
（`git diff --stat d26fc530aa..HEAD` 只有本报告文件），所以产品代码没变，但绑定检查失败、门证据被判无效。

**处置**：本轮把「代码修复 → 提交 → 重建 → 跑门」重新排序，见 §15.9；最终门的二进制绑定
`3905126482`（§15.5）。本轮之前的所有门数字（§4、§14.7）明确标注为属于运行时的那个构建，
不再声称属于当前 HEAD。

### 15.2 缺陷 2（minor，真实行为缺口）——`editor_setup_camera_3d` 从不创建相机

**(a) 判定与实现的规则**（原「创建分支不可达」结论被证伪，§2/§4/§11.3/§13.3 已原地更正）。

迁移源 `godot_mcp_gdext/src/commands/scene_3d.rs:85-102` 的 `cmd_setup_camera_3d` 是
「`root.has_node(path)` → 当 `Camera3D` 配置；否则 `find_parent(path)` → 在其下新建」。旧 C++ 实现把
`find_node(p_root, p_path)` 用**同一路径**解析两次（旧 `:158` 与 `:178`），第二次必然与第一次同结果，
所以旧「创建」块确实不可达——但这是**实现 bug**，不是契约问题：契约只有单个必填 `node_path`
（description `配置 Camera3D`），**没有 `parent_path`**，因此 `node_path` 是唯一能命名父节点的参数，
迁移源的 `find_parent` 正是这个父语义。据此本轮实现的规则（也写进了函数上方注释）：

| `node_path` 命中什么 | 结果 |
|---|---|
| 已存在的 `Camera3D` | 配置：`set_current(true)`，`created:false`，回读 `node_path`/`current` |
| 已存在的 `Node3D`（非 `Camera3D`） | **创建**：在其下新建名为 `Camera3D` 的相机，`owner`=场景根，`set_current(true)`，`created:true`，`node_path` 由引擎回读 |
| 已存在的其它类（既非 `Camera3D` 也非 `Node3D`） | `-32602`，消息含实际类名，**在 `memnew` 之前**拒绝 |
| 不存在 | `-32001` `Parent '<path>' not found` + suggestion |

**为什么这里是「按命中的类分流」而不是迁移源的 `has_node` 二分**（契约理由，必须记录）：`has_node`
二分在单参数下会把「父节点路径」也送进「当相机」分支（把 `Node3D` 父节点判成 `-32602`），创建分支
永远不可达；而 `Camera3D` 本身**就是** `Node3D`，所以「相机 / 可承载相机的父」这两个集合天然不交，
用类做边界既能让创建分支可达，又保持迁移源「命中就必须是相机语义」的**拒绝**姿态：非 `Node3D` 命中
仍是 `-32602` 并给出实际类名，且绝不**静默**当父用（创建分支的响应显式带 `created:true` 与引擎回读的
新路径）。这一点与 REVIEWER 要求的「reproduce that rule exactly ... a path that names a non-camera node
is -32602, never silently used as a parent」在**非 `Node3D`** 命中上逐字一致。

**未采纳 REVIEWER 测试项 (d) 里的 `-32000`（显式记录，不伪装）**：REVIEWER 的 (b)
「refuses a non-camera existing node with `-32602`」与 (d)「refuses a non-`Node3D` parent with
`-32000`」在 `node_path` 语义下是**同一个输入类**（已存在、非 `Camera3D`、非 `Node3D`），不可能同时
给两个码。本轮取 `-32602`：(b) 与任务书第 1 条 bullet list 都点名 `-32602`，且它是迁移源原有的拒绝类，
也是门② 原有的 `not_camera` 检查码；兄弟工具（`editor_setup_navigation_agent/region`）用 `-32000`
是因为它们的 `node_path` 是**纯父路径**、拒绝原因是「父缺对应上下文」，与「这个节点根本不能承载相机」
不是同一类。 (d) 的**实质**要求（「建前拒绝、不留半成品」）已用两条证据钉死：
doctest 的 `plain->get_child_count() == 0` / `root->get_child_count() == 3`，与门② 的
`setup_camera_3d_refusals_create_nothing`（`find_nodes_by_type(Camera3D)` 里没有 `A/*` 或 `Plain/*`）。

**(b) 红 → 绿（真实输出）**

红相位：临时把 `setup_camera_3d_on` 回退为旧函数体、并同时给三个 helper 注入定向变异（用于缺陷 4 的
red），重建（`%TEMP%\mcp017_repair_red.log`，`EXIT_CODE=0`，构建本身成功，红在 doctest 里）。相机用例
（`%TEMP%\mcp017_repair_red_dt_camera.log`）失败 8 条断言，核心是：

```
.\modules/mcp_server/tests/test_mcp_server.h(9038): ERROR: CHECK_FALSE( created_error.is_error() ) is NOT correct!
  values: CHECK_FALSE( true )
.\modules/mcp_server/tests/test_mcp_server.h(9040): ERROR: CHECK( (bool)((Dictionary)created)["created"] ) is NOT correct!
  values: CHECK( false )
.\modules/mcp_server/tests/test_mcp_server.h(9044): ERROR: CHECK( empty->get_child_count() == 1 ) is NOT correct!
  values: CHECK( 0 == 1 )
.\modules/mcp_server/tests/test_mcp_server.h(8989): FATAL ERROR: test case CRASHED: SIGSEGV - Segmentation violation signal
```

（该红运行在 `empty->get_child(0)` 上崩了——红相位暴露了测试自身的问题：旧代码下子节点数为 0。随后
把断言改成 `get_child_count() == 1 ? get_child(0) : nullptr` 再判空，避免「红=崩溃」；红日志的行号
属于那次修订前的版本。）helper 用例同一次红（`%TEMP%\mcp017_repair_red_dt.log`）另有 10 条失败，
例如 `CHECK( Foreign ==  )`、`CHECK( Node2D2 == @Node2D@2 )`、`CHECK_FALSE( true )`。

绿相位：恢复实现与 helper 后重建（`%TEMP%\mcp017_repair_green1.log` / `green2.log`，均
`EXIT_CODE=0`）。定向绿：

```
[doctest] test cases:  1 |  1 passed | 0 failed | 1585 skipped
[doctest] assertions: 38 | 38 passed | 0 failed |
[doctest] Status: SUCCESS!
```

**(c) 门② 的线上创建链（同一个 `node_path` 语义，用**另一个**读族工具证明）**

```
$ editor_setup_camera_3d {node_path:"World3D"}                      -> {"created":true,"current":true,"node_path":"World3D/Camera3D","setup":true,"type":"Camera3D"}
   （%TEMP%\mcp017-evidence\setup_03b_camera_create_under_parent.response.json，180 bytes，
     sha256 4dd5ab040e3569bdc22cb70db732973f3fb11c51de79e4afe93833b393c8dfa6）
$ editor_find_nodes_by_type {type:"Camera3D"}                       -> World3D/WorldCamera, World3D/Camera3D
$ editor_get_node_properties {path:"World3D/Camera3D",properties:["current"]} -> true
   （setup_03c_read_created_camera.response.json sha256 e28f010dffa194222cfe924b3dbe74b961003c4a5f41672a1402c85e55dfb505）
```

即：新相机由**不同**工具读到、`current=true`、路径 `World3D/Camera3D` 证明它是 `World3D` 的子节点。
拒绝类保留并加强：`-32602` 从原来的 `node_path:"World3D"`（现已是合法创建路径）改指 `A`（`Node2D`，
既非相机也非 `Node3D`），并新增非空洞检查：

```
$ editor_setup_camera_3d {node_path:"A"}       -> -32602 "Node 'A' is not a Camera3D (is Node2D) and cannot host one: a Camera3D's parent must be a Node3D"
$ editor_setup_camera_3d {node_path:"NoSuchParentXYZ"} -> -32001 result=null "Parent 'NoSuchParentXYZ' not found"
$ editor_find_nodes_by_type {type:"Camera3D"}  -> World3D/WorldCamera, World3D/Camera3D   （A/* 与 Plain/* 下无任何残留）
```

死代码与那句错误注释（「命中即配置、未命中即父」，旧 `:176-177`）一并删除；`editor_node_setup.h`
的声明注释也改成实现后的规则。工具在未创建时绝不会报 `created:true`（只有 `create` 分支返回 true）。

### 15.3 缺陷 3（minor）——§14.4(a) 的假 grep 证据

已按 §14.4(a) 原地更正：原块声称 grep「无输出」，实际打印一行
`tools/running_game_frame_observation.cpp:150:static bool _optional_positive_seconds(...)`。修复轮在
`modules/mcp_server/` 下重跑了那条 grep 与三条 `grep -c`，真实输出写在 §14.4(a)（`--- exit=0`，
命中一处）。解释：`_relative_path` / `_optional_dictionary` / `_optional_float` / `_optional_number`
四种拼写确实消失；`_optional_positive_seconds` 是**故意保留**的那一个，它有独立拒绝措辞
（`must be a number of seconds`）与「正数且有限」规则，取值一步转交 `optional_float`。原块的
「无输出」与 12 行后的「保留」自相矛盾，已消除。

### 15.4 缺陷 4（minor）——helper doctest 覆盖过薄

`tests/test_mcp_server.h` 的 `[MCPServer] MCPTools::relative_path / optional_dictionary / optional_float`
在原断言（根/子/孙；两个读取器的 absent / 接受 / 拒绝）之外新增：

* **跨树 `relative_path`**：`Node::get_path_to` 走两条祖先链、找不到共同祖先时执行
  `ERR_FAIL_NULL_V_MSG(common_parent, NodePath(), ...)`（`scene/main/node.cpp:2389-2398`），即返回**空
  `NodePath`**，因此 helper 今天返回**空字符串**（双向都钉：`relative_path(root, foreign) == ""` 与
  `relative_path(foreign, root) == ""`）。该调用会在日志里打印两行引擎 ERROR（已实测，见 §15.5 门③），
  不影响断言与退出码。
* **`@` 净化自动名**：同一父下两个都叫 `Same` 的 `Node2D`，第二个被 `add_child` 的默认路径
  （`_validate_child_name(p_child, false)`，`scene/main/node.cpp:1537-1576`）改名为 `@Node2D@<counter>`；
  断言返回路径 == 引擎实际应用的 `@Node2D@N` 名且 != `"Same"`。
* **`optional_dictionary` / `optional_float` 的 `null` 与 `bool`**：`null` 等同 absent（空字典/默认值，
  无错误）；`bool` 被拒（`-32602`，消息 `got bool`）。注意读取器**只在拒绝时写 `r_error`**，所以
  「成功且无错误」的断言用独立变量（`null_error`），否则会读到上一次拒绝的残留错误——
  这正是红相位之外、绿相位第一轮暴露并修掉的一个测试自身缺陷（`%TEMP%\mcp017_repair_green_dt_helpers.log`
  的 `CHECK_FALSE( error.is_error() )` 失败）。

红/绿：见 §15.2(b)（同一次红构建覆盖 helper 的四个定向变异：跨树返回名字、`@` 被剥掉、`null` 被拒、
`bool` 被接受；绿后定向用例 38/38）。

### 15.5 缺陷 5（minor）——§14.4(b) 的 175/171/3/1 计数不可复现

已按 §14.4(b) 原地替换为**方法 + 易变字段清单 + 本轮实测值**：同一二进制把门② 跑两遍
（run A 目录快照到 `%TEMP%\mcp017-evidence-runA`，run B 为 `%TEMP%\mcp017-evidence`），只枚举
`*.response.json` 文件逐一比 sha256（避免把嵌套目录名算成「missing」）。实测：

* **186 个文件 / 184 个逐字节相同 / 2 个不同**；
* 不同的两个：`status_9888.response.json`（唯一差异字段 `frame_count`，212 vs 218）与
  `setup_16_read_scene_file.response.json`（差异是引擎保存 `.tscn` 时给**每个节点**生成的随机
  `unique_id=<int>` 及其派生的 `size`，1686 vs 1682）；
* `status_9889.response.json` 也含 `frame_count`，两次运行是否恰好相同取决于时序——原先把它列为
  「不同」只在那一轮成立，这正是脆计数的问题；
* 两次运行的门② 都是 `88/88 checks passed`、`exit 0`。

### 15.6 五道门（最终构建，绑定 `3905126482`）

`--version` = `4.8.dev.custom_build.390512648`，`git rev-parse --short HEAD` = `3905126482`（前 9 位一致）；
构建 `%TEMP%\mcp017_repair_postcommit.log`，`EXIT_CODE=0`；二进制 sha256
`3d96c8f754ff3706cb1adba9f40ffd515b448bc760d716b6c8bdca9f71aea6b2`。

| 门 | 命令 | 结果 | exit | 日志 |
|---|---|---|---|---|
| ① 契约子集 | `check_contract_subset.ps1 -Group editor_node_setup` | `3/3 checks passed`；7 个工具 `name/description/inputSchema` 全 True；编辑器端点 79 tools | 0 | `%TEMP%\mcp017_repair_gate1_setup.log` |
| ① 契约子集 | `check_contract_subset.ps1 -Group editor_control_layout_write` | `3/3 checks passed`；`editor_set_anchor_preset` 三项 True | 0 | `%TEMP%\mcp017_repair_gate1_layout.log` |
| ② 三类证据 + scope + 链 + 批量计数 + setup 读回 | `mcp017_batch_layout_setup_evidence.ps1` | **`88/88 checks passed`**（原 85，+3：`setup_camera_3d_creates_under_parent`、`setup_camera_3d_create_read_back`、`setup_camera_3d_refusals_create_nothing`；`not_camera` 检查由空洞码断言改为「码 + 实际类名」并改指 `A`） | 0 | `%TEMP%\mcp017_repair_gate2_runA.log`（run B 同 `88/88`，`runB.log`） |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"`（仓库根） | `157/157` 用例、**`5875/5875`** 断言、0 failed、1429 skipped | 0 | `%TEMP%\mcp017_repair_gate3.log` |
| ④ 全引擎回归 | `--headless --test`（仓库根） | `1583/1583` 用例、**`430157/430157`** 断言、0 failed、3 skipped | 0 | `%TEMP%\mcp017_repair_gate4.log` |
| ⑤ 批量收口 | `accept_m1.ps1` | `22/22 cases passed`；`implemented tools = 79 (editor endpoint) / 40 (game endpoint); contract = 171` | 0 | `%TEMP%\mcp017_repair_gate5.log` |

与 §14 的 delta：③ 5832 → **5875**（+43 断言，用例数不变）；④ 430114 → **430157**（同 +43）；
② 85 → **88**。门① 的 union 仍 **79/40**、contract 仍 **171**（相机分流实现**不改 schema**：
线上 `tools/list` sha256 仍是 `3514e16dd2bbc27cfc0b933de5c8c6023e46881160d7d0b4922b4116d377fe20`，
22788 bytes，与 §14.3/§14.4 一致）。

### 15.7 本轮触碰文件的 sha256

| sha256 | 文件 |
|---|---|
| `96ee1ab7e14fb037efecd1546a5e3aa5f51ed9ced7ed9fce2801c60efd2421a7` | `modules/mcp_server/tools/editor_node_setup.h` |
| `f4513acaa134059db4d43bf244bd67102e1964d021c418646a1c0732832e5654` | `modules/mcp_server/tools/editor_node_setup.cpp` |
| `6a855277008ec6a96dfb4548a2f4ec32d4d677fe68d16b14c7f1b8c30eea0b17` | `modules/mcp_server/tests/test_mcp_server.h` |
| `f3b010f201cc8b26d3e9b16407d97360902a41e10309a7f0dbe8da965e680c87` | `modules/mcp_server/scripts/mcp017_batch_layout_setup_evidence.ps1` |
| `3d96c8f754ff3706cb1adba9f40ffd515b448bc760d716b6c8bdca9f71aea6b2` | `bin/godot.windows.editor.x86_64.console.exe`（绑定 `3905126482`） |

`tool_helpers.{h,cpp}`、`tool_registry.cpp`、`editor_node_write.cpp`、
`editor_control_layout_write.cpp`、`editor_node_batch_write.cpp`、`registration.cpp` 等本轮**未改**
（sha256 与 §14.8 相同）；红相位的 helper 定向变异只存在于红构建，最终文件与 `3905126482` 的树一致。
契约/清单/生成器（`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、`docs/tool-groups*.json`、
`scripts/gen_*.py`）`git diff 1af7d21647 --` 为空；无 `docs/spec/**`。

### 15.8 未关闭 / 明确不做

1. **REVIEWER 测试项 (d) 的 `-32000`**：未采纳，理由与替代证据在 §15.2(a)（同一输入类只能有一个码；
   取 `-32602`，其「建前拒绝、无半成品」的实质已用 doctest + 门② 双证据覆盖）。
2. **`editor_setup_world_environment` / `editor_setup_lighting` / `editor_setup_physics_body`** 的
   正向路径仍只在真实编辑器进程（门②）验证，doctest 不构造（本模块既有的事实，未变）。
3. **§13.3 的第二条契约瑕疵**（`not_found` 对已含语义措辞的拼接风格）**仍未关闭**，仅记录。
4. `relative_path` 的跨树调用会打印两行引擎 `ERROR: No path can be resolved...`（
   `scene/main/node.cpp:2398` 的 `ERR_FAIL_NULL_V`）；这是引擎自身的诊断输出，退出码与断言不受影响，
   未做屏蔽（屏蔽会让「返回空字符串」这一被钉住的行为变得不可见）。

### 15.9 提交顺序与最终绑定

| # | commit | 说明 |
|---|---|---|
| 1 | `15dfe24b87` | `mcp_server: make editor_setup_camera_3d create the camera under a parent path (TASK-017 repair)` |
| 2 | `3905126482` | `mcp_server: pin the camera create branch, the relative_path edge branches and the wire create chain (TASK-017 repair)` |

顺序（REVIEWER 指定）：**代码修复 → 提交 1/2 → 重建 → 五道门 → 本报告追加 → 提交报告 → 再重建**。
§15.6 的全部门号取自**绑定 `3905126482`** 的构建（提交 2 之后、本报告提交之前的那次重建）。
按 REPORT-016 §10.16 的先例：追加本 §15 的 doc-only 提交会再次推进 `core/version_hash.gen.cpp` 的
版本字符串，因此报告提交之后**又重建了一次**；`git diff --stat 3905126482..HEAD` 只有本报告文件，
所以那个最终二进制与门运行二进制**产品代码逐字节相同、只差版本字符串**。最终一次重建后的
`--version` 与同一次 `git rev-parse --short HEAD` 的并排实测值见下方「报告提交后的重建」行
（对报告自身提交哈希的引用无法写进本文件正文——这正是 REPORT-016 §10.16 记录同一现象的原因）。

**报告提交后的重建**（`%TEMP%\mcp017_repair_finalbuild.log`，`EXIT_CODE=0`）：当时
`git rev-parse --short HEAD` = `0d20f411fc`（§15 的 doc-only 提交），
`--version` = `4.8.dev.custom_build.0d20f411f` → **前 9 位一致**；该二进制 sha256 =
`918092e47161eb4dee7427834bb568311e6c5337a10d3e89340c20f5a017df45`。这一行之后又追加了一次
doc-only 提交（只补这段实测值），它同样只推进版本字符串；工作树里最终 `--version` 与 HEAD 仍一致
（并排实测值在交付说明中给出）。

