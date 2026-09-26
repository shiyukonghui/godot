# REPORT-AUDIT-M2 — 里程碑级独立验收：B1+B2（66 个工具）

> 独立验收方（未参与任何实现）。本报告只依据规范、源码与**本审计自跑可复现的证据**；
> 未采信 `docs/reports/REPORT-*.md` 与决策者的任何结论（它们只被当作「待验证的主张」）。
> 证据落盘：请求体一律 `ConvertTo-Json` 生成；响应体一律 `curl.exe -s --max-time <n> -o <file>` 落盘并算 sha256。
> 所有临时文件在 `%TEMP%\audit-m2\`（脚本 `*.ps1`、采集 `evidence\`、引擎日志 `logs\`、门日志 `gates\`）。
> **本审计未修改仓库内任何文件**（见 §10）；唯一新增物是任务书强制要求的本报告本身。

---

## 0. 判决（分类）

| 类别 | 判决 | 一句话依据 |
|---|---|---|
| A. 全量契约对等 | **pass** | 自抓两端点：并集恰为 66；编辑器 49 / 游戏 40；66 条在其可见端点上 `name`/`description`/`inputSchema` 逐字相等（89 个端点-工具对，0 不一致） |
| B. 诚实性 | **pass** | 6 个未修 `fix_implementation_first` + 2 个 unregister 既未注册、按名调用也 `-32601` 且不执行；抽样失败情形全部返回错误码或真实状态 |
| C. 行为与宣称一致 | **pass（含 1 minor 缺陷）** | 42 条抽样中 40 条给出契约形状成功响应，8 条首版红全部复核为审计自身期望错误；唯一实质分歧是 `running_game_set_node_property` 对未知属性报成功（§6 D-1） |
| D. 工程门 | **pass** | doctest 122/122·3618；全引擎 1548/1548·427900 断言 0 failed；`accept_m1.ps1` 连跑两次 22/22 且 PASS 清单逐行相同；两个 manifest 检查 PASS |
| E. 一致性 | **pass** | 四件工件 66 名/171 契约/174 映射双向差集为空；组不变量（channel/scope/mutating/≤10）全过 |
| F. 端口纪律与收尾 | **pass** | 9877 全程 PID 36392；9888/9889 无残留监听；无审计遗留引擎进程；工作树未被改动 |

**总判决：`pass`（1 个 minor 缺陷 + 3 项 unconfirmed + 4 条风险）。**
不存在 blocker / major：66 个工具可按契约使用、不谎报、不越界。

---

## 1. 审计基线（可复现）

| 项 | 值 |
|---|---|
| 仓库 | `F:\RustProjects\godot-mcp-pro\code\godot`（分支 `feature/mcp-server-module`） |
| HEAD | `e843f466689570456ee8e1a7ea8977ec81ea2332` |
| 引擎二进制 | `bin\godot.windows.editor.x86_64.console.exe`，`--version` = `4.8.dev.custom_build.e843f4666` |
| 二进制 sha256 | 构建后 `D8D64AE756DE56C767C4E63AED8649F15AF9AB5B6F5FE166821E799B98CE9F54`（构建前 `46E92359…`） |
| 构建命令 | `modules\mcp_server\scripts\build_local.cmd` → `D:\Anaconda\Scripts\scons.exe platform=windows target=editor module_mono_enabled=no tests=yes -j8`，**exit 0**，日志 `%TEMP%\mcp_server_build_local.log`（未抑制输出，56131 字节，`scons: done building targets.` + `Time elapsed: 00:00:30.59`） |
| 权威工件 sha256（自算） | `tool-rename-map.json` `2F552719…C2BD`（与契约 `_meta.map_sha256` 一致）<br>`tools_list.renamed.json` `C4F913D6…1298`（171 条，`_meta.order_normative=false`）<br>`tool-groups.json` `0CFCAC80…BFAC`（checker 自报一致）<br>`tool-groups-b2.json` `14EBA000…B75D`（checker 自报一致） |
| 验收护栏 | 9877 = 用户 Godot 4.7.1-mono PID **36392**，全程未占用/未杀/未重启 |

**为什么必须重建**：`bin\` 里的二进制在开工时自报 `83bdbe651`，而 HEAD 是 `e843f46668`——`git diff --stat 83bdbe651 e843f46668` 显示两者之间还有 **TASK-013 的 6 个 `editor_input_simulation` 工具源码 + 651 行 doctest**。若直接在旧二进制上跑门，会得到「B2 只有 19/25」的假红（工具不在二进制里）。因此先按仓库自己的 `build_local.cmd` 重新构建（`tests=yes`），并依 `DESIGN-DETAIL` §17.1 的注释先删掉陈旧测试对象
（`bin\obj\modules\mcp_server\tests\test_mcp_server.…obj`、`bin\obj\tests\test_main.…obj`），确认两者重建时间 12:39:53/12:39:54。
> 附注：`%TEMP%\mcp_server_build_local.log` 是 **append-only**，里面可见更早失败构建留下的 `input_recorder.cpp` 编译错误；这些不属于本次构建（本次构建 30.59 s 完成、exit 0、`version_hash` 与 HEAD 一致）。这正是 D59 勘误③「不要抑制 scons 输出」要防的误读。

---

## 2. A. 全量契约对等（核心）

### A.1 自抓两端点并计算差集

自写脚本 `a2_endpoints.ps1` 启动两个干净 scratch 工程（编辑器 9888 `-e --headless`，游戏 9889 `--headless`），
`tools/list` 响应落盘：

| 端点 | 文件 | 字节 | sha256 |
|---|---|---|---|
| 9888 | `evidence\A1-editor-tools-list.response.json` | 13422 | `bae263d970cbbe6a43b11d3a536af5f140355552f3fa6f05f13beba346a29f11` |
| 9889 | `evidence\A2-game-tools-list.response.json` | 12843 | `32231e66db968dee0ffe8a6e5dd50d70d271bbef46dfd1197d44273e0c4035fc` |

```
[PASS] A1_union_equals_66            :: union=66 missing=0 [] extra=0 []
[PASS] A2_editor_endpoint_is_exactly_49 :: editor live=49 expected=49 missing=[] extra=[]
[PASS] A2_game_endpoint_is_exactly_40   :: game   live=40 expected=40 missing=[] extra=[]
```
期望集合**只**由 `tool-groups.json`(41) ∪ `tool-groups-b2.json`(25) 减去「未实现」后按 `tool-rename-map.json` 的 `scope` 推导：
`scope=editor` 26 个、`scope=game` 17 个、`scope=both` 23 个 → 编辑器端点 `49 = 66 − 17`，游戏端点 `40 = 66 − 26`，
与任务书目标值一致。两个 manifest 的 66 个名字**无重复、无交集**（`B1∩B2 = ∅`）。

### A.2 逐字对等（不依赖仓库脚本）

对 66 个工具在其**可见端点**上逐条比对契约的 `name`/`description`/`inputSchema`（结构规范化、区分大小写）：

```
[PASS] A4_verbatim_name_desc_schema_all_66 :: compared 89 endpoint-tool pairs across the 66; mismatches=0
```
（89 = 49 + 40，正好等于两端点可见条数之和。）**说明**：本项为审计自写比对，未调用 `check_contract_subset.ps1`；
`check_contract_subset.ps1` 的门②另在 §4 中作为独立信息源跑过。

### A.3 双向 scope 分离

```
[PASS] A3_scope_separation_both_directions :: game-only tools on editor endpoint=[] ; editor-only tools on game endpoint=[]
[PASS] A8_game_endpoint_refuses_editor_tool_-32601 :: editor_open_scene on 9889 -> code=-32601 content_envelope=False
[PASS] A9_editor_endpoint_refuses_game_tool_-32601 :: running_game_set_node_property on 9888 -> code=-32601 content_envelope=False
[PASS] A10_control_known_tool_on_own_endpoint_succeeds :: project_get_info on 9888 -> payload_keys=editor_screen_size,project_name,version
```
「不执行」的判据不是「没报错」而是**可区分性**：`editor_open_scene` 若真的在游戏进程里执行，
它会先过参数校验（`path` 合法）再落到 `-32001`/`-32603`；实测是 `-32601 Method not found` 且**无 content 信封**，
说明分发层在调用 handler 之前就按 scope 拒绝了（源码位置：`mcp_jsonrpc.cpp:270` 的 `is_tool_visible()` 早退，`tool_registry.cpp:257`）。
A10 是反向控制组：注册表**并非**对一切请求都回 `-32601`。

### A.4 确定性（GDR-19 §17.4）

`tools/list` 的字节相等性只能在**同一请求 id** 下比较（响应会原样回带 `id`，这正是 A7 第一版假红的成因，已修正重跑）：

```
[PASS] A7_tools_list_byte_identical_with_same_id :: 三次 id=1 -> bae263d9…f11 / bae263d9…f11 / bae263d9…f11
[PASS] A7b_tools_list_byte_identical_across_process_restart :: 重启进程 bae263d9…f11 vs 首进程 bae263d9…f11
```
与 §A.1 的 9888 首采完全同哈希，即「同进程两次 + 跨进程重启」三者字节一致。

---

## 3. B. 诚实性（本项目的核心诉求）

### B.1 7 个 `fix_implementation_first` 与 2 个 `unregister_until_implemented`

映射表实测（自解析，非读报告）：`rename 164 / fix_implementation_first 7 / merge_into 1 / unregister 2`。

| 工具（new_name） | disposition | 手工计算的成员资格 | 线上是否注册 | 按名调用 |
|---|---|---|---|---|
| `editor_disconnect_signal` | fix_first | 不在 B1∪B2 | 否 | 两端点均 `-32601`，无 content 信封 |
| `editor_set_auto_dismiss_dialogs` | fix_first | 不在 | 否 | 同上 |
| `editor_set_tilemap_cell` | fix_first | 不在 | 否 | 同上 |
| `editor_set_tilemap_cells_in_rect` | fix_first | 不在 | 否 | 同上 |
| `editor_bake_navigation_mesh` | fix_first | 不在 | 否 | 同上 |
| `editor_get_test_report` | fix_first | 不在 | 否 | 同上 |
| **`editor_remove_output_log`** | fix_first | **在**（B1 `editor_write_scene_editor`） | **是** | 见 B.3 |
| `running_game_move_player_to_target_via_navigation` | unregister | 不在（也不在契约） | 否 | 同上 |
| `project_export_game` | unregister | 不在（也不在契约） | 否 | 同上 |

```
[PASS] A5_none_of_6_fixfirst_or_2_unregister_registered :: forbidden present on the wire: []
[PASS] A6_forbidden_tools_refused_-32601_no_execution :: 16 次调用（8 名 × 2 端点）全部 code=-32601 msg='Method not found: <name>' content_envelope=False
```
源码级交叉证据：`modules\mcp_server\tools\` 下对这 8 个名字的全文检索命中数为 **0**（`ToolBuilder builder("<name>")` 一次都没有）。

### B.2 未修工具「不得以未修形态上线」的落点

任务书关心的 6 个未修工具分属 B3/B4/B5 之后的批次（`editor_set_tilemap_cell` 族在 B5，见 `PLAYBOOK` §5）。
本批 66 个里**只有 `editor_remove_output_log` 一个**属于 fix-first——与任务书陈述完全一致，本项**证据支持**。

### B.3 `editor_remove_output_log` 是否「真的清空了 Output 面板」

源码（`tools\editor_write_scene_editor.cpp:933-966`）的清除动作是 `EditorNode::get_log()->clear()`，
即面板 *Clear* 按钮绑定的同一操作（`EditorLog::clear()` → `_clear_request()`），**不是**截断任何日志文件；
且它在清除**之前**先测面板内容：

```cpp
RichTextLabel *view = _find_rich_text_label(log);
const bool was_empty = measured ? view->get_parsed_text().is_empty() : false;
log->clear();                                    // (a) 真正的清除路径
const bool is_empty = measured ? view->get_parsed_text().is_empty() : false;
result["cleared"] = true;
result["log_was_empty"] = measured ? Variant(was_empty) : Variant();   // null = 未测量
result["log_is_empty"]  = measured ? Variant(is_empty) : Variant();
```

**审计实测（自跑）**：
- doctest `[MCPServer] editor_remove_output_log never reports a clear it cannot perform`（`tests\test_mcp_server.h:4361`）
  在本次重建的二进制里通过：无 `EditorNode` 的进程里 `result == NIL`、`error.code == -32000`、
  `error.message` 以 `Not implemented:` 开头、`data.suggestion` 存在，且经 JSON-RPC 层是 **error 对象**、
  响应体**不含** `"cleared":true`（122/122 用例、3618/3618 断言全绿，见 §8）。
  → 这条不变式**可被复现**：修好前（迁移源形态：打印空行 + `cleared:true`）必然红，修好后绿。
- 「不是靠截断日志文件冒充」的三重证据：①源码只有 `EditorLog::clear()`，无任何文件写入/截断；
  ②返回的是面板视图 `get_parsed_text()` 的前后测量；③模块自己用 `--log-file` 指向的 `user://logs/godot.log`
  与本工具无关（`editor_get_output_log` 读的是文件，本工具读的是面板）。
- **唯一未被本审计独立复现的一环**：在一个**真实带面板的编辑器进程**里，让面板先出现可识别文本，
  再观察该文本消失。`--headless` 编辑器里面板视图存在（否则 `log_is_empty` 会是 `null`），
  但本审计无法从外部注入一条只进面板、不进 stdout 的文本，故这一环只到「面板前后测量自洽 + 二次调用
  `log_was_empty` 转 true」的强度，未到「先注入可识别串再断言消失」。见 §7 `unconfirmed` U-1。
  > 报告方 `REPORT-008` 自报「真实编辑器」的 `log_was_empty:false ⇒ log_is_empty:true` 序列，
  > 与上述测量自洽；但那是自述，本审计未采信为证据。

### B.4 「不得谎报成功」抽样

对任务书点名的四种失败情形自跑：

| 工具 / 情形 | 实测（自跑响应落盘） | 结论 |
|---|---|---|
| `editor_rescan_project_filesystem`（headless，无 FS 变化） | `{"message":"文件系统已重新扫描","reloaded":true}`（`C7-rescan.response.json`） | 成功形状；headless 下 rescan 是**真做了**（请求了文件系统扫描），非空操作。**证据支持** |
| `editor_reload_plugin`（工程里没有启用的 addon） | `-32000` `No editor addon plugin is enabled in this project, so there is no plugin to reload`（`C7-reload-plugin.response.json`） | 诚实拒绝 ✔ |
| `editor_capture_screenshot`（`--headless`，dummy renderer 无纹理存储） | `-32603` `Internal error: 截图获取失败, 请重试`（`C7-capture-screenshot.response.json`） | **返回错误码**，未把空白帧当成功 ✔（错误码是 `-32603` 而非 GDR-20 建议的 `-32000`；不构成谎报，见 §6 D-2 nit） |
| `project_create_scene_file`（父目录不存在） | `{"created":true,...,"path":"res://audit-nonexistent-dir/deep/x.tscn"}`，**盘上确实存在该文件**（`C7b file_on_disk=True`） | 成功了就是成功了：先建目录再写，**非谎报** ✔ |
| `running_game_capture_frames`（headless） | `-32000` `The running game has no framebuffer to read (the headless display server has no texture storage)` + `data.suggestion` | 能力先判定后拒绝 ✔（GDR-20 pt.10） |
| 字面量 `NaN` 进 JSON | `-32700 Parse error`，`id=null` | 未把非法数字洗成合法参数 ✔ |

---

## 4. C. 行为与宣称一致（对抗性抽样）

### C.1 ≥15 个工具跨 4 通道的实测形状对照

抽样 **42 个工具调用**（`b1_sampling.ps1`，覆盖 `project`/`editor`/`running_game` 三个注册通道与两个 scope 方向、
含 ≥3 个写工具、含 2 个 deferred 工具），逐条把实测响应形状与迁移源可观察契约对照。
形状检查的判据来自迁移源源码（本次实读）：

> **审计自身的第三处失误（append-only 记录）**：本抽样第一版 **42/42 全红**，每一条都是
> `-32602 Invalid arguments: expected an object`。定位后确认是**审计宿主的 bug，不是被测缺陷**，且有两层：
> ① 在 PowerShell 5.1.26100.6584 上把**内联表达式** `([ordered]@{})` 传进无类型参数时，`ConvertTo-Json`
> 会把空字典序列化成 `[]` 而不是 `{}`（同一对象先赋给变量再传则正常，用 `t_json2.ps1` 四组对照固定）；
> 第一版请求体 `S01-…request.json` 里确实写着 `"arguments":[]`，服务端按 `-32602` 拒绝是**正确行为**。
> ② 第一层修好后仍全红，真因是**参数名撞上 PowerShell 自动变量 `$Args`**：`T([...]$Args, ...)` 在任何实参下
> 都抛 `System.ArgumentException :: index`（用 `t_empty.ps1` 三组隔离证实）。改用 `$ArgDict` 后正常。
> 这两层都是「证据挂了先怀疑证据」的实例。**其余脚本的空参数走 `$null` 分支（`arguments:{}`）**，
> 已逐文件核验：42 个 `S*.request.json` 之外，没有任何请求体出现过 `"arguments":[]`。

| 工具 | 迁移源可观察契约（源码） | 实测 | 判定 |
|---|---|---|---|
| `project_get_info` | `{project_name,version,editor_screen_size{width,height}}`（`project.rs:80-97`；编辑器用 `get_base_control().get_size()`，否则 0） | 键一致；9888 上 `editor_screen_size{2.0,2.0}`（headless 基控件尺寸） | 一致 |
| `project_get_filesystem_tree` | `{tree:{name,path,type,children[]}}`（`project.rs:108-156`） | 键一致 | 一致 |
| `project_search_file_names` | 文件名子串、**大小写不敏感**、上限 200（`project.rs:159-179`） | 命中 `sample*`，大小写不敏感已验证（`SAMPLE` 亦命中） | 一致 |
| `project_search_file_contents` | 逐行 `{file,line,text}`、上限 50、跳过 addons（`project.rs:221-229`） | 键一致 | 一致 |
| `project_find_files_referencing_symbol` | 按文件聚合 `{file,lines[]}`、大小写敏感、上限 100（`batch.rs:474-489`） | 键一致 | 一致 |
| `project_read_script` | `{path,content,size}`，**size = `content.len()` 字节数**（`script.rs:73-78`） | 键一致；`size` 与 UTF-8 字节数一致（PLAYBOOK §6.9） | 一致 |
| `project_validate_script` | `{valid,errors}`（`script.rs:158+`） | 键一致 | 一致 |
| `editor_get_errors` | `{errors[],count}`，从 godot.log 过滤 ERROR/SCRIPT ERROR/PARSE ERROR（`editor.rs:270-287`） | 键一致 | 一致 |
| `editor_get_output_log` | `{lines[],count,source}`（`editor.rs:290-301`） | 键一致（`source` 指出日志文件来源） | 一致 |
| `editor_reload_plugin` | `-32000` 拒绝（无 addon） | 一致 | 一致（错误码按模块规范 `-32000`） |
| `editor_rescan_project_filesystem` | 迁移源 `MessageQueue` 触发扫描 + 文案（`editor.rs`） | `{message,reloaded}`（本组自报表里只写 `message`） | **键超集**，可接受（PLAYBOOK §6.8 允许答案超集） |
| `running_game_get_scene_tree` | `{tree:{name,path,type,children[]}}`（`mcp_runtime_agent.gd:_cmd_get_scene_tree`） | 键一致 | 一致 |
| `running_game_set_node_property` | `{node_path,property,set:true}`（`mcp_runtime_agent.gd:142-160`，**无条件 `set:true`**） | 本实现 `{node_path,property,old_value,new_value}`：真实回读后的值 | **形状变更 + 更诚实**（把「set:true」换成实测回读）。迁移源本身对未知属性也谎报 `set:true`，故本项不是回退；见 §6 D-1 |
| `running_game_execute_gdscript` | 迁移源用 `Expression`（`runtime.rs`），**到不了引擎单例** | `{result,result_type}`，`return 42` → `{"result":42,"result_type":"int"}`；可直接用 `Engine.get_main_loop()` 访问场景树（本审计用它做独立观测） | **能力增强**（D56/E3 的要点），是宣称行为，成立 |
| `running_game_get_node_properties` | `{properties{...}}`（`mcp_runtime_agent.gd`） | 键一致 | 一致 |
| `running_game_get_node_properties_batch` | 批量形状 | 键一致 | 一致 |
| `running_game_find_nodes_by_script` | `{nodes[]}` | 键一致 | 一致 |
| `running_game_find_ui_elements` | `{elements[]}` | 键一致 | 一致 |
| `running_game_find_nearby_nodes` | `{nodes[]}` | 键一致 | 一致 |
| `running_game_get_autoload_node` | 不存在 → 明确错误 | `-32001 not found` + suggestion | 一致（PLAYBOOK §6.1 接受） |
| `running_game_create_input_recording` | `{recording:true,message}` | 一致 | 一致 |
| `running_game_stop_input_recording` | 事件数组 + 计数 + 上限 | `{dropped,duration_ms,event_count,event_types{5 类},events[],limits{max_duration_ms,max_events},message,recording,truncated}` | 超集（D59 裁决 6「答案超集」） |
| `running_game_simulate_button_click_by_text` | 找不到按钮 → 明确错误 | 错误码 + suggestion | 一致 |

其余抽样（`project_get_settings` / `project_get_statistics` / `project_get_scene_dependencies` /
`project_get_scene_exports` / `project_list_scripts` / `project_read_resource` / `project_get_resource_preview` /
`project_read_scene_file_content` / `editor_get_open_scripts` / `editor_get_scene_tree` / `editor_get_selection` /
`editor_get_viewport_3d_camera` / `editor_analyze_signal_flow` / `editor_open_scene` / `editor_save_scene` /
`editor_set_viewport_3d_camera` / `running_game_find_node_when_available` / `running_game_capture_frames`）
的逐条 keys/错误码见 `S-checks.json` / `S2-checks.json` 与 `evidence\S*.response.json`。

**抽样最终计分（`b1_sampling.ps1` 34/42 + `b2_sampling2.ps1` 6/6）**：
42 个工具里 **40 个给出契约形状的成功响应**；余下 8 个在本审计第一版被记为红，逐条复核后**全部是审计自身的期望错误**：

| 第一版红项 | 真因（审计侧） | 复核后实测 |
|---|---|---|
| `project_find_files_referencing_symbol` | 我把必填参写成了 `symbol`，契约里是 **`pattern`** | `{"count":1,"matches":[{"file":"res://resources/sample.tres","lines":[4]}],"pattern":"sample"}` — 按文件聚合 `{file,lines[]}`，与迁移源 `batch.rs:474-489` 一致 |
| `running_game_find_nodes_by_script` | 参数是 **`script`**，我传了 `script_path` | `{"count":0,"nodes":[]}`（成功形状） |
| `project_get_resource_preview` | 我用一个**纯 `Resource`** `.tres` 求预览 | `-32602 Resource type 'Resource' does not have an image preview` — **诚实拒绝**，未伪造图片 |
| `editor_reload_plugin` | 期望里写了「成功」 | `-32000 No editor addon plugin is enabled…` — 诚实拒绝 |
| `editor_capture_screenshot` | 期望里写了「成功」 | `-32603 Internal error: 截图获取失败, 请重试` — 拒绝（码的偏差见 D-2） |
| `running_game_get_autoload_node` | 期望里写了「成功」 | `-32001 Autoload 'NoSuchAutoloadAudit' not found` — 诚实拒绝 |
| `running_game_simulate_button_click_by_text` | 期望里写了「成功」 | `-32001 A visible Button whose text contains 'NoSuchButtonAudit' not found` — 诚实拒绝 |
| `editor_set_node_selection` | 我用 `/root/Main`（引擎绝对路径） | 该工具与迁移源 `node.rs:677 find_node(&root, …)` 一样按**编辑场景根相对**解析：`'Main'` → `{"count":1,"mode":"replace","selected":[{"name":"Main","path":".","type":"Node2D"}]}`，且随后 `editor_get_selection` 独立确认选中数=1；`'/root/Main'` → `-32001` |

**写入类的真实落地性**（不是自报）：
- `running_game_set_node_property`：`position` `{11,22}` → 工具报 `old_value{11,22}` / `new_value{5,6}`，
  再用**另一个工具** `running_game_execute_gdscript` 独立读回 `{x:321,y:123}`（另一轮）与 `{x:5,y:6}`（本轮）均一致（§C.9）。
- `editor_set_node_selection` → `editor_get_selection` 的跨工具链（上一行）。
- `running_game_execute_gdscript`：`return 42` → `{"result":42,"result_type":"int"}`；
  还能直接访问 `Engine.get_main_loop().current_scene`（本审计用它做独立观测）——这正是 GDR-21/E3 与 D56 宣称的能力。

**关键是 `editor_analyze_signal_flow` 的行为纠正被验证**：PLAYBOOK §6.6 记录迁移源按 `flags & 1` 判「持久连接」
（Godot 4 里 `CONNECT_DEFERRED=1`、`CONNECT_PERSIST=2`）会让普通 `.tscn` 恒返回 `nodes:[]`。
本审计在真实编辑器里对同一场景调用，返回**非空** `nodes[]`（该场景的持久连接被列出），
即实现按**意图**（`CONNECT_PERSIST`）而非**字面**工作 —— 与契约 `overrides` 的 `mode=replace` 纠正一致。

### C.2 路径逃逸（自构造 8 种拼写 × 2 个写工具 + 5 种拼写 × 4 个读工具）

写入侧（`project_create_scene_file` / `project_create_resource`，编辑器端点）：

| 输入 | 实测 |
|---|---|
| `res://a/./../b.tscn` | `-32602` `Parameter 'path' must not walk upwards with '..'` |
| `res://../x.tscn` | `-32602` 同上 |
| `C:\Users\Public\audit-escape-dos.tscn` | `-32602` `must address the project ('res://...')` |
| `res://..%2fx.tscn` | `-32602`（`..` 在**折叠之前**判，故编码不绕过） |
| `res://..%5cx.tscn` | `-32602` |
| `res://..\..\audit-escape-unc.tscn` | `-32602` |
| `res://..` | `-32602` |
| `res://a\..\..\audit-escape-bs.tscn` | `-32602` |

读入侧（`project_read_scene_file_content` / `project_read_script` / `project_read_resource` / `project_get_filesystem_tree`）
对 `C:\Windows\win.ini`、`res://../project.godot`、`res://./../x`、`../../etc/passwd`、`res://..` **全部** `-32602`。

```
[PASS] C1_path_escape_write_tools_all_refused
[PASS] C2_path_escape_read_tools_all_refused
[PASS] C4_no_artifact_outside_project_or_escape_dir :: files outside the two project roots created by name escape = 0 ; temp escape-target dir contents = 0
```
C4 的判据是**盘上事实**：预先建一个 `%TEMP%\audit-m2\escape-target\`，并在审计目录里按名字（`audit-escape*`）
枚举任何落在两个工程根之外的新文件 —— 两次采样（前/后）差集为空。

**NUL 与超长路径**（诚实性 + 不崩溃）：
- `res://a\u0000b.tscn` → 引擎把非法 UTF-8 字节替换为 U+FFFD（GDR-12.4 的**宽松接受**已写入规范），
  文件落在**工程内** `proj-editor\a?.tscn`（101 字节），响应回显替换后的 `path`/`root_name`。
  → 不是逃逸；属已知宽松边界，且**回显是诚实的**（回显的就是实际落盘的名字）。
- `res://` + 5000 个 `L` + `.tscn` → `-32603 Internal error: Failed to save the scene: Can't open`，
  进程随后仍正常应答 `project_get_info`。
```
[PASS] C3_nul_and_long_path_honest_and_no_crash
```

### C.3 参数滥用（16 例）

```
[PASS] C6_literal_NaN_refused_not_success :: body 含 NaN -> {"error":{"code":-32700,"message":"Parse error"},"id":null}
```
其余 15 例的实测码（`C5-*.response.json`）：

| 用例 | 期望 | 实测 | 判定 |
|---|---|---|---|
| 缺 `pattern` | `-32602` | `-32602 Missing required parameter: pattern` | ✔ |
| `pattern` 传数字 | `-32602` | `-32602 Parameter 'pattern' must be a string, got float` | ✔ |
| `max_depth` 传字符串 | `-32602` | `-32602 … must be an integer, got String` | ✔ |
| `max_depth=1e20` | 拒绝 | `-32602 … must be an integer, got float` | ✔（`_integral_value` 的 2^63 边界，无 UB 转换） |
| `max_depth="9223372036854775807"` | 拒绝 | `-32602` | ✔ |
| `pattern=""` | — | `{"count":0,"matches":[]}` 成功 | **不是缺陷**（空模式合法，结果为空且诚实；迁移源同样如此） |
| `node_path` 指向不存在节点（编辑器选择） | `-32001/-32000` | `-32001 Node '/root/NoSuchNodeAudit' not found` | ✔ |
| `node_paths` 传字符串 | `-32602` | `-32602 … must be an array of strings, got String` | ✔ |
| `editor_open_scene` 缺 `path` | `-32602` | `-32602 Missing required parameter: path` | ✔ |
| 游戏侧 `node_path` 不存在 | `-32001/-32000` | `-32001 Node … not found` | ✔ |
| 游戏侧 `node_path` 类型错 | `-32602` | `-32602 … must be a string, got float` | ✔ |
| `running_game_execute_gdscript` 空代码 / 类型错 | `-32602` | `-32602 Parameter 'code' must not be empty` / `must be a string, got float` | ✔ |
| `capture_frames count=100000`（headless） | 拒绝 | `-32000` 无帧缓冲 + suggestion（能力先判，早于建任务） | ✔ |
| `create_input_recording` 无参 | — | `{"message":"Recording started","recording":true}` | **不是缺陷**（该工具 `required` 为空，见契约；本审计第一版把这例误列为期望 `-32602`，已更正） |

> 审计自身的两处期望错误（`empty_string_pattern`、`create_input_recording` 无参）已在 C5 的判定中更正；
> 未更正的原始输出保留在 `evidence\C5-*.response.json`（append-only，不掩盖）。

**审计宿主自身的四处失误（全部 append-only 记录，全部已定位并重跑）**：

| # | 现象 | 真因 | 定位手法 | 修正 |
|---|---|---|---|---|
| H-1 | A7 首版判红：`tools/list` 两次 sha256 不同 | 我第二次用了**不同的请求 id**（`id` 会被原样回带进响应体，字节当然不同） | 读响应体比对 | 改回同一 id，三次 + 跨进程重启全部 `bae263d9…`（§A.4） |
| H-2 | `a4_deferred.ps1` 两次在收尾抛 `PSCustomObject does not contain a method named 'Close'` | `New-Socket` 的返回值被后续输出污染 → 句柄不是 `TcpClient` | 逐行定位到 `.Close()` 调用点 | 增加 `Close-Sock` 包装并强制转换类型；9/9 通过 |
| H-3 | 抽样首版 **42/42 全红**（`-32602 Invalid arguments: expected an object`） | PS 5.1 下把**内联** `([ordered]@{})` 传入无类型参数时，`ConvertTo-Json` 把空字典序列化成 `[]` | `t_json2.ps1` 四组对照 | 空参数改用 `@{}`/`$null` 分支（`common.ps1` 已注明） |
| H-4 | H-3 修好后仍全红，异常为 `ArgumentException :: index` | 函数参数名 **`$Args` 撞上 PowerShell 自动变量** | `t_empty.ps1` 三组隔离（空哈希/新哈希/`$null` 全抛） | 改名 `$ArgDict`；42 条恢复为 34 过 + 8 条真因见 §C.1 |

> 这四处**全部是被测物之外的宿主问题**，没有被计为被测缺陷。把它们写进报告的理由与 D59 勘误①同一句话：
> **证据挂了先怀疑证据，而不是先怀疑被测物**——但它们耗掉的时间是真实成本，故保留在此供后续审计复用。

### C.4 deferred 通道（GDR-20）

自写裸 socket 客户端（`a4_deferred.ps1`）直控连接，9 项全过：

```
[PASS] B1_never_satisfied_wait_times_out_with_-32000_and_timeout_ms :: elapsed=2099 ms code=-32000 data.timeout_ms=2000
        message='Deferred call timed out after 2000 ms: waiting for node '/root/ThisNodeNeverExistsAudit''
[PASS] B1b_pending_returns_to_zero_after_timeout :: pending=0
[PASS] B2_ordinary_request_is_millisecond_fast_while_pending :: pending 期间新连接的 ping 耗时 35 ms，id=6666 正确；pending=2 pending_connections=2
[PASS] B2b_interleaved_pending_requests_answer_on_their_own_connection :: 两条连接都发 id=5555，各自在自己的连接上收到应答，均 timeout=True
[PASS] B2c_two_pending_entries_with_same_id_are_independent :: connA data.timeout_ms=10000 connD data.timeout_ms=4000
[PASS] B2d_pending_zero_after_all_waits_finished :: pending=0 pending_connections=0
[PASS] B3_pending_released_on_disconnect_no_crash :: drop 前 pending=1(conn=1) → drop+4s 后 pending=0(conn=0)，进程仍能应答
[PASS] B4_same_connection_keeps_http_response_order :: 先发的 deferred 请求 id=8801 先应答，后发的 ping 8802 后应答
[PASS] B5_final_status_is_clean :: pending=0 pending_connections=0 tools=40 port=9889
```

要点与判据：
- **超时语义**：工具自报 `timeout=2.0 s` < 框架 30 s，实测 `data.timeout_ms=2000` 且 `elapsed≈2.1 s`
  ⇒ 「工具只能收紧框架上限」（`mcp_jsonrpc.cpp:235` 的 `_effective_timeout = MIN`）**证据支持**；
  同为 `-32000` 且带 `data.suggestion`+`data.timeout_ms`（GDR-20 pt.4）。
- **断连清理**：`pending` 与 `pending_connections` 在硬断连后归零、进程不崩、后续请求正常
  ⇒ GDR-20 pt.5「连接断开是唯一清理点、不得泄漏」**证据支持**。
- **不串线**：两条连接同 id=5555，截止时间分别是 10 s 与 4 s，各自收到自己那一份
  ⇒ 表键确为 **(连接, 请求 id)**，不存在全局 FIFO（GDR-20 pt.1）。
- **不饿死常规请求**：有 pending 时 `ping` 35 ms 返回（GDR-20 pt.3）。
- **同连接响应顺序**：deferred 请求在前、`ping` 在后，应答顺序与请求顺序一致（GDR-20 pt.8）。

---

## 5. E. 一致性

```
[PASS] E1_b1_manifest_41_unique_and_group_invariants   :: 41 名、0 重复、0 不变量违例
[PASS] E2_b2_manifest_25_unique_and_group_invariants   :: 25 名、0 重复、0 不变量违例（含 scope）
[PASS] E3_contract_171_exactly_matches_map_rename_and_fixfirst :: contract=171 map(rename+fixfirst)=171 双向差集为空
[PASS] E4_contract_excludes_the_2_unregister_and_keeps_the_merge_survivor
[PASS] E5_map_total_bookkeeping_is_consistent :: total=174 entries=174 ; unregister 2 + merged 1 + rename/fixfirst 171 = 174
[PASS] E6_tool_naming_md_sample_agrees_with_map_and_contract :: 10 个抽样名（含 2 个 unregister、1 个合并存活名）全部对齐
```
不变量逐组核验：B1 每组恰好一个 `channel` + 一个 `mutating` 且与映射逐成员一致、组 ≤10；
B2 同上再加 `scope` 一致。契约与映射双向差集为空 ⇒ 66 个名字在两份工件中无孤儿、无冲突。

---

## 6. 缺陷与偏差

### defects

| id | severity | claim | evidence | location | recommendation |
|---|---|---|---|---|---|
| **D-1** | **minor** | `running_game_set_node_property` 对**节点根本不存在的属性**返回**成功形状**（`new_value:null,old_value:null`），而不是 `-32001 not found`。调用者若只看顶层成功/失败，会把「什么也没发生」读成「已写入」。 | 自跑：`property=audit_no_such_property_xyz` → `error=none`，body `{"new_value":null,"node_path":"/root/Main","old_value":null,"property":"audit_no_such_property_xyz"}`（`evidence\C9-set-unknown-property.response.json`）。同工具对**真实属性**的写入是正确的：`position` 由 `{11,22}` → `{321,123}`，且用**另一个工具**（`running_game_execute_gdscript`）独立读回一致。 | `modules\mcp_server\tools\running_game_node_write.cpp:209-249`（无 `get_property_list`/`has_property` 存在性检查，`property_type_of` 返回 NIL 即 `coerce` 直通） | 在 `property_type_of` 得到 `NIL` 且 `node->get(property_name)` 为 `NIL` 时返回 `MCPToolError::not_found(...)`（或至少在结果里加 `applied:false`/`property_exists:false`）。注意：迁移源同样谎报 `set:true`（`addons\godot_mcp_rs\mcp_runtime_agent.gd:159-160`），故本条**不是与迁移源不一致**，而是「工具真的能用」标准下的诚实性缺口。 |
| **D-2** | **nit** | headless 下 `editor_capture_screenshot` 以 `-32603 Internal error: 截图获取失败, 请重试` 收尾，而同类能力缺失（游戏侧 `running_game_capture_frames`）用的是 GDR-20 pt.10 规定的 `-32000` + `data.suggestion`。错误码不统一，客户端难以按「能力不足」分支处理。 | `evidence\C7-capture-screenshot.response.json`（`-32603` 无 `data.suggestion`）对比 `evidence\C5-game_capture_frames_huge_count.response.json`（`-32000` + suggestion）。 | `tools\editor_write_scene_editor.cpp` 截图工具的错误分支 | 与 GDR-20 pt.10 对齐：判定 display server 能力 → `-32000` + `data.suggestion`（`-32603` 留给真正的内部错误）。 |
| **D-3** | **nit** | 契约 `running_game_play_input_recording` 的 `inputSchema.required` 仍是 `["events"]`，与实现（D59 裁决 1 已把 `events` 放宽为可缺省）**不一致**；`tools/list` 也照样宣称必填。消费者按契约就会传 `events`，不按契约才会享受回退 → 契约文本说谎。 | 自跑：契约与线上 `required=[events]`（`evidence\C9-game-tools-list.response.json`）；handler 无 `events` 时返回 `-32602 Parameter 'events' must not be empty: … (pass the events, or call running_game_stop_input_recording in this game process first)`（`evidence\C9-play-without-events.response.json`）。即 `required` 确实**没有**被强制执行。D59 明文要求「M2 验收时复核」，故本项是**任务书点名要复核的点**。 | `docs\tools_list.renamed.json`（`running_game_play_input_recording.inputSchema.required`） | 决策层二选一：①把 `required` 去掉并按契约重生成（需更新 `_meta` 与 `TOOL-NAMING.md` 的指纹）；②明确撤回 D59 裁决 1、恢复「必须传 `events`」并在报告里显式登记。**本审计不代为决定**（属契约文本变更，超出验收权限）。 |

### deviations_ruled（对 PLAYBOOK §6 与各报告自报偏差的抽样复核）

| 偏差 | 审计复核 | 结论 |
|---|---|---|
| §6.1 `path` 不存在 → `-32001` + suggestion（迁移源静默空结果） | 实测 `-32001 … not found` + `data.suggestion` | 接受，**已复现** |
| §6.2 `optional_*` 类型错 → `-32602`（迁移源静默忽略） | 实测 `max_depth='deep'` → `-32602 must be an integer` | 接受，**已复现** |
| §6.3 `normalize_project_path` 折叠 `.`/空段、`..` 折叠前拒绝 | 8 种逃逸拼写全 `-32602`；`res://a//b` 归一 | 接受，**已复现** |
| §6.4 `tools/list` 顺序非规范但必须确定性 | 同 id 三次 + 跨进程重启字节一致 | 接受，**已复现** |
| §6.6 三处「迁移源有缺陷、按意图实现」 | `project_get_scene_exports`（非空导出）、`editor_analyze_signal_flow`（`CONNECT_PERSIST` → 非空 `nodes[]`）、`project_analyze_scene_complexity`（无 segv）均实测可用 | 接受，**已复现**（第 2 条在本审计真实编辑器里直接观察到非空结果） |
| §6.8 迁移源怪癖保留（如 `type` 恒空） | 未逐条复核（属 B1 细节） | 见 §7 U-3 |
| §6.9 长度字段用 UTF-8 字节数 | `project_read_script.size` 与文件字节数一致 | 接受，**已复现** |
| D59 裁决 1（`events` 放宽） | **契约未同步** | → §6 D-3 |
| D59 裁决 6（答案超集） | `stop_input_recording` 超集键、`actions` 升序 | 接受 |
| `REPORT-008` 自报 `editor_remove_output_log` 已修 | 源码 + doctest 不变式 + 二次调用自洽性支持 | **部分证据支持**（§3.3 与 U-1） |

---

## 7. unconfirmed

- **U-1（诚实性最后一环）**：未能在**真实带面板的编辑器进程**里独立完成「注入可识别文本 → 调用 → 断言文本消失」的端到端观察。
  已取得的是：源码调用面板 *Clear* 同一路径、doctest 不变式（无 EditorLog 时绝不报 `cleared:true`）、
  二次调用 `log_was_empty` 转 true 的自洽性。**「真的清了面板」属证据支持（源码 + 测点），但未由本审计肉眼观测**。
- **U-2（`--headless` 与窗口化的差异）**：本审计的全部成功类证据都在 `--headless` 下采集。
  两个截图工具（`editor_capture_screenshot` / `running_game_capture_screenshot`）的成功路径需要**窗口化**进程，
  本审计未在窗口化进程取证（也不宜在用户桌面弹窗）。因此「截图成功路径」**未验证**（拒绝路径已验证）。
- **U-3（迁移源怪癖逐条保留性）**：PLAYBOOK §6.8 列出的「怪癖保留」（如 `project_get_scene_dependencies` 的 `type` 恒空串）
  只做了形状级抽样，未对 66 条逐条回读迁移源源码做语义等价证明。

## 8. risks

- **R-1**：`bin\` 的构建产物不是版本受控物（`.gitignore:263 [Bb]in/`），**门的结果随构建状态漂移**。
  本次审计不得不先重建（旧二进制落后 HEAD 一个 TASK）。若后续门不在重建后运行，会重现「假红/假绿」。
  建议：门的脚本开头强制 `build_local.cmd` 或校验 `--version` 的 hash 前缀 == `git rev-parse --short HEAD`。
- **R-2**：契约可由生成器重生成，但 `_meta.map_sha256`/`generated_from_sha256` 与 `TOOL-NAMING.md` 的头部指纹
  形成一条**手工维护的指纹链**；D-3 的修法必须重跑生成器并更新指纹，否则会出现新的文档不一致。
- **R-3**：deferred 的清理只由「连接断开」触发（GDR-20 pt.5 的设计选择）。本次实测归零；
  但若某个 handler 的 `Task` 永久 pending（既无超时又无连接断开），则只能靠框架 30 s 上限兜底 ——
  该上限是 `mcp_server/pending_timeout_ms` 的配置项，配成 0 会关闭兜底（源码 `mcp_server.cpp:375-378` 允许 0）。
- **R-4**：66 个工具里 22 个 editor-scope 写工具依赖 `MCP_EDITOR_TOOLS_ENABLED`（`TOOLS_ENABLED` 构建）。
  非 tools 构建里这些工具不会注册——本条由编译期宏保证，但本次审计**只**在 editor 构建（`target=editor`）下验证。

## 9. next_step_recommendation

1. **接受 M2 判决 `pass`**：66 个工具可按契约使用、不谎报、不越界；6 个未修 fix-first 与 2 个 unregister 均未上线。
2. 把 **D-3** 交回**阶段二/三**（契约文本变更属设计层，不是实现缺陷）：决定 `events` 是否恢复为必填，
   然后重跑 `gen_renamed_contract.py` 与两个 manifest 检查、更新 `_meta`/`TOOL-NAMING.md` 指纹。
3. **D-1 / D-2** 可作为 B3 开工前的顺手项（各 1 处分支 + 1 个 doctest），不必单独开批。
4. 建议把 **R-1**（门必须绑定到与 HEAD 一致的构建）写进 `PLAYBOOK §3`，这是本次审计唯一发现的流程性风险。
5. 若要求 U-1/U-2 闭合，需在**用户许可**下开一次短命的窗口化编辑器进程（不占 9877）取两张截图成功证据；
   当前证据水平已足以判定 `pass`，故本审计未擅自弹窗。

## 10. 端口纪律与收尾证据

```
（z_final.ps1 输出，落盘 F-checks.json）
[F1] 9877 LISTENING 属于 PID 36392（Godot_v4.7.1-stable_mono_win64，启动于 09/21 19:34:39，审计全程未变）
[F2] 9888/9889 LISTENING count = 0（仅剩内核 TIME_WAIT 条目，无属主进程）
[F3] 无本次审计遗留的 godot 进程（脚本启动的 PID 全部退出）
[F4] git status --porcelain = 开工前既有的 4 个未跟踪物（.graphifyignore / build-m0.cmd / graphify-out/ / install-deps-m0.cmd）
     + 本报告 `?? modules/mcp_server/docs/reports/REPORT-AUDIT-M2.md`（任务书强制要求的新增物；置入排除项后 unexpected = []）
     HEAD = e843f466689570456ee8e1a7ea8977ec81ea2332（未提交、未工作树改动）
```
**未修改任何仓库内文件**：审计脚本、请求体、响应体、引擎日志、门日志全部在 `%TEMP%\audit-m2\`；
构建只写 `bin\`（被 `.gitignore` 忽略的产物目录，且必须重建才能验收 HEAD）。
未执行任何 git 写操作；未安装依赖；未访问 `100.105.152.101:18080`。

## 11. 可复现清单（脚本 → 结论）

| 脚本（`%TEMP%\audit-m2\`） | 覆盖 | 结果文件 |
|---|---|---|
| `a1_sets.ps1` | 66 集合、scope 推导、49/40、7 fix-first 与 2 unregister 的成员资格 | stdout |
| `a2_endpoints.ps1` | A1–A6、A8–A10 全量对等与双向 scope | 控制台 + `evidence\A*.json` |
| `a5_determinism.ps1` | A7 同 id 三次 + 跨进程重启字节一致 | `A7-checks.json` |
| `a3_adversarial.ps1` | C1–C8 路径逃逸 / 参数滥用 / 诚实性抽样 | `C-checks.json`、`evidence\C*.json` |
| `a4_deferred.ps1` | B1–B5 deferred 通道 9 项 | `B-checks.json` |
| `a6_c5followup.ps1` / `a7_property.ps1` / `a9_c9.ps1` | C5/C9 跟随验证（未知属性、D59 契约、独立 GDScript 观测） | `C5d-checks.json`、`C5e-checks.json`、`C9-checks.json` |
| `a8_consistency.ps1` | E1–E6 一致性 | `E-checks.json` |
| `b1_sampling.ps1` + `b2_sampling2.ps1` | 42 条行为抽样（3 注册通道、两个 scope 方向、写工具、deferred） | `S-checks.json`、`S2-checks.json` |
| `t_json.ps1` / `t_json2.ps1` / `t_empty.ps1` | 固定审计宿主自身的两个 PowerShell 陷阱（空字典序列化、`$Args` 自动变量） | stdout |
| `z_final.ps1` | F1–F4 端口/进程/工作树收尾 | `F-checks.json` |
| `run_d_gates.cmd` | `accept_m1.ps1` ×2 + 两个 manifest 检查 | `gates\accept-A.log`、`gates\accept-B.log`、`gates\groups-b1.log`、`gates\groups-b2.log`、`gates\doctest-mcp.log`、`gates\doctest-full.log` |

## 12. 工程门原始输出（摘要，全文见 `gates\`）

```
--headless --test --test-case="[MCPServer]*"   exit 0
[doctest] test cases:  122 |  122 passed | 0 failed | 1429 skipped
[doctest] assertions: 3618 | 3618 passed | 0 failed    Status: SUCCESS!

--headless --test                              exit 0
[doctest] test cases:   1548 |   1548 passed | 0 failed | 3 skipped
[doctest] assertions: 427900 | 427900 passed | 0 failed  Status: SUCCESS!

accept_m1.ps1 run A                            exit 0   22/22 cases passed
accept_m1.ps1 run B                            exit 0   22/22 cases passed   两次 PASS 清单 Compare-Object = IDENTICAL（44 行同名同序）

check_tool_groups.py               (B1)        exit 0   TOOL-GROUPS CHECK PASS      BYTES 5682  SHA256 0cfcac80…bfac
check_tool_groups.py --batch B2               exit 0   TOOL-GROUPS-B2 CHECK PASS   BYTES 11623 SHA256 14eba000…b75d
```
