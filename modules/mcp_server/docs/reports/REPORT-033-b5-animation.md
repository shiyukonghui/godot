# REPORT-033 · B5 批次 1：动画族 14 个工具 + M4e 三项收尾

| 项 | 值 |
| --- | --- |
| 任务书 | `modules/mcp_server/docs/tasks/TASK-033-b5-animation.md`（B5 batch 1） |
| 工作流 | `modules/mcp_server/docs/tasks/PLAYBOOK-group-port.md`（八步 + 六道门） |
| 分支 / HEAD | `feature/mcp-server-module` / `4e71becf2d62a4fcfdce232c5c0340b774316ada` |
| `--version` | `4.8.dev.custom_build.972729bc7`（与 HEAD 短哈希一致，验证于最后一次构建后） |
| 构建 | `modules\mcp_server\scripts\build_local.cmd -Force`（`tests=yes`）exit 0，日志 `%TEMP%\mcp033_green_build.log` |
| B5 进度 | **14 / 58**（批次 1 的三个组全部 `implemented=true`） |
| 提交 | `613df1eda9` A1 门⑥覆盖 · `36510a32b7` A2/A3 措辞 · `c5bc94ac5d` Quaternion · `7e9d00ddf2` B5 批次 1 · `4e71becf2d` 测试 |

**结论有效性（D86）**：本报告所有实测结论均在提交 `4e71becf2d` / 引擎 `4.8.dev.custom_build.972729bc7` 上测得；
引用他人结论时一律标注其测量提交。被引用的 `REPORT-AUDIT-M4e` 测于 `4.8.dev.custom_build.9f2b2e484`（更早的树），
其一条因果判断在本轮被证伪（§3.3 勘误）；凡复用本文数字前请先在当前 HEAD 复测。

---

## 1. 范围与结果

三件事一起交付：

1. **范围①：M4e 三项收尾**（D-M4e-1 门⑥五个绕过拼写 / D-M4e-2 「不传则返回所有属性」自描述与实现不一致 / D-M4e-3 跨场景写入措辞）；
2. **范围②：B5 批次 1 的 14 个动画工具**（`editor_animation_write` 4 + `editor_animation_tree_write` 7 + `editor_animation_read` 3），
   全部 `scope = editor`，因此**不出现在游戏端点 9889**，在 9889 上调用一律 `-32601`；
3. **范围③：交付物**——本报告、`docs/tool-groups-b5.json` 的三个 `implemented` 布尔、`scripts/mcp033_b5_animation_evidence.ps1`（可复跑证据）。

`docs/tools_list.renamed.json` **逐字节未改**（见 §7 决策）。未改动 `hof-rs` 任何文件，未改 `DESIGN-DETAIL`。

六道门实测（细节见 §8）：

| 门 | 结果 |
| --- | --- |
| ① 契约子集（逐组 verbatim） | 三组各 **3/3**；`implemented_union = 105`（9888）/ `53`（9889），contract 171 |
| ② 线上证据（成功 / `-32602` / `-32001` / 零手术链 / 端点作用域） | **75/75**，summary sha256 `acc8388b328fc3304b8ed424aab48122e2d3508bc1f76b99cb35fc5968c28a3b` |
| ③ 模块 doctest `[MCPServer]*` | 红：225 例 / 9 失败 / 190 断言失败 → 绿：**229/229 例，10714/10714 断言** |
| ④ 引擎全量 `--headless --test` | **1655/1655 例，434996/434996 断言**（3 skipped） |
| ⑤ `accept_m1.ps1` 连跑两次 | **22/22** + **22/22**，两次用例 ID/判定逐字节一致（diffs=0） |
| ⑥ 窄化门三件套 | 扫描器 `scanned=34 pinned=34` PASS（无漂移）；`--coverage` 17 个声明拼写 exit 0；探针 **101/101**（log sha256 `572761415a43d9…`） |
| 回归 | `mcp030` 22 checks / 0 failed；`mcp032` 39 checks / 0 failed；`mcp031` 门⑥探针 101/101 |

端口纪律：`9877` 属用户 Godot（pid 36392，全程未碰，测试前后 pid 相同断言通过）；测试只用 9888/9889，脚本结束即释放（两道 `released` 断言通过）。未 push。

---

## 2. 引擎依据（每个工具一行）

约定：`API` 取自 Godot 4.8-dev 本仓源码；带行号者在上述提交上按源文件核对过，未带行号者标记头文件里的声明符号，
避免给出未核实的行号。三组共享的引擎词汇表在 `tools/animation_shared.{h,cpp}`（不注册任何工具）。

### 2.1 `editor_animation_write`（4）

| 工具 | 引擎依据（API + 出处） |
| --- | --- |
| `editor_create_animation` | `AnimationMixer::get_animation_library` / `add_animation_library`（`scene/animation/animation_mixer.cpp`；默认库名是**空 `StringName`**，具名库的动画名以 `"<lib>/<name>"` 前缀，见 `animation_mixer.cpp:162`）；`AnimationLibrary::add_animation`、`is_valid_animation_name`、`get_animation_list`（`scene/resources/animation_library.h`）；`Animation::set_length`（`scene/resources/animation.h`） |
| `editor_add_animation_track` | `Animation::add_track(type, at_index)` + `track_set_path` + `value_track_set_update_mode` + `find_track` + `track_get_path` + `track_get_type`（`scene/resources/animation.h`）；`Animation::PARAMETERS_BASE_PATH == "parameters/"` |
| `editor_set_animation_keyframe` | `Animation::track_insert_key(track, time, key, transition)` → **返回键下标，类型不符返回 -1**（`scene/resources/animation.cpp:1719`）；各轨道类型要求的键形状：`POSITION/SCALE_3D`→Vector3、`ROTATION_3D`→Quaternion 或 Basis、`BLEND_SHAPE`→float、`VALUE`→任意、`METHOD`→`{method,args}`、`BEZIER`→长度 5 的数值数组、`AUDIO`→`{start_offset,end_offset,stream}`、`ANIMATION`→字符串；`track_get_key_count/time/value`、`track_set_key_transition`、`track_set_key_value` |
| `editor_remove_animation` | `AnimationLibrary::remove_animation`（返回 bool，`has_animation` 先行判定）；读回 `get_animation_list_size` 计真实删除数 |

### 2.2 `editor_animation_tree_write`（7）

| 工具 | 引擎依据 |
| --- | --- |
| `editor_create_animation_tree` | `AnimationTree`（`scene/animation/animation_tree.h`）：`set_animation_player` / `set_root_animation_node` / `is_active`；`AnimationNodeStateMachine`（`scene/animation/animation_node_state_machine.h`）作为默认根；节点路径由 `Node::get_path_to`（`scene/main/node.cpp`）给出场景根相对路径 |
| `editor_add_state_machine_state` | `AnimationNodeStateMachine::add_node(name, node, Vector2 position)` / `has_node` / `get_node_list_as_typed_array` / `set_node_position`；状态根节点类型 = `AnimationNodeAnimation` / `AnimationNodeBlendTree` / `AnimationNodeStateMachine`（均 `AnimationRootNode`） |
| `editor_add_state_machine_transition` | `AnimationNodeStateMachine::add_transition(from,to,transition)` / `has_transition` / `find_transition` / `get_transition_count`；`AnimationNodeStateMachineTransition::set_switch_mode/get_switch_mode`、`set_advance_mode/get_advance_mode`，枚举序 `IMMEDIATE,SYNC,AT_END = 0,1,2`、`DISABLED,ENABLED,AUTO = 0,1,2`（`scene/animation/animation_node_state_machine.h`） |
| `editor_remove_state_machine_state` | `AnimationNodeStateMachine::remove_node` + `get_node`（不存在即拒）；`get_transition_count` 前后差 = 被连带删除的转移数 |
| `editor_remove_state_machine_transition` | `AnimationNodeStateMachine::remove_transition` + `has_transition`（**先判存在**，不再无条件调用） |
| `editor_set_blend_tree_node` | `AnimationNodeBlendTree::add_node(name,node,position)` / `get_node_position` / `get_node_list` / `get_node_connection_array`（`scene/animation/animation_blend_tree.h`）；`AnimationNodeAnimation::set_animation`（属性，不是 `parameters/…`） |
| `editor_set_animation_tree_parameter` | `AnimationTree::get_property_list` 暴露的 `parameters/…`，其组装在 `AnimationTree::_update_properties_for_node`（`scene/animation/animation_tree.cpp:839-883`），递归经 `AnimationNode::get_child_nodes` 展开各状态的 `get_parameter_list()`；写入前按 `PROPERTY_USAGE_READ_ONLY` 与 `OBJECT` 类型拒 |

### 2.3 `editor_animation_read`（3）

| 工具 | 引擎依据 |
| --- | --- |
| `editor_list_animations` | `AnimationMixer::get_animation_library_list` / `get_sorted_animation_list` / `get_animation_library`（`scene/animation/animation_mixer.cpp`）；`AnimationLibrary::get_animation_list` |
| `editor_get_animation_info` | 上表 read 侧的 `Animation` 轨道/键 API 全套（`track_get_path/type/key_count/key_time/key_value/track_get_transition`、`find_track`） |
| `editor_get_animation_tree_structure` | `AnimationTree::get_root_animation_node`；`AnimationNodeStateMachine::get_node_list_as_typed_array` / `get_node_position` / `get_transition_from,to` / `get_transition(index)`；`AnimationNodeBlendTree::get_node_list` / `get_node_position` / `get_node_connections`；`AnimationNode::get_parameter_list`（`Object::get_class()` 提供 `class` 字段） |

顺序确定性：状态 `states`、混合树节点与 `AnimationMixer` 的库表都是 `AHashMap`/`HashMap`，迭代顺序不可复现
（PLAYBOOK §6.8），因此三处输出全部**排序后**再作答，并用 doctest 断言两次调用逐字节相同。

---

## 3. 范围①：M4e 三项收尾

### 3.1 D-M4e-1 —— 门⑥的五个绕过拼写（commit `613df1eda9`）

| 拼写 | 之前 | 现在 |
| --- | --- | --- |
| 带符号字面量 `x = -1e300` | 已覆盖 | 保持 |
| 括号包裹 `x = (1e300)` | 漏 | `lit_float_range` 允许可选括号/数组初始化/`=` |
| C++17 十六进制浮点 `x = 0x1p300` | 漏 | 字面量正则新增 hex-float 分支，用 `float.fromhex` 判定超宽 |
| 同文件 typedef/using 别名 `typedef real_t f32; f32 x = 1e300;` | 漏 | 新增 `lit_real_t_alias` 动态拼写（收集同文件别名声明后拼接正则） |
| 数组初始化 `float v[] = {1e300};` | 漏 | 无括号分支 + 可选 `{` |

边界**显式声明**而非含糊带过：`--coverage` 打印「别名声明在**另一个文件**（头文件/另一翻译单元）时本门不覆盖」，
所以门⑥的保证被限定在 17 个声明拼写内（DESIGN-DETAIL §22.3b 的要求）。三件套证据：扫描器 34/34 无漂移、
`--coverage` exit 0、探针 101/101（新增 T01..T05 各一条「插入 → 扫描器 exit 1」）。

### 3.2 D-M4e-2 —— 「不传则返回所有属性」（commit `36510a32b7`）

选中**方案 B（改实现）**：`tools/running_game_observation.cpp` 的无过滤枚举去掉
`wanted = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE` 过滤，只保留标签 / `_` 前缀 / `script` / 大小写冲突跳过，
于是游戏端与编辑器端对同一节点答**同一集合**。理由：

- 「所有属性」正是引擎 `Object::get_property_list()` 自身的语义；那两个 usage 位是**检查器可见性标志**，不是「是不是属性」的判据；
- 编辑器同族 `editor_get_node_properties` 一直答未过滤集合，本项顺带修掉「同族两个工具对同一问题答不同集合」的可预期性缺陷；
- 方案 A（走 `DESCRIPTION_OVERRIDES` 改描述 + 重生成 + 指纹）会把一个**迁移源怪癖**固化成契约（GDR-23 §21.6），
  并付出契约改动成本，只为让工具答得更少。

**声明代价**：矩阵/变换残差（`Transform2D` 走 `stringify`）现在在游戏端也可达（编辑器端早已如此），属已存在残差，见 §7。

线上证据（commit `4e71becf2d`）：9888 与 9889 各读同一 `Node2D`，**42 键**，
`Compare-Object -CaseSensitive` 差异 **0**；且 9889 侧现在包含 `transform` / `global_position` / `owner`
这些旧筛选会漏掉的键。doctest：`tools/running_game_observation.cpp` 头部注释与本项一一对应。

### 3.3 D-M4e-3 —— 跨场景写入措辞（commit `36510a32b7`）

`tools/project_cross_scene_write.cpp` 原来用**一句话**覆盖所有零写入情形：
`No scene matched '…': nothing was written. 'path_filter' names a directory that contains .tscn files, not a single scene file; check it and call again.`

现在按**真实成因**分流（dry-run 与提交两个分支共用同一段成因句）：

| 情形 | 判定依据 | 消息 |
| --- | --- | --- |
| `path_filter` 真的是个文件 | `FileAccess::exists()`（`core/io/file_access.h:251`） | `No scene matched '<f>': nothing was written. '<f>' is a file, and 'path_filter' has to name a directory that contains .tscn files (the walker opens a directory, and a single scene file is not one) - pass its base directory and call again` |
| 有场景匹配但都在编辑器里打开且未 `force` | `skipped_open_scenes` 非空 | `<n> scene(s) matched '<f>' but nothing was written. It is / They are open in the editor: pass force=true …` |
| 有场景匹配但没有该类型节点 | `scene_files` 非空 | `<n> scene(s) matched '<f>' but nothing was written. None of them contains a node of type '<type>'; check 'type' and the scenes named by 'path_filter'` |
| 什么都没匹配 | 兜底 | `No scene matched '<f>': nothing was written. 'path_filter' names a directory that contains .tscn files; check it and call again` |

**勘误（append-only，D86）**：`REPORT-AUDIT-M4e` §8 D-M4e-3（测于 `4.8.dev.custom_build.9f2b2e484`）写道
「当 `path_filter` 给的是单个场景文件、**文件匹配上了**但该类型节点数为 0 时」——该**因果前提为假**。
本轮实测：单文件过滤必然匹配 **0** 个场景，因为遍历器用的 `DirAccess::open` 对文件必然失败
（`DirAccessWindows::change_dir` 落到 `SetCurrentDirectoryW`，`core/io/dir_access_windows.cpp:195` 返回 0）；
`tests/test_mcp_server.h` 中 TASK-030 自带的 doctest 早已把「单个场景文件路径不匹配任何场景」写成断言。
该审计的**观测**（`total_scenes=0`、无 `Applied`、无条目）是对的，错的只是它给的原因；本轮措辞修正即针对此。
审计的另一半建议（「让单文件过滤真的接受一个文件」）不采纳：那是行为扩展，超出收尾范围，且会与 TASK-030 已冻结的判据冲突。

---

## 4. 范围②：零字符串手术链（GDR-25 §23.1）

线上 21 次调用，**每一步喂给下一步的标识符都由引擎产出**，调用方（本脚本）对其做 0 次字符串操作
（不切割、不拼接、不改写、不猜测大小写）。脚本用 PowerShell 对象直接传递 JSON 解析结果：

| # | 工具 | 产出 → 下一步消费的标识符 | 调用方字符串操作数 |
| --- | --- | --- | --- |
| 1 | `editor_create_animation` | `length`/`track_count` 读回 | 0 |
| 2 | `editor_add_animation_track` | `track_index=0` → 步骤 3、4 | 0 |
| 3 | `editor_set_animation_keyframe` | `value={x,y,z}` 对象 → 步骤 4 的 `value` | 0 |
| 4 | `editor_set_animation_keyframe`（回喂） | `key_index`/`key_count` 读回 | 0 |
| 5 | `editor_get_animation_info` | `tracks[0].index`/`type`/`keys[1].value` 读回并回喂 | 0 |
| 6 | `editor_list_animations` | `count`/`animations` 读回 | 0 |
| 7 | `editor_create_animation_tree` | `node_path="Tree"` → 步骤 8..18 的 `node_path` | 0 |
| 8-9 | `editor_add_state_machine_state` ×2 | `state_count`、状态名 `Idle`/`Walk` → 步骤 10 | 0 |
| 10 | `editor_add_state_machine_transition` | `switch_mode="at_end"`/`advance_mode="auto"` 读回 | 0 |
| 11 | `editor_get_animation_tree_structure` | `state_names`、`transitions[0]`、`parameters[].name` → 步骤 12 | 0 |
| 12 | `editor_set_animation_tree_parameter` | `parameter="parameters/Idle/backward"` 由读侧产出 → 步骤 13 回喂 | 0 |
| 13 | `editor_set_animation_tree_parameter`（回喂） | `changed.{old,new}` 读回 | 0 |
| 14-15 | `editor_add_state_machine_state`(blend_tree) + `editor_set_blend_tree_node` | `class`/`nodes`/`position` 读回 | 0 |
| 16 | `editor_get_animation_tree_structure` | `blend_trees[0].nodes` 读回 | 0 |
| 17-19 | 三个 `remove_*` | `removed`（真实计数）、`transition_count`/`state_count`/`animation_count` | 0 |
| 20-21 | 反例 | 删完再读 → `-32001`；删不存在的状态 → `-32001` + 建议 | 0 |

任何返回值都不含「需要调用方二次解析」的形状：`node_path` 是场景根相对路径（`Node::get_path_to`），
位置是 `{x,y}`，键值是引擎键值的**同一形状**（§5.3 Quaternion/Vector3 同理），参数名就是 `parameters/…` 原文。

---

## 5. 关键实现决策与自我缺陷

### 5.1 失败不假装成功

- 创建类读回证据：`created`+`length`/`track_count`，`created`+`node_path`+`animation_player_source`+`tree_root`；
- 删除类答**真实计数**：`removed = before - after`（`remove_animation`、`remove_state_machine_state` 另答 `removed_transitions`）；
- 重复/不存在：`track_insert_key` 返回 `-1` → 拒绝；`remove_*` 先存在性判定 → `-32001` + `data.suggestion`（列出持有的动画/状态名）；
- `set_animation_tree_parameter`：读回一致才答 `changed:{old,new}`，不一致答 `ignored:[{parameter,requested,stored,reason}]`（PLAYBOOK §20.6）；
- 14 个工具的 `-32001` 都带 `data.suggestion`（线上 75/75 中的 14 条逐一断言非空）。

### 5.2 与迁移源（`animation_tree.rs` / `animation_tree_commands.gd`）的分歧

| 迁移源行为 | 引擎事实 | 本批次做法 |
| --- | --- | --- |
| `switch_mode` 写裸整数（`{"at_end":0,"sync":2,else 1}`） | `IMMEDIATE,SYNC,AT_END = 0,1,2` | 按**名字**映射到引擎枚举；三种拼写 + 默认 `immediate` 现在都正确（旧代码下三者全错，`advance_mode` 恰好对） |
| 读 `position_x/position_y` 但不传给 `add_node` | `add_node(name,node,position)` | 传位置并在答案里读回 `position` |
| `set_blend_tree_node` 先删后加 | 会丢该节点既有连接 | 已存在则 `-32000` 拒绝（不破坏连接） |
| 无条件 `remove_transition` | `has_transition` | 先判存在，不存在 `-32001` |
| 盲 `Object::set` 后答 `set: true` | `PROPERTY_USAGE_READ_ONLY` / `OBJECT` 参数不可写 | 读回一致才算成功，否则 `ignored`/拒绝 |
| `length` 直接转 `f32` | `Animation::set_length(real_t)` | 经 `value_fits_slot`，超宽 `-32602` |
| `remove_animation` 答 `removed: true` | `AnimationLibrary::remove_animation` 返回 bool | 答真实前后差 |
| 2D 轨道类型折进 `TYPE_POSITION_3D` | 4.x 无 2D position 轨道（键必须 Vector3） | 折进 `TYPE_VALUE`，2D 键可插入 |

### 5.3 新窄化点：Quaternion 读写闭环（commit `c5bc94ac5d`）

`serialize_variant` 原来把 `Quaternion` 答成 `"Quaternion(...)"` 字符串，写侧没有对应拼写——旋转动画键
（`track_get_key_value` 给 Quaternion）能读不能写，正是 §23.1 禁止的字符串手术。现在：

- 读：`Variant::QUATERNION` → `{x,y,z,w}`（与 Vector4 同形）；
- 写：`vector_component_hint` / `_vector_components` / `vector_from_dictionary` 新增 `QUATERNION` 分支，
  `shape_vector_from_json` + `coerce_to_property_type` 接受同一对象；
- 四个分量是 `real_t`，逐分量过 `value_fits_slot(REAL_T)`，落点带 `// MCP-NARROWING: G24-NW-COMPONENTS`。

**遗留（需决策者处理，我无权改 `DESIGN-DETAIL`）**：§23.4 的残差清单仍把 Quaternion 列为未闭环项，
应在下一轮文档更新中移除；同时新增的这条「窄化点 × 门 × 证据」须登记（见 §6）。

### 5.4 自我缺陷（本批次内发现并修复，登记以示诚实）

1. **成功响应的双层信封**：三组 handler 误把 `MCPTools::content_result(...)` 当作返回值，
   而 `mcp_jsonrpc.cpp:308` 已经对 handler 返回值再包一层，于是线上 `result.content[0].text` 里是**又一个**
   `{"content":[…]}`。线上证据脚本第一次运行即暴露（`Get-Payload` 拿到的是信封而非 payload）。
   14 处改为返回原始 payload（与 `editor_node_setup.cpp` 等同族一致），重跑门②③④全绿。
2. **整数 `default` 被引擎 JSON 往返拉平**：引擎 JSON 解析器把**所有**数字存成 `double`（`core/io/json.cpp:393-396`），
   而 `JSON::stringify` 把浮点零写成 `0.0`（`json.cpp:93-95`），因此从契约 JSON 解析出来的
   `"default":0` 在线上变成 `0.0`，门①逐字段比对必然失败。本组两个工具
   （`editor_add_state_machine_state`、`editor_set_blend_tree_node`）是全模块**首批带整数默认值**的工具，
   于是首次触发。修法与既有 b2/b3 生成代码同构：注册时把这**两个字段**放回 `int` Variant
   （`_schema_with_integer_position_defaults`），并把同一归一化写进测试的期望侧。其余 12 个 schema 不受影响。
3. **doctest 期望值两处与引擎语义不符**（`AnimationNodeStateMachine` 自带 `Start`/`End` 状态、
   `AnimationNodeBlendTree` 自带小写 `output` 节点）：按 PLAYBOOK §7.5「先测引擎语义再写期望」修正断言，
   并把「`Dictionary::operator[]` 读缺失键会插入 NIL」这一坑写成注释与断言顺序约束（确定性比对放在任何读之前）。

---

## 6. 门⑥：新增窄化点 × 门 × 证据

| 窄化点（marker） | 位置 | 扫描器 | `--coverage` 声明 | doctest | 线上证据 |
| --- | --- | --- | --- | --- | --- |
| `G24-ANIM-EASING` | `editor_animation_write.cpp:341` | PASS（pinned） | `real_t` cast 拼写 | `editor_set_animation_keyframe` 的缓动写入 | 链步骤 3/4 |
| `G24-ANIM-POSITION`（×2） | `editor_animation_tree_write.cpp:321`、`:562` | PASS（pinned） | — | 状态/混合树位置参数 | 链步骤 8、15 |
| `G24-NW-COMPONENTS`（新增第 6 处：Quaternion） | `running_game_node_write.cpp:236` | PASS（pinned） | — | `TASK-033 the Quaternion read and write shapes are closed`（含超宽 `-32602` 命名 `value.x`） | 属性写读回（门②） |
| `G24-THE-GATE`（复核） | `tool_helpers.cpp:1161` | PASS（pinned，行号随本轮改动重钉） | — | 全模块共用 | 门②/③ |

约束：`--coverage` 打印的 17 个声明拼写 + 显式不覆盖边界共同限定本门保证范围；新增点若落在这些拼写内，
**无论无关行是否移动**都会让 `check_narrowing_points.py` 失败。

---

## 7. 未改动、需上报的缺陷（不擅自修补契约）

1. **创建 Animation 状态时无法指定动画名**：GDScript 原实现（`animation_tree_commands.gd:271,504`）与 Rust 迁移源
   都在读一个**未声明**的 `animation` 参数，而契约里 `editor_add_state_machine_state` / `editor_set_blend_tree_node`
   **没有该属性**，且 `AnimationNodeAnimation::animation` 是**属性**而非 `parameters/…` 参数，所以现有任何工具都无法给
   新建的 Animation 状态命名动画。按 PLAYBOOK §5 不改契约：工具诚实读回 `animation: ""`，本报告给出可直接粘贴的
   `SCHEMA_OVERRIDES` 条目（下述），由决策者决定是否开小批次。
2. **转移参数不可达**：`xfade_time` / `priority` / `advance_condition` 在契约中无成员，因此
   `AnimationNodeStateMachineTransition` 的这三个能力目前不可配置（同属上面一类的 schema 缺口）。
3. **`DESIGN-DETAIL` §23.4 残差清单过期**（Quaternion 已闭环），需决策者更新文档。
4. **门①的新发现（引擎事实，非缺陷）**：整数默认值无法经「契约 JSON → 引擎」往返保型；后续任何带整数 `default`
   的新工具都会遇到，建议把 §5.4.2 的归一化办法写入 PLAYBOOK/设计文档，避免下一批重复踩。

建议的 `SCHEMA_OVERRIDES` 补丁（**本轮未应用**）：

```json
{
  "editor_add_state_machine_state": {
    "properties": { "animation": { "type": "string", "description": "state_type=animation 时该状态的动画名（当前库内）" } }
  },
  "editor_set_blend_tree_node": {
    "properties": { "animation": { "type": "string", "description": "bt_node_type=Animation 时该节点的动画名" } }
  }
}
```

---

## 8. 逐门证据与日志

| 门 | 命令 | 结果 | 日志/工件 |
| --- | --- | --- | --- |
| ① | `check_contract_subset.ps1 -Group editor_animation_{write,tree_write,read}` | 3/3 · 3/3 · 3/3 | `%TEMP%\mcp033_gate1_{write,tree,read}.log` |
| ② | `mcp033_b5_animation_evidence.ps1` | 75/75 | `%TEMP%\mcp033_evidence.log`；证据体 `%TEMP%\task033-b5-animation\evidence\*`（`curl.exe -s -o` + 逐体 sha256） |
| ③ | `--headless --test --test-case="[MCPServer]*"` | 红 225/9 失败 → 绿 229/229，10714 断言 | `%TEMP%\mcp033_red_doctest.log`、`%TEMP%\mcp033_green_doctest.log` |
| ④ | `--headless --test` | 1655/1655，434996 断言 | `%TEMP%\mcp033_full_tests.log` |
| ⑤ | `accept_m1.ps1` ×2 | 22/22 两次一致 | `%TEMP%\mcp033_accept_run{1,2}.log` |
| ⑥ | `check_narrowing_points.py` / `--coverage` / `mcp031_gate6_coverage_probes.ps1` | PASS 34/34 · exit 0 · 101/101 | `%TEMP%\mcp033_gate6_{scanner,coverage,probes}.log` |
| 回归 | `mcp030` / `mcp032` | 22 / 39 checks，0 failed | `%TEMP%\mcp033_reg_mcp{030,032}.log` |
| 构建 | `build_local.cmd -Force` | exit 0，`--version` = HEAD 短哈希 | `%TEMP%\mcp033_green_build.log` |

环境事实：Python 3.13 在 PATH；`scons` 在 `D:\Anaconda\Scripts\scons.exe`；构建命令由 `cmd` 启动
（Git Bash 的 `MSYSTEM` 会让 SCons 提前 exit 255），串行、不吞输出；`.ps1` 全为纯 ASCII；
请求体一律 `ConvertTo-Json` + `--data-binary @file`。

---

## 9. 遗留风险与下一步建议

1. **B5 剩余 44 个工具**（批次 2+）：本批次确立的三条规约可复用于后续组——引擎依据表、零手术链、
   整数默认值归一化（§5.4.2）。
2. **schema 缺口（§7.1/7.2）**：建议开一个小批次，经 `SCHEMA_OVERRIDES` + 指纹重生成补齐
   `animation` / `xfade_time` / `priority` / `advance_condition`，那之后零手术链才能覆盖「给状态命名动画」。
3. **文档同步**：`DESIGN-DETAIL` §23.4 残差清单去掉 Quaternion；§22.3b 的声明拼写数从 16 更新为 17；
   PLAYBOOK 增补「整数默认值」条目。
4. **`REPORT-032` 的 D-M4e-4 勘误**（M4e 审计已提出，本轮未处理）：仍待 append-only 勘误。