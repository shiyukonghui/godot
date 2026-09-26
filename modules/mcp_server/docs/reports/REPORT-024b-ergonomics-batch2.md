# REPORT-024b — 顺手性批次 2：E-1+G-2（依赖的 `type` / 可喂回的 `path`）· E-3（读回形状一致）

* **status**：**完成**（六道门全绿；两项范围内改动均落地；发现并上报 1 个门脚本缺陷 + 1 个新残留缺口，均**未**越权修复/扩范围）
* **任务书**：`docs/tasks/TASK-024b-ergonomics-batch2.md`（按 `docs/tasks/PLAYBOOK-group-port.md` 执行）
* **规范落笔**：`docs/DESIGN-DETAIL.md` §23 / GDR-25（零字符串手术链）
* **分支 / HEAD（代码提交）**：`feature/mcp-server-module` · `928af5d3d8`
* **二进制自报**：`4.8.dev.custom_build.928af5d3d`（`scripts/build_local.cmd`，`tests=yes`；`--version` 前缀 == HEAD 前 9 位）
* **端口纪律**：全程只用 9888（编辑器）/ 9889（游戏）；用户 Godot 4.7.1-mono 的 **9877（PID 36392）只读采样，未占用/未杀/未重启**（证据运行前后 pid 同为 36392）；**未 push**
* **范围内的两项**：① `project_get_scene_dependencies` 的 `type`/`path`（E-1+G-2）；② `serialize_variant` 的 `Vector4/Vector4i/Rect2i` + 全部 packed 显式分支（E-3）。**未改名字、未改 `inputSchema`**（门① 逐字 PASS 为证）

## 1. commits

| sha | 一行说明 |
|---|---|
| `2a1cb4a4e8` | `TASK-024b E-1/G-2 + E-3: real dependency type/path, one shape per kind` — 实现（`tool_helpers.{h,cpp}`、`project_read_analysis.cpp`）+ doctest（红→绿） |
| `928af5d3d8` | `TASK-024b: gate-2 evidence script and the renumbered narrowing pin` — 门② 证据脚本 + 门⑥ 引脚行号更新 |
| `abffba1cc5` | `TASK-024b: gate-2 evidence for the E-3 write-side residual gap, and REPORT-024b` — 证据脚本补 `GAP_*` 两条实测 + 本报告 |

## 2. 逐工具表（PLAYBOOK §4）

| new_name（未改） | 迁移源位置（**仅类别参考**） | 引擎依据（为什么这是自然形态） | 自然契约（本次改动的输出面） | C++ 落点 | 与迁移源的差异及理由 |
|---|---|---|---|---|---|
| `project_get_scene_dependencies` | `godot_mcp_gdext/src/commands/batch.rs:519`（只说明「有这类工具、读 ext_resource 列表」） | `ResourceLoader::get_dependencies(path, &deps, /*p_add_types=*/true)`（`core/io/resource_loader.h:270`，实现 `resource_loader.cpp:1348-1358`）→ `ResourceLoaderText::get_dependencies` 的**字符串布局** `path::type[::fallback]`（`scene/resources/resource_format_text.cpp:960-968`；`fallback_path` 语义见 `:949`）；真实类型 `ResourceLoader::get_resource_type`（`resource_loader.h:266`）；UID 归一 `ResourceUID::ensure_path_nocheck`（`core/io/resource_uid.cpp:259-268`） | `{path, dependencies:[{path, uid, type, declared_type, path_source}], count}`；`path` **恒为 `res://`**（可直接喂回），`uid` 为 `uid://…` 或空串，`path_source ∈ {uid, scene_path, unresolved}` | `tools/project_read_analysis.cpp` `_tool_get_scene_dependencies`（`resource_uid.h` 新 include） | 迁移源按 `"::"` 切分后取**第三段**当 `type`，而 `add_types=false` 时第三段是**引擎的 fallback 路径**（D-8）；本实现改用引擎的 `p_add_types=true` 布局并逐字段命名。**这是「工具真的能用」优先于复刻参照**（PLAYBOOK §6.6 / D74 §8b） |
| `editor_get_node_properties` | `editor.rs`（类别参考） | 同一读回序列化器：`serialize_variant`（`tools/tool_helpers.cpp`）——引擎的 `Vector4`/packed 与 `Vector2` 同属值类型，形状应同类同形（GDR-25 §23.1 规则 4） | 值域：`Vector4/Vector4i → {x,y,z,w}`、`Rect2i → {x,y,width,height}`、packed → 元素自身形状的 JSON 数组（`PackedByteArray → [int…]`） | `tools/tool_helpers.cpp` `serialize_variant`（新增分支） | 迁移源把 `Vector4`/packed 落进 `stringify()`（字符串）；本实现给显式分支，理由：同一份读回里对象/字符串混排会让消费者分支处理，且字符串形态**不可喂回** |
| `running_game_get_node_properties`（及 `_batch`、`_property_samples`、`capture_frames`、assertion 族） | `addons/godot_mcp_rs/*`（类别参考） | 同上（全部经**同一个** `serialize_variant`） | 同上（编辑器侧与游戏侧形状**逐字一致**，门② 实测两端口段相同） | 同上 | 同上 |

> `serialize_variant` 的调用面（受影响面清单，见 §7）：`editor_node_read`、`editor_script_write`、`editor_input_simulation`、`input_recorder`、`project_read_analysis`（exports/deps）、`project_read_template`、`project_setting_write`、`project_write_resource_scene`、`running_game_assertion`、`running_game_frame_observation`、`running_game_node_write`、`running_game_observation`、`running_game_script_execution`、`running_game_test_execution`。

## 3. 每项：现状 → 引擎正解 → 改后

### 3.1 E-1 + G-2（`project_get_scene_dependencies`）

**现状（改前，M4c 线上实测 + 本次红阶段 doctest 复现）**

```
{"count":1,"dependencies":[{"path":"uid://c7mt5x5j361vt","type":"res://main.gd"}],"path":"res://scenes/main.tscn"}
```

* `type` = **fallback 路径**（不是类型）：`add_types=false` 时字符串是 `uid://id::::res://fallback`，按 `"::"` 切分后 `parts[2]` 恰是 fallback；
* `path` = `uid://…`，调用方必须**额外走一趟** `project_convert_uid_to_path` 才能喂给别的工具；
* 红阶段 doctest 在 uid 场景上实测同一现象：`CHECK( (String)dep["type"] == "Resource" ) values: CHECK( res://mcp_server_test_fixture/resources/used.tres == Resource )`、`CHECK( (String)dep["path"] == … ) values: CHECK( uid://c7mt5x5j361vt == res://… )`。

**引擎正解（已自行复核行号，非照抄 M4c）**

| 事实 | 位置 |
|---|---|
| `get_dependencies(path, &deps, p_add_types=false)` 默认不产类型 | `core/io/resource_loader.h:270`；`resource_loader.cpp:1348-1358` |
| `p_add_types=true` → `path += "::" + type`；有 uid 时**再** `path += "::" + fallback_path`（`fallback_path` = 标签自带的 `path`，注释原文 "Used by Dependency Editor, in case uid path fails"） | `scene/resources/resource_format_text.cpp:939-968`（`:949` 为注释） |
| `add_types=false` 且无 type 时仍补一个空段（`path += "::"`）→ 第三段是 fallback | 同上 `:960-968` |
| 静态 `ResourceLoader::get_resource_type(path)`：`.tscn → PackedScene`、`.tres` 读头 → 兼容类名、`.gd → GDScript`（不加载资源） | `resource_loader.h:266`；`resource_format_text.cpp:1487-1507`；`modules/gdscript/gdscript_resource_format.cpp:70-76` |
| UID → 路径的**非抛错**归一（未注册返回空串；`uid_to_path` 会 `ERR_FAIL`） | `core/io/resource_uid.cpp:239-268` |

**改后（门② 线上实测，编辑器 9888）**

```jsonc
// 手写场景（标签无 uid=）
{"count":1,"dependencies":[{"declared_type":"Script","path":"res://main.gd","path_source":"scene_path","type":"GDScript","uid":""}],"path":"res://scenes/main.tscn"}
// 第二个场景（资源依赖）
{"count":1,"dependencies":[{"declared_type":"Resource","path":"res://resources/thing.tres","path_source":"scene_path","type":"Resource","uid":""}],"path":"res://scenes/sub.tscn"}
// 引擎自己保存过的场景（`editor_save_scene` 写入 uid=）
{"count":1,"dependencies":[{"declared_type":"Script","path":"res://main.gd","path_source":"uid","type":"GDScript","uid":"uid://bhcm8edoqs7m0"}],"path":"res://scenes/main.tscn"}
```

* `type` = **引擎对已解析资源报告的类型**（`.gd → GDScript`），`declared_type` = `[ext_resource type=…]` 的标签值（`Script`）——两者都给，差异可见而不是靠猜；
* `path` **恒为 `res://`**：UI/资源/脚本类工具可直接接；
* `path_source` 如实披露 `path` 是「UID 注册表解析」还是「场景文件自带的路径」（引擎自己对此的措辞就是 fallback），或 `unresolved`（两者都不可用时 `path` 为空串，绝不把 uid 文本塞进 `path`）。

**改前几趟 / 改后几趟**

| | 调用趟数 | 调用方字符串处理 |
|---|---|---|
| 改前 | `project_get_scene_dependencies` → `project_convert_uid_to_path` → 目标工具 = **3 趟**（且 `type` 仍不可用） | 0（但多一趟） |
| 改后 | `project_get_scene_dependencies` → 目标工具 = **2 趟** | **0** |

门② 实测「把 `path` 直接喂给下一个工具」：`project_read_resource(path = dependencies[0].path)` → `{"loaded":true,"path":"res://main.gd","type":"GDScript"}`，`code=0`。

### 3.2 E-3（`serialize_variant` 的形状）

**现状（改前；红阶段 doctest 实测 `get_type()==4` 即 STRING）**

```
v4   = "(5.0, 6.0, 7.0, 8.0)"        // String
pv2  = "[(1.0, 2.0)]"                // String
pv4  = "[(1.0, 2.0, 3.0, 4.0)]"      // String
position = {"x":..,"y":..}           // 同一份读回里是对象
```

**引擎正解**：`Vector4`/`Vector4i`/packed 与 `Vector2` 同为引擎值类型，模块的**唯一**序列化器就是 `serialize_variant`（`tools/tool_helpers.cpp:94-`；调用面见 §2 注释）；同族同形是 GDR-25 §23.1 规则 4 的可执行判据；packed 的「元素形状 = 元素单独的形状」正是写侧 `coerce_to_property_type` 的元素闸门所接受的形态（`_container_element_type`/`_container_element_slot`，`tool_helpers.cpp:869-949`）。

**改后（门② 线上实测；**编辑器侧与游戏侧逐字一致**）**

```jsonc
{"v4":{"w":4.5,"x":1.5,"y":2.5,"z":3.5},
 "v4i":{"w":4,"x":1,"y":2,"z":3},                         // 整数分量，与 Vector2i 同形
 "rect_i":{"height":40,"width":30,"x":1,"y":2},
 "pv2":[{"x":1.0,"y":2.0},{"x":3.0,"y":4.0}],
 "pv4":[{"w":4.0,"x":1.0,"y":2.0,"z":3.0},{"w":8.0,"x":5.0,"y":6.0,"z":7.0}],
 "bytes":[1,200],  "ints":[7,-3],  "names":["a","b"],  "floats":[0.5,1.5],
 "colors":[{"a":1.0,"b":0.0,"g":0.0,"r":1.0},{"a":1.0,"b":0.0,"g":1.0,"r":0.0}]}
```

**形状表（as-built；写进源码注释与 `tool_helpers.h` 的文档注释，规范章节由决策者维护）**

| Variant 类型 | 改前 | 改后 |
|---|---|---|
| `VECTOR2/2I/3/3I` | `{x,y[,z]}` | 不变 |
| `VECTOR4` / `VECTOR4I` | `toString()` 字符串 | `{x,y,z,w}`（分量类型随引擎：int / float） |
| `COLOR` | `{r,g,b,a}` | 不变 |
| `RECT2` / `RECT2I` | `{x,y,width,height}` / 字符串 | 不变 / `{x,y,width,height}`（同族补齐） |
| `PACKED_BYTE_ARRAY` | 字符串 | **整数数组**（理由见下） |
| `PACKED_INT32/INT64/FLOAT32/FLOAT64/STRING_ARRAY` | 字符串 | 元素自身形状的数组（int / float / string） |
| `PACKED_VECTOR2/VECTOR3/VECTOR4/COLOR_ARRAY` | 字符串 | 元素对象的数组（`{x,y}` / `{x,y,z}` / `{x,y,z,w}` / `{r,g,b,a}`） |
| 其它（`Transform2D/3D`、`Basis`、`Quaternion`、`Plane`、`Projection`、`AABB`、`RID`、`Callable`、`Signal`） | 字符串 | **仍为字符串**（本批未处理：模块目前没有任何工具读回这些类型；见 §8） |
| `NIL/BOOL/INT/FLOAT/STRING/STRING_NAME/NODE_PATH`/`OBJECT`/`ARRAY`/`DICTIONARY` | 原样 | 不变 |

**`PackedByteArray` 的形态理由**：给定**整数数组**（不是 base64 / hex 字符串）。① 与全部其它 packed 的「数组 vs 数组」形状规则一致（GDR-25 §23.1 规则 4）；② 它**就是写侧接受的形态**（`_container_element_type(PACKED_BYTE_ARRAY) = INT` + `ValueSlot::UINT8`），因此字节缓冲**零编码步骤往返**——门② 实测 `bytes = [1,200]` 原样写回成功；③ 可复现性：base64 依赖调用方再做一次解码，而这正是本批要消灭的「字符串手术」。

**可喂回（门② 实测）**：`v4`/`pv4`/`bytes` 的读回对象**原样**写回 `editor_set_node_property` / `running_game_set_node_property` 均 `code=0`，`new_value` 与读回逐字相同。

## 4. 红/绿证据（真实输出）

**红阶段**（旧实现 + 最终测试文本；`--headless --test --test-case="[MCPServer]*" --mcp-port=0`）

```
[doctest] test cases:  201 |  196 passed |  5 failed | 1429 skipped
[doctest] assertions: 7921 | 7882 passed | 39 failed |
[doctest] Status: FAILURE!          （exit=1）
```

失败逐条（节选，完整见 log）：

```
.\modules/mcp_server/tests/test_mcp_server.h(2536): ERROR: CHECK( (String)dep["uid"] == "" ) is NOT correct!      values: CHECK( <null> ==  )
.\modules/mcp_server/tests/test_mcp_server.h(2540): ERROR: CHECK( (String)dep["type"] == "Resource" ) …          values: CHECK(  == Resource )
.\modules/mcp_server/tests/test_mcp_server.h(2624): ERROR: CHECK( (String)dep["type"] == "Resource" ) …          values: CHECK( res://mcp_server_test_fixture/resources/used.tres == Resource )
.\modules/mcp_server/tests/test_mcp_server.h(2626): ERROR: CHECK( (String)dep["path"] == resource_path ) …       values: CHECK( uid://c7mt5x5j361vt == res://mcp_server_test_fixture/resources/used.tres )
.\modules/mcp_server/tests/test_mcp_server.h(13750): ERROR: CHECK( p_serialized.get_type() == Variant::DICTIONARY ) values: CHECK( 4 == 27 )
      logged: Vector4: the value is a String, not an object
.\modules/mcp_server/tests/test_mcp_server.h(13828): ERROR: CHECK( p_serialized.get_type() == Variant::ARRAY ) values: CHECK( 4 == 28 )
      logged: PackedByteArray: the value is a String, not an array   （11 个 packed 各一条）
```

**绿阶段**（新实现；同一二进制自报 `928af5d3d` == HEAD）

```
[doctest] test cases:  201 |  201 passed | 0 failed | 1429 skipped
[doctest] assertions: 8021 | 8021 passed | 0 failed |
[doctest] Status: SUCCESS!          （exit=0）
```

**基线**：REPORT-024a 为 197 例 / 7861 断言 → 本任务 **+4 例 / +160 断言**（4 个新用例；1 个既有用例被更新，见 §7）。

**一次真实的假绿（已修，记录在案）**：绿阶段首跑 1 例失败——`CHECK( (String)out[1] == String::utf8("中文") ) values: CHECK( ä¸­æ == 中文 )`。根因：测试里用了裸 `push_back("中文")`，而 `String(const char*)` **按 Latin-1 读字节**，两侧表示不同形。已改为 `String::utf8("中文")` 并在测试里写明（PLAYBOOK §7.5 的同类陷阱）。

## 5. 六道门（全部在 `--version == HEAD == 928af5d3d` 的二进制上重跑）

| 门 | 命令 | 结果 | exit | log（%TEMP%）/ sha256 |
|---|---|---|---|---|
| ⓪ 构建 | `scripts\build_local.cmd`（`tests=yes`） | `exit code = 0`；`--version = 4.8.dev.custom_build.928af5d3d` == `git rev-parse --short HEAD`(928af5d3d8) | 0 | `mcp_server_build_local.log` |
| ① 契约子集逐字 | `check_contract_subset.ps1 -Group project_read_analysis` | **3/3 PASS**：编辑器 9888 **91 工具**、游戏 9889 **53 工具**；本组 7 个工具 name/description/inputSchema 两端口**逐字 True**；implemented=113 / contract=171；`[PASS] guard_user_port_9877 pid 36392→36392` | 0 | `b_gate1.log` `f0b25a8e…` |
| ② 三类证据 + 跨工具链 | `mcp024b_ergonomics_batch2_evidence.ps1` | **68/68 checks passed** | 0 | `c_evidence.log` `64140755…`；证据目录 `%TEMP%\task024b-ergonomics\evidence`（75 个请求/响应文件 + `evidence.log.txt` `1cc2e70b…`） |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **201/201 passed / 8021/8021 断言 / 0 failed / SUCCESS!** | 0 | `mcp024b_green_module3.log` `a6bb2d2c…` |
| ④ 全引擎回归 | `--headless --test` | **1627/1627 passed / 432303/432303 断言 / 0 failed / SUCCESS!** | 0 | `b_gate4_full.log` `84eb31d4…` |
| ⑤ 批次收口 | `accept_m1.ps1` **连跑两次** | 两次 **22/22 cases passed**；两次 PASS 清单**逐字相同**（脚本比对 `identical=True`，0 FAIL） | 0 / 0 | `b_gate5_run1.log` `3352efe2…`、`b_gate5_run2.log` `581800a5…` |
| ⑥ 收窄点清单（GDR-24） | `python scripts\check_narrowing_points.py` | **扫描 29 点 / 全部已标注并登记**：`PASS: every narrowing point of the module is annotated and pinned` | 0 | `b_gate6.log` `591294e7…` |

**红/绿 log**：`mcp024b_red_module2.log` `d09c2b8d…`（红）；`mcp024b_green_module3.log` `a6bb2d2c…`（绿，HEAD 绑定）。

**构建绑定说明（防空绿/假红，R-1）**：门①–⑥ 均在**重新构建并对上 `--version`** 之后运行。代码提交 `928af5d3d8` 之前的一次构建自报 `94718bc7a`（= 上一个 HEAD）；两份二进制的**编译输入完全相同**（`git diff --name-only 94718bc7a6..HEAD` 仅 6 个文件，其中 4 个是我改的实现/测试文件，2 个是不参与编译的脚本），因此重建后只变了 `version_hash.gen.cpp` 里的 hash，门③/④ 数字与重建前一致（201 / 8021；1627 / 432303）。

## 6. 门② 三类证据（真实请求/响应）与不可构造类声明

对**输出面被改动的三个工具**各给三类（success / 缺参 -32602 / 底层失败 -32001）：

| 工具（端口） | 成功 | 缺参 | 底层失败 |
|---|---|---|---|
| `project_get_scene_dependencies`（9888） | `E1a/E1b/E1c`：两个场景 + 保存后的 uid 场景（见 §3.1） | `E1d_deps_missing_param` → `-32602`（`Missing required parameter: path`） | `E1d_deps_missing_file` → `-32001` + `data.suggestion` |
| `editor_get_node_properties`（9888） | `E3b_read_editor`：10 个属性全部按新形状读回 | `E3d_editor_missing_param` → `-32602` | `E3d_editor_missing_node`（`NoSuchNode`）→ `-32001` + 建议 |
| `running_game_get_node_properties`（9889） | `E3e_read_game`：与编辑器侧**逐字相同**的形状 | `E3g_game_missing_param` → `-32602` | `E3g_game_missing_node` → `-32001` |
| 写侧往返（新增受影响的工具面） | `E3c_*`（编辑器）/ `E3f_*`（游戏）：读回原样写回 `code=0` 且 `new_value` 相同 | — | `GAP_*`（见 §8，两处**显式残留缺口**，实测 `-32602`，非本批缺陷） |

**不可构造类声明**：本批无需声明「不可构造」的三类——三个工具的成功/缺参/底层失败都真实构造并执行了。唯一**不构造**的是「`project_get_scene_dependencies` 的 `path` 无法解析」这一分支：要让「标签有 `uid=` 且没有 `path=` 且注册表也没有该 id」同时成立，需要一个引擎不会写出的场景文件；该分支由源码与 doctest 的 uid 场景（注册表为空 → `scene_path`）覆盖，`unresolved` 分支**只有源码级证据**（已在报告中标注为源码级，不当作实测）。

**零字符串手术链（GDR-25 §23.1，≥4 步；门② 第 4 节实测，逐步标注）**

```
1 project_get_scene_dependencies -> .dependencies[0].path = 'res://main.gd'                     (string ops: 0)
2 project_read_resource(path = step1 .path) -> .path='res://main.gd', .type='GDScript'          (string ops: 0)
3 project_convert_path_to_uid(path = step1 .path) -> .uid='uid://bhcm8edoqs7m0'                 (string ops: 0)
4 editor_get_node_properties -> .v4={w:4.5,x:1.5,y:2.5,z:3.5}, .pv4=[{…},{…}], .bytes=[1,200]   (string ops: 0)
5 editor_set_node_property(value = step4 .v4) -> code=0, .new_value={w:4.5,x:1.5,y:2.5,z:3.5}    (string ops: 0)
6 running_game_get_node_properties -> .v4/.pv4/.bytes 与 step4 逐字相同                        (string ops: 0)
```

调用方**字符串处理次数合计 = 0**（脚本里没有 `.Split/.Replace/.Substring/.Trim`，也没有用 `-match` 从响应文本里抠字段；每一步只做属性访问）。**本批如何把它从 >0 降到 0**：改前 step1 的 `.path` 是 `uid://…`，调用方要么再走一趟 `convert_uid_to_path`（多趟），要么做 `Substring/Replace`（字符串手术）才能进 step2；step4 的 `.v4/.pv4` 在改前是字符串 `"(5.0, 6.0, 7.0, 8.0)"`，喂回 step5 前必须自己解析。现在两者都是可直接使用的字段。

## 7. 受形状变更影响的既有测试 / 证据脚本清单

| 类别 | 项 | 处置 |
|---|---|---|
| doctest | `[MCPServer] project_get_scene_dependencies reads the ext_resource list`（原断言 `CHECK((String)dep["type"] == "")`，即旧口径的「类型恒空串」） | **已更新**：改为断言 `type=="Resource"`、`declared_type=="Resource"`、`uid==""`、`path_source=="scene_path"`（新口径） |
| doctest | 新增 4 例：`TASK-024b E-1/G-2: a uid-bearing ext_resource …`、`… Vector4/Vector4i/Rect2i answer objects …`、`… every packed array answers an array …`、`… the read-back shape is accepted back by the write path` | 新增（红→绿） |
| doctest | **其余全部既有用例**：门③/门④ 全绿证明**没有任何**旧用例断言过 `Vector4`/packed 的字符串形状（否则会红） | 无需改动（以全量跑绿为证） |
| 证据脚本 | 静态检索（`\bpoints\b|\.bytes|PackedVector|PackedColor|PackedString|Vector4|\(5\.0, 6\.0` 等）**未发现**任何脚本把序列化后的 packed/`Vector4` 值**与字符串比较**；断言的都是 `code`、`-32602` 消息、场景 sha 或 `Vector2/Vector3` 的 `position` 字段 | 无需断言改动 |
| 证据脚本（打印面变化） | `mcp021_remaining_silent_value_surfaces_evidence.ps1` 的 `C1/C3/D1/E1/F1/G1/H1` 把 `project_set_setting` 的读回 `value` 打进日志（改前是字符串、改后是数组/对象）；断言只检查 `code`/`!= '<null>'` | **实测复跑**：mcp021 全跑一遍（除它自己的 `gate_version_matches_head` 因随后提交 HEAD 前移而 FAIL 外）**无其它 FAIL**；该 FAIL 是脚本的「版本==HEAD」自检，与本次形状无关 |
| 证据脚本（本批新增） | `scripts/mcp024b_ergonomics_batch2_evidence.ps1`（新文件，68 checks） | 新增 |

## 8. 残留缺口与新发现（**未**越权修复；交决策层裁定）

1. **E-3 的写侧一半**（本批范围内**只改读形状**，任务书限定「只改输出/取数」）：
   * 读侧现在把 `Vector4i`/`Rect2i` 答成对象，但写侧 `vector_component_hint`（`tools/running_game_node_write.cpp:190-205`）**没有 `VECTOR4I`/`RECT2I` 条目**（也没有 `VECTOR2I/VECTOR3I` 之外的 rect 族），因此 `shape_vector_from_json` 不会为它们做分量整形，`coerce_to_property_type` 以 `can_convert(DICTIONARY→Vector4i/Rect2i)=false` 拒绝。
   * **实测**（门② `GAP_*`）：`editor_set_node_property(v4i = 读回对象)` → `-32602`…`does not list Dictionary -> Vector4i`；`rect_i` 同理（`Rect2`/`Rect2i` 都缺，且 **`Rect2` 的对象读形状在本批之前就存在**）。
   * **不是本批的回归**：改前读回是字符串，写侧同样不接受（`can_convert(STRING→VECTOR4I)` 也为 false），因此「读回不能喂回」的**缺口本来就存在**，本批只是把它从「字符串形态」变成「对象形态」并**实测披露**。
   * 建议：作为下一小批（可在 E-3 的延续或 B5 顺手性批次）给写侧分量表补 `VECTOR4I`/`RECT2I`（`vector_from_dictionary`/`_component_fits_slot` 同族）；**需要动写侧实现**，超出本任务书范围。
2. **`scripts/check_narrowing_points.py` 的引脚实际按「行号」匹配，而其自身文档注释写的是「按 (file, marker id, 出现顺序) 匹配、行号漂移不算失败」**（`report()` 用 `PINNED[file][point["line"]]` 查表）。
   * 后果：任何在引脚点**上方**的无关改动都会让门⑥ 报 `UNLISTED` 假红。本批的 E-3 分支插在 `serialize_variant`（位于 `value_fits_slot` 上方）就触发了：`FAIL: tools/tool_helpers.cpp:986 G24-THE-GATE`。
   * 处置：**只更新引脚行号**（`851 → 986`，两处：字典键与 `_pin` 的行号字段），未削弱任何检查；门⑥ 随即 PASS。**这是门脚本自身的实现/文档不一致，建议决策层修**（改为按 marker+顺序 索引，或把「按行号」写进注释）。

## 9. 本批后仍未处理的顺手性项

`E-2 + E-8`（`editor_get_scene_tree` 的编辑器内部绝对路径）、`E-6`（日志工具读共享文件/来源进程）、`E-9`（`project_read_resource` 不给内容）、`G-1`（无子属性路径）、`G-3`（`clear` 默认删共享报告文件）、`G-4`（同族返回形状不一致——本批只闭合了值序列化这一面）、`E-10`（已在 TASK-024a 完成）。另：`E-3` 的**写侧**（§8.1）与「矩阵/Transform 族仍为字符串」（§3.2 表末行）。

## 10. 本批改动文件的 sha256

| 文件 | sha256 |
|---|---|
| `tools/tool_helpers.cpp` | `3ace4c1fb9d6d997e21b5b228247a91d38ae4039c1fdcaa0a806e2ac38a4196b` |
| `tools/tool_helpers.h` | `bb01de49cc003b22d634c07bb245953ee3af8cab520da7f94e5c283564606cbd` |
| `tools/project_read_analysis.cpp` | `6cab897a787460f42f8ef077088182a5aca500f98a12d9889ac22a7f40e0b8ad` |
| `tests/test_mcp_server.h` | `74264a12612755e01907c6e32d8613a7fcd3fdba8b02108db219eb7652ecbbe6` |
| `scripts/mcp024b_ergonomics_batch2_evidence.ps1` | `996a524b6a156a22ede2361d93038c8542eb97000df406f7cffe3fabb5de00ec`（**产生 68/68 那次运行所用版本**；首个提交 `928af5d3d8` 里的版本为 66 checks，其后只追加了 §8.1 的两条 `GAP_*` 实测检查，未改任何既有断言） |
| `scripts/check_narrowing_points.py` | `74c1fdd754fd31211d0299554321afc46ad5d55e646eab2758f40f12edc3d3e5` |

> 契约/生成器**未改**：`docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、`docs/tool-groups*.json` 与三个生成器均未触碰，故契约 sha / 文档指纹不变（门① 逐字 PASS 为独立证据）。

## 11. deviations（与手册/任务书的任何偏离，逐条显式列出）

1. **`Rect2i` 也加了显式分支**（任务书字面只点名 `Vector4/Vector4i` 与「全部 packed」）。理由：`Rect2i` 与 `Rect2` 是同族（`Rect2` 改前即为对象），把 int 双胞胎留在字符串形态就是本项要修的「同族不同形」（GDR-25 §23.1 规则 4）。**未扩到** `Transform*`/`Basis`/`Quaternion`/`Plane`/`Projection`/`AABB`（§3.2 表末行已如实登记为未处理）。
2. **输出新增 3 个字段**（`uid`、`declared_type`、`path_source`）：任务书要求「`type` 必须是真实类型；`path` 与 `uid` 都要给出（**或**让 `path` 直接是 `res://…`）」并要求写清 fallback 语义；把三者都显式给出是**唯一**能让调用方零猜测、且让「fallback」这一引擎语义可被机器判读的形态。**`inputSchema` 未改**，门① 逐字 PASS。
3. **保留 `path_source="scene_path"` 这一分支**（而不是在 UID 不可解析时报错）：引擎自身在 `uid` 可读但注册表无该 id 时也会退回标签里的 `path`（`resource_format_text.cpp:949` 的 `fallback_path`），此处与引擎语义一致并如实标注来源。
4. **`type` 采取「loader 真实类优先、标签类型兜底」**：对导入资源（如 `.png`）`get_resource_type` 返回空串（`compressed_texture_resource_format.cpp:57-62` 只认 `.ctex`），此时回落到标签类型（`Texture2D`），否则 `type` 会凭空丢失；两个答案都给出，差异在响应里可见。
5. **门⑥ 的引脚行号被更新**（`851 → 986`）：见 §8.2，只改行号未改判定；同时在脚本注释里记录「实际按行号索引」。
6. **测试里的一处写法修正**：`PackedStringArray` 的中文元素必须 `String::utf8(...)`（`String(const char*)` 按 Latin-1 读字节），已在测试注释里写明。
7. **证据脚本自带「版本==HEAD」自检**：重跑既有 `mcp021` 时该自检因提交使 HEAD 前移而 FAIL，其余全绿；本批自身证据脚本的所有门运行都在 `--version == HEAD` 时执行（§5）。

## 12. blockers

**无**。（未遇到网络/依赖/工具阻塞；未安装依赖；未访问 `100.105.152.101:18080`。）

## 13. next_step_recommendation

1. **交独立验收子代理**按本报告与门证据复核（重点：E-1 的 `type`/`path` 语义、E-3 两端形状、§8.1 的写侧残留缺口是否被误当成本批成果）。
2. 建议下一小批（顺手性批次 3）按「一个上下文装得下」的粒度拆：
   * **E-3 写侧**：给 `vector_component_hint`/`_check_components` 补 `VECTOR4I`/`RECT2I`（+ `Rect2`），使本批的读回对象**真正**可喂回；
   * **E-2 + E-8**（编辑器路径口径）单独一批；
   * **E-6**（日志来源进程）单独一批。
3. **决策层**：修 `check_narrowing_points.py` 的引脚索引方式（§8.2）；若希望在规范里登记 E-3 的形状表，请由决策者写入 `DESIGN-DETAIL.md`（本报告只提供 as-built 表，未自行写规范）。