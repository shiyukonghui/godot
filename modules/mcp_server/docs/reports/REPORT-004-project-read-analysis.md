# REPORT-004 — 移植组 `project_read_analysis`（7 个只读项目工具）

- **status**：`pass` — 五道门全绿（退出码 0），无 blocker；工作树除既有未跟踪物外干净。
- **任务书**：`docs/tasks/TASK-004-project-read-analysis.md`；通用规范 `docs/tasks/PLAYBOOK-group-port.md`（两者都已完整阅读）。
- **分支**：`feature/mcp-server-module`；**未 push**。
- **范围**：只改 `modules/mcp_server/**`。`F:\moonbit-hof-rs`、`godot_mcp_gdext`、契约/映射/生成器全程**只读**
  （见 §6）：`docs/tool-rename-map.json` 与 `docs/tools_list.renamed.json` **一个字节都没动**。
- **端口纪律**：用户编辑器（PID **36392**）占 **9877**，全程 `pid_before=36392 pid_after=36392`（门①、门⑤ 各自记录）；
  测试只用 **9888（编辑器）/9889（游戏）**；scratch 一律在 `%TEMP%`。所有引擎进程都是我起的 PID，结束后无残留。
- **证据采集**：一律 `curl.exe --data-binary @file`（JSON 作为命令行参数会被 Windows 引号规则吃掉内部双引号 → `-32700`）。

---

## 0. commits

| sha | 一行说明 |
|---|---|
| `4fdaf368b1` | `mcp_server: TASK-004 - failing tests for the project_read_analysis group (TDD red)`（2 files changed, +787 / −3） |
| `9d05a2d99a` | `mcp_server: TASK-004 - project_read_analysis group, 7 read-only project tools (TDD green)`（4 files changed, +1280 / −1） |
| `af9969a4f0` | `mcp_server: TASK-004 - multi-group contract-subset gate, cross-process restart case, REPORT-002 errata`（3 files changed, +110 / −8） |
| 本报告 | 随第四个提交入库（docs only）；`git log --oneline -1` 即本报告的 sha，它不包含任何实现改动。 |

`F:\moonbit-hof-rs\DECISIONS.md` 按硬性约束**只读**，因此「为什么代码长这样」的记录落在本报告与
`docs/DESIGN-DETAIL.md §17`（以及 §10 的 `project_get_scene_exports` 语义说明）。

---

## 1. 逐工具表（契约、迁移源、落点、差异）

组信息（`docs/tool-groups.json`）：`channel=project`、`mutating=false`、`scope=both`、7 个工具，本组**无写操作**。
`description` 与 `inputSchema` 逐字取自 `docs/tools_list.renamed.json`（门① 逐字校验收口）。C++ 落点统一为
`tools/project_read_analysis.cpp`（注册在文件末 `register_project_read_analysis_tools`）。

| new_name | 迁移源 | 可观察契约（参数 / 返回形状 / 上限 / 大小写 / 错误） | C++ 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `project_get_statistics` | `analysis.rs:562` (`cmd_get_project_statistics`) | 入参 `path`（可选，默认 `res://`）、`include_addons`（可选，默认 false）。返回 `{file_counts_by_extension{}, total_files, total_script_lines, scene_count, resource_count, autoloads{}, plugins[]}`。递归：跳过 `.` 开头项（含 `..`、`.godot` 与隐藏文件）；`include_addons=false` 时不下钻 `addons`；扩展名**小写化**后计数；无点文件名只计入 `total_files`；`gd` 计入行数（Rust `lines()` 语义）、`tscn` 计场景、`tres/material/theme/stylebox/font` 计资源。`autoloads` 取 `autoload/` 前缀设置的**去前缀名→字符串值**；`plugins` 扫 `res://addons/*/plugin.cfg`（**恒扫 `res://addons`，与 `path` 无关**，同参照），`enabled` 由 `editor_plugins/enabled` 判定。错误：起始目录不存在 → `-32001`+`suggestion`；可选参数类型错 → `-32602`。 | `_collect_statistics_recursive` / `_collect_autoloads` / `_collect_plugins` / `_tool_get_project_statistics` | autoloads/plugins 由「GDScript Expression」改为直接读 `ProjectSettings` / `FileAccess`（同一数据源，无 Expression 依赖）；错误语义见 §8 D-3。 |
| `project_analyze_scene_complexity` | `analysis.rs:414` | 入参 `path`（可选，**缺省 → 分析当前编辑场景** = 编辑器专有分支）。返回 `{scene_path, total_nodes, max_depth, nodes_by_type{}, scripts_attached[{node,script}], issues[]}`。深度以根为 0（根 + 子 + 孙 → `max_depth=2`）；`scripts_attached.node` 用 `get_path_to`（根为 `"."`）；`issues` 阈值：节点 >1000 warning / >500 info（`else if`），深度 >15 warning / >10 info（`else if`）。错误：场景不存在 → `-32001`；存在但非 `PackedScene` → `-32603`；装载/实例化失败 → `-32603`。 | `_analyze_scene_node` / `_tool_analyze_scene_complexity` | ①编辑场景回退改用 `SceneTree::get_edited_scene_root()`（见 §3.2）；②`path` 为空的**游戏进程**返回 `-32000 Not implemented: ...` + `suggestion`（参照是 `no_scene` 语义，但游戏进程下「编辑场景」根本不存在，必须给明确错误）；③错误语义见 §8 D-3。 |
| `project_detect_circular_dependencies` | `analysis.rs:520` | 入参 `path`（可选 `res://`）、`include_addons`（可选 false）。返回 `{scenes_checked, circular_dependencies[[...]], has_circular, dependency_graph{}}`。只收 `.tscn`（扩展名小写化）；依赖由**原始文本**的 `[ext_resource ...]` 行（`trim()` 后）中含 `.tscn` 且 `path="....tscn"` 者构成；DFS 命中 `visiting` 节点即成环，环首节点在末尾**重复**（`[a,b,a]`）；空/不可读场景**不入图**但仍计入 `scenes_checked`。错误：起始目录不存在 → `-32001`。 | `_parse_scene_dependencies` / `_dfs_detect_cycle` / `_tool_detect_circular_dependencies` | DFS 起点顺序 = **目录扫描顺序**（可复现），参照是 Rust `HashMap` 迭代序（**不可复现**）。环集合相同，输出稳定；见 §3.3。 |
| `project_find_unused_resources` | `analysis.rs:336` | 入参 `path`（可选 `res://`）、`include_addons`（可选 false）。返回 `{unused_resources[], unused_count, total_resources_scanned, total_files_checked}`。资源扩展名 17 个（`tres tscn png jpg jpeg svg wav ogg mp3 ttf otf gdshader material theme stylebox font anim`）；引用文件扩展名 5 个（`tscn gd tres cfg godot`）；引用提取用**未 trim 的原始行**且只认行首 `[ext_resource`（与环检测的「先 trim」不同，刻意保留差异）；差集按收集顺序输出。错误：起始目录不存在 → `-32001`。 | `_resource_extensions` / `_reference_extensions` / `_tool_find_unused_resources` | 错误语义见 §8 D-3（参照在目录缺失时静默返回空）。 |
| `project_find_script_references` | `analysis.rs:485` | 入参 `query`（**必填**）、`path`（可选 `res://`）、`include_addons`（可选 false）。返回 `{query, references[{file,line,content}], reference_count, files_searched}`。**大小写敏感**的子串匹配、逐行内容 `trim()`、无上限；扫描 5 个扩展名（`tscn gd tres cfg godot`）。**与 `project_search_file_contents` 不同**：形状 `{file,line,content}` vs `{file,line,text}`、大小写敏感 vs 不敏感、多出 `files_searched`、扩展名白名单不同（不读 `md/txt/json`）。错误：缺 `query` → `-32602`；目录不存在 → `-32001`。 | `_tool_find_script_references` | 无差异（该工具是 GDR-17 去合并对的一方，语义差异被刻意保留并测试固定）。 |
| `project_get_scene_dependencies` | `batch.rs:519` | 入参 `path`（**必填**）。返回 `{path, dependencies[{path,type}], count}`。经 `ResourceLoader::get_dependencies`（与参照的 GDScript 绑定一致，`add_types=false`）读取；`::` 分割后取 `parts[0]` 为 `path`、`parts[2]`（通常不存在）为 `type`。错误：缺 `path` → `-32602`；文件不存在 → `-32001`。 | `_tool_get_scene_dependencies` | ①`path` 先规范化（`res://a/./b` → `res://a/b`），回显规范化后的路径（参照回显原始入参）；②`type` 字段**逐字保留参照的空值行为**（实测永为 `""`，见 §5 证据 19）；③错误语义见 §8 D-3。 |
| `project_get_scene_exports` | `scene.rs:344` | 入参 `path`（**必填**）。返回 `{path, nodes[{node_path,node_name,node_type,script_path,exports{name:{value,type,hint,hint_string}}}], count}`。只报 `count` 为「**有导出**的节点数」；`node_path` 根为 `"."`；值经 `serialize_variant` 同款序列化（`Vector2/3`、`Color`、`Rect2`、`NodePath`、`Dictionary/Array`、`Object`）。错误：缺 `path` → `-32602`；文件不存在 → `-32001`；装载/实例化失败或非场景 → `-32603`。 | `_serialize_variant` / `_collect_exports_recursive` / `_tool_get_scene_exports` | **导出判定重写**（参照恒返回空）：见 §3.1，这是本组最重要的一条实测偏离。 |

---

## 2. 红/绿证据（TDD）

**红阶段**（先写测试；此时 `tools/project_read_analysis.{h,cpp}` **尚不存在**，注册表里只有模板组 6 个工具）：

```
.\modules\mcp_server\tests\test_mcp_server.h(945):
TEST CASE:  [MCPServer] the shared registration entry point registers the group
.\modules\mcp_server\tests\test_mcp_server.h(949): ERROR: CHECK( registry.get_tool_count() == 13 ) is NOT correct!
.\modules\mcp_server\tests\test_mcp_server.h(952): ERROR: CHECK( registry.has_tool("project_get_statistics") ) is NOT correct!
...
.\modules\mcp_server\tests\test_mcp_server.h(1736): ERROR: CHECK( registry.get_tool_count() == 13 ) is NOT correct!
.\modules\mcp_server\tests\test_mcp_server.h(1750): ERROR: CHECK( registry.has_tool(names[i]) ) is NOT correct!     (×7 工具)
...
[doctest] test cases:  65 |  54 passed | 11 failed | 1429 skipped
[doctest] assertions: 536 | 467 passed | 69 failed
[doctest] Status: FAILURE!
```

11 个用例因「组/工具不存在」而红（正是期望的失败原因），而非编译或断言写法问题。构成：**新增 10 个用例中的 9 个**
＋**2 个既有用例**（`the shared registration entry point registers the group`、`tools of later batches are not registered`，
我把它们的期望数从 6 改成 13，红阶段自然读不到 13）。第 10 个新用例
（`the analysis tools never write to the project`）在红阶段**是绿的**——工具还不存在，文件列表当然不变，
这是它的**空真**语义，如实登记（它在绿阶段才真正开始约束行为）。基线（TASK-003 交付态）为 **55 例 / 450 断言**。
红阶段另暴露并修掉了两个**测试自身**的写法问题（真输出见提交前的构建日志）：
`ScratchProject` 的 out-of-line 定义无法编译（`tests/test_mcp_server.cpp` 故意不包含该头），改为头内 `inline`；
`CHECK(forward || backward)` 触发 doctest 的 `Expression Too Complex`，改为先算 bool。

**绿阶段**（实现 + 注册后）：

```
[doctest] test cases:  65 |  65 passed | 0 failed | 1429 skipped
[doctest] assertions: 607 | 607 passed | 0 failed |
[doctest] Status: SUCCESS!
EXIT_CODE=0
```

新增 10 个用例（55→65）、+157 断言（450→607）：

| 用例 | 固定的行为 |
|---|---|
| `the project_read_analysis group is registered for both processes` | 13 个工具，编辑器/游戏两个视角同可见 |
| `project_get_statistics counts files, scripts, scenes and resources` | fixture 上**精确**计数（9/4/2/8 行、`gd2 tscn4 tres2 md1`）、`include_addons=true` 后 11/3/`cfg1`、缺目录 `-32001`、可选参数类型错 `-32602` |
| `project_analyze_scene_complexity analyses a .tscn from disk` | `total_nodes=3 / max_depth=2 / nodes_by_type`、缺文件 `-32001`、非场景资源 `-32603` |
| `the scene complexity fallback distinguishes editor and game process` | 游戏进程 → `-32000 Not implemented...`；编辑器进程（doctest 无 SceneTree）→ `-32000 No scene is currently open`：**两条分支产生不同消息**，证明守卫真的换了分支且不崩 |
| `project_detect_circular_dependencies reports the scene cycle` | `scenes_checked=4`、恰好 1 个环、环首尾相同、`dependency_graph` 4 键、无依赖场景为空数组 |
| `project_find_unused_resources separates used from unused` | `total_resources_scanned=6`、`total_files_checked=8`、unused **恰好** 3 个（含 `unused.tres`，不含 `used.tres`/`cycle_b.tscn`/`refs.gd`） |
| `project_find_script_references is not the content search (GDR-17)` | 同一 pattern：本工具 `files_searched=8 / count=2`（`{file,line,content}`，**无** `text` 键）；`project_search_file_contents` `count=3`（含 `notes.md`，`{file,line,text}`）：形状与命中集都不同 |
| `project_get_scene_dependencies reads the ext_resource list` | `leaf.tscn → used.tres`（`type==""` 的保留行为）、无依赖场景 `count=0`；缺参 `-32602`、缺文件 `-32001` |
| `project_get_scene_exports reports the scripted nodes of a scene` | 无脚本场景 `count=0` 的形状；非场景资源 `-32603`；缺参 `-32602`；缺文件 `-32001` |
| `the analysis tools never write to the project` | 依次调用 7 个工具后，fixture 文件列表**逐字节不变**（只读不变式） |

**doctest 的已知环境限制（如实登记）**：`Main::test_setup()` **不调用** `ScriptServer::init_languages()`，
所以 `--test` 进程里 GDScript 语言未初始化，任何 `.gd` 装载都会失败：

```
SCRIPT ERROR: Compile Error: GDScript bug (please report): Native class "Node2D" not found.
   at: GDScript::reload (res://mcp_server_test_fixture/scripts/exported.gd:0)
```

因此 fixture 的场景**刻意不带脚本**，`scripts_attached`/`exports` 的**正例**不在 doctest 里假装通过，
而由门② 的真实工程证据（§5 证据 05/22）承载；doctest 只固定与脚本无关的形状、错误类与边界。这是**主动选择**：
若写成「脚本加载成功才断言、否则跳过」，就会得到假通过。

---

## 3. 三条关键实现决策（含实测证据）

### 3.1 `project_get_scene_exports` 的导出判定（**参照实现在本 fork 恒返回空**）

参照用字面量 `PROPERTY_USAGE_SCRIPT_VARIABLE: i64 = 1024`，而本 fork（Godot 4.7）的
`core/object/property_info.h:102` 是 `PROPERTY_USAGE_SCRIPT_VARIABLE = 1 << 12`（**4096**）；`1 << 10`（**1024**）是
`PROPERTY_USAGE_NO_INSTANCE_STATE`。也就是说参照的过滤条件在 4.7 上**不可能命中任何导出变量**（真值见下）。

进一步，实测发现「节点合并属性列表」在两个进程里**语义不一致**。用探针（`--script` 跑在工程副本上，与
编辑器进程 9888 的 curl 调用对照）测得：

| 观察对象 | 编辑器进程（9888，`-e`） | 游戏进程（9889） |
|---|---|---|
| `node.get_property_list()` 里 `speed` | `usage=6`（STORAGE\|EDITOR，**无** SCRIPT_VARIABLE） | `usage=4102` |
| `node.get_property_list()` 里 `not_exported` | **根本不在列表里** | `usage=4096` |
| `script.get_script_property_list()` 里 `speed` | `usage=4102` | `usage=4102` |
| `script.get_script_property_list()` 里 `not_exported` | `usage=4096` | `usage=4096` |

（编辑器侧实测行：`[MCPServer-dbg] Node2D script_valid=true props=60` / `node prop speed usage=6` /
`script prop speed usage=4102` / `script prop not_exported usage=4096`。探针代码在定稿前已删除。）

**定稿实现**：遍历 `Script::get_script_property_list()`（脚本自己的成员表），用
`PROPERTY_USAGE_EDITOR` 作为「导出」判据；值经 `node->get(name)` 读取（保留 `.tscn` 覆盖）。
两条进程路径的结论因此一致，且 `not_exported` 被正确排除。证据见 §5 证据 22（编辑器）与 §5.2 证据 22（游戏），
同一场景两个进程返回**完全相同**的 `nodes`。参照带 1024 的实现只会返回 `count: 0`。

### 3.2 编辑场景回退：用 `SceneTree::get_edited_scene_root()`

`EditorInterface::get_edited_scene_root()` 的实现是 `EditorNode::get_singleton()->get_edited_scene()`
（`editor/editor_interface.cpp:745-746`），**没有 null 检查**；而 doctest 进程的 `Main::test_setup()` 会调用
`register_editor_types()`（于是 `EditorInterface::singleton` **存在**）却**从不启动 `EditorNode`**。
最初的实现在该进程里被守卫放行后 **SIGSEGV**（真实崩溃，`the scene complexity fallback distinguishes editor
and game process` → `FATAL ERROR: test case CRASHED: SIGSEGV`）。

定稿改为 `SceneTree::get_edited_scene_root()`——编辑器始终把当前编辑场景同步到该镜像
（`EditorNode::set_edited_scene_root` → `editor_node.cpp:4698`；切标签页 → `_set_current_scene_nocheck` → `:4837`），
语义与 `EditorInterface` 版本一致，且在 `SceneTree` 不存在时安全返回 null → `no_scene()`。
编辑器专有性仍由 `MCP_EDITOR_TOOLS_ENABLED` + `is_editor_process()` 双层守卫（游戏构建里该分支连编译产物都没有）。

### 3.3 环检测的起点顺序可复现

参照用 `HashMap<String, Vec<String>>` 遍历构图与选起点，Rust `HashMap` 的迭代序**不保证稳定**，
环的**起点**（`[a,b,a]` 还是 `[b,a,b]`）因此随实现/进程变化。定稿用目录扫描顺序作起点顺序，
对同一棵树**逐字节可复现**（与 DESIGN-DETAIL §17.4 的确定性精神一致），环集合不变。

---

## 4. 门（真实输出 + 退出码）

构建命令（统一，**必须 pwsh/cmd，不能用 Git Bash**：`MSYSTEM` 会让 SCons 去 `bin/build_deps` 找依赖并失败）：

```
D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8
```

### 4.1 门① 契约子集逐字（`scripts\check_contract_subset.ps1 -Group project_read_analysis`）→ **EXIT=0**

```
group       : project_read_analysis
tools       : project_get_statistics, project_analyze_scene_complexity, project_detect_circular_dependencies, project_find_unused_resources, project_find_script_references, project_get_scene_dependencies, project_get_scene_exports
implemented : 13 tool(s) across the groups marked implemented: project_get_info, ..., project_get_scene_exports
contract    : 171 entries

user editor on 9877 before run: pid=36392
[PASS] editor_9888_contract_subset
       editor port=9888 tools=13 order=project_get_info > ... > project_get_scene_exports | project_get_statistics: name=True description=True inputSchema=True | project_analyze_scene_complexity: name=True description=True inputSchema=True | project_detect_circular_dependencies: name=True description=True inputSchema=True | project_find_unused_resources: name=True description=True inputSchema=True | project_find_script_references: name=True description=True inputSchema=True | project_get_scene_dependencies: name=True description=True inputSchema=True | project_get_scene_exports: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset
       （同上，game port=9889 tools=13，7 条 name/description/inputSchema 全 True）
[PASS] guard_user_port_9877
       pid_before=36392 pid_after=36392
group=project_read_analysis tools=7 contract=171
implemented_union=13 tools
3/3 checks passed
```

**注意（并已修正）**：本组落地后该脚本**第一次运行是 FAIL**（`tool count actual=13 expected=7` +
`unexpected extra tool(s): project_get_info, ...`×6）——它原先假设「只有一个已实现组」。这是脚本的
真实缺陷，处理见 §7.1。**回归对照**：`-Group project_read_template` 同样 `3/3 checks passed`、EXIT=0，
证明修正没有把门改松（见 §7.1 的强度论证）。

### 4.2 门② 三类证据 → 见 §5（编辑器 24 例 + 游戏进程 24 例，全部为原样粘贴的真实请求/响应）

### 4.3 门③ 模块 doctest（`--headless --test --test-case="[MCPServer]*"`）→ **EXIT_CODE=0**

```
[doctest] test cases:  65 |  65 passed | 0 failed | 1429 skipped
[doctest] assertions: 607 | 607 passed | 0 failed |
[doctest] Status: SUCCESS!
```

基线 55 例 / 450 断言（REPORT-003 §门1）→ **只增不减**。

### 4.4 门④ 全引擎回归（`--headless --test`）→ **EXIT_CODE=0**

```
[doctest] test cases:   1491 |   1491 passed | 0 failed | 3 skipped
[doctest] assertions: 424888 | 424888 passed | 0 failed |
[doctest] Status: SUCCESS!
```

基线 1481 例 / 424731 断言（REPORT-003 §门2）→ +10 例 / +157 断言，**0 failed**。

### 4.5 门⑤ `scripts\accept_m1.ps1` **连跑两次** → **A_EXIT=0 / B_EXIT=0**

两次均 **22/22 cases passed**，PASS 清单**逐条一致**：

```
PASS case1_GET_mcp_200 | case2_initialize | case3_tools_list_fixture | case4_tools_call_project_info
PASS case5_tools_call_invalid_params | case6_unknown_method | case7_parse_error | case8_concurrent_100
PASS case9_keep_alive_two_requests | case10_half_packet | case11_body_too_large | case15_connection_reaping
PASS case16_expect_100_continue | case17_header_too_large_431 | case18_bare_lf_terminator_400
PASS case19_invalid_utf8_body_warns | case20_tools_list_cross_process_restart | case12_game_process_endpoint
PASS case13_game_without_port | case14_port_occupied | guard_user_port_9877 | gate_scope_declared
22/22 cases passed
implemented tools = 13; contract = 171; known_deviation = per-batch verbatim gate only
```

新增的跨进程一致性检查（TASK-004 §3.1，`case20`）两次的真实证据：

```
run A: pid_first=28304 pid_second=51664 tools=13 bytes=4230/4230 byte_identical=True
       sha256_first=94ea99785b475c16d5e68683b40ff8baeefd42b10787e2ddff829bb0641219d3
       sha256_second=94ea99785b475c16d5e68683b40ff8baeefd42b10787e2ddff829bb0641219d3
run B: pid_first=1404  pid_second=39988 tools=13 bytes=4230/4230 byte_identical=True
       sha256_first=94ea99785b475c16d5e68683b40ff8baeefd42b10787e2ddff829bb0641219d3
       sha256_second=94ea99785b475c16d5e68683b40ff8baeefd42b10787e2ddff829bb0641219d3
```

两次的 `tools/list` 响应体 sha256 **跨四次独立进程完全相同**（`94ea9978…`），且**逐字节相等**（长度 + 每字节比较）。
`guard_user_port_9877` 两次均为 `listening=True pid_before=36392 pid_after=36392`。

---

## 5. 门② 三类证据（真实请求与响应）

### 5.1 证据工程（可复现）

`%TEMP%\godot-mcp-evidence-004\proj`（**不在仓库内**）：

```
project.godot            [application] name/version + [autoload] EvidenceAutoload="*res://scripts/autoload.gd"
                         （游戏侧证据运行时另加 run/main_scene="res://scenes/hero.tscn"）
scripts/autoload.gd      3 行；scripts/exported.gd 6 行（speed/title/tint 三个 @export + 一个普通 var）
scripts/helper.gd        3 行，第 3 行含 EVIDENCE_MARKER
scenes/hero.tscn         root 挂 exported.gd（speed=7 覆盖默认值）+ 2 层子节点；ext_resource→used.tres
scenes/a.tscn ⇄ b.tscn   互相 ext_resource（人为环）
resources/used.tres      被 hero.tscn 引用；resources/unused.tres 无人引用
notes.md                 第 3 行含 EVIDENCE_MARKER（只有 project_search_file_contents 会读）
addons/myplugin/plugin.cfg
```

驱动：每个请求体先写文件，再
`curl.exe -s -X POST -H "Content-Type: application/json" --data-binary @<file> http://127.0.0.1:<port>/mcp`
（驱动脚本本身是 `%TEMP%` 下的一次性工具，**刻意不入库**；§5.2 的 BODY/RESP 已逐条原样粘贴，足以原样重放）。
引擎启动：`bin\godot.windows.editor.x86_64.console.exe --headless --verbose -e --path <proj> --mcp-port=9888`
（游戏侧去掉 `-e`，用 9889）。**全程未占用 9877**。

### 5.2 编辑器进程 9888（原样粘贴；`id` 即用例号）

```
### 01 project_get_statistics — 成功
BODY {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_get_statistics","arguments":{"path":"res://"}}}
RESP {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"autoloads\":{\"EvidenceAutoload\":\"*res://scripts/autoload.gd\"},\"file_counts_by_extension\":{\"gd\":3,\"godot\":1,\"md\":1,\"tres\":2,\"tscn\":3,\"uid\":3},\"plugins\":[{\"enabled\":false,\"name\":\"myplugin\"}],\"resource_count\":2,\"scene_count\":3,\"total_files\":13,\"total_script_lines\":12}","type":"text"}]}}

### 02 project_get_statistics — 成功（include_addons=true）
BODY {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"project_get_statistics","arguments":{"path":"res://","include_addons":true}}}
RESP {"id":2,"jsonrpc":"2.0","result":{"content":[{"text":"{\"autoloads\":{\"EvidenceAutoload\":\"*res://scripts/autoload.gd\"},\"file_counts_by_extension\":{\"cfg\":1,\"gd\":3,\"godot\":1,\"md\":1,\"tres\":2,\"tscn\":3,\"uid\":3},\"plugins\":[{\"enabled\":false,\"name\":\"myplugin\"}],\"resource_count\":2,\"scene_count\":3,\"total_files\":14,\"total_script_lines\":12}","type":"text"}]}}

### 03 project_get_statistics — 缺参类（无可选必填 → 用「可选参数类型错」替代）
BODY {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"project_get_statistics","arguments":{"include_addons":"yes"}}}
RESP {"error":{"code":-32602,"message":"Parameter 'include_addons' must be a boolean, got String"},"id":3,"jsonrpc":"2.0"}

### 04 project_get_statistics — 底层失败
BODY {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"project_get_statistics","arguments":{"path":"res://no_such_dir"}}}
RESP {"error":{"code":-32001,"data":{"suggestion":"Call the tool without 'path' (or with 'res://') to address the project root"},"message":"Directory 'res://no_such_dir' not found"},"id":4,"jsonrpc":"2.0"}

### 05 project_analyze_scene_complexity — 成功（磁盘场景 + 脚本）
BODY {"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"project_analyze_scene_complexity","arguments":{"path":"res://scenes/hero.tscn"}}}
RESP {"id":5,"jsonrpc":"2.0","result":{"content":[{"text":"{\"issues\":[],\"max_depth\":2,\"nodes_by_type\":{\"Node2D\":2,\"Sprite2D\":1},\"scene_path\":\"res://scenes/hero.tscn\",\"scripts_attached\":[{\"node\":\".\",\"script\":\"res://scripts/exported.gd\"}],\"total_nodes\":3}","type":"text"}]}}

### 06 project_analyze_scene_complexity — path 缺省（编辑器回退，headless 编辑器无打开场景）
BODY {"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"project_analyze_scene_complexity","arguments":{}}}
RESP {"error":{"code":-32000,"data":{"suggestion":"Use editor_open_scene to open a scene first"},"message":"No scene is currently open"},"id":6,"jsonrpc":"2.0"}

### 07 project_analyze_scene_complexity — 缺参类（path 可选 → 类型错替代）
BODY {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"project_analyze_scene_complexity","arguments":{"path":7}}}
RESP {"error":{"code":-32602,"message":"Parameter 'path' must be a string, got float"},"id":7,"jsonrpc":"2.0"}

### 08 project_analyze_scene_complexity — 底层失败
BODY {"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"project_analyze_scene_complexity","arguments":{"path":"res://scenes/missing.tscn"}}}
RESP {"error":{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the .tscn files of the project"},"message":"Scene 'res://scenes/missing.tscn' not found"},"id":8,"jsonrpc":"2.0"}

### 09 project_detect_circular_dependencies — 成功（a ⇄ b 环）
BODY {"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"project_detect_circular_dependencies","arguments":{"path":"res://"}}}
RESP {"id":9,"jsonrpc":"2.0","result":{"content":[{"text":"{\"circular_dependencies\":[[\"res://scenes/a.tscn\",\"res://scenes/b.tscn\",\"res://scenes/a.tscn\"]],\"dependency_graph\":{\"res://scenes/a.tscn\":[\"res://scenes/b.tscn\"],\"res://scenes/b.tscn\":[\"res://scenes/a.tscn\"],\"res://scenes/hero.tscn\":[]},\"has_circular\":true,\"scenes_checked\":3}","type":"text"}]}}

### 10 project_detect_circular_dependencies — 缺参类（类型错替代）
BODY {"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"project_detect_circular_dependencies","arguments":{"include_addons":5}}}
RESP {"error":{"code":-32602,"message":"Parameter 'include_addons' must be a boolean, got float"},"id":10,"jsonrpc":"2.0"}

### 11 project_detect_circular_dependencies — 底层失败
BODY {"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"project_detect_circular_dependencies","arguments":{"path":"res://no_such_dir"}}}
RESP {"error":{"code":-32001,"data":{"suggestion":"Call the tool without 'path' (or with 'res://') to address the project root"},"message":"Directory 'res://no_such_dir' not found"},"id":11,"jsonrpc":"2.0"}

### 12 project_find_unused_resources — 成功
BODY {"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"project_find_unused_resources","arguments":{"path":"res://"}}}
RESP {"id":12,"jsonrpc":"2.0","result":{"content":[{"text":"{\"total_files_checked\":9,\"total_resources_scanned\":5,\"unused_count\":2,\"unused_resources\":[\"res://resources/unused.tres\",\"res://scenes/hero.tscn\"]}","type":"text"}]}}

### 13 project_find_unused_resources — 缺参类（类型错替代）
BODY {"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"project_find_unused_resources","arguments":{"path":12}}}
RESP {"error":{"code":-32602,"message":"Parameter 'path' must be a string, got float"},"id":13,"jsonrpc":"2.0"}

### 14 project_find_unused_resources — 底层失败
BODY {"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"project_find_unused_resources","arguments":{"path":"res://no_such_dir"}}}
RESP {"error":{"code":-32001,"data":{"suggestion":"Call the tool without 'path' (or with 'res://') to address the project root"},"message":"Directory 'res://no_such_dir' not found"},"id":14,"jsonrpc":"2.0"}

### 15 project_find_script_references — 成功
BODY {"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"project_find_script_references","arguments":{"query":"EVIDENCE_MARKER","path":"res://"}}}
RESP {"id":15,"jsonrpc":"2.0","result":{"content":[{"text":"{\"files_searched\":9,\"query\":\"EVIDENCE_MARKER\",\"reference_count\":2,\"references\":[{\"content\":\"# EVIDENCE_MARKER\",\"file\":\"res://scenes/a.tscn\",\"line\":7},{\"content\":\"const TARGET := \\\"EVIDENCE_MARKER\\\"\",\"file\":\"res://scripts/helper.gd\",\"line\":3}]}","type":"text"}]}}

### 16 project_find_script_references — 缺参（真·必填）
BODY {"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"project_find_script_references","arguments":{}}}
RESP {"error":{"code":-32602,"message":"Missing required parameter: query"},"id":16,"jsonrpc":"2.0"}

### 17 project_find_script_references — 底层失败
BODY {"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"project_find_script_references","arguments":{"query":"x","path":"res://no_such_dir"}}}
RESP {"error":{"code":-32001,"data":{"suggestion":"Call the tool without 'path' (or with 'res://') to address the project root"},"message":"Directory 'res://no_such_dir' not found"},"id":17,"jsonrpc":"2.0"}

### 18 对照：project_search_file_contents 同一 pattern（证明两者不同，GDR-17）
BODY {"jsonrpc":"2.0","id":18,"method":"tools/call","params":{"name":"project_search_file_contents","arguments":{"pattern":"EVIDENCE_MARKER","path":"res://"}}}
RESP {"id":18,"jsonrpc":"2.0","result":{"content":[{"text":"{\"count\":3,\"matches\":[{\"file\":\"res://notes.md\",\"line\":3,\"text\":\"EVIDENCE_MARKER\"},{\"file\":\"res://scenes/a.tscn\",\"line\":7,\"text\":\"# EVIDENCE_MARKER\"},{\"file\":\"res://scripts/helper.gd\",\"line\":3,\"text\":\"const TARGET := \\\"EVIDENCE_MARKER\\\"\"}],\"query\":\"EVIDENCE_MARKER\"}","type":"text"}]}}
```

同一 pattern：`project_find_script_references` = **2 命中 / 9 文件已搜**、逐行 `{file,line,content}`；
`project_search_file_contents` = **3 命中**（多出 `notes.md`）、`{file,line,text}` 且无 `files_searched`。
**两个工具在真实工程上不可互换**（正是 TASK-004 §2.3 要求）。

```
### 19 project_get_scene_dependencies — 成功
BODY {"jsonrpc":"2.0","id":19,"method":"tools/call","params":{"name":"project_get_scene_dependencies","arguments":{"path":"res://scenes/hero.tscn"}}}
RESP {"id":19,"jsonrpc":"2.0","result":{"content":[{"text":"{\"count\":2,\"dependencies\":[{\"path\":\"res://scripts/exported.gd\",\"type\":\"\"},{\"path\":\"res://resources/used.tres\",\"type\":\"\"}],\"path\":\"res://scenes/hero.tscn\"}","type":"text"}]}}

### 20 project_get_scene_dependencies — 缺参（真·必填）
BODY {"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"project_get_scene_dependencies","arguments":{}}}
RESP {"error":{"code":-32602,"message":"Missing required parameter: path"},"id":20,"jsonrpc":"2.0"}

### 21 project_get_scene_dependencies — 底层失败
BODY {"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"project_get_scene_dependencies","arguments":{"path":"res://scenes/missing.tscn"}}}
RESP {"error":{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the files of the project"},"message":"File 'res://scenes/missing.tscn' not found"},"id":21,"jsonrpc":"2.0"}

### 22 project_get_scene_exports — 成功（speed 被场景覆盖为 7；tint 走 serialize_variant；not_exported 不在）
BODY {"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"project_get_scene_exports","arguments":{"path":"res://scenes/hero.tscn"}}}
RESP {"id":22,"jsonrpc":"2.0","result":{"content":[{"text":"{\"count\":1,\"nodes\":[{\"exports\":{\"speed\":{\"hint\":0,\"hint_string\":\"\",\"type\":2,\"value\":7},\"tint\":{\"hint\":0,\"hint_string\":\"\",\"type\":20,\"value\":{\"a\":1.0,\"b\":0.0,\"g\":0.0,\"r\":1.0}},\"title\":{\"hint\":0,\"hint_string\":\"\",\"type\":4,\"value\":\"hello\"}},\"node_name\":\"Hero\",\"node_path\":\".\",\"node_type\":\"Node2D\",\"script_path\":\"res://scripts/exported.gd\"}],\"path\":\"res://scenes/hero.tscn\"}","type":"text"}]}}

### 23 project_get_scene_exports — 缺参（真·必填）
BODY {"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"project_get_scene_exports","arguments":{}}}
RESP {"error":{"code":-32602,"message":"Missing required parameter: path"},"id":23,"jsonrpc":"2.0"}

### 24 project_get_scene_exports — 底层失败
BODY {"jsonrpc":"2.0","id":24,"method":"tools/call","params":{"name":"project_get_scene_exports","arguments":{"path":"res://scenes/missing.tscn"}}}
RESP {"error":{"code":-32001,"data":{"suggestion":"Use project_get_filesystem_tree to list the .tscn files of the project"},"message":"Scene file 'res://scenes/missing.tscn' not found"},"id":24,"jsonrpc":"2.0"}
```

> 关于 `.uid`：`project.godot` 里 `[application]` 的 `file_counts_by_extension` 出现 `uid:3`，是 4.7 编辑器为
> `.gd` 生成的 `*.gd.uid`（`--import` 的产物）。工具按参照语义**照实计数**（它们是普通文件），此处如实登记。

### 5.3 游戏进程 9889（同工程、`run/main_scene` 已设置；证明 `scope=both` 与进程无关性）

24 例与 9888 一一对应，退出码/形状一致；**关键两例**（其余同为原样粘贴，`%TEMP%\godot-mcp-evidence-004\resp\game-*.json`）：

```
### [game] 06 — path 缺省：游戏进程下「编辑场景」不存在 → 明确的 -32000
BODY {"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"project_analyze_scene_complexity","arguments":{}}}
RESP {"error":{"code":-32000,"data":{"suggestion":"Pass 'path' with a res:// .tscn file to analyse a scene from disk"},"message":"Not implemented: analysis of the edited scene in a game process"},"id":6,"jsonrpc":"2.0"}

### [game] 22 — 与编辑器进程逐字段相同的导出结果（证明 §3.1 的过滤与进程无关）
BODY {"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"project_get_scene_exports","arguments":{"path":"res://scenes/hero.tscn"}}}
RESP {"id":22,"jsonrpc":"2.0","result":{"content":[{"text":"{\"count\":1,\"nodes\":[{\"exports\":{\"speed\":{\"hint\":0,\"hint_string\":\"\",\"type\":2,\"value\":7},\"tint\":{\"hint\":0,\"hint_string\":\"\",\"type\":20,\"value\":{\"a\":1.0,\"b\":0.0,\"g\":0.0,\"r\":1.0}},\"title\":{\"hint\":0,\"hint_string\":\"\",\"type\":4,\"value\":\"hello\"}},\"node_name\":\"Hero\",\"node_path\":\".\",\"node_type\":\"Node2D\",\"script_path\":\"res://scripts/exported.gd\"}],\"path\":\"res://scenes/hero.tscn\"}","type":"text"}]}}
```

游戏进程状态探针：`{"connections":1,"frame_count":62,"is_editor":false,"listening":true,"port":9889,"server":"godot-mcp-rs","status":"ok","tools":13,...}`。

### 5.4 **不可构造类**的逐工具声明

| 工具 | 成功 | 缺参 | 底层失败 | 声明 |
|---|---|---|---|---|
| `project_get_statistics` | ✅ 01/02 | ⚠️ 03（类型错替代） | ✅ 04 | 契约 `required: []`，**不存在缺参**；以「可选参数出现但类型错 → `-32602`」作替代证据（PLAYBOOK §6.2 的既有裁决） |
| `project_analyze_scene_complexity` | ✅ 05 | ⚠️ 07（类型错替代） | ✅ 08 | 同上（`path` 可选）。另有 06：**编辑器回退成功类不可构造**——headless 编辑器没有打开的场景，只能得到 `-32000`；该分支的「有场景」路径由 doctest 的分支判别用例 + 代码守卫覆盖，如实登记 |
| `project_detect_circular_dependencies` | ✅ 09 | ⚠️ 10（类型错替代） | ✅ 11 | 契约 `required: []` |
| `project_find_unused_resources` | ✅ 12 | ⚠️ 13（类型错替代） | ✅ 14 | 契约 `required: []` |
| `project_find_script_references` | ✅ 15 | ✅ 16（真必填） | ✅ 17 | 三类全可达 |
| `project_get_scene_dependencies` | ✅ 19 | ✅ 20（真必填） | ✅ 21 | 三类全可达 |
| `project_get_scene_exports` | ✅ 22 | ✅ 23（真必填） | ✅ 24 | 三类全可达；另有「资源存在但不是场景 → `-32603`」由 doctest 覆盖 |

---

## 6. 文件指纹（sha256 + 字节数）

| 文件 | bytes | sha256 |
|---|---|---|
| `tools/project_read_analysis.h`（新） | 3489 | `ea3c90b9bfae22e7366aecde21d56cec0d837c04f527440a956b63bedba3bdce` |
| `tools/project_read_analysis.cpp`（新） | 43695 | `31d5c08391837180f48f079f97fc26cb82f5303e2141d7827d1e68e40fbafd21` |
| `tools/registration.cpp` | 2666 | `ecce22d927932fc2c5f7d6d0a6711f64f9ae99b03c4dd2ac969117236ad7b77b` |
| `tests/test_mcp_server.h` | 101155 | `50d4149ed8561876a886075d0d2e65f39360e1835f6fb2a96c1d376100b3f7c4` |
| `tests/test_mcp_server.cpp` | 7242 | `4cb8fca3618bf23d64e8dd8d38efe1fb5227ee274954a8216442f324b8b0f9d9` |
| `scripts/check_contract_subset.ps1` | 20103 | `121a0e6753db7b489b88cac18dbc8c15b0c27533beb427e946924928fe57e16e` |
| `scripts/accept_m1.ps1` | 55944 | `c06b692dea90658075ffc22ab588c86aaab8427d6f79b28c805e1ccf2df2bbd6` |
| `docs/tool-groups.json` | 5442 | `3ea451c28e9bcb62a47de6a79446317f027300146a8507ee00b5bdf140f41141` |
| `docs/reports/REPORT-002-b1-framework.md` | 38594 | `7bd9c22f89aa3a208c003f2e92a6dbce195048983276e588c320129de4cd3f64` |
| `docs/tools_list.renamed.json`（**未改**） | 98953 | `64723fb9fbe8247512171ee4ae8b6950486bad3722cb957091414b73ecf573f5`（= REPORT-003 记录值） |
| `docs/tool-rename-map.json`（**未改**） | 70917 | `2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd`（= REPORT-002 记录值） |

`docs/tool-groups.json` 只动了 1 个字节级变更：`project_read_analysis.implemented` `false → true`
（5443 → 5442 bytes）。`docs/scripts/check_tool_groups.py` 自跑 **PASS**（41 个工具恰好各一次、
通道/读写属性与映射表一致、名称都在 171 条契约里），其打印的新 `BYTES 5442 / SHA256 3ea451c2…` 与上表一致。

**改动集边界**（`git status --short`）：只有 `modules/mcp_server/**` 下的 7 个 M + 2 个 ??；
另有 4 个**在我开工前就存在**的未跟踪物：`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`
（我未触碰、未纳入任何提交）。契约、映射、生成器、`godot_mcp_gdext`、hof-rs 均未改。

---

## 7. 顺带修掉的两项（任务书 §3）+ 一项必需的门脚本修正

### 7.1 `scripts\accept_m1.ps1`：跨进程重启一致性（TASK-004 §3.1）

新增 `case20_tools_list_cross_process_restart`：抓第一次 `tools/list` 响应体 → **停掉该编辑器进程** →
在同一端口/工程上**另起一个独立进程** → 再抓一次 → **逐字节比较**（长度 + 每字节循环）并打印两个 sha256。
原先的确定性用例只覆盖「同一进程内连续两次」（DESIGN-DETAIL §17.4），
「启动序依赖注册表哈希种子」这类缺陷原本会漏过。§4.5 的两次真实输出显示
`byte_identical=True` 且 sha256 跨四个进程恒为 `94ea9978…`。同时把 `$ToolNames` 从 6 扩到 13。

### 7.2 `docs/reports/REPORT-002-b1-framework.md`：§10 追加勘误 2（append-only）

在 §10（勘误段）**追加**一段，指出该报告 `:194` 的注释「只允许 `res://`、禁 `..` 与空段」已过期：
现行权威是 `docs/DESIGN-DETAIL.md` **§17.2**——`..` 在折叠**之前**拒绝，而 `.` 段与空/仅空白段是**被折叠掉**的
（TASK-003 裁决 D-4）。**原文一字未改**，只追加。

### 7.3 `scripts\check_contract_subset.ps1`：多组并存时的「无多余工具」（**门① 首次运行 FAIL 暴露**）

本组落地后，该脚本首次运行 **FAIL**（真实输出见 §4.1 注）：它把「live `tools/list` 必须等于本组工具集」
当成硬条件，于是 13 个工具里另外 6 个被报成 `unexpected extra tool(s)`。这是脚本的真实缺陷，不是实现缺陷
——PLAYBOOK §3 门① 的原意是「**本组**的名称/描述/schema 逐字一致、且没有本组该有却没有的条目」，
在单组时代恰好等价于「live 集合 = 本组集合」。

**修正（不放松强度）**：期望总数与「多余工具」集合改为对照 `docs/tool-groups.json` 中
`implemented: true` 的所有组的**并集**，并新增「已实现工具必须全部在场」的校验。于是：
① 已实现工具少一个 → FAIL（旧脚本在跨组场景下反而会误判）；
② 出现任何不属于已实现组的工具（例如未实现却偷偷注册，GDR-7）→ FAIL；
③ 本组 7 个工具的 `name/description/inputSchema` 仍与契约逐字比较（未变）。
**回归对照**：`-Group project_read_template` 同样 `3/3 checks passed`、EXIT=0。
后续每个组落地都会遇到同一问题，故这条修正对后续组是必需的。

---

## 8. deviations（与手册/任务书的偏离，逐条显式）

1. **`project_get_scene_exports` 的导出判定重写**（§3.1）。参照的字面量 1024 在本 fork 是
   `PROPERTY_USAGE_NO_INSTANCE_STATE`，其实现**恒返回 `count:0`**；且编辑器进程的节点合并属性列表
   不带 `SCRIPT_VARIABLE`。定稿读 `Script::get_script_property_list()` 并以 `PROPERTY_USAGE_EDITOR` 判定。
   这是**有意的行为差异**（否则该工具永远无输出），已用两个进程的真实响应固定（§5 证据 22）。
2. **编辑场景回退用 `SceneTree::get_edited_scene_root()`**（§3.2）。语义等价（编辑器持续同步该镜像），
   但避开了 `EditorInterface::get_edited_scene_root()` 对 `EditorNode` 的无保护解引用（实测 SIGSEGV）。
   编辑器专有性仍由 `MCP_EDITOR_TOOLS_ENABLED` + `is_editor_process()` 守卫。
3. **`-32001` 强语义**（沿用 PLAYBOOK §6.1 的既有裁决）：起始目录/文件不存在时参照**静默返回空结果**，
   本实现返回 `-32001` + `data.suggestion`（GDR-14）。影响面：统计/环检测/未用资源/脚本引用/场景依赖/场景导出。
4. **`optional_*` 出现即必须类型正确**（沿用 PLAYBOOK §6.2）：类型错 → `-32602`；参照静默忽略。
5. **`normalize_project_path` 的规范化**（沿用 PLAYBOOK §6.3）：本组所有 `path` 入参都先经它折叠；
   `res://a/./b` 与 `res://a//b` 被规范化为 `res://a/b`，`project_get_scene_dependencies`/`_exports` 的
   **回显**因此是规范路径（参照回显原始入参）。
6. **错误消息语言**：模块风格为英文（`File 'x' not found`），参照是中文（`场景文件 'x'`）。
   仅消息文本不同，`code`/`data` 语义一致；与模板组的既有风格保持一致。
7. **环检测起点顺序**（§3.3）：目录扫描顺序替代 Rust `HashMap` 迭代序（后者不可复现）。
8. **`project_get_scene_dependencies` 的 `type` 恒为空串**：这是参照的真实行为（`parts[2]`），
   **逐字保留**而非「顺手修好」（若改成 `parts[1]` 会构成未声明的行为变更）。已写进代码注释与 §1 表格。
9. **少量助手函数在本组文件内重复实现**（`_split_lines`、`_serialize_variant`、`_join_path`、扩展名递归收集）：
   PLAYBOOK §5/§17.1 明确「不得改别组文件」，而 `tools/project_read_template.cpp` 的同名助手是 `static`（内部链接）。
   这些副本都很小且各有测试固定；把它们上提到 `tools/tool_builder.h` 属于**框架清理**，建议留给后续任务
   （本组不擅自扩大改动面）。
10. **`docs/tool-groups.json` 的 `implemented` 标记**（false→true）：任务书正文未点名此文件，但门① 的
    修正需要它作为「已实现集合」的唯一事实源；不写它就只能靠硬编码，反而更差。
11. **`scripts/check_contract_subset.ps1` 的修正**（§7.3）：任务书只点名了 `accept_m1.ps1` 与 REPORT-002，
    但不修它则门① **必然 FAIL**（且后续每个组都会 FAIL）。修正方向是**收紧并精确化**，不是放水。
12. **doctest 无法覆盖脚本相关正例**（§2）：`--test` 进程没有初始化脚本语言，
   因此 faithful 的做法是把正例放到门② 真实工程证据，而不是写「加载失败就跳过」的假通过测试。
13. **证据工程里的 `uid` 计数**（§5.2 注）：`--import` 生成 `*.gd.uid`，统计工具照参照语义计入。

---

## 9. blockers

**无。** 全程无环境阻塞：构建 `EXIT=0`，五道门 `EXIT=0`；端口纪律无一次违反
（9877 始终是用户的 PID 36392，9888/9889 用后即释放）。

---

## 10. next_step_recommendation

1. 请决策者裁决 §8 的 **deviation 1**（`project_get_scene_exports` 的判定重写）与 **deviation 2**
   （`SceneTree` 镜像 vs `EditorInterface`）：两者都是「参照在本 fork 上不可用/会崩」的实测结论，
   若要求逐字对齐参照，则本工具会永远返回 `count:0`，需要另行裁决。
2. §7.3 的 `check_contract_subset.ps1` 修正对**后续每一个组**都是必需的，建议写进后续组的任务书（或 PLAYBOOK §3 门①）。
3. 建议把「助手函数上提到 `tool_builder`」列为一个独立的小型框架任务（§8 deviation 9），
   在 B1 剩余 5 组开工前做，避免第 3、4 份副本继续增殖。
4. `docs/DESIGN-DETAIL.md` 可考虑在 §17.2 补一句：**节点的合并属性列表在两个进程里语义不同**
   （编辑器进程不带 `SCRIPT_VARIABLE`），凡「按 usage 位判定脚本导出变量」的实现必须读脚本自身的属性列表
   ——这是 B1 后续 `editor_*` 组很可能踩到的同一个坑。
5. 本组收口后，`project_read_files`（6）、`editor_read_scene_inspector`（7）可按 REPORT-002 §8 的既有顺序派发。

---

## 11. 复现方法（验收方可独立重跑）

```powershell
# 0) 构建（pwsh/cmd，勿用 Git Bash）
D:\Anaconda\Scripts\scons.exe platform=windows target=editor tests=yes module_mono_enabled=no -j8

# 1) 门③ 模块 doctest / 门④ 全引擎
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
bin\godot.windows.editor.x86_64.console.exe --headless --test

# 2) 门① 契约子集（自起 9888/9889，自建 scratch 工程）
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\check_contract_subset.ps1 -Group project_read_analysis

# 3) 门⑤ 接收脚本 ×2
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1

# 4) 门② 证据工程（%TEMP%，含环/未引用资源/addons/@export 脚本）
#    证据工程与两个驱动脚本（setup / run）都**只**放在 %TEMP%，**刻意不入库**：
#    它们是本任务的一次性证据工具，不是模块的一部分（仓库内的正式门脚本是
#    scripts\accept_m1.ps1 与 scripts\check_contract_subset.ps1，均为 PowerShell）。
#    §5.1 已列出工程的全部文件，§5.2/§5.3 已逐条粘贴请求体与响应体，照此可原样重建：
mkdir -p %TEMP%\godot-mcp-evidence-004\proj\{scripts,scenes,resources,addons\myplugin}
#    …按 §5.1 写 project.godot / autoload.gd / exported.gd / helper.gd / hero.tscn /
#      a.tscn / b.tscn / used.tres / unused.tres / notes.md / plugin.cfg …
bin\...console.exe --headless --path %TEMP%\godot-mcp-evidence-004\proj --import
bin\...console.exe --headless --verbose -e --path %TEMP%\godot-mcp-evidence-004\proj --mcp-port=9888
#    每个用例：把 §5.2 的 BODY 写进 body.json，然后
curl.exe -s -X POST -H "Content-Type: application/json" --data-binary @body.json http://127.0.0.1:9888/mcp
# 游戏侧：给 project.godot 加 run/main_scene="res://scenes/hero.tscn" 后
bin\...console.exe --headless --path %TEMP%\godot-mcp-evidence-004\proj --mcp-port=9889
```

结论：**本组 7 个工具已按契约逐字实现并经五道门验证；`status = pass`。**