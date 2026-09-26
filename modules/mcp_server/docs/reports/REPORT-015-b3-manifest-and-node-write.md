# REPORT-015 — B3/B4/B5 分类清单 + B3 首组（编辑器节点写族，含 2 个 fix-first）

> 任务书：`docs/tasks/TASK-015-b3-manifest-and-node-write.md`
> 通用规范：`docs/tasks/PLAYBOOK-group-port.md`
> 报告路径由任务书指定；本文件是本任务唯一的报告工件（未新建任何规范文档）。

## 0. status / commits

**status：完成**（第一部分 + 第二部分全部交付；五道门在绑定二进制上全绿）。

分支 `feature/mcp-server-module`，提交（均为英文信息，**未 push**）：

| sha | 一行说明 |
|---|---|
| `c07338d88b` | `mcp_server: classify the remaining 105 tools into B3/B4/B5 manifests` |
| `3d7155bb6b` | `mcp_server: port B3 editor_node_write (10 tools, 2 fix_implementation_first)` |
| `b8c3d66c64` | `mcp_server: make the TASK-015 evidence script's import and delete steps honest` |
| `41267a0062` | `mcp_server: check the B3/B4/B5 tools' name-derived channel and verb against the map` |

**门的二进制绑定**（PLAYBOOK §3 第 0 步）：

```
bin\godot.windows.editor.x86_64.console.exe --version
  4.8.dev.custom_build.41267a006        (exit 0)
git rev-parse --short HEAD
  41267a0062
```

`--version` 自报 `41267a006` == `41267a0062` 的前 9 位 → **本报告第 8 节的全部门输出与第 9 节的全部证据都来自这一次重绑后的运行**。
二进制 `sha256 = f57b14d75e8e3304bf993bc4f55dc4a1f20373c1895ce062b5472ec70779b3aa`（300 544 bytes）。
构建命令：`modules\mcp_server\scripts\build_local.cmd`（`tests=yes`，串行，不抑制输出，每次 exit 0）。

## 1. 关键发现：待移植数是 **105**，不是任务书写的 103

任务书 §0/§1.1 的算式是「契约 171 − 2 个 `unregister` − 已实现 66 = **103**」。
实测：**那 2 个 `unregister_until_implemented` 名字根本不在 171 条契约里**，所以不能再减一次。

```
SOURCE  contract entries                       = 171
SOURCE  implemented by the B1/B2 manifests    = 66
DERIVE  contract - implemented                 = 171 - 66 = 105
ASSERT  the 2 unregister_until_implemented names are absent from the contract: PASS
        (running_game_move_player_to_target_via_navigation, project_export_game)
ASSERT  B3 + B4 + B5 = 40 + 7 + 58 = 105 tool(s), each exactly once: PASS
```

映射侧的口径可以交叉验证：`tool-rename-map.json` 共 174 条，`disposition` 分布为
`rename 164 + fix_implementation_first 7 + unregister_until_implemented 2 + merge_into 1`；
`164 + 7 = 171` 恰好是契约规模，`174 − 2(unregister) − 1(merge_into) = 171`。
即：**契约 = 映射去掉 2 个 unregister 与 1 个 merge_into 之后的名字集合**，unregister 的 2 个名字只存在于映射中。

处置：**按真实集合分类 105 个，并把这条差异做成机器可校验的断言**，而不是照抄 103 硬编码。
`check_tool_groups.py --check-completeness` 会自己推导 `len(contract) - len(implemented)` 并打印算式，
同时**正面证明**那 2 个 unregister 名字不在契约里（若某天它们真的进了契约，推导出的数会变成 106，
这个检查会立刻失败，提示必须补上减法）。断言语句里直接写明了「TASK-015 §1 的 103 是重复扣减」。

> 这条不影响任何交付物：三个 manifest 覆盖的是**契约 − 已实现**这个双向差集，命令输出里
> `in_contract_and_not_implemented, both directions of the difference: PASS (missing=0, foreign=0)`
> 就是对任务书 §1.1 真正想要的那条不变式的证明。

## 2. 分类判据（B3 / B4 / B5）

判据按优先级如下，**每条都在 manifest 的 `notes` 里对具体组复述**：

1. **B5 = 子系统**（DESIGN-DETAIL §10 的 B5 名单）：animation / animation_tree / audio / theme /
   tilemap / particle / navigation / physics / scene_3d / shader / export / android / profiling，
   以及唯一的 game-scope 移动写 `running_game_move_player_to_target`。
   一个工具归 B5 的判据是**它驱动的子系统**在这份名单里，而不是它参数长什么样。
2. **B3 = 节点 / 脚本 / 资源 / 编辑器会话状态的写，以及观察这些写所产生的状态的读**。
   任务书 §1.4 把 B3 写成「节点/脚本/资源写操作」并列出 `setup_*`、`set_project_setting`、
   `add_autoload`、`create_script/edit_script/attach_script`、`add_scene_instance/add_raycast`、
   `add_mesh_instance/add_gridmap` 等；本报告沿用这份枚举，并补一条**读的归属规则**：
   一个只读工具若观察的正是某个 B3 写所产生的状态、且没有别的批次认领它，就进 B3（例如
   `editor_get_node_properties` / `editor_get_node_signals` / `editor_list_signal_connections`
   是节点写族的读回工具，PLAYBOOK §3 门② 的「跨工具活证据链」正是靠它们）。
   这就是 `editor_node_read`（6 个）与 `project_resource_uid_read`（2 个）出现在 B3 的原因。
3. **B4 = 测试与断言**：`editor_get_test_report`、`editor_analyze_screenshot_diff`、
   `running_game_assert_node_state`、`running_game_assert_screen_text`、
   `running_game_capture_signal_emissions`（读）与 `running_game_run_test_scenario`、
   `running_game_run_stress_test`（写）。写/读必须分组，是 GDR-18 的强制结果（同 B2 的截图族）。
4. **难以归类者逐条写明判据，不硬塞**。本批有 3 个：
   - `editor_execute_gdscript`（写）→ **B3**：它是脚本域操作（执行调用方脚本），归入
     `editor_script_write` 与 `editor_set_node_script`（attach_script）同组。
   - `project_convert_path_to_uid` / `project_convert_uid_to_path`（读）→ **B3**：资源身份读写，
     是 B3 资源域的只读半边；它们不能与写同组（mutating 不同），故单独成组 `project_resource_uid_read`。
   - 六个 shader 工具（`editor_set_shader_material` / `editor_set_shader_param` /
     `project_get_shader_params` / `project_read_shader` / `project_create_shader` / `project_edit_shader`）
     → **B5**：按「子系统优先」规则整体归 shader，而不是按「资源写」拆进 B3。
     这是判据 1 与判据 2 冲突时的一次取舍，理由：shader 的六个工具共享同一套依赖
     （Shader/ShaderMaterial/参数类型），拆开后两组都要各自实现一半。
   - `editor_bake_navigation_mesh` / `editor_set_navigation_layers` → **B5**（navigation 子系统），
     虽然 `bake_navigation_mesh` 是 `fix_implementation_first`。任务书 §1.4 的 B3 名单里没有它。
   - `editor_set_auto_dismiss_dialogs` 不是节点写，但它按任务书 §2 被点名放进首组，
     判据见 §5 的表与 manifest 的 `editor_node_write.notes`。

**分组轴**：`channel` + `scope` + `mutating`（一组只能一个值，GDR-18），组内 ≤10，
一组一个 `tools/<group>.{h,cpp}`，组间不共享文件。规模：

| batch | tools | groups | implemented=true |
|---|---|---|---|
| B3 | 40 | 12 | 1（`editor_node_write`） |
| B4 | 7 | 3 | 0 |
| B5 | 58 | 26 | 0 |
| 合计 | **105** | **41** | 1 |

B3 的 12 组：`editor_node_write`(10,*) / `editor_node_instantiate`(4) / `editor_node_batch_write`(2) /
`editor_control_layout_write`(1) / `editor_node_setup`(7) / `editor_script_write`(2) / `editor_node_read`(6) /
`project_script_write`(2) / `project_autoload_write`(2) / `project_setting_write`(1) /
`project_cross_scene_write`(1) / `project_resource_uid_read`(2)。

B4 的 3 组：`editor_testing_read`(2, 读) / `running_game_assertion`(3, 读) / `running_game_test_execution`(2, 写)。

B5 的 26 组按子系统命名（`editor_animation_write`、`editor_animation_tree_write`、`editor_audio_write`、
`editor_particle_write`、`editor_theme_write`、`editor_tilemap_write`、`editor_shader_write`、
`editor_physics_write`、`editor_navigation_write`、`editor_scene_3d_write`、各自的 `_read` 兄弟、
`project_shader_*`、`project_theme_*`、`project_export_read`、`project_android_read`、
`os_android_read`、`os_android_write`、`running_game_navigation_write`）。

**本批 6 个 `fix_implementation_first` 的落点**（任务书只要求本组处理 2 个）：

| 工具 | 组 | 本任务是否处理 |
|---|---|---|
| `editor_disconnect_signal` | `editor_node_write`（B3） | **是**（红→修，§6） |
| `editor_set_auto_dismiss_dialogs` | `editor_node_write`（B3） | **是**（红→修，§6） |
| `editor_get_test_report` | `editor_testing_read`（B4） | 否 |
| `editor_set_tilemap_cell` | `editor_tilemap_write`（B5） | 否 |
| `editor_set_tilemap_cells_in_rect` | `editor_tilemap_write`（B5） | 否 |
| `editor_bake_navigation_mesh` | `editor_navigation_write`（B5） | 否 |

## 3. 三个 manifest 的完备性证明（机器输出，exit 0）

命令（在 `modules/mcp_server/docs` 下）：

```
python scripts\check_tool_groups.py                    -> exit 0   TOOL-GROUPS CHECK PASS
python scripts\check_tool_groups.py --batch B2         -> exit 0   TOOL-GROUPS-B2 CHECK PASS
python scripts\check_tool_groups.py --batch B3         -> exit 0   TOOL-GROUPS-B3 CHECK PASS
python scripts\check_tool_groups.py --batch B4         -> exit 0   TOOL-GROUPS-B4 CHECK PASS
python scripts\check_tool_groups.py --batch B5         -> exit 0   TOOL-GROUPS-B5 CHECK PASS
python scripts\check_tool_groups.py --check-completeness -> exit 0 TOOL-GROUPS-COMPLETENESS CHECK PASS
```

`--check-completeness` 的真实输出：

```
SOURCE  contract entries                       = 171
SOURCE  implemented by the B1/B2 manifests    = 66
DERIVE  contract - implemented                 = 171 - 66 = 105
ASSERT  the 2 unregister_until_implemented names are absent from the contract: PASS (running_game_move_player_to_target_via_navigation, project_export_game)
ASSERT  they are therefore NOT subtracted a second time (the literal 103 of TASK-015 section 1 double counts them; the derived size is 105)
ASSERT  B3 + B4 + B5 = 40 + 7 + 58 = 105 tool(s), each exactly once: PASS
ASSERT  B3/B4/B5 pairwise disjoint: PASS
ASSERT  B3/B4/B5 disjoint from B1/B2 (66 tools): PASS
ASSERT  in_contract_and_not_implemented, both directions of the difference: PASS (missing=0, foreign=0)
ASSERT  every claimed name exists in the 171 entry contract: PASS
TOOL-GROUPS-COMPLETENESS CHECK PASS
```

B3 单批断言（节选，`--batch B3`）：

```
ASSERT  distinct tools in B3 manifest = 40
ASSERT  every tool appears exactly once: PASS (duplicates=0)
ASSERT  every name exists in the 171 entry contract: PASS
ASSERT  every group is one channel + one scope + one mutating value: PASS
ASSERT  channel and verb derived from every tool name agree with the rename map: PASS
ASSERT  every group carries a note: PASS
ASSERT  group sizes <= 10: PASS
ASSERT  implemented=true groups = 1, carrying 10 tool(s): editor_add_node, editor_delete_node,
        editor_duplicate_node, editor_rename_node, editor_reparent_node, editor_set_node_property,
        editor_set_node_groups, editor_connect_signal, editor_disconnect_signal, editor_set_auto_dismiss_dialogs
```

任务书 §1.2 要求 `channel`/`verb`/`scope`/`mutating` 与映射逐条一致。三个新 manifest 沿用
B1/B2 的结构（没有 `verb` 字段），所以检查器**从工具名反推** channel 与 verb
（与 `MCPToolRegistry::parse_tool_name` 同规则：最长 channel 前缀，余下第一段为 verb）再与映射比对，
从而在不新增字段的前提下闭合这条不变式。

## 4. `check_tool_groups.py` 的最小改动（B1/B2 未被削弱）

- 新增常量 `GROUPS_B3_JSON/B4_JSON/B5_JSON`、`BATCH_FILES`、两个新函数
  `main_batch(batch)` 与 `main_completeness()`；`main()` 与 `main_b2()` 的**函数体一行未动**。
- `__main__` 分支：新增 `--batch B3|B4|B5` 与 `--check-completeness`；B2 分支与默认分支保持原样。
  唯一的文本改动是给「未知 batch」加了一条新错误行，**B1 的 `sys.exit("usage: check_tool_groups.py [--batch B2]")`
  一字未改**（B1 有效运行不会走到它）。
- 未削弱证据：B1/B2 两条路径的输出**逐字节不变**（BYTES/SHA256 与 TASK-002/TASK-010 冻结值相同）：

| 命令 | BYTES | SHA256 |
|---|---|---|
| 无参数（B1） | 5682 | `0cfcac80f0d999fa7db713ae48f43febe96ae52e2c93633257eeed00ffdfbfac` |
| `--batch B2` | 11623 | `14eba00016c00bff914bb39aff9cfb5f01e375a43fa2ff5038d69bdedfc8b75d` |

## 5. 第二部分逐工具表（组 `editor_node_write`，10 个）

`C++ 落点` 一列全部是 `tools/editor_node_write.cpp` 的静态 `_tool_*`（`H` 表示
`tools/editor_node_write.h` 里为 doctest 可达而导出的节点级 helper）。
`差异` 一列写「一致」表示与迁移源可观察行为一致。

| new_name | 迁移源位置 | 可观察契约（参数 / 返回 / 错误） | 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `editor_add_node` | `node.rs:167-200` | `type`(必,非空) / `name`(选,默认=`type`) / `parent_path`(选,默认`.`) / `properties`(选,默认`{}`)；成功 `{node_path,name,type}`（路径相对编辑场景根，`name`/`type` 读回）；父节点不存在 `-32001`；未知类 / 非 Node 类 / 抽象类 `-32602`；`properties` 里不存在的属性 `-32001` 且销毁半成品节点 | `_tool_add_node` + `H:instantiate_node_of_type` `H:apply_node_properties` | **键集一致**；`name`/`type` 由回显改为读回（迁移源回显请求，会把被引擎消毒过的名字当成真名）；`properties` 增加「先查属性表」并支持 `{x,y}` 组件写法；失败时不留孤儿 |
| `editor_delete_node` | `node.rs:202-209` | `path`(必,非空)；成功 `{deleted,path,deferred:true}`；节点不存在 `-32001`；编辑场景根 `-32000` | `_tool_delete_node` | `deleted` 是 `is_queued_for_deletion()` 的**实测值**并显式声明 `deferred`（`queue_free` 是延迟释放）；`path` 改为解析后的相对路径；**拒删编辑场景根**（迁移源会照删） |
| `editor_duplicate_node` | `node.rs:269-288` | `path`(必) / `new_name`(选，默认=**`path` 字符串**，迁移源怪癖)；成功 `{node_path,name,duplicated:true}`；节点不存在 `-32001`；无父节点 `-32603` | `_tool_duplicate_node` | `node_path`/`name` 读回；`new_name` 默认值怪癖**保留**（PLAYBOOK §6.8），但答案报出引擎实际采用的名字 |
| `editor_rename_node` | `node.rs:211-219` | `path`(必) / `name`(必,非空)；成功 `{renamed,new_name,node_path}`；被消毒时追加 `requested_name`+`name_sanitized`；节点不存在 `-32001` | `_tool_rename_node` + `H:rename_node_to` | `new_name` 改为**引擎实际应用的名字**。`Node::set_name` 走 `String::validate_node_name`（`scene/main/node.cpp:1450`）是**消毒而非失败**，迁移源把请求串当结果回显 |
| `editor_reparent_node` | `node.rs:291-316`（旧 `move_node`） | `path`(必) / `new_parent`(必) / `new_name`(选)；成功 `{node_path,moved:true}`；节点/父不存在 `-32001`；编辑根或「移到自己后代下」`-32602` | `_tool_reparent_node` | 键集一致；新增两条前置拒绝（迁移源不检查，会把节点挂到自己后代下或搬走整棵打开的场景）；`node_path` 为移动后的实测路径 |
| `editor_set_node_property` | `node.rs:221-230`（旧 `update_property`） | `path`(必) / `property`(必,非空) / `value`(必，任意 JSON 类型，`null` 也算给值)；成功 `{node_path,property,old_value,new_value}`（TASK-014 形状，`new_value` 是 `Object::set()` 之后**读回**的值）；未知属性 `-32001`；节点不存在 `-32001`；类型不可转换 `-32602` | `_tool_set_node_property` + `H:set_node_property_on`（复用 `running_game_node_write.h` 的 `write_node_property`） | **返回形状改为 TASK-014 形状**（任务书 §2 指定）：迁移源是恒真常量 `{"updated":true}`，与「先查属性表再写」不匹配；`node_path` 为相对路径；未知属性不再静默成功 |
| `editor_set_node_groups` | `node.rs:501-561` | `node_path`(必) / `groups`(必，字符串数组)；成功 `{node_path,groups,added,removed}`，`_` 前缀内部组双向不可见；非数组/非字符串元素 `-32602`；节点不存在 `-32001` | `_tool_set_node_groups` | 非字符串元素由静默丢弃改为 `-32602`；`removed` 排序、`added` 去重（迁移源的 `removed` 来自 `Node::get_groups()` 的 `HashSet` 迭代序，不确定，PLAYBOOK §6.8）；`groups` 仍回显调用方目标列表 |
| `editor_connect_signal` | `node.rs:319-341` | `source_path`(必) / `signal`(必,非空) / `method`(必,非空) / `target_path`(选，缺省=编辑场景根)；成功 `{connected,signal,source,target}`（两端都是相对路径），已连接时加 `already_connected:true`；信号不存在 `-32001`；`connect()` 被引擎拒绝 `-32000` | `_tool_connect_signal` + `H:connect_signal_on` | 迁移源忽略 `connect()` 的 `Error`，未知信号/重复连接都回 `{"connected":true}`；本实现先解析两端再连、信号不存在 `-32001`、重复连接是**幂等成功**并说明；始终给出 `target`（迁移源在缺省 root 时省略） |
| `editor_disconnect_signal` | `node.rs:344-358` | `source_path`/`signal`/`method`(必) / `target_path`(选，缺省=编辑场景根)；成功 `{disconnected,signal,source,target}`；目标连接不存在 / 信号不存在 `-32001` | `_tool_disconnect_signal` + `H:disconnect_signal_from` | **fix_implementation_first #1**，见 §6.1 |
| `editor_set_auto_dismiss_dialogs` | `editor.rs:613-625`（旧 `set_auto_dismiss`） | `enabled`(必，布尔)；**恒为 `-32000 Not implemented` + `data.suggestion`**；缺参/类型错 `-32602` | `_tool_set_auto_dismiss_dialogs` | **fix_implementation_first #2**，见 §6.2 |

全部 10 个：`channel=editor`、`scope=editor`、`mutating=true`，经 `MCPToolBuilder` 注册，
`description`/`inputSchema` 逐字取自 `docs/tools_list.renamed.json`（门①逐字 True），
游戏进程 9889 **不注册**、调用 `-32601`。

## 6. 两个 fix-first 的红→修全程

过程（严格 TDD，红先绿后）：

1. 先把两个工具**照迁移源语义 1:1 移植**（`editor_node_write.cpp` 里带 `RED` 注释的那一版），
   连同断言「正确语义」的 doctest 一起构建并运行 → **红**；
2. 再改实现 → 重建 → 同一批测试 **绿**。

### 6.1 `editor_disconnect_signal`：忽略 `target_path` 却报成功

**迁移源缺陷**（`node.rs:344-358`）：schema 收 `target_path`（可选），函数体**从不读它**，
`Callable` 固定用场景根构造（`node.rs:355`），且忽略 `disconnect()` 的结果（`node.rs:356`），
最后无条件返回 `{"disconnected": true}`。后果：可能断开的**不是调用方指定的那条连接**，或者
根本没断开，却报成功。

**红（二进制 `047455e39`，修复前）** —— `bin\...console.exe --headless --test --test-case="[MCPServer]*"`，**exit 1**：

```
.\modules/mcp_server/tests/test_mcp_server.h(7580):
TEST CASE:  [MCPServer] editor_disconnect_signal disconnects the named connection, not the scene root

.\modules/mcp_server/tests/test_mcp_server.h(7598): ERROR: CHECK_FALSE( source->is_connected(StringName("renamed"), wanted) ) is NOT correct!
  values: CHECK_FALSE( true )

.\modules/mcp_server/tests/test_mcp_server.h(7603): ERROR: CHECK_FALSE( MCPTools::disconnect_signal_from(source, StringName("renamed"), target, "queue_free", error) ) is NOT correct!
  values: CHECK_FALSE( true )

.\modules/mcp_server/tests/test_mcp_server.h(7604): ERROR: CHECK( error.code == -32001 ) is NOT correct!
  values: CHECK( 0 == -32001 )
...
[doctest] test cases:  130 |  128 passed |  2 failed | 1429 skipped
[doctest] assertions: 4383 | 4369 passed | 14 failed |
[doctest] Status: FAILURE!
```

同一份输出里还有引擎自己留下的物证，说明那版真的去用「场景根这条路」断了一条不存在的连接：

```
ERROR: Attempt to disconnect a nonexistent connection from 'Source:<Node#280515052467>'. Signal: 'renamed', callable: 'Node::queue_free'.
   at: Object::_disconnect (core\object\object.cpp:1713)
ERROR: Disconnecting nonexistent signal 'no_such_signal_xyz' in 'Source:<Node#280515052467>'.
   at: Object::_disconnect (core\object\object.cpp:1711)
```

**最终语义**（`MCPTools::disconnect_signal_from`）：

1. `target` 空 → `-32001`；
2. `source` 没有该信号 → `-32001`（`has_signal` 先问，避免 `Object::_disconnect` 的 ERR_FAIL 噪声）；
3. `Callable(target, method)` **不是**已连接的那条 → `-32001` + `data.suggestion`；
4. 只有确认存在才调 `disconnect()`。

工具层：`target_path` 缺省 = 编辑场景根（保留迁移源唯一的默认规则），两端都先解析成真实 Node，
答案给出两端相对路径。

**绿（二进制 `41267a006`）**：同一测试通过，且门②实测（§9）为
`fix_01 connect=0 / fix_02 first_disconnect=0（target=Renamed）/ fix_03 second_disconnect=-32001`。

### 6.2 `editor_set_auto_dismiss_dialogs`：只写无人读取的 static = 纯谎报

**迁移源缺陷**（`editor.rs:31 / 613-625`）：`static AUTO_DISMISS: AtomicBool`，全仓（addon 内）只有
「声明」和「store」两处引用，**没有任何读取点**；工具却返回
`{"auto_dismiss": <enabled>, "message": "..."}`。调用后编辑器行为零变化。

**修法选择与证据**（PLAYBOOK §6.6：真实现，或诚实 `-32000`，禁止假成功）——选**诚实 `-32000`**：

- 引擎**没有**进程级「自动关闭对话框」开关。`grep` 全 `editor/**`：`set_hide_on_ok` 共 29 处，
  全部是**每个对话框各自硬编码**（`editor/gui/create_dialog.cpp:1109`、`editor/export/project_export.cpp:2151`、
  `editor/scene/connections_dialog.cpp:700` …），没有一处从设置或单例读；
- `EditorSettings` 里唯一的对话框全局项是
  `interface/editor/appearance/accept_dialog_cancel_ok_buttons`（`editor/settings/editor_settings.cpp:559`），
  它决定的是按钮顺序，不是「自动关闭」；
- 内置模块本身不创建任何对话框，所以也没有「模块自己的弹窗」可以关。
- 因此「真的实现」在本引擎里无处落脚；把 `enabled` 存进任何进程内变量都是**第二种假成功**。
  最终返回 `-32000 Not implemented: editor_set_auto_dismiss_dialogs`，`data.suggestion` 明确给出
  真正的旋钮（`AcceptDialog.hide_on_ok` 的逐对话框语义、`accept_dialog_cancel_ok_buttons` 的顺序语义）
  与可达路径（`editor_execute_gdscript` 设置某个具名对话框）。
- 参数契约仍在拒答之前校验，所以畸形调用是 `-32602` 而不是误导性的「未实现」。

**红**（同一份 exit 1 输出）：

```
.\modules/mcp_server/tests/test_mcp_server.h(7636):
TEST CASE:  [MCPServer] editor_set_auto_dismiss_dialogs never reports a success it did not perform

.\modules/mcp_server/tests/test_mcp_server.h(7648): ERROR: CHECK( result.get_type() == Variant::NIL ) is NOT correct!
  values: CHECK( 27 == 0 )                      # 27 = Variant::DICTIONARY：红版回了一个成功体
.\modules/mcp_server/tests/test_mcp_server.h(7649): ERROR: CHECK( error.code == -32000 ) is NOT correct!
  values: CHECK( 0 == -32000 )
.\modules/mcp_server/tests/test_mcp_server.h(7650): ERROR: CHECK( error.message.contains("Not implemented") ) is NOT correct!
  values: CHECK( false )
.\modules/mcp_server/tests/test_mcp_server.h(7651): ERROR: CHECK( error.message.contains("editor_set_auto_dismiss_dialogs") ) is NOT correct!
  values: CHECK( false )
```

**绿**：130/130 用例、4383/4383 断言、exit 0；门② 实测
`honest_01_set_auto_dismiss = -32000（message="Not implemented: editor_set_auto_dismiss_dialogs"，result 为 null）`、
`honest_02_set_auto_dismiss_disabled = -32000`（两种入参同一拒答）。

> 该工具**没有「成功」证据类**（任务书要求的「哪一类不可构造必须显式声明原因」）：
> 原因是本引擎不存在这个能力，成功类**不可能被诚实地构造**；它的「底层失败」类就由上面这条
> `-32000` 承担。这是本组唯一的此类声明。

## 7. 节点写族的「先查属性表」形状与 C# 字段边界

**形状**：`editor_set_node_property` 与 `editor_add_node` 的 `properties` 都调用
`MCPTools::write_node_property`（`tools/running_game_node_write.h` 声明、TASK-014 拆分出来的**唯一**一份节点属性写），
因此编辑器侧与游戏侧共享同一条规则：**先问对象有没有这个属性**，再做 JSON→声明类型的转换，再写，
再把值读回来。未知属性一律 `-32001` + 建议，永不产出成功形状。门②实测：

```
fail_set_node_property_unknown  -> {"error":{"code":-32001,"message":"Property 'not_a_property_xyz' on node '<...>'  not found","data":{"suggestion":"Use running_game_get_node_properties to list the properties this node has"}}}
succ_02_set_node_property       -> {"new_value":{"x":5.0,"y":6.0},"node_path":"Added","old_value":{"x":1.0,"y":2.0},"property":"position"}
```

**C# 边界（PLAYBOOK §3 事实②）**：非 `[Export]` 的 `public` 字段**不在** `get_property_list()` 里，
但 `Object::get/set` 仍能按名读写。共享 helper `_object_has_property` 的判定是**两步**：

1. `p_object->get(name)` 的类型不是 NIL → 认为存在（**当前值这一票**）；
2. 否则遍历 `get_property_list()` 找声明（**声明这一票**）。

由此本组对 C# 普通字段的实际行为是：**有值时显式允许（可读回、可写、答案给 old/new），值为 null/nil
时显式拒绝 `-32001`**。这是 TASK-014 D-1 已确立并写进该 helper 注释的规则，本组**沿用而非新增**。
判定依据本身是**推断**（读 helper 源码 + TASK-014 报告记载的实测：全量列举 29 键不含 `PlainField`，
但按名 `set` 成功 `4242→7`；本任务的非 mono 二进制不含 C# 运行时，无法当场重测），
故在此显式标注为「推断」而非「证据」，留待 M5/mono 阶段用一个 C# 工程实测收口。
本组自身可测的部分已由 doctest 钉住：未知属性 → `-32001`（§9 门②同款断言在 doctest 里）。

## 8. 五道门（全部在 `--version == HEAD == 41267a006` 的二进制上）

| 门 | 命令 | 结果 | 退出码 |
|---|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group editor_node_write` | 3/3 PASS | **0** |
| ② 三类证据 + 活证据链 | `mcp015_editor_node_write_evidence.ps1` | 43/43 PASS | **0** |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | 130/130 用例、4383/4383 断言、0 failed | **0** |
| ④ 全引擎回归 | `--headless --test` | 1556/1556 用例、428665/428665 断言、0 failed、3 skipped | **0** |
| ⑤ 批量收口 | `accept_m1.ps1` ×2 | 22/22 ×2，两次 PASS 清单**逐条相同** | **0 / 0** |

基线对照（只增不减）：
- ③ 上一次（REPORT-014）为 124/124 · 3653；本批 +6 用例（本组 6 个 `TEST_CASE`）、+730 断言；
- ④ 上一次为 1550/1550 · 427935；本批 +6 用例、+730 断言；
- ⑤ 22/22，`implemented tools = 59 (editor endpoint) / 40 (game endpoint); contract = 171`。

门①真实片段（`mcp015-gate1.txt`）：

```
scope       : editor-only=36 game-only=17 both/shared=23
editor set  : 59 tool(s)
game set    : 40 tool(s)
[PASS] editor_9888_contract_subset
       editor port=9888 tools=59 order=... > editor_add_node > editor_delete_node > editor_duplicate_node >
       editor_rename_node > editor_reparent_node > editor_set_node_property > editor_set_node_groups >
       editor_connect_signal > editor_disconnect_signal > editor_set_auto_dismiss_dialogs |
       editor_add_node: name=True description=True inputSchema=True | ... （10 条全 True）
[PASS] game_9889_contract_subset
       editor_add_node: correctly absent on the game endpoint | ...（10 条全 absent）
[PASS] guard_user_port_9877   pid_before=36392 pid_after=36392
3/3 checks passed
```

门⑤真实片段（两次运行 `Compare-Object` 结果为空）：

```
run1 PASS lines: 22
run2 PASS lines: 22
PASS-SET-IDENTICAL
22/22 cases passed
implemented tools = 59 (editor endpoint) / 40 (game endpoint); contract = 171; known_deviation = per-batch verbatim gate only
```

## 9. 门② 三类证据与活证据链（真实请求/响应，端口 9888 / 9889）

采集纪律：请求体一律 `ConvertTo-Json` 落盘，响应体一律 `curl.exe -s --max-time … -o <file>`，
每次打印 `bytes` 与 `sha256`（例：`succ_01_add_node` 响应 137 bytes、
`sha256=0fdbbe682539a904e265d25dafe3161d35f77bdbcada699c9a4a09d0aad5f79f`；
`succ_02_set_node_property` 196 bytes / `b0c3d5a957298faa4846898f316601cd95e09a260d5534cb668477650b2f89dc`；
`honest_01_set_auto_dismiss` 552 bytes / `87b441cbeb47258c5f71572308174192cf82567971eb1d1e821a4e7ad2a53e67`；
完整清单见脚本输出）。**请求体没有进过命令行，响应体没有进过管道或 `Out-File`。**

### 9.1 成功类（9 个可构造的工具全给出）

```
succ_01_add_node           req {"type":"Node2D","name":"Added","parent_path":".","properties":{"position":{"x":1,"y":2}}}
                           resp {"name":"Added","node_path":"Added","type":"Node2D"}
succ_02_set_node_property  req {"path":"Added","property":"position","value":{"x":5,"y":6}}
                           resp {"new_value":{"x":5.0,"y":6.0},"node_path":"Added","old_value":{"x":1.0,"y":2.0},"property":"position"}
succ_03_rename_node        req {"path":"Added","name":"Renamed"}
                           resp {"new_name":"Renamed","node_path":"Renamed","renamed":true}
succ_04_duplicate_node     req {"path":"Renamed","new_name":"Copy"}
                           resp {"duplicated":true,"name":"Copy","node_path":"Copy"}
succ_05_set_node_groups    req {"node_path":"Renamed","groups":["enemies","targets"]}
                           resp {"added":["enemies","targets"],"groups":["enemies","targets"],"node_path":"Renamed","removed":[]}
succ_06_connect_signal     req {"source_path":"Main","signal":"ready","method":"queue_free","target_path":"Renamed"}
                           resp {"connected":true,"signal":"ready","source":".","target":"Renamed"}
succ_07_disconnect_signal  req （同上）
                           resp {"disconnected":true,"signal":"ready","source":".","target":"Renamed"}
succ_08_reparent_node      req {"path":"Copy","new_parent":"World"}
                           resp {"moved":true,"node_path":"World/Copy"}
succ_09_delete_node        req {"path":"World/Copy"}
                           resp {"deferred":true,"deleted":true,"path":"World/Copy"}
```

`editor_set_auto_dismiss_dialogs` **没有成功类**（声明见 §6.2 末尾）。

### 9.2 缺参类（10/10，全部 `-32602` 且 `result` 为 null）

```
miss_add_node            {"type" 缺失}          -> -32602 Missing required parameter: type
miss_delete_node         {"path" 缺失}          -> -32602 Missing required parameter: path
miss_duplicate_node      {"path" 缺失}          -> -32602 Missing required parameter: path
miss_rename_node         {"path":"Renamed"}     -> -32602 Missing required parameter: name
miss_reparent_node       {"path":"Renamed"}     -> -32602 Missing required parameter: new_parent
miss_set_node_property   {path,property 有}     -> -32602 Missing required parameter 'value'
miss_set_node_groups     {"node_path":...}      -> -32602 Missing required parameter 'groups'
miss_connect_signal      {"source_path":...}    -> -32602 Missing required parameter: signal
miss_disconnect_signal   {"source_path":...}    -> -32602 Missing required parameter: signal
miss_set_auto_dismiss    {}                     -> -32602 Missing required parameter 'enabled'
```

### 9.3 底层失败类（11 组，覆盖每个有该类可构造的工具）

```
fail_add_node_unknown_type        NoSuchMcpNodeClass       -> -32602 Cannot instantiate node type 'NoSuchMcpNodeClass': no such class
fail_add_node_not_a_node          Resource                -> -32602 Type 'Resource' is not a Node subclass
fail_delete_node_missing          NoSuchNode              -> -32001 Node 'NoSuchNode' not found (+ suggestion)
fail_duplicate_node_missing       NoSuchNode              -> -32001 Node 'NoSuchNode' not found (+ suggestion)
fail_rename_node_missing          NoSuchNode              -> -32001 Node 'NoSuchNode' not found (+ suggestion)
fail_reparent_node_missing        NoSuchParent            -> -32001 Parent 'NoSuchParent' not found (+ suggestion)
fail_reparent_into_descendant     Child -> Child           -> -32602 Cannot move node 'Child' under its own descendant 'Child'
fail_set_node_property_unknown    not_a_property_xyz      -> -32001 Property 'not_a_property_xyz' on node '<...>' not found (+ suggestion)
fail_set_node_groups_missing_node NoSuchNode              -> -32001 Node 'NoSuchNode' not found (+ suggestion)
fail_connect_signal_unknown_signal no_such_signal_xyz     -> -32001 Signal 'no_such_signal_xyz' on node 'Main' not found (+ suggestion)
fail_disconnect_signal_not_connected（连接不存在）        -> -32001 Connection from signal 'ready' to method 'queue_free' not found (+ suggestion)
```

### 9.4 跨工具活证据链（本组最重要的一条）

链：`editor_open_scene` →（`editor_get_scene_tree` 读回）→ `editor_add_node` →（读回）→
`editor_set_node_property` → `editor_rename_node` → `editor_duplicate_node` →
`editor_set_node_groups` → `editor_connect_signal` → `editor_disconnect_signal` →
`editor_reparent_node` →（读回）→ `editor_delete_node` →（读回）。

每一步的状态变化都由**另一个工具**（B1 组的只读 `editor_get_scene_tree`）观察，实测路径集合：

```
chain_01_tree_before      [Main, Main/Child, Main/World]
chain_02_tree_after_add   [Main, Main/Child, Main/World, Main/Added]
chain_03_tree_after_writes[Main, Main/Child, Main/World, Main/World/Copy, Main/Renamed]
chain_04_tree_after_delete[Main, Main/Child, Main/World, Main/Renamed]
```

其中 `chain_03` 同时证明了三件事：重命名生效（`Added` 消失、`Renamed` 出现）、复制生效（`Copy` 出现）、
搬父生效（`Copy` 变成 `World/Copy`）；`chain_04` 证明删除生效（`World/Copy` 消失）而 `Renamed` 仍在
（删除没有误伤）。这正是「靠活链抓真缺陷」的那一类证据。

### 9.5 fix-first 的线上复现

```
fix_01_connect_for_disconnect   -> {"connected":true,"signal":"ready","source":".","target":"Renamed"}
fix_02_disconnect_named_target  -> {"disconnected":true,"signal":"ready","source":".","target":"Renamed"}
fix_03_disconnect_again         -> -32001 Connection from signal 'ready' to method 'queue_free' not found
```

第二次断同一条连接是 `-32001` 而不是又一次「成功」——这正是红版做不到的（红版恒返回成功）。

### 9.6 进程维度

```
scope_editor_tools_list : 9888 的 tools/list 含全部 10 个（missing=0）
scope_game_tools_list   : 9889 的 tools/list 含 0 个（leaked=[]）
scope_game_call_add_node: 9889 tools/call editor_add_node -> {"error":{"code":-32601,"message":"Method not found: editor_add_node"}}
```

## 10. 本组脚本/文件 sha256（红线/门相关）

| 文件 | bytes | sha256 |
|---|---|---|
| `docs/tool-groups-b3.json` | 8537 | `25a2d784d982bd6e00aa42c6cf54f315212acc2f3a7fa20b78d183834badb2cc` |
| `docs/tool-groups-b4.json` | 3063 | `21a5dd5e48a91fe1a9cca4047a429e263d34606f565794ba2a48aaf695422f26` |
| `docs/tool-groups-b5.json` | 12031 | `09dc64dab5674f29a9b488bab1897957d8c9e9bf971497ea209b2abd6fd0b167` |
| `docs/scripts/check_tool_groups.py` | 28886 | `3d72fddec1f51dded833d732c56419165694d5a954bb1ade777f0b4b8bdc2dfc` |
| `tools/editor_node_write.h` | 8228 | `42c04b4f454b7c1dad3c2fc91c5543da64757081b6a8ddceade3bb38d381df69` |
| `tools/editor_node_write.cpp` | 52264 | `cabe9b1d6df8b22c97e2c9c4e79a7d9dea71bb9faf06c7a9d9e86fdc38322cea` |
| `tools/registration.cpp` | 5558 | `433fe1d82c5bddfe8c8b8a97a29d6be947c61cfe78f47064d370d3e15838fec5` |
| `tests/test_mcp_server.h` | 340442 | `1c4c59ca99ed0542cbebdb176fcf725cfb3b1b00941770ee7fc5b45698c6e250` |
| `scripts/check_contract_subset.ps1` | 26422 | `3a66b9cd08576b1cd3ec4b20fbba4c418367779b556142852e53b47491f467c8` |
| `scripts/accept_m1.ps1` | 64392 | `47daddf01848539da52db590b1829e8cf686c94e0dc0d63523f977c050617765` |
| `scripts/mcp015_editor_node_write_evidence.ps1` | 32074 | `f0ae529cd3a5fcbd5a0ef456ed580dead9988471acec77523e20dc448ee312f9` |
| `bin/godot.windows.editor.x86_64.console.exe`（**门所绑定的那次构建**，`--version` = `4.8.dev.custom_build.41267a006`） | 300544 | `f57b14d75e8e3304bf993bc4f55dc4a1f20373c1895ce062b5472ec70779b3aa` |

未触碰契约 / 映射 / 契约生成器：`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、
`docs/tools_list.*`、`scripts/gen_renamed_contract.py`、`scripts/gen_b2_game_schema.py` 全部零改动
（`git status` 里没有任何这些文件）。

## 11. deviations（与任务书/PLAYBOOK 的偏离，逐条）

1. **待移植数 105 而非 103**（§1）。任务书 §0/§1.1 的算式重复扣减了 2 个 unregister 名字；
   已按真实集合分类 105 并把这条差异做成断言，未按字面值硬编码。**这是对任务书文本的偏离，不是对目标的偏离。**
2. **`editor_set_node_property` 的返回键集改为 TASK-014 形状**（去掉了恒真常量 `updated`）。
   依据：任务书 §2「节点写族的行为基准：TASK-014 已把 `running_game_set_node_property` 确立为
   『先查属性表再写』的形状；编辑器侧同类工具应照此办理」。
3. **`editor_delete_node` 拒绝删除编辑场景根**（`-32000`）。迁移源会 `queue_free()` 掉整棵打开的场景。
   这是「工具真的能用」标准下的安全前置条件；已在此显式记录。
4. **`editor_delete_node` 报实测 `deleted` 并加 `deferred: true`**：`queue_free()` 是延迟释放，
   立刻回 `deleted:true` 是不诚实的承诺。
5. **`editor_rename_node` 报引擎实际采用的 `new_name`**，被消毒时追加 `requested_name`/`name_sanitized`。
6. **`editor_reparent_node` 新增两条 `-32602` 前置拒绝**（移到自己后代下、移动编辑根）。
7. **`editor_connect_signal` 把未知信号改成 `-32001`、重复连接改成幂等成功并标 `already_connected`**，
   且始终返回解析后的 `target`。
8. **`editor_set_node_groups` 对非字符串元素改 `-32602`，`removed` 排序、`added` 去重**（确定性）。
9. **`editor_add_node` 的 `properties` 增加「先查属性表」**，未知属性 `-32001` 且销毁半成品节点，
   不留孤儿；`name`/`type` 改为读回。
10. **`_find_node` 在 `editor_node_write.cpp` 里复制了一份**（与 `editor_write_scene_editor.cpp` 的
    文件私有同名函数文本一致）。PLAYBOOK §2.4 明确允许「共享一份定义或复制语义」二选一，
    而一个组不得调用另一个组的文件私有 helper；把它提升到 `tools/tool_helpers.*` 需要改已验收
    B1 批次的组文件，超出本任务范围。**建议作为后续清理项**（TASK-009/TASK-011 已有先例）。
11. **未知属性的错误消息里节点名用的是引擎路径**（编辑进程里形如
    `/root/@EditorNode@20539/…/Added`，含每次运行不同的节点 id）。原因是这条拒答由共享的
    `write_node_property` 产生（它的 `node_path` 语义是绝对路径）。功能正确（`-32001` + 建议），
    但消息**非确定**且冗长。**已知瑕疵，建议后续把该 helper 的节点命名参数化**；本任务记录而不改，
    因为改动会波及已验收的 B2 `running_game_set_node_property` 的线上消息。
12. **`check_tool_groups.py` 的「未知 batch」错误行是新增文本**；B1 的无参数分支
    `sys.exit("usage: check_tool_groups.py [--batch B2]")` 一字未改（§4），B1/B2 输出哈希不变。
13. **`check_contract_subset.ps1` 现在合并 5 个 manifest**（B1+B2+B3+B4+B5）来查组名与
    「implemented 并集」。断言形式与强度不变：实况 `tools/list` 必须**恰好等于**该进程的已实现集合，
    多一个（未实现却注册）少一个（已实现却缺席）都失败。
14. **`accept_m1.ps1` 的 `$ToolNames` 追加了 10 个 editor-scope 名字**（脚本自述的既有扩展点）；
    `$EditorToolNames`/`$GameToolNames` 由映射推导，既有断言全部未改，22/22 两次一致。
15. **证据脚本的 `--import` 传 `--mcp-port=0`**：否则 import 会去尝试绑定 9877（用户编辑器），
    虽然绑定失败无害，但更干净的做法是不尝试。同时 `--import` 的退出码改为校验
    `$LASTEXITCODE`（`Start-Process` 对象的 `ExitCode` 在本机返回空，前两次运行因此误报失败——
    这是**已实测并修正**的一处工具链陷阱，PLAYBOOK §3 记的 BOM/退出码风险同源）。
16. **门的运行提交点与交接时的二进制绑定**：五道门跑在 `41267a0062`（二进制 `--version` 自报
    `41267a006`，一致），§8/§9 的全部输出都来自那一次运行；本报告自身是一个「仅新增报告」的提交，
    发生在门之后，所以仓库最终 HEAD 会比门所绑定的提交多一个提交（与 REPORT-014 的处理相同）。
    为了让**交接时**也满足 PLAYBOOK §3 第 0 步的机械校验（`--version` hash 前缀 == `git rev-parse --short HEAD`），
    报告提交之后又**原样重建了一次**：源码与门所测的完全一致，只有编译进 `version.h` 的 revision 串
    从 `41267a006` 变成最终 HEAD，因此 §10 里那个二进制 sha256 是**门所绑定构建**的哈希，
    交接时磁盘上的二进制哈希与之不同（同尺寸 300544 bytes），这是预期行为，已在此显式说明。

## 12. blockers

无。

- 网络/依赖：本任务不需要网络，未安装任何依赖，未访问 `100.105.152.101:18080`。
- 端口：全程只用 9888/9889；9877 只做「pid 前后一致」观测（`36392 → 36392`）。
  门①的门脚本自带该守卫并 PASS；门②脚本同样自带并 PASS。
- 工作树：`git status` 只剩四个**既有**未跟踪物（`.graphifyignore`、`build-m0.cmd`、
  `graphify-out/`、`install-deps-m0.cmd`），本任务未新增任何未跟踪残留。

## 13. next_step_recommendation

1. **B3 第二组**：`editor_node_read`（6 个）是 `editor_node_write` 的天然读回半边，
   先做它可以让后续所有 B3 组的活证据链都有一段现成的读回工具；
   或者按依赖顺序做 `editor_node_instantiate`（`add_scene_instance` / `add_raycast` /
   `add_mesh_instance` / `add_gridmap`），它复用本组已建立的 node-add 路径。
2. **在 B3 扩到第 3 组之前把 `_find_node` 提升进 `tools/tool_helpers.*`**（§11.10），
   否则每次编辑器写组都会再复制一份「节点路径解析」语义。
3. **把 B4 的 `editor_testing_read` 两个 fix-first（`editor_get_test_report`）与
   B5 的 tilemap 数据破坏族（`editor_set_tilemap_cell` / `editor_set_tilemap_cells_in_rect`）
   当成独立的「先红后修」任务**，不要与普通组混做——本任务已验证这条流程（红版 1:1 移植 →
   红测试 → 修 → 绿）在 Live 端同样可复现。
4. **C# 普通字段边界需要在 mono 二进制上实测收口**（§7）：一个 `[Export]` 与一个非 `[Export]`
   的 `public` 字段各一个，走 `editor_set_node_property`，把「有值时允许 / nil 时拒绝」这条
   推断变成证据。M3 的 mono 构建经验已在 REPORT-014。
5. **决策层登记建议（我无权改 `DECISIONS.md`，它在 `modules/mcp_server/**` 之外）**：
   - D-?: 「待移植集合以 `contract − implemented` 的实时推导为准，任务书里的字面数（103）不作为断言常量」
     —— 本任务 §1 的偏离依据。
   - D-?: 「B5 的归属按子系统优先于按资源形态」—— §2 判据 4 里 shader 六个工具的取舍。
   - D-?: 「编辑器侧节点属性写复用 `MCPTools::write_node_property`，跨组 include 一个已发布的头文件
     优于复制语义」—— 与 §11.10 里 `_find_node` 的处置相反，两者并列记录，便于后续统一清理决策。