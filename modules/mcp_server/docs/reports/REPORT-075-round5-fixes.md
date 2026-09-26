# REPORT-075 — 修第 5 轮确认项：**D2 契约违约+静默** / **补读工具** / **D9 计数** / D4·D5 最小复现 / 分析器漏报

- **任务书**：`modules/mcp_server/docs/tasks/TASK-075-round5-fixes.md`（自包含）+ `docs/tasks/PLAYBOOK-group-port.md`（自包含手册）
- **来源**：`docs/reports/PLATFORMER-FINDINGS.md`（D1…D11、§0.6 十一条、§6 两条「最该先做」）
- **契约**：**176 → 177**（= **171 ported + 6 added**；新增 1 个读工具）。`_meta.count=177`、`added_count=6`、`generator_version=1.21.0`
- **构建锚点（D86 ①）**：**`077694816`** —— 单精度二进制自报 `4.8.dev.custom_build.077694816`，与 `git rev-parse --short=9 HEAD` **逐字一致**（`check_engine_anchor.ps1` 判 `ANCHOR_EQUAL`、`diff_count=0`，`docs/reports/evidence/task075/gate_engine_anchor.txt` 第一条记录）。**门①/③/④ 在最终二进制上采集**；门②（live after，26/26）采集于 `35ae10422` 的二进制，门⑤ `accept_m1`×2、门⑥、D4 探针、分析器对照采集于 `cdd125493` 的二进制 —— 这三次提交之间**只有 `docs/reports/evidence/**` 与报告**（无任何编译输入、无任何 `modules/mcp_server/{tools,tests,*.cpp,SCsub,config.py}` 改动，`SCsub`/`SConstruct` 也从不引用 `docs/` 下的任何文件），下面每一处都标注了它采自哪一次构建。live 证据之所以不重跑第三次，是因为它每次都在证据树里重建 `proj/`（`project.godot`、`*.tscn`），一次重跑就会让「被构建的提交」与 HEAD 之间多出这些**按路径**被判为 compile input 的工件；已经落盘的那一份就是与最终源码**同一份源码**的构建所产出的。
- **「before」侧锚点（D86 ①）**：**`bf9518c2b3`** —— 基线二进制自报 `bf9518c2b`（== 该提交），`live_before/**` 全部由它产出；红相位用 `git show bf9518c2b3:<4 个文件>` 写回**同一份新测试**再构建。
- **交付提交**：`8a7d96c861`（实现）→ `f911f8831c`（证据/脚本）→ `516120255e`（测试计数）→ `6adaffcdf`（schema 整型折叠）→ `fefc92f08`（报告）→ `cdd125493`（一度把 scratch 工程移出证据树）→ `35ae10422`（恢复 scratch 工程，自包含证据树）→ `03472e20d` / `077694816`（最终门与锚点）→ 锚点记录提交。**未 push。**
- **端口纪律**：**9877 全程未被占用、未杀、未重启** —— 每次 live 目录里的 `guard_user_port_9877` 都是 PASS（`listening=False pid_before=-1 pid_after=-1`），收工 `netstat` 在 9877/9888/9889 上都无监听。我们只用自己的 9888/9889，用后即停。

---

## 0. 一句话结论（先看这 8 行）

| 项 | 结论 |
|---|---|
| **① D2（S1）** | **真缺陷，已修**：不兼容绑定（`Node2D` 节点 ← `extends Area2D`）过去回 `attached:true`（编辑器日志 0 次、游戏日志 3 次「engine drop」），且契约承诺的逐节点 `readable` 字段**全文不存在**。现在：不兼容 → 预检即拒（`-32000` + `data.suggestion` 点名引擎规则与两个类名），合法绑定 → `attached:true` + **`readable:true`**（逐节点读回核实） |
| **② 新增 `project_read_text_file`** | **已交付**：契约逐字、`scope=both`、只读、`res://` 受限；写→读→**三处 sha 一致**（写回执 / 读回 / 磁盘）、四类拒绝（越界/`..`/绝对/目录）、`max_bytes` 触发 `text_omitted` 对照、非 UTF-8 明确拒绝、**每次回答都声明不解析语义** |
| **③ D9 计数** | **修正了根因，并撤回了一个数字**：计数来源是 `obs_digest.py:78` 的 `bad`（**只由编辑器 trace 构造**），游戏侧**根本没有计数器**（只能数 GAME TRACES 的行）；现在按端口从**权威逐调用记录** `CALLS.jsonl` 统计并与 `raw/**` 交叉核对。**但「游戏侧实为 14」不成立**：权威记录与 §C 自己的脚本都给出 **9889 = 2**（编辑 28 / 游戏 2 / 合计 30，`raw/**`=30 MATCH）。**「14」撤回**（详见 §4） |
| **④ D4** | **不是工具口径不一致，是编辑器实例的快照/资源缓存**：三工具同用 `find_node`、在同一路径上**结论一致**；round-5 那次「属性写到 Anim」是 `player.tscn` 打开 + 路径 `"Anim"`。机制已最小复现（新子场景内容在**同一会话**里不进入实例，连新实例也是旧缓存；游戏从磁盘加载则有），并给出会话内绕法 |
| **⑤ D5** | **能力缺口，不是缺陷**：`project_create_resource{TileSet}` 造出的是**无 atlas source** 的 TileSet；`tile_set` 的**赋值真的落地**（`has_tile_set:true`），`editor_set_tilemap_cell` 以 `-32602` 明确说「没有 source 0（先加 TileSetAtlasSource）」——E8「赋值没落地」被证伪 |
| **⑥ 分析器漏报（S3）** | **真缺陷，已修**：`analyze_mcp_trace.py` 因 `args` 恒为 `str` 而**结构性漏报**整类信号；现在两种拼写都读、读不懂的计数上报，并加**仓库内自检**（`--self-test`，含「把它改坏必须 exit 1」的探针）。同一份 trace：修前 `probed args none` → 修后 6 个被拒参数名 |
| **门与检查** | 门①**3/3**（177 = 154 + 73 − 50）；门③ **348/348**、门④ **1774/1774**（0 failed）；门⑤ `accept_m1` ×2 **23/23** 且 **177 名单逐字一致**（同一 sha256）；门⑥ 三段式全绿；`--check-completeness/--added/--generator-version`、`check_exit_propagation`、`check_tautologies`、`check_engine_anchor` **exit 0** |

---

## 1. 交付物（绝对路径 `F:\RustProjects\godot-mcp-pro\code\godot\` + sha256）

| 文件 | sha256 | 角色 |
|---|---|---|
| `modules/mcp_server/tools/editor_set_node_script_batch.{h,cpp}` | `d5a12dc0…` / `ee439b7f…` | D2：`script_readable_on()`（引擎实例化前提）、不兼容的拒绝消息/建议、**预检**、逐节点 `readable` 读回 |
| `modules/mcp_server/tools/editor_script_write.cpp` | `3c3c9939…` | D2：单数工具同一道闸（同一消息/建议，两个工具不可能口径不一） |
| `modules/mcp_server/tools/project_text_read.{h,cpp}` | `13abbd52…` / `bc311ff6…` | ②新工具本体 + 两个纯谓词（UTF-8 校验、省略原因） |
| `modules/mcp_server/tools/registration.cpp` | `fe6f54ff…` | ②注册一行 + D2 头文件 |
| `modules/mcp_server/scripts/gen_renamed_contract.py` | `fec3c946…` | `ADDED_TOOLS` 追加第 6 条；`GENERATOR_VERSION 1.20.0 → 1.21.0`；v1.21 注释 |
| `modules/mcp_server/docs/tools_list.renamed.json` | `6f654b64…` | **177 条**契约（生成物） |
| `modules/mcp_server/docs/tool-groups-added.json` | `d6933678…` | 第 6 组 `project_text_read`（channel=project / verb=read / scope=both / mutating=false） |
| `modules/mcp_server/tests/test_mcp_server.h` | `d3c9a438…` | D2 用例、读工具用例、两个纯谓词、全部端点计数 176→177 / 153→154 / 72→73 / 49→50 / 35→36 |
| `modules/mcp_server/scripts/analyze_mcp_trace.py` | `96ba5260…` | ⑥`call_args()`、读不懂/被截断分别计数、`--self-test` |
| `modules/mcp_server/docs/reports/evidence/task074/observations/obs_digest.py` | `0f5725f0…` | ③按端口统计 + `raw/**` 交叉核对 + 覆盖面声明（D9） |
| `modules/mcp_server/scripts/mcp075_live_evidence.ps1` | `56a44393…` | 门②：`-Phase before\|after`，同一脚本同一请求，两次逐字对照 |
| `modules/mcp_server/scripts/mcp075_red_phase.ps1` | `02a24725…` | 红相位重放（写回 base 字节 → 必须红 → 还原校验 → 必须绿） |
| `modules/mcp_server/scripts/mcp075_analysis_evidence.ps1` | `eb86ac15…` | ③⑥ 修复前后对照（同一份冻结 trace/记录）+ 自检探针 |
| `modules/mcp_server/scripts/mcp075_d4_staleness.ps1` | `7a47f3a6…` | ④D4 机制复现 |
| `docs/reports/evidence/task075/{make_sha_manifest,compare_accept_inventories,dump_bodies,arg_kinds,find_unreadable_args}.py` | 见 `sha256_manifest.txt` | 本报告里每个数字的可复算生成器（§4.3、§4.4、§7、§8） |
| `docs/reports/evidence/task075/**` | 见 `sha256_manifest.txt`（40+ 个关键产物逐个 sha256） | 全部证据（绝对路径） |

**scratch 工程留在证据树里（与 `task074/project/**`、`task065/...` 的既有约定一致）**：三个脚本各自的 `proj/` 都提交，这样每一条请求都能对照**它实际运行的那个工程**（自包含、可复核）。代价是一个机械事实：`project.godot` 与 `*.tscn` 会被锚点分类器读成 **compile input**（实测把它们移出树的那次提交让 `ANCHOR_*` 变成 `STALE_COMPILED`、`RED_COUNT=6`）。因此本报告的纪律是：**引入/改动这些文件的那一次提交之后必须重新构建**——恢复提交 `35ae10422` 之后重建（`ANCHOR_EQUAL`）；最终那一份证据提交 `077694816`（含 live after 重跑重建的 `proj/`）之后**再**重建一次，得到**最终构建锚点 `077694816`（`ANCHOR_EQUAL`）**；其后只有门①/③/④ 的 `.txt`、报告与锚点记录的提交，判 `ANCHOR_STRUCTURAL_EQUIVALENT`，`RED_COUNT=0`（见下）。

**没有触碰的东西**：`docs/DESIGN-DETAIL.md`（0 行）、hof-rs（只读，未写）、`modules/mono/**`（0 行）、五个批次组清单（`tool-groups*.json` 未改）、`tools/` 下**其他任何组**的文件（0 行）。`git diff --name-only bf9518c2b3..HEAD` 的**全部**路径都在 `modules/mcp_server/**` 之内（已机器核对）。

---

## 2. ① D2：静默丢弃 + 契约承诺的 `readable` 不存在

### 2.1 先复现（before，锚点 `bf9518c2b3`；请求与响应逐字在磁盘）

同一脚本 `mcp075_live_evidence.ps1 -Phase before`（`live_before/d2_batch_incompatible.request.json` / `.response.json`，sha256 `4cff9d54834e…`）：

```json
{"attached":[{"attached":true,"index":0,"node_path":"Bad","previous_script_path":"","script_path":"res://scripts/coin.gd"},
{"attached":true,"index":1,"node_path":"Bad2", ...},{"attached":true,"index":2,"node_path":"Bad3", ...},
{"attached":true,"index":3,"node_path":"Good", ...}],"count":4,"errors":[],"keep_existing":false,"status":"ok"}
```

- `Bad/Bad2/Bad3/Good` 都是 `Node2D`，`res://scripts/coin.gd` 是 `extends Area2D` —— 四个节点全部 `attached:true`；
- **响应全文不含 `readable`**（脚本断言 `body carries 'readable'=False`，见 `live_before/evidence/summary.txt`）；
- 单数工具同样：`{"attached":true,"node_path":"Bad","script_path":"res://scripts/coin.gd"}`（`d2_single_incompatible`，`d01d0f93…`）；
- 合法对照（`Good` ← `ok.gd`，`extends Node2D`）在 before **也没有** `readable`（`60a3bb68…`）；
- **引擎侧对照**：`editor.err.log` 里引擎不匹配消息 **0 次**，`game.err.log` **3 次**（`L070`，`live_before`）—— 编辑器静默、游戏丢弃，与 D2/E3 的描述逐字一致。

### 2.2 修法（按引擎语义，不按 D1）

引擎的**唯一**判定点在实例创建：`GDScript::instance_create()` 检查 `p_this->is_class(script 的 native base type)`（`modules/gdscript/gdscript.cpp:420-426`），C# 同样（`modules/mono/csharp_script.cpp:2461-2465`）。编辑器进程里 `Object::set_script()` **问不到**这个问题：`editor/editor_node.cpp:8523` 把整个进程的 scripting 关掉，`GDScript::can_instantiate()` 因此为 false，`set_script()` 走占位分支（`core/object/object.cpp:1069-1072`），于是 `get_script()` 会回答一个引擎真正加载场景时会丢掉的脚本。

因此新增一个**读回式谓词**（`script_readable_on()`）：`get_instance_base_type()` 为空（引擎自己的检查有 `if (native.is_valid())` 守卫）→ 不拒绝；否则必须是该节点的一个类。它是**引擎规则的镜像**，不发明更严的规则（因此不会把 `extends Node` 之类合法绑定误判）。三处落地：

1. `apply_node_script()`（批量的写原语）先做该判定，失败即 `-32000` + 建议；
2. 批量在**预检阶段**逐节点判定 → 不兼容**什么都没写**就整批拒绝（与既有 all-or-nothing 语义一致），`errors[0]` 带 `readable:false` 与 `reason`；
3. 提交阶段**写后再测量一次**并写进逐节点 `readable`（契约承诺的字段），测量为假则整批撤回——`attached:true` 永远不会和 `readable:false` 同时出现；
4. 单数 `editor_set_node_script` 走**同一个**消息/建议函数，两个工具不可能口径不一。

### 2.3 修后（after，锚点 `cdd125493`）

不兼容（`live_after/d2_batch_incompatible.response.json`，sha256 `a788caa9…`）：

```json
{"code":-32000,"message":"nodes[0]: Node 'Bad' (Node2D) cannot carry script 'res://scripts/coin.gd': the script inherits from native type 'Area2D', which is not a class of this node, so the engine would drop the attachment when the scene is loaded",
 "data":{"batch":{"attached":[],"count":0,"errors":[{"index":0,"node_path":"Bad","readable":false,"reason":"…inherits from native type 'Area2D'…"}],
 "status":"rolled_back","rolled_back":true,"reverted":[],"on_error":"all_or_nothing"},
 "suggestion":"The engine attaches a script only when the script's native base type is a class of the node (GDScript::instance_create(), modules/gdscript/gdscript.cpp:420-426; CSharpScript::instance_create(), modules/mono/csharp_script.cpp:2461-2465) - the editor process takes the placeholder branch instead (Object::set_script(), core/object/object.cpp:1069-1072) and so cannot report the mismatch by itself. Attach 'res://scripts/coin.gd' to a node that is a 'Area2D' (or a subclass of it), or change the script's 'extends' to a class of 'Node2D'"}}
```

合法对照（`live_after/d2_batch_compatible.response.json`，`618d3ba4…`）：`{"attached":[{"attached":true,"index":0,"node_path":"Good","previous_script_path":"","readable":true,"script_path":"res://scripts/ok.gd"}],"count":1,...,"status":"ok"}` —— **防假修复**：合法绑定仍成功且 `readable:true`。

**端到端传播证据（活证据链）**：保存场景 → 用工具读回 `main.tscn` → `carries scripts: coin.gd=False ok.gd=True`（before 是 `coin.gd=True`）→ 起游戏（9889）：`Good.marker=75`（脚本真被实例化，**运行期可读**，证明修复没有把好绑定一起拒掉），`game.err.log` 里引擎不匹配消息 **0 次**（before 3 次）。`Good/Bad` 的对照在 before/after 两轮都存在。

**红相位**（`mcp075_red_phase.ps1`，7/7 PASS；证据 `evidence/task075/red_phase/`）：把 `bf9518c2b3` 的 4 个实现文件字节写回 → 重建 → **同一份新测试** `3 cases | 1 passed | 2 failed`、`129 assertions | 75 passed | 54 failed`、`Status: FAILURE!`；还原（逐字节 sha 校验）→ 重建 → `3/3 passed`、`137/137`。

**边界声明**：doctest 进程没有编辑器，因此**编辑器占位分支造成的静默**在 doctest 里不可复现（doctest 里引擎自己就会拒绝）。所以红相位钉住的是**契约字段与拒绝文案**，而「静默接受」本身由上面的 live before/after 钉住。两处证据都在。

---

## 3. ② 新增 `project_read_text_file`（契约 177 = 171 + 6）

- **描述逐字**：`Read a text file inside the project and answer its bytes, size and digest, so a file written by a tool can be verified with a tool.`
- **`inputSchema`**：`path`(string, 必填) / `max_bytes`(integer, 默认 1048576, 上限 16777216)；`scope=both`、`mutating=false`、**只读**。
- **答案**：`path` / `size`（UTF-8 字节数）/ `sha256`（`FileAccess::get_sha256()`，与 `project_write_text_file` 回执同一个调用）/ `text`（或 `text_omitted:true` + `reason` + `max_bytes`）；**每次**都带 `parsed:false` 与 `note`（**如实声明不解析语义**：不判断它是 JSON/配置/场景）。
- **限制在 `res://` 内**：非 `res://`、含 `..`、OS 绝对路径 → `-32602` + 建议；只给目录/项目根 → `-32602` + 建议；缺文件 → `-32001` + 建议；**非 UTF-8** → `-32000` + 建议（绝不把一段并非该文件内容的字符串当 `text` 发出去）。

### 证据（全部 live，`live_after/evidence/`）

1. **写 → 读 → 三处 sha 一致**：`project_write_text_file{res://save/slot1.json}` 回执 `sha256=c824cf30d46289d3488999485166bd2a84082dbe441c1039092ff0c31e1d4f3d / bytes=20`；`project_read_text_file` 回答 `sha256` 同名同值、`size=20`、`text` 逐字等于写入内容（`read_tool_roundtrip.response.json`，`daf4d278…`）；磁盘 `Get-FileHash` 同值（`L040/L041`）。**三处一致**。
2. **四类拒绝各一条**：`user://outside.txt` / `res://../secrets.txt` / `C:/Windows/win.ini` → 均 `-32602` + 建议；`res://scenes`（目录）→ `-32602 "names the directory … not a file"` + 建议；另外补了「缺文件」`-32001` 与两类 `max_bytes` 越界 `-32602`。
3. **`max_bytes` 对照**：4096 B 文件 `max_bytes:16` → `{"text_omitted":true,"size":4096,"sha256":a2e659da…,"reason":"The file is 4096 byte(s), larger than 'max_bytes' (16)…"}`；`max_bytes:8192` → `text_omitted:false` 且 `text` 长度 4096（`read_big_omitted` / `read_big_included`）。
4. **非 UTF-8**：`0x41 FF FE 42 00 43` → `-32000 "its bytes are not valid UTF-8 text"` + 建议（其中一条建议就是「把 `max_bytes` 设得比文件小仍可拿到 sha256」）。

**门①**：`check_contract_subset.ps1 -Group project_text_read` → **3/3 PASS**，`editor 154 / game 73 / contract 177`，且 `project_read_text_file: name=True description=True inputSchema=True`（`gate1_contract_subset.txt`，`ae74016d…`）。**注意**：这条门第一次是 **FAIL** 的（`inputSchema=False`）——因为 schema 字面量经 Godot `JSON` 解析后 `1048576` 成了 `float`、发出去是 `1048576.0`；用与本模块既有两个解析式注册器相同的「整型折回 INT」修正后转绿。**这正是活门抓到的、doctest 没抓到的一处真差异**（记录在 §10）。

---

## 4. ③ D9：计数从哪来、为什么漏、修正——以及**一个必须撤回的数字**

### 4.1 计数从哪来（文件:行）

- **§B 的脚本**：`docs/reports/evidence/task074/observations/obs_digest.py` **第 78 行** `bad = [r for r in calls if not r.get('ok')]`，其中 `calls` 在**第 47 行**由 `recs = load(EDITOR)` 构造 —— **列表里只有编辑器 trace 的调用**。游戏侧（`GAME TRACES` 段，第 189-201 行）只是**逐行打印**，**没有任何聚合计数**。
- **§A/§C 的记录**：会话的**权威逐调用记录**是 `docs/reports/evidence/task074/CALLS.jsonl`（232 行 = 198 编辑 + 34 游戏），字段 `result` 形如 `"ok"` / `"error curl=0 code=-32001"`。

### 4.2 为什么漏

1. 编辑器侧有计数器、**游戏侧没有** —— 想得到一个游戏侧数字，只能去数 `GAME TRACES` 段里的 `ok=False` 行（就是那 **2** 行）；
2. 追踪本身是**有界快照**（强杀会截断尾部；没开追踪的会话一行也没有），**任何按 trace 统计的数都只能是下界**，而两个报告都没有把这句写出来；
3. 修正后的脚本还查到一个同族事实：`CALLS.jsonl` 自带的 `isError` 布尔**在 232 行里全是 false**（harness 侧写坏了），谁用这个字段计数都会得到 0 —— 现在 digest 明确打印这一行，并只认 `result`。

### 4.3 修正（同一份冻结输入的前后对照）

`mcp075_analysis_evidence.ps1`（8/8 PASS，证据 `evidence/task075/analysis/`）：修前脚本在 `%TEMP%` 自建工作目录（`traces/` 副本）运行，**不写**仓库内冻结的 `digest.txt`（其 sha256 前后不变，已断言）；修后脚本带输出参数运行。

| | 修前（`digest_before_task075.txt`，`f6da86af…`） | 修后（`digest_after_task075.txt`，`81591452…`） |
|---|---|---|
| 有没有「按端口非 ok」段 | **没有**（脚本只有编辑器 `count=28`）；游戏侧只能**肉眼数出 2** | 有：`rows=232 ok=202 non-ok total=30`、`editor (9888) non-ok=28`、`game (9889) non-ok=2` |
| 交叉核对 | 无 | `raw/**` 含 `error` 键 = **30**，与 `CALLS.jsonl` 非 ok 合计 **30 → MATCH** |
| 覆盖面 | 无 | 明确打印 `COVERAGE: the traces carry 28 of the 28 editor-side and 2 of the 2 game-side failures…`，并说明按 trace 统计只是**下界** |

### 4.4 **撤回**：任务书里的「游戏侧非 ok 实为 14」不成立

任务书（以及 `PLATFORMER-FINDINGS` §1.1/§2.2）写「游戏侧非 ok 实为 **14**（全部 `-32001`）」、并把「A/B 都记 2」判为**低估 12 条**。**这条主张在冻结证据里查无实据，本报告显式撤回**：

| 独立来源 | 9889 非 ok |
|---|---|
| `CALLS.jsonl`（232 行，按 `result` 判） | **2**（`-32001` ×2，`running_game_get_node_properties`，M11 n=5、M13 n=6） |
| `trace-game{,2,3,4}.jsonl`（34 条 `tools/call`） | **2**（game3 seq2、game4 seq1） |
| `raw/**`（30 个含 `error` 键的响应） | 合计 30 = 28 + 2 |
| **§C 自己的复算输出** `aggregate/c_calls2.stdout.txt:6` | `port 9889 calls 34 ok 32 non-ok 2` / `codes: {-32001: 2}` |

也就是说 §C 的「14」与它**自己的 stdout**以及全部冻结记录相矛盾（14 恰好等于**两个端口**的 `-32001` 总数 12+2，看起来是把端口的 `-32001` 计数误当作游戏侧的数）。**`-32001` 的 14 条里有 12 条是编辑器的 `editor_*` 调用**（`c_calls2.stdout.txt:3` 的 `{-32001: 12}`）。因此：

- **修复保留**：digest 现在有按端口计数、有交叉核对、有覆盖面声明（这才是「根因」层面的修，而不是改一个数字）；
- **数字撤回**：「实为 14 / 低估 12」不成立，正确口径是 **编辑 28 / 游戏 2 / 合计 30**；机器断言 `D904` 就钉住这条撤回；
- 这一条是**对第 5 轮汇总的纠错**，按 PLAYBOOK §7.3（证据被证伪要显式撤回）处理，不改任何历史文件。

---

## 5. ④ D4：实例子场景内部节点的可寻址性（最小复现 + 定性）

**复现脚本**：`scripts\mcp075_d4_staleness.ps1`（9/9 PASS，`evidence/task075/d4_staleness/`）。

| 步骤 | 观测 |
|---|---|
| `player.tscn` 无子节点，`main.tscn` 里实例化它 | `Player` 子节点数 = 0；`Player/Anim` → `-32001`（一致） |
| 打开 `player.tscn`，加 `AnimationPlayer "Anim"`，保存 | 磁盘 `player.tscn` **确实**含 `Anim` |
| 回 `main.tscn`（实例仍在） | `Player` 子节点 **仍 0**；`Player/Anim` **仍 `-32001`** |
| 用 `editor_add_scene_instance` **新建**一个同文件实例 | 新实例子节点 **也是 0**；`Player2/Anim` 也 `-32001` |
| **游戏**（另一进程，从磁盘加载） | 场景树里 **有** `Player2/Anim` |
| 会话内绕法：`editor_add_node{parent_path:"Player"}` | `Player/Anim` **可寻址**，`editor_connect_signal` 成功 `connected:true, persisted:true` |

**定性：不是「工具口径不一」，也不需要改寻址**。

1. 三个工具（`editor_get_scene_tree` / `editor_set_node_property` / `editor_connect_signal`）都经**同一个** `MCPTools::find_node`（`tools/tool_helpers.cpp:1417`），在**同一路径**上结论一致 —— 本轮 live 证据 `L020/L021/L022` 与上面的探针都如此；
2. round-5 记录的「属性写工具到得了 `Anim`」是**另一个上下文**：`docs/reports/evidence/task074/scripts-run/m4_anim.ps1:21` 先 `editor_open_scene res://scenes/player.tscn`，第 78 行才写 `path:"Anim"`（**被编辑场景根的直接子节点**）——与在 `main.tscn` 上下文里写 `World/Player/Anim` **不是同一个路径**；
3. 真正的机制是**编辑器把 PackedScene 缓存成实例快照**：子场景变了以后，同一会话里的旧实例与**新建实例**都还是旧缓存（游戏从磁盘加载，因此是新的）；
4. **声明边界（调用方如何绕）**：`editor_get_scene_tree` 是「此刻可寻址什么」的唯一权威；要在**同一会话**里操作子场景新增的内部节点，就把它作为外层场景里实例下的子节点写（`editor_add_node{parent_path:"<实例>"}`，实测可寻址且可连接）；或者**开新的编辑器会话**（缓存重建）。子场景本身的编辑永远应当**先做**，再做外层场景的实例化。

**未改任何工具**：这是「如实声明边界」而不是「修」，因为把 `find_node` 改成穿越缓存去重建实例会改变所有编辑器工具的语义（并让一次读取产生写副作用）——超出本批范围，也不属于「同一路径口径不一」。

---

## 6. ⑤ D5：TileSet 无 atlas source（最小复现 + 定性）

同一 live 脚本的 `d5_*` 请求（before/after 逐字相同）：

| 调用 | 结果 |
|---|---|
| `editor_add_node{TileMapLayer}` | ok |
| `project_create_resource{path:res://tiles/empty_tileset.tres, type:TileSet}` | `{"properties_set":[],...,"type":"TileSet"}` —— 造出的是**没有任何 source** 的 TileSet |
| `editor_get_tilemap_info`（赋值前） | `has_tile_set:false, source_count:0, sources:[]` |
| `editor_add_resource_to_node_property{tile_set}` / `editor_set_node_property{tile_set}` | **都成功** |
| `editor_get_tilemap_info`（赋值后） | **`has_tile_set:true**, source_count:0, sources:[]` |
| `editor_set_tilemap_cell{source_id:0,…}` | `-32602` `"The TileSet of this TileMapLayer has no source 0; it has: no source at all (add a TileSetAtlasSource first)"` + `data.suggestion`（点名该工具接受的参数） |

**定性：能力缺口，不是缺陷**（E8/D5 的「赋值本身没走通、终态 `has_tile_set:false`」被证伪）。缺口是**没有任何工具能创建/填充 `TileSetAtlasSource`**（需要 texture + source 创建），本模块也没有「加 atlas source」的工具；`editor_set_tilemap_cell` 的拒绝**明确、可执行**（`-32602` + 建议）。**结论**：不改行为，按缺口记账（下一批若要补，应为 `editor_add_tileset_atlas_source` 类的 added 工具；本批不改契约条数以外的东西）。

---

## 7. ⑥ 分析器结构性漏报（`analyze_mcp_trace.py`）

- **漏报点（文件:行）**：`missing_tools()` 里 `args = record.get("args")` 后 **`keys = list(args.keys()) if isinstance(args, dict) else []`** —— trace 把 `args` 写成 **JSON 字符串**（冻结 trace：`args` 为 `str` 198/198、`dict` 0/198），于是恒 False、`probed_argument_names` **结构性为空**，汇总里只印 `probed args none`。
- **修**：新增 `call_args()`（同时接受 `dict` 与 JSON 对象字符串）；读不懂的**上报**而不是静默当空：`unreadable_argument_lists`，并把 trace 自己标记的截断（`args_truncated`）单独计为 `truncated_argument_lists`（冻结 trace 里恰好 1 条：seq 128 `editor_add_nodes_batch`）。
- **同一份 trace 的前后对照**（`analysis/analyze_before_editor.txt` `2f6b6e7c…` → `analyze_after_editor.txt` `f997e4b9…`）：修前 `probed args none`；修后 **6 个**：`source_id ×4`、`atlas_x ×2`、`atlas_y ×2`、`resource_properties ×2`、`resource_type ×2`、`atlas_coords ×2`，另有 `truncated arg lists 1`。
  - 诚实的边界：该信号的定义是「**多次失败且从未在任何成功调用里被接受**」，因此一个**拼写正确但那次调用因别的原因失败**的参数也会出现在列表里（`source_id`/`atlas_coords` 正是如此）——它是**摩擦信号，不是判决**，这一点写进脚本 docstring 与报告。
  - 「`str` 198/198」与「被截断的 1 条 = seq 128 `editor_add_nodes_batch`」由两个小脚本直接测出：`evidence/task075/arg_kinds.py`（`{'str': 198}` / `args_truncated true: 1`）与 `evidence/task075/find_unreadable_args.py`（`tools/call rows: 198`、`unreadable: 1`、`(128, 'editor_add_nodes_batch', '{"nodes":[…', True, 0)`）。
- **仓库内断言（防复发）**：新增 `--self-test` 模式，喂合成 trace（字符串 `args` / dict `args` / 非 JSON / 缺 `args`），要求：`atlas_x/atlas_y/bogus` 必须被报出、`node_path/source_id`（成功调用接受过）**不得**被报出、计数必须为 2/0；不满足即 `exit 1`。**并且证明这个断言真的会红**：把 `call_args()` 改成恒 `return None` 的探针副本 → `SELF-TEST FAILED (4 problem(s))`、`exit 1`（`analysis/analyze_self_test_mutated_probe.txt`）。

---

## 8. 门与纪律（全部自跑，真实输出与退出码都在 `docs/reports/evidence/task075/`）

| 门/检查 | 命令 | 结果（采集自哪次构建） |
|---|---|---|
| 契约 177 = 171+6 | `python docs\scripts\check_tool_groups.py --check-completeness` | **exit 0**；`ASSERT 171 + 6 = 66 + 105 + 6: PASS`、`every claimed name exists in the 177 entry contract: PASS`（无引擎依赖） |
| ADDED 清单一致 | `… --added` | **exit 0**；`manifest = contract _meta.added_tools`（6）、`channel/verb derived agree: PASS` |
| 生成器版本三方一致 | `… --generator-version` | **exit 0**；`GENERATOR_VERSION == _meta.generator_version == source.generator_version: PASS (1.21.0)` |
| **门①** | `scripts\check_contract_subset.ps1 -Group project_text_read` | **3/3 PASS**；`contract 177`、`editor 154`、`game 73`、新工具三字段逐字 True、`guard_user_port_9877 PASS`（`077694816`） |
| **门②** | `mcp075_live_evidence.ps1 -Phase before` / `after` | **before 18/18 PASS**（二进制自报 `bf9518c2b`）、**after 26/26 PASS**（`35ae10422`，源码与最终构建相同）；每条响应由 `curl.exe -s -o` 落盘并有 sha256；含写→读→sha 的跨工具链 |
| **门③** | `bin\…console.exe --headless --test --test-case="[MCPServer]*"` | **exit 0**：`348 | 348 passed | 0 failed`、`24223 | 24223 passed | 0 failed`（`077694816`） |
| **门④** | `bin\…console.exe --headless --test` | **exit 0**：`1774 | 1774 passed | 0 failed | 3 skipped`、`448470 | 448470 passed | 0 failed`（`077694816`） |
| **门⑤** | `scripts\accept_m1.ps1` ×2 | **23/23** ×2；`implemented tools = 154 / 73; contract = 177`；两次 `tool_names` **177 条逐字一致**（同一 sha256 `276f162c94fb…`，`accept_m1_inventory_compare.json` `verdict=PASS`）（`cdd125493`，源码与最终构建相同） |
| **门⑥ 三段式** | `check_narrowing_points.py` / `--coverage` / `mcp031_gate6_coverage_probes.ps1` | **exit 0 / exit 0 / 全 PASS**：`scanned == pinned == 75`、基线绿、17/17 声明拼写都有「插入即 exit 1」探针、B1b `worktree_clean_of_probes` + 逐字节还原（与引擎二进制无关，纯源码扫描） |
| 锚点（D86 ①） | `check_engine_anchor.ps1 -VersionText <自报版本>` | **exit 0**，`ANCHOR_EQUAL`（`077694816`，diff_count=0）；文件末尾追加了报告/证据提交后 HEAD 的 `ANCHOR_STRUCTURAL_EQUIVALENT` 记录 |
| 退出码传播 | `python scripts\check_exit_propagation.py` | **exit 0**（`EXIT-CODE PROPAGATION CHECK PASS`） |
| 同义反复 | `python scripts\check_tautologies.py` | **exit 0**（`TAUTOLOGY CHECK PASS`） |
| 硬编码计数普查 | `python scripts\check_hardcoded_counts.py` | **exit 1（既有红，非本批引入）**：`UNCLASSIFIED` 只有 `scripts/mcp071_gate2_live_evidence.ps1:192` 与 `:266` 两行，该文件 `git diff bf9518c2b3..HEAD` **为空**；用 `git archive bf9518c2b3` 解出的**基线树**跑同一检查同样是这两行（另加 9 条「被扫到的检查器副本自身」的假命中）→ **基线就红**，本批不动它 |
| 组清单哈希 | `check_tool_groups.py --check-completeness` | `BYTES/SHA256 ADDED = 8072 / 0295cf86…`（B3/B4/B5 不变） |

**构建**：严格串行，全部从 cmd 启动 `modules\mcp_server\scripts\build_local.cmd -Force`（`tests=yes`、不抑制输出、日志落 `docs/reports/evidence/task075_build_*.log`）。基线（`bf9518c2b`）→ after（`516120255`）→ 红相位红/绿两次 → `6adaffcdf`（schema 修正）→ `cdd125493` → `35ae10422` → **`077694816`（最终，`ANCHOR_EQUAL`）**。每次构建后都核对 `--version` 与 HEAD。施工顺序是：**先提交、再构建、再跑门**；门①/③/④ 的产物只有 `.txt`，所以在最终二进制上跑完它们、提交之后，锚点判据仍给出 `STRUCTURAL_EQUIVALENT`（`RED_COUNT=0`、`exit 0`，见 `gate_engine_anchor.txt` 末尾那条记录）。

**锚点判据的「±1 次提交」说明**：任何在构建之后落地的文档/脚本/证据提交都会让 `HEAD` 前移一格，此时判据给出 `ANCHOR_STRUCTURAL_EQUIVALENT`（`exit 0`，`git diff A..H` 全是已声明**不参与编译**的白名单文件）。`gate_engine_anchor.txt` 里追加了两条记录：第一条是 `cdd125493`（被构建的提交）的 `ANCHOR_EQUAL`，第二条是最后一批报告/证据提交之后的 `HEAD`，判 `STRUCTURAL_EQUIVALENT`（`RED_COUNT=0`）。这不是「锚点过期」，而正是决策 D130 要的判据：二进制与 HEAD 之间**没有任何能改变编译产物的差异**。

**回归逐条归因**（本批每次「计数移动」都在这里点名）：

| 现象 | 归因 | 处置 |
|---|---|---|
| 端点计数 176→177 / 153→154 / 72→73 / 49→50 / 35→36 | 新增 1 个 `scope=both` 工具（契约 177） | 测试文件内**全部**同步（第一次门③/④ 就是因为漏了一处 `build_tools_list(true).size() == 49` 而红，当场修正后转绿） |
| `inputSchema` 整型漂移（`1048576.0`） | Godot `JSON` 单数字类型 | 在**新文件**里加与既有两处相同的「整型折回 INT」，不动别组文件 |
| `check_hardcoded_counts.py` 2 行 UNCLASSIFIED | `mcp071_gate2_live_evidence.ps1` 的 153/72/176 字面量（TASK-071 证据脚本） | **不改**（别人批次的冻结证据）；基线同样红，已归因 |
| `mcp063_product_defects_evidence.ps1`(378/472/486)、`mcp066b_run.ps1`(349/730)、`mcp071_gate2_live_evidence.ps1`(170/182/191) 仍写 176/153/72 | 同上：TASK-063/066b/071 的**活证据脚本**，按「stale expectation」纪律**允许过期**，普查脚本把它们分在 LIVE/PINNED 桶 | **不改**，在此逐条归因：这些脚本若在今天重放会红，红的原因是契约长大 1 条（预期值 176/153/72 → 177/154/73），不是产品回归 |
| 门⑥ `18 pinned line drifted` | 早于本批的既有漂移（列出的文件里没有本批新增/修改的收窄点） | 不改 pin（检查器自身声明「不是失败，方便时更新」） |

---

## 9. §22.3b 规则 4（新增/修改收窄代码必须逐条列出「新增点 × 闸门 × 证据」）

**本批新增收窄点 = 0。** 证据：门⑥ 基线 `scanned == pinned == 75`（与本批之前相同），探针脚本 `B1b_restored_scanned_75` + `B1b_worktree_clean_of_probes` PASS。本批新代码里的类型转换**逐条**列出（都不是被声明覆盖的收窄拼写，也不经过浮点/颜色/向量构造）：

| 位置 | 转换 | 为什么不是收窄点 |
|---|---|---|
| `project_text_read.cpp` `FileAccess::get_file_as_bytes` 返回值 | `(int64_t)bytes.size()` | 整数→整数（`size()` 是 `int`/`int64_t`），无 `real_t/float`、无 `Color(`/`Vector*` 构造、无隐式收窄 |
| `utf8_bytes_are_valid()` | `(uint32_t)(continuation & 0x3F)` 等 | 纯整数位运算（掩码后最大 0x3F，永不越界），不涉及本模块的槽位宽判据 |
| `utf8_bytes_are_valid()` | `(const uint8_t *)p_bytes` / `(const char *)bytes.ptr()` | 指针转换 |
| `project_text_read.cpp` 错误分支 | `(int64_t)read_error` | 枚举→整数，只用于消息文本 |
| `editor_set_node_script_batch.cpp` | 无新增转换 | 新代码只有 `StringName`/`String` 比较与 `is_class()` |

门⑥ 在本批是三腿之一（机器检查 + 代码审查 + 行为证据）：结构体/字段层的行为证据是 §2 的 live before/after 与 §3 的读工具链。

---

## 10. 结论锚点（D86）

| 结论 | 锚点 |
|---|---|
| D2 修复与 before 对照 | 最终二进制 `077694816`（after；源码相同的中间构建 `35ae10422`/`cdd125493`/`6adaffcdf`）↔ `bf9518c2b3`（before） |
| 契约 177 = 171 + 6 | `_meta.count=177 / added_count=6 / generator_version=1.21.0`；`docs/tools_list.renamed.json` = `6f654b64…` |
| 门③/④ 数字 | `348/348`、`24223`；`1774/1774`、`448470`（最终 `077694816` 的二进制） |
| 门⑤ 两次名单一致 | `accept_m1_inventory_compare.json`（两次 `names_sha256=276f162c94fb…`、`lists_identical=true`、`verdict=PASS`） |
| D9 修正 | `CALLS.jsonl` = `56d95094…`（冻结）；`digest_after_task075.txt` = `81591452…` |
| D9 撤回 | `aggregate/c_calls2.stdout.txt` = `decae247…` 第 6 行 `non-ok 2` |
| D4 机制 | `d4_staleness/evidence/summary.txt` = `9f721ad3…`（9/9 PASS） |
| D5 定性 | `live_after/evidence/d5_info_after_assign.response.json` + `d5_set_cell.response.json` |
| D11 前后 | `analyze_before_editor.txt` = `2f6b6e7c…` → `analyze_after_editor.txt` = `f997e4b9…` |
| 锚点 | `gate_engine_anchor.txt`（`ANCHOR_EQUAL 077694816` + 报告提交后 HEAD 的 `ANCHOR_STRUCTURAL_EQUIVALENT`） |
| 全部产物 sha256 | `docs/reports/evidence/task075/sha256_manifest.txt`（40+ 项，最后一次运行后重新生成） |

---

## 11. 未做、边界与风险

1. **没有给 `editor_set_node_script_batch` 加「不兼容但继续」模式**：契约要求「不兼容必须如实失败」，且该批本就是 all-or-nothing；`errors[0].readable:false` 是逐节点的不可读信号。
2. **`readable` 的精确定义**已写进代码注释与报告：等于「引擎实例化前提」——`get_instance_base_type()` 非空时必须是该节点的一个类；空基类型不拒绝（与引擎 `if (native.is_valid())` 守卫一致）。它**不**回答「脚本本身是否编译通过」（那是 `project_validate_scripts` 的职责），这是刻意的边界，不夸大。
3. **D4 是「声明边界」而非「修寻址」**（§5）：改 `find_node` 去穿透资源缓存会让所有编辑器工具产生写副作用。
4. **D5 是能力缺口**：本批不新增 TileSetAtlasSource 相关工具（那会再动契约与组清单，属于新工作）。
5. **D9 是对第 5 轮汇总的纠错**：`14` 撤回；若决策者认为另有来源支持 14，请给出该来源的文件与 sha256，本报告的可复算脚本（`mcp075_analysis_evidence.ps1`）可直接重跑。
6. **未写 `DECISIONS.md`**：本 fork 的 PLAYBOOK §0 明确「决策日志在 harness 仓库 `F:\moonbit-hof-rs\DECISIONS.md`，对本模块执行者**只读**；本 fork 内不得新建竞争性日志」。因此本批的全部决策/偏离/撤回都记录在**本报告**里（§2.2、§4.4、§5、§6、§11），没有在仓库内新建决策文档。
7. **一处过程偏离（如实声明）**：`mcp075_live_evidence.ps1` 的 `L030_d5_characterised` 谓词在 **before 轮之后**由恒真改为真断言（D5 三项事实）；**请求一字未改**，且加强后的谓词对 before 轮落盘的响应同样成立（`d5_create_empty_tileset.properties_set=[]`、`d5_info_after_assign.has_tile_set=true`、`d5_set_cell.code=-32602`）。
8. **Live 证据只覆盖 9888/9889**：9877 从未被请求、未被杀、未被重启（每次 `guard_user_port_9877` PASS）。
