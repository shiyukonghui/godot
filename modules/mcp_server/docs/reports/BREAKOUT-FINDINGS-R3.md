# BREAKOUT-FINDINGS-R3 — TASK-065 §B：缺口专项第 3 轮（⑤ `scope` 收窄 / ⑥ 窗口化 `changed:false` / 游戏侧活链）

> **D86 锚点**
> - **被测二进制** = `bin\godot.windows.editor.x86_64.console.exe`，`--version` = **`4.8.dev.custom_build.770872998`**
>   （构建于 `7708729982`；本批**没有重建**，理由见 §7.1）。
> - **被测工作树** = `git rev-parse HEAD` = **`08691fd21e90a86497ee3469999217c646a64e2b`**（`--short` = `08691fd21e`）。
> - **最后一个改动 `tools/**`、`tests/**`、契约的提交** = **`92a260b682`**；
>   `git diff --stat 7708729982..HEAD -- modules/mcp_server/tools modules/mcp_server/tests
>   modules/mcp_server/docs/tools_list.renamed.json modules/mcp_server/scripts` = **空**（§7.1 逐条打印），
>   所以**二进制里的模块代码 == 工作树里的模块代码**。
> - **本报告自身的提交锚点**：本批是**试测/取证批次**，只写脚本与报告，**不做提交**（父层决定何时提交）；
>   交付时工作树里新增的是**未跟踪**的 `docs/reports/BREAKOUT-FINDINGS-R3.md`、
>   `docs/reports/evidence/task065b/`（127 文件）与 `scripts/mcp065b_*`（5 `.ps1` + 1 `.py`）——
>   全部内容可由 `evidence\task065b\evidence-manifest.txt`（sha256 `e0c010d3…`）逐行核对。
>   **结论的提交锚点按上三条标注**（二进制 / HEAD / 最后一个改动实现的提交），不依赖本报告是否已提交。
> - 契约 `docs/tools_list.renamed.json` sha256 = **`d4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd`**
>   ——与 TASK-065A 报告的基线**逐字相同**（契约在本批前后同 sha）。
> - 本批**不修改**任何模块实现 / 测试 / 契约 / 映射 / 清单 / 生成器（§7.2 的 `git diff --stat` 全部为 0 行）。
> - **D-119 纪律**：本报告与全部产物一律写**绝对路径**（前缀
>   `F:\RustProjects\godot-mcp-pro\code\godot\`），scratch 除外并显式标注。

---

## 0. 结论（先给答案）

| # | 任务书要求 | 结论 | 关键数字 | 证据 |
|---|---|---|---|---|
| ⑤ | `editor_list_signal_connections` 的 `scope` 收窄**真正构造出来** | **通过（实测，非推断）** | 默认 **47** 条 / 9 756 B；`scope:"user"` **2** 条 / **371 B**；`scope:"internal"` **45** 条 / 9 565 B；`user ∪ internal = default`、`user ∩ internal = ∅`；`signal_name:"timeout"` 与 `scope` **组合正确** | §2 |
| ⑥① | 「报成功但画面没变」→ **`changed:false`** | **通过（窗口化，非 headless）** | 同参同值重放：工具回 `old_value == new_value == {200,120}`（成功），捕获行 **`changed:false` / 0 px / ratio 0.0** | §3.2 |
| ⑥② | 真实变化 → **`changed:true` + `changed_pixel_ratio>0`** | **通过** | **10 232 / 1 334 144 px = 0.0076693…**（`frames_waited=1`、`viewport=2d`、`scale=2`、`status=done`） | §3.2 |
| ⑥③ | **日志 / 工具 / 独立复算三路一致** | **通过** | 三路都给出 `10 232 / 1 334 144`（幂等对：三路都给出 `0 / 1 334 144`、`identical=true`） | §3.3 |
| 游戏① | 注入输入 → **另一工具**读回**位置真的变化**（多帧、非瞬移、给采样） | **通过** | 注入者 `running_game_run_test_scenario`；读回者 `running_game_get_node_property_samples`：x = 321→482，**24 个样本 24 个不同值、逐帧单调、每帧约 +7.0 px**；另一读回 `running_game_get_node_properties`：300→496、`moves=28` | §4.1 |
| 游戏② | 砖块**真的消失/减少** | **通过** | `running_game_find_nodes_by_script{brick.gd}`：**3 → 2**（存活 `Brick1,Brick2`，`Brick0` 从场景树里消失） | §4.2 |
| 游戏③ | 计分**真的变化** | **通过** | `HUD/ScoreLabel.text`：`Score: 0` → **`Score: 10`**；进程内断言 `Main.score > 0` 通过（`actual=10`） | §4.3 |
| 游戏④ | 不可构造项要说明为什么 | **已声明**：**本轮三条全部构造出来**，无「不可构造」项；**仍空白 8 项**已逐条列清（性质是「没测」，每条都给了补测办法） | — | §6.1 |
| 观 | `mcp_watch_run.ps1` 覆盖观察，**`stop_reason` 必须是 `marker`** | **通过** | `stop_reason=marker`、`polls=9`、`elapsed_sec=40`、`activity_seen=1`、`trace_lines=142`、`last_seq=32`、`trace_files=3 / missing=0`、`observation_stopped_before_development_ended=0` | §5 |
| 证 | `mcp_evidence_guard.ps1`（唯一命名 + before→between→after + 断言两 sha 不同） | **通过** | 127 个证据文件、`collisions=0`、`duplicate_names=0`；快照对 `3cad0f2d…` → **`36af27ad…`**（不同） | §5.2、§3.4 |
| 纪律 | 不碰 9877、端口 9888/9889、禁止 push、不抑制/不并发 scons、不改实现 | **全部满足** | 9877 全程**无监听者**；本批**一次 scons 都没跑**；`git diff --stat` 全部 0 行 | §7 |

**一句话**：**第 2 轮「未构造」的两条（⑤ `scope`、⑥ 窗口化 `changed:false`）与「空白」的整条游戏侧活链，本轮全部真正构造出来并留下可复算证据**；
过程中另外**实测到观察器（`mcp_watch_run.ps1`）的一种「看起来成功、其实什么都没观察到」的调用方式**（§6-F2），并给出反例探针与可用的启动方式。

**机器可读总账**：`run-summary.json` = **`checks_passed=71` / `checks_failed=0` / `stop_reason=marker`**（退出码 **0**）。

---

## 1. 方法与证据地图

### 1.1 为什么必须自建 fixture（**这是第 2 轮游戏侧空白的直接原因**）

第 2 轮（TASK-060）留下的 C# 工程 `%TEMP%\mcp-breakout\proj`（本轮仍在磁盘上，只读核对）**无法支撑判据 ②③**：

| 事实（实测，只读） | 后果 |
|---|---|
| `proj\scenes\main.tscn` = **54 B**，只有一个空根节点 | 没有 `Paddle` / `Ball` / `Bricks` / 分数 `Label` |
| `proj-scene\scenes\main.tscn`（3 433 B）里 `Paddle` / `Ball` 节点**没有 `script =` 行**，只有砖块挂了 `Brick.cs` | `Paddle._PhysicsProcess` / `Ball._PhysicsProcess` **根本不会跑** |
| 任何一个 `StaticBody2D` **都没有 `CollisionShape2D`** | 引擎不会产生任何碰撞回调 |
| 没有任何代码调用 `Brick.Hit()`（`grep` 全工程 0 处调用点） | **砖块永远不会消失、计分永远不会变** |
| `proj\project.godot` 无 `launch` / `paddle_left` / `paddle_right` 动作 | 注入输入后没有东西会响应 |
| `proj\scenes\main.tscn` 没有分数 `Label` | 判据③**无观察对象** |

⇒ 第 2 轮游戏侧不是「没跑工具」，而是**被测对象本身没有可观察的游戏行为**。本批因此**新造 fixture**（§1.2），
并把上述事实登记为 **F1（试测产物缺口，不是模块缺陷）**。

### 1.2 本批 fixture（scratch，`%TEMP%\mcp065b\`，UTF-8 无 BOM、LF）

- `proj-editor\`（**GDScript**，2D）：`Main(Node2D, main.gd)` + `Timer` + `Marker(Timer)` + `Box(ColorRect 320x200)`，
  场景文件里有**两条真实持久连接**（`Timer.timeout → Main._on_timer_timeout`、`Marker.timeout → Main._on_timer_two_timeout`），
  两个方法名都**不含 `::`** —— 正是 `scope:"user"` 要保留的那一半（对应第 2 轮 C# 里 `SignalRegistry.EnsurePaddleMarker` 的意图）。
- `proj-game\`（**GDScript**，可真的玩）：`Paddle`（读 `InputMap` 动作逐帧移动）、`Ball`（每物理帧上移，按距离判定击中砖块）、
  3 个 `Brick`（`brick.gd`，被击中即 `queue_free()` 并向父节点 `add_score(10)`）、`HUD/ScoreLabel`（文本 `Score: N`）。
  **没有任何 mock**：工具读回的每个值都由引擎的场景树与物理循环产生。
  动作事件表**故意为空**：模块注入的是 `InputEventAction`，而 `InputMap::event_get_action_status`
  对 `InputEventAction` **只按名字匹配**（`core/input/input_map.cpp:294-315`），动作只要存在即可被 `Input.is_action_pressed` 读到。
- fixture 的 8 个源文件 sha256 在 `run-console.log.txt` 的 `FIXTURES written` 段与 `run-summary.json` 里可核对
  （例：`proj-editor\scenes\main.tscn` = `3cad0f2d7f8d14b3c85ff1325ddde57b1ffa649924e603005cf9e2e373bdb6b6`，661 B）。

### 1.3 进程与端口

| 进程 | 命令行（摘要） | 端口 |
|---|---|---|
| 窗口化编辑器 | `bin\godot.windows.editor.x86_64.console.exe -e --path %TEMP%\mcp065b\proj-editor --mcp-port=9888 --mcp-trace=… --mcp-capture=every_call --mcp-capture-dir=res://mcp065b_shots --mcp-capture-viewport=2d --mcp-capture-scale=2` | **9888**（153 工具） |
| 游戏 | `… console.exe --headless --path %TEMP%\mcp065b\proj-game --mcp-port=9889 --mcp-trace=…` | **9889**（72 工具） |
| 观察者 | `powershell … mcp_watch_run.ps1 -Marker … -TracePath editor,game,PROGRESS -TimeoutSec 1800 -StaleSec 600 -IntervalSec 5`（经 `-EncodedCommand` 启动，理由见 §6-F2） | — |

- 编辑器**不是 headless**（`[MCP] capture enabled: mode=every_call viewport=2d dir=res://mcp065b_shots diff_image=false scale=2`，见 `editor.out.log.txt`）；
  它没有 `--headless`，`--mcp-capture-viewport=2d` 指向 `EditorInterface` 的 2D 主界面 SubViewport
  （`editor_get_scene_tree` 的绝对路径里可见 `@EditorMainScreen@…/2D/…/@SubViewport@…/Main`，见 §2.1）。
- **9877 全程无监听者**（`netstat` 前/后两次，`p0_port_9877_no_listener_before` / `p8_port_9877_no_listener_after` PASS）；
  本批**只杀自己启动的 PID**（`Add-Heartbeat` 记录了 `stopped own pid=73904` 等）。
- 本批**没有跑任何 scons**（因此「不抑制 scons / 不并发 scons」两条无对象可违反）。

### 1.4 证据树（127 文件，绝对路径根 = `…\docs\reports\evidence\task065b\`）

| 目录 / 文件 | 内容 | 文件数 |
|---|---|---|
| `phase5-scope\` | ⑤ 的 **20** 个 `tools/call`（请求 + 响应，唯一命名 `<leaf>__<seq>__<sha8>.{request,response}.json`） | 40 |
| `phase6-capture\` | ⑥ 的 **10** 个调用 + **before/after 场景快照对** | 18 |
| `game-live-chain\` | 游戏侧 **15** 个调用 | 30 |
| `shots\` | 被三路复核的 4 张 PNG（`real_change.{before,after}.png`、`same_args_same_value_replay.{before,after}.png`） | 4 |
| `traces\` | `trace-editor.jsonl`（65 行 = 1 `trace_opened` + 32 请求 + 32 捕获）、`trace-game.jsonl`（16 行）、`PROGRESS.md.txt`（61 行心跳） | 3 |
| `watch\` | `watch-run-final.log.txt`（最终一次观察的独立块）、`watch.log.txt`（**append-only 的累计文件**，见 §6-O3）、`watch-summary.txt`、`watch-summary.json.txt` | 4 |
| `probes\` | §6-F2 的两个反例探针（stderr/stdout + `watch-invocation-probe.json`） | 5 |
| `process-logs\` | 编辑器/游戏 stdout+stderr、两个 `--import` 日志、观察器 stdout/stderr、`run-console.log.txt`（本次运行的**全部 71 条 PASS/FAIL 原始输出**） | 9 |
| 根 | `phase5_scope.json`、`phase6_capture.json`、`game_live_chain.json`、`pixel_recompute.json`、`run-summary.json`、`evidence-manifest.txt`（**126 行 path+size+sha256，不含 manifest 自身**，自身 sha256 = `e0c010d3f4cb22a000cda6397c1bfaefd42d1cd62ff19418e8b57c5cdc358b82`，两次连跑逐字节相同） | 7 |

**证据卫生**（TASK-064 §2 的两条规则，实测）：
- 唯一命名：`Assert-McpEvidenceTreeUniqueness` → **`files=127 collisions=0 duplicate_names=0`**（同名前缀、同一 payload 才会同名，而名字里带 `sha8`）。
- `git check-ignore` 对全部 127 文件 = **0 个被忽略**（两个 `--import` 日志原为 `*.log`（`.gitignore:308`），已按仓库既有约定改名为 `*.log.txt`，内容逐字节未变）。

---

## 2. ⑤ `scope` 收窄 —— **通过（真正构造，实测）**

### 2.1 构造（编辑器端点 9888，真实调用）

`p3_*` 先把编辑器带进可观察状态（全部 PASS）：
`editor_get_scene_tree` → `editor_open_scene{path:"res://scenes/main.tscn"}`（`{"opened":true,…}`）→
`editor_execute_gdscript{code:"EditorInterface.set_main_screen_editor(\"2D\")\nreturn \"ok\""}`（`{"result":"ok"}`）→
`editor_get_scene_tree` 确认 `scene_path=res://scenes/main.tscn` 且 `Box` 在树里、场景根挂在 **2D 主界面 SubViewport** 下。

> 为什么要有「切到 2D 主界面」这一步：`--mcp-capture-viewport=2d` 读的是 `EditorInterface::get_editor_viewport_2d()`
> 的 SubViewport，只有 2D 主界面是当前界面时它才真的在渲染 —— 这也是 ⑥② 唯一能产生像素变化的前提（§3.2 的阳性对照）。

### 2.2 20 次调用的分布与逐条判据

| 组 | 调用 | 次数 | 结果 |
|---|---|---|---|
| 默认（省略 `scope`） | `p5_default_{1,2,3}` | 3 | 47 条 / 9 756 B；`scope:"all"` |
| `scope:"user"` | `p5_user_{1,2,3}` | 3 | **2 条 / 371 B** |
| `scope:"internal"` | `p5_internal_{1,2,3}` | 3 | 45 条 / 9 565 B |
| `scope:"user"` + `signal_name:"timeout"` | `p5_user_timeout_{1,2,3}` | 3 | 2 条 / 370 B |
| `scope:"internal"` + `signal_name:"timeout"` | `p5_internal_timeout_{1,2,3}` | 3 | **0 条**（178 B） |
| 默认 + `signal_name:"timeout"` | `p5_default_timeout_{1,2,3}` | 3 | 2 条 |
| `scope:"all"`（显式） | `p5_all_explicit` | 1 | 47 条 |
| `scope:"bogus"`（负例） | `p5_bogus_scope` | 1 | `-32602` |

**逐条判据（`run-summary.json` 的 checks 里 `c5_*` 共 14 条，全部 PASS）**：

| 判据 id | 结论 | 证据（可复算） |
|---|---|---|
| `c5_default_call_answered` | 默认 `count=47`，9 756 B | `phase5-scope\p5_default_1__0005__3b50a621.response.json` |
| `c5_user_call_answered` | `count=2`，371 B | `phase5-scope\p5_user_1__0008__2b39eda8.response.json` |
| `c5_internal_call_answered` | `count=45`，9 565 B | `phase5-scope\p5_internal_1__0011__a264ddeb.response.json` |
| `c5_scope_field_echoes_the_request` | 20 次调用全部 `scope` 字段与请求一致（默认→`all`） | 20 份响应 |
| **`c5_user_contains_only_scene_side_methods`** | user 的 method **只有** `_on_timer_timeout` / `_on_timer_two_timeout`（**均不含 `::`**） | 同上 user 响应：`{"connections":[{"method":"_on_timer_timeout","signal":"timeout","source":"Timer","target":"."},{"method":"_on_timer_two_timeout","signal":"timeout","source":"Marker","target":"."}],"count":2,"counts":{"all":47,"internal":45,"user":2},"scope":"user"}` |
| **`c5_internal_contains_only_class_method_bindings`** | internal 的 45 条 method **全部含 `::`**（`ScriptEditor::_queue_update_list`、`SceneTreeEditor::_node_script_changed`、`Viewport::canvas_parent_mark_dirty`…） | 同上 internal 响应 |
| **`c5_user_and_internal_partition_the_default_set`** | `user ∪ internal = default`（47）且 **`user ∩ internal = ∅`**，`default − user = 45 = internal`，`default − internal = 2 = user`，`internal − default = 0` | `phase5_scope.json` 的 `user_set` / `internal_set` / `default_set_minus_user`（45 条，逐条列在文件里）/ `default_set_minus_internal`（正好是那 2 条 fixture 连接）/ `user_internal_intersection`（空） |
| `c5_count_and_counts_are_self_consistent` | 20 次调用每一条都满足 `counts.user + counts.internal == counts.all`、`count == 返回的 connections 条数 == 该 scope 对应的 counts 分量` | 见 `run-console.log.txt`（逐条打印，例：`[all:47/47 expected=47 counts=47-2-45]`、`[internal:0/0 expected=0 counts=2-2-0]`） |
| `c5_counts_match_the_independently_computed_sets` | `counts` 与我**独立算出的集合**逐项相等：无 `signal_name` 时 `47-2-45` vs `47/2/45`；`signal_name:"timeout"` 时 `2-2-0` vs `2/2/0` | 同上 |
| **`c5_three_calls_per_scope_have_identical_result_bodies`** | 同一 scope 的 3 次调用**工具结果体**逐字节相同：默认体 sha8 `249ea832`、user `06c09b15`、internal `634832e5`（HTTP 响应整体 sha 不同只因为 JSON-RPC `id` 不同——这一点是本轮**修正掉的一个判据缺陷**，见 §6-O1） | `phase5_scope.json` 的 `*_body_sha256` |
| `c5_explicit_all_equals_the_default` | 显式 `scope:"all"` 的结果体 sha256 **等于**默认：`249ea832ac45b9407973165e60c01240d7879a8d5455394d7d5875704cd2fa85` | `phase5-scope\p5_all_explicit__0023__82b467f6.response.json` |
| `c5_user_answer_differs_from_default` / `c5_internal_answer_differs_from_default` | user / internal 的结果体都与默认不同（`06c09b15…` / `634832e5…` ≠ `249ea832…`） | 同上 |
| **`c5_signal_name_and_scope_compose`** | 组合正确：`signal_name:"timeout"` 时 `default(2) == user(2) ∪ internal(0)`，且三者各自是**同 scope 无过滤结果**的子集 | `p5_default_timeout_1__0020__181e6928`、`p5_user_timeout_1__0014__28b117d1`、`p5_internal_timeout_1__0017__01e49b7d`（`{"all":2,"internal":0,"user":2}`） |
| `c5_signal_name_filter_keeps_the_whole_user_set` | `user` 与 `user+timeout` 条数相同（2），且那条 fixture 连接都在 | `p5_user_1` / `p5_user_timeout_1` |
| `c5_signal_name_filter_drops_every_internal_connection` | `internal+timeout = 0`（45 条内部连接的信号名里没有任何含 `timeout` 的） | `p5_internal_timeout_1` |
| `c5_unknown_scope_is_refused_with_the_enum` | `scope:"bogus"` → `-32602`，`data.suggestion` 列出 `all\|user\|internal`，`message` 逐个解释三种口径 | `phase5-scope\p5_bogus_scope__0024__c05bc087.response.json` |

### 2.3 集合差与体积（任务书要求的「条数 / 字节数 / 集合差」）

| 口径 | 条数 | HTTP 响应字节 | `connections` 数组字节 | 相对默认 |
|---|---|---|---|---|
| 默认（`all`） | 47 | 9 756 | 8 831 | — |
| `scope:"user"` | **2** | **371** | **166** | 响应 **−96.2%**，数组 **−98.1%** |
| `scope:"internal"` | 45 | 9 565 | 8 666 | −1.96% |

- **集合差（逐条）**：
  - `default − user` = 45 条（`phase5_scope.json:default_set_minus_user`，逐条 `<source>|<signal>|<target>|<method>`）；
  - `default − internal` = **正好 2 条**：`Timer|timeout|.|_on_timer_timeout`、`Marker|timeout|.|_on_timer_two_timeout`；
  - `user − default` = **0 条**（空；该字段在 JSON 里被 PowerShell 序列化成 `{}`，是**空集合的序列化产物**，判定以 §2.2 的 `user ∪ internal = default` 为准，本轮已在报告里如实标注，见 §6-O1）；
  - `user ∩ internal` = **0 条**。
- 本轮把第 2 轮审计（TASK-051 O-9）的**根因复现成了可复算的数字**：在一个只有 4 个节点的场景里，**47 条连接中 45 条是编辑器自己的内部连线**
  （占响应字节的 88.8%），而它们按 `node_path` / `signal_name` **都过滤不掉**（它们的 `source` 就是普通场景节点路径，
  例如 `source:"."`、`source:"Timer"`），**只有 `method` 能区分**。`scope:"user"` 就是把「淹没」变成「371 B」的那一刀。

### 2.4 本轮实测到的两点**形态事实**（供决策者，不是缺陷）

- **O-1（文档口径）**：`counts` 是「**先 `node_path`/`signal_name`，后 `scope`**」的口径 ——
  `signal_name:"timeout"` 时 `counts={"all":2,"user":2,"internal":0}`。契约描述只说「counts 给出三种口径各自的条数」，
  **没有说它是在另外两个过滤之后**。实测行为自洽（`counts.user+counts.internal==counts.all` 每次都成立），
  建议在描述里补一句「counts 描述的是**同一请求经 node_path/signal_name 过滤后、scope 过滤前**的集合」。
- **O-2（形态）**：内部连接的 `target` 是**相对节点路径**（含大量 `../../..`，如 `../../../../../../../../../Script`），
  **不是可链式喂回的任何工具的 node path**；`source` 则是场景根相对路径。也就是说「内部连线」这一半的 target 字段
  不能被下一个工具直接使用（`scope:"user"` 那一半是可以的：`Timer|timeout|.`）。

---

## 3. ⑥ 窗口化 `changed:false` —— **通过（真正构造，实测）**

### 3.1 前提（阳性对照）

`--mcp-capture=every_call --mcp-capture-dir=res://mcp065b_shots --mcp-capture-viewport=2d --mcp-capture-scale=2`
在**窗口化**编辑器里生效（启动行逐字见 §1.3 / `editor.out.log.txt`）。**没有使用 headless 顶替**：
本批进程**没有** `--headless`，且所有捕获行 `status:"done"`（headless 下必然是 `unavailable`）；
`c6_capture_status_done_not_unavailable` PASS 就是这条的机器判据。
另外 `editor_get_scene_tree` 证明被编辑场景真的挂在 `@EditorMainScreen…2D…@SubViewport` 下，
而 ⑥② 的 10 232 px 变化**就是 `Box` 被移动后 2D 视口重绘出来的**——这同时构成「2D 视口真的在渲染本场景」的阳性对照。

### 3.2 两条构造（序列 27 / 28，同一个编辑器进程，同一棵树）

| | 调用 | 参数（逐字，两次**同一个对象**） | 工具结论 | 捕获行 |
|---|---|---|---|---|
| **⑥②真实变化** | `editor_set_node_property` (seq 27) | `{"path":"Box","property":"position","value":{"x":200,"y":120}}` | 成功：`old_value={40,40}` → `new_value={200,120}` | `changed=true`、`changed_pixels=10232`、`total_pixels=1334144`、`changed_pixel_ratio=0.00766933704307781`、`frames_waited=1`、`status=done`、`viewport=2d`、`scale=2` |
| **⑥①同参同值重放** | `editor_set_node_property` (seq 28) | **同一个参数对象**（参数 sha256 = `257fbd0b1455e35d…`，`c6_replay_sent_byte_identical_arguments` PASS） | **仍然报成功**：`old_value={200,120}` → `new_value={200,120}` | **`changed=false`**、`changed_pixels=0`、`changed_pixel_ratio=0.0`、`frames_waited=1`、`status=done` |

**这两行就是任务书要的「报成功但画面没变 → `changed:false`」与「真实变化 → `changed:true` + ratio>0」。**

捕获行原文（`traces\trace-editor.jsonl`，可 `grep '"seq":27'`；两份响应分别落在
`phase6-capture\p6_real_change__0027__bbe26972.response.json` 与
`phase6-capture\p6_same_args_same_value_replay__0028__d8bd1c01.response.json`）：

```json
{"after":{"bytes":29464,"path":"res://mcp065b_shots/0027_after.png","sha256":"176c8a2e6a802b3330b5eaab1fea8eab8bb8f644ac6eddec70b177cea9169474",...},"before":{"bytes":29159,"path":"res://mcp065b_shots/0027_before.png","sha256":"42d58bb2295e2cea30dc143cbbbc8de9073cefa0ecb6644ad6d5dde55485ef46",...},"changed":true,"changed_pixel_ratio":0.00766933704307781,"changed_pixels":10232,"event":"capture","frames_waited":1,"mode":"every_call","scale":2,"seq":27,"status":"done","tool":"editor_set_node_property","total_pixels":1334144,"viewport":"2d"}
{"after":{"bytes":29464,"path":"res://mcp065b_shots/0028_after.png","sha256":"176c8a2e6a802b3330b5eaab1fea8eab8bb8f644ac6eddec70b177cea9169474",...},"before":{"bytes":29464,"path":"res://mcp065b_shots/0028_before.png","sha256":"176c8a2e6a802b3330b5eaab1fea8eab8bb8f644ac6eddec70b177cea9169474",...},"changed":false,"changed_pixel_ratio":0.0,"changed_pixels":0,"event":"capture","frames_waited":1,"mode":"every_call","scale":2,"seq":28,"status":"done","tool":"editor_set_node_property","total_pixels":1334144,"viewport":"2d"}
```

**另有第二类 `changed:false`（只读调用的幂等重放）**：`editor_get_scene_tree{max_depth:-1}` 连调两次（seq 25/26），
两次捕获行都是 `changed=false, 0 px`，且捕获行与请求**一一对应**（`c6_capture_lines_map_one_to_one_to_the_calls` PASS：
32 条捕获行 ↔ 32 次 `tools/call`，工具名逐个相符）。

### 3.3 三路一致（日志 / 工具 / 独立复算）

| 路 | 手段 | 真实变化对 | 幂等重放对 |
|---|---|---|---|
| ① **日志** | `trace-editor.jsonl` 的 capture 行（引擎自己算） | `changed_pixels=10232` / `total=1334144`（ratio `0.00766933704307781`） | `0` / `1334144`（ratio `0.0`） |
| ② **工具** | `editor_analyze_screenshot_diff{image_a:<before>, image_b:<after>}`（**同一对落盘 PNG**，`res://` 路径） | `changed_pixels=10232` / `total=1334144`、`identical=false`、`threshold=10`、响应 sha256 `3995d85a8200245688b8e3d643507a4b455d5be2c79f185b4644f6685e5db325` | `changed_pixels=0` / `total=1334144`、**`identical=true`**、响应 sha256 `223309246b1a41a825d7a4cd5876146c9b88b0393cb9ba58e7813f2ce73e449c` |
| ③ **独立复算** | `scripts\mcp065b_pixel_recompute.py`（PIL 解码 + 复刻模块的判据 `max(|dr|,|dg|,|db|) > 10`，**alpha 不参与**） | `10232` / `1334144`、`identical=false`、ratio `0.007669337043077809` | `0` / `1334144`、`identical=true` |

- `pixel_recompute.json` → `all_three_routes_agree = **true**`（`log_matches_independent=true`、`tool_matches_independent=true`，两对都是）。
- 三路用的是**同一对落盘文件**（sha256 已核）：`real_change.before.png` = `42d58bb2…`、`real_change.after.png` = `176c8a2e…`；
  幂等对两张都是 `176c8a2e…`（同一张图 ⇒ 0 px，这正是「画面没变」的物理含义）。
- 复算的口径**不是「看起来像」**：`mcp065b_pixel_recompute.py` 的规则注释逐字引用了
  `tools\tool_helpers.cpp` 的 raw-byte 路径（`max_diff > p_threshold` 计数、alpha 不读），与 `editor_analyze_screenshot_diff`
  与捕获内部调的是**同一个** `compare_screenshot_pixels`（GDR-25）。

### 3.4 `mcp_evidence_guard.ps1` 的两条规则

- **唯一命名**：本次 127 个证据文件全部走 `Write-McpEvidenceBytes`（`<leaf>__<seq:04d>__<sha8>.<ext>`），
  `Assert-McpEvidenceTreeUniqueness` = `collisions=0 / duplicate_names=0`；
  名字里的 sha8 与文件内容 sha256 **由函数自身断言相等**（写后重算）。
- **before → between → after 且断言两 sha 不同**：`Write-McpEvidenceSnapshotPair -Leaf p6_main_tscn`
  - **before** = `proj-editor\scenes\main.tscn` 字节 → `p6_main_tscn.before__0001__3cad0f2d.tscn`（sha8 `3cad0f2d`，661 B）
  - **between** = `editor_set_node_property{Box.position → 260,150}`（seq 29）→ `editor_save_scene{path:"res://scenes/main.tscn"}`（seq 30）
  - **after** = 同一文件字节 → `p6_main_tscn.after__0001__36af27ad.tscn`（sha8 **`36af27ad`**，与 before **不同**）
  - `c6_snapshot_pair_differs` PASS；这正是「被测调用真的改了盘上的东西」的**可归因**证据
    （第 2 轮 D-9/P4b 的退化对照——两个快照同 sha——在本批的构造下不会发生）。

---

## 4. 游戏侧活链（9889）—— **通过（真正构造，实测）**

进程：`… console.exe --headless --path %TEMP%\mcp065b\proj-game --mcp-port=9889 --mcp-trace=…`。
`[MCP] role=game` 行存在、**没有** `bind failed`（第 2 轮 D-7 的静默失能签名缺席）、`tools/list` 72 条。
**注入输入的工具与读回的工具是不同工具**（这是判据的原话）：

| 角色 | 工具 |
|---|---|
| 注入 | `running_game_run_test_scenario`（`steps[].type=input`，`action`，`pressed`） |
| 读回 | `running_game_get_node_property_samples`、`running_game_get_node_properties`、`running_game_find_nodes_by_script`、`running_game_get_scene_tree` |

### 4.1 ① 注入输入 → 另一工具读回**位置真的变化**（多帧、非瞬移、给采样）

1. `g7_inject_paddle_right`（seq 38）：`steps=[{"type":"input","action":"paddle_right","pressed":true}]`
   → `{"injected":1,"step":0,"type":"input"}`（`game-live-chain\g7_inject_paddle_right__0038__d88aa41f.response.json`）
2. `g7_paddle_position_samples`（seq 39，**另一个工具**）：`{node_path:"Paddle", properties:["position"], frame_count:24, frame_interval:1}`
   → **24 个样本、24 个不同的 x、逐帧严格单调递增**：
   ```
   321, 328, 335, 342, 349, 356, 363, 370, 377, 384, 391, 398,
   405, 412, 419, 426, 433, 440, 447, 454, 461, 468, 475, 482
   ```
   每帧 **+7.0 px**（`420 px/s ÷ 60 Hz`，正是 `paddle.gd` 的 `SPEED`）——**这就是「非瞬移」**：
   425 px 的位移分布在 24 个连续帧上，`distinct_x=24`、`monotonic=True`、`per_frame_delta=6.708`（`c6` 同族检查 `g7_another_tool_read_the_motion_over_many_frames` PASS）。
   （`game-live-chain\g7_paddle_position_samples__0039__e8cbf40c.response.json`）
3. `g7_paddle_position_after`（seq 40）：`position={496,560}`、`moves=28`（`g7_injected_input_moved_the_paddle` PASS：300 → 496）
4. `g7_release_and_assert_moves`（seq 41）：`pressed:false` + **进程内断言** `Paddle.moves > 0`
   → `{"all_passed":true,"passed":1,"failed":0,"errors":0,"results":[{"injected":1},**{"actual":31,"expected":0,"operator":"gt","passed":true,"property":"moves"}**]}`

**球也一样**（`g7_ball_position_samples`，seq 43，注入 `launch` 之后立即采样 18 帧）：
```
y: 312, 308, 304, 300, 296, 292, 288, 284, 280, 276, 272, 268, 264, 260, 256, 252, 248, 244
```
严格逐帧非增（每帧 −4 px = `240 px/s ÷ 60 Hz`），从 `{300,320}` 走到 `{300,180}` 并击中 `Brick0`。

### 4.2 ② 砖块**真的消失/减少**

| 时点 | 工具 | 结果 |
|---|---|---|
| 前（seq 36） | `running_game_find_nodes_by_script{script:"res://scripts/brick.gd"}` | `count=3`（`Brick0, Brick1, Brick2`） |
| 后（seq 45） | 同一工具 | **`count=2`**，`nodes=[Brick1, Brick2]` |
| 前/后（seq 34 / 47） | `running_game_get_scene_tree` | 解析后的场景树里 `Brick0`：**前 true → 后 false**；`Brick1`/`Brick2` 仍在 |

消失的机制在 fixture 里是真实的引擎行为：`ball.gd` 在 `_physics_process` 里按距离判定命中 → `main.add_score(10)` → `brick.queue_free()`；
`queue_free()` 在帧末真正删除节点，所以**下一次调用**（另一个帧）读回的是已经少了一个的集合。
（`game-live-chain\g7_bricks_before__0036__fca17599.response.json` / `g7_bricks_after__0045__bda0e228.response.json` /
`g7_scene_tree_before__0034__9a1b6079.response.json` / `g7_scene_tree_after__0047__97d67ecf.response.json`）

### 4.3 ③ 计分**真的变化**

| 时点 | 工具 | 结果 |
|---|---|---|
| 前（seq 37） | `running_game_get_node_properties{node_path:"HUD/ScoreLabel", properties:["text"]}` | `"text":"Score: 0"` |
| 后（seq 46） | 同一工具 | **`"text":"Score: 10"`** |
| 进程内（seq 44） | `running_game_run_test_scenario` 的 assert 步骤 | `{"all_passed":true,"passed":1,"failed":0,"results":[{"type":"wait","waited_seconds":1.2},{"injected":1},{"actual":**10**,"operator":"gt","expected":0,"passed":true,"node_path":"Main","property":"**score**"}]}` |

即：**分是节点自己算出来的（`Main.score`），并且被另一个工具从 UI 文本上读回来了**——两路一致。
（`g7_score_text_before__0037__6cb36424.response.json` / `g7_score_text_after__0046__fd93609d.response.json` /
`g7_wait_and_assert_score__0044__2528cd34.response.json`）

### 4.4 ④ 不可构造项

**游戏侧三条判据本轮全部构造出来**，无「不可构造」项。仍然空白的项在 §6（性质是「没测」，不是「不可构造」）。

---

## 5. 观察覆盖与证据纪律

### 5.1 `mcp_watch_run.ps1`：`stop_reason = marker`

`workdir=%TEMP%\mcp065b\watch` 的 `watch-summary.txt`（**绝对路径副本**：
`…\docs\reports\evidence\task065b\watch\watch-summary.txt`，sha256 = `4ef9b02f4d4a3301757ca426cb651cc680e106dcd22bf8de1c49780405cb06e2`）：

```
stop_reason=marker            exit_code=0
elapsed_sec=40                polls=9
last_seq=32                   trace_lines=142
trace_files=3                 activity_seen=1     stale_age_sec=0
observation_stopped_before_development_ended=0
trace=C:\Users\wyl\AppData\Local\Temp\mcp065b\trace-editor.jsonl lines=65 last_seq=32 missing=0
trace=C:\Users\wyl\AppData\Local\Temp\mcp065b\trace-game.jsonl   lines=16 last_seq=15 missing=0
trace=C:\Users\wyl\AppData\Local\Temp\mcp065b\PROGRESS.md        lines=61 last_seq=0  missing=0
```

机器判据（全部 PASS）：`w8_stop_reason_is_marker`、`w8_watch_had_activity`（`activity_seen=True`）、
`w8_watch_saw_the_trace_lines`（`trace_lines=142`、`last_seq=32`，**> 0**）、`w8_watch_covered_all_three_sources`（`3/0 missing`）、
`w8_watch_saw_the_development_finish`（`observation_stopped_before_development_ended=False`）、
`w2_watcher_received_three_trace_paths`（`watch.log` 头里 `trace_path[0..2]` 三条齐备 —— 这条判据是 §6-F2 的回归闸）。

> **观察者的终止点是 marker**：观察者是被**运行结束**（marker）停下的，不是被预算停下的
> （`timeout_sec=1800` / `stale_sec=600` 都远未触发），且它**确实看到了** 142 行痕迹与开发结束。
> 最终块单独抽出为 `watch\watch-run-final.log.txt`（sha256 `d7e7b156a2c2a45147a0f84f4643e4460610ffac0af875ea416447b9ec68b32f`），
> 理由见 §6-O3（`watch.log` 是 append-only 的）。

### 5.2 纪律逐条

| 要求 | 实测 |
|---|---|
| 绝不占用/杀/重启 **9877** | 前后两次 `netstat`：9877 **无监听者**；本批**从未**对它做任何动作（`Add-Heartbeat` 里逐条记录了本批启停的 PID） |
| 端口 **9888 / 9889** | 编辑器 9888 / 游戏 9889；运行结束时 `p8_9888_9889_released` PASS |
| 禁止 push | 本批**未执行**任何 `git push`（`feature/mcp-server-module` 无上游） |
| 不抑制 / 不并发 scons | 本批**没有跑 scons**（§7.1 说明为什么不需要重建） |
| **绝不改模块实现** | `git diff --stat -- tools / tests / 契约 / 映射 / 清单` 全部 **0 行**（§7.2） |
| `.ps1` 纯 ASCII | 本批新增的 5 个 `.ps1` 全部纯 ASCII（`>127` 字节数 = 0） |
| 产物绝对路径 | 127 个证据文件 + 本报告全部在 `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\...` 下（`%TEMP%` 只作 scratch，并已整份复制进来） |

---

## 6. 发现（按影响面排序）

### F1 `[试测产物缺口]` 第 2 轮的 breakout C# 工程**不具备**判据 ②③ 所需的游戏行为 · **major（对「为什么第 2 轮是空白」的解释）**
- **最小复现**（只读，全部可当场核对）：`Get-ChildItem %TEMP%\mcp-breakout\proj\scenes\main.tscn`（**54 B**）；
  `%TEMP%\mcp-breakout\proj-scene\scenes\main.tscn` 里 `Paddle`/`Ball` 节点**无 `script =`**、所有 `StaticBody2D` **无 `CollisionShape2D`**；
  `proj\project.godot` 无 `launch`/`paddle_*` 动作；全工程 `grep -c "\.Hit()"` = **0**。
- **后果**：即使当时把工具全部调通，也**读不到**砖块减少与分数变化 —— 判据②③的**观察对象不存在**。
- **处置**：本批**新造 GDScript fixture**（§1.2）并在报告里声明；**不建议**在模块侧为它做任何事（这不是模块缺陷）。
- **建议**：下一轮若仍要「C# 真工程」的游戏侧证据，**先修 fixture**（挂脚本 / 加碰撞形状 / 加分数 Label / 加动作），
  否则任何工具链证据都会是空的；或者沿用本批的 GDScript fixture（它把「引擎真的在跑」这件事与「C# 能不能跑」解耦）。

### F2 `[流程/工具]` `mcp_watch_run.ps1` 在**最常见的启动方式**下会丢掉整段观察，而且第二次「看起来成功」 · **major**
- 反例探针（**本批新增，可重跑**）：`modules\mcp_server\scripts\mcp065b_watch_invocation_probe.ps1`
  → `probes\watch-invocation-probe.json` + 4 个 stdout/stderr 文件；探针自身 PASS（两种失败模式都复现）。
- **形态 A（自然写法）**：`powershell -File mcp_watch_run.ps1 … -TracePath a -TracePath b` →
  非零退出（**1**，不是脚本文档里写的 `2`）、stderr `ParameterAlreadyBound`、
  **没有 `watch.log` 头、没有 `watch-summary.*`** ⇒ **整段观察为 0，且只体现在 stderr 里**。
  （`-File` 不允许同一参数被绑定两次；这不是脚本能拦住的错误，因为它在脚本执行前就抛出了。）
- **形态 B（第一次尝试的「修法」）**：把三路来源写成**一个逗号串** `-TracePath "a,b,c"` →
  **exit 0、`stop_reason=marker`、summary 一应俱全**，但 `watch.log` 头写着 `trace_path[0]=a,b,c`（**一条**路径）、
  `trace_files=1 missing=1 trace_lines=0 activity_seen=0` ⇒ **「成功」的观察其实什么都没看到**，而 `stop_reason` 仍然是 `marker`。
- **本批采用的可用启动方式**（已实测）：`powershell -EncodedCommand <base64(UTF-16LE)>`，
  命令串里写 `-TracePath 'a','b','c'`（真正的 PowerShell 数组），并把命令串原文记进 `PROGRESS.md` 心跳（可复现）。
- **建议（留给决策者，不在本批改共享脚本）**：①给 `mcp_watch_run.ps1` 增加一个**单值**参数
  （如 `-TracePathList "a;b;c"`）或让它对**传入的单个逗号串自动 split**；②在 summary 里加一个
  **自检字段**（`trace_files_declared vs resolved`），让「声明了 3 条、只解析出 1 条」这件事**在 summary 里就失败**，
  而不是靠调用方自己看 header。

### F3 `[流程]` 本计划书要求的「观察覆盖」判据，在第 2 轮与第 3 轮都会因 F2 静默失效
- 与 F2 同根：`stop_reason` 是**观察者的自述**，它**不能**证明观察者真的读到了东西。
  本批因此把「`stop_reason=marker`」与「`activity_seen=1` + `trace_lines>0` + `trace_files=3/missing=0`」
  **拆成 5 条独立判据**（§5.1）——建议**后续任务书照此写法**。

### O1 `[判据缺陷，本批自己踩到并修正]` 「同 scope 三次调用逐字节相同」不能用**整个 HTTP 响应**
- 第一版判据比较 `response sha256`，三次必然不同 —— 因为响应里带 JSON-RPC `id`。
  **修正**：比较 `result.content[0].text`（工具结果体）的 sha256（`c5_three_calls_per_scope_have_identical_result_bodies`）。
- 同理，`phase5_scope.json` 里 `user_set_minus_default`（空集）被 PowerShell 序列化成 `{}` —— 空集合的**序列化产物**，
  判定以「`user ∪ internal = default` 且 `∩ = ∅`」这条集合等式为准（§2.2）。

### O2 `[文档口径]` `counts` 的过滤顺序没写进契约（见 §2.4-O1，建议补一句描述）

### O3 `[证据卫生]` `mcp_watch_run.ps1` 的 `watch.log` 是 **append-only**，同一 `-OutDir` 重跑会累加
- 实测：本批最终 `watch.log` 共 **34 行**（含前一次失败观察的块），最后一块（18 行）才是被引用的那次；
  `watch-summary.*` 是**每次重写**的（所以 summary 只描述最后一次）。
- 处置：本批把最终块单独抽成 `watch\watch-run-final.log.txt` 并在报告里引用它；**不建议**把累计文件当单一证据。

### O4 `[正面确认，不是缺陷]` 本批没有发现 ⑤/⑥ 的产品缺陷
- `scope` 的过滤、计数、枚举拒绝、`signal_name` 组合、`counts` 自洽性**全部与契约/实现注释一致**；
- 捕获的 `changed` / `changed_pixel_ratio` / `frames_waited` / `scale` / `viewport` 与**独立复算逐位一致**；
- 游戏侧 15 次调用的错误码：**0 个错误**（全部 `id`+`result`，无 `-326xx`）。

### 6.1 **仍空白项**（任务书要求「明确声明」；性质是**没测**，不是「不可构造」）

| # | 仍空白 | 为什么没测 | 若要补，怎么补 |
|---|---|---|---|
| B1 | **游戏端的窗口化捕获族**（`running_game_capture_screenshot` / `running_game_capture_frames`） | 本轮游戏进程是 `--headless`（判据①②③不需要渲染），而捕获族在 headless 下**按设计**返回 `-32000`（无帧缓冲）。**这是能力边界，不是缺陷**，但本轮同样**没有**给出窗口化游戏进程的帧证据 | 去掉 `--headless` 起游戏端（需要显示服务），再调 `running_game_capture_frames` |
| B2 | **`--mcp-capture=on_error`** 与 **`--mcp-capture-diff-image=on`** | 本轮只测 `every_call` + `diff_image=false`（`every_call` 是本轮判据明令的模式；`diff` 图只是人眼产物） | 同一条捕获脚本加两个开关即可，判据现成（`diff` 字段会出现 `path/bytes/sha256`） |
| B3 | **`--mcp-capture-scale=1` / `=4`** | 本轮只用判据指定的 `scale=2` | 换开关重跑；`scale` 已逐行出现在捕获行里，可直接对比例 |
| B4 | **`scope` 与 `node_path` 的组合** | 本轮 20 次调用都**没有**传 `node_path`（只测了 `scope` × `signal_name`） | 在同一个 fixture 上补 3 组：`node_path:"Timer"` × `scope ∈ {all,user,internal}` |
| B5 | **`user` 集合里两种来源的区分**：场景文件里的 `[connection]` vs 运行期 `connect()` 建的连接 | 本轮 fixture 只有前者（2 条） | 用 `editor_connect_signal`（或 `editor_execute_gdscript` 调 `connect()`）在编辑期再连一条，看它是否同样归入 `scope:"user"` |
| B6 | **`editor_analyze_screenshot_diff` 的拒绝路径**（尺寸不一致 / 超过 `MAX_DIFF_DIMENSION` / 非法 base64） | 本轮只用它复核两个正常对 | 三条负例请求各一组即可（契约里 `-32602` 的两种 message 已写明） |
| B7 | **C# 工程上的同一套活链** | 本批 fixture 是 GDScript（F1 已说明第 2 轮 C# 工程不可用）；**F1 的修复路径（给 C# 工程挂脚本/加碰撞/加分数 Label）未被验证** | 先按 F1 修 fixture，再用**同一批** 15 个游戏侧调用重跑（本批脚本可直接复用，只改 `-GameProject`） |
| B8 | **多进程/多次会话的 `scope` 稳定性** | 单进程、单会话、单场景；`scope` 的 `internal` 数量依赖编辑器当前界面（本轮 45 条） | 换一个场景/界面状态重跑，比较 `counts` 变化（这属于「形态是否稳定」的问题，不是正确性问题） |

> 以上 8 条**没有任何一条**削弱 §0 的结论：本轮三条判据要求的**最小构造**都已完成，且是可复算的实测；
> B1–B8 是「同一能力的其它口径/其它开关/其它进程形态」，列在这里是为了让下一轮不必重新发现它们。

---

## 7. 锚点、纪律与偏差

### 7.1 为什么**不重建**二进制（并对 D86 诚实标注）

```
Command : git diff --stat 7708729982..HEAD -- modules/mcp_server/tools modules/mcp_server/tests
                                              modules/mcp_server/docs/tools_list.renamed.json
                                              modules/mcp_server/scripts
Exit    : 0
Output  : []                                    <- 空
Command : git rev-parse HEAD                    -> 08691fd21e90a86497ee3469999217c646a64e2b
Command : git log -1 --format=%h -- <tools|tests|contract>   -> 92a260b682
Command : bin\godot.windows.editor.x86_64.console.exe --version
Output  : 4.8.dev.custom_build.770872998
```
即：**二进制自报的 `770872998` 与 HEAD `08691fd21e` 之间，`tools/**`、`tests/**`、契约、`scripts/**` 一个字节都没变**
（中间 4 个提交全是 `docs/**`）。因此本轮**不需要重建**即可保证「测的是当前工作树的模块代码」；
代价是必须**如实标注**「HEAD ≠ 二进制 sha」（TASK-065A §5.6 已把这个结构性冲突写清楚，本批沿用它的口径）。
A 部分（TASK-065A）已经在 `770872998` 上重建过 mono/plain，本批**不再重复构建**（也避免并发/耗时风险）。

### 7.2 未改实现 / 未改契约（逐条打印）

```
git diff --stat -- modules/mcp_server/tools                              -> 0 line(s)
git diff --stat -- modules/mcp_server/tests                              -> 0 line(s)
git diff --stat -- modules/mcp_server/docs/tools_list.renamed.json       -> 0 line(s)
git diff --stat -- modules/mcp_server/docs/tool-rename-map.json          -> 0 line(s)
git diff --stat -- modules/mcp_server/docs/tool-groups.json              -> 0 line(s)
git diff --stat -- modules/mcp_server/docs/tool-groups-added.json        -> 0 line(s)
contract sha256 = d4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd
```
`git status --short`（收尾）：只有 **4 个既有未跟踪物**（`.graphifyignore`、`build-m0.cmd`、`graphify-out/`、`install-deps-m0.cmd`）
+ 本批新增的**证据目录**与**5 个 harness 脚本**（`scripts\mcp065b_*.ps1|.py`），**没有任何 ` M ` 行**。

### 7.3 偏差（显式列出）

1. **游戏侧 fixture 是 GDScript 而不是沿用第 2 轮的 C# 工程**（理由与实测见 §1.1 / F1）。这是对「沿用原 fixture」的**实质偏离**，
   如实声明：判据①②③ 证明的是**模块的游戏侧工具链**能在真实游戏里观察到真实状态变化，而**不是**「C# 工程可玩」。
2. **观察者用 `-EncodedCommand` 启动**（而不是 `Start-Process -File`）：见 F2；这是**绕开一个已复现的调用缺陷**，
   不是绕过纪律 —— `mcp_watch_run.ps1` 本身**一个字节都没改**，且 `stop_reason=marker` 等四条机器判据都通过。
3. **本批新建了 6 个 harness 文件**（5 个 `.ps1`：`mcp065b_env.ps1`、`mcp065b_fixtures.ps1`、`mcp065b_run.ps1`、
   `mcp065b_finalize.ps1`、`mcp065b_watch_invocation_probe.ps1`，加 1 个 `.py`：`mcp065b_pixel_recompute.py`）落在 `modules\mcp_server\scripts\`。
   **共用的三个脚本 `mcp_watch_run.ps1` / `mcp_evidence_guard.ps1` / `mcp_import_guard.ps1` 一个字节都没改**
   （`git diff --stat` 为空，§7.2）。这些新文件是**测试产物**（不是实现、不是契约、不是规范文档），
   符合 PLAYBOOK §5「只允许修改 `modules\mcp_server\**`」；若决策者希望它们搬出仓库，迁移只需改三处绝对路径常量。
4. **未跑** `accept_m1.ps1` / `mcp057_gates.ps1` / 15 步回归电池：本批是**缺口专项**（TASK-065 §B 明写「B 部分不改代码，只记录」），
   A 部分（TASK-065A）已在同一 HEAD 上跑过五道门 + 门⑥三段式；B 部分新增的判据是 71 条自校验。
5. **`watch.log.txt` 含两次观察的累计内容**：见 O3，已把被引用的最终块单独抽出。

---

## 8. 复现（照抄可重算本文所有数字）

```cmd
:: 0) 端口前提（9877 必须无监听者；本批从不触碰它）
netstat -ano | findstr ":9877 :9888 :9889"

:: 1) fixture + 观察 + ⑤ + ⑥ + 游戏侧活链，一次跑完（约 2 分钟）
cd /d F:\RustProjects\godot-mcp-pro\code\godot
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp065b_run.ps1
:: 期望末行：TASK-065B RESULT checks_passed=71 checks_failed=0 stop_reason=marker   （exit 0）

:: 2) 把 %TEMP% 侧产物收进仓库绝对路径 + 生成 manifest + 打印被引用的数字
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp065b_finalize.ps1

:: 3) F2 的两个反例探针
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp065b_watch_invocation_probe.ps1

:: 4) 三路一致里第 3 路的单独重算（给定 pixel-pairs.json）
python modules\mcp_server\scripts\mcp065b_pixel_recompute.py %TEMP%\mcp065b\io\pixel-pairs.json <out.json>
```

---

## 9. 交付物清单（绝对路径前缀 `F:\RustProjects\godot-mcp-pro\code\godot\`）

| 路径 | 说明 |
|---|---|
| `modules\mcp_server\docs\reports\BREAKOUT-FINDINGS-R3.md` | **本报告** |
| `modules\mcp_server\docs\reports\evidence\task065b\run-summary.json` | 71 条判据 + 观察者 summary + 路径（机器可读总账） |
| `…\evidence\task065b\phase5_scope.json` | ⑤ 的 20 次调用、三套集合、集合差、体积、三个结果体 sha256 |
| `…\evidence\task065b\phase6_capture.json` | ⑥ 的调用表、**32 条捕获行**、两条主捕获、工具路响应、快照对、三路一致 |
| `…\evidence\task065b\game_live_chain.json` | 游戏侧 15 次调用与全部读回值（含 24 帧位置采样与 18 帧球采样） |
| `…\evidence\task065b\pixel_recompute.json` | 第 3 路的独立复算与「三路一致」断言 |
| `…\evidence\task065b\evidence-manifest.txt` | 126 行 `sha256  size  path`（不含 manifest 自身；manifest sha256 `e0c010d3…`，两次连跑逐字节相同） |
| `…\evidence\task065b\{phase5-scope,phase6-capture,game-live-chain,shots,traces,watch,probes,process-logs}\` | 全部原始请求/响应/PNG/轨迹/观察/探针/进程日志（§1.4 的分布） |
| `modules\mcp_server\scripts\mcp065b_env.ps1` | 共享 harness（MCP 调用、证据守卫接线、端口/PID 助手） |
| `modules\mcp_server\scripts\mcp065b_fixtures.ps1` | 两个 scratch fixture 的写出（UTF-8 无 BOM） |
| `modules\mcp_server\scripts\mcp065b_run.ps1` | **编排器**（71 条判据，`exit 0` 表示全过） |
| `modules\mcp_server\scripts\mcp065b_finalize.ps1` | 产物回收 + manifest + 被引用数字打印 + 收尾核实 |
| `modules\mcp_server\scripts\mcp065b_watch_invocation_probe.ps1` | F2 的反例探针（两种失败模式） |
| `modules\mcp_server\scripts\mcp065b_pixel_recompute.py` | ⑥ 第 3 路独立复算（复刻模块判据） |

**返回给决策者**：见 §0（≤6 行）。