# REPORT-012 — B2 第三批：游戏输入 / 节点写 / 编辑器播放 / 输入读取（8 个工具）

任务书：`modules/mcp_server/docs/tasks/TASK-012-b2-input-playback-groups.md`
通用规范：`modules/mcp_server/docs/tasks/PLAYBOOK-group-port.md`（已完整阅读）
执行者：Godot 内置 MCP 模块实现工程师（TASK-012）
分支：`feature/mcp-server-module`（**未推送**）

## 0. 状态摘要

**commits**（英文提交信息，**未推送**）：

```
17bf5c151c  mcp_server: the input, node-write and playback groups (TASK-012)
            17 个文件、+3842/-50
            + tools/input_recorder.{h,cpp}            （录制设施：Node + 状态机）
            + tools/running_game_input.{h,cpp}        （4 工具）
            + tools/running_game_node_write.{h,cpp}   （1 工具）
            + tools/editor_playback.{h,cpp}           （2 工具）
            + tools/editor_input_read.{h,cpp}         （1 工具）
            + scripts/mcp012_input_playback_evidence.ps1（门②脚本）
            ~ registration.cpp / register_types.cpp / gen_b2_game_schema.py
            ~ tests/test_mcp_server.h（+6 用例） / accept_m1.ps1 / tool-groups-b2.json

19055f740f  mcp_server: TASK-012 report and the live evidence script
            本报告 + 门②脚本的 `g22d`「回放真的跨帧」检查（只增加检查数 31→32，
            未削弱任何断言；不含其它代码改动）

（本报告自身的后续补记提交以 `git log -- modules/mcp_server/docs/reports/REPORT-012-*.md` 为准；
其内容不会改变任何门或任何代码。）
```

| 项 | 结果 |
|---|---|
| `status` | **完成**：8 个工具移植完毕；五道门全绿；3 个真缺陷由活证据链抓到并修复 |
| 实现的工具数 | 8（四个组：4+1+2+1），已实现并集 52 → **60** |
| 端点 | 编辑器 9888 = 40 → **43**，游戏 9889 = 35 → **40** |
| 门① 契约子集逐字 | 四组**各跑两次**（共 8 次运行）各 **3/3 PASS**（9888 与 9889 双向 + 9877 守卫） |
| 门② 三类证据 + 活证据链 | 游戏相 **32/32 PASS**、播放相 **18/18 PASS**（§5/§6） |
| 门③ 模块 doctest | `[MCPServer]*`：**118/118 用例、3288/3288 断言全绿** |
| 门④ 全引擎回归 | `--headless --test`：**1544/1544 用例、427570/427570 断言，0 failed** |
| 门⑤ `accept_m1.ps1` ×2 | 两次各 **22/22 PASS**，两次 PASS 清单 `diff` 为空（**IDENTICAL**，各 22 行） |
| 9877 纪律 | 每次运行前后断言用户编辑器 pid 仍为 **36392**（全部通过） |
| 孤儿进程 | 播放子进程按 pid 追踪：停止后 **该 pid 及其整棵子树皆已消失**（§6.4） |

---

## 1. 组与端点（机器可见的计数）

| 项 | 值 |
|---|---|
| 新实现组 | `running_game_input`(4) + `running_game_node_write`(1) + `editor_playback`(2) + `editor_input_read`(1) |
| 已实现并集 | 52 → **60**（editor-scope 17 → 20；both 23 不变；game-scope 12 → 17） |
| 编辑器端点 9888 | 40 → **43**（= 60 − 17 个 game-scope） |
| 游戏端点 9889 | 35 → **40**（= 60 − 20 个 editor-scope） |
| B2 manifest | `docs/tool-groups-b2.json` 四个组 `implemented` 由 false 翻为 true（`sha256 055ae63287e23c02d922d03f68864597dea145ce4caa5c8931ac322a270ba1ad`） |
| `tools/list` 顺序 | 8 个新工具追加在既有顺序之后，同一次构建内确定性不变（门⑤ case20 跨进程重启仍逐字节相同） |

`docs/scripts/check_tool_groups.py --batch B2` 全过：25/25 恰好一次、每组一个 channel+scope+mutating、
`implemented=true` 组 8 个共 19 工具。

**契约/映射未被触碰**：`git diff --stat` 对 `docs/tools_list.renamed.json`、`docs/tool-rename-map.json`、
`docs/tool-groups.json` **为空**（三个文件均未改）。

### 1.1 与任务书表格的一处措辞差异（已在报告显式记录）

任务书 §1 的表格把 `editor_input_read` 的成员写成 `editor_get_input_map_actions`。该名字**不在**契约里
（`docs/tools_list.renamed.json` 无此条目），也不在 B2 manifest 里。manifest 与契约的唯一成员是
**`editor_get_input_actions`**（映射 `get_input_actions` → `editor_get_input_actions`）。
按「以 manifest 为准」实现 **`editor_get_input_actions`**，此处注明差异。

---

## 2. 两个进程输入的分野（D56 纪律）— 本批的核心

**结论一句话**：`running_game_input` 组的 4 个工具与 `running_game_node_write` 的 1 个工具**驱动/改写的是游戏进程**；
`editor_playback`(2) 与 `editor_input_read`(1) 作用于**编辑器进程自身**的播放控制与 `InputMap`。

| 工具 | scope | 作用对象 | 端点 | 驱动游戏的资格 |
|---|---|---|---|---|
| `running_game_create_input_recording` | game | **游戏进程**的 Input 事件流（模块自己的录制 Node 挂在游戏树根） | 9889 | —（观察游戏） |
| `running_game_stop_input_recording` | game | 同上，回传事件 | 9889 | —（观察游戏） |
| `running_game_play_input_recording` | game | **游戏进程**的 `Input::parse_input_event` | 9889 | ✅ **驱动游戏** |
| `running_game_simulate_button_click_by_text` | game | **游戏场景**里 Button 的 `pressed` 信号 | 9889 | ✅ **驱动游戏** |
| `running_game_set_node_property` | game | **游戏场景**节点属性 | 9889 | ✅ 改写游戏 |
| `editor_play_scene` / `editor_stop_scene` | editor | **编辑器**的播放控制（拉起/终止游戏子进程） | 9888 | 启动/停止，不注入输入 |
| `editor_get_input_actions` | editor | **编辑器进程**的 `InputMap` 单例 | 9888 | ❌ 读编辑器输入配置 |

**为什么这必须写清楚**：`editor_*` 输入类工具（`editor_simulate_key` / `editor_simulate_input_action` /
`editor_add_input_action` 等，属 `editor_input_simulation` 组，B3/B5）注入的是**编辑器进程自己的输入队列**——
编辑器不是游戏，注入进去也驱动不了游戏。映射对 `editor_get_input_actions` 的 `reason` 原文即
「读编辑器进程 InputMap 单例的 action 列表（不读 project.godot）」。

**端到端证据（门② `g02`，真实 `tools/list`，文件 `g01`）**：游戏端点 9889 的 40 条工具里
**一个 editor 侧输入/播放工具都没有**（检查的 9 个名字：`editor_play_scene`、`editor_stop_scene`、
`editor_get_input_actions`、`editor_simulate_*`(5)、`editor_add_input_action`），而本批 5 个 game-scope
工具**全部在**。反向半边在播放相 `p02`：编辑器端点 43 条工具里三个 editor 工具都在、且没有任何
`running_game_*input*` / `running_game_set_node_property`。

---

## 3. 逐工具表（可观察契约与差异）

「迁移源」= PLAYBOOK §1 指定的语义参照（`godot_mcp_gdext/src/commands/*.rs`、`addons/godot_mcp*/**`，**只读**）。
两处迁移源并不一致（`godot_mcp_gdext` + `mcp_runtime_agent.gd` 是"半成品"版，`mcp_game_inspector_service.gd` 是
"完整"版）；**分歧处一律采用完整版**并在下表最后列写明。

| new_name | 迁移源位置 | 可观察契约（as-built） | C++ 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `running_game_create_input_recording` | `runtime.rs:304`（IPC 转发）+ `mcp_runtime_agent.gd:292` / `mcp_game_inspector_service.gd:1482` | 无参数。在**游戏进程**里挂一个模块自有 Node 到树根并 `set_process_input(true)`，从此每帧的 `Input` 事件带毫秒偏移被采集 → `{"recording": true, "message": "Recording started"}`；已在录制 → `-32000` + suggestion（不静默丢弃上一次）；无 SceneTree → `-32000` | `tools/running_game_input.cpp:80-133`、`tools/input_recorder.*` | 迁移源靠 GDScript autoload 的 `_input`；模块无 autoload 可借，改用**自建 Node**。Node 覆写的是**普通 `Node::input()` 虚函数**而非 `_input` GDVIRTUAL（后者只经 ScriptInstance/GDExtension 解析），因此这个钩子不依赖 ClassDB |
| `running_game_stop_input_recording` | `runtime.rs:309` + 同上:299/1490 | 无参数。停止采集、释放录制 Node → `{"recording": false, "events": [...], "event_count": N, "duration_ms": <int>, "event_types": {"key":n,"mouse_button":n,"mouse_motion":n,"action":n,"other":n}}`；每个事件 `{"type": ..., "time_ms": <偏移>, ...}` 按采集顺序；不可回放的类别（触摸/手柄）计入 `other` 而**不静默丢弃**；本来没在录 → `{"recording": false, "events": [], "event_count": 0, ...}`（成功，迁移源同行为） | 同上:165-215 | ①事件一律经 `serialize_variant`，所以 Vector2 是 `{"x":..,"y":..}` 而非 `"(x, y)"`（见 §7 CR-2）；②`duration_ms` 与 `event_types` 是新增键（迁移源只有 `duration`/`count`，且 inspector 版用 `time_ms`、agent 版用秒为单位的 `time`） |
| `running_game_play_input_recording` | `runtime.rs:314` + `mcp_game_inspector_service.gd:1503` | `events`（数组，**契约定义必填**）、`speed`（number，默认 1.0，必须正且有限）。**跨帧**回放：按 `time_ms / speed` 的到达时刻逐帧 `Input::parse_input_event` → `{"replayed": true, "event_count": N, "injected": N, "speed": s}`；缺 `events` 时**回退到本游戏进程刚停止的那次录制**（往返免抄）；两个都没有 → `-32602`；`type` 非四类之一 → `-32602`（**在等待任何帧之前**，因此不会"回放一半才失败"）；框架上限到期 → `-32000` + suggestion + `timeout_ms`（任务自报 = `max(time_ms)/speed + 2s`，只能被框架夹紧） | `tools/running_game_input.cpp:245-575` | ①注册为 **deferred**（GDR-20）：回放的可观察行为就是时间线本身，单帧注入会把所有延迟塌成 0；②`time_ms` 优先、`time`（毫秒）作兼容回退——`mcp_runtime_agent.gd` 写 `time`（**秒**）却按毫秒读，其录制回放时所有延迟除以 1000，属被修正的迁移源缺陷；③**不**接受空数组（迁移源回 `{"error": "No events to replay"}` 的伪成功） |
| `running_game_simulate_button_click_by_text` | `runtime.rs:384` + `mcp_game_inspector_service.gd:985` | `text`（str，必填；空白 → `-32602`）、`partial`（bool，默认 true）。在**游戏当前场景**深度优先找可见 `Button`，文本两侧 `to_lower().strip_edges()` 后 `contains`/`==` → 发射 `pressed` → `{"clicked": true, "button_text", "button_path", "position": {"x","y"}}`；无当前场景 → `-32000`；找不到 → `-32001` + suggestion | 同上:600-690 | ①**立即返回、不 deferred**：发信号是同步的，其效果在同一帧就可观察；②按钮文本与路径在发射**之前**取好并在发射后回显——`pressed` 处理器可能换场景（迁移源 inspector 版已为此加注释修过，本版沿用其结论）；③可见性用 `is_visible_in_tree()` 而非仅本地 `visible` |
| `running_game_set_node_property` | `runtime.rs:240` + `mcp_game_inspector_service.gd:575` | `node_path`/`property`（str，必填；空白 → `-32602`）、`value`（**任意 JSON 类型，必填——"存在"而非"非 null"**）。按共享 `resolve_game_node` 解析节点，值经 `property_type_of` + `coerce_to_property_type` 落到属性类型 → `{"node_path": <解析后绝对路径>, "property", "old_value", "new_value"}`（`new_value` 是 `Object::set()` **之后回读**的，故 clamp/只读属性不会被伪报成功）；整数越界 → `-32602`；JSON 对象未给出目标类型的组件名 → `-32602`（见 §7 CR-1）；无当前场景 → `-32000`；节点不存在 → `-32001` | `tools/running_game_node_write.cpp:100-260` | ①复用模块唯一的 `property_type_of`/`coerce_to_property_type`（TASK-009/010 的语义），迁移源是自写的 `typeof(old)` 转换表——因此本版才有「越界 `1e20` → `-32602`」这条 TASK-010 语义；②`node_path` 回显**解析后的绝对路径**（PLAYBOOK §6.7），迁移源回显入参；③新增组件名映射与"缺组件即拒绝"（迁移源只对 Dictionary→Vector/Color 做手写转换，未给组件时会得到零向量） |
| `editor_play_scene` | `scene.rs:53/126` | `mode`（str，可选，默认 "main"）：`main` → `play_main_scene()`；`current` → `play_current_scene()`；其他一律当**项目场景路径**：先归一（非 `res://` / 含 `..` → `-32602`），再判存在（不存在 → `-32001`），**两次拒绝都发生在拉起播放之前** → `{"playing": true, "mode": <生效值>}`（自定义路径另带 `path`）；非编辑器进程 → `-32000` + suggestion | `tools/editor_playback.cpp:96-160` | 迁移源对"非 main/current 的任意字符串"只做 `FileAccess::file_exists`（绝对宿主路径也能过），本版只接受项目内路径 |
| `editor_stop_scene` | `scene.rs:58/142` | 无参数。没在播放 → `{"stopped": false, "message": "No scene playing"}`（成功）；在播放 → `stop_playing_scene()` 并**回读状态** → `{"stopped": <回读值>, "message": ...}`；非编辑器进程 → `-32000` | 同上:162-215 | 迁移源无条件回 `stopped: true`；本版回读 `is_playing_scene()`，让"子进程拒绝退出"这一唯一失败模式可被调用者察觉 |
| `editor_get_input_actions` | `input.rs:32/104` | 无参数。读**编辑器进程** `InputMap::get_singleton()` → `{"actions": [<String>,...], "count": N}`，**升序**。**无编辑器守卫**（读 InputMap 不需要 EditorInterface，单例在每个进程都存在）——它"属于编辑器"这一点由 `scope` 承担 | `tools/editor_input_read.cpp:70-115` | ①迁移源直接转发 `InputMap::get_actions()`；本版**排序**：该函数迭代 `HashMap`（`input_map.cpp:133-141`），顺序不属引擎契约（PLAYBOOK §6.8 要求确定化）；②不读 `project.godot`（映射 reason 明确） |

---

## 4. 门① 契约子集逐字（`check_contract_subset.ps1`，每组各跑两次）

```
===== running_game_input (run 1 & run 2 各一次) =====
group=running_game_input tools=4 contract=171
implemented_union=43 tools (editor endpoint) / 40 tools (game endpoint)
[PASS] editor_9888_contract_subset    (running_game_* 4 个 "correctly absent on the editor endpoint")
[PASS] game_9889_contract_subset      (4 个 name=True description=True inputSchema=True)
[PASS] guard_user_port_9877           pid_before=36392 pid_after=36392
3/3 checks passed                     (两次运行）

===== running_game_node_write =====
group=running_game_node_write tools=1 contract=171
[PASS] editor_9888_contract_subset    (running_game_set_node_property: correctly absent)
[PASS] game_9889_contract_subset      (name=True description=True inputSchema=True)
[PASS] guard_user_port_9877           pid_before=36392 pid_after=36392
3/3 checks passed（两次运行）

===== editor_playback =====
group=editor_playback tools=2 contract=171
[PASS] editor_9888_contract_subset    (editor_play_scene / editor_stop_scene 各 name=True description=True inputSchema=True)
[PASS] game_9889_contract_subset      (两个 "correctly absent on the game endpoint")
[PASS] guard_user_port_9877           pid_before=36392 pid_after=36392
3/3 checks passed（两次运行）

===== editor_input_read =====
group=editor_input_read tools=1 contract=171
[PASS] editor_9888_contract_subset    (editor_get_input_actions: name=True description=True inputSchema=True)
[PASS] game_9889_contract_subset      (correctly absent on the game endpoint)
[PASS] guard_user_port_9877           pid_before=36392 pid_after=36392
3/3 checks passed（两次运行）
```

共 8 次运行、**24/24 检查全过**，两次运行的 PASS 清单一致。逐条 `name`/`description`/`inputSchema` 由脚本内
`-ceq`（区分大小写）比较；「未实现却已注册」的工具为 0（脚本按已实现**并集**断言 extra/missing）。
新增工具的描述与 schema 全部由 `scripts/gen_b2_game_schema.py` 从契约**逐字节生成**（`--in-place` 连跑两次为
no-op，已验证），手工未誊写一个汉字。

---

## 5. 门② 三类证据（成功 / 缺参 / 底层失败）+ 活证据链

证据目录：`%TEMP%\mcp012-evidence\`（57 个 `.response.json`）。全部用
`curl.exe -s --max-time N -o <file> --data-binary @<body-file>`，响应体**从不经管道或 `Out-File`**；
每个文件落盘后由 `Get-FileHash` 算 sha256 并打印。请求体也用 `[IO.File]::WriteAllBytes` 落盘后由
`curl` 的 `@file` 读入（避免任何命令行引号问题）。

### 5.1 逐工具三类

| 工具 | 成功 | 缺参/类型错 → `-32602` | 底层失败 |
|---|---|---|---|
| `running_game_create_input_recording` | `g13` → `{"recording":true,"message":"Recording started"}` | `—`（契约无参数，无可缺） | **声明**：本类不可构造于正常路径——唯一"状态不允许"是**已在录制**，而本相要成功路径就必须录一次；该分支由 doctest 覆盖（`g13` 之前不构造第二次 create）。同理 `-32000`（无 SceneTree）在真实游戏进程里不可构造 |
| `running_game_stop_input_recording` | `g15`（4 个事件、`event_types` 四类各就位、`time_ms` 42/42/42/42） | `—`（无参数） | `g27`：本来没在录 → **成功** `{"recording":false,"event_count":0,"message":"No recording was running"}`（故本工具**无**失败形态，显式声明） |
| `running_game_play_input_recording` | `g19`（无参回退录制：`injected=4`、`speed=1.0`）/ `g22c`（显式数组）/ `g22d`（**跨帧 647 ms**） | `g21`（`type:"telepathy"`）、`g22_replay_empty_events`（空数组）、`g22b`（`speed:0`） | **声明**：其超时形态（框架上限到期 → `-32000` + `timeout_ms`）在线上需等 30 s 或构造超长录制；该形态由 TASK-011 的 GDR-20 门与 doctest 钉住，本工具只自报更紧的自有截止（`max(time_ms)/speed+2s`），不另起一套 |
| `running_game_simulate_button_click_by_text` | `g23` → `{"clicked":true,"button_path":"/root/Main/FireButton","button_text":"Fire Cannon"}` + `g24`（处理器真的跑了：`clicks 0→1`、`status_text="fired 1"`） | `g26`（`text:"   "`） | `g25`：`text:"Do Not Exist"` → `-32001` + `data.suggestion` |
| `running_game_set_node_property` | `g04`（`{"x":321,"y":123}` → `old_value=0,0` / `new_value=321,123`，第二次工具调用回读 `position=321,123`）、`g06`（标量 `rotation=0.75`）、`g07b`（**脚本变量** `status_text`） | `g09`（`z_index:1e20` → "outside the range of a 64-bit integer"）、`g10`（缺 `value`）、`g12`（缺 `node_path`）、**`g08`（对象未给组件名 → 拒绝，§7 CR-1）** | `g11`：`node_path:"ghost"` → `-32001` + suggestion |
| `editor_play_scene` | `p07` → `{"playing":true,"mode":"main"}` + `p08`（**游戏端点 9889 真的起来**） | `p05`（`res://../escape.tscn`） | `p06`：`res://scenes/nope.tscn` → `-32001` + suggestion |
| `editor_stop_scene` | `p11` → `{"stopped":true,"message":"Playback stopped"}` + `p12`（9889 真的没了） | `—`（无参数） | `p04`：没在播放 → **成功** `{"stopped":false,"message":"No scene playing"}`（故无失败形态，显式声明） |
| `editor_get_input_actions` | `p03` → `count=89`、升序 `true`、含 `ui_accept`、`count` 键与数组长度一致 | `—`（无参数） | **声明**：本工具无失败路径（无参、单例恒在、无 IO）；其"不可用"只可能是工具不存在于该端点，而那是 `p03b`/`g02` 的断言对象 |

### 5.2 跨工具的端到端活证据链（本批主链，全部真实请求）

```
[0] g00b  running_game_get_node_properties(Main.status_text)            -> "idle"
          （先证明游戏自带脚本真的加载了；脚本解析失败时下面所有计数器都会是 null）
[1] g13   running_game_create_input_recording()                        -> {"recording":true}
[2] g14   running_game_execute_gdscript(<GDScript 在游戏进程内构造并
          Input.parse_input_event 4 个事件>)                            -> result_type=Array
[3] g15   running_game_stop_input_recording()                          -> event_count=4
          event_types={"key":2,"mouse_button":1,"mouse_motion":1,"action":0,"other":0}
          每个事件带 time_ms；position 是 {"x":10.0,"y":20.0} 而不是字符串
[4] g16   running_game_get_node_properties(Main.key_events)            -> 游戏自己的 _input 计数 >= 2
[5] g19   running_game_play_input_recording()   （无参：回退到 [3] 的录制）
                                                                       -> {"replayed":true,"injected":4}
[6] g20   running_game_get_node_properties(Main.key_a_down / key_events / mouse_events)
                                                                       -> 三个计数全部上涨
[7] g22d  running_game_play_input_recording(两个事件相距 600 ms)        -> 647 ms 后 injected=2
[8] g23   running_game_simulate_button_click_by_text("Fire")           -> clicked=true, /root/Main/FireButton
[9] g24   running_game_get_node_properties(Main.clicks / status_text)  -> clicks 0->1, "fired 1"
```

每一步都是真实 HTTP 请求/响应文件（sha256 见 §8）。**[4] 与 [6]/[9] 是"驱动游戏"的判据**：计数
由**游戏自己的脚本**产出，不是工具自答。**[7] 是"真的跨帧等待"的判据**：600 ms 的偏移在
speed=1.0 下花掉 647 ms 实测墙钟。

**第 [0] 步不是装饰**：本相第一次运行（§9 勘误 1）因为 `instrumented_auth.gd` 用了 GDScript 里不存在的
`InputEvent.DEVICE_ID_INTERNAL` 而解析失败，结果 5 个检查同时读到 `null` 而"看起来像工具坏了"。
现在有一条专门断言脚本已加载的前置检查。

---

## 6. 播放相：进程级证据与无孤儿进程证明

### 6.1 端口前提（本批的一处重要事实）

`editor_play_scene` 经 `EditorInterface::play_*()` → `EditorRunBar::_run_scene()` → `EditorRun::run()`
（`editor/run/editor_run.cpp:51-190`）拉起**子进程**。**编辑器不会把自己的 `--mcp-port` 传给子进程**：
子进程的参数表里只有 `--path`、`--editor-pid`、`--remote-debug`、`--scene` 等（同文件 60-155 行），
它从**自己的项目设置** `godot_mcp/port` 读端口。因此本相用的 scratch 编辑器项目显式写了：

```
[godot_mcp]
port=9889
enabled_in_game=true
```

这不改任何契约，也不给"编辑器启动的游戏"另发明端口——它只是把被测项目配置成测试端口。报告显式记录该事实，
以免后人以为模块会替调用者挑端口。

### 6.2 播放/停止的进程级证据（真实输出）

```
editor pid=3100; its process tree before play: 3100,48132,5532
[p07] editor_play_scene {"mode":"main"} -> {"playing":true,"mode":"main"}
[status] port=9889 body: {"connections":1,"frame_count":19,"is_editor":false,
        "listening":true,"pending":0,"pending_connections":0,"port":9889,
        "server":"godot-mcp-rs","status":"ok","tools":40,"transport":"streamable-http"}
[PASS] p08 端口 9889 可连且 GET /mcp 回答 tools=40 is_editor=False listening=True
[PASS] p09 监听 9889 的 pid=33596 是编辑器（3100）的子进程；树 = 3100,48132,5532,33596
[PASS] p10 该子进程自报 is_editor=false（是游戏，不是又一个编辑器）
[p11] editor_stop_scene {} -> {"stopped":true,"message":"Playback stopped"}   （attempts=1）
[PASS] p12 停止后 9889 不可连
[PASS] p13 子进程 33596 alive=False，其自身子树（播放中为 []）停止后仍为 []
[PASS] p14 本脚本启动过的 pid（27624）全部已退出
[PASS] p15 netstat 9889 已无 LISTENING，且曾监听的那个 pid 已死
```

### 6.3 为什么 p13 用"子进程自己的子树"而不是"编辑器已无子进程"

编辑器会另起**自己**的辅助子进程（日志中 48132/5532 在**播放开始之前**就存在）。"编辑器没有子进程了"
是个**错误**的判据；本批要证明的是「`editor_play_scene` 拉起的那个游戏子进程及其子树不再存在」，
所以故意**先取游戏 child 的 pid，再取那棵子树**，并在 `p13` 同时断言子进程本体已死。

### 6.4 无孤儿进程（本批硬要求）

- 播放中：`Get-ProcessTree(editor)` 含游戏 child（pid 33596），child 自身子树为空；
- 停止后：child **本体 dead**、其子树**空**、9889 **无监听**；
- 脚本收敛：`StartedPids` 里每个 pid 在 `finally` 里被清理并在 `p14` 断言全部已退出；
- 每次都断言用户编辑器 pid **36392** 未变（`p16`、`g28`，以及两相所有门运行的前后守卫）。

---

## 7. 本相抓到的三个真缺陷（红→绿，全部是"活证据链抓到、doctest 抓不到"的形态）

### CR-1 `running_game_set_node_property`：JSON 对象组件名被静默写成零向量（**已修**）

第一次门②运行的真实响应：

```
request : {"node_path":"Main","property":"position","value":{"x":321,"y":123}}
response: {"new_value":{"x":0.0,"y":0.0}, "old_value":{"x":0.0,"y":0.0}, ...}
```

`property_value_from_json` 有意把 JSON 对象保持为 Dictionary（"retain the structure"），
而 `type_convert(Dictionary→Vector2)` 是**零向量**：工具**报成功**、属性静默变成 `(0,0)`。
这正是模块禁止的"假成功 + 静默错值"。

修法（迁移源 `mcp_game_inspector_service.gd:610-660` 的 `_parse_value_for_type` 就是干这个的）：
新增 `MCPTools::vector_from_dictionary()`（`tools/running_game_node_write.{h,cpp}`），在 coercion 之前
把 `{"x","y"}` 映射成 `Vector2/Vector2i`、`{"x","y","z"}` 成 `Vector3/Vector3i`、`{"r","g","b"[,"a"]}` 成 `Color`；
**映射不出来时返回 null**，工具据此回 `-32602` 而不是写零。

红阶段（把映射临时改成 pass-through，即"修前行为"，真实输出）：

```
TEST CASE: [MCPServer] a Dictionary value reaches a vector-shaped property without becoming the zero vector
.\modules\mcp_server\tests\test_mcp_server.h(5944): FATAL ERROR: REQUIRE( shaped.get_type() == Variant::VECTOR2 ) is NOT correct!
.\modules\mcp_server\tests\test_mcp_server.h(5945): ERROR: CHECK( (Vector2)shaped == Vector2(321.0f, 123.0f) ) is NOT correct!
.\modules\mcp_server\tests\test_mcp_server.h(5951): ERROR: CHECK( (Vector2)node->get("position") == Vector2(321.0f, 123.0f) ) is NOT correct!
.\modules\mcp_server\tests\test_mcp_server.h(5961): FATAL ERROR: REQUIRE( shaped.get_type() == Variant::VECTOR3 ) is NOT correct!
.\modules\mcp_server\tests\test_mcp_server.h(5962): ERROR: CHECK( (Vector3)shaped == Vector3(1.0f, 2.0f, 3.0f) ) is NOT correct!
[doctest] test cases:  1 | 0 passed | 1 failed | 1546 skipped
[doctest] assertions: 12 | 7 passed | 5 failed |
[doctest] Status: FAILURE!
```

绿阶段（恢复映射）+ 线上：`g04` → `new_value={"x":321.0,"y":123.0}`，第二次调用回读 `position=321,123`；
`g08` → 未给组件名时 `-32602`，属性保持 `321,123`；`g06` 标量 `rotation` 与 `g07b` **脚本变量**正常。

### CR-2 录制把 Vector2 写成字符串，导致"录完不能回放"（**已修**）

第一次运行 `g15` 的真实响应里：

```
"position":"(10.0, 20.0)", "relative":"(2.0, 4.0)"
```

裸 `Vector2` 放进 Dictionary 后，`JSON::stringify` 会把它变成**字符串**。于是
`running_game_stop_input_recording` 的答案**不能直接喂回** `running_game_play_input_recording`
（实测回放侧拒绝：`Parameter 'events[2].position' must be a Vector2 or an object with x/y, got String`）——
"录制/回放族"最基本的往返被自己破坏。

修法：`_encode_event` 对四个坐标/相对量走模块唯一的 `serialize_variant`（与属性读取同一规则），
得到 `{"x":..,"y":..}`。doctest 同步改成断言 Dictionary 形状（否则测的就不是线上形状）；
新增线上检查 `g15b` 断言 `position` 是对象。

### CR-3 第二次 stop 把上一次的事件又发一遍（**已修**）

第一次修法的中间版本在 stop 后清空快照，导致 ①`g27`（未在录制时 stop）从前一次会话拿到 4 个事件、
`message` 却是 "No recording was running"；或 ②清空后 `play_input_recording` 无参回退拿不到东西。
最终语义（两条都成立）：

- `take_events()` **只读**：录制结束后的快照一直保留到下一次 `start()`，所以 `play` 无参可用；
- stop 工具：`was_recording` 时才回传事件；否则回 `{"events": [], "event_count": 0}`，
  **不**把上一次的事件当成答案（`g27` 现在 `event_count=0`）。

同时 `running_game_play_input_recording` 增加"无参回退到刚停的录制"，使
`create → stop → play` 不需要在中间抄一遍事件（线上 `g19` 就是这条路径）。

---

## 8. 关键工件 sha256

引擎二进制（本次全部门与证据使用的构建）：
`a9223a26fc2730907129f6ff9d7ae5cc1415e682b861fae0db1b2af020111db8`
（`bin\godot.windows.editor.x86_64.console.exe`）

```
9d91c7c8407e77b2c53222250a31c51642a125a650216e4fbff5afe0b70a8439  tools/input_recorder.h
05edcdee62f00a0178544786c12fcc6f164334c11e3b9445bed60e13266c58fc  tools/input_recorder.cpp
b649378c52f15041704eee07f5dc95c3ac51b7e67306bc91a4ef4b3d0d5453c9  tools/running_game_input.h
94aa4c097a4c83438b673e3e4429fbb541641fba40573e9c9c76fb74fb961580  tools/running_game_input.cpp
79b2010d06784475994136e8b58ce66df1445599c6a27992f6b7d486988fd1c2  tools/running_game_node_write.h
d5aba910b6de540dc125f9d059f1421a258b6bb589080c4f319396a450cc9041  tools/running_game_node_write.cpp
281934bad6e253dc37957518aee576777cecc83e0d41eb50597d2ae8d9c024d4  tools/editor_playback.h
8b77b921c409a158f738e292d828edc29f47954dedd17903280c37aee04f0368  tools/editor_playback.cpp
84d7bddca581a9a2c70b783675c1d2f231aadc959817b1ba328cf23d1af20348  tools/editor_input_read.h
6c092451d58da3da2d9e57500da2f8abc34f85d6758eb386a561edcdfaa0ae5c  tools/editor_input_read.cpp
cd5ca700ba3e137eb48773dafa0ac31e460423b3f94fa1eacfaa6753c470892d  tools/registration.cpp
7ebafe48dccb2e08a756881146f25a50b0c895bab0078ed0e2f94adb57954591  register_types.cpp
5b63890c7eee5e3cc929558654943a54cdb560fba10934332ec687bfabe8cf79  tests/test_mcp_server.h
c1d4d2ce22ad10fb315a1c6d747dcd7053036848561db373cc549e5fbec7087a  scripts/gen_b2_game_schema.py
fcc04286092a228027ca2cfee578168837be7cbfebf478a19020efc7d46d4634  scripts/accept_m1.ps1
ea23f0a76f8c9be20eda37afab061dcecfbc4b0a609e8221f799fa8504318989  scripts/mcp012_input_playback_evidence.ps1
055ae63287e23c02d922d03f68864597dea145ce4caa5c8931ac322a270ba1ad  docs/tool-groups-b2.json
```

（`mcp012_input_playback_evidence.ps1` 的初版 sha256 是
`8928fc44bafecc808e302b4ec6328904fccb71fe21bef0f915510a5ccdb3803e`；上面的值含后来补入的
`g22d`「回放真的跨帧」检查——该检查是本报告 §5.2 第 [7] 步的证据来源，加它只**增加**检查数
（31 → 32），未改动任何断言。）

契约与映射**未被触碰**（B1/B2 三个文件 `git diff` 为空）：

```
0cfcac80f0d999fa7db713ae48f43febe96ae52e2c93633257eeed00ffdfbfac  docs/tool-groups.json        (B1，未改)
c4f913d65c3f3fd311d36ded44b473189cf886f098959fe7b6edf49b74901298  docs/tools_list.renamed.json (未改)
2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd  docs/tool-rename-map.json    (未改)
```

门②证据文件（`%TEMP%\mcp012-evidence\`，全 57 个，下为报告引用到的）：

| 检查 | 文件 | sha256 |
|---|---|---|
| `g01` 游戏端点 tools/list | `g01_tools_list_game_9889.response.json` | `c1ff9a4e98022b476cafaf22bc43fb2d2f26184c9c39ad99924708fe9e5e6a8b` |
| `g04` 属性写（前→后） | `g04_set_position.response.json` | `f386249cd8068746fbc96db5fcccf936734412ff1b4bd7aa0cc380a153c68e1e` |
| `g08` 未给组件名被拒 | `g08_set_non_component_dict.response.json` | `e1d267525ecf646c98c2fbea6fcffc0293179737cacdf07324797b889c312dde` |
| `g13` 开始录制 | `g13_recording_start.response.json` | `a5c5edd59199469e09322e76c6a20ceaf538fb327c41884fa3ddf22d8bf781aa` |
| `g15` 停止录制（事件+time_ms） | `g15_recording_stop.response.json` | `b8c148ac0d81c458855625a99a1c478ccb76b1d17a28394d89b0561738f4d589` |
| `g19` 回放（无参回退） | `g19_replay_recording.response.json` | `9c8b6cc43b96abdea6358c38c693b1db173c96e5ab51b618625659319ced8109` |
| `g22d` 回放真的跨帧（647 ms） | `g22d_replay_spans_frames.response.json` | `fdae7d7e4996cba6cd752f1a58b158d82a36a2f72c6c87ad6d89ddc4ad2d65ab` |
| `g23` 按钮点击 | `g23_click_button.response.json` | `a22f3d259d522bf7e10bea87295e1f5c928d737c3cee0523d65e899a1f672c59` |
| `g25` 按钮找不到 → -32001 | `g25_click_no_such_button.response.json` | `b8e2404b5983f16fd624c1a1317a358674ca9c60ed2ddf22719d4b7593fe5741` |
| `p02` 编辑器端点 tools/list | `p02_tools_list_editor_9888.response.json` | `12b117833ae44d86b813aa0c72f8b6b326eb3266ddbc9f249728289757111f69` |
| `p03` editor_get_input_actions | `p03_editor_get_input_actions.response.json` | `3179b3f5335855269a25e189df13cec0461f8c5eeb4c6f51756035163d0cd4b4` |
| `p04` 未播放时 stop | `p04_stop_when_idle.response.json` | `d676ddbc16d487bcf83e67743a604b52304a799e3d8921eac58f99f332f49f7f` |
| `p07` play_scene | `p07_play_scene_main.response.json` | `a1691514f4cb5f50ba66d774c1a15864b9f70526d6bc50242a8f9d49d855ca9a` |
| `p11` stop_scene | `p11_stop_scene_1.response.json` | `12f75a2c57e9b7083255b0498092279cd118e5481e4fbbef879b2e779bbc539a` |
| `status_9889` 游戏子进程状态 | `status_9889.response.json` | `0632579489a37c2ccbc67579ae55979f746f62ae30b0f095e226b1b07331867b` |

关键响应原文（逐字，来自上表文件）：

```
g04  {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"new_value\":{\"x\":321.0,\"y\":123.0},\"node_path\":\"/root/Main\",\"old_value\":{\"x\":0.0,\"y\":0.0},\"property\":\"position\"}","type":"text"}]}}
g08  {"error":{"code":-32602,"message":"Parameter 'value' sets 'position', which is a Vector2, so the object has to provide its components (\"x\" and \"y\")"},...}
g15  …{"duration_ms":62,"event_count":4,"event_types":{"action":0,"key":2,"mouse_button":1,"mouse_motion":1,"other":0},
      "events":[{"alt":false,…,"keycode":"A","…","time_ms":42,"type":"key"}, …,
                {"button":1,…,"position":{"x":10.0,"y":20.0},"pressed":true,"time_ms":42,"type":"mouse_button"}, …],…}
g19  {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"event_count\":4,\"injected\":4,\"replayed\":true,\"speed\":1.0}","type":"text"}]}}
g23  {"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"{\"button_path\":\"/root/Main/FireButton\",\"button_text\":\"Fire Cannon\",\"clicked\":true,\"position\":{…}}","type":"text"}]}}
status_9889 {"connections":1,"frame_count":19,"is_editor":false,"listening":true,"pending":0,"pending_connections":0,"port":9889,"server":"godot-mcp-rs","status":"ok","tools":40,"transport":"streamable-http"}
```

---

## 9. 门③/④/⑤ 真实输出与退出码

### 门③ 模块 doctest

```
[doctest] test cases:  118 |  118 passed | 0 failed | 1429 skipped
[doctest] assertions: 3288 | 3288 passed | 0 failed
[doctest] Status: SUCCESS!        (exit 0)
```

（门③基线：TASK-011 的 112/2911 → 现在 **118/3288**，只增不减：+6 用例 / +377 断言。）

新增 6 个用例（全部 `[MCPServer]` 前缀）：

| 用例 | 覆盖 |
|---|---|
| `the TASK-012 game groups are game-only and the editor groups are editor-only` | 8 个工具的 scope/可见性/deferred 归属；`call_tool` 对 deferred 回 `-32603` |
| `a Dictionary value reaches a vector-shaped property without becoming the zero vector` | **CR-1** 的引擎级证明（含修前零向量的显式断言 + 组件映射 + 非向量类型的透传） |
| `the replay tool validates every event before it waits for a frame` | 全部 `-32602` 分支（逐字段）、`speed` 的正/有限、**无参回退到录制**、任务自报 2010 ms / 2030 ms |
| `the input recording round trip keeps the time line and the event classes` | 录制状态机：五类事件、`time_ms` 偏移、`serialize_variant` 后的 `{"x","y"}`、`event_types` 计数、二次 `start()` 丢弃旧会话、`empty_type_counts()` 形状 |
| `the recorder node overrides the plain input virtual, not the script one` | 录制的挂钩点（普通虚函数）+ engine-internal 回声被过滤 |
| `the game-side write and the editor-side InputMap read answer their contract` | 三个参数校验 + 无场景 `-32000`；editor 表与 game 表的可见性；`editor_play_scene` 的路径/类型拒绝 |

### 门④ 全引擎回归

```
[doctest] test cases:   1544 |   1544 passed | 0 failed | 3 skipped
[doctest] assertions: 427570 | 427570 passed | 0 failed
[doctest] Status: SUCCESS!        (exit 0)
```

（基线 1538/427192 → **+6 用例 / +378 断言，0 failed**。）

### 门⑤ `accept_m1.ps1` 连跑两次

```
runA: 22/22 cases passed   (exit 0)
runB: 22/22 cases passed   (exit 0)
diff(runA 的 PASS 清单, runB 的 PASS 清单) = 空（IDENTICAL，各 22 行）
implemented tools = 43 (editor endpoint) / 40 (game endpoint); contract = 171
```

`$ToolNames` 只追加 8 个名字（未削弱任何断言）：5 个 game-scope 使 `$GameToolNames` 增长、3 个 editor-scope
使 `$EditorToolNames` 增长，派生量（editor-only / game-only / process split / `gate_scope_declared`）自动跟随映射。

---

## 10. deviations / blockers / 勘误 / next_step_recommendation

### deviations（与手册/任务书的偏离，逐条显式）

1. **`editor_input_read` 的成员是 `editor_get_input_actions`**，不是任务书表格里的
   `editor_get_input_map_actions`（后者不在契约与 manifest 里）。规则是「以 manifest 为准」，已实现前者（§1.1）。
2. **`running_game_play_input_recording` 注册为 deferred 工具**（第一个"写"型 deferred 工具）。
   任务书未明说，但它的可观察行为就是时间线；manifest 的 `frame_clock_axis` 注释也把
   `play_input_recording` 列为 frame-clock bound。
3. **`running_game_play_input_recording` 的 `events` 可以由缺省回退到"本进程刚停止的录制"**。
   契约里 `events` 是 `required`，本实现把它放宽为"可缺省，但缺省时必须有可用录制，否则 `-32602`"。
   理由：`create → stop → play` 是本族的主用法，强制抄回事件既无益又易错（并直接暴露了 CR-2 那类往返缺陷）。
   若决策者认为必须严格 `required`，这是一行即可回退的决定。
4. **新增录制设施 `tools/input_recorder.{h,cpp}`，并在 `register_types.cpp` 里注册
   `MCPInputRecorderNode`。** 迁移源靠 GDScript autoload 的 `_input` 采集；模块内没有 autoload 可借。
   Node 覆写的是**普通 `Node::input()`**（`scene/main/node.cpp:3613` 无条件调用它），而不是 `_input`
   GDVIRTUAL——后者只经 `ScriptInstance`/GDExtension 解析（`core/object/gdvirtual.gen.h`），
   引擎内的 C++ 子类永远收不到。这个选择让钩子不依赖 ClassDB，也让状态机可以在 doctest 进程里被直接驱动
   （`Main::test_entrypoint()` 跑在模块初始化级别**之前**）。
5. **`vector_from_dictionary` 声明在 `tools/running_game_node_write.h`**（而非留作 .cpp 的 file-private）。
   唯一理由：doctest 必须断言**真函数**而不是副本，而 CR-1 是"静默错值"——只有直接断言钉得住。
6. **录制的事件与属性读取共用 `serialize_variant`**，因此 Vector2 一律是 `{"x":..,"y":..}`（CR-2）。
   迁移源是字符串化。
7. **`running_game_stop_input_recording` 新增 `event_types` 与 `duration_ms` 两个键**（answer 是超集）。
8. **`editor_get_input_actions` 的 `actions` 升序**（PLAYBOOK §6.8 对 `HashMap` 迭代序的确定化）。
9. **`editor_stop_scene` 回读 `is_playing_scene()`**，故"子进程拒绝退出"会以 `stopped:false` 显现，
   而非迁移源的无条件 `stopped:true`。
10. **`editor_play_scene` 的 `mode` 走 `normalize_project_path`**（只接受项目内路径），
    迁移源接受任意绝对路径。
11. **`accept_m1.ps1` 的 `$ToolNames` 追加 8 个名字**（未削弱断言）。
12. **`docs/tool-groups-b2.json` 四组的 `implemented` 翻为 true 并更新 notes**（manifest 是数据文件；
    B1 的 `tool-groups.json` 未动）。
13. **门②脚本 `scripts/mcp012_input_playback_evidence.ps1` 是本批新增**（手册 §3 门②的实现载体）。
14. **`running_game_simulate_button_click_by_text` 保持立即返回**（不 deferred）。理由：发信号是同步的，
    其效果同帧可观察；manifest 明确 "start/stop are not [frame-clock bound]" 那一族不包含它。

### blockers

- **无阻塞。** 两条**引擎事实**被显式登记而非绕过：
  1. **编辑器不把 `--mcp-port` 传给 `editor_play_scene` 拉起的子进程**（`editor_run.cpp` 的参数构造里没有端口）。
     测试项目因此写 `godot_mcp/port=9889`；模块不给"它启动的游戏"发明端口（§6.1）。
  2. **编辑器会另起自己的辅助子进程**（播放前就存在）。"编辑器无子进程"不是无孤儿的判据，
     本批改为按游戏 child 的 pid 追踪其子树（§6.3）。

### 勘误（append-only，允许且鼓励）

1. **`instrumented_auth.gd` 第一版用了 GDScript 不存在的 `InputEvent.DEVICE_ID_INTERNAL`**（该常量只在
   `core/input/input_event.h` 里有，未 BIND，`DEVICE_ID_EMULATION` 才 BIND）。游戏随之
   `Parse Error` + `Failed to load script`，于是 5 个检查同时读到 `null`（看起来像工具全坏）。
   修法：改用 `DEVICE_ID_EMULATION`，并**新增 `g00b` 前置检查**专门断言游戏脚本确已加载。
   这是"证据挂了先怀疑证据，而不是先怀疑被测物"的一次实例。
2. **门②脚本第一版的 JSON 由字符串拼接构造**：录制里含引号的坐标值被内联进请求体后破坏 JSON，
   表现为 `-32700`/`-32602`——一种**看起来像被测工具的宿主缺陷**。修法：所有请求体一律
   `ConvertTo-Json` 生成（`Format-CallBody`），数值/字符串比较也改成数值比较（`0.0` vs `0` 的字符串比较
   曾让 `g03` 误报）。
3. **`mcp_deferred.cpp` 的那次编译错误是构建竞态的残留**：我在一次 `scons ... > /dev/null` 里抑制了输出，
   而 SCons 的 `CommandNoCache` 生成 `modules_tests.gen.h` 失败导致该次构建**没有真正进行**；
   日志里的 `mcp_deferred.cpp(100) error C2440` 出现在「首轮编译到一半被中断」的那次运行中，
   同一文件在后续完整构建里零错误。**这不是本批引入的缺陷**，此处登记以免被误读为隐瞒。
4. **门②的游戏相前三次运行不足以作为证据**（`g03/g04/g08/g15/g19/g20` 失败），原因是 CR-1/CR-2/CR-3
   三个**真缺陷**加上勘误 1/2 的两个**宿主问题**。三处代码修完后游戏相 32/32、播放相 18/18；
   上面 §7 保留了红阶段的真实输出，未删除任何失败记录。

### next_step_recommendation

1. **`editor_input_simulation`（6 个工具，B2 剩下的唯一一组）可以直接照本批的 editor 侧写法做**：
   `editor_playback`/`editor_input_read` 已经把「editor-scope 工具如何声明、如何拒绝非编辑器进程、
   如何在端点维度上缺席于 9889」走通；那 6 个工具只需要 `Input.parse_input_event`/`InputMap` 的写侧逻辑
   与 `editor_add_input_action` 的原子写策略。
2. **建议决策者把「D56 边界」写进 DESIGN-DETAIL 的输入章节**（本报告 §2 只是把映射裁定与实测复述）。
   特别是：`editor_*` 输入工具**永远**不能用来驱动游戏，而 `running_game_*` 输入工具**必须**在
   game endpoint 上——这条现在有双向 wire 证据。
3. **`running_game_play_input_recording` 的"无参回退录制"值得决策者确认**（deviation 3）。
   它是本批最方便的一条用法，也是契约 `required` 的一处放宽。
4. **可选加固**：录制目前无长度上限（事件数与单次录制时长都不设限）。长时间录制会持续持有
   `Ref<InputEvent>`。若要防呆，可在 `MCPInputRecording::capture()` 加一个上限（例如 10 万事件）
   并在 `stop` 答案里如实回报被截断的数量——形态与本模块其它工具的"上限 + 如实回报"一致。
5. **B5 的录制族可直接复用 `tools/input_recorder.*`**：状态机与 Node 已经分离，落在 `stop` 答案里的
   事件形状也已与回放工具对齐（可直接串起 `record → save → load → replay`）。
