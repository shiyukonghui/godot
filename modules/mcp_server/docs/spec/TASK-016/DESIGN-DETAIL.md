# TASK-016 — DESIGN-DETAIL（阶段三工件，决策者维护）

> 输入：`REQUIREMENTS.md`（Q1–Q7 裁决）、`DESIGN-OVERVIEW.md`。
> 目标粒度：另一个工程师（或**没有对话上下文的子代理**）照着本文件就能实现，不需要再做设计决策。

## 0. 不可再分的工作单元与提交点

| 单元 | 内容 | 提交信息（英文） |
|---|---|---|
| U1 | 上提 `find_node` / `edited_scene_root` 到 `tools/tool_helpers.*`，删除 4 处本地副本（2×`_find_node`、3×`_edited_scene_root`，其中 `editor_node_write.cpp` 同时持有两者），加等价性 doctest | `mcp_server: hoist the editor node-path resolution into tool_helpers (TASK-016 section 1)` |
| U2 | `tools/editor_node_read.{h,cpp}`（6 工具）+ `registration.cpp` 两行 + `tests/test_mcp_server.h` 计数 + manifest `implemented=true` | `mcp_server: port B3 editor_node_read (6 tools) (TASK-016 section 2)` |
| U3 | `tools/editor_node_instantiate.{h,cpp}`（4 工具）+ 同样四处 | `mcp_server: port B3 editor_node_instantiate (4 tools) (TASK-016 section 2)` |
| U4 | 门② 证据采集脚本 `scripts/mcp016_node_read_instantiate_evidence.ps1` + 报告 | `mcp_server: TASK-016 evidence script and report` |

**U1 必须是第一个提交**：U2/U3 依赖共享助手；若先写组文件再上提，会制造一次性副本。

## 1. U1 详细设计：助手上提

### 1.1 新增到 `tools/tool_helpers.h`（`namespace MCPTools`，放在「Editor-UI guard」小节之后）

```cpp
// 编辑场景根，或 nullptr。
//
// `SceneTree::get_edited_scene_root()` 是编辑器持续同步的镜像
// (`EditorNode::set_edited_scene_root`)；`EditorInterface::get_edited_scene_root()`
// 是 unchecked 的 `EditorNode::get_singleton()` 解引用（editor_interface.cpp:105-107），
// 在 doctest 进程实测 SIGSEGV（REPORT-004 §9）。
//
// 上提自（TASK-016 §1）：tools/editor_node_write.cpp:79、
// tools/editor_read_scene_inspector.cpp:89、tools/editor_write_scene_editor.cpp:87
// —— 三份文本相同的文件私有副本。
Node *edited_scene_root();

// 迁移源 `find_node`（`godot_mcp_gdext/src/commands/node.rs:148-165`）的节点解析：
//   "." 或裸根名 -> 根；`root->has_node(path)` -> 该节点；
//   否则若 path 以 `<根名>/` 开头，去掉前缀再试；都不中 -> nullptr。
// 与 `Node::get_node` 的关键差异：未命中是 nullptr，不产生引擎错误。
//
// 上提自 tools/editor_node_write.cpp:102 与 tools/editor_write_scene_editor.cpp:99
// （两份文本相同的文件私有副本）。
Node *find_node(Node *p_root, const String &p_path);
```

**体是逐字搬运**，只做三处机械改动：去 `static`、去前导 `_`、递归/自调用改名。
**不得**改语义、不得改判断顺序、不得合并 `get_node_path` 的精确匹配语义（见 OVERVIEW §5）。

### 1.2 删除本地副本（4 处定义 + 由它们服务的调用点改名）

| 文件 | 删除 | 调用点改名为 |
|---|---|---|
| `tools/editor_write_scene_editor.cpp` | `_edited_scene_root`(87)、`_find_node`(99) | `MCPTools::edited_scene_root()` / `MCPTools::find_node(...)`（该文件已在 `namespace MCPTools` 内或需确认；不在则加 `using` 或全限定） |
| `tools/editor_read_scene_inspector.cpp` | `_edited_scene_root`(89) | 同上 |
| `tools/editor_node_write.cpp` | `_edited_scene_root`(79)、`_find_node`(102) | 同上 |

**保留** `editor_node_write.cpp:126` 的 `_relative_path`（只有一份定义，§1.4 不动它）。
**保留** 各处解释「为什么是 `SceneTree::get_edited_scene_root()`」的注释——把其中一份挪进
`tool_helpers.h` 的文档注释，其余处改为一句「见 `MCPTools::edited_scene_root()`」。

### 1.3 等价性证明（A2）——必须落成可复现的脚本

脚本 `scripts/mcp016_hoist_equivalence.ps1`，流程：

```
1. 记录 PRE = 重构前提交（= 本任务开工时的 HEAD sha，写死在脚本里并断言
   `git merge-base --is-ancestor $PRE HEAD` 成立）。
2. 造 %TEMP% scratch 工程（.tscn 用 [IO.File]::WriteAllBytes，无 BOM），
   --import 且校验 $LASTEXITCODE == 0。
3. 【before】git stash / git checkout $PRE -- modules/mcp_server（保留脚本本身），
   build_local.cmd（串行、不抑制输出），校验 --version == $(git rev-parse --short HEAD)。
   起 9888，跑 CASE 序列，每步 `curl.exe -s -o before/<name>.json`，记录 sha256。
4. 【after】回到 HEAD，重建，校验 --version，跑**同一** CASE 序列到 after/<name>.json + sha256。
5. 逐文件比较：相等则 PASS；列出 sha256 表与 diff 计数（必须为 0）。
```

**CASE 序列**（覆盖被上提的两个助手的所有分支：根 / 精确相对路径 / 带根名前缀 / 未命中 / 属性写回）：

```
editor_open_scene(scratch 主场景)
editor_get_scene_tree                                  (读回，基线)
editor_add_node  {type:Node2D, parent_path:".",        name:"HoistA"}
editor_add_node  {type:Node2D, parent_path:"HoistA",   name:"Deep"}
editor_set_node_property {path:"HoistA/Deep", property:"position", value:{"x":1,"y":2}}
editor_get_node_properties {path:"HoistA/Deep"}        (使用 find_node 的嵌套分支)
editor_get_node_properties {path:"<根名>/HoistA"}      (使用「带根名前缀重试」分支)
editor_rename_node {path:"HoistA/Deep", name:"Deep2"}
editor_duplicate_node {path:"./HoistA"}
editor_reparent_node {path:"HoistA/Deep2", new_parent:"."}
editor_set_node_property {path:"NoSuchNode", property:"position", value:{"x":0,"y":0}}  (未命中 -> -32001)
editor_get_scene_tree                                  (读回，终态)
editor_delete_node {path:"HoistA"}
```

**before 与 after 的响应必须逐字节相同**（含错误响应）。这条证明比「读代码看起来一样」强，是 A2 的唯一判据。

### 1.4 U1 的 doctest（新增，红→绿）

新增 `TEST_CASE("[MCPServer] the hoisted editor node helpers keep the migration source's resolution")`：

- 构造裸 `Node` 树（`Node *root = memnew(Node); root->set_name("Root")`，加子 `Child`、孙 `Child/Grand`）；
- 断言 `find_node(root, ".")` == root、`find_node(root, "Root")` == root、
  `find_node(root, "Child/Grand")` == 孙、`find_node(root, "Root/Child/Grand")` == 孙（前缀重试）、
  `find_node(root, "Nope")` == nullptr、`find_node(root, "Child/Nope")` == nullptr；
- 断言所有 `tools/*.cpp` 中 `_find_node` 的定义数为 0（这条用 grep 在报告里给，不在 doctest 里做文件 IO）；
- `edited_scene_root()` 在无 `SceneTree` 的 doctest 进程里返回 `nullptr`（不得崩）。

红阶段：先写 `find_node(root, "Root/Child/Grand")` 等断言（此时函数还不存在/未声明 → 编译失败，
或先写一个错误的本地实现让它红）。**编译失败也算红阶段证据**，但报告里必须贴出真实编译器输出。

## 2. U2 详细设计：`editor_node_read`（6 工具，channel=editor / scope=editor / mutating=false）

### 2.1 逐工具可观察契约（迁移源位置 → 契约 → 与迁移源的差异）

统一前置：`require_editor_ui(r_error, ...)` → `edited_scene_root()`（null → `-32000` no-scene）。
所有 `node_path` / `path` 的成功回显一律是**相对编辑根的归一化路径**（根为 `"."`，PLAYBOOK §6.7 + Q5）。

| # | 工具 | 迁移源 | 参数 | 成功返回 | 错误 | 与迁移源差异 |
|---|---|---|---|---|---|---|
| 1 | `editor_get_node_properties` | `node.rs:232-266` | `path`(必,string) / `properties`(选,string 数组) | `{node_path, type, properties:{name:值}}` | 缺 `path`→`-32602`；`properties` 非数组或含非字符串→`-32602`；节点不存在→`-32001`；**点名属性不存在→`-32001`+suggestion** | Q2/Q3/Q5（§6.6 第 8 例）。全量列举仍跳过 `_` 前缀与 `script`（`node.rs:256`，怪癖保留，PLAYBOOK §6.8） |
| 2 | `editor_get_node_groups` | `node.rs:501` 前的读半（`cmd_get_node_groups`） | `node_path`(必,string) | `{node_path, groups:[...], count}` | 缺参 `-32602`；节点不存在 `-32001` | 见 2.3（实现者需先读迁移源确认键名，若为 `groups` 则一致） |
| 3 | `editor_find_nodes_in_group` | `node.rs:564-598` | `group`(必,string) | `{group, nodes:[{name,path,type}], count}` | 缺参 `-32602`；空结果→成功 `count:0`（不是错误） | 一致；`nodes` 为前序遍历确定序 |
| 4 | `editor_find_nodes_by_type` | `batch.rs:105-144` | `type`(必,string) | `{nodes:[{name,path,type}], count}` | 缺参 `-32602`；空结果→成功 `count:0` | 一致；`get_class()==type \|\| is_class(type)` 两条都保留（`batch.rs:111`） |
| 5 | `editor_get_node_signals` | `editor.rs:460-507` | `node_path`(必,string) | `{node_path, type, signals:[{name,args:[{name,type}],connections:[{target,method}]}], count}` | 缺参 `-32602`；节点不存在 `-32001` | `args[].type`：迁移源是 `str(arg["type"])`（VariantType 枚举的数字**字符串**）→ C++ 版用 `Variant::get_type_name(arg.type)` 得到 `"int"`/`"Vector2"` 等**名称**，更可用；这是**显式偏离**，必须在报告里记为「契约描述未规定 type 的拼写，本实现取名称」 |
| 6 | `editor_list_signal_connections` | `batch.rs:207-259` | `node_path`(选,string) / `signal_name`(选,string) | `{connections:[{source,signal,target,method}], count}` | 参数类型错 `-32602` | 迁移源用 GDScript `Expression` + `JSON.stringify`；C++ 版用 `Node::get_signal_list` / `get_signal_connection_list` / `Callable::get_object` 直接构造。**收全部连接（不过滤 CONNECT_PERSIST）**——这是它区别于 `editor_analyze_signal_flow` 的判别点，**不得**顺手过滤；`node_path`/`signal_name` 均为**子串**匹配（`find() >= 0`）；`target`：`Callable` 无 object 或 object 不在根内时是 `""`（迁移源的 `tp` 初值），**保留** |

### 2.2 共享内部结构（`tools/editor_node_read.{h,cpp}`）

```cpp
namespace MCPTools {

// 三个读族工具共用的节点条目（迁移源 `collect_by_type` / `find_in_group_recursive`
// / `serialize_selection_nodes` 三处的同一形状）：{name, path, type}。
// `path` 用根相对归一化拼写，根为 "."。
Dictionary node_entry(Node *p_root, Node *p_node);

// 递归收集：`p_type_name` 非空 -> 按类型（get_class 相等 或 is_class）；
// `p_group` 非空 -> 按组。两者至多一个非空。前序、确定序。
void collect_nodes(Node *p_root, Node *p_node, const String &p_type_name,
        const String &p_group, Array &r_out);

// 一个节点的属性表（仅被 editor_get_node_properties 与 doctest 使用）：
// 跳过 `_` 前缀与 "script"；当 p_filter 非空时只收表中的名字；
// p_filter 中任一名字在表里不存在 -> false + -32001 + data.suggestion。
bool node_properties(Node *p_node, const Vector<String> *p_filter,
        Dictionary &r_out, MCPToolError &r_error);

// 信号条目：迁移源 get_signals 的形状。
Array signal_entries(Node *p_node);      // [{name,args:[{name,type}],connections:[{target,method}]}]
// 扁平连接收集：迁移源 find_signal_connections 的形状（子串过滤、不过滤持久位）。
void collect_signal_connections(Node *p_node, Node *p_root,
        const String &p_node_filter, const String &p_signal_filter, Array &r_out);

} // namespace MCPTools
void register_editor_node_read_tools(MCPToolRegistry &r_registry);
```

**导出这些入口的理由**（与 `editor_node_write.h` 同）：doctest 进程没有 `SceneTree`，
工具级调用只能观察到 `-32000`。把节点级逻辑导出，doctest 才能用裸 `Node` 断言真实行为。

### 2.3 实现纪律

1. **先读迁移源**确认 `cmd_get_node_groups` 的确切返回键与语义，写进报告（本文件不替它下结论）。
2. 每个工具**必须**用 `ToolBuilder`，`channel("editor").verb(<map 值>).scope(MCPToolScope::EDITOR).mutating(false)`；
   `verb` 取值见 `tool-rename-map.json`：`get`/`get`/`find`/`find`/`get`/`list`。
3. `description` 与 `inputSchema` **逐字**取自 `docs/tools_list.renamed.json`（用
   `_schema_from_json(R"schema(...)schema")` 体例，必要时 `_fold_integral_numbers`）。
4. 参数解析只用 `require_string` / `optional_string`；`properties` 数组自己校验元素类型 → `-32602`。
5. 成功一律 `MCPTools::content_result({...})`；错误一律 `MCPToolError`。
6. 空结果（组内无节点 / 无该类型节点 / 无连接）是**成功**，`count:0`，不是错误。

## 3. U3 详细设计：`editor_node_instantiate`（4 工具，channel=editor / scope=editor / mutating=true）

| 工具 | 迁移源 | 参数 | 成功返回 | 错误 | 差异/说明 |
|---|---|---|---|---|---|
| `editor_add_scene_instance` | `scene.rs:284-333` | `scene_path`(必) / `parent_path`(选,默认 `"."`) / `name`(选) | `{node_path, scene_path, name}` | 缺 `scene_path`→`-32602`；文件不存在→`-32001`+suggestion；`parent_path` 解析失败→`-32001`；`ResourceLoader::load` 失败 / `instantiate()` 返回 null→`-32000` | `name` 未给时空串 → **不调用** `set_name`（让实例保留场景根名），`name` 回读引擎实际名字；`node_path` 相对根归一化 |
| `editor_add_raycast` | `physics.rs:67-82` | `parent_path`(选,默认`"."`) / `name`(选,默认`"RayCast"`) / `dimension`(选,默认`"2d"`) | `{added:true, name, node_path, type}` | `parent_path` 解析失败→`-32001` | `dimension=="2d"` → `RayCast2D`，其余（含 `"3d"` 与任意值）→ `RayCast3D`（迁移源 `match` 只有 `"2d"` 分支，**保留**）；`type` 是回读的实际类名，**新增键**（迁移源只回 `added`/`name`） |
| `editor_add_mesh_instance` | `scene_3d.rs:73-83` | `parent_path`(选,默认`"."`) / `name`(选,默认`"Mesh"`) | `{added:true, name, node_path, type}` | 同上 | 新增 `node_path`/`type` 回读键 |
| `editor_add_gridmap` | `scene_3d.rs:256-280` | `mesh_library_path`(必) / `parent_path`(选,默认`"."`) / `name`(选,默认`"GridMap"`) | `{name, parent_path, mesh_library_path, created:true, node_path, type, mesh_library_set}` | 缺 `mesh_library_path`→`-32602`；父节点解析失败→`-32001` | 迁移源**静默忽略** `mesh_library_path` 加载失败（`if let Some(lib)`）→ C++ 版加载失败即 `-32001`+suggestion（§6.6「不得产出成功形状」）；若保留静默，调用方会以为材质库挂上了。**这是本组唯一的行为纠正**，须在报告显式记录 |

共同约束：
- 一律 `require_editor_ui` → `edited_scene_root()`；`add_child` 后 `set("owner", root)`（否则节点不进 `.tscn`）。
- 复用一个共享的 `add_typed_child(Node *p_root, Node *p_parent, const String &p_name, Node *p_node)` 内部函数做
  `set_name` / `add_child` / `set owner`；**不得**复制第二份 `find_node`。
- `MeshInstance3D` / `RayCast2D` / `RayCast3D` / `GridMap` 用 `memnew`（引擎 C++ 侧的直接构造），
  不用 `ClassDB::instantiate` + Variant 转换（迁移源的写法是 Rust 绑定限制的产物，C++ 侧没必要）。
- 属性写入（如 `mesh_library`）**必须**经 `MCPTools::write_node_property`（`tools/running_game_node_write.h`），
  不新写一份。

## 4. 注册与计数（U2/U3 各自）

- `tools/registration.cpp`：在 TASK-015 的两行之后追加
  `#include "editor_node_read.h"` / `register_editor_node_read_tools(r_registry);`
  （U3 同理 `editor_node_instantiate`），顺序 = manifest 顺序。
- `tests/test_mcp_server.h`：既有断言 `editor_registry.get_tool_count() == 76` / `get_visible_tool_count(true) == 59`
  是**硬编码**的。U2 后应为 `82` / `65`；U3 后应为 `86` / `69`；游戏侧 `40` / `40` **不变**。
  该测试用例名提到「ten tools」，U2/U3 要新增各自的「editor-only 且携带 N 个工具」用例，
  **不要**改坏既有用例的语义。
- `docs/tool-groups-b3.json`：两组 `implemented` 置 `true`（**只允许改这两个布尔值**）。

## 5. 测试策略（TDD，红→绿，每步之间跑测试）

每个工具至少 4 条：

| 类别 | 例 |
|---|---|
| 成功 | 裸 `Node` 树经导出的节点级入口断言返回字典逐键相等 |
| 缺参 | `registry.call_tool(name, {}, err)` → `-32602` |
| 底层失败 | 不存在的 `node_path` / `parent_path` / `scene_path` → `-32001` 且有 `data.suggestion` |
| 特有边界 | 读：`properties` 点名不存在 → `-32001`（**红测试先写**）、空过滤结果、组内无节点 `count:0`、`signal_name` 子串匹配、`editor_list_signal_connections` **不过滤非持久连接**；写：`dimension` 非 `"2d"` → `RayCast3D`、`gridmap` 的库加载失败 → `-32001` |

再加：
- 每个**组**一条注册/作用域用例（editor-only、游戏侧缺席、`-32601`、编辑器 `tools/list` 各出现一次）；
- U1 的等价性 grep 断言（报告里给 `grep -c` 结果）。

**红阶段必须先跑并贴真实输出**（至少：`editor_get_node_properties` 点名不存在属性、`editor_add_gridmap`
库加载失败这两条，它们对应两处行为纠正）。

## 6. 门的执行顺序（构建串行）

```
0. 校验 --version == $(git rev-parse --short HEAD)；不一致先 build_local.cmd 重建
1. 门①  scripts\check_contract_subset.ps1 -Group editor_node_read
   scripts\check_contract_subset.ps1 -Group editor_node_instantiate
   （两组各跑一次；断言的是全部 implemented 组的并集）
2. 门②  scripts\mcp016_node_read_instantiate_evidence.ps1（三类证据 + 两条活链 + scope 缺席）
   含 §1.3 的等价性脚本（U1 提交点跑）
3. 门③  bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
4. 门④  同一二进制 --headless --test          （0 failed；passed 只增不减）
5. 门⑤  scripts\accept_m1.ps1 连跑两次（两次 PASS 清单一致）
```

> `--test-case="[MCPServer]*"` 的基线 passed 数取 TASK-015 报告（门③ 基线见 REPORT-015 §8）；
> 只允许增加。

## 7. 活证据链（A6）

**链 A（读族 ↔ 写族互验，最重要）**，全部在 9888：

```
editor_open_scene(scratch)                       -> 打开
editor_add_node {type:Node2D, name:"Chain"}      -> 写族建节点
editor_set_node_property {path:"Chain", property:"position", value:{"x":7,"y":9}}   -> 写族改
editor_get_node_properties {path:"Chain", properties:["position"]}                  -> 读族读回 {"x":7,"y":9}
editor_set_node_groups {node_path:"Chain", groups:["chain_g"]}                      -> 写族改组
editor_get_node_groups {node_path:"Chain"}                                          -> 读族读回含 "chain_g"
editor_find_nodes_in_group {group:"chain_g"}                                        -> 读族按组找到 Chain
editor_connect_signal {source_path:"Chain", signal:"ready", target_path:".", method:"queue_free"} -> 写族连
editor_get_node_signals {node_path:"Chain"}                                         -> 读族读到 ready + connections
editor_list_signal_connections {node_path:"Chain"}                                  -> 读族扁平读到同一连接
editor_disconnect_signal {...}                                                      -> 写族断开
editor_list_signal_connections {signal_name:"ready"}                                -> count 归零
editor_delete_node {path:"Chain"}                                                   -> 清理
```

每一步都要断言**观察到的状态变化**（不是「返回了 200」）。链 A 同时是 §6.6 第 8 例的线上复现：
`editor_get_node_properties {properties:["no_such_prop_xyz"]}` 必须是 `-32001`。

**链 B（实例化族 ↔ 读族）**：

```
editor_get_scene_tree                            -> 基线
editor_add_raycast {dimension:"2d", name:"RC"}   -> 读回 type == "RayCast2D"
editor_add_mesh_instance {name:"MI"}             -> 读回 type == "MeshInstance3D"
editor_add_gridmap {mesh_library_path:"<scratch 内 .tres>", name:"GM"}  -> mesh_library_set == true
editor_find_nodes_by_type {type:"RayCast2D"}     -> count>=1 且路径含 RC
editor_find_nodes_by_type {type:"GridMap"}       -> count>=1
（另起 scratch 场景 .tscn）editor_add_scene_instance {scene_path:"res://inst.tscn", name:"Inst"}
editor_get_node_properties {path:"Inst"}         -> 读回 type 是 inst.tscn 的根类型
editor_get_scene_tree                            -> 终态含全部新增
```

若 scratch 里造不出可加载的 `MeshLibrary` `.tres`，允许把 `editor_add_gridmap` 的**成功类**证据降级为
「`-32001` + suggestion（库不存在）」并**显式声明**原因（PLAYBOOK §3 门②「哪一类不可构造必须显式声明」）。

## 8. 报告的额外小节（TASK-016 §4）

除 PLAYBOOK §4 全部条目外，报告必须含：

1. 「§1 助手上提的逐字节等价证明」——PRE 提交 sha、CASE 列表、before/after 逐文件 sha256 表、diff 计数 0、`grep -c` 结果；
2. 「写族→读族互验链条」——链 A / 链 B 的真实请求与响应片段；
3. 「本批后已实现工具总数与剩余计数」——86 已实现 / 171 总契约 / 剩余 85；并给出 B3/B4/B5 各自的剩余数与本批两组的成员清单。