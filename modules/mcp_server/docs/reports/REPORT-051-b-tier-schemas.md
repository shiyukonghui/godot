# REPORT-051 — B 档契约批（只改 `inputSchema`，条目数不变）：C-3 / O-9 / O-4 / O-5 / M-3

> **任务书**：`docs/tasks/TASK-051-b-tier-schemas.md`（自包含手册 `docs/tasks/PLAYBOOK-group-port.md`）。
> **被独立确认的清单**：`docs/reports/REPORT-AUDIT-RACING-BACKLOG.md`（C-3 / O-9 / O-4 / O-5 / M-3 均 **confirmed**）。
> **本批不做**：O-2（决策者已裁定，见 §10.7）。
> 每条都先按 **D86** 在**改动前的二进制**上复测，再改；红/绿两套证据见 §2。

---

## 0. 锚点、工件与纪律自证

### 0.1 锚点与构建（D86）

| 项 | 值 | 来源 |
|---|---|---|
| 仓库 / 分支 | `F:\RustProjects\godot-mcp-pro\code\godot` / `feature/mcp-server-module` | `git rev-parse --abbrev-ref HEAD`【实测】 |
| **结论所测的 HEAD** | `588f749941dc9f357fac2ce450710b62bc11249a`（短 `588f74994`，`docs(mcp_server): REPORT-050 …`） | `git rev-parse HEAD`【实测】 |
| 引擎自报（绿） | `4.8.dev.custom_build.588f74994`（**== 短 HEAD**） | `bin\godot.windows.editor.x86_64.console.exe --version`【实测】 |
| 引擎自报（红） | `4.8.dev.custom_build.588f74994` | 同上（红用的是**同一 HEAD 源码**重建的改动前二进制，见 §2.1） |
| 构建命令 | `modules\mcp_server\scripts\build_local.cmd -Force`（从 `cmd` 启动，`tests=yes`，`module_mono_enabled=no`）→ **exit 0** | `%TEMP%\mcp_server_build_local.log`【实测，本批共 4 次构建全部 exit 0】 |
| 契约（改前） | `docs/tools_list.renamed.json` **119 598 B** / generator `1.12.0` / overrides **24** / 171 条 | `git show HEAD:…`【实测】 |
| **契约（改后）** | `docs/tools_list.renamed.json` **132 684 B / sha256 `c92b9fd2f93905fbf1a260a740fbbb19ffc0e3d6858165c0d47b0488f508d6d5`**，**171 条**（不变），generator **`1.13.0`**，overrides **28** | `python scripts\gen_renamed_contract.py`【实测，连跑两次 sha 相同】 |
| 端口纪律 | 全程只用 **9888（编辑器）/ 9889（游戏）**；每次运行的守卫生成的判定 `port_9877_pass=true`（`classification=environment_fact_no_listener_before_or_after`） | 红/绿 `summary.json`【实测】 |
| **提交后重建与复验** | 4 条提交后重建：`--version` = `4.8.dev.custom_build.06abd44ce`（**== 短 HEAD `06abd44ce`**），门③ **307/307**、门④ **1733/1733**、门①（`editor_playback` 组）**3/3** 且 `editor_play_scene: inputSchema=True` | `green/gate3_postcommit_rebuild.log`、`gate4_postcommit_rebuild.log`、`gate1_postcommit_editor_playback.log`【实测】 |

### 0.2 交付物

| 文件 | 性质 | 说明 |
|---|---|---|
| `tools/editor_node_batch_write.h/.cpp` | 实现 | **C-3**：`add_nodes_batch_on(..., resolve_within_batch)` + 批内父路径解析 + 三种明确拒绝 |
| `tools/editor_node_read.h/.cpp` | 实现 | **O-9**：`SignalConnectionScope` 枚举、判定/过滤/计数三个纯函数、工具侧 `scope` 参数 |
| `tools/editor_playback.h/.cpp` | 实现 | **M-3**：`build_play_args()` 唯一规则函数 + `headless`/`extra_args` 读写与响应新字段 |
| `tools/editor_input_simulation.cpp` / `tools/running_game_test_execution.cpp` | 实现（生成段） | O-4/O-5 的注册字面量由 `gen_b2_game_schema.py --in-place` 重生成 |
| `scripts/gen_renamed_contract.py` | 生成器 | v1.13 段落 + **5 条 `SCHEMA_OVERRIDES`（`mode=replace`）** + `GENERATOR_VERSION` 1.13.0 |
| `docs/tools_list.renamed.json` | 契约（生成物） | 结构化 diff 只有 5 条 `inputSchema` + `_meta`（§7.3） |
| `tests/test_mcp_server.h` | 测试 | `+610` 行：7 个新用例（含 1 个 schema 逐字用例）+ **3 处 TASK-050 期望值按新派生文本更新**（§9.1） |
| `scripts/mcp051_b_tier_evidence.ps1` | 证据脚本（新，纯 ASCII） | 25 个真实请求 + 8 条事实；红绿同一把尺子，**不写断言** |
| `scripts/mcp051_gate1_groups.ps1` | 门①运行器（新，纯 ASCII） | 5 个受影响组各跑一次完整门①（含并集断言） |
| `scripts/mcp051_gates.ps1` | 门运行器（新，纯 ASCII） | 契约静态检查 + 门③④⑤⑥，逐步记退出码 |
| `scripts/mcp051_regression_battery.ps1` | 回归批次（新，纯 ASCII） | `individual` / `batteries` / `capture` 三批，严格串行 |
| `scripts/mcp051_contract_diff.py` | 契约 diff 门（新） | 断言「只动这 5 条 `inputSchema`、且每条**只新增成员**、`_meta` 只动两处」 |
| `scripts/mcp051_wire_verbatim_check.py` | 线上逐字检查（新） | 从**保存下来的** `tools/list` 响应里对 5 条工具做契约逐字比对 + 证明默认答案的连接数组没动 |
| `scripts/mcp051_final_sweep.py` | 收工一致性检查（新） | 二进制不比 `tools/**`/`tests/**` 旧、4 个脚本纯 ASCII、契约重生成幂等、三段生成段「already up to date」 |
| `docs/reports/evidence/task051/**` | 证据 | 红/绿两套 25×2 请求/响应 + summary + 门日志 + 回归日志 + 红绿逐行对照 |

### 0.3 纪律自证

| 纪律 | 实测 |
|---|---|
| 只改 `modules/mcp_server/**` | `git status --porcelain` 的已跟踪改动**恰好 11 个文件**，全在 `modules/mcp_server/` 下；`hof-rs` 全程只读；`DESIGN-DETAIL.md` **一字未改**【实测】 |
| 绝不占用/杀/重启 9877 | 只用 9888/9889；守卫生成的判定见 §0.1；唯一的 9899 类端口是 M-3 自己起的**游戏子进程**（9889）与 E-17 自动挑的端口，均在本脚本的 PID/命令行登记里【实测】 |
| 禁止 push | 无任何 push；只有本仓库本地提交【实测】 |
| 构建串行、不抑制输出 | 4 次 `build_local.cmd -Force` 全部串行（等待完成才继续），输出落 `%TEMP%\mcp_server_build_local.log`【实测】 |
| `.ps1` 纯 ASCII | 5 个新脚本逐个字节校验：非 ASCII 字节数 = **0**【实测】 |
| 契约**不手改** | 契约由生成器产出；**连跑两次 sha 相同**（`c92b9fd2…`）【实测】 |
| 证据 | 响应一律 `curl.exe -s -o <file>` 落盘 + sha256；请求体无 BOM UTF-8【实测】 |
| 未使用的构建面 | 本锚点仍是 `module_mono_enabled=no`（与审计报告同一限制），C# 语义不在本批范围内 |

### 0.4 两处必须交代的自身事故（诚实优先）

1. **第一次绿相位在 M-3 的子进程命令行取证处中止**：函数参数名取了 `$Pid`——PowerShell 的**只读自动变量**——运行时抛
   `Cannot overwrite variable Pid because it is read-only or constant`（日志 `run.log` 第 751 行），异常被外层 `try/catch`
   吃掉后直接进 `finally`，于是**游戏端点相位（O-5 的 g01/g02）没有跑**，当次 summary 只有 20 个探针、4 条事实。
   处置：改名为 `$ProcessId`，并在脚本里把这次事故写成注释（防止后人再犯），随后**重跑了红与绿两套**（各 25 探针 / 8 事实）。
   当次中止留下过一个游戏子进程（编辑器被杀后它自行退出）；收工时用 `Get-CimInstance Win32_Process -Filter "Name like '%godot%'"`
   复查：**没有任何残留引擎进程**，9877 的守卫判定仍为 pass【实测】。
2. **第一次绿相位的门③有 4 个用例失败 / 5 条断言失败**（日志 `gate3_first_attempt_failures.log`）：
   - 3 条来自 **TASK-050 的 N-7/N-2 用例**：O-4 让 `events[].items` 存在之后，TASK-050 的「建议文本」生成器**合法地**派生出
     更准确的新句子（这正是 O-4 的收益），旧期望值因此失效——按「受影响就改调用点、不得放松断言」处置（§9.1）；
   - 1 条是**我实现里的真缺陷**：C-3 的「前向引用」拒绝把说明文字放进了 `errors[].reason`（第 7 个参数）而没放进线上 `message`
     （第 9 个参数），所以调用方看到的 `message` 里没有那句话；
   - 1 条是**我测试里的真缺陷**：`editor_simulate_input_sequence` 的注册是**生成的 C++ 字面量**（`int` 默认值是 `INT`），
     而契约文本里的 `1` 经 `JSON::parse` 是 `FLOAT`，直接比 `canonical()` 必然不等（§7.4）。
   两处都改掉后门③转绿（307/307）。**这条 red→green 是真实的**，我不把它包装成「先写测试」的 TDD 形态：schema 类断言
   是随改动一起落地的，它们的「红」由**改动前二进制上的线上证据**给出（§2.1 的 facts）。

---

## 1. 逐条复测（D86）：改动前的二进制上，五条都还在

红相位用**改动前的二进制**（`git stash` 本批改动 → `build_local.cmd -Force` → 跑证据 → `git stash pop` → 重建），
因此红绿两套是**同一 HEAD 源码的两个二进制**，逐行可比。25 个探针的红相位结果（`evidence/task051/red/summary.json`，
sha256 `8b90051f427d3d6a8798298945f64e48303dc243eb52fe8a19f2de9be38ee137`）：

| # | 探针 | 红（改动前） | 判定 |
|---|---|---|---|
| 1 | `e08_c3_default_mode_refuses`（同批父子，默认模式） | `-32001`，`nodes[1]: parent 'P1' not found`，`batch_status=rolled_back` | **C-3 confirmed**（审计 §4.3 的原文复现） |
| 2 | `e09_c3_same_batch_parent`（带 `resolve_within_batch`） | `-32602 Unknown parameter 'resolve_within_batch' … Accepted parameters: nodes` | 参数不存在 |
| 3 | `e02_o9_default_scope`（默认） | `count=59`，**59/59 条 method 含 `::`**，响应 **12 412 B** | **O-9 confirmed**（审计的 60/60 与 12 659 B 在本锚点是 59/59 与 12 412 B，差异来自 scratch 场景与编辑器版本，不影响结论） |
| 4 | `e03/e04/e07`（`scope`） | `-32602 Unknown parameter 'scope'` | 参数不存在 |
| 5 | `e15_o4_events_missing_type` | `-32602 Missing required parameter: events[0].type`，建议原文：**「the schema declares 'events' as an array with no item shape, so no accepted member value can be derived from it」** | **O-4 confirmed**（连 TASK-050 的建议生成器都在替 schema 说出这个缺口） |
| 6 | facts：`running_game_run_test_scenario` 的 `steps.items.properties` | `action,expected,keycode,node_path,operator,property,seconds,text,type`（**9 个**，无 `pressed`/`strength`） | **O-5 confirmed**（声明缺项） |
| 7 | facts：`editor_simulate_input_sequence` 的 `events` | `events_items=''`（无 `items`） | **O-4 confirmed** |
| 8 | facts：`editor_play_scene` 的 `top_properties` | `mcp_port,mode`（无 `headless`/`extra_args`） | **M-3 confirmed** |
| 9 | `e17/e18/e19/e20/e22`（M-3） | 全部 `-32602 Unknown parameter(s) headless, extra_args` | **M-3 confirmed** |
| 10 | `g01/g02`（O-5 的 `pressed`/`strength` 调用） | `code=0`（**行为一直在，缺的只是声明**） | 与 O-5 的定性一致 |

> 基线数值：O-9 的默认答案是 **59 条 / 12 412 B**，其中 `ScriptEditor::*` 30 条、`SceneTreeEditor::*` 24 条、
> `Viewport::*` 2 条、`Control::*` 2 条、`Label::*` 1 条，**user 0 条**（用 `python` 直接统计保存下来的响应体得出）。
> 「5 节点小场景就 60/60 条」在**本锚点这就是 59/59**——数字随场景与编辑器版本浮动，结论（只有 `method` 能区分）不变。

---

## 2. 红 / 绿（TDD）

### 2.1 红：两把尺子

* **线上尺子**（§1，25 个真实请求，改动前二进制）；
* **doctest 尺子**：第一次绿相位的 4 个失败用例（§0.4 第 2 条），其中 2 条是**本批新断言的**红（C-3 前向引用文案、
  schema 逐字比对），2 条是 TASK-050 期望值必须随之更新。

### 2.2 绿

* 门③ `307/307` 用例、`22 536/22 536` 断言全绿（`gate3_module_doctests.log`）；
* 线上：25 个探针（`evidence/task051/green/summary.json`，sha256
  `05dc137eb1c66354047863ae249918c13965fe3ede43419227872e4483eb0e8a`），8 条事实；
* **红绿逐行对照**（`evidence/task051/task051-red-green-comparison.txt`）：25 行里**只有 5 行的 `message` 与 `suggestion` 都没动**
  （`e01_open_scene`、`e08_c3_default_mode_refuses`、`e16_o4_events_with_type`、`g01`/`g02`）；其余每一行的变化都在 §3–§6 逐条解释。
  其中 `e08_c3_default_mode_refuses`（默认模式拒绝）**码、文案、字节数 588 B 全部逐字未动**——这是「默认语义不变」的硬证据。
  `e15_o4_events_missing_type` 的 `message` 未动而 `suggestion` 变了——那正是 O-4 的收益（§5.1）。

---

## 3. C-3：`editor_add_nodes_batch` 支持同批父子（`resolve_within_batch`）

### 3.1 形状

新增**可选布尔** `resolve_within_batch`（`default: false`）：

> 为 true 时元素的 parent_path 可以指向**本批更早的元素**所创建的节点（同一个请求里建父子树）。父元素必须排在子元素之前，
> 父路径指向更后面的元素会被拒绝（父/子循环在按数组顺序应用时就是这个形状）；同一父节点下、同一批内重名会被拒绝
> （默认 false 时保留引擎自己的重命名）——两种拒绝都仍然整批回滚。默认 false：父路径只按调用到达时的场景树解析，
> 与旧行为逐字相同。响应在每个 created 元素上给出 parent_source（scene/batch），说明父节点来自场景树还是本批

**为什么是「新增参数」而不是改掉旧行为**：`find_node()` 在构造前解析父路径是**既有的事务语义**（全批回滚的前提是
「不构造任何孤儿」），改成默认允许同批引用会改变**所有既有调用**的含义；审计 §4.3 给的兼容方案就是默认关闭。

### 3.2 实现落点

* `_pending_path_for(parent_relative, name)`：把**原本内联在准备阶段**的路径表达式抽成一个函数（逐字等价：
  `/.` → 名字；有名字 → `父/名字`；无名 → 父路径），使「未挂载节点的路径」只有一份定义；
* `_resolve_batch_parent(...)`：**先问场景树**（`find_node`，默认模式下就是原来那一行），**再问本批已准备的节点**
  （仅 `resolve_within_batch`；未挂载节点问不了引擎，所以用它自己的 `pending_path`）；也接受 `find_node` 认的
  `Root/P1` 拼写；
* `_later_element_requesting(...)`：只用于**改善拒绝文案**——把「没有这个节点」与「你的父在数组后面」分开，
  因为两者的修法相反；这也正是父/子循环的形状（批按数组顺序应用、只向后看）；
* 重复路径：同批内两个元素会得到同一个 `pending_path` 时**明确拒绝**（默认模式仍保留引擎重命名）。

### 3.3 实测（绿相位原文）

成功（`e09_c3_same_batch_parent`，一个请求）：
```json
{"count":2,"created":[
  {"index":0,"name":"P1","node_path":"P1","parent_path":".","parent_source":"scene","type":"Node2D"},
  {"index":1,"name":"C1","node_path":"P1/C1","parent_path":"P1","parent_source":"batch","type":"Node2D"}],
 "errors":[],"resolve_within_batch":true,"status":"ok"}
```
**跨工具链**（门②要求的端到端活证据）：`e10_c3_chain_get_scene_tree` 的树里真的出现
`{"name":"P1","path":"P1",…,"children":[{"name":"C1","path":"P1/C1",…}]}`；`e11_c3_chain_get_properties`
用**批自己回报的路径** `P1/C1` 读回 `{"node_path":"P1/C1","properties":{"name":"C1"},"type":"Node2D"}`
（红相位这一步是 `-32001 Node 'P1/C1' not found`）。

三条明确拒绝（绿）：

| 探针 | 码 | 线上 message（原文） | suggestion（原文，节选） |
|---|---|---|---|
| `e12` 前向引用 | `-32001` | `nodes[0]: parent 'P9' is created later in this batch (nodes[1]) not found` | `Put the parent element before the child in 'nodes' (the batch is applied in array order), or split the request into two editor_add_nodes_batch calls; a parent/child cycle looks exactly like a forward reference here` |
| `e13` 同批重名 | `-32602` | `nodes[1]: 'D1' is already created by nodes[0] of this batch, so a reference to it would be ambiguous` | `Give every element of one parent's children a distinct 'name' (the engine would otherwise rename the second node), or split …` |
| `e14` 无人提供的父 | `-32001` | `nodes[0]: parent 'NoSuchParentXYZ' not found` | 与旧文案相同（`all-or-nothing` 那段） |

三条都带 `batch_status=rolled_back`，且 `e12` 的 `rolled_back` 为空（尚未构造任何节点）、`e13` 回滚了已准备的元素。
**失败仍全批回滚**这一既有语义未被改动。默认模式：`e08` 与红相位**逐字相同**（码/文案/字节 588 B）。

---

## 4. O-9：`editor_list_signal_connections` 的 `scope`

### 4.1 定名与理由（任务书把命名留给执行者）

**`scope`，取值 `all` / `user` / `internal`，默认 `all`。**理由：

1. **它用模块自己的词汇**：`docs/tool-rename-map.json` 里每个工具都声明 `channel/verb/scope/mutating`，
   `scope` 在这个项目里已经是「口径/作用范围」的意思，不是新造词；
2. **枚举比否定式布尔顺手**：`exclude_editor_internal: bool` 只能表达「去掉哪一半」，调用方还得自己推断「剩下的是什么」，
   而调试编辑器自身接线的人要的恰恰是**另一半**；`all|user|internal` 让两侧都能直接说出来；
3. **默认 `all` = 旧答案**：没有任何既有调用需要改，合约描述里的判别点（`node_path`/`signal_name` 子串、收全部连接）
   也一字未动。

### 4.2 判别口径：`method` 的拼写，而不是 `source`

审计的关键实测是「内部连接的 `source` 也是普通场景节点路径」，所以 `node_path` 过滤不掉它们；唯一可区分的是
`Object::Connection.callable.get_method()`。引擎对 **MethodBind 型** `Callable` 的拼写是 `Class::method`
（`ScriptEditor::_queue_update_list`），而 GDScript/C# 的方法名**不可能含 `::`**。于是：

* `internal` = `method` 含 `::`；`user` = 其余；`all` = 全部。
* **一个必须写清的边界**：场景自己用 `Callable(target, "queue_free")` 连的**原生方法**拼写是 `queue_free`，因此判为 `user`——
  这是对的（它是场景连线），但也说明判别的是**连线的来源拼写**而不是「方法属于谁」。这条已用 doctest 钉死。

### 4.3 实测：默认 vs 收窄（同一场景、同一进程）

同一个 5 节点 scratch 场景（未保存、无用户连线），响应体字节数取自落盘文件：

| 请求 | 红（改动前） | 绿 | 说明 |
|---|---|---|---|
| `{}`（默认） | `count=59`，**12 412 B** | `count=59`，**12 481 B** | **连接数组逐元素相同**（`mcp051_wire_verbatim_check.py`：`identical=True`）；多出的 69 B = 新增的 `counts` + `scope` 两个键 |
| `{"scope":"user"}` | `-32602`（未知参数） | `count=0`，**178 B**，`counts={"all":59,"internal":59,"user":0}` | 一个用户连线都没有——**旧接口让调用方拿不到这个事实** |
| `{"scope":"internal"}` | `-32602` | `count=59`，**12 486 B** | 与 `all` 同数（此场景全是内部连接），字节差 5 = `"internal"` 比 `"all"` 多 5 个字符 |
| `{"signal_name":"script_changed"}` | `count=15`，3 113 B | `count=15`，**3 182 B** | `signal_name` **仍是子串过滤**（未改），连接数组逐元素相同 |
| `{"scope":"user","signal_name":"script_changed"}` | `-32602` | `count=0`，178 B，`counts={"all":15,"internal":15,"user":0}` | 证明「单靠 `signal_name` 过滤不掉内部连接，`scope` 可以」 |
| `{"scope":"scene"}` | `-32602`（未知参数） | `-32602`：`Parameter 'scope' is 'scene'; the accepted values are 'all' …'user'…'internal'` | 封闭词表，且**在编辑器守卫之前**判定（本进程非编辑器也答 `-32602`） |

> **`signal_name` 保持子串匹配——这是本批最需要决策者复核的一处解读**：任务书写「保留 `signal_name` 精确过滤」，
> 我按「保留既有的 `signal_name` 过滤能力」理解并**一字未改语义**。理由：该子串行为写在**冻结的契约描述**里
> （「node_path 与 signal_name 均按子串匹配」），并且是它与 `editor_analyze_signal_flow`（精确 `node_path`、只收持久连接）
> 之间的 **GDR-17 / R-1 判别点**；改成精确匹配会同时打破契约文案与这条判别点。若决策者的本意是「改成精确匹配」，
> 那是一条**独立的契约改动**，需要单独裁决与单独的结构化 diff。

### 4.4 一个被明确声明的响应增加

`editor_list_signal_connections` 的**成功响应**新增两个键：`counts`（**未过滤**口径的 `{all,user,internal}` 条数）与
`scope`（本次口径）。用途：调用方问 `user` 时仍能立刻看到「同一请求下有多少条内部接线被隐藏」——这正是 O-9 要解决的问题。
代价是**默认响应的字节数从 12 412 → 12 481（+69）**，已如上表给出前后对照。**连接数组本身逐元素未动**（机器检查见 §7.5）。

---

## 5. O-4 / O-5：补 schema 缺项（只改声明，不改行为）

### 5.1 O-4 `editor_simulate_input_sequence.events[].items`

照实现的读取路径写（`editor_input_simulation.cpp:843-971`），17 个成员：`type`（**必填**，enum
`key|mouse_click|mouse_button|mouse_move|mouse_motion|action`）、`keycode`、`pressed`（默认 true）、`shift`/`ctrl`/`alt`、
`action`、`strength`、`button`（默认 1）、`x`/`y`/`position`、`relative`/`relative_x`/`relative_y`/`button_mask`、
`time_ms`（**明确声明被忽略**，只在响应的 `time_ms_ignored` 里体现）。`items.required = ["type"]`，
并把可粘贴样例放进 `items.description`。

**收益当场可见**（同一个请求的**建议文本**，红→绿）：

```
红：Missing required parameter 'events[0].type': the schema declares 'events' as an array with no item shape,
    so no accepted member value can be derived from it; Accepted parameters of …: events, frame_delay
绿：Missing required parameter 'events[0].type' (a string, one of: key|mouse_click|mouse_button|mouse_move|mouse_motion|action);
    Accepted parameters of …: events, frame_delay
```
线上 `facts`：`events_items` 由 **空** 变为
`action,alt,button,button_mask,ctrl,keycode,position,pressed,relative,relative_x,relative_y,shift,strength,time_ms,type,x,y`。

**行为未改**：`e15` 两个相位的 `message` 都是 `Missing required parameter: events[0].type`（走的是 handler 自己的
`events[0].type` 路径定位，不是新校验层）；`e16` 两个相位都是 `code=0` 且响应 **202 B 逐字相同**。

### 5.2 O-5 `running_game_run_test_scenario.steps[].pressed` / `.strength`

`steps.items.properties` 由 **9 个** 增至 **11 个**（新增 `pressed`（bool，默认 true）与 `strength`（number，默认 1.0）；
两者只对 `type=input` 有意义，描述里写清）。线上 `facts` 的变化即证据；`g01`/`g02`（带 `pressed:true` / `pressed:false`）
红绿两个相位都 `code=0`、响应 **256 B / 257 B 逐字相同**——**行为一直在，本批只是把能力写进声明**。

### 5.3 本批**不**处理的两件事（诚实声明）

1. `running_game_play_input_recording` 的 `events` 也是裸数组（审计 §5.4 同时点名了两处），但**任务书 O-4 只点名
   `editor_simulate_input_sequence`**，我没有顺手扩大范围；若要做，需要先确认「录制事件」的元素形状（含 `time_ms` 语义），
   属于独立裁决。
2. 注册表的未知参数检查**只看顶层**，所以 `items` 是**声明与文档，不是新的校验层**：嵌套成员的类型仍由各 handler 判定。
   这与审计 §5.5 的观察一致，也写进了本批的契约 reason。

---

## 6. M-3：`editor_play_scene` 的 `headless` / `extra_args`

### 6.1 两条新参数

| 参数 | 类型/默认 | 契约描述（原文节选） |
|---|---|---|
| `headless` | `boolean` / `false` | 以 headless 模式启动游戏子进程（给子进程加一个 `--headless`，即引擎自己的"无音频、无渲染"别名）；默认 false，与旧行为逐字一致。注意 `--headless` 不会从编辑器继承（引擎的可转发参数表里没有它），所以在无显示环境里必须显式传 true |
| `extra_args` | `array` of `string` / `[]` | 追加到游戏子进程命令行的额外参数（逐字追加，排在引擎自己构造的 `--path/--remote-debug/--editor-pid/--scene` 与固定注入的 `--mcp-port=<端口>` 之后，所以同名参数以这里的为准）；**不得包含 `--mcp-port`**（端口只由 `mcp_port` 参数注入：引擎的命令行解析取最后一次出现，重复注入会让响应里的 endpoint 指向游戏并未监听的端口，故被明确拒绝）；重复的 `--headless` 会被去重并在响应的 `args_deduplicated` 里列出；每个元素必须是非空字符串 |

### 6.2 与 E-10 端口注入的兼容（**去重 vs 拒绝**，两件事分开）

* `--mcp-port`：**拒绝**（`-32602`），不是静默去重。理由：`MCPPort::parse`（`mcp_server.cpp:75-92`）取**最后一次**
  出现，若把调用方的端口追加在后面，它就会生效，而响应的 `endpoint` 仍在说另一个端口——**答案会撒谎**。
  端口只有一个来源（`mcp_port`），拒绝是「兼容」的诚实形态。两种拼写（`--mcp-port=9889` 与裸 `--mcp-port`）都拒。
* `--headless`：**去重并回报**。它是幂等 token，丢掉重复不改变子进程，但**必须让调用方知道哪一条没进命令行**，
  所以响应用 `args_deduplicated` 列出被丢掉的拼写（而不是让调用方去比对命令行）。

### 6.3 实测（绿相位原文）

`e20`：`{"mode":"main","mcp_port":9889,"headless":true,"extra_args":["--verbose"]}` →
```json
{"args_deduplicated":[],"args_injected":["--mcp-port=9889","--headless","--verbose"],
 "endpoint":"http://127.0.0.1:9889/mcp","headless":true,"mcp_port":9889,"mcp_port_source":"argument",
 "mode":"main","pid":83576,"playing":true}
```
子进程**自己的命令行**（`Get-CimInstance Win32_Process`，不是工具的自述）：
```
…\godot.windows.editor.x86_64.exe --path C:/…/mcp051/scratch/editor --remote-debug tcp://127.0.0.1:6007
  --editor-pid 80344 --scene res://scenes/main.tscn "--mcp-port=9889" --headless --verbose
```
→ `mcp_port_occurrences = 1`、`headless_occurrences = 1`。**游戏端点可用**：直接 `curl 9889/mcp` 得
`is_editor=false, listening=true, tools=69`（196 B，sha256 `faf586ca…`）。`e21` `editor_stop_scene` → `{"stopped":true}`。

`e22`（`headless:true` + `extra_args:["--headless"]`，去重探针）：
```json
{"args_deduplicated":["--headless"],"args_injected":["--mcp-port=9889","--headless"],…}
```
子进程命令行仍是 `mcp_port_occurrences=1`、`headless_occurrences=1`（`pid=60788`）；`e23` 停止成功。

拒绝：`e17`（`headless:"yes"`）`-32602 Parameter 'headless' must be a boolean, got String`；
`e19`（`extra_args:7`）`-32602 … must be an array of strings, got float`；
`e18`（`extra_args:["--mcp-port=9889"]`）`-32602` + 上面那段「端口只有一个来源」的说明。
三个都是**顶层形状**，在编辑器守卫之前判定（本进程非编辑器也答 `-32602`）；`extra_args` 的**元素级**规则与参数表构造
在一起（与 `editor_add_nodes_batch` 对 `nodes[i]` 的分工一致），这条分工写进了源码注释。

**默认行为不变**：不传两个新参数时 `build_play_args(p, false, [], …)` 返回**恰好一个** `--mcp-port=<port>`
（doctest 钉死），且 `e08` 类默认探针在红绿两侧逐字相同。响应新增 `headless` / `args_injected` / `args_deduplicated`
三个键（**声明的增加**：把「子进程到底收到什么」变成可读回的事实，省掉一次进程取证）。
**没有**用非 headless 起子进程做默认探针：那会在用户桌面上闪一个窗口，默认参数表已由纯函数 doctest 精确钉死。

---

## 7. 契约机制（任务书 §0）

### 7.1 五条 `SCHEMA_OVERRIDES`，全部 `mode=replace`，理由逐字引用被替换成员

`gen_renamed_contract.py` 的 v1.5 守卫要求 `mode=replace` 的 `reason` **逐字引用被替换的成员**；五条各自引用的原文是：

| old_name（工具） | 理由里引用的被替换成员（逐字） | 实际动作 |
|---|---|---|
| `batch_add_nodes` | `["nodes"]` | 保留该 `required`，只新增 `resolve_within_batch` |
| `find_signal_connections` | `[]` | 保留空 `required`，只新增 `scope` |
| `simulate_sequence` | `["events"]` | 保留该 `required`，`events` 的 `type: array` 不变，只补 `items` |
| `run_test_scenario` | `["steps"]` | 保留该 `required`，只新增两个 steps 成员 |
| `play_scene` | `[]` | 保留空 `required`，`mode`/`mcp_port` 逐字保留，只新增 `headless`/`extra_args` |

`play_scene` 复用**已有的那条** E-10 override（一个 `old_name` 只能有一条 schema override），reason 里先保留 E-10 原文，
再追加 M-3 段落并再次逐字引用 `[]`。

### 7.2 版本与重生成

* `GENERATOR_VERSION` **1.12.0 → 1.13.0**；
* `python modules\mcp_server\scripts\gen_renamed_contract.py` 运行**两次**，输出 sha 相同
  （`c92b9fd2f93905fbf1a260a740fbbb19ffc0e3d6858165c0d47b0488f508d6d5`），171 条，overrides 28，
  脚本自检 `lint 171/171, unique 171/171, disposition enum OK`；
* **契约文件从未手改**；C++ 侧字面量同样机械同步：
  `gen_b2_game_schema.py --in-place` 重生成三段生成段（`editor_playback.cpp` / `editor_input_simulation.cpp` /
  `running_game_test_execution.cpp`），两个手写 `_schema_from_json` 字面量（`editor_node_read.cpp` /
  `editor_node_batch_write.cpp`）由一个临时脚本**按契约 JSON 生成**后替换（不是手敲中文 JSON），
  doctest 里内嵌的 5 个字面量同理由脚本同步。

### 7.3 结构化 diff（`scripts/mcp051_contract_diff.py`，exit 0）

```
changed tools = editor_add_nodes_batch, editor_list_signal_connections, editor_play_scene,
                editor_simulate_input_sequence, running_game_run_test_scenario
  editor_add_nodes_batch: +3 member(s)      editor_list_signal_connections: +6 member(s)
  editor_play_scene: +7 member(s)           editor_simulate_input_sequence: +53 member(s)
  running_game_run_test_scenario: +6 member(s)
meta keys moved = generator_version, overrides        overrides 24 -> 28
problems = 0
```
断言内容（都是机器检查，不是叙述）：

1. 工具名集合与条数**不变**（171）；
2. 变化的**恰好这 5 条**，且每条**只动 `inputSchema`**（`description` 一个字节没动）；
3. 每条都是**纯新增**：把新旧 schema 展平成 `path -> value`，**旧成员全部在且值相同**，**新成员全部落在该工具允许的前缀里**
   （`/properties/resolve_within_batch`、`/properties/scope`、`/properties/events/items`、
   `/properties/steps/items/properties/pressed|strength`、`/properties/headless`、`/properties/extra_args`）；
4. `_meta` 只动 `generator_version`（1.12.0→1.13.0）与 `overrides`（24→28）；`map_sha256` 与 `generated_from_sha256`
   未动；**变化的 override 记录恰好是这 5 条 `inputSchema`**（`play_scene` 那条 description 记录逐字未动）。

### 7.4 门① 的逐字面（两条腿）

* **实跑门①**：`scripts/check_contract_subset.ps1` 按 5 个受影响组各跑一次（`mcp051_gate1_groups.ps1`），
  5 次都是 **exit 0 / 3/3 checks passed**，日志里这 5 条工具各出现 `name=True description=True inputSchema=True`；
  另跑一次默认组，并集断言 **148（编辑器）/ 69（游戏）** 与旧构建逐字相同（`green/gate1_union.log`）；
* **保存体上的复核**：`scripts/mcp051_wire_verbatim_check.py` 从**保存下来的** `tools/list` 响应里对 5 条工具做
  递归排序键的 JSON 比对 → **全部 `inputSchema=True description=True`**（editor 50 350 B / game 25 369 B），
  且编辑器独有的 4 条在游戏端点上**按 scope 缺席**。

> 一处**实现与测试的诚实说明**：生成段的注册是手搓 `Dictionary`（Python `int` 默认值 → Godot `INT`），而契约文本里的 `1`
> 经 JSON 解析是 `FLOAT`；线上两者都渲染成 `1`（门①就是照着 JSON 文本比的），所以 doctest 里做 schema 逐字比对时，
> **两边都先过一遍 `JSON::stringify`→`JSON::parse`**。这不是放松断言——它比的是「两个端点真正提供的那个 JSON 对象」。

### 7.5 默认答案没动的机器检查

`mcp051_wire_verbatim_check.py` 还断言：O-9 默认请求与 `signal_name` 请求的 `connections[]` 数组在红（改动前二进制）
与绿之间**逐元素相同**（`identical=True`，59 与 15 条），并打印绿侧新增的 `counts`/`scope`。→ **收窄没有顺手动过既有答案。**

---

## 8. 门（五道 + 门⑥ 三段式）

| 门 | 命令 | 结果 |
|---|---|---|
| ① 契约子集逐字 | `check_contract_subset.ps1`（5 组各一次 + 默认组并集） | **6 次全部 exit 0**；5 条工具 `inputSchema=True`；并集 148/69 不变 |
| ② 三类证据 | `mcp051_b_tier_evidence.ps1 -Label red/green`（25 请求 ×2 + `tools/list` ×2） | 红 25/25、绿 25/25；**跨工具链**：开场景 → 一个请求建父子 → 读回树 → 用批回报的路径读回属性（§3.3） |
| ③ 模块 doctest | `--headless --test --test-case="[MCPServer]*"` | **307 / 307 用例、22 536 / 22 536 断言、0 failed**（`gate3_module_doctests.log`） |
| ④ 全引擎回归 | `--headless --test` | **1733 / 1733 用例、446 818 / 446 818 断言、0 failed、3 skipped**（`gate4_full_engine_tests.log`） |
| ⑤ 批收口 | `accept_m1.ps1` 连跑两次 | **两次都 22/22 PASS，两次 PASS 清单逐行一致**（`gate5a`/`gate5b`） |
| ⑥ 收窄点清单 | `check_narrowing_points.py` / `--coverage` / `mcp031_gate6_coverage_probes.ps1` | **exit 0 / exit 0 / 101/101**；`scanned 75, pinned 75`，覆盖集合 **17 种拼写** |

**门⑥ 的三段式（§22.3b 规则 4 要求的「新增点 × 闸门 × 证据」）**：本批**没有新增也没有修改任何收窄代码**——
新增的三处代码路径（批内父路径解析、连接范围过滤、子进程参数表构造）**不含 `real_t`/`float`/`Color(`/`Vector2(`/
`Vector3(`/`Vector4(` 任何拼写，也没有任何数值转换或槽位写入**；`scanned 75 / pinned 75` 与本批改动前一致，
门⑥ 的机器检查与 101 个「插入即 exit 1」探针都通过。因此按规则 4 没有「新增点」需要逐条列出；
按规则 2/7，本批的正确性也不依赖门⑥ 单独作证（见 §9 的逐条归因与线上证据）。

**契约自身的静态门**：`docs/scripts/check_rename_map.py`、`check_tool_groups.py` 均 exit 0；结构化 diff exit 0。

**收工一致性检查**（`scripts/mcp051_final_sweep.py`，exit 0，`green/final-sweep.txt`）：二进制不比任何 `tools/**`、`tests/**`
源文件旧（唯一 mtime 更新的 `tools/running_game_read_scene.cpp` **内容与 HEAD 逐字节相同**——门⑥ 的探针脚本写回它、
自带 `B1b_restored_byte_identical` 检查）；4 个新脚本纯 ASCII；契约重生成**幂等**；三段生成段重跑都是
`already up to date`（即「C++ 字面量就是契约」不是意图而是可复算的事实，与门① 的线上逐字互为两条腿）。

---

## 9. 回归批次（严格串行、逐条归因）

三个批次全部 exit 0（`docs/reports/evidence/task051/green/regression/summary-*.txt`）：

| 批次 | 步骤（退出码） |
|---|---|
| `individual` | `mcp031_gate6_coverage_probes` 0（52 s）、`mcp010_b2_observation` 0（34 s）、`mcp019_b4` 0（25 s）、`mcp027_object_shape_and_paths` 0（24 s）、**`mcp050_parameter_guidance -Label green` 0（22 s）**、**`mcp050_contract_diff` 0（0 s）** |
| `batteries` | `mcp041_gates` 0（398 s）、`mcp042_gates` 0（427 s）、`mcp043_gates` 0（504 s） |
| `capture` | `mcp044_capture` 四个相位 0（59/9/8/12 s）、`mcp045_pixel_compare_cost` 0（30 s）、`mcp046_capture_encode_cost` 0（50 s） |

### 9.1 被本批**影响且必须修改**的既有断言（3 处，都是「改调用点」，**没有放宽**）

`tests/test_mcp_server.h` 的 TASK-050 用例里，3 条**等式断言**的右值随 O-4 的新 schema 合法地变化
（建议生成器现在能派生出元素形状）：

| 位置 | 旧右值 | 新右值 |
|---|---|---|
| 缺 `events` 的建议 | `"Missing required parameter 'events' (an array); " + …` | `"Missing required parameter 'events' (an array of an object with members {action, alt, …, shift, ... (17 members in total)}, requiring {type}); " + …` |
| `events` 为空时的建议 | `"Parameter 'events' accepts an array (required); " + …` | `"Parameter 'events' accepts an array of an object with members {…17…}, requiring {type} (required); " + …` |
| 嵌套缺 `type` 的建议 | `"…: the schema declares 'events' as an array with no item shape, so no accepted member value can be derived from it; " + …` | `"Missing required parameter 'events[0].type' (a string, one of: key|mouse_click|mouse_button|mouse_move|mouse_motion|action); " + …` |

**断言形式与强度不变**（仍是与 `Task050::accepted_of(...)` 拼接后的**全等式**）；另外**新增**一条独立断言
`events_suggestion.contains("requiring {type}")`，把「派生真的读了 `items.required`」钉住——是**加强**而不是削弱。

### 9.2 被本批**影响但无需修改**的脚本（都已实跑）

* `mcp010` / `mcp019` / `mcp027`：与本批五个工具无交集，exit 0；
* `mcp041` / `mcp042` / `mcp043` gates：本批契约改动落在 5 条 `inputSchema`，这三套门比的是**工具集合与描述文案**，
  exit 0；`mcp043_gates.ps1` 的 `gate2g_contract_diff` 仍比它**自己钉死的修订对**（`806d5396b`→`47b5008bac`），
  所以本批的契约改动不会把它弄红，也不需要改它（`mcp043_contract_diff.py` 一字未动）；
* `mcp044`/`mcp045`/`mcp046`：与截图/取色路径无交集，exit 0。

### 9.3 一处**必须交代**的回归副作用（已回滚）

`mcp050_parameter_guidance_evidence.ps1 -Label green` 会**写回它自己的证据目录**
（`docs/reports/evidence/task050/green/` 下 7 个响应 + `summary.json`），因此重跑回归会**覆盖 TASK-050 的历史证据**。
处置：

1. 把重跑产生的那 8 个文件**复制**到 `docs/reports/evidence/task051/green/regression/task050-evidence-rerun/`（本批的回归证据留档）；
2. `git checkout -- modules/mcp_server/docs/reports/evidence/task050` **把 TASK-050 的历史证据恢复原样**；
3. 复核 `git status`：已跟踪改动**只剩本批那 11 个文件**。

### 9.4 一条**不纳入**回归的项（照实说明）

`mcp044_zero_change.ps1` 的 `pre` 相位需要**TASK-044 之前**的二进制（TASK-050 §7.4 已记录同一限制），
本锚点无法重建历史二进制，因此不跑、也不拿替身顶替——它与本批五个工具无任何交集。

---

## 10. 决策与偏离（供决策者复核）

1. **O-9 命名**：`scope: all|user|internal`，默认 `all`（理由见 §4.1）。
2. **O-9 响应新增 `counts`/`scope`**（默认体 +69 B）。**声明的增加**，不是静默变化；若决策者要求「默认响应逐字节不变」，
   去掉这两个键即可（连接数组与 `count` 不受影响）。
3. **`signal_name` 保持子串匹配**（§4.3 末尾的复核请求）——若本意是「改成精确匹配」，需要独立裁决。
4. **M-3 的 `--mcp-port` 用拒绝而不是静默去重**（§6.2）；`--headless` 用去重 + 回报。
5. **C-3 的严格性只在 `resolve_within_batch=true` 时生效**：默认模式的「同批重名 → 引擎重命名」行为逐字保留
   （`e08` 的证据 + 既有 doctest 仍绿）。
6. **C-3 的响应新增**：顶层 `resolve_within_batch` + 每个 `created` 元素的 `parent_source`（`scene`/`batch`）。
   后者是唯一能区分「挂到本批新节点」与「挂到场景里同名旧节点」的字段，链式调用需要它。
7. **不做的**：O-2（决策者裁定，会造出第二个序列化器，违反 GDR-25）；
   `running_game_play_input_recording` 的裸 `events`（任务书未点名，§5.3）。
8. **`extra_args` 不设「引擎自有参数」黑名单**（除端口以外）：参数表排在引擎自己的参数之后，语义是「调用方的显式愿望」；
   只有 `--mcp-port` 会让**本工具的答案说谎**，所以只有它被拒。这条已写进契约描述。
9. **决策日志**：`F:\moonbit-hof-rs\DECISIONS.md` 对本模块执行者**只读**，因此本批**没有**向它追加条目；
   以上 1–8 条即本批的决策记录，提交信息与本节一一对应。

---

## 11. 遗留风险与限制（诚实声明）

1. **红相位的二进制是「同一 HEAD 源码重建的改动前版本」**（`git stash` → 构建 → 取证 → `stash pop` → 重建），
   不是 TASK-050 当时那一份二进制；源码相同、构建参数相同（`-Force`，`tests=yes`，`mono=no`），
   但**二进制 sha 未必相同**——因此红绿对比是**源码级**的对照，不是同一份 artifact 的自比。
2. **O-9 的 59 条是场景/编辑器版本相关的量**（审计是 60 条 / 12 659 B，本锚点 59 条 / 12 412 B）。
   结论（只有 `method` 能区分内部与用户连接）在两侧都成立；数字不要当常量引用。
3. **`user`/`internal` 判别的是 callable 方法的拼写**：场景自己连原生方法（`Callable(target,"queue_free")`）算 `user`。
   一个用 `Callable` 指向编辑器内部对象的场景连线理论上会被算成 `user`；本批以「来源拼写」为准并把它写进了描述。
4. **注册表不校验嵌套成员**（`items` 是声明，不是闸门）。`time_ms` 被**声明为忽略**——这是把既有行为写进 schema，
   而不是新增「静默丢弃」（旧行为本来就忽略它，响应里也有 `time_ms_ignored`）。
5. **`extra_args` 的能力边界**：它可以覆盖引擎自己构造的参数（例如 `--path`），因为它在最后。这是「额外参数」的
   定义，但也是一个 footgun；描述里写清了顺序，没有替调用方做选择。
6. **本锚点仍是 `module_mono_enabled=no`**（与审计同一限制），C# 相关语义不在本批范围。
7. **门⑥ 的保证边界**（§22.3b）不因本批改变：本批没有新增收窄代码，`scanned/pinned = 75/75` 与本批前一致；
   未覆盖边界（运行时隐式 `double→real_t`、整数收窄、`tools/**` 之外等）仍由 `--coverage` 打印。
8. **一次脚本事故已修复并留档**（§0.4）：首轮绿相位的子进程取证用了只读的 `$Pid` 参数名导致中止；
   红绿两套已重跑，收工复查无残留引擎进程。

---

## 12. 结论（按 D86 标锚点）

在 **HEAD `588f749941dc9f357fac2ce450710b62bc11249a`**、二进制
`4.8.dev.custom_build.588f74994`（`build_local.cmd -Force`，`tests=yes`）上：

* **C-3 / O-9 / O-4 / O-5 / M-3 五条全部落地**：三条带行为（C-3 / O-9 / M-3）、两条是声明补齐（O-4 / O-5，行为在红相位即已可用）；
* **契约**：171 条不变，`_meta.generator_version` **1.12.0 → 1.13.0**，overrides **24 → 28**，
  sha256 `c92b9fd2f93905fbf1a260a740fbbb19ffc0e3d6858165c0d47b0488f508d6d5`；
  **结构化 diff 证明只动这 5 条 `inputSchema` 的纯新增成员 + `_meta` 两处**；契约文件从未手改；
* **门①–⑥ 全部通过**，门②给出了 25×2 个真实请求与一条跨工具链，门③ 307/307，门④ 1733/1733，门⑤ 22/22 ×2 一致，
  门⑥ 75/75 + 101/101；
* **回归**：`mcp041/042/043`、`mcp010/019/027`、`mcp044/045/046`、TASK-050 的证据脚本与其契约 diff **全部 exit 0**，
  唯一的既有测试改动是 TASK-050 的 3 条期望值随 O-4 的新派生文本更新（**断言未放宽，另加一条加强断言**）；
* **纪律**：已跟踪改动恰好 11 个文件、全在 `modules/mcp_server/**`；9877 全程未被占用；无 push。

**待决策者复核的三点**：§4.3 末尾的 `signal_name` 语义解读、§10.2 的 O-9 响应新增键、§10.8 的 `extra_args` 边界。

---

## 13. 提交锚点（D86）

| 提交 | 内容 |
|---|---|
| `d652a43a35` | 契约 + 生成器：`GENERATOR_VERSION` 1.13.0、5 条 `SCHEMA_OVERRIDES`、重生成的 `docs/tools_list.renamed.json` |
| `8b4a65a54f` | 实现：C-3（批内父路径）、O-9（`scope`）、M-3（`headless`/`extra_args`）+ 三个生成段同步 |
| `0408da76a9` | 测试：7 个新用例 + TASK-050 的 3 条派生文本期望值（另加一条加强断言） |
| `b34169d634` | 证据/门/回归脚本（7 个新脚本） |
| `06abd44ce4` | `REPORT-051` + 红绿与门/回归证据（`docs/reports/evidence/task051/**`） |
| 本条之后 | 仅文档勘误（本表的**代码锚点是 `06abd44ce`**：它是最后一条含代码/契约/测试/脚本的提交） |

**「--version == HEAD」的口径**（与 TASK-050 §11 同一条规则）：本批的 `--version == 06abd44ce` 是在 `06abd44ce`
这一棵树上重建后由二进制自报的；其后**只允许文档/证据改动**的提交不改变二进制，故不再要求 `--version` 追平那些提交的短 sha
（否则每改一次报告都要重建一次引擎，而这个口令要证明的是「门跑在**与被测源码一致**的二进制上」）。
红线：**任何** `tools/**`、`tests/**`、契约或生成器的改动都必须重新构建并重跑门——本批每次这样改动后都重建过（4 次）。
