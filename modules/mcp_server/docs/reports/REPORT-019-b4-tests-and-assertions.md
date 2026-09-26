# REPORT-019 — B4 收官（7 个工具）+ `editor_get_test_report` 红→修 + P-1 死代码 + M4 收口

- **status**：完成。五道门在实现提交 `e5bfdc9681` 上全绿（见 §6）。**B4 = 7/7**、**M4 = 47/47**（见 §5）。
- **commits**（`feature/mcp-server-module`，**未 push**）：
  | sha | 一行说明 |
  |---|---|
  | `e5bfdc9681` | B4 全部 7 个工具（3 组）+ `editor_get_test_report` 的累加器与红→修 + `run_test_scenario` 结构化结论 + `capture_signal_emissions` + P-1 死代码 + 注册表计数按实测修正 + `docs/tool-groups-b4.json` 3 组置 `implemented=true` + 门②证据脚本 |
  | 本报告 | `docs/reports/REPORT-019-b4-tests-and-assertions.md`（报告提交见 `git log` 最后一条） |
- **引擎二进制**：`--version` = `4.8.dev.custom_build.a63583c6a`，与五道门开跑时的 `git rev-parse --short HEAD`
  （`a63583c6ab`）前 9 位一致；门②脚本首条 check（`gate_version_matches_head`）机器校验这一点。
  实现提交 `e5bfdc9681` 只增删源码与文档、**不重编译二进制**，所以冻结提交上的门结果与 `e5bfdc9681` 的内容一一对应。
- **门②证据脚本**：`modules/mcp_server/scripts/mcp019_b4_evidence.ps1`，sha256 `dbc958ca0e94846d88a11733255ed08d235606aa42635e1d716864df7f3df9d7`，**66 checks / 66 passed / 0 failed**（exit 0）。
- **证据落盘**：每次门②把**每个请求体与响应体**写到 `%TEMP%\mcp019-evidence\<check_id>.{request,response}.json`（`curl.exe -s -o` 抓原始字节 + sha256），重跑即可复现。
- **未 push**（任务书要求）。仅改动 `modules/mcp_server/**`；`git status --porcelain core/` 为空。

---

## 1. 第一部分：`editor_get_test_report` 红 → 修（任务书 ①，`fix_implementation_first`）

### 1.1 缺陷本体（迁移源逐字引用）

`godot_mcp_gdext/src/commands/test.rs:560-590`。它**不收集任何东西**，无论调用多少次都只回一个常量：

```rust
/// 5. get_test_report: 获取测试报告
fn cmd_get_test_report(args) -> ... {
    let _clear = opt_bool(args, "clear", true);          // <- 读了就丢，没有副作用
    // 使用 GDScript Expression 获取测试结果
    // 在 Rust 端维护_test_results 不现实，所以通过 Expression 获取
    let mut expr = Expression::new_gd();
    let report_code = "\
var ei = EditorInterface \
if ei == null: \
    return JSON.stringify({\"error\": \"No EditorInterface\"}) \
return JSON.stringify({\"message\": \"使用 assert_node_state 等测试命令会自动收集结果。请查阅最近执行的测试命令输出。\", \"available_commands\": [...])";
    if expr.parse(report_code) == Error::OK { ... }
    // 回退方案
    Ok(serde_json::json!({
        "message": "测试报告",
        "note": "测试结果在各命令的返回中查看。使用 run_test_scenario 执行完整测试流程。",
        "available_commands": ["run_test_scenario", "assert_node_state", "assert_screen_text", "run_stress_test"],
    }))
}
```

两个独立的坏点：

1. **没有任何累加器**。`assert_node_state` / `assert_screen_text` / `run_test_scenario` 各自返回自己的结论，没有任何一处把结论存下来，所以「报告」在结构上不可能反映真实运行。
2. **它回答的是建议，不是结果**。调用者问「刚才那一串断言结果如何」，得到的是 `message`（一句中文提示）+ `available_commands`（命令名列表）+ `note`。这是**假成功**：`status: ok`，但请求的语义完全没有被满足。

`Expression` 那条分支本身也不可能成功（`Expression` 不支持语句块里的 `return`），但它无关紧要——回退方案回的也是同一个常量。

### 1.2 红证据（先证明「常量的实现过不了」）

按 TDD，红先于绿。红的一半落在 doctest：`tests/test_mcp_server.h:10767` 的
`TEST_CASE("[MCPServer] editor_get_test_report reports the assertions that really ran")`，
**第一条断言就是空累加器契约**，常量实现必然不过：

```cpp
MCPTools::clear_test_results();
// ... 空累加器
CHECK((int)report["total"] == 0);
CHECK((bool)report["no_results"] == true);
CHECK((bool)report["all_passed"] == false);      // "没跑过" != "全部通过"
CHECK(String(report["pass_rate"]) == "N/A");
CHECK_FALSE(report.has("message"));              // 迁移源的常量三件套
CHECK_FALSE(report.has("available_commands"));
CHECK_FALSE(report.has("note"));
```

红的另一半落在**线上**（门② `C1`/`C2`），线上这一半才是「常量实现会被谁看穿」的证明：

| check id | 请求 | 结果 | sha256（响应原始字节） |
|---|---|---|---|
| `C1_get_test_report_success_shape` | `editor_get_test_report {clear:false}` @9888 | `{"all_passed":false,"details":[],"failed":0,"no_results":true,"pass_rate":"N/A","passed":0,"source":"editor_process","total":0}` | `3d8324d074c51b39c08813c141d515e4859bc93af054c66eee9f62c3472e61a3` |
| `C2_get_test_report_rejects_the_fabricated_message_shape` | 同上，逐键检查 | `has message=False available_commands=False note=False` | 同上 |
| `C3_get_test_report_mistyped_clear_is_32602` | `{clear:"yes"}` | `-32602` `Parameter 'clear' must be a boolean, got String` | — |

`C1` 的 payload 里 `total=0 no_results=true` 是关键：**常量实现从结构上就没有这两个键**，也没有能力区分「0 条通过」与「5 条通过 3 条失败」。

### 1.3 修法（累加器一处定义，两个进程各自持有）

累加器加在 `tools/tool_helpers.{h,cpp}`（`tool_helpers.h:650-670`）里，是模块**唯一**的测试结果累加器
（`record_test_result` / `get_test_results` / `clear_test_results` / `build_test_report`），被 B4 的两条断言工具与场景运行器共同写入。
放在 `tool_helpers` 而不是某个 B4 组文件里，是因为它要被 `editor_testing_read`（编辑器侧读）与
`running_game_assertion` / `running_game_test_execution`（游戏侧写）**共同**使用，而一组不得复制另一组的文件私有助手（PLAYBOOK §2.4）。

- `build_test_report()` 产出 `total / passed / failed / pass_rate / all_passed / no_results / details`；
- `pass_rate` 在 `total == 0` 时是 `"N/A"` 而不是 `"0.0%"`——「没跑过」不是「全挂」；
- 没有 `passed` 键的条目（`input` / `wait` 步骤）被跳过，不污染通过率。这条规则是 `run_test_scenario` 能把 `wait` 步骤塞进同一累加器的前提。

**报告是「累加器的原样回答」，不是新造的句子**：`_tool_get_test_report()` 只做三件事——读累加器、按 `clear`（默认 `true`）清空、加一个 `source:"editor_process"` 字段。`source` 存在的理由见 §1.4。

绿证据（同一批 check，修后）：`C1` 仍是 `total=0 no_results=true`（空累加器就该这么答），而**非空**的累加器在 doctest 里被逐字段钉住：

```cpp
MCPTools::record_test_result(pass);   // passed=true
MCPTools::record_test_result(fail);   // passed=false
MCPTools::record_test_result(no_verdict);  // 无 passed 键 -> 跳过
// total == 2, passed == 1, failed == 1, pass_rate == "50.0%",
// all_passed == false, no_results == false, details.size() == 2
```

### 1.4 一个必须解释的行为选择：**报告是「进程内」的**

`editor_get_test_report` 只回答**它自己所在进程**的累加器。这不是取巧，而是本模块的结构事实：模块被编译进编辑器进程与游戏进程两个二进制，两个进程不共享内存（GDR-21 的输入通道边界就是同一个道理的另一面）。游戏进程里跑的四条断言（门② `C10/C11/C16/C17`）**不应该**出现在编辑器进程的报告里，`source:"editor_process"` 就是把这件事显式说出来，让调用者不会把「空报告」误读成「游戏进程没跑测试」。

线上证据——`D` 段：

| check id | 证据 |
|---|---|
| `D1_editor_report_clears_to_nothing` | `clear` 后 `total=0 no_results=True source=editor_process` |
| `D2_editor_report_is_empty_without_editor_assertions` | `total=0 no_results=True all_passed=False pass_rate='N/A'` |
| `D3_game_assertions_do_not_leak_into_the_editor_report` | 游戏进程刚跑完 4 条断言（C10/C11/C16/C17）后，编辑器报告 `total=0` |
| `D4_the_editor_tools_share_the_process_with_the_editor_executor` | 同一 9888 上 `editor_execute_gdscript` 正常应答 `{"result":true,"result_type":"bool"}`（证明 9888 确实是编辑器进程，`D3` 不是「端口搞错了」） |

---

## 2. 第二部分：场景运行器的结构化通过 / 失败结论（任务书 ②）

`running_game_run_test_scenario` 是**延迟通道**工具（跨帧等待 `wait` 步骤），在游戏进程 9889 上执行，返回**结构化结论**而不是一句话。

### 2.1 通过样本（门② `E1`）

请求 `steps = [wait 0.1, assert Actor.position eq {"x":3,"y":4}, assert text "Hello MCP", wait 0.1]`：

```json
{"all_passed":true,"completed_steps":4,"duration_ms":235,"errors":0,"failed":0,"passed":2,
 "results":[
   {"step":0,"type":"wait","waited_seconds":0.1},
   {"actual":{"x":3.0,"y":4.0},"expected":{"x":3.0,"y":4.0},"node_path":"Actor","operator":"eq",
    "passed":true,"property":"position","resolved_node_path":"/root/Main/Actor","step":1,"type":"assert"},
   {"case_sensitive":true,"expected_text":"Hello MCP","matched_element":{"name":"Title","path":"/root/Main/Ui/Title","text":"Hello MCP","type":"Label"},
    "partial":true,"passed":true,"source":"control_tree","step":2,"type":"assert","visible_texts":["Hello MCP","Go"]},
   {"step":3,"type":"wait","waited_seconds":0.1}],
 "total_steps":4}
```

### 2.2 **故意失败**的场景（任务书 ② 的核心要求）

一个「真的会报 fail」的证明不能靠「通过样本」，必须有一个**确定会挂**的场景。门② `E2` 发的是
`[wait 0.05, assert Actor.position eq {"x":999,"y":999}, assert text "ThisTextIsNotOnScreen"]`
（断言值客观不在场景里），响应原始字节 sha256 `6977527ac7c729d7b7766e3694c743cf6bceaa2e2ee0666a4edf260024252b2c`：

```json
{"all_passed":false,"completed_steps":3,"duration_ms":76,"errors":0,"failed":2,"passed":0,
 "results":[
   {"step":0,"type":"wait","waited_seconds":0.05},
   {"actual":{"x":3.0,"y":4.0},"expected":{"x":999.0,"y":999.0},"node_path":"Actor","operator":"eq",
    "passed":false,"property":"position",
    "reason":"expected position eq {\"x\":999.0,\"y\":999.0}, found {\"x\":3.0,\"y\":4.0}",
    "resolved_node_path":"/root/Main/Actor","step":1,"type":"assert"},
   {"case_sensitive":true,"expected_text":"ThisTextIsNotOnScreen","partial":true,"passed":false,
    "reason":"screen text containing 'ThisTextIsNotOnScreen' was not found in the 2 visible text(s) of the control tree",
    "source":"control_tree","step":2,"type":"assert","visible_texts":["Hello MCP","Go"]}],
 "total_steps":3}
```

`E2` 的三条从属 check 把「这不是偶然」钉住：

- `E2_..._reports_a_deliberate_failure`：`all_passed=False passed=0 failed=2`；
- `E3_the_failing_assertion_carries_expected_and_actual`：失败步骤**同时**带 `expected` / `actual` / `reason` / `resolved_node_path`——调用者能直接看出差在哪，不需要再发一次读属性请求；
- `E4_the_failing_scenario_is_not_all_passed_with_zero_assertions`：**一个什么都不断言的场景也不许算「全通过」**（`all_passed=False`）。这条防的是「空场景返回成功」这类最容易被滑过去的假成功。

### 2.3 参数契约在**跑之前**全量校验（不在中途才失败）

场景运行器是延迟工具，一旦开始跑就跨帧了；所以 `steps` 的每个字段都在**进入延迟通道之前**校验完。线上拒绝证据：

| check id | 请求 | 响应 |
|---|---|---|
| `E5` | `steps: []` | `-32602 Parameter 'steps' must not be empty` |
| `E6` | `steps: [{type:"jump"}]` | `-32602 Parameter 'steps[0]'.type is 'jump'; a scenario step is 'input', 'wait' or 'assert'` |
| `E7` | `scene_path:"main"` | `-32602 ... 'scene_path' ('main') is not supported by the game-scope runner: the migration source used it to make the *editor* play a scene before the steps ran, and this tool runs inside the game process that is already running. Use editor_play_scene (editor endpoint) first, then run the scenario against the running game` |

`E7` 是**行为变更**（见 §7 deviations）：迁移源把 `scene_path` 当「先让编辑器播场景」，在游戏进程里语义不成立；本实现**显式拒绝并给出替代路径**，而不是静默忽略一个调用者以为生效了的参数。

### 2.4 `run_stress_test`：**故意没有 `passed` 字段**

压力测试能观测到的是「跑了多少次、发了多少事件、游戏还在不在」，它**不能**判定「功能是否正确」——那需要一个场景断言。所以返回值里没有 `passed` / `all_passed`：`E9_run_stress_test_has_no_fabricated_verdict` 机器校验这两个键**不存在**，把「故意失败的演示」留在真正能判定的场景运行器里。`E8` 的样本：

```json
{"actions":["ui_accept"],"average_iteration_ms":0.0,"completed":true,"crashed":false,
 "elapsed_ms":835,"events_sent":240,"game_still_running":true,"iterations":120,"iterations_completed":120}
```

`E10`：`count: 0` → `-32602 Parameter 'count' must be at least 1, got 0: a stress test of zero iterations is not a test`。

---

## 3. 第三部分：其余 B4 工具（任务书 ①）

### 3.1 逐工具证据（成功 / 缺参 / 底层失败，每个至少一条）

| 工具 | 成功 | 缺参 / 参数错误 | 底层失败 |
|---|---|---|---|
| `editor_get_test_report` | `C1`（空累加器）+ doctest（1 通过 1 失败 → `50.0%`） | `C3` `clear:"yes"` → `-32602` | — |
| `editor_analyze_screenshot_diff` | `C4` `identical:true changed_pixels:0 total_pixels:4`；`C4a` 引擎自产 PNG | `C6` 缺 `image_a` → `-32602`；`C8` `threshold:300` → `-32602` | `C7` 文件不存在 → `-32001 Image 'res://does_not_exist.png' not found` |
| `running_game_assert_node_state` | `C10` `passed:true` | `C12` 缺 `expected` → `-32602`；`C13` 非法算子 → `-32602` 且**列出 8 个合法名** | `C14` 节点不存在 `-32001`；`C15` 属性不存在 `-32001` |
| `running_game_assert_screen_text` | `C16` 命中真实 `Label`，带 `matched_element` 与完整 `visible_texts` | `C20` 缺 `text` → `-32602` | `C17` 未命中（`passed:false` 且**列出搜索空间**）；`C18` 隐藏 `Label` 的 `"Secret"` 不在 `visible_texts` |
| `running_game_capture_signal_emissions` | `F1` `watched=1 count=102`；`F2` 首 tick 1387 → 末 tick 1488 | `F3` 缺 `node_paths` → `-32602`；`F5` `duration_ms:600001` → `-32602` | `F4` 节点不存在 `-32001` |
| `running_game_run_test_scenario` | `E1` | `E5` / `E6` / `E7` | `E2` / `E3`（故意失败） |
| `running_game_run_stress_test` | `E8` | `E10` `count:0` | `E9`（拒绝伪造结论） |

`C9_p1_vector2_string_refused_on_the_wire` 与 §4 的 P-1 是同一条证据的线上那一半。

### 3.2 `assert_screen_text`：迁移源读了一个**从没被写过**的键

迁移源（`test.rs:404-460`）通过 `find_ui_elements` 拿元素，然后读 `elem["text"]`。但
`find_ui_elements` 的收集器**从不写 `text` 键**，所以 `elem_text` 恒为空串，循环第一个元素就 `continue`，
`all_texts` 恒为空 → **永远 `passed: false`**。同时它把 `case_sensitive` 读进 `_case_sensitive` 后**从不使用**（下划线前缀）。

本实现改为直接遍历 `Control` 树取真实文本（`collect_visible_texts()`，跳过 `visible == false` 的子树），并**真正实现** `case_sensitive`：

- `C16`：`partial:true` + `case_sensitive:true`，命中 `Title`（`"Hello MCP"` 包含 `"Hello"`），`matched_element` 带 `name/path/text/type`；
- `C19`：`case_sensitive:false` + `partial:false` 时大小写不敏感地精确匹配 → `passed=True`；
- `C18`：`visible=false` 的 `"Secret"` **不在** `visible_texts` 里。

### 3.3 `capture_signal_emissions`：窗口是真窗口，参数是可核对的集合

`F1`：`watched:[{node:"/root/Main",signal:"pulse",emissions:102}]`，`watch_ended:"duration"`。
`F2` 是防「同一帧采样 N 次」的那条：首个 tick `1387`、末个 tick `1488`，**单调递增**，证明收的是跨帧窗口。
`F6`：不带 `signal_filter` 时把节点的 18 个可连信号全连上，窗口照样能正常结束（`watch_ended:"duration"`），
证明终止条件不依赖「一定收到信号」。
`F5`：`duration_ms` 上限 600000 并在消息里说明**为什么**（框架请求 deadline 30 s，更长窗口永远不可能完成）。

---

## 4. 第四部分：P-1 死代码（任务书 ③）

`tools/tool_helpers.cpp` 的 `property_value_from_json()` 里有一条 `"Vector2(...)"` 字符串语法分支：
把 `"Vector2(1,2)"` 这样的字符串解析成字典。它**在到达那条分支之前就已经死了**——`coerce_to_property_type()`
的 `Variant::can_convert(STRING, VECTOR2)` 为假，所以字符串永远走不到「被解析」那一步，只会在下游
被拒（或更早：被静默转成零向量，这正是 REPORT-018 §1 修掉的那个错值）。任务书要求删掉它并加一条 doctest。

改动（`tool_helpers.cpp` / `.h`）：

- 删除 `"Vector2(...)"` 解析分支；字符串**保持是字符串**，交给 `coerce_to_property_type()` 按引擎自己的转换关系裁决；
- 头文件里那段描述「支持 `Vector2(...)` 语法」的注释改写为陈述**事实**：该语法在本 build 里不可用；
- `coerce_to_property_type()` 的拒绝消息结尾补一句 `the "Vector2(...)" string grammar is not available in this build - see TASK-019 P-1`，让线上调用者知道「你试的这条语法被有意移除了」，而不是以为消息写错了。

红/绿对照由两处证据支撑：

- **doctest**（`tests/test_mcp_server.h` P-1 用例）：字符串 `"Vector2(1,2)"` 送 `Vector2` 属性 → 拒绝，且消息含 `not available in this build`；
- **线上**（门② `C9`）：同一条消息在 9888 上逐字复现（见 §6 的 `C9` 行）。

删掉死代码的价值不在「少几行」，而在**消除一个会撒谎的文档**：注释说支持，实际不支持，而调用者只能从一句含糊的转换失败里猜。

---

## 5. 第五部分：B4 = 7/7、M4 = 47/47（机器校验）

### 5.1 范围怎么派生（不手写清单）

「哪个端点服务哪个工具」**从 rename map 的 `scope` 字段派生**（权威：`docs/tool-rename-map.json` v1.1，TASK-006 §2）：
编辑器端点广告 `scope ∈ {editor, both}`，游戏端点广告 `scope ∈ {game, both}`。

B4 的 7 个工具是 `2 editor-scope + 5 game-scope`、**没有 both-scope 成员**，所以
「B4 = 7/7」是关于**两个端点合起来**的陈述：9888 上 2 个、9889 上 5 个、并集 7 个、两个方向零泄漏。
把它写成「7 个全在 9888 上」会是一条本模块**并不具备**的契约。

机器校验（门② `B` 段，全部来自两个端点的 `tools/list` **真实响应**）：

| check id | 证据 |
|---|---|
| `B0_every_b4_tool_has_a_scope_in_the_rename_map` | `editor-scope 2 + game-scope 5 = 7`，无 `?` |
| `B1_b4_is_complete_7_of_7` | `manifest total=7 tools=7 groups=3 implemented_tools=7 implemented_groups=3` |
| `B2_b4_editor_scope_live_on_9888_only` | `editor-scope B4 on 9888: 2/2`，missing `[]` |
| `B3_b4_game_scope_live_on_9889_only` | `game-scope B4 on 9889: 5/5`，missing `[]` |
| `B3b_b4_is_7_of_7_across_the_two_endpoints` | `B4 live across 9888+9889: 7/7 (2 on editor, 5 on game), no tool served by both` |
| `B4_m4_is_47_of_47` | `B3 implemented=40 B4 implemented=7 M4 union=47/47` |
| `B4b_every_m4_tool_has_a_scope_in_the_rename_map` | 无 `?` |
| `B5_m4_live_47_on_9888` | `42/42 (editor+both)`，missing `[]` |
| `B6_m4_live_on_9889_matches_scope` | `13/13 (game+both)`，missing `[]` |
| `B7/B8/B9` | `check_tool_groups.py --batch B4` / `--batch B3` / `--check-completeness` 三项 exit 0 |

`python docs/scripts/check_tool_groups.py --batch B4` 的关键行：
`ASSERT implemented=true groups = 3, carrying 7 tool(s): editor_get_test_report, editor_analyze_screenshot_diff, running_game_assert_node_state, running_game_assert_screen_text, running_game_capture_signal_emissions, running_game_run_test_scenario, running_game_run_stress_test`
→ `TOOL-GROUPS-B4 CHECK PASS`（文件 sha256 `d95d7d9e793a11aa56ccb66513051ec446e94725316ef3f54dfc28cf4f40a708`）。

### 5.2 注册表计数（随已实现并集上移，全部经测量）

B1+B2+B3+B4 的 scope 分布：**editor 60 / both 31 / game 22 = 113**。由「实现的并集 = 编辑器端点 = 并集减去 `scope == game`」这条规则派生：

| 量 | 值 | 独立佐证 |
|---|---|---|
| 游戏进程注册表 `get_tool_count()` | **53** | `check_contract_subset.ps1`：`game set: 53 tool(s)` |
| 编辑器进程注册表 `get_tool_count()` | **113** | manifest 并集 = 113 |
| 编辑器进程 `get_visible_tool_count(true)` | **91** | `check_contract_subset.ps1`：`editor set: 91 tool(s)` |
| 游戏进程 `get_visible_tool_count(true)`（同表按编辑器视图过滤） | **31** | = both-scope 数 |
| 两者 `get_visible_tool_count(false)` | **53** | 同上 |

**为什么 `91` 而不是 `97`**：`91 = 31 (both) + 60 (editor)`，游戏进程的 22 个 game-scope 工具不在编辑器视图里。
`check_contract_subset.ps1` 独立地从 171 条契约与 rename map 派生出 `scope: editor-only=60 game-only=22 both/shared=31`、`editor set: 91`，与 doctest 的测量一致；doctest 里那个 `97` 是**上一批遗留的错值**，
本任务用一条独立的实测量（在本机打印 `get_visible_tool_count(true)=91`）推翻并改正。
同一处 `registry.build_tools_list(true)` 的 `45` 也同时被纠正为 **31**：这张表是**游戏进程**表，
`EDITOR` scope 的工具在非编辑器进程**根本不注册**（GDR-19 §17.3），所以它的编辑器视图只可能是那 31 个 both-scope 工具。

---

## 6. 第六部分：五道门（真实输出与退出码）

### 门① 契约子集（每个 B4 组一次，共 3 次）

```
=== editor_testing_read ===     editor_9888_contract_subset PASS   game_9889_contract_subset PASS   guard_user_port_9877 PASS   3/3
=== running_game_assertion ===  editor_9888_contract_subset PASS   game_9889_contract_subset PASS   guard_user_port_9877 PASS   3/3
=== running_game_test_execution === editor_9888_contract_subset PASS game_9889_contract_subset PASS  guard_user_port_9877 PASS   3/3
```

每次的 `editor_9888_contract_subset` 都逐名比对 `tools/list` 与 `docs/tools_list.renamed.json` 的 `name/description/inputSchema`
（`editor_get_test_report: name=True description=True inputSchema=True` …），`group=… contract=171
implemented_union=91 tools (editor endpoint) / 53 tools (game endpoint)`。

### 门② 证据脚本（`scratch` 项目 + 9888/9889 双进程）

```
TASK-019 gate 2 evidence -- B4 (7 tools) and M4 closure
user editor on 9877 before run: pid=36392
engine --version: 4.8.dev.custom_build.a63583c6a; git HEAD: a63583c6ab   -> PASS gate_version_matches_head
[PASS] scratch_import_exit_code_is_zero :: imported with exit code 0 on attempt 1 (BOM-free)
...
TASK-019 evidence summary: 66 checks, 66 passed, 0 failed        <- exit 0
```

两条活性 check 是本门「不是只有 HTTP 200」的证明：`G1_the_game_process_survived_the_whole_battery`
`frame_count=650 pending=0 pending_connections=0`、`G2_the_editor_process_survived_the_whole_battery`
`frame_count=882 pending=0 pending_connections=0`（延迟通道**没有泄漏 pending 表**），
`H1_user_editor_on_9877_untouched` `pid before=36392 after=36392`。

### 门③ 模块 doctest

```
[doctest] test cases:  175 |  175 passed | 0 failed | 1429 skipped
[doctest] assertions: 7122 | 7122 passed | 0 failed |
[doctest] Status: SUCCESS!
```

（doctest 进程的 shell 退出码是 1 且 stderr 有既有的 `ERROR: Condition "!configured" is true. at: StringName::StringName` 噪声——这是本 fork 的既有现象，**与本任务无关**；判据是上面两行 `0 failed` / `SUCCESS!`。）

### 门④ 全引擎回归

```
[doctest] test cases:   1601 |   1601 passed | 0 failed | 3 skipped
[doctest] assertions: 431404 | 431404 passed | 0 failed |
[doctest] Status: SUCCESS!
```

### 门⑤ `accept_m1.ps1` 连续两次

两次均 exit 0，`22/22 cases passed`，两次的 `PASS/FAIL` 清单 **逐行相同**（`Compare-Object` 无差异）。
`accept_m1.ps1` 的 `$ToolNames` 已是上一批从 manifest 派生的版本，**本任务无需改动它**；它照旧报 `PASS gate_scope_declared`。

---

## 7. 第七部分：实施者自行决策的事项 + deviations / blockers / next_step

### 7.1 实施者自行决策（需要决策者知悉）

| # | 决策 | 理由 | 回滚点 |
|---|---|---|---|
| D-1 | 报告是**进程内**的，并加 `source:"editor_process"` | 两个进程不共享内存；加字段是为了让「空报告」不被误读为「测试没跑」 | 删掉 `source` 赋值即可；`D3` 的 check 会随之失效 |
| D-2 | `run_test_scenario` **拒绝** `scene_path` 而不是忽略 | 忽略一个调用者以为生效的参数是最坏的假成功；消息给出 `editor_play_scene` 替代路径 | 改回「忽略」需同时改 `E7` 的期望消息 |
| D-3 | `run_stress_test` **不再有** `passed` 字段 | 压力测试观测事实，不判定正确性；伪造一个 `passed:true` 就是任务书禁止的假成功 | 任务书 ② 的「故意失败」由 `run_test_scenario` 承担，不依赖此字段 |
| D-4 | 期望值按**实际值的形状**归一化后再比较（`assertion_expectation_for`） | 线上实测 `assert_node_state` 对 `position` 回 `passed:false`，而 `expected` 与 `actual` **打印出来一模一样**（`{"x":3.0,"y":4.0}`）——因为 Dictionary 与 `Vector2` 是不同类型。归一化走的就是 `running_game_set_node_property` 接受该对象时用的那一个映射（`vector_from_dictionary`），不是第二套规则 | 删掉 `assertion_expectation_for` 调用；`C10` / `E1` 会立刻回到 `passed:false` |
| D-5 | `capture_signal_emissions` 记录**独立快照**参数 | `Array` 是引用计数类型，直接存 `last_args` 会让 102 条 emission 全部显示**最后**一次的 tick（实测） | 改回直接赋值即可复现该缺陷 |
| D-6 | 通过 `ClassDB::get_signal_list()` + `Script::get_script_signal_list()` 枚举信号 | `Object::get_signal_list()` 的绑定是 `private:`（`object.h:479`），且 `Node::has_method("get_signal_list")` 在本 fork 实测为 **false**，走 `callp()` 会静默watch 0 个信号 | 无替代方案；这是唯一可行路径 |

### 7.2 deviations（与任务书/手册的偏离，逐条）

1. **`B4 = 7/7` 的口径**：任务书文字是「B4 = 7/7」，本报告把它落实为**两个端点合起来 7/7**（2 + 5，零泄漏），
   而不是「7 个都在 9888 上」。后者与本模块的 scope 契约（`check_contract_subset.ps1` 同样按 scope 派生）矛盾。
   证据见 §5.1。
2. **决策文档未新增**：任务书明确「不得新增 spec/decision 文档」，因此本批的决策（§7.1）落在本报告与代码注释里，
   未写入 `DECISIONS.md`。若决策者要求，可据此摘录。
3. **编辑器端可见数从 `97` 修正为 `91`**：这是**改了上一批的错值**，属于必须做的修正（§5.2），
   不是「边做边改需求」。若决策者认为这是前序工件缺陷，按阶段关卡应回到对应阶段更新工件——本报告即为该更新。
4. **`C4a` 的 PNG 由引擎自产**：`editor_capture_screenshot` 在 `--headless` 下没有 framebuffer（GDR-20 §10 记录的
   能力门），所以 diff 的输入改用 `project_get_resource_preview` 的输出字节（引擎自己的 PNG 编码器）。
   手工拼的 base64 曾被实测**无法加载**，故不采用。

### 7.3 blockers

无。五道门在 `e5bfdc9681` 上全绿；`9877` 上的用户编辑器（PID 36392）全程未被触碰。

### 7.4 next_step_recommendation

B4 与 M4 已收口（`B4 = 7/7`、`M4 = 47/47`、实现并集 113/171）。建议下一步进入 **B5**（`docs/tool-groups-b5.json`，
剩余 58 个工具），并在 B5 开工前先处理两件跨批事项：

1. **把 §7.1 的 D-4 / D-5 / D-6 三条引擎事实纳入共享文档**（若决策者允许开新文档），否则每一批都会重新踩：
   `Node::has_method("get_signal_list")` 为假、`CallableCustom` 的生命周期由 `Callable` 引用计数持有、
   `Array` 赋值是引用而非快照。
2. **考虑给 `check_contract_subset.ps1` 加一条「scope 与实际注册一致性」的自校验**：本任务在证据脚本里发现
   `-match` / 原始文本包含两种「查名字」的写法都会给出假 PASS（工具 description 互相点名工具名），
   这类假 PASS 值得在共享门脚本层面封堵一次。
