# RACING-TEST-PLAN — TASK-039 §A 组织者产物（赛车游戏方案 + 观察规则）

> 本文件是 TASK-039 试测的**方案与判据唯一来源**，供 §B（开发者）与 §C（观察者）共同使用。
> §A 只产出方案与规则：**不做游戏、不改模块、不碰 9877**。
> 所有「工具真的会这样答」的判断，除标注 **【实测】** 的以外都是 **【源码依据】**（读实现得到）或
> **【推断】**，级别逐条标出；§B/§C 必须把它们当作**待验证假设**而不是事实。

---

## 0. 锚点（D86）与写本文时的实测状态

| 项 | 值 | 来源 |
|---|---|---|
| 仓库 | `F:\RustProjects\godot-mcp-pro\code\godot` | — |
| 分支 | `feature/mcp-server-module` | `git rev-parse --abbrev-ref HEAD`【实测】 |
| HEAD | `f34ee937f3d31c49ac42081bb91433c5fc5b36e3`（2026-09-23 22:31:44 +0800） | `git log -1`【实测】 |
| 模块树是否干净 | 空（`git status --short modules/mcp_server/tools modules/mcp_server/tests` 无输出） | 【实测】写本文时 |
| 契约 `docs/tools_list.renamed.json` | 171 条；sha256 `c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256` | 【实测】 |
| 组清单 `docs/tool-groups.json` | sha256 `0cfcac80f0d999fa7db713ae48f43febe96ae52e2c93633257eeed00ffdfbfac` | 【实测】 |
| `mcp_server.h` | sha256 `ad88d12498aa9225ee8d6cc4f43089fdb76cf59ee617038228283a22301fc63e` | 【实测】 |

**D86 纪律**：§C/§D 的每条结论都必须标「测自哪个提交」。凡引用 `REPORT-013`（D59/GDR-21 编辑器/游戏输入边界）、
`REPORT-024a`（`editor_play_scene` 注入口）、`REPORT-038`（trace）等**别的报告的结论，必须在
`f34ee937f3` 上复测**后才可引用；复测不一致 → 显式写「旧结论在 `f34ee937f3` 已过期」。

---

## 1. 试测目标（First principles）

试测**不是**为了得到一台好看的赛车。它要回答的是：

1. 一个**没有模块上下文**的调用方，能不能只用 MCP 工具把「车能被键盘驱动 → 检查点/圈计时真的在变 →
   HUD 能读到」这条链**做完并自证**？
2. 做不到的那一段，**缺的是什么**（工具？参数形状？错误消息？），以及**摩擦有多大**（几次才成功）。

因此方案里每一条「验收判据」都必须能**用响应本身**判定真假，而不是靠开发者自述。
「车动了」的判据必须是**另一个工具读回的位置/距离变化**，不能是注入工具的返回值。

### 1.1 预登记的「期望行为」——这些**不算缺陷**（观察者不得记成异常）

| 编号 | 预登记 | 依据 |
|---|---|---|
| E-1 | `--headless` 进程里 `running_game_capture_screenshot` / `running_game_capture_frames` 返回 `-32000` + 「没有帧缓冲 / headless display server 没有纹理存储」+ `data.suggestion` | 【源码依据】`tools/running_game_capture.cpp:64,100-101`；`running_game_frame_observation.cpp:444,511-512` |
| E-2 | `--headless` 编辑器里 `editor_capture_screenshot` 同上返回 `-32000` + suggestion | 【源码依据】`tools/editor_write_scene_editor.cpp:829,863-872` |
| E-3 | `editor_simulate_key` / `editor_simulate_input_action` / `editor_simulate_input_sequence` / `editor_add_input_action` 作用于**编辑器进程自己的 `Input`/`InputMap`**，**不能驱动 9889 上的游戏** | 【源码依据】`tools/editor_input_simulation.cpp:301-302,333-334`；`REPORT-013` 的 D59/GDR-21 记录（**须在 `f34ee937f3` 复测**） |
| E-4 | `editor_add_input_action` 成功但 `persisted:false`（**不落盘** `project.godot`）→ 游戏进程读不到该 action | 【源码依据】`tools/editor_input_simulation.cpp:1154-1170` 与 `REPORT-013`（**须复测**） |
| E-5 | 9889（游戏端点）上不存在任何 `editor_*` 工具（`scope=EDITOR` 守卫） | 【源码依据】`tools/tool_builder.h` 的 `MCP_EDITOR_TOOLS_ENABLED` 语义（`PLAYBOOK §2.3`）；用途：`tools/list` 需按 `name` 集合判断而非文本包含（`PLAYBOOK §7.4`） |
| E-6 | `running_game_assert_screen_text` 走**控件树**而非像素 → headless 也成立 | 【源码依据】`tools/running_game_assertion.cpp:186`；`tools/tool_helpers.cpp:2310` |
| E-7 | `running_game_run_test_scenario` 的 `input` step 与 `running_game_play_input_recording` 各由**自己的**注入器注入：前者只设 `keycode`，后者可选 `physical` | 【源码依据】`running_game_test_execution.cpp:127-133`（只 `set_keycode`）vs `running_game_input.cpp:371,374`（`set_keycode` + `set_physical_keycode`） |

> **E-1/E-2 是预登记，不是豁免**：若实际返回的**不是** `-32000`（例如 `-32603`、或报成功但给空图、
> 或没有 `data.suggestion`），那就是**异常**，按 §4 A 类记录。

---

## 2. 赛车游戏方案

### 2.1 工程与构建

| 项 | 值 |
|---|---|
| 工程目录 | `%TEMP%\mcp-racing-test\`（C# 工程，**所有工程文件写 UTF-8 无 BOM**；`.ps1` 一律纯 ASCII） |
| 引擎二进制 | `F:\RustProjects\godot-mcp-pro\code\godot\bin\godot.windows.editor.x86_64.mono.console.exe`（模块已内置；开工前按 `PLAYBOOK §3` 校验 `--version` 的 hash 前缀 == `git rev-parse --short HEAD`） |
| C# 构建 | `dotnet build` **离线**，包源指向引擎自带 `bin\GodotSharp\Tools\nupkgs` |
| 导入 | `--import` 必须**校验退出码 + 有界重试（默认 3 次）+ 可诊断输出**；写工程文件走 `scripts\mcp_import_guard.ps1` 的 `Write-McpUtf8NoBom` / `New-McpScratchProject`（`PLAYBOOK §3` 的 TASK-028 判据） |
| 追踪 | 编辑器 `--mcp-trace=%TEMP%\mcp-racing-test\trace-editor.jsonl`；游戏 `--mcp-trace=%TEMP%\mcp-racing-test\trace-game.jsonl` |
| 端口 | 编辑器 **9888**，游戏 **9889**；**9877 绝不占用/杀/重启**（开工前与收工后各查一次 `netstat -ano \| findstr :9877`） |
| 端点 | `http://127.0.0.1:9888/mcp`（编辑器）、`http://127.0.0.1:9889/mcp`（游戏） |
| 证据采集 | 一律 `curl.exe -s -o <file> --data-binary @file`（**禁止**管道/`Out-File` 承载响应体，`PLAYBOOK §7.1`）；落盘后算 sha256 |

文件清单（`res://`）：

```
project.godot
mcp-racing-test.csproj
scenes/main.tscn                 # 唯一主场景
scripts/Main.cs  Car.cs  ChaseCamera.cs  LapTimer.cs  Checkpoint.cs  Hud.cs
resources/hud_theme.tres         # 用 project_create_theme 族生成
resources/car_material.tres      # PhysicsMaterial（摩擦/弹跳）
```

### 2.2 场景树（`res://scenes/main.tscn`，绝对路径前缀 `/root/`）

```
Main                     Node2D            [scripts/Main.cs]
├── Track                Node2D
│   ├── Road             Polygon2D         # 赛道面（视觉）；点集由 tools 写入 polygon
│   ├── WallOuter        StaticBody2D      # 外护栏（物理）
│   │   └── Collision    CollisionShape2D  # SegmentShape2D / ConcavePolygonShape2D
│   ├── WallInner        StaticBody2D      # 内护栏
│   │   └── Collision    CollisionShape2D
│   └── StartLine        Line2D            # 起跑线视觉
├── Checkpoints          Node2D
│   ├── CP0_StartFinish  Area2D  [scripts/Checkpoint.cs]  Index=0, IsFinish=true
│   │   └── Collision    CollisionShape2D  # RectangleShape2D 120x24
│   ├── CP1             Area2D  [scripts/Checkpoint.cs]  Index=1
│   │   └── Collision    CollisionShape2D
│   └── CP2             Area2D  [scripts/Checkpoint.cs]  Index=2
│       └── Collision    CollisionShape2D
├── Car                  CharacterBody2D  [scripts/Car.cs]
│   ├── Body             Polygon2D        # 车体视觉（无需贴图资源）
│   └── Collision        CollisionShape2D # RectangleShape2D 40x20
├── Camera               Camera2D         [scripts/ChaseCamera.cs]  # 跟随 Car
├── LapTimer             Node             [scripts/LapTimer.cs]
└── HUD                  CanvasLayer       [scripts/Hud.cs]
    ├── Root             PanelContainer   # theme = res://resources/hud_theme.tres
    │   └── VBox         VBoxContainer
    │       ├── LapLabel  Label           # "LAP 1/3"
    │       ├── TimeLabel Label           # "TIME 0.00"
    │       ├── BestLabel Label           # "BEST --.--"
    │       ├── CheckLabel Label          # "CP 0/3"
    │       └── SpeedBar  ProgressBar     # 速度条（主题驱动）
    └── StartButton      Button           # 文本 "GO"；用 running_game_simulate_button_click_by_text 触发计时开始
```

**路径稳定性要求**：所有节点**显式命名**（不用引擎自动后缀）。理由：`running_game_*` 的 `node_path`
既接受场景根相对路径（`Car`）也接受绝对路径（`/root/Main/Car`）【源码依据】`docs/tools_list.renamed.json`
中 `running_game_get_node_properties.description`；**两种写法都要各测一次**，用于抓「两种写法不一致」的缺陷。

### 2.3 C# 脚本（文件名 / 职责 / 关键成员）

> C# 事实（`PLAYBOOK §3` M3 记录，写脚本时必踩）：①`running_game_execute_gdscript` 编译到的是**裸
> `RefCounted`**，没有 `get_node()`，要用 `Engine.get_main_loop()`；②**非 `[Export]` 的 `public` 字段进不了
> `get_property_list()`，但 `Object::get/set` 仍可按名读写**（`csharp_script.cpp:1487-1521`）。
> 本方案**故意**两种字段都用：`[Export]` 用于「属性表可枚举」，裸 `public` 用于「按名可读写」的对照实验。

**`Car.cs`（`CharacterBody2D`）**
- `[Export] public float MaxSpeed = 320f;` / `Acceleration = 620f;` / `TurnRateDeg = 160f;` / `Drag = 240f;`
- `public int physics_frames;`（裸字段，逐物理帧 +1）
- `public double distance_travelled;`（裸字段，`+= Velocity.Length() * delta`）
- `public string last_input = "none";`（裸字段，最近一次生效的输入名；用于证明注入被脚本看见）
- `public int key_frames;` `public int action_frames;`（分别统计「靠原始按键读到」与「靠 InputMap action 读到」的帧数
  → **一次跑就能分辨 §2.4 的哪条注入路径真的打通**）
- `_PhysicsProcess(double delta)`：
  1. 前进/后退：`Input.IsKeyPressed(Key.W) || Input.IsActionPressed("drive_forward")`；
  2. 转向：`Key.A/Key.D` 或 `drive_left/drive_right`；
  3. 手刹：`Key.Space` 或 `drive_brake`；
  4. `Velocity` 用加速度/阻力更新，`Rotation` 按 `TurnRateDeg` 转，`MoveAndSlide()`；
  5. 统计裸字段；`EmitSignal("speed_changed", speed)`（`[Signal] delegate void SpeedChangedEventHandler(float speed)`）。
- `public void ResetToSpawn()`（供 `Main.cs` 与 `running_game_execute_gdscript` 调用）。
- **为什么按键轮询而不是 `_Input`**：`running_game_run_test_scenario` 注入的 `InputEventKey` **只设了 `keycode`**
  （E-7）→ `Input.IsPhysicalKeyPressed` 看不到它，`Input.IsKeyPressed` 能看到【源码依据】`running_game_test_execution.cpp:127-133`
  + 引擎 `Input::_parse_input_event_impl` 的按键表更新。**脚本必须用 `IsKeyPressed`**，否则「注入了但车不动」会被误判成注入工具缺陷。

**`LapTimer.cs`（`Node`）**
- `public int LapCount = 1;` `public int CheckpointsHit;` `public int LastCheckpointIndex = -1;`
- `public double CurrentLapTime;` `public double BestLap = -1.0;` `public double TotalTime;`
- `public bool Timing;`
- `[Signal] delegate void LapCompletedEventHandler(int lap, double time);`
- `[Signal] delegate void CheckpointPassedEventHandler(int index, double t);`
- `public void OnCheckpointEntered(Node2D area)`：按 `Index` 顺序计数，`Index==0 && CheckpointsHit>=3` →
  `LapCount++`、`BestLap` 更新、`CheckpointsHit=0`、`CurrentLapTime=0`、`EmitSignal("lap_completed",...)`；
  否则 `CheckpointsHit++`、`EmitSignal("checkpoint_passed",...)`。
- `_Process(delta)`：`if (Timing) { CurrentLapTime += delta; TotalTime += delta; }`

**`Checkpoint.cs`（`Area2D`）**
- `[Export] public int Index = 0;` `[Export] public bool IsFinish = false;`
- `[Signal] delegate void BodyCrossedEventHandler(int index);`
- `_Ready()`：`BodyEntered += OnBodyEntered;`（把 `body_entered` 转成自定义信号 → 让
  `running_game_capture_signal_emissions` 既能按引擎信号抓、也能按自定义信号抓）

**`Hud.cs`（`CanvasLayer`）**
- `public int refresh_count;`（裸字段，HUD 刷新次数 → 证明 HUD 真的在被驱动而不是静态文本）
- `_Process(delta)`：读 `/root/Main/Car` 与 `/root/Main/LapTimer`，刷新 5 个控件文本/值；`refresh_count++`。
- `public void OnStartPressed()`：`LapTimer.Timing = true;`

**`ChaseCamera.cs`（`Camera2D`）**
- `[Export] public NodePath TargetPath;` `[Export] public float Lerp = 0.15f;`
- `_Process(delta)`：位置向 `Target.GlobalPosition` 插值。用途：车**始终居中**而**世界滚动**，
  使窗口化模式的「帧间差异」判据不会被「车跑出屏幕」这种情况污染。

**`Main.cs`（`Node2D`）**
- `_Ready()`：记录 `Car.spawn_position`（裸字段 `public Vector2 spawn_position;`）、连接
  `Car.SpeedChanged → Hud.OnSpeedChanged`、`LapTimer.CheckpointPassed/LapCompleted → Hud.OnLapEvent`、
  `HUD/Root/VBox/../StartButton.Pressed → Hud.OnStartPressed`。
- 用途：让 `editor_connect_signal` 有 4 条**真实**连接可连、可列、可分析、可在运行时抓发射。

### 2.4 输入映射

| 键（keycode） | Input Action（若可用） | 语义 | 脚本判定 |
|---|---|---|---|
| `Key.W` | `drive_forward` | 油门 | `IsKeyPressed(Key.W) \|\| IsActionPressed("drive_forward")` |
| `Key.S` | `drive_backward` | 倒车 | 同上 |
| `Key.A` | `drive_left` | 左转 | 同上 |
| `Key.D` | `drive_right` | 右转 | 同上 |
| `Key.Space` | `drive_brake` | 手刹 | 同上 |
| `Key.R` | `drive_reset` | 回起点（辅助） | 直接 |

**两条注入路径都要试，并如实记录哪条真的打通**（`key_frames` / `action_frames` 两个裸字段就是判据）：

| 路径 | 工具 | 期望 |
|---|---|---|
| P-键码（**主路径，必须在验收里成立**） | `running_game_run_test_scenario` 的 `input` step 带 `keycode` | 【源码依据】`parse_input_event(InputEventKey{keycode})` → `key_frames` 增长，车动 |
| P-action（**次路径，允许失败，失败即证据**） | 同上带 `action`；或 `running_game_play_input_recording {events:[...]}` | 需要游戏进程 `InputMap` 里有该 action。若 `action_frames` 恒 0 → **缺失工具**证据（下条） |
| P-InputMap 写入（**观察目标，预期失败**） | ①`editor_add_input_action {action:"drive_forward", key:"W"}`；②`project_set_setting {key:"input/drive_forward", …}` | ①E-4 预期 `persisted:false`，游戏读不到；②`input/*` 在 Godot 4 是「含 `InputEventKey` 对象的 Dictionary/Array」，JSON 无法表达 → 预期 `-32602` 或写入后无效。**两条都失败 ⇒ 正是「缺失工具：没有工具能把 InputMap action 持久化进 project.godot」的证据**，回退（手改 `project.godot`）必须按 §4 B2 记录 |

**设计意图**：主路径（键码）不依赖 InputMap，因此**即使 P-action 全灭，验收 AC-3/AC-4 仍然成立**；
P-action 的失败只产出**观察**，不阻塞开发者。

### 2.5 两种运行模式

**模式 A — 窗口化（编辑器驱动；截图类判据只在此模式有效）**
1. 启动编辑器进程（这是**环境准备**，不是 MCP 调用，须在日志里声明）：
   `bin\godot.windows.editor.x86_64.mono.console.exe --path %TEMP%\mcp-racing-test --mcp-port=9888 --mcp-trace=%TEMP%\mcp-racing-test\trace-editor.jsonl -e`
2. 走工具：`editor_rescan_project_filesystem` → `editor_open_scene {path:"res://scenes/main.tscn"}`
   → `editor_get_scene_tree` → `editor_play_scene {mode:"current", mcp_port:9889}`
   （响应含 `mcp_port` / `mcp_port_source` / `endpoint` / 游戏 `pid`【源码依据】契约 description）
3. 游戏窗口化 → 截图类工具可用。

**模式 B — headless（自动化取证的主模式）**
1. 打开**一个**编辑器（9888，可窗口化）用于首次导入与静态检查。
2. 游戏进程直接自启（**环境准备**，须声明）：
   `bin\godot.windows.editor.x86_64.mono.console.exe --headless --path %TEMP%\mcp-racing-test --mcp-port=9889 --mcp-trace=%TEMP%\mcp-racing-test\trace-game.jsonl`
   （`application/run/main_scene` 由 `project_set_setting` 指向 `res://scenes/main.tscn`；
   命令行给了 `--mcp-port` 即 `explicit_cmdline=true` → 游戏进程会监听，无需其他开关
   【源码依据】`mcp_server.cpp:107-115` 的 `should_listen = explicit_cmdline || enabled_in_game`）
3. headless 下：状态/断言/文本/信号/跨帧采样工具**必须全绿**；`running_game_capture_*` 按 E-1 预期返回 `-32000`。

> **模式 B 的观察点**：`editor_play_scene` 是否能产出 **headless 子进程**？契约没有这个参数。
> 若开发者需要 headless，只能绕过工具自启游戏进程 —— 这**本身就是一条「缺失工具」线索**
> （「想要被观测的游戏以 headless 起来」没有任何工具能做），必须记录。**不要**把它写成开发者的失误。

### 2.6 赛道玩法（最小但完整）

- 3 个检查点 + 起/终点（`CP0_StartFinish` 兼作终点线），**跑满 3 圈**由 `LapTimer` 计数。
- 检查点顺序：必须按 `0 → 1 → 2 → 0` 才算一圈（`LapTimer` 用 `LastCheckpointIndex`/`CheckpointsHit` 判序）。
  这个「乱序穿越不计圈」的分支**必须被测**：用 `running_game_execute_gdscript` 把关车瞬移到 CP2 再回 CP0，
  断言 `LapCount` **不变**（负例）。
- `HUD/StartButton` 文本 `GO`：用 `running_game_simulate_button_click_by_text {text:"GO"}` 开计时
  → 这是「计时真的在被事件驱动」的第二个独立证据（第一个是键盘注入）。

---

## 3. 验收判据（§B 必须逐条给出实测响应 + sha256）

> 每条判据的格式：**ID / 用哪些工具 / 看什么响应算「过」/ 反例**。
> 证据文件名约定：`docs/reports/evidence/racing/<AC>-<n>-<tool>.request.json` / `.response.json`，
> 每个响应文件算 sha256；trace 侧给出 `seq` + `ts_ms` + `duration_ms` + `result_bytes`。
> **「车真的动了」不允许只由注入工具的返回值证明**——必须由**另一个读类工具**的位置/距离变化证明。

| ID | 工具链 | 过的判据 | 反例（必须也测） |
|---|---|---|---|
| **AC-1 工程与场景成立** | `project_get_info` → `project_get_settings{prefix:"godot_mcp/"}` → `project_get_filesystem_tree` → `project_read_scene_file_content` → `editor_get_scene_tree{max_depth:6}` | 场景树含 `Main/Track/Road/Car/LapTimer/HUD`；`project_read_scene_file_content` 的 sha256 与磁盘 `.tscn` 一致 | 请求不存在的场景 → 期望 `-32001` + `data.suggestion`（不是 `-32603`） |
| **AC-2 脚本真的挂上了** | `project_validate_script`（每个 `.cs` 各一次）→ `editor_set_node_script` → `editor_find_nodes_by_type{type:"CharacterBody2D"}` → `running_game_find_nodes_by_script{script:"res://scripts/Car.cs", properties:["MaxSpeed"]}`（9889） | 9889 上按脚本找到 Car，且 `MaxSpeed` 读回 == 场景里的值 | `project_validate_script` 对 **`.cs`** 的行为必须**实测记录**（契约没写它只支持 GDScript；若拒绝 → 记「缺失工具：C# 脚本无法被校验」） |
| **AC-3 车真的动了（键盘输入生效）** | ①`running_game_get_node_properties{node_path:"Car",properties:["Position","distance_travelled","physics_frames","key_frames"]}`（**T0 基线**）②`running_game_run_test_scenario{steps:[{type:"input",keycode:"W"},{type:"wait",seconds:1.5},{type:"assert",node_path:"/root/Main/Car",property:"distance_travelled",operator:"gt",expected:50.0},{type:"input",keycode:"W",pressed:false},{type:"assert",node_path:"/root/Main/Car",property:"key_frames",operator:"gt",expected:30.0}]}`（9889）③同上读回（**T1**） | ②的 `all_passed==true` 且 `passed>=3`；③的 `Position != T0.Position` 且 `distance_travelled` 增长 **> 50**；`physics_frames` 增长 > 60 | **反例 A**：只注入 `pressed:false`（不按）→ `distance_travelled` 增长 ≈ 0 且 `key_frames` 不增。**反例 B**：`editor_simulate_input_action{action:"drive_forward"}`（9888）→ 9889 的 `key_frames`/位置**不变**（这就是 E-3 的复测；若反而变了 → **异常**） |
| **AC-4 运动是连续的，不是瞬移** | `running_game_get_node_property_samples{node_path:"/root/Main/Car",properties:["Position","distance_travelled","physics_frames"],frame_count:120,frame_interval:1}`（在注入 W 的 `wait` 窗口内发起） | 样本序列满足：①`distance_travelled` **单调不减**；②相邻样本位移 ≤ `MaxSpeed/60*1.5`（断言一个**上界**，瞬移会违反）；③`physics_frames` 严格递增 ≥100 | 反例：单独调 `running_game_move_player_to_target`（导航分支）→ 位置会**大幅跳变**，用同一条「位移上界」判据把两种移动**区分开** |
| **AC-5 圈计时真的在走** | `running_game_get_node_property_samples{node_path:"/root/Main/LapTimer",properties:["CurrentLapTime","CheckpointsHit","LapCount","Timing"],frame_count:120,frame_interval:1}`（9889） | ①`CurrentLapTime` **严格递增**且末值 - 首值 ≈ `frame_count/60`（±30%）；②越过 CP1 后 `CheckpointsHit` 由 0 变 1；③跑满一圈后 `LapCount` 由 1 变 2 | 负例：`running_game_simulate_button_click_by_text{text:"GO"}` **之前**采样 → `Timing==false` 且 `CurrentLapTime` 不增（证明计时的「走」是被事件驱动的，不是无条件自走） |
| **AC-6 检查点信号链成立** | 9888：`editor_get_node_signals{node_path:"/root/Main/Checkpoints/CP1"}` → `editor_connect_signal{source_path:"/root/Main/Checkpoints/CP1",signal:"body_entered",target_path:"/root/Main/LapTimer",method:"OnCheckpointEntered"}` → `editor_list_signal_connections{node_path:"/root/Main/Checkpoints/CP1"}` → `editor_analyze_signal_flow{node_path:"/root/Main/Checkpoints/CP1"}`；9889：`running_game_capture_signal_emissions{node_paths:["/root/Main/Checkpoints/CP1"],signal_filter:["body_entered","checkpoint_passed"],duration_ms:8000}` | 三个编辑器侧工具对「连接存在」的答案**一致**；运行时的捕获里真出现 ≥1 次发射 | **矛盾检测点**：若 `editor_list_signal_connections` 说有、`editor_analyze_signal_flow` 说无（或反之）→ 按 §4 A7 记为**工具间矛盾**（注意 `analyze_signal_flow` 只统计 `CONNECT_PERSIST`，`PLAYBOOK §6.6` 已记录过这类坑） |
| **AC-7 截图（仅窗口化模式）** | 9889：`running_game_capture_screenshot{save_path:"user://race-1.png"}` → 再取 `user://race-2.png`（中间隔 `wait`）→ `running_game_capture_frames{count:6,frame_interval:10}`；9888：`editor_capture_screenshot{save_path:"res://shots/editor.png"}`；对比：`editor_analyze_screenshot_diff{image_a:...,image_b:...}` | 截图返回 ok 且文件 sha256 非空；`analyze_screenshot_diff` 报「有差异」（车在动 → 世界在滚动；HUD 时间文本在变） | **headless 反例**：模式 B 下调 `running_game_capture_screenshot` → 期望**恰好是** E-1 的 `-32000` + suggestion；偏离即异常 |
| **AC-8 属性写入与读回一致（防「报成功但没写」）** | `running_game_set_node_property{node_path:"/root/Main/Car",property:"MaxSpeed",value:999.0}` → `running_game_get_node_properties{properties:["MaxSpeed"]}`；再对一个**不存在**的属性写一次 | 读回 == 999.0；写不存在属性 → 期望 `-32001` + `data.suggestion`（`PLAYBOOK §6.6` 第 7 例） | 若写不存在属性**报成功**且读回 `null` → §4 A5（报成功但状态未变），**严重度 high** |
| **AC-9 双端点与契约一致性** | `tools/list` @9888 与 @9889（`curl.exe --data-binary @tools_list.json`，**必须解析 `name` 集合**，不得文本包含） | 9889 的集合 ⊂ 9888；差集恰为 `scope=EDITOR` 工具；两边每个工具 `name`/`description`/`inputSchema` 与契约逐字相等 | — |
| **AC-10 静态/工程分析工具可用** | `project_analyze_scene_complexity` → `project_get_scene_dependencies` → `project_find_unused_resources` → `project_get_statistics` → `editor_find_nodes_by_type` → `editor_get_errors` → `editor_get_output_log{filter:"MCP"}` | 各返回 ok；`editor_get_errors` 为空或只含已知 `--import` 噪声 | 大工程上的 `result_bytes` 是否 > 1 MiB（§4 A4 判据） |
| **AC-11 可复现性** | 同一 `running_game_run_test_scenario` 请求**连跑 3 次**（每次都先把车 `ResetToSpawn`） | 三次 `passed`/`failed`/`errors` 一致；`duration_ms` 量级一致 | 三次结果不一致 → §4 A8「不确定行为」 |
| **AC-12 模块未被试测改动** | `git status --short modules/mcp_server/tools modules/mcp_server/tests` 为空 + 契约 sha256 不变 | 与 §0 表一致 | 不等 → §B 违规，直接判 fail |

### 3.1 工具覆盖清单（证明「不是三五个工具的小玩具」）

方案**要求**至少覆盖以下工具族（每族 ≥1 个工具真被调用并留证）：

1. 项目/设置：`project_get_info` `project_get_settings` `project_set_setting` `project_get_filesystem_tree` `project_search_file_names` `project_search_file_contents`
2. 场景文件：`project_create_scene_file` `editor_open_scene` `editor_save_scene` `project_read_scene_file_content` `editor_get_scene_tree`
3. 节点读写：`editor_add_node` `editor_add_nodes_batch` `editor_rename_node` `editor_duplicate_node` `editor_reparent_node` `editor_set_node_property` `editor_set_node_property_batch` `editor_get_node_properties` `editor_set_node_selection` `editor_get_selection` `editor_find_nodes_by_type`
4. 脚本：`project_create_script` `project_edit_script` `project_validate_script` `editor_set_node_script` `project_list_scripts` `project_read_script` `editor_get_open_scripts`
5. 资源：`project_create_resource` `project_edit_resource` `editor_add_resource_to_node_property` `project_read_resource`
6. 输入映射：`editor_add_input_action` `editor_get_input_actions`
7. 物理：`editor_setup_physics_body` `editor_setup_collision_shape` `editor_set_physics_layers` `editor_get_physics_layers` `editor_get_collision_info`
8. 信号：`editor_get_node_signals` `editor_connect_signal` `editor_list_signal_connections` `editor_analyze_signal_flow`
9. 运行与游戏只读：`editor_play_scene` `running_game_get_scene_tree` `running_game_get_node_properties` `running_game_get_node_properties_batch` `running_game_find_node_when_available` `running_game_find_nodes_by_script` `running_game_find_nearby_nodes` `running_game_get_autoload_node`
10. 输入注入：`running_game_run_test_scenario` `running_game_create_input_recording` `running_game_stop_input_recording` `running_game_play_input_recording` `running_game_run_stress_test` `editor_simulate_key` `editor_simulate_input_action` `editor_simulate_input_sequence`
11. 断言/跨帧：`running_game_assert_node_state` `running_game_assert_screen_text` `running_game_get_node_property_samples` `running_game_capture_frames` `running_game_get_test_report`
12. 截图/对比：`running_game_capture_screenshot` `editor_capture_screenshot` `editor_analyze_screenshot_diff`
13. 日志/性能：`editor_get_errors` `editor_get_output_log` `editor_remove_output_log` `editor_get_performance_monitors`
14. HUD/主题/UI：`project_create_theme` `project_set_theme_color` `project_set_theme_font_size` `project_set_theme_stylebox` `editor_set_control_theme` `project_get_theme_info` `running_game_find_ui_elements` `running_game_simulate_button_click_by_text`
15. 分析：`project_analyze_scene_complexity` `project_get_scene_dependencies` `project_find_unused_resources` `project_get_statistics` `project_find_files_referencing_symbol`
16. 脚本执行（兜底/负例构造）：`running_game_execute_gdscript` `editor_execute_gdscript`

**可选分支**（有时间再做，做完记「额外工具覆盖」；**不做不算失败**）：

- **分支 N（导航）**：`editor_setup_navigation_region` → `editor_bake_navigation_mesh` → `editor_setup_navigation_agent` → `editor_set_navigation_layers` → `editor_get_navigation_info` → `running_game_move_player_to_target`。价值：AC-4 的反例（瞬移 vs 连续运动）、以及**「没有导航数据时 `move_player_to_target` 的错误消息是否足以自纠」**的实测（【源码依据】`running_game_navigation_write.cpp:778-784` 是 `-32000` + suggestion，**先不带导航数据调一次**，验证这条）。
- **分支 A（动画）**：`editor_create_animation` `editor_add_animation_track` `editor_set_animation_keyframe` `editor_get_animation_info` —— 检查点命中时闪一下。
- **分支 T（TileMap）**：`editor_get_tilemap_info` `editor_set_tilemap_cell` `editor_get_tilemap_used_cells` —— 把赛道面换成 TileMapLayer。**若无法用工具造出带 TileSet 的瓦片资源，这本身就是一条缺失工具线索**（记录，不要硬凑）。
- **分支 P（性能）**：`running_game_run_stress_test{action:"drive_forward", count:50}` → 与 AC-4 的采样对照（注意它**没有断言**，只有 `iterations_completed`/`events_sent`，`PLAYBOOK`/源码已声明 `crashed` 恒 false【源码依据】`running_game_test_execution.cpp:693-705`）。

---

## 4. 观察规则（rubric）

> **§C 的每条记录格式**（缺任一项视为不合格记录）：
> `序号 / trace ts_ms+seq（编辑器文件与游戏文件各写清哪个）/ 调用序列（工具名+参数要点）/ 事实 /
> 类别（A异常|B缺失|C可合并|D可优化）/ 证据（请求与响应文件名 + sha256 + error_code + duration_ms +
> result_bytes）/ 实测还是推断 / 建议`
>
> **阈值出处**：`scripts/analyze_mcp_trace.py`（TASK-038）已实现四组信号，本 rubric 与它对齐并沿用其常量：
> `DEFAULT_MAX_RESULT_BYTES = 1 << 20`（1 MiB）、`DEFAULT_DOMINANCE = 0.30`、`DEFAULT_EPISODE_WINDOW = 12`、
> `DEFAULT_PROBE_MIN = 2`。框架侧常量【源码依据】`mcp_server.h:60-108`：`MCPPendingTimeout::DEFAULT_MS = 30000`、
> `max_body_bytes = 8 MiB`、`max_requests_per_frame = 8`、`pending_ticks_per_frame = 8`、
> `connection_idle_seconds = 30.0`。
> 追踪行字段【源码依据】`mcp_trace.cpp:254-285`：
> `id, seq, ts_ms, connection, method, ok, error_code, error_message, error_message_truncated, duration_ms,
> result_bytes, tool, args, args_bytes, args_truncated, pending_ms, timeout_ms, tools`。

### 4.0 全局前置：把「预期」和「异常」分开

- 命中 §1.1 的 E-1..E-7 ⇒ **不是异常**，但仍要留证（否则无法区分「符合预期」和「没测」）。
- 响应缺 `id`、trace 行 `method` 为空且 `ok:false` ⇒ 传输层问题，按 A1/A2 记。
- **任何观察至少出现一次即可记录，但「异常」类要求能按相同 args 复现一次**（避免把偶发当缺陷）。
- **推断必须标推断**：如果只看到「报 ok」，不得写成「状态确实变了」；要有第二次读回。

### 4.1 A 类：异常（anomaly）

| ID | 判定标准（可机器判） | 复现要求 | 严重度起点 |
|---|---|---|---|
| **A1 非预期错误码** | `ok:false` 且 `error_code ∉ {-32602, -32001, -32000, -32601}`；`-32603`（内部错误）、`-32700`（解析失败，注意 `PLAYBOOK §3` 已警告「JSON 当命令行参数会丢引号 → -32700」，先排除采集方式问题）**一律算异常** | 相同 args 再调一次 | medium；`-32603` 起 high |
| **A2 超时/慢** | 非 deferred 调用 `duration_ms > 2000`；deferred 调用 `error_code==-32000 且 pending_ms 存在`（撞到 30000ms 天花板） | 一次即可（时间类） | medium |
| **A3 pending 超上限** | trace 行 `pending_ms > timeout_ms`（`analyze_mcp_trace.py` 的 `pending_over_ceiling`） | 一次即可 | high（框架不变量被破坏） |
| **A4 响应异常大** | `result_bytes > 1048576`；或同一工具相同 args 的 `result_bytes` 相差 > 10 倍且无解释 | 一次即可 | medium |
| **A5 报成功但状态未变** | 必须**同时**满足 ①请求语义要求「有变化」；②读回值 == **旧值**；③事务前后**对象/场景 sha256 相同**（`.tscn` 文件 sha256 或 `project_read_scene_file_content` 的 sha256） | 必须复现 | **high**（`PLAYBOOK §5/§7.7` 明确：仅比较「读回值 vs 请求值」不足以判定） |
| **A6 多次调用才摸清用法** | ①同一工具出现 `ok:false … 随后 ok:true`，且两次相隔 ≤ 12 次工具调用（`EPISODE_WINDOW=12`）；或 ②同一参数名在同一工具上失败 ≥ 2 次且 `succeeded_calls==0`（`PROBE_MIN=2`）。**必须附完整调用序列与每次的 error_code** | — | low/medium（这是**ergonomics 缺陷**，不是正确性缺陷） |
| **A7 工具间说法矛盾** | 对**同一事实**两个工具给出不同答案，且两侧 args+响应 sha256 都在案。已点名的检测点：①`editor_list_signal_connections` vs `editor_analyze_signal_flow`（连接存在性）；②`editor_get_node_properties` vs `running_game_get_node_properties`（同名属性值）；③`tools/list` 的 `inputSchema` 声明的参数 vs 实现实际接受的参数（例如 `pressed`）；④`editor_get_scene_tree` 的节点路径 vs `running_game_get_scene_tree` 的路径形态 | 必须复现 | medium 起；若影响「能不能写对值」则 high |
| **A8 不确定行为** | 相同 args 连续 N≥3 次，`ok` 或 `result_bytes` 或返回列表顺序不同（`PLAYBOOK §6.4`：同一次构建内 `tools/list` 顺序**必须确定性**；`§6.8` 要求行为确定可复现） | 即证据本身 | medium 起 |

**A 类明确不算异常的情形**（写清以免误报）：`-32602` 缺参/类型错（`PLAYBOOK §6.2` 已接受）；
`-32001` 带 `data.suggestion` 的路径/节点不存在（`§6.1` 已接受）；`--headless` 下的截图 `-32000`+suggestion（E-1/E-2）。

### 4.2 B 类：缺失工具

| ID | 判定标准 |
|---|---|
| **B1 工具名不存在** | trace 出现 `error_code == -32601`（`analyze_mcp_trace.py` 的 `method_not_found`）。**注意区分**：打到 9888 的 `running_game_*`（或 9889 的 `editor_*`）也会 `-32601`，那**不是**缺失工具，是**端点选择错误** → 归 A6，并在建议里写「工具名跨端点不可发现」。 |
| **B2 能力缺口** | 想做一件事而**没有任何工具**能做。必须写全四段：**想做什么 / 试过哪些工具（≥2 个，含 args 要点）/ 每个的实际响应与错误码 / 回退做了什么**。回退产物（手写 `.cs`、手改 `.tscn`、手改 `project.godot`、手工启动进程）必须给出文件 sha256。 |
| **B3 签署建议** | 每条缺失必须给出**建议工具名 + 签名草案**（参数名/类型/必填、返回字段形状），并说明「引擎本来一次能做什么」（`PLAYBOOK §6.10`：顺手性是验收条款）。 |

**本方案预判的高价值候选**（观察者要用 trace 证实/证伪，不可直接照抄当结论）：

1. **没有工具能把 InputMap action 持久化进 `project.godot`**（P-action 路径的失败证据 + E-4）。
2. **没有工具能让被观测的游戏以 `--headless` 起来**（`editor_play_scene` 无此参数）。
3. **没有工具能校验 C# 脚本语法**（若 `project_validate_script` 拒绝 `.cs`）。
4. **没有工具能「连续驱动 + 采样」原子化**（`run_test_scenario` 有 `wait`/`assert` 但**没有采样**；
   `get_node_property_samples` 有采样但**不能同时注入** → 调用方必须开两条连接/两个请求才能做 AC-4，
   是**缺失工具与可合并的双重候选**）。

### 4.3 C 类：可合并（高频 2-3 步序列）

| ID | 判定标准 |
|---|---|
| **C1 频次门槛** | 同一次 `connection` 内，2-gram 或 3-gram 出现 **≥3 次**（`analyze_mcp_trace.py` 的 `bigrams`/`trigrams`，`count>=3`），或该序列占本连接工具调用 **≥10%**。跨连接不算（脚本已按连接分组）。 |
| **C2 合并合理性** | 被合并的步骤必须**必然成对/成组出现**（几乎不存在只用其中一步的场合）；且合并后**不得掩盖中间步骤的错误**。不满足 ⇒ 写成「**不建议合并**」并给理由（这也是有效结论）。 |
| **C3 产出** | 给出合并后**工具名 + 签名草案 + 返回形状 + 风险**（丢掉了哪一步的错误粒度、失败时无法定位是哪一步）。 |

**本方案预判的高频序列**（待 trace 证实）：

1. `editor_open_scene` → `editor_get_scene_tree` → `editor_add_node`（几乎每次改场景都要三步）
2. `editor_set_node_property` → `editor_get_node_properties`（写后读回，D67/`PLAYBOOK §3` 的教训：读回是**必须**的）
3. `running_game_get_node_properties` → `running_game_set_node_property` → `running_game_get_node_properties`
4. `editor_play_scene` → `running_game_find_node_when_available` → `running_game_get_node_properties`
5. `project_create_script` → `editor_set_node_script` → `editor_save_scene`
6. `editor_get_node_properties`（场景）与 `running_game_get_node_properties`（运行时）成对出现（同一个属性问两次）

### 4.4 D 类：可优化

| ID | 判定标准 |
|---|---|
| **D1 多余往返（不可链式喂回）** | 达成「引擎一次调用能做的事」需要 ≥2 次调用，且第二次的**参数完全来自**第一次的响应（可被自动串联）。必须写出「引擎本来能一次给什么」的依据（引擎 API 或契约里已有字段）。 |
| **D2 需要手工字符串处理** | 调用方必须对返回值做**解析/拼接**才能喂下一个工具：例如从 `path` 里抠节点名、把 `Vector2` 的 **String** 形式转成 `{x,y}`（`PLAYBOOK §6.8b` 已点名 `Vector4`/packed 是 String 而 `Vector2` 是对象 → 形状不一致就是 D4/D2）、手拼 `res://` 前缀、手拼 GDScript 字符串。**判据**：日志里出现「人工把 X 改成 Y 再发下一个请求」。 |
| **D3 错误消息不足以自纠** | `ok:false` 的消息**未**同时给出 ①哪个参数（精确到 `steps[i].strength` 这种粒度）②期望形态 ③下一步怎么做（`data.suggestion`）。**判据**：失败之后调用方**又试探 ≥2 次**才成功（与 A6 联动）；反之，若消息含 suggestion 且**下一次调用直接成功** ⇒ 不算 D3（正面案例也要记，用于对比）。 |
| **D4 参数/返回形状不对称** | 同一语义在不同工具用不同形状（对象 `{x,y}` vs 数组 `[x,y]` vs 字符串 `"1,2"`；`shape_params` 的 `{"size":{"x":32,"y":32}}` 这种嵌套）；或同一工具的**读**与**写**形状不同（写 `{x,y}` 读回 String）。 |
| **D5 契约/文档缺口** | `tools/list` 的 `inputSchema` **未声明**实现实际接受（或实际必需）的参数。已点名的候选【源码依据】：①`running_game_run_test_scenario` 的实现读 `steps[i].pressed` / `steps[i].strength`（`running_game_test_execution.cpp:141-148`），但契约的 `steps[].properties` **只列了** `action/expected/keycode/node_path/operator/property/seconds/text/type`；②`running_game_play_input_recording` 的 `events[]` **没有 item schema**（调用方只能靠猜，且另一个工具 `run_test_scenario` 的 `keycode` 不接受 `physical`，而录制事件接受 `physical` → 两工具形状不一致）。**判据**：`tools/list` 原文（sha256）+ 一次成功调用的 args 二者并列。 |
| **D6 端点/发现性** | 工具打到错误端点才 `-32601`、或 `tools/list` 里两个进程的工具面差异**无法从工具自身发现**（调用方必须先知道「这一点是 game scope」）。判据：一次 `-32601` + 随后同 args 打另一端点成功。 |

**排序与取舍纪律**（§D 汇总者会用到）：按 **证据强度 × 影响面** 排序；证据强度 =
「带 sha256 的响应 + trace 行号」> 「带 sha256 的响应」> 「仅 trace 行」> 「日志自述」。
明确标出**不建议做**的项及理由。

---

## 5. 纪律（§B/§C 都必须遵守；违反记入 findings 的 `violations`）

1. **绝不碰 9877**：任何时刻不得占用/杀/重启用户 Godot（PID 会变）。试测只用 **9888/9889**；
   每轮开始与结束各跑一次 `netstat -ano | findstr LISTENING | findstr :9877`，把结果贴进日志。
2. **不得修改 `modules/mcp_server/**` 的任何实现**（`tools/**`、`tests/**`、`contract`、`scripts` 的实现代码）。
   §C 只读；§B 只写 `%TEMP%\mcp-racing-test\` 与自己的报告。**发现缺陷不修**。
3. **证据不落管道**：响应体一律 `curl.exe -s -o <file> --data-binary @file` 落盘后算 sha256
   （`PLAYBOOK §7.1`：曾发生 `Out-File` 把非 ASCII 塌成 `?` 导致验收 fail）。
4. **`.ps1` 一律纯 ASCII**（PowerShell 5.1 按 ANSI 读无 BOM 脚本）；工程文件 UTF-8 **无 BOM**。
5. **不做竞争性规范**：只写任务书指定的报告与 `%TEMP%` 下的证据；不得在仓库新建
   `REQUIREMENTS.md`/`DESIGN-*.md` 之类文档（`PLAYBOOK §5/§7.2`）。
6. **诚实**：失败不抹；无法复现的旧结论要**显式撤回**并标 `append-only 勘误`；区分实测/推断。
7. **D86**：所有结论标测自的提交（§0 的 `f34ee937f3`）；引用他报告结论前先复测。
8. **构建绑门**：任何「跑门/跑测试」前先确认二进制 hash 前缀 == `git rev-parse --short HEAD`（`PLAYBOOK §3` R-1）。
   **禁止并发跑两个 scons**（D62）。

---

## 6. 交给 §B / §C 的交接清单

**§B（开发者）必须产出**：`docs/reports/RACING-DEV-LOG.md` + 真能跑的 `%TEMP%\mcp-racing-test\` 工程。
逐条日志格式：`时间 / 工具名 / 参数要点 / 结果（ok 或错误码）/ 学到什么`；回退条目按 §4 B2 四段写。

**§C（观察者）必须产出**：`docs/reports/RACING-OBSERVATIONS.md`（边观察边追加），至少给出
≥3 条 **A6（多次调用才摸清用法）**、≥2 条 **B（缺失工具）**、≥2 条 **C（可合并）**、≥2 条 **A7/A5（异常或矛盾）**；
**没有就如实说没有**并列出查过的信号（不得凑数）。

**§D（汇总者）必须自己复算**：回到 `trace-editor.jsonl` / `trace-game.jsonl` 原文，给出行号 + sha256，
把实测与推断分开，并对 §C 的结论**纠错**（`analyze_mcp_trace.py` 的输出要与人工核对）。

---

## 7. 本文的自我约束声明

- 本文**只**依据：`docs/tools_list.renamed.json`（sha256 见 §0）、`tools/**` 与 `mcp_*.cpp/h` 的**只读**阅读、
  `scripts/analyze_mcp_trace.py`、`PLAYBOOK-group-port.md`、`TASK-039` 任务书。**没有运行任何试测**，
  因此除 §0 表与 `git status` 外**全部结论都是【源码依据】或【推断】**，必须在试测中验证。
- 本文**未**修改、也**未**建议修改 `modules/mcp_server/**` 的任何实现。
- 本文**未**触碰 9877，**未**启动任何引擎进程。