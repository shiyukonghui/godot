# REPORT-AUDIT-M4 — 里程碑级独立验收：B3+B4（47 个工具）

- 任务书：`docs/tasks/TASK-AUDIT-M4.md`
- 验收方：**独立验收工程师**（未参与任何实现；**未采信** `REPORT-0*.md` 与决策者结论，全部结论均由本次自行运行产生）
- 日期：2026-09-22
- 仓库：`F:\RustProjects\godot-mcp-pro\code\godot`
- **被验二进制**：`bin\godot.windows.editor.x86_64.console.exe`，`--version` = `4.8.dev.custom_build.5ece15100`，
  `git rev-parse HEAD` = `5ece15100815373270b2df3f0b96993dd7f52bfc`（前缀一致，9 字符）
- 二进制 SHA256：`6FC7BC549E4DB5B11AA687F8A52C730F89C5DA094DB14397053F7CDCA3698989`（重建后同值）
- 工作树终态：`git status --porcelain` 仅 4 个**既有**未跟踪项（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）；
  **本次未修改任何被跟踪文件，未执行任何 git 写操作**
- 临时根目录：`%TEMP%\audit-m4\`（harness、证据体、sha256、JSONL 逐条记录）
- 端口纪律：9877 全程属于用户 PID 36392；本次仅用 9888 / 9889

---

## 0. 开工第一步：`--version` 与 HEAD 校验（**发现真实差异，已重建**）

首次校验即不一致：旧二进制 `4.8.dev.custom_build.a63583c6a`，HEAD `5ece151008`。

自行核实差异来源（不靠推断）：

```
git cat-file -t a63583c6a            -> commit        （旧二进制对应真实旧提交）
git diff --stat a63583c6a..HEAD      -> 16 files changed, 5127 insertions(+), 94 deletions(-)
  其中包含 modules/mcp_server/tools/editor_testing_read.cpp/.h、
  running_game_assertion.cpp/.h、running_game_test_execution.cpp/.h（**B4 全部源码**）
```

即旧二进制**根本不含 B4**。按任务书要求先重建：

1. 先用仓库根未跟踪包装脚本 `build-m0.cmd` 重建 → `--version` 变为 `5ece15100`（与 HEAD 前缀一致）。
2. **但**随后运行门 3（`--headless --test`）时二进制报
   `--test was specified on the command line, but this Godot binary was compiled without support for unit tests`
   ——`build-m0.cmd` **不传 `tests=yes`**（`SConstruct:254` 默认为 False）。
3. 改用**仓库内被跟踪的**验证过的构建脚本 `modules/mcp_server/scripts/build_local.cmd`
   （其头部注释正是记录了这个陷阱），并按它的要求先删除陈旧 test 目标文件后重建：
   `scons platform=windows target=editor module_mono_enabled=no tests=yes -j8`，`EXIT_CODE=0`，
   `Compiling modules\mcp_server\tests\test_mcp_server.cpp`，耗时 00:01:01；
   **日志未抑制**，位于 `%TEMP%\mcp_server_build_local.log`。
4. 重建后 `--version` = `4.8.dev.custom_build.5ece15100` == HEAD 前缀。

> **本验收所有 `tools/list`、行为、事务、延迟通道与门证据均在上述 `tests=yes` 二进制上采集。**
> 重建前后 `--version` 相同（同为 `5ece15100`），仅测试支持差异，故早前采集的 A/B/C 段证据仍对同一代码有效；
> 关键项（相等性、两个静默错值缺陷、场景运行器、端口纪律）已在最终二进制上**重新采集**。

---

## 1. 全量对等与 scope（A 段）

### 1.1 方法（逐字相等）

- 自己 `POST tools/list` 抓两端点响应体，落盘 `%TEMP%\audit-m4\evidence\P1_*.response.json`，
  记录 `curl.exe -s -o` 退出码、字节数、sha256；请求体一律 `ConvertTo-Json` 生成。
- **集合比对完全基于解析后的 JSON `name` 字段**（`analyze_equality.py`：先 `json.loads`，再取
  `result.tools[].name` 做 Python `set` / `==` 精确比较）。
  **未使用 `-match`、`-like`、`-contains`、`Select-String` 或任何文本包含**来判断工具名存在性。
- `description` / `inputSchema` 用规范化 JSON（`sort_keys=True, separators`）**逐字符**比对 91/53 条。
- 契约 = `docs/tools_list.renamed.json` 的 171 条；期望集由 5 个 manifest 的 `implemented=true` 组并集推导。

### 1.2 结论

| 检查 | 结果 | 证据 |
|---|---|---|
| 契约条数 | 171 | `tools_list.renamed.json` |
| manifest 记录数 / `implemented=true` | 171 / **113** | B1=41 B2=25 B3=40 B4=7 B5=58 |
| 端点实况 | **9888 = 91，9889 = 53** | 见下 |
| 并集 == `implemented=true` 集合 | PASS | 两个方向差集**均为空** |
| 未实现却上架 | PASS | `advertised but not implemented: []`（105 条未实现工具无一泄漏） |
| 实现了却缺席 | PASS | `implemented but never advertised: []` |
| 上架但不在契约 | PASS | `[]` |
| `description`+`inputSchema` 逐字相等 | PASS | 9888 的 91 条、9889 的 53 条**零字段差异** |
| 重名 | PASS | 两端 `duplicate names: []`，`empty names: []` |

**端点 scope 分离（按 `scope` 唯一事实源推导）**：`implemented=true` 113 = editor-only 60 + game-only 22 + both 31。

- 编辑器端点期望 = editor-only + both = **91**，实况 91，`missing=[] extra=[]`
- 游戏端点期望 = game-only + both = **53**，实况 53，`missing=[] extra=[]`
- `scope=editor` 出现在 9889：**0 条**（PASS）
- `scope=game` 出现在 9888：**0 条**（PASS）
- 31 个 both 在两端**都**可见（PASS）

**跨端点调用必须 `-32601` 且不执行**：

- 向 9889 调 `editor_get_test_report` → `{"code":-32601,"message":"Method not found: editor_get_test_report"}`，
  `result` 为 null（**未执行**）。
- 向 9888 调 `running_game_assert_node_state` → `-32601`，`result` null（未执行）；随后 9888 的
  `editor_get_test_report` 显示 `total=0, no_results=true`，证明跨端点调用**没有**进入累加器。
- 未知名 `no_such_tool_at_all` → `-32601`。
- 非 `/mcp` 路径 → `{"error":"Not Found"}`（21 字节），不服务。

**`unconfirmed`（非缺陷）**：任务书与 D67 都写「按 `scope` 逐端点过滤」，而 `DESIGN-DETAIL.md` §17.3 同一段文字
先写「`scope=both` 两端都出现」，后写「编辑器端点的期望集合是全体」，两说不相容。**实况与后者不符、与前者的
对称规则相符**，且 `accept_m1.ps1` 自身用的也是对称公式（`$EditorToolNames = union - game-only` = 91，
`$GameToolNames = union - editor-only` = 53），其 `gate_scope_declared` PASS。判为**文档措辞不一致**，
不判实现缺陷（实况满足对称规则，且无任何 `scope` 不允许的端点出现该工具）。

---

## 2. 诚实性（B 段，本项目核心诉求）

### 2.1 7 个 `fix_implementation_first` 的现状

**已修 4 个：逐条自行构造证据，全部证实**

| 工具 | 结论 | 我自己的证据 |
|---|---|---|
| `editor_disconnect_signal` | **真的做到** | `project_create_script` 建 `sig_target.gd` → `editor_set_node_script` 挂到 `Actor` → `editor_connect_signal(tree_exited→_on_pulse)`；`editor_list_signal_connections` 中匹配 `{source:Actor,target:Actor,method:_on_pulse}` 条数=1；`editor_disconnect_signal` → code=0 `{"disconnected":true,...}`，再查同一条数**=0**。**反例**：`target_path='Ui'`（迁移源把 Callable 固定成场景根的那个 bug 面）→ `-32001 "Connection from signal 'tree_exited' to method '_on_pulse' not found"`，且那条连接**仍在（=1）**——不会误删别的连接。 |
| `editor_set_auto_dismiss_dialogs` | **真的做到（改为诚实拒绝）** | 线上返回 `-32000 "Not implemented: editor_set_auto_dismiss_dialogs"`，**`result` 为 null**，`data.suggestion` 给出真实可用的替代旋钮（per-dialog `hide_on_ok`、`accept_dialog_cancel_ok_buttons`）。响应中**不含** `auto_dismiss` 字段，即**不回显请求值**（旧迁移源正是用回显的 `{"auto_dismiss":true}` 伪造成功）。参数校验在前：`enabled="yes"` → `-32602 "Parameter 'enabled' must be a boolean, got String"`。 |
| `editor_get_test_report` | **真的做到（真累积、不伪造）** | ①空报告诚实：`{"total":0,"passed":0,"failed":0,"pass_rate":"N/A","all_passed":false,"no_results":true,"source":"editor_process"}`，字段中**没有**迁移源那句伪造 `message`，也没有「工具名清单」。②真的累积：源码核对 `record_test_result` 的唯一调用者是 `running_game_assertion.cpp:166/255` 与 `running_game_test_execution.cpp:441`，`build_test_report` 只统计带布尔 `passed` 的记录（input/wait 步骤不计）。③**累积链在报告 3 段由场景运行器与 9889 累加器实测覆盖**（见 §4）。 |
| `editor_remove_output_log` | **真的做到（测量式汇报）** | 线上两次调用返回**测得的**面板状态：第 1 次 `{"cleared":true,"log_was_empty":false,"log_is_empty":true}`，第 2 次 `{"cleared":true,"log_was_empty":true,"log_is_empty":true}`——`log_was_empty` 由 false→true，是**跨调用可观测的状态变化**。源码核对：先 `require_editor_ui` 守卫（无编辑器则 `-32000`，绝不报成功），再调 `EditorNode::get_log()->clear()`（面板 Clear 按钮的同一路径），并把 `RichTextLabel::get_parsed_text()` 的前后空态作为 `log_was_empty`/`log_is_empty` 上报。迁移源旧版在 stdout 打约 50 行空行并恒返 `{"cleared":true}`——本实现**不可能**产生那个形状。 |

**剩余 3 个（B5）仍未注册：证实**

- `editor_set_tilemap_cell`、`editor_set_tilemap_cells_in_rect`、`editor_bake_navigation_mesh`
  → 两端 `tools/list` 的解析名集合中**均不存在**（精确集合判定）。

### 2.2 2 个 `unregister_until_implemented` 仍未注册：证实

- `running_game_move_player_to_target_via_navigation`（旧 `navigate_to`）、`project_export_game`（旧 `export_project`）
  → 两端**均不存在**。

### 2.3 静默错值修复（D67 裁决的落地）

**修复确实生效的部分（回归 + 主路径，PASS）**

7 个受影响工具为 `editor_set_node_property`、`editor_set_node_property_batch`、`editor_add_nodes_batch`、
`running_game_set_node_property`、`editor_add_resource_to_node_property`、`project_create_resource`、`project_edit_resource`
（D67 所列）。本次直接实测其中 4 个的线上行为：

- `editor_set_node_property(position, 1e20)` → `-32602`，消息含目标类型、值拼写 `1e+20`、
  以及**引擎本会写入的值** `{"x":0.0,"y":0.0}`；读回 `position` 仍为 `(3,4)`，`main.tscn` sha256 **前后相同**
  （`646F0204…57BD`）。
- `editor_set_node_property(position, "Vector2(1,1)")`（本 fork 无 `construct_from_string`）→ `-32602`。
- `editor_add_nodes_batch` 中间元素属性不兼容（`position=1e20`）→ `-32602` **且场景树与场景文件均未变**。
- `editor_set_node_property_batch(position, 1e20)` → `-32602 "Property 'position' write refused before any node was written: …"`，
  磁盘 sha256 不变、`Actor.position` 仍为 `(11,22)`。
- `running_game_set_node_property(1e20)`（9889）→ `-32602`。
- 合法值回归：`Vector2`、`int`（`z_index`）、`String`（`name`）、`float`（`rotation`）、`Color`（`modulate`）
  全部 code=0 并读回正确；`project_set_setting` 类型保真 `{int:7, str:"seven", bool:true}`。

**修复未覆盖的静默错值（2 个新缺陷，见 §7）**：D67 的闸门是「整值 → 属性类型」一层，
对**嵌套分量**与**可转换但垃圾的字符串**都不生效。详见 §7 D-1 / D-2。

---

## 3. 批量事务语义（B 段续）

`editor_add_nodes_batch` 用**故意坏的中间元素** `[合法 GoodA, {parent_path:'NoSuchParent'} BadMid, 合法 GoodB]`：

- 返回**单个** `-32001`，带 `data.batch = {"status":"rolled_back","on_error":"all_or_nothing","count":0,"created":[],
  "errors":[{index:1,parent_path:'NoSuchParent',reason:"Parent 'NoSuchParent' not found"}],
  "rolled_back":[{index:0,node_path:'GoodA',reason:"transaction rollback"}]}`；
- `editor_get_scene_tree` 在调用前后**逐字节相同**（含编辑器内部路径的全量 tree JSON 比对）→ **零半成品**。

`editor_set_node_property_batch`：

- 无匹配节点（`Sprite2D`，场景内无）→ `-32001 "No node of type 'Sprite2D' in the edited scene not found"`，
  且**未出现** D45/D66 修过的 `not found not found` 重缀（消息经转义后逐字核对）。
- 属性不存在（`no_such_property_zz`）→ `-32001`，写前拒绝。
- 值布局不兼容 → `-32602`，写前拒绝；磁盘 sha 不变、内存值不变。
- 合法批量 → `{"status":"ok","count":4,"updated":4,"nodes":[".","Actor","BatchOne","BatchTwo"]}`，
  场景树**确实**多了 `BatchOne`/`BatchTwo` 两个节点（成功是真成功，可与上面对照）。

**结论：批量两条路径均为「全成功或全回滚」，未观察到「报成功但只做一半」。**

---

## 4. 行为与宣称一致（C 段，对抗性抽样）

抽样对照 **≥15 个** B3/B4 工具（远超要求），并把响应形状与源码/契约的可观察条款对照：

| 工具 | 实测 | 与契约/迁移源对照 | 判定 |
|---|---|---|---|
| `editor_get_test_report` | 空报告 8 字段、`no_results:true` | 契约「获取测试结果报告」；迁移源恒返回伪造 message | 一致（且已修正） |
| `editor_analyze_screenshot_diff` | 见 §6 未覆盖项 | 契约 3 参 | 未单独构造（`unconfirmed`） |
| `editor_remove_output_log` | `{cleared,log_was_empty,log_is_empty}` | 契约无参；迁移源恒 `{cleared:true}` | 一致（且已修正） |
| `editor_disconnect_signal` | 命中才断开，否则 `-32001` | 契约 4 参（`target_path` 可选） | 一致（且已修正） |
| `editor_connect_signal` | `{connected:true,signal,source,target}` | 幂等时另带 `already_connected` | 一致 |
| `editor_list_signal_connections` | 扁平 `connections[]`+`count`，含编辑器自身内部连接 | 契约明文「收全部连接（不过滤非持久连接）、子串匹配」 | 一致（**注意**：`count` 含编辑器内部连接，与契约描述相符，非缺陷） |
| `editor_set_auto_dismiss_dialogs` | `-32000`+suggestion | 契约「设置编辑器自动关闭对话框行为」 | 一致（且已修正） |
| `editor_add_nodes_batch` | 全成功/全回滚 | DESIGN §17 全成功或全回滚 | 一致 |
| `editor_set_node_property_batch` | 写前校验 + `status ok` | D66 D2 裁决 | 一致 |
| `editor_set_node_property` | 不兼容 `-32602`，合法写入 | D67 裁决 | 主路径一致（嵌套/字符串有缺口） |
| `project_convert_path_to_uid` | 有 UID 则返 `uid://…`；存在但无 UID 返 `""` 且 code=0；文件不存在 `-32001` | 契约「路径未注册时 uid 为空串且不报错」 | 一致 |
| `project_convert_uid_to_path` | 合法 UID 往返一致；给 `res://` 串 → `-32602` | 契约「UID 文本格式非法时报参数错误」 | 一致（方向搞反**响亮失败**） |
| `project_set_setting` | 类型保真、`created/existed_before` 诚实 | D67 P-2 | 一致 |
| `running_game_run_test_scenario` | 通过 `all_passed:true`；失败 `all_passed:false` 且失败步骤带 `expected`/`actual`/`reason` | TASK-019 §1.1 | 一致 |
| `running_game_run_stress_test` | `{completed:true,crashed:false,iterations_completed:3,game_still_running:true}` | 契约无必填参 | 一致 |
| `running_game_assert_node_state` | 通过 `passed:true`；失败 `passed:false`+`actual`/`expected`，**无 `reason`** | 见 §7 D-3 | 部分偏差 |
| `running_game_assert_screen_text` | 通过 `passed:true`+`matched_element`；失败 `passed:false`+`visible_elements[]`，**无 `reason`** | 见 §7 D-3 | 部分偏差 |
| `running_game_capture_signal_emissions` | 1200ms 内 `count:174`，`emitted[]` 带 `args`/帧号/节点/信号 | 契约 | 一致 |
| `running_game_get_node_property_samples` | 多帧采样 code=0 | 契约 | 一致 |
| `running_game_find_node_when_available` | 超时返回 `-32000 "Deferred call timed out after 1000 ms: waiting for node '…'"` | GDR-20 | 一致 |

### 4.1 断言与场景运行器（B4 重点，自行跑通/跑失败）

从 **9889** 发起：

- **应通过**：`steps=[assert(. name == "Root"), assert(./Actor position == {3,4})]`
  → `{"all_passed":true,"passed":2,"failed":0,"errors":0,"completed_steps":2,"duration_ms":20}`。
- **应失败**：`steps=[assert 通过, assert(./Actor position == {999,999}), assert(text="TextThatIsNotOnScreenAtAll")]`
  → `{"all_passed":false,"passed":1,"failed":2,"errors":0}`；
  两条失败记录的字段逐个核对：
  - `{"type":"assert","step":1,"node_path":"./Actor","property":"position","operator":"eq","passed":false,
     "expected":{"x":999.0,"y":999.0},"actual":{"x":3.0,"y":4.0},"reason":"expected position eq {\"x\":999.0,…}"}`
  - `{"passed":false,"type":"assert","reason":"screen text containing 'TextThatIsNotOnScreenAtAll' was not found in the 1 visible
     text(s) of the control tree", …}`
  → **`expected`/`actual`/`reason` 三者齐备**。
- **前置拒绝**：`steps=[]` → `-32602 "Parameter 'steps' must not be empty"`；
  `steps=[{type:'teleport'}]` → `-32602 "Parameter 'steps[0]'.type is 'teleport'; a scenario step is 'input', 'wait' or 'assert'"`；
  缺 `steps` → `-32602 "Missing required parameter: steps"`。

### 4.2 对抗性反例

| 反例 | 实测 |
|---|---|
| 路径逃逸（写侧） | `project_create_script("res://../audit_escape.gd")` → `-32602 "Parameter 'path' must not walk upwards with '..'"`，磁盘上**无**该文件 |
| 路径逃逸（写侧，绝对路径） | `project_create_script("%TEMP%\audit_abs_escape.gd")` → `-32602 "Parameter 'path' must address the project ('res://...')"`，磁盘上**无**该文件 |
| 路径逃逸（读侧） | `project_read_script("res://../../../../Windows/win.ini")` → `-32602`；`project_read_script("C:\WINDOWS\win.ini")` → `-32602` |
| 缺参 | `editor_set_node_property{path}` → `-32602 "Missing required parameter: property"` |
| 类型错 | `path=42` → `-32602 "Parameter 'path' must be a string, got float"` |
| 未知节点 | → `-32001 "Node 'NoSuchNode' not found"`（带 suggestion） |
| 越界/布局不兼容 | 见 §2.3，`-32602` + 读回未被改动 |
| 多场景写（故意坏文件） | **未完成**，见 §6 `unconfirmed` |
| `project_set_setting` 类型保真 | PASS（见 §2.3） |
| `editor_set_node_property_batch` 无匹配节点 | `-32001` 前置拒绝（见 §3） |
| UID 双向（方向搞反） | `project_convert_uid_to_path(uid="res://main.gd")` → `-32602 "Parameter 'uid' is not a valid UID text: 'res://main.gd' … To go the other way, use project_convert_path_to_uid"`；反向 `project_convert_path_to_uid(path="uid://…")` → `-32602`。**响亮失败，非静默错映射**。正向往返一致：`res://main.gd` ↔ `uid://conx4tg60qkj7` |

---

## 5. 延迟通道与工程门（D 段）

### 5.1 deferred（自己在 9889 验证）

- **超时**：`running_game_find_node_when_available('/root/NoSuchNodeEver', timeout=1.0)`
  → 实测 **1,037 ms** 返回 `-32000 "Deferred call timed out after 1000 ms: waiting for node '/root/NoSuchNodeEver'"`。
- **pending 期间/之后常规请求仍毫秒级**：紧接着 `running_game_get_scene_tree` → code=0，**32 ms**。
- **多 pending 不串线**：紧接第二次 deferred 调用（另一个节点名）→ 各自消息**只含自己的节点名**
  （`'/root/NoSuchNodeEver2'`），并通过 `-notmatch` 断言确认第二条消息**没有**夹带第一条的节点名。
- **pending 归零不崩**：两次 timeout 之后端点继续正常服务（后续断言/压力/信号/属性读写全部 code=0）。
- 多帧采样与压力测试：`get_node_property_samples` code=0；`run_stress_test(count=3)` → `completed:true, crashed:false`。
- 信号监视：`capture_signal_emissions(duration_ms=1200)` 在真实窗口内观测到 `count:174` 次 `pulse` 发射。

### 5.2 门（全部自己跑，未抑制输出）

| 门 | 命令 | 结果 |
|---|---|---|
| 门③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **175 cases / 175 passed / 0 failed；7122 assertions / 7122 passed / 0 failed**，exit 0 |
| 门④ 全引擎 | `--headless --test` | **1601 cases / 1601 passed / 0 failed / 3 skipped；431404 assertions / 431404 passed / 0 failed**，exit 0（31s） |
| 门⑤ `accept_m1.ps1` | 运行 **3 次** | **22/22 × 3**，三次 exit 0；第 2、3 次 PASS 清单 `Compare-Object` **diff = 0**（23 行逐行相同） |
| `check_tool_groups.py --batch B3` | exit **0** | `TOOL-GROUPS-B3 CHECK PASS` |
| `check_tool_groups.py --batch B4` | exit **0** | `implemented=true groups = 3, carrying 7 tool(s)`；`TOOL-GROUPS-B4 CHECK PASS` |
| `check_tool_groups.py --check-completeness` | exit **0** | `B3+B4+B5 = 40+7+58 = 105`、两两不相交、与 B1/B2 不相交、双向差集 missing=0 foreign=0 |
| `check_tool_groups.py`（无参 = B1 路径） | exit **0** | `TOOL-GROUPS CHECK PASS`、`41 == 42 - 1` |

> 注：`check_tool_groups.py --batch B1` 会以「unknown batch: B1」退出 1，这是脚本**设计如此**
> （B1 走无参路径，源码 `len(sys.argv)==3 and BATCH_FILES` 分支里 B1 不在册）。非缺陷。
> 另：任务书写该脚本在 `docs/scripts/`，实况确为 `modules/mcp_server/docs/scripts/check_tool_groups.py`，
> 任务书路径是相对 docs 的简写，功能正常。

### 5.3 门脚本是否真的不再需要手工改（任务书第 12 项）

**证实：`$ToolNames` 确实由 manifest 派生，不是硬编码并集。**

- 源码结构：脚本用 `$ManifestFileNames = @('tool-groups.json','-b2','-b3','-b4','-b5')` 循环读取，
  仅累积 `implemented -eq $true` 组的 `tools`，并 `if ($ToolNames.Count -eq 0) { throw }` 兜底；
  随后 `Get-ToolScope` 读 `tool-rename-map.json` 派生 `$EditorOnlyToolNames`/`$GameOnlyToolNames`/
  `$EditorToolNames`/`$GameToolNames`。
- 运行输出（本次实测）：`derived tool union : 113 tool(s) from groups marked implemented in
  tool-groups.json, tool-groups-b2.json, tool-groups-b3.json, tool-groups-b4.json, tool-groups-b5.json`；
  且 SUMMARY 打印 `implemented tools = 91 (editor endpoint) / 53 (game endpoint); contract = 171`。
- **独立交叉验证**：我不采信脚本自报，用自己写的 `lib_m4.py` 直接从 5 个 manifest 推导 →
  `union=113 editorEndpoint=91 gameEndpoint=53 editorOnly=60 gameOnly=22`，**与脚本输出完全一致**，
  也与线上 `tools/list` 实况（91/53）一致。
- 硬编码残留检查：可执行行（排除注释）中「形如工具名」的字面量**仅 3 处**，都是**单个 case 的示例调用**
  （`"project_get_info"` ×2 于 case4/case5，`"editor_get_errors"` 于 case12 的 editor-scope 泄漏检查），
  不是工具名清单。**`$ToolNames` 无硬编码残留**。
- 证据：脚本 sha256 `8d89a02bab8ea0a5f2bd92db616d3bde3502cfc46375b7ad57fdfc5b49a006d2`。

**结论：后续批次不再需要手工追加 `$ToolNames`。**

---

## 6. 端口与收尾（E 段）

| 检查 | 结果 |
|---|---|
| 开工前 9877 归属 | owner pid **36392**（`Godot_v4.7.1-stable_mono_win64`，启动于 2026/09/21 19:34:39，路径在 `D:\Program Files\…`，与本次无关） |
| 9888 / 9889 开工前 | 均空闲（owner = -1） |
| 我们的测试实例 | 9888/9889 的 socket owner 是**我们自己启动的 launcher 的子孙进程**（`Test-DescendsFrom` 逐级查 `Win32_Process.ParentProcessId` 证实；`.console.exe` 会派生真正的引擎进程，故 PID 不相等是预期的） |
| 运行中 9877 | **三次采样**（binds 后、shutdown 前、shutdown 后）均仍为 pid 36392 |
| 收尾后 9877 | 仍为 pid **36392**，进程存活 |
| 收尾后 9888 / 9889 | 均 owner = -1（无监听） |
| 孤儿进程 | `Get-Descendants` 对两个 launcher 做整棵进程树遍历，收尾后 **surviving descendants: 空** |
| `editor_play_scene` 拉起的游戏子进程 | 本次未调用 `editor_play_scene`，故无此类子进程；已确认全程无 `godot.windows.editor*` 残留进程 |
| 全程 | **未占用、未杀、未重启 9877** |

---

## 7. `defects`

### D-1（severity: **high**）嵌套分量绕过静默错值闸门——布局不兼容的分量被静默写成 `0.0`

- **claim**：给 `Vector2`/`Vector3`/`Color` 等复合属性传**结构化对象**时，
  对象内的分量若不能落到目标类型（字符串、`null`、对象、数组），会被 `Variant::type_convert`
  **静默替换成该类型的默认值**（`0.0`），而调用返回 `code=0` 的成功与 `new_value`。
  这正是 D67 裁决要根除的「静默写错值并报成功」，只是发生在**一层之下的分量**。
- **evidence（我自己构造并读回）**：对 `Actor.position` 依次传
  | 值 | 错误码 | 读回 `position.x` |
  |---|---|---|
  | `{"x":"NaN","y":1}` | **0** | **0.0** |
  | `{"x":"abc","y":1}` | **0** | **0.0** |
  | `{"x":null,"y":1}` | **0** | **0.0** |
  | `{"x":{"z":9},"y":1}` | **0** | **0.0** |
  | `{"x":[1,2],"y":1}` | **0** | **0.0** |

  统一返回 `{"new_value":{"x":0.0,"y":1.0},"old_value":…,"property":"position"}`。
  证据文件：`%TEMP%\audit-m4\evidence\P2_pv_x_word.response.json` 等（含 sha256）；
  复现脚本 `phase2_editor.ps1` 的 C7g 段。
- **location**：`modules/mcp_server/tools/tool_helpers.cpp:599-607`（`property_value_from_json` 的
  `DICTIONARY` 分支：`out[keys[i]] = property_value_from_json(source[keys[i]], Variant::NIL)`，
  递归时把目标类型降级为 `NIL`，分量因此**不经过** `coerce_to_property_type` 的 `Variant::can_convert` 门；
  闸门只作用于最后 `dict → Vector2` 的**整体**类型，而 `DICTIONARY → VECTOR2` 在引擎的转换关系里是允许的）。
- **一致性**：同一缺口在**批量路径**同样存在（`editor_add_nodes_batch` / `editor_set_node_property_batch`
  复用同一 `property_value_from_json`），且 **9889 的 `running_game_set_node_property` 同样可复现**
  ——即 D67 声称「唯一一处、位于 `Object::set()` 之前」的那道门，对分量不设防。
- **recommendation**：在 `DICTIONARY`/`ARRAY` 分支递归前，把**目标元素类型**（Vector2 的 `x`/`y` 应为 `FLOAT`，
  Color 的 `r/g/b/a` 应为 `FLOAT` 等）传给递归，让每个分量也走 `coerce_to_property_type` 的 `can_convert` 判定；
  这需要一份「复合类型 → 分量类型」的最小映射（引擎 `PropertyInfo` 不提供 Vector 的分量表）。
  与 D67 的既有口径一致：不合规分量一律 `-32602`，批量路径在**任何写入之前**拒绝。

### D-2（severity: **high**）`STRING → FLOAT/INT` 转换放行垃圾字符串——`"abc"` 静默变 `0.0`

- **claim**：给标量数值属性传字符串，只要 `Variant::can_convert(STRING, FLOAT)` 为真就放行，
  随后 `type_convert` 把**无法解析的字符串**折成 `0.0`，调用仍报成功。这使 D67 声称的
  「`coerce_to_property_type` 增加 `Variant::can_convert` 门 → 布局不兼容值一律 `-32602`」
  在字符串键面上落空，也间接使 `coerce_to_property_type` 里针对 `p_value.get_type() == FLOAT`
  的 **NaN/Inf 守卫形同失效**（字符串 `"NaN"`/`"inf"` 走的是另一条支路）。
- **evidence**：`editor_set_node_property(path='Actor', property='rotation', value='abc')`
  → **code=0**，读回 `{"rotation":0.0}`。同法 `value='NaN'` 亦 code=0。
  证据：`%TEMP%\audit-m4\evidence\P2_pv_float_string.response.json`、`P2_pv_float_string_rb.response.json`。
- **location**：`modules/mcp_server/tools/tool_helpers.cpp:683`（`if (!Variant::can_convert(...))` 门）
  与 `:698`（`VariantUtilityFunctions::type_convert`）。`can_convert(STRING, FLOAT)` 为真，
  但 `type_convert("abc", FLOAT)` 返回 `0.0` 而非失败。
- **为何 D67 的自检没抓到**：其线上证明是「场景 `.tscn` 前后 sha256 相同」+「读回证明未被改动」。
  本例**值确实被改了**（写前值为 `0.5`），但读回的是**引擎本来就会写成的默认值**，
  「读回 != 请求值」这条启发式无法区分「拒绝」与「按引擎语义写默认值」。
- **recommendation**：在 `coerce_to_property_type` 里对 `STRING → FLOAT/INT` 增加**可解析性**判定
  （非空、可整体解析为数字、且解析结果有限），不可解析即 `-32602`；或更保守地对数值目标
  禁止字符串来源（契约里 `value` 无类型约束，但 `#rrggbb` 用于 Color 的既有特例需保留）。
  注意这是**对已验收工具的行为变更**，需在报告显式列影响面（与 D67 处理方式一致）。

### D-3（severity: **medium**）两个 assert 工具失败时不带 `reason`

- **claim**：`running_game_assert_node_state` / `running_game_assert_screen_text` 失败时返回
  `passed:false` 与 `actual`/`expected`（后者给 `visible_elements[]`），但**没有 `reason` 字段**。
  同批的 `running_game_run_test_scenario` 的**同样断言在场景内**却带完整 `reason`。调用方不得不用
  自己拼「expected vs actual」的说明。
- **evidence**：
  - `running_game_assert_node_state(node_path='.', property='name', expected='NotRoot')`
    → `{"actual":"Root","assertion":"node_state","expected":"NotRoot","node_path":"/root/Root","operator":"eq","passed":false,"property":"name"}`
    （无 `reason`）；对照场景内同断言 →
    `{"…","passed":false,"reason":"expected position eq \"{…}\"…"}`。
  - `running_game_assert_screen_text(text='NoSuchTextAnywhere')`
    → `{"visible_elements":[…],"expected_text":"NoSuchTextAnywhere","passed":false,"source":"control_tree"}`（无 `reason`）；
    场景内同断言带 `reason: "screen text containing '…' was not found in the 1 visible text(s) of the control tree"`。
- **location**：两个工具的**独立**（非场景）返回构造处：
  `modules/mcp_server/tools/running_game_assertion.cpp`（`_tool_assert_node_state` / `_tool_assert_screen_text`
  的 verdict 构造，约 166/255 行附近写累加器的那两处）；对照路径
  `running_game_test_execution.cpp:494`/`:519`/`:537` 已会写 `reason`。
- **关于任务书字面要求的判定**：任务书 §2.8 要求「失败的确实 `all_passed=false` **且带 `expected`/`actual`/`reason`**」
  是**场景**运行器的要求，实测该要求**已满足**（见 §4.1）。
  本 D-3 是**额外的**形状不一致：同一断言语义在两个入口给出不同字段集，
  建议统一（`high` 不成立，故记 `medium`）。
- **recommendation**：在两个独立 assert 工具的失败分支复用 `running_game_test_execution.cpp`
  已有的同一 `reason` 文案生成路径（或把 verdict 构造下沉为共享 helper），使两入口字段集一致。

### 未判为缺陷的观察（记录以免误读）

- `editor_list_signal_connections` 的 `count` 包含编辑器自身的内部连接（`ScriptEditor::_queue_update_list`
  指向 `Script`/`Shader Editor` 节点）。契约描述明文「收全部连接（不过滤非持久连接）」且它按
  `source/signal/target` 过滤，故**符合契约**；但调用方若要「场景内的连接」，需自行按 target 收敛。
- `editor_remove_output_log` 在 `--headless` 下**仍然**能测到面板（EditorLog 的 RichTextLabel 存在于 headless
  编辑器场景树中），返回 `log_is_empty:true` 与跨调用可观测的 `log_was_empty` 变化——这是**可验证的更诚实**形状，
  不是伪造成功。
- `check_tool_groups.py --batch B1` 退出 1 属**设计如此**（B1 走无参路径）。
- `DESIGN-DETAIL.md` §17.3 关于「编辑器端点期望集合」的措辞与其自身对称规则不相容（见 §1 的 `unconfirmed`）。

---

## 8. `unconfirmed`（我未能独立证实/证伪的点，如实列出）

1. **`project_set_node_property_across_scenes` 的多场景事务**：我阶段化了一个**故意坏的** `scenes/broken.tscn`
   （非法场景语句，`--import` 时报 `Unexpected end of file`），但本阶段的时间预算不足以再起一轮编辑器
   把「好文件 + 坏文件」的跨场景写完整跑透（含 `dry_run`、`force`、`path_filter` 与「Nothing was written」判据）。
   源码核对显示该路径是**全或无**（`project_cross_scene_write.cpp:365-384`：只要 `errors` 非空即整体失败、
   带 `data.scenes.errors` 与 `Nothing was written` 建议，绝不写已通过的文件），**但我没有自行跑出证据**，
   故不作为 PASS 计入。
2. **`editor_analyze_screenshot_diff`** 未构造真实 PNG 对（未验证 `identical`/`changed_pixels`/
   `diff_percentage` 的数值与 `threshold` 越界 `-32602`）。
3. **`editor_get_test_report` 的「累积」链**：我核对了源码（唯一写入点）并验证了空报告与
   「9889 的累加器不进入 9888」（`total=0`）；但**没有**在一次运行里让编辑器进程内的累加器从 0 变到非 0
   再读回（编辑器侧 `editor_execute_gdscript` 有能力触发，但未构造）。因此「真的累积」由
   源码 + 场景运行器/游戏侧累加器行为**支持**，而非编辑器侧端到端实测。
4. **`editor_add_resource_to_node_property`、`project_create_resource`、`project_edit_resource`** 三个
   D67 受影响工具未单独构造静默错值用例（仅实测了其中 4 个 + 批量 2 个 + 游戏侧 1 个）。
5. **`accept_m1.ps1` 的 PASS 清单一致性**：第 1 次运行的清单我只在终端留存，第 2、3 次落盘后
   `diff=0`；严格意义上「×2 一致」是由第 2/3 次证明的（第 1 次同为 22/22 但未逐行 diff）。

---

## 9. `risks`

1. **D-1/D-2 是 D67 同类缺陷的残留面**：D67 的验收证据（场景 sha 不变 + 读回比对）在结构上
   无法覆盖这两类（分量路径与「引擎本会写的默认值」路径）。若后续批次沿用同一自检方法，
   同类缺口仍会被判 PASS。**建议把「分量级拒绝」与「字符串可解析性」列为显式验收条款。**
2. **`build-m0.cmd` 陷阱**：仓库根未跟踪的 `build-m0.cmd` 不传 `tests=yes`，用它重建后
   `--version` 会正确、但 `--test` 直接 abort。任务书只要求「校验 `--version` == HEAD，不一致就重建」，
   **该规则不足以防住这个陷阱**（我本次就踩到）。已在报告中给出正确命令；建议把
   `build_local.cmd` 写进任务书的门配置，或让 `build-m0.cmd` 传递 `tests=yes`、删除陈旧 test 目标。
3. **`--import` 首次偶发崩溃**：本次有 1 次 `--import` 首次以 `-1073741819`（0xC0000005）退出、
   第 2 次成功（脚本有 3 次重试）。不影响结论，但是环境/引擎级偶发，可能污染只跑一次导入的自动化。
4. **文档与实况的措辞漂移**：§17.3 的端点期望公式与实况/门脚本不一致（见 §1 `unconfirmed`）。
   不修代码也应改文档，否则下一位验收者会按文档判 FAIL。
5. **`editor_list_signal_connections` 含编辑器内部连接**：契约如此，但极易误导
   「连接数为 0 就算通过」的检查（我第一版检查就因此假红）。已在报告中记录正确判据
   （按 `source`/`signal`/`target`/`method` 精确计数）。

---

## 10. `verdict`（按任务书要求的分类）

| 分类 | verdict | 依据 |
|---|---|---|
| **全量对等**（A） | **pass** | 113/113 `implemented=true` 线上可见；9888 = 91、9889 = 53 与按 `scope` 推导的期望集合**双向差集为空**；`description`+`inputSchema` 逐字相等（91+53 条零差异）；跨端点 `-32601` 且不执行；未知工具 `-32601` |
| **诚实性**（B） | **fail** | fix-first 已修 4 个**均证实真做到**，B5 的 3 个与 2 个 `unregister` **确未注册**；但 D67 的静默错值修复存在 2 个残留面（D-1 分量、D-2 字符串），**仍可「报成功并写错值」** |
| **行为一致**（C） | **fail** | 抽样 20+ 工具，绝大多数与契约/迁移源可观察条款一致；场景运行器通过/失败/前置拒绝**全部符合要求**；但 D-3：两个独立 assert 工具失败时不带 `reason`（同一断言在场景内带） |
| **安全与事务**（S） | **pass** | 批量**全成功或全回滚**、零半成品（场景树逐字节比对）；无匹配节点/属性不存在/值不兼容**均在写入前拒绝**；路径逃逸（读写、相对/绝对）全部 `-32602` 且磁盘无副作用；缺参/类型错 `-32602`；UID 方向搞反**响亮失败**、正向往返一致；`project_set_setting` 类型保真 |
| **延迟通道**（D） | **pass** | 超时 1,047ms→`-32000`；多 pending 不串线且各报自己的节点名；pending 后常规请求 32ms；多帧采样/压力/信号监视（174 次发射）均正常 |
| **工程门**（G） | **pass** | 模块 doctest **175/175·7122**；全引擎 **1601/1601·431404**；`accept_m1` **22/22 ×3、PASS 清单 diff=0**；`check_tool_groups` B3/B4/completeness（+B1 无参路径）**exit 0**；`$ToolNames` 经独立交叉验证确实由 manifest 派生（113/91/53 与我的推导完全一致），无硬编码残留 |
| **端口纪律**（P） | **pass** | 9877 全程 pid 36392（三次采样 + 收尾后）；仅用 9888/9889；收尾无监听、无孤儿子孙进程；未修改任何被跟踪文件、未执行 git 写操作 |

**总 verdict：`fail`**（因 B 段与 C 段的 3 个缺陷；A/S/D/G/P 六类全部 pass）。

**最严重的两项是 D-1 与 D-2**：它们属于本项目最核心的诉求——「不得静默写错值并报成功」，
且都是 D67 修复的**残留面**，必须回到阶段四（实现）再派新子代理修复，
并在修复后按同样的对抗性反例（分量级 + 字符串级）复核。

---

## 11. `next_step_recommendation`

1. **优先修 D-1 / D-2**（同属 `coerce_to_property_type` / `property_value_from_json` 一层）：
   - D-2 较小：在 `coerce_to_property_type` 对 `STRING → FLOAT/INT` 增加可解析性判定（保留 Color 的
     `#rrggbb` 特例）；
   - D-1 需要「复合类型 → 分量类型」映射并让递归携带目标类型，落在**任何写入之前**的预校验里，
     以保持批量路径的全成功或全回滚语义；
   - 两者都要补「线上 `-32602` + 读回证明未被改动」的**新**证据形态：
     证据必须能区分「拒绝」与「按引擎语义写默认值」——只比较读回值与请求值**不足以**判定（这正是
     D67 漏掉这两类的机制），应显式断言错误码 + 断言**该次写入没有发生**（例如前后场景 sha 相同、
     且旧值仍为旧值）。
2. **修 D-3**（`medium`）：让两个独立 assert 工具的失败分支与场景运行器共用同一 reason 生成路径。
3. **文档**：修正 `DESIGN-DETAIL.md` §17.3 的端点期望公式措辞，使其与 `scope` 对称规则、
   `accept_m1.ps1` 的推导公式和线上实况一致；并把 `modules/mcp_server/scripts/build_local.cmd`
   （含 `tests=yes` 与删除陈旧 test 对象的步骤）写进任务书的门配置。
4. **补完我未能验证的两项**（建议列入下一轮验收的任务书）：
   `project_set_node_property_across_scenes` 的坏文件全或无事务（我已准备好
   `%TEMP%\audit-m4\proj\scenes\broken.tscn`）、以及 `editor_analyze_screenshot_diff`。
5. **回归范围**：修完 D-1/D-2 必须重跑本报告的 C7g/C7h 反例、批量事务段、以及
   门③~⑤（注意用 `tests=yes` 的 `build_local.cmd` 重建，删除陈旧 test 目标）。

---

## 附录 A：证据与复现

- harness 与证据根目录：`%TEMP%\audit-m4\`
  - `audit_common.ps1`（curl/ConvertTo-Json/sha256/进程树纪律）、`lib_m4.py`（契约与 manifest 解析）、
    `analyze_equality.py`（**按解析后的 `name` 字段**做集合与逐字段相等）、
    `stage_project.py` / `stage_scenes.py`（scratch 工程，BOM-free 写入）、
    `phase1_check.ps1`（对等/scope/端口）、`phase2_editor.ps1`（静默错值/事务/honesty/对抗）、
    `phase3_game.ps1`（场景运行器/延迟通道/信号/压力）
  - `evidence\*.request.json` + `*.response.json`（每个请求体与响应体原样落盘）与 transcript 中的 sha256
  - `results-phase1.json`（20 条，0 failed）、`results-phase2.json`（55 条，2 failed）、
    `results-phase3.json`（27 条，2 failed）
  - `eq\equality.txt` / `eq\equality.json`（对等分析全文）
  - `ctg-B{1..5}.txt` / `ctg-complete.txt` / `ctg-B1-noargs.txt`（门脚本输出）、`accept-run{2,3}.txt`
- 构建日志：`%TEMP%\mcp_server_build_local.log`（`tests=yes`，`EXIT_CODE=0`）；
  早前的 `build-m0.log`（无 tests）
- 临时改动还原：**未修改任何仓库文件**（含测试文件），故无「还原并留证」事项；
  唯一写入均在 `%TEMP%` 与本次交付的报告文件。