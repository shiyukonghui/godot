# BREAKOUT-FINDINGS — TASK-060 §D（**补做**；由 TASK-062 生成）

> **本文件是 TASK-060 §D「汇总者」的补做产物**。TASK-060 §D 从未运行，第 2 轮 workflow 被取消。
>
> ## 权威性与方法（先说清楚，否则下面的数字没有意义）
>
> 1. **输入以原文为准，不采信报告叙述。** 本文的每条结论都来自
>    `modules/mcp_server/docs/reports/evidence/task060/**` 里的**响应原文、追踪原文、日志原文**
>    （以及 TASK-062 从 `%TEMP%\mcp-breakout` 回收进来的 `trace-recovered/**`）。
>    §A/§B/§C 三份叙述性产物**只作为「被核对的对象」**，凡与原文不符的都在 §4 单列纠错。
> 2. **实测 vs 推断**：每条结论标 `实测`（有落盘文件 + sha256）或 `推断`（读源码/契约得出）。
> 3. **追踪复算口径**：把 `trace-recovered/` 下 25 份追踪（1 份最终 + 24 份 `.prev-*` 快照 + 1 份游戏追踪）
>    按 **`(pid, seq)`** 去重——`seq` 每代从 1 重启、`trace_opened` 是唯一分代边界，所以
>    **`(pid, seq)` 是同一次调用的精确身份**。去重后 **309 次 `tools/call`（实测）**。
>    复算脚本与产物：`evidence/task060/trace-recovered/TRACE-FRICTION-ANALYSIS.json`
>    与 `TRACE-RECOVERY-SUMMARY.json`。
> 4. **D86 锚点**：被评产物写于 HEAD `4f99a4e37ac4160b5c9b98513068872521bee975`
>    （`feature/mcp-server-module`），编辑器二进制 `4.8.dev.mono.custom_build.cd7224274`；
>    本文件的回收/复算动作在 HEAD `97144b5afb` 起的工作树上完成。
> 5. **⚠️ 本轮观察不完整**（见 §0.3）：§C 的观察窗口是 05:34:40–06:00:25，而开发实际持续到 08:01:15。
>    **哪些结论因此不可信，在 §5 逐条列清。**

---

## 0. 证据基线

### 0.1 回收后的证据地图（TASK-062）

| 目录 / 文件 | 内容 | 来源 |
|---|---|---|
| `evidence/task060/c1/` … `c4/` | 四组判据的请求/响应原文 + `.sha256` 边车 | §B 开发时当场入库（原落在引擎仓根 `docs/reports/`） |
| `evidence/task060/b0-bootstrap/` | 工程引导、导入日志、自写文件 sha256 | 同上 |
| `evidence/task060/probe-{cs2,cs3,gdscript,paths}/` | 四组最小探针 | 同上 |
| `evidence/task060/c-obs/` | 观察者的 watchdog、日志、探针响应、最终 6 行追踪 | 同上 |
| `evidence/task060/PROVENANCE.json`、`contract-excerpt-six-capabilities.json` | §A 的溯源与契约摘录 | 同上 |
| **`evidence/task060/trace-recovered/`** | **TASK-062 新回收**：完整编辑器/游戏追踪（1 + 24 + 1 份）、`logs/`、`scripts/`、`out/` | `%TEMP%\mcp-breakout`（只读复制） |
| **`evidence/task060/DEV-LOG-raw-run.log`** | **TASK-062 新回收**：`run.log`（41 159 B），§B 承诺过但从未入库的那一份 | 同上 |
| `evidence/task060/recovery/` | 搬移/改路径/前插标注的机器可读对照与复算产物 | TASK-062 |

**回收自检（实测）**：搬移前后 **445 个文件、658 190 B**，两份 sha256 清单
（`recovery/MOVE-BEFORE.sha256.tsv` / `MOVE-AFTER.sha256.tsv`）**逐字节相同**，
清单自身 sha256 均为 `a7a623a5417e44fbe0fe9a779e9de117d2bd9ee3d5313a6ad3572b021c29f7ce`
→ **没有丢内容**。

### 0.2 追踪复算总账（`实测`）

| 项 | 值 | 证据 |
|---|---|---|
| 分代数 | **28**（26 编辑器 + 2 游戏） | `TRACE-FRICTION-ANALYSIS.json` `generations` |
| 去重后 `tools/call` | **309** | 同上 `total_distinct_calls` |
| 捕获行 | **307**，**307/307 `status:"unavailable"`，`changed` 全为 `null`，`changed_pixel_ratio` 全为 `null`** | 同上 `capture_*` |
| 大响应（>1 MiB） | **0** | 同上（分析器阈值内） |
| 错误码分布 | `0`×200、`-32602`×77、`-32001`×22、`-32000`×7、`-32601`×3 | 同上 `calls_by_error_code` |
| 失败→成功对（同代、同工具、≤12 次内） | **28 对** | 同上 `friction_fail_then_success` |
| 对 `editor_list_signal_connections` 的调用 | **0** | 同上 `calls_by_tool` 无此键 |
| 对 `running_game_*` 的调用 | **1**，且是**观察者**在 9888 上的 `-32601` 探针 | `calls_by_tool` 只有 `running_game_get_node_properties`=1；`c-obs/obs-runninggame-at-9888.resp.json` sha `7a89ea34e3d7156de5210eb8775174211726725a7f176e6c905cac54d231c244` |

**每工具的调用次数（去重，`实测`）**：
`editor_set_node_property` 60 · `editor_set_node_script_batch` 39 · `editor_execute_gdscript` 26 ·
`project_validate_scripts` 23 · `project_set_setting` 18 · `editor_get_scene_tree` 17 ·
`editor_add_nodes_batch` 16 · `editor_save_scene` 15 · `project_build_csharp` 13 ·
`project_read_scene_file_content` 12 · `editor_add_input_action` 12 · `project_edit_script` 12 ·
`project_validate_script` 11 · `editor_get_node_properties` 9 · `project_get_settings` 5 ·
`editor_set_node_property_batch` 4 · `editor_get_input_actions` 4 · `project_write_text_file` 4 ·
`project_remove_autoload` 3 · `project_create_script` 3 · 其余 3 个工具各 1。

### 0.3 `stop_reason` 对账（§D 的硬要求；**不采信 §C 的转述**）

§D 要求「必须自己打开 `watch.log` 与 `watch-summary.json`，逐项抄进报告并与 §C 说的对账」。

| 字段 | §C 说的（`BREAKOUT-OBSERVATIONS.md`） | 原文实际（`实测`） | 对得上？ |
|---|---|---|---|
| watcher 程序 | 自建 `watch.ps1`，预算 1500 s | `c-obs/watch.ps1` sha `a18e9c052d087ec2544c3dff4794261c505bf89573c918e35d44b667cbc84d8c`，纯 ASCII（>127 字节数 = 0） | ✅ |
| `stop_reason` | `BUDGET_REACHED` | `c-obs/watch.log` sha `a584bc61dcfcc1a2e852048dbd5cc6b9b482d470d1bb1bf6415f21e9f60a0cf2` 末行：`t+1505s 06:00:25 … marker=False ports9877=0 ports9888/9=1 BUDGET_REACHED traces=1` | ✅（但**不是** TASK-061 的 `marker\|timeout\|stale` 三值域） |
| `polls` | 未给（§C 只写「76 次采样」） | `watch.log` 共 77 行（1 行表头 + 76 次采样） | ✅ 口径一致 |
| `elapsed_sec` | 未给（可推 1505 s） | `t+1505s` | ⚠️ §C 未按字段给出 |
| `last_seq` / `trace_lines` | §C 给的是「6 行」 | 观察时的追踪确有 6 行（`c-obs/trace-editor-headless.final-6lines.jsonl` sha `49f50156db4aee9f3a76d6ddbd37a2ed6b99b8e70209c0a4b48fd41e2a6d30d3`） | ✅ |
| `watch-summary.json` | **未提及** | **仓库内不存在** | ❌ 该字段要求落空 |
| 观察覆盖 | §C §5.0 写「§B 在整整 25 分钟预算内没有发出任何一条 `tools/call`」 | 观察窗口 05:34:40–06:00:25；§B **第一次**工具调用的响应文件 mtime 是 **06:26:28**（`c1/c1_g1_remove_autoload.response.json`）；**最后一次**开发证据 mtime **08:01:15**（`c4/`） | ⚠️ §C 的句子**只对 06:00:25 之前成立**；这不是「合格（marker）」观察 |

**判定（`实测`）**：`stop_reason = BUDGET_REACHED`（非 `marker`）⇒
**依 TASK-060 §D 的硬性要求，本轮必须在报告里明确标注「本轮观察不完整」** —— 本文照办（见 §5）。
观察环节的机器可读字段**不全**（缺 `stop_reason` 三值域、缺 `watch-summary.json`），
且 §C 在自身预算到顶后就收尾，**未等到开发结束**：**观察环节不合格**（单列于 §3 D-8）。

---

## 1. 专答：§A 的六条新能力判据（**本轮的主验收点**）

> §A §5.1 定的最简门槛：每条必须有 `判据编号 | 结论 | 证据（文件 + 行号 + sha256）` 三列，
> **只有形容词的行按「不通过（证据不足）」处理**。下表照办。

### 1.1 结论总表

| # | 能力 | 结论 | 一句话理由 |
|---|---|---|---|
| ① | 注释保全（`project_set_setting` / `editor_add_input_action`） | **不通过** | 6 条子判据里 4 条通过、1 条判据自相矛盾、**1 条与证据相反**（P1f） |
| ② | C# 真结论（`invalid`+编译器原文 / `ok` / `not_compiled`） | **通过** | 三类别均在原文里出现且口径正确；`unverifiable` 显式声明不可构造 |
| ③ | 批量父子（`editor_add_nodes_batch{resolve_within_batch:true}`） | **通过** | 一次调用建 26 节点（方案写 27 是方案缺陷）、父子来源可区分、拒绝与回滚可链式判 |
| ④ | 批量挂脚本（`editor_set_node_script_batch` + `keep_existing`） | **不通过** | 核心跳过语义通过，但**「读回证明」不可归因**、**「跳过不动盘」是退化对照**、`P4f` 未构造 |
| ⑤ | `scope` 收窄（`editor_list_signal_connections{scope:"user"}`） | **不通过（不可构造）** | 全程 **0 次调用**该工具；无 `c5/` 证据目录；`BREAKOUT-DEV-LOG.md` §4.5 仍是占位符 |
| ⑥ | 捕获 `changed:false`（`--mcp-capture=every_call`） | **不通过（不可构造）** | **307/307 捕获行是 `unavailable` / `changed:null`**；无窗口化追踪；只观测到 headless 边界（§A 明令不得用它顶替） |

### 1.2 ① 注释保全 —— **不通过**

| 子判据 | 结论 | 证据（文件 + sha256） | 复算事实 |
|---|---|---|---|
| **P1a** `S1 != S0`（证据真的写进去） | **通过** | `c1/project.godot.before` sha `841e2803e5b8b4b77f37b5cdfad4174cfdeec25771371fe1c9fc0696a78bed3a`（383 B）→ `c1/project.godot.after` sha `94050a8079a71d6881b249725e7debc1f6e11411cb417bc3ef6af5f0317f2888`（1 046 B） | `实测`：字节数变了 |
| **P1b** 4 行探针注释逐字仍在 | **通过** | `c1/project.godot.after`（同上 sha） | `实测`：`; mcp060 comment {1..4} of 4` 各 1 次，注释行数 = 4 |
| **P1c** 目标节外**逐字节**不变 | **不通过（判据自相矛盾）** | `c1/p1c_section_split.txt` sha `188c636e312e820300490df5bb9e675bf04b6e7da43f1b3d87c19a0026992e6`；`c1/p1_report.txt` sha `be0596976616427c04675160d6e896b81576d2abf91bd204bf95322f18f48ca2` | `实测`：`[application]` 82→82 B 逐字节相同；`[rendering]` 177→178 B（只差 1 个尾随换行）；**方案 STEP 3 自己要求写 `physics/common/…`，必然追加 `[physics]` 节（46 B）** → 该判据在方案自己的构造下**不可能为真** |
| **P1d** 落点正确（都在 `[input]` 内） | **通过** | `c1/p1_report.txt`（同上 sha） | `实测`：`[input]` offset 197、`[rendering]` offset 821、三个探针键 offset 205/293/735 → 均在区间内 |
| **P1e** 幂等（`S2 == S1`） | **通过** | `c1/project.godot.after2` sha 同 `after` | `实测`：逐字节相同 |
| **P1f** 引擎真的认了（不看文件看引擎） | **❌ 不通过（与证据相反）** | `c1/c1_a6_get_input_actions.response.json` sha `1a5da0e49d60165c6895b01181272cbfa8fb2642c526e60f8a1f6d11432d1388` | `实测`：该响应（**正是 `p1_report.txt` 自己引用的那个 sha**）的 `actions` 列表里**没有** `mcp060_probe_action`；有的是 `mcp060_probe_action2` 与 `mcp060_probe_probe_key`。而 `p1_report.txt` 却写 `InputMap has mcp060_probe_action : True` |
| **P1g** 对照组（未切换的工具必须丢注释） | **通过** | `c1/p1g_after_remove_autoload.txt` sha `7b95fdd4af22093476fd4223a7c2ad7e7226c3d558d4b808747cc17a344be44a` | `实测`：探针注释 0 行，文件以 `; Engine configuration file.` 开头（引擎 7 行头） |

**① 的实质发现（`实测`，值得单独立项）**：
`project_set_setting{key:"input/<action>"}` 把设置**写进了 `project.godot`（`saved:true`）**，
但**运行中的编辑器并没有把它变成活的 InputMap 动作**——P1f 的原始证据恰好把这个事实打出来了。
真正会更新内存 InputMap 的是 `editor_add_input_action`。这**不是**工具缺陷
（写文件是它的契约），但**§A 的 P1f 问法有问题**：它要求"另起 headless 进程问引擎"，
而 §B 用**同一个**编辑器进程问，两者不可互相证明。见 §3 D-2 与 §2.2 M-2。

### 1.3 ② C# 真结论 —— **通过**

| 子判据 | 结论 | 证据（文件 + sha256） | 复算事实 |
|---|---|---|---|
| **P2a** `ok` / `invalid` / `not_compiled` 各 ≥1 | **通过** | `ok`：`c2/c2_v5_validate_ok.response.json` sha `b18ac8290db2cb6599edb5a7d12bd51ab4569d199ef533c4c801914fad81250e`（`valid_count=2`）、`c2/c2_a2_validate_all_final.response.json` sha `a24a7ad11b05379dee5d5b25817a5e8a3c9648295c7edad0ef8d4857417436bb`（`valid_count=6`）；`invalid`：`c2/c2_v2_validate_broken_built.response.json` sha `c088002bfd95939736fc1a3529a994a93878744d59a223b5a29d874d51cc861b`；`not_compiled`：`c2/c2_v1_…` / `c2/c2_v3_…` | `实测`：三类均在原文出现 |
| **P2b** `not_compiled ≠ invalid`（T1 与 T3 都必须是 `not_compiled`） | **通过** | `c2/c2_v1_validate_broken_notbuilt.response.json` 与 `c2/c2_v3_validate_fixed_notbuilt.response.json` **sha256 完全相同**：`a631ecb29649162c63f5b566c1ab24a56aefd2f9f708e023df8a4027185a5d39` | `实测`：两者 `count=1 invalid=0 not_compiled=1`、`valid:null`。「写坏未构建」与「改好未构建」响应逐字节相同 → **「没编译」没有被冒充成「编译失败」** |
| **P2c** 编译器原文是真的（`error CS####` + 文件位置） | **通过** | `c2/c2_v2_…`（同上 sha） | `实测`：`error_text` 含 `…\scripts\Broken.cs(5,5): error CS1519: 成员声明中的标记“this”无效`、`Broken.cs(5,23): error CS1002: 应输入 ;`、`Broken.cs(6,1): error CS1519`、`Broken.cs(5,24): error CS1040` → **既有诊断码，又指向文件(行,列)** |
| **P2d** `valid` 口径（`ok→true`、`invalid→false`、`not_compiled→null`） | **通过** | `c2/c2b_validate_one.response.json` sha `457aec79db6ba3c91dd81c1d9d46c0da8feb8cc0c55ca153a5a15777270a767c`；`c2_v2`（sha 见上）；`c2_v1`/`c2_v3`（sha 见上） | `实测`：三个值在同一批响应里可区分，`not_compiled` 是 `null` **不是** `false` |
| **P2e** `count` 自洽（= 五类之和 = 被问文件数） | **通过** | `c2/c2_a2_…`（sha 见上）、`c2/c2_v4_…` | `实测`：`a2`: `count=7 ok=6 not_compiled=1`；`v4`: `count=2 invalid=1 not_compiled=1`；`returned` 与 `count` 相等 |
| **P2f** 单数工具对「改过未构建」拒绝，且**不**说 `Compilation failed` | **通过** | `c2/c2_sv1_singular_broken_notbuilt.response.json` sha `217b62527d66ca9221dd03f2575b7a31ff6900dc14f0072a9c8f7375b3dbf5ba` | `实测`：`-32000`，`message` 含 `no build of this source is loaded`，`data.suggestion` 明写 `This is 'not compiled', which is not 'does not compile'` |
| **强证据：同一响应里 `invalid` 与 `not_compiled` 并存** | **复现成功** | `c2/c2_v4_validate_both_in_one_response.response.json` sha `f83988170bbfbf5372e10797d9aa312b25d142eaebfc6c43f43c7cecb862f09e` | `实测`：`count=2`，`Broken.cs → not_compiled/valid:null`，`SignalRegistry.cs → invalid/valid:false` + `error CS0103: 当前上下文中不存在名称“NoSuchFlags”` |
| **P2g** 诚实边界（`invalid` 只可能出现在一次本工具跑过的构建之后） | **通过（声明）** | `c2/p2_report.txt` sha `f81ae08f074487a3fd8ada3593ffcc970dfaf81f0bce42fc856d9f98b2705219` | `实测`：原文有 `P2g NOTE` |
| `unverifiable` | **不可构造（显式声明）** | `probe-cs2/pcs2_q1_load_class.response.json` | `实测`：`ResourceLoader.load("res://scripts/Ball.cs","Script")` 返回 `CSharpScript` → 「引擎载入失败」这条分支对可读 `.cs` 不可达 |
| `language_unavailable` | **未观测（mono 构建）** | — | `实测`：落盘的 **8 份批量 validate 响应**（`c2_a0`/`c2_a2`/`c2_v1..v5`/`c2b_validate_one`）里 `unavailable_count`/`unverifiable_count` **全为 0** |

### 1.4 ③ 批量父子 —— **通过**（含一条方案缺陷）

| 子判据 | 结论 | 证据（文件 + sha256） | 复算事实 |
|---|---|---|---|
| **P3a** 一次调用建完 | **通过** | `c3/c3_a1_batch_27.response.json` sha `c841696ca4bf68e82d0f3730d3cae1db951fd99b0f18992b77d41052c4ce029d` | `实测`：`count=26 created=26 errors=0`；追踪里同代仅 1 行该调用。**方案 §2③ 写 27 是错的**：它自己列的清单是 1+1+3+1+1+1+18 = **26** |
| **P3b** `parent_source` 两个来源都出现 | **通过** | 同上 | `实测`：`scene=5`（`Main`/`Walls`/`Paddle`/`Ball`/`Bricks`）、`batch=21`（3 墙 + 18 砖）、`missing=0` |
| **P3c** 另一个工具读回树（不能只看响应） | **通过** | `c3/c3_a2_read_tree.response.json` sha `8de6cff3d7fa5d471b26cf860483fe0c15efc34751c786b9ceae93ee23408838`；`c3/c3_a9_read_scene_final.response.json` sha `a84b26a91bda22ea963429e682759e276cdb1bbdb787618ea473e16c5c9ed423` | `实测`：`editor_get_scene_tree` 里 18 砖 **18/18**；存盘后读盘 18/18 |
| **P3d** 子先于父 → 拒绝 + 整批回滚 | **通过** | `c3/c3_d1_batch_reversed.response.json` sha `c1c1f9331a7f25244438e2c9ceb76df7a695399915363d79fd7c46316d57d985` | `实测`：`-32001`、`data.batch{status:"rolled_back", on_error:"all_or_nothing", count:0, errors:[{index:0,…}]}`；读回 `RevHost`/`RevChild` 均不存在 |
| **P3e** 同批重名 → 拒绝 + 回滚 | **通过** | `c3/c3_e1_batch_duplicate.response.json` sha `c1315bba37107ebebc4654bb634361ddcc3c0e20abf41502cfb212ee4df9ebdf` | `实测`：`-32602`，`rolled_back` 逐项带 `index`/`node_path`/`reason`；读回 `DupHost` 不存在 |
| **P3f** 默认 `false` 行为逐字未变（回归） | **通过** | `c3/c3_f1_batch_default.response.json` sha `d0ace5939e6f93970fda948bd989eb1116a00e8a83a3110c1bc6a5d10e4b82d2` | `实测`：同 body 去掉 `resolve_within_batch` → `-32001 nodes[1]: parent 'DupHost' not found` + `rolled_back` |
| **P3g** 拒绝形状可定位第 i 项 | **通过** | 同 P3d/P3e 两份原文 | `实测`：`errors[].index` 分别指 0 与 2 |

### 1.5 ④ 批量挂脚本 + `keep_existing` —— **不通过**

| 子判据 | 结论 | 证据（文件 + sha256） | 复算事实 |
|---|---|---|---|
| **P4a** 一次挂 18 个 | **通过** | `c4/c4_a1_attach_18.response.json` sha `c180c23fdd6dde3c16cc8d9b141b428aa90e390580cbb6745a0e83bd670fc699` | `实测`：`count=18 attached=18 skipped=0 errors=0`，`attached[].attached` 全 `true` |
| **P4b** 另一个工具读回证明「树上真的有脚本」 | **不通过（证据不可归因）** | `c4/main.tscn.before_attach` 与 `c4/main.tscn.after_attach` **sha 相同**：`a423d468713a4824d1034177f26e8e48fd7a51a23bf47084517088e0172ae183`；`c4/main.tscn.after_skip` 同 sha；`c4/c4_a3_read_scene_file.response.json` sha `5bedff3c9bc890f2d99d140971478a4e9f886353dd3d401d47a25f8bb59299d2`；`c4/p4_report.txt` sha `72b663ed99600b4e4ee9810de3cbecc54b68975eba72de84cf223210d3bdb2ce` | `实测`：`before_attach` **本来就已含 18 行 `script = ExtResource("1_t6lrv")`**（逐节点核对 18/18），且 `a1` 自己对每个节点都回 `previous_script_path="res://scripts/Brick.cs"` → **这 18 条脚本赋值先于被测调用存在**，读回**不能**归因给 `a1`。另外方案 P4b 的字面要求（「`Brick.cs` 出现 ≥18 次」）在 Godot 的 `.tscn` 格式下**不可达**：脚本以 **1 条 `[ext_resource]` + 18 处 `ExtResource("1_t6lrv")`** 表示，`p4_report.txt` 自己也记了 `scene text mentions Brick.cs 1 times` |
| **P4c** `keep_existing` 是**跳过**不是**覆盖** | **通过** | `c4/c4_a4_keep_existing.response.json` sha `64406a67357220457bd8e41c9ead1a325d419622dc27408bae4aa2a3456da7b3` | `实测`：`count=0 attached=0 skipped=18 errors=0`；每项带 `reason="the node already carries a script and 'keep_existing' is true"` 与 `previous_script_path="res://scripts/Brick.cs"` |
| **P4d** 跳过不动盘（存盘前后 sha 相同） | **不通过（退化对照）** | 5 份 `c4/main.tscn.*` 快照 sha **全部**是 `a423d468…`（`before_attach`/`after_attach`/`before_all_or_nothing`/`after_skip`/`after_all_or_nothing`） | `实测`：对照物在**任何**操作前就已相同 → 该判据**没有判别力**（它无法区分「真的没写盘」与「写了但字节相同」） |
| **P4e** 全或无（含不存在节点 → 回滚） | **通过** | `c4/c4_a6_all_or_nothing.response.json` sha `057b9baf3254803e8955ac140a8d7df0a0067bdb31bb3dcd372aacb5502a67e8` | `实测`：`-32001`，`data.batch{status:"rolled_back", rolled_back:true, on_error:"all_or_nothing", count:0, errors:[{index:1, node_path:"Bricks/Nope", …}]}`；调用后读回 **`Ball.cs` 出现 0 次**——这一条**有**判别力（`Ball.cs` 本来不在场景里） |
| **P4f** 引擎拒绝被读回拦下（抽象脚本 → `-32000`） | **未构造** | 无 `abstract.gd`、无对应响应 | `实测`：证据目录里不存在该探针 |
| **P4g** 参数面（7 个形状） | **通过** | `c4/c4_g1_missing_script_path.response.json` sha `dd8c7b8133bb431141e168399d7a119f92234f85abff9189d473b99673f33f62`、`c4_g4_keep_existing_string` sha `3efb89167a8028665c7a966452fd6419bf06124aec575acec23d713e12056732`、`c4_g5_user_scheme` sha `765f80090cffb787ea0002e8478a8d4ef49ba10018dae39d9e83d83ca5d9beb8`、`c4_g6_unknown_param` sha `b5292b3283fa318792bacb857f70005cd36c3e734c5ee9271a6afd5a35a4cd69`、`c4_g7_script_missing` sha `be3be55bedea733d9b98da411714c6e15c2b5cdf5bd56ae2780703546eafe9e8` | `实测`：缺 `script_path`→`-32602`；`node_paths:[]`→`-32602`；`node_paths:"X"`→`-32602`；`keep_existing:"yes"`→`-32602`；`user://x.gd`→`-32602`+`suggestion`；未知参数→`-32602`；脚本不存在→`-32001` |
| **P4h** scope 隔离（9889 → `-32601`） | **通过** | `c4/c4_h1_game_endpoint.response.json` sha `252e312377d7742503bdfde4f294b598b021ad5231f590e23509fc2026e869fd`；`c4/game_tools_list.response.json` sha `c37335a1db9c26b610608be1022dc53c16ed0e26fd9d1df51337aca55e479c84` | `实测`：9889 的 `tools/list` 共 **72** 条、`editor_*` **0** 条、`running_game_*` **23** 条；在该端点调 `editor_set_node_script_batch` → `-32601 Method not found` |

### 1.6 ⑤ `scope` 收窄 —— **不通过（不可构造）**

| 项 | 结论 | 证据 |
|---|---|---|
| 是否调用过 `editor_list_signal_connections` | **从未**（去重后 **0** 次） | `trace-recovered/TRACE-FRICTION-ANALYSIS.json` 的 `calls_by_tool` **无该键**；`trace-recovered/TRACE-RECOVERY-SUMMARY.json` 的 `calls_to_editor_list_signal_connections` 为 `[]` |
| 名字在追踪里出现 6 次是调用吗 | **不是** | 那 6 次全部出现在**被写入的 `SignalRegistry.cs` 源码字符串里**（注释里提到本工具名），见 `trace-editor-headless.jsonl.prev-063059` 第 56/64 行、`prev-063121:12`、`prev-063132:6`、`prev-065345:13`、`prev-065408:7` —— **这是 §7.4 明令禁止的「用文本包含判断工具在线」的同一类陷阱** |
| 是否有 `c5/` 证据目录 | **没有** | `evidence/task060/` 只有 `c1`–`c4` |
| §B 是否声称做了 | **没有**：`BREAKOUT-DEV-LOG.md` §4.5 至今是「（本节在 §4.7 汇总时填入…）」，§4.7 也未回填 | `docs/reports/BREAKOUT-DEV-LOG.md`（前插状态声明之后） |
| 不可构造声明是否附失败证据 | **不适用**：方案要求的构造手段**一次都没试**（连 `mcp060_c5_signals.ps1` 都只是写好没跑） | `trace-recovered/scripts/mcp060_c5_signals.ps1` 与 `mcp060_c6_capture.ps1` **存在**（说明脚本写好了），但 `trace-recovered/out/` 里只有 `bootstrap` / `c2` / `c3`+`c3b..e` / `c4`+`c4b,c` 的 `.out.txt`——**没有 `c1.out.txt`、没有 `c5.out.txt`、没有 `c6.out.txt`** |

**⑤ 判为不通过（不可构造）**。按 §A 的规则，「不可构造」必须逐条列出试过的手段——本轮**没有试过**，
所以严格说这是**「未执行」**而非「不可构造」；两者都不能算通过。

### 1.7 ⑥ 捕获 `changed:false` —— **不通过（不可构造）**

| 项 | 结论 | 证据 |
|---|---|---|
| 是否有 `changed:true` 或 `changed:false` | **一条都没有** | 307 行捕获行 `changed` 全为 `null`；`changed_pixel_ratio` 全为 `null` | 
| 捕获状态分布 | **307/307 `status:"unavailable"`** | `TRACE-FRICTION-ANALYSIS.json` `capture_status_counts` / `capture_changed_counts` |
| 为什么全是 `unavailable` | **全程 headless**：`reason="headless display server 没有纹理存储"`；只存在 `trace-editor-headless.jsonl`，**没有任何窗口化编辑器的追踪** | `trace-recovered/trace-editor-headless.jsonl` 第 3 行（捕获 schema 全字段可见）sha `1951fa707d9a1a3f0415b92d05b1269092cd2bc81b0e080426a6315972264ee1` |
| 关键截图是否落盘 | **没有**：`shots-headless/` 目录存在但**为空** | `%TEMP%\mcp-breakout\shots-headless` 枚举结果为空（TASK-062 现场核对） |
| 游戏端有没有捕获 | **没有**：游戏进程的 `--mcp-capture` 是 **off** | `trace-recovered/logs/game.out.log` sha `0cbaab94aea0dd364c99ff154b3431fd61cfd406fb0f01e2357c5b9126d59762` 里 `[MCP] capture=off (default; …)`；`trace-game.jsonl` 捕获行 = 0 |
| 观测到的唯一相关事实 | **headless 边界（方案的 P6g）成立**：`status:"unavailable"` + 非空 `reason` + `before/after/changed` 为 `null` + `scale:2` 在场 | 同上追踪行 |
| 能否据此判 ⑥ 通过 | **不能**。§A 明写：「（headless 边界）这一条是**独立**判据，**不得用 headless 的结果冒充 ⑥ 的通过**」；P6a（对照组 `changed:true`）、P6b（F1 幂等 `changed:false`）、P6c（`seq` 归属）、P6d（前后图落盘 + 第二意见）**全部未构造** | `docs/reports/BREAKOUT-TEST-PLAN.md` §2⑥ |

---

## 2. 四张表

> 排序：**证据强度 × 影响面**。每条都标了「建议做 / 不建议做」。
> 强度：**强** = 有落盘的响应/追踪原文 + sha256 + 可复算；**中** = 有原文但样本少或需推断；**弱** = 仅间接信号。

### 2.1 异常 / 矛盾（7 条）

| # | 现象 | 证据 | 强度 | 影响面 | 处置 |
|---|---|---|---|---|---|
| **A-1** | **观察在开发开始前 26 分钟就结束、在开发结束前 2 小时结束**：观察窗口 05:34:40–06:00:25；§B 首次调用 06:26:28；开发最后证据 08:01:15 | `c-obs/watch.log` sha `a584bc61…`（末行 `BUDGET_REACHED`）；`c1/c1_g1_remove_autoload.response.json` mtime 06:26:28；`c4/` 最后 mtime 08:01:15 | 强 | 大（本轮观察侧结论全部失效） | **建议做**：改用 TASK-061 的 `mcp_watch_run.ps1` + `stop_reason` + 开发者心跳 |
| **A-2** | **错误响应占 1/3 强**：309 次调用里 `-32602`×77、`-32001`×22、`-32000`×7、`-32601`×3（共 109，35.3%） | `TRACE-FRICTION-ANALYSIS.json` `calls_by_error_code` | 强 | 中 | **建议做**（但**必须扣除刻意的负例探针**：`c4_g1..g7` 被重复 3 轮 ≈21 次、`editor_execute_gdscript` 的 8 个语法探针等——所以这不是「35% 失败率」） |
| **A-3** | **同一工具的同一个逻辑操作反复失败**：`editor_set_node_script_batch` 被调 39 次；同代内 `seq44,45,46,47,48` 连续 5 次失败后 `seq56` 才成功；`seq66,69,70,71,72,73,74,75,76` 连续 9 次失败后 `seq77` 才成功 | `TRACE-FRICTION-ANALYSIS.json` `friction_fail_then_success`（pid=57904）；`trace-editor-headless.jsonl.prev-062549`/`prev-073236` 对应行 | 强 | 中 | **建议做**：把「可接受的 `node_paths` 拼写」写进 description（见 O-2/O-3） |
| **A-4** | **单数/批量两个同义工具并存**：`project_validate_scripts`（23）与 `project_validate_script`（11）交替出现，bigram `project_validate_scripts/project_validate_script` 命中 11 次 | `TRACE-FRICTION-ANALYSIS.json` `repeated_bigrams_trigrams` | 中 | 小 | **不建议做**：两者语义**不同且都必要**（批量给五分类 + `count`；单数给 `-32000` + `not_compiled ≠ invalid` 的建议），合并会破坏 `P2f` 已冻结的语义 |
| **A-5** | **游戏端点静默失能**：`[MCP] bind failed on 127.0.0.1:9889 (error=22)` → `get_port()=0 (MCP server disabled)`，同时**同一追踪文件里前一代游戏进程还在正常应答 `tools/list`** | `trace-recovered/logs/game.out.log` sha `0cbaab94…`、`game.err.log` sha `b3c95a3b3f1d75866fcaa6faa188843734909381dc350a412094e08d9fa9d566`、`trace-game.jsonl` sha `732c49aefd7b13d6a4a8b870611b3ff308cdd911ce99ddbbf0b3137d72443b09` | 强 | 大（游戏侧验收被阻断且不易察觉） | **建议做**：起游戏端前先确认端口空闲；调用方应校验子进程真的绑上了（见 M-5） |
| **A-6** | **承诺的证据文件不存在**：`BREAKOUT-DEV-LOG.md` §2 写「仓库内副本 `docs/reports/evidence/task060/DEV-LOG-raw-run.log`」，回收前**仓库里没有** | TASK-062 已从 `%TEMP%\mcp-breakout\run.log` 补入，sha `e8ac551b8c4e7ba138e745f16b99a356441ea6298a9c207ebce026ce84c66356` | 强 | 小 | **已修**（TASK-062 回收） |
| **A-7** | **本轮完全没做游戏侧活证据链**：`running_game_*` 调用去重后只有 1 次，且是观察者在 **9888** 上的 `-32601` 探针 → §B「自验四条」的 ②（注入输入→另一工具读回位置变化）与 ③（砖块消失/计分变化）**零证据** | `TRACE-FRICTION-ANALYSIS.json` `calls_by_tool`；`c-obs/obs-runninggame-at-9888.resp.json` sha `7a89ea34…` | 强 | 大 | **建议做**：补做（这是 TASK-060 §B 的硬性自验条款） |

### 2.2 缺失工具线索（5 条）

| # | 想要什么 | 试过什么 / 为什么不行 | 证据 | 强度 | 影响面 | 处置 |
|---|---|---|---|---|---|---|
| **M-1** | **一次按节点路径列表写不同值** | `editor_set_node_property_batch` 只接受 `node_type, property, value`（按类型写同一个值）；按 `updates` 传 → `-32602 Unknown parameter 'updates'` | `c3/c3_a5_batch_positions.response.json` sha `6d0daa365380aad6991ceea760cc92c8a46261d3b9aac898f29997988bdd6085`（`-32602`）；`c3/c3_a5b_batch_property_by_type.response.json` sha `46ba525e332651032d837503f0b03e80ed32ec46d176b8291bdfe53c19603168`（`node_type:"StaticBody2D"`, `updated:21`） | 强 | 中 | **建议做**（20 次单点写 → 1 次；见 C-3） |
| **M-2** | **写设置后读回「引擎真的认了」** | `project_set_setting{key:"input/<action>"}` 回 `saved:true`，但同一编辑器的活 InputMap **不含**该 action；只有 `editor_add_input_action` 更新内存 | `c1/c1_a6_get_input_actions.response.json` sha `1a5da0e4…`（`actions` 里无 `mcp060_probe_action`） | 强 | 中 | **建议做**：工具应回「本进程是否已生效」，或描述里点明需重载 |
| **M-3** | **诊断 `dotnet/project/assembly_name` 与 `.csproj` 名不一致** | `project_build_csharp` 成功、`project_validate_scripts` 全 `not_compiled`；唯一线索在编辑器 stderr。**注意**：DEV-LOG 引用的 `logs/editor-headless.err.log` 在回收集里是 **0 字节**，「Failed to load project assembly」只出现在**开发者自己写的脚本注释**里 | `c2/c2c_set_assembly_name.response.json`（`{"key":"dotnet/project/assembly_name", …, "value":"Mcp060Breakout"}`）；`trace-recovered/logs/editor-headless.err.log` sha `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`（空文件）；`trace-recovered/scripts/mcp060_c2c_set_assembly_name.ps1:11` | 中 | 中 | **建议做**（自纠性，major 级体验问题） |
| **M-4** | **在 9888 上判断某 `editor_*` 工具是否在游戏端可见** | 只能靠实际调用拿 `-32601`；`tools/list` 需要调用方自己解析 `name` 集合 | `c4/c4_h1_game_endpoint.response.json` sha `252e3123…`；`c4/game_tools_list.response.json` sha `c37335a1…` | 弱 | 小 | **不建议做**（现状已够用，且 §7.4 明令禁止文本包含判断，解析 `name` 是正确做法） |
| **M-5** | **确认 `editor_play_scene` 起的子进程真的绑上了 MCP 端口** | `editor_play_scene` 的响应已回 `mcp_port`/`pid`，但没有「子进程是否绑定成功」的信号；本轮实测曾发生 `bind failed` + `get_port()=0` | `trace-recovered/logs/game.out.log` sha `0cbaab94…`；`c4/p4_report.txt` 的 `h0 game endpoint on 9889 ready=True pid=78764`（与追踪里的游戏 pid **87908/37080 都不同**） | 中 | 中 | **建议做** |

### 2.3 可合并候选（5 条）

| # | 高频序列 | 次数 | 引擎依据（一次调用本可以做到） | 证据 | 强度 | 影响面 | 处置 |
|---|---|---|---|---|---|---|---|
| **C-1** | `editor_add_nodes_batch` → `editor_get_scene_tree` | 16 | `Node` 的创建返回值里已有 `node_path`（`c3_a1` 的每个 `created[]` 都带）；读回树只是复核 | `TRACE-FRICTION-ANALYSIS.json` `repeated_bigrams_trigrams`；`c3/c3_a1_batch_27.response.json` sha `c841696c…` | 强 | 中 | **建议做**：加 `verify:true` 让 batch 自己回读（保持全或无 + 第 i 项定位） |
| **C-2** | `editor_save_scene` → `project_read_scene_file_content` | 12 | 存盘与读盘是同一次落盘的两位观察；可在 save 响应里回 `sha256` + 脚本计数 | 同上；`c3/c3_a4_read_scene_file.response.json` sha `aa507dd2d0df6441c6e247625a48b3cab2201650a4581c39197b8a3835250fd9` | 强 | 小 | **建议做** |
| **C-3** | `editor_set_node_property` × 3（bigram 命中 57 次、trigram 54 次） | 57 | 18 砖 + 挡板 + 球的位置是 20 次**同一个工具**的单点写 | 同上；`c3/c3_a6_setpos_brick_01..18.*` | 强 | 中 | **建议做**（与 M-1 同一项） |
| **C-4** | `project_set_setting` → `project_get_settings` | 5 | `project_set_setting` 响应只回 `created/existed_before/key/saved/type/value`，回读旧值可省掉一次读 | `TRACE-FRICTION-ANALYSIS.json`；`c2/c2c_get_setting.response.json` | 中 | 小 | **建议做** |
| **C-5** | `project_validate_scripts` ↔ `project_validate_script` | 11 | 见 A-4 | 同上 | 中 | 小 | **不建议做** |

### 2.4 可优化项（6 条）

| # | 项 | 证据 | 强度 | 影响面 | 处置 |
|---|---|---|---|---|---|
| **O-1** | **`editor_execute_gdscript` 的 parse 错误不带行/列**：只有 `Parameter 'code' does not compile: Parse error`。26 次调用、7 对「失败→成功」，其中 pid=74412 有 `seq35,36,37→38` 与 `seq46→47`、`seq51,52→53` 三簇 | `c2/c2_probe_engine_cs_state.response.json` sha `1a58c7d3353c0b0e9ebd77fa348c5fe399dc4f7688996b31dd846dcafd9675d9`；`TRACE-FRICTION-ANALYSIS.json` | 强 | 中 | **建议做**：GDScript 自己有行号，透传即可 |
| **O-2** | **同族工具的 `node_path` 参数名不一致，且基准未声明**：`editor_set_node_property` / `editor_get_node_properties` 用 **`path`**（单数）；`editor_set_node_script_batch` 用 **`node_paths`**（复数）。三者**都**要求「被编辑场景根的相对路径」，**都**拒绝 `/root/...` 与裸名 | `c3/c3_a5_setpos_Ball.response.json`（`-32602 Unknown parameter 'node_path'`，suggestion 列 `path, property, value`）；`c3/c3_a5_setpos_Main_Ball.response.json`（`path:"Main/Ball"` → ok）；`c4/c4_s1_root_absolute.response.json` sha `d3becff087f5ad38d1b885aa73db33f30a58857dc5fd9647016aa0f2034877c0`（`/root/...` → **-32001**）、`c4_s2_scene_relative` sha `ab3241db2ed4fb7be9f59981ca3fd2dcbe3d4b66ea63f6f978031324a17c9c2c`（`Bricks/…`→ok）、`c4_s5_bare_name` sha `826dad7b3e8d6897ff3150e985ef23591ac21b7c0fed86a452a51095078a111e`（裸名→**-32001**）；`c4/c4_dbg_probe__root_Main.response.json` sha `606642faff6b2139757b6c68ec5895fad07d19e3424352d1d8161775fa0a1c5f`（`-32001`）vs `c4/c4_dbg_probe_Main.response.json` sha `4e8ac5024b2d04f55186e903598cec21b8d02f6ac5c5381b17cafc6df934237d`（ok） | 强 | 中 | **建议做**：统一参数名 + 在 description 里写死「相对被编辑场景根，接受 `X`/`./X`，拒绝 `/root/...` 与裸名」 |
| **O-3** | **`-32001 Node '…' not found` 不提示期望拼写**（只说 `Use editor_get_scene_tree to list the nodes of the edited scene`） | `c4/c4_dbg_probe__root_Main.response.json`（sha 见 O-2）、`c4/c4_s1_root_absolute.response.json`（sha 见 O-2） | 强 | 小 | **建议做** |
| **O-4** | `project_set_setting` 的 `Dictionary` 值经引擎序列化后**浮点化**（`74` → `"keycode": 74.0`） | `c1/p1g_after_remove_autoload.txt` sha `7b95fdd4…`；`c1/p1_report.txt` sha `be059697…` | 强 | trivial | **不建议做**：这是引擎的序列化行为，不是本模块的收窄（§A §2① 的「不是缺陷」清单已列） |
| **O-5** | **headless 下每条调用都产生一条无信息的捕获行**：307 条捕获行 = 追踪体积的约一半，且全是 `unavailable`，对 `analyze_mcp_trace.py` 的 n-gram / 大响应统计是噪声 | `TRACE-FRICTION-ANALYSIS.json` `capture_status_counts`；`trace-recovered/trace-editor-headless.jsonl` sha `1951fa70…` | 强 | 小 | **建议做**：headless 时只写一次 `unavailable` 或改为 `--mcp-capture` 的可选行为 |
| **O-6** | `project_write_text_file` **拒绝** `.cs` 并给出替代工具 —— 这是**正面**行为（一次自纠，§B 只失败 1 次就换路） | `c2/c2_w1_write_broken.response.json` sha `1d8810e08af95f8c57c226dc5947222be5c7bf619c1da5b935ec01610f4536ff`；`c2/c2_w0_write_text_file_broken_refused.response.json` 同 sha | 强 | — | **不建议改**（列为「不要动」的正面样本） |

---

## 3. 疑似缺陷（单列）

> 每条给：**最小复现** / **期望** / **实际** / **证据 sha256** / **严重度**。
> 类别标 `[产品]`（模块实现）或 `[试测产物/流程]`（本轮试测本身的问题——它们**同样要修**，否则下一轮还会错）。

### D-1 `[试测产物]` 判据 P1c 自相矛盾（无解判据）· minor
- **最小复现**：按 `BREAKOUT-TEST-PLAN.md` §2① 的 STEP 1–3 执行（手写带 4 行注释的 `project.godot`，
  再依次写 `input/mcp060_probe_action`、`editor_add_input_action`、`physics/common/physics_ticks_per_second`），
  然后按 P1c 断言「`[input]` 之外的全部字节完全相同」。
- **期望**：判据可按字面判真。
- **实际**：STEP 3 写的是**另一个节的键** → 引擎必然**追加 `[physics]` 节（46 B）**，`[rendering]` 还多一个尾随换行
  （177→178 B）→ **在该判据的口径下不可能为真**。可用的是它的**分部**版本：`[application]` 82→82 B 逐字节相同。
- **证据**：`c1/p1c_section_split.txt` sha `188c636e312e820300490df5bb9e675bf04b6e7da43f1b3d87c19a0026992e6`；`c1/p1_report.txt` sha `be0596976616427c04675160d6e896b81576d2abf91bd204bf95322f18f48ca2`
- **修复**：把 P1c 改成「**既有**节的字节不变（容许多出一个尾随换行）+ 新增节只含本次写的键」。

### D-2 `[试测产物]` 判据 P1f 的断言与其引用的证据相反 · **major**
- **最小复现**：读 `c1/p1_report.txt` 的最后 4 行，与它自己标注的 `a6 … sha256=1a5da0e4…` 指向的响应文件逐字比对。
- **期望**：`InputMap has mcp060_probe_action : True`。
- **实际**：该响应的 `actions` 列表里**没有** `mcp060_probe_action`（有的是 `mcp060_probe_action2`、
  `mcp060_probe_probe_key`、`ui_left`）。报告与证据**直接矛盾**，而 ① 的结论被写成了「通过」。
- **证据**：`c1/c1_a6_get_input_actions.response.json` sha `1a5da0e49d60165c6895b01181272cbfa8fb2642c526e60f8a1f6d11432d1388`；
  `c1/p1_report.txt` sha `be059697…`
- **修复**：P1f 必须用**另起的** headless 进程问 `InputMap`（方案原本就是这么写的），
  或把判据改成「`editor_add_input_action` 之后本进程 InputMap 立即生效」——本轮两者都没做对。

### D-3 `[试测产物]` `BREAKOUT-DEV-LOG.md` §3-F4 / §6-D-1 的根因与错误码都写错了 · **major**
- **最小复现**：读 `c3/c3_a5_setpos_Ball.request.json` / `.response.json`。
- **期望**（按 DEV-LOG 的叙述）：用 `/root/Main/Ball` 得到 **`-32001 Node '/root/Main/Ball' not found`**（20/20 全失败），
  且「`editor_set_node_script_batch` 认 `/root/...` 而 `editor_set_node_property` 不认」→ 两条工具的路径基准不一致。
- **实际**：失败请求用的是参数名 **`node_path`**，而 `editor_set_node_property` 只接受 **`path`**
  → 得到的是 **`-32602 Unknown parameter 'node_path'`**，与路径拼写**无关**。
  并且 `editor_set_node_script_batch` **也拒绝** `/root/...`（`c4_s1` → `-32001`）→ **两个工具的路径基准是一致的**，
  DEV-LOG 报的 D-1 缺陷**不成立**；真正的问题是**参数名不统一 + 基准未写进描述**（见 D-5）。
- **证据**：`c3/c3_a5_setpos_Ball.response.json`（`-32602`）、`c3/c3_a5_setpos_Main_Ball.response.json`（`path:"Main/Ball"`→ok）、
  `c4/c4_s1_root_absolute.response.json` sha `d3becff087f5ad38d1b885aa73db33f30a58857dc5fd9647016aa0f2034877c0`
- **修复**：撤回 `BREAKOUT-DEV-LOG.md` 的 D-1 结论（append-only 勘误），改列为「参数名不统一」。

### D-4 `[试测产物]` 证据文件被同名覆盖，导致构建表无法对账 · **major**
- **最小复现**：`grep project_build_csharp DEV-LOG-raw-run.log`。
- **期望**：`BREAKOUT-DEV-LOG.md` §4.2 的 5 行构建表每行都能找到对应响应文件。
- **实际**：表里「第 1 次（首次，exit 1），sha `fb8d88641c70…`」的响应**不在仓库**；
  磁盘上 `c2/c2_b0_build.response.json` 的 sha 是 `27ddf120a68c7b29…`（= 表里「第 2 次、修好后」）。
  根因（实测）：**同一个 id `c2_b0_build` 被复用 4 次**（06:27:35 / 06:28:15 / 06:30:54 / 06:52:44），
  后写覆盖前写；`c2_b1_build_broken` 被复用 3 次。全量核对：`run.log` 与磁盘可比的 200 条里
  **163 条一致、37 条不一致**，不一致全部落在被复用的 id 上。
- **证据**：`DEV-LOG-raw-run.log` sha `e8ac551b8c4e7ba138e745f16b99a356441ea6298a9c207ebce026ce84c66356`（第 75/80/… 行）；
  `c2/c2_b0_build.response.json` sha `27ddf120a68c7b294cbc99677127a900b24052e3876943b0faeb1b27a29eb844`；
  复算见 `REPORT-062-breakout-recovery.md` §4。
- **修复**：证据文件名必须**唯一**（带 run 序号或时间戳）；或每轮清空证据目录并在 run.log 里固定 id↔文件映射。

### D-5 `[产品]` `node_path` 参数面：命名不统一 + 基准未声明 + 拒绝消息不指路 · minor–major
- **最小复现**：`editor_set_node_property{node_path:"/root/Main/Ball", property:"position", value:{x:576,y:320}}`
  → `-32602 Unknown parameter 'node_path'`；`editor_set_node_script_batch{node_paths:["/root/Main/Bricks/Brick_r0_c0"], script_path:"res://scripts/Brick.cs"}`
  → `-32001 Node '/root/Main/Bricks/Brick_r0_c0' is not in the edited scene`。
- **期望**：同族工具的参数名一致；描述里写明接受的拼写族；拒绝消息指出期望形态。
- **实际**：`path`（单数，属 `editor_set_node_property`/`editor_get_node_properties`）vs `node_paths`（复数，属 `editor_set_node_script_batch`）；
  两者都**只**接受场景根相对路径；`-32001` 的 `suggestion` 只说「用 `editor_get_scene_tree` 列节点」。
- **证据**：`c3/c3_a5_setpos_Ball.response.json`、`c4/c4_s1_root_absolute.response.json` sha `d3becff0…`、
  `c4/c4_dbg_probe__root_Main.response.json` sha `606642faff6b2139757b6c68ec5895fad07d19e3424352d1d8161775fa0a1c5f`
- **严重度**：minor–major（20 次调用全废 + 39 次同工具反复试探，A-3）

### D-6 `[产品]` `editor_set_node_property_batch` 无法按路径列表批量写不同值（能力缺口）· minor
- **最小复现**：`editor_set_node_property_batch{updates:[…]}` → `-32602 Unknown parameter 'updates'`。
- **期望**：一次调用写完 20 个几何值。
- **实际**：工具只按 `node_type` 写**同一个值**；几何只能 20 次单点写（`editor_set_node_property` 去重后调 60 次）。
- **证据**：`c3/c3_a5_batch_positions.response.json` sha `6d0daa365380aad6991ceea760cc92c8a46261d3b9aac898f29997988bdd6085`；
  `c3/c3_a5b_batch_property_by_type.response.json` sha `46ba525e332651032d837503f0b03e80ed32ec46d176b8291bdfe53c19603168`
- **注**：这**不是**契约错（契约写的是「批量设置同类型节点的属性」）——是**能力缺口**。

### D-7 `[产品/环境]` 游戏端点静默失能，调用方可能把「没绑上」误读成「端点隔离」· **major**
- **最小复现**：在上一个游戏进程仍占着 9889 时启动新的游戏端（编辑器 `editor_play_scene`）。
- **期望**：子进程绑定失败能被调用方感知（工具响应或明确错误）。
- **实际**：模块只往 stdout 打 `[MCP] bind failed on 127.0.0.1:9889 (error=22)` 与
  `[MCP] get_port()=0 (MCP server disabled)`，stderr 一条 `WARNING`；MCP 响应里没有任何迹象。
  本轮 `c4/p4_report.txt` 的 `h0 game endpoint on 9889 ready=True pid=78764` 用的是**第三个**游戏 pid，
  与追踪里的 87908/37080 都不同 → 说明当时「以为在用的游戏端」和「实际绑上的游戏端」可能不是同一个。
- **证据**：`trace-recovered/logs/game.out.log` sha `0cbaab94aea0dd364c99ff154b3431fd61cfd406fb0f01e2357c5b9126d59762`；
  `trace-recovered/logs/game.err.log` sha `b3c95a3b3f1d75866fcaa6faa188843734909381dc350a412094e08d9fa9d566`；
  `trace-recovered/trace-game.jsonl` sha `732c49aefd7b13d6a4a8b870611b3ff308cdd911ce99ddbbf0b3137d72443b09`

### D-8 `[试测产物/流程]` 观察环节不合格：旧协议 + 未等到开发结束 + 机器可读字段不全 · **major**
- **最小复现**：读 `c-obs/watch.log` 末行与 `c-obs/watch.ps1`。
- **期望**（TASK-061 起）：`stop_reason ∈ {marker,timeout,stale}` + `polls`/`elapsed_sec`/`last_seq`/`trace_lines`
  + `watch-summary.json`，且观察者预算（4500 s）严格大于开发者（2700 s）。
- **实际**：自建 watchdog、预算 1500 s、以 `BUDGET_REACHED` 收口、**无** `watch-summary.json`；
  观察在**开发开始调用工具之前 26 分钟**就结束，离开发结束约 2 小时；
  §C 的结论「§B 零工具调用」被写成了整轮结论。
- **证据**：`c-obs/watch.log` sha `a584bc61dcfcc1a2e852048dbd5cc6b9b482d470d1bb1bf6415f21e9f60a0cf2`；
  `c-obs/watch.ps1` sha `a18e9c052d087ec2544c3dff4794261c505bf89573c918e35d44b667cbc84d8c`；
  `c1/c1_g1_remove_autoload.response.json`（mtime 06:26:28）

### D-9 `[试测产物]` P4d 是退化对照（无法区分「没写盘」与「写了但字节相同」）· minor–major
- **最小复现**：比对 `c4/main.tscn.before_attach` 与 `c4/main.tscn.after_attach`。
- **期望**：对照物在**被测调用之前**是「场景里没有该脚本」的状态。
- **实际**：`before_attach` **已含 18 行 `script = ExtResource("1_t6lrv")`**，且 `a1` 自己对 18 个节点都回
  `previous_script_path="res://scripts/Brick.cs"` → 5 份快照 sha **全部**是
  `a423d468713a4824d1034177f26e8e48fd7a51a23bf47084517088e0172ae183`，判据失去判别力。
- **证据**：`c4/main.tscn.before_attach`/`after_attach`/`after_skip`/`before_all_or_nothing`/`after_all_or_nothing`（同一 sha）；
  `c4/c4_a1_attach_18.response.json` sha `c180c23fdd6dde3c16cc8d9b141b428aa90e390580cbb6745a0e83bd670fc699`
- **修复**：先在**新的**场景上验证「无脚本」基线，再做 attach/skip 对照。

### D-10 `[产品]` `editor_execute_gdscript` 的 parse 错误不带行列 · minor
- **最小复现**：`editor_execute_gdscript{code:"return 1 +"}` → `-32602 Parameter 'code' does not compile: Parse error`。
- **期望**：给出出错行号。
- **实际**：只有 `Parse error`；开发者只能靠 8 个最小 body 逐个试出「必须显式 `return`」这一条语义。
- **证据**：`c2/c2_probe_engine_cs_state.response.json` sha `1a58c7d3353c0b0e9ebd77fa348c5fe399dc4f7688996b31dd846dcafd9675d9`；
  `probe-gdscript/pgd_*`（8 个探针）

---

## 4. 纠错清单（对 §A / §B / §C 的 append-only 勘误）

> 方式：**不改**三份产物正文（TASK-062 只在其头部前插了状态声明），把纠正记在这里。

| # | 出处 | 原叙述 | 原文证据 | 纠正 |
|---|---|---|---|---|
| R-1 | `BREAKOUT-TEST-PLAN.md` §2③ | 「一次建出**全部 27 个**节点」 | `c3/c3_a1_batch_27.response.json`：`count=26` | 方案自己列的清单是 1+1+3+1+1+1+18=**26**，**方案多算 1**（`实测`） |
| R-2 | `BREAKOUT-TEST-PLAN.md` §2③/§2④ 的示例 | 示例里用 `/root/Main/Bricks/Brick_r0_c0` | `c4/c4_s1_root_absolute.response.json` → `-32001 not in the edited scene` | **该示例拼写会被工具拒绝**；正确的是 `Bricks/…` 或 `Main/…` 或 `./Bricks/…`（`实测`） |
| R-3 | `BREAKOUT-TEST-PLAN.md` §2④ P4b | 「`Brick.cs` 出现 **≥18** 次」 | `.tscn` 用 1 条 `[ext_resource]` + 18 处 `ExtResource("1_t6lrv")` | 该字面判据在 Godot 格式下**不可达**；`p4_report.txt` 自己也记了 `mentions Brick.cs 1 times` |
| R-4 | `BREAKOUT-DEV-LOG.md` §4.1 P1f | `InputMap has mcp060_probe_action : True` | `c1/c1_a6_get_input_actions.response.json` 的 `actions` 无该项 | **与证据相反**（见 D-2） |
| R-5 | `BREAKOUT-DEV-LOG.md` §3-F4、§6-D-1 | `/root/Main/Ball` → `-32001 Node not found`，两工具路径基准不一致 | `c3/c3_a5_setpos_Ball.response.json` → `-32602 Unknown parameter 'node_path'`；`c4_s1` → 该工具**同样**拒绝 `/root/...` | **错误码与根因都错**（见 D-3）；**两个工具的基准是一致的** |
| R-6 | `BREAKOUT-DEV-LOG.md` §4.2 构建表第 1 行 | 「首次，exit 1，sha `fb8d88641c70…`」 | 该 sha 只出现在 `DEV-LOG-raw-run.log:75`，**无对应响应文件** | 证据被同名覆盖（见 D-4）；表与磁盘不是同一轮 |
| R-7 | `BREAKOUT-DEV-LOG.md` §6-D-5 | 「`logs/editor-headless.err.log`（`.NET: Failed to load project assembly`）」 | 回收的 `logs/editor-headless.err.log` = **0 字节**；该字符串只出现在 `scripts/mcp060_c2c_set_assembly_name.ps1:11` 的**注释**里 | 该证据**未入库**；现象本身（`not_compiled` 全灭 + assembly_name 修复后 `ok`）**有**证据支持，但「stderr 原文」这一条**不可核** |
| R-8 | `BREAKOUT-DEV-LOG.md` §2 | 「仓库内副本 `docs/reports/evidence/task060/DEV-LOG-raw-run.log`」 | 回收前该文件不存在 | TASK-062 已补入（sha `e8ac551b…`） |
| R-9 | `BREAKOUT-OBSERVATIONS.md` §5.0 | 「§B 在整整 25 分钟预算内没有向服务端发出任何一条 `tools/call`」 | 观察窗口到 06:00:25；§B 首次调用 06:26:28，末次证据 08:01:15 | 该句**只对 06:00:25 之前成立**；不能读成「本轮 §B 从未调用工具」（`实测`，309 次调用有原文） |
| R-10 | `BREAKOUT-OBSERVATIONS.md` §7 的 sha256 表 | 逐项 sha/字节数 | TASK-062 逐行复核 **13 行**：**11 行完全相符**；2 行不符（`watch.ps1` / `analyze-final.json`）**且原因已知**——它们是 TASK-062 修正路径引用时改动的那两个文件（见 `recovery/PATHFIX-TRANSFORM.tsv`）。另外**全部 127 份 `.response.json.sha256` 边车与自己的文件逐字节相符** | ✅ 除 TASK-062 自身改动外无差错（正面结论） |

---

## 5. 明确写清：**哪些结论受「观察不完整」影响**

**前提（`实测`）**：`stop_reason = BUDGET_REACHED`（**非** `marker`），观察窗口 05:34:40–06:00:25，
开发 06:26:28–08:01:15。⇒ 依 TASK-060 §D 的硬性要求：**本轮观察不完整**。

### 5.1 受影响的结论（**不可作为本轮事实**）

| 结论 | 为什么受影响 |
|---|---|
| §C 的四类计数（「多次调用才摸清用法」=0、「缺失工具线索」=0、「可合并候选」=0、「异常」=2） | 全部基于**观察窗口内**的追踪；窗口内 §B **确实还没开始调用**（首次调用 06:26:28），所以这些 0 是**时间错位**的产物，不是「§B 什么也没做」 |
| §C 的「单工具占比 100%」「无异常大响应」「无超时」 | 分母 = 1（§C 自己的探针），**无统计意义**；用 TASK-062 回收的完整追踪复算后是 309 次调用（`TRACE-FRICTION-ANALYSIS.json`） |
| §C §5.3「拒绝用静态猜测补足可合并候选」 | 结论本身**诚实**，但结论应是「**观察窗口内**无样本」，而不是「本轮无可合并候选」——本轮实际有 5 条（§2.3） |
| `BREAKOUT-OBSERVATIONS.md` 里一切关于「§B 是否调用过 X」的陈述 | 窗口错位 |
| 「观察覆盖了整个开发过程」这类判断 | 明确**不成立** |

### 5.2 **不**受影响的结论（可直接用）

| 结论 | 为什么不受影响 |
|---|---|
| §1 的六条判据结论（①②③④） | 依据是 **c1–c4 的响应原文**，落盘于 06:26–08:01，是**开发侧**的原始证据，与观察者无关 |
| ⑤⑥ 判为「不通过/不可构造」 | 依据是**回收的完整追踪**（309 次调用）与 307 条捕获行，覆盖 05:36–08:01 全程 ⇒ 「0 次调用 `editor_list_signal_connections`」与「0 条 `changed:true/false`」是**全程**结论，不是窗口结论 |
| §2 的四张表 | 依据同为回收的完整追踪 + c1–c4 原文 |
| §3 的疑似缺陷 | 同上 |
| `trace-recovered/**` 里的全部请求/响应/追踪原文 | 是服务端的落盘原文，不经过观察者 |

### 5.3 仍然**无法**由本轮数据回答的问题（真正的空白）

1. ⑤ 的 `scope:"user"` 究竟干净不干净 —— **一次都没调**（不是构造失败，是**没做**）。
2. ⑥ 的 `changed:false` 究竟能不能被正确捕获 —— **没有任何窗口化进程**跑过。
3. 游戏侧活链（输入→位置回读、砖块消失、计分变化）—— `running_game_*` 只有观察者的 1 次 `-32601` 探针。
4. `P4f`（抽象脚本被引擎拒绝）与 `unverifiable`/`language_unavailable` 两个分类 —— 未构造。
5. 打砖块工程本身是否真的"能跑"（胜利/失败/计分）—— 本轮**没有**任何游戏内行为证据。

---

## 6. 最该先做的两条（给决策者）

1. **修编排，让「观察完整」成为机器可判的事实**（对应 A-1 / D-8）：
   观察者一律用 `mcp_watch_run.ps1`（TASK-061 协议）+ 开发者心跳 `PROGRESS.md`，
   `-TimeoutSec` 严格大于开发者预算；产物**必须**写死 `stop_reason`/`polls`/`last_seq`/`trace_lines`
   与**观察窗口的起止时刻**。理由：本轮 4 条判据（⑤⑥ + 游戏侧两条）全部因为「观察/执行没跑到」而无法判定，
   这是**流程缺陷**而不是工具缺陷——它比任何单条工具缺陷都更贵。
2. **让证据不可能"不可归因"**（对应 D-4 / D-9 / D-2）：
   ① 证据文件名**唯一**（带 run 序号），禁止同名覆盖；② 对照物必须在**被测调用之前**采样并落盘；
   ③ 报告里的每一条断言必须**直接引用**其证据文件的 sha256，并由独立复算脚本核一遍
   （本轮的 `recovery/PATHFIX-TRANSFORM.tsv`、`TRACE-FRICTION-ANALYSIS.json` 就是这种脚本的雏形）。

**紧接着的第三条（不算"最该先做"但必须补）**：补做 ⑤ 与 ⑥ 的构造，以及游戏侧活证据链——
它们才是本轮原定的"主验收点"。

---

## 7. 附：本文件用到的机器可读产物

| 文件 | 作用 |
|---|---|
| `evidence/task060/recovery/MOVE-BEFORE.sha256.tsv` / `MOVE-AFTER.sha256.tsv` | 445 个文件的搬前/搬后清单（两份 sha256 相同） |
| `evidence/task060/recovery/PATHFIX-TRANSFORM.tsv` | 6 个被改路径引用的文件：旧/新 sha256、字节数、BOM/CR 状态 |
| `evidence/task060/recovery/ANNOTATION-TRANSFORM.tsv` | 3 个被前插状态声明的文件：旧/新 sha256、字节数、CR 状态 |
| `evidence/task060/trace-recovered/TRACE-RECOVERY-MANIFEST.sha256.tsv` | 回收的 78 个追踪/日志/脚本证据的 sha256 清单 |
| `evidence/task060/trace-recovered/TRACE-RECOVERY-SUMMARY.json` | 每份追踪的行数/坏行/调用数/捕获数 + 分代表 |
| `evidence/task060/trace-recovered/TRACE-FRICTION-ANALYSIS.json` | 去重后的调用总账、错误码分布、捕获状态、失败→成功对、重复 n-gram |
