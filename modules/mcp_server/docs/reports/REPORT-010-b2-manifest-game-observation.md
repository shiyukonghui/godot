# REPORT-010 — B2 开局：manifest + 游戏侧观测组（E3 解锁点）+ 3 项小修

任务书：`modules/mcp_server/docs/tasks/TASK-010-b2-manifest-game-observation.md`
通用规范：`modules/mcp_server/docs/tasks/PLAYBOOK-group-port.md`（已完整阅读）
执行者：Godot 内置 MCP 模块实现工程师（TASK-010）
分支：`feature/mcp-server-module`

## 0. 状态摘要

**commits**（英文提交信息，**未推送**）：

```
d93ff20686  mcp_server: B2 manifest and the game observation + script execution groups (TASK-010)
            Implemented above.

(本报告由紧随其后的一个报告提交引入；该提交只新增 docs/reports/REPORT-010-*.md，不含任何代码改动。)
```

| 项 | 结果 |
|---|---|
| `status` | **完成**：B2 manifest（25 个恰好各一次）、游戏侧观测组（6 工具）+ 脚本执行组（1 工具）移植完毕、3 项小修完成、五道门全绿 |
| 实现的工具数 | 7（`running_game_observation` 6 + `running_game_script_execution` 1），已实现并集 41 → **48** |
| 端点 | 编辑器 9888 = **40**（不变），游戏 9889 = 24 → **31** |
| 门① 契约子集逐字 | 两组各 **3/3 PASS**（9888 与 9889 双向） |
| 门② 三类证据 | 7 工具各成功 / 缺参 / 底层失败，**29/29 PASS**（游戏端点），scope 面 **13/13 PASS** |
| 门③ 模块 doctest | `[MCPServer]*`：**103/103 用例、2554/2554 断言全绿**（B1 基线 97/2422 → 只增不减） |
| 门④ 全引擎回归 | `--headless --test`：**1529/1529 用例、426835/426835 断言，0 failed** |
| 门⑤ `accept_m1.ps1` | 连跑两次（runA / runB）**全部 case PASS**，两次 PASS 清单一致 |
| **E3 解锁链** | **29/29 PASS**：读场景树/属性 → 游戏进程内跑 GDScript 够到单例（`OS`/`Engine`/`SceneTree`）→ 注入输入 → 节点位置 0 → 445 → 释放后冻结在 451 |
| 9877 纪律 | 每阶段前后断言用户编辑器 pid 仍为 **36392**（全部通过） |

---

## 1. B2 manifest 与组划分理由

### 1.1 工件

`modules/mcp_server/docs/tool-groups-b2.json`（**B1 的姐妹文件，未改 `docs/tool-groups.json`**）：
`batch=B2`、`total=25`、9 组、`sha256 = 25c6d8bd44644ecdbcdbf0375bdcb6c48e1aed5f73db74ef2d49edc53446f49f`
（B1 manifest 的运行期指纹未被触碰：`check_tool_groups.py` 输出 `SHA256 0cfcac80f0d999fa7db713ae48f43febe96ae52e2c93633257eeed00ffdfbfac`，与 TASK-009 一致）。

25 个 old name 由 `docs/DESIGN-DETAIL.md` §10 的 B2 段落重新推导（不是手抄），经 `docs/tool-rename-map.json`
换算成新名；**全部 25 个 `disposition=rename`，没有 merge_into，因此 25 = 25 − 0**。

### 1.2 机器校验（真实输出）

```
SOURCE  DESIGN-DETAIL.md section 10: B2 declares 25 old tools, parsed 25/25
DERIVE  excluded (merge_into) = (none)
DERIVE  B2 tools to port = 25 - 0 = 25
GROUP   running_game_observation       channel=running_game scope=game   mutating=False implemented=True  tools=6
GROUP   running_game_frame_observation channel=running_game scope=game   mutating=False implemented=False tools=3
GROUP   running_game_script_execution  channel=running_game scope=game   mutating=True  implemented=True  tools=1
GROUP   running_game_input             channel=running_game scope=game   mutating=True  implemented=False tools=4
GROUP   running_game_node_write        channel=running_game scope=game   mutating=True  implemented=False tools=1
GROUP   running_game_capture           channel=running_game scope=game   mutating=True  implemented=False tools=1
GROUP   editor_playback                channel=editor       scope=editor mutating=True  implemented=False tools=2
GROUP   editor_input_simulation        channel=editor       scope=editor mutating=True  implemented=False tools=6
GROUP   editor_input_read              channel=editor       scope=editor mutating=False implemented=False tools=1
ASSERT  distinct tools in manifest = 25
ASSERT  every B2 tool appears exactly once: PASS (duplicates=0, missing=0, foreign=0)
ASSERT  every name exists in the 171 entry contract: PASS
ASSERT  every group is one channel + one scope + one mutating value: PASS
ASSERT  group sizes <= 10: PASS
ASSERT  25 == 25 - 0: PASS
ASSERT  implemented=true groups = 2, carrying 7 tool(s): running_game_get_scene_tree, ... running_game_execute_gdscript
BYTES 9218
SHA256 25c6d8bd44644ecdbcdbf0375bdcb6c48e1aed5f73db74ef2d49edc53446f49f
TOOL-GROUPS-B2 CHECK PASS
```

校验器：`docs/scripts/check_tool_groups.py --batch B2`（**最小扩展**：不带参数时 B1 路径的输出与断言逐字节不变；B2 路径把同一组不变式重写一遍而不是复用 B1 代码，故意如此——共享代码路径会让 B2 的改动有能力削弱 B1 门）。B2 路径额外校验 manifest 里声明的 `scope` 与映射一致。

跨 manifest 机器校验（证据脚本 `-Phase count`，7/7 PASS）：

```
B1 manifest      : 7 groups, 41 tools, implemented=41
B2 manifest      : 9 groups, 25 tools, implemented=7
overlap          : []
implemented union: 48 tool(s) = 17 editor-scope + 23 both-scope + 8 game-scope
editor endpoint  : 40 tool(s) (union minus game-scope)
game endpoint    : 31 tool(s) (union minus editor-scope)
```

### 1.3 组划分理由（为什么是这 9 组）

划分轴是 **`scope` + `channel` + `mutating` + 依赖**：一组 = 一个 `tools/<group>.{h,cpp}` 文件、一种 `channel`、一种 `scope`、一种 `mutating`（`mutating` 由 GDR-18 唯一确定，见下）、≤10 个工具。

| 组 | 为什么单独成组 |
|---|---|
| `running_game_observation`（game/false，6） | 一次帧内、只读、从 `SceneTree::get_current_scene()` 作答；六个工具共用同一套 helper（节点解析、属性序列化、前序遍历） |
| `running_game_frame_observation`（game/false，3） | **需要帧时钟**：`monitor_properties`（N 帧采样）、`wait_for_node`（轮询到出现）、`capture_frames`（N 帧渲染）。本模块的工具在**同一帧内同步执行**（`MCPServer::pump_frame → MCPHttpServer::poll → handler`），没有跨帧机制；它们**未实现也未被注册**（GDR-7）。**这是本任务显式上报的卡点**，见 §6.3 |
| `running_game_script_execution`（game/true，1） | E3 杠杆：唯一执行调用方代码的工具，`mutating=true` 而观测组全是 `false`，一组只能有一个 `mutating` 值 → 必须分文件 |
| `running_game_input`（game/true，4） | 同一依赖面（`Input` 单例 + `InputEvent` 重建）：录制开始/停止/回放 + 按文本点击 UI |
| `running_game_node_write`（game/true，1） | 唯一的游戏侧属性写；与 project/editor 三个写组共用 `property_type_of` / `coerce_to_property_type`，是 B3 节点写族的游戏侧表头 |
| `running_game_capture`（game/true，1） | 视口回读**落盘**（GDR-18 的条件写 → `mutating=true`） |
| `editor_playback`（editor/true，2） | `editor_play_scene` / `editor_stop_scene` 驱动编辑器自己的场景播放器 |
| `editor_input_simulation`（editor/true，6） | 向**编辑器进程**注入合成事件（含 `editor_add_input_action`）。它们**不被用来驱动游戏**——D56 明确：`editor_simulate_*` 当年注入的是编辑器进程的 `Input`，正是 E3 根因 |
| `editor_input_read`（editor/false，1） | 读输入表；`mutating=false` 使它无法并入上组，也无法并入 playback |

**两处必须写明的「规则逼出来的分裂」**：

1. **capture 家族的强制分裂**：`running_game_capture_frames` 与 `running_game_capture_screenshot` 是同一能力（视口回读），
   但 GDR-18 让带可选 `save_path` 的截图工具 `mutating=true`，而帧捕获保持 `false`；一组只能有一个 `mutating` 值，
   因此 manifest **无法**把它们放进同一组。这不是依赖差异，是规则差异，已写进 manifest 的 `notes.capture_family_split`。
2. **观测组的 6 vs 建议的 7**：任务书建议组里含 `running_game_execute_gdscript`（`mutating=true`, 属另一组）
   与 `running_game_get_node_property_samples`（帧时钟）；按 §1.3 的两个不变式，两者都**不能**留在只读组。
   任务书允许「若某工具属于其他组，不要硬塞；你可在报告里说明最终组内成员与理由」——最终成员与理由如上。

### 1.4 与任务书 schema 的差异

任务书示例给 `{ "batch", "total", "groups": [{name, channel, scope, mutating, implemented, tools}] }`；
本 manifest 完全包含这些键，另外照 B1 manifest 的先例补了 `_comment` / `source` / `counts` / `notes`
（人类与机器的溯源信息）以及每组一个 `batch` + `notes`。校验器只读 `.groups`、组内六键，因此多出来的键不影响任何断言。

---

## 2. 逐工具表（可观察契约与差异）

「迁移源」= PLAYBOOK §1 指定的语义参照（`godot_mcp_gdext/src/commands/*.rs`、`addons/godot_mcp_rs/**`，**只读**）；
`addons/godot_mcp/mcp_game_inspector_service.gd`（更早的纯 GDScript 实现）与 `get_..._gdext/src/commands/node.rs`（编辑器侧）
只在两者冲突时作为「意图」的第二证据，逐条注明。

| new_name | 迁移源位置 | 可观察契约（as-built） | C++ 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `running_game_get_scene_tree` | `addons/godot_mcp_rs/mcp_runtime_agent.gd:82-107`（IPC 转发：`runtime.rs:216-241`）；过滤器意图：`mcp_game_inspector_service.gd:160-248` | `max_depth`(int, 默认 -1=无限；`depth < max_depth` 才要 children，故 0=仅根)、`script_filter`(str)、`type_filter`(str)、`named_only`(bool)。无过滤 → `{"tree":{name,type,path,script?,children?}}`（`children` 为空或超深时省略）；有过滤 → 保留「自身命中或后代命中」的节点（命中链保留），全不命中 → `{"tree":null,"message":"No nodes matched the filter"}`；无场景 → -32000；参数类型错 → -32602 | `tools/running_game_observation.cpp:374`（helper：`_build_tree` / `_build_filtered_tree` / `_node_matches`） | **迁移源收下了 `script_filter`/`type_filter`/`named_only` 却完全不用**（只有 `max_depth` 进了 `_build_tree`）。按 PLAYBOOK §6.6「行为以工具真的能用为准」实现其契约语义（`named_only` = 跳过 `@` 开头的自动名，取自更早实现 `mcp_game_inspector_service.gd:238`）；过滤器两实现的分歧在报告里显式记录 |
| `running_game_get_node_properties` | `mcp_runtime_agent.gd:114-135` + `:716-739`（`_safe_get`）；形状参照 `node.rs:232-266` | `node_path`(str, 必填；`""`/`"."` = 当前场景根)、`properties`(str 数组, 可选)。→ `{"node_path":<绝对路径>,"type":<class>,"properties":{...}}`；不传/传空 = 全部 EDITOR ∪ SCRIPT_VARIABLE 属性（跳过 `_` 前缀与 `script`）；节点解析 5 分支（见 §2.1）；找不到节点 → -32001 + suggestion；无场景 → -32000 | `running_game_observation.cpp:440`（`_read_properties:220`、`_resolve_node:152`） | 形状由 **扁平改为嵌套**（扁平形会与 `node_path`/`type`/`name` 撞键）；序列化统一走模块唯一的 `serialize_variant`（不是 `_safe_get`）；不再返回 `name`（绝对路径已含）；**「全部属性」的判据加了 `PROPERTY_USAGE_SCRIPT_VARIABLE`**——第一版只用 EDITOR，线上证据当场抓到它把脚本变量 `moved_frames` 静默丢掉（见 §5.3） |
| `running_game_get_node_properties_batch` | `mcp_runtime_agent.gd:384-402` | `nodes`(数组, 必填)：每项 `{node_path(str, 必填), properties(str 数组, 可选)}`。→ `{"results":[...],"count":N}`，顺序 = 入参顺序；每项是单节点形状，或 `{"node_path":<原样>,"error":"Node not found: <p>"}`；**请求本身**畸形（项非对象 / 缺 `node_path` / `properties` 类型错）→ -32602，且在读任何节点之前判定（不会半答）；无场景 → -32000 | `running_game_observation.cpp:489` | 每项错误文案由 `"Not found"` 改为 `"Node not found: <path>"`（与单节点工具同一措辞）；条目不再带 `name` 而是带嵌套 `properties`（同上一致性理由） |
| `running_game_get_autoload_node` | `mcp_runtime_agent.gd:364-377` | `name`(str, 必填；空白 → -32602)、`properties`(str 数组, 可选)。→ `{"name":<原样>,"path":"/root/<name>","type":<class>}`，**仅当调用方点名属性时**才追加 `"properties"`；**不需要当前场景**（只看 `SceneTree` 根，与迁移源一致），无 SceneTree → -32000；名字不存在 → -32001 + suggestion | `running_game_observation.cpp:575` | 属性由扁平改嵌套；空 `properties` 时不返回属性（契约写的是「需要获取的属性列表」，与 `get_node_properties` 的「不传即全部」不同，逐字按契约） |
| `running_game_find_nodes_by_script` | `mcp_runtime_agent.gd:348-357` + `mcp_runtime_agent.gd:317-330` | `script`(str, 必填；空白 → -32602)、`properties`(str 数组, 可选, 仅在点名时返回)。按 **脚本资源路径精确相等**（大小写敏感）匹配，前序（depth-first pre-order）遍历当前场景 → `{"nodes":[{name,path,type,properties?}],"count":N}`；无场景 → -32000 | `running_game_observation.cpp:634` | 精确匹配取自**记录在案的**迁移源；拒绝采用更早实现的「大小写不敏感子串」——那会让 `res://enemy.gd` 也命中 `res://boss_enemy.gd`，而契约自己的描述是精确路径。线上证据同时钉了两半（`player.gd` 命中 1，子串 `player` 命中 0） |
| `running_game_find_ui_elements` | `mcp_runtime_agent.gd:404-...`（`_cmd_find_ui_elements` + `_find_ui_recursive`） | `type_filter`(str, 可选)。前序遍历，`Control` 且（无过滤或 `is_class(type_filter)`，故子类也命中）→ `{"elements":[{name,path,type}],"count":N}`；无场景 → -32000 | `running_game_observation.cpp:702` | **一致**（字段、顺序、`is_class` 语义逐个对齐） |
| `running_game_execute_gdscript` | `mcp_runtime_agent.gd:230-253`（`execute_script`）+ `runtime.rs:295-302` | `code`(str, 必填且去空白后非空) 是 **GDScript 函数体**：语句、`return`、循环、`match`，以及列 0 的 `func` 声明（被提到类级，函数体可调用）。→ `{"result":<serialize_variant>,"result_type":"<Variant 类型名>"}`；无 `return` 的体 → `result: null, result_type: "nil"`；不编译 → -32602（`does not compile: <verdict>`）；**本进程尚未初始化脚本语言** → -32000 + suggestion；`Callable` 调用错误 → -32603（那是本文件的 bug） | `tools/running_game_script_execution.cpp:202`（源码构造：`_build_source:150`） | **机制替换**：迁移源剥掉前缀 `return ` 后交给 `Expression.parse/execute`，只能一条表达式、只能解析 base 成员；本实现把代码编译成 `extends RefCounted / func _mcp_execute()` 并调用，因此语句全支持、且能直接够到 `Input`/`Engine`/`OS`/`SceneTree`。返回值由 `str(result)` 改为结构化 `{result,result_type}`。**旧路径的失败在游戏进程内被当场复现**（§6.2） |

### 2.1 节点解析（`_resolve_node`，`running_game_observation.cpp:152`）

与迁移源 `_find_node`（`mcp_runtime_agent.gd:690-714`）逐分支一致：① `""`/`"."` → 当前场景根；② `begins_with("/root/")` → 从 SceneTree 根走绝对路径（autoload 的寻址方式）；③ 其余 → 相对当前场景根；④ 失败 → 全子树按**名字精确相等**搜索。回显的是解析后的**绝对路径**。

### 2.2 遍历的可复现性

三个列表型答案（`nodes` / `elements` / 批量的 `results`）顺序都确定：前序 = `Node::get_child(i)` 的插入序；
`find_nodes_by_script` / `find_ui_elements` 用显式栈（children 逆序入栈）以避免深场景的 C++ 递归爆栈，
同时保持前序。同一场景两次调用的响应字节一致（PLAYBOOK §6.8）。

---

## 3. 注册与框架落点

* `tools/registration.cpp:60-61`：两组各一行调用（+ 头文件 include），顺序 = B2 manifest 的组顺序。**同一批只有一个实现者改树**（§17.1），本任务即该实现者。
* 全部工具经 `MCPTools::ToolBuilder` 注册，显式声明 `channel`/`verb`/`scope`/`mutating`；
  `grep -rn "\.register_tool(" modules/mcp_server/tools/` 仍然**恰好一处**：`tool_builder.cpp:143`（§17.2 的机械 review 检查）。
* `description` 与 `inputSchema` **不是手打的**：由 `scripts/gen_b2_game_schema.py` 从 `docs/tools_list.renamed.json`
  逐字节读出、递归展开（含 `default` / `items` / 嵌套对象），写进 `// BEGIN generated … // END generated` 之间的**每文件一段**区域；
  `channel/verb/scope/mutating` 从 `docs/tool-rename-map.json` 读取，因此声明不可能与权威表不一致。
  **幂等性已机器验证**：连续运行 `--in-place` 两次，第二次输出 `is already up to date`，文件字节不再变化。
  （勘误见 §9.1：生成器第一版把标记放在**每个工具块内部**而整组作为一段生成，第二次运行把每个块又插了一份；
  已修好并把两个文件恢复到单份，随后重新构建、重跑全部门——见 §9.4 的二进制等价性说明。）

---

## 4. 红 / 绿证据（TDD）

命令（两条都真实跑过，输出落盘后取 sha256）：

```
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
```

### 4.1 红阶段（实现之前）

日志 `%TEMP%\mcp010-doctest-red-final2.log`，`sha256 5062cfb91c675136942a5d2507ad062e1f00bff5417cb22ac5a3b9832fde2b00`（34543 字节），退出码 1：

```
[doctest] test cases:  103 |   89 passed |  14 failed | 1429 skipped
[doctest] assertions: 2422 | 2249 passed | 173 failed |
[doctest] Status: FAILURE!
```

失败的 14 个用例（8 个是既有用例里编码了「改动后」计数的断言，6 个是本任务新增）：

```
[MCPServer] the shared registration entry point registers the group
[MCPServer] tools of later batches are not registered
[MCPServer] the project_read_analysis group is registered for both processes
[MCPServer] the project_read_files group is registered for both processes
[MCPServer] the editor_read_scene_inspector group is editor-only
[MCPServer] the project_write_resource_scene tools are registered as mutating both-scope tools
[MCPServer] the editor_write_scene_editor group is editor-only and complete
[MCPServer] the running_game_read_scene group is game-only
[MCPServer] the running_game_observation group is game-only and complete
[MCPServer] the running_game_observation tools validate their arguments and need a running game
[MCPServer] the running_game_script_execution group is game-only and complete
[MCPServer] running_game_execute_gdscript runs a GDScript body and reaches engine singletons
[MCPServer] the no_scene advice follows the process, not the editor
[MCPServer] a double that does not fit an integer property is refused, not folded
```

关键红断言（真实输出节选）：

```
test_mcp_server.h(5133): ERROR: CHECK( content.size() == 1 ) is NOT correct!       <- execute_gdscript 工具还不存在
test_mcp_server.h(5164): ERROR: CHECK( game_suggestion.contains("main scene") ) is NOT correct!   <- 小修 1
test_mcp_server.h(5165): ERROR: CHECK( game_suggestion.contains("project.godot") ) is NOT correct!
test_mcp_server.h(5166): ERROR: CHECK_FALSE( game_suggestion.contains("editor_open_scene") ) is NOT correct!
test_mcp_server.h(5239): ERROR: CHECK_FALSE( MCPTools::coerce_to_property_type(Variant(refused[i]), Variant::INT, ...) ) is NOT correct!  <- 小修 3b
test_mcp_server.h(5240): ERROR: CHECK( refusal.code == -32602 ) is NOT correct!
test_mcp_server.h(5272): ERROR: CHECK( result.error.code == -32602 ) is NOT correct!   <- 小修 3b 的线上形态
test_mcp_server.h(5274): ERROR: CHECK_FALSE( FileAccess::exists(target) ) is NOT correct!   <- 越界值**被写进了 .tres**
```

### 4.2 绿阶段（实现之后，最终二进制）

日志 `%TEMP%\mcp010-final\mcp-doctest.log`（见 §7），退出码 0：

```
[doctest] test cases:  103 |  103 passed | 0 failed | 1429 skipped
[doctest] assertions: 2554 | 2554 passed | 0 failed |
[doctest] Status: SUCCESS!
```

断言**总数** 2422（红）→ 2554（绿）：+132 条只在工具存在后才可达的断言；**通过**数 2249 → 2554（红阶段另有 173 条失败）。
B1 的 97 个既有用例（103 − 6 个新增）在红阶段只是被「注册表计数」断言牵连（实现未落地时计数不成立），绿阶段全过；
若把新增用例整体排除，B1 的既有断言在红/绿两阶段都保持通过——**B1 的 2422 条断言一条都没有被放松或删除**。

### 4.3 红阶段的三项诚实声明

1. **红阶段跑的不是最终测试源码**。红日志是在下列四处**测试侧**缺陷被红运行自己暴露、修好**之前**采的：
   (a) 控制组用例的路径扩展名 `.tres_ok` 让 `ResourceSaver` 找不到格式（测试自己的错，非实现）；
   (b) 直接调用 handler 时原生 `int` 与 JSON 的 `float` 类型差异（期望值写成浮点）；
   (c) `Variant::get_type_name(NIL)` 在本 fork 是 `"Nil"` 不是 `"nil"`；
   (d) doctest 进程没有 `Input` 单例（harness 只为 `[SceneTree]`/`[Editor]` 用例创建，见 `tests/test_main.cpp:181-183`），
   以及 `ScriptServer::init_languages()` 从未被调用。四处都属于测试环境/测试自身的修复，不是放松断言；
   每次修复后都重跑，最终红/绿编号见上。
2. **新增的「整数越界」用例在红阶段就已经是绿的**：`MCPTools::require_int`/`optional_int` 走 `_integral_value`，
   在本 fork 的 MSVC `/fp:strict` x64 上 `(int64_t)1e20` 得到 `INT64_MIN`，随后的往返比较为假 → 已经拒绝。
   也就是说 **3a 在可观察行为上是零变化，是 UB 加固**（见 §8.1 的实测表），我不把它说成「修好了一个可复现的错值」。
   有可观察缺陷的是 **3b 的 `coerce_to_property_type` 路径**（同一红运行里 5239/5272/5274 三条真实失败，且越界值确实落盘）。
3. 红运行中出现过一次 `test case CRASHED: Unhandled SEH exception caught`：测试在工具缺失时对空 `Array` 取 `required[0]`
   导致越界。已把 schema 断言改成「先判类型/长度再取值」的全函数式写法（`dict_of`/`array_of`/`type_of`/`required_name`
   一组 lambda），此后红阶段不再崩溃而是正常判红——这是测试自身的健壮性修复，也已记入 §9.2。

---

## 5. 三类证据（门②）

### 5.1 成功类

游戏端点 9889（真实请求 → 真实响应，全部落盘算 sha256，逐字复制，未改一字）：

```
[g02_get_scene_tree] bytes=509 sha256=23fe2bb6011a9ef2047291f8b39d7e1d1e2109fe1e9114037dee30da745bae19
request : {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"running_game_get_scene_tree","arguments":{}}}
response: {"id":2,"jsonrpc":"2.0","result":{"content":[{"text":"{\"tree\":{\"children\":[{\"name\":\"Player\",\"path\":\"/root/Main/Player\",\"script\":\"res://scenes/player.gd\",\"type\":\"Node2D\"},{\"children\":[{\"name\":\"Score\",\"path\":\"/root/Main/Hud/Score\",\"type\":\"Label\"},{\"name\":\"Start\",\"path\":\"/root/Main/Hud/Start\",\"type\":\"Button\"}],\"name\":\"Hud\",\"path\":\"/root/Main/Hud\",\"type\":\"CanvasLayer\"}],\"name\":\"Main\",\"path\":\"/root/Main\",\"type\":\"Node2D\"}}","type":"text"}]}}
```

（子节点顺序 = `Node::get_child(i)` 的插入序 = `.tscn` 里的声明序：`Player` 先于 `Hud`；两次独立运行的这条响应
正文逐字节相同——这就是 §2.2 的可复现性。）

其余成功类逐条见证据脚本日志（§7）：场景树过滤、单节点属性（基线/全属性/点名）、批量、autoload、
按脚本查找（精确命中和子串不命中两半）、UI 元素（无过滤与 `Button` 过滤）、
`execute_gdscript` 的 4 种成功形态（单表达式 / 单例 / 多语句+提升的 helper 函数 / JSON-RPC 信封）。

### 5.2 缺参与底层失败类

```
[g18_missing_parameter]  code=-32602 message='Missing required parameter: node_path'
[g19_mistyped_parameter] code=-32602 message="Parameter 'max_depth' must be an integer, got String"
[g20_node_not_found]     code=-32001 message="Node 'NoSuchNode' not found"
                         data.suggestion='Use running_game_get_scene_tree to list the nodes of the running scene'
[g21_autoload_not_found] code=-32001 message="Autoload 'NoSuchAutoload' not found"
[g22_execute_parse_err]  code=-32602 message="Parameter 'code' does not compile: Parse error"
[g23_execute_empty]      code=-32602 message="Parameter 'code' must not be empty"
[g24_no_current_scene]   code=-32000 message='No scene is currently open'
                         data.suggestion='Start the game with a main scene (application/run/main_scene in project.godot) and call this tool while the game is running'
```

**不可构造类的显式声明**（PLAYBOOK 要求）：

| 类 | 工具 | 声明 |
|---|---|---|
| 底层失败 = `-32601` | 全部 7 个 | 只在**编辑器**端点可构造 → 已构造（§6.4 的 scope 面：7 个工具在 9888 各自 `Method not found: <name>`） |
| 底层失败 = 无当前场景（`-32000`） | 6 个观测工具 | **在游戏端点上只对 5 个可构造**：`get_scene_tree` 已构造（§7 的 g24，`current_scene=null` 的第二个 scratch 工程）。`get_node_properties`/`batch`/`find_by_script`/`find_ui_elements` 与它走同一个 `_current_scene()` 守卫（同一函数、同一分支），且该守卫在 doctest 里逐个被断言（无 SceneTree 的进程）；再为它们各起一个清空场景的游戏进程不会给出新信息，故不重复构造。`get_autoload_node` 按契约**不需要**当前场景，其无 SceneTree 形态只在 doctest 可构造 |
| 底层失败 = 无脚本语言（`-32000`） | `execute_gdscript` | 只在「引擎尚未初始化脚本语言」的进程可构造（`--test` / `--check-only`）。**已在 doctest 里构造并断言**（见 §6.2 的 (2) 段） |
| 底层失败 = GDScript 类不存在（`-32000`） | `execute_gdscript` | **不可构造**：本 fork 的 gdscript 模块无条件注册该类（`modules/gdscript/register_types.cpp:140`，`MODULE_INITIALIZATION_LEVEL_SERVERS`），没有「不带 GDScript 的构建」可用。该分支是防御性的，只在报告里声明 |
| 底层失败 = `-32603`（Callable 调用错误） | `execute_gdscript` | **不可构造**：生成的方法必然存在（源码由本模块构造并已验证可实例化），要走进去只能人为 bug。声明为不可构造 |

### 5.3 线上证据抓到的一个实现缺陷（自我修正，append-only）

第一次 `-Phase game` 的 `g05_properties_all` 实测键列表**只有 27 个引擎属性、没有 `moved_frames`**：

- 原因：第一版「全部属性」判据只用 `PROPERTY_USAGE_EDITOR`；Godot 4 里普通 `var x` 带的是
  `PROPERTY_USAGE_SCRIPT_VARIABLE`，没有 `@export` 就不带 EDITOR。
- 影响：游戏观测最关心的**脚本变量**被静默丢弃，`{"properties": {…}}` 变成「只有引擎属性」。
- 处置：判据改为 `PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE`（仍跳过 `_` 前缀与 `script`），
  重跑后键列表 30 个、含 `injected_events`/`moved_frames`/`total_move`（§7 的 `game_node_properties_all_editor_and_script`）。
- 这条是先由**线上证据**（不是 doctest）发现的，也正是任务书把 E3 证据链列为验收重点的价值所在。

---

## 6. E3 解锁证据链（含旧路径对比）

**结论：全链 29/29 PASS。整条链只经过 9889（游戏端点）与一个 headless 游戏进程；编辑器进程只在 scope 面作反例。**

### 6.1 链的构造

scratch 工程（`%TEMP%\mcp010-b2-observation-scratch`，仓库外）：

* `project.godot`：main_scene、一个 autoload `GameState`（`score=7`）、一个**无事件**的输入动作 `mcp_test_jump`
  （无事件是关键：只有 `InputEventAction` 能承载它）；
* `scenes/main.tscn`：`Main(Node2D)` → `Player(Node2D, player.gd)`、`Hud(CanvasLayer)` → `Score(Label)`、`Start(Button)`；
* `player.gd`：`_unhandled_input` 数注入事件；`_process` 在动作按下期间 `position.x += 1` 并累加 `moved_frames`。

### 6.2 链的三段（真实响应节选）

**① 读运行中的场景树与属性**（见 §5.1 的 g02，以及基线/全属性/批量的实测值）。

**② 在游戏进程内执行脚本并够到引擎单例**

```
[g06_execute_gdscript_singletons]
code:
  var tree := Engine.get_main_loop() as SceneTree
  var legacy := Expression.new()
  legacy.parse("Input.is_action_pressed(\"ui_accept\")")
  var legacy_base := RefCounted.new()
  var legacy_value = legacy.execute([], legacy_base, false)
  return { "pid": OS.get_process_id(), "frames": Engine.get_process_frames(),
           "scene_name": tree.current_scene.name,
           "player_x": tree.current_scene.get_node("Player").position.x,
           "legacy_failed": legacy.has_execute_failed(),
           "legacy_error": legacy.get_error_text(),
           "legacy_value_is_null": legacy_value == null }
response:
  {"result":{"frames":1261,"legacy_error":"Invalid named index 'Input' for base type Object",
             "legacy_failed":true,"legacy_value_is_null":true,"pid":50156,
             "player_x":0.0,"scene_name":"Main"},"result_type":"Dictionary"}
判定：pid=50156 (engine pid=53140) frames=1261 scene_name=Main player_x=0.0  → PASS
      legacy.has_execute_failed()=True legacy.get_error_text()='Invalid named index 'Input' for base type Object'  → PASS
```

两件事同时被钉死：

* **本模块的路径够到了单例**：`OS.get_process_id()` 返回的是**引擎进程**的 pid（与控制台包装进程 53140 不同，
  这正是「代码在哪个进程里跑」的直接区分）；`Engine.get_main_loop()` 拿到运行中的 `SceneTree` 并读到了 `current_scene` 与节点位置。
* **旧路径为何做不到**：迁移源用 `Expression.execute([], base, false)`，`Expression` 只在 **base 对象的成员**里解析名字，
  不查全局单例；同一个进程内当场复现，错误文本是
  `Invalid named index 'Input' for base type Object`，且返回值为 `null`——与任务书 §2 描述的失败逐字一致。
  这条对比不是引用文档，而是**在游戏进程里跑出来的**。

另外，doctest 进程里同时钉了「旧路径失败 / 新路径成功」两半（`[MCPServer] running_game_execute_gdscript runs a
GDScript body and reaches engine singletons` 的 (6) 段用 `Expression` 复现失败，(4)(5) 段用工具成功取到 `OS`/`Engine` 的值）。

**③ 在游戏进程内注入输入并观察到可观测的状态变化**

```
[g07_inject_input]
code:  var event := InputEventAction.new(); event.action = "mcp_test_jump"; event.pressed = true
       Input.parse_input_event(event)
       return {…, "action_known_to_InputMap": InputMap.has_action("mcp_test_jump"),
                    "pressed_same_frame": Input.is_action_pressed("mcp_test_jump")}
response: {"result":{"action":"mcp_test_jump","action_known_to_InputMap":true,
                     "injected":true,"pressed_same_frame":false},"result_type":"Dictionary"}
判定：injected=True action=mcp_test_jump action_in_InputMap=True pressed_same_frame=False
      （缓冲：headless DisplayServer 在下一帧开头 flush，`display_server_headless.cpp:53-55`，故同帧还看不到）→ PASS

[g08_properties_after]（约 3 秒后，另一帧/另一次请求）
{"properties":{"injected_events":1,"moved_frames":445,"position":{"x":445.0,"y":0.0},"total_move":445.0},"type":"Node2D"}
判定：position.x 0 -> 445；moved_frames 0 -> 445；injected_events=1
      （注入的 InputEventAction 同时走到了 `_unhandled_input`）→ PASS
```

**因果性而不是相关性**：随后投递 `pressed=false` 的同一动作，再间隔两秒读两次：

```
[g09_release_input]  {"result":{"pressed_same_frame":true,"released":true}}     → 释放事件已投递（缓冲同上）
[g10_properties_frozen_a] position.x=451.0 moved_frames=451
[g11_properties_frozen_b] position.x=451.0 moved_frames=451
判定：position.x 451.0 -> 451.0；moved_frames 451 -> 451（两次读取相隔两秒、在释放事件之后）→ PASS
```

**整条链不需要编辑器进程参与**：所有请求都打 `127.0.0.1:9889`；编辑器进程只用于反例（§6.4）。
游戏进程由脚本自己启动（`--headless --path <scratch> --mcp-port=9889`），结束即由脚本自己关闭。

### 6.3 卡点：帧时钟组（未实现，显式上报）

`running_game_get_node_property_samples`（旧 `monitor_properties`）、`running_game_find_node_when_available`（旧 `wait_for_node`）、
`running_game_capture_frames`（旧 `capture_frames`）需要**在两次观测之间让游戏推进若干帧**。迁移源用
`await get_tree().process_frame`（`mcp_runtime_agent.gd` 的 `_cmd_monitor_properties`/`_cmd_capture_frames` 都是协程），
而本模块的工具**在服务该请求的那一帧内同步执行完**（`MCPServer::pump_frame → MCPHttpServer::poll → MCPToolRegistry::call_tool → handler`，
`mcp_http_server.cpp` 的连接状态机没有「挂起等待续答」这一档）。

**最小反例/最小证明**：同一帧内 N 次采样只会得到 N 个相同的值；`capture_frames` 只能重复抓同一帧的画面；
`wait_for_node` 无法等到下一帧出现的节点。这不是性能问题，而是**语义不可表达**。

**建议**（不在本任务范围内，交决策者裁决）：给 `MCPHttpServer` + `MCPJsonRpc` 增加「延迟应答」通道
（连接留在 pending 状态、每帧调用一次续答回调、工具 handler 变成状态机），再实现该组。
在那之前，manifest 把这 3 个工具留在 `running_game_frame_observation` 组并标 `implemented=false`，
**不注册**（GDR-7：绝不注册不能工作的工具）。

### 6.4 端点语义（scope 面，13/13 PASS）

```
editor 9888 (40 tools)：不含任何 B2 游戏侧工具 → 7 个工具逐个调用均 `Method not found: <name>`（-32601，未执行）
game   9889 (31 tools)：7 个工具各出现恰好一次；editor_get_errors 仍缺席，调用仍 -32601
editor-only (17)：editor_get_errors … editor_remove_output_log
game-only   (8) ：running_game_find_nearby_nodes, running_game_get_scene_tree, running_game_get_node_properties,
                  running_game_get_node_properties_batch, running_game_get_autoload_node,
                  running_game_find_nodes_by_script, running_game_find_ui_elements, running_game_execute_gdscript
```

---

## 7. 门（指令、真实输出、退出码）

所有门在**最终二进制**上重跑一遍（脚本 `scripts/mcp010_final_gates.cmd` 串行执行；日志目录 `%TEMP%\mcp010-final`）。

| 门 | 命令 | 输出（节选） | 退出码 |
|---|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group running_game_observation` | `PASS editor_9888_contract_subset` / `PASS game_9889_contract_subset` / `PASS guard_user_port_9877` / `group=running_game_observation tools=6 contract=171` / `implemented_union=40 tools (editor endpoint) / 31 tools (game endpoint)` / `3/3 checks passed` | 0 |
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group running_game_script_execution` | 同上，`tools=1`，`3/3 checks passed` | 0 |
| ② E3 证据链 + 三类证据 | `mcp010_b2_observation_evidence.ps1 -Phase game` | 见 §6；`=== phase game: 29/29 checks passed ===` | 0 |
| ② scope 面 | 同上 `-Phase scope` | `=== phase scope: 13/13 checks passed ===` | 0 |
| ② manifest 机器校验 | 同上 `-Phase count` | `=== phase count: 7/7 checks passed ===`（含 B1 校验器 exit 0、B2 exit 0、跨 manifest 48/17+23+8） | 0 |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | `103 passed / 0 failed`，`2554 passed / 0 failed`，`Status: SUCCESS!` | 0 |
| ④ 全引擎回归 | `--headless --test` | `test cases: 1529 | 1529 passed | 0 failed | 3 skipped`；`assertions: 426835 | 426835 passed | 0 failed`；`Status: SUCCESS!` | 0 |
| ⑤ `accept_m1.ps1` ×2 | `powershell -File scripts\accept_m1.ps1`（runA / runB） | `22/22 cases passed`（两次相同）；`implemented tools = 40 (editor endpoint) / 31 (game endpoint); contract = 171`；`equality gate coverage : 40 tool(s) compared verbatim on the editor endpoint`；`implemented=48`；case1…case20 全 PASS（含 `case12_game_process_endpoint`、`case13_game_without_port`、`case14_port_occupied`、`case20_tools_list_cross_process_restart`、`guard_user_port_9877`、`gate_scope_declared`）；runA 与 runB 的 22 行 PASS 清单**逐行相同** | 0 / 0 |

**9877 纪律**：每个阶段都以 `pid_before == pid_after` 断言用户编辑器（PID 36392）未被触碰，全部 PASS
（`guard_user_port_9877 :: port 9877 pid_before=36392 pid_after=36392`）。

**「最终二进制」的界定（说明为什么 §9.1 的生成器修复不削弱上述任何一条）**：生成器修复只移动了生成的**注释**位置，
没有任何代码变化。修复后的二进制与修复前的二进制上，以下日志**逐字节相同**：
`full-test.log`（`78d095e3…`）、`gate1-observation.log`（`e0df1f74…`）、`gate1-script.log`（`9f7b35f9…`）；
`mcp-doctest.log` 的唯一差异是引擎为内存脚本生成的合成 cache 键
（`gdscript://-9223371794122013759.gd` 之类，每次运行不同），其余内容逐行相同。因此 §7 的每一条均可视为
「修复前后同一行为」的证据，而不是两套结果。

**门脚本的最小扩展（不削弱断言）**：

* `scripts/check_contract_subset.ps1`：新增读取姐妹 manifest `docs/tool-groups-b2.json`，把两个 manifest 的组**并起来**
  做「组名查找」和「已实现并集」；其余断言（含 `MUST be hidden on the <label> endpoint` 的显式缺席断言、逐字段 verbatim 比较）**一字未改**。
* `scripts/accept_m1.ps1`：`$ToolNames` 追加 7 个新名（全部 `scope=game`）；`$EditorToolNames`/`$GameToolNames`/
  两个 only-list 由 `tool-rename-map.json` 推导，因此期望值自动跟上，未新增或放松任何断言。
* `docs/scripts/check_tool_groups.py`：新增 `--batch B2`（不带参数= B1 原路径逐字节不变）。

---

## 8. 三项小修的前后对照（任务书 §3）

### 8.1 小修 3a：`tools/tool_builder.cpp:172` `_integral_value`

规则：先做范围判定，再做转换；`NaN` 对两个边界都比较为假，因此被同一判定拒掉；拒绝即 `-32602`（沿用既有文案
`Parameter 'x' must be an integer, got float`），**不再有任何越界 `double→int64` 强转被执行**。

实测（本 fork：MSVC / `/fp:strict` / x64，`coerce_to_property_type(·, INT)` 与 `require_int/optional_int` 各测一遍）：

| 输入 | 修前 | 修后 | 期望 |
|---|---|---|---|
| `2.0` | 接受 → 2 | 接受 → 2 | 不变 |
| `-5.0` | 接受 → -5 | 接受 → -5 | 不变 |
| `9.0e18`（可表示） | 接受 → 9000000000000000000 | 接受 | 不变 |
| `1e20` | `_integral_value`：拒（往返比较失败）／`coerce`：**接受并写盘**，落到 `INT64_MIN`（UB 的实测结果） | 两处都拒 `-32602` | 拒 |
| `-1e20` | 同上 | 两处都拒 | 拒 |
| `NaN` | `_integral_value`：拒／`coerce`：拒（既有非有限判定） | 都拒 | 拒 |
| `inf` | 同上 | 都拒 | 拒 |
| `1.5`（在范围内但非整） | 拒（`_integral_value`）／`coerce` 仍按 `type_convert` 截断 | **不变**（本小修只收紧越界） | 不变 |

**诚实标注两点**：
1. 任务书写「实测越界值 `1e20` 静默变 `0`」。在本 fork 的 `/fp:strict` x64 构建上我**没有复现出 0**：
   `coerce_to_property_type(Variant(1e20), Variant::INT, …)` 的修前结果是**未被拒绝**（`type_convert` 正常返回），
   线上写进 `.tres` 的整数值是 `INT64_MIN`（-9223372036854775808），红运行的三条失败断言是
   `5239/5240/5272/5274`。**「变 0」这个具体数字我无法证实**，可证实的是「越界 double 被静默接受、写入了错的整数」。
   按 PLAYBOOK §7.3 在此显式标注，而不是照抄。
2. 因此 3a（`_integral_value`）在本构建上**可观察行为零变化**，它的价值是消除 UB（换编译器/换架构/换优化档就可能变）并让
   「越界必拒」成为契约而不是巧合；可观察的缺陷修在 3b。对应测试用例
   `[MCPServer] the integer helpers refuse a double that does not fit an int64` 在红阶段就已通过，我不把它算作「红→绿」。

### 8.2 小修 3b：`tools/tool_helpers.cpp:415` `coerce_to_property_type`

新增守卫：`p_target_type == INT` 且值为 `FLOAT` 时，若不在 `[-2^63, 2^63)` 内 → `-32602`
`Parameter '<name>' is outside the range of a 64-bit integer`；非有限值沿用既有 `contains a non-finite number`。
**修前**：`project_create_resource` 用 `Curve.bake_resolution`（int 属性）配 `1e20` → 调用成功、`.tres` 落盘、属性值为错的整数；
**修后**：`-32602`、**文件不存在**；`NaN`/`inf` 同样 `-32602` 且不落盘；在范围内的 `200.0` 仍正常写入并读回 `200`（控制组）。

### 8.3 小修 1：`tool_registry.cpp:66` `MCPToolError::no_scene()`

措辞规则（**按进程**，不按工具名——因为 `scope=game` 的工具在编辑器进程里根本不可达，GDR-7/§17.3）：

* 游戏进程（`Engine::is_editor_hint() == false`）：
  `"Start the game with a main scene (application/run/main_scene in project.godot) and call this tool while the game is running"`
* 编辑器进程：`"Use editor_open_scene to open a scene first"`（与 B1 逐字一致，编辑器组不受影响）
* `error.message` 仍为 `"No scene is currently open"`、`code` 仍为 `-32000`（既有断言不变）。

前后对照：

| 面 | 修前 | 修后 |
|---|---|---|
| doctest（非编辑器进程） | 建议里出现 `editor_open_scene`（对游戏进程是不可能的建议） | `contains("main scene")`/`contains("project.godot")` 为真、`contains("editor_open_scene")` 为假 |
| 9889 线上（`current_scene=null` 的运行中游戏） | 同上 | `data.suggestion='Start the game with a main scene (application/run/main_scene in project.godot) and call this tool while the game is running'` |
| 9888 线上 | 不可达（游戏侧工具在编辑器端点 -32601） | 不可达，编辑器组（走 `is_editor_process()` 分支）措辞不变 |

注意：`project_read_analysis.cpp:364` 那个 `no_scene()` 调用点位于 `if (is_editor_process())` 之内，因此拿到的仍是编辑器措辞。

### 8.4 小修 2：`mcp_server.cpp:411` 绑定成功打印 INFO

```
[MCP] listening on 127.0.0.1:9889 (editor=false, tools=31)          <- 既有 role 行（accept_m1 的 role=game 断言依赖它）
[MCP] INFO: MCP server is ready on 127.0.0.1:9889 as the game process (port source=cmdline, tools=31)   <- 新增
```

一行 INFO 带三件事：**端口**、**进程类型（editor/game）**、**端口来源（cmdline / project setting / default）**。
它在**绑定成功之后**才打印，实测三类进程：

```
# 游戏进程（9889，source=cmdline）——证据脚本 -Phase game 的 g01 断言
[MCP] role=game configured_port=9889 source=cmdline listen=true
[MCP] listening on 127.0.0.1:9889 (editor=false, tools=31)
[MCP] INFO: MCP server is ready on 127.0.0.1:9889 as the game process (port source=cmdline, tools=31)

# 编辑器进程（9888，source=cmdline）——证据脚本 -Phase scope 的编辑器侧日志
[MCP] role=editor configured_port=9888 source=cmdline listen=true
[MCP] listening on 127.0.0.1:9888 (editor=true, tools=40)
[MCP] INFO: MCP server is ready on 127.0.0.1:9888 as the editor process (port source=cmdline, tools=40)

# --import（编辑器进程，source=default → 9877）——本机上 9877 被用户编辑器占着
[MCP] role=editor configured_port=9877 source=default listen=true
[MCP] bind failed on 127.0.0.1:9877 (error=22)
[MCP] get_port()=0 (MCP server disabled)          <- 没有 INFO 行：INFO 只在成功之后打印
```

因此：① 未指定 `--mcp-port` 的 `--import` 仍然**不会**在后台留下一个监听中的服务（GDR-4 的默认端口语义不变）；
② 绑定失败时不会出现「服务已就绪」的误导性 INFO 行；③ 三次 `--import` 都退出 0，非交互式导入不受影响。
（本机上「9877 空闲时的 `--import`」这一状态**无法构造**——不允许停掉用户编辑器（PID 36392）；锁定
`configured_port=9877 source=default` 的日志已由 `accept_m1.ps1` 的 `case13`/`case14` 覆盖。
证据日志：`%TEMP%\mcp010-b2-observation-logs\b2-game.out.log` / `b2-editor-scope.out.log` / `import-b2-*.out.log`。）

---

## 9. 偏离、勘误与撤回

### 9.1 生成器第一版不幂等（已修，影响面已闭合）

`gen_b2_game_schema.py` 第一版把 `// BEGIN/END generated` 标记放在**每个工具块内部**，却把整组作为一段生成，
于是第二次 `--in-place` 只替换了第一个块的标记区间、把整段又插了一遍。**实测**：观察组文件 30806 → 45155 字节。
已改为**每文件一对标记**（整组一段），并机器验证幂等（第二次运行输出 `is already up to date`，字节不变）。
随后两个文件按单份重建、重新构建、**全部门重跑**（§7 的所有输出都来自修复后的二进制）；
旧二进制与修复后二进制的差异仅在于注释位置导致的调试信息/行号（`version_hash` 未变，也无任何代码变化）。

### 9.2 测试自身的四处修复

见 §4.3（控制组扩展名、原生 int/JSON float、`"Nil"` 大小写、`Input` 不可用）；
另加一处健壮性修复（空 `Array` 取值崩溃 → 全函数式 schema 断言）。

### 9.3 与任务书/手册的显式偏离

1. **mark implemented 的组是两个**，不是任务书说的「除你本任务实际完成的那一组」：E3 证据链必须用到
   `running_game_execute_gdscript`，而它 `mutating=true`、按 §17.1 不能与只读观测组同组。因此
   `running_game_observation` 与 `running_game_script_execution` 都标 `implemented=true`，共 7 个工具。
2. **观测组最终 6 个工具**（建议清单一度为 7），`running_game_get_node_property_samples` 与
   `running_game_find_node_when_available` 移入未实现的 `running_game_frame_observation`（理由见 §6.3）；
   任务书允许「不硬塞」并要求说明，故此处显式列出。
3. **新增的 `Input` 线上证据取代了 doctest 里的 `Input` 断言**：doctest 进程没有 `Input` 单例（harness 只为
   `[SceneTree]`/`[Editor]` 用例创建），在 doctest 里断言 `Input.is_action_pressed` 会测到「null 实例上的运行时错误」而
   不是工具行为；已在测试注释里写明，并改到 9889 线上（`game_input_injection_is_delivered` / `game_injected_input_moved_the_node`）。
4. **`execute_gdscript` 增加了一条任务书没写的守卫**：`ScriptServer::are_languages_initialized()` 为假时返回
   `-32000 not_implemented` + suggestion。理由：`--test`/`--check-only` 这类进程从不调用
   `ScriptServer::init_languages()`（`main.cpp:921-943` 早于 `:3863`），不设守卫时工具会把「进程没有脚本语言」
   报成「你的代码不编译」（实测文案 `does not compile: Compilation failed`，引擎日志里真正的原因是
   `Native class "RefCounted" not found`），那是把模块的环境问题甩给调用方。
5. **`execute_gdscript` 的错误码分配**（任务书未指定）：`code` 参数本身的问题（缺失/空白/类型错/**不编译**）→ `-32602`；
   「本进程没有脚本语言」/「本构建没有 GDScript」→ `-32000`；`Callable` 调用错误 → `-32603`。
6. **`running_game_get_node_properties` 形状选择**：采用 Rust 编辑器侧参照（`node.rs:232-266`）的嵌套 `properties`
   与模块唯一序列化器 `serialize_variant`，而不是迁移源的扁平形状与 `_safe_get`。理由：扁平形会与 `node_path`/`type`/`name`
   撞键，且模块内部只应有一个序列化器（差异已逐条列在 §2）。
7. **`find_nodes_by_script` 精确匹配 vs 子串匹配**：取记录在案的迁移源（精确相等），并把「子串不命中」也做成证据
   （`game_find_nodes_by_script_does_not_match_a_substring`）。
8. **一处 `notes` 键**：manifest 用了任务书示例之外的键（`_comment`/`source`/`counts`/`notes`/每组 `batch`+`notes`），
   照 B1 manifest 先例，机器校验只读需要的键。
9. **`docs/scripts/check_tool_groups.py` 里 B2 路径故意重写了不变式检查**而不是抽公共函数：为了让 B1 门的输出与断言
   **逐字节不变**（B1 的日志/指纹在 TASK-002/003/009 的报告里被引用过）。

### 9.4 撤回/无法证实的说法

* **「越界值 1e20 静默变 0」无法证实**：本构建上实测写入的是 `INT64_MIN`，请以 §8.1 的实测为准。
* 迁移源 `_find_node` 的注释声称「不区分大小写」，其**代码**是 `node.name == name`（精确、大小写敏感）。
  本实现按代码（精确）实现，并把注释与代码的矛盾记在此处。

### 9.5 环境事实（供后续批次的实现者节省时间）

* **doctest 进程没有 SceneTree、没有 `Input` 单例、脚本语言未初始化**：`Main::test_entrypoint()`
  （`main/main.cpp:921-943`）在 `Main::setup2()` 之前跑 `test_main()`；harness 只为 `[SceneTree]`/`[Editor]` 用例
  创建 DisplayServer/Input/InputMap/SceneTree（`tests/test_main.cpp:181-251`），`ScriptServer::init_languages()`
  只在 `Main::setup2()`（`:3863`）被调用。任何「需要运行中游戏状态」的 doctest 都应据此设计（本任务的做法：
  纯逻辑 + 参数契约进 doctest，节点树/输入/单例上网）。
* **控制台包装进程与引擎进程不是同一个 pid**：`OS.get_process_id()` 返回被包装的真实引擎进程 id，
  证据里两者不同（50156 对 53140，每次运行不同），这反而是「代码在游戏进程里执行」的旁证。
* **headless 端点上注入的输入是缓冲的**：`Input.parse_input_event` 只入缓冲，
  `DisplayServerHeadless::process_events()`（`servers/display/display_server_headless.cpp:53-55`）在下一帧开头 flush；
  因此「注入」与「观测变化」必须是两次请求（本证据链就是这么构造的）。

---

## 10. 工件指纹（sha256，全部为落盘后计算）

| 文件 | sha256 |
|---|---|
| `docs/tool-groups-b2.json` | `25c6d8bd44644ecdbcdbf0375bdcb6c48e1aed5f73db74ef2d49edc53446f49f` |
| `docs/scripts/check_tool_groups.py` | `c7561484c70b690213b5fb3c10c0a8326291a71bec058a7ce7535b846de833fa` |
| `scripts/gen_b2_game_schema.py` | `a634bfc09346b87abc83d16f606b26cd82d8a5977cd34b425f8fa75e67c2deff`（含 §9.1 的幂等修复） |
| `scripts/mcp010_b2_observation_evidence.ps1` | `34cb7164d062bcb547e8bb8b01f6e83d70a2923d7433ca70a25e1f71d529375d` |
| `scripts/mcp010_final_gates.cmd` | `bbeccefb47afd844822f38db72915cd2b7f1997df4313bd1db80d7940b8a06f2` |
| `scripts/check_contract_subset.ps1` | `0984dee498c1449a5fc8d46c529e3bb447557198a033a4bf80eaeb3a4fec15cd` |
| `scripts/accept_m1.ps1` | `f379132ff9a1c8ea77da9958047109fa9dc2a43f3366237c6c905acecf7cdfbe` |
| `tools/running_game_observation.h` | `a632c8818630f52ee861c2642226221b34cc78911fb099e80b67c177be29eb8e` |
| `tools/running_game_observation.cpp` | `99f91dbf5eb9099d14a8a487c7fddea6fe87066d70a0904922600837836e48cf` |
| `tools/running_game_script_execution.h` | `fec03f23af8383b85d52d2a1bbbfb9704b360716de85ebbd6ed5d4e730205b2f` |
| `tools/running_game_script_execution.cpp` | `d91ad42b9555b1c6fa6a329d6001bca32cee9032e2a2a300d30e98ee7146ef4a` |
| `tools/registration.cpp` | `815ca5c549e525da5249641541ae1cd62623a271e842da999820275f887c120d` |
| `tools/tool_builder.cpp` | `dcd5e977d6ddaf8679eaa53d6f50afd44b3352a14f0a825ecab0d2a5a863eb38` |
| `tools/tool_helpers.cpp` | `597edf0ad763f1ad9dcb47aa53eb2c2ea5d591fe923fb93a8a094a8ff717eb16` |
| `tool_registry.cpp` | `a261c435da6b4088e1e56897fc8487639dfd9d4e762920c7b41d9da777fd0cba` |
| `mcp_server.cpp` | `3df97af39308d07b3f8b812db9932bcae16d576d1f894d2c576b31b5324023bf` |
| `tests/test_mcp_server.h` | `8f35b06f49120f506eddf6b9062d6a088498fc7071e41e177137fa38c0d04174` |

日志指纹（`%TEMP%`，落盘后计算；先于/后于最终二进制修复的说明见 §9.1）：

| 日志 | sha256 |
|---|---|
| 红阶段 `mcp010-doctest-red-final2.log` | `5062cfb91c675136942a5d2507ad062e1f00bff5417cb22ac5a3b9832fde2b00` |
| 绿阶段（实现后第一版二进制）`mcp010-doctest-green4.log` | `79b03e114677fb23f8e5181cbd9dfde77e9e0f44288fdd01fefa2144a2db932e` |
| E3 证据（第一版二进制）`mcp010-evidence-game2.log` | `75a133f7c070dcf7c653dcaceb16ba3b64451b6043b71321e271759b7ed3d2a8` |
| scope 证据（第一版二进制）`mcp010-evidence-scope.log` | `7dfba2666ff1c3c8d35bee2894b50f4555638a744f9bb3d306f2ccda8e5af0e4` |

最终二进制各门日志（`%TEMP%\mcp010-final\`，§7 的引用即来自此目录）：

| 日志 | sha256 |
|---|---|
| `mcp-doctest.log`（门③） | `02d6f8132047cb0bd2deb5ab7077a893ba53094bb91889e4f605c610b05044b2` |
| `full-test.log`（门④） | `78d095e3ca3bf4a887312cfaeee2ab28fb6752be7c04dd602eda5c079a33958e` |
| `gate1-observation.log`（门①） | `e0df1f744677d652dc65a9295a7c55049ae9b60bab0cefc819fa2a483287a9b4` |
| `gate1-script.log`（门①） | `9f7b35f99744e9aa9d6b9ba0ce529549b67b9500392807699d92f6964027c4c9` |
| `evidence-count.log`（门②） | `e3bb568b9f8f01e4173c0f533da6f33a097e28de112c23177a55b46a617b7e77` |
| `evidence-game.log`（门②，E3 链） | `04d8a27f8563a03bb6270f1ddf1e37fcd75a9617e4e552236b839b32fc9de320` |
| `evidence-scope.log`（门②） | `4d4b91d8c54d648acdfda46aa6af5e6c7852c90252f7147074bc40b4029f2892` |
| `accept-runA.log`（门⑤） | `d144d0c9d4811f175c09d558b908a43f18048921901e65ba9b9280dca711edba` |
| `accept-runB.log`（门⑤） | `f04f180bdfab5d18e0cf1c3e9fec6adfaa171e2aed11d2c02d4a61f67d47100b` |
| `runner.log`（九道门的串行记录，全 `EXIT=0`） | 见同目录 |

每一条 9889 的请求/响应正文另有一份落盘文件（`%TEMP%\mcp010-b2-observation-evidence\<case>.request.json` /
`<case>.response.json`），脚本在写响应时逐条打印 `bytes` 与 `sha256`（PLAYBOOK §7.1 的 curl-to-file 纪律）。

---

## 11. `deviations` / `blockers` / `next_step_recommendation`

### deviations（逐条）

1. manifest 标 `implemented=true` 的组是**两个**（`running_game_observation` + `running_game_script_execution`，共 7 工具），
   理由：E3 链必须包含 `running_game_execute_gdscript`，而它因 `mutating=true` 不能与只读组同组（§9.3-1）。
2. 观测组最终 6 个工具，`running_game_get_node_property_samples` / `running_game_find_node_when_available` 移入未实现组（§6.3）。
3. `running_game_get_node_properties` 采用嵌套 `properties` + `serialize_variant`（Rust 编辑器侧参照），与记录在案的
   迁移源的扁平 `_safe_get` 形状不同（§2、§9.3-6）。
4. 「全部属性」判据为 `PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE`（第一版只用 EDITOR，线上证据抓到此缺陷，§5.3）。
5. `find_nodes_by_script` 采用精确路径匹配（子串匹配被拒，附证据）。
6. 找不到节点/autoload 用 `-32001`+suggestion（迁移源经 IPC 变成 `-32603`）——沿用 PLAYBOOK §6.1 的既定偏差。
7. `execute_gdscript` 的方言由「单条 Expression」改为「GDScript 函数体（可 `return`、可定义 helper）」，返回值结构化；
   并新增「脚本语言未初始化 → -32000」守卫（任务书未要求，§9.3-4/5）。
8. `script_filter` / `type_filter` / `named_only` 从「被迁移源静默忽略」变为按契约实现（PLAYBOOK §6.6）。
9. 门脚本的最小扩展（两个 manifest 合并 / `$ToolNames` 加 7 项 / `check_tool_groups.py --batch B2`），未新增或放松断言。
10. manifest 使用了任务书示例之外的键（照 B1 先例）。
11. doctest 里初始化脚本语言（`ScriptServer::init_languages()`）作为测试环境搭台，并在同一用例内先断言未初始化时的 `-32000`；
    `project_validate_script` 的用例在两种模式下都成立且声明式地先于本用例运行（§9.3-3、§9.5）。
12. 附加工件：`scripts/gen_b2_game_schema.py`（契约→C++ 的生成器，可复现且幂等）、
    `scripts/mcp010_b2_observation_evidence.ps1`（三 phase 证据脚本）、`scripts/mcp010_final_gates.cmd`（串行跑门）。
13. 撤回项：任务书「1e20 静默变 0」中 **0 这个数字**无法证实（实测 `INT64_MIN`，§8.1、§9.4）。

### blockers

1. **帧时钟组（3 个工具）无法在当前的同步工具执行模型内实现**：需要给 HTTP/JSON-RPC 层加「延迟应答」通道
   （连接 pending + 每帧续答回调 + handler 状态机）。提案已在 §6.3 给出；在此之前该组保持未实现、未注册。
2. 无其它阻塞：网络、依赖、端口、构建均正常；`9877` 上的用户编辑器全程未被触碰（pid 36392 前后一致）。

### next_step_recommendation

1. **先裁决 §6.3 的架构问题**（延迟应答通道），它就是 B2 剩余 3 个帧时钟工具、以及后续 `capture_frames`/录制回放类工具的前置。
2. 裁决后按 manifest 顺序继续 B2：`running_game_input`（4）→ `running_game_node_write`（1）→ `running_game_capture`（1）
   → `editor_playback`（2）→ `editor_input_simulation`（6）→ `editor_input_read`（1）。
   `running_game_set_node_property` 与 `editor_add_resource_to_node_property` 共用 `coerce_to_property_type`，
   本任务已把该函数的越界拒绝语义钉死（§8.2），B3 的节点写族可直接复用。
3. 编辑器侧输入族（`editor_simulate_*`）落地时请明确一条纪律写进契约侧文档：**它们驱动编辑器进程，不驱动游戏**；
   游戏可玩性判定必须走 `scope=game` 的工具（D56 的既有裁决）。
4. `approve/后续批次` 可考虑把「证据脚本」模式固化：本任务的 E3 链（§6）已经证明「在真实游戏进程里构造可观察状态变化」
   比 doctest 更能发现实现缺陷（§5.3 的属性过滤缺陷就是这么发现的）。
