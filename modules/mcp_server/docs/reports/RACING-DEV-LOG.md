# RACING-DEV-LOG — TASK-039 §B 开发者日志（用 MCP 工具真的做出这台赛车）

> **D86 提交锚点**：本报告所有结论测自
> `F:\RustProjects\godot-mcp-pro\code\godot`，分支 `feature/mcp-server-module`，
> **HEAD = `f34ee937f3d31c49ac42081bb91433c5fc5b36e3`**（2026-09-23 22:31:44 +0800），
> 引擎自报 `4.8.dev.mono.custom_build.f34ee937f`。**除标注【推断】外全部为【实测】。**
>
> **测自提交的引擎二进制**：`bin\godot.windows.editor.x86_64.mono.console.exe`，
> 由本任务在 23:46 前以 `scons platform=windows target=editor module_mono_enabled=yes -j8`
> 在 `f34ee937f` 上重建（**重建原因见 §1.1，这是一个必须先解决的环境阻塞**）。

## 0. 交付物与证据落点

| 项 | 路径 | sha256 |
|---|---|---|
| 赛车工程（真的能跑） | `%TEMP%\mcp-racing-test\` | 见 `AC-METRICS.txt` / §6 |
| 本日志 | `modules/mcp_server/docs/reports/RACING-DEV-LOG.md` | — |
| AC 证据（请求/响应成对） | `docs/reports/evidence/racing/`（145 对 + 索引） | `EVIDENCE-INDEX.json` |
| 原始调用日志（400 条 JSONL） | 同上 `CALL-LOG.jsonl` | `9a038c3f16c1d0dd512dfc188858772e6d2daca435aa78d525d6e5155b5c4841` |
| 引擎追踪（§C 的主要事实源） | `%TEMP%\mcp-racing-test\trace-editor.jsonl`（123 067 B）<br>`%TEMP%\mcp-racing-test\trace-game.jsonl`（39 852 B） | `096b0ccd608d1026e5673339ef2632641ea0c5c1632a209c658cb631cbec7b48`<br>`7cdd8b27de1b764531b493c09fc410dc9d504d8d3838585e5039663b04d1ada3` |
| 完成标记 | `%TEMP%\mcp-racing-test\DEV-DONE.marker` | — |
| 本次全部驱动脚本（ASCII） | `%TEMP%\mcp-racing-src\*.ps1` + `rlog.ps1` | — |
| 过程日志（stdout 抓取） | `%TEMP%\mcp-racing-evid\*.out.txt` | — |

**目录纪律（一条我自己踩出来的实测教训）**：第一次把**调用证据写在工程目录内**（`%TEMP%\mcp-racing-test\calls\`），
立刻污染了被测工程本身 —— `project_search_file_contents{pattern:"CharacterBody2D"}` 的**唯一命中就是我自己的请求体**
（调用 #5），`project_get_statistics` 把 **104 个 json 证据文件**算成工程内容（调用 #50）。
之后所有"测试工件"移到 `%TEMP%\mcp-racing-evid\`，工程目录只留工程本身 + 任务书要求放在那里的两份 trace。

---

## 1. 环境准备（不是 MCP 调用，必须声明）

### 1.1 阻塞：交付的 mono 引擎二进制落后 137 个提交，且**没有 `--mcp-trace`**

任务书要求「用 mono 构建 `bin\godot.windows.editor.x86_64.mono.console.exe`」并全程开 `--mcp-trace`。
实测该文件是 **2026-09-22 13:50** 的产物：

```
$ bin\godot.windows.editor.x86_64.mono.console.exe --version
4.8.dev.mono.custom_build.6ea5de6e0          <- 不是 HEAD
$ git rev-list --count 6ea5de6e0..HEAD
137
```

**不是靠版本号推断，而是直接量二进制字符串**（`--mcp-port` / `--mcp-trace` 都是模块自己扫
`os->get_cmdline_args()` 解析的，**不出现在 `--help`**，所以"help 里没有"证明不了任何事）：

```
mono.exe   (6ea5de6e0):  --mcp-trace= -> -1   --mcp-port= -> 110161800
non-mono   (39a4e59b5):  --mcp-trace= -> 116727632  --mcp-port= -> 116494208
```

**处置**：按 `REPORT-014`/TASK-014 M3-1 记录的同一条命令重建，**串行、不并发**（D62）：

```
scons platform=windows target=editor module_mono_enabled=yes -j8
-> exit 0, INFO: Time elapsed: 00:01:34.14
-> bin\godot.windows.editor.x86_64.mono.exe  179 425 280 B (原 178 121 216 B)
-> --version 现在报 4.8.dev.mono.custom_build.f34ee937f  == git rev-parse --short HEAD ✅
```

> 这是**环境准备**，不改 `modules/mcp_server/**`，只产出 `bin/`（gitignore）。

### 1.2 `--import` 第一次就撞上史书里的 `0xC0000005`

```
import attempt 1/3 exit=-1073741819 log=...\import.attempt1.log
   import| ERROR: Parameter "singleton" is null.
   import|    at: EditorNode::is_cmdline_mode (editor\editor_node.cpp:6732)
import attempt 2/3 exit=0
```

**实测结论**：`--import` 的退出码校验 + 有界重试（`PLAYBOOK §3` / TASK-028 D-1）**不是形式主义** ——
若按老做法忽略退出码，后面每一条断言都会跑在**半导入**的工程上。第一次失败后的第二次直接成功。
TASK-028 说"84 次首导全部 exit 0、无法复现"——**本轮复现了一次**，频率未知，纪律本身正确（append-only 勘误，不撤回 TASK-028 的结论，只补一条新观测）。

### 1.3 我的失误：**前台工具调用超时把整棵进程树连坐杀了**

第一次启动编辑器是在 `b1_bootstrap.ps1` 里 `Start-Process` 之后**前台同步等端点**。
驱动命令 300 s 超时后被杀，**编辑器子进程随之消失**。

**这不是模块问题，但它有两个后果，必须记录**：
1. 之后改用**后台作业**（`host_editor.ps1`，见 §1.4）托管长驻进程，不再有超时风险。
2. 同一时刻 `netstat` 显示**用户 Godot 9877 的监听也消失了**。
   - 22:55（开工前）：`TCP 127.0.0.1:9877 LISTENING 76048`
   - 23:03 起：`9877` 无任何 LISTENING；此后**每一次**复查（共 8 次，含收尾）都是 `pid=-1`
   - **诚实声明**：本试测**从未**对 9877 发过任何信号（没有 kill、没有 connect、没有占端口），
     `9877` 也**不在**我的进程树里（PID 76048 由用户自己的会话启动）。我**无法从本侧归因**，
     **不排除**是那次超时清理的连带效应。**需要用户确认**（§9 遗留项 R-1）。修复动作：全程只用 9888/9889。

### 1.4 最终进程拓扑（实测）

| 进程 | 端口 | 启动方式 | 工具面 | 追踪 |
|---|---|---|---|---|
| 编辑器 | 9888 | `…mono.console.exe --path %TEMP%\mcp-racing-test --mcp-port=9888 --mcp-trace=…\trace-editor.jsonl -e` | `tools=148` | 12 3067 B |
| 游戏（窗口化） | 9889 | **工具** `editor_play_scene{mode:"current", mcp_port:9889}` → 子进程 | `tools=69` | 经工程设置 |
| 游戏（headless，模式 B） | 9889 | CLI 自启（**回退**，见 §4 B-5） | `tools=69` | 经 `--mcp-trace=` |

**游戏那一份 trace 是走 `project_set_setting{key:"godot_mcp/trace_file"}` 打开的**（工具调用，见 §2 F 段），
因为 `editor_play_scene` 只向子进程注入 `--mcp-port`（`editor_playback.cpp:320`），不注入 `--mcp-trace`。
`mcp_trace.cpp:70-82` 的优先级是 **命令行 > 工程设置**，所以编辑器仍然写自己的文件，两边不打架。**实测**：两个文件独立增长。

---

## 2. 逐条日志（分阶段）

> 全量 400 条在 `CALL-LOG.jsonl`（字段：`seq/run/ts/endpoint/tool/label/arguments/ok/error_code/
> error_message/duration_ms/result_bytes/request_sha256/response_sha256`）。
> 下表按阶段摘出**有信息量的**条目，`#n` 就是 `seq`。凡「学到什么」写的是**实测**，不是猜测。

### A. 工程级只读/搜索（编辑器 9888）

| # | 时间 | 工具 | 参数要点 | 结果 | 学到什么 |
|---|---|---|---|---|---|
| 1 | 23:03:27 | `project_get_info` | — | ok 191 B | 返回 `project_name`/`editor_screen_size`，无版本号 |
| 2 | 23:03:28 | `project_get_settings` | `prefix:"godot_mcp"` | ok, `count:0` | 设置还没写，正确空 |
| 41 | 23:03:31 | `project_get_settings` | `prefix:"godot_mcp/"` | ok, `count:2` | 写成后能按前缀过滤；前缀语义未在契约里说明 |
| 4→107 | — | `project_search_file_names` | `pattern:"*.cs"` | ok, **`count:0`** | **6 个 `.cs` 文件在盘上却 0 命中**；换成子串 `"Car"` → 4 命中。**glob 形式不被支持，契约也没写 pattern 是子串还是 glob** |
| 5→? | — | `project_search_file_contents` | `pattern:"CharacterBody2D"` | ok | **第一次命中我自己的请求体**（见 §0 目录纪律） |
| 43/… | — | `project_list_scripts` | — | ok, **`count:0`** | 工程里有 6 个 `.cs`，恒 0 → 该工具看不到 C# 脚本 |

### B. 场景与节点（编辑器 9888）

| # | 时间 | 工具 | 参数要点 | 结果 | 学到什么 |
|---|---|---|---|---|---|
| 6 | 23:03:28 | `project_create_scene_file` | `path/root_name:"Main"/root_type:"Node2D"` | ok | 一行创建场景文件，顺手 |
| 7 | 23:03:28 | `editor_open_scene` | `res://scenes/main.tscn` | ok | **必须先 open_scene，之后所有 `editor_*` 节点工具才有"当前场景"**（隐式依赖 I-1） |
| 9 | 23:03:28 | `editor_add_nodes_batch` | 24 节点一次发 | **-32001** `nodes[1]: parent 'Track' not found` | 见 §5 F-3：**批次解析父路径用的是调用前的树**，同一批里不能"先建父再建子"；`data.batch.rolled_back` 明确回滚，`on_error:"all_or_nothing"` |
| 52-55 | 23:07:25 | `editor_add_nodes_batch` ×4 | 按层级分组（6/9/4/5 或 1 个） | 全 ok | 一次只能建**一层** |
| — | 23:07:26 | `editor_set_node_property` ×12 | `position`/`polygon`/`points`/`text` | 12/12 ok | **`PackedVector2Array` 属性直接吃 `[{x,y},…]`**，读写回形状一致（`polygon` 写 4 点 → 读回 4 点）—— 这是顺手性正面案例 |
| 16-27 | — | 同上 | 脚本属性 `MaxSpeed`/`Index`/`TargetPath` | ok | 但**必须先挂脚本**，否则属性不存在（隐式依赖 I-2） |
| 21-30(2) | 23:04:59 | `editor_set_node_property` | 我写错路径 `CP0_StartFinish`（少了 `Checkpoints/`） | **-32001** `Node 'CP0_StartFinish' not found` | 消息准确但**不给候选**；`Track/Road` 能用是因为逐段找。**自纠成本 = 我知道树结构**（D3 边缘案例） |

### C. 脚本（**工具能写 C# —— 不是回退**）

| # | 时间 | 工具 | 参数要点 | 结果 | 学到什么 |
|---|---|---|---|---|---|
| 26-31 | 23:03:30 | `project_create_script` ×6 | `path:"res://scripts/Car.cs"`, `content:<全文>` | 6/6 ok，回 `bytes` | **`_require_script_path` 显式接受 `.gd`/`.cs`**（`project_script_write.cpp:120`）→ **C# 脚本完全可由工具创建，无需回退** |
| 71-73 | 23:18:27 | `project_edit_script` ×3 | `search`/`replace` 模式 | 3/3 ok，回 `changes_made:1` | 定点改脚本很顺手，且回 `editor_rescan_triggered` |
| 2-7 | 23:08:25 | `project_validate_script` ×6 | 6 个 `.cs` | 6/6 ok，`valid:true`，`"Script compiles successfully"` | **契约没写它只支持 GDScript，实测对 `.cs` 报合法** —— 但它**没有真的编译 C#**（`Main.cs` 里的坏信号名照样 `valid:true`，真错在 `dotnet build` 与运行时才暴露）。**这是"报成功但没验证"**：`project_validate_script` 对 C# 是**弱保证**，调用方不能拿它当编译证明 |

### D. 主题 / 资源 / 分组 / 选择 / 改名 / 物理层

| # | 工具 | 参数要点 | 结果 | 学到什么 |
|---|---|---|---|---|
| 53 | `project_create_theme` | `res://resources/hud_theme.tres` | ok 101 B | — |
| 54-57 | `project_set_theme_stylebox/color/font_size` ×4 | `node_type`/名字/值 | 4/4 ok，回 `changed.old/new` | **返回形状好**：给出 old/new，可判定真的写了 |
| 58 | `editor_set_control_theme` | `HUD/Root` | ok，回 `theme_type_count:3` | — |
| 60 | `project_create_resource` | `PhysicsMaterial` + `properties` | ok，回 `changed.friction.old/new` | 同样带 old/new |
| 61 | `editor_add_resource_to_node_property` | `Car.physics_material_override` | **ok**（回 `{node_path,property,resource_type}`） | **⚠️ 报了成功，什么都没发生** → §7 **缺陷 D-1** |
| 63-67 | `editor_set_node_selection` / `get_selection` / `set/get_node_groups` / `find_nodes_in_group` | — | 5/5 ok | 选择/分组族一致、可读回 |
| 68-73 | `editor_add_node`/`rename_node`/`duplicate_node`/`reparent_node`/`delete_node`×2 | 建 `Scratch` → 改名 → 复制 → 移到 Track → 删两个 | 6/6 ok | 改树族完整；`delete` 回 `deferred:true` |
| 32-37 | `editor_setup_collision_shape` ×6 | 先给 `Car/Collision`（已存在的 CollisionShape2D） | **全部 ok，但建成了 `Car/Collision/CollisionShape2D`** | **工具名说"为物理体添加碰撞形状"，它做的却是"在你给的节点下挂一个 CollisionShape2D"**。响应**诚实**（回 `collision_node_path`），但调用方极易套娃。改用**物理体路径**后正确 |
| 12-13 | `editor_setup_physics_body` ×2 | `WallOuter`/`WallInner` @ `Track` | ok | 与 `add_node` 分工清晰 |
| 75-77 | `editor_add_input_action` | `drive_forward`/`W`、`drive_left`/`A` | ok，但 **`persisted:false`，`target:"editor"`** | **E-4 在 `f34ee937f3` 复测成立**：只写编辑器内存，不落 `project.godot` → 游戏进程读不到 |

### E. 信号（**这里抓到第二条真缺陷**）

| # | 时间 | 工具 | 参数要点 | 结果 | 学到什么 |
|---|---|---|---|---|---|
| 42-44 | 23:08:29 | `editor_get_node_signals` | `Car`/`LapTimer`/`Checkpoints/CP1` | ok（3915/2975/5279 B） | **C# `[Signal]` 注册名是 C# 名（PascalCase）**：`SpeedChanged`/`LapCompleted`/`BodyCrossed`。契约与计划里假设的 `speed_changed` **不存在** |
| 45-47 | 23:08:29 | `editor_connect_signal` | `signal:"speed_changed"` 等 | **-32001** `Signal 'speed_changed' on node 'Car' not found` | 消息准确并**指向 `editor_get_node_signals`**（`data.suggestion`）→ **D3 正面案例**：我下一次（28 分钟后）直接用 PascalCase 成功 |
| 48-49 | 23:08:29 | `editor_connect_signal` | `pressed`→`.`、`body_entered`→`LapTimer` | ok `connected:true` | — |
| 19-22 | 23:11:25 | `editor_connect_signal` ×4 | PascalCase 信号 | 4/4 ok `connected:true` | — |
| 25 | 23:11:26 | `editor_analyze_signal_flow` | — | ok 但 **`nodes:[], total_nodes:0`** | 它只收 `CONNECT_PERSIST`。**与 `list_signal_connections` 的 434 条矛盾**（见 F-2） |
| 23/24 | 23:11:25 | `editor_list_signal_connections` | `{}` / `{node_path:"CP1"}` / `{signal_name:"SpeedChanged"}` | ok，**94 862 B / 5 832 B / 205 B** | `node_path` 是**子串匹配**且**把编辑器内部连接也算进来**（`ScriptEditor::*`、`SceneTreeEditor::*`、`Viewport::*`，目标路径是 `../../…/@EditorBottomPanel@8211/…`）。`signal_name` 过滤才精确。**434 条里只有 2 条是我的** |

### F. 工程设置与保存

| # | 工具 | 参数要点 | 结果 | 学到什么 |
|---|---|---|---|---|
| 37 | `project_set_setting` | `dotnet/project/assembly_name="mcp-racing-test"` | ok，`saved:true` | 类型自动判 |
| 38 | `project_set_setting` | `application/run/main_scene` | ok | — |
| 39 | `project_set_setting` | **`godot_mcp/trace_file` = 绝对路径** | ok，`created:true` | **这是让工具起的游戏子进程也产出 trace 的唯一工具路径**（因为 `editor_play_scene` 只注入端口） |
| 40 | `project_set_setting` | `godot_mcp/enabled_in_game=true` | ok | — |
| 42… | `editor_save_scene` | — | ok | — |
| 43… | `project_read_scene_file_content` | `res://scenes/main.tscn` | ok，`size:4836` | **与磁盘 sha256 逐字节相同**（§6 AC-1） |

### G. dotnet build（回退：构建步骤）

```
dotnet build -c Debug   -> exit 0, 0 warnings 0 errors, 3.16 s
  -> .godot\mono\temp\bin\Debug\mcp-racing-test.dll
```
**隐式依赖 I-2（实测）**：C# 脚本**必须在 assembly 存在之后**才能被 `editor_set_node_script` 真正生效。
我为此把建树拆成 b2a（建场景/节点/脚本）→ **build** → b2b（挂脚本/连信号/存盘）两段。
挂脚本这一步 `editor_set_node_script` **本身不报错**（回 `attached:true`），错误在游戏启动时以
`Attempt to connect nonexistent signal` 的形式出现 —— **工具侧没有"脚本是否可加载"的检查**。

### H. 起游戏与运行期只读（游戏 9889）

| # | 工具 | 参数要点 | 结果 | 学到什么 |
|---|---|---|---|---|
| 1(b3) | `editor_play_scene` | `mode:"current", mcp_port:9889` | ok 1843 ms，回 `{endpoint, mcp_port, mcp_port_source:"argument", pid:44156, playing:true}` | **返回可直接喂回的可链式字段**（`endpoint`/`pid`），顺手性正面案例 |
| 4 | `running_game_get_scene_tree` | `max_depth:4` | ok 3218 B | 路径全是**绝对** `/root/Main/…` |
| 5 | `running_game_get_node_properties` | `"/root/Main/Car"`, 含 `Position` | ok，**`"Position":null`** | **大小写敏感**：`position` 能读、`Position` 静默 `null`。而**编辑器端** `editor_get_node_properties` 做了大小写归一（TASK-032 D3）→ **两端不同形状**（见 F-7） |
| 9 | `running_game_find_nodes_by_script` | `res://scripts/Car.cs` | ok `count:1`，`MaxSpeed:320.0` | **C# 按脚本查节点可用**（AC-2） |
| 10 | `running_game_find_node_when_available` | `"/root/Main/Car"` | ok，`found:true` | — |
| 11 | `running_game_get_node_properties_batch` | 2 节点 | ok | — |
| 12 | `running_game_find_ui_elements` | `type_filter:"Button"` | ok | — |
| 13 | `running_game_assert_screen_text` | `"LAP"` | ok，`passed:true`，`source:"control_tree"` | headless 也成立（E-6 复测成立） |
| 14 | `running_game_get_autoload_node` | 缺 `name` | **-32602** `Missing required parameter: name` | 契约已声明必填，自纠成本 0 |
| 15 | `running_game_find_nearby_nodes` | 我传了 `node_path` | **-32602** `Unknown parameter 'node_path'` | **参数名与直觉不符**：真实签名是 `position`(必填对象)+`radius`，契约里没有 `node_path`。消息准确 |

### I. 本机（非 MCP）：`dotnet build` 与 C# 信号名

游戏日志 `%APPDATA%\Godot\app_userdata\mcp-racing-test\logs\godot.log` 实测：

```
[RACE] Checkpoint CP0_StartFinish index=0 finish=True mono=True
[RACE] Car ready pos=(-140, 0) action_exists=False
[RACE] ChaseCamera ready target=Car
ERROR: In Object of type 'CharacterBody2D': Attempt to connect nonexistent signal 'speed_changed'
ERROR: In Object of type 'Node': Attempt to connect nonexistent signal 'checkpoint_passed'
ERROR: In Object of type 'Node': Attempt to connect nonexistent signal 'lap_completed'
```

**这是我的脚本 bug，不是模块缺陷**：我自己在 `Main.cs` 里写了 snake_case。用
`project_edit_script`（工具）改掉 3 处 → `dotnet build` → `editor_stop_scene` → `editor_play_scene` →
**错误行数 0**。记在这里是因为它证明了 **`project_validate_script` 对 `.cs` 的"合法"是空保证**（§2 C 段）。

---

## 3. 你要求的四个验收判据（§B.4）逐条实测

> 全部在 `f34ee937f3` 上测得；每条给**响应 sha256**（完整请求/响应在 `docs/reports/evidence/racing/`，
> 文件名 = `NNNN-<tool>.request.json` / `.response.json`）。

### ① 工程能起（`dotnet build` + 引擎启动）

| 检查 | 实测 | 证据 |
|---|---|---|
| `dotnet build -c Debug` | **exit 0**，`0 个警告 0 个错误`，3.16 s | `dotnet-build-1.log`；assembly `mcp-racing-test.dll` 38 912 B sha256 `c3c0c33592c55619279c9e799df79cb2f2de40805c1be789a153b4c423fe6613` |
| 编辑器起（9888） | `[MCP] role=editor configured_port=9888 source=cmdline listen=true` / `tools=148` | 编辑器 `--mcp-trace=` 生效，trace 123 067 B |
| 游戏起（9889，窗口化，**由工具起**） | `editor_play_scene` 回 `pid:44156 / playing:true / mcp_port_source:"argument"` | `0012-editor_play_scene` |
| 游戏真的在跑 C# | `[RACE] …` 7 行 + `physics_frames` 逐帧增长 | `running_game_get_node_properties`（§6 AC-3） |
| headless 也能起 | CLI 自启 → `[MCP] listening … tools=69`，`[RACE]` 全在 | `headless-game.out.log` |

### ② 在游戏端点 9889 注入输入让车动，并用**另一个工具**读回位置变化（不是瞬移）

| 项 | 实测值 | 证据 |
|---|---|---|
| 注入 | 工具 `running_game_run_test_scenario`，`steps:[{input,keycode:"W"},{wait,1.5s},{assert distance_travelled>50},{assert key_frames>30}]` | `AC-3` |
| 注入工具自己的结论 | `all_passed:true, passed:2, failed:0, errors:0, duration_ms:1584` | 同上 |
| **另一个工具读回** | `running_game_get_node_properties`（**不同调用**）：`position -140 → 302.75`，`distance_travelled 0 → 442.75`，`key_frames 0 → 98`，`physics_frames +101`，`last_input:"none" → "forward"` | 同上 |
| 反面（不按） | 只发 `pressed:false` → `distance_travelled 0 → 0`，`key_frames 0 → 0`（`physics_frames +68`，证明帧在走但车没动） | `AC-3neg` |
| 反面（用错端点） | `editor_simulate_key`/`editor_simulate_input_action`（**9888**）都回 ok，9889 上 `distance 0→0`、`key_frames 1351→1351` | **E-3 在 `f34ee937f3` 复测成立** |

**「不是瞬移」的证据**（工具 `running_game_get_node_property_samples`，180 帧）：

| 指标 | 实测 | 判据 |
|---|---|---|
| 样本数 / 帧跨度 | 180 / `physics_frames 9139 → 9318`（span 179） | 严格递增 ✅ |
| `distance_travelled` | `51.667 → 1002.75`（Δ951.08，约 317 px/s ≈ MaxSpeed 320） | 单调不减 ✅ |
| 相邻样本最大位移 | **5.333 px** | < 上界 `MaxSpeed/60*1.5 = 8.0` ✅（瞬移必然违反） |
| 反例 | `running_game_move_player_to_target`（无导航数据）→ **-32000** + `data.suggestion` | 消息：*"…has no region: there is no navigation data to follow, so this tool refuses instead of moving the player straight through the world"* |

**「注入+采样」不能一趟做完**：`run_test_scenario` 没有采样步骤，`get_node_property_samples` 不能同时注入。
我用的办法是**两条调用**：先 `[{input,keycode:"W"}]`（**只按不松**，键状态跨调用保留），再采样，最后发 `pressed:false`。
这本身是**可合并候选 C-4 / 缺失工具 B-4** 的实测依据。AC-6 的并发取证则**真的开了第二条连接**（后台进程），实测可并行。

### ③ 检查点/圈计时状态真的变化

| 项 | 实测 | 证据 |
|---|---|---|
| 负例（GO 之前） | `Timing:false`，1.2 s 后 `CurrentLapTime` 仍 `0.0 → 0.0` | `AC-5neg` |
| GO 之后 | `running_game_simulate_button_click_by_text{text:"GO"}` → `Timing:true` | `AC-5` |
| 计时真的在走 | 120 帧采样：`CurrentLapTime 0.6 → 2.583`（跨度 1.983 s，理论 `120/60=2.0 s`，偏差 <1 %），**严格递增** | `AC-5-samples-laptimer-positive.json` |
| 检查点顺序 | 前进：`CheckpointsHit 0 → 1`（越 CP1）→ `2`（越 CP2），`LastCheckpointIndex 1 → 2` | `AC-5` |
| **整圈** | 倒车穿回 CP0 → **`LapCount 1 → 2`**，`CheckpointsHit 2 → 0`，`BestLap = 14.20`，车身 x 从 `1245.7` 开到 `-1802.8`（**真的开回去的**） | `AC-5` |
| 乱序负例（干净初态） | 瞬移 `CP2 → CP0`：`LapCount` **不变**；瞬移 `CP1 → CP0`（跳过 CP2）：`LapCount` **不变** | `AC-5neg` |
| HUD 真的在被驱动 | `running_game_assert_screen_text{"LAP"}` → `passed:true, source:"control_tree"` | b3 |

> **一条重要的因果证据**：第一次跑整圈时 `Timing_after_GO=False`、`LapCount` 没变。
> 原因**不是**计时逻辑，而是 `editor_connect_signal{StartButton.pressed → Main.OnStartPressed}`
> **没有被 `editor_save_scene` 写进 `.tscn`**，游戏里没人监听 `pressed` → 见 §5 **F-2 / §7 缺陷 D-2**。
> 我用 `project_edit_script` 让 `Main.cs` 自己连按钮后，**同一套调用立刻全绿**。

### ④ 每条判据的实测响应（含 sha256）

见 **§6** 的完整表（12 条 AC + E-1 + 反例），每行给 `seq` 与响应 sha256，
原始文件在 `docs/reports/evidence/racing/`。

---

## 4. 回退清单（**工具之外的手段，逐条四段**）

> 每条按任务书 §B.2 的格式：**想做什么 / 试过哪些工具 / 为什么不行 / 回退做了什么**。
> 回退产物一律给 sha256。

### B-1 ★ 从零创建一个 Godot 工程（`project.godot` / `NuGet.config` / `.csproj`）

- **想做什么**：让一个空目录成为 Godot 能打开的 C# 工程。
- **试过哪些工具**：`project_get_info`/`project_get_settings`/`project_get_filesystem_tree`/
  `project_create_scene_file`/`project_create_resource`/`project_set_setting` —— **全部要求"已经有一个工程"**
  （没有工程时引擎都起不来，连不上端点）。171 条里**没有任何 `project_create_*` 能建工程**。
- **为什么不行**：能力缺口。**连"创建工程"这个动作本身都没有工具**，形成鸡生蛋：
  要调工具得先有工程，要有工程得先有工具。
- **回退做了什么**：`b1_bootstrap.ps1` 手写三个文件（UTF-8 **无 BOM**，`[IO.File]::WriteAllBytes` +
  `UTF8Encoding($false)`）：
  - `project.godot` 674 B sha256 `534fcc66911e361a43d4352184355e2f6cc1c15bd38405d9d4ff475f0a79c1b6`
  - `NuGet.config` 232 B sha256 `a9fecf977a9169a42180ac7ca9e0c0f152f8d28e0f75e454240bed90b02130d6`（只指向引擎自带 nupkgs，`<clear/>` 强制离线）
  - `mcp-racing-test.csproj` 305 B sha256 `e58b1c6e6988765d3ffdcc783739892f287f315c89ccbd73cfc265a9b30462ce`
  **其余全部由工具完成**（场景、26 个节点、6 个脚本、主题、资源、设置、连线、存盘）。
- **B3 签署建议**：`project_create_project {path(绝对或 user://), name, dotnet:bool, main_scene_type}` →
  `{created, project_file, csproj, nuget_config}`。引擎本来一次 `ProjectSettings::save()` + 生成 csproj 就能做到。

### B-2 ★ 让被观测的游戏以 `--headless` 起来

- **想做什么**：模式 B（headless）取证，避免窗口依赖。
- **试过哪些工具**：`editor_play_scene{mode:"current", mcp_port:9889}` —— 契约的 `inputSchema`
  **只有 `mode`/`mcp_port`**（`docs/tools_list.renamed.json` 实文），没有任何 headless/args 参数；
  `project_set_setting` 也没有"给子进程加命令行"这种设置项（试了 `godot_mcp/*`，无效）。
- **为什么不行**：能力缺口（**计划 §2.5 已预登记，实测成立**）。
- **回退做了什么**：直接 CLI 自启
  `…mono.console.exe --headless --path %TEMP%\mcp-racing-test --mcp-port=9889 --mcp-trace=…\trace-game.jsonl`，
  PID 写进 `headless-game.pid`，stdout/stderr 抓进 `headless-game.out.log`。
- **B3 签署建议**：`editor_play_scene` 加 `extra_args: array<string>`（或 `headless: bool`）
  → 回显 `args_injected`。引擎侧 `EditorRunBar::play_*` 本来就收 `p_play_args`（本模块已用它塞 `--mcp-port`）。

### B-3 让游戏子进程产出 MCP 调用追踪

- **想做什么**：`trace-game.jsonl` 必须有内容（§C 观察者的主要事实源）。
- **试过哪些工具**：`editor_play_scene` 没有 trace 参数（同上）；
  引擎命令行形式 `--mcp-trace=` 只能在编辑器自己身上用。
- **为什么不行**：`editor_play_scene` 只注入 `--mcp-port=`
  （`tools/editor_playback.cpp:320`，**【源码依据】**）。
- **回退做了什么**：**没有回退**——这一步找到了**工具内的正解**：
  `project_set_setting{key:"godot_mcp/trace_file", value:"…\\trace-game.jsonl"}`（调用 #39），
  游戏子进程启动时读到它（`mcp_trace.cpp:70-82`，命令行 > 工程设置）→ **实测 trace-game.jsonl 39 852 B 有内容**。
  **这算"隐式依赖 I-4"**：要用工具起游戏又要 trace，**必须**先知道 `godot_mcp/trace_file` 这个设置键 ——
  契约与 `editor_play_scene` 的 description 都**没有**提到它。

### B-4 一次调用"边注入输入边连续采样"

- **想做什么**：AC-4 要求"在注入 W 的窗口内采样"，最自然是**一个**请求。
- **试过哪些工具**：`running_game_run_test_scenario`（有 `input`/`wait`/`assert`，**没有采样 step**）；
  `running_game_get_node_property_samples`（能采样，**不能注入**）。
- **为什么不行**：两条工具的能力不重叠。
- **回退做了什么**：**没有回退到工具之外**，用两次调用绕开：
  ① `[{input,keycode:"W"}]` 只按不松（键状态跨调用保留，**实测**）→ ② 采样 180 帧 → ③ `pressed:false`。
  AC-6 的并发场景则**真的开了第二条连接**（`capture_signals.ps1` 独立进程），**实测两条连接可并行**：
  一条挂着 9 s 的信号捕获，另一条同时注入输入，捕获到 545 次发射。
- **B3 签署建议**：给 `run_test_scenario` 加 `sample` step `{type:"sample", properties:[…], frame_count, frame_interval}`
  → `results[i].samples[]`。**风险**：会让单条响应变大（本用例 180 帧 3 属性 = 23 KB）。或独立工具
  `running_game_run_scenario_with_samples{steps, samples:{node_path,properties,frame_count}}`。

### B-5 手写 C# 源文本

- **想做什么**：写 6 个 `.cs`。
- **试过哪些工具**：`project_create_script`（**一次就成**，接受 `.cs` + `content`）、`project_edit_script`（改 3 处也成）。
- **为什么不行**：**不需要回退**。我**唯一**做的是把源文本先存在工程**外的**暂存目录
  `%TEMP%\mcp-racing-src\*.cs`，再由脚本读出来作为 `content` 参数发给工具
  （放在工程内会被 Godot 当第二个脚本导入 → 重复类定义）。
- **回退做了什么**：无。**这是本轮"工具完全够用"的一个正面案例**。

### B-6 `--import` / `dotnet build` / 启进程

- **想做什么**：首次导入资源、编译 C#、把两个进程拉起来。
- **试过哪些工具**：没有工具能做这三件事（`project_*` 全是**在已有工程内**的读写）。
- **为什么不行**：进程生命周期与构建不属于 MCP 工具面（**这是设计边界，不是缺陷**；计划 §2.1/§2.5 也这么安排）。
- **回退做了什么**：`--import`（**校验退出码 + 3 次有界重试 + 诊断**，第 1 次 `0xC0000005`、第 2 次成功）、
  `dotnet build -c Debug`（离线，`NuGet.config` 指引擎自带 nupkgs）、`Start-Process` 起 9888 编辑器与 headless 游戏。

### 回退计数

**6 条**（B-1…B-6），其中 **B-5 是"试了工具、发现不用回退"**，**B-4 是"没回退、用调用序列绕开"**。
**真正的工具外动作 = 4 条**：建工程文件、CLI 导入、CLI 构建、起进程（含 headless 游戏）。

---

## 5. 摩擦清单（任务书 §B.3 要求：调了几次才成功 / 错误消息够不够自纠 / 隐式依赖）

### F-1 「同一工具调几次才成功」实测排行（来自 400 条 CALL-LOG）

| 工具 | 调用 | 失败 | 首次成功在 | 失败原因分类 |
|---|---|---|---|---|
| `editor_set_node_property` | 57 | 21 | 第 14 次 | 1 次是我写错节点路径；**20 次是试图给"还没挂脚本的节点"写脚本属性**（先建后挂的顺序问题，见 I-2） |
| `editor_add_nodes_batch` | 10 | 3 | 第 2 次 | 同批建父子（F-3） |
| `editor_connect_signal` | 9 | 3 | 第 4 次 | snake_case 信号名（C# 用 PascalCase） |
| `editor_analyze_screenshot_diff` | 4 | 2 | 第 3 次 | 绝对路径不被接受（F-10） |
| `editor_setup_physics_body` | 4 | 2 | 第 3 次 | 首次是父节点 `Track` 还没建出来（批次回滚的连带） |
| `editor_setup_collision_shape` | 10 | 0 | — | **不报错但语义易错**：套娃（见 §2 D 段） |
| `running_game_set_node_property` | 4 | 2 | 第 2 次 | 缺参/不存在的节点 |
| `running_game_get_node_properties` | 36 | 0 | — | 但 `Position` 静默 `null`（F-7） |

**整体**：400 次调用 / 43 次失败（10.75 %），错误码只有 `-32001`(37) `-32602`(3) `-32000`(3)。
**没有一次 `-32603`/`-32700`/`-32601`**。

### F-2 「错误消息够不够自纠」

**够的（正面，实测"失败后下一次就成功"）**：
- `editor_connect_signal` 的 `-32001` 带 `data.suggestion`= *"Use editor_get_node_signals to list the signals this node has"*
  → 我照着读了一下工具就拿到 PascalCase 名字。
- `editor_add_nodes_batch` 的 `-32001` 带 `data.batch.rolled_back` + `data.suggestion`=*"…(or split the request into calls that each succeed)…"*
  → 直接告诉我怎么绕。
- `running_game_move_player_to_target` 的 `-32000` 把**为什么拒绝**写清了（没有导航数据）。
- `running_game_find_nearby_nodes` 的 `-32602` 说 Unknown parameter（虽然没列正确签名）。

**不够的**：
- `editor_set_node_property` 的 `Node 'CP0_StartFinish' not found` —— **不给候选路径**。
  我错在少了 `Checkpoints/` 前缀，只能自己 `editor_get_scene_tree` 反查。**判据 D3**：失败后我又探了 **2 次**（先 tree 再写）才成功。
- `editor_add_resource_to_node_property` **根本不报错**（§7 D-1）。

### F-3 「必须先 A 探路再 B」的隐式依赖（全部实测）

| ID | 依赖 | 证据 |
|---|---|---|
| **I-1** | 任何 `editor_*` 节点工具前，**必须**先 `editor_open_scene` | 不开场景时 `edited_scene_root` 为空 |
| **I-2** | 要给节点写**脚本属性**，必须先 `editor_set_node_script`，而**挂脚本前必须先 `dotnet build`** | 写 `MaxSpeed` 前 20 次失败；build 后同一批调用立刻成功 |
| **I-3** | `editor_add_nodes_batch` **不能**在同一批里建父与子 | 第 1 次 24 节点全失败（`rolled_back`） |
| **I-4** | 要用**工具**起游戏又要 trace，必须先知道 `godot_mcp/trace_file` 这个**没被契约提到**的设置键 | `editor_play_scene` 只注入端口 |
| **I-5** | 要列游戏端工具面，必须先有游戏 | 鸡生蛋：`tools/list` 只列**本进程**注册的工具（见 F-11） |
| **I-6** | `editor_setup_collision_shape` 要传**物理体**路径，不是 `CollisionShape2D` 节点路径 | 传 CollisionShape2D → 套娃 |

### F-4 其它工具面事实（顺带记录，供 §C/§D 取用）

- **C# 信号名是 PascalCase**：契约与计划都按 snake_case 写的，实测全错。`[Signal] delegate void SpeedChangedEventHandler` → 节点上是 `SpeedChanged`。
- `editor_list_signal_connections` 的**信噪比**：434 条里 432 条是编辑器内部；`node_path` 过滤是子串匹配；**只有 `signal_name` 过滤是精确的**。
- `project_list_scripts` 恒 `count:0`（工程里 6 个 `.cs`）。
- `project_search_file_names` 只吃子串，`*.cs` 这种 glob 恒 0。
- `editor_analyze_screenshot_diff` 的 `image_a` 契约写"路径或 base64"，**绝对 Windows 路径被拒**（`-32001 The base64 PNG in parameter 'image_a' not found`），`user://race-1.png` 与 base64 都成。
- 计划里点名的 `running_game_get_test_report` **在 171 条里不存在**（真名是 `editor_get_test_report`）。

---

## 6. 验收判据实测表（含 sha256）

> `seq` 对应 `CALL-LOG.jsonl` 与 `docs/reports/evidence/racing/NNNN-*.{request,response}.json`。
> 「响应 sha256」= 该响应文件的 sha256（整段 JSON-RPC 信封）。

### AC-1 工程与场景成立 ✅

| 检查 | 实测 | 证据 |
|---|---|---|
| `project_get_info` | `project_name:"mcp-racing-test"` | 见 evidence |
| `project_get_settings{prefix:"godot_mcp/"}` | `{"godot_mcp/enabled_in_game":true,"godot_mcp/trace_file":"…\\trace-game.jsonl"}` | — |
| `editor_get_scene_tree{max_depth:6}` | **28 个节点**；`Track`/`Track/Road`/`Checkpoints/CP0_StartFinish`/`Car`/`LapTimer`/`HUD`/`HUD/Root/VBox/TimeLabel` 全部在 | `AC-1` |
| `project_read_scene_file_content` **sha256 == 磁盘 .tscn sha256** | 两边都是 `5892209c13782d417d8ef32f794bf94b7aaebcde00f40b1e75345ea8a49b7c3c`，`size:4836` == 磁盘 4836 B | `AC-1` |
| **反例**：读不存在的场景 | **`-32001`** `Scene file 'res://scenes/no_such_scene_zzq.tscn' not found` + `data.suggestion` ✅（不是 `-32603`） | `AC-1counter` |

### AC-2 脚本真的挂上了 ✅

| 检查 | 实测 |
|---|---|
| `project_validate_script` × 6（每个 `.cs`） | 6/6 `valid:true` —— **但这是弱保证**（§2 C 段） |
| `editor_set_node_script` × 8（含 3 个 Checkpoint） | 8/8 回 `attached:true` |
| `editor_find_nodes_by_type{"CharacterBody2D"}`（9888） | `count:1`，`path:"Car"` |
| `running_game_find_nodes_by_script{"res://scripts/Car.cs"}`（9889） | `count:1`，`properties:{MaxSpeed:320.0, distance_travelled:…, physics_frames:…}` → **`MaxSpeed` 读回 == 场景值 320** ✅ |
| 存盘证据 | `.tscn` 里 6 条 `[ext_resource type="Script"]` + `Main.cs`/`Car.cs`/`LapTimer.cs`/`Hud.cs`/`ChaseCamera.cs`/`Checkpoint.cs` |

### AC-3 车真的动了 ✅（见 §3 ②）

`all_passed:true`，`passed:2/failed:0/errors:0`；
`position -140 → 302.75`；`distance_travelled 0 → 442.75`；`key_frames 0 → 98`；`physics_frames 9010 → 9111`。
反例 A（`pressed:false`）与反例 B（9888 的 `editor_simulate_*`）都**没有**让车动。

### AC-4 运动连续、不是瞬移 ✅（见 §3 ②）

180 样本 / 帧跨 179 / 距离单调不减 / 最大相邻位移 5.333 px < 8.0 px 上界 / 反例 `move_player_to_target` 明确拒绝。

### AC-5 圈计时真的在走 ✅（见 §3 ③）

负例（`Timing:false`）→ GO → 严格递增 → CP1 `hit=1` → CP2 `hit=2` → 回到 CP0 **`LapCount 1→2`、`BestLap=14.20`**；
两个乱序负例 `LapCount` **不变**。

### AC-6 检查点信号链成立 ✅

| 工具 | 实测 |
|---|---|
| `editor_get_node_signals{CP1}` | 31 个信号，含自定义 `BodyCrossed(args:index:int)` |
| `editor_connect_signal` × 4（PascalCase） | 4/4 `connected:true` |
| `editor_list_signal_connections{signal_name:"SpeedChanged"}` | `count:1`，`{source:"Car",signal:"SpeedChanged",target:"HUD",method:"OnSpeedChanged"}` |
| `editor_analyze_signal_flow` | **`nodes:[], total_nodes:0`** ⚠️ 见 §7 D-2 |
| `running_game_capture_signal_emissions`（第二条连接，9 s） | **`count:545`**，含：<br>`Checkpoints/CP1.body_entered(args=[/root/Main/Car])`<br>`Checkpoints/CP1.BodyCrossed(1)`<br>`LapTimer.CheckpointPassed(1,0.0)`、`CheckpointPassed(2,0.0)`<br>`Car.SpeedChanged(10.3 → …)` × 大量 |

**矛盾检测点结论**：`list_signal_connections` 说"有"、`analyze_signal_flow` 说"无" —— 两者**对"同一事实"给了不同答案**，
且**都不是错的**（前者不过滤 flags，后者只收 `CONNECT_PERSIST`）。契约描述了差异，但
**`editor_connect_signal` 不告诉调用方"我这根线不会进 `.tscn`"** → §7 D-2。

### AC-7 截图（窗口化模式）✅

| 检查 | 实测 |
|---|---|
| `running_game_capture_screenshot{user://race-1.png}` | ok；`%APPDATA%\Godot\app_userdata\mcp-racing-test\race-1.png`，**12 102 B**，sha256 `0d0257839d7a4a0c293c86bd57ab2b1a92196825314c9ecb54871c4c25121bba` |
| 同上 `race-2.png`（中间车开了一段） | ok；**12 196 B**，sha256 `20f07a55a1328f01b2e6be1f4966b50d1bda675f5bee78e2a3fc0007f2fb5b33` |
| `running_game_capture_frames{count:6,frame_interval:10}` | ok，59 340 B |
| `editor_analyze_screenshot_diff{user://race-1.png, user://race-2.png}` | ok：**`identical:false`，`changed_pixels:282585`，`diff_percentage:37.85`**，`width:1152 height:648`，另返回差异图 base64 |
| `editor_capture_screenshot{res://shots/editor.png}`（9888 窗口化） | ok，`width:3840 height:2054` |
| **反例（形状）** | 传**绝对路径** → `-32001 The base64 PNG in parameter 'image_a' not found`（契约说"路径或 base64"） |
| **headless 反例（E-1）** | 见下 |

### AC-8 属性写入与读回一致 ✅

| 检查 | 实测 |
|---|---|
| `running_game_set_node_property{MaxSpeed, 999.0}` | ok |
| 读回 `running_game_get_node_properties{["MaxSpeed"]}` | **`999.0`** ✅ |
| 写**不存在**的属性 | **`-32001`** + `data.suggestion` ✅（`PLAYBOOK §6.6` 第 7 例的修复在 `f34ee937f3` 仍有效） |

### AC-9 双端点与契约一致性 ⚠️（计划 E-5 被证伪）

| 检查 | 实测 |
|---|---|
| `tools/list` @9888 | **148 条**，43 189 B，sha256 `e31846b5c276e9d3f59c8bf6023a5796e0777187d9ded0586a52954084e8b956` |
| `tools/list` @9889 | **69 条**，23 362 B，sha256 `a1762689b9b1751efa80359d223e5f6b756663eda4d0f0909b90450b3eb7413e` |
| **每个条目的 `name`/`description`/`inputSchema` 与契约逐字相等** | **编辑器 0 处不一致，游戏 0 处不一致** ✅ |
| 9889 ⊂ 9888 ？ | **否！** 有 **23 条 `running_game_*` 只在游戏端注册**（`running_game_run_test_scenario`、`…_get_node_property_samples`、`…_capture_screenshot`、`…_execute_gdscript` …）。编辑器独有 **102** 条。148 + 23 = 171 ✅ |
| 源码依据 | 这 23 条都声明 `scope(MCPToolScope::GAME)`（`tools/running_game_*.cpp`），注册表按进程作用域过滤 |

→ **计划的预登记 E-5「9889 的集合 ⊂ 9888」在 `f34ee937f3` 上不成立**（**不是异常，是预登记错了**：
计划自称该条为【源码依据】，实测证伪）。**后果**：调用方**无法从编辑器端点发现游戏端工具**，
必须先知道"这一点是 game scope"（D6/B1）。

### AC-10 静态/工程分析工具 ✅

`project_analyze_scene_complexity` ok（`total_nodes:29`，`scripts_attached:8`）；
`project_get_scene_dependencies` ok（`count:7`）；`project_find_unused_resources` ok（`unused_count:3`）；
`project_get_statistics` ok（`scene_count:1`）；`editor_get_errors` **`count:0`**（试测全程无引擎错误）；
`editor_get_output_log{filter:"MCP"}` ok；`editor_get_performance_monitors` ok；
`project_convert_path_to_uid` ok。**响应最大 43 189 B（`tools/list`），远低于 1 MiB 阈值**。

### AC-11 可复现性 ✅

同一 `run_test_scenario`（3 步）**连跑 3 次**，每次先 `ResetToSpawn`：

```
run1: passed=1 failed=0 errors=0 all_passed=True duration_ms=1567
run2: passed=1 failed=0 errors=0 all_passed=True duration_ms=1583
run3: passed=1 failed=0 errors=0 all_passed=True duration_ms=1567
```
✅ 结论一致、耗时量级一致（±1.0 %）。

### AC-12 模块未被试测改动 ✅

```
$ git status --short modules/mcp_server/tools modules/mcp_server/tests
(空)
$ certutil -hashfile modules\mcp_server\docs\tools_list.renamed.json SHA256
c844ec8af9ef00d2e6ec7008c9806b3e2b16757e78794d3ccca0704edf844256   <- 与计划 §0 完全一致
$ git rev-parse HEAD
f34ee937f3d31c49ac42081bb91433c5fc5b36e3                            <- 未变
```

### E-1（预登记，headless 截图）✅ 命中

| 检查 | 实测 |
|---|---|
| `running_game_capture_screenshot`（headless 9889） | **`-32000`**，`message:"The running game has no framebuffer to read (the headless display server has no texture storage)"`，**`data.suggestion:"Run the game with a display server (drop --headless, or use a build with a rendering driver) and call the tool again"`** ✅ 与 E-1 逐条相符 |
| `running_game_capture_frames`（headless） | **`-32000`** + `data.suggestion` ✅ |
| headless 下**其它必须全绿**的 | `get_scene_tree` ok；`get_node_properties` ok；`assert_screen_text{passed:true}`；`simulate_button_click_by_text` → `Timing:true`；`run_test_scenario` **`all_passed:true`**，车 `x -140 → 281.4`、`distance 0 → 421.4` ✅ |

### E-2（预登记，headless **编辑器**截图）

**未测，显式声明**：本轮编辑器全程**窗口化**（`-e`），因此 `editor_capture_screenshot` **成功**
（3840×2054，见 AC-7）。要测 E-2 必须让编辑器也 `--headless` 重启，**代价是丢掉窗口化取证**，
且计划并未要求二选一。**这是"不可构造"而非"未做"**：同一端口不能同时窗口化又 headless。
建议 §C 复测时单独起一个 headless 编辑器在 9890。

### E-3 / E-4（预登记，编辑器输入与 InputMap 落盘）✅ 都在 `f34ee937f3` 复测成立

- E-3：`editor_simulate_key`/`editor_simulate_input_action` 回 ok，9889 上 `distance 0→0`、`key_frames 1351→1351`。
- E-4：`editor_add_input_action` 回 `{"action":"drive_forward","created":true,"event_count":1,"key":"W","persisted":false,"target":"editor"}`。
- 连带的**真实后果**（实测）：游戏进程 `Car.action_exists = false`、`action_frames` 恒 0、
  `raw_action_events` 恒 0 → **P-action 路径完全没打通，B2「没有工具能把 InputMap action 持久化进 `project.godot`」成立**。
  **但主路径（keycode）不受影响**：`key_frames` 98、车真的走了 —— 计划 §2.4 的"设计意图"实测有效。

---

## 7. 疑似缺陷（**只记录，未修改任何模块代码**）

### D-1 ★ `editor_add_resource_to_node_property`：给**不存在的属性**写资源，报成功、什么都没发生

**严重度：high**（`PLAYBOOK §5/§7.7` 的 A5 类：报成功但状态未变；且与 `PLAYBOOK §6.6` 第 7 例**同一族**，那一例已在 `running_game_set_node_property` 修好，**编辑器写侧这一条漏了**）

| 步骤 | 请求要点 | 实测响应 |
|---|---|---|
| ① 反例 | `editor_add_resource_to_node_property{node_path:"Car", property:"physics_material_override", resource_type:"PhysicsMaterial", resource_properties:{friction:0.1,bounce:0.0}}` | **ok**：`{"node_path":"Car","property":"physics_material_override","resource_type":"PhysicsMaterial"}` |
| ② 读回 | `editor_get_node_properties{path:"Car", properties:["physics_material_override"]}` | **`-32001`** `Property 'physics_material_override' on node 'Car' not found` |
| ③ 存在性 | `editor_get_node_properties{path:"Car"}`（全量） | **66 个属性，不含 `physics_material_override`** |
| ④ **阳性对照** | 同一工具、同一属性，换成 `Track/WallOuter`（`StaticBody2D`，**真的有**这个属性） | **ok** → 读回 `{"physics_material_override":{"local_to_scene":false,"path":"","type":"PhysicsMaterial"}}` ✅ **工具在属性存在时工作正常** |
| ⑤ 对照 | `editor_set_node_property{path:"Car", property:"no_such_property_zzq"}` | **`-32001`** ✅（TASK-037 的闸门在另一条路径上是好的） |

**根因（源码依据，只读阅读）**：`tools/editor_write_scene_editor.cpp:697` 直接 `node->set(property, Variant(resource_ref));`，
**没有 `get_property_list()`/`has_property` 检查**；返回值（699-702 行）无条件回显 `property`。
引擎侧依据：`physics_material_override` 在 `scene/2d/physics/rigid_body_2d.h:75` 与 `static_body_2d.h:49` 有，
`CharacterBody2D` **没有** —— 所以这不是"我写错了属性名"，而是**工具对不存在的属性静默成功**。

**最小复现（可直接粘贴）**：
```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"editor_add_resource_to_node_property","arguments":{"node_path":"Car","property":"physics_material_override","resource_type":"PhysicsMaterial","resource_properties":{"friction":0.1,"bounce":0.0}}}}
```
期望：`-32001` + `data.suggestion`（像 `editor_set_node_property` 那样）。实际：ok + 空操作。
证据：`docs/reports/evidence/racing/` 中 `…-editor_add_resource_to_node_property.{request,response}.json` 三对（Car 两次 + WallOuter 一次）+ `car-property-list.json`。

### D-2 ★ `editor_connect_signal` 报 `connected:true`，但**连接不进 `.tscn`**，运行时不存在

**严重度：high**（调用方能建出"看起来连好了、存盘后再打开就没了"的场景；我在本轮**真的因此得到了一台不会计时的赛车**）

| 证据 | 实测 |
|---|---|
| `editor_connect_signal` | 回 `{"connected":true,"signal":"SpeedChanged","source":"Car","target":"HUD"}`（×4 全 ok） |
| `editor_save_scene` | 回 `{"saved":true}` |
| `project_read_scene_file_content`（与磁盘同 sha256） | **`.tscn` 里没有任何 `[connection]` 块**（`grep -c connection` = 0） |
| `editor_analyze_signal_flow` | `nodes:[], total_nodes:0` |
| 运行时后果（**实测**） | `simulate_button_click_by_text{"GO"}` 回 ok，但 `LapTimer.Timing` **仍是 false**，120 帧采样 `CurrentLapTime 0.0 → 0.0`；游戏日志里 `pressed` 无监听者 |
| 修好之后 | 让 `Main.cs` 自己连按钮 → 同一套调用 **`Timing:true`、`CurrentLapTime 0.6→2.583` 严格递增、`LapCount 1→2`** |

**根因（源码依据，只读阅读）**：`tools/editor_node_write.cpp:257` —— `p_source->connect(p_signal, callable);`
**没有传 `CONNECT_PERSIST`**（Godot 4 中 `CONNECT_PERSIST = 2`；`scene/resources/packed_scene.cpp:760` 只序列化带该位的连接）。
工具也**没有**参数可以要求持久化，返回值里也**没有**任何 `persisted` 字段（对比：`editor_add_input_action` 就老实回了 `persisted:false`）。

**最小复现**：对一个有两节点的场景 `editor_connect_signal{source_path:"A", signal:"X", target_path:"B", method:"Y"}`
→ ok `connected:true`；`editor_save_scene`；`project_read_scene_file_content` → **无 `[connection]`**；
关掉重开场景 → 连接消失。
**建议的最小修法（不在本任务范围内）**：`connect(..., CONNECT_PERSIST)`，并在返回里加 `"persisted":true`；
或加 `persist: bool`（默认 true）参数。**注意**：这会改变既有行为，属后续批次的决策。

### 非缺陷、但必须记录的语义陷阱（**不建议当缺陷处理**）

- **N-1** `editor_setup_collision_shape` 会在**你给的节点下**挂 `CollisionShape2D`：传 `Car/Collision` 会得到
  `Car/Collision/CollisionShape2D`。响应如实回了 `collision_node_path`，**工具没错**；但名字（"为物理体添加碰撞形状"）容易误导。
- **N-2** C# `[Signal]` 注册名是 **PascalCase**。模块没错（Godot 的 C# 绑定就是这么命名），但**契约/计划按 snake_case 写**，对 C# 用户是坑。
- **N-3** `running_game_get_node_properties` 对 `Position`（首字母大写）**静默回 `null`**，而编辑器端的同名工具做了大小写归一。
  两端形状不一致（D4 候选）。我最终**统一用引擎拼写**（`position`）。
- **N-4** `editor_list_signal_connections` 返回编辑器内部连接（434 条 / 94 KB，其中 432 条不是场景的）。
  用 `signal_name` 过滤可精确；`node_path` 是子串匹配。
- **N-5** `project_search_file_names` 只支持子串（`*.cs` → 0）；`project_list_scripts` 看不到 `.cs`（恒 0）。
- **N-6** `editor_analyze_screenshot_diff` 的"路径"只认 Godot 虚拟路径（`user://`），绝对 Windows 路径被拒。

---

## 8. 与计划（`RACING-TEST-PLAN.md`）的偏差（逐条显式列出）

| # | 计划要求 | 我做的 | 原因 |
|---|---|---|---|
| 1 | 检查点计数按 §2.3 的 `Index==0 && CheckpointsHit>=3` 计圈，HUD 显示 `CP 0/3` | `CheckpointsHit` **只计中间检查点**（CP1/CP2），HUD `CP 0/2`；整圈判据是"CP0 且两个中间点都过" | 计划 §2.3 的算法与 **AC-5②「越过 CP1 后 `CheckpointsHit` 由 0 变 1」** 直接冲突（按 §2.3 应是 1→2）。我选择**让可观测判据逐字成立**，并在 §5 记录了这处张力 |
| 2 | AC-6 用 `editor_connect_signal{… target:"/root/Main/LapTimer", method:"OnCheckpointEntered"}` | 改连 `LapTimer.OnCheckpointBodyEntered`（探针）+ 独立的功能链路 `Checkpoint.OnBodyEntered → LapTimer.OnCheckpointIndex` | `body_entered` 回调参数是**进入区域的 body（车）**，不是检查点，LapTimer 无法从它得知 Index；若照计划连会出现**每帧双计数** |
| 3 | `.csproj` 名为 `mcp-racing-test.csproj` | 采纳（`AssemblyName=mcp-racing-test`），`dotnet build` 一次成功 | 计划本就如此 |
| 4 | 截图对比用 `editor_analyze_screenshot_diff{image_a:…}` 传路径 | 改传 `user://…`（绝对路径被拒） | 见 N-6 |
| 5 | §2.2 场景 24 个节点 | **28 个**（`Track/WallOuter`+`WallInner` 各含 1 个 `CollisionShape2D`） | 用 `editor_setup_physics_body` + `editor_setup_collision_shape` 覆盖物理族 |
| 6 | 计划 §3 说证据放 `docs/reports/evidence/racing/`，但任务书 §B 只列了两个产出 | **两处都写**：AC 级 145 对请求/响应进仓库 `docs/reports/evidence/racing/`，全量 400 条 CALL-LOG 与两份 trace 留 `%TEMP%` | 兼顾 §D 的可核对性与仓库整洁 |
| 7 | 计划 E-5：「9889 ⊂ 9888」 | **证伪**（23 条 game-only） | 实测优于预登记 |
| 8 | 计划 §2.3 说 `LapTimer.OnCheckpointEntered(Node2D area)`；`Checkpoint._Ready` 连 `BodyEntered` | 采纳（`Checkpoint` 侧），但 LapTimer 另有 `OnCheckpointIndex(int)` | 同 #2 |
| 9 | （不是计划，是我的）`b7_headless_mode.ps1` 的 `param` 默认值在该次调用中未生效，显式传 `-GodotExe` 后才正常 | 显式传参 | **未查清的本机 PowerShell 5.1 现象**，与模块无关；如实记，不掩盖 |

---

## 9. 遗留风险与未测项

| ID | 内容 |
|---|---|
| **R-1** ★ | **用户 Godot 9877 的监听在 23:03 起消失**（22:55 还在，PID 76048）。本试测**未对其发过任何信号**，也无法从本侧归因；怀疑与 §1.3 那次"前台超时杀进程树"有关，但**未证实**。**请用户确认 9877 是否需要重启**。此后 8 次复查（含收尾）都是 `pid=-1`，试测全程只用 9888/9889。 |
| **R-2** | **E-2 未测**（headless 编辑器截图）——本轮编辑器是窗口化的，见 §6 E-2 段。 |
| **R-3** | `editor_simulate_input_sequence` 只测到 `-32602 Missing required parameter: events[0].type`（契约的 `events` **没有 item schema**），未构造成功调用。 |
| **R-4** | 分支 N（导航）/A（动画）/T（TileMap）/P（压力测试）**未做**（计划标注为可选，不做不算失败）。`running_game_run_stress_test` 未调用。 |
| **R-5** | `running_game_move_player_to_target` 只测了**无导航数据**的失败路径（AC-4 反例），成功路径未测。 |
| **R-6** | 两份 trace 仍在增长（编辑器/headless 游戏还在跑）。`AC-METRICS.txt` 里的 trace sha256 是 **23:39 的快照值**；§C 引用时应重新算。 |
| **R-7** | 我这一侧的驱动脚本与 `%TEMP%` 下的原始 evidence（`mcp-racing-evid\`）**没有进仓库**，只有 AC 级 145 对进了 `docs/reports/evidence/racing/`。 |

---

## 10. 诚实声明

1. **不改模块**：全程未修改 `modules/mcp_server/tools/**`、`tests/**`、contract、scripts 的任何实现。
   AC-12 给了 `git status` 空 + 契约 sha256 不变两项证据。我只**读**了源码用于**归因**（§7 的两条根因都标了文件与行号）。
2. **不碰 9877**：只在开工前与收尾各查一次 `netstat`，结果见 R-1。
3. **失败不抹**：43 次失败调用全部留在 `CALL-LOG.jsonl` 与 `docs/reports/evidence/racing/` 里，
   包括我自己的 3 类错误（节点路径写错、C# 信号名写成 snake_case、参数名猜错）。
4. **实测 vs 推断**：本报告除标注【源码依据】（只读阅读）与【推断】外全部【实测】，且都给了
   响应 sha256 / 文件 sha256 / 退出码 / 错误码。
5. **证据不落管道**：所有响应体都是 `curl.exe -s -o <file> --data-binary @<file>` 落盘后算 sha256，
   请求体一律 `[IO.File]::WriteAllBytes` + UTF8 无 BOM（`PLAYBOOK §7.1` / TASK-028 D-1）。
   所有 `.ps1` 纯 ASCII。
6. **没有为好看而删掉任何一次失败**；计划里被证伪的 E-5、被复现的 `0xC0000005`、以及我自己未查清的
   PowerShell 现象（§8 #9）都留在原地。

---

## 11. 给 §C（观察者）的提示（哪里最可能有料）

1. **`-32001` 有 37 次**，绝大多数来自我自己的路径笔误与"先建后挂"顺序问题 → 属于 **A6（多次调用才摸清用法）**，
   不是缺陷。真正值得抓的是 **D-1 / D-2** 两条。
2. **`editor_list_signal_connections` 的 94 862 B** 是全程最大的单条响应之一（最大是 `tools/list` 43 KB）→ **A4 的候选**（阈值 1 MiB 未破，但信噪比是问题）。
3. **`editor_add_nodes_batch` 的 3 次失败**连着三次工具调用内成功 → 典型 **A6**。
4. **AC-6 的矛盾**（`list_signal_connections` vs `analyze_signal_flow`）是**设计如此**的矛盾，
   请按"调用方无法知道会不会落盘"这一点来判 —— 矛盾在 `editor_connect_signal` 的**返回值**上，不在两个读工具之间。
5. 高频 3 步序列（**可合并候选**）实测：`editor_open_scene → editor_get_scene_tree → editor_add_nodes_batch`（每个"改场景"回合都有）；
   `editor_set_node_property → editor_get_node_properties`（写后读回，我做了 12 次）；
   `running_game_execute_gdscript(ResetToSpawn) → run_test_scenario → get_node_properties`（AC-11 每次循环）。
