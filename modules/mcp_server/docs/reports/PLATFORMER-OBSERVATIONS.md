# PLATFORMER-OBSERVATIONS — TASK-074 §B（试测第 5 轮：2D 平台跳跃观察者）

> **角色**：§B 观察者。**只读、与 §A 并行、不阻塞**。**产出**：本文件。
> **任务书**：`modules/mcp_server/docs/tasks/TASK-074-round5-platformer.md`（§0 总则 + §B）。
> **手册**：`modules/mcp_server/docs/tasks/PLAYBOOK-group-port.md`。
> **纪律**：绝不占用/杀/重启 **9877**；只用 9888/9889 且**本会话从未监听**任何一个；**未修改**
> `modules/mcp_server/**` 与 `modules/mono/**` 的实现（只读源码用于归因）；**未改** scratch 工程、
> **未打断** §A 进程；产物一律绝对路径；`.ps1` 纯 ASCII；结论按 D86 标提交锚点。
>
> **⚠️ 提交锚点（D86）**：本文件全部实测结论测自
> **`58becb2f33b043f8c73587c7ed8bc43aee97756d`**（`feature/mcp-server-module`），
> 与 `%TEMP%\mcp-platformer\DEV-DONE.marker` 自报的 `head=58becb2f33` **一致**。
> 观察结束时该提交**未再前进**（`git rev-parse HEAD` 于 2026-09-25 20:54:24 复测仍为 58becb2f33b0…）。
> **本会话未产生任何提交**：`PLATFORMER-DEV-LOG.md`、`evidence/task074/` 与本文件在 20:54 时仍是**未跟踪**文件
> （`git status --porcelain` 只有 4 个既有未跟踪项 + 本任务 3 项）。引用本文件时须连 58becb2f33 一起引。
>
> **四类计数（目标 / 实得）**：
> | 类别 | 目标 | 实得 | 位置 |
> |---|---|---|---|
> | 多次调用才摸清用法 | ≥3 | **6** | §3.1 |
> | 缺失工具线索 | ≥2 | **3** | §3.2 |
> | 可合并候选 | ≥2 | **4**（含 1 条与契约冲突的工具名） | §3.3 |
> | 异常 / 矛盾 | ≥2 | **5** | §3.4 |
>
> **另有一条对 §A 主张的证伪**（§5.2），与一条**分析器本身的缺陷**（§3.4-A5）。

---

## §1 观察协议与机器可读的停止条件（§B 强制报告项）

### 1.1 先跑一次阻塞调用（**没有自行决定收工**）

任务书给定的调用形式有一处**实测不可用**，如实记录（这是**过程摩擦**，不是本模块的缺陷）：

```
# 任务书/PLAYBOOK 的写法（-File 形式，多个 -TracePath）：
powershell -NoProfile -ExecutionPolicy Bypass -File <watch>\mcp_watch_run.ps1 `
  -Marker ... -TracePath <trace1> -TracePath <trace2> ...
# 实测：exit code 1，零日志文件生成，stderr：
#   "Cannot bind parameter because parameter 'TracePath' is specified more than once.
#    To provide multiple values to parameters that can accept multiple values, use the array syntax."
# （.ps1 的 [string[]] 形参在 -File 下**不能**重复出现；这是 PowerShell 的绑定规则，
#   与 mcp_watch_run.ps1 的实现无关。）
```

**实际使用的等价调用**（数组语法、仍由 `powershell.exe` 承载、参数一字不改）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '<repo>\modules\mcp_server\scripts\mcp_watch_run.ps1' `
  -Marker '$env:TEMP\mcp-platformer\DEV-DONE.marker' `
  -TracePath @('$env:TEMP\mcp-platformer\*.jsonl','$env:TEMP\mcp-platformer\*.md') `
  -TimeoutSec 4800 -StaleSec 300 -IntervalSec 30 `
  -OutDir '$env:TEMP\mcp-platformer\watch'"
```

（**偏离声明 D-OBS-1**：任务书写 `-TracePath <各 trace>`，但未给出 `-File` 下的合法数组写法；
本会话改用 `-Command` + `@(...)`，**参数值与含义完全一致**。`.`jsonl` 通配覆盖了 §A 事后才出现
的 4 份游戏追踪，`.md` 覆盖 `PROGRESS.md` 心跳；**未**把 `watch/` 自身纳入监视以避免自激。）

### 1.2 阻塞等待与停止原因（**实测，机器可读**）

| 项 | 值 |
|---|---|
| `stop_reason` | **`marker`**（`%TEMP%\mcp-platformer\DEV-DONE.marker` 出现） |
| `polls` | **29** |
| `last_seq` | **199** |
| `trace_lines` | **505** |
| `trace_files` | **6**（`trace-editor.jsonl`、`trace-game{,2,3,4}.jsonl`、`PROGRESS.md`） |
| `elapsed_sec` | **841** |
| `stale_age_sec` | 0 |
| `activity_seen` | 1 |
| `observation_stopped_before_development_ended` | **0**（即**观察覆盖了开发全过程**，**不是**提前停） |
| watch log | `C:\Users\wyl\AppData\Local\Temp\mcp-platformer\watch\watch.log`（7066 B，sha256 `60af1d6ae003…`） |
| watch summary | `…\watch\watch-summary.txt`（986 B，sha256 `cec2bee2f86b…`）/ `.json`（2852 B，sha256 `a146509f24a1…`） |
| 仓库内副本 | `docs/reports/evidence/task074/observations/watch/`（三个文件逐字节相同） |

**时间线（实测）**：观察者 20:29:26 起轮询 → 20:31:26 首次见到活动（§A 的 9888 编辑器启动+`tools/list`）
→ 20:31:56 双双出现（`trace-editor.jsonl` l=2 / `PROGRESS.md` l=1）→ `stale_ok=0` 直到有活动（stale 永不误判）
→ **20:43:26 `marker=1`**，`stop_reason=marker`。§A 的 `DEV-DONE.marker` 自报 `utc=2026-09-25 20:43:21`，
**观察在开发结束的 5 秒内正常收口**。→ **不存在"观察在开发结束前停止"这一情形。**

`%TEMP%\mcp-platformer` 在观察者开工时**不存在**（`Test-Path` False、无 Godot 进程、9888/9889/9877 全无监听）；
`DEV-DONE.marker` 出现后对 scratch 追踪再算 sha256 **与本会话 20:43 冻结的副本逐字节相同**（§6），
即**分析的输入是完整的、未被后续写入污染的记录**。

---

## §2 环境基线与追踪总览（实测）

### 2.1 基线

| 项 | 值 | 证据 |
|---|---|---|
| HEAD / 分支 | `58becb2f33b043f8c73587c7ed8bc43aee97756d` / `feature/mcp-server-module` | `git rev-parse` |
| 契约 | `docs/tools_list.renamed.json`，**176 条**；`editor_*` 104 / `project_*` 47 / `running_game_*` 23 / `os_*` 2 | `json.load(...)['result']['tools']` → n=176 |
| 引擎 | `4.8.dev.mono.custom_build.ff796dbf9`（`trace_opened` 自报） | `trace-editor.jsonl:1`、4 份游戏追踪第 1 行 |
| **线上 9888（编辑器）** | `tools/list` → **153 条**，`result_bytes=61863` | `trace-editor.jsonl:2`（seq=1, method=tools/list） |
| **线上 9889（游戏）** | `tools/list` → **72 条**，`result_bytes=32973` | 4 份游戏追踪各自的 `tools/list` 行 |
| 9877 守卫 | 观察者不启动任何 Godot；`Get-NetTCPConnection` 在开工时对 9877/9888/9889 **无任何监听**，任务书点名的 PID 36392 **不存在**；§A 的 `ports-final.txt` 记 `pid_after=-1`×3 | 见 §6 `baseline-env.txt` |
| 契约与线上 | 决策者给的「176 条契约；9888=153 / 9889=72」**与实测一致** | 同上两行 |

`153 + 72 = 225`，`225 − 176 = 49`：即**49 条工具在两个进程里各注册一次**，其余按 `channel` 分列——
追随后续轮的读者可用本文件 §2.2 的 `tools/list` 计数作为该不变式的锚点。

### 2.2 追踪解剖（为什么每条 call 有两行）

`trace-editor.jsonl` = **398 行** = 1 × `trace_opened` + **199 个请求** + **198 行 `event:"capture"`**：

| 组成 | 数量 | 说明 |
|---|---|---|
| `tools/list` | 1 | `tools=153`（**1 个连接，非 198 个会话**，见下） |
| `tools/call` | **198** | 与 `DEV-DONE.marker` 自报 `editor9888=198` **逐字一致** |
| 非 ok 调用 | **28** | 错误码分布：`-32001`×12、`-32602`×9、`-32000`×4、`-32601`×3 |
| capture 行 | 198 | `--mcp-capture=every_call`，每 call 一行；**不是工具调用**（分析器同此口径） |
| 游戏侧调用 | **34**（`game`8 + `game2`10 + `game3`9 + `game4`7） | 非 ok 2 条（`game3:2`、`game4:1` 均为 `running_game_get_node_properties` `-32001`） |
| **合计调用** | **232** | 与 §A 自报 `tool_calls=232` **逐字一致**（观察者独立复算：198+34） |

**每次调用一个 `connection`（198 个不同值，最大 200）是 §A 客户端的行为，不是模块行为**：
分析器据此把本代会话判为 "one connection per call"，因此它的 `fail→success` 判据
（同连接、同代、中间无别的调用）在本轮**只可能命中 1 条**（见 §3.1-F1 的说明与 §4）。

---

## §3 四类发现

> 每条都给：`seq`（追踪的关联键，**只在本代内可比**，`trace_opened` 为唯一分代边界）、
> 工具名、参数要点、**错误码**、时间/耗时、响应原文路径 + sha256（凡引用 §A 导出的原始响应，均注明）。
> 追踪行号 = `trace-editor.jsonl` 的 1-based 行号（请求行，非 capture 行）。

### 3.1 多次调用才摸清用法（**目标 ≥3，实得 6**）

**F1 — C# 脚本：先撞 `-32602` 的"专用工具"提示，再撞 `-32001` 的"脚本不存在"**
序列（`seq` → 工具 / 结果）：
`7` `project_write_text_file{path:res://scripts/Player.cs, content:<C# 1446B>, overwrite:true}` → **`-32602`**
"Parameter 'path' names a '.cs' file ('res://scripts/Player.cs'), which has a dedicated tool"
→ `8` `editor_set_node_script{node_path:".", script_path:"res://scripts/Player.cs"}` → **`-32001`**
"Script 'res://scripts/Player.cs' not found"
→ `9` `editor_save_scene{player.tscn}` ok（此时场景里根本没有脚本）
→ **`22`** `project_create_script{path:res://scripts/Player.cs, content:<同一 C# 内容>}` ok（`bytes:1446`）
→ `23` `editor_open_scene{player.tscn}` ok → `24` `editor_set_node_script{同参}` **ok** → `25` save ok。
**学到什么**：`set_node_script` 要求脚本**已存在**（先 create 后 set）；`write_text_file` 对脚本路径
**主动拒绝并指向"专用工具"，但不点名哪个工具**——调用方还得自己找到 `project_create_script`。
两个错误码都是**自纠式**（消息直接说明原因），这是正向能力；摩擦在于**两步顺序不可从描述直接读出**。

**F2 — 存档读回：两个猜测名各 `-32601`，最后只能落在 OS 上**（这是 §3.2-M1 的活证据）
序列：`149` `project_write_text_file{res://save/slot1.json, content:<144B JSON>, overwrite:true}` **ok**
（响应同时给出 `bytes:144, sha256:d39c679f9561…`，sha256 `0f2e46221d80…`）
→ `150` `project_read_file{path:res://save/slot1.json}` → **`-32601`** "Method not found: project_read_file"
→ `151` `project_read_text_file{同参}` → **`-32601`** "Method not found: project_read_text_file"
→ 之后**整个会话再没有任何工具读这份文件**；§A 改用 `Get-FileHash` 在磁盘上独立复算
（`evidence/task074/scripts-run/m6_signals.ps1:138-141`）。
**学到什么**：模块**自己新增**了写文本文件的能力，却**没有**配套的读；两个最自然的名字都不存在。

**F3 — TileMap 写单元格：两个工具、四种错、0 次成功**
| seq | 调用 | 结果 | 原文 |
|---|---|---|---|
| 53 | `editor_set_tilemap_cell{node_path:World/Terrain, x:0,y:0, source_id:0, atlas_x:0, atlas_y:0}` | **`-32602`** | `Unknown parameters atlas_y, atlas_x for tool 'editor_set_tilemap_cell'` |
| 54 | `editor_set_tilemap_cells_in_rect{…, atlas_x, atlas_y, x, y, width:4, height:2}` | **`-32602`** | `Unknown parameters atlas_y, atlas_x, width, y, height, x for tool 'editor_set_tilemap_cells_in_rect'` |
| 91 | `editor_set_tilemap_cell{…, atlas_coords:{x:0,y:0}, source_id:0}`（**改正后的形状**） | **`-32000`** | `TileMapLayer 'World/Terrain' has no TileSet, so it has no source or atlas to name` |
| 99 | `editor_set_tilemap_cells_in_rect{…, rect:{x:0,y:0,width:8,height:2}, atlas_coords:{…}, source_id:0}` | **`-32602`** | `The TileSet of this TileMapLayer has no source 0; it has: no source at all (add a TileSetAtlasSource first)` |
补路径：`88` `project_create_resource{res://world/terrain_tileset.tres, type:TileSet}` ok
→ `89` `editor_set_node_property{World/Terrain, tile_set, value:{}}` **`-32602`**（消息解释 `{}` 不合法，须用 `null`/`res://` 串/`{type,path}`）
→ `90` `editor_add_resource_to_node_property{resource_properties:{tile_size:{x:32.0,y:32.0}}, resource_type:TileSet}` **`-32602`**
→ `97` `editor_set_node_property{World/Terrain, tile_set, value:{path:res://world/terrain_tileset.tres, type:TileSet}}` ok。
**学到什么**：正确的参数形状是 `atlas_coords`/`rect`（**不是**扁平 `atlas_x/atlas_y/width/height`），
且 tile 写入需要 TileSet**上有 atlas source**——而**没有任何工具能加这个 source**（§3.2-M2）。
`-32602` 一次性列出**全部**未知参数名（6 个），这一点是好的。

**F4 — 读 `script` 属性：换 4 个节点试了 4 次，全 `-32001`（设计排除）**
`27` `editor_get_node_properties{path:".", properties:["script"]}`（Enemy）→ **`-32001`**
`29` 同参（Coin）→ **`-32001`**；`126` `{World/Coin1, ["script","value","taken"]}` → **`-32001`**
（**整个请求只回一个错，`value`/`taken` 连试都没试**）；`136` `{World/CoinField/Coin000, ["script","value"]}` → **`-32001`**。
响应 `data.suggestion`（`raw/M6__003_coin000_props/response.json`，sha256 `20f7e60eb8d2…`）明说：
> "…Names starting with '_' and the 'script' property are kept out of the property listing
> (the migration source's rule); ask for the properties you need by their public names instead"

**学到什么**：'script' 被**有意**排除（迁移源规则）；但调用方**无法**用这条工具回答"这个节点挂了哪个脚本"，
而它是"批量挂脚本/连信号"回合里最自然的校验手段 —— 于是 §A 连着 3 次改用别的工具（§3.2-M3、§5.2）。
**注意**：一个**未被接受**的名单会让**同请求里其它合法属性**也一起失败（`126`/`136` 的 `value`/`taken` 从未被回答），
这是"全或无 + 第 i 项定位"之外的一种**耦合**：一个被拒的名字废掉整份请求。

**F5 — 粒子与 HUD：两次独立的"先问后建"顺序错误**
`61` `editor_create_particles{name:"Dust", parent_path:"World", particle_type:"CPUParticles2D"}` → **`-32602`**
（`particle_type must be GPUParticles2D or GPUParticles3D: …which those two classes have. Got 'CPUParticles2D'`
—— 消息解释了**为什么**，自纠式）
→ `62` `editor_set_particle_preset{World/Dust, "snow"}` **`-32001`**、`63` `editor_get_particle_info{World/Dust}` **`-32001`**
（**节点还没建成**，两次都白问）
→ `79` `editor_create_particles{…, particle_type:"GPUParticles2D"}` **ok** → `80` preset ok → `82` info ok。
同型：`72` `editor_set_control_theme{HUD/HudRoot/ScoreLabel, …}` **`-32001`**（HUD 尚未建）
→ `78` `editor_add_nodes_batch{[HudRoot,ScoreLabel,LivesLabel,PauseButton,MenuTitle], resolve_within_batch:true}` ok
→ `85` `editor_set_control_theme{同参}` **ok**。
**学到什么**：`parent_path` 与 `resolve_within_batch` 是本组工具的**关键开关**（一次 batch 内互相引用父节点），
但"节点必须先存在"这条在描述里不是显式的；调用方的自然顺序（先设属性/预置）会先撞两次 `-32001`。
**注意**：`-32001` 的 `suggestion` 是"用 editor_get_scene_tree 列节点"，**没有**提示 `resolve_within_batch`。

**F6 — 批量写属性的名字：猜了第三个近义名，`-32601`**
`93` `editor_set_node_properties_batch{updates:[{path:"HUD/HudRoot/MenuTitle", property:"visible", value:false}]}`
→ **`-32601`** "Method not found: editor_set_node_properties_batch"。
正确名是 `editor_set_node_property_updates{updates:[…]}`（`129`、`183`、`184`、`186`…共 4 次成功），
而契约里**同时**存在 `editor_set_node_property_batch{node_type, property, value}`（另一条按类型批量写）。
**学到什么**：三件东西名字近到可以互相猜（`_property_batch` / `_property_updates` / 猜出来的 `_properties_batch`），
**且响应只回 `-32601`、"Method not found"，不提示最接近的合法名**（§3.3-P2）。

> **关于分析器的 `fail→success` 只报 1 条**：`analyze_mcp_trace.py` 的 episode 判据要求
> **同工具、同 `connection`、同代、中间无别的工具调用**（脚本第 30-35 行注释）。§A 的客户端**每次调用新建连接**
> （198 个 distinct connection），因此只有"紧邻的两次同工具调用"才可能命中：实测只有 **1 条**
> （`142` `editor_connect_signal` `-32001` → `143` 同工具 ok）。上面 F1–F6 的 6 条**都不满足**该判据，
> 它们来自**人工按工具序列+错误码**的复核，不是分析器的输出。**这不是分析器错，是它的保守口径与"一调用一连接"的客户端相互作用的结果**。

### 3.2 缺失工具线索（**目标 ≥2，实得 3**）

**M1 — 没有"读工程文本文件"的工具（写有、读无）**
- 判据① **工具名不存在**：`project_read_file`（seq 150）、`project_read_text_file`（seq 151）各 **`-32601`**。
- 判据② **对照 176 条契约的 `name` 集合**（集合判断，不用文本包含——PLAYBOOK §7.4）：
  含 `read` 的只有 4 条：`project_read_resource`、`project_read_scene_file_content`、`project_read_script`、`project_read_shader`；
  含 `text` 的 3 条里 2 条是游戏侧断言/点击，1 条是 `project_write_text_file`（**只有写**）。
- 判据③ **本次会话没有一次成功读回** `res://save/slot1.json`（对 198 条 call 全量筛查）。
- 影响：§0.6-⑧ 要求的"写回再读回校验 sha"**无法用工具完成**，只能用 OS（§A 如实记为 D3，与本条独立吻合）。
- 可用的**替代品**（契约里存在，但本次未用）：`project_search_file_contents{pattern}`（逐行返回 `{file,line,text}`，上限 250）、
  `project_read_scene_file_content`（仅 `.tscn`）。**建议**：补齐 `project_read_text_file`，或在 `project_write_text_file`
  的返回里带上"如何读回"的指向。

**M2 — 没有"给 TileSet 加 atlas source"的工具（于是 `editor_set_tilemap_cell` 在全新工程上不可用）**
- 判据① 工具自己的错误消息**两次**把调用方指向一个不存在的动作：`-32000` "has no TileSet, so it has no source or atlas to name"、
  `-32602` "it has: no source at all (**add a TileSetAtlasSource first**)"。
- 判据② 契约里含 `tileset` 的工具名 **0 条**；tilemap 组 6 条全是 cell 的读/写/信息/去全部
  （`editor_get_tilemap_cell|info|used_cells`、`editor_set_tilemap_cell|cells_in_rect`、`editor_remove_all_tilemap_cells`）。
- 判据③ 实际路径走不通：`project_create_resource{type:TileSet}` 造出的是**空 TileSet**（`88`）；
  `editor_add_resource_to_node_property{resource_properties:{tile_size:{x:32.0,y:32.0}}}` 被 **`-32602`**（`90`，
  见 §3.4-A6 的消息自相矛盾）；最终 4 次 tile 写入 **0 成功**。
- 影响：§0.6-② 只能判 **partial**（与 §A 自报 "2 partial (capability gap)" 一致）。
- **最小复现**：新工程 → `editor_add_node{type:TileMapLayer}` → `editor_set_tilemap_cell{…}` → 观察 `-32000`；
  再 `project_create_resource{type:TileSet}` + 赋 `tile_set` + 重试 → 观察 `-32602`。

**M3 — 没有"读节点上挂了哪个脚本"的入口，且两个工具口径不一致**
- `editor_get_node_properties` **有意**排除 `script`（§3.1-F4 的 `data.suggestion` 原文，源码 `tools/editor_node_read.cpp:251-256`）。
- 游戏侧同样答不出：`running_game_get_node_properties{Coin002, ["value","taken"]}` 与
  `{Coin002, ["value","taken","monitoring"]}` → **`-32001`**（`Property 'value' on node '/root/…/Coin002' not found`）——
  因为脚本在该节点上**根本没实例化**（§3.4-A2）。
- **但另一条工具却报告了脚本的信号**：`editor_get_node_signals{World/CoinField/Coin000}` 的响应 `count:18`，
  第一个信号就是脚本声明的 `coin_collected{args:[{name:value,type:int}]}`（`raw/M6__004_coin000_signals/response.json`，
  sha256 `f1bc509c1444…`）。→ **"属性读不到 script" 与 "信号表里有脚本声明的信号" 同时为真**，
  调用方无从判断脚本到底生效没有。
- 现有绕行（本次用过/存在）：`project_read_scene_file_content`（seq 193 用上了，20851 B）、
  `editor_get_open_scripts`、`project_list_scripts`。
- **建议**：给 `editor_get_node_properties` 加一个**显式**的 `include_script`（或让 `_batch` 的响应
  真的给出 §3.4-A2 承诺的 `readable` 字段）。

### 3.3 可合并候选（**目标 ≥2，实得 4**；门槛 = 引擎一次调用本可以做到 + 合并后仍全或无 + 第 i 项定位）

**P1 — `editor_set_animation_keyframe` 连发 12 次（10 个连续 bigram、8 个连续 trigram）**
实测：`editor_set_animation_keyframe` ×**12**（占编辑器调用 6.1%），其中
`set_animation_keyframe → set_animation_keyframe` **×10**、三元连续 **×8**；另有 `editor_add_animation_track` ×3。
引擎依据：`Animation::track_insert_key(track_idx, time, key, continuous)` 是**逐帧一次**的调用，
模块当前就在一次调用里对**单个** key 做完整解析/写入；同一批 key 用一次调用循环插入与逐次调用**语义等价**
（引擎侧无跨调用状态）。对照：本批已有 `editor_set_node_property_updates`（一次多写）与
`editor_set_node_script_batch`（一次多挂）的**先例**，动画族缺同等形态。
**建议形态**：`editor_set_animation_keyframes{node_path, animation, keys:[{track_index,time,value,easing}], stop_on_error?}`
→ 逐条回 `{index, track_index, time, landed}`（保持"全或无 + 第 i 项定位"）。

**P2 — `editor_set_node_property_batch` 与 `editor_set_node_property_updates` 是同一件事的两半，且**难猜**
`_property_batch{node_type, property, value}`（按**类型**选节点、写**同一**值）与
`_property_updates{updates:[{path,property,value}], stop_on_error}`（**逐节点**不同值）在选择轴和值轴上互补，
调用方在 `-32601`（seq 93）之后才试出 `_updates`。引擎依据：两者都是"遍历编辑场景的节点 + `Object::set()`"，
选节点的那一步（按类型/按显式路径）可以是一个**可选参数**（例：`updates` 里允许 `node_type` 代替 `path`）。
**建议**：合并为一个工具（`updates` 元素支持 `path` **或** `node_type`），或至少在 `-32601` 的
`data.suggestion` 里回最接近的合法名（现在是裸的 `Method not found`）。

**P3 — "写 → 存 → 重开" 的多步舞（本轮最大的调用占比）**
实测：`editor_save_scene` **17** 次、`editor_open_scene` **21** 次（同一参数 `main.tscn` **11** 次、`player.tscn` 4、`enemy.tscn` 3、`coin.tscn` 3），
bigram：`save_scene → open_scene` **×6**、`set_node_script → save_scene` **×5**、`set_node_property → save_scene` **×4**、
`open_scene → get_node_properties` **×4**、`open_scene → set_node_property` **×4**；
**17/17** 次 `editor_save_scene` 的 `path` 都等于**上一次 `editor_open_scene` 打开的那个场景**
（逐条复核：seq 9/15/21/25/45/74/94/124/133/148/160/169/174/179/185/189/199，17/17 match）。
引擎依据：`EditorNode::save_scene()`（一次落盘当前编辑场景）与 `EditorInterface::open_scene_from_path()`（一次重载）；
`Object::set()` 之后紧跟 `ResourceSaver::save()` 是**一个**引擎事实。
**PLAYBOOK §6.10** 把"要求调用方做多步舞蹈才能拿到引擎一次调用能给的"算缺陷（minor 起）——
本轮的舞蹈是"每次改完必须显式 save（否则下一个进程/下一次 open 读不到），而 save 之后又常要 open 回来"。
**建议**：给写族加可选 `save:true`（写+落盘一次），或提供 `editor_apply_and_save{edits:[…]}`。

**P4 — `editor_add_scene_instance` 连发 6 次（5 个连续 bigram），且 3 次是同一个场景**
实测：`editor_add_scene_instance` ×6（Player 1、Enemy 3、Coin 2），连续出现 5 次。
引擎依据：`PackedScene::instantiate()` + `Node::add_child()` 循环，与 `editor_add_nodes_batch` 的循环同构；
`editor_add_nodes_batch` **已存在**并支持 `resolve_within_batch`。
**建议形态**：`instances:[{scene_path, name?, parent_path?, overrides?}]`（一次多实例化，逐条回 `{index, node_path, name}`）。

### 3.4 异常 / 矛盾（**目标 ≥2，实得 5**）

**A1 — capture 的 `changed` 不能当"这一步生效"的证据（含 1 像素噪声与 3 次 `-32601` 的"变化"）**
实测（198 条 capture 行）：`changed=true` **86** 条，其中
`changed_pixels` **min=1**、p25=7、median=9、max=10115；**≤4 px 12 条（14.0%）**、**≤16 px 73 条（84.9%）**、≤64 px 74 条。
- 纯读调用也 `changed=true` 且只有 **1 px**：`82` `editor_get_particle_info` px=1（sha `1ccc4f5403fa`→`bb0e22a3677a`）；
- `86` `project_get_theme_info` px=5、`87` `editor_get_node_properties` px=4、`88` `project_create_resource` px=2；
- **11 次非 ok 调用也 `changed=true`**，其中 **3 次是 `-32601`**（工具**根本不存在**、没有任何工具代码执行）：
  `93` `editor_set_node_properties_batch` px=4、`150` `project_read_file` px=9、`151` `project_read_text_file` px=9；
  另有 `89` px=3、`90` px=4、`91` px=6、`99` px=12、`126` px=8、`136` px=12、`142` px=6、`198` px=10（全部非 ok）。
→ **结论（实测）**：在 9888 窗口化 + `viewport=2d, scale=2` 下，**1–16 px 的 before/after 差异是编辑器自身的重绘噪声**，
与"被调用的工具"无关；`changed`/`before.sha256 != after.sha256` **单独不能证明任何东西**。
→ **与纪律的关系**：§0.3 要求的守卫脚本 `mcp_evidence_guard.ps1` 比较的是**文件字节**快照（`scripts/mcp_evidence_guard.ps1:795-806`
"snapshot pair has the SAME sha256 … cannot attribute anything"），**不是** viewport capture，所以该脚本**不受本条影响**；
但**用 capture 的 `changed` 去做"写入到屏"的论证会得到假阳**。建议：给 capture 的 `changed` 加**面积阈值/区域**
（例如报告 `changed_pixel_ratio` 的最小可判阈值），或在文档里写明"<0.001% 视为噪声"。
→ 另有 **1 条 `status=unavailable`**（seq 152 `project_build_csharp`，`reason`：跨帧应答 deferred 不覆盖），
其余 5 条 `unavailable` 都在游戏侧（`play_input_recording` / `get_node_property_samples` / `run_test_scenario` / `capture_signal_emissions`）。

**A2 — 契约承诺 `_batch` 会报"脚本是否可读"，响应里**没有**这个字段；而脚本确实没生效（两进程结论相反）**
- 契约（`docs/tools_list.renamed.json`，**逐字权威**）`editor_set_node_script_batch` 描述承诺：
  "…answer per node whether **the attachment landed and the script was readable**"。
- 实测响应（`raw/M6__002_attach_coin_script_batch30/response.json`，sha256 `ef8db75df33a…`；4044 B 文本）：
  顶层键 = `attached, count, errors, keep_existing, script_path, skipped, status`；逐节点键 =
  `attached, index, node_path, previous_script_path, script_path`；`attached` **30/30 true**、`status:"ok"`、`errors:[]`、`skipped:[]`；
  **不含 `readable`/`unreadable`/任何等价字段**（对全文做子串检查：`readable`=False、`unreadable`=False）。
- 现实：磁盘 `main.tscn`（`raw/M12__004_read_main_tscn`，`project_read_scene_file_content` **seq 193** 原文，
  content sha256 `c0e4a67db79a…`）里 Coin000…Coin029 **30 个**都有 `script = ExtResource("6_beafk")`（`script = ` 行共 31 = 30 + 根节点 Main.cs）；
  `running_game_get_scene_tree` 对这 30 个节点**不给 `script` 字段**（`Coin1`/`Coin2`/`Player`/`Enemy1-3` 都给）；
  `game.err.log` 出现 **30 次** `ERROR: Script inherits from native type 'Area2D', so it can't be assigned to an object of type 'Node2D'.`
  （`at: GDScript::instance_create (modules\gdscript\gdscript.cpp:425)`）。
- 归因（**明确区分**）：**根因是 §A 自选的类型不匹配**（`coin.gd extends Area2D` 挂到 `Node2D` 节点），§A 的
  `PLATFORMER-DEV-LOG.md` §D2 已如实记录，**观察者不把根因算成模块缺陷**。**缺陷候选是**"契约承诺的 `readable` 判据未实现"：
  一个**能**检测出这种不匹配的字段被写进了描述却没写进响应，于是工具层面对"脚本挂不上"完全沉默。
  （对照：本模块在别处**很**愿意做这种校验，例如 `editor_add_gridmap` 缺 mesh library 时回 `-32001`：
  `tools/editor_node_instantiate.cpp:143-147` 的注释明说"nothing happened, reported as done"是 PLAYBOOK §6.6 禁止的失败模式。）
- 另附一个**同族口径差异**：`editor_get_node_signals{Coin000}` 仍把脚本声明的 `coin_collected` 列出来（§3.2-M3），
  机制来自模块注释（`tools/editor_node_read.cpp:269-274`：`Object::get_signal_list()` 是 **script signals → ClassDB signals → user signals**），
  **所以"信号表里有"不等于"脚本会实例化"** —— 这两条证据不互相矛盾，但**同一个节点在编辑器与运行期被报告成两种东西**。

**A3 — 实例化子场景内部的节点在编辑器侧不可寻址（矛盾成立，机制未定）**
- `142` `editor_connect_signal{source_path:"World/Player/Anim", signal:"animation_finished", method:"OnAnimationFinished", target_path:"."}`
  → **`-32001`** `Node 'World/Player/Anim' not found`（`data.suggestion`: "Use editor_get_scene_tree to list the nodes of the edited scene"）。
- **编辑器侧看不到它**：**4 份内容互不相同**的 `editor_get_scene_tree` 转储
  （`M2__014`、`M3__030`（与 `M3b__002` 请求/响应逐字相同，内文 sha256 `0817b092a8bc…`）、
  `M3b__020`、顶层 `tree-main.json`（内文 sha256 `767d78bf36bf…`，与前三者都不同）；**参数均为 `{}`**，
  默认 `max_depth=-1`）中，`World/Player` **没有 `children` 键**（即 `get_child_count()==0`），
  4 份里 `Anim` 出现 **0 次**；而同一份转储里 `Sky/Far`、`HUD/HudRoot/ScoreLabel` 等**普通子节点都在**
  （`M3b__020` 共 20 个节点，含 HudRoot），
  所以**不是深度裁剪**：模块的构建函数 `_build_scene_tree` 确实递归 `get_child_count()`
  （`tools/editor_read_scene_inspector.cpp:351-372`）。
- **运行期看得到**：`running_game_get_scene_tree` 4 次转储里都有 `/root/Main/World/Player/Anim`
  （`M8__001`/`M10__003`/`M11__004`，135/134 个节点），且 `Body`/`Art` 也在。
- 场景文件本身是对的：`main.tscn` 里 `[node name="Player" type="CharacterBody2D" parent="World" unique_id=571808819 instance=ExtResource("2_on4l3")]`
  （实例节点不内联子节点，运行期由引擎实例化）。
- **结论**：**编辑器进程内经 `node_path` 无法寻址实例化子场景的子节点**（`World/Player` 本身可以，`World/Player/Anim` 不行），
  因此"玩家动画播完"这类信号**连不上**；**机制未定**：可能是 editor 的 edited-scene 镜像里实例子节点未展开，
  也可能是 `editor_add_scene_instance`（`tools/editor_node_instantiate.cpp:216-223`：`packed->instantiate()` + `add_child` + `set_owner`）
  在编辑器进程里的落点与直觉不同。**观察者无法只从追踪判定**，故记为**矛盾/待复现**，并给最小复现：
  打开一个含外部实例的 `.tscn` → `editor_get_scene_tree`（看实例子节点在不在）→
  `editor_connect_signal{<实例>/<子节点>}`（看能否寻址）→ 与 `running_game_get_scene_tree` 对照。
  §A 的 R19/D4 记为"缺失能力候选"，与本条一致。

**A4 — 错误消息被无条件追加后缀，同一族里一句话读不通（源码 + 线上逐字双证据）**
实测消息：`Property 'script' on node 'Coin000' is not readable by name **not found**`（`raw/M6__003_coin000_props/response.json`，sha256 `20f7e60eb8d2…`），
同族共 **5** 次（seq 27/29/126/136 + seq 102 的另一分支）。
源码：构造处只写 `"Property '%s' on node '%s' is not readable by name"`（`tools/editor_node_read.cpp:252-253`），
而 `MCPToolError::not_found` 会再追加 `" not found"` —— 于是"完整句子 + 后缀"拼出病句；
同一工具的**另一**分支（`editor_node_read.cpp:258-260`）写 `"Property 'playback_speed' on node 'Anim'"` + 后缀 = **通顺**。
→ 纯 cosmetic、不影响判据，但**同一份响应里出现的 5 次**说明它不是偶发；建议把 `not_found` 的后缀改为
"仅在 message 不是完整句时追加"，或让这条分支自己带 "not found"。

**A5 — 分析器脚本的一类信号在本构建下**恒不可能触发**（工具缺陷，不是模块缺陷）**
`scripts/analyze_mcp_trace.py:341-349`：
```python
args = record.get("args")
keys = list(args.keys()) if isinstance(args, dict) else []      # ← 要求 args 是 dict
```
而本构建的追踪把 `args` 写成 **JSON 字符串**（例：`trace-editor.jsonl:105`：
`"args": "{\"atlas_x\":0.0,\"atlas_y\":0.0,...}"`），于是 `keys` 恒为 `[]`，
`missing_tools()["probed_argument_names"]` **结构性恒空**：实测输出 `probed args    none`，
而同一份追踪里明确有 **6 个被拒的参数名**（`atlas_x`/`atlas_y` 各 2 次、`width`/`height`/`x`/`y` 各 1 次、`path`（`project_get_theme_info` 用错名）、
`resource_properties`（对 Vector2i 属性））。→ 该脚本四类信号中的"参数名被反复试探"这一类**本轮 100% 漏报**；
建议 `isinstance(args, str)` 时先 `json.loads`（或让模块同时写结构化 `args_obj`）。

**A6 — 复合响应过大，且内容含**每次运行都变**的编辑器内部路径/id（跨运行不可比）**
- `146` `editor_list_signal_connections{scope:"all"}` → `result_bytes=**315850**`（同工具 `scope:"user"` 只有 643 B）；
  分析器的"异常大响应"阈值是 **1 MiB**，所以它**没有**报（`large responses 0`），
  但 315 KB 的清单里绝大多数是 `internal` 连接（`counts`：`all:1354, internal:1350, user:4`）。
- 响应内容里嵌**编辑器内部节点路径与实例 id**，例如
  `"target": "../../../../../../../../../../../../../../DockVSplitLeftR/DockSlotLeftUR/Scene/@VBoxContainer@5378/@MarginContainer@5441/@SceneTreeEditor@5485"`
  与 `@EditorNode@20573`、`@EditorBottomPanel@8211`（`raw/M6__006_player_signals`、`raw/M6__004_coin000_signals`）。
  这些 id **每次启动编辑器都变**（PLAYBOOK §6.8 要求把这种非确定内容改为确定、可复现的形态）。
- 影响：`editor_get_scene_tree` 的 `absolute_path` 字段同理（`tree-main.json` 里整条 `/root/@EditorNode@20573/.../@SubViewport@9998/Main`）
  ——文件里的 sha256 只能**同一次运行内**比较；§A 的 `MANIFEST-sha256.txt` 因此不能跨运行复核这两类响应。
- `editor_get_scene_tree` 另提供稳定的 `path`（相对编辑场景根）与 `name`/`type`，**这是好的**；
  但 315 KB 的 `scope:"all"` 建议加 `max_connections`/分页，或默认不回 internal。

---

## §4 查过但"没有"的信号（诚实清单 —— **不凑数**）

| 检查项 | 结果 | 查了哪些信号 |
|---|---|---|
| 解析/协议类错误 | **0** | 28 条非 ok 全是 `-32001`/`-32602`/`-32000`/`-32601`；无 `-32700`/`-32603`/`-32604` |
| 超时 / 延迟撞自己的上限 | **0** | 分析器 `timeouts 0 / pending over ceiling 0`；全量筛查 `pending_ms`：只有 seq 152 一条（`pending_ms=4759 < timeout_ms=30000`，且 `ok`） |
| 异常大响应（>1 MiB） | **0 条越过 1 MiB**，但**有 1 条 315 850 B**（§3.4-A6） | 分析器默认阈值 1 MiB + 观察者对全部 198+34 条按 `result_bytes` 排序复核 |
| 单工具占比 >30% | **无** | 最大 `editor_open_scene` 21/198 = **10.6%**（分析器 `dominant tool none`） |
| `seq` 跨代比较 | **未做**（不合规） | 只有 1 个 `trace_opened`（编辑器 pid 92828）；4 份游戏追踪各自 1 个，`seq` 各自从 1 起 —— 本文件**不跨代比 `seq`** |
| "`status:"ok"` 但状态未变"的其他形态 | 见 A1/A2/A3 | 对 86 条 `changed=true`、11 条"非 ok 却 changed"、30/30 `attached:true` 逐条复核 |
| `capture` 与响应 `sha` 的其他矛盾 | **未发现其他形态** | 198 条 capture 的 `before`/`after`/`changed`/`changed_pixel_ratio` 与同 `seq` 的 call 配对检查 |
| 工具名"在线"误判（PLAYBOOK §7.4） | **未用文本包含** | 所有工具在场判断均来自 `tools/list` 的 `name` 集合解析（153/72）与 176 条契约集合比对 |

**§0.6 十一条不是 §B 的交付物**，但观察者对其中 3 条做了**独立复算**（作为对 §A 的交叉核对，见 §5）：
⑧（写回读回）**部分**、⑩（用户信号连接）**通过**、⑪（多帧读回）**通过**。

---

## §5 对 §A 主张的独立核对（**含一条证伪**）

> §B 的职责是"只看服务端记录"，§A 的日志只是**被核对对象**。凡下面标"证伪"的，都以**服务端原文 + §A 自身导出的证据**为准。

**§5.1 一致的项（独立复算后成立）**
- `tool_calls=232`（编辑器 198 + 游戏 34）：观察者从 5 份追踪独立计数，**逐字一致**；非 ok 30 条（28+2）与 §A 自报一致。
- 线上 153/72、契约 176：一致（§2.1）。
- **§0.6-⑧ 的摩擦（D3 缺失工具）**：一致且证据独立（§3.2-M1）。
- **§0.6-⑩（用户信号连接）通过**：`145`/`157` `editor_list_signal_connections{scope:"user"}` →
  `{"connections":[4 条], "count":4, "counts":{"all":1354,"internal":1350,"user":4}}`（`raw/M6__012_conns_user/response.json`，
  sha256 `db88134f0490…`），4 条全部是本次会话建的（两条 `coin_collected→OnCoinCollected`、一条 `pressed→SetPaused`、
  一条 `button_down→OnAnimationFinished`）——`scope:"user"` 的过滤**实测有效**（1350 条 internal 未泄漏）。
- **§0.6-⑪（多帧读回，非瞬移）通过**（观察者独立复算 §A 导出的响应原文）：
  `samples-jump.json` n=30、`frame_count`30/`stride`2、**distinct_y=8**、`y∈[-100.73, -20.02]`；
  `samples-arc.json` n=25、**distinct_y=20**、`y∈[-121.02, -20.00]`；两者 `distinct_x=1`（`x=-87.972` 恒定 → **不是瞬移**）。
  注入工具与读回工具**不同**（`running_game_play_input_recording` → `running_game_get_node_property_samples`，`game.jsonl` seq 4/5、`game2` seq 4/5 与 8/9）。
- **§0.6-② partial**：一致（§3.2-M2：4 次写入 0 成功）。

**§5.2 ⚠️ 证伪：§A 的 `R18`/`D1`（"批量挂脚本不落盘，单节点才落盘"）不成立**
- §A 的原文主张（`PLATFORMER-DEV-LOG.md:96`）："`editor_set_node_script_batch(30)` → 报告 30/30 `attached:true`，
  但**存盘后** `main.tscn` 里这 30 个 `Node2D` **没有** `script = ExtResource`；换单节点 `editor_set_node_script`
  后同一个文件里就有了 …… 记为**真缺陷候选 D1**"。
- **反证（服务端原文，§A 自己导出的）**：`raw/M12__004_read_main_tscn/response.json`
  = **seq 193** 的 `project_read_scene_file_content{res://scenes/main.tscn}` 响应，content sha256 `c0e4a67db79a…`，
  其中 `script = ExtResource("6_beafk")` 出现 **30 次**，且**逐节点**落在 `CoinField` 的 **Coin000…Coin029 全部 30 个**上
  （观察者按 `[node name=…]` 分块解析：`CoinField children=100`，其中**带 script 行 = 30**）。
  `script = ` 行共 **31** = 30 + 根节点 `Main`（Main.cs），与 §A 自己的 `main-tscn-script-count.txt`
  （`script_ext_resource_occurrences=31`）**完全吻合**。
- **时序不可能是"单节点补救"**：30 个节点里，`editor_set_node_script` 单点调用只发生在 **Coin002**（seq 158/188/197），
  `editor_set_node_script_batch` 第二次只覆盖 **Coin003/Coin004**（seq 159）；**Coin000、Coin005…Coin029 没有任何其它写入路径**，
  它们文件里的 `script = ` 行只能来自 **seq 135 的那次 30 节点 batch**（其后 seq 148/160/185/189 任一次 save 落盘）。
  → **该 batch 确实落盘了**；`D1` 的前提（"不落盘"）**被 §A 自己的证据推翻**。
- **最可能的误判来源（推断，标注）**：`editor_get_node_properties{…, ["script"]}` 的 **`-32001`**（§3.1-F4）
  被读成了"没写进去"；另有可能是在**save 之前**读盘（`m6_signals.ps1` 里 batch 在 line 15、`save_main` 在 line 125，
  中间**没有**任何磁盘检查；`raw/M6__017`/`M6__018` 两次"读回"都是 `-32601`）。
- **建议**：按 D86 的 append-only 纪律**勘误** `D1`（撤回"真缺陷候选"），并把它改记成
  "**判据错位**：用被设计排除的属性读工具去验证写入"——这本身就是第 4 轮起反复出现的模式（PLAYBOOK §7.4 同类）。
  §C 汇总者若不认同，请指出我漏掉的写入路径或另一次磁盘读取证据。

---

## §6 证据清单（本会话产物，全部绝对路径）

会话证据根：`F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\evidence\task074\observations\`

| 文件 | 大小 | sha256（前 12） | 内容 |
|---|---|---|---|
| `traces\trace-editor.jsonl` | 247681 | `4c9ec2ac81cb` | 冻结副本；与 scratch 原件的 sha256 **相同**（20:43 与 20:53 两次比对） |
| `traces\trace-game.jsonl` | 9619 | `cf100835f337` | 同上（游戏 1） |
| `traces\trace-game2.jsonl` | 11396 | `94dec94c510d` | 同上（游戏 2） |
| `traces\trace-game3.jsonl` | 10213 | `bd36cf2cb9ec` | 同上（游戏 3） |
| `traces\trace-game4.jsonl` | 8125 | `7696fec73a49` | 同上（游戏 4） |
| `traces\PROGRESS.md` | 2095 | `8f14dea66875` | §A 心跳（34 行里程碑） |
| `traces\DEV-DONE.marker` | 431 | `54c2da0c8434` | `utc=2026-09-25 20:43:21, head=58becb2f33, tool_calls=232, rollbacks=33` |
| `watch\watch.log` | 7066 | `60af1d6ae003` | 29 次轮询 + `DECISION stop_reason=marker` |
| `watch\watch-summary.txt` / `.json` | 986 / 2852 | `cec2bee2f86b` / `a146509f24a1` | 机器可读停止条件 |
| `baseline-env.txt` | 2293 | `1b31e7fd88b0` | 开工基线（端口/进程/契约/命名空间） |
| `digest.txt` | 40579 | `f6da86af800a` | 全量摘要：非 ok 清单、重复调用、capture 统计、per-tool、n-gram、游戏追踪 |
| `episodes.txt` | 55504 | `e423ff1833df` | 8 个关键回合的完整 args + 错误消息 + capture 配对；capture 噪声量化；契约交叉核对 |
| `analyze-trace-editor.{json,txt}` | 19313 / 5452 | `73a81617b3bd` / `048c528ce254` | `analyze_mcp_trace.py` 输出（**含 §3.4-A5 的漏报**） |
| `analyze-trace-game{,-2,-3,-4}.{json,txt}` | — | — | 4 份游戏追踪的分析器输出 |
| `raw-responses.txt` / `raw-responses2.txt` | 32637 / 23645 | `b17b60f87273` / `15a4232c90de` | §A 导出响应原文的**摘录**（每份附 sha256），含 §3.4-A2/A4 的两条关键响应 |
| `checks*.txt` + `check*.py` | — | — | 契约交叉核对、tree 转储对比、batch 响应字段检查、`main.tscn` 逐节点解析（§5.2）、samples 复算（§5.1） |
| `obs_digest.py` / `obs_episodes.py` | — | — | 生成上述摘要的**只读**脚本（纯 ASCII，可重跑复现） |

**分析器与模块脚本（只读引用，未改动）**：`modules\mcp_server\scripts\analyze_mcp_trace.py`（28775 B）、
`scripts\mcp_watch_run.ps1`（15880 B）、`scripts\mcp_evidence_guard.ps1`（44890 B）。

---

## §7 诚实声明、偏差与下一步

### 7.1 声明
- 本文件每条结论前缀 **实测**（有落盘追踪/响应 + sha256，或直接命令输出）或 **推断**（读源码/契约得出，已标注）。
  §3.2 的三条"缺失工具"是**实测（工具名不存在）+ 推断（契约 176 条集合内没有等价能力）**的组合。
- **`seq` 只在本代内可比**：编辑器 1 个 `trace_opened`（pid 92828, port 9888），4 份游戏追踪各自 1 个；本文件**未跨代比 `seq`**。
- **capture 事件不是工具调用**：198 条 capture 行不计入调用数/占比/大响应（与 `analyze_mcp_trace.py` 同口径）。
- **只读**：观察者从未写 scratch 工程（只读其文件）、从未启动/停止/杀死任何 Godot、从未监听 9888/9889/9877、
  **未修改** `modules/mcp_server/**` 与 `modules/mono/**`（仅为归因读取 `tools/*.cpp`、`scripts/*.py|ps1`）。

### 7.2 与任务书的偏离（逐条）
1. **D-OBS-1**：`-TracePath` 的多次重复在 `-File` 下不可用（exit 1），改用 `-Command` + `@(...)` 数组（§1.1）。**参数值一致**。
2. **D-OBS-2**：`-OutDir` 按任务书写在 `%TEMP%\mcp-platformer\watch`（该目录由 watcher 首次创建，
   早于 §A 的工程目录）；观察者**未**向工程目录写入任何文件，只在 `watch\` 下写。
3. **D-OBS-3**：观察者给 `%TEMP%\mcp-platformer\` **加过两个通配符路径**（`*.jsonl`、`*.md`），
   任务书只说"`<各 trace>`"；选择依据是 §A 事后才出现 `trace-game{,2,3,4}.jsonl` 与 `PROGRESS.md`（§2.2 实测目录清单）。
4. **D-OBS-4**：分析器给出的四类信号之外，观察者**人工复核**了 6 条"多次调用才摸清用法"（§3.1 末注：
   分析器的 episode 判据与"一调用一连接"的客户端互斥，只命中 1 条）。**没有**改动分析器脚本。
5. **D-OBS-5**：非 ASCII 的契约描述在 **pwsh 控制台**显示为乱码（cp936 控制台读 UTF-8），
   本会话把契约交叉核对**输出到文件**再读（`checks7.txt`），未影响任何判据。

### 7.3 建议的下一步（按性价比排序，交给汇总者/决策者）
1. **撤回 D1**（§5.2）并把"用被排除的属性读工具验证写入"记为判据模式；否则会开出一批修不存在缺陷的工单。
2. **给 `editor_set_node_script_batch` 补齐契约承诺的 `readable` 字段**（§3.4-A2）：这是能直接抓到
   "脚本类型不匹配 → 静默不生效"的**廉价校验**，且模块在别处已经有同等强度的诚实性要求。
3. **补 `project_read_text_file`**（§3.2-M1）：`project_write_text_file` 是本模块新增的写能力，**有写无读**使 §0.6-⑧ 无法用工具闭环。
4. **修 `analyze_mcp_trace.py` 的 `args` 类型判断**（§3.4-A5，一行 `json.loads`）：它现在**结构性**漏掉一整类信号，
   而这一类（"参数名被反复试探"）正是本轮的 `atlas_x/atlas_y`、`project_get_theme_info{path}` 的证据源。
5. **给 capture 的 `changed` 加可判阈值/面积**（§3.4-A1）：1 px 的抖动 + 3 次 `-32601` 也报 `changed=true`，
   若不写清，后续任何"以 capture 证明写入生效"的论证都会被污染。
6. **最小复现 A3**（§3.4-A3）：实例子节点在编辑器侧不可寻址 —— 这是本轮**唯一**"两进程对同一路径结论相反"的硬矛盾，
   且直接决定"能不能给实例内部节点连信号"这类用法是否可行。
7. 处理 §3.4-A6（315 KB 的 `scope:"all"` 与编辑器内部 id 的非确定性）与 §3.4-A4（消息后缀拼接），二者都是 cosmetic/规模问题。

---

*（本文件由 §B 观察者按 TASK-074 §B 交付；原始追踪与 watch 日志的冻结副本见
`docs/reports/evidence/task074/observations/`，与 scratch 原件 sha256 相同。锚点：`58becb2f33`。）*