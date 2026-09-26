# BREAKOUT-FINDINGS-R4 — TASK-066 §B：在 A 的 **C# 工程**上重跑整套活链 + ⑤⑥ + 前 8 条空白

> **D86 锚点**（本报告的全部结论只在这些锚点上成立）
> - **被测二进制** = `bin\godot.windows.editor.x86_64.mono.console.exe`，`--version` = **`4.8.dev.mono.custom_build.770872998`**
>   （本批**没有重建**，理由见 §10.1）。
> - **被测工作树** = `git rev-parse HEAD` = **`a27d7d7ba17d864522ee5fb24a98b60040bc5705`**（分支 `feature/mcp-server-module`）。
> - **最后一个改动 `tools/**`、`tests/**`、契约的提交** = **`92a260b682`**；
>   `git diff --stat 7708729982..HEAD -- modules/mcp_server/tools modules/mcp_server/tests
>   modules/mcp_server/docs/tools_list.renamed.json modules/mcp_server/docs/tool-rename-map.json
>   modules/mcp_server/docs/tool-groups.json` = **空**（本报告 §10.2 逐条打印）。
>   同一区间的 `modules/mcp_server/scripts` 只有 **6 个 TASK-065 B 新增的 harness 脚本**（1520 行，§10.2）。
>   ⇒ **二进制里的模块实现 == 工作树里的模块实现**。
> - **被测 C# 工程** = `%TEMP%\mcp-breakout-cs\proj`（A 的交付物）；本批先**逐字节复制**到
>   `%TEMP%\mcp066b\proj-cs` 再跑，复制后 **176 个源文件全部 sha256 相同**（`p0_project_copy_is_byte_identical`）。
>   A 报告里列的 **10 个 sha256 在盘上全部 MATCH**（§8.1）——**A 的 fixture 主张经独立复核成立**。
> - **契约** `docs/tools_list.renamed.json` sha256 = **`d4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd`**
>   ——与 TASK-065A/R3 的基线**逐字相同**（本批前后同 sha，§10.3）。
> - **线上契约拆分事实**：编辑器 9888 `tools/list` = **153**，游戏 9889 = **72**（其中 `running_game_*` **23**、`editor_*` **0**）。
> - **本报告自身的提交锚点**：本批是**试测/取证批次**，只写脚本与报告，**不做提交**（与 R3 §7.2 同口径，父层决定何时提交）。
>   交付时工作树新增 **4 个未跟踪的 harness 文件**（`scripts\mcp066b_{env,run,finalize}.ps1` + `mcp066b_make_pngs.py`）、
>   **未跟踪的报告** `docs\reports\BREAKOUT-FINDINGS-R4.md`、**未跟踪的证据树** `docs\reports\evidence\task066b\`（**358 文件**）。
>   全树可由 `evidence\task066b\evidence-manifest.txt`（356 行 `sha256 size path`，sha256 `224984f49eb1947c…`）逐行核对。
> - **D-119 纪律**：本报告与全部产物一律写**绝对路径**（前缀 `F:\RustProjects\godot-mcp-pro\code\godot\`），scratch 除外并显式标注。

---

## 0. 结论（先给答案）

| # | 任务书要求 | 结论 | 关键数字 | 证据 |
|---|---|---|---|---|
| ① | `mcp_watch_run.ps1` 保证覆盖，**`stop_reason` 必须是 `marker`** | **通过** | `stop_reason=marker`、`elapsed_sec=76`、`polls=16`、`activity_seen=1`、`trace_lines=203`、`trace_files=6 / missing=0`、`observation_stopped_before_development_ended=0` | §6.1 |
| ② | `mcp_evidence_guard.ps1`（唯一命名 + 快照 before→between→after + **断言两 sha 不同**） | **通过** | 356 文件、`collisions=0`、`duplicate_names=0`；快照对 `d33b8931…` → **`ec0b9826…`**（2890 B → 2910 B，**不同**） | §6.2 |
| 活① | 输入 → **挡板/球位置逐帧单调变化**（给采样） | **通过** | 挡板 **24 帧 24 个不同 x、严格单调**：`313.98 → 475.03`（每帧 **+7.0 px = 420/60**）；球 **18 帧 18 个不同 y、严格递减**：`311.38 → 237.74`（每帧 **−4.3 px = 260/60**） | §2.1 |
| 活② | 砖块命中后**节点集合真的减少** | **通过** | `running_game_find_nodes_by_script{Brick.cs}`：**3 → 2**（存活 `Brick1,Brick2`）；解析后的整棵树 `Brick0` 前 True → 后 False | §2.2 |
| 活③ | **分数真的变化**（读回 Label/属性 + **进程内断言**） | **通过** | `HUD/ScoreLabel.text` `Score: 0` → **`Score: 10`**；`Main{Score=10,BricksHit=1,State=playing}`；进程内断言 `Score gt 0` **actual=10 passed=true** | §2.3 |
| ⑤ | `scope:user`：默认/user/internal **各 ≥3 次**，且 **user ∪ internal = default、∩ = ∅** | **通过** | 默认 **207**（44 751 B）/ user **1**（275 B）/ internal **206**（44 658 B）；`union=207`、`intersection=0`；同 scope 三次**结果体逐字节相同**；显式 `all` == 默认（体 sha `f21a9805`）；`bogus` → `-32602` | §3 |
| ⑥ | 窗口化「报成功但画面没变」→ `changed:false`；真实变化 → `changed:true`；**日志/工具/独立复算三路一致** | **通过** | 真实变化 **2660/1334144**（ratio `0.00199378777703156`）；同参同值重放 **`changed:false` / 0 px / 前后 sha 同为 `37062f00`**；三路（trace 行 / `editor_analyze_screenshot_diff` / PIL 独立复算）**逐位一致**，`all_three_routes_agree=true` | §4 |
| 空白 | B1 游戏端窗口化捕获族 | **收了** | 游戏窗口化（**无 `--headless`**）：screenshot `1152x648`（PNG，8107 B）；`save_path` → `user://b066_shot.png`；`capture_frames` 半分辨率 `3×576x324`（engine frames 592/602/612，间隔 10）、全分辨率 `2×1152x648`；移动可见节点后帧 sha **`3aaa17cb` → `8f0a0546`**（真的跟着屏幕走） | §5.1 |
| 空白 | B2 `on_error` 与 `diff_image` | **收了** | `on_error`：**成功调用 0 条捕获行**、**失败调用 1 条捕获行**（全会话捕获行数 = 1 = 失败数）；`diff_image=on`：`diff.path/bytes/sha256` 三字段齐备（`0005_diff.png`，118 122 B） | §5.2 |
| 空白 | B3 `scale 1/4` | **收了** | scale1 **2978×1793 = 5 339 554**；scale2 **1489×896 = 1 334 144**（每轴 `floor/2`）；scale4 **744×448 = 333 312**（每轴 `floor/4`）——**逐轴取整**，不是「像素数正好 ÷4」 | §5.3 |
| 空白 | B4 `scope × node_path` | **收了** | `node_path:"ProbeTimer"`：all **11** / user **1** / internal **10**；`counts = 11-1-10`；**仍然划分**（user+internal = all） | §5.4 |
| 空白 | B5 连接来源区分 | **收了（并报一条形态缺口）** | 运行期 `connect()` 造的 `ProbeTimer|timeout|Ball|queue_free` **确实进 `user`**（1→2），且**不在 `.tscn` 里**；但两种来源的连接条目**键集完全相同**（`method,signal,source,target`）⇒ **工具不暴露「场景文件连接 vs 运行期连接」的任何字段** | §5.5、§7-F2 |
| 空白 | B6 diff 工具拒绝路径 | **收了** | 非法 base64 → **`-32001`**；尺寸不一致（64×64 vs 64×32）→ **`-32602`**；超 `MAX_SCREENSHOT_DIFF_DIMENSION=4096`（4097×1）→ **`-32602`**；`threshold:999` → **`-32602`** | §5.6 |
| 空白 | **B7（本轮主目标）C# 工程上的同一套活链** | **收了** | 见上三行「活①/②/③」：**全部在 C# 工程上**（5 个 `.cs`、mono 二进制、9889 窗口化）；**判据 1/2/3 各配独立的第二读取工具 + 进程内断言** | §2 |
| 空白 | B8 多进程 scope 稳定性 | **收了** | 4 个**互相独立**的编辑器进程（A/B/C/D）：`internal` **全部 = 206**、`user` 全部 = 1、`default` 全部 = 207；且与 **A 报告的 207/1/206 逐项相同** | §5.8 |
| 纪律 | 不碰 9877、端口 9888/9889、禁止 push、不抑制/不并发 scons、**不改模块实现/契约** | **全部满足** | 9877 全程无监听；本批**一次 scons 都没跑**；`git status --porcelain` 对 `tools/tests/契约/映射/清单` = **0 条**；收尾 9888/9889 已释放 | §10 |

**一句话**：**第 2 轮留下的「C# 工程不可用」缺口（F1）被 A 修复后，本轮在 C# 工程上把整条游戏侧活链、⑤ `scope`、⑥ 窗口化 `changed:false` 与第 3 轮的全部 8 条空白一次性构造出来**，
并且全部判据可复算（**88/88 通过**，`B066 RESULT checks_passed=88 checks_failed=0`）；过程中**对 A 的报告提出 2 条纠错、独立确认 A 的 3 条主张**（§8），
另外把两个**证据/流程陷阱**（整请求体 sha 不可用于「同参」判定、live 文件必须共享读）在现场固定成机器检查。

**机器可读总账**：`preflight\run-summary.json`（**88 条判据**，sha256 `5fd1ea7f34bf21fa…`，29 779 B）
+ `finalize-summary.json`（**8 条收尾判据**，sha256 `13ecb0e96311831e…`，2 689 B）。

---

## 1. 方法与证据地图

### 1.1 本批怎么跑（一条命令，全程可复现）

`modules\mcp_server\scripts\mcp066b_run.ps1` 是一个**自包含编排器**：它自己启动/停止它启动的引擎进程、自己拉起观察者、自己在最后写 marker。
`modules\mcp_server\scripts\mcp066b_finalize.ps1` 负责把 scratch 产物收进仓库证据树、做唯一性审计、写 manifest、做收尾纪律断言。

**进程与端口**（本批共 5 个引擎进程，全部串行，全部只停自己 `Start-Process` 的 PID）：

| 会话 | 进程 | 关键 argv（摘要） | 端口 | 用途 |
|---|---|---|---|---|
| A | 窗口化编辑器 | `-e --path proj-cs --mcp-trace=…/trace-editor-a.jsonl --mcp-capture-dir=res://mcp066b_shots --mcp-capture=every_call --mcp-capture-viewport=2d --mcp-capture-scale=2` | 9888 | ⑤、B4、B5、B6、⑥（三路）、快照对、证据守卫 |
| B | 窗口化编辑器 | 同上 + `--mcp-capture-scale=1 --mcp-capture-diff-image=on`，dir `res://mcp066b_shots_b` | 9888 | **B3**（scale1）+ **B2**（diff_image） |
| C | 窗口化编辑器 | 同上 + `--mcp-capture-scale=4`，dir `res://mcp066b_shots_c` | 9888 | **B3**（scale4） |
| D | 窗口化编辑器 | 同上 + `--mcp-capture=on_error`，dir `res://mcp066b_shots_d` | 9888 | **B2**（on_error） |
| G | **窗口化游戏**（**无 `--headless`**） | `--path proj-cs --mcp-port=9889 --mcp-trace=… --mcp-capture=every_call --mcp-capture-dir=res://mcp066b_game_shots --mcp-capture-scale=2` | 9889 | **B7 活链** + 游戏侧 ⑥ + **B1** |

- **编辑器不是 headless**：4 个会话全部有 `[MCP] capture enabled: mode=… viewport=2d dir=… diff_image=… scale=…` 启动行，
  且所有捕获行 `status:"done"`（headless 必然是 `unavailable`）。这就是 ⑥ 与 B1/B2/B3 的前提。
- 游戏进程 `[MCP] role=game` 行存在、**没有** `bind failed`（第 2 轮 D-7 的静默失能签名缺席），`tools/list` = 72。
- **9877 全程无监听者**（运行前/运行后两次 `netstat`，`p0_port_9877_free_before` / `p6_port_9877_still_untouched`）。
- **本批一次 scons 都没跑**（所以「不抑制 scons / 不并发 scons」两条无对象可违反）。

### 1.2 为什么必须**复制**工程再跑

B 是验证者，A 的 `%TEMP%\mcp-breakout-cs\proj` 是**被评对象**：本批先逐字节复制到 `%TEMP%\mcp066b\proj-cs`，
再在副本上跑（`p0_project_copy_is_byte_identical`：**176 个非 `.godot` 文件逐个 sha256 相等**）。
这样 A 的交付物**没有被 B 的测试改动过**，而 B 又确实在同一批字节上跑。复制前后 A 的 10 个声明 sha256 全部 MATCH（§8.1）。

### 1.3 证据树（**358 文件**，绝对路径根 = `…\docs\reports\evidence\task066b\`）

| 目录 / 文件 | 内容 | 文件数 |
|---|---|---|
| `preflight\` | A 的 10 个 fixture hash 复核表、两个 `tools/list`、`run-summary.json`（88 条判据）、`--import` 日志 | 4 |
| `scope\` | ⑤ 的全部 `tools/call`（请求+响应）、`p1_scope_summary`（三套集合 + 集合差 + 每 call 体 sha）、B4、B5、B8 跨进程表 | 54 |
| `capture\` | ⑥ 的调用、`p2_session_b` / `p3_session_c` / `p4_session_d`、`pixel_recompute.json` | 52 |
| `game\` | 游戏侧全部调用（活链、游戏 ⑥、B1 捕获族）、`p5_live_chain`、`p5_b1_windowed_capture_family` | 61 |
| `probes\` | **B6** 的四个负例（请求+响应） | 12 |
| `shots\` | 被三路复核的 6 张图 + 手工入库的 before/after | 6 |
| `captured-shots\` | 5 个会话的**全部 144 张引擎捕获 PNG**（4.88 MB），经 `Write-McpEvidenceBytes` **重命名**为 `<session>__<stem>__<seq>__<sha8>.png` | 144 |
| `traces\` | 5 份 trace jsonl + `PROGRESS.md.txt`（心跳 35 行） | 6 |
| `watch\` | `watch-summary.json.txt`、`watch-summary.txt.txt`、`watch.log.txt`、观察者 stdout/stderr、`p6_watch_summary` | 6 |
| 根 | `evidence-manifest.txt`（356 行）、`finalize-summary.json` | 2 |

**证据卫生**：
- 唯一命名：`Assert-McpEvidenceTreeUniqueness` → **`files=356 collisions=0 duplicate_names=0`**。
  引擎自己的捕获名（`0001_before.png`…）在 5 个会话里必然重名，本批因此**不直接拷贝**，而是经 `mcp_evidence_guard.ps1` 的写入器
  带 session 前缀 + sha8 重新入库——第一次 `Copy-Item` 的版本被审计**当场判红**（40 条同名不同内容），这正是该守卫的用途（§7-H3）。
- `finalize-summary.json` 在 manifest **之后**写出，因此**不在** manifest 的 356 行里（append-only，已在 §9 声明）。

---

## 2. 游戏侧活链（9889，C# 工程）—— **通过（真正构造，实测）**

进程：`godot.windows.editor.x86_64.mono.console.exe --path %TEMP%\mcp066b\proj-cs --mcp-port=9889 …`（**窗口化**）。
**注入输入的工具与读回的工具是不同工具**（判据原话）：

| 角色 | 工具 |
|---|---|
| 注入 | `running_game_run_test_scenario`（`steps[].type=input`） |
| 读回 | `running_game_get_node_property_samples`、`running_game_get_node_properties`、`running_game_find_nodes_by_script`、`running_game_get_scene_tree` |
| 进程内 | `running_game_run_test_scenario` 的 `steps[].type=assert` |

> **测试前置（已留痕，不是伪造）**：发射前用 `running_game_set_node_property` 把
> `Ball.Vel = {0,-260}`（读回 `old_value {90,-260} → new_value {0,-260}`）与 `Ball.position = {300,320}` 固定，
> 让第一次上冲必然穿过 `Brick0(300,160)`。证据：`game\p5_prepare_ball_velocity__0006__5b5ede64.response.json`。

### 2.1 ① 注入输入 → 另一工具读回**逐帧单调变化**

1. `p5_inject_paddle_right`（seq 8）：`steps=[{type:input, action:paddle_right, pressed:true}]` → `injected:1`
2. **另一个工具** `running_game_get_node_property_samples{node_path:"Paddle", properties:["position"], frame_count:24, frame_interval:1}`：
   24 个样本、**24 个不同的 x、严格单调递增**：

   ```
   313.98, 320.96, 327.96, 335.01, 342.05, 348.97, 356.00, 362.98,
   369.97, 376.97, 384.05, 391.01, 398.05, 405.01, 412.03, 419.04,
   426.02, 432.97, 440.01, 446.94, 453.96, 460.97, 468.08, 475.03
   ```

   每帧 **+7.0 px**（`420 px/s ÷ 60 Hz`，正是 `Paddle.cs` 的 `SPEED`）——**这就是「非瞬移」**：
   161 px 的位移分布在 24 个连续帧上。证据 `game\p5_paddle_position_samples__0009__2005daa4.response.json`。
3. `p5_paddle_after`（seq 10）：`position.x 300.0 → 487.98`、`Moves=1325`、`LastDir="right"`（另一个工具读回）。
4. `p5_release_and_assert_moves`（seq 11）：`pressed:false` + **进程内断言** `Paddle.Moves gt 0`
   → `all_passed:true passed:1 failed:0`，`actual:1434`。
5. 球（seq 13）：注入 `launch` 后 **18 帧 18 个不同 y、严格递减**：

   ```
   311.38, 307.04, 302.71, 298.39, 294.03, 289.70, 285.35, 281.03,
   276.71, 272.40, 267.99, 263.67, 259.37, 255.00, 250.71, 246.38,
   242.04, 237.74
   ```

   每帧 **−4.3 px = 260/60**（`Ball.cs` 的 `Speed`）。

### 2.2 ② 砖块**真的消失/减少**

| 时点 | 工具 | 结果 |
|---|---|---|
| 前（seq 2） | `running_game_find_nodes_by_script{script:"res://scripts/Brick.cs"}` | `count=3`（`Brick0,Brick1,Brick2`） |
| 后（seq 15） | 同一工具 | **`count=2`**，`nodes=[Brick1, Brick2]` |
| 前/后（seq 4 / 18） | `running_game_get_scene_tree{max_depth:-1}` | 解析后的树里 `Brick0`：**前 `true` → 后 `false`**；`Brick1/Brick2` 仍在 |

机制在 fixture 里是真实的引擎行为：`Ball._Process` 每帧做 AABB 邻近判定 → `Main.AddScore(10)` → `brick.QueueFree()`；
`QueueFree()` 在帧末真正删除节点，所以**下一次调用**（另一个帧）读回的就是少了一个的集合。

### 2.3 ③ 计分**真的变化**（两路读回 + 进程内断言）

| 时点 | 工具 | 结果 |
|---|---|---|
| 前（seq 3） | `running_game_get_node_properties{node_path:"HUD/ScoreLabel", properties:["text"]}` | `properties.text = "Score: 0"` |
| 后（seq 16） | 同一工具 | **`properties.text = "Score: 10"`** |
| 后（seq 17） | `running_game_get_node_properties{node_path:"Main", properties:[…]}` | `Score=10 BricksHit=1 State="playing" Lives=3 Launched=true` |
| 进程内（seq 14） | `run_test_scenario`：`wait 1.5s` + `assert Main.Score gt 0` | `all_passed:true passed:1`，`actual:10`，`resolved_node_path:"/root/Main"` |

即：**分是节点自己算出来的（`Main.Score`），并且被另一个工具从 UI 文本上读回来了**——两路一致。
**判据 1/2/3 都是「动作前一次调用、动作后一次调用」的两步证据**，且三步对（paddle / bricks / score）
的响应 sha256 **两两不同**（`p5_every_two_step_pair_has_a_different_sha256`：
`paddle e827725c→16d081db`、`bricks 3d66154c→2992e553`、`score 9fad1927→dbab1147`）。

---

## 3. ⑤ `scope` 收窄 —— **通过（实测，非推断）**

### 3.1 构造与分布（编辑器 9888，真实调用）

| 组 | 次数 | 结果（条数 / HTTP 响应字节） |
|---|---|---|
| 默认（省略 `scope`） | 3 | **207** / **44 751 B**（`scope:"all"`） |
| `scope:"user"` | 3 | **1** / **275 B** |
| `scope:"internal"` | 3 | **206** / **44 658 B** |
| `scope:"all"`（显式） | 1 | 207（结果体 sha **等于**默认） |
| `scope:"bogus"`（负例） | 1 | **`-32602`** + 三种口径的枚举解释 |
| `counts` 自查 3 次 | 3 | `counts={all:207,user:1,internal:206}` 每次都自洽 |
| **B5 造出运行期连接之后** | 3+1+1 | `user 1 → 2`；`default 207 → 208`；`internal` 仍 206 |

**逐条判据（`run-summary.json` 里 `p1_scope_*` / `p1_b4_*` / `p1_b5_*` 全部 PASS）**：

| 判据 | 结论 | 证据（可复算） |
|---|---|---|
| **`p1_scope_user_union_internal_equals_default`** | `user ∪ internal = default`：**207**，且 `user − default = 0`、`internal − default = 0` | `scope\p1_scope_summary__0001__34e35296.json`（含 `default_set_minus_user` 逐条、`user_minus_default`、`internal_minus_default`） |
| **`p1_scope_user_intersection_internal_is_empty`** | `user ∩ internal = ∅`：**0** | 同上 `user_internal_intersection` |
| `p1_scope_*_is_three_times_byte_stable` | 同一 scope 的 3 次调用**结果体逐字节相同**（`all` = `f21a9805`、`user` = `b96f6af2`、`internal` = `95487469`） | `scope\p1_scope_*_{1,2,3}*.response.json` |
| `p1_scope_explicit_all_equals_default` | 显式 `scope:"all"` 的结果体 sha == 默认 | `scope\p1_scope_all_explicit__*.response.json` |
| `p1_scope_user_methods_have_no_class_prefix` | user 的 method **全部不含 `::`**（`OnTimerTimeout`） | user 响应 |
| `p1_scope_internal_methods_all_have_class_prefix` | internal 的 **206/206 全部含 `::`** | internal 响应（44 658 B） |
| `p1_scope_counts_are_self_consistent` | 每次调用 `counts.user + counts.internal == counts.all`、`count == connections 条数 == 该 scope 分量` | 三次 `p1_scope_counts_*` |
| `p1_scope_unknown_is_refused_with_32602` | `scope:"bogus"` → `-32602`，message 逐个解释三种口径 | 负例响应 |

### 3.2 集合差与体积

| 口径 | 条数 | HTTP 响应字节 | 相对默认 |
|---|---|---|---|
| 默认（`all`） | 207 | 44 751 | — |
| `scope:"user"` | **1** | **275** | 响应 **−99.4%** |
| `scope:"internal"` | 206 | 44 658 | −0.2% |

**集合差（逐条）**：`default − user` = **206 = internal**；`default − internal` = **正好 1 条**：
`ProbeTimer|timeout|.|OnTimerTimeout`（场景文件第 89 行那条 `[connection]`）；`user ∩ internal` = **0**。

> 这条与 R3 的形态完全同构（R3：47/2/45；本批：207/1/206——C# 工程的场景只多了 1 条持久连接而编辑器内部连线数从 45 涨到 206，
> 因为本轮编辑器多开了几层面板）。**round-2 审计的根因（「内部连线把 user 淹没」）在 C# 工程上同样复现成一个可复算的数字**：
> 一条真正属于用户场景的连接，在 207 条里占 0.48%，响应体只占 0.61%。

### 3.3 `counts` 的口径（复现 R3 O-1，仍建议补进描述）

`counts` 是「**先 `node_path`/`signal_name`，后 `scope`**」的口径——见 §5.4：`node_path:"ProbeTimer"` 时
`counts={all:11,user:1,internal:10}`，而不是全局的 207/1/206。契约描述没有写这一句。

---

## 4. ⑥ 窗口化 `changed:false` —— **通过（真正构造，实测）**

### 4.1 前提（阳性对照）

- 编辑器**没有 `--headless`**，`--mcp-capture-viewport=2d` 指向 `EditorInterface` 的 2D 主界面 SubViewport，
  且 `editor_execute_gdscript{EditorInterface.set_main_screen_editor("2D")}` 已把主界面切到 2D。
- 所有捕获行 `status:"done"`（headless 下必然是 `unavailable`）；`p1_c6_capture_is_windowed_done_not_unavailable` 就是这条的机器判据。

### 4.2 三条构造（同一个编辑器进程、同一棵树）

| | 调用 | 参数 | 工具结论 | 捕获行 |
|---|---|---|---|---|
| 只读重放 | `editor_get_scene_tree` ×2 | 同一对象 | 两次都成功 | **`changed=false` / 0 px**（两条都是） |
| **真实变化** | `editor_set_node_property`（seq 8） | `{"path":"WallTop","property":"position","value":{"x":0,"y":60}}` | 成功 | **`changed=true` / `changed_pixels=2660` / `total=1334144` / ratio `0.00199378777703156`** / `frames_waited=2` |
| **同参同值重放** | `editor_set_node_property`（seq 9） | **逐字节相同的 arguments**（`arguments_sha256=26fa129814200f12…` 两次相同） | **仍然报成功** | **`changed=false` / 0 px / before sha == after sha == `37062f00`** |

**这就是任务书要的「报成功但画面没变 → `changed:false`」与「真实变化 → `changed:true`」。**

### 4.3 三路一致（日志 / 工具 / 独立复算）

| 路 | 手段 | 真实变化对 | 幂等重放对 |
|---|---|---|---|
| ① **日志** | `trace-editor-a.jsonl` 的 capture 行（引擎自己算） | `2660 / 1334144`（ratio `0.00199378777703156`） | `0 / 1334144` |
| ② **工具** | `editor_analyze_screenshot_diff{image_a,b}`（**同一对落盘 PNG**，`res://` 路径） | `changed_pixels=2660 / total=1334144` | `changed_pixels=0`、**`identical=true`** |
| ③ **独立复算** | `scripts\mcp065b_pixel_recompute.py`（PIL 解码 + 复刻模块判据 `max(|dr|,|dg|,|db|) > threshold`，alpha 不参与） | `2660 / 1334144`、`identical=false` | `0 / 1334144`、`identical=true` |

- `pixel_recompute.json` → **`all_three_routes_agree = true`**（4 对：editor 真实/重放 + game 真实/重放，全部 `log_matches_independent=true`）。
- 三路用的是**同一对落盘文件**（sha256 已核）；幂等对两张图**同一 sha**（`37062f00`）——这正是「画面没变」的物理含义。

### 4.4 证据守卫的 before → between → after 快照对

`Write-McpEvidenceSnapshotPair -Leaf p1_main_tscn`：

- **before** = `proj-cs\scenes\main.tscn` 字节 → `p1_main_tscn.before__0001__d33b8931.tscn`（**2890 B**）
- **between** = `editor_set_node_property{WallTop.position → (0,40)}`（seq 4）→ `editor_save_scene{res://scenes/main.tscn}`（seq 5）
- **after** = 同一文件字节 → `p1_main_tscn.after__0001__ec0b9826.tscn`（**2910 B**，与 before **不同**）
- ⇒ 被测调用**真的改了盘上的东西**，且可归因（before 在调用之前取）。第 2 轮 D-9/P4b 的退化对照（两快照同 sha）在本批不会发生。

---

## 5. 前 8 条空白 —— **8/8 全部收口**

> R3 §6.1 列的 8 条，本轮**构造并留证据**如下。每条都给出「怎么构造 / 看到了什么 / 证据」。

### 5.1 B1 游戏端窗口化捕获族 —— **收了**

**构造**：游戏进程**去掉 `--headless`**（这是 R3 明确没做的那一步），`--mcp-capture=every_call --mcp-capture-scale=2`。

| 调用 | 结果 |
|---|---|
| `running_game_capture_screenshot{}` | `width=1152 height=648 format="png"` + **`image_base64` 解出 8107 B 的真 PNG（magic `89 50 4E 47`）** |
| `running_game_capture_screenshot{save_path:"user://b066_shot.png"}` | `saved_path="user://b066_shot.png"`、`1152x648` |
| `running_game_capture_frames{count:3, frame_interval:10, half_resolution:true}` | **3 帧、每帧 `576x324`、engine frames = `592,602,612`（间隔正好 10）**、三帧都是真 PNG |
| `running_game_capture_frames{count:2, half_resolution:false}` | 2 帧 `1152x648` = **半分辨率的 2 倍** |
| 移动可见节点（`WallTop.position → (0,200)`）后再取 1 帧 | 帧 sha **`3aaa17cb…` → `8f0a0546…`**（**捕获真的跟着屏幕走**） |

> **诚实标注（一条形态事实，不是缺陷）**：这三张间隔 10 帧的 PNG **像素完全相同**。原因是本 fixture 的
> `Ball` / `Paddle` 是**纯 `Node2D`、没有任何可见子节点**（场景里只有 3 面 `ColorRect` 墙、3 个砖块 `ColorRect` 与 HUD Label 是可见的），
> 所以「球在动」**不改变任何像素**。本批因此把「捕获反映屏幕」这条主张**换成**「移动一个可见 `ColorRect` 前后取两帧比较」，
> 而不是把「三帧像素必须不同」当成判据——后者在本 fixture 上**不可构造**（§9）。

### 5.2 B2 `on_error` 与 `diff_image` —— **收了**

**`--mcp-capture=on_error`（会话 D，独立进程）**：

| 调用 | 结果 |
|---|---|
| `editor_get_scene_tree`（成功） | **trace 里没有属于它 seq 的捕获行**（`capture=absent`） |
| `editor_set_node_property{path:"NoSuchNode",…}`（**真的失败**：`-32001 Node 'NoSuchNode' not found`） | **有一条捕获行**，`status:"done"` |
| 整个会话 | **捕获行数 = 1 = 失败调用数**（`p4_capture_count_equals_error_count`） |

这正好实测了 `mcp_capture.cpp:487-496` 的语义：「`on_error` 模式下成功的调用**既不产生图也不产生日志行**」。

**`--mcp-capture-diff-image=on`（会话 B，`every_call`）**：真实变化那次的捕获行 `diff` 字段三件套齐备：
`diff.path = res://mcp066b_shots_b/0005_diff.png`、`diff.bytes = 118122`、`diff.sha256 = 481d12b23f450158bdb96706a989ebaae3c4d42167eaeea7cf525ad558f639ef`，
且该文件**真的在盘上**（118 122 B）。

### 5.3 B3 `scale 1/4` —— **收了（并纠正了「正好 4 倍」的错误预期）**

同一条 `WallTop.position` 改动，三种 scale：

| scale | 捕获栅格 | `total_pixels` | 不变式 |
|---|---|---|---|
| 1（会话 B） | **2978 × 1793** | **5 339 554** | `width × height == total_pixels` |
| 2（会话 A） | **1489 × 896** | **1 334 144** | `width == floor(2978/2)`、`height == floor(1793/2)` |
| 4（会话 C） | **744 × 448** | **333 312** | `width == floor(2978/4)`、`height == floor(1793/4)` |

> **本批一开始把判据写成「`scale1_total == 4 × scale2_total`」，实测 FAIL（比例 4.0022）**。
> 根因不是模块：`1793/2 = 896.5`、`1793/4 = 448.25`，`Image::resize()` **逐轴取整**，所以像素总数不可能正好是 4 倍 / 16 倍。
> 修正后的判据是**逐轴 floor**（并在报告里把 2978×1793 这个基准栅格写出来），这才是可复算的不变式。

### 5.4 B4 `scope × node_path` —— **收了**

`editor_list_signal_connections{node_path:"ProbeTimer"}` × `scope ∈ {all,user,internal}`：

| scope | 条数 | `counts` |
|---|---|---|
| `all` | **11** | `{all:11,user:1,internal:10}` |
| `user` | **1** | 同上 |
| `internal` | **10** | 同上 |

- **仍然划分**：`user + internal = 11 = all`（`p1_b4_node_path_set_still_partitions`）。
- **`counts` 是「过 `node_path` 之后」的口径**（不是全局 207/1/206）——复现 R3 O-1，§3.3。
- 一次调用同时给出「三种口径的条数」，调用方**不必**为拿这个划分而多调两次（顺手性合格）。

### 5.5 B5 连接来源区分 —— **收了（并报一条形态缺口 F2）**

**构造**：`editor_execute_gdscript` 在编辑期对**同一个 `ProbeTimer.timeout`** 再连一条**运行期**连接
（`Callable(Ball,"queue_free")`，且不保存场景）：

| 时点 | `scope:"user"` 集合 |
|---|---|
| 之前 | `ProbeTimer|timeout|.|OnTimerTimeout`（**场景文件第 89 行的 `[connection]`**） |
| 之后 | 上面那条 **+** `ProbeTimer|timeout|Ball|queue_free`（**运行期 `connect()` 建的**） |

- **两类连接都进 `user`**（1 → 2）：`p1_b5_runtime_connection_lands_in_user_scope`。
- **运行期那条不在盘上的 `.tscn` 里**：场景文件 2910 B，`mentions queue_free=False`——来源**可以由文件本身区分**。
- **但答案里区分不了**：两条连接的**键集完全相同**（`method,signal,source,target`，`distinct connection key sets = 1`）。
  ⇒ 见 §7-F2：**工具不暴露 provenance 字段**，「场景文件连接」与「运行期连接」在响应里同形。
- 三条 `scope:"user"` 重复调用**结果体逐字节相同**（`sha8=784c9ed1`），**造完连接后划分依然成立**：
  `default 208 == user 2 ∪ internal 206`（`p1_scope_partition_holds_after_the_runtime_connection`）。

### 5.6 B6 diff 工具拒绝路径 —— **收了（四条）**

| 负例 | 请求要点 | 结果 |
|---|---|---|
| 非法 base64 | `image_a:"this-is-not-base64!!"` | **`-32001`**：`The base64 PNG in parameter 'image_a' not found` |
| 尺寸不一致 | `image_a = 64×64`、`image_b = 64×32`（内联 base64） | **`-32602`**：`Image size mismatch: image_a is 64x64 and image_b is 64x32` |
| 超上限 | 两张都是 `4097×1`（`MAX_SCREENSHOT_DIFF_DIMENSION = 4096`，`tools\tool_helpers.h:474`） | **`-32602`**：`Image is 4097x1; this tool diffs at most 4096x4096 pixels (the comparison is per pixel)` |
| `threshold` 越界 | `threshold:999` | **`-32602`**：`Parameter 'threshold' must be between 0 and 255 (it is a per-channel byte difference), got 999` |

探针图由 `scripts\mcp066b_make_pngs.py` 现场生成（64×64 / 64×32 / 4097×1，全部走 base64 传入），
请求与响应原文落在 `probes\p1_b6_*`。**「不存在但格式合法」的路径**（`res://nope.png`）**没有单独构造**——它落在 `-32001` 的同一个分支上，已由非法 base64 那条覆盖该分支。

### 5.7 B7 C# 工程上的同一套活链 —— **收了（本轮主目标）**

即 §2 全部内容。三处与 R3 的 GDScript fixture 的差异（A 在 `next_step_recommendation` 里提醒过）本批全部实测确认：

1. 脚本路径是 `res://scripts/Brick.cs`（不是 `.gd`）；
2. 属性名是 `Score` / `BricksHit` / `Moves` / `LastDir` / `State` / `Lives` / `Launched` / `Vel`（全部 `[Export]`，所以真的在属性表里）；
3. 移动由 `_Process` 驱动（不是 `_physics_process`），且 `Ball.Live=false` 时**不动**——所以「注入 `launch`」是球动起来的必要条件。
4. **`running_game_run_test_scenario` 的 `wait` 步骤**：接受 `seconds`（契约 `inputSchema` 明写），结果回显字段叫 `waited_seconds`（§8.2）。

### 5.8 B8 多进程 scope 稳定性 —— **收了**

四个**互相独立**的编辑器进程（A/B/C/D，串行、各自重启）：

| 会话 | `default` | `user` | `internal` |
|---|---|---|---|
| A（scale2，有快照保存 + 运行期连接前的基线） | 207 | 1 | **206** |
| B（scale1 + diff_image） | 207 | 1 | **206** |
| C（scale4） | 207 | 1 | **206** |
| D（on_error） | 207 | 1 | **206** |

- `p4_b8_scope_counts_are_stable_across_processes` **PASS**：不同进程、不同捕获配置、不同启动顺序下，**三口径完全一致**。
- 与 **A 报告 §2⑤ 的 `all=207 user=1 internal=206` 逐项相同**——这是**跨实现者、跨会话的独立复现**（§8.3）。
- 证据：`scope\p4_b8_scope_across_processes__*.json`。

---

## 6. 观察覆盖与证据纪律

### 6.1 `mcp_watch_run.ps1`：`stop_reason = marker`（且**真的看到了东西**）

`workdir=%TEMP%\mcp066b\watch` 的 `watch-summary.txt`（**绝对路径副本**：
`…\evidence\task066b\watch\watch-summary.txt.txt`，sha256 `2ecfe1b24c0606d2…`）：

```
stop_reason=marker            exit_code=0
elapsed_sec=76                polls=16
last_seq=39                   trace_lines=203
trace_files=6                 activity_seen=1     stale_age_sec=0
observation_stopped_before_development_ended=0
trace=…\PROGRESS.md              lines=35 last_seq=0  missing=0
trace=…\trace-editor-a.jsonl     lines=78 last_seq=39 missing=0
trace=…\trace-editor-b.jsonl     lines=13 last_seq=6  missing=0
trace=…\trace-editor-c.jsonl     lines=11 last_seq=5  missing=0
trace=…\trace-editor-d.jsonl     lines=8  last_seq=6  missing=0
trace=…\trace-game.jsonl         lines=58 last_seq=29 missing=0
```

机器判据（全部 PASS）：`p6_watch_stop_reason_is_marker`、`p6_watch_had_activity`（`activity_seen=True`）、
`p6_watch_saw_the_trace_lines`（`203` 行 / `6` 文件 / `missing=0`）、`p6_watch_stopped_after_the_development_ended`。
观察者是被**运行结束（marker）**停下的（`timeout_sec=2700` / `stale_sec=0` 都未触发），并且它**看到了全部 5 个会话的 trace 与心跳**。

> **本批复用了 R3 F2 的可用启动方式**：`powershell -EncodedCommand <base64(UTF-16LE)>`，
> 命令串里写 `-TracePath '<glob>','<progress>'`（真正的 PowerShell 数组）。共享脚本 `mcp_watch_run.ps1` **一个字节都没改**。
> 本批还额外验证了观察者与 marker 的**失败路径**：编排器第一次异常退出时 `trap` 立即写 marker，
> 观察者以 `stop_reason=marker / elapsed_sec=15 / activity_seen=1` 自行收口——**没有留下任何孤儿进程**（§7-H1）。

### 6.2 `mcp_evidence_guard.ps1` 的两条规则（实测）

- **唯一命名**：356 个证据文件全部走 `Write-McpEvidenceBytes`（`<leaf>__<seq>__<sha8>.<ext>`），
  `Assert-McpEvidenceTreeUniqueness` = **`files=356 collisions=0 duplicate_names=0`**；
  名字里的 sha8 与文件内容 sha256 **由函数自身断言相等**（写后重算）。
- **before → between → after 且断言两 sha 不同**：见 §4.4（`d33b8931` → `ec0b9826`）。

---

## 7. 发现（按影响面排序）

### F1 `[正面确认，不是缺陷]` C# 工程上的活链/⑤/⑥ **没有发现产品缺陷**
- `scope` 的过滤、计数、枚举拒绝、`node_path` 组合、`counts` 自洽性**全部与契约/实现注释一致**；
- 捕获的 `changed` / `changed_pixel_ratio` / `scale` / `viewport` / `diff` 与**独立复算逐位一致**；
- 游戏侧 88 条判据里 **0 条来自错误响应**：活链与捕获族的全部调用都是 `id`+`result`，负例只有 B6 的四条（刻意构造）。

### F2 `[产品/形态]` `editor_list_signal_connections` **不暴露连接的来源（provenance）** · **minor**
- **最小复现**：`editor_execute_gdscript` 在编辑期 `ProbeTimer.timeout.connect(Callable(Ball,"queue_free"))`，
  再调 `editor_list_signal_connections{scope:"user"}`。
- **期望**：调用方能从答案区分「场景文件里持久化的 `[connection]`」与「运行期 `connect()` 建的连接」（两者的持久性完全不同）。
- **实际**：两条连接都在 `user` 里，且**键集完全相同**（`method,signal,source,target`；`distinct key sets = 1`）。
  唯一能区分的地方是**盘上的 `.tscn` 文件**（运行期那条不在里面，实测 `mentions queue_free=False`），
  而工具**没有**任何字段（`persisted` / `from_scene_file` / `origin`）告诉调用方这件事。
- **影响**：调用方若用 `editor_list_signal_connections` 判断「这个连接存进场景了吗」，会**得到错误答案**；
  必须自己去读场景文件（正是本批做的事）。这与 A 报告里 `editor_connect_signal` 诚实回 `already_connected` 的**正面样本**是同一个信息，但没有出现在读回侧。
- **证据**：`scope\p1_b5_user_after_connect_1__*.response.json`、`scope\p1_scope_summary__0001__34e35296.json`、
  以及场景文件字节（2910 B，`queue_free` 出现 0 次）。
- **建议（留给决策者）**：给每个连接条目加一个 `persisted`（或 `origin ∈ {scene_file, runtime}`）字段；这是纯增量字段，不破坏现有调用方。

### F3 `[文档口径]` `counts` 的过滤顺序仍未写进契约（**复现 R3 O-1，本批在 C# 工程上再证一次**）· minor
- 实测：`node_path:"ProbeTimer"` 时 `counts={all:11,user:1,internal:10}`；`signal_name:"timeout"` 时同理（R3 已测）。
- 契约描述只说「counts 给出三种口径各自的条数」，**没有说它是在 `node_path`/`signal_name` 之后**。
- 建议补一句：「`counts` 描述的是**同一请求经 `node_path`/`signal_name` 过滤后、`scope` 过滤前**的集合」。

### F4 `[正面样本]` `--mcp-capture=on_error` 与 `changed` 语义**分开且自洽** · 不建议改
- 成功调用在 `on_error` 模式**既不产生图也不产生日志行**（`mcp_capture.cpp:487-496`），本批实测全会话捕获行数 = 失败数 = 1。
- 另外核实 `changed` **不是**「工具调用成功」的同义词：在游戏进程上移动**不可见**的 `Paddle`（纯 `Node2D`）会得到
  `changed:false`（正确），移动可见的 `WallTop` 得到 `changed:true`（4224/186624）。A 报告 §2⑥ 的 F-7 note 与本批一致。

### H1 `[流程，本批自身]` 编排器的 `trap` 是「观察者不留孤儿」的关键 · informational
- 本批第一次运行在 P1 中途因一个**读文件共享冲突**异常退出，`trap` 立即停掉自己启动的编辑器、写下 marker，
  观察者以 `stop_reason=marker` 自行收口；`netstat` 事后确认 **9888/9889 已释放、无 godot 进程残留**。
- 没有 `trap` 的版本会让观察者空转到 `TimeoutSec`（2700 s），并且留下一个占着 9888 的编辑器。**建议后续任务书把这条写进去**。

### H2 `[证据纪律，本批自身]` 「同参」判定**不能用整个 JSON-RPC 请求体** · informational
- 本批第一版把「两次调用参数逐字节相同」判成 `request_sha256` 相等 → **必然 FAIL**，因为请求体里带 **JSON-RPC `id`**（每次 +1）。
- 这是 **R3 O-1 的同一类错误**（那里是「整个 HTTP 响应」）。修正：`Invoke-Tool` 另外返回 **arguments 自身的 sha256**
  （`arguments_sha256`），三处「同参」判据全部改用它（editor ⑥、game ⑥），并在两处都 PASS。
- **建议**：把「参数对象 → sha256」做成 harness 的标准字段。

### H3 `[证据纪律，本批自身]` 引擎自己的捕获名会跨会话重名，**必须经守卫重命名** · informational
- 引擎写出的文件叫 `0001_before.png`、`0002_after.png`…，5 个会话必然重名；第一版直接 `Copy-Item` 收集，
  `Assert-McpEvidenceTreeUniqueness` **当场抛红**（40 条同名不同内容）。
- 修正：全部经 `Write-McpEvidenceBytes` 以 `<session>__<stem>` 为 leaf 重新入库 → `collisions=0`。
  这**正是** `mcp_evidence_guard.ps1` 设计要抓的东西（D-4 的同类），本批把它当成了自己的自动化闸门。

### H4 `[环境]` 活着的引擎把 trace / stdout 文件**按住不放**，读法必须一致 · informational
- `[IO.File]::ReadAllLines` / `ReadAllText` 对**运行中的** trace 或重定向 stdout 会
  `The process cannot access the file … because it is being used by another process`（本批两次踩到，一次在 trace、一次在 game 的 stdout）。
- 修正：`Read-TextShared`（`FileStream(..., FileShare.ReadWrite)` + 有界重试）统一承载
  `Get-TraceObjects` / `Wait-LogLine` / `First-LineMatching`。共享的 `mcp_watch_run.ps1` 早就是这么做的（它的 `Update-TraceState` 用的是同一种打开方式）。

---

## 8. 对 A 的纠错与确认

### 8.1 **确认（3 条）—— A 的主张经独立复核成立**

| # | A 的主张 | 本批怎么独立复核 | 结果 |
|---|---|---|---|
| 1 | REPORT-066 §1.1 的 **10 个文件 sha256** | 在 A 的 `%TEMP%\mcp-breakout-cs\proj` 上逐个 `Get-FileHash` | **10/10 MATCH**（`preflight\p0_a_reported_hashes__*.json`） |
| 2 | §2⑤ `scope`：**`all=207 user=1 internal=206`** | 在**复制后的工程**上、4 个独立进程里重算集合与 `counts` | **逐项相同**（207/1/206；§5.8） |
| 3 | §4 F-066-5：**只有 `input` 步骤、没有 `assert` 的 `run_test_scenario` 返回 `all_passed:false`** | 本批两次纯 input 注入的响应原文 | **复现**：`{"all_passed":false,"passed":0,"failed":0,"errors":0,"completed_steps":1}` |

### 8.2 **纠错 1（minor，文档）** REPORT-066 §3 表格第 7 行把 **结果回显字段名**写成了**请求成员名**

- **A 的原叙述**（REPORT-066 §3，判据 7 与 §4 引用）：`{"type":"wait","waited_seconds":1.2}`。
- **契约（唯一权威）**：`docs\tools_list.renamed.json` 的 `running_game_run_test_scenario.inputSchema.steps[].properties`
  里该步骤的键集是 `action,expected,keycode,node_path,operator,pressed,property,seconds,strength,text,type`，
  **只有 `seconds`**（`{"description":"等待秒数（wait 类型使用）","type":"number"}`），**没有 `waited_seconds`**。
- **A 自己的请求证据**：`evidence\task066\session3-game\calls\g4_wait_hit_and_assert_score__0016__1d71673a.request.json`
  里写的是 **`{"type":"wait","seconds":1.2}`** —— 即 **A 发对了**，只是**报告抄了回显**。
- **回显字段确实叫 `waited_seconds`**：本批响应 `game\p5_wait_and_assert_score__0014__8afa488e.response.json` 里
  `results[0] = {"step":0,"type":"wait","waited_seconds":1.5}`（本批请求用的是 `seconds`）。
- **纠正**：**输入成员是 `seconds`，结果回显是 `waited_seconds`**。请把 §3 的引文改成请求形态，或显式注明「这是回显字段」。
  （这条**不是模块缺陷**，但它是「同一字段输入/输出不同名」的一个 ergonomics 陷阱：照回显抄的人会得到
  `-32602 "…carries neither 'seconds' nor 'node_path'"`。）

### 8.3 **纠错 2（minor，数字过期）** REPORT-066 §1.2 的 **`.dll` 字节数 19 968 已不是盘上的值**

- **A 的原叙述**（REPORT-066 第 39 行）：「构建产物：`.godot\mono\temp\bin\Debug\McpBreakoutCs.dll`，**19968 B**，`project_build_csharp` exit 0（响应 sha256 `69cb9dd4…`）」。
- **盘上实测**（A 的工程，未改动）：`20992 B`，sha256 **`2e1ff3ddaee79f6826e41919057278ba5a4c3a4c1739365602a2dd6550676320`**。
- **判定**：这个数字描述的是 **session 1 的第一次构建产物**；A 在 session 2 为修 `CsVerdict.cs` 又构建过一次
  （A 报告 §2② 的 f/g 两步），程序集因此变成 20 992 B。**数字与它所引用的响应 sha 是同一时刻的**，所以不是伪造，
  但**它是 stale 值**，读者拿它去核对会失败。
- **建议**：把该行标注为「session 1 首次构建产物」并补最终值（20 992 B / `2e1ff3dd…`），或直接删掉字节数只留响应 sha。

> **没有发现 A 的伪造、夸大或不可复现的主张。** 上面两条都是「引文/时间点的准确性」级别。
> 另外 A §7 deviations 第 4 条明确声明「判据⑥ 的第三方独立复算（像素级）留给 B 角色的 `mcp065b_pixel_recompute.py`」——
> 本批**照办并做成了三路一致**（§4.3），A 的边界划分与 R3 一致。

---

## 9. 仍未构造项（逐条给原因）

> 任务书要求「能构造就构造，不能就**明确声明为什么**」。**8 条空白全部构造出来了**；下面 4 条是**本批没有构造**的其它项，
> 每条都说明性质（是「不可构造」还是「本批范围之外」）。

| # | 未构造项 | 性质 | 为什么 |
|---|---|---|---|
| 1 | **`--mcp-capture=on_error` 与 `--mcp-capture-diff-image=on` 在同一个进程里同时生效**（即「失败的调用也产出一张 diff 图」） | **不可构造（在本 fixture 上）** | `on_error` 只在调用**失败**时捕获；而 `diff` 图要求这次调用的 before/after **像素不同**。本 fixture 上能构造的失败调用（`-32001` 节点不存在、`-32602` 参数面）在失败前**不改任何像素**；唯一会改像素的失败形态（`editor_set_node_property_updates{stop_on_error:false}` 的部分失败）按实现回的是 **`status:"partial"` 这个结果体，不是错误**，因此在 `on_error` 模式下不触发捕获。两个开关**各自**都已构造（§5.2），只是没在同一进程里合并。 |
| 2 | **C# `invalid` / `ok` / `not_compiled` 三类别与编译器原文**（A 的判据②） | **本批范围之外（A 已做，B 未复做）** | TASK-066 §B 的四条判据不含判据②；A 用两个不挂节点的探针（`CsVerdict.cs` / `CsVerdict2.cs`）构造，B 若要复做需要**改被评工程**（把好文件写坏），会破坏 B7 活链所需的可跑状态。**未复核 ⇒ 不主张其成立也不主张其不成立**。 |
| 3 | **`project_list_scripts` 对 `.cs` 失明**（A 的 F-066-1） | **本批范围之外（未独立复核）** | 同上：B 的判据清单不含它。它是 A 报告里唯一被其自己列为 `minor–major` 的产品项，**建议下一轮单独立项复核**（一条调用即可：`project_list_scripts{}` → 期望 `count>0`）。 |
| 4 | **「间隔 10 帧的三张 `capture_frames` PNG 像素必须互不相同」** | **不可构造（在本 fixture 上）** | 该 fixture 的 `Ball` / `Paddle` 是纯 `Node2D`（无可见子节点），所以「球/挡板在动」**不改变任何像素**。本批改用**可构造的等价主张**：移动可见的 `WallTop` 前后各取一帧比较（`3aaa17cb` → `8f0a0546`，§5.1）。 |

---

## 10. 锚点、纪律与偏差

### 10.1 为什么不重建二进制（并对 D86 诚实标注）

```
Command : git diff --stat 7708729982..HEAD -- modules/mcp_server/tools modules/mcp_server/tests
                                              modules/mcp_server/docs/tools_list.renamed.json
                                              modules/mcp_server/docs/tool-rename-map.json
                                              modules/mcp_server/docs/tool-groups.json
Exit    : 0
Output  : []                                    <- 空
Command : git rev-parse HEAD
Output  : a27d7d7ba17d864522ee5fb24a98b60040bc5705
Command : git log -1 --format=%h -- <tools|tests|contract>
Output  : 92a260b682
Command : bin\godot.windows.editor.x86_64.mono.console.exe --version
Output  : 4.8.dev.mono.custom_build.770872998
```

即：**二进制自报的 `770872998` 与 HEAD `a27d7d7ba1` 之间，`tools/**`、`tests/**`、契约、映射、组清单一个字节都没变**
（`scripts/**` 只多了 6 个 TASK-065 B 的 harness 脚本，见 10.2）。因此本轮**不需要重建**即可保证「测的是当前工作树的模块代码」；
代价是必须**如实标注**「HEAD ≠ 二进制自报 sha」（与 R3 §7.1 同口径，且本批**自己复测过**这组 diff，不是引用）。
A 部分的 TASK-066 也没有重建（A 报告 §0 自己复测过同一组 diff）。

### 10.2 未改实现 / 未改契约（逐条打印）

```
git diff --stat 7708729982..HEAD -- tools tests contract map group-lists   -> 空（0 行）
git diff --stat 7708729982..HEAD -- modules/mcp_server/scripts            -> 6 files, +1520 (mcp065b_*，TASK-065 B 的 harness)
git status --porcelain modules/mcp_server/tools tests contract map group-lists -> 0 条（收尾，f6_module_implementation_and_contract_untouched PASS）
contract sha256 = d4e53b43840b6537af9dfbefdc77e7fb4ed6202ee23f3016503a7a53953e7ecd   （前后同 sha）
```

`git status --short`（收尾）：

```
?? .graphifyignore                      <- 既有未跟踪物
?? build-m0.cmd                         <- 既有未跟踪物
?? graphify-out/                        <- 既有未跟踪物
?? install-deps-m0.cmd                  <- 既有未跟踪物
?? modules/mcp_server/docs/reports/evidence/task066b/     <- 本批证据树（358 文件）
?? modules/mcp_server/scripts/mcp066b_env.ps1             <- 本批 harness
?? modules/mcp_server/scripts/mcp066b_finalize.ps1        <- 本批 harness
?? modules/mcp_server/scripts/mcp066b_make_pngs.py        <- 本批 harness
?? modules/mcp_server/scripts/mcp066b_run.ps1             <- 本批 harness
```

**没有任何 ` M ` 行。**

### 10.3 偏差（显式列出）

1. **被测工程是 A 交付物的逐字节副本**（`%TEMP%\mcp066b\proj-cs`），不是原件。理由见 §1.2：B 是验证者，
   不能在测的过程中改动被评对象；副本与原件的 176 个源文件 sha256 全部相同（`p0_project_copy_is_byte_identical`）。
2. **观察者用 `-EncodedCommand` 启动**（而不是 `Start-Process -File`）：见 R3 F2；这是**绕开一个已复现的调用缺陷**，
   不是绕过纪律 —— `mcp_watch_run.ps1` 本身**一个字节都没改**（§10.2）。
3. **本批新建了 4 个 harness 文件**（`mcp066b_env.ps1` / `mcp066b_run.ps1` / `mcp066b_finalize.ps1` / `mcp066b_make_pngs.py`）
   落在 `modules\mcp_server\scripts\`；**共用的三个脚本 `mcp_watch_run.ps1` / `mcp_evidence_guard.ps1` / `mcp_import_guard.ps1`
   一个字节都没改**（`git status --porcelain` 无 ` M ` 行）。这些是**测试产物**（不是实现、不是契约、不是规范文档）。
4. **未跑** `accept_m1.ps1` / 四道门 / 15 步回归电池：本批是**缺口专项**（TASK-066 §B 明写「不得修改模块实现」），
   新增判据是 88 条自校验 + 8 条收尾判据。**门与回归不是本批范围**。
5. **`finalize-summary.json` 不在 `evidence-manifest.txt` 里**：manifest 在它之前写出（append-only 顺序），
   其自身 sha256 记在 `finalize-summary.json` 中（见 §1.3）。
6. **`captured-shots\` 是本批新增的派生目录**（144 张引擎捕获 PNG 的重命名副本）：引擎原始输出的目录名
   （`proj-cs\mcp066b_shots*`）不唯一，必须重命名后入库（§7-H3）。

---

## 11. 复现（照抄可重算本文所有数字）

```cmd
:: 0) 端口前提（9877 必须无监听者；本批从不触碰它）
netstat -ano | findstr ":9877 :9888 :9889"

:: 1) 整套 B 角色运行：复制工程 -> --import -> 观察者 -> 5 个引擎会话 -> ⑤⑥ -> 8 条空白 -> 三路复算 -> marker
cd /d F:\RustProjects\godot-mcp-pro\code\godot
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp066b_run.ps1
:: 期望末行：B066 RESULT checks_passed=88 checks_failed=0
::           B066 WATCH stop_reason=marker activity_seen=True trace_lines=...
:: （重跑前请先清空 %TEMP%\mcp066b 与 evidence\task066b，理由见 mcp_evidence_guard.ps1 的“不得覆盖已引用的证据”规则）

:: 2) 产物回收 + 唯一性审计 + manifest + 收尾纪律
powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp066b_finalize.ps1
:: 期望末行：B066 FINALIZE passed=8 failed=0

:: 3) 第 3 路（独立复算）单独重跑（给定 run 生成的 pixel-pairs.json）
python modules\mcp_server\scripts\mcp065b_pixel_recompute.py %TEMP%\mcp066b\io\pixel-pairs.json %TEMP%\mcp066b\io\pixel_recompute.json
```

---

## 12. 交付物清单（绝对路径前缀 `F:\RustProjects\godot-mcp-pro\code\godot\`）

| 路径 | 说明 |
|---|---|
| `modules\mcp_server\docs\reports\BREAKOUT-FINDINGS-R4.md` | **本报告** |
| `modules\mcp_server\docs\reports\evidence\task066b\preflight\run-summary.json` | **88 条判据** + 观察者 summary + 关键数字（机器可读总账，sha256 `5fd1ea7f34bf21fa…`） |
| `…\evidence\task066b\finalize-summary.json` | 8 条收尾判据（sha256 `13ecb0e96311831e…`） |
| `…\evidence\task066b\evidence-manifest.txt` | 356 行 `sha256 size path`（不含 manifest 自身，sha256 `224984f49eb1947c…`） |
| `…\evidence\task066b\scope\p1_scope_summary__0001__34e35296.json` | ⑤ 的 207/1/206 三套集合、集合差、交集、每 call 体 sha、B4/B5/B8 |
| `…\evidence\task066b\capture\p2_session_b__*.json` / `p3_session_c__*.json` / `p4_session_d__*.json` | B3（scale1/4）、B2（diff_image / on_error） |
| `…\evidence\task066b\game\p5_live_chain__*.json` | 活链全部读回值（24 帧挡板采样、18 帧球采样、砖块 3→2、分数 0→10、两条进程内断言） |
| `…\evidence\task066b\game\p5_b1_windowed_capture_family__*.json` | B1 窗口化捕获族（screenshot / save_path / frames 半+全 / 可见变化对照） |
| `…\evidence\task066b\probes\p1_b6_*` | B6 的四个拒绝路径（请求 + 响应原文） |
| `…\evidence\task066b\{captured-shots(144),shots(6),traces(6),watch(6),process-logs(11)}\` | 全部原始 PNG / 轨迹 / 观察 / 进程日志 |
| `modules\mcp_server\scripts\mcp066b_env.ps1` | B 角色共享 harness（MCP 调用 + arguments sha256、trace 读取、端口/PID 助手） |
| `modules\mcp_server\scripts\mcp066b_run.ps1` | **编排器**（88 条判据，`exit 0` 表示全过；内置 `trap` 保证不留孤儿进程） |
| `modules\mcp_server\scripts\mcp066b_finalize.ps1` | 产物回收 + 唯一性审计 + manifest + 收尾纪律 |
| `modules\mcp_server\scripts\mcp066b_make_pngs.py` | B6 的三张探针图（64×64 / 64×32 / 4097×1） |

**返回给决策者**：见 §0（≤6 行）。

---

## 附录 A（**TASK-068 追加勘误，append-only**）— §8.3 的 `.dll` 字节数：**19 968 已确认陈旧，最终值 20 992**

> **本节是 TASK-068 于 2026-09-25 追加的勘误，不改动本报告任何既有文字。** 前面 §8.3 的正文（含 `19968 B` 与
> `20992 B` 两个数字）逐字保留，原因见本节末尾「为什么不改原文」。

**1. 被勘误的对象（逐字引用，不修改）**

§8.3 正文中的那一句（本报告第 507 行）写的是：构建产物
`.godot\mono\temp\bin\Debug\McpBreakoutCs.dll`，**19968 B**，响应 sha256 `69cb9dd4…`。**这个字节数不是盘上的最终值。**

**2. 追加的实测（TASK-068，2026-09-25，独立重测）**

| 项 | 值 |
|---|---|
| 被测文件（**绝对路径**） | `C:\Users\wyl\AppData\Local\Temp\mcp-breakout-cs\proj\.godot\mono\temp\bin\Debug\McpBreakoutCs.dll` |
| 字节数 | **20992** |
| sha256 | **`2e1ff3ddaee79f6826e41919057278ba5a4c3a4c1739365602a2dd6550676320`** |
| 谁在哪个提交上实测 | **TASK-068 实现工程师**，工作树锚点 `git rev-parse HEAD` = **`eff591a14`**（父层在本批开工时的 revision）；测量发生在 `mono`/`plain` 二进制尚未重建、模块源码**改动前**的时刻 |
| 测量命令 | `(Get-Item <path>).Length` 与 `Get-FileHash -Algorithm SHA256`，由 `modules\mcp_server\scripts\mcp068_live.ps1` 在跑任何 MCP 调用**之前**执行，产物落盘为 `modules\mcp_server\docs\reports\evidence\task068\run-mono-head\mono-head_p0_breakout_dll__0001__*.summary.json` |
| 与 R4 §8.3 的关系 | **逐字相同**：R4 自己的 `20992 B` 与 sha `2e1ff3dd…` 本轮**独立复算成功**（不是引用 R4 的结论）。R4 §8.3 的问题只在**引文里那个 19968**，不在 R4 的实测值。 |

**3. 结论（一句话）**

**`19968 B` 是 session 1 首次构建产物的陈旧值；`20992 B` / `2e1ff3dd…` 才是盘上的最终值**，TASK-068 独立复算确认了后者。
`19968` 既不被新值取代为「唯一真相」，也不被删除——它作为**时间点标注**保留，与它同一时刻的响应 sha `69cb9dd4…` 配对。

**4. 为什么不改原文（append-only 的三条理由）**

1. **§8.3 正文里的 19968 是「A 的原叙述」的逐字引用**（该句开头即写明「A 的原叙述（REPORT-066 第 39 行）」）。
   勘误要能证明「引用是忠实的」；把被引用的数字改掉，读者就无法再核对 `REPORT-066` 里到底写了什么，
   勘误本身也就失去了可验证性。
2. **`REPORT-066` 是已发布的历史报告**（父层已提交）。按 PLAYBOOK §7.3 与 TASK-067 §3 的口径，
   历史报告的更正走**追加勘误**，不回填历史——R4 §8.3 本身就是这样处理 `REPORT-066` 的，
   本附录只是把 R4 自己的同一纪律应用到 R4 上。
3. **两个数字同时在场才有信息量**：`19968`（session 1）→ `20992`（session 2 修 `CsVerdict.cs` 后）正是
   「同一个工程两次构建、程序集变大」这一事实的**唯一可读形式**。删掉任何一个，这条时间线就消失了。

**5. 剩余风险（诚实边界）**

- 本附录**只**核对字节数与 sha256，**不主张**「`20992` 是全部可能值」：任何一次重新 `dotnet build` 都会
  产生新的程序集（`.NET` 的程序集含时间戳/确定性编译开关），所以 `20992` 的正确读法是
  「**在 TASK-068 实测时刻、该工程盘上的值**」，与 §8.3 对 `19968` 的正确读法同构。
- 本附录**不改** `REPORT-066`、**不改** `BREAKOUT-FINDINGS-R4.md` 的 §8.3 正文，也**不改** §12 的交付物清单
  （因此本报告在该清单的意义上已经「发布完成」，本附录是其后追加的一节，不改任何既有行）。

