# REPORT-013 — B2 收官：`editor_input_simulation`（6 个工具）+ 录制上限 + GDR-21 边界实测

任务书：`modules/mcp_server/docs/tasks/TASK-013-b2-closure-editor-input-simulation.md`
通用规范：`modules/mcp_server/docs/tasks/PLAYBOOK-group-port.md`（已完整阅读）
执行者：Godot 内置 MCP 模块实现工程师（TASK-013）
分支：`feature/mcp-server-module`（**未推送**，遵守「禁止 push」）

## 0. 状态摘要

**commits**：

```
c4db56fa40  mcp_server: B2's last group, editor_input_simulation, plus the recording caps (TASK-013)
            11 个文件、+3003/−21
            + tools/editor_input_simulation.{h,cpp}        （6 工具，含 1 个 deferred）
            + scripts/mcp013_editor_input_evidence.ps1      （门②脚本，3 个 phase）
            ~ tools/input_recorder.{h,cpp}                  （事件数/时长双上限 + 截断报告）
            ~ tools/running_game_input.cpp                  （stop 答案加 truncated/dropped/limits）
            ~ tools/registration.cpp / scripts/gen_b2_game_schema.py
            ~ tests/test_mcp_server.h（+4 用例 / +330 断言，另 3 处旧计数 60→66、43→49）
            ~ scripts/accept_m1.ps1 / docs/tool-groups-b2.json
```

本报告自身的提交（仅新增本文件，不含任何代码/门改动）以
`git log -- modules/mcp_server/docs/reports/REPORT-013-*.md` 为准。

| 项 | 结果 |
|---|---|
| `status` | **完成**：6 个工具移植完毕；录制双上限落地；五道门全绿；GDR-21 边界与截断均有线上实测证据 |
| 实现的工具数 | 6（一组），已实现并集 60 → **66** |
| 端点 | 编辑器 9888 = 49，游戏 9889 = 40（编辑器侧 +6，游戏侧不变） |
| 门① 契约子集逐字 | `-Group editor_input_simulation` **连跑两次**各 **3/3 PASS**；6 工具在 9888 逐字 True、在 9889 **correctly absent** |
| 门② 三类证据 | 三个 phase：`boundary` **24/24**、`limits` **11/11**、`negatives` **15/15** PASS（共 50 项检查，全部真实请求/响应） |
| 门③ 模块 doctest | `[MCPServer]*`：**122/122 用例、3618/3618 断言全绿** |
| 门④ 全引擎回归 | `--headless --test`：**1548/1548 用例、427900/427900 断言，0 failed** |
| 门⑤ `accept_m1.ps1` ×2 | 两次各 **22/22 PASS**，两次 PASS 清单 `Compare-Object` 为 **空（IDENTICAL）** |
| B2 收官 | `check_tool_groups.py --batch B2`：**25/25**、9 组 `implemented=true` 共 **25** 工具 → **B2 = 25/25** |
| 9877 纪律 | 每个 phase 各有一条正 pid 守卫（`b28` = 36392/36392、`l_events_08`/`l_duration_08` = 36392/36392、`n11` = 36392/36392），门① 另有 `guard_user_port_9877`、门⑤ 另有 `guard_user_port_9877` —— 全部通过 |
| 契约/映射 | `tools_list.renamed.json` / `tool-rename-map.json` / `tool-groups.json` 三个 sha256 与 TASK-012 完全相同（**未触碰**） |

---

## 1. 组与端点（机器可见的计数）

| 项 | 值 |
|---|---|
| 新实现组 | `editor_input_simulation`（6 工具，`channel=editor` / `scope=editor` / `mutating=true`） |
| 已实现并集 | 60 → **66**（editor-scope 20 → 26；game-scope 17 不变；both 23 不变） |
| 编辑器端点 9888 | 43 → **49**（= 66 − 17 个 game-scope） |
| 游戏端点 9889 | **40**（不变 = 66 − 26 个 editor-scope） |
| `tools/list` 顺序 | 6 个新工具追加在既有顺序之后（`editor_simulate_input_action > editor_simulate_key > editor_simulate_mouse_click > editor_simulate_mouse_move > editor_simulate_input_sequence > editor_add_input_action`），同一次构建内确定性不变（门⑤ case20 跨进程重启仍逐字节相同） |
| 编辑器进程工具表 | `TestMCPServer::build_editor_process_registry()`：`get_tool_count()` 60 → **66**、`get_visible_tool_count(true)` 43 → **49** |

三个旧用例里的「编辑器进程表」计数随本批 +6（`test_mcp_server.h` 三处：`editor_read_scene_inspector` /
`editor_write_scene_editor` / `running_game_read_scene`），并同步更新了它们说明「23 both + 7 inspector + 10 write
+ 17 game + 3 editor + 6 editor」的注释。**没有任何断言被削弱**：改动只是把不变式里的数字随实现集合推进一步。

**契约/映射未被触碰**（`git diff --stat` 对三个文件为空，sha256 与 TASK-012 报告逐字相同）：

```
c4f913d65c3f3fd311d36ded44b473189cf886f098959fe7b6edf49b74901298  docs/tools_list.renamed.json (未改)
2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd  docs/tool-rename-map.json    (未改)
0cfcac80f0d999fa7db713ae48f43febe96ae52e2c93633257eeed00ffdfbfac  docs/tool-groups.json        (未改)
```

---

## 2. D59 / GDR-21 边界的本组实测对照（编辑器变化 vs 游戏无变化）— **本组最有价值的证据**

任务书 §1.2 要求本组「自己再给一组」证据：**编辑器侧注入后编辑器输入状态变化，而同一动作对游戏端点没有任何影响**。
本组用一个**同项目、双进程**的对照把它钉在实测上：

* **游戏进程（9889）**：项目脚本 `res://instrumented_auth.gd` 自己数它收到的 `InputEventKey`/`MouseButton`/`MouseMotion`；
* **编辑器进程（9888）**：项目的 **`EditorPlugin`** `res://addons/mcp013_probe/plugin.gd` 自己在 `_input()` 里数
  **编辑器进程**收到的事件，并写入 `user://mcp013_editor_input_probe.txt`。
  （`EditorPlugin` 是编辑器进程唯一会加载的项目内容——autoload 是游戏运行时特性，编辑器不实例化它；插件由
  `EditorNode` 在启动时加载，`set_process_input(true)` 之后与模块自己的录制 Node 走同一条
  `Viewport::push_input → _call_input_pause(input_group, …)` 路径。）

### 2.1 真实读数（`-Phase boundary`，**连跑两次**各 24/24 PASS）

下面每一条都是 `[PASS]` 行的原文（`%TEMP%\mcp013_boundary_rerun.log`）。**两次运行的读数完全一致**，
且 §2.2 列出的 12 个响应文件的 sha256 在两次运行之间**逐字节相同**（第二次运行没有改变任何一个响应体）——
这不是「跑一次看起来对」，而是可复现。

```
baselines: game keys=0 mouse=0 motion=0; editor {"action":0,"key":0,"mouse_button":0,"mouse_motion":0,"other":0}

[b06_editor_simulate_key]  {"keycode":"A","pressed":true}            (9888)
  -> {"alt":false,"ctrl":false,"keycode":"A","pressed":true,"shift":false,"simulated":"key","target":"editor"}
[PASS] b07 :: the editor process own EditorPlugin counted key=1 event(s) in its _input after the injection (was 0)
        ← 编辑器侧**真的变了**
[PASS] b08 :: the game own key_events counter is 0 (baseline 0) while the same key moved the editor:
               the editor input queue is not the game one (GDR-21)
        ← 同一动作对游戏**没有任何影响**

[b09..b12] editor_simulate_mouse_click / editor_simulate_mouse_move /
           editor_add_input_action / editor_simulate_input_action      (9888)
[PASS] b09 :: click={"button":1,"position":{"x":5.0,"y":6.0},"pressed":true,"simulated":"click","target":"editor"}
              move={"position":{"x":9.0,"y":10.0},"simulated":"mousemove","target":"editor"}
[PASS] b10 :: answer={"action":"mcp013_probe_action","created":true,"event_count":1,"key":"F9",
                      "persisted":false,"target":"editor"} (the editor InputMap was written, ProjectSettings was not)
[PASS] b11 :: answer={"action":"mcp013_probe_action","in_input_map":true,"pressed":true,
                      "simulated":"action","strength":1.0,"target":"editor"}
[PASS] b12 :: the editor process own counters: mouse_button=1 mouse_motion=1 action=1 (key=1)
[PASS] b15 :: the game own counters are still mouse_events=0 motion_events=0 (baselines 0/0)
              while the editor counted its own copies            ← 仍然没有任何影响

[PASS] b16 :: editor_get_input_actions on 9888 lists mcp013_probe_action=True (count=90)
[PASS] b17 :: the game process own InputMap.has_action("mcp013_probe_action") = False:
              editor_add_input_action wrote the editor singleton, which is not the game one

[b18/b19] **对照（防止「不变」是死计数器）**：在**游戏进程内**用
          running_game_execute_gdscript + Input.parse_input_event 注入同一个按键
[PASS] b19 :: the same key injected *inside* the game moved its own counter 0 -> 1:
              the unchanged readings above are measurements, not a dead counter

[PASS] b20 :: answer={"event_count":3,"frame_delay":1,"sent":true,"simulated":"sequence",
                      "target":"editor","time_ms_ignored":false} after 68 ms
              (it answers through the GDR-20 deferred channel, one event per frame)
[PASS] b21 :: the editor process own key counter went 1 -> 2 across the sequence
[PASS] b22 :: the game own key counter is still 1 (it was 1 after the control injection)
              after a whole editor-side sequence                    ← 整条序列也没到游戏

[PASS] b23 :: code=-32601 message=Method not found: editor_simulate_key
[PASS] b24 :: editor endpoint 9888 has tools=49, missing=[]
[PASS] b25 :: game endpoint 9889 has tools=40, leaked=[];
              the difference between the two listings is exactly the editor-scope set
[PASS] b26 :: a session with no cap configured reports truncated=False dropped=0
              limits={"max_duration_ms":600000,"max_events":100000}
```

**结论（一句话）**：`editor_*` 输入工具注入的是**编辑器进程自己的 `Input` / `InputMap`**，它能被编辑器进程内的
观察者看到（`EditorPlugin._input`、`editor_get_input_actions`），却**永远驱动不了游戏**——游戏进程的计数器在
同一轮运行里一动不动，而同一个按键只要在**游戏进程内**注入就会让它动。这就是 E3 根因的实测形态，
也是 TASK-012 双向证据之外的**第二条独立证据链**（不同工具、不同观察者、同一结论）。

### 2.2 证据文件 sha256（`%TEMP%\mcp013-evidence\`，共 52 个 `.response.json`）

下表的 sha256 在**两次** `boundary` 运行之间逐字节相同（第二次运行后重新计算，全部 `SAME`）。

| 检查 | 文件 | sha256 |
|---|---|---|
| b06 编辑器注入按键 | `b06_editor_simulate_key.response.json` | `eb72f7d35441a21603dad6716ec7b02a50ff60286bbdec8996d8059e69abc3be` |
| b08 游戏按键计数（不变） | `b08_game_keys_after_editor_key.response.json` | `82f582e3036cf8fe3dca2e3695b814247146e8d0ec9011d3694833676c93fafb` |
| b12 编辑器注入 action | `b12_editor_simulate_input_action.response.json` | `bf6fd9e61cb2808b7b54a9180cdf8d6559750f08bfbce79e01c8c2f0df35bf24` |
| b13 游戏鼠标计数（不变） | `b13_game_mouse_after_editor_mouse.response.json` | `e606cfdb39d0cf30139811a692b14dff30054480228bf3f8b74a9195291d6dad` |
| b16 编辑器 InputMap 读取 | `b16_editor_get_input_actions.response.json` | `76a678e97b47cee244e2c145fb29c9a8eee40324939842e4649f2840a2a0a93f` |
| b17 游戏 InputMap 探测 | `b17_game_inputmap_probe.response.json` | `49b7dde3fb8f38bb8a6a6acda4a61cc875c89ba0263f2caf89e985959683315d` |
| b19 对照：游戏内注入后计数=1 | `b19_game_keys_after_control.response.json` | `a9e774566f468850f98d37998343306547a0588010adb511ac244100ea49c9a0` |
| b20 编辑器序列 | `b20_editor_simulate_input_sequence.response.json` | `396bfb4afd089fbc7c49d943fc97b24870a3321669652070edfbe5920dffbcb1` |
| b22 序列后游戏计数（仍=1） | `b22_game_keys_after_sequence.response.json` | `a9e774566f468850f98d37998343306547a0588010adb511ac244100ea49c9a0` |
| b23 9889 上 -32601 | `b23_game_endpoint_refuses_editor_simulate_key.response.json` | `71ffb6e8f4684ec2f0c909047218e2e430c310b3978154d6e594a8cb06df4bf4` |
| b24 编辑器 tools/list | `b24_tools_list_editor_9888.response.json` | `bae263d970cbbe6a43b11d3a536af5f140355552f3fa6f05f13beba346a29f11` |
| b25 游戏 tools/list | `b25_tools_list_game_9889.response.json` | `c1ff9a4e98022b476cafaf22bc43fb2d2f26184c9c39ad99924708fe9e5e6a8b` |

（`b25` 的 sha256 与 TASK-012 报告里同一端点 `tools/list` 的值**逐字相同**：游戏端点在本批**一个工具都没变**。）

---

## 3. 逐工具表（可观察契约与差异）

「迁移源」= PLAYBOOK §1 指定的语义参照（`godot_mcp_gdext/src/commands/input.rs`、`addons/godot_mcp/commands/input_commands.gd`、`addons/godot_mcp/mcp_input_service.gd`，**只读**）。
两个迁移源并不一致：`input.rs` 把事件 `parse_input_event` 进**当前进程**，`addons` 版把它写进
`user://mcp_input_commands` 交给游戏侧服务读取。**映射（`tool-rename-map.json` / `reason`）裁决的是前者**
（"input.rs 只把编辑器进程的 Input 事件 parse_input_event，从不 send_game_command"），本实现与映射一致。

| new_name | 迁移源位置 | 可观察契约（as-built） | C++ 落点 | 与迁移源的差异 |
|---|---|---|---|---|
| `editor_simulate_input_action` | `input.rs:29/94` | `action`（str，必填、非空白）、`pressed`（bool，默认 true）、`strength`（number，默认 1.0，须有限）。注入 `InputEventAction` 到**本（编辑器）进程** → `{"simulated":"action","target":"editor","action","pressed","strength","in_input_map"}`；`strength` 回读引擎 **clamp 到 [0,1]** 后的值 | `editor_input_simulation.cpp:430-493` | ①新增 `target:"editor"`（答案自述作用于哪个进程，GDR-21）；②新增 `in_input_map`：动作不在本进程 InputMap 时事件仍投递（`_input` 听得到）但不会动 `Input` 的 action 状态，调用者不必猜；③`strength` 回读 clamp 值而非请求值 |
| `editor_simulate_key` | `input.rs:13/60` | `keycode`（str，必填）经 `find_keycode()` 解析，额外接受 GDScript 拼法 `KEY_*`；空/未知名 → `-32602`。`pressed`/`shift`/`ctrl`/`alt`（bool，默认 true/false/false/false）→ 注入一个 `InputEventKey` → `{"simulated":"key","target":"editor","keycode":"<解析后拼法>","pressed","shift","ctrl","alt"}` | 同上:287-340 | ①**未知名拒绝**：迁移源注入 `KEY_NONE`（一次什么都看不出的按键），按「工具真的能用」改为 `-32602`；②接受 `KEY_A`（`addons` 版的写法）；③回显解析后的拼法而非入参文本 |
| `editor_simulate_mouse_click` | `input.rs:20/73` | `button`（int，默认 1=LEFT）**必须落在 1..9**；`pressed`（bool，默认 true）、`x`/`y`（number，默认 0）→ 注入**一个** `InputEventMouseButton`（`position` 与 `global_position` 都设）→ `{"simulated":"click","target":"editor","button","pressed","position":{"x","y"}}` | 同上:342-386 | ①button 范围校验：`_parse_input_event_impl` 用 `1 << (button-1)` 算 button mask，未校验的 `button:99` 是**引擎内 UB**（不是口味问题）；②`addons` 版的 press+release（`auto_release`）**不复刻**：该参数不在契约里，且契约自己的 `pressed` 就是让调用者决定要不要 release（映射裁决的 `input.rs` 也只发一个事件）；③两个 position 都设（见 §7 CR-4） |
| `editor_simulate_mouse_move` | `input.rs:26/85` | `x`/`y`（number，默认 0）→ 一个 `InputEventMouseMotion`（`position`+`global_position`，`relative` 为 0）→ `{"simulated":"mousemove","target":"editor","position":{...}}` | 同上:388-428 | 同 ①③。`relative`/`button_mask` 不在契约里，故单工具不提供；**序列**工具按事件支持（录制回放需要，见下） |
| `editor_simulate_input_sequence` | `input.rs:39/128` | `events`（array，必填非空）：每元素 `type` ∈ `key` / `mouse_click`\|`mouse_button` / `mouse_move`\|`mouse_motion` / `action`（**两套拼法都收**，因为录制设施输出的正是第二套）；`frame_delay`（int，默认 1）= 事件之间相隔的**帧数**，`<=0` = 全部在同一帧（迁移源的 `frame_delay<=0` 分支）。**全部参数在任何事件被构造之前校验完**；**deferred**（GDR-20）：一帧注入一个 → `{"simulated":"sequence","target":"editor","sent":true,"event_count":N,"frame_delay":d,"time_ms_ignored":<bool>}` | 同上:538-957（`EditorSequenceTask` 在 840） | ①迁移源对未知 `type` **静默跳过**，本版 `-32602`；②接受 `mouse_button`/`mouse_motion`（录制输出）并支持 `position`/`relative`/`button_mask`；③`time_ms` **被忽略**（pacing 是 `frame_delay`）但**在答案里显式标注** `time_ms_ignored`，不做静默忽略；④第一个事件比迁移源晚一帧落地（deferred 通道**从不**在到达帧 tick，设计如此，`mcp_deferred.h`） |
| `editor_add_input_action` | `input.rs:35/113` | `action`（str，必填非空白，不存在则 `add_action`）、`key`（str，可选，同一套键名规则，绑定 `action_add_event`）→ 写**本（编辑器）进程** `InputMap` 单例（**不落盘 ProjectSettings**）→ `{"action","target":"editor","created":<bool>,"key":<解析后或"">,"event_count":<回读>,"persisted":false}` | 同上:495-536 | ①新增 `persisted:false`（明确「没有改 project.godot」，任务书 §1.3）；②`event_count` **回读**：引擎 `InputMap` 会去重同一事件（`_find_event`，input_map.cpp:205），所以同键二次调用仍然是 1（迁移源不回读）；③`created` 由回读得出 |

**关于迁移源的落盘行为（任务书 §1.3 要求显式判定）**：两个迁移源**都不落盘**——
`input.rs:113-124` 只调 `InputMap::add_action` / `action_add_event`；`addons/godot_mcp/commands/input_commands.gd`
里也没有任何 `ProjectSettings` 写入（它写的是 `user://mcp_input_commands`，那是给游戏侧的 IPC，不是项目设置）。
因此本实现与迁移源**一致**（不落盘），并把这件事写进答案的 `persisted:false` 与 §3 逐工具表。

---

## 4. 门① 契约子集逐字（`check_contract_subset.ps1 -Group editor_input_simulation`，连跑两次）

```
===== RUN 1 =====
group       : editor_input_simulation
tools       : editor_simulate_input_action, editor_simulate_key, editor_simulate_mouse_click,
              editor_simulate_mouse_move, editor_simulate_input_sequence, editor_add_input_action
implemented : 66 tool(s) across the groups marked implemented: …
editor set  : 49 tool(s)
game set    : 40 tool(s)
[PASS] editor_9888_contract_subset
       editor port=9888 tools=49 order=… editor_play_scene > editor_stop_scene > editor_get_input_actions >
       editor_simulate_input_action > editor_simulate_key > editor_simulate_mouse_click >
       editor_simulate_mouse_move > editor_simulate_input_sequence > editor_add_input_action |
       editor_simulate_input_action: name=True description=True inputSchema=True |
       editor_simulate_key: name=True description=True inputSchema=True |
       editor_simulate_mouse_click: name=True description=True inputSchema=True |
       editor_simulate_mouse_move: name=True description=True inputSchema=True |
       editor_simulate_input_sequence: name=True description=True inputSchema=True |
       editor_add_input_action: name=True description=True inputSchema=True
[PASS] game_9889_contract_subset
       game port=9889 tools=40 … |
       editor_simulate_input_action: correctly absent on the game endpoint |
       editor_simulate_key: correctly absent on the game endpoint |
       editor_simulate_mouse_click: correctly absent on the game endpoint |
       editor_simulate_mouse_move: correctly absent on the game endpoint |
       editor_simulate_input_sequence: correctly absent on the game endpoint |
       editor_add_input_action: correctly absent on the game endpoint
[PASS] guard_user_port_9877   pid_before=36392 pid_after=36392
group=editor_input_simulation tools=6 contract=171
implemented_union=49 tools (editor endpoint) / 40 tools (game endpoint)
3/3 checks passed            (exit 0)

===== RUN 2 =====  与 RUN 1 完全一致：3/3 checks passed（exit 0）
```

两次运行的 `[PASS]` 清单一致；逐条 `name`/`description`/`inputSchema` 由脚本内 `-ceq`（区分大小写）比较；
「未实现却已注册」的工具为 0（脚本按已实现**并集**断言 extra/missing）。
6 个工具的 `description` 与 `inputSchema` 全部由 `scripts/gen_b2_game_schema.py` 从契约**逐字节生成**
（`--in-place` 连跑两次为 no-op，已验证），手工未誊写一个汉字。

---

## 5. 门② 三类证据（`scripts/mcp013_editor_input_evidence.ps1`，3 个 phase）

证据目录：`%TEMP%\mcp013-evidence\`（52 个 `.response.json` + `.request.json`）。全部用
`curl.exe -s --max-time N -o <file> --data-binary @<body-file>`；请求体一律 `ConvertTo-Json` 生成并落盘为文件
（禁止命令行承载 JSON）；每个响应文件落盘后算 sha256 并打印。**从不经 `Out-File` / 管道承载响应体。**

| phase | 检查数 | 覆盖 |
|---|---|---|
| `boundary` | **24/24 PASS** | GDR-21 双进程对照、6 工具成功路径、编辑器/游戏 tools/list 双向缺席、默认上限 |
| `limits` | **11/11 PASS** | 事件数上限（3）与时长上限（500 ms）两条轴的真实截断 |
| `negatives` | **15/15 PASS** | 每个工具的缺参/类型错 `-32602`、9889 上 6 个工具全 `-32601`、以及不可构造类的显式声明 |

### 5.1 逐工具三类（成功 / 缺参 → `-32602` / 底层失败）

| 工具 | 成功 | 缺参或类型错 → `-32602` | 底层失败 |
|---|---|---|---|
| `editor_simulate_key` | `b06` → `{"keycode":"A","pressed":true,"simulated":"key","target":"editor"}`（+`b07` 编辑器进程计数=1） | `n02`（缺 `keycode`）、`n02b`（`NOPE_NOT_A_KEY`：`name(s) the key … not a key name this engine knows`） | **声明**：本类=「本进程没有 `Input` 单例」的 `-32000`，**编辑器端点不可构造**（运行中的编辑器必然有 `Input`/`InputMap`）；该分支由 doctest 钉住（见 `n10` 与 §6 门③） |
| `editor_simulate_mouse_click` | `b09` → `{"button":1,"position":{"x":5.0,"y":6.0},"simulated":"click","target":"editor"}` | `n03`（`button:99` → `must be a MouseButton value between 1 (left) and 9 (xbutton2), got 99`） | 同 `editor_simulate_key`（`n10` 声明） |
| `editor_simulate_mouse_move` | `b10` → `{"position":{"x":9.0,"y":10.0},"simulated":"mousemove","target":"editor"}` | `n04`（`y:"tall"` → `'y' must be a number, got String`） | 同（`n10`） |
| `editor_simulate_input_action` | `b12` → `{"action":"mcp013_probe_action","in_input_map":true,"simulated":"action","strength":1.0,"target":"editor"}` | `n01`（缺 `action`）、`n06` 之外的类型/空白分支由 doctest 覆盖 | 同（`n10`） |
| `editor_simulate_input_sequence` | `b20` → `{"event_count":3,"frame_delay":1,"sent":true,"target":"editor","time_ms_ignored":false}`（69 ms，跨帧） | `n05`（`events:[]`）、`n05b`（`type:"telepathy"` → 列出可接受类型）、`n05c`（`events[0].keycode` 缺失） | 同（`n10`）；其超时形态=`框架 30 s 上限 → -32000 + data.timeout_ms`（GDR-20 通用路径，TASK-011 门已钉） |
| `editor_add_input_action` | `b11` → `{"action":"mcp013_probe_action","created":true,"event_count":1,"key":"F9","persisted":false,"target":"editor"}`（+`b16` 编辑器 InputMap 列表含它） | `n06`（缺 `action`） | 同（`n10`） |

**不可构造类的显式声明（`n10`，原文）**：

```
[PASS] n10_underlying_failure_class_declared
  the -32000 (no Input/InputMap singleton) class is unreachable on a live editor endpoint by construction and is
  pinned by the module doctest; the only wire-visible "unavailable" answer is -32601 on the game endpoint (n09)
```

### 5.2 跨工具的端到端活证据链（`boundary` phase，全部真实请求）

```
[0] b02  游戏脚本已加载（Main.status_text == "idle"）        ← 前置：脚本解析失败时下面全是 null
[1] b05  基线：游戏 keys/mouse/motion = 0/0/0；编辑器探针 全 0
[2] b06  9888 editor_simulate_key(A)                        -> ok, target=editor
[3] b07  编辑器探针 key=1                                    ← 编辑器侧状态变化
[4] b08  9889 读游戏 key_events = 0                          ← 游戏侧**无变化**
[5] b09  9888 editor_simulate_mouse_click(1, 5, 6)           -> ok
[6] b10  9888 editor_simulate_mouse_move(9, 10)              -> ok
[7] b11  9888 editor_add_input_action(mcp013_probe_action, F9) -> created=true, persisted=false
[8] b12  9888 editor_simulate_input_action(mcp013_probe_action) -> in_input_map=true
[9] b12' 编辑器探针：mouse_button=1 mouse_motion=1 action=1
[10] b15 9889 读游戏 mouse_events/motion_events = 0/0
[11] b16 9888 editor_get_input_actions -> count=90，含 mcp013_probe_action
[12] b17 9889 执行 GDScript InputMap.has_action(...) -> false  ← 两张 InputMap 不同
[13] b18/b19 **对照**：游戏进程内注入同一个键 -> 游戏 key_events 0→1（计数器是活的）
[14] b20 9888 editor_simulate_input_sequence(3 事件) -> event_count=3（68 ms，跨帧）
[15] b21 编辑器探针 key 1→2
[16] b22 9889 游戏 key_events 仍 = 1                          ← 整条序列也没到游戏
[17] b23 9889 调用 editor_simulate_key -> -32601
[18] b24/b25 两个端点的 tools/list：49 vs 40，六个工具只在 9888
[19] b26/b27 无上限配置的一次录制 -> truncated=false, dropped=0, limits={100000, 600000}
```

### 5.3 证据文件 sha256（报告引用到的）

| 检查 | 文件 | sha256 |
|---|---|---|
| n02b 未知名键被拒 | `n02b_simulate_key_unknown_key.response.json` | `022daab2f281d1997cfeacb028e87c6da8026d1a9382406613258ebc14cb9e9f` |
| n03 button 越界被拒 | `n03_simulate_mouse_click_bad_button.response.json` | `1f653627bbd59114ac0be9e15630e8e8594756f0d826d8ccdd41954dec526275` |
| n09 9889 上第 6 个工具 | `n09_game_calls_5_editor_add_input_action.response.json` | `3cbae6c3d61d6b75d8706173c4dfce74561b89af3726fe060e487d8d68fbfee9` |
| b27 默认上限 | `b27_recording_stop.response.json` | `9b5b5a2fa4f636fcdd2f3456df61e26e40d34950dcd92487a2e08b7274ac310b` |
| l_events 截断（事件轴） | `l_events_05_recording_stop.response.json` | `2bdcb7944e990194448d4c9fc666e5b789064542e641832b437612659f1e74a5` |
| l_duration 截断（时长轴） | `l_duration_05_recording_stop.response.json` | `b423fa1dd8d7c5338bce653bb8a50e2884dc48fd5fa9f70234f564a978be777b` |

---

## 6. 录制上限与截断证据（D59 第 5 条 / `DESIGN-DETAIL` §19.5）

### 6.1 设计（可配置 + 两条轴）

`tools/input_recorder.{h,cpp}`（TASK-012 新增的录制设施）此前**完全没有上限**：`capture()` 对每次事件
`push_back` 一个 `Ref<InputEvent>`，一个忘了 stop 的会话会把游戏进程的堆无界撑大。本批加了**两条轴**的上限，
并在达到上限时**停止采集**、**计数**、**如实回报**：

* 默认值（编译期常量）：`DEFAULT_MAX_EVENTS = 100000`、`DEFAULT_MAX_DURATION_MS = 600000`（10 分钟）。
  理由：人类驱动的会话通常只有几千个事件，10 万个事件是数十 MB 量级——**远高于任何脚本化会话、又远低于**
  **威胁进程的量**；10 分钟比任何脚本化场景都长，同时仍能兜住一个被遗忘的录制。二者都是「长到无感、短到有用」。
* 配置优先级（`start()` 时**按会话**解析，不中途改变）：
  1. **项目设置**（与 `godot_mcp/port` 同一条通道）：`godot_mcp/recording_max_events` /
     `godot_mcp/recording_max_duration_ms`（同时接受点号别名），值 `<= 0` 表示**该轴不设上限**；
  2. `MCPInputRecording::set_limits(events, duration)`（程序化配置，doctest 用它）；
  3. 编译期默认值。
* 截断语义：**「至少真的丢了一个事件」才算 truncated**——达到上限后事件被丢弃并 `dropped++`，
  会话保持 open（这样 `running_game_stop_input_recording` 仍能把已录到的部分交出来）。
  一个「时钟过了时长上限但之后再没来事件」的会话**什么都没丢**，因此不会声称 truncated（不假报，也不静默丢）。
* 报告形状：`truncation_report()` 是**唯一**构造点，`running_game_stop_input_recording` 的答案**无条件**带
  `truncated` / `dropped` / `limits`（`0` = 该轴无上限），换来的是一条稳定的答案形状。

### 6.2 线上证据（`-Phase limits`，11/11 PASS）

事件轴（项目写 `recording_max_events=3`，在游戏进程内注入 5 个按键事件，每次一个 HTTP 调用=不同帧）：

```
[PASS] l_events_05_truncation_is_reported :: answer: event_count=3 truncated=True dropped=2
       limits={"max_duration_ms":600000,"max_events":3}
       message=Recording stopped (a length cap was reached; older events were dropped)
[PASS] l_events_06_exactly_the_cap_was_kept :: recording_max_events=3 with 5 injected events -> event_count=3 dropped=2
[PASS] l_events_07_the_kept_events_are_the_first_ones :: event_types={"action":0,"key":3,"mouse_button":0,"mouse_motion":0,"other":0}
```

被测答案原文（`l_events_05`，节选）：

```
{"dropped":2,"duration_ms":1014,"event_count":3,
 "event_types":{"action":0,"key":3,"mouse_button":0,"mouse_motion":0,"other":0},
 "events":[{"keycode":"A","time_ms":55,"type":"key"},{"keycode":"B","time_ms":82,"type":"key"},
           {"keycode":"C","time_ms":110,"type":"key"}],
 "limits":{"max_duration_ms":600000,"max_events":3},
 "message":"Recording stopped (a length cap was reached; older events were dropped)",
 "recording":false,"truncated":true}
```

时长轴（项目写 `recording_max_duration_ms=500`，限制内注入 1 个事件、1200 ms 后再注入 1 个）：

```
[PASS] l_duration_05_truncation_is_reported :: answer: event_count=1 truncated=True dropped=1
       limits={"max_duration_ms":500,"max_events":100000}
[PASS] l_duration_06_the_cap_is_the_duration_axis :: 一个在限制内、一个在 1200 ms 后 -> event_count=1 dropped=1
```

默认值（`boundary` phase，项目**没有**写任何上限）：

```
[PASS] b26_default_recording_limits_are_reported :: truncated=False dropped=0
       limits={"max_duration_ms":600000,"max_events":100000}
```

### 6.3 doctest 侧（可配置 + 边界）

`[MCPServer] a recording stops at its length cap and reports what it dropped` 用 `set_limits()` 驱动四条：
事件轴（kept=cap、dropped 正确、被保留事件带真实 `time_ms`）、时长轴（**恰好等于上限的事件保留**、其后的丢弃）、
`0/0`= 无上限（200 个事件全留、不截断）、以及「时钟过了上限但无新事件 → 不声称截断」；
`reset()` 把程序化配置也恢复成默认值，避免 doctest 之间串味。

---

## 7. 本批发现并修复的真缺陷（红→绿）

### CR-4 `_make_mouse_button_event` 没设 `global_position`：鼠标实际没动（**已修**）

新 doctest 一开始直接断言「工具注入后 `Input::get_mouse_position()` 应等于注入的坐标」——**失败**：

```
.\modules/mcp_server\tests\test_mcp_server.h(6827): ERROR: CHECK( input->get_mouse_position() == Vector2(1, 2) ) is NOT correct!
```

根因（引擎事实，不是口味问题）：`InputEventMouse::set_position()` **只写 `pos`**（`core/input/input_event.cpp:689`），
而 `Input::_parse_input_event_impl()` 是用 **`get_global_position()`** 移动鼠标的（`input.cpp:926`）。
于是答案里 `position` 看起来是 (1,2)，进程的鼠标却还在 (0,0)——**「报了成功但实际没发生」**，正是模块禁止的形态。
修法：`position` 与 `global_position` **都设**（迁移源里更完整的 `mcp_input_service.gd:_create_mouse_button_event`
也是两者都设）。绿阶段：`b09`/`b10` 之后 `Input::get_mouse_position()` 与序列内的 (3,4) 全部命中。

### CR-5 鼠标按钮下标未做范围校验（**已修**）

`core/input/input_enums.h:156` 的 `mouse_button_to_mask()` 是 `1 << (button - 1)`：迁移源把调用者给的任意整数
直接灌进事件，`button: 99` 就是**移位 UB**。修法：`1..9`（`MouseButton::LEFT..MB_XBUTTON2`）之外一律 `-32602`，
线上 `n03` 与 doctest 各钉一次。（这一条属于「引擎里不能喂 UB」的安全校验，不是格式挑剔。）

### 勘误（append-only）

1. **`truncated` 的语义在实现过程中被收紧过一次**：初稿把「时钟超过时长上限」也算截断；后来改成
   **只有真的丢了事件**才算（`dropped >= 1` 才置位）。理由是「不假报」优先于「早报」，doctest 第 (4) 条专门钉住
   了反面（过了上限但无新事件 → `truncated:false`）。
2. **`editor_add_input_action` 二次同键调用不会重复绑定**：实现时按「迁移源没有去重」写了注释，doctest 立刻抓到
   （`CHECK(event_count == 2)` 失败，实际 1）。查证引擎：`InputMap::action_add_event()` 用 `_find_event()` 去重
   （`input_map.cpp:205`）。已改注释与测试为**回读语义**（答案报告 map 的真实计数，而不是调用者的意图）。
3. **doctest 在本 fork 里 `REQUIRE` 不会中断用例**（`tests/test_macros.h:44` → `DOCTEST_CONFIG_NO_EXCEPTIONS_BUT_WITH_ALL_ASSERTS`）：
   第一版用例在 `REQUIRE(task != nullptr)` 之后直接解引用，结果是 **SIGSEGV 把整个用例变成 crash 报告**
   （而不是一条失败断言）。已把本批所有「REQUIRE 之后才读值」的地方改成 `if (…) { CHECK(false); return; }` 形态，
   并把这个坑以注释写进测试文件，供后续批次复用。
4. **测试期望值自身的一处笔误**：序列用例里我按「click of (4)」写了鼠标仍为 (1,2)，但 (4) 的最后一步 move 已把
   它改成 (7,8)；两处断言改为 (7,8)。这是**测试的**错误，不是被测物的。

---

## 8. 门③/④/⑤ 真实输出与退出码

### 门③ 模块 doctest

```
[doctest] test cases:  122 |  122 passed | 0 failed | 1429 skipped
[doctest] assertions: 3618 | 3618 passed | 0 failed
[doctest] Status: SUCCESS!        (exit 0)
```

基线 TASK-012 的 118 用例 / 3288 断言 → **+4 用例 / +330 断言，0 failed**。新增 4 个用例（全部 `[MCPServer]` 前缀）：

| 用例 | 覆盖 |
|---|---|
| `the editor_input_simulation group is editor-only and one tool is deferred` | 6 个工具的注册/可见性/游戏进程缺席、序列的 deferred 归属、`call_tool` 对 deferred 回 `-32603`、游戏注册表 `-32601` |
| `the editor input simulation tools validate every argument before they touch the editor` | 每个工具的全部 `-32602` 分支、无 `Input`/`InputMap` 时 `-32000` + suggestion、序列「在任何等待之前全部校验」（`deferred=false, task=nullptr`） |
| `the editor input simulation injects into this process' Input and InputMap` | **成功路径**：自建 `Input`/`InputMap`（引擎 listener 只为 `[SceneTree]`/`[Editor]` 用例建它们），断言按键状态、action 状态、鼠标位置（CR-4 的红阶段就在这里）、`persisted:false`、去重回读、序列任务按帧推进与 `time_ms_ignored` |
| `a recording stops at its length cap and reports what it dropped` | 双轴上限、精确到「恰好等于上限」的边界、`0=无上限`、不假报截断、`reset()` 复位 |

### 门④ 全引擎回归

```
[doctest] test cases:   1548 |   1548 passed | 0 failed | 3 skipped
[doctest] assertions: 427900 | 427900 passed | 0 failed
[doctest] Status: SUCCESS!        (exit 0)
```

基线 TASK-012 的 1544/427570 → **+4 用例 / +330 断言，0 failed**。

### 门⑤ `accept_m1.ps1` 连跑两次

```
runA: 22/22 cases passed   (exit 0)   implemented tools = 49 (editor endpoint) / 40 (game endpoint); contract = 171
runB: 22/22 cases passed   (exit 0)   同上
Compare-Object(runA 的 [PASS] 清单, runB 的 [PASS] 清单) = 空（IDENTICAL，各 22 行）
```

`$ToolNames` 只追加 6 个**editor-scope** 名字：`$EditorToolNames` / `$GameToolNames` 等派生量按
`tool-rename-map.json` 的 `scope` 自动跟随，**没有任何断言被削弱**；`case3_tools_list_fixture` 现在比较 66 个
逐字条目，`case12_game_process_endpoint` 的游戏侧集合仍为 40。

### B2 = 25/25（机器校验）

```
SOURCE  DESIGN-DETAIL.md section 10: B2 declares 25 old tools, parsed 25/25
DERIVE  B2 tools to port = 25 - 0 = 25
GROUP   running_game_observation       … implemented=True  tools=6
GROUP   running_game_frame_observation … implemented=True  tools=3
GROUP   running_game_script_execution  … implemented=True  tools=1
GROUP   running_game_input             … implemented=True  tools=4
GROUP   running_game_node_write        … implemented=True  tools=1
GROUP   running_game_capture           … implemented=True  tools=1
GROUP   editor_playback                … implemented=True  tools=2
GROUP   editor_input_simulation        … implemented=True  tools=6
GROUP   editor_input_read              … implemented=True  tools=1
ASSERT  every B2 tool appears exactly once: PASS (duplicates=0, missing=0, foreign=0)
ASSERT  every name exists in the 171 entry contract: PASS
ASSERT  every group is one channel + one scope + one mutating value: PASS
ASSERT  group sizes <= 10: PASS
ASSERT  implemented=true groups = 9, carrying 25 tool(s)
BYTES  11623
SHA256 14eba00016c00bff914bb39aff9cfb5f01e375a43fa2ff5038d69bdedfc8b75d
TOOL-GROUPS-B2 CHECK PASS
```

外加「已实现并集计数」的独立核对：编辑器端点 `tools/list` = **49**、游戏端点 = **40**，
`implemented_union=49/40`（门① 输出），与 B2 的 25 工具无冲突（并集还含 B1 的 41 个）。
**B2 = 25/25。**

---

## 9. 关键工件 sha256

引擎二进制（本次全部门与证据使用的构建）：
`46e92359792703107e3108a469a20fc53a6245768b2e7b76a3ce5a98110e8a6b`
（`bin\godot.windows.editor.x86_64.console.exe`）

```
a51b72930d37861f1f1a1b447b7c5f89da559bd0557f9dcdb9b7445aa25a5bd3  tools/editor_input_simulation.h
42d4fdb585e7cacd818d11de22c45bdef1ffbd327f85a88a508eeb0be779ce74  tools/editor_input_simulation.cpp
ab60398b8a160148c6c5a22b202fcaf6fd5842289fca8b8db823aa18c0e32a55  tools/input_recorder.h
19faabccd00cf029fe5b558392af67ae587900eaa33d7eb0b2d97671cdc5c362  tools/input_recorder.cpp
016b02119c15a9250ddba8c86f606c752da0b1596cfb56a0ce1f8bc73778d137  tools/running_game_input.cpp
a61cd760a2bd275097f5c106323d27778395b5893106127ec4b9d2d35e696dbc  tools/registration.cpp
d96901897974868a0a6772656a8beeeea3cfbf28854ea0d3c0456dd514b4539a  tests/test_mcp_server.h
cc00f5275dc1a57876d562a5abf4aa0fe18d2110f2e2d0a58c232a693d6ac088  scripts/gen_b2_game_schema.py
97a9a039e1e17c4aaf68c6367511b8c0d224b950f6ca4e0a5681c1c15e76ecbd  scripts/accept_m1.ps1
77acaafbb5c2f4cde91a20220bc4f935ccb295ecbeab8205cde977d0587235ec  scripts/mcp013_editor_input_evidence.ps1
14eba00016c00bff914bb39aff9cfb5f01e375a43fa2ff5038d69bdedfc8b75d  docs/tool-groups-b2.json
c4f913d65c3f3fd311d36ded44b473189cf886f098959fe7b6edf49b74901298  docs/tools_list.renamed.json (未改)
2f552719f6a23fe328df0a2944c6048824c1b2a750aebc0fe2cabbcd3529c2bd  docs/tool-rename-map.json    (未改)
0cfcac80f0d999fa7db713ae48f43febe96ae52e2c93633257eeed00ffdfbfac  docs/tool-groups.json        (未改)
```

---

## 10. deviations / blockers / 勘误 / next_step_recommendation

### deviations（与手册/任务书的偏离，逐条显式）

1. **`editor_simulate_input_sequence` 注册为 deferred（GDR-20）**。任务书未明说；理由是它的 `frame_delay`
   就是帧时钟（迁移源的游戏侧服务 `mcp_input_service.gd:61-65` 亦然），单帧注入会把整条序列塌成一帧。
   可观察差异：**第一个事件晚一帧落地**（deferred 通道从不在到达帧 tick）。
2. **两个单事件鼠标工具只发一个事件**：`addons` 版的 `_simulate_mouse_click` 会 press+release（`auto_release`），
   但该参数不在契约里，且映射裁决的语义源（`input.rs`）只发一个事件。已按后者实现并显式记录。
3. **`editor_simulate_key` 对未知键名回 `-32602`**（迁移源注入 `KEY_NONE`）。按 PLAYBOOK §6.6「工具真的能用」，
   一次什么都看不出的按键注入属于必须消除的静默失败。
4. **鼠标 button 范围校验 1..9**（迁移源无校验）：防的是 `mouse_button_to_mask()` 的移位 UB，非风格问题。
5. **所有 6 个工具的答案新增 `target:"editor"`**；`editor_simulate_input_action` 另加 `in_input_map`，
   `editor_add_input_action` 另加 `persisted:false`，序列另加 `time_ms_ignored`。都是**答案超集**，不改既有键。
6. **录制上限可配置的通道是 `ProjectSettings`（`godot_mcp/recording_max_events` /
   `godot_mcp/recording_max_duration_ms`）+ 程序化 `set_limits()`**，默认 100000 / 600000 ms（理由见 §6.1）。
   契约里没有上限参数（不得改契约），所以配置只能走 out-of-band 通道；选的这条与 `godot_mcp/port` 同源。
7. **`running_game_stop_input_recording` 答案新增 `truncated` / `dropped` / `limits` 三个无条件键**
   （TASK-012 已加过 `event_types` / `duration_ms`，本批延续同一策略：稳定形状 > 最小键集）。
8. **`truncated` 的语义是「至少丢了一个事件」**，而不是「时钟越过了上限」；一个 10 分钟无事件的会话不会声称截断。
9. **测试文件里三处旧计数 60→66、43→49**（编辑器进程表），并同步更新其注释；没有削弱任何断言。
10. **门②由三个 phase 组成**（`boundary` / `limits` / `negatives`），脚本为
    `scripts/mcp013_editor_input_evidence.ps1`（本批新增）。
11. **`docs/tool-groups-b2.json` 的 `editor_input_simulation` 翻为 `implemented:true` 并更新 notes**
    （manifest 是数据文件，B1 的 `tool-groups.json` 未动，sha256 未变）。
12. **门③自建 `Input`/`InputMap` 单例**：本模块的 `[MCPServer]` doctest 进程默认没有这两个单例
    （引擎 listener 只为 `[SceneTree]`/`[Editor]` 用例创建，`tests/test_main.cpp:181`），而本组工具的全部成功路径
    都作用在它们之上。用例自己 `memnew` 并在用例末尾删除 `Input`（`test_case_end` 会删掉剩下的 `InputMap`），
    这是让成功路径可测的唯一方式；用例开头用 `REQUIRE` 钉住「进用例时两者为 null」，避免顺序变化把断言变成另一种测试。

### blockers

- **无阻塞。** 一条**引擎事实**被显式登记而非绕过：`InputEventMouse::set_position()` 不派生 `global_position`
  （`input_event.cpp:689` vs `Input::_parse_input_event_impl` 的 `input.cpp:926`），任何鼠标类工具都必须两个都设
  （CR-4）。另一条：`InputMap::action_add_event()` 对同一事件去重（`input_map.cpp:205`），因此
  `editor_add_input_action` 的 `event_count` 是回读值。

### 给决策者的一条观察（不自行修改）

`tools/editor_input_read.cpp` 的 `editor_get_input_actions` **直接解引用 `InputMap::get_singleton()` 而无 null 检查**。
在真实进程里不可达（工具只服务编辑器端点，而编辑器进程必有 `InputMap`），所以**不是缺陷、也不构成本批的门**；
但一个「在无 InputMap 的进程里调用会崩」的分支是**可被 doctest 触达的**。按 PLAYBOOK「不得改别组文件」，
本批只登记不修改；若要收口，可在 B3 一并加一行守卫。

### next_step_recommendation

1. **B2 已 25/25**，可以进入 **M2 里程碑独立验收**（覆盖 B1+B2 共 66 个工具）。建议验收任务书把本报告的
   §2（双进程对照）与 §6（双轴截断）作为**必查证据**，并要求验收者**自己重跑** `-Phase boundary` /
   `-Phase limits`（脚本自包含、可复现）而不是只读结论。
2. **B3 可直接复用本批的两条经验**：①「`editor_*` 只写编辑器进程，`running_game_*` 才驱动游戏」——凡新输入类工具
   先问它属于哪个进程；②答案里写 `target`，让「作用于谁」随答案走，而不是只写在文档里。
3. **`editor_add_input_action` 的「不落盘」值得决策者确认**：如果产品期望「加一个 action 就能被游戏用到」，
   那这条路**不存在**（编辑器进程的内存 map 到不了游戏进程），需要的是写 `project.godot` 的另一个工具
   （属于 project 通道，非本组）。
4. **录制上限的两个项目设置键建议写进规范**（`godot_mcp/recording_max_events` /
   `godot_mcp/recording_max_duration_ms`，`<=0` = 无上限），以免后续被当成「未文档化的配置面」。
5. **可选加固**：`MCPInputRecording` 目前只保留**一个会话**的快照；`stop` 之后的二次 `play` 依赖它。
   若 B5 要串 `record → save → load → replay`，建议把「快照 → 文件」也纳入上限（当前上限只作用于采集）。

---

## 附：TASK-041 勘误（append-only，D86）

> 追加于 TASK-041（M-6 代码锚点 `36c485834e`，门锚点 `96a2dc3331`）。本节**不改动**上面任何原文，
> 只指出哪几条结论已被后续实现取代、取代它们的证据在哪里。

1. §3 逐工具表与 §4 中 `editor_add_input_action` 的「**不落盘 `ProjectSettings` / `project.godot`、
   恒回 `persisted:false`**」**已不是当前行为**：TASK-041 让它把 action 的真实状态（`deadzone` + `events`）
   同时写进 `project.godot` 的 `[input]` 段（引擎自己的 `save_custom()` 原子发布 + rename），
   并把 `persisted` 改为**从磁盘回读**的真实结果（失败时附 `persisted_reason`，不新增参数、`inputSchema` 零改动）。
   证据：`docs/reports/REPORT-041-clean-gates-and-inputmap-persistence.md` §3（红/绿 doctest 真实输出 +
   32 条线上检查，其中两个**游戏进程**的 `InputMap.has_action(...)` = `true`）。
2. §7 建议 3「需要的是写 `project.godot` 的**另一个工具**（属于 project 通道）」**未被采纳**：
   决策是在**同一个**编辑器工具里补齐（理由：这就是该工具的用途，且加参数会动 171 条逐字门）。
3. §7 建议 3 里「值得决策者确认」的那一项**已确认**：结论就是「真的持久化」，见上。
4. **仍然成立**的结论：编辑器进程与游戏进程是**两张** `InputMap`，`editor_*` 只改编辑器进程那一张。
   TASK-041 补的是两者**唯一的汇合点**（`project.godot` 的 `[input]`），不是「让编辑器进程驱动游戏」。
5. **新增的引擎事实**（TASK-041 实测并已在 `REPORT-041` §4 记录）：编辑器进程的 `InputMap`
   **永远不会**加载工程的 `[input]` —— `main/main.cpp:2330-2336` 给编辑器的是 `load_default()`
   （编辑器自己的内建键），只有**游戏**分支走 `load_from_project_settings()`。
   因此 `editor_get_input_actions`（本报告 §1 的那个读工具）**不能**当作持久化的判据，
   甚至在一个全新编辑器进程里也**不会**列出 `project.godot` 里的 action。
