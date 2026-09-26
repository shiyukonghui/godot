# REPORT-066 — A 角色：把 C# 打砖块补成**完整可跑**，并在其上实测 §A 六条判据

> 任务书：`docs/tasks/TASK-066-csharp-breakout.md`（A 角色一节）；手册：`docs/tasks/PLAYBOOK-group-port.md`。
> 依据：`docs/reports/BREAKOUT-FINDINGS.md` §5.3/§6（第 2 轮 F1）、`docs/reports/BREAKOUT-FINDINGS-R3.md` B7（仍空白）。
> 本报告只记录发现，**不修改任何模块实现**（`git status` 见 §6）。

## 0. 元信息与锚点（D86）

| 项 | 值 |
|---|---|
| 角色 / 任务 | A（开发者）/ TASK-066 |
| 状态 | **完成**：工程完整可跑；六条判据逐条有实测；活链在窗口化游戏进程上跑通；无阻塞 |
| **证据提交锚点** | `40dad5a6df`（"TASK-066 A: complete the C# breakout fixture and measure all six criteria"，237 文件 / 5431 行，全部在 `modules/mcp_server/docs/**` 与任务书） |
| 报告提交锚点 | 首版 `edbcfcb4c5`；末尾的「记录锚点」小提交为最终版（`git log --oneline -1 -- modules/mcp_server/docs/reports/REPORT-066-csharp-breakout.md`）。三个 session 的 checks 结论都不随其后提交漂移：证据文件在各自的 `<leaf>__<seq>__<sha8>` 名字里自带内容摘要 |
| 二进制（mono） | `bin\godot.windows.editor.x86_64.mono.console.exe`，`--version` = `4.8.dev.mono.custom_build.770872998` |
| 仓库 HEAD 开工时 | `10fdc60289` |
| **模块实现是否随 HEAD 漂移** | **否**。`git diff --stat 7708729982..HEAD -- modules/mcp_server/tools modules/mcp_server/tests modules/mcp_server/docs/tools_list.renamed.json modules/mcp_server/docs/tool-rename-map.json modules/mcp_server/scripts` 只列 `scripts/mcp065b_*.ps1|py`（6 个**新增**脚本，1520 行），`tools/`、`tests/`、契约 json 全部**零差异**。故二进制 7708729982 对模块行为与契约仍然有效；**未重建二进制**（与 R3 §7.1 同口径，但此处是**自己复测**过的，不是引用） |
| 端口纪律 | 9877 在开工前与收尾时都断言**无监听**（`netstat -ano | LISTENING` 解析）；只用 9888（编辑器）/ 9889（游戏）；只 stop 自己 `Start-Process` 的 PID |
| 契约 | 编辑器 9888 `tools/list` = **153** 条，游戏 9889 = **72** 条（契约 176 按 channel 拆分的线上事实）；`docs/tools_list.renamed.json` 未改 |
| MCP 请求数 | **99**：`tools/call` 97（session1 32 / session2 33 / session3 32）+ `tools/list` 2 |

## 1. 交付物：`%TEMP%\mcp-breakout-cs\proj`（C# / mono）

### 1.1 文件与 sha256（`.godot/` 除外）

| 文件 | 字节 | sha256 |
|---|---|---|
| `project.godot` | 806 | `4973072b5a7432cb00f65e5c2099e346c9d30c3760d4f1c9317a15a514627f2b` |
| `scenes/main.tscn` | 2890 | `d33b89311f018f41861e9a2add9b8afa2fb707c32ae470cd83925570bdb67b35` |
| `McpBreakoutCs.csproj` | 270 | `2d35333d19e4557de7337020ad656bf724622dee9560cf84cb3b18feed231751` |
| `NuGet.config` | 304 | `b1654e727e4ed844e47bee54ffb3304afcc38fc406fec761265d719c47b83d28` |
| `scripts/Main.cs` | 2389 | `14c4aaa24dd1b43fdc16368f87b8aa3539a2c97d10d91fc70d087ecc50105aae` |
| `scripts/Paddle.cs` | 795 | `14934efb2b3a076db8133f7915fc7c1a3c3e3ef2ef20a181cb4f32562c107cd2` |
| `scripts/Ball.cs` | 2264 | `77385665f98001d60e00d728f98e9ebe9223f216cea12139c28b36ca00645c5a` |
| `scripts/Brick.cs` | 343 | `817c1924f55056e31bb7fa2c1b2208c00c67b4fe32895aa8790e9d4581ede48a` |
| `scripts/CsVerdict.cs`（判据②探针，**不挂任何节点**） | 157 | `427219c58a2bd2b38f59e147d170beece388c852f30a8e5531b22b303f3fa05f` |
| `scripts/CsVerdict2.cs`（判据②第二探针，**从未构建过**） | 170 | `f5c6744908a4545f9b20b98a25836a1e1063a23afb0962792737ce67a3e9c57a` |

构建产物：`.godot\mono\temp\bin\Debug\McpBreakoutCs.dll`，19968 B，`project_build_csharp` exit 0（响应 sha256 `69cb9dd4743745d81bd0ba62d6d4d9cf4f96b9c5b16aa13d55c0880bc3182862`）。

### 1.2 场景（**一次** `editor_add_nodes_batch{resolve_within_batch:true}` 建成，16 节点）

```
Main (Node2D, Main.cs)                     <- 场景根
├─ Paddle (Node2D, Paddle.cs)              position (300,560)
├─ Ball (Node2D, Ball.cs)                  position (300,320)
├─ WallLeft / WallRight / WallTop (ColorRect)
├─ Bricks (Node2D)
│  ├─ Brick0 (Node2D, Brick.cs) ─ BrickRect0 (ColorRect)
│  ├─ Brick1 (Node2D, Brick.cs) ─ BrickRect1 (ColorRect)
│  └─ Brick2 (Node2D, Brick.cs) ─ BrickRect2 (ColorRect)
├─ HUD (CanvasLayer)
│  ├─ ScoreLabel (Label)    text "Score: 0"
│  └─ MessageLabel (Label)  text "ready"
└─ ProbeTimer (Timer, one_shot, 不 autostart)
[connection signal="timeout" from="ProbeTimer" to="." method="OnTimerTimeout"]   <- 判据⑤ 的 user 连接
```

`[input]`：`paddle_left` / `paddle_right` / `launch` / `restart`（`editor_add_input_action` 写入，`event_count:0`，靠引擎按**名字**匹配注入的 `InputEventAction`）。
另：`[physics] common/physics_ticks_per_second=60`（`project_set_setting`）。

### 1.3 「完整可跑」的实现口径（**逐条显式声明**）

| 项 | 实现 | 依据 / 诚实边界 |
|---|---|---|
| 挡板移动 | `Paddle._Process` 读 `Input.IsActionPressed("paddle_*)`，`Position.X` 夹到 [48,1104]，`Moves`/`LastDir` 计数 | 输入→运动的唯一路径就是引擎 InputMap；`running_game_run_test_scenario` 注入的是 `InputEventAction` |
| 球移动 | `Ball._Process` 速度积分（`Vel`），左右墙 / 顶反弹，落底 y>648 → `Main.LoseLife()` + 回位 | 与 R3 的 GDScript fixture 同构 |
| **碰撞** | 每帧 **AABB 邻近测试**：`|brick.X-Ball.X|<40 && |brick.Y-Ball.Y|<24` → `HitBrick()` | **不是**物理引擎回调。理由：scratch 工程里 `CollisionShape2D` 需要的 `Shape` **子资源**无法经 `editor_add_nodes_batch` 的 `properties` 表达（设置 `shape` 需要 `SubResource`/`editor_add_resource_to_node_property`，本轮未引入）。这是**能力边界**，不是缺陷；写清以免被读成「做了物理碰撞」 |
| 命中后砖块消失 | `Brick.QueueFree()`（连同 `BrickRect*` 视觉子树）；另有 `Brick.Hit()` 公开入口 | 消失由 `running_game_find_nodes_by_script` 计数 + 解析后的场景树双重验证 |
| 计分 | `Brick` → `Main.AddScore(10)` → `Score`/`BricksHit` → `Main.UpdateHud()` 写 `HUD/ScoreLabel.text` | 分数同时可在节点属性与 HUD Label 两处读回 |
| 胜负 / 重开 | `State ∈ {ready, playing, won, lost}`；`Bricks` 子节点清空 → `won`；`Lives<=0` → `lost`；`restart` 动作 → `Restart()` 复位 | 三项都在**进程内**被观测到（§3） |
| HUD | `ScoreLabel` + `MessageLabel`（`State`） | |
| C# 驱动方式 | 全部用 `_Process`（任务书要求），不依赖 `_PhysicsProcess` | `project.godot` 里的 `physics_ticks_per_second` 只是判据① 的写入对象 |

> 为了让「第一次命中砖块」**确定**，session 3 在发射前用 `running_game_set_node_property` 把 `Ball.Vel` 置为 `{x:0,y:-260}`、`Ball.position` 置为 `(300,320)`（场景默认带 `x=90` 的横漂，第一次上冲会擦过 Brick0 的边缘）。这是**测试前置**，已在证据里留痕，不是伪造。

## 2. §A 六条新能力判据 —— 逐条实测

证据根：`docs/reports/evidence/task066/`。下面每条给「判据 / 结论 / 证据文件 + sha256」。

### ① 注释保全 —— **通过**（并定位到真正的破坏者）

构造链（`session1-build/`，project.godot 的 6 个快照全部落盘）：

| 快照 | 事件 | 字节 | sha256 | `; mcp066 comment N of 4` |
|---|---|---|---|---|
| A | bootstrap 手写（4 行探针注释，`[input]` 非末节） | 734 | `fc809e46cbeadb70fdea33b3125d9b1e6265fcb83592dbd37fadbca09ad39a9a` | 4 |
| B | `--import` 之后 | 734 | 同上（**逐字节未变**） | 4 |
| D | **窗口化编辑器启动之后** | 620 | `fa46bf8d2abf4dc322f8c75b70f20b4ce093894806656583946d4beacfe301f8` | **0** |
| E0 | 在编辑器已运行时重新写入 4 行注释（判据基线） | 716 | `6622ae3bb6f4c312414107bdc6b46ae95670c9dda77c5e7cf0b0176cd721ac6c` | 4 |
| E1 | 4×`editor_add_input_action` + 1×`project_set_setting` 之后 | — | `64200836a788c33db055d55a7a53ea4ad478ba228d8600216a9a8867db84c42b` | **4** |
| E2 | 对照组 `project_add_autoload` + `project_remove_autoload`（文档化的**整文件写**）之后 | 806 | `4973072b5a7432cb00f65e5c2099e346c9d30c3760d4f1c9317a15a514627f2b` | **0** |

- **通过**：E0→E1 文件确实变了（`c1_file_really_changed`），且 4/4 注释逐字幸存（`c1_all_four_probe_comments_survived`）；引擎侧独立确认四元 action 都在（`editor_get_input_actions` 的 **parsed `actions[]` 集合**含 `paddle_left/paddle_right/launch/restart`，`count=93`，**没有用文本包含判断**），且两次读取的 action 集合逐字相同（`c1_action_set_is_idempotent_across_calls`）。
- **对照组有判别力**：同一文件、同一会话，`project_remove_autoload`（整文件写）把 4/4 注释**全部**抹掉 → 差异可**归因**到「分段写 vs 整文件写」，不是环境噪声。
- **新发现（见 F-066-2）**：**窗口化编辑器的启动**本身就把 `project.godot` 整文件重写（引擎自己的定长头 + 全量设置），而**同一工程的 `--import` 不会**。第 1 轮之所以没踩到，是因为那时的编辑器是 `--headless`。这条**改变了判据① 的构造方式**：探针注释必须在编辑器启动**之后**写。

### ② C# 真结论 —— **通过**（三类别齐全，含编译器原文）

在**同一个编辑器进程**内按「未构建 → 构建失败 → 修好未构建」推进，最后重启编辑器读 `ok`（`session2-verify/c2_verdicts.json` + `calls/`）：

| 步骤 | 调用 | 结论 | 证据 |
|---|---|---|---|
| a | `project_validate_script{CsVerdict.cs}`（session1 已构建且程序集已加载） | **`ok`**：结果体 `{path,valid:true,message:"Compiled: the loaded .NET assembly contains a build of this source, and the file has not been modified since that build"}` | `c2_a_validate_ok_baseline__0021__22e19d10.response.json` |
| b | `project_edit_script` 写坏 → **不构建** → 再 validate | **`not_compiled`**：`-32000`，message `Cannot validate 'res://scripts/CsVerdict.cs': no build of this source is loaded, so the file was not compiled and no 'valid' value is published`；`data.suggestion` 逐字含 **"This is 'not compiled', which is not 'does not compile'"**，并指名 `CSharpScript::is_source_newer_than_assembly()` | `c2_b_validate_changed_not_built__0023__0757ff49.response.json` |
| c | 另建 `CsVerdict2.cs`（本会话从未构建）→ `project_build_csharp` → **exit_code 1** → 复数 validate 两个文件 | **同一条响应里 `invalid` 与 `not_compiled` 并存**：`count=2 invalid_count=1 not_compiled_count=1`；`CsVerdict.cs → category=invalid, valid=false, error_text` 含 `CsVerdict.cs(7,22): error CS1040: …` 与 `CsVerdict.cs(8,5): error CS1002: 应输入 ;`（**诊断码 + 文件(行,列)**，真编译器原文）；`CsVerdict2.cs → category=not_compiled, valid=null` | `c2_c_validate_both__0026__163242c0.response.json`、`c2_c_build_fails__0025__b0f7004d.response.json` |
| d | 单数 validate（同一 invalid 文件） | **`invalid` 以「结果」而非「拒绝」返回**：结果体 `{valid:false, message:"Compilation failed. …", error_text:"…error CS1040…"}` | `c2_c_validate_singular_invalid__0027__65e8dc90.response.json` |
| e | 修好 `CsVerdict.cs` → **不构建** → validate | 仍 **`not_compiled`**（源码比已加载程序集新；改对 ≠ 变有效） | `c2_d_validate_fixed_not_built__0029__c4804806.response.json` |
| f | `project_build_csharp` 成功（exit 0）→ **重启编辑器** → validate | **`ok`**（`valid=true`，同上 Compiled 文案） | `c2_f_validate_ok_after_restart__0032__69b79de7.response.json` |
| g | 重启后全量 `project_validate_scripts` | `valid_count=6 invalid=0 not_compiled=0 count=6` | `c2_g_validate_all_after_restart__0033__915e0e21.response.json` |

**诚实边界（必须与结论同读，与 R3 P2g 一致）**：`ok` 只在**本进程已加载构建好的程序集**时可达；`project_build_csharp` 是另起 `dotnet build` 子进程，**不会**让正在跑的编辑器加载新程序集 —— 所以 「构建成功后同一进程仍可能答 `not_compiled`/旧结论」，必须重启编辑器（本报告 a/f 两步就是这条的直接证据）。

### ③ 批量父子 —— **通过**

`editor_add_nodes_batch{nodes:[16], resolve_within_batch:true}` **一次调用**建成 §1.2 全树：

- `status:"ok"`、`count=16`、`errors:[]`，追踪里只有 1 行该调用；响应 sha256 `f74e4934…`（`c3_add_nodes_batch__0005__f74e4934.response.json`）。
- `parent_source` 两值都出现且**可区分来源**：`scene=8`（Paddle/Ball/3 墙/Bricks/HUD/ProbeTimer）、`batch=8`（Brick0..2、BrickRect0..2、ScoreLabel、MessageLabel）、`missing=0`。
- 批内父子确实被解析：`BrickRect0` 的 `parent_path="Bricks/Brick0"`、`parent_source="batch"`。
- 另一个工具独立读回（`editor_get_scene_tree`）能看到 `BrickRect0/ScoreLabel/Paddle`。

### ④ 批量挂脚本 —— **通过**

`editor_set_node_script_batch{node_paths:["Bricks/Brick0","Bricks/Brick1","Bricks/Brick2"], script_path:"res://scripts/Brick.cs"}`：

- `status:"ok" count=3`，`attached` 三项全 `attached:true`，`errors:[]`，每项带 `previous_script_path:""`（**挂之前确实没有脚本**，不是「本来就挂着」）；响应 sha256 `b211c5e7…`（`c4_set_node_script_batch__0014__b211c5e7.response.json`）。
- 单数 `editor_set_node_script` 完成 Main(`node_path:"."`)/Paddle/Ball 三处；响应 sha256 `b441f313…` / `1425326d…` / `24d28f9c…`。
- **落盘验证**：`editor_save_scene` 后 `project_read_scene_file_content` 读回的 `.tscn` 里 4 条 `[ext_resource type="Script"]`（Main/Paddle/Ball/Brick）与 6 处 `ExtResource("…")` 引用齐全，三块砖共用同一条 `Brick.cs` ext_resource。
- **口径纠正（复现 R-3）**：`Brick.cs` 在 `.tscn` 文本里只出现 **1** 次。任何「`Brick.cs` 出现 ≥18 次」式的**字面**判据在 Godot 的 `.tscn` 格式下**构造上不可达**（1 条 ext_resource + N 处 `ExtResource(id)`）。
- **路径基准**（契约 176）：本批 `node_paths` 用 `Bricks/Brick0`（**相对编辑场景根**）；`/root/Main/...` 在 176 上**已被拒绝**（数据源 `editor_set_node_script_batch.cpp:411` 的描述与 `find_node()` 的 `.`/根名规则）——第 2 轮 D-1 的「两工具基准不一致」在 176 上已收口。

### ⑤ `scope` 收窄 —— **通过**（set 层面重算，不是数字对照）

先造出**真的 user 连接**：`editor_connect_signal{source_path:"ProbeTimer", signal:"timeout", target_path:".", method:"OnTimerTimeout"}` → `connected:true, persisted:true`，随后 `editor_save_scene` 把它写进 `.tscn` 第 89 行：`[connection signal="timeout" from="ProbeTimer" to="." method="OnTimerTimeout"]`。

- `scope ∈ {all,user,internal}` **各 3 次**（共 9 次），**每次**都由原始响应体解析出连接集合（`source|signal|target|method`）后**重算**：
  - `all=207  user=1  internal=206`；**交集=0**；**并集=207 且等于 default 集合**（双向往返差集都为空）。
  - `counts` 与重算集合逐项一致（`207/1/206`）。
  - 每 scope 的 3 次响应体 sha256 **唯一值为 1**（byte-stable）。
  - `user` 的 method 全不含 `::`（`OnTimerTimeout`）；`internal` 全含 `::`（样本 `ScriptEditor::_queue_update_list`、`SceneTreeEditor::_node_script_changed`）。
  - 不传 `scope` 的默认调用与显式 `scope:"all"` **响应体逐字节相同**（同一个 body sha8 `f21a9805`）。
  - `signal_name:"timeout"` + `scope:"user"` 命中那条 user 连接（1 条），不越界。
- 证据：`session2-verify/c5_scope.json`（含 207 条集合、交集、并集、每 call 的响应 sha256）、`calls/c5_{all,user,internal}_{1,2,3}*.response.json`。
- **诚实标注**：`c5_connect_signal` 返回 `already_connected:true` —— 因为本 session 的第一版运行已把该连接持久化进场景；工具**没有**谎称这次是它建的（这是正面行为，见 F-066-7）。
- 同一工程的 `session1`（未建 user 连接时）也给了一组：`all=206 user=0 internal=206 counts=206/0/206`（`session1-build/calls/c5_scope_*.response.json`）。

### ⑥ 捕获的诚实性（窗口化 `changed:false` / `changed:true`）—— **通过**

**编辑器（窗口化，`session2-verify/c6_capture.json`）**：argv = `-e … --mcp-capture=every_call --mcp-capture-dir=res://mcp066_shots --mcp-capture-viewport=2d --mcp-capture-scale=2`

| 调用 | 类型 | `changed` | 证据 |
|---|---|---|---|
| `editor_get_scene_tree` ×2（**只读**，参数同一对象） | 读 | `false` / `false` | `c6_read_only_a__0015__152a0e2c` / `c6_read_only_b_replay__0016__fd35f2d0` |
| `editor_set_node_property{WallTop,position,{0,40}}` | **真变化** | **`true`**，`changed_pixels=2660/1334144`，`ratio=0.00199…`，`frames_waited=1` | `c6_real_change__0017__74ab2771` |
| 同参再调一次（**同值重放**，工具自己报写入成功） | 幂等 | **`false`**，`changed_pixels=0` | `c6_same_args_same_value_replay__0018__6e3d1794` |
| `editor_analyze_screenshot_diff`（读捕获自己写的两张 PNG） | 第二路 | `changed_pixels=2660/1334144`（与捕获行**逐位一致**）；重放对 `identical:true, changed_pixels:0` | `c6_tool_diff_real_change__0019__923f53be` / `c6_tool_diff_replay__0020__807da8fc` |

PNG 已复制入库：`shots/real_change.{before,after}.png`（sha8 `085c1024` vs `94a2e8ab`，**不同**）、`shots/replay.{before,after}.png`（两者**同** `94a2e8ab`）；两次调用的 `arguments` 由**同一个对象**序列化，sha256 `e32481fe1b680177…`。

**游戏进程（窗口化 9889，`session3-game/g8_game_capture.json`）**：

| 调用 | `changed` | 证据 |
|---|---|---|
| `running_game_get_scene_tree` ×2（只读） | `false` / `false` | `g8_read_only_a__0030__d08be2e6` / `g8_read_only_b_replay__0031__4a5a96a8` |
| `running_game_set_node_property{WallTop,position,{0,160}}` | **`true`**，`changed_pixels=4544/186624`，`frames_waited=1` | `g8_real_change__0032__9082ffd8` |
| 同参同值重放 | **`false`**，`changed_pixels=0` | `g8_same_args_same_value_replay__0033__3ee1911c` |

`status=done`、`scale=2`（游戏侧），`viewport="game"`（见 F-066-4）。

> **一版**构造失误（已回退，见 §5 F-7）：最初在游戏进程上移动的是 `Paddle`（纯 `Node2D`，**不可见**），`changed` 正确地是 `false`。这恰好说明 `changed` **不是**「工具调用成功」的同义词；换成可见 `ColorRect`（`WallTop`）后 `true`。

## 3. 游戏侧活链 —— 每条**前后两步**且 sha 不同

`session3-game/session3_summary.json` 的 `pairs` 与 `game_live_chain.json`（32 次游戏侧调用全部 `id`+`result`，**0 个 `-326xx`**）。全部为**窗口化**游戏进程（**无** `--headless`）。

| # | 断言 | 前 sha256 → 后 sha256 | 实测值 |
|---|---|---|---|
| 1 | 注入 `paddle_right` → 挡板**真的移动** | `d6782058…` → `ee40720b…` | `Paddle.position.x 300.0 → 513.37`，`Moves 0 → 1458`，`LastDir=right` |
| 2 | 另一工具**逐帧**读回运动 | — | `running_game_get_node_property_samples` 24 帧：`x 320.98 → 482.01`，`distinct_x=24`，**单调不减=True**（不是瞬移） |
| 3 | 进程内断言（release + `assert Paddle.Moves gt 0`） | — | `all_passed=true passed=1 failed=0 errors=0` |
| 4 | 注入 `launch` → 球**真的移动** | `7cc29c7b…` → `c5832997…` | `Ball.position.y 320.0 → 218.97`；18 帧采样 `y 302.65 → 229.01` **严格不增** |
| 5 | **砖块真的消失**（节点集合减少） | `7b939f36…` → `92ab8499…` | `running_game_find_nodes_by_script("res://scripts/Brick.cs")`：`3 → 2`，幸存 `Brick1,Brick2` |
| 6 | **分数真的变**（HUD Label） | `577d5cc1…` → `86731092…` | `HUD/ScoreLabel.text "Score: 0" → "Score: 10"` |
| 7 | 进程内断言（wait 1.2s + `assert Main.Score gt 0`） | — | `all_passed=true passed=1 failed=0 errors=0` |
| 8 | 主节点状态与 Label 一致 | — | `Main.Score=10 BricksHit=1 State=playing Launched=true` |
| 9 | 消失的砖块从**整棵树**里消失 | `9ce28bdc…` → `b7b387c8…` | 解析后的树：`Brick0` 前=True 后=False；`Brick1/Brick2` 仍在 |
| 10 | **胜利**：清掉剩余砖块 → `won` | `3c5d1f06…` → `50b6f517…` | `Main.State=won` |
| 11 | **失败**：`Lives=1` + 球过底 → `lost` | `50b6f517…` → `05f4901c…` | `Main.State=lost`，`Lives=0` |
| 12 | **重开**：注入 `restart` | `05f4901c…` → `fcffd5f4…` | `Score=0 Lives=3 State=ready`，进程内两条 assert 全过 |

> 判据 1/4/5/6/9/10/11/12 都是「动作前一次调用、动作后一次调用」的**两步**证据，且**两步响应 sha256 必然不同**（脚本里逐条断言）。1、5、6 还各自有**第三个独立工具**读回（samples / 整棵树 / 主节点属性），避免「只看被测响应」。

## 4. 发现（**只记录，不修改实现**）

| # | 现象 | 期望 | 实际 | 严重度 | 证据 |
|---|---|---|---|---|---|
| **F-066-1** | **`project_list_scripts` 在 Mono 工程里对 `.cs` 完全失明** | 描述是「列出所有脚本文件」；且 `editor_set_node_script_batch.cpp:237` 的报错文案叫用户「用 `project_list_scripts` 列工程脚本」 | 5 个可读 `.cs` 存在时返回 `{"count":0,"scripts":[]}`；同进程 `project_get_filesystem_tree{path:"res://scripts"}` 能看到 `Main.cs`。根因：walker 只收 `.gd`/`.gdshader`（`project_read_files.cpp:172`，大小写敏感 `ends_with(".gd")`） | **minor–major**（ergonomics + 文案不诚实：这是「照它开工会白走一轮」的那类） | `session1-build/calls/list_scripts__0012__481c0ea5.response.json`（`count:0`）、`list_scripts_crosscheck_fs_tree__0013__58999fa3.response.json` |
| **F-066-2** | **窗口化编辑器启动本身会整文件重写 `project.godot`**，抹掉手写注释；**同一工程的 `--import` 不会** | 注释在编辑器会话之间应存活（或工具应能告知） | bootstrap 734 B（4 注释）→`--import` 后 734 B **逐字节不变** →编辑器起来后 620 B（引擎定长头 + 全量设置，注释 0） | **medium**（**判据①/任何注释保全构造的前置事实**；第 1 轮用 `--headless` 时没暴露） | `session1-build/pg_{A,B,D}_*` 六个快照；`process-logs/editor.out.log.txt` |
| **F-066-3** | **单数 `project_validate_script` 与复数 `project_validate_scripts` 的形状不同**，且「未构建」在单数上不是结果体而是 `-32000` | 同一判据在同一端点上应有统一读法；复数的 `category` 字段在单数上不存在 | 单数：`ok` → 结果体 `{path,message,valid:true}`；`invalid` → 结果体 `{valid:false,message:"Compilation failed…",error_text}`；`not_compiled` → **`-32000`**（message `no build of this source is loaded…`、`data.suggestion` 含 "This is 'not compiled', which is not 'does not compile'"）。复数：`results[].category ∈ {ok,invalid,not_compiled,…}` + 计数 | **minor**（口径差异有文档化的 `suggestion`，但对调用方是三个分支；建议在描述里点明） | `c2_a_…22e19d10`、`c2_b_…0757ff49`、`c2_c_validate_singular_invalid__0027__65e8dc90`、`c2_c_validate_both__0026__163242c0` |
| **F-066-4** | **游戏进程的捕获 `viewport` 恒为 `"game"`**，`--mcp-capture-viewport=2d` 在游戏侧被忽略 | 传了 `2d` 应回 `2d` | 游戏侧 `viewport="game"`；编辑器侧同样参数回 `"2d"` | **不是缺陷**（`mcp_capture.cpp:375-376` 明写「一个游戏进程只有一个窗口」）。但 **B1 类记录必须知道**：不要据 `viewport` 字段判断「游戏端窗口化捕获族失败」 | `session3-game/g8_game_capture.json`；`mcp_capture.cpp:376` |
| **F-066-5** | **只有 `input` 步骤、没有 `assert` 的 `running_game_run_test_scenario` 返回 `all_passed:false`**（`passed=0 failed=0 errors=0`） | 无断言 ⇒ 不应读成失败 | 实测 `all_passed:false` | **minor**（易被读成失败；本报告因此每条都用**显式 `assert` 步骤**） | `g2_inject_paddle_right__0004__2f1c2476`、`g3_inject_launch__0013__820e891c`（均 `all_passed:false, passed:0, failed:0, errors:0`） |
| **F-066-6** | **`.tscn` 的脚本共享形态让「按字面次数」判据不可达**（复现 R-3） | — | 3 块砖共用 **1** 条 `[ext_resource …Brick.cs]` + 6 处 `ExtResource("4_beafk")`；`Brick.cs` 在文件里出现 **1** 次 | informational（**判据设计缺陷**，非工具缺陷） | `session1-build/main_tscn_after_build__0001__bfd5b965.tscn` |
| **F-066-7** | `editor_connect_signal` 在连接**已持久**时诚实回 `already_connected:true`（不冒功） | 应区分「本次建立」与「本来就成立」 | 返回 `{"already_connected":true,"connected":true,"persisted":true,…}` | **正面样本**（不建议改） | `session2-verify/calls/c5_connect_signal__0002__70cf155b.response.json` |

> **记一条不构成缺陷的观测**：`project_build_csharp` 的失败输出与 `error_text` 里编译器中文诊断在 **Windows 控制台（GBK）** 下显示为乱码，但**落盘 JSON 里的字节是正确的 UTF-8**（`error CS1040: 预处理器指令必须作为一行的第一个非空白字符出现`）。采集/比对一律走文件字节，不要走控制台管道（PLAYBOOK §7.1）。

## 5. 回退记录（任务书要求逐条记「想做什么 / 试过什么 / 回退是什么」）

共 **9 条**，其中 **6 条导致重跑**；每条都留了失败的构造与最终证据。

| # | 想做什么 | 试过什么 | 发生了什么 | 回退成什么 |
|---|---|---|---|---|
| F-1 | 用「bootstrap 时写注释 → `--import` → 编辑器 → MCP 写」链测判据① | 一次性写入 + import + 全链 | 基线的注释数 **0**：注释在会话开始前就没了 | 把 project.godot 的 A/B/D/E0 快照做成**因果链**；发现真凶是**编辑器启动**而非 import；探针注释改为**编辑器起来之后**再写 → 判据① 通过（§2①） |
| F-2 | 用文本包含判断 `editor_get_input_actions` 里有 action | `$raw -match '"paddle_left"'` | **假失败**：内层 JSON 被转义成 `\"paddle_left\"`；这正是 PLAYBOOK §7.4 明令禁止的文本包含判断 | 解析 `result.content[0].text` → `actions[]` **名字集合**做成员判定 |
| F-3 | 比较两次 `actions[]` 是否相同 | `@(...) -join ',' -eq $a -join ','` | PowerShell 运算符优先级把它变成「空数组当分隔符」→ **异常中止整轮**（summary 未写出） | 先各自算成字符串再 `-eq`；并把每轮输出重定向到日志文件再判定 |
| F-4 | 用集合运算证明 `user ∪ internal = default` | `$setUser + $setInt \| Sort -Unique` | `union=1`：函数返回的单元素数组被 PowerShell **解卷成标量**，`+` 变成字符串连接 | 每次取值都套 `@(...)`：`@(@($setUser) + @($setInt) …)` → `intersection=0, union=207`（§2⑤） |
| F-5 | 用 `category` 读单数 `project_validate_script` | 与复数同一套断言 | 单数结果体没有 `category`；`not_compiled` 是 `-32000` 而非结果体 → **4 条假失败** | 单数按 `valid`/`message`/`error_text` 判，`not_compiled` 判 `-32000` + message；并把「单数/复数形状差异」登记为 F-066-3 |
| F-6 | 用 `-match '"Brick0"'` 判砖块是否还在树里 | 在**原始响应文本**上匹配 | 前后都 `False`：内层 JSON 的引号被转义 | 改为解析成对象再 `ConvertTo-Json -Compress` 后匹配裸名（§3 #9） |
| F-7 | 在游戏进程上制造 `changed:true` | 移动 `Paddle` | 正确结果却是 `changed:false` —— `Paddle` 是纯 `Node2D`，**不渲染任何像素** | 换成可见的 `ColorRect`（`WallTop`）→ `changed=true, changed_pixels=4544`（§2⑥） |
| F-8 | 断言游戏侧 `viewport == "2d"` | 与编辑器同一断言 | 游戏侧恒为 `"game"`（设计如此） | 期望改为 `game`，并把 `mcp_capture.cpp:376` 的依据写进断言文本（F-066-4） |
| F-9 | 断言 `.tscn` 里 `ExtResource` 出现 ≥7 次 | 早先的估计 | 实测 6 次（4 声明 + 6 引用里的引用形态与我的正则不同） | 改成 `brick_mentions==1 && ExtResource(==6`，并把「字面次数判据不可达」登记为 F-066-6 |

> 另有 **1 次非回退的纠正**：最初把契约的 176 条当成编辑器端点数，实测 9888=**153**、9889=**72**（176 是 channel 拆分前的总数）。这是**我的假设错**，不是缺陷。

## 6. 纪律核对

| 项 | 结果 |
|---|---|
| **只改模块文档区** | `git status --short` 只多 `modules/mcp_server/docs/reports/evidence/task066/`（已提交）。`modules/mcp_server/tools|tests|docs/tools_list.renamed.json|tool-rename-map.json` **零改动** |
| **`.ps1` 纯 ASCII** | 本任务全部脚本（`cs066_*.ps1`）为纯 ASCII，已入库于 `evidence/task066/run-workspace/` |
| **绝对路径** | 所有产物写 `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\**`；scratch 在 `%TEMP%\mcp-breakout-cs\` |
| **9877** | 开工前、session1 前、session2 后、session3 后**四次断言无监听**；从未启动/停止/占用它 |
| **不并发 scons / 不抑制输出** | 未跑任何 scons（未重建二进制，见 §0 的 D86 说明）；所有引擎进程输出都 `RedirectStandardOutput/Error` 落盘 |
| **禁止 push** | 未 push；只做本地提交 `40dad5a6df` + 报告提交 |
| **D86** | §0 给出**证据提交锚点**与**二进制锚点**，并**自己复测**了「模块实现/契约自 7708729982 起未变」（不是引用 R3 的结论）；本报告引用的 R-3/R3 结论都标注了来源 |
| **PROGRESS.md / DEV-DONE.marker** | `%TEMP%\mcp-breakout-cs\PROGRESS.md`（逐里程碑一行 + 每次 MCP 调用的心跳行）与 `DEV-DONE.marker`；两者已复制入库到 `run-workspace/` |

## 7. deviations / blockers / next_step

**deviations（与任务书/手册的显式偏离）**

1. **碰撞用 AABB 邻近测试而不是物理引擎回调**（§1.3）。理由与边界已写清：scratch 工程里 `CollisionShape2D.shape` 这个子资源无法经 `editor_add_nodes_batch.properties` 表达。若判定需要真实物理碰撞，请再派一轮（可用 `editor_add_resource_to_node_property` 试）。
2. **工程引导部分不完全由 MCP 工具完成**：`project.godot`/`.csproj`/`NuGet.config`/单节点 `scenes/main.tscn` 由 `cs066_bootstrap.ps1` 写盘（这是「工程必须先存在才能被 MCP 端点寻址」的前置条件）；**其后每一个节点、每一个 C# 脚本、每一次挂脚本、每一个 input 动作、保存、构建、判据②⑤⑥、整条活链，全部经 9888/9889 端点**。
3. **判据② 的探针用了两个额外文件**（`CsVerdict.cs` 挂 0 节点、`CsVerdict2.cs` 从未构建），以免「写坏 `.cs`」破坏可跑的游戏；`unverifiable` 类别**未构造**（与 R3 同结论：可读 `.cs` 经 `ResourceLoader.load` 会返回 `CSharpScript`，裁不到「载入失败」分支），**不记为通过**。
4. **判据⑥ 的第三方独立复算（像素级）未在本轮做**：编辑器侧做了「捕获行 vs 工具 `editor_analyze_screenshot_diff`」两路一致（2660/1334144 逐位相等），PNG 已入库可供第三方复算；**三路一致（含独立 python 复算）是 B 角色的 `mcp065b_pixel_recompute.py` 活**，A 未越界代跑。
5. 编辑器端点数按线上实测记 **153**（不是契约 176）。

**blockers**：无。

**next_step_recommendation（给 B 角色/决策者）**

1. **B7 现在有 fixture 了**：`%TEMP%\mcp-breakout-cs\proj` 是**完整可跑**的 C# 工程（16 节点 / 5 脚本 / 4 input 动作 / 可构建）。R3 说「本批脚本可直接复用，只改 `-GameProject`」——把那 15 个游戏侧调用指到本工程即可；注意三处 C# 与 GDScript 的差异：脚本路径是 `res://scripts/Brick.cs`、属性名是 `Score`/`BricksHit`/`Moves`/`Live`/`State`（均 `[Export]`，**不在** `get_property_list` 之外）、`_Process` 而非 `_physics_process`。
2. **B 角色重跑判据⑤ 时要自己造 user 连接**：本工程已持久化 1 条 `ProbeTimer.timeout → Main.OnTimerTimeout`；`user=1` 那组数会随场景里的连接数变化。
3. **优先复核 F-066-1**（`project_list_scripts` 对 `.cs` 失明）：这是本轮**唯一**够得上「照它开工会白走一轮」的项，且它是**文案承诺与实现不符**（不是纯能力缺口）。
4. **不要在判据⑥ 里用不可见节点**（F-7）：`changed:false` 对纯 `Node2D` 是**正确**的，不要据此判「捕获坏了」。
5. **判据① 的构造必须先让编辑器起来再写注释**（F-066-2），否则基线就是 0 条注释，会得到「工具没保住注释」的**假结论**——这是最容易被 R4 复现成误判的一条。