# REPORT-027 — D-8（`OBJECT` 属性**双向闭合**）+ **E-2/E-8**（稳定、可复现、可复用的节点路径）

> 任务书：`docs/tasks/TASK-027-object-shape-and-stable-paths.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`；
> 规范：`docs/DESIGN-DETAIL.md` **§23 / GDR-25**（含 **§23.5 `OBJECT` 形状**，本批的新规范）。
> 证据脚本：`scripts/mcp027_object_shape_and_paths_evidence.ps1`（自包含，可重跑）。
> 本批**不新增工具、不改名字、不改契约**（`tools_list.renamed.json` / `tool-rename-map.json` /
> `tool-groups.json` **零改动**，见 §8 指纹；`tools/list` 一律 **True**，门①）。

## 0. status / commits / 构建绑定

| 项 | 值 |
|---|---|
| status | **complete**（两项都落地；OBJECT 形状矩阵与路径口径的每一项都有线上证据） |
| 实现提交 | **`925fc9d607`** — `TASK-027: OBJECT read/write closure (GDR-25 23.5) and root-relative editor node paths`（9 files changed, 741 insertions, 33 deletions） |
| 报告提交 | 第二条提交（本文件；本报告不引用自己的 sha，避免自指） |
| 分支 | `feature/mcp-server-module`（**未 push**） |
| 构建 | `modules/mcp_server/scripts/build_local.cmd -Force`（`tests=yes`），**串行**，scons 输出未抑制（`%TEMP%\mcp_server_build_local.log`） |
| 门绑定（R-1） | 门**全部跑在「二进制自报 hash == 当前 HEAD」之上**：提交后**在 `925fc9d607` 上重建一次**，`--version` = `4.8.dev.custom_build.925fc9d60`，`git rev-parse HEAD` = `925fc9d607761c…` → **前缀一致**；随后重跑门③⑥①②④⑤（结果见 §7）。这是 REPORT-026 登记的流程残留（D-4）在本批被消除，不是本批的缺陷 |

**引擎正解（自己复核过，不是照抄任务书）**：`scene/main/node.h:573`
`NodePath get_path_to(RequiredParam<const Node> p_node, bool p_use_unique_path = false) const;`
与 `node.cpp:2373-2398` 的实现——它按 `data.parent` 链求共同祖先并逐级拼 `get_name()`，**不要求**
节点在场景树里（在未挂接的场景上也成立，TASK-017 的 `_relative_node_path` 手写遍历因此可被它取代）。
`get_unique_scene_id()`（`node.h:554-555`、`node.cpp:2139`）本批**未使用**：它是 `.tscn` 里的
`unique_id=`，是**保存期的身份**，不是调用方要喂回的**路径**；§23.5/E-2 要的是可链式喂回的路径，
所以用 `get_path_to()` 而不是 unique id。

## 1. 逐工具表

### 1.1 D-8 的读侧：`MCPTools::serialize_variant()` 的 `OBJECT` 分支（全模块共用一个形状）

| 项 | 内容 |
|---|---|
| 迁移源位置（**仅类别参考**） | `godot_mcp_gdext` 的 serialize（`{type, value}` 形态）；**不构成行为依据** |
| **引擎依据** | `Object::get_class()`；`Resource::get_path()`（`core/io/resource.h`）与 `Resource::is_local_to_scene()`；节点路径用 `get_path_to()`（见 §0）。判据是「读到的值能不能喂回去」，而 `{}` 与 `{"type","value"}` 都**喂不回去**（`Variant::can_convert(DICTIONARY, OBJECT)` 为假，实测见 REPORT-026 §2.1） |
| **自然契约（读回）** | 空指针 → **`null`**；`Resource` 有路径 → `{"type","path":"res://…"}`；`Resource` 无路径（子资源/内建）→ `{"type","path":"","local_to_scene":<bool>}`；非 `Resource` 对象（节点）→ `{"type","path":"<wire_node_path>"}`。**不泄露指针/地址**（旧 `to_string()` 对无重载的类是 `Object(0x…)`） |
| C++ 落点 | `tools/tool_helpers.cpp`（`serialize_variant` 的 `case Variant::OBJECT`） |
| 与迁移源的差异及理由 | 迁移源给 `{type,value}`（`to_string()`，不可解析、不可喂回）；本批按 **§23.5 落笔的规范**改成 `{type,path}`，理由是引擎自己就能给出稳定标识（`Resource::get_path()`），而 §23.1 要求「返回的标识必须能原样喂回」 |

### 1.2 D-8 的写侧：`coerce_to_property_type(..., OBJECT)`

| 项 | 内容 |
|---|---|
| **引擎依据** | `ResourceLoader::exists()` / `ResourceLoader::load()`（`core/io/resource_loader.h`）；`Object::is_class()`；属性声明类别用 `PropertyInfo::class_name`（`core/object/property_info.h:153-155`：`PROPERTY_HINT_RESOURCE_TYPE` 时 `class_name = hint_string`；`:57` 写明了逗号表 + `-Excluded` 的语法） |
| **自然契约（写回）** | `null` → 清引用；`"res://…"` 字符串 → 加载并设置；`{"type","path"}`（**与读回同形**）→ 按 `path` 加载，`type` 若给出则校验（不符 → `-32602`，消息给期望与实际）；`{}` → `-32602`（不当作"清除"）；路径不存在/加载失败 → `-32001` + `data.suggestion`；**另加**：加载出的资源必须满足该属性**声明的类别**（单个或多个，含 `-` 排除），否则 `-32602`（否则引擎 setter 会静默存 `null` 并报成功） |
| C++ 落点 | `tools/tool_helpers.cpp`（`_object_value_from_json` / `_load_object_resource` / `_object_fits_declared_class` / `object_property_class_hint`）+ `coerce_to_property_type` 的 OBJECT 前置分支；调用点：`running_game_node_write.cpp::prepare_node_property_value`（节点写族）、`project_write_resource_scene.cpp::_resource_property_value`（资源写族） |
| 与迁移源的差异及理由 | 迁移源对 OBJECT 属性只能写字符串（且是静默忽略），本批让**读回形状本身**成为合法输入（§23.1/§23.5） |

### 1.3 E-2：`editor_get_scene_tree`

| 项 | 内容 |
|---|---|
| 迁移源位置（**仅类别参考**） | `godot_mcp_gdext/src/commands/scene.rs:109`（`get_scene_tree`） |
| **引擎依据** | `Node::get_path_to(root, ...)`（`node.h:573`）给出「相对**编辑场景根**」的创作语义路径；`Node::get_path()`（`node.cpp:2462-2463`）走的是**场景树根**，在编辑器里就是编辑器自己的 UI 布局，而且对不在树里的节点是 `ERR_FAIL_COND_V_MSG` |
| **自然契约** | `tree[*].path` = 根为 `"."`、其余为 `get_path_to(root, node)`（`"Actor"`、`"Actor/Sprite2D"`）；**新增** `absolute_path` = 引擎自己的 `get_path()`（不在树里时为 `""`）。`max_depth`/`scene_path`/`name`/`type`/`children` 语义**未变** |
| C++ 落点 | `tools/editor_read_scene_inspector.cpp`（`_build_scene_tree(Node *p_root, …)` + 导出 `MCPTools::scene_tree_of`），声明在 `editor_read_scene_inspector.h` |
| 与迁移源的差异及理由 | 迁移源（与 M4c 实测）给 `/root/@EditorNode@20539/…/@SubViewport@9998/Main/Actor`：不可复现、不可喂回、与同工具成功响应里的 `"Actor"` 两套口径。**绝对路径没有丢**，只是搬到了 `absolute_path`（任务书要求 1 的「另给字段」） |

### 1.4 E-8：节点写族的**拒答消息**

| 项 | 内容 |
|---|---|
| **引擎依据** | 同 §1.3；模块侧唯一的 "wire 拼写" 落在新助手 `MCPTools::wire_node_path()`（`tool_helpers.cpp`）：非 `Node` → 类名；不在树里 → `""`（**不调用** `get_path()`，避免引擎 ERR）；在树里且属于 `edited_scene_root()` → `relative_path(root, node)`；否则（游戏进程）→ 引擎自己的 `node->get_path()` |
| **自然契约** | 拒答消息里的节点与成功响应里的 `node_path` **同一拼写**；编辑器侧**不再出现** `@EditorNode@…`；游戏侧保持 `/root/Main/Actor`（E-2 的范围是编辑器） |
| C++ 落点 | `tools/running_game_node_write.cpp`（`_node_path_for_result` 改为 `wire_node_path`；`prepare_node_property_value` 的未知属性拒答走它） |
| 受影响工具（见 §4） | `editor_set_node_property`、`editor_add_node`、`editor_add_nodes_batch`、`editor_set_node_property_batch`、`running_game_set_node_property`（游戏侧拼写不变） |

## 2. `OBJECT` 形状矩阵（未设置 / 有路径 / 无路径 / 非资源 × 读 / 写 / 往返）

| 情形 | 读回（§23.5） | 写回接受 | 往返证据（三层等价） |
|---|---|---|---|
| **未设置**（空 Object 指针） | **`null`** | `null` → 清引用 | 线上：`P8_read_material_unset` = `null` → `P13_write_material_null` `code=0` `new_value=null` → `P14` 再读 = `null`（`D8_chain_step2/7/8`）；资源侧 `P19`→`P26`→`P27` 同 |
| **有路径资源** | `{"type":"CanvasItemMaterial","path":"res://probe_material.tres"}` | 同形对象 / `"res://…"` 字符串 / `null` | `P9`（字符串写）→ `P10`（读到形状）→ `P11`（**原样喂回**，`new_value` 与读到值结构化相等）→ `P12`（再读相等）；资源侧 `P21`→`P22`→`P23`（`GDScript`/`res://probe.gd`） |
| **无路径资源**（子资源 / 内建） | `{"type":…,"path":"","local_to_scene":<bool>}` | **拒**：`-32602`（"an object without a usable 'path'"）——无文件可加载，宁可诚实拒绝也不静默清空 | 单测 `TASK-027 D-8: an object without a usable path` （`{}` 与缺 `path` 两例） |
| **非资源对象**（节点等） | `{"type":<类>,"path":"<wire_node_path>"}`，**无指针/地址** | **拒**：`-32602`（无 `res://` 路径可解析；本模块没有"按节点路径解析 Object"的入口） | 单测（`serialize_variant` 的节点分支）；登记为 §9 的已知边界 |
| `{}`（空对象） | ——（读侧不再产出它） | **`-32602`** | 线上 `P15`（节点路径）、`P20`（资源路径）、`G5`/`G9`（游戏端点）四处同码；`-32602` 且**前后场景 sha256 不变**（`P18` 证明属性仍是清空后的旧值） |
| `type` 与文件不符 | —— | `-32602`，期望与实际都给 | 线上 `P24b`：`names type 'Node' but 'res://probe.gd' loads as a 'GDScript'`；单测同 |
| 资源不符**属性声明类别** | —— | `-32602`，声明表与实际都给 | 线上 `P24`：`…declared for a 'Script' … expected 'Script', got 'CanvasItemMaterial'`；节点侧 `P16`：`CanvasItemMaterial,ShaderMaterial` vs `Gradient`；单测覆盖 `Texture2D` 单值表与 `CanvasItemMaterial,ShaderMaterial` 多值表 |
| 路径不存在 / 加载失败 | —— | **`-32001` + `data.suggestion`** | 线上 `P17`（节点）、`P25`（资源）；单测同 |

**整包往返（E-9 此前唯一未闭合处）**：`P28a` 读 `environment.tres`（101 条 STORAGE、截断到 64，含
`sky:null`、`script:null` 等 OBJECT 属性）→ `P28` 把整包写回 → **`code=0`**。旧形状下这一步实测是
`-32602`（REPORT-026 §2.1、本批 red 运行里仍是 FAIL）。

## 3. 路径口径前后对照 + 两轮跨进程可复现

**E-8 错误消息（同一工具、同一次调用、同一份请求体）**：

| | 消息（原文） | 响应 sha256 |
|---|---|---|
| **前**（red 二进制，`-Phase red`） | `Property 'no_such_property_xyz' on node '/root/@EditorNode@20539/@Panel@14/@VBoxContainer@16/DockVSplitMain/DockHSplitMain/@VBoxContainer@38/DockVSplitCenter/@VSplitContainer@102/@VBoxContainer@103/@EditorMainScreen@166/2D/@VBoxContainer@9985/@VSplitContainer@9991/@HSplitContainer@9993/@HSplitContainer@9995/@Control@9996/@SubViewportContainer@9997/@SubViewport@9998/Main/Actor' not found` | `bf076ef7…` |
| **后**（green 二进制） | `Property 'no_such_property_xyz' on node 'Actor' not found` | `P5` 响应即证据 |
| 前（根节点，`path='.'`） | `…on node '/root/@EditorNode@20539/…/@SubViewport@9998/Main' not found`（sha256 `b0a69c9e…`） | |
| 后（根节点，`path='.'`） | `…on node '.' not found` | |

**E-2 场景树**：

| | 主字段 `path` | 另给字段 `absolute_path` |
|---|---|---|
| 前 | 整个响应里 `path` = `/root/@EditorNode@…/@SubViewport@9998/Main`（根）、`…/Main/Actor`、`…/Main/Actor/Sprite2D` | （不存在） |
| 后 | `.`、`Actor`、`Actor/Sprite2D` | `/root/@EditorNode@…/@SubViewport@9998/Main` 等（**只在这一个字段里**） |

**两轮跨进程逐字可复现**（两个**独立启动**的编辑器进程，各自 `editor_open_scene` 后调
`editor_get_scene_tree {}`，比较**整个响应体**）：

```
process 1 (P2_tree_run1)  : bytes=1427 sha256=bdebaef06ea075b9ca05bd5a7587654be40bd368c61d6e21c477ed31fb19352d
process 1 again (P3)      :                     sha256=bdebaef06ea075b9ca05bd5a7587654be40bd368c61d6e21c477ed31fb19352d
process 2 (P30_tree_run2) :                     sha256=bdebaef06ea075b9ca05bd5a7587654be40bd368c61d6e21c477ed31fb19352d
paths: '.' / 'Actor' / 'Actor/Sprite2D'  （两轮逐字相同）
```

即 **同进程两次 == 重启后 == 逐字节相同**；red 二进制里同一脚本给出的是
`/root/@EditorNode@20539/…` 那一条（FAIL 三条）。

## 4. 受影响工具清单（逐条 + 证据）

**A. 输出形状改变（E-2）**

| 工具 | 变化 | 证据 |
|---|---|---|
| `editor_get_scene_tree` | `tree[*].path` → 相对编辑场景根；新增 `tree[*].absolute_path` | `P2`/`P3`/`P4`/`P30`（§3） |

**B. 拒答消息改变（E-8，经共享 `write_node_property`/`prepare_node_property_value`）**

| 工具 | 变化 | 证据 |
|---|---|---|
| `editor_set_node_property` | 未知属性的 `-32001` 消息里的节点 → 相对拼写 | `P5`（`Actor`）、`P6`（`.`）；red 对照见 §3 |
| `editor_add_node` | 同上（`properties` 袋里的未知属性） | `P7`：`on node '' not found`（该节点此刻**尚未挂接**在树上 → 按规则给空串；与 TASK-017 的既有断言逐字一致，`mcp017` 88/88 复跑通过） |
| `editor_add_nodes_batch` | 同上（`nodes[i]` 的元素消息） | `mcp017` 复跑 88/88；其中 `text_batch_property_refusal_has_exactly_one_not_found` 断言的**逐字消息** `nodes[1]: Property 'NoSuchPropertyXYZ' on node '' not found` 仍成立 |
| `editor_set_node_property_batch` | 同上（预检与写中两条消息） | 同上 |
| `editor_set_node_property_across_scenes` | 同上（写入的是**未挂接**的实例树 → 空串，字节不变） | 单测 213/213、`mcp018` 未受影响（未跑，登记在 §9 B-1） |
| `running_game_set_node_property` | **不变**（游戏侧仍是 `/root/Main/Actor/Sprite2D`，E-2 只改编辑器拼写） | `G8` 逐字消息 + `sha256=6e24d97f…`（缺属性时的节点解析失败消息） |

**C. 属性值形状改变（D-8，共用一个 `serialize_variant`；只影响**能装 Object 值**的属性）**

| 工具 | 变化 | 证据 |
|---|---|---|
| `editor_get_node_properties` / `editor_get_node_properties`（`properties` 过滤） | Object 值：`{}`/`{type,value}` → `null`/`{type,path}` | `P8`/`P10`/`P12`/`P14`（节点路径 `material`） |
| `running_game_get_node_properties`（含 `_batch`）、`running_game_get_node_property_samples`、`running_game_get_node_properties` 族 | 同上 | `G1`/`G3`/`G7`（游戏端点 `material`） |
| `project_read_resource` | `properties.<Object 属性>` 同上 | `P19`（`script:null`）、`P23`（`{type,path}`）、`P28a`（`sky:null`） |
| `project_edit_resource` / `project_create_resource` | `changed.<名>.old/new` 同上；**并且**新增接受 OBJECT 的三形态（字符串/同形对象/null） | `P21`/`P22`/`P23`/`P26`/`P27`、`P28` |
| `running_game_set_node_property` / `editor_set_node_property` | `old_value`/`new_value` 同上；新增接受三形态 | `P9`-`P14`、`G2`-`G6` |
| `project_set_setting`（值经 `serialize_variant`）、`running_game_execute_gdscript`/`editor_execute_gdscript`（`result`）、`project_get_scene_exports`/`project_analyze_scene_complexity`（属性值）、`running_game_assert_node_state`/`running_game_run_test_scenario`（`expected`/`actual`/verdict） | **源码级**：都经同一个 `serialize_variant`，因此 Object 值同形；本批**未**逐个构造 Object 值活证据（登记 §9 B-2），但形状函数只有一份（`tool_helpers.cpp` 的 `case Variant::OBJECT`），不存在第二套拼写 | 源码：`grep serialize_variant tools/*.cpp` |

**D. 已经用相对拼写、本批**未改**的工具**（对照项，证明口径本来就该如此）：
`editor_get_selection`、`editor_get_node_properties`（`node_path`）、`editor_get_node_groups`、
`editor_find_nodes_in_group`、`editor_find_nodes_by_type`、`editor_list_signal_connections`、
`editor_analyze_signal_flow`、`editor_node_write` 组的全部成功 `node_path`、`editor_node_setup` 组、
`editor_control_layout_write`、`editor_node_instantiate`、`project_cross_scene_write`、
`project_read_analysis` —— 它们本来就走 `get_path_to`/`relative_path`（M4c 的 E-2 只点名了
`editor_get_scene_tree`）。**证据**：`mcp016` 86/86、`mcp017` 88/88、`mcp018`/`mcp026` 未回退（§7）。

## 5. 零字符串手术链（§23.1；调用方字符串处理次数 = **0**）

实测（`P2`→`P14`，编辑器 9888；脚本对链区做机械检查 `E2_zero_string_surgery_chain`，禁止
`.Split(`/`.Replace(`/`.Substring(`/`.Trim(`/`-match `/`-replace `/`[double]`/`[int]`/`[regex]`，
结果 `<none>`）：

```
1 editor_get_scene_tree {}            -> .tree.children[0].children[0].path = "Actor/Sprite2D"   (0 次字符串处理)
2 editor_get_node_properties(path=步1) -> .properties.material = null（未设置 = null，不是 {}）    (0)
3 editor_set_node_property(path=步1, property='material', value='res://probe_material.tres')      (0)
                                     -> code=0
4 editor_get_node_properties(path=步1) -> .properties.material = {"type":"CanvasItemMaterial","path":"res://probe_material.tres"}  (0)
5 editor_set_node_property(path=步1, property='material', value=步4.material) -> code=0，
     .new_value 与步4 结构化相等                                                                  (0)
6 editor_get_node_properties(path=步1) -> 与步4 相同                                              (0)
7 editor_set_node_property(... value=null) -> code=0，new_value=null                              (0)
8 editor_get_node_properties(path=步1) -> material=null                                           (0)
```

**路径未被手工剥离**：步 2..8 的 `path` 是**步 1 的字段值**；`absolute_path` 一次也没被用过，
链上没有任何 `@EditorNode@` 出现（脚本同时断言 `P2_no_path_field_is_absolute` = False 与
`E2_run2_no_path_field_is_absolute` = False）。游戏端点同形链见 `G1`-`G7`（`node_path='Actor/Sprite2D'`，
`resolve_game_node` 语义，0 次字符串处理）。

## 6. 红/绿证据（真实输出）

### 6.1 模块 doctest 红 → 绿（`--headless --test --test-case="[MCPServer]*"`）

* **基线（父提交 `5392486f18`，即 TASK-026 收口）**：`test cases: 209 | 209 passed | 0 failed | 1429 skipped`，
  `assertions: 8228 | 8228 passed`，exit 0（REPORT-026 §6 门③）。
* **红**（把 OBJECT 读/写分支与 `_build_scene_tree` 临时还原为旧行为、`_node_path_for_result` 还原为
  `get_path()`，`git copy` 备份 + 重建，见 §9 D-7 的复现步骤）：`test cases: 213 | 210 passed | **3 failed**`，
  `assertions: 8305 | 8277 passed | **28 failed**`，`Status: FAILURE!`（log `%TEMP%\t027_red_mcpserver.log`）。
  失败点直接点名两项缺口：

  ```
  test_mcp_server.h(14860): ERROR: CHECK( unset.get_type() == Variant::NIL )        ← 空 Object 读回 {}
  test_mcp_server.h(14896): ERROR: CHECK( String(shape["path"]) == resource_path )  ← 读回没有 path
  test_mcp_server.h(14897): ERROR: CHECK_FALSE( shape.has("value") )                ← 仍是 {type,value}
  test_mcp_server.h(14908): ERROR: CHECK( accepted )                                ← 同形对象写回被拒
  test_mcp_server.h(14919): ERROR: CHECK( accepted )                                ← res:// 字符串被拒
  test_mcp_server.h(14930): ERROR: CHECK( error.code == -32001 )                    ← 加载失败不是 -32001
  test_mcp_server.h(15068): ERROR: CHECK( String(tree["path"]) == "." )             ← 场景树仍是绝对路径
  test_mcp_server.h(15076): ERROR: CHECK( String(actor_entry["path"]) == "Actor" )
  ```
* **绿**（本提交工作树重建后）：`test cases: 213 | 213 passed | **0 failed** | 1429 skipped`，
  `assertions: 8309 | 8309 passed | **0 failed**`，`Status: SUCCESS!`（log `%TEMP%\t027_gate3_final.log`）。
  相对基线 **+4 用例 / +81 断言**。

### 6.2 线上红 → 绿（同一个 `scripts/mcp027_object_shape_and_paths_evidence.ps1`，脚本自身不改）

| | 红（旧行为二进制，`-Phase red`） | 绿（本提交，`-Phase green`） |
|---|---|---|
| 结果 | **32/61**，exit 1（log sha256 `7baeb80ef05321d78f8e5466d80c7361de7618ff79843d7c0a65d40db4e5e007`） | **61/61**，exit 0（log sha256 `9ed7c4f2853d578167f3d0cc9351dfc29cbea4776b5fa99f93110bdc6d387a60`） |
| E-2 | `tree[*].path` = `/root/@EditorNode@…/@SubViewport@9998/Main`，`P2_no_path_field_is_absolute` FAIL | `.` / `Actor` / `Actor/Sprite2D`；无绝对 `path` 字段；两轮字节相同 |
| E-8 | `P5`/`P6` FAIL，消息含整条 `@EditorNode@…`（sha256 `bf076ef7…`/`b0a69c9e…`） | `on node 'Actor'` / `on node '.'`，`@EditorNode@` 0 次 |
| D-8 | 读 `{}`、写字符串/对象被拒、写 `null` 读回 `{}`、整包写回 `-32602`（29 条 FAIL） | 三形态全闭合（32 条断言 PASS），整包 `code=0` |
| 两次运行的日志 sha256 | —— | **两次 green 运行逐字节相同**（`9ed7c4f2…`，含跨进程比较） |

> **TASK-026 的缺陷探针 `mcp026_object_shape_probe.ps1` 现在按设计 FAIL**：它断言的正是本批修掉的
> 三种旧行为（`read_answers_a_null_object_reference_as_an_empty_object`、
> `json_null_is_accepted_but_reads_back_as_an_empty_object`、
> `the_whole_read_bag_is_refused_for_the_same_reason`），实测 **8/11**，其余 8 条（含
> `feeding_the_read_value_back_is_refused_-32602`，因为空对象 `{}` 仍按 §23.5 拒绝）仍 PASS。
> 按 PLAYBOOK §7.2/§7.3 的 **append-only** 原则**没有改动这个历史探针**，它的失败方向正是本批的目标。

## 7. 门（全部自跑；真实输出与退出码）

| 门 | 命令 | 结果 | 证据（文件 / sha256） |
|---|---|---|---|
| ⓪ 构建绑定 | `build_local.cmd -Force` + `--version` v.s. `git rev-parse HEAD` | `exit 0`；`--version` = `4.8.dev.custom_build.925fc9d60` == HEAD `925fc9d607761c…`（**在提交上重建**） | `%TEMP%\mcp_server_build_local.log` |
| ① 契约子集逐字 | `scripts\check_contract_subset.ps1 -Group editor_read_scene_inspector` | **3/3 PASS，exit 0**；编辑器 91 工具 / 游戏 53 工具；本组 7 条在两端点 `name/description/inputSchema` 全 True；实现并集 113 == 契约标记数 | `%TEMP%\t027_gate1_final.out.txt`，sha256 `3397271ddc1f7feab2b2bc4cc9c065226f5c19e94bda35d8411346cd7d645f7f` |
| ② 三类证据 + 端到端活证据 | `scripts\mcp027_object_shape_and_paths_evidence.ps1 -Phase green`（9888/9889） | **61/61 checks，exit 0**；红绿对照见 §6.2 | `%TEMP%\t027_script_green.out.txt`；evidence log sha256 `9ed7c4f2…`（`%TEMP%\task027-object-and-paths-green\evidence\`） |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **213/213 passed，0 failed，8309/8309 断言，exit 0**（基线 209/8228） | `%TEMP%\t027_gate3_final.log`，sha256 `b6feb787d8117e3d29065d3e9b97762f99a5832754a9fae3dc702902bc71f9a1` |
| ④ 全引擎回归 | `--headless --test` | **1639/1639 passed，0 failed，432591/432591 断言，SUCCESS!，exit 0**（上一批 1635/432510） | `%TEMP%\t027_gate4_final.log`，sha256 `18a0272772528028825ab3030bb39cc19504a4f1f587b49594522cb030400fe7` |
| ⑤ 批次收口 | `scripts\accept_m1.ps1` **连跑两次** | 两次都 **22/22 PASS，exit 0**，两次 PASS 清单**逐条一致**（`identical=True`） | `%TEMP%\t027_gate5_final_run1.out.txt`（sha256 `92d483db030c1474362490c6f2c6d78ca136b854327885550e161a47e6383f30`）、`…run2.out.txt` |
| ⑥ 收窄点清单 | `python scripts\check_narrowing_points.py` | **exit 0**；无 drifted、无 FAIL；两个 pin 的行号按脚本提示更新（`project_write_resource_scene.cpp` 183→190、`tool_helpers.cpp` 1051→1136） | `%TEMP%\t027_gate6_final.out.txt`，sha256 `1b9283eb469eb8dd6920293b05f8c4e6953f706c98b9501ca682117953111b56` |

**复跑既有证据脚本（确认未回退）**：

| 脚本 | 结果 |
|---|---|
| `mcp016_node_read_instantiate_evidence.ps1`（TASK-016 写族→读族互验链） | **86/86 checks passed，exit 0**（`%TEMP%\t027_recheck_task016.out.txt`） |
| `mcp017_batch_layout_setup_evidence.ps1`（**逐字消息**最敏感的那一条） | **88/88 checks passed，exit 0**（`…\t027_recheck_task017.out.txt`），其中 `nodes[1]: Property 'NoSuchPropertyXYZ' on node '' not found` 逐字不变 |
| `mcp026_e9_e6_evidence.ps1`（E-9 读回→写回链 + 日志来源） | **37/37 checks passed，exit 0**（log sha256 `c7f453b0a96cc7d0b8b99b0beb2714c761b2939f7bee27c5a818c3b0e434246d`） |
| `mcp026_object_shape_probe.ps1`（旧缺陷探针） | **8/11**，失败的 3 条是**被修掉的旧行为**（按设计；见 §6.2 末） |

端口纪律：全程只占 **9888/9889**；用户 Godot 4.7.1-mono 的 **9877（PID 36392）在每次门/证据前后
都被读 pid 校验未变**（脚本内 `port_9877_owner_before/after` PASS）。工作树收尾只剩既有未跟踪物
（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）。

## 8. 改动文件与指纹（sha256，本提交内容）

| 文件 | sha256 | 说明 |
|---|---|---|
| `tools/tool_helpers.cpp` | `260e1b9d89880c7cca97b9944d766e7474587d2a7600157c0243757b50baf3f0` | OBJECT 读形状 + 写语法 + `wire_node_path` + `object_property_class_hint` |
| `tools/tool_helpers.h` | `a02e9ec4217852472bd1558024ebbd3779bad279fd92c579e18d1d408be376f5` | 三个新声明 + `coerce_to_property_type` 的 `p_expected_class` |
| `tools/running_game_node_write.cpp` | `a29aed6d9cc492c518e3f8147c5e885b59a696425bf3c790447bc1cb7929166b` | `_node_path_for_result` → `wire_node_path`；声明类别透传 |
| `tools/project_write_resource_scene.cpp` | `56f573c48a47b66edcbf8fbead9e02df0d65a6438f26988f32597d95fc605334` | 资源路径的声明类别透传 |
| `tools/editor_read_scene_inspector.cpp` | `fe68fe6ed7e84002f2adf7ad2d12e0fc9ca3ef3546d44e3a6e9d3f0339773f44` | 相对路径 + `absolute_path` + `scene_tree_of` |
| `tools/editor_read_scene_inspector.h` | `8f0116dcb27a8604831d6cb7f68e4bdfb9873fe2b4ef2c87d365ac6a35546d2b` | `scene_tree_of` 声明 |
| `tests/test_mcp_server.h` | `5b28b5f2e52267dbe8ffb6453b152819f859542845672df07ca4dbd8674bb93f` | +4 用例、+81 断言 |
| `scripts/check_narrowing_points.py` | `8bd7fd8710682f0258ecb323644354d5d0fc24086b208d84a86f3773dee4c2ae` | 仅两个 pin 行号 |
| `scripts/mcp027_object_shape_and_paths_evidence.ps1` | `b4cc6b25c2ff3f042689b75f44d9ae1f85b8ddc986361f9c3bc2b257a8836b6d` | 门②证据脚本（新，自包含） |

**契约/映射/生成器**：`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、`docs/tool-groups*.json`
**本批零改动**，因此文档指纹与 `_meta.map_sha256` 不变；`tools/list`/`description`/`inputSchema` 逐字未动（门① True）。
**输出形状**（`tree[*].path`/`absolute_path`、OBJECT 值、拒答消息）不在 `inputSchema` 内，因此**不需要**
`SCHEMA_OVERRIDES`/`DESCRIPTION_OVERRIDES`（按任务书要求 4，未自行改描述）。

## 9. deviations / blockers / next_step

### deviations（逐条显式）

* **D-1（新发现，登记）**：**全新**工程目录 + `.tscn` 场景时，第一次 `--import` 实测
  `exit=-1073741819`（`0xC0000005`）。本批证据脚本因此跑两次 `--import`，并要求**第二次**为 0
  （已初始化的工程稳定 exit 0）；对照：TASK-026 的探针工程**没有 `.tscn`**，第一次 `--import` 就是
  exit 0。这与 REPORT-024a §9「未能复现」是同一现象的不同构造（那次没有 `.tscn` 参与）。
  **与本次改动无关**（未触碰 `import` 路径），登记供决策者决定是否立一个引擎侧小批。
* **D-2（超出 §23.5 字面的第四条写侧规则）**：**属性声明类别校验**（`object_property_class_hint` +
  引擎自己的逗号/`-` 列表语法）。加它的理由是它属于本项目一直在打的
  「失败 → 默认值 → 报成功」家族：`Sprite2D.texture` 声明 `Texture2D`，把一个 `Gradient` 资源写进去，
  引擎 setter 会**存 null 并报成功**。不加这条，本批新增的「字符串形态」会把一个**新的**静默默认值
  引进模块。若不接受，可只回退 `_object_fits_declared_class` 的两处调用（但 §2 的最后两行证据会消失）。
* **D-3（非资源对象的写回不支持）**：`{"type":"Node2D","path":"Actor"}` 这种非 Resource 对象的读回值
  **不能**写回（`-32602`，消息说明原因）：模块内没有"按节点路径解析 Object 属性"的上下文/入口，
  而 `ResourceLoader` 只能按 `res://` 加载。当前**没有任何工具**读回 Node 类型的 Object 属性（现有
  Object 属性全是资源：`texture`/`material`/`sky`/`script`/…），所以这是登记边界而非今天的功能缺口。
* **D-4（`local_to_scene` 只读不写）**：无路径资源的读回多带一个 `local_to_scene` 布尔；写侧把它当
  未知成员忽略（同形对象只认 `type`/`path`）。这是 **§23.5 表格**里「（若适用）」的直译。
* **D-5（门⑥ pin 行号）**：按脚本自身提示更新两个 pin（不是绕过失败；不更新也 `exit 0`，只是留 drifted 提示）。
* **D-6（`absolute_path` 是新增输出字段）**：任务书要求 1 的「需要绝对路径时另给字段」；它在
  `tools_list.renamed.json` 的 `inputSchema` 之外，故未触发契约流程（门① 证明契约逐字未变）。
* **D-7（红相位的构造方式，方法论声明）**：为了让红相位是**真的断言失败**而不是编译失败，红二进制是
  「保留新声明（`scene_tree_of`/`wire_node_path`/`object_property_class_hint`/`_object_value_from_json`），
  把三处**行为**临时还原为旧实现（`serialize_variant` 的 OBJECT 分支、`coerce_to_property_type` 的
  OBJECT 前置分支、`_build_scene_tree` 的路径 + `_node_path_for_result` 的 `get_path()`）」，
  备份文件在 `%TEMP%\t027_backup\`，绿相位由备份**逐字节还原**后重建（文件 sha256 见 §8）。
  红二进制**未提交**、**未留在工作树**（`git status` 只剩既有未跟踪物）。
* **D-8（游戏侧路径未改）**：E-2 的范围是编辑器；游戏侧 `running_game_*` 仍答 `/root/Main/…`（`G8` 逐字证据）。
  若决策者希望游戏侧也统一为「相对当前场景根」，那是**另一项**（会影响 53 个游戏工具与它们的契约描述），
  不在本批范围。
* **D-9（门④/⑤ 与二进制 hash 的时序）**：门④⑤ 也**在提交前**跑过（内容相同、`git status` 为空），
  而 §7 表里的数字是**提交后在同一 HEAD 上重建**再跑的一轮；两轮的因果不同，数字一致。

### blockers

* 无。端口 9877 未受影响；无网络/依赖受阻；无未决构建错误。

### next_step_recommendation

1. **D-1 的 `--import` 崩溃**值得给它一个独立小批（或报给引擎侧）：它影响**所有**新建 scratch 工程的门脚本
   （PLAYBOOK §3 要求校验 `--import` 退出码，而它在"全新工程 + 含 `.tscn`"时**必现** 0xC0000005）。
2. **D-8 的两个登记边界**（D-3 非资源对象写回、D-4 `local_to_scene` 写侧）如需闭合，需要一个明确的
   解析上下文设计（谁把节点路径解析成对象），属决策者裁决。
3. 剩余顺手性项（REPORT-026 §9）：**G-1**（子属性路径 `position:y` / `Object::set_indexed`）、
   **G-3**（`editor_get_test_report` 的破坏性 `clear` 默认值）仍未领。
4. 若要求「游戏侧也相对当前场景根」，请显式立项（会动契约描述与 53 个游戏工具的返回形状）。
