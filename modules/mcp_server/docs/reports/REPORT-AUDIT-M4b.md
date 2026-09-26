# REPORT-AUDIT-M4b — 里程碑级独立验收（**第二次**）：B3+B4（47 个工具）

- 任务书：`docs/tasks/TASK-AUDIT-M4.md`（§2 开头「本轮为第二次验收」）
- 首轮报告：`docs/reports/REPORT-AUDIT-M4.md`（判 `fail`，3 个缺陷 D-1/D-2/D-3）
- 验收方：**独立验收工程师**（未参与实现；**未采信** `REPORT-0*.md` 与决策者结论；本报告所有结论均由本次自行运行产生）
- 日期：2026-09-22（本次会话）
- 仓库：`F:\RustProjects\godot-mcp-pro\code\godot`，分支 `feature/mcp-server-module`
- **被验二进制**：`bin\godot.windows.editor.x86_64.console.exe`
  - `--version` = `4.8.dev.custom_build.08f0bd529`，`git rev-parse --short HEAD` = `08f0bd529`（**前缀一致**）
  - SHA256 = `B435E032C9202FFBD727E208E1D49A564501CE4292229026CCE054323AB2C6E5`（22:41:51 重建产物）
- 临时工作根：`%TEMP%\audit-m4b\`（`common.ps1`/`helpers.ps1` 自建 harness、`evidence\*`、`results-phase*.json`、`eq\`、`logs\`）
- 工作树终态：`git status --porcelain` 仅 4 个**既有**未跟踪项（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）；
  HEAD 仍为 `08f0bd529f63bc7077b0c3c42a404e766750406a`。**本次未修改任何被跟踪文件、未执行任何 git 写操作、未安装依赖。**
- 端口纪律：9877 全程属于用户 **PID 36392**（`Godot_v4.7.1-stable_mono_win64`）；本次仅用 9888 / 9889。

---

## 0. 开工第一步：`--version` 与 HEAD 校验（**发现不一致，已用规定脚本重建**）

开工时 `--version` = `4.8.dev.custom_build.de04c86f4`，HEAD = `08f0bd529f` → **不一致**。

按任务书要求用 **`modules/mcp_server/scripts/build_local.cmd`（`tests=yes`）** 重建：

```
cd /d F:\RustProjects\godot-mcp-pro\code\godot
modules\mcp_server\scripts\build_local.cmd
 -> build_local: exit code = 0
 -> log = %TEMP%\mcp_server_build_local.log   （EXIT_CODE=0，**未抑制 scons 输出**）
```

重建后 `--version` = `4.8.dev.custom_build.08f0bd529` == HEAD 前缀。

**陈旧 test 对象陷阱**（`build_local.cmd` 头部注释所警告的那个）本次**未触发**：
`bin\obj\modules\mcp_server\tests\test_mcp_server.windows.editor.x86_64.obj`（22:27）**晚于**
`modules\mcp_server\tests\test_mcp_server.h`（22:26），且门③ 的用例数（184）与 `REPORT-021` 声称的
TASK-021 增量一致（首轮 175 → 184），故被判为「未跑旧用例」。

> 本报告全部证据（`tools/list`、行为、事务、延迟通道、决策面反例、门）均采集于上述二进制。

---

## 1. 全量对等与 scope（A 段）

### 1.1 方法

- `POST tools/list` 抓两端响应体（`curl.exe -s -o`），落盘 `%TEMP%\audit-m4b\evidence\P1_*.response.json`，
  记录 curl 退出码 / 字节数 / sha256；请求体一律 `ConvertTo-Json -Depth 32` 生成（**无** `Out-File`、**无**管道承载响应体、**无**字符串拼接 JSON）。
- 集合比对**完全基于解析后的 JSON `name` 字段**（自撰 `analyze_equality.py`：`json.loads` 后取 `result.tools[].name` 做 Python `set`/`==`），
  **未使用** `-match` / `-like` / `-contains` / `Select-String` 等文本包含判定（PLAYBOOK §7.4）。
- `description` / `inputSchema` 用规范化 JSON（`sort_keys=True, separators`）**逐字符**比对，并同时比对键集。
- 期望集合由 5 个 manifest 的 `implemented=true` 组并集推导；`scope` 唯一事实源 = `tool-rename-map.json`。

### 1.2 结论（全部 PASS）

| 检查 | 结果 | 我自己的证据 |
|---|---|---|
| 契约条数 | 171 | `tools_list.renamed.json` |
| manifest `implemented=true` | 41+25+40+7+0 = **113** | `analyze_equality.py` |
| 端点实况 | **9888 = 91，9889 = 53** | `P1_editor_tools_list` sha256 `B921B2C9…C94B`（26372B）/ `P1_game_tools_list` sha256 `2C8691CF…4089`（18420B） |
| 并集 == `implemented=true` | PASS | 两向差集均空（`missing=[] extra=[]`） |
| 未实现却上架 / 实现却缺席 / 上架不在契约 | PASS | 三项均空 |
| `description`+`inputSchema` 逐字相等 | PASS | 9888 的 91 条、9889 的 53 条 **diffs=[]**（含键集） |
| 重名 / 空名 | PASS | 两端均空 |
| **scope 对称推导** | PASS | editor-only 60 + game-only 22 + both 31 = 113；编辑器期望 91 == 实况 91、游戏期望 53 == 实况 53，**两向差集为空** |
| `scope=editor` 出现在 9889 / `scope=game` 出现在 9888 | PASS | 各 0 条；31 个 both 两端都可见 |

跨端点与边界行为：

- 向 9889 调 `editor_get_test_report` → `{"code":-32601,"message":"Method not found: editor_get_test_report"}`，`result` 为 null（**未执行**）；
  随后 9888 的 `editor_get_test_report` 仍为 `total=0, no_results=true`，证明跨端点调用**没有**进入编辑器累加器。
- 向 9888 调 `running_game_assert_node_state` → `-32601`；未知名 `no_such_tool_at_all` → `-32601`。
- 非 `/mcp` 路径 → `{"error":"Not Found"}`（21B，sha256 `E28BF7D9…DD41`），不服务。

> **首轮 `unconfirmed`（§17.3 措辞）已不再作为问题出现**：本轮只按 `tool-rename-map.json` 的 `scope` 对称推导，
> 实况与对称规则一致，未复现文档措辞冲突。

---

## 2. 诚实性（B 段）

### 2.1 7 个 `fix_implementation_first` 的现状

**已修 4 个：本轮重新自行构造证据，全部证实「真的做到」**

| 工具 | 结论 | 我自己的证据（本轮） |
|---|---|---|
| `editor_remove_output_log` | **真的做到（测量式汇报）** | 连续两次调用返回**测得**的面板状态：`{"cleared":true,"log_was_empty":false,"log_is_empty":true}` → `{"cleared":true,"log_was_empty":true,"log_is_empty":true}`；`log_was_empty` 由 false→true 是**跨调用可观测的状态变化**，不可能由常量伪造。 |
| `editor_set_auto_dismiss_dialogs` | **真的做到（改为诚实拒绝）** | 参数校验在前：`enabled="yes"` → `-32602`；合法调用 → `-32000` 且 **`result` 为 null**，响应中**不含** `auto_dismiss` 字段（不回显请求值）。 |
| `editor_disconnect_signal` | **真的做到** | `editor_connect_signal(Actor.tree_exited → queue_free)` → `editor_list_signal_connections(node_path='Actor', signal_name='tree_exited')` 条数 **3 → 2**（注意 `count` 含编辑器自身内部连接，见 §5 观察）；反例 `target_path='./Ui'` → `-32001 "Connection from signal 'tree_exited' to method 'queue_free' not found"`（**响亮失败**，不误删别的连接）。 |
| `editor_get_test_report` | **诚实，但见 D-6** | 空报告 8 字段 `{"all_passed":false,"details":[],"failed":0,"no_results":true,"pass_rate":"N/A","passed":0,"source":"editor_process","total":0}`；**没有**迁移源那句伪造 `message`；源码核对唯一写入点 `record_test_result`（`running_game_assertion.cpp:160/242`、`running_game_test_execution.cpp:466`）**全部在 game 侧**（见 D-6）。 |

**剩余 3 个（B5）仍未注册：证实** —— `editor_set_tilemap_cell`、`editor_set_tilemap_cells_in_rect`、
`editor_bake_navigation_mesh` 在两端**解析后的 name 集合中均不存在**。

### 2.2 2 个 `unregister_until_implemented` 仍未注册：证实

`running_game_move_player_to_target_via_navigation`、`project_export_game` → 两端**均不存在**。

### 2.3 静默错值修复（D67 裁决的落地）——**主路径成立，但同族仍有缺口（D-4）**

合法值回归（**全部 code=0 并读回正确**）：`Vector2`、`int`、`bool`、`String`、`float`、`Color`、
`Vector2i`、`Vector3`、`Vector4`、`PackedByteArray/Int32/Int64/Float32/Float64/Vector2/Vector4/Color/String`、
`Array`、`Dictionary`；`project_set_setting` 类型保真（`{"created":false,"existed_before":true,"key":"audit/bool_value","saved":true,"type":"bool","value":false}`）。

**控制实验（证明 sha256 判据是活的）**：`editor_set_node_property` + `editor_save_scene` 后
`main.tscn` sha256 `74CA219BDA42…` → `5419E38BD255…`（**变化**）。故后续「sha 相同」是真证据，不是恒真判据。

---

## 3. **本轮核心**：D-1 / D-2 复核 + TASK-020/021 的五个面是否真闭合 + 新同族面

判据（任务书要求三条同时给出）：① 错误码；② 前后文件 sha256 相同；③ **另一读工具**读回旧值。
本轮的「另一读工具」有两路，均为**独立于写路径**的读取通道：

- **R1** = `editor_execute_gdscript` / `running_game_execute_gdscript`（GDScript 求值，返回 `result`/`result_type`）；
- **R2** = `editor_get_node_properties` / `running_game_get_node_properties`（模块自身的属性序列化）。

（`editor_execute_gdscript` 在编辑器侧用 `EditorInterface.get_edited_scene_root()`，游戏侧用
`Engine.get_main_loop().root`；两者均已先行自检可用：`return 42` → 42、`return a.position` → `(3.0, 4.0)`。）

### 3.1 D-1（分量级静默错值）：**已闭合**

对 `Actor.position`（`Vector2`，旧值 `(3,4)`）逐一传**首轮用过的同样五种分量值**，编辑器端点与游戏端点各一遍：

| 值 | 错误码 | R1 读回 | R2 读回 | sha256 |
|---|---|---|---|---|
| `{"x":"NaN","y":1}` | **-32602** | `(3.0, 4.0)` 未变 | `{"x":3.0,"y":4.0}` 未变 | 相同 |
| `{"x":"abc","y":1}` | **-32602** | `(3.0, 4.0)` | `{"x":3.0,"y":4.0}` | 相同 |
| `{"x":null,"y":1}` | **-32602** | `(3.0, 4.0)` | `{"x":3.0,"y":4.0}` | 相同 |
| `{"x":{"z":9},"y":1}` | **-32602** | `(3.0, 4.0)` | `{"x":3.0,"y":4.0}` | 相同 |
| `{"x":[1,2],"y":1}` | **-32602** | `(3.0, 4.0)` | `{"x":3.0,"y":4.0}` | 相同 |

- 首轮缺陷形状（`code=0` + `new_value {"x":0.0,"y":1.0}`）**不再出现**。
- 报错消息带**分量名**（`Parameter 'value.x' is the string "NaN" …`），可定位到槽位。
- 游戏端点（9889）五个值同样 `-32602`，`running_game_get_node_properties` 读回 `{"position":{"x":3.0,"y":4.0}}` 未变。
- 证据：`results-phaseX.json`（`X1_*`）、`results-phaseB2.json`（`G2_*`）、`evidence/X1_*_p{a,b}.response.json`。

### 3.2 D-2（`STRING→FLOAT/INT` 放行垃圾）：**已闭合**

| 面 | 值 | 结果 |
|---|---|---|
| float（原生 `real_t`，首轮同一属性） | `"abc"` / `"NaN"` | **-32602**，读回 `0.5` 未变，sha 相同 |
| float | `"inf"` / `"1e999"` / `"1e"` / `"1.5abc"` / `" 1.5"` | **-32602**（含非有限与「整串未消费」两类） |
| int | `"abc"` / `"1e3"` / `"1.5"` | **-32602** |
| **合法拼写回归** | float `"1.5"`→1.5、`"-3"`→-3.0；int `"7"`→7 | **code=0 且值正确** |

### 3.3 TASK-021 声称闭合的五个面：**逐个复核，四个闭合、一个仍开（新面 D-4）**

| 面 | 复核 | 结论 |
|---|---|---|
| **`STRING→BOOL`** | `"abc"` / `" "` / `"NaN"` / `"yes"` → **-32602**；`"true"`/`"TRUE"`/`"1"`→`true`、`"false"`/`"0"`→`false`（**写拼写所指的值**，非 `booleanize`）；`flag` 值均按预期变化 | **闭合**（`"0"→false` 与引擎 `booleanize("0")==true` 的**有意背离**已在源码与 REPORT-021 声明，见 O-6） |
| **packed 元素位宽** | `bytes`：`300` / `-1` / `1e20` / `256` / `"300"` → **-32602**；`255`→`[255]`、`0`→`[0]`。`ints32`：`±3000000000` → **-32602**；边界 `2147483647`→接受、`2147483648`→**-32602**。`fl32`：`1e300` / `1e-300` / `"1e300"` / `3.5e38` / `3.6e38` → **-32602**；`1.5`→`[1.5]`。`fl64`：`1e300` **接受**（槽位就是 double） | **闭合**（拒绝消息给出引擎本会写的值，如 `44`/`-1294967296`/`inf`） |
| **`Vector4` 元素** | `v4s=[{"x":1,"y":2,"z":3,"w":4}]`→接受（`[(5,6,7,8)]` 回归通过）；元素分量 `"abc"` / `1e300` → **-32602**；缺 `w` → **-32602** 且消息给出四个分量名；`v2s=[{"x":1e300,…}]`、`cols=["notacolor"]` → **-32602** | **闭合** |
| **分量槽位宽** | `{"x":1e300}` / `{"x":1e-300}` / `{"x":"1e300"}`（Vector2/Vector3/Vector4/Color）→ **-32602**；`Vector2i` `{"x":3000000000}` → **-32602**；合法回归 `{"x":1.5}`→`(1, 1)`（已声明的 FLOAT→INT 截断） | **闭合**（分量层） |
| **`STRING→COLOR`** | `"notacolor"` / `"#gggggg"` / `"reddish"` / `""` → **-32602**；`"#ff0000"`→`(1,0,0,1)`、`"#f00"`→`(1,0,0,1)`、`"blue"`→`(0,0,1,1)` | **闭合** |

**但同族的面并未清零** → 见下。

### 3.4 **新发现的同族面（本轮自找）：标量 `real_t` 槽位宽 —— D-4（high）**

TASK-021 的 A-2/A-4 把「槽位宽」判在**容器元素**与**分量**两处，却**漏了普通标量属性**：
单精度构建里 `Node2D.rotation` 等的 C++ 成员是 `real_t` = **`float`**，而 `coerce_to_property_type`
的 FLOAT 分支只判「非 nan/inf」与「INT 目标的范围」，**没有任何 real_t 收窄判定**。

实测（`Actor.rotation`，旧值 `0.5`；R1/R2 双读，`main.tscn` sha 前后相同）：

| 请求 | 返回 | R1 读回 | R2 读回 |
|---|---|---|---|
| `rotation = 1e300`（JSON number） | **code=0**，`new_value=1e99999` | **`inf`** | **`null`** |
| `rotation = 3.5e38` | **code=0** | **`inf`** | `null` |
| `rotation = 1e-300` | **code=0** | **`0.0`** | `0.0` |
| `rotation = 1e-46` | **code=0** | **`0.0`** | `0.0` |
| `rotation = "1e300"`（字符串） | **code=0** | **`inf`** | `null` |
| `rotation = 1e30`（float 可表达） | code=0 | `1.0000000150474662e+30` | 同值（**正确**） |
| `rotation = 1e20` | code=0 | `1.0000000200408773e+20`（**正确**，float 可表达） | 同值 |

**它不只出现在一个工具上**（三个判据在每处都成立——但第三条按缺陷本身**不可能**成立，见下）：

| 路径 | 我自己的证据 |
|---|---|
| `editor_set_node_property` | 上表（`results-phaseB2.json` 的 `N_rot_*`） |
| `editor_set_node_property_batch`（`node_type=Node2D`） | `code=0`，3 个节点全部被写成 `inf`（`D4_batch_rotation_1e300`） |
| `editor_add_nodes_batch` | `code=0`，新节点 `D4Node.rotation` = `inf`（`D4_addnodes_rotation_1e300`） |
| `running_game_set_node_property`（9889） | `code=0`，`{"rotation":0.0}` → `inf`（`D4_game_rotation_1e300`） |
| **`project_set_node_property_across_scenes`（落到磁盘）** | `code=0`、`message="Applied: every closed scene was saved…"`，`xscenes/good.tscn` 内**确实写入** `rotation = inf`（`D4_xscene_rotation_1e300_reaches_the_file`，两个节点各一行） |

**为什么首轮的「三条判据」自检法抓不到 D-4（这正是必须显式补它的理由）**：

- 第 ③ 条（**另一读工具读回旧值**）在本缺陷上**结构性失效**——值真的被改了，旧值不存在了，没有「旧值」可读；
- 第 ② 条（场景 sha 相同）在**编辑器写入未 save** 时恒真（我已用控制实验证明它只有在 save 后才有判别力）；
- `serialize_variant` 对非有限 float 输出 `null`，所以 R2 甚至**看不出** `inf`——只有 R1（GDScript `str()`）能看到 `"inf"`。

**两条真正可判定的形态**（已验证）：
1. **响应里回显的 `new_value` 非有限**（`1e99999`）而 `code=0`；
2. **文件里出现 `rotation = inf`**（`project_set_node_property_across_scenes` 落盘路径）。

**location**：`modules/mcp_server/tools/tool_helpers.cpp` 的 `coerce_to_property_type` FLOAT 分支
（`:838-848` 只判 nan/inf 与 INT 目标范围；`:988` 的 `p_value.get_type() == p_target_type` 直接放行；
`:1029` 的 `type_convert` 结果仍是 double）。对照已修的
`_component_fits_slot`（`running_game_node_write.cpp:276-317`）与 `_element_fits_container`
（`tool_helpers.cpp:745-797`）——同一层判定，标量槽位缺失。

**recommendation**：把「槽位宽」判定从「容器元素 / 分量」提升为**一条作用于最终 Variant→属性成员收窄的统一规则**：
在 `prepare_node_property_value` 的写入前预校验里，对目标类型为 `FLOAT`（且构建为单精度）的**标量**属性
补 `_component_fits_slot(COMPONENT_WIDTH_REAL)` 的同一判定（`|x| > FLT_MAX → 拒绝`、`x != 0 && (float)x == 0 → 拒绝`），
并让批量 / 跨场景路径复用同一预校验（保持全成功或全回滚）。**判定必须落在任何写入之前**，
且报告必须给出「响应回显值有限 + 文件里没有 inf」这一新证据形态。

---

## 4. 行为与宣称一致（C 段，对抗性抽样 ≥15 个工具）

本轮抽样对照 **25+ 个** B3/B4 工具（远超 15）。摘录（完整逐条证据见 `results-phase*.json`）：

| 工具 | 实测 | 与契约/迁移源对照 | 判定 |
|---|---|---|---|
| `editor_set_node_property` | 不兼容 → `-32602`（带分量名）；合法 → `new_value` 为写后真值 | D67 裁决 | 主路径一致；**标量 real_t 有缺口（D-4）** |
| `editor_set_node_property_batch` | 写前拒绝（`Property 'position' write refused before any node was written`）；无匹配节点 `-32001`；属性不存在 `-32001`；合法 `{"count":3,"updated":3,"status":"ok"}` | TASK-017 全成功/全回滚 | 一致 |
| `editor_add_nodes_batch` | 中间元素坏 → `-32602` 且**场景树逐字节相同**（`tree_identical=True`，两次不同坏值） | DESIGN §17 | 一致 |
| `editor_remove_output_log` | `{cleared,log_was_empty,log_is_empty}` 跨调用变化 | 迁移源恒 `{cleared:true}` | 一致（已修正） |
| `editor_set_auto_dismiss_dialogs` | `-32000` + `suggestion`，无回显 | 迁移源回显伪造成功 | 一致（已修正） |
| `editor_disconnect_signal` | 命中才断（3→2），未命中 `-32001` | 契约 4 参 | 一致（已修正） |
| `editor_connect_signal` | `{connected:true,signal,source,target}` | 契约 | 一致 |
| `editor_list_signal_connections` | 扁平 `connections[]` + `count`，**含编辑器自身内部连接** | 契约明文「收全部连接（不过滤非持久连接）」 | 一致（调用方需自行按 `target` 收敛，见 O-10） |
| `editor_get_test_report` | `total=0, no_results=true, source="editor_process"` | 契约「获取测试结果报告」 | **诚实但不可达（D-6）** |
| `editor_analyze_screenshot_diff` | 同图 → `identical=true, changed_pixels=0, diff_percentage=0.0`；异图 → `identical=false, changed_pixels=16/16, diff_percentage=100.0`；`threshold=999`/`-1` → `-32602`；缺文件 `-32001` | 契约 3 参 | 一致（**首轮 `unconfirmed` 项已闭合**） |
| `project_convert_path_to_uid` / `_uid_to_path` | 正向 `res://main.gd` → `uid://…`；`uid_to_path("res://main.gd")` → `-32602`（附「To go the other way…」）；`path_to_uid("uid://…")` → `-32602` | 契约 | 一致（方向搞反**响亮失败**） |
| `project_set_setting` | 类型保真；`"abc"` 对 bool/float 目标 → `-32602`；`"false"` → `{"value":false,"type":"bool"}` | D67 P-2 | 一致 |
| `project_create_resource` | 坏 Color 串 → `-32602` 且**文件未创建**；合法 → `properties_set` | 契约 | 见 **D-5**（`properties_set` 未回读校验） |
| `project_edit_resource` | 坏 Color 串 → `-32602`；合法编辑返回 `changed:{min_value:{old,new}}`（**真回读**） | 契约 | 一致 |
| `editor_add_resource_to_node_property` | `resource_properties.bg_color="notacolor"` → `-32602` | 契约 | 一致 |
| `project_set_node_property_across_scenes` | 默认 `dry_run=true`；坏文件 → `-32000` + `data.scenes.errors` + `Nothing was written`；`dry_run=false,force=true` → `Applied` | 契约 | 一致（**首轮 `unconfirmed` 项已闭合**） |
| `running_game_run_test_scenario` | 通过 → `all_passed=true, passed=2`；失败 → `all_passed=false, failed=2`，两条失败记录**均带 `expected`/`actual`/`reason`**；空步骤/未知类型/缺参 → `-32602` | TASK-019 §1.1 | 一致 |
| `running_game_assert_node_state` / `_screen_text` | 失败返回**已带 `reason`**（`"expected name eq NotRoot, found Root"` / `"screen text containing '…' was not found in the 1 visible text(s)…"`），字段集与场景内一致 | TASK-020 §4（D-3 修复） | **一致（D-3 已闭合）** |
| `running_game_capture_signal_emissions` | `duration_ms=1500` 内观测到 **count=218** 次 `pulse` 发射（`args`/节点/信号齐备） | 契约 | 一致 |
| `running_game_run_stress_test` | `{"completed":true,"crashed":false,"iterations_completed":3,"game_still_running":true}` | 契约 | 一致 |
| `running_game_find_node_when_available` | 超时 `-32000 "Deferred call timed out after 1000 ms: waiting for node '…'"` | GDR-20 | 一致 |
| `editor_rescan_project_filesystem` / `project_read_resource` / `editor_get_scene_tree` / `editor_save_scene` / `editor_execute_gdscript` | 均 code=0，形状与契约相符 | 契约 | 一致 |

---

## 5. 安全与事务（S 段）

| 反例 | 实测 | 判定 |
|---|---|---|
| 路径逃逸（写侧，相对） | `project_create_script("res://../audit_escape.gd")` → `-32602 "…must not walk upwards with '..'"`，磁盘**无**该文件 | PASS |
| 路径逃逸（写侧，绝对） | `%TEMP%\audit_abs_escape.gd` → `-32602 "…must address the project ('res://…')"`，磁盘**无**该文件 | PASS |
| 路径逃逸（读侧） | `project_read_script("res://../../../../Windows/win.ini")` → `-32602` | PASS |
| 路径逃逸（截图工具，第三条路径） | `editor_analyze_screenshot_diff(image_a="res://../../../../Windows/win.ini")` → `-32001 "Image '…' not found"`（**响亮失败**，未读到项目外文件；非 `-32602` 但属可接受，见 O-8） | PASS（形态观察） |
| 缺参 / 类型错 | `editor_set_node_property{path}` → `-32602 "Missing required parameter: property"`；`path=42` → `-32602 "Parameter 'path' must be a string, got float"` | PASS |
| 批量事务（故意坏中间元素，值不兼容） | `[GoodA, BadMid(position={"x":"abc"}), GoodB]` → **单个 `-32602`**，`nodes[1]: …`，**场景树逐字节相同** | PASS |
| 批量事务（故意坏中间元素，bool 垃圾） | `[GoodC, BadBool(visible="abc")]` → `-32602`，场景树逐字节相同 | PASS |
| 批量事务（合法） | `{"count":3,"updated":3,"nodes":[".","Actor","D4Node"],"status":"ok"}`，节点**确实**被改 | PASS |
| 跨场景事务（一个好文件 + 一个坏文件） | 坏文件在 `res://xscenes` 中 → `-32000 "Refusing to write: 1 scene(s) of 'res://xscenes' cannot take this call"`，`data.scenes.errors=[{scene,reason:"not a loadable PackedScene"}]`、`data.suggestion` 含 **"Nothing was written"**，`good.tscn` sha256 **不变**；移除坏文件后同一调用 → `Applied`、sha 变化、文件内 `Vector2(11, 22)` | PASS |
| 无匹配节点 / 属性不存在（批量） | `-32001` 前置拒绝（**未写入**）；消息**无** `not found not found` 重缀 | PASS |
| UID 双向（方向搞反） | `uid_to_path("res://main.gd")` → `-32602`；`path_to_uid("uid://…")` → `-32602` | PASS |
| 跨端点调用 | `-32601` 且不执行 | PASS |

**结论：安全与事务类全部 PASS，未观察到「报成功但只做一半」。**

---

## 6. 延迟通道（D 段）

| 检查 | 实测 |
|---|---|
| 超时 | `running_game_find_node_when_available('/root/NoSuchNodeEver', timeout=1.0)` → **1053 ms** 返回 `-32000 "Deferred call timed out after 1000 ms: waiting for node '…'"` |
| pending 期间/之后常规请求仍毫秒级 | 紧接着 `running_game_get_scene_tree` → code=0，**29 ms** |
| 多 pending 不串线 | 第二次 deferred（另一个节点名）消息**只含自己的节点名**（`'/root/NoSuchNodeEver2'`，且不含 `'/root/NoSuchNodeEver'`） |
| pending 归零不崩 | 两次超时之后端点继续正常服务（后续断言/压力/采样/信号/属性读写全部 code=0） |
| 多帧采样 | `running_game_get_node_property_samples(frame_count=5)` → code=0 |
| 压力测试 | `{"completed":true,"crashed":false,"iterations_completed":3,"game_still_running":true}` |
| 信号监视 | `capture_signal_emissions(duration_ms=1500)` → `count=218`，首条 `{"args":[302],"node":"/root/Root/Actor","signal":"pulse"}` |

**结论：延迟通道 PASS。**

---

## 7. 工程门（G 段，全部在 `08f0bd529` 的 `tests=yes` 二进制上串行运行、未抑制输出）

| 门 | 命令 | 结果 | 退出码 |
|---|---|---|---|
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **184 cases / 184 passed / 0 failed**（1429 skipped）；**7509 assertions / 7509 passed / 0 failed**；`Status: SUCCESS!` | **0** |
| ④ 全引擎 | `--headless --test` | **1610 cases / 1610 passed / 0 failed / 3 skipped**；**431791 assertions / 431791 passed / 0 failed**；`Status: SUCCESS!` | **0** |
| ⑤ 批收口 | `accept_m1.ps1` **连跑两次** | 两次均 **22/22 cases passed**；两次 `[PASS]` 清单 `Compare-Object` **diff = 0**（22 行逐行相同）；两次都打印 `derived tool union : 113 tool(s) …` 与 `implemented tools = 91 (editor endpoint) / 53 (game endpoint); contract = 171` | **0 / 0** |
| tool-groups | `check_tool_groups.py --batch B3` / `--batch B4` / `--check-completeness` / 无参（B1 路径） | 四项均 `… CHECK PASS`（B3 40、B4 7、`40+7+58=105` 两两不相交、B1 `41 == 42 - 1`） | **0 / 0 / 0 / 0** |

证据文件：`%TEMP%\audit-m4b\gate3_doctest.txt`、`gate4_full.txt`、`accept-run1.txt`、`accept-run2.txt`（含 `check_tool_groups` 全文）。

### 7.1 门脚本是否真的不再需要手工改（任务书第 12 项）

**证实：`$ToolNames` 确实由 manifest 派生，无硬编码并集。**

- 结构核对：`$ManifestFileNames = @('tool-groups.json','tool-groups-b2.json','tool-groups-b3.json','tool-groups-b4.json','tool-groups-b5.json')`
  循环、仅累积 `implemented -eq $true` 的组，并有 `if ($ToolNames.Count -eq 0) { throw … }` 兜底；
  `$EditorOnlyToolNames`/`$GameOnlyToolNames`/`$EditorToolNames`/`$GameToolNames` 由 `Get-ToolScope` 读 `tool-rename-map.json` 派生。
- **独立交叉验证**（自撰 `check_accept_derivation.py`）：脚本 sha256 = `8d89a02bab8ea0a5f2bd92db616d3bde3502cfc46375b7ad57fdfc5b49a006d2`（**与首轮一致**）；
  991 条可执行行中「形如工具名」的字面量**仅 3 处**，全是**单个 case 的示例调用**
  （`project_get_info` ×2 于 case4/case5、`editor_get_errors` 于 case12 的 editor-scope 泄漏检查），**不是清单**；
  `$ToolNames = @("…")` 形式的硬编码并集**不存在**。
- 我的 `analyze_equality.py` 直接从 5 个 manifest 推导 → `union=113 editorEndpoint=91 gameEndpoint=53`，与脚本输出、与线上实况**三方一致**。

---

## 8. 端口纪律（P 段）

| 检查 | 结果 |
|---|---|
| 开工前 9877 | owner = **36392**（用户 `Godot_v4.7.1-stable_mono_win64`，与本次无关） |
| 9888 / 9889 开工前 | 均空闲（owner = -1） |
| 我们的测试实例归属 | 9888/9889 的 socket owner 是**我方 launcher 的子孙进程**（`chain=61352>30892>37068`、`63092>62748>37068`，逐级 `ParentProcessId` 证实；`.console.exe` 派生真正引擎进程故 PID 不等，是预期） |
| 运行中 9877 | 多次采样（含**单独重启游戏实例**前后、验收脚本前后）**始终 36392** |
| 收尾后 | 9888 / 9889 均 owner = -1；9877 仍为 **36392**、进程存活 |
| 孤儿进程 | 两个 launcher 的整棵进程树遍历，收尾后 **surviving descendants 为空**；全机仅剩用户自己的 PID 36392 |
| `editor_play_scene` 子进程 | 本次未调用 `editor_play_scene`，故无此类子进程 |
| 全程 | **未占用、未杀、未重启 9877**；未修改任何被跟踪文件；未执行 git 写操作 |

---

## 9. `defects`

### D-4（severity: **high**）标量 `real_t` 属性的槽位宽未判定——`1e300` 静默写成 `inf` 并报成功

- **claim**：TASK-021 的「槽位宽」判定只覆盖 **packed 容器元素**（A-2）与 **复合值的分量**（A-4），
  **没有覆盖普通标量属性**。单精度构建里 `Node2D.rotation` 等属性成员是 `real_t` = **`float`**，
  而 `coerce_to_property_type` 对 FLOAT 目标只判 nan/inf 与 INT 范围，随后
  `p_value.get_type() == p_target_type` 直接放行，`Object::set()` 里的 `double → float` 收窄把
  `1e300` 变成 `inf`、`1e-300`/`1e-46` 变成 `0`，调用返回 `code=0`。
  这正是 D67 裁决与 PLAYBOOK §7.7 要根除的「值表达不出来 → 引擎按自己的语义写 → 工具报成功」，
  也是 TASK-021 §5「同类面已清零」断言的**反例**（该断言的自查范围明写「一切把 JSON 值写进有类型槽位的路径」）。
- **evidence（全部本次自行构造）**：
  - `editor_set_node_property(Actor, rotation, 1e300)` → **code=0**，响应 `new_value = 1e99999`；
    `editor_execute_gdscript` 读回 **`inf`**；`editor_get_node_properties` 读回 **`null`**（非有限 float 的序列化）；
    `main.tscn` sha256 前后相同。
  - `rotation = 3.5e38` → `inf`；`rotation = 1e-300` / `1e-46` → `0.0`；`rotation = "1e300"` → `inf`（均 code=0）。
  - **同样缺口在 4 条其它写路径复现**：`editor_set_node_property_batch`（3 节点全写 `inf`）、
    `editor_add_nodes_batch`（新节点 `rotation=inf`）、`running_game_set_node_property`（9889）、
    **`project_set_node_property_across_scenes`（`dry_run=false,force=true` → `xscenes/good.tscn` 内真的写入 `rotation = inf`，`message="Applied…"`）**。
  - 对照：float 可表达的 `1e30` / `1e20` 写入正确，说明缺口只在**收窄**处。
  - 首轮的三条判据在此**结构性失效**：第 ③ 条（读回旧值）因值真的被改而无旧值可读；
    第 ② 条（sha 相同）在未 `save` 时恒真（本轮已用控制实验证明它只在 save 后有判别力）。
  - 证据文件：`results-phaseB2.json`（`N_rot_*`）、`results-phaseC.json`（`D4_batch_*`、`D4_game_*`）、
    `results-phaseD.json`（`D4_xscene_rotation_1e300_reaches_the_file`）、`evidence/N_rot_1e300*.response.json`。
- **location**：`modules/mcp_server/tools/tool_helpers.cpp` 的 `coerce_to_property_type`（FLOAT 分支 `:838-848`、
  同类型直通 `:988`、`type_convert` 出口 `:1029`）；
  对照已修的 `running_game_node_write.cpp:276-317`（`_component_fits_slot`）与 `tool_helpers.cpp:745-797`（`_element_fits_container`）。
- **recommendation**：把「槽位宽」提为一条**作用于最终 Variant→属性成员收窄的统一预校验**：
  对目标为单精度 `real_t` 的**标量**属性补 `|x| > FLT_MAX → -32602` 与 `x != 0 && (float)x == 0 → -32602`
  （消息须给出引擎会写的值），并在**任何写入之前**拒绝，批量与跨场景路径复用同一预校验以保持全成功/全回滚。
  新证据形态必须是：「响应回显值**有限**」+「落盘文件里**没有** `inf`」+「另一读工具读到旧值」三者同时成立。

### D-5（severity: **medium**）`project_create_resource` 的 `properties_set` 是未经回读校验的断言

- **claim**：`project_create_resource` 返回 `{"properties_set":[...]}` 与 `code=0`，**没有**读回写入后的真实值；
  当引擎自身的属性 setter 静默忽略该值时，工具仍把该属性列为「已设置」。
  同族的 `project_edit_resource` 反而**会**回读（返回 `changed:{prop:{old,new}}`），两个入口口径不一致。
- **evidence**：
  - `project_create_resource(path='res://cv_normal.tres', type='Curve', properties={min_value:5.0})`
    → `{"changed":{},"properties_set":["min_value"],"type":"Curve"}`，`code=0`；
    文件 `_limits = [0.99, 1.0, 0.0, 1.0]`；GDScript 直接 `load(...).min_value` → **`0.990000009536743`**。
  - 同法 `min_value=1e300` → 同样 `properties_set:["min_value"]`，实际值仍 `0.99`。
  - 反向对照：`properties={min_value:0.25, max_value:0.75}` → `_limits=[0.25,0.75,…]`，读回 `0.25/0.75`（正确）；
    直接用 GDScript 复现引擎语义 `Curve.new().min_value = 5.0` → `0.99`（即 **setter 本身忽略**，非工具 bug 之外的路径）。
  - `project_edit_resource('res://cv_small.tres', {min_value:99.0})` → `{"changed":{"min_value":{"new":0.740000009536743,"old":0.25}}}`（**真回读**）。
  - 证据：`evidence/CV1/CV2/CV3*.response.json`、`R1/R2/R3/R4/R5/R6*.response.json`、`logs/editor.err.txt`。
- **location**：`modules/mcp_server/tools/project_write_resource_scene.cpp`（`project_create_resource` 的结果构造，
  与 `:463` 的 `project_edit_resource` 形成对照）。
- **recommendation**：`project_create_resource` 复用 `project_edit_resource` 的 `changed:{old,new}` 回读形状，
  或把 `properties_set` 改为「**实测**已设置」的列表（对 setter 忽略的属性剔除或直接 `-32602`）。

### D-6（severity: **medium**）`editor_get_test_report` 的累加器在任何可达端点上都不可能非空

- **claim**：`editor_get_test_report` 是 **editor-only**（manifest 与 registration 均为 `MCPToolScope::EDITOR`），
  读的是**本进程**的 `record_test_result` 静态累加器；而 `record_test_result` 的**全部三个调用点**
  （`running_game_assertion.cpp:160`、`:242`，`running_game_test_execution.cpp:466`）都在 **game-scope** 工具里，
  这些工具在编辑器端点根本未注册（跨端点调用实测 `-32601`，且不执行）。
  因此编辑器端点的 `total` **恒为 0**——「真的累积」这条能力在**客户端可观测范围内不可达**，
  与契约「获取测试结果报告」的可用性不符。
- **evidence**：
  - 线上：`editor_get_test_report` 在 9888 恒为 `{"total":0,"passed":0,"failed":0,"pass_rate":"N/A","all_passed":false,"no_results":true,"source":"editor_process"}`；
  - 跨端点反证：9889 调 `editor_get_test_report` → `-32601`；9888 调 `running_game_assert_node_state` → `-32601`（**不执行**），
    之后 9888 报告仍 `total=0`；
  - 源码枚举：`grep record_test_result` 只有上述 3 个 game-scope 调用点；
  - 相关注释（`running_game_test_execution.cpp:229-232`）假设「an editor-side caller that drives a scenario **in this process**」，
    但该前提在 scope 分离下不可能成立；`running_game_assertion.cpp:86-93` 反而**明确声明**了游戏侧结论对编辑器报告不可见。
- **location**：`tools/editor_testing_read.cpp:95-101`（读）+ `tools/running_game_assertion.cpp:160/242`、
  `tools/running_game_test_execution.cpp:466`（写）。
- **recommendation**：二选一并写进契约与规范——① 增加一个 **game-scope** 的报告读取工具
  （或在 `editor_get_test_report` 上按 `target: "game"` 参数把请求转发到游戏端点）；② 或者明确把该工具降级为
  「编辑器进程内的断言报告（当前恒空）」，并在 `description` 里写清、在 `data` 里给出「本进程无断言写入者」的原因字段，
  避免调用方把它当成全局测试报告。

---

## 10. 观察（**未判为缺陷**，逐条给出理由）

- **O-1 读方向：非有限 float 序列化为 `null`**。持有 `inf` 的属性，`editor_get_node_properties` 返回 `null`
  （`serialize_variant` → JSON 对非有限值输出 null）。这是 D-4 的**后果**，修 D-4 后自然消失；单独修读数形态属于契约变更。
- **O-2 int32 标量槽（如 `z_index`）越界被引擎丢弃，但工具**诚实**报告**：`z_index=3000000000`
  → `code=0`，响应 `{"new_value":5,"old_value":5}`（**报告的是写后真值**）；引擎日志
  `ERROR: Tried to set Z index to an invalid value: -1294967296. Z index must be between -4096 and 4096.`
  （`logs/editor.err.txt:282+`）。`z_index=5` 正常写入。**不是静默错值**（响应不含错误值），但调用方需比较 `new_value`。
- **O-3 `INT → BOOL` 用 `booleanize`**：`flag=1` → `true`、`flag=2` → `true`（非零即真）。属 PLAYBOOK §7.7
  「已声明的确定性转换」。`flag="abc"` 已被 A-1 闸门拒绝。
- **O-4 `BOOL → FLOAT`**：`position={"x":true,"y":1}` → `(1.0, 1.0)`。`can_convert(BOOL, FLOAT)` 为真，属已声明转换。
- **O-5 `"0" → false` 与引擎 `booleanize("0")==true` 背离**：源码注释与 REPORT-021 已显式声明，
  且写「拼写所指的值」比引擎的 `!is_empty()` 更符合调用方预期。**必须在契约里写明**。
- **O-6 `FLOAT → COLOR` 不可达**：JSON 数字一律解析为 FLOAT，而 `can_convert(FLOAT, COLOR)` 为假，
  故 `tint=16711680` → `-32602`；REPORT-021 §3 #16 声明的「`INT → COLOR`（`Color::hex`）不修」这条路**从 JSON 边界不可达**。
- **O-7 `PACKED_INT32_ARRAY` 元素为浮点时按已声明截断**：`bytes=[255.9]` → `[255]`；这是 §7.7 明确列为
  「已声明的确定性转换」的一类（整值 FLOAT→INT），不是失败默认值。
- **O-8 截图工具的路径逃逸返回 `-32001`（而非 `-32602`）**：`res://../../../../Windows/win.ini` → `-32001 "Image '…' not found"`。
  **响亮失败且未读到项目外文件**，故不判缺陷；若要与读侧其它工具口径一致可改为 `-32602`。
- **O-9 `editor_list_signal_connections` 的 `count` 含编辑器内部连接**：契约描述明文如此；
  实测 `node_path='Actor'` 子串匹配在连接前后为 **3 → 2**（断开确实只去掉 1 条）。契约如此，非缺陷。
- **O-10 `Vector4i` 无分量表**：`vector_from_dictionary`/`_vector_components` 覆盖 Vector2/2i/3/3i/4/Color，
  无 `VECTOR4I`；对 `Vector4i` 目标传对象会走 `can_convert(DICTIONARY, VECTOR4I)=false` 的**响亮拒绝**，
  不是静默错值，故不判缺陷（本机 scratch 场景未构造到 `Vector4i` 属性的实例，记入 `unconfirmed` 的边界）。

---

## 11. `unconfirmed`（本轮未能独立证实/证伪，如实列出）

1. **`editor_get_test_report` 的编辑器侧「累积」端到端**：我确认了累加器是进程内静态、写入点全在 game-scope、
   跨端点调用被 `-32601` 挡住（因此**不可达**，见 D-6），但**没有**构造出编辑器进程内累加器由 0 变非 0 的场景——
   因为按 scope 规则它不存在。D-6 的结论由**源码枚举 + 线上跨端点反证**支持，而非「编辑器侧报告由空变非空」的实测。
2. **`Vector4i` / `Rect2` / `Transform2D` 等复合属性的分量槽位宽**：本轮 scratch 工程只覆盖
   Vector2/2i/3/4/Color 与 packed 容器；这些类型的 JSON 对象形态在本 fork 里多以
   `can_convert(DICTIONARY, X)=false` **响亮拒绝**（我用 `EditorPropertyInfo` 之外的路径确认了 Vector4i 的拒绝逻辑），
   但**未在线构造实例**验证。按同族推断它们不会有静默错值（因为根本不进入分量表），故不计入缺陷。
3. **`editor_analyze_screenshot_diff` 的「真·视口截图」路径**：`editor_capture_screenshot` 在 `--headless` 下
   返回 `-32000`，**无法**用引擎自己编码的截图验证 `save_path` 分支。我改用**自建的真 PNG**
   （`System.Drawing` 生成 4×4 纯色 PNG，落 `res://diff_red.png` / `res://diff_blue.png`）完成了
   `identical`/`changed_pixels`/`diff_percentage`/`threshold` 越界/缺失文件五项验证。
   **未验证**：headless 之外的截图落盘分支、base64 入参分支。
4. **`project_create_resource` 的 D-5 是否普遍**：我只构造了 `Curve.min_value`/`max_value` 一个
   「setter 静默忽略」的属性族；未穷举其它资源类型的 setter 语义。
5. **首轮 `R-5`（`--import` 首次偶发 0xC0000005 崩溃）**：本轮 3 次 `--import` 全部**一次成功**
   （`import attempt=1 exit=0` × 3），**未复现**该偶发，故不重复报告。

---

## 12. `risks`

1. **D-4 是同一「槽位宽」判定第三次被漏掉**：A-2 补了容器元素、A-4 补了分量，标量仍漏。
   **只按「容器/分量」清单逐类补丁的做法已被证明会继续漏**。建议把判定改为「**任何 Variant → 任何 C++ 成员收窄**」
   的统一原则（含 `float`/`int32`/`uint8` 及未来的 `double`/`int64` 例外），并写进 DESIGN-DETAIL 的写值闸门小节。
2. **首轮的证据形态（sha 相同 + 读回 ≠ 请求值）不足以发现 D-4**：本轮已再次证明它在「值真被改」与
   「编辑器未 save」两种情形下都会给出假绿。**必须把「响应回显值必须有限」与「落盘文件不得含 inf/nan」列为显式验收条款**。
3. **D-6 意味着「测试结果报告」这条链在客户端不可用**：若后续批次按 `editor_get_test_report` 判断「测试真的跑了」，
   将永远看到 `total=0` 并可能误判为「测试没跑」。需在契约里澄清或补一个 game-scope 读取入口。
4. **`Curve.min_value` 一类引擎 setter 语义**：D-5 的手法是「工具不复核写后状态」；同类资源属性如果还有，
   会以「报成功但没写」的形式继续存在。建议统一为「写后回读并报告真值」。
5. **`build_local.cmd` 的陈旧 test 对象陷阱仍在**：脚本自身**不**删除陈旧 obj（注释说明这是有意的）。
   本轮恰好未触发（obj 比头文件新），但下一位验收者若在改动 `test_mcp_server.h` 后直接重建，门③ 可能跑旧用例而假绿。
   建议把「删除陈旧 test obj」做成 `build_local.cmd -Force` 选项，或写进任务书的门配置。
6. **`--headless` 下的截图/视口能力缺口**：`editor_capture_screenshot` 返回 `-32000`，
   使截图相关工具的真实视口分支无法在自动化门里覆盖。建议在任务书里明确「截图类工具需窗式运行」或提供离屏替代。

---

## 13. `verdict`（按任务书要求的分类）

| 分类 | verdict | 依据 |
|---|---|---|
| **全量对等**（含 scope） | **pass** | 113/113 `implemented=true` 线上可见；9888=91、9889=53 与按 `scope` 对称推导的期望集合**双向差集为空**；`description`+`inputSchema` 逐字相等（91+53 条零差异，含键集）；跨端点 `-32601` 且不执行 |
| **诚实性** | **fail** | D-1/D-2 与 TASK-021 的五个面**全部核实闭合**，4 个已修 fix-first **均证实真做到**，3+2 个未注册工具**确未上架**；**但**同族残留 **D-4（high，标量 `real_t` 静默写 `inf`/`0` 并报成功，5 条写路径含落盘文件）** 与 **D-5（medium，`project_create_resource` 的 `properties_set` 未回读校验）** |
| **行为一致** | **fail** | 抽样 25+ 工具，绝大多数与契约/迁移源的可观察条款一致；D-3（assert 缺 `reason`）**已闭合**（两入口字段集一致）；首轮两项 `unconfirmed`（跨场景坏文件全或无、截图 diff）**本轮已自行跑通**；**但 D-6（medium）**：`editor_get_test_report` 的累加器在任何可达端点上都不可非空，能力与契约宣称不可达 |
| **安全与事务** | **pass** | 批量两条路径**全成功或全回滚**（场景树逐字节比对，含两种坏值）；跨场景「好+坏」**Nothing was written** 且好文件 sha 不变；路径逃逸（读写/相对/绝对/截图第三条路径）全部**响亮失败且无副作用**；缺参/类型错 `-32602`；UID 方向搞反**响亮失败**、正向往返一致；`project_set_setting` 类型保真 |
| **延迟通道** | **pass** | 超时 1053ms→`-32000`；多 pending 不串线；pending 后常规请求 29ms；多帧采样/压力/信号监视（218 次发射）均正常 |
| **工程门** | **pass** | 模块 doctest **184/184·7509**；全引擎 **1610/1610·431791**；`accept_m1` **22/22 ×2、PASS 清单 diff=0**；`check_tool_groups` B3/B4/completeness/B1 **四项 exit 0**；`$ToolNames` 经独立扫描证明确由 manifest 派生（113/91/53 三方一致），无硬编码残留 |
| **端口纪律** | **pass** | 9877 全程 pid **36392**（多次采样含收尾后）；仅用 9888/9889；收尾无监听、无孤儿子孙进程；**未修改任何被跟踪文件、未执行 git 写操作** |

### 总 verdict：**`fail`**

**本轮的核心结论**：
1. **D-1（五种分量值）与 D-2（字符串）在编辑器与游戏两端、用两种独立读工具全部复核为已闭合**；
2. TASK-021 声称的五个面（`STRING→BOOL`、packed 元素位宽、`Vector4` 元素、分量槽位宽、`STRING→COLOR`）
   经同样的对抗性反例复核，**五个面本身全部闭合**；
3. **但同一缺陷类的面没有清零**：自己找到的 **D-4（标量 `real_t` 槽位宽）** 仍能「报成功并写错值」，
   且**能落到磁盘文件**（`rotation = inf`），在 5 条写路径上复现。这属于本项目最核心的诉求，
   必须回到阶段四（实现）再派新子代理修复；
4. 另有两处次级缺口：D-5（`project_create_resource` 未回读校验）与 D-6（`editor_get_test_report` 累加器不可达）。

---

## 14. `next_step_recommendation`

1. **优先修 D-4**：把「槽位宽」从「容器元素 / 分量」两处提升为**作用于最终 Variant→属性成员收窄的统一预校验**，
   对单精度 `real_t` 的**标量**属性补 `|x| > FLT_MAX` 与「非零下溢为 0」的 `-32602`；
   必须落在**任何写入之前**，并让 4 条写路径（`editor_set_node_property`、`_batch`、`add_nodes_batch`、
   `running_game_set_node_property`、`project_set_node_property_across_scenes`）复用同一处。
2. **D-4 必须用新证据形态验收**（旧形态会假绿）：① 响应回显的 `new_value` 必须**有限**；
   ② 落盘 `.tscn` 中**不得出现** `inf`/`nan`（用 `project_set_node_property_across_scenes` 的 `dry_run=false,force=true` 路径钉住）；
   ③ 另一读工具读到旧值。**只比较「读回值 ≠ 请求值」不算证据。**
3. **修 D-5**：`project_create_resource` 复用 `project_edit_resource` 的 `changed:{old,new}` 回读形状，
   或对 setter 忽略的属性从 `properties_set` 中剔除/直接拒绝。
4. **裁决 D-6**：要么补一个 game-scope 的报告读取入口（或给 `editor_get_test_report` 加转发参数），
   要么把「本进程断言报告（当前恒空）」写进 `description` 与 `data`，避免调用方误读。
5. **文档**：把「槽位宽必须与转换关系分开判、且覆盖**标量**成员」写进 `DESIGN-DETAIL.md` 的写值闸门小节
   （PLAYBOOK §7.7 已有原则，但需落到「凡是写进 C++ 成员的值都要判宽度」这一条）；
   并把 `projects_create_resource` 的写后回读要求写进规范。
6. **补验建议列入下一轮任务书**：`Vector4i`/`Rect2`/`Transform2D` 等复合属性的分量宽度、
   窗式（非 headless）下的截图落盘与 base64 入参分支。
7. **回归范围**：修完 D-4/D-5 必须重跑本报告的 `N_rot_*`、`D4_*`、`CV1-3`、批量事务段，以及门③~⑤
   （用 `tests=yes` 的 `build_local.cmd` 重建；若改了 `test_mcp_server.h` 必须先删除陈旧 test obj）。

---

## 附录 A：证据与复现

- **harness（本次自建，未复用首轮脚本）**：`%TEMP%\audit-m4b\`
  - `common.ps1`（`curl.exe -s -o` + `ConvertTo-Json -Depth 32` 请求体、sha256、端口/进程树、launcher 管理）
  - `helpers.ps1`（`Get-Probe` = GDScript 独立读、`Get-PropsText` = 模块序列化读、`Invoke-Case` 三判据封装）
  - `analyze_equality.py`（**按解析后的 `name` 字段**做集合与逐字段相等 + scope 对称推导）
  - `check_accept_derivation.py`（`accept_m1.ps1` 的 `$ToolNames` 派生性与硬编码残留扫描）
  - `up.ps1` / `down.ps1`（两端点启停 + 端口/进程树证据）、`probe*.ps1`（读通道自检）
  - 相位脚本 `phase_a/b/b2/c/d/d2/e/e2/x/curve*.ps1`
- **证据体**：`evidence\*.request.json` / `*.response.json`（每个请求与响应原样落盘）+ `transcript.log` 中的 sha256
- **结果集**：`results-phase{A,B,B2,C,D,D2,E,E2,X}.json`（合计 **197 条** check；另有 `phase_curve*` 的观察性输出）
  - 17 条 `pass=false` 的记录**全部已定性**：5 条是我的期望字符串书写错误（行为实际正确，已在 `results-phaseB2.json` 的 `FIX_*` 重测为 PASS）、
    2 条是我预期 `-32602` 而实现给出正确的 `-32001` 前置拒绝、1 条是我对「连接数 1」的错误假设（实际 3→2，正确去掉了 1 条）、
    5 条是 headless 下 `editor_capture_screenshot` 不可用（已在 `results-phaseD2.json` 用自建 PNG 重测为 PASS）、
    2 条是场景失败字段名（`results` 而非 `details`）与「探针脚本无 `pulse` 信号」的测试装置问题（已在 `results-phaseE2.json` 重测为 PASS）、
    1 条是截图工具的路径逃逸形态（`-32001` 而非 `-32602`，见 O-8）、1 条是 `Curve.min_value`（升级为 D-5 缺陷）。
- **对等分析全文**：`eq\equality.txt`、`eq\equality_stdout.txt`
- **门输出**：`gate3_doctest.txt`、`gate4_full.txt`、`accept-run1.txt`、`accept-run2.txt`（`check_tool_groups` 四项目输出在 transcript 内）
- **构建**：`%TEMP%\mcp_server_build_local.log`（`tests=yes`，`EXIT_CODE=0`，未抑制输出）
- **临时改动还原**：**未修改任何仓库文件**（含测试文件），改动只在 `%TEMP%\audit-m4b\` 与本报告，故无「还原留证」事项。