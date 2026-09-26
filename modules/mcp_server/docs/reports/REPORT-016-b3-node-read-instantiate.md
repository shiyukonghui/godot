# REPORT-016 — 助手上提（逐字节等价）+ B3 续批：`editor_node_read`(6) + `editor_node_instantiate`(4)

> 任务书：`docs/tasks/TASK-016-b3-node-read-instantiate.md`
> 通用规范：`docs/tasks/PLAYBOOK-group-port.md`
> 决策过程工件：`docs/spec/TASK-016/{REQUIREMENTS,DESIGN-OVERVIEW,DESIGN-DETAIL}.md`
> 本文件是本任务唯一的报告工件（未新建任何规范文档；`docs/spec/TASK-016/` 是决策者的既有未跟踪工件，本任务未创建也未修改它）。

## 0. status / commits

**status：完成**（U1 上提 + 等价性证明、U2 `editor_node_read`、U3 `editor_node_instantiate`、
门①–⑤全部在绑定二进制上通过）。

分支 `feature/mcp-server-module`，提交（均为英文信息，**未 push**）：

| sha | 一行说明 |
|---|---|
| `805899b4e5` | `mcp_server: hoist the editor node-path resolution into tool_helpers (TASK-016 section 1)` |
| `ca9627f638` | `mcp_server: prove the tool_helpers hoist is behaviour preserving (TASK-016 section 1)` |
| `4e023604e4` | `mcp_server: port B3 editor_node_read (6 tools) (TASK-016 section 2)` |
| `6788201ca7` | `mcp_server: port B3 editor_node_instantiate (4 tools) (TASK-016 section 2)` |
| `c1f2b82ace` | `mcp_server: TASK-016 gate-2 evidence script and the manifest registration order` |
| `c9760a7f88` | `mcp_server: keep the GridMap doctest out of the engine test process and fix the gate-2 expectations` |

**门的二进制绑定（PLAYBOOK §3 第 0 步）**：

```
bin\godot.windows.editor.x86_64.console.exe --version
  4.8.dev.custom_build.c9760a7f8        (exit 0)
git rev-parse --short HEAD
  c9760a7f88
```

`--version` 自报 `c9760a7f8` == `c9760a7f88` 的前 9 位 → **§6 的全部门输出与 §5/§7 的全部证据都来自这一次重绑后的运行**。
两点运行纪律上的波折都在本报告里显式记录：① 门④ 曾在**错误的 cwd**（`modules/mcp_server` 而不是仓库根）下
产出 15 个与本批无关的假红并在 5931 行崩溃（exit `0xC0000005`），改回仓库根重跑后 1565/1565 全绿（§6 末）；
② 更早的一次门④ 假红抓到了一个**真缺陷**（`GridMap` 在 doctest 进程里 SIGSEGV），已定位、已规避并写进 §11。
二进制 `sha256 = 700c02a16af5d02a54b76489ad8d4549fa240a966a546595172aae9d81f2633e`（300544 bytes）。
构建命令：`modules\mcp_server\scripts\build_local.cmd`（`tests=yes`，串行，不抑制输出，每次 exit 0）。

## 1. U1 助手上提的逐字节等价证明（A2）

### 1.1 上提内容与「只有一处定义」的机器证据

新增（`tools/tool_helpers.{h,cpp}`，`namespace MCPTools`）：

```cpp
Node *edited_scene_root();                              // 原来 3 份文件私有副本
Node *find_node(Node *p_root, const String &p_path);    // 原来 2 份文件私有副本
```

体**逐字搬运**，只做三处机械改动：去 `static`、去前导 `_`、调用点改名。
删除了 5 处定义（`editor_node_write.cpp` 的 `_edited_scene_root`/`_find_node`、
`editor_read_scene_inspector.cpp` 的 `_edited_scene_root`、`editor_write_scene_editor.cpp` 的两者），
并把「为什么是 `SceneTree::get_edited_scene_root()`」的长注释挪进 `tool_helpers.h`，
其余处改为一句引用。`editor_node_write.cpp` 的 `_relative_path` **原地保留**。

`grep` 结果（`modules/mcp_server/tools`）：

```
$ Select-String -Path tools\*.cpp -Pattern '^static Node \*_find_node' | Measure-Object
  Count = 0
$ Select-String -Path tools\*.cpp -Pattern '^static Node \*_edited_scene_root' | Measure-Object
  Count = 0
$ Select-String -Path tools\tool_helpers.cpp -Pattern '^Node \*(edited_scene_root|find_node)\('
  tool_helpers.cpp:367: Node *edited_scene_root() {
  tool_helpers.cpp:375: Node *find_node(Node *p_root, const String &p_path) {
$ Select-String -Path tools\tool_helpers.h -Pattern '^Node \*(edited_scene_root|find_node)\('
  tool_helpers.h:224: Node *edited_scene_root();          （声明）
  tool_helpers.h:239: Node *find_node(Node *p_root, const String &p_path);   （声明）
$ Select-String -Path tools\*.cpp -Pattern '^static String _relative_path'
  editor_node_write.cpp:81                                  （未上提，只有这一处）
```

即：`edited_scene_root` / `find_node` 在模块内**各只有一处定义**（都在 `tool_helpers.cpp`），
`_relative_path` 仍是 1 处且位置未动。

### 1.2 等价性脚本 `scripts/mcp016_hoist_equivalence.ps1`（exit 0，8/8 PASS）

```
PRE   = c26516becc
AFTER = 805899b4e5822c74598ae4a7ca838662bca7d5b6  (branch feature/mcp-server-module)
[PASS] pre_is_an_ancestor_of_after :: git merge-base --is-ancestor c26516becc 805899b4e5... -> exit 0
[PASS] working_tree_has_no_tracked_modifications :: dirty entries: []
import ...: attempt=1 exit=0
[PASS] scratch_import_exit_code :: the scratch project imported with exit code 0 (attempt(s): 1)
build before: exit=0
version[before] = 4.8.dev.custom_build.c26516bec   (git rev-parse --short HEAD = c26516becc)
[PASS] before_cases_completed :: 20 response files
build after: exit=0
version[after] = 4.8.dev.custom_build.805899b4e   (git rev-parse --short HEAD = 805899b4e5)
[PASS] after_cases_completed :: 20 response files
[PASS] the_two_runs_produced_the_same_case_set :: before=20 after=20
[PASS] before_and_after_responses_are_byte_identical :: 20 response file(s) compared, diff count = 0
[PASS] guard_user_port_9877 :: pid_before=36392 pid_after=36392
8/8 checks passed
```

**before / after 逐文件 sha256（前 16 位，全部相同，diff 计数 = 0）**：

| case | before | after | |
|---|---|---|---|
| 01_open_scene | `8fd4761d07cfe88d` | `8fd4761d07cfe88d` | same |
| 02_selection_baseline | `a49aab02002f2caa` | `a49aab02002f2caa` | same |
| 03_add_node_root | `8ea56628711df339` | `8ea56628711df339` | same |
| 04_add_node_relative | `ed6f7088261cf998` | `ed6f7088261cf998` | same |
| 05_write_relative | `98c3fa2a6919310d` | `98c3fa2a6919310d` | same |
| 06_write_root_prefixed | `2d351978437fdba5` | `2d351978437fdba5` | same |
| 07_duplicate_dot_prefix | `1a041b7bb6aa8404` | `1a041b7bb6aa8404` | same |
| 08_rename_nested | `af28ea208d404a01` | `af28ea208d404a01` | same |
| 09_set_property_by_root_name | `2c0ff903ade61bbd` | `2c0ff903ade61bbd` | same |
| 10_selection_nested_node | `cb2a86a6f3ead28f` | `cb2a86a6f3ead28f` | same |
| 11_selection_read_nested | `6544b9e2f67c164a` | `6544b9e2f67c164a` | same |
| 12_selection_dot | `0ac4e45c70b57316` | `0ac4e45c70b57316` | same |
| 13_selection_read_dot | `5b5802f4b9fcdad1` | `5b5802f4b9fcdad1` | same |
| 14_selection_missing_node | `9d27d737f2ca2287` | `9d27d737f2ca2287` | same |
| 15_reparent_to_dot | `332266ae0b3533fb` | `332266ae0b3533fb` | same |
| 16_write_missing_node | `69a370da32c255d7` | `69a370da32c255d7` | same |
| 17_selection_copy | `6bc7443b52e38bbf` | `6bc7443b52e38bbf` | same |
| 18_selection_read_final | `04f911fbb4880481` | `04f911fbb4880481` | same |
| 19_delete_node | `ddd450f3fc8e28a1` | `ddd450f3fc8e28a1` | same |
| 20_selection_read_after | `fd328dda52ec7bb2` | `fd328dda52ec7bb2` | same |

**CASE 序列覆盖的分支**（每一支都被真的执行到，因为响应是逐字节比较的）：

| 被上提的助手 | 分支 | 覆盖步 |
|---|---|---|
| `edited_scene_root` | 编辑器进程返回真根 | 全部 20 步（每个工具都先取根） |
| `find_node` | `"."` / 裸根名 | 03、09、12 |
| | 相对路径命中 | 04、05、08、10 |
| | `./` 前缀（`Node::get_node` 自己解析） | 07 |
| | 带根名前缀重试 | 06 |
| | 未命中 → `nullptr` → `-32001` | 14、16 |
| | `editor_write_scene_editor.cpp` 的第二个调用点 | 10、12、14、17 |
| | `editor_read_scene_inspector.cpp` 的第三个根调用点 | 02、11、13、18、20 |

### 1.3 U1 的 doctest（红→绿）

新增 `TEST_CASE("[MCPServer] the hoisted editor node helpers keep the migration source's resolution")`：
用裸 `Node` 树（`Root > Child > Grand`）断言 6 个解析分支（`.`、裸根名、相对路径、嵌套相对路径、
根名前缀重试、未命中）+ 「`Root/Nope` 不是通用后缀搜索」+ 无 `SceneTree` 时 `edited_scene_root()==nullptr`。

**红**：把 `tools/` 回退到 PRE（保留新测试）后构建，**exit 2**，编译器输出（节选）：

```
.\modules/mcp_server/tests/test_mcp_server.h(7715): error C2039: "find_node": 不是 "MCPTools" 的成员
.\modules/mcp_server/tests/test_mcp_server.h(7715): error C3861: "find_node": 找不到标识符
.\modules/mcp_server/tests/test_mcp_server.h(7726): error C2039: "edited_scene_root": 不是 "MCPTools" 的成员
.\modules/mcp_server/tests/test_mcp_server.h(7726): error C3861: "edited_scene_root": 找不到标识符
scons: *** [bin\obj\tests\test_main.windows.editor.x86_64.obj] Error 2
```

（DESIGN-DETAIL §1.4 明确允许「编译失败也算红阶段证据」。）

**绿**（`--version = 4.8.dev.custom_build.805899b4e`，exit 0）：

```
[doctest] test cases:  131 |  131 passed | 0 failed | 1429 skipped
[doctest] assertions: 4395 | 4395 passed | 0 failed |
[doctest] Status: SUCCESS!
```

## 2. 本批两组的逐工具表

### 2.1 `editor_node_read`（6 个，`channel=editor` / `scope=editor` / `mutating=false`）

`C++ 落点` 列全部是 `tools/editor_node_read.cpp` 的静态 `_tool_*`；`H` 表示
`tools/editor_node_read.h` 里为 doctest 可达而导出的节点级 helper。

| new_name | 迁移源 | 可观察契约（参数 / 返回 / 错误） | 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `editor_get_node_properties` | `node.rs:232-266` | `path`(必,string)、`properties`(选,string 数组)；成功 `{node_path,type,properties:{名:值}}`；缺参 `-32602`；`properties` 非数组/含非字符串 `-32602`；节点不存在 `-32001`；**点名属性不存在或不可读 → `-32001` + `suggestion`**；全量列举跳过 `_` 前缀与 `script` | `_tool_get_node_properties` + `H:node_properties` | **Q2/Q3/Q5 三处纠正**：过滤后剩空不再静默回 `properties:{}`（§6.6 第 8 例）；非字符串元素不再静默丢弃；`node_path` 回显解析后的根相对路径 |
| `editor_get_node_groups` | `node.rs:471-498` | `node_path`(必,string)；成功 `{node_path,groups,count}`；缺参 `-32602`；节点不存在 `-32001`；`_` 前缀内部组不可见 | `_tool_get_node_groups` | 键名与迁移源**一致**（`node_path`/`groups`/`count`，读迁移源确认）；`node_path` 归一化回显 |
| `editor_find_nodes_in_group` | `node.rs:564-598` | `group`(必,string)；成功 `{group,nodes:[{name,path,type}],count}`；空结果 = 成功 `count:0`；缺参 `-32602` | `_tool_find_nodes_in_group` + `H:node_entry` `H:collect_nodes` | 一致；前序确定序，`path` 根相对 |
| `editor_find_nodes_by_type` | `batch.rs:105-144` | `type`(必,string)；成功 `{nodes,count}`；空结果 = 成功 `count:0`；缺参 `-32602` | `_tool_find_nodes_by_type` + `H:collect_nodes` | 一致；两条类型判定 `get_class()==type \|\| is_class(type)` 都保留 |
| `editor_get_node_signals` | `editor.rs:460-507` | `node_path`(必,string)；成功 `{node_path,type,signals:[{name,args:[{name,type}],connections:[{target,method}]}],count}`；缺参 `-32602`；节点不存在 `-32001` | `_tool_get_node_signals` + `H:signal_entries` | ①`args[].type` 用 `Variant::get_type_name`（`"int"`/`"Vector2"`）而不是 `str(arg["type"])` 的枚举数字串 —— **显式偏离**，契约未规定拼写；②节点解析用共享的 `MCPTools::find_node`，而迁移源用 `root.find_node(path,true,false)`（按名字递归搜） |
| `editor_list_signal_connections` | `batch.rs:207-259` | `node_path`(选,string,子串)、`signal_name`(选,string,子串)；成功 `{connections:[{source,signal,target,method}],count}`；参数类型错 `-32602` | `_tool_list_signal_connections` + `H:collect_signal_connections` | **收全部连接、不过滤 `CONNECT_PERSIST`**（判别点，实测 46 条里 43 条是编辑器运行时连接）；`target` 为 `Callable` 无对象/非 Node 时 `""`；遍历序改为自然前序（集合相同） |

`editor_node_read` 的实现纪律：`require_editor_ui` → `MCPTools::edited_scene_root()` →（有 `node_path` 者）
`MCPTools::find_node()`；成功一律 `content_result`，失败一律 `MCPToolError`；空结果是成功。

### 2.2 `editor_node_instantiate`（4 个，`channel=editor` / `scope=editor` / `mutating=true`）

| new_name | 迁移源 | 可观察契约（参数 / 返回 / 错误） | 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `editor_add_scene_instance` | `scene.rs:284-333` | `scene_path`(必,res://)、`parent_path`(选,默认`.`)；`name`(选,默认空)；成功 `{node_path,scene_path,name}`（`name` 读回引擎实际值）；缺参 `-32602`；非 `res://`/含 `..` → `-32602`；文件不存在 `-32001`；父不存在 `-32001`；加载/实例化失败 `-32000`+suggestion | `_tool_add_scene_instance` + `H:add_typed_child` | `scene_path` 经 `normalize_project_path` 归一（迁移源比原始串）；`name` 为空时不 `set_name`（保留场景根名）；加载失败 `-32000` 而非迁移源的 `-32603` |
| `editor_add_raycast` | `physics.rs:67-82` | `parent_path`(选,默认`.`)、`name`(选,默认`"RayCast"`)、`dimension`(选,默认`"2d"`)；成功 `{added:true,name,node_path,type}`；参数类型错 `-32602`；父不存在 `-32001` | `_tool_add_raycast` + `H:add_typed_child` | `dimension=="2d"` → `RayCast2D`，**其余一切**（含 `"3d"` 与任意值）→ `RayCast3D`（`match` 只有 `"2d"` 分支，怪癖保留）；`type`/`node_path` 是**新增**读回键；父节点不存在时迁移源的 `get_node_as` 给出空 `Gd` 并继续，本实现先拒答、不留孤儿 |
| `editor_add_mesh_instance` | `scene_3d.rs:73-83` | `parent_path`(选,默认`.`)、`name`(选,默认`"Mesh"`)；成功 `{added:true,name,node_path,type}`；参数类型错 `-32602`；父不存在 `-32001` | `_tool_add_mesh_instance` + `H:add_typed_child` | 新增 `node_path`/`type` 读回键；`memnew(MeshInstance3D)` 取代 `ClassDB::instantiate` |
| `editor_add_gridmap` | `scene_3d.rs:256-280` | `mesh_library_path`(必,res://)、`parent_path`(选,默认`.`)、`name`(选,默认`"GridMap"`)；成功 `{name,parent_path,mesh_library_path,created:true,node_path,type,mesh_library_set}`；缺参 `-32602`；库加载失败 `-32001`+suggestion；父不存在 `-32001` | `_tool_add_gridmap` + `H:attach_mesh_library` `H:add_typed_child` | **本批唯一的行为纠正**：迁移源 `if let Some(lib)` 静默忽略加载失败后仍回 `created:true`；本实现 `-32001`+suggestion 且**不创建节点**。另新增 `node_path`/`type`/`mesh_library_set` 键、`parent_path` 归一化回显；`mesh_library` 写入经 `MCPTools::write_node_property`（`running_game_node_write.h` 的唯一定义） |

## 3. 两处行为纠正的红→绿全程（PLAYBOOK §6.6）

### 3.1 `editor_get_node_properties` 点名不存在属性（§6.6 **第 8 例**）

**迁移源缺陷**（`node.rs:241-261`）：`filter` 把不在属性表里的名字全部过滤掉之后**无条件回成功**，
于是 `properties:["typo"]` 得到 `{"properties": {}}` —— 一个「工具从未检查过」的断言，
与 TASK-014 D-1（`running_game_set_node_property`）同一失效模式。

**修法**：过滤之外再做一次「点名即须有答」的检查——申请名单里任一名字没有出现在答案里就是
`-32001` + `data.suggestion`（并区分「表里根本没有」与「被可见性规则挡在列举之外」两种措辞）。
`properties: []`（给了但为空）仍是成功且 `properties:{}`。

### 3.2 `editor_add_gridmap` 库加载失败

**迁移源缺陷**（`scene_3d.rs:273-280`）：`if let Some(lib) { gridmap_node.set("mesh_library", lib) }`
—— 加载失败被静默跳过，函数仍回 `{"created": true}`。调用方无法区分「材质库挂上了」与「没有」。

**修法**：库先加载、后建节点；加载不出 `MeshLibrary` 即 `-32001` + `suggestion`，`memdelete` 半成品。

### 3.3 红/绿两阶段的真实输出（**最终测试文本**上重跑，exit 1 → exit 0）

红版 = 把两处纠正**临时**还原成迁移源语义（`editor_node_read.cpp` 的 `return true;`、
`editor_node_instantiate.cpp` 的 `return true;`），构建 exit 0，运行 `--test-case="[MCPServer]*"`：

```
TEST CASE:  [MCPServer] editor_get_node_properties refuses a property it was asked for and cannot answer
.\modules/mcp_server/tests/test_mcp_server.h(7985): ERROR: CHECK_FALSE( MCPTools::node_properties(node, &filter, properties, error) ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(7986): ERROR: CHECK( error.code == -32001 ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(7987): ERROR: CHECK( error.message.contains("no_such_prop_xyz") ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(7998): ERROR: CHECK_FALSE( MCPTools::node_properties(node, &filter, properties, error) ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(7999): ERROR: CHECK( error.code == -32001 ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(8000): ERROR: CHECK( error.message.contains("not readable by name") ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(8011): ERROR: CHECK_FALSE( MCPTools::node_properties(node, &filter, properties, error) ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(8012): ERROR: CHECK( error.code == -32001 ) is NOT correct!
TEST CASE:  [MCPServer] editor_add_gridmap refuses a mesh library it could not load
.\modules/mcp_server/tests/test_mcp_server.h(8378): ERROR: CHECK_FALSE( MCPTools::attach_mesh_library(probe, "res://no_such_mesh_library_xyz.tres", error) ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(8379): ERROR: CHECK( error.code == -32001 ) is NOT correct!
.\modules/mcp_server/tests/test_mcp_server.h(8380): ERROR: CHECK( error.message.contains("no_such_mesh_library_xyz") ) is NOT correct!
[doctest] test cases:  139 | 137 passed |  2 failed | 1429 skipped
[doctest] assertions: 5185 | 5174 passed | 11 failed |
[doctest] Status: FAILURE!
```

绿（修复写回后重建，同一命令）：

```
[doctest] test cases:  139 |  139 passed | 0 failed | 1429 skipped
[doctest] assertions: 5185 | 5185 passed | 0 failed |
[doctest] Status: SUCCESS!
```

其余 137 个用例在红版里全绿，证明这 11 条断言确实**只因缺行为而失败**。

## 4. 注册、计数与 manifest

- `tools/registration.cpp`：在 TASK-015 的两行之后追加两组各一行 include + 一行调用，
  **顺序 = manifest 顺序**（`editor_node_instantiate` 在 `editor_node_read` 之前，
  见 `docs/tool-groups-b3.json` 的组序）。`tools/list` 实测顺序因此是
  `… editor_set_auto_dismiss_dialogs > editor_add_scene_instance > editor_add_raycast >
  editor_add_mesh_instance > editor_add_gridmap > editor_get_node_properties > … > editor_list_signal_connections`。
- `tests/test_mcp_server.h`：既有硬编码计数 `76`/`59` → **`86`/`69`**（4 个用例里的 4 处
  `get_tool_count()`、4 处 `get_visible_tool_count(true)`、3 处 `editor_list.size()`），
  游戏侧 `40`/`40` 不变；新增 2 个「editor-only 且携带 N 个工具」用例（6 个与 4 个）。
- `docs/tool-groups-b3.json`：**只改了这两组的 `implemented` 布尔值**为 `true`，其余一字未动
  （`git diff` 为 2 行 +/2 行 -）。
- `docs/scripts/check_tool_groups.py --batch B3`：`TOOL-GROUPS-B3 CHECK PASS`（exit 0），
  `implemented=true groups = 3, carrying 20 tool(s)`。

## 5. 门② 三类证据与两条活证据链（真实请求/响应，端口 9888 / 9889）

采集纪律：请求体 `ConvertTo-Json` 落盘后 `curl.exe --data-binary @file`；响应体一律
`curl.exe -s -o <file>` 并打印 `bytes`/`sha256`；**没有任何响应体经过管道或 `Out-File`**。

### 5.1 scope 缺席证据（本批硬要求）

```
[PASS] scope_editor_serves_all_ten :: missing from 9888: []
[PASS] scope_game_serves_none :: leaked into 9889: []
[PASS] scope_game_call_is_32601_editor_get_node_properties :: code=-32601 message='Method not found: editor_get_node_properties'
（10 个工具各有一条 scope_game_call_is_32601_<tool>，全部 -32601 且 result 为 null）
```

### 5.2 成功类（10/10 都构造出来了）

```
succ_get_node_properties_filtered  {"node_path":"ReadProbe","properties":{"position":{"x":1.0,"y":2.0}},"type":"Node2D"}
succ_get_node_groups              {"count":0,"groups":[],"node_path":"ReadProbe"}
succ_find_nodes_in_group          {"count":1,"group":"mcp016_probe","nodes":[{"name":"ReadProbe","path":"ReadProbe","type":"Node2D"}]}
succ_find_nodes_by_type           count=3 paths=[., Child, ReadProbe]
succ_get_node_signals             node_path=ReadProbe type=Node2D，ready.connections=[{target:ReadProbe, method:queue_free}]
                                  child_entered_tree.args[0]={name:node, type:Object}
succ_list_signal_connections      count=46，其中本批自己建的那条在列
succ_04_set_node_groups           {"added":["mcp016_probe"],"groups":["mcp016_probe"],"node_path":"ReadProbe","removed":[]}   （读族的读回前置）
succ_add_gridmap                  {"created":true,"mesh_library_path":"res://scenes/lib.tres","mesh_library_set":true,
                                   "name":"GM","node_path":"GM","parent_path":".","type":"GridMap"}
chainB_01_add_raycast_2d          {"added":true,"name":"RC","node_path":"RC","type":"RayCast2D"}
chainB_03_add_mesh_instance       {"added":true,"name":"MI","node_path":"MI","type":"MeshInstance3D"}
chainB_07_add_scene_instance      {"name":"Inst","node_path":"Inst","scene_path":"res://scenes/inst.tscn"}
```

（`editor_add_scene_instance` / `editor_add_raycast` / `editor_add_mesh_instance` 的成功类在链 B 上
一并给出，见表里的 `chainB_*` 行；`editor_add_gridmap` 的成功类在 `succ_add_gridmap`。）

**全量列举的线上形态**（`editor_get_node_properties {path:"ReadProbe"}`，1743 bytes，
`sha256=1e31f15d95116802b3eafa4b8541967cd4ff5bf30ebffeb426968626b1a67326`）包含
`"position":{"x":1.0,"y":2.0}`、`"name":"ReadProbe"`、`"type":"Node2D"`，
以及 Godot 检查器自己的分组标签 `"Transform":null` / `"Node":null` —— 迁移源同样会返回它们
（它的唯一过滤是 `_` 前缀与 `script`），按 PLAYBOOK §6.8 **保留**。

### 5.3 缺参类（7/7，`-32602` 且 `result` 为 null）

```
miss_get_node_properties / miss_get_node_groups / miss_find_nodes_in_group / miss_find_nodes_by_type /
miss_get_node_signals / miss_add_scene_instance / miss_add_gridmap    -> 全部 -32602 + 对应 message
```

**不可构造声明（缺参类）**：`editor_add_raycast`、`editor_add_mesh_instance`、
`editor_list_signal_connections` 的契约里**没有任何必填参数**，所以它们**没有缺参类**；
它们的拒答类是下面的类型错类。这条在脚本里是一条显式 PASS（`miss_not_constructible_for_three_tools`）。

### 5.4 类型错类（7/7，`-32602`；迁移源是静默忽略）

```
type_get_node_properties_properties   properties="position"      -> -32602 'properties' must be an array of strings
type_get_node_properties_element      properties=["position",7]  -> -32602 'properties[1]' must be a string
type_find_nodes_by_type               type=7                     -> -32602 'type' must be a string
type_list_signal_connections          signal_name=7              -> -32602 'signal_name' must be a string
type_add_raycast_dimension            dimension=7                -> -32602 'dimension' must be a string
type_add_mesh_instance_name           name=7                     -> -32602 'name' must be a string
type_add_gridmap_path                 mesh_library_path=7        -> -32602 'mesh_library_path' must be a string
```

### 5.5 底层失败类（8/8，`-32001` 且 `result` 为 null）

```
fail_get_node_properties_missing / fail_get_node_groups_missing / fail_get_node_signals_missing  -> Node 'NoSuchNode' not found
fail_add_scene_instance_missing_file   -> Scene 'res://scenes/no_such_scene.tscn' not found
fail_add_scene_instance_missing_parent / fail_add_raycast_missing_parent /
fail_add_mesh_instance_missing_parent / fail_add_gridmap_missing_parent -> Parent 'NoSuchParent' not found
```

**不可构造声明（底层失败类）**：`editor_find_nodes_in_group`、`editor_find_nodes_by_type`、
`editor_list_signal_connections` **没有底层失败类**——「没有匹配」按契约是成功 `count:0`
（已由 `succ_find_nodes_in_group_empty_is_success`、`succ_find_nodes_by_type_empty_is_success` 正面证明），
而它们唯一还需要的外部状态（打开着的编辑场景）正是本次运行所处的状态。
`editor_add_gridmap` 的第三个失败类（库加载失败）见 §5.6。

### 5.6 两处纠正的线上复现

```
fix_get_node_properties_refuses_a_named_missing_property
  code=-32001 message='Property 'no_such_prop_xyz' on node 'ReadProbe' not found' result_is_null=True
  suggestion='Call editor_get_node_properties without 'properties' to list every readable property of this node'
fix_get_node_properties_refuses_the_script_property_by_name
  code=-32001 message='Property 'script' on node 'ReadProbe' is not readable by name not found'
fix_add_gridmap_refuses_an_unloadable_mesh_library
  code=-32001 message='MeshLibrary 'res://scenes/no_such_library.tres' not found' result_is_null=True
  suggestion='editor_add_gridmap does not create a GridMap without its mesh library. …'
fix_add_gridmap_leaves_no_orphan :: paths=[Main, Main/Child, Main/World, Main/ReadProbe]
```

最后一条是「什么都不留下」的实测：失败的 `editor_add_gridmap` 没有在编辑场景里留下任何节点。

### 5.7 链 A：**TASK-015 的写族改、本批的读族读回**（每一步都断言观察到的状态变化）

```
chainA_01_add_node              {"name":"Chain","node_path":"Chain","type":"Node2D"}
chainA_02_set_property          {"new_value":{"x":7.0,"y":9.0},"node_path":"Chain","old_value":{"x":0.0,"y":0.0},"property":"position"}
chainA_03_read_back_the_written_property  {"node_path":"Chain","properties":{"position":{"x":7.0,"y":9.0}},"type":"Node2D"}
chainA_04_set_groups            {"added":["chain_g"],"groups":["chain_g"],"node_path":"Chain","removed":[]}
chainA_05_read_back_the_group   {"count":1,"groups":["chain_g"],"node_path":"Chain"}
chainA_06_find_in_group         {"count":1,"group":"chain_g","nodes":[{"name":"Chain","path":"Chain","type":"Node2D"}]}
chainA_07_connect_signal        {"connected":true,"signal":"ready","source":"Chain","target":"."}
chainA_08_get_signals           ready.connections=[{"method":"queue_free","target":"."}]
chainA_09_list_connections      count=12，其中 Chain -> '.' queue_free 那一条在列
chainA_10_disconnect            {"disconnected":true,"signal":"ready","source":"Chain","target":"."}
chainA_11_connections_are_gone  count=0 entries whose source is Chain = 0
chainA_12_delete_node           {"deferred":true,"deleted":true,"path":"Chain"}
chainA_13_node_is_gone          paths=[Main, Main/Child, Main/World, Main/ReadProbe, Main/GM]
chainA_14_group_is_empty_again  {"count":0,"group":"chain_g","nodes":[]}
```

链 A 同时是 §6.6 第 8 例的线上复现（`fix_01`），并且证明了两件事：读族读到的**正是写族写下的值**
（7/9 与 `chain_g`），以及 `editor_list_signal_connections` 与 `editor_get_node_signals` 对同一条连接
给出**互相一致**的两半（嵌套 vs 扁平）。

### 5.8 链 B：实例化族 → 读族

```
chainB_00_tree_before           paths=[Main, Main/Child, Main/World, Main/ReadProbe, Main/GM]
chainB_01_add_raycast_2d        {"added":true,"name":"RC","node_path":"RC","type":"RayCast2D"}
chainB_02_add_raycast_any_other_dimension_is_3d  {"added":true,"name":"RC3","node_path":"RC3","type":"RayCast3D"}
chainB_03_add_mesh_instance     {"added":true,"name":"MI","node_path":"MI","type":"MeshInstance3D"}
chainB_04_read_back_raycast2d   paths=[RC]
chainB_05_read_back_gridmap     paths=[GM]
chainB_06_read_back_mesh        paths=[MI]
chainB_07_add_scene_instance    {"name":"Inst","node_path":"Inst","scene_path":"res://scenes/inst.tscn"}
chainB_08_read_back_the_instance_type   node_path=Inst type=Node3D scene_file_path=res://scenes/inst.tscn
chainB_09_add_scene_instance_keeps_the_scene_root_name  {"name":"InstRoot",…}
chainB_10_tree_contains_every_created_node
  paths=[Main, Main/Child, Main/World, Main/ReadProbe, Main/GM, Main/RC, Main/RC3, Main/MI, Main/Inst, Main/InstRoot]
```

`editor_add_gridmap` 的**成功类是可构造的**：scratch 工程里的 `res://scenes/lib.tres`
（`[gd_resource type="MeshLibrary" format=3]`，无条目）真的加载成功并真的写进了 `mesh_library`
（`mesh_library_set=true`）。因此本任务**没有需要声明为不可构造的成功类**。

### 5.9 一个额外发现（写进 PLAYBOOK §3 的坑位）：PowerShell 5.1 读不了全量属性列举

`editor_get_node_properties` 的全量列举里同时有 `Transform` 与 `transform`、`Node` 与 `node` 这样的
**仅大小写不同的键**，而 Windows PowerShell 5.1 的 `ConvertFrom-Json` 会直接报
`… contains the duplicated keys 'Transform' and 'transform'`。**工具的答案是对的，限制在解析器**，
所以证据脚本对这两个 payload 改成**按原始字节断言**（`Read-ResponseText`），这反而比解析后再断言更强。
门② 里 46 条连接中 **43 条是编辑器自己的运行时（非持久）连接**
（`ScriptEditor::_queue_update_list`、`SceneTreeEditor::_node_script_changed` 等），
这正是 `editor_list_signal_connections` 与 `editor_analyze_signal_flow` 的判别点。

## 6. 五道门（全部在 `--version == HEAD == c9760a7f8` 的二进制上）

| 门 | 命令 | 结果 | 退出码 |
|---|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group editor_node_read` | 3/3 PASS（6 条 `name/description/inputSchema` 全 True；9889 全 absent） | **0** |
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group editor_node_instantiate` | 3/3 PASS（4 条全 True；9889 全 absent） | **0** |
| ② 三类证据 + 两条活链 + scope 缺席 | `mcp016_node_read_instantiate_evidence.ps1` | **86/86 PASS** | **0** |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | 139/139 用例、5185/5185 断言、0 failed | **0** |
| ④ 全引擎回归 | `--headless --test` | 1565/1565 用例、429467/429467 断言、0 failed、3 skipped | **0** |
| ⑤ 批量收口 | `accept_m1.ps1` ×2 | 22/22 ×2，两次 PASS 清单**逐条相同**（`PASS-SET-IDENTICAL`） | **0 / 0** |

基线对照（只增不减）：
- ③ 上一次（REPORT-015）为 130/130 · 4383；本批 +9 用例、+802 断言；
- ④ 上一次为 1556/1556 · 428665；本批 +9 用例、+802 断言；
- ⑤ 22/22，`implemented tools = 69 (editor endpoint) / 40 (game endpoint); contract = 171`。

门①真实片段（`editor_node_read`）：

```
scope       : editor-only=46 game-only=17 both/shared=23
editor set  : 69 tool(s)
game set    : 40 tool(s)
[PASS] editor_9888_contract_subset
       … | editor_get_node_properties: name=True description=True inputSchema=True | editor_get_node_groups: name=True description=True inputSchema=True | editor_find_nodes_in_group: name=True description=True inputSchema=True | editor_find_nodes_by_type: name=True description=True inputSchema=True | editor_get_node_signals: name=True description=True inputSchema=True | editor_list_signal_connections: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset
       editor_get_node_properties: correctly absent on the game endpoint | …（6 条全 absent）
[PASS] guard_user_port_9877   pid_before=36392 pid_after=36392
3/3 checks passed
```

门①真实片段（`editor_node_instantiate`）：

```
[PASS] editor_9888_contract_subset
       … | editor_add_scene_instance: name=True description=True inputSchema=True | editor_add_raycast: name=True description=True inputSchema=True | editor_add_mesh_instance: name=True description=True inputSchema=True | editor_add_gridmap: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset
       editor_add_scene_instance: correctly absent on the game endpoint | …（4 条全 absent）
3/3 checks passed
```

门⑤真实片段：

```
run1 PASS lines: 22
run2 PASS lines: 22
PASS-SET-IDENTICAL
22/22 cases passed
implemented tools = 69 (editor endpoint) / 40 (game endpoint); contract = 171; known_deviation = per-batch verbatim gate only
```

**门③/④ 的那一次假红必须记录**：一次性跑完五道门的门链脚本从 `modules/mcp_server` 起跑，
于是 doctest 的 `res://` 指向了 `modules/mcp_server` 而不是仓库根，15 个**与本批无关**的既有用例
（`running_game_execute_gdscript`、`project_edit_resource` 等）因为 fixture 文件「找不到」而失败，
并在 5931 行崩溃（exit `0xC0000005`）。把 cwd 改回仓库根重跑即 139/139 与 1565/1565 全绿；
上表的两行是**仓库根**那次运行的结果。这是调用方式问题，不是代码问题，按 §10 记入偏离。
（同一批门里，门④ 更早的一次假红确实抓到了真缺陷，见 §11。）

## 7. 本批后已实现工具总数与剩余计数

```
已实现（本批后）          86  = B1 41 + B2 25 + B3 首组 10 + 本批 10
契约总数                 171
剩余                     85

按批次：
  B3  40 中已实现 20（editor_node_write 10 + editor_node_instantiate 4 + editor_node_read 6）
      → B3 剩余 20（editor_node_batch_write 2 / editor_control_layout_write 1 /
                    editor_node_setup 7 / editor_script_write 2 /
                    project_script_write 2 / project_autoload_write 2 /
                    project_setting_write 1 / project_cross_scene_write 1 /
                    project_resource_uid_read 2）＝20
  B4   7 组 3 组，已实现 0  → 剩余 7
  B5  58 组 26 组，已实现 0 → 剩余 58
  20 + 7 + 58 = 85 ✓
```

端点可见性口径（门①/⑤ 实测）：编辑器端点 69、游戏端点 40；`scope` 分布
`editor-only=46 / game-only=17 / both=23`（46+17+23=86）。

**本批两组成员清单**：

- `editor_node_read`（6）：`editor_get_node_properties`、`editor_get_node_groups`、
  `editor_find_nodes_in_group`、`editor_find_nodes_by_type`、`editor_get_node_signals`、
  `editor_list_signal_connections`
- `editor_node_instantiate`（4）：`editor_add_scene_instance`、`editor_add_raycast`、
  `editor_add_mesh_instance`、`editor_add_gridmap`

## 8. 报告额外小节（DESIGN-DETAIL §8）

1. **§1 助手上提的逐字节等价证明** —— 见本报告 §1（PRE `c26516becc`、20 个 CASE、逐文件 sha256 表、
   diff 计数 0、`grep -c` 结果）。
2. **写族→读族互验链条** —— 见 §5.7（链 A）与 §5.8（链 B）的真实请求与响应片段。
3. **本批后已实现总数与剩余计数** —— 见 §7。

## 9. 本批脚本/文件 sha256

| 文件 | bytes | sha256 |
|---|---|---|
| `tools/tool_helpers.h` | 20098 | `eb0f667ba742a776c4ae115b863627964490ab103450eedbcf9cbb5a0ff00b0f` |
| `tools/tool_helpers.cpp` | 23316 | `74544df2613c83678079f63b54452b58d4b554d03c9fad55ea6c150208a7c179` |
| `tools/editor_node_read.h` | 7939 | `428198aa84a850e06a29e6b45d446f6f984dcd404cdab248460d3d74c8835b78` |
| `tools/editor_node_read.cpp` | 28128 | `aa5a1f144c65bf26ec861f1043d08b86302fb2b2858d194f995d037c3cf37cf8` |
| `tools/editor_node_instantiate.h` | 5540 | `bde12fa5a26051b2111844e54613685f45ed2b164ae7adf3816cf889af54d5c2` |
| `tools/editor_node_instantiate.cpp` | 21066 | `4c61a859e41e36de18eebf739c8e4c9baae5139d80aa8eefae900e681dd3edec` |
| `tools/registration.cpp` | 6219 | `bce3ac3f86ea9479aee50ae8b270988e5dd8b3b309fecf5402f921e16ca659ed` |
| `tests/test_mcp_server.h` | 371943 | `732ae6480722d4970dbbc6040b29c3bb4be0225620344b37369bb4b4225f5462` |
| `docs/tool-groups-b3.json` | 8535 | `9a1b3ddf25318184cc0ed7e59fb21fcf90de9a6e4039fa2b7155b9bafb61cfe3` |
| `scripts/accept_m1.ps1` | 65172 | `ac4f126495fa52f93f20bf1395c707b9b49b26dfc71983dc7132cdf71b658d6f` |
| `scripts/mcp016_hoist_equivalence.ps1` | 23909 | `9b3afc0250fa221d690f3216e1a6e540c4f6f6af8ffc87a690debc68270de6a6` |
| `scripts/mcp016_node_read_instantiate_evidence.ps1` | 50609 | `77d62a463bd9b971ae0c6e6c95b622e5440b6bf00831bab3b0d8cf75c0495165` |
| `bin/godot.windows.editor.x86_64.console.exe`（**门所绑定的那次构建**，`--version` = `4.8.dev.custom_build.c9760a7f8`） | 300544 | `700c02a16af5d02a54b76489ad8d4549fa240a966a546595172aae9d81f2633e` |

未触碰契约 / 映射 / 契约生成器：`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、
`docs/tools_list.*`、`scripts/gen_renamed_contract.py`、`scripts/gen_b2_game_schema.py` 全部零改动
（`git status` 里没有任何这些文件）。除任务书指定的两个 `implemented` 布尔值外，
`docs/tool-groups*.json` 一字未动。

## 10. deviations（与任务书 / PLAYBOOK / 设计文档的每条偏离）

1. **§1.3 的 CASE 序列被替换了两次，理由都是「不可能在两边同时成立」**：
   (a) 设计文档列了两条 `editor_get_node_properties` 调用，但那是本批 U2 的工具，在 PRE 与 U1 提交点
   都**不存在**（PRE 二进制会回 `-32601`，「after」回真答案，比较就失去意义）——改用
   `editor_set_node_property`/`editor_rename_node`/`editor_duplicate_node`/`editor_reparent_node`
   覆盖完全相同的 `find_node` 分支；
   (b) 设计文档没写读回工具，但我原先把 `editor_get_scene_tree` 当读回工具时会**逐字节不等**：
   它的 `path` 是 `Node::get_path()`（编辑器绝对路径，含每次运行不同的 `@EditorNode@<id>`），
   与本次重构无关地漂移 —— 改用 `editor_get_selection`/`editor_set_node_selection`
   （根相对路径），它同时覆盖 `editor_write_scene_editor.cpp` 里被上提的那个调用点。
2. **路径解析两个助手之外的四个参数助手是文件私有的**（`_require_node_path`、
   `_optional_parent_path`、`_require_non_empty_string`、`_optional_string_array`）。
   TASK-016 §1 只点名了路径解析的两个助手；这些是参数措辞助手（每个 6–15 行），
   上提会扩大 B1 文件的改动面而不消除语义重复。`_relative_path` 按 §1 原地保留。
3. **`editor_get_node_signals` 的节点解析**：迁移源用 `root.find_node(path,true,false)`（按名字递归搜），
   本实现用共享的 `MCPTools::find_node`。依据 DESIGN-OVERVIEW §4.2 / DESIGN-DETAIL §2 的统一前置。
   后果：`node_path:"Grand"`（裸名字）在迁移源可命中、在本实现为 `-32001`；`"Child/Grand"` 反之。
4. **`signal_entries` 的签名**：DESIGN-DETAIL §2.2 写作 `Array signal_entries(Node *p_node)`，
   但迁移源的 `connections[].target` 是 `root.get_path_to(conn_obj)`（editor.rs:481），
   没有根就拼不出这个字段 —— 实现为 `signal_entries(Node *p_root, Node *p_node)`。
   `collect_signal_connections` 的参数顺序同理按实现需要为 `(p_node, p_root, …)`。
5. **`args[].type` 用类型名**（`"int"`/`"Object"`/`"Vector2"`）而不是迁移源 `str(arg["type"])`
   的枚举数字串 —— 这是 DESIGN-DETAIL §2.1 明确要求的显式偏离，契约未规定拼写。
   线上证据：`child_entered_tree.args[0]={name:node, type:Object}`。
6. **`collect_signal_connections` 的遍历序**改为自然前序（迁移源的 GDScript 用栈，
   子节点是**逆序**）。集合完全相同、契约不规定顺序、与同组 `collect_nodes` 的 `nodes[]` 前序一致；
   同一环集内可复现（PLAYBOOK §6.8 的「非确定行为改确定序」同理）。
7. **`editor_get_node_properties` 的三个边界判定**：点名不存在 → `-32001`（Q2）；
   点名 `script`/`_` 前缀这类「表里有但列举不显示」的名字 → `-32001`（措辞区分，避免同一句
   把两种原因说成一种）；`properties: []`（给了但为空）→ 成功且 `properties:{}`（迁移源亦然）。
8. **`editor_add_scene_instance` 的 `scene_path` 经 `normalize_project_path`**：非 `res://` 或含 `..`
   是 `-32602`，回显是归一化路径（PLAYBOOK §6.3/§6.7）；迁移源比的是原始串（`res://./a.tscn` 在它那里
   是「文件不存在」）。加载/实例化失败按 DESIGN-DETAIL §3 用 `-32000`（`tool_state`），
   迁移源用 `-32603`。
9. **`editor_add_gridmap` 的返回键集扩展**：保留迁移源的 `name`/`parent_path`/`mesh_library_path`/`created`，
   新增 `node_path`/`type`/`mesh_library_set`；`parent_path` 归一化回显。理由：不回读就无法验证。
10. **`editor_add_raycast` / `editor_add_mesh_instance` 新增 `node_path`/`type`**：迁移源只回
    `{"added":true,"name":<请求值>}`，那既不是实测名也不是可喂回下一个工具的路径。
11. **门链脚本那一次的 ③/④ 假红是调用方式错误**（cwd = `modules/mcp_server`，`res://` 指错目录，
    15 个既有用例假失败 + 一次 `0xC0000005`）。改在仓库根重跑后全绿；§6 的表是后者。
    （与 §11 的 `GridMap` 崩溃是两回事：那一次发生在**正确的** cwd 下。）
12. **`--import` 的 0xC0000005 是间歇性的**：等价性脚本第一次运行的首个 import 以
    `-1073741819` 退出（stderr 只有 `Parameter "singleton" is null. At: EditorNode::is_cmdline_mode
    (editor\editor_node.cpp:6732)`）；紧接着对三个**全新目录**的同一工程 import 全部 exit 0，
    之后每一次也都 exit 0。两个脚本因此把 import 做成**最多 3 次重试**并把尝试次数打进证据，
    而不是把它藏起来（PLAYBOOK §7.3 的 append-only 勘误精神）。
13. **`editor_add_gridmap` 的 doctest 接收者从 `GridMap` 改成裸 `Node`**（见 §11）。
14. **`docs/spec/TASK-016/` 是工作树里新增的未跟踪目录**（决策者的阶段一/二/三工件）。
    按纪律实现者不改规范文档，故我**未创建、未修改、未提交**它；任务书 §"工作树收尾" 里
    只列了四个既有未跟踪物，这一条是第五个，记在此处。
15. **`registration.cpp` 的两行顺序**按要求书 = manifest 顺序（`editor_node_instantiate`
    在 `editor_node_read` 之前），这与实现顺序（先 U2 后 U3）相反，也因此在 `c1f2b82ace`
    单独调整过一次；`tools/list` 顺序不是契约（DESIGN-DETAIL §17.4），门① 只把它当证据打印。
16. **门的运行提交点与交接时的二进制绑定**：五道门跑在 `c9760a7f88`（二进制 `--version` 自报
    `c9760a7f8`，一致），§5/§6/§7 的全部输出都来自那一次运行；本报告自身是一个「仅新增报告」的提交，
    发生在门之后，所以仓库最终 HEAD 会比门所绑定的提交多一个提交（与 REPORT-015 §11.16 的处理相同）。
    为了让**交接时**也满足 PLAYBOOK §3 第 0 步的机械校验（`--version` hash 前缀 == `git rev-parse --short HEAD`），
    报告提交之后又**原样重建了一次**：源码与门所测的完全一致，只有编译进 `version.h` 的 revision 串
    从 `c9760a7f8` 前进到报告提交后的 HEAD，因此 §9 里那个二进制 sha256 是**门所绑定构建**的哈希，
    交接时磁盘上的二进制哈希与之不同（同尺寸 300544 bytes），这是预期行为，已在此显式说明。

## 11. 一个真实缺陷：`GridMap` 在 doctest 进程里可能崩溃（门④ 抓到）

**发现过程**：门④ 第一次（正确 cwd 下）运行报
`TEST CASE: [MCPServer] editor_add_gridmap refuses a mesh library it could not load` →
`FATAL ERROR: test case CRASHED: SIGSEGV`，`1565 | 1564 passed | 1 failed`。

**二分**（都在正确 cwd 下、同一二进制）：

```
--test-case-exclude="[MCPServer] the editor node read collectors keep the migration source's order and shape"
    -> 183 | 182 passed | 1 failed        （排除读族收集器用例后仍然崩，说明不是它）
--test-case-exclude="[MCPServer] editor_add_gridmap refuses a mesh library it could not load"
    -> 1564 | 1564 passed | 0 failed      （只排除 gridmap 用例 → 全绿）
```

即崩溃点**只**和「在 doctest 进程里 `memnew(GridMap)` / `memdelete(GridMap)`」这一件事有关，
而且只在**其它测试套件先跑过**时发生：`--test-case="[MCPServer]*"` 单独跑（含同一个用例、同一个
`GridMap`）是通过的。崩溃发生在 `gridmap` 模块的构造/析构路径上，不在本模块代码里
（本模块的 `attach_mesh_library` 在拒答路径上从不碰接收者的属性）。

**处置**：该 doctest 的接收者改为裸 `Node`（`attach_mesh_library` 的拒答发生在任何属性访问之前，
接收者类型不属于被钉的语义）；`GridMap` 的真实路径（用真 `MeshLibrary` 建、坏库拒、不留孤儿）
由门② 的线上证据覆盖（§5.2/§5.6/§5.8）。改后门③ 139/139、门④ 1565/1565 全绿。
**这是留给后续任务的缺陷报告**：`modules/gridmap` 在 `tests=yes` 的全量 doctest 进程里
构造 `GridMap` 会崩，值得单独定位（不在本任务范围，且不能通过改本模块规避——本模块的正确实现
在编辑器进程里必须能 `memnew(GridMap)`，门② 已实测它工作正常）。

## 12. blockers

无。

- 网络/依赖：本任务不需要网络，未安装任何依赖，未访问 `100.105.152.101:18080`。
- 端口：全程只用 9888/9889；9877 只做「pid 前后一致」观测（`36392 → 36392`），
  门①（两次）、门②、门⑤（两次）各自的守卫均 PASS。
- 工作树：`git status` 只剩四个既有未跟踪物（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、
  `install-deps-m0.cmd`）加上决策者的 `modules/mcp_server/docs/spec/`（§10.14）；
  本任务未新增任何其它未跟踪残留。

## 13. next_step_recommendation

1. **B5 的 `editor_scene_3d_write` 必须注意 §11 的 `GridMap` 崩溃**：如果后续任务要在 doctest 里
   直接构造 `GridMap`，会踩同一个 SIGSEGV；先定位 `modules/gridmap` 在测试进程里的状态依赖。
2. **`editor_get_node_properties` 的全量列举里含 Godot 检查器的分组标签**（`"Transform":null` 等）。
   迁移源同样如此（怪癖保留），但它有一个副作用：**Windows PowerShell 5.1 的 `ConvertFrom-Json`
   直接拒绝这种 payload**。若后续要把工具结果喂给 PowerShell 门脚本，必须用原始字节或别的解析器。
3. **B3 剩余 20 个里最顺的下一组是 `editor_node_batch_write`（2 个）**：它复用本批已经上提并验证过的
   `find_node` 与 `write_node_property`，且 `editor_add_nodes_batch` 的部分失败策略可以直接沿用
   `editor_add_node` 的「先查属性表再写、失败销毁半成品」形状。
4. **`editor_script_write`（2 个）与 `project_cross_scene_write`（1 个）应当各自单独成批**：
   前者要面对 `editor_execute_gdscript` 的沙箱/超时问题（B2 的 `running_game_execute_gdscript` 有先例），
   后者是多场景事务（打开→改→保存），比本批的纯内存写复杂一个量级。
5. **决策层登记建议（我无权改 `DECISIONS.md`，它在 `modules/mcp_server/**` 之外）**：
   - D-?：「`--import` 的 `0xC0000005` 是间歇性的；证据/等价性脚本一律做有界重试并把尝试次数写进证据」
     —— §10.12。
   - D-?：「doctest 里不要直接构造 `GridMap`；模块代码里 `memnew(GridMap)` 是允许的」—— §11。
   - D-?：「`signal_entries` 这类需要根的 helper，其签名以『迁移源真正用到的输入』为准，
     不以设计文档的简化签名为准」—— §10.4。