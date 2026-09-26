# REPORT-040 — 修复实机试测发现的 3 条真缺陷（D-1 / D-2 / D-3）+ 同类系统排查

> 任务书：`docs/tasks/TASK-040-racing-defect-fixes.md`；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 证据原文：`docs/reports/RACING-FINDINGS.md` §4。本报告只报告**模块**的改动与证据；
> 未改 `docs/DESIGN-DETAIL.md`，未改契约/映射/生成器（`docs/tools_list.renamed.json` sha256 与 RACING-FINDINGS §0.2 逐字相同），
> 未新建任何竞争性规范文档（PLAYBOOK §7.2）。

---

## 0. 结论速览与锚点（D86）

| 项 | 值 |
|---|---|
| 仓库 / 分支 | `F:\RustProjects\godot-mcp-pro\code\godot` / `feature/mcp-server-module`（未 push） |
| **红基线 HEAD**（三条缺陷的复现测自它） | `6afe08746a5d3cc342b006e61020c13821208c20`（短 `6afe08746a`，引擎自报 `4.8.dev.custom_build.6afe08746`） |
| **修复提交（三条缺陷的代码锚点）** | `8e35a95b94` — `mcp_server: TASK-040 fix the three racing defects (D-1 property gate, D-2 CONNECT_PERSIST+persisted, D-3 named-read consistency)` |
| **证据/脚本提交** | `67e7dbe7c6`；其相对 `8e35a95b94` 在 `modules/mcp_server/tools`、`modules/mcp_server/tests` 上的 diff **为空**（`git diff --stat 8e35a95b94..HEAD -- modules/mcp_server/tools modules/mcp_server/tests` 无输出），即**被测代码 = 修复提交** |
| **本报告提交** | `b416588b8a`（只加本文件；同样在 `tools`/`tests` 上 diff 为空） |
| 门的引擎自报版本 | `4.8.dev.custom_build.8e35a95b9` / `4.8.dev.custom_build.67e7dbe7c` / `4.8.dev.custom_build.b416588b8`（三次重建各自 == 当时的 `git rev-parse --short=9 HEAD`；三次测的是同一份代码，见 §8.4） |
| 契约 sha256 | `C844EC8AF9EF00D2E6EC7008C9806B3E2B16757E78794D3CCCA0704EDF844256`（110 770 B，**未改**） |
| 组清单 sha256 | 未改（三个受影响组：`editor_write_scene_editor` / `editor_node_write` / `running_game_observation`） |
| 三条缺陷的最终状态 | **D-1 已修**（有前置存在性检查 + 类别检查 + 读回）；**D-2 已修**（`CONNECT_PERSIST` + 响应 `persisted` + 断开测过）；**D-3 已修**（选「与写侧一致」`-32001`） |

**门结果一句话**：门① 3/3 组各 3/3 PASS；门② 47/47 PASS（含三类证据）；门③ 276/276；门④ 1702/1702；
门⑤ `accept_m1.ps1` 连跑两次、**PASS 清单一致**（唯一失败项 `guard_user_port_9877` + `case13_game_without_port`，均为环境项，见 §8.5）；
门⑥ 三段式 71/71 pinned + 101/101 探针；赛车工程端到端回归 35/35（§8）；
回归脚本群两轮：二轮 416 条检查 409 PASS，7 条失败**全部**是同一类「用户 Godot 在 9877 上」的环境断言（§9）。

---

## 1. 交付面

### 1.1 提交

| sha | 说明 |
|---|---|
| `8e35a95b94` | 修复 + 红绿 doctest（8 个文件，+539/−46） |
| `67e7dbe7c6` | 证据与回归脚本（两个 `.ps1` + `docs/reports/evidence/task040/**`，25 个文件，+1 515） |

> 本任务的**红态**（两条抽取 + 4 个失败用例）与**绿态**在同一提交里收口：红/绿两阶段都跑了**真实构建**，
> 红态的真实输出见 §2.1/§3.1/§4.1 与 `docs/reports/evidence/task040/red/doctest-red.log`，
> 绿态真实输出见 §8.4。中间态（只做抽取、行为不变）没有单独落一个提交——这一点在 §12 `deviations` 里显式声明。

### 1.2 改动文件与 sha256

| 文件 | 字节 | sha256 | 改动 |
|---|---|---|---|
| `tools/tool_helpers.h` | 66 541 | `cec7835da7dbcd2d986a37e64f031476ef1d70d6eff5a49225119509c0bf4769` | 新增 `MCPTools::assign_resource_to_property` 声明 + `class Resource;` 前向声明 |
| `tools/tool_helpers.cpp` | 114 881 | `d3a2abd28f7c879b75e28a77585d9c2b322b10a1cb6286cba04888ead409f685` | D-1 的闸门实现（存在性 `-32001` / 类别 `-32602` / 读回 `-32000`） |
| `tools/editor_write_scene_editor.cpp` | 49 708 | `7e185368c0b9af67d12ccb8daf2f80948e93428d6102612dfdf63149b21bdd98` | 697 行的裸 `node->set()` 换成 `assign_resource_to_property()`（706 行） |
| `tools/editor_node_write.h` | 9 170 | `16c1639a88013e1bec687242ebe79c15f34ea15daef1fe09416d04f1d86c2f0f` | 两个 helper 的签名 + 语义说明 |
| `tools/editor_node_write.cpp` | 53 412 | `b9d3eb777a27171884ec856e0fee431f1f0937cb19fde5e1d52193651bfb82e3` | D-2：`_connection_is_persistent()`（242）、`connect(..., CONNECT_PERSIST)`（288）、`persisted`（909）、`was_persistent`（1006） |
| `tools/running_game_observation.h` | 5 247 | `7851b2a43d203104da8e1e0f1c6fba1026e31460224827082d9f1449b203a109` | 新增 `MCPTools::read_named_properties` 声明 |
| `tools/running_game_observation.cpp` | 44 103 | `67d49a3083bc593b74b5d4ef047554982dd5ba38a1e08769065bbc85e691667b` | D-3：`read_named_properties`（153，闸门在 175）+ 四个调用点传播 |
| `tests/test_mcp_server.h` | 945 278 | `fc56b76eabe8f9bed38c7c276021bcb9f92943e142ba036f7fb0a1618c51c204` | 4 个新用例（TASK-040 组）+ 旧签名调用点更新 + 1 个新 include |
| `scripts/mcp040_defect_probes.ps1`（新） | 32 005 | `95de255ffc8f1eaeadf984c316226a6286517044c546122c1675a2efcdcecf0a` | 门槛 0/② 的红绿探针（纯 ASCII） |
| `scripts/mcp040_racing_regression.ps1`（新） | 27 474 | `1151a95fda3f624b0612b62a3a98bdcd5ecf2ea57345334bf775f1444b539d98` | 赛车工程端到端回归（纯 ASCII） |
| `docs/reports/evidence/task040/**`（新） | — | 见 `docs/reports/evidence/task040/README.md`（32 个文件的字节数 + sha256） | 红/绿原始响应体 + 门日志 + 回归归因 |

### 1.3 三条缺陷的根因与修法（速览）

| # | 根因（红） | 修法（绿） |
|---|---|---|
| D-1 | `editor_write_scene_editor.cpp:697` 裸 `Object::set()`；`:699-703` 无条件回显成功形状 | 抽出 `assign_resource_to_property()`：`object_has_property` → `-32001`+suggestion；`property_type_of != OBJECT` → `-32602`；`_object_fits_declared_class` 拒绝 → `-32602`+suggestion；写后读回不等 → `-32000` |
| D-2 | `editor_node_write.cpp:257` `connect()` 未传 `CONNECT_PERSIST`；`packed_scene.cpp:1238` 只序列化带该位的连接 | 连接一律带 `CONNECT_PERSIST`（已存在但非持久的连接**重连**升级）；响应 `persisted` 从**活的** `Object::Connection` flags 读回；断开路径加 `was_persistent` |
| D-3 | `running_game_observation.cpp:194` 无条件 `serialize_variant(get(name))`，缺失名回 `null`+`ok` | `read_named_properties()` 先问 `object_has_property`，缺失名 `-32001`+suggestion（与写侧同词形）；batch 走逐项 `error` 条目 |

---

## 2. D-1 红 → 修全程

### 2.1 红（实测，`6afe08746a`）

探针 `mcp040_defect_probes.ps1 -Label base`，探针工程：`Main`(Node2D) / `Car`(CharacterBody2D) / `Button`(Button)。

```
[A02_add_resource_on_missing_property] port=9888 bytes=177 sha256=2b7dc6cd14c5de9564ac6b024845c4f12dc9385ddce8b552607c0c7d7b9f760a
       {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"node_path\":\"Car\",\"property\":\"physics_material_override\",\"resource_type\":\"PhysicsMaterial\"}","type":"text"}]}}
[FAIL] D1_add_resource_on_missing_property_refused   code=0 (want -32001) message='' suggestion=''
[FAIL] D1_add_resource_refusal_names_the_property    message=''
[FAIL] D1_add_resource_refusal_has_suggestion        data.suggestion=''
[FAIL] D1_add_resource_success_shape_has_old_new     payload={"node_path":"Car","property":"physics_material_override","resource_type":"PhysicsMaterial"}
[A01_read_physics_material_override] bytes=243 sha256=28983499f5d55b14d8cf73af6e78ab8727b992bf1a427007667f2de61055407d
       {"error":{"code":-32001,...,"message":"Property 'physics_material_override' on node 'Car' not found"},...}
```

第二条通道（**类型/类别不接受**）同样报成功，而读回是空的：

```
[A03_add_resource_wrong_category] bytes=156 sha256=3b52d7e24a4c3d80bdd2e7ee35b14fd543081d2e77669e03b345653066e6aa2c
       {"result":{"content":[{"text":"{\"node_path\":\"Button\",\"property\":\"material\",\"resource_type\":\"Gradient\"}"...
[FAIL] D1_add_resource_wrong_category_refused  code=0 (want non-zero)
[A04_read_button_material] bytes=154 ...  {"properties":{"material":null},"type":"Button"}
```

doctest 红（同一构建，`%TEMP%\mcp040\doctest_red.log` → `evidence/task040/red/doctest-red.log`）：

```
.\modules/mcp_server/tests/test_mcp_server.h(8487): ERROR: CHECK_FALSE( MCPTools::assign_resource_to_property(node, StringName("physics_material_override"), resource, error) ) is NOT correct!  values: CHECK_FALSE( true )
.\modules/mcp_server/tests/test_mcp_server.h(8488): ERROR: CHECK( error.code == -32001 ) is NOT correct!  values: CHECK( 0 == -32001 )
.\modules/mcp_server/tests/test_mcp_server.h(8510): TEST CASE: ... refuses a resource the property cannot hold
.\modules/mcp_server/tests/test_mcp_server.h(8511): ERROR: CHECK( error.code == -32602 ) is NOT correct!  values: CHECK( 0 == -32602 )
[doctest] test cases:   276 |   272 passed |  4 failed | 1429 skipped
[doctest] assertions: 15864 | 15850 passed | 14 failed
```

### 2.2 修（`tools/tool_helpers.cpp:1801`）

`MCPTools::assign_resource_to_property(Object *, StringName, Ref<Resource>, MCPToolError &)`，四步：
① `object_has_property()` 缺失 → `not_found("Property 'x' on <Class>")` + `data.suggestion`；
② `property_type_of() != Variant::OBJECT` → `-32602`（属性存在但不是 Object 槽）；
③ `object_property_class_hint()` + `_object_fits_declared_class()`（**模块内既有的**引擎 `hint_string` 文法读取，TASK-027 D-8）拒绝 → `-32602` + 命名两侧类的 suggestion；
④ 写后读回，指针不等 → `-32000 tool_state`。
工具侧只留回显（`editor_write_scene_editor.cpp:706`）。

### 2.3 绿（实测，`8e35a95b9`）

```
[A02_add_resource_on_missing_property] bytes=313 sha256=ad535ec4262efe548360a8688a3bf0558dc78e03b76ab07e882511dd9ca400e2
       {"error":{"code":-32001,"data":{"suggestion":"'physics_material_override' is not a property of CharacterBody2D. Call editor_get_node_properties without 'properties' to list every property this node really has"},"message":"Property 'physics_material_override' on CharacterBody2D not found"},...}
[PASS] D1_add_resource_on_missing_property_refused
[A03_add_resource_wrong_category] bytes=447 sha256=4334713128e9b587f2ec1f2814855fd630bf4c149e1009f1288933aca035f6fa
       {"error":{"code":-32602,"data":{"suggestion":"'material' accepts CanvasItemMaterial,ShaderMaterial; ..."},"message":"Property 'material' of Button declares CanvasItemMaterial,ShaderMaterial and cannot hold a Gradient: ..."}}
[PASS] D1_add_resource_wrong_category_refused
[PASS] D1_wrong_category_left_the_slot_alone   （读回 material = null，槽确实没被写）
[PASS] D1_add_resource_good_still_ok           （同工具对能装的资源仍然成功）
[PASS] D1_good_write_is_readable_back          （editor_get_node_properties 读回 CanvasItemMaterial）
[PASS] D1_good_write_landed_in_the_scene_file  （保存后 .tscn 里有 sub_resource type="CanvasItemMaterial"）
```

Doctest 绿：`276/276`、`15875/15875`（§8.4）。

### 2.4 未做的半边（显式声明）

RACING-FINDINGS O-2/AN-1 还建议给本工具加 `old_value`/`new_value`。**本任务未做**，理由：
编辑器侧的 `editor_get_node_properties` 对 Object 值用的是**资源镜像**形状（`{"type","path","local_to_scene"}`），
而模块的单一序列化器 `serialize_variant` 对 Object 给的是 `{"type","value":<to_string()>}`；
两个形状不同，直接加会造出**第二个序列化器**（GDR-25）。这是一个需要决策层的契约/形状决定，不属于本任务三条缺陷的修复范围。

---

## 3. D-2 红 → 修全程

### 3.1 红（实测）

```
[A08_connect_signal] bytes=155 sha256=53ea1e784f234e00fae0f3f6814f709cf7082fc35d83ce06aad7d6474a39b283
       {"result":{"content":[{"text":"{\"connected\":true,\"signal\":\"pressed\",\"source\":\"Button\",\"target\":\".\"}"...
[FAIL] D2_connect_signal_reports_persisted   payload has 'persisted': False
[PASS] D2_connection_is_live_in_memory       count=1
[A10_save_scene_with_connection] bytes=125 sha256=3d27d1110cc6e2521facad213cf00dfee1b715e53dfade0aa5cf14d9e09f90c7
NOTE   main.tscn after save: bytes=379 sha256=130fa3abcc68de5255fe7aa8c2e04b57fb7a0d271fe87c0e0f6bd826b8c52cd1 [connection] count=0
[FAIL] D2_connection_is_on_disk
[B01_list_connections_after_restart] bytes=105 sha256=2d231ce499d69d0dd3def3a2f6c2318e5a2d71314e77cec78cebd401c7b9641f
       {"result":{"content":[{"text":"{\"connections\":[],\"count\":0}"...
[FAIL] D2_connection_survives_a_restart     count=0
[FAIL] D2_analyze_signal_flow_sees_the_persistent_connection   {"nodes":[],"scene":"res://scenes/main.tscn","total_nodes":0}
[B03_disconnect_signal] bytes=222 sha256=e1cb85a6e65f2292bf26ccf7c5cb8eba29c0cf2e779ef4f5c44a4765357e4722
       {"error":{"code":-32001,...,"message":"Connection from signal 'pressed' to method 'queue_free' not found"},...}
```

（重开后连接已不存在，所以断开自然 `-32001`；这正证明「存盘即消失」。）

源码对照（红）：`editor_node_write.cpp:257` `p_source->connect(p_signal, callable);`；`grep -n CONNECT_PERSIST modules/mcp_server/tools/**` = 0 命中（与 RACING-FINDINGS §4 D-2 一致）；
引擎侧只在 `scene/resources/packed_scene.cpp:1238`（序列化）与 `:760`（恢复）使用该位。

doctest 红：
```
.\modules\mcp_server\tests\test_mcp_server.h(8548): ERROR: CHECK( (connection.flags & Object::CONNECT_PERSIST) != 0 ) is NOT correct! values: CHECK( 0 != 0 )
.\modules\mcp_server\tests\test_mcp_server.h(8559): ERROR: CHECK( connection.flags == Object::CONNECT_PERSIST ) is NOT correct! values: CHECK( 0 == 2 )
```

### 3.2 修（`tools/editor_node_write.cpp`）

1. `_connection_is_persistent()`（:242）从 `Object::get_signal_connection_list()` 按 callable 匹配读**真实 flags**；
2. 新连接一律 `connect(p_signal, callable, Object::CONNECT_PERSIST)`（:288）；
3. **已存在但非持久**的连接（脚本/旧工具建的）**disconnect + 重连**升级为持久——`already_connected` 仍为 true（调用前终态已成立），`persisted` 如实说现在的连接是什么（:274-296）；
4. 响应加 `persisted`（:909，布尔，读回值，不是「本次想传什么」）；
5. `editor_disconnect_signal` 加 `r_was_persistent`（:339）与响应 `was_persistent`（:1006）——查找用 `is_connected`（**不看 flags**），所以持久连接本来就能断开；现在这一点被测试钉住，并顺手告诉调用方「下一次保存不会再写这条 `[connection]`」。

### 3.3 绿（实测）

```
[A08_connect_signal] bytes=174 sha256=dd0995e4ae1fb950ebc225a660be178616342b656a69f6d86639947f206d0ee8
       {"result":{"content":[{"text":"{\"connected\":true,\"persisted\":true,\"signal\":\"pressed\",\"source\":\"Button\",\"target\":\".\"}"...
[PASS] D2_connect_signal_reports_persisted
NOTE   main.tscn after save: bytes=... sha256=... [connection] count=1
[PASS] D2_connection_is_on_disk
[B01_list_connections_after_restart] bytes=194 sha256=743a585ae89145ac32254b33af8f23f211b02ae22823ad8df4595db56047037d
       {"result":{"content":[{"text":"{\"connections\":[{\"method\":\"queue_free\",\"signal\":\"pressed\",\"source\":\"Button\",\"target\":\".\"}],\"count\":1}"...
[PASS] D2_connection_survives_a_restart
[PASS] D2_analyze_signal_flow_sees_the_persistent_connection   （analyze 只收 CONNECT_PERSIST，修复前恒空，修复后看得到——结论变化如实记录）
[B03_disconnect_signal] bytes=182 sha256=dea24efac564d702074fbc733c7b2843999868416d597e4bb188e25205424566
       {"result":{"content":[{"text":"{\"disconnected\":true,\"signal\":\"pressed\",\"source\":\"Button\",\"target\":\".\",\"was_persistent\":true}"...
[PASS] D2_disconnect_of_a_persistent_connection_ok
[PASS] D2_disconnect_really_removed_it
[PASS] D2_disconnected_connection_is_gone_from_disk   （[connection] count=0）
```

`editor_list_signal_connections` 与 `editor_analyze_signal_flow` 的结论变化（任务书 §2.4 要求）：

| 工具 | 修复前 | 修复后 |
|---|---|---|
| `editor_list_signal_connections` | 连接当下 `count=1`，重开 `count=0` | 连接当下 `count=1`，**重开仍 `count=1`**（它本来就收全部连接，只是连接根本没落盘） |
| `editor_analyze_signal_flow` | 重开后 `nodes:[]`（只收持久连接，而连接非持久） | 重开后看得到该连接（现在是持久连接，符合它声明过的判别点） |

这条变化**不是**行为契约的变化：两个工具的契约描述一字未改（门①逐字通过），变的只是「连接到底是不是持久连接」这一事实。

---

## 4. D-3 红 → 修全程

### 4.1 红（实测；注意：D-3 的探测**正好落在真实的赛车游戏进程上**）

探测时 9889 被 TASK-039 遗留的赛车游戏占用（pid 73176），本任务**不杀**别人的进程，于是
`editor_play_scene{mcp_port:9889}` 被拒（`-32000 mcp_port 9889 is not free ...`），而三条 `running_game_*` 调用
落在那台**真实赛车游戏**上——也就是最真实的下游：

```
[C01_game_read_missing_name] bytes=210 sha256=a9ea1f3021c46c766d3cf41df24f135bdaf3ede572cc17a20be3e571208586e8
       {"result":{"content":[{"text":"{\"node_path\":\"/root/Main/Car\",\"properties\":{\"collision_layer\":1,\"physics_material_override\":null},\"type\":\"CharacterBody2D\"}"...
[FAIL] D3_game_read_of_a_missing_name_refused   code=0 (want -32001) message='' suggestion=''
[C04_game_set_missing_name] bytes=230 sha256=ea962036f26b272d88b13e35302f6fae4e8dba93fac87f3e93478c81a6036a46
       {"error":{"code":-32001,...,"message":"Property 'physics_material_override' on node '/root/Main/Car' not found"},...}
[PASS] D3_write_side_still_refuses_the_same_name
[C03_game_read_all_properties] code=0 property_count=66   （= RACING-FINDINGS §0.2 的 66 项，该属性不在其中）
```

同节点、同名字、同端点：读侧 `ok`+`null`，写侧 `-32001`——**自相矛盾**实测成立。
契约 `running_game_get_node_properties.description`（未记载 null 语义）与 `:194` 的无条件 `serialize_variant` 相符。

doctest 红：
```
.\modules\mcp_server\tests\test_mcp_server.h(8593): ERROR: CHECK_FALSE( MCPTools::read_named_properties(node, missing, out, error) ) is NOT correct! values: CHECK_FALSE( true )
.\modules\mcp_server\tests\test_mcp_server.h(8594): ERROR: CHECK( error.code == -32001 ) is NOT correct! values: CHECK( 0 == -32001 )
```

### 4.2 修

`MCPTools::read_named_properties`（`running_game_observation.cpp:153`）在**标签跳过之后**加一道
`object_has_property(p_node, name)`（:175）→ 缺失名 `not_found("Property 'x' on node '<wire path>'")` + suggestion，
与写侧 `prepare_node_property_value`（`running_game_node_write.cpp:1158`）**同一个问句**。
四个调用点全部传播：
`running_game_get_node_properties`（-32001 整调用失败）、`..._batch`（**逐项** `error` 条目，保留它自己的逐项粒度）、
`running_game_get_autoload_node`、`running_game_find_nodes_by_script`（后两者也带 `properties` 过滤，留着宽口径会在同一个端点里再造一次自相矛盾）。

### 4.3 绿（实测；游戏子进程跑在**工具自选的空闲端口 62347** 上）

```
[C01_game_read_missing_name] port=62347 bytes=302 sha256=0f840e54a00ba9b770f3dc4928bedbadfde41e5c6c542ed76c464c4a8cde173c
       {"error":{"code":-32001,"data":{"suggestion":"Call running_game_get_node_properties without 'properties' to list every property this node has, or running_game_get_node_signals for its signals"},"message":"Property 'physics_material_override' on node '/root/Main/Car' not found"},...}
[PASS] D3_game_read_of_a_missing_name_refused
[PASS] D3_refusal_names_the_property
[PASS] D3_game_read_of_a_real_property_still_ok      （collision_layer 照常读到）
[PASS] D3_unfiltered_read_still_answers_every_property（不带 properties 的枚举路径一字未动）
[C05_game_read_batch] bytes=319 sha256=46764d459b061a37077eb2f8d1f6e654f1c266be4719bcea714b081e6d5c2025
       {"count":2,"results":[{"node_path":"/root/Main/Car","properties":{"collision_layer":1},"type":"CharacterBody2D"},{"error":"Property 'no_such_property_zzq' on node '/root/Main/Car' not found","node_path":"/root/Main/Car"}]}
[PASS] D3_batch_names_the_missing_property_per_item
```

### 4.4 D-3 的选择与理由（任务书 §3 二选一）

**选 1：与写侧一致，缺失名回 `-32001` + `data.suggestion`。** 理由：

1. **一个端点不得对同一个名字给两个相反答案**——这是任务书的推荐项，也是本缺陷的本质（不是「null 不好用」）；
2. 选 2（保留 null + 改契约描述）需要 `DESCRIPTION_OVERRIDES` + 重生成 + 指纹，会动契约 sha 与 171 条逐字门，而它换来的只是「保留一个与同端点写侧相矛盾的语义」；
3. 选 2 还要求**编辑器侧同族工具**（`editor_get_node_properties`）也把 null 语义写进契约——但编辑器侧**已经是** `-32001`（红证据 A01），照选 2 会变成「两端都写着 null、其中一端实际拒绝」，问题更大；
4. 与 `PLAYBOOK §7.7` 同向：必须能区分「拒绝」与「按引擎语义给默认值」，而 `null` 在这里既不是拒绝也不是默认值，它是一个**不存在的名字**；
5. 代价可控：这只影响**拼错的/不存在的**名字；脚本变量、引擎属性、大小写变体、标签（`PROPERTY_USAGE_GROUP/SUBGROUP/CATEGORY`）行为都不变（`read_named_properties` 保留 TASK-032 D3 的标签跳过）。

契约因此**未改**（`docs/tools_list.renamed.json` sha256 不变），不需要 override/重生成/指纹。

---

## 5. 写工具属性检查缺口全表（D-1 同类系统排查）

**方法**：把「先 `Object::set()` 再无条件回显成功」这一模式当作**可枚举**的东西——直接对所有**用户命名属性**的写入口做全量扫描：

```
grep -n -- "->set(|\.set(|set_deferred(" modules/mcp_server/tools/*.cpp      → 20 处
```

20 处逐条判定（工具名 = 该行所属工具；「前置检查」= 写之前是否问过对象）：

| # | 源码位置 | 工具 | 写的是什么 | 前置存在性检查 | 读回/分类 | 判定 |
|---|---|---|---|---|---|---|
| 1 | `editor_write_scene_editor.cpp:697`（红）→ 现 `:706` | `editor_add_resource_to_node_property` | 调用方给的 `property` | **无（红）** | 无（红） | **缺口 → 本任务修** |
| 2 | `editor_animation_tree_write.cpp:893` | `editor_set_animation_tree_parameter` | 调用方给的 `parameters/...` 名 | 有（:846-878：`found` / OBJECT 参数 / `PROPERTY_USAGE_READ_ONLY`） | 有（`_values_agree` → `changed`/`ignored`） | 合格 |
| 3 | `editor_navigation_write.cpp:225` | `editor_set_navigation_layers` | 硬编码 `navigation_layers` | 有（:213 `object_has_property`） | 有（:227 不等即 `-32000`） | 合格 |
| 4 | `editor_physics_write.cpp:122` | `editor_set_physics_layers` | 硬编码 `collision_layer/mask` | 有（:113 `object_has_property`） | 有（:124） | 合格 |
| 5 | `editor_particle_write.cpp:160` | `editor_apply_particle_preset`（`write_node_member`） | 预设表里的固定成员名（**非调用方命名**） | 不需要（名字来自模块自己的 `PRESETS`） | 有（`changed`/`ignored` + reason） | 合格 |
| 6 | `particle_shared.cpp:268` | `editor_*` 粒子预设（`process_material`） | 硬编码 `process_material` | 不需要（工具自己创建的对象） | 有（cast 回读，null 即 `-32603`） | 合格 |
| 7 | `particle_shared.cpp:450,451` | 同上（`Gradient.offsets/colors`） | 硬编码 | 不需要（新建 `Gradient`） | 有（`get_point_count()` 校验） | 合格 |
| 8 | `particle_shared.cpp:593` | `editor_set_particle_material_params` | 固定 `ParamSpec` 表的名字 | 不需要（名字来自模块表） | 有（`values_agree` → `changed`/`ignored`） | 合格 |
| 9 | `project_write_resource_scene.cpp:554` | `project_edit_resource` | 调用方给的 `properties` 键 | 有（:540 `names.has(key)` → `-32001`） | 有（:565 `_stored_value_matches_request`） | 合格 |
| 10 | `editor_node_setup.cpp:284` | `editor_setup_collision_shape` | 硬编码 `"shape"` | 不需要（新建的 `CollisionShape2D`） | 有（`shape_set`） | 合格 |
| 11 | `editor_node_setup.cpp:367` | `editor_setup_world_environment` | 硬编码 `"environment"` | 不需要（新建 `WorldEnvironment`） | 有（`environment_created` + 读回） | 合格 |
| 12 | `editor_node_setup.cpp:506` | `editor_setup_navigation_region` | 硬编码 `navigation_mesh/navigation_polygon` | 不需要（新建 region） | 有（`assigned` 读回三个字段） | 合格 |
| 13 | `running_game_node_write.cpp:969` | `running_game_set_node_property`（单名分支） | 调用方给的属性名 | 有（`prepare_node_property_value:1158`） | 有（调用方读回；TASK-014 D-1） | 合格 |
| 14 | `running_game_navigation_write.cpp:470,474` | `running_game_move_player_to_target` | 硬编码 `"rotation"` | 有（`Object::cast_to<Node3D/Node2D>` 守卫） | n/a（引擎相位播报用） | 合格（非属性名面） |
| 15 | `shader_shared.cpp:174` | `editor_set_shader_material` / `running_game_*` 材质槽 | `material_slot`（先 `material_slot_exists()`） | 有（:161 `material_slot_exists`） | 有（:177-186 指针读回） | 合格 |
| 16 | `editor_node_write.cpp`（无直接 `set()`） | `editor_set_node_property` / `editor_add_node.properties` | 调用方给的属性名 | 有（共享 `write_node_property` → `prepare_node_property_value`） | 有（`old_value`/`new_value`） | 合格 |
| 17 | `editor_node_batch_write.cpp`（无直接 `set()`） | `editor_set_node_property_batch` | 调用方给的属性名（可带路径） | 有（TASK-028：`node_property_path_exists` 全量预检） | 有（全或无 + 回滚） | 合格 |
| 18 | `editor_control_layout_write.cpp`（无直接 `set()`） | `editor_apply_control_preset` / `editor_set_control_layout` | 调用方给的属性名 | 有（走 `write_node_property`/`apply_node_properties`） | 有 | 合格 |
| 19 | `editor_tilemap_write.cpp`（无直接 `set()`） | `editor_set_tilemap_cell` 族 | 数据破坏面，走专用 setter | n/a（不按属性名写） | 有（B5 的专门校验） | 合格（非本模式） |
| 20 | `project_write_resource_scene.cpp:332,433,671` | `project_create_resource` / `project_create_scene_file` / `project_edit_*` | 调用方给的 `properties` | 有（同一个 `_write_resource_properties`） | 有 | 合格 |

**结论**：全模块只有**一处**「按调用方给的名字 `set()` 且无前置检查」的写入口，即 D-1；已修。
其余 19 处要么有前置检查、要么名字不来自调用方、要么有读回分类。
（`running_game_set_node_property` 的同类缺口 TASK-014 D-1 已修，本表第 13 行确认它仍带着检查。）

---

## 6. 持久化写操作排查表（D-2 同类排查）

口径：**「这个写操作要不要在进程/场景重开后仍然存在？它现在的答案是诚实的吗？」**

| 工具（族） | 落点 | 现在是否真的落盘/可重开复原 | 响应是否诚实 | 判定 |
|---|---|---|---|---|
| `editor_connect_signal` | 编辑场景 | **修复后：是**（`CONNECT_PERSIST` → `.tscn` 的 `[connection]`，`packed_scene.cpp:1238/760`） | 修复后 `persisted` 布尔（读回值） | **缺口 → 本任务修** |
| `editor_disconnect_signal` | 编辑场景 | 是（`is_connected` 不看 flags，持久连接同样能断） | 修复后 `was_persistent` | 补诚实字段 |
| `editor_add_input_action` | 编辑器进程的 `InputMap` | **否**（只在编辑器进程内存里；游戏进程不存在该 action） | **是**：`"persisted": false`（`editor_input_simulation.cpp:587`） | 诚实，但能力缺口（RACING-FINDINGS M-6）；本任务不改行为 |
| `editor_set_node_property` / `editor_add_node` / `_batch` / `duplicate` / `reparent` / `rename` / `delete` / `instantiate` | 编辑场景内存 | 是（节点 `owner` 已设 → `editor_save_scene` 会序列化；既有证据：mcp008/mcp017） | n/a（成功形状即场景状态） | 合格 |
| `editor_set_node_script` | 编辑场景内存 | 是（场景保存会写 `script = ExtResource(...)`） | n/a | 合格 |
| `editor_add_resource_to_node_property` | 编辑场景内存（子资源） | 是（绿证据：保存后 `.tscn` 出现 `sub_resource type="CanvasItemMaterial"`） | n/a | 合格 |
| `editor_*` 动画/音频/粒子/主题/物理/瓦片/着色器写 | 编辑场景/资源内存 | 是（场景或资源保存时落盘） | n/a | 合格 |
| `project_set_setting` / `project_add_autoload` / `project_remove_autoload` | `project.godot` | 是（`publish_file_atomically` + `ProjectSettings::save_custom`；失败会回滚内存值） | 是：`"saved": true`（`project_setting_write.cpp:238`、`theme_shared.cpp:223`） | 合格 |
| `project_set_node_property_across_scenes` | 场景文件 / 活动场景内存 | 两类分别处理 | **是**：逐场景 `persisted`（`:715`）+ 消息明文说「活动场景还没落盘」 | 合格（TASK-030 D1 的既有修复） |
| `project_create_resource` / `project_edit_resource` / `project_create_scene_file` / `project_delete_scene_file` / `project_create_theme` / `project_set_theme_*` / `project_create_shader` / `project_edit_shader` / `project_create_script` / `project_edit_script` | 文件（原子发布） | 是 | 是（`saved`/`changed` + sha256 级别的证据脚本） | 合格 |
| `editor_save_scene` | 文件（原子发布 + `mark_scene_as_saved`） | 是 | 是：`{"path","saved":true}` | 合格 |
| `editor_play_scene` | 子进程 | n/a（不是持久化写） | 是：`pid`/`mcp_port`/`port_source` | 合格 |
| 所有 `running_game_*` 写 | 游戏进程内存 | **不应**持久化（游戏运行期状态） | n/a | 合格（语义如此） |

**结论**：本任务修掉了唯一一处「应为持久却静默不持久」的**未声明**缺口（`editor_connect_signal`）；
剩下的 `editor_add_input_action` 是**已声明**的（`persisted:false`）能力缺口，属决策层议题（M-6），本任务不改行为。

---

## 7. 对赛车工程的端到端回归（关键回归）

脚本：`scripts/mcp040_racing_regression.ps1 -Label fix` → **35 checks，0 failed**（绿证据在 §7.2/§7.3 与 `evidence/task040/green/racing-checks.json`、`racing-regression.log`）。

### 7.1 环境事实（必须先说清）

1. `%TEMP%\mcp-racing-test\` **仍在**，`scenes/main.tscn` sha256 = `5892209c13782d417d8ef32f794bf94b7aaebcde00f40b1e75345ea8a49b7c3c`、**4 836 B、`[connection]` 计数 = 0** — 与 RACING-FINDINGS §0.2/§4 D-2 的锚点**逐字相同**（脚本第一步就断言了这一点）。
2. **我按「真实下游」复测，但用副本**：`Copy-Item` 到 `%TEMP%\mcp040-racing-fix\proj`，并删除 `project.godot` 里的 `trace_file`（避免写进原工程目录）。**原工程目录一字未改**，也**没有**杀掉占用 9889 的那台**原赛车游戏进程**（pid 73176）。
3. **本任务的被规定构建是 `module_mono_enabled=no`**（`scripts/build_local.cmd` 硬编码），而赛车工程是 C# 工程：
   - 第一轮（Phase 0，原样打开）：`editor_open_scene` → `-32001 Loadable scene 'res://scenes/main.tscn' not found`，
     `data.suggestion` = "The file exists but the editor could not open it as a scene; check its dependencies (missing scripts, resources or ext_resource paths)"
     ——**工具自己把原因说清了**（C# 脚本加载不了）。这条作为 P00 检查保留（`PASS`，即我们**复现并记录了**这个环境限制）。
   - 第二轮（Phase 1，**记录在案的适配**）：把 `.tscn` 里 **6 条** `Script` ext_resource 从 `res://scripts/X.cs` 改指到等价的 `res://scripts/X.gd` 桩
     （`Main`/`Car`/`Checkpoint`/`ChaseCamera`/`LapTimer`/`Hud`），**节点、节点名、属性、id 一律不动**；桩**刻意不自连按钮**
     （真实 `Main.cs` 的 `_Ready` 会自己 `startButton.Pressed += OnStartPressed`，那正是被这个缺陷逼出来的绕法；
     桩里去掉它，才能让「重开后还看得到连接」的结论只能来自 `.tscn`）。

### 7.2 Part A：真实赛车场景里的两条连接（TASK-039 真的这样调过）

先看**原追踪**里开发者真正做过的 9 次 `editor_connect_signal`（`%TEMP%\mcp-racing-test\trace-editor.jsonl`，本次重算）：

```
seq 170/171/172  -32001  speed_changed / checkpoint_passed / lap_completed（C# 信号是 PascalCase）
seq 173          ok      source=HUD/StartButton signal=pressed        target=.          method=OnStartPressed
seq 174          ok      source=Checkpoints/CP1 signal=body_entered   target=LapTimer   method=OnCheckpointBodyEntered
seq 225/226/227/228 ok   SpeedChanged / CheckpointPassed / LapCompleted / BodyCrossed
```

回归用**同样的两条**参数（`173`/`174`）打在适配后的真实场景上：

```
NOTE   racing main.tscn before: bytes=4681 sha256=dd055203fe6c665ae4210c71b3ff458428decf4587dd3fd14b658b67d38f81bf [connection] count=0 Script ext_resources=6
[R02_connect_start_button] ok  {"connected":true,"persisted":true,...}
[R03_connect_checkpoint_body] ok
NOTE   racing main.tscn after save: bytes=5026 sha256=d61b22115f204ab75eaa5c50e24495b6b734e74291f263633b53466b340629c6 [connection] count=2
NOTE     [connection signal="body_entered" from="Checkpoints/CP1" to="LapTimer" method="OnCheckpointBodyEntered"]
NOTE     [connection signal="pressed" from="HUD/StartButton" to="." method="OnStartPressed"]
[PASS] A_connection_landed_in_the_racing_scene
[PASS] A_checkpoint_connection_landed_too
[PASS] A_script_ext_resources_untouched_by_the_round_trip   （6 → 6）
```

**重开**（编辑器进程重启，连接只能来自文件）：

```
[B01/R06] editor_list_signal_connections(HUD/StartButton, pressed) → 含 OnStartPressed      [PASS]
[R07]     editor_list_signal_connections(Checkpoints/CP1, body_entered) → 含 OnCheckpointBodyEntered  [PASS]
[R08]     editor_analyze_signal_flow{} → 含 OnStartPressed                                  [PASS]
[R09]     project_read_scene_file_content(res://scenes/main.tscn).content 含
          [connection signal="pressed" from="HUD/StartButton" to="." method="OnStartPressed"] [PASS]
```

### 7.3 Part B：「若当时有 D-2 修复，那台车会不会自己计时？」

先把「真实后果」的机制钉死（**不是**推断，是运行期实测）：
一个用工具连出来的连接，在**存盘 + 重开 + 真的把游戏跑起来**之后**确实被触发**。

```
[R11_connect_timer] ok（Timer.timeout → Flag.mark，工具连的）
[R12] timer.tscn after save: [connection signal="timeout" from="Timer" to="Flag" method="mark"]  [PASS]
（第三次重启编辑器，从文件恢复）→ [R14] editor_play_scene{mode:"current"} 起游戏（工具自选端口 59916）
[R15_read_flag_fired] port=59916 bytes=156 sha256=3cea69cc6e3667f02808ccbae374aec9c3efcc6465949363c519653e4e92a0ca
       {"node_path":"/root/Main/Flag","properties":{"fired":21},"type":"Node"}
[PASS] B_persistent_connection_really_fired_in_the_running_game      （0.2 s 定时器跑 3 s → fired=21）
```

**结论（分两半，避免把「会」说成「本来就会」）**：

1. **用工具连出来的连接，修复后会随场景保存、并在重开时由 `PackedScene` 用 `CONNECT_PERSIST` 恢复**（Part B），
   所以「按了 GO 按钮 → `Main.OnStartPressed` → `LapTimer.Timing = true`」这条链在修复后**不再依赖脚本自己接线**。
   对一台**没有**脚本自连的项目，答案就是**会自己计时**。
2. **但 TASK-039 的那台车当时也能计时**——因为 `Main.cs:_Ready()` 自己写了 `startButton.Pressed += OnStartPressed`
   （`scripts/Main.cs:26`），这是**被 D-2 逼出来的绕法**，它同时**掩盖**了缺陷（对 `pressed` 这一条尤其如此：
   主路径上重复 connect 会被引擎拒掉，行为看起来正常）。同一批工具连接里**没有任何脚本补偿**的两条是
   `Checkpoints/CP1.body_entered → LapTimer.OnCheckpointBodyEntered`（`body_entered_probe_count` 恒为 0）
   与 `Checkpoints/CP1.BodyCrossed → HUD.OnLapEvent` —— **它们才是这个缺陷真正吃掉的东西**。
3. 因此对「会不会自己计时」的最准确回答是：**会**（工具连接现在真的持久且运行期真的触发）；
   而当年那台车之所以还能计时，靠的正是任务书 §D-2 点名的「脚本被迫自己 `Connect`」——绕法既救了效果，也遮了缺陷。

---

## 8. 五道门 + 门⑥三段式（真实输出与退出码）

> 门绑定构建（R-1）：全部门跑在 `scripts\build_local.cmd -Force`（`tests=yes`，从 **cmd** 启动）重建的二进制上，
> 其自报 `4.8.dev.custom_build.8e35a95b9` == `git rev-parse --short=9 HEAD`（`8e35a95b9`）；
> 构建**串行**、**未抑制** scons 输出（`%TEMP%\mcp040\build_*.log`）。

### 8.1 门⑦ 门0：`--version` == HEAD

```
===== GATE0 version: binary must self-report HEAD =====
4.8.dev.custom_build.8e35a95b9
8e35a95b9
```

### 8.2 门① 契约子集逐字（按受影响组各跑一次）

| 组 | 命令 | 结果 |
|---|---|---|
| `editor_write_scene_editor` | `scripts\check_contract_subset.ps1 -Group editor_write_scene_editor` | `editor_9888_contract_subset` PASS / `game_9889_contract_subset` PASS / `guard_user_port_9877` PASS → **3/3 checks passed**，exit 0 |
| `editor_node_write` | 同上 | **3/3 checks passed**，exit 0 |
| `running_game_observation` | 同上 | **3/3 checks passed**，exit 0 |

契约**未改**，所以不存在「override + 重生成 + 指纹」的步骤（`docs/tools_list.renamed.json` sha256 不变）。

### 8.3 门② 三类证据 + 跨工具活证据链

`scripts\mcp040_defect_probes.ps1 -Label fix` → **47 checks，0 failed**（exit 0）。
每个受影响工具三类证据都在：成功（`A05` 资源写、`C02` 游戏读、`A00` 打开场景、`B03` 断开）、
缺参（`E01/E02/E03/E07` → `-32602`）、底层失败（`E04/E05/E06/E08` → `-32001` + suggestion）。
游戏侧三条（`C01/C02/C03`）跑在 `editor_play_scene` **工具自选的空闲端口 62347** 上（响应里回 `mcp_port`），
全程没有绑定、更没有触碰被遗留进程占用的 9889。
活证据链（比单工具更容易抓真缺陷）：`open_scene → add_resource(缺失名拒) → add_resource(合法写) → save_scene(文件里出现子资源)
→ connect_signal(persisted) → save_scene([connection]) → 重启编辑器 → list/analyze 仍在 → disconnect → save([connection] 消失)
→ 重开游戏 → 读属性(-32001)/读真实属性(ok)/batch 逐项 → stop_scene`，以及赛车工程的 §7 端到端链。

### 8.4 门③ / 门④

**三次重建各跑一遍**（每次都用 `scripts\build_local.cmd -Force` 从 cmd 重建，且 `--version` == 重建时刻的 HEAD）：

| 重建时刻 HEAD | 引擎自报 | 门③ | 门④ |
|---|---|---|---|
| `8e35a95b94`（修复提交） | `4.8.dev.custom_build.8e35a95b9` | 276/276 SUCCESS exit 0 | 1702/1702 SUCCESS exit 0 |
| `67e7dbe7c6`（证据/脚本提交） | `4.8.dev.custom_build.67e7dbe7c` | 276/276 SUCCESS exit 0 | 1702/1702 SUCCESS exit 0 |
| `b416588b8a`（报告提交） | `4.8.dev.custom_build.b416588b8` | 276/276 SUCCESS exit 0 | 1702/1702 SUCCESS exit 0 |

三个 sha 之间 `git diff --stat <a>..<b> -- modules/mcp_server/tools modules/mcp_server/tests` **均为空**，
所以这三次跑的是**同一份被测代码**；后续若再有**只动文档/证据**的提交，代码仍然相同（可用同一条 diff 命令自证）。

```
gate3 (--headless --test --test-case="[MCPServer]*"):
[doctest] test cases:   276 |   276 passed | 0 failed | 1429 skipped
[doctest] assertions: 15875 | 15875 passed | 0 failed |
[doctest] Status: SUCCESS!                              GATE3_EXIT=0

gate4 (--headless --test):
[doctest] test cases:   1702 |  1702 passed | 0 failed | 3 skipped
[doctest] assertions: 440157 | 440157 passed | 0 failed |
[doctest] Status: SUCCESS!                              GATE4_EXIT=0
```

基线（红）：门③ `276 | 272 passed | 4 failed`，`15864 | 15850 passed | 14 failed`；门④ `1702 | 1701 passed | 1 failed`。
绿态的用例数与断言数只**增加**（+4 用例 / +11 断言）。

### 8.5 门⑤ `accept_m1.ps1` 连跑两次

| 次 | exit | PASS / FAIL | FAIL 清单 |
|---|---|---|---|
| 1 | 1 | 20 PASS / 2 FAIL | `case13_game_without_port`、`guard_user_port_9877` |
| 2 | 1 | 20 PASS / 2 FAIL | `case13_game_without_port`、`guard_user_port_9877` |

机器提取的两次比对（`evidence/task040/green/accept_m1-comparison.txt`，同时列出两次日志各自的 sha256）：

```
run 1: 20 PASS, 2 FAIL   ['case13_game_without_port', 'guard_user_port_9877']
run 2: 20 PASS, 2 FAIL   ['case13_game_without_port', 'guard_user_port_9877']
PASS lists identical (same ids, same order): True
FAIL lists identical (same ids, same order): True
```

两项失败的环境归因（**都不是模块行为**）：
1. `guard_user_port_9877`：本次运行期间 **9877 没有监听者**（用户的 Godot 没开；RACING-FINDINGS §0 也记了同一现象），
   而该检查断言「用户的编辑器仍在 9877 上」——它断言的是**环境**而不是模块。门① 的同名检查（措辞不同，断言「本 run 不占用 9877」）**PASS**。
2. `case13_game_without_port`：证据 `blocker_listening=True bind_failed_warning=True get_port_zero=True`，
   且 `mcp_lines` 里是 `[MCP] role=game configured_port=0 source=default listen=false` + `[MCP] not listening`——
   游戏默认端口（9889）被 **TASK-039 遗留的赛车游戏进程（pid 73176）**占着，bind 失败 → 不监听；
   该检查期望「没有端口参数的游戏会在默认端口上监听」。
   （该脚本的 `case14_port_occupied` 反而因此 PASS：它要的正是「端口被占时工具如何作答」。）

### 8.6 门⑥ 收窄点清单（三段式）

```
python scripts\check_narrowing_points.py                      → exit 0
  scanned : 71 narrowing point(s) in 17 file(s)
  pinned  : 71
  PASS: every narrowing point ... annotated and pinned ...
  note: 5 pinned line number(s) drifted（按 marker+occurrence 定位，不是失败；本批改动的行号位移导致）

python scripts\check_narrowing_points.py --coverage           → exit 0（17 种已声明拼写 + 集合边界打印）

powershell -File scripts\mcp031_gate6_coverage_probes.ps1     → exit 0
  101/101 checks passed; log sha256=94bb04d625a09317a163c81c496ffe89b2f839d8761780033deedfcdbcdd0cca
  （含 B1b_restored_scanned_71、B1b_worktree_clean_of_probes）
```

**本批没有新增任何收窄点**（新增代码只做 `Object::set` / 指针比较 / 布尔判断），所以清单不变。

### 8.7 证据落盘（`docs/reports/evidence/task040/`）

| 目录 | 内容 |
|---|---|
| `README.md` | 本目录**每个文件**的字节数与 sha256（机器生成，32 条） |
| `red/` | `A02/A03/A08/A10/B01/C01.*.response.json`（六条决定性原始响应体）、`doctest-red.log`、`probe-console-red.txt`（同一 run 的控制台原文抄录，附环境说明） |
| `green/` | `probe-checks.json`（探针 47/47）、`racing-checks.json`（赛车回归 35/35）、决定性响应体、门日志（gate1×3 / gate2 / gate3 / gate4 / gate6c / racing）、`accept_m1_run1.log`、`accept_m1_run2.log`、`accept_m1-comparison.txt` |
| `regression-attribution.txt` | 两轮回归脚本的**机器提取**汇总（每条日志自带字节数与 sha256） |

全部响应体由 `curl.exe -s -o <file>` 产出，sha256 均可就地重算（`certutil -hashfile <file> SHA256`）。

---

## 9. 回归脚本群逐条归因

> 两轮都跑了：**首轮**用脚本默认端口（9888/9889）；**二轮**加 `-GamePort 9890`（空闲 scratch 端口），
> 以绕开被 TASK-039 遗留赛车游戏（pid 73176）占用的 9889。
> 结论（实测，不是推断）：首轮的全部失败都能归因到两件环境事实；二轮除了那一条**断言环境本身**的检查
> （`port_9877_owner_before` / `port_9877_guard_before`，断言「用户的 Godot 正在 9877 上监听」）之外**全部转绿**。
> 日志：`%TEMP%\mcp040\reg_*.log`（首轮）与 `%TEMP%\mcp040\reg2_*.log`（二轮）。

| 脚本 | 首轮（9888/9889） | 二轮（-GamePort 9890） | 归因 |
|---|---|---|---|
| `probe037_d2_d1_r1r2.ps1` | 39/40；唯一失败 `port_9877_owner_before`（`pid=-1`） | **39/40**；同一项失败 | **环境**（9877 无监听）。D2a/D2b/D2c/D2d/D2e/R1/R2 全绿 → TASK-037 的修复未被本批影响 |
| `mcp030_live_open_scene_write_evidence.ps1` | 22 checks / 2 failed：`port_9877_owner_before`、`port_9889_free`(owner=73176) | **22 checks / 1 failed**（只剩 `port_9877_owner_before`） | **环境**；活动场景写族 20 条全绿 |
| `mcp032_d3_d4_d6_evidence.ps1` | 39 / 7 failed：`port_9877_owner_before`、`port_9889_free`、`d6_*` ×5 | **39 / 1 failed**（`d6_*` 全绿） | **环境**：`d6_*`（`running_game_get_scene_tree` 的绝对/相对路径与喂回）断言的是**自己 scratch 场景**里的 `Actor`，而 9889 上坐着的是**赛车工程的游戏**（`path=''`、`properties=0`） |
| `mcp033_b5_animation_evidence.ps1` | 75 / 3 failed：`port_9877_owner_before`、`port_9889_free`、`m4e2_game_reads_the_full_set`（`(Actor) -> 0 properties`） | **74/75**（只剩 `port_9877_owner_before`） | **环境**；动画组 14 条三类证据全绿 |
| `mcp034_b5_audio_particle_theme_evidence.ps1` | 111/114：`port_9877_owner_before`、`port_9889_free`、`ports_released_after_run` | **113/114**（只剩 `port_9877_owner_before`） | **环境**；音频/粒子/主题全绿 |
| `mcp035_b5_tilemap_shader_physics_evidence.ps1` | 63/67：`port_9889_released`、`port_9877_owner_before`、`port_9889_free`、`scope_9889_project_tool_runs` | **66/67**（只剩 `port_9877_owner_before`） | **环境**：`scope_9889_project_tool_runs` 把 scratch 工程的 project 工具打在 9889 的游戏端点上，而那台游戏跑的是**赛车工程** |
| `mcp036_b5_navigation_theme_export_android_evidence.ps1` | 51/59：`mov00/01/02/03`、`class_running_game_move_player_to_target`、`navl01_move_refuses_without_navigation_data`、`port_9889_released`、`port_9877_guard_before` | **58/59**（只剩 `port_9877_guard_before`） | **环境**：6 条全是**游戏侧移动**用例，要的是它自己搭的 `Region/Player/Walker/Goal` 场景，实际拿到的是赛车游戏场景/「Player not found」 |

**二轮合计**：416 条检查，**409 PASS / 7 FAIL**，且 7 条失败全部是同一类环境断言
（「用户的 Godot 正在 9877 上监听」；本次运行期间 9877 无监听，与 RACING-FINDINGS §0 的记录一致）。
→ **没有任何一条失败指向本批改动的四个工具**；受影响组之外的行为**无回归**。

> **证据强度声明**：二轮的转绿与首轮的失败**互相印证**（首轮失败的用例在自由游戏端口下全绿，而失败时 9889 的所有者确实是 pid 73176）；
> 我没有把「首轮失败」当成「已证伪的回归」丢掉——两张表都在，日志都在。

---

## 10. 逐工具表（受影响四个工具；「引擎依据」列按手册 §4）

| `new_name` | 迁移源位置（仅类别） | **引擎依据** | **自然契约** | C++ 落点 | 与迁移源的差异及理由 |
|---|---|---|---|---|---|
| `editor_add_resource_to_node_property` | `node.rs:365`（`add_resource`） | `ClassDB::instantiate` + `Object::set/get_property_list` + `PropertyInfo::class_name`（`property_info.h:57` 的类表文法） | 参数 `node_path/property/resource_type`（必填，**契约一字未改**）、`resource_properties`（可选对象）；成功回 `{node_path,property,resource_type}`；**不存在** → `-32001`+suggestion；**类不匹配** → `-32602`+suggestion；**写不进** → `-32000` | `tools/editor_write_scene_editor.cpp:706` → `tools/tool_helpers.cpp:1801` | 迁移源对不存在的属性静默成功（RACING-FINDINGS §4 D-1）。按「工具真的能用」判据拒绝，并用模块**既有**的类表读取器（TASK-027 D-8）而不是新写一个 |
| `editor_connect_signal` | `node.rs:319` | `Object::connect(signal, callable, flags)` + `Object::CONNECT_PERSIST`；`PackedScene` 只序列化带该位的连接（`packed_scene.cpp:1238/760`） | 参数同上（**未加 `persist` 参数**：加参数会动 `inputSchema` → 171 条逐字门）；成功回 `{connected,signal,source,target,**persisted**}（+已存在时 `already_connected`） | `tools/editor_node_write.cpp:253-296`（helper）、`:909`（响应） | 迁移源不传 flags → 连接不进 `.tscn`。本实现按引擎语义恒用 `CONNECT_PERSIST`，并把 `persisted` 作为**读回值**回给调用方（对标 `editor_add_input_action` 的 `persisted:false`） |
| `editor_disconnect_signal` | `node.rs:344`（fix-first，TASK-015 已修过「用错 target」） | `Object::is_connected`（按 callable 匹配，**无视 flags**）+ `Object::disconnect` | 参数不变；成功回 `{disconnected,signal,source,target,**was_persistent**}` | `tools/editor_node_write.cpp:300-345`、`:1006` | 行为**未变**（持久连接本来就能断）；本批加的是「断开的东西是不是持久的」这一诚实字段，并用 doctest 钉住「持久连接可断」 |
| `running_game_get_node_properties` | `mcp_runtime_agent.gd:114-135` | `Object::get_property_list` / `get` / `has_signal` 之外，关键是**写侧已有的** `object_has_property` 判据（`running_game_node_write.cpp:1158`） | `node_path` 必填、`properties` 可选；不带 `properties` → 枚举全部属性（**未改**）；带 `properties` → 每个名字：标签跳过（TASK-032 D3）、真实属性读回、**不存在的名字 `-32001`+suggestion** | `tools/running_game_observation.cpp:153`（+ 四个调用点） | **二选一选了与写侧一致**（§4.4）；迁移源/旧实现的「不存在回 null」被移除，契约**未改**（因此无 override/重生成/指纹） |

---

## 11. 纪律自证

1. **只改 `modules/mcp_server/**`**；hof-rs 只读；未改 `docs/DESIGN-DETAIL.md`、契约、映射、生成器（契约 sha256 未变，门①逐字通过）。
2. **9877**：`netstat` 观测到全程**无监听**（用户 Godot 未开），本任务**从未绑定/杀死/重启**它；探针与两轮回归都各有一条 `port_9877_owner_unchanged` 断言（PASS）。
3. **9889 上 TASK-039 遗留的赛车游戏（pid 73176，`godot.windows.editor.x86_64.mono.exe --headless --path %TEMP%\mcp-racing-test --mcp-port=9889`）**：
   **没有杀**（不是我启动的进程）；探针/赛车回归都用一个显式断言证明它**未被触碰**（`racing_game_on_9889_untouched`）；
   我自己的游戏子进程一律用 `editor_play_scene` **自动挑空闲端口**（响应里回 `mcp_port`），并在 finally 里只回收**自己**起的那个 pid。
4. **禁止 push**：未 push（`git status` 里只有本任务的文件；无 remote 操作）。
5. **证据**：一律 `curl.exe -s -o <file>` 落盘 + sha256；请求体用 `ConvertTo-Json` 写进临时文件（`--data-binary @file`）；**`Out-File`/管道不承载响应体**。
6. **两个新脚本 `.ps1` 全 ASCII**（`non_ascii=0`，实测）；用 `Parser::ParseFile` 做过 0 error 语法检查。
7. **构建串行**：全程一次只有一个 scons（`build_red`→`build_red2`→`build_red3`→`build_green`→`build_green2`→`build_after_commit`），未抑制输出，从 cmd 启动。

---

## 12. deviations / blockers / next_step_recommendation

**deviations（逐条）**

1. **红态与绿态收在同一个提交**（`8e35a95b94`）：红态是「抽取两个可测入口（行为不变） + 4 个失败用例」的中间构建，
   它的**真实输出**被完整保留（`evidence/task040/red/doctest-red.log` + `probe-console-red.txt`），但中间态源码没有单独提交。
2. **D-3 的改动面比任务书字面更宽**：任务书只点名 `running_game_get_node_properties`，本实现把 `properties` 过滤的
   **同族三个**（`..._batch` / `..._autoload_node` / `..._find_nodes_by_script`）一起收紧——理由写在 §4.2；
   batch 保持逐项粒度（逐项 `error`），不是整调用失败。
3. **赛车工程用副本**（原目录只读）：原因有两条，都写进 §7.1（不污染下游工程 + `module_mono_enabled=no` 加载不了 C# 脚本）。
   适配只改 6 条 `Script` ext_resource 的指向；节点/属性/名字/id 全未动（`P01` 检查）。
4. **回归脚本第二轮换了游戏端口（9890）**：9889 被遗留进程占用；`PLAYBOOK` 的端口纪律只保护 9877，
   但我不杀别人的进程，所以用**空闲 scratch 端口**把「是否真有回归」测清（§9：二轮 409/416，7 条失败全是「用户 Godot 在 9877」
   这一条环境断言）。首轮（默认端口）结果同样保留并逐条归因，**没有**被丢掉。
5. **探针脚本的 `port_9889_free` 改为 NOTE**：环境里 9889 注定被占（遗留进程），保留一个必然 FAIL 的断言会污染 PASS 清单；
   真正的断言改成 `racing_game_on_9889_untouched`（证明未触碰）与「自己的游戏用工具自选端口」。
6. **未采纳 RACING-FINDINGS O-2（给 D-1 工具加 `old_value`/`new_value`）**：形状需要与编辑器侧的**资源镜像**对齐，
   否则会造出第二个序列化器（GDR-25）；属决策层议题（§2.4 已声明）。
7. **未采纳 O-3 的 `persist` 参数**：任务书 §2 只要求「连接必须带 `CONNECT_PERSIST` + 响应给 `persisted`」；
   加参数会改 `inputSchema` → 动契约 sha 与 171 条逐字门。当前实现恒持久 + 诚实回报。
8. **`accept_m1.ps1` 的两次运行都 exit 1**，失败项是 `guard_user_port_9877`（环境：9877 无人监听）与
   `case13_game_without_port`（环境：9889 被遗留进程占用）。**两次 PASS 清单逐条一致**，符合门⑤「两次一致」的实质要求。

**blockers**：无（三条缺陷都已修复并有绿证据；其余全部是全绿或有环境归因的失败）。
唯一**外部条件**：`accept_m1` 的 `case13` 与若干回归脚本的游戏侧用例，只有在 **9889 空闲**时才能纯净地跑一遍。

**next_step_recommendation**

1. **决策项**：是否允许停掉 TASK-039 遗留的赛车游戏进程（pid 73176）。若允许，在 9889 空闲时重跑一次
   `accept_m1.ps1` ×2 与 `mcp032/033/035/036`（预期：只剩 `guard_user_port_9877` 这一条环境失败）。
2. **决策项（RACING-FINDINGS O-2）**：`editor_add_resource_to_node_property` 的 `old_value`/`new_value` 形状，
   应与编辑器侧的资源镜像（`{"type","path","local_to_scene"}`）统一后再加（避免第二个序列化器）。
3. **决策项（M-6）**：`editor_add_input_action` 的 `persisted:false` 是**诚实的能力缺口**（InputMap 不进 `project.godot`）；
   本任务未动行为，建议按 RACING-FINDINGS M-6 单独排期。
4. **可选**：给 `.ps1` 回归脚本加一个「游戏端口参数」的统一约定（本轮暴露：9889 一旦被占用，多个脚本的游戏侧用例整体失效且难以自动归因）。

---

## 13. 结论锚点（D86）

- 本报告**所有绿灯结论**测自 `feature/mcp-server-module` 的 `8e35a95b94`（引擎自报 `4.8.dev.custom_build.8e35a95b9`），
  并在 `67e7dbe7c6`、`b416588b8a` 上一次**重建 + 复跑门③/门④**（`4.8.dev.custom_build.67e7dbe7c` / `4.8.dev.custom_build.b416588b8`）；
  `git diff --stat <a>..<b> -- modules/mcp_server/tools modules/mcp_server/tests` 在这三个 sha 之间**均为空**，
  即三次测的是同一份代码，中间只有「证据/脚本/报告」的追加。
- 三条缺陷的**红**实测自 `6afe08746a`，引擎自报 `4.8.dev.custom_build.6afe08746`（与 RACING-FINDINGS §4 的 `f34ee937f` **不是同一提交**：
  RACING-FINDINGS 之后 `f34ee937f → 6afe08746a` 之间进过一次提交，因此本报告的复现是**在新基线上重新实测**的，
  不是转述 RACING-FINDINGS；两处锚点都写明，避免交叉引用时指错提交）。
- 契约/组清单/引擎源码（`packed_scene.cpp` 等）**只读**，其行号引用沿用 RACING-FINDINGS §4 的读数。
