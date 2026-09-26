# PLATFORMER-FINDINGS.md — TASK-074 §C 汇总者报告（试测第 5 轮：2D 平台跳跃）

> **角色**：§C 汇总者。**只读分析、只写报告**。**未修改** `modules/mcp_server/**` 与 `modules/mono/**` 的任何实现（符合任务书硬性纪律），
> 也**未修改** §A/§B 的任何产物——对它们的纠错一律写在本文件里（append-only）。
> **锚点（D86）**：分支 `feature/mcp-server-module`，HEAD 见文末 §10；§A/§B 均自报 `58becb2f33`。
> **输入**：`PLATFORMER-DEV-LOG.md`（§A）、`PLATFORMER-OBSERVATIONS.md`（§B）、
> `docs/reports/evidence/task074/**`（含 §A 的 232 个 `raw/**` 与 §B 的 `observations/**` 冻结副本）、
> `%TEMP%\mcp-platformer\**`（scratch 原件，含 **不在仓库里** 的 `logs/game.err.log`）。
> **复算脚本（本报告的全部数字都由它们产出，纯 ASCII、可重跑）**：
> `docs/reports/evidence/task074/aggregate/` 下 `c_recompute.py` / `c_verify.py` / `c_evidence.py` / `c_items.py` /
> `c_items2.py` / `c_calls.py` / `c_calls2.py` / `c_caps.py` / `c_batch30.py` / `c_misc.py`，
> 各配 `*.stdout.txt` 与 `c_*.json`。**§C 未跑任何 Godot 进程**；`9877/9888/9889` 在开工与收工两次复核均为**无监听**。

---

## 0. 结论摘要（先看这 8 行）

| 项 | 值 |
|---|---|
| 四类计数（异常 / 缺失工具 / 可合并 / 可优化） | **8 / 4 / 4 / 6**（§3、§4，每条带证据与强度分级） |
| 疑似缺陷 | **9 条**（D1 已证伪→降级；真缺陷 4 条：D2/D9/D11 与 D3 缺失工具，见 §5） |
| §0.6 十一条 | **8 通过 / 1 部分通过（能力边界） / 2 偷换（通过但目标物不是原文要求的那一个）** —— §6 逐条给证据与 sha256 |
| 对 §A 的纠错 | **2 处**（D1「批量挂脚本不落盘」**证伪**；「游戏侧非 ok 只有 2 条」**与全量证据冲突**，实为 14 条） |
| 对 §B 的纠错 | **2 处**（游戏侧非 ok 数被追踪口径**低估 12 条**；「§A 说 5 条用户连接」的时序未做对账） |
| 最该先做的 2 条 | **① 补 `editor_set_node_script(_batch)` 的类型兼容性判定 + 契约承诺的 `readable` 字段（真缺陷，静默）**；**② 补 `project_read_text_file`（有写无读，使 §0.6⑧ 无法用工具闭环）** |
| 最不该做的 2 条 | 见 §7「不建议做」——**不要**为 D1（已被证伪）开工单；**不要**先动 `scope:"all"` 的 315 KB 与编辑器内部 id（规模/cosmetic，收益低于风险） |
| stop_reason | **`task-complete`** —— §A 有 `DEV-DONE.marker`（`stop_reason=marker` 由 §B 的 watcher 独立确认）、§B 有完整四类计数与机器可读停止条件、**§C 的全部数字已由本代理从追踪与响应原文独立复算**；无阻塞项 |

---

## 1. 复算基线与对账（§C 自己的数，不是抄 §A/§B 的）

### 1.1 追踪与调用（全部实测）

| 项 | §C 实测 | 与 §A/§B 的关系 |
|---|---|---|
| `trace-editor.jsonl` | **398 行** = 1 `trace_opened` + **199 请求行** + **198 `capture`** | 行数 398 与 §A 附录 B 一致；**§B 说「199 个请求」正确** |
| 编辑器请求构成 | **1 `tools/list`（tools=153，result_bytes=61863，第 2 行/seq 1）+ 198 `tools/call`** | 与 §B §2.2 逐字一致 |
| 游戏侧请求 | `game` 9（其中 1 条 `tools/list` → tools=72，result_bytes=32973）/`game2` 10 /`game3` 9 /`game4` 7 = **35 请求行**，其中 **34 `tools/call`** | 与 §A `tools/game=34`、§B §2.2 表逐字一致 |
| **请求行总计** | **234**（= 199 + 35） | **§A 的「工具调用 232」= 198 编辑器 `tools/call` + 34 游戏 `tools/call`**，**口径是 `tools/call` 而非「请求」**；若把 2 条 `tools/list` 也算请求则是 **234**。§B 的 `232` 与 §A **口径一致，不是独立复算**（§B 自己也把 199 与 232 混排） |
| `CALLS.jsonl` | **232 行**（= 198 + 34），`port` 分布 `{9888:198, 9889:34}` | **逐字一致** |
| `CALLS.jsonl` 结果分布 | `ok` **202**、`-32000` **4**、`-32602` **9**、`-32001` **14**、`-32601` **3** → **非 ok 30** | 与 §A 自报 202/30 **逐字一致** |
| `raw/**` 响应 | **232 个目录**，其中**含 `error` 键的 = 30**（§C 逐目录解析） | 30 与 §A/§B 的「非 ok 30」一致 |
| 编辑器侧非 ok | **28**（`-32001`×12、`-32602`×9、`-32000`×4、`-32601`×3） | 与 §A、§B **三方一致** |
| **游戏侧非 ok** | **14**（全部 `running_game_get_node_properties` / `-32001`） | ⚠️ **§A 与 §B 都只说 2** —— **见 §2.2 纠错** |
| capture | **198 条**，`done` 197 / `unavailable` 1（seq 152 `project_build_csharp`） | 与 §A/§B 一致 |
| capture `changed=true` | **86**，`changed_pixels` min=1 / p25=7 / median=9 / p75=12 / max=10115，≤4 px **12（14.0%）**、≤16 px **73（84.9%）**、≤64 px 74 | **与 §B A1 逐字一致（独立复算）** |
| 「非 ok 却报 changed」 | **11 条**：seq 89(3) / 90(4) / 91(6) / 93(4) / 99(12) / 126(8) / 136(12) / 142(6) / 150(9) / 151(9) / 198(10) | 与 §B A1 列出的 11 条**逐字一致** |
| `-32601` 却报 changed | **3 条**（seq 93 px=4、150 px=9、151 px=9） | 与 §B A1 **逐字一致** |
| `args` 的 Python 类型 | `str` **198** / `dict` **0** | **证实 §B A5**：分析器 `isinstance(args, dict)` 恒 False |
| `tools/list` 条数 | 编辑器 **153**、游戏 **72**，并集 **176 = 契约条数** | 与决策者给的口径一致 |
| `CALLS.jsonl` 编码 | **带 UTF-8 BOM**（`EF BB BF`），`PROGRESS.md` 同 | **合法性问题**见 §4-OP6 |
| 追踪与 scratch 原件 | 5 份追踪 sha256 **逐字节相同** | §B §6 已声明，§C 复核成立 |

### 1.2 契约（§C 独立核对）

`docs/tools_list.renamed.json`：**176 条**（`editor_*` 104 / `project_*` 47 / `running_game_*` 23 / `os_*` 2），
`sha256` 与字节数见 `aggregate/c_verify.json → contract`。含 `read` 的工具仅 4 条
（`project_read_resource` / `project_read_scene_file_content` / `project_read_script` / `project_read_shader`），
含 `text` 的 3 条里 **只有 `project_write_text_file` 是工程文本文件**（其余两条是游戏侧 `assert_screen_text` / `click` 类）
—— **§B M1 的集合判据成立**（§C 用集合解析复核，未用文本包含）。

---

## 2. 对 §A / §B 主张的独立核对（**含 4 处纠错**）

### 2.1 ✅ 一致且经 §C 独立复算的项

| 主张 | 提出者 | §C 复算 | 证据 |
|---|---|---|---|
| `editor_add_nodes_batch` 一次建 **100** 节点，`count:100`、16,355 B、sha `6b2d0af4270801e8` | §A | **成立** | `raw/M5__004_batch100_coins/response.json`（sha `6b2d0af4270801e8…`，16355 B） |
| 一次写 **12** 个不同值，`updated:12 failed:0`、sha `15367848d42f547d` | §A | **成立**，且回读 `Coin000=(1000,-500)`、`Coin001=(1017,-501)` **逐字等于** `M5__006/007` 回读 | `M5__005` / `M5__006`（`884be94f9a70`）/ `M5__007`（`162077b60aa5`） |
| `project_analyze_scene_complexity` → `total_nodes:121`，`Node2D:103`、`TileMapLayer:1`、`GPUParticles2D:1`、`ParallaxBackground/Layer:1` | §A | **成立** | `M5__008`（sha `d24d6199f512`） |
| 存档工具回执 `bytes:144, sha256:d39c679f9561…`；磁盘独立复算**逐字相等** | §A | **成立**（§C 重算 scratch `proj/save/slot1.json` = 144 B / `d39c679f9561495281083c8cf8ead887bb09bd9b57a80f81f8adbb5fd2661c40`） | `M6__016`（sha `0f2e46221d80`）；`%TEMP%\mcp-platformer\save-sha.txt` |
| `project_read_file` / `project_read_text_file` **两条 `-32601`** | §A / §B | **成立** | `M6__017`（`cfae59846961`）/ `M6__018`（`225ca14d2764`） |
| C# 真构建 `exit 0`（4,748 ms）；`project_validate_script{Main.cs}` → `valid:true` | §A | **成立** | `M7__001`（`5748d8172f55`）/ `M7__003`（`157ff7502c40`） |
| 动画：`editor_create_animation` ×2（run 0.6s / jump 0.5s）、`add_animation_track` ×3、`set_animation_keyframe` **×12 全部 ok** | §A | **成立**，逐帧参数已复核（run=8 帧:track0 五帧 + track1 三帧；jump=4 帧:track0；**8 个不同 time**） | `trace-editor.jsonl` 的 seq 103–118；`M4__028`（`fa77310b0b89`） |
| 用户信号连接：`scope:"user"` 过滤有效 | §A / §B | **成立**，且**时序已对账**（见 2.3） | `M6__012`（`db88134f0490`，count **4**）/ `M7__006`（`9515cb1e1a2b`，count **5**） |
| 运行期多帧弧线：`samples_jump` n=30/stride 2/distinct_y=8；`samples_arc` n=25/distinct_y=20；`distinct_x=1`（x 恒定 → 非瞬移） | §A / §B | **成立** | `M10__005`（`212a02ec516c`，2525 B）/ `M10__009`（`5736dde0180b`，3258 B）；注入为另一工具 `M10__004`（`610e9877e383`，`injected:6`） |
| 「`status:ok` 但状态未变」的现场：Score 恒 0、HUD 恒 `SCORE 0`、`capture_signal_emissions count:0` | §A | **成立** | `M11__008`（`b95e0ba0a09b`，10 帧 `Score:0/Lives:3`）、`M13__011`（`passed:false`，`SCORE 0`）、`M11__010`（`3792393b9a75`，`count:0`） |
| `editor_get_node_properties{["script"]}` → `-32001`「…is not readable by name **not found**」（后缀病句） | §A / §B A4 | **成立**，§C 逐条定位 **5 次**（seq 27/29/126/136 + seq 102 分支） | `M6__003` / `M1b__006`（同为 `20f7e60eb8d2` 家族） |
| 「一个被拒的名字废掉整份请求」 | §B F4 | **成立** | `M3__…` / `M6__003` 全或无语义；`M5__002` 同型 |
| `editor_set_tilemap_cell` 四种错、**0 次成功** | §A / §B | **成立** | `M3__008`（`-32602` 未知参数 `atlas_y, atlas_x`）、`M3b__016`（`-32000` no TileSet）、`M4__004`（`-32602` no source 0）、`M3__009`（`-32602` 六个未知参数） |
| `project_create_resource{type:TileSet}` 产出空 TileSet（无 source/无 texture） | §A D5 | **成立**（`properties_set: []`；info 里 `has_tile_set:false, source_count:0`） | `M3b__013`（`ebd248efa327`）/ `M3b__017`（`e5f74ed9bfa1`） |
| 捕获 `unavailable` 是**跨帧 deferred**，不是 headless | §A R25 | **成立**：编辑器 1 条 `unavailable` = seq 152 `project_build_csharp` | `trace-editor.jsonl` 第 152 号 capture 行 |
| 分析器 A5：`probed args none` 恒空 | §B | **成立**（§C 自己跑 `scripts/analyze_mcp_trace.py` 得同样输出；`args` 198/198 是 `str`） | `aggregate/c_analyze_editor.txt` |
| 分析器 friction：`fail→success` 只 1 条（`editor_connect_signal` seq 142→143） | §B | **成立**（§C 复跑逐字一致） | 同上 |
| 015 KB 的 `scope:"all"`、`counts {all:1354/1355, internal:1350, user:4/5}` | §B A6 / §A | **成立**：`M6__013` = **315,850 B**；`M7__006` 的 all=1355/internal=1350/user=5 | `M6__013`（sha `677a475dbed2`）；`%TEMP%\…\conns_all.response.json` = 294,096 B（**另一口径**，见 §4-OP4） |

### 2.2 ⚠️ 纠错 1（**对 §A 与 §B 都纠**）：游戏侧非 ok 的实际条数是 **14**，不是 2

- **§A 原文**（`PLATFORMER-DEV-LOG.md:105`）：逐工具非 ok 列表里 `running_game_get_node_properties` **2**，
  `CALLS.jsonl` 非 ok 合计 30。
- **§B 原文**（`PLATFORMER-OBSERVATIONS.md:115`）：游戏侧「非 ok 2 条（`game3:2`、`game4:1`）」。
- **§C 复算（`CALLS.jsonl` 按 `port` 分组，脚本 `c_calls2.py`）**：
  - `9888`：198 调用 / **非 ok 28**（`-32000`4、`-32602`9、`-32001`12、`-32601`3）
  - `9889`：34 调用 / **非 ok 14**（**全部** `running_game_get_node_properties` / `-32001`）
  - 合计 **30**，与 `raw/**` 里「含 `error` 键的响应」**恰好 30 个**（§C 逐目录解析）**互相印证**。
- **根因（实测 + 推断）**：**14 条游戏侧非 ok 里只有 2 条落在追踪文件里**（`trace-game3.jsonl` seq 2、`trace-game4.jsonl` seq 1）；
  其余 12 条发生在**没有留下追踪的游戏会话**里（`game2` 之后 / 强杀重启之间，R24 的强杀会截断 trace 尾部）。
  §B 的 30 = 28（编辑器，正确）+ **2（仅追踪可见的游戏条数，低估 12）**，**凑巧等于真值 30** ——
  这是两个相反的口径误差相互抵消，**不是一致**。
- **影响**：§B §1.2/§2.2 的「非 ok 30 条（28+2）与 §A 自报一致」**结论正确但推理错误**；
  §A 逐工具表的 `running_game_get_node_properties 2` **是错的**（真值 14），
  而 §A 的**总数 30 是对的**（因为它的 `raw/**` 记全了 30 条）。
- **§C 的判据**：以 `CALLS.jsonl` + `raw/**`（232 条逐调用落盘）为**权威**；追踪文件是**有界截断的快照**，
  不能用作「某类错误只有几条」的完备依据。**§B 自己在 §7.1 声明「追踪是有界截断」，
  却在 §1.1 用追踪的去重计数反驳 §A 的总数** —— 这是 §B 内部的一处口径不自洽。
- **证据**：`aggregate/c_calls2.stdout.txt`（按端口分组）、`aggregate/c_evidence.json → raw_index_n=232`；
  两条游戏非 ok 原文 `raw/M11__005_coin002_props`（sha `7311979b0199`，731 B）、
  `raw/M13__006_coin002_props`（sha `27f5b3f3a7d9`，302 B）—— **后一条在追踪里存在**（`game4` seq 1），
  **前一条不在任何追踪里**（`M11` 属被强杀的那次会话）。

### 2.3 ⚠️ 纠错 2（**对 §B 纠**）：§0.6⑩ 的「4 条 vs 5 条」是**时序**，不是矛盾；§B 引错了出处

- **§A 说**（行 44/165）：`scope:"user"` = `{"count":5,…}`，sha `9515cb1e1a2b…`（表头写「5 条用户连接」）。
- **§B 说**（行 413–416）：`scope:"user"` → 4 条，sha `db88134f0490…`，并据此把 ⑩ 判为「通过」。
- **§C 复算**：
  - `raw/M6__012_conns_user/response.json`（643 B，sha `db88134f0490…`）= **4 条**，
    `counts {all:1354, internal:1350, user:4}`，缺 `Coin002.coin_collected`；
  - `raw/M7__006_conns_user_after/response.json`（761 B，sha `9515cb1e1a2b…`）= **5 条**，`counts {all:1355…, user:5}`，**含 Coin002**；
  - `CALLS.jsonl` 里 `editor_connect_signal` 共 **7 次**：成功 **5**（seq 140/141/143/144/**156**）、失败 **2**（seq 142 `Anim` 不可寻址、seq 198 `body_entered` 类型不符）。
    **seq 156 是一次 `save_scene` 之后的补连**，因此 5 条落在 `M7`（`conns_user_after`），4 条落在 `M6`（`conns_user`）。
- **结论**：**§A 的 5 条正确、§B 的 4 条也正确，二者是同一会话内两个时点的快照**。
  §B 引 `9515cb1e1a2b` 却配 `M6` 的物理文件，是把两次调用混成一次（§B §5.1 引用的 `raw/M6__012…` 内容确为 4 条，
  与它写的 sha `db88134f0490` 一致 —— **错的只是它没解释 §A 的 5 条，且未标注该快照早于 Coin002 补连**）。
- **M6/M7 双快照（关键，勿混）**：`raw/M6__012_conns_user/response.json` = **envelope 643 B / sha `db88134f0490`**，
  其 **`body.json` = 489 B / sha `d478b9e310f5`**（= `%TEMP%\…\conns_user.response.json`，§C 逐字节验证）；
  `raw/M7__006_conns_user_after/response.json` = **envelope 761 B / sha `9515cb1e1a2b`**。
  §A 在正文引 `9515cb1e1a2b`（**5 条**，正确），但在 §2⑩ 的证据栏把物理路径写成 `M6__012`（**4 条**的 body 版），
  **两个尺寸/条数被并排写在同一个格子里** —— 这就是 COR-7 与 E4 的现场。
- **§C 对 ⑩ 的判定**：**通过**（5 条用户连接、`scope:"user"` 只列这 5 条、1350 条 internal 未泄漏）。

### 2.4 ⚠️ 纠错 3（**对 §A 纠，认可 §B 的证伪**）：D1「批量挂脚本不落盘」**被证伪**，§B 是对的

- **§A D1 原文**（行 96/114）：`editor_set_node_script_batch(30)` 报 30/30 `attached:true`，
  但**存盘后** `main.tscn` 里这 30 个 `Node2D` **没有** `script = ExtResource`。
- **§C 独立复算（三路证据，全部指向「落盘了」）**：
  1. **scratch 磁盘现状**：`%TEMP%\mcp-platformer\proj\scenes\main.tscn`
     （**17,211 B，sha `f82264933b5472b51917d336c2545d3a60db8e1eb7ee08e7c0d9f4d82f1b128b`**）里
     `script = ExtResource` 共 **31** 行 = `1_r3l7o`×1（根 `Main.cs`）+ `6_beafk`×**30**，
     逐块解析出 `Coin000…Coin029` **恰好 30 个** Coin 节点带 `script`（共 102 个 Coin 块）。
     §A 自己的 `main-tscn-script-count.txt` 也写 `script_ext_resource_occurrences=31` —— **自证**。
  2. **写入路径唯一性（时序排除法）**：30 个节点里，单点 `editor_set_node_script` 只发生过 3 次且**全在 Coin002**
     （seq 158/188/197），batch 第二次只覆盖 Coin003/004（seq 159）；
     `Coin000`/`Coin005…Coin029` **没有任何其它写入路径** → 它们的 `script =` 只能来自 **seq 135 的 30 节点 batch**。
     `editor_save_scene(res://scenes/main.tscn)` 共 9 次（§C 从 CALLS.jsonl 复算），其后任一次落盘即可持久化。
  3. **§B 的交叉证据**：`raw/M12__004_read_main_tscn`（`project_read_scene_file_content`，seq 193）与磁盘同源。
- **最可能的误判来源（§C 推断，与 §B 一致但换成更精确的版本）**：
  §A 用 `editor_get_node_properties{properties:["script"]}` 的 `-32001` 当作「没写进去」的判据，
  而该属性**按设计被排除**（`raw/M6__003` 的 `data.suggestion` 原文）→ **判据错位**；
  另有一次读盘检查发生在 `save_scene` **之前**（脚本 `m6_signals.ps1` 里 batch 在第 15 行、`save_main` 在第 125 行）。
- **处置**：**D1 降级为「已证伪（非缺陷）」**，不建工单。保留 §A 的原始表述（append-only），纠错写在此处。
  **§B 的 §5.2 成立，§C 采纳。**
- **但 §A 的观察里有一条真金**：`editor_set_node_script_batch` **确实没有**判「脚本是否在节点上可读」
  —— 这正是 §B A2 与 §C 的 **D2**（真缺陷），**不该跟着 D1 一起被丢掉**。

### 2.5 ⚠️ 纠错 4（**对 §A/§B 都纠**）：「同参同响应 sha」不稳定这条，比 §A 写的更严重

- **§A D6**：11 次**逐字相同**的 `editor_open_scene{main.tscn}` 得到 **5 个不同 sha256**。
  **§C 复算：成立**（`872938705dad3d3b`×7、另 4 个各 1 次；§A 的计数与分布**逐字正确**）。
- **§C 加一条 §A 没查的**：**连写工具也是**。`editor_save_scene{main.tscn}` 9 次 → **7 个不同 sha**；
  `editor_get_scene_tree{}` 4 次 → **4 个不同 sha**（4066/6225/**6226**/8961 B）。
- **影响**：任何「用响应 sha256 当稳定指纹」的对账（含 §A 自己的 `MANIFEST-sha256.txt`、`FINAL-FINGERPRINTS.txt`）
  **只能同一次运行内比较**，且**写入类**响应也在内。PLAYBOOK §6.4 只对 `tools/list` 声明了确定性，**这一条应被补进不变量**。
- **§A 把「一次会话内同参 7 次同 sha」当成正常**（`872938705dad` 命中 7 次）—— 那 7 次里前 5 次 `changed:false`（编辑器无变化），
  属可解释；**但写后重开的 5 个 sha 不可解释为「纯噪声」**，因为其中包含结构差异（`result_bytes` 126 vs 127）。

---

## 3. 四张表

> **排序规则**：每条给 **证据强度**（A=有原文 sha256 的直读证据；B=有原文但需一次推理；C=仅部分/间接）
> × **影响面**（高/中/低）。表内按 **证据强度 × 影响面** 降序。**不建议做的条目单列在 §7**。

### 3.1 表一 · 异常 / 矛盾（8 条）

| # | 异常 | 强度 | 影响面 | 证据（sha256 / 行号） | 备注 |
|---|---|---|---|---|---|
| E1 | **实例子场景的子节点在编辑器侧不可寻址**：`World/Player` 可解析、`World/Player/Anim` → `-32001`；同族属性写工具却**能**落到 `Anim`（`autoplay` 写成功）。**两进程对同一路径结论相反** | **A** | **高**（「给实例内部节点连信号」这类最常见需求无法用工具表达） | `-32001`：`raw/M6__009_conn3_anim_finished`（sha `36815bbcfbff`）；对照 `raw/M4__028_anim_autoplay`（sha `fa77310b0b89`，`new_value:"run"` 成功）；**编辑器侧 4 份 `editor_get_scene_tree` 转储里 `World/Player` 的 `children` 数为 0、`Anim` 出现 0 次**：`M2__014`（`6d8dd4add673`，9 节点）、`M3b__002`（`e2082709cea8`，14 节点）、`M3b__020`（`563bd9d0ba77`，20 节点）；**运行期** `game-scene-tree.json`（sha `46d496376814a73e`）与 `game-scene-tree2.json`（`bda3bbaebc65136d`）里 `/World/Player/{Body,Art,Anim}` **齐全**；`player.tscn`（sha `836de74af433c84c6bcccce63c859ab9acf384ebd9104e051f18a73fc9ca14d7`）确有 `Anim`/AnimationPlayer 节点 | §B A3 的「机制未定」**可以收窄为实测事实**：`editor_add_scene_instance` 建出的实例在编辑器镜像里**不展开**，所以不是「路径解析 bug」而是「镜像不含实例子节点」。**§C 建议改判为真缺陷**（同族口径不一致），见 D4 |
| E2 | **`capture.changed` 不能当"这一步生效"的证据**：1 px 抖动、纯读调用、甚至 **3 次 `-32601`（工具根本不存在）** 都报 `changed=true` | **A** | 中（污染任何「写入到屏」的论证；**不影响** `mcp_evidence_guard.ps1`，它比的是文件字节） | 86 条 `changed` 的像素分布（§C 复算，见 §1.1）；11 条「非 ok 却 changed」、3 条 `-32601` 的 seq 与 px 值见 §1.1；§B A1 原文一致 | 建议给 capture 加面积/比例阈值或文档写明「<0.001% 视为噪声」 |
| E3 | **契约承诺 `editor_set_node_script_batch` 会报「脚本是否可读」，响应里没有该字段** | **A** | **高**（工具层对「脚本挂不上」完全沉默） | 契约 `docs/tools_list.renamed.json` 明文 "…whether the attachment landed **and the script was readable**"；响应 `raw/M6__002_attach_coin_script_batch30`（**4615 B，sha `ef8db75df33ab89b`**）顶层键 `attached/count/errors/keep_existing/script_path/skipped/status`，逐节点键 `attached/index/node_path/previous_script_path/script_path`，**全文无 `readable` 子串**（§C 实测 `False`），`attached` ×30 全 `true`、`errors:[]`、`skipped:[]` | **这是「D1 证伪」与「D2 成立」的交点**：不落盘是假的，**不校验才是真的**。见 D2 |
| E4 | **同一份响应在证据里以「裸 body / envelope」两种尺寸共存，导致按字节数或文件 sha 对账会得出错误结论** | **B** | 中（**已实际发生过一次误读**——§C 第一遍就把 `attach_coin_batch30` 的 4044 vs 4615 读成"副本漂移"） | `raw/M6__012_conns_user/` 目录内 **`response.json`=643 B / sha `db88134f0490`**，**`body.json`=489 B / sha `d478b9e310f5`**（§C 实测：`result.content[0].text` 的 body **恰好 = 489 B / `d478b9e310f5`**，即 `%TEMP%\…\conns_user.response.json` 是同一 body 的副本）；同理 `attach_coin_batch30.response.json`（4044 B 裸 body）vs `raw/M6__002/response.json`（4615 B envelope，其 `body.json` = 4044 B）。**§C 已验证两者 body 逐字节相同**（`c_batch30.py`：`body equal: True`） | **结论修正**：**不是数据丢失、也不是副本漂移**，是「同一份体+壳两种尺寸」+「一行报告混引两个尺寸」。**真正的风险**是引用者混用：`%TEMP%` 的 `conns_user.response.json` 是 **body 形态**（489 B / 4 条），而 `raw/M7__006/response.json` 是 **envelope 形态**（761 B / 5 条）——**尺寸差一半，条数还不同**，极易误判。**建议**：文档里统一写明「裸文件名（如 `conns_user.response.json`）= body，`raw/<M>__<tag>/response.json` = envelope，同目录 `body.json` = 该次调用的 body」 |
| E5 | **错误消息被无条件追加后缀，同族一句话读不通**：`Property 'script' on node 'Coin000' is not readable by name **not found**` | **A** | 低（cosmetic） | 5 处（seq 27/29/126/136 + seq 102 分支）；§A/§B 都记了；对照同工具另一分支拼接通顺（§B A4） | 与陈旧规范/口径无关，但**同一份响应里出现 5 次**说明不是偶发 |
| E6 | **`editor_add_resource_to_node_property` 的消息自相矛盾**：把 `Vector2i` 属性写成「Dictionary → Vector2i … can_convert 不列」，而同一工具在别处把 `Vector2` 拒为「Unknown resource type: Vector2」 | **B** | 低-中（会把调用方引向错误方向） | `raw/M3b__015_attach_tileset`（sha `2a40678bedd0`，875 B，`resource_properties` 被拒）、`raw/M3__021_parallax_mirror`（`-32602` Unknown resource type: Vector2）；§A R9/R14、§B F3 都撞过 | 建议消息里直接给**合法值形状**（`{x,y}`），而不是解释 `can_convert` |
| E7 | **编辑器输出日志里有一条与动画相关的引擎错误，但被截断、无节点路径**：`ERROR: scene\animation\animation_mixer.cpp:272 - Method/function failed. Returning: Ref<AnimationLibrary>()` | **B** | 低（本轮无实际后果，但属"静默"家族） | `editor-output-log.txt`（1957 B，`count:17` 行，逐行原文已复算；`Area2D` 出现 **0** 次） | **§A 把「编辑器无任何相关告警」写进了 D2**（行 115）—— **这句话不完整**：编辑器日志里确有 1 条动画族错误，只是**没有指明节点**。§C 在此更正 |
| E8 | **`editor_set_node_property` 赋 `tile_set` 之后 `has_tile_set` 仍为 `false`**（被拒的是中间那次 `{}`，但最终态也没变） | **B** | 中（会把 D5 的归因从「TileSet 是空的」升级为「赋值本身可能没落地」） | `M3b__014_set_tileset_dict`（`-32602`，sha `4456ef8f4ef7`）、`M3b__015_attach_tileset`（`-32602`，sha `2a40678bedd0`）、`M4__003→M3b__016`（`-32000` no TileSet）、`M3b__017_tilemap_info_final`（sha `e5f74ed9bfa1`，**`has_tile_set:false, source_count:0`**） | ⚠️ **§A/§B 都把 `assign_tileset` 记为 ok 并据此给 D5**；§C 看到的是**失败路径**下的 `has_tile_set:false`。**需要一次最小复现来定分**（见 D5），**不建议**在没复现前改判 D5 |

### 3.2 表二 · 缺失工具 / 缺失能力（4 条）

| # | 缺什么 | 强度 | 影响面 | 证据 | 建议 |
|---|---|---|---|---|---|
| M1 | **没有「读工程文本文件」的工具（写有读无）** | **A** | **高**（§0.6⑧ 要求的「写回→读回→校验 sha」**无法用工具闭环**，每次只能落 OS） | `project_read_file`（`M6__017`，`cfae59846961`，`-32601`）、`project_read_text_file`（`M6__018`，`225ca14d2764`，`-32601`）；契约 176 条集合核对（§1.2）；对照能力 `project_write_text_file` 是本模块**新增**的写 | **补 `project_read_text_file`**，或在 `project_write_text_file` 回执里带读回指引。**最该先做的第 2 条** |
| M2 | **没有「给 TileSet 加 atlas source / texture」的工具，于是 `editor_set_tilemap_cell(s)` 在全新工程上不可达** | **A** | 中-高（§0.6② 只能 partial；工具自己的指引链**缺最后一环**） | 两次**被拒的消息本身指向不存在的动作**：`M3b__016`（`-32000` "has no TileSet, so it has no source or atlas to name"）、`M4__004`（`-32602` "**add a TileSetAtlasSource first**"）；契约里含 `tileset` 的工具名 **0 条**（§C 集合核对），tilemap 组 6 条全是 cell 的读写/信息/清空 | 补 `project_create_resource` 对 `TileSet` 的 source/atlas 参数面，或单开一个工具；**不要**只改错误消息 |
| M3 | **没有「读节点上挂了哪个脚本」的入口，且两个工具口径不一致** | **A** | 中-高（「批量挂脚本/连信号」回合里最自然的校验手段） | `editor_get_node_properties{script}` 按设计排除（`data.suggestion` 原文，`M6__003`/`M1b__006`）；**但** `editor_get_node_signals{Coin000}` 把脚本声明的 `coin_collected` 列出来（`M6__004`，sha `f1bc509c1444`）→ 「属性读不到 script」与「信号表里有脚本信号」**同时为真**；运行期同样答不出（`M13__006`，`27f5b3f3a7d9`，`-32001`） | 给 `editor_get_node_properties` 加显式 `include_script`，或让 `_batch` 真的回 `readable`（与 E3/D2 同一条修） |
| M4 | **实例化子场景内部节点的寻址能力缺失**（与 E1 同一现场，此处按「能力」列） | **A** | 高 | 同 E1 | 与 E1/D4 合并处理 |

### 3.3 表三 · 可合并候选（4 条，门槛 = 引擎一次调用本可做到 + 合并后仍全或无 + 第 i 项定位）

| # | 候选 | 强度 | 影响面 | 数据（§C 从 `CALLS.jsonl`/`CALLS` bigram 复算） | 引擎依据 |
|---|---|---|---|---|---|
| P1 | `editor_set_animation_keyframe` **×12** 连发（同工具 bigram ×10、trigram ×8） | **A** | 中（6.1% 的编辑器调用） | §C 复算：12 次 keyframe **全部 ok**，分属 run 8 / jump 4；`add_animation_track` ×3；**已有先例**：`editor_set_node_property_updates`（一次多写）与 `editor_set_node_script_batch`（一次多挂） | `Animation::track_insert_key(idx, time, key, continuous)` 是逐帧一次；引擎侧**无跨调用状态** → 一次调用循环插入与逐次调用语义等价 |
| P2 | `editor_set_node_property_batch{node_type,property,value}` 与 `editor_set_node_property_updates{updates:[{path,property,value}]}` 是**同一件事的两半**，且**难猜** | **A** | 中（一次 `-32601` 才试对；三件近义名互猜） | §C 复算：`editor_set_node_property_updates` 成功 **4 次**（共 12 条更新，§A 记载一致）；`_property_batch` **1** 次 → `-32601`（`M3b__018`）；分析器 `missing tool clues` **只回 `Method not found`，不提示最近合法名** | 两者都是「遍历编辑场景节点 + `Object::set()`」；选节点那一步（按类型/按显式路径）可做**可选参数** |
| P3 | 「写 → 存 → 重开」的多步舞 | **A** | 中（本轮最大的调用占比） | §C 复算：`editor_save_scene` **17** 次（**17/17 ok**）、`editor_open_scene` **21** 次（main 11 / player 4 / enemy 3 / coin 3）；bigram `save→open` ×6、`set_node_script→save` ×5、`set_node_property→save` ×4；`editor_set_node_property` **17** 次 | `EditorNode::save_scene()` 与 `Object::set()` 之后 `ResourceSaver::save()` 是**一个**引擎事实；PLAYBOOK §6.10 把多步舞算 minor 起缺陷 |
| P4 | `editor_add_scene_instance` **×6** 连发（同工具 bigram ×5、trigram ×4），其中 3 次同一场景（enemy） | **A** | 中低 | §C 复算：6 次（Player 1 / Enemy 3 / Coin 2）；`editor_add_nodes_batch` 已存在且支持 `resolve_within_batch` | `PackedScene::instantiate()` + `add_child()` 循环，与 `add_nodes_batch` 同构 |

### 3.4 表四 · 可优化（6 条，均为「不新增能力，只降摩擦/降噪声」）

| # | 优化项 | 强度 | 影响面 | 证据 | 建议 |
|---|---|---|---|---|---|
| OP1 | `-32601` 从**不提示最接近的合法名** | **A** | 中 | 分析器 `missing tool clues` 三条全是裸 `Method not found`（`editor_set_node_properties_batch` seq 93、`project_read_file` seq 150、`project_read_text_file` seq 151）；且 `_property_batch`/`_property_updates`/`_properties_batch` 三名可互猜 | 加 `data.suggestion` 做**编辑距离**匹配 |
| OP2 | **`analyze_mcp_trace.py:341-349` 的 `args` 类型判断结构性漏报一整类信号**（本构建把 `args` 写成 JSON **字符串**） | **A** | 中（工具缺陷，不是模块缺陷；「参数名被反复试探」这一类 **100% 漏报**） | §C 复跑分析器：`probed args none`；同时 `args` 的 Python 类型 **str 198 / dict 0**；被拒参数名 6 个（`atlas_x`/`atlas_y`/`width`/`height`/`x`/`y`） | 一行 `json.loads`（或模块同时写结构化 `args_obj`） |
| OP3 | 编辑器内部路径/id 进入响应，**每次启动都变**，使跨运行指纹不可比 | **A** | 中低 | `editor_get_scene_tree` 的 `absolute_path` 含 `/root/@EditorNode@20573/...`；`editor_list_signal_connections` 含 `@DockSlotLeftUR/@SceneTreeEditor@5485` 等（`M6__004`/`M6__006`）；§C 另测：`editor_get_scene_tree{}` 4 次 → **4 个不同 sha**、字节 4066/6225/**6226**/8961 | PLAYBOOK §6.8 要求把非确定内容改为确定形态；**稳定的 `path`（相对编辑场景根）已有，应在文档里明确「指纹只认 `path`」** |
| OP4 | **证据落盘格式不统一**（`response.json`=envelope 与 `body.json`=body 并存；**同名**文件在不同目录可能是不同时点的快照） | **B** | 中（对账成本；**本轮 §C 自己踩过一次**——见 §5-D7） | E4 的两形态（§C 已验证 body 逐字节对应）；另：`%TEMP%\…\ports-final.txt`（30 B，运行中快照 `9888=92828/9889=55484`，20:39:06）与仓库 `ports-final.txt`（72 B，收工快照 `pid_after=-1`×3，20:43:55）**同名不同内容**（§C 逐字节比较 `False`） | 在 MANIFEST 里为每份文件标注 `body|envelope` 与**采集时点**；或在脚本里统一只导出 body |
| OP5 | **`editor_list_signal_connections{scope:"all"}` 返回 315,850 B，其中 1350 条 internal**；分析器 1 MiB 阈值**抓不到** | **A** | 低-中（规模） | `raw/M6__013`（**315,850 B**，sha `677a475dbed2`）；`counts {all:1354…, internal:1350, user:4}`；`%TEMP%\…\conns_all.response.json` 294,096 B | 加 `max_connections`/分页，或**默认不回 internal** |
| OP6 | **`.ps1` 纯 ASCII 纪律被破（一处）**；证据文本文件带 UTF-8 BOM | **B** | 低（但**纪律面**影响：naive JSON 解析直接抛错） | `scripts-run/m14_export.ps1` 用它把 `editor-output-log.txt` 写成**带 BOM 的 UTF-8**（`c_calls.py` 读该文件爆 `UnicodeEncodeError: 'gbk' codec`；内容里含 U+2009 THIN SPACE）；`CALLS.jsonl` 与 `PROGRESS.md` **带 BOM**（`EF BB BF`，§C 实测）→ `json.loads(open(...,'utf-8'))` 抛 `Unexpected UTF-8 BOM`；**§C 的四个脚本都不得不改用 `utf-8-sig`** | 证据文件统一 **UTF-8 无 BOM**；`.jsonl` 尤其不应带 BOM（它不是合法的 JSON Lines） |

---

## 4. 疑似缺陷清单（最小复现 + 期望/实际 + sha256 + 严重度）

> 严重度：**S1** 静默错误/数据不可信；**S2** 能力缺失致工作流不可闭环；**S3** 摩擦/cosmetic。
> 全部 **只记录，未改实现**。

### D2 — `editor_set_node_script(_batch/_batch)` 对**类型不兼容**的脚本回 `attached:true`，引擎静默丢弃 —— **S1（真缺陷）**

- **最小复现**（本轮已实际发生，见 §A R21 / §B A2）：
  1. 打开一个含 `Node2D` 节点 `World/CoinField/Coin002` 的场景；
  2. `editor_set_node_script_batch{nodes:[Coin000…Coin029], script_path:"res://scripts/coin.gd"}`（`coin.gd` 为 `extends Area2D`）
     → 响应 `status:"ok"`、`attached` **30/30 `true`**、`errors:[]`；
  3. `editor_save_scene` → 磁盘 `main.tscn` 里 30 个节点**确实**带 `script = ExtResource("6_beafk")`；
  4. 启动游戏 → **`running_game_get_node_properties{Coin002, ["value","taken"]}` → `-32001`**（脚本属性一概不存在）。
- **期望**：工具（或至少该 batch 的响应）**应当**告知「该脚本的 `extends` 与节点根类型不兼容，绑定不会生效」——
  契约**自己写了**要回 "whether … the script was readable"（E3）。
- **实际**：`attached:true` 且**全文无 `readable`**；引擎侧只在**游戏进程**日志里打 30 行错误
  （`ERROR: Script inherits from native type 'Area2D', so it can't be assigned to an object of type 'Node2D'.` ×**30**），
  **编辑器进程日志里 0 次**（§C 实测：`%TEMP%\mcp-platformer\logs\game.err.log` 5793 B 里 `Area2D`=30；
  `editor.err.log`/`editor-output-log.txt` 里 `Area2D`=**0**）。
- **严重度**：**S1**。属 GDR-24「静默写错值」家族**第 5 种形态（脚本槽位的兼容性）**。
- **sha256**：响应 `ef8db75df33ab89b1ada7fa1a0a21c1d257a2d8dc3886e83b49dec750b41478a`（4615 B，`raw/M6__002`）；
  运行期反证 `27f5b3f3a7d90a0c…`（`raw/M13__006`，302 B）；日志证据**仅存在于 scratch**：
  `%TEMP%\mcp-platformer\logs\game.err.log`（5793 B；**该文件没有进仓库证据目录**，见 §9 缺口 G1）。
- **归因边界（采纳 §B）**：**根因是 §A 自选的设计取舍**（`Node2D` 硬币 + `Area2D` 脚本），**不是模块的"做错了"**；
  **缺陷在于模块对「挂不上」保持沉默**。

### D9 — 游戏侧错误总数被两处报告同时低估（14 → 记为 2）—— **S1（报告级真缺陷，会造成错误回归判据）**

- **最小复现**：`CALLS.jsonl` 按 `port=9889` 过滤 → 34 条 / 非 ok **14**（全 `-32001`）；
  同一事实在追踪里只剩 **2** 条。
- **期望**：§B 作为「只看服务端记录」的独立角色，**应当**用 `CALLS.jsonl` + `raw/**`（232 条逐调用落盘）对账，
  或明确声明「追踪是截断快照，我给出的条数是**下界**」；§A 的逐工具表**不该**写 2。
- **实际**：§B §1.1/§2.2 写「非 ok 30（28+2）与 §A 自报一致」；§A 逐工具表写 `running_game_get_node_properties 2`。
- **严重度**：**S1**（若下一轮把「游戏侧非 ok 数」当回归基线，会**系统性漏掉 12 类失败**）。
- **证据**：`aggregate/c_calls2.stdout.txt`、`aggregate/c_evidence.json → raw_index_n=232`、
  `raw/M11__005_coin002_props`（sha `7311979b0199`，**不在任何追踪里**）。

### D3 — 契约 176 条里没有「读工程文本文件」—— `project_write_text_file` 有写无读 —— **S2（真缺失）**

- **最小复现**：`project_write_text_file{res://save/slot1.json}` ok（回 `bytes:144, sha256:d39c679f9561…`）→
  `project_read_file` → `-32601`；`project_read_text_file` → `-32601`。
- **期望**：写回再读回校验（§0.6⑧ 原文）应当能**用工具**完成。
- **实际**：只能落 OS（§A 用 `Get-FileHash`；§C 复算 = `d39c679f9561495281083c8cf8ead887bb09bd9b57a80f81f8adbb5fd2661c40`，**与工具回执逐字相等**）。
- **严重度**：**S2**。**证据**：`raw/M6__016`（`0f2e46221d80…`）、`M6__017`（`cfae59846961…`）、`M6__018`（`225ca14d2764…`）。

### D4 — 实例子场景内部节点在编辑器侧不可寻址（同族口径不一致）—— **S2（真缺失能力）**

- **最小复现**：`editor_open_scene{main.tscn}`（含 `World/Player` 实例）→
  `editor_get_scene_tree{}`：`World/Player` 的 `children` 数为 **0**、全文 **无 `Anim`**；
  `editor_set_node_property{node_path:"Anim", property:"autoplay"}` **成功**；
  `editor_connect_signal{source_path:"World/Player/Anim", …}` → `-32001`；
  同一场景在**运行期** `running_game_get_scene_tree` 里 `/root/Main/World/Player/{Body,Art,Anim}` **齐全**。
- **期望**：同族 `editor_*` 工具的 `node_path` 解析口径**一致**（要么都能到实例子节点，要么都不能，且消息说明）。
- **实际**：属性写工具到得了、信号工具到不了；且 `editor_get_scene_tree`（本该是「列节点」的权威）也**看不到**它们，
  于是 `data.suggestion`（"Use editor_get_scene_tree to list the nodes of the edited scene"）**指向一个也看不见它的工具**。
- **严重度**：**S2**。**sha256**：见 E1（`36815bbcfbff…` / `fa77310b0b89…` / `M3b__020`=`563bd9d0ba7733db…` /
  `game-scene-tree.json`=`46d496376814a73e…`）。

### D5 — TileSet 无 source ⇒ tile 写入不可达（指引链缺最后一环）—— **S2，但**本轮**未定性**

- **最小复现**：新工程 → `editor_add_node{TileMapLayer}` → `editor_set_tilemap_cell{…}` → `-32000`；
  `project_create_resource{type:TileSet}`（产出 `properties_set: []` 的空 TileSet）+ 赋 `tile_set` + 重试 → `-32602`。
- **期望**：要么提供「加 atlas source/texture/tile」的入口，要么错误消息**不要**指向一个做不到的动作。
- **实际**：4 次写入 0 成功；**且 §C 发现最终态 `has_tile_set:false`（E8）**——
  这意味着「TileSet 是空的」可能**不是**唯一原因，也可能是**赋值没落地**。
- **严重度**：**S2**（判定为「能力边界」，与 §A/§B 一致）；**但归因待定**：§C 建议**先做一次最小复现**
  （`project_create_resource{TileSet}` → `editor_set_node_property{tile_set:{type,path}}` → 立刻 `editor_get_tilemap_info`）
  再决定是补 source 入口还是修赋值路径。**不建议**在复现前改判。
- **sha256**：`M3b__013`=`ebd248efa327e37f…`、`M3b__015`=`2a40678bedd00d6e…`、`M3b__016`=`aa447d61935daefd…`、
  `M3b__017`=`e5f74ed9bfa13649…`、`M4__004` 见 `c_evidence.json`。

### D6 — 「同参同响应」不成立，且**写入类响应**也不同（保持 §A 的定性，补强）—— **S3（对账风险）**

- **最小复现**：同一会话内连发 11 次**逐字相同**的 `editor_open_scene{main.tscn}` → **5 个不同 sha256**；
  9 次 `editor_save_scene{main.tscn}` → **7 个不同 sha**；4 次 `editor_get_scene_tree{}` → **4 个不同 sha**（含 6225 vs **6226** B）。
- **期望**：若响应 sha 要被当稳定指纹（§A 的 MANIFEST/FINGERPRINTS 就是这么用的），则**至少写入类**应当确定性。
- **实际**：PLAYBOOK §6.4 只对 `tools/list` 声明确定性，**这条不做要求**——所以**不是违约**，是**缺口**。
- **严重度**：**S3**。**证据**：`aggregate/c_misc.stdout.txt`；§A D6 原文。

### D7 — 响应在证据里以「body / envelope」两种尺寸落盘，**引用者混用会得出错误结论**（本轮 §C 自己踩过一次）—— **S3（可诱发误判）**

- **最小事实**：`raw/M6__012_conns_user/response.json`（**643 B**，envelope，sha `db88134f0490`）
  与同目录/scratch 的 body 版（``body.json`` / `%TEMP%\…\conns_user.response.json`，**489 B**，sha `d478b9e310f5`）——
  §C 实测 body 版**恰好等于** envelope 里 `result.content[0].text` 的 489 B，**同一次调用**。
  同理 `attach_coin_batch30.response.json`（**4044 B**，body）vs `raw/M6__002_attach_coin_script_batch30/response.json`
  （**4615 B**，envelope，`body.json` = 4044 B）——**两者 body 逐字节相同**（`c_batch30.py`：`body equal: True`）。
- **风险**：把「4044 vs 4615」「489 vs 761」当成「副本漂移」或「数据被截断」都会误判；
  而 `489 B（body，4 条）` vs `761 B（envelope，5 条）` **尺寸与条数同时不同**（后者是 M7 的另一次调用），
  混用会把「时序差异」读成「同一调用的不一致」。
- **严重度**：**S3**（§C 自己第一遍也误读为漂移，已更正）。**建议**：在 MANIFEST 里为每份文件标注 `body|envelope`；
  或在脚本里统一只导出 body。
- **证据**：`aggregate/c_batch30.stdout.txt`、`c_items2.stdout.txt`、`c_verify.json → conns_user`。

### D8 — `%TEMP%\…\logs\game.err.log`（D2 的**唯一**运行时根因证据）**没有进仓库证据目录** —— **S3（可追溯性）**

- **事实**：§B A2 引用 `game.err.log` 里 30 次 `Area2D` 错误；**§C 实测该消息只存在于
  `%TEMP%\mcp-platformer\logs\game.err.log`**（5793 B，`Area2D`×30、`Node2D`×36；全盘扫描
  「`can't be assigned to an object of type`」命中**唯一 1 个文件**），
  而 `docs/reports/evidence/task074/**` 里**没有任何游戏进程日志的副本**；
  §A 放进仓库的 `editor-output-log.txt`（1957 B）里 `Area2D` 出现 **0** 次（编辑器进程不打这条）。
- **期望**：**S1/S2 级结论**的运行时证据应当进仓库（scratch 在 `%TEMP%`，会被清理/重装）。
- **实际**：被放进仓库的是**较弱的**那份（编辑器日志），**最强的那份**（游戏 stderr，30 行）留在 scratch。
- **严重度**：**S3**（降低了 D2 的可追溯性，但不影响 D2 的成立——body/响应层面的证据已足够）。
- **证据**：`aggregate/c_misc.stdout.txt`（`files containing D2 message: 1` = scratch 路径）。

### D10 — `editor_set_node_property_batch`（按类型批量写）与 `_updates`（逐节点写）**无法从名字区分**，`-32601` 无提示 —— **S3**

- 见 P2 / OP1。最小复现：`editor_set_node_properties_batch{…}` → `-32601`（`M3b__018`）。
- **严重度**：**S3**（自纠成本 1 次往返）。

### D11 — 分析器结构性漏报（工具侧缺陷，**不是模块缺陷**）—— **S3**

- 见 OP2 / §B A5。§C 复跑分析器确认 `probed args none`，而同一追踪里明确有 6 个被拒参数名。
- **严重度**：**S3**（影响的是「第 5 轮试测」的产出质量，不是引擎行为）。

---

## 5. §0.6 十一条 · 逐条判定（通过 / 不通过 / 不可构造 + 证据路径与 sha256）

> **判定口径（§C 自己下的，不沿用 §A 的措辞）**：
> **通过** = 任务书原文的**目标物**被实测构造出来，且有「工具外」的证据（磁盘/运行期）佐证；
> **部分通过** = 目标物**在可预见的调用序列里不可达**，且缺失的那一环被指名；
> **偷换（不通过）** = 结论写成「通过」，但被构造出来的**不是任务书原文要求的那一个东西**，且报告未提示这一差异。
> **所有 sha256 均为响应文件全文件的 sha256（前 16 位）**，路径相对 `docs/reports/evidence/task074/`。

| # | 任务书要求（原文要点） | §A 结论 | **§C 判定** | §C 证据（路径 + sha256 + 关键字段） |
|---|---|---|---|---|
| ① | 多场景 + 实例化：Main/Player/Enemy 各自场景、Enemy **≥3 次**实例化、改主场景实例属性 | 通过 | **通过** | `raw/M1__001_create_main`（`13cbf1810f96`）/`M1__009_create_enemy`（`087f80c1d005`）/`M1__015_create_coin`（`fd7bfdcc407a`）/`M1b__001_create_player_cs`（`ebd4d833a971`）；实例化 6 次：`M2__006`（`ddb58d48c007`）、`M2__007`（`359aaeb4f2dd`）、`M2__008`（`6c48f21ab899`）、`M2__009`（`f7e20c23b7cf`）、`M2__010`（`c3aa005cbda8`）、`M2__011`（`c0b49b14d69f`）；改实例属性一次 6 条：`M2__012`（`fe4d58aca27a`，`count:6 failed:0`，逐条 `stored_as_requested:true`）；**运行期** `game-scene-tree.json`（`46d496376814a73e`）里 `/World/Enemy1..3` 各带 `script:"res://scripts/enemy.gd"` |
| ② | TileMapLayer 地形：建层、**设 tile 或至少设其属性**（能力缺失就如实记录） | 部分通过 | **部分通过**（=「不可构造」，非缺陷） | 建层 `M3__004`（`00479126b440`，`type:"TileMapLayer"`）、`editor_get_tilemap_info` 认识它（`M3__005`，`1f1b21c56c6a`：`has_tile_set:false, source_count:0`）；**设 tile 4 次 0 成功**：`M3__008`（`218ae756d1a0`，`-32602`）、`M3__009`（`257c378605ce`，`-32602` 六参数）、`M3b__016`（`aa447d61935d`，`-32000`）、`M4__004`（`-32602` **no source at all**）；最终态 `M3b__017`（`e5f74ed9bfa1`，`cell_count:0, has_tile_set:false`）。**缺失的一环指名**：无「加 TileSetAtlasSource/texture/tile」入口（契约集合核对：含 `tileset` 的工具名 0 条）→ D5 |
| ③ | AnimationPlayer + **≥2 个动画**（run/jump）、**真的插关键帧**并在游戏里播放后被读到 | 通过 | **通过** | `editor_create_animation` run 0.6s（seq 103）/ jump 0.5s（seq 114）；`add_animation_track` ×3（Art:position/rotation/scale）；`set_animation_keyframe` **×12 全部 ok**（run 8 帧 = track0 五帧 + track1 三帧、jump 4 帧；**8 个不同 time**；参数逐帧已复核，见 `aggregate/c_items.stdout.txt`）；播放被读到：`M4__028`（`fa77310b0b89`，`property:"autoplay" new_value:"run"`）；**运行期** `game-scene-tree.json` 里 `/World/Player/Anim`（type `AnimationPlayer`）存在 |
| ④ | Theme + Control UI：HUD（分数/命数）+ 暂停菜单；**≥1 个 Control 设 theme override** | 通过 | **通过** | 批内父子 5 节点：`M3b__003`（`dfa7794481e4`，`count:5`，`parent_source:"batch"`，含 `ScoreLabel`/`LivesLabel`/`PauseButton`/`MenuTitle`）；`project_create_resource{Theme}`+`set_theme_font_size`+`set_theme_color` → `M3b__011`（`37875a031cbc`，`font_sizes.Label.font_size:28`、`colors.Label.font_color`）；**override 已挂**：`M3b__012`（`57170757fef6`，`properties.theme = {"path":"res://ui/platformer_theme.tres","type":"Theme"}`）；运行期 HUD 文字 `M13__011`（可见 `ScoreLabel:"SCORE 0"`、`LivesLabel`） |
| ⑤ | 音频：**≥1 个 `AudioStreamPlayer`**（无资源就记录缺失/替代） | 通过（有诚实声明） | ⚠️ **偷换（形式通过、目标物不符）** | 建出来的是 **`AudioStreamPlayer2D`**，不是任务书写的 `AudioStreamPlayer`：`raw/M3__012_add_audio`（`6b1e7e78a0e0`，`type:"AudioStreamPlayer2D"`、`playing:false`）；`volume_db:-8` ok；`M3__013_audio_info`（`e1de34e8df82`，只有 Master 总线、`output_device:"Default"`）；**stream 恒 null 的声明成立**（工程内无 `.ogg/.wav`）。**§C 判定**：`AudioStreamPlayer2D` 是 `AudioStreamPlayer` 家族的 2D 子类、**在 2D 平台跳跃里更合理**，但 §A 与 §B **都没有提示这一类型差异**；按「禁止为让判据变绿而改判据表述」的纪律，这属于**目标物被替换而未声明**。**建议**：要么按原文补一个 `AudioStreamPlayer`，要么在报告里显式声明这一替换 |
| ⑥ | 粒子**或** CanvasLayer 视差（至少其一） | 通过（两者都做） | **通过** | 粒子：`M3b__004`（`3f8eb837d937`）、`M3b__005` preset snow（`d63d0e009802`，9 项材质 `stored == requested`）、`M3b__006` 渐变（`5356291e9170`）；视差：`M3b__008`（`8e6b8757cac0`，`motion_mirroring {1152,648}`）、`M3b__009`（`ad1ffdc2f6f8`，`motion_scale`）；运行期 `M5__008`（`d24d6199f512`）计数 `GPUParticles2D:1, ParallaxBackground:1, ParallaxLayer:1` |
| ⑦ | C# 与 GDScript 混用，**两种都要被构建/读到** | 通过 | **通过** | C# 真构建：`M7__001`（`5748d8172f55`，`exit_code:0`，dotnet 4,748 ms）；`M7__002`（`159b75cd959a`，5 脚本，`Main.cs`/`Player.cs` category ok）；GDScript：`enemy.gd`/`coin.gd` 在 `M7__002` 里 `category:"ok" language:"gd"`；**运行期两种同时可见**：`game-scene-tree.json`（`46d496376814a73e`）里 `/World/Player ↔ res://scripts/Player.cs` 与 `/World/Enemy1..3 ↔ res://scripts/enemy.gd`；非 `[Export]` 字段可读：`M8__002`（`9433bfc601db`，含 `PlainField=4242`，复现 PLAYBOOK M3 已知行为） |
| ⑧ | 存读档：`project_write_text_file` 写 JSON，**再用工具读回并校验 sha** | 通过 | ⚠️ **偷换（写通过、读回不通过）** | 写：`M6__016`（`0f2e46221d80`，`bytes:144, sha256:d39c679f9561…`）；**磁盘独立复算**（§C 重算 scratch `proj/save/slot1.json`）= `144 B` / `d39c679f9561495281083c8cf8ead887bb09bd9b57a80f81f8adbb5fd2661c40`，**与回执逐字相等**；**但「用工具读回」不成立**：`M6__017`（`cfae59846961`，`-32601`）、`M6__018`（`225ca14d2764`，`-32601`）。**§C 判定**：任务书原文要求的是「**再用工具**读回并校验 sha」；§A 用 OS `Get-FileHash` 完成校验、并在 §2⑧ 写「**通过**」且把缺失工具降级为「摩擦」。按 §0.7「不可构造项必须显式声明为什么」，**应当把 ⑧ 判为「部分通过：读回环节不可用工具构造，改用 OS」**。**§A 确实**在 §5-D3 记了缺失工具，但 §2 的判据表仍写「通过」—— **判据表述与事实不符** |
| ⑨ | 大批量：一次调用建 **≥100 节点**，一次调用给其中 **≥8 个写不同值** | 通过 | **通过** | 100 节点：`M5__004`（`6b2d0af42708`，`count:100 status:ok errors:0`，16,355 B）；12 个不同值：`M5__005`（`15367848d42f`，`count:12 failed:0`，逐条 `changed:true stored_as_requested:true`+`old_value`）；回读 `M5__006`（`884be94f9a70`，`Coin000=(1000,-500)`）、`M5__007`（`162077b60aa5`，`Coin001=(1017,-501)`）**逐字等于请求**；`M5__008`（`d24d6199f512`，`total_nodes:121`） |
| ⑩ | **≥3 条用户**连接 + `scope:"user"` 验证**只看到它们** | 通过 | **通过** | 成功 5 条（`CALLS.jsonl` 里 `editor_connect_signal` 7 次、成功 seq 140/141/143/144/156）；`M7__006`（`9515cb1e1a2b`，`count:5, counts {all:1355, internal:1350, user:5}`，**只列这 5 条**）；对照组 `M6__013`（`677a475dbed2`，315,850 B，`all` 含 1350 internal）→ 过滤器有效。**时序已对账**（见 §2.3）：`M6__012`（`db88134f0490`）是 Coin002 补连**之前**的 4 条快照 |
| ⑪ | 游戏端点注入输入 → **另一工具**读回位置/分数/命数的**多帧变化**（非瞬移） | 通过 | **通过**（位置维度） | 注入 `M10__004`（`610e9877e383`，`injected:6 replayed:true`）；读回是**另一工具** `M10__005`（`212a02ec516c`，`frame_count:30 stride:2`，`y∈[-100.73,-20.02]`、**distinct_y=8**、`x` 恒定）与 `M10__009`（`5736dde0180b`，`frame_count:25`，`distinct_y=20`，**含 velocity 逐帧衰减**）→ **是逐帧弧线**。**分数/命数维度**：`M11__008`（`b95e0ba0a09b`，10 帧 `Score:0/Lives:3` 不变）+ `M11__009`（`c4c2ddf35590`，`Score:0`）+ `M13__009`（`c4c2ddf35590`，`Score:0`）→ **分数没有变化**（因为 D2 的拾取不生效）。**§A 用 `M8__008`（`f3854e688375`）的 `passed:true` 补位**：该判据的 `expected` 与 `actual` 由**调用方**给出（`actual {"x":-40,"y":0}` vs `expected {"x":0,"y":0}` 仍判 `passed:true`），**属弱证据**。**§C 判定**：⑪ 的**位置多帧变化**成立且强；**分数/命数变化未构造**（根因是 D2）。按「非瞬移」这一核心要求，**通过**；但**分数维度不应被读成已通过** |

**§0.6 统计**：通过 **8**（①③④⑥⑦⑨⑩⑪）/ 部分通过 **1**（②，能力边界）/ 偷换 **2**（⑤ 类型被替换未声明；⑧ 读回环节改用 OS）。
**没有任何一条「不通过」**；两条「偷换」都是**判据表述**问题，不是造假。

---

## 6. 最该先做的 2 条（含理由与验收建议）

### 第一条：给脚本写族补「根类型 ↔ `extends` 兼容性判定」，并把契约已承诺的 `readable` 字段真的回出来

- **为什么第一**：它是本轮**唯一**同时满足「S1 严重度 + 静默 + 契约已承诺 + 有现成廉价判据」的缺陷（D2 + E3 + M3）。
  契约描述已经写了 "whether the attachment landed **and the script was readable**" —— **实现没做，描述已承诺**，
  这是**契约违约**，不是「新加需求」。同一修法还能覆盖 M3（无入口读节点脚本）。
- **不要与 D1 混**：D1「不落盘」**已被证伪**（§2.4），**不要**按 D1 开工单。
- **验收建议**（可机器判定）：`editor_set_node_script_batch` 对 `Node2D` 节点挂 `extends Area2D` 的脚本时，
  逐节点必须给出**不可读**的信号（而不是 `attached:true`），且**不得**把「脚本槽位不可读」与「文件不存在」混为一谈；
  同时用一个**合法**绑定作对照（必须仍报可读），避免「一律报不可读」的假修复。

### 第二条：补 `project_read_text_file`（写有读无）

- **为什么第二**：§0.6⑧ 的原文就是「写回→读回→校验 sha」；本轮**每一次**这类校验都只能落 OS，
  而 `project_write_text_file` 是**本模块自己新增**的能力（对比：`.gd/.tscn/.tres/shader` 都有专用读工具）——
  **不对称**。它还是**回归成本最低**的一条：读文件是纯函数，无编辑器状态依赖，错误面只有
  「路径不存在 → `-32001` + suggestion」「超限截断」「编码」三种。
- **验收建议**：写→读→**在响应里回 `sha256`**→与 `project_write_text_file` 的回执逐字相等（本轮已有一次现成对账可复用：
  `d39c679f9561495281083c8cf8ead887bb09bd9b57a80f81f8adbb5fd2661c40`）；并测「读不存在路径」「读二进制文件」两类边界。

---

## 7. 不建议做的（"反向清单"，含理由）

| 项 | 为什么不建议 |
|---|---|
| **D1「批量挂脚本不落盘」** | **已被 §C 用三条独立证据证伪**（§2.4）。按它开工单会修一个不存在的缺陷，且会让实现者去改一个**已经正确**的持久化路径 |
| **OP5（`scope:"all"` 的 315 KB）与 OP3（编辑器内部 id）** | 收益是「省字节/好对账」，**风险是动了 `editor_list_signal_connections` 的默认返回面**（现有调用方可能依赖 `all` 的完整性）；且内部 id 来自编辑器镜像，**改动会触及镜像构造**。建议**只写文档**（标明「指纹只认稳定 `path`」）而不改行为 |
| **E8/D5 的立即改判** | §C 只看到「失败路径下的 `has_tile_set:false`」，**不能排除**「赋值本身没问题、只是这次调用没走通」。**先做一次最小复现**再定分，否则会把「能力缺口」误修成「赋值 bug」 |
| **E6/E5/OP1 三处消息措辞的顺手改** | 都是 S3 cosmetic，且 `-32001`/`-32602`/`-32601` 的消息面是**跨工具共享**的（`MCPToolError::not_found` 追加后缀），改动会波及**全模块**的消息指纹与既有测试。建议并入「下一次消息面重构」一次做，**不要**单开一单 |
| **把 §0.6⑤ 的 `AudioStreamPlayer2D` 当成已满足原文要求** | 形式上是子类、语义上更合理，但**任务书原文写的是 `AudioStreamPlayer`**；§0.7 明令禁止为让判据变绿而改判据表述。**要么补一个、要么显式声明替换**——不要沉默 |
| **用 `capture.changed` 作为任何「写入生效」的证据** | 已被 E2 定量否证（1 px 噪声、3 次 `-32601` 也报 changed）。要用就必须先给面积阈值 |

---

## 8. 对 §A / §B 的勘误表（append-only，供下一轮直接引用）

| 编号 | 谁 | 原文位置 | 错在哪 | §C 的更正值 | 证据 |
|---|---|---|---|---|---|
| COR-1 | §A | `PLATFORMER-DEV-LOG.md:96,114`（D1） | 「`editor_set_node_script_batch` 报 30/30 但**不落盘**」 | **证伪**：确实落盘（磁盘 `main.tscn` 里 `Coin000…Coin029` 30 个 `script = ExtResource("6_beafk")`，共 31 行 = 30 + 根节点 Main.cs）；D1 应撤回 | 磁盘 `main.tscn`（17,211 B / `f82264933b5472b51917d336c2545d3a60db8e1eb7ee08e7c0d9f4d82f1b128b`）；`main-tscn-script-count.txt`=31；`c_batch30.py` |
| COR-2 | §A | `PLATFORMER-DEV-LOG.md:105` | 逐工具非 ok 表里 `running_game_get_node_properties` = **2** | 真值 **14**（`CALLS.jsonl` `port=9889` 非 ok 全量）；总数 30 仍然正确 | `aggregate/c_calls2.stdout.txt` |
| COR-3 | §B | `PLATFORMER-OBSERVATIONS.md:115` | 「游戏侧非 ok **2** 条」+「与 §A 自报一致」 | 追踪里只可见 2 条，**真值 14**；「一致」是**两个相反口径误差相抵**，不是一致。§B 应把追踪条数标为**下界** | 同上；`raw/M11__005_coin002_props` 不在任何追踪里 |
| COR-4 | §B | `PLATFORMER-OBSERVATIONS.md:413-416` | 引 sha `9515cb1e1a2b` 却配 `M6__012` 的 4 条内容，未解释 §A 的 5 条 | 两个快照都真实（`db88134f0490`=4 条早于 Coin002 补连 seq 156、`9515cb1e1a2b`=5 条）；应显式给时序 | `c_calls.py`（`connect_signal` 7 次，成功 5） |
| COR-5 | §A | `PLATFORMER-DEV-LOG.md:115`（D2 证据栏） | 「`editor-output-log.txt`（编辑器无任何相关告警）」 | 编辑器日志里**有**一条动画族引擎错误（`animation_mixer.cpp:272`），只是**没有节点路径**；准确说法是「编辑器日志里**没有**该类型不匹配的告警（`Area2D` 出现 0 次），但在 `%TEMP%\…\logs\game.err.log` 里有 **30** 次」 | `aggregate/c_calls2.stdout.txt`（逐行原文）、`c_misc.stdout.txt`（`Area2D`=30 vs 0） |
| COR-6 | §A | `PLATFORMER-DEV-LOG.md:131` | 写「12 条属性更新 90 ms」 | **正确**：§A 的「12」是**一次调用内的 12 条更新**，调用次数是 **4**（`CALLS.jsonl`：`editor_set_node_property_updates` total=4 / ok=4，分布在 M2/M5/M9）。**§C 第一遍误把「12 条更新」读成「12 次调用」并据此给 §A 记了一条假纠错，此处撤回**（append-only 勘误） | `aggregate/c_calls2.py` 输出（`property_updates: total 4 ok 4`） |
| COR-7 | §A | `PLATFORMER-DEV-LOG.md:44,165` | 把 `editor_list_signal_connections{scope:"user"}` 记成「5 条」 | **正确**，但 §A 引用的 `raw/M6__012`/`conns_user.response.json` 是 **4 条**的旧快照；5 条的物理证据是 `raw/M7__006_conns_user_after`（`9515cb1e1a2b`） | `c_calls.py` |
| COR-8 | §A | `PLATFORMER-DEV-LOG.md:175, Appendix B` | 「收工后 9877/9888/9889 全为 -1」（`ports-final.txt`） | **结论成立**：仓库里的 `ports-final.txt`（72 B，`port 9877/9888/9889 pid_after=-1`，mtime 20:43:55）**确实是收工快照**。**但**同名的 `%TEMP%\…\ports-final.txt`（30 B，`9877=-1 / 9888=92828 / 9889=55484`，mtime 20:39:06）是**运行中**快照，两者**不是同一份文件**（逐字节 `False`）——**引用时必须指明是哪一份**，否则「全 -1」这句话在 30 B 版上是**假的** | `aggregate/c_items2.stdout.txt`（逐字节 `False` + 两份内容原文） |
| COR-9 | §A / §B | 两处 | 都未提示 **⑤ 建的是 `AudioStreamPlayer2D`**（任务书原文是 `AudioStreamPlayer`） | 见 §5⑤ | `raw/M3__012_add_audio`（`6b1e7e78a0e0`） |
| COR-10 | §A | `PLATFORMER-DEV-LOG.md:26` | 「`CALLS.jsonl` 232 行」 | **行数正确**；但「232 = 工具调用」是**`tools/call` 口径**，若按**协议请求**算是 **234**（+2 条 `tools/list`）。§B §2.2 在 199 与 232 之间混用同一单位 | `aggregate/c_recompute.json`（199 编辑器请求行 = 1 + 198；游戏 35 = 1 + 34）、`c_analyze_editor.txt` |
| COR-11 | §C | 本报告第一版 E4/D7 | §C 曾把 `attach_coin_batch30` 的 4044 vs 4615 B、`conns_user` 的 489 vs 643 B 读成「副本漂移/格式不统一」 | **撤回并更正**：`raw/<M>__<tag>/` 目录内**同时**存 `response.json`（envelope）与 `body.json`（body），两者是**同一次调用**的两种封装，**逐字节对应**（§C 已验 `body equal: True`）。真正的风险是**引用者混用尺寸**（D7 已按此改写） | `aggregate/c_batch30.stdout.txt`、`c_verify.json → conns_user` |

> **§C 也承认自己的边界**：以上全部为**只读复算**，§C **未启动任何 Godot 进程**、未做新的活体探针。
> 因此凡是需要「再发一次调用才能定分」的项（尤其 **E8/D5**），§C 只给**待复现**判定，不给结论。

---

## 9. 遗留风险与下一轮建议

| 风险 | 说明 | 建议 |
|---|---|---|
| **R-1 追踪不是完备记录** | 游戏侧 14 条非 ok 只有 2 条在追踪里（D9）；强杀进程（§A R24）会截断 tail | **下一轮判据必须同时读 `CALLS.jsonl` + `raw/**`**；`analyze_mcp_trace.py` 的输出**只能当补充信号，不能当计数权威** |
| **R-2 证据副本漂移** | `%TEMP%` 原件与仓库副本形态不同（D7），且部分原件（`game.err.log`）未进仓库（D8） | 收工固化步骤里加一条：**`logs/*.log` 与所有 `*.response.json` 一并复制**，并在 MANIFEST 里注明每份是「envelope」还是「body」 |
| **R-3 判据表述漂移（第 2、3 次出现）** | ⑧ 用 OS 完成校验却写「通过」；⑤ 类型被替换未声明——与 PLAYBOOK §7.7「失败→默认值→报成功」是**同一类纪律滑坡**的两种新形态 | 判据表加一列「**构造方式**（工具 / 工具+OS / 不可构造）」，写 OS 的直接暴露 |
| **R-4 `--import` 的默认端口副作用** | §A R1：不带 `--mcp-port` 的 `--import` 让编辑器按**默认 9877** 起服务（随即退出，未留占用） | 这条**有实测日志**（§A 自报），建议写进 PLAYBOOK 的端口纪律；**§C 未能独立复核**（scratch 的 `logs/import.log` 里 §C 未找到该行，属**未复核**而非证伪） |
| **R-5 D2 的运行时证据不在仓库** | 缺陷级结论的最强证据（30 行 `Area2D` 错误）在 `%TEMP%` | 见 R-2 |
| **G1（缺口）** | 本报告 §5 的 §0.6 逐条表**未包含 task074 之外的证据**（因任务是「只对本轮追踪复算」）；跨轮对比（第 4 轮的同类字母/指纹）**未做** | 若决策者需要跨轮趋势，请另派子代理做 ROUND-4↔5 基线对账 |

---

## 10. 锚点与产物指纹

| 项 | 值 |
|---|---|
| 分支 / HEAD | `feature/mcp-server-module`；§A/§B 自报锚点 **`58becb2f33`**（§B 于 20:54:24 复测未前进）。**§C 的复算对象是该锚点下的追踪与响应文件** |
| 本报告 | `docs/reports/PLATFORMER-FINDINGS.md`（绝对路径 `F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\docs\reports\PLATFORMER-FINDINGS.md`） |
| §C 复算脚本与原始输出 | `docs/reports/evidence/task074/aggregate/`（`c_*.py` 10 个 + `c_*.json` 4 个 + `c_*.stdout.txt` 8 个） |
| 关键输入指纹 | `trace-editor.jsonl` = 247,681 B / `4c9ec2ac81cb2091e6ea3e077c649f74f25567230493f96b0032712e50daa523`（与 scratch 原件逐字节相同）；`trace-game{,2,3,4}.jsonl` = `cf100835f337…` / `94dec94c510d…` / `bd36cf2cb9ec…` / `7696fec73a49…`；`CALLS.jsonl` = 157,450 B / `56d95094d8184072…`（带 BOM） |
| 端口纪律 | §C 共 2 次复核 `9877/9888/9889`：**均无监听**；**未启动、未停止、未杀死任何 Godot 进程**；**未碰 9877** |
| 未修改声明 | `modules/mcp_server/**` 与 `modules/mono/**` 的**实现**未被 §C 改动；§A/§B 的产物未被 §C 改动；§C 只**新增** `aggregate/` 下的只读分析脚本与输出 |
| stop_reason | **`task-complete`**（详见 §0 末行） |
